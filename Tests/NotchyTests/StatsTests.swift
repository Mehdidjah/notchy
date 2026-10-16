import CoreGraphics
import Foundation
import Testing
@testable import Notchy

// MARK: - History ring buffer

struct StatsHistoryTests {
    @Test
    func historyStartsZeroFilledAndSlides() {
        var history = MetricHistory(length: 3)
        #expect(history.values == [0, 0, 0])

        history.push(10)
        history.push(20)
        history.push(30)
        history.push(40)

        #expect(history.values == [20, 30, 40])
        #expect(history.length == 3)
        #expect(history.latest == 40)
        #expect(history.maximum == 40)
    }

    @Test
    func historyAverageIgnoresZeroPadding() {
        var history = MetricHistory(length: 4)
        history.push(10)
        history.push(30)

        #expect(history.averageOfNonZero == 20)
        #expect(MetricHistory(length: 4).averageOfNonZero == 0)
    }

    @Test
    func historyClampsNegativeAndNonFiniteValues() {
        var history = MetricHistory(length: 2)
        history.push(-5)
        history.push(.nan)
        #expect(history.values == [0, 0])
    }

    @Test
    func defaultWindowIsThirtySamples() {
        #expect(MetricHistory().length == 30)
        let history = StatsHistory()
        #expect(history.cpu.length == 30)
        #expect(history.diskWrite.length == 30)
    }

    @Test
    func recordingASampleFeedsEveryWindow() {
        var history = StatsHistory(length: 2)
        history.record(makeSample(cpuUser: 20, cpuSystem: 10, gpu: nil, disk: nil))
        #expect(history.cpu.latest == 30)
        #expect(history.gpu.latest == 0)
        #expect(history.diskRead.latest == 0)
        #expect(history.networkDownload.latest == 2.5)
    }
}

// MARK: - Rate computation

struct StatsRateTests {
    @Test
    func cpuBreakdownUsesTickDeltas() throws {
        let before = CPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        let after = CPUTicks(user: 200, system: 100, idle: 1_600, nice: 100)

        let breakdown = try #require(after.breakdown(since: before))
        #expect(breakdown.user == 15)
        #expect(breakdown.system == 5)
        #expect(breakdown.idle == 80)
        #expect(breakdown.activeUsage == 20)
    }

    @Test
    func firstCPUReadingIsAbsolute() throws {
        let ticks = CPUTicks(user: 25, system: 25, idle: 50, nice: 0)
        let breakdown = try #require(ticks.breakdown(since: nil))
        #expect(breakdown.user == 25)
        #expect(breakdown.system == 25)
        #expect(breakdown.idle == 50)
    }

    @Test
    func backwardsCountersYieldNoBreakdown() {
        let before = CPUTicks(user: 500, system: 50, idle: 800, nice: 50)
        let after = CPUTicks(user: 400, system: 100, idle: 1_600, nice: 100)
        #expect(after.breakdown(since: before) == nil)
        #expect(CPUTicks(user: 0, system: 0, idle: 0, nice: 0).breakdown == nil)
    }

    @Test
    func coreUsageMeasuresAgainstPreviousTicksWhenCountsMatch() {
        let previous = [CPUTicks(user: 0, system: 0, idle: 100, nice: 0), CPUTicks(user: 0, system: 0, idle: 100, nice: 0)]
        let current = [CPUTicks(user: 50, system: 0, idle: 150, nice: 0), CPUTicks(user: 0, system: 25, idle: 175, nice: 0)]

        #expect(CPUTicks.coreUsage(current: current, previous: previous) == [50, 25])
        // A changed core count falls back to the absolute reading.
        #expect(CPUTicks.coreUsage(current: current, previous: [previous[0]]) == [25, 12.5])
        #expect(CPUTicks.coreUsage(current: current, previous: nil) == [25, 12.5])
    }

