// Variety shader primitives (spec 24 layers).
//
// Included by terrain_clipmap.gdshader. Pure functions only — caller
// supplies textures + uniforms.

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
