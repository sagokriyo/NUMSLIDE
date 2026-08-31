class_name UI
extends RefCounted
## UI — a static factory of premium, theme-aware widgets.
##
## Screens compose their layouts from these helpers instead of hand-authoring
## node trees, so spacing, type and colour stay perfectly consistent. Everything
## reads tokens from DesignSystem + ThemeManager at build time. For widgets that
## must restyle live on theme change, see AppScreen (it re-runs build()).

# --- Formatting ---------------------------------------------------------------
## Thin-space-free thousands separator: 12345 -> "12,345".
## The DESIGN-SPACE size of the canvas a node draws into. Inside AppScreen's
## reduced-resolution backdrop target the real viewport is half-sized, and the
## target carries the full logical size in its `design_size` meta (see
## AppScreen._layout_backdrop_target) — full-screen effects (BoardFx, drifting
## shards, behind-menu confetti) must lay out against THAT, or they build a
## quarter-size world. Everywhere else this is exactly the viewport rect.
static func canvas_size(n: CanvasItem) -> Vector2:
	var vp := n.get_viewport()
	if vp != null and vp.has_meta("design_size"):
		return vp.get_meta("design_size")
	return n.get_viewport_rect().size

static func commafy(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if n < 0 else out

# --- Text ---------------------------------------------------------------------
## `size` is the DESIGNED size: the house gain and floor (DesignSystem.type) are
## applied here, once, so a call site never wraps its size in type() itself.
static func label(text: String, size: int, color_key: String = "text", \
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", DesignSystem.type(size))
	l.add_theme_color_override("font_color", ThemeManager.color(color_key))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func display(text: String, color_key: String = "text") -> Label:
	var l := label(text, DesignSystem.TYPE_DISPLAY, color_key)
	l.add_theme_constant_override("line_spacing", -8)
	if ThemeManager.display_font:
		l.add_theme_font_override("font", ThemeManager.display_font)
	return l

static func title(text: String) -> Label:
	return label(text, DesignSystem.TYPE_TITLE, "text")

static func headline(text: String) -> Label:
	return label(text, DesignSystem.TYPE_HEADLINE, "text")

static func body(text: String, color_key: String = "text_dim") -> Label:
	return label(text, DesignSystem.TYPE_BODY, color_key)

static func caption(text: String, color_key: String = "text_faint", \
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label(text, DesignSystem.TYPE_CAPTION, color_key, align)
	return l

## A small UPPERCASE tracked label used for section eyebrows ("CONTINUE").
static func eyebrow(text: String) -> Label:
	var l := label(text.to_upper(), DesignSystem.TYPE_CAPTION, "text_faint")
	l.add_theme_constant_override("line_spacing", 0)
	return l

# --- Surfaces -----------------------------------------------------------------
static func glass_card(elevation: int = 1) -> PanelContainer:
	# The app's premium lit-glass surface: a real frosted pane that samples and blurs
	# the screen's backdrop (see GlassPanel). Handles input pass-through and restyles
	# per theme. Every card and ModalOverlay uses it; the toasts / pills that need a
	# plain stylebox use glass_box() below and stay in the same visual family.
	var card := GlassPanel.new()
	card.elevation = elevation
	return card

## THE SAME SHARD, SHAPED AS A PILL — the material the mode cards wear, at a
## chip's radius and a chip's padding. The currency strip, Home's identity
## capsule and the gameplay control buttons all take this, so a pill and a card
## sitting on the same screen are one substance seen at two sizes.
##
## They used to take `glass_box` instead, and the difference the player saw was
## the HAIRLINE: a flat stylebox draws a 1px rim, so every chip on Home carried
## an outline while the cards below them had none — two materials pretending to
## be one. A shard is transparent glass; it is defined by what shows through it,
## not by a line drawn around it.
static func glass_pill(elevation: int = 1, radius: float = DesignSystem.RADIUS_PILL) -> GlassPanel:
	var pill := GlassPanel.new()
	pill.elevation = elevation
	pill.radius = radius
	# A chip is not a card: card air (SPACE_LG) around a 32pt balance would push
	# three pills past the width budget on its own.
	pill.content_margin = DesignSystem.SPACE_SM
	# And a chip is not a card about its FROST either — see GlassPanel.frost_boost.
	# The card weight is a ~3% veil on a dark theme, which a 500px pane over a
	# textured sky wears beautifully and an Undo button over a flat dark board
	# does not wear at all: it read as a floating label with no surface under it.
	pill.frost_boost = PILL_FROST
	return pill

## How much milkier a pill's frost is than a card's (GlassPanel.frost_boost).
## One number, here, because the capsule, the currency chips and the gameplay
## controls have to agree — three pills at three weights on one screen is the
## drift the shared material exists to prevent.
const PILL_FROST := 0.16

## The FLAT glass stylebox — a translucent fill with a hairline rim, and no live
## frost. For the incidental surfaces drawn ON a card (Shop tickets, How to Play's
## plaques, toasts), where a real frosted pane over a frosted pane would blur the
## same wash twice and say nothing. Anything the player reads as a standalone
## surface — a card, a pill, a capsule, a button — takes glass_card / glass_pill.
static func glass_box(elevation: int = 1, radius: float = DesignSystem.RADIUS_LG) -> StyleBoxFlat:
	var p := ThemeManager.palette()
	var sb := StyleBoxFlat.new()
	sb.bg_color = p["glass"]
	sb.set_corner_radius_all(int(radius))
	var lit: float = GLASS_RIM_LIGHT if bool(p.get("is_light", false)) else GLASS_RIM
	sb.set_border_width_all(1)
	sb.border_color = p["stroke"].lerp(Color.WHITE, lit)
	sb.anti_aliasing = true
	sb.set_content_margin_all(DesignSystem.SPACE_LG)
	var sh := DesignSystem.shadow(elevation, p.get("shadow", p["bg0"]))
	sb.shadow_color = sh["color"]
	sb.shadow_size = int(sh["size"])
	sb.shadow_offset = sh["offset"]
	return sb

## How far glass_box's hairline leans toward pure light. Kept very low on purpose,
## and now only the incidental plaques carry it at all: the chips, the capsule and
## the Undo button used to wear this same rim, and a screen of them read as an
## outline drawn around every element rather than as glass. They are real frosted
## panes now (glass_pill), which have no edge to lean.
const GLASS_RIM := 0.06
const GLASS_RIM_LIGHT := 0.05

# --- Layout helpers -----------------------------------------------------------
static func vbox(gap: float = DesignSystem.SPACE_MD) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(gap))
	return v

static func hbox(gap: float = DesignSystem.SPACE_MD) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(gap))
	return h

static func spacer(min_size: float = 0.0, expand: bool = true) -> Control:
	var c := Control.new()
	# A spacer exists to occupy room and nothing else, so it must never CONSUME a
	# touch. Bare `Control` defaults to MOUSE_FILTER_STOP (Container and Label do
	# not, which is why this trap is invisible in the source), and an expanding
	# spacer is by definition the widest thing in its row — so one dropped into a
	# header inside a ScrollContainer becomes a full-width band where the page
	# refuses to scroll. Nothing errors; the finger just slides and the list
	# stays put.
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if min_size > 0.0:
		c.custom_minimum_size = Vector2(min_size, min_size)
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c

## Caps `child` at `max_w` design points and centres it once the available width
## exceeds that (tablets / wide-aspect phones), while letting it fill edge-to-edge
## on narrower screens. Returns a wrapper to place where `child` would have gone;
## `child` keeps filling — it just never grows past the designed measure, so its
## cards stop stretching. Backgrounds/FX are unaffected (they live outside the
## content frame), so the rest of the screen still uses the full width.
static func constrain_width(child: Control, max_w: float = DesignSystem.MAX_CONTENT_WIDTH) -> MarginContainer:
	var holder := MarginContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(child)
	# A MarginContainer's own minimum is its child's plus the margins, so a margin
	# set from `holder.size.x` can feed straight back into that size and grow a
	# pixel a pass for ever (the Academy's 15x15 board and the cube, whose minimum
	# widths are already past the measure, overflowed the stack that way). Two
	# defences: never take a margin the child cannot afford, and refuse to re-enter.
	var busy := [false]
	var relayout := func() -> void:
		if bool(busy[0]):
			return
		var floor_w: float = maxf(max_w, child.get_combined_minimum_size().x)
		var side := int(maxf(holder.size.x - floor_w, 0.0) * 0.5)
		if holder.get_theme_constant("margin_left") == side:
			return   # no change — avoid re-sorting on every layout pass
		busy[0] = true
		holder.add_theme_constant_override("margin_left", side)
		holder.add_theme_constant_override("margin_right", side)
		busy[0] = false
	holder.resized.connect(relayout)
	relayout.call()
	return holder

# --- Composite widgets --------------------------------------------------------
## A stat tile: big number over a quiet label. Used on Home and Statistics.
static func stat_tile(value_text: String, caption_text: String) -> Control:
	var card := glass_card(2)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = 156
	var col := vbox(DesignSystem.SPACE_XS)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	# FitLabels: the tile is a fixed half-width cell, so a value that outgrows it
	# has to give up type size — the alternative is the cell giving up its place
	# on the page (see FitLabel).
	var v := fit_numeral(value_text, 56, "text", HORIZONTAL_ALIGNMENT_LEFT, value_text)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var c := fit_label(caption_text.to_upper(), 27, "text_dim")
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(v)
	col.add_child(c)
	card.add_child(col)
	return card

## A glass card that responds to taps (for Home hub tiles, list rows, etc.).
## Caller adds content as children; the card lays them out and fires `on_tap`.
static func tappable(on_tap: Callable, elevation: int = 1) -> PanelContainer:
	var card := glass_card(elevation)
	make_scroll_tappable(card, on_tap)
	return card

## Movement (in design px) a press may wander before it's treated as a scroll
## drag rather than a tap. Keeps taps responsive while letting lists scroll.
const TAP_SLOP := 28.0
## Meta set on every make_scroll_tappable target, so a widget can tell "the
## press landed on a tappable child of mine" (see press_on_child_widget).
const TAP_META := &"tap_target"

## Makes `target` a tappable row that ALSO lets an ancestor ScrollContainer
## scroll when the gesture is a drag. The trick: MOUSE_FILTER_PASS lets the touch
## reach both this control (for the tap) and the scroll container (for the drag),
## and we only fire `on_tap` when the finger barely moved. Use this for any
## tappable card/row that lives inside a ScrollContainer.
## Makes every DESCENDANT of `root` transparent to input, so a composite widget
## is one tap target instead of a stack of them.
##
## Control defaults to MOUSE_FILTER_STOP, and a stopping child is handed the
## event and ends it there — the parent's `gui_input` never fires. That is how a
## tile built as "panel inside a wrapper" ships looking perfect and doing
## nothing: nothing errors, nothing is logged, the art is all correct, and the
## control is simply dead. Call this on the wrapper BEFORE `make_scroll_tappable`
## on it, which sets the wrapper itself back to PASS.
static func pass_through(root: Control) -> void:
	for c: Node in root.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			pass_through(c as Control)

static func make_scroll_tappable(target: Control, on_tap: Callable) -> void:
	target.mouse_filter = Control.MOUSE_FILTER_PASS
	target.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	target.set_meta(TAP_META, true)
	# "squished" tracks the press-feedback scale so it springs back exactly once,
	# whether the gesture ends in a tap or turns into a scroll drag.
	var st := {"down": false, "moved": 0.0, "squished": false, "cancel": Callable()}
	target.gui_input.connect(func(e: InputEvent):
		if e is InputEventScreenTouch:
			var te := e as InputEventScreenTouch
			if te.pressed:
				if press_on_child_widget(target, te.position):
					return
				_begin_press(target, st)
			elif bool(st["down"]):
				_end_press(target, st)
				if float(st["moved"]) < TAP_SLOP:
					_fire_tap(on_tap)
		elif e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var me := e as InputEventMouseButton
			if me.pressed:
				if press_on_child_widget(target, me.position):
					return
				_begin_press(target, st)
			elif bool(st["down"]):
				_end_press(target, st)
				if float(st["moved"]) < TAP_SLOP:
					_fire_tap(on_tap)
		elif e is InputEventScreenDrag and bool(st["down"]):
			st["moved"] = float(st["moved"]) + (e as InputEventScreenDrag).relative.length()
			if float(st["moved"]) >= TAP_SLOP:
				_release_feedback(target, st)
		elif e is InputEventMouseMotion and bool(st["down"]):
			st["moved"] = float(st["moved"]) + (e as InputEventMouseMotion).relative.length()
			if float(st["moved"]) >= TAP_SLOP:
				_release_feedback(target, st))

## True when a press at `local_pos` (the target's own coordinates) lands on a
## descendant that handles presses itself: a Button, another make_scroll_tappable
## target, or any control with its own `gui_input` handler. ScrollEnhancer
## switches every such child from STOP to PASS so a drag that starts on it can
## scroll the page, which means the card now sees the press too; without this a
## tap on a card's own button would fire BOTH actions.
static func press_on_child_widget(target: Control, local_pos: Vector2) -> bool:
	var at: Vector2 = target.get_global_transform() * local_pos
	var stack: Array = target.get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n is Control):
			continue
		var c := n as Control
		if c.mouse_filter == Control.MOUSE_FILTER_IGNORE or not c.is_visible_in_tree():
			continue
		if not c.get_global_rect().has_point(at):
			continue
		if c is BaseButton or c.has_meta(TAP_META) or not c.gui_input.get_connections().is_empty():
			return true
	return false

