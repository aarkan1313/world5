# Spec: Quality Tiers

> Status: draft
> Tier: cross-cutting (Tier 0)
> Depends on: 01_MODULE_LAYOUT
> Consumed by: terrain backend, atmosphere, lighting, decoration runtime, streaming budget, every system that scales with hardware

## Purpose

A typed dict per quality tier, holding all per-tier knobs (LOD distances,
streaming budgets, atmosphere/fog ranges, lighting recipe choice, far
plane, etc.). Consumers read the current tier and apply its values; no
hardcoded per-system tier logic.

W4.1 carry-over (`config/quality_tiers.json` + Python resolver +
GDScript resolver + cross-impl parity test). Proven pattern. W5 keeps
the 5-tier structure but **re-derives the actual numbers** based on
W5's renderer architecture (TBD via research sprint).

## Non-goals

- Dynamic per-frame tier switching (tier is chosen at session start;
  user re-selects via a UI restart)
- User-facing graphics settings UI (consumer responsibility)
- Auto-detect "right" tier based on benchmark (defer; user picks)

## Tiers

Five tiers. **Names locked; values calibrated per-system as W5 ships.**

| Tier | Target hardware | Use case |
|---|---|---|
| `low` | Integrated GPUs, mobile (if ever) | Minimum playable |
| `medium` | GTX 1660 / RTX 2060 class | Comfortable mainstream |
| `high` | RTX 3060 / 4060 class (**default**) | Recommended target |
| `ultra` | RTX 3080+ / 4070+ | Enthusiast |
| `cinematic` | RTX 5090 lab machine | Screenshot / cinematic / engine stress |

`cinematic`'s purpose in W5: edge-case validation that the engine
handles extreme distance + runs the heaviest visual stack
(SDFGI + volumetric clouds + planar reflections all on). NOT a
"ship this for players" tier; the 30fps target reflects that. Audit
S7 renamed from `ultra_far` to `cinematic` (final).

## Per-tier knob keys (schema)

The values below are illustrative — actual numbers calibrated per
system as W5 ships. Schema is what's locked here.

```json
{
  "tier_name": "high",

  // Streaming budget (consumed by spec 10)
  "streaming_budget_active_tris": 4000000,
  "streaming_budget_resident_texture_mb": 1500,
  "streaming_budget_draw_calls": 800,
  "streaming_budget_active_jobs": 16,
  "streaming_budget_cpu_pages": 64,
  "streaming_budget_gpu_pages": 32,
  "streaming_budget_asset_cache_mb": 800,

  // Frame budget (consumed by profilers)
  "frame_budget_target_ms": 16.6,
  "frame_budget_p99_ms": 20.0,
  "frame_budget_peak_ms": 33.0,

  // Terrain (consumed by terrain renderer/backend)
  "terrain_rings": 8,
  "terrain_grid_n": 256,
  "terrain_step0_m": 2.0,
  "terrain_stepN_m": 64.0,
  "terrain_collision_rings": 2,
  "terrain_morph_band_fraction": 0.16,
  "terrain_snap_near_cells": 4,
  "terrain_snap_far_cells": 16,
  "terrain_pbr_tile_size_m": 8.0,
  "terrain_macro_tile_size_m": 256.0,

  // Visibility (consumed by terrain + atmosphere)
  "visibility_ship_distance_m": 8000,
  "visibility_haze_start_fraction": 0.65,
  "visibility_haze_end_fraction": 1.0,
  "visibility_min_fade_fraction": 0.1,

  // Decoration (consumed by decoration runtime)
  "decoration_lod_close_m": 30.0,
  "decoration_lod_mid_m": 80.0,
  "decoration_lod_far_m": 250.0,
  "decoration_max_visible": 8000,

  // Spatial index per-workload cell sizes (consumed by spec 08; SA-S1.7)
  "spatial_index_decoration_cell_size_m": 8.0,
  "spatial_index_terrain_cell_size_m": 64.0,
  "spatial_index_foliage_cell_size_m": 16.0,
  "spatial_index_default_cell_size_m": 32.0,

  // Per-system tier knobs may be added by individual specs (SA-M2.6).
  // Example: spec 33 adds nav_grid_n (low=32, medium=48, high=64,
  // ultra=96, cinematic=128). This example dict is NOT exhaustive;
  // see per-spec sections for additional keys.

  // Lighting (consumed by lighting recipes)
  "lighting_recipe": "outdoor_shadow_near",   // or "outdoor_sdfgi_probe" etc

  // Atmosphere (consumed by atmosphere profile)
  "atmosphere_profile": "clear_noon_high"
}
```

