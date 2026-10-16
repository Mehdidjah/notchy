import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
import Testing
@testable import Notchy

/// Records registrations instead of claiming real system-wide hot keys.
@MainActor
private final class FakeHotKeyBackend: HotKeyBackend {
    var onPress: ((UInt32) -> Void)?
    private(set) var registered: [UInt32: Shortcut] = [:]
    private(set) var registerCalls = 0
    /// Keystrokes the fake "system" refuses, as if another app owned them.
    var refused: Set<Shortcut> = []

    func register(keyCode: UInt32, carbonModifiers: UInt32, id: UInt32) -> OSStatus {
        registerCalls += 1
        let shortcut = Shortcut(keyCode: keyCode, carbonModifiers: carbonModifiers)
        if refused.contains(shortcut) { return OSStatus(eventHotKeyExistsErr) }
        registered[id] = shortcut
        return noErr
    }

    func unregister(id: UInt32) {
        registered[id] = nil
    }

    var liveShortcuts: Set<Shortcut> { Set(registered.values) }

    /// Simulates the system delivering a press of `shortcut`.
    func press(_ shortcut: Shortcut) {
        guard let id = registered.first(where: { $0.value == shortcut })?.key else { return }
        onPress?(id)
    }
}

@MainActor
private func makeDefaults() -> UserDefaults {
    let suite = "NotchyTests.Shortcuts.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
private func makeManager(
    defaults: UserDefaults = makeDefaults()
) -> (ShortcutsManager, FakeHotKeyBackend, ShortcutsSettings) {
    let backend = FakeHotKeyBackend()
    let settings = ShortcutsSettings(defaults: defaults)
    let manager = ShortcutsManager(settings: settings, hotKeys: HotKeyCenter(backend: backend))
    return (manager, backend, settings)
}

private let commandShiftV = Shortcut(kVK_ANSI_V, [.command, .shift])

@MainActor
struct ShortcutsTests {
    // MARK: Shortcut value

    @Test
    func modifiersPrintInMenuOrder() {
        #expect(commandShiftV.displayString(keyName: "V") == "⇧⌘V")
        let all = Shortcut(kVK_ANSI_K, [.command, .shift, .option, .control])
        #expect(all.displayString(keyName: "K") == "⌃⌥⇧⌘K")
        #expect(Shortcut(kVK_ANSI_Grave, [.control]).displayString(keyName: "`") == "⌃`")
    }

    @Test
    func modifierEncodingsRoundTrip() {
        for raw in UInt8(0)..<16 {
            let modifiers = ShortcutModifiers(rawValue: raw)
            #expect(ShortcutModifiers(carbon: modifiers.carbonFlags) == modifiers)
            #expect(ShortcutModifiers(modifiers.eventFlags) == modifiers)
        }
        #expect(ShortcutModifiers([.command, .shift]).carbonFlags == UInt32(cmdKey | shiftKey))
        #expect(ShortcutModifiers(NSEvent.ModifierFlags([.command, .capsLock, .function])) == .command)
    }

    @Test
    func specialKeysUseFixedGlyphs() {
        #expect(Shortcut(kVK_Space, [.command]).keyName == "Space")
        #expect(Shortcut(kVK_Return, [.command]).keyName == "↩")
        #expect(Shortcut(kVK_Delete, [.command]).keyName == "⌫")
        #expect(Shortcut(kVK_UpArrow, [.control]).keyName == "↑")
        #expect(Shortcut(kVK_F12, []).keyName == "F12")
        #expect(Shortcut(kVK_F1, [.command]).displayString == "⌘F1")
        #expect(Shortcut(kVK_F5, []).isFunctionKey)
        #expect(!Shortcut(kVK_ANSI_5, []).isFunctionKey)
        #expect(Shortcut(kVK_ANSI_V, []).fallbackKeyName == "V")
    }

    @Test
    func letterKeysTranslateThroughTheActiveLayout() {
        // Whatever the layout, the V key prints one visible character, uppercased.
        let name = commandShiftV.keyName
        #expect(!name.isEmpty)
        #expect(name == name.uppercased())
        #expect(commandShiftV.displayString == "⇧⌘" + name)
        #expect(commandShiftV.keyEquivalent != nil)
    }

    @Test
    func specialKeysMapToKeyEquivalents() {
        #expect(Shortcut(kVK_Escape, [.command]).keyEquivalent == .escape)
        #expect(Shortcut(kVK_LeftArrow, [.command]).keyEquivalent == .leftArrow)
        let f2 = Shortcut(kVK_F2, [.command]).keyEquivalent
        #expect(f2?.character.unicodeScalars.first?.value == UInt32(NSF2FunctionKey))
    }

    // MARK: Actions

    @Test
    func defaultsMatchAtoll() {
        let expected: [ShortcutAction: Shortcut] = [
            .toggleNotchOpen: Shortcut(kVK_ANSI_I, [.command, .shift]),
            .clipboardHistoryPanel: Shortcut(kVK_ANSI_V, [.command, .shift]),
            .colorPickerPanel: Shortcut(kVK_ANSI_P, [.command, .shift]),
            .toggleSneakPeek: Shortcut(kVK_ANSI_H, [.command, .shift]),
            .startDemoTimer: Shortcut(kVK_ANSI_T, [.command, .shift]),
            .toggleCaffeinate: Shortcut(kVK_ANSI_K, [.command, .shift]),
            .screenAssistantPanel: Shortcut(kVK_ANSI_A, [.command, .shift]),
            .toggleTerminalTab: Shortcut(kVK_ANSI_Grave, [.control]),
            .quickPaste: Shortcut(kVK_ANSI_V, [.control, .command]),
            .openLibrary: Shortcut(kVK_ANSI_L, [.control, .command]),
        ]
        for action in ShortcutAction.allCases {
            #expect(action.defaultShortcut == expected[action], "\(action)")
        }
        let defaults = ShortcutAction.allCases.compactMap(\.defaultShortcut)
        #expect(Set(defaults).count == defaults.count, "no two defaults collide")
        #expect(ShortcutAction.toggleNotchOpen.rawValue == "toggleNotchOpen")
        #expect(ShortcutAction.clipboardHistoryPanel.recorderTitle == "Clipboard History:")
    }

    @Test
    func groupsFollowAtollSectionOrder() {
        #expect(ShortcutGroup.allCases.map(\.header) == [
            "Media", "Keep Awake", "Navigation", "Timer", "Clipboard", "AI Assistant", "Terminal", "Color Picker",
        ])
        #expect(ShortcutGroup.clipboard.actions == [.clipboardHistoryPanel, .quickPaste, .openLibrary])
    }

    // MARK: Validation

    @Test
    func structuralRulesMatchTheRecorder() {
        #expect(ShortcutValidation.structuralIssue(Shortcut(kVK_ANSI_V, [])) == .needsModifier)
        #expect(ShortcutValidation.structuralIssue(Shortcut(kVK_ANSI_V, [.shift])) == .needsModifier)
        #expect(ShortcutValidation.structuralIssue(Shortcut(kVK_ANSI_V, [.option])) == .optionNeedsCommandOrControl)
        #expect(ShortcutValidation.structuralIssue(Shortcut(kVK_ANSI_V, [.option, .shift])) == .optionNeedsCommandOrControl)
        #expect(ShortcutValidation.structuralIssue(Shortcut(kVK_ANSI_V, [.option, .command])) == nil)
        #expect(ShortcutValidation.structuralIssue(commandShiftV) == nil)
        #expect(ShortcutValidation.structuralIssue(Shortcut(kVK_ANSI_Grave, [.control])) == nil)
        #expect(ShortcutValidation.structuralIssue(Shortcut(kVK_F6, [])) == nil)
    }

    @Test
    func systemEntriesNeedingTheGlobeKeyAreIgnored() {
        let fn = UInt32(kEventKeyModifierFnMask)
        // Globe-Q (Quick Note) cannot clash with any hot key.
        #expect(ShortcutValidation.systemShortcut(keyCode: UInt32(kVK_ANSI_Q), carbonModifiers: fn) == nil)
        // Globe-Control-F (full screen) must not block Control-F.
        #expect(ShortcutValidation.systemShortcut(keyCode: UInt32(kVK_ANSI_F), carbonModifiers: fn | UInt32(controlKey)) == nil)
        // On arrows the Fn bit is implicit: Control-Up (Mission Control) still counts.
        #expect(ShortcutValidation.systemShortcut(keyCode: UInt32(kVK_UpArrow), carbonModifiers: fn | UInt32(controlKey))
            == Shortcut(kVK_UpArrow, [.control]))
        // A bare F-key (Show Desktop on F11) counts; a bare letter does not.
        #expect(ShortcutValidation.systemShortcut(keyCode: UInt32(kVK_F11), carbonModifiers: 0) == Shortcut(kVK_F11, []))
        #expect(ShortcutValidation.systemShortcut(keyCode: UInt32(kVK_ANSI_A), carbonModifiers: 0) == nil)
        #expect(ShortcutValidation.systemShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey))
            == Shortcut(kVK_Space, [.command]))
        #expect(ShortcutValidation.isTakenBySystem(Shortcut(kVK_Tab, [.command])), "⌘⇥ is always reserved")
    }

    @Test
    func menuConflictsAreFoundInSubmenus() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let submenu = NSMenu()
        submenu.addItem(NSMenuItem(title: "Paste and Match Style", action: nil, keyEquivalent: "V"))
        let quit = NSMenuItem(title: "Quit", action: nil, keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        submenu.addItem(quit)
        appItem.submenu = submenu
        main.addItem(appItem)

        let commandQ = Shortcut(kVK_ANSI_Q, [.command])
        let commandQKey = commandQ.menuKeyEquivalent?.lowercased()
        // Only meaningful on layouts where the Q key types "q".
        if commandQKey == "q" {
            #expect(ShortcutValidation.menuItemTitle(using: commandQ, in: main) == "Quit")
            #expect(ShortcutValidation.menuItemTitle(using: Shortcut(kVK_ANSI_Q, [.command, .shift]), in: main) == nil)
        }
        if commandShiftV.menuKeyEquivalent?.lowercased() == "v" {
            // An uppercase key equivalent implies Shift.
            #expect(ShortcutValidation.menuItemTitle(using: commandShiftV, in: main) == "Paste and Match Style")
        }
    }

    // MARK: Persistence

    @Test
    func settingsStartFromAtollDefaults() {
        let settings = ShortcutsSettings(defaults: makeDefaults())
        #expect(settings.isEnabled)
        #expect(settings.allDefaults)
        for action in ShortcutAction.allCases {
            #expect(settings.shortcut(for: action) == action.defaultShortcut)
        }
    }

    @Test
    func customClearedAndResetBindingsPersist() {
        let defaults = makeDefaults()
        let settings = ShortcutsSettings(defaults: defaults)
        let custom = Shortcut(kVK_ANSI_J, [.control, .option, .command])
        settings.setShortcut(custom, for: .toggleNotchOpen)
        settings.setShortcut(nil, for: .startDemoTimer)
        settings.isEnabled = false

        let reloaded = ShortcutsSettings(defaults: defaults)
        #expect(reloaded.shortcut(for: .toggleNotchOpen) == custom)
        #expect(reloaded.shortcut(for: .startDemoTimer) == nil, "a cleared shortcut must not fall back to the default")
        #expect(!reloaded.isDefault(.startDemoTimer))
        #expect(!reloaded.isEnabled)
        #expect(defaults.dictionary(forKey: "shortcuts.binding.toggleNotchOpen") != nil)

        reloaded.resetToDefault(.startDemoTimer)
        #expect(reloaded.shortcut(for: .startDemoTimer) == ShortcutAction.startDemoTimer.defaultShortcut)
        reloaded.resetAllToDefaults()
        #expect(reloaded.allDefaults)
        #expect(ShortcutsSettings(defaults: defaults).shortcut(for: .toggleNotchOpen) == ShortcutAction.toggleNotchOpen.defaultShortcut)
    }

    @Test
    func savingTheDefaultValueStoresNothing() {
        let defaults = makeDefaults()
        let settings = ShortcutsSettings(defaults: defaults)
        settings.setShortcut(ShortcutAction.quickPaste.defaultShortcut, for: .quickPaste)
        #expect(settings.isDefault(.quickPaste))
        #expect(defaults.object(forKey: ShortcutsSettings.Key.binding(.quickPaste)) == nil)
    }

    @Test
    func unreadableBindingsFallBackToDefault() {
        let defaults = makeDefaults()
        defaults.set("garbage", forKey: ShortcutsSettings.Key.binding(.colorPickerPanel))
        defaults.set(["keyCode": 9], forKey: ShortcutsSettings.Key.binding(.toggleSneakPeek))
        let settings = ShortcutsSettings(defaults: defaults)
        #expect(settings.shortcut(for: .colorPickerPanel) == ShortcutAction.colorPickerPanel.defaultShortcut)
        #expect(settings.shortcut(for: .toggleSneakPeek) == ShortcutAction.toggleSneakPeek.defaultShortcut)
    }

    // MARK: HotKeyCenter

    @Test
    func centerRegistersRebindsAndDispatches() {
        let backend = FakeHotKeyBackend()
        let center = HotKeyCenter(backend: backend)
        var presses: [String] = []

        #expect((try? center.register(id: "a", shortcut: commandShiftV) { presses.append("a") }.get()) != nil)
        #expect(backend.liveShortcuts == [commandShiftV])
        backend.press(commandShiftV)
        #expect(presses == ["a"])

        let other = Shortcut(kVK_ANSI_B, [.command, .option])
        #expect((try? center.rebind(id: "a", to: other).get()) != nil)
        #expect(backend.liveShortcuts == [other])
        backend.press(other)
        #expect(presses == ["a", "a"])

        center.unregister(id: "a")
        #expect(backend.liveShortcuts.isEmpty)
        #expect(center.registeredIDs.isEmpty)
    }

    @Test
    func centerRejectsDuplicatesAndReportsSystemRefusals() {
        let backend = FakeHotKeyBackend()
        let center = HotKeyCenter(backend: backend)
        center.register(id: "a", shortcut: commandShiftV) {}

        let duplicate = center.register(id: "b", shortcut: commandShiftV) {}
        #expect(duplicate.failureValue == .duplicate(ownerID: "a"))
        #expect(center.owner(of: commandShiftV) == "a")

        let taken = Shortcut(kVK_ANSI_K, [.command, .shift])
        backend.refused = [taken]
        #expect(center.register(id: "b", shortcut: taken) {}.failureValue == .alreadyTaken)
        #expect(center.shortcut(for: "b") == nil)

        // Re-registering the same keys only swaps the handler.
        let calls = backend.registerCalls
        center.register(id: "a", shortcut: commandShiftV) {}
        #expect(backend.registerCalls == calls)
    }

    @Test
    func pausingReleasesKeysAndResumeRestoresThem() {
        let backend = FakeHotKeyBackend()
        let center = HotKeyCenter(backend: backend)
        var fired = 0
        center.register(id: "a", shortcut: commandShiftV) { fired += 1 }

        center.pause()
        #expect(center.isPaused)
        #expect(backend.liveShortcuts.isEmpty)
        center.handlePress(numericID: 1)
        #expect(fired == 0)

        // Registrations made while paused wait for resume.
        let other = Shortcut(kVK_ANSI_L, [.control, .command])
        center.register(id: "b", shortcut: other) {}
        #expect(backend.liveShortcuts.isEmpty)

        center.pause()
        center.resume()
        #expect(center.isPaused, "pauses nest")
        let failures = center.resume()
        #expect(failures.isEmpty)
        #expect(backend.liveShortcuts == [commandShiftV, other])
        backend.press(commandShiftV)
        #expect(fired == 1)
    }

    // MARK: ShortcutsManager

    @Test
    func managerClaimsOnlyBoundEnabledActions() {
        let (manager, backend, settings) = makeManager()
        var log: [ShortcutAction] = []
        manager.bind(.toggleNotchOpen) { log.append(.toggleNotchOpen) }
        #expect(backend.liveShortcuts.isEmpty, "nothing is claimed before start")

        manager.start()
        #expect(backend.liveShortcuts == [Shortcut(kVK_ANSI_I, [.command, .shift])])

        manager.bind(.quickPaste) { log.append(.quickPaste) }
        #expect(backend.liveShortcuts.count == 2)
        backend.press(Shortcut(kVK_ANSI_V, [.control, .command]))
        #expect(log == [.quickPaste])

        settings.isEnabled = false
        #expect(backend.liveShortcuts.isEmpty)
        #expect(!manager.perform(.quickPaste))

        settings.isEnabled = true
        #expect(backend.liveShortcuts.count == 2)

        manager.stop()
        #expect(backend.liveShortcuts.isEmpty)
    }

    @Test
    func featureAvailabilityGatesTheKey() {
        let (manager, backend, _) = makeManager()
        let featureEnabled = CurrentValueSubject<Bool, Never>(false)
        var started = 0
        manager.bind(.startDemoTimer, availability: featureEnabled) { started += 1 }
        manager.start()
        #expect(!manager.isAvailable(.startDemoTimer))
        #expect(backend.liveShortcuts.isEmpty)
        #expect(!manager.perform(.startDemoTimer))

        featureEnabled.send(true)
        #expect(backend.liveShortcuts == [Shortcut(kVK_ANSI_T, [.command, .shift])])
        backend.press(Shortcut(kVK_ANSI_T, [.command, .shift]))
        #expect(started == 1)

        manager.unbind(.startDemoTimer)
        #expect(backend.liveShortcuts.isEmpty)
    }

    @Test
    func rebindingAndClearingFollowSettings() {
        let (manager, backend, _) = makeManager()
        manager.bind(.openLibrary) {}
        manager.start()

        let custom = Shortcut(kVK_ANSI_L, [.option, .command])
        #expect(manager.assign(custom, to: .openLibrary) == nil || ShortcutValidation.isTakenBySystem(custom))
        if !ShortcutValidation.isTakenBySystem(custom) {
            #expect(backend.liveShortcuts == [custom])
        }

        manager.clear(.openLibrary)
        #expect(backend.liveShortcuts.isEmpty)

        manager.resetToDefault(.openLibrary)
        #expect(backend.liveShortcuts == [Shortcut(kVK_ANSI_L, [.control, .command])])
    }

    @Test
    func conflictsWithOtherActionsCanBeReassigned() {
        let (manager, backend, settings) = makeManager()
        manager.bind(.clipboardHistoryPanel) {}
        manager.bind(.quickPaste) {}
        manager.start()

        let issue = manager.assign(commandShiftV, to: .quickPaste)
        #expect(issue == .usedByAction(.clipboardHistoryPanel))
        #expect(settings.shortcut(for: .quickPaste) == ShortcutAction.quickPaste.defaultShortcut)

        let accepted: [ShortcutIssue] = [.usedByAction(.clipboardHistoryPanel), .usedBySystem]
        #expect(manager.assign(commandShiftV, to: .quickPaste, accepting: accepted) == nil)
        #expect(settings.shortcut(for: .quickPaste) == commandShiftV)
        #expect(settings.shortcut(for: .clipboardHistoryPanel) == nil)
        #expect(backend.liveShortcuts == [commandShiftV])
        #expect(manager.failures.isEmpty)
    }

    @Test
    func structuralIssuesCannotBeOverridden() {
        let (manager, _, settings) = makeManager()
        let bare = Shortcut(kVK_ANSI_V, [])
        #expect(manager.assign(bare, to: .quickPaste, accepting: [.needsModifier]) == .needsModifier)
        let optionOnly = Shortcut(kVK_ANSI_V, [.option])
        #expect(manager.assign(optionOnly, to: .quickPaste) == .optionNeedsCommandOrControl)
        #expect(settings.shortcut(for: .quickPaste) == ShortcutAction.quickPaste.defaultShortcut)
    }

    @Test
    func unlistedActionsDoNotBlockTheirDefaultKeys() {
        let (manager, _, _) = makeManager()
        let commandShiftA = Shortcut(kVK_ANSI_A, [.command, .shift])
        #expect(!manager.isListed(.screenAssistantPanel))
        #expect(!manager.issues(for: commandShiftA, assigningTo: .quickPaste).contains(.usedByAction(.screenAssistantPanel)))

        manager.bind(.screenAssistantPanel) {}
        #expect(manager.isListed(.screenAssistantPanel))
        #expect(manager.issues(for: commandShiftA, assigningTo: .quickPaste).contains(.usedByAction(.screenAssistantPanel)))
    }

    @Test
    func recordingPausesEveryShortcut() {
        let (manager, backend, _) = makeManager()
        var fired = 0
        manager.bind(.toggleSneakPeek) { fired += 1 }
        manager.start()
        #expect(backend.liveShortcuts.count == 1)

        manager.beginRecording(.toggleSneakPeek)
        #expect(backend.liveShortcuts.isEmpty)
        #expect(!manager.perform(.toggleSneakPeek))
        #expect(manager.isActive(.toggleSneakPeek))

        manager.endRecording()
        #expect(backend.liveShortcuts.count == 1)
        #expect(manager.perform(.toggleSneakPeek))
        #expect(fired == 1)
    }

    @Test
    func refusedKeysSurfaceAsFailures() {
        let (manager, backend, _) = makeManager()
        let caffeinate = Shortcut(kVK_ANSI_K, [.command, .shift])
        backend.refused = [caffeinate]
        manager.bind(.toggleCaffeinate) {}
        manager.start()
        #expect(manager.failures[.toggleCaffeinate] == .alreadyTaken)
        #expect(!manager.isActive(.toggleCaffeinate))

        backend.refused = []
        manager.sync()
        #expect(manager.failures.isEmpty)
        #expect(backend.liveShortcuts == [caffeinate])
    }
}