## Press bookkeeping, plus the scroll cancel: the moment the ancestor
## ScrollContainer passes its deadzone and starts to move (`scroll_started`) the
## press is void, whatever the path-length slop still says. Without it a drag of
## 14 to 28 px both scrolled the page AND opened the card.
static func _begin_press(target: Control, st: Dictionary) -> void:
	st["down"] = true
	st["moved"] = 0.0
	st["squished"] = true
	_press_feedback(target, true)
	var sc := _scroll_ancestor(target)
	if sc == null:
		return
	var cancel := func() -> void:
		if not is_instance_valid(target):
			return
		st["down"] = false
		_release_feedback(target, st)
	st["cancel"] = cancel
	sc.scroll_started.connect(cancel, CONNECT_ONE_SHOT)

static func _end_press(target: Control, st: Dictionary) -> void:
	st["down"] = false
	_release_feedback(target, st)
	var cancel: Callable = st["cancel"]
	if cancel.is_valid():
		var sc := _scroll_ancestor(target)
		if sc != null and sc.scroll_started.is_connected(cancel):
			sc.scroll_started.disconnect(cancel)
	st["cancel"] = Callable()

## The ScrollContainer this control scrolls inside, or null. Stops at a
## CanvasLayer / Viewport boundary (a modal on its own layer is not "inside" the
## page scroll beneath it).
static func _scroll_ancestor(c: Control) -> ScrollContainer:
	var n: Node = c.get_parent()
	while n != null and not (n is CanvasLayer or n is Viewport):
		if n is ScrollContainer:
			return n as ScrollContainer
		n = n.get_parent()
	return null

