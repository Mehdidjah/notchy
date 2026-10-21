<script>
  import Icon from './Icon.svelte';
  import { tabShots } from './shots.js';

  /** The tab of the real island to show; `ai` also offers its Sessions view. */
  let { tab = 'home' } = $props();

  const views = $derived(
    tab === 'ai'
      ? [
          { id: 'ai', label: 'Chat' },
          { id: 'ai-sessions', label: 'Sessions' }
        ]
      : [{ id: tab, label: '' }]
  );
  let selected = $state(null);
  const shot = $derived(tabShots[selected ?? views[0].id] ?? tabShots.home);
</script>

<figure class="device-stage">
  <div class="desktop-screen">
    <div class="desktop-bar" aria-hidden="true">
      <div>
        <Icon name="apple" size={15} /><b>Notchy</b><span>File</span><span>Edit</span><span
          >View</span
        >
      </div>
      <div>
        <Icon name="battery" size={17} /><span>100%</span><Icon name="sun" size={14} /><span
          >Wed 9:41</span
        >
      </div>
    </div>
    <img
      class="island-shot"
      src={shot.src}
      alt={shot.alt}
      width={shot.width}
      height={shot.height}
      style={`--shot-width: ${shot.width}px`}
      loading="lazy"
      decoding="async"
      draggable="false"
    />
  </div>
  {#if views.length > 1}
    <div class="view-switch" role="group" aria-label="AI tools view">
      {#each views as view}
        <button
          type="button"
          aria-pressed={(selected ?? views[0].id) === view.id}
          onclick={() => (selected = view.id)}>{view.label}</button
        >
      {/each}
    </div>
  {/if}
</figure>

<style>
  .device-stage {
    position: relative;
    width: 100%;
    margin: 0;
    isolation: isolate;
  }
  .desktop-screen {
    position: relative;
    container-type: inline-size;
    padding-bottom: clamp(56px, 10vw, 120px);
    border-radius: 20px;
    overflow: hidden;
    background: #5199d9 url('/assets/img/wallpaper.webp') center 64% / cover;
    box-shadow:
      0 1px 0 #ffffff80 inset,
      0 12px 35px #102b5424;
  }
  /* The border is drawn under the island, so the island meets the top edge. */
  .desktop-screen::after {
    content: '';
    position: absolute;
    inset: 0;
    border: 1px solid #ffffff50;
    border-radius: inherit;
    pointer-events: none;
  }
  .desktop-bar {
    position: absolute;
    inset: 0 0 auto;
    height: 30px;
    background: #e0eeff28;
    backdrop-filter: blur(12px);
    display: flex;
    justify-content: space-between;
    padding: 0 17px;
    color: #fff;
    font-size: 10px;
  }
  .desktop-bar > div {
    display: flex;
    gap: 14px;
    align-items: center;
  }
  /* The island hangs from the top edge of the screen, the way it grows out of the notch. */
  .island-shot {
    position: relative;
    z-index: 1;
    display: block;
    width: min(var(--shot-width), calc(100% - 24px));
    height: auto;
    margin: 0 auto;
    user-select: none;
  }
  .view-switch {
    display: flex;
    justify-content: center;
    gap: 6px;
    margin-top: 14px;
  }
  .view-switch button {
    font: inherit;
    font-size: 13px;
    font-weight: 600;
    padding: 7px 14px;
    border-radius: 999px;
    border: 1px solid #e3e2df;
    background: #fff;
    color: #3b3f46;
    cursor: pointer;
    transition:
      background 0.2s ease,
      color 0.2s ease;
  }
  .view-switch button[aria-pressed='true'] {
    background: #0d0d0d;
    border-color: #0d0d0d;
    color: #fff;
  }
  .view-switch button:focus-visible {
    outline: 2px solid #0080ff;
    outline-offset: 2px;
  }
  @media (max-width: 1199px) {
    .desktop-bar > div {
      gap: 8px;
    }
  }
  /* Where the island would cover the menu bar's items, only the bar itself shows. */
  @container (max-width: 1000px) {
    .desktop-bar > div {
      visibility: hidden;
    }
  }
  @media (max-width: 809px) {
    .desktop-screen {
      border-radius: 14px;
    }
    .desktop-bar {
      height: 22px;
      font-size: 8px;
      padding: 0 10px;
    }
    .desktop-bar > div > span {
      display: none;
    }
    .island-shot {
      width: min(var(--shot-width), calc(100% - 12px));
    }
  }
</style>
