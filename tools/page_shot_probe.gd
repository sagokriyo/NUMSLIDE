extends Node
## Screenshot probe — NOT part of the game. Boots the Profile and Statistics
## screens in turn, lets the glass-shard drift settle in, saves viewport
## captures, then quits. Run:
##   godot --path . res://tools/page_shot_probe.tscn --resolution 400x866
## Shots land in OUT (created if missing).

const OUT := "C:/Users/SAIGOP~1/AppData/Local/Temp/claude/c--Users-SAI-GOPAL-OneDrive-Documents-2048/a48cd5da-fe32-43e9-bbff-da943152a570/scratchpad/shots"

var _t := 0.0
var _step := 0
var _current: Node
# [time, action, arg]
var _plan: Array = [
	[0.2, "open", "res://scenes/profile/profile.tscn"],
	[3.0, "shot", "profile"],
	[3.2, "open", "res://scenes/statistics/statistics.tscn"],
	[6.0, "shot", "statistics"],
	[6.4, "quit", ""],
]

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	# Pin the theme so shots are comparable run-to-run (_apply bypasses the gate).
	ThemeManager._apply("arctic")

func _process(delta: float) -> void:
	_t += delta
	while _step < _plan.size() and _t >= float(_plan[_step][0]):
		var kind := String(_plan[_step][1])
		var arg := String(_plan[_step][2])
		_step += 1
		match kind:
			"open":
				if is_instance_valid(_current):
					_current.queue_free()
				var scene: PackedScene = load(arg)
				_current = scene.instantiate()
				add_child(_current)
			"shot":
				var img := get_viewport().get_texture().get_image()
				var err := img.save_png("%s/%s.png" % [OUT, arg])
				print("SHOT ", arg, " err=", err)
			"quit":
				get_tree().quit()
