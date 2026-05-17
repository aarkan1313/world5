## Tests for ChangeBroadcast (spec 11 + SA-S10 + SA-C3.17).

extends GutTest


var _bus: ChangeBroadcast

# Test helper: collect Change events as they arrive
class _Collector:
	var events: Array = []

	func on_change(change: ChangeBroadcast.Change) -> void:
		events.append(change)


var _collector: _Collector


func before_each() -> void:
	_bus = ChangeBroadcast.new()
	add_child_autofree(_bus)
	_collector = _Collector.new()
	await get_tree().process_frame


# --- publish + subscribe basics ---

func test_publish_returns_positive_id() -> void:
	var cid := _bus.publish(Rect2(0, 0, 10, 10), "test_source", {})
	assert_gt(cid, 0)


func test_subscribe_returns_positive_id() -> void:
	var sid := _bus.subscribe(_collector.on_change)
	assert_gt(sid, 0)


func test_sync_subscriber_receives_event_synchronously() -> void:
	_bus.subscribe(_collector.on_change)
	_bus.publish(Rect2(0, 0, 5, 5), "any_source", {"key": "value"})
	# Sync mode: callback invoked inside publish; events visible immediately
	assert_eq(_collector.events.size(), 1)
	assert_eq(_collector.events[0].source, "any_source")
	assert_eq(_collector.events[0].metadata["key"], "value")


func test_unsubscribe_stops_delivery() -> void:
	var sid := _bus.subscribe(_collector.on_change)
	_bus.publish(Rect2(0, 0, 5, 5), "src", {})
	assert_eq(_collector.events.size(), 1)
	assert_true(_bus.unsubscribe(sid))
	_bus.publish(Rect2(0, 0, 5, 5), "src", {})
	assert_eq(_collector.events.size(), 1, "no more events after unsub")


func test_unsubscribe_unknown_returns_false() -> void:
	assert_false(_bus.unsubscribe(99999))


# --- filters ---

func test_source_filter_matches() -> void:
	_bus.subscribe(_collector.on_change, {"sources": PackedStringArray(["allowed"])})
	_bus.publish(Rect2(0, 0, 5, 5), "allowed", {})
	_bus.publish(Rect2(0, 0, 5, 5), "blocked", {})
	assert_eq(_collector.events.size(), 1)
	assert_eq(_collector.events[0].source, "allowed")


func test_source_filter_empty_matches_all() -> void:
	_bus.subscribe(_collector.on_change, {})
	_bus.publish(Rect2(0, 0, 5, 5), "src_a", {})
	_bus.publish(Rect2(0, 0, 5, 5), "src_b", {})
	assert_eq(_collector.events.size(), 2)


func test_region_filter_intersects() -> void:
	_bus.subscribe(_collector.on_change, {"region": Rect2(0, 0, 10, 10)})
	# Inside region
	_bus.publish(Rect2(5, 5, 1, 1), "src", {})
	# Outside region
	_bus.publish(Rect2(100, 100, 1, 1), "src", {})
	assert_eq(_collector.events.size(), 1)


# --- dispatch modes ---

func test_async_dispatch_defers_to_next_frame() -> void:
	_bus.subscribe(_collector.on_change, {"dispatch": "async"})
	_bus.publish(Rect2(0, 0, 5, 5), "src", {})
	# Async mode: callback NOT yet invoked; wait one frame
	assert_eq(_collector.events.size(), 0)
	await get_tree().process_frame
	assert_eq(_collector.events.size(), 1)


func test_job_dispatch_falls_back_to_async_without_scheduler() -> void:
	# In test context there's no /root/JobScheduler, so job mode
	# degrades to async (defer to next frame)
	_bus.subscribe(_collector.on_change, {"dispatch": "job"})
	_bus.publish(Rect2(0, 0, 5, 5), "src", {})
	assert_eq(_collector.events.size(), 0, "not yet invoked")
	await get_tree().process_frame
	assert_eq(_collector.events.size(), 1)


