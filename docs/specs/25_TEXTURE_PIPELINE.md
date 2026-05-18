# Spec: Texture Pipeline

> Status: shipped (2026-05-18; 17 tx_*.py modules + drivers integrated
> at pipeline/world5/textures/ — promote.py + tx_hn_lut + tx_macro_terrain
> + tx_pipeline + 13 supporting tools. Walking demo's 48-layer sibling
> pool was produced through this pipeline. tx_hn_lut added 2026-05-18
> for Heitz-Neyret inverse-CDF LUTs.)
> Tier: 1 (core)
> Depends on: 01_MODULE_LAYOUT, 12_CONTENT_ADDRESSING, 14_WORLD_CONTRACT
> Consumed by: materials (spec 23), ground variety (spec 24),
> impostors (spec 40, alpha cutouts)

## Purpose

The Python pipeline that turns text prompts + style hints into PBR
texture sets ready for the materials system. Carry-over from W4.1
(`pipeline/textures/tx_*` modules) with refactor for module layout
(spec 01) and content addressing (spec 12).

W4.1's pipeline is validated: 4-pass FLUX + variant rank + delight +
hybrid PBR (StableMaterials tileable albedo + derive_pbr_v2 for PBR
maps) + seam_repair + QA. Midline ratio < 2.72 vs broken pipeline's
16-22 (shipped 1.30). Diversity batch driver. Macro albedo companion
pipeline.

V1 adds: **detail-overlay generation** (wet / grunge / moss / etc.)
as a sibling output mode, for use by ground variety system or
arbitrary consumers.

## Non-goals

- Realtime texture generation (offline pipeline only)
- Ground-truth photo matching (we generate stylized, not photoreal-fit)
- Texture authoring UI (config + CLI driven)
- Per-instance texture variation (decoration / mesh per-instance is
  shader concern, not pipeline)
- SAM segmentation in v1 (deferred — adds when compositor sprint runs)

## Pipeline stages (carry-over from W4)

```
prompt
  ↓
[1] tx_seamless         4-pass FLUX (text2img → offset → heal → reverse)
[1] tx_variant_select   Generate N variants, rank by composite, keep all
  ↓
[2] delight             LAB-blur subtract @ strength 0.4
  ↓
[3] tx_pbr_hybrid       StableMaterials tileable pass (albedo only) + derive_pbr_v2 for PBR maps
  ↓
[4] tx_seam_repair      Conditional PatchMatch (rarely triggers)
  ↓
[5] tx_qa               4 gating checks + advisory metrics
  ↓
manifest.json + canonical maps (albedo, normal, roughness, AO, height) + variants/
```

## Output modes (audit S9: enumerated up front)

The pipeline ships **four output modes** in v1, each consumed by a
different downstream spec:

| Mode | Flag | Outputs | Consumed by |
|---|---|---|---|
| **Tileable PBR** (default) | (none) | albedo/normal/roughness/AO/height per slot | Materials (spec 23) |
| **Detail overlays** | `--detail-overlays` | semi-transparent PBR overlays (wet/moss/grunge/snow/cracks) | Ground variety (spec 24) |
| **Single-subject alpha cutout** (`tx_subject`) | `--mode subject` | RGBA PNG with extracted alpha | Foliage leaf cards (spec 29), Impostors (spec 40), Decoration cutouts |
| **Macro albedo** | `python -m world5.textures.macro_terrain` (separate CLI) | 256m-scale macro_albedo companion | Terrain shader far-tier |

`tx_subject` (single-subject alpha cutout) was previously deferred to
a separate undocumented pipeline; audit S9 surfaced that specs 29
(foliage leaf cards) and 40 (impostors) both need it. **It's
documented as a mode of this pipeline in v1.** Implementation reuses
the FLUX → threshold-to-alpha path with subject-focused prompts.

## Output shape

Each generated material produces:

