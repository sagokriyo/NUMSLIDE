extends Node
## Bakes the APP ICON, in every size Android and the project ask for - NOT part
## of the game.
##
##   godot --path . res://tools/icon_bake.tscn
##
## Writes five files from one mark:
##
##   res://icon.png                                   512  the project icon
##   res://assets/icon/launcher_192.png               192  the legacy launcher
##   res://assets/icon/adaptive_foreground_432.png    432  the mark, transparent
##   res://assets/icon/adaptive_background_432.png    432  the ground, opaque
##   res://assets/icon/adaptive_monochrome_432.png    432  the silhouette, themed
##
## THE MARK IS THE WORDMARK, because the family it belongs to is. 2048 Limitless
## and Tic Tac Toe Limitless both put the NAME on the tile in big inflated glass,
## LIMITLESS tracked underneath it and the infinity below that, with the game's
## own pieces scattered around the outside. Three apps by one studio in one store
## listing have to read as three apps by one studio, and that recognition is
## worth more than the legibility a wordless mark would buy at 48 device pixels.
##
## So: NUM over SLIDE, one letter per hue across the spectrum, lit the way every
## letter in this app is lit (a bloom, the colour, a catch of white). The tiles
## ring the outside as the supporting cast, and the open slot they leave is still
## the one idea the icon carries on its own: the gap is what makes a sliding
## puzzle a puzzle, and the mark sitting in it says the game does not run out.
##
## Adaptive icons are masked to an arbitrary shape by the launcher and only the
## middle 66% is guaranteed to survive, so the foreground draws the mark small
## and centred inside that circle and the background carries the ground alone.
##
## Run it after any change to candy_face.gd / tile_face.gd that alters the
## material, then `godot --headless --path . --import` for the sidecars.
##
## Needs a real GPU - never headless (an offscreen viewport renders nothing
## there, and the bake would write black squares).

const ICON_OUT := "res://icon.png"
const LAUNCHER_DIR := "res://assets/icon"
const BAKE := 1024

## The spectrum the wordmark runs, left to right and top to bottom: violet into
## blue, blue into cyan and green, then gold, orange and back through magenta.
## Deliberate constants, not theme keys - the icon is a photograph and must not
## change when the player changes palette, exactly as the medals do not.
const HUES: Array[Color] = [
	Color("A24BF5"), Color("3D7BFF"), Color("22C3F0"),
	Color("3BE08C"), Color("FFC42E"), Color("FF7A2E"),
	Color("FF3FA8"), Color("C24BF5"),
]
## The rim light the frame and the open slot wear.
const NEON := Color("B44DF2")
## The infinity mark's own light, the one the wordmark's ∞ carries.
const LIMITLESS := Color("6FE9FF")

## Fraction of an adaptive icon's box the NAME is allowed to fill. The launcher
## masks the outer third away, and the foreground carries the name alone, so it
## can run most of the width: the word block is already inset inside whatever it
## is handed.
const SAFE_FRACTION := 0.92

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("icon_bake: needs a real display - an offscreen viewport renders nothing headless")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LAUNCHER_DIR))

	var jobs: Array = [
		# [path, output size, mode, transparent, scale of the mark]
		[ICON_OUT, 512, IconFace.Mode.FULL, false, 1.0],
		[LAUNCHER_DIR + "/launcher_192.png", 192, IconFace.Mode.FULL, false, 1.0],
		[LAUNCHER_DIR + "/adaptive_background_432.png", 432, IconFace.Mode.GROUND, false, 1.0],
		[LAUNCHER_DIR + "/adaptive_foreground_432.png", 432, IconFace.Mode.MARK, true, SAFE_FRACTION],
		[LAUNCHER_DIR + "/adaptive_monochrome_432.png", 432, IconFace.Mode.MONO, true, SAFE_FRACTION],
	]
	for job in jobs:
		var ok := await _bake(String(job[0]), int(job[1]), int(job[2]), bool(job[3]), float(job[4]))
		if not ok:
			get_tree().quit(1)
			return
	print("ICON BAKE: %d files written" % jobs.size())
	print("Now run: godot --headless --path . --import   (refreshes the sidecars)")
	get_tree().quit(0)

func _bake(path: String, out_size: int, mode: int, transparent: bool, scale: float) -> bool:
	var vp := SubViewport.new()
	vp.size = Vector2i(BAKE, BAKE)
	vp.transparent_bg = transparent
	vp.disable_3d = true
	vp.msaa_2d = Viewport.MSAA_4X
	vp.handle_input_locally = false
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(vp)

	var face := IconFace.new()
	face.mode = mode
	face.mark_scale = scale
	face.size = Vector2(BAKE, BAKE)
	vp.add_child(face)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		printerr("ICON BAKE: FAILED - the viewport gave back nothing for %s" % path)
		return false
	img.resize(out_size, out_size, Image.INTERPOLATE_LANCZOS)
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		printerr("ICON BAKE: FAILED - save_png err=%d for %s" % [err, path])
		return false
	print("  %4d  %s" % [out_size, path])
	return true

