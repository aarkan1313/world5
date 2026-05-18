# Spec: Asset Content Addressing

> Status: shipped (2026-05-18; promoted per spec-to-impl audit — ContentAddress.gd + Python ContentAddressStore shipped + parity tested)
> Tier: cross-cutting (Tier 0)
> Depends on: 01_MODULE_LAYOUT
> Consumed by: texture pipeline, decoration bake, terrain page cache, LOD bake, audio hooks (consumer-side), any pipeline that produces baked artifacts

## Purpose

Content-addressed asset store with sha-keyed artifacts and a dependency
graph between generators. Partial-rebake when an upstream input changes:
only artifacts affected by the change get re-baked.

W4.1 missing-layer #6. Every pipeline shipped with its own version-stamp
system (decoration blob headers had `seed, generator_revision,
kernel_hash, material_hash, w4_version, quality_tier`; texture pipeline
had per-prompt SHA manifests; terrain page cache had cache keys + stamps).
But there was no **shared** store: each pipeline re-baked its full
output when an input changed, even if 90% of artifacts were unaffected.

W5 builds the shared store so:
- Every artifact (texture, mesh, LOD chain, decoration blob, baked
  image, audio tag manifest, anything generated) has a content hash
- The dependency graph captures "this artifact depends on these inputs"
- A change to an input triggers a precisely-scoped rebake of only
  downstream artifacts
- Cache hits across sessions are possible (re-running the texture
  pipeline with identical inputs reuses prior outputs)

## Non-goals

- Distributed asset CDN (single-machine only)
- User-facing version control (git handles source; this handles bakes)
- Content-defined chunking (whole artifacts, not chunks within them)
- Reproducible builds across machines (we use git SHA + Python version,
  which may drift across OSes; this is bake reproducibility within
  one machine, not byte-identical across machines)

## Public API

### Python: `pipeline/core/content_address.py`

```python
class ContentAddressStore:
    def __init__(self, store_root: Path):
        """Store lives at `store_root` (typically
        `pipeline/.content_addressed_store/`); not checked into git."""

    # Hashing
    def hash_inputs(self, inputs: dict[str, Any]) -> str:
        """Compute a stable sha256 from input dict. Used as the cache key
        for this artifact.

        File-typed inputs (model checkpoints, prompt YAMLs, source DEMs,
        TRELLIS input PNGs) must be passed as FileInput sentinels:
            inputs = {
              "prompt": "fresh wind-packed snow",
              "model": FileInput(Path("models/flux2-klein.safetensors")),
            }
        The FileInput wrapper triggers content-hashing of the file (via
        hash_file_input below) instead of stringifying the path."""

    def hash_file_input(self, path: Path) -> str:
        """Content-hash a file. Cached by (path, mtime, size) to keep
        the call O(1) on cache hit. Cache invalidates on mtime change.

        Used when a file is an input to another bake (e.g. the FLUX
        model checkpoint, a prompt YAML, a source DEM). Bare file paths
        as strings are NOT sufficient — two files with the same path
        but different content would silently cache-collide."""

    # FileInput sentinel
    class FileInput:
        def __init__(self, path: Path): ...
        # hash_inputs detects FileInput instances and calls
        # hash_file_input on them automatically

    # Cache lookup
    def has(self, key: str) -> bool
    def get(self, key: str) -> Path | None      # path to the cached artifact
    def get_metadata(self, key: str) -> dict     # provenance info
    def put(self, key: str, artifact: Path | bytes, metadata: dict) -> None

    # Dependency graph
    def declare_dependency(self, key: str, depends_on: list[str]) -> None
    def find_dependents(self, input_key: str) -> list[str]:
        """Returns all artifacts that transitively depend on this input."""

    # Invalidation
    def invalidate(self, key: str) -> list[str]:
        """Remove this artifact + all transitive dependents from cache.
        Returns the list of evicted keys (for telemetry)."""

    # GC
    def evict_unreferenced(self) -> int:
        """LRU eviction of artifacts not referenced in recent N days.
        Returns count evicted."""
    def gc_size_mb(self) -> int
    def gc_if_over_cap(self, cap_gb: float = 20.0) -> int:
        """Triggers eviction if store exceeds cap. Called automatically
        on every `put()`. SA-S2.4 cap default 20 GB so we don't fill
        the D: drive (per user memory `d_drive_space_constraint`)."""

    # Diagnostics
    def list_artifacts() -> list[dict]
    def graph_dot(self) -> str   # Graphviz output of the dep graph
```

### GDScript: minimal read-side wrapper

Runtime doesn't typically need write access — it just needs to look
up "is this artifact's cache key the same as my expected stamp?"

```gdscript
class_name ContentAddress extends RefCounted

# Static methods
static func compute_stamp(inputs: Dictionary) -> String
static func read_stamp(artifact_path: String) -> String:
    """Read the stamp embedded in the artifact header (e.g. decoration
    blob)."""
static func is_stale(artifact_path: String, expected_stamp: String) -> bool
```

