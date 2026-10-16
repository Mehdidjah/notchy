import Foundation

/// Determinate progress for downloads, where the browser offers it.
///
/// Browsers that show a progress bar on the file in Finder (Safari, Chromium-based browsers)
/// publish an `NSProgress` with the file's URL. `Progress.addSubscriber(forFileURL:)` on the
/// Downloads folder receives proxies for every item directly inside it; this keeps the live
/// ones and sums them for the downloads currently shown. Firefox publishes nothing, so its
/// downloads stay indeterminate, exactly as in Atoll.
@MainActor
final class DownloadProgressTracker {
    private var subscriber: Any?
    private var proxies: [ObjectIdentifier: DownloadProgressBox] = [:]

    init() {}

    var isSubscribed: Bool { subscriber != nil }

    func start(directory: URL) {
        guard subscriber == nil else { return }
        subscriber = Progress.addSubscriber(forFileURL: directory) { [weak self] progress in
            let box = DownloadProgressBox(progress)
            Self.onMain { self?.proxies[box.id] = box }
            return {
                Self.onMain { self?.proxies[box.id] = nil }
            }
        }
    }

    func stop() {
        if let subscriber { Progress.removeSubscriber(subscriber) }
        subscriber = nil
        proxies.removeAll()
    }

    /// Combined fraction for `partials`, or nil when any of them has no determinate progress.
    func fraction(for partials: Set<String>) -> Double? {
        guard !partials.isEmpty else { return nil }
        let names = partials.union(partials.map(PartialDownloadName.finishedName(of:)))
        let live = proxies.values.map(\.progress).filter { progress in
            !progress.isFinished && !progress.isCancelled
                && !progress.isIndeterminate && progress.totalUnitCount > 0
        }
        let matched = live.filter { progress in
            guard let url = progress.fileURL ?? (progress.userInfo[.fileURLKey] as? URL) else { return false }
            return names.contains(url.lastPathComponent)
        }
        // Proxies without a readable URL can still be used when they pair one-to-one.
        let candidates = matched.isEmpty && live.count == partials.count ? live : matched
        guard candidates.count >= partials.count else { return nil }
        let total = candidates.reduce(Int64(0)) { $0 + $1.totalUnitCount }
        let done = candidates.reduce(Int64(0)) { $0 + min($1.completedUnitCount, $1.totalUnitCount) }
        guard total > 0 else { return nil }
        return min(1, max(0, Double(done) / Double(total)))
    }

    /// The subscription blocks are documented to arrive on the main thread; this tolerates a
    /// system that does otherwise.
    nonisolated private static func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
        }
    }
}

/// Carries a progress proxy across the subscription block. `NSProgress` is thread-safe.
final class DownloadProgressBox: @unchecked Sendable {
    let progress: Progress
    var id: ObjectIdentifier { ObjectIdentifier(progress) }

    init(_ progress: Progress) {
        self.progress = progress
    }
}

/// A vnode watcher on one directory: fires on writes, renames, deletes and attribute changes
/// of its entries, on the queue it was given.
final class DownloadsDirectorySource: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject

    init?(directory: URL, queue: DispatchQueue, onEvent: @escaping @Sendable () -> Void) {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: queue
        )
        source.setEventHandler(handler: onEvent)
        source.setCancelHandler { close(descriptor) }
    }

    func resume() { source.resume() }
    func cancel() { source.cancel() }
}
