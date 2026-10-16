import CoreGraphics
import Foundation
import IOKit.ps

/// One reading of the Mac's internal battery, taken from IOKit's public power-source API.
struct BatterySnapshot: Equatable, Sendable {
    var hasBattery: Bool
    /// Charge, 0...100.
    var level: Int
    /// Maximum capacity as IOKit reports it (a percentage on Apple laptops).
    var maxCapacity: Int
    var isPluggedIn: Bool
    var isCharging: Bool
    var isInLowPowerMode: Bool
    /// Minutes until full; 0 when unknown or not charging.
    var timeToFullCharge: Int
    /// Minutes until empty; 0 when unknown or on power.
    var timeToEmpty: Int

    static let unavailable = BatterySnapshot(
        hasBattery: false,
        level: 0,
        maxCapacity: 0,
        isPluggedIn: false,
        isCharging: false,
        isInLowPowerMode: false,
        timeToFullCharge: 0,
        timeToEmpty: 0
    )
}

extension BatterySnapshot {
    /// Reads the internal battery now. powerd answers from cached state, so this is quick,
    /// but callers still run it off the main actor.
    static func read() -> BatterySnapshot {
        let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            var snapshot = BatterySnapshot.unavailable
            snapshot.isInLowPowerMode = lowPowerMode
            return snapshot
        }
        let descriptions: [[String: Any]] = list.compactMap { source in
            IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        }
        return snapshot(fromSources: descriptions, lowPowerMode: lowPowerMode)
    }

    /// Picks the internal battery among the power sources (a UPS can be listed too), falling
    /// back to the first source.
    static func snapshot(fromSources sources: [[String: Any]], lowPowerMode: Bool) -> BatterySnapshot {
        let battery = sources.first { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType }
            ?? sources.first
        guard let battery else {
            var snapshot = BatterySnapshot.unavailable
            snapshot.isInLowPowerMode = lowPowerMode
            return snapshot
        }
        return snapshot(from: battery, lowPowerMode: lowPowerMode)
    }

    /// Converts one IOPS power-source description.
    static func snapshot(from description: [String: Any], lowPowerMode: Bool) -> BatterySnapshot {
        let current = integer(description[kIOPSCurrentCapacityKey]) ?? 0
        let maximum = integer(description[kIOPSMaxCapacityKey]) ?? 100
        // Apple laptops report both in percent (max 100); other sources may use raw units.
        let level: Int = if maximum > 0, maximum != 100 {
            Int((Double(current) * 100 / Double(maximum)).rounded())
        } else {
            current
        }
        let powerState = description[kIOPSPowerSourceStateKey] as? String
        let isPresent = (description[kIOPSIsPresentKey] as? Bool) ?? true
        return BatterySnapshot(
            hasBattery: isPresent,
            level: min(max(level, 0), 100),
            maxCapacity: max(0, maximum),
            isPluggedIn: powerState == kIOPSACPowerValue,
            isCharging: (description[kIOPSIsChargingKey] as? Bool) ?? false,
            isInLowPowerMode: lowPowerMode,
            // IOKit reports -1 while it is still estimating.
            timeToFullCharge: max(0, integer(description[kIOPSTimeToFullChargeKey]) ?? 0),
            timeToEmpty: max(0, integer(description[kIOPSTimeToEmptyKey]) ?? 0)
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: number.intValue
        case let int as Int: int
        default: nil
        }
    }

    /// The state after `event` has been delivered.
    func applying(_ event: BatteryEvent) -> BatterySnapshot {
        var next = self
        switch event {
        case .availabilityChanged(let available): next.hasBattery = available
        case .powerSourceChanged(let pluggedIn): next.isPluggedIn = pluggedIn
        case .levelChanged(let level): next.level = level
        case .chargingChanged(let charging): next.isCharging = charging
        case .lowPowerModeChanged(let enabled): next.isInLowPowerMode = enabled
        case .timeToFullChargeChanged(let minutes): next.timeToFullCharge = minutes
        case .maxCapacityChanged(let capacity): next.maxCapacity = capacity
        }
        return next
    }
}

/// A single change between two battery readings. They are delivered one at a time, a
/// second apart, so a plug-in and the charging flip that follows never collide.
enum BatteryEvent: Equatable, Sendable {
    case availabilityChanged(Bool)
    case powerSourceChanged(isPluggedIn: Bool)
    case levelChanged(Int)
    case chargingChanged(Bool)
    case lowPowerModeChanged(Bool)
    case timeToFullChargeChanged(Int)
    case maxCapacityChanged(Int)
}

