"""KernelComposer — turns a biome catalog into (height, biome_weights)
at any (x, z).

Spec 19 §"KernelComposer" + spec 22 §"Catalog schema". Phase 5.7.b.

Two responsibilities:
1. **biome_weights(x, z, elev, slope)** — compute the per-biome
   selection probability via softmax over each biome's
   auto_biome_rules elevation+slope bands. Used by the renderer
   (Phase 6 multi-biome) to mix per-biome materials per fragment.
2. **sample_height(x, z, seed)** — produce the unified height field
   by dispatching each biome's kernel chain. Currently single-biome
   per-(x,z) dominance (the winning biome's chain output is the
   height); multi-biome smooth blending of height fields lands when
   chains contain something other than the shared NoiseStackKernel.

Kernel chain dispatch supports a single-stage shorthand
`{type: 'noise_stack', params: {...}}` and an explicit
`{type: 'chain', stages: [...]}` form per kernel_chain.schema.json.
First stage MUST be a base generator (noise_stack); subsequent
stages MAY be post-processes (erosion). Erosion in chains is a
5.7.c follow-up (needs content-addressed cache).

This is the Python reference. GDScript runtime mirror (5.7.b cont.)
reads cached output from disk; doesn't re-compute the chain at
runtime.
"""

from __future__ import annotations

import json
from dataclasses import dataclass

import numpy as np

from world5.kernels.erosion import ErosionKernel
from world5.kernels.noise_stack import NoiseStackKernel


# --- biome rule helpers ---


def _smoothstep(edge0: float, edge1: float, x: float) -> float:
    """GLSL smoothstep — clamped Hermite interpolation in [0, 1]."""
    if edge1 == edge0:
        return 1.0 if x >= edge0 else 0.0
    t = (x - edge0) / (edge1 - edge0)
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def _band_weight(elev: float, slope: float, rule: dict) -> float:
    """Spec 22 auto_biome_rules: a band over elevation+slope. Per-axis
    weight ramps from (min - band_in) → min via smoothstep, holds 1
    through max, then ramps down to (max + band_out). Product across
    axes is the cell's pre-softmax score for this biome.

    Same shape as shader `w5_slot_weight` for consistency."""
    elev_min, elev_max = float(rule["elevation_m"][0]), float(rule["elevation_m"][1])
    slope_min, slope_max = float(rule["slope_deg"][0]), float(rule["slope_deg"][1])
    elev_band = max(float(rule.get("band_width_elevation_m", 0.0)), 1e-3)
    slope_band = max(float(rule.get("band_width_slope_deg", 0.0)), 1e-3)

    ew_in = _smoothstep(elev_min - elev_band, elev_min, elev)
    ew_out = 1.0 - _smoothstep(elev_max, elev_max + elev_band, elev)
    sw_in = _smoothstep(slope_min - slope_band, slope_min, slope)
    sw_out = 1.0 - _smoothstep(slope_max, slope_max + slope_band, slope)

    return (ew_in * ew_out) * (sw_in * sw_out)


# --- chain dispatch ---


_EROSION_PARAM_KEYS = (
    "iterations", "rain_rate", "evaporation", "sediment_capacity",
    "dissolve_rate", "deposit_rate", "min_slope", "gravity",
    "thermal_iterations", "talus_angle_deg", "talus_rate", "seed",
)
_NOISE_PARAM_KEYS = ("octaves", "frequency", "lacunarity", "gain", "amplitude")
_DEM_FEATURE_PARAM_KEYS = (
    "dem_path", "modes", "ridge_smooth_sigma_cells", "seed",
)


