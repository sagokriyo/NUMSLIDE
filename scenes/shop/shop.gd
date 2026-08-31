extends AppScreen
## Shop — where earned currency is SPENT. The destination behind every "+" on
## the CurrencyHud strip.
##
## NOTHING HERE COSTS MONEY, and nothing here ever will. Coins and gems are
## earned by playing; the only real-money product in the app is the one lifetime
## premium unlock, which lives on the Premium paywall and sells something else
## entirely (premium themes, unlimited undo, no ads). Keeping soft currency
## unpurchasable is what lets premium stay a single, honest "buy once" — a second
## money axis that sold power would reopen the question premium exists to close.
##
## IT IS A STOREFRONT, NOT A SETTINGS PAGE, and the visual language is the whole
## argument. Three rules hold this screen together:
##
##   1. PRODUCTS ARE MADE OF THE GAME. Every purchasable is painted with
##      CandyFace — the exact glass material the board's tiles wear — at a size
##      where the rim, wet band and streak actually read (see ProductTile). A
##      storefront selling a premium game out of 56pt line icons on flat rows is
##      a settings menu with prices.
##   2. ONE HERO, THEN A SHELF. The cheapest unowned theme gets a full-bleed
##      card with its own live ambience; everything else is a rail behind it.
##      Twelve equal-weight rows give the eye nowhere to land.
##   3. THE MATERIAL IS ALREADY BUILT. Every surface here is UI.glass_box /
##      glass_card — the app's lit-glass pane, with its 2px top rim and real
##      elevation shadow. This screen used to hand-roll the flattest stylebox in
##      the codebase while the premium one sat one call away.
##
## BOTH currencies have somewhere to go. Coins used to be spendable only inside a
## run, so tapping "+" on coins landed on a page that could sell them nothing;
## EconomyRules.BUNDLES is the coin sink, and the coins pill now leads with it.
##
## Arrives with {"currency": <WalletRules id>} from whichever pill was tapped and
## opens on that section.

## Featured shelf geometry, in design points.
## The hero's live-ambience stage.
##
## SHORTER than it was (520), because the card no longer stacks its name, blurb,
## price and a two-up comparison BENEATH the art. All of that now rides ON the
## art over a scrim, so one card says the same things in roughly half the page
## it used to — which is the whole reason Packs and Upgrades were living three
## screens down.
const HERO_ART_H := 470.0
## The caption band at the foot of the hero: how much of the stage the scrim and
## the overlaid name/blurb/price keep to themselves.
##
## MUST EXCEED what the band's own content needs (a TYPE_TITLE name, a
## TYPE_LABEL blurb and a caption, ~170pt together). The band is an anchored
## CONTAINER, and a container whose children need more than its anchors give it
## grows DOWNWARD past them — so an undersized value here does not crop the
## text, it pushes the price pill through the bottom of the card, where the
## stage's clip_contents saws it in half. It first shipped at 150 and did
## exactly that.
const HERO_CAPTION_H := 200.0
## How much of that stage the ambience keeps to itself, as a band above the
## board.
##
## The board is SIZED BY THIS, because MiniBoard squares itself off the shorter
## side of its rect. It used to be parked in a 300pt strip at the bottom of a
## ~700pt-wide stage, which made the one genuinely interactive object on the page
## — a real GameBoard, running the real rules in a theme nobody has bought — take
## up 17% of its own hero and read as a smudge in the art. Sizing it off the
## stage HEIGHT instead of a fixed strip puts a 400pt board in the middle of its
## own shop window.
## Lowered from 0.2 now that the caption band takes the bottom 200pt: the board
## is squared off the SHORTER side of what is left, so every point the sky keeps
## comes straight off the board's edge.
const HERO_SKY := 0.08
## The art on a shelf GRID tile. The shelf is four compact cards across now, not
## three full-width rows: a row spends a third of the page on one theme and can
## only ever show three, while a grid shows four in the height of one row and
## reads as a collection rather than as a list of invoices.
const THUMB_H := 108.0
## Themes on the shelf grid before it defers to the full picker — one row of
## four. The section already leads with a full-bleed featured card, and the job
## here is to show what ELSE is on the shelf, not to reprint the catalogue.
const FEATURED_MAX := 4
## How far the hero's art overscans its window, in design points. The art slides
## inside this margin as the page scrolls, so it moves at a different rate to its
## frame — depth, from one number and a scroll signal.
const HERO_PARALLAX := 40.0
## Ramp swatches previewed on the door to the full picker.
const SWATCHES_MAX := 5
## Ledger rows shown before "Show all" is tapped.
const LEDGER_PREVIEW := 3
## Section titles.
##
## DOWN from 54, and the header token down from 64 to SECTION_TOKEN. The heads
## had grown until a shelf's LABEL outweighed the merchandise under it — a
## 54pt title over a 64pt icon is a chapter heading, and six of them turn a
## storefront into a table of contents. The reference keeps its heads small and
## spends the weight on the products; this now does too, and the type saved here
## is what pays for PRODUCT_TITLE below.
const SECTION_TYPE := 42
## The little token beside a section title.
const SECTION_TOKEN := 44.0
## Art on a hub door. These are the page's wayfinding and, per the reference,
## its centrepiece — the one place on the storefront where an icon is the
## product rather than a label for one.
const HUB_ICON := 92.0
## A product's NAME on a card. Above TYPE_BODY on purpose: on a storefront the
## thing being sold should out-weigh the shelf it sits on.
const PRODUCT_TITLE := 44
## Product art on a shelf card. Bigger than the 132 it was: this is a CandyFace
## glass tile with a rim, a wet top band and a diagonal streak, and below about
## 140pt none of that material reads — it degrades into a coloured square with a
## glyph on it, which is exactly the flat-icon storefront ProductTile exists to
## replace.
const PRODUCT_ART := 156.0

## One line of mood per shop theme.
##
## A shelf that lists a name and a price is a stock list; the player is buying a
## LOOK, and the one thing the old card never said was what the look is. The
## hero shows it and this says it.
##
## PRESENTATION, so it lives here beside the cards it paints rather than in
## ThemeData: the .tres files are the theme's COLOUR contract, every suite that
## reads them would have to grow a field, and a blurb is not something the
## gameplay board has any use for. The cost is that this map can drift from the
## catalogue — which is exactly what the suite pins, in both directions.
const THEME_BLURBS := {
	"arctic": "A lit cabin, snow and a long winter night.",
	"circuit_pulse": "Green circuit traces on black.",
	"ink_wash": "Ink on old paper.",
	"bioluminescence": "Black water, living light.",
	"ember_serpent": "Charcoal scales, ember orange.",
	"antigrav": "Hot pink blobs in the dark.",
	"clockwork": "Brass gears and lamplight.",
	"ronin": "Lacquer black and blood red.",
	"event_horizon": "Orange light falling into black.",
	"starforged": "Cold starlight over deep blue.",
	"sanctum": "Violet glass and candlelight.",
	"nova_forge": "Pale gold heat on plum.",
}

## The mood line for `id` ("" for a theme with none — the row simply omits it
## rather than reserving an empty gap).
static func theme_blurb(id: String) -> String:
	return String(THEME_BLURBS.get(id, ""))

## Gem prices where a theme's frame steps up a tier. Derived from the catalogue's
## own ladder (Entitlements.SHOP_THEMES runs 15 -> 60), NOT a second copy of it:
## a retune there moves which themes look expensive without an edit here.
const TIER_STEPS: Array[int] = [25, 40]

## 0 (entry) .. 2 (showpiece), from a gem price. Pure, so the suite can pin every
## boundary without building a card.
static func theme_tier(price: int) -> int:
	var tier := 0
	for step: int in TIER_STEPS:
		if price > step:
			tier += 1
	return tier

## Bundle id -> the IconLibrary token that stands for it. Lives here rather than
## in EconomyRules: that file is pure rules with no UI vocabulary in it, and an
## icon id is presentation even though it is only a string.
const BUNDLE_ICONS := {
	"revive": "restart",
	"revert5": "undo",
	"tower_swap": "tower",
	# The library's only "this is removed" glyph, which is exactly what a sweep
	# does to the smallest tiles on the board.
	"sweep": "trash",
	# …and its only circular re-deal arrow. Named for the stat it was drawn for;
	# the art is a refresh, which is the whole of what a reroll is. A pack cannot
	# borrow "tower" from the swap beside it — two products in one shelf wearing
	# identical art read as a duplicate row, not as a family.
	"tower_reroll": "total_moves",
}

## The permanent upgrades, in display order. Priced in EconomyRules so a retune
## there lands here with no edit.
##
## TWO, not three: "Energy Cap" left with the currency it widened. The shelf is
## not padded back to three with an invented product — `_coming_soon_row` below
## already exists to say the catalogue grows, and a fake third upgrade would be
## the one dishonest control on the page.
const UPGRADE_ORDER: Array[String] = ["extra_undo", "extra_hint"]

## Packs per row on the bundles shelf, and a FIXED number on purpose.
##
## This used to be `EconomyRules.BUNDLES.size()` — "however many packs exist, all
## on one row" — which was not a layout decision at all, only a coincidence that
## held while the catalogue had three entries. At five, the cards' combined
## minimum width passes DesignSystem.MAX_CONTENT_WIDTH; `UI.constrain_width` then
## oscillates between two margin values trying to centre content wider than its
## own cap, and the screen dies in a layout stack overflow — the exact failure
## `_product_grid`'s own note already warned about for two-up product ROWS.
##
## The shelf grows DOWNWARD from here. A new pack adds a row, never a column.
const BUNDLE_COLUMNS := 3

## The hub: one door per section worth jumping to, in display order — the
## storefront's category tiles. Each door targets a section id from
## ordered_sections and wears its OWN icon; the suite pins both, because a door
## to a section that does not exist scrolls nowhere and never errors, and two
## doors sharing a glyph is the upgrade-icon regression one shelf up.
const HUB_TILES: Array[Dictionary] = [
	{"section": "featured", "icon": "nav_themes", "label": "Themes"},
	{"section": "bundles", "icon": "wallet", "label": "Packs"},
	{"section": "upgrades", "icon": "currency_gems", "label": "Upgrades"},
	{"section": "earning", "icon": "daily", "label": "Earning"},
]

## The Earning section's tabs, [id, label] in display order. "today" leads:
## the bounty board is the only thing on the page a player can go and act on
## right now, and the rate cards are true forever.
const EARN_TABS: Array[Array] = [["today", "Today"], ["coins", "Coins"], ["gems", "Gems"]]

## Upgrade id -> its own icon. Every row used to draw `currency_gems`, so the
## column was identical gems — and the same glyph appeared again in each row's
## price chip. The eye had nothing to tell the products apart by.
##
## Both stay inside IconLibrary's `_ic` line-icon family: the full-colour
## `_token72` set (the currencies, the storefront, the podium) is a different
## material language and would break the column.
const UPGRADE_ICONS := {
	"extra_undo": "undo",
	"tower_swap": "tower",
}

## Which section to lead with, from the tapped pill.
var _focus := ""
## Which card the featured carousel is parked on. An INDEX rather than an id,
## re-clamped per build (hero_pick): the buyable list shrinks when the hero is
## bought, and a stored id would dangle.
var _hero_index := 0
## The Earning tab in view. Survives the rebuilds a purchase triggers, same as
## _ledger_open — a tab that snapped back to Today on every payout would fold
## the rate card the player was reading.
var _earn_tab := "today"
## The page's own vertical scroller, kept so a hub door can jump to its
## section. Reassigned every build, so it never holds a freed container.
var _scroll: ScrollContainer
## The ledger is collapsed to LEDGER_PREVIEW rows until the player asks for the
## rest. Survives the rebuilds a purchase triggers, so expanding it and then
## buying something does not silently fold it again.
var _ledger_open := false
## The entrance choreography runs ONCE per visit, not on every rebuild — a
## purchase rebuilds the page, and re-animating the whole storefront every time
## the player buys something reads as a glitch rather than as polish.
var _entered := false
## Art stages that slide against their frames as the page scrolls. Rebuilt with
## the content, so it never holds a freed node across a purchase.
var _parallax_targets: Array[Control] = []

func on_ready() -> void:
	# CALM drift. The default field puts 120-196pt shards at full vividness over
	# the content; on a page of prices that lands a bright block on a number.
	add_glass_drift(true)
	# The purse is live while the screen is open: a purchase must repaint the
	# balances and re-price every row without a manual refresh.
	Wallet.balance_changed.connect(_on_wallet_changed)
	Wallet.upgrade_bought.connect(_on_wallet_changed)
	Wallet.stash_changed.connect(_on_wallet_changed)

## Every purchase rebuilds this page (see _on_wallet_changed), and a rebuild
## otherwise snaps the storefront back to the top — so buying an upgrade at the
## bottom of the page teleports the player away from what they just bought.
func preserves_scroll_on_rebuild() -> bool:
	return true

