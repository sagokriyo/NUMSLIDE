class_name CandyFace
## The glass-neon tile finish, as a SHARED painter: a slab of edge-lit glass —
## an ambient halo of the tile's own hue, a thin near-white rim, a saturated
## vertical-gradient body, THE diagonal glass streak, a top inner highlight,
## a bottom inner shade and a corner gleam with a tiny specular. Any CanvasItem
## can wear it (TileView on the grid boards, TowerTile, FlingBlock, deck chips…)
## and `draw_ball` is the same material on a sphere (MergeBlob + queue chips) —
## so every mode's pieces read as one physical material.

const _RADIUS_FRAC := 0.15   # corner radius as a fraction of tile size (~15%)

## The same number, published, because other art has to MATCH it rather than
## guess at it: Cube rolls its plastic corners to exactly this radius, and a
## solid whose corners are tighter than the tiles sitting on it reads as a mitre
## beside a fillet. Anything that must agree with a tile's curve reads it here.
const TILE_ROUND_FRAC := _RADIUS_FRAC

static var _masks: Dictionary = {}   # radius_frac -> Texture2D
static var _disc: Texture2D
static var _glow_dot: Texture2D
static var _halo: Texture2D
static var _hex: Texture2D
static var _hex_halo: Texture2D

## The theme-derived candy colour for a value: the theme's OWN tile ramp (the
## same colour story every board tells), lifted a touch in saturation so the
## glass finish pops. One place, so boards and their merge FX agree on the hue.
static func color(value: int) -> Color:
	var bg: Color = ThemeManager.tile_style(value)["bg"]
	return Color.from_hsv(bg.h, clampf(bg.s * 1.32, 0.0, 1.0), clampf(bg.v * 1.08, 0.0, 1.0))

## The same vivid tile colour, for an ARBITRARY palette instead of the active one.
##
## `tile_style_for` takes a palette rather than reading ThemeManager's, so a
## theme's real ramp can be resolved without owning or wearing it — which is what
## lets the Shop paint the tiles a player would actually get. Deliberately a
## SEPARATE entry point from color(): that one is on the board's per-frame draw
## path and reads the manager's internal palette directly, and it stays that way.
static func color_for(pal: Dictionary, value: int) -> Color:
	var bg: Color = ThemeManager.tile_style_for(pal, value)["bg"]
	return Color.from_hsv(bg.h, clampf(bg.s * 1.32, 0.0, 1.0), clampf(bg.v * 1.08, 0.0, 1.0))

## Legible numeral ink for a glass colour: on pale fills a DEEP shade of the
## tile's own hue (glass reads tinted, not printed-on black); white on deep.
## "Pale" and "deep" are decided by REAL contrast (ThemeManager._wcag_contrast),
## not the encoded-luminance average this used to threshold — a hot saturated
## pink reads "deep" to the average but carries little real light, and white
## ink on it measured ~2.6:1. Whichever candidate ink contrasts more wins, so
## the numerals clear the floor test_theme_visuals pins on every ramp.
static func text_color(vivid: Color) -> Color:
	var deep := Color.from_hsv(vivid.h, clampf(vivid.s * 0.8 + 0.25, 0.0, 1.0), 0.24)
	if ThemeManager._wcag_contrast(deep, vivid) >= ThemeManager._wcag_contrast(Color(1, 1, 1), vivid):
		return deep
	return Color(1, 1, 1)

## Numeral ink for the VOID face. The void body is deeply darkened whatever the
## ramp colour is, so the pale-fill branch above would put near-black digits on a
## near-black tile — the numbers would simply disappear on every light theme. The
## void always takes light ink, tinted by its own hue so it still belongs to the
## palette rather than reading as flat white.
static func void_text_color(vivid: Color) -> Color:
	return Color.from_hsv(vivid.h, clampf(vivid.s * 0.45, 0.0, 1.0), 0.97)

## The shared white rounded-square mask (soft SDF edge) at the house radius.
static func mask() -> Texture2D:
	return rounded_mask(_RADIUS_FRAC)

