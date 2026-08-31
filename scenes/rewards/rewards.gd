extends AppScreen
## Rewards — the page a finished run hands its receipt to.
##
## THE PAYOUT USED TO BE A TABLE ROW. Every mode ended in a game-over modal with
## "Coins earned  +230" wedged between "Time" and "Undos used" — one line, one
## number, no itemisation, and gems nowhere at all. That is a statement of fact
## where the moment wanted a reward: a run is the loop's whole unit of work, and
## the thing that pays for it was the least prominent line on the screen that
## announced it.
##
## WHAT IT SHOWS. One row per line of `Progression.take_reward()`, in the order
## the series earned them — the score, the win, the day's opener, a mode's first
## win, a medal, the streak — and the daily cap's cut as its own row when it
## bit. Rows land one at a time and each one rolls its currency's balance
## up as it lands, so the number in the purse moves BECAUSE of the line the
## player is reading. That coupling is the point of the page. A balance that
## jumped to its final value on load would make the ledger a receipt for money
## that had already arrived.
##
## THE MONEY IS ALREADY BANKED. `Progression.conclude()` credited every coin and
## gem before this screen existed, so the balances here count UP FROM
## `Wallet.balance() - earned` rather than crediting anything a second time.
## Nothing on this page can pay, refuse to pay, or change a total: it is a
## window onto a transaction that is already closed, which is what makes it safe
## for the reveal to be interrupted, rebuilt by a theme change, or skipped.
##
## WHERE IT SITS. AFTER the game-over modal, not instead of it. The modal owns
## the things that need the live board — the score summary, and Retry, which is
## the revive and the economy's main coin drain. Only once the player has chosen
## to leave (Play Again / Home) does the run's receipt come out, and this page's
## own button carries them on to wherever they were headed. Replacing the modal
## would have meant taking the revive with it.

## Where "Continue" goes, and what it carries. Set by whoever routed here; a
## missing destination falls back to Home rather than stranding the player on a
## page whose only button does nothing.
const PAYLOAD_NEXT := "next"
const PAYLOAD_NEXT_ARGS := "next_args"
const PAYLOAD_MODE := "mode"
const PAYLOAD_SCORE := "score"
const PAYLOAD_WON := "won"

## Reward row id -> the icon it wears. A row whose id is absent falls back to its
## currency token, so an id added to Progression without a picture here still
## renders a correct row — it just looks generic, which is the failure mode to
## prefer over a blank square.
##
## `run` is deliberately NOT in this table: the score row wears the MODE'S own
## icon (see `_row_texture`), because that row is the one that says which board
## this receipt is for.
const ROW_ICONS := {
	Progression.REWARD_WIN: "games_won",
	Progression.REWARD_FIRST_OF_DAY: "daily",
	Progression.REWARD_FIRST_CLEAR: "best_score",
	Progression.REWARD_BADGE: "rank_badge",
	Progression.REWARD_STREAK: "day_streak",
	Progression.REWARD_CAPPED: "daily",
}

## Edge of a row's icon square, and of the currency tokens in the balance strip.
const ROW_ICON := 56.0
const PURSE_ICON := 48.0

## How long one row takes to arrive, and the gap between consecutive rows. The
## gap is longer than the fade on purpose: rows should read as counted out one by
## one, not as a list fading in together — the whole reason the page exists.
const ROW_DUR := 0.26
const ROW_GAP := 0.17
## How long a balance takes to roll by one row's amount. Matched to ROW_GAP so a
## roll finishes as the next row lands, and the two never overlap into a blur.
const ROLL_DUR := 0.34

## The receipt, taken ONCE. `Progression.take_reward()` clears as it reads, so a
## content rebuild (a theme change mid-reveal) must redraw from this copy rather
## than ask again and get an empty list — which would silently replace a full
## ledger with an empty page.
var _lines: Array[Dictionary] = []
var _info: Dictionary = {}
var _loaded := false

## The purse totals this page counts UP TO, resolved once for the same reason.
var _final_coins := 0
var _final_gems := 0
## What each balance is showing right now, so a rebuild or an interrupted reveal
## resumes from the visible number instead of snapping.
var _shown := {"coins": 0, "gems": 0}
var _purse_labels: Dictionary = {}
var _purse_rolls: Dictionary = {}

## The rows, hidden until the reveal walks them.
var _row_nodes: Array[Control] = []
## Guards against a second reveal (a rebuild lands while one is running) and
## marks the page finished so `_skip()` knows there is nothing left to skip.
var _revealing := false
var _revealed := false

