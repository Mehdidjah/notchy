import AppKit
import Combine
import Foundation
import SwiftUI
import Testing
@testable import NotchIsland

@MainActor
struct BluetoothTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "BluetoothTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func context(hovering: Bool = false, gesture: CGFloat = 0, notchWidth: CGFloat = 185) -> ClosedActivityContext {
        ClosedActivityContext(
            closedHeight: 32,
            notchWidth: notchWidth,
            isHovering: hovering,
            gestureProgress: gesture,
            hasHardwareNotch: true
        )
    }

    private let sampleDevice = BluetoothAudioDevice(address: "aa-bb-cc-dd-ee-ff", name: "Mehdi's AirPods Pro", kind: .airpodsPro)

    // MARK: Device classification

    @Test
    func detectsKindsFromNamesLikeAtoll() {
        #expect(BluetoothAudioDeviceKind.detect(name: "Mehdi's AirPods Pro", classOfDevice: 0) == .airpodsPro)
        #expect(BluetoothAudioDeviceKind.detect(name: "AirPods Pro 3", classOfDevice: 0) == .airpodsPro3)
        #expect(BluetoothAudioDeviceKind.detect(name: "AirPods Max", classOfDevice: 0) == .airpodsMax)
        #expect(BluetoothAudioDeviceKind.detect(name: "AirPods 4", classOfDevice: 0) == .airpodsGen4)
        #expect(BluetoothAudioDeviceKind.detect(name: "AirPods (3rd generation)", classOfDevice: 0) == .airpodsGen3)
        #expect(BluetoothAudioDeviceKind.detect(name: "AirPods", classOfDevice: 0) == .airpods)
        #expect(BluetoothAudioDeviceKind.detect(name: "Beats Studio Pro", classOfDevice: 0) == .beatsStudio)
        #expect(BluetoothAudioDeviceKind.detect(name: "Beats Flex", classOfDevice: 0) == .beatsSolo)
        #expect(BluetoothAudioDeviceKind.detect(name: "JBL Speaker", classOfDevice: 0) == .speaker)
        #expect(BluetoothAudioDeviceKind.detect(name: "Galaxy Buds2", classOfDevice: 0) == .headphones)
    }

    @Test
    func productIDAndDeviceClassFallbacks() {
        #expect(BluetoothAudioDeviceKind.detect(name: "Living room", classOfDevice: 0, appleProductID: 0x2014) == .airpodsPro)
        #expect(BluetoothAudioDeviceKind.detect(name: "Living room", classOfDevice: 0, appleProductID: 0x9999) == .generic)
        // Audio/Video major class (0x04) with minor class 0x06 (headphones) and 0x0C (loudspeaker).
        #expect(BluetoothAudioDeviceKind.detect(name: "WH-1000XM5", classOfDevice: 0x04 << 8 | 0x06 << 2) == .headphones)
        #expect(BluetoothAudioDeviceKind.detect(name: "Soundbar", classOfDevice: 0x04 << 8 | 0x0C << 2) == .speaker)
        #expect(BluetoothAudioMonitor.isAudioVideoClass(0x24_0418))
        #expect(!BluetoothAudioMonitor.isAudioVideoClass(0x00_2540), "a keyboard is not audio")
    }

    @Test
    func everyKindResolvesToASymbolThisSystemHas() {
        for kind in BluetoothAudioDeviceKind.allCases {
            #expect(NSImage(systemSymbolName: kind.systemImage, accessibilityDescription: nil) != nil, "\(kind)")
        }
    }

    @Test
    func addressesCompareAcrossFormats() {
        #expect(BluetoothAudioDevice.normalizedAddress("AA:BB:CC:DD:EE:FF") == "aabbccddeeff")
        #expect(BluetoothAudioDevice.normalizedAddress("aa-bb-cc-dd-ee-ff") == "aabbccddeeff")
    }

    // MARK: Battery report

    @Test
    func parsesSystemProfilerBatteryLevels() throws {
        let json = """
        {
          "SPBluetoothDataType" : [
            {
              "controller_properties" : { "controller_state" : "attrib_on" },
              "device_connected" : [
                { "Mehdi's AirPods Pro" : {
                    "device_address" : "AA:BB:CC:DD:EE:FF",
                    "device_batteryLevelCase" : "40%",
                    "device_batteryLevelLeft" : "81%",
                    "device_batteryLevelRight" : "79%",
                    "device_minorType" : "Headphones"
                } },
                { "Magic Keyboard" : { "device_address" : "11:22:33:44:55:66" } },
                { "Speaker" : { "device_address" : "66:55:44:33:22:11", "device_batteryLevelMain" : "100%" } }
              ],
              "device_not_connected" : [
                { "Old Headset" : { "device_address" : "00:00:00:00:00:01", "device_batteryLevelMain" : "5%" } }
              ]
            }
          ]
        }
        """
        let report = BluetoothBatteryReader.parse(Data(json.utf8))
        #expect(report.level(address: "aa-bb-cc-dd-ee-ff", name: "whatever") == 81, "highest reading wins")
        #expect(report.level(address: "unknown", name: "Speaker") == 100)
        #expect(report.level(address: "11-22-33-44-55-66", name: "Magic Keyboard") == nil)
        #expect(report.level(address: "00-00-00-00-00-01", name: "Old Headset") == nil, "only connected devices")
        #expect(BluetoothBatteryReader.parse(Data("not json".utf8)) == BluetoothBatteryReport())
    }

    // MARK: Wing sizes

    @Test
    func wingWidthsMatchAtollsInlineHUD() {
        #expect(BluetoothHUDMetrics.infoWidth(showsName: false, gestureProgress: 0) == 64)
        #expect(BluetoothHUDMetrics.infoWidth(showsName: true, gestureProgress: 10) == 137)
        let trailing = { (battery: Bool, circular: Bool, percent: Bool, name: Bool) in
            BluetoothHUDMetrics.trailingWidth(
                showsBattery: battery, circular: circular, showsPercentage: percent, showsName: name, gestureProgress: 0
            )
        }
        #expect(trailing(false, true, false, false) == 80)
        #expect(trailing(false, true, false, true) == 110)
        #expect(trailing(true, true, false, false) == 76)
        #expect(trailing(true, true, true, false) == 112)
        #expect(trailing(true, false, false, false) == 100)
        #expect(trailing(true, false, true, false) == 128)
    }

    @Test
    func islandIsExactlyAsWideAsAtolls() {
        let settings = BluetoothSettings(defaults: makeDefaults())
        let controller = BluetoothHUDController(
            settings: settings,
            activityCenter: IslandActivityCenter(),
            batteryReader: { _ in nil }
        )
        let activity = BluetoothHUDActivity(controller: controller, settings: settings)
        controller.present(sampleDevice, batteryLevel: 80)
        #expect(activity.isActivityVisible)
        #expect(activity.priority == ClosedActivityPriority.inlineHUD)

        for hovering in [false, true] {
            let context = context(hovering: hovering)
            let hostWidth = activity.leftWingWidth(in: context) + context.centerWidth + activity.rightWingWidth(in: context)
            // Atoll: info + 8 + (notch - 20) + 8 + trailing, and the centre does not swell.
            let atollWidth: CGFloat = 64 + 8 + (185 - 20) + 8 + 76
            #expect(hostWidth == atollWidth, "hovering: \(hovering)")
            // The black centre starts where Atoll's does: after the info column and its gap.
            let atollCentreStart: CGFloat = 64 + 8
            #expect(activity.leftWingWidth(in: context) == atollCentreStart, "hovering: \(hovering)")
        }

        // Same on a narrow synthetic notch, where the host's centre is held at 96 pt.
        let narrow = context(notchWidth: 80)
        let narrowWidth = activity.leftWingWidth(in: narrow) + narrow.centerWidth + activity.rightWingWidth(in: narrow)
        let atollNarrowWidth: CGFloat = 64 + 8 + (80 - 20) + 8 + 76
        #expect(narrowWidth == atollNarrowWidth)
        controller.stop()
    }

    @Test
    func scrollingNameUsesAtollsInfoColumn() {
        let settings = BluetoothSettings(defaults: makeDefaults())
        settings.showDeviceNameMarquee = true
        let controller = BluetoothHUDController(
            settings: settings,
            activityCenter: IslandActivityCenter(),
            batteryReader: { _ in nil }
        )
        let activity = BluetoothHUDActivity(controller: controller, settings: settings)
        controller.present(sampleDevice, batteryLevel: nil)
        let context = context()
        #expect(activity.infoWidth(in: context) == 132)
        #expect(activity.leftWingWidth(in: context) == 140)
        // No battery with the name: Atoll's trailing column is 110 pt.
        let hostWidth = activity.leftWingWidth(in: context) + context.centerWidth + activity.rightWingWidth(in: context)
        let atollWidth: CGFloat = 132 + 8 + (185 - 20) + 8 + 110
        #expect(hostWidth == atollWidth)
        controller.stop()
    }

    // MARK: Controller

    @Test
    func controllerShowsInlineOrAsASneakPeek() {
        let settings = BluetoothSettings(defaults: makeDefaults())
        let center = IslandActivityCenter()
        let controller = BluetoothHUDController(settings: settings, activityCenter: center, batteryReader: { _ in nil })
        var peeks: [SneakPeek] = []
        let subscription = center.sneakPeekRequests.sink { peeks.append($0) }
        defer { subscription.cancel() }

        controller.present(sampleDevice, batteryLevel: nil)
        #expect(controller.presentation?.device == sampleDevice)
        #expect(controller.presentation?.showsBattery == false)
        #expect(controller.suppressesVolumeHUD)
        #expect(peeks.isEmpty)

        controller.dismiss()
        settings.useInlineHUD = false
        controller.present(sampleDevice, batteryLevel: 55)
        #expect(controller.presentation == nil)
        #expect(peeks.count == 1)
        #expect(peeks.first?.kind == .bluetooth)
        #expect(peeks.first?.subtitle == sampleDevice.name)
        #expect(peeks.first?.level == 0.55)
        #expect(peeks.first?.duration == .milliseconds(2_500))

        // Atoll's standard indicator always draws the battery bar; unknown reads as empty.
        controller.present(sampleDevice, batteryLevel: nil)
        #expect(peeks.count == 2)
        #expect(peeks.last?.level == 0)

        settings.showDeviceConnections = false
        controller.present(sampleDevice, batteryLevel: 55)
        #expect(peeks.count == 2, "switched off")
        controller.stop()
    }

    @Test
    func connectionWaitsForTheBatteryReading() async throws {
        let settings = BluetoothSettings(defaults: makeDefaults())
        let report = BluetoothBatteryReport(byAddress: ["aabbccddeeff": 64], byName: [:])
        let controller = BluetoothHUDController(
            settings: settings,
            activityCenter: IslandActivityCenter(),
            batteryReader: { _ in report }
        )
        controller.deviceDidConnect(sampleDevice)
        for _ in 0..<100 where controller.presentation == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.presentation?.batteryLevel == 64)
        controller.stop()
    }

    @Test
    func settingsUseAtollDefaults() {
        let defaults = makeDefaults()
        let settings = BluetoothSettings(defaults: defaults)
        #expect(settings.showDeviceConnections)
        #expect(settings.useInlineHUD)
        #expect(settings.useCircularBatteryIndicator)
        #expect(!settings.showBatteryPercentageText)
        #expect(!settings.showDeviceNameMarquee)
        #expect(settings.useColorCodedBatteryDisplay)
        #expect(settings.useSmoothColorGradient)
        settings.showDeviceNameMarquee = true
        #expect(BluetoothSettings(defaults: defaults).showDeviceNameMarquee)
    }

    @Test
    func batteryPaletteThresholds() {
        let green = Color(red: 0.2, green: 0.78, blue: 0.35)
        let yellow = Color(red: 0.93, green: 0.75, blue: 0.2)
        let red = Color(red: 0.95, green: 0.36, blue: 0.3)
        #expect(BluetoothBatteryPalette.color(forLevel: 0.9, smooth: false) == green)
        #expect(BluetoothBatteryPalette.color(forLevel: 0.3, smooth: false) == yellow)
        #expect(BluetoothBatteryPalette.color(forLevel: 0.1, smooth: false) == red)
        #expect(BluetoothBatteryPalette.color(forLevel: 0.5, smooth: true) == green)
        #expect(BluetoothBatteryPalette.color(forLevel: 0, smooth: true) == red)
    }
}
