// The Oslo Tree: the page around the live scene. It opens on a still of
// the scene (so the tree is there at once), starts the WebGPU module, and
// fades to the live picture once it draws. Without WebGPU it shows a
// recording and stills of each look, rendered offline by the same code.
//
// URL parameters: ?look=<id> ?sky=night ?quality=high|medium|low
// ?recorded (force the recorded views) ?bench (measure frame time).

import { createChoices } from "./choices.js";

const params = new URLSearchParams(location.search);
const $ = (id) => document.getElementById(id);
const body = document.body;
const canvas = $("live");
const poster = $("poster");
const recording = $("recording");
const statusEl = $("status");
const lookRow = $("look-row");
const lookLine = $("look-line");
const hint = $("hint");

const state = {
  site: null,
  looks: [],
  look: params.get("look") || "frost",
  sky: params.get("sky") === "night" ? "night" : "blue",
  mode: "loading", // "live" | "recorded"
  tier: 0,
  interacted: false,
};

const choices = createChoices({ endpoint: null });

// Quality steps, best first: the renderer's tier and the share of the
// device's pixels drawn, capped by a pixel budget per tier.
const TIERS = [
  { quality: "high", scale: 1.0, budget: 2.6e6 },
  { quality: "high", scale: 0.82, budget: 2.0e6 },
  { quality: "medium", scale: 0.8, budget: 1.4e6 },
  { quality: "medium", scale: 0.66, budget: 1.0e6 },
  { quality: "low", scale: 0.58, budget: 0.7e6 },
  { quality: "low", scale: 0.48, budget: 0.48e6 },
  { quality: "minimum", scale: 0.42, budget: 0.33e6 },
  { quality: "minimum", scale: 0.34, budget: 0.22e6 },
];

// Where to start: a phone low, a tablet or a laptop (a high-density screen
// no wider than a laptop's) medium, a desktop high; the frame rate then
// steps it down.
function startingTier() {
  const asked = params.get("quality");
  if (asked === "high") return 0;
  if (asked === "medium") return 2;
  if (asked === "low") return 4;
  if (asked === "minimum") return 6;
  const coarse = matchMedia("(pointer: coarse)").matches;
  const small = Math.min(screen.width, screen.height) < 600;
  if (coarse && small) return 4;
  if (coarse) return 2;
  if ((devicePixelRatio || 1) >= 1.5 && screen.width <= 1800) return 2;
  return 0;
}

function canvasSize(tier) {
  const t = TIERS[tier];
  const dpr = Math.min(devicePixelRatio || 1, 2);
  let w = innerWidth * dpr * t.scale;
  let h = innerHeight * dpr * t.scale;
  const k = Math.min(1, Math.sqrt(t.budget / (w * h)));
  w = Math.max(64, Math.round(w * k));
  h = Math.max(64, Math.round(h * k));
  return [w, h];
}

// ---- The opening -------------------------------------------------------

const opened = performance.now();
function openFrame() {
  requestAnimationFrame(() => {
    body.classList.remove("opening");
    body.classList.add("opened");
  });
  const subs = [...document.querySelectorAll(".subtitle")];
  subs.forEach((s, i) => {
    const at = parseFloat(s.dataset.at) * 1000;
    const next = subs[i + 1] ? parseFloat(subs[i + 1].dataset.at) * 1000 : at + 5200;
    setTimeout(() => s.classList.add("shown"), at);
    setTimeout(() => s.classList.remove("shown"), next - 700);
  });
  setTimeout(() => {
    if (!state.interacted && state.mode !== "loading") {
      body.classList.add("show-hint");
      setTimeout(() => body.classList.remove("show-hint"), 6500);
    }
  }, 12500);
}
if (poster.complete) openFrame();
else {
  poster.addEventListener("load", openFrame, { once: true });
  poster.addEventListener("error", openFrame, { once: true });
}

