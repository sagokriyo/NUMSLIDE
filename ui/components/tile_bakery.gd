class_name TileBakery
extends Node
## Bakes Fling's square glass tile — `CandyFace.draw_face` plus the numeral — into
## ONE texture per value, so a tile in play costs a single textured quad.
##
## WHY. `_glass_face` is a stack of ~14 vector commands: three different textures
## (the rounded mask, the halo, the glow dot), seven masked gradient polygons,
## two-to-three antialiased `draw_circle` speculars, and the numeral on top. Every
## one is re-submitted every frame.
##
## Worse than the raw count: the textures INTERLEAVE. Mask, glow dot, font atlas,
## halo, mask again — per tile — which is the exact pattern that defeats canvas
## batching (see the menu-glint work). One quad per tile, with every tile of the
## same value sharing one texture, batches instead.
##
## MEASURED with tools/fling_perf_probe.gd, one frozen 40-tile fixture, both
## builds rendering the identical picture (FLING_NO_BAKE=1 selects the old path):
##
##   live vector   813 draw calls   23,858 primitives   per frame
##   baked         185 draw calls    2,244 primitives   per frame
##
## and the marginal cost of a tile fell from ~16 draw calls to ~0.7 (158 calls at
## 1 tile, 164 at 10, 185 at 40 — the rest of the screen is the ~158 floor). RULES
## 11.2 puts draw submissions ahead of everything else as the Android currency,
## and the arena now runs nearer its tile cap than it used to, because the feed no
## longer stops for a full board.
##
## HOW. The skin renders once into a SubViewport sized to the tile's exact
## on-screen footprint, so the bake is 1:1 with what the vector path drew — same
## painter, same textures, same order, no reinterpretation. Compositing layers
## onto a transparent target yields PREMULTIPLIED alpha, so the tile draws the
## result through a `BLEND_MODE_PREMULT_ALPHA` material; that is also why the
## numeral is baked IN rather than drawn over the quad, which would blend it as
## if it were premultiplied and fringe every glyph edge.
##
## Tiles fall back to the live vector path until their bake lands (one frame), so
## a tile never waits on the bakery to appear — and `baked` fires when it does,
## which is NOT optional. `_draw` only re-runs on `queue_redraw()`, and a Fling
## tile has no reason to redraw once it is on screen: rotation is locked and the
## face never animates. Without this signal every tile that missed on its first
## frame stayed on the vector path for the rest of the run, and the bakery
## quietly did nothing — 549 draw calls against 813 for the pure vector path,
## where the finished thing measures 185. (Merge Drop's balls hide the same
## hazard: they counter-rotate, so they redraw every frame and pick up their bake
## by accident.)
##
## RELATED: [BallBakery] does the identical job for Merge Drop's spheres, with the
## same rationale and the same premultiplied-alpha contract. The two are separate
## classes because they bake genuinely different skins — a different painter, a
## different footprint rule and a different numeral scale — but the SubViewport
## plumbing between them is the same thirty lines, and they should be folded onto
## one shared base the next time either is touched. They were left apart here
## only because Merge Drop had uncommitted work in flight at the time.

## Total bake width as a multiple of the tile's half-extent. `_glass_face` paints
## its ambient halo at `hw / CandyFace._HALO_Q` (0.62), reaching +/-1.613 hw —
## the widest layer by some margin, and the one that sets this number. The
## contact shadow, the corner gleam and the specular all sit inside it.
##
## Nothing is drawn on a tile beyond the bake: the match glow that used to ride
## on same-value tiles during a drag is gone, so a baked tile is one quad.
const FOOTPRINT := 3.24

## Half the side the bake is BOTH authored at and drawn at, in design units.
##
## The rounding is the point, and it is shared rather than repeated: a texture is
## a whole number of texels, so the bake target is `ceil`ed — and if the quad were
## then drawn at the raw fractional `hw * FOOTPRINT`, the texture would be
## stretched by up to a texel across the tile and every edge in it would resample.
## Asking both sides for this one number makes the blit 1:1 wherever the canvas
## itself is 1:1, which is the case on the phone. Measured on a fixed eight-tile
## board, baked against live-vector: the rounding alone was most of the residual
## edge difference between them.
static func footprint_half(hw: float) -> float:
	return ceilf(hw * FOOTPRINT) * 0.5

## Fired once per value when its texture lands, so the tiles wearing that value
## can redraw onto it. Also fired by clear(), because dropping the cache puts
## every tile back on the vector path until the bakes are redone.
signal baked(value: int)

