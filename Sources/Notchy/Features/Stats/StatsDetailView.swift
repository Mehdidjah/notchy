import SwiftUI

/// The detail panel that replaces the card grid when a card is clicked: the numbers Atoll
/// shows in its popovers (usage rings, breakdown rows, per-core bars, pressure and swap,
/// devices, averages and peaks), laid out as compact columns inside the island so the
/// pointer never has to leave it.
struct StatsDetailView: View {
    let metric: StatsMetric
    @ObservedObject var manager: StatsManager
    let onClose: () -> Void

    static let systemColor = Color(red: 0.94, green: 0.32, blue: 0.28)
    static let userColor = Color(red: 0.27, green: 0.52, blue: 0.97)
    static let idleColor = Color.gray.opacity(0.28)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                columns
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(StatsLayout.gridPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: metric.systemImage)
                .foregroundStyle(metric.tint)
                .font(.caption)
            Text(metric.title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
            Spacer()
            if let lastUpdated = manager.lastUpdated {
                Text(lastUpdated, format: .dateTime.hour().minute().second())
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Back to graphs")
            .accessibilityLabel("Back to graphs")
        }
    }

    @ViewBuilder
    private var columns: some View {
        switch metric {
        case .cpu: cpuColumns
        case .memory: memoryColumns
        case .gpu: gpuColumns
        case .network: networkColumns
        case .disk: diskColumns
        }
    }

    // MARK: - CPU

