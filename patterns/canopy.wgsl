//! name = "Canopy"
//! description = "Light that lives in a minority of a tree and moves through its limbs, branches, twigs and leaves, layered with noise: snakes, sap, starlight, a ribbon, rings, panes, a beam, embers"
//! inputs = ["audio", "structure", "palette"]
//! fits = ["tree"]
//! [[param]]
//! id = "mode"
//! label = "Mode"
//! type = "enum"
//! options = ["snakes", "sap", "starlight", "ribbon", "rings", "panes", "beam", "embers"]
//! default = "snakes"
//! [[param]]
//! id = "speed"
//! label = "Speed"
//! type = "float"
//! default = 1.0
//! min = 0.0
//! max = 10.0
//! unit = "×"
//! [[param]]
//! id = "density"
//! label = "How much of the tree"
//! type = "float"
//! default = 0.5
//! min = 0.0
//! max = 1.0
//! [[param]]
//! id = "size"
//! label = "Size"
//! type = "float"
//! default = 1.0
//! min = 0.2
//! max = 4.0
//! unit = "×"
//! [[param]]
//! id = "floor"
//! label = "Rest level"
//! type = "float"
//! default = 0.05
//! min = 0.0
//! max = 0.5
//! [[param]]
//! id = "grain"
//! label = "Fine noise"
//! type = "float"
//! default = 0.5
//! min = 0.0
//! max = 1.0
//! [[param]]
//! id = "notes"
//! label = "Notes"
//! type = "float"
//! default = 0.0
//! min = 0.0
//! max = 2.0
//! unit = "×"
//! [[param]]
//! id = "note_time"
//! label = "A note's time across the tree"
//! type = "float"
//! default = 0.9
//! min = 0.05
//! max = 1.5
//! unit = "s"
//! [[param]]
//! id = "note_reach"
//! label = "How far a note reaches"
//! type = "float"
//! default = 1.2
//! min = 0.1
//! max = 1.2
//! unit = "of the tree"
//! [[param]]
//! id = "shift"
//! label = "Moved on"
//! type = "float"
//! default = 0.0
//! min = 0.0
//! max = 1000000.0
//! [[param]]
//! id = "drift"
//! label = "Drifted on"
//! type = "float"
//! default = 0.0
//! min = 0.0
//! max = 1000000.0
//! unit = "s"
//! [[param]]
//! id = "palette"
//! label = "Palette"
//! type = "enum"
//! options = ["ember", "ocean", "aurora", "sunset", "ice", "spectrum", "mono", "show"]
//! default = "show"
//! [[param]]
//! id = "tint"
//! label = "Tint (mono)"
//! type = "color"
//! default = [1.0, 0.8, 0.5]
//! shown_when = { param = "palette", is = "mono" }
//! [[param]]
//! id = "brightness"
//! label = "Brightness"
//! type = "float"
//! default = 1.0
//! min = 0.0
//! max = 8.0
//! unit = "×"
// ==== shared library v2: begin ====
// Copied byte for byte into every pattern in patterns/ that has a `palette`
// parameter, because contract v0 has no imports. Edit it in one file, copy it
// to the others; `crates/patterns-tests` fails when the copies differ. An
// import mechanism replaces this block later.
//
// The `palette` enum of a pattern using it must list its options in this
// order: ["ember", "ocean", "aurora", "sunset", "ice", "spectrum", "mono"].
// v2 adds the show's middle and size, from the bounds in `Frame` (contract
// v1).

const PI: f32 = 3.14159265;
const TAU: f32 = 6.28318531;

// 32-bit integer mixer (the "lowbias32" constants from Chris Wellons' hash
// prospector, 2018). Integer arithmetic, so every GPU gets the same bits.
fn lib_hash(x: u32) -> u32 {
    var h = x;
    h = (h ^ (h >> 16u)) * 0x7feb352du;
    h = (h ^ (h >> 15u)) * 0x846ca68bu;
    return h ^ (h >> 16u);
}

