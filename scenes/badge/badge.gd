extends AppScreen
## Badge — the PROGRESSION page, reached by tapping Home's floating tier capsule.
##
## THIS IS NOT THE PROFILE TAB. The game has two identity destinations and they
## answer different questions, which is the whole reason they are separate
## screens:
##
##   • Badge (here, route BADGE) — "how am I doing?" The tier badge you just
##     tapped, blown up and playable, and everything the ladder is made of.
##     Reached ONLY from the Home capsule, because the capsule IS this badge.
##   • Profile (route PROFILE, the bottom-nav tab) — "who am I, what account am
##     I on, what have I paid for?" See scenes/profile/profile.gd.
##
## Sending the capsule to the account page was the mistake this split fixes: a
## player taps a rank badge and expects the rank, not a membership card.
##
## Read top to bottom as ONE card per section under ONE header, separated by a
## full SPACE_XL band:
##
##   Hero (identity only) → Rank → Highlights → Streak → Trophy Case →
##   Mastery by Mode → Recent Runs → Full statistics → Account & Data
##
## The page is deliberately long and deliberately NOT dense. It used to carry
## three near-identical three-across stat strips printing nine of the ten numbers
## the Statistics screen already owns; those are gone, replaced by one link to
## that screen. What's left is what only a profile can say: who you are, what rank
## you hold and what's next, the habit, the collection, and the per-mode series
## mastery the tier ladder is actually computed from.
##
## Identity lives in the "profile" save section { name, avatar, joined, status } —
## the SAME section the Profile tab reads and writes, so a name or avatar changed
## on either page shows on both.
## Play Games is the sole account provider (see AccountManager) — the account row
## rides at the top as a call to action while signed out, and files itself under
## Account & Data once signed in.
##
## NOTE: the Account & Data block, the delete-account row and the share card are
## also carried by the Profile tab. That duplication is deliberate for now — this
## page was restored as it was rather than trimmed — and is the obvious follow-up
## if the two pages should each own their half.

const SECTION := "profile"
const BEST_SECTION := "best_scores"

const C_VIOLET := Color("7B6CF6")
const C_INDIGO := Color("5B57E0")
const C_BLUE := Color("4D8DF0")
const C_AMBER := Color("F4B23E")
const C_GOLD := Color("F4B93E")
const C_TEAL := Color("36C7B8")
const C_GREEN := Color("57C77A")
const C_PINK := Color("F178B6")

const _MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

## Stars ONE hero-badge tap sends down - four times what it used to spend.
## This is a count, not a rate: how many are in the air at any moment is
## `StarRain.MAX_STARS`, and that ceiling is the thing frame time is bought
## with. Raising THIS makes the shower last longer; raising the ceiling makes
## it denser and costs per frame.
const STAR_BURST := 256

## A soft living layer for the hero card: theme tile shards and light dots
## drifting slowly upward, each fading in and out on its own clock. Only ever
## instanced when reduce-motion is off.
class HeroParticles extends Control:
	var tint: Color = Color.WHITE
	const RAMP := [2, 4, 8, 16, 32, 64, 128]

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_spawn.call_deferred()

	func _spawn() -> void:
		await get_tree().process_frame   # let the card lay out first
		if not is_inside_tree() or size.x < 40.0 or size.y < 40.0:
			return
		for i in 12:
			var piece: Control
			if i % 3 == 0:
				piece = TierBadge._burst_dot(Color.WHITE.lerp(tint, randf_range(0.3, 0.7)))
			else:
				var v: int = RAMP[randi() % RAMP.size()]
				piece = TierBadge._shard(ThemeManager.tile_style(v)["bg"])
			var sz := randf_range(8.0, 18.0)
			piece.size = Vector2(sz, sz)
			piece.pivot_offset = Vector2(sz, sz) * 0.5
			piece.modulate.a = 0.0
			add_child(piece)
			_cycle(piece, true)

	## One drift pass: appear low, rise, glow, fade — then again from a new spot.
	func _cycle(p: Control, first: bool) -> void:
		if not is_instance_valid(p) or not is_inside_tree():
			return
		var sz := p.size.x
		p.position = Vector2(randf_range(0.0, maxf(size.x - sz, 1.0)),
			size.y * randf_range(0.45, 0.95))
		p.rotation = randf_range(-0.6, 0.6)
		var rise := size.y * randf_range(0.25, 0.5)
		var dur := randf_range(3.2, 6.0)
		var delay := randf_range(0.0, 2.5) if first else randf_range(0.0, 0.8)
		var tw := p.create_tween().set_parallel()
		tw.tween_property(p, "position:y", p.position.y - rise, dur).set_delay(delay)
		tw.tween_property(p, "rotation", p.rotation + randf_range(-0.8, 0.8), dur).set_delay(delay)
		var ta := p.create_tween()
		ta.tween_interval(delay)
		ta.tween_property(p, "modulate:a", randf_range(0.25, 0.5), dur * 0.4)
		ta.tween_property(p, "modulate:a", 0.0, dur * 0.6)
		tw.finished.connect(func(): _cycle(p, false))

# Achievement tiers — a mastery ladder evaluated from series won against a
# mode's own yardstick (GameStats.best_mastery_ratio). The tier data,
# progression rule and painted-shield art live in `TierBadge` so the profile
# rank emblem, the medallion rail and the home profile icon all track the same
# progression.

var _main_col: VBoxContainer
var _hero_inner: Control   # the hero badge stack, for the scroll parallax
var _hero_par_t := -1.0    # last applied parallax t — gates redundant subtree writes
var _rain: StarRain        # the live star-shower layer; repeat taps top it up
var _scroll: ScrollContainer   # the page's scroll, for the reveal + the capsule
var _header_band: Control      # the rank-tinted wash behind the top bar
var _sticky: Control           # the rank capsule that docks once the hero leaves
var _atm_t := -1.0             # last applied atmosphere t — gates redundant writes
## Sections still waiting to be scrolled to. Emptied as they are revealed, which
## is what lets `_reveal_pass` sit on the scroll path and cost nothing after the
## first few flicks.
var _pending: Array = []
var _case_view := 0            # 0 rail, 1 grid, 2 sky (persisted in the profile)
var _case_body: MarginContainer
## The newest medal, resolved once per build — every medallion in the case asks,
## and the answer walks the whole catalogue.
var _newest_cached := false
var _newest_id := ""
var _newest_at := 0

func on_ready() -> void:
	custom_entrance = true
	# Home's glass-shard identity behind the page — the profile is painted in the
	# game's own tiles, not floating on a bare gradient.
	# The page's air takes the RANK's colour, not only the theme's: a Diamond
	# profile drifts through cold light and an Infinity one through violet, so the
	# whole screen belongs to the badge at the top of it, not just the badge
	# itself. Unranked leaves the field exactly as the theme dealt it.
	var drift := add_glass_drift()
	var rank: int = TierBadge.current_index(GameStats.best_mastery_ratio()["ratio"])
	if drift != null and rank >= 0:
		drift.rank_tint = Color(TierBadge.metal(rank)["air"], 0.55)
	AccountManager.auth_changed.connect(func(): _refresh())
	# The Play Games gamer tag lands AFTER the session does, so refresh when it
	# arrives or the account card would keep showing the placeholder.
	AccountManager.profile_changed.connect(func(): _refresh())
	# Fires only for explicit sign_in() attempts, never for the automatic launch
	# prompt — so this toast can't nag on boot.
	AccountManager.sign_in_failed.connect(func(): _toast("Sign-in unavailable", "Play Games sign-in isn't available right now."))
	content.modulate.a = 0.0
	await get_tree().process_frame
	content.modulate.a = 1.0
	# Split at the fold rather than staggering the whole column: eight of this
	# page's nine sections are below it on arrival, and animating them there
	# spends the entrance on cards nobody can see — and leaves them simply
	# PRESENT, with no arrival at all, by the time they are scrolled to.
	_split_entrance()
	_on_scroll_atmosphere(0.0)

func build_content(root: VBoxContainer) -> void:
	# Bake the star bitmap HERE, on a frame the player is already waiting on,
	# rather than letting it happen inside StarRain._init() on the first badge
	# tap. Idempotent and static, so this costs nothing after the first build.
	StarRain.bake()
	# Per-build state. A rebuild (theme change, identity edit, sign-in) runs this
	# whole function again, and a pending-reveal list left over from the previous
	# tree is a list of freed nodes.
	_pending.clear()
	_newest_cached = false
	_newest_id = ""
	_newest_at = 0
	_atm_t = -1.0
	_case_view = clampi(int(_profile().get("case_view", 0)), 0, CASE_VIEWS.size() - 1)
	root.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))
	_build_top_bar(root)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.clip_contents  = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	SmoothWheel.attach(scroll)   # desktop wheel glides instead of stepping
	_scroll = scroll
	root.add_child(scroll)
	# Scroll parallax: as the page scrolls, the hero badge scales away and
	# fades — depth instead of a flat crop.
	scroll.get_v_scroll_bar().value_changed.connect(_on_hero_parallax)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", int(DesignSystem.SPACE_MD))
	margin.add_theme_constant_override("margin_right", int(DesignSystem.SPACE_MD))
	margin.add_theme_constant_override("margin_bottom", int(DesignSystem.SPACE_2XL))
	scroll.add_child(margin)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# One full SPACE_XL band between sections. Every block below is ONE card under
	# ONE header, and this air is what keeps a deliberately long page from reading
	# as a congested one.
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_XL))
	margin.add_child(col)
	_main_col = col

	col.add_child(_hero_card())
	# A signed-OUT player gets the sign-in prompt up top, where it reads as a call
	# to action; once signed in the same card is just a fact, and it files itself
	# under Account & Data at the foot of the page.
	var promote_sign_in := AccountManager.is_configured() and not AccountManager.is_signed_in()
	if promote_sign_in:
		col.add_child(_section("Account", _account_card(), "", Callable()))
	col.add_child(_section("Rank", _rank_card(), "", Callable()))
	col.add_child(_section("Highlights", _highlights(), "", Callable()))
	col.add_child(_section("Streak", _streak_card(), "", Callable()))
	col.add_child(_section("Trophy Case", _trophy_case(), "View All",
		func(): SceneRouter.goto(SceneRouter.Route["ACHIEVEMENTS"])))
	# The section that names something still unbeaten, so it earns the only
	# outbound "go do it" link on the page. Before there is any mastery to break
	# down it teases instead of vanishing: dropping out entirely left the page
	# silent about where a rank comes from for exactly the player who has never
	# seen one.
	var mastery: Control = _mastery_card()
	if mastery == null:
		mastery = _mastery_teaser()
	col.add_child(_section("Mastery by Mode", mastery, "Play",
		func(): SceneRouter.goto(SceneRouter.Route["HOME"])))
	col.add_child(_section("Recent Series", _recent_scores_card(), "", Callable()))
	# The lifetime numbers belong to Statistics. This page links to them instead of
	# reprinting nine of the ten stats that screen already owns.
	col.add_child(_nav_row("Full statistics",
		"Moves, play time, win rate and records by mode.", "text",
		func(): SceneRouter.goto(SceneRouter.Route["STATISTICS"])))
	# The native Play Games leaderboards — only once signed in, since the OS
	# sheet needs an authenticated session behind it.
	if AccountManager.is_signed_in():
		col.add_child(_nav_row("Leaderboards",
			"See how your best scores rank worldwide.", "text",
			func(): PlayGames.show_leaderboards()))
	col.add_child(_section("Account & Data", _account_block(promote_sign_in), "", Callable()))

func _refresh() -> void:
	for c in content.get_children():
		c.queue_free()
	build_content(content)

# --- Data ---------------------------------------------------------------------
func _profile() -> Dictionary:
	return SaveManager.get_section(SECTION, {"name": "Player", "avatar": -1})

func _save(p: Dictionary) -> void:
	SaveManager.set_section(SECTION, p)

## The identity name: the Play Games profile name once it has loaded, falling
## back to the locally-saved name from pre-PGS saves, else "Player".
func _identity_name() -> String:
	var tag := AccountManager.display_name()
	if not tag.is_empty():
		return tag
	return String(_profile().get("name", "Player"))

func _joined_text() -> String:
	var p := _profile()
	var unix := int(p.get("joined", 0))
	if unix <= 0:
		unix = int(Time.get_unix_time_from_system())
		p["joined"] = unix
		_save(p)
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "Joined %s %d" % [_MONTHS[int(d["month"]) - 1], int(d["year"])]

# --- Top bar ------------------------------------------------------------------
func _build_top_bar(root: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))
	bar.add_child(UI.circle_button("back", "",
		func(): SceneRouter.back(), 120.0))
	# The rank capsule lives in the gap between the back arrow and the share
	# button, and fades in only once the hero it mirrors has scrolled away.
	bar.add_child(_sticky_capsule())
	# The design sheet's magenta paper plane (IconLibrary "share"), on the SAME
	# plain circle button as its two neighbours. The old "↗" was a text glyph
	# on a glass chip that neither the back arrow nor the gear wore, so a
	# three-button bar carried two different kinds of control — and the arrow
	# came from the UI font rather than the icon set, so it changed shape with
	# the display face. Flat (no baked glow): the token brings its own contour
	# and cast shadow. The Profile tab's bar wears the identical control.
	bar.add_child(UI.circle_button("share", "",
		func(): _share_profile(), 120.0, false))
	# The SAME gear as Home's top bar — the original PNG tinted to the theme's dim
	# text, not the runtime gradient icon. The settings entry point must look
	# identical on every screen that offers it.
	bar.add_child(UI.circle_button("res://assets/icons/settings.png", "text_dim",
		func(): SceneRouter.goto(SceneRouter.Route["SETTINGS"]), 120.0))
	root.add_child(_top_bar_stack(bar))

