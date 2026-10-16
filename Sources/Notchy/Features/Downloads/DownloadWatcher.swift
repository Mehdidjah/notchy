import Combine
import SwiftUI

/// Watches ~/Downloads for browsers' partial files and publishes the state the download live
/// activity draws (Atoll's DownloadManager).
///
/// A download appearing after launch raises `isDownloading`. When nothing is being written any
/// more, a download whose destination received data shows the green checkmark for 2 s before
/// the activity closes; an abandoned one closes it at once. Folder reads happen on a utility
/// queue; every published change happens on the main actor.
@MainActor
final class DownloadWatcher: ObservableObject {
    static let shared = DownloadWatcher()

    @Published private(set) var isMonitoring = false
    @Published private(set) var isDownloading = false
    @Published private(set) var isCompleted = false
    /// Smoothed bytes per second across all downloads; nil until two samples exist.
    @Published private(set) var bytesPerSecond: Double?
    /// 0...1 when every running download publishes determinate progress, otherwise nil.
    @Published private(set) var fractionCompleted: Double?
    /// False when the Downloads folder could not be listed (for example, access denied).
    @Published private(set) var hasFolderAccess = true

    let settings: DownloadsSettings
    let directory: URL?

    private var tracker = DownloadTracker()
    private let queue = DispatchQueue(label: "Notchy.Downloads.Watcher", qos: .utility)
    private var source: DownloadsDirectorySource?
    /// Bumped on every start and stop, so a scan already in flight cannot land in a new run.
    private var session = 0
    private var speedSession = 0
    private var speedTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var completionTask: Task<Void, Never>?
    private var lastSpeedSample: DownloadSpeedSample?
    private var smoothedSpeed: Double?
    private let progressTracker = DownloadProgressTracker()
    private var cancellables: Set<AnyCancellable> = []

    /// How long the checkmark stays before the activity closes.
    static let completionHold: Duration = .seconds(2)
    static let speedInterval: Duration = .seconds(1)
    static let progressInterval: Duration = .milliseconds(250)

    init(
        settings: DownloadsSettings = .shared,
        directory: URL? = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    ) {
        self.settings = settings
        self.directory = directory
        settings.$enableDownloadDetection
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self, self.isFeatureStarted else { return }
                if enabled { self.startMonitoring() } else { self.stopMonitoring() }
            }
            .store(in: &cancellables)
    }

    /// Set by `start()`; the setting can only switch monitoring on while the feature runs.
    private var isFeatureStarted = false

    func start() {
        isFeatureStarted = true
        if settings.enableDownloadDetection { startMonitoring() }
    }

    func stop() {
        isFeatureStarted = false
        stopMonitoring()
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        guard source == nil, let directory else { return }
        session &+= 1
        let current = session
        tracker.reset()
        isDownloading = false
        isCompleted = false

        let source = DownloadsDirectorySource(directory: directory, queue: queue) { [weak self] in
            Self.scan(directory, session: current, into: self)
        }
        self.source = source
        isMonitoring = true
        progressTracker.start(directory: directory)
        // The baseline is queued before the source resumes, on the same serial queue, so it is
        // always the first listing delivered.
        queue.async { [weak self] in Self.scan(directory, session: current, into: self) }
        source?.resume()
    }

    private func stopMonitoring() {
        source?.cancel()
        source = nil
        session &+= 1
        tracker.reset()
        isMonitoring = false
        progressTracker.stop()
        closeImmediately()
    }

    /// Runs on `queue`.
    nonisolated private static func scan(_ directory: URL, session: Int, into watcher: DownloadWatcher?) {
        let listing = DownloadsFolderReader.listing(of: directory)
        DispatchQueue.main.async { [weak watcher] in
            MainActor.assumeIsolated {
                guard let watcher, watcher.session == session else { return }
                watcher.ingest(listing)
            }
        }
    }

    /// Applies one listing; `nil` means the folder could not be read.
    func ingest(_ listing: DownloadsFolderListing?) {
        guard let listing else {
            hasFolderAccess = false
            return
        }
        hasFolderAccess = true
        switch tracker.ingest(listing, isShowing: isDownloading, isShowingCompletion: isCompleted) {
        case .unchanged:
            break
        case .downloading:
            beginOrContinue()
        case .finished:
            finish()
        case .cancelled:
            closeImmediately()
        }
    }

    // MARK: - State

    private func beginOrContinue() {
        completionTask?.cancel()
        completionTask = nil
        if isCompleted {
            withAnimation(.smooth) { isCompleted = false }
        }
        // Asked every time: a download that starts during the checkmark still needs sampling.
        startSampling()
        if !isDownloading {
            withAnimation(.smooth) { isDownloading = true }
        }
    }

    private func finish() {
        guard isDownloading else { return }
        stopSampling()
        withAnimation(.smooth) { isCompleted = true }
        completionTask?.cancel()
        completionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.completionHold)
            guard !Task.isCancelled, let self else { return }
            withAnimation(.smooth) {
                self.isDownloading = false
                self.isCompleted = false
            }
        }
    }

    private func closeImmediately() {
        completionTask?.cancel()
        completionTask = nil
        stopSampling()
        guard isDownloading || isCompleted else { return }
        withAnimation(.smooth) {
            isDownloading = false
            isCompleted = false
        }
    }

    // MARK: - Speed and progress sampling

    private func startSampling() {
        if speedTask == nil, let directory {
            speedSession &+= 1
            let current = speedSession
            lastSpeedSample = nil
            smoothedSpeed = nil
            bytesPerSecond = nil
            speedTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let watcher = self else { return }
                    watcher.requestSpeedSample(directory: directory, session: current)
                    try? await Task.sleep(for: Self.speedInterval)
                }
            }
        }
        if progressTask == nil {
            progressTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let watcher = self else { return }
                    watcher.refreshFraction()
                    try? await Task.sleep(for: Self.progressInterval)
                }
            }
        }
    }

    private func stopSampling() {
        speedSession &+= 1
        speedTask?.cancel()
        speedTask = nil
        progressTask?.cancel()
        progressTask = nil
        lastSpeedSample = nil
        smoothedSpeed = nil
        if bytesPerSecond != nil { bytesPerSecond = nil }
        if fractionCompleted != nil { fractionCompleted = nil }
    }

    private func requestSpeedSample(directory: URL, session current: Int) {
        queue.async { [weak self] in
            let sample = DownloadsFolderReader.speedSample(of: directory)
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.record(sample, session: current) }
            }
        }
    }

    /// Feeds one speed reading; readings from an earlier sampling run are dropped.
    func record(_ sample: DownloadSpeedSample, session current: Int? = nil) {
        if let current, current != speedSession { return }
        defer { lastSpeedSample = sample }
        guard let previous = lastSpeedSample else { return }
        guard let rate = sample.rate(since: previous) else {
            smoothedSpeed = nil
            if bytesPerSecond != nil { bytesPerSecond = nil }
            return
        }
        let smoothed = DownloadSpeedSample.smoothed(previous: smoothedSpeed, sample: rate)
        smoothedSpeed = smoothed
        let shown = DownloadSpeedSample.displayable(smoothed)
        if shown != bytesPerSecond { bytesPerSecond = shown }
    }

    private func refreshFraction() {
        guard isDownloading, !isCompleted else { return }
        let next = progressTracker.fraction(for: tracker.activePartials)
        switch (fractionCompleted, next) {
        case (nil, nil):
            return
        case let (old?, new?) where abs(old - new) < 0.002:
            return
        default:
            withAnimation(.linear(duration: 0.25)) { fractionCompleted = next }
        }
    }
}
