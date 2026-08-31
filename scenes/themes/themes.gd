extends AppScreen
## Themes — pick the mood. Themes load from data/themes/*.tres and are browsed one
## section at a time — My Themes (everything the player can wear, however it was
## opened: free, bought with gems, earned with a badge, or premium), Gem Shop and
## Premium (only what is still locked) — styled after How to Play: a tab bar up
## top jumps straight to a section, and a single Done returns to Settings. The
## split is ThemeManager.grouped_themes(); this screen only draws it.
##
## Every card IS the theme, edge to edge: the theme's own world fills the whole
## card (its baked backdrop breathing under a lightweight ThemePreview drifting
## the theme's real confetti cast), its real 4×4 tile board floats in that sky,
## and a periodic true-recipe confetti burst is thrown over the board
## (Confetti.preview). The name, the price and the status ride ON the art, on a
## plate painted in the theme's own base colour — so the card *shows* the theme
## instead of framing a small picture of one in a panel that belongs to no theme.
## Selecting one updates SettingsManager, which restyles the whole app instantly
## — and the chosen card answers with its own celebration.

## The position every mini board shows: a tray one move from home, with the top
## row already in. A board mid-solve rather than an empty one, because an empty
## grid shows a theme's sockets and nothing of its TILES, and the tiles are half
## the picture. 0 is the hole.
const MINI_CELLS: Array[int] = [
	1, 2, 3,
	4, 5, 6,
	7, 0, 8,
]
## The row that is home, lit the way the tray lights a finished band.
const MINI_LINE: Array[int] = [0, 1, 2]

## The card is one landscape window per theme: art to every edge, the name plate
## laid over the top of it, the board floating in the sky below that.
const CARD_H := 500.0
## Fraction of the card the name plate's solid ground owns at the top (it feathers
## out over half as much again below that) — see ThemePreview.plate.
const PLATE := 0.27
## Where the board's centre sits, as a fraction of the card: below the plate, not
## in the middle, or the name wash grades across its top row.
const BOARD_CENTRE := 0.655
const TILE_PX := 56.0
## Rim widths. The card's surface is only ever seen AS this rim - the stage runs
## to every edge inside it - so the border and the content margin are one number.
const RIM := 2
const RIM_SELECTED := 4

var _current_page: int = 0
var _current_cat: String = ""          # the open section by NAME — see build_content
var _visible_cats: Array = []          # [{category, ids: Array[String]}] in display order
var _inited: bool = false              # first build opens the current theme's page

var _scroll: ScrollContainer
var _saved_scroll: float = 0.0
var _restore_scroll: bool = false      # keep scroll across a selection restyle
var _suppress_anim: bool = false       # skip the entrance stagger on rebuilds
var _just_selected: bool = false       # pop the card after a selection restyle
var _current_card: Control
var _fill_gen: int = 0                 # invalidates in-flight stage streaming on rebuild
var _last_burst_ms: int = 0            # global burst spacing — one shower starts at a time

func on_ready() -> void:
	# Rebuild so premium tags + tap behaviour refresh if entitlement changes while
	# the Themes screen is open.
	EntitlementManager.premium_changed.connect(func(_p): _on_theme_changed(ThemeManager.palette()))
	# Same for reward themes: earning a badge while this screen is open (e.g. a
	# daily-streak unlock firing on resume) flips its card from locked to live.
	Achievements.unlocked.connect(func(_id, _def): _on_theme_changed(ThemeManager.palette()))

## Selecting a theme restyles the whole app (a theme change). Keep our page + the
## page's scroll position and skip the re-stagger instead of snapping to page 0.
## The scroll offset and stagger suppression are captured NOW, in-signal, while
## the old page still stands; the grid teardown + rebuild rides the base class's
## deferred, coalesced rebuild so a selection tap never pays the ~16-card
## rebuild inside the emitting call stack. (_show_page keeps its synchronous
## rebuild — that is direct navigation, not a restyle.)
func _on_theme_changed(_palette: Dictionary) -> void:
	if is_instance_valid(_scroll):
		_saved_scroll = _scroll.scroll_vertical
		_restore_scroll = true
	_suppress_anim = true
	_paint_background()
	_queue_content_rebuild()

