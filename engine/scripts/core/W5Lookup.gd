## W5Lookup — autoload lookup helper with W5_-prefixed primary +
## bare-name fallback for test injection.
##
## Per Phase 4.7 autoload-rename refactor: production autoloads are
## at /root/W5_<Name> (W5_ prefix avoids class_name collision per
## Godot 4 rules). Tests historically instantiate at /root/<Name>
## without the prefix to avoid colliding with the autoload. This
## helper checks both so SUT code Just Works in both contexts.
##
## Static-only; no instances; class_name only.

class_name W5Lookup extends RefCounted


## Returns the autoload-or-test-override node for the given short name
## (e.g. "JobScheduler"). Tries the bare name first (test-injection
## path: /root/<name>) so tests' manually-instantiated systems
## override the autoload; falls back to W5_-prefixed (production
## autoload path: /root/W5_<name>). Returns null if neither exists.
static func find(short_name: String) -> Node:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	# Test-override wins: lets gut tests instantiate at /root/<name>
	# without renaming + still get the SUT to wire to their instance.
	var n: Node = loop.root.get_node_or_null("/root/" + short_name)
	if n != null:
		return n
	# Production fallback: the autoload-registered prefixed name.
	return loop.root.get_node_or_null("/root/W5_" + short_name)
