# Atoll spec: PRODUCTIVITY TABS (Timer, Calendar, Notes, Color picker, Terminal, Screen Assistant, LLM usage)

Source: Atoll 2.3.3 source clone plus REA evidence from the installed binary (see ../atoll-behaviour-evidence.md). Values are quoted with file:line from the Atoll source. Reimplement behaviour, do not copy code (GPL-3).

## Summary

Atoll 2.3.3 exposes productivity features as (a) tabs inside the open notch selected by an icon-only capsule tab bar, (b) closed-notch live activities (timer, calendar reminder) and (c) header popovers / floating NSPanels (timer popover, color picker, screen assistant). All source paths below are relative to A = /private/tmp/claude-501/-Users-a-dynamic-iland-dynamic-island/b501c539-18bc-4747-a9c4-d824916ad38f/scratchpad/atoll-clone/Atoll/DynamicIsland. REA evidence (rea-out/macho.json, dispatch.json, graph.json) confirms the shipped binary links EventKit, Security, ApplicationServices (AX), AVFoundation/AVFAudio, libsqlite3, imports NSColorSampler, EKEventStore/EKEvent/EKReminder, AXUIElementCreateSystemWide/CreateApplication/CopyAttributeValue, AXIsProcessTrusted(+WithOptions), forkpty (SwiftTerm LocalProcess), SecItemCopyMatching, NSAppleScript, NSTask, AVAudioPlayer, NSHapticFeedbackManager, NSSound; dispatch.json carries Swift decls for TimerManager, SystemTimerBridge, TimerPopover, TimerPreset, CalendarManager, CalendarService, ReminderLiveActivity, ColorPickerManager, ColorPickerPanel, PickedColor, TerminalManager, SwiftTerm TerminalView/LocalProcess, ScreenAssistantManager, ScreenshotSnipping, LLMUsageManager, Claude/Codex/CursorUsageProvider, AppleNotesSyncManager, NoteItem; bundle resources include timer.mp3, dynamic.m4a, pricing.json and SwiftTerm_SwiftTerm.bundle (SwiftTerm statically linked, no dylib). Everything in this subsystem is built on PUBLIC macOS APIs except: Clock-timer mirroring (SystemTimerBridge) which streams the undocumented com.apple.mobiletimer.logging log subsystem via /usr/bin/log, reads ~/Library/Preferences/com.apple.mobiletimerd.plist (MTTimers) via CFPreferences and drives Clock.app's PauseResumeButton/CancelButton via Accessibility; and LLM-usage quota clients which read third-party app credentials (Claude Code Keychain item / ~/.claude/.credentials.json, ~/.codex/auth.json, Cursor state.vscdb) and call undocumented endpoints. Priority detail is given for Timer, Calendar and Color picker; Notes, Terminal, Screen Assistant and LLM usage are summarised with their sizes, data sources and settings. Shared hosting rules: tab bar is HStack(spacing 24) of SF-symbol TabButtons each 26pt tall, selected tint white (extension accent otherwise) vs .gray, selection capsule fill Color(nsColor:.secondarySystemFill).opacity(0.25) with matchedGeometryEffect id "capsule" (components/Tabs/TabSelectionView.swift:116-148); tab order Home, Shelf, Timer(.tab mode), Stats, Usage(LLM), Notes|Clipboard, Terminal, extension tabs (65-115). Tab content switches with asymmetric move(.trailing/.leading)+opacity transitions depending on coordinator.tabSwitchForward and .animation(.smooth(duration:0.3), value: currentView) (ContentView.swift:311-323, 1316-1323). Open-notch height per tab (ContentView.swift:188-211): timer 250pt, notes = max(base, NotesLayoutState.preferredHeight: list 240 / split 260 / editor 320), clipboard = max(base, 240), terminal = max(300, screenVisibleHeight * terminalMaxHeightFraction); base open size is (Defaults[.openNotchWidth] clamped, 200) (sizing/matters.swift:69-75). Corner radii of the open shell: top 19 / bottom 24 (closed 6/14), minimalistic 35/35 (sizing/matters.swift:199-200).

## Reference screenshot (user-supplied, Atoll 2.3.3, 2026-10-16)

`reference/atoll-home-standalone-calendar.png` shows Atoll's open notch on the Home tab with no
media playing, so the calendar renders as the standalone month grid: header "October 2026"
(month bold, year lighter) with chevron.left / chevron.right buttons on the right; weekday row
M T W T F S S in grey; week rows of day numbers in white, today (16) inside a filled blue
accent circle; the grid scrolls vertically so partial rows show above and below; on the right a
centred empty state with the calendar.badge.checkmark-style glyph, "No events today" (white,
semibold) and "Enjoy your free time!" (grey, smaller). Header row above: Home (selected, white),
Shelf, Timer and Terminal tab icons on the left; on the right a clipboard button, a second round
button, the text "21%" and a battery outline glyph (battery indicator with percentage outside).


## Timer – core state machine (TimerManager + TimerLifecycle + TimerPreset)

### Behaviour

A single countdown timer (manual preset/custom, or mirrored from macOS Clock). Counts down once per second; at 0 it plays a looping sound and flips into 'overtime' counting negative ('-M:SS') until the user stops it. Pause/resume/cancel supported for manual timers; for Clock-mirrored timers controls are forwarded to Clock via Accessibility. Colour of the timer glyph/progress follows an adaptive green→yellow→red ramp unless a preset colour or a solid colour is configured. Default presets: Focus 25 min orange, Break 5 min green, Deep Work 45 min purple.

### Layout

No UI of its own. Formatting: timeString 'M:SS' or 'H:MM:SS' (A/managers/TimerManager.swift:540-551), overtime prefixed with '-' (524-530). Status text Overtime/Paused/Running/Ready (92-102). TimerPreset.formattedDuration uses DateComponentsFormatter with [.hour,.minute,.second] when >= 3600 else [.minute,.second], zeroFormattingBehavior .pad (A/models/TimerPreset.swift:80-85).

### Animations

isTimerActive toggled inside withAnimation(.smooth) on start/adopt/forceStop/reset (TimerManager.swift:175-177, 259-261, 335-337, 399-401, 409-411). Smooth close after completion/cancel: wait 3.0 s then withAnimation(.easeInOut(duration: 1.0)) { isTimerActive = false } guarded by session id (456-472). Colour ramp: progress < 0.6 → .green; 0.6..<0.9 → Color(red: 1 - (1 - t)*0.5, green: 1, blue: 0) where t=(p-0.6)/0.3; >= 0.9 or overtime → .red (54-77). progress = elapsed/total clamped 0...1, overtime = 1 + min(1, |remaining|/total) (44-52).

### State and timing

start: invalidate existing, beginSession (cancels pending close), isTimerActive=true, source=.manual, remaining=total, elapsed=0, paused=false. Tick (1 s): if remaining>0 decrement & elapsed=total-remaining; if remaining==0 → finished=true, overtime=true, play sound, remaining=-1; else remaining -= 1 (195-213). pause: paused=true, timer invalidated; resume: new 1 s timer (265-321). stopTimer: invalidate, stop sound, scheduleSmoothClose (3 s + 1 s fade) then resetTimer (222-247); forceStopTimer: immediate .smooth deactivate (249-263). External timers: adoptExternalTimer/updateExternalTimer/completeExternalTimer/endExternalTimer (323-405); a positive 'remaining' update after completion starts a new session (356-361). allowsManualInteraction = source != .external || SystemTimerBridge.canControlClockTimer (437-444).

### Data sources and APIs

Foundation Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) ticking on main (191-215, 296-320). Sound: AVAudioPlayer with numberOfLoops = -1 on UserDefaults 'customTimerSoundPath' if file exists, else bundle timer.mp3, else dynamic.m4a, else NSSound.beep() (486-521). REA: _OBJC_CLASS_$_AVAudioPlayer, NSSound.beep import and timer.mp3/dynamic.m4a present in Atoll.app/Contents/Resources. Observes SystemTimerBridge.$canControlClockTimer via Combine to republish (148-153). All PUBLIC.

### Settings

enableTimerFeature=true; timerDisplayMode=.tab (TimerDisplayMode tab|popover); timerPresets=TimerPreset.defaultPresets; showTimerPresetsInNotchTab=true; timerIconColorMode=.adaptive (TimerIconColorMode adaptive|solid, raw 'Adaptive'/'Solid'); timerSolidColor=.blue; timerShowsCountdown=true; timerShowsLabel=false; timerShowsProgress=true; timerProgressStyle=.bar (TimerProgressStyle bar|ring, raw 'Bar'/'Ring'); mirrorSystemTimer=true; timerInputStyle=.manual (TimerInputStyle ruler|manual, raw 'Ruler'/'Manual'); timerControlWindowEnabled=true (legacy name; now 'show pause/stop controls in notch') (A/models/Constants.swift:1317-1338). @AppStorage 'timerLiveActivityEnabled'=true (A/DynamicIslandViewCoordinator.swift:129). @AppStorage 'customTimerDuration'=600 (NotchTimerView.swift:40). UserDefaults 'customTimerSoundPath' (string path, set by Settings 'Choose File'; supported MP3/M4A/WAV/AIFF; default shown as dynamic.m4a) (SettingsView.swift:7688-7777). TimerPreset model: id UUID, name, duration TimeInterval, colorData {red,green,blue,alpha} sRGB (TimerPreset.swift:23-66). Global shortcut startDemoTimer default Cmd+Shift+T (A/Shortcuts/ShortcutConstants.swift:35).

### Dependencies

Defaults (sindresorhus, 9.0.3, MIT) for TimerPreset storage (Defaults.Serializable).

### Implementation notes

Reimplement as @MainActor @Observable TimerEngine with: state {active,name,total,remaining,elapsed,paused,finished,overtime,source(.none/.manual/.external),presetID,sessionID}; a 1 s Timer or Task sleep loop; session UUID so delayed close work-items can be invalidated (TimerLifecycle: beginSession/completeSession/endSession/isCurrent, A/managers/TimerLifecycle.swift:15-41). Keep remaining == 0 as the 'just finished' tick that plays the sound and sets remaining = -1 (201-207). Estimated size ~350 lines.

### Key files

- `DynamicIsland/managers/TimerManager.swift`
- `DynamicIsland/managers/TimerLifecycle.swift`
- `DynamicIsland/models/TimerPreset.swift`
- `DynamicIsland/enums/TimerDisplayMode.swift`
- `DynamicIsland/models/Constants.swift`

## Timer – open-notch Timer tab (NotchTimerView, RulerTimerPicker)

### Behaviour

Tab labelled 'Timer' (SF 'timer') when enableTimerFeature && timerDisplayMode == .tab. Idle state: left column shows a custom-duration composer (either a horizontal ruler scrubber 0–90 min, or H:M:S text fields with Start/Reset buttons); right column (if showTimerPresetsInNotchTab) is a 210pt-wide scrolling list of preset cards (colour dot, name, duration, play glyph). Tapping a preset or Start starts the timer and switches the tab to Timer. Active state: the preset column disappears; a card shows pause/cancel circular buttons (or a single stop button in overtime), the timer name (marquee if too long) with a status capsule (Paused/Completed/Overtime), a big monospaced countdown (or a 110pt ring with countdown inside when progress style is Ring) and, for Bar style, a 4pt progress capsule beneath. When the timer is Clock-mirrored and Clock can't be controlled the controls area is an empty 46pt placeholder. When the feature is disabled the tab shows a 'Timer Disabled' placeholder. Hovering the closed notch while a timer runs in tab mode opens the notch on the Timer tab even if open-on-hover is off (ContentView.swift:2334-2340). Open notch height on this tab is 250pt (ContentView.swift:188-190).

### Layout

