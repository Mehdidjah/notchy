import AppKit
import Foundation

struct NotchGeometry: Equatable, Sendable {
    let screenFrame: CGRect
    let topInset: CGFloat
    let hardwareNotchWidth: CGFloat
    let isHardwareNotch: Bool

    /// Width of the island on displays without a hardware notch.
    static let syntheticNotchWidth: CGFloat = 150
    /// Menu-bar height used when a display reports none (for example with an auto-hidden bar).
    static let fallbackMenuBarHeight: CGFloat = 24

    /// The collapsed silhouette is the hardware gap plus a small bleed on each side so the
    /// software notch fuses with the physical one instead of leaving a hairline seam.
    var syntheticOrHardwareWidth: CGFloat {
        isHardwareNotch
            ? hardwareNotchWidth + NotchSilhouette.hardwareBleed * 2
            : Self.syntheticNotchWidth
    }

    /// The generous hover sensor: arming a dwell a little beside or below the notch is
    /// harmless, so this band is wider and taller than what is drawn.
    var triggerWidth: CGFloat {
        min(screenFrame.width - 80, syntheticOrHardwareWidth + 48)
    }

    var triggerHeight: CGFloat {
        max(topInset + 24, isHardwareNotch ? 56 : 48)
    }
}

/// Shape and feel constants for the island. Values are grouped here so the collapsed
/// look, the hover swell and the open silhouette can be tuned in one place.
enum NotchSilhouette {
    static let hardwareBleed: CGFloat = 2
    static let closedTopFlare: CGFloat = 6
    static let closedBottomRadius: CGFloat = 14
    static let openTopFlare: CGFloat = 19
    static let openBottomRadius: CGFloat = 24
    /// The open content is clipped to a rectangle this far inside the silhouette's sides and
    /// bottom. Its corners then stay inside the rounded bottom corners at every radius from the
    /// closed 14 pt to the open 24 pt, and it stays clear of the content, which sits 7 pt in from
    /// the sides and 12 pt up from the bottom.
    static let openContentSideInset: CGFloat = 6
    static let openContentBottomInset: CGFloat = 9
    static let peekBottomRadius: CGFloat = 18
    /// Extra width and height the collapsed notch gains while the pointer rests on it.
    static let hoverSwell: CGFloat = 8
    /// Maximum extra width an open swipe stretches the collapsed notch before it opens.
    static let gestureStretch: CGFloat = 20
    /// Slack around the drawn collapsed notch inside which hover, a click or a swipe counts
    /// (closed hit area: +24 wide, +6 tall).
    static let activationHorizontalSlack: CGFloat = 24
    static let activationVerticalSlack: CGFloat = 6
    /// Side padding of the closed island; equals the closed bottom radius (14).
    static let closedHorizontalPadding: CGFloat = 14
    /// The idle closed content is the notch width minus this, before the side padding.
    static let idleContentInset: CGFloat = 20
    /// Height of a sneak-peek row under the closed notch, including its 10-pt bottom padding.
    static let sneakPeekRowHeight: CGFloat = 30
    static let sneakPeekMinimumWidth: CGFloat = 300
    static let shadowRadius: CGFloat = 10
    static let shadowOpacity: Double = 0.6
    static let peekWidth: CGFloat = 360
    /// Height of the tray that drops under the notch for a captured clip.
    static let peekTrayHeight: CGFloat = 30
}

struct NotchPresentationMetrics: Equatable, Sendable {
    /// What is drawn.
    let renderedSize: CGSize
    /// Where hovering arms the island and where the hosting view accepts events.
    let interactiveSize: CGSize
    /// Where a click or an open swipe is accepted: the drawn collapsed notch plus a little
    /// slack, never the wider hover band, so input meant for the app underneath is left alone.
    let activationSize: CGSize
    let interactionEnabled: Bool
}

enum NotchGeometryResolver {
    static func resolve(screen: NSScreen) -> NotchGeometry {
        let safeAreaTop = max(0, screen.safeAreaInsets.top)
        let hardwareWidth: CGFloat
        if safeAreaTop > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            hardwareWidth = max(0, right.minX - left.maxX)
        } else {
            hardwareWidth = 0
        }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY

