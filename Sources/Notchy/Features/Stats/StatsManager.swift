import Combine
import Foundation

/// Owns sampling for the Stats tab: a `SystemStatsProbe` ticking at the configured interval
/// while the tab is on screen, the 30-sample histories behind the graphs, and the strings
/// the cards show. The lifecycle is "smart monitoring": sampling starts 0.5 s after the tab
/// appears, stops 0.1 s after switching to another tab, and 3 s after the island closes
/// (unless the user chose to keep it running). Histories survive a stop; per-tick state
/// such as core usage and GPU devices does not.
@MainActor
final class StatsManager: ObservableObject {
    static let shared = StatsManager()

    static let startDelay: Duration = .milliseconds(500)
    static let tabSwitchStopDelay: Duration = .milliseconds(100)
    static let notchCloseStopDelay: Duration = .seconds(3)

    @Published private(set) var isMonitoring = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var sampleCount = 0
    @Published private(set) var cpu: CPULoadBreakdown = .zero
    @Published private(set) var coreUsage: [Double] = []
    @Published private(set) var loadAverage: LoadAverage = .zero
    @Published private(set) var uptime: TimeInterval = 0
    @Published private(set) var memory: MemorySnapshot = .zero
    /// nil until an accelerator reports a utilisation figure.
    @Published private(set) var gpuUsage: Double?
    @Published private(set) var gpuDevices: [GPUDevice] = []
    @Published private(set) var network: TransferRate = .zero
    @Published private(set) var networkTotals: TransferTotals = .zero
    /// nil when no block-storage driver publishes byte counters.
    @Published private(set) var disk: TransferRate?
    @Published private(set) var diskTotals: TransferTotals = .zero
    @Published private(set) var rootVolume: VolumeUsage?
    @Published private(set) var history = StatsHistory()
    /// False once a tick found no block-storage counters; the disk card then shows dashes.
    @Published private(set) var diskThroughputAvailable = true

    let settings: StatsSettings
    private let probe: SystemStatsProbe
    private var samplingTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var lastNotchIsOpen = false
    private var lastStatsTabSelected = false

