import Foundation

/// Number and unit formatting shared by the stats cards, the detail panel and Settings.
enum StatsFormatting {
    /// "42.0%"
    static func percentage(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    /// A throughput given in MB/s, shown in the largest unit that is at least one: MB/s with
    /// one fraction digit from 10 up (two below), KB/s with none from 10 up (one below),
    /// B/s with no fraction digits, and "0 B/s" when nothing moved.
    static func throughput(megabytesPerSecond value: Double, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale

        func render(_ number: Double, fractionDigits: Int, unit: String) -> String {
            formatter.maximumFractionDigits = fractionDigits
            let text = formatter.string(from: NSNumber(value: number))
                ?? String(format: "%.\(fractionDigits)f", number)
            return "\(text) \(unit)"
        }

        guard value.isFinite, value > 0 else { return "0 B/s" }
        if value >= 1 {
            return render(value, fractionDigits: value >= 10 ? 1 : 2, unit: "MB/s")
        }
        let kilobytes = value * 1_024
        if kilobytes >= 1 {
            return render(kilobytes, fractionDigits: kilobytes >= 10 ? 0 : 1, unit: "KB/s")
        }
        let bytes = value * 1_048_576
        if bytes >= 1 {
            return render(bytes, fractionDigits: 0, unit: "B/s")
        }
        return "0 B/s"
    }

    /// Disk rates always read in MB/s with one fraction digit: "0.3 MB/s".
    static func megabytesPerSecond(_ value: Double) -> String {
        String(format: "%.1f MB/s", value)
    }

    /// Byte counts in MB or GB using memory (1024-based) units.
    static func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        formatter.includesUnit = true
        return formatter.string(fromByteCount: Int64(clamping: value))
    }

    /// Megabyte totals accumulated over a session, shown like `bytes`.
    static func megabytes(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return bytes(0) }
        let capped = min(value * 1_048_576, Double(Int64.max / 2))
        return bytes(UInt64(capped))
    }

    /// Uptime-style durations: at most two of days, hours and minutes, abbreviated.
    static func abbreviatedDuration(_ value: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: max(0, value)) ?? "—"
    }

    /// "1.23"
    static func loadAverage(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
