import Combine
import SwiftUI

/// Entry point for global keyboard shortcuts (Atoll's KeyboardShortcuts integration,
/// rebuilt on the public Carbon hot-key API).
///
/// The coordinator binds a handler per action, optionally gated by the owning feature's
/// enabled flag, and calls `start()` once:
///
///     ShortcutsFeature.bind(.startDemoTimer, availability: TimerSettings.shared.$isEnabled) {
///         TimerManager.shared.start(duration: 300, name: "Demo Timer")
///     }
///     ShortcutsFeature.start()
@MainActor
enum ShortcutsFeature {
    static var manager: ShortcutsManager { .shared }
    static var settings: ShortcutsSettings { .shared }

    /// Starts following the keyboard layout, registers every bound, enabled shortcut and
    /// adds the rows to Settings › Shortcuts (Atoll's “keyboard” tab).
    static func start() {
        KeyboardLayout.shared.startObserving()
        ShortcutsManager.shared.start()
        SettingsSectionRegistry.shared.register(.shortcuts, id: "shortcuts") { ShortcutsSettingsSection() }
    }

    /// Releases every global shortcut. Handlers stay bound for a later `start()`.
    static func stop() {
        ShortcutsManager.shared.stop()
        KeyboardLayout.shared.stopObserving()
    }

    /// Attaches the work an action performs; its key is claimed while shortcuts are on.
    static func bind(_ action: ShortcutAction, handler: @escaping @MainActor () -> Void) {
        manager.bind(action, handler: handler)
    }

    /// Attaches the work an action performs, claiming its key only while `availability`
    /// last emitted true (the feature's enabled flag). Emit on the main thread.
    static func bind<P: Publisher>(
        _ action: ShortcutAction,
        availability: P,
        handler: @escaping @MainActor () -> Void
    ) where P.Output == Bool, P.Failure == Never {
        manager.bind(action, availability: availability, handler: handler)
    }

    static func unbind(_ action: ShortcutAction) {
        manager.unbind(action)
    }

    /// Marks an action's feature on or off when no publisher was supplied to `bind`.
    static func setAvailable(_ available: Bool, for action: ShortcutAction) {
        manager.setAvailable(available, for: action)
    }

    /// The shortcut that currently triggers `action`, or nil when it has none or shortcuts
    /// are switched off. Use it to show the binding in menus and tooltips.
    static func shortcut(for action: ShortcutAction) -> Shortcut? {
        settings.isEnabled ? settings.shortcut(for: action) : nil
    }

    /// Fires on the main run loop after any binding, the master switch or the keyboard
    /// layout changed, so menus can refresh with `NSMenuItem.applyShortcut(_:)`.
    static var changes: AnyPublisher<Void, Never> {
        let settings = settings
        return Publishers.Merge3(
            settings.$isEnabled.map { _ in () },
            settings.$shortcuts.map { _ in () },
            KeyboardLayout.shared.$revision.map { _ in () }
        )
        .receive(on: RunLoop.main)
        .eraseToAnyPublisher()
    }
}

extension View {
    /// Mirrors an action's global shortcut as this control's in-app key equivalent, the way
    /// Atoll's `keyboardShortcut(_ name:)` helper does, and follows rebinding.
    func keyboardShortcut(for action: ShortcutAction) -> some View {
        modifier(ActionKeyboardShortcutModifier(action: action, settings: .shared))
    }
}

private struct ActionKeyboardShortcutModifier: ViewModifier {
    let action: ShortcutAction
    @ObservedObject var settings: ShortcutsSettings

    func body(content: Content) -> some View {
        if settings.isEnabled,
           let shortcut = settings.shortcut(for: action),
           let key = shortcut.keyEquivalent {
            content.keyboardShortcut(key, modifiers: shortcut.modifiers.eventModifiers)
        } else {
            content
        }
    }
}
