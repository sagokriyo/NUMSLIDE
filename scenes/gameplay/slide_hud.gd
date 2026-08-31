class_name SlideHud
extends Control
## SlideHud — the scoreboard. Three numbers across the top, progress under them,
## and what the board is asking of you at the bottom.
##
## THREE NUMERALS, NOT TWO NUMERALS AND A WORD. The grade used to sit in the
## right-hand slot at title size, so "PERFECT" ran nearly twice the width of the
## "0" opposite it and the bar read as one heavy end and one light one. The three
## slots hold numbers now — moves, tiles home, the target — and the grade has a
## strip of its own where a word has room to be a word.
##
## PROGRESS IS A BAR ACROSS THE PANEL, NOT A RING IN THE MIDDLE OF IT. The ring
## was 152 points wide, which is sixty-nine pixels on the phone this is drawn
## for, and a readout has to live inside it: at that size the number and its
## caption together are taller than the hole in the middle, so "LEFT" was drawn
## straight across the bottom of the arc on every board Rush dealt, and moving
## the caption out only bought a couple of points of air. A circle cannot be
## given more room without taking it from the board. A bar can be as wide as the
## panel, reads from across the room, and has nothing inside it to collide with.
##
## THE MIDDLE STILL MATTERS. A sliding puzzle gives almost no feedback on its own
## — the board looks like a mess right up until it does not — so the bar is what
## says you are getting somewhere. On Rush it is the CLOCK instead, because there
## the thing draining is the run, and it goes hot in the last ten seconds.
##
## THE STRIP COUNTS DOWN TO THE DROP. It carries the grade the current move count
## would earn AND how many moves are left before it falls to the next one. That
## number shrinking is the tension the mode runs on; the grade alone just sat
## there saying PERFECT until suddenly it did not.

const BAR_PX := 16.0
const PIP_PX := 26.0
## The panel's height with the grade strip, and without it (Rush has no par).
const H_GRADED := 268.0
const H_PLAIN := 200.0

var par: int = 0
var mode: GameModes.Mode = null

var _pane: GlassPanel
var _moves_lbl: Label
var _mid_lbl: Label
var _mid_cap: Label
var _right_lbl: Label
var _right_cap: Label
var _bar: _Meter
var _strip: HBoxContainer
var _grade_lbl: Label
var _drop_lbl: Label
var _pips: Array[Control] = []
var _timer_mode := false
var _shown_grade := ""
var _assisted := false
var _last_moves := 0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = H_GRADED

func _ready() -> void:
	_build()
	if ThemeManager.has_signal("theme_changed"):
		ThemeManager.theme_changed.connect(func(_p: Dictionary) -> void: _restyle())

func _build() -> void:
	_pane = GlassPanel.new()
	_pane.elevation = 1
	_pane.radius = DesignSystem.RADIUS_LG
	_pane.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pane)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, int(DesignSystem.SPACE_LG))
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(DesignSystem.SPACE_MD))
	add_child(margin)

	var col := UI.vbox(DesignSystem.SPACE_MD)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	var row := UI.hbox(DesignSystem.SPACE_MD)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	row.add_child(_slot(0))
	row.add_child(_slot(1))
	row.add_child(_slot(2))

	_bar = _Meter.new()
	_bar.custom_minimum_size.y = BAR_PX
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_bar)

	col.add_child(_grade_strip())
	_restyle()

## One slot of the top row: a numeral over its caption. All three are built by
## the same call, so no two of them can drift apart in size or spacing.
func _slot(which: int) -> Control:
	var col := UI.vbox(DesignSystem.SPACE_XS)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A FitLabel, because these grow: a move count reaches four figures and Rush
	# opens on a two-digit clock. The type shrinks rather than the slot widening
	# and shoving its neighbours off centre.
	var value := UI.fit_numeral("0", DesignSystem.TYPE_TITLE, "text",
		HORIZONTAL_ALIGNMENT_CENTER, "88/88")
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cap := UI.caption("", "text_faint", HORIZONTAL_ALIGNMENT_CENTER)
	cap.autowrap_mode = TextServer.AUTOWRAP_OFF
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(value)
	col.add_child(cap)
	match which:
		0:
			_moves_lbl = value
			cap.text = "MOVES"
		1:
			_mid_lbl = value
			_mid_cap = cap
		_:
			_right_lbl = value
			_right_cap = cap
	return col