    @Test
    func linkDeltaHandlesWrapAroundAndNewInterfaces() {
        let before = ["en0": LinkCounters(inbound: UInt32.max - 10, outbound: 100)]
        let after = [
            "en0": LinkCounters(inbound: 20, outbound: 150),
            "en5": LinkCounters(inbound: 999, outbound: 999)
        ]

        let delta = TransferMath.delta(from: before, to: after)
        #expect(delta.inbound == 31)
        #expect(delta.outbound == 50)
    }

    @Test
    func monotonicCounterGoingBackwardsCountsNothing() {
        #expect(TransferMath.delta(from: 400, to: 500) == 100)
        #expect(TransferMath.delta(from: 500, to: 400) == 0)
        let delta = TransferMath.delta(
            from: TransferDelta(inbound: 10, outbound: 50),
            to: TransferDelta(inbound: 30, outbound: 40)
        )
        #expect(delta == TransferDelta(inbound: 20, outbound: 0))
    }

    @Test
    func rateDividesBytesByElapsedSecondsAndMegabytes() {
        let delta = TransferDelta(inbound: 2_097_152, outbound: 1_048_576)
        let rate = TransferRate(delta: delta, elapsed: 2)
        #expect(rate.inboundMBps == 1)
        #expect(rate.outboundMBps == 0.5)
    }

    @Test
    func rateNeedsAMeasurableSpan() {
        let delta = TransferDelta(inbound: 2_097_152, outbound: 1_048_576)
        #expect(TransferRate(delta: delta, elapsed: 0.05) == .zero)
        #expect(TransferRate(delta: delta, elapsed: 0) == .zero)
    }

    @Test
    func totalsAccumulateMegabytes() {
        var totals = TransferTotals.zero
        totals.add(TransferDelta(inbound: 1_048_576, outbound: 524_288))
        totals.add(TransferDelta(inbound: 1_048_576, outbound: 524_288))
        #expect(totals.inboundMB == 2)
        #expect(totals.outboundMB == 1)
    }

    @Test
    func virtualInterfacesAreNotCounted() {
        #expect(SystemStatsProbe.isCountedInterface("en0"))
        #expect(SystemStatsProbe.isCountedInterface("en5"))
        #expect(SystemStatsProbe.isCountedInterface("anpi0"))
        #expect(!SystemStatsProbe.isCountedInterface("lo0"))
        #expect(!SystemStatsProbe.isCountedInterface("utun3"))
        #expect(!SystemStatsProbe.isCountedInterface("awdl0"))
        #expect(!SystemStatsProbe.isCountedInterface("bridge0"))
        #expect(!SystemStatsProbe.isCountedInterface("vmnet8"))
    }
}

// MARK: - Memory and GPU parsing

struct StatsSnapshotTests {
    @Test
    func usedMemoryExcludesFileCache() {
        let pages = VMPageCounts(
            free: 100, active: 300, inactive: 200, speculative: 50,
            wired: 150, compressed: 100, purgeable: 30, external: 70
        )
        let snapshot = MemorySnapshot.make(
            pages: pages,
            pageSize: 1_000,
            total: 1_000_000,
            pressure: .warning,
            swap: SwapUsage(total: 10, used: 4, free: 6)
        )

        #expect(snapshot.used == 700_000)
        #expect(snapshot.free == 300_000)
        #expect(snapshot.app == 450_000)
        #expect(snapshot.cache == 100_000)
        #expect(snapshot.wired == 150_000)
        #expect(snapshot.compressed == 100_000)
        #expect(snapshot.usagePercent == 70)
        #expect(snapshot.percent(of: snapshot.wired) == 15)
        #expect(snapshot.pressure == .warning)
        #expect(snapshot.swap.isEnabled)
        #expect(snapshot.swap.fraction == 0.4)
    }

    @Test
    func pressureLevelsMapFromSysctl() {
        #expect(MemoryPressureLevel(sysctlLevel: 1) == .normal)
        #expect(MemoryPressureLevel(sysctlLevel: 2) == .warning)
        #expect(MemoryPressureLevel(sysctlLevel: 4) == .critical)
        #expect(MemoryPressureLevel(sysctlLevel: 0) == .normal)
    }

