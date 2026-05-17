## W5 ContentAddress — runtime read-side helper for content stamps.
##
## Per spec 12. Python side (pipeline/world5/content_address.py) is
## the writer + dependency graph + GC. GDScript runtime just needs to:
## - Compute a stable hash from a Dictionary of inputs (for stamp
##   verification at load time)
## - Read a stamp embedded in an artifact header (e.g. decoration blob)
## - Detect "is this artifact stale vs my expected stamp"
##
## Not an autoload; static class.

class_name ContentAddress extends RefCounted

const SYSTEM_NAME: String = "content_address"


## Compute a stable sha256 from a Dictionary of inputs.
## Matches Python's hash_inputs canonical encoding:
## - sorted keys
## - no whitespace
## - default=str for unknown types
##
## FileInput-style entries: GDScript runtime doesn't typically have
## file inputs (those are pipeline-side); if needed, hash the file
## bytes first via _hash_file_bytes and pass the digest as a string.
static func compute_stamp(inputs: Dictionary) -> String:
	var canonical := _canonical_json(inputs)
	return canonical.sha256_text()


## Read the stamp embedded in an artifact header. Per-artifact format
## varies; decoration blobs have a content_address_key field, JSON
## manifests have it as a top-level key.
##
## Returns "" if not found / file unreadable.
static func read_stamp(artifact_path: String) -> String:
	if not FileAccess.file_exists(artifact_path):
		return ""
	# Try JSON-manifest format first (most common)
	if artifact_path.ends_with(".json"):
		var file := FileAccess.open(artifact_path, FileAccess.READ)
		if file == null:
			return ""
		var text := file.get_as_text()
		file.close()
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed.get("content_address_key", "")
	# Binary blob formats: per-format header reading lives in the
	# system spec (e.g. decoration loader peels the W5DEC header).
	# This helper just covers JSON.
	return ""


## True if expected_stamp does not match the stamp recorded in artifact.
## Stale artifacts should be re-baked (caller's choice).
static func is_stale(artifact_path: String, expected_stamp: String) -> bool:
	var actual := read_stamp(artifact_path)
	if actual == "":
		return true  # missing stamp → treat as stale
	return actual != expected_stamp


# --- internals ---

static func _canonical_json(d: Dictionary) -> String:
	## Sorted-keys, no whitespace JSON to match Python's
	## json.dumps(sort_keys=True, separators=(",", ":")).
	var sorted_keys: Array = d.keys()
	sorted_keys.sort()
	var parts: PackedStringArray = []
	for k in sorted_keys:
		var key_str: String = JSON.stringify(str(k))
		var val: Variant = d[k]
		var val_str: String
		if typeof(val) == TYPE_DICTIONARY:
			val_str = _canonical_json(val)
		elif typeof(val) == TYPE_ARRAY:
			val_str = _canonical_array(val)
		else:
			val_str = JSON.stringify(val)
		parts.append("%s:%s" % [key_str, val_str])
	return "{" + ",".join(parts) + "}"


static func _canonical_array(a: Array) -> String:
	var parts: PackedStringArray = []
	for v in a:
		if typeof(v) == TYPE_DICTIONARY:
			parts.append(_canonical_json(v))
		elif typeof(v) == TYPE_ARRAY:
			parts.append(_canonical_array(v))
		else:
			parts.append(JSON.stringify(v))
	return "[" + ",".join(parts) + "]"
