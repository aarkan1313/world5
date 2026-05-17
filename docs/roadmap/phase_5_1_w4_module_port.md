# Phase 5.1 — W4 Texture-Pipeline Module Port

> Phase: 5.1 (sub-phase of Phase 5)
> Status: 🚧 active (opened 2026-05-17)
> Plan ref: [25_TEXTURE_PIPELINE_PLAN.md §5.1](../plans/25_TEXTURE_PIPELINE_PLAN.md)
> Source: `D:/assets/world 4/pipeline/textures/tx_*.py` (11 files) +
>         `D:/assets/world 4/pipeline/{diversity_*, build_contact_sheet, overnight_queue}.py` (5 drivers)
> Destination: `D:/assets/world 5/pipeline/world5/textures/`

## Why this phase exists

Per Phase 0-5 audit (2026-05-17), every remaining audit item that
isn't kernel/calibration work converges on one unlock: a W5-side
texture pipeline. Currently `pipeline/world5/textures/` contains
only `promote.py` + `__init__.py`. Everything else lives in W4 or
at the texture team's external chain (`D:/tmp/w5_candidates/`).
Phase 5.1 makes the pipeline first-class in W5 so:

- 4.9.c can run `tx_macro_terrain.py --purpose-candidates` to author
  macro_albedo
- 5.4.b can author detail overlays (5-7 per biome)
- 5.6 can re-run diversity batches with calibration measurements
- Fresh devs cloning W5 can produce textures without W4 + external
  chain

## What goes where

Per plan 25 §5.1, every W4 `tx_*.py` ports as **file-copy + path
edit**. Validated by 2026-05-17 staging test (text team did this
test against an external dir). The destination is
`pipeline/world5/textures/` (already exists with `__init__.py` +
`promote.py`).

### Module port table (Phase 5.1.a-d)

