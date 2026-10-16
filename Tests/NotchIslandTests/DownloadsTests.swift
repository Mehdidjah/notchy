import Combine
import Foundation
import Testing
@testable import NotchIsland

@MainActor
struct DownloadsTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "DownloadsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func listing(_ partials: Set<String>, _ stamps: [String: Date] = [:]) -> DownloadsFolderListing {
        DownloadsFolderListing(partials: partials, stamps: stamps)
    }

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: Partial names

    @Test
    func recognisesEveryBrowsersPartialExtension() {
        #expect(PartialDownloadName.isPartial("a.zip.crdownload"))
        #expect(PartialDownloadName.isPartial("a.zip.download"))
        #expect(PartialDownloadName.isPartial("a.zip.part"))
        #expect(PartialDownloadName.isPartial("a.zip.opdownload"))
        #expect(PartialDownloadName.isPartial("A.ZIP.CRDOWNLOAD"))
        #expect(!PartialDownloadName.isPartial("a.zip"))
        #expect(PartialDownloadName.finishedName(of: "report.pdf.crdownload") == "report.pdf")
    }

    @Test
    func finishedNeedsDataWrittenAfterTheDownloadStarted() {
        let vanished: Set = ["a.zip.part"]
        // Firefox's empty placeholder is never stamped: not finished.
        #expect(PartialDownloadName.finished(among: vanished, stamps: [:], startStamps: [:]).isEmpty)
        // Fresh data where nothing was before: finished.
        #expect(PartialDownloadName.finished(among: vanished, stamps: ["a.zip": t0], startStamps: [:]) == vanished)
        // Replacing an existing file: only a newer stamp counts.
        #expect(PartialDownloadName.finished(
            among: vanished, stamps: ["a.zip": t0], startStamps: ["a.zip": t0]
        ).isEmpty)
        #expect(PartialDownloadName.finished(
            among: vanished, stamps: ["a.zip": t0.addingTimeInterval(5)], startStamps: ["a.zip": t0]
        ) == vanished)
    }

    // MARK: Tracker

    @Test
    func baselineIgnoresDownloadsAlreadyRunningAtLaunch() {
        var tracker = DownloadTracker()
        #expect(tracker.ingest(listing(["old.crdownload"]), isShowing: false, isShowingCompletion: false) == .unchanged)
        #expect(tracker.ingest(listing(["old.crdownload"]), isShowing: false, isShowingCompletion: false) == .unchanged)
        #expect(tracker.ingest(listing([]), isShowing: false, isShowingCompletion: false) == .unchanged)
        // The name is free again once its file is gone.
        #expect(tracker.ingest(listing(["old.crdownload"]), isShowing: false, isShowingCompletion: false) == .downloading)
    }

    @Test
    func newDownloadThatLandsFinishes() {
        var tracker = DownloadTracker()
        _ = tracker.ingest(listing([]), isShowing: false, isShowingCompletion: false)
        #expect(tracker.ingest(listing(["a.zip.crdownload"]), isShowing: false, isShowingCompletion: false) == .downloading)
        #expect(tracker.activePartials == ["a.zip.crdownload"])
        #expect(tracker.ingest(listing([], ["a.zip": t0]), isShowing: true, isShowingCompletion: false) == .finished)
    }

    @Test
    func abandonedDownloadIsCancelled() {
        var tracker = DownloadTracker()
        _ = tracker.ingest(listing([]), isShowing: false, isShowingCompletion: false)
        _ = tracker.ingest(listing(["a.zip.part"]), isShowing: false, isShowingCompletion: false)
        #expect(tracker.ingest(listing([]), isShowing: true, isShowingCompletion: false) == .cancelled)
    }

    @Test
    func finishedDownloadIsRememberedWhileAnotherIsStillRunning() {
        var tracker = DownloadTracker()
        _ = tracker.ingest(listing([]), isShowing: false, isShowingCompletion: false)
        _ = tracker.ingest(listing(["a.zip.crdownload", "b.zip.crdownload"]), isShowing: false, isShowingCompletion: false)
        #expect(tracker.ingest(listing(["b.zip.crdownload"], ["a.zip": t0]), isShowing: true, isShowingCompletion: false) == .downloading)
        // b is cancelled, but a landed earlier: the run ends with the checkmark.
        #expect(tracker.ingest(listing([], ["a.zip": t0]), isShowing: true, isShowingCompletion: false) == .finished)
    }

    @Test
    func scansDuringTheCheckmarkDoNotCloseIt() {
        var tracker = DownloadTracker()
        _ = tracker.ingest(listing([]), isShowing: false, isShowingCompletion: false)
        _ = tracker.ingest(listing(["a.zip.download"]), isShowing: false, isShowingCompletion: false)
        _ = tracker.ingest(listing([], ["a.zip": t0]), isShowing: true, isShowingCompletion: false)
        #expect(tracker.ingest(listing([], ["a.zip": t0]), isShowing: true, isShowingCompletion: true) == .unchanged)
    }

    // MARK: Speed

    @Test
    func rateNeedsTheSameDownloadsOnBothSides() {
        let first = DownloadSpeedSample(bytes: 1_000, partials: ["a.part"], takenAt: t0)
        let second = DownloadSpeedSample(bytes: 3_000, partials: ["a.part"], takenAt: t0.addingTimeInterval(1))
        #expect(second.rate(since: first) == 2_000)

        let lostOne = DownloadSpeedSample(bytes: 5_000, partials: ["b.part"], takenAt: t0.addingTimeInterval(1))
        #expect(lostOne.rate(since: first) == nil, "a download that ended took its bytes with it")

        let shrunk = DownloadSpeedSample(bytes: 500, partials: ["a.part"], takenAt: t0.addingTimeInterval(1))
        #expect(shrunk.rate(since: first) == nil)
    }

    @Test
    func speedIsSmoothedAndHiddenWhenStalled() {
        #expect(DownloadSpeedSample.smoothed(previous: nil, sample: 100) == 100)
        #expect(DownloadSpeedSample.smoothed(previous: 100, sample: 200) == 140)
        #expect(DownloadSpeedSample.displayable(0.5) == nil)
        #expect(DownloadSpeedSample.displayable(1) == 1)
    }

    // MARK: Layout

    @Test
    func wingsCarryTheWidenedCentreAndTheSpeedAllowance() {
        let context = ClosedActivityContext(
            closedHeight: 32, notchWidth: 185, isHovering: false, gestureProgress: 0, hasHardwareNotch: true
        )
        // Atoll: left 20, centre +40, right max(60, 32) = 60. Atoll's widened centre ends on the
        // notch's right edge, so its +40 lies left of the notch: the host's left wing carries it.
        #expect(DownloadWingMetrics.leftWidth(in: context, showsSpeed: false) == 60)
        #expect(DownloadWingMetrics.rightWidth(in: context, showsSpeed: false) == 60)
        // With the rate: centre +58 more (left of the notch again) and right +58.
        #expect(DownloadWingMetrics.leftWidth(in: context, showsSpeed: true) == 118)
        #expect(DownloadWingMetrics.rightWidth(in: context, showsSpeed: true) == 118)
        let total = DownloadWingMetrics.leftWidth(in: context, showsSpeed: true)
            + DownloadWingMetrics.rightWidth(in: context, showsSpeed: true)
        let atollTotal: CGFloat = 20 + 60 + 40 + 58 + 58
        #expect(total == atollTotal)

        // Atoll's download view never sees hover or swipe.
        let hovered = ClosedActivityContext(
            closedHeight: 32, notchWidth: 185, isHovering: true, gestureProgress: 12, hasHardwareNotch: true
        )
        #expect(DownloadWingMetrics.leftWidth(in: hovered, showsSpeed: false) == 60)
        #expect(DownloadWingMetrics.rightWidth(in: hovered, showsSpeed: false) == 60)
    }

    @Test
    func speedTextUsesFileUnits() {
        #expect(DownloadSpeedText.string(bytesPerSecond: 1_200_000).hasSuffix("/s"))
        #expect(DownloadSpeedText.string(bytesPerSecond: 1_200_000).contains("MB"))
    }

    // MARK: Settings, watcher and activity

    @Test
    func settingsDefaultToAtollsChoices() {
        let defaults = makeDefaults()
        let settings = DownloadsSettings(defaults: defaults)
        #expect(settings.enableDownloadDetection)
        #expect(!settings.showDownloadSpeed)
        #expect(settings.indicatorStyle == .progress)
        settings.indicatorStyle = .circle
        #expect(DownloadsSettings(defaults: defaults).indicatorStyle == .circle)
    }

    @Test
    func watcherRunsTheDownloadLifecycle() {
        let watcher = DownloadWatcher(settings: DownloadsSettings(defaults: makeDefaults()), directory: nil)
        let activity = DownloadActivity(watcher: watcher)
        watcher.ingest(listing([]))
        #expect(!watcher.isDownloading)

        watcher.ingest(listing(["a.zip.crdownload"]))
        #expect(watcher.isDownloading)
        #expect(!watcher.isCompleted)
        #expect(activity.isActivityVisible)

        watcher.ingest(listing([], ["a.zip": t0]))
        #expect(watcher.isDownloading, "the checkmark holds the activity open")
        #expect(watcher.isCompleted)

        // A new download during the checkmark takes over again.
        watcher.ingest(listing(["b.zip.crdownload"], ["a.zip": t0]))
        #expect(watcher.isDownloading)
        #expect(!watcher.isCompleted)

        watcher.ingest(listing([], ["a.zip": t0]))
        #expect(!watcher.isDownloading, "b was abandoned")
        #expect(!activity.isActivityVisible)
    }

    @Test
    func unreadableFolderIsReported() {
        let watcher = DownloadWatcher(settings: DownloadsSettings(defaults: makeDefaults()), directory: nil)
        watcher.ingest(nil)
        #expect(!watcher.hasFolderAccess)
        watcher.ingest(listing([]))
        #expect(watcher.hasFolderAccess)
    }

    @Test
    func speedReadoutWidensTheWings() {
        let settings = DownloadsSettings(defaults: makeDefaults())
        settings.showDownloadSpeed = true
        let watcher = DownloadWatcher(settings: settings, directory: nil)
        let activity = DownloadActivity(watcher: watcher)
        var notifications = 0
        let token = activity.activityDidChange.sink { notifications += 1 }
        defer { token.cancel() }

        watcher.ingest(listing([]))
        watcher.ingest(listing(["a.zip.part"]))
        #expect(notifications == 1)
        #expect(!activity.showsSpeed)

        watcher.record(DownloadSpeedSample(bytes: 0, partials: ["a.zip.part"], takenAt: t0))
        watcher.record(DownloadSpeedSample(bytes: 2_000_000, partials: ["a.zip.part"], takenAt: t0.addingTimeInterval(1)))
        #expect(watcher.bytesPerSecond == 2_000_000)
        #expect(activity.showsSpeed)
        #expect(notifications == 2)
    }
}
