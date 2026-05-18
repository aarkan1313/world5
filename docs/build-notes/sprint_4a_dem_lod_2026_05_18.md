# Sprint 4a close — DEM mip pyramid + per-ring LOD selection

> Plan: [docs/plans/19_DEM_AND_RUNTIME_KERNELS_PLAN.md](../plans/19_DEM_AND_RUNTIME_KERNELS_PLAN.md)
> Sprint: 4a of 4 (LOD-aware DEM sampling; 4b on-disk tile streaming deferred)
> Status: ✅ closed 2026-05-18
> Visible result: walking demo capture finally shows recognizable
> Mount Hood foothills (snow-capped peaks + alpine surface_slots
> responding to real elevation) — capture is "clearly real-world
> terrain" not "noise that's vaguely terrain-shaped."

## Summary

Sprint 4 of the plan was scoped as "DEM virtual-texture streaming"
(tile pyramid on disk + AssetStream-based residency + StreamingBudget
bucket). After implementing Sprints 1-3 and seeing the actual visible
issues, the architecturally-correct rescoping is **Sprint 4a (this
sprint)** — in-memory mip pyramid with per-ring LOD selection — and
**Sprint 4b (deferred)** — on-disk tile streaming for DEMs larger
than a few hundred MB.

Reasoning: walking_demo's DEM is 4 km × 4 km at 1024² (4 MB float
grid + 5 MB feature PNGs). Tile streaming for that is architectural
debt without payoff. The real visible payoff is LOD-aware sampling
(which 4a delivers) so adjacent rings sampling at matching mip
levels eliminate stitching cracks. When a consumer needs a DEM >
~256 MB, sprint 4b activates.

## What landed

### Mip pyramid construction
- **`DemSource._build_mip_pyramids`**: called once at bundle load.
  Builds in-memory mip pyramids for the base heights + every loaded
  feature mode. Each pyramid level is the prior level 2:1 box-
  averaged. Stops when grid drops below 8×8 (further downsampling
  discards too much information).
- **`mip_pyramids: Dictionary`**: mode name → Array of
  Dict{grid, rows, cols}, fine→coarse. `_HEIGHTS_KEY = "_heights"`
  for the base heights pyramid.
- **`mip_levels_for(mode)`**: introspection helper for tests/logs.

### LOD-aware sampling API
- **`sample_world_xz(x, z, cell_size_m_hint=0.0)`**: optional cell
  size hint picks the matching mip via `_pick_mip`. Default 0 = full
  resolution (back-compat).
- **`sample_feature_world_xz(mode, x, z, cell_size_m_hint=0.0)`**:
  same shape for feature sampling.
- **`_pick_mip(mode, hint)`**: walks pyramid fine→coarse, picks the
  COARSEST mip whose cell size is still ≤ hint. Near rings (small
  hint) sample fine mips; far rings (large hint) sample coarse mips.
  Adjacent rings sampling at hint=A and hint=2A pick mips one step
  apart, so shared cells get matching DEM values — fixes ring-
  stitching cracks.

### Backend integration
- **`GpuTerrainBackend._apply_dem_feature_blend`**: passes `cell`
  (= `request.extent_m / (grid_n - 1)`) as the LOD hint to all 3
  feature sampling sites. Each page picks the appropriate mip for
  its own resolution.

### Walking demo tuning
- **`biome_catalog.json` alpine chain**: bumped noise stage
  amplitude from 20m to 200m so outside-DEM areas have height range
  comparable to the DEM's ±400m. Eliminates the cliff at DEM-bounds
  fade-band. Reduced `dem_feature.strength` from 1.0 to 0.85 so the
  DEM still dominates but noise contributes some organic detail at
  the boundary.

### Tests
- 6 new `test_dem_source.gd` cases covering pyramid construction
  (level counts, threshold below which no downsample), LOD-aware
  sampling (zero hint = full res, large hint = coarsest mip),
  missing-feature graceful behavior.
- Refactored `_write_fixture` to use Dictionary opts instead of
  GDScript-incompatible Python-style kwargs. This silently fixed a
  pre-existing parse error that had caused the WHOLE
  `test_dem_source.gd` file to be skipped by gut since Sprint 3
  shipped — none of those 11 dem_source unit tests had been running.
  (Discovered while debugging the parse error in the new Sprint 4a
  tests; verify pipeline reports 11 newly-passing tests on top of
  the 6 sprint-4a additions.)

## Verification

- pytest: 195 passed.
- gut: passed (incl. 17 dem_source tests that are now actually
  executing — 11 pre-existing + 6 new).
- preflight: 0 errors / 1 warning (STATE.md cap).
- Runtime capture: walking_demo with DEM-anchored alpine shows
  snow-capped Mount Hood foothills clearly. Mip pyramid built with
  9 levels (1024² → 4²); page generation logs report `mip_levels=9`
  in the dem_source loaded line.

## What deferred for sprint 4b

- On-disk tile pyramid output (`dem/<id>/<mip>/<x>_<z>.tif`).
- AssetStream-based tile residency + streaming.
- StreamingBudget `dem_tiles` bucket + eviction.
- Tile-edge seam handling (`_soft_composite`-style overlap from W3).

These all activate when a consumer specifies a DEM larger than the
in-memory threshold (TBD ~256 MB). Walking demo + most v1 worlds fit
comfortably in RAM. Plan doc updated to reflect this split.

## Known follow-ups (non-blocking)

1. **DEM fade-band tuning**: 256m fade is hardcoded. Could be a
   per-DEM sidecar field so author can pick wider/sharper transitions.
2. **Noise+DEM amplitude matching**: walking_demo's bumped noise to
   200m by hand. Future polish: auto-set noise amplitude to match
   DEM's span/2 when a `dem_feature` stage is in the chain (avoid
   the manual tuning burden on authors).
3. **GPU compute path** for DEM blend. Today's CPU readback +
   per-pixel blend works fine for walking_demo's page rate; bigger
   worlds with higher page churn may need GPU port.

## Doc cap status

~115 lines (under 200 cap).
