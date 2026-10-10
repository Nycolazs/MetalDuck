import AppKit
import Foundation

@MainActor
protocol AddProfileViewControllerDelegate: AnyObject {
    func addProfileViewController(_ vc: AddProfileViewController, didCreateProfileWithName name: String)
    func addProfileViewControllerDidCancel(_ vc: AddProfileViewController)
}

/// A view controller for the "New Profile" modal.
/// This modal allows users to create a custom profile based on the current active settings.
final class AddProfileViewController: NSViewController {
    weak var delegate: AddProfileViewControllerDelegate?
    
    private var clickMonitor: Any?
    
    private let titleLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "New Profile")
        tf.font = .systemFont(ofSize: 16, weight: .bold)
        tf.textColor = NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.96, alpha: 1.0)
        return tf
    }()
    
    private let subtitleLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "Enter a name for your new profile.")
        tf.font = .systemFont(ofSize: 12, weight: .regular)
        tf.textColor = NSColor(calibratedRed: 0.50, green: 0.53, blue: 0.58, alpha: 1.0)
        return tf
    }()
    
    private let nameField: NSTextField = {
        let tf = NSTextField()
        tf.placeholderString = "Profile Name"
        tf.isBordered = false
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.textColor = NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.96, alpha: 1.0)
        tf.font = .systemFont(ofSize: 14)
        tf.focusRingType = .none
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()
    
    private lazy var nameFieldContainer: NSView = {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.20, alpha: 0.6).cgColor
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(calibratedRed: 0.26, green: 0.27, blue: 0.32, alpha: 0.35).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(nameField)
        NSLayoutConstraint.activate([
            nameField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            nameField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            nameField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }()
    
    private lazy var createButton: ModalActionButton = {
        let btn = ModalActionButton(title: "Create", style: .primary)
        btn.setAction(#selector(handleCreate), target: self)
        return btn
    }()
    
    private lazy var cancelButton: ModalActionButton = {
        let btn = ModalActionButton(title: "Cancel", style: .secondary)
        btn.setAction(#selector(handleCancel), target: self)
        return btn
    }()
    
    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 200))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 1.0).cgColor
        view.layer?.cornerRadius = 12
        self.view = view
        self.preferredContentSize = NSSize(width: 340, height: 200)
        
        let headerStack = NSStackView(views: [titleLabel, subtitleLabel])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 4
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        
        let buttonsStack = NSStackView(views: [cancelButton, createButton])
        buttonsStack.orientation = .horizontal
        buttonsStack.spacing = 10
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false
        
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(calibratedRed: 0.26, green: 0.27, blue: 0.32, alpha: 0.35).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(headerStack)
        view.addSubview(nameFieldContainer)
        view.addSubview(divider)
        view.addSubview(buttonsStack)
        
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            
            nameFieldContainer.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 18),
            nameFieldContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            nameFieldContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            nameFieldContainer.heightAnchor.constraint(equalToConstant: 34),
            
            divider.topAnchor.constraint(equalTo: nameFieldContainer.bottomAnchor, constant: 20),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
            
            buttonsStack.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 16),
            buttonsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            buttonsStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),
        ])
        
        nameField.stringValue = "Custom Profile"
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        nameField.selectText(nil)
        view.window?.makeFirstResponder(nameField)
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
    
    @objc private func handleCreate() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            delegate?.addProfileViewController(self, didCreateProfileWithName: name)
        }
    }
    
    @objc private func handleCancel() {
        delegate?.addProfileViewControllerDidCancel(self)
    }
}
