<script>
  import Icon from './Icon.svelte';
  import { tabShots } from './shots.js';

  const shot = tabShots.home;
</script>

<div class="hero-stage">
  <div class="glass-desktop">
    <div class="glass-menubar" aria-hidden="true">
      <div><Icon name="apple" size={20} /><span>Notchy</span></div>
      <div>
        <Icon name="search" size={16} /><svg
          width="19"
          height="16"
          viewBox="0 0 24 20"
          fill="none"
          stroke="currentColor"
          stroke-width="2.2"
          ><path d="M2 6q10-9 20 0M5 10q7-6 14 0M8.5 14q3.5-3 7 0" /><circle
            cx="12"
            cy="17.5"
            r="1"
            fill="currentColor"
          /></svg
        ><span>09:41</span>
      </div>
    </div>
    <img
      class="hero-island"
      src={shot.src}
      alt={shot.alt}
      width={shot.width}
      height={shot.height}
      fetchpriority="high"
      decoding="async"
      draggable="false"
    />
  </div>
</div>

<style>
  .hero-stage {
    position: relative;
    width: 100%;
    height: 562.5px;
    display: flex;
    justify-content: center;
    align-items: flex-start;
    isolation: isolate;
  }
  .glass-desktop {
    position: relative;
    flex: none;
    width: 1000px;
    height: 562.5px;
    background: #ffffff33;
    border-radius: 30px;
    backdrop-filter: blur(10px);
    box-shadow:
      inset 0 2px 4px #ffffff33,
      inset 0 4px 8px #ffffff40,
      inset 0 -20px 20px #ffffff40,
      inset 0 -1px #ffffff66;
    overflow: hidden;
  }
  /* The glass edge is drawn under the island, so the island meets the top edge. */
  .glass-desktop::after {
    content: '';
    position: absolute;
    inset: 0;
    z-index: 1;
    border: 1px solid #ffffff99;
    border-radius: inherit;
    pointer-events: none;
  }
  .glass-menubar {
    position: absolute;
    inset: 0 0 auto;
    height: 40px;
    padding: 0 20px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    color: #fff;
    font-size: 12px;
    line-height: 1;
    font-weight: 500;
    pointer-events: none;
  }
  .glass-menubar > div {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .glass-menubar > div:last-child {
    gap: 12px;
  }
  /* The real island, open on Home, hanging from the top of the screen like it does from the
     notch. */
  .hero-island {
    position: absolute;
    left: 50%;
    top: 0;
    transform: translateX(-50%);
    width: 696px;
    height: auto;
    z-index: 2;
    user-select: none;
  }
  @media (min-width: 810px) and (max-width: 1199px) {
    .hero-stage {
      width: 711px;
      height: 399.9375px;
    }
    .glass-desktop {
      position: absolute;
      top: -80px;
      left: 50%;
      transform: translateX(-50%) scale(0.7);
    }
  }
  @media (max-width: 809px) {
    .hero-stage {
      width: 373px;
      height: 209.8125px;
    }
    .glass-desktop {
      position: absolute;
      top: -180px;
      left: 50%;
      transform: translateX(-50%) scale(0.35);
    }
  }
  @media (max-width: 359px) {
    .hero-stage {
      width: 320px;
      height: 180px;
    }
    .glass-desktop {
      top: -190px;
      transform: translateX(-50%) scale(0.3);
    }
  }
</style>
