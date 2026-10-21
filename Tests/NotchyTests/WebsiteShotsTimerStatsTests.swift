import Foundation
import SwiftUI
import Testing
@testable import Notchy

/// The website's Timer and Stats tabs: a Focus session partway through, and all five metric
/// cards over half a minute of an ordinary afternoon's work.
@MainActor
@Suite(.serialized)
struct WebsiteShotsTimerStatsTests {
    // MARK: Timer

    /// Focus (25:00) started 7 min 20 s ago: 17:40 left, the ring a little under a third full.
    @Test func timerTab() async throws {
        guard let output = WebsiteShots.output else { return }
        let timerSettings = TimerSettings(defaults: try WebsiteShots.defaults())
        timerSettings.soundEnabled = false
        timerSettings.notificationsEnabled = false
        let clock = ShotClock()
        let timer = TimerManager(
            settings: timerSettings,
            sound: SilentShotSound(),
            notifier: SilentShotNotifier(),
            clock: { clock.now }
        )
        timer.start(preset: timerSettings.preset(for: .focus))
        defer { timer.stop() }
        clock.advance(by: 7 * 60 + 20)
        timer.tick()
        #expect(timer.formattedRemainingTime == "17:40")
        #expect(abs(timer.progress - 440.0 / 1_500.0) < 0.0001)

        let island = try WebsiteIsland()
        island.open(.timer)
        try await island.renderOpen(
            to: output.appendingPathComponent("tab-timer.png"),
            content: { tab in
                guard tab == .timer else { return nil }
                return AnyView(NotchTimerTabView(model: island.model, manager: timer, settings: timerSettings).islandScaled())
            },
            beforeCapture: {
                // The countdown reads the hand-moved clock, so its tick loop never moves it on.
                #expect(timer.formattedRemainingTime == "17:40")
                #expect(timer.isRunning)
            }
        )
    }

    // MARK: Stats

    /// CPU, Memory, GPU, Network and Disk, each graph drawn from thirty one-second samples.
    @Test func statsTab() async throws {
        guard let output = WebsiteShots.output else { return }
        let stats = StatsManager.shared
        let settings = StatsSettings.shared

        // The tab asks the manager to start sampling when it appears. Record that request
        // first and cancel it, so the tab's identical request is ignored and no real reading
        // of this Mac is ever taken.
        stats.updateMonitoringState(notchIsOpen: true, statsTabSelected: true)
        stats.stopMonitoring()
        #expect(!stats.isMonitoring)

        // All five cards. The shared settings live in the test runner's own defaults; put
        // them back exactly as found.
        let saved = StatsGraphToggles(settings)
        defer { saved.restore(on: settings) }
        settings.showCpuGraph = true
        settings.showMemoryGraph = true
        settings.showGpuGraph = true
        settings.showNetworkGraph = true
        settings.showDiskGraph = true
        #expect(settings.enabledMetrics.count == 5)

        let samples = Self.sampleHistory()
        let countBefore = stats.sampleCount
        for sample in samples { stats.ingest(sample) }
        let expected = samples.reduce(into: StatsHistory()) { $0.record($1) }
        #expect(stats.history == expected)
        #expect(stats.cpuUsageString == "23.4%")
        #expect(stats.memoryUsageString == "61.0%")
        #expect(stats.gpuUsageString == "14.3%")
        #expect(stats.networkDownloadString == "864 KB/s")
        #expect(stats.networkUploadString == "420 KB/s")
        #expect(stats.diskReadString == "6.8 MB/s")
        #expect(stats.diskWriteString == "2.1 MB/s")

        let island = try WebsiteIsland()
        // The provider the app installs: a second row of cards makes the island taller.
        island.model.extraOpenHeightProvider = { tab in
            tab == .stats ? StatsLayout.extraOpenHeight(forCardCount: StatsSettings.shared.enabledMetrics.count) : 0
        }
        island.open(.stats)
        // The tab is built as the app builds it, on the manager prepared above. The settle
        // outlasts the manager's 0.5 s start delay, so a sampler that did start would show
        // up in the checks below.
        try await island.renderOpen(
            to: output.appendingPathComponent("tab-stats.png"),
            settle: .milliseconds(1_200),
            beforeCapture: {
                #expect(!stats.isMonitoring)
                #expect(stats.history == expected)
                #expect(stats.sampleCount == countBefore + samples.count)
            }
        )

        // Nothing but the made-up samples reached the cards, before or after the render.
        #expect(!stats.isMonitoring)
        #expect(stats.history == expected)
        #expect(stats.sampleCount == countBefore + samples.count)
        #expect(stats.lastUpdated == samples.last?.timestamp)
    }