## A cached rounded-square mask at an arbitrary corner-radius fraction — used
## by board frames that want a different rounding than the tiles (e.g. ~4%).
static func rounded_mask(radius_frac: float) -> Texture2D:
	var key := snappedf(radius_frac, 0.001)
	if not _masks.has(key):
		_masks[key] = _make_mask(256, radius_frac)
	var tex: Texture2D = _masks[key]
	return tex

## A solid anti-aliased white disc — the sphere version of the mask.
static func disc() -> Texture2D:
	if _disc == null:
		_disc = _make_disc(256)
	return _disc

## A soft radial glow dot (bright core → transparent) for sheens and halos.
static func glow_dot() -> Texture2D:
	if _glow_dot == null:
		_glow_dot = _make_glow_dot(96)
	return _glow_dot

## A rounded-square BLOOM: solid over the central tile footprint, then a soft
## falloff to the texture edge — the tile's ambient halo (no hard ring). The
## tile occupies the central `_HALO_Q` fraction, so draw it at hw / _HALO_Q.
const _HALO_Q := 0.62
static func halo_tex() -> Texture2D:
	if _halo == null:
		_halo = _make_halo(160)
	return _halo

## The FLAT-TOP hexagon mask (Hex mode's tiles). Spans the texture's full width;
## a regular hexagon is only sqrt(3)/2 as tall as it is wide, so the top and
## bottom of the texture are transparent bands. That is deliberate — it lets a
## hex tile keep the SQUARE Control rect every animation, glow and layout path
## already assumes, with the silhouette carved entirely by this mask.
static func hex_mask() -> Texture2D:
	if _hex == null:
		_hex = _make_hex_mask(256, _RADIUS_FRAC)
	return _hex

## The hexagon's ambient bloom, same contract as halo_tex().
static func hex_halo_tex() -> Texture2D:
	if _hex_halo == null:
		_hex_halo = _make_hex_halo(160)
	return _hex_halo

## Signed distance to a flat-top hexagon of half-width `a`, rounded by `r`.
##
## The hexagon is the intersection of three slabs — one horizontal and two at
## +/-60 degrees — all sharing the same bound, because a regular hexagon's
## inradius is the same across every opposing edge pair. Taking the max of the
## three plane distances is exact inside and along the edges (which is all the
## soft AA edge and the rounding need), and rounding is the usual trick of
## shrinking the shape by r and growing the distance back.
static func _hex_sdf(px: float, py: float, a: float, r: float) -> float:
	var bb := a * 0.8660254 - r
	var e1 := absf(py) - bb
	var e2 := absf(0.8660254 * px + 0.5 * py) - bb
	var e3 := absf(0.8660254 * px - 0.5 * py) - bb
	return maxf(e1, maxf(e2, e3)) - r

static func _make_hex_mask(sz: int, radius_frac: float) -> Texture2D:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var hf := float(sz) * 0.5
	var r := radius_frac * float(sz)
	for y in sz:
		for x in sz:
			var d := _hex_sdf(float(x) + 0.5 - hf, float(y) + 0.5 - hf, hf, r)
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 - smoothstep(-1.0, 1.0, d)))
	return ImageTexture.create_from_image(img)

static func _make_hex_halo(sz: int) -> Texture2D:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var hf := float(sz) * 0.5
	var th := hf * _HALO_Q                 # tile half-width inside the texture
	var r := _RADIUS_FRAC * 2.0 * th       # the tile's own corner radius
	var spread := hf - th                  # glow room outside the tile footprint
	for y in sz:
		for x in sz:
			var d := _hex_sdf(float(x) + 0.5 - hf, float(y) + 0.5 - hf, th, r)
			var a := 1.0
			if d > 0.0:
				a = pow(clampf(1.0 - d / spread, 0.0, 1.0), 1.7)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

