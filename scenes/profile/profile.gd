extends AppScreen
## Profile — the player's identity and account page.
##
## INFORMATION, NOT PROGRESSION. This page answers four questions and no others:
## who am I, what account am I on, what have I paid for, and how do I get help or
## tell someone about the game. The rank ladder, trophy case, day streak and
## per-mode mastery that used to fill it belong to the Achievements tab, and the
## lifetime numbers belong to Statistics — printing them a third time here is
## exactly what made this screen read as a second achievements page wearing a
## name label rather than as a profile.
##
## Read top to bottom, one card per section:
##
##   Player card → Balance → Account → Membership → At a glance →
##   Share & Invite → Support & About → Delete account & data
##
## Identity lives in the "profile" save section
## { name, status, avatar, frame, joined, player_id }, edited by the shared
## IdentitySheet. Play Games is the sole account provider (see AccountManager):
## its photo fills the portrait while signed in.
##
## The profile picture is the player's RANK BADGE, drawn by BadgePortrait — the
## same widget the identity sheet previews live, so aura and frame picked there
## land here exactly as shown.
##
## Nothing on this page is a game action. Every row either states a fact, copies
## it, or leaves for the screen that owns it.

const SECTION := "profile"

## Where "Contact support" writes to. A real inbox, not a placeholder — a support
## row that opens a mail client addressed to nobody is worse than no row.
const SUPPORT_EMAIL := "sagokriyo@gmail.com"

## The Play listing this build points at. MUST track `package/unique_name` in
## export_presets.cfg — a stale value here sends "Rate us" to a store page that
## does not exist, which fails silently on the one device a tester never checks.
const STORE_PACKAGE := "com.sagokriyo.numslide"
const STORE_URL := "https://play.google.com/store/apps/details?id=" + STORE_PACKAGE

## The player-id alphabet: uppercase letters and digits with every ambiguous
## glyph removed (no O/0, I/1, S/5, B/8, Z/2, G/6). The id exists to be read off
## a screen and typed into a support mail, so a character nobody can transcribe
## defeats the point.
const ID_ALPHABET := "ACDEFHJKLMNPQRTUVWXY3479"
const ID_BLOCK := 4


const _MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var _main_col: VBoxContainer
## The page's section rail. Rebuilt by `build_content`, so nothing may hold a
## reference to it across a `_refresh()`.
var _rail: PanelRail
## Which section is open, kept OUTSIDE the tree so it survives the four signals
## that rebuild this page. Without it, the Play Games photo landing while someone
## is reading Membership drops them back on Balance — the paged equivalent of
## being thrown to the top of a scroll.
var _open_tab := 0
## True only between the player tapping "Restore purchase" and the store
## answering — the same latch settings.gd uses, so the silent ownership queries
## BillingService runs on connect never raise a toast here.
var _restore_requested := false

func on_ready() -> void:
	custom_entrance = true
	# Home's glass-shard identity behind the page — the profile is painted in the
	# game's own tiles, not floating on a bare gradient. CALM, though: this is the
	# densest page in the app, and on the Home mix a near-band shard parks a bright
	# 196pt block on the avatar, the PREMIUM eyebrow and "SHARE & INVITE" (worst on
	# the light palettes). Atmosphere that covers a word is not atmosphere.
	add_glass_drift(true)
	AccountManager.auth_changed.connect(func(): _refresh())
	# The Play Games gamer tag and photo land AFTER the session does, so refresh
	# when they arrive or the card keeps showing the guest face.
	AccountManager.profile_changed.connect(func(): _refresh())
	# Fires only for explicit sign_in() attempts, never for the automatic launch
	# prompt — so this toast can't nag on boot.
	AccountManager.sign_in_failed.connect(func():
		_toast("Sign-in unavailable", "Play Games sign-in isn't available right now."))
	EntitlementManager.premium_changed.connect(func(_owned: bool): _refresh())
	BillingService.purchases_restored.connect(_on_restore_result)
	content.modulate.a = 0.0
	await get_tree().process_frame
	content.modulate.a = 1.0
	# The hero, then the rail. Two beats rather than eight: the page no longer
	# stacks its sections, so there is no longer a column of blocks to cascade.
	if _main_col and _main_col.get_child_count() > 0:
		stagger_in(_main_col.get_children())

func nav_tab() -> String: return "profile"

func build_content(root: VBoxContainer) -> void:
	root.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))
	_build_top_bar(root)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", int(DesignSystem.SPACE_MD))
	margin.add_theme_constant_override("margin_right", int(DesignSystem.SPACE_MD))
	margin.add_theme_constant_override("margin_bottom", int(DesignSystem.SPACE_MD))
	root.add_child(margin)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_LG))
	margin.add_child(col)
	_main_col = col

	# The player card runs FULL WIDTH, above the rail. It is the page's subject,
	# not one of its sections — putting identity behind a tab would mean a profile
	# page that can be open without showing you.
	col.add_child(_player_card())

	# Everything else is a TAB, not a scroll stop. Each panel is built by the same
	# `_section()` that used to stack them, so the section keeps its header, its
	# "Shop ›" / "Statistics ›" jump, and its exact copy — the page did not lose a
	# fact in the move, it stopped printing all seven of them at once.
	#
	# The builders are deferred Callables: PanelRail re-runs the one it is showing,
	# so a panel always states current data and the other five are not sitting in
	# the tree reacting to signals they cannot show the result of.
	var rail := PanelRail.new()
	col.add_child(rail)
	_rail = rail
	rail.add_tab("wallet", "Balance", func() -> Control:
		return _section("Balance", _balance_card(), "Shop",
			func(): SceneRouter.goto(SceneRouter.Route["SHOP"])))
	rail.add_tab("profile", "Account", func() -> Control:
		return _section("Account", _account_block(), "", Callable()))
	rail.add_tab("rank_badge", "Membership", func() -> Control:
		return _section("Membership", _membership_card(), "", Callable()))
	rail.add_tab("chart", "At a glance", func() -> Control:
		return _section("At a glance", _glance_card(), "Statistics",
			func(): SceneRouter.goto(SceneRouter.Route["STATISTICS"])))
	rail.add_tab("invite", "Share & Invite", func() -> Control:
		return _section("Share & Invite", _share_block(), "", Callable()))
	# The deletion row rides in Support, where a player looks for it, rather than
	# taking a rail slot of its own. Play asks for a reachable path, not a tab.
	rail.add_tab("how_to_play", "Support & About", func() -> Control:
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
		box.add_child(_section("Support & About", _support_block(), "", Callable()))
		box.add_child(_delete_card())
		return box)
	rail.tab_changed.connect(func(i: int): _open_tab = i)
	rail.select(clampi(_open_tab, 0, rail.tab_count() - 1))

## Rebuilds the page in place, KEEPING the section the reader had open.
##
## Four signals land here — auth, the Play Games profile arriving, premium, and
## the identity sheet's Save — and each one frees the whole page. `_open_tab`
## lives outside the tree precisely so it survives that: without it, a photo
## finishing its download while someone is reading Membership silently drops them
## back on Balance.
func _refresh() -> void:
	for c in content.get_children():
		c.queue_free()
	build_content(content)

# --- Data ---------------------------------------------------------------------
func _profile() -> Dictionary:
	return SaveManager.get_section(SECTION, {"name": "Player", "avatar": -1})

func _save(p: Dictionary) -> void:
	SaveManager.set_section(SECTION, p)

## The identity name: the Play Games gamer tag once it has loaded, falling back
## to the locally-saved name, else "Player".
func _identity_name() -> String:
	var tag := AccountManager.display_name()
	if not tag.is_empty():
		return tag
	return String(_profile().get("name", "Player"))

## The status line, defaulted. IdentitySheet owns both the default and the sheet
## that edits it, so the page that PRINTS a status and the sheet that WRITES one
## can't disagree about what an empty one means.
func _status_text() -> String:
	return IdentitySheet.status_text()

func _joined_text() -> String:
	var p := _profile()
	var unix := int(p.get("joined", 0))
	if unix <= 0:
		unix = int(Time.get_unix_time_from_system())
		p["joined"] = unix
		_save(p)
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%s %d" % [_MONTHS[int(d["month"]) - 1], int(d["year"])]

