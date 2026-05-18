# Spec: Streaming Budget Contract

> Status: shipped (2026-05-18; promoted per spec-to-impl audit — StreamingBudget.gd shipped + per-system usage tracking)
> Tier: cross-cutting (Tier 0)
> Depends on: 01_MODULE_LAYOUT, 13_QUALITY_TIERS
> Consumed by: terrain backend, async asset streaming, decoration runtime, future water/weather/etc — every async system

## Purpose

Per-tier shared ceilings for: active triangles, resident texture MB,
draw calls, active jobs, CPU pages, GPU pages, asset cache MB.

Every async system publishes its current usage; the accountant
aggregates and fails loudly if total exceeds the budget. Same idea
as W4.1's `StreamingBudgetAccountant` but enforced for ALL systems,
not just terrain.

W4.1 had this for terrain only. Decoration would publish via
`ClipmapWorld.publish_streaming_budget_usage` but only when wired up
— it didn't auto-register. Other systems (audio, future water) never
participated. The result: the budget existed but didn't catch overruns
from anything except terrain.

W5 makes participation a **contract obligation**: a system that
allocates streamable resources MUST publish into the accountant. The
spec template's Quality bar section flags this.

## Non-goals

- Per-frame budget enforcement (that's the profiler's job; this is
  for resource accounting)
- Runtime cost prediction (we measure usage, not predict)
- Auto-throttling consumers when over budget (consumers MUST design
  for budget compliance; the accountant raises flags but doesn't
  manage their queues)

## Public API

### `engine/scripts/core/StreamingBudget.gd`

```gdscript
class_name StreamingBudget extends Node

# Singleton autoload at /root/StreamingBudget

# Publish (called by systems)
func publish(system_name: String, usage: Dictionary) -> void:
    """`usage` keys: active_tris, resident_texture_mb, draw_calls,
    active_jobs, cpu_pages, gpu_pages, asset_cache_mb. Missing keys
    default to 0. Overwrites prior publish from same system_name."""

func clear(system_name: String) -> void:
    """Called on system teardown (decoration unloads, water lake
    disposes, etc.). Removes contribution from total."""

# Query
func get_system_usage(system_name: String) -> Dictionary
func get_total_usage() -> Dictionary
func get_budget() -> Dictionary    # from QualityTiers.get_current()['streaming_budget_*']
func get_headroom() -> Dictionary  # budget - total, per key
func is_over_budget() -> bool

# Detailed query
func get_top_publishers(budget_key: String, n: int = 5) -> Array[Dictionary]:
    """Returns top N publishing systems by absolute contribution to
    `budget_key`. Used for diagnostic HUDs (which system is eating
    the budget). SA-S2.2: replaces vague get_violators() which had
    no clean definition of 'expected share'."""

# Diagnostics
func get_publishers() -> PackedStringArray
func get_history(seconds: float = 60.0) -> Array[Dictionary]:
    """Recent usage snapshots for graphing / diagnosis."""
```

### Per-tier budget keys (in QualityTiers config)

```json
{
  "high": {
    "streaming_budget_active_tris": 4000000,
    "streaming_budget_resident_texture_mb": 1500,
    "streaming_budget_draw_calls": 800,
    "streaming_budget_active_jobs": 16,
    "streaming_budget_cpu_pages": 64,
    "streaming_budget_gpu_pages": 32,
    "streaming_budget_asset_cache_mb": 800
  }
}
```

(Numbers above are placeholders pending tier calibration.)

## Producer / consumer contract

- **Producers**: every system that allocates streamable resources
  (terrain rings, decoration MMIs, asset cache entries, water plane
  meshes, etc.) MUST call `publish(name, usage)` whenever its usage
  changes (typically on residency change, not per-frame).
- **Consumers**: the profiler reads `get_total_usage()` and
  `get_budget()` to fail tests; diagnostic HUDs read
  `get_system_usage()` per system.

## Failure mode

When `is_over_budget()` returns true:
- Default: log a warning (not an error — over-budget is a measurement,
  not an exception)
- The profiler tests fail when over-budget is detected during
  motion/spin/startup gates
- Per-tier `--full` verify mode includes budget checks; default mode
  doesn't (preflight; cheap)

Systems do NOT auto-back-off. Over-budget signals a real problem that
needs human attention (probably re-tuning tier limits or fixing a
runaway publisher).

## Dependencies

- `01_MODULE_LAYOUT` (placement)
- `13_QUALITY_TIERS` (provides per-tier budget values)

## Quality bar

- `publish()` is < 50µs (called frequently)
- `get_total_usage()` is < 100µs (called per HUD frame in dev tools)
- Memory: ~200 bytes per publishing system regardless of update rate
- 100% gut test coverage of public API
- The spec-template's Quality bar section reminds spec authors:
  "If this system allocates streamable resources, it MUST publish
  into StreamingBudget."

## Discoverability

- **Entry point**: `StreamingBudget` autoload; `publish(name, usage)`
  to participate
- **Schema**: the `usage` Dictionary keys + the per-tier config keys
  are the schema; both documented in this spec + in
  `engine/resources/quality_tiers.json`
- **Validator / preflight**: gut test suite + profiler tests check
  that systems publishing-when-they-shouldn't is caught (lint-like)
- **Example**: `engine/examples/streaming_budget_example.gd` shows a
  fake system publishing + the diagnostic readout
- **Deterministic outputs**: yes — same usage snapshots produce same
  totals + headroom

## Open questions

- Should `publish()` be rate-limited (e.g. throttle to once per 100ms
  per system)? Probably yes — high-frequency publish is wasteful and
  systems generally know their usage at low cadence
  (per-chunk-bringup, not per-frame). Spec choice: rate-limit
  internally; if a system calls publish twice within 100ms, the second
  call coalesces.
- "Violators" detection: hard to define "expected share" generically.
  May drop this feature if it can't be implemented cleanly. Defer.

## References

- W4.1 `StreamingBudgetAccountant.gd` — proven pattern, this spec
  generalizes it
- W4.1 retrospective: streaming-budget contract was retrofit, single-
  consumer; W5 makes it day-1 + multi-consumer

## Revision history

- 2026-05-16: initial draft
