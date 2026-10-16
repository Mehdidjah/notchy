import Foundation

/// Battery levels of connected Bluetooth devices, keyed by normalized address and by
/// lower-cased name.
struct BluetoothBatteryReport: Equatable, Sendable {
    var byAddress: [String: Int] = [:]
    var byName: [String: Int] = [:]

    func level(address: String, name: String) -> Int? {
        byAddress[BluetoothAudioDevice.normalizedAddress(address)] ?? byName[name.lowercased()]
    }
}

/// Best-effort battery levels for Bluetooth headphones.
///
/// macOS has no public API for an accessory's battery. The `system_profiler` tool that ships
/// with macOS prints the levels the Bluetooth daemon knows (AirPods buds and case, Beats,
/// many third-party headsets), so this runs it once per connection, off the main thread,
/// and gives up after a deadline. The JSON keys are undocumented and may change.
enum BluetoothBatteryReader {
    static let toolURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    static let batteryKeys = [
        "device_batteryLevelMain",
        "device_batteryLevel",
        "device_batteryLevelCombined",
        "device_batteryLevelLeft",
        "device_batteryLevelRight",
        "device_batteryLevelCase"
    ]

    /// Runs the tool and parses its report, or returns nil when it fails or overruns `timeout`.
    static func read(timeout: Duration) async -> BluetoothBatteryReport? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: runTool(timeout: timeout))
            }
        }
    }

    /// Parses `system_profiler SPBluetoothDataType -json`. Each connected device is a
    /// one-entry dictionary from its name to its properties; levels are strings like "80%".
    /// Like Atoll, the highest level among the main, left, right and case readings wins.
    static func parse(_ data: Data) -> BluetoothBatteryReport {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return BluetoothBatteryReport() }
        var report = BluetoothBatteryReport()
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let properties = value as? [String: Any],
                          let level = batteryLevel(in: properties)
                    else { continue }
                    report.byName[name.lowercased()] = level
                    if let address = properties["device_address"] as? String {
                        report.byAddress[BluetoothAudioDevice.normalizedAddress(address)] = level
                    }
                }
            }
        }
        return report
    }

    static func batteryLevel(in properties: [String: Any]) -> Int? {
        batteryKeys
            .compactMap { percent(properties[$0]) }
            .max()
    }

    private static func percent(_ value: Any?) -> Int? {
        let number: Int? = switch value {
        case let string as String:
            Int(string.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
        case let number as NSNumber:
            number.intValue
        default:
            nil
        }
        guard let number, (0...100).contains(number) else { return nil }
        return number
    }

    private static func runTool(timeout: Duration) -> BluetoothBatteryReport? {
        let process = Process()
        process.executableURL = toolURL
        process.arguments = ["SPBluetoothDataType", "-json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let watchdog = ProcessWatchdog(process: process)
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) {
            watchdog.terminateIfRunning()
        }
        // Read to the end before waiting, so a large report cannot fill the pipe and stall.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard !watchdog.didFire, process.terminationStatus == 0 else { return nil }
        return parse(data)
    }
}

/// Ends our own `system_profiler` child if it overruns its deadline.
private final class ProcessWatchdog: @unchecked Sendable {
    // `Process` is thread-safe for `isRunning` and `terminate()`; the lock guards `fired`.
    private let process: Process
    private let lock = NSLock()
    private var fired = false

    init(process: Process) {
        self.process = process
    }

    var didFire: Bool {
        lock.withLock { fired }
    }

    func terminateIfRunning() {
        lock.withLock {
            guard process.isRunning else { return }
            fired = true
            process.terminate()
        }
    }
}