# --- Hero (identity) ----------------------------------------------------------
## The centrepiece, and ONLY identity: a floating tier badge on a breathing accent
## aura, the name in the display face, the tier chip, the join date and the status
## line. The mastery numbers used to live here too and made the card carry six
## different things — they now have their own Rank section directly below.
## The whole card taps through to name editing — the card itself is the
## affordance (there is deliberately no pencil in the top bar).
func _hero_card() -> Control:
	var p := _profile()
	var best := GameStats.best_mastery_ratio()
	var ratio: float = best["ratio"]
	var tier_idx: int = TierBadge.current_index(ratio)
	var accent := _tier_accent(tier_idx)
	# What this rank is MADE of, not just what colour it is: the light it throws,
	# the burst it celebrates with, the air it hangs in. Seven ranks used to share
	# one glow and one celebration, so the only thing that changed as a player
	# climbed was which PNG was on screen.
	var metal := TierBadge.metal(tier_idx)
	var still := bool(SettingsManager.get_value("reduce_motion"))

	# The same frosted glass pane the game-mode cards wear, one elevation up so
	# the identity block still reads as the page's focal point. With the shard
	# field drifting behind the page, the frost has real depth to sample — the
	# old opaque banner is gone.
	var card := UI.glass_card(3)
	card.clip_contents = true
	# The series this player has won, ghosted across the whole card behind
	# everything else. A poster spine: it fills the dead air either side of a
	# 300pt badge with the one number the page is ultimately about, at an ink
	# level that can never compete with the name printed over it.
	card.add_child(_hero_watermark(tier_idx))
	# A living layer of theme tile shards and light drifting up BEHIND the
	# identity — the hero breathes instead of sitting as a large empty surface.
	# Tinted by the RANK rather than the theme accent, so the air around a
	# Diamond badge is cold and an Infinity one is violet.
	if not still:
		var fx := HeroParticles.new()
		fx.tint = metal["air"]
		card.add_child(fx)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_LG))
	card.add_child(col)

	# Floating badge, ringed by its progress to the next tier, on a soft aura in
	# the player's chosen colour — all wrapped so they bob together without
	# fighting the VBox that owns the wrapper's position (home's pattern).
	const BADGE := 300.0
	const RING_TH := 22.0
	var next_accent := ThemeManager.color("gold") if tier_idx + 1 >= TierBadge.count() \
		else _tier_accent(tier_idx + 1)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(BADGE, BADGE)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var inner := Control.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(inner)

	var aura_col: Color = TierBadge.aura_color(int(p.get("avatar", -1)), accent)
	# The player's own aura still wins where they set one; the metal only fills in
	# the default. An aura is a choice, and a rank must not overrule it.
	var chose_aura := int(p.get("avatar", -1)) >= 0
	var glow_hot: Color = aura_col if chose_aura else metal["aura"]
	var glow_deep: Color = aura_col.darkened(0.35) if chose_aura else metal["aura2"]

	# An unranked badge is a TARGET, so its light is banked right down: at full
	# strength the faded Bronze shield sat in the middle of a blaze, which reads as
	# a celebration of having achieved nothing.
	var lit := 1.0 if tier_idx >= 0 else 0.40

	# Godrays first, under everything: light coming off the shield rather than a
	# disc of colour sitting behind it. Skipped under reduce-motion (a static fan
	# of beams reads as a printed sunburst, which is a different, worse thing) and
	# while unranked, where there is nothing yet to radiate.
	if not still and tier_idx >= 0:
		var rays := RayFan.new(glow_hot)
		rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var rpad := BADGE * 0.35
		rays.offset_left = -rpad; rays.offset_top = -rpad
		rays.offset_right = rpad; rays.offset_bottom = rpad
		rays.pivot_offset = Vector2(BADGE, BADGE) * 0.5 + Vector2(rpad, rpad)
		inner.add_child(rays)
		rays.tree_entered.connect(func():
			var tw := rays.create_tween().set_loops()
			tw.tween_property(rays, "rotation", TAU, 90.0).from(0.0))

	# TWO glow stops rather than one flat disc: a wide deep floor with a tighter
	# hot centre inside it. A single radial is a colour; two is a light source.
	var deep := _soft_glow(BADGE * 1.25, glow_deep, 0.20 * lit)
	inner.add_child(deep)
	var aura := _soft_glow(BADGE, glow_hot, 0.42 * lit)
	inner.add_child(aura)

	# The halo ring — a THICK soft white circle (the reference look), with the
	# progress-to-next-tier arc sweeping over it in the tier gradient, so the
	# ring is both the champion's halo and a live meter.
	var ring := ProgressRing.new()
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.thickness = RING_TH
	ring.track_color = Color(1, 1, 1, 0.9)
	ring.color_a = accent
	ring.color_b = next_accent
	# The ring stops being one number and becomes the LADDER: seven notches, lit
	# up to the rank held, so how far along the whole climb you are is readable
	# without scrolling to the trophy case for it. The hairline gives the 22pt
	# band a lip so it reads as a channel rather than a drawn circle, and the bead
	# marks the head of the fill — which is also the only moving part the fill
	# animation has to follow.
	ring.inner_hairline = true
	ring.bead = true
	ring.ticks = TierBadge.count()
	ring.ticks_lit = TierBadge.unlocked_count(ratio)
	var ring_target := TierBadge.progress_to_next(ratio)
	inner.add_child(ring)

	var emblem := TierBadge.make_view(BADGE, maxi(tier_idx, 0), tier_idx < 0)
	emblem.set_anchors_preset(Control.PRESET_FULL_RECT)
	emblem.custom_minimum_size = Vector2.ZERO
	var einset := RING_TH + 16.0
	emblem.offset_left = einset; emblem.offset_top = einset
	emblem.offset_right = -einset; emblem.offset_bottom = -einset
	# The same periodic light glint the home capsule's badge wears.
	emblem.material = TierBadge.shine_material()
	inner.add_child(emblem)
	# No drawn wreath here. Every badge in assets/images/badges already carries its
	# own laurel, in its OWN metal; the runtime gold one that used to be layered on
	# top wrapped a second garland over art that had one, crossed the halo ring,
	# and over Infinity's violet wings simply read as a rendering fault.
	# The Play Games picture, when there is one, as a medallion on the shoulder.
	# NOT over the shield's face: the badge is the subject of this page, and a
	# photo laid across it hides the one thing the player tapped to see.
	var photo := PhotoMedallion.new(AccountManager.icon_uri(), glow_hot)
	photo.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var pbox := BADGE * 0.28
	photo.offset_left = BADGE * 0.70; photo.offset_top = BADGE * 0.66
	photo.offset_right = photo.offset_left + pbox
	photo.offset_bottom = photo.offset_top + pbox
	inner.add_child(photo)
	# The equipped frame (identity sheet), drawn in the chosen aura colour.
	TierBadge.add_frame(inner, BADGE, TierBadge.equipped_frame(p), aura_col)
	# ...and the equipped effect above it, so what the badge gives off is never
	# hidden behind the ornament around it.
	BadgeCosmetics.add_effect(inner, BADGE, BadgeCosmetics.effect_of(p), glow_hot)
	_hero_inner = inner

	# A slow float + a breathing aura + a ring that fills in + twinkling sparkles,
	# so the rank avatar feels alive. Deferred to tree entry: the badge nodes aren't
	# in the tree until the card is added.
	aura.modulate.a = 0.85
	ring.value = 0.0
	_add_sparkles(inner, BADGE, aura_col)
	inner.tree_entered.connect(func():
		if not still:
			var bob := inner.create_tween().set_loops()
			bob.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			bob.tween_property(inner, "position:y", -5.0, 2.0)
			bob.tween_property(inner, "position:y", 5.0, 2.0)
			var gt := aura.create_tween().set_loops()
			gt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			gt.tween_property(aura, "modulate:a", 1.0, 1.7)
			gt.tween_property(aura, "modulate:a", 0.6, 1.8)
		var rt := ring.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		rt.tween_property(ring, "value", ring_target, DesignSystem.DUR_SLOW).set_delay(0.2))

	# The badge is a toy, not just a picture: press it and it leans toward your
	# finger; release on a clean tap and it pops with a sparkle burst; HOLD it and
	# the shield opens full size to be looked at. (The card around it still opens
	# the identity editor everywhere else.)
	inner.pivot_offset = Vector2(BADGE, BADGE) * 0.5
	var press := {"down": false, "moved": 0.0, "hold": 0, "inspected": false}
	holder.gui_input.connect(func(e: InputEvent):
		_hero_badge_input(e, holder, inner, tier_idx, press))

	# The reference layout: the NAME crowns the card, the badge fills its
	# centre, and the rank title sits beneath in gold.
	var name_lbl := _label(String(p.get("name", "Player")), 100)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The nameplate decides the ink, not the page: three of the four plates are
	# bright, and the theme's own "text" is near-white on every dark palette — so
	# equipping a plate would otherwise be the act that erases the name on it.
	var plate_idx := BadgeCosmetics.plate_of(p)
	name_lbl.add_theme_color_override("font_color",
		BadgeCosmetics.plate_ink(plate_idx, ThemeManager.color("text")))
	if ThemeManager.display_font:
		name_lbl.add_theme_font_override("font", ThemeManager.display_font)
	# CENTRED, so the plate hugs the name instead of stretching the width of the
	# card. The identity sheet previews it hugging, and a preview that shows a
	# pill where the page draws a full-width banner is a preview that lies about
	# the only thing it exists to show.
	var plate_wrap := CenterContainer.new()
	plate_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The label stops expanding once it is centred rather than filling, so it has
	# to be told what it may claim: a FitLabel with no ceiling reports the full
	# natural width of the name and walks a long one off the card.
	name_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	name_lbl.max_width = 700.0
	plate_wrap.add_child(BadgeCosmetics.plate_for(name_lbl, plate_idx, accent))
	col.add_child(plate_wrap)

	# The earned title, if one is worn. Under the name and above the badge, which
	# is where a title reads as an epithet rather than as a caption on the shield.
	var worn_title := BadgeCosmetics.title_of(p)
	if not worn_title.is_empty():
		var tl := _label(worn_title.to_upper(), 34)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tl.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
		col.add_child(tl)

	# Badge and its reflection ride in a gapless sub-column: the page's SPACE_LG
	# between them would float the shield above its own pedestal.
	var stage := VBoxContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.add_theme_constant_override("separation", 0)
	stage.add_child(holder)
	stage.add_child(_hero_pedestal(BADGE, tier_idx, glow_hot))
	col.add_child(stage)

	# "GOLD" — the tier as a title, in the tier's own metal. Just the rank name:
	# "MEMBER" said nothing the badge doesn't already say.
	var member_text := "UNRANKED" if tier_idx < 0 \
		else String(TierBadge.tier(tier_idx)["name"]).to_upper()
	var member := _label(member_text, 48)
	member.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	member.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	member.add_theme_color_override("font_color",
		ThemeManager.color("text_dim") if tier_idx < 0 else accent)
	member.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	member.add_theme_constant_override("shadow_offset_y", 3)
	if ThemeManager.display_font:
		member.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(member)

	# UNRANKED is an absence, and an absence is the one state on this page that
	# has to be told what to do about it. The word alone left a new player looking
	# at a faded shield with no way to know whether it was a target or a failed
	# load — so it now names the exact series count that turns it on.
	if tier_idx < 0:
		col.add_child(_unranked_goal_line(best))

	var joined := _label(_joined_text(), 35)
	joined.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	joined.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	joined.add_theme_color_override("font_color", ThemeManager.color("text_faint"))
	col.add_child(joined)

	# No status tagline on the hero — identity is the name, the badge and the
	# rank; the status stays editable in the identity sheet for the share card.
	UI.make_scroll_tappable(card, func(): _edit_identity())
	return card

## The ghosted numeral behind the hero: the series this player has won, or the
## game's own two marks before they have won one.
##
## Deliberately a plain Label rather than a FitLabel: it is meant to overflow and
## be clipped by the card, which is what makes it read as a watermark under the
## content instead of a number in a box.
func _hero_watermark(tier_idx: int) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.clip_contents = true
	var won := int(GameStats.get_stat("games_won"))
	var lbl := Label.new()
	lbl.text = str(won) if won > 0 else "XO"
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# CLIPPED, and that is load-bearing rather than cosmetic. A Label reports the
	# full width of its text as its MINIMUM size, so an unclipped 300pt numeral
	# inside the hero pane pushes the pane itself past the 981pt width budget and
	# walks the whole card off the screen edge — which is exactly what
	# flow_number_overflow caught. clip_text drops that claim to one pixel and
	# lets the numeral bleed past the card instead of moving it.
	lbl.clip_text = true
	# ...and the type comes down as the number gets longer, so a five-figure count
	# still reads as itself rather than as the three digits that survived the crop.
	lbl.add_theme_font_size_override("font_size",
		int(clampf(880.0 / float(maxi(lbl.text.length(), 1)), 110.0, 300.0)))
	lbl.add_theme_color_override("font_color", Color(_tier_accent(tier_idx), 0.09))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ThemeManager.display_font_heavy:
		lbl.add_theme_font_override("font", ThemeManager.display_font_heavy)
	holder.add_child(lbl)
	return holder

## What the badge STANDS on: a contact shadow and a short mirrored reflection
## sinking into the card.
##
## The shield used to float in the middle of a pane with nothing under it, which
## is why it read as a sticker rather than as an object on the page. The
## reflection is the cheap half of the trick — the same texture, flipped, faint,
## and cut off by a fade before it can look like a second badge.
func _hero_pedestal(box: float, tier_idx: int, tint: Color) -> Control:
	const H := 92.0
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, H)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.clip_contents = true

	# The contact shadow: a radial squashed flat, so the badge lands on something
	# rather than hovering over it.
	var shadow := _soft_glow(1.0, Color(0, 0, 0, 1), 0.42)
	shadow.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	shadow.offset_left = -box * 0.40; shadow.offset_right = box * 0.40
	shadow.offset_top = -14.0; shadow.offset_bottom = 30.0
	holder.add_child(shadow)
	# A whisper of the badge's own light spilling onto the surface it sits on.
	var spill := _soft_glow(1.0, tint, 0.22)
	spill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	spill.offset_left = -box * 0.30; spill.offset_right = box * 0.30
	spill.offset_top = -8.0; spill.offset_bottom = 22.0
	holder.add_child(spill)

	var mirror := TextureRect.new()
	mirror.texture = load(String(TierBadge.tier(maxi(tier_idx, 0))["tex"])) as Texture2D
	mirror.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mirror.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mirror.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mirror.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	# Full badge height, hanging below the clip — only its top few dozen pixels
	# (the shield's foot) survive, which is exactly how far a reflection carries.
	mirror.offset_left = -box * 0.5; mirror.offset_right = box * 0.5
	mirror.offset_top = 0.0; mirror.offset_bottom = box
	# The mirroring AND the fade both happen in the shader. The first version laid
	# a gradient of the page's backdrop colour over the reflection to sink it,
	# which is fine over a solid page and a black slab over a GLASS one — and this
	# card is glass, so the pedestal read as a hole cut in the hero.
	mirror.material = _mirror_material(0.26 if tier_idx >= 0 else 0.14)
	holder.add_child(mirror)
	return holder

## The reflection's material: the badge art flipped, faded out downward, and
## dimmed to `strength`.
##
## Ascending smoothstep only — a descending edge renders black on D3D12
## (CLAUDE.md) — and the flip is done by sampling 1.0 - UV.y rather than with
## TextureRect.flip_v, so the shader and the sampler cannot disagree about which
## way up the art is.
const _MIRROR_CODE := "
shader_type canvas_item;
uniform float strength = 0.26;
void fragment() {
	vec4 tex = texture(TEXTURE, vec2(UV.x, 1.0 - UV.y));
	float fade = 1.0 - smoothstep(0.0, 0.40, UV.y);
	COLOR = vec4(tex.rgb, tex.a * fade * strength);
}
"

static var _mirror_shader: Shader

func _mirror_material(strength: float) -> ShaderMaterial:
	if _mirror_shader == null:
		_mirror_shader = Shader.new()
		_mirror_shader.code = _MIRROR_CODE
	var mat := ShaderMaterial.new()
	mat.shader = _mirror_shader
	mat.set_shader_parameter("strength", strength)
	return mat

## "0 / 3 series in Classic — win them for Bronze". The concrete series count
## that ends the unranked state, in whichever mode the player is actually
## closest in.
func _unranked_goal_line(best: Dictionary) -> Control:
	var mode_id := String(best.get("mode_id", ""))
	if mode_id.is_empty():
		mode_id = "classic"
	var mode := GameModes.get_mode(mode_id)
	var need := _series_for_tier(mode, 0)
	var have := int(GameStats.mode_record(mode_id).get("series_won", 0))
	var box := VBoxContainer.new()
	var accent: Color = TierBadge.tier(0)["accent"]
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))
	var line := _label("%s / %s series in %s  →  Bronze" % [
		_fmt_group(have), _fmt_group(need), mode.title], 33)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_color_override("font_color", accent)
	box.add_child(line)
	box.add_child(_progress_bar(clampf(float(have) / float(maxi(need, 1)), 0.0, 1.0),
		accent, accent.lerp(Color.WHITE, 0.35), 10.0))
	return box

## Godrays behind the emblem: soft beams fanning out from under the shield.
##
## ONE canvas item, drawn once, turning as a whole via a transform — the beams
## never change shape, so re-emitting them per frame would be paying a
## triangulation to animate a rotation the renderer can do for free.
##
## `draw_polygon` with per-vertex colours rather than a shader: the fade is
## linear from the hot inner edge to a transparent outer one, which vertex
## colours interpolate exactly, and a shader here would be a GLES3 compile on the
## frame the page is being built (CLAUDE.md, RULES 9.5).
class RayFan extends Control:
	var tint: Color = Color.WHITE
	var rays := 9

	func _init(p_tint: Color) -> void:
		tint = p_tint
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var box := minf(size.x, size.y)
		if box <= 8.0:
			return
		var c := size * 0.5
		var r0 := box * 0.16
		var r1 := box * 0.50
		var hot := Color(tint, 0.20)
		var gone := Color(tint, 0.0)
		for i in rays:
			var a := TAU * float(i) / float(rays)
			var w0 := TAU / float(rays) * 0.10
			var w1 := TAU / float(rays) * 0.32
			draw_polygon(PackedVector2Array([
				c + Vector2(cos(a - w0), sin(a - w0)) * r0,
				c + Vector2(cos(a - w1), sin(a - w1)) * r1,
				c + Vector2(cos(a + w1), sin(a + w1)) * r1,
				c + Vector2(cos(a + w0), sin(a + w0)) * r0,
			]), PackedColorArray([hot, gone, gone, hot]))

