class_name BottomNav
extends Control
## BottomNav — the app's five-tab bar: Home · Achievements · Stats · Themes ·
## Profile, wearing the design sheet's glossy 3D glyphs (IconLibrary's "nav_*"
## set, sheet option 1a).
##
## Deliberately PLATE-FREE. There is no chip, pill or dark bubble behind any
## glyph, active or not — the icons sit straight on the bar's glass the way the
## rest of the app's icons sit on their cards, so the bar reads as one surface
## instead of five buttons. The active tab is called out with the glyph's OWN
## colour story instead: full-strength icon, a soft bloom in its signature hue,
## a small lift, and a label tinted to match. Inactive tabs are the same glyph,
## dimmed and a touch smaller.
##
## AppScreen owns placement and the content inset it reserves — a screen opts in
## by overriding `nav_tab()`. See ui/screen.gd.

## Height of the bar itself, in design px (the safe-area inset is added on top
## by AppScreen, which is also what reserves the matching content inset).
const BAR_HEIGHT := 180.0
const ICON_BOX := 96.0
const PAD_V := 14.0
## The active bloom's box. It hangs from the TOP of its tab cell, so this is both
## its diameter and the deepest it can reach — keeping it under BAR_HEIGHT is
## what guarantees the aura never escapes the bar. Sized so its centre lands on
## the glyph's centre (PAD_V plus half an icon, give or take the lift).
const GLOW_BOX := 124.0
## The active tab's lift, and how much smaller a resting glyph sits.
const LIFT := 6.0
const REST_SCALE := 0.9
const REST_ALPHA := 0.5

## The tab order, left to right. `route` keys into SceneRouter.Route, so a
## relocated screen cannot silently fall out of the bar.
##
## HOME SITS IN THE MIDDLE, not at the left end: it is the tab a player returns
## to most, and the centre slot is the one a thumb reaches without crossing the
## screen. The other four keep their reading order around it.
const TABS: Array[Dictionary] = [
	{"id": "achievements", "icon": "nav_achievements", "label": "Achievements", "route": "ACHIEVEMENTS"},
	{"id": "stats",        "icon": "nav_stats",        "label": "Stats",        "route": "STATISTICS"},
	{"id": "home",         "icon": "nav_home",         "label": "Home",         "route": "HOME"},
	{"id": "themes",       "icon": "nav_themes",       "label": "Themes",       "route": "THEMES"},
	{"id": "profile",      "icon": "nav_profile",      "label": "Profile",      "route": "PROFILE"},
]

## Which tab reads as current. Set by AppScreen from the screen's `nav_tab()`.
var active_tab := ""

var _card: PanelContainer

func _init() -> void:
	custom_minimum_size = Vector2(0, BAR_HEIGHT)
	# The bar is a surface players tap, not a hole: STOP keeps a press on the
	# glass between two icons from falling through to whatever the screen has
	# behind it (Home's grabbable tile field, most of all).
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Nothing the bar draws may leave the bar. GLOW_BOX already bounds the active
	# aura by construction; this is the guarantee that survives someone later
	# growing the icon, the lift or the bloom without re-deriving that geometry.
	clip_contents = true

func _ready() -> void:
	_rebuild()
	# The bar is a sibling of AppScreen's content frame, so the theme rebuild
	# that tears content down never reaches it — it restyles itself.
	ThemeManager.theme_changed.connect(func(_p):
		if is_instance_valid(self):
			_rebuild())

func _rebuild() -> void:
	# Detached before freeing: queue_free is deferred, so leaving the old bar in
	# the tree would render two stacked glass panes for a frame.
	for c in get_children():
		remove_child(c)
		c.queue_free()
	# The app's own frosted pane, so the bar belongs to the same material family
	# as every card above it rather than introducing a second kind of surface.
	_card = UI.glass_card(2)
	if _card is GlassPanel:
		var gp := _card as GlassPanel
		gp.radius = DesignSystem.RADIUS_XL
		gp.content_margin = 0.0
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	_card.add_child(row)

	var font_size := _label_size()
	for tab: Dictionary in TABS:
		row.add_child(_build_tab(tab, font_size))

## The biggest caption that still fits the narrowest tab, measured against the
## LONGEST label so all five share one size — fitting each label on its own
## would step the bar's typography across the row. Falls back to the caption
## token when there is no font or no width to measure against yet.
func _label_size() -> int:
	var fnt := get_theme_default_font()
	# _rebuild runs before the first layout pass, so `size` is still zero on the
	# opening build — fall back to the width the bar is about to be given (the
	# viewport less AppScreen's side padding) rather than to a blind default.
	var wide: float = size.x
	if wide <= 0.0:
		wide = get_viewport_rect().size.x - DesignSystem.SPACE_LG * 2.0
	if fnt == null or wide <= 0.0:
		return 30
	# Each tab owns a fifth of the bar; leave a little air on both sides so
	# neighbouring labels never touch.
	var budget: float = wide / float(TABS.size()) - 12.0
	var longest := ""
	for tab: Dictionary in TABS:
		var t := String(tab["label"])
		if t.length() > longest.length():
			longest = t
	var probe := 30
	var w: float = fnt.get_string_size(longest, HORIZONTAL_ALIGNMENT_LEFT, -1, probe).x
	if w <= 0.0:
		return probe
	return clampi(int(float(probe) * budget / w), 22, 30)

