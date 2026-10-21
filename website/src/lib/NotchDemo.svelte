<script>
  import { onDestroy, tick, untrack } from 'svelte';
  import Icon from './Icon.svelte';

  let { initialTab = 'home', compact = false, label = 'Interactive Notchy preview' } = $props();
  const uid = $props.id();
  const tabs = [
    { id: 'home', label: 'Home', icon: 'home' },
    { id: 'shelf', label: 'Shelf', icon: 'shelf' },
    { id: 'timer', label: 'Timer', icon: 'timer' },
    { id: 'stats', label: 'Stats', icon: 'stats' },
    { id: 'notes', label: 'Notes', icon: 'notes' },
    { id: 'face', label: 'Face Check', icon: 'face' },
    { id: 'ai', label: 'AI tools', icon: 'sparkles' },
    { id: 'clipboard', label: 'Clipboard', icon: 'clipboard' }
  ];
  let activeTab = $state(
    untrack(() => (tabs.some((t) => t.id === initialTab) ? initialTab : 'home'))
  );
  let playing = $state(false);
  let track = $state(0);
  const tracks = ['Golden Hour', 'Slow Sunday', 'Blue Afternoon'];
  let filter = $state('All');
  let selectedClip = $state(null);
  let notice = $state('');
  let noticeTimeout;
  let timerInterval;
  let scanTimeout;
  let deadline = 0;
  let dragMoved = false;
  const clips = [
    {
      id: 1,
      type: 'Text',
      icon: 'notes',
      title: 'A little reminder',
      body: 'Make room for the things that matter.',
      source: 'Notes',
      time: 'Just now',
      color: '#e3b96b'
    },
    {
      id: 2,
      type: 'Images',
      icon: 'image',
      title: 'Somewhere quiet',
      body: 'landscape.webp · Sample image',
      source: 'Photos',
      time: '2 min ago',
      color: '#78c9aa',
      image: '/assets/img/landscape.webp'
    },
    {
      id: 3,
      type: 'Links',
      icon: 'link',
      title: 'A better place to focus.',
      body: 'apple.com/macos',
      source: 'Safari',
      time: '5 min ago',
      color: '#7aabff'
    },
    {
      id: 4,
      type: 'Colors',
      icon: 'color',
      title: '#E46642',
      body: 'Warm terracotta · RGB 228, 102, 66',
      source: 'Colour picker',
      time: '8 min ago',
      color: '#e46642'
    },
    {
      id: 5,
      type: 'Code',
      icon: 'code',
      title: 'A tiny interaction',
      body: 'island.open(.home)',
      source: 'Xcode',
      time: '12 min ago',
      color: '#b1a0ff'
    },
    {
      id: 6,
      type: 'Text',
      icon: 'calendar',
      title: 'Design review',
      body: 'Meeting moved to 3 pm, same room. Bring your next big idea.',
      source: 'Messages',
      time: '18 min ago',
      color: '#81c8f4'
    }
  ];
  let visibleClips = $derived(filter === 'All' ? clips : clips.filter((c) => c.type === filter));
  let files = $state([
    { id: 1, name: 'Brief.pdf', type: 'PDF', size: '240 KB', color: '#fa796d' },
    {
      id: 2,
      name: 'Landscape.webp',
      type: 'IMG',
      size: '1.2 MB',
      color: '#89bdff',
      image: '/assets/img/landscape.webp'
    },
    { id: 3, name: 'Assets.zip', type: 'ZIP', size: '4.8 MB', color: '#c2a2ff' }
  ]);
  let nextFile = 4;
  let preview = $state(null);
  let previewDialog;
  const presets = [
    { label: 'Focus', minutes: 25, color: '#ffa143' },
    { label: 'Break', minutes: 5, color: '#71dba4' },
    { label: 'Deep Work', minutes: 45, color: '#b4a0ff' }
  ];
  let preset = $state(0);
  let duration = $state(1500);
  let seconds = $state(1500);
  let running = $state(false);
  let timeText = $derived(
    `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`
  );
  let note = $state(
    'A little space to think.\n\n• Finish the design review\n• Find a good playlist\n• Make something useful'
  );
  let scan = $state('idle');
  const metrics = [
    {
      name: 'CPU',
      value: '23',
      unit: '%',
      color: '#6cafff',
      points: '0,35 10,31 20,34 30,18 40,26 50,22 60,30 70,12 80,20 90,17 100,22',
      sub: 'Plenty of headroom',
      icon: 'cpu'
    },
    {
      name: 'Memory',
      value: '61',
      unit: '%',
      color: '#79dca4',
      points: '0,26 10,27 20,24 30,25 40,21 50,23 60,20 70,18 80,20 90,17 100,18',
      sub: '9.8 of 16 GB',
      icon: 'layers'
    },
    {
      name: 'GPU',
      value: '12',
      unit: '%',
      color: '#b69cff',
      points: '0,37 10,37 20,34 30,37 40,28 50,34 60,35 70,30 80,35 90,34 100,35',
      sub: 'Taking it easy',
      icon: 'stats'
    }
  ];

  function notify(text) {
    notice = text;
    clearTimeout(noticeTimeout);
    noticeTimeout = setTimeout(() => (notice = ''), 4500);
  }
  function changeTab(id) {
    activeTab = id;
    notice = '';
  }
  function tabKeys(event, index) {
    let next;
    if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
    else if (event.key === 'ArrowLeft') next = (index - 1 + tabs.length) % tabs.length;
    else if (event.key === 'Home') next = 0;
    else if (event.key === 'End') next = tabs.length - 1;
    else return;
    event.preventDefault();
    changeTab(tabs[next].id);
    event.currentTarget.parentElement.querySelectorAll('[role="tab"]')[next]?.focus();
  }
  function chooseClip(clip) {
    if (dragMoved) return;
    selectedClip = clip.id;
    notify(`${clip.title}: ${clip.body}. Preview only, nothing copied.`);
  }
  function draggable(node) {
    let startX = 0,
      startScroll = 0,
      pressed = false;
    const down = (event) => {
      if (event.pointerType !== 'mouse' || event.button !== 0) return;
      pressed = true;
      dragMoved = false;
      startX = event.clientX;
      startScroll = node.scrollLeft;
    };
    const move = (event) => {
      if (!pressed) return;
      const delta = event.clientX - startX;
      if (Math.abs(delta) > 5) {
        dragMoved = true;
        node.scrollLeft = startScroll - delta;
        event.preventDefault();
      }
    };
    const up = () => {
      pressed = false;
    };
    const click = (event) => {
      if (dragMoved) {
        event.preventDefault();
        event.stopPropagation();
        dragMoved = false;
      }
    };
    node.addEventListener('pointerdown', down);
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', up);
    node.addEventListener('click', click, true);
    return {
      destroy() {
        node.removeEventListener('pointerdown', down);
        window.removeEventListener('pointermove', move);
        window.removeEventListener('pointerup', up);
        window.removeEventListener('pointercancel', up);
        node.removeEventListener('click', click, true);
      }
    };
  }
  function addFile() {
    const id = nextFile++;
    files = [
      ...files,
      { id, name: `Idea ${id - 3}.txt`, type: 'TXT', size: '2 KB', color: '#e3c784' }
    ];
    notify('Sample file added. No files were read from your device.');
  }
  async function quickLook(file) {
    preview = file;
    await tick();
    previewDialog?.showModal();
  }
  function closePreview() {
    previewDialog?.close();
    preview = null;
  }
  function stopTimer() {
    clearInterval(timerInterval);
    timerInterval = undefined;
    running = false;
  }
  function setPreset(index) {
    stopTimer();
    preset = index;
    duration = presets[index].minutes * 60;
    seconds = duration;
  }
  function resetTimer() {
    stopTimer();
    seconds = duration;
  }
  function toggleTimer() {
    if (running) {
      seconds = Math.max(0, Math.ceil((deadline - Date.now()) / 1000));
      stopTimer();
      return;
    }
    if (seconds === 0) seconds = duration;
    deadline = Date.now() + seconds * 1000;
    running = true;
    timerInterval = setInterval(() => {
      seconds = Math.max(0, Math.ceil((deadline - Date.now()) / 1000));
      if (seconds === 0) {
        stopTimer();
        notify('Your timer is complete. Take a breath.');
      }
    }, 200);
  }
  function simulateScan() {
    clearTimeout(scanTimeout);
    scan = 'scanning';
    scanTimeout = setTimeout(() => {
      scan = 'success';
    }, 1800);
  }
  onDestroy(() => {
    clearInterval(timerInterval);
    clearTimeout(scanTimeout);
    clearTimeout(noticeTimeout);
  });