## Quick tactile press "squish" for a tappable card/row: scale down on touch,
## spring back on release or when the gesture becomes a scroll.
static func _press_feedback(target: Control, down: bool) -> void:
	if target.size != Vector2.ZERO:
		target.pivot_offset = target.size * 0.5
	var to: Vector2 = Vector2(0.97, 0.97) if down else Vector2.ONE
	var dur: float = DesignSystem.DUR_INSTANT if down else DesignSystem.DUR_FAST
	var t := target.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(target, "scale", to, dur)
	_press_shadow(target, down, dur)

## Collapses a card's drop shadow while it is held, so a press reads as the card
## moving DOWN toward its surface rather than merely shrinking. Scale alone is a
## web hover; scale plus a closing shadow is a physical object.
##
## Only touches a StyleBoxFlat the widget owns as its own "panel" override, which
## every card here builds fresh per instance — so this can never mutate a shared
## or themed stylebox out from under another screen. Anything else (GlassPanel's
## shader surface, a bare Label) keeps the scale-only feedback it had.
static func _press_shadow(target: Control, down: bool, dur: float) -> void:
	if not target.has_theme_stylebox_override("panel"):
		return
	var sb := target.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		return
	var rest: float = float(target.get_meta("rest_shadow", sb.shadow_size))
	if rest <= 0.0:
		return
	target.set_meta("rest_shadow", rest)
	var to: float = rest * 0.35 if down else rest
	target.create_tween().set_ease(Tween.EASE_OUT) \
		.tween_property(sb, "shadow_size", to, dur)

