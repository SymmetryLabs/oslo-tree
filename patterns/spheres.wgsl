//! name = "Spheres"
//! description = "Shells expanding from one or several centres: ripples, standing waves or rings"
//! inputs = ["audio", "palette"]
//! [[param]]
//! id = "mode"
//! label = "Mode"
//! type = "enum"
//! options = ["ripple", "standing", "rings"]
//! default = "ripple"
//! [[param]]
//! id = "count"
//! label = "Centres"
//! type = "int"
//! default = 1
//! min = 1
//! max = 4
//! [[param]]
//! id = "centre"
//! label = "Centre (offset from the show's middle)"
//! type = "vec3"
//! default = [0.0, 0.0, 0.0]
//! min = -1000.0
//! max = 1000.0
//! unit = "m"
//! [[param]]
//! id = "spread"
//! label = "Spread"
//! type = "float"
//! default = 4.0
//! min = 0.0
//! max = 50.0
//! unit = "m"
//! [[param]]
//! id = "wavelength"
//! label = "Wavelength"
//! type = "float"
//! default = 3.0
//! min = 0.1
//! max = 50.0
//! unit = "m"
//! [[param]]
//! id = "thickness"
//! label = "Thickness"
//! type = "float"
//! default = 0.7
//! min = 0.02
//! max = 50.0
//! unit = "m"
//! [[param]]
//! id = "speed"
//! label = "Speed"
//! type = "float"
//! default = 1.5
//! min = -20.0
//! max = 20.0
//! unit = "m/s"
//! [[param]]
//! id = "phase"
//! label = "Moved on"
//! type = "float"
//! default = 0.0
//! min = 0.0
//! max = 5.0
//! unit = "shells"
//! [[param]]
//! id = "launch"
//! label = "Rings on notes"
//! type = "float"
//! default = 0.0
//! min = 0.0
//! max = 4.0
//! unit = "×"
//! [[param]]
//! id = "launch_speed"
//! label = "Their speed"
//! type = "float"
//! default = 6.0
//! min = 0.5
//! max = 40.0
//! unit = "m/s"
//! [[param]]
//! id = "reach"
//! label = "Reach"
//! type = "float"
//! default = 20.0
//! min = 0.5
//! max = 1000.0
//! unit = "m"
//! [[param]]
//! id = "softness"
//! label = "Edge softness"
//! type = "float"
//! default = 0.15
//! min = 0.0
//! max = 5.0
//! unit = "m"
//! [[param]]
//! id = "palette"
//! label = "Palette"
//! type = "enum"
//! options = ["ember", "ocean", "aurora", "sunset", "ice", "spectrum", "mono", "show"]
//! default = "show"
//! default_before = { format = 2, value = "ocean" }
//! [[param]]
//! id = "tint"
//! label = "Tint (mono)"
//! type = "color"
//! default = [0.2, 0.6, 1.0]
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

// Centre `k` of `n` around `c`: at `c` when alone, otherwise all spaced
// round a horizontal circle of radius `spread`, which turns once a minute
// while each centre bobs gently up and down.
fn centre_of(k: i32, n: i32, c: vec3<f32>, p: Params, t: f32, shrink: f32) -> vec3<f32> {
    if (n == 1) {
        return c;
    }
    let a = TAU * (f32(k) / f32(n) + t / 60.0);
    let bob = 0.25 * sin(TAU * t / 23.0 + 2.0 * f32(k));
    return c + shrink * p.spread * vec3<f32>(cos(a), bob, sin(a));
}

// A note `ago` seconds ago, 0..1: how far the bands stood then over where
// they were 80 ms before (the low bands whole, the rest a little less),
// which every note raises for a moment: a plucked string, a drum, a
// cymbal. 0 in silence. The Oslo tree's website counts its notes the same
// way (`apps/oslo-site/src/motion.rs`).
fn note_at(ago: f32) -> f32 {
    let w = array<f32, 8>(1.0, 1.0, 0.8, 0.6, 0.6, 0.5, 0.6, 0.6);
    var flux = 0.0;
    for (var b = 0u; b < 8u; b++) {
        flux += w[b] * max(audio_history(ago, b) - audio_history(ago + 0.08, b), 0.0);
    }
    // Against how loud the passage is, so a full one's own stir is not a
    // note.
    let floor = 0.06 + 0.3 * audio_loudness();
    return smoothstep(floor, floor + 0.45, flux);
}

// The lengths in metres (centre, spread, wavelength, thickness, speed,
// reach, softness) are for a show 10 m or more across (a tree); a smaller
// show (the cubes, a branch, a twig) is drawn as if it were scaled up to 10
// m, so shells cross it one after another rather than lighting all of it at
// once.
const DESIGN_SIZE: f32 = 10.0;

