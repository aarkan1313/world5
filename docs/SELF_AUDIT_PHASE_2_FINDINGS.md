# W5 Phase 2 Self-Audit — Code Findings

> Self-audit of Phase 0 + Phase 2 shipped code (commits f73b4f8 →
> 1627bb5). Done by the same agent that wrote the code; bias
> acknowledged. Two lenses:
>
> 1. **Spec-vs-code adherence**: did the implementation actually
>    deliver what the spec promised?
> 2. **Cross-system integration**: are the wires (JobScheduler →
>    StreamingBudget, AssetStream → StreamingBudget, ChangeBroadcast
>    job-mode → JobScheduler) actually correct?
>
> Audit performed 2026-05-16 immediately after Phase 2 close (commit
> 1627bb5). 5 blocks matching the build flow.

## Severity legend

- **SA2-C**: critical — fix before Phase 3
- **SA2-S**: significant — worth addressing
- **SA2-M**: minor — polish

---

## Block 1 — Meta layer (Phase 0 scaffold + 2.1 test infra + 2.12 plugin wiring)

### SA2-C1.1: Plugin autoload registration silently broken for static classes

**Severity: critical** (Phase 2.12's wiring claim is partially false)
**Files: engine/plugin.gd, engine/scripts/core/Log.gd**

`engine/plugin.gd` registers 8 autoloads. But:

- **Log.gd extends `RefCounted`**, not `Node`. Godot can't autoload
  RefCounted classes — they need a Node base. Confirmed by Godot
  error log at every `--import`:
  ```
  ERROR: Request for nonexistent project setting: 'autoload/Log'
  ```
  Translation: autoload registration failed silently; the setting
  was never created.
- **World5 + QualityTiers extend Node** but use ONLY static methods.
  Registering them as autoloads creates an unused root child node
  taking up `/root/World5` and `/root/QualityTiers` paths without
  doing anything useful. `class_name` is what makes them accessible
  (Log.info, QualityTiers.get_tier) — autoload is redundant.
- **JobScheduler, AssetStream, StreamingBudget, ChangeBroadcast,
  GpuResourceTracker** legitimately ARE Node-based instances that
  need to be running for `_process` ticks + `_exit_tree` cleanup.
  THESE are correct autoload registrations.

Plugin claims to wire 8 systems; only 5 actually do anything. The
other 3 either fail (Log) or create unused empty nodes (World5,
QualityTiers).

**Why tests pass anyway**: tests instantiate Node-based systems
manually via `add_child_autofree(...)` and access static classes via
class_name globals. Neither relies on autoload. So the broken
plugin.gd doesn't surface as a test failure.

**Fix**: Remove Log/World5/QualityTiers from the autoload list.
Leave the 5 Node-based ones. Update plugin.gd comment to clarify
why static classes aren't there.

### SA2-C1.2: Verify CLI's gut layer hard-codes a Windows-specific Godot path

**Severity: critical** (any contributor / CI without Godot at the
hard-coded path gets a misleading error instead of a clean skip)
**File: pipeline/world5/verify/__init__.py:134-141**

```python
godot_bin = shutil.which("godot") or "C:/Godot/Godot_v4.5-stable_win64.exe"
if not Path(godot_bin).exists() and not shutil.which(godot_bin):
    return LayerResult(name=name, status="error", ...)
```

Issues:
1. Hard-coded Windows path is THIS user's dev machine path; not
   portable to Linux/Mac or other Windows installs.
2. The `not shutil.which(godot_bin)` second check passes an
   already-resolved absolute path back to `which`, which won't find
   it. The logic is confused.
3. Fallback when Godot is missing is `status="error"` (exit code 3).
   Better: `status="skip"` with a clear reason, like the gut_path
   check above.

**Fix**: detect Godot via `shutil.which("godot")` only (consumers add
to PATH or set a `WORLD5_GODOT_BIN` env var). If absent, return
`status="skip"` with `reason: "godot binary not on PATH"`. Document
WORLD5_GODOT_BIN override in USAGE.md.

### SA2-S1.3: Verify CLI's gut timeout branch reports wrong layer name

**Severity: significant** (misleading diagnostic on timeout)
**File: pipeline/world5/verify/__init__.py:165-173**

The `name` variable was set correctly at line 126 (`name =
"gut_real_gpu" if real_gpu else "gut"`) but the timeout branch
hard-codes `name="gut"`. Real-GPU gut timeout would be misreported.

**Fix**: change `name="gut"` to `name=name`.

### SA2-S1.4: Plugin.gd has no error handling on autoload registration

**Severity: significant**
**File: engine/plugin.gd:22-24**

`add_autoload_singleton` logs internally on failure but returns no
value. Plugin code has no programmatic way to detect failure (as
SA2-C1.1 demonstrates). Add post-registration verification:
`ProjectSettings.has_setting("autoload/<name>")` for each entry +
log error on missing. Surfaces broken-autoload bugs immediately
instead of silently.

### SA2-S1.5: Verify CLI scans pipeline/ for test_*.py but no tests live there

**Severity: significant** (dead code + cross-spec inconsistency)
**File: pipeline/world5/verify/__init__.py:79-81**

Spec 06 line 39 says pipeline tests live at `pipeline/*/tests/`.
Reality: all tests live at top-level `tests/`. The verify CLI's
`rglob("test_*.py")` branch never triggers.

**Fix**: pick a location. Recommendation: keep tests at top-level
`tests/` (simpler discovery, single test root); update spec 06 to
match; delete the dead branch.

### SA2-M1.6: pyproject.toml testpaths lists pipeline/ unnecessarily

**Severity: minor**
**File: pyproject.toml**

Same root cause as SA2-S1.5 — testpaths includes `"pipeline"` but
nothing's there. Pytest scans for nothing every run. Drop to just
`["tests"]`.

### SA2-M1.7: `worldgen5/` gitignore entry may be dead config

**Severity: minor**
**File: .gitignore (line 142-145)**

Phase 0 discovered a pre-existing `worldgen5/` user-scratch dir and
gitignored it (didn't delete; investigate-before-delete rule).
Confirmed still there. If the user has since moved/deleted it, the
gitignore entry is stale. Low priority — defer to Phase 4 review.

### SA2-M1.8: .gitattributes marks *.tres as binary; should be text

**Severity: minor**
**File: .gitattributes**

`*.tres binary` loses git's ability to diff resource changes
(`.tres` is text — YAML-like). `*.scn` IS binary (packed scene).

**Fix**: `*.tres text eol=lf` (split from `*.scn binary`).

### SA2-M1.9: setup.py CLI install_demo doesn't trigger Godot import after

**Severity: minor**
**File: pipeline/world5/setup/__init__.py:install_demo**

After creating the junction, gut tests fail with "GUT class_names
have not been imported" until Godot `--import` runs once (per
running_tests.md gotcha 1). Fresh contributors hit this on first
install.

**Fix**: after successful link, optionally run `godot --headless
--path demo --import` (with `--no-import` flag to skip). Or document
the follow-up step in the install_demo log line + USAGE.md install
recipe.

---

## Block 2 — Config + identity (2.2 Log + 2.3 QualityTiers + 2.10 ContentAddress)

### SA2-C2.1: Cross-impl parity is unverified — claimed but never bit-diffed

**Severity: critical** (the parity claim is load-bearing for spec
13 + spec 19 kernel system + future cross-impl systems)
**Files: tests/integration/test_quality_tiers_cross_impl.py,
tests/unit/test_spatial_index.py vs engine/tests/unit/test_spatial_index.gd,
tests/unit/test_content_address.py vs engine/tests/unit/test_content_address.gd**

Per spec 06: "Cross-impl parity: 0 differences between Python and
GDScript resolvers for any valid config."

What we actually shipped: Python side asserts properties X of
config A; GDScript side asserts the same properties X of config A
INDEPENDENTLY. Both pass. But there's no test that:
1. Drives Python to compute a value V1 from input I
2. Drives GDScript to compute V2 from the same I
3. Asserts V1 == V2

Specifically:
- **QualityTiers**: Python's `QualityTiers.get("high")` and GDScript's
  `QualityTiers.get_tier("high")` both read the same JSON. But the
  Python `QualityTiers.get_current()` looks at env var
  `WORLD5_QUALITY_TIER` while GDScript looks at `ProjectSettings`
  `world5/quality_tier`. **Different defaults, different override
  mechanisms**. If a consumer sets one, the other doesn't see it.
  Not cross-impl-parity at all.
- **SpatialIndex**: query_radius / query_nearest could produce
  different ordering between Python and GDScript due to subtle
  iteration order in dict/cell traversal. We assert each side is
  deterministic; we don't assert both sides produce the SAME order.
- **ContentAddress.hash_inputs**: Python uses `json.dumps(...
  default=str)`. GDScript uses `JSON.stringify`. For primitive types
  (int/float/bool/string/null) they SHOULD match. But e.g.
  Python `float("inf")` → `Infinity`, GDScript `INF` → ... unclear.
  Edge cases unverified.

Phase 2.3's spec said: "A diff-script that drives both is added in
Phase 2.11 when world_contract preflight lands." Phase 2.11 didn't
deliver it.

**Fix**: Phase 2.11.5 (or fold into Phase 3 prep): write
`tests/integration/test_cross_impl_diff.py` that:
1. Invokes Godot headless with a gut test that writes each
   GDScript-computed value to a JSON file
2. Computes the Python equivalent in pytest
3. Asserts equality
For now this means primitive-input cases only; expand as systems
need it.

### SA2-S2.2: QualityTiers Python + GDScript use different override mechanisms

**Severity: significant** (consumer sets one, runtime reads the
other → silent wrong tier)
**Files: pipeline/world5/quality_tiers.py:79-86, engine/scripts/core/QualityTiers.gd:83-91**

Python's `get_current()`:
```python
tier = os.environ.get("WORLD5_QUALITY_TIER", DEFAULT_TIER)
```

GDScript's `get_current()`:
```gdscript
if ProjectSettings.has_setting("world5/quality_tier"):
    var v: Variant = ProjectSettings.get_setting("world5/quality_tier")
```

A consumer who sets `ProjectSettings.world5/quality_tier = "ultra"`
in Godot expects the pipeline to also bake at ultra. It won't —
pipeline reads the env var which is unset, falls back to "high".

**Fix**: pick one source of truth, or have the GDScript side ALSO
read the env var (`OS.get_environment("WORLD5_QUALITY_TIER")`) and
have the Python side ALSO check `project.godot` for the setting
(harder; project.godot parsing). Recommend: env var is primary;
ProjectSettings is a Godot-side convenience that also writes to
env. Document in USAGE.md.

### SA2-S2.3: Log.fatal() promises set_crash_on_fatal() that doesn't exist

**Severity: significant** (docstring lies)
**File: engine/scripts/core/Log.gd:66-67**

```gdscript
## Log at FATAL level. Implies engine cannot continue. Triggers
## push_error; consumer can opt-in to OS.crash on fatal via
## set_crash_on_fatal(true).
```

The `set_crash_on_fatal()` method does not exist on Log.gd. Spec 16
says FATAL "triggers shutdown if possible." We log + push_error but
don't crash, and we don't expose a way to opt into crashing.

**Fix**: either build `set_crash_on_fatal(bool)` + check inside
`fatal()`, OR remove the docstring claim. Simplest: drop the
promise; fatal logs + push_errors, consumer is expected to handle
shutdown via signals.

### SA2-S2.4: Log.set_output("file:...") truncates on every session

**Severity: significant** (each session loses prior log file)
**File: engine/scripts/core/Log.gd:103**

```gdscript
_file_handle = FileAccess.open(path, FileAccess.WRITE_READ)
```

`FileAccess.WRITE_READ` truncates the file on open. Spec 16 says
"append-mode" implicit. A dev running multiple sessions loses all
log history except the most recent.

**Fix**: use `FileAccess.READ_WRITE` (which doesn't truncate),
then `file.seek_end()` before first write. Or check if Godot 4.5
has a dedicated append mode (recent versions added `FileAccess.WRITE_BACKEND`
options — verify).

### SA2-S2.5: Log emit goes through Godot's print() which may interfere with JSON mode

**Severity: significant** (machine-readable output mode may not be
machine-readable)
**File: engine/scripts/core/Log.gd:131**

```gdscript
if _output == "stdout" or _output == "both":
    print(line)
```

Godot's `print()` writes to stdout but with implementation details:
multi-arg behavior, line wrapping, etc. For human format this is
fine. For JSON format (one object per line), `print()` may add
formatting that breaks line-based parsing.

**Fix**: in JSON mode, use `printraw(line + "\n")` (raw, no
formatting). Test by piping `Log.set_format("json")` output to
`jq -c .` and verifying each line parses.

### SA2-S2.6: Python log facade WARN+ to stderr; GDScript Log doesn't differentiate

**Severity: significant** (cross-impl divergence)
**File: pipeline/world5/log.py:108 vs engine/scripts/core/Log.gd:131**

Python:
```python
stream = sys.stderr if level >= Level.WARN else sys.stdout
print(line, file=stream)
```

GDScript: always `print(line)` (stdout). WARN/ERROR additionally
call `push_warning`/`push_error` for Godot debugger highlighting,
but the stdout line goes to stdout.

So a log-aggregator that watches stderr for WARN+ sees Python warnings
but not GDScript warnings. The two log streams are NOT bit-compatible
for stderr/stdout split — only for line content.

**Fix**: either GDScript also routes WARN+ to stderr (Godot has
`printerr()` for this), or Python stops splitting + uses stdout
exclusively. Document the chosen approach in spec 16.

### SA2-S2.7: ContentAddressStore._file_hash_cache is per-instance not per-process

**Severity: significant** (perf regression in multi-pipeline scenarios)
**File: pipeline/world5/content_address.py:80**

```python
self._file_hash_cache: dict[tuple[str, float, int], str] = {}
```

If two pipelines (e.g. texture pipeline + decoration pipeline) both
instantiate `ContentAddressStore(...)` and both consume the same
model file, the file gets hashed twice (5+ GB files = noticeable).

**Fix**: lift to module-level cache (or use functools.lru_cache on
hash_file_input). Trade-off: globals are harder to reason about in
tests. Probably worth it for multi-GB model files.

### SA2-S2.8: ContentAddress canonical JSON may diverge between Python and GDScript on edge values

**Severity: significant** (related to SA2-C2.1)
**Files: pipeline/world5/content_address.py:101, engine/scripts/core/ContentAddress.gd:_canonical_json**

Python: `json.dumps(resolved, sort_keys=True, separators=(",", ":"), default=str)`
GDScript: hand-rolled `_canonical_json` calling `JSON.stringify(val)`

Edge cases:
- **NaN / Infinity**: Python `default=str` converts → "nan" / "inf";
  GDScript `JSON.stringify(NAN)` returns "null" by default.
- **Very large ints**: Python keeps as JSON int; GDScript may
  truncate to float.
- **Empty dict/array**: Python `{}` / `[]`; GDScript `{}` / `[]` —
  match.
- **Nested order**: Python sorts at every level (because
  `default=str` recurses into native dict/list); GDScript's
  `_canonical_json` sorts ONLY top-level keys. **Nested dicts hash
  differently** between sides for the same input.

The nested-dict issue is a real bug. ContentAddress stamps with
nested config dicts (which texture pipeline + biome catalog will
both have) would silently produce different cache keys between the
two languages.

**Fix**: GDScript `_canonical_json` recursively sorts nested dict
keys. Add a parity test that hashes a nested dict in both languages
+ asserts equality. (Resolves SA2-C2.1 partially.)

### SA2-M2.9: Log padding uses .left(N).rpad(N) but .left() returns empty for short strings on Godot 4.5

**Severity: minor (visual format glitch only)**
**File: engine/scripts/core/Log.gd:139**

```gdscript
var system_padded := system.left(_SYSTEM_NAME_WIDTH).rpad(_SYSTEM_NAME_WIDTH)
```

`String.left(N)` returns the leftmost N chars, but if string is
shorter than N, it returns the WHOLE string (not padded). Then
`.rpad(N)` pads to N. So this works for short names but if a system
name exceeds 15 chars it gets truncated cleanly. Good.

BUT: there's a subtle issue — `system.left(15)` on a 15-char string
should return the full string; on a 16-char string returns first 15.
Tested empirically: Phase 2.4 test_job_system.gd output shows
`[job_scheduler  ]` (15 chars: "job_scheduler" = 13 + 2 pad). Works.

**No bug, but worth a one-line test** asserting the padding for
edge cases (empty string, exactly-15-char string, >15-char string).

### SA2-M2.10: World5 migration_path stub returns [to_v] always

**Severity: minor (documented as stub; not a bug)**
**File: engine/scripts/core/World5.gd:84**

```gdscript
static func migration_path(from_v: String, to_v: String) -> Array:
    if from_v == to_v:
        return []
    return [to_v]
```

Docstring acknowledges it's a stub. Real impl lands in Phase 14
(persistence). Worth flagging: there's no migration scripts dir
yet (`pipeline/migrations/` exists empty). The stub is honest;
documenting here so future-me doesn't forget.

### SA2-M2.11: hash_inputs cache key uses `str(path.resolve())` — case-sensitive on Windows but mtime/size differentiate

**Severity: minor (subtle)**
**File: pipeline/world5/content_address.py:114**

```python
cache_key = (str(path.resolve()), stat.st_mtime, stat.st_size)
```

On Windows, `C:\Models\model.bin` and `c:\models\MODEL.bin` resolve
to the same file but `str(path.resolve())` may return different
case strings depending on input. Cache misses on same file accessed
via different case. Not wrong; just slower.

**Fix (optional)**: `str(path.resolve()).lower()` on Windows; or
use `path.stat().st_ino` (inode) as key on Unix, leave Windows as-is.
Low priority — bake throughput dominates.

---

## Block 3 — Cross-cutting primitives (2.4 Job + 2.5 GpuJob + 2.6 SpatialIndex)

### SA2-C3.1: JobScheduler iterates _jobs.keys() while erasing — undefined behavior

**Severity: critical** (silent data corruption under specific
timing)
**File: engine/scripts/core/JobScheduler.gd:225-230**

```gdscript
# Evict ancient terminal jobs
var now := Time.get_ticks_msec()
for jid in _jobs.keys():
    var job: Job = _jobs[jid]
    if job.is_done() and (now - job.completed_at_ms) > _RESULT_EVICTION_TTL_MS:
        _jobs.erase(jid)  # ← mutating during iteration
```

GDScript Dictionary iteration during erase is undefined (same as
Python). Could miss adjacent entries OR re-visit erased keys OR
crash. The 60-second TTL means this fires rarely + only on long-
running scenes, so tests don't catch it. But under sustained load
this bug WILL surface.

Same pattern at line 212-223 (reap loop) — iterates `_running.keys()`
while erasing. Same bug.

**Fix**:
```gdscript
var to_evict: Array = []
for jid in _jobs.keys():
    if _jobs[jid].is_done() and ...:
        to_evict.append(jid)
for jid in to_evict:
    _jobs.erase(jid)
```

Apply to both eviction loop AND reap loop.

### SA2-S3.2: JobScheduler dispatches ONE job per frame — bottleneck

**Severity: significant** (60 jobs/sec max throughput)
**File: engine/scripts/core/JobScheduler.gd:204-209**

```gdscript
for p in [Job.Priority.CRITICAL, Job.Priority.HIGH, ...]:
    if _queues[p].size() > 0:
        var jid: int = _queues[p].pop_front()
        _dispatch(jid)
        break  # one per tick
```

At 60 FPS that's 60 dispatches/sec. Spec 07 quality bar promises
"scheduler tick is < 1ms for 1000-job queues" — but if 1000 jobs
arrive simultaneously, draining them takes ~17 seconds at 60Hz.

Phase 4 terrain MVP will submit MANY chunk-bringup jobs simultaneously
(decoration meshes per chunk × residency ring). 60 jobs/sec ceiling
will hurt.

**Fix**: dispatch up to N jobs per tick (N = min(active_workers_target,
queue_depth, _RATE_LIMIT)). Default N = 4 (matches typical WTP
worker count). Tier-aware: high tier allows more concurrent dispatch.

### SA2-S3.3: _enumerate_all_queued called per-pending-job → O(N²) per tick

**Severity: significant** (perf cliff at scale)
**File: engine/scripts/core/JobScheduler.gd:191-200**

```gdscript
for jid in _jobs.keys():
    var job: Job = _jobs[jid]
    if job.status != Job.Status.PENDING:
        continue
    if job.id in _enumerate_all_queued():  # ← O(N) inside O(N) loop
        continue
    ...
```

With 1000 pending jobs that's 1M operations per tick. Same scale as
SA2-S3.2.

**Fix**: maintain a `_queued_set: Dictionary` of jid → true alongside
the per-priority queue arrays. O(1) membership check.

### SA2-S3.4: get_total_completed walks all jobs every call

**Severity: significant (perf)**
**File: engine/scripts/core/JobScheduler.gd:137-142**

```gdscript
func get_total_completed() -> int:
    var count := 0
    for jid in _jobs.keys():
        if _jobs[jid].status == Job.Status.COMPLETED:
            count += 1
    return count
```

O(N) per call. If diagnostics HUD polls this each frame, frame budget
takes a hit at scale.

**Fix**: maintain a counter incremented in the place that promotes
status to COMPLETED (or read from a publish to StreamingBudget).

### SA2-S3.5: GpuJob bridge doesn't check JobScheduler.is_shutting_down()

**Severity: significant**
**File: engine/scripts/core/GpuJob.gd:34-50**

`_run_on_render_thread` checks `is_cancelled()` but not
`JobScheduler.is_shutting_down()`. The docstring example tells users
to check both. The bridge itself only checks one. So during shutdown,
in-flight GpuJobs that haven't been individually cancelled will
still execute `_execute()` on the render thread — potentially after
the rest of the engine has torn down.

**Fix**: bridge also checks shutdown. Or document that GpuJob
authors MUST check both inside their `_execute()` override.

### SA2-S3.6: GpuJob dispatch is fire-and-forget; no completion signal

**Severity: significant**
**File: engine/scripts/core/JobScheduler.gd:251-253**

```gdscript
if job is GpuJob:
    _running[job_id] = -1
    RenderingServer.call_on_render_thread(Callable(job, "_run_on_render_thread"))
```

`RenderingServer.call_on_render_thread` queues the callback for the
next render frame. JobScheduler immediately marks `_running` and
moves on. The next tick's reap loop (line 215-219) checks
`job.is_done()` — but `is_done()` only returns true after
`_run_on_render_thread` sets `status = Status.COMPLETED`. Until
then, the job sits in `_running` indefinitely.

In tests this works because the render thread ticks every frame. In
shutdown scenarios where render thread stops processing first, GpuJobs
could be stuck "running" forever (until the eviction TTL fires 60s
later).

**Fix**: add a wallclock timeout to the reap loop for GpuJob entries.
If `_running` has held a GpuJob for > N seconds (e.g. 5s), mark as
FAILED with "GpuJob did not complete on render thread".

### SA2-S3.7: GpuJob test test_scheduler_routes_gpu_job_via_bridge is timing-fragile

**Severity: significant** (test reliability)
**File: engine/tests/unit/test_gpu_cpu_contract.gd:54-61**

```gdscript
func test_scheduler_routes_gpu_job_via_bridge() -> void:
    var job := _MarkerGpuJob.new()
    var jid := _scheduler.submit(job)
    for i in range(5):
        await get_tree().process_frame
    assert_true(job.did_run, "GpuJob executed via render thread")
```

5 frame-wait is arbitrary. Under CI load or heavier scenes it could
fail intermittently. Test passes today (~3-5 frames is enough on dev
machine) but flake risk.

**Fix**: replace fixed frame wait with explicit wait-for-status loop
with a wallclock cap (e.g. 1 second, fail if not done).

### SA2-S3.8: Test cancel_pending_job hand-waves race

**Severity: significant** (the test isn't actually testing)
**File: engine/tests/unit/test_job_system.gd:120-130**

```gdscript
func test_cancel_pending_job() -> void:
    var job := _SimpleJob.new(42)
    job.priority = Job.Priority.LOW
    var jid := _scheduler.submit(job)
    var cancelled := _scheduler.cancel(jid)
    # Race: if already dispatched, fall back to cooperative cancel
    if job.status == Job.Status.PENDING or job.status == Job.Status.CANCELLED:
        assert_true(cancelled or job.status == Job.Status.CANCELLED)
```

The test acknowledges the race but doesn't FORCE a deterministic
scenario. To genuinely test "cancel a pending job before dispatch":
- Pause the scheduler before submit (e.g. set `_shutting_down = true`,
  submit, cancel, then unset) — but that's hacky
- OR test via direct internal state mutation

**Fix**: refactor test to use a deterministic scenario; the current
`if-else` covers behavior without verifying any specific path.

### SA2-S3.9: SpatialIndex query_radius / query_rect / query_nearest order may differ Python vs GDScript

**Severity: significant** (cross-impl parity claim)
**File: pipeline/world5/spatial_index.py vs engine/scripts/core/SpatialIndex.gd**

Python iterates `for cell in self._cells_overlapping_radius(...)`
in dict-insertion order. GDScript iterates the same — but Dictionary
insertion order in GDScript Godot 4.x is documented as insertion-
ordered, same as Python 3.7+. SHOULD match for the same insert
sequence.

Tested only via independent assertions per side. Not cross-diffed.
Related to SA2-C2.1 (cross-impl unverified).

**Fix**: write a true cross-impl test — driver script that runs
both sides on the same insert sequence + asserts identical output
arrays.

### SA2-M3.10: Job.duration_ms returns running duration when started but not completed

**Severity: minor** (intentional, but worth documenting)
**File: engine/scripts/core/Job.gd:89-94**

```gdscript
func duration_ms() -> int:
    if started_at_ms == 0:
        return 0
    if completed_at_ms == 0:
        return Time.get_ticks_msec() - started_at_ms
    return completed_at_ms - started_at_ms
```

Returns a "live" duration for in-flight jobs. Useful for
diagnostics (long-running job HUD) but consumer code that uses
`duration_ms()` to compute "did this job take X ms" gets monotone-
increasing values until completion. Document the behavior.

### SA2-M3.11: SpatialIndex Vector2 used for XZ but Godot convention is Vector2 = XY

**Severity: minor (naming convention)**
**File: engine/scripts/core/SpatialIndex.gd**

Spec 08 says "2D XZ" but Vector2 has fields `.x` and `.y`. Throughout
SpatialIndex we use `point.y` to mean Z. Consistent within the
class but every consumer needs to remember Vector2.y = world Z.

**Fix (optional)**: define a `WorldXZ` wrapper type or alias. Or
just document at top of file: "Vector2(x, z) used throughout; Vector2.y
is world Z (not world Y)." Low priority; comment is enough.

### SA2-M3.12: _ring_cells generates duplicates for ring 0

**Severity: minor**
**File: pipeline/world5/spatial_index.py:_ring_cells (Python) + engine/scripts/core/SpatialIndex.gd:_ring_cells (GDScript)**

Both implementations yield `(cx, cz)` for ring=0 then return.
Subsequent rings yield perimeter cells. No duplicates within a ring.

But `query_nearest` iterates rings 0, 1, 2, ... — a cell at the
corner of ring 2 also appears in rings adjacent? Let me re-check:

Ring N (N>0) yields: top + bottom rows (ix in [-N..N], iz = ±N) +
left + right cols (excluding corners, iz in [-N+1..N-1], ix = ±N).
Corners only at the top/bottom rows. So ring 1 yields 8 cells, ring
2 yields 16, etc. No duplicates across rings. **OK.**

But the candidates list itself may double-add an item if my ring
generation has off-by-one. Sanity test exists (test_query_nearest_k3)
verifies first 2 are {1, 5} and 3rd is 2 — passes. No bug, just
worth a comment that ring generation is exclusive.

### SA2-M3.13: GpuResourceTracker._exit_tree clears allocations dict without freeing RIDs

**Severity: minor (defensive only — owners should have freed)**
**File: engine/scripts/core/GpuResourceTracker.gd:_exit_tree**

```gdscript
func _exit_tree() -> void:
    if _allocations.is_empty():
        ...
        return
    Log.warn(SYSTEM_NAME, "shutdown — leaked RIDs detected", ...)
    # We do NOT call RenderingDevice.free_rid here because the
    # RenderingDevice itself may already be torn down.
    _allocations.clear()
```

The tracker logs leaked RIDs but doesn't free them. Documented as
intentional (RD may be torn down). True, but leaks ARE leaks —
Godot's renderer will report validation-layer errors at process
exit.

**Fix**: probably none — owners must free their own. But add to
the warning message: "owners must free RIDs in their own _exit_tree
BEFORE GpuResourceTracker tears down."

---

## Block 4 — The wired triangle (2.7 AssetStream + 2.8 StreamingBudget + 2.9 ChangeBroadcast)

### SA2-C4.1: ChangeBroadcast._dispatch iterates _subs.keys() while sync callbacks may unsubscribe

**Severity: critical** (crash / undefined behavior under realistic
use)
**File: engine/scripts/core/ChangeBroadcast.gd:120-133**

```gdscript
func _dispatch(change: Change) -> void:
    for sid in _subs.keys():  # ← iteration
        var sub: _Sub = _subs[sid]
        ...
        match sub.dispatch:
            "sync":
                _invoke_sync(sub, change)  # ← may call unsubscribe()
```

A subscriber in "sync" mode whose callback calls `unsubscribe(...)`
(common pattern: "fire once then auto-remove") mutates `_subs`
mid-iteration. GDScript Dictionary iteration during erase is
undefined behavior. Could crash or skip subsequent subs.

The `alive` flag at line 33 LOOKS like defensive guarding for this
case, but `unsubscribe` also calls `_subs.erase(sub_id)` at line 87,
so the `alive` check is moot — the iteration finds keys that no
longer exist.

**Fix**:
```gdscript
var sids := _subs.keys()  # snapshot
for sid in sids:
    if not _subs.has(sid):
        continue  # was unsubscribed during this dispatch
    var sub: _Sub = _subs[sid]
    ...
```

Plus: `unsubscribe` should ONLY set `alive = false` if dispatch is
in progress; the erase happens at end of dispatch. (Use a re-entry
counter.) Or: `_subs` is only cleaned in `_tick`, not on `unsubscribe`.

### SA2-C4.2: ChangeBroadcast sync callbacks that error kill the dispatch loop

**Severity: critical** (one bad subscriber poisons the whole event)
**File: engine/scripts/core/ChangeBroadcast.gd:148-150**

```gdscript
func _invoke_sync(sub: _Sub, change: Change) -> void:
    if sub.callback.is_valid():
        sub.callback.call(change)
```

If `callback.call(change)` raises (push_error inside, or accesses a
freed Node, etc.), the exception propagates up through `_dispatch`,
killing the iteration. Remaining subscribers don't get the event.

GDScript doesn't have try/catch as such; you can guard via `Callable.bindv`
return checking, or by wrapping in a deferred call. For sync mode the
risk is real.

**Fix**: catch errors per-callback. Either:
- Wrap each `_invoke_sync` in a Callable that handles errors
  (Callable.call_deferred won't propagate; could use that always for
  sync mode at the cost of "sync" no longer meaning "in publish()'s
  call stack")
- Document that sync subscribers MUST NOT throw; promote async/job
  for any callback that could fail

Recommend: change "sync" mode to use `call()` wrapped in error-
handling via push_error catch. Add a test that asserts a throwing
callback doesn't prevent others from running.

### SA2-S4.3: StreamingBudget.get_budget reparses QualityTiers on every call

**Severity: significant** (perf at scale)
**File: engine/scripts/core/StreamingBudget.gd:79-88**

`get_budget()` calls `QualityTiers.get_current()`. Internally
QualityTiers does cache the loaded JSON, but the per-call lookup
still walks ProjectSettings + the cached dict. Per
`is_over_budget()`-per-frame HUD pattern, that's many dict lookups
per frame.

Worse: `get_headroom()` calls `get_budget()` + `get_total_usage()`.
`is_over_budget()` calls `get_headroom()`. Per-frame HUD = 3 chained
calls.

**Fix**: cache the budget at first call OR on QualityTiers tier
change. Invalidate via signal when tier changes (tier changes are
rare — once per session typically).

### SA2-S4.4: AssetStream._enforce_budget may evict the just-promoted request

**Severity: significant** (consistency bug)
**File: engine/scripts/core/AssetStream.gd:272-275**

```gdscript
_cache[req.path] = resource
_touch_lru(req.path)
_cache_bytes += req.size_bytes
_enforce_budget()  # ← may evict req.path if it's the LRU
```

If `_cache_bytes` exceeds budget after adding this request,
`_enforce_budget` evicts the LRU. But `_touch_lru` just put the new
item at the END (most-recent). The LRU front is some earlier item,
so usually fine. BUT: if the cache had only this item and budget is
0, `_enforce_budget` evicts the new item — `req.resource` is set
but `_cache.has(req.path)` is false. Subsequent `is_ready(path)`
returns false; `get_resource(req_id)` returns the resource.

The test `test_set_cache_budget_evicts_lru` (line 90 of
test_asset_stream.gd) hits this exact case + asserts the
inconsistency works as expected (`is_ready` false, get_resource
still returns the resource).

The semantics are subtle: the resource is "still held by
JobScheduler/caller" via the req, but no longer "cached for reuse."

**Fix**: document the semantics + add a comment. Or change behavior
to "if we just evicted ourselves, restore + log warning." The
current behavior is technically correct (LRU bound respected) but
surprising.

### SA2-S4.5: AssetStream._estimate_bytes returns 4096 for unknown types

**Severity: significant** (cache accounting drifts)
**File: engine/scripts/core/AssetStream.gd:_estimate_bytes**

A .tres file might be 200 bytes on disk but accounted as 4KB. With
many small Resource loads, `_cache_bytes` overestimates by 10-50x.
LRU evicts prematurely.

**Fix**: for Resource type fallback, use the actual disk file size
via `FileAccess.get_file_as_bytes(path).size()` — but that re-reads
the file. Or use `Resource.get_meta("__bytes")` if available. Or
accept the 4KB minimum + document.

### SA2-S4.6: AssetStream has no _exit_tree cleanup

**Severity: significant** (resource lifecycle opacity)
**File: engine/scripts/core/AssetStream.gd**

No `_exit_tree` override. On shutdown the cache resources release
via refcount decrement (when AssetStream node frees), but:
- No log of "cache had N items at shutdown" diagnostic
- No explicit cancel of in-flight ResourceLoader requests (they
  complete on a Godot thread we don't own)

JobScheduler has a proper drain. AssetStream should too, even if
simple.

**Fix**: add `_exit_tree` that logs in-flight count + cache count
at shutdown.

### SA2-S4.7: StreamingBudget integration with JobScheduler / AssetStream tested only individually

**Severity: significant** (cross-system wire untested)
**Files: tests don't cover the JobScheduler→StreamingBudget→AssetStream chain**

Phase 2.8 added `_publish_to_budget` to JobScheduler + AssetStream.
The lazy lookup `get_node_or_null("/root/StreamingBudget")` means
tests (without autoload) silently no-op. We have:
- JobScheduler unit tests (no StreamingBudget)
- AssetStream unit tests (no StreamingBudget)
- StreamingBudget unit tests (no Job/AssetStream wiring)

We do NOT have a test that:
1. Spawns JobScheduler + StreamingBudget + AssetStream as siblings
2. Submits jobs / loads assets
3. Asserts StreamingBudget.get_system_usage("job_scheduler")
   reflects the load
4. Asserts StreamingBudget.get_system_usage("asset_stream") reflects
   the cache

So the "publishes to active_jobs" claim is untested end-to-end.

**Fix**: add an integration test
`engine/tests/integration/test_tier0_wired.gd` that exercises the
wired chain. ~50 lines of test code; high value.

### SA2-S4.8: ChangeBroadcast job-mode falls back to async without scheduler

**Severity: significant (silent degradation)**
**File: engine/scripts/core/ChangeBroadcast.gd:163-168**

```gdscript
func _invoke_job(sub: _Sub, change: Change) -> void:
    var scheduler := get_node_or_null("/root/JobScheduler")
    if scheduler == null:
        # Tests without autoload — degrade to async
        if sub.callback.is_valid():
            sub.callback.call_deferred(change)
        return
```

In test contexts this is convenient. In production: if for any
reason the JobScheduler autoload isn't registered (e.g. user
disabled the plugin partially), job-mode subscribers silently degrade
to async — which has different semantics (no priority, no deps,
no cancellation).

A real consumer might rely on job mode for the priority queue.
Silent fallback hides the failure.

**Fix**: log a WARN once per session when fallback triggers. Or
make fallback configurable (`subscribe(..., {"dispatch": "job",
"fallback": "async|error"})`).

### SA2-S4.9: AssetStream.cancel doesn't cancel Godot's load_threaded request

**Severity: significant** (resource leak risk)
**File: engine/scripts/core/AssetStream.gd:cancel**

```gdscript
func cancel(req_id: int) -> bool:
    ...
    # Godot's ResourceLoader doesn't expose cancel; mark our wrapper
    # cancelled + drop the resource when it eventually arrives.
    req.status = Status.FAILED
    req.error = "cancelled"
    _path_to_id.erase(req.path)
    return true
```

The Godot side keeps loading. When complete, `_tick`'s
`load_threaded_get_status` shows LOADED but our req is already
FAILED, so `_promote_to_ready` never runs. The resource is loaded
into Godot's threaded-load cache + sits there until next request
or until Godot's own GC.

Probably fine — Godot's resource cache has its own LRU. But worth
documenting + maybe explicitly calling `load_threaded_get` (which
removes from Godot's internal threaded-load buffer) on cancel.

**Fix**: on cancel, ALSO call `ResourceLoader.load_threaded_get(req.path)`
(discard result) to clean up Godot's threaded-load state.

### SA2-M4.10: StreamingBudget history ring memory unbounded if publish frequency exceeds limit

**Severity: minor**
**File: engine/scripts/core/StreamingBudget.gd:55, 161-164**

Rate limit (line 49-52) coalesces high-frequency publishes from the
SAME system. But if 100 systems each publish exactly once per
100ms, history grows at 1000 entries/sec → fills the 600-entry ring
in 0.6 seconds. The ring caps OK but oldest entries get evicted
fast; "60s history" claim in the comment becomes "0.6s history"
under load.

**Fix**: `_record_history` only fires when totals actually CHANGE.
Skip if `get_total_usage()` equals previous snapshot.

### SA2-M4.11: ChangeBroadcast get_recent has no docstring; behavior at count > history is unclear

**Severity: minor**
**File: engine/scripts/core/ChangeBroadcast.gd:93-96**

Returns full history if count >= history.size(). Comment-only
behavior; consumers may pass `get_recent(100)` and get 1000
entries unexpectedly. Document or change to `min(count,
_HISTORY_MAX)`.

### SA2-M4.12: AssetStream Priority enum unused in dispatch logic

**Severity: minor (dead-by-design or genuinely dead?)**
**File: engine/scripts/core/AssetStream.gd:43**

`Priority` enum is defined + accepted in `request(path, priority)`
+ stored on `_Request.priority`. But `_tick`'s polling loop
processes requests in dictionary insertion order, NOT priority
order. CRITICAL and BACKGROUND get the same dispatch order.

Spec 09 implies priority matters for the LOAD start order (high
priority loads first). With Godot's `load_threaded_request` we
don't have control — Godot's loader manages its own queue. So our
`priority` field is essentially ignored.

**Fix**: either remove the Priority enum (we can't honor it), OR
honor it by NOT submitting low-priority loads until high-priority
ones complete. The latter changes semantics significantly. Recommend
remove + document in spec 09 that asset load priority isn't honored
(Godot limitation).

---

## Block 5 — world_contract preflight + cross-system integration

### SA2-S5.1: logging_lint `stripped = line.split("#")[0]` corrupts strings containing `#`

**Severity: significant (false positive risk)**
**File: pipeline/world5/world_contract/logging_lint.py:65**

```python
stripped = line.split("#")[0]
```

A GDScript line like `Log.info("test", "color #ff00aa pattern")`
gets stripped to `Log.info("test", "color ` — the lint then doesn't
see the full `print(`/etc call AFTER the `#`. Could produce false
NEGATIVES (missing real violations after `#` in string).

Symmetric false positive: `Log.info("test", "println # then print()")`
would get stripped to `Log.info("test", "println ` and no match.
False negative here, not false positive — so this specific path is
"safe" in the wrong direction (misses violations).

True false-positive risk: a string literal containing `print(`
would be caught. E.g. `var msg = "see print() for output"`. Lint
flags as `direct print() call`. Today no such string exists in our
code but it WILL bite eventually.

**Fix**: better tokenizer that handles strings. Simplest: regex for
`(?<!["'])\bprint\(` (negative lookbehind for quote). Best: actual
GDScript tokenizer. For now: add `# LINT_OK` suppress on first
false-positive when it happens; document the limitation.

### SA2-S5.2: logging_lint exempts "tests" and "examples" but only scans engine/scripts/ which doesn't have those subdirs

**Severity: significant (dead exemption, possibly hiding bugs)**
**File: pipeline/world5/world_contract/logging_lint.py:36-40, 51, 53**

```python
_EXEMPT_DIRS = {"addons", "tests", "examples"}
...
for path in scripts.rglob("*.gd"):  # scripts = repo_root / "engine" / "scripts"
    if any(part in _EXEMPT_DIRS for part in path.parts):
        continue
```

`engine/scripts/` doesn't have `tests/` or `examples/` subdirs.
Those live at `engine/tests/` and `engine/examples/` (siblings to
`engine/scripts/`). The lint NEVER scans either, so exemption is
moot.

If we ever add `engine/scripts/examples/` or `engine/scripts/tests/`,
they'd be exempt — which is probably what was intended.

**Fix**: either delete the `tests`/`examples` exemptions (dead code)
OR extend the scan to `engine/tests/` and `engine/examples/` (so
exemptions become meaningful). Current spec 16 says "no print
outside Log.gd"; tests legitimately need print sometimes. Recommend:
extend scan to all engine/, keep exemptions.

### SA2-S5.3: world_contract validate() doesn't propagate exception details from individual checks

**Severity: significant**
**File: pipeline/world5/world_contract/__init__.py:97-104**

```python
try:
    issues = check_fn(root, world_path, tier)
    all_issues.extend(issues)
except Exception as e:
    all_issues.append(Issue(
        severity=Severity.ERROR,
        code=f"{prefix}.check_crashed",
        message=f"Check '{prefix}' raised: {e}",
    ))
```

Catches `Exception` but doesn't include traceback. Debugging a
crashed check is hard — just "Exception X" without where it came
from.

**Fix**: include `traceback.format_exc()` in the issue details.

### SA2-S5.4: world_contract has NO integration test that all 3 checks run together end-to-end on real repo

**Severity: significant**
**File: tests/unit/test_world_contract.py:test_validate_real_repo_passes**

There IS one test that calls `validate()` against the real repo and
asserts it passes. Good. But:
- Doesn't enumerate which checks ran
- Doesn't assert that EACH check (allowlist, doc_health,
  logging_lint) ran (a check could silently skip with no error)
- Doesn't verify the registry mechanism works (only the result)

**Fix**: add test that asserts `get_registered()` has the expected
3 entries + each ran in the validate() call (count of issues from
each prefix, even if 0).

### SA2-C5.5: Cross-system wires are present but UNTESTED end-to-end

**Severity: critical** (system claim is unverified)
**Files: JobScheduler.gd, AssetStream.gd, ChangeBroadcast.gd, StreamingBudget.gd**

The "wired triangle" finding from Block 4 SA2-S4.7 + the wires
verified by grep in Block 5 lead to the same conclusion: every
cross-system integration is **architecturally present** (lazy
autoload lookup) but **never tested in integration**. Phase 2.8's
commit message says:
> JobScheduler.gd: _publish_to_budget uncommented; resolves /root/
> StreamingBudget lazily so tests w/o autoload silently no-op.

Tests don't have autoloads → wires silently no-op. **The
integration claim has zero test coverage.**

Phase 2.6+ shipped 224 tests. Zero of them exercise the wire.

**Fix**: `engine/tests/integration/test_tier0_wired.gd` (~50 lines):
1. Spawn StreamingBudget + JobScheduler + AssetStream + ChangeBroadcast
   as siblings under the test root
2. Inject `_streaming_budget_node` directly into Job/Asset (the
   inject-via-property hatch Phase 2.8 mentioned in inline comments)
3. Submit a Job → assert StreamingBudget.get_system_usage(
   "job_scheduler")["active_jobs"] reflects it
4. Load an asset → assert StreamingBudget.get_system_usage(
   "asset_stream")["asset_cache_mb"] > 0
5. ChangeBroadcast.publish with dispatch=job → assert JobScheduler
   receives + executes the wrapped Job

If this test passes, the wires are real. If not, we have silent
broken integration shipping as "Phase 2 done."

### SA2-S5.6: world_contract exit code logic in main() has bug

**Severity: significant**
**File: pipeline/world5/world_contract/__init__.py:139-144**

```python
return 0 if result.passed else (2 if any(i.severity == Severity.WARNING for i in result.issues) and args.strict else 1)
```

If `strict=True` and there are warnings (but no errors), `passed`
is False per `validate(strict=True)` logic. The expression evaluates
to `2 if (has_warning and args.strict) else 1` — for strict-with-
warnings = 2. OK.

But: errors exit 1, warnings-in-strict-mode exit 2. Spec 06 exit
codes say:
- 0: all clear
- 1: test failure
- 2: preflight failure

Preflight failures should ALL exit 2, not split errors=1 / warnings=2.
The current code mismatches the spec.

**Fix**: `return 0 if result.passed else 2` (all preflight failures
= 2).

### SA2-M5.7: world_contract checks don't take a tier-specific path

**Severity: minor**
**Files: all 3 check fns**

Each check function has signature `(repo_root, world_path, tier)`.
None actually USES the tier param. So tier-aware preflight isn't
tier-aware.

Not wrong per spec (no spec currently demands tier-aware preflight)
but documenting: when tier-aware checks land (e.g. macro_albedo
required at visibility_ship_distance > 2km PER SA-S3.7), the
infrastructure is here but not exercised.

### SA2-M5.8: world_contract docstring shows "engine/.godot" in allowlist comment but it's `.godot` (hidden, auto-ignored)

**Severity: minor (cosmetic)**
**File: pipeline/world5/world_contract/godot_root_check.py**

The allowlist correctly skips hidden dirs (line 62: `if name.startswith(".")`).
`.godot` cache lives at `demo/.godot/` and is auto-excluded. Just
flag that the docstring / comments don't make this clear.

### SA2-M5.9: world_contract has no `infos` (Severity.INFO) accessor on ContractResult

**Severity: minor**
**File: pipeline/world5/world_contract/__init__.py:50-53**

```python
@property
def errors(self) -> list[Issue]:
    return [i for i in self.issues if i.severity == Severity.ERROR]

@property
def warnings(self) -> list[Issue]:
    return [i for i in self.issues if i.severity == Severity.WARNING]
```

No `.infos` property. doc_health emits INFO for long specs
("advisory"). Consumers wanting to filter for advisory only have to
filter manually.

**Fix**: add `.infos` property (3 lines).

---

## Summary

### Findings tally

| Severity | Count |
|---|---|
| Critical (SA2-C) | 5 |
| Significant (SA2-S) | 24 |
| Minor (SA2-M) | 13 |
| **Total** | **42** |

### The 5 criticals (must fix before Phase 3)

1. **SA2-C1.1** Plugin autoloads broken — Log fails to register
   (RefCounted base), World5 + QualityTiers register useless empty
   nodes. Only 5 of 8 "autoloads" work.
2. **SA2-C1.2** Verify CLI hard-codes Windows Godot path — breaks
   any other contributor / CI.
3. **SA2-C2.1** Cross-impl parity is CLAIMED but never bit-diffed.
   Python and GDScript could produce different outputs for the same
   input.
4. **SA2-C3.1** JobScheduler iterates `_jobs.keys()` while erasing —
   undefined behavior; will bite at scale.
5. **SA2-C4.1 + SA2-C4.2** ChangeBroadcast `_dispatch` iterates
   `_subs` while sync callbacks may unsubscribe; one bad subscriber
   kills the whole event.
6. **SA2-C5.5** Cross-system wires (Job→Budget, AssetStream→Budget,
   ChangeBroadcast job-mode→JobScheduler) untested end-to-end. The
   integration claim has zero test coverage.

(5 numbered but 6 entries — SA2-C4.1 and SA2-C4.2 share the same
root cause: dispatch loop fragility.)

### Patterns observed

- **"Lazy autoload lookup" worked for fast unit-test iteration but
  left integration completely untested.** Every cross-system wire is
  architecturally present but practically unverified. This is the
  same pattern as the spec-side audit (SA-C2.3 file-input hashing,
  SA-C3.17 placement_exclusion schema): we claim correctness, we
  don't measure it.

- **Iteration-while-mutating bug appears 3-4 times** (JobScheduler
  twice, ChangeBroadcast once, no false positives in SpatialIndex /
  AssetStream / StreamingBudget). A pattern worth promoting to a
  pitfall (`meta-3`: "GDScript Dictionary iteration during erase is
  undefined; snapshot keys first").

- **Cross-impl parity is asserted independently per side, never
  diffed.** QualityTiers / SpatialIndex / ContentAddress all have
  this exact same hole. Need a true cross-impl driver script.

- **Phase 2.12's autoload registration was never validated** beyond
  "verify --full passes" — and verify --full doesn't actually require
  autoloads to work (each test instantiates manually). So broken
  autoloads sailed through.

- **Test count vs test value**: 224 tests sounds rigorous; 5
  criticals slipped through because tests pass for the wrong
  reasons (manual instantiation bypasses the autoload bug; lazy
  lookup bypasses the integration bug).

### Highest-leverage fixes

In order of "biggest payoff per minute":

1. **Write the wired-triangle integration test** (SA2-C5.5). ~50
   lines. Catches SA2-C1.1 + SA2-C4.1 + SA2-C4.2 + the integration
   gap simultaneously. **Do this first** — running it will likely
   surface MORE bugs we don't even know about.
2. **Fix JobScheduler / ChangeBroadcast iteration bugs** (SA2-C3.1
   + SA2-C4.1). Mechanical; ~15 lines total across 3 sites.
   Promote to pitfall meta-3.
3. **Fix plugin autoload list** (SA2-C1.1). Remove static-only
   classes from `_AUTOLOADS`. 3-line edit. Update docstring.
4. **Fix verify CLI Godot lookup** (SA2-C1.2). 10 lines. Adds env
   var override + skip-on-missing instead of error.
5. **Write cross-impl diff test** (SA2-C2.1). 100-200 lines. Drive
   both Python + GDScript with same inputs, assert outputs match.
   Probably surfaces SA2-S2.8 nested-canonical-JSON bug.

### What this audit can't see

- **Runtime behavior under sustained load**: 1000+ jobs, sustained
  ChangeBroadcast traffic, AssetStream cache churn at 100 req/sec.
  Tests cover single-shot correctness; not load.
- **Performance claims**: spec 07 says scheduler tick < 1ms for
  1000 jobs. Spec 10 says publish < 50µs. We have ZERO perf tests.
- **Race conditions between WTP workers + main thread**: tested
  only indirectly via the cancel/dep tests; not stressed.
- **Whether the 8 autoloads actually CAN coexist** (priority
  conflicts, double-_ready, etc.) — we've never opened the demo
  project as a normal Godot session.

## Revision history

- 2026-05-16: initial Phase 2 self-audit immediately after Phase 2
  close commit `1627bb5`. 5 blocks, 42 findings.