static func _make_mask(sz: int, radius_frac: float) -> Texture2D:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var hf := float(sz) * 0.5
	var r := radius_frac * float(sz)
	for y in sz:
		for x in sz:
			var px := absf(float(x) + 0.5 - hf)
			var py := absf(float(y) + 0.5 - hf)
			var qx := px - hf + r
			var qy := py - hf + r
			var d := Vector2(maxf(qx, 0.0), maxf(qy, 0.0)).length() + minf(maxf(qx, qy), 0.0) - r
			var a := 1.0 - smoothstep(-1.0, 1.0, d)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

static func _make_disc(sz: int) -> Texture2D:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c := float(sz) * 0.5
	for y in sz:
		for x in sz:
			var ux := (float(x) + 0.5 - c) / c
			var uy := (float(y) + 0.5 - c) / c
			var d := sqrt(ux * ux + uy * uy)
			var a := 1.0 - smoothstep(0.975, 1.0, d)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

static func _make_glow_dot(sz: int) -> Texture2D:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c := float(sz) * 0.5
	for y in sz:
		for x in sz:
			var ux := (float(x) + 0.5 - c) / c
			var uy := (float(y) + 0.5 - c) / c
			var d := sqrt(ux * ux + uy * uy)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 1.6)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

static func _make_halo(sz: int) -> Texture2D:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var hf := float(sz) * 0.5
	var th := hf * _HALO_Q                 # tile half-extent inside the texture
	var r := _RADIUS_FRAC * 2.0 * th       # the tile's own corner radius
	var spread := hf - th                  # glow room outside the tile footprint
	for y in sz:
		for x in sz:
			var px := absf(float(x) + 0.5 - hf)
			var py := absf(float(y) + 0.5 - hf)
			var qx := px - th + r
			var qy := py - th + r
			var d := Vector2(maxf(qx, 0.0), maxf(qy, 0.0)).length() + minf(maxf(qx, qy), 0.0) - r
			var a := 1.0
			if d > 0.0:
				a = pow(clampf(1.0 - d / spread, 0.0, 1.0), 1.7)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

# --- Geometry helpers for the masked overlay polygons ---------------------------

