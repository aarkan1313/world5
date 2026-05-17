# Pitfalls: Meta + Tier 0

> Bugs in build / test / packaging / docs / lint / Tier 0 primitives.
> See `pitfalls_INDEX.md` for the symptom-lookup table.

## #1 — Static methods named `get`/`load`/`set`/`free`/etc. shadow Godot builtins

**Symptom**: GDScript parser fails with `Cannot call non-static
function "get()" from the static function ...` or `Too few arguments
for "load()" call. Expected at least 1 but received 0.` when calling
a class-level static method.

**Cause**: GDScript's base `Object` class has builtin methods named
`get(property)`, `set(property, value)`, `load(path)` (Resource
loader), `free()`, `call(method, args)`, and several others. A
`class_name` extending Node (or any Object) inherits these as
instance methods. A `static func get(...)` in your class shadows
the inherited instance `get()` and the parser flags the conflict.

The compiler doesn't error at definition — it errors at the CALL
site, on every test that uses the static method.

**Fix**: rename the static method to avoid collision:
- `get(x)` → `get_tier(x)` / `get_item(x)` / `get_entry(x)`
- `load(path)` → `load_config(path)` / `load_file(path)`
- `set(k, v)` → `set_entry(k, v)`
- `call(name, args)` → `invoke(name, args)`

The Python mirror of the same class is unaffected (Python has no
such builtin shadowing). Cross-impl tests should call the
language-appropriate name.

**What didn't work**: Trying to call `MyClass.get(x)` from gut test
code — parser fails. Trying to call it from within the class's own
methods — parser fails. Renaming the test's local variable — no
effect; the static method itself is what's broken.

**Diagnostic**: gut output shows tests as "Risky: Did not assert"
(zero asserts ran) because every `before_each` / test method crashes
on parse. Look at the raw godot stderr for "SCRIPT ERROR: Parse
Error: Too few arguments for ..." messages.

**Related**: spec 13 QUALITY_TIERS (first hit; renamed `load` →
`load_config`, `get` → `get_tier`). Every cross-impl static class
in Tier 0 + later should check for builtin collisions.

**First hit**: 2026-05-16 (Phase 2.3, QualityTiers).

---

## #2 — `--headless` mode disables RenderingDevice

**Symptom**: `RenderingServer.get_rendering_device()` returns null
when Godot was launched with `--headless`. Any
`RenderingDevice.*` call from a gut test crashes. Tests that try to
exercise compute shaders / textures / buffers fail to run.

**Cause**: Godot's `--headless` flag is shorthand for
`--display-driver headless --audio-driver Dummy`. The `headless`
display driver only supports the `dummy` rendering driver, which
provides no GPU pipeline. Intentional (servers without GPUs need to
run); not a bug.

**Fix**: For tests that need RenderingDevice, launch with
`--display-driver windows --rendering-driver vulkan` (or `d3d12`)
instead of `--headless`. A real (briefly visible) Vulkan window
appears + closes when the script exits. The verify CLI's `--full`
mode does this automatically for `test_*_real_device.gd` files.

**Pattern in test code** (so the same file passes under both modes):
```gdscript
var rd: RenderingDevice = RenderingServer.get_rendering_device()
if rd == null:
    pending("RenderingDevice unavailable; run with --display-driver windows")
    return
# ... real GPU work ...
```

**What didn't work**:
- `--display-driver dummy --rendering-driver vulkan` — invalid combo
- `RenderingServer.create_local_rendering_device()` — depends on
  main device existing; returns null in headless too

**Diagnostic**: `RenderingServer.get_rendering_device() == null` is
the definitive check.

**Related**: spec 06 Layer 3a (real GPU gut), spec 08a GpuJob, W4
memory entry `godot_headless_null_viewport`.

**First hit**: 2026-05-16 (Phase 2.5, user-prompted; real GPU tests
shipped Phase 2.6).

---

## #3 — GDScript Dictionary iteration during erase is undefined

**Symptom**: Code that iterates `for k in dict.keys():` and calls
`dict.erase(k)` (or `dict.erase(some_other_key)`) inside the loop
may silently skip entries, double-process entries, or crash. No
warning; just wrong results at runtime.

**Cause**: Godot's Dictionary `.keys()` returns a snapshot Array,
but the documentation is ambiguous about behavior under concurrent
mutation. Empirically: iteration sometimes sees the mutation, sometimes
doesn't, depending on hash bucket layout. Same class of bug as
Python's "RuntimeError: dictionary changed size during iteration"
but GDScript doesn't raise — it just produces wrong results.

**Fix**: snapshot keys BEFORE iterating, then guard each iteration
with `has()`:

```gdscript
# WRONG:
for k in my_dict.keys():
    if some_condition:
        my_dict.erase(k)  # undefined behavior

# RIGHT:
var keys_snapshot: Array = my_dict.keys()
for k in keys_snapshot:
    if not my_dict.has(k):
        continue  # already erased by a callback or another iteration
    if some_condition:
        my_dict.erase(k)
```

Same pattern for `Array.erase` during iteration (also undefined).

**What didn't work**:
- Hoping Godot would warn — it doesn't
- Using `for k in my_dict:` instead of `for k in my_dict.keys():` —
  same underlying iteration mechanism, same bug

**Diagnostic**: under load (many entries, frequent erase) you'll see
flaky test failures, intermittent missed events, or crashes. Search
the codebase for `for ... in *.keys():` paired with `.erase(` in the
same function block.

