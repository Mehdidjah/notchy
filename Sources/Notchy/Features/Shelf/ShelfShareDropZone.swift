import AppKit
import SwiftUI

/// The square on the left of the shelf: drop files on it to AirDrop them (or open the share
/// menu), click it to send what is on the shelf. A small switch in its corner picks the
/// service.
struct ShelfShareDropZone: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var settings: ShelfSettings
    let hub: ShelfInteractionHub

    @StateObject private var anchor = ShelfViewAnchor()
    @State private var isTargeted = false
    @State private var isProcessing = false
    @State private var isSwitchHovered = false

    @MainActor private static let airDropIcon: NSImage? = NSSharingService(named: .sendViaAirDrop)?.image

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.35), Color.black.opacity(0.20)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isTargeted ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.1),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
                        )
                )
                .shadow(color: Color.black.opacity(0.6), radius: 6, x: 0, y: 2)

            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(isTargeted ? 0.11 : 0.09))
                        .frame(width: 55, height: 55)
                    targetIcon
                        .frame(width: 34, height: 34)
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.gray)
                        .scaleEffect(isTargeted ? 1.06 : 1.0)
                        .animation(.spring(response: 0.36, dampingFraction: 0.7), value: isTargeted)
                }
                Text(settings.shareTarget.label)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(18)

            VStack {
                HStack {
                    Spacer()
                    targetSwitch
                        .padding(.trailing, 8)
                        .padding(.top, 8)
                }
                Spacer()
            }

            if isProcessing {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .tint(.white)
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .background(ShelfAnchorView(anchor: anchor))
        .onDrop(of: ShelfDropImporter.acceptedTypes, isTargeted: $isTargeted) { providers in
            shareDropped(providers)
            return true
        }
        .onTapGesture { shareShelf() }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(settings.shareTarget.label)
        .accessibilityHint(helpText)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var targetIcon: some View {
        if settings.shareTarget == .airDrop, let icon = Self.airDropIcon {
            Image(nsImage: icon)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
        } else {
            Image(systemName: settings.shareTarget.symbolName)
                .resizable()
                .scaledToFit()
        }
    }

    private var targetSwitch: some View {
        Menu {
            Picker("Quick share with", selection: $settings.shareTarget) {
                ForEach(ShelfShareTarget.allCases) { target in
                    Label(target.label, systemImage: target.symbolName).tag(target)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "switch.2")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 14, height: 14)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSwitchHovered ? Color.white.opacity(0.12) : Color.clear)
                )
                .foregroundStyle(isSwitchHovered ? Color.accentColor : Color.gray)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isSwitchHovered = $0 }
        .help("Quick Share settings")
    }

    private var helpText: String {
        switch settings.shareTarget {
        case .airDrop: "Drop files here to AirDrop them, or click to AirDrop the shelf"
        case .shareMenu: "Drop files here to share them, or click to share the shelf"
        }
    }

    /// Files dropped here are shared, not shelved. Anything the importer had to write to
    /// disk for the share is deleted once the share is over.
    private func shareDropped(_ providers: [NSItemProvider]) {
        guard !isProcessing else { return }
        isProcessing = true
        let importer = store.importer
        let target = settings.shareTarget
        let dropped = ShelfDroppedProviders(providers)
        Task {
            let items = await importer.items(from: dropped)
            isProcessing = false
            let scratch = items.filter(\.isTemporary).compactMap(\.fileURL)
            let bundle = store.shareBundle(for: items, filesOnly: target == .airDrop)
            let cleanup = scratch + bundle.scratchURLs
            guard !bundle.isEmpty else {
                store.discardScratchFiles(cleanup)
                return
            }
            hub.sharing.share(bundle.objects, via: target, from: anchor.view) { [weak store] in
                store?.discardScratchFiles(cleanup)
            }
        }
    }

    /// Click: the selection, or the whole shelf. With nothing shelved, AirDrop asks for files.
    private func shareShelf() {
        let items = store.hasSelection ? store.selectedItems : store.items
        if items.isEmpty {
            guard settings.shareTarget == .airDrop else { return }
            chooseFilesForAirDrop()
            return
        }
        hub.share(items, from: anchor.view)
    }

    private func chooseFilesForAirDrop() {
        hub.holdOpen?()
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = "Choose files to send with AirDrop"
        panel.begin { response in
            Task { @MainActor in
                let urls = response == .OK ? panel.urls : []
                if urls.isEmpty || !hub.sharing.airDrop(urls) {
                    hub.releaseHold?()
                }
            }
        }
    }
}
