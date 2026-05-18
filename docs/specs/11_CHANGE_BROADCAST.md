# Spec: Change Broadcast (Dirty-Rect Pattern)

> Status: shipped (2026-05-18; promoted per spec-to-impl audit — ChangeBroadcast.gd shipped with multicast events)
> Tier: cross-cutting (Tier 0)
> Depends on: 01_MODULE_LAYOUT, 08_SPATIAL_INDEX
> Consumed by: decoration runtime (re-bake on zone change), nav export (regenerate on water/obstruction change), terrain page cache (invalidate on kernel-version change), persistence (write-back on runtime edit), audio hooks (re-evaluate tag manifest), future AI knowledge

## Purpose

A publish-subscribe pattern for "region R changed at time T because of
source S." Consumers subscribe and invalidate their own caches when
relevant changes arrive.

W4.1 missing-layer #3. No system needed it yet (W4.1 had no runtime
edits, no persistence, no live worldbuilding). But every future Tier
2 system in W5 requires it: terrain deformation invalidates nav +
decoration; persistence writes invalidate terrain page cache;
decoration zone edits invalidate decoration runtime; etc.

Built day-1 so consumers can subscribe without retrofit. Even with
zero publishers on day 1, the contract is solid.

## Non-goals

- Cross-process broadcast (single-game-runtime only)
- Event sourcing / replay (that's persistence's concern)
- Distributed event log (single machine, in-memory)
- Subscription with backpressure (consumers process events; if they
  can't keep up, that's their problem to solve)

## Public API

### `engine/scripts/core/ChangeBroadcast.gd`

```gdscript
class_name ChangeBroadcast extends Node

# Singleton autoload at /root/ChangeBroadcast

# Change event shape
class Change extends RefCounted:
    var region: Rect2          # world-XZ bounds of what changed
    var source: String         # "decoration_zone", "terrain_edit", "persistence_write", etc.
    var timestamp_ms: int      # Time.get_ticks_msec() at publish
    var metadata: Dictionary   # source-specific extra data (zone_id, edit_type, etc.)

# Publish
func publish(region: Rect2, source: String, metadata: Dictionary = {}) -> int:
    """Broadcast a change. Returns a change ID (for diagnostics).
    All current subscribers whose filter matches the region+source
    receive the Change object."""

# Subscribe
func subscribe(callback: Callable, filter: Dictionary = {}) -> int:
    """Returns subscription ID. `filter` keys:
      - sources: PackedStringArray — only events from these sources
      - region: Rect2 — only events whose region intersects this
      - dispatch: 'sync' (default) | 'async' (next-frame) | 'job' (Job-submitted)
      - both null/empty = match everything
    `callback.call(change: Change)` invoked on each matching publish.

    Dispatch modes (audit S10):
    - 'sync': callback runs inside publish() on the publisher's thread.
      Use only if callback is < 100µs (typical: just invalidate a cache
      bit, defer real work).
    - 'async': callback deferred to next frame via call_deferred. Use
      for moderate work (< 5ms aggregate per frame).
    - 'job': scheduler submits the callback as a Job (spec 07). Use
      for heavy work (e.g. decoration removing 200 instances after
      a terrain deformation crater)."""

func unsubscribe(sub_id: int) -> bool

# Query (mostly for diagnostics)
func get_recent(count: int = 100) -> Array[Change]
func get_subscribers_for_source(source: String) -> PackedInt32Array
func get_subscriber_count() -> int
```

### Usage patterns

Decoration runtime listens for zone changes:
```gdscript
func _ready():
    _sub_id = ChangeBroadcast.subscribe(
        _on_change,
        {"sources": PackedStringArray(["decoration_zone", "persistence_decoration"])}
    )

func _on_change(change: ChangeBroadcast.Change):
    # Invalidate decoration cache for any chunks intersecting change.region
    var affected_chunks = _index.query_rect(change.region)
    for chunk_key in affected_chunks:
        _refresh_chunk(chunk_key)
```

Terrain deformation publishes after a crater is applied:
```gdscript
func apply_crater(world_xz: Vector2, radius: float):
    # ... modify heightmap ...
    var crater_rect = Rect2(world_xz - Vector2(radius, radius), Vector2(radius*2, radius*2))
    ChangeBroadcast.publish(crater_rect, "terrain_edit", {"crater_radius_m": radius})
```

## Spatial index integration

Subscriptions with a `region` filter use a SpatialIndex internally
to test region intersection in O(log N) instead of O(subscribers).
The SpatialIndex dependency is purely an implementation detail; the
public API doesn't expose it.

## Producer / consumer contract

- **Producers**: any system that mutates world state in a way other
  systems care about. publish() is a contract obligation, not
  optional.
- **Consumers**: any system that caches anything derived from world
  state. subscribe() at startup, unsubscribe at _exit_tree.

## Source naming convention

