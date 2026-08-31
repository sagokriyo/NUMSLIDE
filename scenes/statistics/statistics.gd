extends AppScreen
## Statistics — premium layout: a 2-column icon-tile grid of the lifetime
## numbers, the per-mode series ledger, and a large full-width win-rate section
## with metallic donut + dot matrix.
##
## Everything here is in NUMSLIDE terms: a "game" is one finished BOARD
## (first to N rounds), rounds are the grind inside it, and mastery is series
## won against the mode's own ladder (GameModes.Mode.mastery_yardstick).
##
## THE NUMBERS ARRIVE, they are not simply printed. This page held every stat the
## game tracks and not one moving pixel: the donut set its ratio once, the dot
## matrix was painted at its final fill, and the cards appeared at once. A page
## that states a win rate reads as a spreadsheet; a page that *counts* to it
## reads as a record of what the player did, which is the only reason to keep
## these numbers on a screen of their own.
##
## REBUILD-SAFE, and that is what shapes the split below. `build_content` re-runs
## on every theme change while `on_ready` fires once, so everything here is BUILT
## at its final value and `_start_flourishes` (entry only) winds it back to zero
## and plays it forward. Build it at zero instead and a theme change leaves an
## empty ring and a row of zeroes on screen.

const CHIP_VIOLET  := [Color("9D8FFB"), Color("5E48E8")]

## The "empty / loss" fill — a light lavender on light themes (so it's visible
## on a white card), a faint white on dark themes.
func _muted_col() -> Color:
	var p := ThemeManager.palette()
	if bool(p.get("is_light", false)):
		return Color(CHIP_VIOLET[0]).lerp(Color.WHITE, 0.68)
	return Color(1, 1, 1, 0.14)

## How long the whole dot matrix takes to fill, however many win dots there are.
## A fixed per-dot delay reads fine at 4 dots and takes most of three seconds at
## 42, so the budget is what is constant and the step is what shrinks.
const DOTS_FILL_SECONDS := 0.62

# -------------------------------------------------------------------------

## The entrance's animation targets, all captured while `build_content` runs.
## Every one is freed and replaced by a theme rebuild, so nothing may hold a
## reference across one — `_start_flourishes` only ever runs on the build that
## `on_ready` follows.
var _ring: ProgressRing
var _pct_lbl: Label
## The dots standing for wins, in fill order. The loss dots never animate.
var _win_dots: Array[Panel] = []
## [{"label": Label, "target": int, "commas": bool}] — the cells that count up.
var _counters: Array[Dictionary] = []
## The top-level cards, in reading order, for the entrance cascade.
var _cards: Array[Control] = []

func on_ready() -> void:
	# Home's glass-shard identity behind the numbers — the stats live inside the
	# game's own world instead of floating on a bare gradient.
	add_glass_drift()
	# We own the entrance from here: the base class fades the whole content block
	# as one, which would run underneath the per-card cascade and read as two
	# fades of the same pixels.
	custom_entrance = true
	content.modulate.a = 0.0
	await get_tree().process_frame
	if not is_inside_tree():
		return
	content.modulate.a = 1.0
	_start_flourishes()

func nav_tab() -> String: return "stats"