## Springs a squished target back to rest, exactly once per press.
static func _release_feedback(target: Control, st: Dictionary) -> void:
	if not bool(st["squished"]):
		return
	st["squished"] = false
	_press_feedback(target, false)

static func _fire_tap(on_tap: Callable) -> void:
	AudioManager.play_sfx("button_tap", 0.04)
	Haptics.light()
	if on_tap.is_valid():
		on_tap.call()

## A circular ghost icon-button showing a single glyph (e.g. back chevron, gear).
static func icon_button(glyph: String) -> PremiumButton:
	var b := PremiumButton.make(glyph, PremiumButton.Variant.GLASS)
	b.custom_minimum_size = Vector2(96, 96)
	b.add_theme_font_size_override("font_size", DesignSystem.TYPE_TITLE)
	return b

# --- Themed PNG icons ---------------------------------------------------------
# The bundled icons are colourful gradients. To keep the premium, restrained look
# (and to make icons follow the active theme) we render them monochrome: a small
# shader converts each icon to luminance and multiplies by a theme colour. The
# result re-tints automatically when the palette changes.
static var _icon_shader: Shader

static func _get_icon_shader() -> Shader:
	if _icon_shader == null:
		_icon_shader = Shader.new()
		_icon_shader.code = """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float l = dot(t.rgb, vec3(0.299, 0.587, 0.114));
	l = clamp(l * 1.2 + 0.12, 0.0, 1.0);
	COLOR = vec4(tint.rgb * l, t.a * tint.a);
}
"""
	return _icon_shader