    init(settings: StatsSettings = .shared, probe: SystemStatsProbe = SystemStatsProbe()) {
        self.settings = settings
        self.probe = probe
        settings.$updateInterval
            .map(StatsSettings.clampedInterval)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.restartSamplingIfNeeded() }
            }
            .store(in: &cancellables)
        settings.$stopWhenNotchCloses
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] stopsWhenClosed in
                MainActor.assumeIsolated { self?.stopPolicyChanged(stopsWhenClosed) }
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    /// Call whenever the island's open state or the selected tab changes. Repeated calls with
    /// the same pair are ignored so they cannot restart a pending timer.
    func updateMonitoringState(notchIsOpen: Bool, statsTabSelected: Bool) {
        guard notchIsOpen != lastNotchIsOpen || statsTabSelected != lastStatsTabSelected else { return }
        lastNotchIsOpen = notchIsOpen
        lastStatsTabSelected = statsTabSelected
        startTask?.cancel()
        stopTask?.cancel()

        if notchIsOpen && statsTabSelected {
            scheduleStart(after: Self.startDelay)
        } else if notchIsOpen {
            scheduleStop(after: Self.tabSwitchStopDelay)
        } else if settings.stopWhenNotchCloses {
            scheduleStop(after: Self.notchCloseStopDelay)
        }
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        networkTotals = .zero
        diskTotals = .zero
        launchSamplingLoop(rebaseline: true, sampleImmediately: true)
    }

    func stopMonitoring() {
        startTask?.cancel()
        stopTask?.cancel()
        samplingTask?.cancel()
        samplingTask = nil
        guard isMonitoring else { return }
        isMonitoring = false
        coreUsage = []
        gpuDevices = []
        let probe = self.probe
        Task { await probe.reset() }
    }

    private func scheduleStart(after delay: Duration) {
        startTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.startMonitoring()
        }
    }

    private func scheduleStop(after delay: Duration) {
        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.stopMonitoring()
        }
    }

    /// Samples, applies, sleeps for the configured interval, repeats. A fresh start takes an
    /// immediate first sample like Atoll; an interval change just waits out the new interval.
    private func launchSamplingLoop(rebaseline: Bool, sampleImmediately: Bool) {
        samplingTask?.cancel()
        let probe = self.probe
        samplingTask = Task { @MainActor [weak self] in
            if rebaseline { await probe.prepareForMonitoring() }
            if !sampleImmediately {
                guard let interval = self?.settings.effectiveUpdateInterval else { return }
                try? await Task.sleep(for: .seconds(interval))
            }
            while !Task.isCancelled {
                let sample = await probe.sample()
                guard !Task.isCancelled, let self else { return }
                self.ingest(sample)
                let interval = self.settings.effectiveUpdateInterval
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func restartSamplingIfNeeded() {
        guard isMonitoring else { return }
        launchSamplingLoop(rebaseline: false, sampleImmediately: false)
    }

    /// Turning the close timeout on while the island is already closed schedules the 3 s
    /// stop; turning it off cancels one that is pending.
    private func stopPolicyChanged(_ stopsWhenClosed: Bool) {
        guard isMonitoring, !lastNotchIsOpen else { return }
        stopTask?.cancel()
        if stopsWhenClosed {
            scheduleStop(after: Self.notchCloseStopDelay)
        }
    }

    // MARK: - Samples

    /// Applies one tick to the published state. Internal so tests can feed synthetic samples.
    func ingest(_ sample: StatsSample) {
        cpu = sample.cpu
        if coreUsage != sample.coreUsage { coreUsage = sample.coreUsage }
        loadAverage = sample.loadAverage
        uptime = sample.uptime
        memory = sample.memory
        gpuUsage = sample.gpuUsage
        if gpuDevices != sample.gpuDevices { gpuDevices = sample.gpuDevices }
        network = sample.network
        networkTotals.add(sample.networkDelta)
        disk = sample.disk
        diskThroughputAvailable = sample.disk != nil
        diskTotals.add(sample.diskDelta)
        rootVolume = sample.rootVolume
        history.record(sample)
        lastUpdated = sample.timestamp
        sampleCount += 1
    }

    // MARK: - Strings for the cards

    var cpuUsageString: String { StatsFormatting.percentage(cpu.activeUsage) }
    var memoryUsageString: String { StatsFormatting.percentage(memory.usagePercent) }
    var gpuUsageString: String { gpuUsage.map(StatsFormatting.percentage) ?? "—" }
    var networkDownloadString: String { StatsFormatting.throughput(megabytesPerSecond: network.inboundMBps) }
    var networkUploadString: String { StatsFormatting.throughput(megabytesPerSecond: network.outboundMBps) }
    var diskReadString: String { disk.map { StatsFormatting.megabytesPerSecond($0.inboundMBps) } ?? "—" }
    var diskWriteString: String { disk.map { StatsFormatting.megabytesPerSecond($0.outboundMBps) } ?? "—" }

    /// The value line and graph data for one card.
    func cardContent(for metric: StatsMetric) -> StatsCardContent {
        switch metric {
        case .cpu:
            .single(value: cpuUsageString, history: history.cpu.values)
        case .memory:
            .single(value: memoryUsageString, history: history.memory.values)
        case .gpu:
            .single(value: gpuUsageString, history: history.gpu.values)
        case .network:
            .mirrored(
                upper: "↓" + networkDownloadString,
                lower: "↑" + networkUploadString,
                upperHistory: history.networkDownload.values,
                lowerHistory: history.networkUpload.values
            )
        case .disk:
            .mirrored(
                upper: "R " + diskReadString,
                lower: "W " + diskWriteString,
                upperHistory: history.diskRead.values,
                lowerHistory: history.diskWrite.values
            )
        }
    }
}
