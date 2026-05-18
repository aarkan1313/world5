# Spec: Async Asset Streaming

> Status: shipped (2026-05-18; promoted per spec-to-impl audit — AssetStream.gd shipped + integrated with Job system)
> Tier: cross-cutting (Tier 0)
> Depends on: 01_MODULE_LAYOUT, 07_JOB_SYSTEM
> Consumed by: decoration runtime (mesh load), terrain backend (texture array load), audio hooks consumer-side, future foliage card load, future nav region load

## Purpose

Wraps Godot's `ResourceLoader.load_threaded_request` + `load_threaded_get`
in a shared primitive. Every async asset load in W5 goes through here.

W4.1 missing-layer #2. Decoration mesh loading hit the wall in R14d:
synchronous `ResourceLoader.load()` per mesh on the main thread caused
visible hitches when chunks were brought up. Each consumer that ever
needed async loading would have re-implemented the same plumbing
(request queue, in-flight dedup, cancellation, retry-on-fail, GC).

The async-streaming layer is also where **mesh import format** gets
hidden — Godot's GLB default is PackedScene; we want ArrayMesh for
decoration meshes. The streaming layer handles the conversion once
so consumers always get the resource type they expect.

## Non-goals

- Network asset loading (Godot ResourceLoader abstracts this if needed;
  we don't add it)
- Asset generation on demand (separate concern; pipeline produces,
  streaming loads)
- Hot-reload of changed assets at runtime (W4.1 Sprint R5 deferred;
  separate concern)

## Public API

### `engine/scripts/core/AssetStream.gd`

```gdscript
class_name AssetStream extends Node

# Singleton autoload at /root/AssetStream

enum Status { NOT_LOADED, LOADING, READY, FAILED }
enum Priority { CRITICAL, HIGH, NORMAL, LOW, BACKGROUND }

# Request
func request(path: String, priority: Priority = Priority.NORMAL) -> int:
    """Begin loading the resource at `path`. Returns a request ID.
    Idempotent: requesting the same path again returns the same ID
    while the original is in flight."""

# Query
func get_status(req_id: int) -> Status
func get_resource(req_id: int) -> Resource  # null until READY; cached after
func get_error(req_id: int) -> String       # populated when FAILED
func is_ready(path: String) -> bool         # cache lookup; cheap
func get_cached(path: String) -> Resource   # cache lookup; null if not READY

# Await
func await_ready(req_id: int) -> Resource:
    """Coroutine: yield until status is READY (or FAILED, raises).
    Useful for chunk-bring-up patterns."""

# Cancellation
func cancel(req_id: int) -> bool

# Eviction
func evict(path: String) -> bool            # frees cached resource if not in use
func set_cache_budget_mb(mb: int) -> void   # LRU eviction past budget
func get_cache_usage_mb() -> int

# Diagnostics
func get_in_flight_count() -> int
func get_cache_count() -> int
func get_stats() -> Dictionary  # for streaming budget contract integration
```

### Resource-type adapters

For mesh files specifically, the streaming layer hides the
PackedScene → ArrayMesh extraction:

```gdscript
func request_mesh(path: String, priority: Priority = Priority.NORMAL) -> int:
    """Same as request() but the resource returned is guaranteed to be
    a Mesh (not a PackedScene). Equivalent to W4.1's
    DecorationMeshCache._extract_mesh_from_scene but built once."""
```

Other type adapters (`request_texture`, `request_texture_2d_array`,
`request_audio_stream`) added as consumers need them.

## Architecture

### Internal flow
1. `request(path, priority)` called
2. If `path` is already in cache (READY): return existing request ID
3. If `path` is in flight: return existing request ID (dedup)
4. Otherwise: assign new request ID, push to priority queue, kick
   off `ResourceLoader.load_threaded_request(path)`
5. Background tick (every frame): poll `load_threaded_get_status` for
   each in-flight request; promote completed to READY; cache the result
6. LRU eviction runs when `cache_usage_mb > budget` (set via
   `set_cache_budget_mb`)

### Integration with Job system
A request is NOT a Job (different mechanism — Godot's loader runs on
its own thread pool). But: consumers can wrap an AssetStream request
in a Job dependency:

```gdscript
class BringUpChunkJob extends Job:
    var mesh_req_ids: Array[int]   # AssetStream IDs
    func _execute() -> Variant:
        for rid in mesh_req_ids:
            AssetStream.await_ready(rid)   # coroutine yield
        # ... build chunk ...
```

This is how chunks bring up cleanly: mesh requests start early, the
chunk-build Job awaits them, and consumers see "chunk ready" as a
single event.

### Pre-warm pattern (the R14d-3 problem)
For predictive loading (e.g. neighbor chunks about to come into
residency), consumers call `request(path, Priority.BACKGROUND)` early.
The asset gets loaded at low priority; when the chunk actually needs
it, the cache hit is instant.

```gdscript
# In residency manager:
for neighbor_chunk in get_neighbors(current_chunk):
    for mesh_id in neighbor_chunk.mesh_ids:
        AssetStream.request(mesh_path_for(mesh_id), AssetStream.Priority.BACKGROUND)
```

## Producer / consumer contract

- **Produces**: cached resources (Mesh, Texture, etc.) on demand;
  status events on request lifecycle.
- **Consumes**: request paths + priority hints. Cache budget signal
  from streaming-budget contract.

## Dependencies

- `01_MODULE_LAYOUT` (placement)
- `07_JOB_SYSTEM` (for await patterns; not a hard dep but the
  recommended consumer pattern)
- Godot 4.5 `ResourceLoader.load_threaded_*` APIs

## Quality bar

- Request → ready latency for a small mesh (< 1 MB): < 50ms p99 on
  target hardware
- Request → ready latency for a 5 MB texture: < 200ms p99
- Cache hit returns in < 1ms
- No main-thread hitch > 5ms during any single request lifecycle
- LRU eviction never frees a resource that's currently in use (refcount
  check)
- Concurrent requests: 100 simultaneous in-flight, no deadlock
- 100% gut test coverage of public API

## Discoverability

- **Entry point**: `AssetStream` autoload + `request(path, priority)`
- **Schema**: GDScript class signature in this spec; example consumers
  in `engine/examples/asset_stream_examples.gd`
- **Validator / preflight**: gut test suite at
  `engine/tests/unit/test_asset_stream.gd`
- **Example**: chunk bring-up pattern documented in spec + working
  scene at `engine/examples/asset_stream_chunk_bringup.tscn`
- **Deterministic outputs**: yes — same request path produces same
  resource; cache hits are stable; LRU eviction order is deterministic
  given access pattern

## Open questions

- **Cache budget default**: probably tied to streaming-budget contract
  (spec 10) — `set_cache_budget_mb(QualityTiers.get_current()['asset_cache_mb'])`.
  Decide during streaming budget spec.
- **Hot-reload of changed files**: deferred (W4.1 Sprint R5 was the
  hot-reload sprint, never built). When picked up, ResourceLoader
  invalidation hooks integrate here.
- **Type adapter set**: starts with `request_mesh`; others added on
  demand. No "support every Godot Resource type up front."
- **Failure retry policy**: failed loads stay FAILED (no auto-retry).
  Consumer can retry by submitting a new request. Reconsider if it
  bites.

## References

- W4.1 plan 19 R14d-1/2/3 (the spec that surfaced this need)
- W4.1 memory entry: GLB import-as-Mesh issue (R14d-1) — handled
  here by `request_mesh()` adapter

## Revision history

- 2026-05-16: initial draft
