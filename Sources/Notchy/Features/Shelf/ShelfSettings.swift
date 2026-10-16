import Combine
import Foundation
import SwiftUI

/// Where the square drop target on the left of the shelf sends files.
enum ShelfShareTarget: String, CaseIterable, Codable, Identifiable, Sendable {
    case airDrop
    case shareMenu

    var id: Self { self }

    var label: String {
        switch self {
        case .airDrop: "AirDrop"
        case .shareMenu: "Share Menu"
        }
    }

    var symbolName: String {
        switch self {
        case .airDrop: "airplayaudio"
        case .shareMenu: "square.and.arrow.up"
        }
    }
}

/// Shelf preferences, stored under `shelf.*` in UserDefaults.
@MainActor
final class ShelfSettings: ObservableObject {
    static let shared = ShelfSettings()

    private enum Key {
        static let opensOnDrag = "shelf.openOnDrag"
        static let allowsMoveOnDragOut = "shelf.allowMoveOnDragOut"
        static let removesAfterDragOut = "shelf.removeAfterDragOut"
        static let shareTarget = "shelf.shareTarget"
    }

    private let defaults: UserDefaults

    /// Dragging files over the closed notch opens the island on the Shelf tab.
    @Published var opensOnDrag: Bool {
        didSet { defaults.set(opensOnDrag, forKey: Key.opensOnDrag) }
    }
    /// Off by default: offering a move lets Finder relocate the original when the drop lands
    /// on the same volume, which reads as data loss. Off, drags out of the shelf only copy.
    @Published var allowsMoveOnDragOut: Bool {
        didSet { defaults.set(allowsMoveOnDragOut, forKey: Key.allowsMoveOnDragOut) }
    }
    /// Drop a tile into another app and it leaves the shelf.
    @Published var removesAfterDragOut: Bool {
        didSet { defaults.set(removesAfterDragOut, forKey: Key.removesAfterDragOut) }
    }
    @Published var shareTarget: ShelfShareTarget {
        didSet { defaults.set(shareTarget.rawValue, forKey: Key.shareTarget) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        opensOnDrag = defaults.object(forKey: Key.opensOnDrag) as? Bool ?? true
        allowsMoveOnDragOut = defaults.bool(forKey: Key.allowsMoveOnDragOut)
        removesAfterDragOut = defaults.bool(forKey: Key.removesAfterDragOut)
        shareTarget = ShelfShareTarget(rawValue: defaults.string(forKey: Key.shareTarget) ?? "") ?? .airDrop
    }
}

/// Form rows for the Settings window. Drop it inside an existing `Form`.
struct ShelfSettingsSection: View {
    @ObservedObject var settings: ShelfSettings

    init(settings: ShelfSettings = .shared) {
        self.settings = settings
    }

    var body: some View {
        Section("Shelf") {
            Toggle("Open shelf when files are dragged to the notch", isOn: $settings.opensOnDrag)
            Toggle("Allow moving files when dragging out", isOn: $settings.allowsMoveOnDragOut)
            Text("Off, items dragged out of the shelf are always copied. On, the receiving app may move the original file instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Remove from shelf after dragging out", isOn: $settings.removesAfterDragOut)
            Picker("Quick share with", selection: $settings.shareTarget) {
                ForEach(ShelfShareTarget.allCases) { target in
                    Text(target.label).tag(target)
                }
            }
        }
    }
}