func nav_tab() -> String: return "themes"

func build_content(root: VBoxContainer) -> void:
	root.add_child(nav_header("Themes"))

	_recompute_visible()
	# The open section is remembered by NAME, not by index: sections come and go
	# with ownership (buying the last shop theme folds Gem Shop away, premium
	# folds Premium away), and an index would land on whichever section slid
	# into that slot. A section that vanished, or a selection that MOVED (a
	# purchase lands its theme in My Themes), resolves to the page the current
	# theme now sits on — and scrolls to it, rather than restoring an offset
	# that belonged to a different page.
	var page_idx := _page_index_of(_current_cat)
	if not _inited or page_idx < 0 \
			or (_just_selected and not _page_has(page_idx, ThemeManager.current_id())):
		_inited = true
		page_idx = _page_of_current()
		_restore_scroll = false
	_current_page = clampi(page_idx, 0, maxi(0, _visible_cats.size() - 1))
	_current_cat = _cat_at(_current_page)

	root.add_child(_tab_bar())

	if _visible_cats.is_empty():
		root.add_child(UI.spacer(DesignSystem.SPACE_2XL, false))
		var empty := UI.body("No themes available.")
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(empty)
		return

	var page: Dictionary = _visible_cats[_current_page]
	var ids: Array = page["ids"]
	root.add_child(_cat_header(String(page["category"]), ids.size()))

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.clip_contents  = true
	_scroll.follow_focus   = false
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	SmoothWheel.attach(_scroll)   # desktop wheel glides instead of stepping
	root.add_child(_scroll)

	var col := UI.vbox(DesignSystem.SPACE_LG)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(col)

	var current := ThemeManager.current_id()
	var cards: Array[Control] = []
	_current_card = null
	_fill_gen += 1   # abandon any stage streaming still running from the old page
	for id in ids:
		var sid := String(id)
		var card := _preview_card(sid, sid == current)
		col.add_child(card)
		cards.append(card)
		if sid == current:
			_current_card = card
	col.add_child(UI.spacer(DesignSystem.SPACE_LG, false))
	_animate_cards_in(cards)
	_suppress_anim = false
	# The heavy stages (live ambience + a 16-tile styled board per card) stream in
	# over the next frames — building them all at once stalled the whole screen.
	_fill_stages(cards, _fill_gen)

	# A single Done button returns to Settings. Categories are browsed via the tab
	# bar above, not a wizard, so the primary action is always "Done" — never a
	# "Next" that implies more required steps after picking a theme.
	var done_btn := PremiumButton.make("Done", PremiumButton.Variant.PRIMARY)
	done_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done_btn.pressed.connect(func(): SceneRouter.back())
	root.add_child(done_btn)

	_apply_scroll_deferred()

# --- Category tabs / navigation -----------------------------------------------

func _tab_bar() -> Control:
	var row := UI.hbox(DesignSystem.SPACE_SM)
	for i in _visible_cats.size():
		var g: Dictionary = _visible_cats[i]
		row.add_child(_pill(_category_label(String(g["category"])), i == _current_page, _goto_page.bind(i)))
	# Wrap the pills in a horizontal scroller. A full row of category tabs is wider
	# than the screen; without this the row forced the whole page wider than the frame,
	# which pushed every card off the right edge. Now the extra tabs scroll instead.
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(row)
	return sc

## A compact tab pill; filled with the accent when it is the current section.
func _pill(text: String, active: bool, on_tap: Callable) -> Control:
	var pill := UI.tappable(on_tap, 0)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var accent: Color = ThemeManager.color("accent")
	var box := StyleBoxFlat.new()
	box.bg_color = accent if active else ThemeManager.color("glass")
	box.set_corner_radius_all(int(DesignSystem.RADIUS_PILL))
	box.set_border_width_all(1)
	box.border_color = accent if active else ThemeManager.color("stroke")
	box.content_margin_left = DesignSystem.SPACE_MD
	box.content_margin_right = DesignSystem.SPACE_MD
	box.content_margin_top = DesignSystem.SPACE_SM
	box.content_margin_bottom = DesignSystem.SPACE_SM
	pill.add_theme_stylebox_override("panel", box)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", DesignSystem.TYPE_LABEL)
	lbl.add_theme_color_override("font_color", _on_color(accent) if active else ThemeManager.color("text_dim"))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(lbl)
	return pill

