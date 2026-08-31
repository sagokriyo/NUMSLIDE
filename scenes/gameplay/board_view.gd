class_name BoardView
extends Control
## BoardView — the tray, and the only board there is. A frosted glass pane holding a grid of luminous
## sockets; the tiles are TileView children that the rules' EVENTS drive.
##
## It knows nothing about rules: the conductor hands it `apply(events)` and it
## replays them as motion (slide, wrap, weld, solve), then calls back. Input
## goes the other way: a tap or a swipe lands on a cell and the tray emits
## `cell_pressed(i)` or `swiped(dir, cell)`; the conductor decides what it means.
##
## LAYERS (tree order is the z order):
##   pane   GlassPanel, the frosted tray
##   wells  draws every socket, the hairlines and the Lockdown rim
##   tiles  TileView holders, one per tile VALUE
##   fx     the solve sweep and the landing rings
## Nothing here animates a drawing node: TileViews are holders and `wells` only
## redraws on a state change.
##
## TILES ARE KEYED BY VALUE, and that is the whole reason the animation is
## simple. A sliding puzzle never creates or destroys a piece: tile 7 is the
## same object from the deal to the solve, so a move is a list of tiles and the
## cells they are going to, and the view never has to work out what happened by
## comparing two boards.

## A finger landed on a tile. The conductor decides whether it is a legal move.
signal cell_pressed(index: int)
## A finger dragged across the tray. `dir` is a SlideRules direction, `cell` the
## tile the drag started on (-1 when it started on nothing).
signal swiped(dir: int, cell: int)
## A finger landed on a junction (Twist). The conductor turns the four tiles.
signal pivot_pressed(pivot: int)
## The animation for one apply() has finished playing.
signal move_shown(events: Array)
## The solve celebration has finished playing.
signal solved_shown()

## Whether a tap may land on a tile right now.
var interactive := true

## Gap between sockets as a fraction of a cell.
const GAP_FRAC := 0.06
## How far a finger may travel and still count as a tap rather than a swipe.
const TAP_SLOP := 22.0
## How far it must travel to count as a swipe.
const SWIPE_MIN := 34.0

var w := 4
var h := 4
## True when the tray has no hole in it and a tap turns four tiles round a
## junction. The board is played on the CORNERS then, not on the cells.
var twist := false

var _pane: GlassPanel
var _wells: Wells
var _tiles_layer: Control
var _fx: FxLayer
var _tiles: Dictionary = {}        # value -> TileView
var _cell_of: Dictionary = {}      # value -> cell it is sitting in
var _blank_cells: PackedInt32Array = PackedInt32Array()
var _visible: Dictionary = {}      # cell -> true (Blind); empty = everything shows
var _blind := false
var _locked: PackedInt32Array = PackedInt32Array()
var _live: PackedInt32Array = PackedInt32Array()
var _hint_cell := -1
## The junction under the finger, for the handle's press state.
var _hot_pivot := -1
var _press_cell := -1
var _press_pos := Vector2.ZERO
var _pressing := false
var _busy := false
var _cell_px := 100.0
var _gap := 6.0
var _origin := Vector2.ZERO

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_pane = GlassPanel.new()
	_pane.elevation = 2
	_pane.radius = DesignSystem.RADIUS_LG
	_pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pane)
	_wells = Wells.new()
	_wells.view = self
	add_child(_wells)
	_tiles_layer = Control.new()
	_tiles_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tiles_layer)
	_fx = FxLayer.new()
	_fx.view = self
	add_child(_fx)

func _ready() -> void:
	resized.connect(_relayout)
	if ThemeManager.has_signal("theme_changed"):
		ThemeManager.theme_changed.connect(_on_theme_changed)
	_relayout()

func _on_theme_changed(_p: Dictionary) -> void:
	for v in _tiles:
		(_tiles[v] as TileView).restyle()
	_wells.queue_redraw()

# --- Setup and state ---------------------------------------------------------------

func setup(p_w: int, p_h: int, _p_faces: int = 1) -> void:
	w = maxi(1, p_w)
	h = maxi(1, p_h)
	clear()
	_relayout()

