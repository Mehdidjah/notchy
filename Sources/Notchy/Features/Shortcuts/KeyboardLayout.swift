import AppKit
import Carbon.HIToolbox
import Combine

/// Translates virtual key codes into the glyphs a keyboard layout prints, with
/// `UCKeyTranslate`, and republishes when the user switches input source so every recorder
/// and menu re-renders its shortcut text.
///
/// Shortcut text comes from the current ASCII-capable layout, so a Russian or
/// Greek input source still reads ⇧⌘V, while in-app key equivalents follow the selected
/// layout.
///
/// Text Input Sources must be queried on the main thread, hence the main-actor isolation.
@MainActor
final class KeyboardLayout: ObservableObject {
    static let shared = KeyboardLayout()

    /// Bumped whenever the selected input source changes.
    @Published private(set) var revision = 0

    /// Which input source a glyph is read from.
    enum Source: Sendable {
        /// The current ASCII-capable layout: shortcut text in recorders, menus and footers.
        case asciiCapable
        /// The selected layout: SwiftUI and menu key equivalents.
        case current
    }

    private struct CacheKey: Hashable {
        let keyCode: UInt32
        let source: Source
    }

    private var cache: [CacheKey: String] = [:]
    private var observer: NSObjectProtocol?

    init() {}

    /// Starts listening for input-source switches. Safe to call more than once.
    func startObserving() {
        guard observer == nil else { return }
        let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        observer = DistributedNotificationCenter.default().addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidate() }
        }
    }

    func stopObserving() {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observer = nil
    }

    /// Drops cached glyphs, for example after the input source changed.
    func invalidate() {
        cache.removeAll()
        revision &+= 1
    }

    /// The glyph `keyCode` produces with no modifiers held, or nil when the layout yields
    /// nothing printable (dead keys, keypad clear, …).
    func character(for keyCode: UInt32, uppercased: Bool = true, source: Source = .asciiCapable) -> String? {
        let key = CacheKey(keyCode: keyCode, source: source)
        let base: String?
        if let cached = cache[key] {
            base = cached.isEmpty ? nil : cached
        } else {
            let translated = Self.translate(keyCode, source: source)
            cache[key] = translated ?? ""
            base = translated
        }
        guard let base else { return nil }
        guard uppercased else { return base }
        // Keep glyphs whose uppercase form changes length (ß → SS) as they are.
        let upper = base.uppercased()
        return upper.count == base.count ? upper : base
    }

    private static func translate(_ keyCode: UInt32, source: Source) -> String? {
        let data: Data?
        switch source {
        case .asciiCapable:
            data = layoutData(TISCopyCurrentASCIICapableKeyboardLayoutInputSource())
                ?? layoutData(TISCopyCurrentKeyboardLayoutInputSource())
        case .current:
            data = layoutData(TISCopyCurrentKeyboardLayoutInputSource())
                ?? layoutData(TISCopyCurrentASCIICapableKeyboardLayoutInputSource())
        }
        guard let data else { return nil }

        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let capacity = characters.count
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                UInt16(truncatingIfNeeded: keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                capacity,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: characters, count: length)
        let printable = text.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                && !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
        return printable ? text : nil
    }

    private static func layoutData(_ source: Unmanaged<TISInputSource>?) -> Data? {
        guard let source = source?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        return data as Data
    }
}
