<script>
  import { onMount } from 'svelte';
  import { flip } from 'svelte/animate';
  import { cubicOut } from 'svelte/easing';
  import Icon from './Icon.svelte';

  const apps = {
    safari: { name: 'Safari', icon: '/assets/macos/safari.png' },
    photos: { name: 'Photos', icon: '/assets/macos/photos.png' },
    notes: { name: 'Notes', icon: '/assets/macos/notes.png' },
    messages: { name: 'Messages', icon: '/assets/macos/messages.png' },
    finder: { name: 'Finder', icon: '/assets/macos/finder.png' }
  };

  const categories = [
    { id: 'history', label: 'History' },
    { id: 'text', label: 'Text' },
    { id: 'link', label: 'Links' },
    { id: 'image', label: 'Images' },
    { id: 'color', label: 'Colors' },
    { id: 'code', label: 'Code' }
  ];

  const kindNames = {
    text: 'Text',
    link: 'Link',
    image: 'Image',
    color: 'Color',
    code: 'Code'
  };

  const clips = [
    {
      id: 'clip-note',
      kind: 'text',
      app: 'notes',
      time: 'Now',
      timeLong: 'just now',
      title: 'Meeting note',
      body: 'Ship the onboarding tweaks Friday, then review feedback Monday.'
    },
    {
      id: 'clip-photo',
      kind: 'image',
      app: 'photos',
      time: '2m',
      timeLong: '2 minutes ago',
      title: 'Wallpaper',
      src: '/assets/img/wallpaper.webp'
    },
    {
      id: 'clip-link',
      kind: 'link',
      app: 'safari',
      time: '6m',
      timeLong: '6 minutes ago',
      title: 'studio.example',
      body: '/guides/keyboard-shortcuts'
    },
    {
      id: 'clip-color',
      kind: 'color',
      app: 'finder',
      time: '11m',
      timeLong: '11 minutes ago',
      title: '#0080FF',
      body: 'Accent blue'
    },
    {
      id: 'clip-address',
      kind: 'text',
      app: 'messages',
      time: '18m',
      timeLong: '18 minutes ago',
      title: 'Address',
      body: '48 Harbor Lane, Suite 3, Portland, OR 97209'
    },
    {
      id: 'clip-code',
      kind: 'code',
      app: 'notes',
      time: '34m',
      timeLong: '34 minutes ago',
      title: 'Shortcode',
      body: 'git switch -c polish'
    },
    {
      id: 'clip-landscape',
      kind: 'image',
      app: 'safari',
      time: '1h',
      timeLong: '1 hour ago',
      title: 'Landscape',
      src: '/assets/img/landscape.webp'
    },
    {
      id: 'clip-route',
      kind: 'link',
      app: 'messages',
      time: '2h',
      timeLong: '2 hours ago',
      title: 'maps.example',
      body: '/route?from=office'
    }
  ];

  let query = $state('');
  let category = $state('history');
  let compact = $state(false);
  let selectedId = $state(null);
  let statusText = $state('');
  let reduceMotion = $state(false);
  let dragging = $state(false);
  let strip = $state();

  let statusTimer;

  const normalizedQuery = $derived(query.trim().toLowerCase());

  function matchesQuery(clip, q) {
    if (!q) return true;
    const haystack = [clip.title, clip.body ?? '', apps[clip.app].name, kindNames[clip.kind]]
      .join(' ')
      .toLowerCase();
    return haystack.includes(q);
  }

  const searched = $derived(clips.filter((clip) => matchesQuery(clip, normalizedQuery)));

  const counts = $derived(
    Object.fromEntries(
      categories.map((c) => [
        c.id,
        c.id === 'history' ? searched.length : searched.filter((clip) => clip.kind === c.id).length
      ])
    )
  );

  const visible = $derived(
    category === 'history' ? searched : searched.filter((clip) => clip.kind === category)
  );

  const showingAll = $derived(category === 'history' && normalizedQuery === '');
  const duration = $derived(reduceMotion ? 0 : 400);

  function slideIn(node, { duration: ms = 400 } = {}) {
    return {
      duration: ms,
      easing: cubicOut,
      css: (t, u) => `opacity: ${t}; transform: translateX(${u * 30}px);`
    };
  }

  function clearSearch() {
    query = '';
  }

  function showAll() {
    query = '';
    category = 'history';
  }

  function selectClip(clip) {
    selectedId = clip.id;
    statusText = '';
    clearTimeout(statusTimer);
    // Re-set on the next frame so repeated selections are announced again.
    requestAnimationFrame(() => {
      statusText = 'Sample selected';
      statusTimer = setTimeout(() => {
        statusText = '';
      }, 1600);
    });
  }

  function onSearchKeydown(event) {
    if (event.key === 'Escape' && query) {
      event.preventDefault();
      clearSearch();
    }
  }

  function clipLabel(clip) {
    const detail =
      clip.kind === 'image' ? clip.title : [clip.title, clip.body].filter(Boolean).join(', ');
    return `${kindNames[clip.kind]} from ${apps[clip.app].name}: ${detail}, copied ${clip.timeLong}`;
  }

  // Bring the strip back to the start whenever the result set changes.
  $effect(() => {
    category;
    normalizedQuery;
    if (strip) strip.scrollLeft = 0;
  });

  // Pointer drag-to-scroll for mouse and pen; touch keeps native panning.
  $effect(() => {
    const el = strip;
    if (!el) return;

    const threshold = 4;
    let pointerId = null;
    let startX = 0;
    let startScroll = 0;
    let moved = false;
    let suppressClick = false;

    const reset = () => {
      if (pointerId !== null && el.hasPointerCapture?.(pointerId)) {
        el.releasePointerCapture(pointerId);
      }
      pointerId = null;
      moved = false;
      dragging = false;
    };

    const onPointerDown = (event) => {
      suppressClick = false;
      if (event.pointerType === 'touch' || event.button !== 0) return;
      pointerId = event.pointerId;
      startX = event.clientX;
      startScroll = el.scrollLeft;
      moved = false;
    };

    const onPointerMove = (event) => {
      if (pointerId === null || event.pointerId !== pointerId) return;
      const dx = event.clientX - startX;
      if (!moved && Math.abs(dx) > threshold) {
        moved = true;
        dragging = true;
        el.setPointerCapture?.(pointerId);
      }
      if (moved) {
        event.preventDefault();
        el.scrollLeft = startScroll - dx;
      }
    };

    const onPointerEnd = (event) => {
      if (pointerId === null || event.pointerId !== pointerId) return;
      if (moved) suppressClick = true;
      reset();
    };

    const onClickCapture = (event) => {
      // Keyboard activations report detail 0 and are never swallowed.
      if (suppressClick && event.detail !== 0) {
        event.preventDefault();
        event.stopPropagation();
      }
      suppressClick = false;
    };

    const onDragStart = (event) => event.preventDefault();

    el.addEventListener('pointerdown', onPointerDown);
    el.addEventListener('pointermove', onPointerMove);
    el.addEventListener('pointerup', onPointerEnd);
    el.addEventListener('pointercancel', onPointerEnd);
    el.addEventListener('lostpointercapture', onPointerEnd);
    el.addEventListener('click', onClickCapture, true);
    el.addEventListener('dragstart', onDragStart);

    return () => {
      el.removeEventListener('pointerdown', onPointerDown);
      el.removeEventListener('pointermove', onPointerMove);
      el.removeEventListener('pointerup', onPointerEnd);
      el.removeEventListener('pointercancel', onPointerEnd);
      el.removeEventListener('lostpointercapture', onPointerEnd);
      el.removeEventListener('click', onClickCapture, true);
      el.removeEventListener('dragstart', onDragStart);
    };
  });

  onMount(() => {
    const media = window.matchMedia('(prefers-reduced-motion: reduce)');
    const update = () => {
      reduceMotion = media.matches;
    };
    update();
    media.addEventListener('change', update);
    return () => {
      media.removeEventListener('change', update);
      clearTimeout(statusTimer);
    };
  });