# --- metadata + change object ---

func test_change_metadata_carries_through() -> void:
	_bus.subscribe(_collector.on_change)
	_bus.publish(Rect2(0, 0, 5, 5), "src", {
		"owner_system": "foliage",
		"exclusion_kind": "trunk_footprint",
		"exclusion_categories": ["foliage", "rocks"],
	})
	var ch: ChangeBroadcast.Change = _collector.events[0]
	assert_eq(ch.metadata["owner_system"], "foliage")
	assert_eq(ch.metadata["exclusion_kind"], "trunk_footprint")
	assert_eq(ch.metadata["exclusion_categories"], ["foliage", "rocks"])


func test_change_timestamp_set() -> void:
	_bus.subscribe(_collector.on_change)
	_bus.publish(Rect2(0, 0, 5, 5), "src", {})
	assert_gt(_collector.events[0].timestamp_ms, 0)


# --- diagnostics ---

func test_get_recent_returns_history() -> void:
	for i in range(5):
		_bus.publish(Rect2(0, 0, 1, 1), "src_%d" % i, {})
	var recent := _bus.get_recent(3)
	assert_eq(recent.size(), 3)
	# Most recent at end
	assert_eq(recent[2].source, "src_4")


func test_get_subscriber_count() -> void:
	_bus.subscribe(_collector.on_change)
	_bus.subscribe(_collector.on_change)
	assert_eq(_bus.get_subscriber_count(), 2)


func test_get_subscribers_for_source_filters() -> void:
	_bus.subscribe(_collector.on_change, {"sources": PackedStringArray(["foo"])})
	_bus.subscribe(_collector.on_change, {"sources": PackedStringArray(["bar"])})
	_bus.subscribe(_collector.on_change, {})  # matches all
	var for_foo := _bus.get_subscribers_for_source("foo")
	assert_eq(for_foo.size(), 2, "foo subscriber + all-source subscriber")


# --- SA2-C4.1: unsubscribe-during-dispatch must not crash ---

var _unsubbed_count: int = 0


func _on_change_and_unsub(_change) -> void:
	_unsubbed_count += 1
	for sid in _bus._subs.keys():
		_bus.unsubscribe(sid)


func test_unsubscribe_during_dispatch_does_not_crash() -> void:
	_unsubbed_count = 0
	_bus.subscribe(_on_change_and_unsub)
	_bus.subscribe(_on_change_and_unsub)
	_bus.subscribe(_on_change_and_unsub)
	_bus.publish(Rect2(0, 0, 5, 5), "src", {})
	# First callback nukes all subs; snapshot+has() guard skips the
	# rest. No crash.
	assert_eq(_unsubbed_count, 1,
		"first callback unsubs all; remaining iterations guarded")
	assert_eq(_bus.get_subscriber_count(), 0,
		"all subs cleaned up")


# --- audit C3.17: placement_exclusion contract ---

func test_placement_exclusion_metadata_shape() -> void:
	## The canonical metadata payload for placement_exclusion per spec 11
	## SA-C3.17. Subscribers (decoration, foliage, roads) check
	## exclusion_categories.
	var received: Array = []
	_bus.subscribe(
		func(ch): received.append(ch),
		{"sources": PackedStringArray(["placement_exclusion"])}
	)
	_bus.publish(
		Rect2(0, 0, 20, 20),
		"placement_exclusion",
		{
			"owner_system": "foliage",
			"exclusion_kind": "trunk_footprint",
			"exclusion_categories": ["foliage", "rocks", "props"],
		}
	)
	assert_eq(received.size(), 1)
	var ch: ChangeBroadcast.Change = received[0]
	assert_true(ch.metadata.has("owner_system"))
	assert_true(ch.metadata.has("exclusion_kind"))
	assert_true(ch.metadata.has("exclusion_categories"))
	# Decoration would check if "rocks" or "props" in exclusion_categories
	assert_true("rocks" in ch.metadata["exclusion_categories"])