func clear() -> void:
	for v in _tiles:
		(_tiles[v] as TileView).queue_free()
	_tiles.clear()
	_cell_of.clear()
	_blank_cells = PackedInt32Array()
	_hint_cell = -1
	_wells.queue_redraw()

## Rebuilds every tile from a board with no animation.
func sync_board(board: SlideBoard) -> void:
	if board == null:
		return
	twist = board.blanks().is_empty()
	if board.w != w or board.h != h:
		setup(board.w, board.h, 1)
	var seen := {}
	for i in board.size():
		var value := board.at(i)
		if value == SlideBoard.BLANK:
			continue
		seen[value] = true
		var tile: TileView = _tiles.get(value, null)
		if tile == null:
			tile = _make_tile(board, value)
		tile.number = _display_number(board, value)
		tile.ramp_value = _ramp_for(board, value)
		tile.home = board.is_home(i)
		tile.locked = _locked.has(i)
		tile.numeral_alpha = _numeral_alpha(i)
		_cell_of[value] = i
		tile.position = _cell_pos(i)
		tile.size = Vector2(_cell_px, _cell_px)
		tile.restyle()
	# Anything the board no longer carries (a Rush re-deal shrinking the tray).
	for v in _tiles.keys():
		if not seen.has(v):
			(_tiles[v] as TileView).queue_free()
			_tiles.erase(v)
			_cell_of.erase(v)
	_blank_cells = board.blanks()
	_wells.queue_redraw()
	_fx.queue_redraw()

## Deals the board in, tile by tile, as the run opens.
func deal_in(board: SlideBoard) -> void:
	sync_board(board)
	if DesignSystem.reduce_motion():
		return
	var order: Array = _tiles.keys()
	order.sort()
	for k in order.size():
		var tile: TileView = _tiles[order[k]]
		tile.appear(float(k) * 0.012)

func _make_tile(board: SlideBoard, value: int) -> TileView:
	var tile := TileView.new()
	tile.number = _display_number(board, value)
	tile.ramp_value = _ramp_for(board, value)
	tile.size = Vector2(_cell_px, _cell_px)
	_tiles_layer.add_child(tile)
	_tiles[value] = tile
	return tile

## The number painted on a tile. The flat tray shows the value itself.
func _display_number(_board: SlideBoard, value: int) -> int:
	return value

## The rung of the theme's tile ramp a tile draws its colour from: its HOME ROW,
## so a finished board reads as clean bands and a stray tile is obvious.
##
## SPREAD ACROSS THE WHOLE RAMP, not taken off the bottom of it. Consecutive
## rungs (2, 4, 8, 16) are neighbours in a colour story that was authored to
## climb slowly, so four rows off the low end came out as four shades of the
## same pale blue on half the palettes and the banding did not read at all.
## Stepping the rows evenly over the ramp's eleven rungs gives every row a
## colour the eye separates at a glance, on every theme.
const RAMP_RUNGS := 11

func _ramp_for(board: SlideBoard, value: int) -> int:
	var home := board.home_of(value)
	var row: int = board.xy(home).y if home >= 0 else 0
	return ramp_for_row(row, board.h)

## The ramp rung row `row` of `rows` wears. Shared so the tray, the Continue
## card's glimpse and anything else drawing a board agree on the bands.
static func ramp_for_row(row: int, rows: int) -> int:
	var span := maxi(1, rows - 1)
	var rung := 1 + int(round(float(posmod(row, maxi(1, rows))) * float(RAMP_RUNGS - 1) / float(span)))
	return 1 << clampi(rung, 1, RAMP_RUNGS)

func _numeral_alpha(cell: int) -> float:
	if not _blind:
		return 1.0
	return 1.0 if _visible.has(cell) else 0.0

func set_visible_cells(cells: PackedInt32Array) -> void:
	_blind = true
	_visible.clear()
	for c in cells:
		_visible[c] = true
	for v in _tiles:
		var tile: TileView = _tiles[v]
		var target := _numeral_alpha(int(_cell_of.get(v, -1)))
		if is_equal_approx(tile.numeral_alpha, target):
			continue
		if DesignSystem.reduce_motion():
			tile.numeral_alpha = target
			tile.restyle()
		else:
			_fade_numeral(tile, target)
	_wells.queue_redraw()

