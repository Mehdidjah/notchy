<script>
  import Icon from './Icon.svelte';
  import { onDestroy } from 'svelte';

  const activities = [
    {
      id: 'music',
      label: 'Music',
      icon: 'music',
      color: '#ff4f8b',
      width: '430px',
      value: 'Golden Hour',
      detail: 'Sample playback · Sunset Tapes'
    },
    {
      id: 'timer',
      label: 'Timer',
      icon: 'timer',
      color: '#ff9e3d',
      width: '350px',
      value: '24:18',
      detail: 'Pomodoro · ready when you are'
    },
    {
      id: 'downloads',
      label: 'Downloads',
      icon: 'download',
      color: '#50a8ff',
      width: '372px',
      value: '72%',
      detail: 'Design-assets.zip · 86 MB remaining'
    },
    {
      id: 'headphones',
      label: 'Headphones',
      icon: 'headphones',
      color: '#a98bff',
      width: '390px',
      value: '82%',
      detail: 'Headphone battery · sample reading'
    },
    {
      id: 'charging',
      label: 'Charging',
      icon: 'battery',
      color: '#7bdc78',
      width: '360px',
      value: '84%',
      detail: 'MacBook Air · 43 min to full'
    },
    {
      id: 'focus',
      label: 'Focus',
      icon: 'moon',
      color: '#6f77ff',
      width: '380px',
      value: 'Deep Work',
      detail: 'Notifications paused until 4:30 PM'
    },
    {
      id: 'camera',
      label: 'Camera',
      icon: 'camera',
      color: '#ff6b5d',
      width: '354px',
      value: 'In use',
      detail: 'FaceTime · camera and mic active'
    },
    {
      id: 'ai',
      label: 'AI context',
      icon: 'sparkles',
      color: '#d477ff',
      width: '405px',
      value: '19%',
      detail: 'Claude Code · sample session context'
    }
  ];

  let active = $state('music');
  let musicPlaying = $state(true);
  let timerRunning = $state(false);
  let seconds = $state(24 * 60 + 18);
  let interval;
  let current = $derived(activities.find((item) => item.id === active) ?? activities[0]);
  let timerText = $derived(
    `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`
  );

  $effect(() => {
    if (timerRunning)
      interval = window.setInterval(() => {
        if (seconds > 0) seconds -= 1;
        if (seconds === 0) timerRunning = false;
      }, 1000);
    return () => {
      if (interval) window.clearInterval(interval);
    };
  });
  onDestroy(() => {
    if (interval) window.clearInterval(interval);
  });

  function selectActivity(id) {
    active = id;
  }
  function toggleTimer() {
    active = 'timer';
    if (seconds === 0) seconds = 24 * 60 + 18;
    timerRunning = !timerRunning;
  }
</script>

