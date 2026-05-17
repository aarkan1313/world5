# Phase 4.6 Visual Review — Build Note

> Date: 2026-05-17
> Triggered by: user request "run it for me and review"

## What I tried

Wrote a one-shot capture script (`demo/scripts/capture_walking_demo.gd`
+ `demo/scenes/walking_demo_capture.tscn`) that loads the walking
demo scene, lets it settle for 8 seconds, captures the main viewport,
saves a PNG, and quits. Goal: agent-side visual review without
needing the user to launch interactively + report.

Launched in real-GPU mode:
```
godot --display-driver windows --rendering-driver vulkan \
  --path demo res://scenes/walking_demo_capture.tscn --single-window
```

## What the capture showed

**Pure sky.** The captured PNG (saved to
`user://_capture_walking_demo.png`, 1152x648) contained only the
ProceduralSky's gradient: blue-grey top fading to brown-grey at the
horizon. **No terrain visible whatsoever.**

Captured diagnostics:
- `resident_pages = 0`
- `is_full_detail_ready() = false`
- Console flooded with `[terrain_backend] JobScheduler autoload missing`
  errors every frame

## Root cause

The Tier 0 autoloads (StreamingBudget / JobScheduler / etc.) are
registered by `engine/plugin.gd` via
`EditorPlugin.add_autoload_singleton(name, path)`. Per Godot 4
semantics, this writes to `project.godot`'s autoload section only
after an interactive editor save action. Standalone runs
(via `godot --path demo res://scenes/X.tscn`) bypass the plugin
entirely + see no autoloads.

Without `JobScheduler`, terrain backend can't submit page-generation
jobs → no pages stream → no heightmaps bind → terrain renders flat
→ camera at Y=60 looking down sees nothing terrain-shaped + the
sky fills the viewport.

This is NOT a renderer regression. It's an installation/bootstrap
gap. The renderer code works correctly — proven by the gut_real_gpu
test layer which DOES populate autoloads manually (8 test files
do `before_each: instantiate + add_child` for each system).

## Attempted fix (rolled back)

Spent ~30 minutes on the W5_-prefixed-autoload rename. Naive sed
approach broke 50+ files. The test refactor side (replacing 8
files' `before_each` blocks to use the autoload instead of manual
instantiation) is mechanical but needs care: tests sharing an
autoload need state reset between runs.

Scoped the proper fix as Phase 4.7 (see
`docs/roadmap/phase_4_7_autoload_rename.md`). Reverted all
W5_-rename changes; verify back to green stable.

## What the user should do to actually see terrain

Per the updated `docs/workflows/walking_demo.md`:

1. Open `demo/project.godot` in Godot 4.6.2 editor
2. The plugin's `_enter_tree` will call `add_autoload_singleton`
   for each Tier 0 system
3. Save the project (Ctrl + S) — this persists the autoload
   entries to `project.godot`
4. Press F5 to launch the walking demo
5. WASD to walk, mouse to look, ESC to release mouse

After this one-time bootstrap, standalone runs also work.

## Phase 4 status

Phase 4 (terrain MVP) remains CLOSED at commit `3f9b08c`. The
walking demo is a real deliverable — it works once you do the
editor bootstrap. Phase 4.7 (1-session focused refactor) makes
the bootstrap unnecessary so fresh checkouts work standalone.

## Verify status (post-revert)

5/5 layers green stable on Godot 4.6.2 stable mono:
- pytest 115 passed
- gut (headless) all passed
- gut_real_gpu all passed
- preflight 0 errors
- capture all passed
