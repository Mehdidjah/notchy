import AppKit
import QuartzCore

/// Developer aid for measuring tab-switch smoothness: launched with `--perf-cycle-tabs`, the
/// app opens the island pinned, steps through every tab a few times while a display link
/// times every frame, prints a per-tab report, then quits. Does nothing without the argument.
@MainActor
enum PerfTabCycler {
    static let argument = "--perf-cycle-tabs"
    static let settleDelay: Duration = .seconds(6)
    static let stepInterval: Duration = .milliseconds(900)
    /// Frames are measured for this long after each switch (the slide lasts 0.3 s).
    static let measureWindow: TimeInterval = 0.6
    static let rounds = 3

    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    private static var recorder: FrameRecorder?

    static func startIfRequested(model: NotchViewModel) {
        guard isRequested else { return }
        Task { @MainActor in
            try? await Task.sleep(for: settleDelay)
            let recorder = FrameRecorder()
            Self.recorder = recorder
            recorder.start()
            var samples: [NotchTab: [FrameRecorder.Window]] = [:]
            for _ in 0..<rounds {
                for tab in model.availableTabs {
                    let start = CACurrentMediaTime()
                    let tapStart = Date()
                    model.selectTab(tab)
                    let selectCost = Date().timeIntervalSince(tapStart)
                    try? await Task.sleep(for: stepInterval)
                    var window = recorder.window(from: start, length: measureWindow)
                    window.selectCost = selectCost
                    samples[tab, default: []].append(window)
                }
            }
            recorder.stop()
            print(report(samples, refresh: recorder.nominalInterval))
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    private static func report(_ samples: [NotchTab: [FrameRecorder.Window]], refresh: Double) -> String {
        var lines = [String(format: "PERF nominal frame %.2f ms", refresh * 1000)]
        for tab in NotchTab.allCases {
            guard let windows = samples[tab], !windows.isEmpty else { continue }
            let worst = windows.map(\.worstFrame).max() ?? 0
            let hitches = windows.map(\.hitchCount).reduce(0, +)
            let dropped = windows.map(\.droppedFrames).reduce(0, +)
            let firstFrame = windows.map(\.firstFrameDelay).max() ?? 0
            let select = windows.map(\.selectCost).max() ?? 0
            lines.append(String(
                format: "PERF %@ switches=%d worstFrame=%.1fms hitches=%d dropped=%d firstFrame=%.1fms selectCall=%.1fms",
                tab.rawValue, windows.count, worst * 1000, hitches, dropped, firstFrame * 1000, select * 1000
            ))
        }
        return lines.joined(separator: "\n")
    }
}

/// Times every display refresh with a display link.
@MainActor
private final class FrameRecorder: NSObject {
    struct Window {
        var worstFrame: Double = 0
        var hitchCount = 0
        var droppedFrames = 0
        var firstFrameDelay: Double = 0
        var selectCost: Double = 0
    }

    private var link: CADisplayLink?
    private var timestamps: [CFTimeInterval] = []
    private(set) var nominalInterval: Double = 1.0 / 60

    func start() {
        guard let screen = NSScreen.main else { return }
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        timestamps.append(link.timestamp)
        let interval = link.targetTimestamp - link.timestamp
        if interval > 0.001 { nominalInterval = interval }
    }

    /// Frame gaps in `[start, start + length]`. A hitch is a frame taking over 1.5 refreshes.
    func window(from start: CFTimeInterval, length: Double) -> Window {
        let inWindow = timestamps.filter { $0 >= start && $0 <= start + length }
        var result = Window()
        result.firstFrameDelay = (inWindow.first ?? start) - start
        for (previous, next) in zip(inWindow, inWindow.dropFirst()) {
            let gap = next - previous
            result.worstFrame = max(result.worstFrame, gap)
            if gap > nominalInterval * 1.5 {
                result.hitchCount += 1
                result.droppedFrames += Int((gap / nominalInterval).rounded()) - 1
            }
        }
        result.worstFrame = max(result.worstFrame, result.firstFrameDelay)
        return result
    }
}