</script>

<section class="shelf" class:compact aria-label="Interactive clipboard shelf preview">
  <div class="toolbar">
    <label class="search">
      <Icon name="search" size={14} />
      <input
        type="search"
        bind:value={query}
        onkeydown={onSearchKeydown}
        placeholder="Search sample clips"
        aria-label="Search sample clips"
        autocomplete="off"
        spellcheck="false"
      />
    </label>

    <p class="status" class:visible={statusText !== ''} role="status" aria-live="polite">
      {#if statusText}
        <Icon name="check" size={12} strokeWidth={2.2} />
        {statusText}
      {/if}
    </p>

    <div class="actions">
      <button
        type="button"
        class="round"
        onclick={clearSearch}
        disabled={query === ''}
        aria-label="Clear search"
        title="Clear search"
      >
        <Icon name="x" size={12} strokeWidth={2} />
      </button>
      <button
        type="button"
        class="round"
        onclick={showAll}
        disabled={showingAll}
        aria-label="Show all clips"
        title="Show all clips"
      >
        <Icon name="layers" size={12} strokeWidth={2} />
      </button>
      <button
        type="button"
        class="round"
        onclick={() => (compact = !compact)}
        aria-pressed={compact}
        aria-label="Compact view"
        title="Switch compact view"
      >
        <Icon name="menu" size={12} strokeWidth={2} />
      </button>
    </div>
  </div>

  <div class="pills" role="group" aria-label="Clip categories">
    {#each categories as c (c.id)}
      <button
        type="button"
        class="pill"
        class:active={category === c.id}
        aria-pressed={category === c.id}
        onclick={() => (category = c.id)}
      >
        {c.label}
        <span class="count">{counts[c.id]}</span>
      </button>
    {/each}
  </div>

  <div class="viewport">
    {#if visible.length === 0}
      <div class="empty">
        <Icon name="search" size={16} />
        <span>No clips match{normalizedQuery ? ` “${query.trim()}”` : ' this filter'}</span>
        <button type="button" class="reset" onclick={showAll}>Show all</button>
      </div>
    {/if}

    <ul class="strip" class:dragging bind:this={strip} aria-label="Sample clips">
      {#each visible as clip (clip.id)}
        <li class="item" in:slideIn={{ duration }} animate:flip={{ duration, easing: cubicOut }}>
          <button
            type="button"
            class="card kind-{clip.kind}"
            class:selected={selectedId === clip.id}
            aria-pressed={selectedId === clip.id}
            aria-label={clipLabel(clip)}
            onclick={() => selectClip(clip)}
          >
            {#if clip.kind === 'image'}
              <img class="thumb" src={clip.src} alt="" draggable="false" loading="lazy" />
            {:else if clip.kind === 'color'}
              <span class="content">
                <span class="hex">{clip.title}</span>
                <span class="sub">{clip.body}</span>
              </span>
            {:else if clip.kind === 'link'}
              <span class="content">
                <span class="link-head">
                  <Icon name="link" size={11} strokeWidth={2} />
                  {clip.title}
                </span>
                <span class="sub">{clip.body}</span>
              </span>
            {:else if clip.kind === 'code'}
              <span class="content">
                <code>{clip.body}</code>
              </span>
            {:else}
              <span class="content">
                <span class="text">{clip.body}</span>
              </span>
            {/if}

            <span class="footer">
              <img
                class="app-icon"
                src={apps[clip.app].icon}
                alt=""
                width="14"
                height="14"
                draggable="false"
              />
              <span class="time">{clip.time}</span>
            </span>
          </button>
        </li>
      {/each}
    </ul>
  </div>
</section>

<style>
  .shelf {
    --spring: cubic-bezier(0.34, 1.56, 0.64, 1);
    position: relative;
    box-sizing: border-box;
    flex: none;
    width: 700px;
    height: 220px;
    padding: 10px 10px 0;
    background: #000;
    color: #fff;
    border-radius: 0 0 30px 30px;
    font-size: 12px;
    line-height: 1.2;
    -webkit-font-smoothing: antialiased;
  }

  /* Outward curved shoulders that blend the shelf into the top edge. */
  .shelf::before,
  .shelf::after {
    content: '';
    position: absolute;
    top: 0;
    width: 40px;
    height: 40px;
    pointer-events: none;
  }

  .shelf::before {
    left: -40px;
    background: radial-gradient(circle at 0 100%, transparent 39.5px, #000 40px);
  }

  .shelf::after {
    right: -40px;
    background: radial-gradient(circle at 100% 100%, transparent 39.5px, #000 40px);
  }

  .shelf *,
  .shelf *::before,
  .shelf *::after {
    box-sizing: border-box;
  }

  button {
    font: inherit;
    color: inherit;
    border: 0;
    margin: 0;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
  }

  button:focus-visible,
  .search:focus-within {
    outline: 2px solid #0080ff;
    outline-offset: 2px;
  }

  /* Toolbar */
  .toolbar {
    display: flex;
    align-items: center;
    gap: 10px;
    height: 32px;
  }

  .search {
    display: flex;
    align-items: center;
    gap: 7px;
    width: 230px;
    height: 32px;
    padding: 0;
    border-radius: 10px;
    background: transparent;
    color: rgba(255, 255, 255, 0.45);
    cursor: text;
  }

  .search input {
    flex: 1;
    min-width: 0;
    height: 100%;
    padding: 0;
    border: 0;
    outline: none;
    background: transparent;
    color: rgba(255, 255, 255, 0.9);
    font: inherit;
    font-size: 12px;
    appearance: none;
  }

  .search input::placeholder {
    color: rgba(255, 255, 255, 0.45);
  }

  .search input::-webkit-search-cancel-button,
  .search input::-webkit-search-decoration {
    appearance: none;
  }

  .status {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    margin: 0 0 0 auto;
    padding: 0 10px;
    height: 24px;
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.1);
    color: rgba(255, 255, 255, 0.85);
    font-size: 11px;
    white-space: nowrap;
    opacity: 0;
    transform: translateY(-3px);
    transition:
      opacity 0.2s ease,
      transform 0.4s var(--spring);
  }

  .status.visible {
    opacity: 1;
    transform: none;
  }

  .actions {
    display: flex;
    gap: 6px;
  }

  .round {
    display: grid;
    place-items: center;
    width: 26px;
    height: 26px;
    padding: 0;
    border-radius: 50%;
    background: rgba(255, 255, 255, 0.1);
    color: rgba(255, 255, 255, 0.75);
    transition:
      background-color 0.2s ease,
      color 0.2s ease,
      opacity 0.2s ease;
  }

  .round:hover:not(:disabled) {
    background: rgba(255, 255, 255, 0.18);
    color: #fff;
  }

  .round[aria-pressed='true'] {
    background: #fff;
    color: #000;
  }

  .round:disabled {
    opacity: 0.35;
    cursor: default;
  }

  /* Category pills */
  .pills {
    display: flex;
    gap: 6px;
    height: 33px;
    margin-top: 10px;
  }

  .pill {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 33px;
    padding: 0 10px;
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.1);
    color: rgba(255, 255, 255, 0.82);
    font-size: 12px;
    font-weight: 500;
    white-space: nowrap;
    transition:
      background-color 0.2s ease,
      color 0.2s ease;
  }

  .pill:hover:not(.active) {
    background: rgba(255, 255, 255, 0.16);
    color: #fff;
  }

  .pill.active {
    background: #fff;
    color: #000;
  }

  .count {
    font-size: 10.5px;
    font-variant-numeric: tabular-nums;
    opacity: 0.55;
  }

  /* Card strip */
  .viewport {
    position: relative;
    clip-path: inset(0 0 -7px round 0 0 30px 30px);
    height: 110px;
    margin: 18px -10px 0;
  }

  .strip {
    display: flex;
    align-items: center;
    gap: 10px;
    height: 110px;
    margin: 0;
    padding: 5px 10px;
    list-style: none;
    overflow-x: auto;
    overflow-y: hidden;
    overscroll-behavior-x: contain;
    scrollbar-width: none;
    cursor: grab;
    touch-action: pan-x;
  }

  .strip::-webkit-scrollbar {
    display: none;
  }

  .strip.dragging {
    cursor: grabbing;
    user-select: none;
  }

  .strip.dragging .card {
    cursor: grabbing;
  }

  .item {
    flex: none;
  }

  .card {
    position: relative;
    display: block;
    width: 133px;
    height: 100px;
    padding: 0;
    overflow: hidden;
    border-radius: 12px;
    background: #1c1c1e;
    text-align: left;
    cursor: grab;
    box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.06);
    transition:
      transform 0.4s var(--spring),
      box-shadow 0.2s ease;
  }

  .card:hover {
    transform: scale(1.05);
  }

  .card.selected {
    box-shadow:
      inset 0 0 0 2px #fff,
      0 0 0 1px rgba(0, 0, 0, 0.4);
  }

  .card:focus-visible {
    outline-offset: 1px;
  }

  .compact .card {
    width: 100px;
    height: 76px;
  }

  .compact .card .sub {
    display: none;
  }

  .thumb {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    object-fit: cover;
    pointer-events: none;
  }

  .content {
    position: absolute;
    inset: 0 0 24px;
    display: flex;
    flex-direction: column;
    gap: 4px;
    padding: 10px 10px 0;
    overflow: hidden;
  }

  .text {
    display: -webkit-box;
    -webkit-box-orient: vertical;
    -webkit-line-clamp: 3;
    line-clamp: 3;
    overflow: hidden;
    color: rgba(255, 255, 255, 0.92);
    font-size: 11px;
    line-height: 1.35;
  }

  .compact .text {
    -webkit-line-clamp: 2;
    line-clamp: 2;
  }

  .link-head {
    display: flex;
    align-items: center;
    gap: 5px;
    color: #fff;
    font-size: 11.5px;
    font-weight: 600;
    white-space: nowrap;
  }

  .sub {
    overflow: hidden;
    color: rgba(255, 255, 255, 0.55);
    font-size: 10.5px;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .kind-color {
    background: #0080ff;
  }

  .kind-color .hex {
    color: #fff;
    font-family: ui-monospace, 'SF Mono', Menlo, monospace;
    font-size: 13px;
    font-weight: 600;
    letter-spacing: 0.02em;
  }

  .kind-color .sub {
    color: rgba(255, 255, 255, 0.78);
  }

  .kind-code {
    background: #0f1115;
  }

  .kind-code code {
    color: #8cc8ff;
    font-family: ui-monospace, 'SF Mono', Menlo, monospace;
    font-size: 10.5px;
    line-height: 1.4;
    word-break: break-word;
  }

  .footer {
    position: absolute;
    right: 0;
    bottom: 0;
    left: 0;
    display: flex;
    align-items: center;
    gap: 5px;
    height: 26px;
    padding: 0 8px 2px;
    pointer-events: none;
  }

  /* Keeps white footer text legible over photos. */
  .kind-image .footer {
    height: 40px;
    align-items: flex-end;
    padding-bottom: 7px;
    background: linear-gradient(to top, rgba(0, 0, 0, 0.72), rgba(0, 0, 0, 0));
  }

  .app-icon {
    width: 14px;
    height: 14px;
    flex: none;
    object-fit: contain;
  }

  .time {
    color: rgba(255, 255, 255, 0.78);
    font-size: 9.5px;
    font-weight: 500;
    font-variant-numeric: tabular-nums;
    text-shadow: 0 1px 2px rgba(0, 0, 0, 0.35);
  }

  /* No-result state */
  .empty {
    position: absolute;
    inset: 0;
    z-index: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    color: rgba(255, 255, 255, 0.45);
    font-size: 12px;
    pointer-events: none;
  }

  .reset {
    height: 24px;
    padding: 0 10px;
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.1);
    color: rgba(255, 255, 255, 0.85);
    font-size: 11px;
    pointer-events: auto;
  }

  .reset:hover {
    background: rgba(255, 255, 255, 0.18);
  }

  @media (prefers-reduced-motion: reduce) {
    .card,
    .status,
    .round,
    .pill {
      transition: none;
    }

    .card:hover {
      transform: none;
    }
  }
</style>
