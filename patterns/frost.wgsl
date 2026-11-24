//! name = "Frost"
//! description = "White leaves, the palette's first colour blushing in drifting patches on the outer leaves of the canopy"
//! inputs = ["palette"]
//! fits = ["tree"]
//! [[param]]
//! id = "blush"
//! label = "Blush"
//! type = "float"
//! default = 0.6
//! min = 0.0
//! max = 1.0
//! [[param]]
//! id = "depth"
//! label = "Depth"
//! type = "float"
//! default = 0.45
//! min = 0.0
//! max = 1.0
//! unit = "of the canopy"
//! [[param]]
//! id = "speed"
//! label = "Speed"
//! type = "float"
//! default = 1.0
//! min = 0.0
//! max = 10.0
//! unit = "×"
//! [[param]]
//! id = "drift"
//! label = "Drifted on"
//! type = "float"
//! default = 0.0
//! min = 0.0
//! max = 1000000.0
//! unit = "s"

// The canopy taken as an ellipsoid over the show's bounds (centred a little
// above half height, where a tree's crown is widest). A point's place in it
// runs from 0 at the centre to 1 at the outer leaves; the blush lies on the
// outer `depth` of that, in slowly drifting patches of value noise, its
// colour from the start of the palette (pinks on Frost's palette), and the
// rest is the palette's end (white). Written for this repository.

fn frost_hash(c: vec3<i32>) -> f32 {
    var h = u32(c.x) * 73856093u ^ u32(c.y) * 19349663u ^ u32(c.z) * 83492791u;
    h = (h ^ (h >> 13u)) * 1274126177u;
    h = h ^ (h >> 16u);
    return f32(h & 0xffffffu) / 16777215.0;
}

fn frost_noise(q: vec3<f32>) -> f32 {
    let i = vec3<i32>(floor(q));
    let f = fract(q);
    let u = f * f * (3.0 - 2.0 * f);
    var v = 0.0;
    for (var c = 0u; c < 8u; c++) {
        let o = vec3<i32>(i32(c & 1u), i32((c >> 1u) & 1u), i32((c >> 2u) & 1u));
        let w = mix(1.0 - u, u, vec3<f32>(o));
        v += w.x * w.y * w.z * frost_hash(i + o);
    }
    return v;
}

// The pattern with its patches at drift time `t`.
fn frosted(s: Sample, p: Params, f: Frame, t: f32) -> vec4<f32> {
    let lo = f.bounds_min;
    let hi = f.bounds_max;
    let c = vec3<f32>(0.5 * (lo.x + hi.x), lo.y + 0.55 * (hi.y - lo.y), 0.5 * (lo.z + hi.z));
    let half = max(0.5 * (hi - lo), vec3<f32>(1e-3));
    let e = length((s.pos - c) / half);
    let shell = smoothstep(1.0 - p.depth - 0.1, 1.0, e);
    let scale = 2.2 / max(max(half.x, half.y), half.z);
    let n = 0.65 * frost_noise(s.pos * scale + vec3<f32>(t, 0.6 * t, -0.8 * t))
        + 0.35 * frost_noise(s.pos * scale * 3.1 - vec3<f32>(1.3 * t, 0.0, t));
    let amount = clamp(shell * smoothstep(0.46, 0.74, n + 0.15 * shell) * 1.7 * p.blush, 0.0, 1.0);
    let blush = palette(0.02 + 0.12 * (1.0 - n));
    let white = palette(1.0);
    return vec4<f32>(mix(white, blush, amount), 1.0);
}

fn pattern(s: Sample, p: Params, f: Frame) -> vec4<f32> {
    let t = f.time * 0.05 * p.speed;
    // `drift` is seconds the patches have drifted on besides (a host moves
    // it to carry them along with a sound). Its own path, so that without
    // it the pattern is computed exactly as it always was, to the last
    // bit.
    if (p.drift != 0.0) {
        return frosted(s, p, f, t + 0.05 * p.drift);
    }
    return frosted(s, p, f, t);
}