</script>

<section class="notchy" class:compact aria-label={label}>
  <div class="toolbar">
    <span class="brand"
      ><img src="/assets/img/icon-256.png" width="18" height="18" alt="" />Notchy</span
    >
    <div class="physical-notch" aria-hidden="true"><span></span></div>
    <span class="toolbar-right"
      ><span class="time">9:41</span><Icon name="battery" size={17} /></span
    >
  </div>
  <div class="tabs" role="tablist" aria-label="Notchy features">
    {#each tabs as tab, index}
      <button
        type="button"
        role="tab"
        id={`${uid}-tab-${tab.id}`}
        aria-controls={`${uid}-panel-${tab.id}`}
        aria-selected={activeTab === tab.id}
        tabindex={activeTab === tab.id ? 0 : -1}
        class:active={activeTab === tab.id}
        aria-label={tab.label}
        title={tab.label}
        onclick={() => changeTab(tab.id)}
        onkeydown={(event) => tabKeys(event, index)}
      >
        <Icon name={tab.icon} size={17} /><span>{tab.label}</span>
      </button>
    {/each}
  </div>
  <div
    class="panel"
    role="tabpanel"
    id={`${uid}-panel-${activeTab}`}
    aria-labelledby={`${uid}-tab-${activeTab}`}
    tabindex="0"
  >
    {#if activeTab === 'home'}
      <div class="home-grid">
        <div class="card player">
          <div class="card-eyebrow">
            <Icon name="music" size={13} /> NOW PLAYING
            <span class="equalizer" class:playing aria-hidden="true"
              ><i></i><i></i><i></i><i></i></span
            >
          </div>
          <div class="album-row">
            <img
              class="album"
              src="/assets/img/wallpaper.webp"
              alt="Green hills beneath a blue sky"
              draggable="false"
            />
            <div>
              <strong>{tracks[track]}</strong>
              <p>Sunset Tapes</p>
              <span class="tiny">A soundtrack for right now.</span>
            </div>
          </div>
          <div class="track-progress"><span></span></div>
          <div class="track-times"><span>1:42</span><span>3:56</span></div>
          <div class="playback">
            <button
              type="button"
              class="icon-button previous"
              aria-label="Previous sample track"
              onclick={() => (track = (track + tracks.length - 1) % tracks.length)}
              ><Icon name="skip" size={18} /></button
            ><button
              type="button"
              class="play-button"
              aria-label={playing ? 'Pause sample playback' : 'Play sample playback'}
              aria-pressed={playing}
              onclick={() => (playing = !playing)}
              ><Icon name={playing ? 'pause' : 'play'} size={19} /></button
            ><button
              type="button"
              class="icon-button"
              aria-label="Next sample track"
              onclick={() => (track = (track + 1) % tracks.length)}
              ><Icon name="skip" size={18} /></button
            >
          </div>
          <span class="playback-note">{playing ? 'Playing' : 'Paused'} · visual demo, no audio</span
          >
        </div>
        <div class="card weather">
          <div class="card-eyebrow">LISBON <Icon name="sun" size={16} /></div>
          <div class="temperature">18<span>°</span></div>
          <strong>A little sunshine.</strong>
          <p>Feels like 17°. Clear skies<br />until the evening.</p>
          <div class="weather-bottom"><span>H: 20°</span><span>L: 14°</span></div>
        </div>
        <div class="card agenda">
          <div class="card-eyebrow"><Icon name="calendar" size={14} /> YOUR AFTERNOON</div>
          <div class="agenda-event">
            <span class="event-dot violet"></span>
            <div>
              <strong>Design review</strong>
              <p>14:00 – 14:30</p>
              <span class="tiny">Studio team</span>
            </div>
          </div>
          <div class="agenda-event">
            <span class="event-dot orange"></span>
            <div>
              <strong>Ship the update</strong>
              <p>16:30 – 17:00</p>
              <span class="tiny">One thing at a time.</span>
            </div>
          </div>
          <span class="agenda-foot">All caught up after that.</span>
        </div>
      </div>
    {:else if activeTab === 'clipboard'}
      <div class="section-heading">
        <div>
          <strong>Your clipboard, remembered.</strong><span>Little things worth keeping.</span>
        </div>
        <span class="count-badge"
          >{visibleClips.length} {visibleClips.length === 1 ? 'clip' : 'clips'}</span
        >
      </div>
      <div class="filters" aria-label="Filter sample clipboard">
        {#each ['All', 'Text', 'Links', 'Images', 'Colors', 'Code'] as type}<button
            type="button"
            class:chosen={filter === type}
            aria-pressed={filter === type}
            onclick={() => {
              filter = type;
              selectedClip = null;
              notice = '';
            }}>{type}</button
          >{/each}
      </div>
      <div class="clip-strip" use:draggable>
        {#each visibleClips as clip (clip.id)}
          <button
            type="button"
            class="clip-card"
            class:selected={selectedClip === clip.id}
            class:image-clip={clip.image}
            style={`--clip-color:${clip.color}`}
            aria-pressed={selectedClip === clip.id}
            onclick={() => chooseClip(clip)}
          >
            <span class="clip-type"
              ><Icon name={clip.icon} size={13} />{clip.type}{#if selectedClip === clip.id}<Icon
                  name="check"
                  size={13}
                />{/if}</span
            >
            {#if clip.image}<img
                src={clip.image}
                alt="A scenic landscape sample"
                draggable="false"
              />{:else if clip.type === 'Colors'}<span class="swatch"></span><strong
                >{clip.title}</strong
              >{:else if clip.type === 'Code'}<code
                ><span>island</span>.open(<br />&nbsp; .home<br />)</code
              >{:else}<strong>{clip.title}</strong><span class="clip-body">{clip.body}</span>{/if}
            <span class="clip-source">{clip.source}<small>{clip.time}</small></span>
          </button>
        {/each}
      </div>
      <p class="panel-hint">
        <Icon name="lock" size={12} />Sample history only. Drag to explore. Select a card to
        preview.
      </p>
    {:else if activeTab === 'shelf'}
      <div class="section-heading">
        <div>
          <strong>A place to park your files.</strong><span>Keep the next thing within reach.</span>
        </div>
        <button class="soft-button" type="button" onclick={addFile}
          ><Icon name="plus" size={14} />Add demo file</button
        >
      </div>
      <div class="shelf-files">
        {#each files as file (file.id)}
          <div class="shelf-file">
            <button
              class="file-preview"
              type="button"
              aria-label={`Quick Look ${file.name}`}
              onclick={() => quickLook(file)}
              >{#if file.image}<img src={file.image} alt="" draggable="false" />{:else}<span
                  class="file-sheet"
                  style={`--file-color:${file.color}`}
                  ><Icon name="file" size={30} /><b>{file.type}</b></span
                >{/if}<strong>{file.name}</strong><span>{file.size}</span></button
            ><button
              class="remove-file"
              type="button"
              aria-label={`Remove ${file.name}`}
              onclick={() => {
                files = files.filter((f) => f.id !== file.id);
                notify(`${file.name} removed from the demo shelf.`);
              }}><Icon name="x" size={12} /></button
            >
          </div>
        {/each}
        {#if files.length === 0}<p class="empty-shelf">
            Your shelf is clear. Add a demo file to try it.
          </p>{/if}
      </div>
      <p class="panel-hint">
        <Icon name="eye" size={13} />Select a file for Quick Look. No uploads or device access.
      </p>
    {:else if activeTab === 'timer'}
      <div class="timer-layout">
        <div
          class="timer-face"
          style={`--timer-color:${presets[preset].color};--progress:${(seconds / duration) * 100}%`}
        >
          <div>
            <span>{presets[preset].label}</span><strong
              role="timer"
              aria-label={`${Math.floor(seconds / 60)} minutes ${seconds % 60} seconds remaining`}
              >{timeText}</strong
            ><span
              >{running
                ? 'One thing at a time.'
                : seconds === 0
                  ? 'Beautifully done.'
                  : 'Ready when you are.'}</span
            >
          </div>
        </div>
        <div class="timer-options">
          <span class="card-eyebrow">MAKE A LITTLE SPACE</span>
          <h3>Time, on your side.</h3>
          <div class="presets">
            {#each presets as item, index}<button
                type="button"
                class:chosen={preset === index}
                aria-pressed={preset === index}
                onclick={() => setPreset(index)}
                ><span style={`color:${item.color}`}
                  ><Icon
                    name={index === 1 ? 'sun' : index === 2 ? 'moon' : 'timer'}
                    size={15}
                  />{item.label}</span
                ><span>{item.minutes} min</span></button
              >{/each}
          </div>
          <div class="timer-actions">
            <button type="button" class="white-button" onclick={toggleTimer}
              ><Icon name={running ? 'pause' : 'play'} size={15} />{running
                ? 'Pause'
                : seconds < duration && seconds > 0
                  ? 'Resume'
                  : 'Start timer'}</button
            ><button type="button" class="soft-button" aria-label="Reset timer" onclick={resetTimer}
              ><Icon name="refresh" size={15} />Reset</button
            >
          </div>
        </div>
      </div>
    {:else if activeTab === 'stats'}
      <div class="section-heading">
        <div>
          <strong>Everything, running smoothly.</strong><span
            >Illustrative values, not your device’s activity.</span
          >
        </div>
        <span class="count-badge">SAMPLE</span>
      </div>
      <div class="metrics">
        {#each metrics as metric}<div class="metric card" style={`--metric-color:${metric.color}`}>
            <div class="card-eyebrow"><Icon name={metric.icon} size={15} />{metric.name}</div>
            <strong>{metric.value}<span>{metric.unit}</span></strong><svg
              class="sparkline"
              viewBox="0 0 100 44"
              preserveAspectRatio="none"
              aria-hidden="true"><path d={`M${metric.points.replaceAll(' ', ' L')}`} /></svg
            ><span class="tiny">{metric.sub}</span>
          </div>{/each}
      </div>
      <div class="stats-bottom">
        <span><Icon name="download" size={14} />Network <b>2.4 MB/s</b></span><span
          ><Icon name="layers" size={14} />Disk <b>48% used</b></span
        ><span class="sample-label">Illustrative snapshot</span>
      </div>
    {:else if activeTab === 'notes'}
      <div class="section-heading">
        <div>
          <label for={`${uid}-note`}><strong>Your next little idea.</strong></label><span
            >Session-only scratchpad. Nothing is sent or saved.</span
          >
        </div>
        <button type="button" class="soft-button" disabled={!note} onclick={() => (note = '')}
          ><Icon name="trash" size={14} />Clear</button
        >
      </div>
      <textarea
        id={`${uid}-note`}
        bind:value={note}
        placeholder="What's on your mind?"
        spellcheck="true"
        aria-describedby={`${uid}-note-help`}></textarea>
      <p id={`${uid}-note-help`} class="panel-hint">
        <Icon name="notes" size={13} />{note.length} characters · Resets when this preview is reloaded.
      </p>
    {:else if activeTab === 'face'}
      <div class="face-layout">
        <div
          class="face-visual"
          class:scanning={scan === 'scanning'}
          class:success={scan === 'success'}
        >
          <span class="face-corner tl"></span><span class="face-corner tr"></span><span
            class="face-corner bl"
          ></span><span class="face-corner br"></span><Icon
            name={scan === 'success' ? 'check' : 'face'}
            size={66}
            strokeWidth={1}
          />{#if scan === 'scanning'}<span class="scan-line"></span>{/if}<span
            >SIMULATED PREVIEW</span
          >
        </div>
        <div class="face-copy">
          <span class="card-eyebrow"><Icon name="shield" size={14} /> A LITTLE EXTRA PRIVACY</span>
          <h3>Just for your eyes.</h3>
          <p>
            In the Mac app, Face Check helps reveal sensitive clips only after checking it’s you.
            This preview never opens your camera.
          </p>
          <button
            type="button"
            class="white-button"
            disabled={scan === 'scanning'}
            onclick={simulateScan}
            ><Icon name={scan === 'success' ? 'refresh' : 'face'} size={16} />{scan === 'scanning'
              ? 'Simulating scan…'
              : scan === 'success'
                ? 'Try again'
                : 'Simulate Face Check'}</button
          ><span class="scan-status" role="status"
            >{scan === 'success'
              ? 'Demo success. No face data was captured.'
              : scan === 'scanning'
                ? 'Playing a sample scan animation…'
                : 'No camera permission needed.'}</span
          >
        </div>
      </div>
    {:else if activeTab === 'ai'}
      <div class="section-heading">
        <div>
          <strong>A little context for your context.</strong><span
            >AI tools for Claude Code · Static demo, not connected.</span
          >
        </div>
        <span class="ai-badge"><Icon name="sparkles" size={14} />AI tools</span>
      </div>
      <div class="ai-layout">
        <div class="context-card card">
          <div class="context-ring">
            <div><strong>19<span>%</span></strong><span>context used</span></div>
          </div>
          <strong>notchy</strong><span class="tiny">Sample session · plenty of room</span>
          <div class="usage"><span>Session limit</span><b>24%</b></div>
          <div class="usage-track"><span></span></div>
        </div>
        <div class="terminal">
          <div class="terminal-top">
            <span><i></i><i></i><i></i></span><span>sample session</span>
          </div>
          <div class="terminal-body">
            <p><span class="prompt">❯</span> Summarise today’s changes</p>
            <p class="terminal-response">
              <Icon name="sparkles" size={13} /><span>A few small things, a better day.</span>
            </p>
            <ul>
              <li>A faster update check</li>
              <li>A simpler install window</li>
              <li>Context, right under the notch</li>
            </ul>
            <div class="terminal-bottom">
              <span class="status-dot"></span>Example response, no request sent.
            </div>
          </div>
        </div>
      </div>
    {/if}
  </div>
  <div class="demo-footer">
    <span class="preview-dot"></span>Interactive preview · sample data<span class="footer-brand"
      >Made for your Mac.</span
    >
  </div>
  <div class="toast" class:visible={notice !== ''} role="status" aria-live="polite">
    {#if notice}<Icon name="check" size={15} /><span>{notice}</span><button
        type="button"
        aria-label="Dismiss preview message"
        onclick={() => (notice = '')}><Icon name="x" size={14} /></button
      >{/if}
  </div>
</section>

<dialog
  bind:this={previewDialog}
  class="quick-look"
  aria-labelledby={`${uid}-quick-title`}
  onclose={() => (preview = null)}
>
  {#if preview}<div class="quick-header">
      <div>
        <span>QUICK LOOK · SIMULATED</span>
        <h3 id={`${uid}-quick-title`}>{preview.name}</h3>
      </div>
      <button type="button" aria-label="Close Quick Look" onclick={closePreview}
        ><Icon name="x" /></button
      >
    </div>
    {#if preview.image}<img
        class="quick-image"
        src={preview.image}
        alt="Sample landscape file preview"
      />{:else}<div class="document-preview">
        <Icon name="file" size={42} />
        <h4>
          {preview.type === 'PDF'
            ? 'A little brief.'
            : preview.type === 'ZIP'
              ? 'Everything in one place.'
              : 'An idea worth keeping.'}
        </h4>
        <p>
          {preview.type === 'PDF'
            ? 'Make something thoughtful. Keep it simple. Leave a little room for delight.'
            : preview.type === 'ZIP'
              ? 'Sample archive: artwork, icons, and a few useful things.'
              : 'Good things start small. This is a sample text file.'}
        </p>
        <div></div>
        <div></div>
        <div></div>
      </div>{/if}
    <p class="quick-disclaimer">Sample content only. No file was opened from your device.</p>{/if}
</dialog>

<style>
  .notchy {
    --muted: #99999f;
    --border: #ffffff12;
    --surface: #18181b;
    position: relative;
    isolation: isolate;
    width: 100%;
    max-width: 800px;
    margin-inline: auto;
    background: #050505;
    color: #f4f4f6;
    border: 1px solid #ffffff18;
    border-top: 0;
    border-radius: 0 0 24px 24px;
    padding: 0 15px 12px;
    text-align: left;
    font-family:
      Inter,
      -apple-system,
      BlinkMacSystemFont,
      'Segoe UI',
      sans-serif;
    font-size: 12px;
    line-height: 1.45;
    letter-spacing: -0.015em;
    box-shadow:
      0 28px 65px #0005,
      0 4px 12px #0003;
    color-scheme: dark;
  }
  .notchy *,
  .quick-look * {
    box-sizing: border-box;
  }
  .notchy button,
  .quick-look button {
    font: inherit;
    cursor: pointer;
    border: 0;
    color: inherit;
    letter-spacing: inherit;
  }
  .notchy button {
    transition:
      background 0.18s,
      color 0.18s,
      box-shadow 0.18s;
  }
  .notchy button:disabled {
    opacity: 0.5;
    cursor: default;
  }
  .notchy button:focus-visible,
  .notchy textarea:focus-visible,
  .notchy .panel:focus-visible,
  .quick-look button:focus-visible {
    outline: 2px solid #8dbbff;
    outline-offset: 3px;
  }
  .notchy p,
  .notchy h3 {
    margin: 0;
  }
  .notchy strong {
    font-weight: 560;
  }
  .toolbar {
    height: 42px;
    position: relative;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding-inline: 3px;
    color: #b5b5bc;
    font-size: 10px;
  }
  .brand,
  .toolbar-right {
    display: flex;
    gap: 7px;
    align-items: center;
  }
  .brand {
    font-weight: 600;
    color: #c5c5ca;
  }
  .brand img {
    border-radius: 5px;
  }
  .physical-notch {
    position: absolute;
    width: 142px;
    height: 27px;
    top: 0;
    left: 50%;
    transform: translateX(-50%);
    border-radius: 0 0 13px 13px;
    background: #000;
    box-shadow: 0 1px 0 #ffffff0a;
    display: flex;
    align-items: center;
    justify-content: flex-end;
    padding-right: 16px;
  }
  .physical-notch span {
    width: 6px;
    height: 6px;
    background: radial-gradient(circle at 40% 30%, #203445, #080d12 65%);
    border-radius: 50%;
  }
  .tabs {
    display: flex;
    gap: 3px;
    padding: 4px 2px 12px;
    overflow-x: auto;
    scrollbar-width: none;
  }
  .tabs::-webkit-scrollbar {
    display: none;
  }
  .tabs button {
    display: flex;
    flex: 1 0 auto;
    align-items: center;
    justify-content: center;
    gap: 6px;
    padding: 8px 9px;
    background: transparent;
    border-radius: 9px;
    color: #909095;
    font-size: 10px;
    font-weight: 550;
    white-space: nowrap;
  }
  .tabs button:hover {
    background: #ffffff13;
    color: #eee;
  }
  .tabs button.active {
    background: #f5f5f6;
    color: #18181b;
    box-shadow: 0 2px 7px #0004;
  }
  .panel {
    min-height: 245px;
    outline: none;
  }
  .card {
    border-radius: 13px;
    background: var(--surface);
    border: 1px solid #ffffff06;
  }
  .home-grid {
    display: grid;
    grid-template-columns: 1.3fr 0.85fr 1fr;
    gap: 9px;
    min-height: 245px;
  }
  .home-grid .card {
    padding: 15px;
  }
  .card-eyebrow {
    display: flex;
    align-items: center;
    gap: 6px;
    color: #aaaab1;
    font-size: 9px;
    font-weight: 550;
    letter-spacing: 0.065em;
  }
  .equalizer {
    display: flex;
    gap: 2px;
    align-items: center;
    margin-left: auto;
    height: 12px;
  }
  .equalizer i {
    width: 2px;
    height: 4px;
    background: #c8b6f6;
    border-radius: 3px;
  }
  .equalizer i:nth-child(2) {
    height: 10px;
    animation-delay: -0.3s;
  }
  .equalizer i:nth-child(3) {
    height: 7px;
    animation-delay: -0.6s;
  }
  .equalizer.playing i {
    animation: equalize 0.75s ease-in-out infinite alternate;
  }
  .album-row {
    display: flex;
    gap: 12px;
    align-items: center;
    margin-top: 16px;
  }
  .album {
    width: 64px;
    height: 68px;
    object-fit: cover;
    border-radius: 8px;
    box-shadow: 0 5px 15px #0005;
  }
  .album-row strong {
    font-size: 14px;
  }
  .album-row p {
    font-size: 11px;
    color: #a9a9b1;
    margin: 3px 0 6px;
  }
  .tiny {
    color: #93939b;
    font-size: 9px;
  }
  .track-progress {
    height: 3px;
    background: #ffffff17;
    border-radius: 3px;
    margin-top: 17px;
    overflow: hidden;
  }
  .track-progress span {
    display: block;
    width: 43%;
    height: 100%;
    background: #b2b2ba;
  }
  .track-times {
    display: flex;
    justify-content: space-between;
    color: #81818b;
    font-variant-numeric: tabular-nums;
    font-size: 8px;
    margin-top: 4px;
  }
  .playback {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 19px;
    margin-top: 4px;
  }
  .icon-button {
    background: transparent;
    color: #c7c7cd;
    width: 30px;
    height: 30px;
    display: grid;
    place-items: center;
    border-radius: 8px;
  }
  .icon-button:hover {
    background: #ffffff10;
  }
  .previous {
    transform: rotate(180deg);
  }
  .play-button {
    background: #eeeef2;
    color: #131316 !important;
    border-radius: 50%;
    width: 32px;
    height: 32px;
    display: grid;
    place-items: center;
  }
  .playback-note {
    display: block;
    color: #7d7d86;
    text-align: center;
    font-size: 8px;
    margin-top: 8px;
  }
  .weather {
    background: radial-gradient(ellipse at 100% 0, #283e5b99, transparent 75%), #151c26;
  }
  .weather .card-eyebrow {
    justify-content: space-between;
    color: #bac6d4;
  }
  .temperature {
    font-size: 53px;
    font-weight: 300;
    letter-spacing: -0.07em;
    margin: 12px 0 3px;
    line-height: 1.2;
  }
  .temperature span {
    color: #97a9c0;
  }
  .weather strong {
    font-size: 12px;
  }
  .weather p {
    color: #a8b1c0;
    font-size: 10px;
    line-height: 1.65;
    margin-top: 7px;
  }
  .weather-bottom {
    display: flex;
    gap: 13px;
    color: #b6c0cf;
    font-size: 9px;
    margin-top: 17px;
  }
  .agenda-event {
    display: flex;
    gap: 9px;
    margin-top: 21px;
  }
  .event-dot {
    width: 3px;
    align-self: stretch;
    border-radius: 3px;
  }
  .violet {
    background: #a69aff;
  }
  .orange {
    background: #edaf66;
  }
  .agenda-event strong {
    font-size: 11px;
  }
  .agenda-event p {
    color: #b0b0b8;
    font-size: 10px;
    margin: 3px 0;
  }
  .agenda-foot {
    font-size: 8px;
    color: #81818b;
    display: block;
    margin-top: 16px;
  }
  .section-heading {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 12px;
    padding: 2px 3px 12px;
  }
  .section-heading strong {
    font-size: 13px;
  }
  .section-heading div > span {
    display: block;
    font-size: 10px;
    color: #888891;
    margin-top: 3px;
  }
  .count-badge {
    font-size: 9px;
    white-space: nowrap;
    padding: 4px 7px;
    background: #1b1b20;
    border-radius: 5px;
    color: #a5a5ae;
  }
  .filters {
    display: flex;
    gap: 5px;
    margin: 0 2px 12px;
    overflow-x: auto;
    scrollbar-width: none;
  }
  .filters button {
    background: transparent;
    padding: 5px 12px;
    border-radius: 6px;
    font-size: 10px;
    color: #91919c;
  }
  .filters button:hover {
    background: #ffffff0b;
  }
  .filters .chosen {
    background: #25252b;
    color: #f3f3f6;
  }
  .clip-strip {
    display: flex;
    gap: 10px;
    overflow-x: auto;
    padding: 2px 3px 9px;
    scrollbar-width: thin;
    scrollbar-color: #414148 transparent;
    cursor: grab;
    overscroll-behavior-x: contain;
    user-select: none;
  }
  .clip-strip:active {
    cursor: grabbing;
  }
  .clip-card {
    flex: 0 0 156px;
    width: 156px;
    min-height: 174px;
    background: #1b1b20;
    padding: 11px !important;
    border-radius: 12px;
    display: flex;
    flex-direction: column;
    gap: 9px;
    text-align: left;
    box-shadow: inset 0 0 0 1px #ffffff0a;
    overflow: hidden;
  }
  .clip-card:hover {
    background: #232329;
    box-shadow: inset 0 0 0 1px #ffffff24;
  }
  .clip-card.selected {
    box-shadow: inset 0 0 0 2px var(--clip-color);
  }
  .clip-type {
    display: flex;
    gap: 5px;
    align-items: center;
    color: var(--clip-color);
    font-size: 9px;
  }
  .clip-type :global(svg:last-child:not(:first-child)) {
    margin-left: auto;
  }
  .clip-card > strong {
    font-size: 12px;
    line-height: 1.5;
  }
  .clip-body {
    font-size: 11px;
    color: #c1c1c9;
    line-height: 1.6;
  }
  .clip-card > img {
    width: calc(100% + 22px);
    height: 89px;
    margin: 0 -11px;
    object-fit: cover;
    pointer-events: none;
  }
  .clip-source {
    margin-top: auto;
    font-size: 9px;
    color: #b1b1bb;
  }
  .clip-source small {
    display: block;
    color: #7e7e89;
    font-size: 8px;
    margin-top: 2px;
  }
  .swatch {
    height: 55px;
    width: 100%;
    border-radius: 6px;
    background: #e46642;
    box-shadow: inset 0 0 20px #ffffff10;
  }
  .clip-card code {
    font-family: 'Fragment Mono', ui-monospace, monospace;
    font-size: 11px;
    line-height: 1.7;
    color: #aeadc6;
  }
  .clip-card code span {
    color: #c6b0fa;
  }
  .panel-hint {
    display: flex;
    align-items: center;
    gap: 6px;
    color: #888891;
    font-size: 9px;
    padding: 8px 3px 0;
  }
  .soft-button,
  .white-button {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    border-radius: 7px;
    padding: 8px 11px;
    font-size: 10px !important;
    white-space: nowrap;
    background: #25252b;
  }
  .soft-button:hover {
    background: #34343d;
  }
  .white-button {
    color: #131316 !important;
    background: #f0f0f3;
    font-weight: 600 !important;
  }
  .white-button:hover {
    background: #d9d9e2;
  }
  .shelf-files {
    display: flex;
    gap: 10px;
    padding: 18px 12px;
    border: 1px dashed #ffffff26;
    border-radius: 12px;
    min-height: 174px;
    overflow-x: auto;
    scrollbar-width: thin;
    scrollbar-color: #414148 transparent;
  }
  .shelf-file {
    flex: 0 0 126px;
    position: relative;
  }
  .file-preview {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 5px;
    width: 100%;
    height: 100%;
    padding: 4px;
    border-radius: 8px;
    background: transparent;
  }
  .file-preview:hover {
    background: #ffffff0a;
  }
  .file-sheet {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 2px;
    width: 58px;
    height: 69px;
    border-radius: 5px;
    background: color-mix(in srgb, var(--file-color) 15%, #1d1d23);
    color: var(--file-color);
    margin-bottom: 5px;
    border: 1px solid color-mix(in srgb, var(--file-color) 30%, transparent);
  }
  .file-sheet b {
    font-size: 9px;
  }
  .file-preview img {
    width: 80px;
    height: 69px;
    object-fit: cover;
    border-radius: 6px;
    margin-bottom: 5px;
  }
  .file-preview strong {
    font-size: 10px;
    max-width: 120px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .file-preview > span:last-child {
    font-size: 9px;
    color: #93939f;
  }
  .remove-file {
    position: absolute;
    top: -7px;
    right: 0;
    display: grid;
    place-items: center;
    width: 24px;
    height: 24px;
    border-radius: 50%;
    background: #2d2d34;
    color: #a7a7b1 !important;
  }
  .remove-file:hover {
    background: #493132;
    color: #ffbbb8 !important;
  }
  .empty-shelf {
    color: #8c8c96;
    margin: auto !important;
  }
  .timer-layout {
    min-height: 245px;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 46px;
    padding: 7px 16px;
  }
  .timer-face {
    width: 201px;
    height: 201px;
    flex: none;
    padding: 5px;
    background: conic-gradient(var(--timer-color) var(--progress), #25252c 0);
    border-radius: 50%;
    transform: rotate(0deg);
  }
  .timer-face > div {
    width: 100%;
    height: 100%;
    background: #09090b;
    border: 5px solid #050505;
    border-radius: 50%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
  }
  .timer-face strong {
    font-size: 43px;
    font-weight: 350;
    font-variant-numeric: tabular-nums;
    line-height: 1.5;
    letter-spacing: -0.055em;
  }
  .timer-face span {
    font-size: 10px;
    color: #92929e;
  }
  .timer-face span:first-child {
    color: var(--timer-color);
    font-weight: 550;
  }
  .timer-options {
    width: 240px;
  }
  .timer-options h3,
  .face-copy h3 {
    font-size: 21px;
    font-weight: 550;
    letter-spacing: -0.04em;
    margin: 5px 0 13px;
  }
  .presets {
    display: grid;
    gap: 4px;
  }
  .presets button {
    display: flex;
    justify-content: space-between;
    gap: 14px;
    background: transparent;
    padding: 7px 9px;
    border-radius: 6px;
    color: #9696a0;
    font-size: 10px;
  }
  .presets button span:first-child {
    display: flex;
    align-items: center;
    gap: 7px;
  }
  .presets button.chosen {
    background: #1d1d23;
  }
  .presets button:hover {
    background: #25252b;
  }
  .timer-actions {
    display: flex;
    gap: 7px;
    margin-top: 12px;
  }
  .metrics {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 9px;
  }
  .metric {
    padding: 13px;
    min-width: 0;
  }
  .metric .card-eyebrow {
    color: var(--metric-color);
  }
  .metric > strong {
    display: block;
    font-size: 33px;
    font-weight: 350;
    margin: 7px 0 0;
    letter-spacing: -0.05em;
  }
  .metric strong span {
    font-size: 17px;
    color: #9999a4;
    margin-left: 3px;
  }
  .sparkline {
    display: block;
    width: 100%;
    height: 49px;
    margin-bottom: 7px;
    overflow: visible;
  }
  .sparkline path {
    stroke: var(--metric-color);
    stroke-width: 1.5;
    vector-effect: non-scaling-stroke;
    fill: none;
    stroke-linejoin: round;
  }
  .stats-bottom {
    display: flex;
    gap: 20px;
    margin-top: 13px;
    padding: 0 3px;
    font-size: 9px;
    color: #91919b;
  }
  .stats-bottom > span {
    display: flex;
    gap: 5px;
    align-items: center;
  }
  .stats-bottom b {
    font-weight: 500;
    color: #cacad1;
  }
  .stats-bottom .sample-label {
    margin-left: auto;
    font-size: 8px;
  }
  textarea {
    display: block;
    width: 100%;
    min-height: 174px;
    resize: vertical;
    border: 1px solid #ffffff13;
    border-radius: 12px;
    background: #19191d;
    color: #dddde3;
    padding: 15px;
    font:
      12px/1.8 Inter,
      system-ui,
      sans-serif;
    outline: none;
  }
  .face-layout {
    display: flex;
    gap: 29px;
    align-items: center;
    min-height: 245px;
    padding: 15px 20px;
  }
  .face-visual {
    width: 180px;
    height: 180px;
    flex: none;
    position: relative;
    display: grid;
    place-content: center;
    justify-items: center;
    gap: 19px;
    background: radial-gradient(circle, #212c3b, #11151c 70%);
    border-radius: 14px;
    color: #96b9e9;
    overflow: hidden;
  }
  .face-visual > span:last-child {
    font-size: 7px;
    color: #7d94b1;
    letter-spacing: 0.1em;
  }
  .face-corner {
    position: absolute;
    width: 20px;
    height: 20px;
    border: 2px solid #7ca6dc88;
  }
  .tl {
    top: 22px;
    left: 22px;
    border-right: 0;
    border-bottom: 0;
    border-top-left-radius: 6px;
  }
  .tr {
    top: 22px;
    right: 22px;
    border-left: 0;
    border-bottom: 0;
    border-top-right-radius: 6px;
  }
  .bl {
    bottom: 40px;
    left: 22px;
    border-right: 0;
    border-top: 0;
    border-bottom-left-radius: 6px;
  }
  .br {
    bottom: 40px;
    right: 22px;
    border-left: 0;
    border-top: 0;
    border-bottom-right-radius: 6px;
  }
  .face-visual.success {
    color: #8fe2ab;
    background: radial-gradient(circle, #1e3b30, #101a15 70%);
  }
  .scan-line {
    position: absolute;
    height: 2px;
    background: #a3caff;
    box-shadow: 0 0 20px #8abafa;
    left: 24px;
    right: 24px;
    top: 32px;
    animation: scan 1.2s ease-in-out infinite alternate;
  }
  .face-copy {
    max-width: 345px;
  }
  .face-copy p {
    color: #a2a2ad;
    font-size: 11px;
    line-height: 1.7;
    margin-bottom: 15px;
  }
  .scan-status {
    display: block;
    color: #9595a2;
    font-size: 9px;
    min-height: 14px;
    margin-top: 9px;
  }
  .ai-badge {
    display: flex;
    align-items: center;
    gap: 5px;
    font-size: 9px;
    color: #e7aa92;
  }
  .ai-layout {
    display: grid;
    grid-template-columns: 200px 1fr;
    gap: 10px;
  }
  .context-card {
    padding: 13px 16px;
    display: flex;
    flex-direction: column;
    align-items: center;
  }
  .context-ring {
    width: 82px;
    height: 82px;
    background: conic-gradient(#dd967a 19%, #363033 0);
    padding: 4px;
    border-radius: 50%;
    margin-bottom: 8px;
  }
  .context-ring > div {
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: center;
    height: 100%;
    background: #18181b;
    border-radius: 50%;
  }
  .context-ring strong {
    font-size: 24px;
    font-weight: 400;
    line-height: 1.2;
  }
  .context-ring strong span {
    font-size: 12px;
    margin-left: 1px;
    color: #b9a59c;
  }
  .context-ring div > span {
    font-size: 7px;
    color: #a08d87;
  }
  .context-card > strong {
    font-size: 11px;
    margin-bottom: 3px;
  }
  .context-card .tiny {
    font-size: 8px;
  }
  .usage {
    display: flex;
    justify-content: space-between;
    width: 100%;
    font-size: 8px;
    color: #95909a;
    margin-top: 12px;
  }
  .usage b {
    color: #c7b5ac;
    font-weight: 500;
  }
  .usage-track {
    width: 100%;
    height: 3px;
    border-radius: 2px;
    background: #363033;
    margin-top: 5px;
  }
  .usage-track > span {
    display: block;
    width: 24%;
    height: 100%;
    background: #dd967a;
  }
  .terminal {
    min-width: 0;
    border: 1px solid #ffffff13;
    border-radius: 12px;
    overflow: hidden;
    background: #121215;
    font:
      10px/1.75 'Fragment Mono',
      ui-monospace,
      monospace;
  }
  .terminal-top {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 9px 12px;
    border-bottom: 1px solid #ffffff0b;
    color: #71717b;
    font-size: 8px;
  }
  .terminal-top > span:first-child {
    display: flex;
    gap: 4px;
  }
  .terminal-top i {
    width: 6px;
    height: 6px;
    background: #4c4244;
    border-radius: 50%;
  }
  .terminal-top i:nth-child(2) {
    background: #514a3b;
  }
  .terminal-top i:nth-child(3) {
    background: #354c3f;
  }
  .terminal-body {
    padding: 14px;
  }
  .prompt {
    color: #dc9b7d;
  }
  .terminal-response {
    display: flex;
    align-items: center;
    gap: 7px;
    color: #d3ac98;
    margin-top: 14px !important;
  }
  .terminal ul {
    padding-left: 22px;
    margin: 7px 0 15px;
    color: #a7a2ac;
  }
  .terminal-bottom {
    font-size: 8px;
    color: #797680;
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .status-dot {
    width: 4px;
    height: 4px;
    background: #b8a58f;
    border-radius: 50%;
  }
  .demo-footer {
    display: flex;
    align-items: center;
    gap: 5px;
    color: #73737c;
    font-size: 8px;
    margin: 13px 3px 0;
  }
  .preview-dot {
    width: 4px;
    height: 4px;
    border-radius: 50%;
    background: #7a7a83;
  }
  .footer-brand {
    margin-left: auto;
    color: #5f5f68;
  }
  .toast {
    position: absolute;
    bottom: 28px;
    left: 16px;
    right: 16px;
    display: flex;
    align-items: center;
    gap: 9px;
    border-radius: 11px;
    background: #292930f5;
    backdrop-filter: blur(12px);
    box-shadow: 0 8px 25px #0007;
    color: #dedee7;
    font-size: 10px;
    opacity: 0;
    pointer-events: none;
    transform: translateY(5px);
    transition:
      opacity 0.2s,
      transform 0.2s;
    z-index: 2;
  }
  .toast.visible {
    padding: 12px;
    opacity: 1;
    transform: none;
    pointer-events: auto;
  }
  .toast > :global(svg) {
    color: #9ed6b5;
  }
  .toast button {
    margin-left: auto;
    display: grid;
    place-items: center;
    background: #ffffff0a;
    border-radius: 5px;
    padding: 5px;
  }
  .quick-look {
    color-scheme: dark;
    width: min(480px, calc(100vw - 32px));
    max-height: 85vh;
    padding: 18px;
    background: #18181d;
    color: #eeeeef;
    border: 1px solid #ffffff26;
    border-radius: 17px;
    box-shadow: 0 35px 100px #0009;
    font-family: Inter, system-ui, sans-serif;
  }
  .quick-look::backdrop {
    background: #0008;
    backdrop-filter: blur(6px);
  }
  .quick-header {
    display: flex;
    justify-content: space-between;
    gap: 16px;
    align-items: center;
    margin-bottom: 17px;
  }
  .quick-header span {
    font-size: 9px;
    color: #8e8e9a;
    letter-spacing: 0.09em;
  }
  .quick-header h3 {
    font-size: 14px;
    font-weight: 550;
    margin: 5px 0 0;
  }
  .quick-header button {
    background: #ffffff0a;
    border-radius: 50%;
    width: 32px;
    height: 32px;
    display: grid;
    place-items: center;
  }
  .quick-image {
    width: 100%;
    max-height: 50vh;
    object-fit: cover;
    border-radius: 9px;
  }
  .quick-disclaimer {
    font-size: 10px;
    color: #93939e;
    margin: 15px 0 0;
  }
  .document-preview {
    background: #efeee9;
    color: #373634;
    border-radius: 9px;
    min-height: 250px;
    padding: 30px;
  }
  .document-preview h4 {
    font-size: 23px;
    font-weight: 550;
    margin: 13px 0;
  }
  .document-preview p {
    font-size: 12px;
    line-height: 1.7;
    max-width: 280px;
  }
  .document-preview > div {
    height: 5px;
    background: #d7d6d1;
    width: 100%;
    margin-top: 10px;
    border-radius: 2px;
  }
  .document-preview > div:last-child {
    width: 60%;
  }
  .compact {
    padding-inline: 11px;
  }
  .compact .toolbar {
    height: 34px;
  }
  .compact .tabs {
    padding-bottom: 10px;
  }
  .compact .panel {
    min-height: 230px;
  }
  .compact .home-grid {
    min-height: 230px;
  }
  .compact .home-grid .card {
    padding: 12px;
  }
  @keyframes equalize {
    to {
      height: 3px;
    }
  }
  @keyframes scan {
    to {
      transform: translateY(95px);
    }
  }
  @media (max-width: 809px) {
    .tabs {
      gap: 4px;
    }
    .tabs button {
      padding: 8px 10px;
    }
    .tabs button:not(.active) span {
      display: none;
    }
    .tabs button.active {
      flex-grow: 1.5;
    }
    .home-grid {
      grid-template-columns: 1.25fr 0.85fr 1fr;
      gap: 7px;
    }
    .home-grid .card {
      padding: 12px;
    }
    .album-row {
      gap: 9px;
    }
    .album {
      width: 54px;
      height: 62px;
    }
    .album-row strong {
      font-size: 12px;
    }
    .album-row .tiny {
      font-size: 8px;
    }
    .timer-layout {
      gap: 26px;
    }
    .face-layout {
      gap: 22px;
      padding-inline: 12px;
    }
  }
  @media (max-width: 560px) {
    .notchy {
      padding-inline: 10px;
      border-radius: 0 0 20px 20px;
    }
    .toolbar {
      height: 36px;
    }
    .physical-notch {
      width: 110px;
      height: 24px;
    }
    .tabs {
      gap: 1px;
      padding-bottom: 10px;
    }
    .tabs button {
      padding: 8px 7px;
      font-size: 9px;
      gap: 4px;
    }
    .tabs button :global(svg) {
      width: 15px;
      height: 15px;
    }
    .home-grid {
      grid-template-columns: 1.2fr 1fr;
    }
    .home-grid .player {
      grid-column: 1 / -1;
      display: grid;
      grid-template-columns: 1fr auto;
      gap: 0 15px;
    }
    .player .card-eyebrow {
      grid-column: 1 / -1;
    }
    .player .album-row {
      grid-column: 1;
      margin-top: 10px;
    }
    .player .album {
      width: 48px;
      height: 48px;
    }
    .player .album-row strong {
      font-size: 13px;
    }
    .player .album-row .tiny {
      display: none;
    }
    .player .playback {
      grid-column: 2;
      grid-row: 2;
      gap: 6px;
    }
    .player .track-progress {
      grid-column: 1 / -1;
      margin-top: 12px;
    }
    .player .track-times {
      grid-column: 1 / -1;
    }
    .player .playback-note {
      grid-column: 1 / -1;
      margin-top: 1px;
    }
    .weather .temperature {
      font-size: 38px;
      margin-top: 8px;
    }
    .weather-bottom {
      margin-top: 10px;
    }
    .agenda-event {
      margin-top: 13px;
    }
    .agenda-foot {
      display: none;
    }
    .agenda-event .tiny {
      display: none;
    }
    .section-heading {
      gap: 7px;
    }
    .section-heading strong {
      font-size: 11px;
    }
    .section-heading div > span {
      font-size: 9px;
    }
    .section-heading .soft-button {
      padding: 7px 8px;
      font-size: 9px !important;
    }
    .filters {
      gap: 2px;
    }
    .filters button {
      padding: 5px 9px;
    }
    .clip-card {
      flex-basis: 145px;
    }
    .timer-layout {
      gap: 18px;
      padding: 12px 0;
      flex-direction: column;
    }
    .timer-face {
      width: 158px;
      height: 158px;
    }
    .timer-face strong {
      font-size: 35px;
    }
    .timer-options {
      width: 100%;
    }
    .timer-options > .card-eyebrow,
    .timer-options h3 {
      display: none;
    }
    .presets {
      grid-template-columns: repeat(3, 1fr);
      gap: 4px;
    }
    .presets button {
      flex-direction: column;
      gap: 4px;
      align-items: center;
      padding: 8px 3px;
      font-size: 9px;
    }
    .presets button span:first-child {
      gap: 4px;
    }
    .timer-actions {
      justify-content: center;
    }
    .metric {
      padding: 10px;
    }
    .metrics {
      gap: 6px;
    }
    .metric > strong {
      font-size: 27px;
    }
    .metric .tiny {
      font-size: 8px;
    }
    .stats-bottom {
      gap: 12px;
      flex-wrap: wrap;
      font-size: 8px;
    }
    .stats-bottom .sample-label {
      display: none;
    }
    .sparkline {
      height: 57px;
    }
    .face-layout {
      gap: 18px;
      padding: 10px 4px;
      flex-direction: column;
    }
    .face-visual {
      width: 145px;
      height: 150px;
    }
    .face-copy {
      text-align: center;
      max-width: 330px;
    }
    .face-copy .card-eyebrow {
      justify-content: center;
    }
    .face-copy h3 {
      font-size: 20px;
    }
    .face-copy p {
      font-size: 10px;
    }
    .ai-layout {
      grid-template-columns: 1fr;
    }
    .context-card {
      display: grid;
      grid-template-columns: 74px 1fr;
      column-gap: 13px;
      padding: 12px;
    }
    .context-ring {
      grid-column: 1;
      grid-row: 1 / 5;
      width: 70px;
      height: 70px;
      margin-bottom: 0;
    }
    .context-card > strong,
    .context-card > .tiny,
    .usage,
    .usage-track {
      grid-column: 2;
    }
    .usage {
      margin-top: 5px;
    }
    .terminal-body {
      padding: 13px;
    }
    .demo-footer {
      font-size: 7px;
    }
    .footer-brand {
      display: none;
    }
    .toast {
      left: 9px;
      right: 9px;
      font-size: 9px;
    }
    .panel-hint {
      font-size: 8px;
      align-items: flex-start;
    }
    .panel-hint :global(svg) {
      flex: none;
      margin-top: 1px;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .notchy *,
    .quick-look * {
      animation: none !important;
      transition: none !important;
      scroll-behavior: auto !important;
    }
    .scan-line {
      top: 75px;
    }
  }
</style>
