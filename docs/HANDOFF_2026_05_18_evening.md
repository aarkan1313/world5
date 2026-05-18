# W5 session handoff — 2026-05-18 (evening; Sprint 1+2 closed)

> For: the next session (you, fresh context). Read this first.
> Phase 6 + Sprint 1 + Sprint 2 of the DEM/runtime-kernels epic all
> shipped + pushed today. Sprint 3 is the next active work.

## Where we are in 60 seconds

Phase 6 closed earlier today (multi-biome rendering end-to-end,
W3 M11-derived triplanar+hex sampler, PBR maps wired, etc. — see
`build-notes/phase_6_close_2026_05_18.md` for the full story).

After Phase 6 close the user flagged: "world gen is bumpy noise, DEM
is super important." Spawned a spec-to-impl audit (results in commit
`3aef731`), wrote a 4-sprint plan
([docs/plans/19_DEM_AND_RUNTIME_KERNELS_PLAN.md](plans/19_DEM_AND_RUNTIME_KERNELS_PLAN.md)),
shipped sprints 1+2:

- **Sprint 1** (commit `3fb70fa`): runtime kernel chain execution.
  Walking demo's alpine `noise_stack + erosion` chain now runs at
  runtime via GPU compute instead of being ignored. Visible eroded
  terrain in capture render.
- **Sprint 2** (commit `b34cda8`): Python `DemFeatureKernel`
  reference (ridge/drainage/slope/aspect from real DEMs) + bundle DEM
  schema + `tx_dem_prepare` tool. Smoke-tested against W3's Cascades
  DEM.

Stats: 193 pytest (was 174 pre-Sprint-2), gut + preflight green.

## Commit graph since last handoff

```
b34cda8 Sprint 2: Python DemFeatureKernel + bundle DEM schema + tx_dem_prepare
3fb70fa Sprint 1 close: runtime kernel chain execution + visible erosion
d2c8371 Sprint 1.2a: KernelComposer.gd + TerrainPageRequest chain support
090af50 Sprint 1.1: ErosionKernel.gd config + GLSL hydraulic/thermal shaders
f711c93 plan: DEM-anchored procedural-infinite world gen (13-20 session epic)
3aef731 docs: spec status sweep — 22 shipped, 3 reviewed, 1 obsolete, 21 draft
fbafc34 Phase 6 close: multi-biome rendering end-to-end
```

Branch: `main`, pushed to `github.com/aarkan1313/world5.git`.

## Sprint 3 — next active work

**Goal**: walking demo's alpine biome uses a real Cascades DEM via
the chain (noise → DEM ridge_emphasis → erosion); forest stays pure
procedural to prove catalog mixing.

### 3.1 GDScript DemFeatureKernel.gd config class (1 session)

Mirror NoiseStackKernel.gd / ErosionKernel.gd pattern. Fields:
`dem_source: String, modes: PackedStringArray,
ridge_smooth_sigma_cells: float, seed: int`. Standard from_dict,
to_dict, validate, config_hash. Add as a 3rd kernel type in
`KernelComposer.gd` (`STAGE_DEM_FEATURE = "dem_feature"` +
`VALID_STAGE_TYPES` + `_build_config`). Unit tests for the config
class + composer dispatch.

### 3.2 Bundle DEM source loader (1 session)

