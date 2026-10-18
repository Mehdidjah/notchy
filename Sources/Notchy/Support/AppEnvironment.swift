import AppKit
import Combine
import Foundation

@MainActor
final class AppEnvironment {
    let settings: UserSettings
    let repository: any ClipRepository
    let payloadStore: PayloadStore
    let targetTracker: FrontmostApplicationTracker
    let clipPasteboardWriter: SystemClipPasteboardWriter
    let pasteCoordinator: PasteCoordinator
    let model: NotchViewModel
    let clipboardMonitor: ClipboardMonitor
    let panelController: NotchPanelController
    let fullscreenDetector: FullscreenDetector
    let permissionManager: PermissionManager
    let quickPasteWindowController: QuickPasteWindowController
    let libraryWindowController: LibraryWindowController
    let settingsWindowController: SettingsWindowController
    let menuBarController: MenuBarController
    private var cancellables: Set<AnyCancellable> = []
    private var faceCheckWindow: FaceCheckWindowController?

    init() throws {
        settings = UserSettings()
        repository = try SwiftDataClipRepository.production()
        payloadStore = try PayloadStore.production()

        let pasteboardService = PasteboardService()
        targetTracker = FrontmostApplicationTracker()
        clipPasteboardWriter = SystemClipPasteboardWriter(payloadStore: payloadStore)
        pasteCoordinator = PasteCoordinator(pasteboardWriter: clipPasteboardWriter)
        model = NotchViewModel(
            repository: repository,
            pasteboardService: pasteboardService,
            pasteCoordinator: pasteCoordinator,
            targetProvider: targetTracker,
            settings: settings,
            faceAuthorizer: FaceCheckController.shared
        )
        let normalizer = ClipboardNormalizer(payloadStore: payloadStore)
        clipboardMonitor = ClipboardMonitor(
            normalizer: normalizer,
            repository: repository,
            policy: { [weak settings] in settings?.capturePolicy ?? CapturePolicy(isEnabled: false) }
        )
        panelController = NotchPanelController(model: model)
        fullscreenDetector = FullscreenDetector(
            screenProvider: { [weak panelController] in panelController?.currentScreen }
        )
        permissionManager = PermissionManager()
        quickPasteWindowController = QuickPasteWindowController(
            model: model,
            targetTracker: targetTracker
        )
        libraryWindowController = LibraryWindowController(model: model)
        settingsWindowController = SettingsWindowController(
            model: model,
            settings: settings,
            permissions: permissionManager
        )
        menuBarController = MenuBarController(
            model: model,
            openShelf: { [weak panelController] in panelController?.openPinned() },
            openQuickPaste: { [weak quickPasteWindowController] in quickPasteWindowController?.show() },
            openLibrary: { [weak libraryWindowController] in libraryWindowController?.show() },
            openSettings: { [weak settingsWindowController] in settingsWindowController?.show() }
        )

        pasteboardService.onInternalWrite = { [weak clipboardMonitor] changeCount in
            clipboardMonitor?.markInternalWrite(changeCount: changeCount)
        }
        clipPasteboardWriter.onInternalWrite = { [weak clipboardMonitor] changeCount in
            clipboardMonitor?.markInternalWrite(changeCount: changeCount)
        }
        clipboardMonitor.onClipCaptured = { [weak model] clip in
            model?.acceptCapturedClip(clip)
            model?.presentCapturePeek(for: clip)
        }
        clipboardMonitor.onCaptureError = { [weak model] error in
            model?.reportCaptureError(error)
        }
        fullscreenDetector.isEnabled = { [weak settings] in settings?.hideInFullscreen ?? false }
        fullscreenDetector.onChange = { [weak model] active in
            model?.setFullscreen(active)
        }
        model.fullscreenProvider = { [weak fullscreenDetector] in fullscreenDetector?.isFullscreen ?? false }
        settings.$hideInFullscreen
            .removeDuplicates()
            .dropFirst()
            .sink { [weak fullscreenDetector] _ in
                // Re-evaluate immediately; with hiding switched off this reports false.
                fullscreenDetector?.evaluate()
            }
            .store(in: &cancellables)
        Publishers.MergeMany(
            settings.$showHomeTab.map { _ in () }.eraseToAnyPublisher(),
            settings.$showShelfTab.map { _ in () }.eraseToAnyPublisher(),
            settings.$showTimerTab.map { _ in () }.eraseToAnyPublisher(),
            settings.$showStatsTab.map { _ in () }.eraseToAnyPublisher(),
            settings.$showNotesTab.map { _ in () }.eraseToAnyPublisher(),
            settings.$showFaceTab.map { _ in () }.eraseToAnyPublisher()
        )
        .dropFirst(6)
        .receive(on: RunLoop.main)
        .sink { [weak model] in model?.normalizeSelectedTab() }
        .store(in: &cancellables)
        model.onOpenLibrary = { [weak libraryWindowController] in libraryWindowController?.show() }
        model.onOpenSettings = { [weak settingsWindowController] in settingsWindowController?.show() }
        model.onOpenQuickPaste = { [weak quickPasteWindowController] in quickPasteWindowController?.show() }
    }

