extends AppScreen
## Premium — the "Go Premium" paywall and the home of premium status.
##
## Lists what the one-time lifetime unlock includes and drives the purchase /
## restore flow through Google Play Billing (BillingService). Ownership is keyed
## to the device's Google Play account — buying needs no app sign-in, and the
## purchase restores on any device with that account. Where the store plugin is
## absent (editor/desktop), a DEBUG build can simulate the unlock so the whole
## premium experience is testable end to end. Premium is a one-time purchase,
## NOT a subscription. The screen rebuilds itself when ownership changes.
##
## THE HERO SHOWS THE GOODS. This page's second-biggest promise is "all 52
## themes" and for a long time it made that promise entirely in small type, on
## the flattest card in the app, while fifty-two finished, animated palettes sat
## one screen away. The hero now cycles the PREMIUM-tier palettes behind the
## lockup — the same live `ThemePreview` ambience the Themes screen and the Shop
## hero use, crossfading between two layers so one palette dissolves into the
## next instead of cutting. A paywall selling a look should be showing the look.
##
## The carousel is AMBIENT, not an entrance: it is started by `_hero` and its
## clock is parented to the stage, so it is rebuilt along with the page by the
## several signals that rebuild it, rather than dying on the first ownership or
## theme change the way an `on_ready` timer would.

## The hero stage's height, in design points — tall enough for the ambience to
## read as a place rather than as a strip of texture behind the crown.
const HERO_ART_H := 420.0
## How long each palette holds, and how long it takes to dissolve into the next.
const CAROUSEL_HOLD := 3.2
const CAROUSEL_FADE := 1.1
## How dark the scrim over the ambience sits. The lockup is light-on-whatever, and
## "whatever" here includes the light palettes — without this the title drops
## under the legibility floor on a good part of the rotation.
const HERO_SCRIM_ALPHA := 0.52

const BENEFITS := [
	{
		"icon": "res://assets/icons/mode_classic.png",
		"title": "Every game mode",
		"desc": "Quantum, Cube, Orbit, Arena, and every mode added later.",
	},
	{
		"icon": "res://assets/icons/tab_visual.png",
		# Keep this number honest against data/themes/theme_ids.gd — a store-facing
		# claim the build must actually meet. flow_ui_buttons.gd pins the match.
		"title": "All 61 themes",
		"desc": "Including the metallic, crystal and snowing boards.",
	},
	{
		"icon": "res://assets/icons/restart.png",
		"title": "Unlimited undo",
		"desc": "Take back as many moves as you like.",
	},
	{
		"icon": "res://assets/icons/star.png",
		"title": "No ads",
		"desc": "No interruptions between games.",
	},
]

var _unlock_btn: PremiumButton
var _restore_btn: PremiumButton
var _diag_status: Label
var _diag_log: Label

## The hero carousel's two ambience layers and where it is in the rotation.
## Rebuilt with the page; never held across a rebuild.
##
## `_stage_hi` sits ON TOP of `_stage_lo` in tree order and STAYS there — the
## crossfade is done entirely by fading `_stage_hi` in and out over its partner,
## alternating which layer receives the next palette. Swapping the two by
## z-order instead means reordering children of a stage that also carries the
## scrim, and the scrim only has to be pushed under the art once to ruin the
## legibility the whole arrangement exists to protect.
var _stage_lo: ThemePreview
var _stage_hi: ThemePreview
## Whether the top layer is currently the one being seen.
var _hi_shown := true
var _carousel_ids: Array[String] = []
var _carousel_i := 0
## The caption naming the palette on stage.
var _stage_name: Label
## The benefit rows, for the entrance cascade.
var _cards: Array[Control] = []
## True once this page has watched ownership flip, so the celebration fires on
## the PURCHASE rather than on every later visit to an owned page.
var _celebrated := false

