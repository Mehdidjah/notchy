import Combine
import Foundation

/// Keeps the system's hot keys in step with the stored shortcuts, the master switch, the
/// handlers the coordinator binds and each feature's on/off state, the way Atoll pairs
/// `KeyboardShortcuts.onKeyDown` with `updateFeatureShortcutAvailability()`.
///
/// An action's keystroke is claimed only while shortcuts are enabled, a handler is bound,
/// its feature is available and it has a shortcut; otherwise the key is left to other apps.
@MainActor
final class ShortcutsManager: ObservableObject {
    static let shared = ShortcutsManager(settings: .shared, hotKeys: .shared)

    let settings: ShortcutsSettings
    let hotKeys: HotKeyCenter

    @Published private(set) var isRunning = false
    /// Actions with a handler attached.
    @Published private(set) var boundActions: Set<ShortcutAction> = []
    /// Actions whose feature is currently switched off.
    @Published private(set) var unavailableActions: Set<ShortcutAction> = []
    /// Actions whose keystroke the system refused.
    @Published private(set) var failures: [ShortcutAction: HotKeyError] = [:]
    /// The action whose recorder is listening for keys; hot keys are paused meanwhile.
    @Published private(set) var recordingAction: ShortcutAction?

    private var handlers: [ShortcutAction: @MainActor () -> Void] = [:]
    private var availabilitySubscriptions: [ShortcutAction: AnyCancellable] = [:]
    private var settingsSubscription: AnyCancellable?

    init(settings: ShortcutsSettings, hotKeys: HotKeyCenter) {
        self.settings = settings
        self.hotKeys = hotKeys
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        // `@Published` emits before storing, so sync from the emitted values. The first
        // emission is the current state and performs the initial registration.
        settingsSubscription = settings.$isEnabled
            .combineLatest(settings.$shortcuts)
            .sink { [weak self] isEnabled, shortcuts in
                self?.sync(isEnabled: isEnabled, shortcuts: shortcuts)
            }
    }

    func stop() {
        settingsSubscription = nil
        if recordingAction != nil {
            recordingAction = nil
            hotKeys.resume()
        }
        isRunning = false
        for action in ShortcutAction.allCases {
            hotKeys.unregister(id: action.hotKeyID)
        }
        if !failures.isEmpty { failures = [:] }
    }

    // MARK: - Handlers and availability

    /// Attaches the work a shortcut performs. Replaces any earlier handler.
    func bind(_ action: ShortcutAction, handler: @escaping @MainActor () -> Void) {
        handlers[action] = handler
        boundActions.insert(action)
        sync()
    }

    /// Attaches a handler that only runs, and only claims its key, while `availability`
    /// last emitted true. The publisher must emit on the main thread (an `@Published`
    /// property of a main-actor settings object, for example).
    func bind<P: Publisher>(
        _ action: ShortcutAction,
        availability: P,
        handler: @escaping @MainActor () -> Void
    ) where P.Output == Bool, P.Failure == Never {
        handlers[action] = handler
        boundActions.insert(action)
        availabilitySubscriptions[action] = availability
            .removeDuplicates()
            .sink { [weak self] available in
                self?.setAvailable(available, for: action)
            }
        sync()
    }

    func unbind(_ action: ShortcutAction) {
        handlers[action] = nil
        boundActions.remove(action)
        availabilitySubscriptions[action] = nil
        unavailableActions.remove(action)
        sync()
    }

    /// Marks an action's feature on or off, like Atoll's per-feature `KeyboardShortcuts.enable`.
    func setAvailable(_ available: Bool, for action: ShortcutAction) {
        let changed = available
            ? unavailableActions.remove(action) != nil
            : unavailableActions.insert(action).inserted
        if changed { sync() }
    }

    func isBound(_ action: ShortcutAction) -> Bool { boundActions.contains(action) }

    func isAvailable(_ action: ShortcutAction) -> Bool { !unavailableActions.contains(action) }

    /// Whether the action has a row in Settings.
    func isListed(_ action: ShortcutAction) -> Bool {
        !action.isListedOnlyWhenBound || boundActions.contains(action)
    }

    /// Whether the action's key is currently registered with the system.
    func isActive(_ action: ShortcutAction) -> Bool {
        hotKeys.isLive(action.hotKeyID) || (hotKeys.isPaused && hotKeys.shortcut(for: action.hotKeyID) != nil)
    }

