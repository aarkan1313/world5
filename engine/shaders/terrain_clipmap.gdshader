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
//
// Legacy single-page binding (Phase 4.4-4.8): `height_map` Texture2D
// covers the ring's snapped_center page; sampled with UV (mesh-local).
// Stretches at outer-ring edges when ring extent > page_extent_m;
// caused chunk seams pre-Phase-4.9.a.
uniform sampler2D height_map : repeat_disable, filter_linear;
uniform float height_scale: hint_range(0.0, 1000.0) = 50.0;
uniform float height_offset: hint_range(-500.0, 500.0) = 0.0;

// --- multi-page heightmap (Phase 4.9.a, audit C1 fix) ---
//
// When `has_height_array` is true, the vertex shader samples from
// `height_array` (Texture2DArray) instead of `height_map`. Each layer
// holds one page; layer index = page_y * height_pages_per_side +
// page_x, where (page_x, page_y) are page-grid coords relative to
// `height_array_min_xz`. Pages span `height_array_page_extent_m` of
// world XZ each.
//
// This lets outer rings sample the correct page per fragment instead
// of stretching one page across the whole ring.
uniform sampler2DArray height_array : repeat_disable, filter_linear;
uniform bool has_height_array = false;
uniform int height_pages_per_side = 1;
uniform vec2 height_array_min_xz = vec2(0.0, 0.0);
uniform float height_array_page_extent_m = 256.0;

// --- macro albedo (world-spanning) ---
uniform sampler2D macro_albedo : repeat_disable, filter_linear;
uniform vec4 macro_aabb = vec4(-1024.0, -1024.0, 1024.0, 1024.0);
uniform vec3 fallback_color : source_color = vec3(0.35, 0.45, 0.25);
// TEMP diagnostic 2026-05-17: toggle macro/fallback contributions to
// isolate what's washing out slot textures. Set from script via
// material.set_shader_parameter("macro_debug_mode", N).
//   0 = production (macro 0.35 mix into fallback, slot mix 0.7)
//   1 = no macro, no fallback contamination — pure slot color
//   2 = pure macro (no fallback olive), slot mix 0.85 = 85% slot
//   3 = macro fully off (fallback green visible where no slot)
// Remove this uniform + branch once we pick the production behavior.
uniform int macro_debug_mode = 0;

// --- Layer 1: sibling array (Phase 5.5, spec 24) ---
//
// Single Texture2DArray with all slot variants concatenated.
// sibling_start/sibling_count window into the array for the active slot;
// shader 3-tap blends siblings via world-noise per Heitz-Neyret 2018.
// has_siblings flips false when no array is bound so the fragment falls
// through to the pre-Phase-5 macro-only path (walking demo still
// renders before textures land).
uniform sampler2DArray sibling_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform int sibling_start = 0;
uniform int sibling_count = 0;
uniform bool has_siblings = false;
// World-XZ frequency for the per-fragment sibling selection noise.
// (Legacy `w5_variety_sample_3tap`; kept for back-compat with single-slot
// scenes + tests. Phase 6 visual A/B replaced primary path with
// `w5_variety_sample_combined` which uses region+HN sampling.)
uniform float sibling_blend_freq = 0.10;
// World-space wavelength (m) for tiling the sibling textures themselves.
// Bumped 2026-05-17 from 4 → 16: with region_size_m=512 a 4m tile
// repeats 128× per region (visible wallpaper). 16m repeats 32× per
// region, reads as natural ground texture at walking eye height.
uniform float sibling_tile_m = 16.0;

