import AppKit
import SwiftUI

/// Pointer and geometry state of the media views that the island itself has to respect.
///
/// The host reads the flags (see the integration notes on `MediaFeature`); the media views
/// write them.
@MainActor
final class MediaInteractionState: ObservableObject {
    static let shared = MediaInteractionState()

    /// Where the closed music activity sits on screen while its wings are drawn.
    struct ClosedWings: Equatable {
        /// Frame of the screen the island is on, in global coordinates.
        var screenFrame: NSRect
        /// Height of the closed notch.
        var closedHeight: CGFloat
        /// Width of the black centre over the hardware notch.
        var centerWidth: CGFloat
        /// Width of each wing.
        var wingWidth: CGFloat
    }

    /// True while the pointer rests on the closed spectrum with its play/pause glyph showing
    /// ("open on hover" off). A click there toggles playback and must not open the island
    /// (Atoll's `handleClosedMusicWaveformTapIfNeeded` runs before the open handler).
    @Published private(set) var claimsClosedClick = false
    /// True while the pointer is over the side lyrics panel, so scrolling the lyrics never
    /// reads as a swipe to close the island (Atoll's `setScrollGestureSuppression`).
    @Published private(set) var suppressesCloseGesture = false
    /// The closed music wings while they are on screen; nil when the island is open or
    /// another activity owns the closed notch.
    @Published private(set) var closedWings: ClosedWings?

    init() {}

    func setClaimsClosedClick(_ claims: Bool) {
        if claimsClosedClick != claims { claimsClosedClick = claims }
    }

    func setSuppressesCloseGesture(_ suppresses: Bool) {
        if suppressesCloseGesture != suppresses { suppressesCloseGesture = suppresses }
    }

    func setClosedWings(_ wings: ClosedWings?) {
        if closedWings != wings { closedWings = wings }
    }
}

// MARK: - Matched geometry

private struct MediaArtworkNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// The island's matched-geometry namespace. When the host sets it on the view that holds
    /// both the closed row and the open shell, the album art morphs from the closed wing into
    /// the open player and back, as Atoll's "albumArt" geometry group does.
    var mediaArtworkNamespace: Namespace.ID? {
        get { self[MediaArtworkNamespaceKey.self] }
        set { self[MediaArtworkNamespaceKey.self] = newValue }
    }
}

private struct MediaMatchedArtworkModifier: ViewModifier {
    @Environment(\.mediaArtworkNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: MediaMatchedArtworkModifier.geometryID, in: namespace)
        } else {
            content
        }
    }

    static let geometryID = "media.albumArt"
}

extension View {
    /// Joins the artwork to the island's album-art geometry group, when the host provides one.
    func mediaMatchedArtwork() -> some View {
        modifier(MediaMatchedArtworkModifier())
    }
}

// MARK: - Window probe

/// Reports the frame of the screen its window is on, so window-level helpers (the floating
/// controls) can place themselves beside the island.
struct MediaScreenReader: NSViewRepresentable {
    let onChange: @MainActor (NSRect?) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.onChange = onChange
        nsView.report()
    }

    final class ProbeView: NSView {
        var onChange: (@MainActor (NSRect?) -> Void)?
        private var lastFrame: NSRect?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        /// Reports on the next main-actor turn, never inside a SwiftUI view update.
        func report() {
            let frame = window?.screen?.frame
            guard frame != lastFrame else { return }
            lastFrame = frame
            let callback = onChange
            Task { @MainActor in callback?(frame) }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
