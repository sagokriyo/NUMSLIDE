extends "res://regression/headless/harness/script_test_base.gd"
## The six rule plug-ins: what each one accepts, what it emits, and the one
## thing every scrambler in the game has to guarantee — that the board it deals
## can be brought home.

func run_tests() -> void:
	_test_factory()
	_test_classic_taps_and_swipes()
	_test_runs_move_together()
	_test_every_scramble_is_solvable()
	_test_a_tray_needs_two_rows()
	_test_lockdown()
	_test_twist()
	_test_blind()
	_test_rush()

func _rules(mode_id: String, size: int = 0) -> SlideRules:
	var m := GameModes.get_mode(mode_id)
	if size > 0:
		m.board_size = size
	return SlideRules.make(m)

func _test_factory() -> void:
	print("test_factory:")
	# EVERY rule id in the catalogue builds the class it names, and no two modes
	# share one. The catalogue test pins the mapping; this pins the factory.
	for m in GameModes.all():
		var r := SlideRules.make(m)
		check_eq("'%s' builds its own rule" % m.id, r.rule_id(), m.rule)
		check_eq("'%s' names the class it builds" % m.id,
			SlideRules.class_for(m.rule), SlideRules.class_for(r.rule_id()))
	# An unknown rule falls back to Classic rather than crashing the app.
	var stray := GameModes.get_mode("classic")
	stray.rule = "nonsense"
	check_eq("an unknown rule falls back to classic", SlideRules.make(stray).rule_id(), "classic")

func _test_classic_taps_and_swipes() -> void:
	print("test_classic_taps_and_swipes:")
	var r := _rules("classic", 3)
	var b := r.new_board()
	# Solved 3x3: 1..8 then the hole at cell 8. A finished board offers nothing,
	# which is what stops a solved tray from accepting one more tap.
	check("a solved board offers nothing", r.legal_moves(b).is_empty())
	check("and is over", bool(r.outcome(b)["over"]))
	check("a tap on a finished board is refused", not r.is_legal(b, SlideRules.tap(7)))

	# Move one tile out of place, so the board is live again. Tile 5 sits at
	# cell 4; sliding it down leaves the hole in the middle.
	b.slide(7, 8)
	b.slide(4, 7)
	b.moves = 0
	check("the board is live again", not bool(r.outcome(b)["over"]))
	# The hole is at cell 4 now: cell 1, 3, 5 and 7 all touch it.
	check("a tile beside the hole is legal", r.is_legal(b, SlideRules.tap(1)))
	check("a tile off its row and column is not", not r.is_legal(b, SlideRules.tap(0)))
	var events := r.apply(b, SlideRules.tap(1))
	check_eq("one slide, one event and nothing else", events.size(), 1)
	check_eq("and it is a slide", String(events[0]["type"]), "slid")
	check_eq("one tile moved", int(events[0]["tiles_moved"]), 1)
	check_eq("carrying the value that moved", (events[0]["values"] as PackedInt32Array)[0], 2)
	check_eq("one player action is one move", b.moves, 1)
	check_eq("the tile landed in the hole", b.at(4), 2)

	# A swipe names the direction the TILE travels, so swiping RIGHT pulls the
	# tile on the hole's LEFT side into it. The hole is at cell 1 now.
	check_eq("the hole moved up", b.blank(), 1)
	var before := b.at(0)
	var swipe := r.apply(b, SlideRules.swipe(SlideRules.RIGHT))
	check("a swipe moves a tile", not swipe.is_empty())
	check_eq("the tile left of the hole travelled right", b.at(1), before)

func _test_runs_move_together() -> void:
	print("test_runs_move_together:")
	var r := _rules("classic", 3)
	var b := r.new_board()
	# The hole is at 8. Tapping cell 6 shifts the whole run 6, 7 one step right,
	# which is what makes a tap on a far tile read as one gesture.
	var events := r.apply(b, SlideRules.tap(6))
	check_eq("a run of two moves as one event", events.size(), 1)
	check_eq("two tiles travelled", int(events[0]["tiles_moved"]), 2)
	check_eq("but it counts as ONE move", b.moves, 1)
	check_eq("the tapped tile took the cell it was tapped from", b.at(6), SlideBoard.BLANK)
	check_eq("tile 7 stepped along", b.at(7), 7)
	check_eq("tile 8 took the hole", b.at(8), 8)
	# A run through a cell in another row is not a run at all.
	var r2 := _rules("classic", 3)
	var b2 := r2.new_board()
	check("a tap off the hole's row and column does nothing",
		r2.apply(b2, SlideRules.tap(0)).is_empty())

