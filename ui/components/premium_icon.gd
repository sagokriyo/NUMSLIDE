class_name PremiumIcon
extends Control
## PremiumIcon — crisp, bright, vector icons drawn in code (no image assets), so
## they're sharp at any size, theme-tintable, and free of the cheap PNG badges.
## Each icon is a vivid filled shape with a soft white gloss highlight.
##
## Use PremiumIcon.make("crown", Color("F4B93E"), 64).
## The "tile" kind takes an optional label — PremiumIcon.make("tile", c, 64, "2048")
## draws a 2048-style tile frame with the number centered inside.

var kind: String = "star"
var color: Color = Color("F4B93E")
var label: String = ""

static func make(p_kind: String, p_color: Color, box: float, p_label: String = "") -> PremiumIcon:
	var i := PremiumIcon.new()
	i.kind = p_kind
	i.color = p_color
	i.label = p_label
	i.custom_minimum_size = Vector2(box, box)
	return i

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

# --- fill helper (handles concave polygons reliably) --------------------------
func _fill(points: PackedVector2Array, col: Color) -> void:
	var idx := Geometry2D.triangulate_polygon(points)
	if idx.is_empty():
		draw_colored_polygon(points, col)
		return
	for i in range(0, idx.size(), 3):
		draw_colored_polygon(PackedVector2Array([
			points[idx[i]], points[idx[i + 1]], points[idx[i + 2]]]), col)

func _ring(c: Vector2, r: float, width: float, col: Color, a0: float = 0.0, a1: float = TAU) -> void:
	draw_arc(c, r, a0, a1, 48, col, width, true)

func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var dark := color.darkened(0.18)
	var light := color.lightened(0.22)
	match kind:
		"gear": _gear(c, s, dark, light)
		"person": _person(c, s, dark, light)
		"star": _star(c, s, dark, light)
		"trophy": _trophy(c, s, dark, light)
		"crown": _crown(c, s, dark, light)
		"chart": _chart(c, s, dark, light)
		"flame": _flame(c, s)
		"grid": _grid(c, s, dark, light)
		"lock": _lock(c, s, dark, light)
		"check": _check(c, s)
		"clock": _clock(c, s, dark, light)
		"undo": _undo(c, s)
		"infinity": _infinity(c, s)
		"back": _back(c, s)
		"restart": _restart(c, s)
		"shield": _shield(c, s, dark, light)
		"gem": _gem(c, s, dark, light)
		"tile": _tile(c, s)
		"merge": _merge(c, s, light)
		"tile_drop": _tile_drop(c, s)
		"tile_fling": _tile_fling(c, s)
		"calendar": _calendar(c, s)
		_: _star(c, s, dark, light)
	# A soft round gloss highlight on filled icons only (line icons skip it).
	if kind in ["gear", "person", "star", "trophy", "crown", "flame", "grid", "lock", "clock", "shield", "gem"]:
		draw_circle(c + Vector2(-s * 0.16, -s * 0.2), s * 0.1, Color(1, 1, 1, 0.28))

# --- icons --------------------------------------------------------------------
func _star(c: Vector2, s: float, _dark: Color, light: Color) -> void:
	var ro := s * 0.46
	var ri := ro * 0.42
	var pts := PackedVector2Array()
	for i in 10:
		var r := ro if i % 2 == 0 else ri
		var ang := -PI / 2.0 + float(i) * PI / 5.0
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	_fill(pts, color)
	# inner sparkle
	var pts2 := PackedVector2Array()
	for i in 10:
		var r := (ro if i % 2 == 0 else ri) * 0.5
		var ang := -PI / 2.0 + float(i) * PI / 5.0
		pts2.append(c + Vector2(cos(ang), sin(ang)) * r)
	_fill(pts2, light)

func _crown(c: Vector2, s: float, dark: Color, light: Color) -> void:
	var w := s * 0.78
	var h := s * 0.62
	var b := c + Vector2(0, h * 0.16)
	var pts := PackedVector2Array([
		b + Vector2(-w * 0.5, h * 0.42),
		b + Vector2(-w * 0.5, -h * 0.36),
		b + Vector2(-w * 0.2, h * 0.02),
		b + Vector2(0, -h * 0.5),
		b + Vector2(w * 0.2, h * 0.02),
		b + Vector2(w * 0.5, -h * 0.36),
		b + Vector2(w * 0.5, h * 0.42),
	])
	_fill(pts, color)
	# base band
	draw_rect(Rect2(b + Vector2(-w * 0.5, h * 0.18), Vector2(w, h * 0.24)), dark)
	# gem dots on the tips
	for p in [b + Vector2(-w * 0.5, -h * 0.36), b + Vector2(0, -h * 0.5), b + Vector2(w * 0.5, -h * 0.36)]:
		draw_circle(p, s * 0.05, light)

