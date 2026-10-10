import AppKit
import Foundation

@MainActor
protocol DeleteProfileViewControllerDelegate: AnyObject {
    func deleteProfileViewControllerDidConfirm(_ vc: DeleteProfileViewController)
    func deleteProfileViewControllerDidCancel(_ vc: DeleteProfileViewController)
}

/// A view controller for the "Delete Profile" confirmation modal.
/// This modal asks the user to confirm the deletion of a non-built-in profile.
final class DeleteProfileViewController: NSViewController {
    weak var delegate: DeleteProfileViewControllerDelegate?
    private let profileName: String
    
    private var clickMonitor: Any?
    
    private let titleLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "Delete Profile")
        tf.font = .systemFont(ofSize: 16, weight: .bold)
        tf.textColor = NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.96, alpha: 1.0)
        return tf
    }()
    
    private lazy var messageLabel: NSTextField = {
        let tf = NSTextField(wrappingLabelWithString: "Are you sure you want to delete \"\(profileName)\"? This action cannot be undone.")
        tf.font = .systemFont(ofSize: 13, weight: .regular)
        tf.textColor = NSColor(calibratedRed: 0.78, green: 0.80, blue: 0.84, alpha: 1.0)
        tf.lineBreakMode = .byWordWrapping
        tf.usesSingleLineMode = false
        return tf
    }()
    
    private lazy var warningIcon: NSImageView = {
        let iv = NSImageView()
        let config = NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        iv.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")?.withSymbolConfiguration(config)
        iv.contentTintColor = NSColor.systemOrange.withAlphaComponent(0.8)
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.widthAnchor.constraint(equalToConstant: 32).isActive = true
        iv.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return iv
    }()
    
    private lazy var deleteButton: ModalActionButton = {
        let btn = ModalActionButton(title: "Delete", style: .destructive)
        btn.setAction(#selector(handleDelete), target: self)
        return btn
    }()
    
    private lazy var cancelButton: ModalActionButton = {
        let btn = ModalActionButton(title: "Cancel", style: .secondary)
        btn.setAction(#selector(handleCancel), target: self)
        return btn
    }()
    
    init(profileName: String) {
        self.profileName = profileName
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 1.0).cgColor
        view.layer?.cornerRadius = 12
        self.view = view
        self.preferredContentSize = NSSize(width: 360, height: 200)
        
        let headerStack = NSStackView(views: [warningIcon, titleLabel])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 10
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        
        let buttonsStack = NSStackView(views: [cancelButton, deleteButton])
        buttonsStack.orientation = .horizontal
        buttonsStack.spacing = 10
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false
        
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(calibratedRed: 0.26, green: 0.27, blue: 0.32, alpha: 0.35).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(headerStack)
        view.addSubview(messageLabel)
        view.addSubview(divider)
        view.addSubview(buttonsStack)
        
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            
            messageLabel.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 14),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            
            divider.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 20),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
            
            buttonsStack.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 16),
            buttonsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            buttonsStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),
        ])
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        setupClickOutsideMonitor()
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            handleCancel()
        } else {
            super.keyDown(with: event)
        }
    }
    
    private func setupClickOutsideMonitor() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let _ = self.view.window else { return event }
            let locationInView = self.view.convert(event.locationInWindow, from: nil)
            if !self.view.bounds.contains(locationInView) {
                self.handleCancel()
                return nil
            }
            return event
        }
    }
    
    @objc private func handleDelete() {
        delegate?.deleteProfileViewControllerDidConfirm(self)
    }
    
    @objc private func handleCancel() {
        delegate?.deleteProfileViewControllerDidCancel(self)
    }
}
