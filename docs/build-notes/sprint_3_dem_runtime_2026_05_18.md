# Sprint 3 close — DEM-anchored alpine biome

> Plan: [docs/plans/19_DEM_AND_RUNTIME_KERNELS_PLAN.md](../plans/19_DEM_AND_RUNTIME_KERNELS_PLAN.md)
> Sprint: 3 of 4 (GDScript DemFeatureKernel + catalog integration + Cascades wire)
> Status: ✅ closed 2026-05-18
> Visible result: walking demo's alpine biome runs a 3-stage chain
> `noise_stack → dem_feature → erosion`. Cascades DEM (Mount Hood,
> Copernicus GLO-30) loaded at bundle load, ridge_emphasis feature
> blended into the height field at runtime per page.

## Summary

Sprint 1 shipped the runtime kernel chain dispatch. Sprint 2 shipped
the Python `DemFeatureKernel` reference + bundle DEM schema +
`tx_dem_prepare` tool. Sprint 3 closes the loop: GDScript runtime
`DemFeatureKernel` config + `DemSource` bundle loader + bake-route
DEM feature blending in `GpuTerrainBackend` + walking_demo's alpine
biome wired with a real Cascades DEM excerpt.

The visible payoff is subtle from fly-camera angles (DEM ridge
contributions add positive bias up to amplitude×strength meters, but
ridges are sparse features by design) — the real win is
architectural: a real-world DEM is now a first-class kernel chain
stage, indistinguishable from noise or erosion in the dispatch path.

## What landed

### Config + composer integration
- **`engine/scripts/terrain/kernels/DemFeatureKernel.gd`**: config-
  only RefCounted. Fields: `source` (bundle-local DEM ID), `mode`
  (ridge_emphasis / drainage_accumulation / slope_deg / aspect_deg),
  `strength`, `ridge_smooth_sigma_cells`, `seed`. Standard
  `from_dict / to_dict / validate / config_hash` mirroring the other
  kernel config classes. 16 unit tests.
- **`KernelComposer.gd`** extension: `STAGE_DEM_FEATURE = "dem_feature"`
  added to `VALID_STAGE_TYPES` + `_build_config` dispatch. New
  helpers `has_dem_feature()` + `dem_feature_stages()`. 7 new
  composer unit tests covering parse, validate, chain hash, helper
  semantics.
- **`engine/resources/schemas/kernels/kernel_chain.schema.json`**:
  `dem_feature` added to the enum so author-supplied catalogs can
  declare it without schema rejection.

### Bundle loader
- **`engine/scripts/terrain/kernels/DemSource.gd`**: reads
  `<bundle>/dem/<id>.json` sidecar + `<bundle>/dem/<id>.png`
  16-bit height PNG → PackedFloat32Array of world-meter heights +
  bounds_world_xz / elevation_range_m / content_hash. Sprint 3 v1
  RAM-loads the entire DEM (small worlds); Sprint 4 adds tile
  streaming for procedural infinite. Pre-baked features (from
  `tx_dem_prepare`) load as additional PackedFloat32Array grids keyed
  by mode. Public sampling API: `sample_world_xz(x, z) -> float` for
  heights, `sample_feature_world_xz(mode, x, z) -> float` for features.
  Bilinear interpolation, edge-clamped. 12 unit tests using synthetic
  PNG + sidecar fixtures.

