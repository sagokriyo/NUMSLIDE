extends AppScreen
## Leaderboard — one page per ranked board, side by side, each a table of players.
##
## THE DESTINATION BEHIND THE PURSE STRIP'S THIRD PILL. That slot used to hold
## the energy meter; energy is gone, and what replaced it is deliberately not a
## fourth currency but the one question the rest of the app never answers: not
## "how am I doing" (Badge) or "what are my totals" (Statistics), but WHERE DO I
## STAND — against other people.
##
## ONE PAGE PER BOARD, and never a single table of every mode. A one-round
## Daily solve and a first-to-three series against Oracle are not denominated in
## the same thing, so one table would rank whoever plays the longest mode.
## Scores only ever compare WITHIN a board, so a board is what a page is. The
## pages are `GameModes.RANKED_MODES` — Classic, Vanish and Ultimate, the Home
## trio — because those are the boards whose best series a player can read
## against each other at all. Every other mode keeps its record on Statistics.
##
## IT IS NOT A STATS PAGE. Per-mode records already live twice: Statistics owns
## the By Mode list (series played and won, the mastery bar) and Badge owns
## Mastery by Mode. Nothing here restates them — a page shows a board's PLAYERS,
## plus the one row that is the reader.
##
## IT IS NEVER BLANK, which is the constraint that shapes every state below.
## Real standings need Play Games: the plugin present, the player signed in, and
## the Play Console ids in `PlayGamesIds` filled in — and those ship EMPTY, so
## today every page falls back. The fallback is not an error card; it is the
## player's own entry, drawn from the local best series `Progression.best_score`
## holds (the exact number that mirrors to Play Games once it is configured),
## under a line saying plainly why nobody else is listed yet.

## How many player rows a page draws at most. Matches PlayGames.BOARD_PAGE_SIZE —
## asking for ten and rendering five would silently drop half the standings.
const MAX_ROWS := 10

## Podium colours for the first three ranks. Not theme colours on purpose: gold,
## silver and bronze are what a rank means everywhere, and a palette that
## recoloured them would be a palette that renamed them.
const RANK_HUES: Array[Color] = [
	Color("F4C13E"), Color("C7D2E0"), Color("D08A4E"),
]

## The widest a score may claim before it shrinks its own type instead of the
## row. Scores here are OTHER PEOPLE'S, arriving from Play Games with no ceiling
## this app controls, so the row has to be able to survive any of them.
const SCORE_SLOT := 300.0

## The save section the reader's identity lives in — the SAME one the Profile
## tab, the Badge page and the shared IdentitySheet read and write, so the name
## and the aura chosen on any of them are what this page prints and paints.
const PROFILE_SECTION := "profile"

## Edge of the square a row's picture occupies. One number for both kinds of
## picture (the reader's badge portrait and a stranger's initial disc), because
## two rows of different heights in one table read as a rendering fault.
const AVATAR := 84.0

## The pager and its pages, rebuilt with the content.
var _pager: ScrollContainer
var _pages: HBoxContainer
## mode id -> the VBox holding that page's player rows, so a reply can repaint
## one page without rebuilding the screen (which would lose the pager position).
var _bodies: Dictionary = {}
## The tab chips, restyled as the page changes.
var _tabs: Array[Control] = []
## Which board is in view. Survives the rebuild a theme change triggers, so
## switching palette does not throw the reader back to Classic.
var _page_index := 0
## Board ids still waiting on a reply, so a page can show "loading" rather than
## an empty table it is about to fill.
var _pending: Dictionary = {}
## The page slide in flight, killed before another starts.
##
## WITHOUT THIS the pager fights itself. `scroll_horizontal` is one property and
## a Tween keeps writing to it until it finishes, so tapping a second tab while
## the first slide is still running leaves TWO tweens driving it — and the older
## one, which is aiming at the previous page, wins the last frame. The pager
## ends up back where it came from after a tap that visibly started moving,
## which reads as the tab being ignored. (CurrencyHud's odometer kills its
## per-currency roll for exactly this reason.)
var _slide: Tween

