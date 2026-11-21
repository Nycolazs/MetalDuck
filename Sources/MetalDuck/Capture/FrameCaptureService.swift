import Foundation

protocol FrameCaptureService: AnyObject, Sendable {
    var onFrame: ((CapturedFrame) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }

    @MainActor func start() async throws
    @MainActor func stop() async
    @MainActor func reconfigure(target: CaptureTarget) async throws
    @MainActor func reconfigure(configuration: CaptureConfiguration) async throws
}
