# Atoll spec: Live activities, HUDs and system events on the closed notch and as separate windows (Atoll 2.3.3 / DynamicIsland source)

Source: Atoll 2.3.3 source clone plus REA evidence from the installed binary (see ../atoll-behaviour-evidence.md). Values are quoted with file:line from the Atoll source. Reimplement behaviour, do not copy code (GPL-3).

## Summary

Atoll's closed-notch "live activity" system is driven by one ObservableObject, DynamicIslandViewCoordinator, which owns two published structs: `sneakPeek` (transient HUD: volume/brightness/backlight/mic/bluetooth/capsLock/music/timer/reminder, default auto-hide 1.5 s, written atomically inside withAnimation(.smooth(duration: 0.3))) and `expandingView` (longer-lived expansion: battery/download/recording/music/lockScreen, default auto-hide 3 s except .download which its manager closes). ContentView.NotchLayout() (ContentView.swift:1055-1325) renders a strict priority chain on the closed notch: connectivity HUD > battery temporary HUD > InlineHUD (sneak) > persistent Caps Lock InlineHUD > MusicLiveActivity (with a "secondary" live activity badge + right wing) > Timer > Reminder > Recording > Download > LocalSend > Do Not Disturb > Privacy (camera/mic) > extension > shelf > idle Lottie face > header (open) > empty spacer; a second row below shows the non-inline SystemEventIndicatorModifier (progress bar HUD) or the standard music/timer/reminder marquee sneak peek. Every closed-notch activity is laid out as HStack(spacing: 0) { leftWing | black Rectangle(width: closedNotchSize.width [+8 on hover]) | rightWing } where wing content height = effectiveClosedNotchHeight - (isHovering ? 0 : 12), the row height = effectiveClosedNotchHeight + (isHovering ? 8 : 0), and the wing base width = that content height + gestureProgress/2. Hover uses Animation.bouncy.speed(1.2); live-activity swaps use an asymmetric opacity+scale transition (0.965 in / 0.92 out). Volume/brightness/keyboard-backlight HUDs come from a CGEvent HID tap on NX_SYSDEFINED media keys (needs Accessibility), CoreAudio property listeners, and CoreBrightness/DisplayServices private frameworks loaded at runtime; the native macOS OSD is suppressed by SIGSTOP-ing OSDUIHelper via /usr/bin/killall with a background respawn watcher (unsandboxed app). Three alternative HUD surfaces exist as separate NSWindows (statusBar+1 / screenSaver level, SkyLightWindow-delegated): a 200x200 macOS-style OSD, a vertical capsule, and a circular dial; all auto-hide after 2.0 s. Other activities: battery charging/low/full HUD (IOKit IOPS notifications; compact pill +180 pt wide, or standard +75/+70 pt tall), screen recording (private CGSIsScreenWatcherPresent + CGSRegisterNotifyProc 1502/1503, confirmed in binary), camera/mic privacy dots (CoreMediaIO + CoreAudio DeviceIsRunningSomewhere listeners), Focus/DND (private distributed notifications + Assertions.json polling or `log stream` of duetexpertd), downloads (DispatchSource on ~/Downloads watching .crdownload/.download/.part/.opdownload), Wi-Fi/hotspot/no-connection HUD (NWPathMonitor + CoreWLAN), Bluetooth audio connect + AirPods listening mode (IOBluetooth, private notifications, `log stream`, ioreg), Caps Lock (NSEvent flagsChanged monitors), calendar reminders (EventKit via CalendarManager, ring/digital/minutes countdown), and a Lottie idle animation (airbnb Lottie + LottieUI). REA on the shipped 2.3.3 binary confirms the private CGS symbols, dlopen/dlsym, CGEventTapCreate, AX trust prompt, CMIO/CoreAudio listeners, IOPS, IOBluetooth/CoreBluetooth, NSDistributedNotificationCenter, NSTask, bundled BluetoothHUDAnimations/*.mov and Lottie JSONs; CoreBrightness/DisplayServices are NOT link-time dependencies (loaded via Bundle.load/dlopen). Only Lottie and Sparkle are embedded frameworks.

## Sneak peek / expanding-view coordinator and closed-notch composition

### Behaviour

A transient HUD ("sneak peek") appears in/under the closed notch for 1.5 s by default and auto-hides; longer "expanding views" (battery HUD, download, recording, music, lock screen) widen the notch and auto-hide after 3 s unless the owning manager closes them. Only one closed-notch activity renders at a time, chosen by a fixed priority chain; hovering grows the notch by 8 pt in height and width (content wings grow from h-12 to h). When a sneak peek is visible on a non-notch display configured to hide until hover, the notch is temporarily revealed. Per-screen targeting: a sneak peek carries targetScreenName; battery HUD carries its own target screen; `showOnAllDisplays` shows on every screen.

### Layout

SneakContentType cases (DynamicIslandViewCoordinator.swift:23-40): brightness, volume, backlight, music, mic, battery, download, timer, reminder, recording, doNotDisturb, bluetoothAudio, privacy, lockScreen, capsLock, extensionLiveActivity(bundleID, activityID). `struct sneakPeek` (:78-88): show=false, type=.music, value: CGFloat=0 (0...1, or -1 for AirPods listening-mode), icon: String, title, subtitle, accentColor: Color?, styleOverride: SneakPeekStyle?, targetScreenName: String?. `struct ExpandedItem` (:90-95): show, type=.battery, value, autoHideDuration: TimeInterval?. Closed notch size (sizing/matters.swift:398-441): width = screen.frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width + 4 on notch Macs (or Defaults[.closedNotchWidth]=150 when customizePhysicalNotchWidth / no notch); height = Defaults[.notchHeight]=32 (notchHeightMode .matchRealNotchSize → safeAreaInsets.top, .matchMenuBar → frame.maxY - visibleFrame.maxY) or Defaults[.nonNotchHeight]=32 on external displays. effectiveClosedNotchHeight = 0 when hideOnClosed on a non-notch screen (DynamicIslandViewModel.swift:376-380). Corner radii (matters.swift:199-200): closed top 6 / bottom 14, opened top 19 / bottom 24 (minimalistic opened 35/35); Dynamic-Island pill mode: closed radius max(h/2, 16), opened 24 (:357-360); window bleeds 4 pt above screen top on notch displays (:363). Priority chain in ContentView.NotchLayout() (ContentView.swift:1058-1176) in order: (1) NetworkConnectivityHUD if isConnectivityHUDVisible; (2) first-launch HelloAnimation 200x80; (3) BatteryTemporaryActivityView when expandingView.type == .battery && visible on this screen && notch closed && showPowerStatusNotifications && activeTemporaryHUDKind != nil (:1109-1124, `.id(activeTemporaryHUDToken)`); (4) InlineHUD when sneak visible && (Defaults[.inlineHUD] || AirPods listening-mode sneak) && type ∉ {music,battery,timer,reminder,extension} && (type ∉ {volume,brightness,backlight} || notch closed) (:1125-1131; transition move(edge:.trailing)+opacity for capsLock else .opacity); (5) persistent Caps Lock InlineHUD(type:.capsLock,value:1) when closed && CapsLockManager.isCapsLockActive && enableCapsLockIndicator && !hideOnClosed && !locked (:1132-1134, move trailing+opacity); (6) MusicLiveActivity(secondary:) when music pairing eligible (:1135-1138, `.id("closed-music-live-activity")`, transition closedLiveActivitySwapTransition); (7) TimerLiveActivity (:1139); (8) ReminderLiveActivity (:1141); (9) RecordingLiveActivity when closed && isRecording && enableScreenRecordingDetection && showRecordingIndicator && !hideOnClosed && !musicPairingEligible (:1143); (10) DownloadLiveActivity when isDownloading && enableDownloadListener (:1145, transition .blurReplace.animation(.interactiveSpring(dampingFraction: 1.2))); (11) LocalSendLiveActivity (:1148); (12) DoNotDisturbLiveActivity when enableDoNotDisturbDetection && showDoNotDisturbIndicator && (isDoNotDisturbActive || isFocusToastDismissing) && !locked (:1151); (13) PrivacyLiveActivity when privacyManager.hasAnyIndicator && (enableCameraDetection || enableMicrophoneDetection) (:1153); (14) ExtensionLiveActivityStandaloneView (:1155); (15) ShelfInlineLiveActivity when shelf non-empty (:1166, transition opacity .smooth(0.25)); (16) DynamicIslandFaceAnimation when no expansion && closed && (!isPlaying && isPlayerIdle) && showNotHumanFace (:1169); (17) DynamicIslandHeader when open, height max(24, effectiveClosedNotchHeight) (:1172); (18) else Rectangle(.clear) width closedNotchSize.width - 20, height effectiveClosedNotchHeight (:1175). Second row (:1178-1261), only when sneak visible on this screen: SystemEventIndicatorModifier for type ∉ {music,battery,timer,reminder,capsLock,extension} && !inlineHUD && !AirPods sneak && (type ∉ {volume,brightness,backlight} || closed), with .padding(.bottom,10).padding(.leading,4).padding(.trailing,8); music standard sneak = HStack{ Image(systemName:"music.note"); GeometryReader{ MarqueeText("<title> - <artist>", textColor:.gray, minDuration:1, frameWidth: geo.width) } }.foregroundStyle(.gray).padding(.bottom,10); timer sneak identical with "timer" glyph and timerManager.timerColor; reminder sneak = HStack(spacing:6){ RoundedRectangle(cornerRadius:2).fill(calendar colour ensureMinimumBrightness(0.7)).frame(8x12); MarqueeText(reminderSneakPeekText, minDuration:1, frameWidth: geo.width-14) }.padding(.bottom,10). The whole column gets `.fixedSize()` when shouldFixSizeForSneakPeek() (:2978-2994), zIndex 2, and an x-offset for menu-bar clearance animated .smooth(0.25) (:1281-1283). Standard closed activity row geometry (MusicLiveActivity :1393-1518 is the canonical example): closedHeight = effectiveClosedNotchHeight; outerHeight = closedHeight + (isHovering ? 8 : 0); notchContentHeight = isHovering ? closedHeight : closedHeight - 12; wingBaseWidth = notchContentHeight + gestureProgress/2; centerBaseWidth = max(closedNotchSize.width + (isHovering ? 8 : 0), 96); artworkSize = min(closedHeight-12, wingBaseWidth); inline sneak peek centre = 380 pt. Open-notch size when something expands (dynamicNotchSize, :110-186 and DynamicIslandApp.swift:479-560): inline music/timer sneak → width max(base, 460) (AirPods listening mode → InlineHUD.airPodsListeningModeWidth + notchHorizontalPadding*2); recording HUD → RecordingHUDLayout.size; battery → charging/compact +180 w, low-standard +100 w & +75 h, full-standard +80 w & +70 h; window gets addShadowPadding (+18 standard / +12 minimalistic, matters.swift:171-172,323).

### Animations

toggleSneakPeek writes all fields in one assignment inside DispatchQueue.main.async + withAnimation(.smooth(duration: 0.3)) (DynamicIslandViewCoordinator.swift:359-376). Auto-hide: Task.sleep(resolvedDuration) then withAnimation (default) toggleSneakPeek(status:false) and reset duration to 1.5 (:383-400); duration .infinity disables auto-hide (:387). Durations: default 1.5 s (:325); .timer → 10 s (:337); .reminder → Defaults[.reminderSneakPeekDuration] (5 s) (:339); music keyboard shortcut → 3.0 s (DynamicIslandApp.swift:1035-1039); bluetooth → 2.5 s; capsLock → ∞. toggleExpandingView uses withAnimation(.smooth) (:419); auto-hide after autoHideDuration ?? 3 s for every type except .download (:430-447), hide call always passes type .battery (:440). Hover: Animation.bouncy.speed(1.2) on isHovering; notch open spring(response 0.42, dampingFraction 1.0), close spring(response 0.45, dampingFraction 1.0) when useModernCloseAnimation (default true) else same 0.42 spring for both + .transition(.blurReplace.animation(.interactiveSpring(dampingFraction: 1.2))); gestureProgress animated .smooth (ContentView.swift:691-711). closedLiveActivitySwapTransition (:382-391): insertion opacity+scale(0.965, anchor .center) with .spring(response 0.34, dampingFraction 0.88); removal opacity+scale(0.92) with .smooth(duration 0.22). Download/LocalSend insertion .blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)) (:1147). Face animation `.animation(.interactiveSpring, value: isPlayerIdle)` (:1170). Hover-open suppression 0.35 s (:249). Haptics: only on notch tap/gestures when Defaults[.enableHaptics] (default true), throttled 300 ms (:2482-2488); no haptics on HUDs.

### State and timing

sneakPeek.didSet schedules hide when show==true and cancels the Task when show==false. expandingView.didSet cancels/reschedules its hide Task. LiveActivityModifier (LiveActivityModifier.swift:31-48) is a legacy overlay helper (HStack{left; Spacer; right}.padding()) kept from boring.notch and not used by the current chain. The .timer SneakContentType paths (10 s duration, inline timer centre text) have no caller in TimerManager in this tree (see unknowns).

### Data sources and APIs

Pure SwiftUI/Combine state. Trigger sites (grep): SystemChangesObserver (volume/brightness/backlight sneak), CapsLockManager, BluetoothAudioManager, ReminderLiveActivityManager, MusicManager.updateSneakPeek (standard style → sneak .music; inline style → expandingView .music; only when isPlaying && enableSneakPeek) (MusicManager.swift:1530-1543), LockScreenManager (hides any sneak/expansion on lock, shows expandingView .lockScreen when enableLockScreenLiveActivity, hides after unlockRemovalDelay) (LockScreenManager.swift:245-273,335-345), BatteryStatusViewModel (expandingView .battery), ScreenRecordingManager (.recording), DownloadManager (.download), ExtensionLiveActivityManager, BetterDisplayManager/LunarManager (third-party DDC brightness sneak). Gate: non-extension, non-bypassed types ({music,timer,reminder,bluetoothAudio} bypass) return early when !Defaults[.enableSystemHUD] (:346-358). Per-screen visibility: isSneakPeekVisibleOnCurrentScreen (ContentView.swift:435-440) and isBatteryHUDVisibleOnCurrentScreen (:495-502). Screen size APIs: NSScreen.auxiliaryTopLeftArea/auxiliaryTopRightArea, safeAreaInsets (public).

### Settings

enableSystemHUD=true (master gate for volume/brightness/backlight/mic/capsLock/privacy etc. sneak peeks); enableSneakPeek=false; sneakPeekStyles=.standard ("Default"|"Inline"); showSneakPeekOnTrackChange=true; inlineHUD=true; showOnAllDisplays=false; hideNonNotchUntilHover; notchHeight=32, nonNotchHeight=32, notchHeightMode/nonNotchHeightMode (WindowHeightMode: matchMenuBar|matchRealNotchSize|custom), closedNotchWidth=150, customizePhysicalNotchWidth, openNotchWidth=640; useModernCloseAnimation=true; enableHaptics=true; enableMinimalisticUI=false; showNotHumanFace=false; AppStorage hudReplacement=true (legacy, unused by HUD code); AppStorage musicLiveActivityEnabled=true, timerLiveActivityEnabled=true; preferred_screen_name.

### Dependencies

sindresorhus/Defaults 9.0.3 (MIT) for settings; none required in NotchIsland (use @AppStorage/UserDefaults).

### Implementation notes

Reimplement as an @MainActor @Observable `NotchActivityCoordinator` with two value-type states (TransientHUD, Expansion) and Task-based auto-hide; keep the one-write-per-update rule to avoid racing the hide task. Render the priority chain as a single `switch` over a derived `ClosedNotchContent` enum computed from manager state rather than nested if/else; this is the biggest correctness/maintainability win. Use the same geometry constants (h-12 wings, +8 hover, +gestureProgress/2, centre = notch width, min 96). All public API. Estimated size: ~400 lines coordinator+chain, plus per-activity views.

### Key files

- `DynamicIsland/DynamicIslandViewCoordinator.swift`
- `DynamicIsland/ContentView.swift`
- `DynamicIsland/sizing/matters.swift`
- `DynamicIsland/models/DynamicIslandViewModel.swift`
- `DynamicIsland/DynamicIslandApp.swift`
- `DynamicIsland/components/Live activities/LiveActivityModifier.swift`

## Inline HUD (volume / brightness / keyboard backlight / mic / Bluetooth battery / AirPods mode / Caps Lock)

### Behaviour

With `inlineHUD` on (default), pressing volume/brightness/backlight keys shows, inside the closed notch row, a leading glyph + label ("Volume", "Brightness", "Backlight", "Mic", device name) on the left wing and a slim draggable progress capsule with optional percentage on the right wing; the notch widens to fit. Mic shows "muted"/"unmuted"; volume 0 shows "muted" in grey instead of a bar. A Bluetooth audio device connecting shows its symbol (or a looping 3D .mov icon) + name and a circular or linear battery gauge; an AirPods listening-mode change shows the mode glyph and the mode name ("Noise Cancellation", "Transparency", "Adaptive Audio", "Conversation Awareness", "Off"). Caps Lock shows capslock.fill and optionally "Caps Lock" on the right, persistently while active. Widths are constant between hover/non-hover so content does not slide.

### Layout