func on_ready() -> void:
	EntitlementManager.premium_changed.connect(_on_premium_changed)
	# Billing results + a late-arriving localized price refresh the screen.
	BillingService.purchase_succeeded.connect(_on_purchase_succeeded)
	BillingService.purchase_failed.connect(_on_purchase_failed)
	BillingService.purchase_pending.connect(_on_purchase_pending)
	BillingService.purchases_restored.connect(_on_purchases_restored)
	BillingService.price_changed.connect(func(_p: String): _rebuild())
	# Sign-in state changes the account card; manual sign-in failures surface a
	# toast (PGS reports no failure reason, so the copy stays generic).
	AccountManager.auth_changed.connect(func(): _rebuild())
	AccountManager.sign_in_failed.connect(_on_sign_in_failed)
	# The Play Games gamer tag lands AFTER the session does, so refresh when it
	# arrives or the account card would keep showing the placeholder.
	AccountManager.profile_changed.connect(func(): _rebuild())
	# Debug billing card: patch the two labels in place rather than rebuilding the
	# whole screen on every plugin event.
	BillingService.diagnostics_changed.connect(_on_diagnostics_changed)
	# The page owns its entrance: the base class fades the content block as one,
	# which would run underneath the per-card cascade as a second fade of the same
	# pixels.
	custom_entrance = true
	content.modulate.a = 0.0
	await get_tree().process_frame
	if not is_inside_tree():
		return
	content.modulate.a = 1.0
	UI.stagger_in(_cards)

func _on_premium_changed(is_premium: bool) -> void:
	# THE PURCHASE ITSELF, celebrated once. `_rebuild` runs on half a dozen
	# signals and this screen is also where an owner lands to check their status,
	# so the burst is tied to ownership FLIPPING while the page is open — not to
	# the page being open and owned, which would fire on every visit forever.
	if is_premium and not _celebrated:
		_celebrated = true
		Haptics.medium()
		AudioManager.play_sfx("victory")
		if not bool(SettingsManager.get_value("reduce_motion")):
			# Parented to `self`: `_rebuild` frees the whole content tree on the
			# very next line and would take the burst with it.
			Confetti.celebrate(self, 200, true)
	_rebuild()

## Rebuild the content tree (used when ownership flips). Mirrors AppScreen's
## theme-change rebuild so the screen always reflects the current entitlement.
func _rebuild() -> void:
	for c in content.get_children():
		c.queue_free()
	build_content(content)

func build_content(root: VBoxContainer) -> void:
	# Cleared, not appended to: a rebuild frees every node these point at, and
	# this page rebuilds on ownership, billing, price, auth and theme changes.
	_cards.clear()
	_stage_lo = null
	_stage_hi = null
	_stage_name = null

	root.add_child(nav_header("Premium"))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.clip_contents = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	SmoothWheel.attach(scroll)   # desktop wheel glides instead of stepping
	root.add_child(scroll)

	var col := UI.vbox(DesignSystem.SPACE_LG)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	# The hero is NOT in the cascade: it carries the live ambience and the lockup,
	# and a card that big fading in behind the ones after it reads as the page
	# loading rather than as an entrance. It arrives with the screen; the sales
	# argument below it cascades in underneath.
	col.add_child(_hero())

	for section in _page_sections():
		col.add_child(section)
		_cards.append(section)

	col.add_child(UI.spacer(DesignSystem.SPACE_LG, false))

## Everything under the hero, in order, so the cascade and the page agree by
## construction rather than by two lists being kept in step.
func _page_sections() -> Array[Control]:
	var out: Array[Control] = []
	out.append(_benefits_card())

	if EntitlementManager.is_premium():
		out.append(_owned_banner())
	else:
		out.append(_cta())

	# Play Games account — only where an identity provider exists (Android builds).
	if AccountManager.is_configured():
		out.append(_account_card())

	if EntitlementManager.debug_unlock_enabled():
		out.append(_debug_card())

	# Billing diagnostics — debug builds only (compiled out of release). Shown even
	# when the plugin is absent: "plugin ABSENT" is itself the finding.
	if OS.is_debug_build():
		out.append(_billing_debug_card())
	return out