func _goto_page(idx: int) -> void:
	if idx == _current_page:
		return
	Haptics.light()
	_show_page(idx)

## Rebuild the whole screen for a new section so the tab highlight, header, cards
## and nav all update together. Lands the scroll at the top of the new section.
func _show_page(idx: int) -> void:
	_current_page = clampi(idx, 0, maxi(0, _visible_cats.size() - 1))
	_current_cat = _cat_at(_current_page)
	_restore_scroll = false
	_suppress_anim = false
	# Through the base rebuild, not inline teardown: it clears _rebuild_pending,
	# so a restyle queued earlier this frame is absorbed instead of rebuilding
	# the freshly built page a second time at the deferred flush.
	_rebuild_content()

func _recompute_visible() -> void:
	_visible_cats = []
	for group_v in ThemeManager.grouped_themes():
		var group: Dictionary = group_v
		var ids: Array[String] = []
		for id in group["ids"]:
			ids.append(String(id))
		if ids.size() > 0:
			_visible_cats.append({"category": String(group["category"]), "ids": ids})

func _page_of_current() -> int:
	var cur := ThemeManager.current_id()
	for i in _visible_cats.size():
		if _page_has(i, cur):
			return i
	return 0

## The page index of section `cat` (-1 when it is not on offer right now).
func _page_index_of(cat: String) -> int:
	for i in _visible_cats.size():
		if _cat_at(i) == cat:
			return i
	return -1

## The section name at page `idx` ("" when out of range).
func _cat_at(idx: int) -> String:
	if idx < 0 or idx >= _visible_cats.size():
		return ""
	var g: Dictionary = _visible_cats[idx]
	return String(g["category"])

## True when theme `id` is listed on page `idx`.
func _page_has(idx: int, id: String) -> bool:
	if idx < 0 or idx >= _visible_cats.size():
		return false
	var g: Dictionary = _visible_cats[idx]
	return (g["ids"] as Array).has(id)

## Land the scroll after layout: restore the saved offset on a selection restyle,
## otherwise reveal the current theme's card. Also pops a freshly-selected card.
func _apply_scroll_deferred() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		if _restore_scroll:
			_scroll.scroll_vertical = int(_saved_scroll)
		elif is_instance_valid(_current_card):
			_scroll.ensure_control_visible(_current_card)
	_restore_scroll = false
	if _just_selected:
		_just_selected = false
		_confirm_pop(_current_card)

func _confirm_pop(card: Control) -> void:
	if not is_instance_valid(card):
		return
	card.pivot_offset = card.size / 2.0
	var tw := card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(card, "scale", Vector2(1.02, 1.02), 0.10)
	tw.tween_property(card, "scale", Vector2.ONE, 0.12)
	# The selection's answer: the newly worn theme celebrates ON its card, in its
	# own confetti, the moment it is chosen. (While this burst flies, the stage's
	# ambient beat skips — Confetti.preview never stacks showers in one layer.)
	if card.has_meta("stage_fx"):
		var fx := card.get_meta("stage_fx") as Control
		if fx != null and is_instance_valid(fx):
			var pal: Dictionary = card.get_meta("stage_pal")
			_last_burst_ms = Time.get_ticks_msec()   # the ambient beats give it air
			Confetti.preview(fx, pal, 80)

# --- Category header ----------------------------------------------------------

func _cat_header(cat: String, count: int) -> Control:
	var col := UI.vbox(int(DesignSystem.SPACE_XS))
	var top := UI.hbox()
	var lbl := Label.new()
	lbl.text = _category_label(cat).to_upper()
	lbl.add_theme_font_size_override("font_size", 48)
	lbl.add_theme_color_override("font_color", ThemeManager.color("accent"))
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ThemeManager.display_font:
		lbl.add_theme_font_override("font", ThemeManager.display_font)
	top.add_child(lbl)
	var cnt := Label.new()
	cnt.text = str(count)
	cnt.add_theme_font_size_override("font_size", DesignSystem.TYPE_LABEL)
	cnt.add_theme_color_override("font_color", ThemeManager.color("text_faint"))
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(cnt)
	col.add_child(top)
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 2)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var a: Color = ThemeManager.color("accent")
	line.color = Color(a.r, a.g, a.b, 0.30)
	col.add_child(line)
	return col

