# Spec: Test Infrastructure

> Status: draft
> Tier: meta
> Depends on: 01_MODULE_LAYOUT
> Consumed by: every system

## Purpose

W4.1's test gap was load-bearing. **pytest** covered Python pipeline
code well (255+ tests at end of W4.1) but caught zero GDScript-side
bugs. The R14 PackedInt32Array silent fail (today, in W4.1) was
invisible to pytest because the bug was in GDScript dict-value-type
semantics; manual visual review caught it after wasted hours.

W5 builds test infrastructure from day 1 with three layers, runnable
via one tiered command, so:
- Python pipeline bugs caught at PR time
- GDScript runtime bugs caught at PR time (not after deploy)
- Renderer regressions caught via capture comparison
- Doc/structural integrity caught via preflight (allowlist, doc-health, world contract)

Plus: **consumers of W5 can run `python -m world5.verify` themselves**
to confirm their integration is sound. This is part of forkability.

## Non-goals

- Replacing Godot's built-in editor tests (we ship our own framework
  because the built-in is too limited)
- Performance benchmark suite (separate concern; profilers + perf
  budgets live in capture tests but aren't called "benchmarks")
- Coverage % gates (we track coverage as a metric, not a gate)

## The three test layers

### Layer 1: pytest (Python)

Standard pytest, lives at `tests/` (top level) + `pipeline/*/tests/`
(per-pipeline-subdir). Covers:
- Pipeline math (kernels, texture generation, decoration generation)
- Cross-impl parity tests (Python ↔ GDScript ↔ C# / GPU)
- Validators / preflight (world contract, allowlist, doc health)
- Pure-data tests for schemas, configs

Run: `pytest tests/ pipeline/*/tests/`.

### Layer 2: gut (GDScript)

[github.com/bitwes/Gut](https://github.com/bitwes/Gut) installed as a
Godot addon under `demo/addons/gut/` (Phase 2.1 lesson: gut needs to
live at the Godot project root's addons/, not nested inside the W5
plugin — Godot expects `addons/gut/...` paths, so it must sit beside
the world5 addon link, not inside it). Test files for W5's engine
classes still live at `engine/tests/unit/` etc. — gut finds them via
the `-gdir=res://addons/world5/tests/` argument. Covers:
- GDScript class behavior (job system, spatial index, async streaming,
  decoration runtime, etc.)
- Per-system logic correctness
- Mock-friendly tests for systems that need Godot runtime without
  full scene tree

Run: `godot --headless --path demo --script res://addons/gut/gut_cmdln.gd
-gdir=res://addons/world5/tests/ -gexit` (wrapped by
`python -m world5.verify`).

**Why gut not custom**: gut is the established Godot test framework.
Building our own would duplicate effort. The fact that W4.1 didn't
adopt it was the gap.

### Layer 3: Capture-based renderer tests

Lives at `engine/tests/perf/` + `engine/tests/visual/`. Three sub-types:

1. **Motion/spin/startup profilers** — auto-walk or auto-spin scenes,
   record frame times, fail if exceeds tier budget (p99, peak, hitches).
   W4.1 pattern; works.
2. **Visual diff probes** — load a scene at a fixed camera pose, capture
   PNG, diff against a golden PNG. Fail on threshold exceeded. Used for
   "is the renderer still producing the right output" regression.
3. **Material/contract probes** — sample fixed world XZ points through
   each ring's splat/material contract; verify ring disagreement = 0,
   drift = 0. W4.1 pattern; works.

Run: Godot headless + capture scenes write JSON manifests; Python
script verifies them.

## The verify command

`python -m world5.verify` with **four** modes (audit S14: original
`--fast ≤ 30s` was unrealistic with gut included; Godot 4.5 headless
launch alone is 3-5s + per-test overhead):

```bash
python -m world5.verify --fastest   # pytest only — ~10s (the constant dev loop)
python -m world5.verify --fast      # pytest + gut (no GPU/Godot scene) — ~90s
python -m world5.verify             # default: fast + preflight — ~3 min (pre-commit)
python -m world5.verify --full      # default + capture-based renderer — ~15 min (CI / pre-release)
python -m world5.verify --layer X   # explicit single-layer run
```

### Mode breakdown

**`--fastest` (target ≤ 15s, constant dev loop, pytest only)**:
- pytest (all Python tests)
- No Godot launch at all

**`--fast` (target ≤ 90s, batched dev loop)**:
- pytest (all Python tests)
- gut (all GDScript tests, headless Godot)
- No renderer captures, no preflight that touches disk-scan

**default mode (target ≤ 2 min, pre-commit gate)**:
- Everything in --fast, plus:
- World contract preflight (validates worlds bundles)
- Godot root allowlist check
- Doc-health check (line caps, broken index links)
- SITEMAP regen + diff (fails if SITEMAP is stale)

**`--full` (target ≤ 15 min, CI / pre-release)**:
- Everything in default, plus:
- Motion/spin/startup profilers (all profile scenes)
- Visual diff probes (all golden-PNG scenes)
- Material/contract probes
- Forkability smoke test (Phase 16; only runs if `demo/` is in tree)

### Exit codes

- `0` — all clear
- `1` — test failure (pytest, gut, capture diff exceeded threshold, etc.)
- `2` — preflight failure (world contract, allowlist, doc health, etc.)
- `3` — environment error (Godot not found, gut not installed, etc.)

### JSON output

`python -m world5.verify --json` produces machine-readable summary:
```json
{
  "version": 1,
  "mode": "default",
  "started_at": "...",
  "duration_s": 87.3,
  "layers": {
    "pytest": {"status": "pass", "tests": 287, "failures": 0, ...},
    "gut": {"status": "pass", "tests": 45, "failures": 0, ...},
    "preflight": {
      "world_contract": "pass",
      "godot_root_allowlist": "pass",
      "doc_health": "pass"
    }
  },
  "overall_status": "pass"
}
```

## Public API

CLI:
```
python -m world5.verify [--fast | --full] [--layer X] [--json] [--help]
```

Python:
```python
from world5.verify import run_verify, VerifyMode, VerifyResult

result: VerifyResult = run_verify(VerifyMode.DEFAULT)
if not result.passed:
    sys.exit(1)
```

## Producer / consumer contract

- **Produces**: a single command that any contributor (or consumer)
  runs to validate their tree. JSON output for LLM consumption.
- **Consumes**: every system's tests + every preflight script.

## Dependencies

- `01_MODULE_LAYOUT` (defines `tests/` and `engine/tests/` locations)
- gut addon (third-party, installed under `engine/addons/gut/`)
- Godot 4.5+ headless mode for gut
- Python 3.12+ for pytest + verify wrapper

## Quality bar

- `--fastest` runs in ≤ 15s on dev hardware (pytest only)
- `--fast` runs in ≤ 90s on dev hardware (pytest + gut headless)
- default runs in ≤ 3 min on dev hardware
- `--full` runs in ≤ 15 min on dev hardware
- Zero false-positive failures on a clean main-branch tree
- Capture diffs use perceptual diff (not bit-exact) to tolerate
  GPU driver variance. Library committed (audit M7):
  **`pixelmatch-py`** (https://github.com/whtsky/pixelmatch-py) — same
  algorithm as the JS canonical, 0.0-1.0 threshold, fast enough for
  CI. Per-test threshold default 0.005 (0.5% as W4 norm).
- Every spec promotion to "shipped" requires `verify` passing in
  default mode

## Discoverability

- **Entry point**: `python -m world5.verify`
- **Schema**: `--json` output is the machine-readable surface
- **Validator / preflight**: verify IS the master validator
- **Example**: `python -m world5.verify --fast --json` is the minimal
  call; output JSON describes what ran + what passed
- **Deterministic outputs**: yes for pytest + gut; capture-based
  layer uses perceptual-diff threshold (deterministic verdict, not
  bit-exact)

## Logging lint integration (audit M11)

Spec 16's "no `print` / `push_*` outside `Log.gd`" lint runs as part
of the default verify mode (not `--fast` or `--fastest`). Lint script
lives at `pipeline/world_contract/logging_lint.py` and walks
`engine/scripts/` for forbidden calls.

## Open questions

- Should `--fast` include world contract preflight, or just code
  tests? Currently excluded from --fast for speed; may need to
  reconsider if world bundles become tightly coupled to code.
- Capture-diff threshold per-test tuning: 0.5% default; may need
  per-test override (e.g. atmosphere scenes more tolerant due to
  GPU shader nondeterminism).
- Should we run `--full` per-PR or per-release? Probably per-release
  given the 15 min target.
- Code coverage: track or ignore? Probably track-but-don't-gate at
  first; revisit if it surfaces.

## References

- W4.1 retrospective lesson 6: "Test discipline holds but lacks
  rendering coverage" — gut closes that gap.
- W4.1's motion/spin/startup profilers (proven pattern, carry
  over the shape, rebuild on Job system).
- gut documentation: github.com/bitwes/Gut

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-audit (S14, M7, M11). Split `--fast` into
  `--fastest` (pytest only ≤ 15s) and `--fast` (+ gut ≤ 90s) since
  Godot headless launch makes the original 30s target infeasible.
  Committed `pixelmatch-py` as the perceptual-diff library. Added
  logging lint integration note.
