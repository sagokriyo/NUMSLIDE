extends Node
## Perf probe — boots a real gameplay session, plays it automatically, and prints
## Godot's own performance monitors once a second.
##
## Answers the two questions a raw FPS number can't: is the cost CPU or GPU, and
## is it STEADY or GROWING (a node/tween leak shows up as a rising object count
## and a frame time that creeps as the session goes on).
##
##   & <godot> --path . res://tools/perf_probe.tscn --resolution 540x1170
##
## Env knobs: PERF_MODE (default "classic"), PERF_SECONDS (default 45),
## PERF_MOVE_EVERY (seconds between injected swipes, default 0.5; 0 = idle),
## PERF_ROUTE (route name, e.g. "SETTINGS" — measures that screen idle instead
## of gameplay), PERF_UNCAP=1 (vsync off, so fps reflects raw headroom instead
## of the monitor's refresh — the way to see a GPU-cost change on desktop).

const REPORT_EVERY := 1.0

var _mode := "classic"
var _seconds := 45.0
var _move_every := 0.5

func _ready() -> void:
	var m := OS.get_environment("PERF_MODE")
	if m != "":
		_mode = m
	var s := OS.get_environment("PERF_SECONDS")
	if s != "":
		_seconds = float(s)
	var mv := OS.get_environment("PERF_MOVE_EVERY")
	if mv != "":
		_move_every = float(mv)
	if OS.get_environment("PERF_UNCAP") == "1":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	# The sampler lives on the tree ROOT so it survives the scene change into
	# gameplay (this probe scene is the current scene and gets freed by goto()).
	var sampler := Sampler.new()
	sampler.seconds = _seconds
	sampler.move_every = _move_every
	sampler.mode_id = _mode
	get_tree().root.add_child.call_deferred(sampler)

	await get_tree().process_frame
	var route := OS.get_environment("PERF_ROUTE")
	if not route.is_empty():
		sampler.move_every = 0.0   # menu screens are measured idle, never swiped
		SceneRouter.goto(SceneRouter.Route[route])
		return
	SceneRouter.goto(SceneRouter.Route["GAMEPLAY"], {"mode": _mode, "continue": false})

## Samples the monitors and drives synthetic play from outside the scene tree's
## churn, so nothing it measures is an artefact of the probe's own scene.
class Sampler extends Node:
	var seconds := 45.0
	var move_every := 0.5
	var mode_id := "classic"

	var _t := 0.0
	var _report_t := 0.0
	var _move_t := 0.0
	var _dirs: Array[Key] = [KEY_LEFT, KEY_UP, KEY_RIGHT, KEY_DOWN]
	var _i := 0
	var _worst := 0.0
	var _first_objects := 0
	var _settled := false

	func _process(delta: float) -> void:
		_t += delta
		_report_t += delta
		_move_t += delta

		if move_every > 0.0 and _move_t >= move_every:
			_move_t = 0.0
			_swipe()

		# Ignore the first second: scene build + shader compile are one-off costs
		# and would otherwise dominate the "worst frame" figure.
		if _t > 1.0:
			if not _settled:
				_settled = true
				_first_objects = int(Performance.get_monitor(Performance.OBJECT_COUNT))
			_worst = maxf(_worst, delta)

		if _report_t >= REPORT_EVERY:
			_report_t = 0.0
			_report()

		if _t >= seconds:
			_summary()
			get_tree().quit()

	func _swipe() -> void:
		var ev := InputEventKey.new()
		ev.keycode = _dirs[_i % _dirs.size()]
		ev.physical_keycode = ev.keycode
		ev.pressed = true
		_i += 1
		Input.parse_input_event(ev)

	func _report() -> void:
		print("t=%5.1fs fps=%3d frame=%5.2fms proc=%5.2fms phys=%5.2fms | draw=%4d prims=%7d | objs=%5d nodes=%5d orphans=%4d | vram=%6.1fMB mem=%6.1fMB" % [
			_t,
			int(Performance.get_monitor(Performance.TIME_FPS)),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
				+ Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		])
		print("        fx subtrees: %s" % _fx_breakdown())

	## Recursive descendant count of every BoardFx in the live scene, so growth can
	## be attributed to a specific ambience layer rather than "the scene".
	func _fx_breakdown() -> String:
		var cur := get_tree().current_scene
		if cur == null:
			return "(no scene)"
		var found: Array[Node] = []
		_collect_fx(cur, found)
		var parts: Array[String] = []
		for n in found:
			parts.append("%s=%d" % [n.name, _descendants(n)])
		return ", ".join(parts) if not parts.is_empty() else "(none)"

	func _collect_fx(n: Node, out: Array[Node]) -> void:
		if n is BoardFx:
			out.append(n)
		for c in n.get_children():
			_collect_fx(c, out)

	func _descendants(n: Node) -> int:
		var total := 0
		for c in n.get_children():
			total += 1 + _descendants(c)
		return total

	func _summary() -> void:
		var objs := int(Performance.get_monitor(Performance.OBJECT_COUNT))
		print("---- SUMMARY (%s, reduce_motion=%s, theme=%s) ----" % [
			mode_id,
			bool(SettingsManager.get_value("reduce_motion")),
			ThemeManager.current_id()])
		print("worst frame after warmup: %.2f ms  (a 60fps budget is 16.7 ms)" % (_worst * 1000.0))
		print("object count: %d -> %d  (drift %+d)" % [_first_objects, objs, objs - _first_objects])
