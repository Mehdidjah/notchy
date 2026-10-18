import Foundation
import UserNotifications

/// The app's one notification-center delegate. Banners show while the app is active (the island
/// is a floating panel, so the user should see them either way), and clicking a notification runs
/// the action registered for its category.
@MainActor
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    /// The notification center is unavailable when the process is not running from an app bundle.
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    private var actions: [String: @MainActor ([String: String]) -> Void] = [:]
    private var isInstalled = false

    func install() {
        guard Self.isAvailable, !isInstalled else { return }
        isInstalled = true
        UNUserNotificationCenter.current().delegate = self
    }

    /// Runs `action` with the notification's string user info when one of `category` is clicked.
    func setClickAction(forCategory category: String, _ action: @escaping @MainActor ([String: String]) -> Void) {
        actions[category] = action
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let content = response.notification.request.content
        let category = content.categoryIdentifier
        var info: [String: String] = [:]
        for (key, value) in content.userInfo {
            if let key = key as? String, let value = value as? String { info[key] = value }
        }
        await MainActor.run { self.actions[category]?(info) }
    }
}
