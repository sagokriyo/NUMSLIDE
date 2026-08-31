extends AppScreen
## How to Play: the Academy. Six hands-on lessons on a live tray, one per mode,
## then the roster of every board in the game.
##
## Every lesson is the REAL game in miniature: the mode's own rule plug-in
## (SlideRules.make), the real BoardView, and one thing the player must DO.
## The screen hosts its own small driver (finger -> SlideRules.apply -> events
## -> BoardView.apply -> _after_move) and never touches Progression, the wallet
## or the session save: a lesson is not play, and nothing here costs a coin.
##
## THE GOAL IS ALWAYS THE SAME: SOLVE THE BOARD. That is not a shortcut, it is
## the honest shape of this game. A sliding puzzle has one win condition, and a
## lesson that asked for something else ("now slide tile 3 left") would teach a
## gesture rather than a rule. Instead each lesson deals a board a handful of
## moves from home under ITS OWN rule, so finishing it is the only way to meet
## the rule, and meeting the rule is the lesson. Blind's numbers really do go
## out; Lockdown really does weld the row shut behind you.
##
## THE DEAL IS A WALK, NOT AN ARRANGEMENT. A lesson names the tiles to slide,
## in order, starting from the solved board. So a dealt position is reachable by
## construction, cannot be unsolvable, and reads in the source as "three moves
## from home" rather than as a grid of numbers nobody can verify.
##
## Forward movement is EARNED. The forward arrow is absent until the board comes
## out, then lights as a breathing success medallion; the page never turns
## itself. A subtle back chevron (never on the first lesson) and the dot rail
## walk back through lessons already reached; dots past the furthest earned
## lesson stay locked.
##
## Progress persists in the "academy" save section as a list of LESSON IDS (the
## mode id), never array positions, so a lesson inserted in the middle can never
## re-mark its neighbours as earned.
##
## THE CONTRACT: LESSONS covers EVERY mode in GameModes.all(), the launch tier
## first and in catalogue order, and the roster lists every mode on one page,
## built from the catalogue at runtime.
## regression/headless/suites/test_academy_catalog.gd fails when a mode is added
## to the game and not to the academy. "Reachable behind a tour arrow" does not
## count.

const SAVE_SECTION := "academy"
const ROSTER_ID := "roster"
## A finished board stays on view this long before the medallion lights.
const EARN_HOLD := 0.55
## The earned page-turn: a quick fade out, then the next lesson blooms in.
const FLOW_FADE_OUT := 0.24
## The tray's height on the page.
const TRAY_PX := 520.0

## The lessons, in teaching order: the launch tier, then wave two, then wave
## three, as the catalogue lists them. `id` is the mode id and the STABLE key
## progress is saved under. The coach opens with the mode's own `lesson` from
## GameModes unless `intro` says otherwise; `goal` is what the player must DO;
## `done` is the line the coach says once it is earned.
##
## `size` is the tray the lesson deals (small: a lesson is a minute, not a
## sitting). `deal` is the tiles to slide from the SOLVED board, in order, named
## by the CELL each one is sitting in at the moment it is slid. Twist has no
## tiles to slide, so it names JUNCTIONS to turn instead, each wrapped in its own
## array: [[0], [3]] turns junction 0 then junction 3.
const LESSONS := [
	{"id": "classic", "size": 3,
		"deal": [7, 8, 5, 4, 3, 6],
		"goal": "Put the numbers back in order.",
		"done": "That is the whole game. Every other board is this one with a rule on it."},
	{"id": "sprint", "size": 3,
		"deal": [7, 8, 5],
		"goal": "Clear the board and watch the clock.",
		"intro": "Rush does not stop when you solve it. It pays you and deals another.",
		"done": "Every board you clear buys seconds. The run ends when the clock does."},
	{"id": "lock", "size": 3,
		"deal": [7, 6, 3, 4, 5, 8],
		"goal": "Solve it. Watch the tiles weld as they land.",
		"intro": "A tile that reaches home here is welded down and never moves again.",
		"done": "The lit cells are the ones you may finish next. Take them out of order and you cannot."},
	{"id": "twist", "size": 3,
		"deal": [[0], [3]],
		"goal": "Turn the tiles back into order.",
		"intro": "No hole on this tray. Tap a corner where four tiles meet and they pinwheel.",
		"done": "Every turn fixes one tile and spins three others. That is the whole mode."},
	{"id": "fog", "size": 3,
		"deal": [7, 8, 5, 4],
		"goal": "Solve it once the numbers go out.",
		"intro": "Look at the board now. From your first slide, only the tiles touching the hole show.",
		"done": "A tile that gets home stays lit. That island is the only map you get."},
]

