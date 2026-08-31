extends "res://regression/headless/harness/script_test_base.gd"
## The Academy's catalogue contract and its earned forward movement.
##
## Pins that How to Play teaches EVERY mode, the launch tier first and in the
## catalogue's order, one lesson per mode and every rule plug-in in
## GameModes.RULES taught by one of them; that the roster page lists every mode
## in GameModes.all() (a mode added to the game and not to the academy fails
## here); that every lesson's dealt position is REACHABLE and NOT ALREADY SOLVED
## (a lesson that opens finished teaches nothing and a lesson that opens dead
## cannot be finished); that the way forward stays locked until a lesson's board
## comes out; that solving one lights the arrow and persists under the "academy"
## save section by lesson id; and that progress survives a content rebuild and a
## fresh screen.
##
## Runs with reduce-motion ON so every tray beat resolves on the next frame.

const SCENE := "res://scenes/how_to_play/how_to_play.tscn"
const SCRIPT := "res://scenes/how_to_play/how_to_play.gd"
## The catalogue's own order: the launch tier first, then wave two, then three.
const EXPECTED_ORDER := ["classic", "sprint", "lock", "twist", "fog"]
const LAUNCH_COUNT := 4
const LESSON_COUNT := 5

var _had_academy := false
var _academy_snapshot: Dictionary = {}
var _orig_reduce := false
var _screen: Variant = null
var _academy: Variant = null   # the screen script, for its static catalogue

func run_tests() -> void:
	_had_academy = SaveManager.has_section("academy")
	_academy_snapshot = SaveManager.get_section("academy", {})
	_orig_reduce = bool(SettingsManager.get_value("reduce_motion"))
	SettingsManager.set_value("reduce_motion", true)
	SaveManager.clear_section("academy")
	_academy = load(SCRIPT)

	_test_lessons_cover_every_mode()
	_test_every_deal_is_reachable_and_unsolved()
	await _test_fresh_screen_locks_the_way_forward()
	await _test_first_lesson_earns_and_persists()
	await _test_progress_survives_a_rebuild_and_a_reopen()

	await _close_screen()
	if _had_academy:
		SaveManager.set_section("academy", _academy_snapshot)
	else:
		SaveManager.clear_section("academy")
	SettingsManager.set_value("reduce_motion", _orig_reduce)
	SaveManager.flush()

# --- Helpers -----------------------------------------------------------------------
func _open_screen() -> void:
	await _close_screen()
	var packed: PackedScene = load(SCENE)
	_screen = packed.instantiate()
	get_tree().root.add_child(_screen)
	await process_frame
	await process_frame

func _close_screen() -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.queue_free()
		_screen = null
		await process_frame

## Waits until the lesson's tray has finished animating, with a cap so a broken
## view cannot hang the suite.
func _tray_idle() -> void:
	for _i in 240:
		await process_frame
		var view: Variant = _screen.get("_view")
		if view == null or not view.is_busy():
			return

func _saved_done() -> Array:
	return SaveManager.get_section("academy", {}).get("done", [])

## The board a lesson deals, built the way the screen builds it.
func _dealt(lesson: Dictionary) -> Dictionary:
	var mode := GameModes.get_mode(String(lesson["id"]))
	mode.board_size = int(lesson.get("size", 3))
	var rules := SlideRules.make(mode)
	var board := rules.new_board()
	var applied := 0
	for step_v in lesson.get("deal", []):
		if step_v is Array:
			var turn: Array = step_v
			if not turn.is_empty() and not board.rotate_block(int(turn[0]),
					bool(turn[1]) if turn.size() > 1 else true).is_empty():
				applied += 1
		else:
			var cell := int(step_v)
			for nb in board.neighbours(cell):
				if board.at(nb) == SlideBoard.BLANK and board.slide(cell, nb):
					applied += 1
					break
	board.moves = 0
	rules.sync(board)
	return {"board": board, "rules": rules, "applied": applied,
		"wanted": (lesson.get("deal", []) as Array).size()}

# --- The catalogue contract ----------------------------------------------------------
func _test_lessons_cover_every_mode() -> void:
	print("test_lessons_cover_every_mode:")
	var lessons: Array = _academy.LESSONS
	check_eq("one lesson per mode", lessons.size(), LESSON_COUNT)
	check_eq("as many lessons as modes", lessons.size(), GameModes.all().size())

	var ids: Array[String] = []
	for pg_v in lessons:
		ids.append(String((pg_v as Dictionary)["id"]))
	check_eq("the lessons run in the catalogue's order", ids, EXPECTED_ORDER as Array)
	for id in ids:
		check("lesson '%s' is a real mode" % id, GameModes.has_mode(id))
	# The launch tier is taught first: a new player meets the four free boards
	# before anything they cannot open.
	for i in LAUNCH_COUNT:
		check("lesson %d is a launch mode" % i, GameModes.get_mode(ids[i]).tier == "launch")

	# Every rule plug-in is taught by exactly one lesson.
	var taught := {}
	for id in ids:
		var rule := GameModes.get_mode(id).rule
		check("taught rule '%s' is in GameModes.RULES" % rule, GameModes.RULES.has(rule))
		check("rule '%s' is taught once" % rule, not taught.has(rule))
		taught[rule] = true
	for rule in GameModes.RULES:
		check("rule '%s' is taught at all" % rule, taught.has(rule))

	check_eq("the roster is the final page", int(_academy.page_of_id("roster")), ids.size())
	check_eq("six pages", int(_academy.page_count()), LESSON_COUNT + 1)
	check_eq("an unknown id has no page", int(_academy.page_of_id("nope")), -1)

	for pg_v in lessons:
		var pg: Dictionary = pg_v
		var id := String(pg["id"])
		check("'%s' names a goal" % id, not String(pg.get("goal", "")).is_empty())
		check("'%s' has a done line" % id, not String(pg.get("done", "")).is_empty())
		var copy := String(pg["goal"]) + String(pg["done"]) + String(pg.get("intro", ""))
		check("'%s' copy has no em dash" % id, not copy.contains("—"))
		check("'%s' deals a small tray" % id,
			int(pg.get("size", 3)) >= 2 and int(pg.get("size", 3)) <= 4)
		check("'%s' names a deal" % id, not (pg.get("deal", []) as Array).is_empty())

