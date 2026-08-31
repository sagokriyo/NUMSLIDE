extends AppScreen
## Settings: the preferences screen, built like the rest of the app rather than
## like a phone's settings list.
##
## Top: a hero of the theme the player is WEARING: its world photograph (the
## same bake the Themes cards carry), its three colours, its name, and one
## Change pill. Below it a PanelRail (the Profile page's side rail) holds four
## short panels a tap apart: Visual, Audio, Feel, Access. Each toggle is a card
## with its own icon plate, the volume slider wears its painted icon, and the
## page has a fixed height.
##
## EVERY control writes to a real system (SettingsManager, persisted and
## broadcast; AudioManager, Haptics, ThemeManager, DesignSystem and AppScreen
## read the keys), so there are no decorative dead toggles. NOTHING about the
## account lives here: the bottom bar's Profile tab owns identity, premium,
## support, privacy and data deletion. Settings is preferences only; the one
## destructive action it keeps (reset settings) is its own.

const ThemeIds := preload("res://data/themes/theme_ids.gd")

const ICON_DIR := "res://assets/icons/painted"
## The painted tab set shipped in assets/icons/painted/settings tabs, one per panel.
const TAB_ICONS := {
	"visual": ICON_DIR + "/settings tabs/visual.png",
	"audio": ICON_DIR + "/settings tabs/Audio.png",
	"feel": ICON_DIR + "/settings tabs/feel.png",
	"access": ICON_DIR + "/settings tabs/access.png",
}
const SFX_ICON := ICON_DIR + "/settings volume sliders/sfx volume.png"
const VOLUME_ICON := ICON_DIR + "/settings volume sliders/master volume.png"
const MUTED_ICON := ICON_DIR + "/settings volume sliders/muted state.png"
const AMBIENT_ICON := ICON_DIR + "/settings volume sliders/ambient volume.png"
## One painted icon per ambience loop, named after the loop's display name
## (AudioManager.MUSIC_NAMES: "white noise.png"); the Off chip wears the muted
## speaker from the slider set.
const PRESET_ICON_DIR := ICON_DIR + "/settings ambience presets"
## The glass icons the plates wear where no painted PNG covers the setting:
## IconLibrary ids, drawn in their own colours by _png() like the PNGs are.
const THEMES_GLASS := "nav_themes"     ## the Themes brush, for the theme card
const MOTION_GLASS := "restart"        ## turning arrows, for the moving backdrop
const HAPTIC_GLASS := "day_streak"     ## the flame, for vibration
const CLOCK_GLASS := "longest_session" ## the clock, for reduce motion

## Designed sizes. Icons go through DesignSystem.icon() and type through
## DesignSystem.type() at the point of use.
const HERO_H := 264.0        ## the theme hero's height
const PLATE := 76.0          ## the icon plate beside a control
const PLATE_ICON := 48.0
const SLIDER_ICON := 52.0
const SLIDER_H := 60.0       ## the slider's hit band
const SEGMENT_H := 72.0      ## one segment of a segmented picker
const KNOB := 48             ## the slider grabber's diameter
const CHIP_H := 64.0         ## an ambience chip
const CHIP_ICON := 36.0

## Vibration strength: the multiplier Haptics applies to every buzz.
const _HAPTIC_OPTS := [
	{"label": "Light", "value": "light"},
	{"label": "Medium", "value": "medium"},
	{"label": "Strong", "value": "strong"},
]

## Animation speed: DesignSystem scales its motion durations by this.
const _SPEED_OPTS := [
	{"label": "Slow", "value": "slow"},
	{"label": "Normal", "value": "normal"},
	{"label": "Fast", "value": "fast"},
]

