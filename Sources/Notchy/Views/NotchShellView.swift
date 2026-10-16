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
        switch model.selectedTab {
        case .home:
            NotchHomeTabView(model: model)
        case .notes:
            NotchNotesTabView(model: model)
        case .face:
            NotchFaceTabView(model: model)
        case .clipboard:
            NotchClipboardTabView(model: model)
        case .shelf:
            NotchShelfTabView(model: model)
        case .timer:
            NotchTimerTabView(model: model)
        case .stats:
            NotchStatsTabView(model: model)
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

/// Header row: tabs, notch spacer, and the run of round buttons.
struct NotchHeaderView: View {
    @ObservedObject var model: NotchViewModel

    /// Point sizes chosen so mixed symbols read as one size in a 30-pt capsule.
    private static let glyphSizes: [String: CGFloat] = [
        "list.clipboard": 13,
        "gearshape": 14.2,
        "pin": 14.4,
        "pin.fill": 14.4,
        "square.grid.2x2": 14.0
    ]

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

            HStack(spacing: 8) {
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
            Capsule()
                .fill(.black)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: symbol)
                        .foregroundStyle(.white)
                        .font(.system(size: Self.glyphSizes[symbol] ?? 14.4, weight: .medium))
                        .frame(width: 20, height: 20)
                }
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A row of tab icons 24 pt apart; the selected one sits on a translucent capsule that
/// slides between tabs.
struct NotchTabBar: View {
    @ObservedObject var model: NotchViewModel
    @Namespace private var capsuleNamespace

    var body: some View {
        HStack(spacing: 24) {
            ForEach(model.availableTabs) { tab in
                let isSelected = model.selectedTab == tab
                Button {
                    model.selectTab(tab)
                } label: {
                    Image(systemName: tab.systemImage)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(height: 26)
                .foregroundStyle(isSelected ? Color.white : Color.gray)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill).opacity(0.25))
                            .matchedGeometryEffect(id: "capsule", in: capsuleNamespace)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .matchedGeometryEffect(id: "capsule", in: capsuleNamespace)
                            .hidden()
                    }
                }
                .help(tab.label)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .clipShape(Capsule())
        .animation(.smooth(duration: 0.25), value: model.selectedTab)
    }
}