@MainActor
struct ShortcutsRecorderParityTests {
    @Test
    func recorderIsACentredSearchFieldLikeAtolls() {
        let (manager, _, _) = makeManager()
        let field = ShortcutRecorderField(action: .quickPaste, manager: manager)
        #expect(field.placeholderString == "Record Shortcut")
        #expect(field.alignment == .center)
        #expect((field.cell as? NSSearchFieldCell)?.searchButtonCell == nil)
        #expect(field.intrinsicContentSize.width == 130)
        #expect(!field.canBecomeKeyView, "never takes initial focus")

        field.apply(text: "", isEnabled: true)
        #expect((field.cell as? NSSearchFieldCell)?.cancelButtonCell == nil, "no clear button while empty")
        field.apply(text: "⌃⌘V", isEnabled: true)
        #expect(field.stringValue == "⌃⌘V")
        #expect((field.cell as? NSSearchFieldCell)?.cancelButtonCell != nil)
        field.apply(text: "⌃⌘V", isEnabled: false)
        #expect(!field.isEnabled)
        #expect(!field.isRecording)
    }

    @Test
    func rowsAreBuiltLikeAtollsSections() {
        #expect(ShortcutGroup.media.rowLayout == .bare)
        #expect(ShortcutGroup.navigation.rowLayout == .bare)
        #expect(ShortcutGroup.keepAwake.rowLayout == .stacked)
        for group in [ShortcutGroup.timer, .clipboard, .aiAssistant, .terminal, .colorPicker] {
            #expect(group.rowLayout == .stackedWithSpacer, "\(group)")
        }
    }

    @Test
    func shortcutTextUsesAnASCIICapableLayout() {
        let name = Shortcut(kVK_ANSI_V, [.command, .shift]).keyName
        #expect(name.count == 1)
        let isASCII = name.allSatisfy { $0.isASCII }
        #expect(isASCII)
    }

    @Test
    func optionOnlyIsRefusedAfterMenuAndBeforeSystemChecks() {
        let (manager, _, _) = makeManager()
        let optionV = Shortcut(kVK_ANSI_V, [.option])
        let issues = manager.issues(for: optionV, assigningTo: .quickPaste)
        if #available(macOS 15, *) {
            #expect(issues.first(where: { if case .usedByMenuItem = $0 { false } else { true } })
                == .optionNeedsCommandOrControl)
        }
        #expect(manager.issues(for: Shortcut(kVK_ANSI_V, [.shift]), assigningTo: .quickPaste) == [.needsModifier])
    }
}

private extension Result {
    var failureValue: Failure? {
        if case let .failure(error) = self { return error }
        return nil
    }
}