## The Play Games picture as a small medallion on the badge's shoulder.
##
## HIDDEN until a picture actually lands, and that is the whole design: a ring
## with nothing in it is worse than no ring, and PGS hands out a URL rather than a
## texture, so "is there a photo" is not answerable at build time. Off Android
## `icon_uri()` is empty and this node simply never shows itself, which is also
## why no headless test here ever touches the network.
##
## Masked to a circle on the CPU (BadgePortrait's own routine, reused rather than
## re-derived) — one pass over a ~90px bitmap, once, against a GLES3 shader that
## would compile synchronously on the render thread the first time it binds.
class PhotoMedallion extends Control:
	var uri := ""
	var rim: Color = Color.WHITE

	func _init(p_uri: String, p_rim: Color) -> void:
		uri = p_uri
		rim = p_rim
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func _ready() -> void:
		if not uri.begins_with("http"):
			return
		var req := HTTPRequest.new()
		add_child(req)
		req.request_completed.connect(_on_photo)
		if req.request(uri) != OK:
			req.queue_free()

	func _on_photo(result: int, code: int, _headers: PackedStringArray,
			body: PackedByteArray) -> void:
		if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
			return   # no photo is not an error state; the badge is already complete
		var img := Image.new()
		var err := img.load_png_from_buffer(body)
		if err != OK:
			err = img.load_jpg_from_buffer(body)
		if err != OK:
			err = img.load_webp_from_buffer(body)
		if err != OK or not is_inside_tree():
			return
		var edge := maxi(int(size.x), 8)
		img.resize(edge, edge, Image.INTERPOLATE_LANCZOS)
		BadgePortrait._mask_circle(img)
		_show(ImageTexture.create_from_image(img))

	func _show(tex: Texture2D) -> void:
		var plate := Panel.new()
		plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = ThemeManager.color("bg0")
		sb.set_corner_radius_all(int(size.x * 0.5) if size.x > 0.0 else 48)
		sb.set_border_width_all(3)
		sb.border_color = rim.lerp(Color.WHITE, 0.35)
		sb.anti_aliasing = true
		plate.add_theme_stylebox_override("panel", sb)
		add_child(plate)

		var rect := TextureRect.new()
		rect.texture = tex
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pad := size.x * 0.06
		rect.offset_left = pad; rect.offset_top = pad
		rect.offset_right = -pad; rect.offset_bottom = -pad
		add_child(rect)

		visible = true
		modulate.a = 0.0
		pivot_offset = size * 0.5
		scale = Vector2(0.7, 0.7)
		var tw := create_tween().set_parallel()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(self, "modulate:a", 1.0, DesignSystem.DUR_BASE)
		tw.tween_property(self, "scale", Vector2.ONE, DesignSystem.DUR_SLOW)

## The hero badge scales away and fades as the page scrolls under it. Scale and
## alpha only — the bob tween owns position:y.
##
## Also the page's ONE scroll listener: the header band, the sticky rank capsule
## and the reveal-on-scroll sections all ride this callback rather than each
## connecting to the scrollbar. The bar emits at pixel granularity during a touch
## drag, so four independent handlers would be four subtree writes per event.
func _on_hero_parallax(v: float) -> void:
	_on_scroll_atmosphere(v)
	if not is_instance_valid(_hero_inner):
		return
	var t := clampf(v / 520.0, 0.0, 1.0)
	# The scrollbar emits value_changed at pixel granularity during a touch drag.
	# Past the 520 px ramp (and for sub-pixel jitter) the write below is visually
	# a no-op — but it would still re-transform and re-composite the whole hero
	# subtree (ring + badge + particles) on every event, every frame.
	if absf(t - _hero_par_t) < 0.002:
		return
	_hero_par_t = t
	_hero_inner.scale = Vector2.ONE * (1.0 - 0.16 * t)
	_hero_inner.modulate.a = 1.0 - 0.45 * t

## Press-tilt, tap-pop and hold-to-inspect for the hero badge. The bob tween owns
## position:y, so the tilt only ever touches rotation/scale — competing tweens on
## the same property fight forever.
func _hero_badge_input(e: InputEvent, holder: Control, inner: Control, tier_idx: int,
		st: Dictionary) -> void:
	var accent := _tier_accent(tier_idx)
	var down_evt: bool = (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed) \
		or (e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (e as InputEventMouseButton).pressed)
	var up_evt: bool = (e is InputEventScreenTouch and not (e as InputEventScreenTouch).pressed) \
		or (e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and not (e as InputEventMouseButton).pressed)
	if e is InputEventScreenDrag:
		st["moved"] = float(st["moved"]) + (e as InputEventScreenDrag).relative.length()
	elif e is InputEventMouseMotion and bool(st["down"]):
		st["moved"] = float(st["moved"]) + (e as InputEventMouseMotion).relative.length()
	if down_evt:
		st["down"] = true
		st["moved"] = 0.0
		st["inspected"] = false
		var at: Vector2 = (e as InputEventMouse).position if e is InputEventMouse \
			else (e as InputEventScreenTouch).position
		var lean := clampf((at.x / maxf(holder.size.x, 1.0)) * 2.0 - 1.0, -1.0, 1.0)
		var tw := inner.create_tween().set_parallel()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(inner, "rotation", lean * 0.09, 0.16)
		tw.tween_property(inner, "scale", Vector2(0.94, 0.94), 0.16)
		_arm_hold(inner, tier_idx, st)
	elif up_evt and bool(st["down"]):
		st["down"] = false
		if bool(st["inspected"]):
			return   # the hold already fired; a release must not also pop
		if float(st["moved"]) < 24.0:
			holder.accept_event()   # a clean tap is the badge's own — not the card's
			_pop_hero_badge(inner, accent, String(TierBadge.metal(tier_idx)["burst"]))
		else:
			_settle_hero_badge(inner)

## How long a press has to hold before it becomes an inspect rather than a tap.
const HOLD_SEC := 0.55

## Arms the hold. TOKENED rather than cancelled: a SceneTreeTimer cannot be
## called off once created, so each press stamps its own number and a timer whose
## number has moved on simply does nothing when it fires. Without that, a fast
## tap-tap-tap opens the inspector on the release of the FIRST tap.
func _arm_hold(inner: Control, tier_idx: int, st: Dictionary) -> void:
	st["hold"] = int(st["hold"]) + 1
	var token := int(st["hold"])
	get_tree().create_timer(HOLD_SEC).timeout.connect(func():
		if int(st["hold"]) != token or not bool(st["down"]) or float(st["moved"]) >= 24.0:
			return
		if not is_instance_valid(inner):
			return
		st["inspected"] = true
		Haptics.light()
		_settle_hero_badge(inner)
		_inspect_badge(tier_idx))

## Hold the badge and it opens: the shield at full size, turning slowly, with
## what the rank is and what it took to get it.
##
## The page shows the emblem at 300pt behind a ring, a frame, an aura and an
## effect — everything the player has dressed it in, which is also everything
## between them and the ART they earned. This is the one place it is shown alone.
func _inspect_badge(tier_idx: int) -> void:
	var ranked := tier_idx >= 0
	var idx := maxi(tier_idx, 0)
	var t := TierBadge.tier(idx)
	var m := ModalOverlay.new()
	m.compact = true
	const BIG := 420.0
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(BIG, BIG)
	stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var metal := TierBadge.metal(idx)
	stage.add_child(_soft_glow(BIG, metal["aura"], 0.5))
	var view := TierBadge.make_view(BIG, idx, not ranked)
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.custom_minimum_size = Vector2.ZERO
	view.material = TierBadge.shine_material(3.0)
	stage.add_child(view)
	if not bool(SettingsManager.get_value("reduce_motion")):
		# A slow lean rather than a full spin: the shield art has a front, and
		# turning it all the way round shows the back of a picture that has none.
		stage.pivot_offset = Vector2(BIG, BIG) * 0.5
		stage.tree_entered.connect(func():
			var tw := stage.create_tween().set_loops()
			tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			tw.tween_property(stage, "rotation", 0.05, 3.2)
			tw.tween_property(stage, "rotation", -0.05, 3.2))
	var body := "Win a series to earn your first badge."
	if ranked:
		body = _tier_rule_text(idx)
	m.set_header("Mastery Rank", String(t["name"]) if ranked else "Unranked", body)
	m.add_content(stage)
	if ranked:
		m.add_action("Replay ceremony", PremiumButton.Variant.GLASS, func():
			m.close()
			SceneRouter.replay_rank_up(idx))
	m.add_action("Done", PremiumButton.Variant.PRIMARY, func(): m.close())
	m.open(self)

## The tap celebration: sfx + haptic + the RANK's own burst + a full-page star
## shower + an overshoot pop back upright.
func _pop_hero_badge(inner: Control, accent: Color, burst: String = "star") -> void:
	AudioManager.play_sfx("button_tap", 0.04)
	Haptics.light()
	TierBadge.sparkle_burst(inner, inner.size.x, accent, 12, burst)
	_star_shower(accent)
	var rt := inner.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	rt.tween_property(inner, "rotation", 0.0, 0.2)
	var tw := inner.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(inner, "scale", Vector2(1.15, 1.15), 0.12)
	tw.tween_property(inner, "scale", Vector2.ONE, 0.22)

## Spring back upright when the press turned into a scroll instead of a tap.
func _settle_hero_badge(inner: Control) -> void:
	var tw := inner.create_tween().set_parallel()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tw.tween_property(inner, "rotation", 0.0, 0.5)
	tw.tween_property(inner, "scale", Vector2.ONE, 0.4)