func _trophy(c: Vector2, s: float, dark: Color, light: Color) -> void:
	var bw := s * 0.5
	var top := c.y - s * 0.34
	# bowl
	var bowl := PackedVector2Array([
		Vector2(c.x - bw * 0.5, top),
		Vector2(c.x + bw * 0.5, top),
		Vector2(c.x + bw * 0.42, top + s * 0.22),
		Vector2(c.x, top + s * 0.36),
		Vector2(c.x - bw * 0.42, top + s * 0.22),
	])
	_fill(bowl, color)
	# handles
	_ring(Vector2(c.x - bw * 0.5, top + s * 0.06), s * 0.12, s * 0.05, dark, PI * 0.4, PI * 1.5)
	_ring(Vector2(c.x + bw * 0.5, top + s * 0.06), s * 0.12, s * 0.05, dark, -PI * 0.5, PI * 0.6)
	# stem + base
	draw_rect(Rect2(c.x - s * 0.05, top + s * 0.36, s * 0.1, s * 0.16), dark)
	draw_rect(Rect2(c.x - s * 0.2, top + s * 0.5, s * 0.4, s * 0.1), dark)
	# rim highlight
	draw_rect(Rect2(c.x - bw * 0.5, top, bw, s * 0.05), light)

func _gear(c: Vector2, s: float, dark: Color, light: Color) -> void:
	var ro := s * 0.46
	var ri := ro * 0.80
	var pts := PackedVector2Array()
	var teeth := 8
	for i in teeth * 2:
		var r := ro if i % 2 == 0 else ri
		var ang := float(i) * PI / float(teeth)
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	_fill(pts, color)
	draw_circle(c, ro * 0.5, dark)
	draw_circle(c, ro * 0.24, light)

func _person(c: Vector2, s: float, _dark: Color, light: Color) -> void:
	# head
	draw_circle(c + Vector2(0, -s * 0.22), s * 0.17, color)
	draw_circle(c + Vector2(-s * 0.05, -s * 0.26), s * 0.06, light)
	# shoulders dome
	var pts := PackedVector2Array()
	var cy := c.y + s * 0.42
	var rx := s * 0.32
	var ry := s * 0.34
	var steps := 16
	for i in steps + 1:
		var ang := PI + float(i) / float(steps) * PI
		pts.append(Vector2(c.x + cos(ang) * rx, cy + sin(ang) * ry))
	pts.append(Vector2(c.x + rx, c.y + s * 0.46))
	pts.append(Vector2(c.x - rx, c.y + s * 0.46))
	_fill(pts, color)

func _chart(c: Vector2, s: float, dark: Color, light: Color) -> void:
	var baseline := c.y + s * 0.34
	var bw := s * 0.2
	var xs := [c.x - s * 0.32, c.x, c.x + s * 0.32]
	var hs := [s * 0.34, s * 0.52, s * 0.7]
	var cols := [light, color, dark]
	for i in 3:
		var h: float = hs[i]
		draw_rect(Rect2(xs[i] - bw * 0.5, baseline - h, bw, h), cols[i])

func _flame(c: Vector2, s: float) -> void:
	var pts := PackedVector2Array([
		c + Vector2(0, -s * 0.46),
		c + Vector2(s * 0.34, -s * 0.02),
		c + Vector2(s * 0.3, s * 0.28),
		c + Vector2(0, s * 0.44),
		c + Vector2(-s * 0.3, s * 0.28),
		c + Vector2(-s * 0.34, -s * 0.02),
	])
	_fill(pts, color)
	# inner brighter flame
	var inner := PackedVector2Array([
		c + Vector2(0, -s * 0.12),
		c + Vector2(s * 0.16, s * 0.12),
		c + Vector2(0, s * 0.32),
		c + Vector2(-s * 0.16, s * 0.12),
	])
	_fill(inner, Color(1, 0.92, 0.55, 0.9))

func _grid(c: Vector2, s: float, dark: Color, light: Color) -> void:
	var q := s * 0.2
	var sz := s * 0.3
	var cols := [color, light, dark, color]
	var k := 0
	for sy in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			var p := c + Vector2(sx * q, sy * q) - Vector2(sz, sz) * 0.5
			draw_rect(Rect2(p, Vector2(sz, sz)), cols[k])
			k += 1

