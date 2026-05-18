# Spec: Plugin Install + Dev Loop

> Status: reviewed — `world5.setup install_demo` + `verify_install`
> CLI shipped at pipeline/world5/setup/__init__.py; junction-based dev
> loop works. Pending (~1-2 sessions): automated Godot hot-reload
> harness (currently manual restart per shader edit).
> Tier: meta
> Depends on: 01_MODULE_LAYOUT, 17_VERSIONING_AND_MIGRATION
> Consumed by: every consumer of W5; every contributor

## Purpose

W5's success metric is "usable, exportable, swappable, easy to adapt
and tune for whatever." Forkable into 3 projects. Without a clear
install + iteration story, "usable" is aspirational; a consumer faces
ambiguity at every step.

This spec defines:
1. How a consumer **installs** W5 into their Godot project
2. How they **iterate** on a world (edit → see → repeat) without
   restarting Godot each time
3. How a contributor **develops** W5 itself in the `demo/` project

## Non-goals

- Asset Store / Godot addon registry distribution (deferred until
  W5 is mature enough to publish publicly)
- Multi-version installation (one W5 version per consumer project at
  a time)
- Auto-update / auto-migrate without user action

## Three install methods (consumer chooses)

### Method A: Git submodule (recommended for projects pinning a version)

```bash
cd my_game_project
git submodule add -b v0.3.2 https://github.com/.../world5 addons/world5_engine
# Symlink or junction to expose engine/ as the addons/world5 dir
ln -s addons/world5_engine/engine addons/world5
```

Pros: pinned version, easy upgrades via submodule update.
Cons: extra clone step; submodule footgun for inexperienced users.

### Method B: Copy + lock (recommended for projects that customize)

```bash
cd my_game_project
git clone --branch v0.3.2 https://github.com/.../world5 /tmp/world5
cp -r /tmp/world5/engine addons/world5
# Record the version
echo "v0.3.2" > addons/world5/INSTALLED_VERSION.txt
```

Pros: full control to customize; no submodule complexity.
Cons: manual upgrades require diff + merge.

### Method C: Symlink (recommended for W5 contributors developing in
parallel with their consumer project)

```bash
cd my_game_project
ln -s /path/to/world5/engine addons/world5
```

Pros: instant W5 changes visible in consumer; ideal for development.
Cons: only works on dev machine; not for distribution.

The `demo/` consumer project bundled with W5 uses Method C by default
(symlink to `../engine`), with a `setup.py` script that does the
platform-correct symlink call (Windows `mklink /D` vs Unix `ln -s`).

**Windows symlink prerequisite (audit M10)**: `mklink /D` requires
either (a) running the terminal as Administrator, OR (b) enabling
Developer Mode in Windows 10/11 Settings (Settings → Update & Security
→ For developers → Developer Mode ON). The `setup.py` script detects
the case and prints a clear error pointing the user to one of the
two options if symlink creation fails. For consumers who cannot
enable Developer Mode (locked-down corporate machines), Method A (git
submodule) or Method B (copy via setup.py) are the supported
fallbacks; both work without admin or Developer Mode.

## What `addons/world5/` contains

After install, the consumer's `addons/world5/` is exactly the contents
of W5's `engine/`:

```
addons/world5/
├── plugin.cfg
├── scripts/
├── scenes/
├── shaders/
├── resources/
└── README.md
```

The consumer activates the plugin in Godot's Project Settings → Plugins.

## Consumer's project structure (recommended)

```
my_game_project/
├── addons/
│   └── world5/             # W5 engine via one of methods above
├── worlds/                 # consumer's world bundles
│   ├── my_world_alpha/
│   │   ├── world.json
│   │   ├── biome_catalog.json
│   │   └── ...
│   └── my_world_beta/
├── scenes/                 # consumer's game scenes
├── scripts/                # consumer's game logic
└── project.godot
```

Consumer's game scenes instance W5's exposed scene components (e.g.
`res://addons/world5/scenes/components/terrain_world.tscn`) and pass
in a world bundle path.

## Public API for consumers

The W5 plugin exposes via Godot's plugin system:
- **Autoloads**: `JobScheduler`, `AssetStream`, `StreamingBudget`,
  `ChangeBroadcast`, `QualityTiers`, `World5`, `Log` (all in
  `engine/scripts/core/`)
- **Scene components**: pre-built `.tscn` files under
  `engine/scenes/components/` that consumers instance + configure
- **Resource types**: custom `.tres` types for world bundles, biome
  catalogs, etc.
