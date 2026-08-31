extends AppScreen
## Gameplay — the conductor. Owns the SESSION: the rules, the board, the par,
## the clocks, the undo history, the save for Home's Continue card, and the
## modals (Pause, Run Over). It holds no rules (core/slide), no search
## (SlideSolver) and no drawing (BoardView, TileView, SlideHud).
## Every move travels one way:
##
##   finger → _on_cell_pressed → SlideRules.apply → events → BoardView.apply
##          → _after_move → Progression / the world
##
## Every mode reports play through Progression, and nothing else.
##
## THE OPPONENT IS THE PAR. A sliding puzzle has nobody on the other side of the
## board, so the board sets the terms: every scramble is dealt with a par taken
## off its own tile distance, and the run is graded on how far under it you came
## home. See core/slide/pace.gd. That grade is what the shell banks, what the
## streak counts and what the economy pays for.

const SAVE_SECTION := "current_game"
## The pack ids the helplines spend from. Each one is a key of
## EconomyRules.BUNDLES: `Wallet.use_consumable` takes a held one before it
## charges coins, so a pack bought in the Shop is spent here.
const BUNDLE_UNDO := "undo"
const BUNDLE_HINT := "hint"
## Gem upgrades that widen a free budget. `core/` may not reach an autoload, so
## EconomyRules holds the price and Entitlements the base, and the levels the
## player actually bought are added HERE, at the only place that spends them.
const UPGRADE_EXTRA_UNDO := "extra_undo"
const UPGRADE_EXTRA_HINT := "extra_hint"
## How long the helpline's ring stays on the tile it is pointing at.
const HINT_HOLD := 3.2
## The coin beside a helpline's price.
const COIN_PX := 40
## How long the solve sits on screen before the run-over card opens.
const SOLVE_HOLD := 1.15

# --- Session ------------------------------------------------------------------
var _mode: GameModes.Mode
var _rules: SlideRules
var _board: SlideBoard
var _par := 0
var _elapsed := 0.0
var _clock := 0.0              # Rush: seconds left
var _clock_total := 0.0
var _cleared := 0              # Rush: boards cleared this run
var _history: Array = []       # board dicts before each of your moves (undo)
var _undos_used := 0
var _paid_undos := 0
var _used_undo := false
var _hints_used := 0
var _assisted := false         # the solver closed a board out for you
var _paused := false
var _ended := false
var _blocked := false
var _payload_read := false
var _continue := false
var _daily := false
var _resumed_state: Dictionary = {}
var _theme_locked := false
var _seed := 0
var _size := 4

# --- Nodes --------------------------------------------------------------------
var _fx: BoardFx
var _wave: ShockWave
var _hud: SlideHud
var _view: BoardView
var _view_holder: Control
var _undo_btn: PremiumButton
var _hint_btn: PremiumButton
var _modal: ModalOverlay
var _subtitle: Label
var _rule_line: Label
var _size_row: Control

func has_own_fx() -> bool:
	return true

# =============================================================================
# Build
# =============================================================================
func build_content(root: VBoxContainer) -> void:
	root.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	if not _payload_read:
		_payload_read = true
		_read_payload()
	if _blocked:
		return
	if _fx == null:
		_fx = BoardFx.new()
		_fx.modulate.a = _living_fx_alpha()
		place_in_backdrop(_fx)
	_build_top_bar(root)
	_hud = SlideHud.new()
	_hud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(UI.constrain_width(_hud))
	# THE BOARD SITS IN THE MIDDLE. The slack is split above and below the board
	# rather than all collecting under it, so the tray and the cube both land on
	# the page's centre line instead of hanging off the HUD. The two spacers are
	# the whole mechanism: both expand, so they share what is left after the
	# fixed rows and the board have taken theirs.
	root.add_child(UI.spacer())
	if _mode.has_size_choice() and not _daily:
		_size_row = _build_size_row()
		root.add_child(UI.constrain_width(_size_row))
	_build_board(root)
	_build_controls(root)
	root.add_child(UI.spacer())
	if _wave == null:
		_wave = ShockWave.new()
		_wave.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_wave)

