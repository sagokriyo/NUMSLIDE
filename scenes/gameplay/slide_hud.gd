class_name SlideHud
extends Control
## SlideHud — the scoreboard. Three numbers across the top, and what the board is
## asking of you underneath.
##
## THREE NUMERALS, NOT TWO NUMERALS AND A WORD. The grade used to sit in the
## right-hand slot at title size, so "PERFECT" ran nearly twice the width of the
## "0" opposite it and the bar read as one heavy end and one light one. The three
## slots hold numbers now — moves, tiles home, par — and the grade moved to a
## strip of its own where a word has room to be a word.
##
## THE MIDDLE IS THE POINT. A sliding puzzle gives almost no feedback on its own
## (the board looks like a mess right up until it does not), so the ring is the
## thing that tells the player they are getting somewhere. On Rush the ring is
## the CLOCK instead, because there the thing draining is the run.
##
## THE STRIP COUNTS DOWN TO THE DROP. It carries the grade the current move count
## would earn AND how many moves are left before it falls to the next one. That
## number shrinking is the tension the mode runs on; the grade alone just sat
## there saying PERFECT until suddenly it did not.

const RING_PX := 140.0
## How far the ring's readout is inset from the stroke, so type never touches it.
const RING_INSET := 26.0
const PIP_PX := 22.0
## The bar's height with the grade strip, and without it (Rush has no par).
const H_GRADED := 258.0
const H_PLAIN := 208.0

var par: int = 0
var mode: GameModes.Mode = null

var _pane: GlassPanel
var _moves_lbl: Label
var _ring: ProgressRing
var _ring_lbl: FitLabel
var _ring_cap: Label
var _right_lbl: Label
var _right_cap: Label
var _strip: HBoxContainer
var _grade_lbl: Label
var _drop_lbl: Label
var _pips: Array[Control] = []
var _timer_mode := false
var _shown_grade := ""

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

	var col := UI.vbox(DesignSystem.SPACE_SM)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	var row := UI.hbox(DesignSystem.SPACE_MD)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	row.add_child(_number_column(true))
	row.add_child(_centre_column())
	row.add_child(_number_column(false))

	col.add_child(_grade_strip())

## One end of the bar: a numeral over a caption. Both ends are built the same, so
## the two cannot drift apart in size or spacing.
func _number_column(is_left: bool) -> Control:
	var col := UI.vbox(DesignSystem.SPACE_XS)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var value := UI.numeral("0", DesignSystem.TYPE_TITLE, "text")
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cap := UI.caption("", "text_faint")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(value)
	col.add_child(cap)
	if is_left:
		_moves_lbl = value
		cap.text = "MOVES"
	else:
		_right_lbl = value
		_right_cap = cap
	return col

func _centre_column() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(RING_PX, RING_PX)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring = ProgressRing.new()
	_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ring.thickness = 10.0
	_ring.rounded_caps = true
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_ring)

	# INSET from the stroke. The readout used to lay out against the ring's full
	# box, so "12/24" ran under the arc it was supposed to sit inside.
	var inner := MarginContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, int(RING_INSET))
	holder.add_child(inner)

	var stack := UI.vbox(0.0)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(stack)
	# A FitLabel, because "3/8" and "18/24" are not the same width and the ring
	# is a fixed circle: the type shrinks rather than the number overflowing it.
	# BODY, not headline: the fraction shares a fixed circle with its own stroke,
	# and at headline size "12/24" filled the ring wall to wall.
	_ring_lbl = UI.fit_numeral("0", DesignSystem.TYPE_BODY, "text",
		HORIZONTAL_ALIGNMENT_CENTER, "88/88")
	_ring_cap = UI.caption("", "text_faint")
	_ring_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_ring_lbl)
	stack.add_child(_ring_cap)
	return holder

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
	if _ring == null:
		return
	_ring.color_a = ThemeManager.color("accent")
	_ring.color_b = ThemeManager.color("accent_soft")
	_ring.track_color = Color(1, 1, 1, 0.10)

# --- The conductor drives these -----------------------------------------------------

## Sets the bar up for one run.
func begin(p_mode: GameModes.Mode, p_par: int) -> void:
	mode = p_mode
	par = p_par
	_timer_mode = p_mode != null and p_mode.has_timer
	_restyle()
	_shown_grade = ""
	if _timer_mode:
		_ring_cap.text = "LEFT"
		_right_cap.text = "CLEARED"
		_right_lbl.text = "0"
		_strip.visible = false
		custom_minimum_size.y = H_PLAIN
	else:
		_ring_cap.text = "HOME"
		_right_cap.text = "PAR"
		_right_lbl.text = str(par)
		_strip.visible = true
		custom_minimum_size.y = H_GRADED
	set_moves(0)
	set_progress(0, 1)

func set_moves(n: int) -> void:
	if _moves_lbl == null:
		return
	_moves_lbl.text = UI.commafy(n)
	if _timer_mode or par <= 0:
		return
	# The grade the CURRENT move count would earn, and how much room is left in
	# it. A run at nought moves is Perfect by definition; the interest is watching
	# the room shrink.
	var grade := Pace.grade(maxi(n, 1), par)
	var spare: int = maxi(0, Pace.threshold(grade, par) - n)
	_grade_lbl.text = Pace.title(grade)
	_grade_lbl.add_theme_color_override("font_color", Pace.hue(grade))
	# Nothing sits below Steady, so there is no drop left to count down to.
	_drop_lbl.text = "" if grade == Pace.STEADY else "· %d before it drops" % spare
	_light_grade(grade)

## Fills the ring with tiles home over tiles total.
func set_progress(home: int, total: int) -> void:
	if _ring == null or _timer_mode:
		return
	var denom := maxi(1, total)
	_ring.value = clampf(float(home) / float(denom), 0.0, 1.0)
	_ring_lbl.text = "%d/%d" % [home, denom]

## Rush: the clock in the ring, and boards cleared on the right.
func set_clock(seconds_left: float, of_total: float) -> void:
	if _ring == null or not _timer_mode:
		return
	var denom := maxf(1.0, of_total)
	_ring.value = clampf(seconds_left / denom, 0.0, 1.0)
	_ring_lbl.text = "%d" % int(ceil(maxf(0.0, seconds_left)))
	# The last ten seconds go hot, so the clock is felt rather than read.
	var hot := seconds_left <= 10.0
	_ring.color_a = Color("FF8A5C") if hot else ThemeManager.color("accent")
	_ring.color_b = Color("F25C6E") if hot else ThemeManager.color("accent_soft")

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

# --- One rung of the grade ladder ------------------------------------------------

class _Pip extends Control:
	var hue: Color = Color.WHITE
	var lit := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

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
