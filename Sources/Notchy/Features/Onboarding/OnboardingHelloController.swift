import Combine
import Foundation

/// Runs the first-launch hello: one second after launch the island opens and shows the
/// glowing "hello" in place of its header and tabs; 3.5 s after the hello appears the island
/// closes and the hello is marked as shown. While it is up the island is held open (auto-close
/// is blocked during first launch). When the island cannot open, the hello waits for the next
/// launch.
@MainActor
final class OnboardingHelloController: ObservableObject {
    static let shared = OnboardingHelloController()

    /// Delay between launch and the island opening (`runAfter(1)`).
    static let openDelay: Duration = .seconds(1)
    /// How long the hello stays after it appears (`closeHello` after 3.5 s).
    static let holdDuration: Duration = .milliseconds(3_500)
    /// Delay used when the hello is replayed from Settings.
    static let replayDelay: Duration = .milliseconds(250)

    /// True while the open island should show the hello instead of its tabs.
    @Published private(set) var isPresenting = false
    /// Bumped on each presentation so an already visible hello restarts its stroke.
    @Published private(set) var replayCount = 0

    /// Opens the island and holds it open; false when it cannot open now (switched off or
    /// retracted for a fullscreen app). Wired by `OnboardingFeature`.
    var openIsland: (() -> Bool)?
    /// Closes the island again. Wired by `OnboardingFeature`.
    var closeIsland: (() -> Void)?
    /// Called once the hello has played and the island was asked to close.
    var onFinished: (() -> Void)?

    private var openTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private let sleeper: @Sendable (Duration) async -> Void

    init(sleeper: @escaping @Sendable (Duration) async -> Void = { duration in _ = try? await Task.sleep(for: duration) }) {
        self.sleeper = sleeper
    }

    /// Schedules the hello: the island opens after `delay`.
    func present(after delay: Duration = OnboardingHelloController.openDelay) {
        openTask?.cancel()
        closeTask?.cancel()
        closeTask = nil
        openTask = Task { @MainActor [weak self, sleeper] in
            await sleeper(delay)
            guard !Task.isCancelled, let self else { return }
            // A stage that is already on screen restarts its stroke but will not appear
            // again, so start its hold here.
            let stageAlreadyVisible = self.isPresenting
            self.replayCount += 1
            self.isPresenting = true
            guard self.openIsland?() == true else {
                self.isPresenting = false
                return
            }
            if stageAlreadyVisible { self.helloDidAppear() }
        }
    }

    /// Plays the hello again, for example from Settings.
    func replay() {
        present(after: Self.replayDelay)
    }

    /// The hello became visible in the island; close it after the hold. Repeated calls while
    /// a close is pending are ignored, so a re-render cannot extend the hold.
    func helloDidAppear() {
        guard isPresenting, closeTask == nil else { return }
        closeTask = Task { @MainActor [weak self, sleeper] in
            await sleeper(Self.holdDuration)
            guard !Task.isCancelled, let self else { return }
            self.finish()
        }
    }

    /// Ends the hello now and closes the island.
    func finish() {
        openTask?.cancel()
        closeTask?.cancel()
        closeTask = nil
        guard isPresenting else { return }
        closeIsland?()
        isPresenting = false
        onFinished?()
    }

    /// Stops any pending open or close without touching the island.
    func cancel() {
        openTask?.cancel()
        closeTask?.cancel()
        openTask = nil
        closeTask = nil
        isPresenting = false
    }
}