static func icon_material(tint: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _get_icon_shader()
	m.set_shader_parameter("tint", tint)
	return m

## Path → Texture2D, or null if missing (keeps callers crash-safe).
## Also accepts an IconLibrary id ("best_score", "settings", …) — those render
## the premium gradient icon set, sharp at any size and with no PNG asset.
static func icon_tex(path: String) -> Texture2D:
	if IconLibrary.has_icon(path):
		return IconLibrary.texture(path, 128)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

## `icon_tex` WITHOUT the baked glow halo. For the design sheet's 72-unit tokens
## (currencies, shop, share), which carry their own dark contour and cast shadow
## — the halo double-lights them and bleeds a coloured smudge onto whatever they
## sit on. See IconLibrary._token72. Non-library paths are unaffected.
static func icon_tex_flat(path: String) -> Texture2D:
	if IconLibrary.has_icon(path):
		return IconLibrary.texture(path, 128, false)
	return icon_tex(path)

## A decorative themed icon (no interaction). `box` is the square size in px.
## An empty `tint_key` keeps the icon's native colours (IconLibrary gradients).
static func icon_rect(path: String, box: float, tint_key: String = "accent") -> TextureRect:
	var icon_node := TextureRect.new()
	icon_node.custom_minimum_size = Vector2(box, box)
	icon_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_node.texture = icon_tex(path)
	if not tint_key.is_empty():
		icon_node.material = icon_material(ThemeManager.color(tint_key))
	return icon_node

## A glass icon-button backed by a PNG, tinted to the theme. Falls back to a
## glyph button when the texture is missing so the UI degrades gracefully.
static func image_button(path: String, tint_key: String = "text", fallback_glyph: String = "") -> PremiumButton:
	var tex := icon_tex(path)
	if tex == null:
		return icon_button(fallback_glyph)
	var b := PremiumButton.make("", PremiumButton.Variant.GLASS)
	b.custom_minimum_size = Vector2(96, 96)
	var icon_node := TextureRect.new()
	icon_node.texture = tex
	icon_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_node.material = icon_material(ThemeManager.color(tint_key))
	icon_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_node.offset_left = 20
	icon_node.offset_top = 20
	icon_node.offset_right = -20
	icon_node.offset_bottom = -20
	b.add_child(icon_node)
	return b

## Adds a calm press "squish" to any custom button: the visual `target` scales
## down while `button` is held, springing back on release.
static func wire_press(target: Control, button: Button) -> void:
	target.pivot_offset = target.custom_minimum_size / 2.0
	target.resized.connect(func(): target.pivot_offset = target.size / 2.0)
	button.button_down.connect(func():
		target.pivot_offset = target.size / 2.0
		var t := target.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		t.tween_property(target, "scale", Vector2(0.95, 0.95), DesignSystem.DUR_INSTANT))
	button.button_up.connect(func():
		var t := target.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		t.tween_property(target, "scale", Vector2.ONE, DesignSystem.DUR_FAST))

## An UPPERCASE coloured section eyebrow with an optional right-aligned action
## ("View All ›"), wrapped tightly above `body`. Used across the redesigned
## screens for a consistent rhythm.
static func section(eyebrow_text: String, body: Control, color_key: String = "accent", \
		action_text: String = "", action_cb: Callable = Callable()) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ey := Label.new()
	ey.text = eyebrow_text.to_upper()
	ey.add_theme_font_size_override("font_size", 32)
	ey.add_theme_color_override("font_color", ThemeManager.color(color_key))
	ey.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ey.autowrap_mode = TextServer.AUTOWRAP_OFF
	header.add_child(ey)
	if not action_text.is_empty() and action_cb.is_valid():
		var act := Label.new()
		act.text = action_text + "  ›"
		act.add_theme_font_size_override("font_size", 28)
		act.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
		act.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		make_scroll_tappable(act, action_cb)
		header.add_child(act)
	box.add_child(header)
	box.add_child(body)
	return box

## A standard top bar: a circular back button on the left, a centered title, and
## an optional trailing control on the right (balanced so the title stays centred).
static func top_bar(title_text: String, on_back: Callable, trailing: Control = null) -> Control:
	var bar := hbox(DesignSystem.SPACE_SM)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size.y = 104
	bar.add_child(circle_button("back", "", on_back))
	var title := label(title_text, DesignSystem.TYPE_TITLE, "text", HORIZONTAL_ALIGNMENT_CENTER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	if ThemeManager.display_font:
		title.add_theme_font_override("font", ThemeManager.display_font)
	bar.add_child(title)
	if trailing != null:
		bar.add_child(trailing)
	else:
		var bal := Control.new()
		bal.custom_minimum_size = Vector2(104, 104)
		bar.add_child(bal)
	return bar

## A true circular chip background (no StyleBoxFlat half-radius seam).
static func _chip_bg(p: Dictionary) -> Control:
	var bg := ChipBg.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.fill = p["glass"]
	bg.stroke = p["stroke"]
	if bool(p.get("is_light", false)):
		var sc: Color = p.get("shadow", p["bg0"])
		sc.a = 0.18
		bg.shadow_col = sc
	return bg

## A circular frosted button hosting a crisp PremiumIcon (gear, person, back…).
static func premium_circle(kind: String, icon_color: Color, on_press: Callable, diameter: float = 104.0) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(diameter, diameter)
	var p := ThemeManager.palette()

	holder.add_child(_chip_bg(p))

	var icon: Control = PremiumIcon.make(kind, icon_color, diameter * 0.5)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	var inset := diameter * 0.27
	icon.offset_left = inset
	icon.offset_top = inset
	icon.offset_right = -inset
	icon.offset_bottom = -inset
	holder.add_child(icon)

	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	btn.pressed.connect(func(): _fire_tap(on_press))
	holder.add_child(btn)
	wire_press(holder, btn)
	return holder

## A bare icon button — no bubble, just a tinted PNG icon with a tap ripple.
## `tint_key` empty → native glossy colours; otherwise tinted to that theme color.
static func circle_button(icon_path: String, tint_key: String, on_press: Callable, diameter: float = 104.0, with_glow: bool = true) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(diameter, diameter)

	var icon := TextureRect.new()
	# with_glow = false for the 72-unit sheet tokens (shop, share, currencies),
	# which already carry their own contour — see icon_tex_flat.
	icon.texture = icon_tex(icon_path) if with_glow else icon_tex_flat(icon_path)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Library icons already carry their own internal margin (shadow + glow ring),
	# so they sit nearly edge-to-edge; PNGs keep the classic breathing room.
	var inset := diameter * (0.02 if IconLibrary.has_icon(icon_path) else 0.10)
	icon.offset_left = inset
	icon.offset_top = inset
	icon.offset_right = -inset
	icon.offset_bottom = -inset
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not tint_key.is_empty():
		icon.material = icon_material(ThemeManager.color(tint_key))
	holder.add_child(icon)

	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	btn.pressed.connect(func(): _fire_tap(on_press))
	holder.add_child(btn)
	wire_press(holder, btn)
	return holder

## THE BUTTON THAT DEALS A BOARD — the glossy play circle every mode card wears,
## sized and centred for a list row. `play_icon` names one of IconLibrary's six
## colour variants; ask the mode for it (`GameModes.Mode.play_icon`) rather than
## picking one here, so the row icon and the circle stay one set.
##
## It lives in the factory rather than on Home because two screens draw it — the
## featured rows on Home and every card on More Modes — and a hand-copied second
## one is how the two lists would start disagreeing about what a play button is.
## Shrink-centred vertically so it sits mid-row whatever height the text grows to.
static func play_button(play_icon: String, on_press: Callable, diameter: float = 124.0) -> Control:
	var holder := circle_button(play_icon, "", on_press, diameter)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return holder

## A themed on/off switch (pill track + circular knob) — replaces the stock
## Godot CheckButton so Settings' toggles match the app's premium sliders
## instead of a default OS control. `on_toggled` receives the new bool value.
static func switch(value: bool, on_toggled: Callable) -> Control:
	const W := 108.0
	const H := 60.0
	const PAD := 6.0
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(W, H)
	holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var p := ThemeManager.palette()
	var d := H - PAD * 2.0

	var track := Panel.new()
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	# Off-state track wears the CONTROL fill (a dark ink tint on light themes) —
	# the card fill `glass` is white on light themes and vanished on white cards.
	sb.bg_color = p["accent"] if value else p["control"]
	sb.set_corner_radius_all(int(H * 0.5))
	sb.set_border_width_all(1)
	sb.border_color = p["control_stroke"]
	track.add_theme_stylebox_override("panel", sb)
	holder.add_child(track)

	# On light themes the white knob gets a soft ink outline so it still reads on
	# the pale off-state track.
	var ring := Color(0, 0, 0, 0)
	if bool(p.get("is_light", false)):
		var outline: Color = p["text"]
		ring = Color(outline.r, outline.g, outline.b, 0.30)
	var knob := TextureRect.new()
	knob.texture = _switch_knob_tex(int(d), ring)
	knob.custom_minimum_size = Vector2(d, d)
	knob.size = Vector2(d, d)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	knob.position = Vector2((W - d - PAD) if value else PAD, PAD)
	holder.add_child(knob)

	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var state := {"on": value}
	btn.pressed.connect(func():
		var on: bool = not bool(state["on"])
		state["on"] = on
		AudioManager.play_sfx("button_tap", 0.04)
		Haptics.light()
		var to_x: float = (W - d - PAD) if on else PAD
		var to_col: Color = p["accent"] if on else p["control"]
		var t := knob.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		t.tween_property(knob, "position:x", to_x, DesignSystem.DUR_FAST)
		var from_col: Color = sb.bg_color
		var ct := track.create_tween()
		ct.tween_method(func(c: Color): sb.bg_color = c, from_col, to_col, DesignSystem.DUR_FAST)
		on_toggled.call(on))
	holder.add_child(btn)
	return holder

## A soft-edged filled circle for the switch knob — the track already supplies
## all the colour, so this is a white disc; a non-transparent `ring` adds a thin
## outline so the knob stays visible on pale tracks (light themes).
static func _switch_knob_tex(d: int, ring: Color = Color(0, 0, 0, 0)) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := float(d) * 0.5
	var ring_w := 2.0
	for y in d:
		for x in d:
			var dist := Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c).length()
			var a := clampf(c - dist + 0.5, 0.0, 1.0)
			if a <= 0.0:
				continue
			var col := Color(1, 1, 1, a)
			if ring.a > 0.0:
				# Blend the outline in over the outermost ring_w pixels of the disc.
				var edge := clampf((dist - (c - 1.0 - ring_w)) / ring_w, 0.0, 1.0)
				var mixed := Color(1, 1, 1, 1).lerp(Color(ring.r, ring.g, ring.b, 1.0), edge * ring.a)
				col = Color(mixed.r, mixed.g, mixed.b, a)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

## A thin progress bar (used for achievements progress, daily timer, etc.).
## The fill is anchored proportionally so it tracks the bar's actual width.
## `fill_in` animates the bar out to `value` on entry instead of appearing at it.
## A bar that is simply THERE states a fact; one that fills reads as progress the
## player made, which is the whole reason a bounty has a bar rather than a
## fraction. Honours reduce_motion, where it lands at its value immediately.
static func progress(value: float, accent_key: String = "accent",
		fill_in: bool = false) -> Control:
	var track := Control.new()
	track.custom_minimum_size.y = 8
	track.clip_contents = true
	# Decorative, so it must not eat a drag: bare Control and ColorRect both
	# default to MOUSE_FILTER_STOP, and a progress bar spans the full width of
	# whatever row it reports on — three bounty rows' worth of them turned into
	# three full-width bands where the Shop refused to scroll.
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := ColorRect.new()
	bg.color = ThemeManager.color("control")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	track.add_child(bg)

	var bar := ColorRect.new()
	bar.color = ThemeManager.color(accent_key)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	var target := clampf(value, 0.0, 1.0)
	bar.anchor_right = target
	track.add_child(bar)

	if fill_in and target > 0.0 and not bool(SettingsManager.get_value("reduce_motion")):
		bar.anchor_right = 0.0
		# Deferred: a tween needs the node in the tree, and the caller has not
		# parented `track` yet at this point.
		track.ready.connect(func() -> void:
			var tw := track.create_tween()
			tw.tween_property(bar, "anchor_right", target, DesignSystem.DUR_SLOW) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))
	return track