    @Test
    func gpuDeviceParsesRegistryProperties() throws {
        let properties: [String: Any] = [
            "IOClass": "AGXAcceleratorG13G",
            "model": Data("Apple M1\0".utf8),
            "PerformanceStatistics": [
                "Device Utilization %": 37,
                "Renderer Utilization %": 12.5
            ] as [String: Any],
            "AGCInfo": ["poweredOffByAGC": 0] as [String: Any]
        ]

        let device = try #require(GPUDevice(registryProperties: properties, index: 0))
        #expect(device.name == "Apple M1")
        #expect(device.id == "Apple M1#1")
        #expect(device.utilization == 37)
        #expect(device.renderUtilization == 12.5)
        #expect(device.tilerUtilization == nil)
        #expect(device.isActive)
    }

    @Test
    func gpuDeviceFallsBackToVendorNameAndClampsPercentages() throws {
        let device = try #require(GPUDevice(
            registryProperties: ["IOClass": "IntelAccelerator", "PerformanceStatistics": ["GPU Activity(%)": 140] as [String: Any]],
            index: 2
        ))
        #expect(device.name == "Intel Graphics")
        #expect(device.id == "Intel Graphics#3")
        #expect(device.utilization == 100)
        #expect(GPUDevice(registryProperties: ["model": "no class"], index: 0) == nil)
    }

    @Test
    func gpuAverageSkipsDevicesWithoutUtilization() {
        let devices = [
            GPUDevice(id: "a", name: "A", utilization: 40),
            GPUDevice(id: "b", name: "B", utilization: nil),
            GPUDevice(id: "c", name: "C", utilization: 20)
        ]
        #expect(GPUDevice.averageUtilization(of: devices) == 30)
        #expect(GPUDevice.averageUtilization(of: [GPUDevice(id: "b", name: "B", utilization: nil)]) == nil)
        #expect(GPUDevice.averageUtilization(of: []) == nil)
    }

    @Test
    func volumeUsageDerivesUsedFromTotalAndFree() {
        let volume = VolumeUsage(total: 1_000, free: 250)
        #expect(volume.used == 750)
        #expect(volume.fraction == 0.75)
        #expect(VolumeUsage(total: 0, free: 0).fraction == 0)
    }
}

// MARK: - Formatting

struct StatsFormattingTests {
    private let locale = Locale(identifier: "en_US")

    @Test
    func throughputPicksTheLargestUnitAtLeastOne() {
        #expect(StatsFormatting.throughput(megabytesPerSecond: 12.345, locale: locale) == "12.3 MB/s")
        #expect(StatsFormatting.throughput(megabytesPerSecond: 1.5, locale: locale) == "1.5 MB/s")
        #expect(StatsFormatting.throughput(megabytesPerSecond: 1.234, locale: locale) == "1.23 MB/s")
        #expect(StatsFormatting.throughput(megabytesPerSecond: 0.5, locale: locale) == "512 KB/s")
        #expect(StatsFormatting.throughput(megabytesPerSecond: 0.005, locale: locale) == "5.1 KB/s")
        #expect(StatsFormatting.throughput(megabytesPerSecond: 0.0001, locale: locale) == "105 B/s")
        #expect(StatsFormatting.throughput(megabytesPerSecond: 0, locale: locale) == "0 B/s")
    }

    @Test
    func percentagesAndDiskRatesUseOneFractionDigit() {
        #expect(StatsFormatting.percentage(42.26) == "42.3%")
        #expect(StatsFormatting.percentage(0) == "0.0%")
        #expect(StatsFormatting.megabytesPerSecond(0.26) == "0.3 MB/s")
        #expect(StatsFormatting.loadAverage(1.234) == "1.23")
    }