## The player's handle, minted once and then permanent.
##
## Deliberately NOT derived from the name (which changes), the Play Games id
## (which a guest does not have) or the device (which a reinstall replaces): it
## is the one stable string a player can read out to support or to a friend, so
## it has to survive every one of those changing underneath it.
func _player_id() -> String:
	var p := _profile()
	var id := String(p.get("player_id", ""))
	if id.is_empty():
		id = _mint_player_id()
		p["player_id"] = id
		_save(p)
	return id

func _mint_player_id() -> String:
	var out := ""
	for i in ID_BLOCK * 2:
		if i == ID_BLOCK:
			out += "-"
		out += ID_ALPHABET[randi() % ID_ALPHABET.length()]
	return out

## The rank the player currently holds, as a plain title ("Gold"), or "" while
## unranked. A NAME, not a ladder: the progression it comes from is the
## Achievements tab's subject, and this page only states which one is in force.
func _rank_title() -> String:
	var best := GameStats.best_mastery_ratio()
	var ratio: float = best["ratio"]
	var idx: int = TierBadge.current_index(ratio)
	return "" if idx < 0 else String(TierBadge.tier(idx)["name"])

func _rank_accent() -> Color:
	var best := GameStats.best_mastery_ratio()
	var ratio: float = best["ratio"]
	var idx: int = TierBadge.current_index(ratio)
	if idx < 0:
		return ThemeManager.color("accent")
	return TierBadge.tier(idx)["accent"]

# --- Top bar ------------------------------------------------------------------
func _build_top_bar(root: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))
	bar.add_child(UI.circle_button("back", "",
		func(): SceneRouter.back(), 120.0))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	# The design sheet's magenta paper plane (IconLibrary "share"), on the SAME
	# plain circle button as its two neighbours. The old "↗" was a text glyph on
	# a glass chip that neither the back arrow nor the gear wore, so a
	# three-button bar carried two different kinds of control. Flat (no baked
	# glow): the token brings its own contour and cast shadow.
	bar.add_child(UI.circle_button("share", "",
		func(): _share_profile(), 120.0, false))
	# The SAME gear as Home's top bar — the original PNG tinted to the theme's dim
	# text, not the runtime gradient icon. The settings entry point must look
	# identical on every screen that offers it.
	bar.add_child(UI.circle_button("res://assets/icons/settings.png", "text_dim",
		func(): SceneRouter.goto(SceneRouter.Route["SETTINGS"]), 120.0))
	root.add_child(bar)

# --- 1. Player card -----------------------------------------------------------
## Who you are, in one card: picture, name, the rank and account chips, your
## status line, and the two facts that identify the account — the player id and
## the month you started. Tapping anywhere opens the identity sheet; the card
## itself is the affordance, which is why there is no pencil in the top bar.
##
## The id is shown here but copied from the Share section: a second hit target
## inside a tappable card is the classic double-fire, and "copy" belongs with the
## other things you do TO your identity rather than with the statement of it.
func _player_card() -> Control:
	var p := _profile()
	var accent := _rank_accent()
	var aura: Color = TierBadge.aura_color(int(p.get("avatar", -1)), accent)

	var card := UI.glass_card(3)
	# The hero is a different CLASS of object from the rows below it. Radius says
	# so (RADIUS_XL against their RADIUS_LG), and the player's OWN aura tints the
	# glass and its rim — until now the colour picked in the identity sheet landed
	# in exactly one place, the disc fill, so choosing it changed almost nothing.
	#
	# Done on the STYLEBOX, not with an overlay node. The overlay version used
	# GradientPanel and shipped as an opaque gold slab across the whole card:
	# that shader ends `COLOR = vec4(col, alpha)` with `alpha` coming only from
	# its rounded-rect SDF, so the alpha on the colours handed to `make()` is
	# discarded. GradientPanel is an opaque SURFACE, not a wash — it is the right
	# tool for the share card's full background and the wrong one for a tint.
	# (`UI.round_clip` on it was a second bug: it replaces `material`, which is
	# where GradientPanel keeps its own shader.)
	#
	# Alpha stays low: gold over a warm light palette (Carnival) breaks first.
	var hero_box := UI.glass_box(3, DesignSystem.RADIUS_XL)
	hero_box.bg_color = hero_box.bg_color.lerp(aura, 0.14)
	hero_box.border_color = hero_box.border_color.lerp(aura, 0.5)
	hero_box.set_content_margin_all(DesignSystem.SPACE_LG)
	card.add_theme_stylebox_override("panel", hero_box)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_LG))
	card.add_child(row)

	# The player's aura as LIGHT, not just a tint on the fill. A soft radial in the
	# chosen colour sits under the row, centred on the picture — so the hero reads
	# as a lit portrait rather than as a rectangle that happens to be slightly
	# gold. PanelContainer fits every child to its content rect, so this and the
	# row below it both fill the card; added first, it renders behind.
	#
	# Alpha is deliberately low and the wash is centred LEFT (over the avatar, not
	# over the text): the same gold that reads as depth behind a picture reads as a
	# stain behind a paragraph, worst on the warm light palettes.
	var wash := _aura_wash(aura)
	card.add_child(wash)

	var display_name := _identity_name()
	# The RANK BADGE is the profile picture — BadgePortrait, the same widget the
	# identity sheet previews, so what a player dresses there is what lands here.
	# It is a STATEMENT, not a ladder: the badge and the chip that names it, and
	# nothing else — no threshold, no ratio, no "next rank", no progress ring. The
	# moment a percentage appears beside this, the page is the Achievements screen
	# again, which is the exact drift this screen was rebuilt to stop (see the file
	# header, and flow_profile_page's EVICTED list).
	var avatar := BadgePortrait.new()
	avatar.box = 240.0
	avatar.tint = aura
	avatar.uri = AccountManager.icon_uri()
	avatar.frame_idx = TierBadge.equipped_frame(p)
	# The bought emblem effect shows here too. A decoration that only ever appears
	# on the page you had to tap a capsule to reach is one most players will never
	# see themselves wearing.
	avatar.effect_idx = BadgeCosmetics.effect_of(p)
	avatar.tier_idx = TierBadge.current_index(GameStats.best_mastery_ratio()["ratio"])
	row.add_child(avatar)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))
	row.add_child(col)

	var name_lbl := _label(display_name, 64)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.clip_text = true
	# A long Play Games tag was being cut mid-glyph with nothing to say so, which
	# reads as a rendering fault rather than as a name that did not fit.
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_color_override("font_color", ThemeManager.color("text"))
	if ThemeManager.display_font:
		name_lbl.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(name_lbl)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))
	var rank := _rank_title()
	if not rank.is_empty():
		chips.add_child(_chip(rank, accent))
	var signed_in := AccountManager.is_signed_in()
	chips.add_child(_chip("Play Games" if signed_in else "Guest",
		ThemeManager.color("accent") if signed_in else ThemeManager.color("text_dim")))
	col.add_child(chips)

	var status := _label(_status_text(), 32)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	col.add_child(status)

	# A rule between the identity and the two facts that merely IDENTIFY it. Four
	# unbroken text runs down one column read as a paragraph; a hairline turns the
	# last one into a footer, which is what it is. Gaps read as absence, a line
	# reads as structure.
	var rule := UI.hairline(0.1)
	rule.custom_minimum_size.y = 1
	col.add_child(rule)

	# The two facts that merely IDENTIFY the account, as their own small objects
	# rather than as one dim run-on line. A footer that reads "ID PJCY-DKWD ·
	# Joined Aug 2026" is a sentence nobody parses; two labelled pills are two
	# facts you can point at, and the id — the one string on this page a player is
	# ever asked to read aloud — stops being the faintest thing on the screen.
	#
	# HFlowContainer, NOT an HBox. Both pills carry AUTOWRAP_OFF text, so in a row
	# their widths SUM into one hard minimum (~560pt) beside a 240pt picture, and
	# that minimum propagates out to the page exactly the way a non-wrapping row
	# title does — the 982-budget failure whose only symptom is the top bar's gear
	# being clipped. A flow container's minimum is its WIDEST CHILD: the pair sits
	# on one line when there is room and wraps to two when there is not.
	var facts := HFlowContainer.new()
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.add_theme_constant_override("h_separation", int(DesignSystem.SPACE_XS))
	facts.add_theme_constant_override("v_separation", int(DesignSystem.SPACE_XS))
	facts.add_child(_fact_pill("ID", _player_id()))
	facts.add_child(_fact_pill("Joined", _joined_text()))
	col.add_child(facts)

	var chev := _chevron()
	chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chev)

	UI.make_scroll_tappable(card, func(): _edit_identity())
	return card

