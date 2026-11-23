// The Oslo Tree: the page around the live scene. It opens on a still of
// the scene (so the tree is there at once) with a loading mark over it,
// fetches the module and the tree (the mark shows how much has arrived),
// starts WebGPU, and fades to the live picture once it draws. Without
// WebGPU it shows a recording and stills of each look, rendered offline by
// the same code.
//
// URL parameters: ?look=<id> ?sky=blue ?quality=high|medium|low|minimum
// ?recorded (force the recorded views) ?bench (measure frame time)
// ?stats (frame times on the page).

import { createChoices } from "./choices.js";

const params = new URLSearchParams(location.search);
const $ = (id) => document.getElementById(id);
const body = document.body;
const canvas = $("live");
const poster = $("poster");
const recording = $("recording");
const lookRow = $("look-row");
const lookLine = $("look-line");
const hint = $("hint");

const state = {
  site: null,
  looks: [],
  look: params.get("look") || "starlings",
  sky: params.get("sky") === "blue" ? "blue" : "night",
  mode: "loading", // "live" | "recorded"
  tier: 0,
  interacted: false,
};

const choices = createChoices({ endpoint: null });
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
// A window too small to keep the sliders out: they fold behind "Adjust"
// (the stylesheet's own breakpoint).
const compact = matchMedia("(max-width: 720px), (max-height: 720px)");

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
}
if (poster.complete) openFrame();
else {
  poster.addEventListener("load", openFrame, { once: true });
  poster.addEventListener("error", openFrame, { once: true });
}

// The subtitles follow the loading (they sit where the loading mark was),
// no sooner than the opening's own timing.
let subtitlesEnd = 0;
function startSubtitles() {
  const shift = Math.max(0, performance.now() - opened - 1600 + 900);
  subtitlesEnd = opened + 12300 + shift;
  const subs = [...document.querySelectorAll(".subtitle")];
  subs.forEach((s, i) => {
    const at = parseFloat(s.dataset.at) * 1000 + shift;
    const next = subs[i + 1] ? parseFloat(subs[i + 1].dataset.at) * 1000 + shift : at + 5200;
    setTimeout(() => s.classList.add("shown"), at - (performance.now() - opened));
    setTimeout(() => s.classList.remove("shown"), next - 700 - (performance.now() - opened));
  });
  setTimeout(() => {
    if (!state.interacted && state.mode === "live") {
      body.classList.add("show-hint");
      setTimeout(() => body.classList.remove("show-hint"), 6500);
    }
  }, 12500 + shift - (performance.now() - opened));
}

// ---- Loading -------------------------------------------------------------

// The leaf's ten lights, in the order a leaf of the tree is wired: up its
// left side from the stem, then down its right.
const loader = {
  el: $("loader"),
  line: $("loader-line"),
  retry: $("loader-retry"),
  leaf: document.querySelector(".leaf"),
  lights: [],
  shown: 0,
};
{
  const ns = "http://www.w3.org/2000/svg";
  const rows = [44, 37, 30, 23, 16];
  const order = [...rows.map((y) => [20.6, y]), ...[...rows].reverse().map((y) => [27.4, y])];
  order.forEach(([x, y], i) => {
    const c = document.createElementNS(ns, "circle");
    c.setAttribute("cx", String(x));
    c.setAttribute("cy", String(y));
    c.setAttribute("r", "1.9");
    c.style.setProperty("--i", String(i));
    $("leaf-lights").append(c);
    loader.lights.push(c);
  });
}

/** Show `share` (0 to 1) of the tree as arrived. */
function setProgress(share) {
  const p = Math.max(loader.shown, Math.min(1, share));
  loader.shown = p;
  loader.leaf.style.setProperty("--p", p.toFixed(3));
  loader.el.setAttribute("aria-valuenow", String(Math.round(p * 100)));
  const lit = p * loader.lights.length;
  loader.lights.forEach((c, i) => {
    const on = Math.max(0, Math.min(1, lit - i));
    c.style.setProperty("--on", on.toFixed(3));
    c.classList.toggle("lit", on >= 1);
    c.classList.toggle("next", on < 1 && i === Math.floor(lit));
  });
}
setProgress(0);

