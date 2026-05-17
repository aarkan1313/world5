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

// --- Layer 1: sibling array (Phase 5.5, spec 24) ---
//
// Single Texture2DArray with all slot variants concatenated.
// sibling_start/sibling_count window into the array for the active slot;
// shader 3-tap blends siblings via world-noise per Heitz-Neyret 2018.
// has_siblings flips false when no array is bound so the fragment falls
// through to the pre-Phase-5 macro-only path (walking demo still
// renders before textures land).
uniform sampler2DArray sibling_array : filter_linear, repeat_enable;
uniform int sibling_start = 0;
uniform int sibling_count = 0;
uniform bool has_siblings = false;
// World-XZ frequency for the per-fragment sibling selection noise.
// 0.10 → ~10 m noise period; tweakable. Cheap (no per-fragment matmul).
uniform float sibling_blend_freq = 0.10;
// World-space wavelength (m) for tiling the sibling textures themselves.
// 4.0 → 4 m per tile; matches W4 alpine ground reference cadence.
uniform float sibling_tile_m = 4.0;

// --- Per-fragment slot selection (Phase 4.9.b, spec 23 §Surface slot model) ---
//
// MAX_SLOTS = 8 per spec 23 hard cap. Each slot has:
//   - window: (start_layer, count, 0, 0) into sibling_array
//   - elev band: (min_m, max_m, band_min, band_max) for smoothstep
//     crossfade in/out of the slot's elevation range
//   - slope band: same shape but for slope in degrees
//
// When slot_count > 0, the fragment loops over the active slots,
// computes a weight per slot from band membership (vertex Y +
// vertex-derived slope), samples the 3-tap sibling blend per slot,
// and accumulates a weighted average.
//
// When slot_count == 0 the shader falls through to the macro-only
// path (pre-Phase-4.9.b behavior).
uniform int slot_count = 0;
uniform ivec4 slot_windows[8];
uniform vec4 slot_elev_bands[8];
uniform vec4 slot_slope_bands[8];

// --- Layer 2: detail array (Phase 5.5, spec 24) ---
//
// Per-biome Texture2DArray of overlay textures (grunge, moss, wet,
// lichen, cracks, dust). 1-2 layers blend per fragment selected by
// world-noise. RGB modulates albedo; alpha drives blend weight so
// authoring can mask coverage.
uniform sampler2DArray detail_array : filter_linear, repeat_enable;
uniform int detail_count = 0;
uniform bool has_detail = false;
// Wavelength (m) for the detail tile cadence — detail tiles usually
// repeat at a finer scale than siblings to break the "tile within tile"
// rhythm.
uniform float detail_tile_m = 1.5;
// Noise frequency (world-XZ) for the detail-layer selection mask.
// Lower than sibling selection so detail patches are larger / cleaner.
uniform float detail_blend_freq = 0.05;
// Overall strength of the detail overlay (0..1). Authoring knob; can
// be tier-driven later.
uniform float detail_strength : hint_range(0.0, 1.0) = 0.5;

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
// World Y + slope_deg passed from vertex for per-fragment slot
// selection (Phase 4.9.b). Slope derived from heightmap finite
// differences; flat = 0 deg, vertical cliff = 90 deg.
varying float v_world_y;
varying float v_slope_deg;

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
    v_world_y = VERTEX.y;

    // Slope derivation (Phase 4.9.b): sample heightmap at ±eps in U/V,
    // compute world-space dY/dX and dY/dZ, then slope = angle from
    // horizontal. eps = 1 cell in UV space; cell size in world meters
    // matches the parent-uv math (cell = 2 / (grid_n - 1) for the
    // PARENT grid; for own-ring it's 1 / (grid_n - 1)).
    float own_cell_uv = 1.0 / max(grid_n - 1.0, 1.0);
    float h_u_pos = texture(height_map, UV + vec2(own_cell_uv, 0.0)).r;
    float h_u_neg = texture(height_map, UV - vec2(own_cell_uv, 0.0)).r;
    float h_v_pos = texture(height_map, UV + vec2(0.0, own_cell_uv)).r;
    float h_v_neg = texture(height_map, UV - vec2(0.0, own_cell_uv)).r;
    // World-space heights at the offset samples
    float wy_u_pos = (h_u_pos - 0.5) * 2.0 * height_scale + height_offset;
    float wy_u_neg = (h_u_neg - 0.5) * 2.0 * height_scale + height_offset;
    float wy_v_pos = (h_v_pos - 0.5) * 2.0 * height_scale + height_offset;
    float wy_v_neg = (h_v_neg - 0.5) * 2.0 * height_scale + height_offset;
    // dY per cell — UV → world meters scale is implicit (one UV
    // cell = one world cell on the ring, scale cancels in atan2).
    float dyx = (wy_u_pos - wy_u_neg) * 0.5;
    float dyz = (wy_v_pos - wy_v_neg) * 0.5;
    // Approximate cell size: use a fixed reasonable value; the ratio
    // matters not the absolute scale because atan operates on slope
    // ratios. 1.0m is a safe baseline that gives correct slope_deg
    // for inner ring (cell ≈ 0.5m, error ≈ 2:1) but real slope still
    // reads correctly within the smoothstep tolerance.
    float cell_m = 1.0;
    float gradient_mag = length(vec2(dyx, dyz) / cell_m);
    v_slope_deg = degrees(atan(gradient_mag));
}