var _rail: PanelRail
## The rail tab the reader had open, kept across the rebuilds a theme change or
## a reset triggers so the page never snaps back to the first panel.
var _open_tab := 0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
## TEST HOOK. Opens a rail tab by its label so a probe can photograph every
## panel (tools/screen_probe.gd `--page=audio`). Unknown names are ignored.
func probe_show_page(page: String) -> void:
	if _rail == null or not is_instance_valid(_rail):
		return
	var labels := _rail.tab_labels()
	for i in labels.size():
		if String(labels[i]).to_lower() == page.to_lower():
			_rail.select(i)
			return

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
func build_content(root: VBoxContainer) -> void:
	root.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))
	root.add_child(nav_header("Settings"))

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", int(DesignSystem.SPACE_MD))
	margin.add_theme_constant_override("margin_right", int(DesignSystem.SPACE_MD))
	margin.add_theme_constant_override("margin_bottom", int(DesignSystem.SPACE_SM))
	root.add_child(margin)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	margin.add_child(col)

	col.add_child(_theme_hero())

	# The builders are deferred Callables: PanelRail re-runs the one it is
	# showing, so a panel always states current data and the other three are
	# not sitting in the tree reacting to signals they cannot show.
	_rail = PanelRail.new()
	col.add_child(_rail)
	_rail.add_tab(String(TAB_ICONS["visual"]), "Visual", _visual_panel)
	_rail.add_tab(String(TAB_ICONS["audio"]), "Audio", _audio_panel)
	_rail.add_tab(String(TAB_ICONS["feel"]), "Feel", _feel_panel)
	_rail.add_tab(String(TAB_ICONS["access"]), "Access", _access_panel)
	_rail.tab_changed.connect(func(i: int): _open_tab = i)
	_rail.select(clampi(_open_tab, 0, _rail.tab_count() - 1))

# ---------------------------------------------------------------------------
# The hero: the theme the player is wearing
# ---------------------------------------------------------------------------
## A photograph of the active theme's world edge to edge (the same bake the
## Themes cards carry), the palette's three colours, the name, and the one
## thing to do here. The whole card opens the picker; the pill just says so.
func _theme_hero() -> Control:
	var id := ThemeManager.current_id()
	var pal := ThemeManager.palette()
	var card := UI.glass_card(3) as GlassPanel
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = HERO_H
	card.content_margin = 0.0
	card.radius = DesignSystem.RADIUS_XL

	var stage := Control.new()
	stage.custom_minimum_size.y = HERO_H
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.clip_contents = true
	card.add_child(stage)

	# The theme's world, photographed: ThemePreview shows the shipped bake
	# breathing under the theme's own confetti cast, and paints the palette's
	# wash where a bake is missing, so the hero never reads as a hole.
	var world := ThemePreview.new()
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.setup(pal, id)
	UI.round_clip(world, DesignSystem.RADIUS_XL)
	# Reduce motion stills the drift; the photograph still shows.
	world.set_process(not DesignSystem.reduce_motion())
	stage.add_child(world)

	# The plate: the theme's own ground, firm only where the words sit and gone
	# by the middle of the card, so the name reads over any sky and the world
	# still shows. A heavier wash turns the photograph back into a flat card.
	var base: Color = pal["bg0"]
	var wash := TextureRect.new()
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.texture = _gradient_tex(Color(base.r, base.g, base.b, 0.80),
		Color(base.r, base.g, base.b, 0.0), Vector2(0.0, 0.5), Vector2(1.0, 0.5),
		PackedFloat32Array([0.0, 0.42, 0.78, 1.0]),
		PackedColorArray([Color(base.r, base.g, base.b, 0.80),
			Color(base.r, base.g, base.b, 0.46), Color(base.r, base.g, base.b, 0.10),
			Color(base.r, base.g, base.b, 0.0)]))
	UI.round_clip(wash, DesignSystem.RADIUS_XL)
	stage.add_child(wash)

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", int(DesignSystem.SPACE_LG))
	pad.add_theme_constant_override("margin_right", int(DesignSystem.SPACE_LG))
	pad.add_theme_constant_override("margin_top", int(DesignSystem.SPACE_MD))
	pad.add_theme_constant_override("margin_bottom", int(DesignSystem.SPACE_MD))
	stage.add_child(pad)

	var row := UI.hbox(DesignSystem.SPACE_MD)
	pad.add_child(row)
	row.add_child(_swatch_cluster(pal))

	var col := UI.vbox(DesignSystem.SPACE_XS)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	var ey := UI.label("NOW WEARING", 26, "accent")
	ey.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(ey)
	var name_lbl := UI.label(ThemeManager.theme_name(id),
		DesignSystem.TYPE_HEADLINE, "text")
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if ThemeManager.display_font:
		name_lbl.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(name_lbl)
	var cap := UI.label("%d themes to choose from" % ThemeIds.IDS.size(),
		28, "text_dim")
	cap.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(cap)

	var open_themes := func(): SceneRouter.goto(SceneRouter.Route["THEMES"])
	var btn := PremiumButton.make("Change", PremiumButton.Variant.PRIMARY)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(open_themes)
	row.add_child(btn)

	UI.make_scroll_tappable(card, open_themes)
	return card

