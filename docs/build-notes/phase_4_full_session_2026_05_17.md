# Phase 4 Full Session — Build Note 2026-05-17

> Date: 2026-05-17 (single-day session)
> Closes: Phase 4 (terrain MVP) including 4.1-4.8 sub-phases
> Opens: Phase 5 (texture pipeline) — scaffold + spec amendments shipped

This session took Phase 4 from "specs unblocked" to "walking demo
runs standalone on Godot 4.6.2 with all 5 verify layers green". 16
commits, 2 outside-audit passes actioned, 2 standalone-run bugs
fixed post-close.

## Commits in chronological order

| Commit | Sub-phase | Summary |
|---|---|---|
| `d998d47` | 4.1 | Unblock specs 21+24 (clipmap committed); write 21_TERRAIN_RENDERER_PLAN.md |
| `3014c6c` | 4.2 | Terrain backend: GpuTerrainBackend + compute shader + Python parity (1e-4 m) |
| `6dbb7d7` | 4.3 | NoiseStackKernel.gd wrapper + kernel-from-request wire (NOT full kernel system) |
| `a619f62` | 4.4.a | renderer/ modules: ClipmapGeometry + ClipmapRing + ClipmapDispatch |
| `778b022` | 4.4.b | streaming/ modules: TerrainPageCache + ResidencyManager + PageStreamingJob |
| `ae77e67` | 4.4.c | material/ modules: SurfaceSlotMask + MacroAlbedo + MaterialPipeline + shaders |
| `5930048` | 4.4.d | TerrainWorld composer (430 lines) + diagnostics + smoke test |
| `a40723a` | 4.4-audit | 7 of 8 criticals + 9 of 16 significants actioned (3 parallel subagents) |
| `371461e` | infra | Upgrade Godot pin 4.5 → 4.6.2 stable mono |
| `2703771` | 4.4-audit2 | Outside-audit pass: 4 criticals + 2 significants (morph_factor wired, etc.) |
| `7810f1d` | 4.5 | Calibration sprint + 2nd outside-audit fixes |
| `b435640` | 4.5-close | quality_tiers.json + X_FRAME_BUDGET.md reflect calibration |
| `3f9b08c` | 4.6 | Walking demo + stationary baseline — Phase 4 closes |
| `8672006` | 4.6-review | Visual review found 2 standalone-run bugs |
| `bc8c954` | 4.7 | Autoload W5_ rename + W5Lookup helper + project.godot [autoload] |
| `049ceb8` | 4.8 | GpuTerrainBackend uses local RD (Godot 4.6 main-RD submit/sync rejected) |
| `baa71ac` | 5 entry | Spec 23/24/25 amendments + walking_demo bundle scaffold + MaterialVariants loader |

## What ships

**Phase 4 Code** (engine/scripts/terrain/):
- `backend/` (TerrainPageRequest, TerrainPageResult, GpuTerrainBackend (local RD), TerrainBackendAdapter)
- `kernels/` (NoiseStackKernel.gd — config wrapper only)
- `renderer/` (ClipmapGeometry, ClipmapRing, ClipmapDispatch)
- `streaming/` (TerrainPageCache, ResidencyManager, PageStreamingJob)
- `material/` (SurfaceSlotMask, MacroAlbedo, MaterialPipeline, MaterialVariants)
- `diagnostics/` (RingDebugOverlay, PageDebugProbes)
- `TerrainWorld.gd` (composer, 430 lines)
- engine/shaders/ (terrain_clipmap.gdshader, variety_common.gdshaderinc, terrain_page_gen.glsl)

**Phase 4 Tests**:
- pytest 115 passed
- gut headless ~50+ unit tests
- gut_real_gpu including stationary-baseline measurement
- capture layer (test_terrain_capture_baseline_real_device.gd)

**Phase 4 Calibration** (RTX 5090 Laptop, Godot 4.6.2):
| Rings | CPU avg | Stationary avg |
|---|---|---|
| 4 | 4.16 ms | 4.43 ms |
| 5 | 4.17 ms | 4.37 ms |
| 6 | 6.08 ms | 5.57 ms |
| 7 | 26.93 ms | 25.90 ms |
| 8 | 109.47 ms | — |