New keys are added freely as systems need them. Removed keys require
revision history note + a one-version deprecation cycle for forks.

### Where per-tier knobs live (SA-S2.5)

Two patterns:
- **Numeric / scalar knobs** (frame budget targets, page counts,
  resolutions, LOD distances): live HERE in `quality_tiers.json` as
  per-tier fields. This is the canonical source.
- **Per-tier recipe selection** (lighting recipe name, atmosphere
  profile name, weather profile name): named recipes live in the
  consuming system's own config (e.g. `lighting_recipes.json`,
  `atmosphere_profiles.json`); the tier→recipe mapping lives HERE as
  a single field (e.g. `lighting_recipe: "outdoor_shadow_near"` per
  tier). Spec 13 is the source of truth for the mapping; the
  consuming spec's `auto_quality` block is documentation only.

## Public API

### Python: `pipeline/core/quality_tiers.py`

```python
class QualityTiers:
    @staticmethod
    def load(config_path: Path = None) -> dict[str, dict]: ...

    @staticmethod
    def get(tier_name: str) -> dict: ...

    @staticmethod
    def get_current() -> dict:
        """Reads from world5 process state (env var or config); default 'high'."""

    @staticmethod
    def names() -> list[str]: ...
```

### GDScript: `engine/scripts/core/QualityTiers.gd`

**Phase 2.3 lesson**: GDScript's `Object.load(path)` (Resource loader)
and `Object.get(property)` (property getter) are builtins; static
methods named `load` or `get` shadow them and the parser errors out
("Cannot call non-static function ... from the static function ...").
GDScript renamed `load → load_config` and `get → get_tier`. Python
side keeps `.load` and `.get` since there's no conflict. Cross-impl
tests call the language-appropriate name.

```gdscript
class_name QualityTiers extends Node
# Singleton autoload at /root/QualityTiers

static func get(tier_name: String = "") -> Dictionary:
    """Returns the tier dict. tier_name="" means current."""

static func get_current() -> Dictionary:
    """Reads from ProjectSettings 'world5/quality_tier' or default 'high'."""

static func names() -> PackedStringArray
```

### Config source of truth

`engine/resources/quality_tiers.json`. JSON Schema for validation lives
at `engine/resources/quality_tiers.schema.json` (used by world contract
preflight to reject invalid tier configs).

## Cross-impl parity

Same as W4.1: a test at `tests/test_quality_tiers_cross_impl.py` runs
both resolvers against the same JSON config and asserts identical
output. Catches any drift between Python and GDScript interpretation
(e.g. JSON number → typed value conversion).

## Producer / consumer contract

- **Produces**: tier dicts on demand
- **Consumes**: a JSON config + optional override env var / project
  setting

## Dependencies

- `01_MODULE_LAYOUT` (placement)

## Quality bar

- `get_current()` is < 100µs (cached after first call)
- Cross-impl parity: 0 differences between Python and GDScript
  resolvers for any valid config
- Schema validation: rejects malformed configs at preflight time
- Default tier is `high`; explicit env var override available for
  testing
- 100% test coverage of public API (pytest + gut)

## Discoverability

- **Entry point**: `QualityTiers.get_current()` (either language)
- **Schema**: JSON Schema at `engine/resources/quality_tiers.schema.json`
- **Validator / preflight**: world contract checks tier config matches
  schema; cross-impl test catches resolver drift
- **Example**: `engine/examples/quality_tier_example.gd` shows a system
  reading + applying tier knobs
- **Deterministic outputs**: yes — same config + same tier name → same dict

## Open questions

- **Rename `cinematic`**: RESOLVED (audit S7). Renamed from
  `ultra_far` to `cinematic`. Specs 31 + 40 updated; X_FRAME_BUDGET
  uses the new name throughout.
- **Calibration sprint**: at what point in W5 do we re-derive the
  actual per-tier numbers? Probably right after the terrain MVP +
  texture pipeline ship (so we can measure on something real).
- **Auto-detect**: defer; user picks tier explicitly for now.

## References

- W4.1 `pipeline/quality_tiers.py` + `scripts/QualityTiers.gd` +
  `config/quality_tiers.json` — the carry-over source (review +
  refactor; don't copy literally)
- W4.1 cross-impl test: `tests/test_quality_tiers_cross_impl.py`

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-audit (S7). Renamed `ultra_far` → `cinematic`
  (committed, no longer "may be renamed"). Cinematic stays in v1 but
  with explicit 30fps target.