func _category_label(cat: String) -> String:
	match cat:
		"free": return "My Themes"
		"shop": return "Gem Shop"
		"premium": return "Premium"
		_: return cat.capitalize()

## A readable colour to sit ON `bg` (dark text on light fills, light on dark).
func _on_color(bg: Color) -> Color:
	return Color.BLACK if bg.get_luminance() > 0.6 else Color.WHITE

# --- Cards --------------------------------------------------------------------

## The cascade radiates from the SELECTED card, not from the top of the list:
## the screen opens scrolled to the current theme, and an index-based stagger
## left that view EMPTY for over a second on the 38-card premium page while the
## off-screen cards above it took their turns first — the "stuck cards" report.
## Capped, so the tail of a large page never waits either.
func _animate_cards_in(cards: Array[Control]) -> void:
	if _suppress_anim:
		return
	var centre := 0
	for i in cards.size():
		if cards[i] == _current_card:
			centre = i
			break
	for i in cards.size():
		var card: Control = cards[i]
		card.modulate.a = 0.0
		var delay: float = minf(float(absi(i - centre)) * 0.05, 0.35)
		card.create_tween().tween_property(card, "modulate:a", 1.0, 0.20).set_delay(delay)

func _preview_card(id: String, selected: bool) -> Control:
	var pal := ThemeManager.palette_for(id)
	var unlocked := EntitlementManager.is_theme_unlocked(id)
	var is_shop := Entitlements.theme_is_shop(id)
	var accent: Color = pal["accent"]
	var stroke: Color = pal["stroke"]
	# A SOLID card painted in THIS theme's own surface colour — deliberately not the
	# app-wide glass. A see-through card would show the *current* theme through it and
	# wreck the preview, so we build a plain panel and wire the tap directly instead
	# of UI.tappable() (which returns a GlassPanel).
	var card := PanelContainer.new()
	UI.make_scroll_tappable(card, func():
		if unlocked:
			Haptics.light()
			_just_selected = true
			SettingsManager.set_value("theme", id)
		elif is_shop:
			# Shop themes are bought with earned gems, never with money — offer the
			# purchase right here rather than routing to the paywall, which sells
			# something else entirely.
			_offer_purchase(id)
		else:
			SceneRouter.goto(SceneRouter.Route["PREMIUM"]))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Press-bounce feedback.
	card.gui_input.connect(func(e: InputEvent):
		var is_down: bool = (e is InputEventMouseButton \
			and (e as InputEventMouseButton).pressed) \
			or (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed)
		var is_up: bool = (e is InputEventMouseButton \
			and not (e as InputEventMouseButton).pressed) \
			or (e is InputEventScreenTouch and not (e as InputEventScreenTouch).pressed)
		if is_down:
			card.pivot_offset = card.size / 2.0
			var tw := card.create_tween()
			tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tw.tween_property(card, "scale", Vector2(0.98, 0.98), 0.07)
		elif is_up:
			card.pivot_offset = card.size / 2.0
			var tw := card.create_tween()
			tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tw.tween_property(card, "scale", Vector2.ONE, 0.14))

	# The card surface is only ever seen AS the rim around the art: the stage below
	# runs to every edge inside it. Selected takes a thicker accent rim plus a soft
	# accent glow; the rest a quiet stroke.
	var rim := RIM_SELECTED if selected else RIM
	var card_box := StyleBoxFlat.new()
	card_box.bg_color = pal["bg0"]
	card_box.set_corner_radius_all(int(DesignSystem.RADIUS_LG))
	card_box.set_border_width_all(rim)
	card_box.border_color = accent if selected else stroke
	card_box.set_content_margin_all(rim)
	if selected:
		card_box.shadow_color = Color(accent.r, accent.g, accent.b, 0.45)
		card_box.shadow_size = 14
	card.add_theme_stylebox_override("panel", card_box)

	# ONE stacked window rather than a column of rows. A theme is a look, and the
	# column spent most of the card on a flat panel wrapped around a small picture
	# of one; here the theme's world is the card and the words ride on it.
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(0, CARD_H)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(stack)

	# The live stage (ambience + the theme's own 16-tile board) is the expensive
	# part of a card, so it is filled LAZILY by _fill_stages into this slot. The
	# slot is added FIRST, so everything below lands ON the art rather than under
	# it, and the slot holds the card's layout exact from frame one.
	var art := Control.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(art)
	card.set_meta("stage_slot", art)
	card.set_meta("stage_pal", pal)
	card.set_meta("stage_id", id)
	card.set_meta("stage_unlocked", unlocked)
	card.set_meta("stage_rim", rim)

	# The name plate, laid over the top of the art on the ground ThemePreview.plate
	# paints for it: the theme's OWN base colour, so the theme's own text colour
	# lands on the surface that palette was designed to put it on.
	var plate := UI.vbox(int(DesignSystem.SPACE_XS))
	var head := UI.hbox(DesignSystem.SPACE_MD)
	# A FitLabel, not a wrapping one: the plate is a FIXED band of the card (the
	# board is placed just under it), so a two-line "Lantern Festival" would push
	# its own price line down across the top row of tiles. This shrinks the type
	# instead and keeps the band exactly the height it was drawn for.
	var title_label := FitLabel.make(String(pal["name"]), DesignSystem.TYPE_TITLE)
	title_label.add_theme_color_override("font_color", pal["text"])
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ThemeManager.display_font:
		title_label.add_theme_font_override("font", ThemeManager.display_font)
	head.add_child(title_label)
	# Status rides in the same row as the name, never floating loose over the art:
	# a chip anchored to its own corner sooner or later lands on top of a long
	# theme name, and one row can never do that.
	if selected:
		head.add_child(_check_pill(accent))
	elif not unlocked:
		head.add_child(_plated(_price_pill(id, accent) if is_shop else _premium_badge(accent), pal))
	plate.add_child(head)

	# A locked shop card says exactly what it costs and whether that is reachable
	# today ("40 gems. You have 25.").
	if is_shop and not unlocked:
		plate.add_child(_price_hint(id, pal))
	stack.add_child(plate)
	plate.anchor_left = 0.0
	plate.anchor_right = 1.0
	plate.anchor_top = 0.0
	plate.anchor_bottom = 0.0
	plate.offset_left = DesignSystem.SPACE_LG
	plate.offset_right = -DesignSystem.SPACE_LG
	plate.offset_top = DesignSystem.SPACE_MD
	plate.offset_bottom = CARD_H * PLATE

	# Nothing stacked on the card may swallow the card's own tap: a composite
	# tappable is exactly where a child Control ends a gesture one node short of
	# the handler, and the card then renders perfectly and does nothing.
	UI.pass_through(card)
	return card

