extends AppScreen
## Sign In — the welcome screen that follows the 2048 loading sequence.
##
## Two ways in, and they do DIFFERENT things:
##   • "Sign in with Play Games" runs a real interactive PGS prompt through
##     AccountManager, holding the page in a pending state until the facade
##     answers (auth_changed → continue, sign_in_failed / timeout → an inline
##     error and the buttons come back). Where no identity provider exists at all
##     — the editor, desktop, an Android build without the plugin — the button is
##     disabled up front rather than offering a prompt that cannot appear.
##   • "Continue as Guest" skips identity entirely and goes straight to Home.
## Nothing about the local game depends on the outcome: stats, achievements and
## themes live in the save either way, which is why the guest path is a peer of
## the sign-in path and not a lesser one.
##
## Settings' "Sign out" row simply returns the player here (PGS sessions are
## owned by the OS — see AccountManager — so there is no app-level session to
## end), and the hardware back press offers to leave the app, because this is the
## root of the boot chain and there is nothing behind it.
##
## The whole page is choreographed: the 2048 crystal wordmark inflates into place
## and sways (and plays along when tapped — every tap splashes confetti),
## sparkles twinkle around the mark, tiles drift up the backdrop, and confetti
## fires on arrival and again on the way out. Everything decorative is skipped
## under reduce-motion, which leaves a clean static page.

# The backdrop tiles' colours — the fixed accent story (as on Home), so the
# drifting field looks the same in every theme.
const C_VIOLET := Color("7B6CF6")
const C_INDIGO := Color("5B57E0")
const C_BLUE := Color("4D8DF0")
const C_SKY := Color("46C7E0")
const C_PINK := Color("F178B6")
const C_MAGENTA := Color("E0529C")
const C_ORANGE := Color("FF8A4C")
const C_AMBER := Color("F4B23E")

## The lowest luminance gap a glyph may have from the page background before the
## wordmark stops being readable. The tile ramp is chosen for a lit board, not for
## a dark welcome page, so on several themes the top two digits land near-black on
## near-black; this is the floor that lifts them back out.
const MIN_GLYPH_CONTRAST := 0.34

## How long a PGS prompt may hang before the page stops waiting on it. The prompt
## is an OS surface we get no cancellation signal from, so without this a player
## who dismisses it sits on a dead screen with two disabled buttons.
const SIGN_IN_TIMEOUT := 20.0

## Both call-to-actions share one height: they are peers, not a primary and a
## consolation prize.
const CTA_HEIGHT := 112.0

## The CTAs sit on a narrower measure than the rest of the page. Spanning the full
## content width made two 112pt-tall bars read as slabs rather than buttons; pulled
## in, they sit as a considered pair with air either side, and the hero above keeps
## the full measure it needs.
const CTA_MEASURE := 840.0

## Tall buttons need more rounding than the house radius, which is tuned for the
## standard 64pt row — at RADIUS_MD a 112pt bar reads nearly square. One token up,
## no further: still a button with corners, not a pill.
const CTA_RADIUS := DesignSystem.RADIUS_LG

const PLAY_LABEL := "Sign in with Play Games"

## One-shot latch: the celebration + navigation must never run twice.
var _leaving := false
## True while an interactive PGS prompt is outstanding.
var _pending := false
## Bumped per attempt so a timeout from attempt N can never fail attempt N+1.
var _attempt := 0

var _play: PremiumButton
var _guest: PremiumButton
var _status: Label            # inline availability note / sign-in error
var _fx_host: Control         # confetti layer, behind the content

func on_ready() -> void:
	# The page runs its own entrance, so the base screen fade must stay out of it.
	custom_entrance = true
	_build_backdrop()
	# The splash before us is a fixed midnight scene, not a themed one, so this page
	# is where the player's palette arrives. Landing it at full strength on frame one
	# — motif, light shafts and all, with no content on top yet — read as a slab of
	# wallpaper cutting in. Faded up over the entrance, the theme develops behind the
	# wordmark instead. Matched to the content stagger (which finishes at ~1.08s) so
	# the backdrop resolves just as the buttons land.
	fade_in_backdrop(0.8)
	AccountManager.auth_changed.connect(_on_auth_changed)
	AccountManager.sign_in_failed.connect(_on_sign_in_failed)
	# A first, gentle burst as the page settles — the welcome itself. It fires
	# BEHIND the content (see _celebration_host) so the buttons never make their
	# entrance through a shower of paper.
	await get_tree().create_timer(0.45).timeout
	if is_inside_tree():
		Confetti.celebrate(_celebration_host(), 110)

