import AppKit
import Combine
import Foundation

/// Wires the volume, brightness and microphone observers, the media-key tap and the Caps Lock monitor to
/// the HUD, and keeps them in step with the settings.
@MainActor
final class SystemHUDManager {
    static let shared = SystemHUDManager()

    /// Volume updates echoed back by the device while the bar is being dragged are ignored
    /// for this long, so the bar does not jump back under the pointer.
    static let dragEchoWindow: Duration = .milliseconds(350)
    /// Minimum gap between two feedback sounds (0.08 s).
    static let feedbackInterval: Duration = .milliseconds(80)
    /// `com.apple.screenIsLocked` / `Unlocked`: public distributed notifications posted by
    /// loginwindow, the same signal the lock-screen manager uses.
    static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")
    static let screenUnlockedNotification = Notification.Name("com.apple.screenIsUnlocked")
    /// After a display wakes or the screen setup changes, macOS restores the backlight (and
    /// the built-in panel may come and go, as with the lid). The brightness monitor waits
    /// this long and starts over from a fresh baseline, so the restore is never mistaken
    /// for a key press.
    static let brightnessRestartDelay: Duration = .seconds(1)

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
    private var displayObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    /// Between `screensDidSleep` and `screensDidWake`: the backlight is off, nothing to watch.
    private var isDisplayAsleep = false
    private let screenTopology: @MainActor () -> ScreenTopology
    /// The screen setup when the display observers were installed or last changed.
    private var knownScreenTopology: ScreenTopology?
    private var brightnessRestartTask: Task<Void, Never>?
    private var lastDrag: ContinuousClock.Instant?
    private var lastFeedback: ContinuousClock.Instant?
    private let clock = ContinuousClock()
    private lazy var feedbackSound: NSSound? = Self.makeFeedbackSound()

    /// The click macOS itself plays for "Play feedback when volume is changed". Falls back to the "Pop" system sound.
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
        brightness: BrightnessMonitor = .shared,
        screenTopology: @escaping @MainActor () -> ScreenTopology = { ScreenTopology.current() }
    ) {
        self.settings = settings
        self.presenter = presenter
        self.volume = volume
        self.microphone = microphone
        self.interceptor = interceptor
        self.capsLock = capsLock
        self.brightness = brightness
        self.screenTopology = screenTopology
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
        interceptor.onBrightnessKey = { [weak self] direction in
            self?.brightness.brightnessKeyPressed(direction)
        }
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
        installDisplayObservers()
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
        interceptor.onBrightnessKey = nil
        interceptor.configure(interceptVolumeKeys: false, observeBrightnessKeys: false)
        removeLockObservers()
        removeDisplayObservers()
        brightnessRestartTask?.cancel()
        brightnessRestartTask = nil
        volume.stop()
        microphone.stop()
        capsLock.stop()
        brightness.stop()
        brightness.brightnessKeyTapDidStop()
        brightness.onUserChange = nil
        presenter.hideInlineHUD()
    }

    /// Applies the current settings: which observers run and whether keys are swallowed.
    func reconfigure() {
        guard isRunning else { return }
        let hudOn = settings.enableSystemHUD
        let brightnessOn = hudOn && settings.enableBrightnessHUD && !presenter.isScreenLocked
        // The tap also runs for the brightness HUD alone: it only reports brightness keys
        // and passes them on, so it is useful even with volume interception off.
        interceptor.configure(
            interceptVolumeKeys: hudOn && settings.enableVolumeHUD && settings.interceptMediaKeys
                && !presenter.isScreenLocked,
            observeBrightnessKeys: brightnessOn
        )
        brightnessKeyTapChanged(isObserving: interceptor.isObservingBrightnessKeys)
        if hudOn && settings.enableMicrophoneHUD { microphone.start() } else { microphone.stop() }
        if brightnessOn && !isDisplayAsleep && brightnessRestartTask == nil {
            brightness.start()
        } else {
            brightness.stop()
        }
        if settings.enableCapsLockIndicator { capsLock.start() } else { capsLock.stop() }
        if !hudOn || !settings.usesInlineStyle { presenter.hideInlineHUD() }
    }

    /// Keeps the brightness monitor's record of whether the tap sees brightness keys in
    /// step with the tap. Locking removes the tap only while the island is hidden, and
    /// unlocking installs it again under the same Accessibility grant, so the record
    /// stands; forgetting it would put the monitor back on the typing tier after every
    /// unlock until the next brightness key. Losing Accessibility or turning the HUD off
    /// (seen on unlock at the latest, which reconfigures) clears it.
    func brightnessKeyTapChanged(isObserving: Bool) {
        guard !isObserving, !presenter.isScreenLocked else { return }
        brightness.brightnessKeyTapDidStop()
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
    /// own HUD answers them.
    private func setScreenLocked(_ locked: Bool) {
        guard presenter.isScreenLocked != locked else { return }
        presenter.isScreenLocked = locked
        reconfigure()
    }

    // MARK: Display sleep and screen changes

    /// Display sleep turns the backlight off and wake turns it back on: both look like
    /// brightness changes right after input. Opening the lid or changing the screen setup
    /// can do the same. The brightness monitor sits these out and re-reads its baseline.
    private func installDisplayObservers() {
        knownScreenTopology = screenTopology()
        let workspace = NSWorkspace.shared.notificationCenter
        let sleep = workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysDidSleep() }
        }
        let wake = workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysDidWake() }
        }
        let screens = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenParametersDidChange() }
        }
        displayObservers = [(workspace, sleep), (workspace, wake), (.default, screens)]
    }

    private func removeDisplayObservers() {
        displayObservers.forEach { $0.center.removeObserver($0.token) }
        displayObservers.removeAll()
        knownScreenTopology = nil
    }

    /// AppKit posts `didChangeScreenParameters` whenever the EDR headroom changes, which on
    /// an XDR panel showing HDR content is every brightness step. Restarting then would
    /// stop the monitor for a second at the very key presses it should show, so only a
    /// change of the screens themselves restarts it; the monitor absorbs headroom changes
    /// on its own. Before the observers are installed there is nothing to compare with.
    func screenParametersDidChange() {
        let topology = screenTopology()
        defer { knownScreenTopology = topology }
        guard let known = knownScreenTopology, known != topology else { return }
        restartBrightnessSoon()
    }

    private func displaysDidSleep() {
        isDisplayAsleep = true
        brightnessRestartTask?.cancel()
        brightnessRestartTask = nil
        brightness.stop()
    }

    private func displaysDidWake() {
        isDisplayAsleep = false
        restartBrightnessSoon()
    }

    /// Stops the brightness monitor now and lets `reconfigure` start it again, from a fresh
    /// baseline, once the backlight has settled.
    private func restartBrightnessSoon() {
        brightness.stop()
        brightnessRestartTask?.cancel()
        brightnessRestartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.brightnessRestartDelay)
            guard !Task.isCancelled, let self else { return }
            self.brightnessRestartTask = nil
            self.reconfigure()
        }
    }
}