## The entrance: the cards cascade, the numbers count up to themselves, the
## win-rate arc sweeps out of zero and the win dots light one after another.
##
## Everything here is a no-op under reduce_motion — `UI.stagger_in` returns
## early on its own, and each block below is guarded — which leaves the page in
## exactly the state `build_content` already put it in. That is the whole reason
## the build is authored at final values: the accessible path is "do nothing",
## not "run a second, quieter animation".
func _start_flourishes() -> void:
	if bool(SettingsManager.get_value("reduce_motion")):
		return
	UI.stagger_in(_cards)

	# Counters. Each waits for its own card's step in the cascade so the numbers
	# land in the same wave the cards arrive on, rather than all at once under a
	# page that is still assembling itself.
	var i := 0
	for entry: Dictionary in _counters:
		var lbl: Label = entry["label"]
		if not is_instance_valid(lbl):
			continue
		var target: int = int(entry["target"])
		var commas: bool = bool(entry["commas"])
		var t := lbl.create_tween()
		t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_interval(float(i) * 0.035)
		t.tween_method(func(v: float) -> void:
			if not is_instance_valid(lbl):
				return
			var n := int(round(v))
			lbl.text = UI.commafy(n) if commas else str(n),
			0.0, float(target), 0.7)
		i += 1

	# The win-rate arc, out of zero. Built at its real value (see the header), so
	# it is wound back here and played forward.
	if is_instance_valid(_ring):
		var target_ratio: float = _ring.value
		_ring.value = 0.0
		var rt := _ring.create_tween()
		rt.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		rt.tween_property(_ring, "value", target_ratio, DesignSystem.DUR_SLOW)
		# The percentage in the middle counts with the arc, not on its own clock —
		# a number that finishes ahead of the ring it labels reads as a glitch.
		if is_instance_valid(_pct_lbl):
			var pct := _pct_lbl
			var pt := pct.create_tween()
			pt.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			pt.tween_method(func(v: float) -> void:
				if is_instance_valid(pct):
					pct.text = "%d%%" % int(round(v * 100.0)),
				0.0, target_ratio, DesignSystem.DUR_SLOW)

	# The dot matrix, lighting up one dot at a time inside a fixed budget.
	if not _win_dots.is_empty():
		var step: float = DOTS_FILL_SECONDS / float(_win_dots.size())
		var d := 0
		for dot: Panel in _win_dots:
			if not is_instance_valid(dot):
				continue
			dot.modulate.a = 0.0
			var dt := dot.create_tween()
			dt.tween_property(dot, "modulate:a", 1.0, 0.18) \
				.set_delay(float(d) * step).set_ease(Tween.EASE_OUT)
			d += 1

func build_content(root: VBoxContainer) -> void:
	# Every registry below points at nodes this build is about to create, and a
	# theme change frees the previous set — so they are cleared here, not appended
	# to. Missing this leaves `_start_flourishes` holding freed Labels.
	_ring = null
	_pct_lbl = null
	_win_dots.clear()
	_counters.clear()
	_cards.clear()

	root.add_child(nav_header("Statistics"))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.clip_contents  = true
	scroll.follow_focus   = false
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	SmoothWheel.attach(scroll)   # desktop wheel glides instead of stepping
	root.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", int(DesignSystem.SPACE_MD))
	margin.add_theme_constant_override("margin_right", int(DesignSystem.SPACE_MD))
	margin.add_theme_constant_override("margin_bottom", int(DesignSystem.SPACE_2XL))
	scroll.add_child(margin)

	var col := UI.vbox(int(DesignSystem.SPACE_LG))
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(col)

	# The cascade runs over the two-column grid's CELLS, not over the grid as one
	# block: the grid is the bulk of the page, and fading it in as a single slab
	# is the entrance this screen already effectively had.
	var grid := _stats_grid()
	col.add_child(grid)
	for cell in grid.get_children():
		_cards.append(cell as Control)

	# Fresh players have no win-rate to show — invite them to play instead of
	# rendering a hollow 0% donut.
	var rate: Control
	if int(GameStats.get_stat("games_played")) > 0:
		rate = _win_rate_card()
	else:
		rate = _empty_state("No series yet",
			"Play a series and your stats show up here.")
	col.add_child(rate)
	_cards.append(rate)

	var modes := _by_mode_card()
	col.add_child(modes)
	_cards.append(modes)

	col.add_child(UI.spacer(DesignSystem.SPACE_LG, false))

## A friendly first-run card with an icon, a line of copy and a Play button.
func _empty_state(title_text: String, subtitle: String) -> Control:
	var card := UI.glass_card(2)
	var box := UI.vbox(int(DesignSystem.SPACE_MD))
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon := UI.icon_rect("games_played", 120.0, "")
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var t := UI.label(title_text, DesignSystem.TYPE_HEADLINE, "text", HORIZONTAL_ALIGNMENT_CENTER)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(t)
	var s := UI.body(subtitle)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(s)
	var cta := UI.tappable(func(): SceneRouter.goto(SceneRouter.Route["HOME"]), 2)
	var cta_row := UI.hbox(0)
	cta_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cta_row.add_child(UI.label("Play  →", DesignSystem.TYPE_BODY, "accent", HORIZONTAL_ALIGNMENT_CENTER))
	cta.add_child(cta_row)
	box.add_child(cta)
	card.add_child(box)
	return card

# --- 2-column stat grid -------------------------------------------------------