function showStatus(text, ms = 0) {
  statusEl.textContent = text;
  statusEl.classList.toggle("shown", !!text);
  if (ms) setTimeout(() => statusEl.classList.remove("shown"), ms);
}

// ---- Looks -------------------------------------------------------------

function swatchCss(colors) {
  return `linear-gradient(to right, ${colors.join(", ")})`;
}

function renderLooks() {
  lookRow.replaceChildren(
    ...state.looks.map((look) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "look";
      b.dataset.look = look.id;
      b.setAttribute("aria-pressed", String(look.id === state.look));
      const sw = document.createElement("span");
      sw.className = "swatch";
      sw.style.background = swatchCss(look.swatch);
      sw.setAttribute("aria-hidden", "true");
      const name = document.createElement("span");
      name.textContent = look.name;
      b.append(sw, name);
      b.addEventListener("click", () => choices.choose(look.id, "visitor"));
      return b;
    }),
  );
  showLine();
}

function showLine() {
  const look = state.looks.find((l) => l.id === state.look);
  lookLine.classList.add("changing");
  setTimeout(() => {
    lookLine.textContent = look ? look.line : "";
    lookLine.classList.remove("changing");
  }, 220);
}

// On a narrow screen the row scrolls: keep the playing look in its middle.
function centreLook(behavior) {
  const b = lookRow.querySelector('.look[aria-pressed="true"]');
  if (b && lookRow.scrollWidth > lookRow.clientWidth) {
    const left = b.offsetLeft + b.offsetWidth / 2 - lookRow.clientWidth / 2;
    lookRow.scrollTo({ left, behavior });
  }
}
addEventListener("resize", () => centreLook("instant"));

// The playing look's controls: thin sliders, no numbers. The site eases
// the picture to each new position; a new look starts from its own values.
const adjust = $("adjust");
const adjustBtn = $("adjust-btn");
// Where the visitor put each slider, for the playing look (kept across a
// rebuild of the row, cleared when the look changes).
let controlPositions = {};
function renderControls() {
  if (state.mode !== "live" || !state.site) {
    adjust.hidden = true;
    adjustBtn.hidden = true;
    return;
  }
  const list = JSON.parse(state.site.controls());
  adjust.replaceChildren(
    ...list.map((c) => {
      const label = document.createElement("label");
      label.className = "control";
      const name = document.createElement("span");
      name.textContent = c.label;
      const input = document.createElement("input");
      input.type = "range";
      input.min = "0";
      input.max = "1";
      input.step = "0.001";
      const at = controlPositions[c.id] ?? c.position;
      input.value = String(at);
      input.style.setProperty("--fill", `${at * 100}%`);
      input.addEventListener("input", () => {
        const v = Number(input.value);
        input.style.setProperty("--fill", `${v * 100}%`);
        controlPositions[c.id] = v;
        state.site.set_control(c.id, v);
        choices.adjust(state.look, c.id, v);
        interacted();
      });
      label.append(name, input);
      return label;
    }),
  );
  adjustBtn.hidden = false;
  const narrow = matchMedia("(max-width: 720px)").matches;
  adjust.hidden = narrow && adjustBtn.getAttribute("aria-expanded") !== "true";
}
adjustBtn.addEventListener("click", () => {
  const open = adjustBtn.getAttribute("aria-expanded") !== "true";
  adjustBtn.setAttribute("aria-expanded", String(open));
  adjust.hidden = !open;
});
matchMedia("(max-width: 720px)").addEventListener("change", renderControls);

choices.onChoice(({ look, source }) => {
  state.look = look;
  for (const b of lookRow.querySelectorAll(".look")) {
    b.setAttribute("aria-pressed", String(b.dataset.look === look));
  }
  centreLook(source === "visitor" ? "smooth" : "instant");
  showLine();
  if (state.mode === "live") {
    state.site.set_look(look);
    controlPositions = {};
    renderControls();
  }
  if (state.mode === "recorded") showRecorded();
  const url = new URL(location.href);
  url.searchParams.set("look", look);
  history.replaceState(null, "", url);
});

