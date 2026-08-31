extends "res://regression/headless/harness/flow_test_base.gd"
## Gameplay flow — plays the real Gameplay screen end to end: a board dealt and
## solved, the par and the grade it earns, Lockdown's welds, Twist's turns,
## Blind's fog, the save behind Home's Continue card, undo and its free budget,
## and the premium gate. Runs with reduce-motion ON so every tray animation
## resolves on the next frame.
##
## THE BOARDS ARE SOLVED BY THE SOLVER, not by a hand-written move list. A
## scramble is random, so a scripted answer would only ever be right for one
## seed; `SlideSolver.solve` finds the path for whatever board was actually
## dealt, which also means the solver is exercised on every run of this flow.

var _orig_premium: bool

func run_tests() -> void:
	snapshot_save_state()
	var orig_reduce: bool = SettingsManager.get_value("reduce_motion")
	SettingsManager.set_value("reduce_motion", true)
	_orig_premium = EntitlementManager.is_premium()
	if _orig_premium:
		EntitlementManager.revoke_premium("_regr_flow")

	await _test_classic_solves_and_grades()
	await _test_lockdown_welds()
	await _test_twist_turns()
	await _test_blind_hides()
	await _test_undo()
	await _test_helpline_pills()
	await _test_every_mode_deals_a_board()
	await _test_premium_gate()

	EntitlementManager._premium = _orig_premium
	SettingsManager.set_value("reduce_motion", orig_reduce)
	restore_save_state()
	await goto_and_settle(SceneRouter.Route["HOME"])

## Opens Gameplay in `mode_id` and waits for a live, scrambled board.
##
## NOTHING IS ASKED ON THE WAY IN. Tapping a mode deals a board and the first
## thing on screen is that board: no sheet, no difficulty menu, no question.
func _open(mode_id: String, extra: Dictionary = {}) -> Variant:
	var payload := {"mode": mode_id, "continue": false}
	for k in extra:
		payload[k] = extra[k]
	var gp: Variant = await goto_and_settle(SceneRouter.Route["GAMEPLAY"], payload)
	if gp == null:
		return null
	var dealt := await await_until(func() -> bool: return gp.get("_board") != null, 300)
	check("%s: the board is dealt with no sheet in the way" % mode_id, dealt)
	if not dealt:
		return null
	check("%s: and it is not dealt solved" % mode_id, not gp._board.is_solved())
	check("%s: it carries a par" % mode_id, int(gp.get("_par")) > 0)
	return gp

## Plays one move through the screen's own input path and waits for the tray.
func _play(gp: Variant, move: Dictionary) -> void:
	gp._play(move)
	await await_until(func() -> bool: return not gp._view.is_busy(), 400)
	await process_frame

## Solves whatever board is on the tray, through the screen's own input path.
## Returns false when the solver could not find a way home.
func _solve(gp: Variant) -> bool:
	var path: Array = SlideSolver.solve(gp._board, gp._rules)
	if path.is_empty():
		return false
	for move in path:
		if bool(gp.get("_ended")):
			break
		await _play(gp, move)
	return true

# --- A board dealt, solved, and graded ------------------------------------------
func _test_classic_solves_and_grades() -> void:
	print("test_classic_solves_and_grades:")
	var gp: Variant = await _open("classic", {"size": 3})
	if gp == null:
		return
	check_eq("classic deals the size it was asked for", int(gp._board.w), 3)
	check_eq("a 3x3 tray carries eight tiles", int(gp._board.tile_count()), 8)
	check_eq("no moves made yet", int(gp._board.moves), 0)

	var saved_before: Dictionary = SaveManager.get_section("current_game", {})
	check("a session is saved for Home's Continue card", saved_before.has("classic"))
	if saved_before.has("classic"):
		var s: Dictionary = saved_before["classic"]
		check("the saved board carries n and cells",
			s.has("board") and (s["board"] as Dictionary).has("cells"))
		check("and the par it was dealt with", s.has("par"))

	var solved := await _solve(gp)
	check("the solver found a way home", solved)
	if not solved:
		return
	check("the board came out", gp._board.is_solved())
	check_eq("every tile is home", int(gp._board.placed()), int(gp._board.tile_count()))
	var ended := await await_until(func() -> bool: return bool(gp.get("_ended")), 400)
	check("solving ends the run", ended)
	# The grade is the whole scoring model: it must be a real rung, and a board
	# closed out by the solver is off the ladder entirely.
	var grade := Pace.grade(int(gp._board.moves), int(gp.get("_par")), bool(gp.get("_assisted")))
	check("the run earned a real grade", Pace.LADDER.has(grade))
	check("the session save is cleared when the run ends",
		not SaveManager.get_section("current_game", {}).has("classic"))
	var card_up := await await_until(func() -> bool: return gp.get("_modal") != null, 600)
	check("the run-over card is up", card_up)

# --- Lockdown: a tile that gets home is welded there -------------------------------
func _test_lockdown_welds() -> void:
	print("test_lockdown_welds:")
	var gp: Variant = await _open("lock")
	if gp == null:
		return
	check("lockdown runs the lock rule", gp._rules is RulesLock)
	var live: PackedInt32Array = (gp._rules as RulesLock).live_group(gp._board)
	check("a group is live from the start", not live.is_empty())
	var solved := await _solve(gp)
	check("the solver respects the welds", solved)
	if not solved:
		return
	var locked := RulesLock.locked_cells(gp._board)
	check_eq("a solved board is welded shut", locked.size(), int(gp._board.size()))
	check("nothing is live once it is all welded",
		(gp._rules as RulesLock).live_group(gp._board).is_empty())

