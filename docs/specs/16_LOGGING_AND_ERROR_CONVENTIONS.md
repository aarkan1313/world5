# Spec: Logging + Error Conventions

> Status: draft
> Tier: meta
> Depends on: 01_MODULE_LAYOUT, 03_PILLARS
> Consumed by: every system that produces runtime output

## Purpose

W4.1 had no logging policy. Each system used Godot's `print`,
`push_warning`, `push_error` inconsistently. Output was noisy in some
places, silent in others. LLM agents couldn't reliably parse output to
know "did the operation succeed?" Consumers couldn't filter signal from
noise.

W5 commits to one logging contract that every system follows. Output
is structured, level-tagged, system-prefixed, and parseable. Humans
get useful console output; LLM agents get machine-readable diagnostic
streams.

## Non-goals

- Replacing Godot's `print` / `push_warning` / `push_error` with a
  custom logger (we wrap them, not replace)
- Per-frame logging at high volume (we ship a debug-only verbose mode;
  default is event-driven)
- Persistent log files in production builds (in dev, yes; ship default
  is stdout)
- Telemetry uploading to external services (consumer responsibility)

## The five levels

| Level | When | Audience | Default visibility |
|---|---|---|---|
| `DEBUG` | Per-event diagnostic noise (chunk load, asset request, etc.) | Developers, agents during debugging | Hidden unless `verbose=true` per system |
| `INFO` | Normal lifecycle events (system ready, world loaded, X chunks resident) | Developers, agents | Visible in dev; suppressible in shipping builds |
| `WARN` | Something unexpected but recoverable (deprecated API, missing optional asset, perf budget approaching) | Everyone | Always visible |
| `ERROR` | Operation failed, but engine continues (mesh load failed, contract violation, etc.) | Everyone | Always visible |
| `FATAL` | Engine cannot continue (config corrupt, unrecoverable runtime state) | Everyone | Always visible; triggers shutdown |

## Format

Every log line follows:
```
[LEVEL] [system_name] [timestamp_ms] message_text  key1=value1 key2=value2
```

Example:
```
[INFO ] [terrain        ] [   1234] Ring 3 full detail ready  duration_ms=87 page_count=64
[WARN ] [decoration     ] [   1235] Mesh refs missing  count=3 mesh_ids=[plants/foo,plants/bar,plants/baz]
[ERROR] [asset_stream   ] [   1456] Load failed  path=res://decoration_meshes/xyz.glb error=truncated
```

- `LEVEL` is 5 chars left-padded so columns align
- `system_name` is 15 chars left-padded (truncate longer names)
- `timestamp_ms` is Time.get_ticks_msec() since engine init
- Key=value pairs appended for structured data (parseable by agents)
- No multi-line messages; if long, summarize + reference a separate
  diagnostic dump file

## Public API

### `engine/scripts/core/Log.gd`

```gdscript
class_name Log extends RefCounted

# Static methods, accessible from anywhere

static func debug(system: String, message: String, kv: Dictionary = {}) -> void
static func info(system: String, message: String, kv: Dictionary = {}) -> void
static func warn(system: String, message: String, kv: Dictionary = {}) -> void
static func error(system: String, message: String, kv: Dictionary = {}) -> void
static func fatal(system: String, message: String, kv: Dictionary = {}) -> void

# Per-system verbose toggle (read at log time)
static func is_verbose(system: String) -> bool
static func set_verbose(system: String, enabled: bool) -> void

# Configuration
static func set_level(min_level: int) -> void          # filter by level
static func set_format(format: String) -> void         # "human" | "json" | "compact"
static func set_output(target: String) -> void        # "stdout" | "file:/path" | "both"
```

### Python: `pipeline/core/log.py`

Same shape, idiomatic Python:
```python
from world5.log import log

log.info("texture", "Pipeline complete", duration_s=42.3, prompts=20)
log.error("decoration", "Bake failed", chunk=(2, 3), error=str(e))
```

Python side honors the same format + level filter as GDScript side.

