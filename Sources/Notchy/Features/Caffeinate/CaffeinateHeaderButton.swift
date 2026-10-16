import SwiftUI

/// The Keep Awake button in the island header: a 30-pt black capsule with a 14-pt cup. While
/// the Mac is held awake the cup fills and turns yellow, the only sign the row gives that a
/// session is running. A click opens the duration popover. Renders nothing while the feature
/// or its header icon is switched off.
struct CaffeinateHeaderButton: View {
    static let glyphSize: CGFloat = 14.0

    @ObservedObject private var controller: CaffeinateController
    @ObservedObject private var settings: CaffeinateSettings
    @State private var isPopoverPresented = false

    init(controller: CaffeinateController = .shared) {
        _controller = ObservedObject(wrappedValue: controller)
        _settings = ObservedObject(wrappedValue: controller.settings)
    }

    var body: some View {
        if settings.isEnabled, settings.showHeaderButton {
            button
        }
    }

    private var button: some View {
        Button {
            withAnimation(.smooth) { isPopoverPresented.toggle() }
        } label: {
            Capsule()
                .fill(.black)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: controller.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .foregroundStyle(controller.isActive ? Color.yellow : Color.white)
                        .font(.system(size: Self.glyphSize, weight: .medium))
                        .frame(width: 20, height: 20)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            CaffeinatePopover(controller: controller) { isPopoverPresented = false }
        }
        .onChange(of: isPopoverPresented) { _, presented in
            controller.setPopoverPresented(presented)
        }
        .onDisappear {
            isPopoverPresented = false
            controller.setPopoverPresented(false)
        }
        .help(helpText)
        .accessibilityLabel("Keep Awake")
        .accessibilityValue(controller.statusText)
    }

    private var helpText: String {
        controller.isActive ? "Keep Awake: \(controller.statusText)" : "Keep this Mac awake"
    }
}
