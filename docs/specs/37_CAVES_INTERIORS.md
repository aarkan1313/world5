# Spec: Caves + Interiors

> Status: draft
> Tier: 2 (world)
> Depends on: 20_TERRAIN_BACKEND, 21_TERRAIN_RENDERER,
> 22_BIOME_CATALOG, 23_MATERIALS_PBR, 33_NAV_EXPORT,
> 11_CHANGE_BROADCAST, 39_PERSISTENCE_AND_AUTHOR_OVERRIDES
> Consumed by: terrain renderer (cave geometry rendered as terrain
> subset), nav export (cave volumes contribute walkable mask),
> persistence (cave state survives sessions)

## Purpose

V1 ships **caves only** as a working interior system. Building +
castle phases (per W4 wishlist) defer to Phase 12+; v1 reserves
the building-footprint schema slot so when phase B/C ship they
slot in cleanly without breaking existing worlds.

Caves are SDF-carved volumes inside the heightfield. Marching cubes
/ surface-nets meshing. Dual-mat blend at cave/surface interface.
NO loading screens — caves are part of the streamed chunks like
terrain.

## Non-goals

- Small buildings (single-room walk-in structures) — Phase B, deferred
- Castles + multi-building structures — Phase C, deferred
- Dynamic cave editing at runtime (deferred; SDF deformation possible
  via spec 38 but not auto-wired to caves)
- Cave-specific AI / spawning logic (consumer)
- Cave-specific lighting (uses spec 31 lighting; cave interiors get
  ambient-only via spec 31's per-biome lighting "indoor" override
  hook)
- Underground rivers (water spec 35 handles water; cave system
  handles the empty volumes)

## V1 cave architecture

```
┌──────────────────────────────────────────────────┐
│ PIPELINE (Python, offline; pipeline/caves/)      │
│                                                   │
│ [1] Cave definition input                         │
│     • Authored: hand-placed SDF blob positions    │
│       per world bundle (worlds/<w>/caves.json)    │
│     • Kernel-derived (optional): kernel module    │
│       outputs cave seed positions based on        │
│       elevation + slope (e.g. mountain caves)     │
│                                                   │
│ [2] SDF blob construction                         │
│     • Each cave = list of SDF primitives          │
│       (spheres, capsules, boxes) unioned          │
│     • Stored per-chunk (caves intersect chunks    │
│       like terrain pages do)                      │
│                                                   │
│ [3] Surface-nets meshing                          │
│     • Per chunk, voxelize the SDF + extract       │
│       mesh via surface-nets (smoother than        │
│       marching cubes; standard for caves)         │
│     • Output: mesh per chunk, only where cave     │
│       intersects                                   │
│                                                   │
│ [4] Dual-mat blend                                │
│     • Cave mesh material = rock/dirt; terrain     │
│       surface material at the interface           │
│       feathers via vertex-distance-to-cave-edge  │
└──────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│ RUNTIME (GDScript; engine/scripts/caves/)         │
│                                                   │
│ • CaveWorld scene component                       │
│ • Per-chunk cave mesh load + parenting            │
│ • Async via spec 09 (cave meshes are assets)     │
│ • Streaming budget participation                  │
│ • Collision mesh per cave chunk                   │
└──────────────────────────────────────────────────┘
```

## V1 cave definition

`worlds/<world>/caves.json`:

```json
{
  "schema_version": 1,
  "caves": [
    {
      "name": "altar_grotto",
      "anchor_xz": [-250, -250],
      "anchor_y_m": 110,
      "blobs": [
        { "type": "sphere", "center_local": [0, 0, 0], "radius_m": 8 },
        { "type": "capsule", "start_local": [0, 0, 0], "end_local": [15, -5, 0], "radius_m": 3 },
        { "type": "sphere", "center_local": [15, -5, 0], "radius_m": 6 }
      ],
      "interior_material": "alpine_rock_cave",
      "ambient_tint": [0.4, 0.4, 0.5],
      "audio_tag": "ambient/cave_drip"
    }
  ]
}
```

Blobs are local-space (anchored at `anchor_xz` + `anchor_y_m`).
Authored: a chamber + tunnel + chamber is 3 blobs. Complex caves =
more blobs.

Kernel-derived caves (deferred): a `cave_kernel` config slot
specifies "place caves at world positions where elevation > X +
slope > Y at density Z." Generator runs offline + writes to
caves.json. Schema slot only in v1.

## Mesh + collision

Per chunk that intersects any cave:
- One cave mesh (surface-nets output, ~5k tris per chunk typical)
- One collision mesh (same shape, simplified to ~500 tris)

