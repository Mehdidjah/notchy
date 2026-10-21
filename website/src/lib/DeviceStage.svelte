<script>
  import NotchDemo from './NotchDemo.svelte';
  import Icon from './Icon.svelte';
  export let initialTab = 'home';
  export let label = 'Interactive Notchy preview';
  const dock = ['finder', 'safari', 'music', 'mail', 'notes', 'notchy', 'settings'];
</script>

<div class="device-stage" aria-label={label}>
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
    <div class="demo-placement"><NotchDemo {initialTab} {label} compact /></div>
    <div class="desktop-dock" aria-hidden="true">
      {#each dock as app}<img
          src={`/assets/macos/${app}.png`}
          alt=""
          width="44"
          height="44"
          draggable="false"
        />{/each}
      <span class="dock-divider"></span><img
        src="/assets/macos/folder.png"
        alt=""
        width="44"
        height="44"
        draggable="false"
      />
    </div>
  </div>
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
  .desktop-dock {
    position: absolute;
    bottom: 18px;
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 8px;
    border-radius: 18px;
    background: #ffffff30;
    box-shadow: inset 0 0 0 1px #ffffff60;
    backdrop-filter: blur(18px);
  }
  .desktop-dock img {
    width: 44px;
    height: 44px;
    max-width: none;
    object-fit: contain;
  }
  .dock-divider {
    height: 32px;
    width: 1px;
    background: #fff5;
    margin: 0 3px;
  }
  @media (max-width: 1199px) {
    .desktop-bar > div {
      gap: 8px;
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
    .demo-placement {
      padding: 0 10px;
    }
    .desktop-dock {
      padding: 6px;
      gap: 3px;
      bottom: 14px;
    }
    .desktop-dock img {
      width: 29px;
      height: 29px;
    }
    .dock-divider {
      height: 23px;
    }
  }
  @media (max-width: 480px) {
    .desktop-screen {
      min-height: 470px;
    }
    .desktop-dock img {
      width: 26px;
      height: 26px;
    }
  }
</style>
