import AppKit
import Foundation
import Testing
@testable import Notchy

@MainActor
struct ClipboardFaceAuthorizationTests {
    @Test
    func lockedItemsRedactEveryPresentationAndDoNotMatchSecretSearches() {
        let clip = hiddenClip()
        let model = makeModel(items: [clip])
        let display = model.items[0]

        #expect(display.id == clip.id)
        #expect(display.title == "Hidden clipboard item")
        #expect(display.contentType == .generic)
        #expect(display.searchableText.isEmpty)
        #expect(display.contentHash.isEmpty)
        #expect(display.ocrText == nil)
        #expect(display.note == nil)
        #expect(display.inlineShortcut == nil)
        #expect(display.urlValue == nil)
        #expect(display.originalFileURLs.isEmpty)
        #expect(display.copiedFilePaths.isEmpty)
        #expect(display.imagePayloadPath == nil)
        #expect(display.richTextPayloadPath == nil)
        #expect(display.htmlPayloadPath == nil)
        #expect(display.thumbnailPath == nil)
        #expect(display.videoPath == nil)
        #expect(display.byteSize == 0)
        #expect(model.count(for: .links) == 0)
        #expect(model.count(for: .history) == 1)
        model.query = "private.example"
        #expect(model.filteredItems.isEmpty)
        model.query = "private note"
        #expect(model.filteredItems.isEmpty)
        model.query = "private source"
        #expect(model.filteredItems.isEmpty)
        model.setSelectedClip(clip)
        model.toggleSelection(clip)
        #expect(model.selectedClip?.title == "Hidden clipboard item")
        #expect(model.selectedClips.first?.value == "Hidden clipboard item")
    }

    @Test
    func capturePeekNeverShowsLockedContent() {
        let clip = hiddenClip()
        let model = makeModel(items: [clip])
        model.presentCapturePeek(for: clip)
        #expect(model.currentSneakPeek?.title == "Hidden clipboard item")
        #expect(model.peekedClip?.urlValue == nil)
    }

    @Test
    func missingAuthorizerFailsClosedForReadsAndDestruction() {
        let clip = hiddenClip()
        let pasteboard = GatePasteboardSpy()
        let model = makeModel(items: [clip], pasteboard: pasteboard)
        model.copy(clip)
        model.paste(clip)
        model.openPreview(clip)
        model.clearHistoryPreservingProtected()
        #expect(pasteboard.values.isEmpty)
        #expect(model.previewedClip == nil)
        #expect(model.items.count == 1)
        #expect(!model.canDrag(clip))
        #expect(model.dragItemProvider(for: clip).registeredTypeIdentifiers.isEmpty)
    }

    @Test
    func failureCancellationAndDuplicateCompletionCannotWrite() {
        let clip = hiddenClip()
        let authorizer = GateAuthorizerSpy()
        let pasteboard = GatePasteboardSpy()
        let model = makeModel(items: [clip], pasteboard: pasteboard, authorizer: authorizer)
        model.copy(clip)
        model.paste(clip)
        #expect(authorizer.requests.count == 1)
        #expect(authorizer.requests[0].requiresEnrollment)
        #expect(pasteboard.values.isEmpty)
        authorizer.complete(0, allowed: false)
        authorizer.complete(0, allowed: true)
        #expect(pasteboard.values.isEmpty)

        model.copy(clip)
        model.cancelClipboardAuthorization()
        authorizer.complete(1, allowed: true)
        #expect(pasteboard.values.isEmpty)

        model.copy(clip)
        authorizer.complete(2, allowed: true)
        authorizer.complete(2, allowed: true)
        #expect(pasteboard.values == [clip.value])
        #expect(model.items[0].value == clip.value)
    }

    @Test
    func replacedOrDeletedItemsCannotUseAnOutstandingApproval() {
        let clip = hiddenClip()
        let authorizer = GateAuthorizerSpy()
        let pasteboard = GatePasteboardSpy()
        let model = makeModel(items: [clip], pasteboard: pasteboard, authorizer: authorizer)
        model.copy(clip)
        var changed = clip
        changed.plainText = "replacement secret"
        // Even a reused content hash cannot carry permission to changed content.
        model.acceptCapturedClip(changed)
        authorizer.complete(0, allowed: true)
        #expect(pasteboard.values.isEmpty)
        #expect(model.isClipLocked(changed))
        model.copy(changed)
        model.delete(changed)
        authorizer.complete(1, allowed: true)
        #expect(pasteboard.values.isEmpty)
        #expect(model.items.isEmpty)
    }

