## W5 quality tiers — engine-side resolver.
##
## Per spec 13. Reads engine/resources/quality_tiers.json. Provides
## load_config + get_tier + get_current + names. Mirror of
## pipeline/world5/quality_tiers.py.
##
## (Phase 2.3 lessons:
##  - Object.get(property) is a Godot builtin; static `get(...)` shadows
##    + parser fails. Renamed to get_tier(). Python keeps .get() —
##    no conflict.
##  - Object.load(path) is also a Godot builtin / Resource loader.
##    Renamed to load_config().)
##
## Cross-impl parity: tests/integration/test_quality_tiers_cross_impl.py
## (Python) + engine/tests/integration/test_quality_tiers_parity.gd
## (GDScript) exercise the same canonical config.
##
## Autoload at /root/QualityTiers (registered in Phase 2.12).

class_name QualityTiers extends Node

const SYSTEM_NAME: String = "quality_tiers"

# Tier names locked per spec 13 (post-audit S7: ultra_far → cinematic)
const TIER_NAMES: PackedStringArray = ["low", "medium", "high", "ultra", "cinematic"]
const DEFAULT_TIER: String = "high"

const _DEFAULT_CONFIG_PATH: String = "res://addons/world5/resources/quality_tiers.json"

# Module-level cache; reset via _reset_cache() in tests
static var _cache: Dictionary = {}
static var _cache_path: String = ""


## Load + parse quality_tiers.json. Cached for subsequent calls with
## the same path. Renamed from `load` to avoid shadowing
## Object.load() (Godot's Resource loader).
static func load_config(config_path: String = "") -> Dictionary:
	var path := config_path if config_path != "" else _DEFAULT_CONFIG_PATH
	if not _cache.is_empty() and _cache_path == path:
		return _cache
	if not FileAccess.file_exists(path):
		Log.error(SYSTEM_NAME, "config not found", {"path": path})
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		Log.error(SYSTEM_NAME, "cannot open config", {"path": path})
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("tiers"):
		Log.error(SYSTEM_NAME, "config missing 'tiers' key", {"path": path})
		return {}
	_cache = parsed["tiers"]
	_cache_path = path
	# Sanity check: every named tier exists
	var missing: Array = []
	for t in TIER_NAMES:
		if not _cache.has(t):
			missing.append(t)
	if not missing.is_empty():
		Log.warn(SYSTEM_NAME, "tier names missing from config", {"missing": missing})
	return _cache


## Return the dict for `tier_name`. Loads config on first call.
## Returns empty dict if tier unknown + logs error.
static func get_tier(tier_name: String = "") -> Dictionary:
	var tiers := load_config()
	var target := tier_name if tier_name != "" else _read_current_tier_name()
	if not tiers.has(target):
		Log.error(SYSTEM_NAME, "unknown tier", {"tier": target, "available": tiers.keys()})
		return {}
	return tiers[target]


## Return the current tier per ProjectSettings 'world5/quality_tier'
## (or DEFAULT_TIER).
static func get_current() -> Dictionary:
	return get_tier(_read_current_tier_name())


## Return the list of known tier names.
static func names() -> PackedStringArray:
	return TIER_NAMES


# --- internals ---

static func _read_current_tier_name() -> String:
	var tier: String = DEFAULT_TIER
	if ProjectSettings.has_setting("world5/quality_tier"):
		var v: Variant = ProjectSettings.get_setting("world5/quality_tier")
		if typeof(v) == TYPE_STRING and v in TIER_NAMES:
			tier = v
		else:
			Log.warn(SYSTEM_NAME, "invalid ProjectSettings world5/quality_tier; falling back",
				{"value": v, "default": DEFAULT_TIER})
	return tier


## Test helper: clear cache so load_config() re-reads.
static func _reset_cache() -> void:
	_cache = {}
	_cache_path = ""
