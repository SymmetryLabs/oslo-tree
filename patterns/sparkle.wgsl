//! name = "Sparkle"
//! description = "Single LEDs flashing and fading at random, a starfield, or a slow twinkle"
//! inputs = ["palette"]
//! [[param]]
//! id = "mode"
//! label = "Mode"
//! type = "enum"
//! options = ["sparkle", "starfield", "twinkle"]
//! default = "sparkle"
//! [[param]]
//! id = "density"
//! label = "Density"
//! type = "float"
//! default = 0.2
//! min = 0.001
//! max = 1.0
//! unit = "of the LEDs lit"
//! [[param]]
//! id = "attack"
//! label = "Attack"
//! type = "float"
//! default = 0.5
//! min = 0.01
//! max = 10.0
//! unit = "s"
//! [[param]]
//! id = "decay"
//! label = "Decay"
//! type = "float"
//! default = 0.6
//! min = 0.01
//! max = 10.0
//! unit = "s"
//! [[param]]
//! id = "variety"
//! label = "Colour variety"
//! type = "float"
//! default = 0.5
//! min = 0.0
//! max = 1.0
//! [[param]]
//! id = "pale"
//! label = "Paleness"
//! type = "float"
//! default = 0.4
//! min = 0.0
//! max = 1.0
//! [[param]]
//! id = "palette"
//! label = "Palette"
//! type = "enum"
//! options = ["ember", "ocean", "aurora", "sunset", "ice", "spectrum", "mono", "show"]
//! default = "show"
//! default_before = { format = 2, value = "ice" }
//! [[param]]
//! id = "tint"
//! label = "Tint (mono)"
//! type = "color"
//! default = [0.6, 0.8, 1.0]
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

// One flash: a linear rise over `attack` to 1.5 and a linear fall over
// `decay`, as the old sparks did, zero outside.
fn flash(age: f32, attack: f32, decay: f32) -> f32 {
    if (age <= 0.0 || age >= attack + decay) {
        return 0.0;
    }
    return 1.5 * select(1.0 - (age - attack) / decay, age / attack, age < attack);
}

fn pattern(s: Sample, p: Params, f: Frame) -> vec4<f32> {
    let t = f.time;
    let id = lib_hash(s.index * 0x2c1b3c6du + 0x5bd1e995u);
    var v: f32;
    var hue_hash: u32;
    if (p.mode == MODE_TWINKLE) {
        // Every LED breathes at its own rate and phase; the sharper the
        // peak, the fewer are lit at once (`density` sets the exponent).
        let life = p.attack + p.decay;
        let rate = (0.15 + 0.45 * lib_unit(lib_hash(id + 1u))) / life;
        let w = max(sin(TAU * (rate * t + lib_unit(id))), 0.0);
        let k = clamp(1.0 / (TAU * p.density * p.density), 1.0, 200.0);
        v = 1.5 * pow(w, k);
        hue_hash = id;
    } else {
        // Time is cut into slots, offset per LED; a slot holds one flash
        // with probability q, at a hashed start that keeps it inside the
        // slot. Slot length life·q/density lights `density` of the LEDs on
        // average. Starfield flashes every LED once a slot.
        let life = p.attack + p.decay;
        let q = select(clamp(max(0.5, p.density), 0.5, 1.0), 1.0, p.mode == MODE_STARFIELD);
        let slot = life * q / p.density;
        let x = t / slot + lib_unit(id);
        let n = floor(x);
        let h = lib_hash(id ^ (bitcast<u32>(i32(n)) * 0x9e3779b9u));
        let fire = lib_unit(h) < q;
        let start = lib_unit(lib_hash(h + 7u)) * max(slot - life, 0.0);
        let age = (x - n) * slot - start;
        v = select(0.0, flash(age, p.attack, p.decay), fire);
        hue_hash = lib_hash(h + 13u);
    }
    let pos = 0.5 + p.variety * (lib_unit(hue_hash) - 0.5);
    let base = show_or_lib_palette(p.palette, pos, p.tint);
    let white = vec3<f32>(dot(base, vec3<f32>(0.2126, 0.7152, 0.0722)));
    let rgb = mix(base, white, p.pale) * v;
    return vec4<f32>(rgb * p.brightness, 1.0);
}
