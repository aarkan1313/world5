# Spec: TRELLIS 3D Asset Pipeline

> Status: draft
> Tier: 1 (core)
> Depends on: 01_MODULE_LAYOUT, 12_CONTENT_ADDRESSING
> Consumed by: LOD bake (spec 27), decoration (spec 28), foliage trunks
> (spec 29), impostors source images (spec 40)

## Purpose

Image → 3D textured mesh pipeline. W5 uses Microsoft's TRELLIS-2-4B
model wrapped as a W5 batch driver. Image inputs come from:
- AI-generated stylized 2D (via texture pipeline's subject mode, or
  similar)
- Real photos (after stylization pass)
- Hand-authored 2D art

Output: textured GLB at ~1M tris + 4K textures (TRELLIS native
output), then consumed by LOD bake pipeline (spec 27) to produce the
4-tier game-ready LOD chain.

W4.1 validated TRELLIS on 343 subjects; 186 baked through to shippable
quality. ~3 min/subject on a 5090. Handles thick / organic geometry
well; fails on thin / wiry / branching topology (foliage, ropes,
chains, thin tools).

## Non-goals

- Realtime mesh generation (offline only)
- Multi-view input (TRELLIS handles single-view; deferred if higher-
  quality demands multiview)
- Tree foliage / leaf clusters (foliage spec 29 handles those via
  procedural branches + leaf cards; TRELLIS only contributes the
  trunk geometry)
- Mesh editing UI (Blender + manual hand-edit for one-offs;
  not in the pipeline)
- Realtime tree-growth animation (out of scope per inventory)

## Pipeline stages

```
input image (RGBA preferred; alpha = subject mask)
  ↓
[1] preprocess          rembg / SAM background removal if RGB only
                        center + scale to standard frame
  ↓
[2] TRELLIS inference   ~3 min on 5090; ~6 min on 4080; ~12 min on 3060
                        output: textured GLB at ~1M tris + 4K texture
  ↓
[3] post-process        verify mesh integrity; flag degenerate output
                        (open mesh, fragmented topology, blank texture)
  ↓
[4] manifest emit       provenance (input image hash, model version,
                        seed, processing time) + content-address key
  ↓
output: <category>/<name>/mesh.glb + manifest.json
```

After this, LOD bake pipeline (spec 27) takes the high-detail mesh
and produces the 4-tier LOD chain.

## Subject organization

Outputs at `subjects_3d/<category>/<name>/`:

```
subjects_3d/
├── rocks/
│   ├── boulder_01/
│   │   ├── mesh.glb           # TRELLIS raw output
│   │   ├── manifest.json
│   │   └── source.png         # the input image used (for regen)
│   └── ...
├── structures/
├── bones/
├── props/
├── plants/                    # only short-foliage / non-branching (mushrooms, succulents)
├── foliage_trunks/            # foliage spec 29 consumes; tree trunks only
└── ...
```

Branching trees + complex foliage are NOT in subjects_3d/. The
foliage system (spec 29) builds them procedurally with TRELLIS
trunks as ONE input.

## Batch driver

`pipeline/trellis/batch_run.py` — runs TRELLIS on a list of input
images, retries failures, writes a batch report. Per W4 pattern:
~3 min/subject, parallel batch via ProcessPoolExecutor (1 worker
at a time since TRELLIS is GPU-bound; queueing).

Failures retry once with adjusted preprocess params (rembg vs SAM,
different scale). After two failures, subject is flagged for manual
review (not auto-retried).

## Asset carry-over from W4.1

Per inventory decision: **review per subject**, copy what's good,
regenerate the rest. Concrete process:

1. List W4.1's 186 OK chains from
   `world 4/the world 4/decoration_meshes/_lod_manifest.json`