func _build_tab(tab: Dictionary, font_size: int) -> Control:
	var id := String(tab["id"])
	var icon_id := String(tab["icon"])
	var is_active: bool = id == active_tab

	var holder := Control.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# The active bloom: the glyph's own drop-shadow hue from the sheet.
	#
	# It hangs off the CELL, not off the icon. Parented to the icon it was
	# positioned relative to a box whose top edge sits ~12px below the bar's,
	# so a bloom wide enough to read spilled straight out of the bar. Anchored
	# to the top of the cell instead, its radius is bounded by the bar itself:
	# the gradient reaches zero alpha exactly on the ellipse inscribed in this
	# rect, so nothing is drawn past y = GLOW_BOX and the bar's own top edge is
	# already black. Added FIRST so it renders behind the icon and label.
	if is_active:
		var glow := TextureRect.new()
		glow.texture = _soft_radial_tex()
		glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glow.stretch_mode = TextureRect.STRETCH_SCALE
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.anchor_left = 0.5
		glow.anchor_right = 0.5
		glow.anchor_top = 0.0
		glow.anchor_bottom = 0.0
		glow.offset_left = -GLOW_BOX * 0.5
		glow.offset_right = GLOW_BOX * 0.5
		glow.offset_top = 0.0
		glow.offset_bottom = GLOW_BOX
		var g := IconLibrary.glow_color(icon_id)
		glow.modulate = Color(g.r, g.g, g.b, 0.5)
		holder.add_child(glow)

	# The column carries the lift: the active tab's content sits a few px higher
	# in its slot. Done with a margin rather than a position, because the column
	# is container-managed and a written position would be overwritten on layout.
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_top", int(PAD_V - (LIFT if is_active else 0.0)))
	pad.add_theme_constant_override("margin_bottom", int(PAD_V + (LIFT if is_active else 0.0)))
	holder.add_child(pad)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(col)

	# Native colours: an empty tint key, or UI's monochrome icon shader flattens
	# the whole gradient story these glyphs exist for.
	var icon := UI.icon_rect(icon_id, ICON_BOX, "")
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if not is_active:
		icon.modulate = Color(1, 1, 1, REST_ALPHA)
		icon.pivot_offset = Vector2(ICON_BOX, ICON_BOX) * 0.5
		icon.scale = Vector2(REST_SCALE, REST_SCALE)
	col.add_child(icon)

	var lbl := UI.label(String(tab["label"]), font_size,
		"text" if is_active else "text_faint", HORIZONTAL_ALIGNMENT_CENTER)
	# The measured size is FINAL: it was fitted to the tab's width, so the
	# factory's gain and floor (which "Achievements" cannot afford) are undone.
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.clip_text = true
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_active:
		# The label wears the glyph's hue, brightened so it still reads as text
		# against the glass rather than as a second glow.
		var g2 := IconLibrary.glow_color(icon_id)
		lbl.add_theme_color_override("font_color",
			Color.from_hsv(g2.h, clampf(g2.s * 0.72, 0.0, 1.0), clampf(maxf(g2.v, 0.86), 0.0, 1.0)))
	col.add_child(lbl)

	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	btn.pressed.connect(func(): _on_tab_pressed(tab, holder))
	holder.add_child(btn)
	UI.wire_press(holder, btn)
	return holder

func _on_tab_pressed(tab: Dictionary, holder: Control) -> void:
	AudioManager.play_sfx("button_tap", 0.04)
	Haptics.light()
	# Tapping the tab you are already on is a no-op, not a reload: a crossfade
	# back into the same screen throws away scroll position and any in-flight
	# entrance for nothing. It still answers the touch.
	if String(tab["id"]) == active_tab:
		if is_instance_valid(holder):
			holder.pivot_offset = holder.size * 0.5
			var t := holder.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			t.tween_property(holder, "scale", Vector2(1.08, 1.08), DesignSystem.DUR_INSTANT)
			t.tween_property(holder, "scale", Vector2.ONE, DesignSystem.DUR_FAST)
		return
	var path: String = SceneRouter.Route[String(tab["route"])]
	SceneRouter.goto(path)

## A soft white radial (opaque centre → transparent edge) for the active bloom.
func _soft_radial_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 1.0)
	t.width = 128
	t.height = 128
	return t