Async loaded via spec 09's mesh loader (`request_mesh`). Cached in
addon (synced from `subjects_3d/` analog, but kept under
`engine/cave_meshes/` since they're world-bundle-coupled — content
addressed via spec 12).

## Dual-mat blend at cave entrance

Terrain shader samples per-fragment distance to nearest cave-mesh
vertex (precomputed per-chunk SDF lookup). Within an N-meter band
near a cave entrance, terrain albedo darkens toward the cave's
interior material — soft transition from outside to inside, no hard
seam.

Implementation: per-chunk world-anchored "cave proximity" texture
sampled by terrain shader. Cheap; built at offline-bake time.

## Building footprint schema (reserved, no implementation)

`worlds/<world>/buildings.json` schema reserved:

```json
{
  "schema_version": 1,
  "buildings": [
    {
      "name": "altar_hut",
      "footprint_polygon_xz": [...],
      "anchor_y_m": 120,
      "type": "hut_small",   // future Phase B kit reference
      "rotation_y_deg": 30,
      "interior_audio_tag": "ambient/wood_interior"
    }
  ]
}
```

V1: world contract accepts the file but does nothing with it
beyond schema validation. When Phase B ships, building runtime
consumes this same file — no migration needed.

## Public API (skeleton)

```gdscript
class_name CaveWorld extends Node3D

@export var world_bundle_path: String
@export var focus_camera_path: NodePath

signal cave_chunk_loaded(world_xz: Vector2, cave_name: String)
signal camera_entered_cave(cave_name: String)
signal camera_exited_cave()

func is_position_in_cave(world_pos: Vector3) -> bool
func get_nearest_cave_name(world_pos: Vector3) -> String
```

```python
# Offline mesh bake
python -m world5.caves.bake_meshes --world worlds/two_biome_demo
```

## Producer / consumer contract

- **Produces**: cave mesh per chunk; collision per chunk; cave
  proximity texture per chunk; audio tag emission; camera state
  signals
- **Consumes**: caves.json; per-cave material from biome catalog +
  spec 23; chunk grid from terrain backend

## Dependencies

- `20_TERRAIN_BACKEND` (chunk grid + per-chunk page anchoring)
- `21_TERRAIN_RENDERER` (cave meshes rendered alongside terrain;
  shader hook for cave-proximity blend)
- `22_BIOME_CATALOG` (per-biome cave material defaults)
- `23_MATERIALS_PBR` (cave interior materials)
- `33_NAV_EXPORT` (cave volumes contribute walkable mask)
- `11_CHANGE_BROADCAST` (cave-edit events publish; persistence
  subscribes for runtime add/remove)
- `39_PERSISTENCE_AND_AUTHOR_OVERRIDES` (runtime-added caves persist)

## Quality bar

- Per-chunk cave bake (offline): ≤ 5s per chunk that has caves
- Cave mesh load (runtime, via spec 09 async): ≤ 50ms
- Cave proximity shader sample: ≤ 0.1ms additional terrain frag cost
- Visual: cave entrances blend smoothly with surrounding terrain;
  no hard seams; cave interior materials read distinctly from outside
- Total cave system perf at runtime: ≤ 1.5ms p99 on high tier
  (assumes typical 3-5 caves per chunk; large caves cost more)
- World contract validates caves.json + cross-refs + buildings.json
  schema slot

## Discoverability

- **Entry point**: `CaveWorld` scene component
- **Schema**: `engine/resources/schemas/caves.schema.json` +
  `buildings.schema.json` (reserved)
- **Validator / preflight**: world contract validates blob shapes,
  anchor positions inside world extent, materials exist
- **Example**: `engine/examples/cave_example_world/` with one cave
- **Deterministic outputs**: yes — same caves.json → same baked
  meshes; cache-friendly per spec 12

## Open questions

- **Cave LOD**: do distant caves need LOD reduction? Probably yes
  for big caves; defer until measured. Schema slot for per-cave
  `max_visible_distance_m`.
- **Lighting inside caves**: spec 31 lighting needs an "indoor"
  hook — when camera enters a cave, switch lighting recipe to
  cave-appropriate (dim ambient, no skylight). Adds a per-cave
  `lighting_override` schema slot.
- **Buildings phase B/C trigger**: when do we promote? Probably when
  consumer (wizard game) demands them. Schema reserved means
  no rework when they ship.
- **Cave audio reverb**: tag emits, consumer handles. Audio hooks
  spec 34 has reverb schema slot reserved.

## References

- W4 WISHLIST "Procedural interiors" (3-phase plan)
- Surface-nets meshing literature; common cave-rendering pattern
- No Man's Sky cave system (visual reference for organic cave shape
  via SDF blobs)

## Revision history

- 2026-05-16: initial draft
