# Spec: Weather

> Status: draft
> Tier: 2 (world)
> Depends on: 22_BIOME_CATALOG, 30_ATMOSPHERE, 21_TERRAIN_RENDERER,
> 29_FOLIAGE, 34_AUDIO_HOOKS
> Consumed by: terrain renderer (wetness/snow shader), foliage (wind
> shader strength), audio hooks (weather-driven tags), consumer
> (gameplay-side weather state)

## Purpose

Visible weather effects in v1: rain + snow + wind. Engine renders the
weather; consumer wires gameplay impact (slippery surfaces, reduced
visibility for combat, etc.).

Per inventory + your scope decision: **visual effects only in v1, no
gameplay hooks**. Same pattern as audio hooks — engine provides the
runtime state + signals, consumer reacts.

Climate (regional gating: which biome gets which weather) reads from
biome catalog spec 22's per-XZ computed climate (post-audit C5: this
is per-XZ via `climate_base` + `climate_rules`, not flat per biome).
The computed values respond to elevation lapse, distance-to-water
moisture, and slope/aspect wind exposure — so the same biome at
different elevations or distances gets different weather.

## Non-goals

- Gameplay impact (slippery, visibility, hypothermia) — consumer
  territory
- Long-term seasonal cycles (consumer territory; can drive via
  scripted profile changes)
- Tornados / hurricanes / extreme weather events (defer; could be
  Tier 4 spec)
- Snow accumulation as buildup over time (snow visible on terrain
  per current weather state — yes; long-term accumulation that
  persists across sessions — no, that's persistence's job)
- Wetness as authored "this is a wet biome" (handled by biome catalog
  climate.moisture; weather adds temporary on-top of static)

## V1 weather effects

### Rain
- Particle system (GPU particles) tied to camera; spawns in
  hemisphere ahead of camera
- Per-particle wind influence (drifts with current wind direction +
  strength)
- Audio tag emission: `ambient/rain_light` / `ambient/rain_heavy` /
  `ambient/rain_storm` per intensity
- Terrain wetness shader overlay (albedo darken + roughness drop;
  same shader hook used by water shoreline)
- Foliage shader: leaves wobble more (wind strength multiplier
  delivered to foliage shader)

### Snow
- Particle system similar to rain
- Slower fall, drift more in wind
- Audio tag: `ambient/snow_light` / `ambient/snow_heavy` /
  `ambient/snow_blizzard`
- Terrain shader: snow visibility (per-fragment 0..1) layered on top
  of biome materials; based on current weather state, not accumulation
- Foliage: leaves get snow-dusted shader override at high intensity

### Wind
- Always-on; intensity varies by atmosphere profile (storm has
  high wind, clear has low)
- World-anchored direction + strength uniforms (drive foliage wind
  shader spec 29, rain/snow particle drift)
- No particle effect for wind itself; visible via foliage sway + rain
  drift

### Visibility / fog tie-in
- Rain at heavy intensity bumps atmosphere fog density (transient
  override); reverts when rain stops
- Same for snow blizzard

## Regional gating

Per-XZ climate from spec 22's `climate_base` + `climate_rules`
(audit C5):

```
climate = biome_catalog.sample_climate_at(world_xz)
  // returns {temperature_c, moisture, wind_exposure} after applying
  // lapse rate, water-distance, slope/aspect rules; per-XZ resolution
weather_state = atmosphere.current_weather_profile.evaluate(climate)
```

Examples:
- Alpine peak at 1400m in `clear_noon` → -0.6 C (lapse from 1000m
  ref), no rain, gusty wind (exposed ridge): light snow flurries
  possible in `storm_noon`, definitely blizzard
- Alpine valley at 700m, near a lake, in `storm_noon` → +6.4 C
  (lapse warms valley), high moisture (lake proximity), low wind
  (valley shadow): heavy rain not snow
- Wetland biome at 50m, far from coast, in `storm_noon` → +20 C
  base, moderate moisture, low wind: rain

Crossfade smoothly across XZ (climate is already smooth from kernel
composer).

## Weather profile catalog

Atmosphere spec 30 ships profiles (clear_noon, storm_noon, etc).
Weather profiles are a sibling schema:

`engine/resources/weather_profiles.json`:

