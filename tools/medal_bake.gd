extends Node
## Bakes the achievement MEDALS - NOT part of the game.
##
##   godot --path . res://tools/medal_bake.tscn
##   godot --path . res://tools/medal_bake.tscn -- perfect_run streak_7
##
## Renders one glass medallion per id in Achievements.DEFS into an offscreen
## viewport and writes it to res://assets/images/medals/<id>.png: 256x256, a
## transparent ground, the same neon-glass material the tiles and marks wear
## (CandyFace paints the body, TileFace the numerals, IconLibrary the glyphs).
## The Achievements screen, the Badge trophy rail and the unlock toast all load
## that PNG by id, and each of them falls back to a plain chip when it is
## missing, so a crown added to DEFS without a bake earns into a blank chip.
##
## Run this after adding an achievement, after changing a hue below, and after
## any change to candy_face.gd or mark_face.gd that alters the material. Then
## run `godot --headless --path . --import` so the new PNGs get sidecars.
##
## Needs a real GPU - never headless (an offscreen viewport renders nothing
## there, and the bake would write 28 empty squares).

const OUT_DIR := "res://assets/images/medals"
const SIZE := 256

# --- The hue table -------------------------------------------------------------
# Deliberate constants, not theme keys: a medal is a photograph and must look
# the same in all 61 worlds, exactly as the marks keep their own colours on
# every theme (HUE_HERO / HUE_COOL). Mode crowns wear the board's band hues
# alternating down the list so the page reads as the two neon lights taking
# turns; a crown whose label IS a mark wears that mark's colour. Wild wears the
# two blended, because its whole point is either mark.
## The two hues the crowns are cast in. They were the mark colours in the
## sibling project and are the board's own band ends here: the hero rung the
## first row wears, and the cool rung the last one does.
const HUE_HERO := Color("F25CC9")
const HUE_COOL := Color("4FD6EA")
const HUE_XO := Color("A099D9")
const HUE_GOLD := Color("F4C13E")
const HUE_SILVER := Color("DCE5F1")
const HUE_VIOLET := Color("8A5CFF")
const HUE_EMERALD := Color("3ED98C")
const HUE_FLAME := Color("FF8A3A")

const HUES := {
	"first_solve": HUE_SILVER,
	"classic_series": HUE_HERO,
	"sprint_series": HUE_FLAME,
	"lock_series": HUE_VIOLET,
	"twist_series": HUE_COOL,
	"fog_series": HUE_XO,
	"cube_series": HUE_HERO,
	"classic_master": HUE_GOLD,
	"lock_master": HUE_GOLD,
	"twist_master": HUE_GOLD,
	"perfect_pace": HUE_VIOLET,
	"perfect_run": HUE_EMERALD,
	"streak_7": HUE_FLAME,
	"streak_30": HUE_FLAME,
}

# DEFS names its glyphs by PremiumIcon kind (the toast's fallback painter). The
# medal wears the painted IconLibrary icon of the same meaning instead, so it
# sits in the same glass-and-metal family as every other icon on the page.
# `merge` has no library icon and no meaning here: first_solve paints its own
# "first board" (1 2 3 in a row and the strike through them) in _draw.
const ICON_FOR := {
	"trophy": "best_score",
	"star": "games_won",
	"flame": "day_streak",
	"calendar": "daily",
}

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("medal_bake: needs a real display - an offscreen viewport renders nothing headless")
		get_tree().quit(1)
		return
	# One frame before anything renders: a SubViewport added while the scene
	# root is still setting up is refused, and the bake writes empty squares.
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var only := _requested_ids()
	var ids: Array = Achievements.ordered_ids()
	for want in only:
		if not ids.has(String(want)):
			printerr("medal_bake: no such achievement - %s" % String(want))
			get_tree().quit(1)
			return
	for id_v in ids:
		if not HUES.has(String(id_v)):
			printerr("medal_bake: %s has no hue in HUES - add it before baking" % String(id_v))
			get_tree().quit(1)
			return

	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.msaa_2d = Viewport.MSAA_4X
	vp.handle_input_locally = false
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(vp)

	var done := 0
	var failed: Array[String] = []
	for id_v in ids:
		var id := String(id_v)
		if not only.is_empty() and not only.has(id):
			continue
		var def: Dictionary = Achievements.definition(id)
		var face := MedalFace.new()
		face.hue = HUES[id]
		face.halo = _halo_tex()
		face.label = String(def.get("icon_label", ""))
		face.icon_id = String(ICON_FOR.get(String(def.get("icon", "")), ""))
		face.first_line = id == "first_solve"
		face.font = ThemeManager.display_font
		face.size = Vector2(SIZE, SIZE)
		vp.add_child(face)
		# Two frames so the face's first draw lands, then the frame that holds it.
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img: Image = vp.get_texture().get_image()
		face.queue_free()
		if img == null or img.is_empty() or _is_blank(img):
			failed.append(id)
			printerr("  FAILED %s - the viewport gave back nothing" % id)
			continue
		_unpremultiply(img)
		var path := "%s/%s.png" % [OUT_DIR, id]
		var err := img.save_png(ProjectSettings.globalize_path(path))
		if err != OK:
			failed.append(id)
			printerr("  FAILED %s - save_png err=%d" % [id, err])
			continue
		done += 1
		print("  baked %-20s -> %s" % [id, path])
	vp.queue_free()
	_report_strays(ids)
	print("MEDAL BAKE: %d baked, %d failed -> %s" % [done, failed.size(), OUT_DIR])
	if not failed.is_empty():
		printerr("failed: %s" % str(failed))
	print("Now run: godot --headless --path . --import   (imports the new .png files)")
	get_tree().quit(1 if not failed.is_empty() else 0)

