# Spec: Persistence + Author Overrides

> Status: draft
> Tier: 2 (world)
> Depends on: 14_WORLD_CONTRACT, 17_VERSIONING_AND_MIGRATION,
> 11_CHANGE_BROADCAST, 22_BIOME_CATALOG, 28_DECORATION,
> 33_NAV_EXPORT
> Consumed by: terrain renderer, decoration runtime, foliage runtime,
> water world, every system that has authored overrides

## Purpose

The "replace procedural with handcrafted" pattern across all systems.
A world bundle ships procedural defaults (kernel-generated terrain,
auto-biome assignment, Poisson-scatter decoration). Authors override
locally to ship handcrafted set-pieces (an altar grove with placed
stones, a specific lake polygon, a town footprint, a path through the
mountain).

V1 scope: **author overrides only (offline)**. Runtime save-state is
the consumer game's concern (different games save different things).
Engine ships the loading contract — at world load, layered authored
content is applied over procedural defaults. Consumer can wire their
game's save state to call into the same override API to apply player
edits at load time.

Save format: **JSON files per world bundle**, one file per system.
Human-readable, LLM-readable (matches engine LLM-drivability
commitment), easy to diff in git, easy to author by hand or by
agent.

## Non-goals

- Runtime save-state of player edits (consumer territory; engine's
  authoring API can be reused but engine doesn't auto-save runtime
  state)
- Multiplayer state sync (consumer)
- Versioned diffing / branching of saves (consumer)
- Cross-machine save migration beyond W5 version migration (spec 17
  handles that)

## V1 author-override scope

Per-system overrides supported in v1:

| System | Override file | What it overrides |
|---|---|---|
| Decoration | `decoration_overrides.json` | Per-zone hand-placed instances; exclude zones |
| Biome catalog | `biome_overrides.json` | Splat overrides (auto-biome alternative; already in spec 22) |
| Water | `water_bodies.json` | Lakes, rivers, coasts (already in spec 35) |
| Caves | `caves.json` | Cave SDF blobs (already in spec 37) |
| Buildings | `buildings.json` | Reserved schema slot (spec 37) |
| Roads | `roads.json` | Path segments (will be defined in spec 41) |
| Audio | `audio_tags.json` | Per-zone audio tag overrides (already in spec 34) |
| Atmosphere | `atmosphere_overrides.json` | Per-zone atmosphere profile overrides |

Many of these already exist as files defined by their respective
specs. This spec UNIFIES them under a shared loading + validation +
versioning contract.

## World bundle override directory

Inside a world bundle:

```
worlds/<world_name>/
├── biome_catalog.json
├── decoration_overrides.json    # ← override file
├── water_bodies.json            # ← override file
├── caves.json                   # ← override file
├── roads.json                   # ← override file
├── audio_tags.json              # ← override file
├── atmosphere_overrides.json    # ← override file
└── ...
```

All override files share a common structure:

```json
{
  "schema_version": 1,
  "w5_version": "0.1.0",
  "world_name": "two_biome_demo",
  "overrides": [
    {
      "name": "altar_grove",
      "bounds": { "x0": -300, "z0": -300, "x1": -200, "z1": -200 },
      "mode": "hybrid|handcrafted|exclude",
      /* system-specific payload */
    }
  ]
}
```

`mode` semantics common to all systems:
- `hybrid`: procedural + override. Procedural runs respects the
  override locally.
- `handcrafted`: only the override applies in `bounds`; procedural
  skipped.
- `exclude`: no system output in `bounds`.

Plus system-specific extensions (e.g. decoration has
`instance_overrides`; roads has `path_segments`).

## Loading + apply order

When a world bundle is loaded:

1. World contract validates all override files (schema, cross-refs,
   bounds within world extent)
2. **Water bodies loaded FIRST** (SA-M4.13): spec 22 climate's
   `distance_to_nearest_water` rule depends on the water bodies
   registry being available before climate is computed
3. Biome catalog parsed (climate is now computable per-XZ)
4. Other per-system overrides loaded (decoration, caves, roads,
   audio, atmosphere)
5. Override events are published via change broadcast as
   `<system>_override` source (decoration → `decoration_override`,
   roads → `road_override`, etc.) — so systems can self-subscribe to
   their own overrides at startup uniformly
6. Each system applies overrides per its own rules (decoration
   replaces procedural in zone bounds; water adds lakes; caves carve
   SDF; etc.)

## Public API (skeleton)

