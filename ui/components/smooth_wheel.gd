class_name SmoothWheel
extends Node
## Glides mouse-wheel scrolling on a ScrollContainer. Godot's built-in wheel
## handling jumps the content in hard fixed steps — on the long menu pages
## (Home, Themes, Premium…) that discrete lurch reads as "the scrolling is
## choppy" however high the frame rate is. This node intercepts ONLY wheel
## events on its parent scroll and eases toward the accumulated target instead.
##
## Touch drag (the phone's scrolling) and scrollbar drags travel a different
## input path and are untouched — Android keeps the native inertial feel.
## Reduce-motion keeps the native stepped behaviour: no interception at all.
##
##   SmoothWheel.attach(scroll)   # after building a vertical ScrollContainer

## One wheel notch in px — matches the native step's reach (ScrollContainer
## scrolls 1/8 of a page per notch; menu pages are ~1700-2600px) so the glide
## covers the same ground per flick, just smoothly.
const STEP := 220.0

var _scroll: ScrollContainer
var _target := 0.0
var _pos := 0.0          # float mirror of scroll_vertical (which is int-quantised)
var _gliding := false

static func attach(scroll: ScrollContainer) -> void:
	var sw := SmoothWheel.new()
	sw._scroll = scroll
	scroll.add_child(sw)

func _ready() -> void:
	set_process(false)
	_scroll.gui_input.connect(_on_gui_input)

func _on_gui_input(e: InputEvent) -> void:
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	var dir := 0.0
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		dir = -1.0
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		dir = 1.0
	else:
		return
	var vbar := _scroll.get_v_scroll_bar()
	var span: float = maxf(vbar.max_value - vbar.page, 0.0)
	if span <= 0.0:
		return   # nothing to scroll — let the event pass (a parent may want it)
	if not _gliding:
		_target = float(_scroll.scroll_vertical)
	# factor carries precision-wheel deltas (trackpads); clicky wheels report ~1.
	_target = clampf(_target + dir * STEP * maxf(mb.factor, 1.0), 0.0, span)
	_pos = float(_scroll.scroll_vertical)
	_gliding = true
	set_process(true)
	_scroll.accept_event()   # keep ScrollContainer's own stepped handler out

func _process(delta: float) -> void:
	# If something else moved the scroll mid-glide (a drag, follow_focus, a
	# programmatic jump), yield immediately rather than fighting it.
	if absf(float(_scroll.scroll_vertical) - _pos) > 1.5:
		_stop()
		return
	# Exponential ease: brisk out of the notch, settling softly — the standard
	# frame-rate-independent glide.
	_pos = lerpf(_pos, _target, 1.0 - pow(0.002, delta))
	if absf(_pos - _target) < 0.5:
		_pos = _target
	_scroll.scroll_vertical = int(round(_pos))
	if _pos == _target:
		_stop()

func _stop() -> void:
	_gliding = false
	set_process(false)
