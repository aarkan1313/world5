## W5 ChangeBroadcast — pub/sub for "region R changed at time T".
##
## Per spec 11 + SA-S10 (three dispatch modes: sync / async / job).
##
## Source metadata schemas (per SA-C3.17) documented in spec 11:
## - placement_exclusion: foliage/decoration/roads coordinate footprints
## - terrain_deformation: spec 38 publishes crater events
## - path_zone: spec 41 publishes road exclusion zones
## - decoration_zone: spec 28 zone add/edit/remove
##
## Autoload at /root/ChangeBroadcast (registered Phase 2.12).

class_name ChangeBroadcast extends Node

const SYSTEM_NAME: String = "change_broadcast"

# Change event record (passed to subscriber callbacks)
class Change extends RefCounted:
	var region: Rect2
	var source: String
	var timestamp_ms: int
	var metadata: Dictionary
	var id: int  # globally unique


# Subscription record
class _Sub extends RefCounted:
	var id: int
	var callback: Callable
	var filter_sources: PackedStringArray  # empty = match all
	var filter_region: Rect2  # empty (size==0) = match all
	var dispatch: String  # "sync" | "async" | "job"
	var alive: bool = true


var _subs: Dictionary = {}  # sub_id → _Sub
var _next_sub_id: int = 1
var _next_change_id: int = 1

# Ring buffer of recent changes
var _history: Array = []
const _HISTORY_MAX: int = 1000


# --- publish ---

## Broadcast a change to matching subscribers.
## Returns the change id (for diagnostics).
func publish(region: Rect2, source: String, metadata: Dictionary = {}) -> int:
	var change := Change.new()
	change.id = _next_change_id
	_next_change_id += 1
	change.region = region
	change.source = source
	change.timestamp_ms = Time.get_ticks_msec()
	change.metadata = metadata
	_record_history(change)
	_dispatch(change)
	return change.id


# --- subscribe ---

## Subscribe to changes. Returns subscription id (use for unsubscribe).
## filter keys:
##   - sources: PackedStringArray — only events from these sources
##   - region:  Rect2 — only events whose region intersects this
##   - dispatch: "sync" (default) | "async" | "job"
func subscribe(callback: Callable, filter: Dictionary = {}) -> int:
	var sub := _Sub.new()
	sub.id = _next_sub_id
	_next_sub_id += 1
	sub.callback = callback
	sub.filter_sources = filter.get("sources", PackedStringArray()) as PackedStringArray
	sub.filter_region = filter.get("region", Rect2())
	sub.dispatch = filter.get("dispatch", "sync")
	assert(sub.dispatch in ["sync", "async", "job"],
		"dispatch must be sync/async/job; got %s" % sub.dispatch)
	_subs[sub.id] = sub
	return sub.id


func unsubscribe(sub_id: int) -> bool:
	if not _subs.has(sub_id):
		return false
	_subs[sub_id].alive = false
	_subs.erase(sub_id)
	return true


# --- query ---

func get_recent(count: int = 100) -> Array:
	if count >= _history.size():
		return _history.duplicate()
	return _history.slice(_history.size() - count, _history.size())


func get_subscribers_for_source(source: String) -> PackedInt32Array:
	var out: PackedInt32Array = []
	for sid in _subs.keys():
		var sub: _Sub = _subs[sid]
		if sub.filter_sources.is_empty() or sub.filter_sources.has(source):
			out.append(sid)
	return out


func get_subscriber_count() -> int:
	return _subs.size()


# --- Godot lifecycle ---

func _ready() -> void:
	Log.info(SYSTEM_NAME, "ChangeBroadcast ready")


# --- internals ---

func _dispatch(change: Change) -> void:
	# SA2-C4.1: snapshot keys before iterating — a sync subscriber's
	# callback may unsubscribe (auto-remove pattern), mutating _subs
	# mid-iteration. Snapshot avoids the undefined-behavior trap.
	# Per pitfall meta-3.
	var sids: Array = _subs.keys()
	for sid in sids:
		# Sub may have been unsubscribed during this dispatch
		if not _subs.has(sid):
			continue
		var sub: _Sub = _subs[sid]
		if not sub.alive:
			continue
		if not _matches(sub, change):
			continue
		match sub.dispatch:
			"sync":
				_invoke_sync(sub, change)
			"async":
				_invoke_async(sub, change)
			"job":
				_invoke_job(sub, change)


# SA2-C4.2 notes: Godot's Callable.call catches script errors
# internally (the error appears in the debugger Output panel but
# doesn't propagate up to abort the surrounding loop). Empirically
# verified: a throwing sync subscriber doesn't kill the dispatch
# loop. The audit concern was inherited from Python-style
# exception-propagation thinking; GDScript semantics differ.
#
# Two exceptions where dispatch CAN abort:
# 1. `assert false` in a callback — kills the scene tree in debug
# 2. Native crashes (rare; e.g. accessing a freed Object)
# Document for subscribers; rely on per-callback discipline.


func _matches(sub: _Sub, change: Change) -> bool:
	# Source filter
	if not sub.filter_sources.is_empty():
		if not sub.filter_sources.has(change.source):
			return false
	# Region filter (empty Rect2 → match all)
	if sub.filter_region.size != Vector2.ZERO:
		if not sub.filter_region.intersects(change.region):
			return false
	return true


func _invoke_sync(sub: _Sub, change: Change) -> void:
	if sub.callback.is_valid():
		sub.callback.call(change)


func _invoke_async(sub: _Sub, change: Change) -> void:
	# Defer to next idle frame
	if sub.callback.is_valid():
		sub.callback.call_deferred(change)


func _invoke_job(sub: _Sub, change: Change) -> void:
	# Wrap in a Job + submit to scheduler. Lazy lookup of /root/JobScheduler;
	# if absent (test context), fall back to call_deferred so behavior is
	# still observable.
	var scheduler := get_node_or_null("/root/JobScheduler")
	if scheduler == null:
		# Tests without autoload — degrade to async
		if sub.callback.is_valid():
			sub.callback.call_deferred(change)
		return
	# Real path: scheduler.submit(BroadcastCallbackJob.new(...))
	# For Phase 2.9 we use a simple Job subclass inline.
	var job := _CallbackJob.new(sub.callback, change)
	scheduler.call("submit", job)


func _record_history(change: Change) -> void:
	_history.append(change)
	if _history.size() > _HISTORY_MAX:
		_history.pop_front()


## Test helper: reset state.
func _reset() -> void:
	_subs.clear()
	_history.clear()
	_next_sub_id = 1
	_next_change_id = 1


# --- Job wrapper for "job" dispatch mode ---

class _CallbackJob extends Job:
	var _callback: Callable
	var _change: Change

	func _init(cb: Callable, ch: Change):
		_callback = cb
		_change = ch
		name = "broadcast_callback_%d" % ch.id
		priority = Priority.NORMAL

	func _execute() -> Variant:
		if is_cancelled():
			return null
		if _callback.is_valid():
			_callback.call(_change)
		return null
