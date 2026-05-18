// Variety shader primitives (spec 24 layers).
//
// Included by terrain_clipmap.gdshader. Pure functions only — caller
// supplies textures + uniforms.
//
// Layer 1 sampling path (Phase 6 visual A/B 2026-05-17):
//   The original `w5_variety_sample_3tap` blended 3 random siblings per
//   fragment via overlapping world-noise — visible as permanent 30%-grey
//   mush at ~10m wavelength (the "blob overlay" user kept seeing).
//   Replaced by `w5_variety_sample_combined` which combines:
//     (a) W4-style REGION-based variant selection: deterministic hash
//         of floor(world_xz / region_size_m) picks ONE sibling per
//         region, 4-corner bilinear crossfade only within edge_blend_m
//         of region borders. Each region reads as "field of variant X",
//         not "blur of variants A+B+C".
//     (b) Heitz-Neyret 2018 per-fragment tiling within the chosen
//         variant: triangle-grid 3-tap with per-tap rotation/offset
//         + inverse-histogram-transform LUT (T_inv) — kills visible
//         tile repeat within a single variant without losing contrast.
//   Old `w5_variety_sample_3tap` kept below for back-compat with tests
//   + legacy single-slot path; new scenes should use the combined sampler.

// Hash-based pseudo-random in [0,1) for a world XZ coord.
float w5_variety_hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Smooth world-noise scalar (low-frequency macro modulator).
// Smoother than raw hash; used for sibling-weight modulation in
// stochastic UV sampling (Heitz-Neyret 2018 simplification).
float w5_world_noise(vec2 p, float freq) {
    vec2 pf = p * freq;
    vec2 i = floor(pf);
    vec2 f = fract(pf);
    vec2 w = f * f * (3.0 - 2.0 * f);
    float a = w5_variety_hash(i + vec2(0.0, 0.0));
    float b = w5_variety_hash(i + vec2(1.0, 0.0));
    float c = w5_variety_hash(i + vec2(0.0, 1.0));
    float d = w5_variety_hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

// Convert world XZ → macro albedo UV given a vec4(min_x, min_z, max_x, max_z).
vec2 w5_macro_uv(vec2 world_xz, vec4 aabb) {
    vec2 span = aabb.zw - aabb.xy;
    if (span.x <= 0.0 || span.y <= 0.0) return vec2(0.0);
    vec2 uv = (world_xz - aabb.xy) / span;
    return clamp(uv, vec2(0.0), vec2(1.0));
}

// 3-tap stochastic UV blend over a sibling Texture2DArray.
//
// Phase 5.5 Layer 1 (spec 24). Simplified Heitz-Neyret 2018:
// sample 3 offset UVs from 3 different layers (selected by world-noise),
// blend with weights derived from a second noise octave. Breaks the
// "same tile repeats" artifact across world XZ even though each sibling
// is itself tileable.
//
// Caller responsibilities:
// - array: sibling Texture2DArray (all slot variants concatenated)
// - tile_uv: world XZ scaled to sibling tile-frequency (e.g.
//   world_xz / sibling_tile_m); tiling is handled here via fract().
// - world_xz: raw world XZ; drives layer selection + offset hashing
//   independent of the per-tile UV.
// - start: first layer index for the active slot inside the array
// - count: number of sibling layers the active slot owns (1..8)
// - blend_freq: world-XZ frequency for layer-selection noise (~0.1
//   gives ~10m blend cells; lower = larger patches)
//
// Returns vec4 (rgb + a); caller treats rgb as albedo. For now siblings
// are albedo-only; normal-map siblings can ship later via a second call
// against a normal-array (same start/count window).
vec4 w5_variety_sample_3tap(sampler2DArray array, vec2 tile_uv,
        vec2 world_xz, int start, int count, float blend_freq) {
    if (count <= 0) return vec4(0.0);
    if (count == 1) {
        // Single sibling: no blending possible, just sample.
        return texture(array, vec3(fract(tile_uv), float(start)));
    }
    // Per-fragment selection noise: 3 octaves so the 3 chosen layers
    // bias differently across world XZ.
    float n0 = w5_world_noise(world_xz, blend_freq);
    float n1 = w5_world_noise(world_xz + vec2(37.3, 91.7), blend_freq * 1.7);
    float n2 = w5_world_noise(world_xz + vec2(-71.5, 23.1), blend_freq * 2.3);
    float fcount = float(count);
    // Quantize each noise to a layer index in [0, count). The +0.001
    // bias keeps boundaries off integer-grid hash artifacts.
    int l0 = clamp(int(floor(n0 * fcount + 0.001)), 0, count - 1);
    int l1 = clamp(int(floor(n1 * fcount + 0.001)), 0, count - 1);
    int l2 = clamp(int(floor(n2 * fcount + 0.001)), 0, count - 1);
    // 3-tap weights — softmax-ish via squared values; small offset
    // avoids zero weight when noise dips low.
    float w0 = n0 * n0 + 0.05;
    float w1 = n1 * n1 + 0.05;
    float w2 = n2 * n2 + 0.05;
    float wsum = w0 + w1 + w2;
    w0 /= wsum; w1 /= wsum; w2 /= wsum;
    // Offset UVs per tap break edge-aligned tile boundaries; offsets
    // are constants chosen to be incommensurate with unit tile size.
    vec2 uv0 = fract(tile_uv);
    vec2 uv1 = fract(tile_uv + vec2(0.3725, 0.6191));
    vec2 uv2 = fract(tile_uv + vec2(0.8147, 0.2058));
    vec4 c0 = texture(array, vec3(uv0, float(start + l0)));
    vec4 c1 = texture(array, vec3(uv1, float(start + l1)));
    vec4 c2 = texture(array, vec3(uv2, float(start + l2)));
    return c0 * w0 + c1 * w1 + c2 * w2;
}

// 2-tap detail-overlay blend over a per-biome detail Texture2DArray.
//
// Phase 5.5 Layer 2 (spec 24). Pick 2 detail layers based on world-XZ
// noise, blend their RGB weighted by their alpha channels (alpha is
// the authored coverage mask — high alpha = dense overlay). Returns
// vec4 (rgb is blended overlay color, a is combined coverage 0..1).
//
// Caller responsibilities:
// - array: per-biome detail Texture2DArray
// - tile_uv: world XZ scaled to detail tile-frequency (e.g.
//   world_xz / detail_tile_m)
// - world_xz: raw world XZ; selection-noise lives here
// - count: number of detail layers in the array (1..N)
// - blend_freq: world-XZ frequency for layer-selection noise
//
// Typical usage: caller multiplies/over-blends the returned rgb into
// the base albedo, weighted by detail_strength * a.
vec4 w5_detail_blend(sampler2DArray array, vec2 tile_uv, vec2 world_xz,
        int count, float blend_freq) {
    if (count <= 0) return vec4(0.0);
    if (count == 1) {
        vec4 only = texture(array, vec3(fract(tile_uv), 0.0));
        return only;
    }
    float n0 = w5_world_noise(world_xz, blend_freq);
    float n1 = w5_world_noise(world_xz + vec2(53.7, -17.9), blend_freq * 1.4);
    float fcount = float(count);
    int l0 = clamp(int(floor(n0 * fcount + 0.001)), 0, count - 1);
    int l1 = clamp(int(floor(n1 * fcount + 0.001)), 0, count - 1);
    vec2 uv0 = fract(tile_uv);
    vec2 uv1 = fract(tile_uv + vec2(0.5719, 0.4283));
    vec4 d0 = texture(array, vec3(uv0, float(l0)));
    vec4 d1 = texture(array, vec3(uv1, float(l1)));
    // Weight each tap by its alpha so high-coverage details dominate.
    // +0.05 avoids fully zero weight when both layers are alpha-empty.
    float w0 = d0.a + 0.05;
    float w1 = d1.a + 0.05;
    float wsum = w0 + w1;
    return vec4((d0.rgb * w0 + d1.rgb * w1) / wsum,
                clamp((d0.a + d1.a) * 0.5, 0.0, 1.0));
}

// Per-fragment slot weight from elevation + slope bands (Phase 4.9.b,
// spec 23 §Surface slot model). Smoothstep crossfade in from
// (band.x - band.z) to band.x, hold full weight band.x..band.y, then
// crossfade out from band.y to (band.y + band.w). Returns 0..1.
//
// Caller passes the slot's elev band as vec4(min_m, max_m,
// band_in_m, band_out_m) and slope band as vec4(min_deg, max_deg,
// band_in_deg, band_out_deg). Final weight is product (slot is
// active only where BOTH bands match).
float w5_slot_weight(vec4 elev_band, vec4 slope_band,
                     float elev_m, float slope_deg) {
    // Elevation band: ramp up min - band_in → min, ramp down max → max + band_out
    float ew_in  = smoothstep(elev_band.x - max(elev_band.z, 0.001), elev_band.x, elev_m);
    float ew_out = 1.0 - smoothstep(elev_band.y, elev_band.y + max(elev_band.w, 0.001), elev_m);
    float ew = ew_in * ew_out;
    // Slope band: same shape, in degrees
    float sw_in  = smoothstep(slope_band.x - max(slope_band.z, 0.001), slope_band.x, slope_deg);
    float sw_out = 1.0 - smoothstep(slope_band.y, slope_band.y + max(slope_band.w, 0.001), slope_deg);
    float sw = sw_in * sw_out;
    return ew * sw;
}


// ---- W4-style region selection + Heitz-Neyret 2018 sampling ----
//
// Port of W4's region hashing (terrain_world_v3.gdshader) + standard
// HN3 by-example noise sampling. Combined sampler `w5_variety_sample_combined`
// at bottom uses both.

uint w5_avalanche_u32(uint value) {
    uint x = value;
    x = ((x ^ 61u) ^ (x >> 16u));
    x = x + (x << 3u);
    x = x ^ (x >> 4u);
    x = x * 668265261u;
    x = x ^ (x >> 15u);
    return x;
}

uint w5_region_hash_u32(int seed, int salt, int region_x, int region_z) {
    uint x = uint(seed);
    x = x ^ (uint(salt) * 2654435761u);
    x = x ^ (uint(region_x) * 2246822507u);
    x = x ^ (uint(region_z) * 3266489909u);
    return w5_avalanche_u32(x);
}

// Pick which variant layer this region uses. Salt lets multiple slots
// (or multiple property arrays — normal, roughness — sharing the same
// seed) pick INDEPENDENT variants per region.
int w5_region_pick_variant(int seed, int salt, ivec2 region, int count) {
    if (count <= 1) return 0;
    uint h = w5_region_hash_u32(seed, salt, region.x, region.y);
    return int(h % uint(count));
}

// Edge-blend mix factor as we approach a region border from inside.
// d = distance from border (within blend_m). Linear ramp; could be
// smoothstep'd but linear matches W4's pattern.
float w5_region_neighbor_mix(float d, float blend_m) {
    if (blend_m <= 0.001) return 0.0;
    return clamp(1.0 - d / blend_m, 0.0, 1.0) * 0.5;
}

// W3 M11-derived hex-cell stochastic UV sampling (the proven anti-repeat
// + variance-preserving blend from world3/shaders/terrain_splat_unified.gdshader).
//
// Per Heitz & Neyret 2018 §3 + W3's working impl:
//   1. Skew UV into a triangle lattice via mat2([K,0],[-K/2,K]) where
//      K = 1.15470054 (= 2/sqrt(3)).
//   2. Pick the triangle the fragment is in; compute barycentric (w0,w1,w2).
//   3. For each vertex, hash-jitter the UV + hash-rotate, sample.
//   4. Variance-corrected blend: mean + (w0*d0+w1*d1+w2*d2)/sqrt(w0²+w1²+w2²)
//      where di = si - mean. This preserves CONTRAST (the histogram
//      variance), unlike plain weighted average which collapses it.
//
// W3 shipped this and it looked right. My earlier HN attempt had a no-op
// variance correction + broken T_inv LUT remap. This replaces both.
vec2 w5_hash22(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)),
             dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453) * 2.0 - 1.0;
}

