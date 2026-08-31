class_name BallBakery
extends Node
## Bakes Merge Drop's ball skin — `CandyFace.draw_ball` plus the numeral — into ONE
## texture per (value, tint), so a ball in play costs a single textured quad.
##
## WHY. `draw_ball` is a stack of ~13 vector commands (three different textures, four
## `draw_arc` polylines, two gradient polygons, three glow quads) and the numeral adds
## another. Every one of them is re-submitted every frame, and re-BUILT every frame a
## ball is rolling (the skin counter-rotates, so the command list is rotation-
## dependent). Measured on a 24-ball pile: the balls were **552 of the frame's 958
## draw calls**, on a frame that is main-thread bound — and RULES 11.2 puts draw
## submissions ahead of everything else as the Android currency.
##
## HOW. The skin is rendered once into a SubViewport sized to the ball's exact
## on-screen footprint, so the bake is 1:1 with what the vector path drew — same
## painter, same textures, same order, no reinterpretation. Compositing layers onto a
## transparent target yields PREMULTIPLIED alpha, so the ball draws the result with a
## `BLEND_MODE_PREMULT_ALPHA` material; that is also why the numeral is baked IN
## rather than drawn over the quad, which would blend it as if it were premultiplied
## and fringe every glyph edge.
##
## Balls fall back to the live vector path until their bake lands (one frame), so a
## ball never waits on the bakery to appear.

## value -> ImageTexture. Cleared wholesale on a theme change: the key is a value, and
## the same value wears a different colour in every palette.
var _cache: Dictionary = {}
var _pending: Dictionary = {}      # value -> true while its bake is in flight
var _tint: Dictionary = {}         # value -> the Color the cached bake was made with

func _init() -> void:
	name = "BallBakery"

## The baked skin for `value`, or null if it is not ready yet (the caller draws the
## vector path meanwhile). Kicks off the bake on the first miss, and again if the
## theme has moved the colour under us.
func skin(value: int, radius: float, fill: Color, text_col: Color, font: Font) -> Texture2D:
	var cached_tint: Color = _tint.get(value, Color(0, 0, 0, 0))
	if _cache.has(value) and cached_tint == fill:
		return _cache[value]
	if not _pending.has(value):
		_pending[value] = true
		_bake(value, radius, fill, text_col, font)
	return null

## Drops every bake. Called when the palette changes — every entry is now the wrong
## colour, and the textures are the only thing holding that memory.
func clear() -> void:
	_cache.clear()
	_tint.clear()

func _bake(value: int, radius: float, fill: Color, text_col: Color, font: Font) -> void:
	# The halo is the widest layer draw_ball paints: centre +/- radius * 1.55.
	var extent := radius * BallSkin.FOOTPRINT * 0.5
	var side := int(ceil(extent * 2.0))
	if side <= 0 or side > 2048:
		_pending.erase(value)
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(side, side)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := BallSkin.new()
	painter.radius = radius
	painter.fill = fill
	painter.text_col = text_col
	painter.font = font
	painter.value = value
	painter.position = Vector2(extent, extent)
	vp.add_child(painter)
	add_child(vp)
	# One full draw of the target, then read it back. This runs once per value per
	# theme, behind the screen's own build, never during a drop.
	await RenderingServer.frame_post_draw
	if not is_instance_valid(vp):
		_pending.erase(value)
		return
	var img := vp.get_texture().get_image()
	vp.queue_free()
	_pending.erase(value)
	if img == null or img.is_empty():
		return
	_cache[value] = ImageTexture.create_from_image(img)
	_tint[value] = fill

## The painter that runs inside the bake target: the SAME CandyFace call the live
## balls used to make, drawn at the origin of a footprint-sized canvas.
class BallSkin extends Node2D:
	## Total bake width as a multiple of the radius — draw_ball's halo reaches
	## +/- 1.55r, so 3.1r covers every layer it paints.
	const FOOTPRINT := 3.1

	var radius: float = 24.0
	var fill: Color = Color.WHITE
	var text_col: Color = Color.BLACK
	var font: Font
	var value: int = 2

	func _draw() -> void:
		CandyFace.draw_ball(self, Vector2.ZERO, radius, fill)
		if font == null:
			return
		# The same numeral geometry NumberBody._blit_number lays down (size_ref =
		# radius, base 1.20, 0.16 per extra character, no outline), kept here so the
		# baked ball and a fallback-drawn ball are the same picture.
		var s := str(value)
		var fscale := clampf(1.20 - 0.16 * float(s.length() - 1), 0.5, 1.20)
		var fs := int(clampf(radius * fscale, 16.0, 130.0))
		var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var y := (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
		font.draw_string(get_canvas_item(), Vector2(-w * 0.5, y), s,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_col)