func build_content(root: VBoxContainer) -> void:
	if not _loaded:
		_loaded = true
		_info = SceneRouter.take_payload()
		_lines = Progression.take_reward()
		var totals := Progression.reward_totals(_lines)
		_final_coins = Wallet.coins()
		_final_gems = Wallet.gems()
		# Count up from what the purse held BEFORE the run paid. Clamped at zero:
		# a receipt can only ever be a subset of the balance, but a save edited
		# between banking and arriving here must not start the roll negative.
		_shown["coins"] = maxi(0, _final_coins - int(totals["coins"]))
		_shown["gems"] = maxi(0, _final_gems - int(totals["gems"]))

	root.add_theme_constant_override("separation", int(DesignSystem.SPACE_LG))
	root.alignment = BoxContainer.ALIGNMENT_CENTER

	root.add_child(_hero())
	root.add_child(_ledger())
	root.add_child(UI.spacer(DesignSystem.SPACE_SM, true))
	root.add_child(_purse())
	root.add_child(_continue_button())

func on_ready() -> void:
	# The whole screen is one tap target for "get on with it". A player who has
	# seen the ceremony forty times should never have to wait it out, and the
	# Continue button is the wrong place for that gesture: it is the thing they
	# are waiting to be ABLE to press.
	_start_reveal()

# --- Hero ---------------------------------------------------------------------
## The headline: what happened, on which board, for how many points. Reads the
## payload rather than the run state, because by the time this page is up the
## run is concluded and `Progression` has moved on to the next one.
func _hero() -> Control:
	var col := UI.vbox(DesignSystem.SPACE_XS)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var won := bool(_info.get(PAYLOAD_WON, false))
	var eyebrow := UI.eyebrow("Rewards")
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(eyebrow)

	var title := UI.fit_label("You Win" if won else "Series Over",
		DesignSystem.TYPE_TITLE, "text", HORIZONTAL_ALIGNMENT_CENTER)
	if ThemeManager.display_font:
		title.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(title)

	var mode_id := String(_info.get(PAYLOAD_MODE, ""))
	var score := int(_info.get(PAYLOAD_SCORE, 0))
	if not mode_id.is_empty():
		var sub := UI.caption("%s  ·  %s points"
			% [GameModes.get_mode(mode_id).title, UI.commafy(score)], "text_dim",
			HORIZONTAL_ALIGNMENT_CENTER)
		col.add_child(sub)
	return col

# --- The ledger ---------------------------------------------------------------
func _ledger() -> Control:
	_row_nodes.clear()
	var card := UI.glass_card()
	var col := UI.vbox(DesignSystem.SPACE_SM)
	card.add_child(col)
	if _lines.is_empty():
		# Callers gate on Progression.has_reward(), so this is the save-edited /
		# direct-navigation case. An honest empty state beats an empty card.
		col.add_child(UI.body("This series paid nothing.", "text_dim"))
		return card
	for line: Dictionary in _lines:
		var row := _row(line)
		_row_nodes.append(row)
		col.add_child(row)
	return card

## One receipt line: icon, what it was for, and what it paid in each currency.
func _row(line: Dictionary) -> Control:
	var row := UI.hbox(DesignSystem.SPACE_MD)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon := TextureRect.new()
	icon.texture = _row_texture(line)
	icon.custom_minimum_size = Vector2(ROW_ICON, ROW_ICON)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var label := UI.label(String(line.get("label", "")), DesignSystem.TYPE_LABEL,
		"text_dim")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

	# Coins then gems, and a row may carry BOTH — a first clear and the weekly
	# streak both pay two currencies at once, and splitting them across two rows
	# would claim the run earned twice as many things as it did.
	var coins := int(line.get("coins", 0))
	var gems := int(line.get("gems", 0))
	if coins != 0:
		row.add_child(_amount(coins, "currency_coins"))
	if gems != 0:
		row.add_child(_amount(gems, "currency_gems"))
	return row

## The mode's own icon on the score row (its catalog `icon_path`, an
## IconLibrary token or a painted PNG); the table's otherwise; the row's
## currency token as the last resort. Never null: a receipt line with no
## picture reads as a line the page forgot.
func _row_texture(line: Dictionary) -> Texture2D:
	var id := String(line.get("id", ""))
	if id == Progression.REWARD_RUN:
		var mode_id := String(_info.get(PAYLOAD_MODE, ""))
		if GameModes.has_mode(mode_id):
			var path := GameModes.get_mode(mode_id).icon_path
			if IconLibrary.has_icon(path):
				return IconLibrary.texture(path, int(ROW_ICON), false)
			var painted := UI.icon_tex(path)
			if painted != null:
				return painted
		return IconLibrary.texture("best_score", int(ROW_ICON), false)
	var icon := String(ROW_ICONS.get(id, ""))
	if not icon.is_empty() and IconLibrary.has_icon(icon):
		return IconLibrary.texture(icon, int(ROW_ICON), false)
	var token := "currency_gems" if int(line.get("coins", 0)) == 0 else "currency_coins"
	return IconLibrary.texture(token, int(ROW_ICON), false)

