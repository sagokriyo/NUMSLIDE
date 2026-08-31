extends Node
## Screenshot harness for the design feedback loop. Instances a target scene as
## a child of the root and saves a framebuffer PNG after a delay, then quits.
## Usage:
##   godot --path . res://tools/shoot.tscn -- scene=res://scenes/splash/splash.tscn out=res://tools/out/splash.png delay=1.6

func _ready() -> void:
	var cfg := {
		"scene": "res://scenes/splash/splash.tscn",
		"out": "res://tools/out/shot.png",
		"delay": "1.6",
	}
	for a in OS.get_cmdline_user_args():
		var kv := String(a).split("=", false, 1)
		if kv.size() == 2:
			cfg[kv[0]] = kv[1]
	_run(cfg)

func _run(cfg: Dictionary) -> void:
	var scene_path := String(cfg["scene"])
	var out_path := String(cfg["out"])
	var delay := float(cfg["delay"])

	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("shoot: cannot load " + scene_path)
		get_tree().quit(1)
		return
	await get_tree().process_frame
	var inst := packed.instantiate()
	get_tree().root.add_child(inst)
	get_tree().current_scene = inst

	await get_tree().create_timer(delay).timeout
	# A couple of frames so the latest tween state is rendered to the framebuffer.
	await RenderingServer.frame_post_draw

	var img := get_tree().root.get_viewport().get_texture().get_image()
	var abs_out := ProjectSettings.globalize_path(out_path)
	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())
	var err := img.save_png(abs_out)
	print("shoot: ", "OK" if err == OK else ("ERR " + str(err)), " -> ", abs_out)
	get_tree().quit(0)