## This is the root of the boot chain — the splash behind us is gone and nothing
## is stacked — so back means "leave the app", the Android convention Home already
## follows. Swallowing it instead (the old behaviour) left the player's only exit
## from the app's first interactive screen being to sign in.
##
## Mid-prompt the press is simply eaten: a quit dialog stacked under an OS sign-in
## sheet is a trap.
func on_back_request() -> bool:
	if _pending:
		return true
	SceneRouter.request_quit()
	return true

# --- Layout -------------------------------------------------------------------
## The legal/reassurance footer is pinned to the BOTTOM of the page and the hero
## block is centred in what is left. Letting one centred column carry everything
## looked top-heavy: the wordmark's mirrored reflection is drawn outside the
## control's reported height and has to be paid for with a hand-set bottom margin
## (see _lockup), which shoved the whole stack up the screen and left a dead
## quarter-page under the footnote.
func build_content(root: VBoxContainer) -> void:
	root.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_theme_constant_override("separation", int(DesignSystem.SPACE_LG))

	var col := UI.vbox(DesignSystem.SPACE_LG)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Equal expanding spacers above and below: the hero centres itself in the space
	# the footer does not claim, on any screen height.
	root.add_child(UI.spacer())
	root.add_child(UI.constrain_width(col))
	root.add_child(UI.spacer())
	root.add_child(UI.constrain_width(_footer()))

	col.add_child(_lockup())
	col.add_child(_wordmark())
	col.add_child(_tagline())
	col.add_child(UI.spacer(DesignSystem.SPACE_XL, false))
	col.add_child(_buttons())

# --- The 2048 balloon wordmark ------------------------------------------------
## The SAME living balloon logo Home wears (ExtrudedWord): chunky inflated digits
## painted in the board's own candy tile colours, dressed for the active theme,
## squashing and stretching under their own jelly physics. Here it also pops in
## on arrival, sways forever, and reacts when tapped.
func _lockup() -> Control:
	# The SAME letter-board Home wears: T·I·C / T·A·C / T·O·E as nine glass
	# tiles in the board's own ramp. Smaller than Home's: this page carries the
	# mark AND two buttons, so it keeps a margin of air rather than the full measure.
	var width: float = clampf(get_viewport_rect().size.x * 0.56, 280.0, 520.0)
	var word := HeroBoard.make(width)
	word.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# PASS, not STOP: a tap plays with the tiles, but never blocks the page.
	word.mouse_filter = Control.MOUSE_FILTER_PASS
	word.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	word.tile_tapped.connect(func(_i: int): _on_word_tap(word))

	var stage := MarginContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_PASS
	stage.add_child(word)

	# Blow up into place, then breathe: a slow left-right turn, and a delighted
	# "amaze" once it has landed (the same expression Home uses for surprises).
	word.modulate.a = 0.0
	word.scale = Vector2(0.55, 0.55)
	word.resized.connect(func(): word.pivot_offset = word.size * 0.5)
	word.tree_entered.connect(func():
		word.pivot_offset = word.size * 0.5
		var t := word.create_tween().set_parallel(true)
		t.tween_property(word, "modulate:a", 1.0, 0.3).set_delay(0.12)
		t.tween_property(word, "scale", Vector2.ONE, 0.75).set_delay(0.12) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
		var sway := word.create_tween().set_loops()
		sway.tween_interval(0.9)
		sway.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		sway.tween_property(word, "turn", 6.0, 3.4)
		sway.tween_property(word, "turn", -6.0, 3.4)
		await get_tree().create_timer(0.8).timeout
		if is_instance_valid(word):
			word.amaze(2.0))
	return stage