## Wraps a bare icon+text status row in a quiet plate of the theme's own base
## colour. The row alone was legible on a flat panel; over a live sky it needs
## its own ground, or a bright cloud simply erases the price.
func _plated(inner: Control, pal: Dictionary) -> Control:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var base: Color = pal["bg0"]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(base.r, base.g, base.b, 0.72)
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_PILL))
	sb.set_border_width_all(1)
	var edge: Color = pal["stroke"]
	sb.border_color = Color(edge.r, edge.g, edge.b, 0.55)
	sb.content_margin_left = DesignSystem.SPACE_MD
	sb.content_margin_right = DesignSystem.SPACE_MD
	sb.content_margin_top = DesignSystem.SPACE_XS
	sb.content_margin_bottom = DesignSystem.SPACE_XS
	box.add_theme_stylebox_override("panel", sb)
	box.add_child(inner)
	return box

## Stream the heavy card stages in over several frames: the current theme's card
## and the first screenful land immediately, then two more cards per frame —
## hidden behind the entrance stagger, so the list feels instant instead of
## stalling while ~16 cards × (ambience + 16 styled tiles) build in one frame.
func _fill_stages(cards: Array[Control], gen: int) -> void:
	# The selected card first: the entry scroll lands on it, so it must be whole.
	if is_instance_valid(_current_card):
		_fill_stage(_current_card)
	# Stream RADIATING from the selected card, not from the top of the list —
	# the entry scroll centres on it, so its neighbours ARE the visible fold;
	# top-first order left the cards actually on screen with empty stages while
	# a dozen off-screen ones above them took their turns.
	var centre := 0
	for i in cards.size():
		if cards[i] == _current_card:
			centre = i
			break
	var order: Array = range(cards.size())
	order.sort_custom(func(a, b): return absi(int(a) - centre) < absi(int(b) - centre))
	var filled := 0
	for idx in order:
		if gen != _fill_gen or not is_inside_tree():
			return
		var card: Control = cards[idx]
		if is_instance_valid(card):
			_fill_stage(card)
		filled += 1
		# three cards land in the first frame (the visible fold), then two per frame
		if filled >= 3 and (filled - 3) % 2 == 0:
			await get_tree().process_frame

