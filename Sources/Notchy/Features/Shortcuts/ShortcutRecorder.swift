import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The click-to-record shortcut field Atoll's Settings use (KeyboardShortcuts'
/// `Recorder`): a native, centred `NSSearchField` at least 130 pt wide with the magnifier
/// removed. It reads “Record Shortcut” when empty and shows the binding (⇧⌘V) with the
/// search field's own clear button; once clicked it shows the system focus ring, hides the
/// caret and reads “Press Shortcut” until a keystroke arrives.
///
/// While listening: Escape stops, Tab stops and moves focus on, Delete clears, a click
/// outside stops, a bare key or Shift-only keystroke beeps, and unusable keystrokes raise
/// Atoll's alerts before listening again. Global hot keys are paused meanwhile so pressing
/// an existing shortcut records it instead of firing it.
struct ShortcutRecorder: View {
    /// KeyboardShortcuts' `minimumWidth`.
    static let width: CGFloat = 130

    let action: ShortcutAction

    @ObservedObject private var manager: ShortcutsManager
    @ObservedObject private var settings: ShortcutsSettings
    @ObservedObject private var layout: KeyboardLayout
    @Environment(\.isEnabled) private var isEnabled

    init(action: ShortcutAction, manager: ShortcutsManager = .shared, layout: KeyboardLayout = .shared) {
        self.action = action
        _manager = ObservedObject(wrappedValue: manager)
        _settings = ObservedObject(wrappedValue: manager.settings)
        _layout = ObservedObject(wrappedValue: layout)
    }

    var body: some View {
        _ = layout.revision
        return RecorderFieldRepresentable(
            action: action,
            manager: manager,
            text: settings.shortcut(for: action)?.displayString ?? "",
            isEnabled: isEnabled
        )
    }
}

private struct RecorderFieldRepresentable: NSViewRepresentable {
    let action: ShortcutAction
    let manager: ShortcutsManager
    let text: String
    let isEnabled: Bool

    func makeNSView(context: Context) -> ShortcutRecorderField {
        let field = ShortcutRecorderField(action: action, manager: manager)
        field.apply(text: text, isEnabled: isEnabled)
        return field
    }

    func updateNSView(_ field: ShortcutRecorderField, context: Context) {
        field.shortcutAction = action
        field.apply(text: text, isEnabled: isEnabled)
    }

    static func dismantleNSView(_ field: ShortcutRecorderField, coordinator: ()) {
        field.stopRecording()
    }
}

/// The AppKit half of `ShortcutRecorder`, modelled on KeyboardShortcuts' `RecorderCocoa`.
final class ShortcutRecorderField: NSSearchField, NSSearchFieldDelegate {
    static let recordPlaceholder = "Record Shortcut"
    static let listeningPlaceholder = "Press Shortcut"
    /// Clicks this close to the field still count as inside it.
    private static let clickMargin: CGFloat = 3

    var shortcutAction: ShortcutAction
    private weak var manager: ShortcutsManager?

    /// The search field's own clear button, detached while there is nothing to clear so
    /// the centred placeholder is not pushed off-centre by its reserved space.
    private var clearButtonCell: NSButtonCell?
    private var eventMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []
    /// False just after the window becomes key, so the field never takes initial focus.
    private var allowsKeyView = false
    private(set) var isRecording = false
    /// Keystrokes the user already chose to keep despite an alert, for the current attempt.
    private var acceptedIssues: [ShortcutIssue] = []
    private var pendingShortcut: Shortcut?

    init(action: ShortcutAction, manager: ShortcutsManager) {
        shortcutAction = action
        self.manager = manager
        super.init(frame: .zero)
        delegate = self
        placeholderString = Self.recordPlaceholder
        alignment = .center
        (cell as? NSSearchFieldCell)?.searchButtonCell = nil
        wantsLayer = true
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        clearButtonCell = (cell as? NSSearchFieldCell)?.cancelButtonCell
        showsClearButton = false
        // The clear button also sends the field's action, which covers a click while the
        // field is not being edited (no text-change callback then).
        self.target = self
        self.action = #selector(searchFieldSentAction(_:))
        setAccessibilityHelp("Click, then press the new shortcut. Delete clears it, Escape cancels.")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var canBecomeKeyView: Bool { allowsKeyView }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width = ShortcutRecorder.width
        return size
    }

