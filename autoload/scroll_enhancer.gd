## ScrollEnhancer — makes every ScrollContainer in the app scroll from ANY
## point under the finger, with Godot's own inertia. Registered as an autoload
## in project.godot; no per-screen code.
##
## Why it exists: Godot's ScrollContainer only sees a touch drag whose press
## landed on a control that PASSES (or IGNORES) mouse input. Button,
## PanelContainer, Panel, ColorRect, ProgressBar, LineEdit and a bare Control
## all default to MOUSE_FILTER_STOP (Containers, ScrollContainer and TextureRect
## are PASS), so a page built from cards, pills and play circles is riddled
## with spots where a swipe does nothing at all — the press is swallowed and
## the container never starts its drag. The June-2026 version of this file
## papered over that with a momentum tween fired at finger LIFT, which is
## exactly why every swipe seemed to land half a second late (and, on the
## spots that did scroll, fought the native inertia: slide, stop, creep).
## tools/scroll_probe.tscn maps the dead spots per screen.
##
## Now: whenever a Control enters the tree it is checked — DEFERRED, so the
## builder's own filter choices (make_scroll_tappable, pass_through, an explicit
## STOP) are final by then — and if it sits inside a ScrollContainer and STOPs,
## it is switched to PASS. The control still receives every event first, so a
## Button still clicks and a card still taps; the drag simply reaches the scroll
## too, and the scroll cancels the child's press the moment the gesture becomes
## a scroll (NOTIFICATION_SCROLL_BEGIN → BaseButton drops its press attempt;
## UI.make_scroll_tappable listens to `scroll_started`). Momentum is the
## engine's: ScrollContainer decelerates at 1000 px/s² after the lift, like
## 2048. Never layer a kinetic tween over it again — two drivers on one
## scrollbar IS the "late" feel.
##
## Kept STOP (`owns_drag`): sliders / scrollbars / spin boxes drag their own
## value, LineEdit / TextEdit drag a selection, and anything carrying the
## `keep_stop` meta. Those are accepted dead bands (Settings › Audio's sliders).
##
## Limit: the filter is read when the node is ADDED (before its `_ready`); a
## widget that sets STOP in `_ready` is never revisited. Nothing in the repo does
## (the explicit STOP sites are `_init`-time or overwritten at once).
extends Node

## Set `control.set_meta(&"keep_stop", true)` on a widget that must keep the
## whole gesture (a custom slider, a swipe-to-dismiss row).
const KEEP_STOP_META := &"keep_stop"

## Finger travel (canvas px) before a drag counts as a scroll. Zero — Godot's
## default — meant a one-pixel wobble on a tap cancelled the Button under it now
## that buttons pass the press on. UI.make_scroll_tappable cancels its tap on
## `scroll_started`, i.e. at this same distance, whatever UI.TAP_SLOP says.
const DEADZONE := 14

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node is ScrollContainer:
		# Defer so the node is fully inside the tree before we touch its children.
		_enhance.call_deferred(node)
	elif node is Control and (node as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
		# Cheap pre-filter at add time; the real decision is made deferred, once
		# the builder has finished with the subtree.
		_unblock.call_deferred(node)

func _enhance(sc: ScrollContainer) -> void:
	if not is_instance_valid(sc):
		return
	if sc.scroll_deadzone == 0:
		sc.scroll_deadzone = DEADZONE
	# Disable follow_focus (prevents layout jumps when tapping cards).
	sc.follow_focus = false
	# Hide the vertical scrollbar where a screen left it visible (modal bodies
	# use SCROLL_MODE_AUTO): the pages are designed bar-less.
	var vsb := sc.get_v_scroll_bar()
	if vsb:
		var empty := StyleBoxEmpty.new()
		vsb.add_theme_stylebox_override("scroll", empty)
		vsb.add_theme_stylebox_override("scroll_focus", empty)
		vsb.add_theme_stylebox_override("grabber", empty)
		vsb.add_theme_stylebox_override("grabber_highlight", empty)
		vsb.add_theme_stylebox_override("grabber_pressed", empty)
		vsb.mouse_filter = Control.MOUSE_FILTER_IGNORE

## A STOP control inside a ScrollContainer becomes PASS, unless it owns its drag.
func _unblock(c: Control) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	if c.mouse_filter != Control.MOUSE_FILTER_STOP:
		return
	if owns_drag(c) or not _inside_scroll(c):
		return
	c.mouse_filter = Control.MOUSE_FILTER_PASS

## True for a widget that must keep the whole gesture. `Range` itself would be
## too broad — a ProgressBar is a Range and would become a dead band.
static func owns_drag(c: Control) -> bool:
	return c is Slider or c is ScrollBar or c is SpinBox or c is LineEdit or c is TextEdit \
		or c.has_meta(KEEP_STOP_META)

## True when a ScrollContainer sits between `c` and its canvas layer / window.
## A CanvasLayer boundary ends the walk: a modal or the nav bar hosted on its
## own layer is not "inside" the page scroll under it.
static func _inside_scroll(c: Control) -> bool:
	var n: Node = c.get_parent()
	while n != null:
		if n is ScrollContainer:
			return true
		if n is CanvasLayer or n is Viewport:
			return false
		n = n.get_parent()
	return false