## The hall-of-fame glitter rain: ONE canvas item owns every falling star, and
## the whole shower is submitted as a SINGLE textured triangle array — one draw
## call, however many stars are in the air. A repeat tap tops up this same layer
## (hard-capped at MAX_STARS) instead of stacking a second shower of tweened
## nodes.
##
## --- Why it is one triangle array and not `draw_colored_polygon` -------------
## The first version drew each star as two `draw_colored_polygon` calls (the
## tinted outer star, then the bright inner one) behind a per-star
## `draw_set_transform`. That is three problems stacked, all paid EVERY FRAME:
##
##  1. `draw_colored_polygon` triangulates its polygon on the CPU on every call
##     (`RendererCanvasCull::canvas_item_add_polygon` runs
##     `Geometry2D::triangulate_polygon`). The star is a ten-vertex CONCAVE
##     polygon, so this was ~220 ear-clipping runs per frame for geometry that
##     never changes shape.
##  2. Each polygon is its own canvas command and the interleaved
##     `draw_set_transform` commands break 2D batching, so a full shower
##     submitted ~220 draw calls per frame. On Android the currency is draw
##     submissions, not triangles (RULES 3.8, 11.2).
##  3. The polygons are hard-edged, so 7–18 px stars crawled with aliasing —
##     which reads as "not smooth" even at a perfect frame rate.
##
## Now the star is baked ONCE into a soft-edged texture and every star is ONE
## indexed textured quad appended into a shared vertex array, submitted with a
## single `canvas_item_add_triangle_array`. No triangulation, no transform
## commands, one draw call, antialiased edges.
##
## --- Why ONE indexed quad, and why that is what pays for the burst size ------
## The batched form still rebuilt every vertex from GDScript every frame, so the
## cost is `writes per star x stars` and nothing else - which is the entire
## budget once a tap fills the sky. Three changes cut it to a third with no
## visible difference, and that is what the 4x burst is bought with:
##
##  1. INDEXED. Six vertices per quad (two standalone triangles) became four
##     plus a six-entry index list, written once per slot ever, not per frame.
##  2. ONE QUAD. The bright inner star used to be a SECOND quad drawn over the
##     first. It is baked into the texture now as a hotter core alpha, so the
##     highlight costs nothing per frame.
##  3. NO RESIZE. The arrays only grow, to the high-water star count, and slots
##     past the live stars collapse to degenerate triangles the GPU discards.
##     The previous form resized and refilled every UV on each frame a star
##     landed, which is most frames of a shower.
##
## Deliberately NOT a MultiMesh, which would also collapse the draws: a MultiMesh
## canvas item is a different shader specialization, and on the Compatibility
## renderer GLES3 compiles at first bind, synchronously, on the render thread
## (RULES 9.5) — that is a hitch on the first badge tap, which is precisely the
## frame this whole change exists to protect. Textured quads reuse the canvas
## shader every TextureRect in the app has already compiled.
class StarRain extends Control:
	## How many stars may be IN THE AIR at once - the whole per-frame cost of
	## the shower, since the draw is linear in this and nothing else. Measured
	## under the Compatibility renderer the phone ships: 59us fixed plus 0.57us
	## a star, so this ceiling costs ~170us a frame - LESS than the 110-star
	## ceiling it replaces cost before the draw was rebuilt (~190us), while
	## holding nearly twice the sky. Stars past it are not dropped, they wait
	## in `_pending` and fall as the ones ahead land.
	const MAX_STARS := 200
	## Baked star edge in px. The stars draw at 7–18 px, so this is comfortably
	## above their on-screen size and never has to magnify.
	const TEX := 48
	## Inset so the five tips keep their soft edge inside the bitmap instead of
	## being clipped flat by it; QUAD_SCALE grows the quad back by exactly the
	## same factor, so a star's tips still land at its nominal radius on screen.
	const TEX_PAD := 1.5
	const QUAD_SCALE := (float(TEX) * 0.5) / (float(TEX) * 0.5 - TEX_PAD)
	## The bright inner star, as a fraction of the outer radius. Same value the
	## two-polygon version used, so the star reads the way it always has.
	const CORE := 0.45
	## The two-tone bake. The body sits under full opacity so the core stands
	## out of it as a highlight - over the dark page that difference is what the
	## second, whiter quad used to draw. TINT_LIFT returns the hue that quad
	## also carried, mixed into each star once at spawn.
	const BODY_A := 0.86
	const TINT_LIFT := 0.3

	# Baked once for the app's lifetime — a white mask with no per-theme state.
	# The texture is held in a static so the RID handed to the server always has
	# a live resource behind it (RULES 4.2).
	static var _star_tex: ImageTexture
	static var _star_rid: RID

	var view := Vector2.ZERO   # the page size, stamped by the spawner

	# Star state as parallel packed arrays rather than an Array of Dictionaries.
	# This is per-frame numeric data touched twice per star per frame (advance,
	# then emit), and the dictionary form paid a hashed String lookup plus a
	# Variant unbox for every single field access (RULES 4.1).
	var _n := 0
	# Stars a tap asked for that the sky had no room for. They are spent a few
	# at a time as slots free up, which is what lets one tap deliver a burst
	# four times the ceiling without ever drawing more than the ceiling.
	var _pending := 0
	var _pending_pool: Array = []
	var _x := PackedFloat32Array()
	var _y := PackedFloat32Array()
	var _r := PackedFloat32Array()
	var _rot := PackedFloat32Array()
	var _spin := PackedFloat32Array()
	var _speed := PackedFloat32Array()
	var _amp := PackedFloat32Array()
	var _sway_w := PackedFloat32Array()
	var _twk_w := PackedFloat32Array()
	var _ph := PackedFloat32Array()
	var _t := PackedFloat32Array()
	var _tint := PackedColorArray()

	# The submitted geometry, kept and reused across frames instead of rebuilt.
	# These GROW to the high-water star count and never shrink. `_cap` counts the
	# vertex slots whose FIXED data (UV corners, index pattern) has been written;
	# `_written` counts the star slots holding live geometry from the last frame.
	var _pts := PackedVector2Array()
	var _cols := PackedColorArray()
	var _uvs := PackedVector2Array()
	var _idx := PackedInt32Array()
	var _cap := 0
	var _written := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		bake()

	## A unit five-point star, outer radius `r`, first point straight up.
	static func _star_pts(r: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 10:
			var ang := -PI * 0.5 + TAU * float(i) / 10.0
			var rad := r if i % 2 == 0 else r * 0.42
			pts.append(Vector2(cos(ang), sin(ang)) * rad)
		return pts

	## Bakes the shared star bitmap. Public and idempotent so the Profile page can
	## call it while it is BUILDING: the bake walks TEX² pixels against ten edges,
	## which is a one-off some-milliseconds cost, and the one frame it must never
	## land on is the badge tap.
	static func bake() -> void:
		if _star_tex != null:
			return
		var rad := float(TEX) * 0.5 - TEX_PAD
		var poly := _star_pts(rad)
		var core := _star_pts(rad * CORE)
		var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
		var c := Vector2(TEX, TEX) * 0.5
		for y in TEX:
			for x in TEX:
				var p := Vector2(float(x) + 0.5, float(y) + 0.5) - c
				# ~1 px of soft edge on both shapes: the whole reason the baked
				# form looks better than the polygon it replaces at these sizes.
				var body := clampf(0.5 - _poly_dist(p, poly), 0.0, 1.0) * BODY_A
				var hot := clampf(0.5 - _poly_dist(p, core), 0.0, 1.0) * (1.0 - BODY_A)
				img.set_pixelv(Vector2i(x, y), Color(1, 1, 1, body + hot))
		_star_tex = ImageTexture.create_from_image(img)
		_star_rid = _star_tex.get_rid()

	## Signed distance from `p` to a polygon: distance to the nearest edge, made
	## negative inside (even-odd crossing test).
	static func _poly_dist(p: Vector2, poly: PackedVector2Array) -> float:
		var best := INF
		var inside := false
		var count := poly.size()
		var j := count - 1
		for i in count:
			var a := poly[i]
			var b := poly[j]
			var e := b - a
			var w := p - a
			var t := clampf(w.dot(e) / maxf(e.length_squared(), 0.000001), 0.0, 1.0)
			best = minf(best, (w - e * t).length())
			if ((a.y > p.y) != (b.y > p.y)) \
					and (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x):
				inside = not inside
			j = i
		return -best if inside else best

	## Adds one tap's worth of small stars, staggered high above the top edge so
	## the rain keeps arriving in a long soft front. Whatever the sky has no
	## room for is HELD rather than dropped, so the tap still spends its whole
	## burst - it just keeps raining for longer. The backlog is itself capped at
	## a sky, so spamming the badge converges on a full sky that ends, not on
	## a shower that outlives the visit. (An inner class cannot see the outer
	## script's STAR_BURST by name, which is why the bound is in its own terms.)
	func add_burst(pool: Array, n: int) -> void:
		var room := MAX_STARS - _n
		_pending_pool = pool
		if n > room:
			_pending = mini(_pending + n - maxi(room, 0), MAX_STARS)
		_spawn(pool, mini(n, room))

	## Spends the backlog into whatever the sky has freed this frame. Called
	## once a frame from `_process`, after the landed stars have been reaped.
	func _drain() -> void:
		if _pending <= 0:
			return
		var add := mini(_pending, MAX_STARS - _n)
		if add <= 0:
			return
		_pending -= add
		_spawn(_pending_pool, add)

	func _spawn(pool: Array, add: int) -> void:
		if add <= 0 or pool.is_empty():
			return
		var h := view.y
		_grow(_n + add)
		for i in add:
			var k := _n + i
			var sz := randf_range(7.0, 18.0)
			_x[k] = randf_range(0.0, maxf(view.x - sz, 1.0))
			_y[k] = -sz - randf_range(0.0, h * 0.7)
			_r[k] = sz * 0.5
			_rot[k] = randf_range(-PI, PI)
			_spin[k] = randf_range(-0.6, 0.6)
			_speed[k] = h * randf_range(0.17, 0.30)   # the slow, steady drift
			_amp[k] = randf_range(16.0, 44.0)
			_sway_w[k] = TAU / randf_range(1.8, 3.4)
			_twk_w[k] = TAU / randf_range(0.4, 0.9)
			_ph[k] = randf() * TAU
			_t[k] = 0.0
			# Lifted here and never per frame: see TINT_LIFT.
			var base: Color = pool[i % pool.size()]
			_tint[k] = base.lerp(Color.WHITE, TINT_LIFT)
		_n += add
		_reserve(_n)

	## Resized one by one on purpose: Packed*Arrays are VALUE types in GDScript,
	## so a `for arr in [...]` loop would resize eleven throwaway copies and leave
	## every member array untouched.
	func _grow(size: int) -> void:
		if _x.size() >= size:
			return
		_x.resize(size)
		_y.resize(size)
		_r.resize(size)
		_rot.resize(size)
		_spin.resize(size)
		_speed.resize(size)
		_amp.resize(size)
		_sway_w.resize(size)
		_twk_w.resize(size)
		_ph.resize(size)
		_t.resize(size)
		_tint.resize(size)

	func _process(delta: float) -> void:
		var floor_y := view.y + 20.0
		var i := 0
		while i < _n:
			_y[i] += _speed[i] * delta
			_rot[i] += _spin[i] * delta
			_t[i] += delta
			if _y[i] > floor_y:
				# Swap-remove: the shower has no draw order to preserve, so
				# moving the last star into the hole beats shifting the tail.
				_n -= 1
				_swap_in(i, _n)
				continue
			i += 1
		_drain()
		if _n == 0 and _pending <= 0:
			queue_free()
		else:
			queue_redraw()

	func _swap_in(dst: int, src: int) -> void:
		if dst == src:
			return
		_x[dst] = _x[src]
		_y[dst] = _y[src]
		_r[dst] = _r[src]
		_rot[dst] = _rot[src]
		_spin[dst] = _spin[src]
		_speed[dst] = _speed[src]
		_amp[dst] = _amp[src]
		_sway_w[dst] = _sway_w[src]
		_twk_w[dst] = _twk_w[src]
		_ph[dst] = _ph[src]
		_t[dst] = _t[src]
		_tint[dst] = _tint[src]

	func _draw() -> void:
		if _n == 0 or not _star_rid.is_valid():
			return
		_reserve(_n)
		var h := view.y
		# Hoisted: the fade divides by the same page band for every star.
		var fade_k := 1.0 / maxf(h * 0.25, 1.0)
		var w := 0
		for i in _n:
			var t := _t[i]
			var ph := _ph[i]
			# Sway and twinkle are DERIVED from the star clock rather than stored
			# as animated state - nothing to tween, nothing to drift.
			var cy := _y[i]
			var cx := _x[i] + sin(t * _sway_w[i] + ph) * _amp[i]
			var twinkle := 0.65 + 0.35 * sin(t * _twk_w[i] + ph * 2.0)
			var col := _tint[i]
			col.a = twinkle * clampf((h - cy) * fade_k, 0.0, 1.0)
			var rad := _r[i] * QUAD_SCALE
			var rot := _rot[i]
			var ux := cos(rot) * rad
			var uy := sin(rot) * rad
			# The quad written straight into the arrays: no helper call, no
			# intermediate Vector2 for the rotated half-extents.
			_pts[w] = Vector2(cx - ux + uy, cy - uy - ux)
			_pts[w + 1] = Vector2(cx + ux + uy, cy + uy - ux)
			_pts[w + 2] = Vector2(cx + ux - uy, cy + uy + ux)
			_pts[w + 3] = Vector2(cx - ux - uy, cy - uy + ux)
			_cols[w] = col
			_cols[w + 1] = col
			_cols[w + 2] = col
			_cols[w + 3] = col
			w += 4
		# Slots vacated by stars that have landed, collapsed to a point so their
		# two triangles are zero-area and the GPU throws them out. Cheaper than
		# resizing every array (and refilling every UV) on every landing frame.
		while _written > _n:
			_written -= 1
			var v := _written * 4
			_pts[v] = Vector2.ZERO
			_pts[v + 1] = Vector2.ZERO
			_pts[v + 2] = Vector2.ZERO
			_pts[v + 3] = Vector2.ZERO
		_written = _n
		RenderingServer.canvas_item_add_triangle_array(
			get_canvas_item(), _idx, _pts, _cols, _uvs,
			PackedInt32Array(), PackedFloat32Array(), _star_rid)

	## Grows the submitted arrays to hold `stars` quads, writing the fixed
	## per-slot data - the UV corners and the index pattern - for the NEW slots
	## only. Never shrinks: the arrays settle at the tap that filled the most
	## sky and every later frame reuses them as they are.
	func _reserve(stars: int) -> void:
		var verts := stars * 4
		if verts <= _cap:
			return
		_pts.resize(verts)
		_cols.resize(verts)
		_uvs.resize(verts)
		_idx.resize(stars * 6)
		var slot := _cap / 4
		while slot < stars:
			var v := slot * 4
			_uvs[v] = Vector2(0, 0)
			_uvs[v + 1] = Vector2(1, 0)
			_uvs[v + 2] = Vector2(1, 1)
			_uvs[v + 3] = Vector2(0, 1)
			var q := slot * 6
			_idx[q] = v
			_idx[q + 1] = v + 1
			_idx[q + 2] = v + 2
			_idx[q + 3] = v
			_idx[q + 4] = v + 2
			_idx[q + 5] = v + 3
			slot += 1
		_cap = verts

## The badge tap writ large: small glittery stars raining slowly down the WHOLE
## profile page in white / gold / the badge's own accent. The layer sits on the
## screen itself (over the scroll, tree order — never negative z), swallows no
## input, and frees itself once the last star lands. Only ever reached from the
## tap toy.
func _star_shower(accent: Color) -> void:
	var pool: Array = [Color.WHITE, ThemeManager.color("gold"), accent,
		accent.lerp(Color.WHITE, 0.5)]
	if not is_instance_valid(_rain):
		_rain = StarRain.new()
		_rain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_rain)
	_rain.view = size
	_rain.add_burst(pool, STAR_BURST)

## A rounded pill wearing the current tier's accent — a soft tint fill, a brighter
## rim, and the tier name in the accent itself. Reads as a rank badge.
func _tier_chip(text: String, accent: Color) -> Control:
	var pill := PanelContainer.new()
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.r, accent.g, accent.b, 0.16)
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_PILL))
	sb.set_border_width_all(1)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	sb.content_margin_left = DesignSystem.SPACE_MD
	sb.content_margin_right = DesignSystem.SPACE_MD
	sb.content_margin_top = DesignSystem.SPACE_XS
	sb.content_margin_bottom = DesignSystem.SPACE_XS
	pill.add_theme_stylebox_override("panel", sb)
	var lbl := _label(text.to_upper(), 34)
	lbl.add_theme_color_override("font_color", accent)
	if ThemeManager.display_font:
		lbl.add_theme_font_override("font", ThemeManager.display_font)
	pill.add_child(lbl)
	return pill

## The series a mode's ladder asks for at tier `i`: the tier's share of the
## mode's yardstick, rounded UP so a tier is never announced before the last
## series that earns it. GameStats.best_mastery_ratio divides by the same
## yardstick, so what this prints is exactly what the ladder measures.
func _series_for_tier(mode: GameModes.Mode, i: int) -> int:
	return int(ceil(TierBadge.tier_ratio(i) * float(mode.mastery_yardstick())))

## The rule behind tier `i`, in the player's terms, with Classic as the worked
## example: "Win a quarter of a mode's ladder. In Classic, that's 3 series."
func _tier_rule_text(i: int) -> String:
	var classic := GameModes.get_mode("classic")
	var need := _series_for_tier(classic, i)
	var share := "%d%% of" % int(round(TierBadge.tier_ratio(i) * 100.0))
	if TierBadge.tier_ratio(i) == 1.0:
		share = "all of"
	elif TierBadge.tier_ratio(i) > 1.0:
		share = "%s×" % String.num(TierBadge.tier_ratio(i), 0)
	return "Win %s a mode's ladder of series. In Classic, that's %d series." % [share, need]

## The mastery rail beneath the badge: the current tier badge → the "X / Y
## series in <mode>" numbers → the next tier badge. The ring around the badge
## already shows the progress visually, so this strip carries the concrete
## numbers instead of a second bar. The ladder is difficulty-normalized (see
## TierBadge); the absolute numbers come from whichever mode is carrying the
## player's best ratio.
func _tier_progress(best: Dictionary, tier_idx: int, _accent: Color) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))
	var mode_id: String = best["mode_id"]

	# Top tier reached — nothing left to chase; celebrate instead.
	if tier_idx + 1 >= TierBadge.count():
		var done := _label("Infinity. The highest tier there is.", 34)
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		done.add_theme_color_override("font_color", ThemeManager.color("gold"))
		box.add_child(done)
		return box

	# Real series counts from the mode carrying the rank, against the series the
	# NEXT tier asks of that mode's own yardstick — the same division
	# GameStats.best_mastery_ratio makes, so the numbers and the ring agree.
	var mode := GameModes.get_mode(mode_id)
	var have := int(GameStats.mode_record(mode_id).get("series_won", 0))
	var need := _series_for_tier(mode, tier_idx + 1)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))

	# Left cap — the current badge (a spacer while still unranked).
	const CAP := 96.0
	if tier_idx >= 0:
		var cur := TierBadge.make_view(CAP, tier_idx, false)
		cur.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cur)
	else:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(CAP, CAP)
		row.add_child(gap)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_theme_constant_override("separation", 2)
	var big := _label("%s / %s" % [_fmt_group(have), _fmt_group(need)], 50)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	big.add_theme_color_override("font_color", ThemeManager.color("text"))
	if ThemeManager.display_font:
		big.add_theme_font_override("font", ThemeManager.display_font)
	mid.add_child(big)
	var cap := _label("series in %s → %s" % [
		mode.title, String(TierBadge.tier(tier_idx + 1)["name"])], 32)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	mid.add_child(cap)
	row.add_child(mid)

	# Right cap — the next badge, dimmed until earned.
	var nxt := TierBadge.make_view(CAP, tier_idx + 1, true)
	nxt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(nxt)
	box.add_child(row)
	return box

# --- Rank ---------------------------------------------------------------------
## Everything about the rank in one place: the mastery rail (current badge → the
## concrete series numbers → the next badge), the nearest goal actually within
## reach, and the explainer for how the ladder is scored.
func _rank_card() -> Control:
	var best := GameStats.best_mastery_ratio()
	var ratio: float = best["ratio"]
	var tier_idx: int = TierBadge.current_index(ratio)
	var accent := _tier_accent(tier_idx)

	var card := _card(2)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_LG))
	card.add_child(col)
	col.add_child(_tier_progress(best, tier_idx, accent))

	var next := _next_milestone()
	if not next.is_empty():
		col.add_child(_hrule())
		col.add_child(_milestone_row(next))

	var info := _label("ⓘ  How ranks are earned", 33)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_color_override("font_color", ThemeManager.color("accent"))
	UI.make_scroll_tappable(info, func(): _rank_info())
	col.add_child(info)
	return card

## The nearest goal still open, and how close it is. Achievements persist only
## unlocked/locked, so the progress is derived from the counters that unlock them:
## a mode's ladder of series wins, or a day streak.
##
## Candidacy is decided by the GOAL, not by the achievement flag — a mode whose
## ladder is unfinished is still something to chase even if an older save has its
## achievement ticked, and reading GameModes directly means there's no second copy
## of the mode catalog here to drift. Only modes already WON ONCE qualify:
## dangling "0 / 10 in a mode you've never opened" is noise, not a milestone.
func _next_milestone() -> Dictionary:
	var cands: Array = []
	for mode in GameModes.all():
		var rec := GameStats.mode_record(mode.id)
		var yard: int = mode.mastery_yardstick()
		if yard <= 0:
			continue
		var have := int(rec.get("series_won", 0))
		if have <= 0 or have >= yard:
			continue
		# The achievement's own name when this mode has one, so the goal reads the
		# same here as it does in the Trophy Case.
		var ach_id := String(Achievements.MODE_MASTERY_ACHIEVEMENT.get(mode.id, ""))
		var title := "Master %s" % mode.title
		if not ach_id.is_empty():
			title = String(Achievements.definition(ach_id).get("title", title))
		var unit := "series"
		cands.append({
			"title": title,
			"detail": "%s / %s %s in %s" % [
				_fmt_group(have), _fmt_group(yard), unit, mode.title],
			"ratio": clampf(float(have) / float(yard), 0.0, 1.0),
		})

	var streak := int(GameStats.get_stat("current_streak_days"))
	for pair in [["streak_7", 7], ["streak_30", 30]]:
		var ach_id := String(pair[0])
		var need := int(pair[1])
		if Achievements.is_unlocked(ach_id) or streak >= need:
			continue
		cands.append({
			"title": String(Achievements.definition(ach_id).get("title", "")),
			"detail": "%d / %d day streak" % [streak, need],
			"ratio": clampf(float(streak) / float(need), 0.0, 1.0),
		})

	var best: Dictionary = {}
	for c in cands:
		var cand: Dictionary = c
		if best.is_empty() or float(cand["ratio"]) > float(best["ratio"]):
			best = cand
	return best

## "NEXT MILESTONE — Classic Master · 4 / 10 series in Classic" over a bar.
## Gives the page a forward pull; every other block on it looks backwards.
func _milestone_row(m: Dictionary) -> Control:
	var accent: Color = ThemeManager.color("accent")
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))

	var head := HBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ey := _label("NEXT MILESTONE", 30)
	ey.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ey.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	head.add_child(ey)
	var pct := _label("%d%%" % int(round(float(m["ratio"]) * 100.0)), 30)
	pct.add_theme_color_override("font_color", accent)
	head.add_child(pct)
	box.add_child(head)

	var t := _label(String(m["title"]), 36)
	t.add_theme_color_override("font_color", ThemeManager.color("text"))
	if ThemeManager.display_font:
		t.add_theme_font_override("font", ThemeManager.display_font)
	box.add_child(t)

	box.add_child(_progress_bar(float(m["ratio"]), accent, accent.lerp(Color.WHITE, 0.35), 12.0))

	var d := _label(String(m["detail"]), 32)
	d.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	box.add_child(d)
	return box