Add `engine/scripts/terrain/kernels/DemSource.gd` — RefCounted that
reads `<bundle>/dem/<id>.json` sidecar + loads the GeoTIFF (or NPY)
into a `PackedFloat32Array` + 2D dims. TerrainWorld instantiates
these at bundle-load time and passes them to PageStreamingJob.
**Decision needed**: load entire DEM into RAM (~16 MB for
walking_demo's 2048² Cascades patch) vs. lazy/tile-based. RECOMMEND:
RAM-load for sprint 3 (small DEMs), tile-based streaming is sprint 4.

### 3.3 GLSL DEM feature compute shader (2-3 sessions)

`engine/shaders/terrain_dem_feature.glsl`. Inputs: source DEM
storage buffer + sample window. Outputs: feature buffer per mode.
For ridge_emphasis: gaussian blur pass + Laplacian pass. For
drainage_accumulation: D8 + iterative scatter (this one's tricky on
GPU — may need multi-pass or accept CPU bake for v1).
**Pragmatic alternative**: for sprint 3, CALL the Python ref via
subprocess at bundle-load time + bake the feature stacks to disk;
runtime samples from baked PNGs. Faster path to visible result.

### 3.4 GpuTerrainBackend chain dispatch for DEM (1 session)

Add `dem_feature` stage handling to `_generate_chain`. When a stage
is `dem_feature`, sample the DEM source's feature stack at the page's
world bounds + blend the result into the height field via the stage's
`strength` param. Cache key includes DEM source path hash.

### 3.5 Walking demo wire (1 session)

1. Run `tx_dem_prepare` on a Cascades excerpt:
   ```
   python -m world5.textures.tx_dem_prepare \
     --bundle engine/worlds/walking_demo \
     --source d:/assets/world3/opentopo/raw/cog/tcf_pnw_cascades_usa/COP30_*.tif \
     --id cascades \
     --bounds-world-xz <bounds in target CRS that actually overlap the source> \
     --crs EPSG:32610
   ```
   **Note**: smoke-test showed the tool works but bounds-world-xz must
   be in target CRS that overlaps source. Easier path: auto-derive
   bounds from the source if not specified. Add `--auto-bounds` flag.
2. Update `walking_demo/biome_catalog.json` alpine biome:
   ```json
   "kernel": {"type": "chain", "stages": [
     {"type": "noise_stack", "params": {...}},
     {"type": "dem_feature", "params": {"source": "cascades", "mode": "ridge_emphasis", "strength": 0.7}},
     {"type": "erosion", "params": {...}}
   ]}
   ```
3. Launch + capture. Alpine should show Mount Hood-style ridges.

### Sprint 3 close

- Visible: alpine = Cascades-anchored (real ridges visible from
  walking eye height); forest = pure procedural (smooth fBm).
- Build note: `docs/build-notes/sprint_3_dem_runtime_<date>.md`.

## Sprint 4 (after 3) — DEM virtual-texture streaming (4-6 sessions)

This is what makes "procedural infinite" real. See plan doc §"Sprint 4".

## Sprint 5 — spec gap closures (deferred)

`08a` GPU/CPU contract enforcement, `14` world contract validators
(biome/surface/kernel/tier/decoration), `18` hot-reload harness.

## Roadmap status

| Phase | Status |
|---|---|
| 0–4.11, 5.1, 5.4, 5.4.b (a+b), 5.5, 5.7.a/b/c | ✅ done |
| **6 (forest)** | **✅ closed 2026-05-18** |
| **DEM/runtime-kernels epic (5 sprints, 13-20 sessions)** | **🚧 sprints 1+2 done; 3 next** |
| 7+ (decoration, foliage, atmosphere, water, ...) | pending |

## Verify commands

```
python -m world5.verify --fastest    # pytest (~5s, 193 tests)
python -m world5.verify              # + gut + preflight (~8s)
python -m world5.verify --full       # + perf tests (~60s)
```

Currently green: 193 pytest, gut OK, preflight 0 errors / 1 warning
(STATE.md cap, unrelated).

## Demo launch + capture

```
# Interactive (you walk around):
C:/Godot/v4.6.2/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64.exe \
  --path demo demo/scenes/walking_demo.tscn

# Headless capture (PNG to user://_capture_walking_demo.png):
C:/Godot/v4.6.2/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64.exe \
  --display-driver windows --rendering-driver vulkan \
  --path demo res://scenes/walking_demo_capture.tscn
```

WalkCamera: WASD = walk, mouse = look, Shift = sprint, F = toggle
fly, ESC/Tab = release mouse. Camera starts at 2m walking height.

Expected launch log (Sprint 1 wiring):
```
[INFO ] [terrain_world] kernel chain loaded  biome=alpine stages=2
        chain_hash=02c01389d407
```

## Key paths

| Path | What |
|---|---|
| `docs/plans/19_DEM_AND_RUNTIME_KERNELS_PLAN.md` | The 4-sprint epic plan |
| `docs/build-notes/sprint_1_runtime_kernels_2026_05_18.md` | Sprint 1 close |
| `engine/scripts/terrain/kernels/ErosionKernel.gd` | New config class |
| `engine/scripts/terrain/kernels/KernelComposer.gd` | Chain orchestrator |
| `engine/scripts/terrain/backend/GpuTerrainBackend.gd` | Backend with chain dispatch (`_generate_chain`) |
| `engine/shaders/terrain_erosion.glsl` | Mei hydraulic compute |
| `engine/shaders/terrain_erosion_thermal.glsl` | Musgrave thermal compute |
| `pipeline/world5/kernels/dem_feature.py` | DEM feature extraction (Python ref) |
| `pipeline/world5/textures/tx_dem_prepare.py` | DEM prep tool |
| `engine/resources/schemas/kernels/dem_source.schema.json` | Bundle DEM sidecar schema |
| `engine/resources/schemas/kernels/kernel_chain.schema.json` | Chain spec (needs `dem_feature` added to VALID enum in sprint 3) |
| `d:/assets/world3/opentopo/raw/cog/tcf_pnw_cascades_usa/COP30_*.tif` | The Cascades DEM source for walking_demo |

## Known follow-ups (non-blocking)

1. **GPU↔Python parity test for erosion**: shader algorithm matches
   Python structurally but no tolerance-bound parity test yet.
   Erosion is chaotic enough that strict byte-parity is the wrong
   bar; need "drainage map correlates, mass preserved within tolerance"
   test. Sprint 1 carries this as deferred.
2. **Multi-biome height blend in composer**: today the runtime uses
   the FIRST biome's chain for the whole world (forest pixels render
   on alpine-eroded terrain). Spec 19 calls for per-(x,z) biome-
   weighted height. Big lift; sprint 3-adjacent.
