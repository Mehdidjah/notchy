import AppKit
import Combine
import Foundation

/// Runs the system colour loupe. Abstracted so tests can hand back a colour without a screen.
@MainActor
protocol ScreenColorSampling {
    /// Resolves with the chosen colour, or nil when the user cancels the loupe.
    func sampleColor() async -> NSColor?
}

/// `NSColorSampler` shows the magnifying loupe and calls back on the main thread. A fresh
/// instance per session keeps it out of the actor's stored state.
@MainActor
final class SystemScreenColorSampler: ScreenColorSampling {
    func sampleColor() async -> NSColor? {
        await NSColorSampler().sample()
    }
}

/// The soft tap that confirms a pick; distinct from the island's alignment tick.
@MainActor
final class ColorPickerHaptic: HapticFeedbackPerforming {
    func perform() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }
}

/// Samples colours, keeps the recent-colour history, and copies formats to the pasteboard.
@MainActor
final class ColorPickerService: ObservableObject {
    static let shared = ColorPickerService()

    /// How many colours are kept on disk; the popover shows the first `settings.historySize`.
    static let maximumStoredColors = 50
    /// How long "Color Picked!" stays up after a pick.
    static let pickedFeedbackDuration: Duration = .seconds(2)

    /// Newest first.
    @Published private(set) var history: [PickedColor] = []
    /// True while the loupe is on screen.
    @Published private(set) var isPicking = false
    @Published private(set) var lastPickedColor: PickedColor?
    @Published private(set) var isShowingPickedFeedback = false
    /// The exact string most recently written to the pasteboard.
    @Published private(set) var lastCopiedValue: String?
    @Published private(set) var isPopoverPresented = false

    let settings: ColorPickerSettings

    /// Fires with the colour's `#RRGGBB` hex after any copy, so the host can record the colour
    /// in its clipboard history.
    var onColorCopied: ((String) -> Void)?
    /// Fires after a successful screen sample, before the copy callback.
    var onColorPicked: ((PickedColor) -> Void)?
    /// Fires when the header popover opens or closes; the host uses it to hold the island open
    /// while the pointer is inside the popover's own window.
    var onPopoverPresentationChanged: ((Bool) -> Void)?
    /// Whether to play the pick haptic. Defaults to the island's own haptics preference.
    var hapticsEnabled: () -> Bool

    private let defaults: UserDefaults
    private let sampler: any ScreenColorSampling
    private let pasteboard: any PasteboardWriting
    private let haptics: any HapticFeedbackPerforming
    private var pickTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?

    init(
        settings: ColorPickerSettings? = nil,
        defaults: UserDefaults = .standard,
        sampler: (any ScreenColorSampling)? = nil,
        pasteboard: (any PasteboardWriting)? = nil,
        haptics: (any HapticFeedbackPerforming)? = nil
    ) {
        self.defaults = defaults
        self.settings = settings
            ?? (defaults === UserDefaults.standard ? ColorPickerSettings.shared : ColorPickerSettings(defaults: defaults))
        self.sampler = sampler ?? SystemScreenColorSampler()
        self.pasteboard = pasteboard ?? PasteboardService()
        self.haptics = haptics ?? ColorPickerHaptic()
        hapticsEnabled = { defaults.object(forKey: "notch.hapticsEnabled") as? Bool ?? true }
        history = Self.loadHistory(from: defaults)
    }

    /// The colours the popover grid shows.
    var recentColors: [PickedColor] {
        Array(history.prefix(settings.historySize))
    }

    // MARK: Picking

    /// Shows the loupe. On a pick the colour goes to the front of the history, the default
    /// format is copied, a haptic plays and the feedback flag is raised for two seconds.
    /// Cancelling the loupe (Escape) changes nothing.
    func pick() {
        guard settings.isEnabled, !isPicking else { return }
        isPicking = true
        pickTask?.cancel()
        pickTask = Task { @MainActor [weak self, sampler] in
            let sampled = await sampler.sampleColor()
            guard let self, !Task.isCancelled else { return }
            self.isPicking = false
            guard let sampled, let color = PickedColor(nsColor: sampled) else { return }
            self.accept(color)
        }
    }

    /// Records a colour as if it had just been sampled.
    func accept(_ color: PickedColor) {
        insert(color)
        lastPickedColor = color
        onColorPicked?(color)
        copy(color, as: settings.defaultFormat, haptic: true)
        showPickedFeedback()
    }

    // MARK: Copying

    /// Writes one format of the colour to the pasteboard and reports the colour's hex.
    @discardableResult
    func copy(_ color: PickedColor, as format: PickedColorFormat, haptic: Bool = false) -> Bool {
        let value = color.formatted(as: format)
        guard pasteboard.copy(value) else { return false }
        lastCopiedValue = value
        if haptic, hapticsEnabled() { haptics.perform() }
        onColorCopied?(color.hexString)
        return true
    }

    // MARK: History

    func remove(_ color: PickedColor) {
        history.removeAll { $0.id == color.id }
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    /// Re-picking a colour moves it to the front instead of adding a twin swatch.
    private func insert(_ color: PickedColor) {
        history.removeAll { $0.id == color.id || $0.looksLike(color) }
        history.insert(color, at: 0)
        if history.count > Self.maximumStoredColors {
            history.removeLast(history.count - Self.maximumStoredColors)
        }
        saveHistory()
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: ColorPickerSettings.Key.history)
    }

    private static func loadHistory(from defaults: UserDefaults) -> [PickedColor] {
        guard let data = defaults.data(forKey: ColorPickerSettings.Key.history),
              let stored = try? JSONDecoder().decode([PickedColor].self, from: data) else { return [] }
        return Array(stored.prefix(maximumStoredColors))
    }

    // MARK: Presentation

    func setPopoverPresented(_ presented: Bool) {
        guard presented != isPopoverPresented else { return }
        isPopoverPresented = presented
        onPopoverPresentationChanged?(presented)
    }

    private func showPickedFeedback() {
        feedbackTask?.cancel()
        isShowingPickedFeedback = true
        feedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.pickedFeedbackDuration)
            guard !Task.isCancelled else { return }
            self?.isShowingPickedFeedback = false
        }
    }
}
