import SwiftUI

/// The Home tab, laid out as in Atoll: `HStack(alignment: .top, spacing: 20)` of the media
/// player, the calendar (compact beside a player, standalone month view otherwise) and the
/// camera mirror, inside an 8-pt outer padding. Content fades and slides from the top as the
/// island opens.
struct NotchHomeTabView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject private var layout = HomeLayoutState.shared

    var body: some View {
        Group {
            if layout.hasContent {
                HStack(alignment: .top, spacing: 20) {
                    if layout.showsMediaPlayer {
                        HomeMediaSlot(model: model)
                    }
                    if layout.showsCalendar {
                        HomeCalendarSlot(model: model, compact: layout.showsMediaPlayer)
                            .frame(maxWidth: .infinity)
                    }
                    if layout.showsMirror {
                        HomeMirrorSlot(model: model)
                    }
                }
            } else {
                HomeEmptyView()
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transition(.opacity.animation(.smooth.speed(0.9)).combined(with: .move(edge: .top)))
    }
}

private struct HomeEmptyView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note.house")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("Nothing playing")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Play something in Music or Spotify, or turn on the calendar in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
