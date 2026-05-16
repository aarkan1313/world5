# Spec: Audio Hooks

> Status: draft
> Tier: 1 (core)
> Depends on: 22_BIOME_CATALOG, 28_DECORATION
> Consumed by: consumer projects wiring spatial audio playback

## Purpose

**Engine ships ZERO audio assets.** What it ships is an audio-tag
manifest: each biome / decoration zone / specific decoration subject
emits an opaque audio tag (e.g. `"ambient/forest_dense"`,
`"point/waterfall"`, `"loop/wind_high_altitude"`). Consumer projects
map tags to their own `.ogg` / `.wav` files and wire spatial-audio
playback via Godot's `AudioStreamPlayer3D`.

Per inventory decision (Block 4 of W5 plan): smaller engine surface;
consumer gets full freedom over audio direction without engine bloat.

## Non-goals

- Bundling audio files (engine has NONE)
- Realtime audio synthesis
- Spatial-audio runtime (Godot's `AudioStreamPlayer3D` is what
  consumers use)
- Music selection / dynamic music (consumer)
- Voice / dialogue systems (consumer)

## V1 feature set

Two layers:

### 1. Tag manifest

`worlds/<world>/audio_tags.json`:

```json
{
  "schema_version": 1,
  "biome_ambient": {
    "alpine":  "ambient/alpine_high_altitude",
    "wetland": "ambient/wetland_swampy"
  },
  "zone_ambient": [
    { "zone_name": "altar_grove", "tag": "ambient/eerie_grove" }
  ],
  "decoration_point_sources": [
    { "mesh_id": "structures/waterfall_01", "tag": "point/waterfall_loop" },
    { "mesh_id": "props/campfire_01", "tag": "point/fire_crackle_loop" }
  ]
  // SA-M4.7: mesh_id format = "<category>/<name>", matching the LPSTR
  // strings stored in spec 28 decoration blob's mesh_id_table and
  // spec 27's subjects_3d/<category>/<name>/ convention. Audio hooks
  // looks up by this string at runtime.
}
```

### 2. Runtime publisher (engine side)

```gdscript
class_name AudioHooksWorld extends Node
# Reads audio_tags.json + emits AudioEvent signals as the camera
# moves through biomes / enters zones / passes near decoration

signal biome_changed(biome_name: String, tag: String)
signal zone_entered(zone_name: String, tag: String)
signal zone_exited(zone_name: String, tag: String)
signal point_source_added(world_xz: Vector2, tag: String, source_id: int)
signal point_source_removed(source_id: int)

func get_current_biome_tag() -> String
func get_active_zone_tags() -> PackedStringArray
func get_resident_point_sources() -> Array[Dictionary]
```

Consumer subscribes to signals, instantiates their own
`AudioStreamPlayer3D` nodes with appropriate streams, attaches to
the right transform, manages lifecycle.

## Tag naming convention

`<type>/<descriptor>`:
- `ambient/` — looping environmental ambience (biome / zone level)
- `loop/` — long-form looping sources (wind, river current at
  distance)
- `point/` — short-loop point sources (campfire, waterfall, mechanism)
- `oneshot/` — single-play events (player triggers, runtime
  deformation thuds)

Tag is opaque to W5; engine doesn't interpret content. Consumer's
audio-bank lookup table maps tag → audio file.

## Canonical tag registry (SA-S4.6 / audit S5 fix)

The canonical list of tags any W5 system may emit. Every consumer's
audio_bank.json must cover this set or accept silent fallback.
Emitting specs add to this list when they introduce new tags.

### `ambient/` (biome ambient)
Emitted by: spec 22 biome catalog (per-biome `audio_tag` field)
- `ambient/alpine_high_altitude`, `ambient/wetland_swampy`,
  `ambient/forest_dense`, `ambient/desert_arid`,
  `ambient/coastal_breeze` (catalog of 5-10 stock; world authors
  pick + extend)

