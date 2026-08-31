class_name CurrencyHud
extends HBoxContainer
## CurrencyHud — the three-pill strip: coins · gems · leaderboard.
##
## Wears the currency tokens from the design sheet ("Currency Icons v2",
## IconLibrary's "currency_*" set) on the app's own glass pill, so the strip
## belongs to the same surface family as the identity capsule it sits under
## rather than introducing a second kind of chrome.
##
## THE PILL IS A REAL FROSTED PANE (UI.glass_pill), the same shard the mode cards
## and the capsule are cut from — not a flat fill with a rim. The rim it used to
## wear leaned toward each token's signature hue, on the argument that a pill
## should be identifiable at a glance; what that actually bought was a hairline
## around three chips sitting directly above cards that had none, and a 6% hue
## lerp on a 1px line was never what told coins from gems anyway. The TOKEN does
## that, in its own full colours, at 48pt.
##
## TWO BALANCES AND A DOOR. The third pill used to be energy, a capped currency
## on a refill clock; it is gone from the app entirely, and the slot now holds
## the LEADERBOARD — the player's best score, opening their record book. Keeping
## the strip at three pills is not nostalgia for the layout: the row is what
## aligns with the identity capsule above it and with Home's settings gear (see
## `trailing_action`), and two pills would leave that column empty.
##
## The leaderboard pill is built by exactly the same code as the two balances,
## and that is deliberate — it reads its number from `Progression` instead of
## `Wallet`, but a slot that looked or behaved differently would invite the eye
## to treat a best score as a third thing to spend.
##
## Reads `Wallet` / `Progression` and nothing else — it holds no state of its own
## — and stays live off `balance_changed` and `GameStats.stats_changed`, so a
## payout or a new record lands in place with no polling here.
##
## ONE HIT TARGET PER PILL. The "+" circle is DECORATION, not a nested button:
## the whole pill routes to the Shop. A real button inside a tappable panel is
## the classic double-fire (both the child and the parent claim the press), and
## the pill is a far better thumb target than a 44px circle anyway.
##
## No theme listener: the strip is built into AppScreen's `content`, which is
## torn down and rebuilt wholesale on a palette change. Adding one here would
## rebuild the pills a second time on the same frame. (Contrast BottomNav, which
## is a SIBLING of content and so must restyle itself.)

## Pills hug their contents; they do NOT split the width three ways. Stretched
## to a third each, a "25" sat alone in ~280px with a dead gap before its "+",
## which read as three empty bars rather than three balances. Sized to content
## the strip stays compact and the numbers sit against their own tokens.
## (`trailing_action` is the one exception — see below.)
##
## The width this can reach is bounded on purpose: every number abbreviates past
## COMMA_LIMIT. Worst case is ~700 of the ~866 usable px.
const PILL_HEIGHT := 68.0
const ICON_BOX := 48.0
const PLUS_BOX := 40.0
## Above this, a balance is abbreviated rather than spelled out — three pills
## share ~866px of usable width, and "1,240,000" would push the "+" off its pill.
const COMMA_LIMIT := 99_999

## The pill id the third slot uses. Deliberately NOT a WalletRules currency —
## the whole point is that this slot no longer holds one — but it keys the same
## per-slot dictionaries, so the strip stays "one child per slot id" and the
## flow can still address the pill by name.
const LEADERBOARD_SLOT := "leaderboard"

## Ordered left to right. `icon` keys into IconLibrary and `slot` is either a
## WalletRules currency or LEADERBOARD_SLOT, so neither can drift silently: the
## suite checks every icon resolves and that the last slot is the door.
const SLOTS: Array[Dictionary] = [
	{"slot": WalletRules.COINS, "icon": "currency_coins", "label": "Coins"},
	{"slot": WalletRules.GEMS, "icon": "currency_gems", "label": "Gems"},
	{"slot": LEADERBOARD_SLOT, "icon": "leaderboard", "label": "Leaderboard"},
]