InlineHUD (components/Live activities/InlineHUD.swift:96-466). Root: HStack { leftInfo.frame(width: infoWidth, height: notchSize.height - (hoverAnimation ? 0 : 12), alignment .leading); Rectangle().fill(.black).frame(width: closedNotchSize.width - 20); trailing.padding(.trailing, trailingWidth > 0 ? 4 : 0).frame(width: trailingWidth, height: closedNotchSize.height - (hover ? 0 : 12)) }.frame(height: closedNotchSize.height + (hover ? 8 : 0)) (:236-456). Left info = HStack(spacing: 5){ glyph.frame(20x15).foregroundStyle(.white).symbolVariant(.fill); label } (:237-326). Glyphs: volume → speaker symbol by level (0 "speaker", ≤0.3 "speaker.wave.1", ≤0.8 ".wave.2", else ".wave.3", :533-546) or "headphones" when Bluetooth audio connected, .symbolVariant(.slash) when value==0, custom icon gets opacity 0.6 + scale 0.85 at zero (:240-254); brightness → icon or "sun.min" (≤0.6)/"sun.max" (:548-557); backlight → "light.max" (≥0.5)/"light.min" (:559-564); mic → "mic" hierarchical, slash when 0; timer → "timer"; bluetooth → AirPodsListeningModeSymbol(mode) (font size 15 medium hierarchical, frame 17x17, :83-94) or LoopingVideoIcon 20x20 (AVQueuePlayer+AVPlayerLooper, muted, resizeAspect, :30-81) when useBluetoothHUD3DIcon && deviceType.inlineHUDAnimationURL != nil, else icon/"dot.radiowaves.left.and.right"; capsLock → "capslock.fill" tinted capsLockIndicatorTintMode.color (:290-295). Label: Text(Type2Name).font(.subheadline).fontWeight(.medium).lineLimit(1).allowsTightening.contentTransition(.numericText()).white (:318-324); Bluetooth name uses MarqueeText(font .system(size:13,weight:.medium), nsFont .body, white, minDuration 0.2, frameWidth infoWidth) when showBluetoothDeviceNameMarquee (:308-315), nothing for capsLock/listening mode. Widths (:143-234): baseInfoWidth = 92 default; bluetooth: listening-mode 44 (36 minimalistic), marquee 132 (96), else 64 (56); capsLock without label 56 (48). infoWidth = max(baseInfoWidth + gestureProgress/2, minimum) where minimum = 88 default; bluetooth listening 38 (32), marquee 112 (84), else 60 (48); capsLock no-label 44 (36). baseTrailingWidth = 92 default; capsLock with label 88 (76) else 0; bluetooth without battery: listening-mode 180 (136), marquee 110 (88) else 80 (66); with battery circular: 112 (92) w/ % text else 76 (64); linear: 128 (100) w/ % else 100 (84). trailingWidth = max(base + gestureProgress/2, minimum) with minimum 90 default; capsLock label 72 (60) else 0; bluetooth listening 172 (128), marquee 102 (80) else 80 (56); circular 102 (80)/64 (48); linear 112 (88)/82 (64). Trailing content: mic → Text("muted"/"unmuted").gray trailing; timer → formattedRemainingTime in timerColor; capsLock label Text("Caps Lock").font(.subheadline).medium tinted; bluetooth listening-mode → Text(displayName).font(.caption.weight(.medium)).white.minimumScaleFactor(0.6).frame(width: min(max(trailingWidth-44, 64), 124 (96 minimalistic)), alignment .trailing) (:363-384); bluetooth battery → HStack(spacing: circular ? (pct ? 8 : 2) : (pct ? 6 : 4)){ CircularBatteryIndicator | LinearBatteryIndicator; optional Text("\(Int(value*100))%").font(.caption).medium.white } (:386-419); volume → value==0 ? Text("muted").font(.caption).medium.gray : HStack(spacing: 6){ DraggableProgressBar(colorMode:.volume); PercentageLabel } with .transition(.opacity.combined(with:.scale)) and .animation(.smooth(duration: 0.2), value: value.isZero) (:423-442); brightness/backlight → HStack(spacing:6){ DraggableProgressBar(); PercentageLabel } (:444-448). CircularBatteryIndicator (:468-497): 16x16, track Circle stroke white 0.18 lineWidth 2, fill trim(0...max(v,0.015)) rotated -90°, lineWidth 2.2 round cap, colour white or ColorCodedProgressBar.paletteColor(.battery). LinearBatteryIndicator (:499-531): 54x6 capsules, track white 0.18. Static airPodsListeningModeWidth = leading(44|36) + gestureProgress/2 + max(closedWidth-20, 0) + trailing(180|136) + gestureProgress/2 (:120-129).

### Animations

DraggableProgressBar height 5 (8 while dragging) in inline mode, 6 (9) otherwise, drag changes animated .smooth(duration: 0.3) (SystemEventIndicatorModifier.swift:254-270); battery indicators .animation(.smooth(duration: 0.18), value:) (InlineHUD.swift:495,529); glyph swaps use .contentTransition(.interpolate) / .symbolEffect; percentage/labels .contentTransition(.numericText()); muted↔bar swap .smooth(0.2) with opacity+scale transition; InlineHUD itself appears with .opacity (or move trailing + opacity for Caps Lock) under the coordinator's .smooth(0.3).

### State and timing

displayName state refreshed onAppear / type change / lastConnectedDevice.name change (:457-465). Listening-mode detection in view: activeListeningModeEvent?.mode, or type==.bluetoothAudio && value<0 → AirPodsListeningMode.fromHUDSymbol(icon) (:133-136). hasBatteryLevel = value > 0 && !listeningMode.

### Data sources and APIs

Bindings to coordinator.sneakPeek (type/value/icon) and isHovering/gestureProgress. BluetoothAudioManager.shared (isBluetoothAudioConnected, lastConnectedDevice.name/deviceType, activeListeningModeEvent). AVFoundation AVQueuePlayer/AVPlayerLooper/AVPlayerLayer (public) for the .mov icon; bundled movies BluetoothHUDAnimations/{airpods,airpodsGen3,airpodsGen4,airpodsPro,airpodsPro3,airpodsMax,beatsstudio,beatssolo}.mov (REA graph: 9 'BluetoothHUDAnimations' hits, 'airpodsPro.mov' present). Custom AirPods glyphs are SF Symbols ("ear.badge.waveform", "ear", "waveform", "person.wave.2", "airpods.pro").

### Settings

inlineHUD=true; progressBarStyle=.hierarchical ("Hierarchical"|"Gradient"|"Segmented"); showProgressPercentages=true; systemEventIndicatorShadow=false; systemEventIndicatorUseAccent=false; accentColor=Color.blue; useColorCodedVolumeDisplay=true; useColorCodedBatteryDisplay=true; useSmoothColorGradient=true; useCircularBluetoothBatteryIndicator=true; showBluetoothBatteryPercentageText=false; showBluetoothDeviceNameMarquee=false; useBluetoothHUD3DIcon=true; showCapsLockLabel=false; capsLockIndicatorTintMode=.white (green|accent|white); enableMinimalisticUI=false.

### Implementation notes

Straightforward SwiftUI; copy the width table verbatim as a struct of constants keyed by (kind, minimalistic). Use AVPlayerLooper for optional animated device icons or skip. ~350 lines.

### Key files

- `DynamicIsland/components/Live activities/InlineHUD.swift`
- `DynamicIsland/components/Live activities/SystemEventIndicatorModifier.swift`
- `DynamicIsland/components/Live activities/MarqueeTextView.swift`
- `DynamicIsland/components/ColorCodedProgressBar.swift`

## Standard (non-inline) system event indicator with progress bar styles

### Behaviour

With `inlineHUD` off, the volume/brightness/backlight/mic HUD renders as a full-width row under the closed notch content: glyph on the left, a draggable progress capsule (hierarchical/gradient/segmented style), optional 3-digit percentage. Dragging the bar sets the value. Segmented style animates a glow wave across segments as the level changes; muted volume shows "muted" text.

### Layout

SystemEventIndicatorModifier (SystemEventIndicatorModifier.swift:26-140): HStack(spacing: 14){ glyph.frame(20x15); content }.frame(maxWidth: .infinity, alignment .leading).symbolVariant(.fill).imageScale(.large). Glyphs: volume speaker symbol ("speaker.slash" at 0, wave.1 ≤0.3, wave.2 ≤0.8, wave.3) :122-135, brightness "sun.max.fill" white, backlight light.max/light.min (≥0.5), mic "mic" (+slash at 0), bluetooth mode symbol or icon. Content: mic → Text("Mic unmuted"/"Mic muted").gray numericText; volume → VolumeProgressSection (muted → Text("muted").font(.caption).medium.gray; else ProgressSection(colorMode:.volume) with .transition(.opacity.combined(with:.scale)), .animation(.smooth(0.2), value: isZero)) :156-176; others → ProgressSection. ProgressSection = HStack(spacing: 8){ DraggableProgressBar; PercentageLabel }.frame(maxWidth: .infinity, .leading) :142-154. PercentageLabel: Text(String(format:"%3d", round(value*100))).font(.caption).semibold.monospacedDigit.white 0.9.numericText.frame(width: 28, .trailing); hidden when progressBarStyle == .segmented :178-205. DraggableProgressBar (:223-332): VStack{ GeometryReader{ segmented ? SegmentedProgressContent : ZStack(.leading){ Capsule().fill(.tertiary); progressFill.opacity(value==0 ? 0 : 1) } }.gesture(DragGesture(minimumDistance:0)) }.frame(height: inlineHUD ? (dragging ? 8 : 5) : (dragging ? 9 : 6)). progressFill (:280-320): width = clamp(width*value); colour-coded → Capsule fill ColorCodedProgressBar.shapeStyle(value, mode, smooth); .gradient → LinearGradient([accent, accent.ensureMinimumBrightness(0.2)] or [.white, .white.opacity(0.2)], start .trailing end .leading); .hierarchical → accent or white; shadow(color: accent.ensureMinimumBrightness(0.7) or white, radius 8, x 3) when systemEventIndicatorShadow. SegmentedProgressContent (:334-434): 16 segments, spacing 1.5, barWidth = max(3, (W - 15*1.5)/16), RoundedRectangle(cornerRadius 2), active = index < round(value*16), colour accent or white, inactive white 0.15; shadow radius 12 on glowing segment / 4 on active when shadow enabled; .opacity(0) when value==0. ColorCodedPalette (ColorCodedProgressBar.swift:113-173): green (0.2,0.78,0.35), yellow (0.93,0.75,0.2), red (0.95,0.36,0.3); intensity = value for .volume, 1-value for .battery; discrete: <0.6 green, <0.85 yellow, else red; smooth: green below 0.6, lerp green→yellow over 0.6-0.85, yellow→red over 0.85-1.0; gradient from colour(intensity-0.15) to colour(intensity), leading→trailing.

### Animations

Segment count change .spring(response 0.3, dampingFraction 0.8); glow scale 1.15 with .spring(response 0.2, dampingFraction 0.6); wave: for each segment between old and new index, after delay i*0.015 s set glowIndex with .spring(0.2, 0.7), clear 0.2 s later with .spring(0.3, 0.8) (:400-432). Drag .smooth(0.3). Glyph .contentTransition(.interpolate) / .symbolEffect.

### State and timing

The sendEventBack closure is a no-op in ContentView (:1180-1182): dragging updates the bound sneakPeek.value visually but does not write system volume/brightness in this path (the Vertical HUD does).

### Data sources and APIs

Bindings to coordinator.sneakPeek; Defaults keys; no system APIs.

### Settings

inlineHUD=true (false selects this view); progressBarStyle=.hierarchical; showProgressPercentages=true; systemEventIndicatorShadow=false; systemEventIndicatorUseAccent=false; useColorCodedVolumeDisplay=true; useColorCodedBatteryDisplay=true; useSmoothColorGradient=true; accentColor=.blue; legacy enableGradient=false.

### Implementation notes

~250 lines of SwiftUI; reuse the palette enum for inline and window HUDs.

### Key files

- `DynamicIsland/components/Live activities/SystemEventIndicatorModifier.swift`
- `DynamicIsland/components/ColorCodedProgressBar.swift`

## System HUD pipeline: media-key interception, volume/brightness/backlight control, native OSD suppression

### Behaviour

Pressing F1/F2 brightness, F10-F12 volume/mute (and ⌘+brightness for keyboard backlight; ⌥⇧ for fine steps) is intercepted so macOS's own bezel never appears; Atoll adjusts the level itself (default 6 % steps, 2 % fine) and shows its chosen HUD (inline notch, OSD window, vertical or circular). Optional click sound on volume change. While the Mac is locked, Atoll stands down and macOS's HUD is restored; on unlock it is suppressed again. If Accessibility is not granted the tap cannot be created: keys pass through, the native HUD shows, and Atoll retries every 2 s for a minute, then every 15 s, giving up after an hour. On quit the frozen OSDUIHelper is resumed synchronously.

### Layout

No UI of its own (dispatches to InlineHUD / SystemEventIndicatorModifier / OSD windows).

### Animations

Brightness changes are animated in software: 10 steps, duration = clamp(0.08 + |delta|*1.6, 0.08...0.3) s, ease-out cubic 1-(1-t)^3, emission throttled to ≥0.04 s (~25 fps), final value force-emitted (SystemMediaControllers.swift:657-660,679,784-836,878-881). Volume feedback click min interval 0.08 s (SystemChangesObserver.swift:436).

### State and timing

Startup: SystemHUDManager.setup → CustomOSDWindowManager.initialize, start observer if any HUD enabled, SystemOSDManager.disableSystemHUD(). Media key → delegate on main queue (tap callback must return fast) → adjust → CoreAudio listener fires → sendVolumeNotification → suppressNativeOSDNow + HUD. Brightness keys drive an animation timer; auto-brightness changes are absorbed silently (baseline only).

### Data sources and APIs

MediaKeyInterceptor (managers/MediaKeyInterceptor.swift): CGEvent.tapCreate(tap: .cghidEventTap then .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, mask 1<<14 NX_SYSDEFINED) (:191-211); parses NSEvent(cgEvent:) subtype 8, keyCode = (data1 & 0xFFFF0000)>>16, keyDown = ((data1 & 0xFF00)>>8)==0xA, repeat bit 0x1 (:340-351); NX_KEYTYPE_SOUND_UP 0, SOUND_DOWN 1, BRIGHTNESS_UP 2, BRIGHTNESS_DOWN 3, MUTE 7 (:31-35); swallows handled key-down AND key-up (returns nil) and re-enables tap on .tapDisabledByTimeout/.tapDisabledByUserInput (:326-338). Requires Accessibility: AXIsProcessTrustedWithOptions prompt once (:463-472); retry policy fast 2 s x30, slow 15 s, give up 3600 s (:72-94). REA: _CGEventTapCreate, _CGEventTapEnable, _AXIsProcessTrusted, _AXIsProcessTrustedWithOptions imported. (All public API, but a HID event tap is privileged.) SystemChangesObserver (managers/SystemChangesObserver.swift) is the delegate: volume key → SystemOSDManager.suppressNativeOSDNow(); volumeController.adjust(by: ±step); VolumeFeedbackPlayer.playIfNeeded() (:185-209); mute → toggleMute; brightness key → brightness or (⌘) keyboard backlight (:217-254); dispatch order for each channel: locked → nothing; circular HUD; vertical HUD; custom OSD; else notch sneak peek via coordinator.toggleSneakPeek(type:.volume/.brightness/.backlight, value, icon "") when enableSystemHUD && none of the window HUDs (:258-396). HUDSuppressionCoordinator (SystemMediaControllers.swift:31-61) suppresses the volume HUD for 1.5 s after a Bluetooth connect/listening-mode HUD. SystemVolumeController (SystemMediaControllers.swift:63-640): CoreAudio public API — default output device via kAudioHardwarePropertyDefaultOutputDevice, AudioObjectAddPropertyListenerBlock on kAudioDevicePropertyVolumeScalar / kAudioDevicePropertyMute (elements main/1/2) and on default-device change; falls back to 'vmvc' kAudioHardwareServiceDeviceProperty_VirtualMainVolume (0x766D7663) for HDMI/DP devices (:90-95); silenceThreshold 0.001 treated as mute (:88); refuses relative adjust until a real level was read (:159-168); adjust unmutes first (:150). REA: _AudioObjectAddPropertyListenerBlock, _AudioObjectSetPropertyData imported. SystemBrightnessController (SystemMediaControllers.swift:643-980): PRIVATE CoreBrightnessDisplayClient (helpers/CoreBrightnessDisplayClient.swift) loads /System/Library/PrivateFrameworks/CoreBrightness.framework via Bundle.load and resolves class CBBrightnessProxy / CBDisplayBrightnessClient / BrightnessSystemClient / DisplayBrightnessClient, selectors brightnessForDisplay: / setBrightness:forDisplay: (display 0) via method IMP casts (:38-43,28-29); fallback PRIVATE DisplayServicesDynamic (helpers/DisplayServicesDynamic.swift) dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices") + dlsym DisplayServicesGetBrightness/DisplayServicesSetBrightness (:34-45); final fallback public IODisplayGetFloatParameter/IODisplaySetFloatParameter on IODisplayConnect (deprecated) (:758-760,846-848). External change detection: DistributedNotificationCenter names com.apple.BezelEngine.BrightnessChanged, com.apple.BezelServices.BrightnessChanged, com.apple.controlcenter.display.brightness, com.apple.CoreBrightness.DisplayBrightnessChanged (PRIVATE, undocumented) (:934-939); only shows HUD if userInitiatedBrightnessChange within 1.5 s window (:671-673); polling fallback every 0.15 s with 0.005 threshold when CoreBrightness unavailable (:665-666,958-980). REA: _dlopen/_dlsym imported; CoreBrightness/DisplayServices absent from LC_LOAD_DYLIB list (consistent with runtime loading). KeyboardBrightnessSensor (managers/KeyboardBrightnessSensor.swift): PRIVATE CoreBrightness KeyboardBrightnessClient brightnessForKeyboard:/setBrightness:forKeyboard: (keyboard id 1) (:154-200); fallback IORegistry AppleHIDKeyboardEventDriverV2 property "KeyboardBacklightBrightness" (max 342) via IORegistryEntryCreateCFProperty/SetCFProperty (:87-150, REA confirms both imports); last resort /usr/libexec/corebrightnessdiag status-info plist CBKeyboards (:111-133); perceptual mapping log10(raw+0.03)+1, raw≤0.07 → 0 (:72-85). SystemKeyboardBacklightController (84 lines) emits on a userInitiated queue and posts .keyboardBacklightDidChange. SystemDisplayManager/SystemVolumeManager (legacy helpers: IODisplayConnect brightness, corebrightnessdiag, AppleScript `get volume settings`) are fallbacks not in the main path. SystemHUDManager (managers/SystemHUDManager.swift): wires everything on launch (DynamicIslandApp.swift:748), restarts the observer when any HUD toggle changes, resolves flags (circular/vertical use enableVolumeHUD/enableBrightnessHUD/enableKeyboardBacklightHUD; custom OSD uses enableOSDVolume/…; BetterDisplay/Lunar running → brightness+backlight handled externally, optional volume too) (:258-298); lock handover updateNativeHUDSuppressionForLockState (:342-363) via SystemHUDPlacement (SystemChangesObserver.swift:34-58: both suppressesAppHUD and yieldsToNativeHUD == isLocked). SystemOSDManager (managers/SystemOSDManager.swift) — PRIVATE/fragile mechanism: disable = SIGSTOP OSDUIHelper (`/usr/bin/killall -STOP OSDUIHelper`), if not running `launchctl kickstart gui/<uid>/com.apple.OSDUIHelper` then poll up to 5 s (200 ms) and SIGSTOP, retry 3x with 250 ms settle (:214-349); watcher task re-SIGSTOPs any new PID (macOS jetsam-exits the helper when idle): 150 ms while catching, 500 ms after 5 stable checks, 1 s steady state / when not running; paused during sleep (NSWorkspace.willSleep/didWake) (:371-427); PID lookup via proc_listpids + proc_name + proc_pidinfo (PROC_PIDTBSDINFO start time, newest wins) (:450-487) — REA shows _proc_pidinfo imported but not _proc_listpids/_proc_name (see unknowns); enable = `killall -9 OSDUIHelper`, 200 ms, `launchctl kickstart`, 300 ms, fallback `launchctl load -w /System/Library/LaunchAgents/com.apple.OSDUIHelper.plist` (:103-171); suppressNativeOSDNow() immediate SIGSTOP coalesced (:232-267); resumeOSDUIHelperForTermination() synchronous `killall -CONT` with ≤1 s watcher drain, called from applicationWillTerminate (DynamicIslandApp.swift:296). Requires an unsandboxed app: entitlements in signature.json contain no com.apple.security.app-sandbox (hardened runtime + disable-library-validation + apple-events). VolumeFeedbackPlayer plays bundled audio-feedback.m4a via AVAudioPlayer (REA: 'audio-feedback' resource present).

### Settings

