import Combine
import Foundation

enum DefaultClipAction: String, Codable, CaseIterable, Sendable {
    case paste
    case copy
    case preview
}

enum RetentionPreset: String, Codable, CaseIterable, Sendable {
    case sevenDays
    case fifteenDays
    case thirtyDays
    case ninetyDays
    case forever

    var maximumAge: TimeInterval? {
        switch self {
        case .sevenDays: 7 * 86_400
        case .fifteenDays: 15 * 86_400
        case .thirtyDays: 30 * 86_400
        case .ninetyDays: 90 * 86_400
        case .forever: nil
        }
    }
}

struct CapturePolicy: Sendable, Equatable {
    var isEnabled: Bool = true
    var manualCaptureOnly: Bool = false
    var ignoredApplicationBundleIdentifiers: Set<String> = []
    var ignoredContentTypes: Set<ClipType> = []
    var maximumPayloadBytes: Int = 50 * 1_024 * 1_024
    var saveSensitiveContent: Bool = false
    var duplicateBehavior: DuplicateCaptureBehavior = .moveOriginalToFront
}

/// Interaction timings and feel for the notch island. The defaults follow the
/// behaviour observed in shipped notch apps: a short dwell before a hover opens
/// the island, a brief grace period after the pointer leaves, and a swipe
/// threshold measured in accumulated trackpad scroll units.
enum NotchInteractionDefaults {
    static let hoverDelayMilliseconds = 300
    static let closeDelayMilliseconds = 100
    static let gestureSensitivity = 200.0
    static let peekDurationMilliseconds = 1_500
    static let hoverTimingVersion = 2
}

@MainActor
final class UserSettings: ObservableObject {
    private enum Key {
        static let captureEnabled = "capture.enabled"
        static let manualCaptureOnly = "capture.manualOnly"
        static let ignoredApplications = "capture.ignoredApplications"
        static let ignoredTypes = "capture.ignoredTypes"
        static let maxPayloadMegabytes = "capture.maxPayloadMegabytes"
        static let saveSensitive = "privacy.saveSensitive"
        static let duplicateBehavior = "history.duplicateBehavior"
        static let notchEnabled = "notch.enabled"
        static let hoverDelayMilliseconds = "notch.hoverDelayMilliseconds"
        static let closeDelayMilliseconds = "notch.closeDelayMilliseconds"
        static let hoverTimingVersion = "notch.hoverTimingVersion"
        static let openNotchWidth = "notch.openWidth"
        static let openOnHover = "notch.openOnHover"
        static let hapticsEnabled = "notch.hapticsEnabled"
        static let gesturesEnabled = "notch.gesturesEnabled"
        static let closeGestureEnabled = "notch.closeGestureEnabled"
        static let gestureSensitivity = "notch.gestureSensitivity"
        static let showShadow = "notch.showShadow"
        static let hideFromScreenCapture = "notch.hideFromScreenCapture"
        static let showCapturePeek = "notch.showCapturePeek"
        static let showHomeTab = "tabs.home"
        static let showNotesTab = "tabs.notes"
        static let openLastTab = "tabs.openLastTab"
        static let showShelfTab = "tabs.shelf"
        static let showTimerTab = "tabs.timer"
        static let showStatsTab = "tabs.stats"
        static let defaultAction = "history.defaultAction"
        static let retentionPreset = "history.retentionPreset"
        static let maximumItemCount = "history.maximumItemCount"
        static let hideInFullscreen = "notch.hideInFullscreen"
    }

    private let defaults: UserDefaults