## Fill one card's stage slot with its live stage (idempotent — streaming and the
## current-card fast-path may both reach the same card).
func _fill_stage(card: Control) -> void:
	if not card.has_meta("stage_slot"):
		return
	var slot := card.get_meta("stage_slot") as Control
	card.remove_meta("stage_slot")
	if slot == null or not is_instance_valid(slot):
		return
	var pal: Dictionary = card.get_meta("stage_pal")
	# The art is inset by the card's rim, so it rounds a rim tighter than the card.
	var rim: float = float(card.get_meta("stage_rim"))
	var stage := _theme_stage(pal, String(card.get_meta("stage_id")),
		maxf(DesignSystem.RADIUS_LG - rim, 0.0))
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not bool(card.get_meta("stage_unlocked")):
		stage.modulate.a = 0.8
	slot.add_child(stage)
	# The card remembers its confetti layer so a selection can celebrate on it
	# immediately (see _confirm_pop) rather than waiting for the stage's beat.
	card.set_meta("stage_fx", stage.get_meta("fx_layer"))

## The price line under a locked shop card, told against what the player
## actually holds ("40 gems — you have 25"). Showing the shortfall rather than
## the price alone is what turns a wall into a target: the player learns how
## close they are without opening another screen.
func _price_hint(id: String, pal: Dictionary) -> Control:
	var price := Entitlements.theme_price(id)
	var have := Wallet.gems()
	var l := Label.new()
	if have >= price:
		l.text = "%d gems. You can buy this now." % price
	else:
		l.text = "%d gems. You have %d; medals pay %d." % [price, have, EconomyRules.GEMS_PER_BADGE]
	l.add_theme_font_size_override("font_size", DesignSystem.TYPE_LABEL)
	l.add_theme_color_override("font_color", pal["text_dim"])
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Tapping a locked shop card: confirm the spend, or explain the shortfall.
##
## The purchase itself goes through Wallet.buy_theme(), which is the ONLY writer
## of the owned-themes record — this screen never touches the save. On success
## the theme is applied immediately, because a player who just spent 40 gems on
## a look wants to see it, not to hunt for a second tap.
func _offer_purchase(id: String) -> void:
	var price := Entitlements.theme_price(id)
	var have := Wallet.gems()
	var title := ThemeManager.theme_name(id)
	var modal := ModalOverlay.new()
	if have < price:
		modal.set_header("Not enough gems", title,
			"%s costs %d gems. You have %d, and every medal pays %d." \
				% [title, price, have, EconomyRules.GEMS_PER_BADGE])
		modal.add_action("See Medals", PremiumButton.Variant.GLASS, func():
			modal.close()
			SceneRouter.goto(SceneRouter.Route["ACHIEVEMENTS"]))
		modal.add_action("Close", PremiumButton.Variant.GLASS, modal.close)
	else:
		modal.set_header("Buy theme", title,
			"Unlock %s forever for %d gems. You have %d." % [title, price, have])
		modal.add_action("Buy", PremiumButton.Variant.PRIMARY, func():
			modal.close()
			if Wallet.buy_theme(id):
				Haptics.medium()
				# Applying it fires theme_changed, which rebuilds this screen's
				# content for us — the theme now lists under My Themes, and
				# build_content follows the selection there (no explicit refresh
				# here, and no double rebuild).
				_just_selected = true
				SettingsManager.set_value("theme", id))
		modal.add_action("Not now", PremiumButton.Variant.GLASS, modal.close)
	modal.open(self)