def _instantiate_stage(stage: dict):
    """Build a kernel instance from a single-stage spec.
    Supported: noise_stack (base generator), erosion (post-process),
    dem_feature (post-process, Sprint 3 of the DEM/runtime-kernels epic).

    Per spec 19, the first stage of a chain MUST be a base generator
    (noise_stack); subsequent stages MAY be post-processes.
    KernelComposer.__init__ validates chain ordering; this function
    just builds the instance for whichever stage type is asked.

    Phase 5.7.c: erosion was previously deferred (NotImplementedError)
    pending bake_page. Now bake_page runs erosion stages on whole
    pages; this function returns a usable ErosionKernel instance.
    Per-POINT sample_height still skips erosion (correctly — erosion
    is not a per-point function).

    Sprint 3: dem_feature stages are bundle-side concerns (the GDScript
    runtime resolves the source ID to a DemSource at page generation
    time). The Python composer returns a *placeholder* DemFeatureKernel
    so chain parsing succeeds end-to-end; per-POINT sample_height
    treats dem_feature as a no-op (the feature blend is bake-time + GPU
    only in v1)."""
    stype = stage.get("type", "")
    params = stage.get("params", {}) or {}
    if stype == "noise_stack":
        return NoiseStackKernel(**{k: params[k] for k in _NOISE_PARAM_KEYS
                                   if k in params})
    if stype == "erosion":
        return ErosionKernel(**{k: params[k] for k in _EROSION_PARAM_KEYS
                                if k in params})
    if stype == "dem_feature":
        # Map catalog params (source, mode, strength) onto the Python
        # ref DemFeatureKernel (dem_path, modes). The Python ref isn't
        # consumed at runtime; this just makes chain parsing succeed.
        from world5.kernels import DemFeatureKernel
        mode = params.get("mode", "ridge_emphasis")
        return DemFeatureKernel(
            dem_path=params.get("source", ""),
            modes=(mode,),
            ridge_smooth_sigma_cells=float(
                params.get("ridge_smooth_sigma_cells", 2.0)),
            seed=int(params.get("seed", 42)),
        )
    raise ValueError(f"unknown kernel stage type: {stype!r}")


def _normalize_chain(kernel_field: dict) -> list[dict]:
    """A biome's `kernel` field is either a single-stage spec or a
    chain spec. Normalize to a list of single-stage specs."""
    if not isinstance(kernel_field, dict):
        raise ValueError(f"kernel must be a dict, got {type(kernel_field)}")
    ktype = kernel_field.get("type", "")
    if ktype == "chain":
        stages = kernel_field.get("stages", [])
        if not isinstance(stages, list) or len(stages) == 0:
            raise ValueError("chain kernel must have a non-empty `stages` array")
        return list(stages)
    # Shorthand: a single-stage spec IS a chain of length 1.
    return [kernel_field]


# --- composer ---


@dataclass
class _BiomeEntry:
    name: str
    auto_rule: dict
    chain: list[dict]
    instantiated_stages: list   # cached kernel instances


