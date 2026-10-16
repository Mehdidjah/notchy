# Atoll spec: Notch shell UI (window, shape, open/closed layout, header, tab bar, hover/gesture state machine, Dynamic Island pill mode, minimalistic mode, hide-until-hover, menu-bar clearance, multi-display)

Source: Atoll 2.3.3 source clone plus REA evidence from the installed binary (see ../atoll-behaviour-evidence.md). Values are quoted with file:line from the Atoll source. Reimplement behaviour, do not copy code (GPL-3).

## Summary

Atoll 2.3.3 (source clone at MARKETING_VERSION 2.3.3 matches the shipped bundle CFBundleShortVersionString 2.3.3 / build 20260720004, LSUIElement=true, LSMinimumSystemVersion 14.6) renders one borderless non-activating NSPanel per display (level .mainMenu+3, pinned into a private CGS Space at max level) whose SwiftUI root is ContentView. The shell is a black background clipped by an animatable NotchShape (quad-curve top corners that flare outward, bottom corners rounded) or, on non-notch displays with externalDisplayStyle == .dynamicIsland, a continuous-corner pill. Closed size = physical notch width + 4 (or closedNotchWidth 150 on non-notch displays) x notch height (safeAreaInsets.top by default, 32 fallback); open size = max(openNotchWidth 640, min width by enabled tab count 640/690/770) x 200 (+12pt inner padding + 18pt shadow padding), with per-tab height overrides (timer 250, notes 240/260/320, terminal 40% of screen, stats +132 for 4+ graphs, +18 inline lyrics). Minimalistic UI uses 420x180 (340x144 in pill mode) with 35pt opened radii. Open/close is driven by hover (300 ms default dwell, 100 ms exit debounce, click/global monitors, top-edge retention), tap, two-finger scroll (NSEvent scrollWheel monitors, 200pt sensitivity, live gestureProgress stretch/blur) and a keyboard shortcut (3 s auto close). Animations: hover .bouncy.speed(1.2); open spring(response 0.42, damping 1.0); close spring(0.45, 1.0) (or blurReplace+interactiveSpring in legacy mode); header fade/blur 20pt with .smooth.delay(0.1); tab content asymmetric move+opacity .smooth(0.3) directed by tabSwitchForward. Header = tab capsule bar on the left (HStack spacing 24, 26pt tall, white icon on secondarySystemFill 25% capsule with matchedGeometryEffect), a black NotchShape-masked spacer of min(closedWidth,300) over the hardware notch, and a trailing run of 30x30 black capsule buttons (spacing 8; web.camera, list.clipboard, eyedropper, timer, slider.vertical.3, cup.and.saucer, gearshape at hand-tuned 13-14.5pt medium sizes) plus recording/focus indicators and a 30pt-wide battery. Private API used by the shell: CGS Space functions (CGSSpaceCreate/SetAbsoluteLevel/AddWindowsToSpaces...) confirmed as undefined imports in the shipped binary; NSGlassEffectView (string present, loaded via NSClassFromString) is used by LiquidGlassBackground for HUD/lock-screen surfaces, not for the notch shell itself. Everything else (NSScreen.auxiliaryTopLeft/RightArea, safeAreaInsets, AXUIElement menu-bar measurement, NSHapticFeedback via .sensoryFeedback, NSEvent monitors) is public.

## Notch window: NSPanel, level, Spaces pinning, placement, resizing

### Behaviour

A click-through-free black panel floats above the menu bar on the chosen display, centred on the screen's horizontal midpoint, hugging the top edge (hanging 4pt above screen.maxY on physical-notch displays so no gap shows). It stays visible over fullscreen apps and across Space switches, never activates the app, accepts first mouse, and is excluded from screenshots/recordings when 'hideDynamicIslandFromScreenCapture' is on. On lock it is hidden (alpha 0 + orderOut) and restored on unlock.

### Layout

DynamicIslandWindow: NSPanel subclass (components/Notch/DynamicIslandWindow.swift:25-61): isFloatingPanel=true, hidesOnDeactivate=false, isOpaque=false, titleVisibility=.hidden, titlebarAppearsTransparent=true, backgroundColor=.clear, isMovable=false, collectionBehavior=[.fullScreenAuxiliary,.canJoinAllSpaces,.ignoresCycle,.stationary] (:26-31), isReleasedWhenClosed=false, level = .mainMenu + 3 (:57), hasShadow=false (:58), canBecomeKey/Main = true (:63-69). Created with styleMask [.borderless,.nonactivatingPanel], backing .buffered, animationBehavior .none, contentView = FirstMouseHostingView(rootView: ContentView()...) which overrides acceptsFirstMouse -> true (DynamicIslandApp.swift:90-94, 408-439). Window frame: width = contentSize.width (+ 2*14 in pill mode), height = contentSize.height + 4 top bleed (notch) or + 6 top offset (pill) (DynamicIslandApp.swift:635-644); origin x = (screen.midX - w/2).rounded(), y = (screen.maxY + topBleed - h).rounded(), width clamped to screen width, height clamped to screen height + topBleed (DynamicIslandApp.swift:441-465, 670-687). Required content size = dynamic open/closed size + shadow padding 18 (standard) / 12 (minimalistic) (sizing/matters.swift:171-172, 319-325; DynamicIslandApp.swift:479-598). The SwiftUI root clamps itself to the same numbers: maxWidth = dynamicNotchSize.width + (open ? 24 : 0) + (island ? 28 : 0); maxHeight = dynamicNotchSize.height + (open ? 12 : 0) + (island ? 0 : 4) + (island ? 6+28 : shadowPadding), .animation(nil, value: notchState), inside a top-aligned infinite frame (ContentView.swift:859-874).

### Animations

Window resizes are immediate setFrame(display:true) with no AppKit animation (DynamicIslandApp.swift:686); 'animated' flag is accepted but unused. Tab switches force an immediate resize on the next run-loop tick (DynamicIslandApp.swift:474-477, 803-807); setting-driven resizes are debounced 150 ms (DynamicIslandApp.swift:147-159); minimalistic toggle resizes immediately (:941-944). ViewModel-driven size changes animate the SwiftUI notchSize with .smooth (reminders/lyrics/open width/side lyrics), .easeInOut(0.3) for stats second row, .easeInOut(0.25) for notes layout (models/DynamicIslandViewModel.swift:173-326).

### State and timing

Screens change -> compare count/names/frames, then cleanupWindows()+adjustWindowPosition() async (DynamicIslandApp.swift:1559-1576). Lock: hideWindowsForLock (alpha 0, orderOut); unlock: restore + adjustWindowPosition(changeAlpha:true) (:320-354). Active-space change -> reassert collectionBehavior + orderFrontRegardless + re-sync CGS space membership (:396-406, 974-983).

### Data sources and APIs

Public: NSPanel, NSWindow.Level(.mainMenu + 3), NSWindow.CollectionBehavior, NSHostingView.acceptsFirstMouse, NSWindow.sharingType (.none when hiding from capture, else .readOnly; helpers/ScreenCaptureVisibilityManager.swift:65-68), NSApplication.didChangeScreenParametersNotification, NSWorkspace.activeSpaceDidChangeNotification, DistributedNotificationCenter 'com.apple.screenIsLocked'/'com.apple.screenIsUnlocked' (DynamicIslandApp.swift:967-1029). PRIVATE: CGS Spaces via @_silgen_name: _CGSDefaultConnection, CGSSpaceCreate(cid, 1, nil), CGSSpaceSetAbsoluteLevel(level 2147483647), CGSShowSpaces/CGSHideSpaces, CGSAddWindowsToSpaces/CGSRemoveWindowsFromSpaces, CGSSpaceDestroy (private/CGSSpace.swift:69-87, managers/NotchSpaceManager.swift:25-34). REA macho.json imports confirm the shipped binary links exactly these: _CGSSpaceCreate, _CGSSpaceDestroy, _CGSSpaceSetAbsoluteLevel, _CGSAddWindowsToSpaces, _CGSRemoveWindowsFromSpaces, _CGSShowSpaces, _CGSHideSpaces, __CGSDefaultConnection (plus _CGSIsScreenWatcherPresent, _CGSRegisterNotifyProc used elsewhere). dispatch.json confirms ObjC classes _TtC5Atoll19DynamicIslandWindow : NSPanel with selectors initWithContentRect:styleMask:backing:defer:, canBecomeKeyWindow, canBecomeMainWindow, and Swift classes NotchSpaceManager, CGSSpace, ScreenCaptureVisibilityManager. SkyLightWindow package is imported but .moveToSky()/delegateWindow are commented out for the notch window (DynamicIslandApp.swift:432,437). No private framework is in LC_LOAD_DYLIB (all 75 deps are public frameworks + Lottie + Sparkle).

### Settings

hideDynamicIslandFromScreenCapture (Bool, false); showOnAllDisplays (Bool, false); automaticallySwitchDisplay (Bool, true); preferred_screen_name (@AppStorage, NSScreen.main?.localizedName); menubarIcon (Bool, true). Notification names: 'SelectedScreenChanged', 'NotchHeightChanged', 'showOnAllDisplaysChanged' (DynamicIslandApp.swift:1703-1705).

### Implementation notes

NotchIsland already has NotchPanelController; match: NSPanel [.borderless,.nonactivatingPanel], level .mainMenu+3, the 4 collection behaviors, hasShadow=false, first-mouse hosting view, 4pt top bleed above screen.maxY. Skip the private CGS Space (it only reinforces .canJoinAllSpaces/.fullScreenAuxiliary); public collectionBehavior is sufficient for macOS 14+. Size ~150 LOC.

### Key files

- `DynamicIsland/components/Notch/DynamicIslandWindow.swift`
- `DynamicIsland/DynamicIslandApp.swift`
- `DynamicIsland/managers/NotchSpaceManager.swift`
- `DynamicIsland/private/CGSSpace.swift`
- `DynamicIsland/helpers/ScreenCaptureVisibilityManager.swift`
- `../../rea-out/macho.json`
- `../../rea-out/dispatch.json`

## Notch shell shape, clip, padding and shadow (standard notch and Dynamic Island pill)

### Behaviour

The black island is drawn with a NotchShape whose top corners curve outward into the screen edge (quad curves) and whose bottom corners are rounded; radii animate between closed (top 6 / bottom 14) and open (top 19 / bottom 24, or 35/35 in minimalistic) when 'Corner radius scaling' is on. A 60%-black drop shadow (radius 10, or 5 without radius scaling) appears while open or hovered. On non-notch displays set to 'Dynamic Island' the clip is a continuous-corner pill floating 6pt below the top edge with capsule radius = max(closedHeight/2, 16) closed and 24 (35 minimalistic) open.

### Layout

