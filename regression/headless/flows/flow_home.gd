extends "res://regression/headless/harness/flow_test_base.gd"
## Home flow — the hero's TWO GESTURES on one control.
##
## A tap slides a tile; a long press charges the confetti bomb and releasing it
## detonates. They share `gui_input` and divide the gesture at one threshold, so
## the thing worth pinning is that they still divide it: a hold must not slide,
## a tap must not charge, and the two must read the same number.
##
## The bomb only exists with motion on, so the charge half is skipped under
## reduce-motion — which is itself the contract (a hold is a plain tap there).

var _orig_reduce: bool

func run_tests() -> void:
	snapshot_save_state()
	_orig_reduce = SettingsManager.get_value("reduce_motion")
	SettingsManager.set_value("reduce_motion", false)

	await _test_hero_gestures()

	SettingsManager.set_value("reduce_motion", _orig_reduce)
	Engine.time_scale = 1.0
	restore_save_state()

## The hero board on Home, or null.
func _hero(home: Variant) -> LineBoard:
	var holder: Variant = home.get("_word")
	if holder == null or not is_instance_valid(holder):
		return null
	for c in holder.get_children():
		if c is LineBoard:
			return c
	return null

func _press(strip: LineBoard, at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = at
	strip.gui_input.emit(e)

func _test_hero_gestures() -> void:
	print("test_hero_gestures:")
	var home: Variant = await goto_and_settle(SceneRouter.Route["HOME"])
	check("Home built", home != null)
	if home == null:
		return
	var strip := _hero(home)
	check("the hero is a board", strip != null)
	if strip == null:
		return

	# ONE THRESHOLD. The board and the charge both read it; if they ever disagree
	# a hold would slide a tile on its way to the bomb, or neither would fire.
	check_eq("the board and the charge share one threshold",
		strip.long_press_s, home.get("_WM_HOLD_S"))

	# --- A TAP is a MOVE, never a charge ------------------------------------
	var before: PackedInt32Array = strip._board.cells.duplicate()
	# A tile the RULE accepts, not an arbitrary one: on a 3 x 2 tray most tiles
	# are not beside the hole, and tapping one of those is correctly a no-op.
	var legal: Array = strip._rules.legal_moves(strip._board)
	check("the hero has a legal move to tap", not legal.is_empty())
	if legal.is_empty():
		return
	var cell := strip._cell_rect(int(legal[0]["cell"])).get_center()
	_press(strip, cell, true)
	_press(strip, cell, false)
	await process_frame
	check("a tap slides a tile", strip._board.cells != before)
	check("and charges nothing", home.get("_charge_root") == null)

	# --- A HOLD charges, and does NOT slide ----------------------------------
	var held_from: PackedInt32Array = strip._board.cells.duplicate()
	var legal_now: Array = strip._rules.legal_moves(strip._board)
	if legal_now.is_empty():
		return
	# A tile a TAP would move, so the hold is genuinely suppressing a move.
	var at := strip._cell_rect(int(legal_now[0]["cell"])).get_center()
	_press(strip, at, true)
	var charged := false
	for _i in 900:
		await process_frame
		if home.get("_charge_root") != null:
			charged = true
			break
	check("holding charges the bomb", charged)
	check("and the hold did not slide a tile", strip._board.cells == held_from)

	# --- RELEASE detonates ---------------------------------------------------
	_press(strip, at, false)
	await process_frame
	check("releasing spends the charge", home.get("_charge_root") == null)
	# The blast dips the whole screen into slow motion for half a second.
	check("and the screen dips into slow motion", Engine.time_scale < 1.0)
	Engine.time_scale = 1.0

	# --- A DRAG is a scroll, and stands the charge down ----------------------
	_press(strip, at, true)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(0, 90)
	drag.position = at + Vector2(0, 90)
	strip.gui_input.emit(drag)
	for _i in 120:
		await process_frame
	check("a drag never charges", home.get("_charge_root") == null)
	_press(strip, at + Vector2(0, 90), false)
	await process_frame
