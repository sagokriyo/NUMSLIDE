class_name RulesFog
extends SlideRules
## Blind: the numbers go out.
##
## The board opens face up for a study beat, and from the first slide onward a
## tile only shows its number when it is touching the hole. Everything else is
## blank glass in the theme's own colour, and the only record of where a tile
## went is the one the player is keeping in their head.
##
## THE TILES THAT ARE HOME STAY LIT. Without that the mode is a memory test with
## no board in it, and every player fails the same way: they lose track at tile
## four and there is nothing on screen to recover from. A solved tile staying
## visible turns the puzzle into what it should be, an expanding island of the
## known that you are pushing outward through the dark, and it pays back the one
## thing the player earned. It also means the mode ends face up.

func rule_id() -> String:
	return "fog"

## Everything, until the first slide. After that: the holes, whatever touches
## them, and every tile already home.
func visible_cells(board: SlideBoard) -> PackedInt32Array:
	if board.moves <= 0:
		return super(board)
	var seen := {}
	for b in board.blanks():
		seen[b] = true
		for nb in board.neighbours(b):
			seen[nb] = true
	for i in board.size():
		if board.at(i) != SlideBoard.BLANK and board.is_home(i):
			seen[i] = true
	var out := PackedInt32Array()
	for i in board.size():
		if seen.has(i):
			out.append(i)
	return out

## Blind is played on a small tray and the player is carrying the board in their
## head, so it is dealt shallower than a Classic of the same size. A 40-move
## scramble you cannot see is not four times the puzzle, it is a different and
## much worse one.
func scramble_steps() -> int:
	return maxi(18, cols * rows * 3)
