# Plan: Texture Pipeline Implementation (Phase 5)

> Spec: [25_TEXTURE_PIPELINE.md](../specs/25_TEXTURE_PIPELINE.md)
> Phase: 5 (ground texture pipeline; one biome end-to-end, then second)
> Created: 2026-05-17
> Status: draft (pre-execution; validated via 2026-05-17 staging test)

This plan is **workflow-first**, not module-first. Spec 25 describes
*what the pipeline produces*; this plan describes *what you actually do
when you sit down to author a biome's textures*. It's reverse-engineered
from the W4 working pipeline + validated via a staging-area test
(2026-05-17) that ran the full chain end-to-end against real models
and real prompts.

Per spec 02 lifecycle: spec → **plan** → implement. This plan locks
build order + tooling-glue deliverables + the per-biome authoring loop.

## Operator model (decided 2026-05-17)

W5's texture pipeline is **author-side / dev-only**:
- You (the author) run it on your dev hardware (RTX 5090 Laptop)
- It produces PBR sets baked into world bundles
- Consumer games receive baked artifacts in `worlds/<world>/materials/`,
  NOT pipeline access
- The 90s-per-material target in spec 25 (3060/4060 framing) is irrelevant;
  perf is measured on author hardware

Implication: `pipeline/textures/` is dev-side only. It is **NOT** part of
the shipped Godot addon (`engine/`). Consumer projects forking W5 get
the texture artifacts, not the pipeline.

## Cross-project shared dependencies (NOT W5 deliverables)

The pipeline lives inside W5 but depends on a cross-project substrate
that lives outside the W5 repo:

| Dependency | Path | Owned by |
|---|---|---|
| ComfyUI runtime | `d:/assets/animators/ComfyUI/` | shared infra |
| FLUX2-klein-9B + Qwen-3-8B + flux2-vae models | `ComfyUI/models/{diffusion_models,text_encoders,vae}/` | shared infra |
| StableMaterials runtime | `d:/assets/animators/mesa-env/venv/` | shared infra |
| `derive_pbr_v2.py`, `delight.py`, `stablematerials_image2pbr.py` | `d:/assets/pipelines/textures/` | shared infra |

These are **prerequisites**, not W5 deliverables. Verified present in
the 2026-05-17 staging test. If any goes missing, `tx_pbr_hybrid.py`
breaks via subprocess error.

## Reading order for the implementer

Before writing code, read in this order:
1. [25_TEXTURE_PIPELINE.md](../specs/25_TEXTURE_PIPELINE.md) — the contract
   (4 output modes, GPU mutex with TRELLIS, QA bar)
2. [24_GROUND_VARIETY.md](../specs/24_GROUND_VARIETY.md) — the 3-layer
   distance composition (siblings + detail + macro)
3. [23_MATERIALS_PBR.md](../specs/23_MATERIALS_PBR.md) — runtime kit shape
4. W4 [`features/textures.md`](../../../world%204/docs/features/textures.md)
   — canonical W4 workflow doc; almost everything below is its W5 port
5. W4 [`pipeline/textures/README.md`](../../../world%204/pipeline/textures/README.md)
   — module-level reference for the `tx_*` files we're porting
6. W4 [`material_variants_config.json`](../../../world%204/the%20world%204/worlds/scale_v2/material_variants_config.json)
   — the sibling-pool schema (locked, see below)

## The authoring workflow (the actual thing this plan exists to enable)

This is what you do, per biome. ~6-10 hours wall clock, ~4-6 hours
active attention per biome on RTX 5090 Laptop. First biome takes longer
because tooling glue is still being built.

### Step 1 — Author two prompt YAMLs (15-30 min, manual)

Per biome, you write **two** YAMLs:

| File | Purpose | Candidates |
|---|---|---|
| `pipeline/biomes/<biome>.yaml` | Discovery pool — diverse prompts across all slots | 40-60 (ground+mid+rock combined; W4 alpine = 51) |
| `pipeline/biomes/<biome>_siblings.yaml` | Sibling pool — N prompts describing the **same** anchor concept with phrasing variation | 30 (W4 alpine_siblings convention) |

YAML shape per W4 (locked, validated 2026-05-17):
```yaml
biome: <biome>
prompt_prefix: "tileable seamless texture, "
prompt_suffix: ", overhead perspective"
slots:
  <slot>:
    category: Snow | Sand | Mixed | Rock | Concrete | Foliage | Ground | ...
    candidates:
      - tag: <short_id>
        body: "<descriptive prompt body>"
```

