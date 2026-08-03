import AppKit
import Foundation

struct NotchGeometry: Equatable, Sendable {
    let screenFrame: CGRect
    let topInset: CGFloat
    let hardwareNotchWidth: CGFloat
    let isHardwareNotch: Bool

    var syntheticOrHardwareWidth: CGFloat {
        isHardwareNotch ? min(hardwareNotchWidth, 183) : 183
    }

    var triggerWidth: CGFloat {
        min(screenFrame.width - 80, syntheticOrHardwareWidth + 48)
    }

    var triggerHeight: CGFloat {
        max(topInset + 24, isHardwareNotch ? 56 : 48)
    }
}

struct NotchPresentationMetrics: Equatable, Sendable {
    let renderedSize: CGSize
    let interactiveSize: CGSize
    let interactionEnabled: Bool
}

enum NotchGeometryResolver {
    static func resolve(screen: NSScreen) -> NotchGeometry {
        let topInset = max(0, screen.safeAreaInsets.top)
        let hardwareWidth: CGFloat
        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            hardwareWidth = max(0, right.minX - left.maxX)
        } else {
            hardwareWidth = 0
        }

        return NotchGeometry(
            screenFrame: screen.frame,
            topInset: topInset > 0 ? topInset : 30,
            hardwareNotchWidth: hardwareWidth,
            isHardwareNotch: hardwareWidth > 80
        )
    }

    static func metrics(
        state: NotchState,
        geometry: NotchGeometry,
        preferredExpandedWidth: CGFloat
    ) -> NotchPresentationMetrics {
        let screenWidth = geometry.screenFrame.width
        let expandedWidth = min(screenWidth - 40, max(680, min(920, preferredExpandedWidth)))
        let baseExpanded = CGSize(width: expandedWidth, height: 276)
        let collapsedRenderedSize = CGSize(
            width: geometry.syntheticOrHardwareWidth,
            height: geometry.topInset
        )

        switch state {
        case .disabled, .retractedForFullscreen:
            return NotchPresentationMetrics(
                renderedSize: collapsedRenderedSize,
                interactiveSize: .zero,
                interactionEnabled: false
            )
        case .idle, .hoverArmed:
            return NotchPresentationMetrics(
                renderedSize: collapsedRenderedSize,
                interactiveSize: CGSize(width: geometry.triggerWidth, height: geometry.triggerHeight),
                interactionEnabled: true
            )
        case .peeking:
            let size = CGSize(width: min(screenWidth - 40, 256), height: max(48, geometry.topInset + 14))
            return NotchPresentationMetrics(
                renderedSize: size,
                interactiveSize: size,
                interactionEnabled: true
            )
        case .expanded, .searchFocused, .dragging, .pinnedOpen:
            return NotchPresentationMetrics(
                renderedSize: baseExpanded,
                interactiveSize: baseExpanded,
                interactionEnabled: true
            )
        case .multiSelecting:
            let size = CGSize(width: expandedWidth, height: 372)
            return NotchPresentationMetrics(
                renderedSize: size,
                interactiveSize: size,
                interactionEnabled: true
            )
        case .previewing:
            let size = CGSize(width: expandedWidth, height: 452)
            return NotchPresentationMetrics(
                renderedSize: size,
                interactiveSize: size,
                interactionEnabled: true
            )
        case .closing:
            return NotchPresentationMetrics(
                renderedSize: collapsedRenderedSize,
                interactiveSize: CGSize(width: geometry.triggerWidth, height: geometry.triggerHeight),
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
}
