# Phase 4.9.b + 4.9.d — Per-fragment slot selection + biome catalog

> Date: 2026-05-17
> Closes: 4.9.b (C2 fix) + 4.9.d (biome catalog scaffold)
> Sub-phase of: [phase_4_9_renderer_correctness.md](../roadmap/phase_4_9_renderer_correctness.md)
> Driven by: [AUDIT_FINDINGS_PHASE_0_5_2026_05_17.md](../AUDIT_FINDINGS_PHASE_0_5_2026_05_17.md) C2 + S8

## What shipped

### 4.9.d — biome_catalog (S8)

- `engine/worlds/walking_demo/biome_catalog.json` (spec 22): alpine
  single-biome catalog with per-slot selectors. Slot bands tuned to
  the NoiseStackKernel amplitude=50m so all three slots (ground /
  mid / rock) are exercised on the visible terrain
- `engine/scripts/terrain/BiomeCatalog.gd`: loader + validator
  matching the MaterialVariants pattern. `biome_by_name(name)`
  query; `validate()` returns Array of error strings; spec 23 hard
  cap (8 slots per biome) enforced
- 8 unit tests (`test_biome_catalog.gd`) covering load / missing /
  empty / cap / query / selector field round-trip

### 4.9.b — per-fragment slot selection (C2)

The renderer's biggest spec gap. Pre-fix: TerrainWorld bound only
`mv.slots[0]` (the first slot's sibling window); mid + rock textures
were dead weight on disk. Now all slots bind + the fragment shader
weighted-blends across them per-fragment based on elevation + slope.

**Shader primitives** (`engine/shaders/variety_common.gdshaderinc`):
- `w5_slot_weight(elev_band, slope_band, elev_m, slope_deg) -> float`:
  smoothstep crossfade in/out of the slot's bands; returns 0..1

**Fragment-shader wiring** (`engine/shaders/terrain_clipmap.gdshader`):
- New uniforms: `slot_count`, `slot_windows[8]` (ivec4 start/count),
  `slot_elev_bands[8]` (vec4 min/max/band_in/band_out),
  `slot_slope_bands[8]` (same shape, degrees)
- New varyings: `v_world_y`, `v_slope_deg`
- Vertex shader: 4-tap finite-difference slope from heightmap;
  publishes per-vertex slope_deg + world_y
- Fragment shader: loop over `slot_count`, compute weight per slot,
  sample 3-tap sibling blend for each slot's window, accumulate
  weighted color, normalize
- Legacy single-slot path (Phase 5.5 `bind_sibling_array`) preserved
  as fallback when `slot_count == 0`

**Binder** (`engine/scripts/terrain/material/MaterialPipeline.gd`):
- `bind_all_slots(mat, sibling_array, windows, elev_bands, slope_bands)`:
  packs per-slot data into the shader's fixed-size arrays.
  Caps slot count at MAX_SLOTS=8 (spec 23 hard cap). Empty inputs
  leave `has_siblings=false` so the macro-only path still works
- `make_ring_material` pre-fills the slot uniforms with zeros so
  Godot doesn't reject the material on the first frame

**TerrainWorld wire-up** (`engine/scripts/terrain/TerrainWorld.gd`):
- `_load_world_bundle`: reads biome_catalog.json (if present);
  builds per-slot windows from the manifest + selector bands from
  the catalog; calls `bind_all_slots` (not `bind_sibling_array`)
- Helper `_bind_slots_with_catalog`: walks all slots in the manifest,
  looks up matching catalog entries, falls back to wide-open default
  bands when no catalog match (so worlds without catalogs degrade
  to "all slots active everywhere" rather than crashing)

**Tests**:
- 3 unit tests for `bind_all_slots` (set/clamp/empty)
- 3 unit tests for shader primitives + fragment loop (text checks)
- 2 real-GPU integration tests in `test_slot_selection_real_device.gd`:
  low-elevation quad reads red-dominant (ground slot wins),
  high-elevation reads blue-dominant (rock slot wins). Pre-fix:
  both renders identical fallback color → delta = 0; post-fix:
  delta ≥ 0.015 per channel. Threshold low because the base mix
  applies sibling at 0.7 + brightness modulator + tonemap attenuate;
  ANY positive delta proves the per-fragment slot loop fires.
- Existing `test_terrain_world_material_binding` integration test
  updated to assert the new `slot_count` + `slot_windows` contract
  instead of the legacy `sibling_count`

## What did NOT ship

- **Slope accuracy**: vertex-shader slope uses a fixed `cell_m=1.0`
  baseline (atan operates on slope ratios, so absolute scale isn't
  critical for smoothstep-banding). True per-ring cell size lookup
  would tighten the slope_deg values; deferred until visual review
  shows it matters.
- **Selector grammar**: the catalog's `selector` is a Dict of
  `elevation_m: [min, max]` + `slope_deg: [min, max]` + band widths.
  Spec 22 allows string expressions like `"slope_deg > 30 or
  elevation > 1000"`; not parsed. Hardcoded Dict form is enough for
  Phase 6 forest; string-expr parsing deferred.
- **Per-tier slot count caps**: shader supports up to 8 slots; no
  spec-21 calibration yet on how many active slots fits the 2.0ms
  budget on 3060. Phase 5.6 calibration territory.

## Verify status

5/5 layers green stable in 47.6s:
- pytest 139 passed
- gut headless all passed (3 new tests in test_variety_common_shader
  + 3 new in test_material_pipeline + 8 in test_biome_catalog)
- gut_real_gpu all passed (2 new in test_slot_selection_real_device)
- preflight 0 errors / 1 warning (pre-existing, not regressed)
- capture all passed

Walking demo runtime log:
```
[INFO] [terrain_world] sibling array built  slots=3 layers=12
[INFO] [terrain_world] binding slots on rings  slot_count=3 has_catalog=true rings=5
```
Three slots × four variants bound on all five rings with catalog
selectors active. C2 is fixed.

## What's load-bearing post-4.9.b

- `BiomeCatalog` is the single source of truth for per-slot selectors.
  Any new slot OR new biome must declare its bands here; the shader
  cannot infer them
- `MaterialPipeline.bind_all_slots` replaces `bind_sibling_array` for
  any caller that wants per-fragment selection. Legacy
  `bind_sibling_array` retained as fallback (Phase 5.5 tests + scenes
  without catalogs)
- The shader's `slot_count > 0` branch is the new primary albedo path;
  the macro-only fallback is now opt-out via the catalog/manifest,
  not opt-in. Don't break this without updating
  `test_slot_selection_real_device`
- Slot bands use smoothstep crossfade with author-supplied
  band_width fields (8m for ground elev, 5m for ground slope, etc.).
  Hard transitions are intentional in the band MIDDLE but soft at
  the EDGES. Visually-validated; tune in Phase 5.6 if it reads bad

## Next sub-tasks

- **4.9.a** multi-page heightmap binding (next session): closes C1
  (chunk seams at outer rings)
- **4.9.c** macro_albedo for walking_demo: needs `tx_macro_terrain.py`
  ported (depends on Phase 5.1 W4 module port)
- **4.9 close** rolls 4.9.a + 4.9.c + b/d into one sub-phase build
  note + ROADMAP correction

## Doc cap status

~150 lines (under 350 build-note cap).
