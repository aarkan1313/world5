#version 450

// W5 terrain page generator (Phase 4.2)
//
// Generates a heightmap page on the GPU. Output is a float32 storage
// buffer (row-major, grid_n by grid_n). Backend reads back to CPU
// and/or copies to a Texture2DRD per the request's capabilities.
//
// Same kernel math must match the Python NoiseStackKernel reference
// within 1e-3 m tolerance.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant, std430) uniform Params {
    vec2  world_origin;    // page origin in world meters
    float extent_m;        // page side length in meters
    uint  grid_n;          // samples per side
    uint  seed;
    uint  octaves;         // fBm octaves (typically 4-8)
    float frequency;       // base frequency in cycles/meter
    float lacunarity;      // freq multiplier per octave (typ 2.0)
    float gain;            // amplitude multiplier per octave (typ 0.5)
    float amplitude;       // base amplitude in meters (typ 50.0)
    uint  _pad0;           // 16-byte alignment pad
    uint  _pad1;
} params;

layout(set = 0, binding = 0, std430) restrict writeonly buffer HeightOut {
    float height[];
} height_out;

// --- Hash + value-noise helpers (must match Python reference) ---

// 32-bit integer hash (Wang). Same algorithm in Python.
uint hash_u32(uint x) {
    x = (x ^ 61u) ^ (x >> 16);
    x = x * 9u;
    x = x ^ (x >> 4);
    x = x * 0x27d4eb2du;
    x = x ^ (x >> 15);
    return x;
}

// 2D hash on integer cell coords plus seed -> [0,1) float
float hash2i(ivec2 cell, uint seed) {
    uint h = hash_u32(uint(cell.x) ^ hash_u32(uint(cell.y) ^ hash_u32(seed)));
    return float(h & 0x00FFFFFFu) / float(0x01000000u);
}

// Value noise: bilinearly-interpolated hash on a unit grid.
float value_noise2(vec2 p, uint seed) {
    vec2 pf_full = floor(p);
    ivec2 pi = ivec2(pf_full);
    vec2 pf = p - pf_full;
    // Smoothstep ease so derivative is continuous
    vec2 w = pf * pf * (3.0 - 2.0 * pf);
    float a = hash2i(pi + ivec2(0, 0), seed);
    float b = hash2i(pi + ivec2(1, 0), seed);
    float c = hash2i(pi + ivec2(0, 1), seed);
    float d = hash2i(pi + ivec2(1, 1), seed);
    float ab = mix(a, b, w.x);
    float cd = mix(c, d, w.x);
    return mix(ab, cd, w.y);
}

// fBm: octave-summed value noise. Output range roughly [-1, 1] after
// normalization by amplitude sum.
float fbm(vec2 p, uint octaves, float frequency, float lacunarity,
          float gain, uint seed) {
    float sum = 0.0;
    float amp = 1.0;
    float freq = frequency;
    float norm = 0.0;
    for (uint i = 0u; i < octaves; i = i + 1u) {
        // Center value noise around 0 by mapping [0,1) to [-1,1)
        sum = sum + amp * (value_noise2(p * freq, seed + i * 1013u) * 2.0 - 1.0);
        norm = norm + amp;
        amp = amp * gain;
        freq = freq * lacunarity;
    }
    return sum / norm;
}

void main() {
    uvec2 gid = gl_GlobalInvocationID.xy;
    if (gid.x >= params.grid_n || gid.y >= params.grid_n) return;

    // World position of this sample. Cell-aligned at the page origin;
    // last sample at origin + extent.
    float cell = params.extent_m / float(max(params.grid_n - 1u, 1u));
    vec2 world_xz = params.world_origin + vec2(gid) * cell;

    float h = params.amplitude * fbm(
        world_xz,
        params.octaves,
        params.frequency,
        params.lacunarity,
        params.gain,
        params.seed
    );

    uint idx = gid.y * params.grid_n + gid.x;
    height_out.height[idx] = h;
}
