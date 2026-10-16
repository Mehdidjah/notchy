import AppKit
import SwiftUI

/// The eyedropper in the island header: a 30-pt black capsule like its neighbours. A click
/// samples a colour from the screen; a right-click, control-click or half-second press opens
/// the recent-colours popover. Renders nothing while the feature or the button is switched off.
struct ColorPickerHeaderButton: View {
    @ObservedObject private var service: ColorPickerService
    @ObservedObject private var settings: ColorPickerSettings
    @State private var isPopoverPresented = false

    init(service: ColorPickerService = .shared) {
        _service = ObservedObject(wrappedValue: service)
        _settings = ObservedObject(wrappedValue: service.settings)
    }

    var body: some View {
        if settings.isEnabled, settings.showHeaderButton {
            capsule
        }
    }

    private var capsule: some View {
        Capsule()
            .fill(.black)
            .frame(width: 30, height: 30)
            .overlay {
                Image(systemName: "eyedropper")
                    .foregroundStyle(.white)
                    .font(.system(size: 14.3, weight: .medium))
                    .frame(width: 20, height: 20)
                    .opacity(service.isPicking ? 0.55 : 1)
                    .animation(.easeInOut(duration: 0.2), value: service.isPicking)
            }
            .contentShape(Capsule())
            .overlay {
                ColorPickerPressCatcher(
                    onClick: { service.pick() },
                    onSecondaryAction: { isPopoverPresented = true }
                )
            }
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                NotchColorPickerPopover(service: service) { isPopoverPresented = false }
            }
            .onChange(of: isPopoverPresented) { _, presented in
                service.setPopoverPresented(presented)
            }
            .help("Pick a color. Right-click for recent colors.")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pick a color")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { service.pick() }
            .accessibilityAction(named: "Show recent colors") { isPopoverPresented = true }
    }
}

/// Routes mouse input on the capsule: a plain click, a right- or control-click, and a press
/// held long enough to count as a long press. SwiftUI gestures cannot see the right button, so
/// this sits as a transparent AppKit view over the capsule.
private struct ColorPickerPressCatcher: NSViewRepresentable {
    var onClick: () -> Void
    var onSecondaryAction: () -> Void

    func makeNSView(context: Context) -> PressCatcherView {
        let view = PressCatcherView()
        view.onClick = onClick
        view.onSecondaryAction = onSecondaryAction
        return view
    }

    func updateNSView(_ view: PressCatcherView, context: Context) {
        view.onClick = onClick
        view.onSecondaryAction = onSecondaryAction
    }
}

private final class PressCatcherView: NSView {
    static let longPressDuration: Duration = .milliseconds(500)
    /// Pointer travel that turns a press into a drag and cancels it.
    static let dragSlop: CGFloat = 4

    var onClick: (() -> Void)?
    var onSecondaryAction: (() -> Void)?

    private var pressTask: Task<Void, Never>?
    private var longPressFired = false
    private var pressOrigin: NSPoint = .zero

    override var acceptsFirstResponder: Bool { false }

    /// The island lives in a non-activating panel; the first click must count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onSecondaryAction?()
            return
        }
        longPressFired = false
        pressOrigin = convert(event.locationInWindow, from: nil)
        pressTask?.cancel()
        pressTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.longPressDuration)
            guard !Task.isCancelled, let self else { return }
            self.longPressFired = true
            self.onSecondaryAction?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if hypot(location.x - pressOrigin.x, location.y - pressOrigin.y) > Self.dragSlop {
            cancelPress()
        }
    }

    override func mouseUp(with event: NSEvent) {
        let wasPending = pressTask != nil
        let firedLongPress = longPressFired
        cancelPress()
        let location = convert(event.locationInWindow, from: nil)
        guard wasPending, !firedLongPress, bounds.contains(location) else { return }
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        cancelPress()
        onSecondaryAction?()
    }

    private func cancelPress() {
        pressTask?.cancel()
        pressTask = nil
    }
}
