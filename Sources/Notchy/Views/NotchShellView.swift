import SwiftUI

/// The open island: a header row at notch height (tab icons on the left, a black spacer
/// that hides the hardware notch in the middle, round buttons on the right) above the
/// selected tab's content, which slides in the direction of travel between tabs.
struct NotchShellView: View {
    @ObservedObject var model: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            NotchHeaderView(model: model)
                .frame(height: max(24, model.notchGeometry.topInset))

            ZStack {
                if model.state.showsShelfContent {
                    tabContent
                        .id(model.selectedTab)
                        .transition(tabSwitchTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.smooth(duration: 0.3), value: model.selectedTab)
        }
        .padding(.horizontal, NotchSilhouette.openTopFlare - 5)
        .padding(.horizontal, NotchTab.openHorizontalInset)
        .padding(.bottom, NotchTab.openBottomInset)
        .foregroundStyle(.white)
        .onExitCommand(perform: model.escape)
    }

    @ViewBuilder
    private var tabContent: some View {
        // Pure SwiftUI tabs are drawn at the compact content scale; tabs with embedded AppKit
        // views (Notes' editor, Face Check's camera, Shelf's tiles) size themselves instead.
        switch model.selectedTab {
        case .home:
            NotchHomeTabView(model: model).islandScaled()
        case .notes:
            NotchNotesTabView(model: model)
        case .face:
            NotchFaceTabView(model: model)
        case .claude:
            NotchClaudeTabView(model: model)
        case .clipboard:
            NotchClipboardTabView(model: model).islandScaled()
        case .shelf:
            NotchShelfTabView(model: model)
        case .timer:
            NotchTimerTabView(model: model).islandScaled()
        case .stats:
            NotchStatsTabView(model: model).islandScaled()
        }
    }

    private var tabSwitchTransition: AnyTransition {
        if model.tabSwitchForward {
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        } else {
            .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }
}

/// Header row: tab chips, notch spacer, and the run of round buttons.
struct NotchHeaderView: View {
    @ObservedObject var model: NotchViewModel

    var body: some View {
        let isOpen = model.state.showsShelfContent
        HStack(spacing: 0) {
            HStack {
                NotchTabBar(model: model)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isOpen ? 1 : 0)
            .blur(radius: isOpen ? 0 : 20)
            .animation(.smooth.delay(0.1), value: model.state)
            .zIndex(2)
            .padding(8)

            if isOpen {
                Rectangle()
                    .fill(model.notchGeometry.isHardwareNotch ? Color.black : Color.clear)
                    .frame(width: min(model.notchGeometry.syntheticOrHardwareWidth, 300))
                    .mask {
                        NotchShape(
                            topFlareRadius: NotchSilhouette.closedTopFlare,
                            bottomCornerRadius: NotchSilhouette.closedBottomRadius
                        )
                    }
            }

            HStack(spacing: NotchChipStyle.spacing) {
                if isOpen {
                    // Order: mirror, clipboard, colour picker, timer, volume, caffeinate,
                    // settings, then indicators and the battery.
                    headerButton("list.clipboard", help: "Clipboard") { model.toggleClipboardTab() }
                    ColorPickerHeaderButton()
                    headerButton("gearshape", help: "Settings") { model.requestSettings() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(isOpen ? 1 : 0)
            .blur(radius: isOpen ? 0 : 20)
            .animation(.smooth.delay(0.1), value: model.state)
            .padding(8)
        }
        .foregroundStyle(.gray)
    }

    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NotchChipFace(symbol: symbol)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A row of tab chips 8 pt apart; the selected chip's lighter disc slides between tabs.
struct NotchTabBar: View {
    @ObservedObject var model: NotchViewModel
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: NotchChipStyle.spacing) {
            ForEach(model.availableTabs) { tab in
                let isSelected = model.selectedTab == tab
                Button {
                    model.selectTab(tab)
                } label: {
                    NotchTabChip(symbol: tab.systemImage, isSelected: isSelected, namespace: selectionNamespace)
                }
                .buttonStyle(.plain)
                .help(tab.label)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .animation(.smooth(duration: 0.25), value: model.selectedTab)
    }
}

private struct NotchTabChip: View {
    let symbol: String
    let isSelected: Bool
    let namespace: Namespace.ID

    @State private var isHovering = false

    var body: some View {
        ZStack {
            Circle()
                .fill(isHovering ? NotchChipStyle.hoverFill : NotchChipStyle.fill)
            if isSelected {
                Circle()
                    .fill(NotchChipStyle.selectedFill)
                    .matchedGeometryEffect(id: "selection", in: namespace)
            }
            NotchChipGlyph(symbol: symbol, isSelected: isSelected)
        }
        .frame(width: NotchChipStyle.diameter, height: NotchChipStyle.diameter)
        .contentShape(Circle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}