**Related**: spec 07 JOB_SYSTEM (JobScheduler _tick reaped + evicted
in one loop; SA2-C3.1), spec 11 CHANGE_BROADCAST (_dispatch could
see sync callbacks unsubscribe; SA2-C4.1). Both fixed Phase 2 audit
pass.

**First hit**: 2026-05-16 (Phase 2 self-audit caught 3 instances
across JobScheduler + ChangeBroadcast; all fixed via snapshot
pattern).

---

## #4 — Autoload name collides with class_name global

**Symptom**: Godot editor's Autoload UI rejects with dialog:
"Can't add Autoload: X is an invalid name. Must not collide with an
existing global script class name." Same error appears as a parse
error in headless `--import` mode for every script whose class_name
matches an autoload entry in `[autoload]` of project.godot.

**Cause**: Godot 4 treats autoload-registered names as global
identifiers (so consumer code can write `JobScheduler.submit(...)`).
A `class_name JobScheduler` declaration creates the same identifier.
The engine refuses the collision rather than silently picking one.

The hidden trap: if autoloads are registered only via an editor
plugin's `add_autoload_singleton`, the collision is checked at
add-time but the autoloads aren't persisted to `project.godot` until
an interactive editor save. So everything works in tests + editor
sessions; standalone runs silently see no autoloads → SUT
`get_node_or_null("/root/X")` returns null → systems silently
no-op or crash later.

**Fix**: prefix autoload-registered names with a project-unique tag
(W5 uses `W5_`); keep `class_name X` on the script for test
construction + type hints. Add an explicit `[autoload]` section to
`project.godot` with the prefixed names so standalone runs work.
SUT code looks up via a helper (`W5Lookup.find("X")`) that checks
the prefixed path first, falls back to bare name for tests that
inject a fresh instance.

```ini
; project.godot
[autoload]
W5_StreamingBudget="*res://addons/world5/scripts/core/StreamingBudget.gd"
W5_JobScheduler="*res://addons/world5/scripts/core/JobScheduler.gd"
```

```gdscript
# Script keeps class_name for test .new()
class_name JobScheduler extends Node
# Consumer code:
var sched: Node = W5Lookup.find("JobScheduler")
```

**What didn't work**:
- Same-name autoload + class_name → parse error
- Plugin-only autoload registration → fails in standalone (editor-
  save dependency hidden)
- Renaming the class_name and updating every test to use preload
  instead of `.new()` → touches 14+ test files; fragile

**Diagnostic**: standalone-run console fills with
`[your_system] X autoload missing` errors every frame. Test suite
green but `godot --path demo res://scenes/X.tscn` broken.

**Related**: spec 07 JOB_SYSTEM (lazy `/root/W5_JobScheduler`
lookup), spec 08a (GpuJob routing depends on JobScheduler being
findable), W5Lookup helper at
`engine/scripts/core/W5Lookup.gd`.

**First hit**: 2026-05-17 (Phase 4.6 visual review found walking
demo broken standalone; Phase 4.7 fix landed at commit `bc8c954`).

---

## #5 — Main RenderingDevice rejects explicit submit/sync in Godot 4.6

**Symptom**: Calling `RenderingDevice.submit()` or
`RenderingDevice.sync()` on the RD returned by
`RenderingServer.get_rendering_device()` fires:
```
ERROR: Only local devices can submit and sync.
   at: submit (servers/rendering/rendering_device.cpp:6293)
```
Every frame, as long as your compute work is being dispatched.
Buffer readbacks via `buffer_get_data()` return empty or stale data.

**Cause**: Godot 4.6 made the main RD's submit/sync lifecycle the
exclusive domain of Godot's own renderer. External callers must
create a LOCAL RD via `RenderingServer.create_local_rendering_device()`
for any compute work that needs explicit submit/sync.

Tests sometimes work by accident: gut's test viewport setup creates
a local RD under the hood that `get_rendering_device()` happens to
return in test contexts. Standalone scene runs use the main RD
directly, exposing the bug.

**Fix**: create + cache a local RD in any system that does compute
work with explicit submit/sync:

```gdscript
var _rd: RenderingDevice = null

func _ensure_rd() -> RenderingDevice:
    if _rd != null:
        return _rd
    _rd = RenderingServer.create_local_rendering_device()
    return _rd

func shutdown() -> void:
    if _rd != null:
        # Free any owned RIDs first, then the device itself
        _rd.free()
        _rd = null
```

Local RD is fully independent from the main RD — different memory
pool, different command queue. Readback via `buffer_get_data()`
crosses back to CPU bytes which any consumer (including the main
RD's shaders via ImageTexture upload) can use.

**What didn't work**:
- `RenderingServer.get_rendering_device()` from the render thread
  (still the main RD; same error)
- `RenderingServer.call_on_render_thread(...)` wrapping the
  submit/sync (same error; the thread isn't the issue, the RD
  ownership is)

**Diagnostic**: grep your code for `.submit()` + `.sync()` paired
with `get_rendering_device()`. Replace with
`create_local_rendering_device()`.

**Related**: spec 08a GPU_CPU_CONTRACT (rule 1: RenderingDevice
calls on render thread — refines to "on render thread + on a local
RD"), spec 20 TERRAIN_BACKEND (first hit), GpuTerrainBackend.gd.

**First hit**: 2026-05-17 (Phase 4.6 visual review; Phase 4.8 fix
landed at commit `049ceb8`).