// Heitz-Neyret 2018 inverse-histogram LUT array (Phase 6 follow-up).
// Layer-matched 1:1 with sibling_array; each entry is a 256×1 LUT.
// has_t_inv flips false when missing → HN falls back to plain blend.
uniform sampler2DArray sibling_t_inv_array : filter_linear, repeat_disable;
uniform bool has_t_inv = false;
// Region-based variant selection (W4 pattern, terrain_world_v3.gdshader).
// region_size_m: world meters per region (typical 32-128).
// edge_blend_m: crossfade width at region borders (0 = hard borders).
// world_seed: scene seed (from material_variants.json) for the region hash.
uniform float region_size_m = 0.0;
uniform float edge_blend_m = 0.0;
uniform int world_seed = 0;
// Phase 6 follow-up diagnostic: bypass HN tiling, just region-pick +
// plain texture sample. Lets us isolate region-system correctness
// from HN sampler correctness during visual review. Default false
// (region-only) since first HN impl had visible white-patch artifacts;
// will re-enable after fixing variance correction. Toggle: 4=off, 5=on.
uniform bool hn_enabled = false;

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
// Phase 6 / 5.7.b GDScript Composer mirror: per-slot biome index +
// per-biome auto_rule bands. biome_count=0 disables the per-biome
// multiply (single-biome scenes still render via slot_weight only).
// Index packed as int[] (NOT ivec4 — single int per slot).
uniform int slot_biome_index[8];
uniform int biome_count = 0;
uniform vec4 biome_auto_elev_bands[8];
uniform vec4 biome_auto_slope_bands[8];
// Per-biome avg ground albedo. Used as a per-fragment biome-weighted
// fallback color so coverage gaps (no slot wins, e.g. mid-elev flats
// where ground band ends but mid needs steep slope) blend to neighbor-
// biome's ground color instead of a single global olive. Bound from
// TerrainWorld._bind_slots_with_catalog by sampling each biome's first
// ground slot albedo and downscaling to a 1×1 average.
uniform vec3 biome_fallback_colors[8];

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

// --- Terrain edge haze ---
//
// Minimal terrain-only haze for the current finite clipmap. The full
// Atmosphere system owns sky/fog later; this pass hides the hard outer
// clipmap edge and late page visibility during walking-demo review.
uniform bool terrain_haze_enabled = false;
uniform float terrain_haze_start_m = 1000000.0;
uniform float terrain_haze_end_m = 1000001.0;
uniform float terrain_haze_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 terrain_haze_color : source_color = vec3(0.646, 0.656, 0.674);

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
//
// Phase 4.10.a (W4 PITFALLS #11 fix): morph is now per-vertex. Pre-
// fix `morph_factor` was a single per-ring uniform driven by camera-
// to-ring-CENTER distance, so all vertices got the same factor and
// the outer-edge vertices never morphed when camera was near center
// → visible cliff at ring boundary. Per-vertex math: each vertex
// computes its own morph from its world-XZ distance to the ring's
// outer edge.
uniform vec2 ring_center_xz = vec2(0.0, 0.0);
uniform float ring_half_extent_m = 1.0;
uniform float morph_band_frac : hint_range(0.0, 0.5) = 0.16;
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

// Sample heightmap at world XZ, picking from height_array or the
// legacy height_map per `has_height_array`. Returns normalized [0,1]
// height value matching the shader's encoding (caller decodes via
// (h - 0.5) * 2 * scale + offset).
//
// For the array path: compute page coord from world XZ → array layer
// (spatially packed, no lookup table needed) + UV within the page.
// Out-of-window samples return 0.5 (= world y = 0) so missing pages
// look like flat ground instead of black/garbage.
float w5_sample_height(vec2 world_xz, vec2 fallback_uv) {
    if (has_height_array) {
        vec2 ring_local = world_xz - height_array_min_xz;
        vec2 page_coord_f = ring_local / max(height_array_page_extent_m, 0.01);
        ivec2 page_coord = ivec2(floor(page_coord_f));
        // Reject out-of-window (shouldn't happen at runtime but defensive)
        if (page_coord.x < 0 || page_coord.y < 0 ||
            page_coord.x >= height_pages_per_side ||
            page_coord.y >= height_pages_per_side) {
            return 0.5;
        }
        int layer = page_coord.y * height_pages_per_side + page_coord.x;
        vec2 uv_within_page = page_coord_f - vec2(float(page_coord.x), float(page_coord.y));
        return texture(height_array, vec3(uv_within_page, float(layer))).r;
    }
    return texture(height_map, fallback_uv).r;
}

