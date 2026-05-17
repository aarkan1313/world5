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
//
// morph_factor is the per-ring "how close to the outer boundary is the
// camera" value computed by ClipmapDispatch.compute_morph_factor().
// At 0.0 the vertex renders at its own ring's resolution; at 1.0 it
// snaps to where the next-coarser ring's vertex would be.
//
// The morph itself: heightmap sample at the vertex's UV vs heightmap
// sample at the parent-ring-aligned UV (rounded to even cells).
// Blending the two heights smooths the LOD transition so ring
// boundaries don't visibly pop (OA-C1 fix from 2026-05-17 audit).
uniform float morph_factor : hint_range(0.0, 1.0) = 0.0;
// Grid size in vertices per side (matches ring_vertex_grid in
// TerrainWorld; used to compute parent-ring UV snap).
uniform float grid_n = 256.0;

// World XZ passed from vertex to fragment so the per-fragment matmul
// is avoided (TR-PERF-M1 fix).
varying vec2 v_world_xz;

// Snap a UV to the parent-ring sample grid: every other vertex along
// each axis matches a parent-ring vertex, so rounding to the nearest
// even-cell UV gives the height the coarser ring would interpolate.
vec2 w5_parent_uv(vec2 uv, float n) {
    // Cell size in UV space; parent grid has half the resolution
    float parent_cell = 2.0 / max(n - 1.0, 1.0);
    return floor(uv / parent_cell + 0.5) * parent_cell;
}

void vertex() {
    // This vertex's own height (own-ring resolution)
    float h_self = texture(height_map, UV).r;
    // Parent-ring height (next-coarser resolution at this XZ)
    float h_parent = texture(height_map, w5_parent_uv(UV, grid_n)).r;
    // Morph: 0 = own ring, 1 = parent ring. Smooth blend hides LOD
    // boundary; ClipmapDispatch drives morph_factor toward 1 as the
    // vertex approaches the ring's outer edge.
    float h = mix(h_self, h_parent, morph_factor);
    // Heightmap stored as [0,1] normalized fraction → world height
    VERTEX.y = (h - 0.5) * 2.0 * height_scale + height_offset;
    // Compute world_xz ONCE in vertex (was per-fragment matmul)
    v_world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
    vec2 world_xz = v_world_xz;

    // Sample macro albedo (the anti-repeat layer). When no macro
    // texture is bound, texture() returns vec3(0); detect that and
    // fall back to fallback_color at full strength instead of the
    // 15% blend (which made unbound-macro terrain near-black against
    // the procedural-sky ground band, invisible — Phase 4.6 visual
    // review caught this).
    // Sample macro albedo (the anti-repeat layer). When no macro
    // texture is bound, texture() returns vec3(0); detect that and
    // fall back to fallback_color at full strength instead of the
    // 15% blend (which made unbound-macro terrain near-black against
    // the procedural-sky ground band, invisible — Phase 4.6 visual
    // review caught this).
    vec2 mu = w5_macro_uv(world_xz, macro_aabb);
    vec3 macro_col = texture(macro_albedo, mu).rgb;
    float macro_strength = dot(macro_col, vec3(1.0)) > 0.001 ? 0.85 : 0.0;

    // Variation: small modulation by world-noise so adjacent fragments
    // differ slightly even when sampling the same macro pixel
    float nv = w5_world_noise(world_xz, 0.05);
    vec3 base = mix(fallback_color, macro_col, macro_strength);
    ALBEDO = base * (0.85 + 0.30 * nv);
    ROUGHNESS = 0.85;
    METALLIC = 0.0;
}
