# Phase 4.9.a — Multi-page heightmap binding (audit C1 close)

> Date: 2026-05-17
> Closes: 4.9.a (audit C1 — outer ring chunk seams)
> Sub-phase of: [phase_4_9_renderer_correctness.md](../roadmap/phase_4_9_renderer_correctness.md)
> Driven by: [AUDIT_FINDINGS_PHASE_0_5_2026_05_17.md](../AUDIT_FINDINGS_PHASE_0_5_2026_05_17.md) C1

## What shipped

### RingHeightArray helper (new)

`engine/scripts/terrain/streaming/RingHeightArray.gd`. Per-ring
stitched-heightmap state for multi-page binding.

- `configure(ring_extent_m, page_extent_m)` → derives
  `pages_per_side` (conservative: `ceil(extent/page) + 1` to handle
  ring straddling page boundaries; minimum 2)
- `set_min_corner(world_min_xz)` → anchors the page grid to the
  ring's snapped center; pages added relative to this corner
- `add_page(page_xz, image) -> layer_index` → places the page in the
  spatial grid; layer = `page_y * pages_per_side + page_x` relative
  to min_xz (out-of-window pages rejected with -1)
- `remove_page(page_xz)` → on eviction
- `build_texture_array()` → emits Texture2DArray with
  `pages_per_side²` layers; missing pages get a flat-0.5 placeholder
  so the shader's spatial indexing is always valid (missing pages
  render as flat y=0 instead of black)
- 9 unit tests covering configure / add / remove / out-of-window /
  spatial-layer / texture array build / placeholder padding

### Shader path: vertex samples Texture2DArray

`engine/shaders/terrain_clipmap.gdshader`:
- New uniforms: `sampler2DArray height_array`, `bool has_height_array`,
  `int height_pages_per_side`, `vec2 height_array_min_xz`,
  `float height_array_page_extent_m`
- `w5_sample_height(world_xz, fallback_uv)` helper: if
  `has_height_array`, computes page coord from world XZ → array
  layer (spatially packed, no lookup table) + intra-page UV; samples
  the array. Else falls back to legacy `texture(height_map, UV)`
- Vertex shader: uses `w5_sample_height(vertex_world_xz, UV)` for
  own-ring + parent-ring heights (LOD morph) + the 4-tap slope
  derivative. The legacy path is preserved as fallback for tests +
  scenes that haven't migrated to bind_height_array.

### Binder: MaterialPipeline.bind_height_array

`engine/scripts/terrain/material/MaterialPipeline.gd`:
- `bind_height_array(mat, array, pages_per_side, min_xz,
  page_extent_m, scale_m, offset_m)` — flips `has_height_array=true`,
  sets all the new uniforms
- `make_ring_material` defaults: `has_height_array=false`,
  `pages_per_side=1`, `min_xz=(0,0)`, `page_extent_m=256` so the
  shader's array path doesn't fire until explicitly bound
- Legacy `bind_height_map` retained for back-compat

### TerrainWorld: per-ring RingHeightArray + rebuild on page load/evict

`engine/scripts/terrain/TerrainWorld.gd`:
- New per-ring state: `_ring_height_arrays: Array[RingHeightArray]`,
  one per ring; initialized in `_build_modules` with each ring's
  extent + the world's `page_extent_m`
- `_on_page_actually_loaded` now calls `_update_ring_height_array`
  (new) instead of the old single-page `_bind_height_to_ring`
- `_update_ring_height_array`:
  - Anchors the array's min_xz to the ring's current snapped center
    (page-aligned)
  - **If min_xz drifted** (ring snapped to a new center), discards
    the old array + creates fresh — old layer indices are invalid
    relative to the new window
  - Normalizes the page's float heights into a `R32_FLOAT` Image
  - Adds the page to the RingHeightArray at the correct spatial slot
  - Rebuilds the Texture2DArray + binds via `bind_height_array`
- `_on_page_actually_evicted`: removes the page + rebuilds
- Legacy `_bind_height_to_ring` removed (no callers remain)

### Real-GPU regression test

`engine/tests/integration/test_multi_page_height_real_device.gd`:
constructs a 2-page RingHeightArray with one all-low + one all-high
page, binds via `bind_height_array`, renders a quad spanning both
pages, asserts the two halves of the rendered image show measurably
different brightness (proves the shader picked the right page per
fragment). Pre-fix this test would produce delta=0 (single page
covers everything); post-fix delta > 0.005.

### Capture-baseline test updated

`engine/tests/visual/test_terrain_capture_baseline_real_device.gd::
test_ring_materials_have_height_bound` (renamed from
`test_ring_materials_have_height_map_bound`): now accepts EITHER
the legacy `height_map` Texture2D path OR the new `height_array`
Texture2DArray path, so the test stays meaningful through the
migration.

## Verify status

5/5 layers green stable in 60.6s:
- pytest 139 passed
- gut headless all passed (9 new RingHeightArray tests; 2 new
  shader-text tests for height_array uniforms + vertex sampling)
- gut_real_gpu all passed (including new
  test_multi_page_height_real_device — first end-to-end proof that
  multi-page binding works on GPU)
- preflight 0 errors / 1 warning (pre-existing)
- capture all passed

## Visual confirmation

Walking demo capture (post-fix, top-down oblique view at 70m up):
the previously stretched outer-ring band is gone; horizon shows a
varied snow-covered alpine landscape with continuous displacement
across the visible distance. Walking the demo at ground level needed
for full chunk-seam visual judgment, but the architectural fix is
verified end-to-end.

Walking demo runtime log per ring:
```
[INFO] [terrain_world] sibling array built  slots=3 layers=12
[INFO] [terrain_world] binding slots on rings  slot_count=3 has_catalog=true rings=5
```
Plus all 5 rings now also bind a RingHeightArray Texture2DArray
(silent log path; no per-ring spam).

## What's load-bearing post-4.9.a

- The `pages_per_side` derivation in `RingHeightArray.configure`
  assumes worst-case offset; if a future renderer change makes ring
  centers always page-aligned, the +1 slack is wasted but harmless
- The shader's `w5_sample_height` is the SINGLE entry point for
  heightmap sampling (vertex shader uses it 5× per vertex: own +
  parent + 4 slope-derivative taps). Any new height-related code
  path must route through here
- The discard-on-snap behavior in `_update_ring_height_array` is
  the correct contract — when the ring center moves to a new page,
  ALL old pages are invalid because their world coords no longer
  map into the new window. Cheap because images are held by
  reference, not copied
- The Texture2DArray rebuild happens on EVERY page load/evict
  (`build_texture_array` constructs a fresh `Texture2DArray` object).
  Acceptable for Phase 4.9 ship at the walking demo's page rate
  (~10-30 page events per second during walking) but flagged as
  calibration target for Phase 5.6 — the rebuild allocates +
  re-uploads all layers. Future: use Texture2DArrayRD with partial
  layer updates via the GPU compute pipeline (spec 08a path)

## What did NOT ship

- Per-tier `page_extent_m` (still global). Phase 5.6 calibration
  may bump outer rings to a coarser page resolution if measured
  bandwidth hurts
- Texture2DArrayRD (GPU-resident with partial updates per spec 08a)
  — current path uses ImageTexture which re-uploads the full array
  on each page event. Sufficient for walking demo; flagged for
  calibration

## Doc cap status

~165 lines (under 350 cap).