## Parks the LAST pill at the far right of the strip instead of packing it
## against gems. Home turns this on so the leaderboard lands under the settings
## gear: the strip spans exactly the row the top bar does, so the two right edges
## line up and the gear reads as the head of that column. Must be set BEFORE the
## strip enters the tree — the pills are built once, in `_ready`.
##
## Off everywhere else (Shop, Profile): there is no gear to sit under there, and
## a lone pill floating right would read as a layout bug rather than a choice.
var trailing_action := false

## slot id -> the Label showing its number (rebuilt with the strip).
var _values: Dictionary = {}
## slot id -> the amount currently ON SCREEN, which during a roll is not yet the
## real value. Rolls start from here rather than from Wallet, so a payout landing
## mid-roll continues from what the player can see instead of snapping back to
## the old total and starting again.
var _shown: Dictionary = {}
## slot id -> its live odometer tween, killed before a new one starts.
var _rolls: Dictionary = {}
## How long a balance takes to count to its new value.
const ODOMETER_DUR := 0.45

func _init() -> void:
	add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))
	# The STRIP spans the row (so it aligns with the capsule above it) while the
	# pills inside it stay content-sized and packed to the left.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alignment = BoxContainer.ALIGNMENT_BEGIN
	custom_minimum_size.y = PILL_HEIGHT

func _ready() -> void:
	for slot: Dictionary in SLOTS:
		add_child(_build_pill(slot))
	_refresh_all()
	Wallet.balance_changed.connect(_on_value_changed)
	# The leaderboard pill's number is a best score, and a best score moves when
	# a RUN ends, not when a balance does. GameStats is the one signal that fires
	# on every such ending, in every mode.
	#
	# It arrives AFTER the record is written, and that ordering is load-bearing
	# rather than lucky: Progression.conclude calls submit_best before
	# GameStats.record_game_end, so the section this reads is already current by
	# the time the signal lands. Swap those two lines and the pill shows the
	# PREVIOUS best for the rest of the session — with no error anywhere.
	GameStats.stats_changed.connect(_on_stats_changed)

# --- Construction -------------------------------------------------------------

func _build_pill(slot: Dictionary) -> Control:
	var id := String(slot["slot"])
	# The pill's own air: room for the token and the "+" disc across, barely any
	# down (PILL_HEIGHT already sets the height, and card-sized vertical padding
	# would push the row past it).
	var pill := UI.glass_pill(1)
	pill.margin_left = DesignSystem.SPACE_SM
	pill.margin_right = DesignSystem.SPACE_SM
	pill.margin_top = DesignSystem.SPACE_XS
	pill.margin_bottom = DesignSystem.SPACE_XS
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if trailing_action and id == LEADERBOARD_SLOT:
		# EXPAND claims the strip's leftover width; SHRINK_END parks the pill at
		# the far end of it, still sized to its contents. A spacer child would do
		# the same, but the pills are addressed by SLOTS index, so the strip keeps
		# exactly one child per currency.
		pill.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	pill.custom_minimum_size.y = PILL_HEIGHT
	pill.tooltip_text = String(slot["label"])

	var row := UI.hbox(DesignSystem.SPACE_SM)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(row)

	# The token in its OWN colours and with NO baked glow — the sheet is explicit
	# that each icon carries its own contour so it reads on any surface, and the
	# halo would smear against the pill's rim at this size.
	var icon := TextureRect.new()
	icon.texture = IconLibrary.texture(String(slot["icon"]), int(ICON_BOX), false)
	icon.custom_minimum_size = Vector2(ICON_BOX, ICON_BOX)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	# The number itself, in a stack so a pill can grow a second line later without
	# the row's centring changing.
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 0)
	stack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stack)

	# NOT clip_text. A clipping Label reports a minimum width of ZERO, and in a
	# content-sized pill that collapses the number to nothing — the balance is
	# what the pill exists to show. Width is bounded by abbreviation instead
	# (see _format_amount / COMMA_LIMIT), which is a real bound, not a crop.
	var value := UI.label("0", 32, "text")
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ThemeManager.display_font:
		value.add_theme_font_override("font", ThemeManager.display_font)
	stack.add_child(value)
	_values[id] = value

	# "+" on a balance means "get more of this". The leaderboard is not a thing
	# to top up, so its disc wears a chevron: the same 40pt accent circle in the
	# same place, saying "this opens" instead of "this fills".
	row.add_child(_badge("+" if id != LEADERBOARD_SLOT else "›"))

	# The pill IS the button (see the class note). MOUSE_FILTER_PASS on the panel
	# lets a drag still reach an ancestor scroll, which is what make_scroll_tappable
	# is built for even though Home's top strip does not scroll today.
	UI.make_scroll_tappable(pill, func(): _open(id))
	return pill