## THE ONE THING EVERY SCRAMBLER OWES THE PLAYER. A shuffled array is
## unsolvable half the time; a WALK can only reach what it can walk back from.
## Proven here per mode, by walking every board home with the solver.
func _test_every_scramble_is_solvable() -> void:
	print("test_every_scramble_is_solvable:")
	var rng := RandomNumberGenerator.new()
	for m in GameModes.all():
		var r := SlideRules.make(m)
		for seed_n in 3:
			rng.seed = 9000 + seed_n
			var b := r.new_board()
			r.scramble(b, rng, r.scramble_steps())
			check("'%s' seed %d: the scramble moved the board" % [m.id, seed_n], not b.is_solved())
			check("'%s' seed %d: it opens on nought moves" % [m.id, seed_n], b.moves == 0)
			check("'%s' seed %d: something is legal on it" % [m.id, seed_n],
				not r.legal_moves(b).is_empty())
			if m.topology == "square":
				check("'%s' seed %d: the parity is intact" % [m.id, seed_n], b.is_solvable())

## ONE ROW IS NOT A PUZZLE. Tiles on a single line can be translated but never
## REORDERED: whatever the walk does, the numbers still read 1, 2, 3 across the
## strip and the only thing that has moved is the hole. Home's hero was a 1 x 4
## strip, which is why it read as a board where nothing happened. Pinned here
## because the mistake is invisible until you watch it.
func _test_a_tray_needs_two_rows() -> void:
	print("test_a_tray_needs_two_rows:")
	var rng := RandomNumberGenerator.new()
	for shape in [[4, 1], [3, 1]]:
		var m := GameModes.get_mode("classic")
		m.board_size = int(shape[0])
		m.rows = 1
		var r := SlideRules.make(m)
		var ever_reordered := false
		for seed_n in 12:
			rng.seed = seed_n
			var b := r.new_board()
			r.scramble(b, rng, 12)
			if not _in_order(b):
				ever_reordered = true
		check("a %d x 1 strip can never reorder its tiles" % int(shape[0]),
			not ever_reordered)
	# Two rows is the smallest tray whose tiles can actually change places, and
	# it is what the hero deals.
	var hero := GameModes.get_mode("classic")
	hero.board_size = 3
	hero.rows = 2
	var hr := SlideRules.make(hero)
	var reordered := 0
	for seed_n in 12:
		rng.seed = 400 + seed_n
		var b := hr.new_board()
		hr.scramble(b, rng, 12)
		if not _in_order(b):
			reordered += 1
	check("a 3 x 2 tray reorders its tiles (%d of 12 deals)" % reordered, reordered >= 10)
	check_eq("and carries five tiles", hr.new_board().tile_count(), 5)

## True when the tiles read 1, 2, 3 ... in cell order, wherever the hole sits.
func _in_order(board: SlideBoard) -> bool:
	var seen := 0
	for i in board.size():
		var v := board.at(i)
		if v == SlideBoard.BLANK:
			continue
		seen += 1
		if v != seen:
			return false
	return true

func _test_lockdown() -> void:
	print("test_lockdown:")
	var r := _rules("lock", 3) as RulesLock
	var b := r.new_board()
	# The lock order: the top row's first cell alone, then its last pair, then
	# the last two rows in column pairs, then the final 2x2.
	var groups := RulesLock.lock_groups(3, 3)
	check_eq("a 3x3 locks in four groups", groups.size(), 4)
	check_eq("the first group is one cell", groups[0], PackedInt32Array([0]))
	check_eq("then the row's last pair", groups[1], PackedInt32Array([1, 2]))
	check_eq("then a column pair", groups[2], PackedInt32Array([3, 6]))
	check_eq("then the final square", groups[3], PackedInt32Array([4, 5, 7, 8]))
	var flat: Array[int] = []
	for g in groups:
		for c in g:
			flat.append(c)
	check_eq("every cell is locked exactly once", flat.size(), 9)

	r.sync(b)
	check_eq("a solved board is welded shut", RulesLock.locked_cells(b).size(), 9)
	check("and nothing is live on it", r.live_group(b).is_empty())

	# A tile out of order does NOT weld, which is the rule that keeps the mode
	# from dealing dead boards: a tile drifting over its own cell mid-solve
	# would otherwise weld itself into the middle of the tray.
	var b2 := r.new_board()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	r.scramble(b2, rng, 30)
	var live := r.live_group(b2)
	check("a scrambled board has a live group", not live.is_empty())
	check_eq("the live group is the front of the order", live, groups[0] if not RulesLock.locked_cells(b2).has(0) else live)
	for c in RulesLock.locked_cells(b2):
		check("a welded cell is actually home", b2.is_home(c))
	# A welded tile refuses to move, and says so.
	var welded := RulesLock.locked_cells(b2)
	if not welded.is_empty():
		var events := r.apply(b2, SlideRules.tap(welded[0]))
		check("a welded tile refuses", events.size() == 1 and String(events[0]["type"]) == "blocked")

