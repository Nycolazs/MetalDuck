import AppKit
import Foundation

@MainActor
protocol RenameProfileViewControllerDelegate: AnyObject {
    func renameProfileViewController(_ vc: RenameProfileViewController, didRenameProfileWithName name: String)
    func renameProfileViewControllerDidCancel(_ vc: RenameProfileViewController)
}

/// Sheet that renames an existing custom profile.
final class RenameProfileViewController: NSViewController {
    weak var delegate: RenameProfileViewControllerDelegate?

    private let nameField: NSTextField

    init(currentName: String) {
        nameField = GlassSheet.textField(value: currentName, placeholder: "Profile name")
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = GlassSheet.makeView(
            width: 380,
            symbol: "pencil",
            title: "Rename Profile",
            message: "Choose a new name for this profile.",
            body: nameField,
            buttons: [
                GlassButton.push("Cancel", target: self, action: #selector(handleCancel), isCancel: true),
                GlassButton.push("Save", target: self, action: #selector(handleRename), isDefault: true)
            ]
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(nameField)
        nameField.selectText(nil)
    }

    @objc private func handleRename() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            NSSound.beep()
            return
        }
        delegate?.renameProfileViewController(self, didRenameProfileWithName: name)
    }

    @objc private func handleCancel() {
        delegate?.renameProfileViewControllerDidCancel(self)
    }
}