func build_content(root: VBoxContainer) -> void:
	# take_payload() empties the router's slot, so read it ONCE per entry and
	# hold it — build_content re-runs on every theme change, and a second read
	# would come back blank and lose the section the player asked for.
	if _focus.is_empty():
		_focus = String(SceneRouter.take_payload().get("currency", ""))
	# Cleared per build: every purchase rebuilds the tree, and a stale entry here
	# would be a freed node the scroll signal still tries to move.
	_parallax_targets.clear()
	root.add_child(_sparkled_header())

	# The purse is PINNED above the scroll rather than carried inside it. On a
	# storefront the balance is the number every price is read against, and one
	# that scrolls away is missing exactly while the player is deciding. (Home
	# pins its strip for the same reason.)
	root.add_child(CurrencyHud.new())

	# An OVERLAY host, not a bare scroll: content passing under the pinned strip
	# needs to dissolve into the backdrop rather than be guillotined at the
	# container edge, and the fade has to be a SIBLING of the scroller — a child
	# would scroll away with the content it exists to mask.
	var stack := Control.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.clip_contents = true
	root.add_child(stack)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.clip_contents = true
	scroll.follow_focus = false
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SmoothWheel.attach(scroll)
	stack.add_child(scroll)
	_scroll = scroll

	var fade := UI.edge_fade("top", 56.0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	fade.offset_bottom = 56.0
	stack.add_child(fade)

	# The other edge. Content ran off the bottom of the viewport with a hard cut —
	# the same unfinished tell the top fade exists to remove, left on the edge a
	# player is actually looking at while they scroll DOWN.
	var bottom_fade := UI.edge_fade("bottom", 48.0)
	bottom_fade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_fade.offset_top = -48.0
	stack.add_child(bottom_fade)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", int(DesignSystem.SPACE_MD))
	margin.add_theme_constant_override("margin_right", int(DesignSystem.SPACE_MD))
	margin.add_theme_constant_override("margin_top", int(DesignSystem.SPACE_LG))
	margin.add_theme_constant_override("margin_bottom", int(DesignSystem.SPACE_2XL))
	scroll.add_child(margin)

	# SPACE_2XL between sections, not SPACE_XL: a storefront's rhythm comes from
	# air between shelves. Packed sections read as a catalogue index.
	var col := UI.vbox(DesignSystem.SPACE_2XL)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(UI.constrain_width(col))

	for section: String in ordered_sections(_focus):
		match section:
			"featured": col.add_child(_featured_section())
			"bundles": col.add_child(_bundles_section())
			"upgrades": col.add_child(_upgrades_section())
			"earning": col.add_child(_earning_section())
			"ledger": col.add_child(_ledger_section())

	# Parallax. The art inside each hero stage tracks the page's scroll at a
	# fraction of its speed, so the frame and its contents move at different rates
	# — the cheapest real depth cue there is. Driven off the scrollbar's own signal
	# rather than polled per frame, so a still page costs nothing.
	if not bool(SettingsManager.get_value("reduce_motion")):
		var bar := scroll.get_v_scroll_bar()
		bar.value_changed.connect(func(_v: float) -> void: _apply_parallax())

	if not _entered:
		_entered = true
		UI.stagger_in(col.get_children())

## Slides each hero stage's art against its window. The stage clips, and the art
## overscans by HERO_PARALLAX, so this can never expose an edge.
func _apply_parallax() -> void:
	for stage_v: Variant in _parallax_targets:
		var stage: Control = stage_v as Control
		if stage == null or not is_instance_valid(stage) or stage.get_child_count() == 0:
			continue
		var art: Control = stage.get_child(0) as Control
		if art == null:
			continue
		# Relative to where the stage sits on the page, so the art is centred in its
		# window when the stage is centred in the viewport rather than at scroll 0.
		var rel := stage.global_position.y - size.y * 0.5
		art.position.y = clampf(-rel * 0.06, -HERO_PARALLAX, HERO_PARALLAX)

## Section order, with the tapped currency's own section pulled to the front.
##
## Gems lead with the featured themes (the trophy purchase) and coins with the
## packs they buy. Both currencies lead with something they can actually be spent
## on — the coins case is the whole reason BUNDLES exists.
##
## There were six sections; "energy" was one, and it went with the currency. The
## strip's third pill no longer routes here at all (it opens the Leaderboard), so
## no focus value can ask for a section that is gone.
##
## Static and payload-pure so the suite can check the reordering without booting
## a screen; an unknown focus leaves the order alone.
static func ordered_sections(focus: String) -> Array[String]:
	var base: Array[String] = ["featured", "bundles", "upgrades", "earning", "ledger"]
	var lead := ""
	match focus:
		WalletRules.GEMS: lead = "featured"
		WalletRules.COINS: lead = "bundles"
	if lead.is_empty():
		return base
	var out: Array[String] = [lead]
	for s: String in base:
		if s != lead:
			out.append(s)
	return out

# --- Featured: the hero, the collection, the shelf ----------------------------

## The shop window: one HERO (the cheapest unowned theme, full-bleed and live),
## the collection as a constellation, up to three more that are still for sale,
## then what is already owned as a strip of swatches, then the door to the full
## picker.
##
## Everything after the hero is deliberately SMALLER THAN THE HERO. The section
## once ran hero + three product cards + two more product cards for themes that
## could not be bought at all, which pushed Packs, Upgrades and Earning three and
## a half screens down a page they are supposed to share.
##
## The Themes picker still owns the full grid — this is a shelf, not a duplicate
## of it — but the headline product has to be visible and buyable from the
## storefront, or the Shop is a page that describes a shop.
func _featured_section() -> Control:
	var owned_ids: Array[String] = []
	var buyable: Array[String] = []
	for id: String in Entitlements.SHOP_THEMES:
		if EntitlementManager.is_theme_unlocked(id):
			owned_ids.append(id)
		else:
			buyable.append(id)
	# Cheapest first, so the hero is always the next one the player can
	# realistically reach. Sorted on the PRICE rather than trusting the
	# catalogue's own order, which is authored as a ladder today but is grouped
	# by mood the moment someone reorders it.
	buyable.sort_custom(func(a: String, b: String) -> bool:
		return Entitlements.theme_price(a) < Entitlements.theme_price(b))

	var total: int = Entitlements.SHOP_THEMES.size()
	var owned: int = owned_ids.size()
	var body := UI.vbox(DesignSystem.SPACE_LG)

	# The card the CAROUSEL is parked on — the cheapest by default, any other
	# buyable theme by tapping its dot. Clamped every build: buying the hero
	# shrinks the list under a remembered index.
	var hero_id := ""
	if buyable.is_empty():
		body.add_child(_collection_trophy(total))
		body.add_child(_hub_grid())
	else:
		var hero_i := hero_pick(buyable.size(), _hero_index)
		hero_id = buyable[hero_i]
		body.add_child(_hero_card(hero_id))
		if buyable.size() > 1:
			body.add_child(_carousel_dots(buyable.size(), hero_i))
		# How far off the cheapest one is — but ONLY when it is out of reach. The
		# card's own price pill already answers "can I afford this", and printing
		# a green "you can buy it now" directly under a lit price tag was the
		# page saying the same thing twice.
		var reach := _gem_progress(buyable[0])
		if reach != null:
			body.add_child(reach)
		# THE HUB, directly under the featured card — the reference layout. On a
		# page this tall wayfinding is a product feature, and parked below the
		# whole shelf it existed only for players who no longer needed it. The
		# shelf resumes beneath; the doors are how everyone else skips it. Not a
		# "shop_section" — the flow counts six of those, and the hub is
		# navigation, not merchandise.
		body.add_child(_hub_grid())
		# The shelf: ONE ROW of compact cards showing what else is for sale,
		# skipping whichever theme the carousel is already holding up. The
		# collection strip and the constellation both moved out to the Themes
		# picker, which is the screen built to celebrate them — here they were
		# two more full-width blocks between the player and the rest of the shop.
		var shelved := {}
		shelved[hero_id] = true
		var shelf: Array[String] = []
		for id: String in buyable:
			if id == hero_id:
				continue
			if shelf.size() >= FEATURED_MAX:
				break
			shelf.append(id)
			shelved[id] = true
		if not shelf.is_empty():
			body.add_child(_theme_grid(shelf))
		# The door previews what is behind it: everything in the catalogue the shelf
		# has not already shown, owned or not. Scoped to the leftovers rather than
		# the unowned leftovers — the button says "all 12 themes", and with most of
		# the catalogue collected the unowned remainder is empty, which left the row
		# a bare text link exactly when the collection is most worth showing off.
		var rest: Array[String] = []
		for id: String in Entitlements.SHOP_THEMES:
			if not shelved.has(id):
				rest.append(id)
		body.add_child(_all_themes_button(total, rest))

	# THE ROOM TAKES THE COLOUR OF WHAT IS ON THE SHELF. A shop that sells LOOKS
	# had one fixed neutral chrome wrapped around a coloured hero, so the page
	# never changed no matter what it was selling. The shelf now carries a wash of
	# the featured theme's own accent, and it shifts as the hero does — including
	# when the carousel turns.
	var lead_accent: Color = ThemeManager.color("accent")
	if not hero_id.is_empty():
		lead_accent = ThemeManager.palette_for(hero_id).get("accent", lead_accent)
	# NO head link: the shelf already closes with the "See all 12 themes" row,
	# which does the same job and previews the ramps behind the door. Two
	# identical exits from one section is the page repeating itself.
	return _section("currency_gems", "Themes", "%d / %d" % [owned, total],
		_tinted_shelf(body, lead_accent), "featured")

## Which of `count` featured cards the carousel shows for a remembered `index`.
## Clamped, not wrapped: the list shrinks when the hero is bought, and a stale
## index must land on a real card rather than off the end of the shelf. Pure so
## the suite can pin the edges without building a screen.
static func hero_pick(count: int, index: int) -> int:
	if count <= 0:
		return 0
	return clampi(index, 0, count - 1)

## The carousel's pager: one dot per buyable theme, the active one stretched to
## an accent pill. Each dot sits inside a generous hit target — a 13pt circle
## is a statement, not a button — and the whole row is redundant with a dot
## count of one, which is why the caller gates it.
func _carousel_dots(count: int, active: int) -> Control:
	var row := UI.hbox(DesignSystem.SPACE_XS)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var accent := ThemeManager.color("accent")
	var idle := ThemeManager.color("text_dim")
	for i in count:
		var hit := CenterContainer.new()
		hit.custom_minimum_size = Vector2(36, 36)
		var on := i == active
		var dot := Panel.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.custom_minimum_size = Vector2(34 if on else 13, 13)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(7)
		sb.anti_aliasing = true
		if on:
			sb.bg_color = accent
			sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.4)
			sb.shadow_size = 6
		else:
			sb.bg_color = Color(idle.r, idle.g, idle.b, 0.45)
		dot.add_theme_stylebox_override("panel", sb)
		hit.add_child(dot)
		if not on:
			var pick := i
			UI.make_scroll_tappable(hit, func():
				_hero_index = pick
				Haptics.light()
				_rebuild_content())
		row.add_child(hit)
	return row

