import AppKit
import Combine
import Foundation

/// Tells the user, once per version, that a newer Notchy is out.
@MainActor
protocol UpdateAnnouncing: AnyObject {
    func announce(_ release: UpdateRelease)
}

/// Looks for a newer release shortly after launch and then every few hours, and keeps the result
/// for the menu bar and Settings. Downloads open in the browser; installing is dragging the new
/// copy into Applications.
@MainActor
final class UpdateChecker: ObservableObject {
    enum Status: Equatable {
        /// This build has no version number or no release feed, for example under `swift run`.
        case unavailable
        case idle
        case checking
        case upToDate
        case available(UpdateRelease)
        case failed(String)
    }

    enum Key {
        static let automaticallyChecks = "updates.automaticallyChecks"
        static let lastChecked = "updates.lastChecked"
        static let lastAnnouncedVersion = "updates.lastAnnouncedVersion"
    }

    /// Info.plist key with the `owner/name` repository whose releases are checked.
    static let repositoryInfoKey = "NotchyUpdateRepository"
    static let checkInterval: TimeInterval = 6 * 3_600

    static let shared: UpdateChecker = {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
        let repository = info[repositoryInfoKey] as? String ?? ""
        let feed: (any UpdateFeed)? = GitHubReleaseFeed.isValidRepository(repository)
            ? GitHubReleaseFeed(repository: repository, userAgent: "Notchy/\(version?.description ?? "development")")
            : nil
        return UpdateChecker(currentVersion: version, feed: feed, announcer: SystemUpdateAnnouncer())
    }()

    let currentVersion: AppVersion?
    @Published private(set) var status: Status
    @Published private(set) var lastChecked: Date?
    @Published var automaticallyChecks: Bool {
        didSet { defaults.set(automaticallyChecks, forKey: Key.automaticallyChecks) }
    }

    var availableRelease: UpdateRelease? {
        if case .available(let release) = status { release } else { nil }
    }

    var isChecking: Bool { status == .checking }

    private let feed: (any UpdateFeed)?
    private let announcer: any UpdateAnnouncing
    private let defaults: UserDefaults
    private let now: () -> Date
    private var schedule: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?

    init(
        currentVersion: AppVersion?,
        feed: (any UpdateFeed)?,
        announcer: any UpdateAnnouncing,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.currentVersion = currentVersion
        self.feed = feed
        self.announcer = announcer
        self.defaults = defaults
        self.now = now
        status = currentVersion != nil && feed != nil ? .idle : .unavailable
        lastChecked = defaults.object(forKey: Key.lastChecked) as? Date
        automaticallyChecks = defaults.object(forKey: Key.automaticallyChecks) as? Bool ?? true
    }

    /// True when the last successful check is older than `checkInterval`.
    var isCheckDue: Bool {
        guard let lastChecked else { return true }
        return now().timeIntervalSince(lastChecked) >= Self.checkInterval
    }

    /// Checks after `initialDelay`, then wakes every `pollInterval` and checks when one is due, so
    /// a Mac that slept through the interval catches up soon after waking.
    func start(initialDelay: Duration = .seconds(20), pollInterval: Duration = .seconds(1_800)) {
        guard schedule == nil, status != .unavailable else { return }
        schedule = Task { [weak self] in
            try? await Task.sleep(for: initialDelay)
            while !Task.isCancelled {
                guard let self else { return }
                if self.automaticallyChecks && self.isCheckDue { await self.checkAutomatically() }
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    func stop() {
        schedule?.cancel()
        schedule = nil
    }

    /// A check the user asked for. Its result shows where it was asked from, so it is not
    /// announced again later.
    func checkNow() async {
        await check(announcing: false)
    }

    /// A scheduled check: a version found for the first time is announced.
    func checkAutomatically() async {
        await check(announcing: true)
    }

    func openDownload(_ release: UpdateRelease) {
        NSWorkspace.shared.open(release.preferredDownloadURL)
    }

    func openReleasePage(_ release: UpdateRelease) {
        NSWorkspace.shared.open(release.pageURL)
    }

    private func check(announcing: Bool) async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await self.runCheck(announcing: announcing) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func runCheck(announcing: Bool) async {
        guard let feed, let currentVersion else {
            status = .unavailable
            return
        }
        status = .checking
        do {
            let release = try await feed.latestRelease()
            let checkedAt = now()
            lastChecked = checkedAt
            defaults.set(checkedAt, forKey: Key.lastChecked)
            guard let release, release.version > currentVersion else {
                status = .upToDate
                return
            }
            status = .available(release)
            let version = release.version.description
            guard defaults.string(forKey: Key.lastAnnouncedVersion) != version else { return }
            defaults.set(version, forKey: Key.lastAnnouncedVersion)
            if announcing { announcer.announce(release) }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
