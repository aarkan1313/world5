## W5 version + identity singleton.
##
## Per spec 17. VERSION is parsed from plugin.cfg at boot. Provides
## semver helpers (parse, is_compatible, needs_migration,
## migration_path) used by every loader that checks artifact version
## stamps.
##
## Autoload at /root/World5 (registered in Phase 2.12).

class_name World5 extends Node

const VERSION: String = "0.0.1"  # mirrors engine/plugin.cfg version field
const SYSTEM_NAME: String = "world5"  # for Log calls


## Parse a semver string into [major, minor, patch] ints.
## Returns [0, 0, 0] on invalid input + logs warning.
static func parse(version_str: String) -> Array:
	var parts := version_str.split(".")
	if parts.size() < 3:
		Log.warn(SYSTEM_NAME, "Invalid version string", {"version": version_str})
		return [0, 0, 0]
	var nums: Array = []
	for p in parts.slice(0, 3):
		# Strip pre-release suffix like "0.1.0-beta.1" → "0"
		var num_str := p.split("-")[0]
		if not num_str.is_valid_int():
			Log.warn(SYSTEM_NAME, "Invalid version component", {"version": version_str, "component": p})
			return [0, 0, 0]
		nums.append(num_str.to_int())
	return nums


## Returns true if artifact_version is compatible with runtime VERSION.
##
## Compat rules (per spec 17):
## - Same MAJOR → compatible (MINOR additions don't break readers)
## - Different MAJOR → NOT compatible; migration required
## - Pre-1.0 (MAJOR==0): MINOR differences also break (per "anything
##   goes pre-1.0" rule); only PATCH-level differences are compat
static func is_compatible(artifact_version: String) -> bool:
	var runtime := parse(VERSION)
	var artifact := parse(artifact_version)
	if runtime[0] != artifact[0]:
		return false
	# Pre-1.0: MINOR must also match
	if runtime[0] == 0 and runtime[1] != artifact[1]:
		return false
	return true


## Returns true if the artifact needs migration to load against runtime.
static func needs_migration(artifact_version: String) -> bool:
	return not is_compatible(artifact_version)


## Returns the chain of intermediate versions to migrate from_v → to_v.
## Each entry is a version string; the first migration step is from_v
## → result[0], the second is result[0] → result[1], etc.
##
## Stub for Phase 2.2: returns [to_v] (direct migration). Real
## implementation walks the migration script directory in Phase 14 +
## persistence sprint.
static func migration_path(from_v: String, to_v: String) -> Array:
	if from_v == to_v:
		return []
	return [to_v]
