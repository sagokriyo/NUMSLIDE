extends "res://regression/headless/harness/script_test_base.gd"
## SlideSolver and the Pace ladder: the thing that knows the way out, and the
## thing that decides what a run was worth.
##
## THE SOLVER'S ONE PROMISE IS THAT IT ANSWERS. A hint that thinks for four
## seconds has already failed the player, so every strategy in it is capped and
## the last one cannot fail. These tests hold it to that on every mode, at every
## size the game deals, and on a board deliberately left one move from home.

func run_tests() -> void:
	_test_hint_always_answers()
	_test_hint_is_a_legal_move()
	_test_optimal_on_a_short_board()
	_test_solve_brings_a_board_home()
	_test_answers_inside_its_budget()
	_test_solver_leaves_the_board_alone()
	_test_pace_ladder()
	_test_pace_grades()

func _dealt(mode_id: String, seed_v: int, size: int = 0) -> Array:
	var m := GameModes.get_mode(mode_id)
	if size > 0:
		m.board_size = size
	var r := SlideRules.make(m)
	var b := r.new_board()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	r.scramble(b, rng, r.scramble_steps())
	return [b, r]

func _test_hint_always_answers() -> void:
	print("test_hint_always_answers:")
	# EVERY mode, at the size it deals. Twist is the hard case: no hole to walk and
	# no distance bound to prune with, so it proves the fallback.
	for m in GameModes.all():
		for seed_n in 2:
			var pair := _dealt(m.id, 300 + seed_n)
			var b: SlideBoard = pair[0]
			var r: SlideRules = pair[1]
			var mv := SlideSolver.hint(b, r)
			check("'%s' seed %d: the hint answers" % [m.id, seed_n], not mv.is_empty())
			check("'%s' seed %d: and it is legal" % [m.id, seed_n], r.is_legal(b, mv))
	# A finished board has nothing to suggest, and says so rather than guessing.
	var solved := SlideRules.make(GameModes.get_mode("classic"))
	check("a solved board gets no hint", SlideSolver.hint(solved.new_board(), solved).is_empty())

func _test_hint_is_a_legal_move() -> void:
	print("test_hint_is_a_legal_move:")
	# Classic at all three sizes it offers.
	for size in [3, 4, 5]:
		var pair := _dealt("classic", 88, size)
		var b: SlideBoard = pair[0]
		var r: SlideRules = pair[1]
		var mv := SlideSolver.hint(b, r)
		check("%dx%d: the hint answers" % [size, size], not mv.is_empty())
		check("%dx%d: applying it moves the board" % [size, size],
			not r.apply(b, mv).is_empty())
	# Twist has no hole and no tile to point at, so the hint names a JUNCTION.
	var twist_pair := _dealt("twist", 4)
	var tb: SlideBoard = twist_pair[0]
	var tr: SlideRules = twist_pair[1]
	var tm := SlideSolver.hint(tb, tr)
	check("the twist hint answers", not tm.is_empty())
	check("and it names a junction, not a tile", tm.has("pivot"))
	check("which is legal", tr.is_legal(tb, tm))

## On a board a handful of moves from home the answer must be the SHORTEST one,
## because that is what the player is being graded against.
func _test_optimal_on_a_short_board() -> void:
	print("test_optimal_on_a_short_board:")
	var r := SlideRules.make(GameModes.get_mode("classic"))
	var b := r.new_board()
	b.set_adjacency(b.build_flat_adjacency())
	# Walk three single-tile slides out of the solved board, so the way back is
	# exactly three and there is no shorter one.
	b.slide(14, 15)
	b.slide(10, 14)
	b.slide(9, 10)
	b.moves = 0
	var path := SlideSolver.solve(b, r)
	check_eq("three slides out, three slides back", path.size(), 3)
	for mv in path:
		check("every step is legal when it is played", r.is_legal(b, mv))
		r.apply(b, mv)
	check("and the board came home", b.is_solved())
	# The hint on that board is the first move of the shortest line.
	var again := r.new_board()
	again.set_adjacency(again.build_flat_adjacency())
	again.slide(14, 15)
	again.slide(10, 14)
	again.moves = 0
	var hint := SlideSolver.hint(again, r)
	check_eq("the hint is the first move of the optimal line", int(hint["cell"]), 14)

