import Combine
import SwiftUI

/// Keeps the island open while something it presented (a popover) is on screen.
/// Set by `HomeMediaSlot`.
struct MediaHoldOpenAction: Sendable {
    let perform: @MainActor @Sendable (_ reason: String, _ active: Bool) -> Void

    @MainActor func callAsFunction(_ reason: String, active: Bool) {
        perform(reason, active)
    }
}

private struct MediaHoldOpenKey: EnvironmentKey {
    static let defaultValue: MediaHoldOpenAction? = nil
}

extension EnvironmentValues {
    var mediaHoldOpen: MediaHoldOpenAction? {
        get { self[MediaHoldOpenKey.self] }
        set { self[MediaHoldOpenKey.self] = newValue }
    }
}

// MARK: - Output volume

/// The system output volume for the media-output popover, through the HUD feature's
/// `VolumeController`. Changes made here keep the volume HUD quiet for 1.5 s.
@MainActor
final class MediaOutputVolumeModel: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var isMuted = false

    /// How long our own changes keep the volume HUD from popping up over the popover.
    static let ownControlHUDSuppression: TimeInterval = 1.5

    private var startedController = false
    private var cancellables = Set<AnyCancellable>()

    init() {}

    func activate() {
        let controller = VolumeController.shared
        if !controller.isRunning {
            controller.start()
            startedController = true
        }
        level = controller.volume
        isMuted = controller.isMuted
        cancellables.removeAll()
        controller.$volume
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.level = value }
            .store(in: &cancellables)
        controller.$isMuted
            .receive(on: RunLoop.main)
            .sink { [weak self] muted in self?.isMuted = muted }
            .store(in: &cancellables)
    }

    func deactivate() {
        cancellables.removeAll()
        if startedController {
            VolumeController.shared.stop()
            startedController = false
        }
    }

    func setVolume(_ value: Float) {
        SystemHUDPresenter.shared.suppressVolumeHUD(for: Self.ownControlHUDSuppression)
        level = value
        if value > 0 { isMuted = false }
        VolumeController.shared.setVolume(value)
    }

    func toggleMute() {
        SystemHUDPresenter.shared.suppressVolumeHUD(for: Self.ownControlHUDSuppression)
        isMuted.toggle()
        VolumeController.shared.toggleMute()
    }

    var iconName: String {
        Self.iconName(level: level, isMuted: isMuted)
    }

    static func iconName(level: Float, isMuted: Bool) -> String {
        if isMuted || level <= 0.001 { return "speaker.slash.fill" }
        if level < 0.33 { return "speaker.wave.1.fill" }
        if level < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var percentage: String { "\(Int((level * 100).rounded()))%" }
}

// MARK: - Buttons

/// The "Change Media Output" slot: the current output's glyph in a hover button that opens
/// the volume and device popover.
struct MediaOutputPickerButton: View {
    @ObservedObject private var routes = MediaAudioRouteManager.shared
    @StateObject private var volume = MediaOutputVolumeModel()
    @Environment(\.mediaHoldOpen) private var holdOpen
    @State private var isPresented = false
    @State private var token = UUID()

    var body: some View {
        MediaHoverButton(
            icon: routes.activeDevice?.iconName ?? "speaker.wave.2",
            accessibilityTitle: "Media output"
        ) {
            isPresented.toggle()
            if isPresented { routes.refreshDevices() }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            MediaOutputSelectorPopover(routes: routes, volume: volume) {
                isPresented = false
            }
        }
        .onAppear {
            routes.start()
            routes.refreshDevices()
        }
        .onChange(of: isPresented) { _, presented in
            holdOpen?("media.output.\(token.uuidString)", active: presented)
        }
        .onDisappear {
            holdOpen?("media.output.\(token.uuidString)", active: false)
        }
    }
}

/// The AirPlay slot (Music only): lists Music's AirPlay receivers with a volume slider for
/// each selected one.
struct MediaAirPlayPickerButton: View {
    @ObservedObject var manager: MusicManager
    @ObservedObject private var airPlay = MediaAirPlayManager.shared
    @Environment(\.mediaHoldOpen) private var holdOpen
    @State private var isPresented = false
    @State private var token = UUID()

