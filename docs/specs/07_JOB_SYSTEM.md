# Spec: Job System

> Status: shipped (2026-05-18; promoted per spec-to-impl audit — Job + JobScheduler + GpuJob shipped as autoloads + tested)
> Tier: cross-cutting (Tier 0)
> Depends on: 01_MODULE_LAYOUT, 03_PILLARS
> Consumed by: terrain backend, async asset streaming, decoration runtime, nav, audio hooks, every async system

## Purpose

W5's wrapper over Godot's `WorkerThreadPool`. Every long-running async
operation in the engine goes through this — no direct
`WorkerThreadPool.add_task` calls from system code.

Built because W4.1 PITFALLS #10 (shutdown spam + editor crash from
workers outliving shared deps) is **structural**: every consumer of
`WorkerThreadPool` re-implemented the same bookkeeping (drain queue at
`_exit_tree`, null-guard the worker function, track in-flight task IDs,
manage cancellation manually). Multiple consumers got it subtly wrong
in different ways. The fix is to centralize once.

Additionally W4.1's WTP lacked: priority queues (terrain ring refresh
should pre-empt distant decoration mesh load), cancellation tokens
(replaced by ad-hoc "supersede" booleans per system), dependency graphs
(chunk-bring-up tasks should wait for their mesh-load tasks).

## Non-goals

- Cross-machine job scheduling (single-runtime only)
- GPU job orchestration (that's the GPU/CPU contract — Job system covers
  CPU-thread work; GPU compute runs on Godot's render-thread queue, not
  here)
- Real-time job system (best-effort priority; no hard deadlines)

## Public API

### `engine/scripts/core/Job.gd`

```gdscript
class_name Job extends RefCounted

enum Priority { CRITICAL, HIGH, NORMAL, LOW, BACKGROUND }
enum Status { PENDING, RUNNING, COMPLETED, FAILED, CANCELLED }

var id: int                  # assigned by JobScheduler
var name: String             # for diagnostics ("terrain_ring_3_refresh")
var priority: Priority
var status: Status
var dependencies: Array[int] # other job IDs that must complete first
var result: Variant          # set when status becomes COMPLETED
var error: String            # set when status becomes FAILED

# Set by submitter:
func _execute() -> Variant:
    # OVERRIDE: do the work. Return the result. Throw on error.
    # MUST check JobScheduler.is_shutting_down() periodically + return early.
    push_error("Job._execute() must be overridden")
    return null
```

### `engine/scripts/core/JobScheduler.gd`

```gdscript
class_name JobScheduler extends Node

# Singleton autoload at /root/JobScheduler

# Submission
func submit(job: Job) -> int:
    """Submit a job; returns its id. Job runs when its deps complete + a
    worker is free + priority allows."""

# Query
func get_status(job_id: int) -> Job.Status
func get_job(job_id: int) -> Job  # null if not found / already evicted

# Awaiting
func await_completion(job_id: int) -> Variant:
    """Block (yield, actually — coroutine-style) until job completes; return result.
    Raises on FAILED or CANCELLED."""

# Cancellation
func cancel(job_id: int) -> bool:
    """Request cancellation. Job's _execute() must cooperate by checking
    is_cancelled() periodically. Returns true if cancellation honored."""

func is_cancelled(job_id: int) -> bool

# Shutdown
func is_shutting_down() -> bool
    """Workers MUST check this and bail early. Set during scene tree
    teardown."""

# Diagnostics
func get_queue_depth() -> Dictionary  # {priority -> count}
func get_running_count() -> int
func get_total_completed() -> int
func get_active_workers() -> int      # WTP workers currently running our jobs
```

### StreamingBudget integration (audit S6)

JobScheduler publishes the running + queued job count to
StreamingBudget as the `active_jobs` budget key (spec 10), debounced
to once per 100ms:

```gdscript
# Inside JobScheduler:
func _on_state_change():
    StreamingBudget.publish("job_scheduler",
        {"active_jobs": get_running_count() + _get_queued_count()})
```