// Hash of an integer lattice cell.
fn lib_hash3(c: vec3<i32>) -> u32 {
    return lib_hash(bitcast<u32>(c.x) ^ lib_hash(bitcast<u32>(c.y) ^ lib_hash(bitcast<u32>(c.z) + 0x9e3779b9u)));
}

// A hash as a float in 0..1.
fn lib_unit(h: u32) -> f32 {
    return f32(h >> 8u) / 16777216.0;
}

// OKLab to linear sRGB (Björn Ottosson, "A perceptual color space for image
// processing", 2020). Colours outside the sRGB gamut are clamped at zero.
fn lib_oklab_to_linear(c: vec3<f32>) -> vec3<f32> {
    let l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    let m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    let s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
    let l3 = l * l * l;
    let m3 = m * m * m;
    let s3 = s * s * s;
    return max(vec3<f32>(
        4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
        -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
        -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3,
    ), vec3<f32>(0.0));
}

// Five stops per palette, in OKLab (L, a, b), converted from the sRGB
// colours named in each comment.
const LIB_PALETTES: array<vec3<f32>, 30> = array<vec3<f32>, 30>(
    // ember: #8a1200 #d42c00 #ff6a00 #ffae2b #ffe7a8
    vec3<f32>(0.4062, 0.1323, 0.0816),
    vec3<f32>(0.5647, 0.1737, 0.1135),
    vec3<f32>(0.7009, 0.1428, 0.1417),
    vec3<f32>(0.8099, 0.0472, 0.1545),
    vec3<f32>(0.9329, 0.0006, 0.0841),
    // ocean: #0b2a8f #0066cc #00a6c7 #2fd6c3 #b8fff0
    vec3<f32>(0.3458, -0.0155, -0.1682),
    vec3<f32>(0.5220, -0.0434, -0.1717),
    vec3<f32>(0.6698, -0.0943, -0.0756),
    vec3<f32>(0.7910, -0.1320, -0.0073),
    vec3<f32>(0.9490, -0.0732, -0.0001),
    // aurora: #1fd67a #00b3a1 #2a6fd6 #7b3fe0 #d93fbf
    vec3<f32>(0.7712, -0.1695, 0.0830),
    vec3<f32>(0.6881, -0.1229, -0.0051),
    vec3<f32>(0.5558, -0.0337, -0.1696),
    vec3<f32>(0.5348, 0.0940, -0.2074),
    vec3<f32>(0.6348, 0.2103, -0.0952),
    // sunset: #4a0d80 #a0177a #f0425a #ff8a2a #ffd23f
    vec3<f32>(0.3431, 0.0869, -0.1454),
    vec3<f32>(0.4818, 0.1835, -0.0565),
    vec3<f32>(0.6402, 0.1988, 0.0645),
    vec3<f32>(0.7487, 0.1017, 0.1400),
    vec3<f32>(0.8789, -0.0027, 0.1617),
    // ice: #1a1f7a #2f5bd9 #5aa8ff #a8dcff #f2fbff
    vec3<f32>(0.3096, 0.0034, -0.1501),
    vec3<f32>(0.5190, -0.0165, -0.1987),
    vec3<f32>(0.7203, -0.0441, -0.1425),
    vec3<f32>(0.8703, -0.0383, -0.0615),
    vec3<f32>(0.9825, -0.0076, -0.0079),
    // spectrum: #ff2a2a #ffd400 #2adf5a #2a7fff #b03aff
    vec3<f32>(0.6427, 0.2153, 0.1124),
    vec3<f32>(0.8809, -0.0127, 0.1801),
    vec3<f32>(0.7912, -0.1878, 0.1225),
    vec3<f32>(0.6185, -0.0391, -0.2032),
    vec3<f32>(0.6145, 0.1634, -0.2165)
);

