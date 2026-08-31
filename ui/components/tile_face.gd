class_name TileFace
extends RefCounted
## TileFace — the NUMERAL inside the glass, as a SHARED painter.
##
## CandyFace paints the slab; this paints what is printed on it. One painter, so
## every number in the app is the same object under the same light: the tray, the
## Continue glimpse, the Splash, the drifting shards, the theme cards, the Shop.
##
## THE INK IS DERIVED, NEVER CHOSEN. `CandyFace.text_color` picks by measured
## contrast, so a numeral reads on all 61 palettes with nothing tuned per theme.
## Pass an ink to tint one; pass nothing to have it simply read.
##
## Replaces the sibling project's MarkFace. The shape changed, the material did
## not.

## The size a numeral is drawn at, as a fraction of the tile's half-extent, by
## digit count. Three digits have to fit the same box one does.
const PX_ONE := 1.05
const PX_TWO := 0.86
const PX_MANY := 0.66

## The face the numbers are set in. Falls back down the chain so a painter is
## never handed null, which is what a missing font actually looks like at draw
## time: nothing at all, silently.
static func font() -> Font:
	var f: Font = ThemeManager.tile_font_heavy
	if f == null:
		f = ThemeManager.tile_font
	if f == null:
		f = ThemeManager.ui_font
	return f

## The point size a numeral of this many digits wears in a tile of half-extent
## `hw`. Published so a caller measuring its own layout agrees with the painter.
static func size_for(hw: float, digits: int) -> int:
	var frac := PX_ONE if digits <= 1 else (PX_TWO if digits == 2 else PX_MANY)
	return maxi(1, int(hw * frac))

## The theme-derived glass colour for a ramp rung. The same entry point
## CandyFace offers, republished here so a caller drawing a numbered tile reads
## one class rather than two.
static func color(ramp_value: int) -> Color:
	return CandyFace.color(ramp_value)

## The same, for an ARBITRARY palette instead of the active one, so a theme
## nobody owns can still show its real glass with a real number on it.
static func color_for(pal: Dictionary, ramp_value: int) -> Color:
	return CandyFace.color_for(pal, ramp_value)

## Paints `number` centred at `centre` in a tile of half-extent `hw`.
##
## `ink` with zero alpha means "work it out from the glass", which is what
## almost every caller wants. `glow` fades the whole numeral (Blind turns it
## down to nothing); `shadow` is how deep the numeral sits IN the glass rather
## than sitting on top of it.
static func draw_number(ci: CanvasItem, centre: Vector2, hw: float, number: int,
		ink: Color = Color(0, 0, 0, 0), glow: float = 1.0, shadow: float = 1.0) -> void:
	if number <= 0 or hw <= 1.0 or glow <= 0.01:
		return
	var f := font()
	if f == null:
		return
	var label := str(number)
	var px := size_for(hw, label.length())
	var col := ink
	if col.a <= 0.001:
		col = CandyFace.text_color(CandyFace.color(2))
	col.a *= glow
	var measured := f.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, px)
	var at := centre - Vector2(measured.x * 0.5, 0.0) + Vector2(0.0, measured.y * 0.32)
	if shadow > 0.01:
		ci.draw_string(f, at + Vector2(0.0, maxf(1.0, hw * 0.035)), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.22 * shadow * glow))
	ci.draw_string(f, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)

## The whole tile in one call: the glass slab and the number on it. What every
## caller outside the board itself actually wants, and the reason none of them
## has to know how the ink is chosen.
static func draw_tile(ci: CanvasItem, centre: Vector2, hw: float, number: int,
		vivid: Color, with_shadow: bool = true, glow: float = 1.0) -> void:
	CandyFace.draw_face(ci, centre, hw, vivid, with_shadow)
	draw_number(ci, centre, hw, number, CandyFace.text_color(vivid), glow)

## The same, on a palette the app is not currently wearing.
static func draw_tile_for(ci: CanvasItem, pal: Dictionary, centre: Vector2, hw: float,
		number: int, ramp_value: int, with_shadow: bool = true) -> void:
	var vivid := color_for(pal, ramp_value)
	CandyFace.draw_face(ci, centre, hw, vivid, with_shadow)
	draw_number(ci, centre, hw, number, CandyFace.text_color(vivid))