## Storage layout

```
pipeline/.content_addressed_store/
├── objects/
│   ├── ab/                           # first 2 hex chars (git-style)
│   │   └── abcdef0123...             # the artifact (sha256-named file)
│   └── ...
├── metadata/
│   └── <sha>.json                    # provenance: inputs, deps, generator version
├── deps.json                         # dependency graph (lightweight)
└── access_log.json                   # for LRU eviction
```

The store is git-ignored. It's a build-artifact cache, not source.

## Dependency declaration pattern

When a pipeline bakes an artifact:
```python
inputs = {
    "biome": "alpine",
    "slot": "ground",
    "prompt": "fresh wind-packed snow",
    "model_version": "klein-9B-FP8",
    "pipeline_version": "0.1.0",
}
key = store.hash_inputs(inputs)
if store.has(key):
    return store.get(key)  # cache hit; return existing artifact

artifact = run_expensive_bake(inputs)
store.put(key, artifact, metadata={"inputs": inputs, "duration_s": 42.0})

# Declare what this artifact depends on (for invalidation chain)
store.declare_dependency(key, depends_on=[
    f"input:model:{model_version_hash}",
    f"input:prompt:{prompt_hash}",
    f"input:pipeline:{pipeline_version}",
])

return store.get(key)
```

When an input changes (e.g. a new pipeline version ships):
```python
old_pipeline_input_key = f"input:pipeline:{old_version}"
evicted = store.invalidate(old_pipeline_input_key)
# Now all artifacts that depended on old_pipeline_version are gone
# Next bake will regenerate them with the new version
```

## Integration with existing pipelines

- **Texture pipeline**: replaces per-prompt SHA manifest with content
  addressing. Cache hits across sessions become free.
- **Decoration bake**: blob headers' `decoration_revision` field
  becomes a content-address input
- **LOD bake**: LOD chains keyed by source mesh + pipeline version
- **Terrain page cache**: page cache keys feed into content addressing;
  pages with the same `(seed, generator_revision, kernel_hash)` are
  shared across runs

## Producer / consumer contract

- **Produces**: content-addressed paths to artifacts; provenance metadata;
  invalidation events
- **Consumes**: input dictionaries (hashable); artifact bytes/files on
  put

## Dependencies

- `01_MODULE_LAYOUT` (placement)

## Quality bar

- `hash_inputs()` is deterministic across runs (stable sort of keys,
  stable repr of values)
- `has()` + `get()` are < 1ms (filesystem stat + open)
- `invalidate()` is O(transitive dependents); typical: < 100ms for
  N=1000 dependents
- Store integrity check (`python -m world5.content_address verify`)
  detects corruption (any artifact whose sha doesn't match its name
  is flagged)
- 100% pytest coverage
- Across-session cache hit rate: > 80% for unchanged-inputs reruns
  (measured on test pipelines)

## Discoverability

- **Entry point**: `ContentAddressStore` class (Python); `ContentAddress`
  static class (GDScript)
- **Schema**: input dictionaries are arbitrary but must be JSON-serializable;
  the `metadata` dict shape is per-pipeline (no global schema)
- **Validator / preflight**: `python -m world5.content_address verify`
  CLI checks integrity; gut/pytest cover semantics
- **Example**: `pipeline/core/examples/content_address_example.py` shows
  a fake pipeline using the store; runtime example in
  `engine/examples/content_address_runtime_read.gd`
- **Deterministic outputs**: yes — same inputs always produce same
  cache key; same cache key always returns same artifact

## Open questions

- **Storage backend**: filesystem (simplest, ships first) vs SQLite
  (transactional, harder to inspect). Spec choice: filesystem; revisit
  if dep graph queries get slow.
- **Cross-machine reproducibility**: can different machines produce
  bit-identical artifacts for the same inputs? Hard (model nondeterminism
  in FLUX/TRELLIS). Spec choice: within-machine reproducibility only;
  cross-machine treated as "different inputs" pragmatically.
- **Eviction policy**: pure LRU (simple) vs LFU (better for hot artifacts).
  Start with LRU; revisit if measured.
- **Whole-tree GC**: should we have a "delete everything older than N
  days even if referenced" emergency lever? Probably yes; defer.

## References

- W4.1 audit cross-cutting concern #2.F ("Asset content addressing") —
  this spec is the direct response
- W4.1 decoration blob headers carry `(seed, generator_revision,
  kernel_hash, material_hash, w4_version, quality_tier)` stamps —
  proves the pattern works per-system; this spec generalizes it
- Memory entry on cross-pipeline staleness ("stale" flags in W4.1 LOD
  manifest happened because dispatch table changed)

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-self-audit (SA-C2.3). Added `FileInput` sentinel
  + `hash_file_input` helper. File-typed inputs (model checkpoints,
  prompt YAMLs, source DEMs, TRELLIS PNGs) now content-hash via
  this path so two files with the same path but different content
  don't cache-collide. Also added GC size cap + invalidation policy
  (SA-S2.4).
