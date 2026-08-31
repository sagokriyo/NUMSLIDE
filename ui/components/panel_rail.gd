class_name PanelRail
extends HBoxContainer
## PanelRail — a code-editor activity bar: a vertical strip of icons on the left,
## and the selected one's panel filling the space beside it.
##
## WHY, on a phone. A page with seven sections is a page nobody reads past the
## third. Profile was seven viewport-heights of scroll, so "Support & About" was
## real, reachable, and effectively invisible. The rail turns depth into breadth:
## every section is one tap from every other section, the panel never scrolls
## more than its own content, and the page has a fixed height again.
##
## Tabs are built LAZILY and only one panel is ever in the tree. That is not an
## optimisation, it is the contract: the panels hold live widgets (the shared
## CurrencyHud, a sign-in button wired to the Play Games facade), and keeping six
## of them alive so five can be hidden means five copies quietly reacting to
## every signal the visible one does.
##
## The icons keep their OWN colours. They were flattened to one hue through
## UI.icon_material, which made the rail read as a control but threw away the
## thing the icon set is for: every glyph in it is a lit gold, silver or glass
## object, and a monochrome wash turns them into six identical grey shapes the
## player has to read the label to tell apart. The active tab is lifted by
## ALPHA, SCALE, its bloom and its marker instead, none of which touch the hue.
##
## EVERY TAB IS LABELLED. The first cut was icon-only, the way an editor's
## activity bar is, and that is a borrowed idiom that does not survive the move:
## an editor is a daily-use tool where five glyphs are learned once and a hover
## tooltip covers the rest. This is a page a player opens rarely, on a touch
## screen where hover does not exist — six unlabelled glyphs is a guessing game.
## BottomNav settled this for the app already: it captions every glyph, and goes
## to real trouble sizing the caption. A rail that did not would contradict the
## app's own navigation one component away.

## The strip's width, the icon in it, and the cell that holds both. RAIL_W is
## width the panels do not get, so it is the narrowest that fits the longest
## section name over two lines — measured against "Support & About", the worst
## case, not against a comfortable one.
## RAIL_W is the narrowest that fits "Membership" on ONE line at LABEL_SIZE (236
## at 36 points; it was 196 at 30) —
## below this it breaks mid-word to "Membershi / p", because AUTOWRAP_WORD_SMART
## will split inside a word rather than overflow.
##
## It is also width the PANEL does not get, and the page has a hard 982-point
## design budget (see the width note in CLAUDE.md's neighbours). This has already
## blown that budget once, and the only visible symptom was the TOP BAR'S GEAR
## being clipped — a control nowhere near the thing that caused it. Re-measure
## with `tools/profile_width_probe.tscn` on every tab before growing this or the
## panels' minimums; do not eyeball it.
const RAIL_W := 236.0
const ICON_BOX := 92.0
const ITEM_H := 208.0
## `DesignSystem.TYPE_CAPTION`, and it is a FLOOR rather than a preference.
##
## The first pass set this to 22 — below the smallest type token the design
## system defines, which is the exact trap the Shop plan caught in the energy
## countdown ("below TYPE_CAPTION... it reads as clipped"). Type smaller than the
## smallest token is not a small label, it is an unreadable one, and nothing in
## the build complains. Hardcoded rather than read from DesignSystem because a
## `const` initialiser cannot reach an autoload.
const LABEL_SIZE := 36
## The active tab's bloom, in the icon's own signature hue — BottomNav's device
## for the same job. Bounded by the cell so it can never bleed onto a neighbour.
const GLOW_BOX := 124.0
## The active marker: a bar down the item's leading edge, the signature that says
## "this rail is a selector" in every editor that has one.
const MARK_W := 5.0
const REST_ALPHA := 0.42

signal tab_changed(index: int)

