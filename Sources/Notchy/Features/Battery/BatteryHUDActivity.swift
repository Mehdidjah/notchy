import Combine
import SwiftUI

/// The temporary charging / low / full battery alert in the closed notch: the
/// highest-priority closed surface.
///
/// The compact alert is a pair of 90-pt wings (title on the left, percentage and pill on the
/// right), making the island 180 pt wider than the notch. The standard low and full alerts
/// are 150 and 140 pt wider and grow a 75 / 70-pt card under the notch; that card needs the
/// host to draw a band under the wings (`bottomBandHeight(in:)` / `bottomBand(in:)`). Until
/// the host asks for that band, standard alerts fall back to the compact row so they are
/// never invisible.
@MainActor
final class BatteryHUDActivity: ClosedLiveActivity {
    let activityID = "battery.hud"
    let priority = ClosedActivityPriority.batteryHUD

    let controller: BatteryHUDController
    let settings: BatterySettings
    let monitor: BatteryMonitor

    /// Set the first time the host asks for the band under the wings.
    private(set) var hostDrawsBottomBand = false

    init(
        controller: BatteryHUDController = .shared,
        settings: BatterySettings = .shared,
        monitor: BatteryMonitor = .shared
    ) {
        self.controller = controller
        self.settings = settings
        self.monitor = monitor
    }

    var isActivityVisible: Bool {
        settings.showPowerStatusNotifications && controller.presentation != nil
    }

    var activityDidChange: AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            controller.$presentation.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            settings.$showPowerStatusNotifications.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            settings.$lowBatteryHUDStyle.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            settings.$fullBatteryHUDStyle.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
        )
        .eraseToAnyPublisher()
    }

    /// The style actually drawn: the setting when the host can draw the card, else compact.
    var effectiveStyle: BatteryHUDStyle {
        guard let kind = controller.presentation?.kind else { return .compact }
        return hostDrawsBottomBand ? settings.style(for: kind) : .compact
    }

    var metrics: BatteryHUDMetrics? {
        guard let kind = controller.presentation?.kind else { return nil }
        return BatteryHUDMetrics.resolve(kind: kind, style: effectiveStyle)
    }

    func leftWingWidth(in context: ClosedActivityContext) -> CGFloat {
        metrics?.wingWidth ?? context.wingBaseWidth
    }

    func rightWingWidth(in context: ClosedActivityContext) -> CGFloat {
        metrics?.wingWidth ?? context.wingBaseWidth
    }

    func leftWing(in context: ClosedActivityContext) -> AnyView {
        guard let presentation = controller.presentation, effectiveStyle == .compact else {
            return AnyView(Color.clear)
        }
        return AnyView(
            BatteryHUDCompactLeadingWing(kind: presentation.kind)
                .id(presentation.id)
        )
    }

    func rightWing(in context: ClosedActivityContext) -> AnyView {
        guard let presentation = controller.presentation, effectiveStyle == .compact else {
            return AnyView(Color.clear)
        }
        return AnyView(
            BatteryHUDCompactTrailingWing(controller: controller, monitor: monitor, kind: presentation.kind)
                .id(presentation.id)
        )
    }

    // MARK: Band under the wings (standard style)

    /// Extra height under the wings: 75 pt for the standard low alert, 70 for the full one.
    func bottomBandHeight(in context: ClosedActivityContext) -> CGFloat {
        if !hostDrawsBottomBand {
            hostDrawsBottomBand = true
        }
        return metrics?.bandHeight ?? 0
    }

    /// The standard alert's card, laid out across the island's full width under the wings.
    func bottomBand(in context: ClosedActivityContext) -> AnyView? {
        guard let presentation = controller.presentation,
              presentation.kind != .charging,
              hostDrawsBottomBand,
              settings.style(for: presentation.kind) == .standard
        else { return nil }
        return AnyView(
            BatteryHUDStandardCard(controller: controller, monitor: monitor, kind: presentation.kind)
                .id(presentation.id)
        )
    }

    /// Rounds the island's bottom corners to 40 pt (low) or 36 pt (full) for the
    /// standard cards; nil keeps the closed radius.
    func closedBottomCornerRadius(in context: ClosedActivityContext) -> CGFloat? {
        hostDrawsBottomBand ? metrics?.bottomCornerRadius : nil
    }
}