## "+120 ◉" — the number and its currency token. The cap's cut arrives negative
## and prints as "−175" in the warning colour, because a deduction dressed as a
## reward is how a payout stops being trusted.
func _amount(value: int, token: String) -> Control:
	var box := UI.hbox(DesignSystem.SPACE_XS)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var text := ("+%s" % UI.commafy(value)) if value > 0 \
		else ("−%s" % UI.commafy(absi(value)))
	var lbl := UI.numeral(text, DesignSystem.TYPE_LABEL,
		"text" if value > 0 else "warning")
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lbl)

	var tok := TextureRect.new()
	tok.texture = IconLibrary.texture(token, 40, false)
	tok.custom_minimum_size = Vector2(40, 40)
	tok.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tok.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tok.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tok)
	return box

# --- The purse ----------------------------------------------------------------
## The two balances, which is where the whole page is heading. Built here rather
## than reusing `CurrencyHud` on purpose: that strip reads Wallet live and is
## therefore ALREADY at the final total the moment it enters the tree — exactly
## the snap this page exists to replace. These roll.
func _purse() -> Control:
	_purse_labels.clear()
	var row := UI.hbox(DesignSystem.SPACE_MD)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_purse_pill(WalletRules.COINS, "currency_coins"))
	row.add_child(_purse_pill(WalletRules.GEMS, "currency_gems"))
	return row

func _purse_pill(slot: String, token: String) -> Control:
	var pill := PanelContainer.new()
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := UI.glass_box(1, DesignSystem.RADIUS_PILL)
	var glow := IconLibrary.glow_color(token)
	sb.border_color = ThemeManager.color("stroke") \
		.lerp(Color(glow.r, glow.g, glow.b, 1.0), 0.35)
	sb.content_margin_left = DesignSystem.SPACE_MD
	sb.content_margin_right = DesignSystem.SPACE_MD
	sb.content_margin_top = DesignSystem.SPACE_SM
	sb.content_margin_bottom = DesignSystem.SPACE_SM
	pill.add_theme_stylebox_override("panel", sb)

	var row := UI.hbox(DesignSystem.SPACE_SM)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(row)

	var icon := TextureRect.new()
	icon.texture = IconLibrary.texture(token, int(PURSE_ICON), false)
	icon.custom_minimum_size = Vector2(PURSE_ICON, PURSE_ICON)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var value := UI.numeral(UI.commafy(int(_shown[slot])),
		DesignSystem.TYPE_HEADLINE, "text")
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ThemeManager.display_font:
		value.add_theme_font_override("font", ThemeManager.display_font)
	row.add_child(value)
	_purse_labels[slot] = value
	return pill

# --- Continue -----------------------------------------------------------------
func _continue_button() -> Control:
	var btn := PremiumButton.new()
	btn.text = "Collect"
	btn.variant = PremiumButton.Variant.PRIMARY
	btn.full_width = true
	btn.pressed.connect(_leave)
	return btn

## The hardware back button finishes the page rather than returning to the dead
## game screen behind it. A terminal screen's back IS its forward.
func on_back_request() -> bool:
	_leave()
	return true

func _leave() -> void:
	var route := String(_info.get(PAYLOAD_NEXT, ""))
	if route.is_empty():
		route = SceneRouter.Route["HOME"]
	var args: Dictionary = _info.get(PAYLOAD_NEXT_ARGS, {})
	# `replace` — this page must not sit in the back stack. Backing into a
	# receipt for a run that is over, from wherever the player went next, would
	# re-run the whole ceremony with nothing left to pay.
	SceneRouter.goto(route, args, true)

# --- The reveal ---------------------------------------------------------------
## Walks the rows, landing one at a time and rolling the balances as each lands.
##
## reduce_motion means what it says: the rows are already at their authored alpha
## (nothing has hidden them yet at that point), the balances jump to their final
## values, and the page is simply a ledger. That is the correct answer for anyone
## who asked for less movement — not a slower version of the same choreography.
func _start_reveal() -> void:
	if _revealing or _revealed:
		return
	if _row_nodes.is_empty():
		_settle()
		return
	if SettingsManager.reduce_motion():
		_settle()
		return
	_revealing = true
	for row: Control in _row_nodes:
		if is_instance_valid(row):
			row.modulate.a = 0.0
			row.scale = Vector2(0.97, 0.97)
	_walk_rows()