# --- State ----------------------------------------------------------------------
var _page := 0
var _earned: Array[String] = []
var _mode: GameModes.Mode
var _rules: SlideRules
var _board: SlideBoard
var _view: BoardView
var _tray_holder: Control
var _coach: Label
var _goal_lbl: Label
var _forward: Control
var _back_chevron: Control
var _dots: HBoxContainer
var _lesson_done := false

func nav_tab() -> String:
	return ""

func has_own_fx() -> bool:
	return false

# =============================================================================
# The catalogue contract
# =============================================================================
## Pages, lessons plus the roster. Static: it reads the catalogue const alone,
## and the suite asks the SCRIPT this rather than having to stand a screen up.
static func page_count() -> int:
	return LESSONS.size() + 1

## The page index of a lesson id, or -1. The roster is the final page. Static,
## for the same reason page_count is.
static func page_of_id(id: String) -> int:
	if id == ROSTER_ID:
		return LESSONS.size()
	for i in LESSONS.size():
		if String(LESSONS[i]["id"]) == id:
			return i
	return -1

## Opens a page by id. The probe's entry point.
func probe_show_page(page: String) -> void:
	var idx := page_of_id(page)
	if idx < 0 and page.is_valid_int():
		idx = int(page)
	if idx < 0 or idx >= page_count():
		return
	_page = idx
	_rebuild_content()

# =============================================================================
# Build
# =============================================================================
func on_ready() -> void:
	_load_progress()

func build_content(root: VBoxContainer) -> void:
	root.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	root.add_child(nav_header("How to Play"))
	if _page >= LESSONS.size():
		_build_roster(root)
		return
	_build_lesson(root)

# --- The roster -------------------------------------------------------------------
func _build_roster(root: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.clip_contents = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	SmoothWheel.attach(scroll)
	root.add_child(scroll)

	var col := UI.vbox(DesignSystem.SPACE_MD)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(UI.constrain_width(col))
	col.add_child(UI.eyebrow("EVERY BOARD"))
	# Built from the CATALOGUE, never a second hand-written list: a mode added to
	# the game is on this page the moment it exists.
	for mode in GameModes.all():
		col.add_child(_roster_row(mode))
	col.add_child(UI.spacer(DesignSystem.SPACE_LG, false))
	col.add_child(_rail())

func _roster_row(mode: GameModes.Mode) -> Control:
	var card := UI.tappable(func() -> void:
		var idx := page_of_id(mode.id)
		if idx >= 0:
			_go_to(idx), 1)
	var row := UI.hbox(DesignSystem.SPACE_MD)
	if not mode.icon_path.is_empty() and UI.icon_tex(mode.icon_path) != null:
		var tint := "" if IconLibrary.has_icon(mode.icon_path) else "accent"
		var icon := UI.icon_rect(mode.icon_path, 110, tint)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.custom_minimum_size.x = 124
		row.add_child(icon)
	var col := UI.vbox(DesignSystem.SPACE_XS)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UI.label(mode.title, 50, "text"))
	col.add_child(UI.caption(mode.tagline, "text_dim"))
	col.add_child(UI.caption(mode.board_caption(), "text_faint"))
	row.add_child(col)
	card.add_child(row)
	return card

# --- One lesson -------------------------------------------------------------------
func _build_lesson(root: VBoxContainer) -> void:
	var lesson: Dictionary = LESSONS[_page]
	_mode = GameModes.get_mode(String(lesson["id"]))
	_mode.board_size = int(lesson.get("size", 3))
	_rules = SlideRules.make(_mode)
	_lesson_done = false

	var head := UI.vbox(DesignSystem.SPACE_XS)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UI.title(_mode.title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(title)
	_coach = UI.body(String(lesson.get("intro", _mode.lesson)), "text")
	_coach.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coach.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_coach)
	root.add_child(UI.constrain_width(head))

	root.add_child(UI.spacer())
	_build_tray(root)
	root.add_child(UI.spacer())

	_goal_lbl = UI.caption(String(lesson["goal"]), "accent")
	_goal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goal_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(UI.constrain_width(_goal_lbl))

	root.add_child(_controls())
	root.add_child(_rail())
	_deal(lesson)