for (const b of document.querySelectorAll(".hour-btn")) {
  b.addEventListener("click", () => setSky(b.dataset.sky));
}
function setSky(sky) {
  state.sky = sky;
  for (const b of document.querySelectorAll(".hour-btn")) {
    b.setAttribute("aria-pressed", String(b.dataset.sky === sky));
  }
  if (state.mode === "live") state.site.set_sky(sky);
  if (state.mode === "recorded") showRecorded();
  const url = new URL(location.href);
  if (sky === "night") url.searchParams.set("sky", "night");
  else url.searchParams.delete("sky");
  history.replaceState(null, "", url);
}

// The story card.
const story = $("story");
const storyBtn = $("story-btn");
function toggleStory(open = story.hidden) {
  story.hidden = !open;
  storyBtn.setAttribute("aria-expanded", String(open));
  if (open) $("story-close").focus({ preventScroll: true });
  else storyBtn.focus({ preventScroll: true });
}
storyBtn.addEventListener("click", () => toggleStory());
$("story-close").addEventListener("click", () => toggleStory(false));
addEventListener("keydown", (e) => {
  if (e.key === "Escape" && !story.hidden) toggleStory(false);
});

// ---- The recorded views (no WebGPU) -------------------------------------

function stillUrl(look, sky) {
  return `media/poster-${look}-${sky}.webp`;
}

function showRecorded() {
  const isDefault = state.look === "frost" && state.sky === "blue";
  if (isDefault && recording.dataset.ready) {
    recording.classList.add("playing");
    recording.play().catch(() => {});
  } else {
    recording.classList.remove("playing");
    recording.pause();
  }
  const next = stillUrl(state.look, state.sky);
  if (!poster.src.endsWith(next)) {
    const img = new Image();
    img.onload = () => {
      poster.style.opacity = "0";
      setTimeout(() => {
        poster.src = next;
        poster.style.opacity = "";
      }, 400);
    };
    img.src = next;
  }
}

function startRecorded(reason) {
  state.mode = "recorded";
  body.classList.add("is-recorded");
  canvas.hidden = true;
  hint.textContent = "Recorded views. Open in a browser with WebGPU to see it live.";
  body.classList.add("show-hint");
  const source = document.createElement("source");
  source.src = "media/drift-frost-blue.mp4";
  source.type = "video/mp4";
  recording.append(source);
  recording.preload = "auto";
  recording.addEventListener(
    "canplay",
    () => {
      recording.dataset.ready = "1";
      showRecorded();
    },
    { once: true },
  );
  recording.load();
  showRecorded();
  console.info("The Oslo Tree: recorded views,", reason);
}

// ---- The live scene ----------------------------------------------------

async function startLive() {
  const { default: init, Site } = await import("./li_oslo_site.js");
  await init();
  state.tier = startingTier();
  const [w, h] = canvasSize(state.tier);
  canvas.width = w;
  canvas.height = h;
  const site = await Site.create(canvas, TIERS[state.tier].quality, state.look, params.has("profile"));
  state.site = site;
  if (state.sky === "night") site.set_sky("night");
  if (params.has("debug")) site.set_debug(params.get("debug"));
  if (params.has("orbit")) {
    const [a, e, d] = params.get("orbit").split(",").map(Number);
    site.set_orbit(a, e, d);
  }
  state.mode = "live";
  window.oslo = {
    site,
    stats: () => JSON.parse(site.stats()),
    tiers: TIERS,
    state,
    // GPU time per pass group of a frame (with ?profile), resolved as JSON.
    profile: () =>
      new Promise((resolve) => {
        site.request_profile();
        const t = setInterval(() => {
          const r = site.profile_result();
          if (r) {
            clearInterval(t);
            resolve(r);
          }
        }, 50);
      }),
  };
  bindPointer();
  renderControls();
  addEventListener("resize", resize);
  if (params.has("bench")) await bench(site);
  let frames = 0;
  const loop = () => {
    site.frame();
    frames += 1;
    if (frames === 3) body.classList.add("is-live");
    adapt();
    updateStats(performance.now());
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);
}

