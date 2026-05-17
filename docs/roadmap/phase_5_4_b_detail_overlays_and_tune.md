# Phase 5.4.b — Detail Overlays + Sibling Tune + Per-biome YAMLs

> Phase: 5.4.b (extension of Phase 5.4 first-biome work)
> Status: 🚧 opening 2026-05-17
> Triggered by:
> [AUDIT_FINDINGS_PHASE_0_5_2026_05_17.md](../AUDIT_FINDINGS_PHASE_0_5_2026_05_17.md)
> + user-flagged visual issues ("clear lines/transitions tile to
> tile, chunk to chunk strangeness")
> Unblocked by: Phase 5.1 module port (tx_pipeline + drivers in W5)
> + Phase 4.9 (renderer correctness fully closed)

## Why this exists

Phase 4.9 closed the renderer's structural bugs — multi-page
heightmap binding (C1), per-fragment slot selection (C2), macro
albedo (S2). Walking demo now renders the visible world as a real
alpine snowfield with slot textures appearing on slopes per the
catalog selectors. **What's left**: the eye-height visible repeat
+ the inactive Layer 2 detail-overlay system + the missing per-
biome authoring YAMLs.

These three pieces directly attack the user-flagged visual issues
that survive Phase 4.9:
- "tile to tile transitions" = audit C3 (`sibling_blend_freq` too low
  → 4 m tile reads 2-3× in a row before noise switches sibling)
- "chunk to chunk strangeness" (residual after 4.9.a) = audit S3
  (Layer 2 detail overlays inactive → no detail variation breaks up
  the macro-level repeating tile pattern)

## Sub-tasks

### 5.4.b.1 — Per-biome YAMLs (S7)

**Problem**: `pipeline/biomes/` doesn't exist in W5. `diversity.py`
expects `pipeline/biomes/<biome>.yaml` for any biome batch run, and
`tx_macro_terrain.py` has its `PURPOSE_PRESETS` dict hardcoded.
Fresh devs can't run a real biome authoring batch.

**Acceptance**:
- `pipeline/biomes/alpine.yaml` + `pipeline/biomes/forest.yaml`
  authored, schema-validated by `diversity.py`'s loader
- `tx_macro_terrain.py` reads alpine + forest purpose-preset palettes
  from the YAML instead of the hardcoded dict (single source of truth)
- `diversity.py --biome alpine` runs without erroring on missing config

**Approach**:
- Port W4's `pipeline/textures/biomes/alpine.yaml` + forest config
- Extract `PURPOSE_PRESETS["alpine"]` + `["forest"]` to YAML; leave
  the others in-code for now (they're unused in current scope)
- Update `tx_macro_terrain._load_purpose_preset(biome)` to try YAML
  first, fall back to hardcoded dict for the unmigrated biomes

**Effort**: 1 session

### 5.4.b.2 — sibling_blend_freq tune (C3)

**Problem**: `engine/shaders/terrain_clipmap.gdshader` defaults
`sibling_blend_freq = 0.10`. With 4 m tile_m, the noise wavelength is
40 m. Standing eye height looks 5-30 m ahead → same 4 m tile reads
2-3× in a row before the stochastic-UV noise switches sibling. Visible
texture repeat. Spec 24 Quality bar "no obvious texture repeats" NOT
met.

**Acceptance** (per spec 24 Quality bar):
- Walking demo at standing eye height shows no obvious 4 m tile repeat
  in the foreground 5-30 m range
- `sibling_blend_freq` is per-tier (`quality_tiers.json` knob) so high
  tier can afford finer-frequency variation than low tier
- A/B captures show before/after for the alpine demo at standing eye
  height — committed to `docs/captures/` (gitignored, but referenced
  in build note)

**Approach**:
- Bump `sibling_blend_freq` default from 0.10 → 0.30 (or higher;
  visually tune)
- Add `sibling_blend_freq` to `quality_tiers.json` per-tier (low 0.20,
  medium 0.30, high 0.40, ultra 0.40)
- Plumb through `TerrainWorld.gd` via `QualityTiers.current()` (or
  similar — check existing tier resolver pattern)
- If simple knob tune isn't enough, fall back: extend `w5_variety_sample_3tap`
  in `variety_common.gdshaderinc` from simplified 3-tap toward the
  full Heitz-Neyret derivative-blend (more samples, sharper noise)

**Effort**: 1-2 sessions (tune is fast; full HN is the fallback)

### 5.4.b.3 — Detail overlays authored (S3)

**Problem**: Walking demo `materials/biome_alpine/detail/` is gitkeeped
but empty. `detail_array.json` has `detail_tiles: []`. Spec 24 Layer 2
contract is inactive in render — no overlay variation breaks up the
macro pattern at eye height.

**Acceptance**:
- 5-7 alpine detail overlay tiles authored (e.g. wet stones, moss
  patches, snow drift, frost, lichen close-up, dust)
- `detail_array.json` populated with `detail_tiles` + per-slot
  `slot_blends` weights
- Tiles promoted via `promote.py --detail` to walking demo
- Walking demo shader Layer 2 binds → visible detail variation across
  the visible ground; no two 4 m tiles read identical at eye height

**Approach**:
- Run `python -m world5.textures.diversity --biome alpine --slot detail
  --batch-size 8` to produce candidates
- Review via `python -m world5.textures.review --biome alpine`
- Promote A-grade candidates via `promote.py` (may need a `--detail`
  flag added to handle the per-biome-rather-than-per-slot layout)
- Update walking_demo `detail_array.json` with selected tiles + per-slot
  blend weights (e.g. ground: 0.4 snow_drift, 0.2 frost; mid: 0.3 moss,
  0.2 lichen; rock: 0.3 dust)
- Capture A/B: before (no detail) vs after (5-7 detail tiles); confirm
  no regression in slot-selection visibility

**Effort**: 2-3 sessions (authoring + review + promote + tune)

## Close criteria

- All 3 sub-tasks shipped with acceptance criteria met
- 5/5 verify layers green
- Build note `phase_5_4_b_2026_05_XX.md` written
- ROADMAP + STATE updated (phase 5.4.b row, audit C3 + S3 + S7
  marked ✅)
- A/B captures (in build note) show the user-flagged tile-to-tile
  + chunk-to-chunk issues resolved
- Next phase: Phase 5.6 (calibration on real hardware) OR Phase 6
  (second biome — forest); user picks

## Sub-task order

`5.4.b.1` first (cheapest, unblocks future biome authoring runs)
→ `5.4.b.2` (cheap knob change; immediate visible win)
→ `5.4.b.3` (heaviest lift; benefits from tuned sibling blend
already present so the detail comparison is apples-to-apples)

## Doc cap status

~110 lines (under 350 cap).