func _build_tray(root: VBoxContainer) -> void:
	_tray_holder = Control.new()
	_tray_holder.custom_minimum_size.y = TRAY_PX
	_tray_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view = BoardView.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.cell_pressed.connect(_on_cell_pressed)
	_view.swiped.connect(_on_swiped)
	_tray_holder.add_child(_view)
	root.add_child(UI.constrain_width(_tray_holder))

## Deals the lesson's position by walking the named moves out of the solved
## board. Reachable by construction, so no lesson can open on a dead tray.
func _deal(lesson: Dictionary) -> void:
	_board = _rules.new_board()
	for step_v in lesson.get("deal", []):
		if step_v is Array:
			# A junction to turn: [pivot] clockwise, or [pivot, false] the other way.
			var turn: Array = step_v
			if not turn.is_empty():
				_board.rotate_block(int(turn[0]), bool(turn[1]) if turn.size() > 1 else true)
		else:
			var cell := int(step_v)
			for nb in _board.neighbours(cell):
				if _board.at(nb) == SlideBoard.BLANK:
					_board.slide(cell, nb)
					break
	_board.moves = 0
	_rules.sync(_board)
	_view.setup(_board.w, _board.h)
	_view.deal_in(_board)
	_refresh_state()

func _refresh_state() -> void:
	if _view == null or _board == null:
		return
	if _mode.blind:
		_view.set_visible_cells(_rules.visible_cells(_board))
	if _rules is RulesLock:
		var lr := _rules as RulesLock
		_view.set_locked(RulesLock.locked_cells(_board))
		_view.set_live_group(lr.live_group(_board))
	_view.mark_home(_board)

# --- The driver --------------------------------------------------------------------
func _on_cell_pressed(index: int) -> void:
	_play(SlideRules.tap(index))

func _on_swiped(dir: int, cell: int) -> void:
	if _mode.no_blank:
		_play({"dir": dir, "cell": cell})
	else:
		_play(SlideRules.swipe(dir))

func _play(move: Dictionary) -> void:
	if _lesson_done or _board == null or _view.is_busy():
		return
	var events := _rules.apply(_board, move)
	if events.is_empty():
		return
	Haptics.light()
	_view.apply(events, func() -> void:
		_refresh_state()
		for e_v in events:
			var kind := String((e_v as Dictionary).get("type", ""))
			# Rush re-deals rather than ending, so the lesson takes the FIRST
			# clear as the thing it was asking for and stops there.
			if kind == "solved" or kind == "cleared":
				_earn()
				return)

func _earn() -> void:
	if _lesson_done:
		return
	_lesson_done = true
	var lesson: Dictionary = LESSONS[_page]
	AudioManager.play_sfx("victory")
	Haptics.success()
	Confetti.celebrate(self, 90)
	_view.celebrate()
	_set_coach(String(lesson["done"]))
	_mark_earned(String(lesson["id"]))
	var t := create_tween()
	t.tween_interval(EARN_HOLD)
	t.tween_callback(_show_forward)

## Crossfades the coach line: the academy's entire voice is this one label.
func _set_coach(text: String) -> void:
	if _coach == null or not is_instance_valid(_coach):
		return
	if DesignSystem.reduce_motion():
		_coach.text = text
		return
	var t := _coach.create_tween()
	t.tween_property(_coach, "modulate:a", 0.0, DesignSystem.DUR_FAST)
	t.tween_callback(func() -> void: _coach.text = text)
	t.tween_property(_coach, "modulate:a", 1.0, DesignSystem.DUR_BASE)