class KernelComposer:
    """Composer for a multi-biome catalog. Construct from a parsed
    biome_catalog.json (or any dict matching the catalog schema)."""

    def __init__(self, catalog: dict) -> None:
        biomes_field = catalog.get("biomes")
        if not isinstance(biomes_field, list) or len(biomes_field) == 0:
            raise ValueError("catalog must have at least one biome in `biomes`")

        self._catalog_hash = _hash_catalog(catalog)
        self._biomes: list[_BiomeEntry] = []
        for b in biomes_field:
            name = str(b.get("name", "")).strip()
            if name == "":
                raise ValueError("biome missing `name`")
            kernel_field = b.get("kernel")
            if kernel_field is None:
                raise ValueError(f"biome {name!r} missing `kernel` field")
            chain = _normalize_chain(kernel_field)
            # Instantiate stages eagerly so config errors surface at
            # construct time, not at first sample.
            stages = [_safe_instantiate(s, name) for s in chain]
            # Spec 19 chain-ordering: first stage MUST be a base generator
            # (NoiseStackKernel). Post-process stages (erosion) need
            # height-IN, so they can't lead a chain.
            if not isinstance(stages[0], NoiseStackKernel):
                raise ValueError(
                    f"biome {name!r}: first chain stage must be a base "
                    f"generator (noise_stack); got {type(stages[0]).__name__}")
            # Default auto_rule to "always-on" if missing (back-compat
            # with single-biome catalogs that didn't bound their range).
            auto_rule = b.get("auto_biome_rules") or {
                "elevation_m": [-1e6, 1e6], "slope_deg": [0.0, 90.0],
                "band_width_elevation_m": 1.0, "band_width_slope_deg": 1.0,
            }
            self._biomes.append(_BiomeEntry(
                name=name, auto_rule=auto_rule, chain=chain,
                instantiated_stages=stages,
            ))

    # --- introspection ---

    @property
    def biome_count(self) -> int:
        return len(self._biomes)

    @property
    def biome_names(self) -> list[str]:
        return [b.name for b in self._biomes]

    # --- biome weights (Phase 6 multi-biome render consumer) ---

    def biome_weights(self, x: float, z: float,
                      elev_m: float, slope_deg: float) -> np.ndarray:
        """Per spec 22 §biome_weights. Compute the per-biome selection
        weight at this (x, z, elev, slope). Output sums to 1 (softmax-
        normalized; really sum-normalized since each biome's raw weight
        is a probability-shaped product of smoothsteps in [0, 1]).

        Returns shape (biome_count,) float32 array. Order matches
        `self.biome_names`."""
        raw = np.array(
            [_band_weight(elev_m, slope_deg, b.auto_rule) for b in self._biomes],
            dtype=np.float64,
        )
        total = float(raw.sum())
        if total <= 1e-9:
            # No biome's auto_rule covers this (elev, slope) — fall
            # back to uniform so the renderer still picks SOMETHING.
            return np.full(self.biome_count, 1.0 / self.biome_count,
                           dtype=np.float32)
        return (raw / total).astype(np.float32)

    # --- height (chain dispatch) ---

    def sample_height(self, x: float, z: float, seed: int) -> float:
        """Sample the composed height at (x, z) with `seed`.

        Single-biome catalogs: pass through the biome's chain output.
        Multi-biome catalogs (Phase 6+): currently returns the weighted
        sum of each biome's chain output (works for chains-of-1 where
        all biomes share a noise_stack with compatible amplitudes).
        True multi-biome height blending with different kernel chains
        per biome lands when erosion enters the chain (5.7.c).
        """
        weights_uniform_seed = np.array([1.0] * self.biome_count) \
            if self.biome_count > 1 else np.array([1.0])
        # When all biomes share an identical NoiseStackKernel (walking
        # demo case), sampling once + weight-summing gives the same
        # result as N samples + weight-sum (since they all return the
        # same value). Still, compute per-biome for general correctness.
        h_total = 0.0
        # For now use uniform across biomes (no per-(x,z) blend at
        # height level); biome_weights drives the MATERIAL blend in
        # the shader. When chains diverge per biome, this becomes
        # weighted by biome_weights(x, z, h_self_estimate, slope_self).
        # Iterating chains at sample-point granularity:
        for b in self._biomes:
            h_total += self._sample_chain(b.instantiated_stages, x, z, seed)
        return float(h_total / max(self.biome_count, 1))

    def _sample_chain(self, stages: list, x: float, z: float,
                      seed: int) -> float:
        """Run the chain on a single point. Only the base generator
        contributes — erosion (post-process) needs page-scope context
        + is dispatched via bake_page. sample_height callers get the
        un-eroded value; for eroded heights at known XZ, bake the
        relevant page + sample via local bilinear."""
        if not stages:
            return 0.0
        base = stages[0]
        # __init__ already validated base is a NoiseStackKernel.
        arr = base.sample_page((x, z), extent_m=1.0, grid_n=2, seed=seed)
        return float(arr[0, 0])

    # --- bake_page (Phase 5.7.c, the erosion-in-chain unblocker) ---

    def bake_page(
        self,
        world_origin_xz: tuple[float, float],
        extent_m: float,
        grid_n: int,
        seed: int,
        store=None,  # type: Optional[ContentAddressStore]
        biome_index: int = 0,
    ) -> np.ndarray:
        """Run the full kernel chain on a whole page. Erosion stages
        execute here (they need page-scope context).

        Per spec 19 + spec 12: when `store` is provided, the output is
        content-addressed by sha256(catalog_hash + world_origin +
        extent + grid + seed + biome_index). Cache hit → bytes loaded
        from disk, no recompute. Cache miss → chain runs, output
        stored.

        Returns (grid_n, grid_n) float32 array (row-major, [r,c] =
        sample at world_origin + (c, r) * cell, matching the
        NoiseStackKernel ordering).

        biome_index selects which biome's chain to bake (default 0 =
        first biome). Multi-biome blending across biomes is a
        renderer concern (per-fragment via biome_weights), not a
        bake concern."""
        if biome_index < 0 or biome_index >= self.biome_count:
            raise IndexError(
                f"biome_index {biome_index} out of range [0, {self.biome_count})")
        biome = self._biomes[biome_index]

        # Cache key + provenance metadata (used both for cache lookup
        # and for cache-miss `put`).
        cache_key = self._page_cache_key(
            world_origin_xz, extent_m, grid_n, seed, biome.name)
        provenance = {
            "catalog_hash": self._catalog_hash,
            "biome": biome.name,
            "biome_index": biome_index,
            "world_origin_xz": list(world_origin_xz),
            "extent_m": float(extent_m),
            "grid_n": int(grid_n),
            "seed": int(seed),
            "chain_types": [type(s).__name__ for s in biome.instantiated_stages],
        }

        # Cache hit path.
        if store is not None and store.has(cache_key):
            artifact_path = store.get(cache_key)
            return _load_page_bytes(artifact_path, grid_n)

        # Cache miss path: run the chain.
        page = self._run_chain_on_page(
            biome.instantiated_stages,
            world_origin_xz, extent_m, grid_n, seed,
        )

        # Persist if a store was provided.
        if store is not None:
            store.put(cache_key, page.tobytes(), metadata=provenance)

        return page

    def _run_chain_on_page(
        self,
        stages: list,
        world_origin_xz: tuple[float, float],
        extent_m: float,
        grid_n: int,
        seed: int,
    ) -> np.ndarray:
        """Execute a chain on a page. First stage produces the base
        height; subsequent stages are post-processes that take the
        prior stage's height-OUT as their input."""
        if not stages:
            raise ValueError("empty chain")
        # Stage 0 must be a base generator (validated at __init__).
        base = stages[0]
        height = base.sample_page(world_origin_xz, extent_m=extent_m,
                                  grid_n=grid_n, seed=seed)
        # Stages 1..N are post-processes. Each takes height in, returns
        # height out (plus auxiliary outputs we don't currently expose
        # via bake_page — those will land when spec 35 water consumes
        # drainage_map directly through a separate API).
        for stage in stages[1:]:
            if isinstance(stage, ErosionKernel):
                result = stage.erode(height)
                height = result.eroded
            else:
                raise ValueError(
                    f"unsupported post-process stage type: "
                    f"{type(stage).__name__}")
        return height.astype(np.float32)

    def _page_cache_key(
        self,
        world_origin_xz: tuple[float, float],
        extent_m: float,
        grid_n: int,
        seed: int,
        biome_name: str,
    ) -> str:
        """Compute the cache key for a page bake. Includes the catalog
        hash so a catalog edit invalidates all baked pages."""
        from world5.content_address import ContentAddressStore
        # Use a transient store just for its hash_inputs method —
        # hashing doesn't touch the filesystem.
        return ContentAddressStore.hash_inputs.__call__(
            _DummyHasher(),
            {
                "kind": "kernel_composer.bake_page",
                "catalog_hash": self._catalog_hash,
                "biome": biome_name,
                "world_origin_x": float(world_origin_xz[0]),
                "world_origin_z": float(world_origin_xz[1]),
                "extent_m": float(extent_m),
                "grid_n": int(grid_n),
                "seed": int(seed),
            },
        )


