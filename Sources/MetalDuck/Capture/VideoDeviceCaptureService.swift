@preconcurrency import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

struct VideoCaptureSource {
    let id: String
    let title: String
}

enum VideoDeviceCaptureError: LocalizedError {
    case noDevice
    case missingUsageDescription
    case permissionDenied
    case cannotStart
    case interrupted

    var errorDescription: String? {
        switch self {
        case .noDevice: "Connect a capture card and refresh the source list."
        case .missingUsageDescription: "Open the packaged MetalDuck.app to use a capture card."
        case .permissionDenied: "Allow MetalDuck under System Settings → Privacy & Security → Camera."
        case .cannotStart: "Could not start capture card video. Check the connection and close other apps using it."
        case .interrupted: "Capture card video was interrupted. Check the connection and restart capture."
        }
    }
}

final class VideoDeviceCaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onFrame: ((CapturedFrame) -> Void)?
    var onError: ((Error) -> Void)?

    private let context: MetalContext
    // All session operations and sample delivery run on this queue.
    private let queue = DispatchQueue(label: "metalduck.capture.video-device", qos: .userInitiated)
    private var session: AVCaptureSession?
    private var observers: [NSObjectProtocol] = []
    private var minimumFrameSpacing = 0.0
    private var lastTimestamp: Double?

    init(context: MetalContext) {
        self.context = context
    }

    private static func devices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified).devices
    }

    static func sources() -> [VideoCaptureSource] {
        devices().map { VideoCaptureSource(id: $0.uniqueID, title: $0.localizedName) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func start(id: String?, framesPerSecond: Int) async throws {
        guard let id else { throw VideoDeviceCaptureError.noDevice }
        guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else {
            throw VideoDeviceCaptureError.missingUsageDescription
        }
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            throw VideoDeviceCaptureError.permissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.startSession(id: id, framesPerSecond: framesPerSecond)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.stopSession()
                continuation.resume()
            }
        }
    }

    func updateFrameRate(_ framesPerSecond: Int) async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.minimumFrameSpacing = 0.75 / Double(max(1, framesPerSecond))
                continuation.resume()
            }
        }
    }

    private func startSession(id: String, framesPerSecond: Int) throws {
        stopSession()
        guard let device = Self.devices().first(where: { $0.uniqueID == id }) else {
            throw VideoDeviceCaptureError.noDevice
        }
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        guard session.canAddInput(input) else { throw VideoDeviceCaptureError.cannotStart }
        session.addInput(input)
        guard session.canAddOutput(output) else { throw VideoDeviceCaptureError.cannotStart }
        session.addOutput(output)
        guard output.availableVideoPixelFormatTypes.contains(kCVPixelFormatType_32BGRA) else {
            throw VideoDeviceCaptureError.cannotStart
        }
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)

        minimumFrameSpacing = 0.75 / Double(max(1, framesPerSecond))
        lastTimestamp = nil
        self.session = session
        let center = NotificationCenter.default
        let sessionID = ObjectIdentifier(session)
        let notifications: [(Notification.Name, AnyObject)] = [
            (AVCaptureSession.runtimeErrorNotification, session),
            (AVCaptureSession.wasInterruptedNotification, session),
            (AVCaptureDevice.wasDisconnectedNotification, device)
        ]
        observers = notifications.map { name, sender in
            center.addObserver(forName: name, object: sender, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    guard self.session.map(ObjectIdentifier.init) == sessionID else { return }
                    self.stopSession()
                    self.onError?(VideoDeviceCaptureError.interrupted)
                }
            }
        }
        session.startRunning()
        guard session.isRunning else {
            stopSession()
            throw VideoDeviceCaptureError.cannotStart
        }
    }

    private func stopSession() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        session?.stopRunning()
        session = nil
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard session?.outputs.contains(where: { $0 === output }) == true,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let seconds = timestamp.seconds
        if seconds.isFinite {
            if let lastTimestamp, seconds >= lastTimestamp, seconds - lastTimestamp < minimumFrameSpacing {
                return
            }
            lastTimestamp = seconds
        }

        if let frame = CapturedFrame(pixelBuffer: pixelBuffer, timestamp: timestamp, targetRect: nil, context: context) {
            onFrame?(frame)
        }
    }
}