void vertex() {
    // Compute world XZ for THIS vertex (pre-displacement; model matrix
    // is XZ-translate-only so VERTEX.y doesn't affect it).
    vec2 vertex_world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
    // This vertex's own height (own-ring resolution). For the
    // height_array path, use world XZ → page → layer; for the legacy
    // single-page path, use the mesh-local UV.
    float h_self = w5_sample_height(vertex_world_xz, UV);
    // Parent-ring height (next-coarser resolution at this XZ). For the
    // array path, we need to snap world XZ to the parent grid (vs UV
    // snapping which is fine for single-page). Approximate by snapping
    // to a 2× cell in world XZ.
    vec2 parent_world_xz = vertex_world_xz;
    if (has_height_array) {
        // Cell size in world meters for own-ring ≈ page_extent /
        // (grid_n - 1). Parent grid is 2× coarser, so snap to 2× cell.
        float own_cell_m = height_array_page_extent_m / max(grid_n - 1.0, 1.0);
        float parent_cell_m = own_cell_m * 2.0;
        parent_world_xz = floor(vertex_world_xz / parent_cell_m + vec2(0.5)) * parent_cell_m;
    }
    float h_parent = has_height_array
        ? w5_sample_height(parent_world_xz, UV)
        : texture(height_map, w5_parent_uv(UV, grid_n)).r;
    // Phase 4.10.a per-vertex morph (W4 PITFALLS #11). Chebyshev
    // distance from THIS vertex to ring center; band starts at
    // ring_half_extent * (1 - morph_band_frac) and ends at
    // ring_half_extent. Inside the band, morph linearly ramps 0 → 1.
    // Outermost ring has no parent → ring_half_extent_m == 0 (or any
    // value with morph_band_frac == 0) → morph stays at 0 always.
    vec2 to_center = vertex_world_xz - ring_center_xz;
    float cheb = max(abs(to_center.x), abs(to_center.y));
    float band_start = ring_half_extent_m * (1.0 - morph_band_frac);
    float band_width = ring_half_extent_m - band_start;
    float m = 0.0;
    if (band_width > 0.001 && cheb > band_start) {
        m = clamp((cheb - band_start) / band_width, 0.0, 1.0);
    }
    float h = mix(h_self, h_parent, m);
    // Heightmap stored as [0,1] normalized fraction → world height
    VERTEX.y = (h - 0.5) * 2.0 * height_scale + height_offset;
    // World XZ unchanged by Y displacement; cache for fragment.
    v_world_xz = vertex_world_xz;
    v_world_y = VERTEX.y;

    // Slope derivation (Phase 4.9.b): 4-tap finite difference. For the
    // array path, sample at ±1 cell in world XZ; for the legacy path,
    // sample at ±1 UV-cell.
    float h_u_pos, h_u_neg, h_v_pos, h_v_neg;
    float cell_m;
    if (has_height_array) {
        cell_m = height_array_page_extent_m / max(grid_n - 1.0, 1.0);
        h_u_pos = w5_sample_height(vertex_world_xz + vec2(cell_m, 0.0), UV);
        h_u_neg = w5_sample_height(vertex_world_xz - vec2(cell_m, 0.0), UV);
        h_v_pos = w5_sample_height(vertex_world_xz + vec2(0.0, cell_m), UV);
        h_v_neg = w5_sample_height(vertex_world_xz - vec2(0.0, cell_m), UV);
    } else {
        float own_cell_uv = 1.0 / max(grid_n - 1.0, 1.0);
        h_u_pos = texture(height_map, UV + vec2(own_cell_uv, 0.0)).r;
        h_u_neg = texture(height_map, UV - vec2(own_cell_uv, 0.0)).r;
        h_v_pos = texture(height_map, UV + vec2(0.0, own_cell_uv)).r;
        h_v_neg = texture(height_map, UV - vec2(0.0, own_cell_uv)).r;
        cell_m = 1.0;  // approximation (see Phase 4.9.b note)
    }
    // World-space heights at the offset samples
    float wy_u_pos = (h_u_pos - 0.5) * 2.0 * height_scale + height_offset;
    float wy_u_neg = (h_u_neg - 0.5) * 2.0 * height_scale + height_offset;
    float wy_v_pos = (h_v_pos - 0.5) * 2.0 * height_scale + height_offset;
    float wy_v_neg = (h_v_neg - 0.5) * 2.0 * height_scale + height_offset;
    float dyx = (wy_u_pos - wy_u_neg) * 0.5;
    float dyz = (wy_v_pos - wy_v_neg) * 0.5;
    float gradient_mag = length(vec2(dyx, dyz) / max(cell_m, 0.001));
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
    // Phase 6 / 5.7.b GDScript Composer mirror — lifted out of the
    // slot_count branch so it can also feed the biome-weighted
    // fallback color below.
    float biome_w[8];
    float biome_w_sum = 0.0;
    for (int b = 0; b < 8; b++) {
        biome_w[b] = 0.0;
        if (b >= biome_count) continue;
        biome_w[b] = w5_slot_weight(
            biome_auto_elev_bands[b],
            biome_auto_slope_bands[b],
            v_world_y, v_slope_deg);
        biome_w_sum += biome_w[b];
    }
    if (biome_count > 0) {
        if (biome_w_sum > 0.001) {
            for (int b = 0; b < 8; b++) biome_w[b] /= biome_w_sum;
        } else {
            float uniform_w = 1.0 / float(biome_count);
            for (int b = 0; b < 8; b++) {
                biome_w[b] = (b < biome_count) ? uniform_w : 0.0;
            }
        }
    }

    // Per-fragment biome-weighted fallback color. Replaces the single
    // global `fallback_color` so coverage gaps blend neighbor-biome's
    // ground color (no green olive screaming "BUG HERE"). Single-biome
    // scenes (biome_count==0) keep the legacy global fallback.
    vec3 frag_fallback = fallback_color;
    if (biome_count > 0) {
        frag_fallback = vec3(0.0);
        for (int b = 0; b < 8; b++) {
            if (b >= biome_count) break;
            frag_fallback += biome_w[b] * biome_fallback_colors[b];
        }
    }

    // Sample macro albedo (the anti-repeat layer). When no macro
    // texture is bound, texture() returns vec3(0); detect that and
    // fall back to frag_fallback at full strength.
    vec2 mu = w5_macro_uv(world_xz, macro_aabb);
    vec3 macro_col = texture(macro_albedo, mu).rgb;
    bool macro_present = dot(macro_col, vec3(1.0)) > 0.001;
    // Per-mode macro strength (see macro_debug_mode uniform comment).
    float macro_strength = 0.35;
    if (macro_debug_mode == 1) macro_strength = 0.0;
    else if (macro_debug_mode == 2) macro_strength = 1.0;
    else if (macro_debug_mode == 3) macro_strength = 0.0;
    if (!macro_present) macro_strength = 0.0;

    // Phase 4.10.c (W4 PITFALLS #31 fix): brightness modulator removed.
    // See git log f571576-era comments for history.
    vec3 base = mix(frag_fallback, macro_col, macro_strength);

    // --- Layer 1 (Phase 5.5 + 4.9.b): siblings + per-fragment slot selection ---
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
            // Multiply by this slot's biome weight (1.0 if single-biome).
            if (biome_count > 0) {
                int bi = slot_biome_index[i];
                w *= biome_w[bi];
            }
            if (w > 0.001) {
                ivec4 window = slot_windows[i];
                // Phase 6 follow-up: region-based variant pick + Heitz-Neyret
                // sampling. Salt with the slot's start index so each slot's
                // region pattern is independent of others.
                vec4 sib = w5_variety_sample_combined(
                    sibling_array, sibling_t_inv_array, has_t_inv,
                    tile_uv, world_xz,
                    window.x, window.y,
                    region_size_m, edge_blend_m,
                    world_seed, window.x, hn_enabled);
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
            // Per-mode slot mix strength (see macro_debug_mode comment).
            float slot_mix = 0.7;
            if (macro_debug_mode == 1) slot_mix = 1.0;       // pure slot, no fallback
            else if (macro_debug_mode == 2) slot_mix = 0.85; // 85% slot, 15% macro
            else if (macro_debug_mode == 3) slot_mix = 1.0;  // pure slot, macro off
            base = mix(base, slot_color, slot_mix);
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

    if (terrain_haze_enabled) {
        float haze_dist = distance(world_xz, ring_center_xz);
        float haze_t = smoothstep(terrain_haze_start_m,
            max(terrain_haze_end_m, terrain_haze_start_m + 0.01), haze_dist);
        base = mix(base, terrain_haze_color,
            haze_t * clamp(terrain_haze_strength, 0.0, 1.0));
    }

    ALBEDO = base;
    ROUGHNESS = 0.85;
    METALLIC = 0.0;
}
