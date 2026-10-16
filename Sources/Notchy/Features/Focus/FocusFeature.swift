import Foundation

/// Entry point for the Focus (Do Not Disturb) live activity.
@MainActor
enum FocusFeature {
    private static var activity: FocusActivity?

    /// Starts Focus monitoring (when enabled) and registers the activity.
    static func start() {
        let monitor = FocusMonitor.shared
        monitor.start()
        let activity = activity ?? FocusActivity(monitor: monitor)
        activity.center = IslandActivityCenter.shared
        self.activity = activity
        IslandActivityCenter.shared.register(activity)
    }

    static func stop() {
        IslandActivityCenter.shared.unregister(id: FocusActivity.identifier)
        FocusMonitor.shared.stop()
    }
}