## Wraps a shelf in a soft wash of `tint`, fading out down the section.
##
## A PanelContainer fits EVERY child to its own rect, so the gradient added first
## fills behind and the content added second draws over it — tree order, not
## z_index. (A negative z_index would put it under AppScreen's opaque background
## and vanish entirely; see the note on that in screen.gd.)
func _tinted_shelf(body: Control, tint: Color) -> Control:
	var host := PanelContainer.new()
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# PASS, not the PanelContainer default of STOP. This wrapper is pure paint
	# and it is the TALLEST single node on the page — it spans the whole featured
	# shelf — so leaving it on STOP made roughly a screen and a half of the Shop
	# a dead zone where dragging did nothing at all. The cards inside it still
	# get their taps: PASS delivers the touch to this node AND lets it continue
	# to the ScrollContainer, which is the same contract make_scroll_tappable
	# relies on.
	host.mouse_filter = Control.MOUSE_FILTER_PASS
	var clear := StyleBoxFlat.new()
	clear.bg_color = Color(0, 0, 0, 0)
	clear.set_content_margin_all(DesignSystem.SPACE_MD)
	host.add_theme_stylebox_override("panel", clear)

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	# Kept faint on purpose. This is the room's light, not a colour block — loud
	# enough to feel, quiet enough that a theme card's own art still wins.
	grad.colors = PackedColorArray([
		Color(tint.r, tint.g, tint.b, 0.14), Color(tint.r, tint.g, tint.b, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 8
	tex.height = 256
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	var wash := TextureRect.new()
	wash.texture = tex
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(wash)
	host.add_child(body)
	return host

## The hero: one theme, FULL-BLEED, wearing its own ambience, with everything
## the card has to say laid over the art.
##
## The art IS the card now. It used to be a glass pane holding a picture, with
## the name, the balance-after line, the blurb, a price chip and a two-up ramp
## comparison stacked underneath in the ACTIVE theme's colours — six stacked
## blocks selling one thing, and the reason a single product filled a screen and
## a half. Overlaying the copy on a scrim costs nothing vertically and is what
## the reference does.
##
## Because the copy now sits on a FOREIGN theme's art, it is painted in flat
## white on a dark scrim rather than in either palette's ink — the same rule
## _stage_hint follows, and for the same reason: neither the active palette
## (wrong surface) nor the previewed one (unknown contrast against its own
## ambience) can be trusted to read.
func _hero_card(id: String) -> Control:
	var pal := ThemeManager.palette_for(id)
	var price := Entitlements.theme_price(id)
	var affordable := Wallet.gems() >= price
	var accent: Color = pal.get("accent", Color.WHITE)

	# A plain frame rather than glass_card: the art covers every pixel of the
	# card, so a frosted pane underneath it would blur a backdrop nobody can see
	# — paid for on every frame. The rim and the elevation shadow are what the
	# glass was actually contributing here, and a stylebox carries both.
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var frame := StyleBoxFlat.new()
	frame.bg_color = pal.get("bg1", Color.BLACK)
	frame.set_corner_radius_all(int(DesignSystem.RADIUS_LG))
	frame.set_border_width_all(1)
	frame.border_width_top = 2
	frame.border_color = accent.lerp(Color.WHITE, 0.35) if affordable \
		else pal.get("stroke", accent)
	frame.anti_aliasing = true
	frame.set_content_margin_all(0)
	# The card's own AURA: an accent-tinted bloom under the art, so the featured
	# theme lights the page it sits on rather than floating on it.
	frame.shadow_color = Color(accent.r, accent.g, accent.b, 0.42 if affordable else 0.18)
	frame.shadow_size = 30
	frame.shadow_offset = Vector2(0, 10)
	card.add_theme_stylebox_override("panel", frame)
	UI.make_scroll_tappable(card, func():
		_offer_theme(id, card.get_global_rect().get_center()))

	# The live stage, ROUND-CLIPPED to the card's own radius. A square-cornered
	# rectangle of art inside a RADIUS_LG card cuts visibly across the curve —
	# the concentric-radius rule broken at the most looked-at place on the page.
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, HERO_ART_H)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(stage)
	var preview := ThemePreview.new()
	preview.setup(pal)
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Overscan, so parallax has somewhere to travel: the art is taller than its
	# window and slides inside it, rather than dragging a hard edge into view.
	preview.offset_top = -HERO_PARALLAX
	preview.offset_bottom = HERO_PARALLAX
	UI.round_clip(preview, DesignSystem.RADIUS_LG)
	stage.add_child(preview)
	_parallax_targets.append(stage)
	# THE PRODUCT, laid over its own ambience: the theme's real tile ramp. The
	# backdrop is what a theme looks like in a screenshot; these are what the
	# player will actually stare at for a whole run, and until now the storefront
	# never showed them. Catch-light is live here (and only here) — on a device it
	# tracks the tilt of the phone.
	# A REAL BOARD, wearing a theme nobody has bought yet. Everything else on this
	# page is a picture of the product; this is the product, running the actual
	# rules — swipe it and the tiles merge in Nova Forge before you have paid for
	# Nova Forge. GameBoard is pure and node-free, which is the only reason a
	# storefront can afford to run one.
	#
	# It claims HORIZONTAL drags only; vertical ones fall through to the page
	# scroll (see MiniBoard's input note).
	var demo := MiniBoard.new()
	demo.setup(pal)
	# CENTRED IN THE STAGE, sized off its height — not a strip pinned to the
	# bottom edge. See HERO_SKY.
	demo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	demo.offset_top = HERO_ART_H * HERO_SKY
	demo.offset_left = DesignSystem.SPACE_MD
	demo.offset_right = -DesignSystem.SPACE_MD
	# Clear of the caption band, so the board is never half-buried under the
	# scrim carrying the name and the price.
	demo.offset_bottom = -(HERO_CAPTION_H - DesignSystem.SPACE_SM)
	stage.add_child(demo)
	# SAY IT IS PLAYABLE. A board that responds to a swipe is worth nothing if
	# nobody swipes it, and there is no way to discover an affordance that looks
	# exactly like the screenshot it is sitting on. The pill is painted in flat
	# black-and-white rather than palette colours on purpose: it lies over a
	# FOREIGN theme's art, where the active palette's ink is not guaranteed to
	# read against anything.
	stage.add_child(_stage_hint("Live board — swipe to try it"))

	# THE SCRIM. A gradient from clear to near-black across the caption band, so
	# white copy is guaranteed a surface to sit on whatever the art underneath is
	# doing. Round-clipped to the SAME radius as the art: a square-cornered
	# rectangle laid over a rounded one pokes its corners out at the card's foot.
	var scrim := TextureRect.new()
	var sg := Gradient.new()
	sg.offsets = PackedFloat32Array([0.0, 1.0 - HERO_CAPTION_H / HERO_ART_H, 1.0])
	sg.colors = PackedColorArray([
		Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.86)])
	var stex := GradientTexture2D.new()
	stex.gradient = sg
	stex.width = 8
	stex.height = 256
	stex.fill_from = Vector2(0, 0)
	stex.fill_to = Vector2(0, 1)
	scrim.texture = stex
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UI.round_clip(scrim, DesignSystem.RADIUS_LG)
	stage.add_child(scrim)

	# The caption band: name and blurb left, price hugging the right — the same
	# anatomy every other product on the page uses, moved onto the art.
	var foot := UI.hbox(DesignSystem.SPACE_MD)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -HERO_CAPTION_H
	foot.offset_left = DesignSystem.SPACE_LG
	foot.offset_right = -DesignSystem.SPACE_LG
	foot.offset_bottom = -DesignSystem.SPACE_LG
	stage.add_child(foot)

	var titles := UI.vbox(DesignSystem.SPACE_XS)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_END
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_lbl := UI.label(String(pal.get("name", id)), DesignSystem.TYPE_TITLE)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tracked := UI.tracked_display(int(DesignSystem.LETTER_SPACING_WIDE))
	if tracked != null:
		name_lbl.add_theme_font_override("font", tracked)
	titles.add_child(name_lbl)
	# The hero is the one card big enough to SHOW the mood; this is what says it.
	var blurb := theme_blurb(id)
	if not blurb.is_empty():
		var blurb_lbl := UI.label(blurb, DesignSystem.TYPE_LABEL)
		blurb_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
		blurb_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		titles.add_child(blurb_lbl)
	# What it LEAVES you with. A price answers "how much"; on the one purchase big
	# enough to hesitate over, the question actually being asked is "can I still
	# afford the next one" — and that is a subtraction the player should not have
	# to do in their head while looking at a shop window.
	if affordable:
		var after := UI.label("%s → %s gems after"
			% [UI.commafy(Wallet.gems()), UI.commafy(Wallet.gems() - price)],
			DesignSystem.TYPE_CAPTION)
		after.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		after.autowrap_mode = TextServer.AUTOWRAP_OFF
		after.mouse_filter = Control.MOUSE_FILTER_IGNORE
		titles.add_child(after)
	foot.add_child(titles)

	var buy := _buy_button(price, affordable, accent)
	buy.size_flags_vertical = Control.SIZE_SHRINK_END
	foot.add_child(buy)
	return card

## The shelf: one row of compact theme cards, four across.
func _theme_grid(ids: Array[String]) -> Control:
	var grid := GridContainer.new()
	grid.columns = FEATURED_MAX
	grid.add_theme_constant_override("h_separation", int(DesignSystem.SPACE_SM))
	grid.add_theme_constant_override("v_separation", int(DesignSystem.SPACE_SM))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id: String in ids:
		grid.add_child(_theme_tile(id))
	return grid

## One theme on the shelf: its own ambience, its name, its price.
##
## Painted in the theme's OWN colours — a glass card would show the CURRENT theme
## through it and wreck the preview, which is why this builds a solid panel
## rather than UI.glass_card(). Every piece of text on it therefore has to come
## from the PASSED palette too: the active theme's ink on a foreign theme's card
## is the same disappearing-text trap as glass-on-glass.
##
## This replaced the full-width theme ROW, which spent a third of the page on one
## product to say what a 250pt card says: what it looks like, what it is called,
## what it costs. The row's blurb and its "Once the X reward" lore moved to the
## featured card and the picker respectively — a shelf is for scanning, and four
## scannable cards beat three essays.
func _theme_tile(id: String) -> Control:
	var pal := ThemeManager.palette_for(id)
	var price := Entitlements.theme_price(id)
	var affordable := Wallet.gems() >= price
	var accent: Color = pal.get("accent", Color.WHITE)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := StyleBoxFlat.new()
	box.bg_color = pal.get("bg1", Color.BLACK)
	box.set_corner_radius_all(int(DesignSystem.RADIUS_MD))
	# RARITY IS A FRAME, not a number. The 60-gem showpiece and the 15-gem entry
	# wore identical 1px rims, so the ladder the catalogue is deliberately built
	# as (Entitlements.SHOP_THEMES prices Arctic to open the shop and Nova Forge
	# to close it) was invisible until you read the price. Weight climbs with tier.
	var tier := theme_tier(price)
	box.set_border_width_all(1 + tier)
	box.border_width_top = 2 + tier
	box.border_color = accent.lerp(Color.WHITE, 0.25) if affordable \
		else pal.get("stroke", accent)
	box.anti_aliasing = true
	box.set_content_margin_all(DesignSystem.SPACE_SM)
	if affordable:
		box.shadow_color = Color(accent.r, accent.g, accent.b, 0.35)
		box.shadow_size = 10 + tier * 4
		box.shadow_offset = Vector2(0, 4)
	card.add_theme_stylebox_override("panel", box)
	# ONE affordability language, applied to the whole card. Rimming affordable
	# cards in the theme's accent and the rest in its stroke encodes state in two
	# per-theme HUES — a violet rim beside a gold rim reads as decoration, not as
	# "you can afford this one". Desaturating the whole card does read as state,
	# identically on every theme in the catalogue.
	if not affordable:
		card.modulate = Color(0.78, 0.78, 0.80, 0.85)
	UI.make_scroll_tappable(card, func():
		_offer_theme(id, card.get_global_rect().get_center()))

	var col := UI.vbox(DesignSystem.SPACE_SM)
	card.add_child(col)

	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, THUMB_H)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var preview := ThemePreview.new()
	preview.setup(pal)
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UI.round_clip(preview, DesignSystem.RADIUS_SM)
	stage.add_child(preview)
	# THE PRODUCT, over its own ambience: two real tiles in this theme's ramp.
	# The backdrop is what a theme looks like in a screenshot; the tiles are what
	# the player stares at for a whole run.
	var strip := ThemeTileStrip.new()
	strip.setup(pal, false, [4, 16] as Array[int])
	strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	strip.offset_top = THUMB_H * 0.22
	strip.offset_bottom = -THUMB_H * 0.14
	stage.add_child(strip)
	col.add_child(stage)

	var name_lbl := UI.label(ThemeManager.theme_name(id), DesignSystem.TYPE_CAPTION)
	name_lbl.add_theme_color_override("font_color", pal.get("text", Color.WHITE))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_lbl)

	var chip := _price_chip("currency_gems", str(price), affordable, pal, true)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(chip)
	return card

## The hero's price, built as a lit OBJECT rather than a tinted label: accent
## fill, a brighter top rim so it catches light from above like every other
## surface on the page, and an accent-tinted shadow. Buying should read as
## tappable from across the room.
func _buy_button(price: int, affordable: bool, accent: Color) -> Control:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_PILL))
	sb.anti_aliasing = true
	sb.content_margin_left = DesignSystem.SPACE_LG
	sb.content_margin_right = DesignSystem.SPACE_LG
	sb.content_margin_top = DesignSystem.SPACE_SM
	sb.content_margin_bottom = DesignSystem.SPACE_SM
	if affordable:
		sb.bg_color = Color(accent.r, accent.g, accent.b, 0.92)
		sb.set_border_width_all(1)
		sb.border_width_top = 2
		sb.border_color = accent.lerp(Color.WHITE, 0.45)
		sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.35)
		sb.shadow_size = 14
		sb.shadow_offset = Vector2(0, 4)
	else:
		# Unaffordable recedes completely — no fill, no rim. A greyed-out BUTTON
		# still shouts "button"; a quiet number does not pretend to be one.
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(0)
	chip.add_theme_stylebox_override("panel", sb)

	var row := UI.hbox(DesignSystem.SPACE_XS)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	row.add_child(_token("currency_gems", 34))
	var lbl := UI.numeral(str(price), 46, "text" if affordable else "text_faint")
	if affordable:
		# On a filled accent pill the palette's own text colour can land at the
		# same value as the fill (a light theme's near-black accent under
		# near-black text). CandyFace already solves exactly this for tile
		# numerals; borrow its answer rather than guessing a contrast pair.
		lbl.add_theme_color_override("font_color", CandyFace.text_color(accent))
	row.add_child(lbl)
	return chip

## Net movement per day across whatever history the ledger still holds, as a bar
## per day, oldest to newest.
##
## Gated by the caller on having at least a few distinct days: LEDGER_MAX is 20
## entries, and a "trend" drawn through two points is noise presented as insight.
class DayBars extends Control:
	var nets: Array[int] = []
	var up: Color = Color.GREEN
	var down: Color = Color.RED

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var n := nets.size()
		if n <= 0 or size.x <= 0.0 or size.y <= 0.0:
			return
		var peak := 1
		for v in nets:
			peak = maxi(peak, absi(v))
		var gap := 4.0
		var w := maxf((size.x - gap * float(n - 1)) / float(n), 1.0)
		# A shared zero line, so a spend reads as below the water rather than as a
		# short bar of a different colour.
		var mid := size.y * 0.5
		for i in n:
			var v: int = nets[i]
			var h := (float(absi(v)) / float(peak)) * (size.y * 0.5 - 2.0)
			var x := float(i) * (w + gap)
			var rect := Rect2(x, mid - h, w, h) if v >= 0 else Rect2(x, mid, w, h)
			draw_rect(rect, up if v >= 0 else down, true)
		draw_line(Vector2(0, mid), Vector2(size.x, mid),
			Color(up.r, up.g, up.b, 0.18), 1.0, true)

## The purchase takeover: the bought theme floods the page from the point that
## was tapped.
##
## Applying a theme already repaints everything — but instantly, which reads as a
## glitch rather than as a reward. A ring expanding from where the finger was
## turns the repaint into a cause and an effect, and it is the single most
## memorable second in the app. Drawn rather than composited: there is no cheap
## screen capture to wipe between, so this floods the NEW theme's accent outward
## and fades, which reads as the look washing over the page.
class Takeover extends Control:
	var origin := Vector2.ZERO
	var tint: Color = Color.WHITE
	var t := 0.0
	var dur := 0.55
	var reach := 1200.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _process(delta: float) -> void:
		t += delta / maxf(dur, 0.01)
		if t >= 1.0:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var e := clampf(t, 0.0, 1.0)
		# Fast out, slow settle — the wave leaves quickly and dissolves.
		var r := reach * (1.0 - pow(1.0 - e, 2.2))
		if r <= 1.0:
			return
		# A filled wash behind a brighter leading edge, both fading as they travel.
		var body_a := 0.22 * (1.0 - e)
		draw_circle(origin, r, Color(tint.r, tint.g, tint.b, body_a), true, -1.0, true)
		draw_arc(origin, r, 0.0, TAU, 64,
			Color(tint.r, tint.g, tint.b, 0.55 * (1.0 - e)), maxf(3.0, r * 0.012), true)

