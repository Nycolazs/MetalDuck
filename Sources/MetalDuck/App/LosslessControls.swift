import AppKit
import UniformTypeIdentifiers

/// Status of the imported `Lossless.dll`, a Steam console button and a manual
/// import button, for the Lossless.dll row of the Frame Generation group.
///
/// The Steam copy is imported on its own whenever MetalDuck becomes active, so
/// running the download in the Steam console and switching back is enough.
@MainActor
final class LosslessControls: NSStackView {
    private let statusLabel = GlassLabel.make("", font: GlassFont.value, color: .secondaryLabelColor)
    /// Called when a Lossless.dll arrives where there was none (from Steam or Import…).
    var onImported: (() -> Void)?
    private var activationObserver: NSObjectProtocol?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        orientation = .horizontal
        alignment = .centerY
        spacing = 8

        let steamButton = Self.button("Steam Console", target: self, action: #selector(handleOpenSteamConsole))
        steamButton.toolTip = "Opens steam://open/console and copies \(LosslessScalingLibrary.downloadCommand)."
        let importButton = Self.button("Import…", target: self, action: #selector(handleImport))
        importButton.toolTip = "Import a Lossless.dll stored somewhere other than Steam's download folder."
        setViews([statusLabel, steamButton, importButton], in: .leading)

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncFromSteam() }
        }
        syncFromSteam()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    private static func button(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = HandCursorButton(title: title, target: target, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .push
        button.controlSize = .small
        return button
    }

    private func syncFromSteam() {
        let hadFile = LosslessScalingLibrary.installedSize != nil
        LosslessScalingLibrary.importFromSteamIfNeeded()
        refreshStatus()
        if !hadFile, LosslessScalingLibrary.installedSize != nil { onImported?() }
    }

    private func refreshStatus() {
        if let size = LosslessScalingLibrary.installedSize {
            statusLabel.stringValue = "Imported · " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            statusLabel.textColor = .secondaryLabelColor
        } else {
            statusLabel.stringValue = "Not found"
            statusLabel.textColor = .tertiaryLabelColor
        }
    }

    @objc private func handleOpenSteamConsole() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(LosslessScalingLibrary.downloadCommand, forType: .string)
        if !LosslessScalingLibrary.openSteamConsole() {
            showAlert(
                title: "Steam is not installed",
                message: "Install Steam, sign in, then try again. The command \(LosslessScalingLibrary.downloadCommand) is on the clipboard."
            )
        }
    }

    @objc private func handleImport() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.message = "Choose Lossless.dll from your Lossless Scaling download."
        panel.prompt = "Import"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let dll = UTType(filenameExtension: "dll") {
            panel.allowedContentTypes = [dll]
        }
        if let folder = LosslessScalingLibrary.steamDownloadFolder {
            panel.directoryURL = folder
        }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try LosslessScalingLibrary.importFile(from: url)
                self.refreshStatus()
                self.onImported?()
            } catch {
                self.showAlert(title: "Could not import Lossless.dll", message: error.localizedDescription)
            }
        }
    }

    private func showAlert(title: String, message: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.beginSheetModal(for: window)
    }
}

/// The Steam console command, shown as selectable text with a Copy button.
@MainActor
final class LosslessCommandControl: NSStackView {
    private let copyButton = HandCursorButton(title: "Copy", target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        orientation = .horizontal
        alignment = .centerY
        spacing = 8

        let command = NSTextField(labelWithString: LosslessScalingLibrary.downloadCommand)
        command.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        command.textColor = .labelColor
        command.isSelectable = true

        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.bezelStyle = .push
        copyButton.controlSize = .small
        copyButton.target = self
        copyButton.action = #selector(handleCopy)
        setViews([command, copyButton], in: .leading)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleCopy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(LosslessScalingLibrary.downloadCommand, forType: .string)
        copyButton.title = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton.title = "Copy"
        }
    }
}