func _fade_numeral(tile: TileView, target: float) -> void:
	var t := tile.create_tween()
	t.tween_method(func(a: float) -> void:
		tile.numeral_alpha = a
		tile.restyle(), tile.numeral_alpha, target, DesignSystem.DUR_BASE)

func set_locked(cells: PackedInt32Array) -> void:
	_locked = cells
	for v in _tiles:
		var tile: TileView = _tiles[v]
		tile.locked = cells.has(int(_cell_of.get(v, -1)))
		tile.restyle()
	_wells.queue_redraw()

func set_live_group(cells: PackedInt32Array) -> void:
	_live = cells
	_wells.queue_redraw()

func set_hint(cell: int) -> void:
	if _hint_cell == cell:
		return
	var was: TileView = _tile_at(_hint_cell)
	if was != null:
		was.set_hinted(false)
	_hint_cell = cell
	var now := _tile_at(cell)
	if now != null:
		now.set_hinted(true)

func _tile_at(cell: int) -> TileView:
	if cell < 0:
		return null
	for v in _cell_of:
		if int(_cell_of[v]) == cell:
			return _tiles.get(v, null)
	return null

func is_busy() -> bool:
	return _busy

# --- Geometry ----------------------------------------------------------------------

func _relayout() -> void:
	if w <= 0 or h <= 0:
		return
	_pane.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wells.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tiles_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad: float = DesignSystem.SPACE_MD
	var avail := size - Vector2(pad, pad) * 2.0
	if avail.x <= 0.0 or avail.y <= 0.0:
		return
	# One cell size for both axes, so a socket is always square.
	var by_w: float = avail.x / (float(w) + GAP_FRAC * float(w - 1))
	var by_h: float = avail.y / (float(h) + GAP_FRAC * float(h - 1))
	_cell_px = maxf(8.0, minf(by_w, by_h))
	_gap = _cell_px * GAP_FRAC
	var span := Vector2(
		float(w) * _cell_px + float(w - 1) * _gap,
		float(h) * _cell_px + float(h - 1) * _gap)
	_origin = (size - span) * 0.5
	for v in _tiles:
		var tile: TileView = _tiles[v]
		tile.size = Vector2(_cell_px, _cell_px)
		tile.position = _cell_pos(int(_cell_of.get(v, 0)))
	_wells.queue_redraw()

func _cell_pos(index: int) -> Vector2:
	var x := index % w
	@warning_ignore("integer_division")
	var y := (index / w) % h
	return _origin + Vector2(float(x) * (_cell_px + _gap), float(y) * (_cell_px + _gap))

func cell_rect(index: int) -> Rect2:
	return Rect2(_cell_pos(index), Vector2(_cell_px, _cell_px))

func cell_global(index: int) -> Vector2:
	return global_position + cell_rect(index).get_center()

## Junctions on this tray: the interior corners where four tiles meet.
func pivot_count() -> int:
	return maxi(0, (w - 1) * (h - 1))

## Where junction `p` sits on screen: the shared corner of its four tiles.
func pivot_pos(p: int) -> Vector2:
	var pw := w - 1
	if pw <= 0 or p < 0 or p >= pivot_count():
		return Vector2.ZERO
	@warning_ignore("integer_division")
	var pr := p / pw
	var pc := p % pw
	return _origin + Vector2(float(pc + 1) * (_cell_px + _gap) - _gap * 0.5,
		float(pr + 1) * (_cell_px + _gap) - _gap * 0.5)

## The junction NEAREST a local point. Never -1 on a twist board: the four
## corners of a 3 x 3 are far enough apart that the nearest one is always the
## one the player meant, and refusing a tap that landed a few pixels wide of a
## handle is the kind of precision a phone should never ask for.
func pivot_at(local: Vector2) -> int:
	var best := -1
	var best_d := 1e20
	for p in pivot_count():
		var d := local.distance_squared_to(pivot_pos(p))
		if d < best_d:
			best_d = d
			best = p
	return best

