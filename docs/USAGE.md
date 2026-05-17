# W5 Usage Guide

> Front door for **how to use** W5. Spec docs (`specs/`) say what W5
> IS; this doc + `workflows/` say how to **run / test / build / edit /
> debug** it.
>
> Per spec 05 doc architecture: this file ≤ 200 lines (navigation
> only). Recipes live in `workflows/`.

## Common tasks (jump in)

### Run all tests
```bash
python -m world5.verify --fast    # ~1s, pytest + gut headless
python -m world5.verify --full    # ~3s, + real GPU + preflight + capture
```
Full recipe: [workflows/running_tests.md](workflows/running_tests.md)

### Open the project in Godot
```bash
# Repo root: D:\assets\world 5\
# Open demo/project.godot in Godot 4.5+
# The addons/world5/ junction → ../../engine/ is already set up.
```

### Test code that uses RenderingDevice / compute shaders
**Cannot use `--headless`** — that disables RenderingDevice. Use:
```bash
godot --display-driver windows --rendering-driver vulkan --path demo \
  --script "res://addons/gut/gut_cmdln.gd" \
  -gtest=res://addons/world5/tests/unit/test_gpu_real_device.gd -gexit
```
Or run `python -m world5.verify --full` which does this automatically
for `test_*_real_device.gd` files.
Full recipe: [workflows/godot_rendering_modes.md](workflows/godot_rendering_modes.md)

### Install the Python pipeline
```bash
pip install -e ./pipeline
python -c "import world5; print(world5.__version__)"   # 0.0.1
```

### Run a specific gut test file
```bash
godot --headless --path demo --script "res://addons/gut/gut_cmdln.gd" \
  -gtest=res://addons/world5/tests/unit/test_smoke.gd -gexit
```
For all gut tests with subdirs: `-gdir=res://addons/world5/tests/ -ginclude_subdirs`

### Run a specific pytest file
```bash
.venv/Scripts/python.exe -m pytest tests/unit/test_log.py -v
```

## Recipes (in `workflows/`)

| File | Topic |
|---|---|
| [running_tests.md](workflows/running_tests.md) | The 4-tier verify CLI; pytest + gut + real GPU + preflight + capture layers |
| [godot_rendering_modes.md](workflows/godot_rendering_modes.md) | `--headless` vs `--display-driver windows`; when to use which; the RenderingDevice gotcha |
| [subagent_review_prompt.md](workflows/subagent_review_prompt.md) | Read-only review subagent prompt template; for parallel multi-lens audits before phase close |

(More recipes land as workflows surface during build.)

## Where the bodies are buried

If you hit something unexpected:
- **Pitfalls** (symptom → cause → fix): [reference/pitfalls/pitfalls_INDEX.md](reference/pitfalls/pitfalls_INDEX.md)
- **Current state**: [STATE.md](STATE.md)
- **What's next**: [ROADMAP.md](ROADMAP.md)
- **System specs**: [specs/](specs/)

## Conventions reminder

- `engine/` = Godot addon source (what gets shipped to consumers)
- `demo/` = consumer Godot project that uses the addon via
  `demo/addons/world5/` junction → `../../engine/`
- `pipeline/` = Python (engine-agnostic content tools)
- Empty dirs marked with `.gitkeep`
- Junction is per-machine, not in git (per [spec 18](specs/18_PLUGIN_INSTALL_AND_DEV_LOOP.md))
- LF line endings repo-wide (`.gitattributes`)
- All logs through `Log.gd` / `world5.log` — no direct `print` /
  `push_*` (Phase 2.11 lint enforces)

## Versions pinned

- **Godot**: 4.6.2 stable mono (`C:/Godot/v4.6.2/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64.exe` on dev)
  - Verified via full verify pass 2026-05-17 (Phase 4.4 close); upgraded from 4.5
  - 4.5 stable binary kept as fallback at `C:/Godot/Godot_v4.5-stable_win64.exe`
- **Python**: 3.12+ (per `pipeline/pyproject.toml`)
- **gut**: 9.4.0 (cloned into `demo/addons/gut/`)
- **W5**: 0.0.1 (per `engine/plugin.cfg`)

## Doc cap status

This file: ~95 lines.