    @Test
    func sessionMegabytesMatchByteFormatting() {
        #expect(StatsFormatting.megabytes(1_024) == StatsFormatting.bytes(1_073_741_824))
        #expect(StatsFormatting.megabytes(0) == StatsFormatting.bytes(0))
    }

    @Test
    func intervalLabelsCapAtOneMinute() {
        #expect(StatsSettingsSection.intervalLabel(1) == "1 s")
        #expect(StatsSettingsSection.intervalLabel(5.4) == "5 s")
        #expect(StatsSettingsSection.intervalLabel(60) == "60 s (1 min)")
    }
}

// MARK: - Layout

struct StatsLayoutTests {
    @Test
    func rowsSplitThreeFourAndFiveCardsLikeAtoll() {
        #expect(StatsLayout.rows(for: [1, 2, 3]) == [[1, 2, 3]])
        #expect(StatsLayout.rows(for: [1, 2, 3, 4]) == [[1, 2], [3, 4]])
        #expect(StatsLayout.rows(for: [1, 2, 3, 4, 5]) == [[1, 2, 3], [4, 5]])
        #expect(StatsLayout.rows(for: [Int]()).isEmpty)
        #expect(StatsLayout.rowCount(forCardCount: 0) == 0)
        #expect(StatsLayout.rowCount(forCardCount: 3) == 1)
        #expect(StatsLayout.rowCount(forCardCount: 4) == 2)
    }

    @Test
    func secondRowAddsExactly132Points() {
        #expect(StatsLayout.extraOpenHeight(forCardCount: 3) == 0)
        #expect(StatsLayout.extraOpenHeight(forCardCount: 4) == 132)
        #expect(StatsLayout.openHeight(forCardCount: 2) == 200)
        #expect(StatsLayout.openHeight(forCardCount: 5) == 332)
    }

    @Test
    func cardSizingKeepsTheFullGraphWhenThereIsRoom() {
        #expect(StatsCardSizing(contentHeight: 168, rowCount: 1) == .full)
        #expect(StatsCardSizing(contentHeight: 300, rowCount: 2) == .full)
        #expect(StatsCardSizing(contentHeight: 0, rowCount: 2) == .full)
    }

    @Test
    func cardSizingDropsTheHintThenShrinksTheGraph() {
        // Two rows in the one-row box: (168 - 24 - 12) / 2 = 66 pt per card.
        let squeezed = StatsCardSizing(contentHeight: 168, rowCount: 2)
        #expect(!squeezed.showsHint)
        #expect(squeezed.graphHeight == 13)

        let crushed = StatsCardSizing(contentHeight: 80, rowCount: 2)
        #expect(crushed.graphHeight == StatsCardSizing.minimumGraphHeight)
    }
}

// MARK: - Graph geometry

struct StatsGraphGeometryTests {
    @Test
    func normalizationScalesToTheWindowMaximum() {
        #expect(StatsGraphGeometry.normalized([0, 5, 10]) == [0, 0.5, 1])
        #expect(StatsGraphGeometry.normalized([0, 0]) == [0, 0])
        #expect(StatsGraphGeometry.normalized([5], maximum: 20) == [0.25])
        #expect(StatsGraphGeometry.normalized([5], maximum: 0) == [0])
    }

    @Test
    func pointsSpanTheWidthAndMirrorAroundTheBaseline() {
        let upper = StatsGraphGeometry.points(for: [0, 1], width: 100, baseline: 36, amplitude: 36)
        #expect(upper == [CGPoint(x: 0, y: 36), CGPoint(x: 100, y: 0)])

        let lower = StatsGraphGeometry.points(for: [0, 1], width: 100, baseline: 18, amplitude: -18)
        #expect(lower == [CGPoint(x: 0, y: 18), CGPoint(x: 100, y: 36)])

        #expect(StatsGraphGeometry.points(for: [], width: 100, baseline: 0, amplitude: 1).isEmpty)
        #expect(StatsGraphGeometry.points(for: [1], width: 100, baseline: 10, amplitude: 10) == [CGPoint(x: 0, y: 0)])
    }
}