## The palette's three colours as one overlapping cluster, drawn as one object
## rather than a row of dots.
func _swatch_cluster(pal: Dictionary) -> Control:
	const DOT := 46.0
	const STEP := 30.0
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(DOT + STEP * 2.0, DOT)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring: Color = pal["bg0"]
	var i := 0
	for key in ["gold", "accent2", "accent"]:
		var dot := PanelContainer.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.position = Vector2(STEP * float(2 - i), 0.0)
		dot.size = Vector2(DOT, DOT)
		var sb := StyleBoxFlat.new()
		sb.bg_color = pal[key]
		sb.set_corner_radius_all(int(DOT * 0.5))
		sb.set_border_width_all(3)
		sb.border_color = ring
		sb.anti_aliasing = true
		dot.add_theme_stylebox_override("panel", sb)
		holder.add_child(dot)
		i += 1
	return holder

# ---------------------------------------------------------------------------
# The panels
# ---------------------------------------------------------------------------
## Random Theme feeds ThemeManager.maybe_randomize_for_game; Tilt Parallax is
## read by AppScreen's backdrop.
func _visual_panel() -> Control:
	var box := _panel_box()
	var cards := UI.vbox(DesignSystem.SPACE_SM)
	cards.add_child(_toggle_card("Random Theme",
		"A new unlocked theme each game.",
		_png(THEMES_GLASS), "random_theme_each_game"))
	cards.add_child(_toggle_card("Tilt Parallax",
		"The backdrop moves with the phone.",
		_png(MOTION_GLASS), "tilt_parallax"))
	box.add_child(_section("Visual", cards))
	return box

## The master mute sits above the level it gates; the slider dims and locks
## while sound is off. AudioManager applies both to the SFX bus. Below it the
## ambience loops as a chip cloud over their own volume, which dims while the
## loop is Off; AudioManager cross-fades to whatever `ambience_id` says.
func _audio_panel() -> Control:
	var box := _panel_box()
	var card := _card()
	var col := UI.vbox(DesignSystem.SPACE_SM)
	card.add_child(col)
	# A tiny mutable holder lets the (earlier) toggle's callback reach the
	# (later-built) slider without reordering the card.
	var vol_ref := {"row": null}
	col.add_child(_toggle_row("Sound Effects", "", _png(VOLUME_ICON), "sound_enabled",
		func(on: bool): _apply_dim(vol_ref["row"], on)))
	col.add_child(UI.hairline(0.1))
	var vol := _slider_row("Volume", "sfx_volume", SFX_ICON)
	vol_ref["row"] = vol
	col.add_child(vol)
	_apply_dim(vol, SettingsManager.sound_enabled())
	box.add_child(_section("Audio", card))

	var amb := UI.vbox(DesignSystem.SPACE_SM)
	amb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var amb_vol := _slider_row("Ambience Volume", "ambience_volume", AMBIENT_ICON)
	amb.add_child(_ambience_cloud(func(id: String): _apply_dim(amb_vol, not id.is_empty())))
	var amb_card := _card()
	amb_card.add_child(amb_vol)
	amb.add_child(amb_card)
	_apply_dim(amb_vol, not String(SettingsManager.get_value("ambience_id")).is_empty())
	box.add_child(_section("Ambience", amb, "Background sound while you play."))
	return box

