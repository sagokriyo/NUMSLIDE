class_name ProgressRing
extends Control
## ProgressRing — a thin circular progress arc. A full faint track ring with a
## brighter fill arc sweeping clockwise from 12 o'clock, painted as a short
## col_a → col_b gradient so it matches the app's linear progress bars. Used to
## ring the profile rank badge with "progress to next tier".
##
## `value` (0..1) drives the sweep and has a setter that repaints, so it can be
## tweened directly: `tw.tween_property(ring, "value", target, dur)`.

var value: float = 0.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()
var thickness: float = 12.0:
	set(v): thickness = v; queue_redraw()
var track_color: Color = Color(1, 1, 1, 0.12):
	set(v): track_color = v; queue_redraw()
var color_a: Color = Color.WHITE:
	set(v): color_a = v; queue_redraw()
var color_b: Color = Color.WHITE:
	set(v): color_b = v; queue_redraw()
## Where the fill starts, in degrees (−90 = 12 o'clock).
var start_deg: float = -90.0
## Rounds both ends of the fill arc with a disc the width of the stroke.
##
## OFF by default: the 12pt ring around the rank badge is thin enough that a
## squared end reads as a clean tick, and turning caps on there would change art
## that already shipped. A FAT ring is the opposite case — at the 24pt the
## Statistics win-rate donut wears, a squared end reads as a broken pipe, which
## is why that donut drew its own caps before it moved onto this widget.
var rounded_caps: bool = false:
	set(v): rounded_caps = v; queue_redraw()

## A thin bright line just INSIDE the stroke, so a fat ring reads as a filled
## channel with a lip rather than as a drawn circle. Depth, not decoration: at
## the 22pt the Badge page hero wears, a flat band is the one element on the card
## with no material to it.
##
## Off by default — every ring that shipped before this is thin enough that a
## second line inside it would simply thicken the stroke.
var inner_hairline: bool = false:
	set(v): inner_hairline = v; queue_redraw()

## Notches cut across the track: `ticks` of them, evenly spaced from `start_deg`,
## with the first `ticks_lit` drawn in the fill colour and the rest in the track.
##
## What turns a progress arc into a LADDER. The Badge page halo shows progress to
## the next tier; the notches show how many rungs the ladder has and how many are
## behind you, which is the fact the page otherwise makes you scroll to the
## trophy case to learn. 0 = no notches, which is every other ring in the app.
var ticks: int = 0:
	set(v): ticks = maxi(v, 0); queue_redraw()
var ticks_lit: int = 0:
	set(v): ticks_lit = maxi(v, 0); queue_redraw()

## A bright bead riding the head of the fill, with a soft halo behind it.
##
## The head of an arc is where the eye lands, and a squared end there reads as
## the ring having been cut rather than as a value having been reached. The bead
## says "you are HERE" — and it is what makes the fill animation legible, since a
## growing band of colour has no moving part to follow.
var bead: bool = false:
	set(v): bead = v; queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5 - thickness * 0.5 - 1.0
	if r <= 0.0:
		return
	var c := size * 0.5
	# Full faint track.
	draw_arc(c, r, 0.0, TAU, 128, track_color, thickness, true)
	_draw_ticks(c, r)
	if value <= 0.0:
		return
	# Fill arc, drawn as short gradient segments (draw_arc takes one colour each).
	var start := deg_to_rad(start_deg)
	var end := start + TAU * value
	var segs := maxi(2, int(round(128.0 * value)))
	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var a0 := lerpf(start, end, t0)
		var a1 := lerpf(start, end, t1)
		var col := color_a.lerp(color_b, (t0 + t1) * 0.5)
		draw_arc(c, r, a0, a1, 8, col, thickness, true)
	if rounded_caps:
		# Each cap wears the gradient colour of the end it closes, so a cap never
		# sits as a differently-coloured bead on a two-tone arc.
		var cap := thickness * 0.5
		draw_circle(c + Vector2(cos(start), sin(start)) * r, cap, color_a)
		draw_circle(c + Vector2(cos(end), sin(end)) * r, cap, color_b)
	if inner_hairline:
		# Just inside the stroke, and drawn AFTER the fill so it catches the lip
		# of whatever the arc painted rather than being buried under it.
		draw_arc(c, r - thickness * 0.5 + maxf(1.0, thickness * 0.06), 0.0, TAU, 96,
			Color(1, 1, 1, 0.22), maxf(1.0, thickness * 0.09), true)
	if bead:
		var at := c + Vector2(cos(end), sin(end)) * r
		# Halo first, then the bead, so the glow sits behind the light rather
		# than washing over it.
		draw_circle(at, thickness * 1.05, Color(color_b, 0.18))
		draw_circle(at, thickness * 0.68, Color(color_b, 0.45))
		draw_circle(at, thickness * 0.40, Color(1, 1, 1, 0.95))

## The rung notches, cut across the track from `start_deg`. Drawn as short radial
## lines rather than as gaps in the arc: a gap would mean re-cutting the fill
## into `ticks` separate arcs, and the fill is already segmented for its gradient.
func _draw_ticks(c: Vector2, r: float) -> void:
	if ticks <= 0:
		return
	var half := thickness * 0.62
	var w := maxf(1.5, thickness * 0.12)
	for i in ticks:
		var a := deg_to_rad(start_deg) + TAU * float(i) / float(ticks)
		var d := Vector2(cos(a), sin(a))
		var col := Color(color_a, 0.85) if i < ticks_lit else Color(1, 1, 1, 0.22)
		draw_line(c + d * (r - half), c + d * (r + half), col, w, true)