## Clip a convex polygon (centre-relative points) against the diagonal half-plane
## f(p) = p.x + p.y - c: keeps f <= 0 when keep_below, else f >= 0.
static func _clip_diag(pts: PackedVector2Array, c: float, keep_below: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var fa := a.x + a.y - c
		var fb := b.x + b.y - c
		if not keep_below:
			fa = -fa
			fb = -fb
		if fa <= 0.0:
			out.append(a)
		if (fa < 0.0 and fb > 0.0) or (fa > 0.0 and fb < 0.0):
			out.append(a.lerp(b, fa / (fa - fb)))
	return out

## UVs mapping centre-relative points into the FULL face's mask space, so an
## overlay polygon clips inside the face's rounded corners.
static func _face_uvs(pts: PackedVector2Array, hw: float) -> PackedVector2Array:
	var uvs := PackedVector2Array()
	for p in pts:
		uvs.append(Vector2((p.x + hw) / (2.0 * hw), (p.y + hw) / (2.0 * hw)))
	return uvs

## Twice the unsigned area of a simple polygon (the shoelace sum, absolute).
## `_clip_diag` can hand back a 3-point SLIVER — vertex count valid, geometry
## degenerate — which `draw_polygon` cannot triangulate. Swept over 20,001
## positions of the shine band at hw = 80 / 118.5 / 131, the worst survivor had an
## area of 7.2e-5 / 1.6e-4 / 1.9e-4 px² and a shortest edge of 0.012 / 0.018 /
## 0.020 px, and it produced, once per 120-move run, from
## `TileView.ShineLayer._draw` -> `draw_shine_band`:
##   ERROR: Invalid polygon data, triangulation failed.
##   at: canvas_item_add_polygon (renderer_canvas_cull.cpp:1727)
## — a synchronous stderr write from inside a `_draw`. Skipping such a polygon
## changes nothing on screen: the triangulator already rejected it, so it drew
## nothing. The threshold is 1% of ONE pixel's area — ~50x the largest sliver the
## sweep produced, and reached within 2.6e-4 of `t`, i.e. a window 70x narrower
## than a single 60 fps step of the 0.9 s sweep. The exact endpoints t = 0.0 and
## t = 1.0 were already safe: they yield 0- or 1-point polygons that the
## vertex-count guard catches.
const _MIN_POLY_AREA2 := 0.02   # 2x area, i.e. reject below 0.01 px²

static func _poly_area2(pts: PackedVector2Array) -> float:
	var acc := 0.0
	var n := pts.size()
	for i in n:
		var p := pts[i]
		var q := pts[(i + 1) % n]
		acc += p.x * q.y - q.x * p.y
	return absf(acc)

static func _offset_pts(pts: PackedVector2Array, centre: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + centre)
	return out

# --- The glass-neon face --------------------------------------------------------

## The one internal painter both public faces delegate to. Layer stack (spec):
## ambient halo → contact shadow → near-white rim → gradient body → diagonal
## glass streak → top inner highlight → bottom inner shade → corner gleam +
## specular. Everything derives from `vivid`; white/black overlays only.
static func _glass_face(ci: CanvasItem, centre: Vector2, hw: float, vivid: Color,
		with_shadow: bool, void_mode: bool = false, hex: bool = false,
		with_halo: bool = true) -> void:
	# The silhouette is decided ENTIRELY here. Every polygon below still spans the
	# full square +/-hw and is UV-mapped through this mask, so a hexagonal tile
	# needs no geometry changes at all — only the two unmasked layers (the corner
	# gleam and the specular, drawn with draw_circle/draw_texture_rect) have to
	# move, because a square's 45-degree corner is outside a flat-top hexagon.
	var tex := hex_mask() if hex else mask()
	var uvs := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	# The void inverts the KEY LIGHT rather than recolouring the tile: same ramp
	# hue, same silhouette, but the highlights sit low and the body falls away into
	# a dark core, so an antimatter tile reads as a hole punched in the board next
	# to its identically-coloured positive twin. Every overlay below flips with it —
	# a half-inverted face reads as a rendering bug, not as a material.
	var ink := Color(0, 0, 0) if void_mode else Color(1, 1, 1)
	# Darkening the ramp colour alone does not carry the void: the low tiles are
	# already muted (a darkened +2 is just a browner +2) and the pale ramps have no
	# headroom, so -2 and +2 came out near-identical. The body is therefore pulled
	# most of the way to a COMMON near-black instead, and tile identity moves to the
	# rim, which keeps the full ramp hue. Bodies read as one family of holes; the
	# edges still say which hole.
	var vd := Color(0.03, 0.02, 0.06)
	# 1. Ambient halo — a soft bloom of the tile's own hue hugging the tile shape.
	# The void swallows light instead of throwing it: a much fainter, unlifted hue.
	if with_halo:
		var halo_col := vivid if void_mode else vivid.lerp(Color(1, 1, 1), 0.35)
		var he := hw / _HALO_Q
		ci.draw_texture_rect(hex_halo_tex() if hex else halo_tex(),
			Rect2(centre - Vector2(he, he), Vector2(he, he) * 2.0),
			false, Color(halo_col.r, halo_col.g, halo_col.b, 0.12 if void_mode else 0.30))
	# 2. Contact shadow — reduced, keeps tiles separating on light themes.
	if with_shadow:
		var so := centre + Vector2(hw * 0.05, hw * 0.12)
		var sh := hw * 1.03
		var sc := Color(0, 0, 0, 0.26 if void_mode else 0.18)
		ci.draw_polygon(PackedVector2Array([
			so + Vector2(-sh, -sh), so + Vector2(sh, -sh),
			so + Vector2(sh, sh), so + Vector2(-sh, sh)]),
			PackedColorArray([sc, sc, sc, sc]), uvs, tex)
	# 3. Rim (edge-lit border): the full rounded square in near-white, brightest
	# at the top — this is the brightest part of the tile. The void keeps a rim (it
	# is still glass) but dims it and puts the bright end at the BOTTOM: that single
	# flip is what the eye reads as engraved rather than raised.
	var rim_top := vivid.lerp(vd, 0.62) if void_mode else vivid.lerp(Color(1, 1, 1), 0.78)
	var rim_bot := vivid.lerp(Color(1, 1, 1), 0.22) if void_mode else vivid.lerp(Color(1, 1, 1), 0.50)
	ci.draw_polygon(PackedVector2Array([
		centre + Vector2(-hw, -hw), centre + Vector2(hw, -hw),
		centre + Vector2(hw, hw), centre + Vector2(-hw, hw)]),
		PackedColorArray([rim_top, rim_top, rim_bot, rim_bot]), uvs, tex)
	# 4. Body — inset so the visible rim ring is ~2.75% of S thick.
	var bw := hw * 0.945
	var col_top := vivid.lerp(vd, 0.93) if void_mode else vivid.lightened(0.20)
	var col_bot := vivid.lerp(vd, 0.78) if void_mode else vivid.darkened(0.28)
	ci.draw_polygon(PackedVector2Array([
		centre + Vector2(-bw, -bw), centre + Vector2(bw, -bw),
		centre + Vector2(bw, bw), centre + Vector2(-bw, bw)]),
		PackedColorArray([col_top, col_top, col_bot, col_bot]), uvs, tex)
	# 4b. The void core — a soft black pit sunk into the middle of the body. This
	# is the layer that actually sells "hole": without it an inverted gradient just
	# looks like a dimmer tile.
	if void_mode:
		ci.draw_texture_rect(glow_dot(),
			Rect2(centre - Vector2.ONE * bw * 0.98, Vector2.ONE * bw * 1.96),
			false, Color(0, 0, 0, 0.72))
	# 5. Diagonal glass streak — the face splits along a soft diagonal running
	# bottom-left → top-right; the upper-left region reads lighter. Drawn with
	# full-face mask UVs so it clips inside the rounded corners. On near-white
	# bodies (arctic/paper 2 and 4) a 0.10 white overlay vanishes — scale the
	# streak alpha up with body luminance; dark bodies keep the exact current look.
	var lum: float = vivid.get_luminance()
	var streak_a: float = 0.10 + 0.08 * clampf((lum - 0.75) / 0.25, 0.0, 1.0)
	var square := PackedVector2Array([
		Vector2(-hw, -hw), Vector2(hw, -hw), Vector2(hw, hw), Vector2(-hw, hw)])
	var k := hw * 0.34   # transition half-width (~12% of S along the normal)
	var lit := _clip_diag(square, -k, true)
	if lit.size() >= 3:
		var lc := Color(ink.r, ink.g, ink.b, streak_a)
		var lcs := PackedColorArray()
		for _i in lit.size():
			lcs.append(lc)
		ci.draw_polygon(_offset_pts(lit, centre), lcs, _face_uvs(lit, hw), tex)
	var band := _clip_diag(_clip_diag(square, k, true), -k, false)
	if band.size() >= 3:
		var bcs := PackedColorArray()
		for i in band.size():
			var f := band[i].x + band[i].y
			bcs.append(Color(ink.r, ink.g, ink.b,
				lerpf(streak_a, 0.0, clampf((f + k) / (2.0 * k), 0.0, 1.0))))
		ci.draw_polygon(_offset_pts(band, centre), bcs, _face_uvs(band, hw), tex)
	# A second, narrower bright band riding just above the diagonal.
	var band2 := _clip_diag(_clip_diag(square, -k, true), -k * 1.9, false)
	if band2.size() >= 3:
		var b2a: float = streak_a * 0.5
		var b2cs := PackedColorArray()
		for i in band2.size():
			var f2 := band2[i].x + band2[i].y
			b2cs.append(Color(ink.r, ink.g, ink.b,
				lerpf(0.0, b2a, clampf((f2 + k * 1.9) / (k * 0.9), 0.0, 1.0))))
		ci.draw_polygon(_offset_pts(band2, centre), b2cs, _face_uvs(band2, hw), tex)
	# 6. Top inner highlight — a thin white band hugging the inside of the top rim.
	# Inverted, it becomes a top inner SHADE: the light no longer enters from above.
	var hl := PackedVector2Array([
		Vector2(-bw, -bw), Vector2(bw, -bw), Vector2(bw, -bw + hw * 0.2), Vector2(-bw, -bw + hw * 0.2)])
	var hl_a: float = 0.30 if void_mode else 0.36
	ci.draw_polygon(_offset_pts(hl, centre),
		PackedColorArray([
			Color(ink.r, ink.g, ink.b, hl_a), Color(ink.r, ink.g, ink.b, hl_a),
			Color(ink.r, ink.g, ink.b, 0.0), Color(ink.r, ink.g, ink.b, 0.0)]),
		_face_uvs(hl, hw), tex)
	# 7. Bottom inner shade — glass depth; the base reads deeper. Inverted, it is
	# the bounce light pooling in the bottom of the pit.
	var shd := PackedVector2Array([
		Vector2(-bw, bw - hw * 0.4), Vector2(bw, bw - hw * 0.4), Vector2(bw, bw), Vector2(-bw, bw)])
	var lo := Color(1, 1, 1) if void_mode else Color(0, 0, 0)
	var lo_a: float = 0.22 if void_mode else 0.16
	ci.draw_polygon(_offset_pts(shd, centre),
		PackedColorArray([
			Color(lo.r, lo.g, lo.b, 0.0), Color(lo.r, lo.g, lo.b, 0.0),
			Color(lo.r, lo.g, lo.b, lo_a), Color(lo.r, lo.g, lo.b, lo_a)]),
		_face_uvs(shd, hw), tex)
	# 8. Corner gleam tucked into the top-left, plus a tiny specular ON the rim.
	# On warm off-white fills (paper) the 0.60 white dot sinks into the pale rim:
	# bump its alpha and seat it on a soft darker contact ring so it still reads.
	# The void's catch moves to the BOTTOM-RIGHT and dims, following its key light.
	# A hexagon's widest point is its LEFT vertex, not its top-left corner, so the
	# catch-light rides the upper-left EDGE and sits much closer in. At the square
	# tile's 0.86 the specular would hang in the transparent corner of the mask,
	# detached from the tile it belongs to.
	var gleam_c := Vector2(bw * 0.05, bw * 0.05) if void_mode else Vector2(-bw * 1.05, -bw * 1.05)
	if hex and not void_mode:
		gleam_c = Vector2(-bw * 0.80, -bw * 0.72)
	ci.draw_texture_rect(glow_dot(), Rect2(centre + gleam_c, Vector2(bw, bw)),
		false, Color(1, 1, 1, 0.10 if void_mode else 0.24))
	var spec_reach: float = 0.52 if hex else 0.86
	var spec_dir := spec_reach if void_mode else -spec_reach
	# Squashed vertically on hex: the shape is only ~87% as tall as it is wide.
	var spec_drop: float = 0.72 if hex else 1.0
	var spec_pos := centre + Vector2(hw * spec_dir, hw * spec_dir * spec_drop)
	var spec_a: float = 0.34 if void_mode else 0.70
	if lum > 0.8 and not void_mode:
		spec_a = 0.85
		ci.draw_circle(spec_pos, hw * 0.075, Color(0, 0, 0, 0.06), true, -1.0, true)
	# A tight hot core inside the specular sells a polished glass/metal catch.
	ci.draw_circle(spec_pos, hw * 0.06, Color(1, 1, 1, spec_a), true, -1.0, true)
	ci.draw_circle(spec_pos + Vector2(-hw * 0.012, -hw * 0.012), hw * 0.028,
		Color(1, 1, 1, minf(spec_a + 0.15, 1.0)), true, -1.0, true)

## The TRAVELLING glass shine: one bright diagonal band sweeping bottom-left →
## top-right across the face, clipped inside the rounded corners exactly like the
## static streaks above. `t` runs 0 → 1 to carry the band from fully off one
## corner to fully off the other; alpha peaks along the band's centre line (drawn
## as two half-bands so the peak lands on real vertices). Hero tiles sweep this
## every few seconds — the "someone tilted the glass" catch-light.
static func draw_shine_band(ci: CanvasItem, centre: Vector2, hw: float, t: float,
		strength: float = 0.20, hex: bool = false) -> void:
	if t < 0.0 or t > 1.0 or hw <= 0.0:
		return
	var tex := hex_mask() if hex else mask()
	var k := hw * 0.30                                 # band half-width in f = x + y space
	var c := lerpf(-2.0 * hw - k, 2.0 * hw + k, t)     # band centre line
	var square := PackedVector2Array([
		Vector2(-hw, -hw), Vector2(hw, -hw), Vector2(hw, hw), Vector2(-hw, hw)])
	for half in 2:
		var lo: float = c - k if half == 0 else c
		var hi: float = c if half == 0 else c + k
		var poly := _clip_diag(_clip_diag(square, hi, true), lo, false)
		# Vertex count alone is not enough — see `_MIN_POLY_AREA2`.
		if poly.size() < 3 or _poly_area2(poly) < _MIN_POLY_AREA2:
			continue
		var cols := PackedColorArray()
		for i in poly.size():
			var f := poly[i].x + poly[i].y
			var edge_t := clampf((f - lo) / maxf(hi - lo, 0.001), 0.0, 1.0)
			var a := strength * (edge_t if half == 0 else 1.0 - edge_t)
			cols.append(Color(1, 1, 1, a))
		ci.draw_polygon(_offset_pts(poly, centre), cols, _face_uvs(poly, hw), tex)

## Paint the full finish centred at `centre` with half-extent `hw` onto `ci`.
## Call from inside the item's _draw only.
static func draw_face(ci: CanvasItem, centre: Vector2, hw: float, vivid: Color,
		with_shadow: bool = true) -> void:
	_glass_face(ci, centre, hw, vivid, with_shadow)

## Same glass finish — kept as a separate entry point so the grid boards keep
## their own call site, but the material is ONE across every mode now.
## `with_halo` off skips the ambient bloom that hugs the tile shape: the Cube's
## stickers sit nearly edge-to-edge on a solid, and a halo that crosses onto
## the neighbouring plastic — or past the silhouette — reads as the sticker
## overflowing the toy instead of as printed ink.
static func draw_face_soft(ci: CanvasItem, centre: Vector2, hw: float, vivid: Color,
		with_shadow: bool = true, with_halo: bool = true) -> void:
	_glass_face(ci, centre, hw, vivid, with_shadow, false, false, with_halo)

## The ANTIMATTER face: the same glass, the same ramp colour, the same silhouette
## — with the key light inverted so the tile reads as a hole rather than a slab.
## Pass a negative tile's colour here and its positive twin's to draw_face_soft,
## and the pair reads as matter and antimatter of the same magnitude.
static func draw_face_void(ci: CanvasItem, centre: Vector2, hw: float, vivid: Color,
		with_shadow: bool = true) -> void:
	_glass_face(ci, centre, hw, vivid, with_shadow, true)

## The HEX face: the identical glass material carved to a flat-top hexagon. The
## caller still passes a single square half-extent — the hexagon is inscribed
## across its full width and is ~87% as tall, so a hex tile drops into the same
## square Control rect a grid tile uses.
static func draw_face_hex(ci: CanvasItem, centre: Vector2, hw: float, vivid: Color,
		with_shadow: bool = true) -> void:
	_glass_face(ci, centre, hw, vivid, with_shadow, false, true)

## Paint the SAME material as a glossy sphere centred at `centre`, radius `r`:
## ambient halo, thin near-white rim ring, vertical-gradient body, a curved
## crescent sheen across the upper-left hemisphere, a small white specular pair
## and a faint bottom bounce light. Used by Merge Drop's balls + queue chips.
static func draw_ball(ci: CanvasItem, centre: Vector2, r: float, vivid: Color,
		with_shadow: bool = true) -> void:
	var d := disc()
	var uvs := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	# Ambient halo — the sphere's own hue blooming around it.
	var halo_col := vivid.lerp(Color(1, 1, 1), 0.35)
	ci.draw_texture_rect(glow_dot(), Rect2(centre - Vector2.ONE * r * 1.55, Vector2.ONE * r * 3.1),
		false, Color(halo_col.r, halo_col.g, halo_col.b, 0.32))
	# Contact shadow.
	if with_shadow:
		var so := centre + Vector2(r * 0.05, r * 0.12)
		ci.draw_texture_rect(d, Rect2(so - Vector2.ONE * r * 1.02, Vector2.ONE * r * 2.04),
			false, Color(0, 0, 0, 0.18))
	# Thin near-white rim ring: the full disc in the edge-lit tint …
	var rim_top := vivid.lerp(Color(1, 1, 1), 0.78)
	var rim_bot := vivid.lerp(Color(1, 1, 1), 0.50)
	ci.draw_polygon(PackedVector2Array([
		centre + Vector2(-r, -r), centre + Vector2(r, -r),
		centre + Vector2(r, r), centre + Vector2(-r, r)]),
		PackedColorArray([rim_top, rim_top, rim_bot, rim_bot]), uvs, d)
	# … with the vertical-gradient body inset inside it.
	var br := r * 0.945
	var top := vivid.lightened(0.20)
	var bot := vivid.darkened(0.28)
	ci.draw_polygon(PackedVector2Array([
		centre + Vector2(-br, -br), centre + Vector2(br, -br),
		centre + Vector2(br, br), centre + Vector2(-br, br)]),
		PackedColorArray([top, top, bot, bot]), uvs, d)
	# Glass hollow (fresnel): the centre falls away into a deeper shade so the
	# edges carry the light — the body reads as a transparent crystal shell, not
	# a painted solid.
	ci.draw_texture_rect(glow_dot(),
		Rect2(centre - Vector2.ONE * br * 0.80, Vector2.ONE * br * 1.60),
		false, Color(0, 0, 0, 0.20))
	# A faint inner reflection ring just inside the shell — light bouncing along
	# the sphere's inside face.
	ci.draw_arc(centre, br * 0.84, 0.0, TAU, 40, Color(1, 1, 1, 0.10), r * 0.05, true)
	# The refracted caustic: light focused through the sphere pools bright at the
	# lower inside, in the ball's own hue lifted toward white.
	var caustic := vivid.lerp(Color.WHITE, 0.60)
	ci.draw_arc(centre, r * 0.50, PI * 0.32, PI * 0.68, 18,
		Color(caustic.r, caustic.g, caustic.b, 0.28), r * 0.20, true)
	# The diagonal streak becomes a curved crescent sheen across the upper-left.
	ci.draw_arc(centre, r * 0.70, PI * 1.02, PI * 1.60, 22, Color(1, 1, 1, 0.22), r * 0.16, true)
	ci.draw_texture_rect(glow_dot(),
		Rect2(centre + Vector2(-br * 0.95, -br * 0.95), Vector2(br * 0.9, br * 0.9)),
		false, Color(1, 1, 1, 0.18))
	# Small white specular pair on the rim side of the sheen — hotter for a glossier catch.
	ci.draw_circle(centre + Vector2(-r * 0.38, -r * 0.42), r * 0.11, Color(1, 1, 1, 0.78), true, -1.0, true)
	ci.draw_circle(centre + Vector2(-r * 0.30, -r * 0.52), r * 0.05, Color(1, 1, 1, 0.96), true, -1.0, true)
	# Faint bounce light along the bottom, closing the sphere.
	ci.draw_arc(centre, r * 0.84, PI * 0.25, PI * 0.75, 18, Color(1, 1, 1, 0.14), r * 0.10, true)