    /// Thirty seconds of a 16 GB laptop doing light work: a browser, an editor and a build
    /// now and then. CPU sits around a quarter with one short build burst, memory just over
    /// 60 %, the GPU idles in the teens, two downloads spike the network, and the disk reads
    /// and writes in bursts.
    static func sampleHistory() -> [StatsSample] {
        let cpu: [Double] = [
            21.8, 24.6, 27.9, 26.1, 22.4, 19.7, 18.2, 20.9, 25.3, 29.8,
            31.6, 28.4, 24.9, 22.1, 20.6, 23.8, 27.2, 33.9, 34.6, 30.2,
            26.7, 23.5, 21.2, 19.4, 17.8, 20.3, 24.1, 26.8, 25.2, 23.4,
        ]
        let memory: [Double] = [
            57.6, 57.8, 57.7, 57.9, 58.1, 58.0, 58.2, 58.4, 58.3, 58.6,
            59.2, 59.9, 60.5, 60.8, 61.1, 61.3, 61.2, 61.0, 61.1, 60.9,
            60.8, 61.0, 61.2, 61.1, 61.0, 60.8, 60.9, 61.1, 61.0, 61.0,
        ]
        let gpu: [Double] = [
            9.8, 10.1, 9.6, 10.4, 10.2, 9.9, 10.6, 11.2, 10.8, 10.5,
            11.0, 12.6, 17.8, 24.1, 27.3, 25.9, 21.4, 16.2, 13.1, 12.0,
            11.6, 11.9, 12.4, 12.1, 12.8, 13.5, 13.2, 13.9, 14.1, 14.3,
        ]
        // The latest rates land in whole KB/s, which read the same in every locale; the disk
        // and percentage figures are always written with a point.
        let download: [Double] = [
            1.62, 1.85, 2.40, 2.04, 1.71, 2.36, 2.88, 3.42, 5.84, 4.96,
            3.17, 2.41, 2.05, 1.83, 2.26, 2.74, 3.11, 2.58, 2.12, 1.91,
            2.67, 6.26, 5.18, 3.74, 2.86, 2.31, 1.64, 1.12, 0.93, 864 / 1_024,
        ]
        let upload: [Double] = [
            0.31, 0.44, 0.61, 0.48, 0.32, 0.36, 0.55, 0.71, 0.92, 0.68,
            0.43, 0.39, 1.26, 2.64, 1.97, 0.82, 0.54, 0.40, 0.37, 0.45,
            0.51, 0.94, 0.78, 0.59, 0.43, 0.46, 0.48, 0.45, 0.43, 420 / 1_024,
        ]
        let diskRead: [Double] = [
            1.8, 2.4, 3.6, 2.9, 2.1, 13.6, 10.2, 4.8, 3.3, 2.6,
            2.2, 1.9, 2.5, 4.4, 3.7, 2.8, 2.3, 8.8, 11.6, 6.2,
            3.4, 2.7, 2.1, 1.9, 2.6, 3.8, 5.1, 6.3, 6.1, 6.8,
        ]
        let diskWrite: [Double] = [
            2.4, 3.1, 1.8, 1.2, 2.6, 3.8, 2.9, 1.7, 1.3, 2.2,
            3.5, 11.4, 7.8, 4.2, 2.1, 1.6, 1.9, 2.8, 3.3, 2.4,
            1.5, 1.2, 1.8, 2.6, 9.7, 6.4, 3.1, 2.2, 1.9, 2.1,
        ]

        let gigabyte: UInt64 = 1_073_741_824
        let totalMemory = 16 * gigabyte
        let now = Date()
        let count = cpu.count
        return (0 ..< count).map { index in
            func bytes(_ megabytesPerSecond: Double) -> UInt64 {
                UInt64((megabytesPerSecond * TransferRate.bytesPerMegabyte).rounded())
            }
            let busy = cpu[index]
            let used = UInt64((Double(totalMemory) * memory[index] / 100).rounded())
            let wired = UInt64(2.3 * Double(gigabyte))
            let compressed = UInt64(0.9 * Double(gigabyte))
            let cores = (0 ..< 10).map { core in
                min(100, max(2, busy * (core < 4 ? 1.6 : 0.6) + Double((core * 7 + index * 3) % 9) - 4))
            }
            return StatsSample(
                timestamp: now.addingTimeInterval(Double(index - (count - 1))),
                cpu: CPULoadBreakdown(user: busy * 0.68, system: busy * 0.32, idle: 100 - busy),
                coreUsage: cores,
                loadAverage: LoadAverage(oneMinute: 2.84, fiveMinutes: 2.61, fifteenMinutes: 2.37),
                uptime: 3 * 86_400 + 4 * 3_600 + 12 * 60 + Double(index),
                memory: MemorySnapshot(
                    total: totalMemory,
                    used: used,
                    free: totalMemory - used,
                    app: used - wired - compressed,
                    cache: UInt64(3.1 * Double(gigabyte)),
                    wired: wired,
                    compressed: compressed,
                    pressure: .normal,
                    swap: .zero
                ),
                gpuUsage: gpu[index],
                gpuDevices: [GPUDevice(id: "Apple M3 Pro#1", name: "Apple M3 Pro", utilization: gpu[index])],
                network: TransferRate(inboundMBps: download[index], outboundMBps: upload[index]),
                networkDelta: TransferDelta(inbound: bytes(download[index]), outbound: bytes(upload[index])),
                disk: TransferRate(inboundMBps: diskRead[index], outboundMBps: diskWrite[index]),
                diskDelta: TransferDelta(inbound: bytes(diskRead[index]), outbound: bytes(diskWrite[index])),
                rootVolume: VolumeUsage(total: 494_384_795_648, free: 236_812_451_840)
            )
        }
    }
}

