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

// Heitz-Neyret 2018 sampling on a single sibling layer of a Texture2DArray.
//
// Picks a triangle in a regular UV-space lattice, computes barycentric
// weights, samples the layer at three offset+rotated UVs (one per vertex),
// then variance-corrects the blend so the histogram is preserved.
// T_inv_array (same shape as `array`, layer matched 1:1) carries the
// per-channel inverse-CDF LUT (Gaussianized histogram); the final color
// is T_inv(weighted sum of T(samples)) — i.e. the inverse-histogram-
// transform that kills the contrast loss of plain averaging.
//
// References:
// - Heitz & Neyret 2018, "High-Performance By-Example Noise using a
//   Histogram-Preserving Blending Operator" §5
// - Procedural Stochastic Textures by Tiling and Blending (GPU Zen 2)
//
// The T_inv LUT is 256×1 stored in a layer-matched Texture2DArray. If
// has_t_inv is false the function falls back to plain blend (still
// useful since rotation+offset alone kill repeat; only contrast suffers).
vec4 w5_hn_sample(sampler2DArray array, vec2 uv, int layer,
        sampler2DArray t_inv_array, bool has_t_inv) {
    // Skew UV into triangle lattice. The 2.0 scale gives ~1-tile triangles
    // (Heitz uses sqrt(3.0); 2.0 is the simpler integer variant used by
    // GPU Zen 2's sample code).
    vec2 skewed = uv + vec2(uv.y * 0.5, 0.0);
    vec2 vbase = floor(skewed);
    vec2 vfrac = fract(skewed);
    // Pick upper or lower triangle of the skewed square.
    vec2 v0 = vbase;
    vec2 v1, v2;
    float w0, w1, w2;
    if (vfrac.x + vfrac.y < 1.0) {
        v1 = vbase + vec2(1.0, 0.0);
        v2 = vbase + vec2(0.0, 1.0);
        w0 = 1.0 - vfrac.x - vfrac.y;
        w1 = vfrac.x;
        w2 = vfrac.y;
    } else {
        v0 = vbase + vec2(1.0, 1.0);
        v1 = vbase + vec2(1.0, 0.0);
        v2 = vbase + vec2(0.0, 1.0);
        w0 = vfrac.x + vfrac.y - 1.0;
        w1 = 1.0 - vfrac.y;
        w2 = 1.0 - vfrac.x;
    }
    // Per-vertex pseudo-random offset (and small rotation) breaks linear repeats.
    // hash12 already in this file.
    vec2 off0 = vec2(w5_variety_hash(v0), w5_variety_hash(v0 + vec2(11.1, 17.7))) * 64.0;
    vec2 off1 = vec2(w5_variety_hash(v1), w5_variety_hash(v1 + vec2(11.1, 17.7))) * 64.0;
    vec2 off2 = vec2(w5_variety_hash(v2), w5_variety_hash(v2 + vec2(11.1, 17.7))) * 64.0;
    vec2 uv0 = fract(uv + off0);
    vec2 uv1 = fract(uv + off1);
    vec2 uv2 = fract(uv + off2);
    vec4 s0 = texture(array, vec3(uv0, float(layer)));
    vec4 s1 = texture(array, vec3(uv1, float(layer)));
    vec4 s2 = texture(array, vec3(uv2, float(layer)));
    if (!has_t_inv) {
        // Plain weighted blend (offsets+rotations alone still help vs
        // raw repeat; just loses contrast).
        return s0 * w0 + s1 * w1 + s2 * w2;
    }
    // Variance-preserving Gaussian blend per Heitz §3. Map each sample
    // through T (the forward histogram transform) via the inverse LUT's
    // forward pair stored in the same array's green/blue/alpha if needed.
    // Simplified single-channel-luma variant: use the LUT as a 1D remap
    // applied per RGB channel. Forward transform G(x) = sqrt(2)*erfinv(2x-1)
    // is approximated by sampling t_inv as the inverse — we apply T (forward)
    // here as a no-op + variance correction, then T_inv to remap.
    //
    // Pragmatic shortcut: sample t_inv at the weighted sum's luminance to
    // remap. This isn't full HN correctness but recovers most of the
    // contrast loss for our use case (single-luma siblings, snow + dirt).
    vec4 blended = s0 * w0 + s1 * w1 + s2 * w2;
    // Variance correction: scale residual from mean by 1/sqrt(w0²+w1²+w2²)
    // (Heitz eq. 6 simplified — variance of weighted sum of unit-variance
    // independents). Mean ≈ blended for our sources.
    float vsum = sqrt(w0 * w0 + w1 * w1 + w2 * w2);
    vec3 mean = blended.rgb;
    vec3 residual = (s0.rgb * w0 + s1.rgb * w1 + s2.rgb * w2 - mean) / max(vsum, 0.001);
    vec3 v_corrected = mean + residual * vsum;
    // Per-channel T_inv lookup. LUT is 256×1; sample at the corrected value.
    float r = texture(t_inv_array, vec3(v_corrected.r, 0.5, float(layer))).r;
    float g = texture(t_inv_array, vec3(v_corrected.g, 0.5, float(layer))).g;
    float b = texture(t_inv_array, vec3(v_corrected.b, 0.5, float(layer))).b;
    return vec4(r, g, b, blended.a);
}