## The viewport composes over a clear ground, so the readback carries
## PREMULTIPLIED colour: a soft halo pixel comes back as (hue * a, a), which a
## PNG viewer and a TextureRect both show as a dark grey fringe around every
## medal. Divide the alpha back out so the file holds straight colour.
static func _unpremultiply(img: Image) -> void:
	img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	for i in range(0, data.size(), 4):
		var a: int = data[i + 3]
		if a == 0 or a == 255:
			continue
		var k := 255.0 / float(a)
		for ch in 3:
			data[i + ch] = mini(int(roundf(float(data[i + ch]) * k)), 255)
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)

## A frame whose centre carries no alpha is a viewport that never rendered.
static func _is_blank(img: Image) -> bool:
	return img.get_pixel(img.get_width() >> 1, img.get_height() >> 1).a <= 0.0

## The pool of light the medal sits in: full under the body, fading through
## the gap to the ring and out to nothing at the canvas edge. CandyFace's
## glow_dot cannot do this job because the ring sits so near the edge that a
## dot wide enough to reach it would be cut square by the canvas.
static var _halo: Texture2D = null
static func _halo_tex() -> Texture2D:
	if _halo != null:
		return _halo
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var hf := float(SIZE) * 0.5
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(float(x) + 0.5 - hf, float(y) + 0.5 - hf).length() / hf
			var t := clampf((1.0 - d) / 0.40, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, pow(t, 1.4)))
	_halo = ImageTexture.create_from_image(img)
	return _halo

## Names every PNG in the folder that no achievement asks for, so leftovers
## from a retired crown are seen rather than shipped.
static func _report_strays(ids: Array) -> void:
	var d := DirAccess.open(OUT_DIR)
	if d == null:
		return
	var strays: Array[String] = []
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		if not d.current_is_dir() and entry.get_extension() == "png":
			if not ids.has(entry.get_basename()):
				strays.append(entry)
		entry = d.get_next()
	d.list_dir_end()
	if not strays.is_empty():
		strays.sort()
		print("stray medals nobody references (delete them and their .import): %s" % ", ".join(strays))

func _requested_ids() -> Array:
	var out: Array = []
	for a in OS.get_cmdline_user_args():
		out.append(String(a))
	return out

# --- The medallion -------------------------------------------------------------