func on_ready() -> void:
	if _blocked:
		SceneRouter.goto(SceneRouter.Route["PREMIUM"], {}, true)
		return
	_apply_mode_atmosphere()
	_begin_board()
	set_process(true)

func _exit_tree() -> void:
	if _theme_locked:
		ThemeManager._apply(SettingsManager.theme_id())

## THE BOARD IS NOT TORN DOWN BY A THEME CHANGE.
##
## AppScreen answers a new palette by rebuilding its whole content, which is
## right on every screen whose content is a description of some state. This one
## IS the state: `build_content` makes a fresh, empty tray and only `on_ready`
## deals a board into it, so the inherited behaviour swapped a run in progress
## for an empty grid the moment the player changed world. The backdrop still
## repaints on the signal frame, exactly as the base does; everything else here
## restyles in place, because every painter on this screen reads the palette at
## draw time rather than baking it in.
func _on_theme_changed(_palette: Dictionary) -> void:
	_paint_background()
	if is_instance_valid(_hud):
		_hud._restyle()
	if is_instance_valid(_view):
		_view.queue_redraw()
	if _rule_line != null and is_instance_valid(_rule_line):
		_rule_line.add_theme_color_override("font_color", ThemeManager.color("text"))
	if _subtitle != null and is_instance_valid(_subtitle):
		_subtitle.add_theme_color_override("font_color", ThemeManager.color("text_faint"))

## The back chip and the system back gesture are the same door.
func _on_back_pressed() -> void:
	if not on_back():
		SceneRouter.back()

## The screen keeps no bottom bar: a board is a place you leave deliberately.
func on_back() -> bool:
	if _modal != null:
		_close_modal()
		return true
	if _ended:
		return false
	_open_pause()
	return true

# --- Payload and session --------------------------------------------------------
func _read_payload() -> void:
	var payload := SceneRouter.take_payload()
	var wanted := String(payload.get("mode", "classic"))
	var mode_id := wanted if GameModes.has_mode(wanted) else "classic"
	_continue = bool(payload.get("continue", false))
	_daily = bool(payload.get("daily", false))
	_mode = GameModes.get_mode(mode_id)
	_apply_size(payload)
	if not EntitlementManager.is_mode_unlocked(mode_id):
		_blocked = true
		return
	_rules = SlideRules.make(_mode)
	# THE DAILY IS ONE BOARD FOR EVERYONE. Its seed is the date, so every phone
	# that opens it today scrambles the same tray. Every other run is dealt from
	# the clock, so no two are alike.
	_seed = GameModes.today_seed() if _daily else (int(Time.get_unix_time_from_system()) ^ randi())
	if _continue:
		var sec := SaveManager.get_section(SAVE_SECTION, {})
		var saved: Dictionary = sec.get(mode_id, {})
		if saved.has("state"):
			_resumed_state = saved
		else:
			_continue = false
	if not _continue:
		Progression.begin_run(mode_id)

## The tray is as big as the player last left it, for the one mode that offers a
## choice. GameModes hands back a fresh Mode every call, so writing the chosen
## size onto it here reaches the rules and the view without either of them
## having to know a setting exists: `core/` may not read an autoload.
func _apply_size(payload: Dictionary) -> void:
	if _mode == null:
		return
	if _daily:
		_size = GameModes.DAILY_SIZE
	elif _mode.has_size_choice():
		var want := int(payload.get("size", 0))
		if want <= 0:
			want = int(SettingsManager.get_value("slide_size"))
		_size = clampi(want, _mode.sizes[0], _mode.sizes[_mode.sizes.size() - 1])
	else:
		_size = _mode.board_size
	_mode.board_size = _size

## A mode with its own world (Blind's fog, the Cube's star atlas) wears it for
## the session and hands the player's theme back on exit.
func _apply_mode_atmosphere() -> void:
	if _mode.theme_id.is_empty() or _mode.theme_id == SettingsManager.theme_id():
		return
	_theme_locked = true
	ThemeManager._apply(_mode.theme_id)

