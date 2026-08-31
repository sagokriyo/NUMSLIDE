class_name ChipBg
extends Control
## ChipBg — a true circular chip background drawn with draw_circle, avoiding the
## StyleBoxFlat seam that appears when a square panel's corner radius equals half
## its size (which left a faint vertical line down every circular button).

var fill: Color = Color(1, 1, 1, 0.08)
var stroke: Color = Color(1, 1, 1, 0.12)
var shadow_col: Color = Color(0, 0, 0, 0.0)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	if shadow_col.a > 0.0:
		# A soft drop shadow built from a few faded, downward-offset discs.
		for i in 4:
			var t := float(i) / 4.0
			var a := shadow_col.a * (1.0 - t)
			draw_circle(c + Vector2(0, 3.0 + t * 4.0), r * (1.0 + t * 0.04),
				Color(shadow_col.r, shadow_col.g, shadow_col.b, a))
	draw_circle(c, r, fill)
	draw_arc(c, r - 1.0, 0.0, TAU, 64, stroke, 2.0, true)
