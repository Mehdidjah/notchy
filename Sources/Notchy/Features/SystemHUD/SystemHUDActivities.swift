import Combine
import SwiftUI

/// Inline HUD on the closed notch: volume or microphone state for 1.5 s after a change.
@MainActor
final class InlineHUDActivity: ClosedLiveActivity {
    let activityID = "systemHUD.inline"
    let priority = ClosedActivityPriority.inlineHUD

    private let presenter: SystemHUDPresenter
    private let onDrag: (CGFloat) -> Void

    init(presenter: SystemHUDPresenter = .shared, onDrag: @escaping (CGFloat) -> Void = { _ in }) {
        self.presenter = presenter
        self.onDrag = onDrag
    }

    var isActivityVisible: Bool { presenter.isShowingInlineHUD }

    var activityDidChange: AnyPublisher<Void, Never> {
        presenter.inlineVisibilityDidChange.eraseToAnyPublisher()
    }

    func leftWingWidth(in context: ClosedActivityContext) -> CGFloat {
        InlineHUDMetrics.wingWidths(.level, context: context).info
    }

    func rightWingWidth(in context: ClosedActivityContext) -> CGFloat {
        InlineHUDMetrics.wingWidths(.level, context: context).trailing
    }

    func leftWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(
            InlineHUDLeadingWing(
                presenter: presenter,
                columnWidth: InlineHUDMetrics.designColumns(.level, gestureProgress: context.gestureProgress).info,
                wingWidth: leftWingWidth(in: context)
            )
        )
    }

    func rightWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(
            InlineHUDTrailingWing(
                presenter: presenter,
                columnWidth: InlineHUDMetrics.designColumns(.level, gestureProgress: context.gestureProgress).trailing,
                wingWidth: rightWingWidth(in: context),
                onDrag: onDrag
            )
        )
    }
}

/// Persistent Caps Lock indicator: the glyph (and optional label) stays on the closed
/// notch while Caps Lock is on. Always drawn inline, whatever the HUD style.
@MainActor
final class CapsLockActivity: ClosedLiveActivity {
    let activityID = "systemHUD.capsLock"
    let priority = ClosedActivityPriority.capsLock

    private let monitor: CapsLockMonitor
    private let settings: SystemHUDSettings
    private let presenter: SystemHUDPresenter
    private let changes = PassthroughSubject<Void, Never>()
    private var cancellables: Set<AnyCancellable> = []

    init(
        monitor: CapsLockMonitor = .shared,
        settings: SystemHUDSettings = .shared,
        presenter: SystemHUDPresenter = .shared
    ) {
        self.monitor = monitor
        self.settings = settings
        self.presenter = presenter
        let signal = changes
        monitor.$isCapsLockOn.removeDuplicates().dropFirst()
            .sink { _ in signal.send() }
            .store(in: &cancellables)
        settings.$enableCapsLockIndicator.removeDuplicates().dropFirst()
            .sink { _ in signal.send() }
            .store(in: &cancellables)
        settings.$showCapsLockLabel.removeDuplicates().dropFirst()
            .sink { _ in signal.send() }
            .store(in: &cancellables)
        presenter.$isScreenLocked.removeDuplicates().dropFirst()
            .sink { _ in signal.send() }
            .store(in: &cancellables)
    }

    var isActivityVisible: Bool {
        settings.enableCapsLockIndicator && monitor.isCapsLockOn && !presenter.isScreenLocked
    }

    /// Emits after the published value has landed (`@Published` fires in `willSet`).
    var activityDidChange: AnyPublisher<Void, Never> {
        changes.receive(on: RunLoop.main).eraseToAnyPublisher()
    }

    private var content: InlineHUDMetrics.Content {
        .capsLock(showsLabel: settings.showCapsLockLabel)
    }

    func leftWingWidth(in context: ClosedActivityContext) -> CGFloat {
        InlineHUDMetrics.wingWidths(content, context: context).info
    }

    func rightWingWidth(in context: ClosedActivityContext) -> CGFloat {
        InlineHUDMetrics.wingWidths(content, context: context).trailing
    }

    func leftWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(
            CapsLockLeadingWing(
                settings: settings,
                columnWidth: InlineHUDMetrics.designColumns(content, gestureProgress: context.gestureProgress).info,
                wingWidth: leftWingWidth(in: context)
            )
        )
    }

    func rightWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(
            CapsLockTrailingWing(
                settings: settings,
                columnWidth: InlineHUDMetrics.designColumns(content, gestureProgress: context.gestureProgress).trailing,
                wingWidth: rightWingWidth(in: context)
            )
        )
    }
}