# --- Share card ----------------------------------------------------------------
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

## The card itself: identity on a deep theme gradient — badge, name, rank and
## the headline score, signed with the game's name.
func _share_card_content(box: Vector2) -> Control:
	var p := _profile()
	var ratio: float = GameStats.best_mastery_ratio()["ratio"]
	var tier_idx: int = TierBadge.current_index(ratio)
	var accent := _tier_accent(tier_idx)
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
	var chip := _tier_chip(tier_name, accent)
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

# --- Account / sign-in --------------------------------------------------------
## A prominent Play Games sign-in entry (or the signed-in gamer tag). Reachable
## from Home → profile badge, so signing in isn't buried behind the premium flow.
## What to call the signed-in player: the PGS gamer tag. It arrives only once
## profile_changed fires, so fall back to a generic name while it's empty.
func _account_label() -> String:
	var tag := AccountManager.display_name()
	return tag if not tag.is_empty() else "Play Games account"

func _account_card() -> Control:
	var signed_in := AccountManager.is_signed_in()
	# Imported Play Games details ride along when PGS supplies them (level 0 =
	# the payload omitted level info — hide rather than show a fake "Level 0").
	var sub_text := "Play with your Google Play Games profile."
	if signed_in:
		sub_text = _account_label()
		if AccountManager.player_level() > 0:
			sub_text += "  ·  Level %d" % AccountManager.player_level()
	# Signed-in is terminal here: PGS has no sign-out API (players switch accounts
	# in the OS-level Play Games settings), so the card is informational once
	# signed in and tappable only while signed out.
	var tap := Callable()
	if not signed_in:
		tap = func(): AccountManager.sign_in()
	return _nav_row("Signed in" if signed_in else "Sign in with Play Games",
		sub_text, "text", tap)

## The shared "title / subtitle / chevron" row used by every navigational card on
## this page — account, statistics, delete. One shape, so they read as one family
## of destinations instead of three differently-weighted banners.
func _nav_row(title_text: String, sub_text: String, title_key: String, on_tap: Callable) -> Control:
	var card := _card(2)
	card.custom_minimum_size = Vector2(0, 150)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(row)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 4)
	var title := _label(title_text, 40)
	title.add_theme_color_override("font_color", ThemeManager.color(title_key))
	if ThemeManager.display_font:
		title.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(title)
	var sub := _label(sub_text, 34)
	sub.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	row.add_child(col)

	if on_tap.is_valid():
		var chev := _chevron()
		chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chev)
		UI.make_scroll_tappable(card, on_tap)
	return card

## The foot of the page: who you're playing as, and the way to erase everything.
func _account_block(sign_in_promoted: bool) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	# Not repeated when it's already sitting under the hero as a call to action.
	if AccountManager.is_configured() and not sign_in_promoted:
		box.add_child(_account_card())
	box.add_child(_delete_card())
	return box

func _toast(title_text: String, msg: String) -> void:
	var m := ModalOverlay.new()
	m.compact = true
	m.set_header("Profile", title_text, msg)
	m.add_action("Done", PremiumButton.Variant.PRIMARY, func(): m.close())
	m.open(self)

# --- Account & data deletion ----------------------------------------------------
## Google Play requires an in-app account-deletion path. The honest split under
## the Play-only stack: local data is erased here; the Play Games profile is
## Google-owned and is deleted in the OS-level Play Games settings; a premium
## purchase belongs to the Google Play account and is never deleted (restore
## must keep working after a wipe).
## Rendered in normal text, not danger red: compliance asks for a reachable path,
## not a red banner shouting over the rest of the page. The confirm modal — where
## the choice is actually made — keeps the full danger treatment.
func _delete_card() -> Control:
	return _nav_row("Delete account & data",
		"Erase all game data from this device.", "text_dim",
		func(): _confirm_delete())

func _confirm_delete() -> void:
	var m := ModalOverlay.new()
	m.set_header("Profile", "Delete account & data?",
		"This erases every stat, achievement, best score, setting and game in progress on this device. It can't be undone.\n\nYour Play Games profile (gamer tag, leaderboard scores) belongs to your Google account — remove this game's data in the Play Games app: Settings → Delete Play Games account & data.\n\nA premium purchase stays with your Google Play account and can be restored anytime.")
	m.add_action("Delete everything", PremiumButton.Variant.DANGER, func(): _delete_everything())
	m.add_action("Cancel", PremiumButton.Variant.GHOST, func(): m.close())
	m.open(self)

## Wipe, then quit. SaveManager latches a wiped flag, so nothing can re-persist
## a section during quit teardown (this screen's own rebuild writes "joined"
## back on read). Premium re-grants automatically from Play ownership on the
## next billing connect — deleting data must never delete a purchase.
func _delete_everything() -> void:
	SaveManager.wipe()
	get_tree().quit()

# --- Highlights ---------------------------------------------------------------
## Three numbers, not nine: the featured Best Series over a PAIR of cards — the
## best win streak, and Win Rate as a donut. Everything else that used to be
## crammed into two more three-across strips here (games, wins, average, moves,
## play time, longest session) is what the Statistics screen exists for, and
## printing it twice is what made this page feel packed.
func _highlights() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	box.add_child(_featured_score_card())

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	# Two cards over the old three, so each gets half the row instead of a third.
	row.add_child(_streak_stat_card(int(GameStats.get_stat("best_win_streak"))))
	row.add_child(_win_rate_card(int(round(GameStats.win_rate() * 100.0))))
	box.add_child(row)
	return box

## The hero stat: a wide card with a large trophy icon and the big Best Series
## number (count-up).
func _featured_score_card() -> Control:
	var card := _card(2)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 200)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_LG))

	var icon := _tex_icon("best_score", 140.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 2)
	var eyebrow := _label("BEST SERIES", 34)
	eyebrow.add_theme_color_override("font_color", ThemeManager.color("accent"))
	left.add_child(eyebrow)
	var num := _count_label(int(GameStats.get_stat("best_score")), _fmt_comma, 90)
	# Expanding, so the hero number takes the column the trophy leaves and fits
	# itself into it. At 90pt a seven-figure score is half the page wide, and
	# claiming that outright is what walked the card off the screen edge.
	num.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(num)
	# The series count rides along in this line rather than claiming a whole card
	# of its own — it's context for the best series, not a headline.
	var games := int(GameStats.get_stat("games_played"))
	var sub := _label("Your best series score" if games <= 0
		else "Your best across %s series" % _fmt_comma(games), 33)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	left.add_child(sub)
	row.add_child(left)
	card.add_child(row)
	return card

## Win Rate as a radial donut with the percentage in the centre.
func _win_rate_card(pct: int) -> Control:
	var card := _card(2)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 248)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))

	const D := 132.0
	var donut := Control.new()
	donut.custom_minimum_size = Vector2(D, D)
	donut.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var accent: Color = ThemeManager.color("accent")
	var ring := ProgressRing.new()
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.thickness = 14.0
	ring.track_color = ThemeManager.color("stroke")
	ring.color_a = accent
	ring.color_b = accent.lerp(Color.WHITE, 0.4)
	var target := clampf(float(pct) / 100.0, 0.0, 1.0)
	ring.value = 0.0
	ring.tree_entered.connect(func():
		var tw := ring.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(ring, "value", target, DesignSystem.DUR_SLOW).set_delay(0.2))
	donut.add_child(ring)
	var pl := _count_label(pct, _fmt_pct, 44)
	pl.set_anchors_preset(Control.PRESET_FULL_RECT)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	donut.add_child(pl)
	box.add_child(donut)
	box.add_child(_stat_caption("Win Rate"))
	card.add_child(box)
	return card

## The best run of series wins, as a big counting number under the trophy the
## Statistics grid uses for the same figure.
func _streak_stat_card(streak: int) -> Control:
	var card := _card(2)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 248)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))
	var icon := _tex_icon("best_score", 96.0)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var num := _count_label(streak, _fmt_comma, 56)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(num)
	box.add_child(_stat_caption("Win Streak"))
	card.add_child(box)
	return card

func _stat_caption(text: String) -> Label:
	var c := _label(text.to_upper(), 33)
	c.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return c

## A mode's own mark at `box` pt: its IconLibrary token in its native colours,
## its PNG tinted to the accent, its catalog glyph otherwise — the same three-way
## fallback the mode picker uses, so the two never disagree about what a board
## looks like. Dimmed when `ghost`, for a mode not yet started.
func _mode_chip(mode: GameModes.Mode, box: float, ghost: bool = false) -> Control:
	var holder: Control
	if not mode.icon_path.is_empty() and UI.icon_tex(mode.icon_path) != null:
		var tint := "" if IconLibrary.has_icon(mode.icon_path) else "accent"
		holder = UI.icon_rect(mode.icon_path, box, tint)
	else:
		var glyph := _label(mode.icon, int(box * 0.6))
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_color_override("font_color", ThemeManager.color("accent"))
		holder = glyph
	holder.custom_minimum_size = Vector2(box, box)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ghost:
		holder.modulate.a = 0.45   # a ghost of the board, inviting play

	# A gentle "spawn" pop, like a mark landing on the board.
	holder.pivot_offset = Vector2(box, box) * 0.5
	holder.scale = Vector2(0.7, 0.7)
	holder.tree_entered.connect(func():
		var tw := holder.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(holder, "scale", Vector2.ONE, DesignSystem.DUR_BASE).set_delay(0.18))
	return holder

# --- Streak -------------------------------------------------------------------
## The last fortnight as a row of dots — lit for a day played, hollow for a day
## missed. "Day Streak: 1" as a bare number said nothing; the same fact drawn as
## a calendar shows the shape of the habit and leaves an obvious gap to close.
##
## GameStats persists only `current_streak_days` + `last_played_unix`, and a
## streak is by definition consecutive, so the lit run is derivable exactly:
## it ends on the last-played day and runs back `current_streak_days` days.
const _STREAK_DAYS := 14
const _WEEKDAY_INITIALS := ["S", "M", "T", "W", "T", "F", "S"]

func _streak_card() -> Control:
	var card := _card(2)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	card.add_child(col)

	var streak := int(GameStats.get_stat("current_streak_days"))
	var best := int(GameStats.get_stat("max_streak_days"))
	var accent: Color = ThemeManager.color("accent")

	var head := HBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))
	var flame := _tex_icon("day_streak", 56.0)
	flame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# A cold streak shows a cold flame. The icon burned at full strength above a
	# row of empty days and a "0 days" count, which reads as a lit thing that has
	# simply failed to count anything.
	if streak <= 0:
		flame.modulate.a = 0.45
	head.add_child(flame)
	var big := _label("%d day%s" % [streak, "" if streak == 1 else "s"], 52)
	big.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big.add_theme_color_override("font_color", ThemeManager.color("text"))
	if ThemeManager.display_font:
		big.add_theme_font_override("font", ThemeManager.display_font)
	head.add_child(big)
	var best_lbl := _label("BEST %d" % best, 30)
	best_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	best_lbl.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	head.add_child(best_lbl)
	col.add_child(head)

	col.add_child(_streak_strip(streak, accent))

	var cap_text := "Play any mode today to keep the streak."
	if int(GameStats.get_stat("games_played")) <= 0:
		cap_text = "Play a game to start your streak."
	elif streak >= 2:
		cap_text = "%d days in a row. Keep it going." % streak
	var cap := _label(cap_text, 32)
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	col.add_child(cap)
	# With no streak the caption is an INSTRUCTION, so it becomes the way to
	# follow it. A card telling the player to go and play, on a page with no way
	# to, is the shape of an empty state nobody acts on.
	if streak <= 0:
		var go := _label("Play a mode  ›", 33)
		go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		go.add_theme_color_override("font_color", ThemeManager.color("accent"))
		UI.make_scroll_tappable(go, func():
			SceneRouter.goto(SceneRouter.Route["HOME"]))
		col.add_child(go)
	return card

## The dot row itself, oldest → today, with a weekday initial under each.
func _streak_strip(streak: int, accent: Color) -> Control:
	# Unix day index. Day 0 (1 Jan 1970) was a Thursday, so +4 lands weekday 0 on
	# Sunday — matching _WEEKDAY_INITIALS.
	@warning_ignore("integer_division")
	var today := int(Time.get_unix_time_from_system()) / 86400
	@warning_ignore("integer_division")
	var last_played := int(GameStats.get_stat("last_played_unix")) / 86400

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))
	var lit_n := 0
	for i in range(_STREAK_DAYS - 1, -1, -1):
		var day := today - i
		var lit := streak > 0 and day <= last_played and day > last_played - streak
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))

		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(0, 44)
		dot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(accent.r, accent.g, accent.b, 0.92) if lit else ThemeManager.color("glass")
		sb.set_corner_radius_all(12)
		sb.set_border_width_all(1)
		# Today gets a rim whether or not it's been played — it's the actionable one.
		sb.border_color = accent if day == today else ThemeManager.color("stroke")
		dot.add_theme_stylebox_override("panel", sb)
		# On a cold streak today's cell BREATHES. Fourteen identical empty slots
		# say nothing about which one is still winnable, and the one that is, is
		# the entire reason to show a fortnight rather than a number.
		var cold := day == today and not lit
		if cold and not bool(SettingsManager.get_value("reduce_motion")):
			dot.modulate.a = 0.55
			dot.tree_entered.connect(func():
				var tw := dot.create_tween().set_loops()
				tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
				tw.tween_property(dot, "modulate:a", 1.0, 1.1)
				tw.tween_property(dot, "modulate:a", 0.55, 1.1))
		# The chain lights up oldest → today, one cell at a time — the habit
		# being re-walked on every visit.
		if lit:
			var wait := 0.25 + float(lit_n) * 0.07
			dot.modulate.a = 0.0
			dot.tree_entered.connect(func():
				var tw := dot.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				tw.tween_property(dot, "modulate:a", 1.0, 0.25).set_delay(wait))
		if lit:
			lit_n += 1
		cell.add_child(dot)

		var d := _label(String(_WEEKDAY_INITIALS[(day + 4) % 7]), 27)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		d.add_theme_color_override("font_color",
			ThemeManager.color("text_dim") if day == today else ThemeManager.color("text_faint"))
		cell.add_child(d)
		row.add_child(cell)
	return row

# --- Mastery by mode ----------------------------------------------------------
## What the rank is actually made of: the series won in each mode against that
## mode's RANK YARDSTICK (GameModes.Mode.mastery_yardstick, ten series unless
## the mode names its own) — the exact inputs to the tier ladder, and the one
## view neither Statistics (totals) nor Achievements (pass/fail) provides. This
## card divides by the same number GameStats.best_mastery_ratio does, or it
## would contradict the very rank it claims to explain. A mode's first win is
## still celebrated — in the Trophy Case, which is where "beat this mode" lives.
## Null when no series has been won yet, so the section drops out entirely.
func _mastery_card() -> Control:
	var open_rows: Array = []
	var done_rows: Array = []
	var leader: String = String(GameStats.best_mastery_ratio()["mode_id"])
	for mode in GameModes.all():
		var won := int(GameStats.mode_record(mode.id).get("series_won", 0))
		var yard: int = mode.mastery_yardstick()
		if won <= 0 or yard <= 0:
			continue
		var entry := {
			"id": mode.id,
			"won": won,
			"ratio": float(won) / float(yard),
		}
		if won >= yard:
			done_rows.append(entry)
		else:
			open_rows.append(entry)
	if open_rows.is_empty() and done_rows.is_empty():
		return null

	# Still-climbing modes lead, closest first — those are the ones with something
	# to do. Cleared modes follow as a compact honour roll. Rendering a beaten mode
	# as a full bar reading "100%" five times over says nothing and was the single
	# most repetitive thing on the page.
	open_rows.sort_custom(func(a, b): return float(a["ratio"]) > float(b["ratio"]))
	done_rows.sort_custom(func(a, b): return float(a["ratio"]) > float(b["ratio"]))

	var card := _card(2)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_LG))
	card.add_child(col)
	var first := true
	for r in open_rows + done_rows:
		if not first:
			col.add_child(_hrule())
		first = false
		var e: Dictionary = r
		col.add_child(_mastery_row(String(e["id"]), int(e["won"]),
			float(e["ratio"]), String(e["id"]) == leader))
	return card

