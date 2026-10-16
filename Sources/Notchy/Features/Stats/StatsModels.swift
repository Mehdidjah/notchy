import Foundation
import SwiftUI

/// The five metrics a stats card can show, in display order.
enum StatsMetric: String, CaseIterable, Identifiable, Codable, Sendable {
    case cpu
    case memory
    case gpu
    case network
    case disk

    var id: Self { self }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .gpu: "GPU"
        case .network: "Network"
        case .disk: "Disk"
        }
    }

    var systemImage: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .gpu: "display"
        case .network: "network"
        case .disk: "internaldrive"
        }
    }

    /// The card's accent, and the colour of the upper series on a mirrored graph.
    var tint: Color {
        switch self {
        case .cpu: .blue
        case .memory: .green
        case .gpu: .purple
        case .network: .orange
        case .disk: .cyan
        }
    }

    /// The colour of the lower series (upload, write) on a mirrored graph.
    var secondaryTint: Color {
        switch self {
        case .network: .red
        case .disk: .yellow
        case .cpu, .memory, .gpu: tint
        }
    }

    /// Network and disk draw two series mirrored around a centre line.
    var isMirrored: Bool {
        switch self {
        case .network, .disk: true
        case .cpu, .memory, .gpu: false
        }
    }
}

/// A fixed-length sliding window of samples, zero-filled until real values arrive, so the
/// graphs always have a full set of points to draw.
struct MetricHistory: Equatable, Sendable {
    static let defaultLength = 30

    private(set) var values: [Double]

    init(length: Int = MetricHistory.defaultLength) {
        values = Array(repeating: 0, count: max(1, length))
    }

    var length: Int { values.count }
    var latest: Double { values.last ?? 0 }
    var maximum: Double { values.max() ?? 0 }

    /// Mean of the samples that carry a value, so a window that is still filling up is not
    /// dragged down by its zero padding.
    var averageOfNonZero: Double {
        let present = values.filter { $0 > 0 }
        guard !present.isEmpty else { return 0 }
        return present.reduce(0, +) / Double(present.count)
    }

    /// Drops the oldest sample and appends `value`, clamped at zero.
    mutating func push(_ value: Double) {
        values.removeFirst()
        values.append(value.isFinite ? max(0, value) : 0)
    }
}

// MARK: - CPU

/// Scheduler tick counters as `host_statistics` and `host_processor_info` report them.
struct CPUTicks: Equatable, Sendable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64

    var total: UInt64 { user &+ system &+ idle &+ nice }

    /// Ticks spent in each state since `previous`, or nil when a counter went backwards.
    func delta(since previous: CPUTicks) -> CPUTicks? {
        guard user >= previous.user, system >= previous.system,
              idle >= previous.idle, nice >= previous.nice else { return nil }
        return CPUTicks(
            user: user - previous.user,
            system: system - previous.system,
            idle: idle - previous.idle,
            nice: nice - previous.nice
        )
    }

    /// Usage over the span these ticks cover. Nice time counts as user time.
    var breakdown: CPULoadBreakdown? {
        let total = Double(self.total)
        guard total > 0 else { return nil }
        return CPULoadBreakdown(
            user: Double(user &+ nice) / total * 100,
            system: Double(system) / total * 100,
            idle: Double(idle) / total * 100
        )
    }

    /// Usage since `previous`, or the absolute split since boot for the very first reading.
    func breakdown(since previous: CPUTicks?) -> CPULoadBreakdown? {
        guard let previous else { return breakdown }
        return delta(since: previous)?.breakdown
    }

    /// Per-core busy percentages (user + system + nice over everything), measured against
    /// the previous reading while the core count still matches, absolute otherwise.
    static func coreUsage(current: [CPUTicks], previous: [CPUTicks]?) -> [Double] {
        current.enumerated().map { index, ticks in
            let span: CPUTicks?
            if let previous, previous.count == current.count {
                span = ticks.delta(since: previous[index])
            } else {
                span = ticks
            }
            guard let span, span.total > 0 else { return 0 }
            let busy = Double(span.user &+ span.system &+ span.nice)
            return min(100, max(0, busy / Double(span.total) * 100))
        }
    }
}