## Fires the takeover from `origin` in `tint`. Silent under reduce_motion, where
## the theme simply applies — which is the whole point of the setting.
func _play_takeover(origin: Vector2, tint: Color) -> void:
	if bool(SettingsManager.get_value("reduce_motion")):
		return
	var wave := Takeover.new()
	wave.origin = origin
	wave.tint = tint
	# Far corner, so the wave always clears the screen whatever was tapped.
	wave.reach = maxf(size.length(), 600.0)
	add_child(wave)

## The collection, drawn as a constellation: one star per shop theme, lit for the
## ones owned. "10 / 12" tells a player the same thing, but only after they have
## read and parsed it — and this game already has constellations as a vocabulary.
class Constellation extends Control:
	var total := 12
	var owned := 0
	var lit: Color = Color.WHITE
	var idle: Color = Color(1, 1, 1, 0.25)
	## 0..1. The collection DRAWS ITSELF IN — stars light along the joining line
	## in the order they were collected, rather than the whole shape arriving
	## pre-made. A finished constellation appearing instantly says "here is a
	## fact"; one that draws says "look what you built".
	var reveal := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
		if owned > 0 and not bool(SettingsManager.get_value("reduce_motion")):
			reveal = 0.0
			var tw := create_tween()
			tw.tween_method(func(v: float) -> void:
				reveal = v
				queue_redraw(), 0.0, 1.0, DesignSystem.DUR_SLOW * 1.6) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		if total <= 0 or size.x <= 0.0:
			return
		var pts: Array[Vector2] = []
		var pad := 14.0
		var span := maxf(size.x - pad * 2.0, 1.0)
		for i in total:
			var t := float(i) / float(maxi(total - 1, 1))
			# A gentle arc rather than a straight line: a row of evenly spaced dots
			# is a progress bar with gaps, which is what this is trying not to be.
			pts.append(Vector2(pad + span * t,
				size.y * 0.5 - sin(t * PI) * size.y * 0.22))
		# The joining line only reaches as far as the collection does, so the
		# constellation visibly grows rather than sitting pre-drawn and waiting —
		# and during the reveal it draws out to a PARTIAL segment, so the line is
		# still being inked when the next star lights.
		var shown := float(mini(owned, total)) * clampf(reveal, 0.0, 1.0)
		for i in range(1, mini(owned, total)):
			var seg := clampf(shown - float(i), 0.0, 1.0)
			if seg <= 0.0:
				break
			draw_line(pts[i - 1], pts[i - 1].lerp(pts[i], seg),
				Color(lit.r, lit.g, lit.b, 0.45), 2.0, true)
		for i in total:
			if i < owned:
				# Each star pops as the line reaches it.
				var on := clampf(shown - float(i), 0.0, 1.0)
				if on <= 0.0:
					continue
				draw_circle(pts[i], 9.0 * on, Color(lit.r, lit.g, lit.b, 0.22 * on),
					true, -1.0, true)
				draw_circle(pts[i], 4.5 * on, Color(lit.r, lit.g, lit.b, lit.a * on),
					true, -1.0, true)
			else:
				draw_arc(pts[i], 4.5, 0.0, TAU, 18, idle, 1.5, true)

## Everything owned: the shelf has nothing left to sell, so it says so as a
## TROPHY rather than as a text card that reads like a failed load.
func _collection_trophy(total: int) -> Control:
	var card := UI.glass_card(2)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := UI.vbox(DesignSystem.SPACE_SM)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var stars := Constellation.new()
	stars.total = total
	stars.owned = total
	stars.lit = ThemeManager.color("success")
	# text_dim, not control_stroke — an unlit star is a free-floating ring with no
	# surface behind it, and control_stroke falls below the threshold where it
	# reads as a shape at all. Same trap as the upgrade pips.
	stars.idle = ThemeManager.color("text_dim")
	stars.custom_minimum_size.y = 72
	stars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(stars)
	var done := UI.label("All %d themes unlocked." % total, DesignSystem.TYPE_BODY, "success")
	done.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(done)
	col.add_child(UI.caption("Pick your look in the Themes picker.", "text_dim"))
	card.add_child(col)
	UI.make_scroll_tappable(card, func(): SceneRouter.goto(SceneRouter.Route["THEMES"]))
	return card

## Where a shop theme CAME FROM, back when it was a badge payout.
##
## `Entitlements.LEGACY_REWARD_BADGES` already stores this for grandfathering and
## for badge accent colours; nothing ever showed it to the player. Every one of
## the twelve has a piece of history attached, and printing it costs no new data
## and no new art — it just makes the shelf read like a collection with a past
## rather than a price list.
static func legacy_lore(id: String) -> String:
	var badge := Entitlements.legacy_reward_badge(id)
	if badge.is_empty():
		return ""
	var title := String(Achievements.DEFS.get(badge, {}).get("title", ""))
	if title.is_empty():
		return ""
	return "Once the %s reward" % title

## The shelf's last row: the door to the full picker, so showing a subset is
## never a dead end.
func _all_themes_button(total: int, rest: Array[String]) -> Control:
	var card := UI.tappable(func(): SceneRouter.goto(SceneRouter.Route["THEMES"]), 1)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := UI.vbox(DesignSystem.SPACE_SM)
	card.add_child(col)

	var row := UI.hbox(DesignSystem.SPACE_SM)
	var lbl := UI.label("See all %d themes" % total, DesignSystem.TYPE_BODY, "accent")
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	var arrow := UI.label("›", DesignSystem.TYPE_BODY, "accent")
	arrow.autowrap_mode = TextServer.AUTOWRAP_OFF
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow)
	col.add_child(row)

	# A LOOK at what is behind the door, not just a word for it. The row used to
	# be a text link, which asked the player to take on trust that there was more
	# worth seeing; a line of the remaining themes' real ramps shows it.
	if not rest.is_empty():
		var strip := UI.hbox(DesignSystem.SPACE_SM)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var shown := 0
		for id: String in rest:
			if shown >= SWATCHES_MAX:
				break
			var sw := ThemeTileStrip.new()
			# Two tiles each: enough to read a theme's colour story, small enough
			# that several fit without becoming a second shelf. Sized to match the
			# collected strip directly above it — at 74x38 these read as a
			# lower-resolution copy of that row rather than as a different thing.
			sw.setup(ThemeManager.palette_for(id), false, [4, 16] as Array[int])
			sw.custom_minimum_size = Vector2(96, 44)
			strip.add_child(sw)
			shown += 1
		col.add_child(strip)
	return card

## The line under the hero: how close the player is to it.
##
## A balance of 0 beside a wall of 40-gem cards is a dead end; the same balance
## with "4 medals away" is a target. Reads the REAL cheapest unowned theme, so
## it can never advertise a distance to something already bought.
func _gem_progress(cheapest: String) -> Control:
	var price := Entitlements.theme_price(cheapest)
	var have := Wallet.gems()
	var row := UI.hbox(DesignSystem.SPACE_SM)
	if have >= price:
		# NOTHING TO SAY. The featured card's own price pill is lit when the player
		# can afford it and quiet when they cannot, so a green "you can buy X now"
		# banner directly beneath it was the page making the same point twice —
		# and spending a whole row on the restatement.
		return null
	var short := price - have
	var medals := int(ceil(float(short) / float(maxi(1, EconomyRules.GEMS_PER_BADGE))))
	var bar := UI.vbox(DesignSystem.SPACE_XS)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(UI.progress(float(have) / float(maxi(1, price))))
	bar.add_child(UI.caption("%d of %d gems toward %s. %d more %s pays for it." \
		% [have, price, ThemeManager.theme_name(cheapest), medals,
			"medal" if medals == 1 else "medals"], "text_dim"))
	row.add_child(bar)
	return row

## Tapping a card: apply it if it is already owned, otherwise offer the purchase.
##
## The purchase goes through Wallet.buy_theme(), the ONLY writer of the owned
## record — this screen never touches the save.
## `origin` is where the player actually touched, in screen space — the takeover
## radiates from there, so the purchase visibly comes FROM the card they chose
## rather than from an arbitrary point. Defaults to the screen centre for callers
## with no card to point at.
func _offer_theme(id: String, origin: Vector2 = Vector2.INF) -> void:
	var from: Vector2 = size * 0.5 if origin == Vector2.INF else origin
	if EntitlementManager.is_theme_unlocked(id):
		Haptics.light()
		SettingsManager.set_value("theme", id)
		_play_takeover(from, ThemeManager.palette_for(id).get("accent", Color.WHITE))
		return
	var price := Entitlements.theme_price(id)
	var have := Wallet.gems()
	var title := ThemeManager.theme_name(id)
	# The short-of-gems branch takes over from here, so the confirm modal is built
	# AFTER it: a ModalOverlay is a Control, and one built before this check was
	# never parented and never freed — an orphan node leaked on every tap of a
	# theme the player cannot afford, which is exactly the tap this branch exists
	# to catch.
	if have < price:
		_short_of_gems(price)
		return
	var m := ModalOverlay.new()
	# WHERE IT CAME FROM, at the moment of buying it. Every shop theme was once a
	# badge payout (Entitlements.LEGACY_REWARD_BADGES keeps the mapping for
	# grandfathering), and that history is the difference between buying a colour
	# scheme and buying a trophy someone else had to earn. It used to sit in a
	# shelf row's third line, where it was the least-read text on the page; the
	# confirm modal is the one moment the player is actually reading.
	var body := "Unlock %s forever for %d gems. You have %d." % [title, price, have]
	var lore := legacy_lore(id)
	if not lore.is_empty():
		body += "\n%s." % lore
	m.set_header("Buy theme", title, body)
	m.add_action("Buy", PremiumButton.Variant.PRIMARY, func():
		m.close()
		var bought_accent: Color = ThemeManager.palette_for(id).get("accent", Color.WHITE)
		if Wallet.buy_theme(id):
			_play_takeover(from, bought_accent)
			# Wearing it immediately: a player who just spent gems on a look wants
			# to see it, not hunt for a second tap. This fires theme_changed, which
			# rebuilds the screen — so the card repaints as owned with no explicit
			# refresh here.
			SettingsManager.set_value("theme", id)
			# AFTER the theme lands, so the celebration wears the look that was just
			# bought: Confetti mixes its recipe from the ACTIVE palette, and firing
			# first would throw the OLD theme's colours over the new one.
			_celebrate("theme"))
	m.add_action("Not now", PremiumButton.Variant.GHOST, m.close)
	m.open(self)

# --- Chrome -------------------------------------------------------------------

## The standard nav header with a sparkle flanking the title on each side.
##
## An OVERLAY rather than a rewritten top bar: `UI.top_bar` centres its title and
## is shared by every secondary screen, so the flecks are laid over it at fixed
## fractions of its width instead of being threaded through a shared widget for
## one screen's decoration. They ignore input, so the back chip underneath keeps
## the whole bar.
func _sparkled_header() -> Control:
	var bar := nav_header("Shop")
	var stack := Control.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.custom_minimum_size.y = 0
	# IGNORE, or this decoration layer — which is laid OVER the whole bar — eats
	# every press meant for the back chip underneath it. Bare Control defaults to
	# STOP, so "the sparkles ignore input" is only true once it is said out loud.
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var host := PanelContainer.new()
	var clear := StyleBoxFlat.new()
	clear.bg_color = Color(0, 0, 0, 0)
	clear.set_content_margin_all(0)
	host.add_theme_stylebox_override("panel", clear)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.add_child(bar)
	host.add_child(stack)

	var accent := ThemeManager.color("accent")
	for spec: Array in [[0.30, 20.0], [0.70, 20.0], [0.255, 11.0], [0.745, 11.0]]:
		var s := Sparkle.new()
		s.tint = accent
		var d := float(spec[1])
		s.custom_minimum_size = Vector2(d, d)
		# Anchored to a fraction of the bar's width, with the control's own size
		# subtracted so it is CENTRED on that fraction rather than starting there.
		s.anchor_left = float(spec[0])
		s.anchor_right = float(spec[0])
		s.anchor_top = 0.5
		s.anchor_bottom = 0.5
		s.offset_left = -d * 0.5
		s.offset_right = d * 0.5
		s.offset_top = -d * 0.5
		s.offset_bottom = d * 0.5
		stack.add_child(s)
	return host

# --- The hub ------------------------------------------------------------------

## The category doors: four tinted tiles riding under the featured card, one
## per destination on the page. On a storefront this tall, wayfinding is a
## product feature — without it, Upgrades and Earning exist only for players
## patient enough to scroll past everything above them.
func _hub_grid() -> Control:
	var grid := GridContainer.new()
	grid.columns = HUB_TILES.size()
	grid.add_theme_constant_override("h_separation", int(DesignSystem.SPACE_SM))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for tile: Dictionary in HUB_TILES:
		grid.add_child(_hub_tile(String(tile["section"]), String(tile["icon"]),
			String(tile["label"])))
	return grid