func on_ready() -> void:
	# The reply can arrive after the player has swiped on, so pages are repainted
	# individually rather than by rebuilding the screen.
	PlayGames.board_loaded.connect(_on_board_loaded)

func build_content(root: VBoxContainer) -> void:
	root.add_child(nav_header("Leaderboard"))
	_bodies.clear()
	_tabs.clear()

	var boards := GameModes.ranked()
	root.add_child(_tab_bar(boards))

	# THE PAGER. A horizontal scroller whose children are each exactly one
	# viewport wide, so the boards genuinely sit side by side and a swipe moves
	# between them. Vertical scrolling is DISABLED here and owned by each page,
	# which is what keeps a vertical drag inside a long table from dragging the
	# pager sideways.
	_pager = ScrollContainer.new()
	_pager.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_pager.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pager.clip_contents = true
	_pager.follow_focus = false
	_pager.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pager.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_pager)

	_pages = UI.hbox(0.0)
	_pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pager.add_child(_pages)

	for mode: GameModes.Mode in boards:
		_pages.add_child(_board_page(mode))

	# Pages are sized from the pager's OWN width, which is not known until it has
	# been laid out at least once — and changes again on rotation or on a tablet's
	# split view. Sizing them once would leave every page at whatever the first
	# frame happened to measure.
	_pager.resized.connect(_resize_pages)
	_resize_pages.call_deferred()
	_request_all(boards)

# --- The pager ----------------------------------------------------------------

## One chip per board. The chips are the accessible half of the pager: a swipe is
## the fast way between boards and this is the discoverable one, and it is the
## only way to reach page three on a desktop with no touch screen.
func _tab_bar(boards: Array[GameModes.Mode]) -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(DesignSystem.SPACE_MD))
	margin.add_theme_constant_override("margin_right", int(DesignSystem.SPACE_MD))
	margin.add_theme_constant_override("margin_bottom", int(DesignSystem.SPACE_SM))
	var row := UI.hbox(DesignSystem.SPACE_SM)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(row)
	for i in boards.size():
		var chip := _tab_chip(boards[i], i)
		_tabs.append(chip)
		row.add_child(chip)
	return margin

func _tab_chip(mode: GameModes.Mode, index: int) -> Control:
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.custom_minimum_size.y = 76
	chip.add_theme_stylebox_override("panel", _tab_box(index == _page_index))
	var lbl := UI.label(mode.title, DesignSystem.TYPE_LABEL,
		"text" if index == _page_index else "text_dim", HORIZONTAL_ALIGNMENT_CENTER)
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)
	UI.make_scroll_tappable(chip, func(): _goto_page(index))
	return chip

func _tab_box(active: bool) -> StyleBoxFlat:
	var p := ThemeManager.palette()
	var base: Color = p["control"]
	var sb := StyleBoxFlat.new()
	sb.bg_color = base if active else Color(base.r, base.g, base.b, base.a * 0.35)
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_PILL))
	sb.set_border_width_all(2 if active else 1)
	sb.border_color = ThemeManager.color("accent") if active else p["control_stroke"]
	sb.anti_aliasing = true
	sb.content_margin_left = DesignSystem.SPACE_SM
	sb.content_margin_right = DesignSystem.SPACE_SM
	return sb

## Every page is exactly one pager wide, so scroll_horizontal is page_index *
## width and snapping is arithmetic rather than a search.
func _resize_pages() -> void:
	if not is_instance_valid(_pager) or not is_instance_valid(_pages):
		return
	var w := _pager.size.x
	if w <= 0.0:
		return
	for child in _pages.get_children():
		(child as Control).custom_minimum_size.x = w
	# A resize re-derives the page offset from the NEW width, so any slide still
	# aiming at an offset measured against the old one has to go.
	_kill_slide()
	_pager.scroll_horizontal = int(round(w * float(_page_index)))

