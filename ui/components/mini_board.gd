class_name MiniBoard
extends Control
## MiniBoard — the PRODUCT, playable: a 3 x 3 tray painted in a theme nobody has
## bought yet, running the real rule. Tap a tile beside the hole and it slides;
## order the eight and it celebrates and deals itself again. The Shop's hero
## stage carries one; Home's Continue card draws its own still glimpse instead.
##
## The palette is handed in (`setup`), never read from ThemeManager, which is
## the whole point: the storefront shows the tiles a player would actually get.
## Every painter here takes a palette rather than reading the active one, so a
## locked theme can show its real glass with real numbers on it.
##
## Input: PASS, so a vertical drag that starts on the board still scrolls the
## page (the user's rule for anything inside a ScrollContainer); a tap slides.

const N := 3
const GAP_FRAC := 0.06
## Per-row ramp rungs, so the three rows read as three colours, exactly as the
## real board does.
const ROW_RAMP := [8, 64, 512]
const SLIDE_DUR := 0.14
## How far the opening scramble walks. Short: this is a shop window, and a
## board nobody can finish in three taps is an advert for frustration.
const SCRAMBLE := 8
const HOLD_AFTER_SOLVE := 1.4
## How far a finger may travel and still count as a tap.
const TAP_SLOP := 18.0

var _pal: Dictionary = {}
var _cells: Array[int] = []
## cell -> the offset that tile is drawn at while it slides.
var _offsets: Dictionary = {}
var _locked := false
var _press_pos := Vector2.ZERO
var _pressing := false

func setup(pal: Dictionary) -> void:
	_pal = pal
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_deal()

## Deals a fresh scramble by walking the solved board, so the demo can never
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
	_offsets.clear()
	_locked = false
	queue_redraw()

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

# --- Geometry ---------------------------------------------------------------------

func _square() -> Rect2:
	var side := minf(size.x, size.y)
	return Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))

func _cell_rect(i: int) -> Rect2:
	var box := _square()
	var gap := box.size.x * GAP_FRAC
	var cell := (box.size.x - gap * float(N - 1)) / float(N)
	@warning_ignore("integer_division")
	var y := i / N
	var x := i % N
	return Rect2(box.position + Vector2(float(x) * (cell + gap), float(y) * (cell + gap)),
		Vector2(cell, cell))

# --- Input ------------------------------------------------------------------------

func _on_gui_input(event: InputEvent) -> void:
	_gui_input(event)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var pressed: bool = event.pressed
		var at: Vector2 = event.position
		if pressed:
			_pressing = true
			_press_pos = at
		elif _pressing:
			_pressing = false
			# Only a TAP slides. A drag belongs to the page's scroll.
			if at.distance_to(_press_pos) <= TAP_SLOP:
				_tap(at)

func _tap(p: Vector2) -> void:
	if _locked:
		return
	for i in N * N:
		if _cell_rect(i).has_point(p):
			_slide(i)
			return

func _slide(idx: int) -> void:
	if _cells[idx] == 0:
		return
	var hole := -1
	for nb in _neighbours(idx):
		if _cells[nb] == 0:
			hole = nb
			break
	if hole < 0:
		return
	var value := _cells[idx]
	_cells[hole] = value
	_cells[idx] = 0
	AudioManager.play_sfx("tile_move", 0.02)
	if DesignSystem.reduce_motion():
		queue_redraw()
		_after_move()
		return
	# The tile is already in its new cell; it is DRAWN sliding out of the old
	# one, so the animation never has to disagree with the board.
	var travel := _cell_rect(idx).position - _cell_rect(hole).position
	_offsets[value] = travel
	var t := create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_method(func(a: float) -> void:
		_offsets[value] = travel * a
		queue_redraw(), 1.0, 0.0, SLIDE_DUR)
	t.tween_callback(func() -> void:
		_offsets.erase(value)
		queue_redraw()
		_after_move())

func _after_move() -> void:
	if not _is_solved():
		return
	_locked = true
	_reset_later(HOLD_AFTER_SOLVE)

func _reset_later(sec: float) -> void:
	# A tween interval on THIS node, never a SceneTree timer: the shop page is
	# freed on a theme change, and a tree timer would resume into a dead board.
	var t := create_tween()
	t.tween_interval(sec)
	t.tween_callback(_deal)

# --- Drawing ------------------------------------------------------------------------

func _draw() -> void:
	if _cells.is_empty() or size.x <= 4.0:
		return
	var font: Font = ThemeManager.tile_font_heavy
	if font == null:
		font = ThemeManager.tile_font
	if font == null:
		font = get_theme_default_font()
	# The sockets first, so the tray reads as a tray even where a hole is.
	var well: Color = _pal.get("bg2", Color(0.1, 0.1, 0.14))
	for i in N * N:
		var r := _cell_rect(i)
		draw_texture_rect(CandyFace.mask(), r, false, Color(well.r, well.g, well.b, 0.55))
	for i in N * N:
		var value: int = _cells[i]
		if value <= 0:
			continue
		var r := _cell_rect(i)
		var offset: Vector2 = _offsets.get(value, Vector2.ZERO)
		var centre := r.get_center() + offset
		var hw := r.size.x * 0.5
		# THE PALETTE IS HANDED IN, so a theme nobody owns still shows its real
		# glass. `color_for` takes a palette; `color` reads the active one.
		@warning_ignore("integer_division")
		var ramp: int = int(ROW_RAMP[posmod((value - 1) / N, ROW_RAMP.size())])
		var vivid := CandyFace.color_for(_pal, ramp)
		CandyFace.draw_face(self, centre, hw, vivid)
		var label := str(value)
		var px := int(hw * 1.05)
		var ink := CandyFace.text_color(vivid)
		var measured := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, px)
		var at := centre - Vector2(measured.x * 0.5, 0.0) + Vector2(0.0, measured.y * 0.32)
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, px, ink)
