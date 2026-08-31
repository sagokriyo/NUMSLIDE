extends Control
## Studio intro — Sago Kriyo Games logo, fades in/out, then proceeds to Splash.

var _done := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# The wordmark carries its own type and tagline, so the screen is the art and
	# nothing else — the "SAGO KRIYO GAMES" / "crafted with passion" labels this
	# used to stack underneath now only repeat what the logo already says.
	var logo := TextureRect.new()
	var tex := load("res://assets/images/sagokriyo_logo.png") as Texture2D
	logo.texture = tex
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = _logo_size(tex)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(logo)

	# Home's scene graph costs ~400 ms to parse, and until now every millisecond of
	# it was paid AFTER the splash had faded to black — the player watched an empty
	# curtain for it. This screen is idle while its logo holds, so start the parse
	# on a worker thread now and let the splash→Home hand-off find a warm cache.
	# Purely a cache warm: routing, timings and the crossfade are untouched, and if
	# the load has not landed by the time the router asks, the engine joins the
	# worker task and we are exactly where we were before. See SceneRouter.warm().
	SceneRouter.warm(String(SceneRouter.Route["HOME"]))

	if bool(SettingsManager.get_value("reduce_motion")):
		# Reduced motion: no fades, just a short hold on the logo. Same guard after
		# the wait as the full-motion path below — see _hold().
		await _hold(1.2)
		if _done or not is_inside_tree(): return
		_advance()
		return
		
	modulate.a = 0.0
	var tw_in := create_tween()
	tw_in.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw_in.tween_property(self, "modulate:a", 1.0, 0.55)
	await tw_in.finished
	if _done or not is_inside_tree(): return
	await _hold(0.7)
	if _done or not is_inside_tree(): return
	var tw_out := create_tween()
	tw_out.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw_out.tween_property(self, "modulate:a", 0.0, 0.5)
	await tw_out.finished
	if _done or not is_inside_tree(): return
	_advance()

## The wordmark's on-screen box, fitted to whatever phone is holding it.
##
## Measured against the LIVE viewport rather than the 1080-wide design canvas:
## SceneRouter applies a content_scale_factor on top of the canvas_items stretch,
## so UI space is nearer 982 wide than 1080, and a hardcoded width sized off the
## design canvas would run the art under the screen edges. The cap keeps it from
## going comically wide on a tablet.
func _logo_size(tex: Texture2D) -> Vector2:
	if tex == null or tex.get_width() <= 0:
		return Vector2(720, 346)
	var w: float = minf(get_viewport_rect().size.x * 0.92, 980.0)
	return Vector2(w, w * float(tex.get_height()) / float(tex.get_width()))

func _input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventKey and event.pressed)
	if tapped:
		_advance()

func _advance() -> void:
	# Never latch _done while the router is mid-transition — goto() would drop
	# the request silently and this screen would be stranded with no retry.
	if _done or SceneRouter.is_busy():
		return
	_done = true
	SceneRouter.goto(SceneRouter.Route["SPLASH"])

## A hold that DIES WITH THIS NODE, used everywhere `_ready` waits.
##
## `get_tree().create_timer()` is owned by the SceneTree, so it keeps ticking
## after tap-to-skip (or any router navigation) has already freed this screen —
## and then resumes `_ready` into a dead instance, which the engine reports as
## "Resumed function '_ready()' after yield, but class instance is gone" (a plain
## ERROR, not a SCRIPT ERROR, so the regression gate never saw it). A tween
## created on this node is killed with the node instead, so `finished` simply
## never fires and the coroutine is abandoned cleanly. Callers still re-check
## `_done` / `is_inside_tree()` afterwards, for the case where we ARE still alive
## but already on our way out.
func _hold(sec: float) -> void:
	var tw := create_tween()
	tw.tween_interval(sec)
	await tw.finished
