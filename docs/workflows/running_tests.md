# Workflow: Running Tests

> How to run W5's tests. The verify CLI is the single entry point;
> direct pytest/gut invocation is for debugging specific tests.
>
> See [spec 06 TEST_INFRASTRUCTURE](../specs/06_TEST_INFRASTRUCTURE.md)
> for the contract; this doc is the user-facing recipe.
> See [godot_verify_gut_command_reference.md](godot_verify_gut_command_reference.md)
> for the pinned Godot/GUT command reference and current session quirks.

## TL;DR

```bash
.venv/Scripts/python.exe -m world5.verify --fastest   # pytest only, ~0.3s
.venv/Scripts/python.exe -m world5.verify --fast      # + gut headless, ~1s
.venv/Scripts/python.exe -m world5.verify             # + preflight, ~3 min (pre-commit gate)
.venv/Scripts/python.exe -m world5.verify --full      # + real GPU + capture, ~15 min (pre-release)
```

## The 4 verify tiers

Per spec 06 + SA-S14 (the original `--fast ≤ 30s` was unrealistic;
split + relaxed).

| Tier | Runs | Target time | When to use |
|---|---|---|---|
| `--fastest` | pytest only | ≤ 15s | Constant dev loop (every save) |
| `--fast` | + gut (headless) | ≤ 90s | Batched dev loop (every 5-10 saves) |
| default | + preflight | ≤ 3 min | Pre-commit gate |
| `--full` | + real-GPU gut + capture | ≤ 15 min | Pre-release / CI |

Current measured times (Phase 2.6, 127 tests):
- `--fastest`: 0.3s (54 pytest cases)
- `--fast`: 0.9s (+ 70 gut headless cases)
- default: 0.9s (preflight stub; real preflight lands Phase 2.11)
- `--full`: 2.9s (+ 3 real GPU cases incl. compute shader dispatch)

## Output formats

### Human (default)
```
W5 verify (fast) -- pass in 0.9s
  [  OK] pytest       0.3s  {'returncode': 0, 'summary': '54 passed in 0.10s'}
  [  OK] gut          0.6s  {'returncode': 0}
```

ASCII markers (`OK` / `FAIL` / `ERR` / `skip`) — Windows cp1252 console
can't render unicode checkmarks; this avoids the encoding error.

### JSON (for LLM agents + CI)
```bash
.venv/Scripts/python.exe -m world5.verify --fastest --json
```
```json
{
  "version": 1,
  "mode": "fastest",
  "started_at": "2026-05-16T19:31:59",
  "duration_s": 0.28,
  "layers": {
    "pytest": {"status": "pass", "duration_s": 0.28, "returncode": 0,
               "summary": "54 passed in 0.10s"}
  },
  "overall_status": "pass",
  "exit_code": 0
}
```

## Exit codes (per spec 06)

| Code | Meaning |
|---|---|
| 0 | all clear |
| 1 | test failure (pytest / gut) |
| 2 | preflight failure (world_contract / allowlist / etc.) |
| 3 | environment error (Godot not found, gut missing, etc.) |

CI / pre-commit hooks should fail on non-zero.

## Running individual tests

### Specific pytest file
```bash
.venv/Scripts/python.exe -m pytest tests/unit/test_log.py -v
```

### Specific pytest test by name
```bash
.venv/Scripts/python.exe -m pytest tests/unit/test_log.py::test_json_format_valid -v
```

### Specific gut file (headless mode; no RenderingDevice)
```bash
"/c/Godot/v4.6.2/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64.exe" --headless --path demo \
  --script "res://addons/gut/gut_cmdln.gd" \
  -gtest=res://addons/world5/tests/unit/test_log.gd -gexit
```

### All gut tests in a dir (recurse subdirs)
```bash
"/c/Godot/v4.6.2/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64.exe" --headless --path demo \
  --script "res://addons/gut/gut_cmdln.gd" \
  -gdir=res://addons/world5/tests/ -ginclude_subdirs -gexit
```

### Tests that need real RenderingDevice (compute shaders, etc.)
```bash
"/c/Godot/v4.6.2/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64.exe" \
  --display-driver windows --rendering-driver vulkan --path demo \
  --script "res://addons/gut/gut_cmdln.gd" \
  -gtest=res://addons/world5/tests/unit/test_gpu_real_device.gd -gexit
```
Why no `--headless`: see [godot_rendering_modes.md](godot_rendering_modes.md).

## Test layout

```
tests/                                  # Python (pytest)
├── unit/
│   ├── test_log.py                     # per-module unit tests
│   ├── test_version.py
│   ├── test_smoke.py
│   └── test_spatial_index.py
└── integration/
    └── test_quality_tiers_cross_impl.py  # cross-impl Python ↔ GDScript

engine/tests/                           # GDScript (gut)
├── unit/
│   ├── test_smoke.gd
│   ├── test_log.gd
│   ├── test_world5.gd
│   ├── test_job_system.gd
│   ├── test_gpu_cpu_contract.gd        # class-shape (headless OK)
│   ├── test_gpu_real_device.gd         # real GPU (needs Vulkan window)
│   └── test_spatial_index.gd
├── integration/
│   └── test_quality_tiers_parity.gd    # gut-side cross-impl
├── perf/                               # capture-based profilers (Phase 4+)
└── visual/                             # capture-based visual diff (Phase 4+)
```

## Writing new tests

### Python (pytest)
- File: `tests/<unit|integration>/test_<system>.py`
- Test names: `def test_*():`
- Use `pytest.fixture` for setup; `pytest.raises` for expected errors
- Cross-impl tests live in `tests/integration/`; mirror in
  `engine/tests/integration/`

### GDScript (gut)
- File: `engine/tests/<unit|integration>/test_<system>.gd`
- Extend `GutTest`
- Test names: `func test_*() -> void:`
- Use `before_each()` / `after_each()` for setup/teardown
- Every test MUST assert something (or call `pending()`) — gut flags
  "Risky: Did not assert"

**Cross-impl + naming gotcha** (pitfall meta-1): GDScript classes
can't have static methods named `get` / `load` / `set` (Godot
builtins on Object). Rename to `get_tier` / `load_config` / etc.
Python side has no such conflict.

## Debugging failed tests

### pytest verbose + stop on first fail
```bash
.venv/Scripts/python.exe -m pytest tests/ -vx
```

### gut verbose output
The gut runner prints test names + per-test status by default. Look
for `SCRIPT ERROR: Parse Error:` lines in stderr — those mean the
test file has a syntax / shadowing issue (see pitfall meta-1).

### Re-import Godot's class registry
After adding a new `class_name` GDScript file, gut may report
"GUT class_names have not been imported." Fix:
```bash
"/c/Godot/v4.6.2/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64.exe" --headless --path demo --import
```

## See also

- [spec 06 TEST_INFRASTRUCTURE](../specs/06_TEST_INFRASTRUCTURE.md) — the contract
- [godot_rendering_modes.md](godot_rendering_modes.md) — headless vs windowed
- [pitfalls_INDEX.md](../reference/pitfalls/pitfalls_INDEX.md) — bugs to recognize

## Doc cap status

This file: ~170 lines.
