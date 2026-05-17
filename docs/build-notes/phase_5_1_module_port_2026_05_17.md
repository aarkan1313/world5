# Phase 5.1 — W4 Texture-Pipeline Module Port (DONE 2026-05-17)

> Phase: 5.1 (sub-phase of Phase 5)
> Status: ✅ done 2026-05-17
> Plan: [phase_5_1_w4_module_port.md](../roadmap/phase_5_1_w4_module_port.md)

## What shipped

15 of 15 ported modules import cleanly + 6 of 6 CLIs respond to
`--help`. Full verify 5/5 layers green stable in 59.8s.

### Modules (11 tx_*.py)

All under `pipeline/world5/textures/`:

| Module | Source | Edits |
|---|---|---|
| `tx_pipeline.py` | W4 | Bare imports → relative-package (`from .tx_X import`); 4 sites: top-level + 3 lazy-inside-function |
| `tx_seamless.py` | W4 | Carry-as-is (ComfyUI subprocess; shared-infra paths kept) |
| `tx_variant_select.py` | W4 | One bare import → relative |
| `tx_pbr_hybrid.py` | W4 | One bare import → relative |
| `tx_pbr_derive.py` | W4 | Carry-as-is |
| `tx_pbr_sm.py` | W4 | Carry-as-is |
| `tx_qa.py` | W4 | Carry-as-is (4 gating + 2 advisory) |
| `tx_family.py` | W4 | Carry-as-is — sibling family generator |
| `tx_seam_repair.py` | W4 | Carry-as-is (PatchMatch fallback) |
| `tx_subject.py` | W4 | Bare import + sys.path trick → relative (subject-mode for foliage/impostors) |
| `tx_macro_terrain.py` | W4 | **Real edits**: rebased path constants from W4 layout (`PROJECT_ROOT = D:/assets/world 4`) onto W5 layout (`W5_ROOT = parents[3]`, `ENGINE_ROOT = W5_ROOT/engine`, defaults point at `worlds/walking_demo`). PURPOSE_PRESETS dict left in-place; per-biome YAML extraction deferred to Phase 5.4.b. |

### Drivers (3 CLIs)

| Driver | Source | Edits |
|---|---|---|
| `diversity.py` | W4 `diversity_run.py` | sys.path trick removed; relative package import; `CANDIDATES_ROOT` rebased to in-W5-repo default + `BIOMES_DIR` at `pipeline/biomes/` |
| `contact_sheet.py` | W4 `build_contact_sheet.py` | `CANDIDATES_ROOT` rebased |
| `review.py` | W4 `diversity_review.py` | `CANDIDATES_ROOT` rebased |

### Skipped (deliberately)

- `pipeline/material_variants.py` (W4) — depends on `biome_catalog.py`
  (another W4-internal module of significant size). **`promote.py`
  already covers the same job** (atomic candidate→world copy with
  manifest update); building another path adds confusion without
  value. Plan amendment noted: 5.1 ships with promote.py as the
  canonical manifest builder; the W4 split-style builder doesn't
  need to land.

## Module dependency graph (post-port)

```
diversity.py
  └→ tx_pipeline.py
       ├→ tx_variant_select.py
       │    └→ tx_seamless.py (ComfyUI subprocess)
       ├→ tx_pbr_derive.py (default fallback)
       ├→ tx_pbr_hybrid.py (lazy, hybrid backend)
       │    └→ tx_pbr_derive.py
       ├→ tx_pbr_sm.py (lazy, SM-only backend)
       ├→ tx_seam_repair.py (lazy, PatchMatch fallback)
       └→ tx_qa.py

tx_family.py (sibling pool generator) — standalone, called by diversity
tx_subject.py — alt subject-mode pipeline for foliage/impostors
tx_macro_terrain.py — world-bundle macro_albedo builder (4.9.c)
contact_sheet.py — review tool, reads candidates/<biome>/<slot>/_index.json
review.py — surfaces below-A candidates

promote.py (W5-native; not a W4 port) — copies candidates → world
```

## What's still NOT in W5 (deferred / blocked)

