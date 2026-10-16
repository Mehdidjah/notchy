import Combine
import Foundation

/// Entry point for the camera mirror: starts the camera controller and keeps Home's mirror
/// column in step with the setting and with whether a camera is connected (Atoll hides the
/// mirror on Macs without one).
@MainActor
enum MirrorFeature {
    private static var subscriptions: Set<AnyCancellable> = []

    static var controller: WebcamController { .shared }

    static func start() {
        guard subscriptions.isEmpty else { return }
        let controller = WebcamController.shared
        controller.start()
        controller.settings.$isEnabled
            .combineLatest(controller.$cameraAvailable)
            .map { $0 && $1 }
            .removeDuplicates()
            .sink { shows in
                if HomeLayoutState.shared.showsMirror != shows {
                    HomeLayoutState.shared.showsMirror = shows
                }
            }
            .store(in: &subscriptions)
    }

    /// Stops the camera and removes the mirror from Home.
    static func stop() {
        subscriptions.removeAll()
        WebcamController.shared.stop()
        HomeLayoutState.shared.showsMirror = false
    }
}
