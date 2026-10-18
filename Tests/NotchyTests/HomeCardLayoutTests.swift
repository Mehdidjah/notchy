import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Notchy

struct HomeCardLayoutTests {
    private let height: CGFloat = 148

    private func widths(_ slots: [HomeCardSlot]) -> [HomeCardKind: CGFloat] {
        Dictionary(uniqueKeysWithValues: slots.map { ($0.kind, $0.width) })
    }

    private func rowWidth(_ slots: [HomeCardSlot]) -> CGFloat {
        slots.reduce(0) { $0 + $1.width } + HomeCardLayout.spacing * CGFloat(max(0, slots.count - 1))
    }

    @Test func cardsKeepTheirDisplayOrderAndFixedWidths() {
        let slots = HomeCardLayout.plan([.calendar, .media, .timer], width: 782, height: height)
        #expect(slots.map(\.kind) == [.timer, .media, .calendar])
        #expect(widths(slots)[.timer] == 130)
        #expect(widths(slots)[.calendar] == 130)
        // Spare room goes to the player, up to its maximum.
        #expect(widths(slots)[.media] == 384)
        #expect(rowWidth(slots) <= 782)
    }

    @Test func anIdleTimerIsLeftOutBeforeTheMirror() {
        let kinds: Set<HomeCardKind> = [.timer, .media, .calendar, .mirror]
        let idle = HomeCardLayout.plan(kinds, width: 600, height: height)
        #expect(idle.map(\.kind) == [.media, .calendar, .mirror])
        #expect(widths(idle)[.media] == 306)

        let running = HomeCardLayout.plan(kinds, width: 600, height: height, timerRunning: true)
        #expect(running.map(\.kind) == [.timer, .media, .calendar])
        #expect(widths(running)[.media] == 324)
    }

    @Test func aCrowdedRowNarrowsTheLyricsBeforeThePlayer() {
        let slots = HomeCardLayout.plan([.media, .lyrics, .calendar], width: 560, height: height)
        #expect(slots.map(\.kind) == [.media, .lyrics, .calendar])
        #expect(widths(slots)[.lyrics] == 162)
        #expect(widths(slots)[.media] == 251)
        #expect(rowWidth(slots) <= 560)
    }

    @Test func aPreferredWidthCapsTheCardWithinItsRange() {
        let preferred = HomeCardLayout.plan([.media, .lyrics], width: 900, height: height, preferredWidths: [.lyrics: 300])
        #expect(widths(preferred)[.lyrics] == 300)
        #expect(widths(preferred)[.media] == 384)
        let tooWide = HomeCardLayout.plan([.lyrics], width: 900, height: height, preferredWidths: [.lyrics: 1_000])
        #expect(widths(tooWide)[.lyrics] == 355)
        let tooNarrow = HomeCardLayout.plan([.lyrics], width: 900, height: height, preferredWidths: [.lyrics: 50])
        #expect(widths(tooNarrow)[.lyrics] == 162)
    }

    @Test func nothingIsPlannedWithoutRoomOrCards() {
        #expect(HomeCardLayout.plan([], width: 782, height: height).isEmpty)
        #expect(HomeCardLayout.plan([.media], width: 0, height: height).isEmpty)
        #expect(HomeCardLayout.plan([.media], width: 782, height: 0).isEmpty)
        #expect(HomeCardLayout.plan([.media], width: 100, height: height).isEmpty)
    }

    @Test func theRowNeverOverflows() {
        let kinds = Set(HomeCardKind.allCases)
        for width in stride(from: CGFloat(120), through: 1_000, by: 10) {
            for running in [false, true] {
                let slots = HomeCardLayout.plan(kinds, width: width, height: height, timerRunning: running)
                #expect(rowWidth(slots) <= width, "width \(width)")
                for slot in slots {
                    #expect(slot.width >= HomeCardLayout.widthRange(for: slot.kind, height: height).minimum.rounded(.down))
                }
            }
        }
    }

    @Test func timerEdgeStartsAtTheTopCentre() {
        let rect = CGRect(x: 0, y: 0, width: 130, height: 148)
        let path = HomeTimerEdge(cornerRadius: 18, inset: 1.5).path(in: rect)
        #expect(path.currentPoint == CGPoint(x: 65, y: 1.5))
        #expect(path.boundingRect.insetBy(dx: -0.01, dy: -0.01).contains(rect.insetBy(dx: 1.5, dy: 1.5)))
    }

    @MainActor @Test func timerCardSettingPersists() {
        let suite = "notchy.home-widgets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = HomeWidgetSettings(defaults: defaults)
        #expect(settings.timerCard == .always)
        settings.timerCard = .whileRunning
        #expect(HomeWidgetSettings(defaults: defaults).timerCard == .whileRunning)

        #expect(HomeWidgetSettings.TimerCard.always.isShown(timerActive: false))
        #expect(!HomeWidgetSettings.TimerCard.whileRunning.isShown(timerActive: false))
        #expect(HomeWidgetSettings.TimerCard.whileRunning.isShown(timerActive: true))
        #expect(!HomeWidgetSettings.TimerCard.off.isShown(timerActive: true))
    }
}