## JSON output mode

For LLM consumption + log-aggregation tools:
```
log.set_format("json")
```
Produces:
```json
{"level": "INFO", "system": "terrain", "ts_ms": 1234, "msg": "Ring 3 full detail ready", "duration_ms": 87, "page_count": 64}
```
One JSON object per line. Easy for agents to parse: `result = json.loads(line)`.

## Error vs warning vs info — when

Heuristic per system author:

- **Use `error`** when: an operation produced wrong-or-no output and a
  consumer would notice. Examples: asset load failed, contract
  violation, schema mismatch, file missing.
- **Use `warn`** when: an operation succeeded but in a degraded /
  unexpected way. Examples: using deprecated API, falling back to a
  lower LOD, optional asset missing, perf approaching budget.
- **Use `info`** when: a meaningful lifecycle event. Examples: world
  loaded, system ready, X chunks streamed in.
- **Use `debug`** when: per-event noise useful only when debugging.
  Examples: every chunk bring-up, every asset request, every job
  scheduled.
- **Use `fatal`** when: engine cannot continue. Rare. Triggers
  graceful shutdown if possible.

Spec authors document the events their system emits in the
Discoverability section ("Logs at level X under system_name='Y' for
these events: ...").

## Verbosity control

Three layers:
1. **Global min level**: `Log.set_level(Log.INFO)` filters all output
   below INFO. Default: INFO in dev, WARN in shipping.
2. **Per-system verbose**: `Log.set_verbose("terrain", true)` makes
   terrain's DEBUG output visible without enabling DEBUG globally.
   Useful for debugging one system.
3. **Per-event debug bool** (sparingly): some systems have an
   `@export var verbose: bool` on a node for scene-level debugging.
   Honors `Log.is_verbose(system_name)` as well as the explicit flag.

## Wrapping Godot's print/push_warning/push_error

The `Log` class wraps these:
- `info` → `print()`
- `warn` → `push_warning()` (so it appears in Godot's debugger Output)
- `error` → `push_error()` (so it appears + flags the script)
- `fatal` → `push_error()` + `OS.crash()` if shutdown impossible

Systems should NEVER call `print` / `push_warning` / `push_error`
directly. Lint rule (preflight): grep `engine/scripts/` for direct
calls; fail if found outside `Log.gd` itself.

## Producer / consumer contract

- **Produces**: structured log lines on configured output(s)
- **Consumes**: log calls from every system; configuration from
  startup

## Dependencies

- `01_MODULE_LAYOUT` (placement)
- `03_PILLARS` (architecturally correct = consistent logging)

## Quality bar

- A log call is < 50µs in normal (INFO+) path
- DEBUG calls are < 5µs when filtered out (early return)
- JSON mode output is valid JSON per line (parseable by `json.loads`)
- Lint preflight catches direct `print`/`push_warning`/`push_error`
  calls outside `Log.gd`
- 100% gut test coverage of public API

## Discoverability

- **Entry point**: `Log.info(system, message, kv)` etc.
- **Schema**: log line format + JSON mode shape, both documented above
- **Validator / preflight**: lint script catches direct Godot logging
  calls; gut tests verify format + level filtering
- **Example**: every other system's spec includes its "events emitted"
  list in its Discoverability section
- **Deterministic outputs**: yes — same inputs produce same log lines
  (timestamp aside)

## Open questions

- **File output rotation**: if `set_output("file:...")`, do we rotate?
  Probably yes by date; defer until first user.
- **Async logging**: should logging be async (push to a queue, flush
  on another thread)? Probably not — synchronous is simpler and the
  per-call cost is already low. Revisit if a high-volume system
  surfaces.
- **Color in human format**: default no, opt-in via env var.

## References

- W4.1 used inconsistent print/push_warning/push_error throughout; no
  formal logging policy ever shipped
- Common practice in production game engines (Unreal `UE_LOG`, Unity
  `Debug.Log` with categories)

## Revision history

- 2026-05-16: initial draft
