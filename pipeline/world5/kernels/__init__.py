"""W5 kernel system — Python reference + canonical implementations.

Per spec 19. Kernels are the math that turns world coordinates into
terrain fields (height, slope, biome, etc.). Each kernel has a
Python reference implementation (this package) and a GPU compute
implementation (engine/shaders/) that must match within tolerance.

Phase 4.2 shipped NoiseStackKernel. Phase 5.7.a adds ErosionKernel
(hydraulic + thermal post-process). Sprint 2 (2026-05-18) adds
DemFeatureKernel (ridge / drainage / slope / aspect extraction from
real DEMs, per spec 19 amendment).
"""

from world5.kernels.noise_stack import NoiseStackKernel  # noqa: F401
from world5.kernels.erosion import ErosionKernel, ErosionResult  # noqa: F401
from world5.kernels.composer import KernelComposer  # noqa: F401
from world5.kernels.dem_feature import DemFeatureKernel, DemFeatureResult  # noqa: F401

__all__ = [
    "NoiseStackKernel",
    "ErosionKernel",
    "ErosionResult",
    "KernelComposer",
    "DemFeatureKernel",
    "DemFeatureResult",
]
