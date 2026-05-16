# Spec: LOD Bake Pipeline

> Status: draft
> Tier: 1 (core)
> Depends on: 26_TRELLIS_3D_PIPELINE, 12_CONTENT_ADDRESSING
> Consumed by: decoration (spec 28), foliage trunks (spec 29);
> impostor system (spec 40) handles distant tier separately

## Purpose

Takes TRELLIS's high-detail meshes (~1M tris, 4K textures) and
produces game-ready 3-tier LOD chains: LOD0 hero, LOD1 mid, LOD2 far.
Distant-tier rendering lives in the **impostor system (spec 40)** —
not part of LOD bake. Clean separation: LOD bake = geometry chains;
impostors = billboards.

W4.1 baked 186/343 subjects successfully via this pipeline. Pattern
is solid; failures cluster on thin/wiry geometry + saturated colors
(known limitations, not bugs).

## Non-goals

- Distant-tier billboards / impostors (spec 40)
- Realtime LOD generation
- Mesh decimation for non-decoration assets (terrain has its own LOD
  via renderer; this spec is decoration meshes only)
- Manual mesh editing (we automate; one-offs go through Blender by
  hand and skip this pipeline)

## LOD tier targets

| Tier | Distance band | Tris | Texture | Method |
|---|---|---|---|---|
| LOD0 | 0-30m (close) | ~8000 | 2K | Voxel-remesh → smart UV → Cycles bake |
| LOD1 | 30-80m (mid) | ~2000 | 1K | gltfpack decimate from LOD0 |
| LOD2 | 80-200m (far) | ~500 | 512 | gltfpack decimate + texture downscale |
| (distant >200m) | — | — | — | **Impostor system, spec 40** |

Distance bands per quality_tier (see spec 13). The numbers above are
high-tier; low-tier shrinks distances, ultra-tier extends.

## Pipeline stages (W4 carry-over)

```
TRELLIS output (~1M tris, 4K texture)
  ↓
[1] Voxel remesh → ~8000 tris, clean topology
[1] Smart UV @ 89° angle threshold → low-distortion UV unwrap
[1] Cycles bake @ 32 samples → albedo/normal/roughness/AO at 2K
[1] Brightness compensation: clamp baseColorFactor to [0.5, 2.5]
    relative to source albedo mean (prevents drift)
[1] WebP compression for textures
  ↓ → mesh_lod_0.glb (2K WebP textures, ~8K tris)
[2] gltfpack decimate LOD0 → LOD1: target 25% tris, 1K textures
  ↓ → mesh_lod_1.glb
[3] gltfpack decimate LOD0 → LOD2: target 6% tris, 512px textures
    (gltfpack -ts flag is no-op on already-WebP textures; use PIL
    resize + re-encode — W4 fix)
  ↓ → mesh_lod_2.glb
[4] Quality gates: tri count per tier, texture inventory, brightness
    drift, near-black pixel check (PITFALL #1 prevention)
[5] Manifest write: per-subject _lod_meta.json + global rollup
    _lod_manifest.json
```

## LOD2 gotcha (W4 lesson)

Original W4 attempt used voxel-remesh for LOD2 directly — produced
"exploded skull" artifacts at 14k-tri overshoot. **Fix**: build LOD2
via gltfpack-decimate-from-LOD0 + manual texture downscale with PIL,
NOT another voxel pass. This carries over to W5.

Brightness drift: subjects can darken or lighten between source and
baked output (mip + texture compression). W4 introduced the
`baseColorFactor` clamp `[0.5, 2.5]` to correct without destroying
saturation. Carry over.

## Output layout

```
subjects_3d/<category>/<name>/
├── mesh.glb              # TRELLIS source (spec 26 output)
├── mesh_lod_0.glb        # 2K WebP textures, ~8K tris
├── mesh_lod_1.glb        # 1K WebP textures, ~2K tris
├── mesh_lod_2.glb        # 512px WebP textures, ~500 tris
├── _lod_meta.json        # per-subject manifest (provenance + gates)
└── manifest.json         # from spec 26 (TRELLIS provenance)
```

Plus rollup `_lod_manifest.json` at `subjects_3d/` root listing
which subjects baked successfully + per-category stats.

## Sync to addon

Decoration runtime (spec 28) reads LOD chains from
`engine/decoration_meshes/<category>/<name>/mesh_lod_*.glb` — inside
the addon, not the `pipeline/` tree. A sync tool
(`pipeline/decoration/sync_lods_to_engine.py`) copies the LOD chain
files from `subjects_3d/` into `engine/decoration_meshes/` so the
runtime can `ResourceLoader.load_threaded_request` them via
spec 09.

