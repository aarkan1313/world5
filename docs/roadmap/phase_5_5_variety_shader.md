# Phase 5.5 — Variety shader Layer 1 + Layer 2 (DONE 2026-05-17)

> Phase: 5.5 (sub-phase of Phase 5)
> Status: ✅ done
> Triggered by: Phase 4 left spec 24 Layer 1+2 deferred to Phase 5 once
> texture pipeline exists. User authoring textures offline in parallel
> + Phase 5.1 W4 module port is held (another chat working in W4) →
> shader work is the highest-leverage non-conflicting Phase 5 slice.

## What shipped

### Shader primitives (`engine/shaders/variety_common.gdshaderinc`)
- `w5_variety_sample_3tap(sampler2DArray, tile_uv, world_xz, start, count, blend_freq) -> vec4`
  — Heitz-Neyret 2018 simplified 3-tap stochastic UV blend
- `w5_detail_blend(sampler2DArray, tile_uv, world_xz, count, blend_freq) -> vec4`
  — 2-tap detail overlay blend; alpha-weighted

### Fragment-shader wiring (`engine/shaders/terrain_clipmap.gdshader`)
- New uniforms gating Layer 1 + Layer 2 paths
- Default-off via `has_siblings` / `has_detail` flags so walking demo
  preserves Phase 4.6 behavior until textures bind

### Binders (`MaterialPipeline.gd`)
- `bind_sibling_array()` — start/count window into per-slot variants
  inside a single Texture2DArray; clamps count to spec 24's 8-cap
- `bind_detail_array()` — per-biome detail overlay array binder
- Defaults wire `has_*` to false on `make_ring_material()`

### Tests (TDD, 22 new)
- 5 unit tests for Layer 1 + Layer 2 binders
  (`test_material_pipeline.gd`)
- 7 unit tests for shader-text primitive references
  (`test_variety_common_shader.gd`, NEW)
- 4 real-GPU integration tests
  (`test_variety_layers_real_device.gd`, NEW):
  - shader loads + parses
  - sibling-bound + detail-bound draws don't crash
  - sibling-bound render measurably differs from macro-only via
    per-channel color delta (proves Layer 1 actually samples on GPU)

## Verify

5/5 layers green stable in 47s:
- pytest 115 passed
- gut headless all passed
- gut_real_gpu all passed
- preflight 0 errors / 0 warnings
- capture all passed

## What did NOT ship

- Real ground textures (user authoring offline; Phase 5.4)
- Per-fragment slot selection (Phase 6 multi-biome widens this)
- Normal-map sibling array binder (deferable to Phase 5.4 when
  sibling normals actually arrive)
- Spec 25 `promote.py` (Phase 5.2 deliverable; Phase 5.1 port held)

## Investigation closed

Verify CLI `gut_actually_failed` parser confirmed working — injected
deliberate failure returns exit 2 + `[FAIL]` correctly.

## Coordination note

Phase 5.1 (W4 `tx_*.py` port) stays held pending the parallel chat's
W4 pipeline cleanup landing on origin/main. W4 is currently 312
commits ahead locally with dirty working tree in
`pipeline/textures/` + `pipeline/diversity_*.py`.

## Phase 5.5 extension (same-day, post initial commit)

After the shader landed, built out the runtime glue + the promote
tool while still avoiding W4-touching work. Now in:

- `DetailArray.gd` + `DetailTextureArray.gd` (Layer 2 manifest +
  Texture2DArray loader)
- `SiblingTextureArray.gd` (Layer 1 Texture2DArray loader; resolves
  biome-relative `source` per the canonical spec 24 schema)
- `pipeline/world5/textures/promote.py` (5.2; "single highest-leverage
  tooling deliverable" per plan 25 — net-new W5 tool, never existed
  in W4)
- `world_contract/materials_manifests.py` (5.3 preflight: warn on
  not-promoted-yet, error on broken-promote)
- 43+ new tests total across pytest + gut

Schema clarification: `source` is biome-relative (short form),
matching the plan's schema example. Corrected across all consumers.

## Next entry points

- Phase 5.4 (first biome) — when textures land; promote.py drives
  the file moves, preflight gates the result
- Phase 5.1 (W4 `tx_*.py` port) still held — parallel chat working
  in W4 pipeline. Re-evaluate next session once their changes land
- ~~TerrainWorld integration of SiblingTextureArray + DetailTextureArray
  loaders~~ ✅ shipped same-day (third pass): `_load_world_bundle()`
  now drives the loaders + binders end-to-end. 4 integration tests
  cover bound + unbound + missing-manifest paths. When textures land
  + promote.py runs, Layer 1+2 fire automatically with zero engine
  code changes.
