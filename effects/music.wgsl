//! name = "Music"
//! description = "Moves the light under it with the sound: each accent a swell travelling out from the foot of the show, notes lighting twigs, glints on the highs, more the fuller the music. Silence leaves the light as it is"
//! inputs = ["audio", "structure"]
//! [[param]]
//! id = "pulse"
//! label = "Bass swell"
//! type = "float"
//! default = 1.0
//! min = 0.0
//! max = 2.0
//! unit = "×"
//! [[param]]
//! id = "travel"
//! label = "Swell's travel"
//! type = "float"
//! default = 0.16
//! min = 0.0
//! max = 1.0
//! unit = "s to cross the show"
//! [[param]]
//! id = "notes"
//! label = "Notes"
//! type = "float"
//! default = 0.7
//! min = 0.0
//! max = 2.0
//! unit = "×"
//! [[param]]
//! id = "sparkle"
//! label = "Sparkle"
//! type = "float"
//! default = 0.6
//! min = 0.0
//! max = 2.0
//! unit = "×"

// Every term below is 0 when the audio is silent, and the light is then
// returned bit for bit as it came: a show with this effect on its master
// looks the same as one without until something plays.

// 32-bit integer mixer (the "lowbias32" constants from Chris Wellons' hash
// prospector), as in the pattern library.
fn music_hash(x: u32) -> u32 {
    var h = x;
    h = h ^ (h >> 16u);
    h = h * 0x7feb352du;
    h = h ^ (h >> 15u);
    h = h * 0x846ca68bu;
    h = h ^ (h >> 16u);
    return h;
}

fn music_unit(h: u32) -> f32 {
    return f32(h >> 8u) / 16777216.0;
}

// How far band `b` stood, `ago` seconds ago, above the most it had been
// over the 0.45 s before (at three moments in it): up at once with a
// note, and back down within two tenths of a second. A note that only
// repeats the one before it, closer than that, does not count again, so
// a fast passage does not flicker: the light answers what is new, at most
// about twice a second.
fn music_fresh(b: u32, ago: f32) -> f32 {
    let before = max(
        max(audio_history(ago + 0.19, b), audio_history(ago + 0.31, b)),
        audio_history(ago + 0.43, b),
    );
    return max(audio_history(ago, b) - before, 0.0);
}

// A weight that picks `share` of the things numbered `id`, a new pick
// `rate` times a second, each thing at its own moment, fading in and out
// over its turn so nothing is cut off.
fn music_pick(id: u32, time: f32, rate: f32, share: f32) -> f32 {
    let at = time * rate + music_unit(music_hash(id + 0x9e3779b9u));
    let turn = bitcast<u32>(i32(floor(at)));
    let chosen = music_unit(music_hash(id ^ (turn * 0x85ebca6bu))) < share;
    let x = fract(at);
    return select(0.0, smoothstep(0.0, 0.2, x) * (1.0 - smoothstep(0.7, 1.0, x)), chosen);
}

fn effect(c: vec4<f32>, s: Sample, p: Params, f: Frame) -> vec4<f32> {
    // How loud the passage is, from hushed (0) to full (1): the level over
    // the last few seconds. A hushed passage moves the light by half
    // of what a full one does, so the light grows with the music.
    let full = smoothstep(0.1, 0.4, audio_loudness());
    let reach = mix(0.5, 1.0, full);

    // An accent: what is new in the low bands (a kick, a plucked bass, a
    // drum), and less of what is new in the middle (a chord from the whole
    // orchestra counts as one; the highs have their own answer below). It
    // is read a moment back, further back the further the point is from
    // the foot of the show (the middle of its floor), so each accent is a
    // swell travelling up and out.
    let size = max(f.bounds_max - f.bounds_min, vec3<f32>(1e-3));
    let foot = vec3<f32>(
        0.5 * (f.bounds_min.x + f.bounds_max.x),
        f.bounds_min.y,
        0.5 * (f.bounds_min.z + f.bounds_max.z),
    );
    let far = clamp(length((s.pos - foot) / size) / 1.2, 0.0, 1.0);
    let ago = far * p.travel;
    let accent = music_fresh(0u, ago) + music_fresh(1u, ago) + 0.6 * music_fresh(2u, ago)
        + 0.3 * (music_fresh(3u, ago) + music_fresh(4u, ago) + music_fresh(5u, ago));
    let swell = smoothstep(0.05, 0.45, accent) * reach;

    // Notes: what is new in the middle bands lights a third of the twigs,
    // others the next time, each a breath after the note (never the same
    // breath).
    let twig = select(s.fixture, s.group, s.group != NO_FIXTURE);
    let late = 0.07 * music_unit(music_hash(twig * 0x2c1b3c6du + 17u));
    let mid = max(max(music_fresh(3u, late), music_fresh(4u, late)), music_fresh(5u, late));
    let note = smoothstep(0.05, 0.35, mid) * reach * music_pick(twig, f.time, 1.6, 0.34);

    // The highs: a hat or a cymbal's stroke glints on a few leaves, other
    // leaves each time; and while the highs ring on (a cymbal, the brass
    // at full cry) the leaves keep glittering, more of them the fuller
    // the passage.
    let stroke = smoothstep(0.1, 0.5, max(audio_onset(6u), audio_onset(7u)));
    let ringing = 0.55 * smoothstep(0.3, 0.75, max(audio_band(6u), audio_band(7u)));
    let glint = max(stroke, ringing) * music_pick(s.fixture + 0x51ed270bu, f.time, 5.0, 0.07 + 0.15 * full);

    // The swell and the notes multiply the light, up to about two and a
    // half times and no further, however much happens at once.
    let lift = (1.0 + p.pulse * swell) * (1.0 + p.notes * note) - 1.0;
    let gain = 1.0 + 1.6 * tanh(lift / 1.6);
    let luma = dot(c.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    // A glint is the leaf's own colour brighter and paler, and a little
    // light of its own where the leaf is dark.
    let white = p.sparkle * glint * (1.2 * c.rgb + vec3<f32>(0.6 * luma + 0.12));
    return vec4<f32>(c.rgb * gain + white, c.a);
}
