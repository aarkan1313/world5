# Spec: Runtime Terrain Deformation

> Status: draft
> Tier: 2 (world)
> Depends on: 20_TERRAIN_BACKEND, 21_TERRAIN_RENDERER,
> 07_JOB_SYSTEM, 11_CHANGE_BROADCAST, 28_DECORATION, 29_FOLIAGE,
> 33_NAV_EXPORT
> Consumed by: consumer game (calls deformation API on game events
> like spells, explosions, footprints)

## Purpose

Player or event-caused heightfield edits at runtime: craters,
footprints, explosions, magical impacts. Engine ships the deformation
API + handles cleanup of decoration/foliage inside the affected area.

V1 is **ephemeral**: deformations persist for the session, disappear
on world reload. No save-state integration (consumer wires
persistence via spec 39 if they need it).

V1 is also **destructive**: rocks/trees inside the deformation
radius are destroyed (removed). No "turn into burning tree" hooks;
consumer adds those via change broadcast subscription if they want.

## Non-goals

- Persistence (consumer wires via spec 39 if needed)
- Burning / damaged / partial-destruction overrides (consumer concern;
  subscribe to change broadcast, override behavior)
- GPU vertex deformation for animation (different problem; this is
  topology, not animation)
- Real-time terrain authoring tools / world editor (consumer concern)
- Mass-deformation events (1000 simultaneous craters) — spec assumes
  ≤10 deformations per second, ≤50 active in scene

## V1 architecture (SA-S5.12: GPU-direct, no per-deformation readback)

```
consumer calls Deformation.apply_crater(world_xz, profile)
  ↓
[1] DeformationController computes affected chunks (typically 1-4)
  ↓
[2] GpuJob submitted (per spec 08a): deform_chunk_<cx>_<cz>
    • Compute shader directly modifies the GPU overlay texture
      (per spec 20 overlay layer); NO CPU readback of the base
      heightmap (audit-found readback-per-deformation would cost
      ~1-3 ms × N deformations/sec = visible hitching)
    • For gameplay-side height queries (collision, nav), a SEPARATE
      throttled readback runs at most once per N frames (e.g. 4Hz)
      batching all pending deformations into one readback
    • Marks chunk dirty for re-mesh on render thread
  ↓
[3] Splat painter Job submitted in parallel
    • Paints "disturbed earth" or "scorch" decal in splat texture
      over crater radius
    • Splat painter writes to runtime splat override layer
  ↓
[4] ChangeBroadcast.publish(crater_rect, "terrain_deformation",
                            { "profile": "crater_small", "world_xz": ... })
  ↓
[5] Decoration runtime + foliage runtime subscribe to
    "terrain_deformation" events with dispatch="job" (audit S10:
    heavy cleanup MUST go through Job system to avoid frame hitch).
    On receipt, the Job queries their spatial index for instances
    in the rect, removes them, rebuilds the affected MMIs.
  ↓
[6] Nav export (if subscribed) marks chunk dirty for re-export
    (consumer may rebuild navmesh; engine doesn't auto-rebuild)
```

## Deformation profiles

Crater profiles are reusable shapes that describe how heightmap +
splat are affected:

`engine/resources/deformation_profiles.json`:

```json
{
  "schema_version": 1,
  "profiles": {
    "crater_small": {
      "radius_m": 3.0,
      "depth_m": 0.6,
      "falloff_curve": "smoothstep",
      "splat_overlay": "decals/disturbed_earth",
      "audio_tag": "oneshot/impact_small"
    },
    "crater_medium": {
      "radius_m": 8.0,
      "depth_m": 1.5,
      "falloff_curve": "smoothstep",
      "splat_overlay": "decals/scorch_medium",
      "audio_tag": "oneshot/explosion_medium"
    },
    "footprint": {
      "radius_m": 0.4,
      "depth_m": 0.08,
      "falloff_curve": "linear",
      "splat_overlay": null,
      "audio_tag": null
    },
    "magical_impact": {
      "radius_m": 5.0,
      "depth_m": 0.0,
      "falloff_curve": "smoothstep",
      "splat_overlay": "decals/arcane_burn",
      "audio_tag": "oneshot/arcane_zap"
    }
  }
}
```

The profile contract is simple — consumer picks a profile by name
and calls the API. Custom profiles can be added per-world or per-
consumer.

## Public API (skeleton)

```gdscript
class_name DeformationController extends Node
# Autoload at /root/Deformation

func apply_crater(world_xz: Vector2, profile: String) -> int:
    """Returns a deformation_id for diagnostics; engine handles
    cleanup."""

func apply_at(world_pos: Vector3, profile: String) -> int:
    """Same; convenience for 3D-space callers."""

func clear_all() -> void
    """Removes every applied deformation (resets to baked state)."""

signal deformation_applied(id: int, world_xz: Vector2, profile: String)

func get_active_deformation_count() -> int
func get_active_deformations() -> Array[Dictionary]
func query_deformations_in_rect(rect: Rect2) -> Array[Dictionary]:
    """SA-S4.12: spatial query for deformations affecting a region.
    Used by persistence (spec 39) on save/load + by nav re-export
    triggers."""
func revert_deformation(id: int) -> bool:
    """SA-S4.12: revert a specific deformation by id (undo).
    Used by persistence load (if saved state has fewer deformations
    than current runtime state) + gameplay rewind features."""
```

