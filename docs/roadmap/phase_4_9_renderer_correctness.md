# Phase 4.9 — Renderer Correctness (audit-driven)

> Phase: 4.9 (re-opening Phase 4 to close gaps the audit found)
> Status: 🚧 opening 2026-05-17
> Triggered by:
> [AUDIT_FINDINGS_PHASE_0_5_2026_05_17.md](../AUDIT_FINDINGS_PHASE_0_5_2026_05_17.md)

## Why this exists

Walking demo Phase 5.4 alpine render exposed three critical bugs
that violate specs 21+23+24. The bugs aren't regressions — they
were shipped baked into Phase 4 closure. The audit (charter +
4-subagent findings) confirmed phases 4 / 4.5 / 4.6 / 5.4 / 5.5
all claim ✅ done while shipping unfinished core systems. This
sub-phase closes the critical gaps before Phase 5.6 calibration or
Phase 6 forest can start meaningfully.

## Sub-tasks

### 4.9.a — Multi-page heightmap binding (C1)

**Problem**: `engine/scripts/terrain/TerrainWorld.gd:444-452` binds
one heightmap page per ring (covers ring's `snapped_center` only).
Walking demo defaults: rings 2-4 are 510m / 1020m / 2040m wide; one
256m page can't cover them. The texture stretches at the edges,
producing visible chunk seams where stretched samples meet.

**Acceptance** (per spec 21 hardened Quality bar):
- At any LOD ring, heightmap sampled at the visible mesh boundary
  matches the heightmap an adjacent ring (or adjacent page within
  the same ring) samples at the same world XZ
- Rings wider than `page_extent_m` bind multiple pages and sample
  the right page per fragment via world XZ
- Regression guard `test_ring_heightmap_continuity_at_page_boundary`
  in `engine/tests/visual/test_terrain_capture_baseline_real_device.gd`

**Approach** (cheapest path; defer alternatives until measured):
- Per-ring heightmap stored as a `Texture2DArray` indexed by page
- Vertex shader: per-vertex compute world XZ → which page layer →
  sample that layer's UV
- TerrainWorld binds one Texture2DArray per ring (vs current single
  Texture2D); array grows as residency adds pages, shrinks as
  evictions remove them
- Per-ring `page_table` (PackedInt32Array or vec4 array uniform)
  maps (world XZ page coord) → array layer index; updated on
  page_actually_loaded / page_actually_evicted

**Effort**: 1 session. Most of the wiring exists; the missing piece
is per-fragment page lookup.

### 4.9.b — Per-fragment slot selection (C2)

**Problem**: spec 23 §"Surface slot model" + spec 22 declare per-slot
selectors (`slope_deg`, `elevation`) that should drive per-fragment
slot weight. Zero shader code does selection. TerrainWorld binds
only `mv.slots[0]`. Mid + rock textures are dead weight.

**Acceptance** (per spec 23 hardened §"Surface slot model"):
1. Every (biome, slot) declared in `surface_slots.json` has its
   sibling Texture2DArray window bound on every ring material
2. Fragment shader computes per-fragment slot weight from
   `slope_deg` (from heightmap derivatives) + `elevation` (vertex Y)
3. Final albedo = weighted sum across active slots; weights sum to
   1.0 per fragment
4. Single-slot bundles collapse to the existing single-slot binding
   path; selector machinery is opt-in via slot count > 1

**Approach**:
- Sibling array becomes the union across all slots (already happens
  in `SiblingTextureArray.build`); pass full `(start, count)` table
  to shader instead of just first
- Add shader uniform: `slot_count: int`, `slot_starts[MAX_SLOTS]`,
  `slot_counts[MAX_SLOTS]`, `slot_elevation_bands[MAX_SLOTS]`,
  `slot_slope_bands[MAX_SLOTS]`. MAX_SLOTS = 8 (spec 23 hard cap)
- Add shader function `w5_slot_weights(world_y, slope_deg)` that
  returns N weights (one per active slot) normalized to 1.0
- Fragment loops over active slots, samples `w5_variety_sample_3tap`
  for each, accumulates weighted sum
- `slope_deg` derived from heightmap finite differences in vertex
  shader; passed to fragment via varying
- Selector parsing (the `"elevation < 800"` string) deferred — for
  Phase 4.9 hardcode the alpine bands; spec 22 selector grammar is
  Phase 6 work

**Effort**: 2-3 sessions. Real shader work + needs real-GPU visual
regression test.

### 4.9.c — Macro albedo for walking_demo (S2)

**Problem**: walking_demo logs "bundle missing macro_albedo.json"
every load. Far-field uses fallback_color instead of biome-matched
gradient. Spec 23 says "REQUIRED for any world configured with
visibility_ship_distance_m > 2km" (conditional but recommended).

**Approach** (depends on 5.1 module port):
- Run `python -m world5.textures.macro_terrain --biome alpine
  --purpose-candidates --promote-purpose` against walking_demo
- Outputs `engine/worlds/walking_demo/macro_albedo.png` +
  `macro_albedo.json` (world AABB mapping)
- MacroAlbedo loader already exists; should just work post-promote
- Update `.gitignore` if needed (macro_albedo PNG should probably be
  tracked since it's small + per-world; OR gitignored per same
  policy as the slot textures — decide)

**Effort**: 1 session if 5.1 module port lands first; 0.5 session if
we hand-author a placeholder PNG instead

**Blocker**: needs `tx_macro_terrain.py` ported (currently W4 only)

### 4.9.d — biome_catalog.json for walking_demo (S8)

**Problem**: walking_demo has no `biome_catalog.json`. Spec 22 +
spec 14 world contract require one per world.

**Approach**:
- Author single-biome catalog for alpine; declares slot list +
  selectors (matches the surface_slots.json content + adds the
  `selector` strings)
- TerrainWorld load: read catalog → drives 4.9.b's slot bands
- World contract preflight: add a catalog check

**Effort**: 0.5 session

## Verify gates

- 5/5 verify layers green stable after each sub-task
- Visual capture of walking_demo after 4.9.a + 4.9.b: chunk seams
  gone, mid/rock textures visible on slopes/cliffs
- Per-fragment slot test in `test_terrain_capture_baseline` asserts
  > 0 fragments use rock slot at high elevation, > 0 use ground at
  low elevation, given a heightmap with both extremes

## Sequence

1. 4.9.d biome_catalog (0.5 session) — unblocks 4.9.b parsing
2. 4.9.b per-fragment slot selection (2-3 sessions) — fixes the most
   visible bug (dead textures)
3. 4.9.a multi-page binding (1 session) — fixes chunk seams
4. 4.9.c macro_albedo (0.5-1 session; depends on 5.1 port) — far-field
   completion

C3 (sibling_blend_freq tune) is folded into Phase 5.6 calibration
since it needs the textures and real eye-height walking to tune.

## Open questions

- **MAX_SLOTS = 8 enough?** Spec 23 says yes (shader cap). Walking
  demo uses 3. Phase 6 forest also 3. No biome currently exceeds 8.
- **Should slot blending crossfade across elevation bands?** Yes —
  hard slot transitions look bad. Use smoothstep over a per-slot
  `band_width` parameter. Default 50m (alpine band ~800-850m
  transitions across 50m).
- **Per-fragment selector evaluation cost?** 8 slots × (1 slope
  smoothstep + 1 elev smoothstep + 1 noise) ≈ 24 ALU ops. Trivial.

## Doc cap status

~190 lines (under 350 cap).
