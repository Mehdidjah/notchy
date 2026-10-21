import Foundation
import Testing
@testable import Notchy

@MainActor
struct UpdateTests {
    // MARK: Versions

    @Test
    func versionsParseTagsAndIgnoreBuildMetadata() throws {
        #expect(AppVersion("v1.4.2")?.components == [1, 4, 2])
        #expect(AppVersion(" 2.0 ")?.components == [2, 0])
        #expect(AppVersion("1.2.0+45")?.description == "1.2.0")
        #expect(AppVersion("2.0.0-beta.1")?.prerelease == "beta.1")
        for invalid in ["", "v", "1..2", "1.x", "-1.0", "1.2-", "1.2.3.4.5", "١.٢"] {
            #expect(AppVersion(invalid) == nil, "\(invalid) is not a version")
        }
    }

    @Test
    func versionsCompareNumericallyWithMissingPartsAsZero() throws {
        let v = { (text: String) in AppVersion(text)! }
        #expect(v("1.10.0") > v("1.9.9"))
        #expect(v("1.2") == v("1.2.0"))
        #expect(Set([v("1.2"), v("1.2.0")]).count == 1)
        #expect(v("2.0.0-beta.2") < v("2.0.0"))
        #expect(v("2.0.0-beta.2") < v("2.0.0-beta.10"))
        #expect(v("2.0.0-beta.2") > v("1.9"))
        #expect(!(v("1.0") < v("1.0")))
    }

    // MARK: Feed

    @Test
    func releasePayloadPrefersTheDiskImageAsset() throws {
        let release = try GitHubReleaseFeed.decodeRelease(from: Self.payload(tag: "v1.3.0", assets: [
            ("Notchy-1.3.0.zip", "https://example.com/Notchy-1.3.0.zip"),
            ("Notchy-1.3.0.dmg", "https://example.com/Notchy-1.3.0.dmg"),
        ]))
        #expect(release.version == AppVersion("1.3.0"))
        #expect(release.title == "Notchy 1.3.0")
        #expect(release.notes == "Fixes")
        #expect(release.preferredDownloadURL.absoluteString == "https://example.com/Notchy-1.3.0.dmg")
        #expect(release.publishedAt != nil)
    }

    @Test
    func releaseWithoutDiskImageFallsBackToItsPage() throws {
        let release = try GitHubReleaseFeed.decodeRelease(from: Self.payload(tag: "1.3", assets: []))
        #expect(release.downloadURL == nil)
        #expect(release.preferredDownloadURL.absoluteString == "https://example.com/releases/1.3")
    }

