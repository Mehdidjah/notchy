import AppKit
import Combine
import Foundation

@MainActor
final class NotchViewModel: ObservableObject {
    @Published private(set) var state: NotchState
    @Published private(set) var items: [Clip]
    @Published var query = ""
    @Published var selectedCategory: ClipboardCategory = .history
    @Published var usesCompactCards = false
    @Published private(set) var copiedItemID: Clip.ID?
    @Published private(set) var selectedClipIDs: [Clip.ID] = []
    @Published private(set) var previewedClipID: Clip.ID?
    @Published private(set) var selectedClipID: Clip.ID?
    @Published private(set) var captureErrorDescription: String?
    @Published var multiPasteSeparator: MultiPasteSeparator = .blankLine
    @Published var multiPasteOutputFormat: MultiPasteOutputFormat = .plainText
    @Published var customSeparator = ""
    @Published private(set) var pasteOutcome: PasteOutcome?
    @Published private(set) var isPasteRunning = false
    @Published private(set) var queue = SequentialPasteQueue()
    @Published private(set) var notchGeometry = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        topInset: 30,
        hardwareNotchWidth: 0,
        isHardwareNotch: false
    )

    var onStateChange: ((NotchState) -> Void)?
    var onOpenLibrary: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenQuickPaste: (() -> Void)?

    let settings: UserSettings
    private let repository: any ClipRepository
    private let pasteboardService: any PasteboardWriting
    private let pasteCoordinator: (any PasteCoordinating)?
    private weak var targetProvider: (any PasteTargetProviding)?
    private var stateMachine: NotchStateMachine
    private var pointerIsInside = false
    private var hoverTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var copiedFeedbackTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var pasteTask: Task<Void, Never>?

    init(
        items: [Clip] = [],
        repository: (any ClipRepository)? = nil,
        pasteboardService: any PasteboardWriting = PasteboardService(),
        pasteCoordinator: (any PasteCoordinating)? = nil,
        targetProvider: (any PasteTargetProviding)? = nil,
        settings: UserSettings = UserSettings()
    ) {
        #if DEBUG
        let previewMode = ProcessInfo.processInfo.arguments.contains("--expanded-preview")
        let initialItems = previewMode && items.isEmpty ? Clip.debugPreviewItems : items
        #else
        let previewMode = false
        let initialItems = items
        #endif
        self.items = initialItems
        self.repository = repository ?? InMemoryClipRepository(clips: initialItems)
        self.pasteboardService = pasteboardService
        self.pasteCoordinator = pasteCoordinator
        self.targetProvider = targetProvider
        self.settings = settings
        let initialState: NotchState = settings.notchEnabled
            ? (previewMode ? .pinnedOpen : .idle)
            : .disabled
        stateMachine = NotchStateMachine(initialState: initialState)
        state = initialState
    }

    var isExpanded: Bool { state.isVisible && state != .peeking && state != .closing }
    var showsExpandedContent: Bool { state.showsShelfContent }
    var usesExpandedShape: Bool { state.isVisible }
    var isPinnedOpen: Bool { state == .pinnedOpen }
    var isSelectionMode: Bool { state == .multiSelecting }

    var filteredItems: [Clip] {
        items.filter { item in
            matchesSelectedCategory(item) && matchesSearch(item)
        }
    }

    var previewedClip: Clip? {
        guard let previewedClipID else { return nil }
        return items.first { $0.id == previewedClipID }
    }

    var selectedClip: Clip? {
        guard let selectedClipID else { return filteredItems.first }
        return items.first { $0.id == selectedClipID }
    }

    var selectedClips: [Clip] {
        selectedClipIDs.compactMap { id in items.first { $0.id == id } }
    }

    func start() {
        loadTask?.cancel()
        loadTask = Task { [weak self, repository] in
            do {
                let stored = try await repository.fetchAll(limit: nil)
                guard !Task.isCancelled else { return }
                self?.items = stored
            } catch {
                self?.captureErrorDescription = error.localizedDescription
            }
        }
    }

    func acceptCapturedClip(_ clip: Clip) {
        if let index = items.firstIndex(where: { $0.id == clip.id || $0.contentHash == clip.contentHash }) {
            items[index] = clip
        } else {
            items.append(clip)
        }
        items.sort { $0.lastCopiedAt > $1.lastCopiedAt }
    }

    func reportCaptureError(_ error: Error) {
        captureErrorDescription = error.localizedDescription
    }

    func updateNotchGeometry(_ geometry: NotchGeometry) {
        notchGeometry = geometry
    }

    func count(for category: ClipboardCategory) -> Int {
        items.filter { matchesCategory($0, category: category) }.count
    }

    func setHovered(_ hovered: Bool) {
        hovered ? pointerEntered() : pointerExited()
    }

    func pointerEntered() {
        if state == .idle { targetProvider?.rememberFrontmostApplication() }
        pointerIsInside = true
        closeTask?.cancel()
        let transition = transition(.pointerEntered)
        if transition.to == .hoverArmed {
            scheduleDwell()
        }
    }

    func pointerExited() {
        pointerIsInside = false
        if state == .hoverArmed {
            hoverTask?.cancel()
            transition(.pointerExited)
            return
        }
        if state == .peeking {
            transition(.pointerExited)
            scheduleCloseAnimationCompletion()
            return
        }
        scheduleCloseIfAllowed()
    }

    func openPinned() {
        targetProvider?.rememberFrontmostApplication()
        hoverTask?.cancel()
        closeTask?.cancel()
        transition(.openPinned)
    }

    func togglePin() {
        closeTask?.cancel()
        transition(state == .pinnedOpen ? .unpin : .pin)
        if state == .expanded, !pointerIsInside { scheduleCloseIfAllowed() }
    }

    func setKeyboardFocus(_ focused: Bool) {
        transition(focused ? .focusSearch : .blurSearch)
        if !focused && !pointerIsInside { scheduleCloseIfAllowed() }
    }

    func openPreview(_ clip: Clip) {
        previewedClipID = clip.id
        selectedClipID = clip.id
        transition(.openPreview)
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
        guard pasteboardService.copy(item.value) else { return }
        showCopiedFeedback(for: item.id)
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
        guard let pasteCoordinator else {
            copy(item)
            pasteOutcome = .copiedOnly
            return
        }
        isPasteRunning = true
        let target = targetProvider?.targetApplication()
        pasteTask?.cancel()
        pasteTask = Task { @MainActor [weak self, pasteCoordinator, repository] in
            let outcome = await pasteCoordinator.paste(item, to: target, plainTextOnly: plainTextOnly)
            guard !Task.isCancelled, let self else { return }
            self.pasteOutcome = outcome
            self.isPasteRunning = false
            if outcome == .pasted {
                var updated = item
                updated.lastPastedAt = Date()
                updated.pasteCount += 1
                try? await repository.replace(updated)
                self.acceptCapturedClip(updated)
            }
        }
    }

    func copyUsingCoordinator(_ item: Clip, plainTextOnly: Bool = false) {
        guard let pasteCoordinator else { copy(item); return }
        pasteTask?.cancel()
        pasteTask = Task { @MainActor [weak self, pasteCoordinator] in
            let outcome = await pasteCoordinator.copy(item, plainTextOnly: plainTextOnly)
            guard !Task.isCancelled else { return }
            self?.pasteOutcome = outcome
            if case .failed = outcome {
                return
            }
            self?.showCopiedFeedback(for: item.id)
        }
    }

    func pasteSelectedCombined() {
        let value = MultiPasteComposer().combine(
            clips: selectedClips,
            separator: multiPasteSeparator,
            outputFormat: multiPasteOutputFormat,
            customSeparator: customSeparator
        )
        guard !value.isEmpty else { return }
        let combined = Clip(
            contentType: .clipGroup,
            plainText: value,
            searchableText: value,
            byteSize: Int64(value.utf8.count),
            contentHash: "combined:\(value.hashValue)",
            isManuallySaved: false,
            cardStyle: .dark
        )
        paste(combined, plainTextOnly: multiPasteOutputFormat != .preserveFormatting)
    }

    func startQueueMode() {
        queue.start(with: selectedClips)
    }

    func pasteNextQueueItem() {
        guard let id = queue.currentClipID,
              let clip = items.first(where: { $0.id == id }) else { return }
        paste(clip)
        _ = queue.advance()
    }

    func previousQueueItem() { queue.movePrevious() }
    func skipQueueItem() { queue.skip() }
    func restartQueue() { queue.restart() }
    func cancelQueue() { queue.cancel() }

    func toggleFavorite(_ item: Clip) {
        var updated = item
        updated.isFavorite.toggle()
        updated.updatedAt = Date()
        persistUpdatedClip(updated)
    }

    func togglePinned(_ item: Clip) {
        var updated = item
        updated.isPinned.toggle()
        updated.updatedAt = Date()
        persistUpdatedClip(updated)
    }

    func delete(_ item: Clip) {
        items.removeAll { $0.id == item.id }
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
    func requestSettings() { onOpenSettings?() }
    func requestQuickPaste() { onOpenQuickPaste?() }

    func toggleCapture() {
        settings.captureEnabled.toggle()
    }

    func clearHistoryPreservingProtected() {
        items.removeAll { !($0.isFavorite || $0.isPinned || $0.isManuallySaved) }
        selectedClipIDs.removeAll()
        Task { [repository] in
            try? await repository.clearHistory(preservingProtected: true)
        }
    }

    func escape() {
        let previous = state
        transition(.escape)
        if previous == .previewing { previewedClipID = nil }
        if previous == .multiSelecting { selectedClipIDs.removeAll() }
        if state == .closing { scheduleCloseAnimationCompletion() }
    }

    func setNotchEnabled(_ enabled: Bool) {
        settings.notchEnabled = enabled
        transition(enabled ? .enable : .disable)
    }

    func setFullscreen(_ fullscreen: Bool) {
        hoverTask?.cancel()
        closeTask?.cancel()
        transition(fullscreen ? .fullscreenEntered : .fullscreenExited)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    // Compatibility hooks retained until all callers are on state transitions.
    func setExpandedContentVisible(_: Bool) {}
    func finishCollapsePresentation() { transition(.closeAnimationElapsed) }

    private func scheduleDwell() {
        hoverTask?.cancel()
        let delay = settings.hoverDelayMilliseconds
        hoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let self, self.pointerIsInside else { return }
            self.transition(.dwellElapsed)
        }
    }

    private func scheduleCloseIfAllowed() {
        guard state.isVisible, !state.preventsAutomaticClose else { return }
        closeTask?.cancel()
        let delay = settings.closeDelayMilliseconds
        closeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let self, !self.pointerIsInside,
                  !self.state.preventsAutomaticClose else { return }
            guard self.transition(.closeDelayElapsed).to == .closing else { return }
            self.scheduleCloseAnimationCompletion()
        }
    }

    private func scheduleCloseAnimationCompletion() {
        closeTask?.cancel()
        closeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.transition(.closeAnimationElapsed)
        }
    }

    @discardableResult
    private func transition(_ event: NotchEvent) -> NotchTransition {
        let result = stateMachine.send(event)
        guard result.wasAccepted else { return result }
        state = result.to
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
        switch category {
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