// The ripples over the shells' light `rgb`: with `launch`, a ripple leaves
// each centre on every note and rolls out at `launch_speed`: a point r
// away sees the note r / speed later, read from the audio's history
// (which holds 2 s, so a ripple fades out as it nears 1.5 s old). The
// light gathers on its crest and, a moment behind it, sinks into a trough
// of the palette's deep colour.
fn rippled(rgb: vec3<f32>, s: Sample, p: Params, f: Frame) -> vec3<f32> {
    let shrink = min(lib_show_size(f) / DESIGN_SIZE, 1.0);
    let middle = lib_show_middle(f) + shrink * p.centre;
    var ripple = 0.0;
    var dip = 0.0;
    for (var k = 0; k < p.count; k++) {
        let d = (s.pos - centre_of(k, p.count, middle, p, f.time, shrink)) / shrink;
        let r = select(length(d), length(d.xz), p.mode == MODE_RINGS);
        let ago = r / p.launch_speed;
        let live = p.launch * (1.0 - smoothstep(1.1, 1.5, ago));
        ripple = max(ripple, live * note_at(min(ago, 1.5)));
        dip = max(dip, live * note_at(clamp(ago - 0.09, 0.0, 1.5)));
    }
    let deep = show_or_lib_palette(p.palette, 0.12, p.tint);
    return mix(rgb * (1.0 + 0.35 * ripple), deep * 1.1, 0.85 * min(dip, 1.0));
}

// The pattern with its shells moved on by `phase` of themselves and, with
// `launch`, the ripples over them: the pattern's own sum with the shells
// further out. Kept apart from it so that without either the pattern is
// computed as it always was.
fn moved(s: Sample, p: Params, f: Frame) -> vec4<f32> {
    let t = f.time;
    let shrink = min(lib_show_size(f) / DESIGN_SIZE, 1.0);
    let duty = p.thickness / p.wavelength;
    let w = p.softness / p.wavelength;
    let middle = lib_show_middle(f) + shrink * p.centre;
    var rgb = vec3<f32>(0.0);
    for (var k = 0; k < p.count; k++) {
        let d = (s.pos - centre_of(k, p.count, middle, p, t, shrink)) / shrink;
        let r = select(length(d), length(d.xz), p.mode == MODE_RINGS);
        let outward = (r - p.speed * t) / p.wavelength - p.phase;
        var cover = lib_band(outward, duty, w);
        if (p.mode == MODE_STANDING) {
            cover += lib_band((r + p.speed * t) / p.wavelength + p.phase, duty, w);
        }
        let fade = 1.0 / (1.0 + (r / p.reach) * (r / p.reach));
        let c = lib_cycle(0.4 * outward + 0.6 * f32(k));
        rgb += show_or_lib_palette(p.palette, c, p.tint) * (1.6 * cover * fade);
    }
    if (p.launch > 0.0) {
        rgb = rippled(rgb, s, p, f);
    }
    return vec4<f32>(rgb * p.brightness, 1.0);
}

fn pattern(s: Sample, p: Params, f: Frame) -> vec4<f32> {
    // `phase` moves the shells on by that many of themselves (a host steps
    // it to push them out on a beat), and `launch` sends ripples over
    // them: their own path.
    if (p.phase != 0.0 || p.launch > 0.0) {
        return moved(s, p, f);
    }
    let t = f.time;
    let shrink = min(lib_show_size(f) / DESIGN_SIZE, 1.0);
    let duty = p.thickness / p.wavelength;
    let w = p.softness / p.wavelength;
    let middle = lib_show_middle(f) + shrink * p.centre;
    var rgb = vec3<f32>(0.0);
    for (var k = 0; k < p.count; k++) {
        let d = (s.pos - centre_of(k, p.count, middle, p, t, shrink)) / shrink;
        // Rings measure the distance from a vertical axis; the others from
        // a point.
        let r = select(length(d), length(d.xz), p.mode == MODE_RINGS);
        let outward = (r - p.speed * t) / p.wavelength;
        var cover = lib_band(outward, duty, w);
        if (p.mode == MODE_STANDING) {
            // The same shells running inward as well: where they cross the
            // light doubles, at the standing wave's crests.
            cover += lib_band((r + p.speed * t) / p.wavelength, duty, w);
        }
        let fade = 1.0 / (1.0 + (r / p.reach) * (r / p.reach));
        let c = lib_cycle(0.4 * outward + 0.6 * f32(k));
        rgb += show_or_lib_palette(p.palette, c, p.tint) * (1.6 * cover * fade);
    }
    return vec4<f32>(rgb * p.brightness, 1.0);
}
