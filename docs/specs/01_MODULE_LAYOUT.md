# Spec: Module Layout

> Status: shipped (2026-05-18; promoted per spec-to-impl audit — engine/+pipeline/+demo/+docs/ structure shipped, validated by godot_root_check)
> Tier: meta
> Depends on: none (this is foundational)
> Consumed by: every other system

## Purpose

W5's directory + module layout defines where everything lives. The W4.1
mistake was a single Godot project that mixed runtime code, pipeline
scratch (`candidates/`), and decoration assets into one directory; this
made the project hard to scan, hard to fork, and hard to package as an
addon. W5 fixes this from commit #1 by separating concerns into three
top-level dirs.

The layout is **load-bearing** for the success metric (forkable into 3
projects): if the engine isn't shaped like a Godot addon from day 1,
"package as addon" becomes a separate retroactive sprint that probably
never happens.

## Non-goals

- Naming the W5 project officially (it's "world 5" for now; could
  rebrand)
- Specifying the linkage method between `demo/addons/world5/` and
  `engine/` — that's a setup decision, deferred to Phase 0
- Versioning + release packaging (separate spec)
- Migration story from W4.1 (separate spec, review-driven)

## Layout

```
world 5/
├── engine/                          # W5 Godot addon, plugin-shaped
│   ├── scripts/
│   │   ├── core/                    # Cross-cutting primitives (Tier 0)
│   │   │   ├── Job.gd
│   │   │   ├── JobScheduler.gd
│   │   │   ├── GpuJob.gd              # spec 08a (SA-M5.11)
│   │   │   ├── GpuResourceTracker.gd  # spec 08a (SA-M5.11)
│   │   │   ├── SpatialIndex.gd
│   │   │   ├── AssetStream.gd
│   │   │   ├── StreamingBudget.gd
│   │   │   ├── ChangeBroadcast.gd
│   │   │   ├── ContentAddress.gd
│   │   │   ├── QualityTiers.gd
│   │   │   ├── Log.gd                 # spec 16
│   │   │   └── World5.gd              # spec 17 version singleton
│   │   ├── terrain/                 # ClipmapWorld replacement etc.
│   │   ├── materials/
│   │   ├── decoration/
│   │   ├── foliage/
│   │   ├── atmosphere/
│   │   ├── lighting/
│   │   ├── water/
│   │   ├── weather/
│   │   ├── caves/
│   │   ├── deformation/
│   │   ├── persistence/
│   │   ├── nav/
│   │   ├── camera/
│   │   └── audio/                   # IN (hooks only per spec 34;
│   │                                #   ai/ removed per inventory)
│   ├── scenes/                      # reusable scene components
│   │   ├── components/              # plug-into-any-game subscenes
│   │   └── test_harness/            # diagnostic + verification scenes
│   ├── shaders/
│   ├── resources/                   # .tres files, default configs
│   ├── tests/                       # gut tests for engine/ classes
│   │   ├── unit/
│   │   ├── integration/
│   │   └── perf/
│   ├── examples/                    # minimal example scenes per system (capped per spec 04)
│   ├── decoration_meshes/           # shipped LOD-baked decoration (spec 27)
│   ├── foliage_meshes/              # shipped trunks + leaves (spec 29)
│   ├── cave_meshes/                 # shipped cave/interior geometry (spec 37)
│   ├── worlds/                      # bundled demo world(s); small
│   ├── plugin.cfg                   # Godot addon manifest
│   ├── README.md                    # how to install + use the addon
│   ├── CHANGELOG.md                 # semver changelog (spec 17 + 43)
│   ├── RELEASE_NOTES.md             # per-release narrative (spec 43)
│   ├── INSTALL.md                   # install methods (spec 18)
│   ├── MIGRATION.md                 # only present on MAJOR releases (spec 17)
│   └── LICENSE                      # addon license
├── demo/                            # consumer Godot project
│   ├── addons/
│   │   └── world5/                  # link to ../../engine (TBD method)
│   ├── project.godot
│   ├── scenes/                      # demo-specific scenes
│   │   ├── walking_demo.tscn        # baseline 1-biome walk
│   │   └── two_biome_demo.tscn      # the 2-biome target
│   ├── worlds/                      # demo world bundles (small)
│   └── README.md                    # how to run the demos
├── pipeline/                        # Python pipeline, engine-agnostic
│   ├── core/                        # cross-cutting Python primitives
│   │   ├── spatial_index.py
│   │   ├── content_address.py
│   │   ├── change_broadcast.py
│   │   └── ...
│   ├── kernels/                     # terrain kernels (Python side)
│   ├── textures/                    # tx_* pipeline (evolved from W4)
│   ├── decoration/                  # generator (offline blob bake)
│   ├── foliage/                     # parametric tree gen, leaf cards
│   ├── trellis/                     # 3D asset gen
│   ├── nav/                         # nav export pipeline
│   ├── world_contract/              # preflight + schema validators
│   ├── lighting/                    # recipe builders
│   ├── atmosphere/                  # profile builders
│   ├── water/                       # if scoped
│   ├── weather/                     # if scoped
│   ├── caves/                       # if scoped
│   ├── persistence/                 # if scoped
│   ├── bake_recipes/                # 2.5D / topdown / map bake tools
│   ├── verify.py                    # `python -m world5.verify`
│   └── README.md
├── docs/
│   ├── README.md                    # doc index
│   ├── STATE.md                     # current state (small, current)
│   ├── ROADMAP.md                   # what next, ranked
│   ├── CONTRIBUTING.md              # spec → plan → build → state lifecycle
│   ├── PILLARS.md                   # project pillars (quality first etc.)
│   ├── specs/                       # one spec per system
│   ├── plans/                       # implementation plans (when spec → plan)
│   ├── build-notes/                 # "what shipped, lessons"
│   ├── workflows/                   # recipes for recurring tasks
│   ├── reference/
│   │   ├── PITFALLS.md              # carry over + extended from W4.1
│   │   ├── TOOLS.md                 # one-line-per CLI tool / script
│   │   └── API.md                   # auto-generated engine public surface
│   └── handoffs/                    # dated cross-session handoff docs
├── tests/                           # pytest (Python pipeline tests)
│   ├── unit/
│   ├── integration/
│   └── conftest.py
├── tools/                           # one-off scripts, debugging utilities
├── .godotignore.template            # default ignore rules for the project
├── .gitignore
└── README.md                        # top-level project overview
```