# --- Sections -----------------------------------------------------------------
func _hero() -> Control:
	var card := UI.glass_card(3)
	# The lockup and the stage are SIBLINGS in a PanelContainer, which lays every
	# child out at the same rect — so the column floats over the ambience without
	# either one having to know the other's size. The stage carries the height.
	card.content_margin = 0.0
	_build_hero_stage(card)

	var col := UI.vbox(DesignSystem.SPACE_SM)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	# The card gave up its own content margin to let the art bleed to the rim, so
	# the text block brings its own.
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, int(DesignSystem.SPACE_LG))
	pad.add_child(col)
	card.add_child(pad)

	var crown := UI.icon_rect("best_score", 120, "")
	crown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(crown)
	_idle_turn(crown)

	var title := UI.label("NUMSLIDE Limitless Premium", DesignSystem.TYPE_TITLE, "text", HORIZONTAL_ALIGNMENT_CENTER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if ThemeManager.display_font:
		title.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(title)

	var sub := UI.body("One unlock. Every mode and every theme, for good.", "text_dim")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	# NAME WHAT IS ON SCREEN. The ambience behind this card is a real, purchasable
	# theme, and an unnamed one is just a nice background — the label is what turns
	# the rotation from decoration into a catalogue the reader is being shown.
	if not _carousel_ids.is_empty():
		col.add_child(UI.spacer(DesignSystem.SPACE_SM, false))
		var now := UI.caption("", "text_dim")
		now.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		now.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(now)
		_stage_name = now
		_paint_stage_name()

	return card

## The hero's live backdrop: two ambience layers that crossfade through the
## premium palettes, under a scrim in the app's own backdrop colour.
##
## The scrim takes its colour from the ACTIVE theme rather than being a flat
## black wash, which is what keeps the lockup readable in both directions: the
## rotation runs through light palettes and dark ones, and the title on top is
## painted in the current theme's own text colour. A fixed dark scrim would read
## beautifully on a dark theme and hide the title on a light one.
func _build_hero_stage(card: Control) -> void:
	_carousel_ids = _premium_theme_ids()
	if _carousel_ids.is_empty():
		return
	_carousel_i = 0

	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, HERO_ART_H)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(stage)

	# Added low-then-high, and never reordered after this.
	var first := ThemeManager.palette_for(_carousel_ids[0])
	_stage_lo = _ambience_layer(stage, first)
	_stage_hi = _ambience_layer(stage, first)
	_hi_shown = true

	var scrim := ColorRect.new()
	scrim.color = _scrim_color()
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UI.round_clip(scrim, DesignSystem.RADIUS_LG)
	stage.add_child(scrim)

	# reduce_motion holds ONE palette: the ambience itself is already still (see
	# ThemePreview), and a crossfade every few seconds is exactly the kind of
	# unprompted movement the setting exists to switch off.
	if bool(SettingsManager.get_value("reduce_motion")) or _carousel_ids.size() < 2:
		return
	# The clock is parented to the STAGE so it dies with the page it drives — this
	# screen rebuilds on ownership, billing, auth and theme changes, and a timer
	# on `self` would survive every one of them and stack up.
	var clock := Timer.new()
	clock.wait_time = CAROUSEL_HOLD
	clock.autostart = true
	clock.timeout.connect(_advance_carousel)
	stage.add_child(clock)

## One ambience layer, round-clipped to the card's radius so a square-cornered
## rectangle of art never cuts across the curve.
func _ambience_layer(stage: Control, pal: Dictionary) -> ThemePreview:
	var layer := ThemePreview.new()
	layer.setup(pal)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UI.round_clip(layer, DesignSystem.RADIUS_LG)
	stage.add_child(layer)
	return layer

