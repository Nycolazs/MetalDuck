import Foundation
@preconcurrency import Metal
import Vision
@preconcurrency import CoreVideo
import os
import MetalPerformanceShaders

/// Async optical flow provider using Apple's Vision framework.
/// Runs VNGenerateOpticalFlowRequest on the ANE/GPU via a dedicated queue.
/// The frame pipeline submits frame pairs and queries the latest available result.
/// Async optical flow provider leveraging Apple's Vision framework (VNGenerateOpticalFlowRequest).
/// Computes motion vectors on the ANE or GPU to enable accurate frame interpolation.
final class VisionFlowProvider: @unchecked Sendable {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let flowQueue = DispatchQueue(label: "com.metalduck.visionflow", qos: .userInitiated)
    private var textureCache: CVMetalTextureCache?
    private let scaler: MPSImageBilinearScale

    // Latest computed flow pair (protected by lock)
    private var lock = os_unfair_lock()
    private var _forwardFlow: MTLTexture?
    private var _backwardFlow: MTLTexture?
    private var _flowFrameID: UInt64 = 0
    private var isComputing = false
    private var totalSubmitted: UInt64 = 0
    private var totalCompleted: UInt64 = 0
    private var totalFailed: UInt64 = 0
    private var latestFlowCallCount: UInt64 = 0

    struct FlowResult {
        let forward: MTLTexture
        let backward: MTLTexture
        let frameID: UInt64
    }

    init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
        self.scaler = MPSImageBilinearScale(device: device)

        // Setup texture cache for zero-copy CVPixelBuffer to MTLTexture conversions
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        if status != kCVReturnSuccess {
            NSLog("VisionFlowProvider: Error creating texture cache (status = %d)", status)
        }
        
