## Tests for ContentAddress.gd (GDScript read-side wrapper).
##
## Per spec 12. Runtime mostly reads stamps from artifact headers +
## checks staleness; full content-address machinery lives in Python.

extends GutTest


# --- compute_stamp determinism + order independence ---

func test_compute_stamp_deterministic() -> void:
	var inputs := {"a": 1, "b": "two", "c": [1, 2, 3]}
	var h1 := ContentAddress.compute_stamp(inputs)
	var h2 := ContentAddress.compute_stamp(inputs)
	assert_eq(h1, h2)


func test_compute_stamp_order_independent() -> void:
	# Sorted-keys canonicalization → insertion order doesn't matter
	var a := {"alpha": 1, "beta": 2}
	var b := {"beta": 2, "alpha": 1}
	assert_eq(ContentAddress.compute_stamp(a), ContentAddress.compute_stamp(b))


func test_compute_stamp_different_values_differ() -> void:
	assert_ne(
		ContentAddress.compute_stamp({"x": 1}),
		ContentAddress.compute_stamp({"x": 2})
	)


func test_compute_stamp_handles_nested() -> void:
	var nested := {
		"outer": "v",
		"inner": {"a": 1, "b": [1, 2]},
	}
	var stamp := ContentAddress.compute_stamp(nested)
	assert_eq(stamp.length(), 64, "sha256 hex digest is 64 chars")


# --- read_stamp from JSON artifact ---

func test_read_stamp_from_json_manifest() -> void:
	# Write a temp JSON manifest with a content_address_key
	var tmp_path := "user://_test_manifest.json"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	file.store_string('{"content_address_key": "abcdef1234567890"}')
	file.close()
	assert_eq(ContentAddress.read_stamp(tmp_path), "abcdef1234567890")
	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))


func test_read_stamp_missing_file_empty() -> void:
	assert_eq(ContentAddress.read_stamp("res://does/not/exist.json"), "")


func test_read_stamp_no_key_in_json_empty() -> void:
	var tmp_path := "user://_test_manifest_nokey.json"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	file.store_string('{"other_field": "value"}')
	file.close()
	assert_eq(ContentAddress.read_stamp(tmp_path), "")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))


# --- is_stale ---

func test_is_stale_matching_stamp_false() -> void:
	var tmp_path := "user://_test_stale_match.json"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	file.store_string('{"content_address_key": "expected_stamp"}')
	file.close()
	assert_false(ContentAddress.is_stale(tmp_path, "expected_stamp"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))


func test_is_stale_mismatch_true() -> void:
	var tmp_path := "user://_test_stale_mismatch.json"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	file.store_string('{"content_address_key": "old_stamp"}')
	file.close()
	assert_true(ContentAddress.is_stale(tmp_path, "new_stamp"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))


func test_is_stale_missing_artifact_true() -> void:
	assert_true(ContentAddress.is_stale("res://does/not/exist.json", "any_stamp"))