## The loops as a chip cloud: Off first, then AudioManager's catalogue in its
## own order, each chip wearing its painted icon, the chosen one lit in the
## accent. A radio restyled in place, no rebuild. `on_change` gets the new id.
func _ambience_cloud(on_change: Callable) -> Control:
	var flow := _cloud()
	var chips: Array = []
	var restyle := func(chosen: String) -> void:
		for c in chips:
			_style_chip(c["chip"], String(c["id"]) == chosen)
	var options: Array = [{"id": "", "name": "Off", "icon": MUTED_ICON}]
	for id: String in AudioManager.AMBIENCE_IDS:
		var file_name := String(AudioManager.MUSIC_NAMES.get(id, id))
		options.append({"id": id, "name": file_name.capitalize(),
			"icon": "%s/%s.png" % [PRESET_ICON_DIR, file_name]})
	for opt in options:
		var id := String(opt["id"])
		var chip := _chip(String(opt["name"]), String(opt["icon"]))
		# For tests: the id a chip stands for, so a flow can find and tap it.
		chip.set_meta("ambience_id", id)
		chips.append({"chip": chip, "id": id})
		# The tap sound and haptic come from UI._fire_tap, like every tappable.
		UI.make_scroll_tappable(chip, func():
			SettingsManager.set_value("ambience_id", id)
			restyle.call(id)
			on_change.call(id))
		flow.add_child(chip)
	restyle.call(String(SettingsManager.get_value("ambience_id")))
	return flow

## Vibration and its strength (Haptics reads both), then the animation speed
## DesignSystem scales its durations by.
func _feel_panel() -> Control:
	var box := _panel_box()
	var cards := UI.vbox(DesignSystem.SPACE_SM)

	var haptics := _card()
	var hcol := UI.vbox(DesignSystem.SPACE_SM)
	haptics.add_child(hcol)
	var str_ref := {"bar": null}
	hcol.add_child(_toggle_row("Vibration", "", _png(HAPTIC_GLASS), "haptics_enabled",
		func(on: bool):
			_apply_dim(str_ref["bar"], on)
			if on:
				Haptics.medium()))
	# A sample buzz on pick, so the player feels the strength they just chose.
	var bar := _segmented(_HAPTIC_OPTS, SettingsManager.haptic_strength(),
		func(v: String):
			SettingsManager.set_value("haptic_strength", v)
			Haptics.medium())
	str_ref["bar"] = bar
	hcol.add_child(bar)
	_apply_dim(bar, SettingsManager.haptics_enabled())
	cards.add_child(haptics)

	var speed := _card()
	var scol := UI.vbox(DesignSystem.SPACE_SM)
	speed.add_child(scol)
	var row := UI.hbox(DesignSystem.SPACE_MD)
	row.add_child(_plate(_png(String(TAB_ICONS["feel"]))))
	row.add_child(_copy("Animation Speed", ""))
	scol.add_child(row)
	scol.add_child(_segmented(_SPEED_OPTS, SettingsManager.tile_speed(),
		func(v: String): SettingsManager.set_value("tile_speed", v)))
	cards.add_child(speed)

	box.add_child(_section("Feel", cards))
	return box

## Reduce Motion (every ambient effect asks DesignSystem.reduce_motion), and the
## page's one destructive action.
func _access_panel() -> Control:
	var box := _panel_box()
	var cards := UI.vbox(DesignSystem.SPACE_SM)
	cards.add_child(_toggle_card("Reduce Motion", "", _png(CLOCK_GLASS), "reduce_motion"))
	box.add_child(_section("Accessibility", cards))
	box.add_child(_section("Reset", _reset_card()))
	return box