**Why two YAMLs**: discovery pool gives you 5-10× more candidates than
you ship, so promotion has real options. Sibling pool produces the
palette-locked family that Layer 1 of spec 24 stochastic-UV needs.
W4 evidence: `alpine_siblings.yaml` shipped 30 prompts all describing
"dense firn snow" with phrasing variation; 4 of those became the alpine
ground sibling family in `material_variants.json`.

**Author cost note**: writing 80-90 prompts per biome is the creative
bottleneck. Pillar 4 (no deadline) — take the time. Spec 24's
"~48 effective variants per slot" math depends on this pool size.

### Step 2 — Run the diversity batch (1-2 hours, mostly unattended)

```bash
python -m world5.textures.diversity --biome alpine
python -m world5.textures.diversity --biome alpine_siblings
```

Iterates every candidate through the 5-stage pipeline
(seamless → variant_select → delight → pbr_hybrid → seam_repair → qa).
Writes to `candidates/<biome>/<slot>/<NN>_<tag>/` with full PBR set +
manifest + auto-grade. Already-done candidates skipped (idempotent
resume).

**Measured perf on RTX 5090 Laptop (2026-05-17 staging test)**:
~47s per material at 1024px × 2 variants. Extrapolating: 4 variants
adds proportionally → ~80-90s per material at production settings
(1024px × 4 variants).

- 51 base + 30 sibling candidates = 81 materials per biome
- 81 × ~80s = **~110 min wall time for a full biome on 5090 Laptop**

Always use `--size 1024`. The 4-pass FLUX + SM hybrid is calibrated
against 1024 outputs; **at 512 the seam-repair patch is proportionally
too large and visible midline crosses survive** (confirmed 2026-05-17).
Reduce candidate count or variant count to shrink wall time, never
resolution.

GPU mutex with TRELLIS: cannot run both simultaneously. Spec 25
documents this.

### Step 3 — Auto-grade + visual review (1-2 hours, manual)

```bash
python -m world5.textures.contact_sheet --biome alpine
```

Builds `candidates/alpine/<slot>/_contact_sheet.png` per slot. The
QA stage already ran during step 2 and wrote `qa.json` + a status
field in `_index.json`.

**The irreducibly human step**: open the contact sheets, look at every
candidate. **Auto-grade and visual quality diverge in both directions**
(confirmed 2026-05-17 forest mid test, 4 candidates):
- A-grade outputs that read as washed-out or off-prompt are common
- B-grade outputs that fail one metric (often `periodic_artifact`) can
  still be the visually-strongest pick
- Treat the grade as a triage hint, not a verdict

W4 grade distribution (alpine ground, 16 candidates):
- A-grade: ~half (passed all 4 gates)
- B-grade: ~third (failed one gate, usually `periodic_artifact`)
- C/D: rare (genuine seam failures)

Optional companion review CLI:
```bash
python -m world5.textures.review --biome alpine
```
Lists every below-A candidate with metric breakdown + reason.

### Step 4 — Promote winners (currently manual in W4 — Phase 5 deliverable: tool it)

For each (biome, slot) you pick:
- **1 base winner** → promotes to `worlds/<world>/materials/biome_<biome>/<slot>/{albedo,normal,roughness,ao}.png`
- **4 sibling winners** → promote to `materials/biome_<biome>/<slot>_variants/v0_*.png` ... `v3_*.png` + add entries to `material_variants.json`

W4's pain: this is **96 file moves per biome** (6 slots × 4 siblings ×
4 PBR maps), all by hand in Explorer. One typo silently breaks a sibling
group; surfaces 2 hours later when you walk the demo.

**Phase 5 ships `promote.py`**:
```bash
python -m world5.textures.promote \
    --biome alpine \
    --world worlds/walking_demo \
    --slot ground --base 03_firn_dense \
    --slot ground --siblings s05_firn s07_firn s09_firn s11_firn \
    --slot mid --base ...
    ...
```
- Copies files from `candidates/...` to `worlds/.../materials/...`
- Renames to canonical layout
- Updates `material_variants.json` with the new sibling list
- Runs preflight; refuses to commit if validation fails
- Prints a diff of what changed (which files in/out, manifest deltas)

This is the **single highest-leverage Phase 5 tooling deliverable**.
Without it, sibling authoring is hand-typed file gymnastics.

### Step 5 — Build macro albedo (1 hour, mostly unattended)

```bash
python -m world5.textures.macro_terrain --biome alpine --purpose-candidates
# review captures/macro_albedo_compare_*.png
python -m world5.textures.macro_terrain --biome alpine --purpose-candidates --promote-purpose
```