## [{ "icon": String, "label": String, "build": Callable, "btn": Button,
##    "rect": TextureRect, "mark": Panel }]
var _tabs: Array = []
var _strip: VBoxContainer
var _host: ScrollContainer
## The panel currently mounted in `_host`. Held by reference so a tab swap frees
## exactly this and nothing else — `_host` also parents SmoothWheel's helper.
var _panel: Control
var _active := -1

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))

	# The strip rides on the app's own frosted glass, the same surface BottomNav
	# uses for the same job. It runs FULL HEIGHT on purpose: a short panel (Balance
	# is four lines) would otherwise leave the bottom two thirds of the screen as
	# undifferentiated void, and a rail that stops halfway down reads as content
	# that failed to load rather than as a page with room to spare.
	var shell := UI.glass_card(1)
	shell.custom_minimum_size.x = RAIL_W
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(shell)

	_strip = VBoxContainer.new()
	_strip.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))
	shell.add_child(_strip)

	# The panel is a PANE, with its own quiet ground running the full height.
	#
	# Without it a four-line section (Balance) leaves the lower half of the screen
	# as bare backdrop, and the page reads as content that failed to load rather
	# than as a section with little to say. This is the half of the editor idiom
	# that is easy to miss: the activity bar gets copied, the sidebar's own
	# background does not, and the emptiness that looks deliberate on a desktop
	# looks broken without it.
	#
	# `control`, deliberately NOT `glass`: the panels are full of frosted cards,
	# and frosted-on-frosted turns a light palette to mush. A flat ground under
	# them keeps every card's own edge readable.
	var pane := PanelContainer.new()
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var psb := StyleBoxFlat.new()
	var base: Color = ThemeManager.color("control")
	psb.bg_color = Color(base.r, base.g, base.b, base.a * 0.55)
	psb.set_corner_radius_all(int(DesignSystem.RADIUS_LG))
	psb.set_border_width_all(1)
	# Half-strength. `control_stroke` carries an accent veil on the light palettes,
	# and at full alpha the pane wore a hard blue outline beside the rail's soft
	# glass edge — two panes of the same instrument drawn in two different hands.
	# The pane needs to be FOUND, not framed.
	var edge: Color = ThemeManager.color("control_stroke")
	psb.border_color = Color(edge.r, edge.g, edge.b, edge.a * 0.5)
	psb.anti_aliasing = true
	psb.content_margin_left = DesignSystem.SPACE_SM
	psb.content_margin_right = DesignSystem.SPACE_SM
	psb.content_margin_top = DesignSystem.SPACE_SM
	psb.content_margin_bottom = DesignSystem.SPACE_SM
	pane.add_theme_stylebox_override("panel", psb)
	add_child(pane)

	# The panel scrolls, the rail does not. Owning the scroller here (rather than
	# leaving each panel to bring its own) is what keeps the rail pinned while its
	# content moves — the whole reason this beats one long page.
	_host = ScrollContainer.new()
	_host.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_host.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_host.clip_contents = true
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	SmoothWheel.attach(_host)
	pane.add_child(_host)