# --- cache helpers ---


def _hash_catalog(catalog: dict) -> str:
    """Stable hash of the catalog so kernel/auto_rule edits invalidate
    cached bakes. JSON-canonicalized to ignore key-order differences."""
    import hashlib
    canonical = json.dumps(catalog, sort_keys=True, separators=(",", ":"),
                           default=str)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _load_page_bytes(artifact_path, grid_n: int) -> np.ndarray:
    """Reverse of `page.tobytes()` — load a baked float32 page from
    the content-addressed store back into an (grid_n, grid_n) array."""
    raw = artifact_path.read_bytes()
    arr = np.frombuffer(raw, dtype=np.float32)
    return arr.reshape(grid_n, grid_n).copy()  # copy: arr is read-only


class _DummyHasher:
    """Borrows ContentAddressStore.hash_inputs's canonical-JSON-then-
    sha256 logic without instantiating a real store (no filesystem
    touch). Only `_file_hash_cache` would be used by hash_inputs if
    FileInput entries were passed; we never pass them, so the empty
    dict suffices."""
    def __init__(self):
        self._file_hash_cache: dict = {}


def _safe_instantiate(stage: dict, biome_name: str):
    """Wrap _instantiate_stage to surface biome context in error msgs."""
    try:
        return _instantiate_stage(stage)
    except Exception as e:
        raise ValueError(
            f"biome {biome_name!r} kernel stage invalid: {e}") from e
