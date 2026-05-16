# Spec: Lighting + GI

> Status: draft
> Tier: 1 (core)
> Depends on: 13_QUALITY_TIERS, 22_BIOME_CATALOG, 30_ATMOSPHERE,
> 21_TERRAIN_RENDERER
> Consumed by: terrain renderer, decoration, foliage, every visible
> system

## Purpose

W5's lighting backbone: per-quality-tier GI strategy, per-biome
lighting tuning, per-biome + per-time-of-day color grading, shadow
strategy.

W4.1 shipped a `LightingRecipeController` with 3 recipes (baseline,
shadow_near, sdfgi_probe) and per-tier `auto_quality` mapping. Validated
on the lab 5090; never validated on real 3060/4060. W5 carries the
controller pattern + adds per-biome variation + color grading.

Per pillar 1 (visual quality first): lighting is the single biggest
visual lift after atmosphere. Doing it right matters more than perf
optimization here — but pillar 2 still rules: target hardware must
hit budget.

## Non-goals

- Realtime lightmap baking (consumer responsibility)
- User-facing lighting editor UI (config-driven only)
- Ray-tracing (Godot 4.5 doesn't ship RT)
- HDR sky capture from atmosphere (atmosphere → ambient color drives
  reflections automatically via Godot's Sky resource)
- Hand-placed light sources in worlds (decoration may emit lights via
  consumer extension — engine doesn't ship a light-placement system)

## V1 architecture

### GI strategy

Per quality tier (audit O5: SDFGI + planar reflections + volumetric
clouds together at high blow the frame budget; SDFGI tier-gated):

| Tier | GI | Shadows | Frame cost (X_FRAME_BUDGET) |
|---|---|---|---|
| `low` | Analytical (sky + sun ambient only) | None | 0 ms |
| `medium` | Analytical + SSAO | Cascaded (2 cascades, near only) | ~0.5 ms |
| `high` | **SDFGI probe LIGHT** (Godot built-in, lower probe density) | Cascaded (4 cascades, 600m max) | 1.2 ms |
| `ultra` | SDFGI probe FULL (full density) | Cascaded (4 cascades, 1000m max) | 3.0 ms |
| `cinematic` | SDFGI extended + planar reflection enabled | Cascaded + far-distance | ~4.0 ms |

**SDFGI light vs full**: at `high` tier (1.2 ms target), SDFGI runs
with reduced probe density / lower cascade count so the cost fits the
budget while still delivering bounce light. `ultra` enables the full
SDFGI cost W4 measured.

Shadow gating: W4 measured full-ring terrain shadow casting blowing
the geometry budget (1.30M → 6.51M tris). v1 defers full-ring terrain
shadow casting; only decoration + foliage cast shadows at all tiers.
Documented trade-off; revisit if a "shadowed terrain" demo becomes
important.

### Color grading + post-process

Per-biome × per-time-of-day grading recipes:

```json
{
  "alpine_noon": {
    "lut_path": "luts/alpine_cool_noon.cube",
    "exposure_offset": 0.0,
    "saturation": 1.05,
    "contrast": 1.10,
    "bloom_threshold": 1.2,
    "bloom_intensity": 0.15,
    "vignette_strength": 0.0
  },
  "wetland_dawn": { /* ... warmer, more saturated, higher bloom */ },
  "alpine_storm": { /* ... desaturated, gray, low contrast */ }
}
```

LUT-driven: 3D color LUTs (`.cube` format, standard) loaded as
`Texture3D`. Per-biome + per-time-of-day choice. Cross-fade at biome
boundaries (same shader as material splat blend; lighting recipe
honors biome weights).

### Per-biome lighting tuning

Each biome declares lighting overrides in its catalog entry:

```json
"biome": {
  "name": "alpine",
  "lighting": {
    "ambient_color_tint": [0.85, 0.92, 1.0],  // cool blue tint
    "shadow_strength_mult": 1.1,
    "sun_intensity_mult": 0.95,
    "ssao_strength": 0.6,
    "grading_recipe_prefix": "alpine"
  }
}
```

Cross-faded at biome boundaries via biome-weight blend. Same
world-anchored mask used by materials applies here.

## Public API (skeleton)

```gdscript
class_name LightingController extends Node
# Autoload at /root/Lighting

@export var auto_quality: bool = true

func apply_recipe(name: String) -> void
func get_current_recipe() -> Dictionary
func resolve_recipe_for_tier(tier_name: String) -> String  # returns recipe name
func apply_biome_grading(biome_weights: Dictionary, time_of_day: float) -> void

signal recipe_changed(name: String)
```

```python
# Pipeline: build per-biome × per-time-of-day grading recipes
python -m world5.lighting.build_grading_recipes --biome alpine
```

## Recipe catalog

`engine/resources/lighting_recipes.json`:

```json
{
  "schema_version": 1,
  "_documentation_only_auto_quality": {
    "_note": "SA-S4.2: source of truth for tier→recipe mapping is quality_tiers.json's per-tier lighting_recipe field. This block is reference documentation showing the default mapping; consumer worlds override by setting their own lighting_recipe in quality_tiers.json.",
    "low": "baseline_analytical",
    "medium": "shadow_near",
    "high": "sdfgi_probe",
    "ultra": "sdfgi_probe_tight",
    "cinematic": "sdfgi_probe_extended"
  },
  "recipes": {
    "baseline_analytical": { /* sun + ambient only */ },
    "shadow_near": { /* + SSAO + 2 cascade shadows */ },
    "sdfgi_probe": { /* + SDFGI + 4 cascades + 600m */ },
    "sdfgi_probe_tight": { /* + tighter cascade splits */ },
    "sdfgi_probe_extended": { /* + 1000m + extra far cascade */ }
  }
}
```

Per-recipe inheritance: a recipe can extend another (`extends:
"shadow_near"`) and override only what changes. Carry from W4.

## Producer / consumer contract

- **Produces**: applied WorldEnvironment + DirectionalLight + post-
  process state; cross-faded per biome
- **Consumes**: recipe catalog; per-biome lighting overrides;
  per-biome × per-time grading LUTs; quality tier; biome weights from
  terrain backend

## Dependencies

- `13_QUALITY_TIERS` (auto_quality mapping)
- `22_BIOME_CATALOG` (per-biome lighting overrides)
- `30_ATMOSPHERE` (sun direction + ambient color baseline)
- `21_TERRAIN_RENDERER` (consumes shadow + GI uniforms)

## Quality bar

- Lighting recipe apply: ≤ 100ms (one-time per scene; not per-frame)
- Per-frame grading shader cost: ≤ 0.3 ms per frame at `high` tier
  (authorized by `X_FRAME_BUDGET.md`)
- SDFGI cost: ≤ 1.2 ms per frame at `high` tier (light variant);
  3.0 ms at `ultra` (full); 4.0 ms at `cinematic` (extended, far-
  distance probes); authorized by `X_FRAME_BUDGET.md` (SA-S4.3)
- GPU/CPU thread compliance verified per spec 08a
- Visual: per-biome lighting visibly varies (cold alpine vs warm
  wetland); cross-faded at boundaries (no hard switch)
- Color grading: per-time-of-day shifts (dawn warm, noon neutral,
  dusk warm) visibly correct
- pytest coverage of recipe loader + auto_quality; gut coverage of
  controller behavior; capture-based visual diff for per-biome
  grading at all 3 times-of-day

## Discoverability

- **Entry point**: `Lighting.apply_recipe(name)` autoload
- **Schema**: `engine/resources/schemas/lighting_recipe.schema.json` +
  per-biome catalog lighting block in spec 22 schema
- **Validator / preflight**: world contract validates recipes + LUT
  paths exist
- **Example**: `engine/examples/lighting_recipe_example.tscn` shows
  all auto_quality tiers + per-biome variants
- **Deterministic outputs**: yes — recipe + biome weights + time-of-day
  produces same uniforms

## Open questions

- **LUT authoring**: who creates per-biome LUTs? Probably hand-authored
  in DaVinci Resolve / Photoshop and exported as `.cube`. Could be
  LLM-suggested baselines. Defer.
- **Grading at biome boundaries**: blending 3D LUTs is GPU-cheap but
  requires shader work. Plan-doc detail.
- **Far-distance lighting**: at >5km, shadow maps degenerate. SDFGI
  helps but only out to its range. Far-distance is mostly fog +
  ambient. Document as a known limitation; revisit if visual review
  surfaces.
- **Reflection probes**: WorldEnvironment + Sky drives default
  reflections. Per-biome reflection tinting? Probably overkill;
  ambient_color_tint covers most.

## References

- W4 `scripts/lighting/LightingRecipeController.gd` — proven controller
- W4 `config/lighting_recipes.json` — catalog pattern
- WISHLIST "Color grading + post-process recipes"
- Godot 4.5 SDFGI documentation

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-audit (S7, O5). Tier-gated SDFGI: light variant at
  `high` (1.2 ms), full at `ultra` (3.0 ms). Renamed `ultra_far` to
  `cinematic`. Frame costs authorized by X_FRAME_BUDGET.