## One door: its icon on a wash of its own glow, the label, and a live line —
## themes and upgrades as collected-of-total, packs as a shelf count, Earning
## as how many bounties are still open today.
func _hub_tile(section_id: String, icon_id: String, label_text: String) -> Control:
	var glow := IconLibrary.glow_color(icon_id)
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The flow's handle: hub doors are built in code, and a tap that scrolls
	# nowhere is invisible without one.
	tile.set_meta("hub_target", section_id)
	var sb := StyleBoxFlat.new()
	# A DEEP base under a bright gloss (added below), not the flat 14% wash this
	# started as. A lit object needs a dark bottom to have a bright top; washing
	# the whole tile in one alpha gave four evenly-tinted rectangles, which is a
	# legend, not a row of buttons.
	sb.bg_color = Color(glow.r, glow.g, glow.b, 0.22)
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_LG))
	sb.set_border_width_all(1)
	sb.border_width_top = 2
	sb.border_color = Color(glow.r, glow.g, glow.b, 0.75)
	sb.anti_aliasing = true
	# The tile's own coloured aura, so the hub reads as four lit objects sitting
	# on the page rather than four holes cut in it.
	sb.shadow_color = Color(glow.r, glow.g, glow.b, 0.34)
	sb.shadow_size = 16
	sb.shadow_offset = Vector2(0, 6)
	sb.content_margin_left = DesignSystem.SPACE_SM
	sb.content_margin_right = DesignSystem.SPACE_SM
	sb.content_margin_top = DesignSystem.SPACE_MD
	sb.content_margin_bottom = DesignSystem.SPACE_MD
	tile.add_theme_stylebox_override("panel", sb)
	UI.make_scroll_tappable(tile, func(): _scroll_to_section(section_id))

	# THE GLOSS. A white-to-clear gradient over the top half, round-clipped to
	# the tile's own radius — the single cheapest cue that a surface is convex
	# and lit from above, and the difference between the reference's chunky
	# category buttons and a flat coloured rectangle. Added FIRST so the icon and
	# copy draw over it (a PanelContainer fits every child to its rect, so this
	# is tree order, not z_index — see _tinted_shelf).
	var gloss := TextureRect.new()
	var gg := Gradient.new()
	gg.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gg.colors = PackedColorArray([
		Color(1, 1, 1, 0.30), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.0)])
	var gtex := GradientTexture2D.new()
	gtex.gradient = gg
	gtex.width = 8
	gtex.height = 128
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	gloss.texture = gtex
	gloss.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gloss.stretch_mode = TextureRect.STRETCH_SCALE
	gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.round_clip(gloss, DesignSystem.RADIUS_LG)
	tile.add_child(gloss)

	var col := UI.vbox(DesignSystem.SPACE_XS)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(col)
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# BIGGER art. These are the page's wayfinding and, per the reference, its
	# centrepiece; a 64pt glyph in a 250pt tile is a footnote with a border.
	holder.add_child(_token(icon_id, HUB_ICON))
	col.add_child(holder)
	var name_lbl := UI.label(label_text.to_upper(), DesignSystem.TYPE_CAPTION, "text")
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tracked := UI.tracked_display(int(DesignSystem.LETTER_SPACING_WIDE))
	if tracked != null:
		name_lbl.add_theme_font_override("font", tracked)
	col.add_child(name_lbl)
	var extra := _hub_tile_meta(section_id)
	if extra != null:
		col.add_child(extra)
	return tile

## A door's third line — null when there is nothing true to say, so the tile
## simply closes at its label rather than reserving an empty row.
func _hub_tile_meta(section_id: String) -> Control:
	match section_id:
		"featured":
			var owned := 0
			for id: String in Entitlements.SHOP_THEMES:
				if EntitlementManager.is_theme_unlocked(id):
					owned += 1
			return _hub_count("%d / %d" % [owned, Entitlements.SHOP_THEMES.size()])
		"bundles":
			return _hub_count("%d packs" % EconomyRules.BUNDLES.size())
		"upgrades":
			var level := 0
			var cap := 0
			for id: String in UPGRADE_ORDER:
				level += Wallet.upgrade_level(id)
				cap += EconomyRules.upgrade_max_level(id)
			return _hub_count("%d / %d" % [level, cap])
		"earning":
			var ids := Progression.todays_bounties()
			if ids.is_empty():
				return null
			var open := 0
			var uncollected := 0
			for id: String in ids:
				if Progression.bounty_claimable(id):
					uncollected += 1
				elif not Bounties.complete(id, Progression.bounty_progress(id)):
					open += 1
			# UNCOLLECTED COINS OUTRANK UNFINISHED TASKS. Both are "go look at
			# Earning", but one is money already earned and sitting there, and
			# that is the only badge worth interrupting someone for.
			var hold := CenterContainer.new()
			hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if uncollected > 0:
				hold.add_child(_flag("%d to claim" % uncollected,
					ThemeManager.color("success"), true))
				return hold
			if open > 0:
				hold.add_child(_flag("%d to do" % open, IconLibrary.glow_color("daily"), true))
				return hold
			return _hub_count("All done")
	return null

func _hub_count(text: String) -> Control:
	var cap := UI.caption(text, "text_dim", HORIZONTAL_ALIGNMENT_CENTER)
	cap.autowrap_mode = TextServer.AUTOWRAP_OFF
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cap

## Glides the page to `section_id`'s shelf — the hub's whole job. Instant under
## reduce_motion, where a travelling scroll is exactly the motion being refused.
func _scroll_to_section(section_id: String) -> void:
	if _scroll == null or not is_instance_valid(_scroll):
		return
	var target := _find_section_node(_scroll, section_id)
	if target == null:
		return
	var offset := int(target.global_position.y - _scroll.global_position.y)
	var y := maxi(0, _scroll.scroll_vertical + offset - int(DesignSystem.SPACE_MD))
	if bool(SettingsManager.get_value("reduce_motion")):
		_scroll.scroll_vertical = y
		return
	var tw := create_tween()
	tw.tween_property(_scroll, "scroll_vertical", y, DesignSystem.DUR_SLOW) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## The section wearing `section_id`'s meta, anywhere under `n` — the same
## handle the flow suite walks for.
func _find_section_node(n: Node, section_id: String) -> Control:
	if n.has_meta("shop_section") and String(n.get_meta("shop_section")) == section_id:
		return n as Control
	for c in n.get_children():
		var found := _find_section_node(c, section_id)
		if found != null:
			return found
	return null

# --- Coin bundles -------------------------------------------------------------

## The coin sink, as a two-up GRID of products rather than a stack of rows.
## Iterates EconomyRules.BUNDLES directly rather than keeping a display order
## beside it — a second list is one more place a new pack can be added and
## silently not appear.
func _bundles_section() -> Control:
	# A GRID, per the reference. As full-width rows the packs ran most of a screen
	# to say a few short things; as a grid they read as a shelf and the section
	# fits in the height of one old row plus its head. The column count follows
	# the catalogue size rather than a number written here — see _product_grid for
	# why that is a per-section decision, and note the shelf grew from three packs
	# to five when Sweep and the Tower reroll got prices.
	var grid := _product_grid(BUNDLE_COLUMNS)
	var lead := true
	for id: String in EconomyRules.BUNDLES:
		grid.add_child(_bundle_card(id, lead))
		lead = false
	# NO "View all" here, deliberately. The reference prints one because its
	# Packs shelf is a preview of a longer list; ours shows the entire catalogue,
	# and a link promising more behind it would be the storefront lying about its
	# own inventory. The links live where there genuinely is more: Themes (5 of
	# 12 on the page) and Recent Activity (3 of up to 20).
	return _section("currency_coins", "Packs", "", grid, "bundles")

func _bundle_card(id: String, lead: bool = false) -> Control:
	var def: Dictionary = EconomyRules.BUNDLES.get(id, {})
	var price := EconomyRules.bundle_price(id)
	var count := EconomyRules.bundle_count(id)
	var saving := EconomyRules.bundle_saving(id)
	var singly := count * EconomyRules.bundle_unit_price(id)
	var held := Wallet.stash(id)
	var affordable := Wallet.coins() >= price

	var card := _product_card(true, true)
	var col := UI.vbox(DesignSystem.SPACE_SM)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(col)

	# The pack COUNT is drawn, not written: three fanned glass tiles for a
	# three-pack. Quantity you can see beats quantity you have to read.
	#
	# SHINE on the leading pack only. A page where every product glints at once
	# reads as cheap; one travelling catch-light says "this material is glass"
	# and lets the rest of the shelf inherit the claim.
	var art := _product_art(String(BUNDLE_ICONS.get(id, "currency_coins")),
		"currency_coins", count, lead)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(art)

	# TYPE_BODY on a grid card, not PRODUCT_TITLE: three across leaves roughly a
	# third of the measure, and at 44pt every pack name in the catalogue wraps to
	# two lines — a title that breaks mid-name reads as an accident, not as
	# emphasis. Full-width rows (Upgrades) keep the bigger size.
	var title := UI.label(String(def.get("title", id)), DesignSystem.TYPE_BODY, "text",
		HORIZONTAL_ALIGNMENT_CENTER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(title)

	# The blurb WRAPS inside the card's own measure. In a three-up grid the
	# column is a third of the page, so AUTOWRAP_OFF here would report the whole
	# sentence as a minimum width and blow the grid past the content cap.
	var detail := UI.caption(String(def.get("detail", "")), "text_dim",
		HORIZONTAL_ALIGNMENT_CENTER)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(detail)

	if held > 0:
		var badge := UI.caption("%d held" % held, "accent", HORIZONTAL_ALIGNMENT_CENTER)
		badge.autowrap_mode = TextServer.AUTOWRAP_OFF
		badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(badge)

	# Price anchoring: what the same contents cost bought one at a time. The
	# saving used to be appended into the description string, so the pack's whole
	# pitch rendered in the same dim grey as its blurb. It keeps its torn-stub
	# perforation — the cue that separates a thing you SPEND from a thing you keep.
	if saving > 0:
		var perf := Perforation.new()
		perf.ink = ThemeManager.color("control_stroke")
		col.add_child(perf)
		var flag := _flag("Save %d" % saving, ThemeManager.color("success"))
		flag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(flag)
		var was := UI.caption("vs %d singly" % singly, "text_faint",
			HORIZONTAL_ALIGNMENT_CENTER)
		was.autowrap_mode = TextServer.AUTOWRAP_OFF
		was.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(was)

	var chip := _price_chip("currency_coins", str(price), affordable)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(chip)

	UI.make_scroll_tappable(card, func():
		if Wallet.buy_bundle(id):
			_celebrate("pack")
		else:
			_short_of_coins(price))
	return card

# --- Gem upgrades -------------------------------------------------------------

func _upgrades_section() -> Control:
	var body := UI.vbox(DesignSystem.SPACE_MD)
	var grid := _product_grid()
	for id: String in UPGRADE_ORDER:
		grid.add_child(_upgrade_card(id))
	body.add_child(grid)
	body.add_child(_coming_soon_row())
	return _section("currency_gems", "Upgrades", "Kept forever", body, "upgrades")

## The shelf's open end. A section that simply runs out of products reads as
## finished forever; the locked row says the catalogue grows. NO tap is wired —
## a buy button on a promise would be the one dishonest control on the page.
func _coming_soon_row() -> Control:
	var card := _product_card()
	card.modulate = Color(1, 1, 1, 0.6)
	# Nothing here is tappable, so nothing here may swallow a drag.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var line := UI.hbox(DesignSystem.SPACE_MD)
	card.add_child(line)
	line.add_child(_token("shield_lock", 52))
	var cap := UI.label("More upgrades coming soon.", DesignSystem.TYPE_LABEL, "text_dim")
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(cap)
	return card

func _upgrade_card(id: String) -> Control:
	var def: Dictionary = EconomyRules.UPGRADES.get(id, {})
	var level := Wallet.upgrade_level(id)
	var maxed := EconomyRules.upgrade_maxed(id, level)
	var price := EconomyRules.upgrade_price(id)
	var affordable := Wallet.gems() >= price

	var card := _product_card()
	var line := UI.hbox(DesignSystem.SPACE_MD)
	card.add_child(line)

	line.add_child(_product_art(String(UPGRADE_ICONS.get(id, "currency_gems")),
		"currency_gems", 1))

	var col := UI.vbox(DesignSystem.SPACE_XS)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(col)

	var title := UI.label(String(def.get("title", id)), PRODUCT_TITLE, "text")
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(title)
	col.add_child(UI.caption(String(def.get("detail", "")), "text_dim"))
	var pips := _pips(level, EconomyRules.upgrade_max_level(id))
	if pips != null:
		col.add_child(pips)

	var chip: Control = _owned_chip() if maxed \
		else _price_chip("currency_gems", str(price), affordable)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(chip)

	UI.make_scroll_tappable(card, func():
		if maxed:
			return
		if Wallet.buy_upgrade(id):
			_celebrate("upgrade")
		else:
			_short_of_gems(price))
	return card

## Level dots: filled for what is owned, a RING for what is left. A "0/2" tells
## the player the same thing, but only once they have read and parsed it.
##
## Rings, not dim discs: the old empty pip was a flat 18pt circle of
## control_stroke, which on both palettes read as dust rather than as a slot
## waiting to be filled.
func _pips(level: int, max_level: int) -> Control:
	if max_level <= 0:
		return null
	var row := UI.hbox(DesignSystem.SPACE_XS)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var accent := ThemeManager.color("accent")
	# text_dim, NOT control_stroke. A control_stroke ring is tuned to sit quietly
	# at the edge of a filled surface; floating on its own it falls below the
	# threshold where it reads as a shape at all, on both palettes — which is how
	# these ended up looking like dust rather than like empty slots.
	var idle := ThemeManager.color("text_dim")
	for i in max_level:
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(22, 22)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(11)
		sb.anti_aliasing = true
		if i < level:
			sb.bg_color = accent
			sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.35)
			sb.shadow_size = 6
		else:
			sb.bg_color = Color(0, 0, 0, 0)
			sb.set_border_width_all(3)
			sb.border_color = Color(idle.r, idle.g, idle.b, 0.6)
		dot.add_theme_stylebox_override("panel", sb)
		row.add_child(dot)
	return row

# --- Earning ------------------------------------------------------------------