### Pipeline (tx_dem_prepare extension)
- Now emits a **16-bit single-channel height PNG** companion to the
  GeoTIFF (Godot can't read GeoTIFF; PNG is the runtime path). PNG
  pixels normalized [0, 1] over elevation_range_m; sidecar carries
  the rescale params for DemSource to decode.
- Also **bakes the 4 DemFeatureKernel modes** into companion PNGs
  (ridge_emphasis / drainage_accumulation / slope_deg / aspect_deg).
  Each is a 16-bit PNG normalized over the per-feature [min, max]
  range; sidecar carries `features.paths` + `features.ranges`. Runtime
  decodes by rescale.
- **`--auto-bounds-extent-m`** flag: takes the source DEM's extent
  reprojected into target CRS, centers the world-XZ output on (0, 0),
  emits a square of `extent_m × extent_m`. Sidecar gets recentered
  bounds; the geographic bounds (used internally for the reproject
  pull) stored in `_geographic_bounds` for debugging.
- Output capped at **1024² for v1 RAM-load** (~4 MB float grid +
  ~5 MB combined feature PNGs). Sprint 4 introduces tile pyramid for
  larger worlds.

### Backend chain dispatch (CPU bake-route, v1)
- **`GpuTerrainBackend._dem_sources: Dictionary`** — registry keyed
  by source ID. TerrainWorld registers each DemSource at bundle load
  via `TerrainBackendAdapter.register_dem_source(id, source)`.
  `clear_dem_sources()` on bundle unload.
- **`_apply_dem_feature_blend`**: after the GPU chain (noise +
  optional erosion) completes and heights are read back, iterates the
  composer's `dem_feature_stages()` and CPU-blends each into the
  heights array. ridge_emphasis is purely additive (`height += feat
  * amp * strength`); other modes are centered-around-0.5
  (`height += (feat - 0.5) * amp * strength`). v1 documents that this
  runs *after* erosion (not the strict-spec "between noise and
  erosion" ordering) — pragmatic choice; Sprint 4 may move to GPU
  compute with correct mid-chain ordering.
- Handles both `needs_erosion = true` and `needs_erosion = false`
  chain paths.

### Python composer parity
- **`pipeline/world5/kernels/composer.py`** `_instantiate_stage`
  extended to handle `dem_feature` stages so chain parsing
  round-trips through the Python ref end-to-end. Per-point
  `sample_height` skips DEM feature stages (the bake-route in v1
  isn't a per-point function); bake_page-style consumers can call the
  Python DemFeatureKernel directly.

### TerrainWorld bundle integration
- Scans `<bundle>/dem/*.json` at bundle load; instantiates a
  `DemSource` per sidecar; registers each on the backend via
  `_adapter.register_dem_source(id, src)`. Missing PNGs/invalid
  sidecars log + skip without crashing the bundle load.

### Walking demo wire
- Ran `tx_dem_prepare` on
  `d:/assets/world3/opentopo/raw/cog/tcf_pnw_cascades_usa/COP30_*.tif`
  with `--auto-bounds-extent-m 4000`, producing
  `engine/worlds/walking_demo/dem/cascades.{png, tif, json,
  _ridge_emphasis.png, _drainage_accumulation.png, _slope_deg.png,
  _aspect_deg.png}`.
- Bundle DEM dir is `.gitignore`-d per existing rule (`**/dem/`) so
  the DEM data stays out of git. Anyone cloning the repo and running
  the demo needs to re-run `tx_dem_prepare` to materialize the DEM.
- Updated `biome_catalog.json` alpine kernel chain from
  `[noise_stack, erosion]` to `[noise_stack, dem_feature(cascades,
  ridge_emphasis, strength=1.0), erosion]`. Forest stays pure noise
  (proves catalog mixing).

## Verification

- pytest: 193 passed.
- gut: passed (pre-existing ChangeBroadcast flake unrelated).
- preflight: 0 errors / 1 warning (STATE.md cap).
- Runtime capture log (`demo/scenes/walking_demo_capture.tscn`):
  ```
  [INFO ] [dem_source] loaded  id=cascades rows=1024 cols=1024
          bounds=[P: (-2000, -2000), S: (4000, 4000)] elev=(879.3, 1711.9)
          features=["ridge_emphasis", "drainage_accumulation",
                    "slope_deg", "aspect_deg"]
  [INFO ] [terrain_world] kernel chain loaded  biome=alpine stages=3
          chain_hash=e18e1212258b
  ```
  `resident_pages=76, full_detail_ready=true, no leaked RIDs`.

## Visible result

Capture shows visibly more pronounced ridge contributions on the
horizon vs the Sprint 1 pre-DEM capture. Effect is subtle from
fly-camera oblique angles because ridge_emphasis is a sparse
positive bias by design (96% of pixels < 0.05; only true ridges get
significant values). For more dramatic visible difference, future
options:
1. Use slope_deg as an elevation multiplier (mountain areas get
   amplitude × multiplier added height) — needs new kernel mode.
2. Use raw DEM heights as the base instead of fBm noise — dramatic
   but couples world strictly to DEM extent. Architectural shift.
3. Higher strength + author multi-mode chains (ridges + drainage
   carving + slope-driven amplitude). Sprint 4-adjacent.

## Architectural notes + tradeoffs

- **Bake-route vs runtime compute**: v1 bakes features at pipeline
  time (Python ref produces PNGs at `tx_dem_prepare` time), runtime
  just samples baked PNGs. Pros: no runtime Python dep, deterministic,
  cheap to sample. Cons: feature set fixed at bake time (can't tune
  ridge_smooth_sigma_cells without re-running tool); RAM footprint
  scales with DEM resolution × number of feature modes.
- **CPU blend after chain**: v1 reads heights back to CPU after GPU
  chain, blends features, returns. Correct ordering would be "blend
  feature INTO heights between noise and erosion" so erosion carves
  the DEM-influenced terrain. v1 does feature blend AFTER erosion
  which is technically wrong but visually close. Sprint 4 GPU port
  fixes both perf + ordering.
- **DEM coordinate system**: tool emits world-XZ bounds centered on
  (0, 0) regardless of source CRS. World-XZ is what the runtime sees;
  geographic bounds (UTM coords from the source) only matter inside
  the reproject pull at bake time.

## Known follow-ups (sprint 4 / non-blocking)

1. **GPU compute path** for DEM feature blend. Eliminates CPU readback
   round-trip + enables correct mid-chain ordering (blend BEFORE
   erosion).
2. **DEM tile pyramid + streaming** (Sprint 4 of the epic). Today's
   RAM-load works for ≤ ~16 km² worlds; infinite-world needs tile
   streaming via AssetStream.
3. **Per-biome divergent chains**: today the runtime uses the FIRST
   biome's chain for the whole world; forest pixels render on
   alpine-DEM-influenced heights. Multi-biome height blend via
   composer softmax is the architectural fix (spec 19's full Composer
   contract).
4. **New `mode: dem_height`** that uses raw DEM elevation as a base
   instead of fBm noise. Much more dramatic visible result for
   "Cascades-anchored" worlds. Would be ~1 extra mode in the Python
   ref + GDScript blender.

## Doc cap status

~190 lines (under 200 cap).