func _goto_page(index: int) -> void:
	var count := _pages.get_child_count() if is_instance_valid(_pages) else 0
	if count <= 0:
		return
	_page_index = clampi(index, 0, count - 1)
	_restyle_tabs()
	var target := int(round(_pager.size.x * float(_page_index)))
	# BEFORE either branch: an in-flight slide would otherwise keep writing to
	# scroll_horizontal after this call has set (or started aiming at) a new page.
	_kill_slide()
	if bool(SettingsManager.get_value("reduce_motion")):
		_pager.scroll_horizontal = target
		return
	_slide = create_tween()
	_slide.tween_property(_pager, "scroll_horizontal", target,
		DesignSystem.DUR_BASE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _kill_slide() -> void:
	if _slide != null and _slide.is_valid():
		_slide.kill()
	_slide = null

func _restyle_tabs() -> void:
	for i in _tabs.size():
		var chip := _tabs[i] as PanelContainer
		if not is_instance_valid(chip):
			continue
		chip.add_theme_stylebox_override("panel", _tab_box(i == _page_index))
		for c in chip.get_children():
			if c is Label:
				(c as Label).add_theme_color_override("font_color",
					ThemeManager.color("text" if i == _page_index else "text_dim"))

# --- One board's page ---------------------------------------------------------

func _board_page(mode: GameModes.Mode) -> Control:
	var page := ScrollContainer.new()
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	page.clip_contents = true
	page.follow_focus = false
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	SmoothWheel.attach(page)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", int(DesignSystem.SPACE_MD))
	margin.add_theme_constant_override("margin_right", int(DesignSystem.SPACE_MD))
	margin.add_theme_constant_override("margin_bottom", int(DesignSystem.SPACE_2XL))
	page.add_child(margin)

	var col := UI.vbox(DesignSystem.SPACE_MD)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(col)

	col.add_child(_board_header(mode))

	var body := UI.vbox(DesignSystem.SPACE_SM)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bodies[mode.id] = body
	col.add_child(body)
	_fill_body(mode.id, [], "loading")
	return page

## What this board IS and what the reader has done on it — the two facts a table
## of strangers' names needs above it to mean anything.
func _board_header(mode: GameModes.Mode) -> Control:
	var card := UI.glass_card(2)
	var row := UI.hbox(DesignSystem.SPACE_MD)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(row)
	row.add_child(_mode_glyph(mode))

	var col := UI.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var title := UI.fit_label(mode.title, DesignSystem.TYPE_HEADLINE, "text")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ThemeManager.display_font:
		title.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(title)
	# Catalogue facts, not statistics: the room and the series length are what
	# tell the reader which board's table they are looking at.
	var room := "9 boards" if mode.is_meta() else "%dx%d" % [mode.board_size, mode.board_size]
	var meta := "%s  ·  first to %d" % [room, mode.win_target]
	if not EntitlementManager.is_mode_unlocked(mode.id):
		meta += "  ·  Premium"
	col.add_child(UI.caption(meta, "text_faint"))
	row.add_child(col)

	var mine := Progression.best_score(mode.id)
	var stack := UI.vbox(0)
	stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var eyebrow := UI.label("BEST SERIES", 30, "text_faint", HORIZONTAL_ALIGNMENT_RIGHT)
	eyebrow.autowrap_mode = TextServer.AUTOWRAP_OFF
	stack.add_child(eyebrow)
	var mine_text := UI.commafy(mine) if mine > 0 else "—"
	var value := UI.fit_numeral(mine_text, 48,
		"text" if mine > 0 else "text_faint", HORIZONTAL_ALIGNMENT_RIGHT, mine_text)
	value.max_width = SCORE_SLOT
	stack.add_child(value)
	row.add_child(stack)

	UI.make_scroll_tappable(card, func(): _play(mode.id))
	return card

# --- The standings ------------------------------------------------------------

## Repaints one board's table. `reason` is "" for a real list, or the code the
## adapter handed back ("loading" / "signed_out" / "not_configured" / …).
##
## The order matters: a real list wins, and only when there is none does the
## fallback run. That way a board that HAS standings never shows the "why nobody
## is here" copy underneath them.
func _fill_body(mode_id: String, entries: Array, reason: String) -> void:
	var body: VBoxContainer = _bodies.get(mode_id)
	if body == null or not is_instance_valid(body):
		return
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()

	if not entries.is_empty():
		body.add_child(UI.eyebrow("Top players"))
		var shown := mini(entries.size(), MAX_ROWS)
		for i in shown:
			body.add_child(_player_row(entries[i] as Dictionary))
		# The reader is only listed when they are inside the top page. Off it,
		# their own entry is pinned below the table rather than left out, which
		# is the whole reason to show standings to someone who is 4000th.
		if not _contains_you(entries):
			body.add_child(UI.spacer(DesignSystem.SPACE_XS, false))
			body.add_child(_your_row(mode_id))
		return

	# NO LIST. Never an error card — the reader's own entry, then the reason.
	body.add_child(UI.eyebrow("Your entry"))
	body.add_child(_your_row(mode_id))
	body.add_child(UI.caption(_why(reason, mode_id), "text_faint"))
	if reason == "signed_out":
		var sign_in := PremiumButton.make("Sign in to Play Games",
			PremiumButton.Variant.PRIMARY)
		sign_in.pressed.connect(func(): AccountManager.sign_in())
		body.add_child(sign_in)

static func _contains_you(entries: Array) -> bool:
	for e: Dictionary in entries:
		if bool(e.get("is_you", false)):
			return true
	return false

## Why this board has no standings, in the player's terms rather than in the
## adapter's. Each branch names a DIFFERENT missing precondition, because "no
## leaderboard" covers several unrelated situations and only one of them is
## something the player can act on.
func _why(reason: String, mode_id: String) -> String:
	match reason:
		"loading":
			return "Loading the standings…"
		"unavailable":
			return "Global standings need Play Games, on Android."
		"signed_out":
			return "Sign in to Play Games to see how you rank."
		"not_configured":
			return "This board is not live on Play Games yet. Your best series is saved and will rank when it is."
		"failed":
			return "Play Games did not answer. Your best series is saved either way."
	if Progression.best_score(mode_id) <= 0:
		return "Nobody has posted a series here yet. Be first."
	return "No other players on this board yet."

## The reader's own row, built from the LOCAL record rather than from Play Games.
## This is what makes the page never blank: it is true offline, true signed out,
## and true before the Play Console ids exist — and it is the same number that
## mirrors up as this player's entry once they do.
func _your_row(mode_id: String) -> Control:
	var mine := Progression.best_score(mode_id)
	return _row(0, identity_name(), UI.commafy(mine) if mine > 0 else "—", "", true)

## WHO THE READER IS — and never "You".
##
## A leaderboard is a table of NAMES, so a row labelled with a pronoun is the one
## row on it that does not say whose it is; sitting under nine real gamer tags it
## reads as a placeholder the page forgot to fill in rather than as the player.
## And the name was never missing: the identity sheet writes one into the profile
## section (defaulting it to "Player"), the Badge page and the Profile tab have
## printed it all along, and only this page asked Play Games and gave up.
##
## The chain is exactly badge.gd's `_identity_name`, so the app's three identity
## surfaces cannot disagree about what to call the player: the Play Games gamer
## tag once it has landed, the locally saved name otherwise, "Player" as the
## floor. Off Android the tag is ALWAYS empty, so the middle link is the one that
## runs on every desktop build — which is precisely the state that used to
## print "You".
static func identity_name() -> String:
	var tag := AccountManager.display_name()
	if not tag.is_empty():
		return tag
	var saved := String(SaveManager.get_section(PROFILE_SECTION, {})
		.get("name", "")).strip_edges()
	return saved if not saved.is_empty() else "Player"

func _player_row(entry: Dictionary) -> Control:
	var shown_score := String(entry.get("display_score", ""))
	if shown_score.is_empty():
		shown_score = UI.commafy(int(entry.get("score", 0)))
	var who := String(entry.get("name", ""))
	if who.is_empty():
		# A nameless entry that is the READER is the same person `_your_row`
		# names, so it gets the same name rather than the stranger's placeholder
		# — the row is pinned to the top of the reader's attention by its accent
		# border, and "Player" on it would be the page failing to recognise them.
		who = identity_name() if bool(entry.get("is_you", false)) else "Player"
	return _row(int(entry.get("rank", 0)), who, shown_score,
		String(entry.get("icon_uri", "")), bool(entry.get("is_you", false)))

## One standings row: rank medal, avatar, name, score. `rank` of 0 means "no rank
## yet" and draws a dash rather than a "0", which would read as last place.
func _row(rank: int, who: String, score_text: String, icon_uri: String,
		is_you: bool) -> Control:
	var card := UI.glass_card(1)
	if is_you:
		# The reader's row is the one thing on the page they are looking for, so
		# it wears the theme accent rather than being one more grey line.
		var sb := UI.glass_box(2)
		sb.set_border_width_all(2)
		sb.border_color = ThemeManager.color("accent")
		card.add_theme_stylebox_override("panel", sb)
	var line := UI.hbox(DesignSystem.SPACE_MD)
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(line)

	line.add_child(_rank_chip(rank))
	line.add_child(_my_portrait() if is_you else _avatar(icon_uri, who))

	# A Play Games gamer tag is whatever its owner typed, so the name shrinks into
	# whatever the score leaves rather than pushing the row off the card.
	var name_lbl := UI.fit_label(who, DesignSystem.TYPE_BODY,
		"text" if is_you else "text_dim")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_lbl)

	# NOT plain clip_text: a clipping Label reports zero minimum width and would
	# collapse the very number the row exists to show. A FitLabel reserves its
	# floor instead — it can shrink its type, never its meaning.
	var score := UI.fit_numeral(score_text, 44,
		"text" if is_you else "text_dim", HORIZONTAL_ALIGNMENT_RIGHT, score_text)
	score.max_width = SCORE_SLOT
	line.add_child(score)
	return card

