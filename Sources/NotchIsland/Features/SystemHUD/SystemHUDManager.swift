import AppKit
import Combine
import Foundation

/// Wires the volume, brightness and microphone observers, the media-key tap and the Caps Lock monitor to
/// the HUD, and keeps them in step with the settings (Atoll `SystemHUDManager` +
/// `SystemChangesObserver`).
@MainActor
final class SystemHUDManager {
    static let shared = SystemHUDManager()

    /// Volume updates echoed back by the device while the bar is being dragged are ignored
    /// for this long, so the bar does not jump back under the pointer.
    static let dragEchoWindow: Duration = .milliseconds(350)
    /// Minimum gap between two feedback sounds (Atoll: 0.08 s).
    static let feedbackInterval: Duration = .milliseconds(80)
    /// `com.apple.screenIsLocked` / `Unlocked`: public distributed notifications posted by
    /// loginwindow, the same signal Atoll's lock-screen manager uses.
    static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")
    static let screenUnlockedNotification = Notification.Name("com.apple.screenIsUnlocked")

    let settings: SystemHUDSettings
    let presenter: SystemHUDPresenter
    let volume: VolumeController
    let microphone: MicrophoneMuteMonitor
    let interceptor: SystemHUDMediaKeyInterceptor
    let capsLock: CapsLockMonitor
    let brightness: BrightnessMonitor

    private(set) var isRunning = false
    private var cancellables: Set<AnyCancellable> = []
    private var lockObservers: [NSObjectProtocol] = []
    private var lastDrag: ContinuousClock.Instant?
    private var lastFeedback: ContinuousClock.Instant?
    private let clock = ContinuousClock()
    private lazy var feedbackSound: NSSound? = Self.makeFeedbackSound()

    /// The click macOS itself plays for "Play feedback when volume is changed"; Atoll ships
    /// its own short clip of the same kind. Falls back to the "Pop" system sound.
    static let systemVolumeFeedbackPath =
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Media Keys.aif"

    private static func makeFeedbackSound() -> NSSound? {
        if FileManager.default.fileExists(atPath: systemVolumeFeedbackPath),
           let sound = NSSound(contentsOfFile: systemVolumeFeedbackPath, byReference: true) {
            return sound
        }
        return NSSound(named: NSSound.Name("Pop"))
    }

    init(
        settings: SystemHUDSettings = .shared,
        presenter: SystemHUDPresenter = .shared,
        volume: VolumeController = .shared,
        microphone: MicrophoneMuteMonitor = .shared,
        interceptor: SystemHUDMediaKeyInterceptor = .shared,
        capsLock: CapsLockMonitor = .shared,
        brightness: BrightnessMonitor = .shared
    ) {
        self.settings = settings
        self.presenter = presenter
        self.volume = volume
        self.microphone = microphone
        self.interceptor = interceptor
        self.capsLock = capsLock
        self.brightness = brightness
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        volume.changes
            .sink { [weak self] change in self?.handle(change) }
            .store(in: &cancellables)
        microphone.muteChanges
            .sink { [weak self] muted in self?.presenter.presentMicrophone(isMuted: muted) }
            .store(in: &cancellables)
        interceptor.onCommand = { [weak self] command, _ in self?.handle(command) }
        brightness.onUserChange = { [weak self] level in
            self?.presenter.presentBrightness(level: CGFloat(level))
        }

        // `@Published` fires before the value lands; reconfigure on the next turn.
        Publishers.MergeMany(
            settings.$enableSystemHUD.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$enableVolumeHUD.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$enableMicrophoneHUD.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$enableBrightnessHUD.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$interceptMediaKeys.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$enableCapsLockIndicator.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$style.dropFirst().map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.reconfigure() }
        .store(in: &cancellables)

        installLockObservers()
        // Accessibility is often granted from System Settings or another onboarding step
        // while the app runs; coming back to the app is a cheap moment to retry the tap.
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.interceptor.refreshAccessibility()
                self?.reconfigure()
            }
            .store(in: &cancellables)
        volume.start()
        reconfigure()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        cancellables.removeAll()
        interceptor.onCommand = nil
        interceptor.setEnabled(false)
        removeLockObservers()
        volume.stop()
        microphone.stop()
        capsLock.stop()
        brightness.stop()
        brightness.onUserChange = nil
        presenter.hideInlineHUD()
    }

    /// Applies the current settings: which observers run and whether keys are swallowed.
    func reconfigure() {
        guard isRunning else { return }
        let hudOn = settings.enableSystemHUD
        interceptor.setEnabled(
            hudOn && settings.enableVolumeHUD && settings.interceptMediaKeys && !presenter.isScreenLocked
        )
        if hudOn && settings.enableMicrophoneHUD { microphone.start() } else { microphone.stop() }
        if hudOn && settings.enableBrightnessHUD && !presenter.isScreenLocked {
            brightness.start()
        } else {
            brightness.stop()
        }
        if settings.enableCapsLockIndicator { capsLock.start() } else { capsLock.stop() }
        if !hudOn || !settings.usesInlineStyle { presenter.hideInlineHUD() }
    }

    // MARK: Events

    private func handle(_ change: SystemAudioChange) {
        switch change.reason {
        case .initial:
            return
        case .command, .external:
            // Writes made by a drag come back in both forms, sometimes out of order.
            if let lastDrag, clock.now - lastDrag < Self.dragEchoWindow { return }
        case .routeChanged:
            break
        }
        presenter.presentVolume(
            level: CGFloat(change.snapshot.displayLevel),
            isBluetooth: change.snapshot.isBluetooth
        )
    }

    private func handle(_ command: SystemHUDMediaKeyCommand) {
        switch command {
        case .volumeUp(let fine):
            volume.adjust(by: settings.volumeStep(fine: fine))
            playFeedbackIfNeeded()
        case .volumeDown(let fine):
            volume.adjust(by: -settings.volumeStep(fine: fine))
            playFeedbackIfNeeded()
        case .toggleMute:
            volume.toggleMute()
        }
    }

    /// The inline bar was dragged: move the system volume with it.
    func userDraggedVolume(to value: CGFloat) {
        lastDrag = clock.now
        presenter.userDidDrag(to: value)
        volume.setVolume(Float(value))
    }

    private func playFeedbackIfNeeded() {
        guard settings.playVolumeFeedback else { return }
        let now = clock.now
        if let lastFeedback, now - lastFeedback < Self.feedbackInterval { return }
        lastFeedback = now
        guard let sound = feedbackSound else { return }
        sound.stop()
        sound.play()
    }

    // MARK: Lock state

    private func installLockObservers() {
        let center = DistributedNotificationCenter.default()
        let locked = center.addObserver(forName: Self.screenLockedNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setScreenLocked(true) }
        }
        let unlocked = center.addObserver(forName: Self.screenUnlockedNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setScreenLocked(false) }
        }
        lockObservers = [locked, unlocked]
    }

    private func removeLockObservers() {
        let center = DistributedNotificationCenter.default()
        lockObservers.forEach(center.removeObserver)
        lockObservers.removeAll()
    }

    /// While locked the island is hidden: stand down and hand the keys back to macOS so its
    /// own HUD answers them (Atoll `SystemHUDPlacement`).
    private func setScreenLocked(_ locked: Bool) {
        guard presenter.isScreenLocked != locked else { return }
        presenter.isScreenLocked = locked
        reconfigure()
    }
}
