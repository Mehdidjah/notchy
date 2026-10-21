# Notchy website

The download page for Notchy: plain HTML, CSS and JavaScript with no build step.

```sh
cd website
python3 -m http.server 8000   # then open http://localhost:8000
```

## Deploying

Upload the folder as it is to any static host, for example Netlify or Vercel
(drag the folder in, or point a project at `website/`), or GitHub Pages from a
public repository. Once the site has a domain, make the `og:image` link in
`index.html` absolute (`https://your-domain/assets/img/icon-256.png`) so link
previews show the icon.

## Downloads and versions

Every Download button links to

```text
https://github.com/Mehdidjah/notchy-releases/releases/latest/download/Notchy.dmg
```

which always serves the newest release that `script/release.sh --publish`
uploaded. The download card reads the version, date and size of that release
from the GitHub API when the page loads; `RELEASES` at the top of `script.js`
names the repository. Nothing on the page needs editing for a new release.

The "First time opening Notchy?" card explains Open Anyway, which macOS asks
for while releases aren't notarized. Remove it, and the FAQ answer that links
to it, once they are.

## Fonts

Inter, Instrument Serif (italic) and Fragment Mono are served from
`assets/fonts`, so visitors' browsers don't contact a font service. They are
licensed under the SIL Open Font License; see `assets/fonts/OFL.txt`.