    @Test
    func revealExpiresAtTheClockBoundaryEvenBeforeItsTimerRuns() {
        let clip = hiddenClip()
        let clock = GateClock()
        let authorizer = GateAuthorizerSpy()
        let pasteboard = GatePasteboardSpy()
        let model = makeModel(items: [clip], pasteboard: pasteboard, authorizer: authorizer, clock: clock)
        model.reveal(clip)
        authorizer.complete(0, allowed: true)
        #expect(model.items[0].value == clip.value)
        #expect(model.canDrag(clip))
        clock.now += 60
        #expect(model.items[0].title == "Hidden clipboard item")
        #expect(!model.canDrag(clip))
        #expect(model.dragItemProvider(for: clip).registeredTypeIdentifiers.isEmpty)
        model.copy(clip)
        #expect(authorizer.requests.count == 2)
        #expect(pasteboard.values.isEmpty)
        model.expireSensitiveReveals()
        #expect(model.isClipLocked(clip))
    }

    @Test
    func explicitLockRevokesRevealsAndPendingApprovals() {
        let clip = hiddenClip()
        let authorizer = GateAuthorizerSpy()
        let model = makeModel(items: [clip], authorizer: authorizer)
        model.reveal(clip)
        authorizer.complete(0, allowed: true)
        #expect(!model.isClipLocked(clip))
        model.lockSensitiveClips()
        #expect(model.isClipLocked(clip))
        model.reveal(clip)
        model.lockSensitiveClips()
        authorizer.complete(1, allowed: true)
        #expect(model.isClipLocked(clip))
        #expect(authorizer.cancellationCount == 1)
    }

    @Test
    func appDeactivationRevokesARevealWithoutCancellingAnExplicitPasteCheck() {
        let revealed = hiddenClip()
        var pending = hiddenClip()
        pending.contentHash = "another private hash"
        let authorizer = GateAuthorizerSpy()
        let pasteboard = GatePasteboardSpy()
        let model = makeModel(items: [revealed, pending], pasteboard: pasteboard, authorizer: authorizer)
        model.reveal(revealed)
        authorizer.complete(0, allowed: true)
        model.paste(pending)

        // The application-deactivation observer uses this policy; a session lock uses the default.
        model.lockSensitiveClips(cancelPending: false)
        #expect(model.isClipLocked(revealed))
        #expect(model.isAuthorizingClipboard)
        #expect(authorizer.cancellationCount == 0)
        authorizer.complete(1, allowed: true)
        #expect(pasteboard.values == [pending.value])
        #expect(model.isClipLocked(revealed))
    }

    @Test
    func clearHistoryRequiresFreshApprovalAndKeepsProtectedItems() async {
        let clip = hiddenClip()
        var favorite = Clip(contentType: .plainText, plainText: "keep", contentHash: "favorite")
        favorite.isFavorite = true
        let repository = InMemoryClipRepository(clips: [clip, favorite])
        let authorizer = GateAuthorizerSpy()
        let model = makeModel(items: [clip, favorite], repository: repository, authorizer: authorizer)
        model.reveal(clip)
        authorizer.complete(0, allowed: true)
        model.clearHistoryPreservingProtected()
        #expect(authorizer.requests.count == 2)
        #expect(!authorizer.requests[1].requiresEnrollment)
        #expect(model.items.count == 2)
        authorizer.complete(1, allowed: false)
        #expect(model.items.count == 2)
        model.clearHistoryPreservingProtected()
        authorizer.complete(2, allowed: true)
        authorizer.complete(2, allowed: true)
        #expect(model.items.map(\.id) == [favorite.id])
        for _ in 0..<50 {
            if await repository.fetchAll(limit: nil).count == 1 { break }
            await Task.yield()
        }
        #expect(await repository.fetchAll(limit: nil).map(\.id) == [favorite.id])
    }

    @Test
    func combinedPasteChecksAllSelectedClipsBeforeComposing() {
        let clip = hiddenClip()
        let publicClip = Clip(contentType: .plainText, plainText: "public", contentHash: "public")
        let authorizer = GateAuthorizerSpy()
        let pasteboard = GatePasteboardSpy()
        let model = makeModel(items: [publicClip, clip], pasteboard: pasteboard, authorizer: authorizer)
        model.toggleSelection(publicClip)
        model.toggleSelection(clip)
        model.pasteSelectedCombined()
        #expect(pasteboard.values.isEmpty)
        authorizer.complete(0, allowed: true)
        #expect(pasteboard.values.count == 1)
        #expect(pasteboard.values[0].contains(clip.value))
        #expect(pasteboard.values[0].contains(publicClip.value))
        #expect(!pasteboard.values[0].contains("Hidden clipboard item"))
    }

    @Test
    func queueDoesNotAdvanceWhenItsCheckFailsOrIsSuperseded() {
        let first = hiddenClip()
        let second = Clip(contentType: .plainText, plainText: "second", contentHash: "second")
        let authorizer = GateAuthorizerSpy()
        let pasteboard = GatePasteboardSpy()
        let model = makeModel(items: [first, second], pasteboard: pasteboard, authorizer: authorizer)
        model.toggleSelection(first)
        model.toggleSelection(second)
        model.startQueueMode()
        model.pasteNextQueueItem()
        authorizer.complete(0, allowed: false)
        #expect(model.queue.currentClipID == first.id)
        model.pasteNextQueueItem()
        model.skipQueueItem()
        authorizer.complete(1, allowed: true)
        #expect(pasteboard.values.isEmpty)
        #expect(model.queue.currentClipID == second.id)
    }