# --- 2. Balance ---------------------------------------------------------------
## The purse, stated. One row per number: its token, its name, the figure, and
## what the figure is FOR — the last of which is the only reason a whole panel
## beats the three-pill strip Home wears.
func _balance_card() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))

	# NO CURRENCY STRIP HERE. The shared CurrencyHud is built for a FULL-WIDTH
	# page (Home, the Shop): three pills need ~866pt and this panel sits beside a
	# 236pt rail with 553 left over, so the leaderboard pill was always sliced
	# through its own number. The sideways scroller that was meant to absorb that
	# did not read as a scroller, it read as three balances running off the page —
	# and the strip was saying, in a clipped shorthand, exactly what the three
	# rows below it say in full. One statement of a number per panel.

	# WHAT each number is for. A section with room to spare should use it to
	# answer the question the figures raise.
	box.add_child(_purse_row("currency_coins", "Coins",
		"Undos, retries and sweeps.", Wallet.coins()))
	box.add_child(_purse_row("currency_gems", "Gems",
		"Themes and upgrades. Kept for good.", Wallet.gems()))
	# The best score, on the same terms as the two balances — which is the only
	# reason it is in a section called Balance. It is not a currency, and a player
	# who taps it expecting to spend something is exactly who this row is written
	# for. Tappable, unlike the two above it: those lead to the Shop through the
	# section's own action, while this one IS its destination.
	#
	# TITLED FOR ITS NUMBER, not for its destination. "Leaderboard" is a 293pt
	# label at this size — against "Coins" at 131 — and this panel sits beside a
	# 236pt rail inside a 981pt budget with barely a dozen points to spare, so
	# that one word pushed the whole page over (flow_profile_page pins it). Naming
	# the row after what the figure IS reads better anyway: "Leaderboard: 99,999"
	# invites the number to be read as a third currency, which is the exact
	# confusion this row exists to prevent.
	var best: Dictionary = Progression.best_score_overall()
	var record := _purse_row("leaderboard", "Best Series",
		"Tap to see every board." if int(best["score"]) <= 0
			else "Set in %s. Tap for every board."
				% GameModes.get_mode(String(best["mode_id"])).title,
		int(best["score"]))
	UI.make_scroll_tappable(record,
		func(): SceneRouter.goto(SceneRouter.Route["LEADERBOARD"]))
	box.add_child(record)

	# The last thing that moved. Not a ledger — the Shop owns that — just enough
	# for the page to answer "did that reward actually land?" without leaving it.
	var entries := Wallet.ledger()
	if entries.size() > 0:
		var e: Dictionary = entries[0]
		var amount := int(e.get("amount", 0))
		var sign_txt := "+%d" % amount if amount >= 0 else str(amount)
		box.add_child(_info_card("Last change",
			"%s  %s" % [sign_txt, String(e.get("reason", ""))],
			"The full ledger is in the Shop."))
	return box

## The hue each purse wears — the currency token's OWN colour, taken from the
## icon set that draws it. Identical grey rows state their numbers and imply they
## are the same kind of thing; coins and gems are not, and the glyph beside each
## one has been saying so in colour all along.
## The podium is gold on purpose and NOT the theme accent: it is the same hue the
## leaderboard token is drawn in, so the row's leading bar matches the icon beside
## it exactly as the two currency rows do.
const _PURSE_HUES := {
	"currency_coins": Color("F4C13E"),
	"currency_gems": Color("9A7BF5"),
	"leaderboard": Color("F4C13E"),
}

## One row of the Balance panel: its token, its name, its number, and what that
## number is FOR. Used for the two currencies and for the leaderboard, which is
## not one — the shape is shared on purpose, because a third row built
## differently would imply the best score is a third thing to spend.
const PURSE_SLOT := 196.0

func _purse_row(icon_id: String, name_text: String, why: String, amount: int) -> Control:
	var hue: Color = _PURSE_HUES.get(icon_id, ThemeManager.color("accent"))
	var card := _card(2)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	card.add_child(row)

	# The currency's hue as a bar down the row's leading edge — the same device
	# the panel titles use, so a purse reads as a labelled thing rather than as
	# one more card. It is the CARD's own accent, which is why it leads the row
	# instead of sitting between the icon and the text.
	var edge := Panel.new()
	edge.custom_minimum_size = Vector2(6, 0)
	edge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edge.custom_minimum_size.y = 72
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var esb := StyleBoxFlat.new()
	esb.bg_color = hue
	esb.set_corner_radius_all(3)
	esb.anti_aliasing = true
	edge.add_theme_stylebox_override("panel", esb)
	row.add_child(edge)

	# FLAT: the currency tokens are the design sheet's 72-unit set and carry their
	# own contour and cast shadow, so the baked halo double-lights them.
	var ic := TextureRect.new()
	ic.texture = UI.icon_tex_flat(icon_id)
	ic.custom_minimum_size = Vector2(72, 72)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 4)
	# EXPANDING, with a 30-point floor. "BEST SCORE" in the display face is the
	# widest fixed leaf in the whole Balance panel, and a content-sized FitLabel
	# claims its NATURAL width - which, beside the rail, is what tipped this tab
	# past the 982-point page budget when the rail's captions grew. Expanding,
	# it claims only the floor: at everyday widths it still draws at 38, and
	# only a squeezed phone ever sees it give up a few points of type.
	var t := FitLabel.make(name_text, 38, 30)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_color_override("font_color", ThemeManager.color("text"))
	if ThemeManager.display_font:
		t.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(t)
	var w := _label(why, 30)
	w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	col.add_child(w)
	row.add_child(col)

	# The balance in its OWN currency's hue, inked so it survives a light palette
	# (a raw gold numeral on Carnival's wash is a fuzzy blob, the same correction
	# every accent-as-text on this page takes).
	# CAPPED. This row sits in a panel beside a 236-point rail inside a 982-point
	# page with barely a dozen points to spare (the same budget RAIL_W's note is
	# about), and a balance has no ceiling — coins accumulate for as long as the
	# player keeps playing. Past PURSE_SLOT the figure shrinks its own type rather
	# than widening the row, the panel and the page behind it.
	var money := _fmt_comma(amount)
	var val := UI.fit_numeral(money, 48, "text", HORIZONTAL_ALIGNMENT_RIGHT, money)
	val.max_width = PURSE_SLOT
	val.add_theme_color_override("font_color", UI.ink_of(hue, 0.5))
	row.add_child(val)
	return card

# --- 3. Account ---------------------------------------------------------------
## What the account IS, and the two Play Games sheets that hang off it.
##
## Signed out is the interesting state: a guest gets the full linking card with a
## real primary button and the reason to press it, not one more chevron row —
## that is the version players actually notice (settings.gd carries the same
## card for the same reason).
func _account_block() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))

	if not AccountManager.is_configured():
		# Editor, desktop, and any Android build without the PGS plugin. Said
		# plainly rather than showing a sign-in button that cannot work.
		# Eyebrowed "Play Games", like the signed-in card below it, so both states
		# of this section wear the same label — and NOT "Account", which would
		# print the section's own header a second time.
		box.add_child(_info_card("Play Games", "Playing as Guest",
			"Play Games isn't available on this device, so your progress stays here."))
		box.add_child(_link_benefits("What Play Games adds"))
		return box

	if not AccountManager.is_signed_in():
		box.add_child(_link_account_card())
		box.add_child(_link_benefits("What linking adds"))
		return box

	var tag := AccountManager.display_name()
	var who := tag if not tag.is_empty() else "Signed in"
	if AccountManager.player_level() > 0:
		who += "  ·  Level %d" % AccountManager.player_level()
	box.add_child(_info_card("Play Games", who,
		"Achievements and best scores sync to this account."))
	box.add_child(_nav_row("Leaderboards",
		"See how your best scores rank worldwide.", func(): PlayGames.show_leaderboards(),
		"best_score"))
	box.add_child(_nav_row("Play Games achievements",
		"The Google-side copy of your trophies.", func(): PlayGames.show_achievements(),
		"nav_achievements"))
	box.add_child(_link_benefits("What's synced"))
	return box