// Palette `id` at `x` (0..1, clamped), as linear RGB, interpolated in OKLab
// between its five stops. Palette 6 ("mono") ramps from a dark shade of
// `tint` through `tint` to a paler `tint`.
fn lib_palette(id: u32, x: f32, tint: vec3<f32>) -> vec3<f32> {
    let u = clamp(x, 0.0, 1.0);
    if (id >= 6u) {
        let pale = mix(tint, vec3<f32>(max(max(tint.r, tint.g), tint.b)), 0.45);
        return select(mix(tint * 0.4, tint, u / 0.6), mix(tint, pale, (u - 0.6) / 0.4), u > 0.6);
    }
    let k = u * 4.0;
    let i = min(u32(k), 3u);
    let base = id * 5u + i;
    return lib_oklab_to_linear(mix(LIB_PALETTES[base], LIB_PALETTES[base + 1u], k - f32(i)));
}

// Triangle wave 0 → 1 → 0 over two units: walks a palette back and forth
// with no jump, for colours that cycle.
fn lib_cycle(x: f32) -> f32 {
    return 1.0 - abs(2.0 * fract(0.5 * x) - 1.0);
}

// Running integral of a periodic band of width `duty` (in periods) centred
// on the integers.
fn lib_band_integral(x: f32, duty: f32) -> f32 {
    let y = x + 0.5 * duty;
    return floor(y) * duty + min(fract(y), duty);
}

// A periodic band, lit within duty/2 periods of each integer of `x`, averaged
// exactly over a window `w` periods wide (a box filter). Edges become ramps
// `w` wide; a band thinner than `w` dims instead of flickering; for w ≥ 1
// the result tends to `duty`, the band's mean.
fn lib_band(x: f32, duty: f32, w: f32) -> f32 {
    let d = clamp(duty, 0.0, 1.0);
    let h = 0.5 * max(w, 1e-3);
    let xf = fract(x);
    return (lib_band_integral(xf + h, d) - lib_band_integral(xf - h, d)) / (2.0 * h);
}

// A slab |d| < half, box-filtered over a window `s` wide (same units as d).
fn lib_slab(d: f32, half: f32, s: f32) -> f32 {
    let h = 0.5 * max(s, 1e-4);
    return max(min(d + half, h) - max(d - half, -h), 0.0) / (2.0 * h);
}
// The middle of the show's bounding box, metres. Patterns measure their
// `centre` parameter from here, so they are centred on any sculpture.
fn lib_show_middle(f: Frame) -> vec3<f32> {
    return 0.5 * (f.bounds_min + f.bounds_max);
}

// The show's size: its bounding box's largest side, metres (at least 1 mm).
fn lib_show_size(f: Frame) -> f32 {
    let e = f.bounds_max - f.bounds_min;
    return max(max(max(e.x, e.y), e.z), 1e-3);
}
// ==== shared library v2: end ====

// The pattern's palette at `x`: the show's (`palette = "show"`, the
// palette input) or one of the library's.
fn show_or_lib_palette(id: u32, x: f32, tint: vec3<f32>) -> vec3<f32> {
    if (id == PALETTE_SHOW) {
        return palette(x);
    }
    return lib_palette(id, x, tint);
}

// Written for this repository, after the old tree's own patterns
// (TreeSnakes, TreeEmanation, TreeStarlight, TreeSwarm, TreeClouds, the
// lighthouse): each mode lights whole leaves, a minority of them at a
// time, in a shape made of the tree (the order of a branch's leaves, the
// way out from the trunk, a twig as one pane, the side that faces a
// heading). The light gathers: in two pools that wander through the
// crown on opposite sides of the trunk, as the old swarm's point did,
// their edges and their insides shaped by noise at several octaves bent
// through itself, or in the mode's own shape (a ribbon, a beam). Inside
// it the mode's detail lives; the fine octaves give it life; the rest of
// the tree rests at `floor` in the palette's deep colour. A tree lit in
// one place leaves the rest of itself dim: light sprinkled evenly over
// it, however thinly, lights all of it.
//
// A host moves three parameters to play it: `shift` (the mode's own
// motion stepped on: leaves along a branch, turns of a beam), `drift`
// (seconds the noise and the pools have drifted on besides) and
// `density`. With `notes`, every note (read from the audio's history)
// sends a wave out from the trunk, across the tree in `note_time` seconds
// and as far as `note_reach` of it, which the mode answers in its own
// way, where its light already lives.