The publish is automatic — consumer systems don't need to handle it.
Spec 10's `active_jobs` ceiling enforcement gates scheduler from
accepting new jobs above limit (via priority-aware backpressure).

### Submission patterns

Simple one-shot:
```gdscript
class MyJob extends Job:
    var input: float
    func _init(x: float):
        input = x
        name = "compute_x"
        priority = Priority.NORMAL
    func _execute() -> Variant:
        if JobScheduler.is_shutting_down(): return null
        return expensive_compute(input)

var jid = JobScheduler.submit(MyJob.new(42.0))
var result = await JobScheduler.await_completion(jid)
```

With dependency:
```gdscript
var load_jid = JobScheduler.submit(LoadMeshJob.new("rocks/boulder_01"))
var build_job = BuildChunkJob.new(...)
build_job.dependencies = [load_jid]
var build_jid = JobScheduler.submit(build_job)
```

## Producer / consumer contract

- **Produces**: `Job.Status` updates over time; results on completion;
  shutdown signal during teardown.
- **Consumes**: Jobs (instances of subclasses of `Job` base) with
  `_execute()` overridden.

## Dependencies

- `01_MODULE_LAYOUT` (placement at `engine/scripts/core/`)
- Godot 4.5 `WorkerThreadPool` (underlying primitive)

## Quality bar

- `_exit_tree` of JobScheduler drains all pending + running jobs
  cleanly (no orphan worker errors, no editor F6-stop crash)
- Cancellation honored within 50ms (cooperative; jobs must check
  `is_cancelled()` periodically — enforced by lint/convention)
- Priority queue actually preempts: a CRITICAL job submitted while
  many NORMAL jobs are queued runs next (after currently-running
  workers complete their slices)
- Dependency edges respected; a job NEVER starts before its
  dependencies complete
- 100% gut test coverage of public API
- Performance: submitting a job + getting its ID is < 100µs;
  scheduler tick (priority sort + dispatch) is < 1ms for 1000-job queues

## Discoverability

- **Entry point**: `JobScheduler` autoload + `Job` base class at
  `engine/scripts/core/`
- **Schema**: GDScript class definitions are the schema; example
  job subclasses in `engine/examples/job_examples.gd`
- **Validator / preflight**: gut test suite at
  `engine/tests/unit/test_job_system.gd` validates contract; CI
  fails if behavior drifts from spec
- **Example**: `engine/examples/job_example_chunk_bringup.gd` shows
  a real multi-job dependency chain (mesh-load → chunk-build → MMI-bind)
- **Deterministic outputs**: jobs run in priority order; tie-broken by
  submission order. Cancellation timing is best-effort (cooperative).

## Open questions

- **Priority dynamics**: should priority be adjustable after submission
  (e.g. a distant-chunk decoration job gets bumped to HIGH when the
  player walks toward it)? Probably yes for one specific use case
  (residency-driven priority); design for it but ship without it.
- **Job result eviction**: how long do completed jobs sit in scheduler
  memory? Probably evict after `await_completion` returns OR after a
  TTL. Spec choice: evict on await OR after 60s, whichever first.
- **GPU compute integration**: RESOLVED (audit C6) by spec 08a
  GPU/CPU contract. `GpuJob` subclass exists, routed via
  `RenderingServer.call_on_render_thread`. Same status/await API as
  plain Job.

## References

- W4.1 PITFALLS #10 (the structural failure this spec fixes)
- W4.1 retrospective Lesson 7 (test infra gap; W5 gut coverage closes
  the runtime-class hole)
- Godot 4.5 WorkerThreadPool docs (underlying primitive)
- Memory entry on the shutdown-stress harness pattern in W4.1
  (informs the `_exit_tree` drain implementation)

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-audit (S6, C6). JobScheduler auto-publishes to
  StreamingBudget `active_jobs` key (debounced). GPU compute
  integration resolved by spec 08a GPU/CPU contract.