## Why this shape

### Three top-level concerns

- **`engine/`** is the runtime addon. Plugin-shaped from commit #1.
- **`demo/`** is a consumer Godot project that uses the addon. Every change
  to `engine/` gets validated by running the demo. Forces the addon to
  actually work as an addon, not as "Godot project we drop code into."
- **`pipeline/`** is engine-agnostic Python. Other projects could use the
  pipeline without the engine, or the engine without the pipeline. Lives
  alongside but is independent.

### Why a `core/` subdir inside `engine/scripts/`

Cross-cutting primitives (Job system, Spatial index, Async asset
streaming, etc.) are consumed by every vertical system. They live in
`core/` to make their special status visible: "if you're touching
anything in `core/`, you affect everything." Vertical systems live in
sibling dirs by domain (`terrain/`, `materials/`, etc.) and explicitly
import from `core/`.

### Why `engine/tests/` vs top-level `tests/`

Two test suites because two language runtimes:
- `tests/` (top-level) — pytest, for Python pipeline code
- `engine/tests/` — gut, for GDScript runtime code (lives next to the
  code being tested, like Godot convention)

Single command `python -m world5.verify` runs both + the capture-based
renderer tests.

### Why `engine/examples/` separate from `demo/`

`demo/` is the comprehensive consumer project that validates forkability.
`engine/examples/` are minimal per-system illustrations (e.g.
`examples/spatial_index_example.tscn`) that get bundled with the addon
so consumers see how to use each piece. Smaller surface, faster to write.

### Why `.godotignore.template`

W4.1's `candidates/` trap (9 GB of pipeline scratch inside the Godot
project root) repeats unless the layout makes it impossible. Anyone
adding a new dir under `engine/` (or `demo/`, or a fork) inherits the
template, which lists default `.godotignore`-able subdirs.

## Producer / consumer contract

- **Producers**: this spec defines the directory contract; every other
  spec assumes the layout and references paths accordingly.
- **Consumers**: every other spec, every script, every doc that
  references a path.

## Dependencies

None. This is bedrock.

## Quality bar

- A clean clone of `world 5/` opens in Godot 4.5 without errors.
- A clean clone, `cd demo/` + open in Godot, runs the demo scene.
- `python -m world5.verify` runs without import errors after Phase 0.
- Forking `demo/` to a new directory, fixing the addon link, the new
  demo runs unchanged. (Verified in Phase 16.)

## Open questions

- **Linkage method for `demo/addons/world5/` ←→ `engine/`**: symlink
  (works on Windows + Unix with `mklink /D` or `ln -s`), git-subtree
  (one repo, no submodule complexity, harder to extract engine), or
  git-submodule (clean separation, extra-step clone for consumers).
  Decided in Phase 0 setup. **Default proposal: symlink during dev,
  with a small `setup.py` script for fresh clones that runs the
  platform-correct `mklink` / `ln -s`. Git-submodule retained as
  documented option for forks that want the harder boundary.**
- **`engine/scripts/audio/` and `ai/` scope**: RESOLVED (audit M2).
  `audio/` IN (audio hooks per spec 34; engine ships zero audio files).
  `ai/` REMOVED (consumer responsibility per inventory).

## References

- W4.1 layout: `world 4/` has `the world 4/` (Godot project) +
  `pipeline/` + `subjects_3d/` + `candidates/` + `docs/` mixed at top
  level. The W4.1 `the world 4/` name + the inner-project nesting were
  the source of multiple traps (PITFALLS #16 — Godot launcher launches
  if path isn't quoted; the 9 GB `candidates/` scan; the LOD scratch).
- Memory entry `w4_godot_root_no_big_assets`: documents the "asset dirs
  must live at parent dir, not inside Godot project root" rule that W5
  bakes into the layout from day 1.

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-audit (M1, M2). Added CHANGELOG/RELEASE_NOTES/
  INSTALL/MIGRATION/LICENSE to `engine/` (referenced by spec 43 but
  missing from layout). Added shipped-mesh dirs (decoration_meshes/,
  foliage_meshes/, cave_meshes/, worlds/) per spec 04 allowlist
  update. Resolved audio/ai scope: audio IN, ai REMOVED.