## One mode's line: its own icon, the mode name, and either a bar in the tier
## colour that mode has earned (still climbing) or a single gold "mastered" mark
## (the ladder done).
func _mastery_row(mode_id: String, won: int, ratio: float, leader: bool) -> Control:
	var mode := GameModes.get_mode(mode_id)
	var mastered := ratio >= 1.0
	var accent := _tier_accent(TierBadge.current_index(ratio))

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	var chip := _mode_chip(mode, 76.0)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chip)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))

	var head := HBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := _label(mode.title, 36)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", ThemeManager.color("text"))
	if ThemeManager.display_font:
		t.add_theme_font_override("font", ThemeManager.display_font)
	head.add_child(t)
	var mark := _label("✓ MASTERED" if mastered else "%d%%" % int(round(ratio * 100.0)), 33)
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_theme_color_override("font_color", ThemeManager.color("gold") if mastered else accent)
	head.add_child(mark)
	col.add_child(head)

	# Mastered modes get no bar — the icon and the mark already say it, and a
	# rail of full bars is just noise.
	if not mastered:
		col.add_child(_progress_bar(ratio, accent, accent.lerp(Color.WHITE, 0.35), 10.0))

	# Past the yardstick, "23 / 10" reads like a broken fraction — a mastered mode
	# reports its series won outright instead.
	var detail := "%s series won" % _fmt_group(won) if mastered \
		else "%s / %s series" % [_fmt_group(won), _fmt_group(mode.mastery_yardstick())]
	if leader:
		detail += "  ·  carries your rank"
	var d := _label(detail, 30)
	d.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	col.add_child(d)
	row.add_child(col)
	return row

# --- Trophy case --------------------------------------------------------------
## A showcase rail of the actual earned art — the tier-shield ladder followed by
## the achievement medallions — over the two summary meters. The full interactive
## rail (with detail modals) lives on the Achievements screen; the section header
## links out. Earned pieces glow in their own accent; unearned ones sit dimmed so
## the case reads as a collection with more to fill in.
## The collection, in whichever of three views the player left it in.
##
## A RAIL is the right shape for a handful of pieces and the wrong one for
## twenty-nine: past the fourth item everything is off-screen, which is how a
## page that owns the whole trophy catalogue ended up showing four of it. The
## view is remembered in the profile section, so the choice survives the trip to
## a mode and back.
func _trophy_case() -> Control:
	var card := _card(2)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	card.add_child(col)

	var ratio: float = GameStats.best_mastery_ratio()["ratio"]
	var tier_idx: int = TierBadge.current_index(ratio)
	var tiers_have := TierBadge.unlocked_count(ratio)
	var ach_have := Achievements.unlocked_count()

	col.add_child(_case_switch())

	# The body is swapped in place rather than by rebuilding the page: switching
	# view is a look at the same facts, and a full _refresh would restart every
	# count-up and bar on the screen to answer it.
	_case_body = MarginContainer.new()
	_case_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_case_body.add_child(_case_view_node())
	col.add_child(_case_body)

	col.add_child(_meter_row("Tiers", tiers_have, TierBadge.count(),
		float(tiers_have) / float(TierBadge.count()), _tier_accent(tier_idx)))
	col.add_child(_meter_row("Achievements", ach_have, Achievements.total_count(),
		float(ach_have) / float(maxi(Achievements.total_count(), 1)), ThemeManager.color("accent")))

	# A medal earned since the player last looked gets a real welcome, once. The
	# stamp goes in on the SAME visit that celebrates, so a rebuild (a theme
	# change, a swapped view) cannot replay it.
	_greet_new_medals(card)
	return card

const CASE_VIEWS := ["Rail", "Grid", "Sky"]

## The three-way view switch. Segmented rather than a menu: three options that
## change one thing want to show all three and which is on.
func _case_switch() -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))
	var paints: Array = []
	for i in CASE_VIEWS.size():
		var idx := i
		var pill := PanelContainer.new()
		var lbl := _label(String(CASE_VIEWS[i]), 28)
		lbl.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
		pill.add_child(lbl)
		var paint := func() -> void:
			var on := _case_view == idx
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(ThemeManager.color("accent"), 0.22) if on \
				else ThemeManager.color("control")
			sb.set_corner_radius_all(int(DesignSystem.RADIUS_PILL))
			sb.set_border_width_all(2 if on else 1)
			sb.border_color = ThemeManager.color("accent") if on \
				else ThemeManager.color("control_stroke")
			sb.content_margin_left = DesignSystem.SPACE_MD
			sb.content_margin_right = DesignSystem.SPACE_MD
			sb.content_margin_top = DesignSystem.SPACE_XS
			sb.content_margin_bottom = DesignSystem.SPACE_XS
			sb.anti_aliasing = true
			pill.add_theme_stylebox_override("panel", sb)
			lbl.add_theme_color_override("font_color",
				ThemeManager.color("accent") if on else ThemeManager.color("text_dim"))
		paint.call()
		paints.append(paint)
		UI.make_scroll_tappable(pill, func():
			if _case_view == idx:
				return
			_case_view = idx
			Haptics.light()
			var prof := _profile()
			prof["case_view"] = idx
			_save(prof)
			for pnt in paints:
				(pnt as Callable).call()
			_swap_case_body())
		row.add_child(pill)
	return row

## Replaces the case body with the current view, cross-faded so the switch reads
## as the same collection re-laid-out rather than as a page reload.
func _swap_case_body() -> void:
	if not is_instance_valid(_case_body):
		return
	for c in _case_body.get_children():
		c.queue_free()
	var node := _case_view_node()
	node.modulate.a = 0.0
	_case_body.add_child(node)
	var tw := node.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(node, "modulate:a", 1.0, DesignSystem.DUR_BASE)

func _case_view_node() -> Control:
	match _case_view:
		1: return _case_grid()
		2: return _case_sky()
	return _case_rail()

## Every piece in the case, in ladder order: the seven tier shields, then the
## achievement medallions. Hidden achievements stay hidden until earned.
func _case_items() -> Array:
	var ratio: float = GameStats.best_mastery_ratio()["ratio"]
	var tier_idx: int = TierBadge.current_index(ratio)
	var out: Array = []
	for i in TierBadge.count():
		out.append({"kind": "tier", "idx": i, "earned": i <= tier_idx})
	for id in Achievements.ordered_ids():
		var sid := String(id)
		var def := Achievements.definition(sid)
		var unlocked := Achievements.is_unlocked(sid)
		if bool(def.get("hidden", false)) and not unlocked:
			continue
		out.append({"kind": "medal", "id": sid, "earned": unlocked})
	return out

func _case_item_node(e: Dictionary, box: float) -> Control:
	if String(e["kind"]) == "tier":
		return _trophy_badge(int(e["idx"]), bool(e["earned"]), box)
	return _trophy_medal(String(e["id"]), bool(e["earned"]), box)

## The original view: one horizontal shelf, oldest rank first.
func _case_rail() -> Control:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("separation", 0)

	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 150)
	var rail := HBoxContainer.new()
	rail.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	scroll.add_child(rail)

	var first := true
	for e: Dictionary in _case_items():
		if String(e["kind"]) == "medal" and first:
			rail.add_child(_vrule())
			first = false
		var item := _case_item_node(e, 138.0)
		if item != null:
			rail.add_child(item)
	rail.add_child(_rail_tail())
	_stagger_case(rail)
	wrap.add_child(_rail_fade(scroll))
	# The shelf the collection stands ON. A rail of trophies floating in the
	# middle of a pane reads as a filmstrip; one line of lit edge under them and
	# they are objects on a surface.
	wrap.add_child(Shelf.new(ThemeManager.color("stroke"),
		_tier_accent(TierBadge.current_index(GameStats.best_mastery_ratio()["ratio"]))))
	return wrap

## Everything at once, wrapped. The view for a collection that has outgrown a
## single line — which is every collection past the first few hours.
func _case_grid() -> Control:
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", int(DesignSystem.SPACE_MD))
	flow.add_theme_constant_override("v_separation", int(DesignSystem.SPACE_MD))
	for e: Dictionary in _case_items():
		var item := _case_item_node(e, 132.0)
		if item != null:
			flow.add_child(item)
	_stagger_case(flow)
	return flow

## The collection as a sky: every piece a star on one figure, linked in the order
## it was earned.
##
## Positions come from a golden-angle spiral rather than from randomness, so the
## same collection draws the same constellation every time the page is built — a
## star map that re-deals itself on every visit is a screensaver, not a record.
func _case_sky() -> Control:
	var items := _case_items()
	var map := StarMap.new(_spiral_points(items.size()),
		_tier_accent(TierBadge.current_index(GameStats.best_mastery_ratio()["ratio"])))
	map.custom_minimum_size = Vector2(0, 460)
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pts := map.points
	for i in items.size():
		var e: Dictionary = items[i]
		var item := _case_item_node(e, 96.0)
		if item == null:
			continue
		var at: Vector2 = pts[i]
		# Anchored by FRACTION, so the figure holds its shape on any width without
		# a single line of layout code.
		item.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		item.anchor_left = at.x; item.anchor_right = at.x
		item.anchor_top = at.y; item.anchor_bottom = at.y
		item.offset_left = -48.0; item.offset_right = 48.0
		item.offset_top = -48.0; item.offset_bottom = 48.0
		map.add_child(item)
	_stagger_case(map)
	return map

## A golden-angle spiral in 0..1 space: the arrangement sunflowers use, which is
## the one that never leaves a gap or a collision however many points it holds.
func _spiral_points(n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := float(i) * 2.399963   # the golden angle, in radians
		var r := 0.10 + 0.36 * sqrt(float(i) / float(maxi(n - 1, 1)))
		pts.append(Vector2(0.5 + cos(a) * r * 0.92, 0.5 + sin(a) * r))
	return pts

## The case fills like a collection being laid out: each piece a beat after the
## one before it.
func _stagger_case(parent: Control) -> void:
	var delay := 0.0
	for c in parent.get_children():
		if not (c is Control):
			continue
		var piece := c as Control
		piece.modulate.a = 0.0
		var d := delay
		piece.tree_entered.connect(func():
			var tw := piece.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tw.tween_property(piece, "modulate:a", 1.0, 0.3).set_delay(0.15 + d))
		delay += 0.045

## The lit edge a rail of trophies stands on: one bright line fading out at both
## ends, over a short wash of shadow. Drawn rather than built from panels — it is
## two gradients, and two gradients as StyleBoxes would be two more nodes on a
## page that already carries thirty.
class Shelf extends Control:
	var line: Color
	var glow: Color

	func _init(p_line: Color, p_glow: Color) -> void:
		line = p_line
		glow = p_glow
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 22)

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		if size.x <= 4.0:
			return
		# The edge, brightest in the middle: a hard line all the way across reads
		# as a divider between sections rather than as a surface under objects.
		var segs := 24
		for i in segs:
			var t0 := float(i) / float(segs)
			var t1 := float(i + 1) / float(segs)
			var fade := sin(PI * (t0 + t1) * 0.5)
			draw_line(Vector2(size.x * t0, 1.0), Vector2(size.x * t1, 1.0),
				Color(line.lerp(glow, 0.35), 0.75 * fade), 2.0, true)
		# ...and the shadow it casts down into the card.
		for i in 6:
			var f := float(i) / 6.0
			draw_line(Vector2(size.x * 0.06, 3.0 + f * 10.0),
				Vector2(size.x * 0.94, 3.0 + f * 10.0),
				Color(0, 0, 0, 0.10 * (1.0 - f)), 3.0, true)

## The link lines of the sky view. The stars themselves are child nodes anchored
## by fraction; this draws the figure between them from the SAME fractions, so
## the two can never disagree about where a star is.
class StarMap extends Control:
	var points: PackedVector2Array
	var tint: Color

	func _init(p_points: PackedVector2Array, p_tint: Color) -> void:
		points = p_points
		tint = p_tint
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		if points.size() < 2 or size.x <= 4.0:
			return
		for i in points.size() - 1:
			draw_line(points[i] * size, points[i + 1] * size,
				Color(tint, 0.16), 2.0, true)

## One tier shield in the case; earned bright, unearned dimmed. Tapping it opens
## the rank's detail sheet right here.
func _trophy_badge(i: int, earned: bool, box: float = 138.0) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(box, box)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var view := TierBadge.make_view(box, i, not earned)
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.custom_minimum_size = Vector2.ZERO
	holder.add_child(view)
	UI.make_scroll_tappable(holder, func(): _tier_modal(i, earned))
	return holder

## One achievement medallion.
##
## An unearned medal is a SILHOUETTE with a rim of light behind it, not a greyed
## picture. Grey said "disabled"; a silhouette says "there is something here you
## have not seen yet", which is the entire job of an empty slot in a trophy case
## — and it makes the earned ones, in full colour beside it, actually look won.
##
## NEVER NULL. A badge whose medal PNG has not been painted yet draws as its
## catalog icon on a glass chip (see _medal_chip) rather than vanishing from the
## case: the old rail SKIPPED an unpainted crown entirely, so it was absent from
## the shelf even once earned, with no warning anywhere.
func _trophy_medal(id: String, unlocked: bool, box: float = 138.0) -> Control:
	var medal := UI.icon_tex("res://assets/images/medals/%s.png" % id)
	if medal == null:
		return _medal_chip(id, unlocked, box)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(box * 0.82, box)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	if not unlocked:
		# The rim: the same shape, a touch larger, in the theme accent behind the
		# dark body — light leaking round an object you cannot see yet.
		var rim := TextureRect.new()
		rim.texture = medal
		rim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rim.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var grow := box * 0.035
		rim.offset_left = -grow; rim.offset_top = -grow
		rim.offset_right = grow; rim.offset_bottom = grow
		rim.material = _silhouette_material(
			Color(ThemeManager.color("accent"), 0.55))
		holder.add_child(rim)

	var rect := TextureRect.new()
	rect.texture = medal
	rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	if not unlocked:
		# A SLATE, not the backdrop colour. Filling with bg0 on a dark theme paints
		# the medal in the exact colour of the card behind it, so the silhouette
		# stops being a shape and becomes a hole punched in the trophy case.
		rect.material = _silhouette_material(Color(
			ThemeManager.color("bg0").lerp(ThemeManager.color("text"), 0.22), 0.95))
	holder.add_child(rect)

	# What is still between the player and this medal, when that is a number the
	# game already counts. A locked medal with no measure stays a plain
	# silhouette rather than wearing an empty ring, which would read as zero
	# progress on something that simply is not measured that way.
	if not unlocked:
		var prog := _achievement_progress(id)
		if prog >= 0.0:
			var ring := ProgressRing.new()
			ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			ring.thickness = maxf(3.0, box * 0.035)
			ring.track_color = Color(ThemeManager.color("stroke"), 0.6)
			ring.color_a = ThemeManager.color("accent")
			ring.color_b = ThemeManager.color("accent").lerp(Color.WHITE, 0.4)
			ring.rounded_caps = true
			ring.value = 0.0
			holder.add_child(ring)
			ring.tree_entered.connect(func():
				var tw := ring.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				tw.tween_property(ring, "value", prog, DesignSystem.DUR_SLOW).set_delay(0.3))

	# The most recent unlock announces itself: the same glint the badges wear,
	# plus one pop, so the answer to "what did I just get?" is on screen without
	# reading a single label.
	if unlocked and id == _newest_medal_id():
		rect.material = TierBadge.shine_material(2.6)
		holder.pivot_offset = Vector2(box * 0.41, box * 0.5)
		holder.tree_entered.connect(func():
			var tw := holder.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tw.tween_property(holder, "scale", Vector2(1.14, 1.14), 0.22).set_delay(0.55)
			tw.tween_property(holder, "scale", Vector2.ONE, 0.34))

	UI.make_scroll_tappable(holder, func(): _medal_modal(id, unlocked))
	return holder