    /// Wires feature modules that have landed into the island, header and settings.
    private func startFeatures() {
        TimerFeature.start()
        model.liveActivityTabProvider = { TimerManager.shared.isActive ? .timer : nil }

        let colorPicker = ColorPickerService.shared
        colorPicker.hapticsEnabled = { [weak settings] in settings?.hapticsEnabled ?? true }
        colorPicker.onPopoverPresentationChanged = { [weak model] active in model?.setHeaderPopoverActive(active) }
        colorPicker.onColorPicked = { color in
            IslandActivityCenter.shared.requestSneakPeek(SneakPeek(
                kind: .colorPicker,
                systemImage: "eyedropper",
                title: color.hexString,
                subtitle: "Color Picked",
                tint: color.color,
                duration: .seconds(2)
            ))
        }
        SettingsSectionRegistry.shared.register(.colorPicker, id: "colorPicker") { ColorPickerSettingsSection() }

        // Stats: two rows of graphs make the island 132 pt taller; sampling follows the island.
        model.extraOpenHeightProvider = { tab in
            tab == .stats ? StatsLayout.extraOpenHeight(forCardCount: StatsSettings.shared.enabledMetrics.count) : 0
        }
        StatsSettings.shared.objectWillChange
            .sink { [weak model] _ in model?.openSizeDidChange.send() }
            .store(in: &cancellables)
        model.$state.combineLatest(model.$selectedTab)
            .receive(on: RunLoop.main)
            .sink { state, tab in
                StatsManager.shared.updateMonitoringState(notchIsOpen: state.showsShelfContent, statsTabSelected: tab == .stats)
            }
            .store(in: &cancellables)
        SettingsSectionRegistry.shared.register(.stats, id: "stats") { StatsSettingsSection() }

        // Shelf: count indicator on the closed notch, drop-to-open, settings.
        ShelfFeature.start(userSettings: settings, activityCenter: model.activityCenter)

        // Home: the music player and its closed-notch activity, and the calendar.
        MediaFeature.start()
        SettingsSectionRegistry.shared.register(.media, id: "media") { MediaSettingsSection() }
        CalendarFeature.start()
        SettingsSectionRegistry.shared.register(.calendar, id: "calendar") { CalendarSettingsSection() }

        // Volume, brightness and microphone HUDs on the closed notch, and Caps Lock.
        SystemHUDFeature.start()

        // The camera and model load only for a preview, enrollment, or an explicit check.
        let faceCheck = FaceCheckController.shared
        let faceWindow = FaceCheckWindowController(controller: faceCheck)
        faceCheckWindow = faceWindow
        model.activityCenter.register(faceCheck.liveActivity)
        faceCheck.liveActivity.hapticsEnabled = { [weak settings] in settings?.hapticsEnabled ?? false }
        faceCheck.onBeginCheck = { [weak model, weak faceWindow] in
            guard let model else { return }
            model.collapseForFaceCheck()
            if model.state == .disabled || model.state == .retractedForFullscreen { faceWindow?.show() }
        }
        faceCheck.onSaved = { [weak model] in model?.collapseForFaceCheck() }
        faceCheck.onNeedsEnrollment = { [weak model, weak settings] in
            settings?.showFaceTab = true
            model?.selectTab(.face)
            model?.openPinned()
        }
        faceCheck.loadIdentities()
        let workspaceEvents = NSWorkspace.shared.notificationCenter
        Publishers.Merge(
            workspaceEvents.publisher(for: NSWorkspace.sessionDidResignActiveNotification),
            workspaceEvents.publisher(for: NSWorkspace.willSleepNotification)
        )
        .receive(on: RunLoop.main)
        .sink { [weak model] _ in
            faceCheck.stopCamera()
            model?.lockSensitiveClips()
        }
        .store(in: &cancellables)
        SettingsSectionRegistry.shared.register(.faceCheck, id: "faceCheck") { FaceCheckSettingsSection() }

        // New releases: a sneak peek and a notification once per version, the menu bar, and About.
        UpdateChecker.shared.start()
        SettingsSectionRegistry.shared.register(.about, id: "updates") { UpdateSettingsSection() }
    }

    private func stopFeatures() {
        UpdateChecker.shared.stop()
        FaceCheckController.shared.stopCamera()
        faceCheckWindow?.hide()
        model.activityCenter.unregister(id: FaceCheckController.shared.liveActivity.activityID)
        SystemHUDFeature.stop()
        MediaFeature.stop()
        CalendarFeature.stop()
        TimerFeature.stop()
    }

    func start() {
        // Installed at launch so a click on a notification delivered before relaunch still routes.
        NotificationRouter.shared.install()
        startFeatures()
        model.start()
        clipboardMonitor.start()
        panelController.show()
        PerfTabCycler.startIfRequested(model: model)
        fullscreenDetector.start()
    }

    func stop() {
        stopFeatures()
        fullscreenDetector.stop()
        clipboardMonitor.stop()
        panelController.stop()
        quickPasteWindowController.closeWindow()
        menuBarController.stop()
    }
}