```
candidates/<biome>/<slot>/<NN>_<tag>/
├── manifest.json              # provenance + QA scores
├── albedo.png                 # canonical PBR maps
├── normal.png
├── roughness.png
├── ao.png
├── height.png                 # optional
├── macro_albedo.png           # optional, separate tool
└── variants/                  # all N variants kept; siblings system uses these
    ├── v0_albedo.png
    ├── v1_albedo.png
    └── ...
```

Sibling variants stored as files in `variants/`. The ground variety
system (spec 24) consumes them based on its chosen architecture.

## Detail overlays (v1 addition)

A new output mode: `--detail-overlays`. Generates tileable PBR sets
with semi-transparent alpha + designed to overlay on a base texture.
Examples: wet patch, mossy grunge, snow dusting, dry cracks, debris
scatter.

Detail overlays use the same FLUX → delight → hybrid PBR stack but
with prompts tuned for "subject is the texture, background is gray
40% so threshold-to-alpha works." Alpha mask extraction is simple
threshold + erode/dilate; NOT full SAM segmentation (SAM deferred).

Per-biome detail sets are authored in `pipeline/biomes/<biome>.yaml`
alongside base slot prompts.

**Why detail overlays ship in v1 regardless of spec 24's pending
ground-variety architecture choice** (SA-C3.9): they're a
general-purpose asset class consumed by multiple systems:
- Spec 36 weather: wetness overlay during rain; snow accumulation
- Spec 28 decoration: splat decals around point sources (waterfall
  splash zone, fire scorch)
- Spec 38 deformation: scorch / disturbed-earth overlays per profile
- Spec 41 roads: dirt/cobblestone surface overlays
- Spec 24 ground variety: IF spec 24 picks Option B (detail texture
  array) or Option E (multi-frequency triplanar) as variety
  architecture, detail overlays are the direct input

If spec 24 picks Option A (virtual texturing) or Option C (siblings +
stochastic UV), the detail overlays still serve the other consumers
above. They aren't wasted bake work.

## Macro albedo