## One medal, painted in a single _draw: a soft halo of the hue, a thin ring in
## the hue with its own specular, the glass body CandyFace paints for a sphere,
## a wet band along the top of the glass, then the face (an IconLibrary glyph,
## a MarkFace X or O, or the label in the display face), and one last streak of
## glass over the face so the glyph reads as a light inside the medal rather
## than a sticker on it. Proportions are fractions of the square so the bake
## size is one number.
class MedalFace extends Control:
	var hue: Color = Color.WHITE
	var label: String = ""
	var icon_id: String = ""
	var first_line: bool = false
	var font: Font = null
	var halo: Texture2D = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		var r_body := s * 0.385
		var r_ring := s * 0.452
		var ring_w := s * 0.021
		# 1. Halo: the hue pooling behind the medal and out past the ring.
		if halo != null:
			var hc := hue.lerp(Color.WHITE, 0.25)
			draw_texture_rect(halo, Rect2(c - Vector2.ONE * s * 0.5, Vector2.ONE * s),
				false, Color(hc.r, hc.g, hc.b, 0.55))
		# 2. The ring: a shadow under it, the hue lifted toward white, a catch of
		# light on its upper-left.
		draw_arc(c + Vector2(0.0, s * 0.012), r_ring, 0.0, TAU, 128,
			Color(0, 0, 0, 0.28), ring_w * 1.4, true)
		draw_arc(c, r_ring, 0.0, TAU, 128, hue.lerp(Color.WHITE, 0.30), ring_w, true)
		draw_arc(c, r_ring, deg_to_rad(195.0), deg_to_rad(255.0), 32,
			Color(1, 1, 1, 0.70), ring_w * 0.55, true)
		draw_arc(c, r_ring, deg_to_rad(20.0), deg_to_rad(60.0), 24,
			Color(1, 1, 1, 0.22), ring_w * 0.45, true)
		# 3. The body: the same glass every piece in the app is made of.
		CandyFace.draw_ball(self, c, r_body, hue, true)
		# 4. The wet band along the top of the glass, clipped to the disc.
		var br := r_body * 0.945
		_masked_band(c, br, -br, -br + br * 0.55, Color(1, 1, 1, 0.30), Color(1, 1, 1, 0.0))
		# 5. The face.
		if first_line:
			_draw_first_line(c, r_body)
		elif not icon_id.is_empty():
			_draw_icon(c, r_body)
		elif label.is_valid_int():
			TileFace.draw_number(self, c, r_body * 0.68, int(label), Color(0, 0, 0, 0), 1.0, 0.5)
		elif not label.is_empty():
			_draw_label(c, r_body)
		# 6. Glass over the face: a faint streak so the face sits inside the medal.
		draw_arc(c, r_body * 0.74, PI * 1.06, PI * 1.52, 24, Color(1, 1, 1, 0.12), r_body * 0.14, true)

	## A vertical gradient quad from `y0` to `y1` (centre-relative), UV-mapped
	## into the disc mask so it clips to the round body.
	func _masked_band(c: Vector2, br: float, y0: float, y1: float, top: Color, bot: Color) -> void:
		var pts := PackedVector2Array([
			c + Vector2(-br, y0), c + Vector2(br, y0), c + Vector2(br, y1), c + Vector2(-br, y1)])
		var uvs := PackedVector2Array()
		for i in 4:
			var p := pts[i] - c
			uvs.append(Vector2((p.x + br) / (2.0 * br), (p.y + br) / (2.0 * br)))
		draw_polygon(pts, PackedColorArray([top, top, bot, bot]), uvs, CandyFace.disc())

	## A painted IconLibrary glyph, without its own glow (the medal has one).
	func _draw_icon(c: Vector2, r_body: float) -> void:
		var tex := IconLibrary.texture(icon_id, 128, false)
		if tex == null:
			return
		var box := r_body * 1.30
		draw_texture_rect(tex, Rect2(c - Vector2.ONE * box * 0.5, Vector2.ONE * box), false)

	## The first line: three X marks in a row with the win strike through them.
	func _draw_first_line(c: Vector2, r_body: float) -> void:
		var step := r_body * 0.60
		var hw := r_body * 0.36
		var a := c + Vector2(-step - hw * 0.85, 0.0)
		var b := c + Vector2(step + hw * 0.85, 0.0)
		var strike := HUE_HERO.lerp(Color.WHITE, 0.5)
		draw_line(a, b, Color(strike.r, strike.g, strike.b, 0.40), hw * 0.70, true)
		draw_line(a, b, Color(1, 1, 1, 0.90), hw * 0.26, true)
		# 1 2 3 in a row: the first board, come home.
		for i in 3:
			TileFace.draw_number(self, c + Vector2(step * float(i - 1), 0.0), hw,
				i + 1, Color(0, 0, 0, 0), 1.0, 0.3)

	## The label in the display face: ink chosen by CandyFace's rule for glass
	## (deep hue on a pale body, white on a deep one) over a soft drop shadow.
	func _draw_label(c: Vector2, r_body: float) -> void:
		if font == null:
			return
		var fs := int(r_body * (1.30 if label.length() <= 1 else 0.98))
		var ink := CandyFace.text_color(hue)
		var shade := hue.darkened(0.65)
		var box := r_body * 2.0
		var asc := font.get_ascent(fs)
		var desc := font.get_descent(fs)
		var baseline := c.y + (asc - desc) * 0.5 - fs * 0.04
		var pos := Vector2(c.x - box * 0.5, baseline)
		draw_string(font, pos + Vector2(0.0, r_body * 0.05), label, HORIZONTAL_ALIGNMENT_CENTER,
			box, fs, Color(shade.r, shade.g, shade.b, 0.55))
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, box, fs, ink)
