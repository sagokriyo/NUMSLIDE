class_name SlideRules
extends RefCounted
## SlideRules: the base rule plug-in and the factory that picks one per mode.
##
## A rule turns a move into an ordered list of events on a SlideBoard. It keeps
## no board state of its own, so the solver can clone a board and apply moves
## freely. The base class plays Classic; subclasses override the hooks below
## rather than apply() where they can.
##
## A MOVE takes one of three shapes, and every rule declares which it accepts:
##   {"cell": i}                     tap a tile: the run between it and the hole
##                                   shifts one step (Classic, Lockdown, Blind)
##   {"dir": d}                      swipe: the tile on the far side of the hole
##                                   travels d into it (every tap rule accepts this too)
##   {"pivot": p}                     turn the four tiles round a junction (Twist only)
##
## ONE MOVE IS ONE PLAYER ACTION. A tap that shifts a run of three tiles counts
## once, not three times, because that is what the player did and what a "best
## moves" record has to mean to them. `tiles_moved` on the slid event carries the
## finer number for anything that wants it.
##
## Events, in the order they can appear in one apply():
##   slid / rotated, locked, blocked, solved.

## Swipe directions: the way the TILE travels. Index into DIR_VECTORS.
const RIGHT := 0
const DOWN := 1
const LEFT := 2
const UP := 3
const DIR_VECTORS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
]

var mode: GameModes.Mode = null
## Columns and rows the mode deals.
var cols: int = 4
var rows: int = 4

# --- Factory ----------------------------------------------------------------------

## The rule plug-in for a mode. A rule that is not built yet falls back to
## Classic on the mode's own board size, so no mode can crash the app.
static func make(p_mode: GameModes.Mode) -> SlideRules:
	var r: SlideRules = null
	var rid := p_mode.rule if p_mode != null else "classic"
	match rid:
		"sprint":
			r = RulesSprint.new()
		"lock":
			r = RulesLock.new()
		"twist":
			r = RulesTwist.new()
		"fog":
			r = RulesFog.new()
		_:
			r = RulesClassic.new()
	r.setup(p_mode)
	return r

## The class a rule id maps to, by name. For tests and debug prints.
static func class_for(rid: String) -> String:
	match rid:
		"sprint":
			return "RulesSprint"
		"lock":
			return "RulesLock"
		"twist":
			return "RulesTwist"
		"fog":
			return "RulesFog"
	return "RulesClassic"

## Builds a tap move.
static func tap(cell: int) -> Dictionary:
	return {"cell": cell}

## Builds a swipe move.
static func swipe(dir: int) -> Dictionary:
	return {"dir": dir}

## Reads the mode's flags. Called by make(); safe to call again.
func setup(p_mode: GameModes.Mode) -> void:
	mode = p_mode
	if p_mode == null:
		return
	cols = p_mode.board_size
	rows = p_mode.rows if p_mode.rows > 0 else p_mode.board_size

## The rule id this plug-in serves ("classic" for the base).
func rule_id() -> String:
	return "classic"

## A fresh SOLVED board sized from the mode, with its adjacency table built.
## Callers scramble it after; a rule never deals a scrambled board itself,
## because the seed belongs to the mode (Daily) not the rule.
func new_board() -> SlideBoard:
	var b := SlideBoard.new(cols, rows)
	b.set_adjacency(b.build_flat_adjacency())
	return b

# --- The move interface -------------------------------------------------------------

## Every legal move, as taps. Empty once the board is solved.
func legal_moves(board: SlideBoard) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if outcome(board)["over"]:
		return out
	for i in board.size():
		if board.at(i) == SlideBoard.BLANK:
			continue
		if _can_move(board, i) and not _path_to_blank(board, i).is_empty():
			out.append({"cell": i})
	return out

## The single-tile moves only: the four tiles orthogonally touching a hole.
## The solver searches on these, so its move count is the true optimum.
func unit_moves(board: SlideBoard) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in board.blanks():
		for nb in board.neighbours(b):
			if board.at(nb) != SlideBoard.BLANK and _can_move(board, nb):
				out.append({"cell": nb})
	return out

## True when `move` is one the board would accept. Cheap enough for input checks.
func is_legal(board: SlideBoard, move: Dictionary) -> bool:
	if outcome(board)["over"]:
		return false
	if move.has("dir"):
		return _swipe_source(board, int(move["dir"])) >= 0
	if not move.has("cell"):
		return false
	var cell: int = int(move["cell"])
	if board.at(cell) == SlideBoard.BLANK or not _can_move(board, cell):
		return false
	return not _path_to_blank(board, cell).is_empty()

