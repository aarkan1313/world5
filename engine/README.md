# W5 Engine — Godot Addon

The runtime side of W5 (World 5). Drop this directory into your Godot
project's `addons/world5/` and enable the plugin in Project Settings.

## Status

**Phase 0 scaffold.** Plugin manifest + directory tree only; no system
code yet. Enabling the plugin will work but autoloads aren't registered
until Phase 2.

See [`../docs/STATE.md`](../docs/STATE.md) for current state and
[`../docs/ROADMAP.md`](../docs/ROADMAP.md) for what's next.

## Install (when there's something to install)

Three methods per [spec 18](../docs/specs/18_PLUGIN_INSTALL_AND_DEV_LOOP.md):
- **Method A — git submodule**: `git submodule add -b v0.X.Y https://github.com/aarkan1313/world5.git addons/world5_engine` + symlink
- **Method B — copy**: `cp -r world5-0.X.Y/engine/ my_project/addons/world5/`
- **Method C — symlink** (dev only): `ln -s /path/to/world5/engine my_project/addons/world5`
  (Windows: `mklink /D my_project\addons\world5 \path\to\world5\engine` — needs admin OR Developer Mode)

After install, enable in Project Settings → Plugins → World5.

## What's in here

```
engine/
├── plugin.cfg              # Godot addon manifest
├── plugin.gd               # EditorPlugin (autoloads register here in Phase 2)
├── scripts/
│   ├── core/               # Tier 0 primitives (Job, SpatialIndex, ...)
│   └── <system>/           # vertical systems (terrain, materials, ...)
├── scenes/
│   ├── components/         # plug-into-any-game subscenes
│   └── test_harness/       # diagnostic + verification scenes
├── shaders/
├── resources/              # .tres + JSON config + JSON schemas
├── tests/                  # gut tests (Phase 2 installs gut)
├── examples/               # per-system example scenes
├── decoration_meshes/      # shipped LOD-baked decoration (Phase 7+)
├── foliage_meshes/         # shipped trunks + leaves (Phase 8+)
├── cave_meshes/            # reusable cave assets (Phase 12+)
└── worlds/                 # bundled reference world(s) (Phase 6+)
```

## License

TBD before v0.1.0 release.

## See also

- [`../README.md`](../README.md) — project overview
- [`../docs/README.md`](../docs/README.md) — docs index
- [`../docs/specs/`](../docs/specs/) — 47 system specs
