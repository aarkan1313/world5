"""NoiseStackKernel — Python reference for the fBm height kernel.

Must produce the same heights (within 1e-3 m tolerance) as the GPU
compute shader at engine/shaders/terrain_page_gen.glsl. The parity
test in tests/integration/test_terrain_backend_parity.py verifies
this.

Algorithm:
- Per sample: world_xz -> fBm value -> amplitude scaling
- fBm: octave-summed value noise (value at lattice points hashed by
  Wang's integer hash, smoothstep-interpolated bilinearly)

This is a deliberate exact reimplementation of the shader math; the
parity test is the cross-impl check (spec 06 + SA2-C2.1 pattern).
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


# --- hash helpers (must match GLSL exactly) ---

def hash_u32(x: np.ndarray) -> np.ndarray:
    """Wang hash on uint32 arrays. Must match GLSL hash_u32."""
    x = x.astype(np.uint32, copy=True)
    x = (x ^ np.uint32(61)) ^ (x >> np.uint32(16))
    x = x * np.uint32(9)
    x = x ^ (x >> np.uint32(4))
    x = x * np.uint32(0x27d4eb2d)
    x = x ^ (x >> np.uint32(15))
    return x


def hash2i(cell_x: np.ndarray, cell_y: np.ndarray, seed: int) -> np.ndarray:
    """2D hash on integer cell coords + seed -> [0,1) float."""
    cx = cell_x.astype(np.int32).astype(np.uint32)
    cy = cell_y.astype(np.int32).astype(np.uint32)
    # Wrap seed mod 2^32 to match GLSL uint arithmetic
    s = np.uint32(int(seed) & 0xFFFFFFFF)
    h = hash_u32(cx ^ hash_u32(cy ^ hash_u32(np.full_like(cx, s))))
    # Same mask + divisor as GLSL: (h & 0x00FFFFFF) / float(0x01000000)
    h24 = (h & np.uint32(0x00FFFFFF)).astype(np.float32)
    return h24 / np.float32(0x01000000)


def value_noise2(px: np.ndarray, py: np.ndarray, seed: int) -> np.ndarray:
    """Value noise: bilinearly-interpolated hash on a unit grid."""
    pi_x = np.floor(px).astype(np.int32)
    pi_y = np.floor(py).astype(np.int32)
    pf_x = (px - pi_x.astype(np.float32)).astype(np.float32)
    pf_y = (py - pi_y.astype(np.float32)).astype(np.float32)
    # Smoothstep: w = pf*pf*(3 - 2*pf)
    wx = pf_x * pf_x * (np.float32(3.0) - np.float32(2.0) * pf_x)
    wy = pf_y * pf_y * (np.float32(3.0) - np.float32(2.0) * pf_y)
    # int32 literals so NumPy on Windows doesn't upcast to int64
    # (S5: drift risk near INT32 extremes; matches GLSL ivec2 + 1)
    one = np.int32(1)
    zero = np.int32(0)
    a = hash2i(pi_x + zero, pi_y + zero, seed)
    b = hash2i(pi_x + one, pi_y + zero, seed)
    c = hash2i(pi_x + zero, pi_y + one, seed)
    d = hash2i(pi_x + one, pi_y + one, seed)
    ab = a + (b - a) * wx     # mix(a, b, wx)
    cd = c + (d - c) * wx     # mix(c, d, wx)
    return ab + (cd - ab) * wy  # mix(ab, cd, wy)


def fbm(px: np.ndarray, py: np.ndarray, octaves: int, frequency: float,
        lacunarity: float, gain: float, seed: int) -> np.ndarray:
    """fBm: octave-summed value noise. Output range roughly [-1, 1]."""
    sum_v = np.zeros_like(px, dtype=np.float32)
    amp = np.float32(1.0)
    freq = np.float32(frequency)
    norm = np.float32(0.0)
    for i in range(octaves):
        # Mask to uint32 to match GLSL `seed + i * 1013u` overflow
        sub_seed = (int(seed) + i * 1013) & 0xFFFFFFFF
        nv = value_noise2(px * freq, py * freq, sub_seed)
        sum_v = sum_v + amp * (nv * np.float32(2.0) - np.float32(1.0))
        norm = norm + amp
        amp = amp * np.float32(gain)
        freq = freq * np.float32(lacunarity)
    return sum_v / norm


# --- Kernel API ---

@dataclass(frozen=True)
class NoiseStackKernel:
    """fBm heightmap kernel. Defaults match the GLSL backend Phase 4.2
    hard-coded params; future spec 19 work parameterizes via world bundle."""

    octaves: int = 6
    frequency: float = 1.0 / 512.0   # cycles/m
    lacunarity: float = 2.0
    gain: float = 0.5
    amplitude: float = 50.0           # meters

    def sample_page(self, world_origin_xz: tuple[float, float],
                    extent_m: float, grid_n: int, seed: int) -> np.ndarray:
        """Sample a square page. Returns (grid_n, grid_n) float32 array,
        row-major; element [r, c] is sample at world_origin + (c, r) * cell.

        Matches GLSL ordering: idx = gid.y * grid_n + gid.x.
        """
        cell = extent_m / max(grid_n - 1, 1)
        ix = np.arange(grid_n, dtype=np.float32)
        iy = np.arange(grid_n, dtype=np.float32)
        xs = world_origin_xz[0] + ix * cell  # shape (grid_n,)
        ys = world_origin_xz[1] + iy * cell
        # Broadcast to (grid_n, grid_n)
        xx, yy = np.meshgrid(xs, ys)
        h = self.amplitude * fbm(
            xx.astype(np.float32),
            yy.astype(np.float32),
            self.octaves,
            self.frequency,
            self.lacunarity,
            self.gain,
            seed,
        )
        return h.astype(np.float32)
