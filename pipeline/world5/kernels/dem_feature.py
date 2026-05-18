"""DemFeatureKernel — Python reference for DEM-derived feature extraction.

Spec 19 §"Kernel types shipped in v1" item 3. Sprint 2 of the DEM/
runtime-kernels epic.

Extracts ridge / drainage / slope / aspect features from a real DEM
(GeoTIFF). These features become procedural kernel inputs — the
composer can blend DEM-derived ridge_emphasis into a noise+erosion
chain so generated worlds feel grounded in real geology without being
recognizable copies of the source.

This is the PARITY REFERENCE — the ground truth a future GPU compute
port is tested against. CPU-only, scipy/rasterio. Output is per-cell
float fields packed into a Dict keyed by feature mode name.

Algorithm summary:

- ridge_emphasis: positive curvature of the height field via discrete
  Laplacian. Smoothed (gaussian σ ~ 2 cells) to suppress per-pixel
  noise. Normalized to [0, 1] over the queried extent. Output strong
  where the surface bends UP (ridges, peaks); near zero in flat
  regions; slightly negative-clipped in valleys (we clamp at 0 for the
  "ridge emphasis" semantic — use drainage_accumulation for the
  inverse).

- drainage_accumulation: D8 single-flow accumulation. For each cell,
  flow goes to its steepest-descent neighbor (one of 8). Accumulation
  counts upstream cells; log-scaled + normalized to [0, 1] so river
  networks read as bright features over a dark background.

- slope_deg: per-cell slope in degrees from height gradient magnitude.
  Output range 0..90.

- aspect_deg: per-cell aspect (compass direction of steepest descent)
  in degrees [0, 360).

Caching: outputs are deterministic given (DEM source path + bounds +
grid_n + mode). Caller (the runtime) uses spec 12 content addressing
on those inputs to skip re-extraction.

Determinism: given the same DEM + params, output is byte-identical
(numpy ops, no RNG, no parallelism beyond numpy's internal threading
which is deterministic for these ops).
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np


# D8 neighbor offsets (8 cardinal + diagonal); index → (dy, dx, dist).
# Order: E, SE, S, SW, W, NW, N, NE (clockwise from East).
_D8_OFFSETS = [
    ( 0,  1, 1.0),
    ( 1,  1, np.sqrt(2.0)),
    ( 1,  0, 1.0),
    ( 1, -1, np.sqrt(2.0)),
    ( 0, -1, 1.0),
    (-1, -1, np.sqrt(2.0)),
    (-1,  0, 1.0),
    (-1,  1, np.sqrt(2.0)),
]


@dataclass(frozen=True)
class DemFeatureResult:
    """Output of `DemFeatureKernel.extract()`. Dict-of-fields keyed by
    mode name. Each field is a (rows, cols) float32 array."""

    features: dict[str, np.ndarray]


@dataclass(frozen=True)
class DemFeatureKernel:
    """DEM feature extraction config.

    - `dem_path`: path to a GeoTIFF or NPZ file holding the DEM.
      Format auto-detected from extension.
    - `modes`: feature modes to extract. Allowed: "ridge_emphasis",
      "drainage_accumulation", "slope_deg", "aspect_deg".
    - `ridge_smooth_sigma_cells`: gaussian smoothing applied before
      computing curvature (in source-DEM cells). Default 2.0 suppresses
      single-pixel sensor noise without losing real-world ridges.
    - `seed`: reserved for future stochastic variants; currently unused
      (algorithm is deterministic).
    """

    dem_path: str = ""
    modes: tuple = ("ridge_emphasis",)
    ridge_smooth_sigma_cells: float = 2.0
    seed: int = 42

    def extract(
        self,
        world_xz_min: tuple[float, float],
        world_xz_max: tuple[float, float],
        grid_n: int,
        dem_array: np.ndarray | None = None,
    ) -> DemFeatureResult:
        """Extract features for the given world-XZ window at grid_n²
        resolution.

        For testing: `dem_array` can be supplied directly to bypass the
        on-disk load (so tests can run without a real GeoTIFF). When
        omitted, the kernel loads from `dem_path`.

        World-XZ bounds are interpreted in the DEM's own coordinate
        system — this v1 reference assumes the DEM has already been
        reprojected/cropped to the world by the pipeline tool
        `tx_dem_prepare`. We sample the DEM on a regular grid of
        `grid_n × grid_n` cells over `[world_xz_min, world_xz_max]`.
        """
        if grid_n <= 0:
            raise ValueError(f"grid_n must be > 0 (got {grid_n})")
        if dem_array is None:
            dem_array = self._load_dem(self.dem_path)
        if dem_array.ndim != 2:
            raise ValueError(
                f"DEM must be 2D height grid (got shape {dem_array.shape})"
            )
        # Resample the DEM to the requested grid. The DEM array is
        # treated as already-cropped to the world bounds, so we just
        # bilinear-resample to grid_n × grid_n.
        h_grid = self._resample(dem_array, grid_n)

        features: dict[str, np.ndarray] = {}
        for mode in self.modes:
            if mode == "ridge_emphasis":
                features[mode] = self._ridge_emphasis(h_grid).astype(np.float32)
            elif mode == "drainage_accumulation":
                features[mode] = self._drainage_accumulation(h_grid).astype(np.float32)
            elif mode == "slope_deg":
                features[mode] = self._slope_deg(h_grid).astype(np.float32)
            elif mode == "aspect_deg":
                features[mode] = self._aspect_deg(h_grid).astype(np.float32)
            else:
                raise ValueError(f"unknown feature mode '{mode}'")
        return DemFeatureResult(features=features)

    # --- loaders -----------------------------------------------------

    @staticmethod
    def _load_dem(path: str) -> np.ndarray:
        if not path:
            raise ValueError("DemFeatureKernel.dem_path is empty")
        p = Path(path)
        if not p.exists():
            raise FileNotFoundError(f"DEM not found: {p}")
        suffix = p.suffix.lower()
        if suffix in (".tif", ".tiff"):
            try:
                import rasterio  # type: ignore
            except ImportError as e:
                raise ImportError(
                    "rasterio required to load GeoTIFF DEMs; install via pip"
                ) from e
            with rasterio.open(p) as src:
                arr = src.read(1).astype(np.float32)
            return arr
        if suffix == ".npz":
            with np.load(p) as z:
                # Look for first 2D float array
                for k in z.files:
                    a = z[k]
                    if a.ndim == 2:
                        return a.astype(np.float32)
            raise ValueError(f"no 2D array found in {p}")
        if suffix == ".npy":
            arr = np.load(p)
            return arr.astype(np.float32)
        raise ValueError(f"unsupported DEM extension '{suffix}' (need .tif/.tiff/.npz/.npy)")

    @staticmethod
    def _resample(arr: np.ndarray, grid_n: int) -> np.ndarray:
        """Bilinear-resample 2D array to grid_n × grid_n. Uses scipy's
        map_coordinates for proper interpolation."""
        try:
            from scipy.ndimage import map_coordinates  # type: ignore
        except ImportError as e:
            raise ImportError("scipy required for DEM resampling") from e
        src_rows, src_cols = arr.shape
        # Sample coords across the source array; +0.5 centers samples
        # on cells (so corner pixels aren't sampled at the boundary).
        y = np.linspace(0.0, src_rows - 1.0, grid_n)
        x = np.linspace(0.0, src_cols - 1.0, grid_n)
        yy, xx = np.meshgrid(y, x, indexing="ij")
        coords = np.stack([yy.ravel(), xx.ravel()], axis=0)
        out = map_coordinates(arr, coords, order=1, mode="reflect")
        return out.reshape(grid_n, grid_n).astype(np.float32)

    # --- features ----------------------------------------------------

    def _ridge_emphasis(self, h: np.ndarray) -> np.ndarray:
        """Smoothed positive curvature: ridges read bright, flats dark."""
        try:
            from scipy.ndimage import gaussian_filter, laplace  # type: ignore
        except ImportError as e:
            raise ImportError("scipy required for ridge_emphasis") from e
        sigma = max(self.ridge_smooth_sigma_cells, 0.001)
        smooth = gaussian_filter(h, sigma=sigma, mode="reflect")
        # Discrete Laplacian — POSITIVE in valleys, NEGATIVE on ridges
        # by sign convention (∇²h < 0 where the surface bends down at
        # both axes). Flip sign so ridges are positive.
        lap = -laplace(smooth, mode="reflect")
        # Clip to non-negative (we only want ridges).
        lap = np.clip(lap, 0.0, None)
        # Normalize to [0, 1] over this grid.
        lo, hi = float(lap.min()), float(lap.max())
        if hi - lo > 1e-6:
            lap = (lap - lo) / (hi - lo)
        else:
            lap = np.zeros_like(lap)
        return lap

    @staticmethod
    def _drainage_accumulation(h: np.ndarray) -> np.ndarray:
        """D8 single-flow accumulation, log-scaled, normalized [0, 1]."""
        rows, cols = h.shape
        # Compute each cell's steepest-descent direction (one of 8 or
        # -1 if it's a sink / boundary).
        flow_dir = np.full((rows, cols), -1, dtype=np.int8)
        for r in range(rows):
            for c in range(cols):
                here = h[r, c]
                best_drop = 0.0
                best_dir = -1
                for d, (dr, dc, dist) in enumerate(_D8_OFFSETS):
                    nr, nc = r + dr, c + dc
                    if nr < 0 or nr >= rows or nc < 0 or nc >= cols:
                        continue
                    drop = (here - h[nr, nc]) / dist
                    if drop > best_drop:
                        best_drop = drop
                        best_dir = d
                flow_dir[r, c] = best_dir
        # Accumulation: each cell starts with weight 1 (itself); add 1
        # to its downstream target. Iterate in elevation order
        # (high → low) so each cell's accumulation is finalized before
        # we read it for the next step.
        accum = np.ones((rows, cols), dtype=np.float32)
        # Sort cells by elevation, descending.
        flat_idx = np.argsort(-h.ravel())
        for idx in flat_idx:
            r, c = divmod(int(idx), cols)
            d = int(flow_dir[r, c])
            if d < 0:
                continue
            dr, dc, _ = _D8_OFFSETS[d]
            accum[r + dr, c + dc] += accum[r, c]
        # Log scale + normalize.
        log_accum = np.log1p(accum)
        lo, hi = float(log_accum.min()), float(log_accum.max())
        if hi - lo > 1e-6:
            return ((log_accum - lo) / (hi - lo)).astype(np.float32)
        return np.zeros_like(log_accum, dtype=np.float32)

    @staticmethod
    def _slope_deg(h: np.ndarray) -> np.ndarray:
        gy, gx = np.gradient(h)
        return np.degrees(np.arctan(np.sqrt(gx * gx + gy * gy))).astype(np.float32)

    @staticmethod
    def _aspect_deg(h: np.ndarray) -> np.ndarray:
        gy, gx = np.gradient(h)
        # Aspect = compass direction of steepest descent. atan2(-gx, gy)
        # gives 0 = N, 90 = E (standard GIS convention).
        a = np.degrees(np.arctan2(-gx, gy))
        a = np.mod(a, 360.0)
        return a.astype(np.float32)
