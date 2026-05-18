# W5 session handoff — 2026-05-18 (late; Sprint 1+2+3 closed)

> For: the next session (you, fresh context). Read this first.
> Phase 6 + Sprints 1+2+3 of the DEM/runtime-kernels epic all shipped
> + pushed today. Sprint 4 (DEM tile streaming for infinite worlds)
> is the next active work.

## Where we are in 60 seconds

Phase 6 closed earlier today (multi-biome rendering end-to-end,
W3 M11-derived triplanar+hex sampler, PBR maps wired, etc. — see
`build-notes/phase_6_close_2026_05_18.md` for the full story).

After Phase 6 close the user flagged: "world gen is bumpy noise, DEM
is super important." Spawned a spec-to-impl audit (results in commit
`3aef731`), wrote a 4-sprint plan
([docs/plans/19_DEM_AND_RUNTIME_KERNELS_PLAN.md](plans/19_DEM_AND_RUNTIME_KERNELS_PLAN.md)),
shipped sprints 1+2+3:

- **Sprint 1** (commit `3fb70fa`): runtime kernel chain execution.
  Walking demo's alpine `noise_stack + erosion` chain runs at
  runtime via GPU compute instead of being ignored.
- **Sprint 2** (commit `b34cda8`): Python `DemFeatureKernel` ref +
  bundle DEM schema + `tx_dem_prepare` tool.
- **Sprint 3** (commit `9c61395`): GDScript `DemFeatureKernel` +
  `DemSource` bundle loader + bake-route DEM feature blending +
  walking_demo wired with Cascades DEM (Mount Hood foothills,
  Copernicus GLO-30). Alpine chain is now 3 stages:
  `noise_stack → dem_feature(cascades, ridge_emphasis) → erosion`.

Stats: 193 pytest (was 174 pre-Sprint-2), gut + preflight green.

## Commit graph since last handoff

```
9c61395 Sprint 3 close: DEM-anchored alpine biome end-to-end
f0ff2ac docs: post Sprint 1+2 handoff + STATE update
b34cda8 Sprint 2: Python DemFeatureKernel + bundle DEM schema + tx_dem_prepare
3fb70fa Sprint 1 close: runtime kernel chain execution + visible erosion
d2c8371 Sprint 1.2a: KernelComposer.gd + TerrainPageRequest chain support
090af50 Sprint 1.1: ErosionKernel.gd config + GLSL hydraulic/thermal shaders
f711c93 plan: DEM-anchored procedural-infinite world gen (13-20 session epic)
3aef731 docs: spec status sweep — 22 shipped, 3 reviewed, 1 obsolete, 21 draft
fbafc34 Phase 6 close: multi-biome rendering end-to-end
```

Branch: `main`, pushed to `github.com/aarkan1313/world5.git`.

## Sprint 4 — next active work

**Goal**: DEM virtual-texture streaming so the world is genuinely
"procedural infinite" — player can walk arbitrary distance, DEM tiles
stream in/out as needed, cache budget honored.

See `docs/plans/19_DEM_AND_RUNTIME_KERNELS_PLAN.md` §"Sprint 4" for
the full plan. Summary:

### 4.1 DEM tile pyramid format (1 session)

DEM source becomes a tile pyramid (mip levels of sub-tiles), not a
single 1024² PNG. `tx_dem_prepare` updated to emit
`dem/<id>/<mip>/<x>_<z>.tif` + `dem/<id>/index.json`. LOD selection:
far pages sample coarse mips; near pages sample full-res.

### 4.2 DEM tile streaming via AssetStream (2-3 sessions)

New `DemTileResidency` tracking which tiles overlap the active page
set. Tile load through AssetStream (spec 9); budget tracked via spec
10 StreamingBudget (new `dem_tiles` bucket). Eviction when no
resident page needs the tile. DemFeatureKernel reads from resident
tile cache; missing-tile fallback = coarse-mip placeholder.

### 4.3 Perf measurement + GPU pivot if needed (1-2 sessions)

Measure DEM feature blend time at typical pages-per-second. Today's
CPU bake-route is fine for small worlds; large-world streaming may
need GPU compute path. Target: > 80% cache hit rate after first orbit
of a region.

### Sprint 4 close

- Visible: player walks 10+ km in any direction with no stalls,
  no missing pages, no tile-edge seams.
- Build note: `docs/build-notes/sprint_4_dem_streaming_<date>.md`.

## Sprint 5 — spec gap closures (deferred)

`08a` GPU/CPU contract enforcement, `14` world contract validators
(biome/surface/kernel/tier/decoration), `18` hot-reload harness.

## Sprint 5 — spec gap closures (deferred)

`08a` GPU/CPU contract enforcement, `14` world contract validators
(biome/surface/kernel/tier/decoration), `18` hot-reload harness.

## Roadmap status

| Phase | Status |
|---|---|
| 0–4.11, 5.1, 5.4, 5.4.b (a+b), 5.5, 5.7.a/b/c | ✅ done |
| **6 (forest)** | **✅ closed 2026-05-18** |
| **DEM/runtime-kernels epic (5 sprints, 13-20 sessions)** | **🚧 sprints 1+2+3 done; 4 next** |
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