// A value in 0..1 that belongs to thing `id`, the `salt`-th of them.
fn c_rand(id: u32, salt: u32) -> f32 {
    return lib_unit(lib_hash(id * 0x9e3779b9u + salt * 0x85ebca6bu + 1u));
}

// Value noise, 0..1, smooth.
fn c_noise(q: vec3<f32>) -> f32 {
    let i = vec3<i32>(floor(q));
    let f = fract(q);
    let u = f * f * (3.0 - 2.0 * f);
    var v = 0.0;
    for (var c = 0u; c < 8u; c++) {
        let o = vec3<i32>(i32(c & 1u), i32((c >> 1u) & 1u), i32((c >> 2u) & 1u));
        let w = mix(1.0 - u, u, vec3<f32>(o));
        v += w.x * w.y * w.z * lib_unit(lib_hash3(i + o));
    }
    return v;
}

// Three octaves of it, each twice as fine and half as strong, each
// drifting its own way with `t`: 0..1, mostly 0.3..0.7.
fn c_fbm(q: vec3<f32>, t: f32) -> f32 {
    return 0.57 * c_noise(q + vec3<f32>(0.021 * t, 0.013 * t, -0.017 * t))
        + 0.29 * c_noise(q * 2.03 + vec3<f32>(17.1 - 0.04 * t, 3.7 + 0.03 * t, 9.2))
        + 0.14 * c_noise(q * 4.11 + vec3<f32>(5.3, 31.9 - 0.07 * t, 12.8 + 0.06 * t));
}

// The same bent through itself: the place it is read at is pushed about
// by two more readings of the noise, so its shapes curl and never look
// like a lattice.
fn c_cloud(q: vec3<f32>, t: f32) -> f32 {
    let bend = vec3<f32>(
        c_noise(q * 0.9 + vec3<f32>(0.0, 0.019 * t, 4.1)),
        c_noise(q * 0.9 + vec3<f32>(31.7, -0.015 * t, 0.0)),
        c_noise(q * 0.9 + vec3<f32>(0.017 * t, 12.3, 27.9)),
    );
    return c_fbm(q + 1.3 * (bend - 0.5), t);
}

// A note `ago` seconds ago, 0..1: how far the bands stood then over where
// they were 80 ms before (the low bands whole, the rest a little less),
// against how loud the passage is. 0 in silence.
fn c_note(ago: f32) -> f32 {
    let w = array<f32, 8>(1.0, 1.0, 0.8, 0.6, 0.6, 0.5, 0.6, 0.6);
    var flux = 0.0;
    for (var b = 0u; b < 8u; b++) {
        flux += w[b] * max(audio_history(ago, b) - audio_history(ago + 0.08, b), 0.0);
    }
    let low = 0.06 + 0.3 * audio_loudness();
    return smoothstep(low, low + 0.45, flux);
}

// Distance between two places on a loop of length n.
fn c_wrap(a: f32, b: f32, n: f32) -> f32 {
    let d = abs(a - b) - n * floor(abs(a - b) / n);
    return min(d, n - d);
}

// A front: 1 where `behind` (how far behind it a place is, 0 at the front
// and rising to 1 at the next one) is 0, falling away over `tail` and gone
// by halfway to the next, with a short soft nose just ahead of it.
fn c_front(behind: f32, tail: f32) -> f32 {
    let nose = smoothstep(1.0 - 0.25 * tail, 1.0, behind);
    return max(exp(-behind / tail) * (1.0 - smoothstep(0.3, 0.5, behind)), nose);
}

// A weight that picks `share` of the things numbered `id`, a new pick
// `rate` times a second, each thing at its own moment, fading in and out
// over its turn so nothing is cut off.
fn c_pick(id: u32, time: f32, rate: f32, share: f32) -> f32 {
    let at = time * rate + c_rand(id, 11u);
    let turn = bitcast<u32>(i32(floor(at)));
    let chosen = c_rand(id ^ (turn * 0x85ebca6bu), 12u) < share;
    let x = fract(at);
    return select(0.0, smoothstep(0.0, 0.25, x) * (1.0 - smoothstep(0.65, 1.0, x)), chosen);
}

