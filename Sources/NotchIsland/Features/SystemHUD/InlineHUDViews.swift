import SwiftUI

/// Left column of the inline volume / brightness / microphone HUD: glyph and label (Atoll
/// `InlineHUD`).
struct InlineHUDLeadingWing: View {
    @ObservedObject var presenter: SystemHUDPresenter
    /// Atoll's column width; the content keeps it even when the host's wing is a little
    /// narrower (see `InlineHUDMetrics`).
    let columnWidth: CGFloat
    let wingWidth: CGFloat

    var body: some View {
        HStack(spacing: InlineHUDMetrics.iconLabelSpacing) {
            icon
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .allowsTightening(true)
                .contentTransition(.numericText())
                .foregroundStyle(.white)
        }
        .foregroundStyle(.white)
        .frame(width: columnWidth, alignment: .leading)
        .frame(width: wingWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var icon: some View {
        switch presenter.kind {
        case .volume:
            Image(systemName: SystemHUDPresenter.volumeSymbolName(
                for: presenter.level,
                isBluetooth: presenter.isBluetoothOutput
            ))
            .font(.body)
            .contentTransition(.interpolate)
            .frame(width: InlineHUDMetrics.iconSize.width, height: InlineHUDMetrics.iconSize.height, alignment: .leading)
        case .brightness:
            Image(systemName: SystemHUDPresenter.brightnessSymbolName(for: presenter.level))
                .font(.body)
                .contentTransition(.interpolate)
                .frame(width: InlineHUDMetrics.iconSize.width, height: InlineHUDMetrics.iconSize.height)
        case .microphone:
            Image(systemName: SystemHUDPresenter.microphoneSymbolName(isMuted: presenter.level <= 0))
                .font(.body)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.interpolate)
                .frame(width: InlineHUDMetrics.iconSize.width, height: InlineHUDMetrics.iconSize.height)
        }
    }

    private var label: String {
        switch presenter.kind {
        case .volume: "Volume"
        case .brightness: "Brightness"
        case .microphone: "Mic"
        }
    }

    private var accessibilityText: String {
        switch presenter.kind {
        case .volume:
            presenter.level <= 0 ? "Volume muted" : "Volume \(Int((presenter.level * 100).rounded())) percent"
        case .brightness:
            "Brightness \(Int((presenter.level * 100).rounded())) percent"
        case .microphone:
            presenter.level <= 0 ? "Microphone muted" : "Microphone unmuted"
        }
    }
}

/// Right column of the inline HUD: level bar and percentage, "muted", or the microphone
/// state. Brightness has no muted state and its bar is display-only (there is no public API
/// to set a built-in display's brightness).
struct InlineHUDTrailingWing: View {
    @ObservedObject var presenter: SystemHUDPresenter
    let columnWidth: CGFloat
    let wingWidth: CGFloat
    var onDrag: ((CGFloat) -> Void)?

    var body: some View {
        HStack {
            switch presenter.kind {
            case .microphone:
                Text(presenter.level <= 0 ? "muted" : "unmuted")
                    .font(.body)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentTransition(.interpolate)
            case .volume:
                volumeContent
            case .brightness:
                HStack(spacing: 6) {
                    SystemHUDProgressBar(
                        value: presenter.level,
                        isVolume: false,
                        isInline: true,
                        settings: presenter.settings
                    )
                    SystemHUDPercentageLabel(value: presenter.level, settings: presenter.settings)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.trailing, columnWidth > 0 ? InlineHUDMetrics.trailingPadding : 0)
        .frame(width: columnWidth)
        .frame(width: wingWidth, alignment: .trailing)
        .frame(maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
    }

    private var volumeContent: some View {
        let isMuted = presenter.level <= 0
        return Group {
            if isMuted {
                Text("muted")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .multilineTextAlignment(.trailing)
                    .contentTransition(.numericText())
            } else {
                HStack(spacing: 6) {
                    SystemHUDProgressBar(
                        value: presenter.level,
                        isVolume: true,
                        isInline: true,
                        onDrag: onDrag,
                        settings: presenter.settings
                    )
                    SystemHUDPercentageLabel(value: presenter.level, settings: presenter.settings)
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.smooth(duration: 0.2), value: isMuted)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Left column of the Caps Lock indicator: the tinted glyph, sliding out of the notch.
struct CapsLockLeadingWing: View {
    @ObservedObject var settings: SystemHUDSettings
    let columnWidth: CGFloat
    let wingWidth: CGFloat
    @State private var hasAppeared = false

    var body: some View {
        Image(systemName: "capslock.fill")
            .font(.body)
            .symbolRenderingMode(.hierarchical)
            .contentTransition(.interpolate)
            .foregroundStyle(settings.capsLockTint.color)
            .frame(width: InlineHUDMetrics.iconSize.width, height: InlineHUDMetrics.iconSize.height)
            .offset(x: hasAppeared ? 0 : columnWidth)
            .opacity(hasAppeared ? 1 : 0)
            .frame(width: columnWidth, alignment: .leading)
            .frame(width: wingWidth, alignment: .leading)
            .frame(maxHeight: .infinity)
            .environment(\.colorScheme, .dark)
            .onAppear {
                withAnimation(CapsLockMonitor.toggleAnimation) { hasAppeared = true }
            }
            .accessibilityLabel("Caps Lock on")
    }
}

/// Right column of the Caps Lock indicator: the optional "Caps Lock" label.
struct CapsLockTrailingWing: View {
    @ObservedObject var settings: SystemHUDSettings
    let columnWidth: CGFloat
    let wingWidth: CGFloat
    @State private var hasAppeared = false

    var body: some View {
        HStack {
            if settings.showCapsLockLabel {
                Text("Caps Lock")
                    .foregroundStyle(settings.capsLockTint.color)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentTransition(.interpolate)
            }
        }
        .padding(.trailing, columnWidth > 0 ? InlineHUDMetrics.trailingPadding : 0)
        .frame(width: columnWidth)
        .offset(x: hasAppeared ? 0 : columnWidth)
        .opacity(hasAppeared ? 1 : 0)
        .frame(width: wingWidth, alignment: .trailing)
        .frame(maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .onAppear {
            withAnimation(CapsLockMonitor.toggleAnimation) { hasAppeared = true }
        }
    }
}