- **`pipeline/biomes/` (per-biome authoring YAMLs)**: `diversity.py`
  reads `pipeline/biomes/<biome>.yaml` but the dir doesn't exist
  in W5 yet. First biome batch (Phase 5.4.b) creates them — port
  W4's `alpine.yaml` + `forest.yaml` + extract `PURPOSE_PRESETS`
  from `tx_macro_terrain.py`.
- **`tx_qa.py` validation tests**: spec 25 §Quality bar wants
  pytest coverage of the QA gates. Plan says "carry over W4
  coverage." W4 had ad-hoc test scripts; no pytest. **Deferred to
  5.4.b** when the first real biome batch surfaces correctness
  gaps.
- **GPU mutex (audit S5)**: spec 25 §"GPU mutex with TRELLIS"
  documents a contract; no W5 implementation yet. Pre-emptive; not
  critical until Phase 6 (TRELLIS).
- **Cross-project shared infra references**: `tx_pbr_hybrid.py` +
  `tx_pbr_derive.py` + `tx_qa.py` + `tx_seam_repair.py` reference
  `d:/assets/pipelines/textures/` via `sys.path.insert`. These
  paths are correct in W5 too (shared infra outside W5 repo per
  spec 25). The W4 → W5 port doesn't change the shared-infra
  references.

## Verify status

5/5 layers green stable in 59.8s:
- pytest 139 passed (no regression from doc-only sweep + module ports)
- gut headless all passed
- gut_real_gpu all passed
- preflight 0 errors / 1 warning (pre-existing)
- capture all passed

Smoke tests:
- 15/15 ported modules importable via `python -c "import world5.textures.X"`
- 6/6 CLIs respond to `--help` cleanly (tx_pipeline, tx_macro_terrain,
  promote, diversity, contact_sheet, review)

## What's load-bearing post-5.1

- The relative-package import convention (`from .tx_X import Y`) is
  now baked into all 11 ported modules. New texture-pipeline code
  in W5 must use the same pattern. Never use bare `from tx_X` or
  `sys.path.insert(0, str(Path(__file__).parent))` — they only work
  by accident when CWD aligns.
- `tx_macro_terrain.py`'s W5 path defaults (`DEFAULT_WORLD =
  ENGINE_ROOT/worlds/walking_demo`) are the contract for any
  consumer running it without args. Phase 4.9.c will pass
  `--world worlds/<other>` for non-default worlds.
- `tx_pbr_hybrid` lazy-imports `tx_pbr_sm` + `tx_seam_repair` for
  the alt-backend branches; the lazy form prevents a module-load
  failure on missing optional deps from breaking the default path.
- Shared-infra references at `d:/assets/pipelines/textures/` are
  out-of-W5 dependencies. Consumers cloning W5 to fresh machines
  need that path to exist OR `--pbr-backend derive` to skip the
  hybrid path. Phase 5.6 calibration is the natural place to
  document fresh-machine setup.

## Phase 5.1 unblocks

| Sub-phase | Unblocks because |
|---|---|
| **Phase 4.9.c** macro_albedo for walking_demo | `tx_macro_terrain.py` now runs in W5 layout |
| **Phase 5.4.b** detail overlays + sibling tune | `tx_pipeline.py` + drivers can run a real batch |
| **Phase 5.6** calibration on real hardware | Pipeline runs in-repo → measure on author hardware |
| **Audit S6** QA gates | `tx_qa.py` is now in the W5 package; can be wired into preflight |
| **Audit S7** per-biome YAMLs | `pipeline/biomes/` is the documented home; 5.4.b authors them |

## Next sub-phase: 5.4.b OR 4.9.c

Both are short (1-2 sessions) and both unblock the visible-quality
gap the user flagged ("clear lines/transitions tile to tile, chunk
to chunk strangeness").

- **4.9.c macro_albedo** (1 session): generate the missing
  `macro_albedo.png` for walking_demo via the now-ported
  `tx_macro_terrain.py --purpose-candidates --promote-purpose
  --biome alpine`. Fixes the olive-fallback band at the horizon.
- **5.4.b sibling tune + detail overlays** (3-4 sessions): tune
  `sibling_blend_freq` per tier (audit C3) + author the missing
  detail tiles (audit S3). Fixes the tile-to-tile repeat at
  standing-eye-height.

User picks which to start.

## Doc cap status

~210 lines (under 350 cap).
