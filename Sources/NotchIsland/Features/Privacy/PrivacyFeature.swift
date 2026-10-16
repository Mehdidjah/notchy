import Foundation

/// Entry point for the camera and microphone live activity.
@MainActor
enum PrivacyFeature {
    private static var activity: PrivacyActivity?

    /// Starts the detectors (each only while its setting is on) and registers the activity.
    static func start() {
        let monitor = PrivacyMonitor.shared
        monitor.start()
        let activity = activity ?? PrivacyActivity(monitor: monitor)
        activity.center = IslandActivityCenter.shared
        self.activity = activity
        IslandActivityCenter.shared.register(activity)
    }

    static func stop() {
        IslandActivityCenter.shared.unregister(id: PrivacyActivity.identifier)
        PrivacyMonitor.shared.stop()
    }
}
