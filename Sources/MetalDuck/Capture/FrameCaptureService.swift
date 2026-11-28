import Foundation

protocol FrameCaptureService: AnyObject, Sendable {
    var onFrame: ((CapturedFrame) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
    /// Called for every picture the source sends, before repeats and the rate cap drop any.
    var onSourceFrame: (() -> Void)? { get set }

    func start() async throws
    func stop() async
    func reconfigure(target: CaptureTarget) async throws
    func reconfigure(configuration: CaptureConfiguration) async throws
}
