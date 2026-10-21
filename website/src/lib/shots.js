// Screenshots of the real app. Each one is drawn by Notchy's own SwiftUI views, filled with
// made-up data, by the WebsiteShots test suites (Tests/NotchyTests/WebsiteShots*.swift):
//
//   NOTCHY_WEBSITE_SHOTS="$PWD/website/public/assets/app" swift test --no-parallel --filter WebsiteShots
//
// Sizes are in CSS pixels at the size the island has on a 14-inch MacBook Pro: the open island
// is drawn at 2x and the closed notch at 4x, so both stay sharp when shown larger.

/** The open island on each tab. */
export const tabShots = {
  home: {
    src: '/assets/app/tab-home.png',
    width: 696,
    height: 183.5,
    alt: 'Notchy open on its Home tab: a Focus timer, the song that is playing with its controls, a grid of apps, the next calendar event and the weather.'
  },
  clipboard: {
    src: '/assets/app/tab-clipboard.png',
    width: 696,
    height: 183.5,
    alt: 'Notchy open on its Clipboard tab: recent clips of text, a link, a colour and code, each with how long ago it was copied.'
  },
  shelf: {
    src: '/assets/app/tab-shelf.png',
    width: 696,
    height: 183.5,
    alt: 'Notchy open on its Shelf tab: an image, a PDF, a text snippet and a link parked beside the share area.'
  },
  timer: {
    src: '/assets/app/tab-timer.png',
    width: 696,
    height: 183.5,
    alt: 'Notchy open on its Timer tab: a Focus session with 17:40 left, its progress ring and a pause button.'
  },
  stats: {
    src: '/assets/app/tab-stats.png',
    width: 696,
    height: 183.5,
    alt: 'Notchy open on its Stats tab: live graphs of CPU, memory and GPU use.'
  },
  notes: {
    src: '/assets/app/tab-notes.png',
    width: 696,
    height: 183.5,
    alt: 'Notchy open on its Notes tab: colour-coded notes such as a launch checklist and ideas for a landing page.'
  },
  face: {
    src: '/assets/app/tab-face.png',
    width: 696,
    height: 183.5,
    alt: 'Notchy open on its Face Check tab after a check: “It’s you”, with Check now and Scan again buttons.'
  },
  ai: {
    src: '/assets/app/tab-ai.png',
    width: 696,
    height: 183.5,
    alt: 'Notchy open on its AI tools tab: a chat with Claude, with the plan’s session and weekly usage above it.'
  },
  'ai-sessions': {
    src: '/assets/app/tab-ai-sessions.png',
    width: 696,
    height: 183.5,
    alt: 'Notchy’s AI tools tab showing Claude Code sessions, each with how full its context is.'
  }
};

/** Live activities on the closed notch, in the order the page offers them. */
export const closedShots = [
  {
    id: 'music',
    label: 'Now playing',
    src: '/assets/app/closed-music.png',
    width: 258.5,
    height: 33.5,
    caption: 'The album art on one side of the notch, bars that dance while it plays on the other.'
  },
  {
    id: 'timer',
    label: 'Timer',
    src: '/assets/app/closed-timer.png',
    width: 344,
    height: 33.5,
    caption: 'Your countdown and how far along it is, right beside the notch.'
  },
  {
    id: 'reminder',
    label: 'Next meeting',
    src: '/assets/app/closed-reminder.png',
    width: 352.5,
    height: 33.5,
    caption: 'A countdown to your next meeting in the minutes before it starts.'
  },
  {
    id: 'claude',
    label: 'Claude Code',
    src: '/assets/app/closed-claude.png',
    width: 272.5,
    height: 33.5,
    caption: 'Claude Code at work, and how full its session’s context is.'
  },
  {
    id: 'volume',
    label: 'Volume',
    src: '/assets/app/closed-volume.png',
    width: 398.5,
    height: 33.5,
    caption: 'Volume changes, shown right in the notch.'
  },
  {
    id: 'brightness',
    label: 'Brightness',
    src: '/assets/app/closed-brightness.png',
    width: 398.5,
    height: 33.5,
    caption: 'Brightness changes, shown right in the notch.'
  },
  {
    id: 'shelf',
    label: 'Shelf',
    src: '/assets/app/closed-shelf.png',
    width: 258.5,
    height: 33.5,
    caption: 'How many items are waiting for you on the shelf.'
  },
  {
    id: 'capslock',
    label: 'Caps Lock',
    src: '/assets/app/closed-capslock.png',
    width: 394.5,
    height: 33.5,
    caption: 'A quiet sign that Caps Lock is on.'
  },
  {
    id: 'copied',
    label: 'Copied',
    src: '/assets/app/peek-copied.png',
    width: 326,
    height: 81,
    caption: 'A quick peek at what you just copied.'
  },
  {
    id: 'facecheck',
    label: 'Face Check',
    src: '/assets/app/closed-facecheck.png',
    width: 263.5,
    height: 219,
    caption: 'Face Check confirming it’s you before a hidden clip is shown.'
  }
];
