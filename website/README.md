# Notchy website

A responsive Svelte 5 + Vite website for Notchy. All UI state is implemented in Svelte components, with locally served fonts and original generated landscape imagery.

## Run

```sh
cd website
npm ci
npm run dev
```

Open `http://127.0.0.1:4173`.

```sh
npm run check       # Svelte + accessibility/compiler diagnostics
npm run build       # static production bundle in dist/
npm run preview     # serve the production build
npm test            # Playwright browser/interaction regression suite
```

Playwright uses Chromium. Install it with `npx playwright install chromium` if it is not already available. The test configuration may also select a local browser via `PLAYWRIGHT_CHANNEL`.

The dependency overrides select the official WebAssembly distributions of Rollup and esbuild. This keeps builds portable without depending on platform-specific executable permissions.

## Structure

- `src/App.svelte`: page sections, navigation, responsive menu, release data, download tabs, FAQ and page-motion control.
- `src/lib/NotchDemo.svelte`: eight isolated interactive app-preview panels.
- `src/lib/LiveActivities.svelte`: eight selectable live-activity states.
- `src/lib/HeroStage.svelte`: the 1000×562.5px glass hero scene, scaled as one unit on tablet and phone.
- `src/lib/HeroClipboard.svelte`: compact interactive clipboard shelf with search, categories, selection, drag and compact view.
- `src/lib/DeviceStage.svelte`: reusable feature desktop with native app icons.
- `src/lib/Icon.svelte`: local UI icon set and the locally rendered system Apple glyph.
- `public/assets/icons/benefits/`: six vendored Phosphor regular SVGs for the audience cards, displayed in 64px white badges. The MIT license and source attribution are included.
- `src/lib/motion.js`: cleanly disposed IntersectionObserver reveal action.
- `styles.css`: fonts, layout tokens, responsive rules and page motion.
- `public/assets/`: production images, fonts, app icons and social card.
- `tests/website.spec.js`: browser regression coverage.

The native macOS app is not changed by this website.

## Visual system

- Inter Display 400/500/600/700, with Instrument Serif Italic as the editorial accent.
- Blue landscape palette: `#190096`, `#0080FF`, `#78D2FF`; white, black and `#F7F7F7` surfaces.
- 1200px content container, 40px desktop inset, 30px feature-card radius.
- Breakpoints at 1200px and 810px; additional compact-phone refinements below 480px.
- Hero glass width: 1000px desktop, 700px tablet, 350px phone. Hero heading: 80px desktop/tablet, 50px phone. The 700×220px clipboard shelf is scaled with the glass frame.
- Staggered character blur reveals, one-time section entrances, reversible scroll-linked foreground parallax and stateful component transitions.
- `prefers-reduced-motion` disables decorative movement. The footer also exposes a page-motion pause control.

`landscape.webp` and `wallpaper.webp` are original generated images. `foreground.webp` is a transparent foreground derived from the generated landscape, not a third-party asset. `social-card.jpg` is derived from the original landscape. The app icon is rendered from the built Notchy app’s original ICNS resource. The macOS application icons were extracted locally from the installed macOS 27.0.1 application bundles; see `public/assets/macos/PROVENANCE.md`. They are not hand-drawn substitutes. Fonts are self-hosted under the SIL Open Font License; see `public/assets/fonts/OFL.txt`.

## Interactive previews

Preview data is fictional and clearly labeled. Tabs, clipboard filters, sample selection/dragging, shelf add/remove/Quick Look, playback controls, timer start/pause/reset, editable notes and simulated Face Check all work. They do not access a visitor's clipboard, files, camera, accounts or native app. Demo state is kept in memory and is not persisted or uploaded. The Face Check preview is not a biometric check.

## Downloads and releases

The existing stable download integration is preserved:

- Download: `https://github.com/Mehdidjah/notchy-releases/releases/latest/download/Notchy.dmg`
- Release metadata: `https://api.github.com/repos/Mehdidjah/notchy-releases/releases/latest`
- Release notes: `https://github.com/Mehdidjah/notchy-releases/releases`

The metadata request has a seven-second timeout and an explicit unavailable state. It never invents a version, size, date or price. It does not replace the configured download destination based on an API response.

**Release availability:** during verification on 2026-10-21, the public latest-release API and stable download returned 404. The repository must have a publicly accessible published release with an asset named `Notchy.dmg` before the public download works. Publishing a release is separate from deploying the website.

Keep the first-launch guidance until the app is notarized. The current build explains Privacy & Security → Open Anyway and notes that permission grants may need to be renewed after updates.

## Deploy

Deploy the production `dist/` folder, not the Svelte source folder.

For Vercel, set **Root Directory** to `website`, **Build Command** to `npm run build`, and **Output Directory** to `dist`. The local `vercel.json` contains these build settings. For another static host, use the same build command and output directory.

Once a production domain is selected, make the `og:image` URL in `index.html` absolute and add the site's canonical URL. No domain is invented in this project. Existing in-page anchors are retained: `#top`, `#features`, `#live`, `#privacy`, `#download`, `#install`, `#faq`.
