class_name TileView
extends Control
## TileView — one numbered tile on the tray: a slab of the same edge-lit glass
## every piece in the app is made of, with its number cut into it.
##
## The node itself is the ANIMATED holder (slide, settle, lock, shatter); the
## `Face` child does all the drawing. Never tween a node that draws: it
## re-records its draw list every frame. Position is the exception the engine
## allows — moving a Control does not queue a redraw — so the slide itself rides
## on this node and only the squash rides on the holder's scale.
##
## THE COLOUR IS THE HOME ROW. A tile's hue is not its number, it is the ROW the
## number belongs to, taken off the theme's own tile ramp. So a solved board
## reads as clean horizontal bands of colour, and a tile sitting in the wrong
## band is visible from across the room without reading a single numeral. On the
## cube the same idea runs on faces instead of rows, which is what makes a tile
## that has been pushed over an edge findable at all.

## The number painted on the tile. Not always the internal value: the cube
## numbers 1 to 8 per face and tells the faces apart by colour.
var number: int = 0
## The rung of the theme's tile ramp this tile draws its colour from.
var ramp_value: int = 2
## 0 hidden, 1 fully lit. Blind fades the numeral out, never the glass.
var numeral_alpha: float = 1.0
## Welded down (Lockdown). Draws a seal instead of a lift.
var locked := false
## Sitting in its own cell.
var home := false
## The helpline is pointing at this one.
var hinted := false

var _face: Face
var _pivot: Control
var _pulse: Tween

## Seconds one slide takes. Read through DesignSystem so the player's tile-speed
## setting reaches the board.
static func slide_dur() -> float:
	return DesignSystem.tile_move_dur() * 2.2

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ANCHORED, not sized by hand. The holder's size is written by the tray, and
	# a plain `size = size` assignment only notifies when the value CHANGES — so
	# a tile built at the right size and then handed the same number again never
	# fired a resize, its drawing child stayed at zero, and the board came up as
	# an empty tray of sockets. Full-rect anchors make the child follow the
	# holder whatever route the size arrives by.
	_pivot = Control.new()
	_pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pivot.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_pivot)
	_face = Face.new()
	_face.owner_tile = self
	_face.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pivot.add_child(_face)

func _ready() -> void:
	_layout()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()

## Keeps the scale pivot on the tile's middle. The sizes themselves ride on the
## anchors set in _init.
func _layout() -> void:
	if _pivot == null:
		return
	_pivot.pivot_offset = size * 0.5
	_face.pivot_offset = size * 0.5
	_face.queue_redraw()

## Repaints after a value, a theme or a state change.
func restyle() -> void:
	if _face != null:
		_face.queue_redraw()

## Slides to `to` over the house duration and settles with a small squash along
## the direction of travel. Returns the tween so a caller can await it.
func slide_to(to: Vector2, dur: float = -1.0) -> Tween:
	var seconds := dur if dur > 0.0 else slide_dur()
	var t := create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(self, "position", to, seconds)
	if not DesignSystem.reduce_motion():
		var travel := to - position
		var squash := Vector2(1.06, 0.94) if absf(travel.x) > absf(travel.y) else Vector2(0.94, 1.06)
		t.parallel().tween_property(_pivot, "scale", squash, seconds * 0.45)
		t.chain().tween_property(_pivot, "scale", Vector2.ONE, seconds * 0.55) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return t