    private var showsClearButton: Bool {
        get { (cell as? NSSearchFieldCell)?.cancelButtonCell != nil }
        set {
            guard newValue != showsClearButton else { return }
            (cell as? NSSearchFieldCell)?.cancelButtonCell = newValue ? clearButtonCell : nil
        }
    }

    /// Mirrors the stored binding and the SwiftUI enabled state.
    func apply(text: String, isEnabled enabled: Bool) {
        if isEnabled != enabled {
            if !enabled { blur() }
            isEnabled = enabled
        }
        if stringValue != text {
            stringValue = text
        }
        showsClearButton = !stringValue.isEmpty
    }

    // MARK: - Window and focus

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeWindowObservers()
        guard let window else {
            stopRecording()
            return
        }
        let center = NotificationCenter.default
        windowObservers = [
            // Settings windows hide rather than close, so stop when the window stops being key.
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.stopRecording()
                    if self.window?.firstResponder === self.currentEditor() {
                        self.window?.makeFirstResponder(nil)
                    }
                }
            },
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.preventInitialFocus() }
            },
        ]
        preventInitialFocus()
    }

    private func preventInitialFocus() {
        allowsKeyView = false
        Task { @MainActor [weak self] in
            self?.allowsKeyView = true
        }
    }

    private func removeWindowObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers = []
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        guard became else { return became }
        startRecording()
        return became
    }

    private func focus() {
        window?.makeFirstResponder(self)
    }

    private func blur() {
        if let window, window.firstResponder === currentEditor() || window.firstResponder === self {
            window.makeFirstResponder(nil)
        }
        stopRecording()
    }

    // MARK: - Recording

    private func startRecording() {
        guard !isRecording, let manager else { return }
        isRecording = true
        placeholderString = Self.listeningPlaceholder
        showsClearButton = !stringValue.isEmpty
        (currentEditor() as? NSTextView)?.insertionPointColor = .clear
        manager.beginRecording(shortcutAction)
        installMonitor()
    }

    /// Stops listening without changing the binding. Safe to call when idle.
    func stopRecording() {
        removeMonitor()
        placeholderString = Self.recordPlaceholder
        showsClearButton = !stringValue.isEmpty
        guard isRecording else { return }
        isRecording = false
        manager?.endRecording()
    }

    private func installMonitor() {
        removeMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseUp, .rightMouseUp]
        ) { [weak self] event in
            let input = RecorderInput(event)
            let verdict = MainActor.assumeIsolated { self?.handle(input) ?? .pass }
            return verdict == .pass ? event : nil
        }
    }

    private func removeMonitor() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    private enum Verdict: Sendable {
        case pass
        case swallow
    }

    private func handle(_ input: RecorderInput) -> Verdict {
        guard isRecording else { return .pass }

        if input.kind == .mouseUp {
            let inside = input.windowNumber == window?.windowNumber
                && bounds.insetBy(dx: -Self.clickMargin, dy: -Self.clickMargin)
                    .contains(convert(input.locationInWindow, from: nil))
            if inside { return .swallow }
            blur()
            return .pass
        }
        guard input.kind == .keyDown else { return .pass }

        if input.modifiers.isEmpty {
            switch Int(input.keyCode) {
            case kVK_Tab:
                // Let the Tab through so it moves focus to the next control.
                blur()
                return .pass
            case kVK_Escape:
                blur()
                return .swallow
            case kVK_Delete, kVK_ForwardDelete:
                clear()
                return .swallow
            default:
                break
            }
        }

        acceptedIssues = []
        submit(Shortcut(keyCode: UInt32(input.keyCode), modifiers: input.modifiers))
        return .swallow
    }

    /// Saves `shortcut` or, when something stands in the way, beeps or explains why.
    private func submit(_ shortcut: Shortcut) {
        guard let manager else { return }
        guard let issue = manager.assign(shortcut, to: shortcutAction, accepting: acceptedIssues) else {
            stringValue = shortcut.displayString
            showsClearButton = true
            acceptedIssues = []
            pendingShortcut = nil
            blur()
            return
        }
        if issue == .needsModifier {
            NSSound.beep()
            return
        }
        pendingShortcut = shortcut
        blur()
        presentAlert(for: issue)
    }

    private func clear() {
        stringValue = ""
        manager?.clear(shortcutAction)
    }

    // MARK: - Alerts

    /// Atoll's recorder alerts, as a warning sheet on the Settings window. “OK” returns to
    /// listening; “Use Anyway” (system shortcut) or “Reassign” (another Notchy action)
    /// keeps the keystroke.
    private func presentAlert(for issue: ShortcutIssue) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = issue.message
        if let informative = issue.informativeText {
            alert.informativeText = informative
        }
        alert.addButton(withTitle: "OK")
        if issue.canOverride {
            if case .usedByAction = issue {
                alert.addButton(withTitle: "Reassign")
            } else {
                alert.addButton(withTitle: "Use Anyway")
            }
        }

        if let window, window.isVisible, window.attachedSheet == nil {
            alert.beginSheetModal(for: window) { [weak self] response in
                MainActor.assumeIsolated { self?.alertDidEnd(response, issue: issue) }
            }
        } else {
            alertDidEnd(alert.runModal(), issue: issue)
        }
    }

    private func alertDidEnd(_ response: NSApplication.ModalResponse, issue: ShortcutIssue) {
        guard issue.canOverride, response == .alertSecondButtonReturn, let shortcut = pendingShortcut else {
            // Back to listening for a better keystroke, as Atoll's recorder does.
            pendingShortcut = nil
            acceptedIssues = []
            focus()
            return
        }
        acceptedIssues.append(issue)
        submit(shortcut)
    }

    // MARK: - Clear button and NSSearchFieldDelegate

    @objc private func searchFieldSentAction(_ sender: Any?) {
        // Only the clear button can empty the text here; ignore actions for a binding that
        // is already gone (after Delete, say) so they never restart listening.
        guard stringValue.isEmpty, manager?.settings.shortcut(for: shortcutAction) != nil else { return }
        clearButtonEmptiedText()
    }

    func controlTextDidChange(_ notification: Notification) {
        if stringValue.isEmpty {
            clearButtonEmptiedText()
        } else {
            showsClearButton = true
        }
    }

    /// The clear button emptied the text: drop the binding, then listen again so the
    /// placeholder re-centres, as KeyboardShortcuts does.
    private func clearButtonEmptiedText() {
        manager?.clear(shortcutAction)
        showsClearButton = false
        focus()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        stopRecording()
    }
}

/// The parts of an `NSEvent` the recorder needs, copied out so they cross isolation safely.
private struct RecorderInput: Sendable {
    enum Kind: Sendable {
        case keyDown
        case mouseUp
        case other
    }

    let kind: Kind
    let keyCode: UInt16
    let modifiers: ShortcutModifiers
    let locationInWindow: CGPoint
    let windowNumber: Int

    init(_ event: NSEvent) {
        modifiers = ShortcutModifiers(event.modifierFlags)
        locationInWindow = event.locationInWindow
        windowNumber = event.windowNumber
        switch event.type {
        case .keyDown:
            kind = .keyDown
            keyCode = event.keyCode
        case .leftMouseUp, .rightMouseUp:
            kind = .mouseUp
            keyCode = 0
        default:
            kind = .other
            keyCode = 0
        }
    }
}
