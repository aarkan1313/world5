@tool
extends EditorPlugin

# W5 plugin entry point. Registers autoloads for Tier 0 systems.
# Order matters for shutdown: autoloads tear down in reverse
# registration order (Godot's behavior), so register low-level
# foundations FIRST and higher-level consumers LAST.

const _AUTOLOADS: Array = [
	# (name, path) — registered in order; teardown is reversed
	["Log", "res://addons/world5/scripts/core/Log.gd"],
	["World5", "res://addons/world5/scripts/core/World5.gd"],
	["QualityTiers", "res://addons/world5/scripts/core/QualityTiers.gd"],
	["StreamingBudget", "res://addons/world5/scripts/core/StreamingBudget.gd"],
	["JobScheduler", "res://addons/world5/scripts/core/JobScheduler.gd"],
	["GpuResourceTracker", "res://addons/world5/scripts/core/GpuResourceTracker.gd"],
	["AssetStream", "res://addons/world5/scripts/core/AssetStream.gd"],
	["ChangeBroadcast", "res://addons/world5/scripts/core/ChangeBroadcast.gd"],
]


func _enter_tree() -> void:
	for entry in _AUTOLOADS:
		add_autoload_singleton(entry[0], entry[1])


func _exit_tree() -> void:
	# Remove in REVERSE registration order so dependents detach first
	for i in range(_AUTOLOADS.size() - 1, -1, -1):
		remove_autoload_singleton(_AUTOLOADS[i][0])