function resize() {
  if (!state.site) return;
  const [w, h] = canvasSize(state.tier);
  if (w !== canvas.width || h !== canvas.height) {
    canvas.width = w;
    canvas.height = h;
    state.site.resize(w, h);
  }
}

// Step down while the frame rate is under 50 (two steps under 32), after
// 2.5 s to settle, judged every 1.5 s. Never steps back up within a visit.
const adaptState = { since: 0, frames: 0, start: 0 };
function adapt() {
  if (params.has("quality")) return;
  const now = performance.now();
  if (!adaptState.start) {
    adaptState.start = now;
    adaptState.since = now;
    return;
  }
  adaptState.frames += 1;
  if (now - adaptState.start < 2500) {
    adaptState.since = now;
    adaptState.frames = 0;
    return;
  }
  if (now - adaptState.since < 1500) return;
  const fps = (adaptState.frames * 1000) / (now - adaptState.since);
  adaptState.since = now;
  adaptState.frames = 0;
  if (document.hidden) return;
  if (fps < 50 && state.tier < TIERS.length - 1) {
    const before = TIERS[state.tier].quality;
    state.tier = Math.min(TIERS.length - 1, state.tier + (fps < 32 ? 2 : 1));
    if (TIERS[state.tier].quality !== before) state.site.set_quality(TIERS[state.tier].quality);
    resize();
    console.info(`The Oslo Tree: ${fps.toFixed(1)} fps, now ${TIERS[state.tier].quality} at ${canvas.width}×${canvas.height}`);
  }
}

// ?stats: the numbers on the page, for measuring on other machines. The
// GPU figure is the time from a frame's submission to the GPU going idle,
// sampled every second: about the GPU's time for one frame.
const statsState = { el: null, frames: [], gpu: 0, cpu: 0, last: 0, busy: false };
function updateStats(now) {
  if (!params.has("stats") || !state.site) return;
  if (!statsState.el) {
    const el = document.createElement("pre");
    el.className = "stats";
    document.body.append(el);
    statsState.el = el;
  }
  statsState.frames.push(now);
  while (statsState.frames.length && now - statsState.frames[0] > 2000) statsState.frames.shift();
  if (now - statsState.last < 1000 || statsState.busy) return;
  statsState.last = now;
  statsState.busy = true;
  const t0 = performance.now();
  state.site.gpu_idle().then(() => {
    statsState.gpu = performance.now() - t0;
    statsState.busy = false;
  });
  const s = JSON.parse(state.site.stats());
  const f = statsState.frames;
  const fps = f.length > 1 ? ((f.length - 1) * 1000) / (f[f.length - 1] - f[0]) : 0;
  const t = TIERS[state.tier];
  statsState.el.textContent = [
    `${fps.toFixed(1)} fps   ${(1000 / Math.max(fps, 1e-3)).toFixed(1)} ms a frame`,
    `CPU ${s.frame_ms_mean.toFixed(2)} ms (p95 ${s.frame_ms_p95.toFixed(2)})   GPU ≈ ${statsState.gpu.toFixed(1)} ms`,
    `tier ${state.tier} ${t.quality} × ${t.scale}   ${s.size[0]}×${s.size[1]}   mirror ${s.mirror[0]}×${s.mirror[1]} every ${s.mirror_every}`,
    `${s.adapter}   loaded in ${(s.load_ms / 1000).toFixed(2)} s, ${(s.bytes / 1e6).toFixed(1)} MB`,
  ].join("\n");
}

function interacted() {
  if (!state.interacted) {
    state.interacted = true;
    body.classList.remove("show-hint");
  }
}