// MARK: - Helpers

/// The five graph switches of the shared Stats settings as they were, with the stored values
/// behind them, so a shot can turn every card on and leave no trace.
@MainActor
private struct StatsGraphToggles {
    private static let keys = [
        StatsSettings.Key.showCpuGraph,
        StatsSettings.Key.showMemoryGraph,
        StatsSettings.Key.showGpuGraph,
        StatsSettings.Key.showNetworkGraph,
        StatsSettings.Key.showDiskGraph,
    ]

    private let values: [Bool]
    private let stored: [String: Any]

    init(_ settings: StatsSettings) {
        values = [
            settings.showCpuGraph, settings.showMemoryGraph, settings.showGpuGraph,
            settings.showNetworkGraph, settings.showDiskGraph,
        ]
        stored = Self.keys.reduce(into: [:]) { result, key in
            result[key] = UserDefaults.standard.object(forKey: key)
        }
    }

    func restore(on settings: StatsSettings) {
        settings.showCpuGraph = values[0]
        settings.showMemoryGraph = values[1]
        settings.showGpuGraph = values[2]
        settings.showNetworkGraph = values[3]
        settings.showDiskGraph = values[4]
        for key in Self.keys {
            if let value = stored[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}

/// A clock the shot moves by hand.
private final class ShotClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date()

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }
}

private final class SilentShotSound: TimerSoundPlaying {
    func play(named name: String, looping: Bool) {}
    func stop() {}
}

private final class SilentShotNotifier: TimerCompletionNotifying {
    func prepare() {}
    func notifyCompletion(name: String, duration: TimeInterval) {}
}