enableSystemHUD=true; enableVolumeHUD=true; enableBrightnessHUD=true; enableKeyboardBacklightHUD=true; systemHUDSensitivity=5 (unused in read code paths); playVolumeChangeFeedback=false; volumeStepPercent=6; volumeFineStepPercent=2; brightnessStepPercent=6; brightnessFineStepPercent=2; enableCustomOSD=false; enableVerticalHUD=false; enableCircularHUD=false; enableOSDVolume=true; enableOSDBrightness=true; enableOSDKeyboardBacklight=true; enableThirdPartyDDCIntegration=false; thirdPartyDDCProvider=.betterDisplay; enableExternalVolumeControlListener=false; hasSeenOSDAlphaWarning=false.

### Dependencies

None (Foundation/CoreAudio/IOKit/CoreGraphics/ApplicationServices).

### Implementation notes

For NotchIsland prefer: CGEvent tap for media keys (public, needs Accessibility) + CoreAudio listeners (public) + IOKit/IODisplay or DisplayServices-free approach. Killing/suspending OSDUIHelper is a private, fragile hack that also requires no sandbox; a public alternative is to intercept the keys (which prevents the native OSD from being triggered at all for volume/brightness since macOS only draws the bezel in response to the key event it receives) — Atoll still suppresses because CoreAudio writes wake the OSD helper. Keyboard backlight and display brightness have no public write API on Apple Silicon besides private CoreBrightness/DisplayServices; mark as optional. Size: ~1,500 lines in Atoll; a minimal public-only reimplementation (tap + CoreAudio + IODisplay best-effort) ~500 lines.

### Key files

- `DynamicIsland/managers/MediaKeyInterceptor.swift`
- `DynamicIsland/managers/SystemChangesObserver.swift`
- `DynamicIsland/managers/SystemHUDManager.swift`
- `DynamicIsland/managers/SystemOSDManager.swift`
- `DynamicIsland/managers/SystemMediaControllers.swift`
- `DynamicIsland/managers/KeyboardBrightnessSensor.swift`
- `DynamicIsland/managers/SystemKeyboardBacklightController.swift`
- `DynamicIsland/helpers/CoreBrightnessDisplayClient.swift`
- `DynamicIsland/helpers/DisplayServicesDynamic.swift`
- `DynamicIsland/managers/SystemDisplayManager.swift`
- `DynamicIsland/managers/SystemVolumeManager.swift`
- `DynamicIsland/managers/SystemKeyObserver.swift`
- `DynamicIsland/helpers/SystemHUDDebugger.swift`

## Custom OSD window (macOS-style 200x200 bezel replacement)

### Behaviour

When `enableCustomOSD` is on, volume/brightness/backlight changes show a 200x200 rounded square at bottom-centre of every screen (120 pt above the bottom), with a large hierarchical SF Symbol and a 16-segment bar; slides up 20 pt while fading in over 0.3 s, stays 2.0 s, slides down/fades out over 0.3 s. Material options: frosted (ultraThinMaterial), Liquid Glass (macOS 26), solid dark/light/auto; icon colour styles white/black/grey/auto with transparent variants.

### Layout

CustomOSDView (components/OSD/CustomOSDView.swift:25-194): VStack(spacing: 20){ ZStack{ Image(systemName:).font(.system(size: 56, weight: .regular)).symbolRenderingMode(.hierarchical).foregroundStyle(iconColor) }.frame(width: 80, height: 60); progressView.frame(width: 140).padding(.top, 4) }.frame(200x200).background(RoundedRectangle(18, .continuous).fill(.black.opacity(0.1)).shadow(black 0.25, radius 24, y 8)).background(material clipped to RoundedRectangle(18)).clipShape(RoundedRectangle(18)). Symbols: volume <0.01 speaker.slash.fill, <0.33 speaker.fill, <0.66 speaker.wave.1.fill, else speaker.wave.3.fill; brightness sun.max.fill; backlight light.max/light.min (≥0.5) (:72-98). progressView: HStack(spacing: 3){ 16 x Capsule().frame(6x6) } active = iconColor, inactive white/black 0.25 (:134-153). Icon colours: white, white 0.85, Color(white: 0.85), Color(white: 0.3), black, black 0.85, auto by colorScheme (:100-119). Window (managers/CustomOSDWindowManager.swift): NSWindow styleMask [.borderless, .nonactivatingPanel], isOpaque false, clear background, level .statusBar + 1, collectionBehavior [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary], hasShadow false, alpha 0, SkyLightOperator.shared.delegateWindow(window) (:179-203); frame x = screen.midX - 100, y = screen.minY + 120, 200x200 (:210-218); one window per screen per type (volume/brightness/backlight dictionaries).

### Animations

Present: start frame offset dy -20, NSAnimationContext duration 0.3 easeOut → target frame + alpha 1 (:220-232). Hide: duration 0.3 easeIn, frame offset dy -20, alpha 0, then orderOut (:277-306). Switching type hides other-type windows immediately with 0.15 s easeIn fade (:252-261). displayDuration 2.0 s (:39) via DispatchWorkItem rescheduled on each show.

### State and timing

Windows are created lazily per screen and kept (alpha 0) for reuse; content replaced by swapping hostingView.rootView.

### Data sources and APIs

Fed by SystemChangesObserver (showVolume/showBrightness/showBacklight). AppKit NSWindow/NSHostingView, NSAnimationContext (public). SkyLightWindow package (Lakr233) delegates the window to a private SkyLight space so it draws over full-screen apps/lock-screen-adjacent contexts — PRIVATE (CGSSpaceCreate/CGSAddWindowsToSpaces/CGSSpaceSetAbsoluteLevel/_CGSDefaultConnection all confirmed imported in REA macho.json). Hides all windows when enableCustomOSD or a per-type toggle turns off (:88-120).

### Settings

enableCustomOSD=false; enableOSDVolume=true; enableOSDBrightness=true; enableOSDKeyboardBacklight=true; osdMaterial=.frosted ("Frosted Glass"|"Liquid Glass"|"Solid Dark"|"Solid Light"|"Solid Auto"); osdLiquidGlassCustomizationMode=.standard; osdLiquidGlassVariant=.defaultVariant; osdIconColorStyle=.white (White|White (Transparent)|Light Gray|Dark Gray|Black|Black (Transparent)|Auto|Auto (Transparent)).

### Dependencies

SkyLightWindow (github.com/Lakr233/SkyLightWindow, rev 4a7e862; license MIT — verify) used only for window delegation; optional.

### Implementation notes

Reimplement with an NSPanel at .statusBar+1 and collectionBehavior above; use public `.fullScreenAuxiliary` and skip SkyLight (loses lock-screen overlay only). ~300 lines.

### Key files

- `DynamicIsland/components/OSD/CustomOSDView.swift`
- `DynamicIsland/components/OSD/HUDNumericLabel.swift`
- `DynamicIsland/managers/CustomOSDWindowManager.swift`
- `DynamicIsland/helpers/LiquidGlassBackground.swift`

## Vertical HUD window (elastic capsule)

### Behaviour

When `enableVerticalHUD` is on, a 36x160 vertical capsule appears at the left or right screen edge (24 pt padding, vertically centred), fills from the bottom with white/accent or volume colour-coding, shows the percentage at top (10 pt bold) and the glyph at the bottom. Pressing a key at the limit (≥0.99 / ≤0.01) makes the capsule stretch 15 pt in that direction and spring back (elastic bump). Optionally interactive: dragging sets volume/brightness with rubber-banding beyond the ends. Fades in 0.2 s, stays 2 s, fades out 0.2 s.

### Layout

VerticalHUDView (components/OSD/VerticalHUDView.swift:42-293): ZStack{ ZStack{ background.clipShape(Capsule()).overlay(Capsule().stroke(.white 0.1, lineWidth 1)); GeometryReader{ VStack{ Spacer; Rectangle().fill(fillStyle).frame(height: H*value) } }.clipShape(Capsule()); VStack{ if showValue HUDNumericLabel(font .system(size 10, bold), colour value>0.85 ? (accent ? white : black) : .secondary, width hudWidth*0.8).padding(.top, 8 + …); Spacer; Image(symbol).font(.system(size: hudWidth*0.4, semibold)).hierarchical.foregroundStyle(value>0.15 ? (accent ? .white : .black) : .secondary).padding(.bottom, hudWidth*0.35) } }.frame(width: dragging ? hudWidth*0.9 : hudWidth, height: hudHeight + stretchAmount).offset(y: stretchOffset).shadow(black 0.15, radius 10, y 4) }.frame(maxWidth/maxHeight .infinity). Symbols: volume <0.01 speaker.slash.fill, <0.33 speaker.wave.1.fill, <0.66 wave.2, else wave.3; brightness sun.max.fill; backlight light.max/min (:218-234); volume icon may be the Bluetooth device symbol or "headphones.slash" when muted (SystemChangesObserver.swift:310-316). fillStyle: volume colour-coded → vertical gradient of ColorCodedPalette (bottom→top) or discrete; else accent or white (:238-251). Window (managers/VerticalHUDWindowManager.swift): shadowPadding 120 (60/side) so frame = (w+120)x(h+120); x = minX + padding - 60 (left) or maxX - w - padding - 60 (right); y = midY - totalH/2 (:71-104); level .screenSaver, [.borderless,.nonactivatingPanel], collection [.canJoinAllSpaces,.stationary,.ignoresCycle,.fullScreenAuxiliary], ignoresMouseEvents unless interactive && visible (:205-227). HUDNumericLabel (OSD/HUDNumericLabel.swift): monospacedDigit, numericText transition, animation .interactiveSpring(response 0.35, dampingFraction 0.75, blendDuration 0.15), format %3d.

### Animations

Fill .interactiveSpring(response 0.55, dampingFraction 0.85, blendDuration 0.3) (:89). Hover .spring(0.5, 0.8). Bump: .task(id: bumpEvent) → .interactiveSpring(0.35, 0.6) stretchAmount 15, offset ∓7.5; after 150 ms .spring(0.55, 0.65) back to 0 (:127-148). Drag: isDragging .spring(0.4,0.75); rubber band stretch = min(sqrt(|excess|)*1.5, 30) with .interactiveSpring(0.4,0.65); in-range .interactiveSpring(0.45,0.8); release .spring(0.55,0.7) (:149-199). Window alpha 0.2 s in/out, displayDuration 2.0 (:34-35).

### State and timing

One VerticalHUDState (ObservableObject: type, value, icon, bumpEvent) per screen; content updates mutate state instead of recreating the view. Layout re-applied when any geometry Default changes; windows torn down when disabled.

### Data sources and APIs

Drag writes via SystemVolumeController.setVolume / SystemBrightnessController.setBrightness (:210-216). Bump triggered from SystemChangesObserver when direction hits the limit (SystemChangesObserver.swift:195-203,228-245). Same SkyLightWindow delegation (PRIVATE) as the OSD window.

### Settings

enableVerticalHUD=false; verticalHUDPosition="right" ("left"|"right"); verticalHUDShowValue=true; verticalHUDInteractive=true; verticalHUDHeight=160; verticalHUDWidth=36; verticalHUDPadding=24; verticalHUDUseAccentColor=false; verticalHUDMaterial=.frosted; verticalHUDLiquidGlassCustomizationMode=.standard; verticalHUDLiquidGlassVariant=.defaultVariant; useColorCodedVolumeDisplay=true; useSmoothColorGradient=true.

### Implementation notes

~450 lines; all SwiftUI/AppKit public except SkyLight.

### Key files

- `DynamicIsland/components/OSD/VerticalHUDView.swift`
- `DynamicIsland/managers/VerticalHUDWindowManager.swift`
- `DynamicIsland/components/OSD/HUDNumericLabel.swift`

## Circular HUD window (dial)

### Behaviour

When `enableCircularHUD` is on, a 65 pt opaque dark dial appears centred on each screen: a 252° arc track with an animated progress arc and a white ball indicator, a bold central glyph (headphones/AirPods icon when such an output is default) and a percentage below. Fades in 0.2 s, stays 2 s, fades out 0.2 s.

### Layout

CircularHUDView (components/OSD/CircularHUDView.swift:24-206): ZStack{ Circle().fill(Color(white: 0.1)).overlay(Circle().stroke(Color(white: 0.2), 1)); track Circle().trim(0.15...0.85).stroke(Color(white: 0.15), lineWidth strokeWidth*1.5, round).rotation 90°; progress trim(0.15 ... 0.15 + 0.7*value) stroke(strokeStyle) rotation 90°; ball Circle().fill(.white).frame(trackWidth*1.45).shadow(black 0.45, radius 2, y 1.2) positioned at angle 144° + 252°*value on radius size/2; Image(symbol).font(.system(size: size*0.32, bold)).hierarchical.white.contentTransition(.symbolEffect(.replace)); if showValue HUDNumericLabel(font .system(size: size*0.15, bold, rounded), white 0.65).padding(.bottom, size*0.03) }.frame(size x size).shadow(black 0.2, radius 15, y 5). strokeStyle: volume colour-coded palette, else accent, else Color(white: 0.25) (:112-123). Symbols: AirPods default output → "airpods"/"headphones.slash"; headphones → "headphones"; else speaker.slash.fill/<0.33 wave.1/<0.66 wave.2/wave.3; brightness sun.max.fill; backlight "keyboard" (:125-155). Window: size+80 square centred, level .screenSaver, same style/collection as vertical HUD (:92-130).

### Animations

Arc and ball .interactiveSpring(response 0.35, dampingFraction 0.85, blendDuration 0) (:62,79); symbol swap .spring(response 0.3, dampingFraction 0.6) (:89); window alpha 0.2 s, displayDuration 2.0 (:33-34).

### State and timing

Windows kept hidden for fast re-show; frame re-centred when circularHUDSize changes.

### Data sources and APIs

CoreAudio default output device name via kAudioHardwarePropertyDefaultOutputDevice + kAudioDevicePropertyDeviceNameCFString to pick headphone/AirPods glyph (:162-205, public). SkyLight delegation (PRIVATE).

### Settings

enableCircularHUD=false; circularHUDShowValue=true; circularHUDSize=65; circularHUDStrokeWidth=4; circularHUDUseAccentColor=true; useColorCodedVolumeDisplay=true; useSmoothColorGradient=true.

### Implementation notes

~250 lines.

### Key files

- `DynamicIsland/components/OSD/CircularHUDView.swift`
- `DynamicIsland/managers/CircularHUDWindowManager.swift`

## Battery live activity (charging / low / full temporary HUD) and battery indicator

### Behaviour

Plugging in power shows a compact pill HUD in the closed notch: "Charging" on the left, "NN%" + a small filled battery glyph on the right, for 3 s. Dropping to ≤20 % (while unplugged) shows a Low Battery HUD (standard: taller two-line card with a pulsing red battery illustration, or compact pill) for 3 s and plays lowbattery.mp3; reaching 100 % shows a Full Battery card (MagSafe illustration that turns from orange to green, then swaps to a pulsing green battery) for 3 s. Enabling Low Power Mode also triggers the low-battery HUD in yellow. In the open notch header a battery indicator (percentage + glyph, or Apple-style filled battery with the number inside) is shown; clicking it opens a popover with capacity, charging state, time to full and a Battery Settings button.

### Layout

BatteryTemporaryActivityView (components/Live activities/DynamicIslandBattery.swift:543-891): metrics (:464-497) — charging or any .compact: width closedNotchWidth + 180, height baseHeight, topRadius max(12, compactBaseRadius-4), bottomRadius compactBaseRadius = max(baseHeight/2, 16); lowBattery .standard: width +150, height +75, radii 22/40; fullBattery .standard: width +140, height +70, radii 18/36 (NOTE the window/notch-size computation in ContentView:173-182 and DynamicIslandApp:549-558 uses +100 / +80 width for the standard styles, so the view is clipped to the notch shape). Root ZStack(.bottom){ content }.frame(width, height, .bottom).clipShape(isDynamicIslandMode ? DynamicIslandPillShape(cornerRadius: 24) : NotchShape(topCornerRadius: closed.top (6), bottomCornerRadius: metrics.bottomRadius)) (:601-616); closedNotchWidth passed = closedNotchSize.width + (hover ? 8 : 0), baseHeight = effectiveClosedNotchHeight + (hover ? 8 : 0) (ContentView.swift:1118-1119). Compact: BatteryCompactStatusRow (:499-541) HStack{ Text(title).font(.system(size:14)).white 0.8; Spacer; HStack(spacing:6){ Text("NN%").font(14).tint; HStack(spacing:1.5){ ZStack(.leading){ RoundedRectangle(6,.continuous).fill(tint 0.3); GeometryReader Rectangle().fill(tint.gradient).frame(width: level/100*W) }.frame(28x16).clipShape(RoundedRectangle(6)); RoundedRectangle(1.5).fill(level==100 ? tint.gradient : tint 0.3 gradient).frame(2x6) } } }.padding(.horizontal, 16). Titles: "Charging"/"Low Battery"/"Full Battery". Tint: charging → yellow if low power, red if ≤20, else green; low → yellow/red; full → yellow/green (:584-598). Standard: VStack{ Spacer; HStack{ VStack(.leading, spacing: low ? 2 : 3){ title HStack(spacing 5){ Text("Battery Low"/"Full Battery").font(13 semibold).white 0.82; Text("NN%").font(low ? 12 : 13 semibold).tint }; description .font(10 medium) gray 0.6 (low: "Turn on Low Power Mode or it\nis recommended to charge it." 2 lines, or yellow "Low Power Mode enabled" + ", it is recommended to charge it."; full: "Your Mac is fully charged.") }; Spacer; indicator }.padding(.leading, low ? 40 : 35).padding(.trailing, low ? 45 : 40).padding(.bottom, 20) } (:628-702). Indicators (:731-855): red/yellow low = ZStack{ RoundedRectangle(30).fill(colour 0.2).frame(70x40); HStack(spacing 2){ RoundedRectangle(10).fill(colour 0.4).frame(40x24); RoundedRectangle(10).fill(colour 0.4).frame(3x8) }.padding(.trailing 5); RoundedRectangle(8).fill(colour.gradient).frame(8x14).offset(x:-15) [red: opacity pulse 1↔0.3 + stroke ring RoundedRectangle(30).stroke(red 0.9, 1.5) frame pulse ? 8x14 : 30x32, opacity pulse ? 0.3 : 1] }; green/yellow full = 70x40 pill with 44x24 body overlaid by RoundedRectangle(4).fill(gradient).frame(34x14) opacity pulse ? 1 : 0.4, terminal 3x8; magSafe = HStack(spacing 0){ Rectangle gray 0.15 30x5; ZStack{ RoundedRectangle(2).fill(gray 0.2 gradient).frame(30x40); Circle().fill(orange→green).shadow(same colour, radius 5).frame(5x5) }; Rectangle white 0.4 3x32 }. Header indicator DynamicIslandBatteryView (:364-454): HStack{ if showBatteryPercentage && !showBatteryPercentInside: ZStack(.trailing){ Text("100%").font(.callout).hidden(); Text("NN%").font(.callout).white }.fixedSize; BatteryView(batteryWidth: 30 in header) }, press scale 0.95, popover BatteryMenuView width 280 (:281-360). BatteryView filled body (:81-131): height = width*0.52, inset 1.5, bodyRadius height*0.34, body fill white 0.45, fill colour batteryColor (yellow low power / red ≤20 unplugged / green charging|plugged|100 / white) width max((w-3)*fraction, 2), number .system(size: height*0.62, bold, rounded) black 0.82 + bolt.fill/powerplug.fill at height*0.42 bold, terminal RoundedRectangle(height*0.1) width height*0.11 height height*0.36, spacing height*0.11. Outlined body (:149-183): "battery.0" symbol thin white 0.5 width w+1, inner RoundedRectangle(2.5) width (level/100)*(w-6) height (w-2.75)-18, leading 2, asset Image("bolt"/"plug") 17x17. MinimalisticBatteryView (:187-278): 28x16 RoundedRectangle(5) body fill colour 0.3 + gradient fill, number .system(size: h*0.6, heavy, rounded) (white when charging else black), terminal 2 x max(4, h*0.38) radius 1.5, spacing 1.5.