NotchShape path (components/Notch/NotchShape.swift:50-133): move (minX,minY); quadCurve to (minX+top, minY+top) ctrl (minX+top, minY); line to (minX+top, maxY-bottom); quadCurve to (minX+top+bottom, maxY) ctrl (minX+top, maxY); line to (maxX-top-bottom, maxY); quadCurve to (maxX-top, maxY-bottom) ctrl (maxX-top, maxY); line to (maxX-top, minY+top); quadCurve to (maxX, minY) ctrl (maxX-top, minY); close. Defaults top 6 / bottom 14 (:33-34); animatableData = AnimatablePair(top,bottom) (:37-48). DynamicIslandPillShape = Path(roundedRect:cornerRadius:min(r, min(w,h)/2), style:.continuous), animatable radius (components/Notch/DynamicIslandPillShape.swift:25-37). Radii: cornerRadiusInsets opened (19, 24) closed (6, 14) (sizing/matters.swift:199); minimalisticCornerRadiusInsets opened (35, 35), closed = standard closed (:200); dynamicIslandPillCornerRadiusInsets opened 24, closed 16 (:357-360); dynamicIslandTopOffset 6 (:372); dynamicIslandShadowInset 14 (:377); notchTopScreenBleedAmount 4 (notch only) (:363-367). currentNotchShape uses opened radii only when open && cornerRadiusScaling else closed radii (ContentView.swift:406-414); currentPillShape: open -> 35 (minimalistic) or 24, closed -> max(closedNotchSize.height/2, 16) (:482-493). mainLayoutBase (ContentView.swift:655-689): NotchLayout().frame(alignment:.top) .padding(.horizontal, notchHorizontalPadding) .padding([.horizontal,.bottom], open ? 12 : 0) .background(.black) .clipShape(resolvedClipShape) .padding(.top, island ? 0 : 4) .overlay(alignment:.top){ black Rectangle height 4 (non-island) } .compositingGroup() .shadow(color: (open||hovering)&&enableShadow ? .black.opacity(0.6) : .clear, radius: cornerRadiusScaling ? 10 : 5) .padding(.horizontal, island ? 14 : 0) .padding(.bottom, island ? 14 : 0) .padding(.top, island ? 6 : 0) .accessibilityIdentifier("AtollNotch"). notchHorizontalPadding: closed -> activeCornerRadiusInsets.closed.bottom = 14; open && cornerRadiusScaling -> opened.top - 5 (= 14 standard, 30 minimalistic); open && !scaling -> opened.bottom - 5 (= 19 standard, 30 minimalistic) (ContentView.swift:345-353). Net closed shell width = (closedNotchSize.width - 20) + 2*14 = closedNotchSize.width + 8, i.e. physical notch width + 12. Special closed-state clip overrides: connectivity HUD (bottom radius 40 when no connection else 20; pill 40/24), recording HUD expanded (bottom 40), battery HUD standard style (bottom 40 low / 36 full) (ContentView.swift:574-649). Bottom padding below the shell = shadowPadding (18/12) + 10 when effectiveClosedNotchHeight == 0 (zeroHeightHoverPadding) unless open && extendHoverArea (ContentView.swift:304, 355-364, 751).

### Animations

Shape radii animate implicitly with the notchState animation (spring response 0.42 open / 0.45 close, dampingFraction 1.0) and hover (.bouncy.speed(1.2)) because NotchShape/DynamicIslandPillShape are Animatable (ContentView.swift:691-711). Shadow colour toggles with the same animations. compositingGroup before shadow so the shadow follows the clipped silhouette.

### State and timing

Radii depend on (notchState, cornerRadiusScaling, enableMinimalisticUI, isDynamicIslandMode, active closed HUD kind).

### Data sources and APIs

Public SwiftUI Shape/Path, .clipShape, .shadow, .compositingGroup. Pill vs notch decision: shouldUseDynamicIslandMode(for:) = externalDisplayStyle == .dynamicIsland && screen.safeAreaInsets.top <= 0 (sizing/matters.swift:335-352) — public NSScreen.safeAreaInsets.

### Settings

cornerRadiusScaling (Bool, true); enableShadow (Bool, true); externalDisplayStyle (enum 'Standard Notch' | 'Dynamic Island', default .notch; raw strings confirmed in binary); enableMinimalisticUI (Bool, false); extendHoverArea (Bool, false).

### Implementation notes

Reimplement NotchShape with the identical quad-curve construction (it is the defining silhouette) and an AnimatablePair of radii; keep the 4pt top bleed overlay outside the clip so corners anchor at the visible edge. Pill mode = RoundedRectangle(.continuous) with radius clamp. ~120 LOC.

### Key files

- `DynamicIsland/components/Notch/NotchShape.swift`
- `DynamicIsland/components/Notch/DynamicIslandPillShape.swift`
- `DynamicIsland/sizing/matters.swift`
- `DynamicIsland/ContentView.swift`

## Open notch size resolution (standard, per-tab, minimalistic)

### Behaviour

The open island is 640x200 by default, grows wider automatically when more tabs are enabled (5 tabs -> 690, 6+ -> 770), can be widened in settings up to 900 but never beyond screen width - 60, and changes height per tab: Timer 250, Notes 240/260/320 (list/split/editor), Clipboard tab 240, Terminal 40% of visible screen height (min 300), Stats +132 when 4-5 graphs are shown, Home +18 when inline lyrics are on with the calendar. Minimalistic UI opens to 420x180 (340x144 as a pill), +50 for lyrics, plus reminder rows / +94 for an external timer countdown.

### Layout

openNotchSize: width = min(max(openNotchWidth, currentRecommendedMinimumNotchWidth(), sideLyricsRequiredNotchWidth()), maxAllowedNotchWidth()), height 200 (sizing/matters.swift:69-75). maxAllowedNotchWidth = max(screen.frame.width - 60, 400), 900 fallback (:79-90). enabledStandardTabCount counts Home (media||calendar||mirror), Shelf, Timer(tab mode), Stats, Notes/Clipboard(separateTab), Terminal (:101-135); recommendedMinimumNotchWidth: >=6 -> 770, >=5 -> 690, else 640 (:138-142); enforceMinimumNotchWidth clamps the stored value (debounced 100 ms on tab-affecting settings; DynamicIslandViewCoordinator.swift:220-242). Side lyrics width = 380 + lyricsPanelWidth(280) + 20 + |lyricsPanelOffset| + (mirror ? 220+20 : 0) + 40 (:31-67). minimalisticBaseOpenNotchSize 420x180; pill mode 340x144; +50 lyrics; + reminder rows; + 94 (12+82) external timer countdown (:163-198). inlineLyricsLineHeight 18 added on home when !minimalistic && enableLyrics && showCalendar && showStandardMediaControls && (!autoHide || hasActiveSession) (:252-285). statsAdjustedNotchSize adds (120+12)*progress when stats tab && >=4 graphs (:169-170, 287-317). dynamicNotchSize in ContentView.swift:110-241 additionally: inline sneak peek closed width 460 (or AirPods width + 2*padding); recording HUD size; battery HUD closed expansions (+180 w compact; low standard +100 w/+75 h; full standard +80 w/+70 h); timer 250; notes preferredHeight (enums/generic.swift:86-101: list 240, split 260, editor 320); clipboard 240; terminal min(screenH*terminalMaxHeightFraction, max(300, same)); extension tab preferredHeight clamped to [base, base+132]; minimalistic extension content estimate (24 headline, 20 subtitle, 98/section, 16 spacing, 10 top, 10 bottom) (ContentView.swift:2520-2571). ViewModel.calculateDynamicNotchSize mirrors base + notes/clipboard + inline lyrics + stats (DynamicIslandViewModel.swift:421-441).

### Animations

notchSize changes inside vm animate .smooth (default), stats .easeInOut(0.3), notes .easeInOut(0.25) (DynamicIslandViewModel.swift:173-343). ContentView's frame uses .animation(nil, value: notchState) so the window-sized frame snaps while the inner shell animates with the spring.

### State and timing

Width is enforced on launch and 100 ms after any tab-affecting setting change.

### Data sources and APIs

Defaults (sindresorhus/Defaults 9.0.3) publishers; NSScreen.main.frame / visibleFrame (public).

### Settings

openNotchWidth (CGFloat, 640; settings slider range recommendedMin...900 step 10, disabled in minimalistic; 'Reset Width' button; SettingsView.swift:5409-5500); closedNotchWidth (CGFloat, 150; slider 80...400 step 5); customizePhysicalNotchWidth (Bool, false); lyricsPanelWidth (280); lyricsPanelOffset (0); terminalMaxHeightFraction (Double, 0.4); showCpuGraph/showMemoryGraph/showGpuGraph/showNetworkGraph/showDiskGraph.

### Implementation notes

Port as a pure function `openSize(for tab:, settings:, screen:)`; keep 640x200 base, the 640/690/770 ladder and per-tab heights. ~150 LOC.

### Key files

- `DynamicIsland/sizing/matters.swift`
- `DynamicIsland/ContentView.swift`
- `DynamicIsland/models/DynamicIslandViewModel.swift`
- `DynamicIsland/enums/generic.swift`

## Closed notch layout: wings beside the hardware notch, closed size, effective height, hover swell

### Behaviour

Closed, the island is an invisible black bar exactly covering the hardware notch (physical width + 12 incl. padding) at the notch height. Live activities draw into 'wings' left and right of the notch: left wing holds album art (closedHeight - 12 square), centre is a black spacer as wide as the notch, right wing holds the audio spectrum or timer/reminder/focus/caps-lock/shelf-count supplements. Hovering swells the whole closed bar by 8pt in height and width (content height grows from closedHeight-12 to closedHeight). On non-notch displays the height follows the menu bar (24 default) and, when a fullscreen app hides the notch, the height collapses to 0 and a 10pt hover strip remains.

### Layout

getClosedNotchSize (sizing/matters.swift:398-441): width = screen.frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width + 4 on notched screens (or closedNotchWidth when customizePhysicalNotchWidth, and on non-notch screens); height: notched -> notchHeight (default mode .matchRealNotchSize -> safeAreaInsets.top; .matchMenuBar -> frame.maxY - visibleFrame.maxY; .custom -> Defaults notchHeight 32, picker presets 38/44/38 and slider 15...45); non-notch -> nonNotchHeight (default mode .matchMenuBar -> menu bar height; presets 24/32/32, slider 0...40) (SettingsView.swift:1265-1321). effectiveClosedNotchHeight = hideOnClosed && (no physical notch) ? 0 : closedNotchSize.height (DynamicIslandViewModel.swift:376-380). Idle closed placeholder: Rectangle(.clear).frame(width: closedNotchSize.width - 20, height: effectiveClosedNotchHeight) (ContentView.swift:1175); DynamicIslandHeader when open .frame(height: max(24, effectiveClosedNotchHeight)) (:1172-1173, nil height in minimalistic pill). MusicLiveActivity wing math (ContentView.swift:1393-1518): closedHeight = effectiveClosedNotchHeight; outerHeight = closedHeight + (hover ? 8 : 0); notchContentHeight = hover ? closedHeight : closedHeight - 12; wingBaseWidth = notchContentHeight + gestureProgress/2; artworkHeight = closedHeight - 12; artworkSize = min(artworkHeight, wingBaseWidth); centerBaseWidth = max(closedNotchSize.width + (hover ? 8 : 0), 96); effectiveCenterWidth = inline sneak peek ? 380 : centerBaseWidth; rightWingWidth per secondary (timer countdown: max(base, 18 + ring 30 + 8 + countdownFrameWidth) where countdownFrameWidth = max(textWidth+16, 72); timer no countdown: scaled factor 0.46/0.52/0.38 with extra 18/24/12; reminder: max(base, 16 + ring/digital/minutes width); caps lock label: factor 0.4 extra 12; focus: base; recording: min(base, max(38, min(base*0.6, min(base-6, 52)))); extension: trailingWidth up to base + center*0.6; shelf: base) (:1554-1636); total width = wingBaseWidth + effectiveCenterWidth + rightWingWidth; HStack(spacing 0) { ZStack(bottomTrailing) artwork (RoundedRectangle radius 4, or 4/3 for landscape art; matchedGeometryEffect 'albumArt') + badge circle (size max(13, artwork*0.36), black fill, icon at 0.5-0.55 of badge, shadow black 0.35 r3 y1, offset (0.2,0.25)*badge) .frame(wingBaseWidth x notchContentHeight) | Rectangle black effectiveCenterWidth x notchContentHeight with inline-sneak-peek overlay (marquee title leading 8 / artist trailing 8, Spacer(minLength: closedWidth)) | right wing .frame(rightWingWidth x notchContentHeight) }.frame(width: notchWidth, height: notchContentHeight).frame(height: outerHeight). Spectrum: Rectangle 50 wide filled with avgColor (or gray) spectrogram gradient, masked by AudioVisualizerView(width visualizerBarCount*4, height 12), matchedGeometryEffect 'spectrum' (:1753-1769); hover play/pause overlay RoundedRectangle r8 black 0.24, icon 16 semibold, padding h14 v6, blur 2.4 (:1771-1804). DynamicIslandFaceAnimation (showNotHumanFace idle): sideSize = effectiveClosedNotchHeight - 12; HStack { clear sideSize^2 | black Rectangle width closedNotchSize.width - 20 | IdleAnimationView sideSize^2 }.frame(height: closed + (hover ? 8 : 0)) (:1375-1390). Closed-notch hit area for the top-edge checks: height = max(closedHeight + (hover ? 8 : 0), recordingHUD h) + 6 + pinned-lyrics reserved; width = max(closedWidth + (hover ? 8 : 0), 96, recording w) + 24; x = screen.midX - w/2 + menuBarClearanceOffset (:2407-2428).