Sync is **the only writer** into `engine/decoration_meshes/`. Direct
writes from elsewhere are forbidden (W4 lesson: pollution killed
Godot open times).

**Enforcement (SA-S3.13)**: every file under
`engine/decoration_meshes/` MUST be referenced by
`engine/decoration_meshes/_lod_manifest.json`. Orphan files (present
on disk but not in the manifest) are flagged by world contract
preflight as "polluting sync target". Sync tool writes the manifest;
direct copies don't update the manifest, so they get caught.

## Public API

### CLI

```bash
# Single subject
python -m world5.lod.build_chain --subject rocks/boulder_01

# Batch (all subjects in subjects_3d/ that don't have current LODs)
python -m world5.lod.batch_chain

# Sync to engine
python -m world5.lod.sync_to_engine
```

### Per-subject quality gates (`_lod_meta.json`)

```json
{
  "w5_version": "0.1.0",
  "schema_version": 1,
  "subject_id": "rocks/boulder_01",
  "lod_tiers": [
    { "tier": 0, "tri_count": 7997, "texture_size_kb": 2400, "passes_gates": true },
    { "tier": 1, "tri_count": 1998, "texture_size_kb": 600, "passes_gates": true },
    { "tier": 2, "tri_count": 498, "texture_size_kb": 150, "passes_gates": true }
  ],
  "brightness_compensation": { "source_mean": 0.42, "factor": 1.10, "in_range": true },
  "qa_grade": "A",
  "content_address_key": "sha256..."
}
```

## Asset carry-over from W4.1

Per spec 26 decision (review per subject): the 186 OK chains in W4's
`_lod_manifest.json` get reviewed; the COPY set's LOD chains are
brought over without rebuilding (cache hit via content addressing if
inputs match). REGEN subjects get fresh LOD chains via this pipeline.

## Producer / consumer contract

- **Produces**: 3-tier LOD chains per subject; _lod_meta.json
  manifest; addon-side sync
- **Consumes**: TRELLIS output GLBs from spec 26; quality-tier knobs
  for per-tier sizes

## Dependencies

- `26_TRELLIS_3D_PIPELINE` (source meshes)
- `12_CONTENT_ADDRESSING` (cache hits on unchanged subjects)
- `13_QUALITY_TIERS` (per-tier mesh + texture sizing)
- External: gltfpack (carry over W4 install), Blender 5.1+ (Cycles
  + Python API), PIL

## Quality bar

- Per-subject LOD chain build: ≤ 8 min on dev hardware (W4 measured
  ~7 min average; allow margin)
- Batch parallelism: 3 workers (W4 pattern; GPU + disk-bound)
- LOD chain success rate: ≥ 80% on hard-surface inputs (W4: 186/188
  in 210-batch = 89%)
- Brightness drift: |factor - 1.0| ≤ 1.5 on 95% of subjects (W4 hit
  this; clamp catches outliers)
- Mesh integrity gates pass for every shipped LOD tier
- pytest coverage of all post-process scripts

## Discoverability

- **Entry point**: `python -m world5.lod.build_chain`
- **Schema**: `_lod_meta.json` + `_lod_manifest.json` shapes above
- **Validator / preflight**: quality gates IS the validator; failing
  subjects don't sync to engine
- **Example**: `subjects_3d/_examples/` minimal subject
- **Deterministic outputs**: yes given fixed source mesh + pipeline
  version (Cycles has small noise; tolerable since textures use
  perceptual-diff gates)

## Open questions

- **Per-subject LOD distance overrides**: some subjects (non-branching
  plants like mushrooms) have different LOD curves than rocks. W4 had
  `decoration_lod_dispatch.json` for per-subject overrides. Carry over.
- **Tri-count overshoots**: occasional subjects bake to ~14k tris at
  LOD0 (target 8k). gltfpack-from-LOD0 fallback handles it; flagged
  in gates.
- **Per-tier texture format**: WebP is default. Some consumers may
  want KTX2/Basis for GPU-direct loading. Defer.
- **Sync conflict resolution**: if a subject's content address key
  changes (input mesh updated), sync should overwrite the engine
  copy. Schema slot for "force regen" flag in batch driver.

## References

- W4 memory entries: `w4_3d_library_status_2026_05_14`,
  `trellis_optimize_2026_05_13`,
  `verify_visual_output_yourself` (sync_lods_to_godot.py is the W4
  carry-over candidate)
- W4 `pipeline/decoration/build_lod_chain.py` +
  `batch_lod_chain.py` + `sync_lods_to_godot.py`
- W4 PITFALL #1 (near-black texel speckling — brightness compensation
  + luma floor are the fixes)

## Revision history

- 2026-05-16: initial draft