function setLoaderLine(text) {
  if (loader.line.textContent === text) return;
  loader.line.classList.add("changing");
  setTimeout(() => {
    loader.line.textContent = text;
    loader.line.classList.remove("changing");
  }, 200);
}

/** The loading is over: the mark fades with the live frame coming up. */
function endLoading() {
  if (!body.classList.contains("is-loading")) return;
  setProgress(1);
  body.classList.remove("is-loading");
  loader.el.removeAttribute("aria-valuenow");
  setTimeout(() => (loader.el.hidden = true), 1000);
  startSubtitles();
}

/** The tree did not arrive: say so, with a way to try again. */
function failLoading(retry) {
  loader.el.classList.add("failed");
  for (const c of loader.lights) c.classList.remove("next");
  setLoaderLine(navigator.onLine === false
    ? "You seem to be offline. The tree will light when you are back."
    : "The tree didn't arrive. Check the connection and try again.");
  loader.retry.hidden = false;
  loader.retry.onclick = () => {
    loader.retry.hidden = true;
    loader.el.classList.remove("failed");
    setLoaderLine("Lighting the tree");
    retry();
  };
  if (navigator.onLine === false) addEventListener("online", () => loader.retry.click(), { once: true });
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
  markRowEdges();
}

function showLine() {
  const look = state.looks.find((l) => l.id === state.look);
  lookLine.classList.add("changing");
  setTimeout(() => {
    lookLine.textContent = look ? look.line : "";
    lookLine.classList.remove("changing");
  }, 220);
}

// Where the window is narrower than the row, the row scrolls: keep the
// playing look in its middle, and mark each edge that has more beyond it
// (the stylesheet fades that edge and, with a mouse, shows an arrow there).
const lookStrip = $("look-strip");
const rowPrev = $("row-prev");
const rowNext = $("row-next");
function centreLook(behavior) {
  const b = lookRow.querySelector('.look[aria-pressed="true"]');
  if (b && lookRow.scrollWidth > lookRow.clientWidth) {
    const left = b.offsetLeft + b.offsetWidth / 2 - lookRow.clientWidth / 2;
    lookRow.scrollTo({ left, behavior });
  }
}
function markRowEdges() {
  const max = lookRow.scrollWidth - lookRow.clientWidth;
  const start = lookRow.scrollLeft > 4;
  const end = lookRow.scrollLeft < max - 4;
  lookStrip.dataset.more = [start && "start", end && "end"].filter(Boolean).join(" ");
  rowPrev.hidden = !start;
  rowNext.hidden = !end;
}
lookRow.addEventListener("scroll", markRowEdges, { passive: true });
new ResizeObserver(() => {
  centreLook("instant");
  markRowEdges();
}).observe(lookRow);
for (const [button, way] of [[rowPrev, -1], [rowNext, 1]]) {
  button.addEventListener("click", () => {
    lookRow.scrollBy({ left: way * Math.max(160, lookRow.clientWidth * 0.6), behavior: reducedMotion.matches ? "instant" : "smooth" });
  });
}

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
  adjust.hidden = compact.matches && adjustBtn.getAttribute("aria-expanded") !== "true";
}
adjustBtn.addEventListener("click", () => {
  const open = adjustBtn.getAttribute("aria-expanded") !== "true";
  adjustBtn.setAttribute("aria-expanded", String(open));
  adjust.hidden = !open;
});
compact.addEventListener("change", renderControls);

