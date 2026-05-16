# State: Tier 2 World Systems

> Per-system state for Tier 2 world specs (35-41). Updated when systems
> ship.
>
> Cap: ≤ 300 lines (spec 05).
> Last updated: 2026-05-16.

## Tier 2 world systems (35-41)

| # | Spec | Status | Code | Notes |
|---|---|---|---|---|
| 35 | WATER | draft | none | All 4 phases in v1: lakes + rivers + coasts + underwater. Tiered reflection + per-body opt-in. Consumes spec 19 ErosionKernel drainage outputs for river masks (post-self-audit SA-C4.8) |
| 36 | WEATHER | draft | none | Visual only in v1: rain + snow + wind. Per-XZ climate from spec 22; rain + snow particle systems both always active, per-XZ intensity (post-self-audit SA-M4.10) |
| 37 | CAVES_INTERIORS | draft | none | Caves only in v1; buildings schema reserved. Per-chunk procedural cave geometry lives in world bundles at `worlds/<w>/cave_chunks/`; `engine/cave_meshes/` is for reusable cave-specific assets (stalactites, props) |
| 38 | RUNTIME_DEFORMATION | draft | none | Ephemeral; destroy assets in crater. GPU-direct compute shader (no per-deformation readback); throttled batched readback for gameplay. `query_deformations_in_rect` + `revert_deformation` API |
| 39 | PERSISTENCE_AND_AUTHOR_OVERRIDES | draft | none | Author overrides only (offline); JSON per system. Load order: water FIRST (climate needs it), then biome catalog, then other overrides. Consumer save-state hook is informative not normative |
| 40 | IMPOSTORS | draft | none | 2 crossed billboards from LOD0 render. Per-tier sizes: low 128 / medium 256 / high 512 / ultra 1024 / cinematic 2048. Frame budget: 0.2 ms at high (10k forest) |
| 41 | ROADS_PATHS | draft | none | Procedural A* + hand-authored overrides. Cost grid computed by pipeline from terrain backend capabilities (8m resolution, content-addressed). Frame budget: 0.1 ms at high |

## What's load-bearing in this tier

These are the "richness" systems that take W5 from "renders terrain"
to "feels like a world." Build order (per ROADMAP Phase 10-14):
- **Phase 10 — Water** (longest Tier 2 sprint; 4 phases)
- **Phase 11 — Weather**
- **Phase 12 — Caves**
- **Phase 13 — Runtime deformation**
- **Phase 14 — Persistence + author overrides**

Impostors (40) ship alongside foliage in Tier 1 (Phase 8) since
foliage Phase H consumes them. Roads (41) is its own sprint, scheduled
after persistence so it can use the override infrastructure.

## Cross-spec contracts (Tier 2 ↔ Tier 1)

- **Water (35) ↔ Erosion (19)**: water reads `drainage_map` +
  `flow_direction` + `flow_accumulation` outputs from ErosionKernel
- **Water (35) ↔ Atmosphere (30)**: water pushes underwater fog
  override via spec 30 `push_fog_override` stack API
- **Weather (36) ↔ Climate (22)**: per-XZ climate drives per-XZ weather
  state
- **Caves (37) ↔ Terrain backend (20)**: caves consume terrain backend
  contracts but don't add to frame budget (cost is in terrain +
  decoration)
- **Deformation (38) ↔ Decoration (28) + Foliage (29) + Nav (33)**:
  publishes `terrain_deformation` broadcast; subscribers use `job`
  dispatch for heavy cleanup (per spec 11 SA-S10 fix)
- **Roads (41) ↔ Decoration (28) + Foliage (29)**: publishes
  `path_zone` broadcast; subscribers exclude in width buffer

## Known open questions

- **Tier 2 ranking**: audit + self-audit acknowledged Tier 2 in full
  is ~60-120 sessions. Per user direction (2026-05-16), v1 scope
  stands. If any Tier 2 system slips to v0.2, water rivers/coasts
  and roads are the most-likely deferrals (per audit O2)
- **Cave entrance lighting handoff**: cave interiors use ambient-only
  lighting; per-biome lighting override hook (spec 31) untested at
  cave entrances

## Doc cap status

- This file: ~50 lines (well under 300 cap)
