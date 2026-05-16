# Spec: Atmosphere

> Status: draft
> Tier: 1 (core)
> Depends on: 01_MODULE_LAYOUT, 13_QUALITY_TIERS, 21_TERRAIN_RENDERER
> Consumed by: terrain renderer (sky + fog + haze), lighting (sun
> direction), weather (uses atmosphere schema), every visible scene

## Purpose

Sky + sun + fog + distance haze + time-of-day + volumetric clouds +
Bruneton-style atmospheric scattering. The visual envelope around the
world.

W4.1 had `AtmosphereController.gd` with 7 named profiles using
Godot's built-in procedural sky. Carry over the controller pattern;
upgrade the SKY itself to Bruneton-style atmospheric scattering +
volumetric clouds for v1.

This makes v1 atmosphere significantly more ambitious than W4 — but
per pillar 1, sky + clouds + sun-scattering are the biggest visual
lift after lighting. Worth the work.

## Non-goals

- Weather effects (rain, snow, wind) — Tier 2 spec 36 owns runtime
  weather; this spec defines the schema atmosphere consumes
- God-rays / shafts of light (Godot 4 volumetric fog handles most;
  no separate spec)
- HDR sky capture / image-based lighting (defer; procedural sky
  drives lighting + reflections via Godot's Sky resource)
- Night sky detail (stars, moon, milky way) — defer to a later sprint
  or schema slot only
- Galactic / non-Earth skies — out of scope for W5 v1

## V1 feature set (per frame budget X_FRAME_BUDGET)

Tier-gated per `X_FRAME_BUDGET.md`. Atmosphere gets 0.5 ms at high
tier (sky shader only); volumetric clouds (1.5 ms) move to ultra tier
default-on; clouds at high tier are opt-in per scene.

1. **Bruneton-style atmospheric scattering sky shader** (≤ 0.5 ms
   at high; required v1)
   - Sun-position-aware atmosphere color (real Rayleigh + Mie)
   - Proper horizon gradient + sunset/sunrise color shifts
   - Per-time-of-day sun position (driven by `time_of_day` 0-24)
   - Replaces Godot's built-in procedural sky for v1
2. **Volumetric clouds** (≤ 1.5 ms at ultra; default OFF at high;
   opt-in via profile flag)
   - Raymarched noise-field cloud shader (3D Worley + Perlin)
   - Per-profile cloud type (clear / scattered / overcast / storm)
   - Density / coverage / altitude per profile
   - Lit by sun direction (matches scattering sky)
   - **High tier default uses flat sky color matching scattering;
     clouds engage when consumer opts in or selects ultra tier.**
   - Audit O1 + O5 + S2: clouds + SDFGI together at high blow the
     frame budget. Solution: tier-gate clouds to ultra; high tier
     ships Bruneton sky only.
3. **Sun + WorldEnvironment**
   - Directional light driven by atmosphere profile
   - ACES tonemap (carry from W4)
4. **Depth fog + terrain haze**
   - W4 patterns: depth fog (volumetric, near-range) +
     terrain-only haze (far-range, hides hidden-buffer pop-in)
   - Per-tier fog/haze distances (atmosphere consumes quality_tiers)
5. **Time-of-day API**
   - `apply_time_of_day(hour: float)` interpolates dawn → noon →
     dusk over the same profile
   - Optional smooth transitions (sunrise over N seconds)
6. **Profile catalog**
   - Carry over W4's 7 profiles as starting set; expand:
     `clear_dawn`, `clear_noon`, `clear_dusk`, `clear_night`,
     `overcast_noon`, `scattered_noon`, `storm_noon`
   - Per-quality-tier variants (low tier disables Bruneton AND
     clouds, uses flat gradient; medium uses Bruneton no clouds;
     high uses Bruneton no clouds; ultra adds clouds)

## Fog override stack (SA-S4.9)

Atmosphere owns the base fog (per profile). Other systems can push
transient overrides (water on submerge, dense weather, magical
effects). Stack-based:

```gdscript
func push_fog_override(profile_override: Dictionary, owner: String) -> int:
    """Push a fog override; returns handle for release. Owner is
    a system name for diagnostics."""
func release_fog_override(handle: int) -> void:
    """Release this override; next-most-recent (or base) becomes active."""
```

Spec 35 water calls `push_fog_override` on camera submerge with the
underwater profile; releases on surface. Spec 36 weather may push
storm-density override. Atmosphere base profile is always the
fallback.

## Public API (skeleton)

```gdscript
class_name AtmosphereController extends Node3D
# Autoload at /root/Atmosphere (or instanced per-scene)

@export var current_profile: String = "clear_noon"
@export var time_of_day: float = 12.0  # 0-24 hours

func apply_profile(name: String) -> void
func get_profile(name: String) -> Dictionary
func apply_time_of_day(hour: float, transition_s: float = 0.0) -> void
func get_sun_direction() -> Vector3
func get_sun_color() -> Color
func get_ambient_color() -> Color

signal profile_changed(name: String)
signal time_of_day_changed(hour: float)
```

### Profile shape

`engine/resources/atmosphere_profiles.json`:

```json
{
  "schema_version": 1,
  "profiles": {
    "clear_noon": {
      "sky_type": "bruneton_scattering",
      "rayleigh_density": 1.0,
      "mie_density": 1.0,
      "sun_intensity": 1.0,
      "sun_color_tint": [1.0, 0.96, 0.88],
      "time_of_day_default": 12.0,
      "cloud_layer": {
        "type": "scattered",
        "coverage": 0.3,
        "altitude_m": 2500,
        "thickness_m": 800,
        "density_mult": 1.0,
        "force_render_at_tier": "ultra"
        // SA-M4.1: cloud_layer is always present in schema (authors
        // define it). RUNTIME RENDERS only at ultra+ OR when this
        // profile has "force_render_at_tier" set ≤ current tier.
        // At high tier without force_render, clouds use a cheap
        // flat sky color matching the scattering.
      },
      "fog": {
        "depth_fog_enabled": true,
        "depth_fog_start_m": 200,
        "depth_fog_end_m": 1500,
        "depth_fog_color": [0.6, 0.7, 0.8],
        "terrain_haze_enabled": true,
        "terrain_haze_start_m": 800,
        "terrain_haze_end_m": 3500,
        "terrain_haze_strength": 0.35
      },
      "tonemap": "aces",
      "ambient_light_energy": 0.55
    },
    "storm_noon": { /* ... */ },
    "clear_dawn": { /* ... */ }
  }
}
```

## Bruneton scattering — what + why

Realistic sky color: Rayleigh scattering (blue from short-wavelength
scatter) + Mie scattering (sun halo from larger particles). Sun
position drives the look — at noon, blue overhead, white horizon; at
sunset, deep orange near sun, indigo opposite. Mathematically
correct, looks like real sky.

Godot 4 has a `Sky` resource taking a sky shader. v1 implements the
Bruneton model as a custom sky shader. Pre-computed transmittance +
in-scattering tables uploaded as `Texture2D` uniforms for runtime
performance. Reference implementations exist (Bruneton 2008 paper +
publicly available shaders in UE / Unity ports).

## Volumetric clouds — what + why

Raymarched cloud-density field (3D Worley + Perlin noise). Lit by
sun direction (matches scattering). Per-profile cloud type changes
density / coverage / altitude. Renders as a transparent overlay above
terrain.

Godot 4 doesn't ship volumetric clouds; v1 implements as a custom
fragment shader raymarching a cloud-density 3D texture. Performance
cost: ~1-2ms per frame at high tier (gate via quality_tier:
`low`/`medium` disable clouds, render flat sky color instead).

## Weather schema (forward-compat) — RESOLVED audit M8

Atmosphere defines the schema slots weather (spec 36) consumes.
**Field names aligned with spec 36's WeatherController API**:

| Atmosphere schema | Weather (spec 36) publishes |
|---|---|
| `wind_direction` (Vector3) | `Weather.get_wind_direction()` |
| `wind_strength` (float 0-1) | `Weather.get_wind_strength()` |
| `rain_intensity` (float 0-1) | weather_state `rain_intensity` |
| `snow_intensity` (float 0-1) | weather_state `snow_intensity` |
| `visibility_m` (float, default 5000) | derived: high precipitation drops it |

The earlier draft used `precipitation_type` + `precipitation_intensity`
(combined enum + value); audit M8 found spec 36 instead publishes
separate `rain_intensity` + `snow_intensity` (different particle
systems, can co-occur in transition weather). Atmosphere schema
updated to match — separate intensities. `precipitation_type` removed
as redundant (read directly from which intensity is nonzero).

v1 atmosphere doesn't animate these (weather drives); the schema
exists so spec 36 reads/writes uniformly without atmosphere refactor.

## Producer / consumer contract

- **Produces**: rendered sky + clouds + sun direction + ambient color;
  fog uniforms; current weather schema state
- **Consumes**: profile config; time_of_day; quality_tier knobs;
  optional weather state input (from spec 36 once it ships)

## Dependencies

- `01_MODULE_LAYOUT` (placement at `engine/scripts/atmosphere/`)
- `13_QUALITY_TIERS` (per-tier cloud + scattering gating)
- `21_TERRAIN_RENDERER` (consumes fog uniforms; rendered together)

## Quality bar

- Sky shader: ≤ 0.5 ms per frame at `high` tier (authorized by
  `X_FRAME_BUDGET.md`)
- Volumetric clouds: ≤ 1.5 ms at `ultra` tier; OFF at `high` default
  (opt-in via profile)
- Profile transition: smooth, no pop, ≤ 1s default
- Visual: sky reads as "real sky" — sunsets are gorgeous, daytime is
  natural; clouds (at ultra or opt-in) have volume
- Profile schema validation in world contract (preflight)
- GPU/CPU thread compliance verified per spec 08a
- pytest coverage of profile loader + time-of-day math; gut coverage
  of controller behavior

## Discoverability

- **Entry point**: `Atmosphere.apply_profile(name)` autoload
- **Schema**: `engine/resources/schemas/atmosphere_profile.schema.json`
- **Validator / preflight**: world contract validates per-world
  profile overrides
- **Example**: `engine/examples/atmosphere_profile_example.tscn`
  shows all profiles in a single test scene
- **Deterministic outputs**: yes — same profile + same time-of-day
  → same uniforms (shaders are GPU-deterministic)

## Open questions

- **Cloud shadows on terrain**: clouds occluding sun is realistic but
  expensive (extra shadow map / volumetric shadow). Defer to
  measurement.
- **Multi-layer clouds**: high cirrus + low cumulus mixed. Single
  cloud layer in v1 schema; multi-layer is a schema extension.
- **Night sky stars / moon**: schema slots reserved; rendering
  deferred unless a consumer demands it (probably yes once a "night
  walk" demo is built).
- **Reflection probes from sky**: should sky color drive ambient
  reflection probes? Godot 4 does this via `SkyMaterial`; v1 leverages
  same automatically.
- **Bruneton implementation choice**: hand-port the paper vs adapt an
  existing open-source shader. Adapting is faster but quality varies;
  hand-port is best fidelity. Decide during plan doc.

## References

- W4 `scripts/atmosphere/AtmosphereController.gd` — proven controller
  pattern + profile catalog approach
- Bruneton 2008 "Precomputed Atmospheric Scattering" paper
- Schneider et al. "Real-Time Volumetric Cloudscapes" (Horizon: Zero
  Dawn) — volumetric cloud architecture
- WISHLIST "Cloud + atmospheric scattering volumetrics" entry

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-audit (S2, O1, O5, M8). Volumetric clouds
  tier-gated to ultra; high tier ships sky shader only (0.5 ms vs
  prior 1.0 ms + 2.0 ms clouds). Cleared frame budget conflict with
  SDFGI + clouds + planar reflection stack at high. Weather schema
  field names aligned with spec 36's WeatherController API
  (separate `rain_intensity` + `snow_intensity` instead of combined
  `precipitation_type`/`_intensity`).