Sources are lowercase snake_case strings:
- `terrain_edit` — runtime heightmap deformation
- `terrain_deformation` — alias for `terrain_edit` (deformation subsystem)
- `decoration_zone` — decoration zone add/edit/remove
- `placement_exclusion` — a system claimed a footprint that other
  placement systems should respect (see schema below)
- `path_zone` — a road/path was added; decoration + foliage should
  exclude in width buffer
- `persistence_decoration` — persistence layer wrote new decoration data
- `persistence_terrain` — persistence layer wrote new terrain data
- `water_lake_dispose` — a lake was removed
- ...

Each system's spec documents its source string(s) in the Discoverability
section.

## Source metadata schemas (SA-C3.17 fix)

Each source string has a canonical metadata payload. Schemas:

### `placement_exclusion`
Used by foliage (spec 29) + decoration (spec 28) + roads (spec 41)
to coordinate non-overlapping placement.
```
{
  "owner_system": "foliage|decoration|roads|structures",
  "exclusion_kind": "trunk_footprint|structure|path_carve|crater",
  "exclusion_categories": ["foliage", "rocks", "props", "all"],
    # subscriber checks: if any of MY category is in this list (or
    # "all"), respect the exclusion
  "exclusion_radius_m": float | null,
    # optional; if present, use as buffer beyond `region` bounds
}
```

### `terrain_deformation`
Published by spec 38 deformation. Subscribers: decoration, foliage,
nav.
```
{
  "profile": "crater_small|crater_medium|footprint|magical_impact|...",
  "world_xz": [x, z],
  "crater_radius_m": float,
  "depth_m": float,
}
```

### `path_zone`
Published by spec 41 roads at world load. Subscribers: decoration,
foliage (treat as exclusion).
```
{
  "path_name": "altar_to_village",
  "width_m": float,
  "exclusion_buffer_mult": 1.5,   // exclude in width_m * mult radius
  "surface": "dirt|stone_slab|...",
}
```

### `decoration_zone`
Published when decoration zones load or edit at runtime.
```
{
  "zone_name": "altar_grove",
  "mode": "procedural|handcrafted|hybrid|exclude",
  "change_kind": "added|edited|removed",
}
```

New source strings added by future specs MUST document their metadata
schema in their spec + add an entry here (preflight check enforces
sync).

## Dependencies

- `01_MODULE_LAYOUT` (placement)
- `08_SPATIAL_INDEX` (for region-filtered subscription indexing)

## Quality bar

- `publish()` to 100 matching subscribers: < 1ms p99
- `publish()` to 1 matching subscriber: < 100µs p99
- Region filter test (SpatialIndex hit) < 50µs per subscriber
- Memory: < 1KB per active subscription
- Recent-changes ring buffer: bounded at 1000 entries (older evicted)
- 100% gut test coverage of public API
- No subscriber receives an event after `unsubscribe()` returns

## Discoverability

- **Entry point**: `ChangeBroadcast` autoload; `publish()` / `subscribe()`
- **Schema**: `Change` class + filter Dictionary shape; both in spec
- **Validator / preflight**: gut tests verify subscribe/publish/unsubscribe
  semantics + filter correctness
- **Example**: `engine/examples/change_broadcast_example.gd` shows a
  publisher and subscriber working together
- **Deterministic outputs**: publish order is FIFO; subscriber callback
  order is registration order; deterministic given same publish sequence

## Open questions

- **Coalescing**: if 10 nearby publishes happen in one frame, should
  they coalesce into one event? Probably yes for many consumers
  (decoration doesn't care if it gets 1 or 10 events, just needs to
  invalidate). Spec choice: coalesce per source per frame; consumer
  opts out with `subscribe(..., {"coalesce": false})` if it needs
  fidelity.
- **Sync vs async dispatch**: RESOLVED (audit S10): three dispatch
  modes (`sync` / `async` / `job`) per subscribe call. Heavy
  callbacks (decoration cleanup after deformation) MUST use `job`;
  moderate use `async`; trivial (cache-bit flip) use `sync`. Each
  consumer spec declares its dispatch mode in its Discoverability
  section.
- **Persistent change log**: should the recent-changes ring be saved
  to disk for debugging post-crash? Useful but expensive. Defer.

## References

- W4.1 audit cross-cutting concern #2.C ("Dirty-rect / change-broadcast
  pattern") — this spec is the direct response
- W4.1 decoration runtime's `_refused_chunks` dict (a one-system version
  of what this spec generalizes)

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-audit (S10). Three dispatch modes
  (sync / async / job) committed; deformation-removes-decoration
  use case routed to `job` dispatch to avoid frame hitches.
- 2026-05-16: post-self-audit (SA-C3.17). Source metadata schemas
  defined for placement_exclusion, terrain_deformation, path_zone,
  decoration_zone. Future sources must document schema here.