func _stats_grid() -> Control:
	var total_time := GameStats.format_duration(float(GameStats.get_stat("total_play_seconds")))
	var games := int(GameStats.get_stat("games_played"))
	var wins := int(GameStats.get_stat("games_won"))
	var rounds := int(GameStats.get_stat("rounds_won"))
	var streak := int(GameStats.get_stat("best_win_streak"))
	var days := int(GameStats.get_stat("current_streak_days"))
	# The best grade ever reached, by NAME: "Expert" says more on a card than a
	# rung number would, and the ladder is only four long.
	var pace_id := GameStats.best_grade_id()
	var rival := Pace.title(pace_id) if not pace_id.is_empty() else "None yet"

	# [icon_library_id, value, caption, count_to] — the premium gradient icon set
	# carries its own colours (gold / silver / glass), so no chip gradient behind it.
	#
	# `count_to` is the number the cell counts UP to on entry, or -1 for a cell
	# that simply states its value. Three kinds sit out deliberately: the
	# duration, which is a formatted string ("3m 20s") with no single number to
	# run through; the rival, which is a name; and WIN RATE, because the donut
	# lower down already animates exactly that figure and counting it twice on
	# one page reads as two different measurements.
	var defs: Array = [
		["games_played",    str(games),                                          "SERIES PLAYED",   games],
		["games_won",       str(wins),                                           "SERIES WON",      wins],
		["win_rate",        "%d%%" % int(round(GameStats.win_rate() * 100.0)),   "WIN RATE",        -1],
		["total_moves",     UI.commafy(rounds),                                  "ROUNDS WON",      rounds],
		["best_score",      str(streak),                                         "BEST WIN STREAK", streak],
		["rank_badge",      rival,                                               "BEST GRADE"   ,   -1],
		["day_streak",      str(days),                                           "DAY STREAK",      days],
		["total_play_time", total_time,                                          "TIME PLAYED",     -1],
	]

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", int(DesignSystem.SPACE_MD))
	grid.add_theme_constant_override("v_separation", int(DesignSystem.SPACE_MD))

	for d in defs:
		var cell := _stat_cell(String(d[0]), String(d[1]), String(d[2]), int(d[3]))
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
	return grid

## One stat tile. `count_to` >= 0 registers the value label to count up to that
## number on entry; -1 leaves it stating `value` and nothing else.
func _stat_cell(icon_id: String, value: String, caption: String,
		count_to: int = -1) -> Control:
	# The same frosted GlassPanel every other card on this screen wears — a flat
	# glass_box here read as a different material sitting next to the real panes.
	var card: GlassPanel = UI.glass_card(2)
	card.content_margin = 18.0
	card.custom_minimum_size = Vector2(0, 216)

	var row := UI.hbox(int(DesignSystem.SPACE_MD))
	row.alignment = BoxContainer.ALIGNMENT_BEGIN          # icon pinned to the left edge
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL    # fill card so children center

	var ico := UI.icon_rect(icon_id, 120.0, "")
	ico.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ico.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ico)

	var text_col := UI.vbox(6)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical   = Control.SIZE_SHRINK_CENTER

	# FitLabels, so the cell can neither be pushed past its half of the screen nor
	# eat the end of its own value. Clipping alone used to do the first job and
	# fail the second: a seven-figure count arrived as "1,234,5", and the reader
	# had no way to tell that the number they were reading was not the number
	# they had earned. The budget is the FINAL value, so the count-up below runs
	# through its digits at one settled size instead of breathing.
	#
	# A counting number also runs through every digit, which is why these wear the
	# tabular face UI.fit_numeral picks (see UI.tabular_display) — proportional
	# figures make a rolling number jitter as it passes them.
	var val_lbl := UI.fit_numeral(value, 58, "text", HORIZONTAL_ALIGNMENT_LEFT, value)
	val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_child(val_lbl)

	if count_to >= 0:
		# The separator style is READ OFF the finished text rather than decided
		# here, so the count can never format differently from the value it lands
		# on: "48" counts without a comma and "12,480" counts with one, whatever
		# the call site chose.
		_counters.append({
			"label":  val_lbl,
			"target": count_to,
			"commas": value.contains(","),
		})

	# "BEST WIN STREAK" is the longest caption in the grid and would lose its last
	# letters to a clip for the same reason the values did.
	var cap_lbl := UI.fit_label(caption, 38, "text_dim")
	cap_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_child(cap_lbl)

	row.add_child(text_col)
	card.add_child(row)
	return card

