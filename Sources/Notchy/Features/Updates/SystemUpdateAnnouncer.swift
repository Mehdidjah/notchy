import AppKit
import SwiftUI
import UserNotifications

/// Announces a new version with a sneak peek under the notch and a system notification that
/// opens the download when clicked.
@MainActor
final class SystemUpdateAnnouncer: UpdateAnnouncing {
    static let categoryIdentifier = "update.available"

    init() {
        NotificationRouter.shared.setClickAction(forCategory: Self.categoryIdentifier) { info in
            guard let link = info["url"], let url = URL(string: link) else { return }
            NSWorkspace.shared.open(url)
        }
    }

    func announce(_ release: UpdateRelease) {
        IslandActivityCenter.shared.requestSneakPeek(SneakPeek(
            kind: .update,
            systemImage: "arrow.down.circle.fill",
            title: "Notchy \(release.version)",
            subtitle: "Update Available",
            tint: .blue,
            duration: .seconds(4)
        ))

        guard NotificationRouter.isAvailable else { return }
        NotificationRouter.shared.install()
        let title = "Notchy \(release.version) is available"
        let link = release.preferredDownloadURL.absoluteString
        let category = Self.categoryIdentifier
        let identifier = "update.available.\(release.version)"
        Task.detached(priority: .utility) {
            let center = UNUserNotificationCenter.current()
            var status = await center.notificationSettings().authorizationStatus
            if status == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                status = await center.notificationSettings().authorizationStatus
            }
            guard status == .authorized || status == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = "Click to download the new version."
            content.sound = .default
            content.categoryIdentifier = category
            content.userInfo = ["url": link]
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        }
    }
}
