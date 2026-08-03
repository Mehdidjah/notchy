import SwiftUI

struct NotchRootView: View {
    @ObservedObject var model: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("NotchIsland clipboard")
    }

    private var island: some View {
        let metrics = NotchGeometryResolver.metrics(
            state: model.state,
            geometry: model.notchGeometry,
            preferredExpandedWidth: model.settings.expandedWidth
        )
        let isVisible = model.state.isVisible
        let showsCollapsedNotch = model.state == .idle || model.state == .hoverArmed
        let usesExpandedSilhouette = model.state.showsShelfContent || model.state == .peeking
        let shape = NotchShape(
            topFlareRadius: usesExpandedSilhouette ? 9 : 5,
            bottomCornerRadius: model.state == .peeking ? 18 : (model.state.showsShelfContent ? 30 : 9)
        )

        return ZStack(alignment: .top) {
            shape.fill(Color.black)

            if model.state == .peeking {
                PeekNotchView(itemCount: model.items.count)
                    .transition(.opacity)
            } else if model.state.showsShelfContent {
                ExpandedNotchView(model: model)
                    .transition(.opacity.combined(with: .offset(y: -8)))
            } else {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.openPinned() }
                    .accessibilityLabel("Open clipboard shelf")
                    .accessibilityHint("Reveals clipboard history")
            }
        }
        .frame(
            width: metrics.renderedSize.width,
            height: metrics.renderedSize.height,
            alignment: .top
        )
        .clipShape(shape)
        .contentShape(shape)
        // Keep the reference-sized black idle silhouette visible. Event routing still uses a
        // separate, slightly larger transparent sensor in NotchPanelController.
        .opacity(isVisible || showsCollapsedNotch ? 1 : 0.001)
        .animation(animation, value: model.state)
        .animation(animation, value: metrics.renderedSize)
    }

    private var animation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.12)
            : .spring(response: 0.42, dampingFraction: 0.92, blendDuration: 0.1)
    }
}

private struct PeekNotchView: View {
    let itemCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard.fill")
                .foregroundStyle(.white.opacity(0.82))
            Text("\(itemCount) saved")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
            Spacer(minLength: 6)
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 18)
        .padding(.top, 17)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