# ---------------------------------------------------------------------------
# Cards and rows
# ---------------------------------------------------------------------------
## A switch with a face: icon plate, title and an optional one-line reason, the
## switch on the right. `extra` runs after the setting is written.
func _toggle_row(title: String, desc: String, icon: Control, key: String,
		extra: Callable = Callable()) -> Control:
	var row := UI.hbox(DesignSystem.SPACE_MD)
	row.add_child(_plate(icon))
	row.add_child(_copy(title, desc))
	var tog := UI.switch(bool(SettingsManager.get_value(key)), func(on: bool):
		SettingsManager.set_value(key, on)
		if extra.is_valid():
			extra.call(on))
	tog.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tog)
	return row

func _toggle_card(title: String, desc: String, icon: Control, key: String,
		extra: Callable = Callable()) -> Control:
	var card := _card()
	card.add_child(_toggle_row(title, desc, icon, key, extra))
	return card

## Title + live "NN%" over a full-width slider, with its painted icon on the
## left, which swaps to the muted glyph when the slider is run to zero.
func _slider_row(title: String, key: String, icon_path: String = VOLUME_ICON) -> Control:
	var row := UI.hbox(DesignSystem.SPACE_MD)
	var icon := UI.icon_rect(icon_path, DesignSystem.icon(SLIDER_ICON), "")
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var box := UI.vbox(DesignSystem.SPACE_XS)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)

	var head := HBoxContainer.new()
	head.add_child(_title(title))
	var pct := UI.label(_pct_text(key), 32, "accent",
		HORIZONTAL_ALIGNMENT_RIGHT)
	pct.autowrap_mode = TextServer.AUTOWRAP_OFF
	pct.custom_minimum_size.x = 96
	head.add_child(pct)
	box.add_child(head)

	var sl := HSlider.new()
	sl.min_value = 0.0; sl.max_value = 1.0; sl.step = 0.01
	sl.value = float(SettingsManager.get_value(key))
	sl.custom_minimum_size = Vector2(0, SLIDER_H)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_slider(sl)
	var refresh_icon := func(v: float) -> void:
		if is_instance_valid(icon):
			icon.texture = UI.icon_tex(MUTED_ICON if v <= 0.005 else icon_path)
	sl.value_changed.connect(func(v: float):
		SettingsManager.set_value(key, v)
		if is_instance_valid(pct):
			pct.text = "%d%%" % int(round(v * 100.0))
		refresh_icon.call(v))
	# The level just set, heard once the finger lifts.
	sl.drag_ended.connect(func(_changed: bool): AudioManager.play_sfx("button_tap"))
	refresh_icon.call(sl.value)
	box.add_child(sl)
	# The slider is the row's interactive control, so _apply_dim can lock it.
	row.set_meta("interactive", [sl])
	return row

## The one destructive action: every preference back to its shipped default,
## behind a confirm. Progress (stats, scores, achievements) lives in other save
## sections and is untouched, which is exactly what the confirmation promises.
func _reset_card() -> Control:
	var card := _card()
	var col := UI.vbox(DesignSystem.SPACE_MD)
	card.add_child(col)
	col.add_child(_copy("Reset settings",
		"Sound, feel and theme go back to default. Your progress stays."))
	var btn := PremiumButton.make("Reset settings", PremiumButton.Variant.DANGER)
	btn.full_width = true
	btn.pressed.connect(_confirm_reset)
	col.add_child(btn)
	return card

func _confirm_reset() -> void:
	var m := ModalOverlay.new()
	m.set_header("Reset", "Reset all settings?",
		"Sound, feel and theme go back to default. Your stats, scores and achievements stay.")
	m.add_action("Reset", PremiumButton.Variant.DANGER, func():
		m.close()
		_reset_all_settings())
	m.add_action("Cancel", PremiumButton.Variant.GHOST, func(): m.close())
	m.open(self)

## DEFAULTS is the schema, so writing each entry back cannot drift from the
## real defaults the way a duplicated table would. The theme write lands as a
## theme change, whose queued rebuild coalesces with the one here.
func _reset_all_settings() -> void:
	for key in SettingsManager.DEFAULTS.keys():
		SettingsManager.set_value(String(key), SettingsManager.DEFAULTS[key])
	_rebuild_content()
	_toast("Settings reset", "Everything is back to its defaults.")

