# Spec: GPU / CPU Contract

> Status: draft
> Tier: cross-cutting (Tier 0)
> Depends on: 01_MODULE_LAYOUT, 07_JOB_SYSTEM, 10_STREAMING_BUDGET
> Consumed by: terrain backend, async asset streaming, decoration runtime,
> materials, atmosphere, lighting, any system using RenderingDevice

## Purpose

W4.1 discovered that mixing GPU compute (`RenderingDevice`) and CPU
worker threads (`WorkerThreadPool`) causes silent failures and crashes
unless rules are followed strictly. The rules lived as a memory entry
(`w4_gpu_cpu_contract_2026_05_14`); the audit (2026-05-16, finding C6)
correctly flagged that **load-bearing contracts living outside the
spec set is exactly the W4.1 mistake W5's spec discipline was supposed
to prevent**. This spec elevates the rules to a Tier 0 contract.

## Non-goals

- Documenting Godot's `RenderingDevice` API itself (read Godot docs)
- Cross-platform GPU portability beyond Godot 4.5 Vulkan + Forward+
- Pre-Vulkan or Compatibility-renderer support (out of scope per spec 20)
- GPU profiling tooling (separate; future spec)
- **Pipeline-side (Python/CUDA) GPU coordination** — separate concern;
  see spec 25's `pipeline/core/gpu_mutex.py` for TRELLIS + ComfyUI
  serialization. This spec covers Godot RenderingDevice only. SA-S3.10.

## The five rules

### Rule 1: `RenderingDevice` calls happen on the render thread only

Calling `RenderingDevice.compute_list_dispatch()` or any
`RenderingDevice` mutation from inside a `WorkerThreadPool` task is
**undefined behavior**. Symptoms: silent corruption, intermittent
crashes, editor freeze on stop.

✅ **Correct**: GPU work is dispatched from a node that has render-thread
access — typically a system autoload calling `RenderingServer.call_on_render_thread`
to enqueue the compute, or running inside `_process` / `_physics_process`
which run on the main thread which holds render-thread context for
sync APIs.

❌ **Forbidden**: any `Job._execute()` (which runs on a WorkerThreadPool
thread) calling `RenderingDevice.*`.

The Job system (spec 07) reflects this: `GpuJob` (below) is the only
sanctioned bridge.

### Rule 2: `Texture2DRD` is GPU-only

GPU pages produced via `RenderingDevice.texture_create` and wrapped in
`Texture2DRD` are **render-thread resources**. CPU code (gameplay,
physics, AI, decoration placement) cannot read them without an explicit
GPU→CPU readback, which is a frame stall.

✅ **Correct**: a system that needs height for gameplay (collision, nav,
decoration placement) requests `["collision_height", "slope",
"nav_traversability"]` capabilities from `TerrainBackend`, which
computes them as CPU `PackedFloat32Array` outputs in the same compute
pass with explicit readback.

❌ **Forbidden**: trying to sample a `Texture2DRD` from GDScript pixel
fetches at runtime, or expecting `Texture2DRD.get_image()` to return
current data without an explicit readback.

### Rule 3: GPU pages live in the streaming budget GPU bucket

Spec 10 has `streaming_budget_gpu_pages` and `streaming_budget_cpu_pages`
as separate keys. Every system that allocates a `Texture2DRD`-class
resource publishes to the GPU bucket; every system that allocates a
CPU array publishes to the CPU bucket.

Mixing buckets (e.g. publishing a `Texture2DRD` allocation against
`cpu_pages`) breaks the budget accountant and lets one class of
allocation crowd out the other.

### Rule 4: GPU readbacks are explicit and accounted

A GPU→CPU readback (via `RenderingDevice.buffer_get_data` /
`texture_get_data`) is a **frame-blocking stall**. Spec 21 will budget
its cost (terrain compute: ~1-3ms for a 256² page readback). Systems
that do readbacks must:

- Declare it in their spec's quality bar
- Run the readback on a `GpuJob` (below) so it shows up in diagnostics
- Never do a readback every frame (cache-or-recompute pattern; the
  content addressing layer in spec 12 makes this cheap)

### Rule 5: GPU shutdown requires explicit free

`RenderingDevice` resources (textures, buffers, shaders) outlive
GDScript references because the GPU pipeline holds them. On shutdown,
every system that allocated GPU resources MUST call `RenderingDevice.free_rid`
on each, in dependency order (descriptor sets before buffers before
textures before shaders), inside `_exit_tree` BEFORE the autoload
unloads.