function bindPointer() {
  const pointers = new Map();
  let pinch = 0;
  canvas.addEventListener("pointerdown", (e) => {
    canvas.setPointerCapture(e.pointerId);
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    interacted();
  });
  canvas.addEventListener("pointermove", (e) => {
    const p = pointers.get(e.pointerId);
    if (!p) return;
    if (pointers.size === 1) {
      state.site.drag(e.clientX - p.x, e.clientY - p.y, innerHeight);
    } else if (pointers.size === 2) {
      const [a, b] = [...pointers.values()];
      const d0 = Math.hypot(a.x - b.x, a.y - b.y);
      p.x = e.clientX;
      p.y = e.clientY;
      const [c, d] = [...pointers.values()];
      const d1 = Math.hypot(c.x - d.x, c.y - d.y);
      if (d0 > 0 && pinch) state.site.zoom(d1 / d0);
      pinch = 1;
      return;
    }
    p.x = e.clientX;
    p.y = e.clientY;
  });
  const up = (e) => {
    pointers.delete(e.pointerId);
    if (pointers.size < 2) pinch = 0;
  };
  canvas.addEventListener("pointerup", up);
  canvas.addEventListener("pointercancel", up);
  canvas.addEventListener(
    "wheel",
    (e) => {
      e.preventDefault();
      interacted();
      state.site.zoom(Math.exp(-e.deltaY * 0.0015));
    },
    { passive: false },
  );
  canvas.addEventListener("keydown", (e) => {
    const step = { ArrowLeft: [-40, 0], ArrowRight: [40, 0], ArrowUp: [0, -30], ArrowDown: [0, 30] }[e.key];
    if (step) {
      e.preventDefault();
      interacted();
      state.site.drag(step[0], step[1], innerHeight);
    } else if (e.key === "+" || e.key === "=") state.site.zoom(1.12);
    else if (e.key === "-") state.site.zoom(1 / 1.12);
  });
}

// Frame time with the GPU in it: batches of frames back to back, each
// ended by the GPU going idle; the median batch's time per frame.
async function bench(site) {
  const frames = Number(params.get("frames") || 60);
  const rounds = Number(params.get("rounds") || 5);
  for (let i = 0; i < 30; i++) site.frame();
  await site.gpu_idle();
  const per = [];
  for (let r = 0; r < rounds; r++) {
    const t0 = performance.now();
    for (let i = 0; i < frames; i++) site.frame();
    await site.gpu_idle();
    per.push((performance.now() - t0) / frames);
  }
  per.sort((a, b) => a - b);
  const result = { frame_ms_median: per[Math.floor(per.length / 2)], rounds: per, size: [canvas.width, canvas.height], quality: TIERS[state.tier].quality };
  window.osloBench = result;
  console.info("The Oslo Tree bench", JSON.stringify(result));
}

// ---- Start -------------------------------------------------------------

(async () => {
  try {
    state.looks = await (await fetch("looks.json")).json();
  } catch {
    state.looks = [];
  }
  if (!state.looks.some((l) => l.id === state.look)) state.look = state.looks[0]?.id ?? "frost";
  renderLooks();
  choices.choose(state.look, params.has("look") ? "link" : "default");
  setSky(state.sky);
  if (state.sky !== "blue" || state.look !== "frost") poster.src = stillUrl(state.look, state.sky);

  let adapter = null;
  if (!params.has("recorded") && navigator.gpu) {
    try {
      adapter = await navigator.gpu.requestAdapter({ powerPreference: "high-performance" });
    } catch {
      adapter = null;
    }
  }
  if (!adapter) {
    startRecorded(navigator.gpu ? "no adapter" : "no WebGPU");
    return;
  }
  const slow = setTimeout(() => showStatus("Lighting the tree"), 2500);
  try {
    await startLive();
  } catch (e) {
    console.error(e);
    startRecorded(String(e));
  } finally {
    clearTimeout(slow);
    showStatus("");
  }
  window.osloLoadMs = performance.now() - opened;
})();