### Animations

Hover swell uses .animation(.bouncy.speed(1.2), value: isHovering) on the whole shell (ContentView.swift:694-711). Secondary wing swaps .animation(.smooth(duration 0.25), value: secondary.id) with .contentTransition(.symbolEffect(.replace)) on badge and wing (:1437-1440, 1512-1517). Closed live-activity swap transition: insertion opacity + scale 0.965 with spring(response 0.34, damping 0.88); removal opacity + scale 0.92 with .smooth(0.22) (:382-391). Download/LocalSend activities use .blurReplace with interactiveSpring(dampingFraction 1.2) (:1147,1150); shelf inline .opacity .smooth(0.25) (:1168); idle face .interactiveSpring on isPlayerIdle (:1170). Waveform hover overlay .smooth(0.16); play state .smooth(0.2).

### State and timing

Closed content priority chain (ContentView.swift:1109-1176): battery HUD > inline HUD (volume/brightness/etc when inlineHUD) > caps lock > music (with secondary) > timer > reminder > recording > download > LocalSend > DND > privacy > extension standalone > shelf count > idle face > header (open) > clear placeholder.

### Data sources and APIs

Public: NSScreen.auxiliaryTopLeftArea / auxiliaryTopRightArea (REA imports confirm the Swift getters $sSo8NSScreenC6AppKitE20auxiliaryTopLeftAreaSo6CGRectVSgvg / ...TopRightArea...), NSScreen.safeAreaInsets, NSScreen.frame/visibleFrame. hideOnClosed source: FullscreenMediaDetector using MacroVisionKit (SwiftPM, TheBoredTeam/MacroVisionKit 0.1.0) + public AX attribute kAXFullScreen check with 500 ms debounce after activeSpaceDidChange / didChangeScreenParameters; honours hideNotchOption (.always / .nowPlayingOnly default / .never) (observers/FullscreenMediaDetection.swift:28-140).

### Settings

notchHeightMode (WindowHeightMode, .matchRealNotchSize; raw 'Match real notch height'/'Match menubar height'/'Custom height'); nonNotchHeightMode (.matchMenuBar); notchHeight (CGFloat 32); nonNotchHeight (CGFloat 32); closedNotchWidth (150); customizePhysicalNotchWidth (false); enableFullscreenMediaDetection (true); hideNotchOption (.nowPlayingOnly); showNotHumanFace (false); selectedIdleAnimation (nil); useMusicVisualizer (true); visualizerBarCount (4); coloredSpectrogram (true); showSongMetadataInClosedNotch (false).

### Implementation notes

NotchIsland's NotchGeometryResolver should adopt: closed width = screen width - aux areas + 4; closed height = safeAreaInsets.top; wings = (closedHeight-12) squares flanking a black centre of notch width; hover adds 8 both axes. Keep effectiveClosedNotchHeight=0 only for non-notch displays. ~250 LOC for the closed layout container (without the live activities themselves).

### Key files

- `DynamicIsland/sizing/matters.swift`
- `DynamicIsland/ContentView.swift`
- `DynamicIsland/models/DynamicIslandViewModel.swift`
- `DynamicIsland/observers/FullscreenMediaDetection.swift`
- `DynamicIsland/helpers/ClosedMusicPairingVisibility.swift`

## Hover / open / close state machine, click handling, haptics

### Behaviour

Hovering the closed notch swells it immediately and, after the minimum hover duration (0.3 s default), opens it (if 'Open notch on hover' is on, or if a timer is active in tab mode which also jumps to the Timer tab). Clicking the closed notch opens it at once (works even at the exact top pixel through global/local mouse monitors). Moving the pointer off the open notch closes it after a 100 ms grace unless a popover, drag, share sheet, sticky terminal, or first-launch hello is active. Parking the cursor on the top screen pixel does not count as leaving. Haptic 'alignment' feedback fires on hover-in/tap/gesture open, throttled to one per 300 ms. A keyboard shortcut toggles the notch and auto-closes 3 s later. Closing returns to Home (or Shelf if it has files and openShelfByDefault), unless 'Remember last tab' is on. On first launch the notch opens after 1 s with a glowing 'hello' stroke and closes after 3.5 s.

### Layout

Interaction surface = .contentShape(resolvedClipShape) + .onHover + .onTapGesture applied before the bottom shadow padding so only the shell is hit-testable (ContentView.swift:712-751). Right-click context menu: 'Settings' (:842-856).

### Animations

isHovering toggled inside withAnimation(.bouncy.speed(1.2)) (ContentView.swift:2325-2328, 2379-2381); shell .animation(hoverAnimation .bouncy.speed(1.2), value: isHovering); .animation(spring(response 0.42, dampingFraction 1.0, blendDuration 0) when opening, spring(response 0.45, dampingFraction 1.0) when closing (useModernCloseAnimation=true default), value: notchState); legacy (useModernCloseAnimation=false): single spring(0.42,1.0) + .transition(.blurReplace.animation(.interactiveSpring(dampingFraction: 1.2))) (:691-711). closeHello uses animationLibrary.animation = .spring(.bouncy(duration: 0.4)) for .notch style, else timingCurve(0.16,1,0.3,1, duration 0.7) (animations/drop.swift:34-40; DynamicIslandViewModel.swift:473-483). Timer-tab focus on hover: withAnimation(.smooth) currentView = .timer (:2355-2358). Clipboard tab auto-focus on open within 10 s of a copy: withAnimation(.smooth) (DynamicIslandViewModel.swift:86, 122-132).

### State and timing

handleHover (ContentView.swift:2303-2376): ignore hover-exit when shouldRetainHoverAtScreenTopEdge; cancel hoverTask; on enter start click monitors (only if openNotchOnHover, no connectivity HUD, no recording HUD), animate isHovering=true, haptic if closed; guard closed && !sneakPeek && !connectivityHUD && !recordingHUD && (openNotchOnHover || timer-tab focus) -> Task sleep minimumHoverDuration then re-check (still closed, hovering, not recording, no sneak peek, !isHoverOpenSuppressed) -> open. On exit: stop monitors, Task sleep 100 ms -> finishHoverExit. shouldPreventAutoClose = firstLaunch || any popover (battery/clipboard/colorPicker/stats/timer/perAppVolume/caffeinate/mediaOutput/reminder) || isAutoCloseSuppressed || shelf drag || clipboard drag || sharing preventNotchClose || (terminalStickyMode && terminal tab) (:2461-2479). Popover close -> recheck after 0.1 s and close if not hovering (:792-813; header uses vm.shouldRecheckHover toggled 0.1 s after popover dismissal). Sneak peek end -> if still hovering & closed & !isHoverOpenSuppressed reopen after 0.2 s (:821-830). coordinator.suppressHoverOpen(for: 0.35 s default) (DynamicIslandViewCoordinator.swift:245-251). Haptic throttle 0.3 s (:2482-2488). Shortcut toggle auto-close 3.0 s via DispatchWorkItem, cancelled by cancelPendingNotchAutoClose() when the header switches to the clipboard tab (DynamicIslandApp.swift:1061-1073, 1391-1394). vm.open(): compute target size, force window resize, set notchSize + notchState=.open, MusicManager.forceUpdate, focusClipboardTabIfNeeded (DynamicIslandViewModel.swift:395-419); vm.close(): sizes = closed, reset suppressions, choose shelf/home/last tab (:443-458); closeForLockScreen with .none animation (:460-469). First launch: onAppear runAfter(1) open (ContentView.swift:756-763); HelloAnimation 200x80 padding top 40 strokes HelloShape with rainbow gradient, lineWidth 8, blur 8, easeInOut 4 s (HelloAnimation.swift:92-111); closeHello after 3.5 s sets firstLaunch=false and closes (DynamicIslandViewModel.swift:471-483). notchState .open -> menuBarLayout.stopTracking, music control window suppressed; .closed -> startTracking, release after 0.24 s (ContentView.swift:903-912, 1009-1020).

### Data sources and APIs

Public: SwiftUI .onHover/.onTapGesture, .sensoryFeedback(.alignment, trigger:) (ContentView.swift:841; NSHapticFeedbackManager class is an import in the binary), NSEvent.addGlobalMonitorForEvents/addLocalMonitorForEvents(.leftMouseDown) (:2236-2246), NSEvent.mouseLocation, KeyboardShortcuts (sindresorhus 2.3.0) for toggleNotchOpen (DynamicIslandApp.swift:1042-1077).

### Settings

openNotchOnHover (Bool, true); minimumHoverDuration (TimeInterval, 0.3; slider 0...1 step 0.1); enableHaptics (Bool, true); extendHoverArea (Bool, false); useModernCloseAnimation (Bool, true; UI label 'Use simpler close animation'); openShelfByDefault (Bool, true); @AppStorage alwaysShowTabs (true), openLastTabByDefault (false; setting it true forces alwaysShowTabs=true, setting alwaysShowTabs false clears openLastTabByDefault), firstLaunch (true), hudReplacement (true); enableShortcuts; terminalStickyMode (false).

### Implementation notes

NotchIsland's NotchViewModel should implement: handleHover(hovering) -> cancel task; hovering: animate isHovering, haptic if closed, guard closed && openOnHover, Task sleep(minimumHoverDuration) then open; !hovering: Task sleep 100 ms then finishHoverExit (animate isHovering=false; close if open and !preventAutoClose). Add the top-edge retention check (mouse.y >= screen.maxY - 1.5 and inside hit rect). ~200 LOC.

### Key files

- `DynamicIsland/ContentView.swift`
- `DynamicIsland/models/DynamicIslandViewModel.swift`
- `DynamicIsland/DynamicIslandViewCoordinator.swift`
- `DynamicIsland/animations/drop.swift`
- `DynamicIsland/animations/HelloAnimation.swift`

## Two-finger scroll / pan gestures (open, close, skip) and gestureProgress stretch

### Behaviour

With gestures enabled, scrolling down (two fingers) over the closed notch stretches it live (wings widen, content blurs) and opens it once the accumulated scroll exceeds the sensitivity (200pt = Medium; 100 High, 300 Low); scrolling up over the open notch squeezes it and closes it. Horizontal swipes skip tracks on the Home tab (or on the closed music activity when hover-open is off). 'Reverse scroll gestures' swaps open/close directions; 'Reverse swipe gestures' swaps skip directions. Momentum scrolling is ignored so one flick does not fire twice.

### Layout

Open content blur radius = min(|gestureProgress|, 8) and opacity = min(|gp|*2, 0.8) once |gp| > 0.3 (ContentView.swift:1321-1322). Closed wings grow by gestureProgress/2 (:1398). Music control floating window rightWingWidth = max(0, effectiveClosedNotchHeight - (hover ? 0 : 12) + gestureProgress/2), spacing 36 (:2933-2942).

### Animations

gestureProgress = (translation / gestureSensitivity) * 20 (open) or * -20 (close), set with withAnimation(.smooth); reset to 0 with .smooth on .ended or when threshold crossed; shell has .animation(.smooth, value: gestureProgress) (ContentView.swift:2595-2648, 694-711). Close path also animates isHovering=false.

### State and timing

Open gesture only when closed and no recording HUD lock; close gesture only when open, not hovering calendar, not isScrollGestureActive (child views register scroll suppression tokens; DynamicIslandViewModel.swift:88-104). Skip gesture fires once per gesture when translation > sensitivity, guarded by canPerformSkipGesture (open home or closed music context, player not idle, not locked, no popovers) (ContentView.swift:2650-2689).

### Data sources and APIs

Public: SwiftUI DragGesture(minimumDistance: 0) + NSEvent.addLocalMonitorForEvents/addGlobalMonitorForEvents(.scrollWheel) in an NSViewRepresentable 'ScrollMonitor' (extensions/PanGesture.swift:36-182): threshold 4pt, noiseThreshold 0.2, verticalEdgeInset 4 (hit rect = view.bounds inset dy -4, no horizontal extension), de-dupe by event.timestamp, phase .ended or momentumPhase .ended -> action(accumulated, .ended), momentum events ignored, accumulated resets when direction flips; direction sign: right/down = +1. REA dispatch.json shows a ScrollMonitor Coordinator class (RulerScrollMonitor.Coordinator) proving the NSEvent-monitor pattern ships.

