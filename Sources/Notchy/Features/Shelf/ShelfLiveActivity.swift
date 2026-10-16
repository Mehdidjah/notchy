import Combine
import SwiftUI

/// Atoll's closed-notch shelf indicator: a tray glyph on the left wing and the item count on
/// the right, shown whenever the shelf holds something and nothing more urgent is showing.
@MainActor
final class ShelfLiveActivity: ClosedLiveActivity {
    let activityID = "shelf.count"
    let priority = ClosedActivityPriority.shelf

    private let store: ShelfStore
    private let settings: UserSettings?

    /// `settings` lets the indicator step aside when the Shelf tab is switched off.
    init(store: ShelfStore = .shared, settings: UserSettings? = nil) {
        self.store = store
        self.settings = settings
    }

    var isActivityVisible: Bool {
        !store.isEmpty && (settings?.showShelfTab ?? true)
    }

    var activityDidChange: AnyPublisher<Void, Never> {
        let items = store.$items.map { _ in () }
        guard let settings else { return items.eraseToAnyPublisher() }
        return items.merge(with: settings.$showShelfTab.map { _ in () }).eraseToAnyPublisher()
    }

    func leftWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(
            Image(systemName: "tray.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 4)
                .accessibilityHidden(true)
        )
    }

    func rightWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(ShelfCountWing(store: store))
    }
}

/// The count, bold and rounded, rolling to the new number when it changes.
private struct ShelfCountWing: View {
    @ObservedObject var store: ShelfStore

    var body: some View {
        Text("\(store.count)")
            .font(.system(.callout, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .contentTransition(.numericText(countsDown: false))
            .animation(.smooth(duration: 0.3), value: store.count)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, 4)
            .accessibilityLabel("\(store.count) items on the shelf")
    }
}
