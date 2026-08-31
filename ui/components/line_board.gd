class_name LineBoard
extends Control
## LineBoard — the smallest real board in the game. A 3 x 2 tray: five numbered
## tiles and a hole. Tap a tile in the hole's row or column and the run slides.
## Get 1 to 5 in order and it lights, celebrates and deals itself again.
##
## Home's hero, and deliberately NOT a full board. A 4x4 in the menu is a second
## game sitting above the one the player came to open. Five tiles is a handful of
## taps and the whole rule: slide, order, done. Something to do on the way past.
##
## WHY NOT ONE ROW. It was one, and one row cannot be a sliding puzzle: on a
## single line tiles can only be TRANSLATED, never reordered, so every position
## reachable from the solved one is already solved. It celebrated the instant it
## was dealt and looped. Two rows is the smallest tray that can be scrambled.
##
## It runs the REAL engine — `SlideRules` deals and validates every move — so it
## cannot drift from the board the player is about to open, and cannot deal a
## position that will not come out.
##
## Painted from a PALETTE handed in rather than the active theme, the same rule
## MiniBoard follows, so a caller can show it in any world's glass.
##
## Input is PASS, never STOP: a vertical drag that begins on it still scrolls the
## page (the house rule for anything inside a ScrollContainer).

const COLS := 3
const ROWS := 2
## Gap between sockets, as a fraction of one socket.
const GAP_FRAC := 0.16
## How long a finished tray is held before it deals itself again.
const HOLD := 0.9
const SLIDE_DUR := 0.14
## How far from home it is dealt. Short: a decoration you can actually finish.
const SCRAMBLE := 12
## The ramp rung each ROW wears, so the hero bands like the board does.
const ROW_RAMP := [16, 512]

## Emitted when the five come home.
signal line_made

var _pal: Dictionary = {}
var _rules: SlideRules
var _board: SlideBoard
var _locked := false
var _press_pos := Vector2.ZERO
var _press_ms := 0
## How long a press may last and still be a MOVE. Anything longer belongs to
## whoever else is listening — on Home that is the long-press confetti charge —
## and must not slide a tile when it is released. Set by the screen that owns
## both gestures, so one number decides where a tap ends.
var long_press_s := 0.26
## Per-socket landing pop, 1 -> 0, and the finished tray's light, 0 -> 1. Plain
## floats redrawn by hand, never tweened transforms: this node DRAWS.
var _pop: Array[float] = []
var _glow := 0.0
## The tiles mid-slide (a set of tile numbers), how far along the run is
## (1 -> 0), and the offset that walks them back where they came from. They all
## move one cell the same way, so one offset describes the whole run.
var _moving: Dictionary = {}
var _slide_back := Vector2.ZERO
var _slide_t := 0.0

## A tray `width` design px across. The height follows from the socket size, so
## a caller books width and gets the true box back.
static func make(width: float) -> LineBoard:
	var b := LineBoard.new()
	var cell := width / (float(COLS) + GAP_FRAC * float(COLS - 1))
	var gap := cell * GAP_FRAC
	b.custom_minimum_size = Vector2(width, cell * float(ROWS) + gap * float(ROWS - 1))
	return b

func setup(pal: Dictionary) -> void:
	_pal = pal
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	gui_input.connect(_on_gui_input)
	resized.connect(queue_redraw)
	var mode := GameModes.get_mode("classic")
	mode.board_size = COLS
	mode.rows = ROWS
	_rules = SlideRules.make(mode)
	_pop.resize(COLS * ROWS)
	_deal()

func _deal() -> void:
	_board = _rules.new_board()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_rules.scramble(_board, rng, SCRAMBLE)
	for k in _pop.size():
		_pop[k] = 0.0
	_moving = {}
	_slide_t = 0.0
	_glow = 0.0
	_locked = false
	queue_redraw()

func _cell_rect(i: int) -> Rect2:
	var cell := size.x / (float(COLS) + GAP_FRAC * float(COLS - 1))
	var gap := cell * GAP_FRAC
	@warning_ignore("integer_division")
	var y := i / COLS
	var x := i % COLS
	var span_h := cell * float(ROWS) + gap * float(ROWS - 1)
	var top := (size.y - span_h) * 0.5
	return Rect2(Vector2(float(x) * (cell + gap), top + float(y) * (cell + gap)),
		Vector2(cell, cell))

