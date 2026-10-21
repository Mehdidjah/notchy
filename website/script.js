// Notchy website: the headline's letters, reveals on scroll, the living notch, the FAQ, and the
// latest release's version.
(() => {
  // The public repository whose releases the app checks and the Download buttons serve.
  const RELEASES = "Mehdidjah/notchy-releases";
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ---------- Headline letters ----------

  document.querySelectorAll("[data-split]").forEach((line) => {
    const words = line.textContent.trim().split(/\s+/);
    line.textContent = "";
    let index = Number(line.closest("h1")?.dataset.count || 0);
    words.forEach((word, wordIndex) => {
      const span = document.createElement("span");
      span.className = "word";
      for (const letter of word) {
        const char = document.createElement("span");
        char.className = "char";
        char.style.setProperty("--i", index++);
        char.textContent = letter;
        span.append(char);
      }
      line.append(span);
      if (wordIndex < words.length - 1) line.append(" ");
    });
    if (line.closest("h1")) line.closest("h1").dataset.count = index;
  });

  // ---------- Reveal on scroll ----------

  const revealed = document.querySelectorAll("[data-reveal]");
  // Cards in the same row arrive one after another.
  document.querySelectorAll(".grid, .bento, .download-cards").forEach((group) => {
    [...group.children].forEach((child, i) => child.style.setProperty("--d", `${(i % 3) * 0.09}s`));
  });
  if ("IntersectionObserver" in window && !reduceMotion) {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      });
    }, { threshold: 0.16, rootMargin: "0px 0px -6% 0px" });
    revealed.forEach((element) => observer.observe(element));
  } else {
    revealed.forEach((element) => element.classList.add("is-visible"));
  }

  // ---------- Hero: the sky sinks into the glow as you scroll ----------

  const hero = document.querySelector(".hero");
  let ticking = false;
  const updateHero = () => {
    ticking = false;
    const progress = Math.min(1, Math.max(0, window.scrollY / (window.innerHeight * 0.9)));
    hero.style.setProperty("--p", progress.toFixed(3));
  };
  if (!reduceMotion) {
    window.addEventListener("scroll", () => {
      if (!ticking) {
        ticking = true;
        requestAnimationFrame(updateHero);
      }
    }, { passive: true });
    updateHero();
  }

  // ---------- The notch ----------

  const icon = (id, extra = "") => `<svg class="icon ${extra}"><use href="#i-${id}"/></svg>`;
  const ACTIVITIES = {
    music: { wing: 3.4, left: '<span class="art"></span>', right: '<span class="bars"><i></i><i></i><i></i><i></i></span>' },
    timer: { wing: 5.4, left: '<span class="mini-ring" style="--v:.72;--c:#ff9f0a"></span>', right: '<span class="num" data-countdown>04:59</span>' },
    download: { wing: 3.4, left: icon("arrow-circle", "c-blue"), right: '<span class="mini-ring" style="--v:.64;--c:#0a84ff"></span>' },
    headphones: { wing: 4.8, left: icon("headphones"), right: '<span class="num c-green">82%</span>' },
    charging: { wing: 4.8, left: icon("bolt", "fill c-green"), right: '<span class="num c-green">87%</span>' },
    focus: { wing: 3.8, left: icon("moon", "fill c-indigo"), right: '<span class="num c-indigo">On</span>' },
    privacy: { wing: 3.4, left: icon("camera", "c-green"), right: '<span class="dot"></span>' },
    ai: { wing: 3.6, left: icon("asterisk", "c-claude"), right: '<span class="ctx-mini" style="--v:.19"><b>19</b></span>' },
  };

  const show = (island, id) => {
    const activity = ACTIVITIES[id];
    island.style.setProperty("--wing", `${activity.wing}em`);
    island.querySelector('[data-slot="left"]').innerHTML = activity.left;
    island.querySelector('[data-slot="right"]').innerHTML = activity.right;
    island.dataset.activity = id;
  };

  const swap = (island, id) => {
    island.classList.add("is-swapping");
    setTimeout(() => {
      show(island, id);
      island.classList.remove("is-swapping");
    }, 220);
  };

  // The small notches in the live activities card.
  document.querySelectorAll(".mini").forEach((tile) => {
    const island = document.createElement("div");
    island.className = "island";
    island.dataset.mode = "closed";
    island.innerHTML = '<div class="island-closed"><div class="wing wing-l" data-slot="left"></div><div class="cam"></div><div class="wing wing-r" data-slot="right"></div></div>';
    tile.append(island);
    show(island, tile.dataset.activity);
  });

  // The hero's notch shows a few live activities in turn, then opens; hovering opens it.
  const heroIsland = document.getElementById("hero-island");
  const stage = document.querySelector(".stage");
  const order = ["music", "timer", "ai", "headphones", "charging", "download"];
  let step = 0;
  let hovering = false;
  let openUntil = 0;
  show(heroIsland, order[0]);

  const setOpen = (open) => { heroIsland.dataset.mode = open ? "open" : "closed"; };

  if (!reduceMotion) {
    setInterval(() => {
      if (hovering || document.hidden) return;
      const now = Date.now();
      if (openUntil) {
        if (now < openUntil) return;
        openUntil = 0;
        setOpen(false);
        return;
      }
      step += 1;
      if (step === order.length) {
        step = -1;
        openUntil = now + 4200;
        setOpen(true);
        return;
      }
      swap(heroIsland, order[Math.max(step, 0)]);
    }, 2600);
  }

  stage.addEventListener("mouseenter", () => { hovering = true; setOpen(true); });
  stage.addEventListener("mouseleave", () => { hovering = false; openUntil = 0; setOpen(false); });
  stage.addEventListener("click", () => {
    if (window.matchMedia("(hover: hover)").matches) return;
    setOpen(heroIsland.dataset.mode !== "open");
  });

  // Timers count down.
  let seconds = 4 * 60 + 59;
  setInterval(() => {
    seconds = seconds > 0 ? seconds - 1 : 4 * 60 + 59;
    const text = `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
    document.querySelectorAll("[data-countdown]").forEach((element) => { element.textContent = text; });
  }, 1000);

  // ---------- FAQ ----------

  document.querySelectorAll(".qa button").forEach((button) => {
    button.addEventListener("click", () => {
      const item = button.closest(".qa");
      const open = !item.classList.contains("is-open");
      item.classList.toggle("is-open", open);
      button.setAttribute("aria-expanded", String(open));
    });
  });

  // ---------- The latest release ----------

  fetch(`https://api.github.com/repos/${RELEASES}/releases/latest`, { headers: { Accept: "application/vnd.github+json" } })
    .then((response) => (response.ok ? response.json() : null))
    .then((release) => {
      if (!release) return;
      const version = String(release.tag_name || "").replace(/^v/i, "");
      const date = release.published_at
        ? new Date(release.published_at).toLocaleDateString(undefined, { year: "numeric", month: "long", day: "numeric" })
        : "";
      document.querySelectorAll("[data-version]").forEach((element) => {
        element.textContent = [version && `Version ${version}`, date].filter(Boolean).join(" · ");
      });
      const image = (release.assets || []).find((asset) => asset.name.toLowerCase().endsWith(".dmg"));
      if (image) {
        const size = `${Math.max(1, Math.round(image.size / 1e6))} MB`;
        document.querySelectorAll("[data-asset]").forEach((element) => {
          element.textContent = `${image.name} · ${size} · Apple silicon and Intel`;
        });
      }
    })
    .catch(() => {});
})();