# --- Twist: the tray with no hole in it ------------------------------------------
func _test_twist_turns() -> void:
	print("test_twist_turns:")
	var gp: Variant = await _open("twist")
	if gp == null:
		return
	check("twist runs the twist rule", gp._rules is RulesTwist)
	check_eq("there is no hole on the tray", gp._board.blanks().size(), 0)
	check_eq("every cell carries a tile", int(gp._board.tile_count()), int(gp._board.size()))
	check_eq("a 3x3 has four junctions", int(gp._board.pivot_count()), 4)
	# A junction turned four times is the board it started on.
	var before: PackedInt32Array = gp._board.cells.duplicate()
	await _play(gp, {"pivot": 0})
	check("a turn moved the board", gp._board.cells != before)
	check_eq("and it counted as one move", int(gp._board.moves), 1)
	for _i in 3:
		await _play(gp, {"pivot": 0})
	check("four quarter turns come back round", gp._board.cells == before)
	check_eq("and all four counted", int(gp._board.moves), 4)
	# The tray takes taps on the JUNCTIONS, not the cells.
	check("the tray is in twist mode", bool(gp._view.twist))
	var handles: int = gp._view.pivot_count()
	check_eq("the tray draws a handle per junction", handles, int(gp._board.pivot_count()))

# --- Blind: the numbers go out ----------------------------------------------------------
func _test_blind_hides() -> void:
	print("test_blind_hides:")
	var gp: Variant = await _open("fog")
	if gp == null:
		return
	check("blind runs the fog rule", gp._rules is RulesFog)
	var all_seen: PackedInt32Array = gp._rules.visible_cells(gp._board)
	check_eq("the board opens face up", all_seen.size(), int(gp._board.size()))
	var moves: Array = gp._rules.unit_moves(gp._board)
	check("there is something to slide", not moves.is_empty())
	if moves.is_empty():
		return
	await _play(gp, moves[0])
	var seen: PackedInt32Array = gp._rules.visible_cells(gp._board)
	check("the numbers go out after the first slide", seen.size() < int(gp._board.size()))
	check("the hole is always lit", seen.has(gp._board.blank()))

# --- Undo and its free budget ---------------------------------------------------------------
func _test_undo() -> void:
	print("test_undo:")
	var gp: Variant = await _open("classic", {"size": 3})
	if gp == null:
		return
	var before: PackedInt32Array = gp._board.cells.duplicate()
	var moves: Array = gp._rules.unit_moves(gp._board)
	if moves.is_empty():
		check("there is something to slide", false)
		return
	await _play(gp, moves[0])
	check("the board moved", gp._board.cells != before)
	check_eq("one move counted", int(gp._board.moves), 1)
	check_eq("undo history holds your move", (gp._history as Array).size(), 1)
	var coins_before: int = Wallet.balance(WalletRules.COINS)
	gp._on_undo()
	await await_until(func() -> bool: return not gp._view.is_busy(), 300)
	check("undo put the board back", gp._board.cells == before)
	check_eq("the free undo cost nothing", Wallet.balance(WalletRules.COINS), coins_before)
	check_eq("one undo used", int(gp._undos_used), 1)
	check("undo marked the run", bool(gp._used_undo))

# --- The helpline pills -----------------------------------------------------------
## The free COUNT and the coin PRICE share one slot, so they have to be told
## apart by something other than the number: the price wears a coin.
func _test_helpline_pills() -> void:
	print("test_helpline_pills:")
	var gp: Variant = await _open("classic", {"size": 3})
	if gp == null:
		return
	var hint: Variant = gp.get("_hint_btn")
	check("the board has a hint pill", hint != null)
	if hint == null:
		return
	var free_hints: int = gp._free_hints()
	check_eq("it opens on the free count", String(hint.text), "Hint · %d" % free_hints)
	check("and wears no coin while it is free", hint.icon == null)
	# Spend every free hint.
	for _i in free_hints:
		gp._on_hint()
		await process_frame
	check_eq("the free hints are spent", int(gp.get("_hints_used")), free_hints)
	check("the pill now shows a price", String(hint.text).contains(str(EconomyRules.HINT_PRICE)))
	check("and wears a coin to say so", hint.icon != null)
	check("the two states do not read the same",
		String(hint.text) != "Hint · %d" % free_hints)

## Every mode deals a live board the moment it opens, and never asks anything.
func _test_every_mode_deals_a_board() -> void:
	print("test_every_mode_deals_a_board:")
	EntitlementManager.grant_premium("_regr_flow")
	for m in GameModes.all():
		var gp: Variant = await goto_and_settle(SceneRouter.Route["GAMEPLAY"],
			{"mode": m.id, "continue": false})
		if gp == null:
			check("%s: the screen built" % m.id, false)
			continue
		var dealt := await await_until(func() -> bool: return gp.get("_board") != null, 400)
		check("%s: deals straight to a board" % m.id, dealt)
		if not dealt:
			continue
		check("%s: the board is scrambled" % m.id, not gp._board.is_solved())
		check("%s: the rule it names is the rule it runs" % m.id,
			gp._rules.rule_id() == m.rule)
		check("%s: something is legal on it" % m.id, not gp._rules.legal_moves(gp._board).is_empty())
	EntitlementManager.revoke_premium("_regr_flow")

# --- The premium gate ------------------------------------------------------------------------
func _test_premium_gate() -> void:
	print("test_premium_gate:")
	EntitlementManager.revoke_premium("_regr_flow")
	await goto_and_settle(SceneRouter.Route["GAMEPLAY"], {"mode": "fog", "continue": false})
	# A locked mode routes straight to the paywall.
	var rerouted := await await_until(func() -> bool:
		var cur := current_scene
		return cur != null and cur.scene_file_path == SceneRouter.Route["PREMIUM"], 600)
	check("a premium mode without premium lands on the paywall", rerouted)