func _rank_chip(rank: int) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(68, 68)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hue: Color = ThemeManager.color("text_dim")
	if rank >= 1 and rank <= RANK_HUES.size():
		hue = RANK_HUES[rank - 1]
		var disc := Panel.new()
		disc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(hue.r, hue.g, hue.b, 0.18)
		sb.set_corner_radius_all(34)
		sb.set_border_width_all(2)
		sb.border_color = hue
		sb.anti_aliasing = true
		disc.add_theme_stylebox_override("panel", sb)
		holder.add_child(disc)
	# Ranks are not all single digits — a player 4,000th on a live board has to
	# fit the same 68pt disc as the player who came first.
	var rank_text := str(rank) if rank > 0 else "—"
	var lbl := UI.fit_numeral(rank_text, 34, "text",
		HORIZONTAL_ALIGNMENT_CENTER, rank_text, 16)
	lbl.add_theme_color_override("font_color", hue)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(lbl)
	return holder

## THE READER'S PICTURE: their RANK BADGE, drawn by the same BadgePortrait the
## Profile tab's hero and the identity sheet's live preview use — plate, chosen
## aura, tier emblem and the equipped frame. What a player picks in that sheet is
## literally the widget that lands here, so the three surfaces cannot drift.
##
## The one row on this page that belongs to somebody the app actually knows is
## the one row that can carry a real picture. Drawing it as an initial-letter
## disc — the fallback that exists for strangers whose photo this page will not
## fetch — rendered the app's own player as the most anonymous entry in the
## table, under a name they had typed themselves.
##
## No `uri` is passed, so no HTTP request is started. That is the same policy
## `_avatar` states for everyone else, and it holds harder here: `_your_row` is
## built once per BOARD PAGE, so a fetching portrait would open one connection
## per ranked board every time the screen is built or the theme changes. The
## badge is local, correct offline and signed out, and is the thing the reader
## climbed a ladder for.
func _my_portrait() -> Control:
	var p := SaveManager.get_section(PROFILE_SECTION, {})
	var tier_idx: int = TierBadge.current_index(
		float(GameStats.best_mastery_ratio()["ratio"]))
	# Unranked has no tier colour to borrow, so the aura falls back to the theme
	# accent exactly as the identity sheet's preview does.
	var accent: Color = TierBadge.tier(tier_idx)["accent"]
	if tier_idx < 0:
		accent = ThemeManager.color("accent")
	var portrait := BadgePortrait.new()
	portrait.box = AVATAR
	portrait.tier_idx = tier_idx
	portrait.frame_idx = TierBadge.equipped_frame(p)
	portrait.effect_idx = BadgeCosmetics.effect_of(p)
	portrait.tint = TierBadge.aura_color(int(p.get("avatar", -1)), accent)
	return portrait

