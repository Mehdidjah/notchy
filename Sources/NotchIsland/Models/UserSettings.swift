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
        static let expandedWidth = "notch.expandedWidth"
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
    @Published var expandedWidth: Double { didSet { defaults.set(expandedWidth, forKey: Key.expandedWidth) } }
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
        let usesBalancedHoverTiming = defaults.integer(forKey: Key.hoverTimingVersion) >= 1
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
        hoverDelayMilliseconds = usesBalancedHoverTiming
            ? max(0, defaults.object(forKey: Key.hoverDelayMilliseconds) as? Int ?? 500)
            : 500
        closeDelayMilliseconds = usesBalancedHoverTiming
            ? max(0, defaults.object(forKey: Key.closeDelayMilliseconds) as? Int ?? 500)
            : 500
        expandedWidth = min(
            920,
            max(760, defaults.object(forKey: Key.expandedWidth) as? Double ?? 840)
        )
        defaultAction = DefaultClipAction(
            rawValue: defaults.string(forKey: Key.defaultAction) ?? ""
        ) ?? .paste
        retentionPreset = RetentionPreset(
            rawValue: defaults.string(forKey: Key.retentionPreset) ?? ""
        ) ?? .thirtyDays
        maximumItemCount = max(100, defaults.object(forKey: Key.maximumItemCount) as? Int ?? 10_000)
        hideInFullscreen = defaults.bool(forKey: Key.hideInFullscreen)

        if !usesBalancedHoverTiming {
            defaults.set(hoverDelayMilliseconds, forKey: Key.hoverDelayMilliseconds)
            defaults.set(closeDelayMilliseconds, forKey: Key.closeDelayMilliseconds)
            defaults.set(1, forKey: Key.hoverTimingVersion)
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
