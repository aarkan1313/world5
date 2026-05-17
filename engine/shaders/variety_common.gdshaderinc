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