## The tiles are a toy: a tap flips one (the board does that itself) and the
## whole mark bounces with a splash of confetti, fired behind the content (the
## celebration host) so the CTAs stay clear.
func _on_word_tap(word: HeroBoard) -> void:
	if not is_instance_valid(word):
		return
	AudioManager.play_sfx("button_tap", 0.04)
	Haptics.light()
	Confetti.celebrate(_celebration_host(), 50)
	word.dance()

## The board's own candy colours, one per digit, climbing the ramp to 2048 gold —
## so the logo is literally painted in the same material as the tiles.
##
## With one correction: on a BOARD every tile sits on a lit frame, so the ramp's
## deep end reads fine. Here the same colours sit straight on the page, and on the
## dark themes the "4" and the "8" came out near-black on near-black — half the
## hero mark simply disappeared. Each glyph is lifted away from the backdrop until
## it clears MIN_GLYPH_CONTRAST, which leaves the light end untouched (it already
## passes) and only rescues the digits that were vanishing.
func _palette() -> PackedColorArray:
	var bg: Color = ThemeManager.color("bg0")
	var pal := PackedColorArray()
	for v in ExtrudedWord.WORDMARK_TILES:
		pal.append(_legible(CandyFace.color(int(v)), bg))
	return pal

## `c` pushed away from `bg` in luminance until the gap clears the floor.
##
## The lift works in HSV and spends BRIGHTNESS before it spends saturation: the
## digit gets as vivid as its own hue allows, and only a colour that still cannot
## clear the floor at full value — a deep blue, whose luminance ceiling is low
## whatever you do to it — starts washing toward white. Lerping to white directly
## (Color.lightened) was the first cut and it turned the rescued digits grey,
## which fixed the legibility and lost the candy.
##
## Stepped rather than solved because luminance moves non-linearly through HSV;
## the loop is bounded, so even a pathological palette costs a fixed 32 iterations.
func _legible(c: Color, bg: Color) -> Color:
	var dark_bg: bool = bg.get_luminance() < 0.5
	var out := c
	for _i in 32:
		var gap: float = (out.get_luminance() - bg.get_luminance()) * (1.0 if dark_bg else -1.0)
		if gap >= MIN_GLYPH_CONTRAST:
			break
		if dark_bg:
			if out.v < 0.999:
				out = Color.from_hsv(out.h, out.s, minf(out.v + 0.08, 1.0), out.a)
			else:
				out = Color.from_hsv(out.h, maxf(out.s - 0.10, 0.0), 1.0, out.a)
		elif out.v > 0.001:
			out = Color.from_hsv(out.h, out.s, maxf(out.v - 0.08, 0.0), out.a)
		else:
			out = Color.from_hsv(out.h, minf(out.s + 0.10, 1.0), out.v, out.a)
	return out

## Biggest font size whose DRAWN width still fits the screen: the balloon puff
## fattens every digit and buys each one extra air from its neighbour, so the
## word is wider than its raw advance (mirrors Home's fit-to-screen measure).
func _word_size() -> int:
	const WISH := 330
	# brand_font: the wordmark's own face (never themed), so the measure always
	# matches what ExtrudedWord draws.
	var fnt: Font = ThemeManager.brand_font
	if fnt == null:
		fnt = ThemeManager.display_font
	if fnt == null:
		return WISH
	var adv: float = fnt.get_string_size("2048", HORIZONTAL_ALIGNMENT_LEFT, -1, WISH).x
	var gaps: float = 3.0 * (2.0 + float(WISH) * ExtrudedWord.SILHOUETTE_FRAC * 1.5)
	var need: float = (adv + gaps) * 1.03 + float(WISH) * 0.10
	# Tighter than Home's 830: this page carries the word AND two buttons, so the
	# mark keeps a margin of air rather than spanning the full measure.
	const BUDGET := 720.0
	if need > BUDGET:
		return int(float(WISH) * BUDGET / need)
	return WISH

