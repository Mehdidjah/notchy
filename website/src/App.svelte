<script>
  import { onMount } from 'svelte';
  import { slide } from 'svelte/transition';
  import Icon from './lib/Icon.svelte';
  import DeviceStage from './lib/DeviceStage.svelte';
  import HeroStage from './lib/HeroStage.svelte';
  import LiveActivities from './lib/LiveActivities.svelte';
  import { reveal } from './lib/motion.js';

  const download =
    'https://github.com/Mehdidjah/notchy-releases/releases/latest/download/Notchy.dmg';
  const releases = 'https://github.com/Mehdidjah/notchy-releases/releases';
  let menuOpen = false;
  let reduceMotion = false;
  let motionPaused = false;
  let heroElement;
  let version = 'Latest release';
  let assetLabel = 'Notchy.dmg · Universal Mac app';
  let releaseStatus = 'loading';
  let openFaqs = new Set();
  let downloadTab = 'download';

  const features = [
    {
      tab: 'clipboard',
      icon: 'clipboard',
      label: 'A better memory',
      title: 'Copy once. Keep the useful bits.',
      text: 'Text, links, images, code, colors and files, all in one visual history. Find the clip you need, paste it back, or drag it straight into another app.',
      chips: ['Visual history', 'Filter by type', 'Drag to reuse']
    },
    {
      tab: 'shelf',
      icon: 'shelf',
      label: 'A little space for everything',
      title: 'Drop it here. Pick it up anywhere.',
      text: 'Give your files a temporary home at the top of your screen. Drop them into the shelf, preview with Quick Look, share with AirDrop, and keep moving.',
      chips: ['File shelf', 'Quick Look', 'AirDrop']
    },
    {
      tab: 'home',
      icon: 'home',
      label: 'Your day, at a glance',
      title: 'One small place. Your whole day.',
      text: 'Your music, weather, calendar and reminders come together in Home. Check what’s next without opening another window or losing your place.',
      chips: ['Now playing', 'Weather', 'Calendar & reminders']
    },
    {
      tab: 'timer',
      icon: 'timer',
      label: 'Make a little room for focus',
      title: 'Set a timer. Find your flow.',
      text: 'Start a focused session and let the countdown live beside the notch. Your time stays visible while the rest of your screen stays yours.',
      chips: ['Quick presets', 'Live countdown', 'Start, pause, reset']
    },
    {
      tab: 'stats',
      icon: 'stats',
      label: 'A pulse on your Mac',
      title: 'Know what’s happening under the hood.',
      text: 'Keep an eye on CPU, memory, GPU, network and disk activity. A quick glance tells you how your Mac is doing, without a dashboard taking over your desktop.',
      chips: ['System stats', 'Live graphs', 'At-a-glance monitoring']
    },
    {
      tab: 'notes',
      icon: 'notes',
      label: 'Catch the thought',
      title: 'Good ideas don’t wait for a new window.',
      text: 'A quick thought, a small checklist, the thing you’ll forget in five minutes. Keep a note right in the notch and get back to what you were doing.',
      chips: ['Quick notes', 'Always close by', 'Less app switching']
    },
    {
      tab: 'face',
      icon: 'face',
      label: 'Personal stays personal',
      title: 'Your clipboard. For your eyes.',
      text: 'Clips that look like passwords or keys aren’t kept unless you choose to, and the ones you keep stay hidden until Face Check confirms it’s you with your Mac’s camera. Face data stays on your Mac.',
      chips: ['Sensitive clip detection', 'Local face processing', 'Protected actions'],
      id: 'privacy'
    },
    {
      tab: 'ai',
      icon: 'sparkles',
      label: 'Keep your coding flow',
      title: 'A little more context. Right on top.',
      text: 'Keep your Claude Code session context and plan usage in view, with a dedicated chat just a click away. Requires Claude Code installed and signed in on your Mac.',
      chips: ['Session context', 'Plan usage', 'Tool-free chat']
    }
  ];
  const benefits = [
    {
      icon: 'paint-brush',
      title: 'Designers',
      text: 'Keep colors, design ideas, screenshots and the assets for your next great idea within reach.'
    },
    {
      icon: 'code-block',
      title: 'Developers',
      text: 'Bring back a command, watch your system stats, and keep an eye on your coding session.'
    },
    {
      icon: 'pencil-line',
      title: 'Creators',
      text: 'Save the thought, find the file, control the music. Spend more time making, less time switching.'
    },
    {
      icon: 'calendar-check',
      title: 'Busy days',
      text: 'Meetings, reminders, the weather and a moment to focus, all without leaving your work.'
    },
    {
      icon: 'browsers',
      title: 'Multitaskers',
      text: 'A home for everything you’re moving between apps. Your workflow, with a little less friction.'
    },
    {
      icon: 'laptop',
      title: 'Your everyday Mac',
      text: 'Copied addresses, useful links, favorite tracks and quick notes. Small things that add up.'
    }
  ];
  const chips = [
    ['music', 'Music'],
    ['clipboard', 'Clipboard history'],
    ['shelf', 'File shelf'],
    ['timer', 'Timer'],
    ['stats', 'System stats'],
    ['notes', 'Notes'],
    ['calendar', 'Calendar'],
    ['sun', 'Weather'],
    ['face', 'Face Check'],
    ['sparkles', 'AI tools'],
    ['volume', 'Volume & brightness'],
    ['lock', 'Local clipboard']
  ];
  const faqs = [
    [
      'What is Notchy?',
      'Notchy is a native macOS menu-bar app that turns the top of your screen into a useful island. It brings together live activities, clipboard history, a file shelf, timers, notes, system stats and more.'
    ],
    [
      'Does my Mac need a notch?',
      'No. On a MacBook with a notch, the island grows out of it. On other displays, Notchy draws its own island at the top of the screen.'
    ],
    [
      'Which Macs does it work on?',
      'Notchy requires macOS 14 Sonoma or later. The download includes support for Apple silicon and Intel Macs.'
    ],
    [
      'Where is my clipboard history stored?',
      'Your clipboard history is stored locally on your Mac. No account is required and Notchy does not upload what you copy. A few features go online: the weather, the AI tools through Claude Code, album art and track details for the song that is playing, and the check for updates.'
    ],
    [
      'What is Face Check?',
      'Face Check uses your Mac’s camera to check an enrolled face before revealing protected clips. Camera images and face data stay on your Mac. It is an in-app privacy feature, not Apple Face ID or a way to unlock macOS, and it cannot guarantee rejection of every photo or video replay.'
    ],
    [
      'Why can’t macOS verify Notchy?',
      'Notchy is not notarized by Apple yet. After trying to open it, go to System Settings → Privacy & Security and choose Open Anyway. You may need to repeat this and grant permissions again after an update.'
    ],
    [
      'How do updates work?',
      'Notchy checks for new releases every 30 minutes. An update appears under the notch and in a notification. Download the new disk image, then drag the new copy into Applications.'
    ],
    [
      'Does it work in fullscreen?',
      'Yes. Notchy stays across Spaces and can appear above fullscreen apps. You can also choose to retract it while a fullscreen app is active or hide it from screen recordings.'
    ],
    [
      'What do the AI tools need?',
      'Claude Code must be installed and signed in on your Mac. Notchy reads session information for its context display. Its dedicated chat runs in tool-free mode, without file access.'
    ],
    [
      'What permissions will it ask for?',
      'Permissions depend on the features you use: Accessibility for pasting and media keys, Calendar and Reminders access for your agenda, Location for weather, Automation for music apps, the camera for Face Check, and notifications.'
    ]
  ];
  function toggleFaq(index) {
    const next = new Set(openFaqs);
    next.has(index) ? next.delete(index) : next.add(index);
    openFaqs = next;
  }
  function closeMenu() {
    menuOpen = false;
  }

  onMount(() => {
    const media = window.matchMedia('(prefers-reduced-motion: reduce)');
    const updatePreference = () => {
      reduceMotion = media.matches;
      scroll();
    };
    let frame = 0;
    const updateParallax = () => {
      frame = 0;
      if (!heroElement) return;
      const progress =
        reduceMotion || motionPaused
          ? 0
          : Math.max(0, Math.min(1, window.scrollY / heroElement.offsetHeight));
      heroElement.style.setProperty('--hero-progress', String(progress));
    };
    const scroll = () => {
      if (!frame) frame = requestAnimationFrame(updateParallax);
    };
    updatePreference();
    media.addEventListener('change', updatePreference);
    window.addEventListener('scroll', scroll, { passive: true });
    window.addEventListener('resize', scroll, { passive: true });
    const onKey = (event) => {
      if (event.key === 'Escape') menuOpen = false;
    };
    window.addEventListener('keydown', onKey);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 7000);
    fetch('https://api.github.com/repos/Mehdidjah/notchy-releases/releases/latest', {
      signal: controller.signal,
      headers: { Accept: 'application/vnd.github+json' }
    })
      .then((response) => {
        if (!response.ok) throw new Error('Release metadata unavailable');
        return response.json();
      })
      .then((release) => {
        if (release.tag_name) version = `Version ${String(release.tag_name).replace(/^v/i, '')}`;
        const asset = release.assets?.find((item) => item.name.toLowerCase().endsWith('.dmg'));
        if (asset) assetLabel = `${asset.name} · ${Math.round(asset.size / 1e6)} MB · Universal`;
        releaseStatus = 'ready';
      })
      .catch(() => {
        releaseStatus = 'fallback';
      })
      .finally(() => clearTimeout(timeout));
    return () => {
      window.removeEventListener('scroll', scroll);
      window.removeEventListener('resize', scroll);
      window.removeEventListener('keydown', onKey);
      media.removeEventListener('change', updatePreference);
      cancelAnimationFrame(frame);
      clearTimeout(timeout);
      controller.abort();
    };
  });
  $: if (typeof document !== 'undefined')
    document.documentElement.dataset.motion = motionPaused ? 'paused' : 'running';
