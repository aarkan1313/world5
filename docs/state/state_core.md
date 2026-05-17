# State: Tier 1 Core Systems

> Per-system state for Tier 1 core specs (19-34). Updated when systems
> ship.
>
> Cap: ≤ 300 lines (spec 05).
> Last updated: 2026-05-17.

## Tier 1 core systems (19-34)

| # | Spec | Status | Code | Notes |
|---|---|---|---|---|
| 19 | KERNEL_SYSTEM | draft | [NoiseStackKernel only](../../engine/scripts/terrain/kernels/NoiseStackKernel.gd) | **Phase 4.3 shipped NoiseStack config wrapper only**. **Audit (C4 2026-05-17)**: spec 19 v1 also requires ErosionKernel + DemFeatureKernel + KernelComposer; none built. Scheduled for **Phase 5.7 erosion sprint** (was unscheduled in original ROADMAP). Phase 10 water blocks on ErosionKernel's drainage_map + flow_direction + flow_accumulation outputs |
| 20 | TERRAIN_BACKEND | draft | [backend/](../../engine/scripts/terrain/backend/) | Phase 4.2 shipped: TerrainPageRequest/Result + GpuTerrainBackend (local RD per Phase 4.8) + TerrainBackendAdapter (bounded-concurrency window). Python ↔ GPU parity at 1e-4 m across 7 test cases including negative coords + seed extremes |
| 21 | TERRAIN_RENDERER | draft | [terrain/](../../engine/scripts/terrain/) + [PLAN](../plans/21_TERRAIN_RENDERER_PLAN.md) | Phase 4.4-4.6 shipped 12 modules + TerrainWorld composer (514 lines). 250+ tests. Walking demo runs standalone post 4.7+4.8 + renders displaced firn-snow alpine post 5.4. **Audit-found critical gaps (Phase 4.9 opening)**: (C1) outer rings bind one heightmap page each → chunk seams visible for rings 2-4 (510-2040m wide vs 256m page); (S1) spec 21 perf bar measured 4-6 ms on 5090 Laptop, 3060 extrapolation is **7-12× over 2.0 ms budget**. Phase 4.5 calibration claim "F2 engaged conservatively" is inverted — viability unproven |
| 22 | BIOME_CATALOG | draft | none | Hybrid auto-biome + splat overrides. Climate is per-XZ via climate_base + climate_rules (post-audit C5) |
| 23 | MATERIALS_PBR | draft | [MaterialPipeline + variants + array loaders](../../engine/scripts/terrain/material/) | Phase 4.4 shipped MaterialPipeline + MacroAlbedo + SurfaceSlotMask. Phase 5 entry shipped: on-disk layout for sibling sets (`<slot>_variants/`) + detail overlays (`detail/`) per amended spec; MaterialVariants.gd loader. Phase 5.5: DetailArray + SiblingTextureArray + DetailTextureArray runtime loaders. **Audit (C2 2026-05-17)**: per-fragment slot selection NEVER IMPLEMENTED — spec 23 §"Surface slot model" + spec 22 declare per-slot selectors (slope/elevation) but no shader code does selection; TerrainWorld binds only first slot. Mid + rock textures are dead weight. **Phase 4.9.b fixes** |
| 24 | GROUND_VARIETY | draft | [variety_common.gdshaderinc + terrain_clipmap.gdshader](../../engine/shaders/) | Phase 4: Layer 3 macro+world-noise shipped. Phase 5 entry: spec absorbed material_variants.json schema as Layer 1 contract. Phase 5.5: Layer 1 (`w5_variety_sample_3tap`) + Layer 2 (`w5_detail_blend`) shader primitives + MaterialPipeline binders + 22 tests. **Audit (C3 2026-05-17)**: `sibling_blend_freq=0.10` produces visible repeat at standing eye height (spec 24 Quality bar "no obvious repeat" NOT MET). **Audit (S3)**: walking_demo has detail_tiles=[] — Layer 2 inactive. Fixed in **Phase 5.4.b** (tune + detail authoring). Compositor (D) deferred to Phase 7+ |
| 25 | TEXTURE_PIPELINE | draft | [PLAN](../plans/25_TEXTURE_PIPELINE_PLAN.md) + [promote.py](../../pipeline/world5/textures/promote.py) | Phase 5 entry: spec amended with two-YAML layout, purpose-mode macro default, dev-only operator model. **Phase 5.5 expansion**: `promote.py` CLI (net-new W5 tool; copies candidates→world materials/ + atomically updates manifest with cap enforcement). Module port from W4 (`tx_*.py`) + first biome execution still pending |
| 26 | TRELLIS_3D_PIPELINE | draft | none | Review-per-subject carry-over from W4.1 (~120 COPY / 40 REGEN / 26 DROP estimate). GPU mutex coordination with spec 25 |
| 27 | LOD_BAKE | draft | none | 3 tiers (LOD0/1/2); impostors handle distant. Sync orphan-file preflight check (post-self-audit) |
| 28 | DECORATION | draft | none | Build fresh on Tier 0; ships R1-R9 + R13 + R14abc + R15 dither. `decoration_overrides.json` (renamed from `decoration_zones.json`). Foliage placement seam via `placement_exclusion` broadcast. Blob instance = 40 bytes |
| 29 | FOLIAGE | draft | none | Full system in v1 across 8 phases. Author estimate 25-35 sessions; audit re-estimate 60-100 sessions; both stand. Largest Tier 1 system |
| 30 | ATMOSPHERE | draft | none | Bruneton scattering required at high (0.5 ms); volumetric clouds tier-gated to ultra (default OFF at high). Fog override stack API (post-self-audit) |
| 31 | LIGHTING_GI | draft | none | SDFGI light variant at high (1.2 ms); full at ultra (3.0 ms); extended at cinematic (4.0 ms). Per-biome lighting + color grading LUTs |
| 32 | CAMERA_VIEW | draft | none | Single 3D walk camera. Depends on spec 20 backend for height (not spec 21 renderer) |
| 33 | NAV_EXPORT | draft | none | W4.1 carry-over manifest + per-chunk NPZ. `tier_at_bake` field; per-tier `nav_grid_n`. Depends on foliage + water + caves (post-audit M18) |
| 34 | AUDIO_HOOKS | draft | none | Engine ships ZERO audio assets. Canonical tag registry (post-self-audit S5) — spec 34 owns; world contract validates consumer's audio_bank covers emitted tags |

