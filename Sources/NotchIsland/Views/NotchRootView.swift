import SwiftUI

struct NotchRootView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject private var settings: UserSettings
    @ObservedObject private var activityCenter: IslandActivityCenter
    @ObservedObject private var homeLayout = HomeLayoutState.shared
    @State private var openSizeRevision = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: NotchViewModel) {
        self.model = model
        _settings = ObservedObject(wrappedValue: model.settings)
        _activityCenter = ObservedObject(wrappedValue: model.activityCenter)
    }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("NotchIsland")
        .onReceive(model.openSizeDidChange.receive(on: RunLoop.main)) { openSizeRevision &+= 1 }
    }

    private var island: some View {
        let isOpen = model.state.showsShelfContent
        let isPeeking = model.state == .peeking
        let showsActivity = model.state.isCollapsed || isPeeking
        let activityLayout = showsActivity ? model.closedActivityLayout() : nil
        let metrics = NotchGeometryResolver.metrics(
            state: model.state,
            geometry: model.notchGeometry,
            preferredExpandedWidth: settings.openNotchWidth,
            tab: model.selectedTab,
            tabCount: model.availableTabs.count,
            extraOpenHeight: model.extraOpenHeight,
            activity: activityLayout
        )
        let isVisible = model.state.isVisible
        let shape = NotchShape(
            topFlareRadius: isOpen ? NotchSilhouette.openTopFlare : NotchSilhouette.closedTopFlare,
            bottomCornerRadius: isOpen ? NotchSilhouette.openBottomRadius : NotchSilhouette.closedBottomRadius
        )
        let showsShadow = settings.showShadow && (isOpen || model.isHovering || isPeeking)
        let closeSwipe = max(0, -model.gestureProgress)

        return ZStack(alignment: .top) {
            shape.fill(Color.black)

            if isOpen {
                NotchShellView(model: model)
                    .blur(radius: closeSwipe > 0.3 ? min(closeSwipe, 8) : 0)
                    .opacity(closeSwipe > 0.3 ? 0.8 : 1)
                    .transition(.blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)))
            } else {
                ClosedIslandContent(
                    model: model,
                    activityCenter: activityCenter,
                    layout: activityLayout,
                    sneakPeek: isPeeking ? model.currentSneakPeek : nil
                )
                .transition(.blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)))
            }
        }
        .frame(
            width: metrics.renderedSize.width,
            height: metrics.renderedSize.height,
            alignment: .top
        )
        .clipShape(shape)
        .contentShape(shape)
        .compositingGroup()
        .shadow(
            color: showsShadow ? .black.opacity(NotchSilhouette.shadowOpacity) : .clear,
            radius: NotchSilhouette.shadowRadius
        )
        .opacity(isVisible || model.state.isCollapsed ? 1 : 0.001)
        .animation(hoverAnimation, value: model.isHovering)
        .animation(isOpen ? openAnimation : closeAnimation, value: model.state)
        .animation(gestureAnimation, value: model.gestureProgress)
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .smooth, value: model.selectedTab)
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .smooth, value: settings.openNotchWidth)
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .smooth, value: homeLayout.extraHeight)
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .easeInOut(duration: 0.3), value: openSizeRevision)
        .animation(liveActivityAnimation, value: activityCenter.activeActivityID)
    }

    /// Hover swells the wings with a quick bounce.
    private var hoverAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .bouncy.speed(1.2)
    }

    /// Opening settles with a critically damped spring; closing uses a slightly longer one.
    private var openAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.42, dampingFraction: 1.0, blendDuration: 0)
    }

    private var closeAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
    }

    private var gestureAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .smooth
    }

    /// Activities swap in with Atoll's spring (response 0.34, damping 0.88).
    private var liveActivityAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.88)
    }
}

/// The closed island: the winning live activity's wings around a black centre, or the idle
/// notch-sized box, with an optional sneak-peek row underneath.
private struct ClosedIslandContent: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var activityCenter: IslandActivityCenter
    let layout: ClosedActivityLayout?
    let sneakPeek: SneakPeek?

    var body: some View {
        VStack(spacing: 0) {
            closedRow
            if let sneakPeek {
                SneakPeekRow(peek: sneakPeek)
                    .frame(height: NotchSilhouette.sneakPeekRowHeight - 10)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, NotchSilhouette.closedHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { model.openFromClick() }
        .shelfDropDetector(isEnabled: model.settings.showShelfTab && ShelfSettings.shared.opensOnDrag) { targeted in
            guard targeted, model.state.isCollapsed || model.state == .peeking else { return }
            model.selectTab(.shelf)
            model.openFromClick()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open the island")
        .accessibilityHint("Shows Home, Shelf, Timer, Stats, Notes and Clipboard")
    }

    @ViewBuilder
    private var closedRow: some View {
        if let layout, let activity = activityCenter.activeActivity {
            let context = model.closedActivityContext()
            HStack(spacing: 0) {
                activity.leftWing(in: context)
                    .frame(width: layout.leftWidth, height: layout.contentHeight)
                Rectangle()
                    .fill(Color.black)
                    .frame(width: layout.centerWidth, height: layout.contentHeight)
                    .overlay { activity.centerOverlay(in: context) }
                activity.rightWing(in: context)
                    .frame(width: layout.rightWidth, height: layout.contentHeight)
            }
            .frame(height: layout.outerHeight, alignment: .center)
            .id(activity.activityID)
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.965))
                        .animation(.spring(response: 0.34, dampingFraction: 0.88)),
                    removal: .opacity.combined(with: .scale(scale: 0.92))
                        .animation(.smooth(duration: 0.22))
                )
            )
        } else {
            Color.clear
                .frame(
                    width: max(0, model.notchGeometry.syntheticOrHardwareWidth - NotchSilhouette.idleContentInset),
                    height: model.notchGeometry.topInset
                )
        }
    }
}

/// Atoll's standard sneak-peek row: an icon and a single line of grey text, or an icon and
/// a level bar for volume and brightness.
private struct SneakPeekRow: View {
    let peek: SneakPeek

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: peek.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(peek.tint ?? .gray)
                .contentTransition(.symbolEffect(.replace))
            if let level = peek.level {
                LevelBar(level: level, tint: peek.tint ?? .white)
                    .frame(height: 6)
            } else {
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    private var text: String {
        [peek.subtitle, peek.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " – ")
    }
}

private struct LevelBar: View {
    let level: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(tint).frame(width: proxy.size.width * max(0, min(1, level)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: level)
    }
}