## Drops in from nothing. The opening deal and Rush's re-deal.
func appear(delay: float = 0.0) -> void:
	if DesignSystem.reduce_motion():
		_pivot.scale = Vector2.ONE
		modulate.a = 1.0
		return
	_pivot.scale = Vector2.ONE * DesignSystem.TILE_SPAWN_SCALE
	modulate.a = 0.0
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_property(self, "modulate:a", 1.0, DesignSystem.DUR_FAST)
	t.parallel().tween_property(_pivot, "scale", Vector2.ONE, DesignSystem.tile_spawn_dur() * 2.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Fades out and frees itself. The tile that wraps off the edge, and the board
## coming apart at the end of a Rush.
func vanish(delay: float = 0.0) -> void:
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_property(self, "modulate:a", 0.0, DesignSystem.DUR_FAST)
	if not DesignSystem.reduce_motion():
		t.parallel().tween_property(_pivot, "scale", Vector2.ONE * 0.7, DesignSystem.DUR_FAST)
	t.tween_callback(queue_free)

## The one-beat flash a tile gives when it lands home.
func flash_home() -> void:
	home = true
	restyle()
	if DesignSystem.reduce_motion():
		return
	var t := create_tween()
	t.tween_property(_pivot, "scale", Vector2.ONE * 1.10, DesignSystem.DUR_INSTANT) \
		.set_trans(Tween.TRANS_SINE)
	t.tween_property(_pivot, "scale", Vector2.ONE, DesignSystem.DUR_BASE) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## The seal that closes over a tile Lockdown has welded.
func seal() -> void:
	locked = true
	restyle()
	if DesignSystem.reduce_motion():
		return
	var t := create_tween()
	t.tween_property(_pivot, "scale", Vector2.ONE * 0.90, DesignSystem.DUR_FAST) \
		.set_trans(Tween.TRANS_CUBIC)
	t.tween_property(_pivot, "scale", Vector2.ONE, DesignSystem.DUR_SLOW) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## The slow breath the hinted tile keeps until it is played.
func set_hinted(on: bool) -> void:
	if hinted == on:
		return
	hinted = on
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
		_pulse = null
	_pivot.scale = Vector2.ONE
	restyle()
	if not on or DesignSystem.reduce_motion():
		return
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_pivot, "scale", Vector2.ONE * 1.05, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse.tween_property(_pivot, "scale", Vector2.ONE, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## The refusal a locked tile gives when it is tapped: a short shove, no move.
func refuse() -> void:
	if DesignSystem.reduce_motion():
		return
	var t := create_tween()
	t.tween_property(_pivot, "position:x", 5.0, 0.045).set_trans(Tween.TRANS_SINE)
	t.tween_property(_pivot, "position:x", -4.0, 0.06).set_trans(Tween.TRANS_SINE)
	t.tween_property(_pivot, "position:x", 0.0, 0.05).set_trans(Tween.TRANS_SINE)

# --- The drawing child ------------------------------------------------------------

class Face extends Control:
	var owner_tile: TileView

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var t := owner_tile
		if t == null or size.x <= 2.0:
			return
		var hw := size.x * 0.5
		var centre := size * 0.5
		var vivid := CandyFace.color(t.ramp_value)
		# A tile still looking for its cell sits a shade back, so the ones that
		# are home read as the finished part of the picture.
		if not t.home:
			vivid = vivid.lerp(ThemeManager.color("surface"), 0.10)
		CandyFace.draw_face(self, centre, hw, vivid)

		if t.locked:
			# The weld: a bright ring hugging the tile, and the glass behind the
			# numeral lifted, so a locked tile reads as finished rather than dead.
			var seal_col := ThemeManager.color("accent").lerp(Color(1, 1, 1), 0.45)
			draw_arc(centre, hw * 0.92, 0.0, TAU, 48,
				Color(seal_col.r, seal_col.g, seal_col.b, 0.75), maxf(2.0, hw * 0.055), true)
		elif t.hinted:
			var hint_col := Color(1, 1, 1)
			draw_arc(centre, hw * 0.90, 0.0, TAU, 48,
				Color(hint_col.r, hint_col.g, hint_col.b, 0.85), maxf(2.5, hw * 0.06), true)

		if t.numeral_alpha <= 0.01 or t.number <= 0:
			return
		var font: Font = ThemeManager.tile_font_heavy
		if font == null:
			font = ThemeManager.tile_font
		if font == null:
			font = get_theme_default_font()
		var label := str(t.number)
		# Three digits have to fit the same box one does, so the size steps down
		# with the digit count rather than overflowing the glass.
		var px := int(hw * (1.05 if label.length() <= 1 else (0.86 if label.length() == 2 else 0.66)))
		var ink := CandyFace.text_color(vivid)
		ink.a = t.numeral_alpha
		var measured := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, px)
		var at := centre - Vector2(measured.x * 0.5, 0.0) + Vector2(0.0, measured.y * 0.32)
		# The numeral's own shadow, so it sits IN the glass rather than on it.
		draw_string(font, at + Vector2(0.0, maxf(1.0, hw * 0.035)), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.22 * t.numeral_alpha))
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, px, ink)
