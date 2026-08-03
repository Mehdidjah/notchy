import Foundation

enum NotchState: String, CaseIterable, Codable, Sendable {
    case disabled
    case idle
    case hoverArmed
    case peeking
    case expanded
    case searchFocused
    case previewing
    case multiSelecting
    case dragging
    case pinnedOpen
    case closing
    case retractedForFullscreen

    var isVisible: Bool {
        switch self {
        case .peeking, .expanded, .searchFocused, .previewing, .multiSelecting,
             .dragging, .pinnedOpen, .closing:
            true
        case .disabled, .idle, .hoverArmed, .retractedForFullscreen:
            false
        }
    }

    var showsShelfContent: Bool {
        switch self {
        case .expanded, .searchFocused, .previewing, .multiSelecting, .dragging, .pinnedOpen:
            true
        case .disabled, .idle, .hoverArmed, .peeking, .closing, .retractedForFullscreen:
            false
        }
    }

    var preventsAutomaticClose: Bool {
        switch self {
        case .searchFocused, .previewing, .multiSelecting, .dragging, .pinnedOpen:
            true
        default:
            false
        }
    }
}

enum NotchEvent: Sendable, Equatable {
    case enable
    case disable
    case pointerEntered
    case pointerExited
    case dwellElapsed
    case peekElapsed
    case closeDelayElapsed
    case closeAnimationElapsed
    case openPinned
    case pin
    case unpin
    case focusSearch
    case blurSearch
    case openPreview
    case closePreview
    case beginMultiSelect
    case endMultiSelect
    case beginDrag
    case endDrag
    case escape
    case fullscreenEntered
    case fullscreenExited
}

struct NotchTransition: Equatable, Sendable {
    let from: NotchState
    let event: NotchEvent
    let to: NotchState
    let wasAccepted: Bool
}

struct NotchStateMachine: Sendable {
    private(set) var state: NotchState
    private var stateBeforeRetraction: NotchState = .idle

    init(initialState: NotchState = .idle) {
        state = initialState
    }

    @discardableResult
    mutating func send(_ event: NotchEvent) -> NotchTransition {
        let previous = state
        let next = destination(from: previous, event: event)
        if next != previous || acceptsNoStateChange(event, in: previous) {
            if event == .fullscreenEntered, previous != .retractedForFullscreen {
                stateBeforeRetraction = previous
            }
            state = next
            return NotchTransition(from: previous, event: event, to: next, wasAccepted: true)
        }
        return NotchTransition(from: previous, event: event, to: previous, wasAccepted: false)
    }

    private func destination(from state: NotchState, event: NotchEvent) -> NotchState {
        if event == .disable { return .disabled }
        if event == .fullscreenEntered, state != .disabled { return .retractedForFullscreen }
        if state == .retractedForFullscreen {
            guard event == .fullscreenExited else { return state }
            return stateBeforeRetraction == .pinnedOpen ? .pinnedOpen : .idle
        }

        return switch (state, event) {
        case (.disabled, .enable): .idle
        case (.idle, .pointerEntered): .hoverArmed
        case (.idle, .openPinned): .pinnedOpen
        case (.hoverArmed, .pointerExited): .idle
        case (.hoverArmed, .dwellElapsed): .expanded
        case (.hoverArmed, .openPinned): .pinnedOpen
        case (.peeking, .peekElapsed): .expanded
        case (.peeking, .pointerExited): .closing
        case (.peeking, .openPinned): .pinnedOpen
        case (.expanded, .focusSearch): .searchFocused
        case (.expanded, .openPreview): .previewing
        case (.expanded, .beginMultiSelect): .multiSelecting
        case (.expanded, .beginDrag): .dragging
        case (.expanded, .pin): .pinnedOpen
        case (.expanded, .closeDelayElapsed): .closing
        case (.searchFocused, .blurSearch): .expanded
        case (.searchFocused, .escape): .expanded
        case (.previewing, .closePreview): .expanded
        case (.previewing, .escape): .expanded
        case (.multiSelecting, .endMultiSelect): .expanded
        case (.multiSelecting, .escape): .expanded
        case (.dragging, .endDrag): .expanded
        case (.pinnedOpen, .unpin): .expanded
        case (.pinnedOpen, .escape): .closing
        case (.closing, .pointerEntered): .hoverArmed
        case (.closing, .openPinned): .pinnedOpen
        case (.closing, .closeAnimationElapsed): .idle
        case (.expanded, .escape): .closing
        default: state
        }
    }

    private func acceptsNoStateChange(_ event: NotchEvent, in state: NotchState) -> Bool {
        switch (state, event) {
        case (.idle, .pointerExited), (.expanded, .pointerEntered), (.pinnedOpen, .pointerExited):
            true
        default:
            false
        }
    }
}