# --- By mode --------------------------------------------------------------------
## Every mode in the catalog, with its series record and how far along its
## mastery ladder the player is. Read straight off GameStats.mode_record (the
## section Progression.record_series writes), so a mode added to the catalog
## lists itself here with nothing on this screen edited.
##
## Every mode is listed, played or not: the unplayed ones are the invitation,
## and a list that only showed the boards already tried would hide the other
## fifteen from exactly the player who has not found them yet.

## The widest the right-hand "3 / 10" may claim before it shrinks its own type
## instead of the row. With the icon and the chevron fixed, this is what keeps
## the mode's name a readable share of the card.
const MASTERY_SLOT := 170.0

func _by_mode_card() -> Control:
	var card := UI.glass_card(2)
	var box := UI.vbox(int(DesignSystem.SPACE_MD))
	box.add_child(UI.eyebrow("By Mode"))
	var first := true
	for mode: GameModes.Mode in GameModes.all():
		if not first:
			box.add_child(UI.hairline(0.1))
		first = false
		box.add_child(_mode_row(mode))
	card.add_child(box)
	return card

## One mode's line: its icon, its name, series played and won, and the mastery
## bar. A mastered mode wears a gold mark instead of a bar — a rail of full bars
## says nothing. Tapping the row starts a series on that board.
func _mode_row(mode: GameModes.Mode) -> Control:
	var rec := GameStats.mode_record(mode.id)
	var played := int(rec.get("series_played", 0))
	var won := int(rec.get("series_won", 0))
	var yard: int = mode.mastery_yardstick()
	var mastered := yard > 0 and won >= yard

	var row := UI.hbox(int(DesignSystem.SPACE_MD))
	row.custom_minimum_size = Vector2(0, 88)
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	# The mode's own mark, in its native colours; the catalog glyph when a mode
	# has no icon art yet (a fallback, never a blank).
	if not mode.icon_path.is_empty() and UI.icon_tex(mode.icon_path) != null:
		var tint := "" if IconLibrary.has_icon(mode.icon_path) else "accent"
		var icon := UI.icon_rect(mode.icon_path, 72, tint)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	else:
		var glyph := UI.label(mode.icon, 44, "accent", HORIZONTAL_ALIGNMENT_CENTER)
		glyph.custom_minimum_size = Vector2(72, 72)
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(glyph)

	var col := UI.vbox(int(DesignSystem.SPACE_XS))
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var head := UI.hbox(int(DesignSystem.SPACE_SM))
	var name_lbl := UI.fit_label(mode.title, 40, "text" if played > 0 else "text_dim")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ThemeManager.display_font:
		name_lbl.add_theme_font_override("font", ThemeManager.display_font)
	head.add_child(name_lbl)
	var mark_text := "MASTERED" if mastered else "%d / %d" % [won, yard]
	var mark := UI.fit_numeral(mark_text, 34, "gold" if mastered else "text_dim",
		HORIZONTAL_ALIGNMENT_RIGHT, mark_text)
	mark.max_width = MASTERY_SLOT
	head.add_child(mark)
	col.add_child(head)

	if not mastered:
		var ratio := 0.0 if yard <= 0 else clampf(float(won) / float(yard), 0.0, 1.0)
		var bar := UI.progress(ratio, "accent")
		bar.custom_minimum_size = Vector2(0, 8)
		col.add_child(bar)

	var detail := "Not played yet" if played <= 0 \
		else "%d played  ·  %d won" % [played, won]
	var d := UI.fit_label(detail, 32, "text_faint")
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(d)
	row.add_child(col)

	if played <= 0:
		row.modulate.a = 0.72
	UI.make_scroll_tappable(row, func(): _play(mode.id))
	return row

## Starts a series on `mode_id`, through the SAME gate Home's launcher uses: a
## locked board sends the player to the paywall rather than into a game they
## have not bought.
func _play(mode_id: String) -> void:
	if not EntitlementManager.is_mode_unlocked(mode_id):
		SceneRouter.goto(SceneRouter.Route["PREMIUM"])
		return
	SceneRouter.goto(SceneRouter.Route["GAMEPLAY"], {"mode": mode_id, "continue": false})