| W4 file | W5 destination | Edits needed |
|---|---|---|
| `tx_pipeline.py` | `pipeline/world5/textures/tx_pipeline.py` | Bare imports → package imports (`from .tx_seamless import ...`). Add spec 12 content-address keys at output (deferred OK; promote.py path-resolves) |
| `tx_seamless.py` | `pipeline/world5/textures/tx_seamless.py` | Carry as-is (ComfyUI subprocess; W4 paths kept since ComfyUI is shared cross-project) |
| `tx_variant_select.py` | `pipeline/world5/textures/tx_variant_select.py` | Bare import → package import |
| `tx_pbr_hybrid.py` | `pipeline/world5/textures/tx_pbr_hybrid.py` | Default backend; SM + derive_pbr_v2 subprocess paths point at shared infra (`d:/assets/pipelines/textures/`); leave as-is |
| `tx_pbr_derive.py` | `pipeline/world5/textures/tx_pbr_derive.py` | Carry as-is |
| `tx_pbr_sm.py` | `pipeline/world5/textures/tx_pbr_sm.py` | Carry as-is |
| `tx_seam_repair.py` | `pipeline/world5/textures/tx_seam_repair.py` | Carry as-is (PatchMatch fallback) |
| `tx_qa.py` | `pipeline/world5/textures/tx_qa.py` | Carry as-is (4 gating + 2 advisory) |
| `tx_family.py` | `pipeline/world5/textures/tx_family.py` | Carry as-is — sibling family generator (the load-bearing module spec 25 doesn't currently name explicitly) |
| `tx_macro_terrain.py` | `pipeline/world5/textures/tx_macro_terrain.py` | **Real edits**: `PROJECT_ROOT` + `GODOT_ROOT` + `DEFAULT_*` paths point at W4. Extract `PURPOSE_PRESETS` dict to per-biome YAML alongside `<biome>.yaml`. Per plan: defer the YAML extraction to Phase 5.4.b; for 5.1, just rebase the paths onto W5 layout + add CLI knobs |
| `tx_subject.py` | `pipeline/world5/textures/tx_subject.py` | Carry as-is (the 4th output mode — alpha cutouts for foliage leaves + impostors) |

### Driver port table (Phase 5.1.e)

| W4 file | W5 destination | Edits needed |
|---|---|---|
| `pipeline/diversity_run.py` | `pipeline/world5/textures/diversity.py` | Batch driver. Update import paths to package form (`from world5.textures import tx_pipeline`). Drop W4-specific paths in favor of `--candidates-root` + `--biome` args (matches promote.py shape) |
| `pipeline/build_contact_sheet.py` | `pipeline/world5/textures/contact_sheet.py` | Per-slot contact sheet builder. Same path-arg refactor |
| `pipeline/diversity_review.py` | `pipeline/world5/textures/review.py` | Below-A surfacing CLI. Same refactor |
| `pipeline/material_variants.py` (W4) | `pipeline/world5/textures/material_variants_builder.py` | Sibling manifest builder (turns authoring-config into the runtime manifest). Schema already locked in spec 24 |

**Out of scope for 5.1**:
- `tx_canonicalize_hi`, `tx_trellis`, `tx_lod*` → spec 26 / spec 27
- `tx_img2img`, `tx_inpaint`, `tx_redux` → defer to v0.2 (photo input
  path; validated but not Phase 5 critical)
- `overnight_queue.py` → optional convenience driver; defer

## Out-of-W5 dependencies (NOT W5 deliverables)

Per spec 25 dev-only operator model — these are PREREQUISITES that
the W5 port references but doesn't ship:

| Dependency | Path | Owned by |
|---|---|---|
| ComfyUI runtime | `d:/assets/animators/ComfyUI/` | shared infra |
| FLUX2-klein-9B + Qwen-3-8B + flux2-vae models | `ComfyUI/models/{diffusion_models,text_encoders,vae}/` | shared infra |
| StableMaterials runtime | `d:/assets/animators/mesa-env/venv/` | shared infra |
| `derive_pbr_v2.py`, `delight.py`, `stablematerials_image2pbr.py` | `d:/assets/pipelines/textures/` | shared infra |

The W4 modules reference these via `sys.path.insert(0, r"D:/assets/pipelines/textures")`; keep
those references as-is. They're correct in W5 too.

## Sequence

1. **5.1.a** (this session): orchestrator + seamless + variant_select.
   These are the core 3 with the most coupled imports; doing them
   together lets us validate the package-import refactor pattern.
2. **5.1.b**: PBR backends. tx_pbr_hybrid imports tx_pbr_derive
   internally so order matters.
3. **5.1.c**: QA + family + seam_repair + subject (independent).
4. **5.1.d**: macro_terrain (the only one needing real path edits).
5. **5.1.e**: drivers (need ported modules to import).

## Verify gates

- **After each port batch**: `python -c "from world5.textures import <module>"`
  imports without error
- **After 5.1.e**: each driver's `--help` runs without crashing
- **Final**: full verify 5/5 green stable (pytest + gut +
  gut_real_gpu + preflight + capture). The pipeline modules don't
  ship runtime tests (they're dev-only per spec 25); smoke tests
  via `--help` are the bar
- **End-to-end smoke** (optional, deferred to 5.4.b): kick a
  diversity batch with 1 candidate to confirm the chain runs

## What NOT to do in 5.1

- **Don't rewrite the W4 modules.** Plan says port as-is. The
  modules carry years of tuning; the rewrite-temptation is real but
  out of scope. If something doesn't work, port the W4 fix.
- **Don't extract `PURPOSE_PRESETS` to YAML yet** (plan 25 step 5).
  That's Phase 5.4.b once we have a real per-biome authoring loop.
- **Don't add pytest coverage of the W4 modules** unless porting
  surfaces a bug. They're dev-only per spec 25; smoke tests are
  enough. Phase 5.4.b can add coverage if the first-biome run
  surfaces gaps.
- **Don't touch the W4 source files.** Read-only. The parallel chat
  is still working in W4.

## Open questions

- **`tx_canonicalize_hi.py` truly skip or carry?** It's a one-shot
  W4 migration script. W5 doesn't need it. Skip.
- **`pipeline/material_variants.py`'s exact name in W5?** Plan calls
  it `material_variants_builder.py` to disambiguate from
  `engine/scripts/terrain/material/MaterialVariants.gd`. Going with
  that.
- **Bare imports → relative or absolute?** `from .tx_seamless import X`
  (relative) is cleanest inside the package. Going with that.

## Doc cap status

~155 lines (under 350 cap).
