# Atoll spec: LOCK SCREEN, SETTINGS, ONBOARDING, APP LIFECYCLE (Atoll 2.3.3; source clone DynamicIsland/*, REA evidence from /Applications/Atoll.app)

Source: Atoll 2.3.3 source clone plus REA evidence from the installed binary (see ../atoll-behaviour-evidence.md). Values are quoted with file:line from the Atoll source. Reimplement behaviour, do not copy code (GPL-3).

## Summary

Atoll's app shell is an LSUIElement SwiftUI App (`DynamicNotchApp`, DynamicIslandApp.swift:27-88) with a MenuBarExtra and an `AppDelegate` that owns one borderless NSPanel per screen (`DynamicIslandWindow`, components/Notch/DynamicIslandWindow.swift), positions it flush to the top edge (+4pt bleed on notch displays, +6pt offset in pill mode), resizes it from a single `calculateRequiredNotchSize()` (DynamicIslandApp.swift:479-598) and keeps it pinned across Spaces by inserting the window into a PRIVATE CGS space at absolute level Int32.max (`CGSSpace`/`NotchSpaceManager`, private/CGSSpace.swift). The lock-screen feature set (media panel, status/weather capsule with calendar+focus rows, timer widget, reminder chip, lock/fingerprint live-activity overlay, and third-party extension widgets) is a family of borderless `CGShieldingWindowLevel()` NSWindows that only become visible over loginwindow because each is handed to `SkyLightOperator.shared.delegateWindow(_:)` from the Lakr233/SkyLightWindow package, which dlopen()s the PRIVATE SkyLight.framework and calls SLSMainConnectionID/SLSSpaceCreate/SLSSpaceSetAbsoluteLevel(400)/SLSShowSpaces/SLSSpaceAddWindowsAndRemoveFromSpaces (confirmed in the shipped binary: `_dlopen`/`_dlsym` imports, framework path string and all five SLS* symbol strings present; SkyLight is NOT a link-time dependency). Lock state comes from the distributed notifications com.apple.screenIsLocked/Unlocked, NSWorkspace.sessionDidBecomeActive and a 500 ms poll of CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"] (LockScreenManager.swift:359-391). Settings is a 700pt-wide NavigationSplitView with 21 tabs in 8 sidebar groups, a search index of ~230 entries, and roughly 300 `Defaults` keys (sindresorhus/Defaults 9.0.3) whose defaults are all in models/Constants.swift:984-1645; onboarding is a 400x600 titled-transparent window with 6 steps (welcome, camera, calendar, music source, profile presets, finish). Global shortcuts use sindresorhus/KeyboardShortcuts 2.3.0 with 10 named shortcuts (Shortcuts/ShortcutConstants.swift:26-37), updates use Sparkle 2.7.0 with a channel-switching delegate and a custom SwiftUI user driver, launch-at-login uses LaunchAtLogin-Modern (SMAppService). Extensions expose an NSXPCListener mach service `com.ebullioscopic.Atoll.xpc` plus a loopback-only JSON-RPC 2.0 WebSocket on 127.0.0.1/::1:9020, with per-bundle authorization, scopes, 5-minute rate-limit windows and capacity caps (4/4/2). Everything below quotes constants with file:line (paths relative to the clone's DynamicIsland/ directory).

## App lifecycle: process model, notch window creation, positioning and resizing (AppDelegate)

### Behaviour

Atoll runs as a menu-bar-only accessory app (Info.plist LSUIElement=true, LSMinimumSystemVersion 14.6). On launch it creates the notch window on the preferred screen (or one per screen when 'Show on all displays' is on), flush against the top edge and centered horizontally. The window grows/shrinks to fit the current tab/HUD, hides itself (alpha 0 + orderOut) the instant the screen locks and comes back 1 s after unlock, follows Space switches, and is rebuilt when displays are added/removed. On first launch an onboarding window appears and a welcome chime (dynamic.m4a) plays. Dropping/opening files onto the app adds them to the Shelf and switches the notch to the shelf tab.

### Layout

DynamicIslandWindow (components/Notch/DynamicIslandWindow.swift:25-61): NSPanel, styleMask [.borderless, .nonactivatingPanel] (DynamicIslandApp.swift:417-423), isFloatingPanel, hidesOnDeactivate false, isOpaque false, backgroundColor .clear, isMovable false, hasShadow false, level = .mainMenu + 3 (L57), collectionBehavior pinnedCollectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle, .stationary] (L26-31), canBecomeKey/Main true, animationBehavior .none (DynamicIslandApp.swift:425), content = FirstMouseHostingView(ContentView().environmentObject(vm).environmentObject(webcamManager)) which overrides acceptsFirstMouse=true (L90-94). Sizing (DynamicIslandApp.swift:479-598): base = openNotchSize (sizing/matters.swift:69-75: width = clamp(Defaults.openNotchWidth(640), recommendedMin, max(screenWidth-60,400)), height 200) or minimalisticOpenNotchSize (DI mode 340x144, matters.swift:175-198); per-tab height: timer 250 (L569), notes = NotesLayoutState.preferredHeight (list 240/split 260/editor 320, enums/generic.swift:91-100), clipboard max(base, 240) (L575), terminal min(screenH*terminalMaxHeightFraction, max(300,…)) (L577-579); inline sneak peek width 460 (L516); battery HUD closed-size + (charging/compact: +180 w) (lowBattery standard: +100 w, +75 h) (fullBattery standard: +80 w, +70 h) (L546-558); then addShadowPadding adds 18 (standard) or 12 (minimalistic) to height (matters.swift:171-172, 323-325). adjustedSizeForScreen (L635-644): Dynamic-Island mode adds dynamicIslandShadowInset*2 = 28 to width and dynamicIslandTopOffset = 6 to height (matters.swift:372-377); notch mode adds notchTopScreenBleed = 4 (matters.swift:363-367). positionWindow (L441-465): x = round(screen.midX - w/2), y = round(screen.maxY + topBleed - h). resizeWindow (L670-687) clamps width to screen width and height to screen height + bleed, skips no-op frames. closedNotchSize comes from getClosedNotchSize (matters.swift:398-420): physical notch width = screen.frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width + 4, overridable by Defaults.customizePhysicalNotchWidth/closedNotchWidth (150); non-notch height Defaults.nonNotchHeight (32).

### Animations

Window frame changes are immediate `setFrame(display:true)` (no animator) at DynamicIslandApp.swift:686; tab switches resize synchronously on the next runloop tick (L803-807); other triggers are debounced 0.15 s via DispatchWorkItem (L147-159). shouldAnimateResize returns false only when minimalistic UI + reminder rows are active (L689-694). Unlock restore is delayed 1.0 s (L319). AudioTap restart after a music app launches is delayed 2.0 s (L228).

### State and timing

applicationDidFinishLaunching order (DynamicIslandApp.swift:696-1116): post didBecomeActive → configure LockScreenLiveActivityWindowManager & LockScreenManager with vm → start XPC host + RPC server → run Defaults migrations (progress bar style, music aux controls, music control slots, caps lock tint, third-party DDC, clipboard shortcut ⌘⇧C→⌘⇧V) → idle animations → apply app icon → install main-menu items → SystemHUDManager/BetterDisplay/Lunar setup → purge clipboard history if persistence off → start ScreenRecording/DND/Privacy/Network monitors (skipped under --uitesting) → AudioTap if enableRealTimeWaveform → Combine observers (currentView, hudState, isAdvertisement, notesLayoutState, stats graph toggles, openNotchWidth, terminal keys, reminders, timer, shortcuts enable flags, hideNotchOption→space resync, minimalistic→immediate resize) → screen/space/lock notifications → KeyboardShortcuts handlers → create window(s) + adjustWindowPosition(changeAlpha:true) → onboarding if firstLaunch (+welcome sound) → weather prepareLocationAccess + refresh(force) if enableLockScreenWeatherWidget → warm LockScreenTimerWidgetManager. firstLaunch is cleared 3.5 s after the hello animation (DynamicIslandViewModel.swift:473-483). applicationWillTerminate (L281-310): post didBecomeIdle, SystemOSDManager.resumeOSDUIHelperForTermination(), cancel resize work item, stop XPC/RPC, stop network monitor, AudioTap.stopCapture, LunarManager.appWillTerminate. applicationShouldTerminateAfterLastWindowClosed=false. screenConfigurationDidChange compares screen count/names/frames and rebuilds windows (L1559-1576). MediaControlsStateCoordinator (L1722-1815) caches/restores musicLiveActivityEnabled, enableLockScreenMediaWidget, musicControlWindowEnabled when showStandardMediaControls/enableMinimalisticUI toggle, using cached* nil-able keys (Constants.swift:1090-1092).

### Data sources and APIs

Public AppKit: NSPanel, NSScreen.safeAreaInsets/auxiliaryTopLeftArea/auxiliaryTopRightArea, NSApplication.didChangeScreenParametersNotification (L967-972), NSWorkspace.activeSpaceDidChangeNotification (L974-983), NSWorkspace didLaunch/didTerminateApplication (L215-249), NSApp.setActivationPolicy(.regular/.accessory). DistributedNotificationCenter names "com.apple.screenIsLocked"/"com.apple.screenIsUnlocked" (L1024-1029; undocumented but public API; confirmed as strings in binary). PRIVATE: CGS Space APIs via NotchSpaceManager (see separate feature). Posts DistributedNotificationCenter "com.ebullioscopic.Atoll.lifecycle.didBecomeActive"/"…didBecomeIdle" with userInfo sourcePID on launch/terminate (services/Extensions/AtollDistributedNotifications.swift:13-20; DynamicIslandApp.swift:281-290, 697-705). REA: Info.plist LSUIElement true, CFBundleIdentifier com.Ebullioscopic.Atoll, version 2.3.3 (20260720004), min macOS 14.6; signed Developer ID team 9Y64TRM77N with hardened runtime; entitlements com.apple.security.cs.disable-library-validation, device.camera, automation.apple-events (+temporary exceptions for com.spotify.client, com.apple.Music, com.apple.Notes), personal-information.calendars/location, mach-services [com.ebullioscopic.Atoll.xpc], temporary-exception.mach-lookup.global-name [com.Ebullioscopic.Atoll-spks, -spki] (Sparkle).

### Settings

showOnAllDisplays=false (Constants.swift:989), automaticallySwitchDisplay=true (L990), preferred_screen_name (@AppStorage, default NSScreen.main?.localizedName, DynamicIslandViewCoordinator.swift:155), openNotchWidth=640 (L1014), closedNotchWidth=150 (L1015), customizePhysicalNotchWidth=false (L1016), notchHeightMode=.matchRealNotchSize (L1004), nonNotchHeightMode=.matchMenuBar (L1008), notchHeight=32 (L1013), nonNotchHeight=32 (L1012), externalDisplayStyle=.notch (L999), hideNonNotchUntilHover=false (L1003), enableMinimalisticUI=false (L1503), firstLaunch=true (@AppStorage "firstLaunch", coordinator L126), showWhatsNew=true (@AppStorage), hudReplacement=true (@AppStorage L153).

### Dependencies

Defaults 9.0.3 (MIT), KeyboardShortcuts 2.3.0 (MIT), Sparkle 2.7.0 (MIT), LaunchAtLogin-Modern (MIT), Lottie-spm + LottieUI (Apache-2.0 / MIT), MacroVisionKit 0.1.0 (TheBoredTeam; license not checked), SkyLightWindow (Lakr233; license not verified in this session), SwiftUIIntrospect 1.3.0 (MIT), SwiftTerm 1.13.0 (MIT), Pow 1.0.5 (MIT), open-meteo 1.4.16 (SDK, license not checked), AtollExtensionKit (branch main), swift-collections, swift-argument-parser, swift-syntax (Package.resolved).

### Implementation notes

NotchIsland already has NotchPanelController/NotchGeometryResolver; adopt the same arithmetic: y = screen.maxY + bleed(4 on notch screens, 0 in pill mode) - height; width clamp to screen; pill mode adds 28 w / 6 h for shadow room; always round to whole points. Replace `Defaults` with UserDefaults-backed @Observable settings. Keep lock hide/restore (alpha 0 + orderOut, 1 s restore). Everything here is public API except Space pinning (see CGS feature). Estimated size: ~400 lines (window controller + size resolver + screen-change handling).

### Key files

- `DynamicIslandApp.swift`
- `components/Notch/DynamicIslandWindow.swift`
- `sizing/matters.swift`
- `models/DynamicIslandViewModel.swift`
- `DynamicIslandViewCoordinator.swift`
- `helpers/AppRuntimeEnvironment.swift`
- `Info.plist`
- `DynamicIsland.entitlements`

## Status bar item and main menu (MenuBarExtra, Focus/Accessibility/Permissions/Tools menus, log export)

### Behaviour

A menu-bar icon (SF Symbol mountain.2.fill) with items: Settings, Check for Updates…, separator, Restart Atoll, Quit (⌘Q). Hidden when the 'Menubar icon' setting is off. When the app is active (settings/onboarding window open), four extra top-level menus are inserted before Window/Help: Focus (Use without DevTools / Use DevTools, check-marked), Accessibility (Request Accessibility Access / Open Accessibility Settings), Permissions (Request Full Disk Access / Open Full Disk Access Settings / — / Open Developer Tools Settings), Tools (Logging Level ▸ No Logging/Error/Warning/Info/Debug check-marked / — / Export Logs). Export Logs shows an NSSavePanel named Atoll_Logs.zip and bundles 2 days of unified logs plus crash reports.

### Layout

MenuBarExtra("dynamic.island", systemImage: "mountain.2.fill", isInserted: $showMenuBarIcon) (DynamicIslandApp.swift:51). Items in order: Button("Settings") → SettingsWindowController.shared.showWindow() (L52-54); CheckForUpdatesView(updater:) = Button("Check for Updates…") disabled while !updater.canCheckForUpdates (components/Settings/SoftwareUpdater.swift:35-50); Divider; Button("Restart Atoll") (L57-72) uses NSWorkspace.OpenConfiguration.createsNewApplicationInstance = true then NSApplication.terminate; Button("Quit", role: .destructive).keyboardShortcut("Q", .command) (L73-76). CommandGroup(replacing: .appSettings) → "Settings…" (L80-87). Main menu insertion index = index of "Window" else "Help" else end (L1247-1255); identifiers Atoll.Focus.Menu, Atoll.Accessibility.Menu, Atoll.Permissions.Menu, Atoll.Tools.Menu, Atoll.Tools.LoggingLevel (L1118-1245). `statusItem: NSStatusItem?` (L103) is declared but never assigned (legacy; togglePopover/showMenu/quitAction L1645-1659 are dead).

### Animations

None (native menus).

### State and timing

installTopMenuItemsIfNeeded runs on applicationDidFinishLaunching and applicationDidBecomeActive (L165-167, 738); idempotent via identifier check. Focus menu check state follows Defaults.publisher(.focusMonitoringMode) (L740-745).

### Data sources and APIs

SwiftUI MenuBarExtra; NSMenu/NSMenuItem; NSSavePanel; Process `/usr/bin/log show --predicate "subsystem == 'com.Ebullioscopic.Atoll' OR subsystem == 'com.Ebullioscopic.Atoll.dev'" --info --debug --last 2d` (L1333-1335, string confirmed in binary), copies ~/Library/Logs/DiagnosticReports and /Library/Logs/DiagnosticReports files whose name contains "Atoll", zips with /usr/bin/zip -r (L1345-1364), NSAlert on completion/failure. System Settings deep links: x-apple.systempreferences:com.apple.preference.security?Privacy_DevTools (L1291), ?Privacy_Accessibility (AccessibilityPermissionStore.swift:56), ?Privacy_AllFiles (FullDiskAccessPermissionStore.swift:140) — all confirmed as strings in binary. All public.

### Settings

menubarIcon=true (Constants.swift:988); focusMonitoringMode=.withoutDevTools (L1477, raw "withoutDevTools"/"useDevTools"); logLevel=.none (L987; Int 0…4).

### Dependencies

Sparkle (for the Check for Updates item).

### Implementation notes

Straight port with MenuBarExtra + NSApp.mainMenu insertion in applicationDidBecomeActive. Keep identifiers so state can be refreshed by lookup. ~150 lines.

### Key files

- `DynamicIslandApp.swift`
- `components/Settings/SoftwareUpdater.swift`
- `helpers/AccessibilityPermissionStore.swift`
- `helpers/FullDiskAccessPermissionStore.swift`

## Global keyboard shortcuts (KeyboardShortcuts package)

### Behaviour

System-wide hotkeys, recordable in Settings ▸ Shortcuts, all gated by 'Enable global keyboard shortcuts' and by the owning feature toggle. Defaults: Toggle Sneak Peek ⌘⇧H, Toggle Notch Open ⌘⇧I (opens, auto-closes after 3 s unless the user interacts), Toggle Keep Awake ⌘⇧K, Start Demo Timer ⌘⇧T (5-minute timer), Clipboard History ⌘⇧V, Screen Assistant ⌘⇧A, Toggle Terminal Tab ⌃`, Color Picker Panel ⌘⇧P. Two more names (decreaseBacklight ⌘F1, increaseBacklight ⌘F2) are declared but have no handler or recorder in this codebase.

### Layout

Settings ▸ Shortcuts (components/Settings/SettingsView.swift:7107-7377): Section General: Defaults.Toggle enableShortcuts; then one Section per shortcut with KeyboardShortcuts.Recorder("Toggle Sneak Peek:", name: .toggleSneakPeek) (L7137), "Toggle Keep Awake:" .toggleCaffeinate (L7150), "Toggle Notch Open:" .toggleNotchOpen (L7169), "Start Demo Timer:" .startDemoTimer (L7183), "Clipboard History:" .clipboardHistoryPanel (L7206), "Screen Assistant:" .screenAssistantPanel (L7235), "Toggle Terminal Tab:" .toggleTerminalTab (L7258), "Color Picker Panel:" .colorPickerPanel (L7281); each shows '<Feature> is disabled' when its feature flag is off. Footer copy documents defaults (e.g. 'Default is Cmd+Shift+A', 'Default is Ctrl+`', 'Default is Cmd+Shift+P').

### Animations

toggleNotchOpen: vm.open() then a DispatchWorkItem closes after 3.0 s (DynamicIslandApp.swift:1064-1076); cancelled by cancelPendingNotchAutoClose() when the clipboard/terminal shortcut switches tabs (L1388-1394, 1452). toggleSneakPeek shows the music sneak peek for duration 3.0 (L1035-1039). Popover-mode shortcuts open the notch then post the popover notification after 0.3 s (L1419, 1514).

### State and timing

optionalShortcutHandlersRegistered guard ensures handlers register once (L1396-1398). Shortcut enabled state recomputed on every relevant Defaults change (L894-930).

### Data sources and APIs

