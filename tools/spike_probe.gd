extends Node
## Spike attribution probe — boots a route, idles on it, and on every frame that
## runs long prints WHERE the time went: the SceneTree process step (scripts,
## tweens, timers) versus everything else (render submit, GPU wait, present),
## plus what CHANGED that frame — objects, nodes, resources, live tweens, static
## memory, video memory. A spike that lands with a VRAM jump is a texture
## upload or a buffer realloc; one with a node jump is a spawner; one that is
## all TIME_PROCESS with nothing else moving is a script doing a lot of work;
## one with a small TIME_PROCESS is the renderer or the driver.
##
## Frame time is measured with the wall clock (Time.get_ticks_usec) between
## consecutive _process calls, NOT `delta` — delta smoothing can round a spike
## away or spread it over its neighbours.
##
##   & <godot> --path . res://tools/spike_probe.tscn --resolution 540x1170
##
## Env: PERF_ROUTE (default "HOME"), PERF_SECONDS (default 14),
##      PERF_THEME (palette id, applied via ThemeManager._apply — probe-only),
##      PERF_STAGE (0..N — strip the decorative subsystems CUMULATIVELY up to
##      that stage right after the route settles, perf_bisect's pattern, so the
##      stage where the spikes vanish names the cost; see Sampler.STAGES),
##      PERF_QUIET=1 (print only the summary).

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var theme := OS.get_environment("PERF_THEME")
	if not theme.is_empty():
		ThemeManager._apply(theme)
	var s := Sampler.new()
	s.seconds = 14.0
	var secs := OS.get_environment("PERF_SECONDS")
	if not secs.is_empty():
		s.seconds = float(secs)
	var st := OS.get_environment("PERF_STAGE")
	if not st.is_empty():
		s.stage = int(st)
	s.quiet = OS.get_environment("PERF_QUIET") == "1"
	get_tree().root.add_child.call_deferred(s)
	await get_tree().process_frame
	var route := OS.get_environment("PERF_ROUTE")
	if route.is_empty():
		route = "HOME"
	SceneRouter.goto(SceneRouter.Route[route])

