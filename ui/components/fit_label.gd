class_name FitLabel
extends Label
## A Label that SHRINKS ITS OWN TYPE to fit the box it was given.
##
## EVERY NUMBER ON THESE SCREENS GROWS. A best score reaches seven figures, a
## move count eight, a play-time string "1274h 20m" — and a Label with
## AUTOWRAP_OFF answers that by reporting a minimum width the size of its text.
## Whatever contains it then has one of two bad options: grow, and push the card
## and the whole page off the screen, or refuse, and let the text draw straight
## through the card's edge and into its neighbour. Both are what "the number came
## out of its block" looks like, and which one a given row does is decided by
## nothing more principled than whether its container happened to be expandable.
##
## `clip_text` alone is not the fix either. It keeps the LAYOUT honest by eating
## the last digits, and a stats page that renders 1,234,567 as "1,234,5" is worse
## than one that overflows, because the reader cannot tell it happened.
##
## So this label clips only as a last resort and SIZES ITSELF FIRST: it picks the
## largest font size between `min_font_size` and `max_font_size` whose text fits
## the width it was actually handed, and it reserves exactly the floor width (the
## text at `min_font_size`) as its minimum — so a row can neither be pushed wide
## by it nor collapse it to nothing. Height is reserved at the FULL size, so a
## number that shrinks never changes the height of the card it sits in.
##
## `budget_text` is the widest string the label will ever hold, and setting it is
## what makes a COUNTING number stable: Statistics tweens each figure up through
## its digits, and re-fitting per frame would make the type visibly breathe on the
## way. Left empty, the label refits from its own live text instead — which is
## what an in-game SCORE wants, since nobody knows in advance how far a run goes.

## The designed size — what the label wears whenever the text fits.
var max_font_size := 0
## The floor it will shrink to before it gives up and clips.
var min_font_size := 0
## The widest string this label will ever hold, or "" to track the live text.
## Setting it also turns OFF the per-frame text watch, which is the whole point:
## a label whose final width is known never needs to be measured again.
var budget_text := "":
	set(value):
		budget_text = value
		set_process(budget_text.is_empty())
		_refresh()

## A ceiling on the width this label may CLAIM (0 = none). Only meaningful for a
## label that is not expanding — see `_claim_width` for which of the two rules a
## given label lands on, and why it is read off the size flags rather than asked
## for as a second setting.
var max_width := 0.0:
	set(value):
		max_width = value
		_refresh()

## The font size currently pushed as an override, so an unchanged fit costs
## nothing (add_theme_font_size_override re-runs layout even for the same value).
var _applied := -1
## The text the live watch last measured, so _process only works when it changed.
var _fitted_for := "￿"

## `p_min` of 0 means "pick a sensible floor" — 55% of the designed size, which
## is as small as these numerals stay legible next to their captions.
static func make(p_text: String, p_max: int, p_min: int = 0) -> FitLabel:
	var l := FitLabel.new()
	l.max_font_size = p_max
	l.min_font_size = p_min if p_min > 0 else maxi(1, int(round(float(p_max) * 0.55)))
	# The designed size is pushed as an override up front, so a label that never
	# needs to shrink is already wearing the size its caller asked for rather than
	# whatever the theme's default happens to be.
	l.add_theme_font_size_override("font_size", p_max)
	l.text = p_text
	return l

func _init() -> void:
	autowrap_mode = TextServer.AUTOWRAP_OFF
	# The height is pinned at the designed size (see _refresh), so a shrunken
	# number has to centre itself in the space its full-size sibling reserved.
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	resized.connect(_fit)
	# The size flags decide which width this label claims (see _claim_width), and
	# callers set them AFTER construction — so the claim has to be re-derived
	# when they move, not just when the text does.
	size_flags_changed.connect(_refresh)

func _ready() -> void:
	set_process(budget_text.is_empty())
	_refresh()

func _notification(what: int) -> void:
	# A theme change swaps the face out from under every measurement taken here.
	if what == NOTIFICATION_THEME_CHANGED and is_inside_tree():
		_refresh()

func _process(_delta: float) -> void:
	if text != _fitted_for:
		_refresh()

