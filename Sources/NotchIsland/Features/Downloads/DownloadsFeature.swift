import Foundation

/// Entry point for the browser-download live activity.
@MainActor
enum DownloadsFeature {
    private static var activity: DownloadActivity?

    /// Starts watching ~/Downloads (when enabled) and registers the activity.
    static func start() {
        let watcher = DownloadWatcher.shared
        watcher.start()
        let activity = activity ?? DownloadActivity(watcher: watcher)
        activity.center = IslandActivityCenter.shared
        self.activity = activity
        IslandActivityCenter.shared.register(activity)
    }

    static func stop() {
        IslandActivityCenter.shared.unregister(id: DownloadActivity.identifier)
        DownloadWatcher.shared.stop()
    }
}
