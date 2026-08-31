class_name HeroBoard
extends Control
## HeroBoard — the wordmark. A 3 x 3 tray of numbered glass, and it is REAL: tap
## a tile beside the hole and it slides, order the eight and the board
## celebrates and deals itself again.
##
## The app icon's own composition, alive. It is the hero on Home, on Sign In and
## on the Splash, and it is the first thing a new player touches, so it teaches
## the whole game before a single screen has explained anything: the tiles slide,
## the numbers go in order, that is it.
##
## STRUCTURE. This node animates (turn, scale, modulate) and draws NOTHING:
## `_pivot` carries the sway rotation, and every tile is a `Tile` child inside a
## `holder` that carries its own slide. Never tween a node that draws, it
## re-records its draw list every frame.
##
## Tile colours climb the theme's own tile ramp by ROW, exactly as the real
## board does, so a solved hero reads as three clean bands and the mark
## restyles with every world in the same glass the pieces wear.

const N := 3
## Per-row ramp rungs, so the three rows read as three colours.
const ROW_RAMP := [8, 64, 512]
const GAP_FRAC := 0.07
## Seconds one slide takes here. Slower than the board's: this is a decoration
## that happens to be playable, and it should read as calm.
const SLIDE_DUR := 0.16
## How far the opening scramble walks. Short: the hero is a demonstration, and a
## player who taps it a few times should be able to finish it by accident.
const SCRAMBLE := 12
## How long a solved hero holds before it deals itself again.
const HOLD_AFTER_SOLVE := 1.6

## Emitted when a tap slides a tile (Home wires its taps and haptics to this).
signal tile_tapped(index: int)
## Emitted when the eight come home.
signal solved

## The slow parallax sway, in degrees. Home and Sign In tween this.
var turn: float = 0.0:
	set(v):
		turn = v
		if _pivot != null:
			_pivot.rotation_degrees = v

var tile_px: float = 110.0

var _pivot: Control
var _holders: Array[Control] = []
var _tiles: Array[Tile] = []
## cell -> value, 0 for the hole.
var _cells: Array[int] = []
var _locked := false

## A hero sized to fill `width`.
static func make(width: float) -> HeroBoard:
	var b := HeroBoard.new()
	var gap := width * GAP_FRAC / float(N)
	b.tile_px = (width - gap * float(N - 1)) / float(N)
	b.custom_minimum_size = Vector2(width, width)
	return b

func _ready() -> void:
	_pivot = Control.new()
	_pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pivot.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_pivot)
	for i in N * N:
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pivot.add_child(holder)
		_holders.append(holder)
		var tile := Tile.new()
		tile.board = self
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tile)
		_tiles.append(tile)
	_deal()
	resized.connect(_layout)
	gui_input.connect(_on_gui_input)
	if ThemeManager.has_signal("theme_changed"):
		ThemeManager.theme_changed.connect(func(_p: Dictionary) -> void: _restyle())
	_layout()

## Deals a fresh scramble by walking the solved board, so the hero can never
## open on a position it cannot be slid out of.
func _deal() -> void:
	_cells = []
	for i in N * N:
		_cells.append(0 if i == N * N - 1 else i + 1)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var last := -1
	var done := 0
	while done < SCRAMBLE:
		var hole := _cells.find(0)
		var options := _neighbours(hole)
		var pick: int = options[rng.randi_range(0, options.size() - 1)]
		if pick == last and options.size() > 1:
			continue
		_cells[hole] = _cells[pick]
		_cells[pick] = 0
		last = hole
		done += 1
	if _is_solved():
		var hole := _cells.find(0)
		var nb := _neighbours(hole)[0]
		_cells[hole] = _cells[nb]
		_cells[nb] = 0
	_locked = false
	_restyle()
	_layout()

func _neighbours(i: int) -> Array[int]:
	var out: Array[int] = []
	@warning_ignore("integer_division")
	var y := i / N
	var x := i % N
	if x > 0: out.append(i - 1)
	if x < N - 1: out.append(i + 1)
	if y > 0: out.append(i - N)
	if y < N - 1: out.append(i + N)
	return out

func _is_solved() -> bool:
	for i in N * N:
		var want: int = 0 if i == N * N - 1 else i + 1
		if _cells[i] != want:
			return false
	return true

func _restyle() -> void:
	for i in N * N:
		var tile := _tiles[i]
		tile.value = _cells[i]
		# The hue is the tile's HOME row, so a finished hero reads as bands.
		var home: int = _cells[i] - 1
		@warning_ignore("integer_division")
		tile.ramp = int(ROW_RAMP[posmod(home / N, ROW_RAMP.size())]) if _cells[i] > 0 else 0
		tile.queue_redraw()

func _layout() -> void:
	if _holders.is_empty():
		return
	var gap := tile_px * GAP_FRAC
	var span := tile_px * float(N) + gap * float(N - 1)
	var origin := (size - Vector2(span, span)) * 0.5
	if _pivot != null:
		_pivot.pivot_offset = size * 0.5
	for i in N * N:
		var holder := _holders[i]
		holder.position = origin + _cell_offset(i, gap)
		holder.size = Vector2(tile_px, tile_px)
		holder.pivot_offset = Vector2(tile_px, tile_px) * 0.5
		var tile := _tiles[i]
		tile.size = Vector2(tile_px, tile_px)
		tile.pivot_offset = Vector2(tile_px, tile_px) * 0.5
		tile.queue_redraw()

