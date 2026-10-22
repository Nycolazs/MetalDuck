import AppKit
import Foundation

@MainActor
protocol DeleteProfileViewControllerDelegate: AnyObject {
    func deleteProfileViewControllerDidConfirm(_ vc: DeleteProfileViewController)
    func deleteProfileViewControllerDidCancel(_ vc: DeleteProfileViewController)
}

/// Confirmation sheet for deleting a custom profile.
final class DeleteProfileViewController: NSViewController {
    weak var delegate: DeleteProfileViewControllerDelegate?
    private let profileName: String

    init(profileName: String) {
        self.profileName = profileName
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let deleteButton = GlassButton.push("Delete", target: self, action: #selector(handleDelete), isDefault: true)
        deleteButton.hasDestructiveAction = true
        deleteButton.bezelColor = .systemRed

        view = GlassSheet.makeView(
            width: 380,
            symbol: "trash",
            symbolTint: .systemRed,
            title: "Delete “\(profileName)”?",
            message: "This profile and its settings will be removed. This can’t be undone.",
            buttons: [
                GlassButton.push("Cancel", target: self, action: #selector(handleCancel), isCancel: true),
                deleteButton
            ]
        )
    }

    @objc private func handleDelete() {
        delegate?.deleteProfileViewControllerDidConfirm(self)
    }

    @objc private func handleCancel() {
        delegate?.deleteProfileViewControllerDidCancel(self)
    }
}
