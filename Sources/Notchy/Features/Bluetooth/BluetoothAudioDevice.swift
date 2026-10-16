import AppKit
import Foundation

/// The family of a Bluetooth audio device, which picks its symbol in the HUD.
enum BluetoothAudioDeviceKind: String, CaseIterable, Sendable {
    case airpods
    case airpodsGen3
    case airpodsGen4
    case airpodsPro
    case airpodsPro3
    case airpodsMax
    case beats
    case beatsStudio
    case beatsSolo
    case headphones
    case speaker
    case generic

    /// SF Symbols to try, best first; newer names fall back to ones macOS 14 ships.
    var symbolCandidates: [String] {
        switch self {
        case .airpods: ["airpods"]
        case .airpodsGen3: ["airpods.gen3", "airpods"]
        case .airpodsGen4: ["airpods.gen4", "airpods.gen3", "airpods"]
        case .airpodsPro: ["airpods.pro", "airpodspro"]
        case .airpodsPro3: ["airpods.pro", "airpodspro"]
        case .airpodsMax: ["airpods.max", "airpodsmax", "headphones"]
        case .beats, .beatsStudio, .beatsSolo: ["beats.headphones", "headphones"]
        case .headphones: ["headphones"]
        case .speaker: ["hifispeaker.fill", "hifispeaker"]
        // No dedicated symbol exists for this kind, so the HUD falls back to this one.
        case .generic: ["dot.radiowaves.left.and.right"]
        }
    }

    /// The first candidate symbol this system has.
    var systemImage: String {
        symbolCandidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
            ?? "dot.radiowaves.left.and.right"
    }

    var displayName: String {
        switch self {
        case .airpods: "AirPods"
        case .airpodsGen3: "AirPods (Gen 3)"
        case .airpodsGen4: "AirPods (Gen 4)"
        case .airpodsPro: "AirPods Pro"
        case .airpodsPro3: "AirPods Pro 3"
        case .airpodsMax: "AirPods Max"
        case .beats: "Beats"
        case .beatsStudio: "Beats Studio"
        case .beatsSolo: "Beats Solo"
        case .headphones: "Headphones"
        case .speaker: "Speaker"
        case .generic: "Bluetooth Device"
        }
    }

    var isAirPods: Bool {
        switch self {
        case .airpods, .airpodsGen3, .airpodsGen4, .airpodsPro, .airpodsPro3, .airpodsMax: true
        default: false
        }
    }

    /// Apple product IDs of AirPods and Beats models, as published in their PnP records.
    static let appleProductIDs: [UInt16: BluetoothAudioDeviceKind] = [
        0x2002: .airpods,
        0x200F: .airpods,
        0x2013: .airpodsGen3,
        0x2019: .airpodsGen4,
        0x201B: .airpodsGen4,
        0x200A: .airpodsMax,
        0x201F: .airpodsMax,
        0x200E: .airpodsPro,
        0x2014: .airpodsPro,
        0x2024: .airpodsPro,
        0x2027: .airpodsPro3,
        0x2017: .beatsStudio,
        0x2009: .beatsStudio,
        0x2006: .beatsSolo,
        0x200C: .beatsSolo
    ]

    /// Classifies a device: Apple product ID first, then the name, then
    /// the Bluetooth class-of-device minor class.
    static func detect(name: String, classOfDevice: UInt32, appleProductID: UInt16? = nil) -> BluetoothAudioDeviceKind {
        if let appleProductID, let kind = appleProductIDs[appleProductID] {
            return kind
        }
        let lowercased = name.lowercased()
        if lowercased.contains("airpods") {
            if lowercased.contains("max") { return .airpodsMax }
            if lowercased.contains("pro") {
                return lowercased.contains("3") ? .airpodsPro3 : .airpodsPro
            }
            if ["gen 4", "gen4", "4th", "airpods 4", "airpods4"].contains(where: { lowercased.contains($0) }) {
                return .airpodsGen4
            }
            if ["gen 3", "gen3", "3rd", "third", "airpods 3", "airpods3"].contains(where: { lowercased.contains($0) }) {
                return .airpodsGen3
            }
            return .airpods
        }
        if lowercased.contains("beats") {
            return lowercased.contains("studio") ? .beatsStudio : .beatsSolo
        }
        if lowercased.contains("speaker") || lowercased.contains("boombox") {
            return .speaker
        }
        if ["headphone", "headset", "buds", "earbuds"].contains(where: { lowercased.contains($0) }) {
            return .headphones
        }
        switch (classOfDevice >> 2) & 0x3F {
        case 0x01, 0x02, 0x06: return .headphones // wearable headset, hands-free, headphones
        case 0x08, 0x0C: return .speaker // portable audio, loudspeaker
        default: return .generic
        }
    }
}

/// A connected Bluetooth audio device.
struct BluetoothAudioDevice: Identifiable, Equatable, Sendable {
    /// The device address as IOBluetooth formats it (for example `aa-bb-cc-dd-ee-ff`).
    let address: String
    let name: String
    let kind: BluetoothAudioDeviceKind

    var id: String { address }

    /// Lower-case hex digits only, so `AA:BB:…` and `aa-bb-…` compare equal.
    static func normalizedAddress(_ address: String) -> String {
        String(address.lowercased().filter(\.isHexDigit))
    }
}