func _lock(c: Vector2, s: float, dark: Color, light: Color) -> void:
	draw_rect(Rect2(c.x - s * 0.28, c.y - s * 0.04, s * 0.56, s * 0.42), color)
	_ring(c + Vector2(0, -s * 0.12), s * 0.2, s * 0.08, dark, PI, TAU)
	draw_circle(c + Vector2(0, s * 0.14), s * 0.06, light)

func _check(c: Vector2, s: float) -> void:
	var w := s * 0.12
	draw_polyline(PackedVector2Array([
		c + Vector2(-s * 0.26, 0),
		c + Vector2(-s * 0.06, s * 0.2),
		c + Vector2(s * 0.3, -s * 0.22),
	]), color, w, true)

func _clock(c: Vector2, s: float, dark: Color, light: Color) -> void:
	draw_circle(c, s * 0.42, color)
	draw_circle(c, s * 0.34, light)
	draw_line(c, c + Vector2(0, -s * 0.22), dark, s * 0.05)
	draw_line(c, c + Vector2(s * 0.16, s * 0.06), dark, s * 0.05)

func _undo(c: Vector2, s: float) -> void:
	_ring(c, s * 0.34, s * 0.09, color, PI * 0.6, TAU + PI * 0.1)
	var tip := c + Vector2(cos(PI * 0.6), sin(PI * 0.6)) * s * 0.34
	_fill(PackedVector2Array([
		tip + Vector2(-s * 0.1, -s * 0.02),
		tip + Vector2(s * 0.04, -s * 0.14),
		tip + Vector2(s * 0.08, s * 0.06),
	]), color)

func _infinity(c: Vector2, s: float) -> void:
	_ring(c + Vector2(-s * 0.18, 0), s * 0.18, s * 0.09, color)
	_ring(c + Vector2(s * 0.18, 0), s * 0.18, s * 0.09, color)

func _shield(c: Vector2, s: float, dark: Color, light: Color) -> void:
	var w := s * 0.66
	var h := s * 0.82
	var pts := PackedVector2Array([
		c + Vector2(-w * 0.5, -h * 0.42),
		c + Vector2(w * 0.5, -h * 0.42),
		c + Vector2(w * 0.5, h * 0.06),
		c + Vector2(0, h * 0.5),
		c + Vector2(-w * 0.5, h * 0.06),
	])
	_fill(pts, color)
	# inner crest highlight
	var inner := PackedVector2Array([
		c + Vector2(-w * 0.28, -h * 0.24),
		c + Vector2(w * 0.28, -h * 0.24),
		c + Vector2(w * 0.28, h * 0.0),
		c + Vector2(0, h * 0.28),
		c + Vector2(-w * 0.28, h * 0.0),
	])
	_fill(inner, light)
	draw_circle(c, s * 0.08, dark)

func _gem(c: Vector2, s: float, dark: Color, light: Color) -> void:
	var w := s * 0.66
	var top := c.y - s * 0.26
	var girdle := c.y - s * 0.02
	var bottom := c.y + s * 0.42
	var pts := PackedVector2Array([
		c + Vector2(-w * 0.5, girdle - c.y + c.y),
		Vector2(c.x - w * 0.28, top),
		Vector2(c.x + w * 0.28, top),
		Vector2(c.x + w * 0.5, girdle),
		Vector2(c.x, bottom),
	])
	pts[0] = Vector2(c.x - w * 0.5, girdle)
	_fill(pts, color)
	# table facet
	_fill(PackedVector2Array([
		Vector2(c.x - w * 0.28, top), Vector2(c.x + w * 0.28, top),
		Vector2(c.x + w * 0.16, girdle), Vector2(c.x - w * 0.16, girdle),
	]), light)
	# facet lines
	draw_line(Vector2(c.x - w * 0.5, girdle), Vector2(c.x, bottom), dark, s * 0.02)
	draw_line(Vector2(c.x + w * 0.5, girdle), Vector2(c.x, bottom), dark, s * 0.02)

func _back(c: Vector2, s: float) -> void:
	var w := s * 0.12
	draw_line(c + Vector2(-s * 0.22, 0), c + Vector2(s * 0.3, 0), color, w)
	draw_polyline(PackedVector2Array([
		c + Vector2(-s * 0.02, -s * 0.24),
		c + Vector2(-s * 0.26, 0),
		c + Vector2(-s * 0.02, s * 0.24),
	]), color, w, true)

func _restart(c: Vector2, s: float) -> void:
	var r := s * 0.32
	_ring(c, r, s * 0.1, color, -PI * 0.35, PI * 1.35)
	var a := -PI * 0.35
	var tip := c + Vector2(cos(a), sin(a)) * r
	_fill(PackedVector2Array([
		tip + Vector2(s * 0.02, -s * 0.16),
		tip + Vector2(s * 0.16, s * 0.02),
		tip + Vector2(-s * 0.04, s * 0.08),
	]), color)