## A live stage: the theme's animated ambience (ThemePreview) with the theme's
## real 4×4 board floating on top, mirroring the gameplay board-over-ambience
## look — and, every several seconds while the card is on screen, the theme
## THROWS its own confetti over the board (Confetti.preview: the same recipe
## table the live showers use, built from THIS card's palette rather than the
## wearer's). The card doesn't describe the theme's celebration — it throws it.
func _theme_stage(pal: Dictionary, id: String, radius: float) -> Control:
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, CARD_H)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var preview := ThemePreview.new()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The plate the name is read on, and the rounding that lets the art run to
	# the card's own edge without squaring off its corners.
	preview.plate = PLATE
	preview.setup(pal, id)
	UI.round_clip(preview, radius)
	stage.add_child(preview)

	# The board floats BELOW the name plate rather than in the middle of the card:
	# centred art under a caption is the composition, and a board in the dead
	# centre wears the name wash across its top row. Sized and placed by number
	# rather than by min-size preset, so it lands correctly on its very first
	# layout instead of after one.
	var board := _mini_board(pal)
	var span := TILE_PX * 3.0 + DesignSystem.SPACE_SM * 2.0
	board.anchor_left = 0.5
	board.anchor_right = 0.5
	board.anchor_top = BOARD_CENTRE
	board.anchor_bottom = BOARD_CENTRE
	board.offset_left = -span * 0.5
	board.offset_right = span * 0.5
	board.offset_top = -span * 0.5
	board.offset_bottom = span * 0.5
	stage.add_child(board)

	# The confetti layer rides OVER the board, like a victory shower over the
	# real grid; the stage's clip keeps every piece inside the card.
	var fx := Control.new()
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(fx)
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.set_meta("fx_layer", fx)

	# Self-rescheduling one-shot: a fast first burst (staggered so a fresh page
	# cascades rather than detonating in unison), then a slow beat. Off-screen
	# cards skip the spawn entirely — the timer tick is the only thing they pay.
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = randf_range(0.6, 2.4)
	timer.autostart = true
	stage.add_child(timer)
	timer.timeout.connect(func():
		var on_screen: bool = is_instance_valid(fx) \
			and fx.get_global_rect().intersects(fx.get_viewport_rect())
		# While backdrop photographs are still rendering, hold the shower —
		# a burst landing on a capture frame compounds the one hitch the screen
		# has into a visible stutter. And bursts keep 1.5s of air BETWEEN
		# cards: two showers spawning their emitters on the same frame is a
		# spike no single card would ever cost.
		if on_screen and (ThemePreview.capture_busy() \
				or Time.get_ticks_msec() - _last_burst_ms < 1500):
			timer.wait_time = randf_range(0.8, 1.6)
			timer.start()
			return
		if on_screen:
			_last_burst_ms = Time.get_ticks_msec()
			Confetti.preview(fx, pal, 34)
		timer.wait_time = randf_range(7.0, 11.0)
		timer.start())
	return stage

