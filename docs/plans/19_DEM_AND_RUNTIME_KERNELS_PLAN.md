# Plan: DEM-Anchored Procedural-Infinite World Generation

> Spec: [19_KERNEL_SYSTEM.md](../specs/19_KERNEL_SYSTEM.md)
> Also touches: [20_TERRAIN_BACKEND.md](../specs/20_TERRAIN_BACKEND.md),
> [22_BIOME_CATALOG.md](../specs/22_BIOME_CATALOG.md),
> [12_CONTENT_ADDRESSING.md](../specs/12_CONTENT_ADDRESSING.md),
> [09_ASYNC_ASSET_STREAMING.md](../specs/09_ASYNC_ASSET_STREAMING.md),
> [10_STREAMING_BUDGET.md](../specs/10_STREAMING_BUDGET.md)
> Phase: post-Phase-6 (world gen sprint epic)
> Created: 2026-05-18
> Status: in progress (Sprint 1 starting)
> Estimate: 13-20 sessions across 4 sprints

Per spec 02 lifecycle: spec → **plan** → implement. This plan locks
build order + per-sprint deliverables + verification approach for
porting the kernel system to GDScript runtime, building the DEM
feature kernel end-to-end, and shipping the infinite-world DEM
streaming layer. The spec says WHAT; this says HOW + WHEN.

## Why this plan exists

State at start (verified 2026-05-18):
- **Python**: `pipeline/world5/kernels/` has NoiseStack + Erosion +
  Composer + bake_page; all tested. Demonstrated end-to-end via
  `bake_walking_demo_erosion.py` — produces eroded PNGs but not used
  at runtime.
- **GDScript runtime**: `engine/scripts/terrain/kernels/` has ONLY
  `NoiseStackKernel.gd`. Live `TerrainWorld` reads
  `kernels/noise_stack.json` and runs pure fBm noise. The catalog's
  per-biome kernel chain is parsed but **ignored** — only the legacy
  single-noise path executes.
- **DEM kernel**: never built. Spec 19 lists `DemFeatureKernel` as
  sprint 3 (deferred).
- **W3 opentopo cache** (`d:/assets/world3/opentopo/`): 17 GB of real
  DEMs already processed (Cascades, Grand Canyon, Guadalupe, Great
  Plains). Includes derived layers (hillshade, slope_deg, roughness).
  Reusable as the DEM source for walking_demo.

Visible symptom: walking demo shows pure fBm noise as terrain — no
erosion, no real-geology anchoring, no per-biome height divergence.
"World gen is bumpy noise" was the user's exact concern.

## Reading order for the implementer

Before writing code, read in this order:
1. [19_KERNEL_SYSTEM.md](../specs/19_KERNEL_SYSTEM.md) — kernel
   contract, chain semantics, DemFeatureKernel intent
2. [20_TERRAIN_BACKEND.md](../specs/20_TERRAIN_BACKEND.md) — page
   contract the kernels feed
3. [22_BIOME_CATALOG.md](../specs/22_BIOME_CATALOG.md) — per-biome
   kernel chain schema + composer rules
4. [12_CONTENT_ADDRESSING.md](../specs/12_CONTENT_ADDRESSING.md) —
   cache key construction for bake outputs
5. [08a_GPU_CPU_CONTRACT.md](../specs/08a_GPU_CPU_CONTRACT.md) —
   compute dispatch + RID lifecycle rules
6. [pipeline/world5/kernels/](../../pipeline/world5/kernels/) — the
   Python reference implementations the GDScript ports must match
