import AppKit
import os
import QuartzCore
import SwiftUI

/// Developer aid for measuring tab-switch smoothness: launched with `--perf-cycle-tabs`, the
/// app opens the island pinned, steps through every tab a few times while a display link
/// times every frame, closes and reopens the island on Home, then measures the face animation
/// and quits. Does nothing without the argument.
@MainActor
enum PerfTabCycler {
    static let argument = "--perf-cycle-tabs"
    static let settleDelay: Duration = .seconds(6)
    static let stepInterval: Duration = .milliseconds(900)
    /// Frames are measured for this long after each switch (the slide lasts 0.3 s).
    static let measureWindow: TimeInterval = 0.6
    static let rounds = 3
    /// Close-and-reopen cycles; each spring settles within 0.7 s.
    static let islandRounds = 5
    static let islandWindow: TimeInterval = 0.7

    private static var enrollmentOnly: Bool { ProcessInfo.processInfo.arguments.contains("--perf-face-enrollment") }
    private static var unlockOnly: Bool { ProcessInfo.processInfo.arguments.contains("--perf-mac-unlock") }
    private static var originalUnlock: Bool { ProcessInfo.processInfo.arguments.contains("--perf-original-unlock") }
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(argument) || enrollmentOnly || unlockOnly || originalUnlock }

    private static var recorder: FrameRecorder?

    /// A standalone artwork profile avoids starting services, loading saved faces, and
    /// touching credentials or owner preferences. Called before application setup.
    static func startUnlockPreviewIfRequested() -> Bool {
        guard unlockOnly || originalUnlock else { return false }
        Task { @MainActor in
            try? await Task.sleep(for: settleDelay)
            let recorder = FrameRecorder()
            Self.recorder = recorder
            recorder.start()
            let samples = await measureMacUnlock(model: nil, recorder: recorder)
            recorder.stop()
            let style = originalUnlock ? "original" : "minimal"
            for name in samples.keys.sorted() {
                print(summary(name: "unlock-\(style)-\(name)", windows: samples[name] ?? []))
            }
            fflush(stdout)
            NSApp.terminate(nil)
        }
        return true
    }

    static func startIfRequested(model: NotchViewModel) {
        guard isRequested else { return }
        Task { @MainActor in
            try? await Task.sleep(for: settleDelay)
            let recorder = FrameRecorder()
            Self.recorder = recorder
            recorder.start()
            if unlockOnly {
                let samples = await measureMacUnlock(model: model, recorder: recorder)
                recorder.stop()
                for name in samples.keys.sorted() { print(summary(name: "unlock-\(name)", windows: samples[name] ?? [])) }
                fflush(stdout)
                NSApp.terminate(nil)
                return
            }
            if enrollmentOnly {
                let samples = await measureEnrollment(model: model, recorder: recorder)
                recorder.stop()
                for name in samples.keys.sorted() { print(summary(name: "enrollment-\(name)", windows: samples[name] ?? [])) }
                fflush(stdout)
                NSApp.terminate(nil)
                return
            }
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
            let media = MusicManager.shared
            let mediaContext = "PERF media playing=\(media.isPlaying ? 1 : 0) player=\(HomeLayoutState.shared.showsMediaPlayer ? 1 : 0)"
            let islandSamples = await measureOpenAndClose(model: model, recorder: recorder)
            let faceSamples = await measureFaceActivity(model: model, recorder: recorder)
            let enrollmentSamples = await measureEnrollment(model: model, recorder: recorder)
            recorder.stop()
            print(report(samples, refresh: recorder.nominalInterval))
            print(mediaContext)
            for name in islandSamples.keys.sorted() {
                print(summary(name: "island-\(name)", windows: islandSamples[name] ?? []))
                print("PERF island-\(name)-each " + (islandSamples[name] ?? []).map {
                    String(format: "%d/%d/%.0f", $0.hitchCount, $0.droppedFrames, $0.firstFrameDelay * 1000)
                }.joined(separator: " "))
            }
            for name in faceSamples.keys.sorted() {
                print(summary(name: "face-\(name)", windows: faceSamples[name] ?? []))
            }
            for name in enrollmentSamples.keys.sorted() {
                print(summary(name: "enrollment-\(name)", windows: enrollmentSamples[name] ?? []))
            }
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    /// Closes the island from Home and opens it again, timing each animation.
    private static func measureOpenAndClose(model: NotchViewModel, recorder: FrameRecorder) async -> [String: [FrameRecorder.Window]] {
        model.selectTab(.home)
        try? await Task.sleep(for: stepInterval)
        var samples: [String: [FrameRecorder.Window]] = [:]
        let signposter = OSSignposter(subsystem: "com.local.Notchy", category: .pointsOfInterest)
        for _ in 0..<islandRounds {
            var start = CACurrentMediaTime()
            signposter.emitEvent("close")
            model.escape()
            try? await Task.sleep(for: .seconds(1))
            samples["close", default: []].append(recorder.window(from: start, length: islandWindow))
            start = CACurrentMediaTime()
            signposter.emitEvent("open")
            model.openPinned()
            try? await Task.sleep(for: .seconds(1))
            samples["open", default: []].append(recorder.window(from: start, length: islandWindow))
        }
        return samples
    }

    /// Exercises presentation only: no camera, face comparison, or authorization request.
    private static func measureFaceActivity(model: NotchViewModel, recorder: FrameRecorder) async -> [String: [FrameRecorder.Window]] {
        let activity = FaceCheckLiveActivity()
        activity.hapticsEnabled = { false }
        activity.onRetry = { [weak activity] in activity?.begin(reason: "Animation preview") }
        model.selectTab(.home)
        model.collapseForFaceCheck()
        model.activityCenter.register(activity)
        var samples: [String: [FrameRecorder.Window]] = [:]
        for _ in 0..<rounds {
            var start = CACurrentMediaTime()
            activity.begin(reason: "Animation preview")
            try? await Task.sleep(for: .seconds(1))
            samples["expand", default: []].append(recorder.window(from: start, length: 0.8))
            start = CACurrentMediaTime()
            activity.update(prompt: "Blink once")
            try? await Task.sleep(for: .seconds(1))
            samples["scan", default: []].append(recorder.window(from: start, length: 0.9))
            start = CACurrentMediaTime()
            activity.finish(recognized: true, message: "Recognized")
            try? await Task.sleep(for: .milliseconds(1_500))
            samples["success", default: []].append(recorder.window(from: start, length: 1.4))
            start = CACurrentMediaTime()
            activity.finish(recognized: false, message: "Try again")
            try? await Task.sleep(for: .milliseconds(1_500))
            samples["failure", default: []].append(recorder.window(from: start, length: 1.4))
            start = CACurrentMediaTime()
            activity.handleHover(true)
            try? await Task.sleep(for: .seconds(1))
            samples["retry", default: []].append(recorder.window(from: start, length: 0.8))
            activity.dismiss()
            try? await Task.sleep(for: .milliseconds(700))
        }
        model.activityCenter.unregister(id: activity.activityID)
        return samples
    }

    private static func report(_ samples: [NotchTab: [FrameRecorder.Window]], refresh: Double) -> String {
        var lines = [String(format: "PERF nominal frame %.2f ms", refresh * 1000)]
        for tab in NotchTab.allCases {
            guard let windows = samples[tab], !windows.isEmpty else { continue }
            lines.append(summary(name: tab.rawValue, windows: windows))
        }
        return lines.joined(separator: "\n")
    }

    /// Exercises the lock-screen artwork on an ordinary desktop panel. It never locks the
    /// session, opens the camera, accesses a credential, or invokes the window-space adapter.
    private static func measureMacUnlock(model: NotchViewModel?, recorder: FrameRecorder) async -> [String: [FrameRecorder.Window]] {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return [:] }
        model?.collapseForFaceCheck()
        let activity = FaceCheckLiveActivity()
        activity.hapticsEnabled = { false }
        activity.onRetry = { [weak activity] in activity?.begin(reason: "Animation preview") }
        let panel = NSPanel(contentRect: CGRect(x: screen.frame.midX - 220, y: screen.frame.maxY - 260, width: 440, height: 260),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 5)
        if originalUnlock {
            panel.contentView = NSHostingView(rootView: MacUnlockOriginalView(activity: activity,
                topInset: MacUnlockGeometry.resolve(screen).closedSize.height))
        } else {
            panel.contentView = NSHostingView(rootView: MacUnlockOverlayView(activity: activity, geometry: .resolve(screen)))
        }
        panel.orderFrontRegardless()
        defer { activity.dismiss(); panel.orderOut(nil); panel.contentView = nil }
        var samples: [String: [FrameRecorder.Window]] = [:]
        for _ in 0..<rounds {
            var start = CACurrentMediaTime()
            activity.begin(reason: "Animation preview")
            try? await Task.sleep(for: .seconds(1))
            samples["open", default: []].append(recorder.window(from: start, length: 0.8))
            start = CACurrentMediaTime()
            activity.update(prompt: "Turn slightly toward your left shoulder.")
            try? await Task.sleep(for: .milliseconds(1_500))
            samples["scan", default: []].append(recorder.window(from: start, length: 1.4))
            start = CACurrentMediaTime()
            activity.finish(recognized: true, message: "Mac unlocked")
            try? await Task.sleep(for: .milliseconds(1_500))
            samples["success", default: []].append(recorder.window(from: start, length: 1.4))
            start = CACurrentMediaTime()
            activity.dismiss()
            try? await Task.sleep(for: .milliseconds(800))
            samples["close", default: []].append(recorder.window(from: start, length: 0.7))
            activity.begin(reason: "Animation preview")
            try? await Task.sleep(for: .seconds(1))
            start = CACurrentMediaTime()
            activity.finish(recognized: false, message: "Face not recognized. Hover to try again.")
            try? await Task.sleep(for: .milliseconds(1_500))
            samples["failure", default: []].append(recorder.window(from: start, length: 1.4))
            start = CACurrentMediaTime()
            activity.handleHover(true)
            try? await Task.sleep(for: .seconds(1))
            samples["retry", default: []].append(recorder.window(from: start, length: 0.8))
            activity.dismiss()
            try? await Task.sleep(for: .milliseconds(700))
        }
        return samples
    }

    /// Presentation-only enrollment cycle: no camera, face store, or credential access.
    private static func measureEnrollment(model: NotchViewModel, recorder: FrameRecorder) async -> [String: [FrameRecorder.Window]] {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return [:] }
        model.collapseForFaceCheck()
        let state = EnrollmentPerfState()
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 5)
        panel.contentView = NSHostingView(rootView: EnrollmentPerfView(state: state, geometry: NotchGeometryResolver.resolve(screen: screen)))
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil); panel.contentView = nil }
        var samples: [String: [FrameRecorder.Window]] = [:]
        for _ in 0..<rounds {
            state.counts = [:]
            state.phase = .scanning
            state.stage = .capturing
            try? await Task.sleep(for: .milliseconds(300))
            var start = CACurrentMediaTime()
            state.expanded = true
            try? await Task.sleep(for: .seconds(1))
            samples["open", default: []].append(recorder.window(from: start, length: 0.8))
            start = CACurrentMediaTime()
            for pose in FaceEnrollmentPose.guidedOrder.prefix(4) {
                state.counts[pose] = 2
                try? await Task.sleep(for: .milliseconds(700))
            }
            samples["capture-and-sweep", default: []].append(recorder.window(from: start, length: 2.8))
            start = CACurrentMediaTime()
            state.phase = .saved
            state.stage = .faceSaved
            try? await Task.sleep(for: .seconds(1))
            samples["save", default: []].append(recorder.window(from: start, length: 0.9))
            start = CACurrentMediaTime()
            state.unavailableReason = FaceModelValidation.unavailableMessage
            state.stage = .password
            try? await Task.sleep(for: .seconds(1))
            samples["saved-confirmation", default: []].append(recorder.window(from: start, length: 0.9))
            state.unavailableReason = nil
            for (name, stage) in [("password", FaceUnlockSetupSession.Stage.password), ("experimental-password", .password),
                                  ("permission", .permission), ("complete", .complete)] {
                start = CACurrentMediaTime()
                state.isExperimental = name == "experimental-password"
                state.stage = stage
                try? await Task.sleep(for: .seconds(1))
                samples[name, default: []].append(recorder.window(from: start, length: 0.9))
            }
            start = CACurrentMediaTime()
            state.expanded = false
            try? await Task.sleep(for: .milliseconds(700))
            samples["close", default: []].append(recorder.window(from: start, length: 0.6))
        }
        return samples
    }

    private static func summary(name: String, windows: [FrameRecorder.Window]) -> String {
        let worst = windows.map(\.worstFrame).max() ?? 0
        let hitches = windows.map(\.hitchCount).reduce(0, +)
        let dropped = windows.map(\.droppedFrames).reduce(0, +)
        let firstFrame = windows.map(\.firstFrameDelay).max() ?? 0
        let select = windows.map(\.selectCost).max() ?? 0
        return String(format: "PERF %@ switches=%d worstFrame=%.1fms hitches=%d dropped=%d firstFrame=%.1fms selectCall=%.1fms",
                      name, windows.count, worst * 1000, hitches, dropped, firstFrame * 1000, select * 1000)
    }
}