## What's load-bearing in this tier

These are the vertical core systems the demo + consumer game consume.
Build order (per ROADMAP Phase 4-9):
1. **Phase 4 — Terrain MVP**: Specs 19 + 20 + 21 + 22 + 23 against
   spec 15 renderer decision
2. **Phase 5 — Ground texture pipeline**: Spec 25
3. **Phase 6 — Second biome**: Validates biome-to-biome contract
4. **Phase 7 — Decoration**: Spec 28 (full sprint set R1-R15)
5. **Phase 8 — Foliage**: Spec 29 (8 phases A-H; largest sprint)
6. **Phase 9 — Atmosphere + Lighting**: Specs 30 + 31

Nav + camera + audio hooks are integration concerns that touch every
phase.

## Cross-spec contracts (post-self-audit alignment)

Verified consistent post-self-audit:
- Biome catalog ↔ decoration ↔ foliage: catalog declares palettes;
  decoration + foliage read them; placement coordinated via
  `placement_exclusion` broadcast metadata schema
- LOD bake ↔ decoration ↔ foliage ↔ impostors: LOD0/1/2 consumed by
  decoration + foliage; impostors swap at distance threshold
- Texture pipeline ↔ materials ↔ ground variety: 4 output modes
  enumerated; detail overlays serve weather + decoration + deformation
  + roads regardless of spec 24 architecture
- Climate (spec 22) ↔ weather (spec 36 in Tier 2): per-XZ climate
  drives per-XZ weather state

## Known open questions

- **Spec 21 renderer primitive**: ✅ resolved 2026-05-16 — clipmap
  committed in spec 15a (3 of 5 candidates eliminated by Godot 4.5
  capability survey)
- **Spec 24 variety architecture**: ✅ resolved 2026-05-17 — Layers
  1+2+3 committed (siblings + detail array + macro albedo). Compositor
  (D) deferred to Phase 7+
- **Foliage branch generator algorithm**: L-systems vs recursive vs
  space-colonization. Decided in foliage Phase B plan doc

## Doc cap status

- This file: ~80 lines (well under 300 cap)
- Per-spec entries will grow ~5-10 lines each as systems ship
- Phase 5 will append a Code column entry to row 25 once
  `pipeline/textures/` lights up
