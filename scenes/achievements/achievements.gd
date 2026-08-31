extends AppScreen
## Achievements — visual style matches the profile tier-badge system.
## Each row uses a PremiumIcon inside a colored chip, identical language to
## the medallion rail in the profile screen.
##
## THE PAGE CELEBRATES, and it is the only page in the app that has to. Unlocking
## a badge is the most triumphant thing that happens outside a board, and this
## screen used to receive one as a row quietly restyling itself while a toast
## went past somewhere above it. SceneRouter still raises that toast — it has to,
## since the unlock usually lands on the gameplay screen — but when the player is
## STANDING HERE, the medal that just came in punches, its glow lights, and the
## theme's own confetti recipe goes off over the page.
##
## The cascade and the celebration are separate contracts. The cascade is an
## entrance (once, on arrival, via `on_ready`); the celebration is reactive and
## fires whenever `Achievements.unlocked` lands while this screen is alive.
##
## LOCKED ROWS STAY DIM. `_row` paints an unearned milestone at 0.6 and that dim
## IS the information — which is why the entrance uses `UI.stagger_in`, whose
## whole contract is that each node returns to its authored alpha rather than to
## full. An entrance that ends by lighting every row erases the page's only
## at-a-glance signal.

const C_GREEN := Color("57C77A")

## The entrance / celebration targets, rebuilt with the content. A theme change
## frees every one of them, so these are cleared and refilled by `build_content`
## and nothing may hold one across a rebuild.
##
## `_medals` maps an achievement id to the CHIP BOX (art + glow), not to the
## texture: the punch scales the whole chip so the glow travels with the medal.
var _medals: Dictionary = {}
var _glows: Dictionary = {}
## Milestone rows, group headings and tier chips, in reading order, for the
## entrance cascade.
var _cards: Array[Control] = []

func nav_tab() -> String: return "achievements"

func on_ready() -> void:
	# A badge landing while the player is reading this page gets celebrated here,
	# not just in the router's toast.
	Achievements.unlocked.connect(_on_unlocked)
	# We own the entrance: the base class fades the content block as one, which
	# would run underneath the cascade as a second fade of the same pixels.
	custom_entrance = true
	content.modulate.a = 0.0
	await get_tree().process_frame
	if not is_inside_tree():
		return
	content.modulate.a = 1.0
	UI.stagger_in(_cards)
	_breathe_newest()

## The most recently earned medal keeps a slow pulse on its glow, so a page of
## two dozen rows still points at the one thing that changed. Locked badges and
## older unlocks stay perfectly still — a list where everything moves singles out
## nothing.
func _breathe_newest() -> void:
	if bool(SettingsManager.get_value("reduce_motion")):
		return
	var newest := ""
	var newest_at := 0
	for id_v: Variant in _glows.keys():
		var id := String(id_v)
		var at := Achievements.unlocked_at(id)
		if at > newest_at:
			newest_at = at
			newest = id
	if newest.is_empty():
		return
	var glow: Control = _glows[newest]
	if not is_instance_valid(glow):
		return
	var base: float = glow.modulate.a
	var tw := glow.create_tween().set_loops()
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(glow, "modulate:a", base * 1.6, 1.3)
	tw.tween_property(glow, "modulate:a", base, 1.3)

