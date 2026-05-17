// W5 terrain clipmap shader (Phase 4.4)
//
// Vertex: sample heightmap at vertex's local UV, displace Y.
// Fragment: macro albedo + procedural color grading by height.
//
// Phase 4 MVP — sibling/detail array integration ships post-4.6 once
// the world bundle authoring tools land. For now: macro albedo is the
// primary color source; per-fragment hash modulates it slightly for
// the appearance of variety.

shader_type spatial;

#include "res://addons/world5/shaders/variety_common.gdshaderinc"

// --- heightmap (per-ring) ---
uniform sampler2D height_map : repeat_disable, filter_linear;
uniform float height_scale: hint_range(0.0, 1000.0) = 50.0;
uniform float height_offset: hint_range(-500.0, 500.0) = 0.0;

// --- macro albedo (world-spanning) ---
uniform sampler2D macro_albedo : repeat_disable, filter_linear;
uniform vec4 macro_aabb = vec4(-1024.0, -1024.0, 1024.0, 1024.0);
uniform vec3 fallback_color : source_color = vec3(0.35, 0.45, 0.25);

// --- LOD morph (per-ring driven by ClipmapDispatch) ---
uniform float morph_factor : hint_range(0.0, 1.0) = 0.0;

void vertex() {
    // Sample heightmap at this vertex's UV (vertices come with UV
    // matching the ring's local grid)
    float h = texture(height_map, UV).r;
    // Heightmap stored as [0,1] normalized fraction → world height
    VERTEX.y = (h - 0.5) * 2.0 * height_scale + height_offset;
}

void fragment() {
    // World XZ from the model-space vertex position
    vec2 world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;

    // Sample macro albedo (the anti-repeat layer)
    vec2 mu = w5_macro_uv(world_xz, macro_aabb);
    vec3 macro_col = texture(macro_albedo, mu).rgb;

    // Variation: small modulation by world-noise so adjacent fragments
    // differ slightly even when sampling the same macro pixel
    float nv = w5_world_noise(world_xz, 0.05);
    vec3 base = mix(macro_col, fallback_color, 0.15);
    ALBEDO = base * (0.85 + 0.30 * nv);
    ROUGHNESS = 0.85;
    METALLIC = 0.0;
}