choices.onChoice(({ look, source }) => {
  state.look = look;
  for (const b of lookRow.querySelectorAll(".look")) {
    b.setAttribute("aria-pressed", String(b.dataset.look === look));
  }
  centreLook(source === "visitor" && !reducedMotion.matches ? "smooth" : "instant");
  showLine();
  if (state.mode === "live") {
    state.site.set_look(look);
    controlPositions = {};
    renderControls();
  }
  if (state.mode === "recorded") showRecorded();
  if (state.mode === "loading") showStill();
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
  if (state.mode === "loading") showStill();
  const url = new URL(location.href);
  if (sky === "blue") url.searchParams.set("sky", "blue");
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
// A press on the scene puts the card away (without moving the focus there).
$("stage").addEventListener("pointerdown", (e) => {
  if (!story.hidden && !e.target.closest(".story, .story-btn")) {
    story.hidden = true;
    storyBtn.setAttribute("aria-expanded", "false");
  }
});

// ---- The recorded views (no WebGPU) -------------------------------------

// Stills come wide and upright (for a screen taller than 4:5, a phone).
const tall = matchMedia("(max-aspect-ratio: 4/5)");
const posterTall = $("poster-tall");
function stillUrl(look, sky, upright = tall.matches) {
  return `media/poster-${look}-${sky}${upright ? "-tall" : ""}.webp`;
}

const DEFAULT_LOOK = "starlings";
const DEFAULT_SKY = "night";

function showRecorded() {
  const isDefault = state.look === DEFAULT_LOOK && state.sky === DEFAULT_SKY;
  if (isDefault && recording.dataset.ready) {
    recording.classList.add("playing");
    recording.play().catch(() => {});
  } else {
    recording.classList.remove("playing");
    recording.pause();
  }
  showStill();
}

// The still of the chosen look and hour, cross-faded in once it has loaded.
function showStill() {
  const next = stillUrl(state.look, state.sky);
  if (!(poster.currentSrc || poster.src).endsWith(next)) {
    const img = new Image();
    img.onload = () => {
      poster.style.opacity = "0";
      setTimeout(() => {
        posterTall.srcset = stillUrl(state.look, state.sky, true);
        poster.src = stillUrl(state.look, state.sky, false);
        poster.style.opacity = "";
      }, 400);
    };
    img.src = next;
  }
}

function startRecorded(reason, failed = false, stopped = false) {
  state.mode = "recorded";
  state.site = null;
  endLoading();
  body.classList.remove("is-live");
  body.classList.add("is-recorded");
  canvas.hidden = true;
  renderControls();
  // The note takes the subtitles' place once they have played.
  hint.textContent = stopped
    ? "The live tree stopped. These are recorded views."
    : failed
    ? "The live tree couldn't start in this browser. These are recorded views."
    : "Recorded views. Open in a browser with WebGPU to see it live.";
  setTimeout(() => body.classList.add("show-hint"), Math.max(0, subtitlesEnd - performance.now()));
  const source = document.createElement("source");
  source.src = `media/drift-${DEFAULT_LOOK}-${DEFAULT_SKY}.mp4`;
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

// Everything the tree needs before it can light, fetched here so the mark
// can show how much has arrived: the share of each file's bytes read,
// weighted by its size as gzip (about what crosses the network), from the
// sizes the build wrote into manifest.json. Kept across a retry.
const fetched = {};
let wasmBytes = null;

class NetworkError extends Error {}

// Fetch `url`, calling `progress(bytesRead)` as it streams; gives up if no
// bytes arrive for 30 s.
async function fetchBytes(url, progress) {
  const abort = new AbortController();
  let stall = setTimeout(() => abort.abort(), 30000);
  try {
    const response = await fetch(url, { signal: abort.signal });
    if (!response.ok) throw new NetworkError(`${url}: HTTP ${response.status}`);
    if (!response.body) {
      const bytes = new Uint8Array(await response.arrayBuffer());
      progress(bytes.length);
      return bytes;
    }
    const reader = response.body.getReader();
    const chunks = [];
    let read = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
      read += value.length;
      progress(read);
      clearTimeout(stall);
      stall = setTimeout(() => abort.abort(), 30000);
    }
    const bytes = new Uint8Array(read);
    let at = 0;
    for (const c of chunks) {
      bytes.set(c, at);
      at += c.length;
    }
    return bytes;
  } catch (e) {
    throw e instanceof NetworkError ? e : new NetworkError(`${url}: ${e?.message ?? e}`);
  } finally {
    clearTimeout(stall);
  }
}

async function fetchTree() {
  if (!fetched["manifest.json"]) fetched["manifest.json"] = await fetchBytes("manifest.json", () => {});
  const manifest = JSON.parse(new TextDecoder().decode(fetched["manifest.json"]));
  const sizes = manifest.sizes ?? {};
  const wanted = Object.keys(sizes);
  const total = wanted.reduce((s, f) => s + sizes[f][1], 0) || 1;
  const share = Object.fromEntries(wanted.map((f) => [f, f in fetched || (f.endsWith(".wasm") && wasmBytes) ? 1 : 0]));
  const report = () => setProgress(0.9 * wanted.reduce((s, f) => s + share[f] * sizes[f][1], 0) / total);
  report();
  const glue = import("./li_oslo_site.js").catch((e) => {
    throw new NetworkError(String(e));
  });
  glue.catch(() => {});
  await Promise.all(
    wanted.map(async (f) => {
      if (share[f] === 1) return;
      const bytes = await fetchBytes(f, (n) => {
        share[f] = Math.min(1, n / sizes[f][0]);
        report();
      });
      if (f.endsWith(".wasm")) wasmBytes = bytes;
      else fetched[f] = bytes;
      share[f] = 1;
      report();
    }),
  );
  return glue;
}

async function startLive() {
  const { default: init, Site } = await fetchTree();
  setLoaderLine("Almost there");
  await init(wasmBytes ? { module_or_path: wasmBytes } : undefined);
  wasmBytes = null;
  state.tier = startingTier();
  const [w, h] = canvasSize(state.tier);
  canvas.width = w;
  canvas.height = h;
  const site = await Site.create(canvas, TIERS[state.tier].quality, state.look, params.has("profile"), fetched);
  for (const k of Object.keys(fetched)) delete fetched[k];
  state.site = site;
  if (!state.looks.length) {
    // looks.json did not arrive: the module carries the same list.
    state.looks = JSON.parse(Site.looks());
    renderLooks();
  }
  site.set_sky(state.sky);
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
  addEventListener("resize", () => (resizeAt = performance.now()));
  matchMedia("(resolution: 1dppx)").addEventListener("change", () => (resizeAt = performance.now()));
  if (params.has("bench")) await bench(site);
  let frames = 0;
  const loop = () => {
    if (state.site !== site) return;
    // A frame that throws (the module trapped), a lost GPU device, or
    // frame after frame failing to draw ends the live scene.
    let failure;
    try {
      // The canvas takes the window's new size once it has held it for a
      // moment (the stylesheet stretches the picture meanwhile): resizing
      // on every event of a drag would rebuild every render target each time.
      if (resizeAt && performance.now() - resizeAt > 120) {
        resizeAt = 0;
        resize();
      }
      site.frame();
      failure = site.failure();
    } catch (e) {
      failure = String(e);
    }
    if (failure) {
      liveFailed(failure);
      return;
    }
    frames += 1;
    if (frames === 3) {
      body.classList.add("is-live");
      endLoading();
      window.osloLoadMs = performance.now() - opened;
    }
    adapt();
    updateStats(performance.now());
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);
}

// The live scene stopped. A lost GPU device usually comes back, so start
// the page afresh once (its files are cached, and the still covers the
// gap), when the page is next looked at; if it stops again within a
// minute, or the page cannot remember that it tried, show the recorded
// views instead.
function liveFailed(reason) {
  console.error("The Oslo Tree: the live scene stopped:", reason);
  state.site = null;
  let again = false;
  try {
    const last = Number(sessionStorage.getItem("oslo-relit")) || 0;
    if (Date.now() - last > 60000) {
      sessionStorage.setItem("oslo-relit", String(Date.now()));
      again = true;
    }
  } catch {
    again = false;
  }
  if (!again) {
    startRecorded(reason, true, true);
    return;
  }
  body.classList.remove("is-live");
  if (document.hidden) addEventListener("visibilitychange", () => location.reload(), { once: true });
  else location.reload();
}

let resizeAt = 0;
function resize() {
  if (!state.site) return;
  const [w, h] = canvasSize(state.tier);
  if (w !== canvas.width || h !== canvas.height) {
    canvas.width = w;
    canvas.height = h;
    state.site.resize(w, h);
  }
}

// Step down while the frame rate is under 50 (two steps under 32), judged
// every 1.5 s, and only on steady frames: a gap of over 250 ms between two
// frames, or a hidden page, means the browser paused or throttled the
// page (a background tab, a tab Chrome slows while still calling it
// visible), not that the tree is slow, so it discards the window and waits
// for 2.5 s of steady frames again. Never steps back up within a visit.
const adaptState = { last: 0, steady: 0, since: 0, frames: 0 };
function adapt() {
  if (params.has("quality")) return;
  const now = performance.now();
  const gap = adaptState.last ? now - adaptState.last : Infinity;
  adaptState.last = now;
  if (gap > 250 || document.hidden) {
    adaptState.steady = now;
    adaptState.since = now;
    adaptState.frames = 0;
    return;
  }
  if (now - adaptState.steady < 2500) {
    adaptState.since = now;
    adaptState.frames = 0;
    return;
  }
  adaptState.frames += 1;
  if (now - adaptState.since < 1500) return;
  const fps = (adaptState.frames * 1000) / (now - adaptState.since);
  adaptState.since = now;
  adaptState.frames = 0;
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
      state.site?.drag(e.clientX - p.x, e.clientY - p.y, innerHeight);
    } else if (pointers.size === 2) {
      const [a, b] = [...pointers.values()];
      const d0 = Math.hypot(a.x - b.x, a.y - b.y);
      p.x = e.clientX;
      p.y = e.clientY;
      const [c, d] = [...pointers.values()];
      const d1 = Math.hypot(c.x - d.x, c.y - d.y);
      if (d0 > 0 && pinch) state.site?.zoom(d1 / d0);
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
  // The wheel comes closer anywhere on the page (the names and sliders
  // lie over the scene), except where it has something to scroll: the
  // story card, and the row of looks under a sideways wheel. A trackpad's
  // pinch arrives as a wheel with ctrl held, in smaller steps.
  $("stage").addEventListener(
    "wheel",
    (e) => {
      if (!state.site || e.target.closest(".story")) return;
      const sideways = Math.abs(e.deltaX) > Math.abs(e.deltaY);
      if (sideways && e.target.closest(".look-row")) return;
      e.preventDefault();
      interacted();
      const lines = e.deltaMode === 1 ? 16 : 1;
      // Two fingers sideways on a trackpad turn the scene, as a drag does.
      if (sideways) state.site.drag(-e.deltaX * lines * 0.6, 0, innerHeight);
      else state.site.zoom(Math.exp(-e.deltaY * lines * (e.ctrlKey ? 0.012 : 0.0015)));
    },
    { passive: false },
  );
  canvas.addEventListener("keydown", (e) => {
    if (!state.site) return;
    const step = { ArrowLeft: [-40, 0], ArrowRight: [40, 0], ArrowUp: [0, -30], ArrowDown: [0, 30] }[e.key];
    if (step) {
      e.preventDefault();
      interacted();
      state.site.drag(step[0], step[1], innerHeight);
    } else if (e.key === "+" || e.key === "=") state.site.zoom(1.12);
    else if (e.key === "-") state.site.zoom(1 / 1.12);
  });
  // With the keyboard on the scene, say what the keys do.
  canvas.addEventListener("focus", () => {
    if (!canvas.matches(":focus-visible") || state.mode !== "live" || performance.now() < subtitlesEnd) return;
    hint.textContent = "Arrow keys to look around, + and − to come closer";
    body.classList.add("show-hint");
    setTimeout(() => body.classList.remove("show-hint"), 6500);
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
    const response = await fetch("looks.json");
    if (!response.ok) throw new Error(`looks.json: HTTP ${response.status}`);
    state.looks = await response.json();
  } catch {
    state.looks = [];
  }
  if (!state.looks.some((l) => l.id === state.look)) state.look = state.looks[0]?.id ?? DEFAULT_LOOK;
  renderLooks();
  choices.choose(state.look, params.has("look") ? "link" : "default");
  setSky(state.sky);
  if (state.sky !== DEFAULT_SKY || state.look !== DEFAULT_LOOK) {
    posterTall.srcset = stillUrl(state.look, state.sky, true);
    poster.src = stillUrl(state.look, state.sky, false);
  }

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
  const attempt = async () => {
    try {
      await startLive();
    } catch (e) {
      console.error(e);
      if (e instanceof NetworkError) failLoading(attempt);
      else startRecorded(String(e), true);
    }
  };
  await attempt();
})();
