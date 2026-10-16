import Combine
import Foundation
import SwiftUI

/// Which graphs the Stats tab shows and how it samples. Backed by UserDefaults under
/// "stats." keys and shared by the tab, the manager and the Settings window.
@MainActor
final class StatsSettings: ObservableObject {
    static let shared = StatsSettings()

    enum Key {
        static let showCpuGraph = "stats.showCpuGraph"
        static let showMemoryGraph = "stats.showMemoryGraph"
        static let showGpuGraph = "stats.showGpuGraph"
        static let showNetworkGraph = "stats.showNetworkGraph"
        static let showDiskGraph = "stats.showDiskGraph"
        static let updateInterval = "stats.updateInterval"
        static let stopWhenNotchCloses = "stats.stopWhenNotchCloses"
    }

    static let minimumUpdateInterval: Double = 1
    static let maximumUpdateInterval: Double = 60
    static let defaultUpdateInterval: Double = 1
    /// At or below this interval, sampling that never stops is flagged as a battery cost.
    static let batteryWarningInterval: Double = 5

    private let defaults: UserDefaults

    @Published var showCpuGraph: Bool { didSet { defaults.set(showCpuGraph, forKey: Key.showCpuGraph) } }
    @Published var showMemoryGraph: Bool { didSet { defaults.set(showMemoryGraph, forKey: Key.showMemoryGraph) } }
    @Published var showGpuGraph: Bool { didSet { defaults.set(showGpuGraph, forKey: Key.showGpuGraph) } }
    @Published var showNetworkGraph: Bool { didSet { defaults.set(showNetworkGraph, forKey: Key.showNetworkGraph) } }
    @Published var showDiskGraph: Bool { didSet { defaults.set(showDiskGraph, forKey: Key.showDiskGraph) } }
    /// Seconds between samples, 1...60. Out-of-range values are stored and used clamped.
    @Published var updateInterval: Double {
        didSet { defaults.set(Self.clampedInterval(updateInterval), forKey: Key.updateInterval) }
    }
    /// Whether sampling stops a few seconds after the island closes (true) or keeps running
    /// until the Stats tab is left (false).
    @Published var stopWhenNotchCloses: Bool {
        didSet { defaults.set(stopWhenNotchCloses, forKey: Key.stopWhenNotchCloses) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showCpuGraph = defaults.object(forKey: Key.showCpuGraph) as? Bool ?? true
        showMemoryGraph = defaults.object(forKey: Key.showMemoryGraph) as? Bool ?? true
        showGpuGraph = defaults.object(forKey: Key.showGpuGraph) as? Bool ?? true
        showNetworkGraph = defaults.object(forKey: Key.showNetworkGraph) as? Bool ?? false
        showDiskGraph = defaults.object(forKey: Key.showDiskGraph) as? Bool ?? false
        updateInterval = Self.clampedInterval(
            defaults.object(forKey: Key.updateInterval) as? Double ?? Self.defaultUpdateInterval
        )
        stopWhenNotchCloses = defaults.object(forKey: Key.stopWhenNotchCloses) as? Bool ?? true
    }

    static func clampedInterval(_ value: Double) -> Double {
        guard value.isFinite else { return defaultUpdateInterval }
        return min(maximumUpdateInterval, max(minimumUpdateInterval, value))
    }

    /// The interval the sampler actually sleeps between ticks.
    var effectiveUpdateInterval: Double { Self.clampedInterval(updateInterval) }

    func isEnabled(_ metric: StatsMetric) -> Bool {
        switch metric {
        case .cpu: showCpuGraph
        case .memory: showMemoryGraph
        case .gpu: showGpuGraph
        case .network: showNetworkGraph
        case .disk: showDiskGraph
        }
    }

    /// The cards to show, always in CPU, Memory, GPU, Network, Disk order.
    var enabledMetrics: [StatsMetric] { StatsMetric.allCases.filter { isEnabled($0) } }

    var showsBatteryWarning: Bool {
        !stopWhenNotchCloses && effectiveUpdateInterval <= Self.batteryWarningInterval
    }
}

/// Form rows for the Settings window. Place inside a `Form`; `StatsSettingsTab` wraps it in
/// one for use as a TabView page.
struct StatsSettingsSection: View {
    @ObservedObject var settings: StatsSettings
    @ObservedObject var manager: StatsManager

    init(settings: StatsSettings = .shared, manager: StatsManager = .shared) {
        self.settings = settings
        self.manager = manager
    }

    var body: some View {
        Section("Monitoring") {
            Toggle("Stop monitoring after closing the notch", isOn: $settings.stopWhenNotchCloses)
            LabeledContent("Update interval") {
                HStack {
                    Slider(
                        value: $settings.updateInterval,
                        in: StatsSettings.minimumUpdateInterval...StatsSettings.maximumUpdateInterval,
                        step: 1
                    )
                    Text(Self.intervalLabel(settings.effectiveUpdateInterval))
                        .monospacedDigit()
                        .frame(width: 84, alignment: .trailing)
                }
            }
            Text("Controls how often system metrics refresh while monitoring is active.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if settings.showsBatteryWarning {
                Label(
                    "High-frequency updates without a timeout can increase battery usage.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        Section("Graphs") {
            Toggle("CPU usage", isOn: $settings.showCpuGraph)
            Toggle("Memory usage", isOn: $settings.showMemoryGraph)
            Toggle("GPU usage", isOn: $settings.showGpuGraph)
            Toggle("Network activity", isOn: $settings.showNetworkGraph)
            Toggle("Disk I/O", isOn: $settings.showDiskGraph)
            Text(graphFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Monitoring Status") {
            HStack(spacing: 8) {
                Circle()
                    .fill(manager.isMonitoring ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(manager.isMonitoring ? "Active" : "Stopped")
            }
            if manager.isMonitoring {
                LabeledContent("CPU", value: manager.cpuUsageString)
                LabeledContent("Memory", value: manager.memoryUsageString)
                LabeledContent("GPU", value: manager.gpuUsageString)
                LabeledContent("Network", value: "↓\(manager.networkDownloadString) • ↑\(manager.networkUploadString)")
                LabeledContent("Disk", value: "R \(manager.diskReadString) • W \(manager.diskWriteString)")
            }
        }
    }

    /// "1 s" ... "59 s", and "60 s (1 min)" at the top of the range.
    nonisolated static func intervalLabel(_ interval: Double) -> String {
        let seconds = Int(interval.rounded())
        return seconds >= 60 ? "60 s (1 min)" : "\(seconds) s"
    }

    private var graphFooter: String {
        let count = settings.enabledMetrics.count
        if count >= 4 {
            return "With \(count) graphs enabled, the island grows by \(Int(StatsLayout.secondRowExtraHeight)) pt to fit a second row of cards."
        }
        return "Each graph can be individually enabled or disabled. Network activity shows download/upload speeds, and disk I/O shows read/write speeds."
    }
}

/// A ready-made Settings tab: the section inside a grouped Form.
struct StatsSettingsTab: View {
    var body: some View {
        Form {
            StatsSettingsSection()
        }
        .formStyle(.grouped)
    }
}
