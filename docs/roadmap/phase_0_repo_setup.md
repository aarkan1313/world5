# Phase 0 — Repo Setup

> Phase: Phase 0 (next, mechanical scaffolding only)
> Status: 🚧 ready to start
> Estimated sessions: 1
> Owner: agent + user joint
>
> Goal: create the directory contract per spec 01 + `engine/plugin.cfg`
> + addon-link mechanism + first commit. No lint scripts, no preflight
> code, no system implementation. Just structure that Phase 2 builds on.

## Scope (what's in)

- Directory tree per spec 01
- `engine/plugin.cfg` (Godot addon manifest)
- `demo/project.godot` (minimal consumer Godot project)
- `demo/addons/world5/` link to `engine/` (mechanism chosen below)
- Empty test harness directories per spec 06
- Empty `pipeline/core/` + per-system stubs per spec 01
- Top-level `world 5/README.md` (project overview)
- Top-level `world 5/.gitignore` (Python venv, build artifacts,
  pipeline `.content_addressed_store/`)
- `engine/.godotignore.template` per spec 04 allowlist
- First commit on `main` branch

## Scope (what's NOT in — deferred to later phases)

- ❌ `pipeline/world_contract/godot_root_check.py` preflight (spec 04;
  → Phase 2)
- ❌ `python -m world5.verify` CLI (spec 06; → Phase 2)
- ❌ Logging lint (spec 16; → Phase 2)
- ❌ Job system, spatial index, async streaming, etc. (Tier 0; → Phase 2)
- ❌ Any test files (just empty test dirs; → Phase 2)
- ❌ Spec status sweep from `draft` → `reviewed` (→ Phase 0 close
  task below)

## Pre-flight (before starting)

- [ ] Confirm we're on `main` branch of W5 repo (NOT a working branch
      from another project)
- [ ] Confirm `D:/assets/world 5/` exists (it does; `docs/` is here)
- [ ] Confirm git is initialized at `D:/assets/world 5/` OR plan to
      `git init` (user check; W4.1 is at `D:/assets/world 4/`, separate)
- [ ] Read spec 01 module layout one more time to make sure tree
      matches

## Decision: addon-link mechanism

Three options (per spec 18):
- **Method A — git submodule**: `addons/world5_engine` submodule + symlink
- **Method B — copy via `setup.py`**: Python script copies `engine/`
  → `demo/addons/world5/`
- **Method C — symlink during dev**: `setup.py` runs `ln -s` / `mklink /D`

Recommendation: **Method C (symlink)** for the bundled `demo/`. Method
A + Method B are for downstream consumer projects, documented but not
the dev-time choice. SA-M2.11 (Windows mklink prereq) is documented
in spec 18.

- [ ] User confirms Method C is the dev-time call
- [ ] `setup.py` (Python) script for Windows + Unix symlink creation
      (deferred to Phase 2; for now, manual symlink at scaffold time
      is fine)

## Directory creation checklist

Reference: spec 01 module layout.

### Top level (`world 5/`)
- [ ] `engine/` — Godot addon (subdirs below)
- [ ] `demo/` — consumer Godot project (subdirs below)
- [ ] `pipeline/` — Python pipeline (subdirs below)
- [ ] `tests/` — pytest top-level (subdirs: `unit/`, `integration/`)
- [ ] `tools/` — one-off scripts dir (empty)
- [ ] `world 5/README.md` — top-level project overview
- [ ] `world 5/.gitignore` — Python venv, pipeline store, build artifacts
- [ ] `world 5/.godotignore.template` — default ignore rules

### `engine/`
- [ ] `engine/plugin.cfg` — Godot addon manifest (name, version 0.0.1,
      description, autoload list)
- [ ] `engine/README.md` — how to install + use the addon (1-page)
- [ ] `engine/LICENSE` — placeholder; pick before v0.1.0
- [ ] `engine/CHANGELOG.md` — empty Keep-a-Changelog skeleton
- [ ] `engine/scripts/` empty
- [ ] `engine/scripts/core/` empty (Phase 2 fills this)
- [ ] `engine/scripts/terrain/` empty
- [ ] `engine/scripts/materials/` empty
- [ ] `engine/scripts/decoration/` empty
- [ ] `engine/scripts/foliage/` empty
- [ ] `engine/scripts/atmosphere/` empty
- [ ] `engine/scripts/lighting/` empty
- [ ] `engine/scripts/water/` empty
- [ ] `engine/scripts/weather/` empty
- [ ] `engine/scripts/caves/` empty
- [ ] `engine/scripts/deformation/` empty
- [ ] `engine/scripts/persistence/` empty
- [ ] `engine/scripts/nav/` empty
- [ ] `engine/scripts/camera/` empty
- [ ] `engine/scripts/audio/` empty (IN per SA-M2; audio hooks only)
- [ ] `engine/scenes/` empty
- [ ] `engine/scenes/components/` empty
- [ ] `engine/scenes/test_harness/` empty
- [ ] `engine/shaders/` empty
- [ ] `engine/resources/` empty
- [ ] `engine/tests/` empty (Phase 2: install gut here)
- [ ] `engine/tests/unit/` empty
- [ ] `engine/tests/integration/` empty
- [ ] `engine/tests/perf/` empty
- [ ] `engine/examples/` empty
- [ ] `engine/decoration_meshes/` empty (Phase 7+ populates)
- [ ] `engine/foliage_meshes/` empty (Phase 8+ populates)
- [ ] `engine/cave_meshes/` empty (Phase 12+ populates)
- [ ] `engine/worlds/` empty (Phase 6 ships first demo world here)

