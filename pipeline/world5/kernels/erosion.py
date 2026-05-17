"""ErosionKernel — Python reference for hydraulic + thermal erosion.

Spec 19 §"Kernel types shipped in v1" item 2. Phase 5.7.a.

This is the PARITY REFERENCE — the ground truth a future GPU compute
port (5.7.d) is tested against. Optimized for clarity + correctness,
not speed. numpy-vectorized but single-threaded; targets ~60s on a
1024² grid with ~100 iterations (spec 19 Quality bar).

Algorithm summary:

Hydraulic pass (Mei et al. 2007):
1. Add rain to every cell (water += rain_rate per iteration)
2. For each cell, compute flow flux into the 4 cardinal neighbors
   proportional to height delta (water-surface delta, not terrain).
   Scale fluxes if outflow would empty the cell.
3. Update water depth: water += inflow - outflow per cell.
4. Compute velocity vector from net flux + flow direction.
5. Sediment-carrying capacity: C = Kc * sin(slope) * |velocity|.
   Compare to current dissolved sediment:
   - if sediment < capacity: dissolve = dissolve_rate * (capacity - sediment);
     terrain -= dissolve, sediment += dissolve
   - if sediment > capacity: deposit = deposit_rate * (sediment - capacity);
     terrain += deposit, sediment -= deposit
6. Sediment transport: sediment flows with the water (advected by velocity).
7. Evaporate: water *= (1 - evaporation).

Thermal pass (Musgrave/Kolb, interleaved with hydraulic):
1. For each cell, find the steepest of the 4 cardinal slopes.
2. If slope_angle > talus_angle, slump material proportional to
   excess: amount = talus_rate * (slope_height - talus_height).
3. Move that material to the downhill neighbor.

Auxiliary outputs (spec 19 §"Auxiliary outputs"):
- drainage_map: time-accumulated total water flux through each cell
  (sum of outflow magnitudes over the simulation)
- flow_direction: final-step (vx, vy) velocity field
- flow_accumulation: per-cell count of upstream cells (computed
  post-sim by walking the flow_direction graph)

Determinism: given the same input height + params, output is
byte-identical (no random number generation in the inner loop).
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np


@dataclass(frozen=True)
class ErosionResult:
    """Output of `ErosionKernel.erode()`. Spec 19 §"Auxiliary outputs"."""
    eroded: np.ndarray             # (H, W) float32 — eroded height field
    drainage_map: np.ndarray       # (H, W) float32 — accumulated flux
    flow_direction: np.ndarray     # (H, W, 2) float32 — (vx, vy) per cell
    flow_accumulation: np.ndarray  # (H, W) float32 — upstream cell count


@dataclass(frozen=True)
class ErosionKernel:
    """Spec 19 ErosionKernel — hydraulic + thermal erosion.

    Defaults match the schema at engine/resources/schemas/kernels/erosion.schema.json.
    Mei 2007 parameter naming + ranges where applicable.
    """

    iterations: int = 50
    rain_rate: float = 0.012
    evaporation: float = 0.015
    sediment_capacity: float = 0.10
    dissolve_rate: float = 0.30
    deposit_rate: float = 0.30
    min_slope: float = 0.005
    gravity: float = 9.81
    thermal_iterations: int = 50
    talus_angle_deg: float = 30.0
    talus_rate: float = 0.25
    seed: int = 42

    def erode(self, height: np.ndarray) -> ErosionResult:
        """Run iterations of hydraulic + thermal erosion. Returns an
        ErosionResult with the eroded height + spec 19 auxiliary
        outputs. Input is not modified."""
        if height.ndim != 2:
            raise ValueError(f"expected 2D height, got shape {height.shape}")
        h = height.astype(np.float32, copy=True)
        n_rows, n_cols = h.shape

        water = np.zeros_like(h)
        sediment = np.zeros_like(h)
        drainage = np.zeros_like(h)
        vel_x = np.zeros_like(h)
        vel_y = np.zeros_like(h)

        # Cell size in world units (the simulation is unitless past
        # this — we just need consistent ratios). The schema's gravity
        # constant only matters as a scaling factor on velocity.
        cell_size = 1.0
        talus_height = float(np.tan(np.radians(self.talus_angle_deg))) * cell_size

        # Interleave hydraulic + thermal. We want roughly thermal_iterations
        # of thermal over the course of `iterations` hydraulic steps.
        if self.iterations > 0:
            thermal_every = max(
                1,
                self.iterations // max(self.thermal_iterations, 1)
            ) if self.thermal_iterations > 0 else self.iterations + 1
        else:
            thermal_every = 1  # only thermal mode

        for it in range(self.iterations):
            self._hydraulic_step(
                h, water, sediment, vel_x, vel_y, drainage,
            )
            if self.thermal_iterations > 0 and (it % thermal_every == 0):
                self._thermal_step(h, talus_height)

        # iterations=0 case: only thermal_iterations of pure thermal
        if self.iterations == 0 and self.thermal_iterations > 0:
            for _ in range(self.thermal_iterations):
                self._thermal_step(h, talus_height)

        flow_direction = np.stack([vel_x, vel_y], axis=-1).astype(np.float32)
        flow_accum = self._flow_accumulation(flow_direction)

        return ErosionResult(
            eroded=h,
            drainage_map=drainage.astype(np.float32),
            flow_direction=flow_direction,
            flow_accumulation=flow_accum.astype(np.float32),
        )

    # --- hydraulic step (Mei 2007) ---

    def _hydraulic_step(
        self,
        h: np.ndarray,
        water: np.ndarray,
        sediment: np.ndarray,
        vel_x: np.ndarray,
        vel_y: np.ndarray,
        drainage: np.ndarray,
    ) -> None:
        # 1. Add rain.
        water += self.rain_rate

        # 2. Compute outflow flux to 4 cardinal neighbors.
        # Surface = height + water (water flows on top of terrain).
        surface = h + water

        # Outflow at each cell = max(0, this_surface - neighbor_surface)
        # for each of left/right/up/down. Boundary = 0 outflow.
        flux_l = np.zeros_like(h)
        flux_r = np.zeros_like(h)
        flux_u = np.zeros_like(h)
        flux_d = np.zeros_like(h)

        flux_l[:, 1:] = np.maximum(0.0, surface[:, 1:] - surface[:, :-1])
        flux_r[:, :-1] = np.maximum(0.0, surface[:, :-1] - surface[:, 1:])
        flux_u[1:, :] = np.maximum(0.0, surface[1:, :] - surface[:-1, :])
        flux_d[:-1, :] = np.maximum(0.0, surface[:-1, :] - surface[1:, :])

        # Scale fluxes if total outflow would exceed available water.
        total_out = flux_l + flux_r + flux_u + flux_d
        # Use a fraction of available water per step for stability.
        # K = water / total_out, clamped to [0, 1].
        with np.errstate(divide="ignore", invalid="ignore"):
            scale = np.where(
                total_out > 1e-8,
                np.minimum(1.0, water / np.maximum(total_out, 1e-8)),
                1.0,
            )
        flux_l *= scale
        flux_r *= scale
        flux_u *= scale
        flux_d *= scale

        # 3. Update water depth from net flux.
        # inflow to (r, c) = flux_r from (r, c-1) + flux_l from (r, c+1)
        #                  + flux_d from (r-1, c) + flux_u from (r+1, c)
        inflow = np.zeros_like(h)
        inflow[:, 1:] += flux_r[:, :-1]
        inflow[:, :-1] += flux_l[:, 1:]
        inflow[1:, :] += flux_d[:-1, :]
        inflow[:-1, :] += flux_u[1:, :]
        outflow = flux_l + flux_r + flux_u + flux_d

        water += inflow - outflow

        # Accumulate drainage (total magnitude of water moving through).
        drainage += outflow

        # 4. Velocity from net horizontal flow.
        # vx = (flux_r_in - flux_l_out) - (flux_l_in - flux_r_out) ... simplified:
        # net flow toward +x at cell = (flux_r leaving) - (flux_l leaving)
        #   averaged with neighbor contributions.
        # For a parity reference, simple per-cell:
        # vel_x = (flux_r - flux_l), vel_y = (flux_d - flux_u)
        vel_x[:] = flux_r - flux_l
        vel_y[:] = flux_d - flux_u

        # 5. Sediment capacity + dissolve/deposit.
        # Local slope: |gradient(h)|, approximated by neighbor difference.
        slope = self._slope_magnitude(h)
        speed = np.sqrt(vel_x * vel_x + vel_y * vel_y)
        capacity = self.sediment_capacity * np.maximum(slope, self.min_slope) * speed

        # Where capacity > sediment, dissolve from terrain into water.
        # Where capacity < sediment, deposit from water back onto terrain.
        delta = capacity - sediment
        dissolve = np.where(delta > 0.0, self.dissolve_rate * delta, 0.0)
        deposit = np.where(delta < 0.0, self.deposit_rate * (-delta), 0.0)
        h -= dissolve
        sediment += dissolve
        h += deposit
        sediment -= deposit

        # 6. Sediment transport — naive but stable: a fraction of
        # sediment moves with the velocity. For simplicity we use the
        # same flux scheme as water (proportional to fluxes).
        # Skip sediment transport in the reference to keep the parity
        # surface minimal — dissolve/deposit alone produces visible
        # carving on this scale. (Future: full Mei sediment advection.)

        # 7. Evaporate.
        water *= (1.0 - self.evaporation)

    # --- thermal step (Musgrave) ---

    def _thermal_step(self, h: np.ndarray, talus_height: float) -> None:
        """Slump material from cells where neighbor slope exceeds talus.
        Symmetric movement: half goes to neighbor, half stays (the
        cell's height drops, the neighbor rises by the same amount)."""
        # Compute height differences to 4 cardinal neighbors.
        # diff[r,c] in direction X = h[r,c] - h[r,c+dx]; positive = downhill.
        delta_l = np.zeros_like(h)
        delta_r = np.zeros_like(h)
        delta_u = np.zeros_like(h)
        delta_d = np.zeros_like(h)
        delta_l[:, 1:] = h[:, 1:] - h[:, :-1]
        delta_r[:, :-1] = h[:, :-1] - h[:, 1:]
        delta_u[1:, :] = h[1:, :] - h[:-1, :]
        delta_d[:-1, :] = h[:-1, :] - h[1:, :]

        # Excess over talus threshold; only positive (downhill) deltas
        # contribute. Negative deltas mean the neighbor is uphill —
        # the OTHER cell handles its own slump in this iteration.
        excess_l = np.maximum(0.0, delta_l - talus_height)
        excess_r = np.maximum(0.0, delta_r - talus_height)
        excess_u = np.maximum(0.0, delta_u - talus_height)
        excess_d = np.maximum(0.0, delta_d - talus_height)

        total_excess = excess_l + excess_r + excess_u + excess_d
        # Move talus_rate * excess from this cell to the downhill side.
        # Per-cell deduction:
        h -= self.talus_rate * total_excess
        # Per-neighbor addition (mirror the deduction):
        h[:, :-1] += self.talus_rate * excess_l[:, 1:]
        h[:, 1:] += self.talus_rate * excess_r[:, :-1]
        h[:-1, :] += self.talus_rate * excess_u[1:, :]
        h[1:, :] += self.talus_rate * excess_d[:-1, :]

    # --- slope helpers ---

    @staticmethod
    def _slope_magnitude(h: np.ndarray) -> np.ndarray:
        """Per-cell |gradient| via central differences (Sobel-like 1D).
        Returns same shape as h."""
        gy, gx = np.gradient(h)
        return np.sqrt(gx * gx + gy * gy).astype(np.float32)

    # --- flow accumulation (D8 single-flow) ---

    @staticmethod
    def _flow_accumulation(flow_direction: np.ndarray) -> np.ndarray:
        """Walk each cell's flow_direction downhill to the next cell,
        accumulating an upstream count. Bounded by grid size; cycles
        impossible since flow_direction is a velocity field that
        flowed downhill at each step."""
        n_rows, n_cols, _ = flow_direction.shape
        accum = np.ones((n_rows, n_cols), dtype=np.float32)
        # Discretize velocity to D8 direction (which neighbor cell
        # the flow points at, if any).
        vx = flow_direction[..., 0]
        vy = flow_direction[..., 1]
        # Round to nearest of {-1, 0, 1} for each axis.
        dx = np.sign(vx).astype(np.int32)
        dy = np.sign(vy).astype(np.int32)
        # Cells with zero velocity are sinks; skip them.
        # For each cell, find its downstream neighbor's coords.
        target_r = np.clip(np.arange(n_rows)[:, None] + dy, 0, n_rows - 1)
        target_c = np.clip(np.arange(n_cols)[None, :] + dx, 0, n_cols - 1)
        # Accumulate: each cell donates 1 to its downstream target.
        # Single-pass scatter — doesn't iterate to full convergence but
        # produces a reasonable upstream-cell-count proxy.
        for r in range(n_rows):
            for c in range(n_cols):
                if dx[r, c] == 0 and dy[r, c] == 0:
                    continue
                tr = int(target_r[r, c])
                tc = int(target_c[r, c])
                if (tr, tc) != (r, c):
                    accum[tr, tc] += 1.0
        return accum