# --- Layout ---------------------------------------------------------------------
func _build_top_bar(root: VBoxContainer) -> void:
	var bar := UI.hbox(DesignSystem.SPACE_MD)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# BACK, not pause. A pause glyph promises a paused clock, and only Rush has
	# one; on every other board the button's real job is "let me out", and the
	# sheet it opens is where Resume, a fresh board and the solver live. Leaving
	# mid-run is safe either way: _save_session keeps the board for Home's
	# Continue card.
	bar.add_child(UI.circle_button("back", "", _on_back_pressed, 96.0))
	var titles := UI.vbox(0.0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := UI.title("Daily Slide" if _daily else _mode.title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titles.add_child(title)
	# THE RULE, in the mode's own words. Six modes that all deal numbered tiles
	# differ by their RULE, and the rule is the one thing the board cannot show
	# by itself.
	_rule_line = UI.caption(_mode.tagline, "text")
	_rule_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rule_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_rule_line)
	# The shape of the board, which the board itself mostly says: faint, and
	# under the rule rather than in place of it.
	_subtitle = UI.caption(_mode.board_caption(_size), "text_faint")
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titles.add_child(_subtitle)
	bar.add_child(titles)
	var restart := UI.circle_button("restart", "", _confirm_restart, 96.0)
	bar.add_child(restart)
	root.add_child(UI.constrain_width(bar))

func _build_board(root: VBoxContainer) -> void:
	_view_holder = Control.new()
	_view_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view = BoardView.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.cell_pressed.connect(_on_cell_pressed)
	_view.swiped.connect(_on_swiped)
	_view.pivot_pressed.connect(_on_pivot_pressed)
	_view_holder.add_child(_view)
	# The tray is square and takes what the page can spare, so the board is the
	# biggest thing on screen at every phone height.
	_view_holder.custom_minimum_size.y = _board_box()
	root.add_child(UI.constrain_width(_view_holder))

## The side of the board's box, in design points. Wide enough to fill the page
## and short enough that the HUD and the controls still fit above and below it.
func _board_box() -> float:
	var vp := get_viewport_rect().size
	return clampf(minf(vp.x * 0.92, vp.y * 0.46), 320.0, 980.0)

func _build_controls(root: VBoxContainer) -> void:
	var row := UI.hbox(DesignSystem.SPACE_MD)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_undo_btn = PremiumButton.new()
	_undo_btn.variant = PremiumButton.Variant.GLASS
	_undo_btn.pressed.connect(_on_undo)
	_hint_btn = PremiumButton.new()
	_hint_btn.variant = PremiumButton.Variant.GLASS
	_hint_btn.pressed.connect(_on_hint)
	if _mode.allow_undo:
		row.add_child(_undo_btn)
	row.add_child(_hint_btn)
	root.add_child(UI.constrain_width(row))
	_refresh_pills()

## The tray picker, for the one mode that offers a choice.
func _build_size_row() -> Control:
	var row := UI.hbox(DesignSystem.SPACE_SM)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for n in _mode.sizes:
		var b := PremiumButton.new()
		b.text = "%d×%d" % [n, n]
		b.variant = PremiumButton.Variant.PRIMARY if n == _size else PremiumButton.Variant.GHOST
		b.pressed.connect(_pick_size.bind(n))
		row.add_child(b)
	return row

func _pick_size(n: int) -> void:
	if n == _size or _modal != null:
		return
	if _board != null and _board.moves > 0 and not _ended:
		var m := ModalOverlay.new()
		m.compact = true
		m.set_header("BOARD", "Switch to %d×%d?" % [n, n], "This board goes away.")
		m.add_action("Switch", PremiumButton.Variant.PRIMARY, func() -> void:
			_close_modal()
			_switch_size(n))
		m.add_action("Keep playing", PremiumButton.Variant.GHOST, _close_modal)
		_modal = m
		m.open(self)
		return
	_switch_size(n)

func _switch_size(n: int) -> void:
	SettingsManager.set_value("slide_size", n)
	_clear_session()
	SceneRouter.goto(SceneRouter.Route["GAMEPLAY"],
		{"mode": _mode.id, "continue": false, "size": n}, true)

# =============================================================================
# The board
# =============================================================================
func _begin_board() -> void:
	if not _resumed_state.is_empty():
		_restore(_resumed_state)
		return
	_board = _rules.new_board()
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	if _rules is RulesSprint:
		(_rules as RulesSprint).seed_rng(_seed)
	_rules.scramble(_board, rng, _rules.scramble_steps())
	_par = Pace.par_for(_board)
	_history.clear()
	_elapsed = 0.0
	_clock_total = _mode.time_limit if _mode.has_timer else 0.0
	_clock = _clock_total
	_cleared = 0
	_view.setup(_board.w, _board.h)
	_view.deal_in(_board)
	_hud.begin(_mode, _par)
	_refresh_board_state()
	_save_session()

func _restore(saved: Dictionary) -> void:
	_board = SlideBoard.from_dict(saved.get("state", {}))
	_board.set_adjacency(_rules.new_board()._adj)
	_rules.sync(_board)
	_par = int(saved.get("par", Pace.par_for(_board)))
	_elapsed = float(saved.get("elapsed", 0.0))
	_clock_total = _mode.time_limit if _mode.has_timer else 0.0
	_clock = float(saved.get("clock", _clock_total))
	_cleared = int(saved.get("cleared", 0))
	_used_undo = bool(saved.get("used_undo", false))
	_hints_used = int(saved.get("hints", 0))
	_size = _board.w
	if _rules is RulesSprint:
		var sr := _rules as RulesSprint
		sr.seed_rng(_seed)
		sr.cleared = _cleared
	_view.setup(_board.w, _board.h)
	_view.sync_board(_board)
	_hud.begin(_mode, _par)
	_refresh_board_state()

## Pushes the rule's per-board state into the view, and the board's into the HUD.
## Called after every move, undo and re-deal, so nothing on screen can drift
## from the position.
func _refresh_board_state() -> void:
	if _board == null or _view == null:
		return
	if _mode.blind:
		_view.set_visible_cells(_rules.visible_cells(_board))
	if _rules is RulesLock:
		var lr := _rules as RulesLock
		_view.set_locked(RulesLock.locked_cells(_board))
		_view.set_live_group(lr.live_group(_board))
	_view.mark_home(_board)
	_hud.set_moves(_board.moves)
	if _mode.has_timer:
		_hud.set_clock(_clock, _clock_total)
		_hud.set_cleared(_cleared)
	else:
		_hud.set_progress(_board.placed(), _board.tile_count())
	_refresh_pills()

# =============================================================================
# Input
# =============================================================================
func _on_cell_pressed(index: int) -> void:
	_play(SlideRules.tap(index))

func _on_swiped(dir: int, _cell: int) -> void:
	# Twist has no swipe: a drag across a full tray is a scroll, and the tray
	# never emits one. Every other rule reads it as a slide.
	if not _mode.no_blank:
		_play(SlideRules.swipe(dir))

## Twist: the four tiles round the junction the finger landed on.
func _on_pivot_pressed(pivot: int) -> void:
	_play({"pivot": pivot})

func _play(move: Dictionary) -> void:
	if _paused or _ended or _board == null or _view.is_busy():
		return
	if not _rules.is_legal(_board, move):
		# A move the rule refuses still gets an answer, so a tap is never a
		# silent nothing: the rule says why (a weld) or the tray shrugs.
		var events := _rules.apply(_board, move)
		if not events.is_empty():
			_view.apply(events)
		return
	_history.append({"state": _board.to_dict(), "par": _par})
	if _history.size() > 120:
		_history.pop_front()
	_view.set_hint(-1)
	var events := _rules.apply(_board, move)
	if events.is_empty():
		_history.pop_back()
		return
	Progression.record_turn()
	if is_instance_valid(_fx):
		_fx.on_swipe(Vector2.ZERO)
	Haptics.light()
	_view.apply(events, _after_move.bind(events))

func _after_move(events: Array) -> void:
	_refresh_board_state()
	for e_v in events:
		var e: Dictionary = e_v
		match String(e.get("type", "")):
			"cleared":
				_on_board_cleared(e)
			"solved":
				_on_solved()
				return
	_save_session()

# =============================================================================
# Solving
# =============================================================================
func _on_solved() -> void:
	_ended = true
	_clear_session()
	var grade := Pace.grade(_board.moves, _par, _assisted)
	var score := EconomyRules.series_score(1, true, grade)
	# THE ONE REPORT: the funnel banks the score, writes the mode record,
	# unlocks the crowns and pays the coins. Nothing else on this screen earns.
	Progression.record_series(_mode.id, true, 1, 0, grade, _used_undo, _elapsed)
	Achievements.report_solve()
	_supernova()
	Confetti.celebrate(self, 160)
	AudioManager.play_sfx("victory")
	if is_instance_valid(_fx):
		_fx.celebrate()
	_view.celebrate()
	if is_instance_valid(_fx):
		var tw := _fx.create_tween()
		tw.tween_property(_fx, "modulate:a", 0.35, 0.6)
	var delay := create_tween()
	delay.tween_interval(SOLVE_HOLD)
	delay.tween_callback(_solve_modal.bind(grade, score))

## Rush: this board came out, the next one is already on the tray, and the clock
## just got paid. Nothing ends.
func _on_board_cleared(e: Dictionary) -> void:
	var paid := float(e.get("seconds", 0.0))
	_clock = minf(_clock_total, _clock + paid)
	# Banking the clear and dealing the next board are the CONDUCTOR's, once,
	# for the move the player really made. `apply` stays free of side effects so
	# the solver can search on it. See RulesSprint.bank_clear.
	if _rules is RulesSprint:
		var sr := _rules as RulesSprint
		_cleared = sr.bank_clear()
		sr.deal_next(_board)
	else:
		_cleared += 1
	_par = Pace.par_for(_board)
	_history.clear()
	Confetti.celebrate(self, 60)
	AudioManager.play_sfx("combo")
	Haptics.success()
	if is_instance_valid(_fx):
		_fx.on_merge(_view.cell_global(0) - global_position, _cleared)
	_view.deal_in(_board)
	_refresh_board_state()
	_flash_seconds(paid)
	_save_session()

## The seconds a cleared board paid, floating up off the clock.
func _flash_seconds(paid: float) -> void:
	if paid <= 0.0 or DesignSystem.reduce_motion():
		return
	var lbl := UI.numeral("+%d" % int(round(paid)), DesignSystem.TYPE_TITLE, "text")
	lbl.modulate = ThemeManager.color("accent")
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.position = Vector2(size.x * 0.5 - 60.0, size.y * 0.28)
	add_child(lbl)
	var t := lbl.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(lbl, "position:y", lbl.position.y - 90.0, 0.9)
	t.parallel().tween_property(lbl, "modulate:a", 0.0, 0.9)
	t.tween_callback(lbl.queue_free)

## Rush: the clock ran out. The run is over and the score is boards cleared.
func _on_time_up() -> void:
	_ended = true
	_clear_session()
	_view.interactive = false
	var grade := Pace.STEADY if _cleared > 0 else Pace.ASSISTED
	var score := _cleared * EconomyRules.ROUND_POINTS
	Progression.record_series(_mode.id, _cleared > 0, _cleared, 0, grade, _used_undo, _elapsed)
	if _cleared > 0:
		Achievements.report_solve()
		Confetti.celebrate(self, 120)
		AudioManager.play_sfx("victory")
	else:
		AudioManager.play_sfx("game_over")
		Haptics.warning()
	var delay := create_tween()
	delay.tween_interval(0.6)
	delay.tween_callback(_rush_modal.bind(score))

## The goal moment: time slows to a quarter under a white bloom, then lets go.
func _supernova() -> void:
	if DesignSystem.reduce_motion():
		return
	Engine.time_scale = 0.25
	get_tree().create_timer(0.55, true, false, true).timeout.connect(func() -> void:
		Engine.time_scale = 1.0)
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 1)
	flash.modulate.a = 0.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(flash)
	var tw := flash.create_tween().set_ignore_time_scale(true)
	tw.tween_property(flash, "modulate:a", 0.85, 0.08)
	tw.tween_property(flash, "modulate:a", 0.0, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(flash.queue_free)

func _solve_modal(grade: String, score: int) -> void:
	var m := ModalOverlay.new()
	m.set_header("SOLVED" if not _daily else "TODAY'S BOARD",
		Pace.title(grade), Pace.line(grade))
	m.add_stat_row("Moves", "%d  (par %d)" % [_board.moves, _par])
	m.add_stat_row("Time", _fmt_time(_elapsed))
	m.add_stat_row("Score", UI.commafy(score))
	var next_grade := Pace.next_up(grade)
	if not next_grade.is_empty() and not _assisted:
		m.add_stat_row(Pace.title(next_grade),
			"in %d moves" % Pace.threshold(next_grade, _par))
	m.add_action("Play again", PremiumButton.Variant.PRIMARY, func() -> void:
		_close_modal()
		Progression.present_pending_ad(self)
		SceneRouter.goto(SceneRouter.Route["GAMEPLAY"],
			{"mode": _mode.id, "continue": false, "size": _size}, true))
	m.add_action("Home", PremiumButton.Variant.GLASS, func() -> void:
		_close_modal()
		Progression.present_pending_ad(self)
		Progression.present_rewards(_mode.id, score, true, SceneRouter.Route["HOME"]))
	_modal = m
	m.open(self)

func _rush_modal(score: int) -> void:
	var m := ModalOverlay.new()
	m.set_header("TIME", "%d cleared" % _cleared,
		"The clock always wins. It is how far you got that counts.")
	m.add_stat_row("Boards", str(_cleared))
	m.add_stat_row("Best", str(maxi(_cleared, Progression.best_score(_mode.id) / maxi(1, EconomyRules.ROUND_POINTS))))
	m.add_stat_row("Score", UI.commafy(score))
	m.add_action("Run again", PremiumButton.Variant.PRIMARY, func() -> void:
		_close_modal()
		Progression.present_pending_ad(self)
		SceneRouter.goto(SceneRouter.Route["GAMEPLAY"], {"mode": _mode.id, "continue": false}, true))
	m.add_action("Home", PremiumButton.Variant.GLASS, func() -> void:
		_close_modal()
		Progression.present_pending_ad(self)
		Progression.present_rewards(_mode.id, score, _cleared > 0, SceneRouter.Route["HOME"]))
	_modal = m
	m.open(self)

# =============================================================================
# Clocks
# =============================================================================
func _process(delta: float) -> void:
	if _paused or _ended or _board == null:
		return
	_elapsed += delta
	if not _mode.has_timer:
		return
	_clock -= delta
	_hud.set_clock(_clock, _clock_total)
	if _clock <= 0.0:
		_clock = 0.0
		_on_time_up()

# =============================================================================
# Helplines
# =============================================================================
func _on_undo() -> void:
	if _history.is_empty() or _ended or _paused or _view.is_busy():
		return
	var unlimited := EntitlementManager.has_capability("unlimited_undo")
	if not unlimited and _undos_used >= _free_undos():
		var price := EconomyRules.undo_price(_paid_undos + 1)
		if not Wallet.use_consumable(BUNDLE_UNDO, price):
			_short_of_coins(price)
			return
		_paid_undos += 1
	_undos_used += 1
	_used_undo = true
	var snap: Dictionary = _history.pop_back()
	var adj := _board._adj
	_board = SlideBoard.from_dict(snap["state"])
	_board.set_adjacency(adj)
	_rules.sync(_board)
	Progression.record_undo()
	AudioManager.play_sfx("button_tap")
	Haptics.medium()
	_view.set_hint(-1)
	_view.sync_board(_board)
	_refresh_board_state()
	_save_session()

func _on_hint() -> void:
	if _ended or _paused or _view.is_busy() or _board == null:
		return
	if _hints_used >= _free_hints():
		if not Wallet.use_consumable(BUNDLE_HINT, EconomyRules.HINT_PRICE):
			_short_of_coins(EconomyRules.HINT_PRICE)
			return
	_hints_used += 1
	_refresh_pills()
	var mv := SlideSolver.hint(_board, _rules)
	var cell := int(mv.get("cell", -1))
	if cell < 0:
		# The torus has no tile to point at, so the hint plays the rotation for
		# you rather than gesturing at a row you would still have to find.
		if mv.has("axis"):
			_play(mv)
		return
	AudioManager.play_sfx("achievement", 0.02)
	Haptics.light()
	_view.set_hint(cell)
	var tw := create_tween()
	tw.tween_interval(HINT_HOLD)
	tw.tween_callback(func() -> void:
		if not _ended and is_instance_valid(_view):
			_view.set_hint(-1))

## The free budgets, widened by the gem upgrades the player bought.
func _free_undos() -> int:
	return Entitlements.free_undo_limit() + Wallet.upgrade_level(UPGRADE_EXTRA_UNDO)

func _free_hints() -> int:
	return EconomyRules.FREE_HINTS_PER_SERIES + Wallet.upgrade_level(UPGRADE_EXTRA_HINT)

func _refresh_pills() -> void:
	if _undo_btn != null and is_instance_valid(_undo_btn):
		var unlimited := EntitlementManager.has_capability("unlimited_undo")
		_helpline_pill(_undo_btn, "Undo", maxi(0, _free_undos() - _undos_used),
			EconomyRules.undo_price(_paid_undos + 1), unlimited)
		_undo_btn.disabled = _history.is_empty()
	if _hint_btn != null and is_instance_valid(_hint_btn):
		_helpline_pill(_hint_btn, "Hint", maxi(0, _free_hints() - _hints_used),
			EconomyRules.HINT_PRICE, false)

## A helpline pill in one of its three states: unlimited, N free left, or a COIN
## PRICE.
##
## The price wears a coin, and it has to. Both numbers used to render as
## "Hint · N" in the same slot in the same shape, so the moment the one free hint
## was spent the label flipped from a COUNT DOWN to a fixed PRICE and sat on
## "Hint · 30" for the rest of the run. Every player reads that as a counter that
## jumped to thirty and then broke.
func _helpline_pill(btn: PremiumButton, label: String, free_left: int,
		price: int, unlimited: bool) -> void:
	btn.icon = null
	if unlimited:
		btn.text = label
		return
	if free_left > 0:
		btn.text = "%s · %d" % [label, free_left]
		return
	btn.text = "%s  %d" % [label, price]
	btn.icon = IconLibrary.texture("currency_coins", COIN_PX, false)

func _short_of_coins(price: int) -> void:
	var m := ModalOverlay.new()
	m.compact = true
	m.set_header("COINS", "Not enough coins",
		"That costs %d. You have %d." % [price, Wallet.balance(WalletRules.COINS)])
	m.add_action("Okay", PremiumButton.Variant.PRIMARY, _close_modal)
	_modal = m
	m.open(self)

# =============================================================================
# Pause, restart, saving
# =============================================================================
func _open_pause() -> void:
	if _modal != null or _ended:
		return
	_paused = true
	_view.interactive = false
	var m := ModalOverlay.new()
	m.set_header("PAUSED", _mode.title, "%s\n%s" % [_fmt_time(_elapsed), _mode.challenge])
	m.add_action("Resume", PremiumButton.Variant.PRIMARY, func() -> void:
		_close_modal()
		_paused = false
		_view.interactive = true)
	m.add_action("New board", PremiumButton.Variant.GLASS, func() -> void:
		_close_modal()
		_paused = false
		_restart())
	# Solving it FOR you is a real action with a real cost: the board comes out,
	# it pays its coins, and the grade says Assisted for ever. Offered because a
	# player stuck on a 5x5 at midnight otherwise just closes the app.
	if not _mode.has_timer:
		m.add_action("Solve it for me", PremiumButton.Variant.GHOST, func() -> void:
			_close_modal()
			_paused = false
			_auto_solve())
	m.add_action("Home", PremiumButton.Variant.GHOST, func() -> void:
		_close_modal()
		_save_session()
		SceneRouter.goto(SceneRouter.Route["HOME"], {}, true))
	_modal = m
	m.open(self)

## Plays the solver's whole path out on the tray, one move at a time. The run is
## marked assisted, so it banks and it pays but it sets no record.
func _auto_solve() -> void:
	if _board == null or _ended:
		return
	var path := SlideSolver.solve(_board, _rules)
	if path.is_empty():
		var m := ModalOverlay.new()
		m.compact = true
		m.set_header("SOLVER", "This one is beyond me",
			"The board is too far from home to solve inside a moment.")
		m.add_action("Okay", PremiumButton.Variant.PRIMARY, _close_modal)
		_modal = m
		m.open(self)
		return
	_assisted = true
	_view.interactive = false
	_step_solution(path, 0)

func _step_solution(path: Array, k: int) -> void:
	if _ended or k >= path.size() or not is_instance_valid(_view):
		return
	var events := _rules.apply(_board, path[k])
	if events.is_empty():
		return
	_view.apply(events, func() -> void:
		_refresh_board_state()
		for e_v in events:
			if String((e_v as Dictionary).get("type", "")) == "solved":
				_on_solved()
				return
		_step_solution(path, k + 1))

func _confirm_restart() -> void:
	if _modal != null or _ended:
		return
	var m := ModalOverlay.new()
	m.compact = true
	m.set_header("NEW BOARD", "Deal a fresh scramble?", "This board goes away.")
	m.add_action("Deal", PremiumButton.Variant.DANGER, func() -> void:
		_close_modal()
		_restart())
	m.add_action("Keep playing", PremiumButton.Variant.GHOST, _close_modal)
	_modal = m
	m.open(self)

func _restart() -> void:
	_clear_session()
	SceneRouter.goto(SceneRouter.Route["GAMEPLAY"],
		{"mode": _mode.id, "continue": false, "size": _size}, true)

func _close_modal() -> void:
	if _modal != null and is_instance_valid(_modal):
		_modal.close()
	_modal = null

func _fmt_time(seconds: float) -> String:
	var total := int(maxf(0.0, seconds))
	@warning_ignore("integer_division")
	var mins := total / 60
	return "%d:%02d" % [mins, total % 60]

func _save_session() -> void:
	if _ended or _board == null:
		return
	var sec := SaveManager.get_section(SAVE_SECTION, {})
	var cells: Array = []
	for i in _board.size():
		cells.append(_board.at(i))
	sec[_mode.id] = {
		"saved_at": int(Time.get_unix_time_from_system()),
		"score": _board.placed() * EconomyRules.ROUND_POINTS / maxi(1, _board.tile_count()),
		"board": {"n": _board.w, "cells": cells},
		"state": _board.to_dict(),
		"par": _par,
		"elapsed": _elapsed,
		"clock": _clock,
		"cleared": _cleared,
		"hints": _hints_used,
		"used_undo": _used_undo,
	}
	SaveManager.set_section(SAVE_SECTION, sec)

func _clear_session() -> void:
	var sec := SaveManager.get_section(SAVE_SECTION, {})
	if sec.has(_mode.id):
		sec.erase(_mode.id)
		SaveManager.set_section(SAVE_SECTION, sec)
