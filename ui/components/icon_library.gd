class_name IconLibrary
extends RefCounted
## IconLibrary — the premium "glass + metal" UI icon set from the design sheet
## (stats, header controls and game-mode icons). Each icon is authored as two
## SVG paths — the silhouette `d` and the detail stroke `ds` — which _svg_for
## then draws TEN times over, in the sheet's own order: a blurred ambient
## occlusion shadow, an extruded side wall in the face's darkened hue, the face
## itself, and then the light on it (rim, specular, gloss). That stack is what
## makes a flat path read as a lit solid object; an icon is not a picture of one
## shape here, it is one shape lit. Rasterised on demand via
## Image.load_svg_from_string(), so icons stay crisp at any size and need no
## PNG assets.
##
## Use IconLibrary.texture("best_score", 96) for a Texture2D, or go through
## UI.icon_rect("best_score", 96, "") — UI.icon_tex() resolves library ids.
## These icons carry their own colour story (gold / silver / glass gradients);
## pass an empty tint key so the monochrome shader never flattens them.

# Gradient paint tokens (resolved against _GRADS in the generated SVG).
const G := "url(#gGold)"
const S := "url(#gSil)"
const B := "url(#gGlass)"
const P := "url(#gPurp)"
const C := "url(#gCyan)"
const F := "url(#gFlame)"
# Magenta: the pass-and-play row's "two people" token. The sheet paints people
# pink (nav_profile, share) and no other family in the token set does.
const MG := "url(#gMag)"

# Per-family glow colours (the sheet's drop-shadow glow, approximated as a
# radial halo behind the icon).
const GLOW_GOLD  := "rgba(255,200,80,0.3)"
const GLOW_SIL   := "rgba(200,220,255,0.18)"
const GLOW_GLASS := "rgba(90,180,255,0.32)"
const GLOW_PURP  := "rgba(160,100,255,0.35)"
const GLOW_CYAN  := "rgba(94,232,248,0.45)"
const GLOW_FLAME := "rgba(255,140,40,0.45)"

const _GRADS := '<defs>' \
	+ '<linearGradient id="gGold" x1="0" y1="0" x2="0.35" y2="1"><stop offset="0" stop-color="#ffefaf"/><stop offset="0.45" stop-color="#f5b83d"/><stop offset="1" stop-color="#c07818"/></linearGradient>' \
	+ '<linearGradient id="gSil" x1="0" y1="0" x2="0.35" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="0.45" stop-color="#cfe0f0"/><stop offset="1" stop-color="#7e9ab8"/></linearGradient>' \
	+ '<linearGradient id="gGlass" x1="0" y1="0" x2="0.35" y2="1"><stop offset="0" stop-color="#bfe2ff"/><stop offset="0.45" stop-color="#4da3e8"/><stop offset="1" stop-color="#2a6fb0"/></linearGradient>' \
	+ '<linearGradient id="gPurp" x1="0" y1="0" x2="0.35" y2="1"><stop offset="0" stop-color="#e2ccff"/><stop offset="0.45" stop-color="#9a6ce8"/><stop offset="1" stop-color="#6a3fb8"/></linearGradient>' \
	+ '<linearGradient id="gCyan" x1="0" y1="0" x2="0.35" y2="1"><stop offset="0" stop-color="#ccf6f4"/><stop offset="0.45" stop-color="#4ec9d4"/><stop offset="1" stop-color="#21879a"/></linearGradient>' \
	+ '<linearGradient id="gFlame" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffd894"/><stop offset="0.5" stop-color="#ff9f4a"/><stop offset="1" stop-color="#e86a1a"/></linearGradient>' \
	+ '<linearGradient id="gMag" x1="0" y1="0" x2="0.35" y2="1"><stop offset="0" stop-color="#ffd6f2"/><stop offset="0.45" stop-color="#f062c8"/><stop offset="1" stop-color="#a8288c"/></linearGradient>' \
	+ '<linearGradient id="rimTop" x1="0" y1="0" x2="0.2" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.85"/><stop offset="0.35" stop-color="#ffffff" stop-opacity="0.18"/><stop offset="0.7" stop-color="#ffffff" stop-opacity="0"/><stop offset="1" stop-color="#ffffff" stop-opacity="0.3"/></linearGradient>' \
	+ '<linearGradient id="glossSweep" x1="0" y1="0" x2="0.75" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.34"/><stop offset="0.34" stop-color="#ffffff" stop-opacity="0.05"/><stop offset="0.52" stop-color="#ffffff" stop-opacity="0"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></linearGradient>' \
	+ '<filter id="softAO" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="1.4"/></filter>' \
	+ '</defs>'

# The extruded side wall under each icon's face — the sheet's `edges` map, keyed
# by the gradient the face is painted in (falling back to the stroke colour for
# the stroke-only icons, then to slate). It is what turns a flat silhouette into
# a solid object, so it is derived from the paint rather than authored per icon:
# a token retinted without its edge reads as the old material seen edge-on.
const _EDGES := {
	G: "#8f5c0c", S: "#5b7592", B: "#1d4f80",
	P: "#4a2a8c", C: "#146a7c", F: "#a83c08", MG: "#7a1a66",
}
const EDGE_DEFAULT := "#33465e"

# The baked ambient-occlusion shadow: the silhouette again, dropped and blurred.
const AO_FILL := "rgba(6,12,26,0.55)"
const AO_STROKE := "rgba(6,12,26,0.5)"

static var _icons: Dictionary = {}
static var _cache: Dictionary = {}

# --- Public API ---------------------------------------------------------------

static func has_icon(id: String) -> bool:
	return _defs().has(id)

## Rasterise `id` at `px` design pixels (rendered 2x for HiDPI scaling).
## Returns null for unknown ids so callers can fall back gracefully.
static func texture(id: String, px: int = 128, with_glow: bool = true) -> Texture2D:
	var key := id + "|" + str(px) + ("|g" if with_glow else "")
	if _cache.has(key):
		return _cache[key]
	var svg := _svg_for(id, with_glow)
	if svg.is_empty():
		return null
	var img := Image.new()
	# Scale against the icon's OWN canvas (its box plus _svg_for's 2px margin on
	# each side), not a hardcoded 52: the nav glyphs are authored on a 64-unit
	# grid and would otherwise rasterise a third too large for the box asked for.
	var scale := clampf(float(px) * 2.0 / _canvas(id), 0.25, 12.0)
	if img.load_svg_from_string(svg, scale) != OK:
		return null
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

## The icon's glow colour (for FX layers that want to echo it).
static func glow_color(id: String) -> Color:
	if not has_icon(id):
		return Color(1, 1, 1, 0.2)
	var ic: Dictionary = _defs()[id]
	return _parse_rgba(String(ic["glow"]))

# --- SVG assembly -------------------------------------------------------------

## The blank ring left around the authoring box, in box units.
##
## The token set needs 3 to hold the sheet's ambient-occlusion shadow, which is
## dropped 3 units and then blurred; at the old 2 the softest tail of it met a
## hard straight cut along the bottom of the texture on the tallest glyphs. The
## raw-SVG families (nav, 72-unit tokens) bake their own contact shadow INSIDE
## their box and keep 2 — the margin is fitted to the TextureRect along with the
## art, so widening theirs would shrink them for no reason and slide the pixel
## bands test_action_icons measures off their elements.
static func _margin(id: String) -> float:
	if not has_icon(id):
		return 3.0
	return 2.0 if not String(_defs()[id]["svg"]).is_empty() else 3.0

## The rendered canvas edge for `id`: its authoring box plus _margin on every
## side. 54 for the token set's 48-unit grid, 68 for the nav glyphs' 64-unit one.
static func _canvas(id: String) -> float:
	if not has_icon(id):
		return 54.0
	return float(_defs()[id]["box"]) + 2.0 * _margin(id)

static func _svg_for(id: String, with_glow: bool) -> String:
	if not has_icon(id):
		return ""
	var ic: Dictionary = _defs()[id]
	var box := float(ic["box"])
	var m := _margin(id)
	var canvas := str(box + 2.0 * m)
	var org := str(-m)
	var s := '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="%s %s %s %s">' \
		% [canvas, canvas, org, org, canvas, canvas]
	if with_glow:
		s += _glow_svg(String(ic["glow"]), box)
	# The raw-SVG set (the bottom-nav glyphs) ships its own <defs> and paint,
	# transcribed from the design sheet. It bypasses the token pipeline below
	# because that pipeline cannot express per-icon gradients, group transforms
	# or rounded rects — and matching the sheet exactly is the whole point of it.
	var raw := String(ic["svg"])
	if not raw.is_empty():
		return s + raw + "</svg>"
	s += _GRADS
	# The sheet's ten-layer stack, in its order. Every layer is drawn from the
	# SAME two paths — the silhouette `d` and the detail stroke `ds` — which is
	# what makes an icon read as one solid object lit from the top left rather
	# than as a pile of shapes: shadow, side wall, face, then the light on it.
	#
	# One deliberate departure: the sheet's gloss sweep is a `mix-blend-mode:
	# screen` layer. The rasteriser ignores `mix-blend-mode` (it is not an
	# error — the paint simply composites normally), and since the sweep is
	# white at low alpha over the icon's own mid-tones the two are
	# indistinguishable here, so it ships without the declaration rather than
	# with one that reads as supported.
	var d := String(ic["d"])
	var ds := String(ic["ds"])
	var edge := String(ic["edge"])
	var caps := ""
	if not ds.is_empty():
		caps = 'stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"' % str(float(ic["sw"]))
	# 1-2. Ambient occlusion: the silhouette dropped 3 and blurred.
	if not d.is_empty():
		s += '<path d="%s" transform="translate(0 3)" %s filter="url(#softAO)"/>' \
			% [d, _paint("fill", AO_FILL)]
	if not ds.is_empty():
		s += '<path d="%s" transform="translate(0 3)" fill="none" %s %s filter="url(#softAO)"/>' \
			% [ds, _paint("stroke", AO_STROKE), caps]
	# 3-4. The extruded side wall, 1.7 below the face and in the face's own
	# darkened hue — the icon's thickness.
	if not d.is_empty():
		s += '<path d="%s" transform="translate(0 1.7)" fill="%s"/>' % [d, edge]
	if not ds.is_empty():
		s += '<path d="%s" transform="translate(0 1.7)" fill="none" stroke="%s" %s/>' % [ds, edge, caps]
	# 5-7. The face itself: gradient fill, second colour, detail stroke.
	if not d.is_empty():
		s += '<path d="%s" %s/>' % [d, _paint("fill", String(ic["fill"]))]
	var d2 := String(ic["d2"])
	if not d2.is_empty():
		s += '<path d="%s" %s/>' % [d2, _paint("fill", String(ic["f2"]))]
	if not ds.is_empty():
		s += '<path d="%s" fill="none" %s %s/>' % [ds, _paint("stroke", String(ic["sc"])), caps]
	# 8-10. The light: a rim that catches along the top-left contour, the
	# hand-placed specular, and the sweep across the whole face.
	if not d.is_empty():
		s += '<path d="%s" fill="none" stroke="url(#rimTop)" stroke-width="1.1" stroke-linejoin="round"/>' % d
	var hl := String(ic["hl"])
	if not hl.is_empty():
		s += '<path d="%s" %s/>' % [hl, _paint("fill", String(ic["hlc"]))]
	if not d.is_empty():
		s += '<path d="%s" fill="url(#glossSweep)"/>' % d
	return s + "</svg>"

