import AppKit
import Carbon

/// System-wide shortcuts that do not need Accessibility permission.
/// Carbon hot keys are delivered even when another app is focused, which is
/// what makes Stop reachable while the scaled picture covers the screen.
@MainActor
final class ShortcutManager {
    static let shared = ShortcutManager()

    /// Always-available stop chord: ⌃⌥⌘⎋. It never starts scaling.
    static let panicDisplay = "⌃⌥⌘⎋"
    static let panicID: UInt32 = 2
    private static let userID: UInt32 = 1
    private static let signature: OSType = 0x4D44_484B // 'MDHK'
    private static let panicKeyCode: UInt32 = 53
    private static let panicModifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey)

    var onTrigger: (() -> Void)?
    var onPanic: (() -> Void)?

    private var handler: EventHandlerRef?
    private var userHotKey: EventHotKeyRef?
    private var panicHotKey: EventHotKeyRef?
    private var installed = false

    private init() {}

    func update(settings: ShortcutSettings) {
        installHandlerIfNeeded()
        unregister(&userHotKey)
        unregister(&panicHotKey)
        register(
            keyCode: Self.panicKeyCode,
            modifiers: Self.panicModifiers,
            id: Self.panicID,
            into: &panicHotKey
        )
        guard settings.enabled, let keyCode = settings.keyCode else { return }
        let modifiers = Self.carbonModifiers(settings.modifiers)
        // The panic chord is reserved, so a user shortcut on the same keys
        // would steal the guaranteed stop.
        guard !(keyCode == Int(Self.panicKeyCode) && modifiers == Self.panicModifiers) else { return }
        register(keyCode: UInt32(keyCode), modifiers: modifiers, id: Self.userID, into: &userHotKey)
    }

    func stopMonitoring() {
        unregister(&userHotKey)
        unregister(&panicHotKey)
    }

    fileprivate func fire(_ id: UInt32) {
        if id == Self.panicID {
            onPanic?()
        } else {
            onTrigger?()
        }
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), metalDuckHotKeyHandler, 1, &spec, nil, &handler)
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, into slot: inout EventHotKeyRef?) {
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &slot)
        if status != noErr {
            PipelineLog.shared.event("session", "could not register hotkey \(id), status \(status)")
        }
    }

    private func unregister(_ slot: inout EventHotKeyRef?) {
        if let hotKey = slot {
            UnregisterEventHotKey(hotKey)
            slot = nil
        }
    }

    private static func carbonModifiers(_ raw: UInt) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: raw)
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}

private func metalDuckHotKeyHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let id = hotKeyID.id
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            ShortcutManager.shared.fire(id)
        }
    }
    return noErr
}

/// Exits the process if the main thread stops responding while scaling is on.
/// A wedged main thread cannot hide the picture, so leaving the process is
/// what gives the screen back without a reboot.
final class RunGuard: @unchecked Sendable {
    static let shared = RunGuard()

    private let lock = NSLock()
    private var beat = Date()
    private var armed = false
    private var timer: DispatchSourceTimer?
    private var heartbeat: Timer?

    private init() {}

    func arm() {
        lock.lock()
        armed = true
        beat = Date()
        lock.unlock()
        guard timer == nil else { return }

        let source = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        source.schedule(deadline: .now() + 2, repeating: 2)
        // The handler must not be MainActor-isolated: it runs on the utility queue.
        source.setEventHandler(handler: RunGuard.checkHandler(self))
        source.resume()
        timer = source

        // .common keeps beating while a menu is open. The default mode pauses
        // during menu tracking, and an open Stop menu would look like a hang.
        let pulse = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.touch()
        }
        RunLoop.main.add(pulse, forMode: .common)
        heartbeat = pulse
    }

    /// A plain function, so the timer does not inherit the caller's actor.
    private static func checkHandler(_ guardObject: RunGuard) -> @Sendable () -> Void {
        { [weak guardObject] in
            guardObject?.check()
        }
    }

    func disarm() {
        lock.lock()
        armed = false
        lock.unlock()
    }

    private func touch() {
        lock.lock()
        beat = Date()
        lock.unlock()
    }

    private func check() {
        lock.lock()
        let stalled = armed && Date().timeIntervalSince(beat) > 8
        lock.unlock()
        guard stalled else { return }
        fputs("MetalDuck main thread stalled while scaling; exiting to release the screen.\n", stderr)
        exit(0)
    }
}