## Dims and locks a row (its "interactive" controls) when the master toggle it
## depends on is off: the volume under Sound Effects, the strength under
## Vibration.
func _apply_dim(box: Control, on: bool) -> void:
	if box == null or not is_instance_valid(box):
		return
	box.modulate.a = 1.0 if on else 0.4
	if box.has_meta("interactive"):
		for c in (box.get_meta("interactive") as Array):
			if not is_instance_valid(c):
				continue
			if c is Range:
				(c as Range).editable = on
			elif c is BaseButton:
				(c as BaseButton).disabled = not on

# ---------------------------------------------------------------------------
# Pieces
# ---------------------------------------------------------------------------
func _panel_box() -> VBoxContainer:
	var box := UI.vbox(DesignSystem.SPACE_LG)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box

## A glass card at CONTROL padding: the panel is narrow beside the rail, and
## card air (SPACE_LG) around a one-line switch is width the words need.
func _card(elevation: int = 2) -> GlassPanel:
	var card := UI.glass_card(elevation) as GlassPanel
	card.content_margin = DesignSystem.SPACE_MD
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return card

## A section: the accent tick and display-face eyebrow the Profile panels use,
## an accent rule, an optional one-line note, then the body.
func _section(eyebrow_text: String, body: Control, note: String = "") -> Control:
	var box := UI.vbox(DesignSystem.SPACE_SM)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := UI.hbox(DesignSystem.SPACE_SM)
	var tick := Panel.new()
	tick.custom_minimum_size = Vector2(6, 40)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = ThemeManager.color("accent")
	tsb.set_corner_radius_all(3)
	tsb.anti_aliasing = true
	tick.add_theme_stylebox_override("panel", tsb)
	header.add_child(tick)
	var ey := UI.label(eyebrow_text.to_upper(), 36, "text")
	ey.autowrap_mode = TextServer.AUTOWRAP_OFF
	ey.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ThemeManager.display_font:
		ey.add_theme_font_override("font", ThemeManager.display_font)
	header.add_child(ey)
	box.add_child(header)
	box.add_child(_accent_rule())
	if not note.is_empty():
		box.add_child(UI.label(note, 28, "text_dim"))
	box.add_child(body)
	return box

## A 2pt accent rule that fades to nothing across the panel's width.
func _accent_rule() -> Control:
	var a: Color = ThemeManager.color("accent")
	var rect := TextureRect.new()
	rect.texture = _gradient_tex(Color(a.r, a.g, a.b, 0.5), Color(a.r, a.g, a.b, 0.0),
		Vector2(0, 0), Vector2(1, 0))
	rect.custom_minimum_size.y = 2
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

## Title over an optional one-line reason, filling the row between the plate
## and the control. The title is a FitLabel: the panel beside the rail is the
## app's tightest width budget after Home, and a plain Label answers a title
## that does not fit by wrapping mid-card ("REDUCE / MOTION") while every other
## card reads on one line.
func _copy(title: String, desc: String) -> Control:
	var col := UI.vbox(2.0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(_title(title))
	if not desc.is_empty():
		# text_dim, not text_faint: faint is text lerped toward the background,
		# which on light themes washes a description to nothing on a white card.
		var d := UI.label(desc, 28, "text_dim")
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(d)
	return col

## A card title in the display face, shrinking to its floor before it would
## wrap. Expanding, so it takes the share its row hands it rather than pushing
## the switch out of the card.
func _title(text: String) -> FitLabel:
	var t := UI.fit_label(text, 34, "text",
		HORIZONTAL_ALIGNMENT_LEFT, DesignSystem.scale_type(28))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ThemeManager.display_font:
		t.add_theme_font_override("font", ThemeManager.display_font)
	return t

## The rounded plate an icon sits on, so every card leads with the same object
## whatever family its icon comes from.
func _plate(icon: Control) -> Control:
	var plate := PanelContainer.new()
	plate.custom_minimum_size = Vector2(PLATE, PLATE)
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeManager.color("control")
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_SM))
	sb.set_border_width_all(1)
	sb.border_color = ThemeManager.color("control_stroke")
	sb.anti_aliasing = true
	plate.add_theme_stylebox_override("panel", sb)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(icon)
	plate.add_child(centre)
	return plate