func _test_solve_brings_a_board_home() -> void:
	print("test_solve_brings_a_board_home:")
	# EVERY SIZE CLASSIC DEALS, INCLUDING THE 5x5. It used to be tested at 3 and
	# 4 only, and a 5x5 auto-solve failed outright on most boards for as long as
	# that was true — the row's last PAIR is the placement that blows a plain
	# search's budget, and only the big tray gets far enough for it to matter.
	for size in [3, 4, 5]:
		for seed_n in 2:
			var pair := _dealt("classic", 707 + seed_n * 31, size)
			var b: SlideBoard = pair[0]
			var r: SlideRules = pair[1]
			var path := SlideSolver.solve(b, r)
			check("%dx%d seed %d: the solver found a way home"
				% [size, size, seed_n], not path.is_empty())
			if path.is_empty():
				continue
			for mv in path:
				r.apply(b, mv)
			check("%dx%d seed %d: and walking it solves the board"
				% [size, size, seed_n], b.is_solved())
	# TWIST, which nothing used to solve. Its hint fell through to greedy and
	# passed the suite that way, so the auto-solve was broken on it from the day
	# the mode shipped: the tray has no hole, so the search runs from both ends
	# and meets in the middle, and nothing else here can stand in for it.
	var tw := _dealt("twist", 909)
	var tb: SlideBoard = tw[0]
	var tr: SlideRules = tw[1]
	var twist_path := SlideSolver.solve(tb, tr)
	check("twist: the solver found a way home", not twist_path.is_empty())
	for mv in twist_path:
		check("twist: every turn it names is legal", tr.is_legal(tb, mv))
		tr.apply(tb, mv)
	check("twist: and walking it solves the board", tb.is_solved())
	# Blind: the same tray as Classic under a rule that hides it. The solver can
	# see what the player cannot, so a fog board must solve like any other.
	var fg := _dealt("fog", 404)
	var fb: SlideBoard = fg[0]
	var fr: SlideRules = fg[1]
	var fog_path := SlideSolver.solve(fb, fr)
	check("blind: the solver found a way home", not fog_path.is_empty())
	for mv in fog_path:
		fr.apply(fb, mv)
	check("blind: and walking it solves the board", fb.is_solved())
	# Lockdown: the welds close behind the solver, so a path that placed a group
	# out of order would jam and never finish.
	var lock_pair := _dealt("lock", 55)
	var lb: SlideBoard = lock_pair[0]
	var lr: SlideRules = lock_pair[1]
	var lock_path := SlideSolver.solve(lb, lr)
	check("lockdown: the solver found a way home", not lock_path.is_empty())
	for mv in lock_path:
		lr.apply(lb, mv)
	check("lockdown: and it solved without jamming", lb.is_solved())
	check_eq("lockdown: every cell welded", RulesLock.locked_cells(lb).size(), lb.size())

## THE DEADLINE IS THE PROMISE. Every strategy in the solver is capped by a wall
## clock, and this is the test that says so — the auto-solve used to freeze the
## app for forty seconds on a 4x4 and over three minutes on a Blind board, which
## no node budget anywhere in the file would ever have caught.
func _test_answers_inside_its_budget() -> void:
	print("test_answers_inside_its_budget:")
	# Generous slack over the budget: a headless CI box is not a phone, and one
	# search step is allowed to overrun the deadline it checks between steps.
	var solve_cap := SlideSolver.SOLVE_BUDGET_MS * 3
	var hint_cap := SlideSolver.HINT_BUDGET_MS * 4
	for m in GameModes.all():
		var pair := _dealt(m.id, 616)
		var b: SlideBoard = pair[0]
		var r: SlideRules = pair[1]
		var t0 := Time.get_ticks_msec()
		SlideSolver.hint(b, r)
		var hint_ms := Time.get_ticks_msec() - t0
		check("'%s': the hint answers in %d ms, under %d"
			% [m.id, hint_ms, hint_cap], hint_ms < hint_cap)
		t0 = Time.get_ticks_msec()
		SlideSolver.solve(b, r)
		var solve_ms := Time.get_ticks_msec() - t0
		check("'%s': the solve answers in %d ms, under %d"
			% [m.id, solve_ms, solve_cap], solve_ms < solve_cap)

## The solver works on CLONES. A hint must never move the board it was asked
## about, or asking for one would play a move.
func _test_solver_leaves_the_board_alone() -> void:
	print("test_solver_leaves_the_board_alone:")
	var pair := _dealt("classic", 12, 4)
	var b: SlideBoard = pair[0]
	var r: SlideRules = pair[1]
	var before := b.cells.duplicate()
	var moves_before := b.moves
	SlideSolver.hint(b, r)
	check("a hint does not move the board", b.cells == before)
	check_eq("nor count a move", b.moves, moves_before)
	SlideSolver.solve(b, r)
	check("a solve does not move the board either", b.cells == before)
	check_eq("nor count a move", b.moves, moves_before)

