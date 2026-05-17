## Tests for StreamingBudget (spec 10).
##
## Headless test runs use the default tier (`high`) per QualityTiers.

extends GutTest


var _budget: StreamingBudget


func before_each() -> void:
	_budget = StreamingBudget.new()
	add_child_autofree(_budget)
	# Wait one frame for _ready
	await get_tree().process_frame


# --- publish + clear ---

func test_publish_records_usage() -> void:
	_budget.publish("test_system", {"active_jobs": 5, "asset_cache_mb": 100})
	var usage := _budget.get_system_usage("test_system")
	assert_eq(usage["active_jobs"], 5)
	assert_eq(usage["asset_cache_mb"], 100)


func test_publish_unknown_keys_filtered() -> void:
	_budget.publish("test_system", {"active_jobs": 5, "bogus_key": 999})
	var usage := _budget.get_system_usage("test_system")
	assert_eq(usage["active_jobs"], 5)
	assert_false(usage.has("bogus_key"))


func test_publish_missing_keys_default_zero() -> void:
	_budget.publish("test_system", {"active_jobs": 5})
	var usage := _budget.get_system_usage("test_system")
	assert_eq(usage["asset_cache_mb"], 0)


func test_publish_overwrites() -> void:
	_budget.publish("test_system", {"active_jobs": 5})
	# Rate limit gate: wait > 100ms before second publish to avoid coalesce
	await get_tree().create_timer(0.15).timeout
	_budget.publish("test_system", {"active_jobs": 10})
	assert_eq(_budget.get_system_usage("test_system")["active_jobs"], 10)


func test_clear_removes_system() -> void:
	_budget.publish("test_system", {"active_jobs": 5})
	_budget.clear("test_system")
	# Unknown system returns zero-usage dict
	var usage := _budget.get_system_usage("test_system")
	assert_eq(usage["active_jobs"], 0)


# --- aggregation ---

func test_get_total_usage_sums_across_systems() -> void:
	_budget.publish("system_a", {"active_jobs": 3, "asset_cache_mb": 100})
	_budget.publish("system_b", {"active_jobs": 4, "asset_cache_mb": 200})
	var total := _budget.get_total_usage()
	assert_eq(total["active_jobs"], 7)
	assert_eq(total["asset_cache_mb"], 300)


func test_get_unknown_system_returns_zeros() -> void:
	var usage := _budget.get_system_usage("nonexistent")
	for key in StreamingBudget.KEYS:
		assert_eq(usage[key], 0)


# --- budget + headroom + over-budget ---

func test_get_budget_reads_quality_tiers() -> void:
	# Default tier is 'high'; budgets > 0
	var budget := _budget.get_budget()
	assert_gt(budget["active_jobs"], 0, "high tier has positive active_jobs budget")


func test_get_headroom_is_budget_minus_total() -> void:
	# Publish small usage; headroom should be (budget - usage)
	_budget.publish("test", {"active_jobs": 1})
	var headroom := _budget.get_headroom()
	var budget := _budget.get_budget()
	assert_eq(headroom["active_jobs"], budget["active_jobs"] - 1)


func test_is_over_budget_false_when_under() -> void:
	_budget.publish("test", {"active_jobs": 1, "asset_cache_mb": 10})
	assert_false(_budget.is_over_budget())


func test_is_over_budget_true_when_over() -> void:
	# Publish way over high-tier budgets
	_budget.publish("test", {
		"active_jobs": 99999,
		"asset_cache_mb": 99999,
	})
	assert_true(_budget.is_over_budget())


# --- top publishers ---

func test_get_top_publishers_orders_by_value() -> void:
	_budget.publish("low", {"active_jobs": 1})
	_budget.publish("high", {"active_jobs": 10})
	_budget.publish("mid", {"active_jobs": 5})
	var top := _budget.get_top_publishers("active_jobs", 3)
	assert_eq(top[0]["system"], "high")
	assert_eq(top[1]["system"], "mid")
	assert_eq(top[2]["system"], "low")


func test_get_top_publishers_respects_n_limit() -> void:
	for i in range(10):
		_budget.publish("system_%d" % i, {"active_jobs": i})
	var top := _budget.get_top_publishers("active_jobs", 3)
	assert_eq(top.size(), 3)


# --- diagnostics ---

func test_get_publishers_lists_published_systems() -> void:
	_budget.publish("a", {"active_jobs": 1})
	_budget.publish("b", {"active_jobs": 2})
	var pubs := _budget.get_publishers()
	assert_eq(pubs.size(), 2)
	assert_true(pubs.has("a"))
	assert_true(pubs.has("b"))


func test_get_history_returns_snapshots() -> void:
	_budget.publish("test", {"active_jobs": 1})
	var history := _budget.get_history(60.0)
	assert_gt(history.size(), 0)
	assert_true(history[0].has("ts_ms"))
	assert_true(history[0].has("totals"))