/// A battery event after delivery, with the state on either side of it.
struct BatteryDelivery: Equatable, Sendable {
    let event: BatteryEvent
    let before: BatterySnapshot
    let after: BatterySnapshot
}

/// The three temporary battery alerts drawn in the closed notch.
enum BatteryHUDKind: String, CaseIterable, Sendable {
    case charging
    case lowBattery
    case fullBattery
}

/// Two looks for the low and full alerts; charging is always compact.
enum BatteryHUDStyle: String, CaseIterable, Identifiable, Sendable {
    /// The taller card with a description and an animated battery illustration.
    case standard
    /// A single row, like the charging alert.
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .compact: "Compact"
        }
    }
}

/// What a delivered event should raise.
struct BatteryHUDTrigger: Equatable, Sendable {
    let kind: BatteryHUDKind
    /// True only for a falling level crossing the low threshold (the low-battery chime).
    let playsAlertSound: Bool
}

enum BatteryEventRules {
    /// The changes from `old` to `new`, in this order: power source, level, charging,
    /// Low Power Mode, time to full, max capacity. Time to empty is not queued (it is not
    /// tracked, and its minute-by-minute estimate would hold up real alerts).
    static func events(from old: BatterySnapshot, to new: BatterySnapshot) -> [BatteryEvent] {
        var events: [BatteryEvent] = []
        if old.hasBattery != new.hasBattery { events.append(.availabilityChanged(new.hasBattery)) }
        if old.isPluggedIn != new.isPluggedIn { events.append(.powerSourceChanged(isPluggedIn: new.isPluggedIn)) }
        if old.level != new.level { events.append(.levelChanged(new.level)) }
        if old.isCharging != new.isCharging { events.append(.chargingChanged(new.isCharging)) }
        if old.isInLowPowerMode != new.isInLowPowerMode { events.append(.lowPowerModeChanged(new.isInLowPowerMode)) }
        if old.timeToFullCharge != new.timeToFullCharge { events.append(.timeToFullChargeChanged(new.timeToFullCharge)) }
        if old.maxCapacity != new.maxCapacity { events.append(.maxCapacityChanged(new.maxCapacity)) }
        return events
    }

    /// Triggers: plugging in raises the charging alert; switching Low Power Mode on
    /// raises the low alert; a falling level that crosses the low threshold on battery raises
    /// the low alert with its chime; a rising level that reaches the full threshold raises
    /// the full alert.
    static func trigger(
        for event: BatteryEvent,
        before: BatterySnapshot,
        lowThreshold: Int,
        fullThreshold: Int
    ) -> BatteryHUDTrigger? {
        switch event {
        case .powerSourceChanged(let pluggedIn):
            return pluggedIn && !before.isPluggedIn
                ? BatteryHUDTrigger(kind: .charging, playsAlertSound: false)
                : nil
        case .lowPowerModeChanged(let enabled):
            return enabled && !before.isInLowPowerMode
                ? BatteryHUDTrigger(kind: .lowBattery, playsAlertSound: false)
                : nil
        case .levelChanged(let level):
            let previous = before.level
            if !before.isPluggedIn, !before.isCharging, level < previous,
               previous > lowThreshold, level <= lowThreshold {
                return BatteryHUDTrigger(kind: .lowBattery, playsAlertSound: true)
            }
            if level > previous, previous < fullThreshold, level >= fullThreshold {
                return BatteryHUDTrigger(kind: .fullBattery, playsAlertSound: false)
            }
            return nil
        default:
            return nil
        }
    }
}

/// Sizes of a battery alert in the closed notch. The alert is drawn `closedWidth + extra`
/// wide; with the notch-covering centre between the wings, each wing is half the extra.
struct BatteryHUDMetrics: Equatable, Sendable {
    /// Width of each wing beside the notch.
    let wingWidth: CGFloat
    /// Height the island grows by under the wings (standard cards only).
    let bandHeight: CGFloat
    /// Bottom corner radius of the island while the alert shows; nil keeps the closed 14.
    let bottomCornerRadius: CGFloat?

    static func resolve(kind: BatteryHUDKind, style: BatteryHUDStyle) -> BatteryHUDMetrics {
        switch (kind, style) {
        case (.charging, _), (.lowBattery, .compact), (.fullBattery, .compact):
            BatteryHUDMetrics(wingWidth: 90, bandHeight: 0, bottomCornerRadius: nil)
        case (.lowBattery, .standard):
            BatteryHUDMetrics(wingWidth: 75, bandHeight: 75, bottomCornerRadius: 40)
        case (.fullBattery, .standard):
            BatteryHUDMetrics(wingWidth: 70, bandHeight: 70, bottomCornerRadius: 36)
        }
    }
}
