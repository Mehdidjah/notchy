import AppKit
import Combine
import Foundation

@MainActor
final class NotchViewModel: ObservableObject {
    @Published private(set) var state: NotchState
    @Published private var storedItems: [Clip]
    @Published var query = ""
    @Published var selectedCategory: ClipboardCategory = .history
    @Published var usesCompactCards = false
    @Published private(set) var copiedItemID: Clip.ID?
    @Published private(set) var selectedClipIDs: [Clip.ID] = []
    @Published private(set) var previewedClipID: Clip.ID?
    @Published private(set) var selectedClipID: Clip.ID?
    @Published private(set) var peekedClipID: Clip.ID?
    /// The sneak peek shown under the closed notch while `state == .peeking`.
    @Published private(set) var currentSneakPeek: SneakPeek?
    @Published private(set) var captureErrorDescription: String?
    @Published var multiPasteSeparator: MultiPasteSeparator = .blankLine
    @Published var multiPasteOutputFormat: MultiPasteOutputFormat = .plainText
    @Published var customSeparator = ""
    @Published private(set) var pasteOutcome: PasteOutcome?
    @Published private(set) var isPasteRunning = false
    @Published private(set) var isAuthorizingClipboard = false
    @Published private(set) var queue = SequentialPasteQueue()
    /// True while the pointer rests on the island. Drives the collapsed swell and the shadow.
    @Published private(set) var isHovering = false
    /// Positive while an open swipe stretches the collapsed notch, negative while a close
    /// swipe fades the open shelf. Returns to zero when the gesture ends or completes.
    @Published private(set) var gestureProgress: CGFloat = 0
    /// The tab shown in the open island and the direction the last switch travelled.
    @Published private(set) var selectedTab: NotchTab = .home
    @Published private(set) var tabSwitchForward = true
    @Published private(set) var notchGeometry = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        topInset: 30,
        hardwareNotchWidth: 0,
        isHardwareNotch: false
    )

    var onStateChange: ((NotchState) -> Void)?
    var onOpenLibrary: (() -> Void)?
    var onOpenSettings: ((SettingsPane?) -> Void)?
    var onOpenQuickPaste: (() -> Void)?
    /// Answers whether the island should currently be retracted for a fullscreen app.
    var fullscreenProvider: (() -> Bool)?
    /// Answers which tab a live activity wants the island to open on, if any (the island opens
    /// on the Timer tab while a timer runs, even with hover-to-open off).
    var liveActivityTabProvider: (() -> NotchTab?)?
    /// Reasons something outside the island's rect (a header popover, a share sheet, Quick
    /// Look, a drag out) needs the island to stay open. The pointer leaving the island does
    /// not fold it away while any reason is held.
    @Published private(set) var holdReasons: Set<String> = []
    var isHeaderPopoverActive: Bool { !holdReasons.isEmpty }

    /// How long a newly captured clip stays on the collapsed notch before it folds away.
    var peekDuration: Duration = .milliseconds(NotchInteractionDefaults.peekDurationMilliseconds)
    /// How long `.closing` lasts before `.idle`; the close animation in `NotchRootView` takes as long.
    var closeAnimationDuration: Duration = .milliseconds(500)

    let settings: UserSettings
    private let repository: any ClipRepository
    private let pasteboardService: any PasteboardWriting
    private let pasteCoordinator: (any PasteCoordinating)?
    private weak var targetProvider: (any PasteTargetProviding)?
    private let haptics: any HapticFeedbackPerforming
    private let faceAuthorizer: (any FaceCheckAuthorizing)?
    private let accessClock: @MainActor () -> TimeInterval
    private let revealDuration: TimeInterval
    private struct RevealGrant {
        let version: UUID
        let expiresAt: TimeInterval
    }
    @Published private var revealGrants: [Clip.ID: RevealGrant] = [:]
    private var clipVersions: [Clip.ID: UUID] = [:]
    private var pendingAuthorizationID: UUID?
    private var pendingAuthorizationClipIDs: Set<Clip.ID> = []
    private var revealExpiryTask: Task<Void, Never>?
    private var stateMachine: NotchStateMachine
    private var pointerIsInside = false
    private var lastHapticTime = Date.distantPast
    private var hoverTask: Task<Void, Never>?
    /// The grace period after the pointer leaves.
    private var closeTask: Task<Void, Never>?
    /// The close spring's settle time, kept apart from the grace period so a pointer that
    /// wanders during the animation cannot strand the island in `.closing`.
    private var closeAnimationTask: Task<Void, Never>?
    private var peekTask: Task<Void, Never>?
    private var dragOutTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    let activityCenter: IslandActivityCenter
    private var copiedFeedbackTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var pasteTask: Task<Void, Never>?

    init(
        items: [Clip] = [],
        repository: (any ClipRepository)? = nil,
        pasteboardService: any PasteboardWriting = PasteboardService(),
        pasteCoordinator: (any PasteCoordinating)? = nil,
        targetProvider: (any PasteTargetProviding)? = nil,
        haptics: (any HapticFeedbackPerforming)? = nil,
        activityCenter: IslandActivityCenter? = nil,
        settings: UserSettings = UserSettings(),
        faceAuthorizer: (any FaceCheckAuthorizing)? = nil,
        revealDuration: TimeInterval = 60,
        accessClock: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        #if DEBUG
        let previewMode = ProcessInfo.processInfo.arguments.contains("--expanded-preview")
            || PerfTabCycler.isRequested
        let initialItems = previewMode && items.isEmpty ? Clip.debugPreviewItems : items
        #else
        let previewMode = PerfTabCycler.isRequested
        let initialItems = items
        #endif
        self.storedItems = initialItems
        self.clipVersions = Dictionary(uniqueKeysWithValues: initialItems.map { ($0.id, UUID()) })
        self.repository = repository ?? InMemoryClipRepository(clips: initialItems)
        self.pasteboardService = pasteboardService
        self.pasteCoordinator = pasteCoordinator
        self.targetProvider = targetProvider
        self.haptics = haptics ?? SystemHapticFeedback()
        self.faceAuthorizer = faceAuthorizer
        self.accessClock = accessClock
        self.revealDuration = max(0, revealDuration)
        self.activityCenter = activityCenter ?? .shared
        self.settings = settings
        let initialState: NotchState = settings.notchEnabled
            ? (previewMode ? .pinnedOpen : .idle)
            : .disabled
        stateMachine = NotchStateMachine(initialState: initialState)
        state = initialState
        selectedTab = availableTabs.first ?? .clipboard
        self.activityCenter.sneakPeekRequests
            .sink { [weak self] peek in self?.presentSneakPeek(peek) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in self?.lockSensitiveClips(cancelPending: false) }
            .store(in: &cancellables)
        for notification in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: notification)
                .sink { [weak self] _ in self?.lockSensitiveClips() }
                .store(in: &cancellables)
        }
    }

    /// All presentation surfaces receive redacted values, including payload paths and metadata.
    /// Original values are resolved by ID only at the operation boundary below.
    var items: [Clip] { storedItems.map(presentationClip) }

    var isExpanded: Bool { state.isVisible && state != .peeking && state != .closing }
    var showsExpandedContent: Bool { state.showsShelfContent }
    var usesExpandedShape: Bool { state.isVisible }
    var isPinnedOpen: Bool { state == .pinnedOpen }
    var isSelectionMode: Bool { state == .multiSelecting }
    /// The collapsed notch grows slightly while hovered; the open shelf does not.
    var showsHoverSwell: Bool { isHovering && state.isCollapsed }
    var acceptsOpenGesture: Bool { state.isCollapsed }
    var acceptsCloseGesture: Bool { state == .expanded }

    /// Tabs offered in the open island, in display order. Clipboard is always present.
    var availableTabs: [NotchTab] {
        var tabs: [NotchTab] = []
        if settings.showHomeTab { tabs.append(.home) }
        if settings.showShelfTab { tabs.append(.shelf) }
        if settings.showTimerTab { tabs.append(.timer) }
        if settings.showStatsTab { tabs.append(.stats) }
        if settings.showNotesTab { tabs.append(.notes) }
        if settings.showFaceTab { tabs.append(.face) }
        if settings.showClaudeTab { tabs.append(.claude) }
        tabs.append(.clipboard)
        return tabs
    }

    /// Extra height a tab asks for beyond its base height (inline lyrics on Home, the second
    /// row of graphs on Stats). Feature modules answer through `extraOpenHeightProvider`.
    var extraOpenHeightProvider: ((NotchTab) -> CGFloat)?

    func extraOpenHeight(for tab: NotchTab) -> CGFloat {
        // Home's extra row (the inline lyric line) applies to every tab, so the island keeps
        // Home's size whichever tab is shown. Extras are design-size heights, drawn at the
        // content scale like everything else.
        (HomeLayoutState.shared.extraHeight + (extraOpenHeightProvider?(tab) ?? 0)) * NotchTab.contentScale
    }

    var extraOpenHeight: CGFloat { extraOpenHeight(for: selectedTab) }

    /// Fires when something that changes the open size (other than the tab) changed.
    let openSizeDidChange = PassthroughSubject<Void, Never>()

    /// Geometry for closed-notch activities at the current hover and swipe state.
    func closedActivityContext(hovering: Bool? = nil) -> ClosedActivityContext {
        ClosedActivityContext(
            closedHeight: notchGeometry.topInset,
            notchWidth: notchGeometry.syntheticOrHardwareWidth,
            isHovering: hovering ?? isHovering,
            gestureProgress: max(0, gestureProgress),
            hasHardwareNotch: notchGeometry.isHardwareNotch
        )
    }

    /// Column sizes of the activity that owns the closed notch, if any.
    func closedActivityLayout(hovering: Bool? = nil) -> ClosedActivityLayout? {
        activityCenter.layout(in: closedActivityContext(hovering: hovering))
    }

    /// Picks a valid tab after the tab settings change, and reopens on Home unless the user
    /// asked to keep the last tab.
    func normalizeSelectedTab(resetToFirst: Bool = false) {
        let tabs = availableTabs
        if resetToFirst || !tabs.contains(selectedTab), let first = tabs.first, first != selectedTab {
            tabSwitchForward = true
            selectedTab = first
        }
    }

    /// Header clipboard button in tab mode: show the clipboard, or go back to Home.
    func toggleClipboardTab() {
        selectTab(selectedTab == .clipboard ? (availableTabs.first ?? .clipboard) : .clipboard)
    }

    func selectTab(_ tab: NotchTab) {
        guard tab != selectedTab, availableTabs.contains(tab) else { return }
        let order = NotchTab.allCases
        let from = order.firstIndex(of: selectedTab) ?? 0
        let to = order.firstIndex(of: tab) ?? 0
        tabSwitchForward = to >= from
        selectedTab = tab
    }

    /// A card is being dragged out to another app. The pointer leaves the island during the
    /// drag, so hold the shelf open until the drag ends; the end is not reported reliably,
    /// so a safety timer releases the hold.
    func beginDragOut() {
        guard transition(.beginDrag).to == .dragging else { return }
        closeTask?.cancel()
        dragOutTask?.cancel()
        dragOutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, self.state == .dragging else { return }
            self.endDragOut()
        }
    }

    func endDragOut() {
        dragOutTask?.cancel()
        guard state == .dragging else { return }
        transition(.endDrag)
        if !pointerIsInside { scheduleCloseIfAllowed() }
    }

    var filteredItems: [Clip] {
        storedItems.filter { item in
            matchesSelectedCategory(item) && matchesSearch(item)
        }.map(presentationClip)
    }

    var previewedClip: Clip? {
        guard let previewedClipID else { return nil }
        return storedItems.first { $0.id == previewedClipID }.map(presentationClip)
    }

    var peekedClip: Clip? {
        guard let peekedClipID else { return nil }
        return storedItems.first { $0.id == peekedClipID }.map(presentationClip)
    }

    var selectedClip: Clip? {
        guard let selectedClipID else { return filteredItems.first }
        return storedItems.first { $0.id == selectedClipID }.map(presentationClip)
    }

    var selectedClips: [Clip] {
        selectedClipIDs.compactMap { id in storedItems.first { $0.id == id }.map(presentationClip) }
    }

    func start() {
        loadTask?.cancel()
        loadTask = Task { [weak self, repository] in
            do {
                let stored = try await repository.fetchAll(limit: nil)
                guard !Task.isCancelled, let self else { return }
                self.lockSensitiveClips()
                self.storedItems = stored
                self.clipVersions = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, UUID()) })
            } catch {
                self?.captureErrorDescription = error.localizedDescription
            }
        }
    }

    func acceptCapturedClip(_ clip: Clip) {
        if let index = storedItems.firstIndex(where: { $0.id == clip.id || $0.contentHash == clip.contentHash }) {
            let previous = storedItems[index]
            guard previous != clip else { return }
            if pendingAuthorizationClipIDs.contains(previous.id) { cancelClipboardAuthorization() }
            revealGrants.removeValue(forKey: previous.id)
            clipVersions.removeValue(forKey: previous.id)
            storedItems[index] = clip
        } else {
            storedItems.append(clip)
        }
        clipVersions[clip.id] = UUID()
        storedItems.sort { $0.lastCopiedAt > $1.lastCopiedAt }
    }

    /// Briefly drops a row under the collapsed notch to show what was just copied.
    func presentCapturePeek(for clip: Clip) {
        guard settings.showCapturePeek else { return }
        let visibleClip = presentationClip(clip)
        let title = visibleClip.title.replacingOccurrences(of: "\n", with: " ")
        presentSneakPeek(
            SneakPeek(kind: .clipboard, systemImage: isClipLocked(clip) ? "lock.fill" : visibleClip.symbolName, title: title, subtitle: "Copied", duration: peekDuration),
            clipID: clip.id
        )
    }

    /// Shows a sneak peek under the closed notch, for track changes and system
    /// events, then folds it away. Skipped while the island is open or hovered; a newer
    /// peek replaces one that is already showing.
    func presentSneakPeek(_ peek: SneakPeek, clipID: Clip.ID? = nil) {
        guard activityCenter.activeActivity?.suppressesAutomaticOpen != true else { return }
        guard !pointerIsInside, state == .idle || state == .peeking else { return }
        if state == .idle {
            guard transition(.peekRequested).to == .peeking else { return }
        }
        currentSneakPeek = peek
        peekedClipID = clipID
        peekTask?.cancel()
        let duration = peek.duration
        peekTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, self.state == .peeking else { return }
            self.transition(.peekElapsed)
            if self.pointerIsInside {
                // The pointer rested on the peek: arm a normal hover-open from here.
                self.targetProvider?.rememberFrontmostApplication()
                self.triggerHaptic()
                self.transition(.pointerEntered)
                if self.settings.openOnHover { self.scheduleDwell() }
            } else {
                self.scheduleCloseAnimationCompletion()
            }
        }
    }

    func reportCaptureError(_ error: Error) {
        captureErrorDescription = error.localizedDescription
    }

    func updateNotchGeometry(_ geometry: NotchGeometry) {
        notchGeometry = geometry
    }

    func count(for category: ClipboardCategory) -> Int {
        storedItems.filter { matchesCategory($0, category: category) }.count
    }

    func setHovered(_ hovered: Bool) {
        hovered ? pointerEntered() : pointerExited()
    }

    func pointerEntered() {
        let onCollapsedSurface = state.isCollapsed || state == .peeking
        if onCollapsedSurface { targetProvider?.rememberFrontmostApplication() }
        pointerIsInside = true
        if state == .dragging { endDragOut() }
        closeTask?.cancel()
        isHovering = true
        if activityCenter.activeActivity?.handleHover(true) == true
            || activityCenter.activeActivity?.suppressesAutomaticOpen == true {
            hoverTask?.cancel()
            return
        }
        let transition = transition(.pointerEntered)
        if onCollapsedSurface { triggerHaptic() }
        if transition.to == .hoverArmed, settings.openOnHover || liveActivityTabProvider?() != nil {
            scheduleDwell()
        }
    }

    func setHeaderPopoverActive(_ active: Bool) {
        active ? holdOpen(reason: "headerPopover") : releaseHold(reason: "headerPopover")
    }

    func holdOpen(reason: String) {
        guard holdReasons.insert(reason).inserted else { return }
        closeTask?.cancel()
    }

    func releaseHold(reason: String) {
        guard holdReasons.remove(reason) != nil, holdReasons.isEmpty, !pointerIsInside else { return }
        scheduleCloseIfAllowed()
    }

    func pointerExited() {
        pointerIsInside = false
        _ = activityCenter.activeActivity?.handleHover(false)
        if isHeaderPopoverActive { return }
        if state == .hoverArmed { hoverTask?.cancel() }
        if state == .peeking {
            isHovering = false
            return
        }
        scheduleCloseIfAllowed()
    }

    /// A click on the collapsed notch opens it at once; the shelf then follows the pointer
    /// like a hover-open and folds away after the pointer leaves.
    func openFromClick() {
        if activityCenter.activeActivity?.handleTap() == true { return }
        guard activityCenter.activeActivity?.suppressesAutomaticOpen != true else { return }
        guard state.isCollapsed || state == .peeking else { return }
        cancelPendingTimers()
        targetProvider?.rememberFrontmostApplication()
        gestureProgress = 0
        triggerHaptic()
        selectLiveActivityTabIfNeeded()
        transition(.openRequested)
        if !pointerIsInside { scheduleCloseIfAllowed() }
    }

    /// Accumulated downward trackpad travel over the collapsed notch. The notch stretches
    /// with the swipe and opens once the travel passes the configured sensitivity.
    func updateOpenGesture(translation: CGFloat) {
        guard activityCenter.activeActivity?.suppressesAutomaticOpen != true else { return }
        guard settings.gesturesEnabled, acceptsOpenGesture else { return }
        let sensitivity = CGFloat(settings.gestureSensitivity)
        guard sensitivity > 0 else { return }
        if translation > sensitivity {
            gestureProgress = 0
            cancelPendingTimers()
            targetProvider?.rememberFrontmostApplication()
            triggerHaptic()
            selectLiveActivityTabIfNeeded()
            transition(.openRequested)
            return
        }
        gestureProgress = min(NotchSilhouette.gestureStretch, translation / sensitivity * NotchSilhouette.gestureStretch)
    }

    /// Accumulated upward trackpad travel over the open shelf. The content fades with the
    /// swipe and the shelf closes once the travel passes the configured sensitivity.
    func updateCloseGesture(translation: CGFloat) {
        guard settings.gesturesEnabled, settings.closeGestureEnabled, acceptsCloseGesture else { return }
        let sensitivity = CGFloat(settings.gestureSensitivity)
        guard sensitivity > 0 else { return }
        if translation > sensitivity {
            gestureProgress = 0
            closeTask?.cancel()
            triggerHaptic()
            if transition(.closeDelayElapsed).to == .closing {
                dropHoverAfterClose()
                scheduleCloseAnimationCompletion()
            }
            return
        }
        gestureProgress = -min(NotchSilhouette.gestureStretch, translation / sensitivity * NotchSilhouette.gestureStretch)
    }

    func endGesture() {
        gestureProgress = 0
    }

    func openPinned() {
        targetProvider?.rememberFrontmostApplication()
        cancelPendingTimers()
        transition(.openPinned)
    }

    func togglePin() {
        let result = transition(state == .pinnedOpen ? .unpin : .pin)
        guard result.wasAccepted else { return }
        closeTask?.cancel()
        if state == .expanded, !pointerIsInside { scheduleCloseIfAllowed() }
    }

    func setKeyboardFocus(_ focused: Bool) {
        transition(focused ? .focusSearch : .blurSearch)
        if !focused && !pointerIsInside { scheduleCloseIfAllowed() }
    }

    func openPreview(_ clip: Clip) {
        withAuthorizedClips(ids: [clip.id], reason: "Reveal this hidden clipboard item") { model, clips in
            guard let clip = clips.first else { return }
            model.previewedClipID = clip.id
            model.selectedClipID = clip.id
            model.transition(.openPreview)
        }
    }

    func closePreview() {
        previewedClipID = nil
        transition(.closePreview)
        if !pointerIsInside { scheduleCloseIfAllowed() }
    }

    func beginSelection() {
        transition(.beginMultiSelect)
    }

    func endSelection() {
        selectedClipIDs.removeAll()
        transition(.endMultiSelect)
        if !pointerIsInside { scheduleCloseIfAllowed() }
    }

    func toggleSelection(_ clip: Clip) {
        if let index = selectedClipIDs.firstIndex(of: clip.id) {
            selectedClipIDs.remove(at: index)
        } else {
            selectedClipIDs.append(clip.id)
        }
        if selectedClipIDs.isEmpty {
            transition(.endMultiSelect)
        } else if state != .multiSelecting {
            transition(.beginMultiSelect)
        }
    }

    func selectRange(to clip: Clip) {
        let visible = filteredItems
        guard let target = visible.firstIndex(where: { $0.id == clip.id }) else { return }
        let anchorID = selectedClipIDs.last ?? selectedClipID
        let anchor = anchorID.flatMap { id in visible.firstIndex { $0.id == id } } ?? target
        let bounds = min(anchor, target)...max(anchor, target)
        for item in visible[bounds] where !selectedClipIDs.contains(item.id) {
            selectedClipIDs.append(item.id)
        }
        if !selectedClipIDs.isEmpty, state != .multiSelecting { transition(.beginMultiSelect) }
    }

    func removeFromSelection(_ clip: Clip) {
        selectedClipIDs.removeAll { $0 == clip.id }
        if selectedClipIDs.isEmpty { transition(.endMultiSelect) }
    }

    func clearSelection() {
        selectedClipIDs.removeAll()
        transition(.endMultiSelect)
        if !pointerIsInside { scheduleCloseIfAllowed() }
    }

    func reorderSelection(fromOffsets: IndexSet, toOffset: Int) {
        selectedClipIDs.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    func moveSelection(_ draggedID: Clip.ID, before targetID: Clip.ID) {
        guard draggedID != targetID,
              let sourceIndex = selectedClipIDs.firstIndex(of: draggedID),
              let targetIndex = selectedClipIDs.firstIndex(of: targetID) else { return }
        selectedClipIDs.remove(at: sourceIndex)
        let adjustedTarget = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        selectedClipIDs.insert(draggedID, at: adjustedTarget)
    }

    func selectCategory(_ category: ClipboardCategory) {
        selectedCategory = category
    }

    func togglePinnedCategory() {
        selectedCategory = selectedCategory == .pinned ? .history : .pinned
    }

    func toggleCardDensity() {
        usesCompactCards.toggle()
    }

    func copy(_ item: Clip) {
        withAuthorizedClips(ids: [item.id], reason: "Copy this hidden clipboard item") { model, clips in
            guard let clip = clips.first, model.pasteboardService.copy(clip.value) else { return }
            model.showCopiedFeedback(for: clip.id)
        }
    }

    func performPrimaryAction(_ item: Clip) {
        switch settings.defaultAction {
        case .paste:
            paste(item)
        case .copy:
            copyUsingCoordinator(item)
        case .preview:
            openPreview(item)
        }
    }

    func paste(_ item: Clip, plainTextOnly: Bool = false) {
        guard !isPasteRunning else { return }
        let target = targetProvider?.targetApplication()
        withAuthorizedClips(ids: [item.id], reason: "Paste this hidden clipboard item") { model, clips in
            guard let clip = clips.first else { return }
            model.performPaste(clip, to: target, plainTextOnly: plainTextOnly)
        }
    }

    private func performPaste(
        _ item: Clip, to target: NSRunningApplication?, plainTextOnly: Bool,
        sourceIDs: [Clip.ID]? = nil
    ) {
        guard !isPasteRunning else { return }
        guard let pasteCoordinator else {
            guard pasteboardService.copy(item.value) else { return }
            showCopiedFeedback(for: item.id)
            pasteOutcome = .copiedOnly
            return
        }
        isPasteRunning = true
        let version = clipVersions[item.id]
        let sourceVersions = (sourceIDs ?? [item.id]).compactMap { id in clipVersions[id].map { (id, $0) } }
        pasteTask?.cancel()
        pasteTask = Task { @MainActor [weak self, pasteCoordinator, repository] in
            guard !Task.isCancelled else { return }
            guard self?.canUseSourceVersions(sourceVersions) == true else {
                self?.isPasteRunning = false
                return
            }
            let outcome = await pasteCoordinator.paste(item, to: target, plainTextOnly: plainTextOnly)
            guard !Task.isCancelled, let self else { return }
            self.pasteOutcome = outcome
            self.isPasteRunning = false
            if outcome == .pasted, let version, self.clipVersions[item.id] == version {
                var updated = item
                updated.lastPastedAt = Date()
                updated.pasteCount += 1
                try? await repository.replace(updated)
                if self.clipVersions[item.id] == version { self.acceptCapturedClip(updated) }
            }
        }
    }

    func copyUsingCoordinator(_ item: Clip, plainTextOnly: Bool = false) {
        guard !isPasteRunning else { return }
        withAuthorizedClips(ids: [item.id], reason: "Copy this hidden clipboard item") { model, clips in
            guard let clip = clips.first else { return }
            guard let pasteCoordinator = model.pasteCoordinator else {
                guard model.pasteboardService.copy(clip.value) else { return }
                model.showCopiedFeedback(for: clip.id)
                return
            }
            model.isPasteRunning = true
            let version = model.clipVersions[clip.id]
            model.pasteTask?.cancel()
            model.pasteTask = Task { @MainActor [weak model, pasteCoordinator] in
                guard !Task.isCancelled else { return }
                guard let version, model?.canUseSourceVersions([(clip.id, version)]) == true else {
                    model?.isPasteRunning = false
                    return
                }
                let outcome = await pasteCoordinator.copy(clip, plainTextOnly: plainTextOnly)
                guard !Task.isCancelled, let model else { return }
                model.isPasteRunning = false
                model.pasteOutcome = outcome
                if case .failed = outcome { return }
                model.showCopiedFeedback(for: clip.id)
            }
        }
    }

    func pasteSelectedCombined() {
        guard !isPasteRunning else { return }
        let target = targetProvider?.targetApplication()
        let separator = multiPasteSeparator
        let format = multiPasteOutputFormat
        let custom = customSeparator
        withAuthorizedClips(ids: selectedClipIDs, reason: "Paste the selected hidden clipboard items") { model, clips in
            let value = MultiPasteComposer().combine(
                clips: clips, separator: separator, outputFormat: format, customSeparator: custom
            )
            guard !value.isEmpty else { return }
            let combined = Clip(
                contentType: .clipGroup, plainText: value, byteSize: Int64(value.utf8.count),
                contentHash: "combined:\(value.hashValue)", isSensitive: clips.contains(where: \.isSensitive)
            )
            model.performPaste(combined, to: target, plainTextOnly: format != .preserveFormatting, sourceIDs: clips.map(\.id))
        }
    }

    func startQueueMode() {
        queue.start(with: selectedClips)
    }

    func pasteNextQueueItem() {
        guard !isPasteRunning, let id = queue.currentClipID else { return }
        let target = targetProvider?.targetApplication()
        withAuthorizedClips(ids: [id], reason: "Paste this hidden clipboard item") { model, clips in
            guard model.queue.currentClipID == id, let clip = clips.first else { return }
            model.performPaste(clip, to: target, plainTextOnly: false)
            _ = model.queue.advance()
        }
    }

    func previousQueueItem() { queue.movePrevious() }
    func skipQueueItem() { queue.skip() }
    func restartQueue() { queue.restart() }
    func cancelQueue() { queue.cancel() }

    func toggleFavorite(_ item: Clip) {
        guard var updated = storedItems.first(where: { $0.id == item.id }) else { return }
        updated.isFavorite.toggle()
        updated.updatedAt = Date()
        persistUpdatedClip(updated)
    }

    func togglePinned(_ item: Clip) {
        guard var updated = storedItems.first(where: { $0.id == item.id }) else { return }
        updated.isPinned.toggle()
        updated.updatedAt = Date()
        persistUpdatedClip(updated)
    }

    func delete(_ item: Clip) {
        if pendingAuthorizationClipIDs.contains(item.id) { cancelClipboardAuthorization() }
        storedItems.removeAll { $0.id == item.id }
        clipVersions.removeValue(forKey: item.id)
        revealGrants.removeValue(forKey: item.id)
        if previewedClipID == item.id { closePreview() }
        selectedClipIDs.removeAll { $0 == item.id }
        Task { [repository] in try? await repository.delete(ids: [item.id]) }
    }

    func selectNext(delta: Int) {
        let visible = filteredItems
        guard !visible.isEmpty else { selectedClipID = nil; return }
        let current = selectedClipID.flatMap { id in visible.firstIndex { $0.id == id } } ?? 0
        let next = min(max(0, current + delta), visible.count - 1)
        selectedClipID = visible[next].id
    }

    func setSelectedClip(_ clip: Clip) {
        selectedClipID = clip.id
    }

    func requestLibrary() { onOpenLibrary?() }
    func requestSettings(pane: SettingsPane? = nil) { onOpenSettings?(pane) }
    func requestQuickPaste() { onOpenQuickPaste?() }

    func toggleCapture() {
        settings.captureEnabled.toggle()
    }

    func clearHistoryPreservingProtected() {
        authorizeOperation(reason: "Clear clipboard history", requiresEnrollment: false) { model in
            let deletedIDs = Set(model.storedItems.filter { !($0.isFavorite || $0.isPinned || $0.isManuallySaved) }.map(\.id))
            model.storedItems.removeAll { deletedIDs.contains($0.id) }
            model.clipVersions = model.clipVersions.filter { !deletedIDs.contains($0.key) }
            model.revealGrants = model.revealGrants.filter { !deletedIDs.contains($0.key) }
            model.selectedClipIDs.removeAll()
            model.queue.cancel()
            if let id = model.previewedClipID, deletedIDs.contains(id) { model.closePreview() }
            Task { [repository = model.repository] in
                try? await repository.delete(ids: deletedIDs)
            }
        }
    }

    func isClipLocked(_ clip: Clip) -> Bool {
        guard let current = storedItems.first(where: { $0.id == clip.id }) else { return clip.isSensitive }
        return isStoredClipLocked(current)
    }

    private func isStoredClipLocked(_ current: Clip) -> Bool {
        guard current.isSensitive else { return false }
        guard let grant = revealGrants[current.id], grant.version == clipVersions[current.id] else { return true }
        return accessClock() >= grant.expiresAt
    }

    func reveal(_ clip: Clip) {
        withAuthorizedClips(ids: [clip.id], reason: "Reveal this hidden clipboard item") { _, _ in }
    }

    func canDrag(_ clip: Clip) -> Bool {
        !isClipLocked(clip) && storedItems.first(where: { $0.id == clip.id })?.isDraggable == true
    }

    /// Recheck at drag creation, so an expired grant cannot export a previously rendered card.
    func dragItemProvider(for clip: Clip) -> NSItemProvider {
        guard canDrag(clip), let current = storedItems.first(where: { $0.id == clip.id }) else {
            return NSItemProvider()
        }
        beginDragOut()
        return current.dragItemProvider()
    }

    func lockSensitiveClips(cancelPending: Bool = true) {
        if cancelPending { cancelClipboardAuthorization() }
        revealExpiryTask?.cancel()
        revealGrants.removeAll()
        redactCapturePeekIfNeeded()
    }

    func cancelClipboardAuthorization() {
        let wasPending = pendingAuthorizationID != nil
        pendingAuthorizationID = nil
        pendingAuthorizationClipIDs.removeAll()
        isAuthorizingClipboard = false
        if wasPending { faceAuthorizer?.cancelAuthorization() }
    }

    /// Timer delivery is only a redraw aid. All readers and exporters also check the clock.
    func expireSensitiveReveals() {
        let now = accessClock()
        revealGrants = revealGrants.filter { $0.value.expiresAt > now && $0.value.version == clipVersions[$0.key] }
        redactCapturePeekIfNeeded()
        scheduleRevealExpiry()
    }

    private func presentationClip(_ clip: Clip) -> Clip {
        guard isStoredClipLocked(clip) else { return clip }
        return Clip(
            id: clip.id, createdAt: clip.createdAt, updatedAt: clip.updatedAt,
            lastCopiedAt: clip.lastCopiedAt, contentType: .generic,
            plainText: "Hidden clipboard item", searchableText: "",
            sourceApplicationName: "Face Check required", contentHash: "",
            copyCount: 0, pasteCount: 0, isFavorite: clip.isFavorite, isPinned: clip.isPinned,
            isSensitive: true, isManuallySaved: clip.isManuallySaved
        )
    }

    private func withAuthorizedClips(
        ids: [Clip.ID], reason: String,
        operation: @escaping @MainActor (NotchViewModel, [Clip]) -> Void
    ) {
        guard !ids.isEmpty, !isAuthorizingClipboard else { return }
        let clips = ids.compactMap { id in storedItems.first { $0.id == id } }
        guard clips.count == ids.count else { return }
        guard clips.contains(where: isStoredClipLocked) else {
            operation(self, clips)
            return
        }
        let versions = ids.compactMap { clipVersions[$0] }
        guard versions.count == ids.count else { return }
        authorizeOperation(reason: reason, requiresEnrollment: true, clipIDs: Set(ids)) { model in
            guard zip(ids, versions).allSatisfy({ model.clipVersions[$0.0] == $0.1 }) else { return }
            let current = ids.compactMap { id in model.storedItems.first { $0.id == id } }
            guard current.count == ids.count else { return }
            let expiry = model.accessClock() + model.revealDuration
            for clip in current where clip.isSensitive {
                guard let version = model.clipVersions[clip.id] else { continue }
                model.revealGrants[clip.id] = RevealGrant(version: version, expiresAt: expiry)
            }
            model.scheduleRevealExpiry()
            // A zero-duration grant is never permission to export.
            guard !current.contains(where: model.isStoredClipLocked) else { return }
            operation(model, current)
        }
    }

    private func authorizeOperation(
        reason: String, requiresEnrollment: Bool, clipIDs: Set<Clip.ID> = [],
        operation: @escaping @MainActor (NotchViewModel) -> Void
    ) {
        guard !isAuthorizingClipboard, let faceAuthorizer else { return }
        let id = UUID()
        pendingAuthorizationID = id
        pendingAuthorizationClipIDs = clipIDs
        isAuthorizingClipboard = true
        faceAuthorizer.authorize(reason: reason, requiresEnrollment: requiresEnrollment) { [weak self] allowed in
            guard let self, self.pendingAuthorizationID == id else { return }
            self.pendingAuthorizationID = nil
            self.pendingAuthorizationClipIDs.removeAll()
            self.isAuthorizingClipboard = false
            guard allowed else { return }
            operation(self)
        }
    }

    private func canUseSourceVersions(_ versions: [(Clip.ID, UUID)]) -> Bool {
        !versions.isEmpty && versions.allSatisfy { id, version in
            guard clipVersions[id] == version, let clip = storedItems.first(where: { $0.id == id }) else { return false }
            return !isStoredClipLocked(clip)
        }
    }

    private func scheduleRevealExpiry() {
        revealExpiryTask?.cancel()
        guard let nextExpiry = revealGrants.values.map(\.expiresAt).min() else { return }
        let delay = max(0.001, nextExpiry - accessClock())
        revealExpiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.expireSensitiveReveals()
        }
    }

    private func redactCapturePeekIfNeeded() {
        guard let id = peekedClipID, let clip = storedItems.first(where: { $0.id == id }),
              isClipLocked(clip), var peek = currentSneakPeek else { return }
        peek.title = "Hidden clipboard item"
        peek.systemImage = "lock.fill"
        currentSneakPeek = peek
    }

    /// Give a closed activity the island without carrying an open tab's transient state.
    func collapseForFaceCheck() {
        cancelPendingTimers()
        dragOutTask?.cancel()
        holdReasons.removeAll()
        gestureProgress = 0
        isHovering = false
        previewedClipID = nil
        peekedClipID = nil
        currentSneakPeek = nil
        let next: NotchState = !settings.notchEnabled ? .disabled
            : (fullscreenProvider?() == true ? .retractedForFullscreen : .idle)
        stateMachine = NotchStateMachine(initialState: next)
        state = next
        onStateChange?(next)
    }

    func escape() {
        if pendingAuthorizationID == nil, activityCenter.activeActivity?.activityID == "faceCheck" {
            faceAuthorizer?.cancelAuthorization()
        }
        cancelClipboardAuthorization()
        let previous = state
        transition(.escape)
        if previous == .previewing { previewedClipID = nil }
        if previous == .multiSelecting { selectedClipIDs.removeAll() }
        if previous == .peeking { peekTask?.cancel() }
        if state == .closing {
            dropHoverAfterClose()
            scheduleCloseAnimationCompletion()
        }
    }

    func setNotchEnabled(_ enabled: Bool) {
        settings.notchEnabled = enabled
        transition(enabled ? .enable : .disable)
        if enabled, fullscreenProvider?() == true {
            transition(.fullscreenEntered)
        }
    }

    /// Retracts the island for a fullscreen app, or restores it. Calls that would not change
    /// anything are ignored so they cannot disturb timers that are mid-flight.
    func setFullscreen(_ fullscreen: Bool) {
        let retracted = state == .retractedForFullscreen
        guard fullscreen != retracted else { return }
        cancelPendingTimers()
        if fullscreen {
            isHovering = false
            gestureProgress = 0
            if state == .previewing { previewedClipID = nil }
            if state == .multiSelecting { selectedClipIDs.removeAll() }
            if state == .peeking { peekedClipID = nil; currentSneakPeek = nil }
        }
        transition(fullscreen ? .fullscreenEntered : .fullscreenExited)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    // Compatibility hooks retained until all callers are on state transitions.
    func setExpandedContentVisible(_: Bool) {}
    func finishCollapsePresentation() { transition(.closeAnimationElapsed) }

    private func selectLiveActivityTabIfNeeded() {
        guard let tab = liveActivityTabProvider?(), availableTabs.contains(tab) else { return }
        selectTab(tab)
    }

    private func cancelPendingTimers() {
        hoverTask?.cancel()
        closeTask?.cancel()
        closeAnimationTask?.cancel()
        peekTask?.cancel()
    }

    private func scheduleDwell() {
        hoverTask?.cancel()
        let delay = settings.hoverDelayMilliseconds
        hoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let self, self.pointerIsInside,
                  self.activityCenter.activeActivity?.suppressesAutomaticOpen != true else { return }
            self.selectLiveActivityTabIfNeeded()
            self.transition(.dwellElapsed)
        }
    }

    /// After the pointer leaves, wait a short grace period, drop the hover swell and, when
    /// nothing holds the shelf open, start the close animation. A brief brush outside the
    /// notch therefore neither collapses the swell nor interrupts an armed dwell.
    private func scheduleCloseIfAllowed() {
        closeTask?.cancel()
        let delay = settings.closeDelayMilliseconds
        closeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let self, !self.pointerIsInside, !self.isHeaderPopoverActive else { return }
            self.isHovering = false
            // Dropping the swell re-measures the island; the pointer may have been found again.
            guard !Task.isCancelled, !self.pointerIsInside else { return }
            if self.state == .hoverArmed {
                self.transition(.pointerExited)
                return
            }
            guard self.state.isVisible, !self.state.preventsAutomaticClose else { return }
            guard self.transition(.closeDelayElapsed).to == .closing else { return }
            self.scheduleCloseAnimationCompletion()
        }
    }

    private func scheduleCloseAnimationCompletion() {
        closeAnimationTask?.cancel()
        let duration = closeAnimationDuration
        closeAnimationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.transition(.closeAnimationElapsed)
        }
    }

    /// The close spring should own the collapse; the hover swell is released one turn later
    /// so its bouncier curve does not take over the same frame change.
    private func dropHoverAfterClose() {
        Task { @MainActor [weak self] in
            guard let self, !self.pointerIsInside || !self.state.isCollapsed else { return }
            self.isHovering = false
        }
    }

    private func triggerHaptic() {
        guard settings.hapticsEnabled else { return }
        let now = Date()
        guard now.timeIntervalSince(lastHapticTime) > 0.3 else { return }
        lastHapticTime = now
        haptics.perform()
    }

    @discardableResult
    private func transition(_ event: NotchEvent) -> NotchTransition {
        let result = stateMachine.send(event)
        guard result.wasAccepted else { return result }
        if result.from != result.to {
            gestureProgress = 0
            if result.from == .closing { closeAnimationTask?.cancel() }
        }
        state = result.to
        if result.from == .peeking, result.to != .peeking {
            peekedClipID = nil
            currentSneakPeek = nil
        }
        if result.to == .idle, result.from == .closing, !settings.openLastTab {
            normalizeSelectedTab(resetToFirst: true)
        }
        onStateChange?(result.to)
        return result
    }

    private func showCopiedFeedback(for id: Clip.ID) {
        copiedFeedbackTask?.cancel()
        copiedItemID = id
        copiedFeedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1_100))
            guard !Task.isCancelled else { return }
            self?.copiedItemID = nil
        }
    }

    private func persistUpdatedClip(_ clip: Clip) {
        acceptCapturedClip(clip)
        Task { [repository] in try? await repository.replace(clip) }
    }

    private func matchesSelectedCategory(_ item: Clip) -> Bool {
        matchesCategory(item, category: selectedCategory)
    }

    private func matchesCategory(_ item: Clip, category: ClipboardCategory) -> Bool {
        if isStoredClipLocked(item) {
            return switch category {
            case .history, .all: true
            case .favorites: item.isFavorite
            case .pinned: item.isPinned
            default: false
            }
        }
        return switch category {
        case .history, .all: true
        case .favorites: item.isFavorite
        case .pinned: item.isPinned
        case .text: [.plainText, .multipleParagraphs, .richText, .html, .email, .phoneNumber].contains(item.contentType)
        case .images: [.image, .gif, .svg, .screenshot, .video].contains(item.contentType)
        case .files: [.file, .folder, .multipleFiles, .pdf].contains(item.contentType)
        case .links: item.contentType == .url
        case .code: [.code, .json, .shellCommand].contains(item.contentType)
        case .colors: item.contentType == .color
        case .screenshots: item.contentType == .screenshot
        }
    }

    private func matchesSearch(_ item: Clip) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }
        guard !isStoredClipLocked(item) else { return false }
        let searchable = [
            item.title,
            item.searchableText,
            item.ocrText,
            item.sourceApplicationName,
            item.note,
            item.inlineShortcut
        ].compactMap { $0 }.joined(separator: "\n")
        return searchable.localizedCaseInsensitiveContains(trimmedQuery)
    }
}
