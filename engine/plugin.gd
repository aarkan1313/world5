@tool
extends EditorPlugin

# W5 plugin entry point. Registers autoloads for Tier 0 systems that
# need an active instance (process tick, _exit_tree drain, signal
# subscribers).
#
# Static-only classes (Log, World5, QualityTiers, ContentAddress) are
# NOT autoloads — they're accessed via class_name globals
# (Log.info(...), QualityTiers.get_tier(...), etc.). Per audit
# SA2-C1.1: registering RefCounted classes as autoloads fails
# silently; registering static-only Node classes wastes a node slot.
#
# Order matters for shutdown: autoloads tear down in reverse
# registration order. Register low-level foundations FIRST so
# higher-level consumers detach BEFORE their dependencies do.

const _AUTOLOADS: Array = [
	# (name, path) — registered in order; teardown is reversed.
	# W5_ prefix per Phase 4.7: bare names collide with the scripts'
	# class_name globals (Godot 4: "X is an invalid name. Must not
	# collide with an existing global script class name."). SUT
	# lookups go through W5Lookup.find(short_name) which tries the
	# W5_-prefixed path first + falls back to the bare name for
	# test-injection compatibility.
	["W5_StreamingBudget", "res://addons/world5/scripts/core/StreamingBudget.gd"],
	["W5_JobScheduler", "res://addons/world5/scripts/core/JobScheduler.gd"],
	["W5_GpuResourceTracker", "res://addons/world5/scripts/core/GpuResourceTracker.gd"],
	["W5_AssetStream", "res://addons/world5/scripts/core/AssetStream.gd"],
	["W5_ChangeBroadcast", "res://addons/world5/scripts/core/ChangeBroadcast.gd"],
]


func _enter_tree() -> void:
	for entry in _AUTOLOADS:
		add_autoload_singleton(entry[0], entry[1])
	# Note (SA2-S1.4 follow-up): add_autoload_singleton's success is
	# only observable in the NEXT editor session via
	# ProjectSettings.has_setting("autoload/<name>"). In --import or
	# --headless mode the check would always report "missing" (false
	# positive). The wired-triangle integration test
	# (engine/tests/integration/test_tier0_wired.gd) is the real
	# verification — if autoloads don't register, that test fails.


func _exit_tree() -> void:
	# Remove in REVERSE registration order so dependents detach first
	for i in range(_AUTOLOADS.size() - 1, -1, -1):
		remove_autoload_singleton(_AUTOLOADS[i][0])