float w5_hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec4 w5_hex_sample_jittered(sampler2DArray array, vec2 uv, int layer, vec2 cell) {
    vec2 jitter = w5_hash22(cell) * 0.5;
    float rot = w5_hash21(cell + 17.31) * 6.2831853;
    float c = cos(rot);
    float s = sin(rot);
    mat2 R = mat2(vec2(c, -s), vec2(s, c));
    return texture(array, vec3(fract(R * uv + jitter), float(layer)));
}

void w5_hex_weights(vec2 uv, out vec2 c0, out vec2 c1, out vec2 c2,
                    out float w0, out float w1, out float w2) {
    const float K = 1.15470054;
    mat2 GRID_TO_SKEW = mat2(vec2(K, 0.0), vec2(-K * 0.5, K));
    vec2 skewed = GRID_TO_SKEW * uv;
    vec2 ip = floor(skewed);
    vec2 fp = skewed - ip;
    if (fp.x + fp.y < 1.0) {
        c0 = ip; c1 = ip + vec2(1.0, 0.0); c2 = ip + vec2(0.0, 1.0);
        w0 = 1.0 - fp.x - fp.y; w1 = fp.x; w2 = fp.y;
    } else {
        c0 = ip + vec2(1.0, 0.0); c1 = ip + vec2(0.0, 1.0); c2 = ip + vec2(1.0, 1.0);
        w0 = 1.0 - fp.y; w1 = 1.0 - fp.x; w2 = fp.x + fp.y - 1.0;
    }
}