## The cell under a local point, or -1. A generous hit box: the gaps belong to
## whichever socket is nearest, so a finger between two tiles is never ignored.
func cell_at(local: Vector2) -> int:
	var p := local - _origin
	var pitch := _cell_px + _gap
	var x := int(floor(p.x / pitch))
	var y := int(floor(p.y / pitch))
	if x < 0 or y < 0 or x >= w or y >= h:
		return -1
	return y * w + x

# --- Input -------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not interactive or _busy:
		return
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var pressed: bool = event.pressed
		var at: Vector2 = event.position
		if pressed:
			_pressing = true
			_press_pos = at
			_press_cell = cell_at(at)
			if twist:
				_hot_pivot = pivot_at(at)
				_fx.queue_redraw()
		elif _pressing:
			_pressing = false
			_release(at)
			if twist:
				_hot_pivot = -1
				_fx.queue_redraw()
		accept_event()
	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and _pressing:
		var at: Vector2 = event.position
		if at.distance_to(_press_pos) >= SWIPE_MIN:
			_pressing = false
			_fire_swipe(at - _press_pos)
			accept_event()

func _release(at: Vector2) -> void:
	var travel := at - _press_pos
	# A twist board has no swipe: every move is a quarter turn about a corner, so
	# a drag across it is a scroll and nothing else.
	if twist:
		if travel.length() <= TAP_SLOP:
			var p := pivot_at(at)
			if p >= 0:
				pivot_pressed.emit(p)
		return
	if travel.length() >= SWIPE_MIN:
		_fire_swipe(travel)
		return
	if travel.length() <= TAP_SLOP and _press_cell >= 0 and _press_cell == cell_at(at):
		cell_pressed.emit(_press_cell)

func _fire_swipe(travel: Vector2) -> void:
	var dir: int
	if absf(travel.x) >= absf(travel.y):
		dir = SlideRules.RIGHT if travel.x > 0.0 else SlideRules.LEFT
	else:
		dir = SlideRules.DOWN if travel.y > 0.0 else SlideRules.UP
	swiped.emit(dir, _press_cell)

# --- Playing the events ------------------------------------------------------------

func apply(events: Array, on_done: Callable = Callable()) -> void:
	if events.is_empty():
		if on_done.is_valid():
			on_done.call()
		return
	_busy = true
	_play(events, on_done)

func _play(events: Array, on_done: Callable) -> void:
	var longest := 0.0
	for e_v in events:
		var e: Dictionary = e_v
		match String(e.get("type", "")):
			"slid":
				longest = maxf(longest, _play_slide(e))
			"twisted":
				longest = maxf(longest, _play_twist(e))
			"locked":
				_play_locked(e)
			"blocked":
				_play_blocked(e)
			"cleared":
				longest = maxf(longest, TileView.slide_dur())
			"solved":
				pass
	var wait := maxf(longest, 0.01)
	var t := create_tween()
	t.tween_interval(wait)
	t.tween_callback(func() -> void:
		_busy = false
		move_shown.emit(events)
		if on_done.is_valid():
			on_done.call())

## Every tile on the run moves at once, which is what makes a three-tile tap
## read as one gesture rather than three.
func _play_slide(e: Dictionary) -> float:
	var pairs: Array = e.get("pairs", [])
	var values: PackedInt32Array = e.get("values", PackedInt32Array())
	var dur := TileView.slide_dur()
	for k in pairs.size():
		var pair: Vector2i = pairs[k]
		var value: int = values[k] if k < values.size() else _value_in(pair.x)
		var tile: TileView = _tiles.get(value, null)
		if tile == null:
			continue
		_cell_of[value] = pair.y
		tile.slide_to(_cell_pos(pair.y), dur)
	_refresh_blanks()
	AudioManager.play_sfx("tile_move")
	return dur