# --- 2048-native badge icons (line style, one per achievement) -----------------
## Rounded-square tile outline — the game's own visual language.
func _tile_frame(rect: Rect2, stroke: float, radius_ratio: float = 0.22) -> void:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = color
	sb.set_border_width_all(int(round(maxf(2.0, stroke))))
	sb.set_corner_radius_all(int(rect.size.x * radius_ratio))
	sb.draw(get_canvas_item(), rect)

## Four-point sparkle (the merge flash).
func _spark(p: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var rad := r if i % 2 == 0 else r * 0.38
		var ang := -PI / 2.0 + float(i) * PI / 4.0
		pts.append(p + Vector2(cos(ang), sin(ang)) * rad)
	_fill(pts, col)

## A game tile with its target number inside ("2048", "16384", ...). The number
## comes from `label` so each mode badge reads as its actual goal tile.
func _tile(c: Vector2, s: float) -> void:
	var w := s * 0.9
	var rect := Rect2(c - Vector2(w, w) * 0.5, Vector2(w, w))
	_tile_frame(rect, s * 0.055, 0.18)
	if label.is_empty():
		return
	var f := get_theme_default_font()
	if f == null:
		return
	var fs := int(w * (0.34 if label.length() <= 4 else 0.27))
	var pos := Vector2(rect.position.x, c.y - f.get_height(fs) * 0.5 + f.get_ascent(fs))
	draw_string(f, pos, label, HORIZONTAL_ALIGNMENT_CENTER, w, fs, color)

## Two tiles meeting, sparkle above the seam — the first merge.
func _merge(c: Vector2, s: float, light: Color) -> void:
	var t := s * 0.42
	var gap := s * 0.05
	var y := c.y + s * 0.12
	_tile_frame(Rect2(Vector2(c.x - t - gap, y - t * 0.5), Vector2(t, t)), s * 0.05)
	_tile_frame(Rect2(Vector2(c.x + gap, y - t * 0.5), Vector2(t, t)), s * 0.05)
	_spark(Vector2(c.x, c.y - s * 0.28), s * 0.15, light)

## A tile dropping into the well (Merge Drop).
func _tile_drop(c: Vector2, s: float) -> void:
	var t := s * 0.5
	_tile_frame(Rect2(Vector2(c.x - t * 0.5, c.y + s * 0.46 - t), Vector2(t, t)), s * 0.055)
	var w := s * 0.09
	draw_line(c + Vector2(0, -s * 0.46), c + Vector2(0, -s * 0.16), color, w)
	draw_polyline(PackedVector2Array([
		c + Vector2(-s * 0.15, -s * 0.3),
		c + Vector2(0, -s * 0.14),
		c + Vector2(s * 0.15, -s * 0.3),
	]), color, w, true)

## A weightless tile with a motion trail (Fling 2048).
func _tile_fling(c: Vector2, s: float) -> void:
	var t := s * 0.46
	var tile_c := c + Vector2(s * 0.16, -s * 0.16)
	_tile_frame(Rect2(tile_c - Vector2(t, t) * 0.5, Vector2(t, t)), s * 0.055)
	var dirv := Vector2(1, -1).normalized()
	for i in 3:
		var back := tile_c - dirv * s * (0.32 + 0.13 * float(i))
		var ln := s * (0.2 - 0.045 * float(i))
		var a := 0.9 - 0.3 * float(i)
		draw_line(back - dirv * ln * 0.5, back + dirv * ln * 0.5,
			Color(color.r, color.g, color.b, a), maxf(2.0, s * 0.05))

## Calendar page with a run of day dots — the daily streak.
func _calendar(c: Vector2, s: float) -> void:
	var w := s * 0.76
	var h := s * 0.68
	var stroke := s * 0.05
	var rect := Rect2(c + Vector2(-w * 0.5, -h * 0.4), Vector2(w, h))
	_tile_frame(rect, stroke, 0.12)
	for i in 2:
		var x := c.x + w * (-0.22 + 0.44 * float(i))
		draw_line(Vector2(x, rect.position.y - s * 0.1),
			Vector2(x, rect.position.y + s * 0.02), color, maxf(2.0, stroke))
	var hy := rect.position.y + h * 0.32
	draw_line(Vector2(rect.position.x + stroke * 2.0, hy),
		Vector2(rect.end.x - stroke * 2.0, hy), color, maxf(2.0, stroke * 0.8))
	for i in 3:
		var p := Vector2(rect.position.x + w * (0.25 + 0.25 * float(i)), hy + h * 0.34)
		draw_circle(p, s * 0.05, color)