7. [d:/assets/world3/opentopo/](file:///d:/assets/world3/opentopo/) —
   the cached DEM source

## Architectural decisions baked into this plan

1. **Runtime kernel execution on GPU compute** where possible (spec 19:
   "GPU is the primary execution target"). CPU fallback for testing.
2. **DEM is a kernel like any other** — composer dispatches it as a
   chain stage. No special casing in the runtime loader.
3. **Content-addressed page caching per spec 12** — every page bake
   is cache-keyed; re-visits are free. DEM-source hash participates
   in the key so DEM swaps invalidate downstream bakes correctly.
4. **DEM tiles stream via AssetStream** (spec 9). Reuses existing
   infrastructure; no parallel streaming system.
5. **Per-biome catalog mixes DEM + non-DEM freely**. Walking demo
   ships alpine = DEM-anchored, forest = pure procedural to prove
   the mixing works.
6. **Bake outputs are heightmap pages + feature stacks**, not full
   meshes. The clipmap renderer (Phase 4-6) already consumes
   heightmap pages; we just give it pages that came from a richer
   kernel chain.

## Sprint 1 — Runtime kernel chain execution (3-5 sessions)

**Goal**: TerrainWorld can execute a catalog-declared kernel chain at
runtime. Walking demo's eroded alpine chain becomes visible.

### 1.1 GDScript ErosionKernel port (1-2 sessions)

- Port Python `pipeline/world5/kernels/erosion.py` to GDScript
  (`engine/scripts/terrain/kernels/ErosionKernel.gd`).
- Algorithm: Mei+Musgrave hydraulic erosion (water grid, sediment
  transport, deposit/dissolve, thermal). CPU first; GPU compute
  shader pass is sprint 1.3.
- TDD: parity test against Python reference. Same params → same
  height output to within float tolerance. Test fixture:
  `tests/integration/test_erosion_kernel_parity.gd` calling out to
  Python subprocess for ground truth.
- Public API:
  `ErosionKernel.apply(height_grid: PackedFloat32Array, grid_n: int, params: Dictionary, out_drainage: PackedFloat32Array = null) -> PackedFloat32Array`.

### 1.2 GDScript KernelComposer port (1-2 sessions)

- Port Python `pipeline/world5/kernels/composer.py` (`engine/scripts/terrain/kernels/KernelComposer.gd`).
- Responsibilities:
  - Parse catalog kernel chain (`{type, params}` list per biome).
  - Dispatch to NoiseStack, Erosion, (later) DemFeature.
  - Compute per-biome `biome_weights` softmax over `auto_biome_rules`.
  - Output combined `(height, biome_weights[N])` per page.
- TDD: parity test against Python `KernelComposer.bake_page`.

### 1.3 TerrainWorld loader switch (1-2 sessions)

- Replace `bundle_path + "kernels/noise_stack.json"` read with
  catalog kernel-chain dispatch.
- `GpuTerrainBackend.generate_page` calls `KernelComposer.bake_page`
  instead of bare NoiseStack.
- Cache integration: page output cached per spec 12 (key includes
  full chain hash, biome name, world origin, extent, grid, seed).
- Fall-back path: if a bundle has only `kernels/noise_stack.json` and
  no catalog kernel chain, run the legacy path (back-compat with
  pre-catalog bundles).
- Watch for the "Texture2DArray binding lifecycle" crash (other-chat
  territory). Run real-GPU GUT after every edit.

### Sprint 1 close

- Visible: walking demo terrain shows erosion (drainage networks,
  ridge breakdown). Compare against
  `engine/worlds/walking_demo/captures/erosion_comparison.png` — the
  live demo should match the bake.
- Verify: 174 pytest + gut + preflight + new parity tests green.
- Build note: `docs/build-notes/sprint_1_runtime_kernels_<date>.md`.

## Sprint 2 — Python DemFeatureKernel + bundle DEM schema (2-3 sessions)

**Goal**: Python reference for DEM feature extraction; bundle DEM
schema; tooling to validate + index a DEM source.

### 2.1 Python DemFeatureKernel (1-2 sessions)

- `pipeline/world5/kernels/dem_feature.py`.
- Inputs: DEM source manifest (path to GeoTIFF, CRS, bounds, resolution).
- Outputs (per page): a feature stack of named float fields:
  - `ridge_emphasis`: positive ridges via curvature
    (Laplacian or eigenvalue of Hessian)
  - `drainage_accumulation`: D8 flow accumulation log-scaled
  - `slope_deg`: per-cell slope from gradient magnitude
  - `aspect_deg`: per-cell aspect from gradient orientation
- Use `scipy.ndimage` + `rasterio` (already in W5 venv from W4 port).
- Each feature is a PackedFloat32 grid matching page extent.
- CPU-only at bake; cache results per spec 12.
- TDD: feature-output goldens for a small known-shape DEM patch
  (Grand Canyon tile from W3 cache).

### 2.2 Bundle DEM schema + tooling (1 session)

- Schema: `engine/resources/schemas/kernels/dem_source.schema.json`
  per spec 19's "DEM source handling defined upfront" §.
  ```json
  {
    "id": "cascades_north",
    "path": "dem/cascades_north.tif",
    "crs": "EPSG:32610",
    "bounds_world_xz": [-2048.0, -2048.0, 2048.0, 2048.0],
    "elevation_range_m": [400.0, 2800.0],
    "source_resolution_m": 10.0
  }
  ```
- World contract validator (spec 14): check schema, file exists,
  declared bounds match GeoTIFF metadata, elevation range plausible.
- New tool: `pipeline/world5/textures/tx_dem_prepare.py` —
  reproject DEM to world CRS, crop to bounds, build pyramid mips,
  emit `<bundle>/dem/<id>.tif` + sidecar JSON.

### Sprint 2 close

- Verify: parity tests vs golden patch green. Tool dry-runs on
  Cascades excerpt from W3 cache.
- No visible change in demo yet (waiting on sprint 3).

## Sprint 3 — GDScript DemFeatureKernel + catalog integration (3-4 sessions)

**Goal**: Runtime can sample DEM features at page-bake time. Catalog
can declare DEM kernel chain stages.

### 3.1 GDScript DemFeatureKernel runtime (2-3 sessions)

- `engine/scripts/terrain/kernels/DemFeatureKernel.gd`.
- Loads DEM tile(s) intersecting a page extent via AssetStream.
- Computes the same feature stack as the Python reference; cached
  per spec 12.
- CPU implementation first (TDD parity vs Python). GPU compute pass
  is sprint 4's perf concern (we'll measure CPU first; GPU only if
  bake time exceeds frame budget).