### Animations

Filled BatteryView .animation(.smooth(duration: 0.3), value: level/colour) (:124-125); minimalistic .smooth(0.18) (:274-276); header press .easeInOut(0.2) (:410). Temporary HUD prepareAnimations (:857-890): standard low (not low-power) pulse .easeInOut(duration 1).repeatForever(autoreverses) ; standard full: same pulse, after 2 s withAnimation(.spring(duration 0.4)) showBatteryIndicator=false (swap to MagSafe), after 3 s withAnimation(.spring(duration 0.2)) changeBatteryIndicator=false (orange→green); indicator transitions .opacity.combined(with: .scale). Appearance is the coordinator's expandingView .smooth animation; view re-mounted per event via .id(activeTemporaryHUDToken). Battery model updates wrapped in withAnimation (BatteryStatusViewModel.swift:93-143).

### State and timing

activeTemporaryHUDKind/Token/TargetScreenName/LevelOverride/LowPowerModeOverride published; the view is shown while expandingView.show && type == .battery && isBatteryHUDVisibleOnCurrentScreen; hidden by the coordinator's auto-hide (duration from settings, min 1 s). MacBatteryManager is a stateless helper (time-to-full formatting) used by lock screen.

### Data sources and APIs

IOKit.ps public: IOPSNotificationCreateRunLoopSource on CFRunLoopGetCurrent .defaultMode, IOPSCopyPowerSourcesInfo/IOPSCopyPowerSourcesList/IOPSGetPowerSourceDescription keys kIOPSCurrentCapacityKey, kIOPSMaxCapacityKey, "Is Charging", kIOPSPowerSourceStateKey == kIOPSACPowerValue, kIOPSTimeToFullChargeKey (BatteryActivityManager.swift:91-101,236-301); NSProcessInfoPowerStateDidChange for Low Power Mode (:76-88). REA confirms _IOPSNotificationCreateRunLoopSource and _IOPSCopyPowerSourcesInfo imports and 'lowbattery' resource. Events are queued and delivered 1.0 s apart (:200-215). Triggers (BatteryStatusViewModel.swift:88-148,164-287): !wasPluggedIn→pluggedIn ⇒ .charging; level crossing down through lowBatteryHUDThreshold while unplugged & not charging ⇒ .lowBattery (+ sound if playLowBatteryAlertSound); crossing up through fullBatteryHUDThreshold ⇒ .fullBattery; Low Power Mode turning on ⇒ .lowBattery. presentTemporaryBatteryHUDIfNeeded sets kind/token/targetScreen/overrides then coordinator.toggleExpandingView(status: true, type: .battery, autoHideDuration: max(1, duration)). Target screen = selectedScreen → preferredScreen → NSScreen.main unless showOnAllDisplays (:225-242). triggerTestHUD for settings preview (:168-186). Battery Settings deep link x-apple.systempreferences:com.apple.preference.battery.

### Settings

showPowerStatusNotifications=true; showBatteryIndicator=hasBattery(); showBatteryPercentage=true; showBatteryPercentInside=true; showMinimalisticBatteryIndicator=true; showPowerStatusIcons=true; playLowBatteryAlertSound=true; showChargingBatteryHUD=true; showLowBatteryHUD=true; showFullBatteryHUD=true; chargingBatteryHUDDuration=3 (s); lowBatteryHUDDuration=3; fullBatteryHUDDuration=3; lowBatteryHUDThreshold=20; fullBatteryHUDThreshold=100; lowBatteryHUDStyle=.standard (standard|compact); fullBatteryHUDStyle=.standard; showOnAllDisplays=false.

### Implementation notes

All public API. Reproduce the compact pill (closed width + 180) first; standard cards need NotchShape with per-event bottom radius. ~700 lines incl. illustrations.

### Key files

- `DynamicIsland/components/Live activities/DynamicIslandBattery.swift`
- `DynamicIsland/models/BatteryStatusViewModel.swift`
- `DynamicIsland/managers/BatteryActivityManager.swift`
- `DynamicIsland/managers/MacBatteryManager.swift`
- `DynamicIsland/components/Notch/DynamicIslandHeader.swift`

## Screen recording live activity

### Behaviour

When any process starts capturing the screen (macOS screen recording, screenshots UI recording, screen sharing apps), the closed notch shows a red pulsing dot in a translucent red rounded square on the left and a red elapsed-time counter (m:ss) on the right (compact, +132 pt wide). Hovering (when a stop button is enabled and no screen-sharing app is frontmost) either widens inline to +176 pt adding a circular stop button, or expands to a +140 pt wide, +70 pt tall card with "Screen Recording", the timer, a status line and a 54 pt stop button. Pressing stop sends ⌘⌃Esc (System Events, then CGEvent) and kills `screencapture`; on failure the text turns to "Failed" / explanatory message for 3 s and the system beeps. When music is playing the recording becomes a badge on the album art instead.

### Layout

RecordingLiveActivity (components/Recording/RecordingLiveActivity.swift:22-213): VStack(spacing:0){ Spacer; expanded ? expandedDetails.frame(hudWidth x hudHeight) : HStack(spacing 0){ badge.frame(leadingWidth x rowHeight); Rectangle(.black).frame(centerWidth x effectiveClosedNotchHeight); trailingStatus.frame(trailingWidth x rowHeight) }.frame(hudWidth x effectiveClosedNotchHeight) }.frame(hudWidth x hudHeight, .bottom). hudWidth = closedNotchSize.width + presentation.extraWidth (compact 132 / inline 176 / expanded 140); hudHeight = effectiveClosedNotchHeight + (expanded ? 70 : 0) (RecordingHUDLayout.swift:21-40); centerWidth = closed width + (hover ? 8 : 0); rowHeight = h - 12; leadingWidth = h - 12 + gestureProgress/2 (0 until visible); trailingWidth = hudWidth - centerWidth - leadingWidth (:83-107). Badge: ZStack{ RoundedRectangle(6).fill(red 0.15); Circle red 10 pt + PulsingModifier }.frame(rowHeight x rowHeight), leading aligned (:117-130). Trailing: HStack(spacing 10){ Text(formattedDuration or "Failed").font(.system(size 14, semibold, rounded)).monospacedDigit.red.minimumScaleFactor(0.72).numericText; inline → stopButton(size: clamp(h-8, 22...30), lineWidth 1.6) }.padding(.trailing, 10) (:132-150). Expanded: HStack{ VStack(.leading, spacing 3){ HStack(spacing 6){ Text("Screen Recording").font(13 semibold).white 0.84; duration .font(13 semibold rounded) red }; Text(status).font(10 medium) gray 0.6 (red 0.78 on failure) }; Spacer(minLength 8); stopButton(size 54, lineWidth 2.4) }.padding(.leading 35).padding(.trailing 40).padding(.top 29).padding(.bottom 20) (:152-183). Stop button: Circle().strokeBorder(white 0.95 (0.5 while sending), lineWidth) + RoundedRectangle(max(3, size*0.1), .continuous).fill(.red).frame(size*0.38) scale 0.84 while sending (:192-212). Music-pairing: badge Circle red size*0.45 pulsing (ContentView.swift:1660-1664); right wing = spectrum with trailingInset 6, width min(base, max(38, min(base*0.6, min(base-6, 52)))) (:1625-1632,1733-1734). PulsingModifier (PulsingModifier.swift): scale 1.2 / opacity 0.7, .easeInOut(0.8).repeatForever(autoreverses).

### Animations

isVisible fade/width-in .smooth(duration 0.32) on appear and when recording starts, .smooth(0.2) when it stops (:57-66); presentation swap .transition(.opacity); isRecording toggled under withAnimation(.smooth) in the manager (ScreenRecordingManager.swift:441,452); dot pulse 0.8 s.

### State and timing

RecordingStopControlState: unavailable → ready (on start) → sending → ready/unavailable or failed(message) cleared after 3 s. makeRecordingHUDLayout drives notch window sizing (expanded: true for sizing so the window is pre-sized).

### Data sources and APIs

PRIVATE SkyLight/CGS: `@_silgen_name("CGSIsScreenWatcherPresent")` polled on events and `CGSRegisterNotifyProc(callback, 1502 /*screen capture connect*/, ctx)` and 1503 (disconnect) (ScreenRecordingManager.swift:23-34,375-385,432-457) — REA confirms _CGSIsScreenWatcherPresent and _CGSRegisterNotifyProc are imported by the shipped binary. NSWorkspace didActivate/didTerminateApplication to flag screen-sharing apps (FaceTime, Screen Sharing, Webex, Discord, Teams, Skype, Slack, Zoom bundle IDs / name tokens) which suppress hover expansion (:42-75,387-430). Stop: AppleScript System Events key code 53 with command+control (needs Apple Events automation) then CGEvent key down/up at HID and session taps with 45/80 ms gaps, repeated after 120/300 ms (:116-181); `/usr/bin/pgrep -x screencapture`, `killall -INT/-TERM screencapture`, `-TERM screencaptureui`, `-TERM ScreenCaptureUI` with 180 ms checks (:313-373); waits 2x250 ms then 8x250 ms (:269-285). Duration Timer 1 s; duration reset 2 s after stop (:459-488). coordinator.toggleExpandingView(.recording) on start/stop (auto-hidden by coordinator after 3 s; the live activity itself stays while isRecording).

### Settings

enableScreenRecordingDetection=true; showRecordingIndicator=true; recordingHoverStyle=.default (default|inline); recordingControlMode=.withStopButton (indicatorOnly|withStopButton).

### Implementation notes

Public alternative for detection: poll `CGWindowListCopyWindowInfo` for the screencapture UI or use `SCShareableContent`? Neither reports third-party capture; the only robust signal is the private CGSIsScreenWatcherPresent. Suggest a polling fallback (1 s) on `CGPreflightScreenCaptureAccess`-independent heuristics plus NSWorkspace app detection, and expose the private symbol behind a feature flag. ~450 lines.

### Key files

- `DynamicIsland/managers/ScreenRecordingManager.swift`
- `DynamicIsland/components/Recording/RecordingLiveActivity.swift`
- `DynamicIsland/helpers/RecordingHUDLayout.swift`
- `DynamicIsland/components/Live activities/PulsingModifier.swift`

## Camera / microphone privacy indicators

### Behaviour

When an app uses the camera, a green video.fill dot appears on the right wing of the closed notch; when the microphone is in use an orange mic.fill dot appears. Both active: mic on the left wing, camera on the right (or both on the right while also screen recording, with the recording pulsator on the left). Wings animate open/closed over 0.4 s. Shown only when neither music nor higher-priority activities are showing.

### Layout

PrivacyLiveActivity (components/Privacy/PrivacyLiveActivity.swift:22-119): HStack(spacing 0){ left Color.clear.background{ if expanded HStack{ recording ? ZStack{ RoundedRectangle(6).fill(red 0.15); Circle red 10 pulsing }.frame((h-12)x(h-12)) : bothActive ? PrivacyIcon(.microphone) }.leading }.frame(width: expanded && (recording || both) ? max(0, h - (hover ? 0 : 12) + gestureProgress/2 + 20) : 0, height: h - (hover ? 0 : 12)); Rectangle(.black).frame(width: closedNotchSize.width + (hover ? 8 : 0)); right Color.clear.background{ HStack(spacing 4){ icons }.trailing }.frame(width: expanded ? max(0, h - (hover?0:12) + gestureProgress/2 + 20) : 0, height: …) }.frame(height: h + (hover ? 8 : 0)). PrivacyIcon (:122-139): Image(systemName: "video.fill"/"mic.fill").font(.system(size: 13, weight: .semibold)).foregroundColor(camera ? Color(red 0.152, green 0.804, blue 0.256) /*#26CC41*/ : Color(red 1.0, green 0.584, blue 0.010) /*#FF9402*/).frame(24x24). An alternative glowing orange PrivacyIndicatorIcon (24 pt radial glow, 18 pt circle, 9 pt glyph, 1.5 s pulse) exists in components/PrivacyIndicatorIcon.swift:55-124 for settings/detail views.

### Animations

isExpanded toggled with .smooth(duration: 0.4) on appear and when hasAnyIndicator changes (:102-117); manager state changes wrapped in withAnimation(.smooth) (PrivacyIndicatorManager.swift:152,168,185); PulsingModifier for recording dot.

### State and timing

activeApp is always "Unknown App" (not resolved). Screen recording state is mirrored into the layout but the standalone PrivacyLiveActivity only shows when RecordingLiveActivity did not already win the priority chain (i.e. when recording indicator disabled or music pairing active).

### Data sources and APIs

CameraMonitor (managers/CameraMonitor.swift): CoreMediaIO public — enumerate kCMIOHardwarePropertyDevices, filter devices with input streams (kCMIODevicePropertyStreams, input scope), CMIOObjectAddPropertyListener for kCMIODevicePropertyDeviceIsRunningSomewhere (wildcard scope/element) on each device, read the same property; OR'd with AVCaptureDevice.DiscoverySession([.builtInWideAngleCamera, .external]).devices.isInUseByAnotherApplication (:152-362). MicrophoneMonitor (managers/MicrophoneMonitor.swift): CoreAudio public — default input device kAudioHardwarePropertyDefaultInputDevice, AudioObjectAddPropertyListener kAudioDevicePropertyDeviceIsRunningSomewhere (global scope, master element) and read it (:155-309). REA confirms _CMIOObjectAddPropertyListener, _CMIOObjectGetPropertyData(Size), _AudioObjectAddPropertyListener imports. PrivacyIndicatorManager (managers/PrivacyIndicatorManager.swift) combines camera/mic/ScreenRecordingManager.isRecording into IndicatorLayout (8 cases) and hasAnyIndicator (respecting enableCameraDetection/enableMicrophoneDetection). Started at launch unless UI testing (DynamicIslandApp.swift:771-772). Both monitors are event-driven only (no polling); note the mic listener is bound to the default input device at start and is not re-bound on route change. Camera entitlement com.apple.security.device.camera present; NSCameraUsageDescription "We need your camera for Mirror mode".

### Settings

enableCameraDetection=true; enableMicrophoneDetection=true.

### Implementation notes

Entirely public API; ~500 lines. Re-bind the mic listener on kAudioHardwarePropertyDefaultInputDevice changes in NotchIsland.

### Key files

- `DynamicIsland/managers/PrivacyIndicatorManager.swift`
- `DynamicIsland/managers/CameraMonitor.swift`
- `DynamicIsland/managers/MicrophoneMonitor.swift`
- `DynamicIsland/components/Privacy/PrivacyLiveActivity.swift`
- `DynamicIsland/components/PrivacyIndicatorIcon.swift`

## Focus / Do Not Disturb live activity

### Behaviour

When a Focus mode turns on, the closed notch grows a left wing with the Focus glyph in the mode's accent colour (moon for DND, briefcase for Work, bed for Sleep, …) and, by default, a right wing with the mode name in the same colour ("Do Not Disturb", "Work", custom names via Full Disk Access). It stays while Focus is active (persistent mode) or, in non-persistent toast mode, shows glyph + "On" for 1.8 s then collapses; turning Focus off plays an "Off" toast (white glyph, 1.5 s) or, in persistent mode, briefly pops the glyph to 1.2x and collapses. Switching modes while active re-plays the ON toast. When music is playing, the Focus glyph becomes a badge on the album art and the right wing keeps the spectrum.

### Layout

DoNotDisturbLiveActivity (components/Focus/DoNotDisturbLiveActivity.swift:23-487): HStack(spacing 0){ iconWing.frame(iconWingWidth x wingHeight); Rectangle(.black).frame(width: centerSegmentWidth); labelWing.frame(labelWingWidth x wingHeight) }.frame(width: notchEnvelopeWidth, height: effectiveClosedNotchHeight). wingHeight = max(h - 10, 20) (:89-91); minimalWingWidth = max(h - 12, 24) (:113-115); iconWingWidth = (expanded || showInactiveIcon) ? minimalWingWidth : 0; labelWingWidth: label hidden → toast ? 0 : minimalWingWidth (when expanded); toast → max(intrinsic + 26, minimal); persistent → max(desiredLabelWidth, minimal) where desiredLabelWidth = max(closedWidth*0.52, 136), ≥164 for DND, ≥ intrinsic + 8 when not marqueeing (:97-145); centerSegmentWidth = pixel-aligned closed width (floor(w*scale)/scale) or, for a fully collapsed toast, closedWidth - (6 + 14) corner insets (:65-130). Icon: currentIcon.font(.system(size 13, semibold)).foregroundColor(accent or white when inactive).scaleEffect(iconScale) (:270-283). Label: .system(size 12, weight .semibold, design .rounded), accent colour (white for "Off"), lineLimit 1, minimumScaleFactor 0.8, trailing aligned, .padding(.horizontal 4); MarqueeText(nsFont .caption1, minDuration 0.4, frameWidth max(48, labelWing - 8)) when intrinsic width > width of "Do Not Disturb" (:285-321). Labels: toast → "On"/"Off"; else focus name, "Do Not Disturb", mode displayName or "Focus"; "Reduce Interruptions" is shortened to "Reduce Interr." (DoNotDisturbManager.swift:243). FocusModeType (DoNotDisturbManager.swift:672-784): identifiers com.apple.donotdisturb.mode, com.apple.focus.work/personal/sleep/driving/fitness/gaming/mindfulness/reading/reduce-interruptions/custom; sfSymbol moon.fill, briefcase.fill, person.fill, bed.double.fill, car.fill, figure.run, gamecontroller.fill, circle.hexagongrid, book.closed.fill, apple.intelligence, app.badge; private internal symbols person.lanyardcard.fill (work), apple.mindfulness, rocket.fill (gaming) via Image(internalSystemName:) (PRIVATE SF Symbol lookup); accent colours: DND (0.370,0.360,0.902), work (0.414,0.769,0.863), personal (0.748,0.354,0.948), sleep (0.341,0.384,0.980), driving (0.988,0.561,0.153), fitness (0.176,0.804,0.459), gaming (0.043,0.518,1.0), mindfulness (0.361,0.898,0.883), reading (1.0,0.622,0.044), reduceInterruptions (0.686,0.322,0.871), custom from ModeConfigurations.json tintColorName (fallback .indigo); inactive DND symbol moon.circle.fill. Music badge: mode.resolvedActiveIcon at badgeSize*0.5 semibold in accent (ContentView.swift:1655-1659).