func _scrim_color() -> Color:
	var c: Color = ThemeManager.color("bg0")
	c.a = HERO_SCRIM_ALPHA
	return c

## Dissolve to the next premium palette.
##
## Only the TOP layer ever animates, and which layer receives the incoming
## palette alternates with it: while the top is showing, the next palette is
## loaded underneath and the top fades away to reveal it; while the bottom is
## showing, the next palette is loaded into the (invisible) top and it fades back
## in to cover. Two directions of one tween, no z-order changes, and the scrim
## keeps its place above both for good.
func _advance_carousel() -> void:
	if _carousel_ids.size() < 2 \
			or not is_instance_valid(_stage_lo) or not is_instance_valid(_stage_hi):
		return
	_carousel_i = (_carousel_i + 1) % _carousel_ids.size()
	var pal := ThemeManager.palette_for(_carousel_ids[_carousel_i])
	var target := 0.0
	if _hi_shown:
		_stage_lo.setup(pal)      # revealed as the top fades off it
	else:
		_stage_hi.setup(pal)      # faded back over the bottom
		target = 1.0
	_hi_shown = not _hi_shown
	var tw := _stage_hi.create_tween()
	tw.tween_property(_stage_hi, "modulate:a", target, CAROUSEL_FADE) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_paint_stage_name()

## The name of the palette currently on stage.
func _paint_stage_name() -> void:
	if not is_instance_valid(_stage_name) or _carousel_ids.is_empty():
		return
	_stage_name.text = "Now showing · %s" % ThemeManager.theme_name(_carousel_ids[_carousel_i])

## The premium-tier themes, which are exactly what this page unlocks. Read from
## the entitlement rule rather than from a list kept here, so a theme moving
## tiers can never leave the paywall advertising something it no longer sells.
func _premium_theme_ids() -> Array[String]:
	var out: Array[String] = []
	for id_v: Variant in ThemeManager.all_theme_ids():
		var id := String(id_v)
		if Entitlements.theme_requires_premium(id):
			out.append(id)
	return out

## A slow, gentle rock — the crown catching the light rather than sitting still.
func _idle_turn(node: Control) -> void:
	if bool(SettingsManager.get_value("reduce_motion")):
		return
	node.pivot_offset = node.custom_minimum_size * 0.5
	var tw := node.create_tween().set_loops()
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "rotation", deg_to_rad(4.0), 2.6)
	tw.tween_property(node, "rotation", deg_to_rad(-4.0), 2.6)

func _benefits_card() -> Control:
	var card := UI.glass_card(2)
	var col := UI.vbox(DesignSystem.SPACE_MD)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for b_raw in BENEFITS:
		var b: Dictionary = b_raw
		col.add_child(_benefit_row(b))
	card.add_child(col)
	return card

func _benefit_row(b: Dictionary) -> Control:
	var row := UI.hbox(DesignSystem.SPACE_MD)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var icon := UI.icon_rect(String(b.get("icon", "")), 56, "accent")
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var texts := UI.vbox(DesignSystem.SPACE_XS)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := UI.label(String(b.get("title", "")), DesignSystem.TYPE_HEADLINE, "text")
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	texts.add_child(t)
	texts.add_child(UI.body(String(b.get("desc", "")), "text_dim"))
	row.add_child(texts)
	return row

func _cta() -> Control:
	var box := UI.vbox(DesignSystem.SPACE_MD)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var unlock := PremiumButton.make("Unlock Premium · %s" % BillingService.display_price(), PremiumButton.Variant.PRIMARY)
	unlock.full_width = true
	unlock.add_theme_font_size_override("font_size", DesignSystem.TYPE_HEADLINE)
	unlock.pressed.connect(_on_unlock_pressed)
	box.add_child(unlock)
	_unlock_btn = unlock

	var restore := PremiumButton.make("Restore Purchase", PremiumButton.Variant.GHOST)
	restore.full_width = true
	restore.pressed.connect(_on_restore_pressed)
	box.add_child(restore)
	_restore_btn = restore

	var note := UI.caption("One-time purchase. It follows your Google Play account to any device.", "text_faint")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	return box