# --- The Pace ladder ------------------------------------------------------------
func _test_pace_ladder() -> void:
	print("test_pace_ladder:")
	check_eq("four rungs", Pace.LADDER.size(), 4)
	check_eq("Steady is the first", Pace.rung(Pace.STEADY), 1)
	check_eq("Sharp the second", Pace.rung(Pace.SHARP), 2)
	check_eq("Expert the third", Pace.rung(Pace.EXPERT), 3)
	check_eq("Perfect the top", Pace.rung(Pace.PERFECT), 4)
	check_eq("an assisted run is off the ladder", Pace.rung(Pace.ASSISTED), 0)
	check_eq("and so is nonsense", Pace.rung("nope"), 0)
	for id in Pace.LADDER:
		check("'%s' has a title" % id, not Pace.title(id).is_empty())
		check("'%s' has a line" % id, not Pace.line(id).is_empty())
		check("'%s' line has no em dash" % id, not Pace.line(id).contains("—"))
		# EVERY grade must be priced, or a run could come home to nothing.
		check("'%s' is priced" % id, EconomyRules.PACE_BONUS.has(id))
	check("the assisted run is priced too", EconomyRules.PACE_BONUS.has(Pace.ASSISTED))
	check_eq("Sharp climbs to Expert", Pace.next_up(Pace.SHARP), Pace.EXPERT)
	check_eq("nothing is above Perfect", Pace.next_up(Pace.PERFECT), "")

func _test_pace_grades() -> void:
	print("test_pace_grades:")
	# Par is derived from the board actually dealt, so a deeper scramble asks
	# more and the grade means the same thing on every board of every size.
	var r := SlideRules.make(GameModes.get_mode("classic"))
	var near := r.new_board()
	near.set_adjacency(near.build_flat_adjacency())
	check_eq("a solved board still asks for the floor",
		Pace.par_for(near), Pace.PAR_FLOOR)
	var pair := _dealt("classic", 21, 4)
	var b: SlideBoard = pair[0]
	var par := Pace.par_for(b)
	check("a scrambled board asks for more than the floor", par > Pace.PAR_FLOOR)
	check("and the par tracks the board's own distance",
		par >= b.manhattan())

	# The ladder is monotone: more moves is never a better grade.
	var last := 5
	for moves in [1, par / 2, par, par * 2, par * 4]:
		var grade := Pace.grade(int(moves), par)
		check("%d moves earns a real grade" % moves, Pace.LADDER.has(grade))
		check("%d moves is no better than fewer" % moves, Pace.rung(grade) <= last)
		last = Pace.rung(grade)
	check_eq("a flawless run is Perfect", Pace.grade(1, par), Pace.PERFECT)
	check_eq("a long one is Steady", Pace.grade(par * 6, par), Pace.STEADY)
	# The solver closing a board out puts the run off the ladder, whatever the
	# move count says.
	check_eq("an assisted board is Assisted", Pace.grade(1, par, true), Pace.ASSISTED)
	# The threshold a grade names is a move count that actually earns it.
	for id in [Pace.PERFECT, Pace.EXPERT, Pace.SHARP]:
		var need := Pace.threshold(id, par)
		check("'%s' names a reachable move count" % id, need > 0)
		check_eq("and hitting it earns '%s'" % id, Pace.grade(need, par), id)

	# THE TOP RUNG MUST BE REACHABLE. Par used to be the board's Manhattan
	# distance times 1.2, and Manhattan is a LOWER BOUND on the moves left, not
	# a solution length — measured over random 3x3 deals the shortest line runs
	# about 1.47x it. So Perfect and usually Expert asked for fewer moves than
	# the puzzle contained, and no player on any board could earn either. A grade
	# nobody can reach is not a target, it is a lie the bar tells every run.
	for size in [3, 4, 5]:
		var deal := _dealt("classic", 4242, size)
		var board: SlideBoard = deal[0]
		var p := Pace.par_for(board)
		var floor_moves := SlideSolver.distance(board)
		check("%dx%d: Perfect asks for more moves than the board's own bound"
			% [size, size], Pace.threshold(Pace.PERFECT, p) > floor_moves)
