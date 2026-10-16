# Atoll spec: SHELF and CLIPBOARD (Atoll 2.3.3 — components/Shelf/*, components/Notch/NotchShelfView.swift, ContentView drop detector, application:open urls, managers/ClipboardManager.swift, components/Clipboard/*, components/Notch/NotchClipboardView.swift, managers/ClipboardPanelManager.swift, managers/ClipboardWindowManager.swift)

Source: Atoll 2.3.3 source clone plus REA evidence from the installed binary (see ../atoll-behaviour-evidence.md). Values are quoted with file:line from the Atoll source. Reimplement behaviour, do not copy code (GPL-3).

## Summary

Base path for all file:line citations below: /private/tmp/claude-501/-Users-a-dynamic-iland-dynamic-island/b501c539-18bc-4747-a9c4-d824916ad38f/scratchpad/atoll-clone/Atoll/DynamicIsland/ (abbreviated "DI/"). Source clone is at tag/commit 868c25d (VERSION 2.3.3, same as the installed binary).

SHELF. The open notch has a "Shelf" tab (TabSelectionView.swift:72-73, icon "tray.fill") whose body is ShelfView: an HStack(spacing 12) of a square FileShareView quick-share drop zone on the left and a dashed-outline drop panel on the right (RoundedRectangle r16, 3pt dashed [10] stroke white@0.1 → accentColor@0.9 while a drag is over it). The panel shows either an empty state ("Drop files here", tray.and.arrow.down.fill) or a horizontal ScrollView of ShelfItemView cells (105pt wide, 56x56 QuickLook thumbnail r12, 2-line 12pt medium name, hover-revealed 20pt white x-button). Items are ShelfItem {id, kind: .file(bookmark Data)|.text|.link, isTemporary, cachedDisplayName, cachedIconData, cachedPath} persisted as pretty JSON at ~/Library/Application Support/DynamicIsland/Shelf/items.json, deduped by identityKey. Dragging anything onto the closed notch opens it straight to the Shelf tab (ContentView dragDetector: full-size Color.clear .onDrop(of:[.data]) → vm.anyDropZoneTargeting → coordinator.currentView = .shelf; vm.open()); when targeting ends without a drop the notch closes again, a drop sets vm.dropEvent so it stays open. Drop ingestion (ShelfDropService) prefers fileURL → url (file or web link) → utf8/plain text → raw .data saved to a temp file (isTemporary) → generic item. Items support single/Cmd/Shift click selection, AppKit rubber-band marquee selection with auto-scroll, Cmd+A, Delete, Escape, double-click open, right-click NSMenu (Open, Open With ▸ incl. default-app marker and "Other…" NSOpenPanel, Show in Finder, Quick Look (+Option alternate), Share…, Image Actions ▸ Remove Background/Convert Image…/Create PDF, Compress, Rename, Copy (+Option "Copy Path"), Remove), Quick Look via QLPreviewPanel/.quickLookPreview, and AppKit NSDraggingSource drag-out writing NSURL/NSString with Copy-only by default (opt-in Move via allowMoveOnDrag; copyOnDrag; autoRemoveShelfItems). While a drag/marquee/share sheet is active the notch is held open (ShelfSelectionModel.isDragging / vm.setAutoCloseSuppression / SharingStateManager.preventNotchClose). The closed notch shows a shelf HUD when items exist: standalone ShelfInlineLiveActivity (tray.fill left, bold rounded count right) or, when music is playing, a lowest-priority secondary wing badge. "open -a Atoll file" (application:open urls / openFile) adds files to the shelf and switches to the Shelf tab. Quick Share: FileShareView drop zone shares dropped files via the selected NSSharingService (AirDrop default, any discovered service, "System Share Menu" picker, or a custom LocalSend v2 protocol client with multicast discovery on 224.0.0.167:53317, a 480x400 device picker window, progress ring and a closed-notch LocalSendLiveActivity). All APIs used are public (QuickLookThumbnailing, QuickLookUI, _QuickLook_SwiftUI's .quickLookPreview, Vision, PDFKit, Network, CoreServices LSSetDefault*, AppKit sharing/dragging) — confirmed in REA macho.json load commands/imports; no private frameworks. The app is NOT sandboxed (signature.json entitlements lack app-sandbox), so it uses plain (non-security-scoped) bookmarks; Info.plist carries NSDocumentsFolderUsageDescription/NSDownloadsFolderUsageDescription and Settings gate the shelf on Full Disk Access or Documents+Downloads access.

CLIPBOARD. ClipboardManager polls NSPasteboard.general.changeCount every 0.5s, classifies into text/url/file/image/rtf (priority: real Finder file URLs → image files → file list; PNG/TIFF/JPEG data w/o files → image; plain http(s) string w/o RTF → url; RTF or HTML→RTF → rtf; plain string → text; image+files → ignored; .URL type → url), dedups, inserts at index 0, trims to clipboardHistorySize (default 3; choices 3/5/7/10), and persists history/pinned as JSON in UserDefaults keys "ClipboardHistory"/"ClipboardPinnedItems" with image PNGs in ~/Documents/ClipboardData (or in-memory only when persistClipboardHistory is off). Four display modes (clipboardDisplayMode, default .panel): panel = floating 380x480 non-activating NSPanel (r18, hudWindow material, search field, sliding segmented History/Favorites tabs, 34pt badge rows with hover pin/copy/delete, position remembered in clipboardPanelPositionX/Y); popover = 280x320 SwiftUI popover from the header "list.clipboard" capsule button; separateTab = NotchClipboardView(fixedColumns: 2) card grid in the Notes tab split; notchTab = dedicated .clipboard tab with an adaptive card grid (min card width 200, cards draggable out via .onDrag with an 8s safety reset holding the notch open). Shortcut Cmd+Shift+V toggles whichever mode is active. Legacy, unreferenced code also exists (ClipboardWindow/ClipboardWindowManager 400x300 NSWindow, ClipboardHistoryPopover, TrayDrop/DropItem/DropItemView/AirDropView/DragDropView from boring.notch).

## Notch drop detector and auto-open to Shelf tab

### Behaviour

With the notch closed, dragging any item (file, text, URL, image) over the notch region makes the notch spring open directly on the Shelf tab. If the user drags away without dropping, the notch closes again (unless something else holds it open). If the user drops, the notch stays open showing the new item. While the notch is open on another tab, dragging over the shelf panel highlights its dashed border in the accent color. After closing the notch, if the shelf has items and "Open shelf tab by default if items added" is on, the next open lands on the Shelf tab. Disabled when the screen is locked, when the shelf feature is off, or in minimalistic UI mode.

### Layout

ContentView.swift:871 `.background(dragDetector)` on the whole notch root view (so the hit area is the full notch window frame incl. open-state padding, lines 862-866). ContentView.swift:2065-2092 `dragDetector`: `Color.clear.frame(maxWidth:.infinity,maxHeight:.infinity).contentShape(Rectangle()).onDrop(of: [.data], isTargeted: $vm.dragDetectorTargeting) { _ in true }` — the drop closure returns true but ignores providers; actual ingestion happens in ShelfView's own onDrop. Guard: `lockScreenManager.isLocked` → EmptyView; `Defaults[.dynamicShelf] && !Defaults[.enableMinimalisticUI]` required (2066-2068).

### Animations

Open/close use vm.open()/vm.close() (DynamicIslandViewModel.swift:395-458); the notch container animation is `DynamicIslandAnimations.animation` = `.spring(.bouncy(duration: 0.4))` for notch style, else `.timingCurve(0.16, 1, 0.3, 1, duration: 0.7)` (animations/drop.swift:33-39). ShelfView's panel applies `transaction.animation = vm.animation` (ShelfView.swift:143-145) so the dashed-border color change rides the same spring.

### State and timing

ContentView.swift:2073-2089 `.onChange(of: vm.anyDropZoneTargeting)`: if targeted && notchState == .closed → `coordinator.currentView = .shelf; openNotch()` (vm.open()). If not targeted: if `vm.dropEvent` is true → reset it to false and return (keep open, a drop happened); else reset and `if !shouldPreventAutoClose() { vm.close() }`. `shouldPreventAutoClose()` (2473-2479) = firstLaunch || any popover active || vm.isAutoCloseSuppressed || ShelfSelectionModel.shared.isDragging || ClipboardManager.shared.isDraggingItem || SharingStateManager.shared.preventNotchClose || (terminalStickyMode && currentView == .terminal). vm.close() (DynamicIslandViewModel.swift:443-458) resets suppression tokens and sets `coordinator.currentView = .shelf` when `!ShelfStateViewModel.shared.isEmpty && Defaults[.openShelfByDefault] && !Defaults[.enableMinimalisticUI]`, else `.home` unless openLastTabByDefault. After a drag-out ends, `vm.shouldRecheckHover.toggle()` (ShelfItemView.swift:112) → ContentView.swift:806-812 `runAfter(0.1)` closes the notch if open, not hovering and not prevented. Stale legacy: DynamicIslandViewCoordinator.swift:138 still consults `TrayDrop.shared.isEmpty` (the old boring.notch tray, always empty) when alwaysShowTabs turns off.

### Data sources and APIs

SwiftUI `.onDrop(of:isTargeted:perform:)` (public; REA macho.json imports `_$s7SwiftUI4ViewPAAE6onDrop2of10isTargeted7perform...`). DynamicIslandViewModel.swift:34-37 `@Published dragDetectorTargeting, dropZoneTargeting, dropEvent, anyDropZoneTargeting`; :164-169 `Publishers.CombineLatest($dropZoneTargeting,$dragDetectorTargeting).map{$0||$1}.assign(to:\.anyDropZoneTargeting)`. No private API.

### Settings

dynamicShelf (Bool, default true) models/Constants.swift:1215; openShelfByDefault (Bool, true) :1216; expandedDragDetection (Bool, true) :1227 — exposed in Settings (SettingsView.swift:4490-4493) but has NO code consumer anywhere (dead toggle); enableMinimalisticUI gates the feature.

### Dependencies

None (Defaults for settings; NotchIsland can use UserDefaults/@AppStorage).

### Implementation notes

NotchIsland: put a transparent `.onDrop(of: [.data], isTargeted:)` layer behind the whole notch root (closed and open sizes), combine its targeting with the inner shelf/quick-share targeting into one Bool, and drive open/close from `onChange` of that Bool with a `dropEvent` latch set by the inner drop handlers. Keep the hold-open predicate as a single function consulted by every auto-close path. ~80 lines in NotchViewModel + root view.

### Key files

- `DynamicIsland/ContentView.swift`
- `DynamicIsland/models/DynamicIslandViewModel.swift`
- `DynamicIsland/animations/drop.swift`

## Shelf tab layout (ShelfView / NotchShelfView)

### Behaviour

The Shelf tab fills the open notch body with two regions: a square quick-share tile on the left and a wide dashed drop panel on the right. Empty panel shows a tray icon and "Drop files here". With items, a single horizontal row of file cells scrolls sideways (no scroll indicators); clicking empty background clears the selection; rubber-band selecting is possible in the empty space. Dragging over the panel turns the dashed border accent-colored.

### Layout

NotchShelfView.swift:24-27 just wraps `ShelfView().environmentObject(vm)`. ShelfView.swift:63-71 `HStack(spacing: 12) { FileShareView().aspectRatio(1, contentMode: .fit); panel.onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) }`. panel (121-147): `RoundedRectangle(cornerRadius: 16).stroke(targeting ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10]))` with `.overlay { ZStack { ShelfBackgroundClickCatcher (NSView, mouseUp clears selection unless dragging/marquee); content.padding() /*16*/ } }.contentShape(Rectangle())`. Empty state (151-163): `VStack(spacing: 10) { Image(systemName: "tray.and.arrow.down").symbolVariant(.fill).symbolRenderingMode(.hierarchical).foregroundStyle(.white, .gray).imageScale(.large); Text("Drop files here").foregroundStyle(.gray).font(.system(.title3, design: .rounded)).fontWeight(.medium) }`. Items (165-204): `ScrollView(.horizontal) { HStack(spacing: 8) { ForEach(items) { ShelfItemView(item:) } }.frame(minWidth: viewportSize.width, minHeight: viewportSize.height, alignment: .leading).overlay { ShelfMarqueeSelectionView } }.padding(-8).scrollIndicators(.never)` + GeometryReader preference measuring the viewport (196-201) + same `.onDrop` types (202-204). Open notch body size: `openNotchSize` = (max(stored openNotchWidth, recommended min for tab count), 200) (sizing/matters.swift:69-75).

### Animations

Panel stroke/overlay changes use `vm.animation` via `.transaction` (ShelfView.swift:143-145) = spring(.bouncy(duration 0.4)). No other explicit animation in ShelfView.

### State and timing

handleDrop (87-92): rejected (returns false) while `selection.isDragging || selection.isMarqueeSelecting`; otherwise `vm.dropEvent = true; ShelfStateViewModel.shared.load(providers); return true`. `onDisappear` releases auto-close suppression token (81-83). Marquee `onActiveChange` → `vm.setAutoCloseSuppression(active, token:)` (186-188) holds the notch open during a rubber-band.

### Data sources and APIs

SwiftUI ScrollView/onDrop; AppKit NSViewRepresentable click catcher (ShelfView.swift:26-46). `onAppear` runs `ShelfStateViewModel.shared.cleanupInvalidItems()` (207-209). QuickLook selection sync 72-80, 94-119 (`quickLookPresenter`). Public only.

### Settings

None beyond dynamicShelf gating the tab.

### Dependencies

None.

### Implementation notes

Straightforward SwiftUI. Use a `PreferenceKey` to measure the ScrollView viewport so the marquee overlay covers the empty trailing area. Negative padding (-8) lets cell backgrounds bleed to the panel padding edge. ~150 lines.

### Key files

- `DynamicIsland/components/Notch/NotchShelfView.swift`
- `DynamicIsland/components/Shelf/Views/ShelfView.swift`
- `DynamicIsland/sizing/matters.swift`

## Shelf item cell (ShelfItemView)

### Behaviour

Each item is a 105pt-wide tile: 56x56 rounded thumbnail (QuickLook preview, else file icon, else a white card with an SF symbol for text/link) over a centered two-line name. Hovering reveals a small white circular x at the top-right that removes the item. A selected tile has a translucent accent fill and 2pt accent border; a tile being dropped-onto shows a stronger accent fill and 3pt border. Right-click opens a context menu; double-click opens; drag starts after 3pt of movement.

### Layout

ShelfItemView.swift:64-69 `VStack(alignment: .center, spacing: 2) { iconView; textView }.frame(width: 105).padding(.vertical, 10).padding(.horizontal, 5).background(backgroundView).contentShape(Rectangle())`. iconView (152-158): `Image(nsImage: thumbnail ?? icon).resizable().aspectRatio(contentMode: .fit).frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)`. textView (161-168): `.font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white).lineLimit(2).truncationMode(.middle).multilineTextAlignment(.center).frame(height: 30, alignment: .top)`. removeButton (177-196) overlay `.topTrailing`: `Circle().fill(.white).frame(20x20).overlay(Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.black)).shadow(color: .black.opacity(0.4), radius: 2)`, `.padding(2)`, `.help("Remove from Shelf")`, `.transition(.scale.combined(with: .opacity))`; constants ShelfRemoveButton.size 20, inset 2, hitRegion 30 (32-40). backgroundView (199-239): `RoundedRectangle(cornerRadius: 12, style: .continuous).fill(bg).overlay(strokeBorder(stroke, lineWidth))` with dropTarget → fill accent@0.25 / stroke accent@0.9 / 3pt; selected → accent@0.15 / accent@0.8 / 2pt; else clear/clear/1pt. Text/link fallback thumbnail (ShelfItem.swift:221-249): NSImage 64x80, white rounded card inset 2 with corner radius min(w,h)*0.06, SF symbol 38pt labelColor centered; symbols: file "questionmark.circle", text "text.justifyleft", link "link" (294-303). Generic file icon when no cached icon: `NSWorkspace.shared.icon(forFileType: "public.item")` (134).

### Animations

`.animation(.easeInOut(duration: 0.1), value: debouncedDropTarget)` and `.animation(.easeInOut(duration: 0.1), value: isSelected)` (ShelfItemView.swift:73-74). Hover: `withAnimation(.smooth(duration: 0.15)) { isHovering = hovering }` (97-99). Drop-target flag debounced 50ms (`Task.sleep(.milliseconds(50))`, 121-128). Remove button transition scale+opacity (196).

### State and timing

Click handling (ShelfItemViewModel.swift:226-238, invoked on mouseUp without a drag): Shift → range select from anchor; Cmd → toggle; Ctrl → context menu; else select single if not already selected; `clickCount == 2` → open all selected (ShelfActionService.open: file → NSWorkspace.open, link → open URL, text → copy string to pasteboard; ShelfActionService.swift:30-42). Right-click (240-243) selects the item if unselected then shows the menu. Drag preview image is pre-rendered once on appear via SwiftUI ImageRenderer at screen backing scale (129-146, 243-249).

### Data sources and APIs

Hover tracked by NSTrackingArea `[.mouseEnteredAndExited, .activeAlways, .inVisibleRect]` on the AppKit drag view (335-345) because that NSView sits on top of the SwiftUI cell; `hitTest` yields the 30x30 top-trailing corner to the SwiftUI remove button while hovering (365-380). Accessibility: combined element, label = displayName, custom action "Remove from Shelf" (82-86). Metadata loaded by ShelfItemViewModel.loadMetadata (ShelfItemViewModel.swift:56-82): resolve bookmark async → applyCachedPath → displayName (localizedName, with TextBlocks JSON/WebLocs plist special cases 93-124) → `NSWorkspace.shared.icon(forFile:)` → `ThumbnailService.shared.thumbnail(for:size: 56x56)`.

### Settings

None.

### Dependencies

None.

### Implementation notes

Reproduce with a SwiftUI cell plus an NSViewRepresentable overlay that owns mouseDown/mouseDragged/mouseUp/rightMouseDown and tracking areas (needed for a real NSDraggingSession). The 50ms debounce on the drop-target flag avoids flicker when SwiftUI toggles isTargeted. ~250 lines.

### Key files

- `DynamicIsland/components/Shelf/Views/ShelfItemView.swift`
- `DynamicIsland/components/Shelf/ViewModels/ShelfItemViewModel.swift`
- `DynamicIsland/components/Shelf/Models/ShelfItem.swift`

## Drag-out of shelf items (NSDraggingSource)

### Behaviour

Dragging a tile (after 3pt movement) lifts a composite preview (thumbnail + accent-colored name pill) and drags the real file(s) to Finder/Mail/Slack etc. If several tiles are selected and the dragged one is among them, all selected are dragged. By default the destination gets a Copy; "Allow moving files when dragging out" adds Move for external apps; "Copy items on drag" forces copy-only everywhere; "Remove from shelf after dragging" removes dragged items after a successful drop. The notch stays open for the whole drag and re-evaluates hover when it ends.

### Layout

DragPreviewView.swift:31-50: `VStack(alignment: .center, spacing: 4) { Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit).frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12)); Text(displayName).font(.system(size: 12, weight: .medium)).foregroundColor(.white).lineLimit(2).truncationMode(.middle).multilineTextAlignment(.center).padding(.horizontal, 8).padding(.vertical, 2).background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor)) }.frame(width: 105)`. Rendered with `ImageRenderer(content:)`, `scale = NSScreen.main?.backingScaleFactor ?? 2.0` (ShelfItemView.swift:243-249, 293-304). Each NSDraggingItem gets `setDraggingFrame(NSRect(0,0,image.size), contents: image)` (463-470).

### Animations

System drag animation only. Drag threshold `ShelfDragMetrics.threshold = 3.0` points (ShelfMarqueeSelectionView.swift:25-27; used at ShelfItemView.swift:329, 416).

### State and timing

mouseDown stores the event (386-389); mouseDragged computes hypot distance in window coords and when > 3pt: `didStartDragSession = true; prepareSelectionForDrag` (if no Shift/Cmd/Ctrl and item not selected → selectSingle, 426-436); `startDragSession` (438-478) drags all selected if count > 1 and includes this item, else just this item. `draggingSession(_:willBeginAt:)` → `ShelfSelectionModel.shared.beginDrag()` (isDragging = true, holds notch open via shouldPreventAutoClose). `draggingSession(_:endedAt:operation:)` (532-543) → endDrag(); if `Defaults[.autoRemoveShelfItems] && !operation.isEmpty` remove each dragged item; `onDragEnded` → `vm.shouldRecheckHover.toggle()`. mouseUp without a started drag → onClick (391-403).

### Data sources and APIs

AppKit `NSView.beginDraggingSession(with:event:source:)`, `NSDraggingItem`, `NSDraggingSource` (REA macho.json imports `_OBJC_CLASS_$_NSDraggingItem`, `_OBJC_CLASS_$_NSPasteboardItem`). Pasteboard writers (ShelfItemView.swift:496-506): `.file` → `item.resolvedFileURL as NSURL` (declares public.file-url, public.url, url-name, legacy filenames); `.text` → NSString; `.link` → NSURL. Unresolvable file items are skipped from the drag (457). resolvedFileURL (ShelfItem.swift:263-269) = `URL(fileURLWithPath: cachedPath)` fast path, else `Bookmark.resolveWithoutMounting()` (`.withoutMounting`, Bookmark.swift:108-117). Operation masks (510-525): `.outsideApplication` → `(Defaults[.allowMoveOnDrag] && !Defaults[.copyOnDrag]) ? [.copy, .move] : [.copy]`; `.withinApplication` → `Defaults[.copyOnDrag] ? [.copy] : [.copy, .move, .generic]`; `ignoreModifierKeys` false (545-547). Legacy SwiftUI NSItemProvider path (`dragItemProvider`, ShelfItemViewModel.swift:148-223 using registerFileRepresentation for UTType.fileURL) is still present but unused by the live cell.

### Settings

copyOnDrag (Bool, false) Constants.swift:1221; allowMoveOnDrag (Bool, false) :1225 (comment: Move lets Finder relocate originals on same volume); autoRemoveShelfItems (Bool, false) :1226. Settings labels: "Copy items on drag", "Allow moving files when dragging out", "Remove from shelf after dragging" (SettingsView.swift:4495-4508).

### Dependencies

None.

### Implementation notes

Must be AppKit: SwiftUI `.onDrag` cannot carry multiple files and has no completion callback. Implement an NSView subclass conforming to NSDraggingSource inside an NSViewRepresentable overlay; hand `NSURL` objects as pasteboard writers. ~200 lines.

### Key files

- `DynamicIsland/components/Shelf/Views/ShelfItemView.swift`
- `DynamicIsland/components/Shelf/Views/DragPreviewView.swift`
- `DynamicIsland/components/Shelf/ViewModels/ShelfSelectionModel.swift`

## Selection model and marquee (rubber-band) selection

### Behaviour

Click selects one; Cmd-click toggles; Shift-click selects the range from the last anchor; clicking empty panel background clears. Pressing in empty space and dragging > 3pt draws a translucent selection rectangle (system selection color) that selects every tile it intersects; Shift adds to the existing selection, Cmd toggles; near the left/right edges the row auto-scrolls. Escape cancels a marquee (restoring the prior selection) or clears selection; Delete/Forward Delete removes selected items; Cmd+A selects all. A plain click below the threshold on the background clears the selection.

### Layout

Marquee rectangle drawn in `draw(_:)` (ShelfMarqueeSelectionView.swift:328-338): `NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))`, fill `NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25)`, stroke same color @0.9, `lineWidth = 1`; redraw regions inset -2 (321-326). The view is an `.overlay` on the ScrollView content (ShelfView.swift:180-190) and is flipped (82).

### Animations

None (immediate redraw via setNeedsDisplay). Auto-scroll timer 1/60 s on `.common` and `.eventTracking` run-loop modes (257-264); `autoScrollEdge = 24`pt, `autoScrollMaxStep = 12`pt per tick, step = min(maxStep, edge − distanceIntoEdge) (79-80, 272-299).

### State and timing

mouseDown: makeFirstResponder, store anchor (107-112). mouseDragged: below 3pt threshold → ignore; above → startMarquee (beginMarquee(mode), onActiveChange(true) → vm auto-close suppression, install up-monitor), then `applyBand` computes the normalized rect, intersects with registry frames and calls `updateMarquee(hitIDs:)` which only publishes when the set changes (167-183). mouseUp: forceFinish(cancelled:false) → endMarquee; if no marquee happened → onBackgroundClick → clear selection (138-146). QuickLook selection updates are skipped mid-marquee (ShelfView.swift:74-80).

### Data sources and APIs

Pure AppKit NSView: hitTest returns nil over item cells (via ShelfItemHitRegistry frames, 92-103) so cell drags still reach the cell view; once active it claims all events. Modifier mapping at start (183-193): Command → `.toggle`, Shift → `.union`, else `.replace`. Safety nets: local `NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp)` (236-242), `NSEvent.pressedMouseButtons & 1 == 0` check (135), `viewDidMoveToWindow` with window nil → cancel (216-222), `dismantleNSView` cancel (64-66). Key codes: Escape 53, Delete 51, Forward Delete 117 (150-169); `performKeyEquivalent` handles Cmd+A even when not first responder (171-179). ShelfItemHitRegistry (Services/ShelfItemHitRegistry.swift:28-73) maps item UUID → weak NSView, `frames(in:)` converts `view.bounds` into the marquee's coordinate space and prunes dead views. Selection model (ShelfSelectionModel.swift): `selectedIDs: Set<UUID>`, `lastAnchorID`; selectSingle 53-56, toggle 58-65, shiftSelect 67-79 (range between anchor index and target index), clear 81-84, selectAll 86-91, reconcileSelection on item changes 93-113; `isDragging` 122-130; marquee state 138-210 with `marqueeBaseSelection` (empty in replace mode), `marqueePreviousSelection` (restored on cancel), `marqueeFirstHitID` becomes the new anchor on end.

### Settings

None.

### Dependencies

None.

### Implementation notes

Port the hit-registry idea (cells register their NSView by id) instead of walking view hierarchies. Keep the marquee NSView inside the ScrollView document view so empty-space mouseDowns reach it. ~350 lines for marquee + registry + selection model.

### Key files

- `DynamicIsland/components/Shelf/Views/ShelfMarqueeSelectionView.swift`
- `DynamicIsland/components/Shelf/ViewModels/ShelfSelectionModel.swift`
- `DynamicIsland/components/Shelf/Services/ShelfItemHitRegistry.swift`

## Shelf item context menu and file actions

### Behaviour

Right-click on a tile: Open; Open With ▸ (default app first with grey "(default)" suffix and 16pt app icons, separator, other apps alphabetically, separator, "Other…" which shows an NSOpenPanel rooted at /Applications with an "Enable: Recommended Applications / All Applications" popup and an "Always Open With" checkbox); Show in Finder (files); Quick Look (files/links; Option shows an alternate Quick Look item); ─; Share… (NSSharingServicePicker); ─ Image Actions ▸ Remove Background (single image), Convert Image… (single image), Create PDF (≥1 image) ─; Compress (files/folders → zip added to shelf as temporary item); Rename (single file, NSSavePanel); Copy (Option → Copy Path); ─; Remove. Actions apply to the whole selection where sensible. Convert Image dialog: NSAlert with Format (PNG/JPEG/HEIC/TIFF/BMP), Image Size (Actual/Large 1280/Medium 640/Small 320/Custom…), Preserve Metadata (on), and a Compression slider (default 85%) shown only for JPEG/HEIC; results are added to the shelf as temporary files named <name>_converted.<ext>, <name>_no_bg.png, images_<timestamp>.pdf.

### Layout

NSMenu built in ShelfItemViewModel.presentContextMenu (ShelfItemViewModel.swift:336-528): items identified by `NSUserInterfaceItemIdentifier(title)` (340-345); Open With submenu app rows have `image = nsAppIcon(for:size: 16)` (399, 420; icon rendered via NSImage(size:flipped:) with .high interpolation 1229-1244); default row attributedTitle: app name labelColor + " (default)" secondaryLabelColor in `NSFont.menuFont(ofSize: 0)` (401-410); "No Compatible Apps Found" disabled row when none (390-394). Open-with panel accessory (809-840): NSStackView vertical spacing 12, edgeInsets (16,20,16,20), row spacing 8, popup min width 200. Convert dialog accessory 380x180 (1019); format label at (0,145,100,20) 12pt medium, popup (120,140,250,28); size label (0,105), popup (120,100,160,28), custom field (285,103,85,22) placeholder "e.g., 1920"; metadata checkbox (120,65,200,20) on; separator y=50 1px separatorColor; compression label (0,7,100,20), slider (120,12,200,20) 0…1 default 0.85, value label (325,7,55,20) "85%".

### Animations

None (AppKit menus/panels).

### State and timing

Menu presentation ensures the clicked item is selected (332-337). Folders are excluded from Open/Open With (353-359). SharingStateManager (SharingStateManager.swift): `preventNotchClose` true while activeSessions > 0; SharingLifecycleDelegate finishes on didShareItems/didFailToShareItems/picker cancel, with a 2-second timeout fallback after a service begins (`Task.sleep(for: .seconds(2))`); posts `.sharingDidFinish` → ContentView re-evaluates close after 0.1s (ContentView.swift:814-816). Processed outputs are added via `ShelfStateViewModel.shared.add([ShelfItem(kind: .file(bookmark:), isTemporary: true)])`.

### Data sources and APIs

`NSMenu.popUpContextMenu(_:with:for:)` (527). `NSWorkspace.shared.urlsForApplications(toOpen:)` for URL and for UTType (376-387), `urlForApplication(toOpen:)` default (1246-1253), `NSWorkspace.shared.open(_:withApplicationAt:configuration:)` (581, 886), `activateFileViewerSelecting` (633), `LSSetDefaultRoleHandlerForContentType` / `LSSetDefaultHandlerForURLScheme` for "Always Open With" (876-880; CoreServices — REA macho.json imports `_LSSetDefaultRoleHandlerForContentType`, `_LSSetDefaultHandlerForURLScheme`), `NSOpenSavePanelDelegate.panel(_:shouldEnable:)` filtering (784-803). Rename: `NSSavePanel` title "Rename File", prompt "Rename", nameField = lastPathComponent, directory = parent; `FileManager.moveItem` then `updateBookmark(path:)` (911-930). Copy: `NSPasteboard.general.writeObjects(fileURLs as [NSURL])` or newline-joined display names (656-687); Copy Path: newline-joined paths (638-654). Compress: `/usr/bin/zip` via Process — single file `-j -q`, single folder `-r -q <name>.zip <folder>` from parent dir, multiple → copy into temp working dir then `-r -q Archive.zip .` (TemporaryFileStorageService.swift:144-242). Image ops (ImageProcessingService.swift): Remove Background = `VNGenerateForegroundInstanceMaskRequest` + `generateScaledMaskForImage` + `CIFilter.blendWithMask` (84-137; Vision confirmed in REA imports `_OBJC_CLASS_$_VNGenerateForegroundInstanceMaskRequest`); Convert = NSBitmapImageRep representations (JPEG compressionFactor, TIFF LZW, HEIC via `CIContext.heifRepresentation` sRGB) with Lanczos downscale preserving source colorspace (184-254); Create PDF = `PDFDocument`/`PDFPage(image:)` (264-295; PDFKit confirmed). Share… = `NSSharingServicePicker(items:).show(relativeTo: .zero, of: view, preferredEdge: .minY)` with a SharingLifecycleDelegate that holds the notch open (250-293).

### Settings

None.

### Dependencies

None.

### Implementation notes

All public API. NotchIsland can start with Open / Open With / Show in Finder / Quick Look / Share / Copy / Copy Path / Rename / Remove and add Image Actions + Compress later. Use identifiers (not titles) to dispatch so localization cannot break it. ~600 lines for the full set.

### Key files

- `DynamicIsland/components/Shelf/ViewModels/ShelfItemViewModel.swift`
- `DynamicIsland/components/Shelf/Services/ShelfActionService.swift`
- `DynamicIsland/components/Shelf/Services/ImageProcessingService.swift`
- `DynamicIsland/components/Shelf/Services/TemporaryFileStorageService.swift`
- `DynamicIsland/models/SharingStateManager.swift`

## Quick Look integration

### Behaviour

Choosing Quick Look from the context menu (or pressing the alternate Option item) opens the system Quick Look panel for all selected files/links, selecting the first. While the panel is open, changing the shelf selection updates the previewed set (except mid-marquee). Closing the panel externally resets state.

### Layout

No custom UI; system QLPreviewPanel.

### Animations

System.

### State and timing

`show(urls:selectFirst:)` sets urls, isQuickLookOpen = true, selectedURL = first (41-63). ShelfView.updateQuickLookSelection (94-119) resolves selected items' URLs async and calls `updateSelection(urls:)` only if the selection is unchanged since resolution began. `hide()` orders the panel out (65-77). The menu's Option alternate "Quick Look" item is wired to the same identifier (slideshow flag unused).

### Data sources and APIs

QuickLookService.swift: SwiftUI `.quickLookPreview($service.selectedURL, in: service.urls)` modifier (118-131; `_QuickLook_SwiftUI` framework, confirmed in REA macho.json load commands and import `quickLookPreview(_:in:)`), plus `QLPreviewPanel.shared()` observation of `NSWindow.willCloseNotification` to release security scope (56-62, 103-115; QuickLookUI confirmed `_OBJC_CLASS_$_QLPreviewPanel`). `QuickLookDataSource` (QLPreviewPanelDataSource/Delegate) exists but is unused by the SwiftUI path (134-149). URLs get `startAccessingSecurityScopedResource` (no-op for a non-sandboxed app).

### Settings

None.

### Dependencies

None.

### Implementation notes

Use `.quickLookPreview(_:in:)` (macOS 14+) bound to an ObservableObject; observe QLPreviewPanel willClose to sync state. ~80 lines.

### Key files

- `DynamicIsland/components/Shelf/Services/QuickLookService.swift`
- `DynamicIsland/components/Shelf/Views/ShelfView.swift`

## Drop ingestion (ShelfDropService, NSItemProvider helpers, temp files)

### Behaviour

Dropping Finder files adds them as file items; dropping a web link adds a link item (shown as host/path without http(s)://); dropping selected text adds a text item; dropping raw data/promised files (e.g. images from a browser, SwiftUI file promises) writes a temp file and adds it as a temporary item whose file is deleted when removed from the shelf. Duplicates (same file path / same URL / same text) are not added again. Files that no longer exist are pruned when the shelf appears.

### Layout

n/a

### Animations

n/a (items appear with the panel's vm.animation transaction).

### State and timing

ShelfStateViewModel.load (ShelfStateViewModel.swift:204-214): `isLoading = true`, async `ShelfDropService.items(from:)`, then `add(dropped)` on main, `isLoading = false` (isLoading is not rendered anywhere). add (116-131) appends only new identityKeys, preserving existing order (new items go to the END of the row), then notifies RPC subscribers ("added"). remove (133-138) calls `item.cleanupStoredData()` (deletes temp file only when isTemporary) and notifies "removed". cleanupInvalidItems (216-235) validates each file bookmark (`fileExists`) off-main and drops missing ones.

### Data sources and APIs

ShelfDropService.swift:60-88 per-provider priority: `extractFileURL()` (has UTType.fileURL) → file item; `extractURL()` (UTType.url, must have scheme) → file item if isFileURL else `.link`; `extractText()` (utf8PlainText, plainText) → `.text`; `loadData()` (UTType.data; accepts `com.apple.SwiftUI.filePromises` URLs and deletes the promise temp) → `TemporaryFileStorageService.createTempFile(.data(data, suggestedName: provider.suggestedName))` → file item `isTemporary: true`; `extractItem()` (UTType.item) → file item. Helpers in extensions/NSItemProvider+LoadHelpers.swift (loadItem(forTypeIdentifier:) with URL/Data/String coercion incl. bookmark data fallback). Bookmarks: `url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)` — plain, because the app is not sandboxed and `.withSecurityScope` throws on macOS 26 (Bookmark.swift:38-47; REA confirms `URL.bookmarkData(options:includingResourceValuesForKeys:relativeTo:)` and `URL(resolvingBookmarkData:...)` imports). Temp files (TemporaryFileStorageService.swift:75-132): `NSTemporaryDirectory()/<UUID>/<suggestedName ?? ".dat">`; text → `<UUID>/<UUID>.txt`; url → `<UUID>/<host ?? UUID>.webloc` with a minimal plist `{URL: absoluteString}` (247-258). Removal deletes the file and its now-empty UUID folder, only under NSTemporaryDirectory (46-71). Identity key (ShelfItem.swift:274-289): file → "file://"+standardized path (or "file://missing/"+base64 bookmark), link → "link://"+absoluteString, text → "text://"+string.

### Settings

None.

### Dependencies

None.

### Implementation notes

Reuse the same provider priority; for Swift 6 wrap NSItemProvider in an @unchecked Sendable box. Since NotchIsland is also unsandboxed (presumably), plain bookmarks + cachedPath are enough. ~250 lines.

### Key files

- `DynamicIsland/components/Shelf/Services/ShelfDropService.swift`
- `DynamicIsland/extensions/NSItemProvider+LoadHelpers.swift`
- `DynamicIsland/components/Shelf/Services/TemporaryFileStorageService.swift`
- `DynamicIsland/components/Shelf/Models/Bookmark.swift`

## Shelf persistence and bookmark self-healing

### Behaviour

Shelf contents survive relaunch (including items whose files were renamed/moved, via bookmark resolution). Corrupted entries are dropped individually without losing the rest.

### Layout

n/a

### Animations

n/a

### State and timing

On init, items load synchronously and `backfillCachedPaths()` resolves missing cachedPath values on a detached utility task, applying them in one mutation (58-110). `resolveFileURLAsync` (238-253): if the bookmark is stale, refresh it with a deferred coalesced update (`scheduleDeferredBookmarkUpdate`, 167-201, after `Task.yield()`); otherwise re-apply the resolved path (self-healing for moved files). Updates are guarded so a resolve that started before a rename cannot write back a pre-rename bookmark (`resolvedFrom` source checks, 95-110, 152-165). A URL→item cache (`urlToItemCache`) is rebuilt lazily for `findItem(by:)` (273-306).

### Data sources and APIs

ShelfPersistenceService.swift:36-45: file `~/Library/Application Support/DynamicIsland/Shelf/items.json` (falls back to temp dir), `JSONEncoder.outputFormatting = [.prettyPrinted]`, ISO-8601 dates; save is atomic (88-95). Load (47-86): decode `[ShelfItem]`; on failure, parse as JSON array and decode item-by-item, discarding failures. Schema (ShelfItem.swift:26-91): `{id: UUID, kind: {type: "file"|"text"|"link", value: Data(base64)|String|URL}, isTemporary: Bool, cachedDisplayName?: String, cachedIconData?: Data, cachedPath?: String}`. Every `items` mutation triggers a full save and selection reconciliation (ShelfStateViewModel.swift:30-35).

### Settings

None.

### Dependencies

None.

### Implementation notes

Store the same JSON shape (or NotchIsland's own) under Application Support/NotchIsland/Shelf/items.json; keep cachedPath to avoid main-thread bookmark I/O. ~150 lines.

### Key files

- `DynamicIsland/components/Shelf/Services/ShelfPersistenceService.swift`
- `DynamicIsland/components/Shelf/ViewModels/ShelfStateViewModel.swift`
- `DynamicIsland/components/Shelf/Models/ShelfItem.swift`

## Thumbnails and icons (ThumbnailService)

### Behaviour

File tiles show a QuickLook icon-mode thumbnail (document preview with the file-type frame) at 56x56; folders and unsupported types show the Finder icon; text/link items show a white card with an SF symbol.

### Layout

Request size 56x56 pt at `NSScreen.main?.backingScaleFactor ?? 2.0` scale (ThumbnailService.swift:72-82; requested from ShelfItemViewModel.swift:79).

### Animations

Thumbnail swaps in without animation when it arrives; the drag preview is re-rendered on thumbnail change (ShelfItemView.swift:141-146).

### State and timing

Loaded once per cell view model in init (`Task { await loadMetadata() }`, ShelfItemViewModel.swift:46-51); order: cachedPath heal → displayName → icon → thumbnail.

### Data sources and APIs

`QLThumbnailGenerator.shared.generateBestRepresentation(for: QLThumbnailGenerator.Request(fileAt:size:scale:representationTypes: .all))` with `request.iconMode = true` (ThumbnailService.swift:76-96; QuickLookThumbnailing confirmed in REA macho.json: `_OBJC_CLASS_$_QLThumbnailGenerator`, `_OBJC_CLASS_$_QLThumbnailGenerationRequest`). Actor with in-memory cache keyed `"<path>_<w>x<h>"` and in-flight request de-duplication (28-59). Fallback icon `NSWorkspace.shared.icon(forFile:)` (ShelfItemViewModel.swift:135-137). Legacy `QLThumbnailImageCreate` 128x128 in Ext+URL.swift:24-33 is only used by the dead TrayDrop path.

### Settings

None.

### Dependencies

None.

### Implementation notes

Use QLThumbnailGenerator with iconMode; cache per path+size in an actor. ~80 lines.

### Key files

- `DynamicIsland/components/Shelf/Services/ThumbnailService.swift`
- `DynamicIsland/components/Shelf/ViewModels/ShelfItemViewModel.swift`

## Quick Share tile (FileShareView / QuickShareService / AirDrop)

### Behaviour

Left square tile labelled with the chosen service's icon and name (default "AirDrop"). Dropping files/text/links onto it shares them immediately via that service (AirDrop sheet, Mail, Messages, Reading List, any installed share extension), or shows the system share picker for "System Share Menu"; for LocalSend a device picker appears first. Clicking the tile (AirDrop/LocalSend only) opens an NSOpenPanel to pick files to share. A small "switch.2" button at the tile's top-right opens a popover with a "Quick Share" menu picker of all services plus "Currently: X — Files shared from the shelf will use this service". While a drag hovers the tile its dashed border turns accent, the icon tints accent and scales up slightly. A dark overlay with a spinner shows while a picker/share is in progress.

### Layout

FileShareView.swift:78-93 tile: `RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [Color.black.opacity(0.35), Color.black.opacity(0.20)], startPoint: .topLeading, endPoint: .bottomTrailing)).overlay(RoundedRectangle(cornerRadius: 12).stroke(targeting ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10]))).shadow(color: Color.black.opacity(0.6), radius: 6, x: 0, y: 2)`; `.contentShape(RoundedRectangle(cornerRadius: 12))` (279); squared by `.aspectRatio(1, contentMode: .fit)` in ShelfView.swift:65. Content (96-137): `VStack(spacing: 5) { ZStack { Circle().fill(Color.white.opacity(targeting ? 0.11 : 0.09)).frame(width: 55, height: 55); provider image resizable scaledToFit 34x34 (or SF "square.and.arrow.up" 34x34) .foregroundStyle(targeting ? accent : .gray).scaleEffect(targeting ? 1.06 : 1.0) }; Text(provider.id).font(.system(.headline, design: .rounded)).foregroundColor(.white.opacity(0.8)).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity) }.padding(18)`. Switch button (143-160): `Image(systemName: "switch.2").resizable().aspectRatio(.fit).frame(14x14).padding(8).background(RoundedRectangle(cornerRadius: 8).fill(hover ? Color(.windowBackgroundColor).opacity(0.12) : .clear)).foregroundColor(hover ? .accentColor : .gray)`, `.padding(.trailing, 8).padding(.top, 8)`. Popover (161-229, arrowEdge .bottom): `VStack(alignment: .leading, spacing: 8) { Text("Quick Share").font(.headline); Picker(.menu).frame(minWidth: 260) rows HStack(spacing 8) 16pt icon r3 + name; HStack(alignment: .top, spacing: 8) { 20pt icon r4; VStack(spacing 2) { "Currently: X" .caption secondary; "Files shared from the shelf will use this service" .caption2 secondary } } }.padding()`. Loading overlay (237-245): `RoundedRectangle(12).fill(.black.opacity(0.3))` + `ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(0.8)`. LocalSend progress ring top-right (247-277): 24x24, `Circle().stroke(Color.white.opacity(0.16), lineWidth: 3)` + `Circle().trim(0…progress).stroke(Color.white, StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(-90°)`, checkmark 9pt bold white when > 0.99, `.padding(.top, 10).padding(.trailing, 10)`, `.transition(.opacity)`.

### Animations

Icon tint/scale: `.animation(.spring(response: 0.36, dampingFraction: 0.7), value: vm.dropZoneTargeting)` (FileShareView.swift:124). Ring progress `.animation(.easeInOut(duration: 0.2), value: sendProgress)` (262). Popover auto-close suppression released 0.05 s after dismissal (224-226).

### State and timing

onAppear → `quickShare.ensureDiscovered(); localSend.startDiscovery()` (54-57). Tap (69-75) only acts when provider is AirDrop or LocalSend. Switch button hover and popover both hold the notch open via `vm.setAutoCloseSuppression(_, token:)` (144, 159, 221-228). `isProcessing || quickShare.isPickerOpen` shows the overlay. Share lifecycle via SharingStateManager.beginInteraction/endInteraction + SharingLifecycleDelegate (2 s timeout fallback).

### Data sources and APIs

`.onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data, .image], isTargeted: $vm.dropZoneTargeting)` (58) sets `vm.dropEvent = true`. QuickShareService.swift discovery (62-153, lazy, off-main): `NSSharingService.sharingServices(forItems: [URL("https://apple.com") as NSURL, "Test Text" as NSString])` plus manually injected `.composeEmail, .sendViaAirDrop, .composeMessage, .addToSafariReadingList` (REA macho.json imports `_NSSharingServiceNameSendViaAirDrop`, `_NSSharingServiceNameComposeEmail`, `_NSSharingServiceNameComposeMessage`, `_NSSharingServiceNameAddToSafariReadingList`); each provider = {id: svc.title, imageData: 32x32 PNG of svc.image, supportsRawText: canPerform(["Test Text"])}; AirDrop moved to index 0, "LocalSend" inserted at index 1 with bundled asset "LocalSend" icon, "System Share Menu" appended. Sharing (218-261): LocalSend → LocalSendService.send; cached `NSSharingService.perform(withItems:)` if `canPerform`; else `NSSharingServicePicker(items:).show(relativeTo: .zero, of: hostView, preferredEdge: .minY)` anchored to a hidden NSView (NSViewHost 320-332). shareDroppedFiles (275-305): collects web URLs, first text, file URLs (resolving shelf bookmarks via `findItem(by:)`); text wins and is shared raw if supportsRawText, else written to a temp .txt then deleted. File picker (176-215): `NSOpenPanel` multi-select, files+dirs, title "Select Files for <X>", message "Choose files to share via <X>", sheet on the host window, `NSApp.activate(ignoringOtherApps: true)`. Legacy `AirDrop` class (AirDrop.swift:21-51) wraps `NSSharingService(named: .sendViaAirDrop)`; AirDropView.swift is unused.

### Settings

quickShareProvider (String, default "AirDrop") Constants.swift:1217 — also in Settings ▸ Shelf ▸ Quick Share picker (SettingsView.swift:4515-4550).

### Dependencies

None.

### Implementation notes

Public AppKit sharing API. Recommend starting with AirDrop + System Share Menu; discovery must run off-main and shrink service icons to 32x32 PNG to avoid memory spikes. ~400 lines without LocalSend.

### Key files

- `DynamicIsland/components/Shelf/Views/FileShareView.swift`
- `DynamicIsland/components/Shelf/Services/QuickShareService.swift`
- `DynamicIsland/components/Shelf/AirDrop.swift`
- `DynamicIsland/models/SharingStateManager.swift`

## LocalSend sharing (protocol client, device picker, live activity)

### Behaviour

When Quick Share is set to LocalSend, dropping onto the tile (or clicking it) first shows a 480x400 floating "Select Device" glass panel listing discovered LocalSend devices in a 3-column grid (device-type SF symbol, alias, model; red "Rejected" state), with refresh and close buttons, an empty state ("Scanning for devices..." / "No devices found" + "Scan Again"), click-outside to dismiss. Choosing a device uploads the files; a white progress ring appears on the tile and a LocalSendLiveActivity shows in the closed notch (upload icon on the left, progress ring → green checkmark / red x / orange hand on the right) for ~3 s after success or ~4 s after failure.

### Layout

LocalSendDevicePickerWindowManager.swift: borderless NSWindow 480x400 centered on NSScreen.main, `level = .floating`, `collectionBehavior [.canJoinAllSpaces, .fullScreenAuxiliary]`, transparent, hasShadow, movable by background, corner mask radius 24 continuous (44-93). View: header `HStack` padding(.horizontal 20, .top 20): `Image("LocalSend") 28x28`, `Text("Select Device").font(.system(size: 18, weight: .semibold, design: .rounded)).white`, refresh `arrow.clockwise 14 semibold white@0.8` in 32pt circle white@0.1 rotating, close `xmark 12 bold white@0.6` in 28pt circle white@0.1. Grid: `LazyVGrid(3 × .flexible(spacing: 16), spacing: 16).padding(.horizontal, 20).padding(.bottom, 20)`. DeviceGridItem (330-395): `VStack(spacing: 10) { Circle 56pt fill white@0.08 (hover 0.15; rejected red@0.15) + icon 24pt medium (white@0.8 / accent on hover / red rejected); alias 12pt medium white; model 10pt white@0.5 or "Rejected" 10pt medium red@0.8 }.padding(.vertical, 16).background(RoundedRectangle(16).fill(white@0.06 / 0.12 hover / red@0.08 rejected)).overlay(stroke hover ? accent@0.6 : white@0.1, 1pt)`, scale 1.02 on hover. Panel background: `.ultraThinMaterial` over black@0.4 (or LiquidGlass variants per setting); outer stroke white@0.2 1pt; shadow black@0.4 r30 y15 (231-237). Empty state: ProgressView white scale 1.2 + "Scanning for devices..." 14 medium white@0.7; or `antenna.radiowaves.left.and.right.slash` 48 light white@0.4, "No devices found" 16 medium white@0.7, hint 12 white@0.5, "Scan Again" capsule accent@0.8 13 medium padding h16 v8. LocalSendLiveActivity.swift (closed notch): left `RoundedRectangle(6, continuous).fill(tint.opacity(0.14))` with `document.badge.arrow.up.fill` 14 semibold tint, size (closedHeight−12)²; center black rect width `closedNotchSize.width + (hover ? 8 : 0) + (active ? 40 : 0)`; right width `max(60, closedHeight)` holding a 20pt ring (stroke 2.5 white@0.2 / accent round cap, −90°, checkmark 8 bold accent at > 0.99) or `checkmark.circle.fill` green / `xmark.circle.fill` red / `hand.raised.fill` orange at 16 semibold with `.padding(.trailing, 6)`; total height `closedHeight + (hover ? 8 : 0)`.

### Animations

Picker refresh icon `.linear(duration: 0.85).repeatForever(autoreverses: false)` while refreshing else `.easeOut(0.2)`; device tile `.spring(response: 0.3, dampingFraction: 0.7)` on hover. Live activity expand `withAnimation(.smooth(duration: 0.35))` on appear and on isActive change; ring `.easeInOut(duration: 0.2)`. Send state: minimum visible 0.8 s, completed → idle after 3 s, failed/rejected → idle after 4 s (LocalSendService.swift:568-597).

### State and timing

FileShareView.swift:58-68: drop with LocalSend selected stores `pendingDropProviders` and sets `showLocalSendPicker = true` → `LocalSendDevicePickerWindowManager.shared.show(onDeviceSelected:onDismiss:)` (280-302); selection sets `localSend.selectedDeviceID` then runs handleDrop. `LocalSendTransferState`: idle, sending, completed, failed(String), rejected(deviceID) (LocalSendService.swift:38-44); `rejectedDeviceIDs` persists until the device is re-selected. `isActive` for the live activity = isSending || completed || failed || rejected.

### Data sources and APIs

LocalSendService.swift (Network.framework, public; REA confirms NWConnectionGroup/NWMulticastGroup/NWListener imports): multicast discovery group 224.0.0.167:53317 UDP (`NWMulticastGroup`, `NWConnectionGroup`, allowLocalEndpointReuse, includePeerToPeer, 60-61, 93-107); announcement JSON `{alias: Host.current().localizedName ?? "Atoll", version: "2.1", deviceModel: "Mac", fingerprint: "atoll.localsend.bridge", port: 53317, …}` (600-607); stale device cutoff 30 s (817), cleanup loop every 15 s (120), re-announce loop 8 s (127); HTTP fallbacks: GET `/api/localsend/v2/info?fingerprint=…` probes of recent peers (timeout 0.14 s, limit 20) and legacy subnet sweep (0.12 s, concurrency 50) (165-301); a tiny `NWListener` HTTP server answers POST `/api/localsend/v2|v3/register` and GET `/api/localsend/v2/info` (620-770). Send: POST `/api/localsend/v2/prepare-upload` JSON (204 → nothing to send; 403 → rejected) returning `sessionId` + per-file tokens, then POST `/api/localsend/v2/upload?sessionId=&fileId=&token=` with `URLSession.uploadTask` and delegate-based byte progress (920-1020); TLS via custom `LocalSendTLSDelegate` (accepts self-signed; class confirmed in REA dispatch.json `_TtC5AtollP33_…LocalSendTLSDelegate`). Items → TransferFile(name, mimeType, data) via `buildTransferFiles`. Progress aggregated by bytes (529-547).

### Settings

localSendSelectedDeviceID (String, "") Constants.swift:1218; localSendDevicePickerGlassMode (LockScreenGlassCustomizationMode, .standard) :1219; localSendDevicePickerLiquidGlassVariant (LiquidGlassVariant, .v11) :1220; Settings ▸ Shelf shows a LocalSend section only when quickShareProvider == "LocalSend" (SettingsView.swift:4552-4554).

### Dependencies

None (Network.framework).

### Implementation notes

Optional for NotchIsland (large: ~1100 lines service + ~450 picker). If implemented, follow the public LocalSend protocol v2 (register/info/prepare-upload/upload) over Network.framework + URLSession; no private API involved.

### Key files

- `DynamicIsland/components/Shelf/Services/LocalSendService.swift`
- `DynamicIsland/managers/LocalSendDevicePickerWindowManager.swift`
- `DynamicIsland/components/Shelf/Views/LocalSendLiveActivity.swift`
- `DynamicIsland/components/Shelf/Views/FileShareView.swift`

## Closed-notch shelf HUD (ShelfInlineLiveActivity and secondary wing badge)

### Behaviour

When the notch is closed and the shelf holds items (and nothing higher-priority is showing), the closed notch widens to show a white tray icon on the left and a bold rounded white item count on the right. When music is playing, the shelf count instead appears as the lowest-priority secondary live activity in the music HUD's right wing (count text) with a `tray.and.arrow.down.fill` badge on the left. Count changes animate with a numeric roll.

### Layout

ShelfInlineLiveActivity.swift:30-55: `HStack(spacing: 0) { Image(systemName: "tray.fill").font(.system(size: 13, weight: .medium)).foregroundStyle(.white).frame(width: 24, alignment: .leading); Rectangle().fill(Color.black).frame(width: vm.closedNotchSize.width); Text("\(count)").font(.system(.callout, design: .rounded, weight: .bold)).foregroundStyle(.white).contentTransition(.numericText(countsDown: false)).frame(width: 24, alignment: .trailing) }.frame(height: vm.effectiveClosedNotchHeight, alignment: .center)`. Secondary variant (ContentView.swift:1737-1743): same count Text, `.frame(alignment: .center)`; badge (1675-1678): `Image(systemName: "tray.and.arrow.down.fill").font(.system(size: badgeSize * 0.50, weight: .semibold)).foregroundStyle(.white)`; right wing width = base width (1571-1572).

### Animations

Count: `.animation(.smooth(duration: 0.3), value: count)` with `.contentTransition(.numericText(countsDown: false))` (ShelfInlineLiveActivity.swift:50-51; ContentView.swift:1741-1742). Standalone HUD appears with `.transition(.opacity.animation(.smooth(duration: 0.25)))` (ContentView.swift:1167-1168).

### State and timing

Reactive to items.count; no timers.

### Data sources and APIs

Observes `ShelfStateViewModel.shared.items.count`. Priority: standalone shown when `!coordinator.expandingView.show && vm.notchState == .closed && !shelfState.isEmpty && !vm.hideOnClosed && !lockScreenManager.isLocked && !enableMinimalisticUI` and no extension/battery/other inline activity matched earlier in the else-if chain (ContentView.swift:1166); secondary `.shelf(count:)` is returned last in the music secondary resolver (1546-1549) with id "shelf-<count>" (3027-3028).

### Settings

hideOnClosed, enableMinimalisticUI (outside subsystem) suppress it.

### Dependencies

None.

### Implementation notes

Simple HStack around the black notch rectangle; NotchIsland's closed-notch HUD framework decides priority. ~40 lines.

### Key files

- `DynamicIsland/components/Shelf/Views/ShelfInlineLiveActivity.swift`
- `DynamicIsland/ContentView.swift`

## "open -a Atoll file" and extension RPC adds

### Behaviour

Opening files with Atoll (Finder "Open With", `open -a Atoll file.pdf`, dock drop) adds them to the shelf and switches the notch's current tab to Shelf (the notch does not auto-open). Third-party extensions can add files/text, list items, fetch item data, share items and subscribe to change events.

### Layout

n/a

### Animations

n/a

### State and timing

Asynchronous add on the main actor; no notch open.

### Data sources and APIs

DynamicIslandApp.swift:169-188: `application(_:open urls:)` and `application(_:openFile:)` → `handleIncomingShelfURLs` filters `isFileURL`, `await ShelfDropService.items(from: fileURLs)` (ShelfDropService.swift:40-58: standardize, require existence), `ShelfStateViewModel.shared.add(items)`, `coordinator.currentView = .shelf`; returns true if any file URL. RPC (services/Extensions/ExtensionRPCService.swift:100-116): methods `atoll.getShelfItems`, `atoll.getShelfItemData`, `atoll.shareShelfItems`, `atoll.addFilesToShelf`, `atoll.subscribeShelfEvents`; server pushes `atoll.shelfItemsDidChange {action: "added"|"removed", itemIDs}` (ExtensionRPCServer.swift:233-247). Info.plist (REA plist.json) declares `UTImportedTypeDeclarations: [{}]` and no CFBundleDocumentTypes, so Finder "Open With" availability relies on LaunchServices defaults (unknown).

### Settings

None.

### Dependencies

None.

### Implementation notes

Implement `application(_:open:)` in NotchIsland's AppDelegate; optionally add CFBundleDocumentTypes for public.item to appear in Open With. ~30 lines.

### Key files

- `DynamicIsland/DynamicIslandApp.swift`
- `DynamicIsland/components/Shelf/Services/ShelfDropService.swift`
- `DynamicIsland/services/Extensions/ExtensionRPCServer.swift`

## Shelf settings and permissions

### Behaviour

Settings ▸ Shelf (icon books.vertical, brown): Permissions callouts ("Additional folder access required" — enable Full Disk Access or grant Documents+Downloads; "Full Disk Access for global mode"); General: Enable shelf (disabled until permission), Open shelf tab by default if items added, Expanded drag detection area, Copy items on drag, Allow moving files when dragging out, Remove from shelf after dragging; Quick Share: service picker with icons + "Currently selected: X / Files dropped on the shelf will be shared via this service" + footer; LocalSend section when selected.

### Layout

SettingsView.swift:4415-4563 (Form with Sections). Permission callouts use SettingsPermissionCallout with icons folder.badge.questionmark (orange) and externaldrive.fill (purple).

### Animations

n/a

### State and timing

Permission stores refresh on appear and poll after a request.

### Data sources and APIs

FullDiskAccessPermissionStore probes readability of ~/Library/Application Support/com.apple.TCC/TCC.db or ~/Library/DoNotDisturb/DB/ModeConfigurations.json (helpers/FullDiskAccessPermissionStore.swift:24-45); ShelfFolderAccessAuthorization lists Documents and Downloads (`contentsOfDirectory`) to trigger/verify TCC folder prompts (57-98); opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`. Info.plist usage strings (REA plist.json): NSDocumentsFolderUsageDescription "Atoll needs access to save and read shelf dragged files.", NSDownloadsFolderUsageDescription "Atoll needs access to read files in the downloads folder.". App is unsandboxed (signature.json entitlements: apple-events, disable-library-validation, camera, mach-services, calendars, location; no app-sandbox).

### Settings

dynamicShelf=true, openShelfByDefault=true, quickShareProvider="AirDrop", localSendSelectedDeviceID="", localSendDevicePickerGlassMode=.standard, localSendDevicePickerLiquidGlassVariant=.v11, copyOnDrag=false, allowMoveOnDrag=false, autoRemoveShelfItems=false, expandedDragDetection=true (unused) — models/Constants.swift:1214-1227.

### Dependencies

Defaults (sindresorhus, MIT) in Atoll; not required.

### Implementation notes

Map to NotchIsland UserSettings keys with identical defaults. Permission probing is optional for an unsandboxed app but explains why drops may fail on Documents/Downloads without TCC consent.

### Key files

- `DynamicIsland/components/Settings/SettingsView.swift`
- `DynamicIsland/models/Constants.swift`
- `DynamicIsland/helpers/FullDiskAccessPermissionStore.swift`

## Clipboard monitoring, classification and persistence (ClipboardManager)

### Behaviour

While enabled, every copy is captured into a history list (newest first) capped at the configured size (default 3). Items are typed Text / URL / File / Image / Rich Text with a one-line preview (first 50 chars, file name, "N files", "Image (123 KB)"). Re-copying an existing item moves it to the top. Items can be pinned to a separate Favorites list (unaffected by the size cap), unpinned (returns to top of history), deleted, or the whole list cleared. Clicking an item copies it back (RTF with plain-text fallback, PNG for images, file URLs for files). With "Save History Across Restarts" off, nothing is written to disk (images stay in memory), and turning it off erases saved history and unpinned image files; pinned items are always persisted.

### Layout

n/a (data layer)

### Animations

n/a

### State and timing

Monitoring starts lazily: header button onAppear, NotchClipboardView onAppear, settings toggle, or the shortcut handler (DynamicIslandHeader.swift:170-174; NotchClipboardView.swift:106-110; SettingsView.swift:8481-8487; DynamicIslandApp.swift:1409-1411). `lastCopiedItemDate` drives `focusClipboardTabIfNeeded` (DynamicIslandViewModel.swift:124-131): in separateTab mode, opening the notch within 10 s (`clipboardFocusWindow`, :86) of a copy switches to the Notes/Clipboard tab with `.smooth`. `isDraggingItem` + 8 s safety reset (`dragSafetyResetTimeout`, 397-405). Pin (483-508) removes from history, appends to pinned (persisting an in-memory image to a file); unpin (525-550) inserts at history index 0 then trims. Tests (ClipboardHistoryPersistenceTests.swift:105-331) pin down the privacy behaviours.

### Data sources and APIs

ClipboardManager.swift: polling `Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true)` comparing `NSPasteboard.general.changeCount` (374-381, 562-574). Classification `getCurrentClipboardItem` (576-674): (1) `canReadObject(forClasses: [NSURL.self])` → real file URLs filtered (isFileURL, not "/.file/id=", not "/tmp/", not "/private/var/" prefix, not "/ClipboardViewer", exists); if any has extension in [jpg,jpeg,png,gif,bmp,tiff,tif,webp,heic,heif] → `ClipboardItem(imageData:)` of the FIRST image file; else `.file` with absoluteStrings; (2) image data (.png, .tiff, "public.jpeg") without file URLs → image (PNG preferred); (3) plain string starting with http:// or https:// and NO rich text → .url; (4) rich text: `.rtf` data, or `.html` → NSAttributedString(html) → RTF data (805-824) → `.rtf` with plainText; RTF > 100000 bytes is dropped to nil (130); (5) non-empty string → .text; (6) image+fileURLs → nil (document thumbnail); (7) `.URL` pasteboard type → .url. Dedup `isSameContent` (719-735). addToHistory on main (676-716): remove same-content, insert at 0, set `lastCopiedItemDate`, trim to `Defaults[.clipboardHistorySize]` deleting evicted image files, save. copyToClipboard (407-438): text/url/unknown → setString(.string); image → setData(.png); file → writeObjects(URLs); rtf → setData(.rtf) + setString fallback. Item model (27-174): `{id, type, timestamp, preview, isPinned, stringData?, imageFileName?, fileURLs?: [String], rtfData?}`; images saved as `clipboard_image_<UUID>.png` in `~/Documents/ClipboardData` (96-100, 248-256) or kept in `ClipboardItem.inMemoryImages` when persistence is off (40-59, 86-93). Persistence: `UserDefaults.standard` keys "ClipboardHistory" and "ClipboardPinnedItems" (JSON-encoded arrays) (756-796); `purgeStoredHistoryIfPersistenceDisabled()` at launch (330-338); `cleanupOldFiles()` deletes unreferenced PNGs on init (738-752); Defaults.publisher on persistClipboardHistory handles on/off transitions (269-287). Types icons/names (176-205): text doc.text "Text", url link "URL", file doc "File", image photo "Image", rtf doc.richtext "Rich Text", unknown questionmark.circle. REA macho.json confirms `_NSPasteboardTypePNG/TIFF/RTF/String/URL/FileURL` imports and class `_TtC5Atoll16ClipboardManager`.

### Settings

enableClipboardManager (Bool, true) Constants.swift:1359; clipboardHistorySize (Int, 3; UI offers 3/5/7/10) :1360, SettingsView.swift:8532-8537; persistClipboardHistory (Bool, true) :1364; showClipboardIcon (Bool, true) :1365; clipboardDisplayMode (.panel) :1366; shortcut `clipboardHistoryPanel` default Cmd+Shift+V (Shortcuts/ShortcutConstants.swift:27; migrated from Cmd+Shift+C, Constants.swift:1574-1582).

### Dependencies

Defaults (MIT) in Atoll only.

### Implementation notes

NotchIsland already has a clipboard foundation; align the classification order and dedup semantics above, store image bytes outside UserDefaults, and honour a persistence switch. ~500 lines.

### Key files

- `DynamicIsland/managers/ClipboardManager.swift`
- `DynamicIslandTests/ClipboardHistoryPersistenceTests.swift`

## Clipboard entry points and display modes

### Behaviour

A "list.clipboard" capsule button in the open-notch header (when Show Clipboard Icon is on and mode ≠ Separate Tab) toggles the clipboard UI according to Display Mode: Panel → floating panel; Popover → popover under the button; Notch Tab → switches the notch to the Clipboard tab (second press returns Home). Separate Tab mode hides the header button and merges the clipboard into the Notes tab (tab label "Clipboard"/icon doc.on.clipboard when Notes is off, or "Notes"/note.text). Cmd+Shift+V does the same from anywhere (opening the notch first for popover/separateTab/notchTab).

### Layout

DynamicIslandHeader.swift:133-176: `Button { … } label: { Capsule().fill(.black).frame(width: 30, height: 30).overlay { headerGlyph("list.clipboard") } }.buttonStyle(.plain).popover(isPresented: $showClipboardPopover, arrowEdge: .bottom) { ClipboardPopover() }`. Tab (TabSelectionView.swift:90-93). Notes split (NotchNotesView.swift:46-57): `HStack(spacing: 0) { NotchClipboardView(fixedColumns: 2).frame(maxWidth: .infinity); Divider().background(Color.white.opacity(0.15)) if Notes enabled; notes… }`. Tab count for min notch width includes the Notes/Clipboard tab (sizing/matters.swift:125-127).

### Animations

Header controls fade/blur with notch state: `.opacity(closed ? 0 : 1).blur(radius: closed ? 20 : 0).animation(.smooth.delay(0.1), value: vm.notchState)` (DynamicIslandHeader.swift:368-370).

### State and timing

Notch open size for .notes/.clipboard uses `coordinator.notesLayoutState.preferredHeight` (DynamicIslandViewModel.swift:424-428). ClipboardPanelManager (managers/ClipboardPanelManager.swift:24-55): show closes any existing panel, creates a new ClipboardPanel, `positionNearNotch()`, `makeKeyAndOrderFront` + `orderFrontRegardless`, `NSApp.activate(ignoringOtherApps: true)`, `makeKey()` again after 0.1 s; toggle hides if visible.

### Data sources and APIs

ClipboardDisplayMode enum (Constants.swift:308-331): popover, panel, separateTab, notchTab with display names and descriptions. Shortcut handler (DynamicIslandApp.swift:1405-1432): panel → `ClipboardPanelManager.shared.toggleClipboardPanel()`; popover → open notch then post `Notification("ToggleClipboardPopover")` after 0.3 s (immediately if open); separateTab → open + `currentView = .notes` or toggle; notchTab → analogous with `.clipboard` (coordinator.shouldToggleClipboardPopover handler DynamicIslandHeader.swift:376-399 also cancels `AppDelegate.cancelPendingNotchAutoClose()` for notchTab). Popover state mirrors to `vm.isClipboardPopoverActive` and triggers `shouldRecheckHover` 0.1 s after closing (DynamicIslandHeader.swift:155-166).

### Settings

clipboardDisplayMode default .panel; showClipboardIcon default true.

### Dependencies

KeyboardShortcuts (sindresorhus, MIT) for the global hotkey in Atoll.

### Implementation notes

NotchIsland can expose the same four modes; the Notch Tab mode is the most 'Dynamic Island'-like and only needs the card grid. ~100 lines of wiring.

### Key files

- `DynamicIsland/components/Notch/DynamicIslandHeader.swift`
- `DynamicIsland/DynamicIslandApp.swift`
- `DynamicIsland/components/Notch/NotchNotesView.swift`
- `DynamicIsland/components/Tabs/TabSelectionView.swift`
- `DynamicIsland/models/Constants.swift`

## Clipboard floating panel (ClipboardPanel / ClipboardPanelView)

### Behaviour

A 380x480 frosted HUD panel with a search field (focused, with clear button), a close button, a sliding History/Favorites segmented control with counts, a trash button (red on hover, disabled when empty), and a list of rows: 34pt type badge (tinted icon, or image thumbnail), 2-line preview, "Type · time ago" meta line, and hover-revealed pin/copy/delete buttons (pin stays visible on pinned rows). Clicking a row copies it and flashes a green checkmark for 1.5 s. The panel floats above all spaces and full-screen apps, is draggable anywhere, remembers its position, and defaults to screen center.

### Layout

ClipboardPanel.swift:183-188 metrics: panelSize 380x480, cornerRadius 18, rowCornerRadius 12, contentInset 12. NSPanel (34-79): `[.borderless, .nonactivatingPanel]` + `.fullSizeContentView`, canBecomeKey/Main true, backgroundColor .clear, isOpaque false, hasShadow, `level = .floating`, isMovableByWindowBackground, isFloatingPanel, collectionBehavior `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`, acceptsMouseMovedEvents; hosting view layer mask radius 18 continuous (22-30, 87). Body (225-278): `VStack(spacing: 10) { header; empty state | ScrollView(.vertical, showsIndicators: false) { LazyVStack(spacing: 4) { rows }.padding(.horizontal, 12).padding(.bottom, 12) }.scrollBounceBehavior(.basedOnSize) }.frame(380x480).background { VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).overlay(LinearGradient([white@0.07, clear], top→bottom)) }.clipShape(RoundedRectangle(18, continuous)).overlay(RoundedRectangle(18).strokeBorder(white@0.12, 1)).shadow(color: .black.opacity(0.4), radius: 26, x: 0, y: 12)`. Header (294-371) padding h12 top12, `VStack(spacing: 10)`: search row `HStack(spacing: 8) { HStack(spacing: 7) { magnifyingglass 12 semibold secondary; TextField("Search clipboard") .plain 12.5pt; xmark.circle.fill 11 when text } .padding(.horizontal, 9).frame(height: 28).background(RoundedRectangle(9, continuous).fill(Color.primary.opacity(focused ? 0.12 : hovered ? 0.09 : 0.07))).overlay(strokeBorder(accent.opacity(focused ? 0.65 : 0), 1.5)); NativeStyleCloseButton }`; tabs row `HStack(spacing: 8) { ClipboardSegmentedTabs; Spacer; trash 11.5 medium in 26x24, bg RoundedRectangle(7) primary@0.1 on hover, red when hovered & canClear, opacity 0.35 disabled }`. Segmented (376-433): `HStack(spacing: 2)` buttons `HStack(spacing: 5) { icon 10 semibold; label 11.5 medium; count 9.5 semibold monospaced (primary@0.55 selected / secondary@0.7) }.foregroundStyle(selected ? .primary : .secondary).padding(.horizontal, 10).frame(height: 24).background(selected ? RoundedRectangle(7, continuous).fill(primary@0.14).matchedGeometryEffect : nil)`, container `.padding(2).background(RoundedRectangle(9, continuous).fill(primary@0.06))`. Empty state (435-480): `Circle primary@0.06 56x56` with icon 22 light secondary (magnifyingglass / doc.on.clipboard / heart), title 13 semibold, subtitle 11.5 secondary padding top 3, bottom padding 24; strings "No results"/"Try a different search term", "No clipboard history"/"Copy something to get started", "No favorites"/"Pin items to keep them here". Row (496-542): `HStack(alignment: .center, spacing: 10) { badge; VStack(alignment: .leading, spacing: 2) { preview 12.5 primary lineLimit 2; HStack(spacing: 5) { type name tint@0.95; "·" tertiary; timeAgo secondary }.font(10.5 medium) }; Spacer(minLength: 4); actions }.padding(.horizontal, 10).padding(.vertical, 9).background(RoundedRectangle(12, continuous).fill(primary.opacity(hover ? 0.08 : 0.03))).overlay(strokeBorder(primary.opacity(hover ? 0.08 : 0), 1))`. Badge (545-566): 34x34 `RoundedRectangle(9, continuous)` clip; image thumbnail `.fill`, or `tint.opacity(0.18)` + icon 13 semibold tint (checkmark green when justCopied); strokeBorder primary@0.08. Actions (568-606): `HStack(spacing: 2)` of 24x24 buttons (icon 11 medium, bg RoundedRectangle(7) primary@0.12 on hover) pin/pin.fill (accent when pinned), doc.on.doc/checkmark (green), trash (red hover tint); `.frame(width: 78, alignment: .trailing)`. Tints (192-202): text (0.55,0.58,0.64), url (0.35,0.56,0.92), file (0.92,0.66,0.30), image (0.66,0.48,0.90), rtf (0.36,0.72,0.62), unknown = text.

### Animations

List count changes `.animation(.easeOut(duration: 0.18), value: filteredItems.count)` (277). Search focus/clear `.easeOut(0.16)` (332-333); clear-button transition `.opacity.combined(with: .scale(scale: 0.7))` (318). Tab switch `withAnimation(.spring(response: 0.32, dampingFraction: 0.82))` with matchedGeometryEffect (394). Row hover `withAnimation(.easeOut(duration: 0.16))` (535). Copy feedback `withAnimation(.easeOut(duration: 0.18))` set, reset after 1.5 s via cancelable DispatchWorkItem (608-626); icon swaps use `.contentTransition(.symbolEffect(.replace))` (557, 665). Action button hover `.easeOut(0.14)` (669). Trash hover `.easeOut(0.16)` (365).

### State and timing

Tabs: `ClipboardTab` history("clock")/favorites("heart.fill") (ClipboardShared.swift). History tab shows `regularHistory` (unpinned), Favorites shows `pinnedItems`. Delete on a pinned row unpins instead of deleting (596-602). Close button calls `panel.close()` (82-84).

### Data sources and APIs

AppKit NSPanel + NSHostingView; `NSVisualEffectView` material `.hudWindow`, `.behindWindow`, state active, isEmphasized (components/Settings/EditPanelView.swift:52-69). Position persistence: UserDefaults doubles "clipboardPanelPositionX"/"clipboardPanelPositionY" written in `setFrameOrigin` override (138-161); restore if fully inside `NSScreen.main.visibleFrame`, else clamp inside if intersecting, else center (96-125). `positionNearMouse` (163-179) exists but is unused. Registered with ScreenCaptureVisibilityManager (scope .panelsOnly) so it can be hidden from screen capture (75). Search filters on preview or type displayName, case-insensitive (212-223). Time strings: "Just now", "Nm ago", "Nh ago", "Nd ago" (628-643). REA dispatch.json confirms classes `_TtC5Atoll14ClipboardPanel`, `_TtC5Atoll21ClipboardPanelManager`.

### Settings

None beyond display mode.

### Dependencies

None.

### Implementation notes

Build as an NSPanel subclass hosting SwiftUI; replicate metrics above. ~500 lines.

### Key files

- `DynamicIsland/components/Clipboard/ClipboardPanel.swift`
- `DynamicIsland/managers/ClipboardPanelManager.swift`
- `DynamicIsland/components/Clipboard/ClipboardShared.swift`

## Clipboard popover (ClipboardPopover)

### Behaviour

A compact 280x320 popover anchored below the header clipboard button: title row with clipboard icon, "Clipboard", red trash; blue-pill History/Favorites tab buttons with count capsules; a search box; a list of rows with a blue type icon, 2-line preview, type and short time ("now", "5m", "2h", "3d"), and on hover heart/copy/trash buttons. Tap copies.

### Layout

ClipboardPopover.swift:41-81: `VStack(spacing: 0) { header; Divider().background(gray@0.3); empty | ScrollView { LazyVStack(spacing: 1) { rows }.padding(.vertical, 8) } }.frame(width: 280, height: 320).background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial).shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4))`. Header (90-165): `VStack(spacing: 8)`: title `HStack { doc.on.clipboard 14 medium primary; "Clipboard" 13 semibold; Spacer; trash red 11 (disabled when empty) }.padding(.horizontal, 14).padding(.top, 10)`; tabs `HStack(spacing: 0) { ClipboardTabButton… ; Spacer }.padding(.horizontal, 14)`; search `HStack { magnifyingglass 11 secondary; TextField("Search...") 11pt plain; xmark.circle.fill 9 }.padding(.horizontal, 10).padding(.vertical, 5).background(RoundedRectangle(5).fill(gray@0.1)).padding(.horizontal, 14)`; `.padding(.bottom, 6)`. ClipboardTabButton (ClipboardShared.swift): `HStack(spacing: 6) { icon 11; label 11 medium; count 9 bold in Capsule (white@0.3 selected / gray@0.2) padding h4 v1 }.foregroundColor(selected ? .white : .secondary).padding(.horizontal, 12).padding(.vertical, 6).background(RoundedRectangle(6).fill(selected ? Color.blue : .clear))`. Empty (172-198): icon 24 secondary (magnifyingglass / doc.on.clipboard / heart.fill), title 12 medium, subtitle 10 secondary ("Try different search terms", "Copy something to start", "Pin items to add favorites"), padding 20. Row (208-296): `HStack(alignment: .top, spacing: 10) { type icon 12 blue frame(width: 16); VStack(alignment: .leading, spacing: 3) { preview 11 primary lineLimit 2; HStack { type 9 secondary; Spacer; time 9 secondary } }; Spacer; hover HStack(spacing: 4) { heart/heart.fill 9 (red pinned/gray); doc.on.doc 9 green; trash 9 red } }.padding(.horizontal, 14).padding(.vertical, 6).background(RoundedRectangle(4).fill(hover ? gray@0.1 : .clear))`.

### Animations

Tab switch `withAnimation(.easeInOut(duration: 0.2))` (126); row hover `withAnimation(.easeInOut(duration: 0.15))` (289).

### State and timing

Popover open state sets `vm.isClipboardPopoverActive` (counts as an active popover → prevents auto-close); closing triggers hover recheck after 0.1 s.

### Data sources and APIs

SwiftUI `.popover(isPresented:arrowEdge: .bottom)` from the header button (DynamicIslandHeader.swift:153-155). Same ClipboardManager data/actions.

### Settings

clipboardDisplayMode == .popover.

### Dependencies

None.

### Implementation notes

Low priority; the Panel and Notch Tab are the richer modes. ~250 lines.

### Key files

- `DynamicIsland/components/Clipboard/ClipboardPopover.swift`
- `DynamicIsland/components/Clipboard/ClipboardShared.swift`
- `DynamicIsland/components/Notch/DynamicIslandHeader.swift`

## Clipboard card grid in the notch (NotchClipboardView, notchTab and separateTab)

### Behaviour

Inside the open notch, a "Clipboard" header (with a red trash-in-circle that asks "Clear Clipboard History?" via an alert) above an adaptive grid of compact cards: 28pt image thumbnail or blue type icon, one-line preview, type and short age. Hover brightens a card and reveals an xmark.circle.fill delete at its top-right; click copies (icon turns into a green checkmark for 1.5 s; image cards get a dark overlay with a green check); cards can be dragged out to Finder/other apps (text, URL, RTF with plain fallback, PNG for images, single files; multi-file entries are not draggable). In the Notes split the same grid is forced to 2 columns. Scrolling inside suppresses the notch's scroll gestures.

### Layout

NotchClipboardView.swift:39-49: `minCardWidth = 200`, `fixedColumns: Int? = nil`; columns = `[GridItem(.adaptive(minimum: 200, maximum: .infinity), spacing: 8)]` or N × `.flexible()` spacing 8. Body (51-111): `VStack(spacing: 0) { header; emptyState | ScrollView { LazyVGrid(columns:, spacing: 8) { cards }.padding(.horizontal, 20).padding(.bottom, 20) } }.frame(maxWidth: .infinity, maxHeight: .infinity)`. Header (113-135): `HStack { Text("Clipboard").font(.system(size: 16, weight: .semibold, design: .rounded)).white; Spacer; trash 14 red .frame(16x16).padding(5).background(white@0.1).clipShape(Circle()) }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)`. Empty (137-151): doc.on.clipboard 32 secondary@0.3, "No copies yet" .headline secondary, "Copy something to see it here" .caption secondary@0.7, padding vertical 30. Card (184-233): `HStack(spacing: 10) { thumbnail; VStack(alignment: .leading, spacing: 2) { preview 13 white lineLimit 1; HStack(spacing: 6) { type 10 secondary; Spacer(minLength: 0); time 10 secondary } } }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(12).fill(Color.white.opacity(hover ? 0.12 : 0.08)).overlay(RoundedRectangle(12).stroke(Color.blue.opacity(0.2), lineWidth: 1))).clipShape(RoundedRectangle(12)).overlay(alignment: .topTrailing) { xmark.circle.fill 14 .foregroundStyle(.white, .black.opacity(0.5)).padding(4) }`. Thumbnail (237-262): image `28x28 .fill clipShape(RoundedRectangle(6)) overlay stroke white@0.1 0.5pt` + justCopied overlay `RoundedRectangle(6).fill(.black.opacity(0.5))` + `checkmark.circle.fill 14 green`; else icon 16 (`checkmark.circle.fill` green when copied, else type icon blue) in 28x28 `white@0.06` r6. Time (265-270): "Just now", "Nm", "Nh".

### Animations

Card hover `.animation(.easeInOut(duration: 0.12), value: isHovered)` (228); delete button `.transition(.scale.combined(with: .opacity))` (225); copy feedback `withAnimation { justCopiedId = id }` (default animation) reset after 1.5 s if unchanged (153-161).

### State and timing

Shows `clipboardManager.clipboardHistory` only (pinned items are not shown in this mode). `ClipboardManager.isDraggingItem` keeps the notch open during the drag and auto-resets after 8 s (no drag-end callback with SwiftUI `.onDrag`). Hover id is cleared only if it still refers to this card (69-75) to avoid flicker between adjacent cards. onAppear starts monitoring when enabled (106-110).

### Data sources and APIs

Drag-out via `clipboardDraggable(item)` (ClipboardDragging.swift, offsets +21 → file lines 91-107): `.onDrag { ClipboardManager.shared.markDragStart(); return item.dragItemProvider() }`; providers (39-75): rtf → `NSItemProvider` with `registerDataRepresentation(UTType.rtf)` then `UTType.utf8PlainText`; text/url/unknown → `NSItemProvider(object: NSString)`; image → PNG copied to `FileManager.temporaryDirectory/<fileName>` then `NSItemProvider(contentsOf:)` (so eviction mid-drag cannot break the drop); file → `NSItemProvider(contentsOf: firstURL)`; fallback → preview NSString. `isMultiFile` (fileURLs.count > 1) disables dragging. Image decode cached per item with `.task(id: item.id)` (229-233). Hover suppresses notch scroll gestures via `vm.setScrollGestureSuppression(hovering, token:)` (163-167). Clear alert holds the notch open via `vm.setAutoCloseSuppression` (103-105). Accessibility: combined element, label "<Type>: <preview>", button trait, default action copy, named action "Delete" (77-81).

### Settings

clipboardDisplayMode == .notchTab or .separateTab (with enableNotes deciding the split).

### Dependencies

None.

### Implementation notes

Good fit for NotchIsland's existing shelf-in-notch concept; reuse the card metrics. If a true drag-end is needed, use an NSDraggingSource overlay like the shelf. ~300 lines.

### Key files

- `DynamicIsland/components/Notch/NotchClipboardView.swift`
- `DynamicIsland/components/Clipboard/ClipboardDragging.swift`
- `DynamicIsland/components/Notch/NotchNotesView.swift`

## Legacy / unreferenced clipboard and tray code (for completeness)

### Behaviour

Not reachable from the shipped UI, but compiled into the binary (REA dispatch.json lists `_TtC5Atoll22ClipboardWindowManager`, `_TtC5Atoll8TrayDrop`, `_TtC5Atoll7AirDrop`).

### Layout

ClipboardWindow.swift:27-42: 400x300 `VisualEffectView(.hudWindow, .behindWindow)`, cornerRadius 12, shadow black@0.4 r20 y10; header title "Clipboard Manager" (doc.on.clipboard 16 medium, 14 semibold), tabs, search ("Search clipboard..." 12pt, gray@0.1 r6); rows icon 14 blue width 20, preview 12, meta 10, hover gray@0.1 r6, `.easeInOut(0.2)`. ClipboardWindowManager.swift: titled/closable/resizable NSWindow, `level = .screenSaver`, collectionBehavior canJoinAllSpaces+fullScreenAuxiliary, minSize 350x250, maxSize 600x500, centered on `NSScreen.main.frame`, windowShouldClose hides (orderOut) instead of closing. ClipboardHistoryPopover.swift:62-82: width 280, maxHeight 200, black@0.95, r12, stroke gray@0.2, shadow black@0.3 r10 y5; auto-dismisses 0.1 s after the mouse leaves and closes the notch if no battery popover; list maxHeight 150. TrayDrop/DropItem (boring.notch): copies dropped files into `~/Documents/CopiedItems/<uuid>/<name>` with a 128x128 `QLThumbnailImageCreate` PNG preview; DropItemView 64x64 tile r6 footnote label with option-key x button; AirDropView: `Rectangle().fill(.white.opacity(0.1)).opacity(0.5)` r10, "airplayaudio" + "AirDrop" headline rounded gray, `.onDrop(of: [.data])` then AirDrop 0.5 s later; DragDropView: NSView registering `.fileURL`. Ext+FileProvider duplicates dropped items into Caches/TemporaryDrop/<uuid>/ using semaphores (deadlock-prone; unused).

### Animations

n/a

### State and timing

Only live reference: DynamicIslandViewCoordinator.swift:138 reads `TrayDrop.shared.isEmpty` (always true) — a latent bug, not behaviour to copy.

### Data sources and APIs

See layout. `OrderedCollections.OrderedSet` (swift-collections) used only by TrayDrop.

### Settings

n/a

### Dependencies

swift-collections (Apache-2.0) for OrderedSet in TrayDrop only.

### Implementation notes

Do not port.

### Key files

- `DynamicIsland/components/Clipboard/ClipboardWindow.swift`
- `DynamicIsland/managers/ClipboardWindowManager.swift`
- `DynamicIsland/components/Notch/ClipboardHistoryPopover.swift`
- `DynamicIsland/components/Shelf/TrayDrop.swift`
- `DynamicIsland/components/Shelf/DropItem.swift`
- `DynamicIsland/components/Shelf/DropItemView.swift`
- `DynamicIsland/components/Shelf/AirDropView.swift`
- `DynamicIsland/components/Shelf/DragDropView.swift`
- `DynamicIsland/components/Shelf/Ext+FileProvider.swift`

## Unknowns

- expandedDragDetection (Defaults key, default true, Settings toggle 'Expanded drag detection area') has no consumer in the 2.3.3 source — the drop detector is always the full notch window frame. Whether an older build enlarged the frame is unknown.
- Exact resolution of `Color.accentColor` inside the notch (Atoll has an `.effectiveAccent` custom accent used in Settings; the shelf/clipboard views use plain `Color.accentColor`, which follows the system accent unless the hosting window overrides it) — not verified at runtime.
- `vm.closedNotchSize` / `effectiveClosedNotchHeight` numeric values used by ShelfInlineLiveActivity and LocalSendLiveActivity live in the notch-geometry subsystem (sizing/matters.swift getClosedNotchSize) and were not re-derived here.
- Finder 'Open With → Atoll' availability: Info.plist (REA plist.json) has no CFBundleDocumentTypes and an empty UTImportedTypeDeclarations entry, so whether `open -a Atoll file` works for all types is inferred from the application:open handler, not verified.
- LocalSend TLS trust details (LocalSendTLSDelegate accepting self-signed certs), the exact JSON of prepare-upload bodies, and v3 register handling were skimmed, not fully specified (LocalSendService.swift lines 600-1116).
- ScreenCaptureVisibilityManager (hides the clipboard panel from screen capture, scope .panelsOnly) and LiquidGlassBackground/LocalSendGlassBackdrop (macOS 26 glass variants for the device picker) belong to other subsystems and were not specified.
- ClipboardManager thread-safety: the 0.5 s Timer fires on the main run loop and `rtfDataWithFallback` must run on main (WebKit HTML import); behaviour under heavy clipboard churn (e.g. password managers) was not tested.
- ShelfStateViewModel.isLoading is published but never rendered — no loading indicator exists for in-progress drops; any spinner in NotchIsland would be an addition.
- Hover-exit auto-close delay for the open notch (outside this subsystem) interacts with shelf drags only through shouldPreventAutoClose/shouldRecheckHover (0.1 s runAfter); the base hover-close timing itself was not re-specified here.
- Keyboard navigation of shelf items beyond Cmd+A/Delete/Escape (arrow keys) does not exist in Atoll.

## Critic pass

Missing from the spec:

- [Spec truncated] The spec text ends mid-sentence inside the 'Closed-notch shelf HUD' feature ("...returned last in the music secon"); every CLIPBOARD feature entry and any later shelf entries are absent from the delivered text. Everything below under 'CLIPBOARD' therefore has to be confirmed present in the full spec or added. Base path for citations: DI/ = /private/tmp/claude-501/-Users-a-dynamic-iland-dynamic-island/b501c539-18bc-4747-a9c4-d824916ad38f/scratchpad/atoll-clone/Atoll/DynamicIsland/
- [Shelf HUD] Closed-notch shelf HUD priority position: the standalone ShelfInlineLiveActivity is the second-to-last branch of the closed-state else-if chain, after extension standalone payloads and before the idle face animation (DI/ContentView.swift:1153-1172); the LocalSendLiveActivity sits earlier in the same chain with `.transition(.blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)))` and is gated by `localSendLiveActivityActive` = isSending || .completed || failed/rejected (DI/ContentView.swift:1153-1155, 469-479). The secondary `.shelf(count:)` has id "shelf-<count>" (DI/ContentView.swift:3027-3028) so each count change also re-identifies the secondary and runs `.animation(.smooth(duration: 0.25), value: secondary?.id)` (DI/ContentView.swift:1517) on top of the numericText roll.
- [Shelf] Tab bar visibility rule tied to the shelf: DynamicIslandHeader shows TabSelectionView when `coordinator.alwaysShowTabs || vm.notchState == .open || !shelfState.items.isEmpty` (DI/components/Notch/DynamicIslandHeader.swift:90), i.e. a non-empty shelf forces the tab row even with alwaysShowTabs off; tab row fades/blurs with `.opacity(closed ? 0 : 1).blur(radius: closed ? 20 : 0).animation(.smooth.delay(0.1), value: vm.notchState)` and `.padding(8)` (DI/components/Notch/DynamicIslandHeader.swift:96-100).
- [Shelf] Keyboard handling precondition: Escape and Delete/Forward-Delete only work while the marquee NSView is first responder, which it becomes on a mouseDown in empty shelf space (`window?.makeFirstResponder(self)`, DI/components/Shelf/Views/ShelfMarqueeSelectionView.swift:108); Delete also clears the selection afterwards (:161-162). Cmd+A works regardless via performKeyEquivalent (:173-181). The spec should state that keyboard removal requires a prior click on the panel background.
- [Shelf] Marquee gap-coverage mechanics: the ScrollView content is stretched to at least the measured viewport (minWidth/minHeight, `.leading`) so a band can start in the gap right of the last item (DI/components/Shelf/Views/ShelfView.swift:175-190); `ShelfBackgroundClickCatcher` (an NSView whose mouseUp clears selection) covers the ring between the padded content and the panel edge and the whole panel when empty (:129-141). `ShelfItemHitRegistry.unregister` only evicts when the stored view is identical, to survive SwiftUI cell recycling (DI/components/Shelf/Services/ShelfItemHitRegistry.swift:47-55).
- [Shelf] Open With submenu real ordering and content: default app row with attributed ' (default)' suffix, then a separator only when `openWithApps.count > 1 || !openWithApps.contains(defaultApp)`, then the remaining apps in Set order (unsorted), then separator + 'Other…' with representedObject "__OTHER__" (DI/components/Shelf/ViewModels/ShelfItemViewModel.swift:396-432). Choosing an app opens ALL selected openable URLs with `NSWorkspace.shared.open(_:withApplicationAt:configuration:)` (:552-586). NSOpenPanel for Other…: title 'Choose Application', message 'Choose an application to open the document "<name>".', prompt 'Open', allowedContentTypes [.application], directoryURL /Applications, `isAccessoryViewDisclosed = true`, popup switches delegate mode and calls `validateVisibleColumns()` (:736-900).
- [Shelf] Convert Image dialog details not in spec: NSAlert style .informational with buttons 'Convert'/'Cancel' (:1015-1018); format popup items 'PNG','JPEG','HEIC','TIFF','BMP' default PNG; size popup 'Actual Size','Large','Medium','Small','Custom...'; custom field hidden unless index 4; compression row hidden unless JPEG/HEIC; `removeMetadata = checkbox.state == .off`; output `<name>_converted.<png|jpg|heic|tiff|bmp>` (DI/components/Shelf/Services/ImageProcessingService.swift:38-46, 173-174); JPEG via NSBitmapImageRep `.compressionFactor`, TIFF LZW, BMP, HEIC via `CIContext.heifRepresentation(... format: .RGBA8, colorSpace: sRGB, options: [kCGImageDestinationLossyCompressionQuality: quality])` (:184-218); downscale only when the longest side exceeds maxDimension, Lanczos with source colorspace preserved (:220-257). Errors shown with an NSAlert `.warning` 'Image Conversion Failed' / 'Background Removal Failed' / 'PDF Creation Failed' (:1215-1223). Remove Background output `<name>_no_bg.png` (ImageProcessingService.swift:104-105), PDF output `images_<timeIntervalSince1970>.pdf` (:285-286).
- [Shelf] Context menu 'Copy' keeps security-scoped access open on the copied URLs in a static `copiedURLs` array until the next Copy (DI/components/Shelf/ViewModels/ShelfItemViewModel.swift:656-687); 'Share…' for a `.text` item shares only that text, otherwise all selected items (:250-293); the per-view `onQuickLookRequest` closure is wired in ShelfItemView.onAppear (DI/components/Shelf/Views/ShelfItemView.swift:137-139).
- [Shelf] Legacy SwiftUI drag provider still compiled: `dragItemProvider()/createItemProvider/createMultiItemProvider` register `UTType.fileURL` file representations lazily via `resolveAndUpdateBookmarkAsync` and a display-name NSString fallback (DI/components/Shelf/ViewModels/ShelfItemViewModel.swift:148-223). Unused by the live AppKit drag path; spec should mark it dead so NotchIsland does not port it.
- [Shelf] Dead/odd code worth flagging so it is not reproduced: `shouldHideDuringDrag` is hard-wired false (`... && false`, DI/components/Shelf/Views/ShelfItemView.swift:54) and `showStack` is unused (:48); `ThumbnailService.clearCache(...)` is never called (DI/components/Shelf/Services/ThumbnailService.swift:62-68); `QuickLookService.showQuickLook/updateSelection` just re-call `show` (DI/components/Shelf/Services/QuickLookService.swift:95-101); `ShelfStateViewModel.isLoading` is never rendered (DI/components/Shelf/ViewModels/ShelfStateViewModel.swift:37); `ShelfItem.cachedDisplayName/cachedIconData` are never written by the drop path (always nil), so `displayName` returns "" until ShelfItemViewModel loads it (DI/components/Shelf/Models/ShelfItem.swift:88-95).
- [Shelf] Unmentioned file DI/components/Shelf/Services/ShareServiceFinder.swift: `ShareServiceFinder` (NSSharingServicePickerDelegate) shows an NSSharingServicePicker on a zero-size dummy view to capture `proposedSharingServices`, with a 2 s timeout returning []. Compiled into the binary (REA dispatch.json lists `ShareServiceFinder`) but has no callers in 2.3.3 — document as dead.
- [Shelf] Unmentioned helper files: DI/components/Shelf/Ext+NSAlert.swift (`NSAlert.popError(String|Error)` critical alert 'Error'/'OK', `popRestart` 'Need Restart' with 'Exit'/'Later') — used by QuickShareService for LocalSend send failures (DI/components/Shelf/Services/QuickShareService.swift:235) and by legacy AirDrop; DI/components/Shelf/Ext+NSImage.swift (`pngRepresentation`); DI/components/Shelf/Ext+FileProvider.swift (`interfaceConvert()` copies dropped items to `temporaryDirectory/TemporaryDrop/<UUID>/<name>` with semaphore waits and pops 'One or more files failed to load' after 0.5 s) — legacy TrayDrop/AirDropView only; DI/extensions/NSImage+Extensions.swift:41 `fitted(toSide:)` used for 16/20pt provider icons in the Quick Share popover.
- [Shelf] Legacy boring.notch tray not fully described: `TrayDrop` keeps an `OrderedSet<DropItem>` (swift-collections dependency, DI/components/Shelf/TrayDrop.swift:22-27), copies each dropped file into `~/Documents/CopiedItems/<UUID>/<name>` (DI/components/Shelf/DropItem.swift:52-60) and snapshots a 128x128 `QLThumbnailImageCreate` preview PNG (DI/components/Shelf/Ext+URL.swift:24-33); `DropItemView` is a 64x64 cell with footnote name and an x badge scaled by `coordinator.optionKeyPressed` (DI/components/Shelf/DropItemView.swift:30-77); `DragDropView` is an NSView registering `.fileURL` drags (DI/components/Shelf/DragDropView.swift:22-49); `AirDropView` is the old 'airplayaudio' AirDrop tile (DI/components/Shelf/AirDropView.swift:24-177). Only `TrayDrop.shared.isEmpty` is still referenced (DI/DynamicIslandViewCoordinator.swift:138) — always empty.
- [Shelf] application:open urls path details: only `isFileURL` URLs are accepted, non-existent files are skipped with a log (DI/components/Shelf/Services/ShelfDropService.swift:41-58), items are added then `coordinator.currentView = .shelf` WITHOUT opening the notch (DI/DynamicIslandApp.swift:169-189) — the notch is not opened by `open -a Atoll file`.
- [Shelf] Shelf settings UI mechanics: `ShelfFolderAccessPermissionStore` probes Documents/Downloads readability with `FileManager.contentsOfDirectory(... .skipsHiddenFiles)` (DI/helpers/FullDiskAccessPermissionStore.swift:56-100), `requestAccessPrompt()` triggers TCC prompts by listing both folders then polls 40x every 0.5 s (:200-245), `openSystemSettings()` opens `x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders` (:207-220). Two `SettingsPermissionCallout`s ('Additional folder access required' folder.badge.questionmark orange; 'Full Disk Access for global mode' externaldrive.fill purple) and `Enable shelf` disabled when neither FDA nor Docs+Downloads (DI/components/Settings/SettingsView.swift:4446-4483). Quick Share section shows 'Currently selected: X' / 'Files dropped on the shelf will be shared via this service' and footer text (:4515-4550); LocalSend section 'Device Picker Style' + 'Liquid Glass Variant' (Variant 0-19) only when glassMode == .customLiquid (:4567-4600); settings search entries (:352-359); Shelf tab icon 'books.vertical' colour .brown (:132,158).
- [Shelf] Extension RPC surface over the shelf (spec only says 'notifies RPC subscribers'): methods `atoll.getShelfItems` (id,name,kind,path,...), `atoll.getShelfItemData`, `atoll.shareShelfItems` (provider param default "AirDrop", resolves via QuickShareService), `atoll.addFilesToShelf` (paths and/or text), `atoll.subscribeShelfEvents`, plus a file-picker RPC that adds picked files (DI/services/Extensions/ExtensionRPCService.swift:100-116, 382-607); notification `atoll.shelfItemsDidChange` {action: "added"|"removed", itemIDs} (DI/services/Extensions/ExtensionRPCServer.swift:233-247), fired from ShelfStateViewModel.add/remove (DI/components/Shelf/ViewModels/ShelfStateViewModel.swift:129,137). Only 'added'/'removed' — rename/bookmark refresh do not notify.
- [Shelf] Quick Share tile has a stray un-sized `Image(systemName: "square.and.arrow.up")` drawn in the ZStack beneath the 34x34 provider icon (DI/components/Shelf/Views/FileShareView.swift:101) — a visible leftover glyph that the spec's layout tree omits; decide whether to reproduce.
- [Shelf] QuickShareService details: discovery runs in `Task.detached(priority: .userInitiated)` with per-service `autoreleasepool`, dedups providers by (title,image,supportsRawText) equality, and `defaultProvider` falls back to AirDrop → first → 'System Share Menu' (DI/components/Shelf/Services/QuickShareService.swift:63-153, 319-326). `showFilePicker` sets `isPickerOpen` + `SharingStateManager.beginInteraction()` and presents as a sheet on the host window else `runModal()` (:177-215). `shareDroppedFiles` tries `extractURL()` first (so Finder file URLs are appended as URLs), `extractText()` once, then `extractItem()` with shelf bookmark resolution; text is shared raw if `supportsRawText`, else via a temp .txt that is deleted right after (:275-305).
- [LocalSend] Unspecified protocol/discovery details: `refreshDeviceScan()` runs an announce burst at +0.1 s, +0.5 s, +2.0 s, then `probeNearbyDevicesDirectly(limit: 20, timeout: 0.14)`, then a legacy subnet sweep only if nothing fresh was found, then prunes devices not seen since the scan started (DI/components/Shelf/Services/LocalSendService.swift:137-185); neighbour candidates come from `/usr/sbin/arp -an` parsed with a regex and filtered to the own /24 (:390-440) plus a ±radius host sweep (:443-455); own IPv4 via `getifaddrs/getnameinfo` (:457-495); recentProbeIPs capped at 12, knownPeerIPs at 48 (:370-386). Announcement JSON also carries deviceType "desktop", protocol "http", download false, announcement/announce true (:600-614). Register listener is an `NWListener` TCP on 53317 answering POST /api/localsend/v2|v3/register and GET /api/localsend/v2/info with hand-built HTTP/1.1 responses (:620-756). `refreshDevices()` sorts by alias and auto-selects the first device when the selected one disappears (:822-826). Transfer files: text → "text.txt" text/plain, link → "link.url" text/uri-list, svg → application/octet-stream (:835-876); prepare-upload payload includes token "atoll.localsend.bridge" and download false (:887-898); http↔https scheme fallback via `candidateBaseURLs`/`shouldRetryAcrossSchemes` on timeout/connection errors (:1024-1050); `probeSession` ephemeral with 0.2 s timeouts (:362-367).
- [LocalSend] Device picker view details beyond the spec: `onAppear` calls startDiscovery + refreshDeviceScan (DI/managers/LocalSendDevicePickerWindowManager.swift:229-232); `LocalSendGlassBackdrop` uses macOS 26 `.glassEffect(.clear.interactive(), in: .rect(cornerRadius: 24))` on an invisible text when glassMode == .standard on macOS 26, else `.ultraThinMaterial` over black@0.4 (:238-253, 540-560); `.compositingGroup()` (:229); `deviceIcon` heuristic maps alias/model substrings to SF symbols (iphone, ipad, ipodtouch, smartphone, tablet.portrait, laptopcomputer, desktopcomputer, macmini, macpro.gen3, macstudio, appletv; default smartphone) (:395-538); the click-outside `addLocalMonitorForEvents(.leftMouseDown)` is never removed (leaks one monitor per show) (:103-117); existing window is reused by swapping the hosting view (:58-64).
- [Shelf/Clipboard] Third-party packages the subsystem depends on (spec lists only Defaults): `KeyboardShortcuts` for `.clipboardHistoryPanel` (default Cmd+Shift+V, DI/Shortcuts/ShortcutConstants.swift:27; migration from Cmd+Shift+C guarded by `didMigrateClipboardShortcutToV`, DI/models/Constants.swift:1496,1574-1583, called at launch DI/DynamicIslandApp.swift:718) and `swift-collections` (OrderedSet in TrayDrop). NotchIsland must provide its own global-shortcut mechanism.
- [CLIPBOARD] Display-mode routing and entry points: header button is a 30x30 black Capsule with `headerGlyph("list.clipboard")` at 13pt medium in a 20pt box (DI/components/Notch/DynamicIslandHeader.swift:58-84, 133-160), hidden when `clipboardDisplayMode == .separateTab` or `showClipboardIcon` off; per mode: .panel → ClipboardPanelManager.toggle, .popover → SwiftUI `.popover(arrowEdge: .bottom)` setting `vm.isClipboardPopoverActive` and toggling `vm.shouldRecheckHover` 0.1 s after close, .notchTab → `AppDelegate.cancelPendingNotchAutoClose()` then toggle currentView between .clipboard and .home (:136-171). `coordinator.shouldToggleClipboardPopover`/`toggleClipboardPopover()` (DI/DynamicIslandViewCoordinator.swift:454-460) and the `"ToggleClipboardPopover"` NSNotification drive the same switch (DynamicIslandHeader.swift:375-405). Shortcut handler (DI/DynamicIslandApp.swift:1405-1464): starts monitoring if needed; .popover opens the notch then posts the notification after 0.3 s; .separateTab opens → .notes or closes if already there; .notchTab picks the view model under the cursor when showOnAllDisplays, cancels the 3 s auto-close armed by toggleNotchOpen (DI/DynamicIslandApp.swift:1065-1073, 1391-1394) and opens/toggles .clipboard.
- [CLIPBOARD] Notch sizing for clipboard views: `.clipboard` forces open height `max(openNotchSize.height, NotesLayoutState.list.preferredHeight)` = 240 (DI/ContentView.swift:198-203; DI/DynamicIslandApp.swift:573-575; DI/models/DynamicIslandViewModel.swift:425-428 uses `notesLayoutState.preferredHeight` for both .notes and .clipboard); NotesLayoutState list/split/editor = 240/260/320 (DI/enums/generic.swift:86-99). separateTab tab label/icon 'Clipboard'/'doc.on.clipboard' when Notes is off, else 'Notes'/'note.text' (DI/components/Tabs/TabSelectionView.swift:90-93); split layout = `NotchClipboardView(fixedColumns: 2).frame(maxWidth: .infinity)` on the LEFT, `Divider().background(white@0.15)`, notes on the right (DI/components/Notch/NotchNotesView.swift:45-58). `focusClipboardTabIfNeeded()` on vm.open(): in separateTab mode, if the last copy was ≤ 10 s ago (`clipboardFocusWindow`), switch to .notes with `.smooth` (DI/models/DynamicIslandViewModel.swift:86, 122-131, 418).
- [CLIPBOARD] NotchClipboardView / ClipboardGridCard full layout (DI/components/Notch/NotchClipboardView.swift): header HStack 'Clipboard' 16pt semibold rounded white + trash 14pt red in 16x16 frame, padding 5, white@0.1 Circle, padding h20 t8 b12 (:113-135); confirmation `.alert("Clear Clipboard History?")` with destructive 'Clear History' (:97-105) holding auto-close suppression while shown; empty state doc.on.clipboard 32pt secondary@0.3, 'No copies yet' headline, 'Copy something to see it here' caption, padding v30 (:137-151); `LazyVGrid(adaptive min 200 | fixed n, spacing 8)` padding h20 b20 (:44-49, 58-86); card: HStack spacing 10, 28x28 thumbnail r6 (image: fill + white@0.1 0.5pt stroke, copied overlay black@0.5 + green checkmark.circle.fill 14pt; else type icon 16pt blue on white@0.06, swaps to green checkmark when copied), preview 13pt white 1 line, type 10pt + time 10pt secondary ('Just now'/'Xm'/'Xh'), padding 8, bg white@0.08 (hover 0.12) r12 + blue@0.2 1pt stroke, hover delete `xmark.circle.fill` 14pt (.white, .black@0.5) padding 4 with scale+opacity transition, `.animation(.easeInOut(duration: 0.12), value: isHovered)`, image decoded once via `.task(id:)` (:172-263); tap copies with 1.5 s 'justCopied' feedback (:153-161); hovering the view sets `vm.setScrollGestureSuppression` (:163-167); accessibility combine + 'Delete' action (:77-81); onAppear starts monitoring (:106-110).
- [CLIPBOARD] ClipboardDragging payloads (DI/components/Clipboard/ClipboardDragging.swift): `.rtf` registers `public.rtf` then `public.utf8-plain-text` data representations; `.text/.url/.unknown` NSString; `.image` copies the PNG to `temporaryDirectory/<same name>` first then `NSItemProvider(contentsOf:)`; `.file` single URL via `NSItemProvider(contentsOf:)`; fallback drags the preview text; `isMultiFile` entries (>1 fileURLs) are not draggable at all (:37-107); `clipboardDraggable()` calls `ClipboardManager.markDragStart()` (8 s `dragSafetyResetTimeout`, DI/managers/ClipboardManager.swift:397-405).
- [CLIPBOARD] ClipboardPopover (280x320) full spec (DI/components/Clipboard/ClipboardPopover.swift): bg `.regularMaterial` r10 shadow black@0.2 r8 y4 (:75-80); header doc.on.clipboard 14pt medium + 'Clipboard' 13pt semibold + trash 11pt red (disabled when empty), padding h14 t10; `ClipboardTabButton` row; search 'Search...' 11pt in gray@0.1 r5, padding h10 v5, clear xmark.circle.fill 9pt (:90-165); tab switch `.easeInOut(0.2)`; empty state icon 24pt + 12pt/10pt texts ('No results'/'Try different search terms', 'No clipboard history'/'Copy something to start', 'No favorites'/'Pin items to add favorites') (:168-199); rows: icon 12pt blue w16, preview 11pt 2 lines, type/time 9pt ('now','Xm','Xh','Xd'), hover actions heart/heart.fill (red when pinned) · doc.on.doc green · trash red at 9pt spacing 4, padding h14 v6, hover bg gray@0.1 r4 with `.easeInOut(0.15)`, tap copies (:201-313). `ClipboardShared.swift`: `ClipboardTab` history 'clock' / favorites 'heart.fill'; `ClipboardTabButton` 11pt icon + 11pt medium label + 9pt bold count capsule (white@0.3 selected / gray@0.2), padding h12 v6, selected bg Color.blue r6 (DI/components/Clipboard/ClipboardShared.swift:21-86).
- [CLIPBOARD] ClipboardPanel window + view spec (DI/components/Clipboard/ClipboardPanel.swift): NSPanel styleMask [.borderless, .nonactivatingPanel], canBecomeKey/Main true, backgroundColor clear, hasShadow, level .floating, isMovableByWindowBackground, titlebar transparent/hidden, isFloatingPanel, `.fullSizeContentView`, collectionBehavior [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary], acceptsMouseMovedEvents, registered with `ScreenCaptureVisibilityManager(.panelsOnly)` (sets `window.sharingType = .none` when capture-hiding is on, DI/helpers/ScreenCaptureVisibilityManager.swift:67) (:32-80); hosting view corner mask r18 continuous (:22-30, 88); default position = centred in `NSScreen.main.visibleFrame`, saved origin restored if fully inside, clamped if intersecting (:96-135); `setFrameOrigin` override persists `clipboardPanelPositionX/Y` on every move (:157-161); ClipboardPanelManager shows with makeKeyAndOrderFront + orderFrontRegardless + `NSApp.activate(ignoringOtherApps: true)` + `makeKey()` after 0.1 s, toggle closes/recreates each time (DI/managers/ClipboardPanelManager.swift:29-61). View: VStack spacing 10; header search field 28pt tall r9 continuous bg primary@0.07/0.09 hover/0.12 focused, accent@0.65 1.5pt focus ring, 12.5pt font, placeholder 'Search clipboard', clear button with opacity+scale(0.7) transition, `.easeOut(0.16)` (:300-336); `NativeStyleCloseButton` 13pt red circle, xmark 8pt medium white, hover red@0.8 scale 1.1 `.easeInOut(0.1)` (DI/components/ColorPicker/ColorPickerPanel.swift:681-702); `ClipboardSegmentedTabs`: container primary@0.06 r9 padding 2, spacing 2, selected pill primary@0.14 r7 24pt tall padding h10 with `matchedGeometryEffect` and `.spring(response: 0.32, dampingFraction: 0.82)`, icon 10pt semibold, label 11.5pt medium, count 9.5pt semibold monospacedDigit (:376-433); clear button trash 11.5pt medium 26x24 r7, red only on hover, 0.35 opacity disabled, help 'Clear history'/'Clear favorites' (:340-367); list LazyVStack spacing 4, padding 12, `.scrollBounceBehavior(.basedOnSize)`, `.animation(.easeOut(0.18), value: filteredItems.count)` (:238-279); empty state 56pt circle primary@0.06 + 22pt light icon (magnifyingglass/doc.on.clipboard/heart), 13pt semibold title, 11.5pt subtitle ('Try a different search term', 'Copy something to get started', 'Pin items to keep them here'), bottom padding 24 (:435-480); row: badge 34x34 r9 continuous (image thumbnail fill or tint@0.18 + 13pt semibold tint icon, checkmark green with `.symbolEffect(.replace)`), preview 12.5pt 2 lines fixedSize, meta 10.5pt medium 'Type · time' (type in tint@0.95, time 'Just now'/'Xm ago'/'Xh ago'/'Xd ago'), padding h10 v9, bg primary@0.03 (hover 0.08) r12 continuous + primary@0.08 stroke on hover, hover `.easeOut(0.16)`, action cluster fixed width 78 of 24x24 r7 buttons (pin/pin.fill accent always visible when pinned, doc.on.doc/checkmark green, trash with red hoverTint; button hover primary@0.12 `.easeOut(0.14)`), copy confirmation 1.5 s with cancel-on-repeat (:482-676); per-type tints text (0.55,0.58,0.64), url (0.35,0.56,0.92), file (0.92,0.66,0.30), image (0.66,0.48,0.90), rtf (0.36,0.72,0.62) (:191-202); background `VisualEffectView(.hudWindow, .behindWindow, state .active, isEmphasized)` + white@0.07→clear top gradient, r18 continuous clip, white@0.12 1pt hairline, shadow black@0.4 r26 y12 (:257-278; DI/components/Settings/EditPanelView.swift:52-63).
- [CLIPBOARD] ClipboardManager data model and rules (DI/managers/ClipboardManager.swift): `ClipboardItem {id (let id = UUID() — NOT decoded, so ids regenerate every launch), type, timestamp, preview, isPinned, stringData, imageFileName, fileURLs:[String], rtfData}` (:27-32, 62-66); image files named `clipboard_image_<UUID>.png` in `~/Documents/ClipboardData` (:97-98, 248-256), session-only images kept in a locked static `inMemoryImages` dictionary pruned on every save (:40-59); RTF > 100000 bytes dropped (:130); previews: text/rtf/unknown first 50 chars, url lastPathComponent or host, image 'Image (<ByteCountFormatter .file>)', file lastPathComponent or 'N files' (:85-92, 108-111, 153-172); type icons/displayNames text doc.text 'Text', url link 'URL', file doc 'File', image photo 'Image', rtf doc.richtext 'Rich Text', unknown questionmark.circle 'Unknown' (:176-204); real-file filter excludes `/.file/id=`, `/tmp/`, `/private/var/`, `/ClipboardViewer` and non-existent paths (:583-591); image extensions jpg/jpeg/png/gif/bmp/tiff/tif/webp/heic/heif (:602); Finder image files → only the FIRST image's bytes are captured as an `.image` item (:607-612); HTML→RTF synthesis must run on main thread (WebKit) (:805-825); dedup `isSameContent` compares image bytes (:719-736); `addToHistory` removes equal items then inserts at 0, sets `lastCopiedItemDate`, trims and deletes evicted PNGs (:676-716); `copyToClipboard` writes .string / .png / NSURL objects / .rtf+.string (:407-438); pin moves item out of history into `pinnedItems` and materialises an in-memory image to disk (:483-523), unpin re-inserts at index 0 and re-trims (:525-550); `cleanupOldFiles` on init deletes unreferenced PNGs (:738-753); persistence toggle: off → retain images in memory, remove 'ClipboardHistory' key and unpinned PNGs; on → write in-memory images to files and save (:270-290, 296-329); `purgeStoredHistoryIfPersistenceDisabled()` runs at launch (:330-339; DI/DynamicIslandApp.swift:758). Monitoring is lazy — started by header onAppear, NotchClipboardView onAppear, the shortcut, or the Settings toggle, never at launch.
- [CLIPBOARD] Settings UI (DI/components/Settings/SettingsView.swift:8463-8600+): sections 'Clipboard Manager' (toggle starts/stops monitoring), 'Privacy' → 'Save History Across Restarts' with footer about erasing saved history, 'Settings' → 'Show Clipboard Icon', 'Display Mode' menu (Popover/Panel/Separate Tab/Notch Tab), 'History Size' (3/5/7/10 items), read-only rows 'Current Items', 'Pinned Items', 'Monitoring Status' (Active green / Stopped), per-mode footer texts; 'Actions' → red 'Clear Clipboard History'/'Clear Pinned Items'; a live history preview list follows. Clipboard settings tab icon 'clipboard', colour .mint (:128,154); shortcut recorder 'Clipboard History:' under Shortcuts (:7206-7224).
- [CLIPBOARD] Legacy unreferenced clipboard UI (confirm spec marks all three dead): `ClipboardWindow` 400x300 SwiftUI view with hudWindow material, 'Clipboard Manager' title, ClipboardTabButton tabs, 'Search clipboard...' field, rows with heart/doc.on.doc/trash at 11pt (DI/components/Clipboard/ClipboardWindow.swift:22-308); `ClipboardWindowManager` titled/closable/resizable NSWindow 400x300 (min 350x250, max 600x500) at `.screenSaver` level, hide-instead-of-close delegate, ScreenCapture registration (DI/managers/ClipboardWindowManager.swift:22-118); `ClipboardHistoryPopover` 280pt wide, maxHeight 200, black@0.95 r12, auto-closes popover and notch on hover exit (DI/components/Notch/ClipboardHistoryPopover.swift:21-80). REA dispatch.json confirms `ClipboardWindowManager` is compiled into 2.3.3 even though nothing calls it.

Corrections:

- Open With submenu: spec says 'other apps alphabetically'. In the live menu the non-default apps are `Array(Set(results))` — unsorted/arbitrary order (DI/components/Shelf/ViewModels/ShelfItemViewModel.swift:376-387, 420-425). The sorted `loadOpenWithApps()` (:306-330) is never called by `presentContextMenu`.
- Shelf item cell 'drop target' visual state (accent@0.25 fill, accent@0.9 3pt border) is unreachable in 2.3.3: `ShelfItemViewModel.isDropTargeted` (ShelfItemViewModel.swift:36) is never written anywhere; the only reader is `ShelfItemView.swift:121`. The spec presents it as user-visible ('a tile being dropped-onto shows a stronger accent fill'). Also unmentioned: that same onChange writes `vm.dragDetectorTargeting = targeted` (ShelfItemView.swift:122).
- LocalSend click path: spec says 'dropping onto the tile (or clicking it) first shows a 480x400 Select Device panel'. Only the DROP path shows the device picker (DI/components/Shelf/Views/FileShareView.swift:58-68, 280-302). Clicking the tile goes `handleClick → QuickShareService.showFilePicker → shareFilesOrText → LocalSendService.send`, which targets `devices.first(where: id == selectedDeviceID) ?? devices.first` with no picker (FileShareView.swift:69-75, 312-314; DI/components/Shelf/Services/QuickShareService.swift:177-237; DI/components/Shelf/Services/LocalSendService.swift:501-510).
- notchTab is not a tab in the tab bar: `TabSelectionView.tabs` never appends `.clipboard` (DI/components/Tabs/TabSelectionView.swift:65-110) and `enabledStandardTabCount()` does not count it (DI/sizing/matters.swift:98-135). It is a `NotchViews` case reachable only from the header `list.clipboard` button (DI/components/Notch/DynamicIslandHeader.swift:150) and the Cmd+Shift+V handler (DI/DynamicIslandApp.swift:1436-1464). While `currentView == .clipboard` no tab is highlighted, and `TabSelectionView.onAppear → ensureValidSelection` resets `currentView` to the first tab when none matches (TabSelectionView.swift:147-149, 177-190) — so opening a closed notch straight into .clipboard can snap back to Home when the tab row appears. Spec should describe it as a hidden view, not a 'dedicated tab'.
- openNotchSize formula: spec gives '(max(stored openNotchWidth, recommended min for tab count), 200)'. Actual: `min(max(storedWidth, minWidth, sideLyricsRequiredNotchWidth()), maxAllowedNotchWidth())` x 200, where maxAllowedNotchWidth = max(screenWidth − 60, 400) (DI/sizing/matters.swift:69-75, 79-93). For `.clipboard` and `.notes` the open height becomes max(200, notesLayoutState.preferredHeight) = 240 in list state (DI/ContentView.swift:198-203; DI/models/DynamicIslandViewModel.swift:425-428).
- ClipboardPanel default placement: spec implies 'near the notch' (method name `positionNearNotch`). The default is the CENTRE of `NSScreen.main.visibleFrame`; a saved origin is restored when fully on-screen or clamped when only intersecting (DI/components/Clipboard/ClipboardPanel.swift:96-135). `positionNearMouse()` (:163-180) is unused.
- Drop ingestion 'raw .data saved to a temp file': `NSItemProvider.loadData()` only accepts items delivered as `Data`, or as a URL whose absoluteString contains `com.apple.SwiftUI.filePromises` (the promise file is read then deleted). Any other URL-typed `public.data` item returns nil and the provider falls through to `extractItem()` (DI/extensions/NSItemProvider+LoadHelpers.swift:39-77). The spec's 'images from a browser' claim holds only when the browser hands Data, not a URL.
- Clipboard classification of Finder copies: spec says 'real Finder file URLs → image files → file list'. Precisely: if any real file URL has an image extension, ONLY the first image file's bytes are stored as an `.image` item and all other copied files are discarded; otherwise all real URLs become one `.file` item (DI/managers/ClipboardManager.swift:596-617). Copying a folder of mixed files containing one JPEG yields a single image entry.
- LocalSendLiveActivity / ShelfInlineLiveActivity summary wording: the spec says the shelf HUD shows 'when items exist' and 'when music is playing, a lowest-priority secondary wing badge'. The standalone HUD is actually the second-to-last branch of the closed-state chain and is pre-empted by any inline HUD, caps-lock, music, timer, reminder, recording, download, LocalSend, DND, privacy and extension payloads (DI/ContentView.swift:1120-1172); the secondary `.shelf(count:)` is pre-empted by timer, reminder, recording, focus, caps-lock and extension payloads in `resolveMusicSecondaryLiveActivity` (DI/ContentView.swift:1520-1553).
- ClipboardItem identity: spec treats history/pinned entries as stable records persisted as JSON. Because `let id = UUID()` has a default value, Swift's synthesized `init(from:)` does not decode it — every launch assigns fresh ids (DI/managers/ClipboardManager.swift:28). Dedup/pin matching therefore relies on content (`isSameContent`) not on id across launches; NotchIsland should decode ids explicitly if it wants stable identity.
- Minor line-drift in citations: `performKeyEquivalent` is at ShelfMarqueeSelectionView.swift:173-181 (spec: 171-179); `applyBand` is at :303-318 (spec cites 167-183, which is ShelfSelectionModel.updateMarquee); `loadMetadata` starts at ShelfItemViewModel.swift:56; `DynamicIslandAnimations.animation` is drop.swift:34-40; Bookmark creation is Bookmark.swift:43-47. All other spot-checked citations (ContentView 806-820, 862-871, 1166-1168, 1546-1548, 1571-1572, 1675-1678, 1737-1743, 2065-2092, 2473-2479; ShelfView, ShelfItemView, ShelfStateViewModel, ThumbnailService, QuickLookService, TemporaryFileStorageService, FileShareView, QuickShareService, LocalSendService, LocalSendDevicePickerWindowManager, Constants 1215-1227/1359-1366, SettingsView 4490-4554) resolve to the stated code.

Private API summary:

Shelf and clipboard code in Atoll 2.3.3 uses no private macOS APIs, confirmed from both the source and the REA macho.json for /Applications/Atoll.app. Linked frameworks (macho.json normalized_result.dependencies, 75 entries) are all public system frameworks plus @rpath Lottie and Sparkle; the only underscore-prefixed one is /System/Library/Frameworks/_QuickLook_SwiftUI.framework, which is Apple's public SwiftUI QuickLook module behind `View.quickLookPreview(_:in:)` (import `_$s7SwiftUI4ViewP011_QuickLook_aB0E05quickE7Preview_2in...` is present), used by QuickLookService.swift:118-131. Public APIs the subsystem relies on, each confirmed as a macho.json import: SwiftUI `onDrop(of:isTargeted:perform:)` (both UTType and String overloads), `onDrag`, `ImageRenderer(content:)`/`.scale`/`.nsImage`, `fileImporter` (elsewhere); AppKit `NSDraggingItem`, `NSPasteboard`/`NSPasteboardItem`, `NSPasteboardTypeFileURL/PNG/TIFF/RTF/String/URL`, `NSSharingService` + `NSSharingServicePicker` with `NSSharingServiceNameSendViaAirDrop/ComposeEmail/ComposeMessage/AddToSafariReadingList`, `NSOpenPanel`/`NSSavePanel`, `NSMenu`/`NSMenuItem`, `NSPanel`, `NSVisualEffectView`, `NSWorkspace` + `NSWorkspaceOpenConfiguration`, `NSWindow.sharingType` (ScreenCaptureVisibilityManager, used by ClipboardPanel), NSTrackingArea and `NSEvent.addLocalMonitorForEvents`; Foundation `URL.bookmarkData(options:includingResourceValuesForKeys:relativeTo:)` with empty options and `URL(resolvingBookmarkData:options:relativeTo:bookmarkDataIsStale:)` incl. `.withoutMounting` (plain, non-security-scoped bookmarks because the app is not sandboxed: signature.json entitlements contain no com.apple.security.app-sandbox, only automation.apple-events, cs.disable-library-validation, device.camera, mach-services, calendars, location and temporary-exception keys); QuickLookThumbnailing `QLThumbnailGenerator`/`QLThumbnailGenerationRequest` (iconMode); QuickLookUI `QLPreviewPanel`; Vision `VNGenerateForegroundInstanceMaskRequest`; CoreImage `CIFilter` (blendWithMask, lanczosScaleTransform) and `CIContext.heifRepresentation`; PDFKit `PDFDocument`/`PDFPage`; Network `NWConnectionGroup`, `NWMulticastGroup`, `NWListener`, `NWConnection`; URLSession upload tasks with a permissive `URLSessionDelegate` (LocalSendTLSDelegate accepts any serverTrust); CoreServices `LSSetDefaultRoleHandlerForContentType` / `LSSetDefaultHandlerForURLScheme` (public but deprecated since macOS 12; NotchIsland should prefer `NSWorkspace.setDefaultApplication(at:toOpen:)`); the legacy Ext+URL path uses the deprecated public C API `QLThumbnailImageCreate`. Process-spawning of `/usr/bin/zip` (Compress) and `/usr/sbin/arp -an` (LocalSend neighbour discovery) plus `getifaddrs/getnameinfo` are ordinary POSIX/Foundation, not private. The binary DOES import private symbols — `_CGSAddWindowsToSpaces`, `_CGSRemoveWindowsFromSpaces`, `_CGSShowSpaces`, `_CGSHideSpaces`, `_CGSSpaceCreate`, `_CGSSpaceDestroy`, `_CGSSpaceSetAbsoluteLevel`, `__CGSDefaultConnection`, `_CGSIsScreenWatcherPresent`, `_CGSRegisterNotifyProc`, `_CGSessionCopyCurrentDictionary`, `_CGShieldingWindowLevel`, and Accessibility `_AXUIElement*`/`_AXIsProcessTrusted*` — but none of these are referenced from components/Shelf, components/Clipboard, components/Notch/NotchShelfView|NotchClipboardView, managers/Clipboard*, managers/LocalSendDevicePickerWindowManager or helpers/ScreenCaptureVisibilityManager (grep shows only `sharingType` there); they belong to the SkyLightWindow package / lock-screen / spaces subsystems. Info.plist (plist.json) carries NSDocumentsFolderUsageDescription ('Atoll needs access to save and read shelf dragged files.') and NSDownloadsFolderUsageDescription, matching the Settings gating on Full Disk Access or Documents+Downloads TCC access via plain FileManager directory probes.