2. Visual review session (contact sheet + per-subject snapshot)
3. Mark each: COPY (good, use as-is) / REGEN (poor quality, redo) /
   DROP (not needed for W5's 2-biome scope)
4. Batch-copy the COPY set into `subjects_3d/`
5. Schedule the REGEN set for W5 TRELLIS sprint
6. DROP set ignored

Estimated split: ~120 COPY, ~40 REGEN, ~26 DROP (gut estimate; real
review will adjust). Carry-over saves ~80 hours of generation time.

## Photo → 3D loop

W4.1 validated the loop: real photo → stylization pass (img2img with
denoise 0.78 via texture pipeline's subject mode) → TRELLIS → LOD
bake. The stylization step makes photoreal source look consistent
with the rest of the asset library (which is FLUX-generated).

W5 keeps this as a documented workflow, not a separate spec.

## Public API

### CLI

```bash
# Single subject
python -m world5.trellis.run --input subjects/rocks/boulder_01_source.png \
    --output subjects_3d/rocks/boulder_01/

# Batch
python -m world5.trellis.batch_run --manifest pipeline/trellis/batch_alpine.yaml

# Photo → 3D
python -m world5.trellis.photo_to_3d --photo photo.jpg --style alpine_rock \
    --output subjects_3d/rocks/photo_boulder_01/
```

### Output manifest

```json
{
  "w5_version": "0.1.0",
  "schema_version": 1,
  "subject_id": "rocks/boulder_01",
  "category": "rocks",
  "source_image_hash": "sha256...",
  "trellis_model_version": "2-4B",
  "seed": 42,
  "processing_time_s": 187,
  "mesh_stats": {
    "tri_count": 1024000,
    "vertex_count": 512000,
    "texture_resolution": 4096,
    "has_alpha_textures": false
  },
  "content_address_key": "sha256..."
}
```

## Producer / consumer contract

- **Produces**: textured GLB + manifest per subject
- **Consumes**: input image (PNG or JPG); model checkpoint files
  (cached locally)

## Dependencies

- `01_MODULE_LAYOUT` (placement at `pipeline/trellis/`)
- `12_CONTENT_ADDRESSING` (cache key + cross-session reuse)
- **GPU mutex**: spec 25 `pipeline/core/gpu_mutex.py` (audit S12).
  TRELLIS runs MUST wrap their GPU section in
  `acquire_gpu("trellis")` to coordinate with ComfyUI/FLUX. Hard
  contract; not opt-in.
- External: TRELLIS-2-4B checkpoint; nvdiffrast (build from source for
  RTX 50-series; W4 memory entry `nvdiffrast_blackwell_build`);
  rembg / SAM for preprocessing

## Quality bar

- Single subject inference: ≤ 6 min on RTX 4080; ≤ 12 min on 3060
- Success rate (subject yields shippable mesh): ≥ 80% on hard-surface
  inputs (W4 measured ~75-95% depending on category; failures cluster
  on thin/wiry — explicitly out of scope)
- Mesh integrity: watertight, no inverted normals, texture mapped
  correctly (validated by post-process step + downstream LOD bake)
- Content addressing: same input + same model + same seed → cache hit
- Carry-over review session produces a per-subject decision in
  ≤ 1 min/subject (target ~3 hours for 186 subjects)

## Discoverability

- **Entry point**: `python -m world5.trellis.run`
- **Schema**: manifest JSON shape above; batch YAML schema at
  `engine/resources/schemas/trellis_batch.schema.json`
- **Validator / preflight**: post-process step validates mesh
  integrity; LOD bake (spec 27) is the downstream gate
- **Example**: `pipeline/trellis/examples/` minimal subject
- **Deterministic outputs**: yes given fixed model + seed (TRELLIS
  has some inference noise; same seed yields same output bit-for-bit
  on same hardware)

## Open questions

- **GPU mutex with ComfyUI**: RESOLVED (audit S12). Spec 25
  `pipeline/core/gpu_mutex.py` provides the file-lock contract; both
  pipelines wrap their GPU sections in `acquire_gpu(owner)`. Hard
  contract; serializes overnight batches automatically.
- **Multi-view input**: if quality plateaus, multi-view TRELLIS
  variants (3-4 images per subject) might lift the ceiling. Real cost
  to author multiple input views per subject. Defer until measured.
- **Subject library scope for v1**: how many subjects ship in v1?
  Probably enough for the 2-biome demo (~50-80 subjects across
  rocks/structures/props/bones). Decoration spec 28 drives the exact
  number.
- **Photo source curation**: where do real photos come from? W4 used
  Unsplash batch pipeline. Carry over, or curate per-biome?

## References

- W4 memory entries: `trellis_validation_2026_05_13`,
  `trellis_scale_2026_05_13`, `trellis_optimize_2026_05_13`,
  `photo_pipeline_2026_05_13`, `nvdiffrast_blackwell_build`,
  `w4_3d_library_status_2026_05_14`
- TRELLIS paper + Microsoft repo
- W4.1 `pipeline/trellis/` (if it exists) for code carry-over

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-audit (S12). Added hard dependency on
  `pipeline/core/gpu_mutex.py` for ComfyUI coordination (was a W4
  memory entry; now spec contract).
