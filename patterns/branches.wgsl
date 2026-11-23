//! name = "Branches"
//! description = "Light filling, running along or pulsing up a tree's branches; made for trees"
//! role = "texture"
//! inputs = ["audio", "structure", "palette"]
//! fits = ["tree"]
//! [[param]]
//! id = "mode"
//! label = "Mode"
//! type = "enum"
//! options = ["flow", "emanation", "snakes", "eq"]
//! default = "flow"
//! [[param]]
//! id = "speed"
//! label = "Speed"
//! type = "float"
//! default = 1.0
//! min = 0.05
//! max = 10.0
//! unit = "×"
//! [[param]]
//! id = "size"
//! label = "Size"
//! type = "float"
//! default = 1.0
//! min = 0.1
//! max = 5.0
//! unit = "×"
//! [[param]]
//! id = "softness"
//! label = "Edge softness"
//! type = "float"
//! default = 0.05
//! min = 0.0
//! max = 0.5
//! unit = "of a branch"
//! [[param]]
//! id = "palette"
//! label = "Palette"
//! type = "enum"
//! options = ["ember", "ocean", "aurora", "sunset", "ice", "spectrum", "mono", "show"]
//! default = "mono"
//! [[param]]
//! id = "tint"
//! label = "Tint (mono)"
//! type = "color"
//! default = [1.0, 1.0, 1.0]
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
// palette input) or one of the library's, exactly as before.
fn show_or_lib_palette(id: u32, x: f32, tint: vec3<f32>) -> vec3<f32> {
    if (id == PALETTE_SHOW) {
        return palette(x);
    }
    return lib_palette(id, x, tint);
}

// Distance between two places on a loop of length n.
fn wrap(a: f32, b: f32, n: f32) -> f32 {
    let d = abs(a - b) - n * floor(abs(a - b) / n);
    return min(d, n - d);
}

fn pattern(s: Sample, p: Params, f: Frame) -> vec4<f32> {
    let t = f.time * p.speed;
    let soft = max(p.softness, 1e-3);
    // Where along its branch this LED is, 0 at the base to 1 at the tip:
    // its twig's place along the branch, its leaf's place on the twig, its
    // place on the leaf. (On the trees the levels are leaf, twig, branch,
    // limb; on a show without them this is the fixture's own order.)
    let lc = max(s.level_count, vec4<u32>(1u));
    let li = select(s.level_index, vec4<u32>(0u), s.level_index == vec4<u32>(NO_FIXTURE));
    let in_leaf = (f32(s.fixture_index) + 0.5) / f32(max(s.fixture_count, 1u));
    let in_twig = (f32(li.x) + in_leaf) / f32(lc.x);
    let u = (f32(li.y) + in_twig) / f32(lc.y);
    // The branch, and its random value; its order in the tree (limb by
    // limb, branch by branch), as a fraction.
    let branch = select(s.level.z, s.fixture, s.level.z == NO_FIXTURE);
    let br = lib_unit(lib_hash(branch * 0x9e3779b9u + 5u));
    let order = (f32(li.w) + (f32(li.z) + 0.5) / f32(lc.z)) / f32(lc.w);
    var v = 0.0;
    switch p.mode {
        case MODE_EMANATION: {
            // A band runs out along every branch every 5 s, each branch at
            // its own phase; two twigs wide (of a branch's eight).
            let c = fract(t / 5.0 + br);
            let w = 0.25 * p.size;
            v = max(1.0 - abs(u - c) / w, 0.0);
        }
        case MODE_SNAKES: {
            // A blob runs round each branch's leaves every 7 s, its own
            // phase, its length breathing between 4 and 15 leaves of the
            // branch's (about 120).
            let n = f32(lc.x * lc.y);
            let x = u * n;
            let c = fract(t / 7.0 + br) * n;
            let len = mix(4.0, 15.0, 0.5 - 0.5 * cos(TAU * (t / 7.0 + 2.0 * br))) * p.size;
            v = max(1.0 - wrap(x, c, n) / len, 0.0);
        }
        case MODE_EQ: {
            // Each branch shows one band, the bands handed round the
            // branches at 5 branches a second; the branch is lit from its
            // base out to the band's level.
            let pos = order * 8.0 * f32(lc.w) + 5.0 * t;
            let b0 = u32(floor(pos)) % 8u;
            let b1 = (b0 + 1u) % 8u;
            let lvl = mix(audio_band(b0), audio_band(b1), fract(pos));
            v = 1.0 - smoothstep(lvl - soft, lvl + soft, u);
        }
        default: {
            // Flow: two cues walk the branches in order, a whole tree every
            // 50 s; a cued branch fills from its base over 1 s and empties
            // from its base over 1.5 s. On a show of fewer than ten
            // branches (one branch or twig shown alone) the cycle is 2.5 s
            // a branch, at least 3 s, so it flows again rather than
            // waiting 25 s between flows.
            let cycle = clamp(2.5 * f32(lc.z * lc.w), 3.0, 25.0);
            let tau = fract(t / cycle - order) * cycle;
            if (tau < 1.0) {
                v = 1.0 - smoothstep(tau - soft, tau + soft, u);
            } else if (tau < 2.5) {
                let e = (tau - 1.0) / 1.5;
                v = smoothstep(e - soft, e + soft, u);
            }
        }
    }
    let c = show_or_lib_palette(p.palette, 0.3 + 0.5 * u, p.tint);
    return vec4<f32>(c * (1.2 * v * p.brightness), 1.0);
}
