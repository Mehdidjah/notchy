# NotchIsland Collapsed Notch — Design QA

> **Superseded on 2026-10-15.** The collapsed geometry below (183-pt frame, 5-pt flares,
> 9-pt corners, near-black then pure black) was replaced by the Atoll-parity silhouette:
> hardware gap + 4 pt, 6-pt top flares, 14-pt bottom corners, +8 pt hover swell, and a
> 150-pt island at menu-bar height on displays without a notch. The measurements and the
> "passed" verdict describe the earlier build only. See `docs/atoll-behaviour-evidence.md`.

## Comparison target

- Source visual truth: `/Users/a/Desktop/Screenshot 2026-08-03 at 13.34.43.png`
- Source pixels: `3456 × 2234` at 2× density
- Final implementation capture: `/private/tmp/notchisland-collapsed-implementation-v4.png`
- Final implementation pixels: `3456 × 2234` at 2× density
- Normalized source crop: `/private/tmp/notchisland-collapsed-reference-crop.png`, `600 × 160`
- Normalized final crop: `/private/tmp/notchisland-collapsed-implementation-v4-crop.png`, `600 × 160`
- Final combined comparison: `/private/tmp/notchisland-collapsed-comparison-v4.png`
- Geometry comparison with a contrasting desktop background: `/private/tmp/notchisland-collapsed-comparison-v3.png`
- Display viewport: `1728 × 1117` points at 2× capture density
- State: idle/collapsed, not hovered or selected

## Full-view comparison evidence

Both captures use the same built-in Retina display and density. The implementation
occupies the same centered top-edge position and the same 32-point depth as the
reference. The surrounding desktop and active application differ because these
are live macOS captures; the normalized top-center crops isolate the app-owned
notch silhouette for comparison.

## Focused-region comparison evidence

The measured source body is 346 pixels (`173 pt`) wide from rows 12–40. The final
geometry comparison produces the same 346-pixel body over those rows. Both
silhouettes end at row 64 (`32 pt`) and use equivalent bottom-corner curvature.
The implementation uses a 183-point outer frame with 5-point top flares and
9-point bottom corners. The final pass also changes the surface from near-black
to pure black to match the sampled source.

The v4 capture was taken over a dark active application, which reduces contrast
around the upper edge. The v3 combined comparison uses identical geometry over
a contrasting blue desktop and therefore remains the clearer shape comparison;
the only code change between v3 and v4 is the fill token.

## Required fidelity surfaces

- Fonts and typography: the collapsed component contains no text or typography.
- Spacing and layout rhythm: center alignment, 183-point outer frame, 173-point
  body, 32-point height, top flares, and bottom radii match the reference crop.
- Colors and visual tokens: the final app-owned surface uses pure black, matching
  the reference's sampled center pixels.
- Image quality and asset fidelity: no raster assets or generated approximations
  are used; the notch is a resolution-independent native SwiftUI shape.
- Copy and content: the collapsed component contains no app-specific copy.

## Interaction verification

- The visible collapsed surface is independent of the larger invisible hover
  target, so matching the visual size does not reduce hover reliability.
- The app opens after the configured half-second dwell and begins closing after
  a half-second outside delay.
- Six Swift tests pass, including collapsed geometry, invisible sensor sizing,
  delayed hover, closing re-entry, clipboard filtering, and pasteboard behavior.
- The app was stopped after every capture and is not left running.

## Comparison history

### Pass 1 — blocked

- P1: the idle software surface was nearly transparent, so the screenshot showed
  no app-drawn notch even though the invisible hover sensor existed.
- P2: the rendered collapsed height reused the 56-point sensor height rather
  than the reference's 32-point visible height.

Fixes:

- Separated `renderedSize` from `interactiveSize`.
- Made the idle black silhouette visible on hardware-notch displays.
- Set rendered height from the display safe-area inset.

### Pass 2 — blocked

- P2: the first visible implementation body was 348 pixels versus the source's
  346 pixels, and its top flares were too shallow.

Fixes:

- Tuned the outer frame to 183 points and the collapsed top flare to 5 points.
- Tuned collapsed bottom corners to 9 points.

### Pass 3 — passed

- Post-fix geometry evidence: `/private/tmp/notchisland-collapsed-comparison-v3.png`
- Final pure-black evidence: `/private/tmp/notchisland-collapsed-comparison-v4.png`
- No actionable P0, P1, or P2 differences remain.

## Follow-up polish

- None for the requested collapsed size and silhouette.

final result: passed