### Animations

Expand on activation: reset without animation then next runloop .spring(response 0.35, dampingFraction 0.85) isExpanded=true (:336-357); wing widths .smooth(0.3), label visibility .smooth(0.3) (:282,313); toast collapse after 1800 ms (ToastTiming.activeDisplay) .smooth(0.32); deactivation: .spring(0.3, 0.9) expand, .smooth(0.2) show inactive icon, persistent: .interpolatingSpring(stiffness 220, damping 12) scale 1.2 → after 450 ms .interpolatingSpring(180, 18) back + hide inactive icon .smooth(0.2); collapse after 320 ms (persistent) or 1500 ms (toast) .smooth(0.32); cleanup 650 ms (:417-477). Manager toggles isDoNotDisturbActive under .smooth(0.25) (DoNotDisturbManager.swift:173,257).

### State and timing

Published: isDoNotDisturbActive, currentFocusModeName, currentFocusModeIdentifier, focusToastTrigger (UUID, fires when mode switches while active), isFocusToastDismissing, monitoringMode. The standalone view is mounted while (isDoNotDisturbActive || isFocusToastDismissing).

### Data sources and APIs

DoNotDisturbManager (managers/DoNotDisturbManager.swift, 1514 lines): DistributedNotificationCenter observers for PRIVATE names "_NSDoNotDisturbEnabledNotification" / "_NSDoNotDisturbDisabledNotification" with .deliverImmediately (:91-105,519-522) and metadata extraction from the notification object (private DNDMode object selectors) (:389-515,990-1110). Two monitoring modes (focusMonitoringMode): .withoutDevTools (default) → DispatchSourceTimer polls ~/Library/DoNotDisturb/DB/Assertions.json every 2 s (leeway 250 ms, first after 1 s), active = storeAssertionRecords non-empty, skipped for 4 s after a notification, requires Full Disk Access (:584-667); .useDevTools → `/usr/bin/log stream --no-backtrace --style compact --level info --predicate 'process == "duetexpertd" AND eventMessage CONTAINS "semanticModeIdentifier"'` (:1127-1185) plus initial `log show --last 5m|1h|24h --debug` (:543-582). Names/icons/tints for custom modes read from ~/Library/DoNotDisturb/DB/ModeConfigurations.json (FDA) (:1412-1490). Verification task: 5 s after activation, every 3 s re-check assertions and clear if gone (:284-310). Metadata retained 2 s after OFF for the toast (:338-345); isFocusToastDismissing true for 2.5 s when focusIndicatorNonPersistent (:352-366). Started at launch when enableDoNotDisturbDetection (DynamicIslandApp.swift:766-768). REA: _OBJC_CLASS_$_NSDistributedNotificationCenter and _OBJC_CLASS_$_NSTask imported; DoNotDisturbManager class present in dispatch.json.

### Settings

enableDoNotDisturbDetection=true; focusMonitoringMode=.withoutDevTools (withoutDevTools|useDevTools); showDoNotDisturbIndicator=true; showDoNotDisturbLabel=true; focusIndicatorNonPersistent=false.

### Implementation notes

No public API exposes Focus state on macOS. Options for NotchIsland: the same undocumented distributed notifications (observed stable since macOS 12) + Assertions.json polling behind an FDA prompt; or INFocusStatusCenter (requires the com.apple.developer.focus-status entitlement — not available to generic apps). ~900 lines in Atoll; a lean version ~300.

### Key files

- `DynamicIsland/managers/DoNotDisturbManager.swift`
- `DynamicIsland/components/Focus/DoNotDisturbLiveActivity.swift`
- `DynamicIsland/extensions/Image+InternalSystemName.swift`

## Download live activity

### Behaviour

When a browser starts a download into ~/Downloads (Chromium .crdownload, Safari .download bundle, Firefox .part, Opera .opdownload), the closed notch widens: an accent-tinted arrow.down.circle.fill badge on the left, a 40 pt wider black centre, and on the right an indeterminate linear progress bar (or a spinning 16 pt ring) plus optional live speed ("1.2 MB/s"). When all downloads finish, the right side shows a green checkmark for 2 s then collapses; a cancelled download collapses immediately. Downloads already in progress at launch are ignored.

### Layout

DownloadLiveActivity (components/Downloads/DownloadLiveActivity.swift:22-161): HStack(spacing 0){ left Color.clear.background{ if expanded ZStack{ RoundedRectangle(6, .continuous).fill(accent 0.14); Image("arrow.down.circle.fill").font(.system(size 14, semibold)).accent }.frame((h-12)x(h-12)) }.frame(width: expanded ? h - (hover ? 0 : 12) + gestureProgress/2 : 0, height: h - (hover ? 0 : 12)); Rectangle(.black).frame(width: closedWidth + (hover ? 8 : 0) + (isDownloading ? 40 : 0) + speedAllowance (58 when speed shown)); right Color.clear.background{ completed ? Image("checkmark.circle.fill").green.font(16 semibold).padding(.trailing 6) : HStack(spacing 6){ speed Text(.system(size 10, medium).monospacedDigit).secondary; indicatorStyle == .circle ? SpinningCircleDownloadView : ProgressView().progressViewStyle(.linear).tint(.accentColor).frame(width 40) }.padding(.trailing 6) }.frame(width: expanded ? max(60, h) + speedAllowance : 0, …) }.frame(height: h + (hover ? 8 : 0)). SpinningCircleDownloadView (SpinningCircleDownloadView.swift): 16x16, track stroke gray 0.3 lineWidth 3.5, accent trim 0...0.25 round cap rotating 360° .linear(1 s).repeatForever. Speed formatted with ByteCountFormatter(.file, KB/MB/GB adaptive) + "/s" (:35-59).

### Animations

isExpanded .smooth(duration 0.35) on appear and when isDownloading changes (:150-159); centre/right widths .smooth(0.25) on speedAllowance; speed text .smooth(0.2) with .opacity transition; insertion into the notch chain uses .blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)) (ContentView.swift:1147); manager state changes under withAnimation(.smooth).

### State and timing

isDownloading, isDownloadCompleted, downloadSpeed. Sessions (monitorSession/speedSession) guard against stale async scans. Toggling the listener off mid-download closes the view immediately.

### Data sources and APIs

DownloadManager (managers/DownloadManager.swift, @Observable-style with private(set) vars): FileManager Downloads URL; DispatchSource.makeFileSystemObjectSource(fd: open(path, O_EVTONLY), eventMask [.write, .rename, .delete, .attrib]) on a utility queue (:167-210); scan lists names + modification dates of non-empty files (:396-431); PartialDownload extensions ["crdownload","download","opdownload","part"] and destination mapping; completion decided when no partial remains: completed if destination exists with a newer stamp than when the partial appeared (:433-507). Speed: Timer 1 s (speedSampleInterval) summing allocated bytes of partials (Safari bundles walked recursively), EMA smoothing 0.4, <1 B/s hidden (:226-292,388-389). coordinator.toggleExpandingView(type: .download, value 0) on start and on close (the coordinator never auto-hides .download) (:558-612). Completion holds the view 2.0 s via Timer (:572). Requires NSDownloadsFolderUsageDescription (plist confirms) — first access triggers the TCC prompt (:534-537). Public API only.

### Settings

enableDownloadListener=true; enableSafariDownloads=true (not referenced in manager logic read); selectedDownloadIndicatorStyle=.progress ("Progress"|"Percentage"|"Circle"; percentage falls through to linear bar); showDownloadSpeed=false; selectedDownloadIconStyle=.onlyAppIcon ("Only app icon"|"Only download icon"|"Icon and app icon"; unused by this view).

### Implementation notes

Public API; ~300 lines. Note the app is unsandboxed; a sandboxed NotchIsland needs the Downloads read-only entitlement.

### Key files

- `DynamicIsland/managers/DownloadManager.swift`
- `DynamicIsland/components/Downloads/DownloadLiveActivity.swift`
- `DynamicIsland/components/Downloads/SpinningCircleDownloadView.swift`
- `DynamicIsland/enums/generic.swift`

## Network connectivity HUD (Wi-Fi / Personal Hotspot / No Internet)

### Behaviour

Joining or switching a Wi-Fi network shows, for 3.5 s, a wide closed-notch row: green wifi (or personalhotspot) glyph on the left and, right-aligned, "Wi-Fi connected"/"Hotspot connected" over the network name. Losing all connectivity shows a taller card ("No Internet Connection" / "Connect to Wi-Fi, Ethernet, or Personal Hotspot." with an animated antenna) with OK and Settings capsule buttons; it auto-dismisses after 8 s or on OK, and is not shown again until connectivity returns. The HUD stays centred on the physical notch (no menu-bar clearance offset) and takes precedence over everything else.

### Layout

NetworkConnectivityHUDMetrics (components/Network/NetworkConnectivityHUD.swift:17-46): presented when notch closed && state visible && !hideOnClosed && !locked; size: noConnection → (closedWidth + 210) x (effectiveClosedNotchHeight + 125); wifi/hotspot → max(closedWidth + 220, 450) x closedNotchSize.height. Accent Color(red 0.36, green 0.88, blue 0.42) (:55). noConnectionContent (:84-144): VStack(spacing 0){ Spacer(minLength max(h + 2, 30)); HStack(spacing 14){ ZStack{ antenna.radiowaves.left.and.right gray 0.62; same symbol accent with .symbolEffect(.variableColor.iterative.reversing, options: .repeating.speed(0.82)) }.font(.system(size 31, medium)).monochrome.frame(width 48); VStack(.leading, spacing 3){ Text("No Internet Connection").font(15 bold).white; Text("Connect to Wi-Fi, Ethernet, or Personal Hotspot.").font(11 semibold).secondary.minScale 0.75 } }.padding(.horizontal 24); Spacer(minLength 12); HStack(spacing 8){ button("OK", fg white, bg white 0.13); button("Settings", fg (0.28,0.58,1.0), bg (0.08,0.16,0.27)) }.padding(.horizontal 18).padding(.bottom 14) }; buttons Text .font(15 bold).frame(maxWidth .infinity, minHeight 35).background.clipShape(Capsule()) (:196-211). connectedNetworkContent (:146-194): wingWidth = (totalWidth - closedWidth)/2; HStack(spacing 0){ Image(wifi|personalhotspot).font(20 semibold).accent.padding(.leading 18).frame(wingWidth x closedHeight, .leading); Color.clear.frame(closedWidth x closedHeight); VStack(.trailing, spacing 1){ Text("Wi-Fi connected"/"Hotspot connected").font(9 medium).secondary; Text(name).font(12.5 semibold).white.minScale 0.82 }.padding(.trailing 18).frame(wingWidth x closedHeight, .trailing) }.

### Animations

HUD .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top))) (:66); antenna variableColor symbol effect; durations: connected 3.5 s, no-connection 8 s (NetworkConnectivityManager.swift:221,245). The notch window is resized to the HUD size (dynamicNotchSize/calculateRequiredNotchSize first branch).

### State and timing

ConnectivityHUDState: hidden | noConnection | wifi(name) | hotspot(name); hideWorkItem cancelled/rescheduled per show.

### Data sources and APIs

NWPathMonitor (Network framework, public) on a utility queue: satisfied, usesInterfaceType(.wifi), hotspot = isExpensive && !isConstrained (:66-89); CoreWLAN CWWiFiClient.shared() delegate for .ssidDidChange/.linkDidChange and interface().ssid() (public, SSID requires Location permission on recent macOS) with fallback `/usr/sbin/networksetup -getairportnetwork <if>` (1 s timeout, 1.5 s cache) (:248-311); Settings deep links x-apple.systempreferences:com.apple.Network-Settings.extension / com.apple.preference.network (:111-123). Announce rules (:143-211): first path update never announces; announce Wi-Fi when previously unsatisfied, previously non-Wi-Fi, hotspot flag changed, or SSID changed; no-connection shown once until dismissed/reconnected. REA caveat: CoreWLAN.framework is not in the 2.3.3 binary's LC_LOAD_DYLIB list and NetworkConnectivityManager is absent from dispatch.json — this feature may post-date the installed build (see unknowns).

### Settings

None (no Defaults keys; always on when monitoring starts at launch, DynamicIslandApp.swift:773).

### Implementation notes

