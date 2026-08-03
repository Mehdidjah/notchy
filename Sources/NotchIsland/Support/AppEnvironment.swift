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
    let permissionManager: PermissionManager
    let quickPasteWindowController: QuickPasteWindowController
    let libraryWindowController: LibraryWindowController
    let settingsWindowController: SettingsWindowController
    let menuBarController: MenuBarController

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
            settings: settings
        )
        let normalizer = ClipboardNormalizer(payloadStore: payloadStore)
        clipboardMonitor = ClipboardMonitor(
            normalizer: normalizer,
            repository: repository,
            policy: { [weak settings] in settings?.capturePolicy ?? CapturePolicy(isEnabled: false) }
        )
        panelController = NotchPanelController(model: model)
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
        }
        clipboardMonitor.onCaptureError = { [weak model] error in
            model?.reportCaptureError(error)
        }
        model.onOpenLibrary = { [weak libraryWindowController] in libraryWindowController?.show() }
        model.onOpenSettings = { [weak settingsWindowController] in settingsWindowController?.show() }
        model.onOpenQuickPaste = { [weak quickPasteWindowController] in quickPasteWindowController?.show() }
    }

    func start() {
        model.start()
        clipboardMonitor.start()
        panelController.show()
    }

    func stop() {
        clipboardMonitor.stop()
        panelController.stop()
        quickPasteWindowController.closeWindow()
        menuBarController.stop()
    }
}