<section class="live-activities" aria-label="Interactive live activity preview">
  <div class="heading">
    <p class="eyebrow">Interactive preview <span aria-hidden="true">·</span> sample data</p>
  </div>

  <div class="stage" style={`--accent: ${current.color}`}>
    <div class="ambient ambient-one" aria-hidden="true"></div>
    <div class="ambient ambient-two" aria-hidden="true"></div>
    <div class="notch-wrap">
      <div
        class="live-notch"
        style={`--notch-width: ${current.width}`}
        class:music-active={active === 'music' && musicPlaying}
      >
        <div class="notch-camera" aria-hidden="true"><i></i></div>
        <div class="notch-side left-side">
          <span class="status-icon"><Icon name={current.icon} size={17} strokeWidth={2} /></span>
          {#if active === 'music'}<span class="equalizer" aria-hidden="true"
              ><i></i><i></i><i></i></span
            >{/if}
        </div>
        <div class="notch-copy">
          <strong>{active === 'timer' ? timerText : current.value}</strong><span
            >{active === 'music' ? 'Sunset Tapes · visual preview' : current.label}</span
          >
        </div>
        <div class="notch-side right-side">
          {#if active === 'music'}<button
              class="round-control"
              type="button"
              aria-label={musicPlaying ? 'Pause music' : 'Play music'}
              aria-pressed={musicPlaying}
              onclick={() => (musicPlaying = !musicPlaying)}
              ><Icon name={musicPlaying ? 'pause' : 'play'} size={14} strokeWidth={2.2} /></button
            >
          {:else if active === 'timer'}<button
              class="round-control"
              type="button"
              aria-label={timerRunning ? 'Pause timer' : 'Start timer'}
              aria-pressed={timerRunning}
              onclick={toggleTimer}
              ><Icon name={timerRunning ? 'pause' : 'play'} size={13} strokeWidth={2.2} /></button
            >
          {:else}<span class="status-value"
              >{active === 'downloads'
                ? '72%'
                : active === 'charging'
                  ? '84%'
                  : active === 'camera'
                    ? 'LIVE'
                    : '•'}</span
            >{/if}
        </div>
      </div>
      <p class="activity-description">
        <span style={`background:${current.color}`}></span>{active === 'timer' && timerRunning
          ? 'Pomodoro timer is running'
          : current.detail}
      </p>
    </div>
  </div>

  <div class="activity-grid" aria-label="Choose a live activity">
    {#each activities as item}
      <button
        type="button"
        class:active={active === item.id}
        class="activity-card"
        aria-pressed={active === item.id}
        onclick={() => selectActivity(item.id)}
        style={`--card-accent: ${item.color}`}
      >
        <span class="mini-pill" aria-hidden="true"
          ><Icon name={item.icon} size={12} strokeWidth={2} /><i></i><b
            >{item.id === 'timer' && active === 'timer' ? timerText : item.value}</b
          ></span
        >
        <span class="card-name">{item.label}</span>
      </button>
    {/each}
  </div>
</section>

<style>
  .live-activities {
    width: 100%;
    margin: 0 auto;
    padding: 0;
    color: #171719;
  }
  .heading {
    display: flex;
    justify-content: space-between;
    align-items: end;
    gap: 32px;
    margin-bottom: 25px;
  }
  .eyebrow {
    margin: 0 0 9px;
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    font-weight: 700;
    color: #777;
  }
  .eyebrow span {
    color: #a0a0a0;
    padding: 0 3px;
  }
  .stage {
    height: 252px;
    position: relative;
    overflow: hidden;
    border: 1px solid #e3e2df;
    border-radius: 22px;
    background: #efeeeb url('/assets/img/wallpaper.webp') center 45% / cover;
    box-shadow: 0 12px 28px #2c313314;
  }
  .stage:after {
    content: '';
    position: absolute;
    inset: 0;
    background: linear-gradient(90deg, #fff5, #ffffff12 48%, #ffffff32);
    pointer-events: none;
  }
  .ambient {
    position: absolute;
    border-radius: 999px;
    filter: blur(32px);
    opacity: 0.5;
    background: var(--accent);
    transition: background 0.35s ease;
  }
  .ambient-one {
    width: 180px;
    height: 180px;
    top: -75px;
    left: 8%;
  }
  .ambient-two {
    width: 145px;
    height: 145px;
    bottom: -80px;
    right: 13%;
    opacity: 0.26;
  }
  .notch-wrap {
    position: absolute;
    z-index: 1;
    left: 50%;
    top: 45px;
    transform: translateX(-50%);
    width: min(100% - 38px, 430px);
    text-align: center;
  }
  .live-notch {
    margin-inline: auto;
    height: 78px;
    width: min(100%, var(--notch-width, 430px));
    background: #090909;
    border-radius: 31px;
    display: grid;
    grid-template-columns: 1fr 106px 1fr;
    align-items: center;
    color: white;
    box-shadow: 0 12px 25px #0005;
    transition:
      width 0.42s cubic-bezier(0.2, 0.8, 0.2, 1),
      border-radius 0.32s ease,
      box-shadow 0.32s ease;
  }
  .notch-camera {
    grid-column: 2;
    grid-row: 1;
    height: 26px;
    width: 106px;
    border-radius: 99px;
    background: #020202;
    justify-self: center;
    display: flex;
    justify-content: end;
    align-items: center;
    padding-right: 10px;
    box-sizing: border-box;
    box-shadow: inset 0 1px #272727;
  }
  .notch-camera i {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: #182a28;
    box-shadow: 0 0 0 1px #2c4c48;
  }
  .notch-side {
    display: flex;
    align-items: center;
    gap: 7px;
    padding: 0 17px;
    min-width: 0;
  }
  .left-side {
    grid-column: 1;
    grid-row: 1;
    justify-content: flex-start;
  }
  .right-side {
    grid-column: 3;
    grid-row: 1;
    justify-content: flex-end;
  }
  .status-icon {
    color: var(--accent);
    display: grid;
    place-items: center;
    transition: color 0.3s ease;
  }
  .notch-copy {
    position: absolute;
    left: 50%;
    transform: translateX(-50%);
    top: 85px;
    width: max-content;
    max-width: 260px;
    color: #1c1c1d;
    display: flex;
    flex-direction: column;
    gap: 2px;
    text-shadow: 0 1px #fff8;
  }
  .notch-copy strong {
    font-size: 13px;
    letter-spacing: -0.02em;
  }
  .notch-copy span {
    font-size: 10px;
    color: #57575a;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .status-value {
    font-size: 11px;
    color: #ddd;
    font-weight: 700;
    letter-spacing: 0.02em;
  }
  .round-control {
    width: 28px;
    height: 28px;
    border: 0;
    border-radius: 50%;
    display: grid;
    place-items: center;
    background: #292929;
    color: #fff;
    cursor: pointer;
  }
  .round-control:hover {
    background: #3a3a3a;
  }
  .equalizer {
    height: 15px;
    display: flex;
    align-items: center;
    gap: 2px;
  }
  .equalizer i {
    height: 6px;
    width: 2px;
    border-radius: 2px;
    background: var(--accent);
    animation: equalize 0.7s ease-in-out infinite alternate;
  }
  .equalizer i:nth-child(2) {
    height: 12px;
    animation-delay: -0.3s;
  }
  .equalizer i:nth-child(3) {
    height: 8px;
    animation-delay: -0.55s;
  }
  .equalizer i {
    animation-play-state: paused;
  }
  .music-active .equalizer i {
    animation-play-state: running;
  }
  .activity-description {
    position: absolute;
    top: 137px;
    left: 50%;
    transform: translateX(-50%);
    margin: 0;
    width: max-content;
    max-width: 90%;
    font-size: 11px;
    color: #4d4d4e;
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .activity-description span {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    box-shadow: 0 0 0 3px #fff7;
  }
  .activity-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 9px;
    margin-top: 12px;
  }
  .activity-card {
    min-height: 66px;
    text-align: left;
    border: 1px solid #e5e4e2;
    border-radius: 13px;
    background: #fff;
    padding: 10px 11px;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    gap: 8px;
    color: #3c3c3c;
    cursor: pointer;
    transition:
      transform 0.2s ease,
      border-color 0.2s ease,
      box-shadow 0.2s ease;
  }
  .activity-card:hover {
    transform: translateY(-2px);
    border-color: #bbb;
  }
  .activity-card.active {
    border-color: var(--card-accent);
    box-shadow: 0 4px 13px color-mix(in srgb, var(--card-accent) 18%, transparent);
    background: color-mix(in srgb, var(--card-accent) 5%, white);
  }
  .mini-pill {
    height: 19px;
    max-width: 100%;
    border-radius: 10px;
    background: #131313;
    color: var(--card-accent);
    display: grid;
    grid-template-columns: 18px 20px minmax(0, 1fr);
    align-items: center;
    padding: 0 7px 0 5px;
    gap: 3px;
    font-size: 8px;
    overflow: hidden;
  }
  .mini-pill i {
    height: 8px;
    border-radius: 8px;
    background: #010101;
    border: 1px solid #292929;
  }
  .mini-pill b {
    color: #f1f1f1;
    font-size: 8px;
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .card-name {
    font-size: 11px;
    font-weight: 650;
    letter-spacing: -0.01em;
  }
  .activity-card:focus-visible,
  .round-control:focus-visible {
    outline: 3px solid #2478ff;
    outline-offset: 3px;
  }
  @keyframes equalize {
    to {
      transform: scaleY(0.36);
    }
  }
  @media (max-width: 650px) {
    .live-activities {
      padding: 0;
    }
    .heading {
      display: block;
      margin-bottom: 14px;
    }
    .stage {
      height: 225px;
      border-radius: 18px;
    }
    .notch-wrap {
      top: 40px;
      width: calc(100% - 26px);
    }
    .live-notch {
      height: 68px;
      border-radius: 27px;
      grid-template-columns: 1fr 82px 1fr;
    }
    .notch-camera {
      width: 82px;
      height: 23px;
    }
    .notch-side {
      padding: 0 13px;
    }
    .notch-copy {
      top: 75px;
    }
    .activity-description {
      top: 122px;
      font-size: 10px;
    }
    .activity-grid {
      grid-template-columns: repeat(2, 1fr);
      gap: 8px;
    }
    .activity-card {
      min-height: 58px;
      padding: 8px 9px;
    }
    .mini-pill {
      height: 18px;
    }
    .card-name {
      font-size: 10px;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    *,
    *:before,
    *:after {
      animation-duration: 0.01ms !important;
      animation-iteration-count: 1 !important;
      transition-duration: 0.01ms !important;
      scroll-behavior: auto !important;
    }
    .equalizer {
      display: none;
    }
  }
</style>
