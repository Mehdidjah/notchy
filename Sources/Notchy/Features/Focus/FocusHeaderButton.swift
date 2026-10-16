import SwiftUI

/// The Focus glyph in the open island's header: a 30-pt black capsule
/// with the active mode's glyph, 12-pt semibold in a 24-pt frame, in the mode's colour.
/// Informational only; renders nothing unless a Focus is on and the indicator is enabled.
struct FocusHeaderButton: View {
    @ObservedObject private var monitor: FocusMonitor
    @ObservedObject private var settings: FocusSettings

    init(monitor: FocusMonitor = .shared) {
        _monitor = ObservedObject(wrappedValue: monitor)
        _settings = ObservedObject(wrappedValue: monitor.settings)
    }

    var body: some View {
        if settings.enableDoNotDisturbDetection, settings.showDoNotDisturbIndicator, monitor.isActive {
            let appearance = monitor.appearance
            Capsule()
                .fill(.black)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: appearance.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(appearance.accent)
                        .frame(width: 24, height: 24)
                        .contentTransition(.opacity)
                }
                .transition(.opacity)
                .help(accessibilityText(kind: appearance.kind))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText(kind: appearance.kind))
        }
    }

    private func accessibilityText(kind: FocusModeKind) -> String {
        let trimmed = monitor.modeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = kind == .doNotDisturb ? "Focus" : (trimmed.isEmpty ? kind.displayName : trimmed)
        return "Focus active: \(name)"
    }
}
