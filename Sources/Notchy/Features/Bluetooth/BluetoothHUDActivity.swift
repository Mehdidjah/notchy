import Combine
import SwiftUI

/// Wing sizes of the inline Bluetooth HUD.
enum BluetoothHUDMetrics {
    /// Left wing (icon, plus the scrolling name when enabled): 64 pt, or 132 with the name;
    /// a swipe widens it by half its progress; never under 60 / 112.
    static func infoWidth(showsName: Bool, gestureProgress: CGFloat) -> CGFloat {
        let base: CGFloat = showsName ? 132 : 64
        let minimum: CGFloat = showsName ? 112 : 60
        return max(base + gestureProgress / 2, minimum)
    }

    /// Right wing: 80 pt (110 with the name) when the battery is unknown; with a battery,
    /// 76 / 112 for the ring without / with the percentage, 100 / 128 for the bar.
    static func trailingWidth(
        showsBattery: Bool,
        circular: Bool,
        showsPercentage: Bool,
        showsName: Bool,
        gestureProgress: CGFloat
    ) -> CGFloat {
        let base: CGFloat
        let minimum: CGFloat
        switch (showsBattery, circular, showsPercentage) {
        case (false, _, _):
            base = showsName ? 110 : 80
            minimum = showsName ? 102 : 80
        case (true, true, false):
            base = 76
            minimum = 64
        case (true, true, true):
            base = 112
            minimum = 102
        case (true, false, false):
            base = 100
            minimum = 82
        case (true, false, true):
            base = 128
            minimum = 112
        }
        return max(base + gestureProgress / 2, minimum)
    }

    /// Default HStack gap between the info column, the black centre and the trailing
    /// column.
    static let designGap: CGFloat = 8

    /// Design black centre: the closed notch minus 20 pt. It does not swell on hover.
    static func designCentreWidth(notchWidth: CGFloat) -> CGFloat {
        max(notchWidth - 20, 0)
    }

    /// Host left wing: the design info column plus the gap after it, so the host's black centre
    /// starts exactly where the design's does and covers the scrolling name at the same point.
    static func hostLeftWidth(infoWidth: CGFloat) -> CGFloat {
        infoWidth + designGap
    }

    /// Host right wing: whatever is left of the design total width (info + gap + centre + gap +
    /// trailing) once the host's centre (the whole notch, plus the hover swell) is placed.
    /// The trailing content is right-aligned, so it sits exactly where the design places it.
    static func hostRightWidth(trailingWidth: CGFloat, in context: ClosedActivityContext) -> CGFloat {
        let designRemainder = designCentreWidth(notchWidth: context.notchWidth) + designGap + trailingWidth
        return max(0, designRemainder - context.centerWidth)
    }
}

/// The inline "device connected" HUD in the closed notch: the device symbol (and optionally
/// its scrolling name) on the left, its battery on the right, for 2.5 s.
@MainActor
final class BluetoothHUDActivity: ClosedLiveActivity {
    let activityID = "bluetooth.hud"
    let priority = ClosedActivityPriority.inlineHUD

    let controller: BluetoothHUDController
    let settings: BluetoothSettings

    init(controller: BluetoothHUDController = .shared, settings: BluetoothSettings = .shared) {
        self.controller = controller
        self.settings = settings
    }

    var isActivityVisible: Bool {
        settings.useInlineHUD && controller.presentation != nil
    }

    var activityDidChange: AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            controller.$presentation.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            settings.$useInlineHUD.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            settings.$showDeviceNameMarquee.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            settings.$useCircularBatteryIndicator.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            settings.$showBatteryPercentageText.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
        )
        .eraseToAnyPublisher()
    }

    /// Info column width for the current settings and swipe.
    func infoWidth(in context: ClosedActivityContext) -> CGFloat {
        BluetoothHUDMetrics.infoWidth(
            showsName: settings.showDeviceNameMarquee,
            gestureProgress: context.gestureProgress
        )
    }

    func leftWingWidth(in context: ClosedActivityContext) -> CGFloat {
        BluetoothHUDMetrics.hostLeftWidth(infoWidth: infoWidth(in: context))
    }

    func rightWingWidth(in context: ClosedActivityContext) -> CGFloat {
        let width = BluetoothHUDMetrics.trailingWidth(
            showsBattery: controller.presentation?.showsBattery ?? false,
            circular: settings.useCircularBatteryIndicator,
            showsPercentage: settings.showBatteryPercentageText,
            showsName: settings.showDeviceNameMarquee,
            gestureProgress: context.gestureProgress
        )
        return BluetoothHUDMetrics.hostRightWidth(trailingWidth: width, in: context)
    }

    func leftWing(in context: ClosedActivityContext) -> AnyView {
        guard let presentation = controller.presentation else { return AnyView(Color.clear) }
        return AnyView(
            BluetoothHUDLeadingWing(
                device: presentation.device,
                showsName: settings.showDeviceNameMarquee,
                infoWidth: infoWidth(in: context)
            )
            .id(presentation.id)
        )
    }

    func rightWing(in context: ClosedActivityContext) -> AnyView {
        guard let presentation = controller.presentation else { return AnyView(Color.clear) }
        return AnyView(
            BluetoothHUDTrailingWing(presentation: presentation, settings: settings)
                .id(presentation.id)
        )
    }
}