3. **Per-stage perf measurement**: no frame-budget tracking yet on
   chain dispatch.
4. **tx_dem_prepare bounds auto-derivation**: tool requires bounds
   in target CRS that overlap source; easier UX = derive from source
   if not specified. Sprint 3.5 should add `--auto-bounds`.

## Open hazards

- **Gut flake** in `test_change_broadcast::test_job_dispatch_falls_back_to_async_without_scheduler`
  (line 104). Pre-existing in ChangeBroadcast subsystem; not touched
  by this session. Verify pipeline correctly classifies as
  non-blocking but visible in raw gut output. Track separately.
- **`.uid` regeneration**: when adding new `class_name` GDScript
  classes, Godot must scan to generate the `.uid` files OR other
  scripts fail to find the new class. Workaround: run
  `Godot ... --headless --path demo --import` once after each new
  class_name file is added. Sprint 3 will add `DemFeatureKernel.gd`
  — remember this.

## Memory entries to load on new session

Already saved + auto-loaded via MEMORY.md:

- `project_ethos_quality_first` — pillar order
- `w5_clipmap_w4_pitfalls_apply` — W4 PITFALLS lookup discipline
- `w5_perf_tier_and_bake_fallback` — two v1 runtime modes
- `verify_visual_output_yourself` — read PNGs before asking user
- `editor_launch_workflow` — print Godot command; don't background-launch
- `feedback_best_long_term_default` — default to architecturally-correct
- `feedback_dont_offer_session_end` — don't offer "or call it a session"
- `godot_binary_and_capture_invocation` — pinned Godot 4.6.2 path

## Doc cap status

~180 lines (under 200 cap).