// Where the first pool is at noise time `tn`: a point in the crown (0..1
// in the show's bounds, the upper two thirds of its height), on a slow
// path of its own that never repeats soon. The second pool keeps to the
// other side of the trunk from it, at its own height, so that from
// wherever the tree is seen some of its light is in view.
fn c_pool(k: i32, tn: f32) -> vec3<f32> {
    let a = 0.031 * tn;
    let b = 0.023 * tn + 1.3;
    let c = 0.017 * tn + 0.4;
    let first = vec3<f32>(
        0.34 * sin(TAU * a) + 0.1 * sin(TAU * 2.3 * b),
        0.62 + 0.2 * sin(TAU * b) + 0.08 * sin(TAU * 1.9 * c),
        0.34 * sin(TAU * c + 1.1) + 0.1 * sin(TAU * 2.1 * a),
    );
    if (k == 0) {
        return vec3<f32>(0.5 + first.x, first.y, 0.5 + first.z);
    }
    return vec3<f32>(0.5 - first.x, 1.2 - first.y + 0.06 * sin(TAU * 3.1 * c), 0.5 - first.z);
}

// How far inside the gathered light a leaf at `at` (0..1 in the bounds) is,
// 0 outside to 1 well inside: two pools, each wider with `density`, their
// edges broken by the noise `edge` (0..1).
fn c_gather(at: vec3<f32>, tn: f32, density: f32, edge: f32) -> f32 {
    let radius = mix(0.24, 0.5, clamp(density, 0.0, 1.0));
    var w = 0.0;
    for (var k = 0; k < 2; k++) {
        let d = length(at - c_pool(k, tn)) / radius + 0.9 * (edge - 0.5);
        w = max(w, 1.0 - smoothstep(0.55, 1.05, d));
    }
    return w;
}