Failure mode: editor crash on F6-stop, "validation layer" errors in
log, GPU memory leak in headless tests. Same failure class as the W4.1
WorkerThreadPool shutdown issue (PITFALLS #10) but for GPU resources.

The autoload `GpuResourceTracker` (below) enforces this.

## The `GpuJob` bridge

Spec 07 JOB_SYSTEM open question is closed here:

```gdscript
class_name GpuJob extends Job

# A Job subclass that runs its _execute() on the render thread
# instead of a WorkerThreadPool worker. Provides same status/await API
# as plain Job; just dispatches differently.

func _execute() -> Variant:
    # OVERRIDE: do GPU work. SAFE to call RenderingDevice here because
    # the scheduler routes this to RenderingServer.call_on_render_thread.
    push_error("GpuJob._execute() must be overridden")
    return null
```

JobScheduler routing rule:
- `submit(job)` where `job is GpuJob` → enqueues via
  `RenderingServer.call_on_render_thread(_dispatch_gpu_job.bind(job))`
  where `_dispatch_gpu_job(j: GpuJob)` is a private scheduler method
  that calls `j._execute()` then updates `j.status`/`j.result`. SA-S1.6:
  private implementation detail; the public contract is just
  `submit(job) -> int` and `await_completion(jid)`.
- `submit(job)` where `job is Job` (not GpuJob) → enqueues to
  `WorkerThreadPool.add_task`

Both use the same `Job.Status` lifecycle, same `await_completion(jid)`,
same priority queue. Consumer code shouldn't care which one it submitted
unless it cares about thread context — and if it cares, it's writing
a system spec and should declare which type.

## The `GpuResourceTracker` autoload

```gdscript
class_name GpuResourceTracker extends Node
# Singleton autoload at /root/GpuResourceTracker

# Registration
func register(rid: RID, owner_name: String, category: String) -> void:
    """Every RID allocation registers here. category: 'texture', 'buffer',
    'shader', 'pipeline', 'descriptor_set'."""

func unregister(rid: RID) -> void:
    """Called by owner before/during their own RenderingDevice.free_rid call."""

# Query
func get_allocations(owner_name: String = "") -> Array
    # Diagnostic — what's allocated, by whom

func get_total_bytes() -> int
    # Approximate; texture/buffer sizes summed

# Shutdown
func _exit_tree() -> void:
    # Last-resort cleanup: free any RID still registered with a warning
    # log. Owners SHOULD have freed already; this is the safety net.
```

Every GPU-allocating system has this pattern:
```gdscript
func _ready():
    var rid = RenderingDevice.texture_create(...)
    GpuResourceTracker.register(rid, "terrain_backend", "texture")
    _height_texture = Texture2DRD.new()
    _height_texture.texture_rd_rid = rid

func _exit_tree():
    if _height_rid.is_valid():
        RenderingDevice.free_rid(_height_rid)
        GpuResourceTracker.unregister(_height_rid)
```

## Thread context cheat sheet

| Work | Thread | Mechanism |
|---|---|---|
| Gameplay logic (`_process`, `_physics_process`) | Main thread | Godot default |
| CPU async (kernel CPU path, asset decode) | WorkerThreadPool worker | `Job._execute()` |
| GPU compute dispatch | Render thread | `GpuJob._execute()` (routed via `RenderingServer.call_on_render_thread`) |
| GPU readback | Render thread (blocks frame) | `GpuJob._execute()` calling `buffer_get_data` |
| Signal/broadcast publish | Caller's thread (sync by default) | Spec 11 ChangeBroadcast; see S10 fix |
| Resource load (`load_threaded_*`) | Godot's resource loader thread | Wrapped by spec 09 `AssetStream` |

## What lives where in the module layout

```
engine/scripts/core/
├── Job.gd                    # spec 07
├── JobScheduler.gd            # spec 07 + this spec (GpuJob routing)
├── GpuJob.gd                  # this spec
├── GpuResourceTracker.gd      # this spec
└── ...
```

Every system spec's quality bar adds a line: **"GPU/CPU thread compliance
verified per spec 08a."**

## Public API summary

```gdscript
# Submit GPU work (runs on render thread, safe for RenderingDevice)
var jid = JobScheduler.submit(MyGpuJob.new(args))
var result = await JobScheduler.await_completion(jid)

# Register a GPU resource for tracked cleanup
GpuResourceTracker.register(rid, "system_name", "texture")

# Diagnose what's allocated
var allocs = GpuResourceTracker.get_allocations()
```

## Producer / consumer contract

- **Produces**: the five rules + `GpuJob` + `GpuResourceTracker`
- **Consumes**: all systems calling `RenderingDevice` or allocating
  GPU resources

## Dependencies

- `01_MODULE_LAYOUT` (placement)
- `07_JOB_SYSTEM` (extends Job + JobScheduler)
- `10_STREAMING_BUDGET` (GPU bucket vs CPU bucket)
- Godot 4.5 `RenderingDevice` + `RenderingServer`

## Quality bar

- 100% gut + capture-test coverage of the five rules (each rule has a
  test that violates + asserts diagnostic fires)
- `_exit_tree` of any registered GPU-allocating system drains its RIDs
  (capture test: spawn + tear down 10 times, GPU memory steady)
- `GpuResourceTracker.get_allocations()` returns truthful counts
- No `RenderingDevice` calls from any `Job._execute()` (static lint;
  CI failure if violated)
- `GpuJob` dispatch latency < 1 frame (i.e. queued this frame runs next
  frame at the latest)

## Discoverability

- **Entry point**: `GpuJob` base class; `GpuResourceTracker` autoload
- **Schema**: GDScript class defs + the five rules above
- **Validator / preflight**: lint script + gut tests at
  `engine/tests/unit/test_gpu_cpu_contract.gd`
- **Example**: `engine/examples/gpu_job_example.gd` demonstrates
  registering, dispatching, awaiting, freeing
- **Deterministic outputs**: same GPU job + same input data = same
  output (within float tolerance; GPU determinism caveats apply)

## Open questions

- **Lint script implementation**: parsing GDScript for `RenderingDevice`
  calls inside `Job._execute()` overrides — Tree-sitter? regex? defer
  to plan doc.
- **Async compute**: Godot 4.5 has limited async-compute exposure;
  if it lands more fully, do we extend `GpuJob` to express "fire and
  await without blocking the frame"? Defer.
- **Multi-GPU**: no Godot 4.5 support; not in W5 scope.

## References

- Audit finding C6 (2026-05-16): the trigger for this spec
- W4 memory entry `w4_gpu_cpu_contract_2026_05_14` — the original
  five rules (this spec elevates them to a contract)
- W4.1 PITFALLS #10 (the WorkerThreadPool shutdown analog)
- Godot 4.5 `RenderingDevice` + `RenderingServer.call_on_render_thread`
  documentation

## Revision history

- 2026-05-16: initial draft, post-audit. Elevates W4 memory entry to
  a Tier 0 spec contract.
