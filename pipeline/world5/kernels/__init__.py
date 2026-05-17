"""W5 kernel system — Python reference + canonical implementations.

Per spec 19. Kernels are the math that turns world coordinates into
terrain fields (height, slope, biome, etc.). Each kernel has a
Python reference implementation (this package) and a GPU compute
implementation (engine/shaders/) that must match within tolerance.

Phase 4.2 ships NoiseStackKernel only. ErosionKernel + DemFeatureKernel
land in Phase 5+ per the spec 19 / phase 4 roadmap.
"""

from world5.kernels.noise_stack import NoiseStackKernel  # noqa: F401

__all__ = ["NoiseStackKernel"]
