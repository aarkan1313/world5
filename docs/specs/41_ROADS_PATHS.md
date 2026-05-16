# Spec: Roads + Paths + Corridors

> Status: draft
> Tier: 2 (world)
> Depends on: 20_TERRAIN_BACKEND, 21_TERRAIN_RENDERER,
> 22_BIOME_CATALOG, 23_MATERIALS_PBR, 28_DECORATION, 29_FOLIAGE,
> 33_NAV_EXPORT, 35_WATER, 07_JOB_SYSTEM
> Consumed by: terrain renderer (road surface shader), decoration
> + foliage (exclusion along path), nav export (paths boost
> walkability)

## Purpose

Procedural path / road / corridor system. Games need intentional
traversal, not just terrain. V1 supports:
- **Procedural path generation**: A* over a cost grid derived from
  terrain (slope penalty, water blocker, biome cost), connecting
  named POIs
- **Hand-authored path overrides**: author lists control points + the
  engine renders + carves + excludes decoration
- **Both interoperate**: procedural runs by default; authored
  overrides win locally

Paths cut through terrain (modify splat for surface), block
decoration + foliage along their width, contribute walkability boost
to nav export. Optional surface material per path (gravel /
cobblestone / dirt / stone slab) selected per-biome or per-path.

## Non-goals

- Full city / town layout (consumer territory; buildings spec 37
  reserved schema covers footprint, not town grid)
- Multi-floor / multi-level paths (e.g. bridges over rivers — supported
  via control-point Y; complex multi-level traversal deferred)
- Pathfinding for NPCs along roads (nav export feeds consumer's
  NavigationServer3D; consumer-side path logic uses that)
- Animated path elements (cart tracks, footprints accumulating —
  deferred to deformation spec 38 with footprint profile)

## V1 architecture

```
┌──────────────────────────────────────────────────┐
│ PIPELINE (Python, offline; pipeline/roads/)      │
│                                                   │
│ [1] POI catalog                                   │
│     • worlds/<w>/pois.json lists named points    │
│       (towns, altars, dungeons, etc.) with       │
│       world XZ + name                            │
│   ↓                                               │
│ [2] Cost grid generation (SA-C5.4)               │
│     • Per-chunk cost computed BY THIS PIPELINE   │
│       from terrain backend capabilities:         │
│       slope_deg, biome_mask, water_mask (from    │
│       spec 35), elevation                        │
│     • Cost formula per cell:                      │
│       cost = slope_penalty(slope_deg) +          │
│              biome_cost[biome] +                 │
│              elevation_penalty(elevation) +      │
│              (∞ if water_mask, no path through)  │
│       Lower cost = preferred path                │
│     • Per-cell resolution: 8m (chunk-coarser     │
│       than terrain's 2m for fast A*)             │
│     • Storage: roads_cost_grid.npz per world,    │
│       content-addressed (spec 12)                │
│     • Optional: hand-authored cost-mod overlay   │
│       (e.g. forbid path through a specific       │
│       sacred grove); merged at A* time           │
│   ↓                                               │
│ [3] A* path generation                            │
│     • For each POI pair (or declared connections), │
│       A* over the cost grid                      │
│     • Output: path control points + width hint   │
│   ↓                                               │
│ [4] Hand-authored overrides applied               │
│     • Author lists control points for specific   │
│       paths in roads.json                        │
│     • Overrides win locally; procedural paths    │
│       merge into them at endpoints                │
│   ↓                                               │
│ [5] Path mesh + splat bake                        │
│     • Per-chunk path mesh (subtle terrain        │
│       depression along path width)               │
│     • Splat overlay: path surface material        │
│       painted in splat texture                   │
│     • Output: per-chunk path geometry + splat    │
│       deltas in world bundle                     │
└──────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│ RUNTIME (GDScript; engine/scripts/roads/)        │
│                                                   │
│ • PathWorld scene component                       │
│ • Per-chunk path mesh load + render               │
│ • Path-aware decoration exclusion (decoration    │
│   subscribes to path data, skips placements      │
│   in path width zone)                             │
│ • Path-aware foliage exclusion (same)            │
│ • Nav walkability boost (path mask added to nav  │
│   export's walkable_u8)                          │
└──────────────────────────────────────────────────┘
```

## Path definition

`worlds/<world>/roads.json` (hand-authored overrides + procedural
output merged):

```json
{
  "schema_version": 1,
  "paths": [
    {
      "name": "altar_to_village",
      "type": "procedural",
      "from_poi": "altar_grove",
      "to_poi": "village",
      "surface": "dirt",
      "width_m": 2.5,
      "auto_generate": true
    },
    {
      "name": "hand_path_north_ridge",
      "type": "handcrafted",
      "control_points": [[10, 50], [20, 60], [40, 80]],
      "surface": "stone_slab",
      "width_m": 1.5,
      "elevation_offsets_m": [-0.2, -0.15, -0.1]
    }
  ],
  "cost_overrides": [
    {
      "name": "forbid_sacred_grove",
      "bounds": { "x0": -300, "z0": -300, "x1": -200, "z1": -200 },
      "cost_mult": 100.0
    }
  ]
}
```