    @Test
    func anOutstandingAuthorizationDoesNotKeepTheModelAlive() {
        let clip = hiddenClip()
        let authorizer = GateAuthorizerSpy()
        let pasteboard = GatePasteboardSpy()
        weak var released: NotchViewModel?
        do {
            let model = makeModel(items: [clip], pasteboard: pasteboard, authorizer: authorizer)
            released = model
            model.copy(clip)
        }
        #expect(released == nil)
        authorizer.complete(0, allowed: true)
        #expect(pasteboard.values.isEmpty)
    }

    @Test
    func asyncCopyRechecksTheGrantBeforeStartingAnExport() async {
        let clip = hiddenClip()
        let clock = GateClock()
        let authorizer = GateAuthorizerSpy()
        let coordinator = GatePasteCoordinatorSpy()
        let model = makeModel(items: [clip], coordinator: coordinator, authorizer: authorizer, clock: clock)
        model.copyUsingCoordinator(clip)
        authorizer.complete(0, allowed: true)
        clock.now += 60
        for _ in 0..<50 {
            if !model.isPasteRunning { break }
            await Task.yield()
        }
        #expect(!model.isPasteRunning)
        #expect(coordinator.copied.isEmpty)
    }

    @Test
    func faceCheckCollapseReleasesOpenPresentationWithoutChangingTabs() {
        let clip = Clip(contentType: .plainText, plainText: "public", contentHash: "public")
        let model = makeModel(items: [clip])
        model.openPinned()
        model.selectTab(.clipboard)
        model.holdOpen(reason: "popover")
        model.openPreview(clip)
        model.collapseForFaceCheck()
        #expect(model.state == .idle)
        #expect(model.previewedClip == nil)
        #expect(model.holdReasons.isEmpty)
        #expect(model.selectedTab == .clipboard)
    }

    private func makeModel(
        items: [Clip], repository: (any ClipRepository)? = nil,
        pasteboard: GatePasteboardSpy = GatePasteboardSpy(),
        coordinator: GatePasteCoordinatorSpy? = nil,
        authorizer: GateAuthorizerSpy? = nil, clock: GateClock = GateClock()
    ) -> NotchViewModel {
        let defaults = UserDefaults(suiteName: "ClipboardFaceAuthorizationTests.\(UUID().uuidString)")!
        return NotchViewModel(
            items: items, repository: repository, pasteboardService: pasteboard, pasteCoordinator: coordinator,
            activityCenter: IslandActivityCenter(), settings: UserSettings(defaults: defaults),
            faceAuthorizer: authorizer, accessClock: { clock.now }
        )
    }

    private func hiddenClip() -> Clip {
        Clip(
            contentType: .url, plainText: "private token", searchableText: "private searchable",
            richTextPayloadPath: "private.rtf", htmlPayloadPath: "private.html",
            imagePayloadPath: "private.png", thumbnailPath: "private-thumb.png", videoPath: "private.mov",
            originalFileURLs: [URL(fileURLWithPath: "/private/document")], copiedFilePaths: ["/private/document"],
            urlValue: URL(string: "https://private.example/secret"), urlTitle: "private title",
            ocrText: "private OCR", sourceApplicationName: "private source", byteSize: 123,
            contentHash: "private hash", isSensitive: true, note: "private note", inlineShortcut: "private shortcut"
        )
    }
}

@MainActor
private final class GateClock {
    var now: TimeInterval = 100
}

@MainActor
private final class GateAuthorizerSpy: FaceCheckAuthorizing {
    struct Request {
        let reason: String
        let requiresEnrollment: Bool
        let completion: @MainActor (Bool) -> Void
    }
    var requests: [Request] = []
    var cancellationCount = 0

    func authorize(reason: String, requiresEnrollment: Bool, completion: @escaping @MainActor (Bool) -> Void) {
        requests.append(Request(reason: reason, requiresEnrollment: requiresEnrollment, completion: completion))
    }

    func complete(_ index: Int, allowed: Bool) { requests[index].completion(allowed) }
    func cancelAuthorization() { cancellationCount += 1 }
}

@MainActor
private final class GatePasteboardSpy: PasteboardWriting {
    var values: [String] = []
    func copy(_ value: String) -> Bool {
        values.append(value)
        return true
    }
}

@MainActor
private final class GatePasteCoordinatorSpy: PasteCoordinating {
    var copied: [Clip] = []

    func copy(_ clip: Clip, plainTextOnly: Bool) async -> PasteOutcome {
        copied.append(clip)
        return .copiedOnly
    }

    func paste(_ clip: Clip, to application: NSRunningApplication?, plainTextOnly: Bool) async -> PasteOutcome {
        copied.append(clip)
        return .pasted
    }
}