## The pinwheel: four tiles travel a quarter of the way round their shared
## corner. Drawn as an ARC rather than a straight slide, because four tiles
## cutting across the diagonals of a square reads as four unrelated tiles
## swapping places, and turning is the whole idea of the mode.
func _play_twist(e: Dictionary) -> float:
	var pairs: Array = e.get("pairs", [])
	var dur := TileView.slide_dur() * 1.6
	var centre := pivot_pos(int(e.get("pivot", 0)))
	var cw: bool = bool(e.get("cw", true))
	for pair_v in pairs:
		var pair: Vector2i = pair_v
		var value := _value_in(pair.x)
		if value <= 0:
			continue
		var tile: TileView = _tiles.get(value, null)
		if tile == null:
			continue
		_cell_of[value] = pair.y
		if DesignSystem.reduce_motion():
			tile.position = _cell_pos(pair.y)
			continue
		# The tile is swung about the junction: its offset from the corner is
		# rotated a quarter turn, so it travels the arc rather than the chord.
		var from := _cell_pos(pair.x) + Vector2(_cell_px, _cell_px) * 0.5
		var arm := from - centre
		var step: float = (PI * 0.5) * (1.0 if cw else -1.0)
		var half := Vector2(_cell_px, _cell_px) * 0.5
		var tw := tile.create_tween()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_method(func(t: float) -> void:
			tile.position = centre + arm.rotated(step * t) - half, 0.0, 1.0, dur)
	_refresh_blanks()
	AudioManager.play_sfx("tile_move")
	return dur

func _play_locked(e: Dictionary) -> void:
	var cells: PackedInt32Array = e.get("cells", PackedInt32Array())
	for c in cells:
		if not _locked.has(c):
			_locked.append(c)
		var tile := _tile_at(c)
		if tile != null:
			tile.seal()
		_fx.ring(cell_rect(c).get_center(), ThemeManager.color("accent"))
	AudioManager.play_sfx("tile_merge")
	Haptics.medium()
	_wells.queue_redraw()

func _play_blocked(e: Dictionary) -> void:
	var tile := _tile_at(int(e.get("cell", -1)))
	if tile != null:
		tile.refuse()
	AudioManager.play_sfx("invalid")
	Haptics.warning()

func _value_in(cell: int) -> int:
	for v in _cell_of:
		if int(_cell_of[v]) == cell:
			return int(v)
	return 0

## Recomputes which cells are empty from where the tiles now are, and lights any
## tile that has just landed home.
func _refresh_blanks() -> void:
	var taken := {}
	for v in _cell_of:
		taken[int(_cell_of[v])] = true
	var blanks := PackedInt32Array()
	for i in w * h:
		if not taken.has(i):
			blanks.append(i)
	_blank_cells = blanks
	_wells.queue_redraw()

## Marks which tiles are home. Called by the conductor after the board has
## settled, because only it knows the goal.
func mark_home(board: SlideBoard) -> void:
	for v in _tiles:
		var tile: TileView = _tiles[v]
		var cell := int(_cell_of.get(v, -1))
		var now := cell >= 0 and board.at(cell) == board.goal[cell]
		if now and not tile.home:
			tile.flash_home()
			_fx.ring(cell_rect(cell).get_center(), CandyFace.color(tile.ramp_value))
		elif not now and tile.home:
			tile.home = false
			tile.restyle()

## The whole-board celebration: a light sweeps across the tray in reading order.
func celebrate() -> void:
	if DesignSystem.reduce_motion():
		solved_shown.emit()
		return
	var order: Array = _cell_of.keys()
	order.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int(_cell_of[a]) < int(_cell_of[b]))
	for k in order.size():
		var tile: TileView = _tiles[order[k]]
		var delay := float(k) * 0.035
		var t := tile.create_tween()
		t.tween_interval(delay)
		t.tween_callback(func() -> void:
			tile.flash_home()
			_fx.ring(tile.position + tile.size * 0.5, CandyFace.color(tile.ramp_value)))
	var done := create_tween()
	done.tween_interval(float(order.size()) * 0.035 + 0.4)
	done.tween_callback(func() -> void: solved_shown.emit())

# --- The socket layer ---------------------------------------------------------------

