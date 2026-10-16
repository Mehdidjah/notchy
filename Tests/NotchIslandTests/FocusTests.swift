import Combine
import Foundation
import SwiftUI
import Testing
@testable import NotchIsland

@MainActor
struct FocusTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "FocusTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: Mode identification

    @Test
    func identifiersMapToModes() {
        #expect(FocusModeKind(identifier: "com.apple.donotdisturb.mode.default") == .doNotDisturb)
        #expect(FocusModeKind(identifier: "com.apple.sleep.sleep-mode") == .sleep)
        #expect(FocusModeKind(identifier: "com.apple.focus.personal-time") == .personal)
        #expect(FocusModeKind(identifier: "com.apple.focus.work") == .work)
        #expect(FocusModeKind(identifier: "com.apple.focus.reduce-interruptions") == .reduceInterruptions)
        #expect(FocusModeKind(identifier: "com.apple.donotdisturb.mode.graduationcap.fill") == .custom)
        #expect(FocusModeKind(identifier: "com.apple.focus.homework") == .custom)
        #expect(FocusModeKind(identifier: "") == .doNotDisturb)
    }

    @Test
    func namesWinOverIdentifiers() {
        #expect(FocusModeKind.resolve(identifier: "com.apple.focus.work", name: "Sleep") == .sleep)
        #expect(FocusModeKind.resolve(identifier: nil, name: "personal-time") == .personal)
        #expect(FocusModeKind.resolve(identifier: nil, name: "Travail") == .custom, "unknown names are custom, not DND")
        #expect(FocusModeKind.resolve(identifier: nil, name: nil) == .doNotDisturb)
    }

    @Test
    func modesUsePublicSymbolsAndAtollsColours() {
        #expect(FocusModeKind.doNotDisturb.symbolName == "moon.fill")
        #expect(FocusModeKind.doNotDisturb.inactiveSymbolName == "moon.circle.fill")
        #expect(FocusModeKind.sleep.symbolName == "bed.double.fill")
        #expect(FocusModeKind.allCases.allSatisfy { !$0.symbolName.isEmpty })
        #expect(FocusTint.color(named: "systemTealColor") == .teal)
        #expect(FocusTint.color(named: "nonsense") == .indigo)
        let custom = FocusAppearance(
            kind: .custom,
            configuration: FocusModeConfiguration(name: "Study", identifier: "x", symbolName: "book.fill", tintColorName: "systemGreenColor")
        )
        #expect(custom.symbolName == "book.fill")
        #expect(custom.accent == .green)
    }

    // MARK: Database parsing

    @Test
    func assertionsFileDecidesOnOff() throws {
        let active = Data("""
        {"data":[{"storeAssertionRecords":[{"assertionUUID":"1234","assertionDetails":{
          "assertionDetailsIdentifier":"com.apple.controlcenter.dnd",
          "assertionDetailsModeIdentifier":"com.apple.sleep.sleep-mode"}}]}],"header":{}}
        """.utf8)
        let reading = try #require(FocusDatabase.parseAssertions(active))
        #expect(reading.isActive)
        #expect(reading.identifier == "com.apple.sleep.sleep-mode")

        let inactive = Data(#"{"data":[{"storeAssertionRecords":[]}]}"#.utf8)
        #expect(FocusDatabase.parseAssertions(inactive) == .inactive)
        #expect(FocusDatabase.parseAssertions(Data("garbage".utf8)) == nil)
    }

    @Test
    func modeConfigurationsAreReadAndMatched() {
        let data = Data("""
        {"data":[{"modeConfigurations":{
          "com.apple.donotdisturb.mode.graduationcap.fill":{"mode":{"name":"Study",
            "modeIdentifier":"com.apple.donotdisturb.mode.graduationcap.fill",
            "symbolImageName":"graduationcap.fill","tintColorName":"systemOrangeColor"}},
          "com.apple.focus.work":{"mode":{"name":"Work","modeIdentifier":"com.apple.focus.work"}}
        }}]}
        """.utf8)
        let configurations = FocusDatabase.parseModeConfigurations(data)
        #expect(configurations.count == 2)
        let study = FocusDatabase.configuration(
            in: configurations, identifier: "com.apple.donotdisturb.mode.graduationcap.fill", name: nil
        )
        #expect(study?.name == "Study")
        #expect(study?.symbolName == "graduationcap.fill")
        #expect(FocusDatabase.configuration(in: configurations, identifier: nil, name: "work")?.identifier == "com.apple.focus.work")
    }

    @Test
    func notificationPayloadsAndLogLinesYieldMetadata() {
        let metadata = FocusPayloadSearch.metadata(
            userInfo: ["details": ["modeIdentifier": "com.apple.focus.fitness", "displayName": "Fitness"]],
            object: nil
        )
        #expect(metadata.identifier == "com.apple.focus.fitness")
        #expect(metadata.name == "Fitness")

        let line = "2026-10-16 10:00:00.000 I  donotdisturbd[1:2] <DNDMode: 0x1; name: Lock In; modeIdentifier: com.apple.donotdisturb.mode.lock; symbol: x>"
        #expect(FocusPayloadSearch.logEvent(fromLine: line)
            == .metadata(FocusMetadata(identifier: "com.apple.donotdisturb.mode.lock", name: "Lock In")))
        #expect(FocusPayloadSearch.logEvent(fromLine: "activeModeIdentifier: (null)") == .cleared)
        #expect(FocusPayloadSearch.logEvent(fromLine: "Filtering the log data using ...") == nil)
    }

    // MARK: Monitor

    @Test
    func settingsDefaultToAtollsChoices() {
        let settings = FocusSettings(defaults: makeDefaults())
        #expect(settings.enableDoNotDisturbDetection)
        #expect(settings.showDoNotDisturbIndicator)
        #expect(settings.showDoNotDisturbLabel)
        #expect(!settings.focusIndicatorNonPersistent)
        #expect(settings.monitoringMode == .standard)
    }

    @Test
    func bareNotificationDefaultsToDoNotDisturb() {
        let monitor = FocusMonitor(settings: FocusSettings(defaults: makeDefaults()))
        monitor.apply(metadata: FocusMetadata(), isActive: true)
        #expect(monitor.isActive)
        #expect(monitor.modeKind == .doNotDisturb)
        #expect(monitor.modeName == "Do Not Disturb")
    }

    @Test
    func modeSwitchWhileOnReplaysTheToastAndOffKeepsTheMode() {
        let monitor = FocusMonitor(settings: FocusSettings(defaults: makeDefaults()))
        monitor.apply(metadata: FocusMetadata(identifier: "com.apple.focus.work", name: nil), isActive: true)
        #expect(monitor.modeName == "Work")
        let trigger = monitor.toastTrigger

        monitor.apply(metadata: FocusMetadata(identifier: "com.apple.sleep.sleep-mode", name: nil), isActive: true)
        #expect(monitor.modeKind == .sleep)
        #expect(monitor.toastTrigger != trigger)

        monitor.apply(metadata: FocusMetadata(), isActive: false)
        #expect(!monitor.isActive)
        #expect(monitor.modeKind == .sleep, "the ended mode stays for the off animation")
    }

    @Test
    func customSlugNamesAreNotShown() {
        let monitor = FocusMonitor(settings: FocusSettings(defaults: makeDefaults()))
        monitor.apply(
            metadata: FocusMetadata(identifier: "com.apple.donotdisturb.mode.graduationcap.fill", name: "graduationcap.fill"),
            isActive: true
        )
        #expect(monitor.modeKind == .custom)
        #expect(monitor.modeName == "Focus")
    }

    // MARK: Layout

    @Test
    func persistentLabelWingFollowsAtollsWidths() {
        var display = FocusWingDisplay()
        display.isVisible = true
        display.isExpanded = true
        display.labelText = "Do Not Disturb"
        display.isDoNotDisturb = true
        let dnd = FocusWingLayout.make(
            display: display, closedHeight: 32, notchWidth: 185, labelIntrinsicWidth: 90, marqueeThreshold: 90
        )
        #expect(dnd.iconWidth == 24, "max(32 - 12, 24)")
        #expect(dnd.labelWidth == 164, "max(185 * 0.52, 136, 164)")
        #expect(!dnd.usesMarquee)

        display.isDoNotDisturb = false
        display.labelText = "A much longer focus name"
        let long = FocusWingLayout.make(
            display: display, closedHeight: 32, notchWidth: 185, labelIntrinsicWidth: 150, marqueeThreshold: 90
        )
        #expect(long.usesMarquee)
        #expect(long.labelWidth == 136)
        #expect(long.marqueeFrameWidth == 128)
    }

    @Test
    func toastWingHugsTheShortLabel() {
        var display = FocusWingDisplay()
        display.isExpanded = true
        display.toastMode = true
        display.labelText = "On"
        let layout = FocusWingLayout.make(
            display: display, closedHeight: 38, notchWidth: 185, labelIntrinsicWidth: 16, marqueeThreshold: 90
        )
        #expect(layout.labelWidth == 42, "16 + 26")
        #expect(layout.iconWidth == 26)

        display.isExpanded = false
        let collapsed = FocusWingLayout.make(
            display: display, closedHeight: 38, notchWidth: 185, labelIntrinsicWidth: 16, marqueeThreshold: 90
        )
        #expect(collapsed.iconWidth == 0)
        #expect(collapsed.labelWidth == 0)
    }

    @Test
    func labelTextFollowsTheMode() {
        #expect(FocusActivity.labelText(active: true, toast: true, showLabel: false, modeName: "Work", kind: .work) == "On")
        #expect(FocusActivity.labelText(active: false, toast: true, showLabel: true, modeName: "Work", kind: .work) == "Off")
        #expect(FocusActivity.labelText(active: true, toast: false, showLabel: true, modeName: "", kind: .doNotDisturb) == "Do Not Disturb")
        #expect(FocusActivity.labelText(active: true, toast: false, showLabel: false, modeName: "Work", kind: .work).isEmpty)
    }

    // MARK: Activity

    @Test
    func activityExpandsWhileFocusIsOn() async throws {
        let settings = FocusSettings(defaults: makeDefaults())
        let monitor = FocusMonitor(settings: settings)
        let activity = FocusActivity(monitor: monitor)
        #expect(activity.activityID == "focus")
        #expect(activity.priority == ClosedActivityPriority.focus)
        #expect(!activity.isActivityVisible)

        monitor.apply(metadata: FocusMetadata(identifier: "com.apple.focus.driving", name: nil), isActive: true)
        activity.sync()
        #expect(activity.isActivityVisible)
        #expect(activity.display.labelText == "Driving")
        #expect(activity.display.iconColor == FocusModeKind.driving.accentColor)

        settings.showDoNotDisturbIndicator = false
        activity.sync()
        #expect(!activity.isActivityVisible)
    }

    @Test
    func activityReportsOnlyVisibilityAndWidthChanges() {
        let settings = FocusSettings(defaults: makeDefaults())
        let monitor = FocusMonitor(settings: settings)
        let activity = FocusActivity(monitor: monitor)
        var notifications = 0
        let token = activity.activityDidChange.sink { notifications += 1 }
        defer { token.cancel() }

        monitor.apply(metadata: FocusMetadata(identifier: "com.apple.focus.work", name: nil), isActive: true)
        activity.sync()
        #expect(notifications == 1, "appearing")

        activity.sync()
        #expect(notifications == 1, "nothing changed")

        monitor.apply(metadata: FocusMetadata(identifier: "com.apple.focus.reading", name: nil), isActive: true)
        activity.sync()
        #expect(notifications == 2, "a new label can change the label wing")
        #expect(activity.wingModel.display.labelText == "Reading")

        settings.showDoNotDisturbLabel = false
        activity.sync()
        #expect(notifications == 3)
        #expect(activity.rightWingWidth(in: ClosedActivityContext(
            closedHeight: 32, notchWidth: 185, isHovering: false, gestureProgress: 0, hasHardwareNotch: true
        )) == 24, "without a label the right wing is the minimal square")
    }

    @Test
    func toastModeShowsOnThenFoldsAway() async throws {
        let settings = FocusSettings(defaults: makeDefaults())
        settings.focusIndicatorNonPersistent = true
        let monitor = FocusMonitor(settings: settings)
        let activity = FocusActivity(monitor: monitor)

        monitor.apply(metadata: FocusMetadata(), isActive: true)
        activity.sync()
        #expect(activity.isActivityVisible)
        #expect(activity.display.labelText == "On")

        try await Task.sleep(for: .milliseconds(2_100))
        #expect(!activity.isActivityVisible, "the toast collapses after 1.8 s")
    }

    @Test
    func modeSwitchDuringTheToastSnapsShutThenReopens() async throws {
        let settings = FocusSettings(defaults: makeDefaults())
        settings.focusIndicatorNonPersistent = true
        let monitor = FocusMonitor(settings: settings)
        let activity = FocusActivity(monitor: monitor)
        monitor.apply(metadata: FocusMetadata(identifier: "com.apple.focus.work", name: nil), isActive: true)
        activity.sync()
        #expect(activity.display.isExpanded)

        monitor.apply(metadata: FocusMetadata(identifier: "com.apple.focus.reading", name: nil), isActive: nil)
        activity.sync()
        #expect(activity.isActivityVisible, "the island keeps the activity while its wings are shut")
        #expect(!activity.display.isExpanded, "the wings snap shut first")

        try await Task.sleep(for: .milliseconds(150))
        #expect(activity.display.isExpanded, "then spring open for the new mode")
        #expect(activity.display.iconColor == FocusModeKind.reading.accentColor)
        #expect(activity.display.labelText == "On")
    }

    @Test
    func persistentModeFoldsAwayAsSoonAsFocusEnds() {
        let monitor = FocusMonitor(settings: FocusSettings(defaults: makeDefaults()))
        let activity = FocusActivity(monitor: monitor)
        monitor.apply(metadata: FocusMetadata(), isActive: true)
        activity.sync()
        #expect(activity.isActivityVisible)

        monitor.apply(metadata: FocusMetadata(), isActive: false)
        activity.sync()
        #expect(!activity.isActivityVisible, "shipped Atoll unmounts the persistent view at once")
    }

    @Test
    func toastModeTurningOffShowsWhiteOffThenFolds() async throws {
        let settings = FocusSettings(defaults: makeDefaults())
        settings.focusIndicatorNonPersistent = true
        let monitor = FocusMonitor(settings: settings)
        let activity = FocusActivity(monitor: monitor)
        monitor.apply(metadata: FocusMetadata(), isActive: true)
        activity.sync()
        monitor.apply(metadata: FocusMetadata(), isActive: false)
        activity.sync()
        #expect(activity.isActivityVisible)
        #expect(activity.display.labelText == "Off")
        #expect(activity.display.labelColor == .white)
        #expect(activity.display.iconColor == .white)
        #expect(activity.display.symbolName == "moon.circle.fill")

        try await Task.sleep(for: .milliseconds(1_800))
        #expect(!activity.isActivityVisible, "the off toast folds after 1.5 s")
    }
}