## What a Play Games account is FOR, in three lines with their own tokens.
##
## Every state of this panel was one card over an empty pane, and the guest state
## was the worst of them: a sign-in button whose reason to be pressed was one
## sentence of small print inside it. This is that reason, given room.
##
## The three titles deliberately avoid "Leaderboards" as a bare word. The account
## flow proves the not-configured branch by asserting that label ABSENT — a device
## with no provider must not appear to offer the sheet — and a benefits row that
## borrowed the string would break that assertion from a card that is not offering
## anything.
func _link_benefits(title_text: String) -> Control:
	var card := _card(1)
	if card is GlassPanel:
		(card as GlassPanel).content_margin = DesignSystem.SPACE_MD
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	card.add_child(col)

	var ey := _label(title_text.to_upper(), 30)
	ey.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	col.add_child(ey)

	col.add_child(_benefit_row("best_score", "Ranked against the world",
		"Your best scores stand beside everyone else's."))
	col.add_child(_benefit_row("nav_achievements", "Trophies kept by Google",
		"Every achievement mirrors to your Play Games profile."))
	col.add_child(_benefit_row("profile", "One identity, any device",
		"Sign in elsewhere and your gamer tag comes with you."))
	return card

## One benefit: token, title, and the line that says what it means. Deliberately
## NOT a `_nav_row` — these go nowhere, and giving them a chevron would promise a
## destination that does not exist.
func _benefit_row(icon_id: String, title_text: String, sub_text: String) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))

	var ic := UI.icon_rect(icon_id, 68.0, "")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	# WRAPPING, for the reason `_nav_row`'s title wraps: an AUTOWRAP_OFF title's
	# full rendered width becomes a hard minimum that the panel's scroller
	# propagates out to the page.
	var t := _label(title_text, 34)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_color_override("font_color", ThemeManager.color("text"))
	col.add_child(t)
	var s := _label(sub_text, 30)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	col.add_child(s)
	row.add_child(col)
	return row

## The guest's way to an identity: the why, and a real primary button.
func _link_account_card() -> Control:
	var card := _card(2)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	card.add_child(col)

	var title := _label("Playing as Guest", 40)
	title.add_theme_color_override("font_color", ThemeManager.color("text"))
	if ThemeManager.display_font:
		title.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(title)

	var desc := _label("Link Play Games to sync achievements and leaderboards. Your local stats and progress are kept either way.", 32)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	col.add_child(desc)

	var btn := PremiumButton.make("Sign in with Play Games", PremiumButton.Variant.PRIMARY)
	btn.full_width = true
	# The app's own gamepad mark (Google's may not be recoloured), same as the
	# sign-in screen's CTA.
	btn.icon = UI.icon_tex("games_played")
	btn.expand_icon = true
	btn.add_theme_constant_override("h_separation", 16)
	btn.pressed.connect(func(): _link_account(btn))
	col.add_child(btn)
	return card

## Fires the real PGS prompt and holds the button pending until the facade
## answers. EVERY outcome lands as auth_changed (success and failure alike — see
## AccountManager._on_authenticated), which on_ready has wired to _refresh, and
## that rebuild replaces this whole card. The timeout is for the prompt the OS
## swallows without ever answering (a player swiping the sheet away): the tween
## is node-bound, so the rebuild kills it cleanly.
func _link_account(btn: PremiumButton) -> void:
	if not AccountManager.is_configured() or AccountManager.is_signed_in():
		return
	btn.disabled = true
	btn.text = "Signing in…"
	AccountManager.sign_in()
	var tw := btn.create_tween()
	tw.tween_interval(20.0)
	tw.tween_callback(func():
		btn.disabled = false
		btn.text = "Sign in with Play Games")

# --- 4. Membership ------------------------------------------------------------
## What the player owns. Owned is a statement and nothing more; unowned carries
## the two actions a store account can need — buy, and re-claim what was already
## bought on this Google account.
##
## The "what you're missing" line is COUNTED from the catalogs rather than
## written down, because a store-facing number written down is a number that
## silently goes stale the next time a mode or theme lands (the paywall's own
## "All N themes" needs a human to remember; this cannot).
func _membership_card() -> Control:
	if EntitlementManager.is_premium():
		var owned := VBoxContainer.new()
		owned.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		owned.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
		owned.add_child(_info_card("Premium", "Unlocked — thank you!",
			"Every mode, every theme, no ads. It restores on any device with your Google Play account."))
		# An owner gets the SAME showcase, showing everything lit. The panel had
		# half a screen spare in both states, and a thank-you note alone is a
		# thinner answer to "what have I paid for" than the thing itself.
		owned.add_child(_premium_showcase(false))
		return owned

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))

	var locked := _premium_locked_counts()
	var modes: int = locked["modes"]
	var themes: int = locked["themes"]
	var detail := "Ads between some games."
	if modes > 0 or themes > 0:
		detail = "%d modes and %d themes are still locked, and ads play between some games." \
			% [modes, themes]

	var card := _card(2)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	card.add_child(col)

	var title := _label("Free player", 40)
	title.add_theme_color_override("font_color", ThemeManager.color("text"))
	if ThemeManager.display_font:
		title.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(title)

	var desc := _label(detail, 32)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	col.add_child(desc)

	var btn := PremiumButton.make("Unlock Premium", PremiumButton.Variant.PRIMARY)
	btn.full_width = true
	btn.pressed.connect(func(): SceneRouter.goto(SceneRouter.Route["PREMIUM"]))
	col.add_child(btn)
	box.add_child(card)

	box.add_child(_nav_row("Restore purchase",
		"Already bought? Restore it on this device.", func(): _do_restore(), "restart"))
	box.add_child(_premium_showcase(true))
	return box

## What premium contains, SHOWN rather than counted.
##
## The card above states "3 modes and 34 themes are still locked" — a true
## sentence that pictures nothing, in a panel that was leaving half a screen
## empty under it. These are those modes wearing their own icons and those themes
## wearing their own colours: the most useful thing to put in the space is the
## answer to the question the sentence raises.
##
## `locked_only` is the state, not a variant: a free player sees what they are
## missing, an owner sees what they have. Same shape, so the two states of this
## panel read as one page rather than two.
##
## HFlowContainer for both strips, and that is load-bearing rather than tidy.
## Their children carry AUTOWRAP_OFF text, so in an HBox their widths SUM into a
## single hard minimum which the panel's ScrollContainer (horizontal scrolling
## disabled) propagates straight out to the page — the 982-budget overflow whose
## only visible symptom is the top bar's gear being clipped off the right edge. A
## flow container's minimum is its WIDEST CHILD, and it wraps to as many rows as
## it needs.
func _premium_showcase(locked_only: bool) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))

	var modes: Array = []
	for mode in GameModes.all():
		if not locked_only or Entitlements.mode_requires_premium(mode.id):
			modes.append(mode)
	var themes: Array = []
	for id: String in ThemeManager.all_theme_ids():
		if not locked_only or Entitlements.theme_requires_premium(id):
			themes.append(id)
	if modes.is_empty() and themes.is_empty():
		return box

	var card := _card(1)
	if card is GlassPanel:
		(card as GlassPanel).content_margin = DesignSystem.SPACE_MD
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	card.add_child(col)

	# NOT "Membership" and not any other section's name — `_test_section_spine`
	# proves one panel at a time by asserting no OTHER section's title is on
	# screen, and an eyebrow that borrowed one would break that from inside.
	var ey := _label("Premium unlocks" if locked_only else "Included with premium", 30)
	ey.text = ey.text.to_upper()
	ey.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	col.add_child(ey)

	if not modes.is_empty():
		var mode_row := HFlowContainer.new()
		mode_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mode_row.add_theme_constant_override("h_separation", int(DesignSystem.SPACE_SM))
		mode_row.add_theme_constant_override("v_separation", int(DesignSystem.SPACE_SM))
		for m_v: Variant in modes:
			var m: GameModes.Mode = m_v
			mode_row.add_child(_mode_chip(m))
		col.add_child(mode_row)

	if not themes.is_empty():
		col.add_child(UI.hairline(0.08))
		var swatches := HFlowContainer.new()
		swatches.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		swatches.add_theme_constant_override("h_separation", int(DesignSystem.SPACE_XS))
		swatches.add_theme_constant_override("v_separation", int(DesignSystem.SPACE_XS))
		# Capped, with the remainder SAID. A catalogue of 30-odd swatches fills the
		# panel usefully; all of them turns it into wallpaper, and a silent
		# truncation would state a smaller catalogue than the one being sold.
		const SHOWN := 21
		for i in mini(themes.size(), SHOWN):
			swatches.add_child(_theme_swatch(String(themes[i])))
		if themes.size() > SHOWN:
			swatches.add_child(_more_swatch(themes.size() - SHOWN))
		col.add_child(swatches)

	box.add_child(card)
	return box