## How to EARN, behind three tabs: Today's live bounty board, then the coin and
## gem rate cards. Tabbed rather than stacked — piled together, the section ran
## a full screen of chips and the one actionable thing on it (the board) shared
## a frame with facts that are true forever and actionable never.
func _earning_section() -> Control:
	var body := UI.vbox(DesignSystem.SPACE_MD)
	body.add_child(_earn_tab_strip())
	match _earn_tab:
		# Each way to earn wears the icon of the THING it asks for — a Tower star
		# gets the tower, a medal gets the rank badge — instead of every chip
		# repeating its currency's token: the tab already names the currency, so
		# repeating it nine times spends nine icons saying something already said.
		"coins":
			body.add_child(_earn_group("currency_coins", "", [
				["Finish a series", EconomyRules.RUN_BASE_CAP, "classic"],
				["First win on a board", EconomyRules.FIRST_CLEAR_BONUS, "games_won"],
				["Win the series", EconomyRules.WIN_BONUS, "best_score"],
				["First series today", EconomyRules.FIRST_RUN_OF_DAY, "daily"],
				["A new best on a board", EconomyRules.NEW_BEST_BONUS, "best_score"],
			]))
		"gems":
			body.add_child(_earn_group("currency_gems", "", [
				["Any medal", EconomyRules.GEMS_PER_BADGE, "rank_badge"],
				["A board won for the first time", EconomyRules.mode_win_gems("classic"), "games_won"],
			]))
		_:
			# TODAY leads and is the default. The bounties are the only thing on
			# the page that changes overnight and the only thing a player can go
			# and finish right now, so they carry live progress rather than
			# advertising a number.
			var live := _bounty_board()
			if live != null:
				body.add_child(live)
			else:
				body.add_child(UI.caption(
					"No bounties today. New ones at midnight.", "text_dim"))
	return _section("currency_coins", "Earning", "", body, "earning")

## The section's pager. One chip per tab, the active one filled solid — the
## same act-now language as the flags — and only the INACTIVE ones are wired,
## so tapping the tab already in view is a no-op rather than a rebuild.
func _earn_tab_strip() -> Control:
	var row := UI.hbox(DesignSystem.SPACE_SM)
	var accent := ThemeManager.color("accent")
	for tab: Array in EARN_TABS:
		var key := String(tab[0])
		var active := key == _earn_tab
		var chip := PanelContainer.new()
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# The ACTIVE chip gets no make_scroll_tappable (tapping the tab you are
		# already on is a no-op), which would leave it on the PanelContainer
		# default of STOP — a small but real dead spot right above the board.
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		if active:
			chip.add_theme_stylebox_override("panel",
				_chip_box(Color(accent.r, accent.g, accent.b, 0.92),
					accent.lerp(Color.WHITE, 0.45)))
		else:
			chip.add_theme_stylebox_override("panel",
				_chip_box(ThemeManager.color("control"), ThemeManager.color("control_stroke")))
		var lbl := UI.label(String(tab[1]), DesignSystem.TYPE_LABEL)
		# CandyFace's contrast rule on the filled chip, same as the hero's buy
		# button: a light theme's near-black accent under the palette's own
		# near-black ink is a tab with no name.
		lbl.add_theme_color_override("font_color",
			CandyFace.text_color(accent) if active else ThemeManager.color("text_dim"))
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(lbl)
		if not active:
			UI.make_scroll_tappable(chip, func():
				_earn_tab = key
				_rebuild_content())
		row.add_child(chip)
	return row

## Today's bounties, live. Null when the day has none, so the section simply
## starts at the rate card instead of reserving an empty frame.
func _bounty_board() -> Control:
	var ids := Progression.todays_bounties()
	if ids.is_empty():
		return null
	var col := UI.vbox(DesignSystem.SPACE_SM)
	var head_row := UI.hbox(DesignSystem.SPACE_SM)
	var head := UI.eyebrow("Today")
	head.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_row.add_child(head)
	# The board's shelf life. A daily list with no clock on it gives a player no
	# reason to do it TODAY, which is the entire mechanism.
	var reset := UI.caption("resets in %s" % _time_to_reset(), "text_faint")
	reset.autowrap_mode = TextServer.AUTOWRAP_OFF
	reset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_row.add_child(reset)
	col.add_child(head_row)

	var all_claimed := true
	for id: String in ids:
		col.add_child(_bounty_row(id))
		if not Progression.bounty_paid(id):
			all_claimed = false
	# Clearing the board is the small daily win the whole feature is built around,
	# and three identical "Claimed" chips read as three ordinary rows. One line
	# makes it a moment. It waits for the coins to be COLLECTED, not merely
	# earned: with a Claim button on the row, "done" and "in your purse" are two
	# states, and congratulating the player while three buttons still glow
	# unpressed would be the page contradicting itself.
	if all_claimed:
		var swept := UI.label("Every bounty collected today.",
			DesignSystem.TYPE_CAPTION, "success")
		col.add_child(swept)
	return col

## Local time remaining until the bounty rotation turns over at midnight.
func _time_to_reset() -> String:
	var tz := _tz_offset_sec()
	var now := int(Time.get_unix_time_from_system())
	var local := now + tz
	var into_day := local - floori(float(local) / 86400.0) * 86400
	return WalletRules.format_countdown(maxi(0, 86400 - into_day))

func _bounty_row(id: String) -> Control:
	var def := Bounties.definition(id)
	var goal := maxi(1, Bounties.goal(id))
	var progress := clampi(Progression.bounty_progress(id), 0, goal)
	var done := Bounties.complete(id, progress)
	var paid := Progression.bounty_paid(id)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.glass_box(1, DesignSystem.RADIUS_MD))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The ROW is not tappable — only its Claim/Go button is — so it must let the
	# page scroll through it rather than sit on the PanelContainer default of
	# STOP. Three full-width bounty rows on STOP is three dead bands in the one
	# section a player scrolls to most.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var line := UI.hbox(DesignSystem.SPACE_MD)
	card.add_child(line)
	line.add_child(_token("daily", 52))

	var col := UI.vbox(DesignSystem.SPACE_XS)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var head := UI.hbox(DesignSystem.SPACE_SM)
	var title := UI.label(String(def.get("title", id)), DesignSystem.TYPE_LABEL, "text")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var count := UI.numeral("%d / %d" % [progress, goal], DesignSystem.TYPE_CAPTION,
		"success" if done else "text_dim")
	head.add_child(count)
	col.add_child(head)
	col.add_child(UI.progress(float(progress) / float(goal),
		"success" if done else "accent", true))
	line.add_child(col)

	# Claimed, finished-but-uncollected, and still-running are three different
	# states and they get three different controls. The middle one is the whole
	# reason the board exists: it is the only thing on this page the player can
	# act on and be paid for on the spot.
	var chip: Control
	if paid:
		chip = _owned_chip("Claimed")
	elif done:
		chip = _claim_button(id, Bounties.coins(id))
	else:
		# GO, not a price. An unfinished bounty cannot be bought — quoting its
		# reward beside a locked chip reads as something for sale, when what the
		# row actually wants is to send the player back to a game.
		chip = _go_button()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(chip)
	return card

## The payout, as a button. Solid success fill — this page's language for "act
## now" — carrying the exact sum it will pay.
func _claim_button(id: String, coins: int) -> Control:
	var ok := ThemeManager.color("success")
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel",
		_chip_box(Color(ok.r, ok.g, ok.b, 0.92), ok.lerp(Color.WHITE, 0.45)))
	var row := UI.hbox(DesignSystem.SPACE_XS)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	var lbl := UI.label("Claim +%d" % coins, DesignSystem.TYPE_LABEL)
	lbl.add_theme_color_override("font_color", CandyFace.text_color(ok))
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	row.add_child(_token("currency_coins", 30))
	UI.make_scroll_tappable(chip, func():
		# Progression owns the payout and re-checks the latch, so a double tap
		# pays once. A rebuild follows from balance_changed either way.
		if Progression.claim_bounty(id) > 0:
			_celebrate("bounty"))
	return chip

## An unfinished bounty's control: a door back to the game rather than a price.
func _go_button() -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel",
		_chip_box(ThemeManager.color("control"), ThemeManager.color("control_stroke")))
	var lbl := UI.label("Go", DesignSystem.TYPE_LABEL, "text_dim")
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)
	UI.make_scroll_tappable(chip, func():
		SceneRouter.goto(SceneRouter.Route["HOME"]))
	return chip

## A rate-card group, sorted RICHEST FIRST and with the top earner wearing its
## currency's tint.
##
## Nine identical grey pills in source order made every payout look like every
## other one, so the section answered "how do I earn?" without answering "what is
## worth my evening?" — which is the only reason anyone reads it.
func _earn_group(icon_id: String, title: String, entries: Array) -> Control:
	var sorted := entries.duplicate()
	sorted.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
	var col := UI.vbox(DesignSystem.SPACE_SM)
	# "" skips the eyebrow: inside the tabbed Earning section the tab already
	# names the currency, and a second "COINS" directly under the Coins tab
	# would be the page repeating itself.
	if not title.is_empty():
		var head := UI.eyebrow(title)
		head.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
		col.add_child(head)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", int(DesignSystem.SPACE_SM))
	flow.add_theme_constant_override("v_separation", int(DesignSystem.SPACE_SM))
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var i := 0
	for entry: Array in sorted:
		# entry = [label, amount, icon] — the icon is the thing EARNED, but the
		# chip's tint still comes from the group's currency, so a leading coin chip
		# reads gold whatever glyph it wears.
		var glyph: String = String(entry[2]) if entry.size() > 2 else icon_id
		flow.add_child(_earn_chip(glyph, icon_id, String(entry[0]), int(entry[1]), i == 0))
		i += 1
	col.add_child(flow)
	return col

func _earn_chip(icon_id: String, tint_id: String, label: String, amount: int,
		lead: bool = false) -> Control:
	var chip := PanelContainer.new()
	var glow := IconLibrary.glow_color(tint_id)
	var fill: Color = ThemeManager.color("control")
	var stroke: Color = ThemeManager.color("control_stroke")
	if lead:
		fill = Color(glow.r, glow.g, glow.b, 0.18)
		stroke = Color(glow.r, glow.g, glow.b, 0.65)
	chip.add_theme_stylebox_override("panel", _chip_box(fill, stroke))
	var row := UI.hbox(DesignSystem.SPACE_XS)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	row.add_child(_token(icon_id, 30))
	var text := UI.label("%s  +%d" % [label, amount], DesignSystem.TYPE_CAPTION,
		"text" if lead else "text_dim")
	# AUTOWRAP_OFF: a chip is content-sized, and a wrapping label in one reports a
	# one-glyph minimum width — the bug that used to stack every price vertically.
	text.autowrap_mode = TextServer.AUTOWRAP_OFF
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	return chip

# --- Ledger -------------------------------------------------------------------

## The receipt. Collapsed to the last few by default: twenty rows of history at
## the bottom of a storefront is filler, but "where did my coins go?" still has
## to be answerable without leaving the screen.
func _ledger_section() -> Control:
	var raw := Wallet.ledger()
	var body := UI.vbox(DesignSystem.SPACE_SM)
	if raw.is_empty():
		# An empty state with a FACE. One bare grey sentence is the cheapest thing
		# on the page, and it is what a brand-new player sees first — the one
		# audience whose first impression of the storefront is this section.
		var empty := UI.vbox(DesignSystem.SPACE_SM)
		empty.alignment = BoxContainer.ALIGNMENT_CENTER
		var art := ProductTile.new()
		art.custom_minimum_size = Vector2(96, 96)
		art.setup(IconLibrary.glow_color("currency_coins"),
			IconLibrary.texture("currency_coins", 56, false), 1, false)
		var holder := CenterContainer.new()
		holder.add_child(art)
		empty.add_child(holder)
		var line := UI.label("No movements yet.", DesignSystem.TYPE_BODY, "text",
			HORIZONTAL_ALIGNMENT_CENTER)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.add_child(line)
		var sub := UI.caption("Finish a series and your first coins land here.", "text_dim",
			HORIZONTAL_ALIGNMENT_CENTER)
		sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.add_child(sub)
		body.add_child(empty)
		body.add_child(_closing_note())
		return _section("daily", "Recent Activity", "", body, "ledger")


	var entries := collapse_ledger(raw)
	# The statement line: what this history actually amounts to. A list of
	# movements answers "what happened"; only the totals answer "am I ahead?", and
	# that is the question a player scrolling to the bottom of a shop is asking.
	body.add_child(_ledger_totals(entries))
	var bars := _day_bars(raw)
	if bars != null:
		body.add_child(bars)
	body.add_child(UI.hairline(0.07))

	var limit: int = entries.size() if _ledger_open else mini(LEDGER_PREVIEW, entries.size())
	var now := int(Time.get_unix_time_from_system())
	var tz := _tz_offset_sec()
	var last_bucket := ""
	for i in limit:
		var entry: Dictionary = entries[i]
		# WHEN, not just what. The rows are chronological but carried no sense of
		# time at all, so a spend from last week sat flush against one from a
		# minute ago and the receipt read as one undifferentiated session.
		var bucket := day_bucket(int(entry.get("at", 0)), now, tz)
		if bucket != last_bucket:
			last_bucket = bucket
			var eyebrow := UI.eyebrow(bucket)
			eyebrow.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
			body.add_child(eyebrow)
		elif i > 0:
			# Hairlines rather than gaps: a gap reads as absence, a rule reads as
			# structure, and that is most of the difference between a list and a
			# statement.
			body.add_child(UI.hairline(0.07))
		body.add_child(_ledger_row(entry))
	body.add_child(_closing_note())
	# The expander rides the section HEAD as "View all ›", per the reference,
	# rather than sitting as a loose line of link text below the last row. It is
	# only offered when there is genuinely more to see.
	var toggle := Callable()
	if entries.size() > LEDGER_PREVIEW:
		toggle = func():
			_ledger_open = not _ledger_open
			_rebuild_content()
	return _section("daily", "Recent Activity",
		"%d" % entries.size() if not _ledger_open else "", body, "ledger", toggle)

