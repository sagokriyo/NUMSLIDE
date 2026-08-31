class_name ProductTile
extends Control
## ProductTile — a Shop product painted in the GAME'S OWN material.
##
## The storefront used to sell its consumables as 56pt line icons on a flat row,
## which is exactly what made the page read as a settings menu rather than a
## store. This paints each product as a real CandyFace glass tile — the same
## painter the board uses for a 512 — at a size where the material (rim, wet top
## band, diagonal streak) actually reads, with the product's glyph laid over the
## front face.
##
## `count` > 1 FANS the tile into a stack, so "3 x Another Try" is three tiles
## rather than the numeral 3 beside one icon. Quantity you can see beats quantity
## you have to read, and it costs no new art.
##
## Decorative only — never eats input, so the whole product card stays one hit
## target (see UI.make_scroll_tappable).

## Most tiles drawn in a fan. Past three the stack stops reading as "several" and
## starts reading as clutter, and the back tiles are almost entirely occluded.
const MAX_FAN := 3
## Seconds between catch-light sweeps on a hero tile.
const SWEEP_PERIOD := 6.0
## How long one sweep takes to cross the face.
const SWEEP_DUR := 1.1

var vivid: Color = Color(0.55, 0.62, 0.95)
var glyph: Texture2D = null
var count: int = 1
## Hero tiles sweep a travelling shine; grid tiles stay still. A page where
## everything glints at once reads as cheap, so this is opt-in per tile.
var shine: bool = false

var _t := 0.0
## -1 while resting, 0..1 while a sweep is crossing the face.
var _sweep := -1.0
var _acc := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	set_process(shine)
	queue_redraw()

## Call once after construction. `n` is the pack count (1 for a single product).
func setup(v: Color, g: Texture2D, n: int = 1, with_shine: bool = false) -> void:
	vivid = v
	glyph = g
	count = maxi(1, n)
	# See ThemeTileStrip: the sweep is ambient motion and reduce_motion turns it
	# off. The tile itself is unchanged.
	shine = with_shine and not bool(SettingsManager.get_value("reduce_motion"))
	set_process(shine and is_inside_tree())
	queue_redraw()

## The sweep steps at 30 Hz like every other ambient animation in the app — the
## band moves under a pixel per frame at 60, so a half-rate step is free.
func _process(delta: float) -> void:
	_acc += delta
	if _acc < 1.0 / 30.0:
		return
	var dt := _acc
	_acc = 0.0
	_t += dt
	if _sweep < 0.0:
		if _t >= SWEEP_PERIOD:
			_t = 0.0
			_sweep = 0.0
			queue_redraw()
		return
	_sweep += dt / SWEEP_DUR
	if _sweep > 1.0:
		_sweep = -1.0
	queue_redraw()

func _draw() -> void:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var fan: int = clampi(count, 1, MAX_FAN)
	var span := minf(s.x, s.y)
	# Each tile behind the front one steps up-and-right. The front face keeps the
	# control's centre regardless of how many sit behind it, so a 1-count tile and
	# a 3-count tile share a baseline and the grid stays optically aligned.
	var step := span * 0.085
	var hw := span * 0.5 - step * float(fan - 1)
	if hw <= 1.0:
		return
	var front := Vector2(s.x * 0.5, s.y * 0.5) \
		+ Vector2(-step, step) * (float(fan - 1) * 0.5)

	# Back to front: the deeper tiles haze toward the backdrop so the stack reads
	# with aerial depth instead of as three flat stickers (same rule as GlassDrift).
	var bg: Color = ThemeManager.color("bg0")
	for i in range(fan - 1, -1, -1):
		var c := front + Vector2(step, -step) * float(i)
		var tint: Color = vivid if i == 0 else vivid.lerp(bg, 0.22 * float(i))
		CandyFace.draw_face_soft(self, c, hw, tint, true)

	if glyph != null:
		# The glyph rides the FRONT face only, at a size that leaves the tile's rim
		# and top band visible — the material is half the point of drawing it big.
		# Sized generously: these are line icons drawn over a saturated glass face,
		# and a small one loses against the face's own rim and streak.
		var box := hw * 1.24
		draw_texture_rect(glyph, Rect2(front - Vector2.ONE * box * 0.5,
			Vector2.ONE * box), false)

	if shine and _sweep >= 0.0:
		CandyFace.draw_shine_band(self, front, hw, _sweep, 0.26)