sindresorhus/KeyboardShortcuts 2.3.0 (Carbon RegisterEventHotKey under the hood). Names/defaults: Shortcuts/ShortcutConstants.swift:26-37 — clipboardHistoryPanel ⌘⇧V, colorPickerPanel ⌘⇧P, screenAssistantPanel ⌘⇧A, decreaseBacklight ⌘F1, increaseBacklight ⌘F2, toggleSneakPeek ⌘⇧H, toggleNotchOpen ⌘⇧I, toggleTerminalTab ⌃`, startDemoTimer ⌘⇧T, toggleCaffeinate ⌘⇧K. KeyboardShortcuts.isEnabled = Defaults.enableShortcuts (L897, 1079); per-name enable/disable via KeyboardShortcuts.enable/disable from updateFeatureShortcutAvailability (L1524-1541). Migration migrateClipboardShortcutToV moves a shortcut still on ⌘⇧C to ⌘⇧V once (Constants.swift:1574-1583). extensions/KeyboardShortcutsHelper.swift converts a shortcut to SwiftUI KeyEquivalent via TISCopyCurrentKeyboardLayoutInputSource/UCKeyTranslate (public Carbon; both imports confirmed by REA). Handlers: DynamicIslandApp.swift:1031-1077 (sneak peek, notch open), 1396-1522 (demo timer → TimerManager.startDemoTimer(duration: 300); clipboard by clipboardDisplayMode .panel/.popover/.separateTab/.notchTab; color picker panel; caffeinate toggle; terminal tab with focus handling; screen assistant by display mode).

### Settings

enableShortcuts=true (Constants.swift:1397); didMigrateClipboardShortcutToV=false (L1496). Feature gates: enableTimerFeature=true (L1318), enableClipboardManager=true (L1359), enableColorPickerFeature=true (L1352), enableScreenAssistant=true (L1369), enableCaffeinate=true (L1346), enableTerminalFeature=false (L1301). clipboardDisplayMode=.panel (L1366), screenAssistantDisplayMode=.panel (L1370).

### Dependencies

KeyboardShortcuts 2.3.0 (MIT) — stores shortcuts in UserDefaults under 'KeyboardShortcuts_<name>'.

### Implementation notes

With no dependencies, implement a tiny hotkey manager over Carbon RegisterEventHotKey/InstallEventHandler (public, no Accessibility needed) and a recorder view with NSEvent local monitor; persist as {keyCode, modifiers} per name. Keep the same defaults and the per-feature gating. ~300 lines.

### Key files

- `Shortcuts/ShortcutConstants.swift`
- `extensions/KeyboardShortcutsHelper.swift`
- `DynamicIslandApp.swift`
- `components/Settings/SettingsView.swift`

## PRIVATE CGS Space pinning of the notch window (CGSSpace + NotchSpaceManager)

### Behaviour

The notch window stays visible on every desktop and over native fullscreen apps without flicker, because it lives in its own private Space at the maximum absolute level rather than relying only on collectionBehavior.

### Layout

NotchSpaceManager.shared.notchSpace = CGSSpace(level: 2147483647) (managers/NotchSpaceManager.swift:32). CGSSpace (private/CGSSpace.swift:26-67): init creates a space with CGSSpaceCreate(_CGSDefaultConnection(), 0x1, nil) — comment: flag MUST be 1 or Finder draws desktop icons (L46-47) — then CGSSpaceSetAbsoluteLevel(cid, space, level) and CGSShowSpaces(cid, [space]); `windows: Set<NSWindow>` didSet diffs and calls CGSRemoveWindowsFromSpaces / CGSAddWindowsToSpaces with windowNumber arrays (L30-42); deinit hides and destroys the space. AppDelegate inserts each notch window on creation (DynamicIslandApp.swift:436), removes on close (L363, 371), and rebuilds membership via syncNotchSpaceMembership() on adjustWindowPosition, hideNotchOption change and active-space change (L383-406, 934-938, 1642).

### Animations

None.

### State and timing

Space membership is re-synced on activeSpaceDidChange (with collectionBehavior reassert + orderFrontRegardless, skipped while windowsHiddenForLock) (DynamicIslandApp.swift:396-406, 974-983).

### Data sources and APIs

PRIVATE CoreGraphics/SkyLight symbols declared with @_silgen_name (private/CGSSpace.swift:70-87): _CGSDefaultConnection, CGSSpaceCreate, CGSSpaceDestroy, CGSSpaceSetAbsoluteLevel, CGSAddWindowsToSpaces, CGSRemoveWindowsFromSpaces, CGSHideSpaces, CGSShowSpaces. REA macho.json imports CONFIRM all of: __CGSDefaultConnection, _CGSSpaceCreate, _CGSSpaceDestroy, _CGSSpaceSetAbsoluteLevel, _CGSAddWindowsToSpaces, _CGSRemoveWindowsFromSpaces, _CGSHideSpaces, _CGSShowSpaces (plus _CGSIsScreenWatcherPresent and _CGSRegisterNotifyProc used by screen-recording detection elsewhere). dispatch.json confirms types CGSSpace and NotchSpaceManager ship.

### Settings

hideNotchOption=.nowPlayingOnly (Constants.swift:1237; raw always/nowPlayingOnly/never) only triggers a membership resync; it does not gate the Space.

### Dependencies

None (direct private symbols).

### Implementation notes

Public-only alternative (recommended for NotchIsland): NSPanel with level .mainMenu+3 (or .screenSaver) and collectionBehavior [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle] plus re-ordering front on NSWorkspace.activeSpaceDidChangeNotification; this covers Mission Control/fullscreen in practice but may briefly flicker during Space transitions and cannot sit above the lock screen. If private use is accepted, isolate behind a `PrivateSpaces` feature flag in one file using @_silgen_name exactly as above; call on main thread only. ~90 lines.

### Key files

- `private/CGSSpace.swift`
- `managers/NotchSpaceManager.swift`
- `DynamicIslandApp.swift`

## PRIVATE SkyLight lock-screen window delegation (SkyLightWindow package) and the common lock-screen window recipe

### Behaviour

Atoll's own widgets (media panel, status/weather capsule, timer, reminder chip, lock icon overlay, extension widgets) render ON TOP of the macOS lock screen, above the clock, and fade out while Siri is on screen.

### Layout

Every lock-screen window uses the same recipe: NSWindow(styleMask: [.borderless, .nonactivatingPanel]), isReleasedWhenClosed=false, isOpaque=false, backgroundColor .clear, hasShadow=false, level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel())), collectionBehavior [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary], ignoresMouseEvents true for passive widgets (weather, reminder, extension) / false for interactive ones (media panel, timer, lock overlay), ScreenCaptureVisibilityManager.register(window, scope: .entireInterface), SkyLightOperator.shared.delegateWindow(window) exactly once per window (hasDelegated flag), SiriVisibilityMonitor.shared.autohide(window, cancellables:) — see LockScreenPanelManager.swift:129-176, LockScreenLiveActivityWindowManager.swift:102-130, 229-232, LockScreenWeatherPanelManager.swift:95-121, LockScreenTimerWidgetManager.swift:222-251, LockScreenReminderWidgetPanelManager.swift:97-124, ExtensionLockScreenWidgetPresentationController.swift:187-204. Windows are never closed on unlock — only orderOut(nil) and contentView=nil — 'to avoid SkyLight crashes' (LockScreenPanelManager.swift:178, 295-303). Target screen = LockScreenDisplayContextProvider.shared.contextSnapshot()?.screen ?? NSScreen.main, where the provider prefers the built-in display (CGDisplayIsBuiltin), then CGMainDisplayID, refreshed on screen-parameter/wake/space-change and on every lock/unlock (managers/LockScreenDisplayContextProvider.swift:50-124).

### Animations

Siri autohide: when SiriVisibilityMonitor.isSiriVisible flips while locked, window.contentView?.layer?.removeAllAnimations() then NSAnimationContext 0.25 s easeInEaseOut to alphaValue 0/1 (managers/SiriVisibilityMonitor.swift:211-237). Siri detection is a CGWindowListCopyWindowInfo poll for owner "Siri" with height > 400 (L200-207), interval governed by siriResponsivenessMode (automatic / highPerformance 30 Hz / balanced 16 Hz / powerSaver 4 Hz per Constants.swift:744-769).

### State and timing

All lock windows are created lazily on first lock and reused for the process lifetime; geometry is re-applied (unanimated) on NSApplication.didChangeScreenParametersNotification and NSWorkspace.screensDidWakeNotification.

### Data sources and APIs

PRIVATE SkyLight via SkyLightWindow (github.com/Lakr233/SkyLightWindow, branch main rev 4a7e862): dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW) + dlsym of SLSMainConnectionID, SLSSpaceCreate, SLSSpaceSetAbsoluteLevel, SLSShowSpaces, SLSSpaceAddWindowsAndRemoveFromSpaces; the singleton creates a space at absolute level 400 (kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock; other named levels: 0 default, 100 SetupAssistant, 200 SecurityAgent, 300 ScreenLock, 500 BootProgress, 600 VoiceOver) and shows it; delegateWindow(w) = SLSSpaceAddWindowsAndRemoveFromSpaces(cid, spaceID, [w.windowNumber], 7). REA CONFIRMS: Atoll links no SkyLight dylib (dependencies list has none), imports _dlopen/_dlsym, and the binary contains the framework path string and all five SLS* symbol-name strings; dispatch.json lists SkyLightOperator. Public: CGShieldingWindowLevel() (import confirmed), CGDisplayIsBuiltin (confirmed), CGWindowListCopyWindowInfo (confirmed), NSWindow.sharingType.

### Settings

siriResponsivenessMode=.automatic (Constants.swift:1097); hideDynamicIslandFromScreenCapture=false (L992) → window.sharingType = .none vs .readOnly for every registered window (ScreenCaptureVisibilityManager.swift:65-68).

### Dependencies

SkyLightWindow (SwiftPM, Lakr233) — license not verified here.

### Implementation notes

There is no public API to draw above loginwindow; NSWindow.Level(CGShieldingWindowLevel()) alone is not visible on the lock screen on modern macOS. Options for NotchIsland: (a) ship lock-screen widgets behind an opt-in 'experimental' flag using a 30-line dlsym wrapper mirroring the five SLS calls above (private, may break per OS release, must never run in a sandboxed build); (b) omit lock-screen rendering and keep only lock-state-driven behavior (hide notch, play sounds, pause HUDs). Keep the shared window recipe as a `LockScreenOverlayWindow` helper either way. Target-screen selection (built-in first) and Siri autohide are public and portable.

### Key files

- `managers/LockScreenPanelManager.swift`
- `managers/LockScreenLiveActivityWindowManager.swift`
- `managers/LockScreenWeatherPanelManager.swift`
- `managers/LockScreenTimerWidgetManager.swift`
- `managers/LockScreenReminderWidgetPanelManager.swift`
- `managers/Extensions/ExtensionLockScreenWidgetPresentationController.swift`
- `managers/LockScreenDisplayContextProvider.swift`
- `managers/SiriVisibilityMonitor.swift`
- `helpers/ScreenCaptureVisibilityManager.swift`

## LockScreenManager: lock/unlock detection, sequencing, sounds, fingerprint trigger

### Behaviour

When the Mac locks: lock chime (lock.mp3), the notch collapses instantly with no animation, any HUD/sneak peek is dismissed, the media panel/lock overlay/weather/timer/reminder/extension widgets appear, and the in-notch lock live activity expands. When it unlocks: unlock chime, the lock icon flips open (or the fingerprint scan animation plays), the panel widgets disappear, the lock overlay holds then contracts back into the notch, and the music HUD is suppressed for ~1 s more. Pressing the power/Touch ID key while locked plays the fingerprint scan if the fingerprint icon style is selected.

### Layout

n/a (coordinator). Published state: isLocked, isLockIdle, shouldDelayPostUnlockMusicHUD, lastUpdated, isFingerprintAnimating, fingerprintAnimationGeneration (managers/LockScreenManager.swift:74-101). `isLockedSnapshot` is an OSAllocatedUnfairLock-guarded nonisolated mirror for CoreAudio/brightness threads (L87-96).

### Animations

LockScreenAnimationTimings (LockScreenManager.swift:31-63): lockExpand 0.45 s; unlockCollapse 0.82 s; lockUnlockHold 0.82 s; fingerprintUnlockHold 1.45 s; fingerprintScanReset 1.55 s; unlockRemovalPadding 0.14 s; postUnlockMusicHUDPause 1.0 s; postUnlockMusicHUDReveal 0.34 s. currentUnlockHold = lockUnlockHold for .lock style, fingerprintUnlockHold for .fingerprint/.both; currentUnlockSequenceDuration = hold + 0.82; currentUnlockRemovalDelay = that + 0.14. On unlock, shouldDelayPostUnlockMusicHUD is cleared after unlockRemovalDelay + 1.0 s with .spring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.08) (L302-325); the .lockScreen expanding view is toggled off after unlockRemovalDelay (L336-345); isLockIdle flips true after the same delay with animations disabled via Transaction (L414-437). Power-key presses are debounced 0.2 s (L199-201).

### State and timing

screenLocked (L227-278): guard !isLocked → play chime → DisplayContext.refresh → lastUpdated=now, isLockIdle=false → reset fingerprint → isLocked=true → vm.closeForLockScreen() (sets notchSize/closedNotchSize/notchState=.closed inside withAnimation(.none), DynamicIslandViewModel.swift:460-469) → dismiss expandingView and sneakPeek → LockScreenPanelManager.showPanel → updateNativeHUDSuppression → LockScreenLiveActivityWindowManager.showLocked → LockScreenWeatherManager.showWeatherWidget → LockScreenTimerWidgetManager.handleLockStateChange(true) → if enableLockScreenLiveActivity: coordinator.toggleExpandingView(status:true, type:.lockScreen) → startLockStatePolling. screenUnlocked (L280-348): guard isLocked → chime → refresh → start fingerprint animation if style shows fingerprint → isLocked=false → HUD suppression off → stop polling → shouldDelayPostUnlockMusicHUD = enableLockScreenLiveActivity → hidePanel, FullScreenArtworkWindowManager.hide, overlay showUnlockAndScheduleHide, weather hide, timer hide → collapse task.

### Data sources and APIs

DistributedNotificationCenter "com.apple.screenIsLocked"/"com.apple.screenIsUnlocked" (L141-154); NSWorkspace.sessionDidBecomeActiveNotification as an early-unlock fallback (L160-165); CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"] polled every 500 ms while locked (public API, undocumented key; import and key string confirmed by REA) (L359-391) — the poll also calls LockScreenPanelManager.ensurePresentedWhileLocked(). NSEvent.addLocalMonitorForEvents/addGlobalMonitorForEvents(.systemDefined) with subtype rawValue 1 (powerKey) (L27-29, 171-189). Sounds: AVAudioPlayer on bundled lock.mp3 / unlock.mp3, throttled 0.25 s per type (LockSoundPlayer L460-519). Logger category .lifecycle. All public.

### Settings

enableLockScreenLiveActivity=true (Constants.swift:1487); lockScreenLiveActivityIconStyle=.lock (L1488; raw lock/fingerprint/both); enableLockSounds=true (L1489).

### Dependencies

Defaults.

### Implementation notes

Port verbatim semantics: dual notification + session poll; idempotent handlers; keep the timing table as a single enum. NotchIsland already has FullscreenDetector; add a LockStateMonitor actor on the main actor. ~250 lines.

### Key files

- `managers/LockScreenManager.swift`
- `lock.mp3`
- `unlock.mp3`

## Lock-screen live activity: in-notch LockScreenLiveActivity view + delegated LockScreenLiveActivityOverlay window + LockIconAnimator/fingerprint Lottie

### Behaviour

While locked, the closed notch grows sideways by one indicator on each side: a white lock glyph on the left and (optionally) a Touch ID glyph on the right, on a black notch-shaped (or pill-shaped) background. Because the real notch window is hidden on the lock screen, a separate delegated overlay window draws the same thing over loginwindow, animating in with a spring and contracting back to notch width on unlock. On unlock the lock glyph flips from lock.fill to lock.open.fill; with the fingerprint style a green scanning Lottie plays at 5x speed to 70% progress.

### Layout

LockScreenLiveActivityOverlay (components/LockScreen/LockScreenLiveActivityOverlay.swift:26-112): indicatorSize = notchSize.height - 12; horizontalPadding = 8 in pill mode else cornerRadiusInsets.closed.bottom = 14 (matters.swift:199); HStack(spacing 0) [Color.clear w=indicator h=notch.h overlay(.leading) LockIconProgressView frame indicator²] [Rectangle black w=notch.w h=notch.h] [Color.clear overlay(.trailing) LockScreenFingerprintProgressView frame indicator²]; .frame(w: notch.w + 2*indicator) .padding(.horizontal, hp) .background(black) .clipShape(pill ? DynamicIslandPillShape(cornerRadius: max(h/2, 16)) : NotchShape(top 6, bottom 14)) .padding(.top, pill ? 6 : 0) .frame(totalWidth = notch.w + 2*indicator + 2*hp, height notch.h + topOffset) .scaleEffect(x: max(scale, collapsedScale) * hover1.03, y: hover1.03) .opacity. collapsedScale = notch.w / totalWidth (L105-111). Window size = totalWidth x (notch.h + topOffset), frame x = screen.midX - w/2, y = screen.maxY - h; notch size rounded UP to whole points to avoid a hairline at the top (LockScreenLiveActivityWindowManager.swift:61-95). In-notch LockScreenLiveActivity (components/LockScreen/LockScreenLiveActivity.swift:70-148): indicatorDimension = effectiveClosedNotchHeight - 12; side width animates 0 → (closedHeight - (hover ? 0 : 12) + gestureProgress/2); indicator opacity fades in over the first 16% of width (fadeThreshold 0.16) and scales 0.96→1.0; center Rectangle width = closedNotchSize.width + (hover ? 8 : 0); total height = closedHeight + (hover ? 8 : 0). LockIconProgressView (LockIconAnimationView.swift:86-112): Image(systemName: isLocked ? "lock.fill" : "lock.open.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).contentTransition(.symbolEffect(.replace.downUp)); isLocked = progress >= 0.5 && !isFingerprintAnimating. Fingerprint view (L116-164): Image "touchid" 13pt semibold, hidden while animating; LottieView(FingerprintScan.json) playing fromProgress 0 → 0.70 playOnce, animationSpeed 5, valueProvider success color LottieColor(r 0.18, g 0.92, b 0.34) for keypath "**.Stroke 1.Color", renderingEngine .mainThread, scaleEffect 2.65 (crop of its 800x600 canvas), .id(generation). LockIconLottieView (Lock.json) exists as a fallback but is unused by the shipped views.

### Animations

Overlay show (LockScreenLiveActivityWindowManager.swift:240-262): start scale=collapsedScale, opacity 0 → next runloop withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) scale=1 and .easeOut(0.18) opacity=1. Unlock (L264-290): present at scale 1/opacity 1, animator.update(isLocked:false), sleep currentUnlockHold (0.82 or 1.45 s), then withAnimation(.smooth(duration: 0.82)) scale→collapsedScale (fallback 0.7) keeping opacity 1, then after 0.82+0.14 s window alpha 0 + orderOut. In-notch: expandAnimation .smooth(0.45), collapseAnimation .smooth(0.82), plus .animation(.spring(response: 0.5, dampingFraction: 0.85), value: isLocked); hover uses .smooth(0.2) and NSHapticFeedbackManager .alignment (overlay L93-100). LockIconAnimator: 48 steps over 0.35 s with easeOutCubic (1-(1-t)^3) driving progress 0↔1 (LockIconAnimationView.swift:24-84); glyph swap .snappy(duration: 0.28). Fingerprint scan auto-resets after 1.55 s if still locked.

### State and timing

Overlay model: LockScreenLiveActivityOverlayModel scale (default 0.6) / opacity (0). Window alpha 0 while hidden; present() rebuilds rootView each time with current notchSize and isDynamicIslandMode.

### Data sources and APIs

Public SwiftUI/AppKit; Lottie (LottieView, LottieAnimation.named "FingerprintScan" from LottieAnimations/FingerprintScan.json); NSHapticFeedbackManager (import confirmed). Window delegation uses PRIVATE SkyLight (see that feature). The in-notch view is driven by coordinator.toggleExpandingView(type: .lockScreen) (SneakContentType case lockScreen, DynamicIslandViewCoordinator.swift:37).

### Settings

enableLockScreenLiveActivity=true; lockScreenLiveActivityIconStyle=.lock (.lock shows lock only, .fingerprint shows fingerprint only, .both shows both; Constants.swift:975-982); Settings cards 'Lock'/'Fingerprint' toggle between .lock/.fingerprint/.both (SettingsView.swift:5795-5824).

### Dependencies

Lottie (for fingerprint scan only).

### Implementation notes

The in-notch part is fully public: reproduce the HStack with side indicators that animate width from 0 and the lock.fill↔lock.open.fill .replace.downUp transition; the 0.35 s eased progress driver can become a simple withAnimation on a Bool. Fingerprint scan: either omit, or draw a 2-3 stroke SF 'touchid' with a green sweep using a TimelineView to avoid Lottie. The delegated overlay window needs SkyLight (private). ~350 lines public portion.

### Key files

- `components/LockScreen/LockScreenLiveActivity.swift`
- `components/LockScreen/LockScreenLiveActivityOverlay.swift`
- `components/LockScreen/LockIconAnimationView.swift`
- `managers/LockScreenLiveActivityWindowManager.swift`
- `LottieAnimations/FingerprintScan.json`
- `LottieAnimations/Lock.json`

## Lock-screen media panel (LockScreenPanelManager + LockScreenMusicPanel)

### Behaviour

A rounded glass card centered horizontally a little below the screen's vertical center shows album art (60pt, click to expand), marquee title with optional 'E' badge, artist, a 4-bar visualizer, a progress slider and a row of transport controls (configurable slots; play/pause larger). Clicking the art expands the panel to 720x340 with 60pt-radius artwork, 21pt title, bigger controls and an optional 300pt lyrics column; it auto-collapses after 30 s of no interaction (never while the pointer is over it). A volume capsule row and an output-device picker (merged AirPlay + CoreAudio routes for Apple Music) can add height. Right-click on the art makes it the fullscreen wallpaper (FullScreenArtworkWindowManager). The panel is only drawn while a media session exists; otherwise a clear placeholder keeps the frame.

### Layout

Sizes (components/LockScreen/LockScreenMusicPanel.swift:31-41): collapsedHeight 180, defaultCollapsedWidth 390 (also the Defaults default), collapsedSize = (Defaults.lockScreenMusicPanelWidth, 180), expandedSize 720x340. Corner radii (L92-95): collapsed panel 28, expanded 52, collapsed art 16, expanded art 60; the hosting layer also masksToBounds with cornerRadius 28/52 (LockScreenPanelManager.swift:41-42, 165-171, 224-234). Extra heights (L214-217): collapsed slider +48, expanded slider +44, collapsed lyrics +56, expanded lyrics +96; expanded lyrics column width 300 (L171); expandedContentSpacing 28, expandedColumnSpacing 18, expandedHorizontalInsets 40, expandedVerticalInsets 38 (32 in Spotify-canvas fallback) (L96-165); expanded artwork = clamp(min(heightBudget, widthBudget), 180, 340) (L112-123). Controls (L180-190): secondary frame 40/62 (collapsed/expanded), glyph 18/26; play/pause frame 58/84, glyph 28/39; gaps 14, row min width + 24 (L128-138). Foreground padding (L422-424): horizontal 16/20, top 16/22, bottom 12/16 (fallback 18/20, 14/18, 10/14). Collapsed layout VStack(spacing 12): header (HStack spacing 16: album art 60; VStack(spacing 1) title 14pt semibold marquee (minDuration 0.45, badge 'E' 15pt tall, radius 4, min width 16) + artist 12pt medium; visualizer height 16; header height 60, text block height 36) → progress bar (.padding(.top,4)) → controls (.padding(.top,4)) (L432-519). Expanded header: title 21pt semibold (badge 18pt, radius 5), artist 15pt medium 2 lines, block height 52, visualizer 20 (L521-560). Panel shadow black 0.3 radius 20 y 10 (fallback 0.35/26/14) (L313-318). Backgrounds (L1490-1568): standard liquid = GlassTextBackdrop (macOS 26 glassEffect); custom liquid = LiquidGlassBackground(variant) over Color.white.opacity(0.04); frosted = .ultraThinMaterial; opaque = black 0.45 (dark appearance) / white 0.55 (light). Border overlay (L1570-1615): enhanced liquid = 3 strokes (white 0.22 @1.05, inset 0.85 gradient white 0.28→0.1→black 0.18 @0.9, inset 1.55 black 0.16 @0.55); liquid = white 0.15/0.14 @0.95/0.9; otherwise white 0.35 @1.4. Control button style: Circle fill appearance.primary(opacity resting / hover +0.08 clamp 0.15-0.32 / pressed +0.16 clamp 0.26-0.4), pressed scale 0.94 (L1744-1771). Window placement (LockScreenPanelManager.swift:402-422): x = screen.midX - w/2; y = screen.y + screen.h/2 - h - 32 + (-68 defaultLowering) + clamp(lockScreenMusicVerticalOffset, -160, 160); if a timer widget frame exists, top is capped to timerFrame.minY - 12. Expanded/extra sizes keep the collapsed frame's midX and origin.y (L334-352). Spotify-canvas fallback places the panel beside a square artwork with 48pt side margins and 56/84 vertical margins, clearing weather/timer frames by 20 (L354-400).

### Animations

Window resize: NSAnimationContext 0.28 s easeInEaseOut on frame + CATransaction 0.28 s on layer cornerRadius (LockScreenPanelManager.swift:199-234). Panel appearance: scaleEffect 0.9→1, opacity 0→1 with .spring(response: 0.52, dampingFraction: 0.8) on animator.isPresented, set true on the next runloop after showPanel (L181-184; LockScreenMusicPanel.swift:408-410). Hide: isPresented=false then after 360 ms orderOut + contentView=nil (L295-303). Expand/collapse .easeInOut(0.28); volume row .easeInOut(0.24); output picker .spring(0.45, 0.85); lyric line .smooth(0.32); collapse timeout 30 s (L176, 677-691); parallax suspended 0.65 s after interaction (L694); artwork pop .easeInOut(0.2/0.28). Panel-width default changes re-layout animated via applyOffsetAdjustment.

### State and timing

showPanel (LockScreenPanelManager.swift:102-187): guard enableLockScreenMediaWidget else hidePanel; compute collapsed frame; create/reuse window; setFrame; publish frame; animator.isPresented=false; new NSHostingView(LockScreenMusicPanel) each time; delegate once; orderFrontRegardless; next tick isPresented=true. ensurePresentedWhileLocked (L270-281) is called from the 500 ms lock poll and re-shows if window missing/not visible/contentView nil. Screen-geometry changes re-apply unanimated. Observes Defaults.lockScreenMusicPanelWidth → animated re-layout (L325-332).

### Data sources and APIs

MusicManager/AudioRouteManager/AppleMusicAirPlayManager/MediaOutputVolumeViewModel/FullScreenArtworkWindowManager (media subsystem). Window: PRIVATE SkyLight delegation; CGShieldingWindowLevel. LiquidGlassBackground (helpers/LiquidGlassBackground.swift) uses PRIVATE NSGlassEffectView variant setters via NSSelectorFromString("set_variant:") (L178-200) — 20 variants v0…v19, default v11 (L127-143). glassEffect(...) is public macOS 26 API. Posts .atollLockScreenPanelFrameDidChange with the frame (L62-75, 429-431). Publishes latestFrame for the other widgets' layout.

### Settings

enableLockScreenMediaWidget=true (Constants.swift:1094); lockScreenMusicPanelWidth=390 (L1111-1114); lockScreenMusicVerticalOffset=0 (L1110, clamped ±160); lockScreenGlassStyle=.liquid (L1119; "Liquid Glass"/"Frosted Glass"); lockScreenGlassCustomizationMode=.standard (L1120; "Standard"/"Custom Liquid"); lockScreenMusicLiquidGlassVariant=.v11 (L1129); lockScreenShowAppIcon=false (L1137); lockScreenPanelShowsBorder=false (L1138); lockScreenMusicUsesEnhancedLiquidBorder=true (L1139); lockScreenPanelUsesBlur=true (L1143); lockScreenMusicMergedAirPlayOutput=true (L1144); lockScreenMusicFullscreenArtworkEnabled=true (L1145); lockScreenKeepAlbumArtVisibleDuringFullscreenArtwork=false (L1146); lockScreenMusicFullscreenVideoArtwork=true (L1147, no UI); lockScreenUseArtworkLayoutOverFullscreenCanvas key "lockScreenShowCenteredAlbumArtOverFullscreenCanvas"=true (L1148); lockScreenMusicAlbumParallaxEnabled=false (L1115); alwaysShowLockScreenVolume=false (L1080); lockScreenWidgetAppearance=.dark (L1118); showMediaOutputControl=true (L1072); musicControlSlots=MusicControlButton.defaultLayout (L1084); musicSkipBehavior=.track (L1086); enableLyrics=false (L1506). cachedLockScreenMediaWidgetPreference (nil) is used by MediaControlsStateCoordinator to disable/restore the panel when standard media controls are off.

### Dependencies

Defaults; SkyLightWindow (private).

### Implementation notes

Reuse NotchIsland's media views for the panel content; implement a LockScreenPanelController with the same frame math and 0.28 s easeInEaseOut resize. Material: use .ultraThinMaterial + optional glassEffect on macOS 26; skip the private NSGlassEffectView variant hack (keep 'Standard' only). Requires SkyLight to actually show over the lock screen. ~600 lines excluding media controls.

### Key files

- `managers/LockScreenPanelManager.swift`
- `components/LockScreen/LockScreenMusicPanel.swift`
- `helpers/LiquidGlassBackground.swift`
- `components/LockScreen/LyricSweep.swift`

## Lock-screen status/weather capsule (LockScreenWeatherManager + LockScreenWeatherPanelManager + LockScreenWeatherWidget) incl. calendar, focus, battery, Bluetooth and AQI rows

### Behaviour

Above the media panel (roughly 15% above screen center) a transparent, shadowed, white-glyph (or dark-glyph) strip shows, left to right: charging time/bolt, MacBook battery %, Bluetooth device battery %, AQI (wind icon + 'AQI 42 Good'), weather symbol + temperature, sunrise time, and the location name. In 'Circular' layout the battery/AQI/temperature become 64pt accessory gauges with min/max labels. Up to two more rows (order configurable) show the next calendar event ('09:30 • Standup • in 25m', or '09:30 • Standup • 20m left') with a palette-tinted calendar.badge icon, and the active Focus mode with its icon; focus and calendar merge into one row separated by '•' when both are present. Refreshes every 15 s plus exactly on minute boundaries while locked. Weather comes from Open-Meteo (default) with wttr.in fallback, refreshed at most every 30 min.

### Layout

LockScreenWeatherWidget (components/LockScreen/LockScreenWeatherWidget.swift): fonts inlinePrimaryFont 22pt semibold rounded, inlineSecondaryFont 13pt medium rounded (L57-58); icons 20pt semibold (weather symbol 26pt medium, hierarchical; AQI wind 18pt; sunrise 'sunrise.fill' 20pt); body = VStack(alignment .leading, spacing focusWidgetSpacing = 14 inline / 20 circular when calendar or focus enabled else 0) of rows, .foregroundStyle(appearance.primary(0.65)), .padding(.horizontal 10), top padding 6 inline / 22 circular, bottom 6 / 10, shadow appearance.contentShadow (black 0.35 for dark appearance, white 0.5 for light; LockScreenWidgetAppearance+Colors.swift:30-32) radius 8 y 3 (L492-507, 1198-1201, 484-486). Main row HStack(alignment .firstTextBaseline inline / .top circular, spacing 14 / 22) ordering: charging, battery, bluetooth, airQuality, weather, sunrise, location (L627-656); segments use spacing 6; gaugeDiameter 64 (L484); gauges .accessoryCircularCapacity for battery (tint batteryTint), .accessoryCircular for AQI (range 0…500 US / 0…120 EAQI, enums/generic.swift:331-338) and temperature; tinted temperature gauge is a hand-drawn TemperatureRangeArc: startAngle 145°, sweep 250°, lineWidth 6, round caps, AngularGradient over the day's min…max, marker circle lineWidth+2.5 with black 0.22 0.5pt border, animated .easeInOut(0.35) (L1635-1687); center label 20pt semibold rounded, min/max labels 11pt medium rounded under the gauge (L1118-1169). Calendar row LockScreenCalendarEventRow (LockScreenCalendarEventRow.swift:31-50): HStack(spacing 6) icon frame 26x26 (20pt semibold) + Text(line) lineLimit 1 minScale 0.85 layoutPriority 10, horizontal padding 2, opacity by isVisible. Combined focus+calendar row: HStack(spacing 10) [calendar group spacing 6, priority 2] '•' [focus group spacing 8 icon 26x26, priority 1] centered (L675-717). Row order options via lockScreenWeatherWidgetRowOrder strings weather_focus_calendar / weather_calendar_focus (default) / focus_weather_calendar / focus_calendar_weather / calendar_weather_focus / calendar_focus_weather (L411-428); when the middle row is inactive and the bottom active the bottom row offsets up by -(26 + spacing) with .easeInOut(0.3) (L454-471, 496-497). Window frame (LockScreenWeatherPanelManager.swift:124-148): size = hostingView.fittingSize; x centered; verticalOffset = screen.h*0.15; topMargin 120 circular / 48 inline; positionHeight = max(size.h, inlineBaseline≥80) for inline; maxY = screen.maxY - positionHeight - topMargin; baseY = min(maxY, screen.midY + verticalOffset); loweredY = baseY - 36; adjusted = loweredY + (inline ? 44 : 0) + clamp(userOffset,±160) - (circular ? 28 : 0) - max(0, positionHeight-80)*0.35; clamped to [screen.minY+80, maxY]. Window ignoresMouseEvents.

### Animations

Position refresh on offset change: NSAnimationContext 0.22 s easeInEaseOut (LockScreenWeatherPanelManager.swift:157-162); content swaps are unanimated (new NSHostingView per snapshot). Calendar row fade .easeInOut(0.25) (L566-570); re-measure token bumped immediately and again after 0.20 s on event change (L539-551). Ticker: Timer every 15.0 s (tolerance 0, .common) + minute-aligned timer only while locked and calendar row enabled (L71-205).

### State and timing

showWeatherWidget (LockScreenWeatherManager.swift:49-85): if a cached snapshot exists deliver it immediately (forceShow) then refresh(force: !hadSnapshot) and re-deliver only if still locked. Defaults observers rebuild the snapshot from the cached payload; provider/unit/AQI-scale changes clear the payload and force a refresh (L253-284). hide = alpha 0, orderOut, contentView nil, alpha 1, latestFrame nil (PanelManager L52-61).

### Data sources and APIs

Open-Meteo: https://api.open-meteo.com/v1/forecast?latitude&longitude&current=temperature_2m,weather_code,is_day,pressure_msl&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset&forecast_days=2&timezone=auto[&temperature_unit=fahrenheit] (LockScreenWeatherManager.swift:706-730) and https://air-quality-api.open-meteo.com/v1/air-quality?current=us_aqi|european_aqi&timezone=auto (L798-820); fallback https://wttr.in/[lat,lon]?format=j1&aqi=yes (L615-640; wttr has no AQI support). Both URL strings confirmed in the binary. Location: CLLocationManager desiredAccuracy kCLLocationAccuracyHundredMeters (L1092-1145; NSLocationWhenInUseUsageDescription in plist). Refresh gate Defaults.lockScreenWeatherRefreshInterval (1800 s) unless forced (L92-111); provider failure → fallback snapshot with temperature '--' and 'cloud.fill' (L132-165). Accessory data: BatteryStatusViewModel (isCharging/isPluggedIn/timeToFullCharge, debounced 150 ms), BluetoothAudioManager (connected device battery; refreshConnectedDeviceBatteries), CalendarManager.lockScreenEvents (EventKit; filters by lockScreenCalendarSelectionMode/IDs), DoNotDisturbManager (focus name/identifier; FocusModeType.resolvedActiveIcon(usePrivateSymbol: true) — uses private SF symbol names), CGSessionCopyCurrentDictionary for the ticker's lock state (L126-132). Charging label: 'Xh Ym' / 'Ym' remaining, else 'Fully charged' / 'N% • On hold' / 'Charging' (L1270-1308). Event line formats (L825-869): 'All-day • title'; active: '[HH:mm • ]title[ • Nm left]'; upcoming: 'HH:mm • title[ • in Nm]' with countdown 'Nm' or 'Nh Mm' / 'Nh'. Reminder is 'critical' (red, exclamationmark.triangle.fill multicolor) when it starts within reminderSneakPeekDuration seconds (L817-823).

### Settings

enableLockScreenWeatherWidget=true (Constants.swift:1095); lockScreenWeatherRefreshInterval=1800 (L1100, no UI); lockScreenWeatherShowsLocation=true (L1101); lockScreenWeatherShowsSunrise=true (L1102); lockScreenWeatherWidgetStyle=.inline (L1103; "Inline"/"Circular"); lockScreenWeatherTemperatureUnit=matchingSystemPreference via UnitTemperature(forLocale:) (L1104; enums/generic.swift:268-270); lockScreenWeatherShowsAQI=true (L1105); lockScreenWeatherAQIScale=.us (L1106; "U.S. AQI"/"EAQI"); lockScreenWeatherUsesGaugeTint=false (L1107); lockScreenWeatherProviderSource=.openMeteo (L1108; "wttr.in"/"Open Meteo"); lockScreenWeatherVerticalOffset=0 (L1109); lockScreenWeatherWidgetRowOrder="weather_calendar_focus" (L1163, no UI); enableLockScreenFocusWidget=true (L1096); battery sub-keys (stored under legacy 'lockScreenWeather*' names): lockScreenBatteryShowsBatteryGauge key "lockScreenWeatherShowsBatteryGauge"=hasBattery (L1189-1192), lockScreenBatteryUsesLaptopSymbol key "lockScreenWeatherBatteryUsesLaptopSymbol"=true (L1193), lockScreenBatteryShowsCharging key "lockScreenWeatherShowsCharging"=true (L1194), lockScreenBatteryShowsChargingPercentage key "lockScreenWeatherShowsChargingPercentage"=true (L1195), lockScreenBatteryShowsBluetooth key "lockScreenWeatherShowsBluetooth"=true (L1196); calendar: lockScreenShowCalendarEvent=true (L1153), lockScreenCalendarEventLookaheadWindow="3h" (L1154; 15m/30m/1h/3h/6h/12h/rest_of_day/all_time), lockScreenCalendarSelectionMode="all" (L1155), lockScreenSelectedCalendarIDs=[] (L1156), lockScreenShowCalendarCountdown=true (L1157), lockScreenShowCalendarEventEntireDuration=true (L1158), lockScreenShowCalendarEventAfterStartEnabled=false (L1159), lockScreenShowCalendarEventAfterStartWindow="5m" (L1160; 1m/5m/10m/15m/30m/45m/1h/2h), lockScreenShowCalendarTimeRemaining=true (L1161), lockScreenShowCalendarStartTimeAfterBegins=true (L1162); lockScreenReminderChipStyle=.eventColor (L1150); reminderSneakPeekDuration=5 (L1336); appearance lockScreenWidgetAppearance=.dark (L1118; .dark = white glyphs).

### Dependencies

open-meteo SDK package is resolved but the manager uses plain URLSession + JSONDecoder; CoreLocation; EventKit.

### Implementation notes

All public except the SkyLight delegation and the focus icon's private symbol flag. Reimplement as a pure SwiftUI 'StatusCapsule' fed by a Sendable snapshot struct (temperatureText, symbolName, locationName, charging, bluetooth, battery, airQuality, widgetStyle, sunCycle flags…); keep the Open-Meteo query exactly (no key needed) and the 30-min gate; wttr fallback optional. Use `Gauge` styles as above and the hand-drawn arc for tinted temperature. ~900 lines.

### Key files

- `managers/LockScreenWeatherManager.swift`
- `managers/LockScreenWeatherPanelManager.swift`
- `components/LockScreen/LockScreenWeatherWidget.swift`
- `components/LockScreen/LockScreenCalendarEventRow.swift`
- `components/LockScreen/LockScreenWidgetAppearance+Colors.swift`
- `enums/generic.swift`

## Lock-screen timer widget (LockScreenTimerWidgetManager/PanelManager + LockScreenTimerWidget)

### Behaviour

When a manual Atoll timer is running and the Mac locks, a 420x96 rounded card appears between the weather capsule and the media panel with two 48pt circular buttons on the left (pause/resume with the preset's accent tint, and cancel/stop) and a large bold rounded countdown on the right tinted with the preset color (red when in overtime). Pausing/stopping works from the lock screen. Surfaces: classic translucent black, frosted glass, standard liquid glass (macOS 26) or custom liquid variant.

### Layout

LockScreenTimerWidget (components/LockScreen/LockScreenTimerWidget.swift): defaultWidth 420, preferredHeight 96, preferredSize = (Defaults.lockScreenTimerWidgetWidth, 96), cornerRadius 26 (L23-28). Body: VStack(spacing 16){ HStack(spacing 0){ controlButtons.padding(.trailing 12); Spacer; countdownSection.padding(.leading 12) } } .padding(.horizontal 12, .vertical 12) .frame(widgetSize) .background(widgetBackground with colorScheme = appearance.materialColorScheme) .clipShape(RoundedRectangle 26 continuous) .overlay(stroke appearance.primary(0.08) 1pt) .shadow(black 0.25, radius 18, y 16) .overlay(topLeading accentRibbon: Capsule 110x26 accentGradient blur 12 offset(18,-6) opacity 0.45) (L179-210, 253-260). Buttons: HStack(spacing 10) CircleButton 48x48, glyph 18pt semibold, background opacity 0.7 (hover 0.9), disabled 0.25/0.4 opacity (L212-234, 291-322); pause button background accentColor.opacity(0.32), stop button black 0.35 (dark) / black 0.12 (light); pause hidden in overtime. Countdown: font 46pt bold rounded (42 when ≥10 h), monospacedDigit, frame width 160 / 185 (≥1 h) / 200 (≥10 h), minScale 0.68, contentTransition .numericText (L49-66, 236-251). Backgrounds: classic = black 0.65 (dark) / white 0.7 (light); frosted = .ultraThinMaterial; standard liquid = glassEffect(.clear.tint(accent 0.18).interactive()); custom = LiquidGlassBackground over black 0.12 (L115-157). accentColor = (preset color ?? timerManager.timerColor).ensureMinimumBrightness(0.75). Window frame (LockScreenTimerWidgetManager.swift:269-294): x centered; baseY = screen.midY + 24 - 18; + clamp(lockScreenTimerVerticalOffset, ±160); capped below weather frame (weather.minY - h - 20) or screen.maxY - h - 72; floored above music panel (music.maxY + 12) and screen.minY + 100.

### Animations

Presentation: scaleEffect 0.9→1 + opacity with .spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.22) (L207-209); hide delay 360 ms (hideAnimationDurationNanoseconds, Manager L133, 164-189); position refresh 0.22 s easeInEaseOut (L192-207); countdown text .smooth(0.25). Stop from the widget hides first, then stops the timer after 360 ms (Widget L271-289).

### State and timing

shouldDisplayWidget = enableLockScreenTimerWidget && (previewing ? isTimerActive : (isLocked && hasManualTimerRunning)) (Manager L120-127); observes TimerManager.$isTimerActive+$activeSource and the three Defaults keys; show/hide notify LockScreenPanelManager.notifyTimerWidgetFrameChanged and the reminder panel to re-layout.

### Data sources and APIs

TimerManager (isTimerActive, activeSource, hasManualTimerRunning, remainingTime, isPaused, isOvertime, allowsManualInteraction, activePresetId, formattedRemainingTime). Window: CGShieldingWindowLevel + PRIVATE SkyLight; glassEffect public (macOS 26); LiquidGlassBackground private variant hack.

### Settings

enableLockScreenTimerWidget=true (Constants.swift:1099); lockScreenTimerVerticalOffset=0 (L1116); lockScreenTimerWidgetWidth=350 (L1117) — NOTE the view's defaultWidth/reset value is 420 (LockScreenTimerWidget.swift:23), so a fresh install renders 350 wide until 'Reset Timer Width'; lockScreenTimerWidgetUsesBlur=false (L1149; UI 'Timer surface' Classic/Glass); lockScreenTimerGlassStyle=.frosted (L1124); lockScreenTimerGlassCustomizationMode=.standard (L1125); lockScreenTimerLiquidGlassVariant=.v11 (L1133); timerPresets=TimerPreset.defaultPresets (L1320).

### Dependencies

Defaults.

### Implementation notes

Public SwiftUI card; reuse NotchIsland timer model. Only show for manual timers while locked (mirrored system timers excluded). ~300 lines.

### Key files

- `components/LockScreen/LockScreenTimerWidget.swift`
- `managers/LockScreenTimerWidgetManager.swift`

## Lock-screen reminder chip (LockScreenReminderWidgetManager/PanelManager + LockScreenReminderWidget)

### Behaviour

When the reminder live activity has a current reminder/event snapshot and the Mac is locked, a single-line transparent chip appears between the media panel and the weather capsule: SF icon, a 9x20 colored bar (event color or white), the title, optional relative text ('in 5 min'), and the time, separated by '•'. Critical (imminent) items turn red. Horizontal alignment left/center/right and a ±160pt vertical offset are configurable.

### Layout

LockScreenReminderWidget (components/LockScreen/LockScreenReminderWidget.swift:22-127): primaryFont 19pt semibold rounded; iconSize 20; chipWidth 9; HStack(spacing 8){ Image(iconName) 20pt semibold; RoundedRectangle(2) chip 9x20; Text(title) lineLimit 1 minScale 0.85 priority 1; ['•' + relative]; '•'; eventTimeText } .padding(.horizontal 16, .vertical 12) .frame(minWidth 240, idealWidth 360, maxWidth 520, alignment .leading) .shadow(appearance.contentShadow radius 8 y 3). Colors: title appearance.primary(0.92), secondary 0.78 (1.0 when critical), separators 0.65, chip = red if critical else event color (brightened to 0.7 on dark appearance) or primary(0.85) monochrome. Window (LockScreenReminderWidgetPanelManager.swift:126-173): size = fittingSize; x by alignment with 24pt side padding; lowerBound = max(timer.maxY + 24 or music.maxY + 16 (music default midY-32), screen.minY+80); upperBound = weatherBottom - 16 - h where weatherBottom = weather.minY or min(screen.maxY-120, max(midY + h*0.14, lower+h+16)); y = timer present ? upperBound : midpoint, + clamp(offset, ±160), clamped to bounds.

### Animations

Position refresh 0.22 s easeInEaseOut (L58-70); content is replaced unanimated.

### State and timing

Shows on lock if a snapshot exists, hides on unlock; snapshot updates while locked re-render; toggling the chip-style/alignment/offset keys re-renders or re-positions (Manager L76-109).

### Data sources and APIs

ReminderLiveActivityManager.$lockScreenSnapshot (LockScreenReminderWidgetSnapshot: title, eventTimeText, relativeDescription, accent RGBA, chipStyle, isCritical, iconName; models/LockScreenReminderWidgetSnapshot.swift:22-49). Window: CGShieldingWindowLevel + PRIVATE SkyLight; ignoresMouseEvents true.

### Settings

enableLockScreenReminderWidget=true (Constants.swift:1098); lockScreenReminderChipStyle=.eventColor (L1150; "Event color"/"White"); lockScreenReminderWidgetHorizontalAlignment="center" (L1151; leading/left, trailing/right, else center); lockScreenReminderWidgetVerticalOffset=0 (L1152); enableReminderLiveActivity=true (L1333) is the upstream producer.

### Dependencies

Defaults.

### Implementation notes

Trivial SwiftUI row; the snapshot type is already Sendable-friendly. ~150 lines.

### Key files

- `components/LockScreen/LockScreenReminderWidget.swift`
- `managers/LockScreenReminderWidgetManager.swift`
- `managers/LockScreenReminderWidgetPanelManager.swift`
- `models/LockScreenReminderWidgetSnapshot.swift`

## Lock-screen widget preview (Settings ▸ Lock Screen ▸ Preview) and shared appearance/glass model

### Behaviour

A 'Preview' button in Lock Screen settings opens a resizable, closable window titled 'Lock Screen Preview' showing the desktop wallpaper with the media panel, timer (a demo 29:43 timer is started if none runs) and weather capsule laid out exactly as on the lock screen using mock weather, a fake 'Do Not Disturb' focus and preview calendar events. Any lock-screen setting change re-renders it live; closing restores focus/calendar state and stops the demo timer. Separately, a 'Widget appearance' Dark/Light switch flips every widget between white and black glyphs, and a global 'Material' (Liquid/Frosted) + 'Standard/Custom Liquid' mode with per-widget variant sliders (0…19) controls the glass look.

### Layout

Preview window: NSWindow(contentRect: screen.frame, styleMask [.titled, .closable, .miniaturizable, .resizable]), title 'Lock Screen Preview', backgroundColor .clear, centered (LockScreenWidgetPreviewManager.swift:199-242). LockScreenPreviewScene (L380-519) scales the real screen size to fit and re-implements the three frame formulas (media: baseY = midY - h - 32, defaultLowering -28 here vs -68 in the live manager; timer and weather formulas identical to the live managers). Demo timer duration 1783 s (L86). Settings variant preview cell: 'glassdesktop' image, 190x96 liquid glass sample, radius 16 outer / 14 inner, height 120 (SettingsView.swift:6525-6573). Icon style cards 72x50 radius 12 (L6471-6523).

### Animations

None beyond the embedded widgets' own.

### State and timing

togglePreview/showPreview/hidePreview (L41-63); PreviewWindowDelegate.windowWillClose → hidePreview.

### Data sources and APIs

Observes 17 lock-screen Defaults keys (L96-114); mutates DoNotDisturbManager (isDoNotDisturbActive=true, name 'Do Not Disturb', id 'com.apple.donotdisturb') and CalendarManager.setLockScreenPreviewEvents (L279-302); WallpaperView loads the desktop picture (L535+). Public.

### Settings

lockScreenWidgetAppearance=.dark (Constants.swift:1118; usesLightGlyphs when .dark); lockScreenGlassStyle=.liquid (L1119); lockScreenGlassCustomizationMode=.standard (L1120); lockScreenMusicLiquidGlassVariant=.v11 (L1129); lockScreenTimerLiquidGlassVariant=.v11 (L1133); the onboarding profile step forces liquid/customLiquid/v11 on macOS 26 (ProfileSelectionView.swift:279-284).

### Dependencies

Defaults.

### Implementation notes

Useful for NotchIsland's design-QA: a normal window hosting the same SwiftUI widgets with the same frame math. ~250 lines.

### Key files

- `managers/LockScreenWidgetPreviewManager.swift`
- `components/Settings/SettingsView.swift`
- `enums/generic.swift`
- `helpers/LiquidGlassBackground.swift`

## Settings window shell: SettingsWindowController + SettingsView (NavigationSplitView, groups, tabs, search, highlight)

### Behaviour

'Atoll Settings' is a 700pt-wide window (initial 700x600, resizable) with a sidebar: a 'Search Settings' field with up to 8 live suggestions, then grouped rows (General, Appearance | Media & Display: Media, Live Activities, Lock Screen, Devices | System: Controls, Battery | Productivity: Timer, Calendar, Notes | Utilities: Clipboard, Screen Assistant, Color Picker, Shelf, Downloads (BETA), Shortcuts | Developer: Stats, Terminal | Integrations: Extensions (BETA) | About). Minimalistic UI hides Timer, Stats, Clipboard, Screen Assistant, Color Picker, Shelf, Notes, Terminal. Picking a suggestion jumps to the tab, switches the Lock Screen segment if needed, scrolls the row into view and highlights it. Opening the window makes Atoll a regular app (Dock icon); closing returns to accessory mode.

### Layout

SettingsWindowController (components/Settings/SettingsWindowController.swift:27-152): NSWindow 700x600, styleMask [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], title 'Atoll Settings', toolbarStyle .unified, isMovableByWindowBackground, level .normal, collectionBehavior [.managed, .participatesInCycle], isRestorable true, identifier 'DynamicIslandSettingsWindow', registered with ScreenCaptureVisibilityManager scope .panelsOnly; showWindow centers, activates and re-asserts regular semantics; close/windowWillClose → orderOut + setActivationPolicy(.accessory); windowDidBecomeKey → .regular. SettingsView (SettingsView.swift:608-694): NavigationSplitView(.balanced), .formStyle(.grouped), .frame(width: 700), sidebar VStack(spacing 12){ search bar padding 12 ; Divider ; List(selection) SidebarListStyle minWidth 200, column width min 200 / ideal 210 / max 240, defaultMinListRowHeight 44 }, sidebar toggle removed, toolbar spacer 96x32; background = macOS 26 glassEffect(.clear.tint(white 0.1).interactive(), radius 18) else windowBackgroundColor + .ultraThinMaterial radius 18. Sidebar row (L735-792): HStack(spacing 10) 26x26 RoundedRectangle(8) gradient tint→tint 0.7, white 0.2 0.7pt border (plusLighter), shadow tint 0.35 r2 y1, SF icon 13pt semibold white, title; 'BETA' capsule (9pt bold, blue) for Downloads and Extensions; row vertical padding 4. Tab icons/tints (L114-164): general gear/.blue, liveActivities waveform.path.ecg/.pink, appearance paintpalette/.purple, lockScreen lock.laptopcomputer/.orange, media play.laptopcomputer/.green, devices headphones/Color(0.1,0.11,0.12), extensions puzzlepiece.extension/Color(0.557,0.353,0.957), timer timer/.red, calendar calendar/.cyan, hudAndOSD dial.medium.fill/.indigo, battery battery.100.bolt/Color(0.202,0.783,0.348), stats chart.xyaxis.line/.teal, clipboard clipboard/.mint, screenAssistant brain.head.profile/.pink, colorPicker eyedropper/.accentColor, downloads square.and.arrow.down/.gray, shelf books.vertical/.brown, shortcuts keyboard/.orange, notes note.text/Color(0.979,0.716,0.153), terminal apple.terminal/Color(0.2,0.8,0.4), about info.circle/.secondary. Search field: HStack(spacing 6) magnifyingglass + TextField(.plain) + clear button, padding h10 v8, .ultraThinMaterial radius 12, white 0.08 stroke; suggestion rows 28x28 tint tile, 13pt semibold title + 11pt tab, padding h10 v7, dividers inset 48, list shadow black 0.2 r8 y4 (L870-995). Lock Screen tab is split into two segments 'General'/'Widgets' via SettingsSegmentedPicker (L208-220, 5770-5777).

### Animations

Scroll-to-highlight .easeInOut(0.45) (L599-603); suggestion list .easeInOut(0.15) with .opacity + .move(.top) transition (L885, 978). SettingsHighlightCoordinator drives a temporary highlight (L493-585).

### State and timing

selectedTab/searchText @State; search filters tabs whose title or any entry matches; first match auto-selected (L667-673).

### Data sources and APIs

SwiftUI NavigationSplitView/List/Form; Defaults.Toggle; Sparkle updater passed to About. Public.

### Settings

Search index: SettingsSearchIndex.entries (SettingsView.swift:222-484) — one entry per searchable row (title + keywords + highlightID, Lock Screen rows carry a lockScreenSection). Tab visibility: isTabVisible hides the eight utility/dev tabs when enableMinimalisticUI (L1013-1020). Default selected tab .general.

### Dependencies

Defaults, Sparkle, LaunchAtLogin, KeyboardShortcuts (recorders).

### Implementation notes

NotchIsland's SettingsView can adopt the same grouped sidebar with 44pt rows, 26pt gradient icon tiles and a search index table of (tab, title, keywords, highlightID). Keep .formStyle(.grouped) and `Section { } header: { } footer: { }`. ~700 lines for the shell + search.

### Key files

- `components/Settings/SettingsWindowController.swift`
- `components/Settings/SettingsView.swift`

## Settings catalogue A — General, Appearance, Media, Live Activities, Devices, Controls (HUD & OSD), Battery

### Behaviour

Each tab is a grouped Form of Sections (header/footer text) using Defaults.Toggle, Picker, Slider, Stepper and the custom SettingsSegmentedPicker; values apply immediately.

### Layout

General (SettingsView.swift:1119-1460) sections: UI Mode; System features; Keep Awake; Notch Height (+ 'Quit app' button); Gesture control; Notch behavior. Appearance (L4861-5530): General; Display Style (non-notch main screen); Media; Custom music live activity animation; Custom vizualizers (Lottie) with add sheet (Name, Lottie JSON URL, Speed 0…2 step 0.1); Additional features (mirror); IdleAnimationsSettingsSection + AnimationEditorView; App icon (drop PNG/JPEG/TIFF/ICNS); Notch Width. Media (L3156-3670): Media Source (MusicSourceSelector cards; YouTube Music link th-ch/youtube-music; Spotify Canvas Session sp_dc cookie; Spotify Like Button OAuth client ID; Cider token); Dynamic Island Visibility; Media controls (+ MusicSlotConfigurationView drag palette); Lock Screen Media; Skip button behaviour; Media playback live activity; Music Visualizer; Lock Screen Integration (mirror of Lock Screen tab); Hide DynamicIsland Options picker. Live Activities (L4600-4860): Screen Recording (+ live detection status); Do Not Disturb (+ status); Caps Lock Indicator; Privacy Indicators (+ camera/mic status); Media Live Activity; Reminder Live Activity. Devices (L2720-2838): App Volume; Bluetooth Audio Devices; Battery Indicator Styling. Controls = HUDAndOSDSettingsView (L1959-2720) with 4 HUDSelectionCards (Dynamic Island HUD / Custom OSD (macOS 15+) / Vertical Bar / Circular) then mode-specific sections, plus ExternalDisplayIntegrationsSection (Step size; third-party DDC). Battery = Charge (L1462-1712): General; Battery Information; Battery HUDs; HUD Duration; HUD Tests (3 buttons); Low Battery; Full Battery; non-MacBooks see 'Battery settings and informations are only available on MacBooks'.

### Animations

n/a

### State and timing

n/a

### Data sources and APIs

Defaults keys below; LaunchAtLogin.Toggle (SMAppService); NSScreen.screens names for display picker; AVCaptureDevice list for Mirror Camera.

### Settings

GENERAL: enableMinimalisticUI=false (Constants.swift:1503) 'Enable Minimalistic UI'; showMinimalisticBatteryIndicator=true (L1175); showBatteryPercentInside=true (L1174); menubarIcon=true (L988); Launch at login (SMAppService, no key); showOnAllDisplays=false (L989); preferred_screen_name (AppStorage) 'Show on a specific display'; automaticallySwitchDisplay=true (L990); hideDynamicIslandFromScreenCapture=false (L992); enableCaffeinate=true (L1346) 'Enable Keep Awake'; showCaffeinateIcon=true (L1347); caffeinateDefaultDuration=.indefinite (L1348; indefinite/15/30 min/1/2/4 h, Constants.swift:694-726); caffeinateKeepsDisplayAwake=true (L1349); notchHeightMode=.matchRealNotchSize (L1004) with notchHeight=32 slider 15…45 step 1 (L1013; UI L1288); nonNotchHeightMode=.matchMenuBar (L1008) with nonNotchHeight=32 slider 0…40 (L1012; UI L1315); enableGestures=true (L1054); enableHorizontalMusicGestures=true (L1057); musicGestureBehavior=.track (L1058; track/tenSecond); reverseSwipeGestures=false (L1059); closeGestureEnabled=true (L1055); gestureSensitivity=200 slider 100…300 step 100 (L1056); reverseScrollGestures=false (L1060); extendHoverArea=false (L998); enableHaptics=true (L996); openNotchOnHover=true (L997); openLastTabByDefault (AppStorage false) 'Remember last tab'; minimumHoverDuration=0.3 slider 0…1 step 0.1 (L995); externalDisplayStyle=.notch (L999; 'Standard Notch'/'Dynamic Island'); hideNonNotchUntilHover=false (L1003). APPEARANCE: alwaysShowTabs (AppStorage true); settingsIconInNotch=true (L1025); enableShadow=true (L1028); cornerRadiusScaling=true (L1029); useModernCloseAnimation=true (L1030) 'Use simpler close animation'; externalDisplayStyle 'Main screen style'; coloredSpectrogram=true (L1063); playerColorTinting=true (L1043); lightingEffect=true (L1026) 'Enable blur effect behind album art'; sliderColor key "sliderUseAlbumArtColor"=.white (L1039; White/Match album art/Accent color); useMusicVisualizer=true (L1044); selectedVisualizer=nil (L1049); customVisualizers=[] (L1048); showMirror=false (L1022); mirrorShape=.rectangle (L1023; raw 'Rectangular'/'Circular', UI 'Square'/'Circle'); selectedCameraID="" (L1024); showNotHumanFace=false (L1031) 'Idle Animation'; customIdleAnimations=[] (L1032); selectedIdleAnimation=nil (L1033); animationTransformOverrides=[:] (L1034; AnimationTransformConfig defaults scale 1, offset 0/0, crop 30x20, rotation 0, opacity 1, paddingBottom 0, expandWithAnimation false, loopMode .loop, Constants.swift:100-113); customAppIcons=[] (L1050); selectedAppIconID=nil (L1051); customizePhysicalNotchWidth=false (L1016); closedNotchWidth=150 (L1015); openNotchWidth=640 (L1014; min = recommended from enabled tab count, max = screen width − 60). MEDIA: mediaController = .appleMusic on macOS ≥15.4 else .nowPlaying (L1243, 1529-1535; cases Now Playing/Apple Music/Spotify/Youtube Music/Amazon Music/TIDAL/Cider); spotifySPDCCookie="" (L1244); spotifyLibraryClientID="" (L1248); showStandardMediaControls=true (L1088); autoHideInactiveNotchMediaPlayer=true (L1089); showShuffleAndRepeat=true (L1071) 'Enable customizable controls'; showMediaOutputControl=true (L1072); musicControlSlots=defaultLayout (L1084); lockScreenMusicAlbumParallaxEnabled=false (L1115); alwaysShowLockScreenVolume=false (L1080); musicSkipBehavior=.track (L1086); musicLiveActivityEnabled (AppStorage true); musicControlWindowEnabled=false (L1087) 'Show floating media controls'; enableSneakPeek=false (L1065); showSneakPeekOnTrackChange=true (L1067); enableLyrics=false (L1506); lyricHighlightStyle=.sweep (L1509; Sweep/Gradient/Solid); pinLyricsWhenClosed=false (L1512); pinnedLyricContext=.current (L1511; 1/3/5 lines); lyricsPanelWidth=280 slider 180…420 step 10 (L1513); lyricsPanelOffset=0 slider −100…100 (L1514); showLiveCanvasInDynamicIsland=false (L1515); parallaxEffectIntensity=6.0 slider 0…12 (L1069); sneakPeekStyles=.standard (L1066; 'Default'/'Inline'); waitInterval=3 stepper 0…10 s (L1070) 'Media inactivity timeout'; showSongMetadataInClosedNotch=false (L1644); enableRealTimeWaveform=false (L1064); visualizerBarCount=4 (4/5/6) (L1045); colorExtractionMode=.vibrant (L1047); enableWaveformScrubber=true (L1046); hideNotchOption=.nowPlayingOnly (L1237); plus the lock-screen mirror keys listed under the media-panel feature. LIVE ACTIVITIES: enableScreenRecordingDetection=true (L1468); showRecordingIndicator=true (L1469); recordingControlMode=.withStopButton (L1471); recordingHoverStyle=.default (L1470); enableDoNotDisturbDetection=true (L1476); showDoNotDisturbIndicator=true (L1478); showDoNotDisturbLabel=true (L1479); focusIndicatorNonPersistent=false (L1480) 'Show Focus as brief toast'; enableCapsLockIndicator=true (L1492); showCapsLockLabel=false (L1497); capsLockIndicatorTintMode=.white (L1494; green/accent/white); enableCameraDetection=true (L1483); enableMicrophoneDetection=true (L1484); enableReminderLiveActivity=true (L1333). DEVICES: enablePerAppVolume=false (L1341); showPerAppVolumeIcon=true (L1342); perAppVolumeLevels=[:]/perAppVolumeMuted=[] (L1343-1344); showBluetoothDeviceConnections=true (L1271); useCircularBluetoothBatteryIndicator=true (L1275); showBluetoothBatteryPercentageText=false (L1276); showBluetoothDeviceNameMarquee=false (L1277); showAirPodsListeningModeChanges=true (L1279); useBluetoothHUD3DIcon=true (L1278); useColorCodedBatteryDisplay=true (L1272). CONTROLS: enableSystemHUD=true (L1400); enableCustomOSD=false (L1414); enableVerticalHUD=false (L1415); enableCircularHUD=false (L1416); enableVolumeHUD/enableBrightnessHUD/enableKeyboardBacklightHUD=true (L1401-1403); systemHUDSensitivity=5 (L1404); playVolumeChangeFeedback=false (L1405); useColorCodedVolumeDisplay=true (L1273); useSmoothColorGradient=true (L1274); showProgressPercentages=true (L1212); inlineHUD=true (L1206) 'HUD style' Default(false)/Inline(true); progressBarStyle=.hierarchical (L1207; Hierarchical/Gradient/Segmented); systemEventIndicatorShadow=false (L1210) 'Enable glowing effect'; systemEventIndicatorUseAccent=false (L1211); verticalHUDShowValue=true (L1420); verticalHUDUseAccentColor=false (L1425); verticalHUDInteractive=true (L1421); verticalHUDMaterial=.frosted (L1426); verticalHUDLiquidGlassCustomizationMode=.standard (L1427); verticalHUDLiquidGlassVariant=.v11 (L1431); verticalHUDPosition="right" (L1417); verticalHUDPadding=24 slider 0…100 step 4 (L1424); verticalHUDWidth=36 slider 24…80 step 2 (L1423); verticalHUDHeight=160 slider 100…500 step 10 (L1422); circularHUDShowValue=true (L1437); circularHUDUseAccentColor=true (L1440); circularHUDSize=65 slider 40…200 step 5 (L1438); circularHUDStrokeWidth=4 slider 2…16 (L1439); enableOSDVolume/Brightness/KeyboardBacklight=true (L1453-1455); osdMaterial=.frosted (L1456); osdLiquidGlassCustomizationMode=.standard (L1457); osdLiquidGlassVariant=.v11 (L1461); osdIconColorStyle=.white (L1465); hasSeenOSDAlphaWarning=false (L1452); volumeStepPercent=6, volumeFineStepPercent=2, brightnessStepPercent=6, brightnessFineStepPercent=2, steppers 1…25 (L1408-1411); enableThirdPartyDDCIntegration=false (L1443); thirdPartyDDCProvider=.betterDisplay (L1444; BetterDisplay/Lunar); enableExternalVolumeControlListener=false (L1445). BATTERY: showBatteryIndicator=hasBattery (L1172); showPowerStatusNotifications=true (L1171); playLowBatteryAlertSound=true (L1177); showBatteryPercentage=true (L1173); showPowerStatusIcons=true (L1176); showChargingBatteryHUD/showLowBatteryHUD/showFullBatteryHUD=true (L1178-1180); chargingBatteryHUDDuration/lowBatteryHUDDuration/fullBatteryHUDDuration=3 s sliders 1…10 (L1181-1183); lowBatteryHUDStyle=.standard (L1186; standard/compact); lowBatteryHUDThreshold=20 slider 5…30 (L1184); fullBatteryHUDStyle=.standard (L1187); fullBatteryHUDThreshold=100 slider 80…100 (L1185).

### Dependencies

Defaults, LaunchAtLogin-Modern.

### Implementation notes

Map 1:1 onto NotchIsland UserSettings; keep key names so a future importer can read Atoll prefs.

### Key files

- `components/Settings/SettingsView.swift`
- `models/Constants.swift`
- `components/Settings/IdleAnimationsSettingsSection.swift`
- `components/Settings/AnimationEditorView.swift`
- `components/Settings/MusicSlotConfigurationView.swift`
- `components/Settings/SpotifyAuthSettingsSection.swift`
- `components/Settings/SpotifyLikeButtonSettingsSection.swift`
- `components/Settings/CiderFavoritingSettingsSection.swift`

## Settings catalogue B — Lock Screen, Timer, Calendar, Notes, Clipboard, Screen Assistant, Color Picker, Shelf, Downloads, Stats, Terminal, Extensions, About

### Behaviour

Same grouped-Form pattern. Lock Screen has a General/Widgets segmented switch: General = Live Activity & Feedback (icon cards Lock/Fingerprint, lock sounds), Siri Detection, Lock Screen Glass (Material, Standard/Custom Liquid), Diagnostics ('Copy Latest Crash Report'); Widgets = Preview, Appearance (Dark/Light glyphs, Inline/Circular layout), Media Panel, Timer Widget, Weather Widget, Reminder Widget, Battery Widget (MacBooks), Focus Widget, Calendar Widget, Lock Screen Positioning (draggable preview of weather/timer/media offsets ±160 pt with reset buttons, and width sliders for media panel and timer).

### Layout

LockScreenSettings SettingsView.swift:5638-6470; LockScreenPositioningControls L6575-6838 (offsetRange −160…160, L6854; preview panels at 28%/50%/78% of a 26pt-inset mock screen with radius 28, interactiveSpring(0.3, 0.82)); Shortcuts L7107-7377; TimerSettings L7377-7974 (preset editor rows with name TextField, h/m/s steppers, ColorPicker, move up/down/delete; Timer Sound file picker, default dynamic.m4a); CalendarSettings L3671-4125 (permission callout, calendar multi-select); StatsSettings L7974-8463 (New API account editor: name, Base URL, API key → Keychain); ClipboardSettings L8463-8651; ScreenAssistantSettings L8651-8829; ColorPickerSettings L8829-8951; Shelf L4415-4600 (+ LocalSendSettingsSection); Downloads L1712-1847; NotesSettingsView L9219-9318; TerminalSettings L9318-9598; ExtensionsSettingsView components/Settings/ExtensionsSettings.swift (Get Extensions → getatoll.app/marketplace, Global Settings, App Permissions list with Allowed Features toggles and 'Recent Activity (last 5 minutes)' counters); About L4125-4415 (Version info incl. release name & build, Donate/GitHub, Update channel picker + 'Current build', UpdaterSettingsView toggles, 'Made with ❤️ by Ebullioscopic').

### Animations

n/a

### State and timing

n/a

### Data sources and APIs

Defaults; EventKit authorization (Calendar tab Request Access/Open System Settings); Keychain for New API keys and Spotify tokens; Sparkle SPUUpdater.automaticallyChecksForUpdates/automaticallyDownloadsUpdates (SoftwareUpdater.swift:52-82).

### Settings

LOCK SCREEN (see also widget features): enableLockScreenLiveActivity=true; lockScreenLiveActivityIconStyle=.lock; enableLockSounds=true; siriResponsivenessMode=.automatic; lockScreenGlassStyle=.liquid ('Liquid Glass requires macOS 26 or later'); lockScreenGlassCustomizationMode=.standard; lockScreenWidgetAppearance=.dark; lockScreenWeatherWidgetStyle=.inline ('Widget layout'); media/timer/weather/reminder/battery/focus/calendar keys as listed in their features; positioning: lockScreenWeatherVerticalOffset=0, lockScreenMusicVerticalOffset=0, lockScreenTimerVerticalOffset=0 (Constants.swift:1109,1110,1116; all clamped ±160), lockScreenMusicPanelWidth=390 (L1111), lockScreenTimerWidgetWidth=350 (L1117). TIMER: enableTimerFeature=true (L1318); timerLiveActivityEnabled (AppStorage true); mirrorSystemTimer=true (L1328) 'Mirror macOS Clock timers'; timerDisplayMode=.tab (L1319; tab/popover); enableLockScreenTimerWidget + glass keys (mirror); 'Default Custom Timer' steppers (storage key not in Constants — TimerManager, unknown); timerIconColorMode=.adaptive (L1322; 'Adaptive'/'Solid'); timerSolidColor=.blue (L1323); timerProgressStyle=.bar (L1327; Bar/Ring); timerShowsLabel=false (L1325); timerShowsCountdown=true (L1324); timerShowsProgress=true (L1326); showTimerPresetsInNotchTab=true (L1321); timerControlWindowEnabled=true (L1338) 'Show pause/stop controls in the notch'; timerInputStyle=.manual (L1329; Ruler/Manual); timerPresets=defaultPresets (L1320). CALENDAR: showCalendar=true (L1036); hideCompletedReminders=true (L1037); showFullEventTitles=false (L1231); autoScrollToNextEvent=true (L1232); hideAllDayEvents=false (L1038); enableReminderLiveActivity=true (L1333); reminderPresentationStyle=.ringCountdown (L1334; Ring/Digital/Minutes); reminderLeadTime=5 min (L1335) 'Notify before'; reminderSneakPeekDuration=5 s (L1336); enableLockScreenReminderWidget=true; lockScreenReminderChipStyle=.eventColor; lock-screen calendar keys (mirror); enableThirdPartyCalendarApp=false (L1166); selectedCalendarApp=.fantastical (L1167; fantastical/notionCalendar); fantasticalDefaultView=.mini (L1168; mini/calendar); calendarSelectionState=.all (L1230). NOTES: enableNotes=false (L1518); enableNotePinning=true (L1519); enableNoteSearch=false (L1520); enableNoteColorFiltering=false (L1521); enableCreateFromClipboard=true (L1522); enableNoteCharCount=true (L1523); enableAppleNotesSync=false (L1525); appleNotesLastSyncDate=nil (L1526); savedNotes=[] (L1524). CLIPBOARD: enableClipboardManager=true (L1359); persistClipboardHistory=true (L1364) 'Save History Across Restarts'; showClipboardIcon=true (L1365); clipboardDisplayMode=.panel (L1366; popover/panel/separateTab/notchTab); clipboardHistorySize=3 (3/5/7/10) (L1360). SCREEN ASSISTANT: enableScreenAssistant=true (L1369); geminiApiKey="" (L1371); screenAssistantDisplayMode=.panel (L1370); (defined, no UI: openaiApiKey/claudeApiKey/groqApiKey="", selectedAIProvider=.gemini, selectedAIModel=nil, enableThinkingMode=false, localModelEndpoint="http://localhost:11434" L1372-1378). COLOR PICKER: enableColorPickerFeature=true (L1352); showColorPickerIcon=true (L1356); colorPickerDisplayMode=.panel (L1354); colorHistorySize=10 (5/10/15/20) (L1355); showColorFormats=true (L1353). SHELF: dynamicShelf=true (L1215); openShelfByDefault=true (L1216); expandedDragDetection=true (L1227); copyOnDrag=false (L1221); allowMoveOnDrag=false (L1225); autoRemoveShelfItems=false (L1226); quickShareProvider="AirDrop" (L1217); localSendSelectedDeviceID="" (L1218); localSendDevicePickerGlassMode=.standard (L1219); localSendDevicePickerLiquidGlassVariant=.v11 (L1220). DOWNLOADS (BETA): enableDownloadListener=true (L1199); selectedDownloadIndicatorStyle=.progress (L1201; Progress/Percentage/Circle); showDownloadSpeed=false (L1202); selectedDownloadIconStyle=.onlyAppIcon (L1203); enableSafariDownloads=true (L1200, no UI). STATS: enableStatsFeature=false (L1282); enableLLMUsageFeature=false (L1283); enableClaudeProvider/enableCodexProvider/enableCursorProvider/enableAntigravityProvider=true (L1284-1287); enableNewAPIProvider=false (L1288); newAPIAccounts=[] (L1289); autoStartStatsMonitoring=true (L1290); statsStopWhenNotchCloses=true (L1291); statsUpdateInterval=1.0 slider 1…60 (L1292); showCpuGraph=true, showMemoryGraph=true, showGpuGraph=true, showNetworkGraph=false, showDiskGraph=false (L1293-1297); cpuTemperatureUnit=matchingSystemPreference (L1298). TERMINAL: enableTerminalFeature=false (L1301); terminalStickyMode=false (L1315); terminalShellPath="/bin/zsh" (L1302); terminalFontFamily="" (L1303; 'System Monospaced'); terminalFontSize=12 slider 8…24 (L1304); terminalOpacity=1.0 slider 0.3…1.0 step 0.05 (L1305); terminalMaxHeightFraction=0.4 slider 0.2…0.5 step 0.05 (L1306); terminalBackgroundColor=.black, terminalForegroundColor=.white, terminalCursorColor=Color(.selectedControlColor) (L1312-1314); terminalBoldAsBright=true (L1311); terminalCursorStyle="blinkBlock" (L1307); terminalScrollbackLines=1000 (L1308); terminalOptionAsMeta=true (L1309); terminalMouseReporting=true (L1310). EXTENSIONS (BETA): enableThirdPartyExtensions=true (L1381); enableExtensionLiveActivities=true (L1382); enableExtensionLockScreenWidgets=true (L1383); enableExtensionNotchExperiences=true (L1384); enableExtensionNotchTabs=true (L1385); enableExtensionNotchMinimalisticOverrides=true (L1386); enableExtensionNotchInteractiveWebViews=true (L1387); extensionDiagnosticsLoggingEnabled=true (L1390); extensionAuthorizationEntries=[] (L1388); extensionRateLimitRecords=[] (L1389); extensionLiveActivityCapacity=4, extensionLockScreenWidgetCapacity=4, extensionNotchExperienceCapacity=2 (L1391-1393, no UI); enableExtensionFileSharing=true (L1394). ABOUT: releaseName="Kaafu" (L991); updateChannel=.stable (L986; stable/beta/alpha/nightly selectable, dev excluded); Sparkle automaticallyChecksForUpdates/automaticallyDownloadsUpdates (Sparkle-owned keys). Other no-UI keys: enableFullscreenMediaDetection=true (L1068), alwaysHideInFullscreen=false (L1235), enableWobbleAnimation=false (L1240), tileShowLabels=false (L1035), showEmojis=false (L1020), enableGradient=false legacy (L1209), didMigrate* flags (L1083,1085,1446,1495,1496), didClearLegacyURLCacheV1 (L1500), spotify token legacy keys (L1245-1268).

### Dependencies

Defaults, Sparkle, KeyboardShortcuts.

### Implementation notes

Port only the subsets NotchIsland supports; keep key names.

### Key files

- `components/Settings/SettingsView.swift`
- `components/Settings/ExtensionsSettings.swift`
- `components/Settings/SoftwareUpdater.swift`
- `models/Constants.swift`
- `models/UpdateChannel.swift`
- `enums/TimerDisplayMode.swift`

## Onboarding flow (OnboardingView and steps)

### Behaviour

On first launch a 400x600 borderless-looking window ('Onboarding', transparent title bar) walks through: Welcome (logo, 'Atoll', 'Welcome', sparkle particle backdrop, 'Get started', Privacy Policy link) → Enable Camera Access (Allow/Not Now) → Enable Calendar Access → Choose a Music Source (radio list of media controllers) → Choose Your Profile (2x2 grid: Developer, Designer, Light Use, Student; multi-select; Continue) → You're All Set! (Customize in Settings / Finish / Privacy Policy). On appearance a confirmation dialog 'Focus detection mode' offers Use DevTools / Use without DevTools / Later. Finishing hides the window and returns the app to accessory mode; 'Customize in Settings' opens Settings.

### Layout

Window: NSWindow 400x600, styleMask [.titled, .fullSizeContentView], centered, title 'Onboarding', titlebarAppearsTransparent, titleVisibility .hidden, isRestorable false, identifier 'OnboardingWindow', screen-capture scope .panelsOnly (DynamicIslandApp.swift:1663-1699). OnboardingView ZStack of steps .frame(400x600) (components/Onboarding/OnboardingView.swift:45-125). WelcomeView (WelcomeView.swift:26-108): Image 'spotlight' blurred 3 offset y −5 over SparkleView (CAEmitterLayer: birthRate 20 effective, lifetime 5, velocity 10±5, emission 2π, scale 0.2±0.1, alphaSpeed −0.5, yAcceleration 10; SparkleView.swift:39-77) opacity 0.6; VStack(spacing 8): logo2 100x100, 'Atoll' largeTitle semibold, 'Welcome' title secondary (bottom pad 30), 'Get started' borderedProminent (padding h20 v6), 'Privacy Policy' caption link to https://ebullioscopic.github.io/DynamicIsland/privacy-policy; 'ebullioscopic' wordmark 22pt tall at bottom (overlay blend); background VisualEffectView(.hudWindow, .behindWindow). PermissionRequestView (PermissionsRequestView.swift:25-76): VStack(spacing 28): icon 70x56 accent (top pad 32), title .title semibold, description centered, HStack lock.shield + privacy note subheadline secondary, buttons 'Not Now' (.bordered) / 'Allow Access' (.borderedProminent); background .underWindowBackground. MusicControllerSelectionView (MusicControllerSelectionView.swift:27-132): title 'Choose a Music Source' (.title bold, top 24), subtitle, ScrollView of ControllerOptionView rows (checkmark.circle.fill/circle .title2; name headline; description subheadline; RoundedRectangle 12 fill accent 0.15 when selected; stroke accent / secondary 0.3 1.5pt), 'Continue' .large; excludes Now Playing when MusicManager.isNowPlayingDeprecated. ProfileSelectionView (ProfileSelectionView.swift:30-199): person.3.fill 50pt blue→purple gradient, 'Choose Your Profile' largeTitle bold, LazyVGrid 2 columns spacing 16, ProfileCard 160 tall padding 16 radius 16 (icon 28pt gradient, checkmark 22pt, name headline, description caption 3 lines; selected fill gradient 0.15 + 2pt gradient border + shadow gradient[0] 0.3 r8 y4; hover scale 1.02), 'Continue' full width padding v12 disabled until a selection. OnboardingFinishView (OnboardingFinishView.swift:25-84): sparkles 60pt accent, 'You're All Set!' largeTitle bold, body copy, buttons 'Customize in Settings' (Label gear, .large) and 'Finish' (.borderedProminent, .large, default action), Privacy Policy link; padding 24.

### Animations

Step transitions withAnimation(.easeInOut(duration: 0.6)) + .transition(.opacity) (OnboardingView.swift:50-119); profile toggle .spring(response: 0.3, dampingFraction: 0.7) (ProfileSelectionView.swift:125); card hover .easeInOut(0.2); music radio .spring(0.3, 0.6).

### State and timing

Shown via DispatchQueue.main.async after launch when coordinator.firstLaunch && !isUITesting (DynamicIslandApp.swift:1094-1099); NSApp.setActivationPolicy(.regular) + activate; onFinish → orderOut, .accessory, close, deactivate.

### Data sources and APIs

AVCaptureDevice.requestAccess(for: .video) (OnboardingView.swift:153); CalendarService().requestAccess() (EventKit); NSWorkspace.open for links; coordinator.firstLaunch AppStorage. applyProfileSettings (ProfileSelectionView.swift:203-287) writes Defaults: always enableClipboardManager=true; developer → colorPicker/stats/terminal/timer/screenAssistant on, mirror off, minimalistic off; designer → colorPicker on, mirror on, lightingEffect on, inlineHUD on, stats/timer/screenAssistant off; lightuse → minimalistic on, colorPicker/mirror/stats/screenAssistant/lyrics off, timer on, inlineHUD on; student → timer on, showCalendar on, colorPicker/mirror/stats/screenAssistant off; if lightuse not chosen → minimalistic off; common: menubarIcon=true, enableHaptics=true, enableLyrics=false, lockScreenWeatherWidgetStyle=.inline; externalDisplayStyle = .notch if main screen has a notch else .dynamicIsland; on macOS 26: lockScreenGlassStyle=.liquid, customizationMode=.customLiquid, musicLiquidGlassVariant=.v11. Also a ProOnboard view (ProOnboarding.swift, 350x500, 'Buy us a coffee') exists but is unreferenced.

### Settings

firstLaunch (@AppStorage "firstLaunch" = true, DynamicIslandViewCoordinator.swift:126); focusMonitoringMode set by the dialog (Constants.swift:1477); mediaController set by the music step (Notification .mediaControllerChanged posted, MusicControllerSelectionView.swift:73-78).

### Dependencies

SwiftUIIntrospect (ProOnboard only).

### Implementation notes

Straight SwiftUI port; replace the CAEmitterLayer sparkle with a simple Canvas or omit. Steps map to NotchIsland permissions (camera optional). ~500 lines.

### Key files

- `components/Onboarding/OnboardingView.swift`
- `components/Onboarding/WelcomeView.swift`
- `components/Onboarding/PermissionsRequestView.swift`
- `components/Onboarding/MusicControllerSelectionView.swift`
- `components/Onboarding/ProfileSelectionView.swift`
- `components/Onboarding/OnboardingFinishView.swift`
- `components/Onboarding/SparkleView.swift`
- `components/Onboarding/ProOnboarding.swift`
- `DynamicIslandApp.swift`

## Software updates (Sparkle 2.7.0: channels, AtollUpdaterDelegate, AtollUserDriver custom UI, UpdaterSettingsView)

### Behaviour

'Check for Updates…' in the menu bar and About tab; About lets you pick Stable/Beta/Alpha/Nightly feeds and shows the build's own channel badge; Sparkle's automatic check/download toggles. A custom 460x380 floating 'Atoll Update' window (SwiftUI) presents checking, update found (icon, version, release notes), download/extraction progress (120pt ring, 28pt bold rounded percentage, 6pt bar), ready to install, up to date, and error states.

### Layout

Update window: NSWindow(contentViewController:), title 'Atoll Update', styleMask [.titled, .fullSizeContentView], transparent titlebar, hidden title, contentSize 460x380, centered, level .floating (AtollUserDriver.swift:147-156); all views .frame(460x380). UpdateFoundView: app icon 100 / 72 radius 16, release notes monospaced caption inside RoundedRectangle 8; UpdateProgressView: ring 120x120, percent 28pt bold rounded, bar height 6 radius 4. UpdatePhase enum idle/checking/updateFound/downloading/extracting/readyToInstall/installing/installed/upToDate/error with localized titles (L203-226). About: Update channel picker over UpdateChannel.availableChannels with badge colors stable .systemGreen checkmark.seal.fill, beta .systemBlue testtube.2, alpha .systemOrange flask.fill, nightly .systemPurple moon.stars.fill, dev .systemYellow hammer.fill (models/UpdateChannel.swift:63-83); 'Current build: <buildChannel>' (DEBUG→dev, NIGHTLY/ALPHA/BETA flags, else stable; L88-100).

### Animations

Not inspected in detail (SwiftUI default).

### State and timing

Updater starts at app init (unless UI testing); Sparkle manages scheduling.

### Data sources and APIs

SPUStandardUpdaterController(startingUpdater: !isUITesting, updaterDelegate: AtollUpdaterDelegate, userDriverDelegate: nil) (DynamicIslandApp.swift:42-44; note the custom AtollUserDriver exists but the standard controller is what is instantiated — whether the custom driver is wired in elsewhere is unknown). AtollUpdaterDelegate.feedURLString returns Defaults.updateChannel.feedURL (services/AtollUpdaterDelegate.swift:24-28). Feeds: https://raw.githubusercontent.com/Ebullioscopic/Atoll/main/Updates/appcast.xml (stable), appcast-beta.xml, appcast-alpha.xml, appcast-nightly.xml (nightly and dev) (UpdateChannel.swift:52-61; all four URLs confirmed in binary). Info.plist: SUFeedURL = stable appcast, SUPublicEDKey q2YQaJ1umGkaIJWMGN9Isj5fx/YlUtxnzHEBqFtfZcg=, SUEnableDownloaderService true, SUEnableInstallerLauncherService true. REA: Sparkle.framework bundled with Updater.app, Downloader.xpc, Installer.xpc; _OBJC_CLASS_$_SPUStandardUpdaterController imported; dispatch.json shows AtollUserDriver and AtollUpdaterDelegate classes.

### Settings

updateChannel=.stable (Constants.swift:986); Sparkle's SUEnableAutomaticChecks/SUAutomaticallyUpdate (managed by Sparkle, exposed as toggles in About).

### Dependencies

Sparkle 2.7.0 (MIT).

### Implementation notes

NotchIsland has no dependencies; either add Sparkle later or skip. If added, copy the channel enum + delegate pattern (public Sparkle API). ~150 lines without the custom driver.

### Key files

- `components/Settings/SoftwareUpdater.swift`
- `services/AtollUpdaterDelegate.swift`
- `components/Settings/CustomUpdaterViews/AtollUserDriver.swift`
- `components/Settings/CustomUpdaterViews/UpdateFoundView.swift`
- `components/Settings/CustomUpdaterViews/UpdateProgressView.swift`
- `components/Settings/CustomUpdaterViews/UpdateErrorView.swift`
- `components/Settings/CustomUpdaterViews/UpdateNotFoundView.swift`
- `models/UpdateChannel.swift`

## Launch at login

### Behaviour

'Launch at login' toggle in Settings ▸ General ▸ System features.

### Layout

LaunchAtLogin.Toggle { Text("Launch at login") } (SettingsView.swift:1197-1199).

### Animations

n/a

### State and timing

n/a

### Data sources and APIs

LaunchAtLogin-Modern (sindresorhus) → SMAppService.mainApp (REA confirms _OBJC_CLASS_$_SMAppService import and ServiceManagement framework dependency). Public, macOS 13+.

### Settings

No app-side key; state lives in SMAppService.

### Dependencies

LaunchAtLogin-Modern (MIT).

### Implementation notes

Use SMAppService.mainApp.register()/unregister() and .status directly; a 20-line wrapper.

### Key files

- `components/Settings/SettingsView.swift`

## Third-party extensions host (AtollExtensionKit): XPC service, JSON-RPC WebSocket, authorization/rate limits/capacities, lock-screen widget presentation

### Behaviour

Other apps built with AtollExtensionKit can ask Atoll (once authorized by the user in Settings ▸ Extensions) to show live activities in the notch, lock-screen widgets (up to 4, max 480x280 each, up to 12 content elements) and notch experiences (up to 2, duration hint ≤ 6 h), and can read/share Shelf files. Requests are refused when the feature or scope is off, the app is not authorized, or capacity is reached. Lock-screen widgets are drawn as independent delegated windows positioned by alignment/offset with clamp regions.

### Layout

Extension lock-screen widget window (ExtensionLockScreenWidgetPresentationController.swift:161-209, 263-301): hosting view = descriptor.size, layer cornerRadius = descriptor.cornerRadius; frame x by alignment leading/center/trailing + horizontalOffset, y = screen.midY − h/2 + verticalOffset, clamped by safeInsets: safeRegion (top 140, left 48, bottom 100, right 48), relaxed (96, 24, 72, 24), unconstrained (16, 0, 32, 0). ExtensionLockScreenWidgetView (components/Extensions/ExtensionLockScreenWidgetView.swift:25-229): RoundedRectangle(descriptor.cornerRadius, continuous); inline/card/custom = VStack(alignment .leading, spacing 8) of elements; circular = ZStack centered; content insets custom or (12,16,12,16) / circular (10,10,10,10); materials frosted .ultraThinMaterial / liquid LiquidGlassBackground(variant) over black 0.08 / solid tint 0.95 / semiTransparent tint 0.35 / clear; optional glass highlight (macOS 26 glassEffect(.clear.interactive()) else .regularMaterial); tint overlay tintColor.opacity(tintOpacity) except solid/semiTransparent; border custom or white 0.04 1pt; shadow from descriptor. Element views: text, marquee, icon, progress (bar height 8), webView (WKWebView, navigation allow-listed, interaction disabled on lock screen), animation (Lottie), icon 54x54 (ExtensionWidgetElementView L236-470).

### Animations

Reposition on screen change unanimated; animated variant 0.22 s easeInEaseOut (L246-261). Live activity sneak peek default duration 2.5 s (ExtensionLiveActivityManager.swift:191).

### State and timing

XPC host and RPC server start in applicationDidFinishLaunching and stop in applicationWillTerminate; XPC listener is skipped under --uitesting (entitlement may be stripped). Lock-screen widget presentation refreshes on LockScreenManager.$isLocked, manager.$activeWidgets and the enableExtensionLockScreenWidgets key; windows hidden when unlocked, feature off or no payloads (PresentationController L83-96).

### Data sources and APIs

NSXPCListener(machServiceName: "com.ebullioscopic.Atoll.xpc") with exported AtollXPCServiceProtocol and remote AtollXPCClientProtocol; peer bundle id resolved from connection.processIdentifier via NSRunningApplication (ExtensionXPCServiceHost.swift:24-135; entitlement com.apple.security.mach-services confirmed; NSXPCListener/NSXPCConnection imports confirmed). ExtensionXPCService methods: requestAuthorization, checkAuthorization, present/update/dismissLiveActivity, present/update/dismissLockScreenWidget, present/update/dismissNotchExperience, getVersion (ExtensionXPCService.swift:45-185). ExtensionRPCServer (ExtensionRPCServer.swift): Network.framework NWListener bound to 127.0.0.1 and ::1 on port 9020 (rpcPort L90), JSON-RPC 2.0 over WebSocket, loopback peer re-checked per connection, restart coalesced 3 s; methods (ExtensionRPCService.swift:63-115): atoll.getVersion, atoll.requestAuthorization, atoll.checkAuthorization, atoll.presentLiveActivity/updateLiveActivity/dismissLiveActivity, atoll.presentLockScreenWidget/updateLockScreenWidget/dismissLockScreenWidget, atoll.presentNotchExperience/updateNotchExperience/dismissNotchExperience, atoll.getShelfItems, atoll.getShelfItemData, atoll.showFilePicker, atoll.shareShelfItems, atoll.addFilesToShelf, atoll.subscribeShelfEvents; error codes −32700/−32600/−32601/−32602/−32603 standard plus unauthorized −32001, featureDisabled −32002, capacityExceeded −32003, descriptorInvalid −32004, unsupported −32005 (ExtensionRPCMessages.swift:85-96). Authorization (ExtensionAuthorizationManager.swift): entries {bundleIdentifier, appName, status pending/authorized/denied/revoked, allowedScopes liveActivities/lockScreenWidgets/notchExperiences/fileSharing, requestedAt, grantedAt, lastActivityAt, lastDeniedReason} persisted in Defaults; rate-limit timestamps kept for a 5-minute window (L207-210). Validation (ExtensionDescriptorValidator.swift): live activity metadata ≤ 32 keys; widget content ≤ 12 elements, size ≤ 480x280; notch experience durationHint 0 < d ≤ 21 600 s. Capacities from Defaults (4/4/2). Snapshots are broadcast across Atoll processes via DistributedNotificationCenter names com.ebullioscopic.Atoll.extensions.liveActivitySnapshot / lockScreenWidgetSnapshot / notchExperienceSnapshot and persisted under ~/Library/Application Support/AtollExtensions/{live_activities,lock_screen_widgets,notch_experiences}.json (ExtensionEventBridge.swift:116-164). Window delegation PRIVATE SkyLight. Descriptor model lives in the remote package github.com/Ebullioscopic/AtollExtensionKit (Sources/AtollExtensionKit/Models/AtollLockScreenWidgetDescriptor.swift etc.; not read).

### Settings

See Settings catalogue B ▸ EXTENSIONS (all under Constants.swift:1380-1394).

### Dependencies

AtollExtensionKit (branch main), Network.framework, WebKit, Lottie.

### Implementation notes

Out of scope for a first NotchIsland release; if desired, the RPC surface (JSON-RPC over loopback WebSocket, NWListener) is fully public and the method list above is the contract. ~2 500 lines in Atoll.

### Key files

- `services/Extensions/ExtensionXPCServiceHost.swift`
- `services/Extensions/ExtensionXPCService.swift`
- `services/Extensions/ExtensionRPCServer.swift`
- `services/Extensions/ExtensionRPCService.swift`
- `services/Extensions/ExtensionRPCMessages.swift`
- `services/Extensions/AtollDistributedNotifications.swift`
- `managers/Extensions/ExtensionAuthorizationManager.swift`
- `managers/Extensions/ExtensionDescriptorValidator.swift`
- `managers/Extensions/ExtensionEventBridge.swift`
- `managers/Extensions/ExtensionLockScreenWidgetManager.swift`
- `managers/Extensions/ExtensionLockScreenWidgetPresentationController.swift`
- `managers/Extensions/ExtensionLiveActivityManager.swift`
- `managers/Extensions/ExtensionNotchExperienceManager.swift`
- `components/Extensions/ExtensionLockScreenWidgetView.swift`
- `components/Extensions/ExtensionLiveActivityViews.swift`
- `components/Extensions/ExtensionRenderingHelpers.swift`
- `components/Settings/ExtensionsSettings.swift`

## Permission stores and screen-capture visibility (Accessibility, Full Disk Access, Shelf folders, ScreenCaptureVisibilityManager)

### Behaviour

Settings callouts and menu items let the user request Accessibility, Full Disk Access (alert 'Full Disk Access Required' with Continue/Cancel, then opens System Settings and reveals the app in Finder) and Documents/Downloads folder access; status badges update by polling after a request. 'Hide Dynamic Island during screenshots & recordings' excludes every Atoll window from screen capture.

### Layout

n/a

### Animations

Polling cadence: Accessibility 30 x 0.5 s (AccessibilityPermissionStore.swift:62-77); Full Disk / Shelf folders 40 x 0.5 s (FullDiskAccessPermissionStore.swift:153-171, 226-246).

### State and timing

Stores are @MainActor ObservableObjects with isAuthorized published; polling stops early on success.

### Data sources and APIs

AXIsProcessTrusted / AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true]) (both imports confirmed); Full Disk Access probe = try FileHandle(forReadingFrom:) on ~/Library/Application Support/com.apple.TCC/TCC.db or ~/Library/DoNotDisturb/DB/ModeConfigurations.json (L24-53; both path strings confirmed in binary); folder access probe = contentsOfDirectory on Documents/Downloads (L56-100); NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]); deep links Privacy_Accessibility / Privacy_AllFiles / Privacy_FilesAndFolders. ScreenCaptureVisibilityManager (helpers/ScreenCaptureVisibilityManager.swift:28-69): NSMapTable weak-keyed window registry; window.sharingType = hideDynamicIslandFromScreenCapture ? .none : .readOnly on register and on key change (scope enum panelsOnly/entireInterface is stored but currently unused in the decision). All public.

### Settings

hideDynamicIslandFromScreenCapture=false (Constants.swift:992).

### Dependencies

Defaults.

### Implementation notes

Port as-is (~250 lines); NotchIsland can reuse for its own permission UI.

### Key files

- `helpers/AccessibilityPermissionStore.swift`
- `helpers/FullDiskAccessPermissionStore.swift`
- `helpers/ScreenCaptureVisibilityManager.swift`

## Fullscreen media detection (FullscreenMediaDetector, MacroVisionKit + Accessibility)

### Behaviour

When the setting 'Hide DynamicIsland Options' is 'Always hide in fullscreen' or 'Hide only when NowPlaying app is in fullscreen' (default), the notch hides on a screen where a genuinely fullscreen app (or the playing media app) is in native fullscreen; 'Never hide' keeps it. Status is re-evaluated 0.5 s after a Space change or screen-parameter change.

### Layout

n/a

### Animations

500 ms debounce after notifications (observers/FullscreenMediaDetection.swift:68-71).

### State and timing

Singleton initialised eagerly; status recomputed on notifications only (no polling).

### Data sources and APIs

MacroVisionKit.shared.detectFullscreenApps(debug:false) with configuration.includeSystemApps = true (L36-37, 83) yields FullscreenWindowInfo {screen, bundleIdentifier, processId}; Finder excluded (L91); genuine-fullscreen check via Accessibility: AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute / kAXWindowsAttribute, attribute "AXFullScreen" (undocumented attribute, public API; imports confirmed) — falls back to the frame-based result when !AXIsProcessTrusted() (L122-152). Publishes fullscreenStatus: [screenName: Bool]. NSWorkspace.activeSpaceDidChangeNotification and NSApplication.didChangeScreenParametersNotification via AsyncSequence (L42-66). Public APIs only (MacroVisionKit itself uses CGWindowListCopyWindowInfo).

### Settings

enableFullscreenMediaDetection=true (Constants.swift:1068); hideNotchOption=.nowPlayingOnly (L1237); alwaysHideInFullscreen=false (L1235, legacy).

### Dependencies

MacroVisionKit 0.1.0 (TheBoredTeam).

### Implementation notes

NotchIsland already has Services/FullscreenDetector.swift; align semantics: hideNotchOption tri-state, per-screen dictionary, AXFullScreen confirmation when trusted, 0.5 s debounce. Replace MacroVisionKit with CGWindowListCopyWindowInfo(.optionOnScreenOnly) windows whose bounds equal a screen frame. ~150 lines.

### Key files

- `observers/FullscreenMediaDetection.swift`

## Unknowns

- SkyLightWindow package license and the exact repo revision contents beyond SkyLightOperator.swift (github.com was unreachable; only the raw operator file was summarised) — verify before any reuse decision.
- AtollExtensionKit descriptor types (AtollLockScreenWidgetDescriptor fields: layoutStyle inline/card/circular/custom, material frosted/liquid/solid/semiTransparent/clear, position alignment/offsets/clampMode, appearance tintColor/tintOpacity/border/shadow/contentInsets/liquidGlassVariant/enableGlassHighlight, content element enum text/marquee/icon/progress/webView/animation) were inferred from usage only; the package source (github.com/Ebullioscopic/AtollExtensionKit/Sources/AtollExtensionKit/Models/*.swift) was not read.
- Whether the custom Sparkle AtollUserDriver is actually wired in: DynamicNotchApp constructs SPUStandardUpdaterController(userDriverDelegate: nil) (DynamicIslandApp.swift:42-44) and no other instantiation of AtollUserDriver was found in this pass; the class does ship (dispatch.json). Likely dead or wired elsewhere.
- LockScreenMusicPanel internals beyond the panel shell: progress bar (MusicSliderView), VolumeCapsuleSlider, AirPlayVolumeSlider, SkipTrackGlyph press animations, lyrics TimelineView fonts, MusicTitleMarqueeView, visualizer bar widths — these belong to the media subsystem and were only outlined (LockScreenMusicPanel.swift:560-1500).
- FullScreenArtworkWindowManager (lock-screen fullscreen artwork / Spotify canvas fallback, spotifyCanvasFallbackArtworkSideLength/InterItemSpacing) not read; only its effect on panel placement (48/56/84/20 pt margins) is captured.
- DoNotDisturbManager (Focus detection via ~/Library/DoNotDisturb/DB/ModeConfigurations.json and distributed notifications; FocusModeType.resolvedActiveIcon(usePrivateSymbol:) private SF symbol names) and CalendarManager.lockScreenEvents/updateLockScreenEvents were not read — they feed the lock-screen capsule.
- SiriVisibilityMonitor exact polling intervals per SiriResponsivenessMode and power source (calculateIntervals) not read; only the CGWindowList owner=="Siri" && height>400 heuristic and 0.25 s fade are captured.
- LockScreenPositioningControls musicWidthRange/timerWidthRange exact bounds (SettingsView.swift:6600-6680 not fully read); footer says media panel may exceed its default and timer stops at its default (420).
- Timer 'Default Custom Timer' storage key and custom timer sound key (TimerSettings.swift:7560-7707) live in TimerManager, not Constants.swift — not read.
- Settings tabs whose detailed row layout was only sampled via grep: HUDSelectionCard previews/HUDPreviewViewModel (SettingsView.swift:1847-2720), About tab donate/GitHub URLs, SettingsPermissionCallout, SettingsSegmentedPicker visual spec (L5530-5637).
- MediaControlsStateCoordinator restore semantics when both showStandardMediaControls and enableMinimalisticUI are false were captured, but the user-facing wording in Settings for this interplay was not verified.
- REA dispatch.json does not list Swift struct names LockScreenMusicPanel/OnboardingView/ProfileSelectionView/MusicControllerSelectionView/SiriVisibilityMonitor (they have no ObjC/vtable footprint); binary strings do confirm 'OnboardingView', 'OnboardingWindow', 'Lock Screen Preview'. All manager classes in this subsystem are confirmed present.
- decreaseBacklight (⌘F1) / increaseBacklight (⌘F2) KeyboardShortcuts names are declared but no handler/recorder was found in AppDelegate or SettingsView; possibly consumed by SystemHUDManager/KeyboardBrightnessSensor (not read).
- Lock.json Lottie and LockIconLottieView appear unused by the shipped lock views (the SF symbol path is used); Dog waiting/Moody Dog/Orange Cat Peeping/Reindeer Lottie files belong to idle animations (other subsystem).
- Default-value discrepancy to decide on: Defaults.lockScreenTimerWidgetWidth = 350 (Constants.swift:1117) while LockScreenTimerWidget.defaultWidth / reset = 420; and Defaults.lockScreenWeatherRefreshInterval (30 min) and lockScreenWeatherWidgetRowOrder have no Settings UI.

## Critic pass

Missing from the spec:

- SPEC TRUNCATION: the spec text handed to me ends mid-sentence inside the 'Lock-screen reminder chip' layout (after '.shadow(appearance.contentShadow radius 8 y 3).'). Everything after that point (reminder panel geometry, extension widgets, settings catalogue, onboarding, shortcuts tab, extensions tab, about/updater, FullscreenMediaDetection, permission stores) could not be evaluated. All items below marked [T] must be present in the full spec; if they are, treat them as verified-correct cross-checks rather than gaps.
- LockScreenWidgetPreviewManager (managers/LockScreenWidgetPreviewManager.swift, 578 lines, class confirmed in REA dispatch.json, 'Lock Screen Preview' string in binary) is never mentioned. It opens a titled/closable/miniaturizable/resizable NSWindow sized to screen.frame, title 'Lock Screen Preview', backgroundColor .clear, centred (L199-215); content = LockScreenPreviewScene which scales a full-screen layout by min(w/screenW, h/screenH) (L381-430) over WallpaperView (bundled desktop.jpeg -> asset 'desktop' -> NSWorkspace.desktopImageURL, L540-578). Mock data: 21 C / 72 F with min -5/max +6, 'Partly Cloudy', cloud.sun.fill, 'Cupertino', charging 42 min 78 %, AirPods Pro 74 % 'airpodspro', battery 63 %, AQI 42 (US) / 28 (EAQI), sunrise +2 h / sunset +9 h (L116-190); starts a 1783 s demo timer when the timer widget is enabled and forceStopTimer()s it on hide (L82-95); forces DoNotDisturbManager to 'Do Not Disturb'/com.apple.donotdisturb and injects two preview calendar events ('Pay rent' reminder +12..+42 min, systemBlue, high priority; 'Design Review' at 'Studio' +60..+90 min, systemOrange) via CalendarManager.setLockScreenPreviewEvents (L270-355); re-renders on 17 Defaults keys (L97-116). Toggled from Settings > Lock Screen > Widgets > 'Preview lock screen widgets' / 'Hide lock screen preview' (SettingsView.swift:5912-5918). NOTE its media-panel math uses defaultLowering -28 (L491) while the real LockScreenPanelManager uses -68 (LockScreenPanelManager.swift:~408) - an Atoll inconsistency NotchIsland should not copy.
- [T] Settings > Lock Screen tab structure (SettingsView.swift:5638-6470, struct LockScreenSettings): a SettingsSegmentedControl switching LockScreenSettingsSection .general / .widgets (L208-220, titles 'General'/'Widgets'). General: Enable lock screen live activity (5785), Lock/Fingerprint LockScreenIconStyleCard pair (5795-5824, card view at 6471), Lock sounds (5828), 'Siri detection speed' Picker with displayName+description rows, header 'Siri Detection' (5839-5853), 'Lock Screen Glass' Material picker (disabled below macOS 26, 5856-5870) + customization mode + LockScreenGlassVariantPreviewCell grid (6525), Diagnostics section with 'Copy Latest Crash Report' button (5901-5909). Widgets: Preview button (5912-5918, footer 'Opens a transparent preview window with mock data...'), 'Widget appearance' Dark/Light and 'Widget layout' Inline/Circular segmented pickers with circular caveat text (5926-5945), weather provider/unit/AQI/location/sunrise/gauge-tint controls, calendar row controls using CalendarLookaheadOption 15m/30m/1h/3h/6h/12h/rest_of_day/all_time with titles '15 mins'...'All time' (5700-5720), focus widget toggle, Reminder Widget section: 'Chip color', 'Alignment' Left/Center/Right (ReminderAlignmentOption leading/center/trailing, 5722-5736), 'Vertical offset' Slider -160...160 step 2 with 'N px' label, all disabled unless enableLockScreenReminderWidget && enableReminderLiveActivity (6180-6210), battery section gated by BatteryActivityManager.hasBattery() (6215), media-panel toggles (5955-6015), 'Timer glass material' picker (6052-6061), LockScreenPositioningControls (6575-6720): offset sliders +-160 for weather/music/timer, 'Media Panel Width' 320...460 with 'Reset Media Width', 'Timer Widget Width' 320...420 (LockScreenTimerWidget.defaultWidth) with 'Reset Timer Width', header 'Lock Screen Positioning', and an interactive LockScreenPositioningPreview (6840-6900) where the three widgets are dragged inside a mock screen (padding 26, radius 28, windowBackgroundColor 0.55, stroke white 0.12, shadow black 0.22 r20 y18; weather at 28 %, timer 50 %, music 78 % of height; sizes 0.42x0.22 / 0.5x0.2 scaled by timerWidth/420 / 0.56x0.34 scaled by musicWidth/390).
- [T] The lock-screen settings are DUPLICATED in other tabs and the spec must say which tab owns each key: Media tab (struct Media, SettingsView.swift:3313-3330, 3542-3610) repeats 'Lock Screen Media': album-art parallax, Always show volume control (disabled unless showMediaOutputControl), show app icon, merged AirPlay output, panel border, enhanced liquid border (liquid) / blur (frosted), fullscreen artwork, artwork layout over canvas, keep album art; Appearance tab (struct Appearance, 4877-5637) repeats lock-screen glass style, timer glass style, timer surface and a 'Reset Width' button (5486) and runs enforceLockScreenGlassConsistency (5513-5517: frosted forces customizationMode .standard; customLiquid forces style .liquid; same rule again at 6420-6427); Timer tab (struct TimerSettings, 7393-7520) repeats 'Timer glass material' and timer surface.
- [T] Settings window + shell: SettingsWindowController.swift:31-80 - NSWindow 700x600, styleMask [.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView], title 'Atoll Settings', titlebarAppearsTransparent false, toolbarStyle .unified, isMovableByWindowBackground, level .normal, collectionBehavior [.managed,.participatesInCycle], isRestorable true, identifier 'DynamicIslandSettingsWindow', ScreenCaptureVisibilityManager scope .panelsOnly; showWindow() orders front, centers, NSApp.activate(ignoringOtherApps:) and re-makes key on next tick (L84-110); close/windowWillClose -> orderOut + NSApp.setActivationPolicy(.accessory); windowDidBecomeKey -> .regular (L114-150). SettingsView.swift:621-666: NavigationSplitView, sidebar .frame(minWidth: 200), .navigationSplitViewColumnWidth(min 200, ideal 210, max 240), .toolbar(removing: .sidebarToggle) on both columns, whole view .frame(width: 700); sidebar icon 26x26 tinted per tab (tint table L135-160, e.g. lockScreen .orange, extensions rgb(0.557,0.353,0.957), battery rgb(0.202,0.783,0.348)); group headers 'Media & Display','System','Productivity','Utilities','Developer','Integrations' (core/info have none, L33-45). Search index: 221 SettingsSearchEntry rows keyed by tab + highlightID '<tab>-<title>' (L171-223).
- [T] Tab -> group -> icon table (SettingsView.swift:48-133): general(gear), appearance(paintpalette) -> core; media(play.laptopcomputer), liveActivities(waveform.path.ecg), lockScreen(lock.laptopcomputer), devices(headphones) -> Media & Display; hudAndOSD titled 'Controls'(dial.medium.fill), battery(battery.100.bolt) -> System; timer(timer), calendar(calendar), notes(note.text) -> Productivity; clipboard(clipboard), screenAssistant(brain.head.profile), colorPicker(eyedropper), shelf(books.vertical), downloads(square.and.arrow.down), shortcuts(keyboard) -> Utilities; stats(chart.xyaxis.line), terminal(apple.terminal) -> Developer; extensions(puzzlepiece.extension) -> Integrations; about(info.circle) -> info.
- [T] Onboarding details (components/Onboarding/*): OnboardingView.swift:28-35 enum OnboardingStep welcome/cameraPermission/calendarPermission/musicPermission/profileSelection/finished; every step change is withAnimation(.easeInOut(duration: 0.6)) with .transition(.opacity) (L50-120); a 'Focus detection mode' confirmationDialog (Use DevTools / Use without DevTools / Later) is shown once on first appear and writes Defaults[.focusMonitoringMode] (L128-147); camera via AVCaptureDevice.requestAccess(.video), calendar via CalendarService.requestAccess (L152-158). WelcomeView.swift:27-110: 'spotlight' image blur 3 offset y -5 over SparkleView opacity 0.6, 'logo2' 100x100, 'Atoll' largeTitle semibold, 'Welcome' title secondary, 'Get started' borderedProminent, 'Privacy Policy' caption link to https://ebullioscopic.github.io/DynamicIsland/privacy-policy, 'ebullioscopic' footer image h22 blend .overlay, background VisualEffectView(.hudWindow,.behindWindow). SparkleView.swift: CAEmitterLayer rectangle/surface/oldestFirst, cell 'sparkle' image, birthRate 20 (base 50 overridden), lifetime 5, velocity 10 +-5, emissionRange 2pi, scale 0.2 +-0.1, alphaSpeed -0.5, yAcceleration 10. PermissionRequestView.swift: VStack spacing 28, icon 70x56 accent, top padding 32, title .title semibold, privacy note with lock.shield, buttons 'Not Now' (.bordered) / 'Allow Access' (.borderedProminent), background .underWindowBackground. MusicControllerSelectionView.swift: 'Choose a Music Source', hides .nowPlaying when MusicManager.isNowPlayingDeprecated, option cards radius 12 fill accent 0.15 / stroke accent or secondary 0.3 width 1.5, checkmark spring(0.3,0.6), 7 MediaControllerType descriptions, Continue writes Defaults[.mediaController] and posts .mediaControllerChanged. ProfileSelectionView.swift: 4 profiles developer(terminal.fill, blue->purple), designer(paintbrush.fill, pink->orange), lightuse(sparkles, green->mint), student(book.fill, indigo->cyan); person.3.fill 50pt header; 2-column LazyVGrid spacing 16; cards height 160 radius 16, hover scale 1.02 (.easeInOut 0.2), selected gradient fill 0.15 + 2pt gradient border + shadow gradient[0] 0.3 r8 y4; Continue disabled when none selected; applyProfileSettings (L206-290) writes feature toggles per profile, always enableClipboardManager/menubarIcon/enableHaptics true, enableLyrics false, lockScreenWeatherWidgetStyle .inline, externalDisplayStyle .notch if main screen has notch else .dynamicIsland, and on macOS 26 lockScreenGlassStyle .liquid + customizationMode .customLiquid + variant .v11. OnboardingFinishView.swift: sparkles 60pt, 'You're All Set!' largeTitle bold, 'Customize in Settings' (gear, .large) and 'Finish' (borderedProminent, .defaultAction), privacy link. Window (DynamicIslandApp.swift:1661-1699): 400x600, [.titled,.fullSizeContentView], titlebarAppearsTransparent, titleVisibility .hidden, isRestorable false, identifier 'OnboardingWindow', ScreenCaptureVisibilityManager scope .panelsOnly; onFinish -> orderOut, setActivationPolicy(.accessory), close, NSApp.deactivate; onOpenSettings -> close + SettingsWindowController.showWindow. ProOnboarding.swift (ProOnboard, 350x500, 'TheDynamicIsland', 'Buy us a coffee') is legacy and never instantiated.
- [T] Extension lock-screen widget windows (managers/Extensions/ExtensionLockScreenWidgetPresentationController.swift): one borderless CGShielding-level window per payload, initial 200x80, ignoresMouseEvents true, isMovable false, delegated to SkyLight on creation (L187-204); hosting layer masksToBounds with cornerRadius = descriptor.cornerRadius (L171-176); frame: safe insets by descriptor.position.clampMode - safeRegion (top 140, left 48, bottom 100, right 48), relaxed (96,24,72,24), unconstrained (16,0,32,0) (L292-301); x by alignment leading/center/trailing + horizontalOffset, y = screen.midY - h/2 + verticalOffset, both clamped (L258-290); reposition 0.22 s easeInEaseOut (L239-256); shown only when isLocked && Defaults.enableExtensionLockScreenWidgets && payloads non-empty (L78-91). ExtensionLockScreenWidgetManager.swift: present/update/dismiss/dismissAll, capacity Defaults.extensionLockScreenWidgetCapacity (4), sorted by priority desc then receivedAt asc (L130-137), cross-process snapshot sync via ExtensionEventBridge distributed notifications + persisted snapshot files, diagnostics logging gated by extensionDiagnosticsLoggingEnabled. XPC protocol (ExtensionXPCService.swift:45-185): requestAuthorization, checkAuthorization, present/update/dismiss LiveActivity, present/update/dismiss LockScreenWidget, present/update/dismiss NotchExperience, getVersion; bundle id resolved from connection PID via NSRunningApplication (ExtensionXPCServiceHost.swift:118-128). RPC methods (ExtensionRPCService.swift:63-115): atoll.getVersion, requestAuthorization, checkAuthorization, present/update/dismissLiveActivity, present/update/dismissLockScreenWidget, present/update/dismissNotchExperience, getShelfItems, getShelfItemData, showFilePicker, shareShelfItems, addFilesToShelf, subscribeShelfEvents (file-sharing scope). Sneak peek for extension live activities defaults to 2.5 s (ExtensionLiveActivityManager.swift:191).
- [T] Settings > Extensions tab (components/Settings/ExtensionsSettings.swift): 'Get Extensions' marketplace section linking getatoll.app/marketplace (L70-99); Global Settings toggles: Enable third-party extensions, Allow extension live activities, Allow extension lock screen widgets, Allow extension notch experiences, Show extension tabs, Allow minimalistic overrides, Allow interactive web content, Enable extension diagnostics logging (L105-132); 'App Permissions' list with count, empty state 'No extensions yet', per-app ExtensionEntryRow showing Status, Last Denied Reason, 'Allowed Features' scope toggles (Live Activities / Lock Screen Widgets / Notch Experiences), 'Recent Activity (last 5 minutes)' counters, Reset Rate Limits, Authorize/Deny/Revoke Access/Re-authorize/Remove, Reset Live Activities / Reset Lock Screen Widgets / Reset Notch Experiences (L150-520); removal confirmation dialog (L54-60).
- [T] FullscreenMediaDetection (observers/FullscreenMediaDetection.swift): MacroVisionKit.shared with configuration.includeSystemApps = true (L29-32); listens to NSWorkspace.activeSpaceDidChange and NSApplication.didChangeScreenParameters via AsyncSequence, debounced 500 ms (L36-66); publishes fullscreenStatus [screenName: Bool]; excludes com.apple.finder (L78); hideNotchOption .always -> any native-fullscreen app on that screen, .nowPlayingOnly -> app.bundleIdentifier == MusicManager.shared.bundleIdentifier && native fullscreen, .never -> false (L82-98); native fullscreen confirmed through Accessibility: AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute then kAXWindowsAttribute, reading undocumented 'AXFullScreen' attribute; if !AXIsProcessTrusted() the frame-based result is trusted (L111-141). Gating keys: enableFullscreenMediaDetection=true (Constants.swift:1068), alwaysHideInFullscreen=false (L1235), hideNotchOption=.nowPlayingOnly (L1237).
- [T] Permission stores: AccessibilityPermissionStore.swift:28-97 - isAuthorized from AXIsProcessTrusted() (true under --uitesting), requestAuthorizationPrompt uses AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true]) then polls 30 x 500 ms; openSystemSettings -> x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility. FullDiskAccessPermissionStore.swift:24-160 - FDA detected by opening ~/Library/Application Support/com.apple.TCC/TCC.db or ~/Library/DoNotDisturb/DB/ModeConfigurations.json for reading; requestAccessPrompt shows NSAlert 'Full Disk Access Required' (Continue/Cancel) then opens ?Privacy_AllFiles and reveals the app bundle in Finder; polls 40 x 500 ms. ShelfFolderAccessPermissionStore (same file L63-100, 164-257): Documents/Downloads directory probes, ?Privacy_FilesAndFolders deep link. Settings exposes 'Request Access' / 'Open System Settings' (SettingsView.swift:3738-3746). All four deep-link strings confirmed in the binary.
- ScreenCaptureVisibilityManager (helpers/ScreenCaptureVisibilityManager.swift:22-68): two scopes .panelsOnly (settings + onboarding windows) and .entireInterface (notch window + every lock-screen window) are registered, but applyVisibility ignores the scope parameter - every registered window gets sharingType .none when hideDynamicIslandFromScreenCapture else .readOnly (L65-68); NSMapTable weak keys; re-applied on the Defaults publisher. The spec mentions the key but not the scope enum or that the scope is currently a no-op.
- AppDelegate items absent from the visible spec: application(_:open:) / application(_:openFile:) route file URLs through ShelfDropService.items(from:) into ShelfStateViewModel and switch currentView = .shelf (DynamicIslandApp.swift:170-191) - there is NO custom URL scheme (no CFBundleURLTypes in Info.plist; 'atoll://' absent from binary); AudioTap restart observers watch 12 music bundle IDs (com.apple.Music, com.spotify.client, com.amazon.music, sh.cider.genten.mac, com.apple.Safari, com.tidal.desktop, tv.plex.plexamp, com.roon.Roon, com.audirvana.Audirvana-Studio, com.vox.vox, com.coppertino.Vox) plus .systemAudioRouteDidChange (L204-273); Notification.Name selectedScreenChanged/notchHeightChanged/showOnAllDisplaysChanged/automaticallySwitchDisplayChanged (L1689-1694) and their handlers (L985-1020: showOnAllDisplaysChanged rebuilds windows via cleanupWindows(shouldInvert:true); automaticallySwitchDisplayChanged sets alpha 0/1 by selectedScreen == preferredScreen); adjustWindowPosition hides the window (alpha 0) when the preferred screen is absent and automaticallySwitchDisplay is off (L1612-1616); cleanupWindows calls viewModel.onViewTeardown before close (L355-375); AppRuntimeEnvironment.isUITesting ('--uitesting', DEBUG only) skips Sparkle start, monitors, XPC listener, onboarding, welcome sound and weather (helpers/AppRuntimeEnvironment.swift:24-31); deviceHasNotch() helper (L1549-1558); applySelectedAppIcon() sets NSApp.applicationIconImage from Defaults.customAppIcons/selectedAppIconID (helpers/AppIcons.swift:68-80).
- [T] Reminder chip panel manager geometry (managers/LockScreenReminderWidgetPanelManager.swift:93-170): initial window 220x48; horizontalPadding 24 for 'leading'/'left' and 'trailing'/'right' alignments else centred; lowerBound = max(timerFrame.maxY + 24 if timer visible else musicTop + 16, screen.minY + 80) where musicTop = music.latestFrame.maxY ?? screen.midY - 32; weatherBottom = weather.latestFrame.minY ?? min(screen.maxY - 120, max(screen.midY + 0.14*h, lowerBound + h + 16)); upperBound = weatherBottom - 16 - h; top-aligned when a timer frame exists else centred between bounds; user offset clamped +-160 then clamped to bounds; reposition 0.22 s easeInEaseOut; hide = orderOut + contentView nil. LockScreenReminderWidgetManager.swift observes LockScreenManager.$isLocked, ReminderLiveActivityManager.$lockScreenSnapshot and 4 keys (enableLockScreenReminderWidget=true Constants.swift:1098, lockScreenReminderChipStyle, lockScreenReminderWidgetHorizontalAlignment='center' L1151, lockScreenReminderWidgetVerticalOffset=0 L1152). Snapshot model LockScreenReminderWidgetSnapshot (models/) = title, eventTimeText, relativeDescription?, accent RGBAColor, chipStyle, isCritical, iconName. Chip colour: critical -> red; .eventColor -> accent.ensureMinimumBrightness(0.7) in dark appearance; .monochrome -> primary 0.85; text primary 0.92, secondary 0.78 (critical 1.0), separator 0.65 (LockScreenReminderWidget.swift:91-119).
- [T] SiriVisibilityMonitor polling model (managers/SiriVisibilityMonitor.swift): effective mode for .automatic = powerSaver if Low Power Mode, highPerformance if plugged in (BatteryActivityManager.onPowerSourceChange), else balanced (L86-96); intervals (idle, active): highPerformance (0.2, 0.03), balanced (0.5, 0.06), powerSaver (2.0, 0.25) (L99-108); timer tolerance 10 %; monitoring only while isLocked && display awake (screensDidSleep/Wake) (L120-133); disappearance hysteresis 3 consecutive misses (L40-41, 152-162); Siri window = CGWindowListCopyWindowInfo(.optionOnScreenOnly) entry with owner 'Siri' and bounds Height > 400 (L186-203). The spec only quotes the Settings description strings (30/16/4 Hz).
- LockScreenManager -> native HUD handoff: updateNativeHUDSuppression() calls SystemHUDManager.updateNativeHUDSuppressionForLockState(isLocked:) (managers/SystemHUDManager.swift:342-363) which, when SystemHUDPlacement.yieldsToNativeHUD(isLocked:) is true, re-enables the macOS OSD by killing and launchctl-kickstarting OSDUIHelper, and on unlock disables it again and SIGSTOPs OSDUIHelper immediately (SystemOSDManager.swift:27-181); applicationWillTerminate resumes it synchronously (SIGCONT). This cross-subsystem side effect of locking/unlocking is absent from the spec.
- Lock-screen settings keys/features in this subsystem absent from the visible spec: updateChannel=.stable (Constants.swift:986; models/UpdateChannel.swift: stable/beta/alpha/nightly/dev -> appcast.xml / appcast-beta.xml / appcast-alpha.xml / appcast-nightly.xml (dev shares nightly); dev excluded from picker; badge colours green/blue/orange/purple/yellow and icons checkmark.seal.fill/testtube.2/flask.fill/moon.stars.fill/hammer.fill; buildChannel from DEBUG/NIGHTLY/ALPHA/BETA flags); releaseName='Kaafu' (L991, shown in About); minimumHoverDuration=0.3 (L995), enableHaptics=true (L996), openNotchOnHover=true (L997), extendHoverArea=false (L998); customAppIcons=[] / selectedAppIconID=nil (L1050-1051); enableFullscreenMediaDetection=true (L1068); alwaysHideInFullscreen=false (L1235); the 14 extension keys (L1381-1394: enableThirdPartyExtensions, enableExtensionLiveActivities, enableExtensionLockScreenWidgets, enableExtensionNotchExperiences, enableExtensionNotchTabs, enableExtensionNotchMinimalisticOverrides, enableExtensionNotchInteractiveWebViews all true; extensionAuthorizationEntries/extensionRateLimitRecords []; extensionDiagnosticsLoggingEnabled true; capacities 4/4/2; enableExtensionFileSharing true); didClearLegacyURLCacheV1 (L1500); @AppStorage alwaysShowTabs=true and openLastTabByDefault=false with mutual coupling (DynamicIslandViewCoordinator.swift:134-151), musicLiveActivityEnabled/timerLiveActivityEnabled=true (L128-129), customTimerDuration=600 (NotchTimerView/SettingsView/TimerPopover). Sparkle plist: SUFeedURL https://raw.githubusercontent.com/Ebullioscopic/Atoll/main/Updates/appcast.xml, SUPublicEDKey q2YQaJ1umGkaIJWMGN9Isj5fx/YlUtxnzHEBqFtfZcg=, SUEnableDownloaderService/SUEnableInstallerLauncherService true (Info.plist); UpdaterSettingsView toggles automaticallyChecksForUpdates / automaticallyDownloadsUpdates (SoftwareUpdater.swift:52-82); About tab channel picker (SettingsView.swift:4127-4240).
- Lock-screen timer widget details not in the spec: accentGradient = [accent.opacity(0.35), accent.ensureMinimumBrightness(0.5)] topLeading->bottomTrailing (LockScreenTimerWidget.swift:83-92); CircleButton uses contentTransition(.symbolEffect(.replace)) and .help tooltips 'Pause'/'Resume' and 'Cancel'/'Stop' (L291-322); hosting view layer masksToBounds cornerRadius 26 and autoresizingMask [.width,.height] (Manager L252-261); window isMovable false; stopping from the widget calls TimerManager.stopTimer() only if allowsManualInteraction, otherwise endExternalTimer(triggerSmoothClose: false) (L271-289); manager is warmed at launch with the current lock status (DynamicIslandApp.swift:1113-1116).
- Lock-screen weather panel details not in the spec: initial window 110x40 (LockScreenWeatherPanelManager.swift:88); lastInlineBaselineHeight is a monotonic max of inline fitting heights that persists across snapshots and feeds positionHeight (L46-55, 130); hide() sets alpha 0, orderOut, contentView nil, then alpha back to 1 (L52-61); LockScreenWeatherWidget ticker lives in the WIDGET file (components/LockScreen/LockScreenWeatherWidget.swift:69-205): 15.0 s repeating Timer, tolerance 0, RunLoop.main .common, plus a minute-aligned one-shot that chains into a 60 s repeating timer only while locked and the calendar row is enabled.
- DynamicIslandWindow details omitted (components/Notch/DynamicIslandWindow.swift:44-57): titleVisibility .hidden, titlebarAppearsTransparent true, isReleasedWhenClosed false, and ScreenCaptureVisibilityManager.register(self, scope: .entireInterface) in init; level = .mainMenu + 3 is at L55.
- Legacy/dead code that ships in the binary and should be documented as NOT part of the behaviour: menu/StatusBarMenu.swift (NSStatusItem with 'logo' image and a single localized 'Quit' item; class in dispatch.json; never instantiated), components/Settings/CustomUpdaterViews/* (AtollUserDriver + UpdateFound/Progress/NotFound/Error views; never referenced), components/WhatsNewView.swift + @AppStorage showWhatsNew + AppDelegate.whatsNewWindow (never presented), @AppStorage hudReplacement (declared only, DynamicIslandViewCoordinator.swift:153), ProOnboarding.swift, AppDelegate.statusItem/togglePopover/showMenu/quitAction (DynamicIslandApp.swift:103, 1645-1659), LockIconLottieView (Lock.json) unused. components/LockScreen/LockScreenDynamicIslandReplica.swift and utils/Environment+LockScreenReplica.swift are licence-header-only stubs with no code.
- Localization: all UI strings go through String(localized:) with DynamicIsland/Localizable.xcstrings (2.3 MB) and a tr.lproj Turkish bundle - the spec should state that every title quoted is a localizable key.
- Log export specifics (DynamicIslandApp.swift:1319-1372): NSSavePanel title 'Export Logs & Crash Reports', nameField 'Atoll_Logs.zip'; work runs on Task.detached(.utility); unified log written to app_logs.txt in a UUID temp dir; NSAlert 'Logs Exported' / 'Export Failed'.

Corrections:

- DynamicIslandApp.swift:79-87: the spec lists 'CommandGroup(replacing: .appSettings) -> Settings…' as a live menu command. `commands` is a stray `@CommandsBuilder var` property that is never attached to the Scene (body at L50-77 has no `.commands { }`), so that CommandGroup is dead code and no Cmd-, item exists.
- Sparkle 'custom SwiftUI user driver' is NOT wired. DynamicIslandApp.swift:42-44 builds SPUStandardUpdaterController(startingUpdater:updaterDelegate: AtollUpdaterDelegate(), userDriverDelegate: nil); AtollUserDriver (components/Settings/CustomUpdaterViews/AtollUserDriver.swift:29) and the Update* views are referenced nowhere outside their own folder (grep), so users get Sparkle's standard UI. Only the channel-switching delegate (services/AtollUpdaterDelegate.swift:24-28, feedURLString -> Defaults[.updateChannel].feedURL) is active.
- Counts: the search index has 221 `SettingsSearchEntry(tab:` rows (components/Settings/SettingsView.swift:223 ff.), not '~230'; models/Constants.swift declares 373 `static let … = Key<…>` entries (lines 986-1644), not 'roughly 300'.
- sizing/matters.swift:69-75 openNotchSize is `min(max(storedWidth, minWidth, sideLyricsRequiredNotchWidth()), maxWidth)` - the spec drops the side-lyrics minimum term; maxAllowedNotchWidth (L79-89) returns 900 when no screen is resolvable and otherwise max(screenWidth - 60, 400).
- sizing/matters.swift:160-198 minimalisticOpenNotchSize: the base size is 420x180 (minimalisticBaseOpenNotchSize L160) and only becomes 340x144 in Dynamic-Island mode; the function then ADDS minimalisticLyricsExtraHeight 50 when enableLyrics && !isAdvertisement (L161, 182-184), ReminderLiveActivityManager.additionalHeight(forRowCount:) for active reminder rows (L186-190), and minimalisticTimerCountdownBlockHeight 94 (12 + 82) when timerLiveActivityEnabled && isExternalTimerActive (L162-164, 192-194). The spec states only the 340x144 figure.
- Siri responsiveness: the spec attributes the 30/16/4 Hz figures to Constants.swift:744-769, which are only the Settings description strings. The real polling intervals are in managers/SiriVisibilityMonitor.swift:99-108 - highPerformance idle 0.2 s / active 0.03 s (~33 Hz), balanced idle 0.5 / active 0.06 (~16 Hz), powerSaver idle 2.0 / active 0.25 (4 Hz); .automatic resolves to powerSaver (Low Power Mode) / highPerformance (plugged in) / balanced (L86-96); the monitor only runs while locked AND the display is awake (L120) and needs 3 consecutive misses before declaring Siri gone (L40-41, 152-162).
- Extension 'rate-limit windows' are recorded but never enforced: ExtensionAuthorizationManager.recordActivity appends timestamps and flushOldTimestamps keeps only the last 5 minutes (managers/Extensions/ExtensionAuthorizationManager.swift:~100-118, ~187-190), but nothing anywhere throws ExtensionValidationError.rateLimited (only declared at managers/Extensions/ExtensionActivityModels.swift:62 and mapped to an RPC error code at services/Extensions/ExtensionRPCService.swift:347). The only enforced limits are the capacity caps 4/4/2 and authorization/scope checks.
- Evidence attribution: the spec says REA 'confirms' the SkyLight framework path string and the five SLS* symbol strings. The REA JSON files contain neither the framework path nor those strings as binary strings (dispatch.json lists the SLS* names only as Swift declaration names inside SkyLightOperator; macho.json imports contain no SLS symbol because they are resolved via dlsym). They ARE present in the shipped Mach-O when dumped with `strings` (SkyLight.framework x2, each SLS* name x6), as are 'CGSSessionScreenIsLocked', 'Privacy_Accessibility/AllFiles/DevTools/FilesAndFolders', 'api.open-meteo.com', 'wttr.in', 'com.ebullioscopic.Atoll.xpc', 'com.ebullioscopic.Atoll.lifecycle', the `log show` predicate and 'NSGlassEffectView'. Cite these as 'binary strings', not 'REA'. Identifiers of 15 bytes or fewer (mountain.2.fill, Restart Atoll, lock.mp3, Atoll_Logs.zip, FingerprintScan, AXFullScreen, desktop.jpeg) are Swift small strings and cannot be confirmed by `strings`.
- helpers/LiquidGlassBackground.swift:178-200: the private setter is not called through NSSelectorFromString("set_variant:") + performSelector; the selector name is assembled as "set" + "_variant" + ":" and the IMP is fetched with class_getInstanceMethod/method_getImplementation and invoked via unsafeBitCast to a @convention(c) (AnyObject, Selector, Int) -> Void. Functionally the same private hook, but 'set_variant' is therefore not a contiguous string in the binary (0 hits) while 'NSGlassEffectView' is (2 hits).
- Weather ticker file attribution: the spec's 'Timer every 15.0 s (tolerance 0, .common) + minute-aligned timer … (L71-205)' lives in components/LockScreen/LockScreenWeatherWidget.swift:69-205 (a ticker class inside the widget file); managers/LockScreenWeatherManager.swift has no 15 s timer at all.
- Task text mentions 'URL scheme handling' and the spec's app-lifecycle feature implies app-level URL entry points: Atoll declares NO custom URL scheme (no CFBundleURLTypes in DynamicIsland/Info.plist or the REA plist evidence; 'atoll://' absent from the binary). The only `application(_:open:)` path is for file URLs -> Shelf (DynamicIslandApp.swift:170-191). The Spotify OAuth callbackURLScheme belongs to the media subsystem (managers/Spotify/SpotifyOAuthService.swift:92).
- hudReplacement=true is listed as a live setting; DynamicIslandViewCoordinator.swift:153 is its only occurrence - nothing reads it. Likewise showWhatsNew (L127), AppDelegate.whatsNewWindow (DynamicIslandApp.swift:109) and components/WhatsNewView.swift are never used.
- Lock-screen media panel vs its own preview: LockScreenPanelManager.collapsedFrame uses defaultLowering -68 (managers/LockScreenPanelManager.swift:~404-409) but LockScreenWidgetPreviewManager's LockScreenPreviewScene.mediaFrame uses -28 (managers/LockScreenWidgetPreviewManager.swift:491), so the in-app preview sits 40 pt higher than the real lock screen. The spec's -68 is the correct runtime value; flag the preview mismatch.
- ScreenCaptureVisibilityManager: the spec implies registration scopes matter; `applyVisibility(to:scope:)` ignores the scope (parameter named `_`) and applies the same sharingType to every registered window (helpers/ScreenCaptureVisibilityManager.swift:65-68).
- DynamicIslandWindow 'level = .mainMenu + 3 (L57)' is at components/Notch/DynamicIslandWindow.swift:55; the init also sets titleVisibility .hidden, titlebarAppearsTransparent true, isReleasedWhenClosed false and registers with ScreenCaptureVisibilityManager (.entireInterface) (L44-57), which the spec omits.
- LockScreenAnimationTimings is at managers/LockScreenManager.swift:31-62 (not 31-63) and LockSoundPlayer at L461-519; the spec's 'L27-29 powerKey' and 'L359-391 polling' are correct. Minor line drift only.

Private API summary:

PRIVATE APIs used by this subsystem (source + REA/binary evidence):
1) CoreGraphics/SkyLight private Space API via @_silgen_name in private/CGSSpace.swift:70-87 - _CGSDefaultConnection, CGSSpaceCreate, CGSSpaceDestroy, CGSSpaceSetAbsoluteLevel, CGSAddWindowsToSpaces, CGSRemoveWindowsFromSpaces, CGSHideSpaces, CGSShowSpaces. REA macho.json imports confirm all eight undefined symbols (__CGSDefaultConnection, _CGSSpaceCreate, _CGSSpaceDestroy, _CGSSpaceSetAbsoluteLevel, _CGSAddWindowsToSpaces, _CGSRemoveWindowsFromSpaces, _CGSHideSpaces, _CGSShowSpaces); dispatch.json lists CGSSpace and NotchSpaceManager. Used by managers/NotchSpaceManager.swift:32 (CGSSpace(level: 2147483647)) to pin every notch window across Spaces/fullscreen; membership synced in DynamicIslandApp.swift:383-406, 436, 363-371, 934-938, 974-983. (Two more CGS imports, _CGSIsScreenWatcherPresent and _CGSRegisterNotifyProc, belong to the screen-recording subsystem.)
2) SkyLight.framework via the Lakr233/SkyLightWindow package (Package.resolved rev 4a7e8628): dlopen('/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight') + dlsym of SLSMainConnectionID, SLSSpaceCreate, SLSSpaceSetAbsoluteLevel, SLSShowSpaces, SLSSpaceAddWindowsAndRemoveFromSpaces; a space at absolute level 400 is created and each window is moved into it with SLSSpaceAddWindowsAndRemoveFromSpaces(cid, space, [windowNumber], 7). Evidence: macho.json imports _dlopen/_dlsym and NO SkyLight LC_LOAD_DYLIB (dependencies list has only public frameworks + @rpath Lottie/Sparkle); dispatch.json has SkyLightOperator; `strings` on /Applications/Atoll.app/Contents/MacOS/Atoll shows the framework path x2 and each SLS name x6. This is the ONLY reason any widget renders above loginwindow. Call sites: LockScreenPanelManager.swift (media panel), LockScreenLiveActivityWindowManager.swift (lock/fingerprint overlay), LockScreenWeatherPanelManager.swift, LockScreenTimerWidgetManager.swift, LockScreenReminderWidgetPanelManager.swift, Extensions/ExtensionLockScreenWidgetPresentationController.swift - each delegates once per window and never closes the window afterwards.
3) Private AppKit class NSGlassEffectView and its private variant setter (helpers/LiquidGlassBackground.swift:120-215): NSClassFromString("NSGlassEffectView"), selector built as set + _variant + :, IMP invoked through unsafeBitCast; 20 variants v0-v19, default v11. 'NSGlassEffectView' is in the binary strings. Used by the lock-screen media panel and timer widget when lockScreenGlassCustomizationMode/lockScreenTimerGlassCustomizationMode == .customLiquid (and by OSD/vertical HUD/LocalSend picker elsewhere). Public macOS 26 glassEffect() is used for the Standard mode.
4) Private SwiftUI symbol Image(_internalSystemName:) via @_silgen_name("$s7SwiftUI5ImageV19_internalSystemNameACSS_tcfC") in extensions/Image+InternalSystemName.swift:21-30; used by FocusModeType.resolvedActiveIcon(usePrivateSymbol: true) (managers/DoNotDisturbManager.swift:733-745) to draw Apple's internal Focus glyphs in the lock-screen status/focus row (components/LockScreen/LockScreenWeatherWidget.swift:1232) and the focus live activity.
Undocumented-but-public / fragile APIs: CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"] 500 ms poll (LockScreenManager.swift:359-391; import and key string confirmed); DistributedNotificationCenter "com.apple.screenIsLocked"/"com.apple.screenIsUnlocked" (strings confirmed); NSEvent .systemDefined subtype rawValue 1 (power/Touch ID key) local+global monitors (LockScreenManager.swift:27-29, 171-189); Accessibility attribute "AXFullScreen" (observers/FullscreenMediaDetection.swift:111-141) and AXIsProcessTrusted/WithOptions (imports confirmed); Full Disk Access detection by opening ~/Library/Application Support/com.apple.TCC/TCC.db and ~/Library/DoNotDisturb/DB/ModeConfigurations.json (FullDiskAccessPermissionStore.swift:24-45; strings confirmed); x-apple.systempreferences deep links Privacy_Accessibility/AllFiles/DevTools/FilesAndFolders (strings confirmed); CGWindowListCopyWindowInfo owner "Siri" heuristic (SiriVisibilityMonitor.swift:186-203); OSDUIHelper manipulation (kill -9, launchctl kickstart, SIGSTOP/SIGCONT) reached from LockScreenManager.updateNativeHUDSuppression via SystemHUDManager/SystemOSDManager; `log show` + `/usr/bin/zip` Process spawning for log export.
Public APIs confirmed by REA imports: CGShieldingWindowLevel, CGDisplayIsBuiltin, CGMainDisplayID, NSHapticFeedbackManager, SMAppService (LaunchAtLogin-Modern, SettingsView.swift:1197), SPUStandardUpdaterController (Sparkle 2.7.0), RegisterEventHotKey (KeyboardShortcuts 2.3.0; 'KeyboardShortcuts_' prefix in binary), TISCopyCurrentKeyboardLayoutInputSource/UCKeyTranslate (Carbon, extensions/KeyboardShortcutsHelper.swift), NSXPCListener mach service com.ebullioscopic.Atoll.xpc (entitlement + string), Network.framework NWListener on 127.0.0.1/::1 port 9020, CLLocationManager, EventKit, AVAudioPlayer. The app is NOT sandboxed (entitlements: disable-library-validation, camera, apple-events + temporary exceptions, calendars, mach-services, Sparkle mach-lookup exceptions), which is what lets items 1-4 run.
