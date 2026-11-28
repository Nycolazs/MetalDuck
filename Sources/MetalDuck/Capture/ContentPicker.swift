import AppKit
@preconcurrency import ScreenCaptureKit

/// The system's own window, app and display picker: the one macOS shows when you share
/// a window in a meeting. It hands back a content filter for what was chosen.
@MainActor
final class ContentPicker: NSObject {
    var onPick: ((SCContentFilter) -> Void)?
    var onCancel: (() -> Void)?
    var onError: ((Error) -> Void)?

    private let picker = SCContentSharingPicker.shared
    private var isObserving = false

    /// Shows the picker. `excludedWindowIDs` are MetalDuck's own windows: a build run
    /// straight from `.build` has no bundle identifier to exclude it by.
    func present(excludingWindowIDs excludedWindowIDs: [CGWindowID]) {
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow, .singleApplication, .singleDisplay]
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier].compactMap { $0 }
        configuration.excludedWindowIDs = excludedWindowIDs.map { Int($0) }
        configuration.allowsChangingSelectedContent = true
        picker.defaultConfiguration = configuration

        if !isObserving {
            picker.add(self)
            isObserving = true
        }
        // The picker only appears while it is marked active.
        picker.isActive = true
        picker.present()
    }
}

extension ContentPicker: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        let box = UncheckedSendable(filter)
        Task { @MainActor in self.onPick?(box.value) }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in self.onCancel?() }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in self.onError?(error) }
    }
}

/// Carries a ScreenCaptureKit object, which is not marked Sendable, to another thread.
/// Each one is only read after it is handed over.
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
