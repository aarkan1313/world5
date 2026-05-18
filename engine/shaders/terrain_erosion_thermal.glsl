#version 450

// W5 terrain erosion compute kernel — one thermal step (Musgrave/Kolb).
//
// Per spec 19 + Phase 5.7.a. Angle-of-repose-driven slope diffusion.
// For each cell, find the 4-cardinal neighbors that are downhill by
// more than `talus_height`; slump material toward them at `talus_rate`.
//
// The Python reference (pipeline/world5/kernels/erosion.py
// `_thermal_step`) does this as 4 cross-cell numpy ops. We can't do
// cross-cell writes safely in a single compute dispatch, so we use a
// READ-MIRROR pattern: each cell computes its own NEW height by:
//   - subtracting its own slump (talus_rate * sum_of_downhill_excesses)
//   - adding incoming slump from neighbors (each neighbor's excess
//     toward me, computed by reading their height and comparing to mine)
// This produces the same final state as the Python's per-cell deduct +
// per-neighbor addition because the math is symmetric.
//
// Output buffer is `height_out` (separate from `height_in`) to avoid
// read-while-write hazards. Caller ping-pongs.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant, std430) uniform Params {
    uint  grid_n;
    float talus_height;     // tan(angle_of_repose) * cell_size
    float talus_rate;       // 0..1 fraction of excess moved per step
    float _pad0;
} params;

layout(set = 0, binding = 0, std430) restrict readonly buffer HeightIn {
    float v[];
} height_in;

layout(set = 0, binding = 1, std430) restrict writeonly buffer HeightOut {
    float v[];
} height_out;

uint cell_idx(uint x, uint y, uint n) {
    return y * n + x;
}

void main() {
    uvec2 gid = gl_GlobalInvocationID.xy;
    uint n = params.grid_n;
    if (gid.x >= n || gid.y >= n) return;

    float h_self = height_in.v[cell_idx(gid.x, gid.y, n)];

    // My height vs each 4-neighbor. Positive delta = neighbor is BELOW me
    // (so material flows from me toward that neighbor).
    // Boundary: neighbor=self => delta=0 (no slump across world edge).
    float h_l = (gid.x > 0u)     ? height_in.v[cell_idx(gid.x - 1u, gid.y, n)] : h_self;
    float h_r = (gid.x + 1u < n) ? height_in.v[cell_idx(gid.x + 1u, gid.y, n)] : h_self;
    float h_u = (gid.y > 0u)     ? height_in.v[cell_idx(gid.x, gid.y - 1u, n)] : h_self;
    float h_d = (gid.y + 1u < n) ? height_in.v[cell_idx(gid.x, gid.y + 1u, n)] : h_self;

    // Excess above talus threshold for each downhill direction.
    float excess_to_l = max(0.0, (h_self - h_l) - params.talus_height);
    float excess_to_r = max(0.0, (h_self - h_r) - params.talus_height);
    float excess_to_u = max(0.0, (h_self - h_u) - params.talus_height);
    float excess_to_d = max(0.0, (h_self - h_d) - params.talus_height);
    float my_total_loss = (excess_to_l + excess_to_r + excess_to_u + excess_to_d) * params.talus_rate;

    // Incoming slump: for each neighbor, the excess they're shedding
    // TOWARD ME (= excess above talus, in the direction of this cell).
    // Mirror of the above formula computed from the neighbor's perspective.
    float in_from_l = (gid.x > 0u)     ? max(0.0, (h_l - h_self) - params.talus_height) : 0.0;
    float in_from_r = (gid.x + 1u < n) ? max(0.0, (h_r - h_self) - params.talus_height) : 0.0;
    float in_from_u = (gid.y > 0u)     ? max(0.0, (h_u - h_self) - params.talus_height) : 0.0;
    float in_from_d = (gid.y + 1u < n) ? max(0.0, (h_d - h_self) - params.talus_height) : 0.0;
    float my_total_gain = (in_from_l + in_from_r + in_from_u + in_from_d) * params.talus_rate;

    height_out.v[cell_idx(gid.x, gid.y, n)] = h_self - my_total_loss + my_total_gain;
}