## What the balloons wear for the active theme (mirrors Home's mapping, so the
## logo looks the same on both screens).
func _word_dress() -> String:
	# Festive windows outrank the theme: the calendar dresses the cast first.
	var seasonal := ExtrudedWord.seasonal_dress()
	if seasonal != "":
		return seasonal
	var style := ThemeManager.board_style()
	if style in ["gold", "silver", "desert"]:
		return "crown"
	if style == "jade":
		return "leaf"
	if style == "astral":
		return "star"
	match ThemeManager.bg_motif():
		"leaves":
			return "leaf"
		"bubbles", "deep_sea", "biolum":
			return "bubbles"
		"space", "nebula", "starmap":
			return "star"
		"hearts":
			return "blush"
	return ""

# --- "LIMITLESS" --------------------------------------------------------------
## The word under the lockup, letter-spaced in the display face, with a bar of
## light travelling across it on a loop.
func _wordmark() -> Control:
	# `box` clips (the shine must only ever light the word), which makes a fixed
	# height a silent truncator: at the authored 74pt the word fitted a 400pt-wide
	# phone with nothing to spare, so a wider glyph set — a localised string, a
	# theme shipping a broader display face — would have been quietly guillotined
	# rather than shrunk. Measure first, then size the box to the type.
	var pt := _limitless_size()
	var box := Control.new()
	box.custom_minimum_size = Vector2(0, float(pt) * 1.30)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.clip_contents = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lbl := Label.new()
	lbl.text = "LIMITLESS"
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", pt)
	lbl.add_theme_color_override("font_color", ThemeManager.color("text"))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var spaced := _spaced_display_font(14)
	if spaced != null:
		lbl.add_theme_font_override("font", spaced)
	box.add_child(lbl)

	# (The travelling shine bar that used to sweep this word is GONE, user ask:
	# the crystal wordmark above carries the one moving light on this page, and
	# a second sweep on the tagline read as a duplicated effect.)

	# The word itself arrives a beat after the tiles.
	lbl.modulate.a = 0.0
	lbl.pivot_offset = Vector2(box.size.x * 0.5, float(pt) * 0.65)
	lbl.scale = Vector2(0.92, 0.92)
	lbl.tree_entered.connect(func():
		var t := lbl.create_tween().set_parallel(true)
		t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_property(lbl, "modulate:a", 1.0, 0.5).set_delay(0.52)
		t.tween_property(lbl, "scale", Vector2.ONE, 0.6).set_delay(0.52))
	return box

## The biggest "LIMITLESS" that still fits the measure, letter-spacing included
## (the FontVariation is what's measured, so the spacing is part of the budget).
## Same fit-to-screen idea as _word_size, one line down.
const LIMITLESS_WISH := 74

func _limitless_size() -> int:
	var fnt := _spaced_display_font(14)
	if fnt == null:
		return LIMITLESS_WISH
	# The content frame's own left+right padding, which the label never gets to use.
	var budget: float = maxf(get_viewport_rect().size.x - DesignSystem.SPACE_LG * 4.0, 200.0)
	var w: float = fnt.get_string_size("LIMITLESS", HORIZONTAL_ALIGNMENT_LEFT, -1,
		LIMITLESS_WISH).x
	if w <= budget or w <= 0.0:
		return LIMITLESS_WISH
	return maxi(int(float(LIMITLESS_WISH) * budget / w), 28)

func _tagline() -> Control:
	var l := UI.label("Five ways to slide. One order.", DesignSystem.TYPE_BODY, "text_dim",
		HORIZONTAL_ALIGNMENT_CENTER)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.modulate.a = 0.0
	l.tree_entered.connect(func():
		var t := l.create_tween()
		t.tween_property(l, "modulate:a", 1.0, 0.5).set_delay(0.72) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC))
	return l