func _cell_offset(i: int, gap: float) -> Vector2:
	@warning_ignore("integer_division")
	var y := i / N
	var x := i % N
	return Vector2(float(x) * (tile_px + gap), float(y) * (tile_px + gap))

func _on_gui_input(event: InputEvent) -> void:
	var down: bool = (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	if not down:
		return
	var idx := tile_at((event as InputEventFromWindow).position if event is InputEventFromWindow else Vector2.ZERO)
	if idx >= 0:
		slide(idx)

## The cell under a local point, or -1.
func tile_at(p: Vector2) -> int:
	var gap := tile_px * GAP_FRAC
	var span := tile_px * float(N) + gap * float(N - 1)
	var origin := (size - Vector2(span, span)) * 0.5
	var q := p - origin
	var pitch := tile_px + gap
	var x := int(floor(q.x / pitch))
	var y := int(floor(q.y / pitch))
	if x < 0 or y < 0 or x >= N or y >= N:
		return -1
	return y * N + x

## Slides the tile at `idx` into the hole beside it, if there is one.
func slide(idx: int) -> void:
	if _locked or idx < 0 or idx >= _cells.size() or _cells[idx] == 0:
		return
	var hole := -1
	for nb in _neighbours(idx):
		if _cells[nb] == 0:
			hole = nb
			break
	if hole < 0:
		return
	_cells[hole] = _cells[idx]
	_cells[idx] = 0
	tile_tapped.emit(idx)

	# The tiles are laid out by cell, so a slide is a swap of two holders'
	# CONTENTS with the moving one tweened between the two places.
	var gap := tile_px * GAP_FRAC
	var span := tile_px * float(N) + gap * float(N - 1)
	var origin := (size - Vector2(span, span)) * 0.5
	var moving := _tiles[idx]
	var empty := _tiles[hole]
	_tiles[idx] = empty
	_tiles[hole] = moving
	var from_holder := _holders[idx]
	var to_holder := _holders[hole]
	_holders[idx] = to_holder
	_holders[hole] = from_holder
	_restyle()
	if DesignSystem.reduce_motion():
		from_holder.position = origin + _cell_offset(hole, gap)
		to_holder.position = origin + _cell_offset(idx, gap)
	else:
		var t := from_holder.create_tween()
		t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_property(from_holder, "position", origin + _cell_offset(hole, gap), SLIDE_DUR)
		to_holder.position = origin + _cell_offset(idx, gap)
	if _is_solved():
		_celebrate()

func _celebrate() -> void:
	_locked = true
	solved.emit()
	if DesignSystem.reduce_motion():
		var quick := create_tween()
		quick.tween_interval(HOLD_AFTER_SOLVE)
		quick.tween_callback(_deal)
		return
	for i in _tiles.size():
		var tile := _tiles[i]
		var t := tile.create_tween()
		t.tween_interval(float(i) * 0.045)
		t.tween_property(tile, "scale", Vector2.ONE * 1.14, DesignSystem.DUR_INSTANT) \
			.set_trans(Tween.TRANS_SINE)
		t.tween_property(tile, "scale", Vector2.ONE, DesignSystem.DUR_BASE) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var back := create_tween()
	back.tween_interval(HOLD_AFTER_SOLVE)
	back.tween_callback(_deal)

## Deals a fresh board. Kept under the sibling project's name so the screens
## that reset the hero read the same.
func reset_marks() -> void:
	_deal()

## A whole-board bounce, for a tap that had nowhere to go.
func dance() -> void:
	if DesignSystem.reduce_motion() or _pivot == null:
		return
	var t := _pivot.create_tween()
	t.tween_property(_pivot, "scale", Vector2.ONE * 1.05, DesignSystem.DUR_FAST) \
		.set_trans(Tween.TRANS_SINE)
	t.tween_property(_pivot, "scale", Vector2.ONE, DesignSystem.DUR_SLOW) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## A slow attract loop: the hero solves itself a step at a time, so a screen
## left sitting shows what the game is. Stops the moment it comes home.
func amaze(sec: float = 1.5) -> void:
	if _locked:
		return
	var t := create_tween()
	t.tween_interval(sec)
	t.tween_callback(func() -> void:
		if _locked or not is_inside_tree():
			return
		var hole := _cells.find(0)
		var options := _neighbours(hole)
		if options.is_empty():
			return
		slide(options[randi() % options.size()])
		amaze(sec))

# --- One tile ---------------------------------------------------------------------

class Tile extends Control:
	var board: HeroBoard
	var value: int = 0
	var ramp: int = 8

	func _draw() -> void:
		if value <= 0 or size.x <= 2.0:
			return
		var hw := size.x * 0.5
		var centre := size * 0.5
		var vivid := CandyFace.color(ramp)
		CandyFace.draw_face(self, centre, hw, vivid)
		var font: Font = ThemeManager.tile_font_heavy
		if font == null:
			font = ThemeManager.tile_font
		if font == null:
			font = get_theme_default_font()
		var label := str(value)
		var px := int(hw * 1.05)
		var ink := CandyFace.text_color(vivid)
		var measured := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, px)
		var at := centre - Vector2(measured.x * 0.5, 0.0) + Vector2(0.0, measured.y * 0.32)
		draw_string(font, at + Vector2(0.0, maxf(1.0, hw * 0.035)), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.22))
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, px, ink)