## The medal for a badge with no painted art: the DEF's own icon (`icon` plus
## its `icon_label`) as a PremiumIcon on a glass chip, in the badge's accent
## when earned and a neutral grey until then — the same chip the Achievements
## screen falls back to, so the two surfaces agree about what an unpainted
## badge looks like. Carries the same progress ring, newest-unlock pop and tap
## sheet a painted medal does.
func _medal_chip(id: String, unlocked: bool, box: float) -> Control:
	var def := Achievements.definition(id)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(box * 0.82, box)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var raw_col: Color = ThemeManager.badge_accent(id) if unlocked else Color("6A7080")
	var plate := Panel.new()
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UI.glass_box(1, DesignSystem.RADIUS_MD)
	sb.bg_color = sb.bg_color.lerp(raw_col, 0.28 if unlocked else 0.12)
	sb.border_color = sb.border_color.lerp(raw_col, 0.6 if unlocked else 0.2)
	plate.add_theme_stylebox_override("panel", sb)
	holder.add_child(plate)

	var icon_col := Color(1, 1, 1, 1.0) if unlocked else Color(1, 1, 1, 0.45)
	var icon: Control = PremiumIcon.make(String(def.get("icon", "star")), icon_col,
		box * 0.5, String(def.get("icon_label", "")))
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := box * 0.2
	icon.offset_left = pad
	icon.offset_top = pad
	icon.offset_right = -pad
	icon.offset_bottom = -pad
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in icon.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(icon)

	if not unlocked:
		var prog := _achievement_progress(id)
		if prog >= 0.0:
			var ring := ProgressRing.new()
			ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			ring.thickness = maxf(3.0, box * 0.035)
			ring.track_color = Color(ThemeManager.color("stroke"), 0.6)
			ring.color_a = ThemeManager.color("accent")
			ring.color_b = ThemeManager.color("accent").lerp(Color.WHITE, 0.4)
			ring.rounded_caps = true
			ring.value = 0.0
			holder.add_child(ring)
			ring.tree_entered.connect(func():
				var tw := ring.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				tw.tween_property(ring, "value", prog, DesignSystem.DUR_SLOW).set_delay(0.3))

	if unlocked and id == _newest_medal_id():
		holder.pivot_offset = Vector2(box * 0.41, box * 0.5)
		holder.tree_entered.connect(func():
			var tw := holder.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tw.tween_property(holder, "scale", Vector2(1.14, 1.14), 0.22).set_delay(0.55)
			tw.tween_property(holder, "scale", Vector2.ONE, 0.34))

	UI.make_scroll_tappable(holder, func(): _medal_modal(id, unlocked))
	return holder

## The flat-ink material a locked medal is painted with: the art's own alpha,
## filled with one colour.
##
## Ascending edges only and no screen texture — this samples the medal's own
## TEXTURE and nothing else, so it is safe inside the SubViewport the share card
## renders through and on the D3D12 backend the editor runs on.
static var _silhouette_shader: Shader

func _silhouette_material(ink: Color) -> ShaderMaterial:
	if _silhouette_shader == null:
		_silhouette_shader = Shader.new()
		_silhouette_shader.code = "shader_type canvas_item;\n" \
			+ "uniform vec4 ink : source_color = vec4(0.0, 0.0, 0.0, 1.0);\n" \
			+ "void fragment() {\n" \
			+ "\tfloat a = texture(TEXTURE, UV).a;\n" \
			+ "\tCOLOR = vec4(ink.rgb, a * ink.a);\n" \
			+ "}\n"
	var mat := ShaderMaterial.new()
	mat.shader = _silhouette_shader
	mat.set_shader_parameter("ink", ink)
	return mat

## The most recently unlocked achievement, or "" when nothing is unlocked.
## Cached for the build: every medal in the case asks, and the answer walks the
## whole catalogue.
func _newest_medal_id() -> String:
	if _newest_cached:
		return _newest_id
	_newest_cached = true
	var best := 0
	for id in Achievements.ordered_ids():
		var at := Achievements.unlocked_at(String(id))
		if at > best:
			best = at
			_newest_id = String(id)
	_newest_at = best
	return _newest_id

## Confetti for a medal earned since the player last opened this page.
##
## The stamp is written on the visit that celebrates, so switching view or
## changing theme (both of which rebuild this card) cannot replay it — the same
## seen_tier rule the rank-up ceremony follows, for the same reason.
func _greet_new_medals(card: Control) -> void:
	if _newest_medal_id().is_empty():
		return
	var prof := _profile()
	if _newest_at <= int(prof.get("seen_medal_at", 0)):
		return
	prof["seen_medal_at"] = _newest_at
	_save(prof)
	card.tree_entered.connect(func():
		await get_tree().process_frame
		if is_instance_valid(card):
			Confetti.preview(card, ThemeManager.palette(), 30))

## How close the player is to achievement `id`, or -1 when it is not a thing the
## game measures on a scale.
##
## DERIVED from the counters that unlock it rather than stored: Achievements
## persists unlocked/locked and nothing else, and a second copy of "how far along
## is this" would be a number that could disagree with the one that actually
## fires the unlock.
func _achievement_progress(id: String) -> float:
	for mode_id: String in Achievements.MODE_WIN_ACHIEVEMENT:
		if String(Achievements.MODE_WIN_ACHIEVEMENT[mode_id]) != id:
			continue
		var mode := GameModes.get_mode(mode_id)
		# A win crown is one series win: nothing to measure on a scale, so no ring.
		return -1.0
	for mode_id: String in Achievements.MODE_MASTERY_ACHIEVEMENT:
		if String(Achievements.MODE_MASTERY_ACHIEVEMENT[mode_id]) != id:
			continue
		var need := GameModes.get_mode(mode_id).mastery_yardstick()
		if need <= 0:
			return -1.0
		var have := int(GameStats.mode_record(mode_id).get("series_won", 0))
		return clampf(float(have) / float(need), 0.0, 1.0)
	if id == "streak_7" or id == "streak_30":
		var need := 7 if id == "streak_7" else 30
		var days := int(GameStats.get_stat("current_streak_days"))
		return clampf(float(days) / float(need), 0.0, 1.0)
	return -1.0

## Explains the difficulty-normalized tier ladder: your rank is the series won
## in your best mode measured against that mode's own ladder, so mastering any
## mode earns Gold whatever its ladder asks. The Classic counts are shown as a
## concrete example.
func _rank_info() -> void:
	var m := ModalOverlay.new()
	m.set_header("Mastery Ranks", "How ranks are earned",
		"Your rank is the series you have won in a mode, measured against that mode's own ladder, so it is fair across every board. Most ladders ask for ten series. Win a quarter of them for Bronze, half for Silver, and the whole ladder for Gold.\n\nExample: Classic (ladder of %d series)" % GameModes.get_mode("classic").mastery_yardstick())
	var classic := GameModes.get_mode("classic")
	for i in TierBadge.count():
		var need := _series_for_tier(classic, i)
		m.add_stat_row(String(TierBadge.tier(i)["name"]),
			"%d series" % need if need != 1 else "1 series")
	m.add_action("Got it", PremiumButton.Variant.GLASS, func(): m.close())
	m.open(self)

## Detail sheet for one tier shield: what the rank demands, with Classic's
## concrete series count as the example (the same maths as the rank-info modal).
func _tier_modal(i: int, earned: bool) -> void:
	var t := TierBadge.tier(i)
	var m := ModalOverlay.new()
	m.compact = true
	var status := "Earned. Your series wins reached this rank." if earned \
		else "Still ahead of you."
	var rule := _tier_rule_text(i)
	m.set_header("Mastery Rank", String(t["name"]), status + "\n\n" + rule)
	# The rank-up ceremony fires once, unannounced, on whatever screen the player
	# happened to be looking at — so the biggest moment the game has is also the
	# easiest one to miss entirely. An earned shield hands it back.
	if earned:
		m.add_action("Replay ceremony", PremiumButton.Variant.GLASS, func():
			m.close()
			SceneRouter.replay_rank_up(i))
	m.add_action("Done", PremiumButton.Variant.GLASS, func(): m.close())
	m.open(self)

## Detail sheet for a medallion: the achievement behind it, the theme that wears
## its colours, and whether it's still locked.
func _medal_modal(id: String, unlocked: bool) -> void:
	var def := Achievements.definition(id)
	var m := ModalOverlay.new()
	m.compact = true
	var body := String(def.get("detail", ""))
	if not unlocked:
		body += "\n\nStill locked — keep playing."
	# NOT "reward theme". The twelve badge-earned themes were retired into
	# gem-priced Shop items (grandfathered for anyone who had already earned
	# one), so a badge no longer pays a theme out — the link survives as identity
	# only, which is also what ThemeManager.badge_accent reads. Restoring the old
	# "Reward theme: X" wording here would promise a payout that cannot happen.
	# See core/entitlements.gd LEGACY_REWARD_BADGES.
	var theme_id := Entitlements.badge_legacy_theme(id)
	if not theme_id.is_empty():
		body += "\n\nSignature theme: %s — available in the Shop." % ThemeManager.theme_name(theme_id)
	m.set_header("Achievement", String(def.get("title", id)), body)
	m.add_action("Done", PremiumButton.Variant.GLASS, func(): m.close())
	m.open(self)

## A labelled meter: "<name> ........ <have> / <all>" over a gradient bar.
func _meter_row(name_text: String, have: int, all: int, ratio: float, accent: Color) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))
	var head := HBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := _label(name_text, 33)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	head.add_child(n)
	# Counts UP to the tally, the way every other headline number on this page
	# does. The bar under it already animates, and a bar that fills beside a
	# number that was correct before it started reads as two unrelated things.
	var count := _label("%d / %d" % [have, all], 33)
	count.add_theme_color_override("font_color", ThemeManager.color("text"))
	if ThemeManager.display_font:
		count.add_theme_font_override("font", ThemeManager.display_font)
	if have > 0:
		count.text = "0 / %d" % all
		count.tree_entered.connect(func():
			var tw := count.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tw.tween_method(func(v: float): count.text = "%d / %d" % [int(round(v)), all],
				0.0, float(have), DesignSystem.DUR_SLOW).set_delay(0.15))
	head.add_child(count)
	box.add_child(head)
	box.add_child(_progress_bar(ratio, accent, accent.lerp(Color.WHITE, 0.35), 14.0))
	return box

# --- Recent runs --------------------------------------------------------------
## In a card like every other section (it used to float bare on the page) and
## behind the same edge fade, so the run that's half off-screen reads as "there's
## more this way" instead of a clipping bug.
func _recent_scores_card() -> Control:
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 248)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	scroll.add_child(row)

	var card := _card(2)
	card.add_child(_rail_fade(scroll))

	# Prefer the dated series history; fall back to per-mode bests for saves from
	# before it existed.
	var history := GameStats.score_history()
	if not history.is_empty():
		var best_idx := 0
		var best_val := -1
		for i in history.size():
			var s := int((history[i] as Dictionary).get("score", 0))
			if s > best_val:
				best_val = s
				best_idx = i
		for i in history.size():
			var e: Dictionary = history[i]
			row.add_child(_score_card(int(e.get("score", 0)), String(e.get("mode", "")),
				_date_short(int(e.get("t", 0))), i == best_idx,
				String(e.get("pace", "")), bool(e.get("won", false))))
		row.add_child(_rail_tail())
		return card

	var scores := _score_list()
	if scores.is_empty():
		# The same card shape a real series gets, in outline — a shelf with a
		# space on it reads as somewhere a series will go; a sentence reads as a
		# fault.
		row.add_child(_empty_run_card())
		return card
	var first := true
	for entry in scores:
		row.add_child(_score_card(int(entry["score"]), String(entry["mode_id"]), "", first))
		first = false
	row.add_child(_rail_tail())
	return card

func _date_short(unix: int) -> String:
	if unix <= 0:
		return ""
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%s %d" % [_MONTHS[int(d["month"]) - 1], int(d["day"])]

## Best score per mode (plus the overall best), sorted high → low.
func _score_list() -> Array:
	var bests := SaveManager.get_section(BEST_SECTION, {})
	var out: Array = []
	for mode_id in bests.keys():
		var sc := int(bests[mode_id])
		if sc > 0:
			out.append({"score": sc, "mode_id": String(mode_id)})
	out.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	return out

## A recent-series card: the mode's icon, the score, a "Mode · vs Rival" line
## and the date, with a won or lost mark. The best of the set wears the violet
## gradient + crown.
## The card's fixed size, and the width its text actually gets: the column
## inside is inset 20 on each side, so anything wider than CARD_TEXT_W is drawing
## outside the card it belongs to.
const CARD_W := 252.0
const CARD_H := 236.0
const CARD_TEXT_W := CARD_W - 40.0

func _score_card(score: int, mode_id: String, date_label: String, highlight: bool,
		pace_id: String = "", won: bool = false) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(CARD_W, CARD_H)

	if highlight:
		var grad := GradientPanel.make(C_VIOLET, C_INDIGO, 28.0, Vector2(1, 1))
		grad.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.add_child(grad)
		var crown := TextureRect.new()
		crown.texture = UI.icon_tex("best_score")
		# Pinned to the card's top-right corner via anchors, so it tracks the
		# card's real width instead of assuming the design measure.
		crown.anchor_left = 1.0
		crown.anchor_right = 1.0
		crown.offset_left = -76
		crown.offset_right = -16
		crown.offset_top = 12
		crown.offset_bottom = 72
		crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(crown)
	else:
		var panel := Panel.new()
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.add_theme_stylebox_override("panel", UI.glass_box(1, DesignSystem.RADIUS_MD))
		holder.add_child(panel)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))
	col.offset_left = 20
	col.offset_right = -20
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# The mode's own icon crowns each card, so which mode a score came from reads
	# at a glance.
	if not mode_id.is_empty():
		var micon := _tex_icon(GameModes.get_mode(mode_id).icon_path, 72)
		micon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(micon)

	var num := _label(_fmt_comma(score), 54)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# This card is a FIXED 252 wide (see the holder above) and its column is
	# anchored inside it, so nothing here can grow to accommodate the number —
	# the number has to fit CARD_TEXT_W or it draws over the card's own edge and
	# into its neighbour on the rail.
	num.max_width = CARD_TEXT_W
	num.add_theme_color_override("font_color", Color.WHITE if highlight else ThemeManager.color("text"))
	if ThemeManager.display_font:
		num.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(num)

	var parts: Array = []
	if not mode_id.is_empty():
		parts.append(GameModes.get_mode(mode_id).title)
	# The grade it came home at: "Expert" says what the score was worth.
	if not pace_id.is_empty():
		parts.append(Pace.title(pace_id))
	var sub := _label("  ·  ".join(parts) if not parts.is_empty() else "—", 33)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.max_width = CARD_TEXT_W
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.85) if highlight else ThemeManager.color("text_dim"))
	col.add_child(sub)

	# The result and the date on one quiet line. Only a series with a rival on
	# record knows whether it was won; older entries print the date alone.
	var foot: Array = []
	if not pace_id.is_empty():
		foot.append("Won" if won else "Lost")
	if not date_label.is_empty():
		foot.append(date_label)
	if not foot.is_empty():
		var fl := _label("  ·  ".join(foot), 30)
		fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fl.max_width = CARD_TEXT_W
		var won_col: Color = ThemeManager.color("gold")
		var fl_col: Color = Color(1, 1, 1, 0.7) if highlight else ThemeManager.color("text_faint")
		if not pace_id.is_empty() and won and not highlight:
			fl_col = won_col
		fl.add_theme_color_override("font_color", fl_col)
		col.add_child(fl)
	holder.add_child(col)
	return holder

# --- Identity editing (name + status + badge) ---------------------------------
## The sheet is IdentitySheet — ONE editor, shared with the Profile tab. It used
## to be ~95 lines copy-pasted into both screens, which is how the two ended up
## labelling the same control "BADGE AURA" here and "AVATAR COLOUR" there, for a
## setting that paints the same badge on both pages.
func _edit_identity() -> void:
	IdentitySheet.open(self, func(): _refresh())

# --- Page atmosphere ----------------------------------------------------------
## Everything that answers to the scroll position, in ONE handler.
##
## The scrollbar emits value_changed at pixel granularity through a touch drag,
## so a header band, a sticky capsule and a reveal check each connecting to it
## separately would be three subtree writes per event, every frame of every
## flick. The band and the capsule are also gated on a 1% change: past that they
## are visually identical writes that still re-composite their subtree.
func _on_scroll_atmosphere(v: float) -> void:
	var t := clampf(v / 380.0, 0.0, 1.0)
	if absf(t - _atm_t) >= 0.01:
		_atm_t = t
		if is_instance_valid(_header_band):
			_header_band.modulate.a = t
		if is_instance_valid(_sticky):
			_sticky.visible = t > 0.03
			_sticky.modulate.a = t
	_reveal_pass(v)

