<script>
  import NotchDemo from './NotchDemo.svelte';
  import Icon from './Icon.svelte';
  export let initialTab = 'home';
  export let hero = false;
  export let label = 'Interactive Notchy preview';
</script>

<div class:hero class="device-stage" aria-label={label}>
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
    <div class="demo-placement"><NotchDemo {initialTab} {label} compact={!hero} /></div>
    <div class="desktop-caption" aria-hidden="true">
      <span>Less switching.</span><strong>More doing.</strong>
    </div>
    <div class="desktop-dock" aria-hidden="true">
      <span class="dock-icon finder">:)</span><span class="dock-icon calendar"
        ><small>WED</small>21</span
      ><span class="dock-icon music"><Icon name="music" size={22} /></span><span
        class="dock-icon notes"><Icon name="notes" size={22} /></span
      ><img src="/assets/img/icon-256.png" alt="" width="44" height="44" /><span
        class="dock-divider"
      ></span><span class="dock-icon folder"><Icon name="shelf" size={23} /></span>
    </div>
  </div>
  {#if hero}<p class="stage-instruction">
      <span class="live-dot"></span> This is a working preview. Go ahead, explore the tabs.
    </p>{/if}
</div>

<style>
  .device-stage {
    position: relative;
    width: 100%;
    isolation: isolate;
  }
  .desktop-screen {
    position: relative;
    min-height: 490px;
    padding-bottom: 110px;
    border-radius: 20px;
    overflow: hidden;
    background: #5199d9 url('/assets/img/wallpaper.webp') center 64% / cover;
    box-shadow:
      0 1px 0 #ffffff80 inset,
      0 12px 35px #102b5424;
    border: 1px solid #ffffff50;
  }
  .desktop-bar {
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
  .demo-placement {
    position: relative;
    z-index: 3;
    padding: 0 24px;
    display: flex;
    justify-content: center;
    margin-top: -30px;
  }
  .desktop-caption {
    position: absolute;
    bottom: 100px;
    left: 36px;
    display: flex;
    flex-direction: column;
    color: #fff;
    text-shadow: 0 1px 20px #003a5530;
    line-height: 1;
    pointer-events: none;
  }
  .desktop-caption span {
    font-size: 22px;
    letter-spacing: -0.7px;
  }
  .desktop-caption strong {
    font-family: 'Instrument Serif', serif;
    font-style: italic;
    font-size: 50px;
    font-weight: 400;
    letter-spacing: -1.5px;
  }
  .desktop-dock {
    position: absolute;
    bottom: 18px;
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 9px;
    border-radius: 18px;
    background: #ffffff30;
    box-shadow: inset 0 0 0 1px #ffffff60;
    backdrop-filter: blur(18px);
  }
  .dock-icon {
    width: 38px;
    height: 38px;
    border-radius: 10px;
    display: flex;
    align-items: center;
    justify-content: center;
    color: white;
    box-shadow: 0 2px 5px #0002;
  }
  .finder {
    background: linear-gradient(90deg, #229df5 50%, #a9e4ff 50%);
    color: #06243b;
    font-size: 27px;
    letter-spacing: -2px;
  }
  .calendar {
    background: #fff;
    color: #121212;
    flex-direction: column;
    line-height: 1;
    font-size: 21px;
  }
  .calendar small {
    color: #f25757;
    font-size: 8px;
    font-weight: 700;
    margin-bottom: 3px;
  }
  .music {
    background: linear-gradient(#ff667c, #ee214a);
  }
  .notes {
    background: linear-gradient(#ffd55c 30%, #fff 30%);
    color: #9a8954;
  }
  .folder {
    background: linear-gradient(#65c9ff, #2899ee);
  }
  .desktop-dock img {
    width: 38px;
    height: 38px;
    border-radius: 10px;
  }
  .dock-divider {
    height: 28px;
    width: 1px;
    background: #fff5;
    margin: 0 3px;
  }
  .hero .desktop-screen {
    min-height: 560px;
    padding-bottom: 190px;
    border-radius: 30px;
    background: #ffffff1f;
    backdrop-filter: blur(10px);
    border: 1px solid #fff5;
    box-shadow:
      inset 0 2px 4px #fff3,
      inset 0 4px 8px #fff4,
      inset 0 -20px 20px #fff4,
      inset 0 -1px #fff6;
  }
  .hero .desktop-bar {
    background: #fff2;
  }
  .hero .demo-placement {
    padding: 0 70px;
  }
  .device-stage:not(.hero) .desktop-caption {
    display: none;
  }
  .hero .desktop-caption {
    left: 50%;
    bottom: 96px;
    transform: translateX(-50%);
    text-align: center;
    white-space: nowrap;
  }
  .hero .desktop-caption span {
    display: none;
  }
  .hero .desktop-caption strong {
    font-size: 76px;
  }
  .stage-instruction {
    position: absolute;
    top: -28px;
    left: 0;
    width: 100%;
    text-align: center;
    font-size: 12px !important;
    color: #fff !important;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    margin: 0 !important;
  }
  .live-dot {
    width: 5px;
    height: 5px;
    background: #fff;
    border-radius: 50%;
  }
  @media (max-width: 1199px) {
    .hero .demo-placement {
      padding: 0 25px;
    }
    .desktop-bar > div {
      gap: 8px;
    }
    .desktop-caption {
      bottom: 90px;
    }
    .desktop-screen {
      min-height: 460px;
    }
  }
  @media (max-width: 809px) {
    .desktop-screen {
      min-height: 460px;
      border-radius: 14px;
    }
    .desktop-bar {
      font-size: 8px;
      padding: 0 10px;
    }
    .desktop-bar > div > span {
      display: none;
    }
    .demo-placement,
    .hero .demo-placement {
      padding: 0 10px;
    }
    .hero .desktop-screen {
      min-height: 480px;
      padding-bottom: 165px;
      border-radius: 20px;
    }
    .desktop-caption {
      left: 22px;
      bottom: 83px;
    }
    .desktop-caption span {
      font-size: 18px;
    }
    .desktop-caption strong {
      font-size: 39px;
    }
    .hero .desktop-caption strong {
      font-size: 52px;
    }
    .desktop-dock {
      padding: 7px;
      gap: 6px;
      bottom: 14px;
    }
    .dock-icon,
    .desktop-dock img {
      width: 30px;
      height: 30px;
      border-radius: 8px;
    }
    .desktop-dock :global(svg) {
      width: 18px;
    }
    .stage-instruction {
      font-size: 10px !important;
    }
    .hero .desktop-caption {
      bottom: 87px;
    }
  }
  @media (max-width: 480px) {
    .desktop-screen {
      min-height: 470px;
    }
    .hero .desktop-screen {
      min-height: 500px;
    }
    .desktop-caption {
      bottom: 78px;
    }
    .desktop-caption strong {
      font-size: 34px;
    }
  }
</style>