        NSLog("VisionFlowProvider: Initialized with device %@", device.name)
    }

    /// Returns the latest computed flow pair, or nil if not yet available.
    func latestFlow() -> FlowResult? {
        os_unfair_lock_lock(&lock)
        latestFlowCallCount += 1
        let callNum = latestFlowCallCount
        let hasFwd = _forwardFlow != nil
        let hasBwd = _backwardFlow != nil
        let fid = _flowFrameID
        guard let fwd = _forwardFlow, let bwd = _backwardFlow else {
            os_unfair_lock_unlock(&lock)
            if callNum % 120 == 1 {  // Log every 120th call (~1 per second at 120Hz)
                NSLog("VisionFlowProvider: latestFlow() -> nil (hasFwd=%d hasBwd=%d frameID=%llu call#%llu)",
                      hasFwd ? 1 : 0, hasBwd ? 1 : 0, fid, callNum)
            }
            return nil
        }
        os_unfair_lock_unlock(&lock)
        if callNum % 120 == 1 {
            NSLog("VisionFlowProvider: latestFlow() -> VALID (fwd=%dx%d bwd=%dx%d frameID=%llu)",
                  fwd.width, fwd.height, bwd.width, bwd.height, fid)
        }
        return FlowResult(forward: fwd, backward: bwd, frameID: fid)
    }

    /// Submit a frame pair for async flow computation (non-blocking).
    func submitFlowRequest(prev: MTLTexture, next: MTLTexture, frameID: UInt64) {
        os_unfair_lock_lock(&lock)
        let alreadyComputing = isComputing
        if !alreadyComputing {
            isComputing = true
        }
        totalSubmitted += 1
        let submitted = totalSubmitted
        os_unfair_lock_unlock(&lock)

        // Skip if already computing — we'll pick up the next frame
        if alreadyComputing {
            return
        }

        NSLog("VisionFlowProvider: Starting flow #%llu (prev=%dx%d next=%dx%d)",
              submitted, prev.width, prev.height, next.width, next.height)

        // Create pixel buffers and copy texture data to them using a managed texture readback
        let width = prev.width
        let height = prev.height

        // Run Vision flow async on dedicated queue
        flowQueue.async { [weak self] in
            guard let self = self else { return }
            defer {
                os_unfair_lock_lock(&self.lock)
                self.isComputing = false
                os_unfair_lock_unlock(&self.lock)
            }

            guard let prevPB = self.readTextureToPixelBuffer(prev),
                  let nextPB = self.readTextureToPixelBuffer(next) else {
                NSLog("VisionFlowProvider: FAILED to read textures to pixel buffers")
                os_unfair_lock_lock(&self.lock)
                self.totalFailed += 1
                os_unfair_lock_unlock(&self.lock)
                return
            }

            NSLog("VisionFlowProvider: Pixel buffers created (%dx%d), dispatching Vision flow", width, height)

            // Forward flow: prev → next
            let forwardFlow = self.runVisionFlow(source: prevPB, target: nextPB, width: width, height: height)
            // Backward flow: next → prev
            let backwardFlow = self.runVisionFlow(source: nextPB, target: prevPB, width: width, height: height)

            guard let fwd = forwardFlow, let bwd = backwardFlow else {
                os_unfair_lock_lock(&self.lock)
                self.totalFailed += 1
                let failed = self.totalFailed
                os_unfair_lock_unlock(&self.lock)
                NSLog("VisionFlowProvider: Flow computation FAILED (total failures: %llu)", failed)
                return
            }

            // Store results
            os_unfair_lock_lock(&self.lock)
            self._forwardFlow = fwd
            self._backwardFlow = bwd
            self._flowFrameID = frameID
            self.totalCompleted += 1
            let completed = self.totalCompleted
            os_unfair_lock_unlock(&self.lock)
            NSLog("VisionFlowProvider: Flow #%llu COMPLETED (fwd=%dx%d bwd=%dx%d, total completed: %llu)",
                  frameID, fwd.width, fwd.height, bwd.width, bwd.height, completed)
        }
    }

    func reset() {
        os_unfair_lock_lock(&lock)
        _forwardFlow = nil
        _backwardFlow = nil
        _flowFrameID = 0
        os_unfair_lock_unlock(&lock)
    }

    // MARK: - Private

    /// Reads a GPU texture to a CVPixelBuffer using a managed intermediate texture.
    /// This works correctly even with `.private` storage mode textures from ScreenCaptureKit.
    private func readTextureToPixelBuffer(_ texture: MTLTexture) -> CVPixelBuffer? {
        // Increased from 640 to 1280 to handle large displacements in 24fps Anime
        let maxDimension = 1280.0
        let scale = min(1.0, maxDimension / Double(max(texture.width, texture.height)))
        let width = max(1, Int(Double(texture.width) * scale))
        let height = max(1, Int(Double(texture.height) * scale))

        // Create a managed (CPU-accessible) intermediate texture
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        #if os(macOS)
        desc.storageMode = .managed
        #else
        desc.storageMode = .shared
        #endif

        guard let managedTex = device.makeTexture(descriptor: desc),
              let cmdBuf = commandQueue.makeCommandBuffer() else {
            NSLog("VisionFlowProvider: Failed to create managed texture or command buffer")
            return nil
        }

        // Scale and copy from private GPU texture to managed texture directly on GPU
        scaler.encode(commandBuffer: cmdBuf, sourceTexture: texture, destinationTexture: managedTex)

        #if os(macOS)
        guard let blit = cmdBuf.makeBlitCommandEncoder() else { return nil }
        blit.synchronize(resource: managedTex)
        blit.endEncoding()
        #endif

        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        // Now read managed texture data into a CVPixelBuffer
        guard let pb = createPixelBuffer(width: width, height: height) else {
            NSLog("VisionFlowProvider: Failed to create CVPixelBuffer")
            return nil
        }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pb) else {
            NSLog("VisionFlowProvider: Failed to get pixel buffer base address")
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        managedTex.getBytes(baseAddress, bytesPerRow: bytesPerRow,
                           from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                           size: MTLSize(width: width, height: height, depth: 1)),
                           mipmapLevel: 0)

        return pb
    }

    private func runVisionFlow(source: CVPixelBuffer, target: CVPixelBuffer,
                               width: Int, height: Int) -> MTLTexture? {
        let request = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: target)
        // Upgraded to .high to better track large pixel displacements (e.g. low FPS anime)
        request.computationAccuracy = .high
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent16Half

        let handler = VNImageRequestHandler(cvPixelBuffer: source, options: [:])
        do {
            try handler.perform([request])
        } catch {
            NSLog("VisionFlowProvider: Vision optical flow EXCEPTION: %@", error.localizedDescription)
            return nil
        }

        guard let observation = request.results?.first as? VNPixelBufferObservation else {
            NSLog("VisionFlowProvider: Vision returned NO observation results")
            return nil
        }

        guard let cache = textureCache else {
            NSLog("VisionFlowProvider: Texture cache is nil!")
            return nil
        }

        let flowBuffer = observation.pixelBuffer
        let flowW = CVPixelBufferGetWidth(flowBuffer)
        let flowH = CVPixelBufferGetHeight(flowBuffer)

        var cvTex: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, flowBuffer, nil,
            .rg16Float, flowW, flowH, 0, &cvTex
        )
        guard status == kCVReturnSuccess, let tex = cvTex,
              let flowTexture = CVMetalTextureGetTexture(tex) else {
            NSLog("VisionFlowProvider: CVMetalTexture creation failed (status: %d)", status)
            return nil
        }

        // Copy to a persistent GPU texture (CVMetalTexture is transient)
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg16Float, width: flowW, height: flowH, mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        guard let persistentTex = device.makeTexture(descriptor: desc),
              let copyBuf = commandQueue.makeCommandBuffer(),
              let blit = copyBuf.makeBlitCommandEncoder() else {
            NSLog("VisionFlowProvider: Failed to create persistent flow texture")
            return nil
        }
        blit.copy(from: flowTexture, to: persistentTex)
        blit.endEncoding()
        copyBuf.commit()
        copyBuf.waitUntilCompleted()

        return persistentTex
    }

    private func createPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                           kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        return pb
    }
}