- Public API:
  `DemFeatureKernel.bake_features(world_xz_min: Vector2, world_xz_max: Vector2, grid_n: int, dem_source: Dictionary, modes: PackedStringArray) -> Dictionary[String, PackedFloat32Array]`.

### 3.2 Catalog DEM stage integration (1-2 sessions)

- Catalog kernel chain accepts `{type: "dem_feature", params: {source, mode, strength}}`.
- KernelComposer dispatches DEM stage; output feature stack feeds
  downstream stages (e.g. an erosion stage can blend
  `ridge_emphasis` into its initial height).
- Spec 19 amendment: document the chain-stage contract for DEM.

### 3.3 Walking_demo wiring (1 session, parallel)

- Copy a Cascades excerpt from W3 cache to
  `engine/worlds/walking_demo/dem/cascades_excerpt.tif` (~4 km extent).
- Update `biome_catalog.json` alpine kernel chain:
  ```json
  "kernel": {"type": "chain", "stages": [
    {"type": "noise_stack", "params": {...}},
    {"type": "dem_feature", "params": {"source": "cascades_excerpt", "mode": "ridge_emphasis", "strength": 0.7}},
    {"type": "erosion", "params": {...}}
  ]}
  ```
- Forest stays unchanged (pure noise stack) — proves catalog mixing.
- Visible: alpine biome now reads as Cascades-style ridges; forest
  reads as procedural noise. Side-by-side at the biome boundary.

### Sprint 3 close

- Verify: parity tests green. World contract validates the DEM source.
- Visible: walking_demo alpine = DEM-anchored, forest = procedural.
- Build note + commit + push.