## The grade, and the countdown to losing it.
func _grade_strip() -> Control:
	_strip = UI.hbox(DesignSystem.SPACE_SM)
	_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for id in Pace.LADDER:
		var pip := _Pip.new()
		pip.hue = Pace.hue(id)
		pip.custom_minimum_size = Vector2(PIP_PX, PIP_PX)
		_pips.append(pip)
		_strip.add_child(pip)
	_grade_lbl = UI.label("", DesignSystem.TYPE_LABEL, "text")
	_grade_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	_strip.add_child(_grade_lbl)
	_drop_lbl = UI.caption("", "text_faint")
	_drop_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	_strip.add_child(_drop_lbl)
	return _strip

func _restyle() -> void:
	if _bar == null:
		return
	_bar.hot = false
	_bar.color_a = ThemeManager.color("accent")
	_bar.color_b = ThemeManager.color("accent_soft")
	_bar.queue_redraw()

# --- The conductor drives these -----------------------------------------------------

## Sets the bar up for one run.
func begin(p_mode: GameModes.Mode, p_par: int) -> void:
	mode = p_mode
	par = p_par
	_timer_mode = p_mode != null and p_mode.has_timer
	_restyle()
	_shown_grade = ""
	_assisted = false
	if _timer_mode:
		_mid_cap.text = "SECONDS"
		_right_cap.text = "CLEARED"
		_right_lbl.text = "0"
		_strip.visible = false
		custom_minimum_size.y = H_PLAIN
	else:
		_mid_cap.text = "HOME"
		# PAR IS A TARGET, and the caption says so. "PAR" alone reads as a number
		# the player is meant to match; what it marks is the move count an Expert
		# run comes in under, with one more rung above it.
		_right_cap.text = "TARGET"
		_right_lbl.text = str(par)
		_strip.visible = true
		custom_minimum_size.y = H_GRADED
	set_moves(0)
	set_progress(0, 1)

func set_moves(n: int) -> void:
	if _moves_lbl == null:
		return
	_last_moves = n
	_moves_lbl.text = UI.commafy(n)
	if _timer_mode or par <= 0:
		return
	# The grade the CURRENT move count would earn, and how much room is left in
	# it. A run at nought moves is Perfect by definition; the interest is watching
	# the room shrink.
	var grade := Pace.grade(maxi(n, 1), par, _assisted)
	var spare: int = maxi(0, Pace.threshold(grade, par) - n)
	_grade_lbl.text = Pace.title(grade)
	_grade_lbl.add_theme_color_override("font_color", Pace.hue(grade))
	# Nothing sits below Steady, and Assisted has nowhere left to fall.
	var counting := grade != Pace.STEADY and grade != Pace.ASSISTED
	_drop_lbl.text = "· %d before it drops" % spare if counting else ""
	_light_grade(grade)

## The solver touched this run. The ladder is over: the strip says Assisted for
## the rest of the board rather than counting down a grade that can no longer
## be earned.
func set_assisted() -> void:
	if _assisted:
		return
	_assisted = true
	set_moves(_last_moves)

## Fills the meter with tiles home over tiles total.
func set_progress(home: int, total: int) -> void:
	if _bar == null or _timer_mode:
		return
	var denom := maxi(1, total)
	_bar.value = clampf(float(home) / float(denom), 0.0, 1.0)
	_mid_lbl.text = "%d/%d" % [home, denom]

## Rush: the clock across the meter, and boards cleared on the right.
func set_clock(seconds_left: float, of_total: float) -> void:
	if _bar == null or not _timer_mode:
		return
	set_clock_arc(seconds_left, of_total)
	_mid_lbl.text = "%d" % int(ceil(maxf(0.0, seconds_left)))