        return NotchGeometry(
            screenFrame: screen.frame,
            topInset: safeAreaTop > 0
                ? safeAreaTop
                : (menuBarHeight > 0 ? menuBarHeight : NotchGeometry.fallbackMenuBarHeight),
            hardwareNotchWidth: hardwareWidth,
            isHardwareNotch: hardwareWidth > 80
        )
    }

    /// The open island is the tab's content box plus 12-pt insets on both sides and below.
    static func openSize(
        screenWidth: CGFloat,
        preferredOpenWidth: CGFloat,
        tab: NotchTab,
        tabCount: Int
    ) -> CGSize {
        let minimum = NotchTab.minimumOpenWidth(forTabCount: tabCount)
        let width = min(max(screenWidth - 60, 400), max(minimum, min(NotchTab.maximumOpenWidth, preferredOpenWidth)))
        return CGSize(
            width: width + NotchTab.openHorizontalInset * 2,
            height: tab.openHeight + NotchTab.openBottomInset
        )
    }

    static func metrics(
        state: NotchState,
        geometry: NotchGeometry,
        preferredExpandedWidth: CGFloat,
        tab: NotchTab = .home,
        tabCount: Int = 1,
        extraOpenHeight: CGFloat = 0,
        activity: ClosedActivityLayout? = nil
    ) -> NotchPresentationMetrics {
        let screenWidth = geometry.screenFrame.width
        var baseExpanded = openSize(
            screenWidth: screenWidth,
            preferredOpenWidth: preferredExpandedWidth,
            tab: tab,
            tabCount: tabCount
        )
        baseExpanded.height += max(0, extraOpenHeight)
        let padding = NotchSilhouette.closedHorizontalPadding * 2
        // The idle notch is a (notch - 20) box plus 14 pt each side and does not swell;
        // with an activity the island is its three columns plus the same padding.
        let collapsedRenderedSize: CGSize = if let activity {
            CGSize(width: min(screenWidth - 40, activity.contentWidth + padding), height: activity.outerHeight)
        } else {
            CGSize(
                width: min(screenWidth - 40, geometry.syntheticOrHardwareWidth - NotchSilhouette.idleContentInset + padding),
                height: geometry.topInset
            )
        }
        let collapsedActivationSize = CGSize(
            width: collapsedRenderedSize.width + NotchSilhouette.activationHorizontalSlack,
            height: collapsedRenderedSize.height + NotchSilhouette.activationVerticalSlack
        )

        switch state {
        case .disabled, .retractedForFullscreen:
            return NotchPresentationMetrics(
                renderedSize: CGSize(width: geometry.syntheticOrHardwareWidth, height: geometry.topInset),
                interactiveSize: .zero,
                activationSize: .zero,
                interactionEnabled: false
            )
        case .idle, .hoverArmed, .closing:
            return NotchPresentationMetrics(
                renderedSize: collapsedRenderedSize,
                interactiveSize: collapsedActivationSize,
                activationSize: collapsedActivationSize,
                interactionEnabled: true
            )
        case .peeking:
            let size = CGSize(
                width: min(screenWidth - 40, max(collapsedRenderedSize.width, NotchSilhouette.sneakPeekMinimumWidth)),
                height: collapsedRenderedSize.height + NotchSilhouette.sneakPeekRowHeight
            )
            let sensor = CGSize(
                width: size.width + NotchSilhouette.activationHorizontalSlack,
                height: size.height + NotchSilhouette.activationVerticalSlack
            )
            return NotchPresentationMetrics(
                renderedSize: size,
                interactiveSize: sensor,
                activationSize: sensor,
                interactionEnabled: true
            )
        case .expanded, .searchFocused, .dragging, .pinnedOpen, .multiSelecting, .previewing:
            return NotchPresentationMetrics(
                renderedSize: baseExpanded,
                interactiveSize: baseExpanded,
                activationSize: baseExpanded,
                interactionEnabled: true
            )
        }
    }

    static func interactiveRect(
        containerSize: CGSize,
        interactiveSize: CGSize
    ) -> CGRect {
        guard interactiveSize.width > 0, interactiveSize.height > 0 else { return .zero }
        let width = min(containerSize.width, interactiveSize.width)
        let height = min(containerSize.height, interactiveSize.height)
        return CGRect(
            x: (containerSize.width - width) / 2,
            y: containerSize.height - height,
            width: width,
            height: height
        )
    }

    /// `CGRect.contains` excludes the max edges. The pointer can rest on the very top pixel
    /// row of the display, so hit tests against a rect anchored at the screen's top edge
    /// must treat that edge as inside.
    static func rectContainsIncludingTopEdge(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX
            && point.y >= rect.minY && point.y <= rect.maxY
    }
}