# --- Chrome --------------------------------------------------------------------------
func _controls() -> Control:
	var row := UI.hbox(DesignSystem.SPACE_MD)
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	_back_chevron = UI.circle_button("back", "", func() -> void:
		_go_to(_page - 1), 96.0)
	_back_chevron.visible = _page > 0
	row.add_child(_back_chevron)

	var retry := PremiumButton.new()
	retry.text = "Deal again"
	retry.variant = PremiumButton.Variant.GHOST
	retry.pressed.connect(func() -> void:
		if not _lesson_done:
			_deal(LESSONS[_page]))
	row.add_child(retry)

	# The forward arrow is ABSENT until the board comes out. The page never
	# turns itself and it never offers to be skipped: the lesson is the doing.
	_forward = UI.circle_button("new_game", "", func() -> void:
		_go_to(_page + 1), 110.0)
	_forward.visible = false
	row.add_child(_forward)
	return UI.constrain_width(row)

func _show_forward() -> void:
	if _forward == null or not is_instance_valid(_forward):
		return
	_forward.visible = true
	if DesignSystem.reduce_motion():
		return
	var t := _forward.create_tween().set_loops()
	t.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(_forward, "modulate:a", 0.6, 0.8)
	t.tween_property(_forward, "modulate:a", 1.0, 0.8)

## The dot rail: one per page. Dots past the furthest earned lesson stay locked,
## so the rail is a map of what you have done rather than a menu.
func _rail() -> Control:
	_dots = UI.hbox(DesignSystem.SPACE_SM)
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	var reach := _furthest_reachable()
	for i in page_count():
		var dot := _Dot.new()
		dot.custom_minimum_size = Vector2(22, 22)
		dot.active = i == _page
		dot.locked = i > reach
		dot.hue = ThemeManager.color("accent")
		if not dot.locked:
			var target := i
			dot.gui_input.connect(func(e: InputEvent) -> void:
				var down: bool = e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed
				var click: bool = e is InputEventMouseButton and (e as InputEventMouseButton).pressed
				if down or click:
					_go_to(target))
			dot.mouse_filter = Control.MOUSE_FILTER_STOP
		_dots.add_child(dot)
	return UI.constrain_width(_dots)

## The furthest page the player may open: one past the last lesson earned, so
## the roster only opens once every board has been met.
func _furthest_reachable() -> int:
	var reach := 0
	for i in LESSONS.size():
		if _earned.has(String(LESSONS[i]["id"])):
			reach = maxi(reach, i + 1)
	return mini(reach, page_count() - 1)

func _go_to(page: int) -> void:
	if page < 0 or page >= page_count() or page == _page:
		return
	if page > _furthest_reachable():
		return
	_page = page
	if DesignSystem.reduce_motion():
		_rebuild_content()
		return
	var t := content.create_tween()
	t.tween_property(content, "modulate:a", 0.0, FLOW_FADE_OUT)
	t.tween_callback(func() -> void:
		_rebuild_content()
		content.modulate.a = 0.0
		var back := content.create_tween()
		back.tween_property(content, "modulate:a", 1.0, DesignSystem.DUR_BASE))

# --- Progress ------------------------------------------------------------------------
func _load_progress() -> void:
	var data := SaveManager.get_section(SAVE_SECTION, {})
	var raw: Array = data.get("done", [])
	_earned.clear()
	for v in raw:
		var id := String(v)
		if page_of_id(id) >= 0:
			_earned.append(id)
	# The academy reopens on the first lesson still to earn.
	_page = mini(_furthest_reachable(), LESSONS.size())

func _mark_earned(id: String) -> void:
	if _earned.has(id):
		return
	_earned.append(id)
	SaveManager.set_section_fields(SAVE_SECTION, {"done": _earned.duplicate()})

# --- One dot on the rail ----------------------------------------------------------
class _Dot extends Control:
	var active := false
	var locked := false
	var hue: Color = Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		if locked:
			draw_arc(c, r * 0.5, 0.0, TAU, 20, Color(1, 1, 1, 0.12), 2.0, true)
			return
		if active:
			draw_texture_rect(CandyFace.halo_tex(),
				Rect2(c - Vector2(r, r) * 2.0, Vector2(r, r) * 4.0), false,
				Color(hue.r, hue.g, hue.b, 0.35))
			draw_circle(c, r * 0.62, hue)
		else:
			draw_circle(c, r * 0.40, Color(1, 1, 1, 0.35))