## A palette colour adjusted so it survives being used as TEXT on the current
## palette's own surfaces.
##
## LIGHT palettes are the entire reason this exists. `accent` and `text_dim` are
## picked to read on a dark ground; on a pale one the same value lands a pastel
## on near-white and drops under the legibility floor — measurably, on
## `kawaii` (2.56), `sakura_pink` (2.68) and `arctic` (3.32), per
## tools/profile_contrast_audit.tscn. Leaning toward `text` keeps the hue and
## buys the contrast back.
##
## For TEXT only. A fill, a rim or a tint behind something is not being read, and
## darkening those would flatten the palette's whole colour story for no gain —
## which is why this is an explicit call at the point of use rather than
## something baked into `ThemeManager.color`.
static func ink(color_key: String, amount: float = 0.45) -> Color:
	return ink_of(ThemeManager.color(color_key), amount)

## `ink` for a colour that is not a palette key — the rank accent, a currency
## hue, anything already resolved.
static func ink_of(c: Color, amount: float = 0.45) -> Color:
	var p := ThemeManager.palette()
	if not bool(p.get("is_light", false)):
		return c
	return c.lerp(p["text"], amount)

# --- Premium surface craft -----------------------------------------------------
## Rounded-corner CLIPPING for a Control that draws its own content.
##
## `clip_contents` clips to the RECT, so live art (a ThemePreview, a board) inside
## a rounded card keeps square corners that cut visibly across the card's curve —
## the concentric-radius rule broken at the most visible place on the screen.
## Godot has no rounded clip, so this masks alpha in the shader instead.
##
## The mask is computed from VERTEX (the item's own local position) rather than
## UV: UV on a Control's draw calls belongs to each PRIMITIVE, not to the control's
## rect, so a UV-based mask works for draw_texture_rect and silently fails for
## draw_circle / draw_polygon — which is most of what live art is made of.
static var _round_shader: Shader

