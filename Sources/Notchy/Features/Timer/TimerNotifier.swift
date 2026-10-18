import AppKit
import Foundation
import UserNotifications

/// Plays the alert that marks the end of a countdown.
@MainActor
protocol TimerSoundPlaying: AnyObject {
    func play(named name: String, looping: Bool)
    func stop()
}

/// System alert sounds through NSSound. Loops until stopped when asked, the way a
/// kitchen timer keeps ringing until someone silences it.
@MainActor
final class SystemTimerSound: TimerSoundPlaying {
    private var sound: NSSound?

    func play(named name: String, looping: Bool) {
        stop()
        guard let candidate = NSSound(named: NSSound.Name(name)) else {
            NSSound.beep()
            return
        }
        candidate.loops = looping
        sound = candidate
        if !candidate.play() {
            NSSound.beep()
        }
    }

    func stop() {
        sound?.stop()
        sound = nil
    }
}

/// Posts the "timer finished" notification.
@MainActor
protocol TimerCompletionNotifying: AnyObject {
    /// Called when a timer starts so authorisation can be asked for ahead of the alert.
    func prepare()
    func notifyCompletion(name: String, duration: TimeInterval)
}

/// Local notifications through UNUserNotificationCenter. Everything runs in detached
/// tasks so the countdown never waits on the notification daemon, and nothing is
/// attempted when the process is not running from an app bundle, where the center
/// is unavailable.
@MainActor
final class TimerUserNotifier: TimerCompletionNotifying {
    static let categoryIdentifier = "timer.finished"

    private let isAvailable = NotificationRouter.isAvailable

    func prepare() {
        guard isAvailable else { return }
        NotificationRouter.shared.install()
        Task.detached(priority: .utility) {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            guard status == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func notifyCompletion(name: String, duration: TimeInterval) {
        guard isAvailable else { return }
        NotificationRouter.shared.install()
        let title = name.isEmpty ? "Timer" : name
        let body = "\(TimerFormatting.timeString(duration)) is up."
        let category = Self.categoryIdentifier
        Task.detached(priority: .utility) {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = nil // The looping alert sound is already playing.
            content.categoryIdentifier = category
            let request = UNNotificationRequest(
                identifier: "timer.finished.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }
}
