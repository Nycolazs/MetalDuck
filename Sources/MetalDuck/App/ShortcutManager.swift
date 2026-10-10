import AppKit

@MainActor
/// Async optical flow provider leveraging Apple's Vision framework (VNGenerateOpticalFlowRequest).
/// Computes motion vectors on the ANE or GPU to enable accurate frame interpolation.
final class VisionFlowProvider: @unchecked Sendable {
    // Placeholder for VisionFlowProvider content
}

/// Handles system-wide and local keyboard shortcut monitoring.
/// Allows users to toggle application features using configurable hotkey combinations.
final class ShortcutManager {
    static let shared = ShortcutManager()

    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    var onTrigger: (() -> Void)?
    
    private init() {}
    
    func update(settings: ShortcutSettings) {
        stopMonitoring()
        
        guard settings.enabled, let keyCode = settings.keyCode else {
            return
        }
        
        let modifiers = NSEvent.ModifierFlags(rawValue: settings.modifiers)
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(keyCode), 
               event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers {
                DispatchQueue.main.async {
                    self?.onTrigger?()
                }
            }
        }
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(keyCode), 
               event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers {
                self?.onTrigger?()
                return nil // Consume event
            }
            return event
        }
    }
    
    func stopMonitoring() {
        if let m = globalMonitor {
            NSEvent.removeMonitor(m)
            globalMonitor = nil
        }
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
    }
}