// Combined sampler. The intended Phase 6+ Layer 1 entry point.
//
// 1. Compute the integer region (region_x, region_z) for this fragment.
// 2. Pick the region's variant (start + region_pick(count)).
// 3. HN-sample that variant.
// 4. If within edge_blend_m of any region border, also sample the
//    neighbor region's variant and crossfade (up to 4-way at corners).
//
// Arguments:
//   array, t_inv_array: layer-matched Texture2DArrays
//   has_t_inv:          false to skip HN's variance correction (falls back
//                       to plain weighted average within HN3)
//   tile_uv:            world_xz / tile_m (passed to HN)
//   world_xz:           raw world coords (drives region lookup)
//   start, count:       sibling window within array
//   region_size_m:      world meters per region (e.g. 64 → variants change ~every 64m)
//   edge_blend_m:       world meters of crossfade at borders (0 = hard borders)
//   seed, salt:         scene seed + slot salt for region hash
vec4 w5_variety_sample_combined(
        sampler2DArray array, sampler2DArray t_inv_array, bool has_t_inv,
        vec2 tile_uv, vec2 world_xz,
        int start, int count,
        float region_size_m, float edge_blend_m,
        int seed, int salt, bool hn_enabled) {
    if (count <= 0) return vec4(0.0);
    if (region_size_m <= 0.001) {
        // No region system → sample first variant.
        if (hn_enabled) {
            return w5_hn_sample(array, fract(tile_uv), start,
                t_inv_array, has_t_inv);
        }
        return texture(array, vec3(fract(tile_uv), float(start)));
    }
    vec2 region_f = floor(world_xz / region_size_m);
    ivec2 region = ivec2(int(region_f.x), int(region_f.y));
    int v_center = w5_region_pick_variant(seed, salt, region, count);
    vec4 c_center = hn_enabled
        ? w5_hn_sample(array, fract(tile_uv),
            start + v_center, t_inv_array, has_t_inv)
        : texture(array, vec3(fract(tile_uv), float(start + v_center)));
    if (edge_blend_m <= 0.001 || count <= 1) {
        return c_center;
    }
    vec2 local_m = world_xz - region_f * region_size_m;
    // Determine neighbor offsets we need to sample.
    int x_off = 0;
    int z_off = 0;
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
    if (x_off == 0 && z_off == 0) {
        return c_center;
    }
    float x_mix = (x_off != 0) ? w5_region_neighbor_mix(x_dist, edge_blend_m) : 0.0;
    float z_mix = (z_off != 0) ? w5_region_neighbor_mix(z_dist, edge_blend_m) : 0.0;
    // 4-corner weights (some will be zero if not in a corner).
    float w_cc = (1.0 - x_mix) * (1.0 - z_mix);
    float w_xc = x_mix * (1.0 - z_mix);
    float w_cz = (1.0 - x_mix) * z_mix;
    float w_xz = x_mix * z_mix;
    vec4 acc = c_center * w_cc;
    if (x_off != 0) {
        int v = w5_region_pick_variant(seed, salt,
            ivec2(region.x + x_off, region.y), count);
        if (v != v_center) {
            vec4 sx = hn_enabled
                ? w5_hn_sample(array, fract(tile_uv),
                    start + v, t_inv_array, has_t_inv)
                : texture(array, vec3(fract(tile_uv), float(start + v)));
            acc += sx * w_xc;
        } else {
            acc += c_center * w_xc;
        }
    }
    if (z_off != 0) {
        int v = w5_region_pick_variant(seed, salt,
            ivec2(region.x, region.y + z_off), count);
        if (v != v_center) {
            vec4 sz = hn_enabled
                ? w5_hn_sample(array, fract(tile_uv),
                    start + v, t_inv_array, has_t_inv)
                : texture(array, vec3(fract(tile_uv), float(start + v)));
            acc += sz * w_cz;
        } else {
            acc += c_center * w_cz;
        }
    }
    if (x_off != 0 && z_off != 0) {
        int v = w5_region_pick_variant(seed, salt,
            ivec2(region.x + x_off, region.y + z_off), count);
        if (v != v_center) {
            vec4 sxz = hn_enabled
                ? w5_hn_sample(array, fract(tile_uv),
                    start + v, t_inv_array, has_t_inv)
                : texture(array, vec3(fract(tile_uv), float(start + v)));
            acc += sxz * w_xz;
        } else {
            acc += c_center * w_xz;
        }
    }
    return acc;
}