## A soft radial halo standing in for the sheet's CSS drop-shadow glow, sized to
## the icon's own authoring box.
static func _glow_svg(glow: String, box: float = 48.0) -> String:
	var col := _parse_rgba(glow)
	var hex := "#%02x%02x%02x" % [int(col.r * 255.0), int(col.g * 255.0), int(col.b * 255.0)]
	var c := str(box * 0.5)
	return ('<radialGradient id="glow">' \
		+ '<stop offset="0" stop-color="%s" stop-opacity="%.3f"/>' % [hex, col.a * 0.55] \
		+ '<stop offset="0.65" stop-color="%s" stop-opacity="%.3f"/>' % [hex, col.a * 0.22] \
		+ '<stop offset="1" stop-color="%s" stop-opacity="0"/>' % hex \
		+ '</radialGradient><circle cx="%s" cy="%s" r="%s" fill="url(#glow)"/>' \
			% [c, c, str(box * 0.5 + 1.0)])

## Emit fill/stroke attributes; rgba() specs become hex + *-opacity so the SVG
## rasteriser never has to parse CSS colour functions.
static func _paint(kind: String, spec: String) -> String:
	if spec.begins_with("rgba("):
		var col := _parse_rgba(spec)
		var hex := "#%02x%02x%02x" % [int(col.r * 255.0), int(col.g * 255.0), int(col.b * 255.0)]
		return '%s="%s" %s-opacity="%.3f"' % [kind, hex, kind, col.a]
	return '%s="%s"' % [kind, spec]

static func _parse_rgba(spec: String) -> Color:
	if not spec.begins_with("rgba("):
		return Color(spec)
	var parts := spec.trim_prefix("rgba(").trim_suffix(")").split(",")
	if parts.size() != 4:
		return Color.WHITE
	return Color(
		float(parts[0]) / 255.0, float(parts[1]) / 255.0,
		float(parts[2]) / 255.0, float(parts[3]))

# --- Generated path data ------------------------------------------------------

## Rounded-square subpath (the tile silhouette used by the grid/mode icons).
static func _rr(x: float, y: float, s: float, r: float) -> String:
	var w := snappedf(s - 2.0 * r, 0.01)
	var rs := str(r)
	return "M%s %s h%s a%s %s 0 0 1 %s %s v%s a%s %s 0 0 1 -%s %s h-%s a%s %s 0 0 1 -%s -%s v-%s a%s %s 0 0 1 %s -%s Z " % [
		str(snappedf(x + r, 0.01)), str(y), str(w),
		rs, rs, rs, rs, str(w),
		rs, rs, rs, rs, str(w),
		rs, rs, rs, rs, str(w),
		rs, rs, rs, rs]

## n×n board of rounded tiles inside the 48-unit canvas. `skip_row` /
## `skip_col` leave one cell out so an icon can draw it another way (Vanish's
## dissolving corner); -1 keeps every cell.
static func _grid_path(n: int, r: float, skip_row: int = -1, skip_col: int = -1) -> String:
	var d := ""
	var c := (36.0 - float(n - 1) * 3.0) / float(n)
	for i in n:
		for j in n:
			if i == skip_row and j == skip_col:
				continue
			d += _rr(6.0 + float(j) * (c + 3.0), 6.0 + float(i) * (c + 3.0), c, r)
	return d

## A cols×rows block of c-unit tiles with `gap` between them, centred on the
## 48-unit canvas. The wide boards (Five's strip, Notakto's three) are not
## square, so _grid_path cannot draw them.
static func _tile_rows(cols: int, rows: int, c: float, gap: float, r: float) -> String:
	var x0 := 24.0 - (float(cols) * c + float(cols - 1) * gap) * 0.5
	var y0 := 24.0 - (float(rows) * c + float(rows - 1) * gap) * 0.5
	var d := ""
	for i in rows:
		for j in cols:
			d += _rr(snappedf(x0 + float(j) * (c + gap), 0.01),
				snappedf(y0 + float(i) * (c + gap), 0.01), c, r)
	return d

## The hairline 3×3 ruled inside every cell of an n×n board (Ultimate's board
## of boards), stopping `inset` short of each cell's edge.
static func _cell_lines(n: int, inset: float) -> String:
	var d := ""
	var c := (36.0 - float(n - 1) * 3.0) / float(n)
	for i in n:
		for j in n:
			var x0 := 6.0 + float(j) * (c + 3.0)
			var y0 := 6.0 + float(i) * (c + 3.0)
			for k in [1, 2]:
				var t := c * float(k) / 3.0
				d += "M%.2f %.2f V%.2f M%.2f %.2f H%.2f " % [
					x0 + t, y0 + inset, y0 + c - inset,
					x0 + inset, y0 + t, x0 + c - inset]
	return d

## One flat-top hexagon as an SVG subpath, centred at (cx, cy) with half-width a.
## Same orientation as the real board (see core/hex_board.gd) so the icon depicts
## the mode rather than merely gesturing at it.
static func _hex_path(cx: float, cy: float, a: float) -> String:
	var b := a * 0.8660254
	return "M%.2f %.2f L%.2f %.2f L%.2f %.2f L%.2f %.2f L%.2f %.2f L%.2f %.2f Z " % [
		cx + a, cy,
		cx + a * 0.5, cy + b,
		cx - a * 0.5, cy + b,
		cx - a, cy,
		cx - a * 0.5, cy - b,
		cx + a * 0.5, cy - b]

## The six hexes RINGING the centre — the radius-1 board with its middle cell
## left out, so the centre can be painted separately in a second colour.
static func _honeycomb_ring(a: float) -> String:
	var pitch := 7.6
	var d := ""
	for c: Vector2i in [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
			Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]:
		d += _hex_path(
			24.0 + 1.5 * pitch * float(c.x),
			24.0 + 1.7320508 * pitch * (0.5 * float(c.x) + float(c.y)),
			a)
	return d

## Eight-tooth gear ring (settings).
static func _gear_path() -> String:
	var d := ""
	for k in 8:
		var a := float(k) * PI / 4.0
		var ca := cos(a)
		var sa := sin(a)
		var seg := ""
		for p in [[-3.6, -20.0], [3.6, -20.0], [3.6, -11.0], [-3.6, -11.0]]:
			var x: float = p[0]
			var y: float = p[1]
			seg += ("" if seg.is_empty() else " L") + "%.1f %.1f" % [24.0 + x * ca - y * sa, 24.0 + x * sa + y * ca]
		d += "M" + seg + " Z "
	return d + "M24 11 a13 13 0 1 0 0.01 0 Z M24 18 a6 6 0 1 1 -0.01 0 Z"

# --- Icon definitions (ported verbatim from the design sheet) ------------------

static func _ic(d: Dictionary) -> Dictionary:
	var base := {
		"d": "", "fill": "none", "d2": "", "f2": "none",
		"ds": "", "sc": "none", "sw": 0.0,
		"hl": "", "hlc": "rgba(255,255,255,0.35)",
		"glow": "rgba(255,255,255,0.2)",
		# Raw inner SVG (see _svg_for) and the grid it is authored on. Empty +
		# 48 for every token-built icon; the nav glyphs set both.
		"svg": "", "box": 48.0,
	}
	base.merge(d, true)
	base["edge"] = _edge_for(String(base["fill"]), String(base["sc"]))
	return base

## The side-wall colour for a face painted in `fill` (or, for the stroke-only
## icons, stroked in `sc`).
static func _edge_for(fill: String, sc: String) -> String:
	if _EDGES.has(fill):
		return String(_EDGES[fill])
	if _EDGES.has(sc):
		return String(_EDGES[sc])
	return EDGE_DEFAULT

## One bottom-nav glossy glyph: raw sheet markup on the 64-unit grid.
##
## NOTE for anyone transcribing more of these — every `rgba(r,g,b,a)` in the
## source sheet must be pre-resolved to `#rrggbb` plus a matching
## `fill-opacity` / `stroke-opacity`. The rasteriser does not parse CSS colour
## functions and silently drops the whole paint, which reads as a missing
## shape rather than an error. `_paint` does the same conversion for the token
## set; the raw set has to carry it inline.
static func _nav(markup: String, glow: String) -> Dictionary:
	return _ic({"svg": markup, "box": 64.0, "glow": glow})

## One token from the design sheet's 72-unit grid — the three currencies plus
## the storefront and paper plane, which the sheet draws in the same material
## language ("storefront with striped awning, magenta paper plane"). Raw sheet
## markup, same rgba -> hex + *-opacity rule as _nav, plus two deliberate
## departures from the sheet:
##
##  • The GLINT is dropped. It is a CSS keyframe sparkle, and the sheet's own
##    component disables it under 40px — these render in a HUD pill at ~56px.
##    A texture is a single frame, so a "glint" here would be a sparkle frozen
##    at its brightest, which reads as a stray artifact rather than a shine.
##  • Callers pass with_glow = false (UI.icon_tex_flat / circle_button's
##    with_glow arg). The sheet's note is explicit — "no container, no baked-in
##    glow, each icon carries its own contour so it reads on any surface" — and
##    each of these already has a dark stroke and a cast shadow doing that job.
##    The glow colour is still declared because callers echo it (the HUD's pill
##    rim, spend/earn flashes).
static func _token72(markup: String, glow: String) -> Dictionary:
	return _ic({"svg": markup, "box": 72.0, "glow": glow})

