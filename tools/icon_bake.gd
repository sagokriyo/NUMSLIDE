extends Node
## Bakes the LAUNCHER ICON - NOT part of the game.
##
##   godot --path . res://tools/icon_bake.tscn
##
## Renders the brand mark into an offscreen viewport and writes it to
## res://icon.png at 512x512: the logo's board, a 3x3 tray of glass number
## tiles with the last slot open, inside a neon-rimmed glass frame on the
## dark ground. CandyFace paints the slabs and TileFace the numerals, so the
## icon is a photograph of the same material the game is made of.
##
## Run it after any change to candy_face.gd / tile_face.gd that alters the
## material, then `godot --headless --path . --import` for the sidecar.
##
## Needs a real GPU - never headless (an offscreen viewport renders nothing
## there, and the bake would write a black square).

const OUT := "res://icon.png"
const BAKE := 1024
const OUT_SIZE := 512

# Deliberate constants, not theme keys: like the medals, the icon is a
# photograph and must not change when the player changes palette. The hues are
# the logo's grid read through the house colours the medals already wear.
const HUES: Array[Color] = [
	Color("8B36F0"), Color("2E6BFF"), Color("FF7A1A"),
	Color("22C96E"), Color("F0309E"), Color("22B8DE"),
	Color("6B3CFF"), Color("FFAE1A"),
]
const NEON := Color("B44DF2")   # the frame's rim light

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("icon_bake: needs a real display - an offscreen viewport renders nothing headless")
		get_tree().quit(1)
		return
	await get_tree().process_frame

	var vp := SubViewport.new()
	vp.size = Vector2i(BAKE, BAKE)
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.msaa_2d = Viewport.MSAA_4X
	vp.handle_input_locally = false
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(vp)

	var face := IconFace.new()
	face.size = Vector2(BAKE, BAKE)
	vp.add_child(face)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		printerr("ICON BAKE: FAILED - the viewport gave back nothing")
		get_tree().quit(1)
		return
	img.resize(OUT_SIZE, OUT_SIZE, Image.INTERPOLATE_LANCZOS)
	var err := img.save_png(ProjectSettings.globalize_path(OUT))
	if err != OK:
		printerr("ICON BAKE: FAILED - save_png err=%d" % err)
		get_tree().quit(1)
		return
	print("ICON BAKE: baked %dx%d -> %s" % [OUT_SIZE, OUT_SIZE, OUT])
	print("Now run: godot --headless --path . --import   (refreshes the sidecar)")
	get_tree().quit(0)

# --- The mark -------------------------------------------------------------------

## One _draw: the dark ground with the board's own light pooling behind it, a
## neon-rimmed glass frame, and the 3x3 tray - tiles 1 through 8 home and the
## last socket open, because the open socket is the whole game.
class IconFace extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		# 1. Ground: near-black with a breath of the brand violet at the top.
		draw_polygon(PackedVector2Array([
			Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]),
			PackedColorArray([
				Color("0B0716"), Color("0B0716"), Color("050309"), Color("050309")]))
		# 2. The board's light pooling on the ground behind it.
		var glow := NEON.lerp(Color.WHITE, 0.15)
		draw_texture_rect(CandyFace.glow_dot(),
			Rect2(c - Vector2.ONE * s * 0.62, Vector2.ONE * s * 1.24),
			false, Color(glow.r, glow.g, glow.b, 0.06))
		# 3. The frame: bloom, bright rim, a band of the neon's own dark glass,
		# a thin inner catch of light, then the near-black well the tiles sit in.
		var fw := s * 0.455
		var he := fw / 0.62
		draw_texture_rect(CandyFace.halo_tex(),
			Rect2(c - Vector2(he, he), Vector2(he, he) * 2.0),
			false, Color(NEON.r, NEON.g, NEON.b, 0.17))
		_rounded(c, fw, 0.14, NEON.lerp(Color.WHITE, 0.75), NEON.lerp(Color.WHITE, 0.25))
		_rounded(c, fw * 0.985, 0.135, NEON.darkened(0.35), NEON.darkened(0.62))
		_rounded(c, fw * 0.912, 0.10, NEON.lerp(Color.WHITE, 0.45), NEON.lerp(Color.WHITE, 0.10))
		_rounded(c, fw * 0.902, 0.10, Color("0A0714"), Color("0D0918"))
		# 4. The tray: tiles 1..8 home, the ninth socket open.
		var iw := fw * 0.902
		var gap := s * 0.016
		var pitch := (2.0 * iw - 2.0 * gap * 1.6) / 3.0
		var hw := (pitch - gap) * 0.5
		for r in 3:
			for col in 3:
				var at := c + Vector2(pitch * float(col - 1), pitch * float(r - 1))
				var i := r * 3 + col
				if i < 8:
					# White ink, not the derived kind: the logo's numerals are
					# white glass on every tile, and the icon matches the logo.
					CandyFace.draw_face(self, at, hw, HUES[i])
					TileFace.draw_number(self, at, hw, i + 1, Color(1, 1, 1))
				else:
					_socket(at, hw)

	## A rounded square through CandyFace's mask, top-to-bottom gradient.
	func _rounded(centre: Vector2, hw: float, frac: float, top: Color, bot: Color) -> void:
		draw_polygon(PackedVector2Array([
			centre + Vector2(-hw, -hw), centre + Vector2(hw, -hw),
			centre + Vector2(hw, hw), centre + Vector2(-hw, hw)]),
			PackedColorArray([top, top, bot, bot]),
			PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]),
			CandyFace.rounded_mask(frac))

	## The open slot: a dim neon edge around a pit, so the gap reads as part of
	## the board rather than a missing render.
	func _socket(centre: Vector2, hw: float) -> void:
		_rounded(centre, hw * 0.99, 0.15,
			Color(NEON.r, NEON.g, NEON.b, 0.30), Color(NEON.r, NEON.g, NEON.b, 0.14))
		_rounded(centre, hw * 0.93, 0.15, Color("070510"), Color("0D0A18"))
		draw_texture_rect(CandyFace.glow_dot(),
			Rect2(centre - Vector2.ONE * hw * 0.9, Vector2.ONE * hw * 1.8),
			false, Color(0, 0, 0, 0.45))
