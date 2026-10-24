import Combine

/// Shared by the settings window and its sidebar so shortcuts reuse the open window.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var selection: SettingsPane? = .general
    @Published var searchText = ""

    func select(_ pane: SettingsPane) {
        searchText = ""
        selection = pane
    }
}
