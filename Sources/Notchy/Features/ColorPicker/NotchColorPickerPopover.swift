import AppKit
import SwiftUI

/// The 240-pt HUD popover under the eyedropper: Pick Color, the recent-colour grid, and the
/// selected colour's formats with copy buttons. Tapping a swatch selects it and copies the
/// default format; the format rows copy one representation each.
struct NotchColorPickerPopover: View {
    @ObservedObject private var service: ColorPickerService
    @ObservedObject private var settings: ColorPickerSettings
    @State private var selectedColorID: PickedColor.ID?
    @State private var hoveredColorID: PickedColor.ID?
    @State private var isConfirmingClear = false

    private let onDismiss: () -> Void

    static let width: CGFloat = 240
    private static let swatchSize: CGFloat = 24
    private static let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 6)

    init(service: ColorPickerService, onDismiss: @escaping () -> Void) {
        _service = ObservedObject(wrappedValue: service)
        _settings = ObservedObject(wrappedValue: service.settings)
        self.onDismiss = onDismiss
    }

    private var recentColors: [PickedColor] { service.recentColors }

    /// The tapped swatch, or the newest colour until one is tapped.
    private var selectedColor: PickedColor? {
        recentColors.first { $0.id == selectedColorID } ?? recentColors.first
    }

    private var visibleFormats: [PickedColorFormat] {
        settings.showAllFormats ? PickedColorFormat.allCases : [.hex]
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            pickButton
            if recentColors.isEmpty {
                emptyState
            } else {
                recentSection
                if let selectedColor {
                    ColorPickerDetailCard(
                        color: selectedColor,
                        formats: visibleFormats,
                        onCopy: { format in service.copy(selectedColor, as: format) }
                    )
                    .id(selectedColor.id)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
        }
        .padding(16)
        .frame(width: Self.width)
        .background(ColorPickerHUDBackground())
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.2), value: selectedColor?.id)
        .animation(.easeInOut(duration: 0.2), value: recentColors.count)
        .animation(.easeInOut(duration: 0.2), value: isConfirmingClear)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "eyedropper.halffull")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                Text("Color Picker")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
            .accessibilityLabel("Close")
        }
    }

    private var pickButton: some View {
        Button {
            onDismiss()
            service.pick()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                Text(service.isPicking ? "Picking…" : "Pick Color")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(service.isPicking)
        .pointingHandCursor()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "eyedropper")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No Colors Yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
            Text("Click Pick Color to sample a color from anywhere on screen.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            recentHeader
            LazyVGrid(columns: Self.gridColumns, spacing: 4) {
                ForEach(recentColors) { color in
                    PickedColorSwatch(
                        color: color,
                        size: Self.swatchSize,
                        isSelected: color.id == selectedColor?.id,
                        isHovered: color.id == hoveredColorID
                    )
                    .onHover { hovering in
                        if hovering { hoveredColorID = color.id }
                        else if hoveredColorID == color.id { hoveredColorID = nil }
                    }
                    .onTapGesture {
                        selectedColorID = color.id
                        service.copy(color, as: settings.defaultFormat, haptic: true)
                    }
                    .contextMenu {
                        Button("Copy HEX", systemImage: "doc.on.doc") { service.copy(color, as: .hex) }
                        Button("Delete", systemImage: "trash", role: .destructive) { service.remove(color) }
                    }
                    .help(color.hexString)
                    .accessibilityLabel("Color \(color.hexString)")
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
    }

    @ViewBuilder
    private var recentHeader: some View {
        if isConfirmingClear {
            HStack(spacing: 8) {
                Text("Clear all \(service.history.count) colors?")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Button("Cancel") { isConfirmingClear = false }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button("Clear") {
                    isConfirmingClear = false
                    service.clearHistory()
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        } else {
            HStack {
                Text("Recent Colors")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { isConfirmingClear = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clear color history")
                .accessibilityLabel("Clear color history")
            }
        }
    }
}

/// A round swatch: white and black hairlines keep light and dark colours visible on any
/// background; hover lifts it slightly and the selected one gets the thicker ring.
struct PickedColorSwatch: View {
    let color: PickedColor
    var size: CGFloat = 24
    var isSelected = false
    var isHovered = false

    var body: some View {
        Circle()
            .fill(color.color)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: isSelected || isHovered ? 2 : 1))
            .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: isHovered ? 4 : 2, x: 0, y: isHovered ? 2 : 1)
            .scaleEffect(isHovered ? 1.1 : 1)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
            .contentShape(Circle())
    }
}

/// The selected colour's card: swatch, age, and one row per format with a copy button that
/// turns into a green checkmark for 1.5 seconds.
struct ColorPickerDetailCard: View {
    let color: PickedColor
    let formats: [PickedColorFormat]
    let onCopy: (PickedColorFormat) -> Void

    @State private var copiedFormat: PickedColorFormat?
    @State private var copiedResetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PickedColorSwatch(color: color)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Picked Color")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(color.relativeAge())
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()
                .overlay(Color.gray.opacity(0.3))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(formats) { format in
                    ColorFormatRow(
                        name: format.displayName,
                        value: color.formatted(as: format),
                        justCopied: copiedFormat == format,
                        onCopy: { copy(format) }
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 8)
        .onDisappear { copiedResetTask?.cancel() }
    }

    private func copy(_ format: PickedColorFormat) {
        onCopy(format)
        withAnimation(.easeInOut(duration: 0.2)) { copiedFormat = format }
        copiedResetTask?.cancel()
        copiedResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { copiedFormat = nil }
        }
    }
}

/// One format line: monospaced name and value, copy glyph on hover, tap anywhere to copy.
struct ColorFormatRow: View {
    let name: String
    let value: String
    let justCopied: Bool
    let onCopy: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            Image(systemName: justCopied ? "checkmark.circle.fill" : "doc.on.doc")
                .font(.system(size: 10))
                .foregroundStyle(justCopied ? Color.green : Color.blue)
                .opacity(isHovered || justCopied ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(isHovered ? Color.white.opacity(0.1) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) { isHovered = hovering }
        }
        .onTapGesture(perform: onCopy)
        .help("Copy \(name)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(value)")
        .accessibilityHint("Copies this value")
        .accessibilityAddTraits(.isButton)
    }
}

/// The translucent dark material behind HUD-style panels.
struct ColorPickerHUDBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct PointingHandCursorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

extension View {
    /// Shows the hand cursor over a control, as the Pick Color button does.
    fileprivate func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }
}