# --- The two ways in ----------------------------------------------------------
func _buttons() -> Control:
	var box := UI.vbox(DesignSystem.SPACE_MD)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The pair sits on its own narrower measure; the status line below keeps the full
	# width, since it is a wrapping sentence and not part of the pair.
	var pair := UI.vbox(DesignSystem.SPACE_MD)
	pair.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(UI.constrain_width(pair, CTA_MEASURE))

	_play = PremiumButton.make(PLAY_LABEL, PremiumButton.Variant.PRIMARY)
	_play.full_width = true
	_play.corner_radius = CTA_RADIUS
	# The gamepad mark rides at the left edge, like a real store button. This is our
	# OWN icon deliberately — Google's marks may not be recoloured or reproduced, so
	# the button names Play Games in words and wears the app's own iconography.
	_play.icon = UI.icon_tex("games_played")
	_play.expand_icon = true
	_play.add_theme_constant_override("h_separation", 20)
	_play.pressed.connect(_on_play)
	_play.add_theme_stylebox_override("disabled", _inert_box(ThemeManager.color("accent")))

	pair.add_child(_play)
	_dress_cta(_play, CTA_HEIGHT)
	_rise_in(_play, 0.86)

	_guest = PremiumButton.make("Continue as Guest", PremiumButton.Variant.GLASS)
	_guest.full_width = true
	_guest.corner_radius = CTA_RADIUS
	_guest.pressed.connect(_continue)
	_guest.add_theme_stylebox_override("disabled", _inert_box(ThemeManager.color("glass")))

	pair.add_child(_guest)
	_dress_cta(_guest, CTA_HEIGHT)
	_rise_in(_guest, 0.96)

	# The one line that reports back: why the Play button is off, that a prompt is
	# running, or why it failed. Hidden (and claiming no height) when there is
	# nothing to say, so the resting page is unchanged.
	_status = UI.caption("", "text_dim")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.visible = false
	box.add_child(_status)

	_apply_availability()
	return box

## Whether this build can sign anyone in at all. On the editor, on desktop, and on
## an Android build shipped without the PGS plugin there is no provider behind the
## button — offering a prompt that can never appear reads as a broken app, so the
## button is disabled up front and the page says why.
func _apply_availability() -> void:
	if AccountManager.is_configured():
		_breathe(_play)      # a live CTA quietly asking to be pressed
		return
	_play.disabled = true
	_say("Play Games isn't available on this device. Continue as a guest.", "text_dim")

## A disabled Button draws its "disabled" stylebox, and PremiumButton overrides
## every state EXCEPT that one — so a disabled CTA fell back to the runtime theme's
## default and read as loose text floating on the page rather than a button that
## happens to be off. Both buttons get an inert box up front, since either can be
## disabled (the gate below, or a prompt in flight).
## An inert CTA still has to be READ — "Signing in…" and the gated Play label are
## both drawn in this state. PremiumButton leaves font_disabled_color at
## `text_faint`, which is tuned for a disabled row on the page background, not for
## white-ish text over a tinted box; on light themes the label all but vanished.
func _inert_text() -> Color:
	return ThemeManager.color("text_dim")