## THE DEAL IS A WALK, so a lesson cannot open on a dead board. What it CAN do
## is name a step that does not apply (a tile with no hole beside it, a rotation
## on a line that is not there), which would silently deal a shallower board than
## the author meant, or none at all. Both are checked here.
func _test_every_deal_is_reachable_and_unsolved() -> void:
	print("test_every_deal_is_reachable_and_unsolved:")
	for pg_v in _academy.LESSONS:
		var pg: Dictionary = pg_v
		var id := String(pg["id"])
		var dealt := _dealt(pg)
		var board: SlideBoard = dealt["board"]
		var rules: SlideRules = dealt["rules"]
		check_eq("'%s': every dealt step lands" % id, int(dealt["applied"]), int(dealt["wanted"]))
		check("'%s': the lesson does not open solved" % id, not board.is_solved())
		check("'%s': something is legal on it" % id, not rules.legal_moves(board).is_empty())
		check_eq("'%s': it opens on nought moves" % id, int(board.moves), 0)
		# The lesson has to be finishable, and quickly: it is a minute, not a
		# sitting. The solver walking it home is the proof.
		var path := SlideSolver.solve(board, rules)
		check("'%s': the board can be brought home" % id, not path.is_empty())
		check("'%s': and inside a lesson's worth of moves (%d)" % [id, path.size()],
			path.size() > 0 and path.size() <= 40)

# --- Earned forward movement ----------------------------------------------------------
func _test_fresh_screen_locks_the_way_forward() -> void:
	print("test_fresh_screen_locks_the_way_forward:")
	SaveManager.clear_section("academy")
	await _open_screen()
	check_eq("a fresh academy opens on the first lesson", int(_screen.get("_page")), 0)
	check("the lesson is not done", not bool(_screen.get("_lesson_done")))
	var forward: Variant = _screen.get("_forward")
	check("the way forward is not offered yet",
		forward == null or not bool(forward.visible))
	check_eq("nothing is reachable past the first lesson",
		int(_screen._furthest_reachable()), 0)
	# The rail refuses a jump the player has not earned.
	_screen._go_to(3)
	await process_frame
	check_eq("a locked page cannot be jumped to", int(_screen.get("_page")), 0)
	check_eq("the roster is locked on a fresh save",
		int(_screen._furthest_reachable()) < int(_academy.page_of_id("roster")), true)

func _test_first_lesson_earns_and_persists() -> void:
	print("test_first_lesson_earns_and_persists:")
	SaveManager.clear_section("academy")
	await _open_screen()
	var board: SlideBoard = _screen.get("_board")
	var rules: SlideRules = _screen.get("_rules")
	check("the first lesson dealt a board", board != null)
	if board == null:
		return
	var path := SlideSolver.solve(board, rules)
	check("the first lesson can be solved", not path.is_empty())
	for move in path:
		if bool(_screen.get("_lesson_done")):
			break
		_screen._play(move)
		# WAIT FOR THE TRAY, not a fixed number of frames. `_play` refuses while
		# the tray is mid-slide, so a hardcoded wait shorter than the slide
		# silently dropped moves and every one after it was illegal.
		await _tray_idle()
	check("solving the board earns the lesson", bool(_screen.get("_lesson_done")))
	check_eq("the lesson id is saved, not its index", _saved_done(), ["classic"] as Array)
	check_eq("the next lesson is reachable now", int(_screen._furthest_reachable()), 1)
	check_eq("the roster is still locked",
		int(_screen._furthest_reachable()) < int(_academy.page_of_id("roster")), true)
	# The forward medallion lights a beat after the board comes out. Waited for
	# by STATE, not by a frame count: a headless frame is a fraction of a real
	# one, so sixty of them are nowhere near the hold the tween is counting.
	var lit := false
	for _i in 900:
		await process_frame
		var f: Variant = _screen.get("_forward")
		if f != null and bool(f.visible):
			lit = true
			break
	check("the way forward is offered", lit)

func _test_progress_survives_a_rebuild_and_a_reopen() -> void:
	print("test_progress_survives_a_rebuild_and_a_reopen:")
	# A theme change rebuilds the content under the screen.
	_screen._rebuild_content()
	await process_frame
	check_eq("a rebuild keeps the earned lesson", _saved_done(), ["classic"] as Array)
	# And a fresh screen reads it back off the save.
	await _open_screen()
	check_eq("a reopened academy remembers", _saved_done(), ["classic"] as Array)
	check_eq("and opens on the first lesson still to earn", int(_screen.get("_page")), 1)
	check_eq("walking back to an earned lesson is allowed", int(_screen._furthest_reachable()), 1)
	_screen._go_to(0)
	await process_frame
	check_eq("an earned lesson can be reopened", int(_screen.get("_page")), 0)
