extends SceneTree
## Headless bootstrap for Node-based test suites.
##
## `--script` requires a SceneTree main loop, but the suites are Nodes (so the
## device runner can embed the same files in the running app). This tiny loop
## bridges the two: it loads the suite named after `--` and adds it to the tree;
## the suite then drives itself and quits the process with its exit code
## (quit_on_finish is true by default).
##
##   godot --headless --path . --script res://regression/headless/harness/headless_boot.gd -- --test=res://tests/test_game_board.gd

func _initialize() -> void:
	var target := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--test="):
			target = arg.trim_prefix("--test=")
	if target.is_empty():
		printerr("headless_boot: missing --test=res://... (pass it after --)")
		quit(2)
		return
	var script: Variant = load(target)
	if not (script is GDScript):
		printerr("headless_boot: cannot load suite script: %s" % target)
		quit(2)
		return
	var suite: Node = (script as GDScript).new()
	if suite == null:
		printerr("headless_boot: %s did not instantiate as a Node" % target)
		quit(2)
		return
	suite.name = "Suite"
	root.add_child(suite)