Separate tool (carry-over): `tx_macro_terrain.py`. Derives or
purpose-builds a 256m-scale macro_albedo companion from promoted
ground textures. Reversible (doesn't overwrite source detail tiles).

## Model stack (carry-over)

- **Diffusion**: FLUX2-klein 9B FP8 (W4 carry-over; validated)
- **Text encoder**: Qwen3-8B (Comfy-Org FP8mixed pack)
- **Tileable albedo**: StableMaterials (tileable=True diffusion)
- **PBR derivation**: derive_pbr_v2 (normal/roughness/AO from clean
  albedo)
- **VAE / encoders**: per W4 memory entry `flux_fill_redux_model_stack`

Model stack is config-locked in v1. Future model updates require
explicit re-validation (compare midline ratio + QA against current
baseline).

## Diversity batch driver

`pipeline/diversity_run.py` (carry-over). Reads per-biome YAML
listing slot prompts × candidate count, generates all candidates,
ranks by QA composite, writes contact sheet for review.

## Per-biome YAML layout (Phase 5 amendment 2026-05-17)

Each biome ships **two** YAMLs, both at `pipeline/biomes/`:

| File | Purpose | Candidate count |
|---|---|---|
| `<biome>.yaml` | Discovery pool — diverse prompts across all slots | 40-60 (W4 alpine = 51) |
| `<biome>_siblings.yaml` | Sibling pool — N prompts describing the same anchor concept with phrasing variation | 30 (W4 convention) |

YAML shape (W4-locked, validated 2026-05-17 staging test):
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

Two YAMLs because: discovery pool gives 5-10× more candidates than
ship, so promotion has real options. Sibling pool produces the
palette-locked family that Layer 1 of spec 24 stochastic-UV needs.
Writing 80-90 prompts per biome IS the creative bottleneck; Pillar 4
allows the time investment.

## Operator model: dev-only (Phase 5 amendment 2026-05-17)

The texture pipeline is **author-side / dev-only**:
- Runs on dev hardware (RTX 5090 Laptop)
- Produces PBR sets baked into world bundles
- Consumer games receive baked artifacts in `worlds/<world>/materials/`,
  NOT pipeline access
- `pipeline/textures/` is NOT part of the shipped Godot addon (`engine/`)

This means the 90s-per-material Quality bar target below (originally
framed against RTX 3060/4060) should be read as "author-hardware
perf" instead. Phase 5.6 calibration replaces the 3060 number with
measured author-hardware reality. The pipeline is offline + occasional;
its perf doesn't appear in the consumer's runtime budget.

## Macro mode default: purpose (Phase 5 amendment 2026-05-17)

`tx_macro_terrain.py` ships two modes:
- **Derived**: blur + downsample the promoted ground tile (fallback)
- **Purpose**: generate new low-frequency biome image from a palette +
  noise (W4 evidence: reads better at far distance)

**Default for v1: purpose mode.** Per-biome palette configs extracted
from W4's `PURPOSE_PRESETS` dict to per-biome YAML alongside
`<biome>.yaml`. Derived mode stays as the no-palette fallback.

## GPU mutex with TRELLIS pipeline (audit S12)

TRELLIS (spec 26) and ComfyUI cannot share GPU (per W4 memory entry
`trellis_comfy_mutex`). This is a **spec-level contract**, not a
plan-doc detail. Both pipelines must coordinate via a single
file-based lock at `pipeline/_gpu_lock/`:

```python
# pipeline/core/gpu_mutex.py
from contextlib import contextmanager
from filelock import FileLock

GPU_LOCK_PATH = Path("pipeline/_gpu_lock/gpu.lock")

@contextmanager
def acquire_gpu(owner: str, timeout_s: float = 600.0):
    """Block until GPU is free; release on context exit.
    `owner` written into the lock file for diagnostics."""
    with FileLock(str(GPU_LOCK_PATH), timeout=timeout_s):
        try:
            GPU_LOCK_PATH.with_suffix(".owner").write_text(owner)
            yield
        finally:
            GPU_LOCK_PATH.with_suffix(".owner").unlink(missing_ok=True)
```

Both `pipeline/textures/` and `pipeline/trellis/` wrap their GPU
sections in `acquire_gpu("textures")` / `acquire_gpu("trellis")`.
Overnight orchestrators (e.g. a bake driver running texture + TRELLIS
for the same biome) automatically serialize. Manual command-line use
also blocks if the other is running.

This module is part of `pipeline/core/` (not texture-pipeline-specific
even though we document it here because texture pipeline is the
primary consumer).

## Public API

### CLI

```bash
# Single material (one prompt → one PBR set)
python -m world5.textures.pipeline \
    --prompt "tileable seamless texture, fresh wind-packed snow, overhead perspective" \
    --id alpine_ground_fresh_powder \
    --out-dir candidates/alpine/ground/ \
    --variants 4

# Full biome × slot batch (per pipeline/biomes/alpine.yaml)
python -m world5.diversity --biome alpine

# Detail overlays for a biome
python -m world5.textures.pipeline \
    --biome alpine --detail-overlays

# Macro albedo derivation
python -m world5.textures.macro_terrain
```

### Output

Manifest JSON for every output:
```json
{
  "w5_version": "0.1.0",
  "schema_version": 1,
  "prompt": "...",
  "model_stack": { "diffusion": "klein-9B-FP8", ... },
  "stages": { "seamless": {...}, "delight": {...}, "pbr": {...}, "qa": {...} },
  "content_address_key": "sha256...",
  "qa_grade": "A",
  "metrics": { "midline_ratio": 1.30, "mip32_stdev": 0.024, ... }
}
```

Content-addressed via spec 12: same prompt + same model stack + same
pipeline version → cache hit, no re-bake. **Model files passed as
spec 12 `FileInput` sentinels** (content-hashed, not path-stringified)
so a swapped checkpoint with the same filename doesn't silently
cache-collide. Per SA-C2.3.

## Producer / consumer contract

- **Produces**: PBR sets at canonical paths; manifest with provenance;
  optional detail overlays + macro albedo
- **Consumes**: prompts + per-biome configuration (YAML);
  model stack files (cached locally)

## Dependencies

- `01_MODULE_LAYOUT` (placement at `pipeline/textures/`)
- `12_CONTENT_ADDRESSING` (cache key generation; cross-session reuse)
- `14_WORLD_CONTRACT` (output sizes validated per tier)
- W4 carry-over: `tx_seamless`, `tx_pbr_hybrid`, `tx_qa`, `delight`,
  `derive_pbr_v2`, `tx_macro_terrain`, `diversity_run`
- External: ComfyUI runtime + FLUX2-klein 9B model files + Qwen3-8B
  text encoder + StableMaterials checkpoint

## Quality bar

- Single material generation: ≤ 90s on RTX 3060/4060 (W4 measured
  ~70s; allow margin)
- Diversity batch (1 biome, 3 slots, 4 variants each): ≤ 25 min
- QA gates: midline_ratio < 3.0 (W4 baseline 1.30; allow drift),
  mip32_stdev > 0.02 (terrain readability), no near-black pixels at
  p5 < 0.05 luma (PITFALL #1 prevention)
- Detail overlay generation: similar latency, alpha mask correctness
  > 95% (manual review on first 10 outputs per biome)
- Content addressing hit rate: > 80% on rerun with unchanged inputs
- pytest coverage of every pipeline module (carry-over coverage from
  W4)

## Discoverability

- **Entry point**: `python -m world5.textures.pipeline` CLI
- **Schema**: per-biome YAML at `pipeline/biomes/<biome>.yaml`; output
  manifest schema in this spec
- **Validator / preflight**: QA stage IS the validator; failing
  materials are flagged + don't ship to materials/ tree
- **Example**: `pipeline/biomes/_example.yaml` is a minimal valid
  biome config; `engine/examples/example_world/materials/` shows the
  consumed-end shape
- **Deterministic outputs**: yes given fixed model files + seed;
  content-addressed via spec 12

## Open questions

- **SAM segmentation timing**: when compositor sprint runs (Phase 6+),
  this pipeline gains a `--segment-layers` mode that uses SAM2 or
  RemBG to extract layer alpha masks from a generated scene. Until
  then, only the threshold-based detail-overlay path ships.
- **Per-tier output sizing**: high=2048², ultra=4096², low=1024².
  Pipeline outputs at native 2048² + downsamples; world contract
  validates per-tier sizes.
- **Model swap discipline**: if FLUX2-klein gets superseded, who
  signs off on the swap? Spec'd as "re-validate against W4 baseline
  QA scores before adopting."
- **Style range beyond tileable PBR**: RESOLVED (audit S9):
  `tx_subject` is now an output mode of this pipeline (see Output
  modes above), consumed by foliage leaf cards + impostors +
  decoration cutouts.

## References

- W4.1 `features/textures.md` — canonical doc; carry concepts over
- W4.1 `pipeline/textures/tx_*` modules — code carry-over with refactor
- W4.1 `plans/TEXTURE_PIPELINE_FINDINGS_2026_05_12.md` — diagnostic
  record proving the pipeline shape is correct
- W4 memory entries on model stack: `flux2_klein_9b_setup`,
  `flux_fill_redux_model_stack`

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-audit (S9, S12). Enumerated four output modes
  upfront (tileable PBR / detail overlays / `tx_subject` /
  macro_albedo). Added GPU mutex contract with TRELLIS via
  `pipeline/core/gpu_mutex.py` (was a W4 memory entry; now spec
  contract).
- 2026-05-17 (Phase 5 plan amendments): added two-YAML per-biome
  layout (discovery + sibling pools); committed purpose-mode macro
  as default; documented dev-only operator model so Quality-bar
  perf framing is against author hardware, not consumer 3060.