```python
# No pipeline side; deformation is runtime-only
```

## Runtime override layers

The terrain backend (spec 20) provides a runtime override mechanism:
heightmap pages have a "base + overlay" pattern. Base is the kernel-
generated heightmap (unchanged); overlay is a sparse delta from
deformations.

When camera moves out of residency, overlays for departed chunks are
discarded (ephemeral). When chunk re-enters residency, the overlay is
gone — original kernel heightmap shows.

This is what makes "ephemeral" cheap: no save logic, no migration,
no diff tracking across sessions. Persistence (spec 39) extends this
later if consumer needs.

## Asset displacement (destroy in-place)

V1 default: anything inside `crater_rect` (decoration meshes, foliage
trees) gets removed when the deformation event publishes.

```gdscript
# In DecorationManager._on_change(change):
if change.source == "terrain_deformation":
    var crater_radius = change.metadata.get("radius_m", 5.0)
    var crater_center = Vector2(change.region.position) + change.region.size * 0.5
    var affected_ids = _spatial_index.query_radius(crater_center, crater_radius)
    for id in affected_ids:
        _remove_instance(id)
```

Same pattern in foliage runtime. Consumer can subscribe to the same
event with `Priority.HIGHER` and pre-empt — e.g. mark trees "burning"
before engine removes them.

## Producer / consumer contract

- **Produces**: deformed heightmap overlay; splat overlay; change
  broadcast event; asset cleanup signals
- **Consumes**: deformation API calls from consumer code; profile
  catalog

## Dependencies

- `20_TERRAIN_BACKEND` (runtime heightmap + splat overlay support)
- `21_TERRAIN_RENDERER` (consumes deformed pages; visible result)
- `07_JOB_SYSTEM` (chunk deformation runs as a job; not on render thread)
- `11_CHANGE_BROADCAST` (publishes terrain_deformation events;
  decoration/foliage/nav subscribe)
- `28_DECORATION` + `29_FOLIAGE` (subscribe + cleanup)
- `33_NAV_EXPORT` (subscribes for invalidation; consumer rebuilds
  navmesh if needed)

## Quality bar

- `apply_crater` returns immediately; deformation visible within ≤
  200ms (async chunk rebuild)
- Per-deformation cost: ≤ 1 frame of main-thread work (everything
  else on Job system)
- 50 active deformations: no perf degradation beyond linear in
  active count
- Visible: smooth crater shape, no jagged edges, splat overlay
  paints correctly, affected decoration/foliage cleanly removed
- World contract validates deformation_profiles.json
- gut coverage of API + event publishing

## Discoverability

- **Entry point**: `Deformation.apply_crater(world_xz, profile)`
- **Schema**: deformation_profiles.json shape above
- **Validator / preflight**: world contract validates profile catalog
- **Example**: `engine/examples/deformation_example.tscn` shows a
  click-to-crater interaction
- **Deterministic outputs**: yes — same world_xz + profile + base
  terrain → same deformed result (but ephemeral, so different across
  sessions if events differ)

## Open questions

- **Footprints accumulating across paths**: consumer-driven (e.g.
  player walks repeatedly) could accumulate hundreds of footprints
  fast. v1 caps total active deformations (`max_active = 50`); older
  fade out. Schema slot for `lifetime_s` per profile (footprints
  expire faster than craters).
- **Crater + decoration cleanup priority**: if a decoration instance
  has a "destroyed mesh swap" registered via change broadcast, does
  the swap run BEFORE engine removes it? Yes — change broadcast spec
  11's priority subscription handles this. Consumer subscribes with
  higher priority, mutates the event metadata to signal "I handled
  it, don't auto-remove."
- **Persistence integration timing**: spec 39 (persistence) is
  responsible. Hook = subscribe to terrain_deformation event,
  serialize affected overlays. Already supported by change broadcast.
- **Pre-baked craters as authored content**: a world bundle could
  ship "this region has a crater field, generated at bake time."
  Schema slot in world bundle for `baked_deformations` — runtime
  applies on world load. Defer; v1 only does runtime-event-driven.

## References

- W4 WISHLIST "Runtime terrain deformation — meteors, explosions,
  footprints" (the source design)
- The pattern is standard in destruction-enabled games (BF, Just Cause)

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-self-audit (SA-S4.12, SA-S5.12, SA-S10). Added
  `query_deformations_in_rect` + `revert_deformation` API. Removed
  per-deformation CPU readback (GPU-direct compute shader writes
  overlay; gameplay reads via throttled batched readback at 4Hz).
  ChangeBroadcast subscribers (decoration, foliage) use `job` dispatch
  per audit S10.
