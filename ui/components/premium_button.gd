class_name PremiumButton
extends Button
## A button with a calm, expensive feel: glass/accent fills, a subtle press
## "squish", and built-in tap audio + haptics. Restyles itself on theme change.
##
## Three variants cover the whole app:
##   PRIMARY — solid accent, used for the single most important action
##   GLASS   — translucent surface, the default for most actions
##   GHOST   — text only, for tertiary / dismissive actions
##
## Instantiate from code (PremiumButton.make("Play", PremiumButton.Variant.PRIMARY)).
## Not meant to be placed in scenes by hand — screens build their UI in script.

enum Variant { PRIMARY, GLASS, GHOST, DANGER }

var variant: Variant = Variant.GLASS
var silent: bool = false   # skip tap SFX (e.g. for rapid toggles)
var _fx: BtnFx             # ripple + gloss overlay (built in _ready)

## When true the button expands to fill its container's width. Applied via the
## setter so it works whether set before or after the node enters the tree.
var full_width: bool = false:
	set(value):
		full_width = value
		size_flags_horizontal = Control.SIZE_EXPAND_FILL if value else Control.SIZE_SHRINK_CENTER

## Corner rounding, for the rare button that wants a different one from the house
## radius — a tall hero call-to-action reads almost square at RADIUS_MD, which is
## tuned for the standard 64pt row. A DesignSystem token, never a magic number.
## Applied through the setter so it works before or after the node enters the tree.
var corner_radius: float = DesignSystem.RADIUS_MD:
	set(value):
		corner_radius = value
		if is_inside_tree():
			_restyle()

## Factory: the idiomatic way to create one.
static func make(label: String, p_variant: Variant = Variant.GLASS) -> PremiumButton:
	var b := PremiumButton.new()
	b.variant = p_variant
	b.text = label
	return b

func _ready() -> void:
	pivot_offset = size / 2.0
	resized.connect(func(): pivot_offset = size / 2.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size.y = 64
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	pressed.connect(_on_pressed)
	ThemeManager.theme_changed.connect(func(_p): _restyle())
	# Touch ripple + occasional gloss sweep live on their own clipped overlay, so
	# neither ever restyles the button or fights the stylebox.
	_fx = BtnFx.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.clip_contents = true
	add_child(_fx)
	if variant == Variant.PRIMARY:
		_start_gloss()
	_restyle()

func _on_down() -> void:
	_scale_to(0.96, DesignSystem.DUR_INSTANT)
	# The press lands WHERE the finger is: a soft ring of light spreads from the
	# touch point across the glass.
	_fx.ripple(get_local_mouse_position())

func _on_up() -> void:
	_scale_to(1.0, DesignSystem.DUR_FAST)

func _on_pressed() -> void:
	if not silent:
		AudioManager.play_sfx("button_tap", 0.04)
	Haptics.light()

func _scale_to(s: float, dur: float) -> void:
	pivot_offset = size / 2.0
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "scale", Vector2(s, s), dur)

func _restyle() -> void:
	var p := ThemeManager.palette()
	var radius := int(corner_radius)
	var fill: Color
	var text_col: Color
	match variant:
		Variant.PRIMARY:
			fill = p["accent"]
			# Guaranteed-contrast ink: near-black on bright accents, pure white on
			# deep ones. (Using bg0/text here broke on light themes, where bg0 is a
			# pastel and text is dark — a deep accent got dark-on-dark labels.)
			text_col = Color("14161B") if fill.get_luminance() > 0.55 else Color.WHITE
		Variant.GLASS:
			# The CONTROL fill, not the card fill — on light themes the card fill is
			# frosted white, so a glass button painted with it disappears on a card.
			fill = p["control"]
			text_col = p["text"]
		Variant.GHOST:
			fill = Color(0, 0, 0, 0)
			text_col = p["text_dim"]
		Variant.DANGER:
			fill = Color(0.72, 0.14, 0.14, 0.88)
			text_col = Color(1.0, 0.85, 0.85)

	add_theme_stylebox_override("normal", _box(fill, radius, p))
	add_theme_stylebox_override("hover", _box(_hover_fill(fill, p), radius, p))
	add_theme_stylebox_override("pressed", _box(_hover_fill(fill, p).darkened(0.08), radius, p))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_theme_color_override("font_color", text_col)
	add_theme_color_override("font_hover_color", text_col)
	add_theme_color_override("font_pressed_color", text_col)
	add_theme_color_override("font_disabled_color", p["text_faint"])
	add_theme_font_size_override("font_size", DesignSystem.TYPE_BODY)

