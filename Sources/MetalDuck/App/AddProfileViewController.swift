import AppKit
import Foundation

@MainActor
protocol AddProfileViewControllerDelegate: AnyObject {
    func addProfileViewController(_ vc: AddProfileViewController, didCreateProfileWithName name: String)
    func addProfileViewControllerDidCancel(_ vc: AddProfileViewController)
}

/// Sheet that creates a custom profile from the current active settings.
final class AddProfileViewController: NSViewController {
    weak var delegate: AddProfileViewControllerDelegate?

    private let nameField = GlassSheet.textField(value: "Custom Profile", placeholder: "Profile name")

    override func loadView() {
        view = GlassSheet.makeView(
            width: 380,
            symbol: "square.and.arrow.down",
            title: "New Profile",
            message: "Saves the current capture, scaling, and frame generation settings under a new name.",
            body: nameField,
            buttons: [
                GlassButton.push("Cancel", target: self, action: #selector(handleCancel), isCancel: true),
                GlassButton.push("Create", target: self, action: #selector(handleCreate), isDefault: true)
            ]
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(nameField)
        nameField.selectText(nil)
    }

    @objc private func handleCreate() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            NSSound.beep()
            return
        }
        delegate?.addProfileViewController(self, didCreateProfileWithName: name)
    }

    @objc private func handleCancel() {
        delegate?.addProfileViewControllerDidCancel(self)
    }
}