## One mode as a small pill: its own IconLibrary token and its title. Native
## colours — the set's per-mode hue is exactly what makes a strip of ten read as
## ten different games rather than as ten grey chips.
func _mode_chip(m: GameModes.Mode) -> Control:
	var pill := PanelContainer.new()
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeManager.color("control")
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_PILL))
	sb.set_border_width_all(1)
	sb.border_color = ThemeManager.color("control_stroke")
	sb.content_margin_left = DesignSystem.SPACE_SM
	sb.content_margin_right = DesignSystem.SPACE_MD
	sb.content_margin_top = DesignSystem.SPACE_XS
	sb.content_margin_bottom = DesignSystem.SPACE_XS
	sb.anti_aliasing = true
	pill.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))
	var ic := UI.icon_rect(m.icon_path, 64.0, "")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var t := _label(m.title, 30)
	t.add_theme_color_override("font_color", ThemeManager.color("text"))
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(t)
	pill.add_child(row)
	return pill

## One theme as a colour chip — its own surface with its own accent as a bar
## across the foot. Two colours, because a single flat square cannot tell a dark
## theme from another dark theme, and the accent is the thing a player is
## actually choosing between.
func _theme_swatch(id: String) -> Control:
	var pal := ThemeManager.palette_for(id)
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(74, 52)
	chip.tooltip_text = ThemeManager.theme_name(id)
	var sb := StyleBoxFlat.new()
	sb.bg_color = pal.get("bg1", ThemeManager.color("bg1"))
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_SM))
	sb.set_border_width_all(1)
	sb.border_color = ThemeManager.color("control_stroke")
	sb.anti_aliasing = true
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	chip.add_theme_stylebox_override("panel", sb)

	var bar := Panel.new()
	bar.size_flags_vertical = Control.SIZE_SHRINK_END
	bar.custom_minimum_size.y = 10
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = pal.get("accent", ThemeManager.color("accent"))
	bsb.set_corner_radius_all(5)
	bsb.anti_aliasing = true
	bar.add_theme_stylebox_override("panel", bsb)
	chip.add_child(bar)
	return chip

## The remainder the swatch strip did not draw, stated rather than dropped.
func _more_swatch(count: int) -> Control:
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(74, 52)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_SM))
	sb.set_border_width_all(1)
	sb.border_color = ThemeManager.color("control_stroke")
	sb.anti_aliasing = true
	chip.add_theme_stylebox_override("panel", sb)
	var l := _label("+%d" % count, 30)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	chip.add_child(l)
	return chip

## How much of each catalog premium is holding back, counted live. Reward themes
## are excluded on purpose: they are earned with a badge and no purchase has ever
## unlocked one, so counting them here would sell something that isn't for sale.
func _premium_locked_counts() -> Dictionary:
	var modes := 0
	for mode in GameModes.all():
		if Entitlements.mode_requires_premium(mode.id):
			modes += 1
	var themes := 0
	for id: String in ThemeManager.all_theme_ids():
		if Entitlements.theme_requires_premium(id):
			themes += 1
	return {"modes": modes, "themes": themes}

func _do_restore() -> void:
	_restore_requested = true
	BillingService.restore()

func _on_restore_result(count: int) -> void:
	if not _restore_requested:
		return   # ignore the silent connect-time ownership queries
	_restore_requested = false
	var msg: String
	if count > 0:
		msg = "Your purchase has been restored."
	elif count == 0:
		msg = "No previous purchase found on this Google account."
	else:
		msg = "Couldn't reach the store. Check your connection and try again."
	_toast("Restore", msg)

# --- 5. At a glance -----------------------------------------------------------
## Four numbers, as a summary and nothing more. Every one of them is the
## Statistics screen's to explain — the section header links straight there —
## and this card exists so a profile isn't silent about how much has been played.
func _glance_card() -> Control:
	# SIX CELLS, not six rows inside one card. The rows were right when this was
	# one block in a scrolling stack competing with seven others; it owns a whole
	# panel now, and six lines of text in a single frame left the lower half of
	# that panel empty while still reading as the flattest thing on the page. Each
	# number gets its own surface, so the section is a dashboard, not a list.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# SPACE_MD both ways: two columns of glass cells are the widest arrangement on
	# the page, and every point between them is a point the 982 budget does not
	# have.
	grid.add_theme_constant_override("h_separation", int(DesignSystem.SPACE_MD))
	grid.add_theme_constant_override("v_separation", int(DesignSystem.SPACE_MD))

	# Series first, then the rounds inside them, then the run of wins: the three
	# numbers a puzzle player actually quotes.
	var played := int(GameStats.get_stat("games_played"))
	var won := int(GameStats.get_stat("games_won"))
	var rounds := int(GameStats.get_stat("rounds_won"))
	var streak := int(GameStats.get_stat("best_win_streak"))
	grid.add_child(_glance_tile("games_played", _fmt_comma(played), "Series played", played))
	grid.add_child(_glance_tile("games_won", _fmt_comma(won), "Series won", won))
	grid.add_child(_glance_tile("total_moves", _fmt_comma(rounds), "Rounds won", rounds))
	grid.add_child(_glance_tile("best_score", _fmt_comma(streak), "Best win streak", streak))
	# The last two arrive already set. A percentage counting up from 0% and a
	# duration ticking through "0M" each state something briefly FALSE, which a
	# plain count on its way to its own total never does.
	grid.add_child(_glance_tile("win_rate",
		"%d%%" % int(round(GameStats.win_rate() * 100.0)), "Win rate"))
	grid.add_child(_glance_tile("total_play_time",
		GameStats.format_duration(float(GameStats.get_stat("total_play_seconds"))),
		"Time played"))
	return grid

## One number on its own glass cell, led by its own icon. The ids are Statistics'
## own — the same stat wears the same glyph on both screens, which is the whole
## reason this panel is allowed to restate them.
##
## `count_to` above zero makes the numeral count up on entry (see `_count_up`).
func _glance_tile(icon_id: String, value_text: String, caption_text: String,
		count_to: int = -1) -> Control:
	var cell := _card(1)
	# The tighter pad Statistics' stat cells use, for the same reason: two of these
	# side by side beside the rail is the page's widest arrangement, and the
	# default card air is what tips a two-column grid past the budget.
	if cell is GlassPanel:
		(cell as GlassPanel).content_margin = DesignSystem.SPACE_MD
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A FLOOR on the cell, so three rows of two fill the panel they were given
	# rather than huddling in its top third. Height is the one dimension this page
	# has to spare — the width budget is the tight one — and a dashboard whose
	# tiles are the smallest thing on the screen is a list wearing borders.
	cell.custom_minimum_size.y = 210

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))
	cell.add_child(col)

	var ic := UI.icon_rect(icon_id, 68.0, "")
	ic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(ic)

	# A numeral that wraps mid-number is unreadable in a way a wrapped word never
	# is (see the numeral notes in shop.gd), so this one shrinks to fit its cell
	# instead — the grid splits the panel six ways and a lifetime move count has
	# no ceiling. Tinted TOWARD the accent rather than set in it — six saturated
	# numerals in a grid shout; a white carrying the theme's hue reads rich.
	var v := UI.fit_numeral(value_text, 54, "text",
		HORIZONTAL_ALIGNMENT_LEFT, value_text)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_color_override("font_color", UI.ink_of(
		ThemeManager.color("text").lerp(ThemeManager.color("accent"), 0.55), 0.35))
	col.add_child(v)

	var c := _label(caption_text.to_upper(), 28)
	c.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	col.add_child(c)
	if count_to > 0:
		_count_up(v, count_to)
	return cell