### `demo/`
- [ ] `demo/project.godot` — minimal Godot project (Godot 4.5,
      Vulkan/Forward+ renderer, no autoloads yet)
- [ ] `demo/addons/world5/` — symlink to `../../engine/`
- [ ] `demo/scenes/` empty
- [ ] `demo/worlds/` empty
- [ ] `demo/scripts/` empty
- [ ] `demo/resources/` empty
- [ ] `demo/README.md` — how to run the demo (will say "demo scenes
      not built yet" until Phase 4)

### `pipeline/`
- [ ] `pipeline/core/` empty
- [ ] `pipeline/kernels/` empty
- [ ] `pipeline/textures/` empty
- [ ] `pipeline/decoration/` empty
- [ ] `pipeline/foliage/` empty
- [ ] `pipeline/trellis/` empty
- [ ] `pipeline/nav/` empty
- [ ] `pipeline/world_contract/` empty
- [ ] `pipeline/lighting/` empty
- [ ] `pipeline/atmosphere/` empty
- [ ] `pipeline/water/` empty
- [ ] `pipeline/weather/` empty
- [ ] `pipeline/caves/` empty
- [ ] `pipeline/persistence/` empty
- [ ] `pipeline/impostors/` empty
- [ ] `pipeline/lod/` empty
- [ ] `pipeline/roads/` empty
- [ ] `pipeline/bake_recipes/` empty
- [ ] `pipeline/migrations/` empty
- [ ] `pipeline/release/` empty
- [ ] `pipeline/forkability/` empty
- [ ] `pipeline/pyproject.toml` — editable-install package skeleton
      (SA-S5.7); name `world5-pipeline`; version 0.0.1
- [ ] `pipeline/README.md` — what's here, how to install

### Spec status sweep (Phase 0 close task)
- [ ] All 47 specs reviewed via audit + self-audit pass — promote
      `draft` → `reviewed` in a single sweep. NEW specs added by
      future phases start at `draft`.

## Commit

- [ ] `git status` — confirm only the new scaffold files are tracked
- [ ] `git add` only the scaffold (no `git add -A`; per safety
      protocol)
- [ ] First commit message:
```
chore: Phase 0 — repo scaffold per spec 01 module layout

- engine/ + demo/ + pipeline/ + tests/ + tools/ trees created
- engine/plugin.cfg + minimal demo/project.godot
- demo/addons/world5 symlinks engine/ (Method C per spec 18)
- pipeline/pyproject.toml editable-install skeleton
- empty test harnesses (Phase 2 populates)
- top-level README, .gitignore, .godotignore.template

Refs: spec 01_MODULE_LAYOUT.md, spec 04 allowlist, ROADMAP.md
```

## After commit

- [ ] Update [STATE.md](../STATE.md): "What exists" gains engine/demo/
      pipeline scaffold + plugin.cfg
- [ ] Update [STATE.md](../STATE.md) "Recent activity": Phase 0 done
- [ ] Update [ROADMAP.md](../ROADMAP.md): Phase 0 row → ✅ done; Phase
      2 row → 🚧 in progress
- [ ] Write build-note at `docs/build-notes/phase_0_repo_setup_2026_MM_DD.md`
- [ ] Create `docs/roadmap/phase_2_foundations.md` checklist (next
      phase)

## Verification

After Phase 0 closes:
- [ ] `demo/project.godot` opens in Godot 4.5 without errors
- [ ] Godot editor shows `addons/world5` in FileSystem as the
      symlinked engine/
- [ ] `pip install -e ./pipeline` succeeds (editable install)
- [ ] `python -c "import world5; print(world5.__file__)"` works
- [ ] `git log --oneline` shows the Phase 0 commit
- [ ] No files outside the allowlist are present in engine/ or demo/

## Open questions / decisions to lock during Phase 0

- [ ] Does `world 5/` need its own git repo (`git init` now) or live
      inside an existing one? (Currently `D:/assets/.git` exists at
      parent level; user decides)
- [ ] Initial commit on `main` or new branch then merge? (User decides;
      safety protocol says new commit only when explicitly requested)
- [ ] License choice for `engine/LICENSE` (MIT? Apache 2.0? Custom?
      Can defer to v0.1.0 release prep)

## Doc cap status

This file: ~190 lines (under 300 cap; well-scoped per-phase checklist).
