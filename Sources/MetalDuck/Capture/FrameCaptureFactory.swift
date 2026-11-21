import Foundation

enum FrameCaptureFactory {
    @MainActor
    static func make(
        context: MetalContext,
        target: CaptureTarget,
        configuration: CaptureConfiguration
    ) -> FrameCaptureService {
        RoutedFrameCaptureService(context: context, target: target, configuration: configuration)
    }
}

private final class RoutedFrameCaptureService: FrameCaptureService {
    var onFrame: ((CapturedFrame) -> Void)? {
        get { screen.onFrame }
        set {
            screen.onFrame = newValue
            video.onFrame = newValue
        }
    }
    var onError: ((Error) -> Void)? {
        get { screen.onError }
        set {
            screen.onError = newValue
            video.onError = newValue
        }
    }

    private let screen: ScreenCaptureKitCaptureService
    private let video: VideoDeviceCaptureService
    @MainActor private var target: CaptureTarget
    @MainActor private var configuration: CaptureConfiguration
    @MainActor private var running = false
    @MainActor private var pending: Task<Void, Never>?

    @MainActor
    init(context: MetalContext, target: CaptureTarget, configuration: CaptureConfiguration) {
        self.target = target
        self.configuration = configuration
        screen = ScreenCaptureKitCaptureService(context: context, target: target, configuration: configuration)
        video = VideoDeviceCaptureService(context: context)
    }

    @MainActor
    func start() async throws {
        try await serialize {
            if self.running { await self.stopBackend() }
            try await self.startBackend()
        }
    }

    @MainActor
    func stop() async {
        // This operation has no throwing steps.
        _ = try? await serialize { await self.stopBackend() }
    }

    @MainActor
    func reconfigure(target: CaptureTarget) async throws {
        try await serialize {
            guard self.target != target else { return }
            let wasRunning = self.running
            if wasRunning { await self.stopBackend() }
            self.target = target
            if wasRunning { try await self.startBackend() }
        }
    }

    @MainActor
    func reconfigure(configuration: CaptureConfiguration) async throws {
        try await serialize {
            self.configuration = configuration
            if case .videoDevice = self.target {
                await self.video.updateFrameRate(configuration.framesPerSecond)
            } else {
                try await self.screen.reconfigure(configuration: configuration)
            }
        }
    }

    @MainActor
    private func startBackend() async throws {
        switch target {
        case .videoDevice(let id):
            try await video.start(id: id, framesPerSecond: configuration.framesPerSecond)
        default:
            try await screen.reconfigure(target: target)
            try await screen.reconfigure(configuration: configuration)
            try await screen.start()
        }
        running = true
    }

    @MainActor
    private func stopBackend() async {
        running = false
        switch target {
        case .videoDevice:
            await video.stop()
        default:
            await screen.stop()
        }
    }

    @MainActor
    private func serialize(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        let previous = pending
        let current = Task {
            await previous?.value
            try await operation()
        }
        pending = Task { _ = await current.result }
        try await current.value
    }
}
