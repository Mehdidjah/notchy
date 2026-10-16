import AppKit
import SwiftUI

/// Download detection rows for the Settings window. Returns a `Section`; embed it in a `Form`.
///
/// Laid out like Atoll's Downloads pane: the detection switch, the indicator style as two
/// preview cards (a live bar and a live ring), then the speed switch with its explanation.
struct DownloadsSettingsSection: View {
    @ObservedObject private var settings: DownloadsSettings
    @ObservedObject private var watcher: DownloadWatcher

    init(watcher: DownloadWatcher = .shared) {
        _watcher = ObservedObject(wrappedValue: watcher)
        _settings = ObservedObject(wrappedValue: watcher.settings)
    }

    var body: some View {
        Section {
            Toggle("Enable download detection", isOn: $settings.enableDownloadDetection)

            VStack(alignment: .leading, spacing: 12) {
                Text("Download indicator style")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(settings.enableDownloadDetection ? Color.primary : Color.secondary)

                HStack(spacing: 16) {
                    ForEach(DownloadIndicatorStyle.allCases) { style in
                        DownloadStyleCard(
                            style: style,
                            isSelected: settings.indicatorStyle == style,
                            isDisabled: !settings.enableDownloadDetection
                        ) {
                            settings.indicatorStyle = style
                        }
                    }
                }

                Text("A bar that fills as the download runs, or a spinning ring.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Show download speed", isOn: $settings.showDownloadSpeed)
                    .disabled(!settings.enableDownloadDetection)
                Text("Adds the current rate beside the indicator, measured from how fast the files in your Downloads folder are growing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if settings.enableDownloadDetection, watcher.isMonitoring, !watcher.hasFolderAccess {
                LabeledContent("Downloads folder") {
                    Button("Open Privacy & Security") { Self.openFilesAndFoldersSettings() }
                }
                Text("Notchy cannot read your Downloads folder. Allow it under Files and Folders.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Download Detection")
        } footer: {
            Text("Shows a live activity in the notch while a file is downloading. Works with Safari, Firefox, and Chrome and the browsers built on it: Edge, Brave, Arc, Vivaldi and Opera. Only your Downloads folder is watched, so a file saved anywhere else will not appear.")
        }
    }

    private static func openFilesAndFoldersSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// One indicator-style choice: an 80 x 60 rounded card with a live preview and its name
/// underneath. The selected card gets a 2-pt accent border on a faint accent fill; hovering an
/// unselected card tints it faintly and gives it a hairline border.
private struct DownloadStyleCard: View {
    let style: DownloadIndicatorStyle
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
                        )

                    switch style {
                    case .progress:
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                            .frame(width: 40)
                    case .circle:
                        DownloadRing(fraction: nil)
                    }
                }
                .frame(width: 80, height: 60)

                Text(style.label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 100)
                    .foregroundStyle(isDisabled ? .secondary : .primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .onHover { hovering in
            guard !isDisabled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { isHovering = hovering }
        }
        .accessibilityLabel("\(style.label) indicator")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var backgroundColor: Color {
        if isDisabled { return Color(nsColor: .controlBackgroundColor) }
        if isSelected { return Color.accentColor.opacity(0.1) }
        if isHovering { return Color.primary.opacity(0.05) }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        if isSelected { return Color.accentColor }
        if isHovering { return Color.primary.opacity(0.1) }
        return Color.clear
    }
}
