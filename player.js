// The Oslo Tree's music: a small player low in the frame, and the tree
// moving with what it plays.
//
// The browser plays the track (an <audio> element: streamed, nothing
// decoded here) and nothing plays until the visitor asks. The build
// analysed each track ahead of time into its bands (music/<id>.bands,
// about 1 KB a second); the live scene is given those once, and then, at
// every frame while the track sounds, the position being heard, so the
// light lands on the sound. The tracks are listed in music/tracks.json,
// written by the build from apps/oslo-site/music; without one there is no
// player.
//
// The position is the element's own clock (currentTime). That clock is
// the one a browser keeps video in step with sound by, so it is already
// the sound leaving the speakers as far as the browser knows the output's
// delay; an AudioContext's outputLatency taken off it again would count
// the delay twice. The light is asked for a little ahead of it (LEAD_S):
// the frame drawn now is on the screen a frame or two later, and a sound
// shows in its bands a few milliseconds after it starts. ?lead=<ms> sets
// another lead, for checking on a given screen and speakers.

const LEAD_S = 0.04;

// For a visitor who asks for less motion the tree still moves with the
// music, by about a third as much.
const CALM_STRENGTH = 0.35;

const NS = "http://www.w3.org/2000/svg";

function svg(viewBox, ...children) {
  const el = document.createElementNS(NS, "svg");
  el.setAttribute("viewBox", viewBox);
  el.setAttribute("aria-hidden", "true");
  el.setAttribute("focusable", "false");
  for (const [tag, attrs] of children) {
    const c = document.createElementNS(NS, tag);
    for (const [k, v] of Object.entries(attrs)) c.setAttribute(k, v);
    el.append(c);
  }
  return el;
}

function el(tag, props = {}, ...children) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === "class") e.className = v;
    else if (k in e && typeof v !== "string") e[k] = v;
    else e.setAttribute(k, v);
  }
  e.append(...children);
  return e;
}