```json
{
  "schema_version": 1,
  "profiles": {
    "clear": {
      "rain_intensity_base": 0.0,
      "snow_intensity_base": 0.0,
      "wind_strength_base": 0.2,
      "applies_to_atmosphere": ["clear_noon", "clear_dawn", "clear_dusk", "clear_night"]
    },
    "overcast": {
      "rain_intensity_base": 0.0,
      "snow_intensity_base": 0.0,
      "wind_strength_base": 0.4,
      "applies_to_atmosphere": ["overcast_noon", "scattered_noon"]
    },
    "storm": {
      "rain_intensity_base": 0.7,
      "snow_intensity_base": 0.0,
      "wind_strength_base": 0.8,
      "applies_to_atmosphere": ["storm_noon"]
    },
    "blizzard": {
      "rain_intensity_base": 0.0,
      "snow_intensity_base": 0.9,
      "wind_strength_base": 0.9,
      "applies_to_atmosphere": ["storm_noon"],
      "temperature_threshold_c": 0
    }
  }
}
```

The `temperature_threshold_c` means: if blended climate temp is below
threshold, blizzard wins over storm (snow replaces rain).

**Per-XZ behavior** (SA-M4.10): since spec 22 climate is now per-XZ,
`temperature_threshold_c` is evaluated PER-XZ at render time. A world
spanning lowland (15C) + alpine (-5C) renders rain on lowland AND
blizzard on alpine simultaneously. Both rain and snow particle
systems are always active at runtime; per-XZ climate controls which
has nonzero density at that location. Falls naturally out of the
per-XZ climate fix; documented for clarity.

Atmosphere profile change triggers weather profile reselection.
Crossfades over `transition_s` (default 5s).

## Public API (skeleton)

```gdscript
class_name WeatherController extends Node
# Autoload at /root/Weather

@export var current_profile: String = "clear"
@export var transition_s: float = 5.0

signal weather_changed(profile: String)
signal weather_state_updated(rain_intensity: float, snow_intensity: float, wind_strength: float)

func apply_profile(name: String) -> void
func get_state_at(world_xz: Vector2) -> Dictionary:
    """Returns {rain_intensity, snow_intensity, wind_strength, wind_direction}
    at this position, accounting for biome blend."""
func get_wind_direction() -> Vector3
func get_wind_strength() -> float
```

Audio hooks subscribe to `weather_state_updated`; emit appropriate
`ambient/rain_*` etc. tags.

## Producer / consumer contract

- **Produces**: particle effects rendered; wetness/snow shader uniforms;
  wind direction + strength uniforms; weather state signals for audio
  hooks + consumer
- **Consumes**: weather_profiles.json; biome catalog climate; current
  atmosphere profile; camera position for particle spawn

## Dependencies

- `22_BIOME_CATALOG` (climate fields for regional gating)
- `30_ATMOSPHERE` (current profile drives weather selection;
  atmosphere fog override for storm intensity)
- `21_TERRAIN_RENDERER` (wetness/snow shader hooks)
- `29_FOLIAGE` (wind strength multiplier delivered)
- `34_AUDIO_HOOKS` (weather state signals)

## Quality bar

- Particle GPU cost (rain at heavy intensity): ≤ 1.5ms p99 on high
  tier
- Wetness shader overlay: ≤ 0.3ms (samples one extra texture in
  terrain frag shader)
- Snow overlay: ≤ 0.3ms
- Wind uniforms: free (just uniform updates)
- Weather profile transition: smooth, ≤ 5s, no visible pop
- Visual: weather reads as weather; biome-specific (alpine snow vs
  wetland rain works visibly)
- World contract validates weather_profiles.json + cross-refs to
  atmosphere profiles

## Discoverability

- **Entry point**: `Weather.apply_profile(name)` autoload
- **Schema**: `engine/resources/schemas/weather_profile.schema.json`
- **Validator / preflight**: world contract validates profiles +
  cross-refs
- **Example**: `engine/examples/weather_example.tscn` cycles through
  all weather profiles in one scene
- **Deterministic outputs**: yes — profile + climate + position →
  same state

## Open questions

- **Storm transitions (clear → storm)**: should they ramp gradually
  (sky darkens before rain starts) or be ramped via atmosphere
  profile change (which already ramps over time-of-day transitions)?
  Probably the latter; weather doesn't drive atmosphere transitions,
  it follows them.
- **Per-region weather override**: can a world hand-author "this
  region is always foggy" regardless of climate? Schema slot for
  `weather_overrides` array (per-zone weather profile), like
  decoration zones. Defer.
- **Rain dripping from leaves / overhangs**: cool visual; complicates
  particle spawn. Defer to a polish sprint.
- **Indoor weather suppression**: when consumer's player enters
  shelter, weather particles should stop. Consumer-side concern
  (consumer publishes "player indoor" hint); engine respects.

## References

- W4 atmosphere had a `weather` schema slot but never built weather
- WISHLIST "Weather deepening" entry
- Crytek + RDR2 weather systems as visual reference

## Revision history

- 2026-05-16: initial draft