## A badge earned while this page is on screen.
##
## THE ROW HAS TO BE REBUILT FIRST. It was built LOCKED — muted medal, no glow,
## the 0.6 dim — because the page was built before the badge landed, and nothing
## else on this screen listens for an unlock. Celebrating without rebuilding
## punches a greyed-out chip and leaves the row still reading "not earned"
## underneath its own confetti. So: burst now (parented to `self`, it survives),
## rebuild, then punch the chip the rebuild creates — the one we were holding is
## freed by it.
func _on_unlocked(id: String, _def: Dictionary) -> void:
	Haptics.medium()
	AudioManager.play_sfx("victory")
	if not bool(SettingsManager.get_value("reduce_motion")):
		# Parented to `self`, not `content`: the rebuild below frees the content
		# tree and would take the burst with it mid-flight. Shop's _celebrate
		# parents the same way for the same reason.
		Confetti.celebrate(self, 150, true)

	_queue_content_rebuild()
	# One frame for the deferred rebuild, one for the layout pass that gives the
	# new chip a size to pivot around.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	# The badge just earned is by definition the newest, so the pulse moves to it
	# along with everything else the rebuild refreshed.
	_breathe_newest()

	var box: Control = _medals.get(id)
	if box == null or not is_instance_valid(box):
		return
	# Fall back to the chip's designed box if the layout pass has not landed yet:
	# a zero pivot scales the medal out of its own top-left corner.
	var span: Vector2 = box.size if box.size.x > 0.0 else box.custom_minimum_size
	box.pivot_offset = span * 0.5
	var tw := box.create_tween()
	tw.tween_property(box, "scale", Vector2(1.22, 1.22), 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(box, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func build_content(root: VBoxContainer) -> void:
	# Cleared, not appended to: a theme rebuild frees every node these point at.
	_medals.clear()
	_glows.clear()
	_cards.clear()

	root.add_child(nav_header("Achievements"))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.clip_contents  = true
	scroll.follow_focus   = false
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	SmoothWheel.attach(scroll)   # desktop wheel glides instead of stepping
	root.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", int(DesignSystem.SPACE_MD))
	margin.add_theme_constant_override("margin_right", int(DesignSystem.SPACE_MD))
	margin.add_theme_constant_override("margin_bottom", int(DesignSystem.SPACE_2XL))
	scroll.add_child(margin)

	var col := UI.vbox(DesignSystem.SPACE_MD)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(col)

	var header := _progress_header()
	col.add_child(header)
	_cards.append(header)
	# Fresh players have nothing unlocked — make the all-locked list feel inviting.
	if Achievements.unlocked_count() == 0:
		var hint := UI.caption("Win a round to earn your first one.", "text_dim")
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(hint)
	var tiers := _tiers_section()
	col.add_child(tiers)
	_cards.append(tiers)

	for group: Dictionary in _grouped_milestones():
		var ids: Array = group["ids"]
		if ids.is_empty():
			continue
		col.add_child(UI.spacer(DesignSystem.SPACE_SM, false))
		var head := _group_header(String(group["title"]), String(group["blurb"]), ids)
		col.add_child(head)
		_cards.append(head)
		for id_v: Variant in ids:
			var row := _row(String(id_v))
			col.add_child(row)
			_cards.append(row)
	col.add_child(UI.spacer(DesignSystem.SPACE_LG, false))

## The badges that are about WHO you beat, and the ones that are about showing
## up. Everything else the catalog groups by table (see _grouped_milestones);
## these two are the ids the tables do not name.
const GRADE_IDS: Array[String] = ["perfect_pace"]
const HABIT_IDS: Array[String] = ["streak_7", "streak_30"]
## Perfect Run is a way of winning rather than a board, so it files under
## Mastery beside the ten-series crowns.
const MASTERY_EXTRA_IDS: Array[String] = ["perfect_run"]

## The milestone list, split into the five things it is actually made of:
## Firsts, Modes, Mastery, Rivals and Habit.
##
## DERIVED FROM THE CATALOGS, never from a list kept here. `MODE_WIN_ACHIEVEMENT`
## and `MODE_MASTERY_ACHIEVEMENT` are already the source of truth for which badge
## a mode's first series win and its mastery hand out — reading them means a
## mode added later files its crown under the right heading with nothing on
## this screen edited, and a hand-written copy here would be one more catalogue
## to drift (exactly the failure `test_progression` exists to catch elsewhere).
## Only the handful of ids no table names (GRADE_IDS, HABIT_IDS,
## MASTERY_EXTRA_IDS) are listed by hand; anything left over is a First.
##
## Order within a group follows `ordered_ids()`, so the reading order the
## catalogue defines survives the grouping. An empty group is skipped by the
## caller.
func _grouped_milestones() -> Array[Dictionary]:
	var crowns: Array = Achievements.MODE_WIN_ACHIEVEMENT.values()
	var mastery: Array = Achievements.MODE_MASTERY_ACHIEVEMENT.values()
	var groups: Array[Dictionary] = [
		{"title": "Firsts", "blurb": "", "ids": []},
		{"title": "Boards", "blurb": "One for the first board you solve on each mode.", "ids": []},
		{"title": "Mastery", "blurb": "Solve a mode's whole ladder of boards.", "ids": []},
		{"title": "Grades", "blurb": "How far under par you came home.", "ids": []},
		{"title": "Habit", "blurb": "Come back tomorrow.", "ids": []},
	]
	for id_v: Variant in Achievements.ordered_ids():
		var id := String(id_v)
		var bucket := 0
		if mastery.has(id) or MASTERY_EXTRA_IDS.has(id):
			bucket = 2
		elif crowns.has(id):
			bucket = 1
		elif GRADE_IDS.has(id):
			bucket = 3
		elif HABIT_IDS.has(id):
			bucket = 4
		(groups[bucket]["ids"] as Array).append(id)
	return groups

## A section heading that also STATES THE SCORE for its own group. A bare eyebrow
## over sixteen rows tells the reader what the rows are; "4 / 10" tells them where
## they stand in it, which is the question they opened the page with.
func _group_header(title_text: String, blurb: String, ids: Array) -> Control:
	var got := 0
	for id_v: Variant in ids:
		if Achievements.is_unlocked(String(id_v)):
			got += 1

	var box := UI.vbox(2)
	var top := UI.hbox()
	var ey := UI.eyebrow(title_text)
	ey.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(ey)
	var count := UI.label("%d / %d" % [got, ids.size()], DesignSystem.TYPE_CAPTION,
		"accent" if got > 0 else "text_faint")
	count.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(count)
	box.add_child(top)
	if not blurb.is_empty():
		box.add_child(UI.caption(blurb, "text_faint"))
	return box

# --- Mastery tier rail (the painted shield badges) ----------------------------
func _tiers_section() -> Control:
	var card := UI.glass_card(1)
	var c := UI.vbox(int(DesignSystem.SPACE_SM))

	var top := UI.hbox()
	var ey := UI.eyebrow("Mastery Tiers")
	ey.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(ey)
	var ratio: float = GameStats.best_mastery_ratio()["ratio"]
	var count := UI.label(
		"%d / %d" % [TierBadge.unlocked_count(ratio), TierBadge.count()],
		DesignSystem.TYPE_BODY, "text")
	count.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(count)
	c.add_child(top)

	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 348
	var row := UI.hbox(int(DesignSystem.SPACE_MD))
	for i in TierBadge.count():
		row.add_child(_tier_chip(i, ratio))
	scroll.add_child(row)
	c.add_child(scroll)
	card.add_child(c)
	return card

## Each tier's "reach" line shows a clean percentage of a mode's mastery ladder
## — this rail is a general reference chart (not tied to one mode), unlike the
## Badge page's live progress line, which shows real series counts from the
## player's actual best mode.
func _tier_reach_label(tier_ratio: float) -> String:
	if tier_ratio == 1.0:
		return "100% · Mastered"
	return "%d%%" % int(round(tier_ratio * 100.0))

func _tier_chip(i: int, ratio: float) -> Control:
	var tier: Dictionary = TierBadge.tier(i)
	var tier_ratio: float = float(tier["ratio"])
	var unlocked := ratio >= tier_ratio
	var box := UI.vbox(4)
	box.custom_minimum_size.x = 248
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	var badge: Control = TierBadge.make_glowing(232, i, not unlocked)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_make_inert(badge)
	box.add_child(badge)

	var name_lbl := UI.label(String(tier["name"]), 34,
		"text" if unlocked else "text_dim", HORIZONTAL_ALIGNMENT_CENTER)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	if ThemeManager.display_font:
		name_lbl.add_theme_font_override("font", ThemeManager.display_font)
	box.add_child(name_lbl)

	var reach := UI.label(_tier_reach_label(tier_ratio), 30, "text_faint",
		HORIZONTAL_ALIGNMENT_CENTER)
	reach.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(reach)
	UI.make_scroll_tappable(box, _show_tier_modal.bind(i, ratio))
	return box

func _progress_header() -> Control:
	var card := UI.glass_card(1)
	var c := UI.vbox(DesignSystem.SPACE_SM)

	var top := UI.hbox()
	var ey := UI.eyebrow("Progress")
	ey.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(ey)
	var count := UI.label(
		"%d / %d" % [Achievements.unlocked_count(), Achievements.total_count()],
		DesignSystem.TYPE_HEADLINE, "text")
	count.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(count)
	c.add_child(top)

	var ratio := 0.0
	if Achievements.total_count() > 0:
		ratio = float(Achievements.unlocked_count()) / Achievements.total_count()
	# Filled rather than simply drawn at its value: this is the one bar on the page
	# that measures the collection as a whole, and UI.progress already owns the
	# fill (and its reduce_motion gate).
	c.add_child(UI.progress(ratio, "gold", true))
	card.add_child(c)
	return card

func _row(id: String) -> Control:
	var def := Achievements.definition(id)
	var unlocked := Achievements.is_unlocked(id)
	var hidden := bool(def.get("hidden", false)) and not unlocked

	var card := UI.glass_card(1)
	if not unlocked:
		card.modulate.a = 0.6

	var row := UI.hbox(int(DesignSystem.SPACE_LG))
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	row.add_child(_icon_chip(id, def, unlocked, hidden))

	# Text column.
	var text_col := UI.vbox(int(DesignSystem.SPACE_XS))
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	if hidden:
		var title := UI.label("Hidden Achievement", DesignSystem.TYPE_HEADLINE, "text_dim")
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		text_col.add_child(title)
		text_col.add_child(UI.caption("Keep playing to reveal this one.", "text_faint"))
	else:
		var color_key := "text" if unlocked else "text_dim"
		var title := UI.label(String(def.get("title", id)), DesignSystem.TYPE_HEADLINE, color_key)
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		if ThemeManager.display_font:
			title.add_theme_font_override("font", ThemeManager.display_font)
		text_col.add_child(title)
		text_col.add_child(UI.caption(String(def.get("detail", "")), "text_faint"))
		if unlocked:
			var when := Achievements.unlocked_at(id)
			if when > 0:
				text_col.add_child(UI.caption("Earned %s" % _format_date(when), "text_dim"))
	row.add_child(text_col)

	# Right side — check or lock.
	if unlocked:
		var check: Control = PremiumIcon.make("check", C_GREEN, 40)
		check.custom_minimum_size = Vector2(40, 40)
		check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(check)
	else:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(40, 40)
		row.add_child(spacer)

	card.add_child(row)
	UI.make_scroll_tappable(card, _show_achievement_modal.bind(id))
	return card

## Makes a decorative subtree input-transparent so taps fall through to the
## tappable card/chip underneath (a bare Control's default filter is STOP,
## which would swallow the tap right where the art is).
func _make_inert(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in c.get_children():
		if child is Control:
			_make_inert(child as Control)

func _icon_chip(id: String, def: Dictionary, unlocked: bool, is_hidden: bool) -> Control:
	const CHIP := 184.0
	# Painted medallion art (assets/images/medals/<id>.png) — same visual family
	# as the tier shields. Hidden achievements keep the anonymous chip so the
	# medal itself stays a surprise.
	if not is_hidden:
		var medal := UI.icon_tex("res://assets/images/medals/%s.png" % id)
		if medal:
			var box := Control.new()
			box.custom_minimum_size = Vector2(CHIP, CHIP)
			# The chip is what a celebration punches and what the newest-unlock
			# pulse breathes, so both are registered here — the one place that
			# knows an id and the node drawing its medal at the same time.
			_medals[id] = box
			if unlocked:
				var glow := _badge_glow(CHIP, ThemeManager.badge_accent(id))
				box.add_child(glow)
				_glows[id] = glow
			var rect := TextureRect.new()
			rect.texture = medal
			rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			if not unlocked:
				rect.self_modulate = Color(0.62, 0.65, 0.72)  # muted until earned
			box.add_child(rect)
			_make_inert(box)
			return box
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(CHIP, CHIP)
	# Registered like the medal chips above: an achievement without painted art
	# still gets celebrated. A punch that silently skipped those would read as the
	# page reacting to some badges and not others.
	_medals[id] = holder

	# The chip wears the accent of the reward theme this badge unlocks, so every
	# badge foreshadows its payout (ThemeManager.badge_accent handles fallbacks).
	var raw_col: Color = ThemeManager.badge_accent(id) if unlocked else Color("6A7080")
	var bg := GradientPanel.make(
		raw_col,
		raw_col.darkened(0.22),
		CHIP * 0.5,
		Vector2.ONE)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(bg)

	var icon_kind := "star"
	var icon_label := ""
	if not is_hidden:
		icon_kind = String(def.get("icon", "star"))
		icon_label = String(def.get("icon_label", ""))
	var icon_col := Color(1, 1, 1, 1.0) if unlocked else Color(1, 1, 1, 0.55)
	var icon: Control = PremiumIcon.make(icon_kind, icon_col, CHIP * 0.52, icon_label)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := CHIP * 0.24
	icon.offset_left  = pad
	icon.offset_top   = pad
	icon.offset_right  = -pad
	icon.offset_bottom = -pad
	holder.add_child(icon)
	_make_inert(holder)
	return holder

# --- Detail modals + small helpers --------------------------------------------

## A soft radial glow in the badge's own payout accent (TierBadge.accent_glow
## always wears the theme accent; medals wear their reward theme's).
func _badge_glow(box: float, a: Color) -> TextureRect:
	var glow := TextureRect.new()
	var gt := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(a.r, a.g, a.b, 0.38))
	grad.set_color(1, Color(a.r, a.g, a.b, 0.0))
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	glow.texture = gt
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := box * 0.10
	glow.offset_left = -pad
	glow.offset_top = -pad
	glow.offset_right = pad
	glow.offset_bottom = pad
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return glow

const _MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

func _format_date(unix: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix)
	var day: int = d["day"]
	var month: int = d["month"]
	var year: int = d["year"]
	return "%d %s %d" % [day, _MONTHS[month - 1], year]

## A large centered badge image for modals; medal aspect is 4:5 (240×300 art).
func _modal_badge(tex: Texture2D, box_h: float, glow_accent: Color, glowing: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(box_h * 0.9, box_h)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if glowing:
		holder.add_child(_badge_glow(box_h, glow_accent))
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(rect)
	return holder

func _show_achievement_modal(id: String) -> void:
	var def := Achievements.definition(id)
	var unlocked := Achievements.is_unlocked(id)
	var is_hidden := bool(def.get("hidden", false)) and not unlocked

	var m := ModalOverlay.new()
	if is_hidden:
		m.set_header("Achievement", "Hidden Achievement",
			"Keep playing to reveal this one.")
	else:
		m.set_header("Achievement", String(def.get("title", id)),
			String(def.get("detail", "")))
		var medal := UI.icon_tex("res://assets/images/medals/%s.png" % id)
		if medal:
			var accent := ThemeManager.badge_accent(id)
			var view := _modal_badge(medal, 560.0, accent, unlocked)
			if not unlocked:
				view.modulate = Color(0.62, 0.65, 0.72)
			m.add_content(view)
	if unlocked:
		var when := Achievements.unlocked_at(id)
		m.add_stat_row("Earned", _format_date(when) if when > 0 else "—")
	else:
		m.add_stat_row("Status", "Locked")
	# Every badge pays gems, so every badge says so. Shown as "pays" for one still
	# locked and "paid" for one already earned — the same fact, but the tense is
	# what tells the player whether the gems are already in their purse.
	if not is_hidden:
		m.add_stat_row("Paid" if unlocked else "Pays",
			"%d Gems" % EconomyRules.GEMS_PER_BADGE)
	m.add_action("Done", PremiumButton.Variant.GLASS, func(): m.close())
	m.open(self)

func _show_tier_modal(i: int, ratio: float) -> void:
	var tier: Dictionary = TierBadge.tier(i)
	var tier_ratio: float = float(tier["ratio"])
	var unlocked := ratio >= tier_ratio

	var m := ModalOverlay.new()
	m.set_header("Mastery Tier", String(tier["name"]), _tier_detail_text(tier_ratio))
	var view := TierBadge.make_glowing(480, i, not unlocked)
	view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	m.add_content(view)
	m.add_stat_row("Requirement", _tier_reach_label(tier_ratio))
	m.add_stat_row("Status", "Earned" if unlocked else "Locked")
	if not unlocked:
		m.add_stat_row("Your best", "%d%%" % int(round(ratio * 100.0)))
	m.add_action("Done", PremiumButton.Variant.GLASS, func(): m.close())
	m.open(self)

## Plain-language version of the difficulty-normalized mastery rule: a mode's
## ladder is the series wins it asks for (GameModes.Mode.mastery_yardstick), and
## a tier is a share of it.
func _tier_detail_text(tier_ratio: float) -> String:
	if tier_ratio < 1.0:
		return "Win %d%% of the series a mode's ladder asks for." % int(round(tier_ratio * 100.0))
	if tier_ratio == 1.0:
		return "Master any mode: win every series its ladder asks for."
	return "%s× a mode's ladder of series wins." % String.num(tier_ratio, 0)
