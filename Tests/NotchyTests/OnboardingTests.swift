import AVFoundation
import EventKit
import Foundation
import SwiftUI
import Testing
@testable import Notchy

@MainActor
struct OnboardingTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "OnboardingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Lets queued main-actor tasks run until `condition` holds.
    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    // MARK: Flow

    @Test
    func stepsRunWelcomeToFinishedInOrder() {
        #expect(OnboardingStep.allCases == [
            .welcome, .gestures, .accessibility, .camera, .calendar,
            .musicSource, .profile, .features, .finished
        ])
        #expect(OnboardingStep.welcome.next == .gestures)
        #expect(OnboardingStep.features.next == .finished)
        #expect(OnboardingStep.finished.next == nil)
        #expect(OnboardingStep.welcome.previous == nil)
        #expect(OnboardingStep.camera.permission == .camera)
        #expect(OnboardingStep.calendar.permission == .calendar)
        #expect(OnboardingStep.accessibility.permission == .accessibility)
        #expect(OnboardingStep.profile.permission == nil)
    }

    @Test
    func leavingTheProfilePageSeedsTheFeatureSwitches() {
        let flow = OnboardingFlowModel(step: .profile)
        #expect(!flow.canContinueFromProfiles)
        flow.toggle(.developer)
        #expect(flow.canContinueFromProfiles)
        flow.advance()
        #expect(flow.step == .features)
        #expect(flow.featureChoices.stats)
        #expect(flow.featureChoices.colorPicker)
        #expect(!flow.featureChoices.mirror)

        flow.advance()
        #expect(flow.step == .finished)
        flow.advance()
        #expect(flow.step == .finished, "the last page has nowhere to go")
    }

    @Test
    func togglingAProfileTwiceDeselectsIt() {
        let flow = OnboardingFlowModel()
        flow.toggle(.student)
        flow.toggle(.student)
        #expect(flow.selectedProfiles.isEmpty)
    }

    // MARK: Profiles

    @Test
    func developerTurnsOnToolsAndOffTheMirror() {
        var base = OnboardingFeatureChoices.recommendedDefaults
        base.mirror = true
        base.minimalisticUI = true
        let choices = OnboardingFeatureChoices.resolved(for: [.developer], base: base)
        #expect(choices.colorPicker && choices.stats && choices.timer)
        #expect(!choices.mirror)
        #expect(!choices.minimalisticUI)
    }

    @Test
    func laterProfilesWinWhereTheyDisagree() {
        // Designer is applied after Developer, so it switches stats and the timer back off.
        let choices = OnboardingFeatureChoices.resolved(for: [.developer, .designer])
        #expect(!choices.stats)
        #expect(!choices.timer)
        #expect(choices.colorPicker)
        #expect(choices.mirror)
        #expect(choices.lightingEffect && choices.inlineHUD)
    }

    @Test
    func lightUseIsMinimalUnlessStudentFollows() {
        let light = OnboardingFeatureChoices.resolved(for: [.lightUse])
        #expect(light.minimalisticUI)
        #expect(light.timer && light.inlineHUD)
        #expect(!light.colorPicker && !light.mirror && !light.stats)

        let lightAndStudent = OnboardingFeatureChoices.resolved(for: [.lightUse, .student])
        #expect(!lightAndStudent.minimalisticUI, "student runs after light use and turns minimal mode off")
        #expect(lightAndStudent.calendar && lightAndStudent.timer)
    }

    @Test
    func everyProfileKeepsClipboardHapticsAndMenuBarIconOnAndLyricsOff() {
        var base = OnboardingFeatureChoices.recommendedDefaults
        base.clipboard = false
        base.haptics = false
        base.menuBarIcon = false
        base.lyrics = true
        for profile in OnboardingProfile.allCases {
            let choices = OnboardingFeatureChoices.resolved(for: [profile], base: base)
            #expect(choices.clipboard && choices.haptics && choices.menuBarIcon)
            #expect(!choices.lyrics)
        }
    }

    @Test
    func recommendedDefaultsMatchDesign() {
        let defaults = OnboardingFeatureChoices.recommendedDefaults
        #expect(defaults.clipboard && defaults.shelf && defaults.calendar && defaults.timer)
        #expect(defaults.colorPicker && defaults.inlineHUD && defaults.lightingEffect)
        #expect(!defaults.mirror && !defaults.stats && !defaults.notes && !defaults.lyrics)
        #expect(!defaults.minimalisticUI)
        #expect(defaults.haptics && defaults.menuBarIcon)
    }

    // MARK: Settings

    @Test
    func settingsStartIncompleteAndPersist() {
        let defaults = makeDefaults()
        let settings = OnboardingSettings(defaults: defaults)
        #expect(settings.needsOnboarding)
        #expect(!settings.helloShown)
        #expect(settings.playsWelcomeSound)
        #expect(settings.musicSource == .appleMusic)
        #expect(settings.selectedProfiles.isEmpty)

        let date = Date(timeIntervalSince1970: 1_800_000_000)
        settings.markCompleted(at: date)
        settings.helloShown = true
        settings.selectedProfiles = [.designer, .student]
        settings.musicSource = .spotify
        settings.playsWelcomeSound = false

        #expect(defaults.bool(forKey: "onboarding.completed"))
        let reloaded = OnboardingSettings(defaults: defaults)
        #expect(!reloaded.needsOnboarding)
        #expect(reloaded.completedAt == date)
        #expect(reloaded.helloShown)
        #expect(reloaded.selectedProfiles == [.designer, .student])
        #expect(reloaded.musicSource == .spotify)
        #expect(!reloaded.playsWelcomeSound)

        reloaded.resetForNextLaunch()
        let reset = OnboardingSettings(defaults: defaults)
        #expect(reset.needsOnboarding)
        #expect(!reset.helloShown)
        #expect(reset.completedAt == nil)
    }

    // MARK: Hello

    @Test
    func traceWritesThenChasesItself() {
        func window(_ progress: Double) -> (Double, Double) {
            let window = OnboardingTraceWindow(progress: progress)
            return (window.tail, window.head)
        }
        #expect(window(0) == (0, 0))
        #expect(window(0.25) == (0, 0.25))
        #expect(window(0.5) == (0, 0.5))
        #expect(window(0.75) == (0.5, 0.75))
        #expect(window(1) == (1, 1))
        #expect(window(1.4) == (1, 1), "springy overshoot is clamped")
    }

    @Test
    func helloStrokeIsOneContinuousLineInsideItsFrame() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 80)
        let knots = OnboardingHelloShape.knots.map {
            CGPoint(x: $0.x / OnboardingHelloShape.designSize.width * 200, y: $0.y / OnboardingHelloShape.designSize.height * 80)
        }
        let segments = OnboardingHelloShape.cubicSegments(through: knots)
        #expect(segments.count == knots.count - 1)
        for (current, next) in zip(segments, segments.dropFirst()) {
            #expect(current.end == next.start)
        }
        #expect(segments.first?.start == CGPoint(x: 0, y: 92.0 / 100 * 80))

        let bounds = OnboardingHelloShape().path(in: rect).boundingRect
        #expect(bounds.width > 190)
        #expect(rect.insetBy(dx: -4, dy: -4).contains(bounds), "the spline barely overshoots its knots")
        #expect(OnboardingHelloShape.knots.map(\.x).max() == OnboardingHelloShape.designSize.width)
    }

    @Test
    func helloOpensThenClosesAfterItAppears() async {
        let hello = OnboardingHelloController(sleeper: { _ in })
        var opened = 0
        var closed = 0
        var finished = 0
        hello.openIsland = { opened += 1 }
        hello.closeIsland = { closed += 1 }
        hello.onFinished = { finished += 1 }

        hello.helloDidAppear()
        #expect(closed == 0, "nothing to close before the hello is presented")

        hello.present()
        await settle { hello.isPresenting }
        #expect(hello.isPresenting)
        #expect(opened == 1)
        #expect(hello.replayCount == 1)

        hello.helloDidAppear()
        hello.helloDidAppear()
        await settle { !hello.isPresenting }
        #expect(!hello.isPresenting)
        #expect(closed == 1, "repeated appear callbacks close only once")
        #expect(finished == 1)
    }

    @Test
    func replayingAVisibleHelloStillClosesIt() async {
        let hello = OnboardingHelloController(sleeper: { _ in })
        var closed = 0
        hello.closeIsland = { closed += 1 }
        hello.present()
        await settle { hello.isPresenting }
        // The stage never reports a second appearance while it stays on screen.
        hello.present()
        await settle { hello.replayCount == 2 }
        await settle { !hello.isPresenting }
        #expect(closed == 1)
        #expect(!hello.isPresenting)
    }

    @Test
    func cancellingTheHelloNeverOpensTheIsland() async {
        let hello = OnboardingHelloController(sleeper: { _ in await Task.yield() })
        var opened = 0
        hello.openIsland = { opened += 1 }
        hello.present()
        hello.cancel()
        for _ in 0..<20 { await Task.yield() }
        #expect(opened == 0)
        #expect(!hello.isPresenting)
    }

    @Test
    func helloTimingMatchesDesign() {
        #expect(OnboardingHelloController.openDelay == .seconds(1))
        #expect(OnboardingHelloController.holdDuration == .milliseconds(3_500))
    }

    // MARK: Permissions

    @Test
    func automationCodesMapToStatuses() {
        #expect(OnboardingPermissionStatus.automation(0) == .granted)
        #expect(OnboardingPermissionStatus.automation(-1743) == .denied)
        #expect(OnboardingPermissionStatus.automation(-1744) == .notDetermined)
        #expect(OnboardingPermissionStatus.automation(-600) == .targetNotRunning)
        #expect(OnboardingPermissionStatus.targetNotRunning.canPrompt)
        #expect(!OnboardingPermissionStatus.denied.canPrompt)
    }

    @Test
    func cameraCalendarAndAccessibilityStatusesMap() {
        #expect(OnboardingPermissionStatus.camera(.authorized) == .granted)
        #expect(OnboardingPermissionStatus.camera(.denied) == .denied)
        #expect(OnboardingPermissionStatus.camera(.restricted) == .restricted)
        #expect(OnboardingPermissionStatus.camera(.notDetermined) == .notDetermined)

        #expect(OnboardingPermissionStatus.calendar(.fullAccess) == .granted)
        #expect(OnboardingPermissionStatus.calendar(.writeOnly) == .denied, "write-only cannot read events")
        #expect(OnboardingPermissionStatus.calendar(.notDetermined) == .notDetermined)

        #expect(OnboardingPermissionStatus.accessibility(trusted: true, requested: false) == .granted)
        #expect(OnboardingPermissionStatus.accessibility(trusted: false, requested: false) == .notDetermined)
        #expect(OnboardingPermissionStatus.accessibility(trusted: false, requested: true) == .denied)
    }

    @Test
    func permissionsPointAtTheirSettingsPanes() {
        #expect(OnboardingPermission.accessibility.settingsURL?.absoluteString.hasSuffix("Privacy_Accessibility") == true)
        #expect(OnboardingPermission.camera.settingsURL?.absoluteString.hasSuffix("Privacy_Camera") == true)
        #expect(OnboardingPermission.calendar.settingsURL?.absoluteString.hasSuffix("Privacy_Calendars") == true)
        #expect(OnboardingPermission.automationSpotify.settingsURL?.absoluteString.hasSuffix("Privacy_Automation") == true)
        #expect(OnboardingPermission.automationMusic.automationTarget == "com.apple.Music")
        #expect(OnboardingPermission.automationSpotify.automationTarget == "com.spotify.client")
        #expect(OnboardingPermission.camera.automationTarget == nil)
    }

    @Test
    func musicSourcesTargetTheirApps() {
        #expect(OnboardingMusicSource.defaultSource == .appleMusic)
        #expect(OnboardingMusicSource.allCases.map(\.rawValue) == ["automatic", "appleMusic", "spotify"],
                "raw values line up with the media feature's source preference")
        #expect(OnboardingMusicSource.automatic.automationPermissions == [.automationMusic, .automationSpotify])
        #expect(OnboardingMusicSource.appleMusic.automationPermissions == [.automationMusic])
        #expect(OnboardingMusicSource.spotify.automationPermissions == [.automationSpotify])
        #expect(OnboardingMusicSource.spotify.bundleIdentifiers == ["com.spotify.client"])
        for source in OnboardingMusicSource.allCases {
            #expect(source.automationPermissions.compactMap(\.automationTarget) == source.bundleIdentifiers)
        }
    }

    @Test
    func windowMatchesDesignSize() {
        #expect(OnboardingView.windowSize == CGSize(width: 400, height: 600))
        #expect(OnboardingWindowController.windowIdentifier.rawValue == "OnboardingWindow")
    }

    @Test
    func sparkleParticleIsTwentySixPointDot() {
        let image = OnboardingSparkleNSView.sparkleImage
        #expect(image != nil)
        // 26 pt drawn at 2x, so the emitter shows it at 26 pt.
        #expect(image?.width == 52 && image?.height == 52)
        #expect(OnboardingSparkleNSView.sparkleSide == 26)
        #expect(OnboardingSparkleNSView.sparkleImageScale == 2)
        #expect(OnboardingSparkleNSView.settledBirthRate == 20)
        #expect(!OnboardingSparkleNSView(frame: .zero).isFlipped, "y acceleration lifts the sparkles")
    }

    @Test
    func spotlightKeepsDesignProportions() {
        #expect(abs(OnboardingSpotlight.aspectRatio - 689.0 / 1005.0) < 0.0001)
        let rect = CGRect(x: 0, y: 0, width: 689, height: 1005)
        let bounds = OnboardingSpotlightBeam().path(in: rect).boundingRect
        // Full width at the foot, flush with the top edge, landing at 92 % of the height.
        #expect(abs(bounds.minX - 5) < 1 && abs(bounds.maxX - 684) < 1)
        #expect(abs(bounds.minY + 4) < 1)
        #expect(abs(bounds.maxY - 923.5) < 1)
    }

    @Test
    func welcomeArtworkSitsOnTheIconGrid() {
        #expect(abs(OnboardingAppGlyph.gridFill - 824.0 / 1024.0) < 0.0001)
        #expect(OnboardingWordmark.height == 22)
    }

    @Test
    func focusDetectionQuestionUsesDesignAnswers() {
        #expect(OnboardingFocusDetectionMode.allCases.map(\.title) == ["Use DevTools", "Use without DevTools"])
    }

    @Test
    func profileCardsUseDesignCopy() {
        #expect(OnboardingProfile.allCases.map(\.title) == ["Developer", "Designer", "Light Use", "Student"])
        #expect(OnboardingProfile.allCases.map(\.systemImage) == ["terminal.fill", "paintbrush.fill", "sparkles", "book.fill"])
        #expect(OnboardingProfile.designer.summary == "Create and design with color picker, mirror, and visual effects.")
        #expect(OnboardingProfile.lightUse.summary == "Simple and minimal interface with just the essentials for everyday tasks.")
        #expect(OnboardingProfile.student.summary == "Stay organized with calendar, timer, and battery monitoring.")
    }
}
