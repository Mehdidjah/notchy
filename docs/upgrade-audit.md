# NotchIsland production upgrade audit

Audit date: 2026-08-03

## Existing repository

- Project type: Swift Package Manager macOS GUI executable (`NotchIsland`), macOS 14+, Swift tools 6.2.
- Entry point: `Sources/NotchIsland/App/NotchIslandApp.swift`.
- Windowing: one borderless, nonactivating `NSPanel` owned by `NotchPanelController`.
- UI: SwiftUI notch root, expanded shelf, filters, and clipboard cards hosted by AppKit.
- State: `NotchViewModel` using Combine and three independent presentation Booleans.
- Clipboard integration: a string-only `NSPasteboard` writer. There is no monitor, normalization, feedback-loop suppression, or source-app tracking.
- Persistence: none.
- Tests: three Swift Testing cases covering filter composition, pasteboard delegation, and delayed hover collapse.
- Build/run: `./script/build_and_run.sh` stages and launches `dist/NotchIsland.app`.
- Entitlements/signing/assets: no Xcode target, entitlement file, app-owned raster assets, signing configuration, or stored credentials are present.
- Local tooling: `.codex/` is ignored as requested. Unrelated `.vscode/` files are user-owned and remain untouched.

## Baseline

- `swift test`: passed, 3 tests in 1 suite.
- `./script/build_and_run.sh --verify`: Debug build and process launch passed.
- The first sandboxed test attempt could not write Swift compiler caches under `~/.cache`; rerunning with normal toolchain cache access passed. This was an execution sandbox limitation, not a project failure.

## Feature-gap matrix

| Area | Status before upgrade | Evidence / action |
| --- | --- | --- |
| Native SwiftUI + AppKit stack | Already implemented and correct | Preserve the single SwiftPM executable and accessory-app lifecycle. |
| Existing branding and app identity | Already implemented and correct | Preserve `NotchIsland`; keep the current local bundle identifier until a distribution identifier is supplied. |
| Visual dark shelf foundation | Implemented but incomplete | The existing screenshot-inspired styling is useful, but cards are oversized and all production content is hard-coded sample data. |
| Hover open/close | Implemented but architecturally unsafe | An 80 ms polling timer and unrelated Booleans can race; the outer window resizes and the close delay is 220 ms. |
| Transparent-area click-through | Implemented but architecturally unsafe | The full panel explicitly sets `ignoresMouseEvents = false` and has no explicit `interactiveRect`. |
| Notch geometry | Implemented but incomplete | It reads safe-area and auxiliary areas, but geometry, display changes, and synthetic non-notch behavior are embedded in the panel controller. |
| Explicit notch state machine | Missing | Replace Boolean presentation state with legal states/transitions and tests. |
| Clipboard capture and normalization | Missing | Add change-count monitoring, rich snapshots, hashing, source app, internal-write suppression, ignored types/apps, and pause/manual modes. |
| Persistent history | Missing | Add a SwiftData metadata store and Application Support payload directory; no existing on-disk model needs migration. |
| Sensitive-content protection | Missing | Add deterministic local detection and default skip behavior. |
| Search/filter/retrieval | Implemented but incomplete | Search/filter runs against fake in-memory cards only. Connect it to persisted clips and expanded types. |
| Paste target restoration | Missing | Add target tracking, pasteboard serialization, Accessibility-aware Command-V, and copy-only fallback. |
| Multi-select/combined paste/queue | Missing | Add selection, ordering, separators, reusable composition logic, and sequential queue state. |
| Quick Paste | Missing | Add a keyable compact panel and global shortcut. |
| Menu bar | Missing | Add status, recent items, pause, shelf, Library, Quick Paste, queue, clear, settings, and quit commands. |
| Full Library | Missing | Add a resizable search/filter/selection window with grid/list modes and inspector. |
| Settings | Missing | Add native settings for capture, notch timing/sizing, retention, privacy, and permissions. |
| OCR/screenshots/color/reminders | Missing | Add service boundaries and local implementations incrementally; permission-gated features must not block the core app. |
| iCloud/Dropbox/Sparkle | Blocked by credentials or entitlement | Keep optional and disabled. Distribution team must provide bundle/team IDs, iCloud container, Dropbox OAuth values, Sparkle feed/signing keys, and Developer ID credentials. |
| DMG/signing/notarization | Blocked by credentials or entitlement | Debug app bundling exists; Developer ID signing, hardened runtime, notarization, stapling, and DMG release automation require distribution credentials. |

## Reference repository findings

Inspected `stevemcqueenz/claude-notch-tracker` at commit
`94839a43b376801cebd7f8e0cdc6ab1939310fe5`.

Useful engineering concepts:

- a fixed full-width transparent top-strip panel;
- internal SwiftUI island size/shape animation rather than per-frame window resizing;
- a hosting view that returns `nil` outside an explicit interactive rectangle;
- safe-area and auxiliary-area notch geometry with a non-notch fallback;
- an animatable notch silhouette with concave top flares;
- transient click-away monitoring and interaction gating while retracted.

Excluded by design:

- Claude/Codex providers, usage/session parsing, artwork, icons, API and Keychain logic;
- private SkyLight/CGS fullscreen-space code;
- always-visible percentage/status UI and click-only expansion.

The top-strip, pass-through hosting, and animatable-shape implementation will be
adapted in a small, clipboard-specific form. The pinned MIT attribution is kept
in `THIRD_PARTY_NOTICES.md`.

## Migration and implementation strategy

1. Preserve the current target, entry point, build script, app name, bundle ID, and accessory lifecycle.
2. Introduce a production `Clip` model while retaining `ClipboardItem` as a compatibility alias.
3. Store metadata in a versioned SwiftData schema and large payloads under Application Support. There is no prior persistent schema, so the first production schema is additive.
4. Replace fake production items with repository-loaded clips; preview fixtures remain test-only.
5. Centralize notch transitions and delayed effects in one state machine/view model.
6. Replace the resizing panel with one fixed top strip and an explicit pass-through hit region.
7. Layer Quick Paste, menu bar, Library, settings, paste coordination, and multi-paste over shared services rather than duplicating state.
8. Keep permission-dependent and credential-dependent features disabled or copy-only until explicitly configured.