### Settings

enableGestures (Bool, true); closeGestureEnabled (Bool, true); gestureSensitivity (CGFloat, 200; slider 100...300 step 100 labelled High/Medium/Low); reverseScrollGestures (Bool, false); enableHorizontalMusicGestures (Bool, true); reverseSwipeGestures (Bool, false); musicGestureBehavior (.track).

### Implementation notes

Implement a ScrollWheelMonitor NSViewRepresentable with local+global monitors and the same accumulate/threshold logic; drive a @State gestureProgress and apply blur/opacity to tab content and +gp/2 to wing widths. ~150 LOC.

### Key files

- `DynamicIsland/extensions/PanGesture.swift`
- `DynamicIsland/ContentView.swift`

## Header (DynamicIslandHeader): tab area, notch spacer, action buttons, indicators, battery

### Behaviour

When open, the top row shows the tab icons on the left, a black bar hiding the hardware notch in the middle, and on the right a row of round black 30pt buttons: Mirror (web.camera, if showMirror), Clipboard (list.clipboard, when clipboard enabled and not in tab mode; opens panel/popover/tab per clipboardDisplayMode), Color picker (eyedropper), Timer (timer, popover mode only), Per-app volume (slider.vertical.3), Keep Awake (cup.and.saucer, yellow filled cup when active), Settings (gearshape), then a pulsing red recording dot and a Focus-mode capsule when active, and the battery. The whole row fades in and un-blurs 0.1 s after opening and is hidden/blurred when closed. In minimalistic mode only the battery pill is shown.

### Layout

HStack(spacing 0) (components/Notch/DynamicIslandHeader.swift:87-372): [1] HStack { TabSelectionView() if !minimalistic && (alwaysShowTabs || open || shelf has items) } .frame(maxWidth:.infinity, alignment:.leading) .opacity(closed ? 0 : 1) .blur(closed ? 20 : 0) .animation(.smooth.delay(0.1), value: notchState) .zIndex(2) .padding(8) (:88-101). [2] if open: Rectangle fill (minimalistic ? clear : (screen has notch ? black : clear)) .frame(width: min(closedNotchSize.width, 300)) .mask(NotchShape()) (default radii 6/14) (:103-112). [3] HStack(spacing 8) of buttons (:117-365): each Button(PlainButtonStyle) label = Capsule().fill(.black).frame(30x30).overlay(headerGlyph). headerGlyph = Image(systemName:).foregroundColor(white).font(.system(size: glyphSize, weight: .medium)).frame(20x20) with glyph sizes web.camera 14.5, list.clipboard 13, eyedropper 14.3, timer 14.4, gearshape 14.2, slider.vertical.3 13.8, cup.and.saucer(.fill) 14.0, default 14.4 (:58-84). Order: mirror, clipboard, color picker, timer(popover mode), per-app volume, caffeinate, settings, RecordingIndicator().frame(30x30), FocusIndicator().frame(30x30).transition(.opacity), battery. Popovers attach with arrowEdge .bottom. Battery (non-minimalistic): DynamicIslandBatteryView(batteryWidth: 30, ...) -> HStack { optional 'NN%' .callout white (fixed to '100%' width) ; BatteryView filled body height = 30*0.52 = 15.6, bodyRadius h*0.34, inset 1.5, terminal h*0.11 x h*0.36 spaced h*0.11; percent text size h*0.62 bold rounded black 0.82 } (DynamicIslandBattery.swift:81-126, 364-408); colours: low power yellow, <=20% red, charging/plugged/100 green, else white (:51-61). Minimalistic + not pill + showMinimalisticBatteryIndicator: MinimalisticBatteryView(bodyWidth 28, bodyHeight 14).padding(.trailing 4).transition(.opacity + .scale(0.85)) (:338-351). Row modifiers: .font(.system(.headline, design:.rounded)) .frame(maxWidth:.infinity, alignment:.trailing) .opacity/.blur(20)/.animation(.smooth.delay(0.1)) .zIndex(2) (:366-371). Whole header .foregroundColor(.gray) (:373). Status indicators are suppressed when settingsIconInNotch && clipboard && showClipboardIcon && showColorPickerIcon && enableTimerFeature all true (:435-441). RecordingIndicator: 6pt red dot (opacity 0.6->1.0) over a 10pt red 0.3 glow blurred 2 scaled 1.0->1.2, easeInOut 0.8 s repeatForever autoreverses, insertion/removal scale+opacity, .easeInOut(0.3) on isRecording (components/UI/RecordingIndicator.swift:21-76). FocusIndicator: Capsule black with focus icon .system(size 12, weight .semibold) in accent colour, 24x24 frame (components/UI/FocusIndicator.swift:21-35). Header sits in NotchLayout at .frame(height: max(24, effectiveClosedNotchHeight)) (ContentView.swift:1172-1173).

### Animations

Tab area and button row: .opacity(0)+.blur(20) when closed, .animation(.smooth.delay(0.1), value: vm.notchState) (DynamicIslandHeader.swift:97-99, 368-370). Timer/per-app-volume/caffeinate popover toggles wrapped in withAnimation(.smooth) (:216-218, 243-245, 271-273). Battery press scale 0.95 easeInOut 0.2 (DynamicIslandBattery.swift:409-410). Battery fill/colour .smooth(0.3).

### State and timing

Clipboard header button in .notchTab mode toggles coordinator.currentView between .clipboard and .home and cancels the shortcut auto-close; keyboard 'ToggleClipboardPopover' notification toggles the popover; popover dismissal flips vm.shouldRecheckHover 0.1 s later so an un-hovered notch closes (DynamicIslandHeader.swift:133-179, 375-406).

### Data sources and APIs

Public SwiftUI popovers; BatteryStatusViewModel (IOKit power sources — other subsystem); ClipboardPanelManager/ColorPickerPanelManager (other subsystems). Camera toggle uses AVFoundation authorization (DynamicIslandViewModel.swift:485-525).

### Settings

settingsIconInNotch (true); showMirror (false); enableClipboardManager (true); showClipboardIcon (true); clipboardDisplayMode (.panel; .panel/.popover/.separateTab/.notchTab); enableColorPickerFeature (true); showColorPickerIcon (true); colorPickerDisplayMode; enableTimerFeature (true); timerDisplayMode (.tab); enablePerAppVolume (false); showPerAppVolumeIcon (true); enableCaffeinate (true); showCaffeinateIcon (true); enableScreenRecordingDetection (true); showRecordingIndicator (true); enableDoNotDisturbDetection (true); showDoNotDisturbIndicator (true); showBatteryIndicator (hasBattery); showBatteryPercentage; showBatteryPercentInside (true); showMinimalisticBatteryIndicator (true).

### Implementation notes

Build HeaderView with the exact tree above; use SF Symbols with the per-glyph point sizes and 20pt frames inside 30pt black capsules spaced 8. Keep the black NotchShape-masked spacer of width min(closedWidth, 300) only on physical-notch displays. ~250 LOC.

### Key files

- `DynamicIsland/components/Notch/DynamicIslandHeader.swift`
- `DynamicIsland/components/UI/RecordingIndicator.swift`
- `DynamicIsland/components/UI/FocusIndicator.swift`
- `DynamicIsland/components/Live activities/DynamicIslandBattery.swift`

## Tab bar (TabSelectionView/TabButton) and tab switching animation

### Behaviour

Tabs appear as a row of SF Symbol icons (Home house.fill, Shelf tray.fill, Timer timer, Stats chart.xyaxis.line, Usage chart.bar.doc.horizontal, Notes note.text / Clipboard doc.on.clipboard, Terminal apple.terminal, extension tabs with their own symbol or puzzlepiece.extension) spaced 24pt apart; the selected one is white on a translucent capsule that slides between tabs (matched geometry); extension tabs tint the capsule and icon with their accent and add a glow. Switching tabs slides the content in from the right when moving to a later tab and from the left when moving back, with a cross-fade, while the window instantly resizes to the new tab's height.

### Layout

TabSelectionView body (components/Tabs/TabSelectionView.swift:116-152): HStack(spacing: 24) { ForEach tabs: TabButton(label, icon, selected) { select } .frame(height: 26) .foregroundStyle(selected ? (accent ?? .white) : .gray) .background { selected ? Capsule().fill((accent ?? Color(nsColor: .secondarySystemFill)).opacity(0.25)).shadow(color: (accent ?? .clear).opacity(0.4), radius: 8).matchedGeometryEffect(id: "capsule", in: animation) : Capsule().fill(.clear).matchedGeometryEffect(...).hidden() } }.clipShape(Capsule()). TabButton = Button(PlainButtonStyle) { Image(systemName: icon).contentShape(Capsule()) } with no explicit font or padding, so the capsule is the icon's intrinsic width x 26 (components/Tabs/TabButton.swift:25-38). Tab list built from Defaults (:65-115); home visible when minimalistic or media/calendar/mirror enabled (:162-167). Content host (ContentView.swift:1285-1323): ZStack { if open: Group{ switch currentView ... } .id(currentView) .transition(tabSwitchTransition) } .zIndex(1) .allowsHitTesting(open) .blur/.opacity by gestureProgress .animation(.smooth(duration: 0.3), value: coordinator.currentView). Home content pads itself 8 (0 minimalistic) (components/Notch/NotchHomeView.swift:990).

### Animations

tabSwitchTransition: forward -> asymmetric(insertion: .move(edge: .trailing)+.opacity, removal: .move(edge: .leading)+.opacity); backward -> mirrored (ContentView.swift:311-323), driven by .animation(.smooth(duration: 0.3), value: currentView) (:1323). Direction: coordinator.tabSwitchForward = newIdx >= oldIdx over tabOrder [.home,.shelf,.timer,.stats,.llmUsage,.colorPicker,.notes,.clipboard,.terminal,.extensionExperience] (DynamicIslandViewCoordinator.swift:102-119; 'tabSwitchForward' string confirmed in binary). Capsule slide via matchedGeometryEffect in the view's @Namespace with the ambient animation. Programmatic tab changes use withAnimation(.smooth) (coordinator handlers :260-314).

### State and timing

ensureValidSelection on appear picks the first tab if the current one is gone (TabSelectionView.swift:177-189). Minimalistic forces currentView = .home in didSet (coordinator :107-119). Timer tab auto-selected on hover-open when a timer is active (ContentView.swift:2334-2358). On close: shelf if non-empty && openShelfByDefault, else home unless openLastTabByDefault (DynamicIslandViewModel.swift:451-457). Stats tab entry resets statsSecondRowExpansion = 1 (coordinator :253-258).

### Data sources and APIs

Public SwiftUI; NSColor.secondarySystemFill.

### Settings

alwaysShowTabs (@AppStorage, true); openLastTabByDefault (@AppStorage, false); dynamicShelf (true); enableTimerFeature (true) + timerDisplayMode (.tab); enableStatsFeature (false); enableLLMUsageFeature (false); enableNotes (false); enableClipboardManager (true) + clipboardDisplayMode (.panel); enableTerminalFeature (false); enableThirdPartyExtensions/enableExtensionNotchExperiences/enableExtensionNotchTabs (true).

### Implementation notes

Reproduce with an enum of tabs ordered as above, a @Namespace capsule, HStack spacing 24, 26pt row, secondarySystemFill 25% capsule, and the direction-aware asymmetric move+opacity transition keyed by .id(tab). ~120 LOC.

### Key files

- `DynamicIsland/components/Tabs/TabSelectionView.swift`
- `DynamicIsland/components/Tabs/TabButton.swift`
- `DynamicIsland/DynamicIslandViewCoordinator.swift`
- `DynamicIsland/ContentView.swift`

## Dynamic Island pill mode on non-notch displays (externalDisplayStyle)

### Behaviour