```gdscript
class_name OverrideManager extends Node
# Autoload at /root/Overrides

func load_overrides_for_world(world_path: String) -> Dictionary:
    """Returns dict of {system_name: parsed_override_data}.
    Called at world load time."""

func get_overrides_for_system(world_path: String, system_name: String) -> Dictionary

func apply_override(system_name: String, override_data: Dictionary) -> void:
    """Publishes a `<system>_override` event on ChangeBroadcast.
    Used by consumers wiring runtime save-state into the same path."""

signal world_overrides_loaded(world_path: String, systems: PackedStringArray)
```

```python
# Pipeline / consumer:
python -m world5.persistence.validate --world worlds/two_biome_demo
```

## Runtime save-state hook (consumer responsibility — INFORMATIVE)

**SA-M4.14 / audit O6**: this section is INFORMATIVE, not normative.
The contract W5 commits to is `OverrideManager.load_overrides_for_world(path)`
above. The pattern below is example consumer usage of that contract;
W5 doesn't enforce or test it.

Engine doesn't auto-save runtime state. But consumer can plug in:

```gdscript
# Consumer's save system:
class MyGameSaveSystem extends Node:
    func save_world(slot: int):
        var deformations = Deformation.get_active_deformations()
        var custom_decoration = ...  # consumer-tracked
        FileAccess.open("user://saves/%d/decoration_overrides.json" % slot, ...) \
            .store_string(format_as_w5_override(custom_decoration))

    func load_world(slot: int):
        # On world load, point Overrides at our save dir instead of the world bundle
        Overrides.load_overrides_for_world("user://saves/%d/" % slot)
```

The pattern: consumer's save dir LOOKS LIKE a world bundle (same
override files). Engine doesn't care if the dir is part of the world
bundle or part of a save slot — same loader.

## Versioning

Override files carry `w5_version` per spec 17. World contract
validates compat:
- Same MAJOR/MINOR → load directly
- Same MAJOR / older MINOR → load with warning
- Different MAJOR → require migration via `world5.migrate`

## Producer / consumer contract

- **Produces**: layered overrides applied to procedural defaults;
  unified loading flow; validation reports
- **Consumes**: per-system override files in a world bundle (or save
  slot); per-system schemas; world version

## Dependencies

- `14_WORLD_CONTRACT` (validates each override file's schema)
- `17_VERSIONING_AND_MIGRATION` (version stamps + migration on
  version mismatch)
- `11_CHANGE_BROADCAST` (publishes override events at load)
- All systems that have overrides (decoration, water, caves,
  roads, audio, atmosphere)

## Quality bar

- World load with all override files: ≤ 1s additional cost (override
  parsing + change broadcast events)
- Override files are LLM-editable (an LLM agent can read + write +
  validate a `decoration_overrides.json` without W5-specific
  tooling)
- World contract catches: out-of-extent bounds, unknown mesh refs,
  schema violations, version incompat
- 100% pytest coverage of override loaders + cross-system event
  publication
- Author workflow: hand-edit a JSON file → reload world → see the
  result (no rebake required for "hybrid" / "handcrafted" modes;
  procedural systems re-evaluate at runtime)

## Discoverability

- **Entry point**: `OverrideManager.load_overrides_for_world()` at
  world load; per-system files in the bundle for authoring
- **Schema**: per-system override schema in
  `engine/resources/schemas/overrides/<system>.schema.json`; shared
  override-envelope schema also there
- **Validator / preflight**: world contract integrates per-system
  override validation
- **Example**: `engine/examples/example_world_overrides/` shows a
  bundle with each kind of override
- **Deterministic outputs**: yes — same overrides + same procedural
  defaults → same final world

## Open questions

- **Per-system file consolidation**: each system has its own override
  file. Could be one mega-`overrides.json`. Probably keep per-system
  files for diff cleanliness + parallel editing. Defer reconsider.
- **Override priority**: if a decoration zone is "hybrid" and a road
  passes through it, which wins? Probably road wins where it
  intersects (roads carve through). Spec'd in roads spec 41.
- **Per-save migration**: consumer save dirs use the same versioning;
  if W5 bumps MAJOR, consumer saves break. Spec'd; migration script
  handles same way.
- **Authoring tools**: consumer hand-edit is the v1 authoring path.
  Future: in-engine editor for overrides? Probably yes someday;
  defer.

## References

- W4.1 had per-system overrides defined ad-hoc by each system
  (decoration_zones.json, surface_slots.json, material_variants.json).
  W5 unifies via this spec.
- WISHLIST "World persistence + author overrides" + "Advanced
  author override tools"

## Revision history

- 2026-05-16: initial draft