func _inert_box(fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(fill.r, fill.g, fill.b, fill.a * 0.35)
	sb.set_corner_radius_all(int(CTA_RADIUS))
	sb.border_width_bottom = 2
	sb.border_color = Color(fill.r, fill.g, fill.b, fill.a * 0.45)
	return sb

## Everything about a hero CTA that has to be applied AFTER PremiumButton._ready().
##
## That method pins custom_minimum_size.y to the standard 64, and _restyle() stamps
## its own font size and disabled ink over anything the screen set at build time —
## so a button dressed during build silently comes out standard-sized with the
## page's faintest ink. Only the disabled STYLEBOX survives, because _restyle is the
## one state it does not override. (Restyle re-fires on a theme change too, but the
## screen rebuilds its whole content tree then, so this runs again with it.)
func _dress_cta(b: PremiumButton, h: float) -> void:
	b.ready.connect(func():
		b.custom_minimum_size.y = h
		b.add_theme_font_size_override("font_size", DesignSystem.TYPE_HEADLINE)
		b.add_theme_color_override("font_disabled_color", _inert_text()))

# --- Sign in ------------------------------------------------------------------
## The real thing: hand off to the identity facade and hold the page until it
## answers. AccountManager only raises sign_in_failed for MANUAL attempts (the
## automatic launch prompt stays silent), which is exactly this call — so the two
## outcomes below are the complete set, plus the timeout for a prompt that never
## returns at all.
func _on_play() -> void:
	if _leaving or _pending or SceneRouter.is_busy() or not AccountManager.is_configured():
		return
	if AccountManager.is_signed_in():
		_continue()
		return
	_attempt += 1
	var id := _attempt
	_set_pending(true)
	Haptics.light()
	AccountManager.sign_in()
	# The prompt is an OS surface: a player who swipes it away hands us no signal,
	# so the page has to time itself out or it waits forever.
	await _beat(SIGN_IN_TIMEOUT)
	if is_inside_tree() and _pending and id == _attempt:
		_fail("That took too long. Check your connection and try again.")

## Success arrives as the facade's auth_changed. It also fires for the automatic
## launch prompt and for a sign-out elsewhere, so it only carries the player
## onward when THIS screen is the one waiting.
func _on_auth_changed() -> void:
	if _pending and AccountManager.is_signed_in():
		_set_pending(false)
		_continue()

func _on_sign_in_failed() -> void:
	if _pending:
		_fail("Couldn't sign in. Check your connection and try again.")

func _fail(message: String) -> void:
	_attempt += 1                  # retire the in-flight attempt's timeout
	_set_pending(false)
	_say(message, "danger")
	Haptics.light()

## The waiting state: both buttons go inert (a guest tap mid-prompt would race the
## sign-in result to the router) and the primary says what it is doing.
func _set_pending(on: bool) -> void:
	_pending = on
	# Coming OUT of a prompt restores the AVAILABILITY state, not simply "enabled" —
	# on a build with no provider the primary was disabled before the prompt and has
	# to stay that way after it.
	_play.disabled = on or not AccountManager.is_configured()
	_guest.disabled = on
	_play.text = "Signing in…" if on else PLAY_LABEL
	if on:
		_say("Continuing in the Play Games window…", "text_dim")

func _say(message: String, color_key: String) -> void:
	if _status == null:
		return
	_status.text = message
	_status.visible = not message.is_empty()
	_status.add_theme_color_override("font_color", ThemeManager.color(color_key))

# --- Footer -------------------------------------------------------------------
## Pinned to the bottom of the page: the reassurance line and the data disclosure
## Play requires to be reachable. It was previously `text_faint` — on this backdrop
## that rendered as barely-there grey on the one line carrying the page's whole
## promise, so it now sits at `text_dim`.
func _footer() -> Control:
	var box := UI.vbox(DesignSystem.SPACE_XS)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var l := UI.caption("You can change this later in Settings.",
		"text_dim")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(l)

	var privacy := PremiumButton.make("Privacy & data", PremiumButton.Variant.GHOST)
	privacy.add_theme_font_size_override("font_size", DesignSystem.TYPE_CAPTION)
	privacy.pressed.connect(_privacy_modal)
	box.add_child(privacy)

	box.modulate.a = 0.0
	box.tree_entered.connect(func():
		var t := box.create_tween()
		t.tween_property(box, "modulate:a", 1.0, 0.5).set_delay(1.08) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC))
	return box

## The same disclosure Settings carries (settings.gd _privacy_modal), reachable
## BEFORE the player commits to anything — which is the point of putting it here.
## Read-only: deleting data is a Settings action, and there is nothing yet to
## delete at this point in the app anyway.
func _privacy_modal() -> void:
	var m := ModalOverlay.new()
	m.set_header("Data & Privacy", "Your data, on your device",
		"Your stats, achievements, best scores, settings and games in progress are stored on this device only.\n\nSigning in with Play Games shares a gamer tag and your leaderboard scores with your Google account; playing as a guest shares nothing.\n\nYou can change this, and erase everything on this device, from Settings at any time.")
	m.add_action("Close", PremiumButton.Variant.GLASS, func(): m.close())
	m.open(self)