static func _get_round_shader() -> Shader:
	if _round_shader == null:
		_round_shader = Shader.new()
		# NOTE the ASCENDING smoothstep + subtraction. A descending edge
		# (smoothstep(hi, lo, x)) renders black on D3D12 — see the D3D12 note in
		# the gameplay shaders; always write 1.0 - smoothstep(lo, hi, x).
		_round_shader.code = """
shader_type canvas_item;
uniform vec2 rect_size = vec2(100.0, 100.0);
uniform float radius = 32.0;
varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 c = min(local_pos, rect_size - local_pos);
	vec2 d = vec2(radius) - min(c, vec2(radius));
	float dist = length(d);
	COLOR.a *= 1.0 - smoothstep(radius - 1.0, radius + 0.5, dist);
}
"""
	return _round_shader

## Clips `target`'s own drawing to a rounded rect of `radius`, and keeps the mask
## in sync as it resizes. Affects only what `target` itself draws — a CanvasItem
## material does not cascade to children, so apply it to the node holding the art.
static func round_clip(target: Control, radius: float = DesignSystem.RADIUS_LG) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = _get_round_shader()
	mat.set_shader_parameter("radius", radius)
	mat.set_shader_parameter("rect_size", target.size)
	target.material = mat
	target.resized.connect(func() -> void:
		mat.set_shader_parameter("rect_size", target.size))