# --- Input ---------------------------------------------------------------------

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var pressed: bool = event.pressed
		var at: Vector2 = event.position
		if pressed:
			_press(at)
		elif not _held():
			_tap(at)

func _press(p: Vector2) -> void:
	_press_pos = p
	_press_ms = Time.get_ticks_msec()

## True once the finger has been down longer than a tap — see `long_press_s`.
func _held() -> bool:
	return float(Time.get_ticks_msec() - _press_ms) >= long_press_s * 1000.0

func _tap(p: Vector2) -> void:
	if _locked or _board == null:
		return
	for i in _board.size():
		if _cell_rect(i).has_point(p):
			_slide(i)
			return

## The rule decides what moves; the tray only shows it. So a tap on the far end
## of a row walks the whole run along, exactly as it does on the real board.
func _slide(cell: int) -> void:
	var move := SlideRules.tap(cell)
	if not _rules.is_legal(_board, move):
		return
	var events := _rules.apply(_board, move)
	if events.is_empty():
		return
	AudioManager.play_sfx("tile_move", 0.02)
	Haptics.light()
	for e_v in events:
		var e: Dictionary = e_v
		if String(e.get("type", "")) != "slid":
			continue
		var pairs: Array = e.get("pairs", [])
		var values: PackedInt32Array = e.get("values", PackedInt32Array())
		var moved := {}
		for k in values.size():
			moved[values[k]] = true
		if pairs.is_empty() or DesignSystem.reduce_motion():
			continue
		var first: Vector2i = pairs[0]
		_slide_back = _cell_rect(first.x).get_center() - _cell_rect(first.y).get_center()
		_moving = moved
		_slide_t = 1.0
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void:
			_slide_t = v
			for j in _pop.size():
				_pop[j] = v
			queue_redraw(), 1.0, 0.0, SLIDE_DUR).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func() -> void:
			_moving = {}
			_slide_t = 0.0
			queue_redraw())
	queue_redraw()
	if _board.is_solved():
		_finish()

## In order: the tray lights, celebrates, and a beat later it is dealt again.
func _finish() -> void:
	_locked = true
	line_made.emit()
	AudioManager.play_sfx("victory", 0.04)
	Haptics.success()
	Confetti.celebrate(self, 60)
	var tw := create_tween()
	if DesignSystem.reduce_motion():
		_glow = 1.0
		queue_redraw()
	else:
		tw.tween_method(func(v: float) -> void:
			_glow = v
			queue_redraw(), 0.0, 1.0, 0.22).set_ease(Tween.EASE_OUT)
	tw.tween_interval(HOLD)
	tw.tween_callback(_deal)

# --- Drawing --------------------------------------------------------------------

func _draw() -> void:
	if _pal.is_empty() or _board == null or size.x <= 1.0:
		return
	var bg0: Color = _pal.get("bg0", Color.BLACK)
	var bg2: Color = _pal.get("bg2", Color.BLACK)
	var accent: Color = _pal.get("accent", Color.WHITE)
	var well := bg2.lerp(bg0, 0.45)
	var light: bool = bg0.get_luminance() > 0.5
	var mask := CandyFace.mask()

	for i in _board.size():
		var r := _cell_rect(i)
		var c := r.get_center()
		var hw := r.size.x * 0.5
		var ga: float = (0.10 + 0.30 * _glow) * (0.5 if light else 1.0)
		draw_texture_rect(mask, Rect2(c - Vector2(hw, hw) * 1.12, Vector2(hw, hw) * 2.24),
			false, Color(accent.r, accent.g, accent.b, ga))
		draw_texture_rect(mask, r, false, Color(well.r, well.g, well.b, 0.85))

	for i in _board.size():
		var number := _board.at(i)
		if number == SlideBoard.BLANK:
			continue
		var r := _cell_rect(i)
		var c := r.get_center()
		var hw := r.size.x * 0.5
		if _moving.has(number):
			c += _slide_back * _slide_t
		var pop := 1.0 + 0.10 * _pop[i]
		# Banded by the tile's HOME row, so a tile out of place looks it.
		var home := _board.home_of(number)
		@warning_ignore("integer_division")
		var row: int = (home / COLS) if home >= 0 else 0
		var ramp: int = int(ROW_RAMP[posmod(row, ROW_RAMP.size())])
		TileFace.draw_tile_for(self, _pal, c, hw * 0.94 * pop, number, ramp)
