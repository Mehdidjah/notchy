import Combine
import Foundation

/// Which Apple Notes are brought into the island while sync is on.
enum AppleNotesSyncScope: String, CaseIterable, Identifiable, Sendable {
    /// Every note of the default Notes account (the default).
    case allNotes
    /// Only the notes inside the Notchy folder.
    case notchIslandFolder

    var id: Self { self }

    var displayName: String {
        switch self {
        case .allNotes: "All notes"
        case .notchIslandFolder: "Notchy folder only"
        }
    }
}

/// Preferences for the Notes tab, stored under `notes.*` in UserDefaults.
@MainActor
final class NotesSettings: ObservableObject {
    enum Key {
        static let pinningEnabled = "notes.enablePinning"
        static let searchEnabled = "notes.enableSearch"
        static let colorFilteringEnabled = "notes.enableColorFiltering"
        static let createFromClipboardEnabled = "notes.enableCreateFromClipboard"
        static let showsCharacterCount = "notes.showCharacterCount"
        static let showsClipboardBesideNotes = "notes.showClipboardBesideNotes"
        static let appleNotesSyncEnabled = "notes.appleNotesSync"
        static let appleNotesSyncScope = "notes.appleNotesSyncScope"
        static let appleNotesLastSyncDate = "notes.appleNotesLastSyncDate"
    }

    static let shared = NotesSettings()

    private let defaults: UserDefaults

    /// Hover pill offers pin / unpin.
    @Published var pinningEnabled: Bool {
        didSet { defaults.set(pinningEnabled, forKey: Key.pinningEnabled) }
    }
    /// Magnifier button and search field in the list header.
    @Published var searchEnabled: Bool {
        didSet { defaults.set(searchEnabled, forKey: Key.searchEnabled) }
    }
    /// Colour filter capsules under the search field.
    @Published var colorFilteringEnabled: Bool {
        didSet { defaults.set(colorFilteringEnabled, forKey: Key.colorFilteringEnabled) }
    }
    /// "Create from Clipboard" button in the list header.
    @Published var createFromClipboardEnabled: Bool {
        didSet { defaults.set(createFromClipboardEnabled, forKey: Key.createFromClipboardEnabled) }
    }
    /// Character counter in the editor's bottom-right corner.
    @Published var showsCharacterCount: Bool {
        didSet { defaults.set(showsCharacterCount, forKey: Key.showsCharacterCount) }
    }
    /// Split layout: the clipboard grid on the left of the notes (260-pt island).
    @Published var showsClipboardBesideNotes: Bool {
        didSet { defaults.set(showsClipboardBesideNotes, forKey: Key.showsClipboardBesideNotes) }
    }
    /// Two-way sync with the Notes app through AppleScript.
    @Published var appleNotesSyncEnabled: Bool {
        didSet { defaults.set(appleNotesSyncEnabled, forKey: Key.appleNotesSyncEnabled) }
    }
    @Published var appleNotesSyncScope: AppleNotesSyncScope {
        didSet { defaults.set(appleNotesSyncScope.rawValue, forKey: Key.appleNotesSyncScope) }
    }
    @Published var appleNotesLastSyncDate: Date? {
        didSet {
            if let appleNotesLastSyncDate {
                defaults.set(appleNotesLastSyncDate, forKey: Key.appleNotesLastSyncDate)
            } else {
                defaults.removeObject(forKey: Key.appleNotesLastSyncDate)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pinningEnabled = defaults.object(forKey: Key.pinningEnabled) as? Bool ?? true
        searchEnabled = defaults.object(forKey: Key.searchEnabled) as? Bool ?? false
        colorFilteringEnabled = defaults.object(forKey: Key.colorFilteringEnabled) as? Bool ?? false
        createFromClipboardEnabled = defaults.object(forKey: Key.createFromClipboardEnabled) as? Bool ?? true
        showsCharacterCount = defaults.object(forKey: Key.showsCharacterCount) as? Bool ?? true
        showsClipboardBesideNotes = defaults.object(forKey: Key.showsClipboardBesideNotes) as? Bool ?? false
        appleNotesSyncEnabled = defaults.object(forKey: Key.appleNotesSyncEnabled) as? Bool ?? false
        appleNotesSyncScope = AppleNotesSyncScope(
            rawValue: defaults.string(forKey: Key.appleNotesSyncScope) ?? ""
        ) ?? .allNotes
        appleNotesLastSyncDate = defaults.object(forKey: Key.appleNotesLastSyncDate) as? Date
    }

    /// The header's search button shows when either search or colour filtering is on.
    var showsSearchButton: Bool { searchEnabled || colorFilteringEnabled }
}