## Merges CONSECUTIVE entries that share a reason and a currency into one row
## carrying a count.
##
## Three identical "Started a Fling run  -1" lines is the single most common
## thing the ledger has to show, and printing it three times spends three of the
## preview's rows saying one thing. Only ADJACENT runs merge: the ledger is
## chronological, and folding together entries with something else between them
## would put a total against a moment it did not happen at.
##
## Static and pure so the suite can check the folding without a purse.
static func collapse_ledger(entries: Array) -> Array:
	var out: Array = []
	for e_v: Variant in entries:
		var e: Dictionary = e_v
		var reason := String(e.get("reason", ""))
		var currency := String(e.get("currency", ""))
		if not out.is_empty():
			var last: Dictionary = out[out.size() - 1]
			if String(last.get("reason", "")) == reason \
					and String(last.get("currency", "")) == currency:
				last["amount"] = int(last.get("amount", 0)) + int(e.get("amount", 0))
				last["count"] = int(last.get("count", 1)) + 1
				continue
		var copy := e.duplicate()
		copy["count"] = 1
		out.append(copy)
	return out

## Which day a ledger entry belongs to, relative to now.
##
## Pure and offset-explicit so the suite can pin every boundary without waiting
## for midnight or depending on the machine's timezone — a date test that reads
## the developer's own clock is a false negative waiting for a plane trip. Days
## are counted in LOCAL time (hence the offset): an entry from 23:50 last night
## is "Yesterday" to the player regardless of where UTC's midnight fell.
static func day_bucket(at: int, now: int, tz_offset_sec: int = 0) -> String:
	if at <= 0:
		return "Earlier"
	var day_at := floori(float(at + tz_offset_sec) / 86400.0)
	var day_now := floori(float(now + tz_offset_sec) / 86400.0)
	var diff := day_now - day_at
	if diff <= 0:
		return "Today"
	if diff == 1:
		return "Yesterday"
	return "Earlier"

func _tz_offset_sec() -> int:
	var tz := Time.get_time_zone_from_system()
	return int(tz.get("bias", 0)) * 60

## Net movement per calendar day, oldest first — or null when there is not enough
## history for a shape to mean anything (see DayBars).
func _day_bars(raw: Array) -> Control:
	var tz := _tz_offset_sec()
	var by_day: Dictionary = {}
	var order: Array[int] = []
	for e_v: Variant in raw:
		var e: Dictionary = e_v
		var at := int(e.get("at", 0))
		if at <= 0:
			continue
		# COINS ONLY, for the same reason the totals split by currency: a bar
		# mixing a 200-coin payout with a 10-gem badge is drawn in units that do
		# not exist. Coins are the currency that moves every session, so they are
		# the one with a shape worth plotting.
		if String(e.get("currency", WalletRules.COINS)) != WalletRules.COINS:
			continue
		var day := floori(float(at + tz) / 86400.0)
		if not by_day.has(day):
			by_day[day] = 0
			order.append(day)
		by_day[day] = int(by_day[day]) + int(e.get("amount", 0))
	if order.size() < 3:
		return null
	order.sort()
	var nets: Array[int] = []
	for day: int in order:
		nets.append(int(by_day[day]))
	var bars := DayBars.new()
	bars.nets = nets
	bars.up = ThemeManager.color("success")
	bars.down = ThemeManager.color("text_faint")
	bars.custom_minimum_size.y = 46
	bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# LABELLED, now that it plots one currency: an unlabelled chart of bars above
	# and below a zero line is a shape, and the reader has to guess its units.
	var col := UI.vbox(DesignSystem.SPACE_XS)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := UI.eyebrow("Coins per day")
	head.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	col.add_child(head)
	col.add_child(bars)
	return col

## Earned and spent, PER CURRENCY, across `entries`.
##
## Per currency because the first version added every `amount` into one pot, so
## the statement line read "+544 / -1,453" out of coins and gems summed together
## — two units with no exchange rate between them, presented as the answer to
## "am I ahead?". A coin and a gem differ by two orders of
## magnitude in how hard they are to earn; adding them is not a rounding error,
## it is a category error, and it was invisible because the row printed no token.
##
## Static and pure so the suite can pin the split without a purse or a screen.
static func ledger_totals(entries: Array) -> Dictionary:
	var out: Dictionary = {}
	for e_v: Variant in entries:
		var e: Dictionary = e_v
		var currency := String(e.get("currency", WalletRules.COINS))
		var amount := int(e.get("amount", 0))
		if not out.has(currency):
			out[currency] = {"earned": 0, "spent": 0}
		var bucket: Dictionary = out[currency]
		if amount >= 0:
			bucket["earned"] = int(bucket["earned"]) + amount
		else:
			bucket["spent"] = int(bucket["spent"]) - amount
	return out

## The statement: one line per currency that actually moved, each wearing its own
## token so the number is readable as a quantity of something.
func _ledger_totals(entries: Array) -> Control:
	var totals := ledger_totals(entries)
	var col := UI.vbox(DesignSystem.SPACE_XS)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A FIXED order, not the dictionary's insertion order: the purse strip reads
	# coins then gems, and a statement whose rows reshuffle with whatever happened
	# to move first is one the eye has to re-read every visit.
	for currency: String in [WalletRules.COINS, WalletRules.GEMS]:
		if not totals.has(currency):
			continue
		var bucket: Dictionary = totals[currency]
		var row := UI.hbox(DesignSystem.SPACE_SM)
		row.add_child(_token(_currency_icon(currency), 30))
		var earned: int = int(bucket["earned"])
		if earned > 0:
			var a := UI.numeral("+%s" % UI.commafy(earned),
				DesignSystem.TYPE_LABEL, "success")
			a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(a)
		else:
			# A currency that only went OUT prints no "+0". A zero written in the
			# success colour is a credit that never happened — gems in particular
			# go weeks between milestones while themes are bought out of them.
			var filler := Control.new()
			filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(filler)
		var spent: int = int(bucket["spent"])
		if spent > 0:
			row.add_child(UI.numeral("-%s" % UI.commafy(spent),
				DesignSystem.TYPE_LABEL, "text_dim"))
		col.add_child(row)
	return col

## The page's full stop.
##
## The storefront used to simply run out of content. This is the one claim the
## whole screen is built to make, so it closes the page as a statement rather
## than sitting buried mid-way up the Earning rate card where nobody reached it.
func _closing_note() -> Control:
	var col := UI.vbox(DesignSystem.SPACE_SM)
	col.add_child(UI.hairline(0.07))
	var note := UI.label("Coins and gems are earned by playing.\nThey are never for sale.",
		DesignSystem.TYPE_CAPTION, "text_dim", HORIZONTAL_ALIGNMENT_CENTER)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(note)
	return col

func _ledger_row(entry_v: Variant) -> Control:
	var entry: Dictionary = entry_v
	var amount: int = int(entry.get("amount", 0))
	var currency := String(entry.get("currency", ""))
	var row := UI.hbox(DesignSystem.SPACE_SM)
	row.add_child(_token(_currency_icon(currency), 34))
	var repeats: int = int(entry.get("count", 1))
	if repeats > 1:
		var tally := UI.numeral("x%d" % repeats, DesignSystem.TYPE_CAPTION, "text_dim")
		row.add_child(tally)
	var what := UI.label(ledger_label(String(entry.get("reason", ""))),
		DesignSystem.TYPE_LABEL, "text")
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	what.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(what)
	var sign_txt: String = "+%d" % amount if amount >= 0 else str(amount)
	# text_DIM on the negative, not text_faint: the amount is the whole point of
	# the row, and a spend the player cannot read is not a receipt.
	var value := UI.numeral(sign_txt, DesignSystem.TYPE_LABEL,
		"success" if amount >= 0 else "text_dim")
	# CREDITS wear their own currency's hue, so the column can be read by colour
	# before it is read as numbers — gold for coins, violet for gems. Spends stay
	# neutral: two saturated colours per row would make every line shout, and
	# "what went out" is the quieter half of a statement.
	if amount >= 0:
		value.add_theme_color_override("font_color",
			IconLibrary.glow_color(_currency_icon(currency)))
	row.add_child(value)
	return row

## The token that stands for a ledger row's currency. Falls back to the coin
## token so an entry written by an older build still gets an icon.
static func _currency_icon(currency: String) -> String:
	match currency:
		WalletRules.GEMS: return "currency_gems"
		_: return "currency_coins"

## Plain English for a ledger reason slug. Static and pure so the suite can pin
## the wording without building a screen; an unknown slug falls back to itself
## rather than to a blank row.
static func ledger_label(reason: String) -> String:
	if reason.begins_with("run:"):
		return "Finished a series  ·  %s" % GameModes.get_mode(reason.substr(4)).title
	if reason.begins_with("theme:"):
		return "Bought a theme"
	if reason.begins_with("upgrade:"):
		return "Bought an upgrade"
	if reason.begins_with("bundle:"):
		var bundle: Dictionary = EconomyRules.BUNDLES.get(reason.substr(7), {})
		return "Bought a pack  ·  %s" % String(bundle.get("title", reason.substr(7)))
	if reason.begins_with("streak:"):
		return "Daily streak  ·  day %s" % reason.substr(7)
	if reason.begins_with("bounty:"):
		var def := Bounties.definition(reason.substr(7))
		return "Bounty  ·  %s" % String(def.get("title", reason.substr(7)))
	if reason.begins_with("first_clear:"):
		return "First clear  ·  %s" % GameModes.get_mode(reason.substr(12)).title
	match reason:
		"badge": return "Earned a medal"
		"streak_week": return "Seven-day streak"
		"undo": return "Took a move back"
		"hint": return "Asked Oracle"
		"time_boost": return "Bought three seconds"
		"power": return "Used a power"
		"ad": return "Watched an ad"
	return reason

# --- Pieces -------------------------------------------------------------------

## A section: an eyebrow row (token + title + optional right-hand count) with its
## body beneath. The items are the cards here — the section itself is unpainted,
## which is what gives the page a storefront rhythm instead of a stack of
## identical grey boxes.
##
## The header token is LARGER than the row tokens inside it (64 vs the product
## art's own scale). It used to be smaller — 52 against a 56pt row icon — so rows
## out-weighted the headers containing them and the page read as one flat list.
func _section(icon_id: String, title: String, meta_text: String, body: Control,
		section_id: String, view_all: Callable = Callable()) -> Control:
	var col := UI.vbox(DesignSystem.SPACE_MD)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.set_meta("shop_section", section_id)

	var head := UI.hbox(DesignSystem.SPACE_SM)
	head.add_child(_token(icon_id, SECTION_TOKEN))
	var title_lbl := UI.label(title, SECTION_TYPE, "text")
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tracked := UI.tracked_display(int(DesignSystem.LETTER_SPACING_WIDE))
	if tracked != null:
		title_lbl.add_theme_font_override("font", tracked)
	elif ThemeManager.display_font:
		title_lbl.add_theme_font_override("font", ThemeManager.display_font)
	head.add_child(title_lbl)
	# A SPARKLE riding the title, in the section's own currency hue. Small, and
	# the same fleck the header wears — the storefront's one piece of pure
	# decoration, which is what keeps six stacked shelves from reading as a
	# spreadsheet with pictures.
	var fleck := Sparkle.new()
	fleck.tint = IconLibrary.glow_color(icon_id)
	fleck.custom_minimum_size = Vector2(26, 26)
	fleck.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(fleck)
	# The head's spacer, so the title hugs its token and whatever sits on the
	# right hugs the edge. It used to be the TITLE that expanded, which parked
	# the count and the "View all" link in the middle of the row on a short name.
	head.add_child(UI.spacer())
	if not meta_text.is_empty():
		# text_DIM, not text_faint. This is the collection counter and the
		# "kept forever" promise; on a light palette faint text on the backdrop is
		# very nearly invisible, and the count is the one number that says how far
		# through the catalogue the player is.
		var meta_lbl := UI.label(meta_text, DesignSystem.TYPE_LABEL, "text_dim")
		meta_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		meta_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(meta_lbl)
	if view_all.is_valid():
		# The ledger's door is a TOGGLE, so it has to be able to say so — a
		# permanently-"View all" link on an already-expanded list is a control
		# that lies about what pressing it does.
		head.add_child(_view_all_link(view_all,
			"Show less" if section_id == "ledger" and _ledger_open else "View all"))
	col.add_child(head)
	# A short rule beneath the eyebrow, tinted toward the section's own currency:
	# gold under Packs, violet under Upgrades. Packs and Upgrades were
	# pixel-identical blocks, and this is the cheapest way to make the page's own
	# structure visible without repainting every card.
	var glow := IconLibrary.glow_color(icon_id)
	var rule := ColorRect.new()
	rule.custom_minimum_size.y = 2
	rule.color = Color(glow.r, glow.g, glow.b, 0.55)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)
	col.add_child(body)
	return col

## A section head's trailing "View all ›" — the shelf's own door, so a section
## showing a subset is never a dead end.
func _view_all_link(on_tap: Callable, text: String = "View all") -> Control:
	var lbl := UI.label("%s  ›" % text, DesignSystem.TYPE_LABEL, "accent")
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI.make_scroll_tappable(lbl, on_tap)
	return lbl

## A four-point star with a soft bloom behind it. Pure decoration, drawn rather
## than drawn FROM A FONT: the display face is a bubble font with no glyph at
## U+2726, so a literal "✦ SHOP ✦" renders tofu on the one screen it decorates.
class Sparkle extends Control:
	var tint: Color = Color.WHITE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		if r <= 1.0:
			return
		var c := size * 0.5
		# The bloom first, so the star sits IN a glow rather than on top of one.
		draw_circle(c, r * 0.85, Color(tint.r, tint.g, tint.b, 0.16), true, -1.0, true)
		# Four long points and four short shoulders — a classic sparkle. The waist
		# is what makes it a star rather than a diamond.
		var waist := r * 0.22
		var pts := PackedVector2Array([
			c + Vector2(0, -r), c + Vector2(waist, -waist),
			c + Vector2(r, 0), c + Vector2(waist, waist),
			c + Vector2(0, r), c + Vector2(-waist, waist),
			c + Vector2(-r, 0), c + Vector2(-waist, -waist)])
		draw_colored_polygon(pts, Color(tint.r, tint.g, tint.b, 0.92))

