# Spec: Bake Recipes (Offline Output)

> Status: draft (skeleton — actual recipes deferred to per-need
> sprints)
> Tier: 3 (output / packaging)
> Depends on: 21_TERRAIN_RENDERER, 30_ATMOSPHERE, 31_LIGHTING_GI
> Consumed by: consumer projects that want offline-baked images
> (2.5D game scenes, in-game maps, strategic world-map views)

## Purpose

Offline rendering tools that produce static or low-frequency-updated
images from a W5 world bundle. Each recipe:
- Loads a baked world bundle
- Runs Godot headless with a specific camera + lighting + post-process
  configuration
- Writes images + a manifest

V1 ships **the contract + runner skeleton, NOT specific recipes.**
Three known-needed recipes (2.5D, topdown, world-map) defer to
per-need sprints. By the time those sprints run, we'll know the
renderer + atmosphere + lighting in detail — current guess would be
premature.

## Non-goals

- Runtime view-mode switching (engine is 3D-only; bake recipes are
  OFFLINE)
- Real-time map updates in-game (consumer wires their own; can call
  into bake recipes from CLI / agent)
- Animated bake output (recipes produce still images; video bake is
  a future extension via the same contract)
- Bake-time gameplay logic (just rendering)

## Recipe contract

Each recipe is a standalone Python module under
`pipeline/bake_recipes/<recipe_name>.py`. Conforms to:

```python
class BakeRecipe(ABC):
    name: str               # "2_5d_painterly", "topdown_cartographic", etc.
    description: str

    @abstractmethod
    def run(self, world_path: Path, output_dir: Path, options: dict) -> BakeResult: ...

class BakeResult:
    image_paths: list[Path]
    manifest_path: Path     # JSON describing what was rendered
    duration_s: float
    success: bool
    error: str | None
```

Recipe runs by:
1. Validating world_path via world contract
2. Launching Godot headless with a recipe-specific scene
3. Recipe-specific scene loads world, sets camera, renders to PNG(s)
4. Saving manifest with provenance (recipe version, world version,
   render parameters, timestamps)

## Runner skeleton

`pipeline/bake_recipes/run.py`:

```bash
python -m world5.bake --recipe <recipe_name> --world <path> \
    --output <dir> [--option key=value ...]
```

V1 ships:
- The runner CLI (`world5.bake`)
- The `BakeRecipe` base class + registration mechanism
- One example recipe stub (`debug_overhead`) that just renders a
  simple top-down screenshot at a known camera — proves the contract
  works

V1 does NOT ship:
- 2.5D painterly recipe (deferred)
- Topdown cartographic recipe (deferred)
- World-map strategic-scale recipe (deferred)

These recipes get specs when their consumers need them.

## When recipes get added

Each recipe sprint:
1. Write a recipe sub-spec (drilling down from this one) covering
   camera config + lighting overrides + post-process specifics
2. Implement the recipe Python module
3. Write a test fixture (world bundle + expected output diff)
4. World contract validates recipe options if recipe is consumed by
   bundle

## Manifest shape

Every bake output writes:

```json
{
  "schema_version": 1,
  "w5_version": "0.1.0",
  "recipe_name": "debug_overhead",
  "recipe_version": "0.1.0",
  "world_path": "worlds/two_biome_demo",
  "world_version": "0.1.0",
  "render_options": { /* recipe-specific */ },
  "image_paths": ["captures/debug_overhead/output.png"],
  "duration_s": 12.4,
  "content_address_key": "sha256..."
}
```

Cached via content addressing (spec 12) — same world version +
same recipe + same options → cache hit, no re-render.

## Public API

```bash
python -m world5.bake --list-recipes
python -m world5.bake --recipe debug_overhead --world worlds/two_biome_demo \
    --output captures/test_bake/
```

Python:
```python
from world5.bake import registry, run_recipe

result = run_recipe("debug_overhead", world_path, output_dir, options={})
```

## Producer / consumer contract

- **Produces**: images + manifest per bake run
- **Consumes**: world bundle; recipe selection; per-recipe options

## Dependencies

- `21_TERRAIN_RENDERER` (recipes render via the engine renderer)
- `30_ATMOSPHERE` (atmosphere profile applied per recipe)
- `31_LIGHTING_GI` (lighting recipe applied per recipe)
- Godot 4.5 headless mode
- World contract (validates world before render)

## Quality bar

- Recipe runner overhead (Godot launch + world load + scene setup):
  ≤ 10s on dev hardware cold-start; ≤ 2s with warm Godot process
  (SA-S5.5: prior "≤ 5s" was aspirational. Recipe batching keeps
  Godot resident across multiple bakes to amortize startup.)
- Cache hit returns in < 1s
- World contract integration: recipes can't be invoked on invalid
  bundles
- JSON output parseable by LLM agents (for unattended bake pipelines)
- 100% pytest coverage of runner + registration; per-recipe tests
  ship with each recipe

## Discoverability

- **Entry point**: `python -m world5.bake --list-recipes` to see
  available recipes; `--recipe <name>` to run
- **Schema**: `BakeRecipe` base class + manifest shape above
- **Validator / preflight**: world contract integration validates
  recipe options against per-recipe schema
- **Example**: `debug_overhead` recipe is the worked example for v1
- **Deterministic outputs**: yes — same world version + same recipe +
  same options → same output

## Open questions

- **Recipe testing pattern**: how do we visual-diff bake outputs in
  CI? Perceptual diff against golden PNG (same approach as renderer
  capture tests in spec 06). Defer specifics.
- **Recipe versioning**: recipes themselves have version stamps;
  bumps trigger cache invalidation. Spec'd.
- **Per-world recipe overrides**: a world bundle might want to
  override the default recipe options (e.g. "for this world, the
  2.5D bake should use these camera angles"). Schema slot in world
  bundle: `bake_overrides.json`. Defer until first recipe needs it.
- **Recipe sprints sequencing**: probably 2.5D first (closest to
  consumer game's needs), then topdown (in-game map), then world-map
  (strategic view). Defer to Phase 15+ planning.

## References

- W4 had no bake recipes (only headless capture for visual tests)
- Used pattern: Godot's `--headless` + scene script that renders +
  saves PNG (W4 capture pattern, now formalized as recipe contract)

## Revision history

- 2026-05-16: initial draft (skeleton; concrete recipes deferred)
