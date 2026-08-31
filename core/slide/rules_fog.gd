class_name RulesFog
extends SlideRules
## Blind: the numbers go out.
##
## The board opens face up for a study beat, and from the first slide onward a
## tile only shows its number when it is touching the hole. Everything else is
## blank glass in the theme's own colour, and the only record of where a tile
## went is the one the player is keeping in their head.
##
## A FINISHED ROW LIGHTS, AND STAYS LIT. Without that the mode is a memory test
## with no board in it, and every player fails the same way: they lose track at
## tile four and there is nothing on screen to recover from. A row coming up
## turns the puzzle into what it should be, an expanding island of the known
## that you are pushing downward through the dark, and it pays back the one thing
## the player earned. It also means the mode ends face up.
##
## THE ROW, NOT THE TILE, AND IT LATCHES. Lighting each tile the moment it
## happened to be home read as a fault: a tile drifting across its own cell on
## the way somewhere else flashed its number for one slide and went out again, so
## the board flickered constantly and none of it meant anything. A row is the
## unit the player is actually working in and it is a thing they can finish. Once
## finished it is remembered (`META_LIT`), so breaking a row open to free the
## hole below it does not take the row back — which is exactly when the numbers
## are worth most.

## Rows that have been completed at least once, as an Array in board.meta.
const META_LIT := "lit_rows"

func rule_id() -> String:
	return "fog"

## Everything, until the first slide. After that: the holes, whatever touches
## them, and every row the player has brought home.
func visible_cells(board: SlideBoard) -> PackedInt32Array:
	if board.moves <= 0:
		return super(board)
	var seen := {}
	for b in board.blanks():
		seen[b] = true
		for nb in board.neighbours(b):
			seen[nb] = true
	for row in lit_rows(board):
		for x in board.w:
			seen[board.index(x, int(row))] = true
	var out := PackedInt32Array()
	for i in board.size():
		if seen.has(i):
			out.append(i)
	return out

## The rows lit so far, as they stand on this board.
static func lit_rows(board: SlideBoard) -> PackedInt32Array:
	var out := PackedInt32Array()
	var raw: Array = board.meta.get(META_LIT, [])
	for v in raw:
		out.append(int(v))
	return out

## True when every tile of row `y` is home. The hole counts as home wherever the
## goal puts it, so the row holding the blank still completes.
static func row_is_home(board: SlideBoard, y: int) -> bool:
	for x in board.w:
		if not board.is_home(board.index(x, y)):
			return false
	return true

## Lights any row that just came home. Rows only ever accumulate: see the class
## note — a lit row is a thing the player finished, not a thing they are holding.
func _after_slide(board: SlideBoard, _pairs: Array[Vector2i], _events: Array[Dictionary]) -> void:
	_relight(board, false)

## An undo or a load rebuilds the lit rows from the position, and RESETS them,
## because the alternative is a run that remembers rows the board it was loaded
## from never had. Stepping back over the move that lit a row hands the dark
## back with it, which is the honest reading of undo.
func sync(board: SlideBoard) -> void:
	_relight(board, true)

func _relight(board: SlideBoard, reset: bool) -> void:
	var lit := {}
	if not reset:
		for row in lit_rows(board):
			lit[int(row)] = true
	for y in board.h:
		if row_is_home(board, y):
			lit[y] = true
	var out: Array = lit.keys()
	out.sort()
	board.meta[META_LIT] = out

## Blind opens on a board that is fully shuffled and wholly dark, so the
## scramble runs on a clean meta and the lit rows are derived after.
func scramble(board: SlideBoard, rng: RandomNumberGenerator, steps: int) -> void:
	board.meta.erase(META_LIT)
	super(board, rng, steps)

## Blind is played on a small tray and the player is carrying the board in their
## head, so it is dealt shallower than a Classic of the same size. A 40-move
## scramble you cannot see is not four times the puzzle, it is a different and
## much worse one.
func scramble_steps() -> int:
	return maxi(18, cols * rows * 3)