Two modes (carry over from W4):
- **Derived** (default): blur + downsample the promoted ground tile
- **Purpose** (`--purpose-candidates`): generate new low-frequency biome
  image from a palette + noise. Reads better per W4 evidence.

**Default for Phase 5**: purpose mode. Derived stays as a fallback for
biomes where you don't want to author a palette config.

Per-biome palette config inside `tx_macro_terrain.py` (W4 has
`PURPOSE_PRESETS` dict; W5 port: extract to per-biome YAML alongside
`<biome>.yaml`).

### Step 6 — Build detail overlays (2-3 hours per biome)

New for W5 (W4 didn't ship these). Same flow as base textures:

```bash
python -m world5.textures.diversity --biome alpine --detail-overlays
```

Per biome: 5-7 detail tiles (wet, moss, grunge, snow, lichen, dust,
cracks). Each is a semi-transparent PBR overlay — same FLUX → delight
→ derive_pbr stack but with prompts tuned for "subject is the texture,
background is gray 40% so threshold-to-alpha works."

Output: `worlds/<world>/materials/biome_<biome>/detail/<tag>_{albedo,normal,roughness,ao}.png`
+ per-biome `detail_array.json` listing them with per-slot blend weights.

Shared across systems: weather (wetness during rain), decoration
(splat decals around point sources), deformation (scorch overlays),
roads (dirt/cobblestone). Not just ground-variety-only.

### Step 7 — World contract preflight (5 min, gates everything)

```bash
python -m world5.world_contract --world worlds/walking_demo --strict
```

Catches: missing maps, wrong sizes for active tier, shader cap exceeded,
missing macro_albedo, sibling count mismatch, detail array out of range,
orphan files in materials/.

**This step is the merge gate.** Preflight must be green before launching
Godot to verify visually.

### Step 8 — Visual verify in editor (30-60 min per iteration)

Launch walking demo, walk the world, look at:
- **Close-field** (0-50m): does the sibling pool read varied?
- **Mid-field** (30-150m): do detail overlays add character?
- **Far-field** (150m+): does macro_albedo break the repeat?
- **Slope transitions**: ground/mid/rock blends natural?
- **Biome edges**: splat blend hides the seam?

Any of these failing → back to step 4 (re-pick winners) or step 1
(rewrite prompts + rerun batch for one slot).

**Editor launch command**: per `editor_launch_workflow` memory rule,
print the launch command for the user. Don't background-launch from
the agent harness.

## Per-biome ground-up budget

**~6-10 hours wall clock per biome on RTX 5090 Laptop** (sum of step
wall-times above). First biome (walking_demo alpine) longer because
tooling glue still being built; second biome (Phase 6) hits the lower
bound once tools are stable.

## Phase 5 deliverables (what we build)

### Sub-phase 5.1 — Module port from W4 (1-2 sessions)

Port these W4 modules to `pipeline/textures/` with refactor for spec 01
module layout + spec 12 content addressing. **The 2026-05-17 staging
test confirmed these 8 modules port as file-copy + one path edit**
(`CANDIDATES_ROOT`). No refactor of the W4 module internals is needed.

| W4 file | W5 path | Refactor |
|---|---|---|
| `tx_pipeline.py` | `pipeline/textures/tx_pipeline.py` | Add spec 12 content-address keys; drop W4 path globals |
| `tx_seamless.py` | `pipeline/textures/tx_seamless.py` | Carry as-is (ComfyUI subprocess) |
| `tx_variant_select.py` | `pipeline/textures/tx_variant_select.py` | Carry as-is |
| `tx_pbr_hybrid.py` | `pipeline/textures/tx_pbr_hybrid.py` | Default backend; SM + derive_pbr_v2; subprocess paths to shared infra |
| `tx_pbr_derive.py` | `pipeline/textures/tx_pbr_derive.py` | Alt backend |
| `tx_pbr_sm.py` | `pipeline/textures/tx_pbr_sm.py` | Alt backend |
| `tx_seam_repair.py` | `pipeline/textures/tx_seam_repair.py` | PatchMatch fallback |
| `tx_qa.py` | `pipeline/textures/tx_qa.py` | Carry as-is; 4 gating + 2 advisory |
| `tx_family.py` | `pipeline/textures/tx_family.py` | **Sibling family generation** — the load-bearing W4 file spec 25 doesn't currently name |
| `tx_macro_terrain.py` | `pipeline/textures/tx_macro_terrain.py` | Extract `PURPOSE_PRESETS` dict to per-biome YAML |
| `tx_subject.py` | `pipeline/textures/tx_subject.py` | The 4th output mode (alpha cutouts for foliage leaves + impostors) |

Out of scope for spec 25 (move to spec 26 TRELLIS or drop):
- `tx_trellis.py`, `tx_lod*`, `tx_lod_bake*` → spec 26 / spec 27
- `tx_img2img.py`, `tx_inpaint.py`, `tx_redux.py` → defer to v0.2 (photo input path; validated but not Phase 5 critical path)
- `tx_canonicalize_hi.py` → one-shot W4 migration; not needed in W5

### Sub-phase 5.2 — Drivers + glue (1 session)

| File | Purpose | W4 origin |
|---|---|---|
| `pipeline/textures/diversity.py` | Batch driver (was W4 `diversity_run.py`) | Port |
| `pipeline/textures/contact_sheet.py` | Per-slot contact sheet builder | W4 `build_contact_sheet.py` |
| `pipeline/textures/review.py` | Below-A surfacing CLI | W4 `diversity_review.py` |
| **`pipeline/textures/promote.py`** | **NEW — promotion tool that doesn't exist in W4** | net-new |
| `pipeline/textures/material_variants.py` | Sibling manifest builder | W4 `material_variants.py` |

`promote.py` is the workflow-critical net-new deliverable (gap A in the
workflow review). Spec by example above (step 4).

### Sub-phase 5.3 — Spec amendments (0.5 session)

Three small spec edits to capture the workflow-driven decisions:
- **Spec 25**: add "Per-biome YAML layout" section (two-YAML pattern); commit purpose-mode as macro default; note dev-only operator model + drop 3060 perf framing
- **Spec 24**: absorb `material_variants_config.json` schema as the canonical Layer 1 contract (carry from W4)
- **Spec 23**: update on-disk example to show `<slot>_variants/v*_*.png` layout

### Sub-phase 5.4 — First biome (walking_demo alpine refresh) (2-3 sessions)

Execute the workflow steps 1-8 above against the existing walking demo's
alpine biome. Goal: walking demo's close-field reads as varied
(currently only Layer 3 shipped per Phase 4 close).

Deliverables:
- `pipeline/biomes/alpine.yaml` + `alpine_siblings.yaml` (port from W4)
- `worlds/walking_demo/materials/biome_alpine/{ground,mid,rock}/{base PBR set + v0-v3 sibling sets}`
- `worlds/walking_demo/materials/biome_alpine/detail/<5-7 overlays>`
- `worlds/walking_demo/macro_albedo.png` (purpose mode)
- `worlds/walking_demo/material_variants.json`
- Updated `detail_array.json` per biome
- Visual review pass in walking demo

### Sub-phase 5.5 — Spec 24 Layer 1 + Layer 2 shader work (1-2 sessions)

Phase 4 deferred Layer 1 + Layer 2 because the textures didn't exist.
Now they do. Land:
- Variety shader: 3-tap stochastic UV blend (Heitz-Neyret) for siblings
- Detail array sampling in fragment shader (1-2 layers per fragment)
- Per-tile sibling selection via world-anchored hash

Per spec 21 material module: `material/MaterialPipeline.gd` +
`variety_common.gdshaderinc` already exist from Phase 4; Phase 5
extends them.

### Sub-phase 5.6 — Calibration (0.5 session)

Measure on author hardware (RTX 5090 Laptop):
- Per-material wall time (2026-05-17 staging test: ~47s at 1024px ×
  2 variants; estimated ~80s at 1024px × 4 variants — calibrate during
  first real biome batch)
- Per-biome batch total
- Memory peak during batch (does the FLUX 9B stack + Qwen3-8B + SM
  fit comfortably? Staging test ran clean on 24 GB VRAM)
- Disk: per-biome total bytes (W4 ref: ~960 MB for the full 30-layer
  variants manifest at scale_v2)

Update spec 25 Quality bar with measured numbers; replace the 3060
extrapolation with author-hardware reality.

## Sibling manifest schema (locked, port from W4)

`worlds/<world>/material_variants.json` shape:

```json
{
  "schema_version": 1,
  "world_seed": 42,
  "region_size_m": 512.0,
  "edge_blend_m": 48.0,
  "max_variants_per_slot": 8,
  "max_total_variant_layers": 256,
  "slots": [
    {
      "biome": "alpine",
      "slot": "ground",
      "variants": [
        { "id": "default",   "source": "ground",                  "weight": 1.0 },
        { "id": "firn_s09",  "source": "ground_variants/firn_s09", "weight": 1.0 },
        { "id": "firn_s07",  "source": "ground_variants/firn_s07", "weight": 1.0 },
        { "id": "firn_s05",  "source": "ground_variants/firn_s05", "weight": 1.0 }
      ]
    },
    ...
  ]
}
```

Validation rules (W4-proven):
- `region_size_m > 0`; `edge_blend_m < region_size_m / 4` (sanity)
- per-slot variants ≤ `max_variants_per_slot` (shader cap, 8)
- sum of variants across all slots ≤ `max_total_variant_layers`
- each `source` path must exist under the world's materials/ tree
- `world_seed` is the deterministic salt; same seed → same sibling
  selection at any (x, z)

Authoring config (`worlds/<world>/material_variants_config.json`) is
*input* to the manifest builder; manifest is the runtime artifact.

## Open questions to lock during Phase 5

| Question | Lock-by point |
|---|---|
| Per-material wall time on RTX 5090 Laptop at 1024×4 | end of 5.1 (first real batch run) |
| Sibling count per slot (4 vs 6 vs 8) | end of 5.4 visual review |
| Macro purpose vs derived as default | committed: purpose (per W4 evidence) |
| Detail overlay count per biome (5 vs 7) | end of 5.4 visual review |
| Whether photo-input path (`tx_img2img`) ships v1 | end of 5.4 — decide based on biome 1 result |

## Out of scope (deferred to later phases)

- Pre-authoring biomes beyond walking_demo alpine (Phase 6 owns second biome)
- ComfyUI subprocess optimization (W4's pattern works)
- Alt PBR backends beyond hybrid (alts ship but don't get further dev)
- SAM-based detail-overlay segmentation (threshold-based is enough for v1)

## Staging-area validation (2026-05-17)

Before this plan was finalized, the workflow was validated end-to-end
in a staging dir (`d:/tmp/w5_texture_port/`) that mirrored what the
W5 port will look like. Results:

- ✅ Module port = file-copy + one path edit (`CANDIDATES_ROOT`).
  No W4 internals needed refactoring.
- ✅ ComfyUI HTTP at 127.0.0.1:8188, ~25s warmup from cold start
- ✅ All shared dependencies resolved (`mesa-env`, `pipelines/textures/`,
  model files in `ComfyUI/models/`)
- ✅ Full 5-stage pipeline runs cleanly: seamless → variant_select →
  delight → pbr_hybrid → seam_repair → qa
- ✅ Output tree shape matches plan exactly: `candidates/<biome>/<slot>/
  <NN>_<tag>/{albedo,normal,roughness,ao,height,metallic}.png + qa.json
  + manifest.json + prompt.txt + variants/`
- ✅ `_index.json` per slot tracks grade + threshold + status
- ⚠️ **Size matters**: 512px test produced visible midline-cross seams
  even after `tx_seam_repair`; 1024px test produced clean output.
  Always use 1024.
- ⚠️ **Auto-grade ≠ visual quality**: in 4 forest/mid candidates at
  1024px, A-grade outputs included one washed-out failure and one
  off-prompt result; B-grade output (failed `periodic_artifact`) was
  visually usable. Treat grade as triage hint, eye is the gate.

Per-material perf at 1024×2: ~47s on RTX 5090 Laptop. Extrapolation
to 1024×4 (production): ~80-90s. Full biome (81 materials): ~110 min
wall time. Updates `~6-10 hr per biome` estimate above with the
attended-attention portions (review + promote + verify).

## Subagent review schedule

Per [subagent_review_prompt.md](../workflows/subagent_review_prompt.md):

- **After 5.1 (module port)**: single subagent
  - SCOPE = `pipeline/textures/tx_*.py`, against spec 25 + spec 12 + W4 reference modules
  - LENSES = port fidelity (did each carryover preserve W4's working behavior?) + content-addressing wires + spec 01 module-layout compliance
  - ID_PREFIX = `TX-PORT`

- **After 5.4 (first biome refresh)**: 2 parallel subagents
  - Agent 1: workflow review — did the documented steps 1-8 actually
    work as described? Where did reality diverge? ID_PREFIX `TX-WF`
  - Agent 2: spec-vs-output review — does the alpine biome's shipped
    materials match the spec 23 / spec 24 contract? ID_PREFIX `TX-SPEC`

- **After 5.5 (shader work)**: single subagent
  - SCOPE = `engine/scripts/terrain/material/` + variety shader
  - LENSES = visual quality (close + mid + far reads as varied) +
    perf budget (variety pass ≤ 1.0 ms at high tier)
  - ID_PREFIX = `TX-VARIETY`

## Doc cap status

This file: ~365 lines (~15 over 350 plan-doc cap; the overage carries
2026-05-17 staging-test evidence + the locked sibling-manifest schema.
Trim opportunity if it grows further: W4-reference reading-order
could move to a sub-doc).