## Counts `lbl` up to `to_value` when it enters the tree.
##
## The label's width is PINNED to the final string first. Without that its own
## minimum grows as digits appear ("0" → "355"), the grid re-sorts on nearly every
## frame of the count, and six cells visibly jitter — the animation meant to make
## the page feel alive instead makes it look unstable. Measured inside
## `tree_entered` because a theme font lookup does not resolve before then.
func _count_up(lbl: Label, to_value: int) -> void:
	if SettingsManager.reduce_motion() or to_value <= 0:
		return
	lbl.tree_entered.connect(func():
		var f: Font = lbl.get_theme_font("font")
		if f != null:
			lbl.custom_minimum_size.x = f.get_string_size(_fmt_comma(to_value),
				HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				lbl.get_theme_font_size("font_size")).x
		lbl.text = "0"
		var tw := lbl.create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_method(func(v: float): lbl.text = _fmt_comma(int(round(v))),
			0.0, float(to_value), DesignSystem.DUR_SLOW))

# --- 6. Share & Invite --------------------------------------------------------
func _share_block() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	box.add_child(_share_card_preview())
	box.add_child(_nav_row("Share your card",
		"A picture of your profile, ready to post.", func(): _share_profile(), "share"))
	box.add_child(_nav_row("Copy player ID",
		"ID %s. Quote it when you contact support." % _player_id(),
		func(): _copy(_player_id(), "Player ID copied",
			"Paste it anywhere you need to identify this profile."), "profile"))
	box.add_child(_nav_row("Invite a friend",
		"Copy an invite with the store link.",
		func(): _copy("Play NUMSLIDE Limitless with me: %s" % STORE_URL, "Invite copied",
			"Paste it into any chat to send the game to a friend."), "invite"))
	box.add_child(_nav_row("Rate on Google Play",
		"Ratings are how people find the game.", func(): _open_store(), "rank_badge"))
	return box

## The share card, rendered LIVE at the top of the panel.
##
## This is the prettiest thing the page owns and until now nobody saw it: it
## existed only inside `_share_profile`, behind a tap, a two-frame render and a
## modal. Meanwhile this panel was four rows of text over half a screen of empty
## pane. Showing the artifact IS the section — the rows below it become captions
## on a thing the player can already see.
##
## Rendered through a SubViewport rather than by building the card at preview
## size: `_share_card_content` is authored at 720x900 with fixed type sizes and a
## 300pt emblem, so a smaller box would not scale it, it would break its layout.
## One render target, scaled down by the TextureRect, is the same picture.
##
## The target STOPS UPDATING once it has drawn. A live 720x900 UPDATE_ALWAYS
## viewport is a real per-frame GPU cost on a phone for a picture that never
## changes, and the render target keeps its last contents when updates are
## disabled — so the preview stays on screen and the cost does not.
func _share_card_preview() -> Control:
	const CARD := Vector2(720, 900)
	var holder := Control.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Sized so the preview AND all four rows below it clear the panel without
	# scrolling. The card is 4:5, so this height is really a width budget: taller
	# looks better in isolation and pushes "Rate on Google Play" under the fold,
	# where a section that fits is worth more than a picture that is bigger.
	holder.custom_minimum_size.y = 400

	var vp := SubViewport.new()
	vp.size = Vector2i(CARD)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.add_child(_share_card_content(CARD))
	holder.add_child(vp)

	var view := TextureRect.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(view)

	# The texture is claimed on `ready`, not here. A ViewportTexture resolves
	# through the SubViewport's node PATH, so asking for one before the viewport is
	# in the tree hands back a texture bound to nothing. `ready` is the first
	# moment every child of `holder` is guaranteed present.
	holder.ready.connect(func():
		if not is_instance_valid(vp):
			return
		view.texture = vp.get_texture()
		_freeze_preview(vp))

	# The picture is the affordance. Tapping it does what the row under it says,
	# which is the whole reason a preview beats a description.
	UI.make_scroll_tappable(holder, func(): _share_profile())
	return holder

## Lets the preview's target draw, then stops it re-rendering forever.
##
## FRAME-COUNTED, not a wall-clock timer, and not `RenderingServer.frame_post_draw`.
## A timer makes "has it frozen yet?" a race against the machine, which is exactly
## the kind of assertion that passes on the developer's box and fails on someone
## else's; `frame_post_draw` is the signal `_share_profile` uses, but it is a
## RENDER signal and this also has to behave under the headless driver the
## regression suite runs on. `process_frame` fires everywhere and three of them is
## comfortably past the card's first layout pass and draw.
func _freeze_preview(vp: SubViewport) -> void:
	for _i in 3:
		await get_tree().process_frame
	if is_instance_valid(vp):
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

## The clipboard IS the share sheet here. The Android intent needs a native
## plugin the project does not carry (see _share_profile), and "copied, now
## paste it" is a thing every player can finish — unlike a button that opens
## nothing.
func _copy(text: String, title_text: String, msg: String) -> void:
	DisplayServer.clipboard_set(text)
	_toast(title_text, msg)

## The Play listing. `market://` hands straight to the installed Play app; the
## https form is the fallback everywhere else (and on a device without Play).
func _open_store() -> void:
	if OS.get_name() == "Android":
		OS.shell_open("market://details?id=%s" % STORE_PACKAGE)
		return
	OS.shell_open(STORE_URL)

# --- 7. Support & About -------------------------------------------------------
func _support_block() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	box.add_child(_nav_row("How to play",
		"A quick tour of the rules.",
		func(): SceneRouter.goto(SceneRouter.Route["HOW_TO_PLAY"]), "how_to_play"))
	box.add_child(_nav_row("Contact support",
		SUPPORT_EMAIL, func(): _contact_support(), "mail"))
	box.add_child(_nav_row("Data & privacy",
		"What's stored, and how to erase it.", func(): _privacy_modal(), "shield_lock"))
	box.add_child(_info_card("Version", _version_text(),
		"Quote this version if you report a problem."))
	return box

func _version_text() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.1.0"))

## Opens the mail client with the triage facts already filled in. A support mail
## that arrives without a version, a device and a player id costs one whole
## round trip before anyone can start reading it.
func _contact_support() -> void:
	var subject := "NUMSLIDE Limitless support (%s)" % _version_text()
	var body := "\n\n---\nPlayer ID: %s\nVersion: %s\nDevice: %s %s\n" % [
		_player_id(), _version_text(), OS.get_name(), OS.get_model_name()]
	OS.shell_open("mailto:%s?subject=%s&body=%s" % [
		SUPPORT_EMAIL, subject.uri_encode(), body.uri_encode()])

## The same disclosure Settings carries (settings.gd _privacy_modal). The honest
## split under the Play-only stack: local data is erased here, the Play Games
## profile is Google-owned, and a purchase belongs to the Google Play account.
func _privacy_modal() -> void:
	var m := ModalOverlay.new()
	m.set_header("Data & Privacy", "Your data, on your device",
		"Your stats, achievements, best scores, settings and games in progress are stored on this device only.\n\nYour Play Games identity (gamer tag, leaderboard scores) belongs to your Google account and is managed in the Play Games app.\n\nA premium purchase stays with your Google Play account and can be restored anytime.")
	m.add_action("Delete account & data", PremiumButton.Variant.DANGER, func():
		m.close()
		_confirm_delete())
	m.add_action("Close", PremiumButton.Variant.GLASS, func(): m.close())
	m.open(self)

# --- 8. Account deletion ------------------------------------------------------
## Google Play requires an in-app account-deletion path, and the account page is
## where players look for it. Rendered in normal text, not danger red: compliance
## asks for a reachable path, not a red banner shouting over the rest of the
## page. The confirm modal — where the choice is actually made — keeps the full
## danger treatment.
func _delete_card() -> Control:
	return _nav_row("Delete account & data",
		"Erase all game data from this device.", func(): _confirm_delete(), "trash", "text_dim")

