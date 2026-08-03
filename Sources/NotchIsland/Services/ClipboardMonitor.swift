import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
protocol PasteboardSnapshotting: AnyObject {
    var changeCount: Int { get }
    func snapshot(maximumBytes: Int) -> ClipboardSnapshot?
}

@MainActor
final class SystemPasteboardSnapshotter: PasteboardSnapshotting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    func snapshot(maximumBytes: Int) -> ClipboardSnapshot? {
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let source = ClipboardSource(
            bundleIdentifier: sourceApp?.bundleIdentifier,
            applicationName: sourceApp?.localizedName
        )
        let fileURLs = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []

        let preferredTypes: [NSPasteboard.PasteboardType] = [
            .string,
            .rtf,
            .html,
            .png,
            .tiff,
            .pdf,
            .fileURL,
            .URL
        ]
        var representations: [PasteboardRepresentation] = []
        var totalBytes = 0

        for type in preferredTypes where pasteboard.types?.contains(type) == true {
            let data: Data?
            if type == .string, let string = pasteboard.string(forType: type) {
                data = Data(string.utf8)
            } else {
                data = pasteboard.data(forType: type)
            }
            guard let data, !data.isEmpty else { continue }
            totalBytes += data.count
            guard totalBytes <= maximumBytes else { break }
            representations.append(
                PasteboardRepresentation(typeIdentifier: type.rawValue, data: data)
            )
        }

        guard !representations.isEmpty || !fileURLs.isEmpty else { return nil }
        return ClipboardSnapshot(
            changeCount: pasteboard.changeCount,
            capturedAt: Date(),
            source: source,
            representations: representations,
            fileURLs: fileURLs
        )
    }
}

@MainActor
final class ClipboardMonitor {
    var onClipCaptured: ((Clip) -> Void)?
    var onSensitiveContentSkipped: ((Set<SensitiveContentReason>) -> Void)?
    var onCaptureError: ((Error) -> Void)?

    private let snapshotter: PasteboardSnapshotting
    private let normalizer: ClipboardNormalizer
    private let repository: any ClipRepository
    private let detector: SensitiveContentDetector
    private let policy: () -> CapturePolicy
    private var timer: Timer?
    private var lastChangeCount: Int
    private var internalChangeCounts: Set<Int> = []
    private var captureTask: Task<Void, Never>?

    init(
        snapshotter: PasteboardSnapshotting = SystemPasteboardSnapshotter(),
        normalizer: ClipboardNormalizer,
        repository: any ClipRepository,
        detector: SensitiveContentDetector = SensitiveContentDetector(),
        policy: @escaping () -> CapturePolicy
    ) {
        self.snapshotter = snapshotter
        self.normalizer = normalizer
        self.repository = repository
        self.detector = detector
        self.policy = policy
        lastChangeCount = snapshotter.changeCount
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = snapshotter.changeCount
        let timer = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        captureTask?.cancel()
        captureTask = nil
    }

    func markInternalWrite(changeCount: Int) {
        internalChangeCounts.insert(changeCount)
        if internalChangeCounts.count > 20 {
            internalChangeCounts = Set(internalChangeCounts.sorted().suffix(20))
        }
    }

    func captureCurrentManually() {
        captureIfAvailable(manual: true)
    }

    func poll() {
        let currentChangeCount = snapshotter.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        if internalChangeCounts.remove(currentChangeCount) != nil { return }
        captureIfAvailable(manual: false)
    }

    private func captureIfAvailable(manual: Bool) {
        let currentPolicy = policy()
        guard currentPolicy.isEnabled || manual else { return }
        guard !currentPolicy.manualCaptureOnly || manual else { return }
        guard let snapshot = snapshotter.snapshot(maximumBytes: currentPolicy.maximumPayloadBytes) else {
            return
        }
        if let bundleIdentifier = snapshot.source.bundleIdentifier,
           currentPolicy.ignoredApplicationBundleIdentifiers.contains(bundleIdentifier) {
            return
        }

        captureTask?.cancel()
        captureTask = Task { [weak self, normalizer, repository, detector] in
            do {
                guard var clip = try await normalizer.normalize(snapshot) else { return }
                guard !Task.isCancelled else { return }
                if currentPolicy.ignoredContentTypes.contains(clip.contentType) { return }

                let sensitiveResult = detector.inspect(clip.plainText ?? clip.searchableText)
                if sensitiveResult.isSensitive {
                    clip.isSensitive = true
                    clip.isLocalOnly = true
                    guard currentPolicy.saveSensitiveContent || manual else {
                        self?.onSensitiveContentSkipped?(sensitiveResult.reasons)
                        return
                    }
                }

                let saved = try await repository.save(
                    clip,
                    duplicateBehavior: currentPolicy.duplicateBehavior
                )
                guard !Task.isCancelled else { return }
                self?.onClipCaptured?(saved)
            } catch {
                self?.onCaptureError?(error)
            }
        }
    }
}