Procedural paths regenerate at offline bake time if POI positions
change. Hand-authored paths are stable across bakes.

## Path surface materials

Per-biome surface defaults declared in biome catalog spec 22:

```json
"biome": {
  "name": "alpine",
  "path_surfaces": {
    "default": "dirt",
    "stone_zones": "stone_slab"
  }
}
```

Path surface paints into splat at bake time as a new "path" material
slot — the renderer (spec 21) consumes it. Per-tier path surface
resolution (low tier = simpler, fewer slots).

## Decoration + foliage exclusion

Roads.json paths publish a `path_zone` change broadcast event at
world load:
- Decoration runtime (spec 28) subscribes; treats path zones as
  exclusion zones (W4 R9 sprint pattern carries over conceptually)
- Foliage runtime (spec 29) same

Exclusion happens in a width buffer around path centerline (default
1.5× path width). Some authored paths can override (e.g.
"overgrown ruins road" with reduced exclusion).

## Nav export contribution

Nav export (spec 33) at bake time:
- Path mask adds to walkable_u8 (paths boost walkability beyond
  base terrain slope evaluation)
- Path direction stored as optional flow direction (consumer NPC AI
  can follow paths preferentially)

## Public API

```python
# Offline procedural bake
python -m world5.roads.generate --world worlds/two_biome_demo

# Validate
python -m world5.roads.validate --world worlds/two_biome_demo
```

```gdscript
class_name PathWorld extends Node3D
@export var world_bundle_path: String

func get_paths_in_rect(rect: Rect2) -> Array[String]
func get_nearest_path_distance(world_xz: Vector2) -> float
func is_position_on_path(world_xz: Vector2) -> bool
```

## Producer / consumer contract

- **Produces** (offline): per-chunk path meshes; splat deltas;
  walkability mask additions
- **Produces** (runtime): rendered paths; change broadcast events
  at load time for decoration/foliage exclusion
- **Consumes**: POI catalog; cost overrides; biome surface defaults;
  terrain backend cost grid; water masks (water blocks paths)

## Dependencies

- `20_TERRAIN_BACKEND` (cost grid source)
- `21_TERRAIN_RENDERER` (path mesh + splat rendered alongside)
- `22_BIOME_CATALOG` (per-biome path surface defaults)
- `23_MATERIALS_PBR` (path surface materials)
- `28_DECORATION` (path exclusion subscriber)
- `29_FOLIAGE` (path exclusion subscriber)
- `33_NAV_EXPORT` (walkability mask contribution)
- `35_WATER` (water blocks paths during A*)
- `07_JOB_SYSTEM` (procedural generation runs as offline jobs)

## Quality bar

- A* path generation between POIs: ≤ 30s per pair on a 4×4 chunk world
- Path mesh + splat bake: ≤ 2s per chunk that has a path
- Runtime path load: ≤ 50ms per chunk via async streaming
- Visual: paths cut visibly into terrain (subtle depression + surface
  material), decoration cleanly excluded in the width buffer
- Total path runtime perf: ≤ 0.1 ms per frame at `high` tier
  (authorized by `X_FRAME_BUDGET.md`); typical 10-20 resident path
  segments
- World contract validates roads.json + POI cross-refs + biome
  surface availability

## Discoverability

- **Entry point**: `python -m world5.roads.generate` (offline);
  `PathWorld` scene component (runtime)
- **Schema**: `engine/resources/schemas/roads.schema.json` +
  `pois.schema.json`
- **Validator / preflight**: world contract integrates
- **Example**: `engine/examples/road_example_world/` with two POIs
  + procedural path + hand-authored override
- **Deterministic outputs**: yes — same POIs + same cost grid + same
  procedural seed → same paths

## Open questions

- **Path elevation snapping**: should paths follow terrain exactly
  (more natural) or smooth across terrain (rolled grade for carts /
  roads)? Probably tunable per path type — `terrain_follow` (default
  for foot paths) vs `smoothed` (for roads). Defer schema detail.
- **Path-water intersection (bridges)**: when a path A* result needs
  to cross water, do we (a) re-route, (b) auto-place a bridge
  building (depends on spec 37 buildings shipping), or (c) flag for
  hand-authoring? V1: (a) re-route; flag for hand-authoring if no
  route exists. Bridge structures are Phase B / buildings work.
- **Path width variation along length**: roads narrow at switchbacks,
  widen at junctions. Width-per-control-point in schema. Defer
  rendering nicety.
- **Path-cave interaction**: paths shouldn't drop into caves. Cost
  grid should treat cave entrances as low cost (paths often lead to
  caves); cave interiors as high cost (paths don't go through). Spec
  in plan doc.

## References

- W4 WISHLIST "Roads / paths / traversal corridors v0"
- Standard A* terrain pathing; well-understood algorithm

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-self-audit (SA-C5.4). Cost grid generation is
  the pipeline's responsibility (reads slope/biome/water from
  terrain backend's existing capabilities; no new backend output
  needed). Resolution + storage + content addressing committed.
  Also (SA-S5.3): runtime perf budget aligned to X_FRAME_BUDGET's
  0.1 ms allocation at high tier.