// MARK: - Settings

@MainActor
struct StatsSettingsTests {
    @Test
    func defaultsMatchAtoll() {
        let (settings, _) = makeSettings()
        #expect(settings.showCpuGraph)
        #expect(settings.showMemoryGraph)
        #expect(settings.showGpuGraph)
        #expect(!settings.showNetworkGraph)
        #expect(!settings.showDiskGraph)
        #expect(settings.updateInterval == 1)
        #expect(settings.stopWhenNotchCloses)
        #expect(settings.enabledMetrics == [.cpu, .memory, .gpu])
    }

    @Test
    func intervalIsClampedOnReadAndWrite() {
        let (settings, defaults) = makeSettings(seed: { $0.set(0.2, forKey: "stats.updateInterval") })
        #expect(settings.updateInterval == 1)

        settings.updateInterval = 500
        #expect(settings.effectiveUpdateInterval == 60)
        #expect(defaults.double(forKey: "stats.updateInterval") == 60)
    }

    @Test
    func graphTogglesPersistAndKeepDisplayOrder() {
        let (settings, defaults) = makeSettings()
        settings.showDiskGraph = true
        settings.showCpuGraph = false

        #expect(defaults.bool(forKey: "stats.showDiskGraph"))
        #expect(defaults.object(forKey: "stats.showCpuGraph") as? Bool == false)
        #expect(settings.enabledMetrics == [.memory, .gpu, .disk])
        #expect(StatsSettings(defaults: defaults).enabledMetrics == [.memory, .gpu, .disk])
    }

    @Test
    func batteryWarningNeedsNoTimeoutAndAFastInterval() {
        let (settings, _) = makeSettings()
        settings.stopWhenNotchCloses = false
        settings.updateInterval = 5
        #expect(settings.showsBatteryWarning)
        settings.updateInterval = 6
        #expect(!settings.showsBatteryWarning)
        settings.stopWhenNotchCloses = true
        settings.updateInterval = 1
        #expect(!settings.showsBatteryWarning)
    }
}

// MARK: - Manager

@MainActor
struct StatsManagerTests {
    @Test
    func ingestingASampleUpdatesHistoryTotalsAndStrings() throws {
        let (settings, _) = makeSettings()
        let manager = StatsManager(settings: settings)

        manager.ingest(makeSample(cpuUser: 20, cpuSystem: 10, gpu: nil, disk: nil))

        #expect(manager.cpuUsageString == "30.0%")
        #expect(manager.history.cpu.latest == 30)
        #expect(manager.gpuUsageString == "—")
        #expect(manager.diskReadString == "—")
        #expect(!manager.diskThroughputAvailable)
        #expect(manager.history.networkDownload.latest == 2.5)
        #expect(manager.networkTotals.inboundMB == 2.5)
        #expect(manager.networkTotals.outboundMB == 0.25)
        #expect(manager.sampleCount == 1)

        guard case .mirrored(let upper, let lower, let upperHistory, _) = manager.cardContent(for: .network) else {
            Issue.record("Network card should be mirrored")
            return
        }
        #expect(upper.hasPrefix("↓"))
        #expect(lower.hasPrefix("↑"))
        #expect(upperHistory.count == 30)

        guard case .single(let value, _) = manager.cardContent(for: .cpu) else {
            Issue.record("CPU card should be single")
            return
        }
        #expect(value == "30.0%")
    }

    @Test
    func diskStringsAppearOnceCountersExist() {
        let (settings, _) = makeSettings()
        let manager = StatsManager(settings: settings)

        manager.ingest(makeSample(cpuUser: 0, cpuSystem: 0, gpu: 55, disk: TransferRate(inboundMBps: 0.26, outboundMBps: 3)))

        #expect(manager.diskThroughputAvailable)
        #expect(manager.diskReadString == "0.3 MB/s")
        #expect(manager.diskWriteString == "3.0 MB/s")
        #expect(manager.gpuUsageString == "55.0%")
        #expect(manager.history.diskWrite.latest == 3)
    }