fn pattern(s: Sample, p: Params, f: Frame) -> vec4<f32> {
    let t = f.time * p.speed;
    // The noise's own time: slow, and the host's drift besides.
    let tn = f.time * p.speed + p.drift;

    // The leaf, as the tree sees it: its centre from the foot of the
    // trunk (the middle of the show's floor), how far out, how high, round
    // which side.
    let size = max(f.bounds_max - f.bounds_min, vec3<f32>(1e-3));
    let foot = vec3<f32>(
        0.5 * (f.bounds_min.x + f.bounds_max.x),
        f.bounds_min.y,
        0.5 * (f.bounds_min.z + f.bounds_max.z),
    );
    let c = s.fixture_centre - foot;
    let far = clamp(length(c / size) / 1.2, 0.0, 1.0);
    let up = clamp(c.y / size.y, 0.0, 1.0);
    let out = clamp(length(c.xz) / (0.5 * max(size.x, size.z)), 0.0, 1.0);
    let az = atan2(c.z, c.x);
    // Metres to noise: a coarse cell is about a quarter of the tree.
    let q = c * (4.0 / max(max(size.x, size.y), size.z));
    // Where the light gathers, for the modes that gather it: the pools,
    // their edges and their insides shaped by the bent noise.
    let at = vec3<f32>(0.5, 0.0, 0.5) + c / size;
    let cloud = c_cloud(q * 1.15, tn);
    let gathered = c_gather(at, tn, p.density, cloud) * (0.55 + 0.9 * smoothstep(0.3, 0.7, cloud));

    // Its place in the tree's own order: along its twig, along its branch
    // (leaf by leaf, twig after twig), and its branch and twig as things
    // with a value of their own.
    let lc = max(s.level_count, vec4<u32>(1u));
    let li = select(s.level_index, vec4<u32>(0u), s.level_index == vec4<u32>(NO_FIXTURE));
    let per_twig = f32(lc.x);
    let twigs = f32(lc.y);
    let n = per_twig * twigs;
    let j = f32(li.y) * per_twig + f32(li.x);
    let u = (j + 0.5) / n;
    let branch = select(s.level.z, s.fixture, s.level.z == NO_FIXTURE);
    let twig = select(s.level.y, s.fixture, s.level.y == NO_FIXTURE);
    let br = c_rand(branch, 1u);

    // A note's wave, when the host asks for it: this leaf hears each note
    // `note_time` × its distance from the trunk later, and fainter towards
    // `note_reach`, where the wave dies.
    var note = 0.0;
    if (p.notes > 0.0) {
        note = p.notes * c_note(min(far * p.note_time, 1.5))
            * (1.0 - smoothstep(p.note_reach - 0.3, p.note_reach, far));
    }
    // The fine octaves: life inside the light, never where it is. One the
    // size of a twig, drifting, and one a leaf's own, slower.
    let fine = mix(
        1.0,
        (0.55 + 0.9 * c_noise(q * 5.3 + vec3<f32>(0.21 * tn, -0.17 * tn, 0.13 * tn)))
            * (0.8 + 0.4 * c_noise(vec3<f32>(61.0 * s.fixture_rand, 0.35 * tn, 7.0 * br))),
        p.grain,
    );
    // A leaf is lit as one thing, a little fuller along its middle.
    let leaf = 0.78 + 0.22 * sin(PI * clamp(s.fixture_npos.y, 0.0, 1.0));

    var v = 0.0; // the light, 0..1 and a little over
    var x = 0.5; // its place in the palette
    var rest = 0.1; // the palette's place the rest of the tree rests in
    switch p.mode {
        case MODE_SAP: {
            // Sap: fronts rise from the foot of the trunk and run out
            // along every branch to its tip, a long tail behind each, in
            // the limbs on two opposite sides of the tree at a time (the
            // sides the pools are on).
            let way = 0.7 * far + 0.3 * u * (0.5 + 0.5 * out);
            let ph = way * 1.5 - t / 10.0 - p.shift + 0.14 * (br - 0.5);
            let behind = fract(-ph);
            let pool = c_pool(0, tn) - vec3<f32>(0.5, 0.0, 0.5);
            let width = mix(0.35, 0.8, p.density);
            let heading = atan2(pool.z, pool.x);
            let side = min(c_wrap(az, heading, TAU), c_wrap(az, heading + PI, TAU)) / width + 0.9 * (cloud - 0.5);
            let flowing = 1.0 - smoothstep(0.55, 1.05, side);
            let front = c_front(behind, 0.2 * p.size);
            v = front * flowing;
            // Each note is a pulse of its own from the trunk, in the same
            // limbs.
            v = max(v, 0.9 * note * flowing);
            x = 0.3 + 0.45 * way + 0.3 * front;
            rest = 0.1;
        }
        case MODE_STARLIGHT: {
            // Starlight: leaves in fives along their twig come up and go
            // down on a raised cosine, each at its own slow pace, where
            // the light is gathered; the palette's blush (a fifth to two
            // fifths along it: pinks on Frost's) where a second field
            // lies on the outer leaves, its end (white) elsewhere. The
            // tree rests in the palette's start.
            let group = twig * 31u + u32(f32(li.x) / max(round(5.0 * p.size), 1.0));
            let period = mix(3.5, 9.0, c_rand(group, 2u));
            let when = t / period + c_rand(group, 3u);
            let turn = bitcast<u32>(i32(floor(when)));
            let lit = c_rand(group ^ (turn * 0x27d4eb2du), 4u) < 0.9 * gathered;
            let glow = pow(0.5 - 0.5 * cos(TAU * fract(when)), 1.5);
            v = select(0.0, mix(0.4, 1.0, c_rand(group ^ (turn * 0x165667b1u), 5u)) * glow, lit);
            // A note's wave glints on a few leaves as it passes, most
            // where the light already is.
            v = max(v, note * c_pick(s.fixture, f.time, 2.0, 0.16) * (0.08 + 0.92 * gathered));
            let blush = smoothstep(0.5, 0.72, c_fbm(q * 0.55 + vec3<f32>(9.1, 4.7, 2.3), -0.7 * tn))
                * smoothstep(0.45, 0.8, far);
            x = mix(1.0, 0.2 + 0.2 * c_rand(s.fixture, 7u), blush);
            rest = 0.0;
        }
        case MODE_RIBBON: {
            // A ribbon winds once up the tree round the trunk and turns
            // slowly, wandering with the bent noise; the palette lies
            // across its width. A second one, opposite, comes with
            // `density`.
            let wander = 0.2 * (cloud - 0.5);
            let ph = az / TAU + 0.85 * up - t / 46.0 - p.shift + wander;
            let width = 0.062 * p.size;
            let w1 = fract(ph) - 0.5;
            let w2 = fract(ph + 0.5) - 0.5;
            let second = smoothstep(0.5, 0.95, p.density);
            let b1 = exp(-(w1 * w1) / (width * width));
            let b2 = 0.7 * second * exp(-(w2 * w2) / (width * width));
            v = max(b1, b2) * mix(0.55, 1.0, smoothstep(0.05, 0.5, p.density));
            let w = select(w2, w1, b1 >= b2);
            x = clamp(0.5 + w / (2.6 * width), 0.0, 1.0);
            // A note brightens the ribbon where its wave is, on its way up.
            v *= 1.0 + 0.6 * note;
            rest = 0.88 + 0.1 * c_rand(s.fixture, 8u);
        }
        case MODE_RINGS: {
            // Rings leave the middle of the crown and roll out through it,
            // a crest with a tail inside it; only the arcs of them that
            // cross the gathered light show, other arcs of each ring.
            let middle = vec3<f32>(0.0, 0.56 * size.y, 0.0);
            let d = (c - middle) / (0.5 * size);
            let r = length(d);
            let ph = r * 1.25 - t / 13.0 - p.shift;
            let behind = fract(-ph);
            // Which ring: changing halfway between two crests, where
            // nothing of either shows.
            let ring = floor(ph + 0.5);
            let arcs = gathered * (0.55 + 0.45 * c_noise(2.2 * normalize(d + vec3<f32>(1e-4)) + vec3<f32>(0.021 * tn, 7.3 * ring, -0.017 * tn)));
            let crest = c_front(behind, 0.2 * p.size);
            v = crest * arcs;
            // Each note is a ripple of its own from the middle, in the
            // same part of the crown.
            v = max(v, 0.9 * note * gathered);
            x = 0.28 + 0.62 * max(crest * arcs, 0.8 * note * gathered);
            rest = 0.06;
        }
        case MODE_PANES: {
            // Panes: each twig is one pane of its own colour, lit for a
            // while and dark for longer, the panes of a branch taking
            // their turn in order from its base, where the light is
            // gathered; its leaves differ a little in shade.
            let period = 15.0 * (0.8 + 0.4 * c_rand(twig, 2u));
            let when = t / period - 0.45 * f32(li.y) / twigs + br + p.shift;
            let turn = bitcast<u32>(i32(floor(when)));
            let lit = c_rand(twig ^ (turn * 0x27d4eb2du), 4u) < 0.8 * gathered;
            let ph = fract(when);
            let glow = smoothstep(0.0, 0.22, ph) * (1.0 - smoothstep(0.55, 0.95, ph));
            v = select(0.0, glow, lit) * (1.0 + 0.8 * note);
            x = fract(c_rand(twig ^ (turn * 0x165667b1u), 5u) + 0.07 * (s.fixture_rand - 0.5) + 1.0);
            rest = 0.02;
        }
        case MODE_BEAM: {
            // Two beams turn round the trunk, opposite each other (one is
            // always on the side the tree is seen from), leaning a little
            // with height, soft at their edges, through a haze the noise
            // keeps moving; the second is the fainter, less so with
            // `density`.
            let heading = TAU * (t / 24.0 + p.shift);
            let a = az + 0.5 * (up - 0.5);
            let width = 0.33 * p.size;
            let d1 = c_wrap(a, heading, TAU) / width;
            let d2 = c_wrap(a, heading + PI, TAU) / width;
            let haze = mix(1.0, 0.4 + 1.2 * cloud, 0.5 + 0.5 * p.grain);
            let b1 = exp(-d1 * d1);
            let b2 = mix(0.4, 0.9, smoothstep(0.4, 0.95, p.density)) * exp(-d2 * d2);
            let core = max(b1, b2);
            v = core * haze * (0.7 + 0.3 * out);
            // A note runs out along the beam from the trunk.
            v *= 1.0 + 1.3 * note;
            x = 0.42 + 0.58 * core;
            rest = 0.22;
        }
        case MODE_EMBERS: {
            // Embers: each leaf kindles and dies down on its own, slowly,
            // in its own shade of the palette, where the light is
            // gathered; more of them as a gust crosses (a soft front on a
            // slowly turning heading).
            let period = mix(6.0, 14.0, c_rand(s.fixture, 2u));
            let when = t / period + c_rand(s.fixture, 3u);
            let turn = bitcast<u32>(i32(floor(when)));
            let wind = 0.3 + 0.07 * tn;
            let across = dot(q, vec3<f32>(cos(wind), 0.2, sin(wind))) * 0.42 - t / 16.0 - p.shift;
            let gust = pow(0.5 + 0.5 * cos(TAU * across), 3.0);
            let lit = c_rand(s.fixture ^ (turn * 0x27d4eb2du), 4u) < gathered * (0.45 + 0.55 * gust);
            let glow = pow(0.5 - 0.5 * cos(TAU * fract(when)), 1.3);
            v = select(0.0, mix(0.45, 1.0, c_rand(s.fixture ^ (turn * 0x165667b1u), 5u)) * glow, lit);
            // A note's wave fans a fifth of the leaves as it passes, most
            // where the embers are.
            v = max(v, select(0.0, 0.9 * note * (0.08 + 0.92 * gathered), c_rand(s.fixture, 6u) < 0.2));
            x = 0.08 + 0.8 * s.fixture_rand * (0.55 + 0.45 * v);
            rest = 0.04;
        }
        default: {
            // Snakes: snakes run through each branch's leaves in order,
            // leaf by leaf and twig after twig, and round again, two to a
            // branch: a bright head, a tail falling away behind it, its
            // length breathing. They show where the light is gathered.
            let lap = mix(9.0, 21.0, c_rand(branch, 2u));
            let head = fract(t / lap + br) * n + p.shift;
            let length_ = mix(12.0, 34.0, 0.5 - 0.5 * cos(TAU * (t / (1.7 * lap) + 2.0 * br))) * p.size;
            let behind = fract(2.0 * (head - j) / n) * 0.5 * n;
            let nose = smoothstep(0.5 * n - 3.0, 0.5 * n, behind);
            let body = max(pow(max(1.0 - behind / length_, 0.0), 1.4), nose);
            // A note wakes the heads where its wave is.
            v = body * gathered * (1.0 + 1.4 * note * exp(-behind / 2.5));
            // The palette runs from its end at the head (and at the nose
            // just ahead of it) to its start down the tail.
            x = max(1.0 - clamp(behind / (0.8 * length_), 0.0, 1.0), nose);
            rest = 0.06;
        }
    }
    // The rest of the tree: low, in the palette's deep colour, and not
    // flat: two octaves of the noise drifting through it, and a little
    // fuller towards each branch's tip.
    let ground = p.floor
        * (0.35 + 0.8 * c_noise(q * 1.3 + vec3<f32>(0.02 * tn, 0.0, 0.015 * tn))
            + 0.4 * c_noise(q * 3.1 + vec3<f32>(-0.03 * tn, 0.025 * tn, 0.0)))
        * (0.75 + 0.25 * u);
    let rgb = show_or_lib_palette(p.palette, clamp(rest, 0.0, 1.0), p.tint) * ground
        + show_or_lib_palette(p.palette, clamp(x, 0.0, 1.0), p.tint) * (v * fine);
    return vec4<f32>(rgb * (leaf * p.brightness), 1.0);
}
