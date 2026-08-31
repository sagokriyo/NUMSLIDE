extends SceneTree
## Dev screenshot tool. Run WITHOUT --headless (needs a real renderer):
##   godot --path . --script res://tools/screenshot.gd -- <scene_path> <out_png> [continue]
## Saves a portrait PNG of the given scene after it settles, then quits.

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := "res://scenes/home/home.tscn"
	var out := "res://_shot.png"
	if args.size() >= 1:
		scene_path = args[0]
	if args.size() >= 2:
		out = args[1]

	DisplayServer.window_set_size(Vector2i(540, 1170))
	# Force a theme for the preview WITHOUT persisting it (4th arg, default daybreak).
	var want_theme := "daybreak"
	if args.size() >= 4:
		want_theme = args[3]
	var tm: Node = root.get_node_or_null("/root/ThemeManager")
	if tm and String(tm.current_id()) != want_theme:
		tm.set_theme(want_theme)
	await process_frame
	await process_frame

	# Optional 3rd arg: a gameplay mode to start fresh (so we can preview a board).
	if args.size() >= 3:
		var router: Node = root.get_node_or_null("/root/SceneRouter")
		if router:
			router._payload = {"mode": args[2], "continue": false}

	var packed: PackedScene = load(scene_path)
	var inst: Node = packed.instantiate()
	root.add_child(inst)
	current_scene = inst

	# Let layout settle + the entrance fade finish.
	for i in 60:
		await process_frame

	var img := root.get_texture().get_image()
	img.save_png(out)
	print("SHOT_SAVED ", out)
	quit()
