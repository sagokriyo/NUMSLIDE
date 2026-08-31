class_name IdentitySheet
extends RefCounted
## IdentitySheet — the one place a player dresses their badge: name, status, aura,
## frame, nameplate, emblem effect and title.
##
## ONE component, opened by both identity destinations (the Profile tab and the
## Badge page). It used to be ~95 lines copy-pasted into each screen, which is how
## the two ended up labelling the same two controls "AVATAR COLOUR" on one page
## and "BADGE AURA" on the other — for a setting that paints the same badge on
## both.
##
## Everything it edits lives in the "profile" save section
## { name, status, avatar, frame, plate, effect, title }, so a change made from
## either page shows on both. The host screen supplies only what it wants done
## afterwards (`on_saved`, invariably its own rebuild).
##
## --- Why it is a WARDROBE and not a form ------------------------------------
##
## The decoration slots were four stacked rows of grey text pills reading
## "Laurel", "Flames", "Circuit", "Prism". Every failure of that design was the
## same failure: **the option did not show you the thing**. You could not tell a
## laurel from a prism without buying one; four rows of identical lozenges gave
## the eye nothing to land on; and the sheet grew tall enough that Save fell off
## the bottom of the screen. For slots that are SOLD, that is worse than plain —
## it is asking for gems in exchange for a word.
##
## So every option is now a picture of itself: a frame is a badge wearing that
## frame, a nameplate is a nameplate with a name on it, an aura is its own lit
## orb, an effect is a diagram of what it does (see BadgeCosmetics.effect_swatch
## — effects are pure motion and cannot be sampled in a still). Only titles stay
## text, because a title IS text.
##
## The slots are TABBED rather than stacked for a hard reason as well as a
## visual one: ModalOverlay does not scroll. Five rows of picture tiles in one
## column is a sheet taller than the screen with no way to reach its own Save
## button. One slot at a time keeps the sheet a fixed, safe height and gives each
## option room to be worth looking at.
##
## The preview is the WHOLE identity, live: the badge with its frame and effect,
## the name on its actual nameplate (typed into, and it updates as you type), and
## the title under it. A preview exists so it cannot flatter the result — so it
## shows every part the player is about to save, not just the shield.

const SECTION := "profile"

## The status line until the player writes their own — the brand line, so an
## untouched profile reads the same as it did before it had a custom status.
const DEFAULT_STATUS := "Every number, back where it belongs."

## The decoration keys `save` carries through from its `extra` argument.
const EXTRA_KEYS := ["plate", "title", "effect"]

## The wardrobe's slots, in tab order. `group` is the label the slot has always
## carried — the regression flow reads those strings, and they are also what a
## player has learned the controls are called.
const SLOTS := [
	{"id": "aura", "tab": "Aura", "group": "BADGE AURA"},
	{"id": "frame", "tab": "Frame", "group": "BADGE FRAME"},
	{"id": "plate", "tab": "Plate", "group": "NAMEPLATE"},
	{"id": "effect", "tab": "Effect", "group": "EMBLEM EFFECT"},
	{"id": "title", "tab": "Title", "group": "TITLE"},
]

## The saved status, or the default line. Shared so the two pages that print a
## status and the sheet that edits it can't disagree about the empty case.
static func status_text() -> String:
	var s := String(profile().get("status", "")).strip_edges()
	return s if not s.is_empty() else DEFAULT_STATUS

static func profile() -> Dictionary:
	return SaveManager.get_section(SECTION, {"name": "Player", "avatar": -1})

## Opens the sheet over `host`. `on_saved` fires after the section is written.
static func open(host: Node, on_saved: Callable) -> ModalOverlay:
	var w := Wardrobe.new()
	# An inner class cannot see the outer class by its class_name — that is a
	# COMPILE error, not a failed lookup — so the sheet hands its own script down
	# rather than the wardrobe reaching up for it. Same shape the regression
	# suites use to reach a class that is not registered when they compile.
	w.api = load("res://ui/components/identity_sheet.gd")
	return w.build(host, on_saved)

## Writes the edited identity back to the save.
##
## The three decoration slots arrive in a DICTIONARY rather than as three more
## optional parameters, because "" is a real value for a title — it means no
## title — and so cannot also mean "the caller did not mention it". A key that is
## absent is left exactly as it was; a key that is present is written, empty or
## not. That is what lets a four-argument call (every caller that predates the
## decorations, and the suites pinning the name/status/aura contract) edit what
## it names without stripping the frame, plate and title off the badge on its
## way past.
static func save(name_text: String, status_text_in: String, avatar: int, frame: int,
		extra: Dictionary = {}) -> void:
	var p := profile()
	var clean_name := name_text.strip_edges()
	p["name"] = clean_name if not clean_name.is_empty() else "Player"
	# An empty status clears back to the default line (not an empty quote).
	var clean_status := status_text_in.strip_edges()
	p["status"] = "" if clean_status == DEFAULT_STATUS else clean_status
	p["avatar"] = avatar
	p["frame"] = frame
	for key: String in EXTRA_KEYS:
		if extra.has(key):
			p[key] = extra[key]
	SaveManager.set_section(SECTION, p)

