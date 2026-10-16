import Combine
import Foundation

/// Preferences for the colour picker, stored under `colorPicker.*` in UserDefaults.
@MainActor
final class ColorPickerSettings: ObservableObject {
    enum Key {
        static let isEnabled = "colorPicker.enabled"
        static let showHeaderButton = "colorPicker.showHeaderButton"
        static let defaultFormat = "colorPicker.defaultFormat"
        static let historySize = "colorPicker.historySize"
        static let showAllFormats = "colorPicker.showAllFormats"
        /// JSON-encoded `[PickedColor]`, written by `ColorPickerService`.
        static let history = "colorPicker.history"
    }

    /// How many recent colours the popover grid offers.
    static let historySizeChoices = [5, 10, 15, 20]
    static let defaultHistorySize = 10

    static let shared = ColorPickerSettings()

    private let defaults: UserDefaults

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }
    @Published var showHeaderButton: Bool {
        didSet { defaults.set(showHeaderButton, forKey: Key.showHeaderButton) }
    }
    /// The format copied to the pasteboard the moment a colour is picked.
    @Published var defaultFormat: PickedColorFormat {
        didSet { defaults.set(defaultFormat.rawValue, forKey: Key.defaultFormat) }
    }
    @Published var historySize: Int {
        didSet { defaults.set(historySize, forKey: Key.historySize) }
    }
    /// Off shows only the HEX row under a selected swatch.
    @Published var showAllFormats: Bool {
        didSet { defaults.set(showAllFormats, forKey: Key.showAllFormats) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? true
        showHeaderButton = defaults.object(forKey: Key.showHeaderButton) as? Bool ?? true
        defaultFormat = PickedColorFormat(rawValue: defaults.string(forKey: Key.defaultFormat) ?? "") ?? .hex
        let storedSize = defaults.object(forKey: Key.historySize) as? Int ?? Self.defaultHistorySize
        historySize = Self.historySizeChoices.contains(storedSize) ? storedSize : Self.defaultHistorySize
        showAllFormats = defaults.object(forKey: Key.showAllFormats) as? Bool ?? true
    }
}