Stationary ≈ motion → bottleneck is rasterization, not streaming.
F2 engaged for 3060 via quality_tiers terrain_rings 3/4/5/6/7.

**Phase 4 Walking Demo**:
- `demo/scenes/walking_demo.tscn` runs standalone on Godot 4.6.2
- World bundle at `engine/worlds/walking_demo/`:
  - `kernels/noise_stack.json` (50m amp, 512m base wavelength)
  - `surface_slots.json` (alpine: ground/mid/rock)
  - `material_variants.json` (manifest scaffold; default-only)
  - `materials/biome_alpine/{ground,mid,rock}/` (empty, awaiting Phase 5)
  - `materials/biome_alpine/{ground,mid,rock}_variants/` (empty)
  - `materials/biome_alpine/detail/` (empty)
  - `materials/biome_alpine/detail_array.json` (empty overlay manifest)

**Phase 5 Entry**:
- Spec 25: two-YAML layout + purpose-mode macro default + dev-only operator
- Spec 24: material_variants.json schema absorbed as Layer 1 contract
- Spec 23: on-disk layout for sibling sets + detail overlays
- MaterialVariants.gd loader + 8 unit tests
- Plan doc at `docs/plans/25_TEXTURE_PIPELINE_PLAN.md` (~370 lines)

## What did NOT ship

- Real ground textures (user authoring offline)
- Layer 1+2 shader code (variety_common.gdshaderinc only has Layer 3
  primitives; 3-tap stochastic UV + detail array sampling are Phase 5.5)
- W4 texture pipeline module port to `pipeline/textures/` (Phase 5.1)
- ErosionKernel + KernelComposer (Phase 5+ or whenever 2nd kernel
  needed)
- Real RTX 3060 measurement (no hardware on dev rig)

## New pitfalls captured

- **meta-4**: Autoload name vs class_name global collision (Godot 4
  rejects). Fix: W5_ prefix on autoload + W5Lookup helper.
- **meta-5**: Main RenderingDevice rejects submit/sync in Godot 4.6.
  Fix: create_local_rendering_device() in GpuTerrainBackend.

## Audit history this session

- Phase 4.4 close: 3 parallel review subagents found 8C+16S+7M
- Outside audit #1 (after 4.4 fixes): 4C+6S+5M, all actioned
- Outside audit #2 (after 4.4.audit fixes): 1C+5S+4M, all actioned
- Phase 4.6 visual review: 2 standalone bugs found → Phase 4.7+4.8

## Verify status (latest)

5/5 layers green stable:
- pytest 115 passed
- gut headless all passed
- gut_real_gpu all passed (stationary baseline + parity tests)
- preflight 0 errors / 0 warnings
- capture all passed (3 baseline tests + walking-demo scene)

Wall-clock: ~42-46s for full verify (real-GPU + capture layers dominate).

## What's load-bearing post-Phase-4

- `W5Lookup.find(name)` is the SUT-side autoload accessor (test-
  override path first, autoload fallback). Any new system needing
  autoload state should use this helper, not raw `/root/X` lookups.
- `GpuTerrainBackend._ensure_rd()` lazy-creates a local RD per backend
  instance. Any new compute-heavy system (texture pipeline, future
  ErosionKernel runtime) needs the same pattern.
- `TerrainWorld` composer cap of 800 lines is informal but the file
  is at 430 — plenty of headroom for Phase 5 integration without
  refactoring out.
- `material_variants.json` schema in spec 24 is the canonical Layer 1
  contract — texture pipeline's `promote.py` (Phase 5.2) writes it.

## Next session entry points

In rough priority order:
1. **5.1 module port** from W4 `tx_*.py` files (mechanical; 1-2 sessions)
2. **5.4 first biome** when user's textures land (run diversity batch + promote)
3. **5.5 shader work** — extend variety_common.gdshaderinc with
   3-tap stochastic UV + detail array sampling
4. **Spec status sweep** — promote draft → reviewed across all 48
   specs in one pass (queued for Phase 5 close)

## Doc cap status

~165 lines (under 350 build-note cap; the line-count is justified
by 17 commits' coverage in one note).