## Registers a tab. `build` is called the first time the tab is shown and every
## time it is re-shown — it returns the panel Control, freshly built, so a panel
## always states current data rather than whatever was true when the page opened.
func add_tab(icon_id: String, label: String, build: Callable) -> void:
	var idx := _tabs.size()

	# A Control holder rather than styling the Button: the marker has to sit at
	# the item's leading edge, outside the icon's own box, and a Button that owns
	# its whole rect cannot put anything beside itself.
	var item := Control.new()
	item.custom_minimum_size = Vector2(RAIL_W, ITEM_H)
	item.size_flags_horizontal = Control.SIZE_FILL

	# The bloom is a child of the CELL, not of the icon — parented to the icon it
	# would be positioned against a box inside the column's own layout and spill
	# out of the rail (BottomNav learned this the same way). Added first so it
	# renders behind icon and caption.
	#
	# Its POSITION is measured from where the glyph actually ends up, never
	# assumed. The first cut centred it in the cell, which is only the same place
	# as the glyph when the caption is exactly the height it was guessed to be —
	# so it sat visibly low, and lower still on the two-line tabs. Anything that
	# has to line up with a container-managed child has to ask the child.
	var glow := TextureRect.new()
	glow.texture = _bloom_tex()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.size = Vector2(GLOW_BOX, GLOW_BOX)
	var g := IconLibrary.glow_color(icon_id)
	glow.modulate = Color(g.r, g.g, g.b, 0.55)
	item.add_child(glow)

	var mark := Panel.new()
	mark.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	mark.offset_left = 0.0
	mark.offset_right = MARK_W
	mark.offset_top = ITEM_H * 0.22
	mark.offset_bottom = -ITEM_H * 0.22
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var msb := StyleBoxFlat.new()
	msb.bg_color = ThemeManager.color("accent")
	msb.set_corner_radius_all(int(MARK_W))
	msb.anti_aliasing = true
	mark.add_theme_stylebox_override("panel", msb)
	item.add_child(mark)

	# Icon over caption, centred in the cell — BottomNav's column, turned on its
	# side. A MarginContainer rather than offsets because the column is
	# container-managed and a written position is overwritten on the next layout.
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", int(MARK_W + DesignSystem.SPACE_XS))
	pad.add_theme_constant_override("margin_right", int(DesignSystem.SPACE_XS))
	item.add_child(pad)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(col)

	# FLAT, and tinted at select time. The baked glow halo would smear a coloured
	# cloud onto the neighbouring items in a column this tight, and the tint has
	# to change with selection, so neither can be resolved at build time.
	var rect := TextureRect.new()
	rect.texture = UI.icon_tex_flat(icon_id)
	rect.custom_minimum_size = Vector2(ICON_BOX, ICON_BOX)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rect)

	# The SECTION'S OWN NAME, wrapped — not a second, shorter vocabulary invented
	# to fit the rail. A short set was the obvious alternative and it fails on the
	# one that matters: "At a glance" would shorten to "Stats", which is already a
	# BottomNav destination AND the screen this very panel links out to. A rail
	# label that names a different screen is worse than a long one.
	var cap := Label.new()
	cap.text = label
	cap.add_theme_font_size_override("font_size", LABEL_SIZE)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Always two lines' worth of room, even for "Balance".
	#
	# The column is centre-aligned, so a one-line caption makes a shorter column
	# and pushes its glyph DOWN relative to a two-line neighbour's. Reserving the
	# taller box for every tab is what puts all six glyphs on one line across the
	# rail — without it the strip has a visible wobble that reads as sloppiness
	# rather than as labels of different lengths.
	cap.custom_minimum_size.y = LABEL_SIZE * 2.6
	col.add_child(cap)

	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.tooltip_text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func() -> void:
		Haptics.light()
		select(idx))
	item.add_child(btn)
	UI.wire_press(rect, btn)

	# Keep the bloom on the glyph through every relayout — a theme change, a font
	# swap, or a caption that wraps differently all move the icon inside its cell.
	var sync := func() -> void:
		if not is_instance_valid(rect) or not is_instance_valid(glow):
			return
		if not rect.is_inside_tree() or not item.is_inside_tree():
			return   # no global transform yet; `resized` will call this again
		var centre: Vector2 = rect.global_position + rect.size * 0.5 - item.global_position
		glow.position = centre - Vector2(GLOW_BOX, GLOW_BOX) * 0.5
	rect.resized.connect(sync)
	item.resized.connect(sync)
	sync.call_deferred()

	_strip.add_child(item)
	_tabs.append({"icon": icon_id, "label": label, "build": build,
		"btn": btn, "rect": rect, "cap": cap, "mark": mark, "glow": glow,
		"sync": sync})

## One soft radial, built once and shared by every tab's bloom (each tints its
## own copy via `modulate`). A gradient per tab is six textures for one shape.
static var _bloom: GradientTexture2D

static func _bloom_tex() -> GradientTexture2D:
	if _bloom == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		_bloom = GradientTexture2D.new()
		_bloom.gradient = grad
		_bloom.fill = GradientTexture2D.FILL_RADIAL
		_bloom.fill_from = Vector2(0.5, 0.5)
		_bloom.fill_to = Vector2(1.0, 0.5)
		_bloom.width = 64
		_bloom.height = 64
	return _bloom

