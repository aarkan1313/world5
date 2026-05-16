# Spec: Nav Export

> Status: draft
> Tier: 1 (core)
> Depends on: 20_TERRAIN_BACKEND, 22_BIOME_CATALOG, 28_DECORATION,
> 29_FOLIAGE, 35_WATER, 37_CAVES_INTERIORS
> Consumed by: consumer projects building runtime navmesh; W5
> persistence (when shipped)

## Purpose

W5 emits nav-relevant data (walkable mask, slope, water mask,
obstruction masks from decoration / foliage / buildings) on a stable
schema. Consumer projects build actual navmesh from it.

Carry-over from W4.1 (`pipeline/nav_export.py` +
`pipeline/nav_mesh_source.py`). Engine-neutral JSON manifest +
per-chunk compressed `.npz` blobs. Plus runtime helpers for
NavigationServer3D map construction from the source.

W5 keeps the contract, extends coverage to W5's expanded system set
(water + foliage + decoration + buildings all contribute to
obstruction).

## Non-goals

- Runtime navmesh GENERATION (consumer territory; W5 supplies the
  source, consumer builds the actual navmesh)
- NPC AI navigation behavior (consumer territory)
- Pathfinding optimization (consumer concern)
- Multi-floor / multi-level navmesh (consumer extension; W5 ships 2D
  XZ navmesh source)

## V1 schema

### Manifest (`nav_manifest.json`)

```json
{
  "schema_version": 1,
  "w5_version": "0.1.0",
  "world_name": "two_biome_demo",
  "world_extent_m": { "x0": -2048, "z0": -2048, "x1": 2048, "z1": 2048 },
  "chunk_size_m": 256,
  "chunk_grid_n": 64,
  "tier_at_bake": "high",
  /* nav_grid_n is decoupled from terrain_grid_n (audit M9):
     terrain uses 256² samples per chunk; nav uses 64² (quarter rate).
     Decoupling is intentional — nav doesn't need height resolution
     beyond pathfinding granularity. Per-tier nav_grid_n knob in
     quality_tiers.json: low=32, medium=48, high=64, ultra=96,
     cinematic=128 (4x oversampled for hero scenes).

     tier_at_bake field (SA-S4.5): records which tier the nav was
     baked at. Loader checks consumer's runtime tier matches OR
     warns/regenerates. */
  "chunks": [
    { "cx": 0, "cz": 0, "blob": "chunks/chunk_0_0.npz",
      "cache_key": "...", "version_stamp": {...} },
    ...
  ]
}
```

### Per-chunk blob (`chunk_<cx>_<cz>.npz`)

```python
{
  "height_m": np.float32, shape (64, 64),
  "slope_rise_run": np.float32, shape (64, 64),
  "walkable_u8": np.uint8, shape (64, 64),  # 0=blocked, 255=walkable, gradient OK
  "water_u8": np.uint8, shape (64, 64),     # 0=dry, 255=submerged
  "obstruction_u8": np.uint8, shape (64, 64), # 0=clear, 255=fully blocked
  "biome_names": ["alpine", "wetland"],
  "biome_dominant_u8": np.uint8, shape (64, 64),  # index into biome_names
  "source_cache_key": "sha256...",
  "version_stamp": { ... }
}
```

`walkable_u8` derived from slope + biome `nav_default` + obstruction.
`obstruction_u8` aggregates from decoration footprints + foliage trunks
+ structures + buildings (when those systems publish).

### Welded navmesh source (`w5_navmesh_source_v1`)

For consumers that want a ready-to-load NavigationMesh resource:
- Global welded mesh (single source for whole world)
- Per-chunk region sources (tiled consumers; can load N chunks
  independently)

W4.1 validated the welded approach for 1-page and 2x2 batch.

## Public API

### CLI

```bash
# Export from a baked world bundle
python -m world5.nav.export --world worlds/two_biome_demo --out captures/nav_export/

# Build navmesh source from export
python -m world5.nav.build_source --export captures/nav_export/ --mode global

# Per-chunk regions
python -m world5.nav.build_source --export captures/nav_export/ --mode regions
```

### Python module

```python
from world5.nav import export, build_source

manifest = export(world_path, output_dir, capabilities=["height", "slope", "walkable", "water", "obstruction"])
navmesh = build_source.welded_global(manifest_path)
```

### Runtime helpers (GDScript, consumer-side)

```gdscript
# Convenience for consumers to load a navmesh source as a NavigationMesh
static func load_navmesh_source(path: String) -> NavigationMesh
static func load_region_sources(manifest_path: String) -> Array[NavigationMesh]
```

## Producer / consumer contract

- **Produces**: manifest JSON + per-chunk NPZ blobs + welded/region
  navmesh sources
- **Consumes**: terrain backend output (height + slope), biome
  catalog (walkable rules per biome), decoration runtime (obstruction
  footprints), foliage runtime (trunk obstructions), water spec
  (water masks), persistence (runtime placement obstruction updates)

## Cadence

V0 export is **explicit offline / sidecar**, not automatic
terrain-cache writes. Consumer runs the CLI once per world bundle to
generate the nav export. When persistence ships, runtime updates may
trigger incremental re-export of affected chunks (via change
broadcast subscription).

## Dependencies

- `20_TERRAIN_BACKEND` (height + slope sources)
- `22_BIOME_CATALOG` (per-biome walkability defaults)
- `28_DECORATION` (obstruction footprints)
- `29_FOLIAGE` (trunk obstructions)
- `35_WATER` (water masks; when water spec ships)
- `11_CHANGE_BROADCAST` (for future runtime invalidation)

## Quality bar

- Export of typical 4×4 chunk world: ≤ 30s
- Welded navmesh source build: ≤ 10s for 16-chunk world
- Manifest schema validated by world contract (spec 14)
- NavigationServer3D loads the source without errors; sample path
  query (start → end across N chunks) returns valid path
- W4 validation patterns: pytest cross-impl + Godot probe scenes
  (carry over the test harness)

## Discoverability

- **Entry point**: `python -m world5.nav.export` CLI
- **Schema**: manifest + blob shapes documented above; JSON Schema at
  `engine/resources/schemas/nav_manifest.schema.json`
- **Validator / preflight**: world contract validates manifest +
  chunk blob references; standalone gut probe loads + path-queries
- **Example**: `engine/examples/nav_export_example/` with a tiny
  world + its export + a "walk along the path" demo
- **Deterministic outputs**: yes given fixed inputs (kernel + biome +
  decoration are deterministic)

## Open questions

- **Streaming exports**: large worlds may not export in one shot.
  W4.1 deferred this; W5 inherits the deferral. Add when needed.
- **Multi-layer navmesh** (for caves below terrain): nav export
  schema needs extension for 3D. Schema slot only in v1; caves spec
  37 may drive the extension.
- **Runtime obstruction updates**: when persistence ships, decoration
  zone edits + runtime placements need to invalidate nav. Change
  broadcast subscription + incremental re-export. Plan-doc detail.
- **Per-NPC walkability**: a goblin can fit through a tunnel a giant
  can't. Schema slot for `agent_size_class` per nav chunk; consumer
  decides. Defer.

## References

- W4 `pipeline/nav_export.py` + `pipeline/nav_mesh_source.py` —
  carry-over base
- W4 demo: `scenes/nav_demo.tscn` (NavigationAgent3D walking baked
  source) — the validation pattern

## Revision history

- 2026-05-16: initial draft