# --- The mark -------------------------------------------------------------------

## One _draw, in four cuts: the whole icon, the ground alone, the mark alone on
## a transparent ground, and the mark as a flat silhouette for the themed
## monochrome layer.
class IconFace extends Control:
	enum Mode { FULL, GROUND, MARK, MONO }

	var mode: int = Mode.FULL
	var mark_scale: float = 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		if mode == Mode.FULL or mode == Mode.GROUND:
			_ground(s, c)
		if mode == Mode.GROUND:
			return
		_mark(s * mark_scale, c, mode)

	## Near-black with the wordmark's own light bleeding up through it. The
	## reference sits on true black and is legible because the neon lifts off it,
	## so the ground stays dark enough for the tiles to be the only light.
	func _ground(s: float, c: Vector2) -> void:
		draw_polygon(PackedVector2Array([
			Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]),
			PackedColorArray([
				Color("0A0616"), Color("0A0616"), Color("040209"), Color("040209")]))
		# Two pools of the spectrum's ends, so the black is a lit black.
		draw_texture_rect(CandyFace.glow_dot(),
			Rect2(c - Vector2(s * 0.75, s * 0.85), Vector2.ONE * s * 1.3),
			false, Color(0.62, 0.30, 0.98, 0.16))
		draw_texture_rect(CandyFace.glow_dot(),
			Rect2(c - Vector2(s * 0.55, s * 0.25), Vector2.ONE * s * 1.3),
			false, Color(0.13, 0.76, 0.94, 0.11))

	## The supporting cast rings the outside and the name sits in the middle,
	## which is the composition both sibling icons use.
	func _mark(s: float, c: Vector2, m: int) -> void:
		# The ring is FULL only. An adaptive launcher masks the outer third away,
		# so tiles out there are cropped on most phones and all the foreground
		# would carry is a name shrunk to make room for them.
		if m == Mode.FULL:
			_ring_of_tiles(s, c)
		_word(s, c, m == Mode.MONO)

	## Eight numbered tiles and one open slot, laid round the edge of the icon
	## behind the name. The slot holds the limitless mark: the gap is the game.
	##
	## FULL ONLY. An adaptive launcher masks the outer third away, so anything out
	## here is cropped on most phones; the foreground layer carries the name alone.
	func _ring_of_tiles(s: float, c: Vector2) -> void:
		var r := s * 0.395
		var hw := s * 0.083
		# Nine stations round the ring, the last one left open.
		for i in 9:
			var a := -PI * 0.5 + TAU * float(i) / 9.0
			var at := c + Vector2(cos(a), sin(a)) * r
			if i < 8:
				CandyFace.draw_face(self, at, hw, HUES[i])
				TileFace.draw_number(self, at, hw, i + 1, Color(1, 1, 1))
			else:
				_socket(at, hw, false)

	## NUM over SLIDE, then LIMITLESS, then the infinity. One size for both lines
	## so the letters match, fitted to the longer of the two.
	func _word(s: float, c: Vector2, mono: bool) -> void:
		var font := _brand_font()
		if font == null:
			return
		var lines := ["NUM", "SLIDE"]
		var target := s * 0.56
		var px := _fit(font, "SLIDE", target, int(s * 0.30))
		var line_h := float(px) * 0.82
		# The block is the two lines plus the LIMITLESS rule under them; centre
		# the whole thing, not just the type.
		var first := c.y - line_h * 0.46
		var hue := 0
		for li in lines.size():
			var line: String = lines[li]
			var width := 0.0
			for ch in line:
				width += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			var x := c.x - width * 0.5
			var y := first + line_h * float(li)
			for ch in line:
				var adv := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
				_letter(font, Vector2(x, y), ch, px, HUES[hue % HUES.size()], mono)
				x += adv
				hue += 1
		_limitless(font, c, s, first + line_h * 1.56, mono)

	## The largest size at which `text` still fits `target` wide.
	func _fit(font: Font, text: String, target: float, start_px: int) -> int:
		var px := start_px
		while px > 12 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > target:
			px -= 4
		return px

	## One letter of the name, lit the way every lit thing in this app is: a bloom
	## of its own hue, a dark tube edge, the colour, and a catch of white along the
	## top. The same three passes `_infinity` uses, cast on a glyph.
	func _letter(font: Font, pos: Vector2, ch: String, px: int, hue: Color, mono: bool) -> void:
		if mono:
			draw_string(font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color.WHITE)
			return
		var m := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
		var mid := pos + Vector2(m.x * 0.5, -m.y * 0.30)
		# The bloom is kept LOW. At the strength the tiles wear it the halos of
		# eight neighbouring letters overlap into one fog and every hue washes out
		# to pastel; the letters have to stay the most saturated thing on the tile.
		draw_texture_rect(CandyFace.halo_tex(),
			Rect2(mid - Vector2.ONE * m.y * 0.70, Vector2.ONE * m.y * 1.40),
			false, Color(hue.r, hue.g, hue.b, 0.18))
		# A near-black seat under the glyph, so it lifts off the ground.
		draw_string_outline(font, pos + Vector2(0.0, float(px) * 0.020), ch,
			HORIZONTAL_ALIGNMENT_LEFT, -1, px,
			maxi(2, int(float(px) * 0.125)), Color(0.02, 0.01, 0.05, 0.75))
		draw_string_outline(font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px,
			maxi(2, int(float(px) * 0.105)), hue.darkened(0.72))
		draw_string(font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px, hue)
		# The catch: the same glyph a touch higher, so the light lands on the top
		# of every stroke and the letter reads as inflated rather than printed.
		# Faint, because a full-glyph white pass at any real strength bleaches the
		# colour it is supposed to be sitting on.
		draw_string(font, pos - Vector2(0.0, float(px) * 0.045), ch,
			HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(1, 1, 1, 0.15))

	## LIMITLESS in tracked caps with the infinity under it, the way both sibling
	## icons close their wordmark.
	func _limitless(font: Font, c: Vector2, s: float, y: float, mono: bool) -> void:
		var px := int(s * 0.055)
		var track := float(px) * 0.46
		var text := "LIMITLESS"
		var width := -track
		for ch in text:
			width += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + track
		var x := c.x - width * 0.5
		var col := Color.WHITE if mono else LIMITLESS
		for ch in text:
			draw_string(font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
			x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + track
		_infinity(Vector2(c.x, y + s * 0.085), s * 0.050, LIMITLESS, mono)

	## The brand face, which is the wordmark's own. Falls back down the chain so a
	## bake never silently writes an icon with no name on it.
	func _brand_font() -> Font:
		var f: Font = ThemeManager.brand_font
		if f == null:
			f = ThemeManager.display_font
		if f == null:
			f = ThemeManager.ui_font
		return f

	## A rounded square through CandyFace's mask, top-to-bottom gradient.
	func _rounded(centre: Vector2, hw: float, frac: float, top: Color, bot: Color) -> void:
		draw_polygon(PackedVector2Array([
			centre + Vector2(-hw, -hw), centre + Vector2(hw, -hw),
			centre + Vector2(hw, hw), centre + Vector2(-hw, hw)]),
			PackedColorArray([top, top, bot, bot]),
			PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]),
			CandyFace.rounded_mask(frac))

	## The open slot: a dim neon edge around a pit, with the limitless mark lit
	## inside it. The gap is the game and the sign in it is the brand, so the one
	## empty cell says both at once.
	func _socket(centre: Vector2, hw: float, mono: bool) -> void:
		if mono:
			_infinity(centre, hw, Color.WHITE, true)
			return
		_rounded(centre, hw * 0.99, 0.15,
			Color(NEON.r, NEON.g, NEON.b, 0.30), Color(NEON.r, NEON.g, NEON.b, 0.14))
		_rounded(centre, hw * 0.93, 0.15, Color("070510"), Color("0D0A18"))
		draw_texture_rect(CandyFace.glow_dot(),
			Rect2(centre - Vector2.ONE * hw * 0.9, Vector2.ONE * hw * 1.8),
			false, Color(0, 0, 0, 0.45))
		draw_texture_rect(CandyFace.halo_tex(),
			Rect2(centre - Vector2.ONE * hw * 1.5, Vector2.ONE * hw * 3.0),
			false, Color(LIMITLESS.r, LIMITLESS.g, LIMITLESS.b, 0.28))
		_infinity(centre, hw, LIMITLESS, false)

	## The limitless mark: two rings side by side, drawn as neon tube — a wide
	## soft pass for the bloom, the colour itself, then a white core, which is
	## how every lit letter in the wordmark is built.
	func _infinity(centre: Vector2, hw: float, col: Color, flat: bool) -> void:
		var r := hw * 0.34
		# The loops CROSS. Two rings sitting side by side read as "oo" at any
		# size big enough to see them apart, which is not the mark.
		var dx := r * 0.82
		var stroke := hw * 0.17
		for side in [-1.0, 1.0]:
			var at := centre + Vector2(dx * side, 0.0)
			if flat:
				draw_arc(at, r, 0.0, TAU, 48, col, stroke * 1.15, true)
				continue
			draw_arc(at, r, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.35), stroke * 2.1, true)
			draw_arc(at, r, 0.0, TAU, 48, col, stroke, true)
			draw_arc(at, r, 0.0, TAU, 48, Color(1, 1, 1, 0.9), stroke * 0.34, true)