    @Test
    func releaseWithUnreadableTagIsRejected() {
        #expect(throws: UpdateFeedError.invalidRelease) {
            try GitHubReleaseFeed.decodeRelease(from: Self.payload(tag: "latest", assets: []))
        }
    }

    @Test
    func repositoryNamesAreValidated() {
        #expect(GitHubReleaseFeed.isValidRepository("owner/notchy-releases"))
        #expect(GitHubReleaseFeed.isValidRepository("a.b/c_d"))
        for invalid in ["", "owner", "owner/", "/name", "a/b/c", "own er/name", "owner/na?me"] {
            #expect(!GitHubReleaseFeed.isValidRepository(invalid), "\(invalid)")
        }
    }

    // MARK: Checker

    @Test
    func newerReleaseIsAvailableAndAnnouncedOnce() async {
        let feed = StubFeed(release: Self.release("1.1.0"))
        let announcer = RecordingAnnouncer()
        let checker = Self.checker(current: "1.0.0", feed: feed, announcer: announcer)

        await checker.checkAutomatically()
        #expect(checker.availableRelease?.version == AppVersion("1.1.0"))
        #expect(announcer.versions == ["1.1.0"])

        await checker.checkAutomatically()
        #expect(announcer.versions == ["1.1.0"], "the same version is announced only once")

        feed.release = Self.release("1.2.0")
        await checker.checkAutomatically()
        #expect(announcer.versions == ["1.1.0", "1.2.0"])
    }

    @Test
    func sameOrOlderReleaseIsUpToDate() async {
        let announcer = RecordingAnnouncer()
        let checker = Self.checker(current: "1.2.0", feed: StubFeed(release: Self.release("1.2")), announcer: announcer)
        await checker.checkAutomatically()
        #expect(checker.status == .upToDate)

        let older = Self.checker(current: "1.2.0", feed: StubFeed(release: Self.release("1.1.9")), announcer: announcer)
        await older.checkAutomatically()
        #expect(older.status == .upToDate)

        let none = Self.checker(current: "1.2.0", feed: StubFeed(release: nil), announcer: announcer)
        await none.checkAutomatically()
        #expect(none.status == .upToDate)
        #expect(announcer.versions.isEmpty)
    }

    @Test
    func checkTheUserAskedForIsShownButNotAnnouncedLater() async {
        let announcer = RecordingAnnouncer()
        let checker = Self.checker(current: "1.0.0", feed: StubFeed(release: Self.release("1.1.0")), announcer: announcer)
        await checker.checkNow()
        #expect(checker.availableRelease != nil)
        await checker.checkAutomatically()
        #expect(announcer.versions.isEmpty)
    }

    @Test
    func failedCheckReportsTheErrorAndStaysDue() async {
        let feed = StubFeed(release: nil)
        feed.error = UpdateFeedError.badResponse(statusCode: 500)
        let checker = Self.checker(current: "1.0.0", feed: feed, announcer: RecordingAnnouncer())
        await checker.checkNow()
        #expect(checker.status == .failed("The release server answered with status 500."))
        #expect(checker.lastChecked == nil)
        #expect(checker.isCheckDue)
    }

    @Test
    func checkIsDueAfterTheIntervalAndSettingsPersist() async {
        let defaults = Self.defaults()
        var now = Date(timeIntervalSince1970: 1_000_000)
        let checker = UpdateChecker(
            currentVersion: AppVersion("1.0.0"),
            feed: StubFeed(release: nil),
            announcer: RecordingAnnouncer(),
            defaults: defaults,
            now: { now }
        )
        #expect(checker.isCheckDue)
        await checker.checkNow()
        #expect(!checker.isCheckDue)
        now += UpdateChecker.checkInterval
        #expect(checker.isCheckDue)

        checker.automaticallyChecks = false
        let reloaded = UpdateChecker(currentVersion: AppVersion("1.0.0"), feed: nil, announcer: RecordingAnnouncer(), defaults: defaults)
        #expect(!reloaded.automaticallyChecks)
        #expect(reloaded.lastChecked == Date(timeIntervalSince1970: 1_000_000))
    }

    @Test
    func buildWithoutVersionOrFeedIsUnavailable() async {
        let noFeed = UpdateChecker(currentVersion: AppVersion("1.0"), feed: nil, announcer: RecordingAnnouncer(), defaults: Self.defaults())
        #expect(noFeed.status == .unavailable)
        await noFeed.checkNow()
        #expect(noFeed.status == .unavailable)

        let noVersion = UpdateChecker(currentVersion: nil, feed: StubFeed(release: nil), announcer: RecordingAnnouncer(), defaults: Self.defaults())
        #expect(noVersion.status == .unavailable)
    }

    @Test
    func scheduledCheckRunsAfterTheInitialDelay() async throws {
        let announcer = RecordingAnnouncer()
        let checker = Self.checker(current: "1.0.0", feed: StubFeed(release: Self.release("2.0")), announcer: announcer)
        checker.start(initialDelay: .milliseconds(10), pollInterval: .seconds(60))
        defer { checker.stop() }
        for _ in 0..<200 where announcer.versions.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(announcer.versions == ["2.0"])
    }

    @Test
    func installInstructionsExplainOpenAnywayOnlyWithoutADeveloperID() {
        let signed = AppSignature.installInstructions(hasDeveloperID: true)
        let unsigned = AppSignature.installInstructions(hasDeveloperID: false)
        #expect(signed.contains("drag Notchy into Applications"))
        #expect(!signed.contains("Open Anyway"))
        #expect(unsigned.hasPrefix(signed))
        #expect(unsigned.contains("Open Anyway in System Settings → Privacy & Security"))
    }

    // MARK: Helpers

    private static func defaults() -> UserDefaults {
        let suite = "UpdateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static func checker(current: String, feed: StubFeed, announcer: RecordingAnnouncer) -> UpdateChecker {
        UpdateChecker(currentVersion: AppVersion(current), feed: feed, announcer: announcer, defaults: defaults())
    }

    private static func release(_ version: String) -> UpdateRelease {
        UpdateRelease(
            version: AppVersion(version)!,
            title: "Notchy \(version)",
            notes: "",
            pageURL: URL(string: "https://example.com/releases/\(version)")!,
            downloadURL: URL(string: "https://example.com/Notchy-\(version).dmg")!
        )
    }

    private static func payload(tag: String, assets: [(String, String)]) -> Data {
        let assetJSON = assets.map { #"{"name": "\#($0.0)", "browser_download_url": "\#($0.1)", "size": 10}"# }
        return Data(#"""
        {
          "tag_name": "\#(tag)",
          "name": "",
          "body": "Fixes",
          "html_url": "https://example.com/releases/\#(tag)",
          "draft": false,
          "prerelease": false,
          "published_at": "2026-10-18T09:00:00Z",
          "assets": [\#(assetJSON.joined(separator: ","))]
        }
        """#.utf8)
    }
}

@MainActor
private final class RecordingAnnouncer: UpdateAnnouncing {
    var versions: [String] = []
    func announce(_ release: UpdateRelease) { versions.append(release.version.description) }
}

private final class StubFeed: UpdateFeed, @unchecked Sendable {
    var release: UpdateRelease?
    var error: (any Error)?

    init(release: UpdateRelease?) { self.release = release }

    func latestRelease() async throws -> UpdateRelease? {
        if let error { throw error }
        return release
    }
}
