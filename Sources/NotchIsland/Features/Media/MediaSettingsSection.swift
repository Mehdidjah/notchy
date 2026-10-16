import SwiftUI

/// Media preferences as Form sections, mirroring Atoll's Media settings tab.
struct MediaSettingsSection: View {
    @ObservedObject var settings: MediaSettings = .shared
    @ObservedObject private var layout = HomeLayoutState.shared

    var body: some View {
        Section {
            Picker("Music Source", selection: $settings.sourcePreference) {
                ForEach(MediaSourcePreference.allCases) { preference in
                    Text(preference.label).tag(preference)
                }
            }
            Text("Automatic follows whichever of Apple Music or Spotify is playing. NotchIsland asks each player for permission the first time it reads it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Media Source")
        }

        Section {
            Toggle("Show media controls in Dynamic Island", isOn: $settings.showStandardMediaControls)
            Toggle("Auto-hide inactive notch media player", isOn: $settings.autoHideInactivePlayer)
                .disabled(!settings.showStandardMediaControls)
            if !settings.showStandardMediaControls {
                caption("Standard notch media controls are hidden. Re-enable the toggle above to restore them.")
            } else if !settings.autoHideInactivePlayer {
                caption("When disabled, the notch music player stays visible with placeholder metadata even when playback is inactive.")
            }
        } header: {
            Text("Dynamic Island Visibility")
        }

        Section {
            Toggle("Enable customizable controls", isOn: $settings.customizableControls)
            if settings.customizableControls {
                Toggle("Show \"Change Media Output\" control", isOn: $settings.showMediaOutputControl)
                    .help("Lets a control slot open the output device and volume picker.")
                ForEach(0 ..< MediaControlSlot.slotCount, id: \.self) { index in
                    Picker("Slot \(index + 1)", selection: slotBinding(index)) {
                        ForEach(MediaControlSlot.pickerOptions) { slot in
                            Label(slot.label, systemImage: slot.iconName.isEmpty ? "circle.dashed" : slot.iconName)
                                .tag(slot)
                        }
                    }
                }
                Button("Restore Default Layout") { settings.resetControlSlots() }
                    .disabled(settings.controlSlots == MediaControlSlot.defaultLayout)
                caption("Favorite Song and AirPlay work with Apple Music only.")
            } else {
                caption("Turn on customizable controls to rearrange media buttons.")
            }
        } header: {
            Text("Media controls")
        }

        Section {
            Picker("Skip buttons", selection: $settings.skipBehavior) {
                ForEach(MediaSkipBehavior.allCases) { behavior in
                    Text(behavior.displayName).tag(behavior)
                }
            }
            .pickerStyle(.segmented)
            caption(settings.skipBehavior.explanation)
        } header: {
            Text("Skip button behaviour")
        }

        Section {
            Toggle("Enable music live activity", isOn: $settings.liveActivityEnabled)
                .disabled(!settings.showStandardMediaControls)
            Toggle("Show floating media controls", isOn: $settings.controlWindowEnabled)
                .disabled(!settings.liveActivityEnabled || !settings.showStandardMediaControls)
                .help("Displays play/pause and skip buttons beside the notch while music is active. Disabled by default.")
            Toggle("Enable sneak peek", isOn: $settings.enableSneakPeek)
            Toggle("Show sneak peek on playback changes", isOn: $settings.sneakPeekOnTrackChange)
                .disabled(!settings.enableSneakPeek)
            Toggle("Show lyrics", isOn: $settings.enableLyrics)
                .disabled(!settings.showStandardMediaControls)
            if settings.enableLyrics && settings.showStandardMediaControls {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Highlight", selection: $settings.lyricHighlightStyle) {
                        ForEach(MediaLyricHighlightStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    caption(settings.lyricHighlightStyle.explanation)
                }
            }
            caption(layout.showsCalendar
                ? "Lyrics sit on one line under the artist name, since the calendar is using the rest of the notch. Turn the calendar off to give them a full panel beside the player."
                : "Lyrics get their own panel beside the player. Turn the calendar on to move them under the artist name instead.")
            if !settings.showStandardMediaControls {
                caption("Enable Dynamic Island media controls to use lyrics.")
            }
            if settings.enableLyrics && !layout.showsCalendar && settings.showStandardMediaControls {
                Slider(value: $settings.lyricsPanelWidth, in: 180 ... 420, step: 10) {
                    HStack {
                        Text("Side lyrics width")
                        Spacer()
                        Text("\(Int(settings.lyricsPanelWidth)) px").foregroundStyle(.secondary)
                    }
                }
                Slider(value: $settings.lyricsPanelOffset, in: -100 ... 100, step: 1) {
                    HStack {
                        Text("Side lyrics horizontal offset")
                        Spacer()
                        Text("\(settings.lyricsPanelOffset >= 0 ? "+" : "")\(Int(settings.lyricsPanelOffset)) px")
                            .foregroundStyle(.secondary)
                    }
                }
                caption("These controls apply when the calendar is disabled.")
            }
            Slider(value: $settings.parallaxIntensity, in: 0 ... 12, step: 1) {
                HStack {
                    Text("Parallax Effect Intensity")
                    Spacer()
                    Text(String(format: "%.1f", settings.parallaxIntensity)).foregroundStyle(.secondary)
                }
            }
            Picker("Sneak Peek Style", selection: $settings.sneakPeekStyle) {
                ForEach(MediaSneakPeekStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .disabled(!settings.enableSneakPeek)
            Stepper(value: $settings.waitInterval, in: 0 ... 10, step: 1) {
                HStack {
                    Text("Media inactivity timeout")
                    Spacer()
                    Text("\(Int(settings.waitInterval)) seconds").foregroundStyle(.secondary)
                }
            }
            Toggle("Show song title and artist on non-notch displays", isOn: $settings.showSongMetadataInClosedNotch)
        } header: {
            Text("Media playback live activity")
        }

        Section {
            Toggle("Show music visualizer", isOn: $settings.useMusicVisualizer)
            Picker("Visualizer candles", selection: $settings.visualizerBarCount) {
                ForEach(MediaSettings.Default.visualizerBarCounts, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            .disabled(!settings.useMusicVisualizer)
            Toggle("Colored spectrogram", isOn: $settings.coloredSpectrogram)
            Picker("Color extraction", selection: $settings.colorExtractionMode) {
                ForEach(MediaColorExtractionMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
        } header: {
            Text("Music Visualizer")
        }

        Section {
            Toggle("Player tinting", isOn: $settings.playerColorTinting)
            Picker("Slider color", selection: $settings.sliderColor) {
                ForEach(MediaSliderColor.allCases) { color in
                    Text(color.label).tag(color)
                }
            }
            Toggle("Album art lighting effect", isOn: $settings.lightingEffect)
            Toggle("Album art corner radius scaling", isOn: $settings.cornerRadiusScaling)
        } header: {
            Text("Player Appearance")
        }

        Section {
            Toggle("Media change with horizontal gestures", isOn: $settings.horizontalGestures)
            if settings.horizontalGestures {
                Picker("Gesture skip behavior", selection: $settings.gestureBehavior) {
                    ForEach(MediaSkipBehavior.allCases) { behavior in
                        Text(behavior.displayName).tag(behavior)
                    }
                }
                .pickerStyle(.segmented)
                caption(settings.gestureBehavior.explanation)
                Toggle("Reverse swipe gestures", isOn: $settings.reverseSwipeGestures)
            }
            caption("Swipe left or right with two fingers on the closed music activity (with open on hover off) or the Home tab.")
        } header: {
            Text("Media Gestures")
        }
    }

    private func slotBinding(_ index: Int) -> Binding<MediaControlSlot> {
        Binding(
            get: { settings.controlSlots.indices.contains(index) ? settings.controlSlots[index] : .none },
            set: { settings.setSlot($0, at: index) }
        )
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