## How far above the fold a section is revealed, so it is already settled by the
## time it is properly on screen rather than animating under the reader's eyes.
const REVEAL_LEAD := 120.0

## Reveals the sections that have scrolled into reach, and forgets them.
##
## Walked BACKWARDS so a removal cannot skip its neighbour, and early-outs on an
## empty list — which is the state it is in for all but the first few flicks, and
## the reason this can afford to sit on the hot scroll path at all.
func _reveal_pass(v: float) -> void:
	if _pending.is_empty() or not is_instance_valid(_scroll):
		return
	var edge := v + _scroll.size.y - REVEAL_LEAD
	var i := _pending.size() - 1
	while i >= 0:
		var n: Control = _pending[i]
		if not is_instance_valid(n):
			_pending.remove_at(i)
		elif n.position.y <= edge:
			_pending.remove_at(i)
			_reveal(n)
		i -= 1

## One section rising into place — the same motion `stagger_in` gives the cards
## above the fold, so a page that reveals in two different ways still reads as
## one behaviour.
func _reveal(n: Control) -> void:
	n.pivot_offset = Vector2(n.size.x * 0.5, n.size.y)
	n.modulate.a = 0.0
	n.scale = Vector2(0.97, 0.94)
	var tw := n.create_tween().set_parallel()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(n, "modulate:a", 1.0, 0.34)
	tw.tween_property(n, "scale", Vector2.ONE, 0.52).set_trans(Tween.TRANS_BACK)

## Splits the page in two at the fold: what is already visible is staggered in on
## arrival, and everything below waits to be scrolled to.
##
## The whole column used to animate at once on entry, which meant a nine-section
## page spent its entrance budget on eight cards nobody could see — and by the
## time the player reached them they were simply there, with no arrival at all.
## Needs a laid-out tree, so it runs after on_ready's frame.
func _split_entrance() -> void:
	_pending.clear()
	if not is_instance_valid(_main_col):
		return
	var fold := size.y
	var near: Array = []
	for c in _main_col.get_children():
		if not (c is Control):
			continue
		var n := c as Control
		if n.position.y < fold:
			near.append(n)
		else:
			n.modulate.a = 0.0
			_pending.append(n)
	stagger_in(near)

## The bar, on a band of the rank's own light that deepens as the page scrolls.
##
## Once the hero has scrolled away, the three glyphs up here sit directly on a
## moving shard field with nothing between them and it. The band is what gives
## them a surface, and it arrives only when it is needed: at rest it is fully
## transparent, so nothing is added to the page as it first reads.
func _top_bar_stack(bar: Control) -> Control:
	var holder := MarginContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var accent := _tier_accent(TierBadge.current_index(
		GameStats.best_mastery_ratio()["ratio"]))
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	grad.colors = PackedColorArray([
		Color(accent, 0.34), Color(accent, 0.12), Color(accent, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.0, 0.0)
	gt.fill_to = Vector2(0.0, 1.0)
	gt.width = 4
	gt.height = 128
	var band := TextureRect.new()
	band.texture = gt
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Bleeds past the bar on three sides, so it reads as the page's own header
	# rather than as a plate sitting behind three buttons.
	band.offset_left = -DesignSystem.SPACE_XL
	band.offset_right = DesignSystem.SPACE_XL
	band.offset_top = -DesignSystem.SPACE_XL
	band.offset_bottom = DesignSystem.SPACE_LG
	band.modulate.a = 0.0
	_header_band = band
	holder.add_child(band)
	holder.add_child(bar)
	return holder

## The rank, docked into the top bar once the hero it belongs to is off screen.
## Tapping it goes back up to the badge — the capsule IS the badge, the same
## relationship Home's floating capsule has with this page.
func _sticky_capsule() -> Control:
	var wrap := CenterContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ratio: float = GameStats.best_mastery_ratio()["ratio"]
	var idx := TierBadge.current_index(ratio)
	var accent := _tier_accent(idx)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))
	var badge := TierBadge.make_view(56.0, maxi(idx, 0), idx < 0)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var lbl := _label("UNRANKED" if idx < 0 \
		else String(TierBadge.tier(idx)["name"]).to_upper(), 30)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color",
		ThemeManager.color("text_dim") if idx < 0 else accent)
	if ThemeManager.display_font:
		lbl.add_theme_font_override("font", ThemeManager.display_font)
	row.add_child(lbl)

	var pill := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.r, accent.g, accent.b, 0.16)
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_PILL))
	sb.set_border_width_all(1)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	sb.content_margin_left = DesignSystem.SPACE_SM
	sb.content_margin_right = DesignSystem.SPACE_MD
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.anti_aliasing = true
	pill.add_theme_stylebox_override("panel", sb)
	pill.add_child(row)
	# Starts hidden AND transparent: `visible` keeps it out of the hit test while
	# the hero is on screen, so an invisible capsule cannot eat a tap meant for
	# the bar behind it.
	pill.visible = false
	pill.modulate.a = 0.0
	_sticky = pill
	UI.make_scroll_tappable(pill, func(): _scroll_to_top())
	wrap.add_child(pill)
	return wrap

## Glides the page back to the hero. A jump would lose the one thing the capsule
## is for — showing the player that the badge is still up there.
func _scroll_to_top() -> void:
	if not is_instance_valid(_scroll):
		return
	# Captured, not read through the member: the tween outlives a rebuild, and a
	# member that has been reassigned mid-glide would leave this driving the
	# scroll position of a page that no longer exists.
	var target := _scroll
	var from := float(target.scroll_vertical)
	var setter := func(v: float) -> void:
		if is_instance_valid(target):
			target.scroll_vertical = int(v)
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(setter, from, 0.0, DesignSystem.DUR_SLOW)

# --- Empty states -------------------------------------------------------------
## What the Mastery section says before there is any mastery to break down.
##
## The section used to drop out entirely, which left the page silent about the
## one thing it exists to explain — where a rank comes from — for exactly the
## player who has never seen a rank. Three real modes with their real targets,
## and the rule written out once.
func _mastery_teaser() -> Control:
	var card := _card(2)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_LG))
	card.add_child(col)

	var intro := _label("Your rank is the series you have won in a mode, measured against that mode's own ladder. Win the whole ladder and you have that mode mastered.", 32)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	col.add_child(intro)

	var shown := 0
	for mode in GameModes.all():
		if shown >= 3 or mode.mastery_yardstick() <= 0:
			continue
		if shown > 0:
			col.add_child(_hrule())
		col.add_child(_teaser_row(mode))
		shown += 1
	return card

## One unplayed mode: a ghost of its icon, the mode's name, and the series its
## own ladder is measured against.
func _teaser_row(mode: GameModes.Mode) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	var chip := _mode_chip(mode, 76.0, true)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chip)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))
	var t := _label(mode.title, 36)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_color_override("font_color", ThemeManager.color("text"))
	if ThemeManager.display_font:
		t.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(t)
	var d := _label("Not started  ·  %s series to master" % _fmt_group(mode.mastery_yardstick()), 30)
	d.add_theme_color_override("font_color", ThemeManager.color("text_faint"))
	col.add_child(d)
	row.add_child(col)
	row.add_child(_chevron())
	UI.make_scroll_tappable(row, func():
		SceneRouter.goto(SceneRouter.Route["HOME"]))
	return row

## The run card that has not been played yet: the same shape as a real one, in
## outline, so the rail reads as a shelf with a space on it rather than as a
## sentence apologising for being empty.
func _empty_run_card() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(CARD_W, CARD_H)
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(ThemeManager.color("glass"), 0.35)
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_MD))
	sb.set_border_width_all(2)
	sb.border_color = Color(ThemeManager.color("accent"), 0.45)
	sb.anti_aliasing = true
	panel.add_theme_stylebox_override("panel", sb)
	holder.add_child(panel)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))
	col.offset_left = 20
	col.offset_right = -20
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip := _tex_icon("games_played", 84.0)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chip.modulate.a = 0.55
	col.add_child(chip)
	var lbl := _label("Your first series", 36)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.max_width = CARD_TEXT_W
	lbl.add_theme_color_override("font_color", ThemeManager.color("text"))
	if ThemeManager.display_font:
		lbl.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(lbl)
	var sub := _label("Play a game  ›", 32)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.max_width = CARD_TEXT_W
	sub.add_theme_color_override("font_color", ThemeManager.color("accent"))
	col.add_child(sub)
	holder.add_child(col)
	UI.make_scroll_tappable(holder, func():
		SceneRouter.goto(SceneRouter.Route["HOME"]))
	return holder

# --- Shared helpers -----------------------------------------------------------
## A section header with a crisp accent tick before the title, so sections read as
## clearly delineated blocks rather than melting into one another.
func _section(eyebrow_text: String, body: Control, action_text: String, action_cb: Callable) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The header sits closer to its own card than sections do to each other — that
	# difference is what makes a header read as belonging to what follows it.
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))

	var tick := Panel.new()
	tick.custom_minimum_size = Vector2(8, 32)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = ThemeManager.color("accent")
	tsb.set_corner_radius_all(4)
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
		act.add_theme_font_size_override("font_size", 32)
		act.add_theme_color_override("font_color", ThemeManager.color("accent"))
		act.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UI.make_scroll_tappable(act, action_cb)
		header.add_child(act)
	box.add_child(header)
	box.add_child(body)
	return box

## The SAME frosted glass card the rest of the app uses (Home's menu, the
## game-mode cards, Statistics): a real GlassPanel that samples and blurs the
## backdrop — including the drifting shard field — behind it. The page once used
## an opaque surface because bare glass vanished into a flat dark backdrop; the
## shard field gives the frost something to hold, so the glass family is back.
func _card(elevation: int = 2) -> PanelContainer:
	return UI.glass_card(elevation)

## What a rail's edge fade dissolves INTO. The glass pane has no single fill
## colour, so the fade sinks the last items into the theme's own backdrop tone —
## reading as the pane's edge falling into shadow rather than a solid slab.
func _card_bg() -> Color:
	var p := ThemeManager.palette()
	return p["bg1"]

## Wraps a horizontal rail so its right edge dissolves into the card instead of
## being guillotined mid-item. A MarginContainer sizes itself to the scroll and
## lets the fade overlay it at full rect; the gradient is transparent for most of
## the width and only bites in the last few percent.
func _rail_fade(scroll: ScrollContainer) -> Control:
	var holder := MarginContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(scroll)

	var bg := _card_bg()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.86, 1.0])
	grad.colors = PackedColorArray([Color(bg, 0.0), Color(bg, 0.0), Color(bg, 1.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.0, 0.0)
	gt.fill_to = Vector2(1.0, 0.0)
	gt.width = 256
	gt.height = 4

	var fade := TextureRect.new()
	fade.texture = gt
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(fade)
	return holder

## Trailing air inside a rail, so the last item can scroll clear of the fade.
func _rail_tail() -> Control:
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(DesignSystem.SPACE_LG, 0)
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tail

## The accent behind a given tier index (theme accent while still unranked).
func _tier_accent(tier_idx: int) -> Color:
	if tier_idx < 0:
		return ThemeManager.color("accent")
	return TierBadge.tier(tier_idx)["accent"]

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

## A gradient "pill" progress bar: a rounded glass track with a col_a→col_b fill
## that grows in on entry.
func _progress_bar(ratio: float, col_a: Color, col_b: Color, h: float) -> Control:
	var track := Panel.new()
	track.custom_minimum_size = Vector2(0, h)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = ThemeManager.color("glass")
	tsb.set_corner_radius_all(int(h * 0.5))
	tsb.set_border_width_all(1)
	tsb.border_color = ThemeManager.color("stroke")
	track.add_theme_stylebox_override("panel", tsb)

	var fill := GradientPanel.make(col_a, col_b, h * 0.5, Vector2(1, 0))
	fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var target := clampf(ratio, 0.0, 1.0)
	fill.anchor_right = 0.0
	fill.tree_entered.connect(func():
		var tw := fill.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(fill, "anchor_right", target, DesignSystem.DUR_SLOW).set_delay(0.15))
	track.add_child(fill)
	return track

# --- Number formatting + count-up ---------------------------------------------
func _fmt_comma(n: int) -> String:
	return UI.commafy(n)

## Series counts print BARE — "10", the way the game says them. A ladder is never
## long enough to need a separator, and the display-font comma at sub-headline
## sizes is a pixel of tail that reads as a decimal point. Scores keep the comma
## via _fmt_comma, where the headline size makes it unmistakable.
func _fmt_group(n: int) -> String:
	return str(n)

func _fmt_pct(n: int) -> String:
	return "%d%%" % n

## A display-font number label that counts up from 0 to `value` on entry (via
## `fmt`), settling on the final value. Static when there's nothing to animate.
func _count_label(value: int, fmt: Callable, font_sz: int) -> Label:
	var lbl := _label(fmt.call(value), font_sz)
	lbl.add_theme_color_override("font_color", ThemeManager.color("text"))
	if ThemeManager.display_font:
		lbl.add_theme_font_override("font", ThemeManager.display_font)
	if value > 1:
		lbl.text = fmt.call(0)
		lbl.tree_entered.connect(func():
			var tw := lbl.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tw.tween_method(func(v: float): lbl.text = fmt.call(int(round(v))),
				0.0, float(value), DesignSystem.DUR_SLOW + 0.3).set_delay(0.15))
	return lbl

## Scatters a cloud of soft twinkling dots around a `box`-sized badge — the
## reference look's glowing particle halo. Positions vary per index so it never
## looks gridded.
func _add_sparkles(parent: Control, box: float, tint: Color) -> void:
	const N := 14
	for i in N:
		var dot := _soft_glow(1.0, Color.WHITE.lerp(tint, randf_range(0.25, 0.6)), 0.95)
		var sz := randf_range(10.0, 30.0)
		var ang: float = float(i) * 2.4 + randf_range(-0.4, 0.4)
		var rad := box * 0.5 * randf_range(0.62, 1.30)
		var cx := box * 0.5 + cos(ang) * rad
		var cy := box * 0.5 + sin(ang) * rad
		dot.set_anchors_preset(Control.PRESET_TOP_LEFT)
		dot.offset_left = cx - sz * 0.5
		dot.offset_top = cy - sz * 0.5
		dot.offset_right = cx + sz * 0.5
		dot.offset_bottom = cy + sz * 0.5
		dot.modulate.a = 0.0
		parent.add_child(dot)
		var delay := randf_range(0.0, 2.2)
		var up := randf_range(0.7, 1.2)
		var down := randf_range(0.8, 1.4)
		dot.tree_entered.connect(func():
			var tw := dot.create_tween().set_loops()
			tw.tween_interval(delay)
			tw.tween_property(dot, "modulate:a", 0.9, up).set_trans(Tween.TRANS_SINE)
			tw.tween_property(dot, "modulate:a", 0.0, down).set_trans(Tween.TRANS_SINE)
			tw.tween_interval(randf_range(0.6, 1.8)))

## A thin full-width horizontal rule.
func _hrule() -> Control:
	var r := ColorRect.new()
	r.color = ThemeManager.color("stroke")
	r.custom_minimum_size = Vector2(0, 2)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## A thin full-height vertical rule (facts-strip column divider).
func _vrule() -> Control:
	var r := ColorRect.new()
	r.color = ThemeManager.color("stroke")
	r.custom_minimum_size = Vector2(2, 0)
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## Every non-wrapping label on this screen, which is nearly all of them — the
## numbers included. A FitLabel rather than a bare Label because this page states
## more growing figures than any other (best series, win streak, games played, a
## whole rail of series scores) and each of them used to answer a card too
## narrow for it by drawing straight through the card's edge.
##
## It is a true drop-in: an unexpanding FitLabel claims the same natural width a
## plain Label did, so nothing here moves until a number is genuinely too big for
## its box — and then it shrinks its type instead of leaving it. Sites that sit
## in a FIXED box (the recent-run cards) set `max_width` to say so.
func _label(text: String, font_sz: int) -> FitLabel:
	var l := FitLabel.make(text, font_sz)
	l.add_theme_font_size_override("font_size", font_sz)
	l.budget_text = text
	return l

func _tex_icon(path: String, box: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = UI.icon_tex(path)
	t.custom_minimum_size = Vector2(box, box)
	t.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _chevron() -> Label:
	var l := Label.new()
	l.text = "›"
	l.add_theme_font_size_override("font_size", 62)
	var col: Color = ThemeManager.color("text_dim")
	col.a = 0.7
	l.add_theme_color_override("font_color", col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l