### `ambient/` (zone ambient)
Emitted by: spec 28 decoration zones (per-zone `audio_tag`)
- `ambient/eerie_grove`, `ambient/altar_grove`,
  `ambient/cave_drip` (per-world authored)

### `ambient/` (weather-driven)
Emitted by: spec 36 weather
- `ambient/rain_light`, `ambient/rain_heavy`, `ambient/rain_storm`
- `ambient/snow_light`, `ambient/snow_heavy`, `ambient/snow_blizzard`

### `loop/` (long-form loops)
Emitted by: spec 36 weather (wind), spec 35 water
- `loop/wind_low`, `loop/wind_high`, `loop/river_distant`,
  `loop/waterfall_distant`

### `point/` (short-loop point sources)
Emitted by: spec 28 decoration (per-decoration `audio_tag`)
- `point/waterfall_loop`, `point/fire_crackle_loop`,
  `point/mechanism_idle`

### `oneshot/` (single-play events)
Emitted by: spec 38 deformation (per-profile `audio_tag`)
- `oneshot/impact_small`, `oneshot/explosion_medium`,
  `oneshot/arcane_zap`, `oneshot/footstep_grass`,
  `oneshot/footstep_stone`

### Cave-specific (when caves ship)
Emitted by: spec 37 caves
- `ambient/cave_drip`, `ambient/cave_wind`, `loop/cave_water_drip`

### World contract preflight
Validates that every tag a world bundle EMITS via its catalog/zones/
decoration/etc. is in this registry. Validates that consumer's
audio_bank.json (if shipped) covers every tag the world bundle emits.

## Producer / consumer contract

- **Produces**: `audio_tags.json` manifest at offline-bake time;
  `AudioEvent` signals at runtime
- **Consumes**: biome catalog, decoration zones, decoration
  runtime (for point-source discovery)

## Dependencies

- `22_BIOME_CATALOG` (per-biome ambient tags)
- `28_DECORATION` (per-decoration point-source tags + zone tags)
- (Future) `36_WEATHER` may emit weather-driven tags
  (`ambient/storm`, `loop/rain_heavy`)

## Quality bar

- Tag manifest load < 50ms
- Signal latency on biome cross / zone enter: ≤ 100ms
- Point source events emitted in residency order (closest first)
- World contract validates audio_tags.json schema + cross-refs
  (every tag reference points at a real biome / zone / decoration ID)
- gut coverage of signal emission

## Discoverability

- **Entry point**: `AudioHooksWorld` scene component
- **Schema**: `engine/resources/schemas/audio_tags.schema.json`
- **Validator / preflight**: world contract validates manifest +
  cross-refs
- **Example**: `engine/examples/audio_hooks_example.tscn` shows the
  signal subscriptions + a consumer-side stub that logs tag changes
  (NO audio files; the consumer is responsible for hooking those up)
- **Deterministic outputs**: yes — tag manifest is static + signals
  fire deterministically given camera position

## Open questions

- **Distance + falloff for point sources**: consumer concern; tag
  manifest could optionally include suggested `max_distance_m` per
  source class. Schema slot only in v1.
- **Music selection**: completely out of scope; consumer plugs in
  their own music system.
- **Reverb zones**: consumer concern; engine could optionally publish
  "interior" tags for caves / buildings. Schema slot for a future
  reverb-hook system.
- **Wind / weather tags**: when weather spec ships, wind direction +
  intensity may drive `loop/wind_*` tags. Schema slot reserved.

## References

- W4 had no audio system (inventory decision); this is a W5-native
  contract designed to be cheap engine-side + flexible consumer-side
- Common patterns from indie + AAA: spatial audio via tag-event
  signals is the Wwise / FMOD adapter pattern compressed into a
  simple Godot-native contract

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-self-audit (SA-S4.6 / audit S5). Added Canonical
  tag registry — spec 34 owns the cross-system tag list. Every
  emitting spec contributes; world contract validates consumer's
  audio_bank.json covers the world's emitted tags.
