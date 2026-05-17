## W5 StreamingBudget — shared accountant for streamable resources.
##
## Per spec 10. Every async system publishes its current usage;
## accountant aggregates + flags overruns. Budget keys: active_tris,
## resident_texture_mb, draw_calls, active_jobs, cpu_pages, gpu_pages,
## asset_cache_mb.
##
## Autoload at /root/StreamingBudget (registered Phase 2.12).

class_name StreamingBudget extends Node

const SYSTEM_NAME: String = "streaming_budget"

# Budget keys (per spec 10 + spec 13 quality_tiers.json)
const KEYS: PackedStringArray = [
	"active_tris",
	"resident_texture_mb",
	"draw_calls",
	"active_jobs",
	"cpu_pages",
	"gpu_pages",
	"asset_cache_mb",
]

# system_name → {key: value, ...}
var _usage_by_system: Dictionary = {}

# Per-system publish rate limiting (timestamp ms of last publish)
var _last_publish_ms: Dictionary = {}
const _RATE_LIMIT_MS: int = 100

# History ring buffer for diagnostics
var _history: Array = []
const _HISTORY_MAX_SIZE: int = 600  # 60s @ 10Hz

# Last over-budget warning timestamp (avoid log spam)
var _last_over_warn_ms: int = 0
const _OVER_WARN_INTERVAL_MS: int = 5000


# --- publish ---

## A system reports its current usage. Missing keys default to 0.
## Overwrites any prior publish from same system_name.
## Rate-limited internally to once per 100ms per system.
func publish(system_name: String, usage: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	var last: int = _last_publish_ms.get(system_name, 0)
	if (now - last) < _RATE_LIMIT_MS:
		# Coalesce: keep the most recent reading silently
		_usage_by_system[system_name] = _normalize(usage)
		return
	_last_publish_ms[system_name] = now
	_usage_by_system[system_name] = _normalize(usage)
	_record_history(now)
	_maybe_warn_over_budget(now)


## Called when a system tears down (decoration unload, etc.).
func clear(system_name: String) -> void:
	_usage_by_system.erase(system_name)
	_last_publish_ms.erase(system_name)


# --- queries ---

func get_system_usage(system_name: String) -> Dictionary:
	return _usage_by_system.get(system_name, _zero_usage())


func get_total_usage() -> Dictionary:
	var totals := _zero_usage()
	for system_name in _usage_by_system.keys():
		for key in KEYS:
			totals[key] += _usage_by_system[system_name].get(key, 0)
	return totals


func get_budget() -> Dictionary:
	## Reads from QualityTiers.get_current()'s streaming_budget_* keys.
	var tier := QualityTiers.get_current()
	if tier.is_empty():
		Log.warn(SYSTEM_NAME, "no current tier; using zero budgets")
		return _zero_usage()
	var budget := {}
	for key in KEYS:
		budget[key] = tier.get("streaming_budget_" + key, 0)
	return budget


func get_headroom() -> Dictionary:
	var budget := get_budget()
	var total := get_total_usage()
	var headroom := {}
	for key in KEYS:
		headroom[key] = budget[key] - total[key]
	return headroom


func is_over_budget() -> bool:
	var headroom := get_headroom()
	for key in KEYS:
		if headroom[key] < 0:
			return true
	return false


## Returns top N publishing systems by absolute contribution to
## `budget_key`. Per SA-S2.2 (replaces vague get_violators).
func get_top_publishers(budget_key: String, n: int = 5) -> Array:
	var entries: Array = []
	for system_name in _usage_by_system.keys():
		var value: int = _usage_by_system[system_name].get(budget_key, 0)
		entries.append({"system": system_name, "value": value})
	entries.sort_custom(func(a, b): return a["value"] > b["value"])
	return entries.slice(0, n)


# --- diagnostics ---

func get_publishers() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _usage_by_system.keys():
		out.append(k)
	return out


func get_history(seconds: float = 60.0) -> Array:
	var cutoff_ms := Time.get_ticks_msec() - int(seconds * 1000)
	var out: Array = []
	for snap in _history:
		if snap["ts_ms"] >= cutoff_ms:
			out.append(snap)
	return out


# --- Godot lifecycle ---

func _ready() -> void:
	Log.info(SYSTEM_NAME, "StreamingBudget ready")


# --- internals ---

func _zero_usage() -> Dictionary:
	var out := {}
	for k in KEYS:
		out[k] = 0
	return out


func _normalize(usage: Dictionary) -> Dictionary:
	## Ensure all KEYS present; missing → 0.
	var out := _zero_usage()
	for k in usage.keys():
		if k in KEYS:
			out[k] = usage[k]
	return out


func _record_history(now: int) -> void:
	_history.append({"ts_ms": now, "totals": get_total_usage()})
	if _history.size() > _HISTORY_MAX_SIZE:
		_history.pop_front()


func _maybe_warn_over_budget(now: int) -> void:
	if not is_over_budget():
		return
	if (now - _last_over_warn_ms) < _OVER_WARN_INTERVAL_MS:
		return
	_last_over_warn_ms = now
	var totals := get_total_usage()
	var budget := get_budget()
	var over_keys: Array = []
	for key in KEYS:
		if totals[key] > budget[key]:
			over_keys.append({"key": key, "usage": totals[key], "budget": budget[key]})
	Log.warn(SYSTEM_NAME, "over budget", {"over": over_keys})


## Test helper: clear all state.
func _reset() -> void:
	_usage_by_system.clear()
	_last_publish_ms.clear()
	_history.clear()
	_last_over_warn_ms = 0