/** 83 as "1:23". */
function clock(seconds) {
  const s = Math.max(0, Math.floor(seconds));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

/**
 * Put the player on the page if there are tracks. `site()` returns the
 * live scene (or nothing, while it loads and where there is none); `lead`
 * is ?lead's value, if given.
 */
export async function createPlayer({ site, lead }) {
  let tracks = [];
  try {
    const response = await fetch("music/tracks.json");
    if (response.ok) tracks = await response.json();
  } catch {
    tracks = [];
  }
  if (!Array.isArray(tracks) || !tracks.length) return null;

  const leadS = Number.isFinite(parseFloat(lead)) ? parseFloat(lead) / 1000 : LEAD_S;
  const calm = matchMedia("(prefers-reduced-motion: reduce)");
  const audio = new Audio();
  audio.preload = "none";

  // ---- The controls ------------------------------------------------------

  const play = el(
    "button",
    { type: "button", class: "player-play" },
    svg(
      "0 0 44 44",
      ["circle", { class: "player-ripple", cx: "22", cy: "22", r: "19.5" }],
      ["circle", { class: "player-ring", cx: "22", cy: "22", r: "19.5" }],
      ["path", { class: "player-glyph-play", d: "M18.2 14.6v14.8L30 22z" }],
      ["path", { class: "player-glyph-pause", d: "M17.5 15v14M26.5 15v14" }],
    ),
  );
  const title = el("span", { class: "player-title" });
  const artist = el("span", { class: "player-artist" });
  const seek = el("input", {
    type: "range",
    class: "player-seek",
    min: "0",
    max: "1",
    step: "1",
    value: "0",
    "aria-label": "Position in the track",
  });
  const next = el(
    "button",
    { type: "button", class: "player-next", "aria-label": "Next track", hidden: tracks.length < 2 },
    svg("0 0 32 32", ["path", { d: "M11 10.5v11l8.5-5.5zM21.5 10.5v11" }]),
  );
  const mute = el(
    "button",
    { type: "button", class: "player-mute", "aria-label": "Mute", "aria-pressed": "false" },
    svg(
      "0 0 32 32",
      ["path", { d: "M8.5 13.2h3.2l4.3-3.7v13l-4.3-3.7H8.5z" }],
      ["path", { class: "player-waves", d: "M19.6 12.6a4.8 4.8 0 0 1 0 6.8M22.3 10a8.5 8.5 0 0 1 0 12" }],
      ["path", { class: "player-cross", d: "M20 13l5.5 6M25.5 13L20 19" }],
    ),
  );
  const root = el(
    "section",
    { class: "player", "aria-label": "Music" },
    play,
    el("div", { class: "player-track" }, el("p", { class: "player-name" }, title, artist), seek),
    next,
    mute,
  );
  root.dataset.state = "idle";

  // Low in the frame with the looks; on a page without that column, in
  // the frame's corner.
  const dock = document.querySelector(".dock");
  if (dock) dock.append(root);
  else {
    root.classList.add("player-alone");
    (document.getElementById("stage") ?? document.body).append(root);
  }

  // ---- The track ---------------------------------------------------------

  let index = 0;
  let wanted = false; // the visitor asked for music and has not paused it
  const bands = new Map(); // track id -> its bands' bytes, or the promise of them
  let given = null; // what the scene holds: { scene, id }

  const track = () => tracks[index];

  function show() {
    const t = track();
    title.textContent = t.title;
    artist.textContent = t.artist ?? "";
    artist.hidden = !t.artist;
    seek.max = String(Math.max(1, Math.round(t.duration ?? 1)));
    progress(0);
    label();
    if ("mediaSession" in navigator && window.MediaMetadata) {
      navigator.mediaSession.metadata = new MediaMetadata({
        title: t.title,
        artist: t.artist ?? "",
        album: "The Oslo Tree",
        artwork: [{ src: new URL("media/poster-starlings-night.jpg", location.href).href, sizes: "1200x675", type: "image/jpeg" }],
      });
    }
  }

  function label() {
    const t = track();
    const what = t.artist ? `${t.title}, by ${t.artist}` : t.title;
    play.setAttribute("aria-label", wanted ? `Pause ${what}` : `Play ${what}`);
  }

  function setState(state) {
    if (root.dataset.state === state) return;
    root.dataset.state = state;
    root.classList.toggle("has-played", root.classList.contains("has-played") || state !== "idle");
  }

  function progress(seconds) {
    const length = Number(seek.max) || 1;
    const at = Math.min(length, Math.max(0, seconds));
    if (!seeking) seek.value = String(Math.round(at));
    seek.style.setProperty("--played", `${((seeking ? Number(seek.value) : at) / length) * 100}%`);
    seek.setAttribute("aria-valuetext", `${clock(seeking ? Number(seek.value) : at)} of ${clock(length)}`);
  }

  /** The track's bands, fetched once (again after a failure). */
  function fetchBands(t) {
    if (!t.bands) return Promise.resolve(null);
    if (!bands.has(t.id)) {
      const got = fetch(t.bands)
        .then((r) => {
          if (!r.ok) throw new Error(`${t.bands}: HTTP ${r.status}`);
          return r.arrayBuffer();
        })
        .then((b) => {
          const bytes = new Uint8Array(b);
          bands.set(t.id, bytes);
          return bytes;
        })
        .catch((e) => {
          bands.delete(t.id);
          console.warn("The Oslo Tree: the music's bands did not arrive; the tree will not move with it.", e);
          return null;
        });
      bands.set(t.id, got);
    }
    return Promise.resolve(bands.get(t.id));
  }

  function load(i) {
    index = (i + tracks.length) % tracks.length;
    audio.src = track().src;
    sync.locked = false;
    show();
  }

  async function start() {
    wanted = true;
    label();
    setState(audio.readyState >= 3 ? "playing" : "loading");
    fetchBands(track());
    try {
      await audio.play();
    } catch (e) {
      // A pause (or another track) before it began is not a failure.
      if (e?.name === "AbortError") return;
      wanted = false;
      label();
      setState(e?.name === "NotAllowedError" ? "paused" : "error");
      if (e?.name !== "NotAllowedError") console.warn("The Oslo Tree: the music did not play.", e);
    }
  }

  function stop() {
    wanted = false;
    label();
    audio.pause();
    setState("paused");
  }

  play.addEventListener("click", () => {
    if (wanted) stop();
    else {
      if (root.dataset.state === "error") audio.load();
      start();
    }
  });
  // The bands are small: have them by the time the first note sounds.
  for (const type of ["pointerenter", "focus", "touchstart"]) {
    play.addEventListener(type, () => fetchBands(track()), { once: true, passive: true });
  }

  mute.addEventListener("click", () => (audio.muted = !audio.muted));
  audio.addEventListener("volumechange", () => mute.setAttribute("aria-pressed", String(audio.muted)));
  next.addEventListener("click", () => {
    const playing = wanted;
    load(index + 1);
    if (playing) start();
  });

  // The line under the name is where the track is, and a way to move it.
  let seeking = false;
  seek.addEventListener("input", () => {
    seeking = true;
    progress(Number(seek.value));
  });
  seek.addEventListener("change", () => {
    const to = Number(seek.value);
    seeking = false;
    // Before the first play there is nothing to move yet: start from there.
    if (audio.readyState === 0) audio.addEventListener("loadedmetadata", () => (audio.currentTime = to), { once: true });
    else audio.currentTime = to;
    progress(to);
  });

  audio.addEventListener("playing", () => wanted && setState("playing"));
  audio.addEventListener("waiting", () => wanted && setState("loading"));
  audio.addEventListener("pause", () => {
    // Paused from outside the page (a headset's button, the lock screen).
    if (wanted && !audio.ended) {
      wanted = false;
      label();
      setState("paused");
    }
  });
  audio.addEventListener("play", () => {
    if (!wanted) {
      wanted = true;
      label();
      setState(audio.readyState >= 3 ? "playing" : "loading");
    }
  });
  audio.addEventListener("ended", () => {
    load(index + 1);
    start();
  });
  audio.addEventListener("error", () => {
    if (!audio.error || !wanted) return;
    wanted = false;
    label();
    setState("error");
    console.warn("The Oslo Tree: the music stopped arriving.", audio.error.message);
  });
  audio.addEventListener("durationchange", () => {
    if (Number.isFinite(audio.duration) && audio.duration > 0) seek.max = String(Math.round(audio.duration));
  });
  audio.addEventListener("timeupdate", () => !ticking && progress(audio.currentTime));

  if ("mediaSession" in navigator) {
    const handlers = {
      play: () => start(),
      pause: () => stop(),
      seekto: (d) => Number.isFinite(d.seekTime) && (audio.currentTime = d.seekTime),
      nexttrack: tracks.length > 1 ? () => next.click() : null,
    };
    for (const [action, handler] of Object.entries(handlers)) {
      try {
        navigator.mediaSession.setActionHandler(action, handler);
      } catch {
        // An action this browser does not know.
      }
    }
  }

  // ---- In time with the scene --------------------------------------------

  // The element's clock is read once a frame, and what it says jitters by a
  // few milliseconds (more in some browsers, which move it in steps). The
  // page's own clock is smooth: keep the difference between the two, eased,
  // and take the position from the page's clock. A jump (a seek, the next
  // track, a stall) is taken at once.
  const sync = { locked: false, offset: 0, seen: -1, seenAt: 0 };
  let ticking = false;
  let told = false; // the scene has been given a position and not yet a stop
  let last = null; // the position last given, for measuring

  function heard(now) {
    const sounding = wanted && !audio.paused && !audio.ended && !audio.seeking && audio.readyState >= 3;
    if (!sounding) {
      sync.locked = false;
      return null;
    }
    const at = audio.currentTime;
    if (!sync.locked) {
      sync.locked = true;
      sync.offset = at - now;
      sync.seen = at;
      sync.seenAt = now;
    } else {
      const error = at - (now + sync.offset);
      sync.offset += Math.abs(error) > 0.15 ? error : error * 0.1;
      if (at !== sync.seen) {
        sync.seen = at;
        sync.seenAt = now;
      }
    }
    // The clock has stood still: the sound has too.
    if (now - sync.seenAt > 0.3) return null;
    return now + sync.offset;
  }

  function tick() {
    const now = performance.now() / 1000;
    const position = heard(now);
    last = position;
    const scene = site();
    if (!scene) told = false;
    else {
      const t = track();
      const bytes = bands.get(t.id);
      if (bytes instanceof Uint8Array && (given?.scene !== scene || given.id !== t.id)) {
        try {
          scene.set_music(bytes);
          given = { scene, id: t.id, strength: given?.scene === scene ? given.strength : null };
        } catch (e) {
          bands.delete(t.id);
          t.bands = null;
          console.warn("The Oslo Tree: the music's bands could not be read.", e);
        }
      }
      try {
        const strength = calm.matches ? CALM_STRENGTH : 1;
        if (given?.scene === scene && given.strength !== strength) {
          scene.set_music_strength(strength);
          given.strength = strength;
        }
        if (position !== null && given?.scene === scene && given.id === t.id) {
          scene.music_at(position + leadS);
          told = true;
        } else if (told) {
          scene.music_stopped();
          told = false;
        }
      } catch {
        // The scene has gone (it failed and the page is starting afresh).
        given = null;
        told = false;
      }
    }
    if (!audio.seeking) progress(audio.currentTime);
    // Once more after a pause, so the scene hears that the music stopped.
    if (wanted || told) requestAnimationFrame(tick);
    else ticking = false;
  }
  const run = () => {
    if (!ticking) {
      ticking = true;
      requestAnimationFrame(tick);
    }
  };
  audio.addEventListener("play", run);
  audio.addEventListener("playing", run);

  load(0);
  root.classList.add("ready");
  return {
    root,
    audio,
    tracks,
    /** For measuring: the position last taken for the scene, the clock's own, and the lead. */
    position: () => ({ heard: last, clock: audio.currentTime, lead: leadS }),
  };
}