## Applies a move and returns the events, in order. Returns an empty list and
## leaves the board untouched when the move cannot be made.
func apply(board: SlideBoard, move: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var cell := -1
	if move.has("dir"):
		cell = _swipe_source(board, int(move["dir"]))
	elif move.has("cell"):
		cell = int(move["cell"])
	if cell < 0 or board.at(cell) == SlideBoard.BLANK:
		return events
	if not _can_move(board, cell):
		events.append({"type": "blocked", "cell": cell})
		return events
	var path := _path_to_blank(board, cell)
	if path.is_empty():
		return events

	# Shift every tile on the path one step toward the hole, the far end first
	# so each slide lands in a cell the previous one has just vacated.
	var pairs: Array[Vector2i] = []
	var values := PackedInt32Array()
	for k in range(path.size() - 1, 0, -1):
		values.append(board.at(path[k - 1]))
		if board.slide(path[k - 1], path[k]):
			pairs.append(Vector2i(path[k - 1], path[k]))
	pairs.reverse()
	values.reverse()
	board.moves += 1
	events.append({
		"type": "slid", "pairs": pairs, "values": values,
		"tiles_moved": pairs.size(),
	})
	_after_slide(board, pairs, events)
	_judge(board, events)
	return events

## The board's result. {"over": bool, "solved": bool}
func outcome(board: SlideBoard) -> Dictionary:
	var done := board.is_solved()
	return {"over": done, "solved": done}

## The cells the player may see. Everything, until Blind says otherwise.
func visible_cells(board: SlideBoard) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in board.size():
		out.append(i)
	return out

## Refreshes any per-board state the rule caches (after an undo or a load).
func sync(_board: SlideBoard) -> void:
	pass

## Scrambles the board with a random walk of single-tile slides from the solved
## arrangement. A walk can only reach reachable positions, so the board it deals
## is ALWAYS solvable by construction. Blind inversion-counting parity tests
## are only needed by a scrambler that shuffles the array, and this one does not.
func scramble(board: SlideBoard, rng: RandomNumberGenerator, steps: int) -> void:
	# Where the tile moved by the previous step now sits. Moving it straight
	# back is the one choice the walk refuses: a walk that backtracks spends its
	# length standing still and deals a board that is barely off the goal.
	var just_moved := -1
	var done := 0
	var guard := 0
	while done < steps and guard < steps * 12:
		guard += 1
		var picks := _slide_pairs(board)
		if picks.is_empty():
			break
		var choice: Vector2i = picks[rng.randi_range(0, picks.size() - 1)]
		if choice.x == just_moved and picks.size() > 1:
			continue
		if not board.slide(choice.x, choice.y):
			continue
		just_moved = choice.y
		done += 1
	# A scramble that happens to land solved is not a puzzle. One more nudge.
	if board.is_solved():
		var picks := _slide_pairs(board)
		if not picks.is_empty():
			board.slide(picks[0].x, picks[0].y)
	board.moves = 0
	sync(board)

## Every (tile cell, hole it touches) pair on the board right now.
func _slide_pairs(board: SlideBoard) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for b in board.blanks():
		for nb in board.neighbours(b):
			if board.at(nb) != SlideBoard.BLANK and _can_move(board, nb):
				out.append(Vector2i(nb, b))
	return out

## How far off a scramble should be, in slides, for a board of this size.
## Enough that no board opens near-solved, short of the diameter so a run is
## never hopeless.
func scramble_steps() -> int:
	return maxi(40, cols * rows * 8)

# --- Hooks for subclasses -------------------------------------------------------

## True when the tile at `cell` is allowed to move at all (Lockdown freezes the
## ones that have reached home).
func _can_move(_board: SlideBoard, _cell: int) -> bool:
	return true

## Events after the tiles land and before the board is judged.
func _after_slide(_board: SlideBoard, _pairs: Array[Vector2i], _events: Array[Dictionary]) -> void:
	pass

## Appends the solved event when the board is done.
func _judge(board: SlideBoard, events: Array[Dictionary]) -> void:
	if board.is_solved():
		events.append({"type": "solved", "moves": board.moves})

## The cell whose tile travels `dir` into a hole, or -1 when nothing can.
## Swiping right moves the tile on the hole's LEFT into it.
func _swipe_source(board: SlideBoard, dir: int) -> int:
	if dir < 0 or dir >= DIR_VECTORS.size():
		return -1
	var step: Vector2i = DIR_VECTORS[dir]
	for b in board.blanks():
		var p := board.xy(b)
		var q: Vector2i = p - step
		if not board.in_bounds(q.x, q.y):
			continue
		var src := board.index(q.x, q.y)
		if board.at(src) != SlideBoard.BLANK and _can_move(board, src):
			return src
	return -1

## The ordered cells from `cell` to the hole it can reach, hole included, or an
## empty array when there is none. On a flat tray that is a straight run along a
## row or a column with nothing but movable tiles in between; a rule whose
## topology has no rows overrides it.
func _path_to_blank(board: SlideBoard, cell: int) -> PackedInt32Array:
	var empty := PackedInt32Array()
	if board.at(cell) == SlideBoard.BLANK:
		return empty
	var p := board.xy(cell)
	for step in DIR_VECTORS:
		var path := PackedInt32Array([cell])
		var q: Vector2i = p + step
		while board.in_bounds(q.x, q.y):
			var idx := board.index(q.x, q.y)
			path.append(idx)
			if board.at(idx) == SlideBoard.BLANK:
				return path
			if not _can_move(board, idx):
				break
			q += step
	return empty