func _test_twist() -> void:
	print("test_twist:")
	var r := _rules("twist", 3) as RulesTwist
	var b := r.new_board()
	check_eq("the tray has no hole in it", b.blanks().size(), 0)
	check_eq("every cell carries a tile", b.tile_count(), 9)
	check_eq("a 3x3 has four junctions", b.pivot_count(), 4)
	check("a solved board offers nothing", r.legal_moves(b).is_empty())

	# The four cells round junction 0 are the top-left square.
	# CLOCKWISE from the top left, not reading order: the turn walks this ring,
	# so the order is the rotation and not a listing.
	check_eq("junction 0 owns the top left square, clockwise", b.pivot_cells(0),
		PackedInt32Array([0, 1, 4, 3]))
	check_eq("junction 3 owns the bottom right", b.pivot_cells(3),
		PackedInt32Array([4, 5, 8, 7]))
	check("an out-of-range junction owns nothing", b.pivot_cells(9).is_empty())

	var b2 := r.new_board()
	var events := r.apply(b2, {"pivot": 0})
	check_eq("a turn is one event", events.size(), 1)
	check_eq("and it is a twist", String(events[0]["type"]), "twisted")
	check_eq("four tiles moved", int(events[0]["tiles_moved"]), 4)
	check_eq("but it counts as ONE move", b2.moves, 1)
	# Clockwise: the top left goes to the top right.
	check_eq("the top left tile went right", b2.at(1), 1)
	check_eq("the top right went down", b2.at(4), 2)
	check_eq("the bottom right went left", b2.at(3), 5)
	check_eq("the bottom left went up", b2.at(0), 4)
	check("the rest of the tray is untouched", b2.at(2) == 3 and b2.at(8) == 9)
	check_eq("an unsolved board offers every junction", r.legal_moves(b2).size(), 4)

	# FOUR TURNS IS NO TURN. The move is its own inverse three times over, which
	# is what makes a walk scramble reversible without a second direction.
	for _i in 3:
		r.apply(b2, {"pivot": 0})
	check("four quarter turns come back to where they started", b2.is_solved())

	# Counter-clockwise is the mirror of clockwise.
	var b3 := r.new_board()
	r.apply(b3, {"pivot": 0, "cw": false})
	check_eq("anticlockwise sends the top left down", b3.at(3), 1)
	r.apply(b3, {"pivot": 0})
	check("and one turn back solves it", b3.is_solved())

	check("a move with no junction is refused", not r.is_legal(b2, {"cell": 0}))
	check("a junction off the tray is refused", not r.is_legal(b2, {"pivot": 99}))

func _test_blind() -> void:
	print("test_blind:")
	var r := _rules("fog", 3) as RulesFog
	var b := r.new_board()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	r.scramble(b, rng, 20)
	check_eq("the board opens face up", r.visible_cells(b).size(), b.size())
	var moves := r.unit_moves(b)
	check("there is something to slide", not moves.is_empty())
	r.apply(b, moves[0])
	var seen := r.visible_cells(b)
	check("the numbers go out after the first slide", seen.size() < b.size())
	check("the hole stays lit", seen.has(b.blank()))
	for nb in b.neighbours(b.blank()):
		check("and so does what touches it", seen.has(nb))
	# A tile that is home stays lit: the island of the known is the only map the
	# player gets, and without it the mode is a memory test with no board in it.
	for i in b.size():
		if b.at(i) != SlideBoard.BLANK and b.is_home(i):
			check("a tile that is home stays lit", seen.has(i))

func _test_rush() -> void:
	print("test_rush:")
	var r := _rules("sprint", 3) as RulesSprint
	r.seed_rng(1234)
	var b := r.new_board()
	# Rush is NEVER over because a board came out. Only the clock ends a run.
	check("a solved board is not over in Rush", not bool(r.outcome(b)["over"]))
	check_eq("nothing cleared yet", r.cleared, 0)
	var first_reward := r.reward_seconds()
	check("the first solve is worth the full reward",
		is_equal_approx(first_reward, RulesSprint.REWARD_SECONDS))

	r.scramble(b, RandomNumberGenerator.new(), 6)
	# Walk it home; the last move should CLEAR rather than end.
	var path := SlideSolver.solve(b, r)
	check("the opening board can be solved", not path.is_empty())
	var cleared_event := {}
	for mv in path:
		for e_v in r.apply(b, mv):
			var e: Dictionary = e_v
			if String(e.get("type", "")) == "cleared":
				cleared_event = e
	check("clearing a board emits a cleared event", not cleared_event.is_empty())
	if cleared_event.is_empty():
		return
	check("it pays seconds back", float(cleared_event["seconds"]) > 0.0)
	check("the board is left solved", b.is_solved())
	# APPLY COUNTS NOTHING. The solver applied many candidate moves getting here
	# and several of them reached a finished board; if the rule banked a clear
	# inside apply, one solve would have paid three.
	check_eq("searching the board banked nothing", r.cleared, 0)
	check_eq("the conductor banks it, once", r.bank_clear(), 1)
	check("the next reward is smaller", r.reward_seconds() < first_reward)
	check("but never below the floor", r.reward_seconds() >= RulesSprint.REWARD_FLOOR)
	check("and the next board is harder", r.next_scramble_steps() > RulesSprint.FIRST_SCRAMBLE)
	r.deal_next(b)
	check("dealing the next board scrambles the tray in place", not b.is_solved())
	check_eq("and it opens on nought moves", b.moves, 0)