    @Published var captureEnabled: Bool { didSet { defaults.set(captureEnabled, forKey: Key.captureEnabled) } }
    @Published var manualCaptureOnly: Bool { didSet { defaults.set(manualCaptureOnly, forKey: Key.manualCaptureOnly) } }
    @Published var ignoredApplications: Set<String> {
        didSet { defaults.set(Array(ignoredApplications).sorted(), forKey: Key.ignoredApplications) }
    }
    @Published var ignoredTypes: Set<ClipType> {
        didSet { defaults.set(ignoredTypes.map(\.rawValue).sorted(), forKey: Key.ignoredTypes) }
    }
    @Published var maxPayloadMegabytes: Int {
        didSet { defaults.set(maxPayloadMegabytes, forKey: Key.maxPayloadMegabytes) }
    }
    @Published var saveSensitiveContent: Bool {
        didSet { defaults.set(saveSensitiveContent, forKey: Key.saveSensitive) }
    }
    @Published var duplicateBehavior: DuplicateCaptureBehavior {
        didSet { defaults.set(duplicateBehavior.rawValue, forKey: Key.duplicateBehavior) }
    }
    @Published var notchEnabled: Bool { didSet { defaults.set(notchEnabled, forKey: Key.notchEnabled) } }
    @Published var hoverDelayMilliseconds: Int {
        didSet { defaults.set(hoverDelayMilliseconds, forKey: Key.hoverDelayMilliseconds) }
    }
    @Published var closeDelayMilliseconds: Int {
        didSet { defaults.set(closeDelayMilliseconds, forKey: Key.closeDelayMilliseconds) }
    }
    @Published var openNotchWidth: Double { didSet { defaults.set(openNotchWidth, forKey: Key.openNotchWidth) } }
    @Published var openOnHover: Bool { didSet { defaults.set(openOnHover, forKey: Key.openOnHover) } }
    @Published var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) } }
    @Published var gesturesEnabled: Bool { didSet { defaults.set(gesturesEnabled, forKey: Key.gesturesEnabled) } }
    @Published var closeGestureEnabled: Bool {
        didSet { defaults.set(closeGestureEnabled, forKey: Key.closeGestureEnabled) }
    }
    @Published var gestureSensitivity: Double {
        didSet { defaults.set(gestureSensitivity, forKey: Key.gestureSensitivity) }
    }
    @Published var showShadow: Bool { didSet { defaults.set(showShadow, forKey: Key.showShadow) } }
    @Published var hideFromScreenCapture: Bool {
        didSet { defaults.set(hideFromScreenCapture, forKey: Key.hideFromScreenCapture) }
    }
    @Published var showCapturePeek: Bool {
        didSet { defaults.set(showCapturePeek, forKey: Key.showCapturePeek) }
    }
    @Published var showHomeTab: Bool { didSet { defaults.set(showHomeTab, forKey: Key.showHomeTab) } }
    @Published var showNotesTab: Bool { didSet { defaults.set(showNotesTab, forKey: Key.showNotesTab) } }
    /// Reopen on the last tab instead of Home (Atoll: openLastTabByDefault, default off).
    @Published var openLastTab: Bool { didSet { defaults.set(openLastTab, forKey: Key.openLastTab) } }
    @Published var showShelfTab: Bool { didSet { defaults.set(showShelfTab, forKey: Key.showShelfTab) } }
    @Published var showTimerTab: Bool { didSet { defaults.set(showTimerTab, forKey: Key.showTimerTab) } }
    @Published var showStatsTab: Bool { didSet { defaults.set(showStatsTab, forKey: Key.showStatsTab) } }
    @Published var defaultAction: DefaultClipAction {
        didSet { defaults.set(defaultAction.rawValue, forKey: Key.defaultAction) }
    }
    @Published var retentionPreset: RetentionPreset {
        didSet { defaults.set(retentionPreset.rawValue, forKey: Key.retentionPreset) }
    }
    @Published var maximumItemCount: Int {
        didSet { defaults.set(maximumItemCount, forKey: Key.maximumItemCount) }
    }
    @Published var hideInFullscreen: Bool {
        didSet { defaults.set(hideInFullscreen, forKey: Key.hideInFullscreen) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedTimingVersion = defaults.integer(forKey: Key.hoverTimingVersion)
        let usesCurrentTiming = storedTimingVersion >= NotchInteractionDefaults.hoverTimingVersion
        captureEnabled = defaults.object(forKey: Key.captureEnabled) as? Bool ?? true
        manualCaptureOnly = defaults.bool(forKey: Key.manualCaptureOnly)
        ignoredApplications = Set(defaults.stringArray(forKey: Key.ignoredApplications) ?? [])
        ignoredTypes = Set(
            (defaults.stringArray(forKey: Key.ignoredTypes) ?? []).compactMap(ClipType.init(rawValue:))
        )
        maxPayloadMegabytes = max(1, defaults.object(forKey: Key.maxPayloadMegabytes) as? Int ?? 50)
        saveSensitiveContent = defaults.bool(forKey: Key.saveSensitive)
        duplicateBehavior = DuplicateCaptureBehavior(
            rawValue: defaults.string(forKey: Key.duplicateBehavior) ?? ""
        ) ?? .moveOriginalToFront
        notchEnabled = defaults.object(forKey: Key.notchEnabled) as? Bool ?? true
        hoverDelayMilliseconds = usesCurrentTiming
            ? max(0, defaults.object(forKey: Key.hoverDelayMilliseconds) as? Int
                ?? NotchInteractionDefaults.hoverDelayMilliseconds)
            : NotchInteractionDefaults.hoverDelayMilliseconds
        closeDelayMilliseconds = usesCurrentTiming
            ? max(0, defaults.object(forKey: Key.closeDelayMilliseconds) as? Int
                ?? NotchInteractionDefaults.closeDelayMilliseconds)
            : NotchInteractionDefaults.closeDelayMilliseconds
        openNotchWidth = min(
            NotchTab.maximumOpenWidth,
            max(NotchTab.defaultOpenWidth, defaults.object(forKey: Key.openNotchWidth) as? Double ?? NotchTab.defaultOpenWidth)
        )
        openOnHover = defaults.object(forKey: Key.openOnHover) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Key.hapticsEnabled) as? Bool ?? true
        gesturesEnabled = defaults.object(forKey: Key.gesturesEnabled) as? Bool ?? true
        closeGestureEnabled = defaults.object(forKey: Key.closeGestureEnabled) as? Bool ?? true
        gestureSensitivity = min(
            600,
            max(50, defaults.object(forKey: Key.gestureSensitivity) as? Double
                ?? NotchInteractionDefaults.gestureSensitivity)
        )
        showShadow = defaults.object(forKey: Key.showShadow) as? Bool ?? true
        hideFromScreenCapture = defaults.bool(forKey: Key.hideFromScreenCapture)
        showCapturePeek = defaults.object(forKey: Key.showCapturePeek) as? Bool ?? true
        showHomeTab = defaults.object(forKey: Key.showHomeTab) as? Bool ?? true
        showNotesTab = defaults.object(forKey: Key.showNotesTab) as? Bool ?? true
        openLastTab = defaults.bool(forKey: Key.openLastTab)
        showShelfTab = defaults.object(forKey: Key.showShelfTab) as? Bool ?? true
        showTimerTab = defaults.object(forKey: Key.showTimerTab) as? Bool ?? true
        showStatsTab = defaults.object(forKey: Key.showStatsTab) as? Bool ?? true
        defaultAction = DefaultClipAction(
            rawValue: defaults.string(forKey: Key.defaultAction) ?? ""
        ) ?? .paste
        retentionPreset = RetentionPreset(
            rawValue: defaults.string(forKey: Key.retentionPreset) ?? ""
        ) ?? .thirtyDays
        maximumItemCount = max(100, defaults.object(forKey: Key.maximumItemCount) as? Int ?? 10_000)
        hideInFullscreen = defaults.bool(forKey: Key.hideInFullscreen)

        if !usesCurrentTiming {
            defaults.set(hoverDelayMilliseconds, forKey: Key.hoverDelayMilliseconds)
            defaults.set(closeDelayMilliseconds, forKey: Key.closeDelayMilliseconds)
            defaults.set(NotchInteractionDefaults.hoverTimingVersion, forKey: Key.hoverTimingVersion)
        }
    }

    var capturePolicy: CapturePolicy {
        CapturePolicy(
            isEnabled: captureEnabled,
            manualCaptureOnly: manualCaptureOnly,
            ignoredApplicationBundleIdentifiers: ignoredApplications,
            ignoredContentTypes: ignoredTypes,
            maximumPayloadBytes: maxPayloadMegabytes * 1_024 * 1_024,
            saveSensitiveContent: saveSensitiveContent,
            duplicateBehavior: duplicateBehavior
        )
    }

    var retentionPolicy: RetentionPolicy {
        RetentionPolicy(
            maximumAge: retentionPreset.maximumAge,
            maximumItemCount: maximumItemCount,
            maximumDiskBytes: nil
        )
    }
}
