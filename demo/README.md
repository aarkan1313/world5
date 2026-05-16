# W5 Demo Project

Consumer Godot project that uses the W5 plugin. Validates that the
engine works AS AN ADDON, not just as "Godot project we drop code into."

Per spec 01 module layout: every change to `engine/` should be
validated by opening `demo/` in Godot. Forces plugin discipline.

## Status

**Phase 0 scaffold.** No demo scenes yet. Phase 4 (terrain MVP) lands
the first walkable demo.

## Open in Godot

1. Open Godot 4.5+
2. Import this directory (`demo/`)
3. The `addons/world5/` symlink points at `../../engine/` (set up via
   Phase 0 `setup.py` script in Phase 2, or manually for now)
4. Enable the plugin in Project Settings → Plugins (already pre-enabled
   via `project.godot`)

## Addon symlink

`demo/addons/world5/` is a symlink to `../../engine/`. Per spec 18
Method C — symlink during dev so engine changes are instantly visible.

Windows: `mklink /D` requires admin OR Developer Mode (see
[spec 18](../docs/specs/18_PLUGIN_INSTALL_AND_DEV_LOOP.md) for fix).

Unix: `ln -s ../../engine addons/world5` works without admin.

## What lands here over time

| Phase | What ships |
|---|---|
| Phase 4 | `scenes/walking_demo.tscn` — first walkable terrain |
| Phase 6 | `scenes/two_biome_demo.tscn` — 2-biome target |
| Phase 7+ | scenes showcase decoration / foliage / atmosphere / water |
| Phase 15 | bake-recipe demos (offline image outputs) |
| Phase 16 | forkability validation reference |

See [`../docs/ROADMAP.md`](../docs/ROADMAP.md) for phase status.

## Doc cap status

This file: ~40 lines.