## The theme's real board — its tile-colour ramp, with the theme's own glow.
## One still board in a theme nobody may own yet: the theme's own sockets, the
## game's own tiles. The palette is handed in rather than read from
## ThemeManager, so a locked theme shows exactly what buying it would look like.
class MiniCell extends Control:
	var pal: Dictionary = {}
	var number: int = 0
	var row: int = 0
	var lit := false

	func _draw() -> void:
		var hw := minf(size.x, size.y) * 0.5
		if hw <= 1.0 or pal.is_empty():
			return
		var c := size * 0.5
		var bg0: Color = pal.get("bg0", Color.BLACK)
		var bg2: Color = pal.get("bg2", Color.BLACK)
		var accent: Color = pal.get("accent", Color.WHITE)
		var well := bg2.lerp(bg0, 0.45)
		# The tray's own socket: a soft rim, then the well, and a lit cell wears
		# the winning line's glow (halved on a light world, as the board does).
		var light: bool = bg0.get_luminance() > 0.5
		var glow_col: Color = TileFace.color_for(pal, BoardView.ramp_for_row(row, 3)) \
			if lit and number != 0 else accent
		var ga: float = (0.34 if lit else 0.10) * (0.5 if light else 1.0)
		var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		var tex := CandyFace.mask()
		draw_texture_rect(tex, Rect2(c - Vector2(hw, hw) * 1.07, Vector2(hw, hw) * 2.14), false,
			Color(glow_col.r, glow_col.g, glow_col.b, ga))
		var ft := well.lightened(0.11)
		var fb := well.lightened(0.05)
		var bw := hw * 0.976
		draw_polygon(PackedVector2Array([
			c + Vector2(-bw, -bw), c + Vector2(bw, -bw), c + Vector2(bw, bw), c + Vector2(-bw, bw)]),
			PackedColorArray([ft, ft, fb, fb]), uvs, tex)
		if number != 0:
			TileFace.draw_tile_for(self, pal, c, hw * 0.94, number,
				BoardView.ramp_for_row(row, 3))

func _mini_board(pal: Dictionary) -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", int(DesignSystem.SPACE_SM))
	grid.add_theme_constant_override("v_separation", int(DesignSystem.SPACE_SM))
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in MINI_CELLS.size():
		var cell := MiniCell.new()
		cell.pal = pal
		cell.number = int(MINI_CELLS[i])
		# The band is the tile's HOME row, so a stray tile keeps its own colour.
		@warning_ignore("integer_division")
		cell.row = (int(MINI_CELLS[i]) - 1) / 3 if int(MINI_CELLS[i]) > 0 else 0
		cell.lit = MINI_LINE.has(i)
		cell.custom_minimum_size = Vector2(TILE_PX, TILE_PX)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(cell)
	return grid

## Filled "✓ Selected" pill in the theme's accent.
func _check_pill(accent: Color) -> Control:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var b := StyleBoxFlat.new()
	b.bg_color = accent
	b.set_corner_radius_all(int(DesignSystem.RADIUS_PILL))
	b.content_margin_left = DesignSystem.SPACE_MD
	b.content_margin_right = DesignSystem.SPACE_MD
	b.content_margin_top = DesignSystem.SPACE_SM
	b.content_margin_bottom = DesignSystem.SPACE_SM
	pill.add_theme_stylebox_override("panel", b)
	var l := Label.new()
	l.text = "✓ Selected"
	l.add_theme_font_size_override("font_size", DesignSystem.TYPE_LABEL)
	l.add_theme_color_override("font_color", _on_color(accent))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(l)
	return pill

## Gem token + the price for a locked shop card. The gem icon is the SAME token
## the CurrencyHud wears, so "what this costs" and "what I have" are visibly the
## same currency rather than two unrelated symbols.
func _price_pill(id: String, accent: Color) -> Control:
	var row := UI.hbox(int(DesignSystem.SPACE_SM))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var gem := TextureRect.new()
	gem.texture = IconLibrary.texture("currency_gems", 34, false)
	gem.custom_minimum_size = Vector2(34, 34)
	gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(gem)
	var l := Label.new()
	l.text = str(Entitlements.theme_price(id))
	l.add_theme_font_size_override("font_size", DesignSystem.TYPE_LABEL)
	l.add_theme_color_override("font_color", accent)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	return row

## Crown + "PREMIUM" tag for locked cards (crown tinted to this theme's accent).
func _premium_badge(accent: Color) -> Control:
	var row := UI.hbox(int(DesignSystem.SPACE_SM))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tex := UI.icon_tex("res://assets/icons/crown.png")
	if tex:
		var crown := TextureRect.new()
		crown.texture = tex
		crown.custom_minimum_size = Vector2(34, 34)
		crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crown.material = UI.icon_material(accent)
		crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(crown)
	var l := Label.new()
	l.text = "PREMIUM"
	l.add_theme_font_size_override("font_size", DesignSystem.TYPE_LABEL)
	l.add_theme_color_override("font_color", accent)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	return row