On a display without a camera housing, choosing 'Dynamic Island' draws the closed state as a free-floating capsule 6pt below the top edge (closedNotchWidth 150 x menu-bar height) with fully round ends, and the open state as a 24pt-radius rounded rectangle with a soft shadow; 'Standard Notch' keeps the concave notch shape glued to the edge. Minimalistic + pill opens to 340x144 with 35pt corners.

### Layout

isDynamicIslandMode = shouldUseDynamicIslandMode(for: currentScreenName) (ContentView.swift:416-420; sizing/matters.swift:335-352). Pill padding chain: no top bleed; .padding(.horizontal, 14) .padding(.bottom, 14) .padding(.top, 6) after the shadow (ContentView.swift:683-687); root frame adds 28 width and 6+28 height (:864-865); window adds +28 width, +6 height and no bleed (DynamicIslandApp.swift:635-644). Header spacer is clear in pill mode (no physical notch) (DynamicIslandHeader.swift:106-107); header height nil in minimalistic pill (ContentView.swift:1173). Terminal tab inner radius helper uses pill radii (sizing/matters.swift:212-230). Closed music activity shows title • artist marquee in the centre on non-notch screens when showSongMetadataInClosedNotch (ContentView.swift:1485-1493).

### Animations

Pill radius animates with the same notchState spring (DynamicIslandPillShape animatableData).

### State and timing

Changing the style posts NotchHeightChanged -> adjustWindowPosition().

### Data sources and APIs

Public NSScreen.safeAreaInsets.top <= 0 test.

### Settings

externalDisplayStyle (ExternalDisplayStyle, .notch; raw values 'Standard Notch'/'Dynamic Island'; shown as 'External display style' in Behavior and 'Main screen style' in Appearance when the main screen has no notch; SettingsView.swift:1436-1448, 4946-4964).

### Implementation notes

NotchIsland: add a `shellStyle` resolved per screen; in pill mode replace NotchShape with a continuous RoundedRectangle, add top offset 6 and shadow inset 14 on both sides and bottom. ~60 LOC on top of the shell.

### Key files

- `DynamicIsland/sizing/matters.swift`
- `DynamicIsland/components/Notch/DynamicIslandPillShape.swift`
- `DynamicIsland/ContentView.swift`
- `DynamicIsland/enums/generic.swift`

## Minimalistic UI mode

### Behaviour

A reduced layout: no tab bar, no header buttons, only the minimalistic music player (plus optional battery pill) in a 420x180 island with 35pt opened corners, 12pt shadow padding; enabling it also forces the simpler close animation and locks the tab to Home.

### Layout

activeCornerRadiusInsets = (opened: (35,35), closed: (6,14)) (ContentView.swift:394-400); notchHorizontalPadding when open = 30 (:345-353); shadow padding 12 (sizing/matters.swift:172); base size 420x180 / 340x144 pill, +50 lyrics, + reminders, +94 external timer (:163-198); header: tabs hidden (DynamicIslandHeader.swift:89-94), buttons hidden (:118), battery pill 28x14 (:335-351); home content padding 0 (NotchHomeView.swift:990). Minimalistic player heights: 50 header + 10 progress + 56 controls + (lyrics 50) + top 14/15 + bottom 14/baseline (components/Notch/MinimalisticMusicPlayerView.swift:281-324).

### Animations

Same shell springs; settings toggle sets useModernCloseAnimation = true (SettingsView.swift:1159-1164).

### State and timing

Coordinator forces .home whenever minimalistic turns on or currentView changes (DynamicIslandViewCoordinator.swift:107-119, 274-281).

### Data sources and APIs

Defaults only.

### Settings

enableMinimalisticUI (Bool, false); showMinimalisticBatteryIndicator (true); showBatteryPercentInside (true).

### Implementation notes

Model as a layout variant enum {standard, minimalistic} feeding the size/radius/padding tables. ~40 LOC of tables.

### Key files

- `DynamicIsland/sizing/matters.swift`
- `DynamicIsland/ContentView.swift`
- `DynamicIsland/components/Notch/DynamicIslandHeader.swift`
- `DynamicIsland/components/Notch/MinimalisticMusicPlayerView.swift`

## Hide-until-hover on non-notch displays

### Behaviour

With 'Hide until hovered on non-notch displays' on, the closed island slides up off-screen on displays without a notch and slides back when the pointer touches the top edge; it also reveals itself while a HUD (volume/brightness/music sneak peek) or the connectivity HUD is showing.

### Layout

offset(y: shouldHideUntilHover && !isHovering ? -(closedNotchSize.height + pillTopOffset + shadowPadding + 10) : 0) applied after the bottom padding (ContentView.swift:752-755). shouldHideUntilHover = hideNonNotchUntilHover && isNonNotchScreen && closed && !sneakPeekVisibleOnThisScreen && !connectivityHUD (:444-450). Activation rect: width closedWidth + 16, height max(closedHeight + 10, 14), x centred + menuBarClearanceOffset, y at screen top (:2129-2149).

### Animations

Offset animates with the hover .bouncy.speed(1.2) animation (value: isHovering).

### State and timing

Polling task started in onAppear, cancelled in performViewTeardown (ContentView.swift:895, 2153-2165).

### Data sources and APIs

Polling Task: every 50 ms while hidden-edge polling is needed, 100 ms while hovering with interactions, else 1000 ms; compares hiddenHoverActivationContainsMouse(NSEvent.mouseLocation) to isHovering and calls handleHover, and also detects stale hover (pointer no longer inside window/closed hit area) to finishHoverExit (ContentView.swift:2167-2208). Public NSEvent.mouseLocation.

### Settings

hideNonNotchUntilHover (Bool, false).

### Implementation notes

Add a lightweight Task-based poller started on appear and cancelled on teardown; only poll at 50 ms when hidden. ~60 LOC.

### Key files

- `DynamicIsland/ContentView.swift`

## Menu bar clearance for closed live activities (MenuBarLayout)

### Behaviour