## The accent disc at the pill's trailing edge. Decorative — the pill owns the
## press.
func _badge(glyph: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(PLUS_BOX, PLUS_BOX)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var disc := Panel.new()
	disc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeManager.color("accent")
	sb.set_corner_radius_all(int(PLUS_BOX * 0.5))
	sb.anti_aliasing = true
	disc.add_theme_stylebox_override("panel", sb)
	holder.add_child(disc)

	var mark := UI.label(glyph, 32, "bg0", HORIZONTAL_ALIGNMENT_CENTER)
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(mark)
	return holder

# --- Live state ---------------------------------------------------------------

func _refresh_all() -> void:
	for slot: Dictionary in SLOTS:
		var id := String(slot["slot"])
		_on_value_changed(id, _current(id))

## What `id`'s pill should be showing right now. The one place that knows the
## third slot reads a record rather than a balance.
static func _current(id: String) -> int:
	if id == LEADERBOARD_SLOT:
		return int(Progression.best_score_overall()["score"])
	return Wallet.balance(id)

func _on_stats_changed() -> void:
	_on_value_changed(LEADERBOARD_SLOT, _current(LEADERBOARD_SLOT))

func _on_value_changed(id: String, amount: int) -> void:
	if not _values.has(id):
		return
	var lbl: Label = _values[id]
	if not is_instance_valid(lbl):
		return
	# Every pill ROLLS. A number that jumps has already finished changing by the
	# time the eye arrives; one that counts is the only feedback the strip gives
	# that a payout, a purchase or a new record actually landed, and it is the
	# difference between a number and an event.
	var from: int = int(_shown.get(id, amount))
	_shown[id] = amount
	# A counting number is motion, and reduce_motion means what it says. The
	# balance still updates — it just arrives at once, which is the pre-odometer
	# behaviour and the correct answer for anyone who asked for less movement.
	if from == amount or not is_inside_tree() \
			or bool(SettingsManager.get_value("reduce_motion")):
		lbl.text = _format_amount(amount)
		return
	if _rolls.has(id):
		var running: Tween = _rolls[id]
		if running != null and running.is_valid():
			running.kill()
	var roll := create_tween()
	_rolls[id] = roll
	roll.tween_method(func(v: float) -> void:
		if is_instance_valid(lbl):
			lbl.text = _format_amount(int(round(v))),
		float(from), float(amount), ODOMETER_DUR) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Spelled out while it fits, abbreviated once it would not (see COMMA_LIMIT).
static func _format_amount(amount: int) -> String:
	if amount <= COMMA_LIMIT:
		return UI.commafy(amount)
	if amount < 1_000_000:
		return "%.1fK" % (float(amount) / 1000.0)
	return "%.1fM" % (float(amount) / 1_000_000.0)

## A balance pill opens the Shop on its own section; the leaderboard pill opens
## the record book. One chokepoint, so the strip's press behaviour is decided in
## exactly one place.
func _open(id: String) -> void:
	if id == LEADERBOARD_SLOT:
		SceneRouter.goto(SceneRouter.Route["LEADERBOARD"])
		return
	SceneRouter.goto(SceneRouter.Route["SHOP"], {"currency": id})
