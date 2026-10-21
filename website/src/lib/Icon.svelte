<script>
  let { name, size = 20, strokeWidth = 1.7 } = $props();
  const paths = {
    download: 'M12 3v12m-4-4 4 4 4-4M4 16v5h16v-5',
    'arrow-right': 'M4 12h16m-6-6 6 6-6 6',
    check: 'm5 12 4 4L19 6',
    'check-circle': 'M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0M8 12l3 3 5-6',
    plus: 'M12 5v14M5 12h14',
    minus: 'M5 12h14',
    x: 'm6 6 12 12M18 6 6 18',
    menu: 'M4 6h16M4 12h16M4 18h16',
    'chevron-down': 'm6 9 6 6 6-6',
    home: 'm3 10 9-7 9 7M5 9v12h5v-7h4v7h5V9',
    shelf: 'm3 13 3-9h12l3 9v7H3Zm0 0h5l2 3h4l2-3h5',
    clipboard:
      'M9 5H6a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-3M9 2h6v5H9ZM8 12h8M8 16h6',
    timer: 'M9 2h6M12 5v1m6-1 2 2M12 10v4l3 2M20 14a8 8 0 1 1-16 0 8 8 0 0 1 16 0',
    stats: 'M4 3v17h17M7 15l4-5 4 3 5-7',
    notes: 'M5 3h10l4 4v14H5ZM14 3v5h5M8 12h8M8 16h6',
    face: 'M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2M9 9v2m6-2v2m-3-2v4h-1m-2 3q3 2 6 0',
    sparkles:
      'm12 3 2.3 6.7L21 12l-6.7 2.3L12 21l-2.3-6.7L3 12l6.7-2.3ZM4 2v4M2 4h4m13 14v4m-2-2h4',
    music: 'M9 18V6l10-3v13M9 18a3 3 0 1 1-3-3 3 3 0 0 1 3 3m10-2a3 3 0 1 1-3-3 3 3 0 0 1 3 3',
    play: 'm8 4 12 8-12 8Z',
    pause: 'M8 5v14M16 5v14',
    skip: 'm5 5 10 7-10 7ZM19 5v14',
    volume: 'M3 9h4l5-4v14l-5-4H3ZM16 8a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14',
    sun: 'M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1 1m12 12 1 1M5 19l1-1M18 6l1-1',
    calendar: 'M4 5h16v16H4ZM4 10h16M8 2v5m8-5v5M8 14h2m4 0h2m-8 3h2',
    file: 'M5 2h9l5 5v15H5ZM14 2v6h5M8 13h8m-8 4h6',
    image: 'M3 3h18v18H3Zm0 14 5-5 4 4 3-3 6 6M9 8a1 1 0 1 1-2 0 1 1 0 0 1 2 0',
    code: 'm7 6-5 6 5 6m10-12 5 6-5 6M14 3l-4 18',
    link: 'm10 13 4-4m-6 7-1 1a4 4 0 0 1-6-6l4-4a4 4 0 0 1 6 0m2 1 1-1a4 4 0 0 1 6 6l-4 4a4 4 0 0 1-6 0',
    color: 'M12 3s7 7 7 12a7 7 0 0 1-14 0c0-5 7-12 7-12Zm-4 12a4 4 0 0 0 4 4',
    lock: 'M5 10h14v11H5ZM8 10V6a4 4 0 0 1 8 0v4m-4 5v2',
    shield: 'm12 2 9 4v6c0 5-9 10-9 10S3 17 3 12V6ZM8 12l3 3 5-6',
    cpu: 'M6 6h12v12H6ZM9 9h6v6H9ZM9 2v4m6-4v4M9 18v4m6-4v4M2 9h4m-4 6h4m12-6h4m-4 6h4',
    battery: 'M2 6h17v12H2ZM22 10v4M5 9h8v6H5Z',
    headphones: 'M4 15v-3a8 8 0 0 1 16 0v3M3 13h4v8H3Zm14 0h4v8h-4Z',
    moon: 'M20 15A9 9 0 1 1 9 3a7 7 0 0 0 11 12Z',
    camera: 'M3 7h4l2-3h6l2 3h4v14H3ZM16 13a4 4 0 1 1-8 0 4 4 0 0 1 8 0',
    mic: 'M9 6a3 3 0 0 1 6 0v6a3 3 0 0 1-6 0ZM5 11v1a7 7 0 0 0 14 0v-1m-7 8v3m-4 0h8',
    upload: 'M12 16V3m-4 4 4-4 4 4M4 15v6h16v-6',
    trash: 'M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7m4-7v7',
    search: 'M17 10a7 7 0 1 1-14 0 7 7 0 0 1 14 0m-2 5 6 6',
    github:
      'M9 19c-4 1-4-2-6-2m14 5v-4a3 3 0 0 0-.8-2.2c2.8-.3 5.8-1.4 5.8-6.3A5 5 0 0 0 20.6 6 4.6 4.6 0 0 0 20.5 2S19.4 1.7 17 3.4a13 13 0 0 0-7 0C7.6 1.7 6.5 2 6.5 2A4.6 4.6 0 0 0 6.4 6 5 5 0 0 0 5 9.5c0 4.9 3 6 5.8 6.3A3 3 0 0 0 10 18v4',
    globe: 'M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0M3 12h18M12 3c5 5 5 13 0 18-5-5-5-13 0-18Z',
    settings:
      'm10 2-1 3-3 1-3-1-2 4 2 2v3l-2 2 2 4 3-1 3 1 1 3h4l1-3 3-1 3 1 2-4-2-2v-3l2-2-2-4-3 1-3-1-1-3ZM16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0',
    external: 'M14 3h7v7m0-7L10 14M10 3H3v18h18v-7',
    keyboard: 'M2 6h20v13H2ZM6 10h.1m4 0h.1m4 0h.1m4 0h.1M7 15h10',
    cursor: 'm4 2 16 10-8 1-3 8Z',
    layers: 'm12 2 10 5-10 5L2 7Zm-10 10 10 5 10-5M2 17l10 5 10-5',
    eye: 'M2 12S5 5 12 5s10 7 10 7-3 7-10 7S2 12 2 12Zm13 0a3 3 0 1 1-6 0 3 3 0 0 1 6 0',
    mail: 'M3 5h18v14H3Zm0 0 9 8 9-8',
    zap: 'm13 2-9 12h7l-1 8 10-12h-7Z',
    heart: 'M12 21 3 12A6 6 0 0 1 12 4a6 6 0 0 1 9 8Z',
    refresh: 'M20 7a9 9 0 0 0-16 0M20 2v5h-5M4 17a9 9 0 0 0 16 0M4 22v-5h5',
    airdrop:
      'M5 18a10 10 0 1 1 14 0M8 15a6 6 0 1 1 8 0M13 11a1 1 0 1 1-2 0 1 1 0 0 1 2 0m-1 5-4 6h8Z'
  };
</script>

{#if name === 'apple'}
  <span class="native-apple" aria-hidden="true" style={`width:${size}px;height:${size}px`}></span>
{:else}
  <svg
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width={strokeWidth}
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
    focusable="false"
  >
    <path d={paths[name] ?? paths.sparkles} />
  </svg>
{/if}

<style>
  .native-apple {
    display: inline-block;
    flex: none;
    vertical-align: middle;
    background: currentColor;
    mask: url('/assets/macos/apple-logo.png') center / contain no-repeat;
  }
  svg {
    display: inline-block;
    flex: none;
    vertical-align: middle;
  }
</style>