// Albedo path: variance-preserving blend (preserves histogram contrast).
vec4 w5_hex_sample_albedo(sampler2DArray array, vec2 uv, int layer) {
    vec2 c0, c1, c2; float w0, w1, w2;
    w5_hex_weights(uv, c0, c1, c2, w0, w1, w2);
    vec4 s0 = w5_hex_sample_jittered(array, uv, layer, c0);
    vec4 s1 = w5_hex_sample_jittered(array, uv, layer, c1);
    vec4 s2 = w5_hex_sample_jittered(array, uv, layer, c2);
    vec3 mean = (s0.rgb + s1.rgb + s2.rgb) / 3.0;
    vec3 d0 = s0.rgb - mean;
    vec3 d1 = s1.rgb - mean;
    vec3 d2 = s2.rgb - mean;
    float ws = sqrt(w0 * w0 + w1 * w1 + w2 * w2);
    return vec4(mean + (w0 * d0 + w1 * d1 + w2 * d2) / max(ws, 1e-4),
                s0.a * w0 + s1.a * w1 + s2.a * w2);
}

// One-plane variety sample: pick a variant by region hash, hex-sample it.
// `uv` is in plane-units (already scaled by 1/tile_m). Caller picks the
// plane (X-projected vs Y-projected vs Z-projected for triplanar).
vec4 w5_variety_sample_plane(
        sampler2DArray array, vec2 uv, vec2 region_xz,
        int start, int count,
        float region_size_m, float edge_blend_m,
        int seed, int salt) {
    if (count <= 0) return vec4(0.0);
    if (count == 1 || region_size_m <= 0.001) {
        return w5_hex_sample_albedo(array, uv, start);
    }
    vec2 region_f = floor(region_xz / region_size_m);
    ivec2 region = ivec2(int(region_f.x), int(region_f.y));
    int v_center = w5_region_pick_variant(seed, salt, region, count);
    vec4 c_center = w5_hex_sample_albedo(array, uv, start + v_center);
    if (edge_blend_m <= 0.001) return c_center;
    vec2 local_m = region_xz - region_f * region_size_m;
    int x_off = 0; int z_off = 0;
    float x_dist = region_size_m;
    float z_dist = region_size_m;
    if (local_m.x < edge_blend_m) {
        x_off = -1; x_dist = local_m.x;
    } else if (region_size_m - local_m.x < edge_blend_m) {
        x_off = 1; x_dist = region_size_m - local_m.x;
    }
    if (local_m.y < edge_blend_m) {
        z_off = -1; z_dist = local_m.y;
    } else if (region_size_m - local_m.y < edge_blend_m) {
        z_off = 1; z_dist = region_size_m - local_m.y;
    }
    if (x_off == 0 && z_off == 0) return c_center;
    float x_mix = (x_off != 0) ? w5_region_neighbor_mix(x_dist, edge_blend_m) : 0.0;
    float z_mix = (z_off != 0) ? w5_region_neighbor_mix(z_dist, edge_blend_m) : 0.0;
    float w_cc = (1.0 - x_mix) * (1.0 - z_mix);
    float w_xc = x_mix * (1.0 - z_mix);
    float w_cz = (1.0 - x_mix) * z_mix;
    float w_xz = x_mix * z_mix;
    vec4 acc = c_center * w_cc;
    if (x_off != 0) {
        int v = w5_region_pick_variant(seed, salt,
            ivec2(region.x + x_off, region.y), count);
        acc += (v != v_center
            ? w5_hex_sample_albedo(array, uv, start + v)
            : c_center) * w_xc;
    }
    if (z_off != 0) {
        int v = w5_region_pick_variant(seed, salt,
            ivec2(region.x, region.y + z_off), count);
        acc += (v != v_center
            ? w5_hex_sample_albedo(array, uv, start + v)
            : c_center) * w_cz;
    }
    if (x_off != 0 && z_off != 0) {
        int v = w5_region_pick_variant(seed, salt,
            ivec2(region.x + x_off, region.y + z_off), count);
        acc += (v != v_center
            ? w5_hex_sample_albedo(array, uv, start + v)
            : c_center) * w_xz;
    }
    return acc;
}