    private var cpuColumns: some View {
        let cpu = manager.cpu
        return HStack(alignment: .top, spacing: 16) {
            StatsRing(
                segments: [
                    RingSegment(fraction: cpu.system / 100, color: Self.systemColor),
                    RingSegment(fraction: cpu.user / 100, color: Self.userColor)
                ],
                track: Self.idleColor.opacity(0.3),
                lineWidth: 9,
                size: 84
            ) {
                ringLabel(String(format: "%.0f%%", cpu.activeUsage), caption: "Active")
            }
            StatsDetailColumn(title: "Usage") {
                StatsDetailRow(label: "System", value: StatsFormatting.percentage(cpu.system), dot: Self.systemColor)
                StatsDetailRow(label: "User", value: StatsFormatting.percentage(cpu.user), dot: Self.userColor)
                StatsDetailRow(label: "Idle", value: StatsFormatting.percentage(cpu.idle), dot: Color.gray.opacity(0.5))
                StatsDetailRow(label: "Active", value: StatsFormatting.percentage(cpu.activeUsage))
            }
            StatsDetailColumn(title: "System") {
                StatsDetailRow(label: "Logical cores", value: "\(manager.coreUsage.count)")
                StatsDetailRow(label: "Uptime", value: StatsFormatting.abbreviatedDuration(manager.uptime))
                StatsDetailRow(label: "Load 1m", value: StatsFormatting.loadAverage(manager.loadAverage.oneMinute))
                StatsDetailRow(label: "Load 5m", value: StatsFormatting.loadAverage(manager.loadAverage.fiveMinutes))
                StatsDetailRow(label: "Load 15m", value: StatsFormatting.loadAverage(manager.loadAverage.fifteenMinutes))
            }
            if !manager.coreUsage.isEmpty {
                StatsDetailColumn(title: "Cores") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
                        ForEach(Array(manager.coreUsage.enumerated()), id: \.offset) { index, usage in
                            VStack(alignment: .leading, spacing: 2) {
                                StatsUsageBar(fraction: usage / 100, tint: Self.userColor)
                                Text("\(index + 1) · \(Int(usage.rounded()))%")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Memory

    private var memoryColumns: some View {
        let memory = manager.memory
        let freeColor = Color.gray.opacity(0.28)
        return HStack(alignment: .top, spacing: 16) {
            StatsRing(
                segments: [RingSegment(fraction: memory.usagePercent / 100, color: .green)],
                track: freeColor.opacity(0.35),
                lineWidth: 9,
                size: 84
            ) {
                ringLabel(String(format: "%.0f%%", memory.usagePercent), caption: "Used")
            }
            StatsDetailColumn(title: "Memory") {
                StatsDetailRow(label: "Used", value: StatsFormatting.bytes(memory.used), dot: Color.green.opacity(0.8))
                StatsDetailRow(label: "Free", value: StatsFormatting.bytes(memory.free), dot: freeColor.opacity(0.9))
                StatsDetailRow(label: "Total", value: StatsFormatting.bytes(memory.total))
            }
            StatsDetailColumn(title: "Breakdown") {
                memoryBreakdownRow("App", memory.app, opacity: 0.85)
                memoryBreakdownRow("Cached", memory.cache, opacity: 0.65)
                memoryBreakdownRow("Wired", memory.wired, opacity: 0.45)
                memoryBreakdownRow("Compressed", memory.compressed, opacity: 0.35)
            }
            StatsDetailColumn(title: "Pressure & Swap") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(memory.pressure.tint)
                        .frame(width: 8, height: 8)
                    Text(memory.pressure.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(memory.pressure.tint)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(memory.pressure.tint.opacity(0.16)))
                .help(memory.pressure.detail)
                if memory.swap.isEnabled {
                    StatsDetailRow(label: "Swap used", value: StatsFormatting.bytes(memory.swap.used))
                    StatsDetailRow(label: "Swap total", value: StatsFormatting.bytes(memory.swap.total))
                    StatsUsageBar(fraction: memory.swap.fraction, tint: .green)
                } else {
                    Text("Swap is disabled on this system.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func memoryBreakdownRow(_ label: String, _ bytes: UInt64, opacity: Double) -> StatsDetailRow {
        let share = String(format: "%.0f%%", manager.memory.percent(of: bytes))
        return StatsDetailRow(
            label: label,
            value: "\(StatsFormatting.bytes(bytes)) · \(share)",
            dot: Color.green.opacity(opacity)
        )
    }

    // MARK: - GPU

    private var gpuColumns: some View {
        HStack(alignment: .top, spacing: 16) {
            StatsRing(
                segments: [RingSegment(fraction: (manager.gpuUsage ?? 0) / 100, color: .purple)],
                track: Color.purple.opacity(0.25),
                lineWidth: 9,
                size: 84
            ) {
                ringLabel(manager.gpuUsage.map { String(format: "%.0f%%", $0) } ?? "—", caption: "Active")
            }
            StatsDetailColumn(title: "Averages") {
                StatsDetailRow(label: "Session avg", value: StatsFormatting.percentage(manager.history.gpu.averageOfNonZero))
                StatsDetailRow(label: "Peak", value: StatsFormatting.percentage(manager.history.gpu.maximum))
                StatsDetailRow(label: "Devices", value: "\(manager.gpuDevices.count)")
            }
            StatsDetailColumn(title: "Devices") {
                if manager.gpuDevices.isEmpty {
                    Text("No GPU utilisation counters are available.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                ForEach(manager.gpuDevices) { device in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(device.isActive ? Color.green.opacity(0.85) : Color.red.opacity(0.7))
                                .frame(width: 6, height: 6)
                            Text(device.name)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(device.utilization.map(StatsFormatting.percentage) ?? "—")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.purple)
                        }
                        if let render = device.renderUtilization {
                            StatsDetailRow(label: "Renderer", value: StatsFormatting.percentage(render), dot: Color.purple.opacity(0.9))
                        }
                        if let tiler = device.tilerUtilization {
                            StatsDetailRow(label: "Tiler", value: StatsFormatting.percentage(tiler), dot: Color.purple.opacity(0.6))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Network and disk

    private var networkColumns: some View {
        HStack(alignment: .top, spacing: 16) {
            rateColumn(
                title: "Download",
                color: .orange,
                current: manager.networkDownloadString,
                history: manager.history.networkDownload,
                sessionMB: manager.networkTotals.inboundMB
            ) { StatsFormatting.throughput(megabytesPerSecond: $0) }
            Divider().overlay(Color.white.opacity(0.06))
            rateColumn(
                title: "Upload",
                color: .red,
                current: manager.networkUploadString,
                history: manager.history.networkUpload,
                sessionMB: manager.networkTotals.outboundMB
            ) { StatsFormatting.throughput(megabytesPerSecond: $0) }
        }
    }

    private var diskColumns: some View {
        HStack(alignment: .top, spacing: 16) {
            rateColumn(
                title: "Read",
                color: .cyan,
                current: manager.diskReadString,
                history: manager.history.diskRead,
                sessionMB: manager.diskTotals.inboundMB
            ) { StatsFormatting.megabytesPerSecond($0) }
            Divider().overlay(Color.white.opacity(0.06))
            rateColumn(
                title: "Write",
                color: .yellow,
                current: manager.diskWriteString,
                history: manager.history.diskWrite,
                sessionMB: manager.diskTotals.outboundMB
            ) { StatsFormatting.megabytesPerSecond($0) }
            Divider().overlay(Color.white.opacity(0.06))
            StatsDetailColumn(title: "Startup Disk") {
                if let volume = manager.rootVolume {
                    StatsUsageBar(fraction: volume.fraction, tint: .cyan)
                    StatsDetailRow(label: "Used", value: StatsFormatting.bytes(volume.used))
                    StatsDetailRow(label: "Free", value: StatsFormatting.bytes(volume.free))
                    StatsDetailRow(label: "Total", value: StatsFormatting.bytes(volume.total))
                } else {
                    Text("Volume information is unavailable.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if !manager.diskThroughputAvailable {
                    Text("This Mac publishes no block-storage throughput counters.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func rateColumn(
        title: String,
        color: Color,
        current: String,
        history: MetricHistory,
        sessionMB: Double,
        format: (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(current)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            StatsDetailRow(label: "Average", value: format(history.averageOfNonZero), dot: color.opacity(0.6))
            StatsDetailRow(label: "Peak", value: format(history.maximum), dot: color.opacity(0.45))
            StatsDetailRow(label: "Session", value: StatsFormatting.megabytes(sessionMB))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ringLabel(_ value: String, caption: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(caption)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Building blocks

struct RingSegment: Equatable {
    var fraction: Double
    var color: Color
}

/// A track circle with one or more arcs laid end to end from twelve o'clock, round-capped.
struct StatsRing<Center: View>: View {
    let segments: [RingSegment]
    let track: Color
    let lineWidth: CGFloat
    let size: CGFloat
    @ViewBuilder let center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: lineWidth)
            ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                Circle()
                    .trim(from: arc.start, to: arc.end)
                    .stroke(arc.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            center()
        }
        .frame(width: size, height: size)
    }

    private var arcs: [(start: CGFloat, end: CGFloat, color: Color)] {
        var cursor: CGFloat = 0
        return segments.compactMap { segment in
            let span = CGFloat(min(1, max(0, segment.fraction.isFinite ? segment.fraction : 0)))
            guard span > 0 else { return nil }
            let arc = (start: cursor, end: min(1, cursor + span), color: segment.color)
            cursor = arc.end
            return arc
        }
    }
}

struct StatsDetailColumn<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatsDetailRow: View {
    let label: String
    let value: String
    var dot: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let dot {
                Circle()
                    .fill(dot)
                    .frame(width: 6, height: 6)
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

struct StatsUsageBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let clamped = CGFloat(min(1, max(0, fraction.isFinite ? fraction : 0)))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(tint.opacity(0.8))
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: 6)
    }
}
