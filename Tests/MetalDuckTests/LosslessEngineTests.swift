import Foundation
import ImageIO
import Metal
import Testing
import UniformTypeIdentifiers
@testable import MetalDuck

/// Runs LSFG (lsfg-metal, kernels translated in the app) from the imported Lossless.dll on a known
/// motion and scores the in-between frame. Skipped when no Lossless.dll is imported.
@Suite(.serialized) struct LosslessEngineTests {
    private let width = 640
    private let height = 360

    private var dllURL: URL? {
        let url = LosslessScalingLibrary.installedURL
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @Test(arguments: [(false, Float(1)), (false, 0.5), (true, 1), (true, 0.5)])
    func interpolatesHorizontalMotion(performance: Bool, flowScale: Float) throws {
        guard let dllURL else { return }
        let device = try #require(MTLCreateSystemDefaultDevice())
        let queue = try #require(device.makeCommandQueue())
        let engine = try LosslessFrameGenerationEngine(device: device, dllURL: dllURL)

        let step = 16
        let frames = try (0..<4).map { index in
            GenerationFrame(texture: try makeFrame(device: device, shift: index * step), id: UInt64(index + 1))
        }

        var output: MTLTexture?
        for index in 0..<3 {
            let commandBuffer = try #require(queue.makeCommandBuffer())
            if case .produced(let texture, _, _, _, _) = engine.attemptInterpolation(
                commandBuffer: commandBuffer, previous: frames[index], next: frames[index + 1], t: 0.5, multiplier: 2,
                performance: performance, flowScale: flowScale
            ) {
                output = texture
            }
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            #expect(commandBuffer.error == nil)
        }

        let generated = try read(try #require(output), device: device, queue: queue)
        let truth = pattern(shift: 2 * step + step / 2)
        let blend = zip(pattern(shift: 2 * step), pattern(shift: 3 * step)).map { UInt8((Int($0) + Int($1)) / 2) }
        let lsfg = psnr(generated, truth)
        let linear = psnr(blend, truth)
        print("\(performance ? "performance" : "quality") flow \(flowScale): LSFG in-between PSNR \(String(format: "%.1f", lsfg)) dB, linear blend \(String(format: "%.1f", linear)) dB")
        if let folder = ProcessInfo.processInfo.environment["LSFG_SELFTEST_OUT"] {
            try writePNG(generated, to: URL(fileURLWithPath: folder).appendingPathComponent("lsfg.png"))
        }
        #expect(lsfg > linear + 3)
    }

    /// GPU time per real frame at 1080p, 2×: history passes plus one in-between frame.
    @Test(arguments: [(false, Float(1)), (false, 0.5), (true, 1), (true, 0.5)])
    func measuresGPUTimeAt1080p(performance: Bool, flowScale: Float) throws {
        guard let dllURL else { return }
        let device = try #require(MTLCreateSystemDefaultDevice())
        let queue = try #require(device.makeCommandQueue())
        let engine = try LosslessFrameGenerationEngine(device: device, dllURL: dllURL)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1920, height: 1080, mipmapped: false)
        descriptor.usage = [.shaderRead]
        var bytes = [UInt8](repeating: 0, count: 1920 * 1080 * 4)
        let frames = try (0..<12).map { index -> GenerationFrame in
            for i in bytes.indices { bytes[i] = UInt8(truncatingIfNeeded: (i &* 2_654_435_761 &+ index &* 97) >> 7) }
            let texture = try #require(device.makeTexture(descriptor: descriptor))
            texture.replace(region: MTLRegionMake2D(0, 0, 1920, 1080), mipmapLevel: 0, withBytes: bytes, bytesPerRow: 1920 * 4)
            return GenerationFrame(texture: texture, id: UInt64(index + 1))
        }

        var times: [Double] = []
        for index in 0..<11 {
            let commandBuffer = try #require(queue.makeCommandBuffer())
            _ = engine.attemptInterpolation(commandBuffer: commandBuffer, previous: frames[index], next: frames[index + 1],
                                            t: 0.5, multiplier: 2, performance: performance, flowScale: flowScale)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            if index >= 3 { times.append((commandBuffer.gpuEndTime - commandBuffer.gpuStartTime) * 1000) }
        }
        print(String(format: "%@ flow %.2f: LSFG 1080p GPU %.2f ms per real frame at 2x",
                     performance ? "performance" : "quality", flowScale, times.sorted()[times.count / 2]))
    }

    // MARK: - Helpers

    /// BGRA pixels of a fixed multi-scale noise pattern moved `shift` pixels to the right.
    private func pattern(shift: Int) -> [UInt8] {
        func hash(_ x: Int, _ y: Int, _ seed: Int) -> Double {
            var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 2_147_483_647))
            h = (h ^ (h >> 13)) &* 1_274_126_177
            return Double((h ^ (h >> 16)) & 0xFFFF) / 65535
        }
        func noise(_ x: Double, _ y: Double, _ cell: Double, _ seed: Int) -> Double {
            let gx = x / cell, gy = y / cell
            let x0 = Int(floor(gx)), y0 = Int(floor(gy))
            let fx = gx - floor(gx), fy = gy - floor(gy)
            let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
            let top = hash(x0, y0, seed) * (1 - sx) + hash(x0 + 1, y0, seed) * sx
            let bottom = hash(x0, y0 + 1, seed) * (1 - sx) + hash(x0 + 1, y0 + 1, seed) * sx
            return top * (1 - sy) + bottom * sy
        }
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let px = Double(x - shift), py = Double(y)
                for channel in 0..<3 {
                    let value = 0.5 * noise(px, py, 48, channel) + 0.3 * noise(px, py, 16, channel + 3)
                        + 0.2 * noise(px, py, 6, channel + 6)
                    pixels[(y * width + x) * 4 + channel] = UInt8(max(0, min(255, value * 255)))
                }
            }
        }
        return pixels
    }

    private func makeFrame(device: MTLDevice, shift: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pattern(shift: shift), bytesPerRow: width * 4)
        return texture
    }

    private func read(_ texture: MTLTexture, device: MTLDevice, queue: MTLCommandQueue) throws -> [UInt8] {
        let buffer = try #require(device.makeBuffer(length: width * height * 4, options: .storageModeShared))
        let commandBuffer = try #require(queue.makeCommandBuffer())
        let blit = try #require(commandBuffer.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: width * 4, destinationBytesPerImage: width * height * 4)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return [UInt8](UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt8.self), count: width * height * 4))
    }

    /// PSNR over the colour channels, leaving out a 48 px margin where content enters the frame.
    private func psnr(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var error = 0.0, count = 0
        for y in 48..<(height - 48) {
            for x in 48..<(width - 48) {
                for channel in 0..<3 {
                    let i = (y * width + x) * 4 + channel
                    let d = Double(a[i]) - Double(b[i])
                    error += d * d
                    count += 1
                }
            }
        }
        return 10 * log10(255 * 255 / max(error / Double(count), 1e-9))
    }

    private func writePNG(_ bgra: [UInt8], to url: URL) throws {
        var rgba = bgra
        for i in stride(from: 0, to: rgba.count, by: 4) { rgba.swapAt(i, i + 2) }
        let provider = try #require(CGDataProvider(data: Data(rgba) as CFData))
        let image = try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