When a closed live activity's left wing would overlap the frontmost app's menu titles, the closed content shifts right (never past the screen's right edge) leaving an 8pt gap, and the hover/click hit areas move with it. Only when Accessibility is granted; otherwise no shift.

### Layout

menuBarClearanceOffset = MenuBarLayout.clearanceOffset(contentWidth: closedContentWidth (measured via GeometryReader background), screenFrame, menusRightEdge, gap 8): contentLeft = midX - w/2; overlap = (menusRightEdge + gap) - contentLeft; return min(max(overlap,0), max(0, maxX - (contentLeft + w))) (managers/MenuBarLayout.swift:53-69; ContentView.swift:1038-1052, 1268-1274). Applied as .offset(x:) on the closed content VStack except during the connectivity HUD (ContentView.swift:1281).

### Animations

.animation(.smooth(duration: 0.25), value: menuBarClearanceOffset) (ContentView.swift:1282).

### State and timing

startTracking when closed/on appear, stopTracking when open; appMenusRightEdge nil when untrusted / no menu bar / timeout.

### Data sources and APIs

Public Accessibility API: AXIsProcessTrusted, AXUIElementCreateApplication(pid), AXUIElementSetMessagingTimeout 0.25 s per element, kAXMenuBarAttribute, kAXChildrenAttribute, kAXPositionAttribute/kAXSizeAttribute via AXValueGetValue; right edge = max(origin.x + width) over menu items; whole scan deadline 1 s; refresh on NSWorkspace.didActivateApplicationNotification + 3 s poll timer, run off-main with Task.detached(.utility); tracked only while the notch is closed (start/stop counted) (MenuBarLayout.swift:74-187). REA imports confirm _AXIsProcessTrusted, _AXUIElementCreateApplication, _AXUIElementCopyAttributeValue in the shipped binary.

### Settings

None (depends on Accessibility permission).

### Implementation notes

Port as an @MainActor ObservableObject with the same AX scan; keep it optional (nil = no constraint). ~150 LOC.

### Key files

- `DynamicIsland/managers/MenuBarLayout.swift`
- `DynamicIsland/ContentView.swift`

## Show on all displays and screen selection

### Behaviour

By default one island on the preferred display (falls back to the main display when 'Automatically switch displays' is on; hidden with alpha 0 if the preferred display is absent). 'Show on all displays' creates an island per connected screen, each with its own view model, hover state and notch geometry; HUDs/sneak peeks target a specific screen; the keyboard toggle acts on the island under the mouse.

### Layout

AppDelegate keeps windows: [NSScreen: NSWindow] and viewModels: [NSScreen: DynamicIslandViewModel] (DynamicIslandApp.swift:104-107); adjustWindowPosition creates/removes per-screen windows, positions them, and re-closes closed view models (:1578-1643). isPointInsideNotchWindow checks all windows when showOnAllDisplays (ContentView.swift:2430-2441). isSneakPeekVisibleOnCurrentScreen compares sneakPeek.targetScreenName (:434-440); battery HUD likewise (:495-502).

### Animations

Alpha flips 0 -> 1 around repositioning (changeAlpha) without animation.

### State and timing

showOnAllDisplaysChanged -> cleanupWindows(shouldInvert:true) then recreate (DynamicIslandApp.swift:1007-1022).

### Data sources and APIs

Public NSScreen.screens / localizedName / NSScreen.main; NSApplication.didChangeScreenParametersNotification.

### Settings

showOnAllDisplays (false); automaticallySwitchDisplay (true); preferred_screen_name (@AppStorage); 'Show on a specific display' picker disabled when showOnAllDisplays (SettingsView.swift:1201-1225).

### Implementation notes

NotchIsland already has a single panel controller; generalise to a dictionary keyed by NSScreen with a per-screen view model. ~120 LOC.

### Key files

- `DynamicIsland/DynamicIslandApp.swift`
- `DynamicIsland/DynamicIslandViewCoordinator.swift`
- `DynamicIsland/ContentView.swift`

## LiquidGlassBackground (private NSGlassEffectView wrapper) — used by HUD/lock-screen surfaces, not the notch shell

### Behaviour

Provides Apple's Liquid Glass material (variant 0-19, default 11) behind lock-screen music/timer widgets, OSD/vertical HUDs, LocalSend picker and a settings preview. The notch island itself is plain .black.

### Layout

NSViewRepresentable: container NSView hosting an NSClassFromString("NSGlassEffectView") instance pinned to all edges; sets cornerRadius via KVC, calls private selector set_variant: with the variant int, sets contentView = NSHostingView(content); walks sublayers for CABackdropLayer and sets windowServerAware = true and scale = 1.0, re-applying via KVO; fallback NSVisualEffectView(.underWindowBackground) (helpers/LiquidGlassBackground.swift:23-271).

### Animations

None.

### State and timing

Backdrop setup scheduled 50 ms after view attaches/layout.

### Data sources and APIs

PRIVATE: NSGlassEffectView class, set_variant: selector, CABackdropLayer windowServerAware/scale keys. REA: strings 'NSGlassEffectView' and 'windowServerAware' present in the binary; dispatch.json shows class _TtC5AtollP33_..._LiquidGlassContainerView : NSView with layout, viewDidMoveToWindow, observeValueForKeyPath:ofObject:change:context:, removeFromSuperview; imports include _NSClassFromString, _NSSelectorFromString and the NSVisualEffectView class (fallback).

### Settings

lockScreenMusicLiquidGlassVariant, lockScreenTimerLiquidGlassVariant, verticalHUDLiquidGlassVariant, osdLiquidGlassVariant, localSendDevicePickerLiquidGlassVariant (default .v11).

### Implementation notes

Not needed for the notch shell. If NotchIsland wants glass on macOS 26, use public .glassEffect; otherwise NSVisualEffectView. Avoid the private class.

### Key files

- `DynamicIsland/helpers/LiquidGlassBackground.swift`

## Drag-to-open shelf detector and hello/first-launch behaviour (shell-level extras)

### Behaviour

Dragging files over the closed island opens it straight to the Shelf tab; when the drag leaves without dropping the island closes again. First launch plays a welcome sound and shows an onboarding window plus the glowing 'hello' stroke in the notch.

### Layout

dragDetector = Color.clear full-size .contentShape(Rectangle()).onDrop(of: [.data], isTargeted: $vm.dragDetectorTargeting) placed as the root's .background (ContentView.swift:871, 2064-2092); anyDropZoneTargeting = dropZoneTargeting || dragDetectorTargeting (DynamicIslandViewModel.swift:164-169).

### Animations

Opens with the standard open spring; closes via vm.close() unless shouldPreventAutoClose.

### State and timing

Drop detector disabled when locked or minimalistic.

### Data sources and APIs

Public SwiftUI onDrop; AudioPlayer plays 'dynamic.m4a' (DynamicIslandApp.swift:1543-1546).

### Settings

dynamicShelf (true); firstLaunch (@AppStorage true).

### Implementation notes

NotchIsland's shelf is clipboard-based; keep the onDrop detector as the open trigger. ~30 LOC.

### Key files

- `DynamicIsland/ContentView.swift`
- `DynamicIsland/DynamicIslandApp.swift`

## Unknowns

- TabButton has no padding or explicit font in source (icon intrinsic width x 26 capsule); whether the shipped 2.3.3 build adds horizontal padding could not be verified visually — the REA UI probes (ui-probe/ui-closed/ui-hover.json) failed with window-mismatch and shot-*.png captured an unrelated browser window, so no Atoll screenshot evidence exists in rea-out.
- Exact on-screen point values of NSScreen.auxiliaryTopLeftArea/auxiliaryTopRightArea and safeAreaInsets.top on the user's machine (determines closed width/height) were not measured; a runtime probe of the target Mac is needed.
- NotchHomeView/other tab bodies (music player, calendar, shelf, stats, notes, terminal) are out of this subsystem; only their outer padding (8pt, 0 in minimalistic) and height contributions were captured.
- Recording HUD layout (helpers/RecordingHUDLayout.swift), connectivity HUD metrics, inline HUD and battery temporary HUD geometry were referenced by the shell but not spec'd in detail here (other subsystems).
- MusicControlWindowManager floating control window (musicControlWindowEnabled, default false) — spacing 36, pause grace 5 s, resume delay 0.24 s — belongs to the music subsystem.
- The 'alwaysShowTabs', 'openLastTabByDefault', 'firstLaunch' and 'preferred_screen_name' values use @AppStorage (UserDefaults standard) rather than Defaults; their presence in the binary strings was confirmed only for openLastTabByDefault and preferred_screen_name.
- Whether the shipped binary still includes the commented-out SkyLightWindow (.moveToSky) path for the notch window cannot be told from imports alone (SkyLightWindow is also used by LockScreenTimerWidgetManager).

## Critic pass

Missing from the spec:

- [Paths below are relative to /private/tmp/claude-501/-Users-a-dynamic-iland-dynamic-island/b501c539-18bc-4747-a9c4-d824916ad38f/scratchpad/atoll-clone/Atoll/DynamicIsland/. The spec text I received was truncated after the 'LiquidGlassBackground' feature, so anything the original spec listed after that point was not reviewed.]
- Closed-notch floating music-control flyout window (setting musicControlWindowEnabled, Bool, default false, Constants.swift:1087; UI toggle SettingsView.swift:3360-3372, disabled in minimalistic or when showStandardMediaControls is off). managers/MusicControlWindowManager.swift:25-62 + managers/FlyoutWindowPresenter.swift + managers/FlyoutFrameCalculator.swift + components/Music/MusicControlOverlay.swift. Window: NSPanel [.borderless,.nonactivatingPanel], isOpaque false, clear background, hasShadow false, level = NSWindow.Level(CGShieldingWindowLevel()), collectionBehavior [.canJoinAllSpaces,.stationary,.fullScreenAuxiliary], initial alpha 0, initial size 240x68, registered with ScreenCaptureVisibilityManager (FlyoutWindowPresenter.swift:252-284); SkyLightOperator.shared.delegateWindow(window) on first present (:74-77). Placement (FlyoutFrameCalculator.swift:28-56): originX = screen.midX + notchWidth/2 + rightWingWidth + spacing, clamped to [minX+8, maxX-contentWidth-8]; originY = screen.maxY - contentHeight; metrics from ContentView.swift:2933-2942: notchHeight = max(closedNotchSize.height, effectiveClosedNotchHeight), notchWidth = closedNotchSize.width + (hover ? 8 : 0), rightWingWidth = max(0, effectiveClosedNotchHeight - (hover ? 0 : 12) + gestureProgress/2), cornerRadius = closed bottom radius (14), spacing 36. Animations: appear slides in from behind the notch (start x = notchRightEdge - width) over 0.24 s with alpha 0->1; metric refresh 0.16 s; hide retreats behind notch + fades over 0.18 s (FlyoutWindowPresenter.swift:123-215, 317-333). Overlay (MusicControlOverlay.swift:41-165): HStack spacing 18 of three FloatingMediaButtons; buttonSide = clamp(notchHeight*0.94, max(30, h*0.8), max(h+2, 32)); playPauseSide = min(side+8, h+4); buttonCornerRadius = max(cornerRadius-8, side*0.28); play/pause radius max(buttonRadius+2, side*0.32); windowCornerRadius = max(cornerRadius-6, 12) black continuous RoundedRectangle; padding horizontal 18 / vertical max(8, h*0.12); frame height = notchHeight, minWidth side*3.2; icons .system(size: side*0.48, weight .semibold), side buttons white 0.9 (0.35 disabled), hover fill white 0.18 easeOut 0.18; press effects: nudge +/-8pt spring(0.16,0.72) then back spring(0.26,0.8) after 0.12 s; wiggle +/-11 deg spring(0.18,0.52) then spring(0.32,0.76) after 0.18 s; icons backward.fill/forward.fill (track) or gobackward.10/goforward.10 (musicSkipBehavior .tenSecond). Visibility rules (ContentView.swift:2691-2971): shown only when closed, standard media controls active (not minimalistic), music live activity enabled, not hideOnClosed/locked/deferred-after-unlock, and playing or within a 5 s pause grace (musicControlPauseGrace, :306); suppressed while open and released 0.24 s after close (musicControlResumeDelay, :307); re-synced on hover with 0.05 s (enter) / 0.12 s (exit) delay (:981-985), on gestureProgress change (0.05 s), closedNotchSize/effectiveClosedNotchHeight change. MediaControlsStateCoordinator (DynamicIslandApp.swift:1722-1815) caches and force-disables this flag (cachedMusicControlWindowPreference) whenever showStandardMediaControls is off and restores it later.
- Recording HUD closed-notch sizing (helpers/RecordingHUDLayout.swift:21-119): presentations compact (+132 width), inline (+176 width), expanded (+140 width, +70 height) added to closedNotchSize.width / effectiveClosedNotchHeight; visible only when closed && enableScreenRecordingDetection && showRecordingIndicator && !hideOnClosed && isRecording && !closedMusicPairingEligible (:102-107); expansion only when recordingControlMode == .withStopButton && recordingManager.shouldShowStopControlsInHUD && hovering && !isScreenSharingAppActive, style from recordingHoverStyle (.default -> expanded, .inline -> inline) (:49-60). AppDelegate sizes the window with expanded: true (DynamicIslandApp.swift:600-615). While visible: hover-open, tap-open, scroll-open and the click monitors are all locked (ContentView.swift:719-720, 2213, 2312, 2339, 2597).
- Network connectivity HUD closed-notch sizing (components/Network/NetworkConnectivityHUD.swift:13-45): .noConnection -> closedNotchSize.width + 210 x effectiveClosedNotchHeight + 125; connected wifi/hotspot -> max(closedNotchSize.width + 220, 450) x closedNotchSize.height; accent Color(red 0.36, green 0.88, blue 0.42) (:55). While presented the shell drops notchHorizontalPadding to 0 (ContentView.swift:661), suppresses the menu-bar clearance offset (:1281), blocks hover-open/tap/click monitors (:719, 2212, 2338), and the first-launch hello is skipped (:757).
- AirPods listening-mode inline sneak-peek width: InlineHUD.airPodsListeningModeWidth = (minimalistic ? 36 : 44) + gestureProgress/2 + max(closedWidth - 20, 0) + (minimalistic ? 136 : 180) + gestureProgress/2 (components/Live activities/InlineHUD.swift:120-129), plus 2*notchHorizontalPadding, used for dynamicNotchSize when a .bluetoothAudio sneak peek with value < 0 and a listening-mode symbol is showing (ContentView.swift:124-146). AppDelegate sizes that case to the fixed 460 instead (DynamicIslandApp.swift:498-518).
- ShelfInlineLiveActivity closed layout (components/Shelf/Views/ShelfInlineLiveActivity.swift:26-56): HStack(spacing 0) { tray.fill .system(13, .medium) white in 24pt leading slot | black Rectangle width = closedNotchSize.width | item count .callout rounded bold white in 24pt trailing slot, .contentTransition(.numericText) .smooth(0.3) } .frame(height: effectiveClosedNotchHeight). Shown when closed, shelf non-empty, no expanding view, not hideOnClosed/locked/minimalistic (ContentView.swift:1166-1168). The same count badge is reused as the music secondary wing (.shelf) with icon tray.and.arrow.down.fill at badge*0.50 (:1675-1678, 1737-1744).
- Idle animation details (DynamicIslandFaceAnimation -> components/IdleAnimationView.swift:24-88): Lottie via LottieUI LottieView(LUStateData loadedFrom url, speed, loopMode) with per-animation transform config (cropWidth*scale x cropHeight*scale frame, offsetX/Y, rotation, opacity, paddingBottom, .clipped()); Defaults keys customIdleAnimations ([CustomIdleAnimation], []), selectedIdleAnimation (nil), animationTransformOverrides ([:]) (Constants.swift:1032-1034); shown only when !isPlaying && isPlayerIdle && showNotHumanFace && !hideOnClosed && no expansion (ContentView.swift:1169-1170). Settings toggle label 'Idle Animation' (SettingsView.swift:5187-5190) plus IdleAnimationsSettingsSection.
- Pinned lyrics reservation under the closed notch (components/Music/PinnedLyricsView.swift:25-108): when enableLyrics && pinLyricsWhenClosed (Bool, false, Constants.swift:1512) && closed && !hideOnClosed && !locked && isPlaying && lyricsAvailability == .timed, the closed content gets bottom padding rowHeight*pinnedLyricContext.rawValue + gap 4 where rowHeight = ceil(ascender - descender + leading of 10pt medium system font) + 1; rows are 10pt medium, lineLimit 1, lyricSweep sung white / unsung tint 0.55 / idle white 0.45, horizontal padding 10, animated .smooth(0.28) (height) and .smooth(0.18) (slots), hidden while a sneak peek or connectivity HUD shows. This reserved height is added to the closed-notch hit rect (ContentView.swift:2418-2420).
- Sneak-peek rows inside NotchLayout below the closed content (ContentView.swift:1178-1261): standard style only; SystemEventIndicatorModifier with padding bottom 10 / leading 4 / trailing 8; music row = HStack { Image(music.note); MarqueeText('title - artist', gray, minDuration 1) } .padding(.bottom 10); timer row same with timer icon and timerColor; reminder/extension rows = RoundedRectangle(r2) 8x12 colour chip + MarqueeText (frameWidth = geo.width - 14) padding bottom 10; whole closed stack gets .fixedSize() when shouldFixSizeForSneakPeek() (:1264-1267, 2978-3001). Inline HUD transitions: capsLock -> .move(.trailing)+.opacity, else .opacity (:1127-1134).
- Shelf drag detector (ContentView.swift:2064-2092, attached as root .background at :871): when dynamicShelf && !minimalistic && !locked, a full-window Color.clear .onDrop(of: [.data]) sets vm.dragDetectorTargeting; when anyDropZoneTargeting becomes true while closed -> currentView = .shelf and open; when it becomes false -> close unless vm.dropEvent or shouldPreventAutoClose(). anyDropZoneTargeting = dropZoneTargeting || dragDetectorTargeting (DynamicIslandViewModel.swift:164-169).
- Sticky-terminal outside-click monitor (ContentView.swift:2260-2298, 764-790, 831-839, 900-902): whenever the notch is open on the Terminal tab and not hovered, a global leftMouseDown monitor closes the notch on any click outside the window (isPointInsideNotchWindow); installed on notchState/currentView/terminalStickyMode changes and after finishHoverExit when terminalStickyMode is on (:2385-2391). Default terminalStickyMode false (Constants.swift:1315).
- Keyboard shortcut defaults (Shortcuts/ShortcutConstants.swift:33-34): toggleNotchOpen = Command+Shift+I, toggleTerminalTab = Control+Backtick; enableShortcuts (Bool, true, Constants.swift:1397) gates all handlers (DynamicIslandApp.swift:1044, 1079). toggleSneakPeek shortcut shows a 3 s music sneak peek (:1031-1040). The toggle acts on the view model of the screen under the mouse when showOnAllDisplays (:1046-1059).
- Settings interlocks not in spec: turning Open-notch-on-hover off forces enableGestures = true (SettingsView.swift:1337-1341) and the 'Enable gestures' toggle is disabled while openNotchOnHover is off (:1350); the gesture footer states two-finger swipe down opens only when hover-open is disabled (:1400); 'Remember last tab' sits in Notch behavior (:1422); changing minimumHoverDuration, externalDisplayStyle, closedNotchWidth, customizePhysicalNotchWidth or any height mode posts NotchHeightChanged -> adjustWindowPosition (:1284-1319, 1432-1444, 5436-5446); hideNotchOption picker writes enableFullscreenMediaDetection = (option != .never) (:3633-3635) with labels 'Always hide in fullscreen' / 'Hide only when NowPlaying app is in fullscreen' / 'Never hide'; an unused minimalisticRange 250...600 is declared (:5416); alwaysShowTabs set false also resets currentView to .home when TrayDrop is empty or openShelfByDefault is off (DynamicIslandViewCoordinator.swift:134-143); turning enablePerAppVolume/enableCaffeinate/enableTimerFeature off or timerDisplayMode to .tab force-dismisses the matching header popover (DynamicIslandHeader.swift:407-430).
- Window resize trigger list (DynamicIslandApp.swift:839-892): debounced 150 ms resize (debouncedUpdateWindowSize, :147-159) on enableStatsFeature, showCpu/Memory/Gpu/Network/DiskGraph, openNotchWidth, enableTerminalFeature, terminalMaxHeightFraction, ReminderLiveActivityManager.activeWindowReminders, TimerManager.activeSource/isTimerActive; shouldAnimateResize returns false when minimalistic && reminders non-empty (:689-694) although the animated flag is never acted on (:670-687). resizeWindow skips the AppKit transaction when the frame is unchanged even for forced resizes (:685).
- Three size calculators disagree and the spec should name the authority: (1) AppDelegate.calculateRequiredNotchSize (DynamicIslandApp.swift:479-598) = connectivity HUD > inline sneak 460 x effectiveClosedHeight (no shadow padding) > recording HUD > battery HUD > base with timer 250 / notes preferredHeight / clipboard 240 / terminal fraction, then inline lyrics, stats, + shadow padding; (2) ContentView.dynamicNotchSize (ContentView.swift:110-241) adds extension-tab preferredHeight clamped to [base, base+132] and the minimalistic extension estimate, and uses statsRowCount (4+ graphs -> +132 flat, no progress); (3) DynamicIslandViewModel.calculateDynamicNotchSize (DynamicIslandViewModel.swift:421-441) only handles notes/clipboard, inline lyrics and stats progress - vm.open() force-resizes the window with this smaller size (:395-419) and relies on the coordinator.currentView onChange / debounced paths to grow the window for timer and terminal tabs. ContentView.swift:300-302 dynamicNotchResizeAnimation is nil (placeholder).
- Lock/unlock and multi-display lifecycle details: unlock restore runs 1.0 s after com.apple.screenIsUnlocked (DynamicIslandApp.swift:317-324); hideWindowsForLock/restoreWindowsAfterLock are guarded by windowsHiddenForLock (:326-354); cleanupWindows invokes vm.onViewTeardown then NotchSpaceManager removal then window.close() (:356-375); every adjustWindowPosition ends with syncNotchSpaceMembership() (:1642) and activeSpaceDidChange re-applies pinnedCollectionBehavior + orderFrontRegardless (:396-406); automaticallySwitchDisplayChanged notification sets window.alphaValue = selectedScreen == preferredScreen ? 1 : 0 (:997-1005); adjustWindowPosition in single-window mode also resets vm.notchSize = getClosedNotchSize and calls vm.close() if closed (:1627-1638); per-screen windows are keyed by NSScreen with CGRect made Hashable (:1709-1720); previousScreens snapshot taken at launch (:1101). Notification names also include 'automaticallySwitchDisplayChanged' (:1706).
- Screen-capture hiding scope: ScreenCaptureVisibilityManager registers both the notch panel (DynamicIslandWindow.swift:60) and the flyout panel (FlyoutWindowPresenter.swift:279) with scope .entireInterface; ScreenCaptureScope enum {panelsOnly, entireInterface} exists but the scope is ignored when applying sharingType (ScreenCaptureVisibilityManager.swift:23-26, 65-68).
- Terminal-tab clip constants (sizing/matters.swift:202-244): notchTerminalContentEdgePadding = (top 4, horizontal 8, bottom 8), notchTerminalInnerTextInset = 6, notchTerminalBottomCornerRadii(outerBottom, innerBottom = max(0, outerBottom - 8)) where outer is the shell's current bottom radius (pill: 24 / 35 minimalistic open, max(closedHeight/2, 16) closed; notch: opened.bottom when open && cornerRadiusScaling else closed.bottom 14); consumed by components/Notch/NotchTerminalView.swift:95-166.
- Other sizing constants in matters.swift not cited: MusicPlayerImageSizes cornerRadiusInset opened 13 / closed 4 and size 90x90 open / 20x20 closed (:379-382) - the closed artwork clip radius 4 (4/3 for landscape art) in the wing comes from here; legacy downloadSneakSize 65x1 and batterySneakSize 160x1 (:27-28) appear unused; enabledStandardTabCount does NOT count the LLM Usage tab or extension tabs (:101-135) so the 640/690/770 ladder ignores them; openNotchSize / maxAllowedNotchWidth() / shouldUseDynamicIslandMode(nil) all fall back to NSScreen.main rather than the window's own screen (:69-95, 335-352), so all per-screen windows share one open width.
- Home tab root modifiers that belong to the shell contract (components/Notch/NotchHomeView.swift:987-990): .transition(.opacity.animation(.smooth.speed(0.9)).combined(with: .move(edge: .top))), .blur(radius: closed ? 30 : 0), .padding(minimalistic ? 0 : 8). Also HoverButton (components/HoverButton.swift:46-106: 30pt (.medium) / 40pt (.large) capsule, hover fill gray 0.2 .smooth(0.3), nudge spring(0.2,0.55)->spring(0.28,0.72) after 0.16 s, wiggle +/-10 deg spring(0.18,0.5)->spring(0.32,0.72) after 0.18 s) and ParallaxMotionModifier (extensions/View+Parallax3D.swift:24-81, intensity parallaxEffectIntensity default 6.0, interactiveSpring(0.1,0.5) follow / spring(0.35,0.6) release, scale 1.02 on hover) are used by the home/minimalistic players, not the shell.
- Header behavioural consequence worth stating: shouldSuppressStatusIndicators (DynamicIslandHeader.swift:435-441) is TRUE with factory defaults (settingsIconInNotch, enableClipboardManager, showClipboardIcon, showColorPickerIcon, enableTimerFeature all default true), so the header RecordingIndicator and FocusIndicator are hidden by default and only appear after the user turns one of those five settings off.
- Battery header view variants not in spec (components/Live activities/DynamicIslandBattery.swift): outlined body when showBatteryPercentInside == false (:149-183): thin-weight battery symbol white 0.5 at width batteryWidth+1, fill RoundedRectangle r2.5 width (level/100)*(w-6) height (w-2.75)-18 leading 2, 17x17 status glyph; filled body fillWidth = max((w-3)*fraction, 2) with bodyFill white 0.45 (:128-138); tapping (DragGesture minimumDistance 0) opens BatteryMenuView popover arrowEdge .bottom and vm.isBatteryPopoverActive = showPopupMenu && isHoveringPopover (:411-453). MinimalisticBatteryView (:187-260): HStack spacing 1.5, body RoundedRectangle r5 continuous fill batteryColor 0.3 with batteryColor.gradient fill, percent .system(bodyHeight*0.6, .heavy, .rounded) glyph black (white when charging), status glyph bodyHeight*0.42 .black, terminal height max(4, h*0.38).
- FullscreenMediaDetector nuances (observers/FullscreenMediaDetection.swift:73-145): Finder (com.apple.finder) is excluded; when Accessibility is not trusted every detector hit is treated as native fullscreen (:123); MacroVisionKit.configuration.includeSystemApps = true (:37); status is per-screen keyed by localizedName and logged with NSLog.
- hover-polling stale-hover path and lock gating: the 1 s/100 ms poll also ends a hover when the pointer has left the window (open) or the closed hit rect (ContentView.swift:2177-2186); interactionsEnabled = !isLocked removes contentShape/onHover/onTapGesture and all pan gestures entirely while locked (:337-339, 712-747); recordingManager.isRecording true stops the click monitors and false restarts them if still hovering (:986-992); vm.onViewTeardown provides deterministic teardown because .onDisappear is unreliable for borderless panels (:895-898, 2151-2165).
- extendHoverArea precise effect (ContentView.swift:355-364): it only removes the 10pt zeroHeightHoverPadding under the shell while the notch is open; it has no effect unless effectiveClosedNotchHeight == 0 (non-notch display hidden by fullscreen detection).
- Dead code in the subsystem directories that NotchIsland should not port: components/Notch/DynamicIslandExtrasMenu.swift (70x70 r12 black large buttons, HStack spacing 20, shadow black 0.5 r10; unreferenced), components/Notch/ClipboardHistoryPopover.swift (280 wide, maxHeight 200, black 0.95, r12, stroke gray 0.2; unreferenced - ClipboardPopover is used instead), components/BottomRoundedRectangle.swift (unreferenced), components/Settings/EditPanelView.swift (only in a commented-out context-menu item, ContentView.swift:846-855), RecordingIndicatorLarge / RecordingIndicatorSubtle (RecordingIndicator.swift:114-183, unreferenced), DynamicIslandViewModel.isMouseHovering (:382-393, unreferenced), coordinator.optionKeyPressed (:164), NSScreen.screenWithMouse (extensions/MouseTracker.swift), BouncingButtonStyle (extensions/Button+Bouncing.swift), TabSelectionView's QuickShare state (TabSelectionView.swift:49-51), LiveActivityModifier (components/Live activities/LiveActivityModifier.swift).
- Other consumers of the shell shapes: components/LockScreen/LockScreenLiveActivityOverlay.swift:79-82 draws a lock-screen replica with DynamicIslandPillShape / NotchShape, and components/Live activities/DynamicIslandBattery.swift:603-605 clips the battery HUD surface with them; menu bar status item (menu/StatusBarMenu.swift:45-53, menubarIcon default true) is a separate NSStatusItem with a Quit item.
- Header spacer uses coordinator.selectedScreen (global) rather than vm.screen to decide black vs clear (DynamicIslandHeader.swift:106-107); with showOnAllDisplays every window's spacer follows the globally selected screen's notch presence. Also the header receives .environmentObject(vm) and listens to coordinator.shouldToggleClipboardPopover and the 'ToggleClipboardPopover' notification (:374-406).

Corrections:

- Terminal tab height: the spec's '40% of visible screen height (min 300)' is wrong in effect. Both ContentView.swift:207-210 and DynamicIslandApp.swift:577-579 compute min(screenHeight*fraction, max(300, screenHeight*fraction)), which always equals screenHeight*fraction; the 300pt floor is a no-op. screenHeight = NSScreen.main?.visibleFrame.height ?? 800.
- Header clipboard button visibility: spec says it appears 'when clipboard enabled and not in tab mode'. The condition is clipboardDisplayMode != .separateTab (DynamicIslandHeader.swift:133-135), so the button IS shown in .notchTab mode, where it toggles coordinator.currentView between .clipboard and .home and cancels the shortcut auto-close (:145-150). Only .separateTab hides it.
- Timer-tab focus on hover also requires !enableMinimalisticUI: shouldFocusTimerTab = enableTimerFeature && timerDisplayMode == .tab && timerManager.isTimerActive && !enableMinimalisticUI (ContentView.swift:2334); the spec omits the minimalistic exclusion.
- REA ScrollMonitor evidence is misattributed: dispatch.json contains two different coordinators, _TtCV5AtollP33_…13ScrollMonitor11Coordinator (PanGesture.swift's private ScrollMonitor.Coordinator) and _TtCV5AtollP33_…18RulerScrollMonitor11Coordinator (components/Timer/RulerTimerPicker.swift). The spec cites the Ruler one as proof of the notch gesture monitor; the PanGesture ScrollMonitor is confirmed directly and separately.
- SkyLightWindow is not dormant: the spec says .moveToSky()/delegateWindow are commented out (true for the notch panel, DynamicIslandApp.swift:432, 437), but SkyLightOperator.shared.delegateWindow is live for the closed-notch music-control flyout (managers/FlyoutWindowPresenter.swift:75) and for HUD/lock-screen windows (CustomOSDWindowManager.swift:200, CircularHUDWindowManager.swift:125, LockScreenLiveActivityWindowManager.swift:230, LockScreenTimerWidgetManager.swift:245, LockScreenWeatherPanelManager.swift:115, FullScreenArtworkWindowManager.swift:1237/1300/1396); dispatch.json confirms SkyLightWindow.SkyLightOperator, TopmostWindow, TopmostWindowController and NSWindowReadingView ship in the binary (package Lakr233/SkyLightWindow rev 4a7e8628, Package.resolved).
- NSGlassEffectView 'string present' and externalDisplayStyle 'raw strings confirmed in binary' are not verifiable from the five REA JSON files: macho.json imports contain no NSGlassEffectView symbol (it is looked up via _NSClassFromString, LiquidGlassBackground.swift:214) and neither dispatch.json nor artifact.json/graph.json contain the strings 'NSGlassEffectView', 'Standard Notch' or 'Dynamic Island'. What dispatch.json does confirm is the ObjC class _TtC5AtollP33_…LiquidGlassContainerView, the Swift type names LiquidGlassVariant and ExternalDisplayStyle, and the _NSClassFromString/_objc_msgSend imports. Downgrade both claims to 'inferred from source; type names confirmed'.
- Closed height on non-notch displays: the spec's '(24 default)' conflates two things. Defaults[.nonNotchHeight] defaults to 32 (Constants.swift:1012) and is used only in .matchRealNotchSize/.custom modes; the default mode .matchMenuBar (Constants.swift:1008-1011) uses the live menu-bar height screen.frame.maxY - screen.visibleFrame.maxY (matters.swift:434-436). 24 is merely the preset written to nonNotchHeight when the picker is switched to .matchMenuBar (SettingsView.swift:1305-1306).
- vm.open()/vm.notchSize is not the authoritative open size: DynamicIslandViewModel.calculateDynamicNotchSize (:421-441) omits timer 250, terminal and extension-tab heights (and the HUD overrides), yet vm.open() force-resizes the window with it (:395-405). The spec's 'vm.open(): compute target size, force window resize' should say the authoritative window size is AppDelegate.calculateRequiredNotchSize (DynamicIslandApp.swift:479-598) applied via updateWindowSizeForTabSwitch (:474-477) and the 150 ms debounced path, and the SwiftUI frame is ContentView.dynamicNotchSize (:110-241).
- REA import coverage caveat the spec does not state: macho.json imports are flagged exhaustive=false (4,241 items; limitation 'dyld_info textual imports may omit chained or toolchain-unsupported metadata'). _AXUIElementSetMessagingTimeout and _AXValueGetValue (used by managers/MenuBarLayout.swift:150-181) are absent from the list, and MenuBarLayout itself (pure Swift @MainActor class) has no entry in dispatch.json, so the menu-bar-clearance feature cannot be confirmed as shipping in 2.3.3 from the REA evidence; only _AXIsProcessTrusted, _AXUIElementCreateApplication, _AXUIElementCopyAttributeValue are confirmed. Likewise NotchShape, DynamicIslandPillShape, TabSelectionView, HelloAnimation, RecordingHUDLayout, FlyoutFrameCalculator and PinnedLyricsView are Swift structs/enums with no dispatch.json footprint.
- Spec's shelf-on-close rule is incomplete: vm.close() picks .shelf only when shelf non-empty && openShelfByDefault && !enableMinimalisticUI (DynamicIslandViewModel.swift:453-457); the minimalistic exclusion is missing.
- Spec's closed-content priority chain omits the gating used for each branch: music pairing requires canShowMusicDuringExpansion (no expansion, or expansion type .music, or expansion matching the secondary) (ContentView.swift:1083-1104, 1135); recording live activity additionally requires !musicPairingEligible (:1143); ShelfInlineLiveActivity requires !coordinator.expandingView.show (:1166); idle face requires !isPlaying && isPlayerIdle (:1169). Also the DynamicIslandHeader frame height is nil only when minimalistic AND Dynamic Island mode (:1173), otherwise max(24, effectiveClosedNotchHeight).
- Spec lists 'Haptic alignment feedback fires on hover-in/tap/gesture open': it also fires on scroll-close (ContentView.swift:2644-2646), skip gestures (:2670-2672), the closed waveform play/pause tap (:2122-2124), and the global/local click-monitor open (:2226-2228); hover-in only triggers it while the notch is closed (:2330).

Private API summary:

Source clone: /private/tmp/claude-501/-Users-a-dynamic-iland-dynamic-island/b501c539-18bc-4747-a9c4-d824916ad38f/scratchpad/atoll-clone/Atoll/DynamicIsland; REA evidence: /private/tmp/claude-501/-Users-a-dynamic-iland-dynamic-island/b501c539-18bc-4747-a9c4-d824916ad38f/scratchpad/rea-out (macho.json, dispatch.json, graph.json, plist.json; plist confirms CFBundleShortVersionString 2.3.3 / CFBundleVersion 20260720004, LSUIElement true, LSMinimumSystemVersion 14.6, SDK 26.5).

PRIVATE API actually used by the notch-shell subsystem:
1. CoreGraphics Services (CGS) Spaces, declared with @_silgen_name in private/CGSSpace.swift:70-87 and driven by managers/NotchSpaceManager.swift:25-34 (CGSSpace(level: 2147483647)) and DynamicIslandApp.swift:363, 371, 383-406, 436, 1642: _CGSDefaultConnection, CGSSpaceCreate(cid, 1, nil), CGSSpaceSetAbsoluteLevel, CGSShowSpaces/CGSHideSpaces, CGSAddWindowsToSpaces/CGSRemoveWindowsFromSpaces, CGSSpaceDestroy. macho.json imports confirm all eight (__CGSDefaultConnection, _CGSSpaceCreate, _CGSSpaceDestroy, _CGSSpaceSetAbsoluteLevel, _CGSShowSpaces, _CGSHideSpaces, _CGSAddWindowsToSpaces, _CGSRemoveWindowsFromSpaces) and dispatch.json confirms the classes _TtC5Atoll8CGSSpace and _TtC5Atoll17NotchSpaceManager. Purpose: pin every notch panel into a dedicated max-level Space so it stays above fullscreen apps across Space switches; the public collectionBehavior [.fullScreenAuxiliary,.canJoinAllSpaces,.ignoresCycle,.stationary] + level .mainMenu+3 (DynamicIslandWindow.swift:26-31, 57) already does most of this, so NotchIsland can skip CGS.
2. SkyLightWindow SwiftPM package (Lakr233/SkyLightWindow rev 4a7e8628c85e6b2ec429b57657a556a2171a4864, Package.resolved): NOT applied to the notch panel (calls commented out, DynamicIslandApp.swift:432, 437) but SkyLightOperator.shared.delegateWindow() IS used for the closed-notch music-control flyout (managers/FlyoutWindowPresenter.swift:75) and for HUD/lock-screen windows. dispatch.json confirms _TtC14SkyLightWindow16SkyLightOperator, 13TopmostWindow (NSWindow subclass with canBecomeKey/Main), 23TopmostWindowController, 19NSWindowReadingView ship. macho.json shows no SLS*/CGSSetWindowLevel/CGSMainConnectionID imports beyond the CGS Space set above, so the package's window-server access appears to go through the same CGS Space functions or public API (package source not in the clone - unknown).
3. Not shell, but feeding shell UI: CGSIsScreenWatcherPresent and CGSRegisterNotifyProc (events 1502/1503) in managers/ScreenRecordingManager.swift:23-30, 377, 433 (imports confirmed) drive the header RecordingIndicator and the recording HUD; CGSessionCopyCurrentDictionary (managers/LockScreenManager.swift:360, import confirmed; ApplicationServices SPI) feeds lock-state gating of the shell; the undocumented AX attribute 'AXFullScreen' (observers/FullscreenMediaDetection.swift:140-145) plus MacroVisionKit 0.1.0 decide hideOnClosed/effectiveClosedNotchHeight = 0; NSGlassEffectView via NSClassFromString with KVC on CABackdropLayer 'windowServerAware'/'scale' (helpers/LiquidGlassBackground.swift:79-83, 212-226) is HUD/lock-screen only (ObjC class LiquidGlassContainerView and Swift type LiquidGlassVariant confirmed in dispatch.json; the string itself is not in the JSON). graph.json also lists a bundled MediaRemoteAdapter.framework (now-playing bridge, other subsystem) that is not in LC_LOAD_DYLIB (75 deps, all public + Lottie + Sparkle).

PUBLIC API the shell relies on (confirmed where noted): NSPanel with [.borderless,.nonactivatingPanel], isFloatingPanel, hidesOnDeactivate false, NSWindow.Level(.mainMenu + 3), collectionBehavior, hasShadow false, animationBehavior .none, NSHostingView.acceptsFirstMouse override (FirstMouseHostingView, DynamicIslandApp.swift:90-94; generic Swift class so no dispatch.json entry), NSWindow.sharingType .none/.readOnly (ScreenCaptureVisibilityManager, class confirmed), CGShieldingWindowLevel()/CGWindowLevelForKey (imports confirmed; flyout and HUD levels), NSScreen.auxiliaryTopLeftArea/auxiliaryTopRightArea (Swift getters confirmed in imports), NSScreen.safeAreaInsets, frame/visibleFrame/localizedName, NSEvent.addGlobalMonitorForEvents/addLocalMonitorForEvents for .scrollWheel (PanGesture ScrollMonitor.Coordinator confirmed) and .leftMouseDown, NSEvent.mouseLocation, SwiftUI .onHover/.onTapGesture/DragGesture/.sensoryFeedback(.alignment) (SwiftUI sensoryFeedback symbol confirmed; NSHapticFeedbackManager class referenced), NSWorkspace.activeSpaceDidChangeNotification, NSApplication.didChangeScreenParametersNotification, DistributedNotificationCenter com.apple.screenIsLocked/Unlocked, Accessibility AXIsProcessTrusted/AXUIElementCreateApplication/AXUIElementCopyAttributeValue (confirmed) plus AXUIElementSetMessagingTimeout/AXValueGetValue (used by MenuBarLayout but not visible in the non-exhaustive import list), KeyboardShortcuts 2.3.0 and Defaults 9.0.3 packages. Caveat: macho.json imports are marked exhaustive=false and dispatch.json only lists ObjC-visible classes plus a few Swift type names (DynamicIslandWindow with selectors initWithContentRect:styleMask:backing:defer:/canBecomeKeyWindow/canBecomeMainWindow, NotchSpaceManager, CGSSpace, ScreenCaptureVisibilityManager, MusicControlWindowManager, FullscreenMediaDetector, ExternalDisplayStyle, tabSwitchForward), so pure-Swift shell types (NotchShape, DynamicIslandPillShape, TabSelectionView, DynamicIslandHeader, MenuBarLayout, HelloAnimation, RecordingHUDLayout) cannot be confirmed or refuted from the REA output.
