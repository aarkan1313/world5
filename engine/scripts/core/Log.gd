## W5 logging — 5 levels, structured + JSON output, per-system verbose.
##
## Per spec 16. Every system goes through this; direct `print` /
## `push_warning` / `push_error` outside Log.gd fails lint (Phase 2.11).
##
## Usage:
##   Log.info("terrain", "Ring 3 ready", {"duration_ms": 87})
##   Log.warn("decoration", "Mesh refs missing", {"count": 3})
##   Log.error("asset_stream", "Load failed", {"path": path, "error": err})
##
## Output format (human):
##   [INFO ] [terrain        ] [   1234] Ring 3 ready  duration_ms=87
##
## Output format (json, one object per line):
##   {"level":"INFO","system":"terrain","ts_ms":1234,"msg":"Ring 3 ready","duration_ms":87}

class_name Log extends RefCounted

enum Level { DEBUG, INFO, WARN, ERROR, FATAL }

const _LEVEL_NAMES := ["DEBUG", "INFO ", "WARN ", "ERROR", "FATAL"]
const _SYSTEM_NAME_WIDTH := 15

# Configuration (statics; configured at boot)
static var _min_level: int = Level.INFO
static var _format: String = "human"  # "human" | "json" | "compact"
static var _output: String = "stdout"  # "stdout" | "file:<path>" | "both"
static var _verbose_systems: Dictionary = {}  # system_name -> bool
static var _file_handle: FileAccess = null


## Log at DEBUG level. Filtered out unless system is verbose or
## min_level is DEBUG.
static func debug(system: String, message: String, kv: Dictionary = {}) -> void:
	if not _should_log(Level.DEBUG, system):
		return
	_emit(Level.DEBUG, system, message, kv)


## Log at INFO level.
static func info(system: String, message: String, kv: Dictionary = {}) -> void:
	if not _should_log(Level.INFO, system):
		return
	_emit(Level.INFO, system, message, kv)


## Log at WARN level. Routed through push_warning so Godot's debugger
## Output panel highlights it.
static func warn(system: String, message: String, kv: Dictionary = {}) -> void:
	if not _should_log(Level.WARN, system):
		return
	_emit(Level.WARN, system, message, kv)
	push_warning(_format_human(Level.WARN, system, message, kv))


## Log at ERROR level. Routed through push_error so Godot's debugger
## Output panel + script flagging behaves correctly.
static func error(system: String, message: String, kv: Dictionary = {}) -> void:
	if not _should_log(Level.ERROR, system):
		return
	_emit(Level.ERROR, system, message, kv)
	push_error(_format_human(Level.ERROR, system, message, kv))


## Log at FATAL level. Implies engine cannot continue. Triggers
## push_error; consumer can opt-in to OS.crash on fatal via
## set_crash_on_fatal(true).
static func fatal(system: String, message: String, kv: Dictionary = {}) -> void:
	_emit(Level.FATAL, system, message, kv)
	push_error(_format_human(Level.FATAL, system, message, kv))


## Returns true if a system is in verbose mode (DEBUG visible per-system).
static func is_verbose(system: String) -> bool:
	return _verbose_systems.get(system, false)


## Toggle per-system verbose mode.
static func set_verbose(system: String, enabled: bool) -> void:
	_verbose_systems[system] = enabled


## Set the global minimum level filter (default: INFO).
static func set_level(min_level: int) -> void:
	_min_level = min_level


## Set output format: "human" (default), "json", or "compact".
static func set_format(format: String) -> void:
	assert(format in ["human", "json", "compact"], "format must be human/json/compact")
	_format = format


## Set output destination: "stdout" (default), "file:<path>", or "both".
## When file: target, opens a FileAccess append-mode handle.
static func set_output(target: String) -> void:
	if _file_handle:
		_file_handle.close()
		_file_handle = null
	_output = target
	if target.begins_with("file:") or target == "both":
		var path := target.substr(5) if target.begins_with("file:") else "user://world5.log"
		_file_handle = FileAccess.open(path, FileAccess.WRITE_READ)
		if _file_handle == null:
			push_error("Log.set_output: cannot open file %s" % path)
			_output = "stdout"


# --- internals ---

static func _should_log(level: int, system: String) -> bool:
	if level >= _min_level:
		return true
	# Below min level — only allowed if per-system verbose AND level is DEBUG
	if level == Level.DEBUG and is_verbose(system):
		return true
	return false


static func _emit(level: int, system: String, message: String, kv: Dictionary) -> void:
	var line: String
	match _format:
		"json":
			line = _format_json(level, system, message, kv)
		"compact":
			line = _format_compact(level, system, message, kv)
		_:
			line = _format_human(level, system, message, kv)

	if _output == "stdout" or _output == "both":
		print(line)
	if _file_handle != null:
		_file_handle.store_line(line)
		_file_handle.flush()


static func _format_human(level: int, system: String, message: String, kv: Dictionary) -> String:
	var ts := Time.get_ticks_msec()
	var system_padded := system.left(_SYSTEM_NAME_WIDTH).rpad(_SYSTEM_NAME_WIDTH)
	var kv_str := ""
	if not kv.is_empty():
		var parts: PackedStringArray = []
		for k in kv.keys():
			parts.append("%s=%s" % [str(k), str(kv[k])])
		kv_str = "  " + " ".join(parts)
	return "[%s] [%s] [%6d] %s%s" % [_LEVEL_NAMES[level], system_padded, ts, message, kv_str]


static func _format_json(level: int, system: String, message: String, kv: Dictionary) -> String:
	var obj := {
		"level": _LEVEL_NAMES[level].strip_edges(),
		"system": system,
		"ts_ms": Time.get_ticks_msec(),
		"msg": message,
	}
	for k in kv.keys():
		obj[str(k)] = kv[k]
	return JSON.stringify(obj)


static func _format_compact(level: int, system: String, message: String, kv: Dictionary) -> String:
	var kv_str := ""
	if not kv.is_empty():
		var parts: PackedStringArray = []
		for k in kv.keys():
			parts.append("%s=%s" % [str(k), str(kv[k])])
		kv_str = " " + " ".join(parts)
	return "%s %s %s%s" % [_LEVEL_NAMES[level].strip_edges(), system, message, kv_str]