# =============================================================================
# SHARED SHAPES
# =============================================================================
## One labelled group: its eyebrow and its control, added as a SINGLE child so
## the modal's between-groups air can't open up between a label and the thing it
## labels.
static func _group(eyebrow: String, control: Control) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))
	box.add_child(_group_label(eyebrow))
	box.add_child(control)
	return box

static func _group_label(text: String) -> Label:
	var ey := UI.label(text, DesignSystem.TYPE_CAPTION, "text_dim")
	# AUTOWRAP_OFF: UI.label wraps by default, and inside a flow container a
	# wrapping label's minimum width collapses to one character — which is exactly
	# how the frame pills came out reading vertically, one letter per line.
	ey.autowrap_mode = TextServer.AUTOWRAP_OFF
	return ey

static func _field_box(focused: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeManager.color("control")
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_MD))
	sb.set_border_width_all(2)
	sb.border_color = ThemeManager.color("accent") if focused \
		else ThemeManager.color("control_stroke")
	sb.content_margin_left = DesignSystem.SPACE_MD
	sb.content_margin_right = DesignSystem.SPACE_MD
	sb.content_margin_top = DesignSystem.SPACE_SM
	sb.content_margin_bottom = DesignSystem.SPACE_SM
	sb.anti_aliasing = true
	return sb

