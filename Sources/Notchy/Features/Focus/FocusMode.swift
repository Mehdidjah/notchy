import AppKit
import SwiftUI

/// The built-in Focus modes, keyed by the identifiers macOS uses for them.
enum FocusModeKind: String, CaseIterable, Sendable {
    case doNotDisturb = "com.apple.donotdisturb.mode"
    case work = "com.apple.focus.work"
    case personal = "com.apple.focus.personal"
    case sleep = "com.apple.focus.sleep"
    case driving = "com.apple.focus.driving"
    case fitness = "com.apple.focus.fitness"
    case gaming = "com.apple.focus.gaming"
    case mindfulness = "com.apple.focus.mindfulness"
    case reading = "com.apple.focus.reading"
    case reduceInterruptions = "com.apple.focus.reduce-interruptions"
    case custom = "com.apple.focus.custom"
    case unknown = ""

    var displayName: String {
        switch self {
        case .doNotDisturb: "Do Not Disturb"
        case .work: "Work"
        case .personal: "Personal"
        case .sleep: "Sleep"
        case .driving: "Driving"
        case .fitness: "Fitness"
        case .gaming: "Gaming"
        case .mindfulness: "Mindfulness"
        case .reading: "Reading"
        case .reduceInterruptions: "Reduce Interr."
        case .custom: "Focus"
        case .unknown: "Focus Mode"
        }
    }

    /// Public SF Symbols, best first. Atoll draws Work, Mindfulness and Gaming with private
    /// system glyphs (person.lanyardcard.fill, apple.mindfulness, rocket.fill) through a
    /// private SwiftUI initialiser; these are the closest public symbols.
    var symbolCandidates: [String] {
        switch self {
        case .doNotDisturb, .unknown: ["moon.fill"]
        case .work: ["lanyardcard.fill", "briefcase.fill"]
        case .personal: ["person.fill"]
        case .sleep: ["bed.double.fill"]
        case .driving: ["car.fill"]
        case .fitness: ["figure.run"]
        case .gaming: ["gamecontroller.fill"]
        case .mindfulness: ["circle.hexagongrid"]
        case .reading: ["book.closed.fill"]
        case .reduceInterruptions: ["apple.intelligence", "sparkles"]
        case .custom: ["app.badge"]
        }
    }

    @MainActor
    var symbolName: String { FocusSymbols.first(available: symbolCandidates) ?? "moon.fill" }

    /// The outline glyph shown, in white, while Focus is turning off.
    @MainActor
    var inactiveSymbolName: String {
        self == .doNotDisturb ? "moon.circle.fill" : symbolName
    }

    var accentColor: Color {
        switch self {
        case .doNotDisturb, .unknown: Color(red: 0.370, green: 0.360, blue: 0.902)
        case .work: Color(red: 0.414, green: 0.769, blue: 0.863)
        case .personal: Color(red: 0.748, green: 0.354, blue: 0.948)
        case .sleep: Color(red: 0.341, green: 0.384, blue: 0.980)
        case .driving: Color(red: 0.988, green: 0.561, blue: 0.153)
        case .fitness: Color(red: 0.176, green: 0.804, blue: 0.459)
        case .gaming: Color(red: 0.043, green: 0.518, blue: 1.000)
        case .mindfulness: Color(red: 0.361, green: 0.898, blue: 0.883)
        case .reading: Color(red: 1.000, green: 0.622, blue: 0.044)
        case .reduceInterruptions: Color(red: 0.686, green: 0.322, blue: 0.871)
        case .custom: .indigo
        }
    }