## Into the game: celebrate, then Home. Reached two ways — the guest button
## directly, and a successful Play Games sign-in through _on_auth_changed — so
## everything AFTER the choice lives here exactly once.
##
## A tap can land while the router is still revealing THIS screen, and goto()
## drops requests while busy — so latching `_leaving` before the router can take
## us would strand the player here for good. The splash has the same guard, but
## it also has a timeline that retries; this screen has only the button, so a
## dropped request is permanent. Refusing the tap while busy costs nothing: the
## buttons are still live and the next tap works.
func _continue() -> void:
	if _leaving or SceneRouter.is_busy():
		return
	_leaving = true
	Haptics.success()
	# The finale fires on the screen itself, over the content — unlike the arrival
	# burst, there is nothing left here to obscure.
	Confetti.celebrate(self, 260, true)
	AudioManager.play_sfx("achievement")
	# Let the burst read for a beat before the curtain takes the screen. The beat
	# is node-bound (see _beat) so it cannot resume into a freed instance.
	await _beat(0.5)
	if is_inside_tree():
		SceneRouter.goto(SceneRouter.Route["HOME"])

## A pause that DIES WITH THIS NODE. `get_tree().create_timer()` is owned by the
## SceneTree and goes on ticking after this screen is freed, resuming the caller
## into a dead instance ("Resumed function after yield, but class instance is
## gone" — a plain ERROR the regression gate does watch for). A tween created on
## this node is killed with it, so `finished` simply never fires and the
## coroutine is abandoned cleanly. Same idiom as the splash's _hold().
func _beat(sec: float) -> void:
	var tw := create_tween()
	tw.tween_interval(sec)
	await tw.finished

# --- Celebration layer --------------------------------------------------------
## Where the ARRIVAL confetti is fired. Parented just below the content frame, so
## the burst plays behind the wordmark and the buttons instead of raining across
## the two call-to-actions during the exact seconds they are animating in.
## (`content.get_parent()` is AppScreen's frame — the base class owns it, and its
## index is the boundary between backdrop and UI.)
func _celebration_host() -> Control:
	if is_instance_valid(_fx_host):
		return _fx_host
	_fx_host = Control.new()
	_fx_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_host)
	move_child(_fx_host, (content.get_parent() as Control).get_index())
	return _fx_host

# --- Backdrop -----------------------------------------------------------------
## Everything behind the content: the glow the wordmark floats on, twinkling
## sparkles around it, and dim brand tiles drifting up the screen.
##
## Added as a sibling BELOW the frost snapshot (AppScreen's own idiom) so it sits
## over the gradient but under the content; a negative z_index would vanish
## beneath the screen's opaque background instead.
func _build_backdrop() -> void:
	var back := Control.new()
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place_in_backdrop(back)
	# This layer is the page's own decoration, not the base screen's, so it is not in
	# fade_in_backdrop's list — it rides the same reveal by hand.
	back.modulate.a = 0.0
	var reveal := back.create_tween()
	reveal.tween_property(back, "modulate:a", 1.0, 0.8) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	var vp0 := get_viewport_rect().size
	# The aura the balloons float on — a wide accent bloom centred on the mark.
	var aura := TextureRect.new()
	aura.texture = _soft_radial()
	aura.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	aura.stretch_mode = TextureRect.STRETCH_SCALE
	aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var aw := maxf(vp0.x, 1.0) * 1.5
	var ah := aw * 0.72
	aura.size = Vector2(aw, ah)
	aura.position = Vector2(vp0.x * 0.5 - aw * 0.5, vp0.y * 0.36 - ah * 0.5)
	var ac: Color = ThemeManager.color("accent")
	aura.modulate = Color(ac.r, ac.g, ac.b, 0.18)
	back.add_child(aura)

	aura.tree_entered.connect(func():
		var t := aura.create_tween().set_loops()
		t.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		t.tween_property(aura, "modulate:a", 0.28, 2.1)
		t.tween_property(aura, "modulate:a", 0.12, 2.3))
	_add_sparkles(back, 10, 0.20, 0.52)
	_add_drifting_tiles(back)

