import AppKit
import Foundation
import SwiftUI

/// An sRGB colour stored as plain numbers so a preset can be encoded to UserDefaults.
struct TimerColorComponents: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Reads the sRGB components of a SwiftUI colour. Colours that cannot be converted
    /// (for example pattern colours) fall back to white.
    init(color: Color) {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(
            red: Double(nsColor.redComponent),
            green: Double(nsColor.greenComponent),
            blue: Double(nsColor.blueComponent),
            alpha: Double(nsColor.alphaComponent)
        )
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// System colours as they render in the light appearance, so the defaults look the
    /// same on every machine without going through AppKit at type-initialisation time.
    static let systemOrange = TimerColorComponents(red: 1.0, green: 0.584, blue: 0.0)
    static let systemGreen = TimerColorComponents(red: 0.157, green: 0.804, blue: 0.255)
    static let systemPurple = TimerColorComponents(red: 0.686, green: 0.322, blue: 0.871)
    static let systemBlue = TimerColorComponents(red: 0.0, green: 0.478, blue: 1.0)
}

/// Hours, minutes and seconds of a duration, for the entry fields.
struct TimerDurationComponents: Equatable, Sendable {
    var hours: Int
    var minutes: Int
    var seconds: Int

    init(hours: Int = 0, minutes: Int = 0, seconds: Int = 0) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
    }

    init(duration: TimeInterval) {
        let total = max(0, Int(duration.rounded(.down)))
        hours = total / 3_600
        minutes = (total % 3_600) / 60
        seconds = total % 60
    }

    var duration: TimeInterval {
        TimeInterval(hours * 3_600 + minutes * 60 + seconds)
    }
}

/// A named countdown the user can start with one click.
struct TimerPreset: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var duration: TimeInterval
    var colorComponents: TimerColorComponents

    init(id: UUID = UUID(), name: String, duration: TimeInterval, colorComponents: TimerColorComponents) {
        self.id = id
        self.name = name
        self.duration = duration
        self.colorComponents = colorComponents
    }

    var color: Color { colorComponents.color }

    /// "25:00" for durations under an hour, "1:30:00" otherwise, with padded fields.
    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3_600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        formatter.unitsStyle = .positional
        return formatter.string(from: max(0, duration)) ?? "0:00"
    }

    static let defaultPresets: [TimerPreset] = [
        TimerPreset(name: "Focus", duration: 25 * 60, colorComponents: .systemOrange),
        TimerPreset(name: "Break", duration: 5 * 60, colorComponents: .systemGreen),
        TimerPreset(name: "Deep Work", duration: 45 * 60, colorComponents: .systemPurple)
    ]
}