# =============================================================================
# THE WARDROBE
# =============================================================================
## One open sheet, as an object rather than as a stack of nested closures.
##
## The sheet has real state — five equipped slots, a live preview, an active tab,
## and a tile grid rebuilt on every pick and every purchase. Threading that
## through captured lambdas is how the first version ended up passing four
## parallel arrays of repaint callables around, and it is not a shape a sixth
## slot could have been added to.
##
## Held alive by the modal (`set_meta`), so it lives exactly as long as the sheet
## it drives.
class Wardrobe extends RefCounted:
	## The IdentitySheet script itself: the shared save/profile/status helpers and
	## the SLOTS table. Set by open() before build().
	var api: Variant

	## The badge in the preview, and the picture tiles under it. Title cells are
	## wider and shorter because a title is words, not a picture.
	const PREVIEW_BOX := 250.0
	## The alcove is a fixed height with the badge centred in it, rather than a box
	## that shrink-wraps its column. Shrink-wrapped, the badge sat jammed against
	## the top edge with the name and the rank stacked under it, and the one thing
	## the whole sheet is about was in the corner of its own stage.
	const STAGE_H := 610.0
	## How much of the alcove's foot the name, title and rank are given. Declared
	## rather than measured because the text block is ANCHORED to the bottom edge:
	## the badge owns the full rect above it, and the two must not meet.
	const TEXT_H := 176.0
	## The preview name is the size a NAME should be — it was set at body-copy
	## scale, which made the headline of the card the least prominent thing on it.
	const NAME_SIZE := 72
	const TILE_W := 148.0
	const TILE_ART := 116.0
	const TILE_H := 190.0
	const TITLE_W := 236.0
	const TITLE_H := 104.0
	## The options area is pinned to the tallest slot, so switching tabs re-dresses
	## the badge without the Save button jumping up and down the screen under the
	## thumb that is reaching for it.
	const OPTIONS_H := 400.0

	var host: Node
	var modal: ModalOverlay
	var on_saved: Callable

	## The equipped slots, edited in place and written on Save.
	var eq := {"avatar": -1, "frame": 0, "plate": 0, "effect": 0, "title": ""}
	var tab := 0

	var tier_idx := -1
	var accent: Color = Color.WHITE

	var portrait: BadgePortrait
	var name_edit: LineEdit
	var status_edit: LineEdit
	## The preview's name area — cleared and refilled whenever the plate or the
	## typed name changes, because a nameplate WRAPS the label and cannot be
	## restyled in place.
	var name_slot: CenterContainer
	var title_lbl: Label
	var options: MarginContainer
	var meta_lbl: Label
	var gem_lbl: Label
	var tab_paints: Array = []

	func build(p_host: Node, p_on_saved: Callable) -> ModalOverlay:
		host = p_host
		on_saved = p_on_saved
		var p: Dictionary = api.profile()
		tier_idx = TierBadge.current_index(GameStats.best_mastery_ratio()["ratio"])
		accent = ThemeManager.color("accent") if tier_idx < 0 \
			else TierBadge.tier(tier_idx)["accent"]

		# Every slot is read through its OWNER rather than straight off the save,
		# so a decoration the player no longer owns opens as "none" instead of
		# being handed back by the editor that is supposed to gate it.
		eq["avatar"] = int(p.get("avatar", -1))
		eq["frame"] = TierBadge.equipped_frame(p)
		eq["plate"] = BadgeCosmetics.plate_of(p)
		eq["effect"] = BadgeCosmetics.effect_of(p)
		eq["title"] = _earned_title(String(p.get("title", "")))

		modal = ModalOverlay.new()
		# Deliberately NOT compact, and solid. Compact is for a two-line
		# confirmation; this sheet carries two text fields, and at the default
		# frost the page behind stayed legible right through the glass, behind the
		# very characters the player was typing.
		modal.solid = true
		# ONE line. The two-line subtitle cost 50 points of a sheet that has to
		# reach its own Save button on a 16:9 screen.
		modal.set_header("Identity", "Dress your badge",
			"Everything your badge wears.")
		modal.set_meta("wardrobe", self)

		modal._col.add_child(_stage())
		name_edit = _field("YOUR NAME", String(p.get("name", "Player")),
			"Your name", 18, DesignSystem.TYPE_HEADLINE)
		# The preview follows the keystrokes. Typing a name and watching it land
		# on the plate you are choosing is the whole argument for previewing the
		# nameplate rather than the badge alone.
		name_edit.text_changed.connect(func(_t: String): _repaint_name())
		status_edit = _field("STATUS", api.status_text(),
			"Say something…", 42, DesignSystem.TYPE_BODY)

		# The stage is built BEFORE the fields (it is above them on the sheet), so
		# its first paint had no name box to read and fell back to "Player" — the
		# preview opened showing the wrong name until the first keystroke.
		_repaint_name()

		modal._col.add_child(_tab_bar())
		modal._col.add_child(_meta_row())
		options = MarginContainer.new()
		options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		options.custom_minimum_size.y = OPTIONS_H
		modal._col.add_child(options)
		_fill_options()

		modal.add_action("Save", PremiumButton.Variant.PRIMARY, func(): _commit())
		modal.add_action("Cancel", PremiumButton.Variant.GHOST, func(): modal.close())
		modal.open(host)
		return modal

	func _commit() -> void:
		api.save(name_edit.text, status_edit.text,
			int(eq["avatar"]), int(eq["frame"]),
			{"plate": int(eq["plate"]), "title": String(eq["title"]),
			"effect": int(eq["effect"])})
		modal.close()
		if on_saved.is_valid():
			on_saved.call()

	# --- The preview ----------------------------------------------------------
	## The identity as it will actually look: the badge with its frame and effect,
	## the name on its nameplate, the title beneath. On a lit stage rather than in
	## a plain well — this is the thing being bought, and it should look like it.
	func _stage() -> Control:
		var stage := PanelContainer.new()
		stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := StyleBoxFlat.new()
		# Darker than the modal's own glass: a lit alcove, not another pane.
		# Sampling the theme's bg rather than a fixed black keeps it a recess on
		# the light palettes too.
		sb.bg_color = Color(ThemeManager.color("bg0"), 0.42)
		sb.set_corner_radius_all(int(DesignSystem.RADIUS_LG))
		sb.set_border_width_all(1)
		sb.border_color = ThemeManager.color("control_stroke")
		sb.set_content_margin_all(DesignSystem.SPACE_MD)
		sb.anti_aliasing = true
		stage.add_theme_stylebox_override("panel", sb)

		# A FIXED-HEIGHT alcove with two layers, not a column.
		#
		# Stacked in a VBox — badge, then name, then title, then rank — the badge
		# is not centred in the card, it is centred in whatever the text left over,
		# which put the one thing this whole sheet is about up in the top third of
		# its own stage. So the badge gets the full rect and sits dead centre in
		# it, and the text block is anchored along the bottom edge underneath. At
		# a 250pt badge in a 520pt alcove the two cannot reach each other.
		var body := Control.new()
		body.custom_minimum_size = Vector2(0, STAGE_H)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var spot := TierBadge.accent_glow(PREVIEW_BOX,
			TierBadge.aura_color(int(eq["avatar"]), accent))
		spot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		spot.offset_left = -PREVIEW_BOX * 0.85
		spot.offset_right = PREVIEW_BOX * 0.85
		spot.offset_top = -PREVIEW_BOX * 0.72
		spot.offset_bottom = PREVIEW_BOX * 0.72
		body.add_child(spot)

		portrait = BadgePortrait.new()
		portrait.box = PREVIEW_BOX
		portrait.tier_idx = tier_idx
		portrait.frame_idx = int(eq["frame"])
		portrait.effect_idx = int(eq["effect"])
		portrait.tint = TierBadge.aura_color(int(eq["avatar"]), accent)
		# No photo in the preview: this pane is where the BADGE is dressed, and a
		# Play Games picture landing mid-edit would cover the only thing the
		# controls below it change.
		var centre := CenterContainer.new()
		centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
		centre.add_child(portrait)
		body.add_child(centre)

		var foot := VBoxContainer.new()
		foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		foot.offset_top = -TEXT_H
		foot.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))
		foot.alignment = BoxContainer.ALIGNMENT_END
		foot.mouse_filter = Control.MOUSE_FILTER_IGNORE

		name_slot = CenterContainer.new()
		name_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(name_slot)

		title_lbl = UI.label("", DesignSystem.TYPE_CAPTION, "text_dim",
			HORIZONTAL_ALIGNMENT_CENTER)
		title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		foot.add_child(title_lbl)

		# The rank is stated because the badge alone doesn't name itself, and
		# because an unranked player needs to be told that the faded shield is a
		# target rather than a failed load.
		var caption := UI.label(
			"Unranked — win a mode to earn your badge" if tier_idx < 0
			else "%s badge" % String(TierBadge.tier(tier_idx)["name"]),
			DesignSystem.TYPE_CAPTION,
			"text_faint" if tier_idx < 0 else "text_dim", HORIZONTAL_ALIGNMENT_CENTER)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(caption)
		body.add_child(foot)

		stage.add_child(body)
		_repaint_name()
		return stage

	## Repaints everything the preview shows; called after every change.
	func _repaint_preview() -> void:
		if is_instance_valid(portrait):
			portrait.tint = TierBadge.aura_color(int(eq["avatar"]), accent)
			portrait.frame_idx = int(eq["frame"])
			portrait.effect_idx = int(eq["effect"])
			portrait.rebuild()
		_repaint_name()

	## The name on its plate, plus the worn title. Rebuilt rather than restyled: a
	## nameplate wraps the label, so changing plates means changing the node tree.
	func _repaint_name() -> void:
		if not is_instance_valid(name_slot):
			return
		for c in name_slot.get_children():
			c.queue_free()
		var typed := "Player"
		if is_instance_valid(name_edit):
			typed = name_edit.text.strip_edges()
			if typed.is_empty():
				typed = "Player"
		var plate := int(eq["plate"])
		var lbl := FitLabel.make(typed, NAME_SIZE)
		# FitLabel, so an eighteen-character name comes down to fit rather than
		# drawing through the plate it is written on.
		lbl.max_width = 560.0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color",
			BadgeCosmetics.plate_ink(plate, ThemeManager.color("text")))
		if ThemeManager.display_font:
			lbl.add_theme_font_override("font", ThemeManager.display_font)
		name_slot.add_child(BadgeCosmetics.plate_for(lbl, plate, accent))
		if is_instance_valid(title_lbl):
			var def := BadgeCosmetics.title_def(String(eq["title"]))
			title_lbl.text = "" if def.is_empty() else String(def["text"]).to_upper()
			title_lbl.visible = not title_lbl.text.is_empty()

	# --- The tab bar ----------------------------------------------------------
	## Five segments on ONE track. A track rather than five loose pills because
	## these are alternatives, not five separate switches, and the shape has to
	## say so before the labels are read.
	func _tab_bar() -> Control:
		var track := PanelContainer.new()
		track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := StyleBoxFlat.new()
		sb.bg_color = ThemeManager.color("control")
		sb.set_corner_radius_all(int(DesignSystem.RADIUS_PILL))
		sb.set_border_width_all(1)
		sb.border_color = ThemeManager.color("control_stroke")
		sb.set_content_margin_all(DesignSystem.SPACE_XS)
		sb.anti_aliasing = true
		track.add_theme_stylebox_override("panel", sb)

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 0)
		tab_paints.clear()
		var slots: Array = api.SLOTS
		for i in slots.size():
			var idx := i
			var slot: Dictionary = slots[i]
			var seg := PanelContainer.new()
			seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var lbl := UI.label(String(slot["tab"]), DesignSystem.TYPE_CAPTION,
				"text_dim", HORIZONTAL_ALIGNMENT_CENTER)
			lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			seg.add_child(lbl)
			var paint := func() -> void:
				var on := tab == idx
				var box := StyleBoxFlat.new()
				box.bg_color = Color(accent, 0.30) if on else Color(0, 0, 0, 0)
				box.set_corner_radius_all(int(DesignSystem.RADIUS_PILL))
				box.set_border_width_all(1 if on else 0)
				box.border_color = Color(accent, 0.75)
				box.content_margin_top = DesignSystem.SPACE_SM
				box.content_margin_bottom = DesignSystem.SPACE_SM
				box.content_margin_left = DesignSystem.SPACE_XS
				box.content_margin_right = DesignSystem.SPACE_XS
				box.anti_aliasing = true
				seg.add_theme_stylebox_override("panel", box)
				lbl.add_theme_color_override("font_color",
					ThemeManager.color("text") if on else ThemeManager.color("text_dim"))
			paint.call()
			tab_paints.append(paint)
			UI.pass_through(seg)
			UI.make_scroll_tappable(seg, func(): _select_tab(idx))
			row.add_child(seg)
		track.add_child(row)
		return track

	func _select_tab(i: int) -> void:
		if tab == i:
			return
		tab = i
		Haptics.light()
		for p in tab_paints:
			(p as Callable).call()
		_fill_options()

	## The line between the tabs and the tiles: what this slot holds, how much of
	## it is yours, and what is in the purse. The balance sits HERE rather than in
	## the header because here is where a price is about to be read.
	func _meta_row() -> Control:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))
		meta_lbl = UI.label("", DesignSystem.TYPE_CAPTION, "text_dim")
		meta_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		meta_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meta_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(meta_lbl)

		var gem := TextureRect.new()
		gem.texture = UI.icon_tex("currency_gems")
		gem.custom_minimum_size = Vector2(34, 34)
		gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(gem)
		gem_lbl = UI.label(str(Wallet.gems()), DesignSystem.TYPE_CAPTION, "gold")
		gem_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		gem_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(gem_lbl)
		return row

	# --- The tiles ------------------------------------------------------------
	## Rebuilds the option grid for the active tab, faded in so a tab change reads
	## as the same wardrobe re-hung rather than as the sheet reloading.
	func _fill_options() -> void:
		if not is_instance_valid(options):
			return
		for c in options.get_children():
			c.queue_free()
		var flow := HFlowContainer.new()
		flow.alignment = FlowContainer.ALIGNMENT_CENTER
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override("h_separation", int(DesignSystem.SPACE_SM))
		flow.add_theme_constant_override("v_separation", int(DesignSystem.SPACE_SM))
		var slots: Array = api.SLOTS
		var active: Dictionary = slots[tab]
		match String(active["id"]):
			"aura": _fill_aura(flow)
			"frame": _fill_frame(flow)
			"plate": _fill_plate(flow)
			"effect": _fill_effect(flow)
			"title": _fill_title(flow)
		# Centred in the fixed box rather than top-aligned in it. The box is sized
		# for the TALLEST slot so Save cannot move under a reaching thumb; without
		# centring, the one-row slots opened with a hole beneath them instead.
		var centre := VBoxContainer.new()
		centre.alignment = BoxContainer.ALIGNMENT_CENTER
		centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		centre.add_child(flow)
		options.add_child(centre)
		flow.modulate.a = 0.0
		var tw := flow.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(flow, "modulate:a", 1.0, DesignSystem.DUR_BASE)
		if is_instance_valid(gem_lbl):
			gem_lbl.text = str(Wallet.gems())

	## "9 FRAMES · 3 OWNED", "9 TITLES · 6 EARNED", or a bare count for a slot
	## where everything is simply available.
	##
	## `verb` is the difference between bought and won, and it has to be stated:
	## the title tab shows only what has been earned, so a bare "9 TITLES" printed
	## over six cards reads as three of them having failed to load.
	func _set_meta(noun: String, total: int, have: int, verb: String) -> void:
		if not is_instance_valid(meta_lbl):
			return
		if verb.is_empty():
			meta_lbl.text = "%d %s" % [total, noun.to_upper()]
		else:
			meta_lbl.text = "%d %s · %d %s" % [total, noun.to_upper(), have, verb]

	func _fill_aura(flow: HFlowContainer) -> void:
		var opts: Array = [-1]
		for i in TierBadge.AURAS.size():
			opts.append(i)
		for o in opts:
			var idx := int(o)
			flow.add_child(_tile(_aura_art(idx), "Auto" if idx < 0 else _aura_name(idx),
				int(eq["avatar"]) == idx, "", TILE_W, TILE_H,
				func():
					eq["avatar"] = idx
					_after_pick()))
		_set_meta("auras", opts.size(), opts.size(), "")

	func _fill_frame(flow: HFlowContainer) -> void:
		var owned := 0
		for i in TierBadge.FRAMES.size():
			var idx := i
			var cid := TierBadge.frame_cosmetic_id(i)
			if Wallet.owns_cosmetic(cid):
				owned += 1
			flow.add_child(_tile(_frame_art(i), String(TierBadge.FRAMES[i]),
				int(eq["frame"]) == i, cid, TILE_W, TILE_H,
				func():
					eq["frame"] = idx
					_after_pick()))
		_set_meta("frames", TierBadge.FRAMES.size(), owned, "OWNED")

	func _fill_plate(flow: HFlowContainer) -> void:
		var owned := 0
		for i in BadgeCosmetics.PLATES.size():
			var idx := i
			var cid := BadgeCosmetics.plate_cosmetic_id(i)
			if Wallet.owns_cosmetic(cid):
				owned += 1
			flow.add_child(_tile(_plate_art(i), String(BadgeCosmetics.PLATES[i]),
				int(eq["plate"]) == i, cid, TILE_W, TILE_H,
				func():
					eq["plate"] = idx
					_after_pick()))
		_set_meta("plates", BadgeCosmetics.PLATES.size(), owned, "OWNED")

	func _fill_effect(flow: HFlowContainer) -> void:
		var owned := 0
		for i in BadgeCosmetics.EFFECTS.size():
			var idx := i
			var cid := BadgeCosmetics.effect_cosmetic_id(i)
			if Wallet.owns_cosmetic(cid):
				owned += 1
			flow.add_child(_tile(_effect_art(i), String(BadgeCosmetics.EFFECTS[i]),
				int(eq["effect"]) == i, cid, TILE_W, TILE_H,
				func():
					eq["effect"] = idx
					_after_pick()))
		_set_meta("effects", BadgeCosmetics.EFFECTS.size(), owned, "OWNED")

	## Titles are EARNED, never sold, so this tab shows only what has been won. A
	## grid of locked titles would read as a shop shelf, and the one thing a title
	## must never look like is something you could have bought.
	func _fill_title(flow: HFlowContainer) -> void:
		var earned := BadgeCosmetics.earned_titles()
		for t: Dictionary in earned:
			var id := String(t["id"])
			flow.add_child(_tile(_title_art(t), "", String(eq["title"]) == id, "",
				TITLE_W, TITLE_H,
				func():
					eq["title"] = id
					_after_pick()))
		if earned.size() <= 1:
			var hint := UI.label("Titles are earned by playing — win a mode, hold a streak, build a star.",
				DesignSystem.TYPE_CAPTION, "text_faint", HORIZONTAL_ALIGNMENT_CENTER)
			hint.custom_minimum_size.x = 620
			flow.add_child(hint)
		_set_meta("titles", BadgeCosmetics.TITLES.size(), earned.size(), "EARNED")

	func _after_pick() -> void:
		Haptics.light()
		_repaint_preview()
		_fill_options()

	## One option, as a picture of itself.
	##
	## `cosmetic_id` decides the lock: an id EconomyRules does not price is free
	## (every "None", every shipped frame) and `Wallet.owns_cosmetic` says so —
	## which is why nothing here keeps its own list of what is free.
	##
	## Tapping a LOCKED tile does not quietly select it and leave the purchase for
	## Save to sort out. It opens the buy sheet, and only a completed purchase
	## moves the selection: an editor that lets you wear what you have not bought
	## is an editor that has to take it off you again later.
	func _tile(art: Control, caption: String, selected: bool, cosmetic_id: String,
			w: float, h: float, on_pick: Callable) -> Control:
		var owned := cosmetic_id.is_empty() or Wallet.owns_cosmetic(cosmetic_id)
		var stack := Control.new()
		stack.custom_minimum_size = Vector2(w, h)

		var cell := PanelContainer.new()
		cell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var sb := StyleBoxFlat.new()
		# "control", not "glass": these sit on a card, and on the light palettes
		# glass-on-glass is white on white (the control-surface rule).
		sb.bg_color = Color(accent, 0.20) if selected else ThemeManager.color("control")
		sb.set_corner_radius_all(int(DesignSystem.RADIUS_MD))
		sb.set_border_width_all(3 if selected else 1)
		# A locked tile wears a GOLD hairline: the same cue the price chip uses, so
		# "this one costs something" is legible before any number is read.
		var rim: Color = ThemeManager.color("control_stroke")
		if not owned:
			rim = Color(ThemeManager.color("gold"), 0.55)
		sb.border_color = accent if selected else rim
		sb.set_content_margin_all(DesignSystem.SPACE_SM)
		sb.anti_aliasing = true
		cell.add_theme_stylebox_override("panel", sb)

		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))
		var art_wrap := CenterContainer.new()
		art_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		# A locked option is shown FAINTLY, never hidden and never greyed out of
		# recognition: it is an offer, and an offer you cannot see is not one.
		art.modulate.a = 1.0 if owned else 0.62
		art_wrap.add_child(art)
		col.add_child(art_wrap)
		if not caption.is_empty():
			var cap := FitLabel.make(caption, DesignSystem.TYPE_CAPTION)
			cap.max_width = w - DesignSystem.SPACE_MD
			cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cap.add_theme_color_override("font_color",
				ThemeManager.color("text") if selected else ThemeManager.color("text_dim"))
			col.add_child(cap)
		cell.add_child(col)
		stack.add_child(cell)

		if selected:
			stack.add_child(_check_badge())
		if not owned:
			stack.add_child(_price_chip(cosmetic_id))
		# The tile is ONE tap target. Its panel, its column, its price chip and the
		# containers inside the art all default to MOUSE_FILTER_STOP, and any one
		# of them takes the tap and ends it — which is exactly how a wardrobe full
		# of beautiful, completely dead options shipped.
		UI.pass_through(stack)
		UI.make_scroll_tappable(stack, func():
			if not owned:
				_buy(cosmetic_id, on_pick)
				return
			on_pick.call())
		return stack

	## The tick on the chosen option. A border alone is a difference nobody finds
	## on a phone — the same reason the aura swatches grew a ring.
	func _check_badge() -> Control:
		const D := 40.0
		var disc := Panel.new()
		disc.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		disc.offset_left = -D - 6.0
		disc.offset_right = -6.0
		disc.offset_top = 6.0
		disc.offset_bottom = D + 6.0
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		# A DARK disc with an accent tick, not an accent disc with computed ink.
		# The accents run from near-white (Platinum) to deep violet (Infinity), and
		# a tick tuned to sit on one of those is invisible on the other — which is
		# how the first pass shipped a selection marker that read as a plain dot.
		sb.bg_color = Color(ThemeManager.color("bg0"), 0.92)
		sb.set_corner_radius_all(int(D * 0.5))
		sb.set_border_width_all(2)
		sb.border_color = accent
		sb.anti_aliasing = true
		disc.add_theme_stylebox_override("panel", sb)
		var tick := Label.new()
		tick.text = "✓"
		tick.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tick.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tick.add_theme_font_size_override("font_size", 30)
		tick.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.35))
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.add_child(tick)
		return disc

	## The price, on the tile, in gold. Not in a tooltip — there is no hover on a
	## phone — and not appended to the caption, where it read as part of the
	## decoration's name ("Laurel 45").
	func _price_chip(cosmetic_id: String) -> Control:
		const CHIP_W := 108.0
		const CHIP_H := 42.0
		var chip := PanelContainer.new()
		# TOP-RIGHT, where a selected tile puts its tick — the two states are
		# mutually exclusive, so they can share the corner. It started along the
		# bottom edge and sat directly on top of the caption, which meant a locked
		# option showed its price and hid its NAME: you could see that Laurel cost
		# 45 gems without ever learning it was called Laurel.
		chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		chip.offset_left = -CHIP_W - 6.0
		chip.offset_right = -6.0
		chip.offset_top = 6.0
		chip.offset_bottom = CHIP_H + 6.0
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(ThemeManager.color("bg0"), 0.82)
		sb.set_corner_radius_all(int(DesignSystem.RADIUS_PILL))
		sb.set_border_width_all(1)
		sb.border_color = Color(ThemeManager.color("gold"), 0.55)
		sb.anti_aliasing = true
		chip.add_theme_stylebox_override("panel", sb)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 4)
		var gem := TextureRect.new()
		gem.texture = UI.icon_tex("currency_gems")
		gem.custom_minimum_size = Vector2(26, 26)
		gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(gem)
		var price := UI.label(str(EconomyRules.cosmetic_price(cosmetic_id)),
			DesignSystem.TYPE_CAPTION, "gold")
		price.autowrap_mode = TextServer.AUTOWRAP_OFF
		price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(price)
		chip.add_child(row)
		return chip

	# --- The art in each tile -------------------------------------------------
	func _aura_name(i: int) -> String:
		const NAMES := ["Gold", "Ice", "Violet", "Rose", "Jade", "Ember"]
		return String(NAMES[i]) if i >= 0 and i < NAMES.size() else "Aura"

	## An aura as its own lit orb, which is the only honest picture of a colour
	## whose whole job is to glow.
	func _aura_art(idx: int) -> Control:
		const D := 96.0
		var col: Color = accent if idx < 0 else TierBadge.AURAS[idx]
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(D, D)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(TierBadge.accent_glow(D, col))
		var disc := Panel.new()
		disc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var pad := D * 0.16
		disc.offset_left = pad; disc.offset_top = pad
		disc.offset_right = -pad; disc.offset_bottom = -pad
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(int(D * 0.5))
		sb.set_border_width_all(2)
		sb.border_color = Color(1, 1, 1, 0.42)
		sb.anti_aliasing = true
		disc.add_theme_stylebox_override("panel", sb)
		holder.add_child(disc)
		# The AUTOMATIC swatch means "follow my theme and rank", so it is painted
		# in whatever the accent currently is — which on a gold theme makes it
		# identical to the gold swatch beside it. A hollow centre marks it as the
		# automatic one, so the two are never the same object in the same colour.
		if idx < 0:
			var hole := Panel.new()
			hole.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			hole.offset_left = -18; hole.offset_top = -18
			hole.offset_right = 18; hole.offset_bottom = 18
			hole.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var hb := StyleBoxFlat.new()
			hb.bg_color = Color(0, 0, 0, 0)
			hb.set_corner_radius_all(18)
			hb.set_border_width_all(3)
			hb.border_color = Color(1, 1, 1, 0.9)
			hb.anti_aliasing = true
			hole.add_theme_stylebox_override("panel", hb)
			holder.add_child(hole)
		return holder

	## A frame is a badge WEARING that frame. The ornaments reach 22% outside the
	## badge box (TierBadge.FRAME_PAD), so the shield is sized to leave them room
	## inside the tile rather than being drawn as large as the cell allows.
	func _frame_art(i: int) -> Control:
		const BADGE := 78.0
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(TILE_ART, TILE_ART)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var inner := Control.new()
		inner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		inner.offset_left = -BADGE * 0.5; inner.offset_right = BADGE * 0.5
		inner.offset_top = -BADGE * 0.5; inner.offset_bottom = BADGE * 0.5
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var view := TierBadge.make_view(BADGE, maxi(tier_idx, 0), tier_idx < 0)
		view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		view.custom_minimum_size = Vector2.ZERO
		inner.add_child(view)
		TierBadge.add_frame(inner, BADGE, i, TierBadge.aura_color(int(eq["avatar"]), accent))
		holder.add_child(inner)
		return holder

	## A nameplate with a name on it — the only honest picture of a nameplate.
	func _plate_art(i: int) -> Control:
		var lbl := UI.label("Name", DesignSystem.TYPE_CAPTION, "text",
			HORIZONTAL_ALIGNMENT_CENTER)
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		lbl.add_theme_color_override("font_color",
			BadgeCosmetics.plate_ink(i, ThemeManager.color("text")))
		if ThemeManager.display_font:
			lbl.add_theme_font_override("font", ThemeManager.display_font)
		var holder := CenterContainer.new()
		holder.custom_minimum_size = Vector2(TILE_ART, TILE_ART)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var plate := BadgeCosmetics.plate_for(lbl, i, accent)
		plate.custom_minimum_size = Vector2(TILE_ART - 4.0, 58.0)
		holder.add_child(plate)
		return holder

	## The badge, with a DIAGRAM of the effect over it. An effect is pure motion,
	## so a sample of one is a coin toss between "half a particle" and "nothing" —
	## and under reduce-motion it is always nothing. See effect_swatch.
	func _effect_art(i: int) -> Control:
		const BADGE := 72.0
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(TILE_ART, TILE_ART)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var view := TierBadge.make_view(BADGE, maxi(tier_idx, 0), tier_idx < 0)
		view.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		view.custom_minimum_size = Vector2.ZERO
		view.offset_left = -BADGE * 0.5; view.offset_right = BADGE * 0.5
		view.offset_top = -BADGE * 0.5; view.offset_bottom = BADGE * 0.5
		holder.add_child(view)
		var sw := BadgeCosmetics.effect_swatch(TILE_ART, i,
			TierBadge.aura_color(int(eq["avatar"]), accent))
		sw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.add_child(sw)
		return holder

	## A title is text, so its picture is the words — set in the display face at
	## the size they will actually be worn.
	func _title_art(t: Dictionary) -> Control:
		var lbl := FitLabel.make(String(t["text"]), DesignSystem.TYPE_LABEL)
		lbl.max_width = TITLE_W - DesignSystem.SPACE_LG
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", ThemeManager.color("text"))
		if ThemeManager.display_font:
			lbl.add_theme_font_override("font", ThemeManager.display_font)
		var holder := CenterContainer.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(lbl)
		return holder

	# --- Buying ---------------------------------------------------------------
	## The buy sheet for one locked decoration: what it is, what it costs, what is
	## in the purse. `on_bought` fires ONLY on a completed purchase.
	##
	## `Wallet.buy_cosmetic` is the sole authority on whether it happened — its
	## return value is checked, never assumed. An ignored false here is a
	## decoration equipped for free, which is the unpaid-feature bug in its purest
	## form.
	func _buy(cosmetic_id: String, on_bought: Callable) -> void:
		if host == null or not is_instance_valid(host):
			return
		var price := EconomyRules.cosmetic_price(cosmetic_id)
		var name_text := String(BadgeCosmetics.priced_catalogue().get(cosmetic_id, "Decoration"))
		var have := Wallet.gems()
		var m := ModalOverlay.new()
		m.compact = true
		if have < price:
			m.set_header("Locked", name_text,
				"Costs %d gems. You have %d.\n\nGems come from medals, constellations and streaks." % [price, have])
			m.add_action("Close", PremiumButton.Variant.GLASS, func(): m.close())
			m.open(host)
			return
		m.set_header("Unlock", name_text, "Costs %d gems. You have %d." % [price, have])
		m.add_action("Unlock", PremiumButton.Variant.PRIMARY, func():
			var bought := Wallet.buy_cosmetic(cosmetic_id)
			m.close()
			if bought:
				AudioManager.play_sfx("button_tap", 0.04)
				on_bought.call())
		m.add_action("Not now", PremiumButton.Variant.GHOST, func(): m.close())
		m.open(host)

	## The title id the player may actually wear — "" when unearned or unknown.
	func _earned_title(id: String) -> String:
		if id.is_empty():
			return ""
		var def := BadgeCosmetics.title_def(id)
		return id if not def.is_empty() and BadgeCosmetics.title_earned(def) else ""

	## A labelled text field. The box is styled here because Godot's stock LineEdit
	## lands as a hard grey slab in the middle of the app's glass — the single
	## loudest thing in the sheet was the control the player looks straight past.
	func _field(eyebrow: String, value: String, placeholder: String,
			max_len: int, font_sz: int) -> LineEdit:
		var edit := LineEdit.new()
		edit.text = value
		edit.placeholder_text = placeholder
		edit.max_length = max_len
		edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		edit.add_theme_font_size_override("font_size", font_sz)
		edit.add_theme_color_override("font_color", ThemeManager.color("text"))
		edit.add_theme_color_override("font_placeholder_color", ThemeManager.color("text_faint"))
		edit.add_theme_color_override("caret_color", ThemeManager.color("accent"))
		edit.add_theme_color_override("selection_color", Color(ThemeManager.color("accent"), 0.35))
		edit.add_theme_stylebox_override("normal", api._field_box(false))
		edit.add_theme_stylebox_override("focus", api._field_box(true))
		edit.add_theme_stylebox_override("read_only", api._field_box(false))
		modal._col.add_child(api._group(eyebrow, edit))
		return edit
