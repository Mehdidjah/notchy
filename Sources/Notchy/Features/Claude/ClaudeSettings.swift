import Combine
import Foundation

/// The model a chat asks for. "Default" leaves the choice to Claude Code's own setting.
enum ClaudeChatModel: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case opus
    case sonnet
    case haiku

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Default"
        case .opus: "Opus"
        case .sonnet: "Sonnet"
        case .haiku: "Haiku"
        }
    }

    /// The alias passed to `--model`.
    var alias: String? {
        switch self {
        case .automatic: nil
        case .opus: "opus"
        case .sonnet: "sonnet"
        case .haiku: "haiku"
        }
    }
}

/// The two halves of the AI tools tab.
enum ClaudeTabSection: String, CaseIterable, Identifiable, Sendable {
    case chat
    case sessions

    var id: Self { self }

    var title: String {
        switch self {
        case .chat: "Chat"
        case .sessions: "Sessions"
        }
    }
}

/// When the closed notch shows Claude.
enum ClaudeClosedNotchMode: String, CaseIterable, Identifiable, Sendable {
    /// Whenever a Claude Code session is open; it animates while Claude works.
    case whileOpen
    /// Only while Claude is working on a reply.
    case whileWorking
    case never

    var id: Self { self }

    var title: String {
        switch self {
        case .whileOpen: "While a session is open"
        case .whileWorking: "While Claude is working"
        case .never: "Never"
        }
    }
}

@MainActor
final class ClaudeSettings: ObservableObject {
    static let shared = ClaudeSettings()

    private enum Key {
        static let chatModel = "claude.chat.model"
        static let section = "claude.tab.section"
        static let closedNotch = "claude.closedNotch"
        static let announcesFinish = "claude.announcesFinish"
        static let warnsAboutLimits = "claude.warnsAboutLimits"
        static let contextWarningPercent = "claude.contextWarningPercent"
        static let limitWarningPercent = "claude.limitWarningPercent"
    }

    static let contextWarningChoices = [60, 70, 80, 90]
    static let limitWarningChoices = [70, 80, 90]

    @Published var chatModel: ClaudeChatModel {
        didSet { defaults.set(chatModel.rawValue, forKey: Key.chatModel) }
    }

    /// The section the tab shows; it reopens where it was left.
    @Published var section: ClaudeTabSection {
        didSet { defaults.set(section.rawValue, forKey: Key.section) }
    }

    /// When the closed notch shows Claude's mark.
    @Published var closedNotch: ClaudeClosedNotchMode {
        didSet { defaults.set(closedNotch.rawValue, forKey: Key.closedNotch) }
    }

    /// A short note under the closed notch when Claude finishes and it's the user's turn.
    @Published var announcesFinish: Bool {
        didSet { defaults.set(announcesFinish, forKey: Key.announcesFinish) }
    }

    /// A note under the closed notch when a session should be compacted soon or a plan
    /// limit is running out.
    @Published var warnsAboutLimits: Bool {
        didSet { defaults.set(warnsAboutLimits, forKey: Key.warnsAboutLimits) }
    }

    /// How full a session's context gets, as a share of where Claude Code compacts it on its
    /// own, before Notchy suggests compacting.
    @Published var contextWarningPercent: Int {
        didSet { defaults.set(contextWarningPercent, forKey: Key.contextWarningPercent) }
    }

    /// How much of the five-hour session or the week is used before Notchy warns.
    @Published var limitWarningPercent: Int {
        didSet { defaults.set(limitWarningPercent, forKey: Key.limitWarningPercent) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        chatModel = defaults.string(forKey: Key.chatModel).flatMap(ClaudeChatModel.init(rawValue:)) ?? .automatic
        section = defaults.string(forKey: Key.section).flatMap(ClaudeTabSection.init(rawValue:)) ?? .chat
        closedNotch = defaults.string(forKey: Key.closedNotch).flatMap(ClaudeClosedNotchMode.init(rawValue:)) ?? .whileOpen
        announcesFinish = defaults.object(forKey: Key.announcesFinish) as? Bool ?? true
        warnsAboutLimits = defaults.object(forKey: Key.warnsAboutLimits) as? Bool ?? true
        contextWarningPercent = Self.choice(defaults.object(forKey: Key.contextWarningPercent) as? Int, in: Self.contextWarningChoices, default: 80)
        limitWarningPercent = Self.choice(defaults.object(forKey: Key.limitWarningPercent) as? Int, in: Self.limitWarningChoices, default: 80)
    }

    private static func choice(_ value: Int?, in choices: [Int], default fallback: Int) -> Int {
        guard let value, choices.contains(value) else { return fallback }
        return value
    }
}