/// CPU time split into user, system and idle percentages.
struct CPULoadBreakdown: Equatable, Sendable {
    var user: Double
    var system: Double
    var idle: Double

    static let zero = CPULoadBreakdown(user: 0, system: 0, idle: 100)

    init(user: Double, system: Double, idle: Double) {
        self.user = min(100, max(0, user))
        self.system = min(100, max(0, system))
        self.idle = min(100, max(0, idle))
    }

    /// What the card shows: everything that is not idle.
    var activeUsage: Double { min(100, max(0, user + system)) }
}

struct LoadAverage: Equatable, Sendable {
    var oneMinute: Double
    var fiveMinutes: Double
    var fifteenMinutes: Double

    static let zero = LoadAverage(oneMinute: 0, fiveMinutes: 0, fifteenMinutes: 0)
}

// MARK: - Memory

enum MemoryPressureLevel: Int, Equatable, Sendable {
    case normal
    case warning
    case critical

    /// `kern.memorystatus_vm_pressure_level` reports 1 normal, 2 warning, 4 critical.
    init(sysctlLevel: Int32) {
        switch sysctlLevel {
        case 2: self = .warning
        case 4: self = .critical
        default: self = .normal
        }
    }

    var title: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }

    var detail: String {
        switch self {
        case .normal: "System memory pressure is nominal."
        case .warning: "Memory pressure is elevated. Closing apps may help."
        case .critical: "Memory pressure is critical; the system may purge aggressively."
        }
    }

    var tint: Color {
        switch self {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

struct SwapUsage: Equatable, Sendable {
    var total: UInt64
    var used: UInt64
    var free: UInt64

    static let zero = SwapUsage(total: 0, used: 0, free: 0)

    var isEnabled: Bool { total > 0 }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

/// Raw page counts from `vm_statistics64`.
struct VMPageCounts: Equatable, Sendable {
    var free: UInt64
    var active: UInt64
    var inactive: UInt64
    var speculative: UInt64
    var wired: UInt64
    var compressed: UInt64
    var purgeable: UInt64
    var external: UInt64
}

struct MemorySnapshot: Equatable, Sendable {
    var total: UInt64
    var used: UInt64
    var free: UInt64
    var app: UInt64
    var cache: UInt64
    var wired: UInt64
    var compressed: UInt64
    var pressure: MemoryPressureLevel
    var swap: SwapUsage

    static let zero = MemorySnapshot(
        total: 0, used: 0, free: 0, app: 0, cache: 0, wired: 0, compressed: 0,
        pressure: .normal, swap: .zero
    )

    var usagePercent: Double {
        guard total > 0 else { return 0 }
        return min(100, max(0, Double(used) / Double(total) * 100))
    }

    func percent(of bytes: UInt64) -> Double {
        guard total > 0 else { return 0 }
        return Double(bytes) / Double(total) * 100
    }

    /// Activity Monitor's arithmetic: used memory is everything resident (active, inactive,
    /// speculative, wired, compressed) minus the file cache (purgeable + external); app
    /// memory is what is left of that after wired and compressed pages.
    static func make(
        pages: VMPageCounts,
        pageSize: UInt64,
        total: UInt64,
        pressure: MemoryPressureLevel,
        swap: SwapUsage
    ) -> MemorySnapshot {
        let resident = (pages.active + pages.inactive + pages.speculative + pages.wired + pages.compressed) * pageSize
        let cache = (pages.purgeable + pages.external) * pageSize
        let wired = pages.wired * pageSize
        let compressed = pages.compressed * pageSize
        let totalBytes = total > 0 ? total : resident + pages.free * pageSize
        let used = min(resident > cache ? resident - cache : 0, totalBytes)
        let nonApp = wired + compressed
        return MemorySnapshot(
            total: totalBytes,
            used: used,
            free: totalBytes - used,
            app: used > nonApp ? used - nonApp : 0,
            cache: cache,
            wired: wired,
            compressed: compressed,
            pressure: pressure,
            swap: swap
        )
    }
}

// MARK: - GPU

struct GPUDevice: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let utilization: Double?
    let renderUtilization: Double?
    let tilerUtilization: Double?
    let isActive: Bool

    init(
        id: String,
        name: String,
        utilization: Double?,
        renderUtilization: Double? = nil,
        tilerUtilization: Double? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.utilization = utilization
        self.renderUtilization = renderUtilization
        self.tilerUtilization = tilerUtilization
        self.isActive = isActive
    }

    /// Builds a device from an `IOAccelerator` registry entry's properties; nil when the
    /// entry does not look like an accelerator. Utilisation comes from the entry's
    /// `PerformanceStatistics` dictionary and is clamped to 0...100.
    init?(registryProperties properties: [String: Any], index: Int) {
        guard let ioClass = properties["IOClass"] as? String else { return nil }
        let statistics = properties["PerformanceStatistics"] as? [String: Any] ?? [:]
        let vendor = Self.vendor(forClass: ioClass)
        let model = Self.text(statistics["model"])
            ?? Self.text(properties["model"])
            ?? vendor.map { "\($0) Graphics" }
            ?? "GPU"
        name = model
        id = "\(model)#\(index + 1)"
        utilization = Self.percent(statistics, keys: ["Device Utilization %", "GPU Activity(%)"])
        renderUtilization = Self.percent(statistics, keys: ["Renderer Utilization %"])
        tilerUtilization = Self.percent(statistics, keys: ["Tiler Utilization %"])
        if let agc = properties["AGCInfo"] as? [String: Any],
           let poweredOff = agc["poweredOffByAGC"] as? NSNumber {
            isActive = poweredOff.intValue == 0
        } else {
            isActive = true
        }
    }

    /// Mean utilisation across the devices that report one; nil when none does.
    static func averageUtilization(of devices: [GPUDevice]) -> Double? {
        let values = devices.compactMap(\.utilization)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func vendor(forClass ioClass: String) -> String? {
        let value = ioClass.lowercased()
        if value.contains("nvidia") { return "NVIDIA" }
        if value.contains("amd") { return "AMD" }
        if value.contains("intel") { return "Intel" }
        if value.contains("agx") || value.contains("apple") { return "Apple" }
        return nil
    }

    /// Registry strings arrive as String or as NUL-terminated Data.
    private static func text(_ value: Any?) -> String? {
        let raw: String?
        if let string = value as? String {
            raw = string
        } else if let data = value as? Data {
            raw = String(decoding: data, as: UTF8.self)
        } else {
            raw = nil
        }
        guard let cleaned = raw?
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !cleaned.isEmpty else { return nil }
        return cleaned
    }

    private static func percent(_ dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let number = dictionary[key] as? NSNumber {
                return min(100, max(0, number.doubleValue))
            }
        }
        return nil
    }
}

// MARK: - Storage and transfer

struct VolumeUsage: Equatable, Sendable {
    var total: UInt64
    var free: UInt64

    var used: UInt64 { total > free ? total - free : 0 }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    var usagePercent: Double { fraction * 100 }
}

/// Interface byte counters as `if_data` reports them: 32-bit and free to wrap.
struct LinkCounters: Equatable, Sendable {
    var inbound: UInt32
    var outbound: UInt32
}

/// Bytes moved in one sampling span. Inbound is download or read, outbound upload or write.
struct TransferDelta: Equatable, Sendable {
    var inbound: UInt64
    var outbound: UInt64

    static let zero = TransferDelta(inbound: 0, outbound: 0)
}

enum TransferMath {
    /// Sums wrap-aware per-interface deltas. An interface without a previous reading (just
    /// plugged in) contributes nothing until the next tick.
    static func delta(from previous: [String: LinkCounters], to current: [String: LinkCounters]) -> TransferDelta {
        var delta = TransferDelta.zero
        for (name, counters) in current {
            guard let before = previous[name] else { continue }
            delta.inbound += UInt64(counters.inbound &- before.inbound)
            delta.outbound += UInt64(counters.outbound &- before.outbound)
        }
        return delta
    }

    /// Growth of a monotonic 64-bit counter; one that went backwards (a drive was ejected)
    /// contributes nothing.
    static func delta(from previous: UInt64, to current: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    static func delta(from previous: TransferDelta, to current: TransferDelta) -> TransferDelta {
        TransferDelta(
            inbound: delta(from: previous.inbound, to: current.inbound),
            outbound: delta(from: previous.outbound, to: current.outbound)
        )
    }
}

/// Throughput in MB/s for both directions of a transfer.
struct TransferRate: Equatable, Sendable {
    /// Spans shorter than this are too noisy to divide by and report no rate.
    static let minimumElapsed: TimeInterval = 0.1
    static let bytesPerMegabyte: Double = 1_048_576
    static let zero = TransferRate(inboundMBps: 0, outboundMBps: 0)

    var inboundMBps: Double
    var outboundMBps: Double

    init(inboundMBps: Double, outboundMBps: Double) {
        self.inboundMBps = inboundMBps
        self.outboundMBps = outboundMBps
    }

    init(delta: TransferDelta, elapsed: TimeInterval) {
        guard elapsed > Self.minimumElapsed else {
            self = .zero
            return
        }
        inboundMBps = Double(delta.inbound) / elapsed / Self.bytesPerMegabyte
        outboundMBps = Double(delta.outbound) / elapsed / Self.bytesPerMegabyte
    }
}

/// Megabytes moved since monitoring started.
struct TransferTotals: Equatable, Sendable {
    var inboundMB: Double = 0
    var outboundMB: Double = 0

    static let zero = TransferTotals()

    mutating func add(_ delta: TransferDelta) {
        inboundMB += Double(delta.inbound) / TransferRate.bytesPerMegabyte
        outboundMB += Double(delta.outbound) / TransferRate.bytesPerMegabyte
    }
}

// MARK: - Sample and history

/// Everything one sampling tick learned, produced off the main actor and applied on it.
struct StatsSample: Equatable, Sendable {
    var timestamp: Date
    var cpu: CPULoadBreakdown
    var coreUsage: [Double]
    var loadAverage: LoadAverage
    var uptime: TimeInterval
    var memory: MemorySnapshot
    var gpuUsage: Double?
    var gpuDevices: [GPUDevice]
    var network: TransferRate
    var networkDelta: TransferDelta
    /// nil when no block-storage driver publishes byte counters.
    var disk: TransferRate?
    var diskDelta: TransferDelta
    var rootVolume: VolumeUsage?
}

/// The seven sliding windows behind the graphs.
struct StatsHistory: Equatable, Sendable {
    var cpu: MetricHistory
    var memory: MetricHistory
    var gpu: MetricHistory
    var networkDownload: MetricHistory
    var networkUpload: MetricHistory
    var diskRead: MetricHistory
    var diskWrite: MetricHistory

    init(length: Int = MetricHistory.defaultLength) {
        cpu = MetricHistory(length: length)
        memory = MetricHistory(length: length)
        gpu = MetricHistory(length: length)
        networkDownload = MetricHistory(length: length)
        networkUpload = MetricHistory(length: length)
        diskRead = MetricHistory(length: length)
        diskWrite = MetricHistory(length: length)
    }

    mutating func record(_ sample: StatsSample) {
        cpu.push(sample.cpu.activeUsage)
        memory.push(sample.memory.usagePercent)
        gpu.push(sample.gpuUsage ?? 0)
        networkDownload.push(sample.network.inboundMBps)
        networkUpload.push(sample.network.outboundMBps)
        diskRead.push(sample.disk?.inboundMBps ?? 0)
        diskWrite.push(sample.disk?.outboundMBps ?? 0)
    }
}