## The meter alone, without touching the readout. The conductor calls this on
## every frame and `set_clock` only when the second on show actually changes: a
## Label that re-lays out sixty times a second to print the same two digits is
## work nobody can see.
func set_clock_arc(seconds_left: float, of_total: float) -> void:
	if _bar == null or not _timer_mode:
		return
	_bar.value = clampf(seconds_left / maxf(1.0, of_total), 0.0, 1.0)
	# The last ten seconds go hot, so the clock is felt rather than read.
	var hot := seconds_left <= 10.0
	if hot != _bar.hot:
		_bar.hot = hot
		_bar.color_a = Color("FF8A5C") if hot else ThemeManager.color("accent")
		_bar.color_b = Color("F25C6E") if hot else ThemeManager.color("accent_soft")
	_bar.queue_redraw()

func set_cleared(n: int) -> void:
	if _right_lbl == null or not _timer_mode:
		return
	_right_lbl.text = str(n)

## Lights the ladder up to and including `grade`.
func _light_grade(grade: String) -> void:
	if _shown_grade == grade:
		return
	_shown_grade = grade
	var rung := Pace.rung(grade)
	for k in _pips.size():
		var pip: _Pip = _pips[k]
		pip.lit = k < rung
		pip.queue_redraw()

# --- The meter ---------------------------------------------------------------------

## A flat rounded bar: a faint full-width track with the fill laid over it as a
## short two-stop gradient, the same light every other progress reading in the
## app wears. Drawn rather than styled because a StyleBoxFlat cannot carry a
## gradient, and a bar in one flat colour is the one thing on this panel that
## would not look like the rest of the app.
class _Meter extends Control:
	var value: float = 0.0
	var color_a: Color = Color.WHITE
	var color_b: Color = Color.WHITE
	var hot := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var r := size.y * 0.5
		if r <= 0.0 or size.x <= 0.0:
			return
		_capsule(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.12))
		var w := size.x * clampf(value, 0.0, 1.0)
		if w <= 0.0:
			return
		# Never narrower than the cap, or a bar at one percent draws as a wedge.
		_capsule(Rect2(Vector2.ZERO, Vector2(maxf(w, size.y), size.y)), color_a, color_b)

	## ONE POLYGON, not a rectangle with a disc stuck on each end. These colours
	## are translucent, so anywhere the disc lapped the rectangle the alpha
	## doubled and the bar wore a bright pip at each end — most visible on the
	## faint track, where it read as a stray dot rather than as a rounded end.
	const CAP_STEPS := 10

	func _capsule(box: Rect2, left: Color, right: Color) -> void:
		var r := box.size.y * 0.5
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var lo := box.position + Vector2(r, r)
		var hi := box.position + Vector2(box.size.x - r, r)
		# Right cap, top to bottom, then the left one: one closed outline.
		for k in CAP_STEPS + 1:
			var a := -PI * 0.5 + PI * float(k) / float(CAP_STEPS)
			pts.append(hi + Vector2(cos(a), sin(a)) * r)
			cols.append(right)
		for k in CAP_STEPS + 1:
			var a := PI * 0.5 + PI * float(k) / float(CAP_STEPS)
			pts.append(lo + Vector2(cos(a), sin(a)) * r)
			cols.append(left)
		draw_polygon(pts, cols)

# --- One rung of the grade ladder ------------------------------------------------

class _Pip extends Control:
	var hue: Color = Color.WHITE
	var lit := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var c := size * 0.5
		if lit:
			draw_texture_rect(CandyFace.halo_tex(),
				Rect2(c - Vector2(r, r) * 2.2, Vector2(r, r) * 4.4), false,
				Color(hue.r, hue.g, hue.b, 0.30))
			draw_circle(c, r * 0.72, hue)
			draw_circle(c - Vector2(0, r * 0.22), r * 0.28, Color(1, 1, 1, 0.55))
		else:
			draw_arc(c, r * 0.68, 0.0, TAU, 24, Color(1, 1, 1, 0.16), 2.0, true)