## Dim brand tiles floating up behind everything — the page's ambient motion.
func _add_drifting_tiles(field: Control) -> void:
	var vp := get_viewport_rect().size
	var pairs := [[C_VIOLET, C_INDIGO], [C_BLUE, C_SKY], [C_PINK, C_MAGENTA], [C_ORANGE, C_AMBER]]
	for i in 9:
		var pair: Array = pairs[i % 4]
		var sz := randf_range(46.0, 118.0)
		var tile := GradientPanel.make(pair[0] as Color, pair[1] as Color, sz * 0.15, Vector2(1, 1))
		tile.candy = 1.0
		tile.size = Vector2(sz, sz)
		tile.pivot_offset = Vector2(sz, sz) * 0.5
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.modulate.a = randf_range(0.10, 0.22)
		var x := randf_range(0.0, maxf(vp.x - sz, 1.0))
		tile.position = Vector2(x, vp.y + randf_range(0.0, vp.y))
		tile.rotation = randf_range(-0.5, 0.5)
		field.add_child(tile)

		var dur := randf_range(11.0, 20.0)
		var spin := randf_range(-0.6, 0.6)
		tile.tree_entered.connect(func():
			var t := tile.create_tween().set_loops()
			t.tween_property(tile, "position:y", -sz * 1.5, dur).from(vp.y + sz * 0.5)
			var r := tile.create_tween().set_loops()
			r.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			r.tween_property(tile, "rotation", spin, dur * 0.5)
			r.tween_property(tile, "rotation", -spin, dur * 0.5))

# --- Small helpers ------------------------------------------------------------
## A copy of the display font with generous letter spacing (null when the theme
## ships no display face, in which case the label keeps the default).
func _spaced_display_font(spacing: int) -> Font:
	if ThemeManager.display_font == null:
		return null
	var fv := FontVariation.new()
	fv.base_font = ThemeManager.display_font
	fv.spacing_glyph = spacing
	return fv

## A soft white radial (opaque centre → transparent edge) for glows and auras.
func _soft_radial() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t

## Twinkling dots scattered across a horizontal band of `parent` (fractions of
## its height) — the sparkle around the balloons.
func _add_sparkles(parent: Control, count: int, y_lo: float, y_hi: float) -> void:
	var vp := get_viewport_rect().size
	for i in count:
		var dot := TextureRect.new()
		dot.texture = CandyFace.glow_dot()
		dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		dot.stretch_mode = TextureRect.STRETCH_SCALE
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sz := randf_range(10.0, 26.0)
		dot.size = Vector2(sz, sz)
		dot.modulate = Color(1, 1, 1, 0.0)
		parent.add_child(dot)
		# The backdrop layer is anchored to the whole screen, so the viewport gives
		# the band its real coordinates without waiting on a layout pass.
		dot.position = Vector2(vp.x * randf_range(0.06, 0.94),
			vp.y * randf_range(y_lo, y_hi)) - dot.size * 0.5
		var delay := randf_range(0.6, 3.4)
		var up := randf_range(0.5, 0.9)
		var down := randf_range(0.7, 1.3)
		dot.tree_entered.connect(func():
			var t := dot.create_tween().set_loops()
			t.tween_interval(delay)
			t.tween_property(dot, "modulate:a", 0.95, up).set_trans(Tween.TRANS_SINE)
			t.tween_property(dot, "modulate:a", 0.0, down).set_trans(Tween.TRANS_SINE)
			t.tween_interval(randf_range(0.8, 2.4)))

## Fade + rise a control into place after `delay` seconds. SCALE, never position:
## for a container child `position` IS the layout slot, so animating it drops the
## control onto its sibling (a bottom-anchored pivot makes the scale read as a
## rise anyway — the same trick AppScreen.stagger_in uses).
func _rise_in(c: Control, delay: float) -> void:
	c.modulate.a = 0.0
	c.scale = Vector2(0.94, 0.86)
	c.tree_entered.connect(func():
		c.pivot_offset = Vector2(c.size.x * 0.5, c.size.y)
		var t := c.create_tween().set_parallel(true)
		t.tween_property(c, "modulate:a", 1.0, 0.45).set_delay(delay) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_property(c, "scale", Vector2.ONE, 0.6).set_delay(delay) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK))

## A slow scale pulse — the primary button quietly asking to be pressed.
func _breathe(c: Control) -> void:
	c.tree_entered.connect(func():
		c.pivot_offset = c.size * 0.5
		var t := c.create_tween().set_loops()
		t.tween_interval(1.5)
		t.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		t.tween_property(c, "scale", Vector2(1.025, 1.025), 1.1)
		t.tween_property(c, "scale", Vector2.ONE, 1.1))
