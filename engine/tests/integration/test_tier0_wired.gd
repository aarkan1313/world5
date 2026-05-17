## Integration test: the Tier 0 "wired triangle" actually wires.
##
## Per SA2-C5.5: every cross-system wire (JobScheduler→StreamingBudget,
## AssetStream→StreamingBudget, ChangeBroadcast job-mode→JobScheduler)
## uses get_node_or_null("/root/X") which silently no-ops in test
## contexts. Phase 2 unit tests don't have autoloads → wires never
## fire → integration is architecturally claimed but practically
## unverified.
##
## This test spawns all 4 systems as siblings under the test scene
## root, but ALSO puts each at the autoload paths the lazy-lookups
## expect. The wires should fire end-to-end.

extends GutTest


var _budget: StreamingBudget
var _job_scheduler: JobScheduler
var _asset_stream: AssetStream
var _broadcast: ChangeBroadcast


func before_each() -> void:
	# Spawn systems at the autoload paths so lazy lookups resolve.
	# We add them as children of /root so get_node_or_null("/root/X")
	# finds them.
	_budget = StreamingBudget.new()
	_budget.name = "StreamingBudget"
	get_tree().root.add_child(_budget)

	_job_scheduler = JobScheduler.new()
	_job_scheduler.name = "JobScheduler"
	get_tree().root.add_child(_job_scheduler)

	_asset_stream = AssetStream.new()
	_asset_stream.name = "AssetStream"
	get_tree().root.add_child(_asset_stream)

	_broadcast = ChangeBroadcast.new()
	_broadcast.name = "ChangeBroadcast"
	get_tree().root.add_child(_broadcast)

	# One frame for _ready
	await get_tree().process_frame


func after_each() -> void:
	# Tear down in reverse registration order, guarding against
	# already-freed (a test may have freed mid-run).
	if is_instance_valid(_broadcast):
		_broadcast.queue_free()
	if is_instance_valid(_asset_stream):
		_asset_stream.queue_free()
	if is_instance_valid(_job_scheduler):
		_job_scheduler.queue_free()
	if is_instance_valid(_budget):
		_budget._reset()
		_budget.queue_free()
	await get_tree().process_frame


# --- TEST 1: JobScheduler → StreamingBudget wire ---

class _SimpleJob extends Job:
	func _init():
		name = "test_job"
	func _execute() -> Variant:
		return 42


func test_jobscheduler_publishes_active_jobs_to_streaming_budget() -> void:
	# Submit MANY jobs so the queue is observably nonempty
	# (scheduler dispatches 1 per tick — at 60Hz, queuing 10 means
	# at least 9 are pending at the next publish).
	for i in range(10):
		_job_scheduler.submit(_SimpleJob.new())

	# Wait one frame for publish to fire
	await get_tree().process_frame

	var publishers := _budget.get_publishers()
	assert_true(publishers.has("job_scheduler"),
		"job_scheduler appears in StreamingBudget publishers — wire works")

	# Stronger: actual value should reflect queued jobs
	var usage := _budget.get_system_usage("job_scheduler")
	assert_gt(usage["active_jobs"], 0,
		"active_jobs > 0 immediately after submitting 10 jobs")


# --- TEST 2: AssetStream → StreamingBudget wire ---

func test_assetstream_publishes_asset_cache_mb_to_streaming_budget() -> void:
	# AssetStream._tick runs every frame; even with no requests it
	# publishes (debounced). Wait a few frames.
	for i in range(3):
		await get_tree().process_frame

	var publishers := _budget.get_publishers()
	assert_true(publishers.has("asset_stream"),
		"asset_stream appears in StreamingBudget publishers — wire works")


# --- TEST 3: ChangeBroadcast job-mode → JobScheduler wire ---

var _job_dispatch_received: bool = false


func _on_broadcast_via_job(_change) -> void:
	_job_dispatch_received = true


func test_changebroadcast_job_mode_routes_through_jobscheduler() -> void:
	_job_dispatch_received = false

	# Subscribe in job mode
	_broadcast.subscribe(_on_broadcast_via_job, {"dispatch": "job"})

	# Publish — should wrap callback in a Job + submit to scheduler
	_broadcast.publish(Rect2(0, 0, 10, 10), "test_source", {})

	# Wait for scheduler to dispatch + WTP worker to run + callback to fire
	for i in range(10):
		await get_tree().process_frame
		if _job_dispatch_received:
			break

	assert_true(_job_dispatch_received,
		"job-mode broadcast callback fired via JobScheduler")


# --- TEST 4: Aggregate — multiple systems publish, get_total_usage sums ---

func test_total_usage_aggregates_across_publishers() -> void:
	# Tick a few times so both JobScheduler + AssetStream publish
	for i in range(3):
		await get_tree().process_frame

	var publishers := _budget.get_publishers()
	# We should have at least job_scheduler and asset_stream
	assert_true(publishers.has("job_scheduler"),
		"job_scheduler published")
	assert_true(publishers.has("asset_stream"),
		"asset_stream published")

	# get_total_usage should be a valid dict with all KEYS
	var total := _budget.get_total_usage()
	for key in StreamingBudget.KEYS:
		assert_true(total.has(key), "total has key %s" % key)


# --- TEST 5: Autoload absence does NOT crash (negative test of lazy lookup) ---

func test_lazy_lookup_no_crash_when_autoload_missing() -> void:
	# Remove StreamingBudget mid-test; JobScheduler shouldn't crash
	_budget.queue_free()
	await get_tree().process_frame

	# Submit a job; JobScheduler's _publish_to_budget will lookup
	# /root/StreamingBudget, fail, and silently skip. Shouldn't crash.
	_job_scheduler.submit(_SimpleJob.new())
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(true, "no crash when StreamingBudget missing")