## A painted PNG or an IconLibrary id, in its own colours.
func _png(path: String) -> Control:
	return UI.icon_rect(path, DesignSystem.icon(PLATE_ICON), "")

func _pct_text(key: String) -> String:
	return "%d%%" % int(round(float(SettingsManager.get_value(key)) * 100.0))

# ---------------------------------------------------------------------------
# Chips
# ---------------------------------------------------------------------------
func _cloud() -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", int(DesignSystem.SPACE_SM))
	flow.add_theme_constant_override("v_separation", int(DesignSystem.SPACE_SM))
	return flow

## One chip: a painted icon and the name. Its children pass input through so
## the chip is one tap target (see UI.pass_through).
func _chip(text: String, icon_path: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.custom_minimum_size.y = CHIP_H
	var row := UI.hbox(DesignSystem.SPACE_XS)
	var ic := UI.icon_rect(icon_path, DesignSystem.icon(CHIP_ICON), "")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var lbl := UI.label(text, 30, "text")
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	chip.set_meta("label", lbl)
	chip.add_child(row)
	UI.pass_through(chip)
	return chip

## Lit = the accent at chip weight; unlit = the control surface, the same pair
## the segmented picker wears. Restyles in place so a tap answers on the frame.
func _style_chip(chip: PanelContainer, on: bool) -> void:
	var ac: Color = ThemeManager.color("accent")
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(ac.r, ac.g, ac.b, 0.20) if on else ThemeManager.color("control")
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_PILL))
	sb.set_border_width_all(1)
	sb.border_color = Color(ac.r, ac.g, ac.b, 0.70) if on else ThemeManager.color("control_stroke")
	sb.content_margin_left = DesignSystem.SPACE_SM
	sb.content_margin_right = DesignSystem.SPACE_MD
	sb.content_margin_top = DesignSystem.SPACE_XS
	sb.content_margin_bottom = DesignSystem.SPACE_XS
	sb.anti_aliasing = true
	chip.add_theme_stylebox_override("panel", sb)
	var lbl: Label = chip.get_meta("label")
	lbl.add_theme_color_override("font_color",
		UI.ink("accent") if on else ThemeManager.color("text_dim"))

## A small linear gradient texture. Two stops by default; pass `offsets` and
## `colors` for more (the hero's plate feathers in three).
func _gradient_tex(from: Color, to: Color, fill_from: Vector2, fill_to: Vector2,
		offsets: PackedFloat32Array = PackedFloat32Array(),
		colors: PackedColorArray = PackedColorArray()) -> GradientTexture2D:
	var g := Gradient.new()
	if offsets.is_empty():
		g.set_color(0, from)
		g.set_color(1, to)
	else:
		g.offsets = offsets
		g.colors = colors
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_LINEAR
	gt.fill_from = fill_from
	gt.fill_to = fill_to
	gt.width = 128
	gt.height = 4
	return gt

func _toast(title_text: String, msg: String) -> void:
	var m := ModalOverlay.new()
	m.compact = true
	m.set_header("Settings", title_text, msg)
	m.add_action("Done", PremiumButton.Variant.PRIMARY, func(): m.close())
	m.open(self)

