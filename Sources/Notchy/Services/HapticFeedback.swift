import AppKit

@MainActor
protocol HapticFeedbackPerforming: AnyObject {
    func perform()
}

/// Plays the short alignment tap used when the island reacts to the pointer. Force Touch
/// trackpads play it; other input devices ignore it.
@MainActor
final class SystemHapticFeedback: HapticFeedbackPerforming {
    func perform() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
