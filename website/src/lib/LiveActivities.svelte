<script>
  import { closedShots } from './shots.js';

  let active = $state(closedShots[0].id);
  const current = $derived(closedShots.find((item) => item.id === active) ?? closedShots[0]);
  /** Every activity on the stage is drawn at one and a half times its size on a Mac. */
  const zoom = 1.5;
</script>

<section class="live-activities" aria-label="Live activities on the closed notch">
  <figure class="stage">
    <div class="stage-bar" aria-hidden="true"></div>
    <img
      class="stage-shot"
      src={current.src}
      alt={`Notchy’s closed notch showing ${current.label}`}
      width={current.width * zoom}
      height={current.height * zoom}
      style={`--shot-width: ${current.width * zoom}px`}
      decoding="async"
      draggable="false"
    />
    <figcaption class="caption" aria-live="polite">{current.caption}</figcaption>
  </figure>

  <div class="activity-grid" role="group" aria-label="Choose a live activity">
    {#each closedShots as item}
      <button
        type="button"
        class="activity-card"
        class:active={active === item.id}
        aria-pressed={active === item.id}
        onclick={() => (active = item.id)}
      >
        <span class="thumb" aria-hidden="true"
          ><img
            src={item.src}
            alt=""
            width={item.width}
            height={item.height}
            loading="lazy"
            decoding="async"
            draggable="false"
          /></span
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
    color: #171719;
  }
  /* Tall enough for the tallest activity, Face Check, so picking one never moves the page. */
  .stage {
    position: relative;
    display: flex;
    flex-direction: column;
    align-items: center;
    min-height: 420px;
    margin: 0;
    overflow: hidden;
    border-radius: 22px;
    background: #5199d9 url('/assets/img/wallpaper.webp') center 45% / cover;
    box-shadow: 0 12px 28px #2c313314;
  }
  /* The border is drawn under the notch, so the notch meets the top edge. */
  .stage::after {
    content: '';
    position: absolute;
    inset: 0;
    border: 1px solid #e3e2df;
    border-radius: inherit;
    pointer-events: none;
  }
  .stage-bar {
    position: absolute;
    inset: 0 0 auto;
    height: 30px;
    background: #e0eeff28;
    backdrop-filter: blur(12px);
  }
  /* The notch hangs from the top edge of the stage, as it does from the top of the screen. */
  .stage-shot {
    position: relative;
    z-index: 1;
    display: block;
    width: min(var(--shot-width), calc(100% - 24px));
    height: auto;
    margin: 0 auto;
    user-select: none;
  }
  .caption {
    position: relative;
    z-index: 2;
    width: min(100% - 40px, 520px);
    margin: auto 0 22px;
    padding: 9px 16px;
    border-radius: 999px;
    background: #ffffffd9;
    backdrop-filter: blur(12px);
    color: #2a2d33;
    font-size: 14px;
    line-height: 1.35;
    text-align: center;
    box-shadow: 0 6px 18px #10203a1f;
  }
  .activity-grid {
    display: grid;
    grid-template-columns: repeat(5, minmax(0, 1fr));
    gap: 10px;
    margin-top: 14px;
  }
  .activity-card {
    display: flex;
    flex-direction: column;
    align-items: stretch;
    gap: 10px;
    min-width: 0;
    padding: 12px 12px 11px;
    border: 1px solid #e3e2df;
    border-radius: 16px;
    background: #fff;
    font: inherit;
    text-align: left;
    color: inherit;
    cursor: pointer;
    transition:
      border-color 0.2s ease,
      box-shadow 0.2s ease,
      transform 0.2s ease;
  }
  .activity-card:hover {
    transform: translateY(-1px);
    box-shadow: 0 6px 16px #2c313314;
  }
  .activity-card.active {
    border-color: #0d0d0d;
    box-shadow: 0 0 0 1px #0d0d0d inset;
  }
  .activity-card:focus-visible {
    outline: 2px solid #0080ff;
    outline-offset: 2px;
  }
  .thumb {
    display: flex;
    justify-content: center;
    align-items: flex-start;
    height: 40px;
    overflow: hidden;
    border-radius: 8px;
    background: #5199d9 url('/assets/img/wallpaper.webp') center 30% / cover;
  }
  .thumb img {
    display: block;
    width: auto;
    max-width: 100%;
    height: auto;
    max-height: 40px;
    object-fit: contain;
    object-position: top center;
  }
  .card-name {
    font-size: 13px;
    font-weight: 600;
  }
  @media (max-width: 809px) {
    .stage {
      min-height: 360px;
    }
    .activity-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .activity-card {
      transition: none;
    }
  }
</style>