Public API; ~350 lines. SSID access needs Location (NSLocationWhenInUseUsageDescription present in Atoll's plist).

### Key files

- `DynamicIsland/managers/NetworkConnectivityManager.swift`
- `DynamicIsland/components/Network/NetworkConnectivityHUD.swift`

## Bluetooth audio device connection HUD and AirPods listening-mode HUD

### Behaviour

When AirPods/Beats/other Bluetooth audio devices connect, the inline HUD shows the device symbol (or a looping 3D movie icon) with the device name and its battery as a ring or bar (+ optional percentage) for 2.5 s; the volume HUD is suppressed for 1.5 s so a volume write on connect does not fight it. If battery is not yet known it waits up to 1.8 s (polling every 0.3 s) before showing without battery. Changing AirPods listening mode (ANC / Transparency / Adaptive / Conversation Awareness / Off) shows the mode glyph + mode name for 2.5 s.

### Layout

Rendered by InlineHUD (see that feature) with type .bluetoothAudio: value = battery/100 (0 when unknown) and icon = deviceType.sfSymbol; listening-mode events use value = -1 and icon = mode.sfSymbol. BluetoothAudioDeviceType.sfSymbol (BluetoothAudioManager.swift:2751-2778): airpods, airpods.gen3, airpods.gen4, airpods.pro (Pro & Pro 3), airpodsmax, beats.headphones (beats/studio/solo), headphones, hifispeaker.fill, bluetooth.circle.fill. inlineHUDAnimationURL (:2819-2860) resolves BluetoothHUDAnimations/<caseName>.mov in the bundle (validated as a real movie, memoised). AirPodsListeningMode (:2558-2610) displayName/sfSymbol: noiseCancellation "Noise Cancellation" ear.badge.waveform; transparency "Transparency" ear; adaptive "Adaptive Audio" waveform; conversationAwareness "Conversation Awareness" person.wave.2; off "Off" airpods.pro; fromHUDSymbol also accepts "airpods.mode.*" names.

### Animations

Coordinator sneak animation (.smooth 0.3) and InlineHUD indicator animations (.smooth 0.18). HUD duration 2.5 s (:1956,2015); activeListeningModeEvent cleared after 2.7 s (:2024).

### State and timing

Published: lastConnectedDevice, connectedDevices, isBluetoothAudioConnected, activeListeningModeEvent, batteryStatus (refreshed every 20 s). hudBatteryWaitInterval 0.3 s, hudBatteryWaitTimeout 1.8 s (:103-104).

### Data sources and APIs

IOBluetooth (public): IOBluetoothHostController.default()?.powerState, IOBluetoothDevice.pairedDevices(), isConnected, SDP UUIDs 0x110B Audio Sink / 0x1108 Headset / 0x111E Handsfree to classify audio devices (:262-330,543-566); PRIVATE distributed notification names "IOBluetoothDeviceConnectedNotification"/"IOBluetoothDeviceDisconnectedNotification" (:164-190) plus a polling timer; device type from Apple vendor 0x05AC product-ID map (:47-64: 0x2002/0x200F AirPods, 0x2013 Gen3, 0x2019/0x201B Gen4, 0x200A/0x201F Max, 0x200E/0x2014/0x2024 Pro, 0x2027 Pro 3, 0x2017/0x2009 Beats Studio, 0x2006/0x200C Beats Solo) or name heuristics. Battery: IORegistry "BatteryPercent" (IORegistryEntryCreateCFProperty), /Library/Preferences/com.apple.Bluetooth defaults (BatteryPercent*, CoreBluetoothCache), `system_profiler` (SPBluetoothDataType, cached 30 s), `pmset -g accps` fallback (5 s cooldown), CoreBluetooth battery service via BluetoothLEBatteryReader (CBCentralManager; REA confirms class import; NSBluetoothAlwaysUsageDescription present) (:584-1760,2400-2526). Listening mode (PRIVATE/fragile): DistributedNotificationCenter names com.apple.AudioAccessory.prefsChanged/daemonStarted/cdMsgNotification, com.apple.bluetooth.status, com.apple.Bluetooth.* , com.apple.controlcenter.airpodspro.settingschanged (:110-126); Darwin notifications; `/usr/bin/log stream --predicate '(process == "audioaccessoryd" OR "bluetoothd" OR "heard") AND eventMessage CONTAINS[c] "LsnM" …'` (:2180-2240); private selectors on IOBluetoothDevice (listeningMode, LsnM, noiseControlMode, …) (:2067-2093); `ioreg -r -l -w 0` scrape (:2106-2130); private int values 0 off, 1 ANC, 2 transparency, 3 adaptive, 4 conversation (:2656-2671). Event-driven refresh debounced 180 ms; presentation debounced 350 ms; dedupe per address (:1963-2004). HUDSuppressionCoordinator.suppressVolumeHUD(1.5) before each HUD (:1950,2009). SystemChangesObserver uses activeDeviceIconSymbol() for the Vertical HUD icon (headphones.slash when muted). REA: BluetoothAudioManager has 155 dispatch.json hits; _OBJC_CLASS_$_IOBluetoothDevice and _OBJC_CLASS_$_CBCentralManager imported.

### Settings

showBluetoothDeviceConnections=true; showAirPodsListeningModeChanges=true; useCircularBluetoothBatteryIndicator=true; showBluetoothBatteryPercentageText=false; showBluetoothDeviceNameMarquee=false; useBluetoothHUD3DIcon=true; useColorCodedBatteryDisplay=true; useSmoothColorGradient=true.

### Dependencies

None beyond system frameworks.

### Implementation notes

Public subset for NotchIsland: IOBluetooth paired-device polling + CoreAudio default-output route change as the connect trigger, battery via IORegistry BatteryPercent (public IOKit). Listening-mode detection has no public API; treat as optional/experimental. ~3,000 lines in Atoll; minimal ~400.

### Key files

- `DynamicIsland/managers/BluetoothAudioManager.swift`
- `DynamicIsland/components/Live activities/InlineHUD.swift`
- `DynamicIsland/BluetoothHUDAnimations/`

## Caps Lock indicator

### Behaviour

Turning Caps Lock on slides a capslock.fill glyph into the left wing of the closed notch (white by default, optionally green or accent) and optionally the text "Caps Lock" on the right; it stays until Caps Lock turns off, then slides out to the right. When music is playing it becomes a badge on the album art (and the label replaces the spectrum when enabled).

### Layout

InlineHUD(type: .capsLock, value: 1.0) — glyph 20x15 frame tinted capsLockIndicatorTintMode.color; infoWidth 56/48 (no label) or 92; trailing 88/76 with label ("Caps Lock" .subheadline medium tinted, trailing aligned) else 0 (InlineHUD.swift:154-159,199-204,290-295,350-361). Music pairing: badge Image("capslock.fill").font(.system(size: badgeSize*0.5, semibold)) tinted (ContentView.swift:1665-1668); right wing MusicCapsLockLabelView Text("Caps Lock").font(.system(size 13, semibold)) tinted, trailing, .contentTransition(.opacity) (:3231-3242); wing width with label = max(base, max(centerBase*0.4, base + 12)) (:1562-1563).

### Animations

Manager flips isCapsLockActive under .spring(response 0.32, dampingFraction 0.85) (CapsLockManager.swift:34,70); ContentView transition .move(edge: .trailing).combined(with: .opacity) (ContentView.swift:1128-1134); sneak peek shown with duration .infinity (no auto-hide) and explicitly hidden with status false (CapsLockManager.swift:79-97).

### State and timing

Two render paths: the sneak peek (infinite) and, as a fallback when the sneak peek is replaced by another HUD, the persistent branch in the chain keyed on capsLockManager.isCapsLockActive (ContentView.swift:1132-1134).

### Data sources and APIs

NSEvent.addLocalMonitorForEvents(.flagsChanged) + addGlobalMonitorForEvents(.flagsChanged), modifierFlags.contains(.capsLock); initial state from NSEvent.modifierFlags (public; global monitor needs Accessibility/Input Monitoring to receive events from other apps) (CapsLockManager.swift:36-52). REA: CapsLockManager present (14 hits).

### Settings

enableCapsLockIndicator=true; capsLockIndicatorTintMode=.white (green|accent|white; legacy capsLockIndicatorUseGreenColor=false migrated via didMigrateCapsLockTintMode); showCapsLockLabel=false.

### Implementation notes

Public API; ~100 lines manager + reuse InlineHUD.

### Key files

- `DynamicIsland/managers/CapsLockManager.swift`
- `DynamicIsland/components/Live activities/InlineHUD.swift`

## Reminder / calendar live activity

### Behaviour

Five minutes (configurable) before a calendar event or reminder, the closed notch shows a calendar.badge.clock glyph in the calendar's colour on the left and a countdown on the right: a progress ring (default), a mm:ss digital countdown, or "in N min". A sneak peek with the event title and time is shown when it first appears (5 s) and again (critical, red, calendar.badge.exclamationmark) when the remaining time falls inside the sneak-peek window. The activity ends at the event start and advances to the next event. With music playing it becomes a clock badge on the artwork with the countdown in the right wing.

### Layout

ReminderLiveActivity (components/Calendar/ReminderLiveActivity.swift:30-233): HStack(spacing 0){ Color.clear.frame(leftWingWidth x h).background(.leading){ Image(iconName).font(.system(size 16, semibold)).accent.frame(iconDiameter).padding(.leading 8) }; Rectangle(.black).frame(closedWidth x h); Color.clear.frame(rightWingWidth x h).background(.trailing){ right.padding(.trailing 8) } }.frame(height h). wingPadding 16; iconDiameter = max(h - 8, 26); leftWingWidth = 16 + iconDiameter; ring: diameter max(min(h-12, 22), 16), track white 0.15 lineWidth 3, progress accent round cap rotated -90°; digital Text .system(size 16, semibold, monospaced) width max(text + 18, 76); minutes Text .system(size 13, semibold) width max(text + 18, 88); rightWingWidth = 16 + ring/digital/minutes width (:36-41,100-200). Accent = Color(nsColor: calendar.color).ensureMinimumBrightness(0.7), red when critical (remaining ≤ reminderSneakPeekDuration) (:158-163,227-232). Music pairing supplement (ContentView.swift:3150-3229): ring track white 0.15 lineWidth 3 within frame max(d+4, 26) x notchHeight; digital .system(15, semibold, monospaced) width max(text+18, 76); minutes .system(13, semibold) width max(text+18, 88); wing width = max(base, 16 + …) (:1603-1618); badge Image("clock") size*0.55 semibold accent (:1650-1654). Standard sneak peek text: "<title> • now" inside window, else "<title> • in N min • HH:mm" (:1334-1353).

### Animations

View .transition(.opacity.combined(with: .move(edge: .bottom))) (:46); ring progress and digital text .animation(.smooth(duration 0.25)) with .contentTransition(.numericText()) (:111,122-123); 1 s ticker drives currentDate (ReminderLiveActivityManager.swift:423-441).

### State and timing

Published activeReminder, currentDate (1 s tick while active), upcomingEntries, activeWindowReminders, lockScreenSnapshot. isActive = activeReminder != nil.

### Data sources and APIs

EventKit via CalendarManager.shared.events (EventModel: start, title, calendar.color, type .reminder(completed)) — public, needs NSCalendarsFullAccessUsageDescription/NSRemindersFullAccessUsageDescription (both in plist; EKEventStore import confirmed by REA). Manager (ReminderLiveActivityManager.swift): builds entries with triggerDate = start - leadTime (leadMinutes ≥ 1), sorted; debounces calendar updates 0.35 s and settings 0.2 s; schedules an evaluation Task at the next trigger; on trigger sets activeReminder and calls coordinator.toggleSneakPeek(type: .reminder, duration: reminderSneakPeekDuration, icon: standardIconName) (:495-510); critical sneak once when remaining ≤ window with duration min(window, remaining - 2) (:512-532); pauses during lock with 5 s resume cooldown (:256-320). Also feeds lockScreenSnapshot and activeWindowReminders (minimalistic open-notch rows: row 30 pt, spacing 8, top 14, bottom 10, :38-42,632-638).

### Settings

enableReminderLiveActivity=true; reminderPresentationStyle=.ringCountdown ("Ring"|"Digital"|"Minutes"); reminderLeadTime=5 (minutes); reminderSneakPeekDuration=5 (seconds, also the critical window); hideAllDayEvents; hideCompletedReminders=true.

### Implementation notes

Public API; ~700 lines manager (much is lock-screen/minimalistic), ~230 view.

### Key files

- `DynamicIsland/managers/ReminderLiveActivityManager.swift`
- `DynamicIsland/components/Calendar/ReminderLiveActivity.swift`
- `DynamicIsland/managers/CalendarManager.swift`

## Idle animation (Lottie "face") on the closed notch

### Behaviour

When nothing is playing and `showNotHumanFace` is enabled, a small looping Lottie animation (bundled: Dog waiting, Moody Dog, Orange Cat Peeping, Reindeer; or user-imported JSON / remote URL) peeks out of the right wing of the closed notch, sized to the notch height; users can scale/offset/rotate/crop it and set loop mode in settings.

### Layout

DynamicIslandFaceAnimation (ContentView.swift:1376-1390): sideSize = max(0, h - 12); HStack{ Rectangle(.clear).frame(sideSize x sideSize); Rectangle(.black).frame(width: closedNotchSize.width - 20); IdleAnimationView().frame(sideSize x sideSize) }.frame(height: h + (hover ? 8 : 0)). IdleAnimationView (components/IdleAnimationView.swift): LottieView(state: LUStateData(type: .loadedFrom(url), speed, loopMode)).frame(width: cropWidth*scale, height: cropHeight*scale).offset(offsetX, offsetY).rotationEffect(rotation).opacity.padding(.bottom, paddingBottom).clipped(), re-created via .id when the override changes. AnimationTransformConfig defaults (Constants.swift:100-113): scale 1, offset 0/0, cropWidth 30, cropHeight 20, rotation 0, opacity 1, paddingBottom 0, expandWithAnimation false, loopMode .loop (loop|playOnce|autoReverse). LottieAnimationView (components/Music/LottieAnimationView.swift) is the music-visualizer fallback (remote https://assets9.lottiefiles.com/packages/lf20_mniampqn.json or selectedVisualizer).

### Animations

Lottie playback at `speed` (default 1.0) with loop mode; swap .animation(.interactiveSpring, value: isPlayerIdle) (ContentView.swift:1170).

### State and timing

Shown only when !expandingView.show && closed && !isPlaying && isPlayerIdle && !hideOnClosed.

### Data sources and APIs

airbnb Lottie (lottie-spm) + LottieUI wrappers (public packages); IdleAnimationManager stores imports in ~/Library/Application Support/DynamicIsland/IdleAnimations/<UUID>.json, validates JSON, keeps remote URLs unresolved (IdleAnimationManager.swift:29-240). REA: Lottie.framework embedded (@rpath/Lottie.framework), 48 'Lottie' hits, resources 'Dog waiting' and 'Orange Cat Peeping' present in bundle inventory.

### Settings

showNotHumanFace=false; customIdleAnimations=[] (seeded with 4 bundled on first launch); selectedIdleAnimation=nil (→ first bundled); animationTransformOverrides=[:] keyed by animation UUID string.

### Dependencies

airbnb/lottie-spm (Apache-2.0); jasudev/LottieUI (MIT).

### Implementation notes

Requires the Lottie SwiftPM dependency (Apache-2.0); LottieUI is MIT. ~400 lines incl. import/transform UI.

### Key files

- `DynamicIsland/managers/IdleAnimationManager.swift`
- `DynamicIsland/components/IdleAnimationView.swift`
- `DynamicIsland/components/Music/LottieAnimationView.swift`
- `DynamicIsland/models/Constants.swift`
- `LottieAnimations/`

## Music-paired secondary live activity (badge + right wing) and shared primitives (MarqueeText, PulsingModifier)

### Behaviour

While music shows on the closed notch (album art left, spectrum right), one other activity can ride along: a small circular black badge with the activity's glyph overlaps the bottom-right of the album art, and the right wing swaps the spectrum for a timer ring/countdown, reminder ring/countdown, "Caps Lock" label, extension content, or a shelf file count; recording/focus/caps-lock(no label) keep the spectrum (recording with a 6 pt inset). Priority: timer > reminder > recording > focus > caps lock > extension > shelf. Long texts scroll as a marquee at 30 pt/s after a pause.

### Layout

MusicLiveActivity (ContentView.swift:1393-1518): artwork square artworkSize = min(h-12, wingBaseWidth) with corner radius 4 (MusicPlayerImageSizes.cornerRadiusInset.closed; /3 for wide art) and matchedGeometryEffect "albumArt"; badge ZStack{ Circle().fill(.black); glyph }.frame(badgeSize) where badgeSize = max(13, artworkSize*0.36), offset (badgeSize*0.2, badgeSize*0.25) from bottom-trailing, shadow black 0.35 radius 3 y 1, transition opacity+scale (:1417-1419,1639-1703); glyph sizes: timer "timer" 0.55 semibold timerAccent; reminder "clock" 0.55; focus icon 0.5 accent; recording red circle 0.45 pulsing; capsLock 0.5; shelf "tray.and.arrow.down.fill" 0.5 white. Right wing widths (:1554-1636): timer countdown max(base, 18 + ring(30|0) + spacing(8|0) + countdownFrameWidth) where countdownFrameWidth = max(monospaced 13 semibold text + 16, 72); timer no-countdown: progress ring factor 0.46/+18, bar 0.52/+24, name 0.38/+12 via scaledWingWidth = max(base, max(center*factor, base+extra)); reminder 16 + ring/digital/minutes width; capsLock label 0.4/+12; recording min(base, max(38, min(base*0.6, min(base-6, 52)))); focus/shelf base; extension ExtensionLayoutMetrics. Timer supplement (:3033-3148): ring diameter max(min(h-4, 26), 20) track white 0.18 lineWidth 3 inside frame max(d+4, 30); countdown .system(13, semibold, monospaced) white (red overtime) frame width max(text+16, 72) trailing + optional bar 4 pt tall (track white 0.15, accent fill); standalone bar width 68; name .system(12, medium) width max(text+14, 64). Spectrum: Rectangle 50 pt wide filled with avgColor/gray spectrogramGradient masked by AudioVisualizerView(width visualizerBarCount*4, height 12), matchedGeometryEffect "spectrum"; hover play/pause overlay RoundedRectangle(8) black 0.24 + 16 pt semibold symbol (:1753-1804). MarqueeText (MarqueeTextView.swift:40-157): two copies in HStack(spacing: 20 = loopSpacing), measured via PreferenceKey, frame(width: frameWidth, .leading).clipped().frame(height: pointSize*1.3); scrolls only if textWidth > frameWidth. MusicExplicitBadge: 'E' .system(size 9, bold, rounded) white 0.92 on white 0.18 RoundedRectangle(max(4, h*0.28)), height 14 (:159-183).

### Animations

Secondary swap .animation(.smooth(duration 0.25), value: secondary?.id) and .contentTransition(.symbolEffect(.replace)) on badge/right wing (:1440,1513,1517); hover overlay .smooth(0.16), play state .smooth(0.2); timer/reminder progress .smooth(0.25) with numericText; MarqueeText loop: wait minDuration (default 3 s; 0.2-1.0 in HUDs), then .linear(duration: textWidth/30) to offset -(textWidth + 20), snap back with .animation(.none), repeat (MarqueeTextView.swift:128-156); PulsingModifier .easeInOut(0.8).repeatForever(autoreverses) scale 1.2 / opacity 0.7.

### State and timing

MusicSecondaryLiveActivity enum (:3004-3031) with stable ids drive transitions; expansionMatchesSecondary lets a matching expandingView type coexist with music.

### Data sources and APIs

resolveMusicSecondaryLiveActivity (ContentView.swift:1520-1552) reads TimerManager, ReminderLiveActivityManager, ScreenRecordingManager, DoNotDisturbManager (FocusModeType.resolve), CapsLockManager, ExtensionLiveActivityManager, ShelfStateViewModel. Public SwiftUI only.

### Settings

timerShowsCountdown, timerShowsProgress, timerProgressStyle (.ring|.bar), timerIconColorMode (.adaptive|.solid), timerSolidColor, reminderPresentationStyle, showCapsLockLabel, capsLockIndicatorTintMode, visualizerBarCount, coloredSpectrogram, showSongMetadataInClosedNotch.

### Implementation notes

Build MarqueeText with a TimelineView or CADisplayLink instead of nested asyncAfter for Swift 6 safety. ~600 lines.

### Key files

- `DynamicIsland/ContentView.swift`
- `DynamicIsland/components/Live activities/MarqueeTextView.swift`
- `DynamicIsland/components/Live activities/PulsingModifier.swift`

## Unknowns

- TimerLiveActivity (components/Timer/TimerLiveActivity.swift, 542 lines) and TimerManager were not read (Timer subsystem); the SneakContentType .timer paths (10 s duration, inline timer centre text at ContentView.swift:1469-1484, InlineHUD .timer case) have no toggleSneakPeek/toggleExpandingView caller in TimerManager/TimerLifecycle/SystemTimerBridge in this tree — likely legacy or driven elsewhere.
- Extension live activities (ExtensionLiveActivityManager, AtollExtensionKit payloads, ExtensionLiveActivityStandaloneView, ExtensionMusicWingView, ExtensionLayoutMetrics) and LocalSendLiveActivity / ShelfInlineLiveActivity appear in the priority chain but belong to other subsystems and were not specced.
- Lock-screen expanding type (.lockScreen, LockScreenManager, LockScreenLiveActivityWindowManager, unlockRemovalDelay value) and the lock-screen music HUD/volume capsule are out of scope; only the hand-over of native HUD suppression on lock was covered.
- NotchShape(topCornerRadius:bottomCornerRadius:) and DynamicIslandPillShape path geometry (components/Notch/NotchShape.swift, DynamicIslandPillShape.swift) used to clip the battery/recording HUDs were not read (shell subsystem); closed radii 6/14 and pill radius max(h/2,16)/24 are known.
- Battery standard-style HUD: the view asks for width +150 (low) / +140 (full) but the notch/window sizing uses +100 / +80 — behaviour on device (clipping vs. sizing) not verified.
- SystemOSDManager PID lookup: source uses proc_listpids/proc_name/proc_pidinfo, but REA imports list only _proc_pidinfo (no _proc_listpids/_proc_name) — the shipped 2.3.3 binary may still shell out to pgrep for the helper PID; the suppression mechanism itself (killall -STOP/-CONT, launchctl kickstart) cannot be confirmed from REA strings (artifact.json contains only bundle inventory, not binary strings).
- CoreWLAN.framework is absent from the 2.3.3 binary's LC_LOAD_DYLIB dependencies and NetworkConnectivityManager/VerticalHUDWindowManager/SystemHUDManager/SystemOSDManager names are absent from dispatch.json (0 hits) — Network connectivity HUD may be newer than the installed build; others may simply be non-ObjC-visible Swift types. Verify on device.
- BluetoothAudioManager polling interval (startPollingForChanges) and the BluetoothLEBatteryReader timeoutInterval were not read; exact device-connected detection latency unknown.
- AirPods listening-mode detection relies on undocumented log messages/selectors; which path actually fires on current macOS is unknown without runtime testing.
- SystemHUD 'systemHUDSensitivity' (default 5) Defaults key exists but no consumer was found in the files read.
- HUDSuppressionCoordinator is only used by Bluetooth HUDs; whether BetterDisplay/Lunar sneak peeks (third-party DDC) use different durations/icons was not read (BetterDisplayManager.swift:298/322, LunarManager.swift:360/383).
- Image(internalSystemName:) (extensions/Image+InternalSystemName.swift) used for private SF Symbols (person.lanyardcard.fill, apple.mindfulness, rocket.fill) — implementation and fallback behaviour not read.
- SkyLightWindow (Lakr233) exact license and the specific CGS calls it makes were not inspected beyond REA imports (_CGSSpaceCreate, _CGSSpaceDestroy, _CGSSpaceSetAbsoluteLevel, _CGSAddWindowsToSpaces, __CGSDefaultConnection).
- DynamicIslandHeader battery placement details (lines 334-360) only partially read: DynamicIslandBatteryView(batteryWidth: 30) in standard mode, MinimalisticBatteryView in minimalistic non-pill mode; surrounding header layout belongs to the open-notch subsystem.
- Whether the AudioVisualizerView spectrum mask animates while paused and the Pow package usage (EmergeTools/Pow 1.0.5 in Package.resolved) were not investigated; Pow is not referenced by the files read in this subsystem.

## Critic pass

Missing from the spec:

- TRUNCATION NOTE: the spec text handed to me ends inside 'Screen recording live activity › animations'. Everything listed below from item 'DND' onward is what the source contains and that I could NOT confirm is present in the spec; items before that are verified gaps in the visible part.
- MarqueeText mechanics are not specified (components/Live activities/MarqueeTextView.swift): loopSpacing 20 (:50), init defaults font .body / minDuration 3.0 / frameWidth 200 (:66), scrolls only when measured text width > frameWidth (:76-78), 0.1 s start delay (:120), initial pause = minDuration then .linear move at ~30 pt/s (duration = textWidth/30, :132-140) to -(textWidth+20), instant snap back and repeat (:144-154); frame height = textSize.height*1.3 (:111). MusicTitleMarqueeView / MusicExplicitBadge (:159-311, badge radius max(4,h*0.28), bg white 0.18) live in the same file.
- SystemEventIndicatorModifier has a .bluetoothAudio branch the spec omits (SystemEventIndicatorModifier.swift:74-85, :102-112): listening-mode symbol (value<0) + Text(mode.displayName).font(.caption).medium.white, otherwise ProgressSection(colorMode: .battery). Also: colour-coding is force-disabled when progressBarStyle == .segmented (:322-331; InlineHUD.swift:397,404); glowing segment shadow colour uses accent.ensureMinimumBrightness(0.8) vs 0.7 for other active segments (:385-398).
- Hover/tap-to-open suppression tied to live activities is missing: hover does NOT open the notch while a sneak peek is visible on this screen, while the connectivity HUD is visible, or while the recording live activity is visible (ContentView.swift:2335-2340); taps are ignored while the connectivity HUD is visible or recordingOpenGestureLocked (:719-720, :2213, :2620-2622); the hover click monitor is not started while the recording activity is visible (:2312). Hover also fires a haptic when closed (:2330-2332), not only taps.
- Battery popover keeps the notch open via vm.isBatteryPopoverActive = showPopupMenu && isHoveringPopover (DynamicIslandBattery.swift:451-453). BatteryMenuView rows not listed: 'Battery Status' headline + 'NN%' (:296-304), 'Max Capacity: N%', 'Low Power Mode' (bolt.circle), 'Charging' (bolt.fill), 'Plugged In' (powerplug.fill), 'Time to Full Charge: N min' (clock), 'Charging on Hold: Desktop Mode' when !isCharging && isPluggedIn && level >= 80 (:306-334), VStack spacing 16/8, width 280.
- Open-notch header indicators belong to this subsystem but are absent: RecordingIndicator (6 pt red dot + 2 pt blurred glow, scale 1.2 / opacity 0.6↔1.0, .easeInOut(0.8).repeatForever, 30x30 slot) and FocusIndicator (black Capsule, focus-mode icon 12 pt semibold in FocusModeType.accentColor, 24x24) shown when the notch is open and the respective detection toggles are on (components/Notch/DynamicIslandHeader.swift:319-329; components/UI/RecordingIndicator.swift:26-59; components/UI/FocusIndicator.swift:25-35). RecordingIndicatorLarge / RecordingIndicatorSubtle (RecordingIndicator.swift:114-182) are unused. Header battery: minimalistic mode uses MinimalisticBatteryView(bodyWidth 28, bodyHeight 14) and hides it in Dynamic Island mode (DynamicIslandHeader.swift:338-345); standard header BatteryView width 30 (:354).
- Recording live activity details probably cut by truncation: screen-sharing frontmost-app list forcing compact presentation (bundle IDs com.apple.FaceTime, com.apple.ScreenSharing, com.cisco.webexmeetingsapp, com.hnc.Discord, com.microsoft.teams/teams2, com.skype.skype, com.tinyspeck.slackmacgap, us.zoom.xos + name tokens; ScreenRecordingManager.swift:42-75, observed via NSWorkspace didActivate/didTerminate :387-430); stop sequence = System Events ⌘⌃Esc (key code 53) → 120 ms → CGEvent key down/up (45 ms, 80 ms) on hid+session taps → 300 ms → System Events again (:116-181); waitForRecordingToStop 2×250 ms then 8×250 ms (:269-311); native `screencapture` kill ladder killall -INT/-TERM screencapture, -TERM screencaptureui, -TERM ScreenCaptureUI with 180 ms rechecks, only when `pgrep -x screencapture` succeeds (:313-373); failure state text 'Unable to stop recording. Use Command-Control-Escape or the macOS recording menu.' + NSSound.beep, cleared after 3 s (:499-513); duration Timer 1 s, format %d:%02d, reset 2 s after stop (:459-488, :546-551); isVisible fade .smooth(0.32)/.smooth(0.2) (RecordingLiveActivity.swift:57-66); enums RecordingHoverStyle default|inline and RecordingControlMode indicatorOnly|withStopButton (models/Constants.swift:563-594); the window is sized with makeRecordingHUDLayout(expanded: true), i.e. always for the hover-expanded size (DynamicIslandApp.swift:599-614). NOTE: strings 'recordingHoverStyle', 'recordingControlMode', 'Unable to stop recording' are absent from the 2.3.3 binary → the hover stop-button/expanded card is post-2.3.3; 2.3.3 ships only the compact indicator.
- DND / Focus live activity (components/Focus/DoNotDisturbLiveActivity.swift): row = HStack(spacing 0){ iconWing(iconWingWidth × wingHeight) | black Rectangle(centerSegmentWidth) | labelWing }.frame(width: center+icon+label, height: effectiveClosedNotchHeight) (:41-53); wingHeight = max(h-10, 20) (:89-91); minimalWingWidth = max(h-12, 24) (:113-115); center width pixel-aligned to backingScaleFactor (:65-72), collapses to closedWidth-(6+14) in toast mode when both wings are 0 (:117-130); label font .system(12, semibold, rounded) (:164-170); desiredLabelWidth = max(closedWidth*0.52, 136), ≥164 for DND, ≥ intrinsic+8 when not marqueeing (:132-145); marquee when intrinsic > width('Do Not Disturb') with minDuration 0.4 and frame max(48, labelWing-8) (:156-162, :291-299); icon 13 pt semibold in focus accent (:274-276); toast mode (focusIndicatorNonPersistent) labels 'On'/'Off', label wing max(intrinsic+26, minimalWing), linger 1800 ms active / 1500 ms inactive, collapse .smooth(0.32) (:36-39, :97-107, :466-477); persistent OFF animation: expand spring(0.3,0.9), showInactiveIcon .smooth(0.2), icon scale 1.2 interpolatingSpring(220,12), back to 1.0 after 450 ms interpolatingSpring(180,18), collapse after 320 ms, cleanup 650 ms (:417-464); ON expand spring(0.35,0.85) (:327, :350); inactive icon variants (moon.circle.fill, outline of internal symbol, rocket.circle.fill for gaming) (:227-256). Manager (managers/DoNotDisturbManager.swift): DistributedNotificationCenter '_NSDoNotDisturbEnabledNotification'/'_NSDoNotDisturbDisabledNotification' (:91-105, :519-522); mode .withoutDevTools polls ~/Library/DoNotDisturb/DB/Assertions.json every 2 s (1 s initial, 250 ms leeway) via DispatchSourceTimer, requires Full Disk Access, keys storeAssertionRecords / modeIdentifier / activityDisplayName (:584-667); 4 s notification cooldown (:59); state verification loop 5 s delay then every 3 s (:284-311); metadata cleared 2 s after OFF (:338-345); isFocusToastDismissing held 2.5 s (:352-365); mode .useDevTools runs `/usr/bin/log stream --style compact --level info --predicate 'process == "duetexpertd" AND eventMessage CONTAINS "semanticModeIdentifier"'` plus initial `log show --last 5m/1h/24h --debug` (:543-582, :1127-1143); custom-focus name/icon/colour from ~/Library/DoNotDisturb/DB/ModeConfigurations.json (:1413); 'Reduce Interruptions' shortened to 'Reduce Interr.' (:243); FocusModeType identifiers/displayNames/sfSymbols/internal symbols/accent RGB table (:672-784). Settings: enableDoNotDisturbDetection=true, focusMonitoringMode=.withoutDevTools, showDoNotDisturbIndicator=true, showDoNotDisturbLabel=true, focusIndicatorNonPersistent=false (Constants.swift:1476-1480).
- Privacy (camera/mic) live activity (components/Privacy/PrivacyLiveActivity.swift): HStack(spacing 0){ left Color.clear wing width (expanded && (recording || both)) ? h-(hover?0:12)+gp/2+20 : 0 | black Rectangle(closedWidth + (hover?8:0)) | right wing width expanded ? h-(hover?0:12)+gp/2+20 : 0 }, height h+(hover?8:0) (:37-101); layout rules: recording → red pulsator (RoundedRectangle 6 red 0.15 + 10 pt pulsing dot, (h-12)²) on left; both without recording → mic left, camera right; recording+both → mic+camera right (spacing 4) (:41-97); PrivacyIcon = SF 'video.fill' / 'mic.fill' 13 pt semibold in 24x24, camera #26CC41 (0.152,0.804,0.256), mic #FF9402 (1.0,0.584,0.010) (:122-139; PrivacyIndicatorIcon.swift:22-33); expand/collapse .smooth(0.4) (:102-117); isHovering/gestureProgress are local @State never updated (:26-27) so this row never grows on hover. PrivacyIndicatorIcon (orange radial glow pulsing 1.5 s) and PrivacyIndicatorContainer are settings-only, not used in the notch. Manager: IndicatorLayout 8-case enum (PrivacyIndicatorManager.swift:25-76); CameraMonitor = CMIO kCMIODevicePropertyDeviceIsRunningSomewhere listener (wildcard scope/element) on every CMIO device with input streams, OR'ed with AVCaptureDevice.isInUseByAnotherApplication (builtInWideAngleCamera + external), event-driven, no polling (CameraMonitor.swift:153-362); MicrophoneMonitor = CoreAudio kAudioDevicePropertyDeviceIsRunningSomewhere on the default input device only (no default-device-change tracking) (MicrophoneMonitor.swift:87-309); state changes under withAnimation(.smooth). Settings enableCameraDetection=true, enableMicrophoneDetection=true (Constants.swift:1483-1484). No NSMicrophoneUsageDescription in the shipped plist; camera entitlement present (REA plist.json/signature.json).
- Download live activity (components/Downloads/DownloadLiveActivity.swift): left capsule RoundedRectangle(6, continuous) tint 0.14 with 'arrow.down.circle.fill' 14 semibold, (h-12)², wing width expanded ? h-(hover?0:12)+gp/2 : 0 (:68-91); centre black width closedWidth + (hover?8:0) + (isDownloading ? 40 : 0) + speedAllowance 58 when speed shown (:49, :94-102); right wing width isExpanded ? max(60, h) + speedAllowance : 0, shows 'checkmark.circle.fill' green 16 semibold on completion, else optional speed text (.system(10, medium).monospacedDigit, ByteCountFormatter KB/MB/GB + '/s') and ProgressView(.linear).tint(.accentColor) 40 wide or SpinningCircleDownloadView (16 pt, lineWidth 3.5, trim 0.25, 1 s linear rotation) (:105-147; SpinningCircleDownloadView.swift:24-45); expand .smooth(0.35), speed changes .smooth(0.25/0.2); hover/gesture @State never updated (:26-27). Manager (managers/DownloadManager.swift): DispatchSource on ~/Downloads [.write,.rename,.delete,.attrib] (:179-209), partial extensions crdownload/download/opdownload/part (:35), files present at launch are ignored by name (:435-441, :457-462), expandingView .download opened on first active file (:554-563), completion shows checkmark then closes after 2.0 s (:565-592), cancelled downloads close immediately (:502-503, :594-613), speed sampled every 1 s with EMA 0.4, Safari .download bundles summed recursively (:388-389, :355-386). Settings enableDownloadListener=true, enableSafariDownloads=true, selectedDownloadIndicatorStyle=.progress ('Progress'|'Percentage'|'Circle'), showDownloadSpeed=false, selectedDownloadIconStyle=.onlyAppIcon (Constants.swift:1199-1203; enums/generic.swift:114-135) — percentage style and icon style are not consumed by the live activity. 'showDownloadSpeed' is absent from the 2.3.3 binary (post-2.3.3).
- Network connectivity HUD (components/Network/NetworkConnectivityHUD.swift, managers/NetworkConnectivityManager.swift): NOT in the shipped 2.3.3 binary (no CoreWLAN in LC_LOAD_DYLIB, no NetworkConnectivityManager class in dispatch.json, strings 'networksetup'/'CWWiFiClient'/'No Internet Connection'/'Wi-Fi connected' absent) — spec should mark it post-2.3.3. Source spec: NWPathMonitor + CWWiFiClient ssidDidChange/linkDidChange + `/usr/sbin/networksetup -getairportnetwork` fallback (1 s timeout, 1.5 s cache) (:43-56, :62-90, :250-311); hotspot = usesWiFi && isExpensive && !isConstrained (:73); announce only on change (:151-160); no-connection HUD size closed+210 × h+125, auto-dismiss 8 s (:34-38, :213-222), antenna.radiowaves.left.and.right 31 pt medium with .variableColor.iterative.reversing repeating speed 0.82, title 15 bold, subtitle 11 semibold, buttons 'OK' (white 0.13 bg) / 'Settings' (fg (0.28,0.58,1), bg (0.08,0.16,0.27)) 15 bold minHeight 35 capsule (:84-144, :196-211); wifi/hotspot HUD width max(closed+220, 450) × closedNotchSize.height, 3.5 s (:39-44, :224-246), icon wifi/personalhotspot 20 semibold accent (0.36,0.88,0.42), 'Wi-Fi connected'/'Hotspot connected' 9 medium secondary, name 12.5 semibold (:146-194); transition opacity+scale(0.97, anchor .top) (:66); presented only closed && !hideOnClosed && !locked (:13-24); disables menu-bar clearance offset and hover/tap open (ContentView.swift:1277-1283, :719, :2338).
- Bluetooth audio connect / AirPods HUD manager details (managers/BluetoothAudioManager.swift): DistributedNotificationCenter 'IOBluetoothDeviceConnectedNotification'/'IOBluetoothDeviceDisconnectedNotification' (:164-187) + 3 s polling of IOBluetoothDevice.pairedDevices() gated on IOBluetoothHostController powerState (:253-262); audio device = SDP UUIDs 0x110B / 0x1108 / 0x111E (:543-547); battery sources in order: IORegistry 'BatteryPercent*' by address/name, UserDefaults (com.apple.Bluetooth cache), pmset, system_profiler, CoreBluetooth 180F/2A19 LE read (:584-603, :1343, :1460, :1583, :2274-2300); connect HUD waits up to 1.8 s (poll 0.3 s) for a battery value, then shows duration 2.5 s, value = battery/100 (0 if unknown), icon = deviceType.sfSymbol, and suppresses the volume HUD for 1.5 s (:103-104, :1893-1961); listening-mode events: 15 private DNC names (com.apple.AudioAccessory.*, com.apple.Bluetooth.*, com.apple.controlcenter.airpodspro.settingschanged) + Darwin notify center + catch-all DNC observer (:110-125, :193-228), `log stream` of audioaccessoryd/bluetoothd/heard for LsnM/noiseControlMode (:2187-2199), `/usr/sbin/ioreg -r -l -w 0` fallback (:2106-2109), 180 ms refresh delay, 350 ms debounce, HUD value -1 duration 2.5 s, activeListeningModeEvent cleared after 2.7 s (:1963-2030); AirPodsListeningMode symbols ear.badge.waveform / ear / waveform / person.wave.2 / airpods.pro (:2580-2593); BluetoothAudioDeviceType 12 cases with sfSymbols (airpods, airpods.gen3, airpods.gen4, airpods.pro, airpodsmax, beats.headphones, headphones, hifispeaker.fill, bluetooth.circle.fill) and .mov base name = case name (:2737-2800); .beats has no movie (bundle has 8 .mov: airpods, airpodsGen3, airpodsGen4, airpodsMax, airpodsPro, airpodsPro3, beatssolo, beatsstudio, duplicated at bundle root and in BluetoothHUDAnimations/). Settings showBluetoothDeviceConnections=true, showAirPodsListeningModeChanges=true (Constants.swift:1271, :1279). Vertical HUD volume icon = activeDeviceIconSymbol() (last connected device) or 'headphones.slash' when muted (SystemChangesObserver.swift:68-74, :310-316).
- Caps Lock manager (managers/CapsLockManager.swift): NSEvent.addLocalMonitorForEvents + addGlobalMonitorForEvents(.flagsChanged) (:41-51), initial state from NSEvent.modifierFlags (:38), state animated .spring(response 0.32, dampingFraction 0.85) (:34), sneak peek type .capsLock duration .infinity value 1 on activate, status false on deactivate (:77-97); settings enableCapsLockIndicator=true, capsLockIndicatorTintMode=.white (green|accent|white; .accent = SwiftUI Color.accentColor), showCapsLockLabel=false, legacy capsLockIndicatorUseGreenColor + didMigrateCapsLockTintMode (Constants.swift:1492-1497, :509-536). Caps Lock as music secondary: badge 'capslock.fill' size badge*0.5, right wing MusicCapsLockLabelView when showLabel else spectrum, wing width scaledWingWidth(factor 0.4, extra 12) (ContentView.swift:1572-1573, :1685-1688, :1730-1735).
- Reminder live activity (components/Calendar/ReminderLiveActivity.swift): wingPadding 16, ringStrokeWidth 3 (:36-37); row HStack(spacing 0){ left wing width 16+iconDiameter | black Rectangle(closedWidth) | right wing } with height effectiveClosedNotchHeight (no −12, no hover growth) (:52-74); icon 'calendar.badge.clock' / 'calendar.badge.exclamationmark' when critical, 16 pt semibold, iconDiameter max(h-8, 26) (:76-85, :194-196, :223-225); ring diameter max(min(h-12, 22), 16), track white 0.15, progress = elapsed/leadTime, .smooth(0.25), rotated -90° (:100-115, :198-200); digital '%02d:%02d' 16 semibold monospaced, width max(text+18, 76) (:117-125, :182-186); minutes 'in N min' 13 semibold, width max(text+18, 88) (:127-134, :188-192); accent = Color(calendar colour).ensureMinimumBrightness(0.7) or .red when remaining ≤ reminderSneakPeekDuration (:158-163, :227-232); transition opacity+move(.bottom) (:46). Manager (managers/ReminderLiveActivityManager.swift): EventKit via CalendarManager, trigger = start − reminderLeadTime min (:328, :389-390), 1 s ticker (:430), events debounce 0.35 s / settings 0.2 s / lock-resume cooldown 5 s (:63-71), standard sneak peek at trigger (duration reminderSneakPeekDuration, icon standard) and one critical sneak when remaining ≤ window with duration min(window, remaining−2) (:495-532); reminderSneakPeekText 'Title • in N min • HH:mm' / '• now' (ContentView.swift:1334-1353). Settings enableReminderLiveActivity=true, reminderPresentationStyle=.ringCountdown ('Ring'|'Digital'|'Minutes'), reminderLeadTime=5, reminderSneakPeekDuration=5, hideCompletedReminders=true (Constants.swift:1333-1336, :1037, :771-790).
- Idle (face) animation (ContentView.swift:1376-1390; components/IdleAnimationView.swift; managers/IdleAnimationManager.swift): row = HStack{ clear (h-12)² | black Rectangle(closedWidth-20) | IdleAnimationView (h-12)² }.frame(height h+(hover?8:0)); IdleAnimationView = LottieUI LottieView(LUStateData(type: .loadedFrom(url), speed, loopMode)) framed cropWidth*scale × cropHeight*scale, offset/rotation/opacity/paddingBottom, .clipped(), re-created on transform override change (:28-86); AnimationTransformConfig defaults scale 1, offset 0/0, crop 30×20, rotation 0, opacity 1, paddingBottom 0, expandWithAnimation false, loopMode .loop (Constants.swift:100-121); bundled Lottie JSONs 'Dog waiting', 'Moody Dog', 'Orange Cat Peeping', 'Reindeer' (IdleAnimationManager.swift:107; present in /Applications/Atoll.app/Contents/Resources); user imports stored in ~/Library/Application Support/DynamicIsland/IdleAnimations, remote URLs stored as .lottieURL (:166-240); legacy 'builtin://face' migrated away (:54-60, :82-94). Settings showNotHumanFace=false, customIdleAnimations=[], selectedIdleAnimation=nil, animationTransformOverrides=[:] (Constants.swift:1031-1034). components/Music/LottieAnimationView.swift (lottiefiles lf20_mniampqn, selectedVisualizer) is the music visualizer, not idle.
- Lock-screen expansion timings (managers/LockScreenManager.swift): on lock any sneak peek / expanding view is cancelled and expandingView .lockScreen is shown when enableLockScreenLiveActivity (:250-273); hidden after currentUnlockRemovalDelay = unlockHold (lock 0.82 s | fingerprint/both 1.45 s) + unlockCollapse 0.82 + padding 0.14 (:31-61, :336-345); post-unlock music HUD deferred by removalDelay + 1.0 s, revealed with spring(0.34, 0.88, blend 0.08) (:44-45, :298-325); lock detection via DNC com.apple.screenIsLocked/Unlocked + NSWorkspace.sessionDidBecomeActive + CGSessionCopyCurrentDictionary polling (:144-165, :352-360). Settings enableLockScreenLiveActivity=true, lockScreenLiveActivityIconStyle=.lock (lock|fingerprint|both) (Constants.swift:1487-1488, :975-982). 'FingerprintScan' is absent from the 2.3.3 binary (Lock.json present) → fingerprint style is post-2.3.3.
- Third-party DDC (BetterDisplay/Lunar) brightness/volume sneak dispatch: BetterDisplayManager.swift:286-330 and LunarManager.swift:352-392 replicate the Circular → Vertical → Custom OSD → notch sneak order, pass a per-display `onScreen: targetScreen` and an optional custom brightness symbol (`customSymbol`), which is the only path that sets sneakPeek.icon for .brightness; SystemHUDManager surrenders brightness/backlight to them only while the helper app is running (SystemHUDManager.swift:277-295). Settings enableThirdPartyDDCIntegration=false, thirdPartyDDCProvider=.betterDisplay (bundle IDs pro.betterdisplay.BetterDisplay / fyi.lunar.Lunar), enableExternalVolumeControlListener=false, legacy enableBetterDisplayIntegration/enableLunarIntegration/didMigrateThirdPartyDDCIntegration (Constants.swift:371-392, :1443-1450).
- Dead/legacy code the spec should mark explicitly: managers/SystemKeyObserver.swift (NSApplication subclass using sendEvent/NX_KEYTYPE_*) is not the principal class (NSPrincipalClass absent in shipped Info.plist) and nothing references it; SystemDisplayManager/SystemVolumeManager (IODisplayConnect / AppleScript 'get volume settings') and SystemHUDDebugger (launchctl bootstrap/restart) are unused by the HUD path; LiveActivityModifier (boring.notch leftover).
- Screen-capture exclusion: Defaults[.hideDynamicIslandFromScreenCapture]=false toggles window.sharingType .none/.readOnly for registered panels (helpers/ScreenCaptureVisibilityManager.swift:65-68; DynamicIslandApp.swift:1690) — relevant because the recording HUD itself can be hidden from recordings.
- Settings keys in this subsystem with defaults not listed in the visible spec: hideNonNotchUntilHover=false (Constants.swift:1003), minimumHoverDuration=0.3, openNotchOnHover=true (:995-997), enableCameraDetection/enableMicrophoneDetection=true (:1483-1484), enableDoNotDisturbDetection=true, focusMonitoringMode=.withoutDevTools ('withoutDevTools'|'useDevTools'), showDoNotDisturbIndicator=true, showDoNotDisturbLabel=true, focusIndicatorNonPersistent=false (:1476-1480), enableScreenRecordingDetection=true, showRecordingIndicator=true, recordingHoverStyle=.default, recordingControlMode=.withStopButton (:1468-1471), enableDownloadListener=true, enableSafariDownloads=true, selectedDownloadIndicatorStyle=.progress, showDownloadSpeed=false, selectedDownloadIconStyle=.onlyAppIcon (:1199-1203), showBluetoothDeviceConnections=true, showAirPodsListeningModeChanges=true (:1271, :1279), enableCapsLockIndicator=true, capsLockIndicatorTintMode=.white, showCapsLockLabel=false (:1492-1497), enableReminderLiveActivity=true, reminderPresentationStyle=.ringCountdown, reminderLeadTime=5, reminderSneakPeekDuration=5 (:1333-1336), enableLockScreenLiveActivity=true, lockScreenLiveActivityIconStyle=.lock (:1487-1488), showNotHumanFace=false, customIdleAnimations, selectedIdleAnimation, animationTransformOverrides (:1031-1034), hideDynamicIslandFromScreenCapture=false (:992), siriResponsivenessMode=.automatic (:1097, SiriVisibilityMonitor — not in 2.3.3).
- Version-skew summary the spec should carry (source tree is newer than the 2.3.3 binary): absent from /Applications/Atoll.app 2.3.3 per strings/macho/dispatch evidence — NetworkConnectivityManager/HUD (no CoreWLAN link), MenuBarLayout menu-bar clearance offset, SiriVisibilityMonitor, recording hover stop-button/expanded card (recordingHoverStyle/recordingControlMode keys), download speed (showDownloadSpeed), fingerprint lock icon (FingerprintScan.json), libproc PID lookup (proc_listpids/proc_name not imported) and launchctl kickstart/load restore path ('launchctl'/'kickstart' strings absent; 'pgrep' and '/usr/bin/killall' present). Present in 2.3.3: OSDUIHelper SIGSTOP via killall + pgrep, CoreBrightness/DisplayServices runtime loading (class names CBBrightnessProxy/BrightnessSystemClient/KeyboardBrightnessClient, DisplayServicesGetBrightness strings), corebrightnessdiag, AppleHIDKeyboardEventDriverV2/KeyboardBacklightBrightness, DND notifications + Assertions.json + duetexpertd log stream, IOBluetooth DNC notifications + audioaccessoryd LsnM log stream + ioreg/pmset/system_profiler, all HUD/OSD/vertical/circular/inline settings keys, Caps Lock, reminders, idle Lottie files, lowbattery.mp3 / audio-feedback.m4a / 8 BluetoothHUDAnimations .mov.

Corrections:

- Full-battery standard HUD sequence is reversed in user_visible_behaviour. Source (DynamicIslandBattery.swift:857-889, :704-729): for kind .fullBattery && style .standard, showBatteryIndicator starts TRUE so the pulsing green (or yellow) battery pill is shown first; after 2 s withAnimation(.spring(duration 0.4)) it swaps to the MagSafe illustration with an ORANGE LED; after 3 s withAnimation(.spring(duration 0.2)) the LED turns green. The layout/animation fields have it right; the behaviour sentence says MagSafe first then battery.
- BatteryTemporaryHUDMetrics.topRadius values (compact max(12, base-4); low 22; full 18 at DynamicIslandBattery.swift:471, :485, :492) are dead: surfaceShape uses the injected `topCornerRadius` parameter (:605), which ContentView passes as activeCornerRadiusInsets.closed.top = 6 (ContentView.swift:1120). Only bottomRadius (compact max(h/2,16), low 40, full 36) is applied; Dynamic Island mode uses DynamicIslandPillShape(cornerRadius: 24) (:603).
- Inline HUD Bluetooth left wing does NOT show the device name by default. InlineHUD.swift:304-316: for .bluetoothAudio the label is EmptyView for listening-mode events, MarqueeText(displayName) only when showBluetoothDeviceNameMarquee (default false, Constants.swift:1277), otherwise nothing — the default connect HUD is glyph/.mov icon on the left and battery gauge on the right. Spec's 'shows its symbol ... + name' is wrong for defaults.
- 'accent' in Vertical HUD, Circular HUD, CapsLockIndicatorTintMode.accent, DownloadLiveActivity tint and SpinningCircleDownloadView means SwiftUI `Color.accentColor` (system/asset accent), not the app setting Defaults[.accentColor] (VerticalHUDView.swift:250; CircularHUDView.swift:118; Constants.swift:530-531; DownloadLiveActivity.swift:61-63, :132; SpinningCircleDownloadView.swift:34). Only DraggableProgressBar / SegmentedProgressContent read Defaults[.accentColor] (SystemEventIndicatorModifier.swift:282, :377, :389).
- showOnAllDisplays semantics are inverted in the spec ('showOnAllDisplays shows on every screen'). ContentView.swift:435-440 (isSneakPeekVisibleOnCurrentScreen) and :495-502 (isBatteryHUDVisibleOnCurrentScreen): when showOnAllDisplays is OFF the HUD is always treated as visible (there is one notch window); when it is ON, a non-nil targetScreenName restricts the HUD to that one screen (nil target → every screen). BatteryStatusViewModel.swift:225-242 returns a nil target only when showOnAllDisplays is ON.
- SystemOSDManager watcher cadence (SystemOSDManager.swift:406-416) is 150 ms until 5 stable checks, 500 ms until 20 stable checks, then 1 s; 1 s whenever the helper is not running. The spec collapses the 5–20 band.
- OSD-suppression 'confirmed in binary' must be scoped to 2.3.3: the shipped binary imports _proc_pidinfo but not _proc_listpids/_proc_name (REA macho.json) and contains the strings 'pgrep' and '/usr/bin/killall' but NOT 'launchctl' or 'kickstart' (strings of /Applications/Atoll.app/Contents/MacOS/Atoll). So 2.3.3 located OSDUIHelper with `pgrep -n` via NSTask and only SIGSTOP/SIGCONT'd it; the launchctl kickstart/`load -w` restore path (SystemOSDManager.swift:103-171, :297-303) and the libproc lookup (:450-487) are post-2.3.3 source.
- Wing/row geometry rule 'wing content height = h-12, row = h+8 on hover' is not universal across closed activities: ReminderLiveActivity uses full effectiveClosedNotchHeight for all three segments and ignores hover (ReminderLiveActivity.swift:39-41, :52-74); DoNotDisturbLiveActivity wings are max(h-10, 20) tall with no hover growth (DoNotDisturbLiveActivity.swift:89-91); PrivacyLiveActivity and DownloadLiveActivity declare isHovering/gestureProgress as local @State that is never written (PrivacyLiveActivity.swift:26-27; DownloadLiveActivity.swift:26-27), so they never grow on hover; RecordingLiveActivity rowHeight is h-12 but its centre is full h (RecordingLiveActivity.swift:45-47, :95-97). Only MusicLiveActivity, InlineHUD, the face row and the battery HUD follow the generic hover rule.
- Haptics: the spec says 'only on notch tap/gestures'; hover entering the closed notch also calls triggerHapticIfAllowed() when Defaults[.enableHaptics] (ContentView.swift:2330-2332), throttled 300 ms (:2482-2488).
- Priority-chain item (17) DynamicIslandHeader: height is max(24, effectiveClosedNotchHeight) EXCEPT when enableMinimalisticUI && isDynamicIslandMode, where the frame height is nil/intrinsic (ContentView.swift:1172-1173).
- CustomOSDView segment fill uses Int(value*16) truncation (CustomOSDView.swift:138), not round() as the notch SegmentedProgressContent does (SystemEventIndicatorModifier.swift:346); at e.g. 0.99 the OSD shows 15/16 segments.
- InlineHUD left wing height uses vm.notchSize.height (the live window height) while the trailing wing and outer frame use vm.closedNotchSize.height (InlineHUD.swift:327 vs :454-456); the spec states this but should flag it as an intentional-looking asymmetry to reproduce or deliberately drop.
- 'Battery HUD compact: Charging/Low/Full titles' — compact uses 'Charging' / 'Low Battery' / 'Full Battery' (DynamicIslandBattery.swift:648-657) while the standard card title is 'Battery Low' (not 'Low Battery') / 'Full Battery' (:662); the spec lists both but the user-visible text should say 'Battery Low' for the standard card.
- Spec 'Inline HUD ... AirPods listening-mode change shows the mode glyph and the mode name' — the glyph (AirPodsListeningModeSymbol, size 15 medium hierarchical in 17x17) comes from BluetoothAudioManager.activeListeningModeEvent?.mode OR from sneakPeek.icon when value < 0 (InlineHUD.swift:133-136); the event is cleared 2.7 s after presentation (BluetoothAudioManager.swift:2021-2029), slightly after the 2.5 s sneak duration, so the InlineHUD layout stays in listening-mode widths until then.

Private API summary:

PRIVATE / fragile mechanisms in this subsystem (source → confirmed in shipped 2.3.3 via REA macho.json imports / dispatch.json / binary strings where noted):

1. Native OSD suppression (managers/SystemOSDManager.swift): freezes Apple's OSDUIHelper with `/usr/bin/killall -STOP` and a respawn watcher, resumes with `-CONT`, restarts via `launchctl kickstart gui/<uid>/com.apple.OSDUIHelper` (source only). Not an API but an unsupported process-manipulation hack that requires an unsandboxed app (signature.json: hardened runtime, no com.apple.security.app-sandbox, com.apple.security.cs.disable-library-validation, automation.apple-events, device.camera, personal-information.calendars/location). 2.3.3 evidence: strings 'OSDUIHelper' ×28, 'pgrep', '/usr/bin/killall', 'com.apple.OSDUIHelper'; NSTask imported; proc_pidinfo imported but proc_listpids/proc_name not (libproc lookup is newer source).
2. Display brightness (helpers/CoreBrightnessDisplayClient.swift, helpers/DisplayServicesDynamic.swift, managers/SystemMediaControllers.swift:643-989): Bundle.load of /System/Library/PrivateFrameworks/CoreBrightness.framework and ObjC-runtime calls to CBBrightnessProxy / CBDisplayBrightnessClient / BrightnessSystemClient / DisplayBrightnessClient `brightnessForDisplay:` / `setBrightness:forDisplay:`; dlopen/dlsym of DisplayServices.framework `DisplayServicesGetBrightness/SetBrightness`; undocumented DistributedNotificationCenter names com.apple.BezelEngine.BrightnessChanged, com.apple.BezelServices.BrightnessChanged, com.apple.controlcenter.display.brightness, com.apple.CoreBrightness.DisplayBrightnessChanged; `/usr/libexec/corebrightnessdiag status-info` fallback. 2.3.3: _dlopen/_dlsym imported, CoreBrightness/DisplayServices absent from LC_LOAD_DYLIB (runtime-loaded), strings for all class names/notification names/corebrightnessdiag present. Public last resort: IODisplayGetFloatParameter/IODisplaySetFloatParameter (deprecated, imported).
3. Keyboard backlight (managers/KeyboardBrightnessSensor.swift): private CoreBrightness `KeyboardBrightnessClient brightnessForKeyboard:/setBrightness:forKeyboard:` (keyboard 1); fallback IORegistry AppleHIDKeyboardEventDriverV2 'KeyboardBacklightBrightness' (max 342) via IORegistryEntryCreateCFProperty/SetCFProperty (public IOKit but undocumented property); corebrightnessdiag plist. All strings present in 2.3.3.
4. Media keys (managers/MediaKeyInterceptor.swift): CGEvent.tapCreate on NX_SYSDEFINED (type 14, subtype 8) at .cghidEventTap/.cgSessionEventTap — public API but privileged (Accessibility; AXIsProcessTrustedWithOptions prompt). Imported in 2.3.3.
5. Screen recording detection (managers/ScreenRecordingManager.swift:23-34, :375-385, :432-457): private SkyLight/CGS symbols `CGSIsScreenWatcherPresent` and `CGSRegisterNotifyProc` (events 1502/1503) via @_silgen_name — both imported in 2.3.3. Stop control uses AppleScript System Events + CGEvent key posting (public, needs Accessibility/Automation) and killall on screencapture.
6. Window placement for OSD/vertical/circular HUDs and lock-screen overlays: SkyLightWindow package (SkyLightOperator.delegateWindow) plus private/CGSSpace.swift using `_CGSDefaultConnection`, CGSSpaceCreate/Destroy, CGSSpaceSetAbsoluteLevel, CGSAddWindowsToSpaces/RemoveWindowsFromSpaces, CGSShowSpaces/HideSpaces — all imported in 2.3.3 (also _CGShieldingWindowLevel, _CGWindowListCopyWindowInfo, _CGSessionCopyCurrentDictionary for lock detection; 'CGSSessionScreenIsLocked' string present).
7. Focus/DND (managers/DoNotDisturbManager.swift): private DistributedNotificationCenter names `_NSDoNotDisturbEnabledNotification` / `_NSDoNotDisturbDisabledNotification`; reading ~/Library/DoNotDisturb/DB/Assertions.json and ModeConfigurations.json (requires Full Disk Access); `/usr/bin/log stream|show --predicate process == "duetexpertd" AND eventMessage CONTAINS "semanticModeIdentifier"`. All strings present in 2.3.3. Focus badges also use SwiftUI's private `Image.init(_internalSystemName:)` via @_silgen_name (extensions/Image+InternalSystemName.swift:21-22) for internal SF Symbols person.lanyardcard.fill / apple.mindfulness / rocket.fill.
8. Bluetooth / AirPods (managers/BluetoothAudioManager.swift): IOBluetooth (public but soft-deprecated) + DNC 'IOBluetoothDeviceConnectedNotification/DisconnectedNotification'; 15 private Apple notification names (com.apple.AudioAccessory.*, com.apple.Bluetooth.*, com.apple.controlcenter.airpodspro.settingschanged) via DistributedNotificationCenter and CFNotificationCenterGetDarwinNotifyCenter; `log stream` of audioaccessoryd/bluetoothd/heard for LsnM/noiseControlMode; `/usr/sbin/ioreg -r -l -w 0`, `pmset -g accps`, `system_profiler` parsing; IORegistry 'BatteryPercent*' properties; dynamic selector probing. 2.3.3: IOBluetooth/CoreBluetooth linked, _CFNotificationCenterGetDarwinNotifyCenter/_CFNotificationCenterAddObserver imported, strings for airpodspro.settingschanged, audioaccessoryd, LsnM, noiseControlMode, pmset, system_profiler present.
9. Lock screen (managers/LockScreenManager.swift): DNC com.apple.screenIsLocked/Unlocked (undocumented but widely used) + CGSessionCopyCurrentDictionary polling (public, semi-documented key). Present in 2.3.3.
10. Everything else is public API: CoreAudio AudioObjectAddPropertyListenerBlock / kAudioDevicePropertyVolumeScalar / kAudioHardwareServiceDeviceProperty_VirtualMainVolume (vmvc) for volume; kAudioDevicePropertyDeviceIsRunningSomewhere for mic; CoreMediaIO kCMIODevicePropertyDeviceIsRunningSomewhere + AVCaptureDevice.isInUseByAnotherApplication for camera; IOKit.ps IOPSNotificationCreateRunLoopSource/IOPSCopyPowerSourcesInfo + NSProcessInfoPowerStateDidChange for battery; NSEvent flagsChanged monitors for Caps Lock; DispatchSource file watcher for downloads; EventKit for reminders; NWPathMonitor + CoreWLAN + `networksetup` for connectivity (public, but the connectivity feature is not in the 2.3.3 binary); AVQueuePlayer/AVPlayerLooper for .mov icons; AVAudioPlayer/NSSound for feedback sounds; Lottie (embedded framework) + LottieUI for idle animations. No private APIs are needed for the notch-side rendering of any live activity; the private surface is confined to OSD suppression, brightness/keyboard-backlight control, screen-recording detection, Focus detection, SkyLight window delegation, internal SF Symbols and AirPods listening-mode detection.