## Sprint 4 — DEM virtual-texture streaming (4-6 sessions)

**Goal**: Procedural infinite world. Player can walk arbitrary
distance; DEM tiles stream in/out as needed; cache budget honored.

### 4.1 DEM tile pyramid format (1 session)

- DEM source becomes a tile pyramid (like map tiles): root mip is
  coarse full-extent, deeper mips are finer-resolution sub-tiles.
- `tx_dem_prepare` updated to emit pyramid mip directory:
  `dem/<id>/<mip>/<x>_<z>.tif` + `dem/<id>/index.json`.
- LOD selection: pages far from camera sample coarse mips; near
  pages sample full-resolution.

### 4.2 DEM tile streaming via AssetStream (2-3 sessions)

- New `DemTileResidency` class — tracks which DEM tiles overlap the
  current page residency set.
- Tile load through AssetStream (spec 9); budget tracked via spec 10
  StreamingBudget (new `dem_tiles` bucket).
- Eviction when tile is no longer required by any resident page.
- DemFeatureKernel reads from the resident tile cache; missing-tile
  fallback is a "low-detail placeholder" (Gaussian-smoothed coarse
  mip).

### 4.3 Perf measurement + GPU pivot if needed (1-2 sessions)

- Measure DEM feature bake time at typical pages-per-second.
- If CPU bake > 50% of page-generation budget at high tier: port
  the feature extraction to GPU compute (Laplacian + D8 are
  GPU-friendly).
- Cache rate target: > 80% hit rate after first orbit of a region.

### Sprint 4 close

- Verify: real-GPU perf test, run player walk loop of 5+ km. No
  stalls, no missing pages, no tile-edge seams.
- Build note + commit + push.

## Sprint 5 — Spec gap closures (post-DEM, 5-8 sessions)

Once world gen is solid, close the remaining spec gaps from the
2026-05-18 audit. NOT blocking on Sprint 1-4.

- **08a GPU/CPU contract enforcement** (1-2 sessions): static-
  analysis lint preventing RenderingDevice in Job._execute;
  StreamingBudget bucket validation; readback diagnostic; memory-
  stability test.
- **14 World contract validators** (3-4 sessions): biome_catalog
  schema, surface_slots, kernel params, per-tier PBR memory budget,
  decoration palette cross-ref.
- **18 Hot-reload harness** (1-2 sessions): automated Godot reload
  for shader edits.

## Risks + mitigations

1. **GPU page generation crash territory** (the prior other-chat
   native crash at 0x58). Mitigation: real-GPU GUT after every
   sprint 1 edit; small commits; rollback ready.
2. **Erosion runtime perf**. Mitigation: aggressive spec-12 caching;
   profile early in sprint 1; GPU port if needed.
3. **DEM tile-edge seams**. W3 had `_soft_composite` machinery for
   this. Mitigation: study + port if seams appear in sprint 4.
4. **DEM data licensing**. W3's opentopo cache is mixed (some free,
   some research-only). Mitigation: walking_demo uses USGS 10m data
   only (public-domain). Document source in bundle sidecar.
5. **Plan scope creep**. Mitigation: stop after each sprint, verify,
   commit, push. Don't bundle sprints. Don't start sprint 5 until
   sprints 1-4 are visible-and-shipping.

## Acceptance criteria for the epic

- Walking demo alpine biome reads as real Cascades-style geology
  (ridges, drainage, feel of "somewhere on Earth").
- Walking demo forest stays pure-procedural; biome boundary is a
  natural blend.
- Player can walk 10+ km in any direction. No stalls. No missing
  pages.
- Per-biome kernel chains independently composable in the catalog.
- DEM kernel is a first-class kernel — same lifecycle, same cache,
  same composer dispatch as any other kernel.
- All 174 existing tests still green + new parity tests for each
  GDScript kernel port.

## Doc cap status

~290 lines (under 350 cap).
