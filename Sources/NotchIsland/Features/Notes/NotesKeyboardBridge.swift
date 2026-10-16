import AppKit
import SwiftUI

/// Invisible view that tells the Notes tab which window hosts it and watches the keyboard in
/// that window: Command-V creates a note from the list or attaches a picture in the editor, and
/// the standard editing shortcuts reach the focused text field.
struct NotesKeyboardBridge: NSViewRepresentable {
    let controller: NotesTabController

    func makeNSView(context: Context) -> NotesKeyboardBridgeView {
        let view = NotesKeyboardBridgeView()
        view.controller = controller
        return view
    }

    func updateNSView(_ nsView: NotesKeyboardBridgeView, context: Context) {
        nsView.controller = controller
    }

    static func dismantleNSView(_ nsView: NotesKeyboardBridgeView, coordinator: ()) {
        nsView.removeMonitor()
    }
}

final class NotesKeyboardBridgeView: NSView {
    weak var controller: NotesTabController? {
        didSet { controller?.hostWindow = window }
    }

    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        controller?.hostWindow = window
        if window == nil {
            removeMonitor()
        } else {
            installMonitor()
        }
    }

    func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, let controller else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers.contains(.command), !modifiers.contains(.option), !modifiers.contains(.control) else {
            return false
        }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isEditingText = window.firstResponder is NSText

        if modifiers == .command, key == "v" {
            if controller.handlePasteShortcut(textFieldHasFocus: isEditingText) { return true }
            return isEditingText && NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        }

        // The island's app has no Edit menu, so the key equivalents Atoll gets from SwiftUI's
        // standard menu bar are sent to the focused text view here.
        guard isEditingText,
              let action = Self.editingAction(forKey: key, shift: modifiers.contains(.shift)) else { return false }
        return NSApp.sendAction(action, to: nil, from: self)
    }

    /// Command-key editing actions a focused title, body or search field understands.
    static func editingAction(forKey key: String, shift: Bool) -> Selector? {
        switch (key, shift) {
        case ("x", false): #selector(NSText.cut(_:))
        case ("c", false): #selector(NSText.copy(_:))
        case ("a", false): #selector(NSText.selectAll(_:))
        case ("z", false): Selector(("undo:"))
        case ("z", true): Selector(("redo:"))
        default: nil
        }
    }
}