</script>

<a class="skip-link" href="#main-content">Skip to content</a>
<nav class:menu-open={menuOpen} class="site-nav" aria-label="Main navigation">
  <a class="brand" href="#top" onclick={closeMenu}
    ><img src="/assets/img/icon-256.png" alt="" width="30" height="30" /><span>Notchy</span></a
  >
  <div class="nav-links" id="main-menu">
    <a href="#features" onclick={closeMenu}>Features</a><a href="#live" onclick={closeMenu}
      >Live activities</a
    ><a href="#privacy" onclick={closeMenu}>Privacy</a><a href="#faq" onclick={closeMenu}>FAQ</a><a
      href={releases}
      target="_blank"
      rel="noreferrer">Updates<Icon name="external" size={10} /></a
    >
  </div>
  <a class="button button-white nav-download" href={download}
    ><Icon name="apple" size={15} /><span>Download</span></a
  >
  <button
    class="menu-toggle"
    aria-label={menuOpen ? 'Close navigation' : 'Open navigation'}
    aria-expanded={menuOpen}
    aria-controls="main-menu"
    onclick={() => (menuOpen = !menuOpen)}><Icon name={menuOpen ? 'x' : 'menu'} size={21} /></button
  >
</nav>

<main id="main-content">
  <header class="hero-section" id="top" bind:this={heroElement}>
    <div class="hero-landscape" aria-hidden="true"></div>
    <div class="hero-sky" aria-hidden="true"></div>
    <div class="hero-content container">
      <div class="hero-copy">
        <p class="eyebrow hero-enter"><Icon name="apple" size={23} /> Dynamic Island for Mac</p>
        <h1 aria-label="Your notch, finally useful.">
          {#each ['Your notch,', 'finally useful.'] as line, lineIndex}<span
              class:serif={lineIndex === 1}
              class="headline-line"
              aria-hidden="true"
              >{#each Array.from(line) as letter, i}<span
                  class="headline-char"
                  style={`--char-index:${i + lineIndex * 11}`}
                  >{letter === ' ' ? '\u00a0' : letter}</span
                >{/each}</span
            >{/each}
        </h1>
        <p class="hero-description hero-enter">
          Notchy brings your music, clipboard, files, notes, timers, and system stats into one
          beautiful island, so you can find what you need, stay in focus, and get back to doing what
          you love.
        </p>
        <a class="button button-black button-large hero-enter" href={download}
          ><Icon name="apple" size={21} /> Download for macOS</a
        >
        <div class="hero-meta hero-enter">
          <span>No account needed</span><span>Local clipboard</span><span>macOS 14.0 or later</span>
        </div>
      </div>
      <div class="hero-device" use:reveal={{ delay: 1000, threshold: 0.35 }}>
        <HeroStage />
      </div>
    </div>
    <img
      class="hero-foreground"
      src="/assets/img/foreground.webp"
      alt=""
      width="1672"
      height="941"
      fetchpriority="high"
      aria-hidden="true"
    />
  </header>

  <section class="trust-strip container" aria-label="Made for your Mac">
    <div><Icon name="apple" size={21} /><span>Native macOS app</span></div>
    <div><Icon name="lock" size={20} /><span>Your clipboard stays yours</span></div>
    <div><Icon name="cursor" size={20} /><span>Always within reach</span></div>
  </section>

  <section class="section container feature-section" id="features">
    <div class="section-intro" use:reveal>
      <span class="section-label">Small space. So many possibilities.</span>
      <h2>Everything you need,<br />right under the notch.</h2>
      <p>
        Less jumping between apps. More getting things done. A quiet little home for everything you
        reach for throughout the day.
      </p>
    </div>
    <div class="feature-chips" use:reveal>
      {#each chips as [icon, label]}<span><Icon name={icon} size={15} />{label}</span>{/each}
    </div>
    <div class="feature-stack">
      <article class="feature-card" id="live" use:reveal>
        <div class="feature-copy">
          <h3>Little things. Happening live.</h3>
          <p>
            Your next track, a ticking timer, a meeting about to start. Live activities appear
            beside the notch when they matter, then quietly tuck themselves away.
          </p>
        </div>
        <LiveActivities />
      </article>
      {#each features as feature, i}
        <article class="feature-card" id={feature.id} use:reveal={{ threshold: 0.12 }}>
          <div class="feature-copy">
            <h3>{feature.title}</h3>
            <p>{feature.text}</p>
          </div>
          <DeviceStage tab={feature.tab} />
          <div class="feature-footnotes">
            {#each feature.chips as chip}<span><Icon name="check" size={13} />{chip}</span>{/each}
          </div>
        </article>
        {#if i === 1}<div class="editorial-break" use:reveal>
            <img src="/assets/img/icon-256.png" alt="" width="48" height="48" />
            <p>A little less switching.<br /><em>A lot more flow.</em></p>
            <span>Made for the way you already work.</span>
          </div>{/if}
      {/each}
      <div class="two-card-grid">
        <article class="small-card" use:reveal>
          <h3>Feels right at home.</h3>
          <p>
            Hover to peek. Click to open. Swipe to tuck it away. Familiar gestures, soft springs and
            a shape that belongs on your Mac.
          </p>
          <div class="gesture-art" aria-hidden="true">
            <div class="gesture-notch"></div>
            <div class="cursor-bubble"><Icon name="cursor" size={28} /></div>
            <span>Go on. Get closer.</span>
          </div>
        </article>
        <article class="small-card" use:reveal={{ delay: 100 }}>
          <h3>Your notch. Your way.</h3>
          <p>
            Keep the tabs you use, hide the ones you don’t. Choose how Notchy behaves in fullscreen
            and while recording your screen.
          </p>
          <div class="settings-art" aria-label="Illustration of customizable settings">
            <div>
              <Icon name="cursor" size={18} /> Open on hover <span class="toggle on"></span>
            </div>
            <div>
              <Icon name="camera" size={18} /> Hide from screenshots and recordings
              <span class="toggle on"></span>
            </div>
            <div>
              <Icon name="moon" size={18} /> Hide in fullscreen <span class="toggle"></span>
            </div>
          </div>
        </article>
      </div>
    </div>
  </section>

  <section class="section container benefits-section">
    <div class="section-intro" use:reveal>
      <span class="section-label">For whatever your day looks like</span>
      <h2>A little upgrade.<br />For every kind of day.</h2>
      <p>
        From your first idea to your last open tab, Notchy keeps the useful things close and the
        distractions out of the way.
      </p>
    </div>
    <div class="benefits-grid">
      {#each benefits as item, i}<article class="benefit-card" use:reveal={{ delay: (i % 3) * 80 }}>
          <span class="benefit-icon" aria-hidden="true"
            ><img
              src={`/assets/icons/benefits/${item.icon}.svg`}
              alt=""
              width="24"
              height="24"
              decoding="async"
            /></span
          >
          <h3>{item.title}</h3>
          <p>{item.text}</p>
        </article>{/each}
    </div>
  </section>

  <section class="download-section" id="download">
    <div class="section-intro container" use:reveal>
      <span class="section-label">A better place for the little things</span>
      <h2>One download.<br /><em>Every feature.</em></h2>
      <p>Make yourself at home at the top of your Mac.</p>
    </div>
    <div class="download-stage">
      <div class="download-scenery" aria-hidden="true"></div>
      <div class="download-card" use:reveal={{ threshold: 0.25 }}>
        <div class="download-notch">
          <img src="/assets/img/icon-256.png" alt="" width="30" height="30" /><span
            >Notchy for macOS</span
          >
        </div>
        <div class="download-tabs" data-active={downloadTab} role="tablist" aria-label="Get Notchy">
          <button
            role="tab"
            id="download-choice"
            aria-selected={downloadTab === 'download'}
            aria-controls="download-panel"
            tabindex={downloadTab === 'download' ? 0 : -1}
            onclick={() => (downloadTab = 'download')}
            onkeydown={(e) => {
              if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
                downloadTab = 'install';
                document.getElementById('install-choice')?.focus();
              }
            }}>The app</button
          ><button
            role="tab"
            id="install-choice"
            aria-selected={downloadTab === 'install'}
            aria-controls="install-panel"
            tabindex={downloadTab === 'install' ? 0 : -1}
            onclick={() => (downloadTab = 'install')}
            onkeydown={(e) => {
              if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
                downloadTab = 'download';
                document.getElementById('download-choice')?.focus();
              }
            }}>Getting started</button
          >
        </div>
        {#if downloadTab === 'download'}<div
            id="download-panel"
            role="tabpanel"
            aria-labelledby="download-choice"
            class="download-panel"
          >
            <img
              class="download-app-icon"
              src="/assets/img/icon-256.png"
              alt="Notchy app icon"
              width="84"
              height="84"
            />
            <h3>Hello, Notchy.</h3>
            <p class="release-version" aria-live="polite">{version}</p>
            <ul class="download-checks">
              <li>
                <Icon name="check-circle" size={24} strokeWidth={1.5} /> macOS 14 Sonoma or later
              </li>
              <li>
                <Icon name="check-circle" size={24} strokeWidth={1.5} /> Apple silicon and Intel
              </li>
              <li>
                <Icon name="check-circle" size={24} strokeWidth={1.5} /> Every feature in one app
              </li>
              <li>
                <Icon name="check-circle" size={24} strokeWidth={1.5} /> Built-in update notifications
              </li>
              <li><Icon name="check-circle" size={24} strokeWidth={1.5} /> No account required</li>
            </ul>
            <a class="button button-black button-large" href={download}
              ><Icon name="apple" size={20} /> Download for macOS</a
            >
            <p class="download-meta">{assetLabel}</p>
            {#if releaseStatus === 'fallback'}<p class="metadata-fallback">
                Release details are unavailable. Check GitHub for download availability.
              </p>{/if}
          </div>
        {:else}<div
            id="install-panel"
            role="tabpanel"
            aria-labelledby="install-choice"
            class="download-panel install-preview"
          >
            <span class="install-illustration"
              ><Icon name="download" size={42} /><Icon name="arrow-right" size={25} /><Icon
                name="shelf"
                size={42}
              /></span
            >
            <h3>Just drag it in.</h3>
            <p>Open the disk image, then drag Notchy into Applications.</p>
            <p class="install-warning">
              <Icon name="shield" size={20} /> Notchy is not notarized by Apple yet. You’ll need to choose
              Open Anyway in Privacy & Security.
            </p>
            <a class="button button-black button-large" href="#install"
              >View installation steps<Icon name="arrow-right" size={17} /></a
            >
          </div>{/if}
      </div>
    </div>
    <p class="download-note">
      A native app. A local clipboard. A little more breathing room.<br /><a
        href={releases}
        target="_blank"
        rel="noreferrer">Read the release notes<Icon name="external" size={12} /></a
      >
    </p>
  </section>

  <section class="install-section container" id="install" use:reveal>
    <div>
      <span class="section-label">A quick heads-up</span>
      <h3>First time opening Notchy?</h3>
      <p>
        Notchy isn’t notarized by Apple yet, so macOS asks you to allow it. Only continue if you
        trust the download source.
      </p>
      <span class="install-note"
        >After updates, you may need to repeat these steps and grant permissions again.</span
      >
    </div>
    <ol>
      <li>
        <span>1</span>
        <p>Open Notchy from Applications. If macOS can’t verify it, dismiss the alert.</p>
      </li>
      <li>
        <span>2</span>
        <p>Go to <strong>System Settings → Privacy & Security</strong> and scroll down.</p>
      </li>
      <li>
        <span>3</span>
        <p>Choose <strong>Open Anyway</strong>, authenticate when prompted, and confirm.</p>
      </li>
    </ol>
  </section>

  <section class="section container faq-section" id="faq">
    <div class="section-intro" use:reveal>
      <h2>A few things<br />you might be wondering.</h2>
      <p>Everything you need to know before Notchy makes itself at home on your Mac.</p>
    </div>
    <div class="faq-grid">
      {#each [0, 1] as column}<div class="faq-column">
          {#each faqs.slice(column * 5, column * 5 + 5) as faq, i}{@const index = column * 5 + i}
            <article class:open={openFaqs.has(index)} class="faq-item">
              <h3>
                <button
                  aria-expanded={openFaqs.has(index)}
                  aria-controls={`faq-${index}`}
                  id={`faq-button-${index}`}
                  onclick={() => toggleFaq(index)}
                  ><Icon name={openFaqs.has(index) ? 'minus' : 'plus'} size={17} /><span
                    >{faq[0]}</span
                  ></button
                >
              </h3>
              {#if openFaqs.has(index)}<div
                  class="faq-answer"
                  id={`faq-${index}`}
                  role="region"
                  aria-labelledby={`faq-button-${index}`}
                  transition:slide={{ duration: reduceMotion || motionPaused ? 0 : 280 }}
                >
                  <p>{faq[1]}</p>
                  {#if index === 5}<a href="#install"
                      >See the installation steps <Icon name="arrow-right" size={13} /></a
                    >{/if}
                </div>{/if}
            </article>{/each}
        </div>{/each}
    </div>
  </section>

  <section class="closing-section container" use:reveal>
    <img src="/assets/img/icon-256.png" alt="" width="64" height="64" />
    <h2>Your Mac has a notch.<br /><em>Give it a little purpose.</em></h2>
    <a class="button button-black button-large" href={download}
      ><Icon name="apple" size={20} /> Download for macOS</a
    ><span>macOS 14 or later</span>
  </section>
</main>

<footer class="site-footer">
  <div class="footer-content container">
    <div class="footer-about">
      <a href="#top" class="brand"
        ><img src="/assets/img/icon-256.png" alt="" width="32" height="32" /><span>Notchy</span
        ><small>macOS app</small></a
      >
      <p class="footer-headline">Your notch,<br /><em>finally useful.</em></p>
      <p class="footer-description">
        A little home for your music, clipboard, files and focus. Right where you need it.
      </p>
      <a class="button button-white" href={download}
        ><Icon name="apple" size={17} /> Download for macOS</a
      >
      <p class="copyright">© {new Date().getFullYear()} Notchy. Made for your Mac.</p>
      <p class="trademarks">
        Apple, Mac, macOS and AirDrop are trademarks of Apple Inc. Spotify is a trademark of Spotify
        AB. Claude and Claude Code are trademarks of Anthropic. Notchy is not affiliated with or
        endorsed by them.
      </p>
    </div>
    <div class="footer-links">
      <h3>Explore</h3>
      <a href="#features">Features</a><a href="#live">Live activities</a><a href="#privacy"
        >Privacy</a
      ><a href="#faq">FAQ</a>
    </div>
    <div class="footer-links">
      <h3>Get Notchy</h3>
      <a href={download}>Download</a><a href="#install">Installation help</a><a
        href={releases}
        target="_blank"
        rel="noreferrer">Release notes<Icon name="external" size={12} /></a
      ><button
        class="motion-toggle"
        aria-pressed={motionPaused}
        onclick={() => {
          motionPaused = !motionPaused;
          heroElement?.style.setProperty('--hero-progress', '0');
        }}
        ><Icon name={motionPaused ? 'play' : 'pause'} size={13} />{motionPaused
          ? 'Resume decorative motion'
          : 'Pause decorative motion'}</button
      >
    </div>
  </div>
  <div class="footer-wordmark container" aria-hidden="true">Notchy.</div>
</footer>
