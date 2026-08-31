class_name RulesTwist
extends SlideRules
## Twist: the tray has no hole. Tap a junction where four tiles meet and those
## four pinwheel a quarter turn.
##
## The one mode with no blank in it, which changes everything: there is no
## "the piece next to the hole", every tile is always movable, and a move takes
## four tiles round at once. What it costs in gentleness it pays back in reach,
## because any tile can be walked anywhere in a few turns; what it costs the
## player is that every fix spins three other tiles out of place.
##
## IT REPLACED A TORUS, and the difference is that you can SEE this one. The
## torus rolled whole rows off one edge and back in at the other, which is a
## real puzzle and an unreadable one: nothing on screen says where a row will
## land, and with no corner to anchor to the goal had to be accepted at any
## whole-board shift, so a finished board did not even look finished. Four tiles
## turning around a point you tapped is the same class of puzzle with all of it
## visible.
##
## ALWAYS CLOCKWISE. A second direction wants a second control, and three taps
## is a quarter turn the other way; undo covers a slip. The handle draws the
## arrow so the rule is on screen rather than in a lesson.

func rule_id() -> String:
	return "twist"

## A full tray: no hole, tiles 1 to w*h in reading order.
func new_board() -> SlideBoard:
	var b := SlideBoard.new(cols, rows)
	var g := PackedInt32Array()
	g.resize(cols * rows)
	for i in g.size():
		g[i] = i + 1
	b.set_goal(g)
	b.set_adjacency(b.build_flat_adjacency())
	return b

## Every junction, clockwise.
func legal_moves(board: SlideBoard) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if outcome(board)["over"]:
		return out
	for p in board.pivot_count():
		out.append({"pivot": p})
	return out

func unit_moves(board: SlideBoard) -> Array[Dictionary]:
	return legal_moves(board)

func is_legal(board: SlideBoard, move: Dictionary) -> bool:
	if outcome(board)["over"]:
		return false
	if not move.has("pivot"):
		return false
	var p: int = int(move["pivot"])
	return p >= 0 and p < board.pivot_count()

func apply(board: SlideBoard, move: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not move.has("pivot"):
		return events
	var pivot: int = int(move["pivot"])
	if pivot < 0 or pivot >= board.pivot_count():
		return events
	var cw: bool = bool(move.get("cw", true))
	var pairs := board.rotate_block(pivot, cw)
	if pairs.is_empty():
		return events
	board.moves += 1
	events.append({
		"type": "twisted", "pivot": pivot, "cw": cw,
		"pairs": pairs, "tiles_moved": pairs.size(),
	})
	_judge(board, events)
	return events

## A random walk of quarter turns. Reachability is not in question (every turn
## is reversible by three more), so the walk only has to be long enough to look
## shuffled without undoing itself.
func scramble(board: SlideBoard, rng: RandomNumberGenerator, steps: int) -> void:
	var last := -1
	var repeats := 0
	var done := 0
	var guard := 0
	while done < steps and guard < steps * 8:
		guard += 1
		var pivot := rng.randi_range(0, maxi(0, board.pivot_count() - 1))
		# Four turns of one junction is no turn at all, so the walk never spends
		# a whole cycle standing still.
		if pivot == last:
			repeats += 1
			if repeats >= 3:
				continue
		else:
			repeats = 0
		board.rotate_block(pivot, true)
		last = pivot
		done += 1
	if board.is_solved():
		board.rotate_block(0, true)
	board.moves = 0

## A turn moves four tiles at once, so a twist board comes apart in far fewer
## moves than a tray of the same size.
func scramble_steps() -> int:
	return maxi(10, cols * rows)