## value -> ImageTexture. Cleared wholesale on a theme change: the key is a value,
## and the same value wears a different colour in every palette.
var _cache: Dictionary = {}
var _pending: Dictionary = {}      # value -> true while its bake is in flight
var _tint: Dictionary = {}         # value -> the Color the cached bake was made with
var _half: Dictionary = {}         # value -> the half-extent it was baked at
## Every value a bake was ever KICKED for, kept across clear(). A headless run
## never lands a bake (the dummy rasterizer reads back nothing), so this is how a
## test proves the arena asked for a skin before a fusion needed it, which is the
## whole point of fling.gd's warm ladder.
var requested: Dictionary = {}

## The ONE premultiplied-alpha material every baked tile wears.
##
## It is shared on purpose. A CanvasItemMaterial per tile is a distinct RID, and
## the canvas renderer breaks a batch on every material change — so forty tiles
## each holding their own copy of an identical material would cost forty state
## switches per frame and batch with nothing, giving back much of what the bake
## just won. (Merge Drop's blobs still mint one each; that is worth folding in
## when BallBakery and this one are merged.)
static var _premult: CanvasItemMaterial

## Lazily built, then handed to every tile. Static because the arena can rebuild
## its bakery (a theme change clears the cache, not the material) and because the
## point of it is that there is exactly one.
static func premult_material() -> CanvasItemMaterial:
	if _premult == null:
		_premult = CanvasItemMaterial.new()
		_premult.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	return _premult

func _init() -> void:
	name = "TileBakery"

## The baked skin for `value`, or null if it is not ready yet (the caller draws
## the vector path meanwhile). Kicks off the bake on the first miss, and again if
## the theme has moved the colour — or a relayout has moved the SIZE — under us.
## The size check matters here in a way it does not for a ball: `fling.gd::_half`
## clamps against the field width, so a rotation or a tablet split re-sizes every
## tile, and a stale bake would be drawn stretched.
func skin(value: int, hw: float, vivid: Color, text_col: Color, font: Font) -> Texture2D:
	if _cache.has(value) \
			and Color(_tint.get(value, Color(0, 0, 0, 0))) == vivid \
			and absf(float(_half.get(value, 0.0)) - hw) < 0.5:
		return _cache[value]
	if not _pending.has(value):
		_pending[value] = true
		requested[value] = true
		_bake(value, hw, vivid, text_col, font)
	return null

## Drops every bake. Called when the palette changes — every entry is now the
## wrong colour, and the textures are the only thing holding that memory.
func clear() -> void:
	_cache.clear()
	_tint.clear()
	_half.clear()
	baked.emit(0)   # 0 = "all of them": every tile is back on the vector path

func _bake(value: int, hw: float, vivid: Color, text_col: Color, font: Font) -> void:
	var extent := footprint_half(hw)
	var side := int(extent * 2.0)
	if side <= 0 or side > 2048:
		_pending.erase(value)
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(side, side)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := TileSkin.new()
	painter.hw = hw
	painter.vivid = vivid
	painter.text_col = text_col
	painter.font = font
	painter.value = value
	painter.position = Vector2(extent, extent)
	vp.add_child(painter)
	add_child(vp)
	# One full draw of the target, then read it back. This runs once per value per
	# theme, behind the screen's own build, never during a fling.
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
	_tint[value] = vivid
	_half[value] = hw
	baked.emit(value)

## The painter that runs inside the bake target: the SAME CandyFace call the live
## tiles used to make, drawn at the origin of a footprint-sized canvas.
class TileSkin extends Node2D:
	var hw: float = 47.0
	var vivid: Color = Color.WHITE
	var text_col: Color = Color.BLACK
	var font: Font
	var value: int = 2

	func _draw() -> void:
		CandyFace.draw_face(self, Vector2.ZERO, hw, vivid)
		if font == null:
			return
		# The same numeral geometry FlingBlock lays down via
		# NumberBody._blit_number(half, 1.08, 0.14, 0.0), kept here so the baked
		# tile and a fallback-drawn tile are the same picture. Change one and you
		# must change the other, or a tile visibly shifts on the frame its bake
		# lands.
		var s := str(value)
		var fscale := clampf(1.08 - 0.14 * float(s.length() - 1), 0.5, 1.08)
		var fs := int(clampf(hw * fscale, 16.0, 130.0))
		var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var y := (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
		font.draw_string(get_canvas_item(), Vector2(-w * 0.5, y), s,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_col)