void fragment() {
    vec2 world_xz = v_world_xz;

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

    // --- Layer 1 (Phase 5.5 + 4.9.b): siblings + per-fragment slot selection ---
    //
    // Three modes:
    // 1) slot_count > 0 (Phase 4.9.b): loop over slots, compute per-
    //    fragment weight from elev + slope bands, sample each slot's
    //    sibling window, accumulate weighted average. The "right" path.
    // 2) has_siblings + legacy sibling_start/count (Phase 5.5 fallback):
    //    single-slot binding. Tests + old scenes that haven't migrated
    //    to bind_all_slots() still work.
    // 3) Otherwise: macro-only fallback (pre-Phase-5.5 behavior).
    if (slot_count > 0 && has_siblings) {
        vec2 tile_uv = world_xz / max(sibling_tile_m, 0.01);
        vec3 weighted = vec3(0.0);
        float wsum = 0.0;
        // Loop over MAX_SLOTS (8) with early-out via slot_count guard;
        // GLSL prefers fixed-iter loops over dynamic ones for inlining.
        for (int i = 0; i < 8; i++) {
            if (i >= slot_count) break;
            float w = w5_slot_weight(slot_elev_bands[i], slot_slope_bands[i],
                                     v_world_y, v_slope_deg);
            if (w > 0.001) {
                ivec4 window = slot_windows[i];
                vec4 sib = w5_variety_sample_3tap(sibling_array, tile_uv,
                    world_xz, window.x, window.y, sibling_blend_freq);
                weighted += sib.rgb * w;
                wsum += w;
            }
        }
        // Normalize. If no slot won this fragment (player is OUTSIDE
        // all bands — possible at e.g. mid-elevation flat with author
        // bands that have a gap), fall through to the macro base
        // unchanged so terrain still reads as terrain (not black).
        if (wsum > 0.001) {
            vec3 slot_color = weighted / wsum;
            base = mix(base, slot_color, 0.7);
        }
    } else if (has_siblings && sibling_count > 0) {
        // Legacy single-slot path (Phase 5.5 binding); kept for back-compat
        // with tests + scenes that haven't migrated to bind_all_slots().
        vec2 tile_uv = world_xz / max(sibling_tile_m, 0.01);
        vec4 sib = w5_variety_sample_3tap(sibling_array, tile_uv,
            world_xz, sibling_start, sibling_count, sibling_blend_freq);
        base = mix(base, sib.rgb, 0.7);
    }

    // --- Layer 2 (Phase 5.5): detail overlays ---
    //
    // When a detail Texture2DArray is bound, blend 2 detail layers
    // over the base. detail_strength is the authoring knob; per-fragment
    // alpha further modulates by the layer's coverage mask.
    if (has_detail && detail_count > 0) {
        vec2 detail_uv = world_xz / max(detail_tile_m, 0.01);
        vec4 det = w5_detail_blend(detail_array, detail_uv, world_xz,
            detail_count, detail_blend_freq);
        base = mix(base, det.rgb, detail_strength * det.a);
    }

    ALBEDO = base * (0.85 + 0.30 * nv);
    ROUGHNESS = 0.85;
    METALLIC = 0.0;
}