    var body: some View {
        MediaHoverButton(icon: "airplayaudio", accessibilityTitle: "AirPlay") {
            isPresented.toggle()
            if isPresented { Task { await airPlay.refreshDevices() } }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            MediaAirPlaySelectorPopover(airPlay: airPlay)
        }
        .onAppear {
            if manager.isAppleMusicActive { Task { await airPlay.refreshDevices() } }
        }
        .onChange(of: manager.activeSource) { _, source in
            if source == .appleMusic { Task { await airPlay.refreshDevices() } }
        }
        .onChange(of: isPresented) { _, presented in
            holdOpen?("media.airplay.\(token.uuidString)", active: presented)
        }
        .onDisappear {
            holdOpen?("media.airplay.\(token.uuidString)", active: false)
        }
    }
}

// MARK: - Popovers

/// Volume on top (mute chip, slider, "Output volume" and the percentage), then the output
/// devices with the active one checked. 240 pt wide inside 16 pt of padding.
struct MediaOutputSelectorPopover: View {
    @ObservedObject var routes: MediaAudioRouteManager
    @ObservedObject var volume: MediaOutputVolumeModel
    var dismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            volumeSection
            Divider()
            devicesSection
        }
        .frame(width: 240)
        .padding(16)
        .onAppear { volume.activate() }
        .onDisappear { volume.deactivate() }
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    volume.toggleMute()
                } label: {
                    Image(systemName: volume.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.secondary.opacity(0.18)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(volume.isMuted ? "Unmute" : "Mute")

                Slider(
                    value: Binding(
                        get: { Double(volume.level) },
                        set: { volume.setVolume(Float($0)) }
                    ),
                    in: 0 ... 1
                )
                .tint(.accentColor)
            }

            HStack {
                Text("Output volume")
                Spacer()
                Text(volume.percentage)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output devices")
                .font(.caption)
                .foregroundStyle(.secondary)

            if routes.devices.isEmpty {
                Text("No audio outputs available")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(routes.devices) { device in
                            Button {
                                routes.select(device)
                                dismiss()
                            } label: {
                                MediaRouteRow(
                                    icon: device.iconName,
                                    name: device.name,
                                    isSelected: device.id == routes.activeDeviceID
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
            }
        }
    }
}

/// Music's AirPlay receivers, each selected one with its own volume slider.
struct MediaAirPlaySelectorPopover: View {
    @ObservedObject var airPlay: MediaAirPlayManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AirPlay")
                .font(.caption)
                .foregroundStyle(.secondary)

            if airPlay.devices.isEmpty {
                Text("No AirPlay devices found")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(airPlay.devices) { device in
                            VStack(spacing: 4) {
                                Button {
                                    Task { await airPlay.toggle(device) }
                                } label: {
                                    MediaRouteRow(icon: device.iconName, name: device.name, isSelected: device.isSelected)
                                }
                                .buttonStyle(.plain)

                                if device.isSelected {
                                    MediaAirPlayVolumeSlider(airPlay: airPlay, deviceID: device.id)
                                        .padding(.horizontal, 8)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 240)
        .padding(16)
    }
}

/// One output in a picker: glyph, name and a checkmark, on a soft highlight when selected.
private struct MediaRouteRow: View {
    let icon: String
    let name: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
            Text(name)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.12) : .clear)
        )
        .contentShape(Rectangle())
    }
}

/// A receiver's volume, kept in local state so refreshes never reset it mid-drag.
private struct MediaAirPlayVolumeSlider: View {
    @ObservedObject var airPlay: MediaAirPlayManager
    let deviceID: String

    @State private var value: Double = 0

    var body: some View {
        Slider(value: $value, in: 0 ... 100)
            .tint(.accentColor)
            .onAppear {
                value = Double(airPlay.currentVolume(for: deviceID))
            }
            .onChange(of: value) { _, newValue in
                // The first change is the slider adopting the receiver's level, not a drag.
                guard Int(newValue) != airPlay.currentVolume(for: deviceID) else { return }
                airPlay.setVolume(Int(newValue), for: deviceID)
            }
    }
}