## The product shelf: full-width rows, one per product.
##
## This was a two-up GRID, and on a phone that put each card at roughly half of
## ~866pt with SPACE_LG margins inside it — so "Carry on from a game over."
## wrapped to two lines, the saving flag and its anchor price fought for the same
## line, and the whole section read as cramped. One column per row buys back the
## measure: art left, copy centre, price right, nothing wrapping that should not.
## `columns` > 1 builds the COMPACT card shelf (art over copy over price);
## column count is a per-section call because it depends on the card ANATOMY,
## not on the page: a full-width product ROW carries a large minimum width and
## cannot be tiled (see the stack-overflow note below), while the compact card
## the packs now use has a tiny one and tiles happily.
func _product_grid(columns: int = 1) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = maxi(1, columns)
	grid.add_theme_constant_override("h_separation", int(DesignSystem.SPACE_MD))
	grid.add_theme_constant_override("v_separation", int(DesignSystem.SPACE_MD))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# THE COLUMN COUNT IS A HARD LAYOUT BUDGET, not a preference. Whatever a
	# caller passes, the cards on one row must fit inside
	# DesignSystem.MAX_CONTENT_WIDTH: past it, UI.constrain_width oscillates
	# between two margin values trying to centre content wider than its own cap
	# and the screen dies with a layout stack overflow. That is a real crash seen
	# twice on a 1000x1400 probe, and again the day the bundles shelf started
	# passing its own catalogue size (see BUNDLE_COLUMNS).
	#
	# Full-width product ROWS (the default, one column) carry 132pt of art plus
	# copy plus a price, so two of THOSE side by side already breach the cap.
	# Compact grid cards (`tight`) are the narrow variant that makes three work.
	# A caller wanting more per row needs a narrower card, not a bigger number.
	return grid

## One product's surface: the app's own lit-glass pane, NOT the flat local
## stylebox this screen used to hand-roll. glass_box carries the 2px top rim (so
## the card catches light from above like every other surface) and a real
## elevation shadow from DesignSystem.shadow.
## `ticket` gives consumables their own SHAPE. Packs and upgrades were identical
## rectangles, so the fastest-read channel there is carried nothing at all: a
## thing you spend looked exactly like a thing you keep. A tighter corner plus a
## perforation reads as a stub — cues that survive any backdrop, unlike punched
## notches, which need to knock through to whatever is behind the card and cannot
## on a translucent glass surface over a starfield.
## `tight` pulls the inner padding in from SPACE_LG to SPACE_MD — for the
## compact grid cards, where three cards share the measure one row had and
## 24pt of padding a side costs a third of the room the title needs to stay on
## one line.
func _product_card(ticket: bool = false, tight: bool = false) -> PanelContainer:
	var card := PanelContainer.new()
	var box := UI.glass_box(1, DesignSystem.RADIUS_SM if ticket else DesignSystem.RADIUS_LG)
	if tight:
		box.set_content_margin_all(DesignSystem.SPACE_MD)
	card.add_theme_stylebox_override("panel", box)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return card

## A torn-off edge: a dashed rule across a ticket, above the price.
class Perforation extends Control:
	var ink: Color = Color(1, 1, 1, 0.25)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size.y = 2
		resized.connect(queue_redraw)

	func _draw() -> void:
		var dash := 10.0
		var gap := 8.0
		var x := 0.0
		var y := size.y * 0.5
		while x < size.x:
			draw_line(Vector2(x, y), Vector2(minf(x + dash, size.x), y), ink, 2.0, true)
			x += dash + gap

## A product, painted as glass in its CURRENCY's hue: gold packs, violet
## upgrades. The section's currency is legible from the merchandise alone, before
## a single price is read.
## `shine` runs ProductTile's travelling catch-light — reserved for the LEAD
## product on a shelf. A page where every card glints at once reads as cheap;
## one moving highlight is what proves the whole shelf is made of glass. It is
## reduce-motion aware inside ProductTile.setup.
func _product_art(icon_id: String, currency_icon: String, count: int,
		shine: bool = false) -> Control:
	# SHRINK, not EXPAND: the art heads a card, and an expanding holder would
	# take the width the copy needs.
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(PRODUCT_ART, PRODUCT_ART)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tile := ProductTile.new()
	tile.custom_minimum_size = Vector2(PRODUCT_ART, PRODUCT_ART)
	tile.setup(IconLibrary.glow_color(currency_icon),
		IconLibrary.texture(icon_id, int(PRODUCT_ART * 0.62), false), count, shine)
	holder.add_child(tile)
	return holder

## A small filled flag for a claim that is the product's actual pitch ("Save
## 150"). It used to be appended into the description string, which rendered the
## one number that sells the pack in the same dim grey as its blurb.
##
## `solid` fills the pill with the tint instead of washing it, for a flag that
## sits on the PAGE rather than on a card. The tinted-wash version depends on a
## dark card behind it to hold its edge; on the open backdrop of a light palette
## it fades to a pale sentence on a pale field. Ink then comes from
## CandyFace.text_color, the same contrast rule the tile numerals and the hero's
## buy button use, so a near-white success colour still gets dark text.
func _flag(text: String, tint: Color, solid: bool = false,
		type_size: int = DesignSystem.TYPE_CAPTION) -> Control:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if solid:
		chip.add_theme_stylebox_override("panel",
			_chip_box(Color(tint.r, tint.g, tint.b, 0.92), tint.lerp(Color.WHITE, 0.45)))
	else:
		chip.add_theme_stylebox_override("panel",
			_chip_box(Color(tint.r, tint.g, tint.b, 0.18), Color(tint.r, tint.g, tint.b, 0.6)))
	var lbl := UI.label(text, type_size)
	lbl.add_theme_color_override("font_color",
		CandyFace.text_color(tint) if solid else tint)
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)
	return chip

## A caption pill that floats at the top-left of an art stage.
##
## Painted in FLAT BLACK AND WHITE, not palette colours, and that is the whole
## reason it is a separate helper: it lies over art belonging to a theme the
## player does not own, so neither the active palette's ink (wrong surface) nor
## the previewed palette's (unknown contrast against its own ambience) can be
## trusted. A dark scrim under white text reads on all twelve.
##
## Positioned rather than anchored: a preset on a fresh Control pins its 0x0 rect
## with compensating offsets, and the pill would be canvas-culled seconds later.
func _stage_hint(text: String) -> Control:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.position = Vector2(DesignSystem.SPACE_MD, DesignSystem.SPACE_MD)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.52)
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_PILL))
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.22)
	sb.anti_aliasing = true
	sb.content_margin_left = DesignSystem.SPACE_MD
	sb.content_margin_right = DesignSystem.SPACE_MD
	sb.content_margin_top = DesignSystem.SPACE_XS
	sb.content_margin_bottom = DesignSystem.SPACE_XS
	chip.add_theme_stylebox_override("panel", sb)
	var lbl := UI.label(text, DesignSystem.TYPE_CAPTION)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)
	return chip

## A price chip: the currency's own token beside the number, on a pill tinted
## toward that token's signature hue. Affordable chips are filled with the
## accent, unaffordable ones stay quiet — so "can I buy this" is answered by
## colour before the number is read.
##
## The NUMERAL leads and the token follows at a smaller size. The old chip had a
## 38pt icon against a 35pt label, so the currency symbol out-sized the price it
## was labelling — a form field, not a price tag.
##
## `pal` overrides the palette the chip is painted from, and the theme cards MUST
## pass their own: a card is painted in the theme it is selling, so a chip drawn
## from the ACTIVE palette puts (say) Arctic's near-black text on Sanctum's
## near-black card and the price disappears. Same trap as glass-on-glass, one
## level further in — the surface here is a foreign theme, not a foreign
## elevation.
## `compact` shrinks the pill for the shelf grid, where four cards share the
## width one row used to have and a full-size price tag is wider than the card
## carrying it.
func _price_chip(icon_id: String, amount: String, affordable: bool,
		pal: Dictionary = {}, compact: bool = false) -> Control:
	var p: Dictionary = ThemeManager.palette() if pal.is_empty() else pal
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow := IconLibrary.glow_color(icon_id)
	var fill: Color = p.get("control", Color(0, 0, 0, 0.25))
	var stroke: Color = p.get("control_stroke", Color(1, 1, 1, 0.2))
	if affordable:
		fill = Color(glow.r, glow.g, glow.b, 0.22)
		stroke = Color(glow.r, glow.g, glow.b, 0.75)
	var box := _chip_box(fill, stroke)
	if compact:
		box.content_margin_left = DesignSystem.SPACE_SM
		box.content_margin_right = DesignSystem.SPACE_SM
		box.content_margin_top = DesignSystem.SPACE_XS
		box.content_margin_bottom = DesignSystem.SPACE_XS
	chip.add_theme_stylebox_override("panel", box)

	var row := UI.hbox(DesignSystem.SPACE_XS)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	row.add_child(_token(icon_id, 24 if compact else 30))
	var lbl := UI.numeral(amount, 32 if compact else 46)
	lbl.add_theme_color_override("font_color",
		p.get("text", Color.WHITE) if affordable else p.get("text_faint", Color.GRAY))
	row.add_child(lbl)
	return chip

## The chip for something already bought — no price, no currency, no call to act.
func _owned_chip(text: String = "Owned") -> Control:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var ok := ThemeManager.color("success")
	chip.add_theme_stylebox_override("panel",
		_chip_box(Color(ok.r, ok.g, ok.b, 0.18), Color(ok.r, ok.g, ok.b, 0.6)))
	var lbl := UI.label(text, DesignSystem.TYPE_LABEL, "success")
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)
	return chip

func _chip_box(fill: Color, stroke: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_PILL))
	sb.set_border_width_all(1)
	sb.border_color = stroke
	sb.anti_aliasing = true
	sb.content_margin_left = DesignSystem.SPACE_MD
	sb.content_margin_right = DesignSystem.SPACE_MD
	sb.content_margin_top = DesignSystem.SPACE_SM
	sb.content_margin_bottom = DesignSystem.SPACE_SM
	return sb

## A design-sheet token at its native colours. The 72-unit set carries its own
## contour and cast shadow, so it is drawn WITHOUT the glow halo (see
## UI.icon_tex_flat) — the halo double-lights them and smears onto the pill.
func _token(icon_id: String, box: float) -> Control:
	var icon := TextureRect.new()
	icon.texture = IconLibrary.texture(icon_id, int(box), false)
	icon.custom_minimum_size = Vector2(box, box)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon

## The payoff. Buying something used to be a haptic tick and a silent full-page
## repaint — on a storefront the purchase moment IS the product, and every piece
## of this is a system the app already ships.
##
## Scaled to the purchase: a theme is a keepsake and gets the full celebration,
## a consumable pack gets a confident thunk and nothing more. Confetti on every
## coin pack would spend the gesture until it meant nothing.
func _celebrate(kind: String) -> void:
	match kind:
		"theme":
			Haptics.medium()
			# Mixed from the ACTIVE theme's own recipe — see the call site's note on
			# ordering. `self` (not `content`) is the parent, so the burst survives
			# the content rebuild the purchase triggers.
			Confetti.celebrate(self, 150, true)
			AudioManager.play_sfx("victory")
		"upgrade":
			Haptics.medium()
			AudioManager.play_chime(2)
		"bounty":
			# Collecting is the one moment on this page where coins come IN, so it
			# gets the coin chime rather than a purchase thunk.
			Haptics.medium()
			AudioManager.play_chime(1)
		_:
			Haptics.medium()
			# Missing audio is fine — AudioManager lazily resolves by path and
			# silently no-ops when a clip is absent (see assets/audio READMEs).
			AudioManager.play_sfx("tile_merge", 0.06)

func _short_of_gems(price: int) -> void:
	var m := ModalOverlay.new()
	m.compact = true
	m.set_header("Not enough gems", "%d needed" % price,
		"You have %d. Every medal you earn pays %d gems." \
			% [Wallet.gems(), EconomyRules.GEMS_PER_BADGE])
	m.add_action("See Medals", PremiumButton.Variant.GLASS, func():
		m.close()
		SceneRouter.goto(SceneRouter.Route["ACHIEVEMENTS"]))
	m.add_action("Close", PremiumButton.Variant.GHOST, m.close)
	m.open(self)

func _short_of_coins(price: int) -> void:
	var m := ModalOverlay.new()
	m.compact = true
	m.set_header("Not enough coins", "%d needed" % price,
		"You have %d. Finishing a series pays up to %d." \
			% [Wallet.coins(), EconomyRules.RUN_BASE_CAP])
	m.add_action("Close", PremiumButton.Variant.GHOST, m.close)
	m.open(self)

# --- Live state ---------------------------------------------------------------
## Any purchase re-prices every row on the page, so the whole content rebuilds
## rather than each row second-guessing what changed. The page is short, and it
## is the same rebuild a theme change already performs — and it now keeps the
## reader's scroll position (see preserves_scroll_on_rebuild).
##
## Through the base class's QUEUED rebuild, not an inline one: buying an upgrade
## fires balance_changed AND upgrade_bought on the same frame, and a synchronous
## rebuild per signal tore the page down and rebuilt it twice for one tap.
## All three signals carry (String, int) — the id that moved and its new value —
## so one handler serves them without any unbind gymnastics.
func _on_wallet_changed(_id: String, _value: int) -> void:
	_queue_content_rebuild()