Root: HStack(alignment:.top, spacing: active ? 0 : 20){ leftColumn; [Divider().frame(height: maxTabContentHeight-8).opacity(0.2); presetColumn] }.frame(maxHeight: maxTabContentHeight, alignment:.top).padding(.horizontal,16).padding(.vertical,6) (A/components/Notch/NotchTimerView.swift:50-61). maxTabContentHeight = max(130, notchHeight - max(24, effectiveClosedNotchHeight) - 36) (371-383). leftColumn VStack(.leading, spacing 16).frame(maxWidth:.infinity).padding(.bottom,2) (89-103). presetColumn: width 210; VStack(spacing 6); List(.plain, scrollContentBackground hidden, indicators never) rows listRowInsets(top 2,bottom 2), listHeight = min(maxTabContentHeight-16, count*60+4); top/bottom LinearGradient fades 16pt Color.black.opacity(0.65)→clear (105-154); empty text 12pt .secondary padding 14 on white 0.05 radius 14 continuous (108-114). TimerPresetCard (693-737): HStack(spacing 12){ Circle fill preset.color.gradient 30×30 overlay stroke white 0.3 1pt; VStack(.leading, spacing 2){ name 14 semibold lineLimit 1; duration .caption.monospaced .secondary }.foregroundStyle(preset.color); Spacer; Image(isActive ? 'checkmark' : 'play.fill') 12 bold fg isActive ? preset.color : .secondary, padding 6, bg isActive ? preset.color.opacity(0.2) : white 0.08, Circle }.padding(h 12, v 6).background(RoundedRectangle 16 continuous fill isActive ? preset.color.opacity(0.12) : white 0.04). activeTimerCard (156-170): VStack(.leading, spacing 12){ HStack(.center, spacing 14){ leadingControlSection.frame(width 128, .leading); timerTitleSection; countdownSection }; progressSection }.padding(.horizontal,4). TimerControlButton (552-576): SF icon 18 semibold, 46×46, background colour opacity hover 0.95 else 0.8, clipShape Circle, contentTransition(.symbolEffect(.replace)); pause/play bg = accent.opacity(0.32), cancel 'xmark' bg white 0.16, overtime 'stop.fill' bg white 0.16; fg white 0.95 (172-205). timerTitleSection (207-233): GeometryReader height 32; MarqueeText(font .system(20,.semibold), nsFont .title3, white, minDuration 0.2, frameWidth = max(48, width - badgeWidth - (status? 8:0))).frame(width: marqueeWidth, height 24); statusBadge: .caption.weight(.semibold) fg statusColor (red if overtime else accent), padding h12 v4, bg statusColor.opacity(0.18), Capsule; badgeWidth = NSString size with 12pt semibold + 24 (427-447). countdownSection (235-263): Ring style → TimerProgressRing 110×110: track Circle stroke white 0.12 lineWidth 8; progress trim stroke tint lineWidth 8 lineCap round rotation -90°; centre Text 28 black monospaced (red when overtime) minimumScaleFactor 0.6 (578-607). Else VStack(.trailing, spacing 4){ Text 36 .black monospaced, red if overtime else white, minimumScaleFactor 0.8; if overtime Text('Overtime') .caption red }.frame(width 190, .trailing). progressSection (Bar only, 265-282): Capsule white 0.12 height 4, overlay Capsule accent height 4 .scaleEffect(x: progress, anchor .leading), padding top 6 bottom 2. Composer (297-342): padding 12, bg white 0.04, clip RoundedRectangle 14 continuous; manual+presets → VStack(spacing 12){ DurationInputRow(fieldWidth 64); HStack(spacing 10){ start; reset } }; manual no presets → HStack(spacing 16){ DurationInputRow(fieldWidth 78); VStack(spacing 10){start; reset}.frame(width 210) }. DurationInputRow HStack(spacing 8) H(0...23) ':' M(0...59) ':' S(0...59); colon 26 black monospaced white 0.65 (610-643). DurationField: VStack(spacing 6){ TextField('00') 28 semibold monospaced centred plain white tint white frame width×46 bg white 0.08 radius 12 continuous; label .caption white 0.65 }; binding formats %02d, filters digits, clamps (645-691). startButton: Label('Start','play.fill') 15 semibold white, maxWidth, padding v10, bg RoundedRectangle 12 continuous fill Color(red 0.142, green 0.633, blue 0.265) (opacity 0.5 when disabled), overlay stroke white 0.15 1pt, opacity 0.7 when disabled; disabled when 0 s (457-492). resetButton: Label('Reset','arrow.counterclockwise') 15 semibold white 0.9, bg white 0.16, stroke white 0.08 (494-513). Placeholder when controls unavailable: Color.clear height 46 (344-347). Disabled state: 'timer.slash' 48 light .secondary; 'Timer Disabled' .title2 medium; body text .secondary (349-365). RulerTimerPicker (A/components/Timer/RulerTimerPicker.swift): VStack(spacing 0){ rulerArea height 62; controlRow } (138-142). Canvas height 52: tick every minute, major every 5: height 20 width 2 opacity 0.9 y 16; minor height 12 width 1.5 opacity 0.5 y 20; Path(roundedRect radius 1) filled tint.opacity; label every 5 min Text(m) 11 bold rounded tint 0.85 drawn at y 6 (165-206); tickSpacing 10pt/min, range 0...90, fadeWidth 48 (134-136); pointer 'arrowtriangle.up.fill' 10 heavy tint offset y 48 (209-213); drag overlay height 60 (216-218); mask HStack{gradient clear→black 48pt; Rectangle; gradient black→clear 48pt} (240-259). controlRow (279-316): HStack{ Button 'Start Timer' 14 semibold rounded tint, padding h18 v10, Capsule fill tint 0.18 + stroke tint 0.25 width 1.5, opacity 0.45 & disabled at 0; Spacer; Text 'MM:00'/'H:MM:00' 34 semibold rounded monospacedDigit tint }.padding(.horizontal 6).padding(.top 14).

### Animations

Tab content: .transition(.opacity.combined(with: .blurReplace)) (NotchTimerView.swift:62). Start: withAnimation(.smooth) (520-525); Reset fields: .smooth(duration 0.2) (529-533). Countdown digits: .contentTransition(.numericText()) + .animation(.smooth(duration: 0.25), value: remainingTime) (250-251, 603-604). Ring progress .smooth(0.3) (596); bar progress .smooth(0.25) (276). Control icon swap .symbolEffect(.replace) (569). Accent colour is locked for the duration of a run (lockedAccentColor, 385-402). Ruler: drag onEnded snaps withAnimation(.smooth(duration: 0.15)) to integer minute (231-236); readout .numericText + .smooth(0.12) keyed on rounded minutes (311-312); NSHapticFeedbackManager .alignment on every integer minute change (107-112, 344-351). MarqueeText: loop of two copies with 20pt gap, waits minDuration then .linear(duration: width/30) scroll, snaps back instantly, repeats; height = pointSize*1.3 (A/components/Live activities/MarqueeTextView.swift:40-157).

### State and timing

Fields sync both ways with customTimerDuration (syncCustomDuration/updateStoredCustomDuration, 537-549). Start disabled when total seconds == 0. Preset column only when !isTimerActive && showTimerPresetsInNotchTab (367-369). Status badge precedence: Overtime > Paused > Completed > none (412-421).

### Data sources and APIs

TimerManager.shared; Defaults keys; @AppStorage customTimerDuration; RulerScrollMonitor uses NSEvent.addLocalMonitorForEvents(.scrollWheel), consumes horizontal trackpad deltas when |dx|>|dy| && |dx|>0.15 && (phase||momentumPhase non-empty) and cursor inside view, returns nil to swallow (RulerTimerPicker.swift:28-102, 321-327); vm.setScrollGestureSuppression(hovering, token:) while hovering the ruler so the notch's own scroll gesture is disabled (329-333). NSHapticFeedbackManager (PUBLIC). All PUBLIC.

### Settings

Uses enableTimerFeature, enableMinimalisticUI, timerPresets, timerIconColorMode, timerSolidColor, timerShowsProgress, timerProgressStyle, showTimerPresetsInNotchTab, timerInputStyle; customTimerDuration (AppStorage, default 600 s → fields 0:10:00).

### Dependencies

Defaults (MIT).

### Implementation notes

Port as SwiftUI views bound to the TimerEngine. Ruler: Canvas + DragGesture + NSViewRepresentable scroll monitor; keep 10pt/min and 0...90 range. Height budget: tab notch height 250 → maxTabContentHeight = max(130, 250 - headerHeight - 36). Estimated ~750 lines (tab) + ~360 (ruler).

### Key files

- `DynamicIsland/components/Notch/NotchTimerView.swift`
- `DynamicIsland/components/Timer/RulerTimerPicker.swift`
- `DynamicIsland/components/Live activities/MarqueeTextView.swift`
- `DynamicIsland/components/Tabs/TabSelectionView.swift`
- `DynamicIsland/ContentView.swift`

## Timer – closed-notch live activity (TimerLiveActivity + music-paired supplement)

### Behaviour

While a timer is active and the notch is closed, the notch grows wings: left wing shows a tinted 'timer' SF glyph (optionally wrapped by a 3pt progress ring when ring style + countdown), optionally followed by the timer name (shown transiently for 4 s on start/rename, permanently if timerShowsLabel or when finished/overtime; marquee if too long) and, when bar style without countdown, a 3pt progress capsule under the name. Right wing shows (optionally) a 3pt ring, the monospaced countdown (red in overtime) with an optional 3pt bar beneath, and inline circular pause/cancel buttons (single red-tinted stop in overtime). Hovering grows the notch by 8pt and the wings by 12pt of content height. When music is playing the timer instead becomes the music activity's secondary: a small 'timer' badge on the album art and a compact right-wing supplement (ring / countdown / bar / name).

### Layout

A/components/Timer/TimerLiveActivity.swift. notchContentHeight = max(0, effectiveClosedNotchHeight - (hover ? 0 : 12)) (47-49); wingPadding 22; ringStrokeWidth 3 (51-52). Layout HStack(spacing 0){ leftWing(Color.clear width leftWingWidth) ; middle Rectangle black width closedNotchSize.width (+8 hover); rightWing }.frame(height: effectiveClosedNotchHeight + (hover ? 8 : 0)) (266-321). ringWrapsIcon = ring && countdown; ringOnRight = ring && !countdown (55-61). iconWidth = ringWrapsIcon ? max(h-6, 28) : h (63-65). infoContentWidth = label ? clamp(titleWidth(12pt medium), 44, 220) : clamp(h*1.4, 64, 220); infoWidth = infoContentWidth + 18 (67-80). leftWingWidth = iconWidth + 11 (+ 8 + infoWidth when info shown) (82-91); left HStack(spacing 8 or 0).padding(.leading 11) (281-288). ringWidth = 30 when ringOnRight (93-95). inlineButtonSize = clamp(h-4, 20, 26); inlineIconSize = max(0.6*button, 12); spacing 10; count = overtime ? 1 : 2 (97-111). rightWingWidth = 22 + [30 ring] + [10 if ring&&countdown] + countdownWidth + [10 + controls] (113-131); right HStack trailing padding 11-9 = 2 (318). countdownWidth = max(textWidth(13pt semibold monospaced) + 16, 72) (137-144). iconSection: ringDiameter = ringWrapsIcon ? max(min(iconWidth, h-2), 22) : iconWidth; iconSize = ringWrapsIcon ? max(ringDiameter-12, 16) : max(18, iconWidth-6); ring track Circle stroke white 0.15 lw 3; progress trim stroke glyphColor lw 3 round cap rotation -90; Image 'timer' 16 semibold glyphColor (323-350). infoSection: black Rectangle infoWidth×h overlay VStack(.leading, spacing 4 if bar){ label MarqueeText(12 medium, .callout, white, minDuration 0.25, width resolvedTextWidth) when finished/overtime/too wide else Text 12 medium white lineLimit 1; bar Capsule white 0.12 height 3 width barWidth, overlay Capsule glyphColor width*progress }.padding(.leading 12).padding(.trailing 6) (352-401). ringSection: diameter clamp(h-4, 20, 26), frame 30×h (403-416). countdownSection: VStack(spacing 4){ Text 13 semibold monospaced, red if overtime else white, fixedSize; [Capsule white 0.12 h3 width = countdownTextWidth with glyphColor fill] }.frame(width countdownWidth, height h) (418-448). inlineControlButton: Image icon inlineIconSize semibold white, frame button×button, bg white 0.14 (stop in overtime red 0.24), Circle (450-493). Music-paired supplement (A/ContentView.swift:3033-3148 MusicTimerSupplementView): HStack(spacing 8 if ring&&countdown){ ring diameter clamp(h-4,20,26) track white 0.18 lw 3 in frame max(d+4,30)×h; countdown VStack(.trailing, spacing 4 if bar){ Text 13 semibold monospaced frame width max(w+16,72) trailing; bar Capsule white 0.15 h4 width = text width }.padding(.trailing 2); or standalone bar width 68; or name Text 12 medium white frame max(w+14,64) }. Album-art badge: black Circle with 'timer' glyph size badgeSize*0.55 semibold in accent (1646-1649). Paired wing widths: countdown → max(base, 18 + ring30 + 8 + countdownFrame) ; else ring → max(base, max(centre*0.46, base+18)); bar → 0.52/+24; none → 0.38/+12 (1576-1601, 1634-1636). TimerSupplementMetrics.countdownFrameWidth = max(w+16, 72), timerNameFrameWidth = max(w+14, 64) (3250-3266).

### Animations

Hover: withAnimation(.smooth(duration: 0.18)) isHovering (222-226). Ring & bar progress .animation(.smooth(duration: 0.25), value: clampedProgress) (338, 393, 412, 438). Countdown .contentTransition(.numericText()) .animation(.smooth(0.25), value: remainingTime) (426-427). Transient label shown/hidden with withAnimation(.smooth) and DispatchQueue asyncAfter 4 s (512-531); on finish/overtime label forced visible with .smooth and hover reset (246-263). Label text transition .opacity.combined(with: .move(edge: .top)) (380). infoSection .animation(.smooth, value: isFinished) (400). Activity appear/disappear is driven by TimerManager's withAnimation(.smooth) activation and the 1 s .easeInOut smooth close after a 3 s hold.

### State and timing

Transient label 4 s (transientLabelDuration, 53). Controls hidden when !allowsManualInteraction or screen locked (188-193). glyphColor: adaptive → preset colour ?? TimerManager.timerColor; solid → timerSolidColor (150-157).

### Data sources and APIs

TimerManager.shared, LockScreenManager.isLocked (hides inline controls), Defaults; text measured with NSAttributedString size() using NSFont.systemFont / monospacedSystemFont (195-218). Hosted in ContentView.swift:1139 when vm.notchState == .closed && timerManager.isTimerActive && coordinator.timerLiveActivityEnabled && !vm.hideOnClosed and no higher-priority expansion; music live activity takes precedence (1135-1140). All PUBLIC.

### Settings

timerShowsCountdown, timerShowsProgress, timerShowsLabel, timerProgressStyle, timerIconColorMode, timerSolidColor, timerPresets, timerControlWindowEnabled (inline controls), enableMinimalisticUI (suppresses transient label), timerLiveActivityEnabled (AppStorage).

### Dependencies

Defaults.

### Implementation notes