- **CLI tools**: `python -m world5.<tool>` for all pipeline tools
  (world contract, migration, content addressing, etc.)

The "public" vs "internal" boundary:
- Public: anything explicitly exported via `class_name` + documented
  in a spec
- Internal: anything in `engine/scripts/<system>/_internal/` or
  prefixed `_private_` — consumers shouldn't touch; we may change
  without migration

## Dev loop: iterate on a world

The goal: edit something, see the change, without restarting Godot.

### Today (Phase 0 baseline)
1. Consumer opens Godot, runs the game scene
2. To change anything in the world bundle: stop, edit, restart, run
3. ~30s round-trip per iteration

### W5 commits to (when systems support it)
Three levels of dev-loop support:

**Level 1: Restart-required** (acceptable for v0)
Some changes (kernel system rewrite, plugin code change) require a
Godot restart. Document which.

**Level 2: Scene-reload** (acceptable for v0.5)
Consumer presses F8 in editor, scene reloads, world re-streams from
disk. Picks up world bundle changes (texture edits, decoration zone
edits, etc.). ~5s round-trip.

**Level 3: Hot-reload** (target for 1.0)
Consumer edits a world bundle file; W5 detects the change via file
watcher, invalidates relevant caches via the Change Broadcast spec,
re-streams affected chunks. < 1s round-trip for typical edits.

Hot-reload is gated on the Change Broadcast spec (already in Tier 0)
being live. W4.1 wished for this (Sprint R5) but never shipped it.

## Dev loop for W5 contributors (`demo/` project)

Contributors edit `engine/scripts/` etc. directly; the symlinked
`demo/addons/world5/` sees changes immediately. F8 in Godot
reloads the demo scene with the new W5 code.

For Python pipeline changes: run `python -m world5.verify --fast`
to confirm tests still pass; ~30s cycle.

## Public API

### Install commands (Python)

```bash
# Inside the W5 repo, sets up the demo/ project symlink
python -m world5.setup install_demo

# Validates an installed addon is correctly linked
python -m world5.setup verify_install <path_to_consumer_project>
```

### File-watch / hot-reload (engine side)

```gdscript
# (Future, target Phase 7+)
class_name WorldHotReloader extends Node
# Watches world bundle dirs; emits ChangeBroadcast events on file changes
```

## Producer / consumer contract

- **Produces**: a known-good install + iteration flow for consumers;
  contributor dev loop in `demo/`
- **Consumes**: consumer choice of install method; file edits as
  iteration signals

## Dependencies

- `01_MODULE_LAYOUT` (defines `engine/`/`demo/`/`addons/` shapes)
- `17_VERSIONING_AND_MIGRATION` (consumers pin a version; install
  records it)
- `11_CHANGE_BROADCAST` (powers hot-reload at level 3)

## Quality bar

- Fresh-clone of W5 + `python -m world5.setup install_demo` produces
  a runnable `demo/` project in < 30s on dev hardware
- Consumer following Method A or B in their own project can run a
  W5 demo scene in their project in < 5 min (timed test)
- Level 2 scene-reload completes in < 5s (with a typical world bundle)
- Level 3 hot-reload (when shipped) < 1s for a single decoration zone
  edit
- Install verification (`verify_install`) is < 1s

## Discoverability

- **Entry point**: `engine/README.md` is the consumer-facing install
  guide; `demo/README.md` is the developer-facing dev-loop guide
- **Schema**: install methods documented in this spec + `engine/README.md`;
  no other schema
- **Validator / preflight**: `python -m world5.setup verify_install`
  catches broken symlinks, version mismatches, missing autoloads
- **Example**: `demo/` IS the working example
- **Deterministic outputs**: yes — same install method + same source
  produces same `addons/world5/` content

## Open questions

- **Distribution**: when do we publish to Godot Asset Library?
  Probably at 1.0; defer.
- **Multi-version coexistence**: can a consumer have W5 v0.3 AND v0.4
  installed for migration testing? Probably not; out of scope.
- **Auto-version-check on consumer project open**: nice-to-have but
  intrusive. Defer.
- **Hot-reload level 3 timeline**: probably mid-W5 (after Change
  Broadcast has 2-3 real publishers).

## References

- W4.1 wishlist: hot-reload (Sprint R5, never shipped)
- W4.1 PITFALLS #16 (launch command quoting issue — relevant to
  contributor dev loop docs)
- Common practice in Godot plugins (e.g. Dialogic, Phantom Camera)
  for install patterns

## Revision history

- 2026-05-16: initial draft