func _owned_banner() -> Control:
	var card := UI.glass_card(2)
	var col := UI.vbox(DesignSystem.SPACE_XS)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := UI.label("✓  You're Premium", DesignSystem.TYPE_HEADLINE, "accent", HORIZONTAL_ALIGNMENT_CENTER)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(t)
	var msg := UI.body("Everything's unlocked. Thanks for supporting the game.", "text_dim")
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(msg)
	card.add_child(col)
	return card

# --- Account (Play Games) -----------------------------------------------------
## What to call the signed-in player. The PGS gamer tag lands AFTER the session
## does, so fall back rather than rendering a blank "Signed in as ".
func _account_label() -> String:
	var tag := AccountManager.display_name()
	return tag if not tag.is_empty() else "Play Games account"

func _account_card() -> Control:
	var card := UI.glass_card(1)
	var col := UI.vbox(DesignSystem.SPACE_SM)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if AccountManager.is_signed_in():
		col.add_child(UI.body("Signed in as %s" % _account_label(), "text"))
		var body_text := "Purchases are tied to your Google Play account and restore on any device."
		if EntitlementManager.is_premium():
			body_text = "Premium sits with your Google Play account, so it restores on any device."
		col.add_child(UI.caption(body_text, "text_faint"))
	else:
		col.add_child(UI.body("Play with your Google Play Games profile.", "text"))
		var btn := PremiumButton.make("Sign in with Play Games", PremiumButton.Variant.GLASS)
		btn.full_width = true
		btn.pressed.connect(func(): AccountManager.sign_in())
		col.add_child(btn)
	card.add_child(col)
	return card

func _on_sign_in_failed() -> void:
	_toast("Sign-in unavailable", "Play Games sign-in isn't available right now.")

# --- Debug-only controls ------------------------------------------------------
func _debug_card() -> Control:
	var card := UI.glass_card(1)
	var col := UI.vbox(DesignSystem.SPACE_SM)
	col.add_child(UI.caption("DEBUG — debug builds only", "text_faint"))
	col.add_child(UI.body("Status: %s" % ("PREMIUM" if EntitlementManager.is_premium() else "FREE"), "text_dim"))
	var toggle := PremiumButton.make("Toggle Premium (simulate)", PremiumButton.Variant.GLASS)
	toggle.full_width = true
	toggle.pressed.connect(func(): EntitlementManager.debug_toggle_premium())
	col.add_child(toggle)
	card.add_child(col)
	return card

# --- Billing diagnostics (debug builds only) ----------------------------------
## An on-device readout of what the native Play Billing plugin is actually doing.
## The adapter's signal names, arities and payload shapes were derived from the
## DECOMPILED plugin AAR — this card is how we confirm they're right on a real
## device without needing a Play merchant account or a live product.
func _billing_debug_card() -> Control:
	var card := UI.glass_card(1)
	var col := UI.vbox(DesignSystem.SPACE_SM)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	col.add_child(UI.caption("BILLING DIAGNOSTICS — debug builds only", "text_faint"))

	var status := UI.body(_diag_status_text(), "text")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(status)
	_diag_status = status

	var row := UI.hbox(DesignSystem.SPACE_SM)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var q_products := PremiumButton.make("Query products", PremiumButton.Variant.GLASS)
	q_products.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q_products.pressed.connect(func(): BillingService.query_products())
	row.add_child(q_products)
	var q_purchases := PremiumButton.make("Query purchases", PremiumButton.Variant.GLASS)
	q_purchases.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q_purchases.pressed.connect(func(): BillingService.restore())
	row.add_child(q_purchases)
	col.add_child(row)

	var log_label := UI.caption(_diag_log_text(), "text_dim")
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(log_label)
	_diag_log = log_label

	card.add_child(col)
	return card