Reimplement as a ClosedNotchTimerActivity view with the same width functions so the notch window width can be computed before render (Notchy's geometry resolver must add leftWingWidth + rightWingWidth to the closed notch width). ~550 lines.

### Key files

- `DynamicIsland/components/Timer/TimerLiveActivity.swift`
- `DynamicIsland/ContentView.swift`
- `DynamicIsland/sizing/matters.swift`

## Timer – popover mode (TimerPopover, TimerIconAnimation, header button)

### Behaviour

When timerDisplayMode == .popover, the open-notch header shows a 30×30 black capsule button with a 'timer' glyph instead of a Timer tab; clicking toggles a 300pt-wide HUD popover anchored below it containing: header (24pt gradient circle icon + 'Timer' title + status), either the active timer card (name, 28pt countdown, optional linear progress, Pause/Resume + Stop buttons) or a custom timer section (three steppers H/M/S, formatted duration, 'Start Custom Timer'), a divider, then a 'Presets' list (max 200pt). Starting anything dismisses the popover.

### Layout

Header button: Capsule fill .black 30×30 overlay headerGlyph('timer'), .popover(arrowEdge: .bottom) (A/components/Notch/DynamicIslandHeader.swift:214-239). Popover root VStack(spacing 16).padding(16).frame(width 300).background(VisualEffectView(.hudWindow, .behindWindow).cornerRadius(12)) (A/components/Timer/TimerPopover.swift:41-66). HeaderView HStack(spacing 12){ TimerIconAnimation 32×32; VStack(.leading, spacing 2){ 'Timer' 14 semibold; status 11 medium .secondary } } (116-134). ActiveTimerSection: VStack(.leading, spacing 12){ name 15 semibold lineLimit 1; time 28 bold monospaced (red overtime) numericText; ProgressView linear tint when bar; HStack(spacing 8){ Pause/Resume .bordered 12 medium; Stop .borderedProminent destructive } }.padding(12).background(white 0.08).clip RoundedRectangle 10 continuous (137-190). CustomTimerSection: title 14 semibold; Grid(hSpacing 6, vSpacing 8) of DurationStepper width 88 (title 8.5 medium, value 12 semibold monospaced); duration 12 medium monospaced .secondary; 'Start Custom Timer' .borderedProminent 13 medium disabled at 0; padding 12 bg white 0.05 radius 10 (228-293). PresetList: 'Presets' 13 semibold padding leading 4; ScrollView VStack(spacing 8) of TimerPresetRow: Circle preset.color.gradient 20×20 stroke white 0.5; name 13 medium; duration 11 medium monospaced .secondary; trailing checkmark/play.fill 11 semibold padding 6 bg preset 0.2 when active; row padding h12 v10, RoundedRectangle 10 continuous fill active ? preset 0.18 : white 0.05 (295-375). TimerIconAnimation: ZStack{ Circle fill resolvedColor.gradient 24×24; 'timer' 12 medium white } (A/components/Timer/TimerIconAnimation.swift:29-38).

### Animations

Button toggle withAnimation(.smooth) (DynamicIslandHeader.swift:216-218); PresetList .animation(.smooth, value: activePresetId) (58); active card .animation(.smooth, value: isPaused) (189); ProgressView .smooth(0.2) (162); start/pause/stop wrapped in withAnimation(.smooth) (99-113, 192-210).

### State and timing

Idle icon colour = Defaults[.accentColor]; active adaptive → preset colour or ramp; solid → solid colour (TimerIconAnimation.swift:41-53).

### Data sources and APIs

TimerManager, Defaults, SwiftUI .popover, NSVisualEffectView wrapper. vm.isTimerPopoverActive keeps the notch from auto-closing while open; closing triggers vm.shouldRecheckHover after 0.1 s (DynamicIslandHeader.swift:231-238; ContentView.swift:2461-2471). PUBLIC.

### Settings

timerDisplayMode=.popover switches tab→popover; uses timerPresets, timerShowsCountdown, timerShowsProgress, timerProgressStyle, timerIconColorMode, timerSolidColor, customTimerDuration.

### Dependencies

Defaults.

### Implementation notes

Simple SwiftUI popover; ~380 lines.

### Key files

- `DynamicIsland/components/Timer/TimerPopover.swift`
- `DynamicIsland/components/Timer/TimerIconAnimation.swift`
- `DynamicIsland/components/Notch/DynamicIslandHeader.swift`

## Timer – macOS Clock timer mirroring (SystemTimerBridge)

### Behaviour

With 'Mirror macOS Clock timers' on, a timer started in Clock.app (or Siri) appears in the notch as an external timer named after the Clock timer (default 'Clock Timer'), updates live, shows pause state, and completes with the same smooth close. Pause/Resume/Cancel from the notch press the corresponding buttons in Clock.app via Accessibility when Clock is running and AX is trusted; otherwise controls are hidden. Manual notch timers always take priority over mirrored ones.

### Layout

n/a (feeds TimerManager).

### Animations

Main-thread updates throttled to one per 0.25 s (latest wins), completion bypasses throttle (A/managers/SystemTimerBridge.swift:95-106, 541-596). After completion a delayed cleanup fires at 3.2 s if the same session is still active (867-881).

### State and timing

Display name precedence: log Title > plist MTTimerTitle > 'Clock Timer' (524-534). totalDuration = max(seen durations, remaining) (508-522). Paused state from log is overridden to running when remaining drops by >0.75 s between updates or plist says running (806-817). After AX cancel: clearLogState(triggerSmoothClose: true) (1266-1268).

### Data sources and APIs

PRIVATE/undocumented data: (1) spawns /usr/bin/log stream --style ndjson --predicate 'subsystem == "com.apple.mobiletimer.logging" AND NOT eventMessage CONTAINS "MTXPCConnectionProvider" AND NOT ... "MTAlarmManager"' --level debug (273-328) and regex-parses messages 'scheduled timers:' (<MTTimer: TimerID:, state:, Title:, duration:>), 'Timer will fire N minutes', 'remainingTime:', 'next timer changed:', 'started timer:', 'Timer stopped' (608-931); restarts the stream 2 s after unexpected exit (368-383); 1 MB buffer cap (106). (2) CFPreferencesAppSynchronize/CopyAppValue('MTTimers', 'com.apple.mobiletimerd') and a DispatchSource file monitor on ~/Library/Preferences/com.apple.mobiletimerd.plist reading $MTTimer dicts MTTimerID/MTTimerTitle/MTTimerDuration/MTTimerLastModifiedDate/MTTimerFiredDate/MTTimerState (1 stopped,2 running,3 paused,4 fired) (35-59, 428-455, 964-1000). (3) Accessibility fallback ticker every 1 s (leeway 150 ms) reading the menu-bar timer extra via AXUIElementCreateSystemWide → kAXMenuBarAttribute → children, matching identifier/title/value containing 'timer' or 'H:MM:SS' (261-270, 1002-1144). (4) Control: AXUIElementCreateApplication(Clock pid), AXUIElementSetMessagingTimeout 2 s, DFS (max 2000 nodes) for AXIdentifier 'CancelButton' or 'PauseResumeButton' (AXDescription contains 'pause'/'resume'), AXUIElementPerformAction(kAXPressAction); activates Clock and retries once after 0.4 s if not found (1164-1287). Capability = mirrorSystemTimer && AXIsProcessTrusted() && Clock (com.apple.clock) running, refreshed on NSWorkspace launch/terminate and app didBecomeActive (117-151). REA confirms _AXIsProcessTrusted, _AXUIElementCreateSystemWide, _AXUIElementCreateApplication, _AXUIElementCopyAttributeValue, _NSTask, _NSWorkspaceDidLaunchApplicationNotification imports in the shipped binary.

### Settings

mirrorSystemTimer=true (Constants.swift:1328). Starting/stopping the monitor follows Defaults.publisher(.mirrorSystemTimer).

### Dependencies

Defaults.

### Implementation notes

Optional feature; requires Accessibility permission and is fragile (depends on Clock.app AX identifiers and undocumented log text). If implemented, isolate behind a protocol (ExternalTimerSource) with the same adopt/update/complete/end API and throttle to main every 0.25 s. ~1300 lines in Atoll; a minimal log-stream-only port is ~500.

### Key files

- `DynamicIsland/managers/SystemTimerBridge.swift`
- `DynamicIsland/managers/TimerManager.swift`

## Calendar – data layer (CalendarManager, CalendarService, EventModel, third-party apps)

### Behaviour

Events and reminders for the selected day (and a lock-screen look-ahead window) from all or a user-selected subset of calendars/reminder lists. Reminders can be completed from the notch. Tapping an event opens it in Apple Calendar (ical://ekevent/...), Fantastical (x-fantastical3://show/{mini|calendar}/yyyy-MM-dd) or Notion Calendar (cron://showEvent?...) per settings; reminders always open Reminders (x-apple-reminderkit://remcdreminder/{id}). Conference links are detected (Zoom, Teams, Meet, Webex, GoToMeeting, BlueJeans, Whereby, Jitsi, Discord, FaceTime) from URL, location or notes.

### Layout

n/a. Models: CalendarModel{accountName,id,title,color NSColor,isSubscribed,isReminder} (A/models/CalendarModel.swift:25-32); EventModel{id,start,end,title,location,notes,url,isAllDay,type(.event(AttendanceStatus)|.birthday|.reminder(completed)),calendar,participants,timeZone,hasRecurrenceRules,priority,conferenceURL}, eventStatus upcoming/inProgress/ended (A/models/EventModel.swift:27-95).

### Animations

lockScreenEvents updates wrapped in withAnimation(.smooth(duration: 0.25)) (A/managers/CalendarManager.swift:260-262, 329-331, 341-343).

### State and timing

reloadRefreshInterval 15 s; eventStoreChangeThrottle 20 s; selfInducedChangeSuppression 6 s; lockScreenRefreshInterval 15 s; loop 60 s.

### Data sources and APIs

EventKit (PUBLIC; REA: EventKit.framework LC_LOAD_DYLIB, _OBJC_CLASS_$_EKEventStore/EKEvent/EKReminder, _EKEventStoreChangedNotification): EKEventStore.requestFullAccessToEvents()/requestFullAccessToReminders() (A/Providers/CalendarServiceProviding.swift:54-63), calendars(for:), predicateForEvents(withStart:end:calendars:), events(matching:), predicateForReminders(in:) + fetchReminders filtered to due date in range (80-130), calendarItem(withIdentifier:) + save(reminder, commit: true) for completion (132-141). EKEventStoreChanged observed with 20 s throttle and 6 s self-induced-change suppression (49-54, 80-125). Events fetch for [currentWeekStartDate, +1 day) with 15 s dedupe (360-383); lock-screen events refresh loop every 60 s, window = yesterday 00:00 … now + lookahead (15m/30m/1h/3h default/6h/12h/rest_of_day/all_time=365d) (257-358). Serialised through an actor EventFetchLimiter (423-453). Birthday detection via event.birthdayContactIdentifier; attendance from attendees.first(where: isCurrentUser).participantStatus (208-229). NSWorkspace.openApplication for Notion fallback (200-210). NSDataDetector for conference links (340-351).

### Settings

showCalendar=true (Constants.swift:1036); hideCompletedReminders=true; hideAllDayEvents=false (1037-1038); calendarSelectionState=.all (enum CalendarSelectionState .all | .selected(Set<String>), 255-258, 1230); showFullEventTitles=false; autoScrollToNextEvent=true (1231-1232); enableThirdPartyCalendarApp=false; selectedCalendarApp=.fantastical (ThirdPartyCalendarApp fantastical|notionCalendar, bundle ids com.flexibits.fantastical2.mac / com.cron.electron, 272-306, 1166-1167); fantasticalDefaultView (FantasticalViewStyle mini|calendar, 260-270); lockScreenCalendarEventLookaheadWindow='3h' and other lockScreen* keys (1153-1162).

### Dependencies

Defaults.

### Implementation notes

Port 1:1 using EventKit on macOS 14 (requestFullAccess APIs). Keep ids = calendarItemIdentifier. ~450 (manager) + ~360 (service) + ~220 (model) lines.

### Key files

- `DynamicIsland/managers/CalendarManager.swift`
- `DynamicIsland/Providers/CalendarServiceProviding.swift`
- `DynamicIsland/models/EventModel.swift`
- `DynamicIsland/models/CalendarModel.swift`

## Calendar – Home-tab compact panel (CalendarView, WheelPicker, EventListView, AllDayEventsStrip, ConferenceJoinButton)

### Behaviour

On the Home tab, when 'Show calendar' is on and the music player is also shown, a 120pt-tall calendar panel sits to the right of the player. Collapsed header shows one line 'Wed, Oct 15'; hovering the header expands a 50pt horizontal date strip (7 days past … 14 days future, weekday initial over day number, today's number in an accent circle, selected day highlighted with accent 25% rounded background) with 16pt edge fades; the strip is scrubbable by trackpad scroll or mouse drag. Below is the event list for the selected day: all-day events in a single horizontally scrolling 28pt chip row floating over the list; timed events as rows with a 3pt colour bar, title (2 lines, or unlimited), location, a 'Join/Rejoin <Provider>' button for conference links, start/end times; reminders with a 14pt circular toggle. The list auto-scrolls (centre anchor) to the active-conference → in-progress → next-upcoming → last event. Empty state: calendar.badge.checkmark + 'No events today' / 'Enjoy your free time!'. Opening the notch resets selection to today.

### Layout

A/components/Calendar/DynamicIslandCalendar.swift. CalendarView root VStack(spacing 0){ header HStack(.center, spacing 8){ left label VStack(.leading, spacing 1) width 72: expanded → month .headline semibold white + year .caption white 0.65; collapsed → 'EEE, MMM d' .subheadline medium white; ZStack{ WheelPicker; fades LinearGradient black 0.45→clear width 16 leading/trailing }.frame(height expanded ? 50 : 0).opacity(expanded?1:0).clipped }.padding(.horizontal 4).padding(.top 2); list }.frame(height: 120) (369-460). WheelPicker (186-367): ScrollView(.horizontal) HStack(spacing 0) with 2 spacer cells 24×24 each end; cells Button VStack(spacing 8){ weekday 'E' .caption (white if selected else white 0.65); ZStack{ Circle fill accent 20×20 if today; day .body medium (white selected / white 0.9 today / white 0.65) } }.padding(v4,h4).background(selected ? accent.opacity(0.25) : clear).cornerRadius(8); container height 50; scrollTargetBehavior .viewAligned, scrollPosition anchor .center, safeAreaPadding horizontal; Config past 7 future 14 steps 1 offset 2 (168-175). EventListView (1040-1290): ZStack(.top){ List(.plain, scrollContentBackground hidden, indicators never){ rows Button(plain) .padding(.leading,-5) separator .automatic tint gray 0.2, rowBackground clear }.padding(.top, allDay ? 30 : 0); AllDayEventsStrip.background(black 0.95) }. Event row: HStack(.top, spacing 4){ Rectangle calendar colour width 3 cornerRadius 1.5; VStack(.leading, spacing 2){ title .callout medium white lineLimit(showFull ? nil : 2); location .caption white 0.65 lineLimit 1; ConferenceJoinButton }; Spacer; VStack(.trailing, spacing 4){ 'All-day' .caption medium | start white / end white 0.65 .caption }.frame(minWidth 44) } opacity 0.6 if ended today (1240-1288). Reminder row: HStack(spacing 8){ ReminderToggle; title .callout white lineLimit(showFull ? nil : 1); Spacer; time/All-day .caption }.padding(.vertical 4), opacity 0.4 completed / 0.6 past-today (1187-1238). ReminderToggle: Circle strokeBorder colour 2pt 14×14, inner fill Circle 8×8 when on (1292-1318). AllDayEventsStrip: chipRowHeight 28, verticalPadding 3, listTopInset 30 (52-80); ScrollView(.horizontal) HStack(spacing 8).padding(h 4, v 3); chip HStack(spacing 6){ Circle calendar colour 8×8; title .caption medium white lineLimit 1; 'All-day' .caption2 white 0.6; reminder toggle }.padding(h 8, v 3).background(Capsule white 0.08); 1pt divider gray 0.2 below (91-149). ConferenceJoinButton: HStack(spacing 4){ 'video.fill' 9pt; 'Join'/'Rejoin' + provider name .caption2 medium }.padding(h8,v4).background(joinable ? provider.color.opacity(0.85) : gray 0.3).cornerRadius(6); joinable from 15 min before start; provider colours Zoom (0.16,0.52,0.95), Teams (0.36,0.42,0.89), Meet (0,0.65,0.42), Webex (0,0.71,0.84), FaceTime (0.2,0.78,0.35), GoToMeeting (0.95,0.5,0.13), BlueJeans (0,0.48,0.87), Whereby (0.27,0.51,0.96), Jitsi (0.16,0.68,0.95), Discord (0.35,0.39,0.98); native schemes zoommtg/msteams/facetime/discord (1323-1440). EmptyEventsView: 'calendar.badge.checkmark' 20 regular white 0.65 padding bottom 7; 'No events today'/'No events' .subheadline white; 'Enjoy your free time!' .caption white 0.65 padding top 1 (774-796). Hosted in NotchHomeView HStack(alignment .top, spacing 20){ MusicPlayerView; calendar.frame(maxWidth .infinity); mirror } with 8pt outer padding (A/components/Notch/NotchHomeView.swift:959-990); CalendarView chosen when the music player is shown, StandaloneCalendarView otherwise (966-973).

### Animations

Header expand/collapse withAnimation(.easeInOut(duration: 0.18)) on hover (432-436). WheelPicker click: withAnimation (default) scrollPosition; .sensoryFeedback(.alignment, trigger: haptics) when enableHaptics (215-232); mouse drag scrub steps = -translation/measuredCellWidth without animation (258-276). Auto-scroll uses withTransaction(Transaction(animation: nil)) + proxy.scrollTo(id, anchor: .center) inside DispatchQueue.main.async (1088-1102). Home-tab content transition .opacity.animation(.smooth.speed(0.9)) + move(.top), blur 30 when closed (NotchHomeView.swift:987-989).

### State and timing

selectedDate changes call calendarManager.updateCurrentDate (force fetch). On vm.notchState change and onAppear → today (460-476). initialAutoScrollDone guards re-scroll on data refresh (1151-1166). vm.isHoveringCalendar set on hover (NotchHomeView 975-977).

### Data sources and APIs

CalendarManager.shared (EventKit), Defaults, openURL environment, NSWorkspace. PUBLIC.

### Settings

showCalendar, hideAllDayEvents, hideCompletedReminders, showFullEventTitles, autoScrollToNextEvent, enableHaptics, accentColor (Color.effectiveAccent = Defaults[.accentColor], effectiveAccentBackground = accent 0.25; A/extensions/Color+AccentColor.swift).

### Dependencies

Defaults.

### Implementation notes

Port into Notchy's home view as a 120pt panel. Keep AllDayStripMetrics (28/3/30) and auto-scroll priority rules (scrollTargetForTimedEvents, 33-54; reminders count as in-progress for 1 h). ~700 lines for this half of the file.

### Key files

- `DynamicIsland/components/Calendar/DynamicIslandCalendar.swift`
- `DynamicIsland/components/Notch/NotchHomeView.swift`
- `DynamicIsland/extensions/Color+AccentColor.swift`

## Calendar – standalone month-grid view (StandaloneCalendarView, StandaloneEventCardList)

### Behaviour

When the calendar is shown without the music player (media controls off), the Home tab becomes a two-pane calendar: left pane is a month picker (month title + year, chevron prev/next, 7-column weekday initials, scrolling day grid with 28pt accent circle on the selected day, today in accent, other-month days dimmed, 16pt top/bottom fades, auto-centred on the selected date); right pane is a card list of the day's events (all-day chip strip floating on top; timed events as 14pt-radius cards with a 4×36 colour bar, title, location, Join button, start/end; reminders as cards with toggle). Empty state identical to compact view.

### Layout

Root GeometryReader; paneSpacing 12; paneWidth = (width-12)/2; HStack(.top, spacing 12){ left; right } each .frame(width paneWidth, height paneHeight, .topLeading).layoutPriority(1); .frame(height: maxTabContentHeight = max(130, notchHeight - max(24, closedHeight) - 36)) (A/components/Calendar/DynamicIslandCalendar.swift:517-568). leftPickerPane: pickerViewportHeight = max(96, height-56); VStack(.leading, spacing 10){ HStack{ month .title3 semibold white + year .subheadline medium white 0.65 (firstTextBaseline, spacing 4); Spacer; chevrons 11 bold in 24×24 frames spacing 6 }; VStack(spacing 6){ LazyVGrid 7 cols GridItem(.flexible(minimum 14), spacing 6) spacing 6: weekday symbol prefix(1) .caption2 semibold white 0.55; ZStack{ ScrollView(.vertical) LazyVGrid same columns of dayCell (padding bottom 2); fades 16pt black 0.65 } .frame(height pickerViewportHeight-22).clipped } }.padding(.horizontal 6).padding(.top 4) (580-682). dayCell: Button ZStack{ Circle fill accent 28×28 if selected; day text 12 (semibold selected / medium) colour white selected / white 0.35 other month / accent today / white }.frame(maxWidth .infinity, minHeight 30) (707-739). StandaloneEventCardList (804-1038): List(.plain) rows .padding(.bottom 8), rowInsets zero, separators hidden; List .padding(.top 30 if all-day); AllDayEventsStrip overlay .background(black 0.95). calendarEventCard: HStack(.top, spacing 10){ RoundedRectangle r2 fill colour 4×36; VStack(.leading, spacing 4){ title .callout semibold white; location .caption white 0.65; ConferenceJoinButton }; Spacer(minLength 8); VStack(.trailing, spacing 2){ 'All-day' .caption medium white | start .caption white + end .caption2 white 0.65 } }.padding(h 11, v 8).frame(maxWidth .infinity, minHeight 50).background(RoundedRectangle 14 continuous fill white 0.05); opacity 0.6 if ended today (986-1037). reminderCard: HStack(spacing 10){ ReminderToggle; VStack(.leading, spacing 4){ title .callout medium white lineLimit 2|nil; 'All-day' .caption white 0.65 }; Spacer(8); start .caption white 0.75 }.padding(h11,v8) minHeight 50 same background; opacity 0.55 when completed (937-984); reminders wrapped in plain Button, both with .padding(.horizontal 2) (914-935).

### Animations

Day select withAnimation(.smooth(duration: 0.18)) (713-715); month change .smooth(0.22) (743-755); displayedMonth follows selectedDate with .smooth(0.22) (578-585); centre scroll withAnimation(.smooth(duration: 0.24)) proxy.scrollTo(day, anchor: .center) (761-771). Auto-scroll of event list without animation, centre anchor (824-838).

### State and timing

On appear and on notch open: selectedDate = now, displayedMonth = startOfMonth, request centre scroll, fetch (553-594).

### Data sources and APIs

CalendarManager (EventKit), Defaults, Calendar.current (firstWeekday honoured). PUBLIC.

### Settings

showCalendar, showStandardMediaControls (off → standalone), hideAllDayEvents, hideCompletedReminders, showFullEventTitles, autoScrollToNextEvent, accentColor.

### Dependencies

Defaults.

### Implementation notes

Reuse the same event-card components as the compact list; grid built from dateInterval(of: .month) expanded to full weeks (509-524). ~450 lines.

### Key files

- `DynamicIsland/components/Calendar/DynamicIslandCalendar.swift`

## Calendar – Reminder live activity (ReminderLiveActivityManager, ReminderLiveActivity, music supplement)

### Behaviour

N minutes (default 5) before the next event/reminder, the closed notch shows a calendar glyph tinted with the calendar colour on the left and, on the right, a ring countdown (default), a 'MM:SS' digital countdown or 'in N min'. A sneak peek is triggered when the lead window starts (duration reminderSneakPeekDuration, default 5 s) and again with a red 'calendar.badge.exclamationmark' when the remaining time drops inside the sneak-peek window (critical). At event start it advances to the next entry. In minimalistic UI the open notch gains rows listing active-window reminders (30pt rows, 8 spacing, 14 top, 10 bottom padding).

### Layout

A/components/Calendar/ReminderLiveActivity.swift: wingPadding 16, ringStrokeWidth 3 (36-37); notchContentHeight = effectiveClosedNotchHeight (39-41); HStack(spacing 0){ Color.clear width leftWingWidth = 16 + iconDiameter with icon padded leading 8; black Rectangle closedNotchSize.width; Color.clear width rightWingWidth with content padded trailing 8 }.frame(height h) (52-74). iconDiameter = max(h-8, 26); icon Image 16 semibold accent (76-85, 194-196). ringCountdownSection: ringDiameter = clamp(h-12, 16, 22); track white 0.15 lw 3; progress accent lw 3 round cap -90° (100-115, 198-200). digitalSection: Text 'MM:SS' 16 semibold monospaced accent (117-125), width = max(textWidth(monospacedDigit 16 semibold)+18, 76) (182-186). minutesSection: 'in N min' 13 semibold accent, width max(w+18, 88) (127-134, 188-192). rightWingWidth = 16 + ring|digital|minutes width (169-180). accent = red when critical else Color(calendar.color).ensureMinimumBrightness(factor: 0.7) (158-163). Transition .opacity.combined(with: .move(edge: .bottom)) (46). Music-paired variant: MusicReminderSupplementView with ReminderSupplementMetrics ring diameter from notch height, digital width max(w(15 semibold monoDigit)+18,76), minutes width max(w+18,88); wing width = max(base, 16 + width) (ContentView.swift:1603-1618, 3268-3290); album badge 'clock' glyph (1650-1654).

### Animations

Ring progress .animation(.smooth(duration: 0.25), value: progress) (111); digital .contentTransition(.numericText()) .smooth(0.25) (122-123). Manager ticks every 1 s while a reminder is active (423-436), debounces calendar event updates 0.35 s and settings 0.2 s (63, 67).

### State and timing

progress = (lead - remaining)/lead clamped (136-142). Critical when 0 < remaining <= sneakPeekDuration (227-232); critical sneak peek shown once with duration min(window, remaining-2) (512-528). Lock-screen pause/resume cooldown 5 s (71).

### Data sources and APIs

CalendarManager.events via Combine; DynamicIslandViewCoordinator.toggleSneakPeek(status:type:.reminder, duration:, icon:) (A/managers/ReminderLiveActivityManager.swift:500-528). PUBLIC.

### Settings

enableReminderLiveActivity=true; reminderPresentationStyle=.ringCountdown (ReminderPresentationStyle ringCountdown|digital|minutes raw 'Ring'/'Digital'/'Minutes', Constants.swift:771-788); reminderLeadTime=5 (minutes); reminderSneakPeekDuration=5 (s) (1333-1336); hideAllDayEvents, hideCompletedReminders.

### Dependencies

Defaults.

### Implementation notes

Build entries: for each event with start > now (skipping all-day if hidden, completed reminders if hidden) trigger = start - lead; sorted by trigger (367-393). evaluateCurrentState: if start <= now → drop & advance; if trigger <= now → active + ticker; else schedule evaluation at trigger (456-542). ~700 (manager) + ~230 (view) lines.

### Key files

- `DynamicIsland/managers/ReminderLiveActivityManager.swift`
- `DynamicIsland/components/Calendar/ReminderLiveActivity.swift`
- `DynamicIsland/ContentView.swift`

## Color picker (ColorPickerManager, PickedColor, NotchColorPickerView, ColorPickerPopover, ColorPickerPanel, ColorPickedFeedbackView)

### Behaviour

An 'eyedropper' header button (30×30 black capsule) and global shortcut Cmd+Shift+P invoke the system colour loupe (NSColorSampler). The picked colour is converted to sRGB, prepended to a persisted history (max 50 stored), its HEX string is copied to the clipboard, a haptic fires, and a floating 450×600 'Color Picker' HUD panel (history list + detail pane with HEX/RGB/RGBA/HSL/HSLA/HSV/SwiftUI/UIColor rows, copy buttons with 1.5 s checkmark, search, delete-with-alert, clear) reopens 0.1 s later; a 'Color Picked!' feedback flag is raised for 2 s. In popover mode the header button shows a 240pt HUD popover (Pick Color, Show Color History, 6-column grid of 24pt recent swatches). The NotchColorPickerView (notch tab 'colorPicker', not in the tab bar in 2.3.3) shows 'Recent Colors' with count, a blue 'Pick Color' button and an up-to-8-column grid of 32pt swatches (first 15) with hover scale and a 220pt info popup.

### Layout

NotchColorPickerView (A/components/Notch/NotchColorPickerView.swift): VStack(spacing 16){ header HStack{ VStack(.leading, spacing 4){ HStack(spacing 8){ 'eyedropper.halffull' 16 medium; 'Recent Colors' 16 semibold }; '\(n) colors' 12 .secondary }; Spacer; Pick Color button HStack(spacing 6){ 'plus.circle.fill' 12 medium; text 12 medium } white, padding h12 v6, bg .blue, cornerRadius 8, pointingHand cursor }; grid LazyVGrid(columns = min(Int((400+12)/(32+12)), 8) of GridItem(.fixed(32), spacing 12), spacing 12).padding(.horizontal 8); Spacer }.overlay(ColorInfoPopup, alignment .topTrailing) (55-187). ColorCircleView: Circle fill 32×32, overlay stroke white 0.8 (2pt hovered / 1pt), stroke black 0.2 1pt, shadow black 0.3 radius 4/2 y 2/1, scaleEffect 1.1 hovered (202-226). Empty state: 'eyedropper' 28 .secondary; 'No Colors Yet' 16 medium; hint 12 .secondary padding h20 v40 (121-139). ColorInfoPopup: width 220 padding 12, RoundedRectangle 12 fill black 0.9 + stroke gray 0.3, shadow black 0.4 r15 y8; header Circle 24 + 'Picked Color' 12 semibold + time-ago 10; Divider; first 4 formats (or HEX only) as ColorFormatRow (name 10 medium mono width 40; value 10 mono middle-truncated; copy 'doc.on.doc' 10 blue on hover; row padding h8 v4 bg white 0.1 hovered r6) (228-351). Disabled state: 'eyedropper.halffull' 32; 'ColorPicker Disabled' .headline; hint .caption (37-53). ColorPickerPopover (A/components/ColorPicker/ColorPickerPopover.swift): VStack(spacing 16){ header (icon 14 medium + 'Color Picker' 14 semibold + xmark 12); VStack(spacing 12){ 'Pick Color' full-width blue r8 padding v8 14 medium; 'Show Color History' gray 0.2 r8 }; 'Recent Colors' 12 medium .secondary + LazyVGrid 6 flexible cols spacing 4 of Circle 24 (first 12) }.padding(16).frame(width 240).background(VisualEffectView .hudWindow .behindWindow).cornerRadius(12) (26-133). ColorPickerPanel (A/components/ColorPicker/ColorPickerPanel.swift): NSPanel [.borderless,.nonactivatingPanel,.fullSizeContentView], level .floating, movableByWindowBackground, canJoinAllSpaces/stationary/fullScreenAuxiliary, hasShadow, corner mask 12 continuous, size 450×600, position restored from UserDefaults colorPickerPanelPositionX/Y else screen centre (83-187); content VStack(spacing 0){ header (NativeStyleCloseButton 13pt red circle with 8pt xmark, scale 1.1 hover; icon 16 + title 16 semibold; Pick Color blue button 14 medium; trash 14 red; search field 14 in gray 0.1 r8 padding h12 v8).padding(16); Divider gray 0.3; HSplitView{ list minWidth 200 (header 'Recent Colors' 14 semibold + count badge 12 medium gray 0.2 r4, rows ColorListRow: Circle 32, hex 14 medium mono + time 12, hover copy/trash 12, selected bg blue 0.2, hover gray 0.1, padding h16 v8); details minWidth 220 (Rectangle 80 tall r8 stroke white 0.8 2pt shadow; 'Picked N ago' 12; 'Color Formats' 14 semibold; ColorFormatDetailRow name 12 mono width 60, value 12 mono, copy/checkmark 12 blue/green, padding h12 v6) } }.background(.hudWindow).cornerRadius(12) (189-662). ColorPickedFeedbackView: RoundedRectangle 12 fill colour 60×60 stroke white 0.8 2pt shadow r8; 'Color Picked!' 14 semibold; hex 12 medium mono in gray 0.2 r6; padding 16, hudWindow bg, r16, shadow black 0.3 r12 (22-68). Header button DynamicIslandHeader.swift:181-212.

### Animations

Swatch hover .easeInOut(duration: 0.2) (NotchColorPickerView.swift:149, 222); popup transition insertion .scale+.opacity, removal .opacity (193-196); format-row hover .easeInOut 0.2 (343); panel rows .easeInOut 0.2 hover, copied state 1.5 s (ColorPickerPanel.swift:519-523, 649-661); close button .easeInOut 0.1 (696-699); feedback view .spring(response: 0.4, dampingFraction: 0.7) scale 0.8→1 / opacity (ColorPickedFeedbackView.swift:57-59).

### State and timing

isPickingColor true during loupe; on pick: isPickingColor=false, addColor (dedupe by id, insert at 0, cap 50, save, copy hex), showColorPickedFeedback=true, panel reopened after 0.1 s, feedback cleared after 2 s (86-149).

### Data sources and APIs

NSColorSampler().show { NSColor? } (PUBLIC, macOS 10.15+; REA: _OBJC_CLASS_$_NSColorSampler imported) (A/managers/ColorPickerManager.swift:70, 96-120); NSColor.usingColorSpace(.sRGB); NSEvent.mouseLocation stored as displayPoint; NSPasteboard.general setString(hex) (181-188); NSHapticFeedbackManager .generic when enableHaptics (111-114); history persisted as JSON under UserDefaults 'ColorPickerHistory' (196-209); KeyboardShortcuts name colorPickerPanel default Cmd+Shift+P (A/Shortcuts/ShortcutConstants.swift:28). PickedColor formats: hex '#RRGGBB' (+AA when alpha<1, Int truncation), 'rgb(r, g, b)', 'rgba(r, g, b, a.aa)', 'hsl(h, s%, l%)', 'hsla', 'hsv', 'Color(red: %.3f, ...)', 'UIColor(...)' (A/models/PickedColor.swift:41-102). All PUBLIC.

### Settings

enableColorPickerFeature=true; showColorFormats=true; colorPickerDisplayMode=.panel (ColorPickerDisplayMode popover|panel); colorHistorySize=10 (picker offers 5/10/15/20); showColorPickerIcon=true (Constants.swift:1351-1356); UserDefaults 'ColorPickerHistory' (Data), 'colorPickerPanelPositionX'/'Y'; enableHaptics.

### Dependencies

Defaults (MIT), KeyboardShortcuts 2.3.0 (MIT) for the global hotkey.

### Implementation notes

NSColorSampler is the only non-trivial piece and is public. Manager ~200 lines, models ~200, views ~1,300 total. Note ColorPickerManager_Fixed.swift is an empty licence-only stub. colorHistorySize setting is defined but not read anywhere in the manager (history capped at 50 in code, UI shows first 15/12).

### Key files

- `DynamicIsland/managers/ColorPickerManager.swift`
- `DynamicIsland/models/PickedColor.swift`
- `DynamicIsland/components/Notch/NotchColorPickerView.swift`
- `DynamicIsland/components/ColorPicker/ColorPickerPanel.swift`
- `DynamicIsland/components/ColorPicker/ColorPickerPopover.swift`
- `DynamicIsland/components/ColorPicker/ColorPickedFeedbackView.swift`
- `DynamicIsland/Shortcuts/ShortcutConstants.swift`

## Notes tab (NotchNotesView, NoteListView, NoteRow, NoteEditorView, AppleNotesSyncManager) – summary

### Behaviour

Tab 'Notes' (SF 'note.text') when enableNotes (or 'Clipboard' when clipboard separateTab mode without notes; both → split view with NotchClipboardView(fixedColumns: 2) on the left). List of colour-coded sticky notes (yellow/blue/red/green/purple/orange), pinned first then by modification date; >3 notes switches to a compact 2-column grid. Hover reveals pin/copy/delete pill; tap opens an editor (title field, 6 colour dots, TextEditor, optional 55pt image thumbnail, char count) that auto-saves 1.5 s after edits and on close; Cmd+V pastes text/images into a note or creates one; 'Create from clipboard' button; search + colour filter row; 'Delete All' alert. Optional two-way sync with Apple Notes into an 'Atoll' folder via AppleScript. Notch height grows to 240 (list) / 260 (split) / 320 (editor).

### Layout

A/components/Notch/NotchNotesView.swift. Root HStack(spacing 0){ [clipboard pane + Divider white 0.15]; ZStack{ editor | list }.clipped } (49-104). List header HStack padding h16 top 8 bottom 2/4: 'Notes' 16 semibold rounded; sync icon 11; buttons 16×16 glyphs padded 5 on white 0.1 circles (sync 13, search 14, clipboard 13, trash 14 red, plus 14 bold) (489-585). Search field 12 in white 0.05 r8 padding h10 v4; colour filter capsules 10 medium, dots 14 with white 2pt ring (587-649). Empty: 'note.text' 16 + 'No notes yet' 12 medium rounded (650-664). Grid LazyVGrid 1 or 2 flexible columns spacing 8, padding h16 bottom 20, 16pt black 0.65 fades top/bottom (666-698). NoteRow: HStack(spacing 12|8){ RoundedRectangle r3 colour bar width 4|3; VStack(spacing 4|1){ [pin 8|7] title 14|12 semibold rounded white lineLimit 1; content 12|10 white 0.7 lineLimit 2|1 } }.padding(.trailing 130|50).padding(12|8); background RoundedRectangle 12 fill white 0.12 hover / 0.08 + stroke colour 0.2; trailing overlay: hover pill HStack(spacing 4|3) of 11|9pt buttons padded 6|5 on white 0.2 circles inside Capsule fill Color(white 0.12) stroke white 0.1 shadow black 0.3 r3; else time-ago 10pt; image thumb 50|32 r6 (728-884). NoteEditorView: toolbar '< Notes' 15 medium rounded / 'Done' 15 bold rounded in note colour, padding 16; title TextField 17 bold rounded; colour dots 16 in horizontal scroll maxWidth 160; Divider white 0.1; TextEditor 13 rounded lineSpacing 4 padding 8 (+20 bottom, +75 trailing when image) bg white 0.05, placeholder 'Start typing...' 13 white 0.5; image 55×55 r10 with xmark.circle.fill 14 remover offset (4,-4); char count 10 medium mono in black 0.5 r4; background .black (911-1065).

### Animations

List↔editor: .animation(.spring(response: 0.35, dampingFraction: 0.8)) on isEditingNewNote/selectedNoteId with asymmetric .move(edge: .trailing) for editor and .move(edge: .leading) for list (73, 86, 91-92). Search expand .spring(0.35, 0.8) + transition .move(.top)+.opacity (529-531, 647). Row hover .easeInOut 0.2 (871-873); copy checkmark 1.5 s (809-817); sync icon rotates .linear(1 s).repeatForever (501-507). Editor state cleared 0.3 s after close (420-423).

### State and timing

Auto-save debounce 1.5 s (276-287). Untitled notes saved as 'Untitled Note'. Merge rule: newer modificationDate wins; unlinked remote notes imported with colorIndex 0; local notes whose Apple id vanished are removed (126-183).

### Data sources and APIs

Defaults[.savedNotes] ([NoteItem] Codable; images stored as PNG files in ~/Documents/NoteImages/note_image_<uuid>.png, A/models/Constants.swift:872-960); NSPasteboard (file URLs, .tiff, .png, .string); keyboardShortcut('v', .command) hidden button (94-101); vm.setScrollGestureSuppression / setAutoCloseSuppression. Apple Notes sync: NSAppleScript via AppleScriptHelper (REA: _OBJC_CLASS_$_NSAppleScript) — fetch all non-password notes of default account with ␟/␞ separators, create/update/delete notes in folder 'Atoll', bodies as <div> HTML with trailing '<!--atoll:id=UUID-->' marker; automation denial (-1743) surfaced as error (A/managers/AppleNotesSyncManager.swift:207-416). Requires Automation permission for Notes (PUBLIC but permissioned).

### Settings

enableNotes=false; enableNotePinning=true; enableNoteSearch=false; enableNoteColorFiltering=false; enableCreateFromClipboard=true; enableNoteCharCount=true; savedNotes=[]; enableAppleNotesSync=false; appleNotesLastSyncDate=nil (Constants.swift:1517-1526); clipboardDisplayMode=.panel (.separateTab merges with notes). NotesLayoutState preferredHeight list 240/split 260/editor 320 (A/enums/generic.swift:86-101).

### Dependencies

Defaults.

### Implementation notes

Port list/editor UI (~1,070 lines). Apple Notes sync is optional (~420 lines) and needs NSAppleEventsUsageDescription.

### Key files

- `DynamicIsland/components/Notch/NotchNotesView.swift`
- `DynamicIsland/managers/AppleNotesSyncManager.swift`
- `DynamicIsland/enums/generic.swift`
- `DynamicIsland/models/Constants.swift`

## Terminal tab (TerminalManager, NotchTerminalView, SwiftTerm) – summary

### Behaviour

Tab 'Terminal' (SF 'apple.terminal') when enableTerminalFeature; global shortcut Ctrl+` toggles it. A Guake-style dropdown: the notch grows to terminalMaxHeightFraction of the screen (min 300pt) and hosts a persistent login shell (default /bin/zsh) that survives notch close/open and tab switches; header shows the shell-reported title and a restart button; the terminal block has a frosted blur underlay, translucent background per opacity setting, a custom 6pt rounded scroll knob, and the terminal is focused on appear.

### Layout

A/components/Notch/NotchTerminalView.swift: VStack(spacing 0){ header HStack{ 'apple.terminal' 11; title 11 medium lineLimit 1; Spacer; restart 'arrow.counterclockwise' 10 }.padding(h12, top 6, bottom 4) coloured terminalForegroundColor; Divider padded 8; TerminalNSViewRepresentable.clipShape(UnevenRoundedRectangle top 6 / bottom = outer shell bottom radius - 8, continuous).padding(top 4, h 8, bottom 8) } (123-197). Constants: notchTerminalContentEdgePadding (4, 8, 8), notchTerminalInnerTextInset 6, notchTerminalBottomCornerRadii (A/sizing/matters.swift:205-244). Disabled placeholder: icon 28 + 'Terminal is disabled' 12 medium + hint 10 .tertiary (173-188). Scroll knob thickness 6, end inset 3, right margin 2, white 0.45, cornerRadius 3, min proportion 0.04 (A/managers/TerminalManager.swift:156-176, 443-496). Notch height: min(screen*fraction, max(300, screen*fraction)) (ContentView.swift:205-211).

### Animations

Knob alpha via animator(); no SwiftUI animations besides tab transition.

### State and timing

Terminal view created lazily on first tab visit; restartShell terminates process and remounts; processDidTerminate sets isProcessRunning=false and updateNSView restarts the shell on next appearance (286-306).

### Data sources and APIs

SwiftTerm LocalProcessTerminalView (forkpty-based; REA: _forkpty import, SwiftTerm_SwiftTerm.bundle in app; no dylib → statically linked) started with executable = terminalShellPath, args [], execName '-zsh' (login shell), env TERM=xterm-256color, LANG default en_US.UTF-8, TERM_PROGRAM removed (271-301, 627-635). NSVisualEffectView .underWindowBackground/.behindWindow underlay; gutter tint ring masked with CAShapeLayer evenOdd (43-92, 161-200). KVO on SwiftTerm's NSScroller doubleValue/knobProportion/isEnabled (413-451). Focus via window.makeFirstResponder with 3 retries at 50 ms (556-601). vm.setScrollGestureSuppression on hover. PUBLIC + MIT dependency.

### Settings

enableTerminalFeature=false; terminalShellPath='/bin/zsh'; terminalFontFamily=''; terminalFontSize=12; terminalOpacity=1.0; terminalMaxHeightFraction=0.4 (slider 0.2…0.5 step 0.05); terminalCursorStyle='blinkBlock' (TerminalCursorStyleOption 6 cases); terminalScrollbackLines=1000; terminalOptionAsMeta=true; terminalMouseReporting=true; terminalBoldAsBright=true; terminalBackgroundColor=.black; terminalForegroundColor=.white; terminalCursorColor=Color(.selectedControlColor); terminalStickyMode=false (Constants.swift:1300-1315). Shortcut toggleTerminalTab default Ctrl+` (ShortcutConstants.swift:34).

### Dependencies

SwiftTerm 1.13.0 (migueldeicaza, MIT). Defaults.

### Implementation notes

Requires adding SwiftTerm as an SPM dependency; keep a stable container NSView whose resizeSubviews ignores frames <10pt to protect scrollback (43-78). ~670 + ~200 lines.

### Key files

- `DynamicIsland/managers/TerminalManager.swift`
- `DynamicIsland/components/Notch/NotchTerminalView.swift`
- `DynamicIsland/sizing/matters.swift`

## Screen Assistant (ScreenAssistantManager, ChatPanels, ModelSelectionPanel, ScreenshotSnippingTool) – summary

### Behaviour

Cmd+Shift+A (or the header 'AI' button) opens two floating HUD panels: a 600×500 chat transcript panel 50pt from the left screen edge / 100pt from the top, and a 500×60 single-line input bar centred 100pt above the bottom. Users attach files (NSOpenPanel), record microphone audio, take full/window/area screenshots, pick a provider/model (Gemini default, OpenAI, Claude, Groq, Local/Ollama) in a 450×600 model panel, and chat; responses render simple markdown (bold). ESC closes.

### Layout

ChatMessagesPanel NSPanel [.borderless,.nonactivatingPanel], level .floating, hasShadow, corner mask 16, size 600×500, origin (visibleFrame.minX+50, maxY-500-100) (A/components/ScreenAssistant/ChatPanels.swift:34-105); ChatInputPanel 500×60, .fullSizeContentView, centred x, y = minY+100 (108-190); both .hudWindow/.behindWindow with cornerRadius 16. ModelSelectionPanel 450×600 (A/components/ScreenAssistant/ModelSelectionPanel.swift:95-110). RecordingButton 32pt circle red/blue 0.2 with mic.fill/stop.fill 14 (ScreenAssistantPanel.swift:212-234). AttachedFileChip 11pt text, blue 0.1 bg r6 maxWidth 120 (148-176). ScreenAssistantPanel itself is a 1×1 off-screen compatibility wrapper (25-93).

### Animations

Recording button scale 1.1 .easeInOut 0.2 (231-232); messages appear .easeOut 0.5 (ChatPanels.swift:290-298); screenshot button .easeInOut 0.2 (627).

### State and timing

isRecording with 1 s duration timer; isLoading while request in flight; activeRequest cancellable.

### Data sources and APIs

HTTPS APIs (PUBLIC third-party): Gemini https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key= (A/managers/ScreenAssistantManager.swift:418), OpenAI https://api.openai.com/v1/chat/completions (441), Groq https://api.groq.com/openai/v1/chat/completions (470), Claude https://api.anthropic.com/v1/messages (498), local {endpoint}/api/chat Ollama (517). Screenshots via Process /usr/sbin/screencapture -c | -cw | -cs then NSImage(pasteboard:) saved to ~/Documents/ScreenAssistantScreenshots/screenshot_<ts>.png (A/components/ScreenAssistant/ScreenshotSnippingTool.swift:30-184); audio via AVAudioRecorder into ~/Documents/ScreenAssistantAudio (121-138, 283-340). Files persisted to UserDefaults. REA: _NSTask import consistent with screencapture spawning. PUBLIC.

### Settings

enableScreenAssistant=true; screenAssistantDisplayMode=.panel (popover|panel); geminiApiKey/openaiApiKey/claudeApiKey/groqApiKey=''; selectedAIProvider=.gemini (AIModelProvider gemini|openai|claude|local|groq with supportedModels lists, Constants.swift:791-860); selectedAIModel=nil (1368-1376).

### Dependencies

Defaults, KeyboardShortcuts (screenAssistantPanel default Cmd+Shift+A, ShortcutConstants.swift:29).

### Implementation notes

Large (~1,300 manager + ~1,600 views). Low priority for a notch clone; if ported, isolate provider adapters behind one protocol.

### Key files

- `DynamicIsland/managers/ScreenAssistantManager.swift`
- `DynamicIsland/components/ScreenAssistant/ChatPanels.swift`
- `DynamicIsland/components/ScreenAssistant/ModelSelectionPanel.swift`
- `DynamicIsland/components/ScreenAssistant/ScreenshotSnippingTool.swift`
- `DynamicIsland/components/ScreenAssistant/ScreenAssistantPanel.swift`

## LLM usage tab (NotchLLMUsageView, LLMUsageManager, providers, quota clients) – summary

### Behaviour

Tab 'Usage' (SF 'chart.bar.doc.horizontal') when enableLLMUsageFeature. A row of equal-height cards, one per enabled provider (Claude, Codex, Cursor, Antigravity, New API): provider name (+ plan badge e.g. 'Max 5x' for Claude), loading spinner / error text / data: 5-hour 'Session' and 7-day 'Week' quota gauges (6pt capsule, accent → orange >90% → red >95%, '% used' / '% left', 'resets in …'), plus Today/Week token totals with an estimated USD cost (or 'est. n/a'). Antigravity has a Gemini/Claude segmented toggle; New API shows per-account balance/used/today/week and RPM/TPM/requests in a 135pt scroll. Refreshes on appear at most once per 60 s.

### Layout

A/components/Notch/NotchLLMUsageView.swift: HStack(.top, spacing 10){ cards }.padding(.horizontal 8).environment(colorScheme .dark) (37-47). Card VStack(.leading, spacing 6){ HStack(spacing 6){ name .headline minScale 0.7; plan .caption2 semibold padding h5 v1 in white 0.12 capsule .secondary; Spacer; [segmented Picker width 120 .mini] }; content }.padding(10).frame(maxWidth .infinity, maxHeight .infinity, .topLeading).background(white 0.06, RoundedRectangle 12) (49-98). quotaGauge: label .caption2 semibold .secondary + resets .caption2; GeometryReader ZStack(.leading){ Capsule white 0.15; Capsule tint width max(4, w*fraction) }.frame(height 6); '% used' / '% left' .caption2 monospacedDigit (241-266). window row: label .caption2 width 56|48; value rounded 11 compact / 17 prominent bold / 13 semibold monospacedDigit; cost .caption2 .secondary with help text (287-317). Token formatting 1.2M / 3.4k; currency formatter USD (335-361).

### Animations

None beyond ProgressView; tab transition only.

### State and timing

LLMUsageManager.refreshAll: minRefreshInterval 60 s, parallel TaskGroup per provider, results[provider] = .loading/.success/.failure (LLMUsageManager.swift:14-51).

### Data sources and APIs

Local JSONL parsing (PUBLIC file I/O): Claude ~/.claude/projects/**/*.jsonl (message.usage input/output/cache_creation/cache_read tokens, dedupe by messageId-requestId) and plan label from ~/.claude.json oauthAccount (A/managers/LLMUsage/ClaudeUsageProvider.swift:8-66); Codex ~/.codex/sessions/**/*.jsonl (turn_context model + event_msg token_count) (CodexUsageProvider.swift:8-27, JSONLUsageParser.swift:56-117); streaming 64 KB chunks, 1 MB max record, window session 5 h / week 7 d, skips files modified before the week start (119-241). Pricing from bundled pricing.json with remote refresh from raw.githubusercontent.com/Ebullioscopic/Atoll/dev/.../pricing.json (ModelPricingManager.swift:91-130). Quota (PRIVATE/undocumented third-party endpoints and credentials): Claude GET https://api.anthropic.com/api/oauth/usage with OAuth token read from Keychain generic password service prefix 'Claude Code-credentials' (freshest item; read via /usr/bin/security find-generic-password to preserve ACL) or ~/.claude/.credentials.json, refreshed at https://platform.claude.com/v1/oauth/token with client id 9d1c250a-… (ClaudeQuotaClient.swift:24-25, 135, 172-231; KeychainReader.swift:26-80; REA: _SecItemCopyMatching, _NSTask); Codex GET https://chatgpt.com/backend-api/wham/usage with token from $CODEX_HOME/auth.json, ~/.codex/auth.json, ~/.config/codex/auth.json or Keychain 'Codex Auth' (CodexQuotaClient.swift:39-101); Cursor POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage (Bearer) and https://cursor.com/api/usage-summary (WorkosCursorSessionToken cookie read from ~/Library/Application Support/Cursor/User/globalStorage/state.vscdb via sqlite3) (CursorQuotaClient.swift:31-42, CursorTokenStore.swift:28-37; REA: libsqlite3 linked); Antigravity: discovers the language-server port via /bin/ps + /usr/sbin/lsof, reads its Keychain token with /usr/bin/security, calls https://daily-cloudcode-pa.googleapis.com / https://cloudcode-pa.googleapis.com (AntigravityUsageProvider.swift:78, 229, 333, 615-616); New API: user-configured base URL + API key stored in Keychain service com.Ebullioscopic.Atoll.new-api, GET /api/user/self etc. (NewAPIUsage.swift:38, 183-260).

### Settings

enableLLMUsageFeature=false; enableClaudeProvider=true; enableCodexProvider=true; enableCursorProvider=true; enableAntigravityProvider=true; enableNewAPIProvider=false; newAPIAccounts=[] (Constants.swift:1283-1289).

### Dependencies

Defaults.

### Implementation notes

The view is ~360 lines and straightforward; the providers are the bulk (~2,300 lines). For Notchy, local JSONL parsing + bundled pricing is safe; quota clients touch third-party credentials and undocumented endpoints and should be opt-in or omitted.

### Key files

- `DynamicIsland/components/Notch/NotchLLMUsageView.swift`
- `DynamicIsland/managers/LLMUsage/LLMUsageManager.swift`
- `DynamicIsland/managers/LLMUsage/UsageProvider.swift`
- `DynamicIsland/managers/LLMUsage/JSONLUsageParser.swift`
- `DynamicIsland/managers/LLMUsage/ClaudeUsageProvider.swift`
- `DynamicIsland/managers/LLMUsage/Quota/ClaudeQuotaClient.swift`
- `DynamicIsland/managers/LLMUsage/Quota/KeychainReader.swift`
- `DynamicIsland/managers/LLMUsage/ModelPricingManager.swift`

## Unknowns

- Settings UI layout for Timer/Calendar/ColorPicker sections (A/components/Settings/SettingsView.swift:3671, 7377, 8829) was only outlined (toggles/pickers listed), not fully specced: preset editor rows (name TextField, duration steppers, ColorPicker, reorder/delete), 'Restore defaults' confirmation, and the exact segmented-picker helper (SettingsSegmentedPicker) styling.
- Lock-screen timer widget (A/managers/LockScreenTimerWidgetManager.swift, keys lockScreenTimer*) and lock-screen reminder/calendar widgets were out of scope; they share TimerManager/ReminderLiveActivityManager state but their layouts were not read.
- Minimalistic-UI variants: minimalisticTimerCountdownBlockHeight / minimalisticTimerCountdownTopPadding (A/sizing/matters.swift:168-194) and MinimalisticMusicPlayerView's external-timer countdown block were not specced; minimalistic open-notch size function was not read.
- DynamicIslandViewModel.setScrollGestureSuppression / setAutoCloseSuppression semantics (token-based counters) were referenced but not read in detail.
- MusicLiveActivity composition that hosts MusicTimerSupplementView (badge size, left/right wing base widths 'baseWidth'/'centerBaseWidth') lives in the music subsystem (ContentView.swift ~1500-1720) and was only partially read.
- NotchColorPickerView is reachable via NotchViews.colorPicker but no tab entry is added in TabSelectionView in 2.3.3; whether any code path sets currentView = .colorPicker was not verified.
- ScreenAssistant ChatMessagesView / ChatInputView internal layout (bubble sizes 32pt avatar, r16 bubbles, 200pt screenshot options popover) and ModelSelectionView lists were only grepped, not fully read.
- AntigravityUsageProvider request/response schemas (773 lines) and NewAPIUsage endpoints beyond /api/user/self were not read in full.
- Exact AppleScriptHelper implementation (NSAppleScript vs OSAScript, background queue) was not read.
- Whether the shipped binary's SystemTimerBridge still uses the log-stream path exactly as in this source revision could not be verified beyond symbol presence (NSTask, AX imports); runtime behaviour may differ by macOS version of Clock.app AX identifiers.
- LocalizedStrings: many labels use String(localized:); Localizable.xcstrings was not consulted for non-English copies.

## Critic pass

Missing from the spec:

- [Scope note] The spec text relayed to me was truncated after the Color-picker feature's key_files, so the Notes / Terminal / Screen-Assistant / LLM-usage sections never arrived. Items 20-24 below list what those sections must contain; everything else is verified against the visible Timer / Calendar / Color-picker text.
- Lock-screen TIMER widget (entirely absent): components/LockScreen/LockScreenTimerWidget.swift + managers/LockScreenTimerWidgetManager.swift. preferredHeight 96, width = Defaults[.lockScreenTimerWidgetWidth] (default 350, Constants.swift:1117; the view's static defaultWidth 420 only bounds the settings slider 320...420, SettingsView.swift:6584), cornerRadius 26 (:28); countdown .system(46 bold rounded) (42 when |remaining| >= 36 000 s) monospacedDigit, minScale 0.68, frame width 160 / 185 (>=1 h) / 200 (>=10 h) (:49-66, 236-251); accent = (preset colour ?? TimerManager.timerColor).ensureMinimumBrightness(0.75), red in overtime (:77-80); CircleButton 48x48, icon 18 semibold, bg opacity 0.9 hover / 0.7, pause bg accent 0.32, cancel/stop bg black 0.35 (light glyphs) or 0.12, disabled opacity 0.4 (:291-322); accent ribbon Capsule 110x26 gradient blur 12 offset (18,-6) opacity 0.45 (:253-260); backgrounds: classic black 0.65 / white 0.7, frosted .ultraThinMaterial, liquid (.glassEffect on macOS 26 or LiquidGlassBackground variant) (:115-157); stroke primary 0.08, shadow black 0.25 r18 y16; present/hide .spring(response 0.45, dampingFraction 0.85, blendDuration 0.22) scale 0.9->1 (:207-209), hide delay 360 ms (LockScreenTimerWidgetManager.swift:133); NSWindow level CGShieldingWindowLevel, SkyLightOperator.delegateWindow, collectionBehavior canJoinAllSpaces/stationary/fullScreenAuxiliary, registered with ScreenCaptureVisibilityManager .entireInterface (:223-247); position x centred, y = screen.midY + 24 - 18 + clamp(lockScreenTimerVerticalOffset, -160, 160), kept 20 below weather frame, 12 above music panel, >= screen.minY+100 (:269-299); reposition .easeInEaseOut 0.22 (:196-199); shown only while locked AND hasManualTimerRunning (Clock-mirrored timers excluded) (:120-127); stop hides the panel then stops the timer after 360 ms (LockScreenTimerWidget.swift:271-289). Settings: enableLockScreenTimerWidget=true (1099), lockScreenTimerVerticalOffset=0 (1116), lockScreenTimerWidgetWidth=350 (1117), lockScreenTimerGlassStyle=.frosted (1124), lockScreenTimerGlassCustomizationMode (1125), lockScreenTimerLiquidGlassVariant (1133), lockScreenTimerWidgetUsesBlur=false (1149); settings UI SettingsView.swift:7490-7556.
- Lock-screen REMINDER widget (entirely absent): LockScreenReminderWidget.swift, LockScreenReminderWidgetManager.swift, LockScreenReminderWidgetPanelManager.swift, models/LockScreenReminderWidgetSnapshot.swift. Row HStack(spacing 8){ icon 20 semibold (calendar.badge.clock / calendar.badge.exclamationmark when critical); RoundedRectangle r2 9x20 chip (calendar colour ensureMinimumBrightness 0.7 or primary 0.85 monochrome; red when critical); title 19 semibold rounded primary 0.92 lineLimit 1 minScale 0.85; '•' separators primary 0.65; relative 'in N min'/'now'; short time }.padding(h16 v12).frame(min 240, ideal 360, max 520) shadow r8 y3 (LockScreenReminderWidget.swift:26-87). Snapshot built in ReminderLiveActivityManager.publishLockScreenSnapshot/buildLockScreenSnapshot (:564-630). Window: borderless nonactivating, CGShieldingWindowLevel, ignoresMouseEvents, SkyLight delegate, initial 220x48 (PanelManager:92-124); x alignment leading/center/trailing with 24 pt padding; y between (music top+16 or timer top+24) and (weather bottom-16), top-aligned when the timer widget is visible else centred, offset clamp ±160 (PanelManager:126-173); reposition 0.22 easeInEaseOut. Settings: enableLockScreenReminderWidget=true (1098, requires enableReminderLiveActivity), lockScreenReminderChipStyle=.eventColor (1150), lockScreenReminderWidgetHorizontalAlignment="center" (1151), lockScreenReminderWidgetVerticalOffset=0 (1152).
- Minimalistic-UI external-timer countdown block (sizing/matters.swift:166-168, 193-195; MinimalisticMusicPlayerView.swift:233-234, 397-449): only for Clock-mirrored (isExternalTimerActive) timers when timerLiveActivityEnabled; block = 12 top padding + 82 content; HStack(.lastTextBaseline, spacing 12){ MarqueeText(name, 16 semibold, .title3, accent 0.85); countdown .custom("SF Pro Display", 56) monospacedDigit (red in overtime) frame width min(max(0.42*w,150), w-60) }.padding(.horizontal 4); accent = (preset ?? ramp).ensureMinimumBrightness(0.75); appear transition opacity+move(.top), .smooth 0.25; the open-notch window grows by the block height (minimalisticOpenNotchSize).
- Minimalistic-UI reminder rows: MinimalisticReminderEventListView / MinimalisticReminderEventRow (MinimalisticMusicPlayerView.swift:452-500+): VStack spacing 8, top padding 14, text 13 regular, separator spacing 10, indicator height 20, per-row copy-link state and details popover; AppDelegate suppresses window-resize animation while rows are present in minimalistic UI (DynamicIslandApp.swift:689-694) and observes $activeWindowReminders / TimerManager.$activeSource+$isTimerActive to resize (:879-891).
- Timer sneak-peek rendering paths: toggleSneakPeek(type: .timer) forces duration 10 s and bypasses enableSystemHUD (DynamicIslandViewCoordinator.swift:336-352); standard style draws HStack{ Image 'timer'; MarqueeText(name + " - " + remaining, tint timerColor, minDuration 1) }.padding(.bottom 10) (ContentView.swift:1201-1211); inline style draws name marquee (minDuration 0.4, width (centre-notchWidth)/2-12) left and remaining right in timerColor (ContentView.swift:1469-1484, 128-136). No call site in the 2.3.3 source passes type: .timer, so these paths appear vestigial – Notchy can skip them but the spec should say so.
- Reminder live-activity data source nuance: entries are built from CalendarManager.events, i.e. only events/reminders of the day currently selected in the notch calendar (reset to today on every open) across the selected calendars (ReminderLiveActivityManager.swift:151-157, 321-345; CalendarManager.swift:368-370). Lead time = max(1, reminderLeadTime) min (:375); settings sliders 1...60 min and 3...20 s (SettingsView.swift:3815-3838); scheduling pauses while locked and resumes with a 5 s cooldown (:256-319); event snapshots deduped by a hash signature (:643-666).
- Calendar permission flow: checkCalendarAuthorization / checkReminderAuthorization request on .notDetermined and accept .authorized or .fullAccess (CalendarManager.swift:146-201), while CalendarService.hasAccess requires exactly .fullAccess (CalendarServiceProviding.swift:65-68); Info.plist usage strings NSCalendarsFullAccessUsageDescription / NSRemindersFullAccessUsageDescription / NSRemindersUsageDescription (REA plist.json). Lock-screen event fetch uses ALL calendars, ignoring calendarSelectionState (CalendarManager.swift:317) – the lockScreenCalendarSelectionMode / lockScreenSelectedCalendarIDs keys (Constants.swift:1155-1156) filter elsewhere; LockScreenCalendarEventRow (HStack spacing 6, 26x26 icon frame, 20 semibold glyph, 1-line text minScale 0.85) renders those events.
- EventModel mapping details: reminders map dueDate -> start, end = end of that day, isAllDay when dueDateComponents.hour == nil (CalendarServiceProviding.swift:182-205); priority 1-4 high / 5 medium / 6-9 low (:254-266); timeZone nil for subscribed/delegate calendars; participants include organizer (:231-251); Apple Calendar URL for recurring events inserts /yyyy-MM-dd'T'HH:mm:ssZ (UTC for timed) and ends with ?method=show&options=more (EventModel.swift:124-139); CalendarModel.accountName is 'Other' for local/subscribed/birthday sources (:271-279); conference host list (:322-334).
- Home-tab calendar gating: Home tab exists only when showStandardMediaControls || showCalendar || showMirror (or minimalistic) (TabSelectionView.swift:162-167); calendar mounts one run-loop turn after the home view appears via showCalendarDeferred (NotchHomeView.swift:903, 930-942); shouldShowMusicPlayer = showStandardMediaControls && (!autoHideInactiveNotchMediaPlayer || musicManager.hasActiveSession) (:908-910), so StandaloneCalendarView also appears when the player is auto-hidden; vm.isHoveringCalendar disables the close-scroll gesture and horizontal music gestures (ContentView.swift:2625, 2687).
- Calendar view small details: WheelPicker drag = .simultaneousGesture(DragGesture(minimumDistance 4)) with measured cell width (default 40) (DynamicIslandCalendar.swift:195, 258-276); ConferenceJoinButton non-joinable text Color(white 0.5), .help tooltips, provider .generic uses .accentColor and bare 'Join'/'Rejoin' (:1337, 1353, 1426-1438); all-day chips open the event URL on tap (:144-148); reminder toggle accessibility labels (:1316).
- Timer tab nuances: preset tap / Start switch to the Timer tab only when !enableMinimalisticUI (NotchTimerView.swift:123-125, 522-524); Reset also writes customTimerDuration = 0 (:534) and syncing is guarded by isSyncingCustomDuration (:537-549); 'Completed' badge text is not localized (:418).
- Timer popover extras: PresetList empty state 'Configure presets in Settings' 12 pt .secondary padding 12 white 0.05 r10 (TimerPopover.swift:306-313); Divider().padding(.horizontal -8) (:54-55); Pause/Resume and Stop buttons .disabled(!allowsManualInteraction) (:173, 182); 'Ready' status not localized (:83).
- Header glyph metrics for the timer / eyedropper buttons: headerGlyph font size per symbol ('timer' 14.4, 'eyedropper' 14.3, weight .medium) inside a fixed 20x20 frame, buttons spaced 8 pt (DynamicIslandHeader.swift:58-84, 117); shouldSuppressStatusIndicators hides recording/focus indicators when settingsIconInNotch && clipboard && showColorPickerIcon && enableTimerFeature are all on (:435-441); popover close triggers vm.shouldRecheckHover after 0.1 s (:231-238).
- Coordinator behaviours: switching timerDisplayMode to .popover while on the Timer tab, or disabling the feature, redirects currentView to .home with .smooth (DynamicIslandViewCoordinator.swift:260-271); tabOrder [.home,.shelf,.timer,.stats,.llmUsage,.colorPicker,.notes,.clipboard,.terminal,.extensionExperience] drives tabSwitchForward (:102-117); minimalistic UI forces .home (:108-111); timerLiveActivityEnabled is an @AppStorage bool (:129) exposed as 'Enable timer live activity' (SettingsView.swift:7450).
- Timer shortcuts & settings UI: Cmd+Shift+T starts a 300 s 'Demo Timer' (DynamicIslandApp.swift:1400-1403; TimerManager.swift:218-220), enabled only when enableShortcuts && enableTimerFeature (:1526); TimerSettings form (SettingsView.swift:7376-7790): 'Timer controls appear as' (Tab/Popover), 'Timer tint' (Adaptive gradient / Solid colour + ColorPicker without opacity), 'Custom timer style' (Ruler/Manual), toggles Show timer name / Show countdown / Show progress / Show preset list in timer tab / Show pause/stop controls in the notch, 'Progress style' disabled when !showsProgress, preset editor (add 'Preset N' 5 min in accent colour, move up/down, remove, reset to defaults; :7739-7773), sound chooser NSOpenPanel allowedContentTypes [.audio], 'Reset to Default', label 'Default: dynamic.m4a' (:7676-7715, 7764-7778). Note TimerPreset default names use String(localized:) (TimerPreset.swift:100-102).
- TabSelectionView extras: extension tabs tint the capsule with the extension accent plus .shadow(accent 0.4, radius 8) (TabSelectionView.swift:134-135); the row is .clipShape(Capsule()) (:148); ensureValidSelection on appear falls back to the first tab (:177-189); Notes|Clipboard tab uses icon note.text / doc.on.clipboard (:90-94).
- Color picker extras: ColorPickerPanel is registered with ScreenCaptureVisibilityManager scope .panelsOnly (hidden from screen capture), isFloatingPanel, titlebarAppearsTransparent, acceptsMouseMovedEvents, canBecomeKey/Main (ColorPickerPanel.swift:84-119); show = hide existing, positionPanel, makeKeyAndOrderFront, orderFrontRegardless, NSApp.activate(ignoringOtherApps), makeKey after 0.1 s (:40-62); panel 'Color Details' header, noSelection 'hand.point.up.left' 32 + text 14, empty 'No Colors Found' 32 glyph (:399-448); list header bg gray 0.05 (:345); details time strings 'just now'/'N minutes ago' vs list 'Just now'/'Nm ago' (:529-603); search matches hex/rgb/hsl strings (:197-207). Notch grid swatch tap copies hex + .generic haptic (NotchColorPickerView.swift:163-173); popover swatch tap copies + haptic + dismiss, 'Show Color History' icon rectangle.grid.2x2 (ColorPickerPopover.swift:79, 102-110). Unused NSColor.hexString/ColorFormatter helpers (rounded, uppercase) (ColorPickerManager.swift:25-58). ColorPickedFeedbackView is never instantiated anywhere (only its own file) – dead code. Settings UI (SettingsView.swift:8829-8920): Show Color Picker Icon, Display Mode menu, History Size 5/10/15/20, Show All Color Formats, live 'Color History' count, 'Picking Status', 'Show Color Picker Panel' button. Cmd+Shift+P always toggles the panel regardless of display mode (DynamicIslandApp.swift:1466-1469).
- TERMINAL tab (section missing): NotchTerminalView.swift:85-204 – header HStack{ 'apple.terminal' 11 pt; title 11 medium; restart 'arrow.counterclockwise' 10 pt }.padding(h12, top 6, bottom 4) tinted terminalForegroundColor; Divider padded 8; SwiftTerm LocalProcessTerminalView hosted in a stable StableTerminalContainerView, clipped to UnevenRoundedRectangle top 6 / bottom = shell bottom radius - 8 (:96-121; sizing/matters.swift:205-247: edge padding top 4, horizontal 8, bottom 8, inner text inset 6); frosted NSVisualEffectView .underWindowBackground .behindWindow underlay, gutter tint view, custom 6 pt scroll knob white 0.45 insets 3 / right margin 2 replacing SwiftTerm's scroller (TerminalManager.swift:155-199, 430-497); login shell execName '-zsh', env TERM=xterm-256color, LANG default en_US.UTF-8, TERM_PROGRAM removed (:288-301, 628-636); restartShell terminates and remounts (:315-323); cursor style enum blinkBlock/steadyBlock/blinkUnderline/steadyUnderline/blinkBar/steadyBar (:641-670); caretViewTracksFocus=false, scrollback via buffer.changeHistorySize (:394-428). Settings (Constants.swift:1301-1315): enableTerminalFeature=false, terminalShellPath=/bin/zsh, terminalFontFamily='', terminalFontSize=12, terminalOpacity=1, terminalMaxHeightFraction=0.4, terminalCursorStyle='blinkBlock', terminalScrollbackLines=1000, terminalOptionAsMeta=true, terminalMouseReporting=true, terminalBoldAsBright=true, terminalBackgroundColor=.black, terminalForegroundColor=.white, terminalCursorColor=Color(.selectedControlColor), terminalStickyMode=false. Sticky mode blocks auto-close and installs a global leftMouseDown monitor that closes the notch on outside clicks (ContentView.swift:2271-2297, 2382-2390, 2478); Ctrl+` toggles/open-focuses the tab (ShortcutConstants.swift:34; DynamicIslandApp.swift:1476-1501); hovering the terminal suppresses notch scroll gestures (NotchTerminalView.swift:199-203). Dependency SwiftTerm 1.13.0 (MIT) statically linked; REA confirms _forkpty import and SwiftTerm_SwiftTerm.bundle.
- NOTES tab (section missing): NotchNotesView.swift – split layout with NotchClipboardView(fixedColumns 2) + 1 pt Divider white 0.15 when clipboardDisplayMode == .separateTab (:46-56); list<->editor transitions move(.leading)/move(.trailing) with .spring(response 0.35, dampingFraction 0.8) (:69-92); hidden Cmd+V button creates a note from clipboard file-URL image / tiff / png / text (:95-102, 147-188); auto-save task on title/content/colour change (:135-143); layout state list 240 / split 260 / editor 320 drives notch height (enums/generic.swift:86-101; ContentView.swift:192-196). NoteItem (Constants.swift:872-960): id, title, content, creationDate, modificationDate, colorIndex, isPinned, imageFileName, appleNotesId; colours [.yellow,.blue,.red,.green,.purple,.orange]; images in ~/Documents/NoteImages/note_image_<uuid>.png (legacy imageData migrated). NoteListView header 16 semibold rounded, Apple-logo / arrow.triangle.2.circlepath 11 semibold (yellow while syncing) (:491-500), search/colour-filter/clipboard buttons 13-14 pt in 16x16 frames; NoteRow colour bar 3/4 pt, title 12/14 semibold rounded, preview 10/12, hover .easeInOut 0.2, radius 12, thumbnail 32/50 r6 (:728-863); NoteEditorView title 15-17 bold rounded, body 13 rounded, image 55 r10, char-count 10 monospaced r4 (:886-1044). Settings (1518-1526): enableNotes=false, enableNotePinning=true, enableNoteSearch=false, enableNoteColorFiltering=false, enableCreateFromClipboard=true, enableNoteCharCount=true, savedNotes=[], enableAppleNotesSync=false, appleNotesLastSyncDate=nil. AppleNotesSyncManager (:50-60, 207-260, 400-413): NSAppleScript via AppleScriptHelper against Notes.app 'default account', folder 'Atoll', U+241E/U+241F record/field separators, '<!--atoll:id=UUID-->' body tag, merge newest-wins, push unlinked notes, error -1743 = Automation permission denied. REA: _OBJC_CLASS_$_NSAppleScript imported; NSAppleEventsUsageDescription mentions Notes.
- SCREEN ASSISTANT (section missing): two floating NSPanels – ChatMessagesPanel 600x500 positioned left and ChatInputPanel 500x60 centred, .hudWindow backgrounds r16, level .floating, ESC closes (components/ScreenAssistant/ChatPanels.swift:34-175, 308, 426); ModelSelectionPanel 450x600 (ModelSelectionPanel.swift:34-95); legacy ScreenAssistantPanel is a 1x1 off-screen wrapper that forwards to showPanels/closePanels (ScreenAssistantPanel.swift:25-93). Providers & endpoints: Gemini generativelanguage.googleapis.com/v1beta/models/{id}:generateContent, OpenAI api.openai.com/v1/chat/completions, Groq api.groq.com/openai/v1/chat/completions, Claude api.anthropic.com/v1/messages, Local Ollama {endpoint}/api/chat (ScreenAssistantManager.swift:383-517, 595-596). Screenshots via /usr/sbin/screencapture -c / -cw / -cs then read from pasteboard (ScreenshotSnippingTool.swift:30-50, 102); AVAudioRecorder voice notes in ~/Documents/ScreenAssistantAudio, screenshots in ~/Documents/ScreenAssistantScreenshots (:130-148). Settings: enableScreenAssistant=true, screenAssistantDisplayMode=.panel, geminiApiKey/openaiApiKey/claudeApiKey/groqApiKey, selectedAIProvider=.gemini, selectedAIModel, localModelEndpoint, enableThinkingMode (Constants.swift:1369-1376+, AIModelProvider 790-, AIModel 862-870); Cmd+Shift+A (ShortcutConstants.swift:29; DynamicIslandApp.swift:1504-1521). REA: ScreenAssistantManager / ChatInputPanel / ChatMessagesPanel / ModelSelectionPanel / ScreenshotSnippingTool present in dispatch.json; AVFoundation linked.
- LLM USAGE tab (section missing): LLMUsageManager refreshAll min interval 60 s, providers run in a task group (LLMUsageManager.swift:14, 25-50); ProviderID claude/codex/cursor/antigravity/newAPI with enable keys (UsageProvider.swift:4-25); data sources: Claude ~/.claude/projects JSONL + ~/.claude.json plan, quota GET https://api.anthropic.com/api/oauth/usage with token from ~/.claude/.credentials.json falling back to Keychain 'Claude Code-credentials' and refresh via https://platform.claude.com/v1/oauth/token (ClaudeUsageProvider.swift:8-37; Quota/ClaudeQuotaClient.swift:135, 175-231); Codex ~/.codex/sessions, quota https://chatgpt.com/backend-api/wham/usage with $CODEX_HOME|~/.codex|~/.config/codex/auth.json or Keychain 'Codex Auth' (CodexUsageProvider.swift:8; CodexQuotaClient.swift:39, 83-101); Cursor Keychain 'cursor-access-token' or ~/Library/Application Support/Cursor/User/globalStorage/state.vscdb via sqlite3, https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage and https://cursor.com/api/usage-summary (CursorTokenStore.swift:6-37; CursorQuotaClient.swift:31-41); Antigravity token via `security` CLI, cloudcode-pa.googleapis.com (AntigravityUsageProvider.swift:74-142, 608-653); New API accounts with keys in Keychain (NewAPIUsage.swift:37-131); pricing merged from bundled pricing.json + https://raw.githubusercontent.com/Ebullioscopic/Atoll/dev/DynamicIsland/managers/LLMUsage/pricing.json (ModelPricingManager.swift:98). View: HStack(spacing 10) of cards padding 10, .white 0.06 r12, header .headline + plan Capsule badge, Antigravity Gemini/Claude segmented picker width 120 (NotchLLMUsageView.swift:36-99); quota gauge 6 pt Capsule track white 0.15, tint accent / orange >0.9 / red >0.95, 'N% used'/'N% left' caption2, 'resets in Xd Yh Zm' (:241-286). Settings: enableLLMUsageFeature=false, enableClaude/Codex/Cursor/AntigravityProvider=true, enableNewAPIProvider=false, newAPIAccounts=[] (Constants.swift:1283-1290). REA: libsqlite3 + Security linked, _SecItemCopyMatching, _sqlite3_open_v2 imported.
- Version caveat for the whole spec: the clone is dev HEAD (commit 868c25d, 2026-10-15; VERSION 2.3.3 but CHANGELOG has a long '[Unreleased]' section) whereas the installed binary is 2.3.3 build 20260720004 (REA plist.json, built 2026-07-20). Source features that likely post-date the shipped binary and should be tagged 'source-only': Zoom join opens https directly (#813), minimalistic lyrics/timer height fix (#812), Clock-timer AX control (no _AXUIElementPerformAction / _AXUIElementSetMessagingTimeout in macho.json imports even though SystemTimerBridge.swift:1203,1242 use them), TIDAL/Caffeinate/Per-app-volume/NetworkConnectivity managers (0 dispatch.json hits), Antigravity/New API providers and cache-aware pricing.

Corrections:

- Smooth close is overstated for manual timers. Spec: 'Smooth close after completion/cancel: wait 3.0 s then .easeInOut(1.0)' and 'stopTimer: … scheduleSmoothClose (3 s + 1 s fade) then resetTimer'. In code stopTimer() schedules the close (TimerManager.swift:242-244) but immediately calls resetTimer() -> endTimerSession() which cancels the work item and sets isTimerActive=false with .smooth (:246, 407-411, 480-484). The 3 s hold + 1 s fade only ever fires from completeExternalTimer() for Clock-mirrored timers (:381-391). A finished manual timer never auto-closes: it enters overtime and loops the sound until the user stops it (:201-212).
- Critical reminder sneak-peek duration: spec says it is shown 'with duration min(window, remaining-2)'. ReminderLiveActivityManager passes that value (:517-525) but DynamicIslandViewCoordinator.toggleSneakPeek ignores the argument for type .reminder and always uses Defaults[.reminderSneakPeekDuration] (DynamicIslandViewCoordinator.swift:336-345); .reminder/.timer also bypass the enableSystemHUD gate (:346-352).
- Minimalistic reminder-row height: spec lists '10 bottom padding'. additionalHeight(forRowCount:) adds listTopPadding 14 + rows*30 + (rows-1)*8 + max(10 - 3, 0) = 7, because baselineMinimalisticBottomPadding (3) is subtracted (ReminderLiveActivityManager.swift:38-42, 632-638).
- ConferenceJoinButton native schemes: spec lists 'zoommtg/msteams/facetime/discord'. The button opens Zoom https URLs directly without rewriting (DynamicIslandCalendar.swift:1409-1412) and rewrites only Teams->msteams, FaceTime->facetime, Discord->discord (:1373-1381, 1413-1420). (CHANGELOG #813 – this is a post-2.3.3 change; the shipped build may still rewrite to zoommtg.)
- Terminal tab height: spec says 'terminal = max(300, screenVisibleHeight * terminalMaxHeightFraction)'. The code is min(screenHeight*f, max(300, screenHeight*f)), which always equals screenHeight*f – the 300 pt floor is neutralised by the outer min (ContentView.swift:207-209; DynamicIslandApp.swift:577-579).
- REA evidence is overstated. Spec: 'dispatch.json carries Swift decls for TimerManager, SystemTimerBridge, TimerPopover, TimerPreset, …'. dispatch.json only reflects ObjC-visible classes/properties: TimerManager 16, SystemTimerBridge 31, CalendarManager 129, ColorPickerManager 51, TerminalManager 18, LockScreenTimerWidget 21 hits, but TimerPopover 1, TimerPreset 1, RulerTimerPicker 0, TimerLiveActivity 0, TimerLifecycle 0, StandaloneCalendarView 0, ConferenceJoinButton 0, AntigravityUsageProvider 0, NewAPI 0 – SwiftUI structs are not confirmed by it. macho.json imports contain _AXUIElementCreateSystemWide/_CreateApplication/_CopyAttributeValue and _AXIsProcessTrusted(WithOptions) but NOT _AXUIElementPerformAction or _AXUIElementSetMessagingTimeout (and no _dlopen-based SkyLight symbols), so 'REA confirms' cannot be claimed for the Clock pause/resume/cancel control path (SystemTimerBridge.swift:1164-1288).
- Lock-screen look-ahead fetch ignores the user's calendar selection: spec implies events come 'from all or a user-selected subset of calendars'; updateLockScreenEvents() passes allCalendars (CalendarManager.swift:317), only the day view uses selectedCalendars (:368).
- Hover-to-open on a running tab-mode timer also requires !enableMinimalisticUI, honours minimumHoverDuration, and is blocked by recording/sneak-peek/connectivity HUD/hover-open suppression (ContentView.swift:2334-2357), not only 'even if open-on-hover is off'.
- Minor line-reference fixes: NotchTimerView startButton is 471-492 (spec 457-492); statusBadgeWidth is 437-447 (spec 427-447); TimerLiveActivity iconSection 323-350 declares iconSize = max(18, iconWidth-6) when no ring but the glyph font is a fixed 16 pt semibold (:342-345), so '16pt glyph' is the rendered size and iconSize only sets the frame.
- Spec implies ColorPickedFeedbackView ('Color Picked!' flag raised for 2 s') is shown to the user; the flag showColorPickedFeedback is set (ColorPickerManager.swift:134-148) but no view in the project instantiates ColorPickedFeedbackView (grep: only ColorPickedFeedbackView.swift), so nothing is actually displayed – only the panel reopens after 0.1 s.
- Spec states the standalone ReminderLiveActivity digital text is '16 semibold monospaced' with width max(text+18, 76): the width is measured with monospacedDigitSystemFont(16, .semibold) (ReminderLiveActivity.swift:182-186) but rendered with .system(16, .semibold, design: .monospaced) (:120) – the same mismatch Atoll fixed for the timer countdown (TimerLiveActivity.swift:209-218); reproduce the fix, not the mismatch.

Private API summary:

Everything user-facing in this subsystem is built on PUBLIC macOS APIs, confirmed by REA macho.json imports: EventKit (EKEventStore requestFullAccessToEvents/Reminders, EKEvent/EKReminder, EKEventStoreChanged — EventKit.framework LC_LOAD_DYLIB), NSColorSampler (_OBJC_CLASS_$_NSColorSampler), AVAudioPlayer/NSSound.beep (AVFoundation/AVFAudio linked), NSHapticFeedbackManager, NSPasteboard, NSPanel/NSVisualEffectView, NSEvent local/global monitors, NSDataDetector, NSWorkspace, SwiftTerm's forkpty (_forkpty; libSystem) and NSTask/Process for /usr/sbin/screencapture and /usr/bin/log, NSAppleScript (Notes sync, Automation permission), Security SecItemCopyMatching/Add/Update and libsqlite3 (LLM quota credential readers), CFPreferences. Private or undocumented surfaces, by feature: (1) SystemTimerBridge (Clock-timer mirroring, mirrorSystemTimer=true): spawns `/usr/bin/log stream --style ndjson --predicate 'subsystem == "com.apple.mobiletimer.logging" …' --level debug` and regex-parses undocumented MobileTimer log text (SystemTimerBridge.swift:273-328, 608-931); reads another process's preference domain com.apple.mobiletimerd / key MTTimers ($MTTimer dicts MTTimerID/Title/Duration/State 1-4) via CFPreferencesAppSynchronize/CopyAppValue plus a DispatchSource file monitor on ~/Library/Preferences/com.apple.mobiletimerd.plist (:74-76, 428-455, 964-1000; REA imports _CFPreferencesAppSynchronize/_CFPreferencesCopyAppValue); scrapes the menu-bar timer extra and drives Clock.app's 'PauseResumeButton'/'CancelButton' through the public Accessibility API (AXUIElementCreateSystemWide/CreateApplication/CopyAttributeValue/PerformAction, AXIsProcessTrusted) — public API but dependent on undocumented AX identifiers and requiring Accessibility permission (:1002-1288; AccessibilityPermissionStore uses AXIsProcessTrustedWithOptions + kAXTrustedCheckOptionPrompt). Note REA imports lack _AXUIElementPerformAction/_AXUIElementSetMessagingTimeout, so the Clock control path is probably newer than the installed 2.3.3. (2) Lock-screen timer and reminder widgets: windows at CGShieldingWindowLevel (public CoreGraphics, _CGShieldingWindowLevel imported) handed to SkyLightOperator.delegateWindow from the Lakr233/SkyLightWindow package, which talks to the private SkyLight framework (dispatch.json shows SkyLightWindow/SkyLightOperator/SLSMainConnectionID strings; no static SLS imports — resolved dynamically) so they render over the lock screen; the notch window itself uses private CGSSpaceCreate/Destroy/SetAbsoluteLevel (imported) but that belongs to the shell subsystem. (3) LLM-usage quota clients read third-party apps' credentials (Claude Code Keychain item 'Claude Code-credentials' / ~/.claude/.credentials.json, Codex auth.json / Keychain 'Codex Auth', Cursor Keychain 'cursor-access-token' / state.vscdb SQLite, Antigravity token via the `security` CLI) and call undocumented endpoints (api.anthropic.com/api/oauth/usage, chatgpt.com/backend-api/wham/usage, api2.cursor.sh DashboardService, cloudcode-pa.googleapis.com) — all public OS APIs, but fragile private web APIs. (4) Apple Notes sync and Screen Assistant use public NSAppleScript / screencapture CLI / AVAudioRecorder only. Dependencies confirmed in Package.resolved: Defaults 9.0.3, KeyboardShortcuts 2.3.0, SwiftTerm 1.13.0, SkyLightWindow (4a7e862), Lottie, Sparkle 2.7.0, LaunchAtLogin-Modern, Pow 1.0.5, swiftui-introspect 1.3.0.