func _hover_fill(base: Color, p: Dictionary) -> Color:
	if variant == Variant.GHOST:
		return p["control"]
	return base.lightened(0.06)

func _box(fill: Color, radius: int, p: Dictionary) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = DesignSystem.SPACE_LG
	sb.content_margin_right = DesignSystem.SPACE_LG
	sb.content_margin_top = DesignSystem.SPACE_MD
	sb.content_margin_bottom = DesignSystem.SPACE_MD
	if variant == Variant.GLASS:
		sb.set_border_width_all(1)
		sb.border_color = p["control_stroke"]
	elif variant == Variant.PRIMARY or variant == Variant.DANGER:
		var sh := DesignSystem.shadow(2, fill)
		sb.shadow_color = Color(fill.r, fill.g, fill.b, 0.28)
		sb.shadow_size = int(sh["size"])
		sb.shadow_offset = sh["offset"]
	return sb

## Primary buttons only: every few seconds a soft light band glides across the
## face — the hero action quietly advertises itself. Each button runs on its own
## random clock so two primaries on one screen never flash together.
func _start_gloss() -> void:
	var tw := create_tween().set_loops()
	tw.tween_interval(randf_range(4.0, 7.0))
	tw.tween_method(_fx.set_gloss, 0.0, 1.0, 1.1) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

## The ripple/gloss pane. Draws with plain vertex-colour geometry + the shared
## soft glow dot — no shader, no texture allocations. clip_contents keeps the
## light inside the button rect (the soft-edged glow makes the square clip at
## the rounded corners imperceptible at these alphas).
class BtnFx extends Control:
	var _ripples: Array = []   # live ripples: {pos: Vector2, r: float, a: float}
	var _gloss := -1.0         # gloss sweep progress; <0 or >1 = off

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func ripple(at: Vector2) -> void:
		var rp := {"pos": at, "r": 0.0, "a": 0.30}
		_ripples.append(rp)
		var reach: float = maxf(size.length(), 64.0)
		var grow := func(v: float) -> void:
			rp["r"] = v
			queue_redraw()
		var fade := func(v: float) -> void:
			rp["a"] = v
		var done := func() -> void:
			_ripples.erase(rp)
			queue_redraw()
		var tw := create_tween().set_parallel(true)
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_method(grow, 6.0, reach, 0.45)
		tw.tween_method(fade, 0.30, 0.0, 0.45)
		tw.set_parallel(false)
		tw.tween_callback(done)

	func set_gloss(v: float) -> void:
		_gloss = v
		queue_redraw()

	func _draw() -> void:
		for rp in _ripples:
			var r: float = rp["r"]
			var a: float = rp["a"]
			if r > 0.0 and a > 0.0:
				draw_texture_rect(CandyFace.glow_dot(),
					Rect2(Vector2(rp["pos"]) - Vector2(r, r), Vector2(r, r) * 2.0),
					false, Color(1, 1, 1, a))
		if _gloss >= 0.0 and _gloss <= 1.0 and size.x > 0.0:
			# A slanted light band crossing left → right; drawn as two half-quads so
			# the brightness peaks on the band's centre line.
			var s: float = size.y * 0.7            # slant (top leads, base trails)
			var w: float = size.x * 0.14 + s       # band half-width
			var cx: float = lerpf(-w, size.x + w + s, _gloss)
			var a := 0.12
			for half in 2:
				var x0: float = cx - w if half == 0 else cx
				var x1: float = cx if half == 0 else cx + w
				var a0: float = 0.0 if half == 0 else a
				var a1: float = a if half == 0 else 0.0
				draw_polygon(PackedVector2Array([
					Vector2(x0, 0), Vector2(x1, 0),
					Vector2(x1 - s, size.y), Vector2(x0 - s, size.y)]),
					PackedColorArray([
						Color(1, 1, 1, a0), Color(1, 1, 1, a1),
						Color(1, 1, 1, a1), Color(1, 1, 1, a0)]))