    @Test
    func monitoringStartsAfterTheDelayAndStopsOnTabSwitch() async throws {
        let (settings, _) = makeSettings()
        let manager = StatsManager(settings: settings)

        manager.updateMonitoringState(notchIsOpen: true, statsTabSelected: true)
        #expect(!manager.isMonitoring)

        try await Task.sleep(for: .milliseconds(900))
        #expect(manager.isMonitoring)
        #expect(manager.sampleCount >= 1)

        manager.updateMonitoringState(notchIsOpen: true, statsTabSelected: false)
        #expect(manager.isMonitoring)
        try await Task.sleep(for: .milliseconds(400))
        #expect(!manager.isMonitoring)
        #expect(manager.coreUsage.isEmpty)
        // Histories survive a stop.
        #expect(manager.history.cpu.length == 30)
    }

    @Test
    func closingTheNotchKeepsSamplingWhenTheTimeoutIsOff() async throws {
        let (settings, _) = makeSettings()
        settings.stopWhenNotchCloses = false
        let manager = StatsManager(settings: settings)

        manager.startMonitoring()
        manager.updateMonitoringState(notchIsOpen: true, statsTabSelected: true)
        manager.updateMonitoringState(notchIsOpen: false, statsTabSelected: false)
        try await Task.sleep(for: .milliseconds(200))
        #expect(manager.isMonitoring)

        // Switching the timeout on while closed schedules the 3 s stop; off again cancels it.
        settings.stopWhenNotchCloses = true
        settings.stopWhenNotchCloses = false
        try await Task.sleep(for: .milliseconds(100))
        #expect(manager.isMonitoring)

        manager.stopMonitoring()
        #expect(!manager.isMonitoring)
    }

    @Test
    func repeatedStateReportsDoNotRestartPendingTimers() async throws {
        let (settings, _) = makeSettings()
        let manager = StatsManager(settings: settings)

        manager.updateMonitoringState(notchIsOpen: true, statsTabSelected: true)
        try await Task.sleep(for: .milliseconds(350))
        manager.updateMonitoringState(notchIsOpen: true, statsTabSelected: true)
        try await Task.sleep(for: .milliseconds(350))
        // 700 ms after the first report the 500 ms start has fired even though a second,
        // identical report arrived at 350 ms.
        #expect(manager.isMonitoring)
        manager.stopMonitoring()
    }
}

// MARK: - Helpers

@MainActor
private func makeSettings(seed: (UserDefaults) -> Void = { _ in }) -> (StatsSettings, UserDefaults) {
    let suiteName = "StatsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    seed(defaults)
    return (StatsSettings(defaults: defaults), defaults)
}

private func makeSample(cpuUser: Double, cpuSystem: Double, gpu: Double?, disk: TransferRate?) -> StatsSample {
    StatsSample(
        timestamp: Date(timeIntervalSinceReferenceDate: 1_000),
        cpu: CPULoadBreakdown(user: cpuUser, system: cpuSystem, idle: 100 - cpuUser - cpuSystem),
        coreUsage: [10, 50],
        loadAverage: LoadAverage(oneMinute: 1, fiveMinutes: 2, fifteenMinutes: 3),
        uptime: 3_600,
        memory: MemorySnapshot.make(
            pages: VMPageCounts(free: 100, active: 300, inactive: 200, speculative: 50, wired: 150, compressed: 100, purgeable: 30, external: 70),
            pageSize: 1_000,
            total: 1_000_000,
            pressure: .normal,
            swap: .zero
        ),
        gpuUsage: gpu,
        gpuDevices: [],
        network: TransferRate(inboundMBps: 2.5, outboundMBps: 0.25),
        networkDelta: TransferDelta(inbound: 2_621_440, outbound: 262_144),
        disk: disk,
        diskDelta: .zero,
        rootVolume: VolumeUsage(total: 1_000, free: 400)
    )
}
