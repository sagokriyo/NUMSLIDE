class_name FxClip
extends Control
## A clipping WINDOW that confines a full-screen BoardFx to the board's rect.
## BoardFx deliberately lays itself out in SCREEN space sized to the viewport
## (see board_fx.gd _ready); this container follows `target` every frame and
## keeps the fx counter-offset so that layout is untouched — the board simply
## becomes a window onto the ambience, and the rest of the screen stays clean.
## Reward-fx global-position math is unaffected: the fx's global origin stays
## at the screen origin.

var target: Control          # the board rect to follow (field / case / arena)
var fx: BoardFx
var local_rect: Callable     # optional: a sub-rect of target, in target-local space

func _init(p_fx: BoardFx, p_target: Control = null, p_local_rect: Callable = Callable()) -> void:
	fx = p_fx
	target = p_target
	local_rect = p_local_rect
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx)

var _last_rect := Rect2(Vector2.INF, Vector2.ZERO)   # last applied window — gates the writes

func _process(_delta: float) -> void:
	if not (is_instance_valid(target) and is_instance_valid(fx)):
		return
	var r := target.get_global_rect()
	if local_rect.is_valid():
		var lr: Rect2 = local_rect.call()
		r = Rect2(r.position + lr.position, lr.size)
	# The board rect is static for whole minutes of play; re-writing the same
	# position/size dirtied this control's AND the fx subtree's transforms every
	# frame for nothing (the same guard home.gd's parallax uses).
	if r.is_equal_approx(_last_rect):
		return
	_last_rect = r
	global_position = r.position
	size = r.size
	fx.position = -r.position
