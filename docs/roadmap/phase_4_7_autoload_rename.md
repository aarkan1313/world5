# Phase 4.7 — Autoload Rename Refactor (DONE 2026-05-17)

> Phase: 4.7 (sub-phase of Phase 4)
> Status: ✅ done
> Triggered by: 2026-05-17 visual-review session caught that the
> walking demo doesn't run standalone — `JobScheduler autoload missing`
> errors fire because plugin-only `add_autoload_singleton` doesn't
> persist to `project.godot` outside interactive editor sessions.

## Problem

The 5 Tier 0 autoloads were only registered via the editor plugin's
`add_autoload_singleton`. Standalone runs bypassed the editor →
no autoloads → SUT `/root/X` lookups failed → terrain backend
couldn't submit page jobs → terrain stayed flat.

The obvious fix (add `[autoload]` to `project.godot`) hit Godot 4's
class_name collision: "X is an invalid name. Must not collide with
an existing global script class name."

## What shipped

### W5_ prefix for autoload-registered names
- `engine/plugin.gd` `_AUTOLOADS` entries renamed `StreamingBudget`
  → `W5_StreamingBudget`, etc.
- `demo/project.godot` gains `[autoload]` section with the same
  prefixed names (works in standalone)
- `class_name` declarations on the 5 autoload scripts UNCHANGED —
  tests still use `JobScheduler.new()` for unit-level construction

### W5Lookup helper
- `engine/scripts/core/W5Lookup.gd`: static `find(short_name)`
  helper. Checks `/root/<name>` first (test-override path), then
  `/root/W5_<name>` (production autoload). Lets tests inject without
  renaming + still works in production where only the W5_ entry
  exists.

### All SUT lookup sites converted
12 `get_node_or_null("/root/X")` sites in SUT code now go through
`W5Lookup.find("X")`. Plus 5 spec docs updated. Test files
untouched — they still instantiate at `/root/<name>` without prefix
because that's the test-override path W5Lookup checks first.

### `_reset()` added to JobScheduler
For test-suite isolation when sharing the autoload instance (not
strictly needed today since tests use the manual-instantiation
override path, but useful for future test refactors).

## Verify

5/5 layers green stable (115 pytest + gut + gut_real_gpu + preflight
+ capture).

## What this did NOT fix

**Walking demo terrain still doesn't render standalone.** Phase 4.6
visual review uncovered a SECOND bug:
`GpuTerrainBackend._generate_heights` uses
`RenderingServer.get_rendering_device()` (the MAIN RD) and calls
`rd.submit() / rd.sync()` — Godot 4.6 errors with
`"Only local devices can submit and sync"` in standalone runs. The
gut_real_gpu test layer doesn't hit this because gut's test setup
creates a local device for the test viewport.

Scoped as Phase 4.8 (`docs/roadmap/phase_4_8_local_rd_refactor.md`).
Walking demo still requires Godot editor to actually render terrain
until that ships.

## Doc cap status

~80 lines.