# ---------------------------------------------------------------------------
# Segmented picker
# ---------------------------------------------------------------------------
## A rounded segmented picker: a glass bar of equal-width buttons, the active
## one filled with the accent. Restyles in place on tap (no rebuild). `opts` is
## an Array of {"label", "value"}; values are the String enums the settings hold.
func _segmented(opts: Array, current: String, on_pick: Callable) -> Control:
	var bar := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = ThemeManager.color("control")
	bg.set_corner_radius_all(int(DesignSystem.RADIUS_SM))
	bg.set_border_width_all(1)
	bg.border_color = ThemeManager.color("control_stroke")
	bg.set_content_margin_all(5)
	bar.add_theme_stylebox_override("panel", bg)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 5)
	bar.add_child(hb)

	var btns: Array = []
	var state := {"cur": current}
	var restyle := func() -> void:
		for e in btns:
			var b: Button = e["btn"]
			var active: bool = String(e["value"]) == String(state["cur"])
			for st in ["normal", "hover", "pressed", "focus"]:
				b.add_theme_stylebox_override(st, _seg_style(active))
			b.add_theme_color_override("font_color",
				_on_accent_text() if active else ThemeManager.color("text_dim"))
	for opt in opts:
		var b := Button.new()
		b.text = String(opt["label"])
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = SEGMENT_H
		b.add_theme_font_size_override("font_size", DesignSystem.type(32))
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var val := String(opt["value"])
		b.pressed.connect(func():
			state["cur"] = val
			restyle.call()
			AudioManager.play_sfx("button_tap", 0.04)
			on_pick.call(val))
		btns.append({"btn": b, "value": val})
		hb.add_child(b)
	restyle.call()
	var controls: Array = []
	for e in btns:
		controls.append(e["btn"])
	bar.set_meta("interactive", controls)
	return bar

func _seg_style(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeManager.color("accent") if active else Color(0, 0, 0, 0)
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_SM) - 4)
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	if active:
		# A soft halo of the accent lifts the selected pill off the bar.
		var ac: Color = ThemeManager.color("accent")
		sb.shadow_color = Color(ac.r, ac.g, ac.b, 0.30)
		sb.shadow_size = 6
	return sb

## Readable ink over the accent fill (dark on bright accents, white on deep ones).
func _on_accent_text() -> Color:
	return Color.BLACK if ThemeManager.color("accent").get_luminance() > 0.6 else Color.WHITE

# ---------------------------------------------------------------------------
# Slider chrome: themed track + a big round grabber, tall hit area
# ---------------------------------------------------------------------------
## The unfilled rail sits QUIETER than every other control surface in the app,
## and it is the only one that does. A slider off-state is a long thin band
## running the full width of a card: the fill weight that makes a segmented bar
## or a switch track readable reads HERE as a lit highlight drawn across the
## row. Taken as a fraction of that tone rather than a colour of its own, so the
## rail still follows the theme and still moves with any future change to it.
const _RAIL_FILL := 0.36

func _track_box(filled: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var rail: Color = ThemeManager.color("control")
	sb.bg_color = ThemeManager.color("accent") if filled \
		else Color(rail.r, rail.g, rail.b, rail.a * _RAIL_FILL)
	sb.set_corner_radius_all(6)
	sb.content_margin_top    = 8
	sb.content_margin_bottom = 8
	if not filled:
		sb.set_border_width_all(1)
		sb.border_color = ThemeManager.color("control_stroke")
	return sb

func _style_slider(sl: HSlider) -> void:
	sl.add_theme_stylebox_override("slider", _track_box(false))
	sl.add_theme_stylebox_override("grabber_area", _track_box(true))
	sl.add_theme_stylebox_override("grabber_area_highlight", _track_box(true))
	var knob := _grabber_icon(KNOB, ThemeManager.color("accent"))
	sl.add_theme_icon_override("grabber", knob)
	sl.add_theme_icon_override("grabber_highlight", knob)
	sl.add_theme_icon_override("grabber_disabled", knob)

## A soft-edged filled circle texture used as the slider knob.
func _grabber_icon(diameter: int, col: Color) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(diameter) * 0.5
	var r := c - 1.5
	for y in diameter:
		for x in diameter:
			var d := Vector2(float(x) - c + 0.5, float(y) - c + 0.5).length()
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			if a > 0.0:
				img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)