class Sampler extends Node:
	const SETTLE := 3.0
	const STAGES := [
		"baseline (everything on)",
		"BoardFx particles frozen",
		"BoardFx freed",
		"ExtrudedWord animate=false",
		"ExtrudedWord hidden",
		"screen _process off",
		"all tweens killed",
		"GlassDrift freed",
		"TierBadge / BadgePortrait hidden",
		"previews hidden (ThemePreview/SessionPreview/MiniBoard/TileStrip/ProductTile)",
		"Confetti freed",
	]
	var seconds := 14.0
	var stage := 0
	var quiet := false
	var _t := 0.0
	var _applied := false
	var _last_usec := 0
	var _deltas: Array[float] = []
	var _procs: Array[float] = []
	var _prev: Dictionary = {}
	var _spike_times: Array[float] = []

	func _snap() -> Dictionary:
		return {
			"obj": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			"node": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"res": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
			"orph": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
			"mem": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
			"vram": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
			"tex": int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
			"buf": int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)),
			"draw": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"prim": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			"tw": get_tree().get_processed_tweens().size(),
		}

	func _process(delta: float) -> void:
		_t += delta
		var now_usec := Time.get_ticks_usec()
		var ms := float(now_usec - _last_usec) / 1000.0
		_last_usec = now_usec
		var now := _snap()
		if _t < SETTLE:
			if _t >= SETTLE - 0.6 and not _applied:
				_applied = true
				_apply_upto(stage)
			_prev = now
			return
		var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_deltas.append(ms)
		_procs.append(proc)
		var med := _pct(_deltas, 0.5) if _deltas.size() > 30 else 4.0
		if ms > maxf(12.0, med * 2.5):
			_spike_times.append(_t)
			var gap := 0.0
			if _spike_times.size() >= 2:
				gap = _spike_times[-1] - _spike_times[-2]
			if not quiet:
				print("SPIKE t=%6.2fs (+%4.2fs) frame=%6.2fms proc=%6.2fms phys=%5.2fms | draw=%d prim=%d tw=%d(%+d) obj%+d node%+d res%+d orph=%d mem%+dK vram%+dK tex%+dK buf%+dK" % [
					_t, gap, ms, proc, phys,
					now["draw"], now["prim"], now["tw"], now["tw"] - _prev["tw"],
					now["obj"] - _prev["obj"], now["node"] - _prev["node"],
					now["res"] - _prev["res"], now["orph"],
					(now["mem"] - _prev["mem"]) / 1024, (now["vram"] - _prev["vram"]) / 1024,
					(now["tex"] - _prev["tex"]) / 1024, (now["buf"] - _prev["buf"]) / 1024])
		_prev = now
		if _t >= SETTLE + seconds:
			_report()
			get_tree().quit()

	func _pct(a: Array[float], p: float) -> float:
		var s := a.duplicate()
		s.sort()
		return s[clampi(int(float(s.size() - 1) * p), 0, s.size() - 1)]

	func _report() -> void:
		var over := 0
		for d in _deltas:
			if d > 16.7:
				over += 1
		print("SUMMARY stage=%d [%s] frames=%d frame p50=%.2f p95=%.2f p99=%.2f max=%.2f | >16.7ms=%d (%.1f%%) | proc p50=%.2f p95=%.2f max=%.2f | spikes=%d" % [
			stage, STAGES[stage], _deltas.size(), _pct(_deltas, 0.5), _pct(_deltas, 0.95),
			_pct(_deltas, 0.99), _pct(_deltas, 1.0), over,
			100.0 * float(over) / float(maxi(_deltas.size(), 1)),
			_pct(_procs, 0.5), _pct(_procs, 0.95), _pct(_procs, 1.0),
			_spike_times.size()])
		var top := _deltas.duplicate()
		top.sort()
		top.reverse()
		var top_s := ""
		for i in mini(8, top.size()):
			top_s += "%.1f " % top[i]
		print("TOP frames ms: " + top_s)

	# --- Stripping (cumulative, perf_bisect's pattern) ---------------------------

	func _apply_upto(n: int) -> void:
		var scene := get_tree().current_scene
		if scene == null:
			return
		for s in range(1, n + 1):
			_apply(s, scene)
		print("STRIPPED up to stage %d [%s]" % [n, STAGES[n]])

	func _apply(s: int, scene: Node) -> void:
		match s:
			1:
				for fx in _find(scene, "BoardFx"):
					for nd in _all(fx):
						if nd is CPUParticles2D:
							(nd as CPUParticles2D).emitting = false
							(nd as CPUParticles2D).set_process_internal(false)
							(nd as CPUParticles2D).visible = false
			2:
				for nd in _find(scene, "BoardFx"):
					nd.queue_free()
			3:
				for nd in _find(scene, "ExtrudedWord"):
					nd.set("animate", false)
			4:
				for nd in _find(scene, "ExtrudedWord"):
					(nd as CanvasItem).visible = false
					nd.set_process(false)
			5:
				scene.set_process(false)
			6:
				for tw in get_tree().get_processed_tweens():
					tw.kill()
			7:
				for nd in _find(scene, "GlassDrift"):
					nd.queue_free()
			8:
				for k in ["TierBadge", "BadgePortrait"]:
					for nd in _find(scene, k):
						(nd as CanvasItem).visible = false
						nd.set_process(false)
			9:
				for k in ["ThemePreview", "SessionPreview", "MiniBoard", "TileStrip", "ProductTile"]:
					for nd in _find(scene, k):
						(nd as CanvasItem).visible = false
						nd.set_process(false)
			10:
				for nd in _find(scene, "Confetti"):
					nd.queue_free()

	func _find(root: Node, klass: String) -> Array[Node]:
		var out: Array[Node] = []
		for n in _all(root):
			if n.get_script() != null and n.is_class("Control"):
				var s: Script = n.get_script()
				while s != null:
					if s.get_global_name() == klass:
						out.append(n)
						break
					s = s.get_base_script()
		return out

	func _all(root: Node) -> Array[Node]:
		var out: Array[Node] = []
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			out.append(n)
			for c in n.get_children():
				stack.append(c)
		return out