@MainActor
private final class EnrollmentPerfState: ObservableObject {
    @Published var counts: [FaceEnrollmentPose: Int] = [:]
    @Published var phase: FaceEnrollmentScanPhase = .scanning
    @Published var stage: FaceUnlockSetupSession.Stage = .capturing
    @Published var unavailableReason: String?
    @Published var isExperimental = false
    @Published var expanded = false
}

private struct EnrollmentPerfView: View {
    @ObservedObject var state: EnrollmentPerfState
    let geometry: NotchGeometry

    var body: some View {
        let target = FaceEnrollmentPresentation.nextPose(counts: state.counts, samplesPerPose: 2) ?? .centre
        ZStack(alignment: .top) {
            FaceEnrollmentSweepView(direction: state.expanded && state.phase == .scanning ? FaceEnrollmentPresentation.angle(for: target) : nil)
            FaceUnlockSetupSurface(stage: state.stage, hasHardwareNotch: geometry.isHardwareNotch,
                                    isExpanded: state.expanded, compactWidth: geometry.syntheticOrHardwareWidth + 32,
                                    compactHeight: geometry.topInset) {
                FaceEnrollmentScanView(counts: state.counts, instruction: FaceEnrollmentPresentation.instruction(for: target),
                                       phase: state.phase, hasHardwareNotch: geometry.isHardwareNotch,
                                       isExpanded: state.expanded, compactWidth: geometry.syntheticOrHardwareWidth + 32,
                                       compactHeight: geometry.topInset, drawsBackground: false, cancel: {}) {
                    Color(white: 0.15).overlay { Image(systemName: "person.fill").font(.system(size: 80)).foregroundStyle(.gray) }
                }
            } steps: {
                FaceUnlockSetupCard(stage: state.stage, unavailableReason: state.unavailableReason,
                                    isExperimental: state.isExperimental,
                                    hasHardwareNotch: geometry.isHardwareNotch,
                                    isExpanded: state.expanded, compactWidth: geometry.syntheticOrHardwareWidth + 32,
                                    compactHeight: geometry.topInset, drawsBackground: false) {
                    Text("Mac login password").foregroundStyle(.white.opacity(0.4)).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    private let signposter = OSSignposter(subsystem: "com.local.Notchy", category: .pointsOfInterest)

    @objc private func tick(_ link: CADisplayLink) {
        if let last = timestamps.last, link.timestamp - last > nominalInterval * 1.5 {
            signposter.emitEvent("hitch", "\(Int((link.timestamp - last) * 1000))")
        }
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