// Triplanar variety sample. Samples the sibling array from XY, XZ, YZ
// planes and blends by the absolute world normal. Steep slopes get the
// X- or Z-projected sample instead of the stretched-vertically XZ one.
// Region selection always uses world XZ (region is a world-XZ grid;
// triplanar swaps just the sampling plane).
//
// Arguments:
//   array:          sibling Texture2DArray
//   world_pos:      world XYZ
//   world_normal:   normalized world-space surface normal
//   tile_m:         world meters per tile (e.g. 8-16)
//   blend_sharp:    triplanar blend exponent (4-8 typical)
//   start, count:   sibling window
//   region_size_m, edge_blend_m, seed, salt: region selection params
vec4 w5_variety_sample_triplanar(
        sampler2DArray array,
        vec3 world_pos, vec3 world_normal,
        float tile_m, float blend_sharp,
        int start, int count,
        float region_size_m, float edge_blend_m,
        int seed, int salt) {
    float scale = 1.0 / max(tile_m, 0.001);
    vec2 uv_x = world_pos.zy * scale;  // projected from X axis
    vec2 uv_y = world_pos.xz * scale;  // projected from Y axis (the "normal" planar UV)
    vec2 uv_z = world_pos.xy * scale;  // projected from Z axis
    vec3 w = pow(abs(world_normal), vec3(blend_sharp));
    w /= max(w.x + w.y + w.z, 1e-5);
    // Region selection is world-XZ based regardless of which plane we sample.
    vec4 s_x = w5_variety_sample_plane(array, uv_x, world_pos.xz,
        start, count, region_size_m, edge_blend_m, seed, salt);
    vec4 s_y = w5_variety_sample_plane(array, uv_y, world_pos.xz,
        start, count, region_size_m, edge_blend_m, seed, salt);
    vec4 s_z = w5_variety_sample_plane(array, uv_z, world_pos.xz,
        start, count, region_size_m, edge_blend_m, seed, salt);
    return s_x * w.x + s_y * w.y + s_z * w.z;
}