## A soft fade of the screen's own backdrop over ONE edge, so content scrolling
## under a pinned element (or running off the end of a rail) dissolves instead of
## being guillotined. A hard content cut at a container boundary is the most
## common "unfinished layout" tell there is.
##
## Returns the node UNPARENTED — the caller anchors it over the scroller, which
## must be a sibling overlay rather than a child (a child of a ScrollContainer
## scrolls away with the content it is meant to be masking).
static func edge_fade(side: String, extent: float = 64.0) -> TextureRect:
	var p := ThemeManager.palette()
	var base: Color = p["bg0"]
	var grad := Gradient.new()
	grad.set_color(0, Color(base.r, base.g, base.b, 1.0))
	grad.set_color(1, Color(base.r, base.g, base.b, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	match side:
		"top":
			tex.width = 4; tex.height = int(extent)
			tex.fill_from = Vector2(0, 0); tex.fill_to = Vector2(0, 1)
		"bottom":
			tex.width = 4; tex.height = int(extent)
			tex.fill_from = Vector2(0, 1); tex.fill_to = Vector2(0, 0)
		"right":
			tex.width = int(extent); tex.height = 4
			tex.fill_from = Vector2(1, 0); tex.fill_to = Vector2(0, 0)
		_:   # "left"
			tex.width = int(extent); tex.height = 4
			tex.fill_from = Vector2(0, 0); tex.fill_to = Vector2(1, 0)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

## A 1px structural rule at low alpha. Gaps read as absence; a hairline reads as
## structure, which is most of the difference between a list and a table.
static func hairline(alpha: float = 0.08) -> Control:
	var line := ColorRect.new()
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c: Color = ThemeManager.color("text")
	line.color = Color(c.r, c.g, c.b, alpha)
	return line

## A price, set the way a price tag is set: a big confident numeral in the display
## face with the currency token SMALLER beside it.
##
## The old chip had this exactly backwards — a 38pt token beside a 35pt number, so
## the currency symbol out-sized the price it was labelling. Numerals are also
## never allowed to wrap (see the AUTOWRAP_OFF notes in shop.gd).
static func numeral(text: String, size: int, color_key: String = "text") -> Label:
	var l := label(text, size, color_key)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tab := tabular_display()
	if tab != null:
		l.add_theme_font_override("font", tab)
	elif ThemeManager.display_font:
		l.add_theme_font_override("font", ThemeManager.display_font)
	return l

## A numeral that FITS: same tabular display face as `numeral`, but it shrinks
## its own type rather than pushing the row wider than the screen or drawing
## through the card's edge when the number grows a digit. See FitLabel — the two
## failure modes it exists to end are exactly what a seven-figure best score did
## to every stat card and HUD on the way here.
##
## `budget` is the widest string this label will ever hold; pass it whenever the
## final value is known at build time (a stat card, a leaderboard row) so a
## count-up animation cannot make the type breathe on its way there. Leave it
## empty for a live number, e.g. the in-game SCORE.
static func fit_numeral(text: String, size: int, color_key: String = "text", 		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, 		budget: String = "", min_size: int = 0) -> FitLabel:
	var l := FitLabel.make(text, DesignSystem.type(size), min_size)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", DesignSystem.type(size))
	l.add_theme_color_override("font_color", ThemeManager.color(color_key))
	var tab := tabular_display()
	if tab != null:
		l.add_theme_font_override("font", tab)
	elif ThemeManager.display_font:
		l.add_theme_font_override("font", ThemeManager.display_font)
	l.budget_text = budget
	return l

## As `fit_numeral`, but in the BODY face — for the words beside the numbers
## (a mode name, a "LONGEST SESSION" caption) which run out of their cards for
## exactly the same reason and have no count-up to protect.
static func fit_label(text: String, size: int, color_key: String = "text", 		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, 		min_size: int = 0) -> FitLabel:
	var l := FitLabel.make(text, DesignSystem.type(size), min_size)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", DesignSystem.type(size))
	l.add_theme_color_override("font_color", ThemeManager.color(color_key))
	l.budget_text = text
	return l

## The display face with TABULAR figures, cached per theme.
##
## Proportional digits are why a rolling balance jitters: a "1" is narrower than
## an "8", so a counting odometer visibly breathes as it passes through them, and
## a column of prices never quite lines up. `tnum` fixes every digit to one
## advance. Fonts without the feature are unaffected, so this is safe to ask for
## on any face the theme ships.
static var _tabular: FontVariation
static var _tabular_base: Font

static func tabular_display() -> Font:
	var base := ThemeManager.display_font
	if base == null:
		return null
	if _tabular != null and _tabular_base == base:
		return _tabular
	var fv := FontVariation.new()
	fv.base_font = base
	fv.opentype_features = {"tnum": 1}
	_tabular = fv
	_tabular_base = base
	return _tabular

## A copy of the display font with generous letter spacing (null when the theme
## ships no display face, in which case the caller's label keeps the default).
## Wide tracking on a short uppercase title is most of what separates a section
## eyebrow from a row of body text.
static func tracked_display(spacing: int) -> Font:
	if ThemeManager.display_font == null:
		return null
	var fv := FontVariation.new()
	fv.base_font = ThemeManager.display_font
	fv.spacing_glyph = spacing
	return fv

## Fades `nodes` in, staggered. The cheapest "expensive" signal in UI, and the
## reason it is a helper rather than a copy-paste: the stagger must be identical
## everywhere or it reads as jank rather than as choreography.
##
## FADE ONLY, deliberately. The obvious version also slides each node up a few
## px — but these are children of a Container, which OWNS their position and
## rewrites it on the next layout pass, so the slide either fights the container
## or is silently discarded. Opacity is the one channel a container does not
## manage.
##
## EACH NODE RETURNS TO ITS OWN ALPHA, not to 1.0. A dimmed row is dimmed for a
## reason — Achievements paints every locked milestone at 0.6, Themes fades a
## locked card's stage to 0.8 — and an entrance that finished by tweening
## everything to full would silently unlock-look the whole list on the way in.
## The authored alpha is captured BEFORE the node is zeroed and is what the tween
## aims at.
static func stagger_in(nodes: Array, step: float = 0.045) -> void:
	# reduce_motion is a real contract here (Confetti, GlassDrift, GlassPanel and
	# the board flourishes all honour it). A choreographed entrance is exactly the
	# kind of motion it exists to switch off — and a fade that never runs would
	# otherwise leave every section stuck at alpha 0, so the guard has to land
	# BEFORE the tween, not inside it. Nothing is written here: the node has not
	# been zeroed yet, so it is already sitting at exactly the alpha it was built
	# with, which is the same value the animated path would have landed on.
	if bool(SettingsManager.get_value("reduce_motion")):
		return
	var i := 0
	for n_v: Variant in nodes:
		var n: Control = n_v as Control
		if n == null or not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var authored: float = n.modulate.a
		# Already mid-stagger (or authored invisible) — zeroing again would aim the
		# tween at 0 and leave the node hidden for good.
		if authored <= 0.0:
			continue
		n.modulate.a = 0.0
		var tw := n.create_tween()
		tw.tween_property(n, "modulate:a", authored, DesignSystem.DUR_BASE) \
			.set_delay(float(i) * step).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		i += 1