## Re-measures the floor and the reserved height, then re-fits. Called when
## anything a measurement depends on moves: the text, the budget, the theme.
func _refresh() -> void:
	if not is_inside_tree() or max_font_size <= 0:
		return
	_fitted_for = text
	# A wrapping or ellipsised label is not ours to manage (see _defers_to_label),
	# and handing back the CLIP matters as much as handing back the claim: Godot
	# reports a clipping autowrap Label's minimum height as one pixel, so a
	# reserved single-line box would pin a three-line paragraph to its first line.
	if _defers_to_label():
		clip_text = false
		custom_minimum_size = Vector2.ZERO
		return
	clip_text = true
	var f := get_theme_font("font")
	if f == null:
		return
	# Height is reserved at the FULL size on purpose: a number that shrinks must
	# not change the height of the card it sits in, or a HUD would jump the first
	# time a score gained a digit.
	custom_minimum_size = Vector2(_claim_width(f), ceilf(f.get_height(max_font_size)))
	_fit()

## How much width this label ASKS its container for — the one decision that
## separates a label which fixes an overflow from one which causes it, and it is
## read off the size flags rather than asked for as a second setting, because the
## flags already say which of the two situations the label is in.
##
## EXPANDING: claim the FLOOR, the text at `min_font_size`. An expanding label is
## by definition being handed width by its container, so anything it demands
## beyond the floor is width it is taking from the page — that is how a
## seven-figure score used to push a stat card past the screen edge. It gets the
## container's share and fits its type into it.
##
## NOT EXPANDING: claim the NATURAL measure, the text at full size, capped by
## `max_width` when one is set. A content-sized column has no other source of
## width, so a floor claim here would pin every number at the smallest type it
## owns. The cap is what stops the claim growing without limit (Tower's HUD).
func _claim_width(f: Font) -> float:
	if _defers_to_label():
		return 0.0
	var want := _want()
	if size_flags_horizontal & Control.SIZE_EXPAND:
		var floor_size: int = min_font_size if min_font_size > 0 else max_font_size
		return ceilf(f.get_string_size(want, HORIZONTAL_ALIGNMENT_LEFT, -1, floor_size).x)
	var natural := ceilf(
		f.get_string_size(want, HORIZONTAL_ALIGNMENT_LEFT, -1, max_font_size).x)
	return minf(natural, max_width) if max_width > 0.0 else natural

func _want() -> String:
	return budget_text if not budget_text.is_empty() else text

## Whether this label should behave as a plain Label and let go entirely.
##
## Shrinking type is the answer for text that CANNOT reflow. A caller who turns
## autowrap on, or asks for an ellipsis, has already chosen a different answer to
## the same problem and, with it, a Label minimum width of one pixel — which is
## deliberate at the sites that do it (Home's Continue title exists to not
## dictate its card's width). Overriding that with a claim of our own would make
## this class the cause of the overflow it exists to prevent.
func _defers_to_label() -> bool:
	return autowrap_mode != TextServer.AUTOWRAP_OFF \
		or text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING

## Picks the largest size that fits. Text width is near enough LINEAR in font
## size that one proportional guess lands on or just above the answer, so this
## measures two or three times rather than walking every size down from the top —
## which matters because a live SCORE re-fits whenever its digits change.
func _fit() -> void:
	if not is_inside_tree() or max_font_size <= 0 or _defers_to_label():
		return
	var avail := size.x
	if avail <= 0.0:
		return
	var f := get_theme_font("font")
	if f == null:
		return
	var want := _want()
	if want.is_empty():
		return
	var floor_size: int = min_font_size if min_font_size > 0 else max_font_size
	var chosen := max_font_size
	var w := f.get_string_size(want, HORIZONTAL_ALIGNMENT_LEFT, -1, max_font_size).x
	if w > avail:
		chosen = clampi(int(floor(float(max_font_size) * avail / w)),
			floor_size, max_font_size)
		# The guess is an estimate, not a measurement — hinting and kerning make
		# the real width step unevenly. Walk it down until it genuinely fits.
		var guard := 0
		while chosen > floor_size and guard < 8 \
				and f.get_string_size(want, HORIZONTAL_ALIGNMENT_LEFT, -1, chosen).x > avail:
			chosen -= 1
			guard += 1
	if chosen == _applied:
		return
	_applied = chosen
	add_theme_font_size_override("font_size", chosen)
