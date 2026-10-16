import AppKit
import SwiftUI
import Testing
@testable import Notchy

@MainActor
struct FaceCheckPresentationTests {
    @Test func incomingPeeksDoNotInterruptTheCheck() {
        let suite = "notchy.face-presentation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = IslandActivityCenter()
        let model = NotchViewModel(activityCenter: center, settings: UserSettings(defaults: defaults))
        let activity = FaceCheckLiveActivity()
        activity.begin(reason: "Reveal a hidden item")
        center.register(activity)
        let peek = SneakPeek(kind: .clipboard, systemImage: "doc.on.clipboard", title: "Copied")
        center.requestSneakPeek(peek)
        #expect(model.state == .idle)
        #expect(model.currentSneakPeek == nil)
        activity.dismiss()
        center.requestSneakPeek(peek)
        #expect(model.state == .peeking)
        #expect(model.currentSneakPeek?.id == peek.id)
    }

    @Test func activityExpandsBelowTheCutoutAndKeepsTheOpenTabHeight() async throws {
        let activity = FaceCheckLiveActivity()
        let context = ClosedActivityContext(closedHeight: 32, notchWidth: 190, isHovering: false,
                                            gestureProgress: 0, hasHardwareNotch: true)
        activity.begin(reason: "Reveal hidden clipboard item")
        let pill = activity.layout(in: context)
        let end = ContinuousClock.now.advanced(by: .seconds(1))
        while activity.phase == .preparing, ContinuousClock.now < end { try await Task.sleep(for: .milliseconds(10)) }
        let expanded = activity.layout(in: context)
        #expect(expanded.outerHeight > pill.outerHeight)
        #expect(expanded.contentWidth > pill.contentWidth)
        #expect(expanded.centerWidth >= context.notchWidth)
        #expect(expanded.outerHeight == 200)
        #expect(NotchTab.face.openHeight == NotchTab.home.openHeight)
        let detached = activity.layout(in: ClosedActivityContext(closedHeight: 24, notchWidth: 190,
                                                                  isHovering: false, gestureProgress: 0,
                                                                  hasHardwareNotch: false))
        #expect(detached.contentWidth + NotchSilhouette.closedHorizontalPadding * 2 == 180)
        #expect(detached.outerHeight == 180)

        let output = ProcessInfo.processInfo.environment["NOTCHY_FACE_SNAPSHOTS"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        for phase in [FaceCheckLiveActivity.Phase.scanning, .saved, .recognized, .failed] {
            switch phase {
            case .saved: activity.finish(saved: true, recognized: true, message: "Ready for your next check")
            case .recognized: activity.finish(recognized: true, message: "It's you.")
            case .failed: activity.finish(recognized: false, message: "Look at the camera and try again.")
            default: activity.update(prompt: "Turn slightly toward your left shoulder.")
            }
            let shape = NotchShape(topFlareRadius: 16, bottomCornerRadius: 60)
            let renderer = ImageRenderer(content: VStack(spacing: 0) {
                Color.clear.frame(height: context.closedHeight)
                FaceCheckActivityView(activity: activity, animates: false)
                    .frame(width: expanded.contentWidth, height: expanded.outerHeight - context.closedHeight)
            }
                .frame(width: expanded.contentWidth + 28, height: expanded.outerHeight)
                .background(shape.fill(.black))
                .clipShape(shape))
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            #expect(image.height == Int(expanded.outerHeight * 2))
            if let output {
                let bitmap = NSBitmapImageRep(cgImage: image)
                let data = try #require(bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]))
                try data.write(to: output.appendingPathComponent("\(phase).png"))
            }
        }
        if let output { try renderAnimationFrames(to: output) }
        activity.dismiss()
    }

    private func renderAnimationFrames(to output: URL) throws {
        let times = [0.0, 0.12, 0.22, 0.32, 0.46, 0.60, 0.76, 0.86, 1.05, 1.3]
        for phase in [FaceCheckLiveActivity.Phase.recognized, .failed] {
            let renderer = ImageRenderer(content: VStack(spacing: 0) {
                ForEach(0..<2) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<5) { column in
                            let time = times[row * 5 + column]
                            VStack(spacing: 0) {
                                FaceCheckEmblem(phase: phase, animates: false, progress: time)
                                    .frame(width: 156, height: 156)
                                Text(String(format: "%.2f s", time))
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.6))
                                    .frame(height: 20)
                            }
                        }
                    }
                }
            }.background(.black))
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            let bitmap = NSBitmapImageRep(cgImage: image)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: output.appendingPathComponent("\(phase)-frames.png"))
        }
    }
}