func _confirm_delete() -> void:
	var m := ModalOverlay.new()
	m.set_header("Profile", "Delete account & data?",
		"This erases every stat, achievement, best score, setting and game in progress on this device. It can't be undone.\n\nYour Play Games profile (gamer tag, leaderboard scores) belongs to your Google account — remove this game's data in the Play Games app: Settings → Delete Play Games account & data.\n\nA premium purchase stays with your Google Play account and can be restored anytime.")
	m.add_action("Delete everything", PremiumButton.Variant.DANGER, func(): _delete_everything())
	m.add_action("Cancel", PremiumButton.Variant.GHOST, func(): m.close())
	m.open(self)

## Wipe, then quit. SaveManager latches a wiped flag, so nothing can re-persist a
## section during quit teardown (this screen's own rebuild writes "joined" and
## "player_id" back on read). Premium re-grants automatically from Play ownership
## on the next billing connect — deleting data must never delete a purchase.
func _delete_everything() -> void:
	SaveManager.wipe()
	get_tree().quit()

# --- Share card ---------------------------------------------------------------
## Renders the identity into a polished share card image (user://profile_card.png)
## and shows it in a modal with where it was saved — on desktop the file manager
## opens on it, so it's one drag away from anywhere. (The Android share-sheet
## intent needs a native plugin; when one lands, this is its single call site.)
func _share_profile() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(720, 900)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	vp.add_child(_share_card_content(Vector2(720, 900)))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var img := vp.get_texture().get_image()
	vp.queue_free()
	const PATH := "user://profile_card.png"
	var err := img.save_png(PATH)
	var m := ModalOverlay.new()
	m.compact = true
	if err != OK:
		m.set_header("Share", "Couldn't render the card", "Something went wrong saving the image.")
	else:
		m.set_header("Share", "Your card is ready",
			"Saved as profile_card.png in the game's data folder.")
		var tex := ImageTexture.create_from_image(img)
		var prev := TextureRect.new()
		prev.texture = tex
		prev.custom_minimum_size = Vector2(360, 450)
		prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		prev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		m._col.add_child(prev)
		if OS.get_name() != "Android":
			m.add_action("Show file", PremiumButton.Variant.GLASS, func():
				OS.shell_show_in_file_manager(ProjectSettings.globalize_path(PATH)))
	m.add_action("Done", PremiumButton.Variant.PRIMARY, func(): m.close())
	m.open(self)

## The card itself: identity on a deep theme gradient — badge, name, rank and the
## headline score, signed with the game's name. This is the one place the rank
## emblem still appears: a card you hand to someone else is exactly where a
## trophy belongs.
func _share_card_content(box: Vector2) -> Control:
	var p := _profile()
	var ratio: float = GameStats.best_mastery_ratio()["ratio"]
	var tier_idx: int = TierBadge.current_index(ratio)
	var accent := _rank_accent()
	var aura: Color = TierBadge.aura_color(int(p.get("avatar", -1)), accent)
	var pal := ThemeManager.palette()

	var root := Control.new()
	root.size = box
	var bg := GradientPanel.make(pal["bg0"], pal["bg1"].lerp(accent, 0.24), 0.0, Vector2(0, 1))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))

	const BADGE := 300.0
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(BADGE, BADGE)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.add_child(_soft_glow(BADGE, aura, 0.6))
	var emblem := TierBadge.make_view(BADGE, maxi(tier_idx, 0), tier_idx < 0)
	emblem.set_anchors_preset(Control.PRESET_FULL_RECT)
	emblem.custom_minimum_size = Vector2.ZERO
	holder.add_child(emblem)
	TierBadge.add_frame(holder, BADGE, TierBadge.equipped_frame(p), aura)
	col.add_child(holder)

	var name_lbl := _label(_identity_name(), 84)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_color_override("font_color", pal["text"])
	if ThemeManager.display_font:
		name_lbl.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(name_lbl)

	var tier_name := "Unranked" if tier_idx < 0 else String(TierBadge.tier(tier_idx)["name"])
	var chip := _chip(tier_name, accent)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(chip)

	var score := _label("BEST SERIES  %s" % UI.commafy(int(GameStats.get_stat("best_score"))), 40)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score.add_theme_color_override("font_color", Color(pal["text"], 0.9))
	if ThemeManager.display_font:
		score.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(score)

	var brand := _label("T I C   T A C   T O E   L I M I T L E S S", 28)
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_color_override("font_color", Color(accent, 0.9))
	col.add_child(brand)
	root.add_child(col)
	return root

# --- Identity editing (name + status + badge) ---------------------------------
## The sheet itself is IdentitySheet — ONE editor, shared with the Badge page.
## It used to be ~95 lines copy-pasted into both screens, which is how the two
## ended up labelling the same control "AVATAR COLOUR" here and "BADGE AURA"
## there, for a setting that paints the same badge on both pages.
func _edit_identity() -> void:
	IdentitySheet.open(self, func(): _refresh())

# --- Shared card shapes -------------------------------------------------------
## A panel's header: an accent tick, the section's name, and its optional jump to
## the screen that owns the subject ("Shop ›", "Statistics ›").
##
## Since the rail landed this is a PANEL TITLE rather than one heading in a
## stack — the same role the header bar plays over an editor's side panel. It
## still carries the section's exact name because that name is the page's
## contract: the rail's tooltip, the panel's title and the flow test's expected
## string are all this one word.
func _section(eyebrow_text: String, body: Control, action_text: String, action_cb: Callable) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))

	var tick := Panel.new()
	tick.custom_minimum_size = Vector2(6, 44)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = ThemeManager.color("accent")
	tsb.set_corner_radius_all(3)
	tsb.anti_aliasing = true
	tick.add_theme_stylebox_override("panel", tsb)
	header.add_child(tick)

	var ey := Label.new()
	ey.text = eyebrow_text.to_upper()
	ey.add_theme_font_size_override("font_size", 38)
	ey.add_theme_color_override("font_color", ThemeManager.color("text"))
	ey.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ThemeManager.display_font:
		ey.add_theme_font_override("font", ThemeManager.display_font)
	header.add_child(ey)
	if not action_text.is_empty() and action_cb.is_valid():
		var act := Label.new()
		act.text = action_text + "  ›"
		act.add_theme_font_size_override("font_size", 36)
		act.add_theme_color_override("font_color", UI.ink("accent"))
		act.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UI.make_scroll_tappable(act, action_cb)
		header.add_child(act)
	box.add_child(header)
	# A rule under the title, in the accent, FADING OUT to the right. A gap reads
	# as absence and a full hard line reads as a table border; a fading rule reads
	# as a title's underline, which is the only one of the three this is. It is
	# also the page's one repeated piece of colour outside the hero — six panels
	# whose only accent was a 6pt tick is most of why the sections read as grey.
	box.add_child(_accent_rule())
	box.add_child(body)
	return box