## Another player's avatar: their initial on a tinted disc.
##
## The uri is a REMOTE one and is deliberately not fetched here: a leaderboard
## that blocks on ten image downloads is a leaderboard that arrives late, and
## there is no image cache in the app to put them in. The initial is drawn
## immediately and is never wrong.
func _avatar(_icon_uri: String, who: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(AVATAR, AVATAR)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var disc := Panel.new()
	disc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeManager.color("control")
	sb.set_corner_radius_all(int(AVATAR * 0.5))
	sb.set_border_width_all(1)
	sb.border_color = ThemeManager.color("control_stroke")
	sb.anti_aliasing = true
	disc.add_theme_stylebox_override("panel", sb)
	holder.add_child(disc)
	var initial := who.strip_edges().substr(0, 1).to_upper()
	if initial.is_empty():
		initial = "?"
	var lbl := UI.label(initial, 36, "text", HORIZONTAL_ALIGNMENT_CENTER)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(lbl)
	return holder

# --- Loading ------------------------------------------------------------------

## Asks for every board at once. Requesting only the visible page would make the
## first swipe wait on a network round trip; three requests is what the adapter's
## own page size was chosen for.
func _request_all(boards: Array[GameModes.Mode]) -> void:
	_pending.clear()
	for mode: GameModes.Mode in boards:
		var refused := PlayGames.request_board(mode.id)
		if refused.is_empty():
			_pending[mode.id] = true
			continue
		# Refused SYNCHRONOUSLY — no signal is coming, so paint the reason now
		# rather than leaving the page on "loading" forever.
		_fill_body(mode.id, [], refused)

func _on_board_loaded(mode_id: String, entries: Array, error: String) -> void:
	_pending.erase(mode_id)
	_fill_body(mode_id, entries, error)

# --- Shared bits --------------------------------------------------------------

## The mode's own mark: its IconLibrary token when it has one (kept in its native
## gradient colours), its PNG accent-tinted, its glyph otherwise — the same
## three-way fallback mode_select uses, so the two never disagree about what a
## board looks like.
func _mode_glyph(mode: GameModes.Mode) -> Control:
	if not mode.icon_path.is_empty() and UI.icon_tex(mode.icon_path) != null:
		var tint := "" if IconLibrary.has_icon(mode.icon_path) else "accent"
		var icon := UI.icon_rect(mode.icon_path, 92, tint)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.custom_minimum_size = Vector2(92, 92)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return icon
	var glyph := UI.label(mode.icon, 56, "accent")
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.custom_minimum_size = Vector2(92, 92)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return glyph

## Starts a series on `mode_id`, through the SAME gate Home's launcher uses: a
## locked board sends the player to the paywall rather than into a game they have
## not bought. Every ranked board is the shared gameplay conductor, so there is
## no per-mode scene dispatch to do here.
func _play(mode_id: String) -> void:
	if not EntitlementManager.is_mode_unlocked(mode_id):
		SceneRouter.goto(SceneRouter.Route["PREMIUM"])
		return
	SceneRouter.goto(SceneRouter.Route["GAMEPLAY"],
		{"mode": mode_id, "continue": false})