    /// Maps an identifier from a notification, the Focus database or the unified log.
    init(identifier: String) {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard !trimmed.isEmpty else {
            self = .doNotDisturb
            return
        }
        if let exact = FocusModeKind(rawValue: trimmed) ?? FocusModeKind(rawValue: lower), exact != .unknown {
            self = exact
            return
        }
        // duetexpertd reports the Sleep focus under its own domain.
        if lower == "com.apple.sleep.sleep-mode" {
            self = .sleep
            return
        }
        // User-made modes are `com.apple.donotdisturb.mode.<suffix>`; `.default` is plain DND.
        let customPrefix = "com.apple.donotdisturb.mode."
        if lower.hasPrefix(customPrefix) {
            let suffix = lower.dropFirst(customPrefix.count)
            if !suffix.isEmpty, suffix != "default" {
                self = .custom
                return
            }
        }
        if let prefixed = FocusModeKind.allCases.first(where: { !$0.rawValue.isEmpty && lower.hasPrefix($0.rawValue) }) {
            self = prefixed
            return
        }
        self = lower.hasPrefix("com.apple.focus") ? .custom : .doNotDisturb
    }

    /// Resolves a mode from whatever metadata is available, names first.
    static func resolve(identifier: String?, name: String?) -> FocusModeKind {
        if let name, !name.isEmpty {
            if let match = allCases.first(where: {
                !$0.displayName.isEmpty
                    && $0.displayName.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                return match
            }
            switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "work": return .work
            case "personal", "personal-time": return .personal
            case "sleep", "sleep-mode": return .sleep
            case "driving": return .driving
            case "fitness": return .fitness
            case "gaming": return .gaming
            case "mindfulness": return .mindfulness
            case "reading": return .reading
            case "reduce-interruptions", "reduce interruptions": return .reduceInterruptions
            case "do not disturb", "dnd", "donotdisturb", "do-not-disturb", "default": return .doNotDisturb
            default: break
            }
        }
        if let identifier, !identifier.isEmpty {
            return FocusModeKind(identifier: identifier)
        }
        // A name that matched nothing is most likely a localized or user-made mode.
        if let name, !name.isEmpty { return .custom }
        return .doNotDisturb
    }

    /// Normalizes a raw name from a notification or the log into the label Atoll shows.
    static func normalizedName(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "work": "Work"
        case "personal", "personal-time": "Personal"
        case "reduce-interruptions": "Reduce Interruptions"
        case "sleep", "sleep-mode": "Sleep"
        case "driving": "Driving"
        case "default", "dnd", "do-not-disturb", "do not disturb", "donotdisturb": "Do Not Disturb"
        default: raw
        }
    }
}

/// How a Focus mode is drawn: glyph and accent colour.
struct FocusAppearance: Equatable {
    var kind: FocusModeKind
    var symbolName: String
    var inactiveSymbolName: String
    var accent: Color

    @MainActor
    init(kind: FocusModeKind, configuration: FocusModeConfiguration? = nil) {
        self.kind = kind
        if kind == .custom {
            let symbol = configuration?.symbolName.flatMap { FocusSymbols.first(available: [$0]) } ?? "app.badge"
            symbolName = symbol
            inactiveSymbolName = symbol
            accent = configuration?.tintColorName.map(FocusTint.color(named:)) ?? .indigo
        } else {
            symbolName = kind.symbolName
            inactiveSymbolName = kind.inactiveSymbolName
            accent = kind.accentColor
        }
    }
}

/// Maps the system colour names stored in the Focus database ("systemTealColor") to colours.
enum FocusTint {
    static func color(named name: String) -> Color {
        let key = name.lowercased()
            .replacingOccurrences(of: "system", with: "")
            .replacingOccurrences(of: "color", with: "")
        switch key {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "cyan": return .cyan
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "gray", "grey": return .gray
        default: return .indigo
        }
    }
}

/// Checks symbol names through the public `NSImage(systemSymbolName:)` lookup.
@MainActor
enum FocusSymbols {
    private static var cache: [String: Bool] = [:]

    static func isAvailable(_ name: String) -> Bool {
        if let known = cache[name] { return known }
        let available = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        cache[name] = available
        return available
    }

    static func first(available candidates: [String]) -> String? {
        candidates.first(where: isAvailable)
    }
}