## Deliberately a coroutine over tree timers rather than one chained Tween: each
## step has to both animate a row AND start a balance roll of a different length,
## and an interrupted walk (the player taps through) has to be able to stop
## between rows without leaving a half-applied tween behind.
func _walk_rows() -> void:
	# One frame first, so the container has actually laid the rows out: the pop
	# scales about each row's own centre, and `size` is still zero inside _ready().
	await get_tree().process_frame
	for i in _row_nodes.size():
		if _revealed or not is_inside_tree():
			return
		var row: Control = _row_nodes[i]
		if not is_instance_valid(row):
			continue
		# SCALE, never position. These rows are children of a VBoxContainer, which
		# owns their `position` and rewrites it on every layout pass — an offset
		# animated there is silently undone the moment anything reflows, and the
		# glide simply never appears (nothing errors; the rows just fade). `scale`
		# is not a layout property, so the container leaves it alone.
		row.pivot_offset = row.size * 0.5
		var tw := row.create_tween()
		tw.set_parallel(true)
		tw.tween_property(row, "modulate:a", 1.0, ROW_DUR) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(row, "scale", Vector2.ONE, ROW_DUR) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var line: Dictionary = _lines[i]
		_roll(WalletRules.COINS, int(line.get("coins", 0)))
		_roll(WalletRules.GEMS, int(line.get("gems", 0)))
		AudioManager.play_sfx("coin")
		Haptics.light()
		await get_tree().create_timer(ROW_GAP).timeout
	_settle()

## Rolls one balance by `delta`, continuing from what is currently on screen so a
## second roll landing mid-first picks up where the eye is rather than snapping
## back to the old total and starting again.
func _roll(slot: String, delta: int) -> void:
	if delta == 0 or not _purse_labels.has(slot):
		return
	var lbl: Label = _purse_labels[slot]
	if not is_instance_valid(lbl):
		return
	var from: int = int(_shown[slot])
	var to: int = from + delta
	_shown[slot] = to
	if _purse_rolls.has(slot):
		var running: Tween = _purse_rolls[slot]
		if running != null and running.is_valid():
			running.kill()
	var roll := create_tween()
	_purse_rolls[slot] = roll
	roll.tween_method(func(v: float) -> void:
		if is_instance_valid(lbl):
			lbl.text = UI.commafy(int(round(v))),
		float(from), float(to), ROLL_DUR) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Everything visible, both balances at the real purse totals, ceremony done.
##
## Reads Wallet rather than the rolled-up figure: the receipt and the balance are
## two different sources, and if they ever disagree the PURSE is right. A page
## that left a wrong total on screen because its own arithmetic drifted would be
## the worst possible bug in a rewards screen.
func _settle() -> void:
	_revealing = false
	_revealed = true
	for row: Control in _row_nodes:
		if is_instance_valid(row):
			row.modulate.a = 1.0
			row.scale = Vector2.ONE
	for slot: String in [WalletRules.COINS, WalletRules.GEMS]:
		if _purse_rolls.has(slot):
			var running: Tween = _purse_rolls[slot]
			if running != null and running.is_valid():
				running.kill()
		if not _purse_labels.has(slot):
			continue
		var lbl: Label = _purse_labels[slot]
		if is_instance_valid(lbl):
			var final_value: int = _final_coins if slot == WalletRules.COINS \
				else _final_gems
			_shown[slot] = final_value
			lbl.text = UI.commafy(final_value)
	_celebrate()

## Confetti, once, and only for a series that earned something worth it: a win,
## a mode's first win, or a medal. An ordinary lost series pays coins and gets
## the ledger without the party — celebrating every series over is how a
## celebration stops meaning anything.
func _celebrate() -> void:
	if SettingsManager.reduce_motion() or not is_inside_tree():
		return
	if not _worth_celebrating():
		return
	# A BURST, not a top shower. The full-screen version buries the ledger in the
	# exact seconds the player is reading it — measured on the Arctic palette,
	# whose recipe is dense snow — and a celebration that hides what is being
	# celebrated is working against the page.
	Confetti.celebrate(self, 90, false)
	AudioManager.play_sfx("achievement")
	Haptics.success()

func _worth_celebrating() -> bool:
	if bool(_info.get(PAYLOAD_WON, false)):
		return true
	for line: Dictionary in _lines:
		var id := String(line.get("id", ""))
		if id == Progression.REWARD_FIRST_CLEAR or id == Progression.REWARD_BADGE:
			return true
	return false

# --- Tap to skip --------------------------------------------------------------
## Anywhere on the page finishes the reveal immediately. Only while it is still
## running — once settled, a tap must fall through to the Collect button rather
## than being swallowed by a listener that has nothing left to do.
func _unhandled_input(event: InputEvent) -> void:
	if _revealed or not _revealing:
		return
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed)
	if pressed:
		_settle()
		get_viewport().set_input_as_handled()
