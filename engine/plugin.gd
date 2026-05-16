@tool
extends EditorPlugin

# W5 plugin entry point. Phase 0 scaffold — no autoloads registered
# yet. Phase 2 will register: JobScheduler, AssetStream, StreamingBudget,
# ChangeBroadcast, QualityTiers, Log, World5, GpuResourceTracker.
# Each is added per its spec when that system ships in Phase 2.


func _enter_tree() -> void:
	# Autoloads registered here in Phase 2:
	# add_autoload_singleton("Log", "res://addons/world5/scripts/core/Log.gd")
	# add_autoload_singleton("World5", "res://addons/world5/scripts/core/World5.gd")
	# add_autoload_singleton("JobScheduler", "res://addons/world5/scripts/core/JobScheduler.gd")
	# add_autoload_singleton("AssetStream", "res://addons/world5/scripts/core/AssetStream.gd")
	# add_autoload_singleton("StreamingBudget", "res://addons/world5/scripts/core/StreamingBudget.gd")
	# add_autoload_singleton("ChangeBroadcast", "res://addons/world5/scripts/core/ChangeBroadcast.gd")
	# add_autoload_singleton("QualityTiers", "res://addons/world5/scripts/core/QualityTiers.gd")
	# add_autoload_singleton("GpuResourceTracker", "res://addons/world5/scripts/core/GpuResourceTracker.gd")
	pass


func _exit_tree() -> void:
	# remove_autoload_singleton("Log")
	# ... etc, reverse order ...
	pass