## A 2pt accent rule that fades to nothing across the panel's width.
func _accent_rule() -> Control:
	var grad := Gradient.new()
	var a: Color = ThemeManager.color("accent")
	grad.set_color(0, Color(a.r, a.g, a.b, 0.5))
	grad.set_color(1, Color(a.r, a.g, a.b, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 64
	tex.height = 2
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.custom_minimum_size.y = 2
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

## The shared "icon / title / subtitle / chevron" row behind every destination on
## this page. One shape, so they read as one family rather than as differently
## weighted banners.
##
## The icon is not decoration. Twelve identical rows of two grey text lines is a
## page you read rather than scan, and every other list in the app (Shop's items,
## Home's hub, Settings) leads its rows with an IconLibrary token. Six of these
## ids were authored for this page — an icon-less row here would stand out as the
## broken one, which is why the leader is required rather than optional.
func _nav_row(title_text: String, sub_text: String, on_tap: Callable,
		icon_id: String = "", title_key: String = "text") -> Control:
	var card := _card(2)
	# MARKED, and the mark is a contract rather than debug convenience. The flow
	# asserts "every destination row leads with exactly one icon", and it used to
	# do that by counting every drawn texture in the whole panel against the number
	# of rows — an aggregate that only worked while rows were the only thing in a
	# panel carrying art. They are not any more (the share preview, the premium
	# showcase and the panel rule all draw), so the count is now taken PER ROW,
	# which is both what the sentence actually claims and strictly stronger: it
	# fails on one row losing its leader even if another grew a second one.
	#
	# METADATA, not `name`. The obvious version set `name = "NavRow"` and matched
	# the prefix — and it silently found exactly ONE row. `add_child` without
	# `force_readable_name` does not append a serial to a colliding name, it
	# replaces it with `@NavRow@2`, which no longer starts with the prefix. Four
	# rows, one match, and an assertion that looked like it was checking all of
	# them. Metadata survives whatever the engine does to names.
	card.set_meta("nav_row", true)
	card.custom_minimum_size = Vector2(0, 168)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(row)

	if not icon_id.is_empty():
		# Native colours (empty tint key) — these carry the set's own gold / glass
		# / cyan story, and that variety across a column is most of what turns a
		# list into something worth looking at. The rail tints ITS copies flat for
		# the opposite reason: there, one hue is what makes it read as a control.
		var ic := UI.icon_rect(icon_id, 76.0, "")
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 4)
	# WRAPPING, not clipped. `_label` defaults to AUTOWRAP_OFF, which makes a
	# title's full rendered width a hard MINIMUM that propagates up through the
	# panel's ScrollContainer (horizontal scrolling is disabled, so it cannot
	# absorb it) and out to the page — "Delete account & data" alone demanded
	# 568pt and pushed the whole layout past the 982 budget, whose only visible
	# symptom is the top bar's gear getting clipped. A title with room still sits
	# on one line; this only costs a second line when there genuinely isn't room.
	var title := _label(title_text, 40)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", ThemeManager.color(title_key))
	if ThemeManager.display_font:
		title.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(title)
	var sub := _label(sub_text, 34)
	sub.add_theme_color_override("font_color", UI.ink("text_dim", 0.35))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	row.add_child(col)

	if on_tap.is_valid():
		var chev := _chevron()
		chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chev)
		UI.make_scroll_tappable(card, on_tap)
	return card

## The same row shape with nothing to tap: a stated fact, optionally with a line
## of explanation under it.
func _info_card(eyebrow_text: String, value_text: String, note_text: String = "") -> Control:
	var card := _card(2)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)

	var ey := _label(eyebrow_text.to_upper(), 30)
	ey.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	col.add_child(ey)

	var val := _label(value_text, 40)
	val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.add_theme_color_override("font_color", ThemeManager.color("text"))
	if ThemeManager.display_font:
		val.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(val)

	if not note_text.is_empty():
		var note := _label(note_text, 32)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
		col.add_child(note)
	return card

## A rounded pill wearing `accent` — a soft tint fill, a brighter rim, and the
## text in the accent itself.
func _chip(text: String, accent: Color) -> Control:
	# On a LIGHT palette the accent's own hue is the fill AND the ink, and a gold
	# "GOLD" on a pale gold wash is a fuzzy blob rather than a word. UI.ink_of
	# keeps the hue and pushes the text toward the palette's own, which is the
	# same correction every accent-as-text on this page now takes.
	var ink: Color = UI.ink_of(accent, 0.5)

	var pill := PanelContainer.new()
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.r, accent.g, accent.b, 0.16)
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_PILL))
	sb.set_border_width_all(1)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	sb.content_margin_left = DesignSystem.SPACE_SM
	sb.content_margin_right = DesignSystem.SPACE_SM
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sb.anti_aliasing = true
	pill.add_theme_stylebox_override("panel", sb)
	var lbl := _label(text.to_upper(), 30)
	lbl.add_theme_color_override("font_color", ink)
	if ThemeManager.display_font:
		lbl.add_theme_font_override("font", ThemeManager.display_font)
	pill.add_child(lbl)
	return pill

## The player's aura as LIGHT behind the hero row — a soft radial in the colour
## they chose, biased LEFT so it sits under the picture rather than under the
## text. The same gold that reads as depth behind a portrait reads as a stain
## behind a paragraph, worst on the warm light palettes.
##
## `set_anchors_and_offsets_preset`, never `set_anchors_preset`. The latter keeps
## the node's CURRENT rect — 0x0 at build time — by writing compensating offsets,
## so the wash silently renders as nothing at all and no error is raised. The
## radial's own alpha reaches zero at its ellipse boundary, so the corners are
## already transparent and no rect clip is needed (which would cut across the
## card's rounded corner anyway).
func _aura_wash(aura: Color) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var glow := TextureRect.new()
	var gt := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(aura.r, aura.g, aura.b, 0.30))
	grad.set_color(1, Color(aura.r, aura.g, aura.b, 0.0))
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	glow.texture = gt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Left 62% of the card, so the ellipse centres near the 240pt picture.
	glow.anchor_right = 0.62
	glow.offset_top = -DesignSystem.SPACE_LG
	glow.offset_bottom = DesignSystem.SPACE_LG
	holder.add_child(glow)

	# A slow breath, so the hero is the one thing on the page that is alive.
	# Wired on `tree_entered` because `create_tween` needs the node in the tree,
	# and this whole card is built before it is parented.
	if not SettingsManager.reduce_motion():
		glow.tree_entered.connect(func():
			var tw := glow.create_tween().set_loops()
			tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			tw.tween_property(glow, "modulate:a", 0.55, 2.8)
			tw.tween_property(glow, "modulate:a", 1.0, 2.8))
	return holder

## One identifying fact as a small labelled pill: a dim key and its value.
##
## `control` / `control_stroke`, never `glass` / `stroke`. These sit ON the hero
## card, and the glass fill is near-white on the light palettes — a glass pill on
## a glass card is white on white.
func _fact_pill(key: String, value: String) -> Control:
	var pill := PanelContainer.new()
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeManager.color("control")
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_PILL))
	sb.set_border_width_all(1)
	sb.border_color = ThemeManager.color("control_stroke")
	sb.content_margin_left = DesignSystem.SPACE_SM
	sb.content_margin_right = DesignSystem.SPACE_SM
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	sb.anti_aliasing = true
	pill.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))
	var k := _label(key.to_upper(), 28)
	k.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(k)
	var v := _label(value, 32)
	v.add_theme_color_override("font_color", ThemeManager.color("text"))
	row.add_child(v)
	pill.add_child(row)
	return pill

func _toast(title_text: String, msg: String) -> void:
	var m := ModalOverlay.new()
	m.compact = true
	m.set_header("Profile", title_text, msg)
	m.add_action("Done", PremiumButton.Variant.PRIMARY, func(): m.close())
	m.open(self)

# --- Small helpers ------------------------------------------------------------
## The SAME frosted glass card the rest of the app uses (Home's menu, the
## game-mode cards, Statistics): a real GlassPanel that samples and blurs the
## backdrop — including the drifting shard field — behind it.
func _card(elevation: int = 2) -> PanelContainer:
	return UI.glass_card(elevation)

func _fmt_comma(n: int) -> String:
	return UI.commafy(n)

## A soft radial halo sized to sit behind a `box`-sized element.
func _soft_glow(box: float, col: Color, strength: float) -> TextureRect:
	var glow := TextureRect.new()
	var gt := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(col.r, col.g, col.b, strength))
	grad.set_color(1, Color(col.r, col.g, col.b, 0.0))
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	glow.texture = gt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := box * 0.28
	glow.offset_left = -pad; glow.offset_top = -pad
	glow.offset_right = pad; glow.offset_bottom = pad
	return glow

## Every non-wrapping label on this page. A FitLabel rather than a bare Label
## because this page has the app's tightest width budget after Home (see
## PanelRail.RAIL_W, which documents the same 982-point ceiling) and a Label with
## autowrap off answers a box too narrow for it by drawing through the box's edge.
## Unexpanding, it claims the same natural width a plain Label did, so nothing
## moves until the text genuinely does not fit; callers that must be bounded say
## so with `max_width`.
func _label(text: String, font_sz: int) -> FitLabel:
	var l := FitLabel.make(text, font_sz)
	l.add_theme_font_size_override("font_size", font_sz)
	l.budget_text = text
	return l

func _chevron() -> Label:
	var l := Label.new()
	l.text = "›"
	l.add_theme_font_size_override("font_size", 62)
	var col: Color = ThemeManager.color("text_dim")
	col.a = 0.7
	l.add_theme_color_override("font_color", col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l
