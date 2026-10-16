import Foundation

/// Entry point for Keep Awake: the power-assertion controller behind the header button and its
/// popover. The ⇧⌘K shortcut is bound by the coordinator through the Shortcuts feature to
/// `CaffeinateController.shared.toggle()`.
@MainActor
enum CaffeinateFeature {
    private static var isRunning = false

    static var controller: CaffeinateController { .shared }

    static func start() {
        guard !isRunning else { return }
        isRunning = true
        CaffeinateController.shared.startObserving()
    }

    /// Ends any running session so the Mac can sleep again. Called when the app stops.
    static func stop() {
        isRunning = false
        let controller = CaffeinateController.shared
        controller.setPopoverPresented(false)
        controller.stopObserving()
        controller.deactivate()
    }
}