    /// Runs an action's handler if shortcuts and its feature are enabled. Returns whether
    /// anything ran. Hot keys call this; tests and menus may too.
    @discardableResult
    func perform(_ action: ShortcutAction) -> Bool {
        guard settings.isEnabled,
              recordingAction == nil,
              !unavailableActions.contains(action),
              let handler = handlers[action]
        else { return false }
        handler()
        return true
    }

    // MARK: - Editing shortcuts

    /// Every reason `shortcut` cannot be saved for `action`, in the order Atoll's recorder
    /// checks them: a missing modifier (beep), a clash with one of the app's menu items, the
    /// Option-only rule, a system-wide shortcut; Notchy's own in-app clash comes last.
    func issues(for shortcut: Shortcut, assigningTo action: ShortcutAction) -> [ShortcutIssue] {
        let structural = ShortcutValidation.structuralIssue(shortcut)
        if structural == .needsModifier { return [.needsModifier] }
        var issues: [ShortcutIssue] = []
        if let title = ShortcutValidation.menuItemTitle(using: shortcut) {
            issues.append(.usedByMenuItem(title))
        }
        if let structural {
            issues.append(structural)
        }
        if ShortcutValidation.isTakenBySystem(shortcut) {
            issues.append(.usedBySystem)
        }
        if let other = ShortcutAction.allCases.first(where: {
            $0 != action && isListed($0) && settings.shortcut(for: $0) == shortcut
        }) {
            issues.append(.usedByAction(other))
        }
        return issues
    }

    /// Saves `shortcut` for `action` unless an issue not in `accepted` blocks it, which is
    /// then returned. Accepting `.usedByAction` clears the other action's shortcut.
    @discardableResult
    func assign(
        _ shortcut: Shortcut,
        to action: ShortcutAction,
        accepting accepted: [ShortcutIssue] = []
    ) -> ShortcutIssue? {
        let issues = issues(for: shortcut, assigningTo: action)
        if let blocking = issues.first(where: { !($0.canOverride && accepted.contains($0)) }) {
            return blocking
        }
        for case let .usedByAction(other) in issues {
            settings.setShortcut(nil, for: other)
        }
        settings.setShortcut(shortcut, for: action)
        return nil
    }

    func clear(_ action: ShortcutAction) {
        settings.setShortcut(nil, for: action)
    }

    func resetToDefault(_ action: ShortcutAction) {
        settings.resetToDefault(action)
    }

    func resetAllToDefaults() {
        settings.resetAllToDefaults()
    }

    // MARK: - Recording

    /// Pauses every hot key so the recorder receives the keystrokes instead.
    func beginRecording(_ action: ShortcutAction) {
        if recordingAction == nil { hotKeys.pause() }
        recordingAction = action
    }

    func endRecording() {
        guard recordingAction != nil else { return }
        recordingAction = nil
        hotKeys.resume()
        sync()
    }

    // MARK: - Registration

    /// Re-applies the current state. Called automatically; public for the coordinator.
    func sync() {
        sync(isEnabled: settings.isEnabled, shortcuts: settings.shortcuts)
    }

    private func sync(isEnabled: Bool, shortcuts: [ShortcutAction: Shortcut]) {
        var desired: [ShortcutAction: Shortcut] = [:]
        if isRunning, isEnabled {
            for action in ShortcutAction.allCases
            where handlers[action] != nil && !unavailableActions.contains(action) {
                desired[action] = shortcuts[action]
            }
        }

        // Release stale keys first so two actions can swap shortcuts in one pass.
        for action in ShortcutAction.allCases {
            let current = hotKeys.shortcut(for: action.hotKeyID)
            if current != nil, current != desired[action] {
                hotKeys.unregister(id: action.hotKeyID)
            }
        }

        var newFailures: [ShortcutAction: HotKeyError] = [:]
        for action in ShortcutAction.allCases {
            guard let shortcut = desired[action] else { continue }
            let result = hotKeys.register(id: action.hotKeyID, shortcut: shortcut) { [weak self] in
                _ = self?.perform(action)
            }
            if case let .failure(error) = result {
                newFailures[action] = error
            }
        }
        if newFailures != failures { failures = newFailures }
    }
}