class Wells extends Control:
	var view: BoardView

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var v := view
		if v == null or v._cell_px <= 1.0:
			return
		var p := ThemeManager.palette()
		var bg2: Color = p["bg2"]
		var bg0: Color = p["bg0"]
		var accent: Color = ThemeManager.color("accent")
		var well: Color = bg2.lerp(bg0, 0.45)
		var light: bool = bg0.get_luminance() > 0.5
		var mask := CandyFace.mask()
		for i in v.w * v.h:
			var r := v.cell_rect(i)
			# The socket: a recess the tile sits in. On a torus every cell is
			# always filled, so the sockets read as the grout between tiles.
			draw_texture_rect(mask, r, false, Color(well.r, well.g, well.b, 0.55))
			if v._blank_cells.has(i):
				# A hole is lit from inside, so the place a tile can go to is the
				# brightest thing on the tray.
				var glow := Color(accent.r, accent.g, accent.b, 0.10 if light else 0.16)
				var pad := r.size * 0.55
				draw_texture_rect(CandyFace.halo_tex(),
					Rect2(r.get_center() - pad * 1.35, pad * 2.7), false, glow)
				draw_texture_rect(mask, r, false,
					Color(accent.r, accent.g, accent.b, 0.13))
			if v._live.has(i):
				# Lockdown: the cells the player is allowed to finish right now.
				draw_arc(r.get_center(), r.size.x * 0.5 - 2.0, 0.0, TAU, 44,
					Color(accent.r, accent.g, accent.b, 0.55),
					maxf(2.0, r.size.x * 0.035), true)

# --- The effects layer ---------------------------------------------------------------

class FxLayer extends Control:
	var view: BoardView
	var _rings: Array[Dictionary] = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)

	## One turn handle: a ring at the corner four tiles share, with the arrow
	## that says which way they will go. It lifts under the finger.
	func _handle(v: BoardView, p: int, accent: Color, hot: bool) -> void:
		var c := v.pivot_pos(p)
		var r: float = v._cell_px * (0.26 if hot else 0.20)
		var col := Color(accent.r, accent.g, accent.b, 1.0 if hot else 0.75)
		# A dark disc under it, so the arrow reads over whatever glass it covers.
		draw_circle(c, r * 1.12, Color(0.02, 0.03, 0.07, 0.55 if hot else 0.40))
		draw_texture_rect(CandyFace.halo_tex(),
			Rect2(c - Vector2(r, r) * 2.0, Vector2(r, r) * 4.0), false,
			Color(accent.r, accent.g, accent.b, 0.40 if hot else 0.22))
		# Three quarters of a ring, so the gap reads as the direction of travel.
		draw_arc(c, r, -PI * 0.5, PI, 28, col, maxf(2.5, r * 0.26), true)
		# The arrowhead closing the turn, at the open end of the ring.
		var tip := c + Vector2(0.0, -r)
		var a := r * 0.5
		draw_colored_polygon(PackedVector2Array([
			tip + Vector2(a * 0.15, -a * 0.8),
			tip + Vector2(a * 1.15, a * 0.1),
			tip + Vector2(a * 0.05, a * 0.75)]), col)

	## A ring that opens out of a cell and fades. The whole vocabulary of the
	## tray: a tile landing home, a weld closing, a board coming out.
	func ring(at: Vector2, col: Color) -> void:
		if DesignSystem.reduce_motion():
			return
		_rings.append({"at": at, "col": col, "t": 0.0})
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		var alive: Array[Dictionary] = []
		for r in _rings:
			r["t"] = float(r["t"]) + delta * 2.4
			if float(r["t"]) < 1.0:
				alive.append(r)
		_rings = alive
		if _rings.is_empty():
			set_process(false)
		queue_redraw()

	func _draw() -> void:
		var v := view
		if v == null:
			return
		# TWIST: the handles ARE the controls, so they are drawn rather than
		# implied, and they are drawn HERE rather than on the sockets layer. A
		# twist tray is full, so a handle under the tiles is a handle nobody can
		# see: the player taps tiles and watches four of them move for no visible
		# reason. This layer is above them.
		if v.twist:
			var accent := ThemeManager.color("accent")
			for pv in v.pivot_count():
				_handle(v, pv, accent, pv == v._hot_pivot)
		for r in _rings:
			var t := float(r["t"])
			var col: Color = r["col"]
			var radius: float = v._cell_px * (0.45 + t * 0.55)
			var alpha: float = (1.0 - t) * 0.55
			draw_arc(r["at"], radius, 0.0, TAU, 40,
				Color(col.r, col.g, col.b, alpha), maxf(1.5, v._cell_px * 0.035 * (1.0 - t)), true)