# --- Win Rate card (donut left, dot-matrix right — matches reference) ----------

func _win_rate_card() -> Control:
	var card := UI.glass_card(2)
	var outer := UI.vbox(int(DesignSystem.SPACE_LG))

	outer.add_child(UI.eyebrow("Win Rate"))

	# Donut (left) + dot matrix (right), side by side.
	var body := UI.hbox(int(DesignSystem.SPACE_LG))
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_donut_widget())

	var dots := _dot_matrix()
	dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dots.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	body.add_child(dots)
	outer.add_child(body)

	# Legend below, spanning the card.
	outer.add_child(_dot_legend())

	card.add_child(outer)
	return card

func _donut_widget() -> Control:
	const SZ := 208.0
	var holder := Control.new()
	holder.custom_minimum_size  = Vector2(SZ, SZ)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.size_flags_vertical   = Control.SIZE_SHRINK_CENTER

	# The app's shared ring rather than a donut of this screen's own: same track +
	# arc + rounded caps, but `value` has a repainting setter, which is what lets
	# the sweep below exist at all. The local class it replaced held its ratio in
	# a plain var, so the only way to show a win rate was to draw it already there.
	var ring := ProgressRing.new()
	ring.value        = GameStats.win_rate()
	ring.color_a      = Color(CHIP_VIOLET[0])
	ring.color_b      = Color(CHIP_VIOLET[1])
	ring.track_color  = _muted_col()
	ring.thickness    = 24.0
	ring.rounded_caps = true
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(ring)
	_ring = ring

	var center := UI.vbox(2)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var pct_lbl := UI.label(
		"%d%%" % int(round(GameStats.win_rate() * 100.0)), 56, "text",
		HORIZONTAL_ALIGNMENT_CENTER)
	pct_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	# Tabular figures: the number is centred inside a fixed ring and counts through
	# every digit on the way up, so proportional glyphs make it visibly breathe.
	if UI.tabular_display():
		pct_lbl.add_theme_font_override("font", UI.tabular_display())
	elif ThemeManager.display_font:
		pct_lbl.add_theme_font_override("font", ThemeManager.display_font)
	center.add_child(pct_lbl)
	_pct_lbl = pct_lbl

	var wins_lbl := UI.label("Series", 38, "text_dim", HORIZONTAL_ALIGNMENT_CENTER)
	wins_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	center.add_child(wins_lbl)

	holder.add_child(center)
	return holder

func _dot_matrix() -> Control:
	var games := int(GameStats.get_stat("games_played"))
	if games <= 0:
		return Control.new()

	const COLS  := 7
	const ROWS  := 6
	const CELLS := COLS * ROWS
	const DOT   := 36
	const GAP   := 10
	# Proportional fill: the share of "win" cells always tracks the win rate,
	# so the grid reads as a ratio regardless of total games.
	var win_cells := int(round(GameStats.win_rate() * CELLS))

	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)

	var muted := _muted_col()
	for i in CELLS:
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(DOT, DOT)
		var sb := StyleBoxFlat.new()
		var is_win := i < win_cells
		sb.bg_color = Color(CHIP_VIOLET[0]) if is_win else muted
		sb.set_corner_radius_all(6)
		dot.add_theme_stylebox_override("panel", sb)
		grid.add_child(dot)
		# Only the wins light up. The loss dots are the ground the wins land on —
		# animating those too would turn a ratio into a full-grid shimmer that says
		# nothing about the split it exists to show.
		if is_win:
			_win_dots.append(dot)
	return grid

func _dot_legend() -> Control:
	var won   := int(GameStats.get_stat("games_won"))
	var games := int(GameStats.get_stat("games_played"))
	var row   := UI.hbox(int(DesignSystem.SPACE_LG))
	row.add_child(_legend_dot(Color(CHIP_VIOLET[0]), "Won (%d)" % won))
	row.add_child(_legend_dot(_muted_col(), "Lost (%d)" % (games - won)))
	return row

func _legend_dot(col: Color, text: String) -> Control:
	var row := UI.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(16, 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(4)
	swatch.add_theme_stylebox_override("panel", sb)
	row.add_child(swatch)
	var lbl := UI.label(text, 38, "text_dim")
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(lbl)
	return row