static func _defs() -> Dictionary:
	if not _icons.is_empty():
		return _icons
	var play_d := "M24 3 a21 21 0 1 0 0.01 0 Z"
	var play_hl := "M10 16.5 a16.5 16.5 0 0 1 11 -9.5 l1 3.5 a13 13 0 0 0 -8.5 7.5 Z"
	# The shop's scalloped awning hem and its shopfront wall. Each is drawn THREE
	# times in that token (cast shadow, clip path, contour), and a scallop that
	# drifts between the three shows up as a hairline of the wrong colour along
	# the hem — so they are named once rather than transcribed three times.
	var s_awning := "M7 33q4.7 5.5 9.4 0 4.7 5.5 9.4 0 4.7 5.5 9.4 0 4.7 5.5 9.4 0 4.7 5.5 9.4 0 4.7 5.5 9.4 0V22H7z"
	var s_wall := "M12 33h48v27a4 4 0 0 1-4 4H16a4 4 0 0 1-4-4z"
	_icons = {
		# --- Stats (design sheet "Stats Icons") ---------------------------------
		# Transcribed verbatim from that sheet's STATS section. Every one of these
		# is drawn through the ten-layer stack in _svg_for, which is why several
		# carry an `f2` or an `sc` that is a translucent BROWN rather than a
		# colour: those are shading passes over the gold face (the crown's
		# recessed bays, the bar under it), not paint in their own right, and they
		# only read correctly with the side wall and rim underneath and over them.
		"highest_tile": _ic({"d": "M5.5 33.5 L7.5 16.5 L11.5 22 L15 8.5 L19.5 20.5 L24 4.5 L28.5 20.5 L33 8.5 L36.5 22 L40.5 16.5 L42.5 33.5 Z M4.5 34.5 H43.5 a2.6 2.6 0 0 1 2.6 2.6 V41.4 a2.6 2.6 0 0 1 -2.6 2.6 H4.5 A2.6 2.6 0 0 1 1.9 41.4 V37.1 A2.6 2.6 0 0 1 4.5 34.5 Z", "fill": G,
			"d2": "M7.5 16.5 L11.5 22 L9 33.5 H5.5 Z M15 8.5 L19.5 20.5 L16 33.5 L12.5 25 Z M24 4.5 L28.5 20.5 L24 33.5 Z M33 8.5 L36.5 22 L38.5 33.5 H35 L30 22 Z M40.5 16.5 L42.5 33.5 H39.8 Z", "f2": "rgba(120,70,4,0.4)",
			"ds": "M3.5 37.6 H44.5", "sc": "rgba(120,70,4,0.4)", "sw": 1.4,
			"hl": "M7.5 14.4 a2.1 2.1 0 1 0 0.01 0 Z M15 6.2 a2.4 2.4 0 1 0 0.01 0 Z M24 1.8 a2.8 2.8 0 1 0 0.01 0 Z M33 6.2 a2.4 2.4 0 1 0 0.01 0 Z M40.5 14.4 a2.1 2.1 0 1 0 0.01 0 Z M3.5 39.2 H44.5 v1.3 H3.5 Z M24 36.6 l2.6 2.6 -2.6 2.6 -2.6 -2.6 Z M12 37.6 l1.8 1.8 -1.8 1.8 -1.8 -1.8 Z M36 37.6 l1.8 1.8 -1.8 1.8 -1.8 -1.8 Z",
			"hlc": "#fff8e0", "glow": GLOW_GOLD}),
		"best_score": _ic({"d": "M13 4 H35 a1.6 1.6 0 0 1 1.6 1.6 V15 C36.6 23.4 31.6 28.6 27.4 29.8 V33 H31.6 a1.9 1.9 0 0 1 1.9 1.9 V38.4 H14.5 V34.9 A1.9 1.9 0 0 1 16.4 33 H20.6 V29.8 C16.4 28.6 11.4 23.4 11.4 15 V5.6 A1.6 1.6 0 0 1 13 4 Z M10.6 40 H37.4 a1.9 1.9 0 0 1 1.9 1.9 V45.4 H8.7 V41.9 A1.9 1.9 0 0 1 10.6 40 Z M11.4 7.4 H8 C3.4 7.4 1.4 11.4 2.6 15.8 C3.8 20.2 7.4 22.8 12.4 23.6 L11.8 20.1 C8.4 19.4 6.4 17.4 5.7 14.8 C5 12 6 10.9 8.4 10.9 H11.4 Z M36.6 7.4 H40 C44.6 7.4 46.6 11.4 45.4 15.8 C44.2 20.2 40.6 22.8 35.6 23.6 L36.2 20.1 C39.6 19.4 41.6 17.4 42.3 14.8 C43 12 42 10.9 39.6 10.9 H36.6 Z", "fill": G,
			"d2": "M17 8 H31 V15.5 C31 20.5 28 24 24 25 C20 24 17 20.5 17 15.5 Z", "f2": "rgba(120,70,4,0.4)",
			"ds": "M14.5 8 V15 C14.5 19 16 22 18.5 24", "sc": "rgba(255,255,255,0.32)", "sw": 1.6,
			"hl": "M24 9.8 L25.53 13.9 L29.9 14.08 L26.47 16.8 L27.64 21.02 L24 18.6 L20.36 21.02 L21.53 16.8 L18.1 14.08 L22.47 13.9 Z M12 41.6 h24 v1.7 H12 Z M17 34.8 h14 v1.6 H17 Z",
			"hlc": "#ffeaa6", "glow": GLOW_GOLD}),
		"games_played": _ic({"d": "M18 10.5 H30 C40.5 10.5 46.5 18.5 46.5 27.5 C46.5 36 42.5 42 37 42 C31.5 42 30.5 34 26 34 H22 C17.5 34 16.5 42 11 42 C5.5 42 1.5 36 1.5 27.5 C1.5 18.5 7.5 10.5 18 10.5 Z", "fill": S,
			"d2": "M13.5 17.4 h3.4 v3.6 h3.6 v3.4 h-3.6 v3.6 h-3.4 v-3.6 h-3.6 v-3.4 h3.6 Z M33.5 16.4 a2.4 2.4 0 1 0 0.01 0 Z M38 21 a2.4 2.4 0 1 0 0.01 0 Z M33.5 25.6 a2.4 2.4 0 1 0 0.01 0 Z M29 21 a2.4 2.4 0 1 0 0.01 0 Z M24 25.6 a3.4 3.4 0 1 0 0.01 0 Z", "f2": "rgba(74,96,124,0.85)",
			"ds": "M13 6.5 C15 9 16.5 10 18 10.5 M35 6.5 C33 9 31.5 10 30 10.5 M10 37.5 C13.5 33.5 18 31.5 24 31.5 C30 31.5 34.5 33.5 38 37.5", "sc": "rgba(255,255,255,0.3)", "sw": 1.7,
			"hl": "M17.5 12.4 H30.5 C35.5 12.4 39.5 13.9 42.2 16.3 C31.5 18.1 16.5 18.1 5.8 16.3 C8.5 13.9 12.5 12.4 17.5 12.4 Z M24 23.4 a3.4 3.4 0 0 1 3 1.8 a3.4 3.4 0 0 0 -5.8 2.4 a3.4 3.4 0 0 1 2.8 -4.2 Z",
			"hlc": "rgba(255,255,255,0.5)", "glow": GLOW_SIL}),
		"games_won": _ic({"d": "M24 4 L29.5 17.5 L44 18.5 L33 27.5 L36.8 41.5 L24 33.5 L11.2 41.5 L15 27.5 L4 18.5 L18.5 17.5 Z", "fill": B,
			"d2": "M24 4 L29.5 17.5 L24 33.5 L18.5 17.5 Z", "f2": "rgba(255,255,255,0.25)",
			"ds": "M24 8 L27.5 17 M20.5 17 L24 8", "sc": "rgba(255,255,255,0.55)", "sw": 1.4,
			"hl": "M21.5 13 h3.2 l-1.6 4.4 Z", "hlc": "rgba(255,255,255,0.7)", "glow": GLOW_GLASS}),
		"win_rate": _ic({"d": "M30 5.5 H43 a1.5 1.5 0 0 1 1.5 1.5 V20 Z", "fill": G,
			"d2": "M5 31 a1.6 1.6 0 0 1 1.6 -1.6 h3.4 a1.6 1.6 0 0 1 1.6 1.6 V43 H5 Z M15.4 25 a1.6 1.6 0 0 1 1.6 -1.6 h3.4 a1.6 1.6 0 0 1 1.6 1.6 V43 h-6.6 Z M25.8 18 a1.6 1.6 0 0 1 1.6 -1.6 h3.4 a1.6 1.6 0 0 1 1.6 1.6 V43 h-6.6 Z M36.2 11 a1.6 1.6 0 0 1 1.6 -1.6 h3.4 a1.6 1.6 0 0 1 1.6 1.6 V43 h-6.6 Z", "f2": "rgba(150,200,255,0.28)",
			"ds": "M5 38 L16.5 30 L25 33.5 L40.5 12", "sc": G, "sw": 4.4,
			"hl": "M5.4 30.2 h1.8 V43 H5.4 Z M15.8 24.2 h1.8 V43 h-1.8 Z M26.2 17.2 h1.8 V43 h-1.8 Z M36.6 10.2 h1.8 V43 h-1.8 Z",
			"hlc": "rgba(255,255,255,0.3)", "glow": GLOW_GOLD}),
		"average_score": _ic({"d": "M14 8 H34 L43 19 L24 42 L5 19 Z", "fill": B,
			"d2": "M19 8 H29 L33 19 H15 Z", "f2": "rgba(255,255,255,0.38)",
			"ds": "M5 19 H43 M14 8 L15 19 L24 42 M34 8 L33 19 L24 42", "sc": "rgba(235,248,255,0.65)", "sw": 1.3, "glow": GLOW_GLASS}),
		"total_moves": _ic({"d": "M34.32 9.26 A18 18 0 1 1 19.34 6.61 L20.74 11.83 A12.6 12.6 0 1 0 31.23 13.68 Z M27.5 4.1 L21.2 13.6 L18.9 4.9 Z", "fill": S,
			"d2": "M33.41 10.57 A16.4 16.4 0 1 1 19.75 8.16 L20.32 10.28 A14.2 14.2 0 1 0 32.15 12.37 Z", "f2": "rgba(74,96,124,0.5)",
			"hl": "M7.09 17.84 A18 18 0 0 1 27.13 6.27 L26.88 7.65 A16.6 16.6 0 0 0 8.4 18.32 Z",
			"hlc": "rgba(255,255,255,0.55)", "glow": GLOW_SIL}),
		"longest_session": _ic({"d": "M24 11 a16 16 0 1 0 0.01 0 Z M20 3 H28 a1.6 1.6 0 0 1 1.6 1.6 V8 a1.6 1.6 0 0 1 -1.6 1.6 H20 A1.6 1.6 0 0 1 18.4 8 V4.6 A1.6 1.6 0 0 1 20 3 Z M35.6 6.2 L40.4 11 L37.4 14 L32.6 9.2 Z M12.4 6.2 L15.4 9.2 L10.6 14 L7.6 11 Z", "fill": G,
			"d2": "M24 15 a12 12 0 1 0 0.01 0 Z", "f2": "#e6edf6",
			"ds": "M24 27 V18.6 M24 27 L29.8 30.4 M24 16.4 v1.8 M24 36 v1.8 M13.4 27 h1.8 M32.8 27 h1.8", "sc": "rgba(58,74,98,0.85)", "sw": 2.2,
			"hl": "M14.4 21.6 A12 12 0 0 1 26.4 15.4 l0.4 2.6 A9.4 9.4 0 0 0 16.6 23 Z M24 25.4 a1.7 1.7 0 1 0 0.01 0 Z",
			"hlc": "rgba(255,255,255,0.8)", "glow": GLOW_GOLD}),
		"total_play_time": _ic({"ds": "M24 24 C19.5 15 6 15 6 24 C6 33 19.5 33 24 24 C28.5 15 42 15 42 24 C42 33 28.5 33 24 24", "sc": C, "sw": 6.6,
			"hl": "M7.2 21 A9.4 9.4 0 0 1 20.6 18.2 L18.8 21 A6.8 6.8 0 0 0 9.6 22.8 Z M27.4 18.2 A9.4 9.4 0 0 1 40.8 21 L38.4 22.8 A6.8 6.8 0 0 0 29.2 21 Z",
			"hlc": "rgba(255,255,255,0.6)", "glow": GLOW_CYAN}),
		"day_streak": _ic({"d": "M24 2 C30.5 10 37.5 15 37.5 26 A13.5 13.5 0 1 1 10.5 26 C10.5 18.6 15.5 15 18 9 C19.2 13.6 20.8 15.8 23 17 C21.6 11.4 22 6.4 24 2 Z", "fill": F,
			"d2": "M24 18 C20.4 23.6 17.6 26.2 17.6 30.8 A6.4 6.4 0 0 0 30.4 30.8 C30.4 26.2 27.6 23.6 24 18 Z", "f2": "#ffcf3e",
			"ds": "M13.8 23.5 C12.6 27.8 13.6 31.6 16.4 34.4 M34.4 22 C36.4 25.8 36.4 29.6 34.6 32.6", "sc": "rgba(255,216,128,0.5)", "sw": 1.8,
			"hl": "M24 22.6 C22.4 26 21.2 27.8 21.2 30.4 A2.8 2.8 0 0 0 26.8 30.4 C26.8 27.8 25.6 26 24 22.6 Z M24 4.6 C25 9.4 28.4 13 31.6 16.6 C28 13.4 25 9.8 24 4.6 Z",
			"hlc": "#fffbe4", "glow": GLOW_FLAME}),
		# --- Header & controls ---
		"how_to_play": _ic({"d": "M24 10 C19 6.5 12 6 5 7.5 V38 C12 36.5 19 37 24 40.5 C29 37 36 36.5 43 38 V7.5 C36 6 29 6.5 24 10 Z", "fill": G,
			"d2": "M24 13.5 C20.2 11 14.8 10.4 9 11.3 V34.6 C14.8 33.8 20.2 34.3 24 36.8 C27.8 34.3 33.2 33.8 39 34.6 V11.3 C33.2 10.4 27.8 11 24 13.5 Z", "f2": "#f6f1e2",
			"ds": "M24 14 V36.5 M13 17 C16.5 16.6 19.5 17 21.5 18 M13 22 C16.5 21.6 19.5 22 21.5 23 M13 27 C16.5 26.6 19.5 27 21.5 28 M27 18 C29 17 32 16.6 35.5 17 M27 23 C29 22 32 21.6 35.5 22 M27 28 C29 27 32 26.6 35.5 27",
			"sc": "rgba(120,90,30,0.45)", "sw": 1.4, "glow": GLOW_GOLD}),
		"profile": _ic({"d": "M24 5 a9.5 9.5 0 1 0 0.01 0 Z M24 26 C14.5 26 7.5 31.5 6.5 39.5 A3.5 3.5 0 0 0 10 43 H38 A3.5 3.5 0 0 0 41.5 39.5 C40.5 31.5 33.5 26 24 26 Z", "fill": G,
			"hl": "M18 8.5 a8 8 0 0 1 7.5 -1.5 C21 8 18.5 10.5 17.5 14 A8 8 0 0 1 18 8.5 Z M11 36 C13.5 31.5 18 29 24 28.8 C17 30.5 13.5 33.5 12.5 38.5 Z",
			"hlc": "rgba(255,255,255,0.4)", "glow": GLOW_GOLD}),
		"settings": _ic({"d": _gear_path(), "fill": S, "glow": GLOW_SIL}),
		# --- Profile's section rail ---------------------------------------------
		# Three glyphs the set was missing, authored on the same 48-unit grid as
		# their neighbours so the rail reads as ONE family. The rail tints them
		# monochrome through UI.icon_material, so the gradient fills below only
		# matter wherever else these get used at full colour — but they are set
		# honestly (gold for money, glass for people, cyan for data) rather than
		# left at the default, because "it is tinted at the only call site" is how
		# an icon ends up unusable at the second one.
		#
		# Not reused from the existing set on purpose: the storefront/currency/
		# paper-plane tokens are `_token72` full-colour art with a baked contour
		# and cast shadow, and dropping one into a column of `_ic` line glyphs is
		# the same family break the Shop plan called out when three upgrade rows
		# all drew the same gem.
		# Body, pocket, clasp — and NO flap. The first cut carried a triangular flap
		# folded over the top edge, which at rail size (60px, tinted flat) merged
		# with the body into an unreadable blob. Silhouette first: at this size an
		# icon is its outline, and every internal detail has to earn its contrast.
		"wallet": _ic({"d": "M9 13 H39 a6 6 0 0 1 6 6 V37 a6 6 0 0 1 -6 6 H9 a6 6 0 0 1 -6 -6 V19 a6 6 0 0 1 6 -6 Z", "fill": G,
			"d2": "M28 23 H45 V33 H28 a5 5 0 0 1 0 -10 Z", "f2": "rgba(255,255,255,0.55)",
			"hl": "M34.5 26.5 a2.4 2.4 0 1 1 -0.01 0 Z", "hlc": "rgba(60,45,10,0.6)",
			"glow": GLOW_GOLD}),
		"chart": _ic({"d": "M6 27 H15 V42 H6 Z M19.5 17 H28.5 V42 H19.5 Z M33 7 H42 V42 H33 Z", "fill": C,
			"hl": "M6 27 H15 V30.5 H6 Z M19.5 17 H28.5 V20.5 H19.5 Z M33 7 H42 V10.5 H33 Z",
			"hlc": "rgba(255,255,255,0.42)", "glow": GLOW_CYAN}),
		"invite": _ic({"d": "M18 7 a8.5 8.5 0 1 0 0.01 0 Z M18 26 C10.5 26 4.5 31 3.5 38.5 A3 3 0 0 0 6.5 42 H29.5 A3 3 0 0 0 32.5 38.5 C31.5 31 25.5 26 18 26 Z M36.5 9 H41.5 V14 H46.5 V19 H41.5 V24 H36.5 V19 H31.5 V14 H36.5 Z", "fill": B,
			"hl": "M13 10 a7.5 7.5 0 0 1 7 -1.5 C16.5 9.5 14.5 11.5 13.5 14.5 A7.5 7.5 0 0 1 13 10 Z",
			"hlc": "rgba(255,255,255,0.38)", "glow": GLOW_GLASS}),
		# --- Profile's row leaders ----------------------------------------------
		# The remaining three the page's rows needed. Same 48-unit grid, same
		# family. `shield_lock` is deliberately NOT `rank_badge` reused: that badge
		# is the rank emblem's silhouette and means "achievement" everywhere else
		# in the app, so borrowing it for a privacy row would teach two meanings
		# for one shape.
		"mail": _ic({"d": "M5 12 H43 a4 4 0 0 1 4 4 V34 a4 4 0 0 1 -4 4 H5 a4 4 0 0 1 -4 -4 V16 a4 4 0 0 1 4 -4 Z", "fill": S,
			"ds": "M3.5 15 L24 28 L44.5 15", "sc": "rgba(40,52,70,0.75)", "sw": 3.0,
			"glow": GLOW_SIL}),
		"shield_lock": _ic({"d": "M24 3.5 L40.5 9.5 V22 C40.5 32 34 39.4 24 43.5 C14 39.4 7.5 32 7.5 22 V9.5 Z", "fill": C,
			"d2": "M19 23 H29 V33 H19 Z", "f2": "rgba(20,35,45,0.8)",
			"hl": "M20.5 23 V19.5 a3.5 3.5 0 0 1 7 0 V23 H25 V19.5 a1 1 0 0 0 -2 0 V23 Z",
			"hlc": "rgba(255,255,255,0.85)", "glow": GLOW_CYAN}),
		"trash": _ic({"d": "M12 14 H36 L33.5 41 A3 3 0 0 1 30.5 44 H17.5 A3 3 0 0 1 14.5 41 Z M18 6 H30 V11 H18 Z M8 11 H40 V15 H8 Z", "fill": S,
			"ds": "M20 21 V37 M24 21 V37 M28 21 V37", "sc": "rgba(40,52,70,0.7)", "sw": 2.4,
			"glow": GLOW_SIL}),
		# The design sheet's RANK section, and the one icon in it. Gold, not the
		# glass it used to be: it is the rank emblem, and every other "you earned
		# this" surface in the app (mastery crowns, medals, the win achievements)
		# is gold — a blue badge in that company read as a mode icon. The chevrons
		# below the star are the rank chevrons, which is what makes it a RANK badge
		# rather than a second trophy standing next to `best_score`.
		"rank_badge": _ic({"d": "M24 2 C30.5 5.5 36.5 7.2 42 7.6 V23 C42 33.8 34.5 41.8 24 46 C13.5 41.8 6 33.8 6 23 V7.6 C11.5 7.2 17.5 5.5 24 2 Z", "fill": G,
			"d2": "M24 7 C29.8 10 35 11.5 38 11.8 V22.8 C38 31.5 32 38.2 24 41.6 C16 38.2 10 31.5 10 22.8 V11.8 C13 11.5 18.2 10 24 7 Z", "f2": "rgba(120,70,4,0.42)",
			"ds": "M17.5 31.5 L24 34.8 L30.5 31.5 M18.5 35.8 L24 38.6 L29.5 35.8", "sc": "rgba(255,255,255,0.62)", "sw": 2.0,
			"hl": "M24 12 L26.2 17.9 L32.6 18.2 L27.6 22.2 L29.3 28.3 L24 24.8 L18.7 28.3 L20.4 22.2 L15.4 18.2 L21.8 17.9 Z M11.5 9.2 C16.4 8.6 20.5 7.2 24 4.9 V8.2 C20.3 10.2 16.2 11.5 11.5 12.1 Z",
			"hlc": "#ffeaa6", "glow": GLOW_GOLD}),
		"back": _ic({"d": "M21.5 5.5 L26 10 L15 21 H43 V27 H15 L26 38 L21.5 42.5 L3 24 Z", "fill": S,
			"hl": "M8 22.5 L21.5 9 L23.5 11 L12 22.5 Z", "hlc": "rgba(255,255,255,0.3)", "glow": GLOW_SIL}),
		"undo": _ic({"d": "M12.5 3.5 L3 14.5 L16.5 17.5 Z", "fill": G,
			"ds": "M10.5 14.5 A15.5 15.5 0 1 1 13 33", "sc": G, "sw": 4.5, "glow": GLOW_GOLD}),
		"restart": _ic({"d": "M9.5 2.5 L3.5 14.5 L17 13.5 Z M38.5 45.5 L44.5 33.5 L31 34.5 Z", "fill": S,
			"ds": "M37.5 15.5 A16.5 16.5 0 0 0 11 12.5 M10.5 32.5 A16.5 16.5 0 0 0 37 35.5", "sc": S, "sw": 4.2, "glow": GLOW_SIL}),
		"new_game": _ic({"d": "M19 8 a5 5 0 0 1 10 0 v11 h11 a5 5 0 0 1 0 10 h-11 v11 a5 5 0 0 1 -10 0 v-11 h-11 a5 5 0 0 1 0 -10 h11 Z", "fill": C,
			"hl": "M20.5 8.5 a3.5 3.5 0 0 1 7 0 v3.5 h-7 Z", "hlc": "rgba(255,255,255,0.45)", "glow": GLOW_CYAN}),
		# --- Game modes (ids match GameModes._CONFIGS) ---
		# "More Modes": the same 2x2 board the mode icons are built from, with the
		# fourth cell turned into an ellipsis — three tiles you know, one that stands
		# for the rest. Deliberately NOT a bare "..." or a chevron: on Home it sits in
		# a column of mode icons, so it has to read as one of them before it reads as
		# a doorway. Cells match _grid_path(2, 3.5) exactly (16.5 wide at 6 / 25.5).
		"more_modes": _ic({"d": _rr(6, 6, 16.5, 3.5) + _rr(25.5, 6, 16.5, 3.5) + _rr(6, 25.5, 16.5, 3.5),
			"fill": P,
			"d2": _rr(25.5, 25.5, 16.5, 3.5), "f2": B,
			"hl": "M29 33.75 a1.9 1.9 0 1 1 -0.01 0 Z M33.75 33.75 a1.9 1.9 0 1 1 -0.01 0 Z"
				+ " M38.5 33.75 a1.9 1.9 0 1 1 -0.01 0 Z",
			"hlc": "rgba(255,255,255,0.92)", "glow": GLOW_PURP}),
		"classic": _ic({"d": _grid_path(2, 3.5), "fill": G, "glow": GLOW_GOLD}),
		"challenger": _ic({"d": _grid_path(3, 2.5), "fill": P, "glow": GLOW_PURP}),
		"grand": _ic({"d": _grid_path(4, 2.0), "fill": B, "glow": GLOW_GLASS}),
		"merge_drop": _ic({"d": _rr(8, 29, 13, 2.5) + _rr(27, 29, 13, 2.5), "fill": B,
			"d2": _rr(17.5, 3, 13, 2.5), "f2": G,
			"ds": "M24 19.5 V26 M20 22.5 L24 26.5 L28 22.5", "sc": "#e8f4ff", "sw": 2.4, "glow": GLOW_GLASS}),
		"arena_fling": _ic({"d": "M26.5 7 H41 V21.5 Z", "fill": G,
			"ds": "M9 39 L31 17 M7 29 L12.5 23.5 M13 42 L18.5 36.5", "sc": G, "sw": 4.5, "glow": GLOW_GOLD}),
		"tower": _ic({"d": "M12 4 H17 V9 H21.5 V4 H26.5 V9 H31 V4 H36 V14 H12 Z M15 14 H33 L31.2 32 H16.8 Z M12 32 H36 V36.5 H12 Z M9 36.5 H39 V44 H9 Z", "fill": S,
			"d2": "M21.5 19.5 a2.5 2.5 0 0 1 5 0 V26.5 H21.5 Z", "f2": "#222c3a",
			"hl": "M16.2 15.5 h3 L17.8 30.5 h-2.4 Z M13.5 5.5 h2 v7 h-2 Z", "hlc": "rgba(255,255,255,0.35)", "glow": GLOW_SIL}),
		# Orbit: a studded sphere. The outline is the globe; the ring of small discs
		# is the visible hemisphere of faces, with one gold pole picked out.
		"orbit": _ic({"d": "M24 3.5 a20.5 20.5 0 1 1 -0.01 0 Z", "fill": B,
			"d2": "M24 10.5 a3.4 3.4 0 1 1 -0.01 0 Z M13.5 18 a3.4 3.4 0 1 1 -0.01 0 Z"
				+ " M34.5 18 a3.4 3.4 0 1 1 -0.01 0 Z M17.5 30 a3.4 3.4 0 1 1 -0.01 0 Z"
				+ " M30.5 30 a3.4 3.4 0 1 1 -0.01 0 Z", "f2": "#0d1b2e",
			"hl": "M24 10.5 a3.4 3.4 0 1 1 -0.01 0 Z", "hlc": "#f5b83d",
			"ds": "M6 24 a18 9 0 0 0 36 0 a18 9 0 0 0 -36 0", "sc": "rgba(235,248,255,0.45)",
			"sw": 1.3, "glow": GLOW_GLASS}),
		# Cube: an isometric 3x3x3 with its three visible faces. The lit top is
		# flame and the two shadowed sides glass blue — the same warm/cool split
		# Home's card gradient uses — with the stickers ruled in and the top's
		# centre picked out white, because a face centre is Cube's anvil.
		"cube": _ic({"d": "M6 16 L24 26 L24 44 L6 34 Z M42 16 L24 26 L24 44 L42 34 Z",
			"fill": B,
			"d2": "M24 6 L42 16 L24 26 L6 16 Z", "f2": F,
			"hl": "M24 12.67 L30 16 L24 19.33 L18 16 Z", "hlc": "rgba(255,255,255,0.9)",
			"ds": "M30 9.33 L12 19.33 M36 12.67 L18 22.67"
				+ " M18 9.33 L36 19.33 M12 12.67 L30 22.67"
				+ " M12 19.33 L12 37.33 M18 22.67 L18 40.67"
				+ " M6 22 L24 32 M6 28 L24 38"
				+ " M36 19.33 L36 37.33 M30 22.67 L30 40.67"
				+ " M42 22 L24 32 M42 28 L24 38",
			"sc": "rgba(235,248,255,0.42)", "sw": 1.2, "glow": GLOW_FLAME}),
		# Lattice: the same isometric cube as Cube, but READ AS GLASS — the shell
		# is the silhouette hexagon with only its three interior edges ruled in,
		# and the four flame nodes are tiles suspended inside it. Cube's icon is
		# about the surface (stickers, ruled faces); this one has to be about the
		# volume, or the two modes wear the same picture.
		"lattice": _ic({"d": "M24 6 L42 16 L42 34 L24 44 L6 34 L6 16 Z", "fill": B,
			"d2": "M24 17.4 a2.6 2.6 0 1 1 -0.01 0 Z M16.5 24.4 a2.6 2.6 0 1 1 -0.01 0 Z"
				+ " M31.5 24.4 a2.6 2.6 0 1 1 -0.01 0 Z M24 31.4 a2.6 2.6 0 1 1 -0.01 0 Z",
			"f2": F,
			"hl": "M24 17.4 a2.6 2.6 0 1 1 -0.01 0 Z", "hlc": "rgba(255,255,255,0.9)",
			"ds": "M24 26 L24 44 M24 26 L6 16 M24 26 L42 16"
				+ " M24 6 L42 16 L42 34 L24 44 L6 34 L6 16 Z",
			"sc": "rgba(235,248,255,0.50)", "sw": 1.3, "glow": GLOW_GLASS}),
		# Hex: the radius-1 honeycomb, flat-top like the real board. The gold centre
		# reads as the tile you are building and the ring as the six ways out of it.
		"hex": _ic({"d": _honeycomb_ring(7.0), "fill": B,
			"d2": _hex_path(24.0, 24.0, 7.0), "f2": G, "glow": GLOW_CYAN}),
		# Antimatter: a matter tile and its anti-tile, the pair that cancels. Same
		# silhouette, opposite fill and opposite sign — which is the whole rule.
		"antimatter": _ic({"d": _rr(2, 14, 20, 4), "fill": C,
			"d2": _rr(26, 14, 20, 4), "f2": "#171029",
			"ds": "M30.5 24 H41.5", "sc": "#c9b6ff", "sw": 3.2,
			"hl": "M6.5 22.5 h11 v3 h-11 Z M10.5 18.5 h3 v11 h-3 Z",
			"hlc": "#ffffff", "glow": GLOW_CYAN}),
		# --- The twenty modes, one icon each (ids = GameModes ids) --------------
		# Same 48-unit grid and ten-layer stack as the older mode icons above,
		# which stay for the screens that still name them. Each one is a small
		# lit object that shows the RULE, not the board size: readable at 72 px.
		# NUMSLIDE's six boards. Same 48-unit grid and ten-layer stack as the icons
		# above. Each one is a small lit object that shows the RULE, not the board
		# size: readable at 72 px, and distinguishable from each other at that
		# size, which is the harder half. _grid_path's skip_row / skip_col leaves
		# out one cell, which on this game is not a missing tile, it is THE HOLE.
		#
		# Cell geometry, for anything drawn on top of a 3x3: c = 10 units, pitch
		# 13, so cell (row, col) spans x = 6 + 13*col and its centre is at
		# 11 + 13*col. Top left is (11, 11), bottom right (37, 37).
		#
		# Classic: the plain tray with its hole bottom right, and the tile beside
		# it on its way in. The arrow is the whole game in one stroke.
		"classic_slide": _ic({"d": _grid_path(3, 2.5, 2, 2), "fill": G,
			"ds": "M28 37 H39 M35.5 33.5 L39 37 L35.5 40.5",
			"sc": "rgba(90,50,4,0.78)", "sw": 2.4,
			"hl": "M11 7.6 a3.4 3.4 0 1 0 0.01 0 Z M11 9.6 a1.4 1.4 0 1 1 -0.01 0 Z",
			"hlc": "rgba(90,50,4,0.78)", "glow": GLOW_GOLD}),
		# Rush: a clock with a tile set into its face. The one board in the game
		# with a clock on it, so the clock IS the icon.
		"rush": _ic({"d": "M24 5 a19 19 0 1 1 -0.01 0 Z", "fill": F,
			"d2": _rr(17, 17, 14, 3.0), "f2": "#3d1a06",
			"ds": "M24 24 V15 M24 24 L30.5 28 M24 8.5 v2.6 M39.5 24 h-2.6"
				+ " M24 39.5 v-2.6 M8.5 24 h2.6",
			"sc": "rgba(255,232,196,0.9)", "sw": 2.2,
			"hl": "M11.4 15.6 A15 15 0 0 1 25.6 9.1 l-0.3 2.3 A12.7 12.7 0 0 0 13.2 17 Z",
			"hlc": "rgba(255,255,255,0.6)", "glow": GLOW_FLAME}),
		# Lockdown: the tray with its top left cell welded shut. The seal ring is
		# on the cell the lock order finishes FIRST, which is where the mode
		# starts biting.
		"lockdown": _ic({"d": _grid_path(3, 2.5, 2, 2), "fill": P,
			"ds": "M6.5 11 a4.5 4.5 0 1 0 9 0 a4.5 4.5 0 1 0 -9 0",
			"sc": "#ffffff", "sw": 2.0,
			"hl": "M8.8 11.6 h4.4 v3.2 h-4.4 Z M9.6 11.6 v-1.4 a1.4 1.4 0 0 1 2.8 0 v1.4"
				+ " h-1 v-1.4 a0.5 0.5 0 0 0 -0.8 0 v1.4 Z",
			"hlc": "#f0e4ff", "glow": GLOW_PURP}),
		# Wrap: the FULL tray, no hole anywhere, and a line rolling off the right
		# edge and back in at the left. The missing hole is half the story and the
		# curve is the other half.
		# Twist: the FULL tray, no hole anywhere, and a quarter-turn arrow round
		# the junction where four of them meet. The missing hole is half the story
		# and the turn is the other half.
		"twist": _ic({"d": _grid_path(3, 2.5), "fill": C,
			# The arrowhead closing the turn, at the top of the arc.
			"d2": "M28.4 12.2 L24.2 9.4 L28.8 6.4 Z", "f2": "#ccf6f4",
			# A three-quarter arc centred on the junction at (17.5, 17.5), the
			# corner shared by the four top-left tiles.
			"ds": "M17.5 9.6 a7.9 7.9 0 1 0 7.9 7.9",
			"sc": "#ccf6f4", "sw": 2.8,
			"hl": "M17.5 15.4 a2.1 2.1 0 1 0 0.01 0 Z", "hlc": "rgba(255,255,255,0.9)",
			"glow": GLOW_CYAN}),
		# Blind: the tray with its lower rows behind a bank of cloud. The cloud is
		# d2 and translucent on purpose: fog has no side wall.
		"blind": _ic({"d": _grid_path(3, 2.5, 2, 2), "fill": S,
			"d2": "M3 32 a7.5 7.5 0 0 1 12.5 -5.5 a9.5 9.5 0 0 1 17 0 a7.5 7.5 0 0 1 12.5 5.5 V42 a4 4 0 0 1 -4 4 H7 a4 4 0 0 1 -4 -4 Z",
			"f2": "rgba(205,228,255,0.9)",
			"hl": "M10 27.4 a3 1.6 0 1 0 0.01 0 Z", "hlc": "rgba(255,255,255,0.7)",
			"glow": GLOW_GLASS}),
		# Pass and play: two glass discs, two people, the front one lighter.
		"play_sheet_friend": _ic({"d": "M33 5 a12 12 0 1 0 0.01 0 Z M15 19 a12 12 0 1 0 0.01 0 Z",
			"fill": MG,
			"d2": "M15 19 a12 12 0 1 0 0.01 0 Z", "f2": "rgba(255,226,246,0.45)",
			"hl": "M33 9.9 a2.6 2.6 0 1 0 0.01 0 Z M27 24.5 a6 6 0 0 1 12 0 Z"
				+ " M15 23.9 a2.6 2.6 0 1 0 0.01 0 Z M9 38.5 a6 6 0 0 1 12 0 Z",
			"hlc": "rgba(255,255,255,0.9)", "glow": GLOW_PURP}),
		"play_classic": _ic({"d": play_d, "fill": P, "d2": "M19.5 15 L34 24 L19.5 33 Z", "f2": "#ffffff",
			"hl": play_hl, "hlc": "rgba(255,255,255,0.4)", "glow": GLOW_PURP}),
		"play_challenger": _ic({"d": play_d, "fill": F, "d2": "M19.5 15 L34 24 L19.5 33 Z", "f2": "#ffffff",
			"hl": play_hl, "hlc": "rgba(255,255,255,0.4)", "glow": GLOW_FLAME}),
		"play_grand": _ic({"d": play_d, "fill": C, "d2": "M19.5 15 L34 24 L19.5 33 Z", "f2": "#ffffff",
			"hl": play_hl, "hlc": "rgba(255,255,255,0.4)", "glow": GLOW_CYAN}),
		"play_blue": _ic({"d": play_d, "fill": B, "d2": "M19.5 15 L34 24 L19.5 33 Z", "f2": "#ffffff",
			"hl": play_hl, "hlc": "rgba(255,255,255,0.4)", "glow": GLOW_GLASS}),
		"play_gold": _ic({"d": play_d, "fill": G, "d2": "M19.5 15 L34 24 L19.5 33 Z", "f2": "#ffffff",
			"hl": play_hl, "hlc": "rgba(255,255,255,0.4)", "glow": GLOW_GOLD}),
		# Silver's top stop is near-white, so its triangle is dark to stay visible.
		"play_silver": _ic({"d": play_d, "fill": S, "d2": "M19.5 15 L34 24 L19.5 33 Z", "f2": "#222c3a",
			"hl": play_hl, "hlc": "rgba(255,255,255,0.4)", "glow": GLOW_SIL}),
		# --- Bottom navigation (design sheet "Bottom Nav Icons", option 1a:
		# "Glossy 3D glyphs"). Transcribed verbatim onto the 64-unit grid; see
		# _nav for the one transformation applied (rgba -> hex + opacity).
		"nav_home": _nav(
			'<defs>' \
			+ '<linearGradient id="ahB" x1="16" y1="6" x2="48" y2="58" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#ffdf8f"/><stop offset="0.45" stop-color="#f8b62c"/><stop offset="1" stop-color="#d0850a"/></linearGradient>' \
			+ '<linearGradient id="ahD" x1="32" y1="42" x2="32" y2="58" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#8a4f04"/><stop offset="1" stop-color="#5c3102"/></linearGradient>' \
			+ '</defs>' \
			+ '<path d="M6 30.5 32 6.5 58 30.5V52a5 5 0 0 1-5 5H11a5 5 0 0 1-5-5Z" fill="url(#ahB)" stroke="#341a00" stroke-opacity="0.55" stroke-width="2" stroke-linejoin="round"/>' \
			+ '<path d="M32 6.5 58 30.5H6Z" fill="#ffffff" fill-opacity="0.16"/>' \
			+ '<path d="M20 22.8 32 11.6l5 4.7L25.4 27.4Z" fill="#ffffff" fill-opacity="0.4"/>' \
			+ '<rect x="10.5" y="34" width="4" height="17" rx="2" fill="#ffffff" fill-opacity="0.22"/>' \
			+ '<path d="M26 57V45.5a6 6 0 0 1 12 0V57Z" fill="url(#ahD)"/>' \
			+ '<circle cx="35" cy="50" r="1.7" fill="#ffdb95" fill-opacity="0.85"/>',
			"rgba(247,183,49,0.4)"),
		"nav_achievements": _nav(
			'<defs>' \
			+ '<linearGradient id="atB" x1="18" y1="8" x2="46" y2="38" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#ffc9f5"/><stop offset="0.45" stop-color="#e455c9"/><stop offset="1" stop-color="#a52a8e"/></linearGradient>' \
			+ '<linearGradient id="atS" x1="16" y1="42" x2="48" y2="58" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#ef8ade"/><stop offset="1" stop-color="#a92d90"/></linearGradient>' \
			+ '</defs>' \
			+ '<path d="M21 15h-6.5a9.5 9.5 0 0 0 9.5 14.5" fill="none" stroke="#b8339b" stroke-width="4.6" stroke-linecap="round"/>' \
			+ '<path d="M43 15h6.5a9.5 9.5 0 0 1-9.5 14.5" fill="none" stroke="#b8339b" stroke-width="4.6" stroke-linecap="round"/>' \
			+ '<path d="M18.5 9h27v13.5A13.5 13.5 0 0 1 32 36a13.5 13.5 0 0 1-13.5-13.5Z" fill="url(#atB)" stroke="#3a0430" stroke-opacity="0.5" stroke-width="2" stroke-linejoin="round"/>' \
			+ '<path d="M28.5 34.5h7V44h-7Z" fill="#bd3aa3"/>' \
			+ '<rect x="22" y="42.5" width="20" height="5.5" rx="2.5" fill="url(#atS)"/>' \
			+ '<rect x="16.5" y="49" width="31" height="8" rx="4" fill="url(#atS)" stroke="#3a0430" stroke-opacity="0.45" stroke-width="2"/>' \
			+ '<rect x="23.5" y="13.5" width="4" height="13" rx="2" fill="#ffffff" fill-opacity="0.45"/>',
			"rgba(228,85,201,0.4)"),
		"nav_stats": _nav(
			'<defs>' \
			+ '<linearGradient id="asB" x1="10" y1="12" x2="54" y2="57" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#bde9ff"/><stop offset="0.45" stop-color="#45b7f0"/><stop offset="1" stop-color="#1170b8"/></linearGradient>' \
			+ '</defs>' \
			+ '<g stroke="#022642" stroke-opacity="0.5" stroke-width="2">' \
			+ '<rect x="9" y="36" width="12" height="21" rx="4" fill="url(#asB)"/>' \
			+ '<rect x="26" y="24" width="12" height="33" rx="4" fill="url(#asB)"/>' \
			+ '<rect x="43" y="12" width="12" height="45" rx="4" fill="url(#asB)"/>' \
			+ '</g>' \
			+ '<rect x="11.5" y="39" width="3" height="14" rx="1.5" fill="#ffffff" fill-opacity="0.4"/>' \
			+ '<rect x="28.5" y="27" width="3" height="26" rx="1.5" fill="#ffffff" fill-opacity="0.4"/>' \
			+ '<rect x="45.5" y="15" width="3" height="38" rx="1.5" fill="#ffffff" fill-opacity="0.4"/>',
			"rgba(69,183,240,0.4)"),
		"nav_themes": _nav(
			'<defs>' \
			+ '<linearGradient id="abH" x1="26" y1="6" x2="40" y2="40" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#d6ffe6"/><stop offset="0.5" stop-color="#4fd07a"/><stop offset="1" stop-color="#188f4c"/></linearGradient>' \
			+ '<linearGradient id="abF" x1="24" y1="32" x2="40" y2="42" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#e6ecf2"/><stop offset="1" stop-color="#8f9caa"/></linearGradient>' \
			+ '<linearGradient id="abT" x1="26" y1="40" x2="38" y2="54" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#a8f0c4"/><stop offset="1" stop-color="#2fa85e"/></linearGradient>' \
			+ '</defs>' \
			+ '<g transform="rotate(-38 32 32)" stroke="#022e18" stroke-opacity="0.5" stroke-width="2" stroke-linejoin="round">' \
			+ '<rect x="26.5" y="6" width="11" height="27" rx="5.5" fill="url(#abH)"/>' \
			+ '<rect x="24.5" y="31.5" width="15" height="9.5" rx="2.5" fill="url(#abF)"/>' \
			+ '<path d="M26 40h12l-2.6 11.5a3.5 3.5 0 0 1-6.8 0Z" fill="url(#abT)"/>' \
			+ '<rect x="28.5" y="9" width="3" height="20" rx="1.5" fill="#ffffff" fill-opacity="0.45" stroke="none"/>' \
			+ '</g>',
			"rgba(79,208,122,0.4)"),
		"nav_profile": _nav(
			'<defs>' \
			+ '<linearGradient id="apH" x1="22" y1="10" x2="42" y2="32" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#ffd2de"/><stop offset="0.5" stop-color="#f0567f"/><stop offset="1" stop-color="#b41f4c"/></linearGradient>' \
			+ '<linearGradient id="apB" x1="14" y1="36" x2="50" y2="57" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#ffb6c8"/><stop offset="0.5" stop-color="#ea4a75"/><stop offset="1" stop-color="#a81c46"/></linearGradient>' \
			+ '</defs>' \
			+ '<g stroke="#420317" stroke-opacity="0.5" stroke-width="2" stroke-linejoin="round">' \
			+ '<circle cx="32" cy="20.5" r="11" fill="url(#apH)"/>' \
			+ '<path d="M12 57v-2.5a20 20 0 0 1 40 0V57Z" fill="url(#apB)"/>' \
			+ '</g>' \
			+ '<path d="M25.5 15.5a8.5 8.5 0 0 1 6-4" fill="none" stroke="#ffffff" stroke-opacity="0.5" stroke-width="3" stroke-linecap="round"/>' \
			+ '<path d="M20 48.5a13 13 0 0 1 7-5.5" fill="none" stroke="#ffffff" stroke-opacity="0.35" stroke-width="3" stroke-linecap="round"/>',
			"rgba(240,86,127,0.4)"),
			# --- Currencies (design sheet "Currency Icons v2") -----------------
			# Transcribed verbatim onto the 72-unit grid; see _currency for the
			# two deliberate departures from the sheet (glint + glow).
			"currency_coins": _token72(
				'<defs>' \
				+ '<linearGradient id="k-face" x1=".12" y1="0" x2=".8" y2="1">' \
				+ '<stop offset="0" stop-color="#fffaea"/><stop offset=".14" stop-color="#ffeab4"/><stop offset=".3" stop-color="#fdd071"/>' \
				+ '<stop offset=".45" stop-color="#f2b13c"/><stop offset=".56" stop-color="#e29a24"/><stop offset=".68" stop-color="#f9cd63"/>' \
				+ '<stop offset=".84" stop-color="#d18d1c"/><stop offset="1" stop-color="#a86a0d"/></linearGradient>' \
				+ '<linearGradient id="k-edge" x1=".2" y1="0" x2=".7" y2="1"><stop offset="0" stop-color="#b8790f"/><stop offset=".4" stop-color="#8d5407"/><stop offset=".7" stop-color="#a86a0d"/><stop offset="1" stop-color="#6d3d03"/></linearGradient>' \
				+ '<linearGradient id="k-disc" x1=".2" y1="0" x2=".75" y2="1"><stop offset="0" stop-color="#ffeec2"/><stop offset=".35" stop-color="#fbcf6d"/><stop offset=".6" stop-color="#eaa72f"/><stop offset=".82" stop-color="#f7c556"/><stop offset="1" stop-color="#c9840f"/></linearGradient>' \
				+ '<radialGradient id="k-ao" cx="50%" cy="46%" r="52%"><stop offset=".62" stop-color="#7a4405" stop-opacity="0"/><stop offset=".9" stop-color="#7a4405" stop-opacity=".28"/><stop offset="1" stop-color="#5e3403" stop-opacity=".5"/></radialGradient>' \
				+ '<radialGradient id="k-spec" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#fffdf2" stop-opacity=".95"/><stop offset=".45" stop-color="#fff6d8" stop-opacity=".5"/><stop offset="1" stop-color="#fff6d8" stop-opacity="0"/></radialGradient>' \
				+ '<radialGradient id="k-bounce" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#ffdf9a" stop-opacity=".75"/><stop offset="1" stop-color="#ffdf9a" stop-opacity="0"/></radialGradient>' \
				+ '<radialGradient id="k-shadow" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#000000" stop-opacity=".38"/><stop offset="1" stop-color="#000000" stop-opacity="0"/></radialGradient>' \
				+ '<linearGradient id="k-emboss" x1=".2" y1="0" x2=".7" y2="1"><stop offset="0" stop-color="#fffdf4"/><stop offset=".5" stop-color="#ffeec0"/><stop offset="1" stop-color="#f0c97e"/></linearGradient>' \
				+ '<clipPath id="k-clip"><circle cx="36" cy="34" r="30"/></clipPath>' \
				+ '</defs>' \
				+ '<ellipse cx="36" cy="68" rx="25" ry="5.5" fill="url(#k-shadow)"/>' \
				+ '<circle cx="36" cy="39.5" r="29.6" fill="url(#k-edge)"/>' \
				+ '<circle cx="36" cy="34" r="30" fill="url(#k-face)"/>' \
				+ '<g clip-path="url(#k-clip)">' \
				+ '<circle cx="36" cy="34" r="30" fill="url(#k-ao)"/>' \
				+ '<ellipse cx="23" cy="14" rx="17" ry="11" fill="url(#k-spec)" transform="rotate(-30 23 14)"/>' \
				+ '<ellipse cx="48" cy="56" rx="16" ry="9" fill="url(#k-bounce)" transform="rotate(-28 48 56)"/>' \
				+ '</g>' \
				+ '<circle cx="36" cy="34" r="29.2" fill="none" stroke="#fff3cd" stroke-width="1.1" stroke-opacity=".45"/>' \
				+ '<circle cx="36" cy="34" r="22.6" fill="#a3630c" fill-opacity=".45"/>' \
				+ '<circle cx="36" cy="33.4" r="21.8" fill="url(#k-disc)"/>' \
				+ '<circle cx="36" cy="33.4" r="21.8" fill="url(#k-ao)" opacity=".55"/>' \
				+ '<path d="M22.5 43V27.5l8 7L36 22.5l5.5 12L49.5 27.5V43z" transform="translate(.6 2)" fill="#8a4f08" fill-opacity=".38"/>' \
				+ '<path d="M22.5 43V27.5l8 7L36 22.5l5.5 12L49.5 27.5V43z" fill="url(#k-emboss)"/>' \
				+ '<path d="M22.5 43V27.5l8 7L36 22.5v20.5z" fill="#ffffff" fill-opacity=".28"/>' \
				+ '<path d="M22.5 43V27.5l8 7L36 22.5l5.5 12L49.5 27.5V43z" fill="none" stroke="#b0700f" stroke-width=".9" stroke-opacity=".55" stroke-linejoin="round"/>',
				"rgba(242,177,60,0.4)"),
			"currency_gems": _token72(
				'<defs>' \
				+ '<linearGradient id="g-table" x1=".15" y1="0" x2=".7" y2="1"><stop offset="0" stop-color="#fdf6ff"/><stop offset=".3" stop-color="#eed6ff"/><stop offset=".62" stop-color="#c996f7"/><stop offset="1" stop-color="#a463ea"/></linearGradient>' \
				+ '<linearGradient id="g-f1" x1=".1" y1="0" x2=".7" y2="1"><stop offset="0" stop-color="#d5a4fa"/><stop offset=".55" stop-color="#9a4ee2"/><stop offset="1" stop-color="#5e18ab"/></linearGradient>' \
				+ '<linearGradient id="g-f2" x1=".3" y1="0" x2=".6" y2="1"><stop offset="0" stop-color="#f0dcff"/><stop offset=".5" stop-color="#c58ef6"/><stop offset="1" stop-color="#8231d6"/></linearGradient>' \
				+ '<linearGradient id="g-f3" x1=".8" y1="0" x2=".4" y2="1"><stop offset="0" stop-color="#a75fe8"/><stop offset=".55" stop-color="#7a2bcb"/><stop offset="1" stop-color="#4a0d90"/></linearGradient>' \
				+ '<linearGradient id="g-f4" x1="1" y1="0" x2=".35" y2="1"><stop offset="0" stop-color="#8c3ad9"/><stop offset=".6" stop-color="#59139f"/><stop offset="1" stop-color="#34066b"/></linearGradient>' \
				+ '<linearGradient id="g-cl" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fbf3ff"/><stop offset="1" stop-color="#d9b4fb"/></linearGradient>' \
				+ '<linearGradient id="g-cr" x1="1" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#a865ea"/><stop offset="1" stop-color="#7b2fc9"/></linearGradient>' \
				+ '<radialGradient id="g-caustic" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#f3ddff" stop-opacity=".75"/><stop offset="1" stop-color="#f3ddff" stop-opacity="0"/></radialGradient>' \
				+ '<radialGradient id="g-core" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#2c0357" stop-opacity=".55"/><stop offset="1" stop-color="#2c0357" stop-opacity="0"/></radialGradient>' \
				+ '<radialGradient id="g-shadow" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#000000" stop-opacity=".34"/><stop offset="1" stop-color="#000000" stop-opacity="0"/></radialGradient>' \
				+ '<linearGradient id="g-girdle" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#ffffff" stop-opacity=".25"/><stop offset=".35" stop-color="#ffffff" stop-opacity=".95"/><stop offset="1" stop-color="#ffffff" stop-opacity=".3"/></linearGradient>' \
				+ '<clipPath id="g-clip"><path d="M6 28 22 10h28l16 18-30 36z"/></clipPath>' \
				+ '</defs>' \
				+ '<ellipse cx="36" cy="68" rx="20" ry="4.6" fill="url(#g-shadow)"/>' \
				+ '<path d="M6 28 22 10h28l16 18-30 36z" fill="#4a1385"/>' \
				+ '<path d="M22 10h28l6 18H16z" fill="url(#g-table)"/>' \
				+ '<path d="M6.5 28 22 10l-6 18z" fill="url(#g-cl)"/>' \
				+ '<path d="M65.5 28 50 10l6 18z" fill="url(#g-cr)"/>' \
				+ '<path d="M6.5 28H19l17 36z" fill="url(#g-f1)"/>' \
				+ '<path d="M19 28h17v36z" fill="url(#g-f2)"/>' \
				+ '<path d="M36 28h17L36 64z" fill="url(#g-f3)"/>' \
				+ '<path d="M53 28h12.5L36 64z" fill="url(#g-f4)"/>' \
				+ '<g clip-path="url(#g-clip)">' \
				+ '<ellipse cx="36" cy="60" rx="22" ry="14" fill="url(#g-core)"/>' \
				+ '<ellipse cx="27" cy="46" rx="13" ry="12" fill="url(#g-caustic)"/>' \
				+ '<ellipse cx="30" cy="19" rx="16" ry="7" fill="#ffffff" fill-opacity=".3"/>' \
				+ '<path d="M6 27.2h60v1.9H6z" fill="url(#g-girdle)"/>' \
				+ '<path d="M58 29 41 62l4 1 21-33z" fill="#ffffff" fill-opacity=".14"/>' \
				+ '<path d="M24 12.5h19l2.6 6.5H21.6z" fill="#ffffff" fill-opacity=".62"/>' \
				+ '</g>' \
				+ '<path d="M6 28 22 10h28l16 18-30 36z" fill="none" stroke="#2b0850" stroke-width="2.6" stroke-linejoin="round"/>' \
				+ '<path d="M6 28 22 10h28l16 18-30 36z" fill="none" stroke="#f0dcff" stroke-width=".9" stroke-opacity=".45" stroke-linejoin="round"/>' \
				+ '<ellipse cx="29" cy="14.6" rx="5.5" ry="2.2" fill="#ffffff" fill-opacity=".92"/>',
				"rgba(164,99,234,0.4)"),
			# --- Leaderboard ----------------------------------------------------
			# The purse strip's third pill. It is NOT a currency, which is exactly
			# why it has to be made of the same stuff as the two that are: it sits
			# between them on one rail of 72-unit tokens, and a flat line icon there
			# would read as a broken currency rather than as a door.
			#
			# A PODIUM, not a trophy. `best_score` and `rank_badge` already spend the
			# trophy and the shield in this app, and a third cup would say "award"
			# where this one has to say "standings" — three places, ranked, with the
			# gold one in the middle and taller.
			"leaderboard": _token72(
				'<defs>' \
				+ '<linearGradient id="lb-gold" x1=".15" y1="0" x2=".7" y2="1"><stop offset="0" stop-color="#fff6d8"/><stop offset=".28" stop-color="#fbcf6d"/><stop offset=".62" stop-color="#eaa72f"/><stop offset="1" stop-color="#b8790f"/></linearGradient>' \
				+ '<linearGradient id="lb-sil" x1=".15" y1="0" x2=".7" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset=".32" stop-color="#e2ecf7"/><stop offset=".7" stop-color="#adbccd"/><stop offset="1" stop-color="#7c8da3"/></linearGradient>' \
				+ '<linearGradient id="lb-brz" x1=".15" y1="0" x2=".7" y2="1"><stop offset="0" stop-color="#ffdcb8"/><stop offset=".32" stop-color="#e3a468"/><stop offset=".7" stop-color="#b8703a"/><stop offset="1" stop-color="#8a4a1e"/></linearGradient>' \
				+ '<radialGradient id="lb-spec" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#ffffff" stop-opacity=".85"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient>' \
				+ '<radialGradient id="lb-shadow" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#000000" stop-opacity=".34"/><stop offset="1" stop-color="#000000" stop-opacity="0"/></radialGradient>' \
				+ '</defs>' \
				+ '<ellipse cx="36" cy="67" rx="30" ry="4.6" fill="url(#lb-shadow)"/>' \
				+ '<rect x="4" y="36" width="20" height="28" rx="2.5" transform="translate(1.4 2)" fill="#4e5a6b"/>' \
				+ '<rect x="48" y="44" width="20" height="20" rx="2.5" transform="translate(1.4 2)" fill="#6b3d18"/>' \
				+ '<rect x="26" y="22" width="20" height="42" rx="2.5" transform="translate(1.4 2)" fill="#8a5a06"/>' \
				+ '<rect x="4" y="36" width="20" height="28" rx="2.5" fill="url(#lb-sil)" stroke="#404d5e" stroke-width="2.2" stroke-linejoin="round"/>' \
				+ '<rect x="48" y="44" width="20" height="20" rx="2.5" fill="url(#lb-brz)" stroke="#5e3413" stroke-width="2.2" stroke-linejoin="round"/>' \
				+ '<rect x="26" y="22" width="20" height="42" rx="2.5" fill="url(#lb-gold)" stroke="#7a4f05" stroke-width="2.4" stroke-linejoin="round"/>' \
				+ '<rect x="6.6" y="38.4" width="5.4" height="23" rx="2" fill="#ffffff" fill-opacity=".5"/>' \
				+ '<rect x="28.6" y="24.4" width="5.4" height="37" rx="2" fill="#ffffff" fill-opacity=".42"/>' \
				+ '<rect x="50.6" y="46.4" width="5.4" height="15" rx="2" fill="#ffffff" fill-opacity=".38"/>' \
				+ '<ellipse cx="34" cy="30" rx="13" ry="5" fill="url(#lb-spec)" opacity=".6"/>' \
				+ '<path d="M36 5.5 39.4 12.4 47 13.5 41.5 18.9 42.8 26.5 36 22.9 29.2 26.5 30.5 18.9 25 13.5 32.6 12.4z" transform="translate(1 1.6)" fill="#7a4f05" fill-opacity=".5"/>' \
				+ '<path d="M36 5.5 39.4 12.4 47 13.5 41.5 18.9 42.8 26.5 36 22.9 29.2 26.5 30.5 18.9 25 13.5 32.6 12.4z" fill="url(#lb-gold)" stroke="#7a4f05" stroke-width="2.2" stroke-linejoin="round"/>' \
				+ '<path d="M36 5.5 39.4 12.4 47 13.5 41.5 18.9 36 17.5z" fill="#ffffff" fill-opacity=".34"/>',
				"rgba(244,193,62,0.4)"),
			# --- Actions (design sheet "Shop & Share Icons") --------------------
			# The same 72-unit grid and material language as the currencies above
			# ("storefront with striped awning, magenta paper plane"), which is
			# why they are _token72 and not part of the 48-unit token set: these
			# sit next to the purse, so they have to be made of the same stuff.
			"shop": _token72(
				'<defs>' \
				+ '<linearGradient id="s-wall" x1=".1" y1="0" x2=".6" y2="1"><stop offset="0" stop-color="#fffaf0"/><stop offset=".45" stop-color="#f5e6cd"/><stop offset="1" stop-color="#d8bd97"/></linearGradient>' \
				+ '<linearGradient id="s-sign" x1=".1" y1="0" x2=".6" y2="1"><stop offset="0" stop-color="#ffe9a8"/><stop offset=".4" stop-color="#f4bd44"/><stop offset="1" stop-color="#bd7d0d"/></linearGradient>' \
				+ '<linearGradient id="s-aw" x1=".1" y1="0" x2=".5" y2="1"><stop offset="0" stop-color="#3fd79f"/><stop offset=".5" stop-color="#1cb37f"/><stop offset="1" stop-color="#0d7e58"/></linearGradient>' \
				+ '<linearGradient id="s-awl" x1=".1" y1="0" x2=".5" y2="1"><stop offset="0" stop-color="#f6fff9"/><stop offset="1" stop-color="#cfeee0"/></linearGradient>' \
				+ '<linearGradient id="s-door" x1=".2" y1="0" x2=".7" y2="1"><stop offset="0" stop-color="#7fe6c0"/><stop offset=".45" stop-color="#22a87c"/><stop offset="1" stop-color="#0a5c40"/></linearGradient>' \
				+ '<radialGradient id="s-spec" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#ffffff" stop-opacity=".85"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient>' \
				+ '<radialGradient id="s-shadow" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#000000" stop-opacity=".34"/><stop offset="1" stop-color="#000000" stop-opacity="0"/></radialGradient>' \
				+ '<clipPath id="s-awclip"><path d="' + s_awning + '"/></clipPath>' \
				+ '<clipPath id="s-wallclip"><path d="' + s_wall + '"/></clipPath>' \
				+ '</defs>' \
				+ '<ellipse cx="36" cy="67" rx="27" ry="4.6" fill="url(#s-shadow)"/>' \
				+ '<path d="' + s_wall + '" transform="translate(1.6 2.2)" fill="#8a6a3e"/>' \
				+ '<path d="' + s_wall + '" fill="url(#s-wall)" stroke="#5c421f" stroke-width="2.4" stroke-linejoin="round"/>' \
				+ '<g clip-path="url(#s-wallclip)">' \
				+ '<path d="M12 33h10v31H12z" fill="#ffffff" fill-opacity=".5"/>' \
				+ '<path d="M50 33h10v31H50z" fill="#a5793f" fill-opacity=".28"/>' \
				+ '<ellipse cx="24" cy="38" rx="16" ry="6" fill="url(#s-spec)" opacity=".7"/>' \
				+ '</g>' \
				+ '<path d="M25.5 64V50a10.5 10.5 0 0 1 21 0v14z" fill="#0a4a34"/>' \
				+ '<path d="M26.5 64V50.4a9.5 9.5 0 0 1 19 0V64z" fill="url(#s-door)" stroke="#0a4a34" stroke-width="2" stroke-linejoin="round"/>' \
				+ '<path d="M28.8 64V50.6a7.2 7.2 0 0 1 5.4-7V64z" fill="#ffffff" fill-opacity=".22"/>' \
				+ '<circle cx="42" cy="56" r="1.9" fill="#ffe9a8" stroke="#0a4a34" stroke-width=".8"/>' \
				+ '<path d="' + s_awning + '" transform="translate(1.4 2)" fill="#0a5c40"/>' \
				+ '<g clip-path="url(#s-awclip)">' \
				+ '<rect x="7" y="20" width="65" height="20" fill="url(#s-aw)"/>' \
				+ '<rect x="16.4" y="20" width="9.4" height="20" fill="url(#s-awl)"/>' \
				+ '<rect x="35.2" y="20" width="9.4" height="20" fill="url(#s-awl)"/>' \
				+ '<rect x="54" y="20" width="9.4" height="20" fill="url(#s-awl)"/>' \
				+ '<rect x="7" y="20" width="65" height="5" fill="#ffffff" fill-opacity=".35"/>' \
				+ '<rect x="7" y="30" width="65" height="9" fill="#053b2b" fill-opacity=".22"/>' \
				+ '</g>' \
				+ '<path d="' + s_awning + '" fill="none" stroke="#053b2b" stroke-width="2.4" stroke-linejoin="round"/>' \
				+ '<rect x="14" y="10" width="44" height="12" rx="4" transform="translate(1.2 1.8)" fill="#7a4f05"/>' \
				+ '<rect x="14" y="10" width="44" height="12" rx="4" fill="url(#s-sign)" stroke="#5c3a04" stroke-width="2.2"/>' \
				+ '<rect x="17" y="12.4" width="38" height="3.4" rx="1.7" fill="#ffffff" fill-opacity=".55"/>',
				"rgba(28,179,127,0.4)"),
			"share": _token72(
				'<defs>' \
				+ '<linearGradient id="p-top" x1=".1" y1="0" x2=".7" y2="1"><stop offset="0" stop-color="#fff2fb"/><stop offset=".35" stop-color="#ffbdec"/><stop offset=".75" stop-color="#f562c8"/><stop offset="1" stop-color="#d92fa8"/></linearGradient>' \
				+ '<linearGradient id="p-side" x1=".8" y1="0" x2=".2" y2="1"><stop offset="0" stop-color="#ef4fb8"/><stop offset=".5" stop-color="#c72294"/><stop offset="1" stop-color="#8f0c67"/></linearGradient>' \
				+ '<radialGradient id="p-spec" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#ffffff" stop-opacity=".9"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient>' \
				+ '<radialGradient id="p-shadow" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#000000" stop-opacity=".3"/><stop offset="1" stop-color="#000000" stop-opacity="0"/></radialGradient>' \
				+ '</defs>' \
				+ '<ellipse cx="36" cy="66" rx="22" ry="4.2" fill="url(#p-shadow)"/>' \
				+ '<path d="M64 8 6 33l25 8 5 20z" transform="translate(1.6 2.4)" fill="#8f0c67"/>' \
				+ '<path d="M64 8 6 33l25 8z" fill="url(#p-top)"/>' \
				+ '<path d="M64 8 31 41l5 20z" fill="url(#p-side)"/>' \
				+ '<path d="M64 8 31 41l-25-8z" fill="none" stroke="#8f0c67" stroke-width="2.6" stroke-linejoin="round"/>' \
				+ '<path d="M64 8 31 41l5 20z" fill="none" stroke="#8f0c67" stroke-width="2.6" stroke-linejoin="round"/>' \
				+ '<path d="M64 8 12 31l19 10z" fill="#ffffff" fill-opacity=".3"/>' \
				+ '<ellipse cx="30" cy="24" rx="16" ry="5" fill="url(#p-spec)" transform="rotate(-24 30 24)" opacity=".7"/>' \
				+ '<path d="M64 8 31 41" fill="none" stroke="#ffd9f2" stroke-width="1.4" stroke-opacity=".7" stroke-linecap="round"/>',
				"rgba(245,98,200,0.4)"),
	}
	return _icons
