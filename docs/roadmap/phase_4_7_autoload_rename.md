# Phase 4.7 — Autoload Rename Refactor

> Phase: 4.7 (post-4.6 audit-driven refactor)
> Status: 📋 planned
> Estimated sessions: 1 (focused)
> Triggered by: 2026-05-17 visual-review session caught that the
> walking demo doesn't run standalone — `JobScheduler autoload missing`
> errors fire because plugin-only `add_autoload_singleton` doesn't
> persist to `project.godot` outside interactive editor sessions.

## Problem statement

The 5 Tier 0 autoloads (`StreamingBudget`, `JobScheduler`,
`GpuResourceTracker`, `AssetStream`, `ChangeBroadcast`) currently:

1. Are registered by `engine/plugin.gd` via
   `EditorPlugin.add_autoload_singleton(name, path)` in `_enter_tree`.
2. Are referenced at `/root/<Name>` by SUT code (24 lookup sites).
3. Are manually instantiated in 8 test files via
   `var x = JobScheduler.new(); x.name = "JobScheduler";
   root.add_child(x)` because tests don't run the editor plugin.

This pattern has three failure modes:

**Failure A**: standalone runs (`godot --path demo`) miss the
autoloads → SUT code's `/root/JobScheduler` lookups fail. Editor
must be opened + saved once before standalone runs work.

**Failure B**: adding the obvious explicit `[autoload]` section to
`project.godot` collides with `class_name JobScheduler` etc. —
Godot 4 rejects with "X is an invalid name. Must not collide with
an existing global script class name."

**Failure C**: tests' manual instantiation creates instances at
`/root/<Name>` that would coexist with the autoload-registered
instance at the same path → `get_node_or_null` returns one of two,
racy.

## Decision

Rename the autoload-registered globals to `W5_<Name>` prefix, keep
`class_name <Name>` on the scripts. Test files stop instantiating
autoload-backed systems manually — they use the autoload directly
via `get_node("/root/W5_<Name>")` + `._reset()` between tests.

## Deliverables

- [ ] `engine/plugin.gd` `_AUTOLOADS` entries renamed to W5_*
- [ ] `demo/project.godot` gains `[autoload]` section with W5_*
      names (works in standalone runs)
- [ ] All 24 `/root/<Name>` lookups in engine + spec docs renamed
      to `/root/W5_<Name>`
- [ ] Test refactor: 8 integration / perf / visual test files
      stop manually instantiating autoload-backed systems. New
      pattern: `before_each: _x = get_node("/root/W5_X"); _x._reset()`.
- [ ] Add `_reset()` to JobScheduler + verify state-isolation works
- [ ] Verify all 5 layers pass green stable post-refactor
- [ ] Update `docs/workflows/walking_demo.md` to remove the
      known-issue + workaround section
- [ ] Pitfall note documenting the class_name vs autoload-name
      collision

## Out of scope

- Renaming the underlying `class_name` declarations (keep them; they
  exist for test type hints + `.new()` construction in unit tests
  that don't touch /root)
- Adding `_reset()` to GpuResourceTracker (per-test state doesn't
  accumulate problematically)
- Changing test isolation strategy for non-autoload-backed systems
  (TerrainPageCache, ResidencyManager, etc.)

## Why not done in Phase 4.6

Tried it during the visual-review session. The naive sed-rename
broke 50+ files. The test-refactor side (replacing 8 files'
`before_each` blocks) is mechanical but needs care: tests that
share an autoload must reset state between runs OR design around
state accumulation.

A focused session can do this cleanly. Splitting it out keeps
Phase 4.6 close.

## Close criteria

- Walking demo runs standalone from a fresh `git clone` without
  needing to open the editor first
- All tests pass on first run (no editor bootstrap needed)
- Walk-through doc no longer carries the workaround section

## Doc cap status

~80 lines.
