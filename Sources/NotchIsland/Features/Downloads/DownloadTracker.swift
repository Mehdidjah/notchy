import Foundation

/// Names browsers give a file while they are still writing it.
///
/// Chromium-based browsers write `name.crdownload`, Safari a `name.download` bundle, Firefox
/// `name.part` and Opera `name.opdownload`. Removing the extension gives the name the finished
/// file will have.
enum PartialDownloadName {
    static let extensions: Set<String> = ["crdownload", "download", "opdownload", "part"]

    static func isPartial(_ name: String) -> Bool {
        extensions.contains((name as NSString).pathExtension.lowercased())
    }

    static func finishedName(of partial: String) -> String {
        (partial as NSString).deletingPathExtension
    }

    /// The partial files among `vanished` whose download finished rather than being abandoned.
    ///
    /// A download counts as finished only when its destination now holds data that was written
    /// after the partial file appeared. Existence is not enough: Firefox creates an empty
    /// placeholder at the destination up front (empty files are never stamped), and a download
    /// that replaces an existing file starts with a destination that already holds data, so
    /// the stamp must be strictly newer than the one recorded at the start.
    ///
    /// - Parameters:
    ///   - stamps: modification dates of the non-empty items in the folder now.
    ///   - startStamps: the destination's stamp when each partial appeared; absent means
    ///     nothing (with data) was there.
    static func finished(
        among vanished: Set<String>,
        stamps: [String: Date],
        startStamps: [String: Date]
    ) -> Set<String> {
        vanished.filter { partial in
            let destination = finishedName(of: partial)
            guard let now = stamps[destination] else { return false }
            guard let before = startStamps[destination] else { return true }
            return now > before
        }
    }
}

/// One read of the Downloads folder.
struct DownloadsFolderListing: Equatable, Sendable {
    /// Partial-download names present now.
    var partials: Set<String>
    /// Modification dates of the non-empty items present now, by name.
    var stamps: [String: Date]
}

/// Scan-to-scan bookkeeping that turns folder listings into "a download started", "it
/// finished" or "it was cancelled". Pure value logic, driven by `DownloadWatcher`.
struct DownloadTracker: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        /// Nothing to change.
        case unchanged
        /// At least one download is being written.
        case downloading
        /// Writing stopped and at least one download reached its destination.
        case finished
        /// Writing stopped and every download was abandoned.
        case cancelled
    }

    private(set) var hasBaseline = false
    private(set) var previousPartials: Set<String> = []
    /// Partials that were already there at the first scan; a download running before the app
    /// started does not claim the notch. A name leaves this set once its file is gone.
    private(set) var ignored: Set<String> = []
    /// Partials that went away since the activity appeared, judged once nothing is writing.
    private(set) var vanishedSinceActive: Set<String> = []
    private(set) var startStamps: [String: Date] = [:]
    /// Partials currently counted as live downloads.
    private(set) var activePartials: Set<String> = []

    init() {}

    mutating func reset() {
        self = DownloadTracker()
    }

    /// Feeds one listing.
    /// - Parameters:
    ///   - isShowing: the activity is on screen (downloading or showing completion).
    ///   - isShowingCompletion: the completion checkmark currently owns the activity.
    mutating func ingest(
        _ listing: DownloadsFolderListing,
        isShowing: Bool,
        isShowingCompletion: Bool
    ) -> Outcome {
        guard hasBaseline else {
            hasBaseline = true
            previousPartials = listing.partials
            ignored = listing.partials
            activePartials = []
            return .unchanged
        }

        let gone = previousPartials.subtracting(listing.partials)
        let appeared = listing.partials.subtracting(previousPartials)
        previousPartials = listing.partials

        // Record what each destination looked like the moment its download began.
        for partial in appeared {
            let destination = PartialDownloadName.finishedName(of: partial)
            startStamps[destination] = listing.stamps[destination]
        }

        vanishedSinceActive.formUnion(gone.subtracting(ignored))
        ignored.subtract(gone)
        activePartials = listing.partials.subtracting(ignored)

        if !activePartials.isEmpty { return .downloading }

        guard isShowing else {
            vanishedSinceActive.removeAll()
            startStamps.removeAll()
            return .unchanged
        }

        // The rename that completes a download is itself a folder event; once the checkmark
        // is up, later scans must not close it early.
        guard !isShowingCompletion else {
            vanishedSinceActive.removeAll()
            return .unchanged
        }

        let finished = PartialDownloadName.finished(
            among: vanishedSinceActive,
            stamps: listing.stamps,
            startStamps: startStamps
        )
        vanishedSinceActive.removeAll()
        startStamps.removeAll()
        return finished.isEmpty ? .cancelled : .finished
    }
}

/// Bytes on disk across the partial downloads at one moment, for the speed readout.
struct DownloadSpeedSample: Equatable, Sendable {
    let bytes: Int64
    let partials: Set<String>
    let takenAt: Date

    /// Bytes per second since `earlier`, or nil when this pair cannot carry a rate: a download
    /// that ended in between took its bytes with it, and a shrinking total is a truncation.
    func rate(since earlier: DownloadSpeedSample) -> Double? {
        guard earlier.partials.isSubset(of: partials) else { return nil }
        let elapsed = takenAt.timeIntervalSince(earlier.takenAt)
        guard elapsed > 0 else { return nil }
        let delta = bytes - earlier.bytes
        guard delta >= 0 else { return nil }
        return Double(delta) / elapsed
    }

    /// Exponential smoothing (factor 0.4) so one bursty flush does not swing the figure.
    static func smoothed(previous: Double?, sample: Double) -> Double {
        guard let previous else { return sample }
        return previous + (sample - previous) * 0.4
    }

    /// Below one byte a second the download is stalled, not slow; nothing is shown.
    static func displayable(_ speed: Double) -> Double? {
        speed >= 1 ? speed : nil
    }
}

/// Disk reads for the watcher. Called on the watcher's utility queue, never the main thread.
enum DownloadsFolderReader {
    static func listing(of directory: URL) -> DownloadsFolderListing? {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys
        ) else { return nil }

        var partials: Set<String> = []
        var stamps: [String: Date] = [:]
        for url in contents {
            let name = url.lastPathComponent
            if PartialDownloadName.isPartial(name) { partials.insert(name) }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard (values?.fileSize ?? 0) > 0, let modified = values?.contentModificationDate else { continue }
            stamps[name] = modified
        }
        return DownloadsFolderListing(partials: partials, stamps: stamps)
    }

    /// Allocated bytes of every partial download. Allocated rather than logical size: a browser
    /// that reserves the full length up front would otherwise look finished from the start.
    static func speedSample(of directory: URL, at date: Date = Date()) -> DownloadSpeedSample {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey]
        ) else {
            return DownloadSpeedSample(bytes: 0, partials: [], takenAt: date)
        }
        var bytes: Int64 = 0
        var partials: Set<String> = []
        for url in contents where PartialDownloadName.isPartial(url.lastPathComponent) {
            partials.insert(url.lastPathComponent)
            bytes += allocatedBytes(of: url)
        }
        return DownloadSpeedSample(bytes: bytes, partials: partials, takenAt: date)
    }

    /// Safari's `.download` is a bundle whose payload grows inside it, so bundles are walked.
    private static func allocatedBytes(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileAllocatedSizeKey, .fileSizeKey]
        func size(_ item: URL) -> Int64 {
            guard let values = try? item.resourceValues(forKeys: keys), values.isDirectory != true else { return 0 }
            return Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
            return size(url)
        }
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else {
            return 0
        }
        var total: Int64 = 0
        for case let child as URL in walker { total += size(child) }
        return total
    }
}