func _diag_status_text() -> String:
	return "Plugin: %s   ·   Store: %s   ·   Price: %s" % [
		"FOUND" if BillingService.is_available() else "ABSENT",
		"CONNECTED" if BillingService.is_store_connected() else "not connected",
		BillingService.display_price(),
	]

func _diag_log_text() -> String:
	var lines := BillingService.diagnostics_log()
	if lines.is_empty():
		return "(no plugin events yet)"
	return "\n".join(lines)

## Patch the labels in place — a full _rebuild() on every plugin event would tear
## down the buttons mid-tap.
func _on_diagnostics_changed() -> void:
	if _diag_status != null and is_instance_valid(_diag_status):
		_diag_status.text = _diag_status_text()
	if _diag_log != null and is_instance_valid(_diag_log):
		_diag_log.text = _diag_log_text()

# --- Actions ------------------------------------------------------------------
## Disables the purchase/restore buttons and shows a "Processing…" label while a
## real billing call is in flight, so it can't be double-tapped. Cleared when the
## billing signals return (success / failure / cancel / restore).
func _set_purchase_busy(on: bool) -> void:
	if _unlock_btn != null and is_instance_valid(_unlock_btn):
		_unlock_btn.disabled = on
		_unlock_btn.text = "Processing…" if on else "Unlock Premium · %s" % BillingService.display_price()
	if _restore_btn != null and is_instance_valid(_restore_btn):
		_restore_btn.disabled = on

func _on_unlock_pressed() -> void:
	# Purchase needs no app sign-in — Play Billing keys ownership to the device's
	# Google Play account.
	if BillingService.is_available():
		# Real Play Billing purchase. The result returns via the billing signals
		# (success / failure / cancel) connected in on_ready().
		_set_purchase_busy(true)
		BillingService.purchase()
		return
	if EntitlementManager.debug_unlock_enabled():
		# Off-device dev build: simulate a verified purchase so the flow is testable.
		EntitlementManager.grant_premium("debug")
		_toast("Premium unlocked", "Enjoy every mode, theme and unlimited undo.")
		return
	_toast("Unavailable", "In-app purchase needs the Google Play build of the game.")

func _on_restore_pressed() -> void:
	if BillingService.is_available():
		_set_purchase_busy(true)
		BillingService.restore()
		return
	_toast("Restore", "Restoring needs the Google Play build of the game.")

func _on_purchase_succeeded() -> void:
	_set_purchase_busy(false)
	# premium_changed already rebuilt the screen to the owned state; confirm it.
	_toast("Premium unlocked", "Every mode, every theme and unlimited undo are yours.")

func _on_purchase_failed(reason: String) -> void:
	_set_purchase_busy(false)
	if reason == "cancelled":
		return  # user backed out — no need to nag
	_toast("Purchase didn't complete", "You weren't charged. Please try again. (%s)" % reason)

## Deferred payment (UPI collect / netbanking): Play will confirm later; premium
## unlocks automatically via BillingService when it does — don't say "failed".
func _on_purchase_pending() -> void:
	_set_purchase_busy(false)
	_toast("Payment processing", "Google Play is still confirming your payment. Premium unlocks on its own once it clears.")

func _on_purchases_restored(count: int) -> void:
	_set_purchase_busy(false)
	if count > 0:
		_toast("Restored", "Your premium purchase is back on this device.")
	elif count < 0:
		_toast("Restore failed", "Couldn't reach Google Play. Check your connection and try again.")
	else:
		_toast("Nothing to restore", "No previous purchase was found for this Google account.")

func _toast(title_text: String, msg: String) -> void:
	var m := ModalOverlay.new()
	m.compact = true
	m.set_header("Premium", title_text, msg)
	m.add_action("Done", PremiumButton.Variant.PRIMARY, func(): m.close())
	m.open(self)