## Shows tab `index`, rebuilding its panel. Out-of-range is a no-op rather than
## an error: the caller's tab list can shrink between a rebuild and a restore
## (the account block is a different number of rows signed in and out).
func select(index: int) -> void:
	if index < 0 or index >= _tabs.size():
		return
	_active = index
	for i in _tabs.size():
		var t: Dictionary = _tabs[i]
		var on: bool = (i == index)
		# UI.ink for the LABEL, not the raw token: `accent` and `text_dim` are
		# picked to read on a dark ground, and on the pale palettes both fall under
		# the legibility floor on this rail's own glass.
		var rect: TextureRect = t["rect"]
		# No material: the glyph paints in its own gradients. The resting tab is
		# dimmed, never recoloured.
		rect.modulate.a = 1.0 if on else REST_ALPHA
		var cap: Label = t["cap"]
		cap.add_theme_color_override("font_color",
			UI.ink("accent") if on else UI.ink("text_dim", 0.35))
		cap.modulate.a = 1.0 if on else REST_ALPHA + 0.2
		var mark: Panel = t["mark"]
		mark.visible = on
		var glow: TextureRect = t["glow"]
		glow.visible = on
		# The resting glyph sits a touch smaller, so the open tab reads as lifted
		# rather than merely lit. Pivot from the icon's own centre or it slides.
		var rest: float = 1.0 if on else 0.92
		rect.pivot_offset = rect.size * 0.5
		rect.scale = Vector2(rest, rest)
		# Scaling does not emit `resized`, and the bloom is placed from the glyph's
		# measured centre — re-run the sync or it lands on the previous scale.
		var sync: Callable = t["sync"]
		sync.call()

	# Clear the PANEL, by reference — never "every child of _host".
	#
	# The scroller is not an empty box: `SmoothWheel.attach` parents a helper node
	# to it, and a swap that frees all children takes the glide with it on the
	# very first tab. Nothing errors; wheel scrolling silently reverts to Godot's
	# hard stepping, which is the exact regression flow_smooth_scroll exists to
	# catch — and did.
	#
	# `remove_child` BEFORE `queue_free`: the old panel lives until the end of the
	# frame, and a ScrollContainer holding two children sizes itself to both, so a
	# free-only swap makes the scroll range jump for one frame on every tab.
	if _panel != null and is_instance_valid(_panel):
		_host.remove_child(_panel)
		_panel.queue_free()
	_panel = null
	var entry: Dictionary = _tabs[index]
	var build: Callable = entry["build"]
	var panel: Control = build.call() as Control
	if panel != null:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_host.add_child(panel)
		_panel = panel
		_play_in(panel)
	_host.scroll_vertical = 0   # a newly-opened panel starts at its own top
	tab_changed.emit(index)

## The incoming panel arrives rather than appearing. A swap with no transition
## reads as a redraw glitch — the eye cannot tell "new content" from "the screen
## flickered", which is most of why a paged layout can feel cheaper than a scroll.
##
## The panel's BLOCKS arrive in sequence where there are blocks to sequence. One
## flat fade of the whole pane is a slide change; a short cascade is the same
## choreography the page's own hero already plays on entry (`stagger_in` in
## profile.gd's `on_ready`), and a rail whose panels appeared differently from the
## page they live on read as two components rather than one screen. A panel that
## is a single card has nothing to cascade and keeps the plain fade — a one-item
## stagger is just a fade with a delay in front of it.
##
## FADE ONLY either way. The obvious version also slides each block in from the
## rail, but these are Container children whose positions are rewritten on the
## next layout pass, so the slide either fights the container or is silently
## discarded (the same trap documented on UI.stagger_in).
func _play_in(panel: Control) -> void:
	if SettingsManager.get_value("reduce_motion"):
		return
	var blocks := panel.get_children()
	if blocks.size() > 1:
		# The panel itself must be opaque: `stagger_in` drives each CHILD's alpha,
		# and a parent left at 0 from a previous run would hide the lot.
		panel.modulate.a = 1.0
		UI.stagger_in(blocks)
		return
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, DesignSystem.DUR_BASE) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func active() -> int:
	return _active

## The panel currently mounted, or null. For tests: an assertion about "what is on
## the page" that walks the whole screen also sweeps the rail, the top bar and
## BottomNav, and a count taken that wide cannot see one missing icon inside one
## row. This is the handle that lets a test scope itself to the open section.
func current_panel() -> Control:
	return _panel if is_instance_valid(_panel) else null

func tab_count() -> int:
	return _tabs.size()

## The tab labels, in rail order. For tests: the rail is only a rail if every
## section it claims to hold is actually reachable from it.
func tab_labels() -> Array:
	var out: Array = []
	for t_v: Variant in _tabs:
		out.append(String((t_v as Dictionary)["label"]))
	return out

## The icon id behind each tab, in rail order. For tests, and it is not a
## formality: this rail has NO labels, so a typo'd id resolves to a null texture
## and leaves an invisible button that still swallows taps. The section is then
## unreachable and the page looks like it has a gap — with nothing logged.
func tab_icons() -> Array:
	var out: Array = []
	for t_v: Variant in _tabs:
		out.append(String((t_v as Dictionary)["icon"]))
	return out
