extends Node
## Wallet — the player's purse: coins and gems, plus what they buy.
##
## The single source of truth for soft-currency balances, the way
## EntitlementManager is for premium ownership. Screens never read or write the
## "wallet" save section directly; they ask here and listen to `balance_changed`.
##
## Persistence and signalling only — every NUMBER lives in one of two pure
## siblings: `WalletRules` (core/wallet_rules.gd) for the purse's plumbing
## (clamps) and `EconomyRules` (core/economy_rules.gd) for policy (payouts,
## prices, caps). Neither knows about nodes, which is why the economy is
## unit-testable without booting a screen.
##
## WHO CALLS WHAT: `Progression` is the only earn site — the same funnel every
## mode already reports play through — so no screen owns economy logic. Spending
## happens at the point of use (an undo, a revive, a theme card), always through
## `spend()` and always checking the result.
##
## TWO JOBS, ONE SENTENCE: coins buy consumables, gems buy permanent things.
##
## There was a third, energy, which gated Fling runs on a refill clock. It is
## gone — currency, cap, clock, timer and all — so nothing in this autoload
## polls, and no balance here can ever refuse the player a game.

## Fired whenever a balance lands on a new value (never on a no-op write).
signal balance_changed(currency: String, amount: int)

## Fired when a shop theme is bought, so a screen can celebrate without polling.
signal theme_bought(theme_id: String)

## Fired when a permanent upgrade's level changes.
signal upgrade_bought(upgrade_id: String, level: int)

## A badge decoration was bought. The identity sheet repaints its pickers on it,
## so a frame unlocks in place instead of after a reopen.
signal cosmetic_bought(cosmetic_id: String)

## Fired when the count of a stashed consumable changes — bought or spent — so
## a HUD showing "2 held" updates without polling.
signal stash_changed(item_id: String, count: int)

const SECTION := "wallet"

## Permanent gem upgrades: upgrade id -> level owned. Separate section from the
## purse so a balance write can never clobber a purchase.
const UPGRADES_SECTION := "upgrades"

## Pre-bought consumables: bundle id -> how many are held. Its own section for
## the same reason upgrades have one — a balance write must never be able to
## clobber goods the player has already paid coins for.
const STASH_SECTION := "stash"

## Owned badge decorations: cosmetic id -> when it was bought. Its own section
## for the same reason upgrades have one — a purse write must never be able to
## clobber something already paid for.
##
## OWNERSHIP only. What the player has EQUIPPED is identity rather than property
## and lives in the "profile" section the identity sheet owns, which is why
## un-equipping a frame cannot lose it and a wipe of one does not touch the other.
const COSMETICS_SECTION := "cosmetics"

## The recent-transactions ledger the Shop shows. Newest first, capped — this is
## a receipt for the player, not an audit log, and an unbounded array in a save
## file that is rewritten on every coin earned is a slow leak.
const LEDGER_SECTION := "ledger"
const LEDGER_MAX := 20

## The opening grant. TEMPORARY AND DELIBERATELY OVER-GENEROUS: 10,000 coins and
## 1,000 gems open every shop theme, upgrade and helpline from the first launch,
## so the whole economy can be walked end to end without grinding for it. The
## tuned numbers this replaces were 500 coins (two revives) and 25 gems (enough
## for Arctic at 15, so the medals -> gems -> themes loop is learned by doing it
## once) — put those back when the free-money window closes.
const STARTER := {
	WalletRules.COINS: 10000,
	WalletRules.GEMS: 1000,
}

## Which grant the purse has already been paid, stamped into the save section.
##
## The grant is a FLOOR APPLIED ONCE, not a first-run-only gift: bumping this id
## alongside `STARTER` tops every EXISTING purse up to the new numbers on the
## next launch too, which is the only way "everyone starts with this" can be true
## of players who already installed. Without the stamp the alternative is a
## floor re-applied on every boot, which would refund every gem ever spent.
##
## Raising it is therefore a real payout to the whole install base. Change
## `STARTER` without touching this and only brand-new saves see it.
const GRANT_KEY := "grant"
const GRANT_ID := 1

## In-memory purse. Mirrors the save section; SaveManager hands out copies, so
## this is the live one and every write goes through _store().
var _purse: Dictionary = {}
## upgrade id -> level owned. Cached: the Shop re-prices every row on each
## rebuild, and a purchase rebuilds the page.
var _upgrades: Dictionary = {}
## bundle id -> how many are held. Cached for the same reason as _upgrades: the
## game-over modal asks whether a revive is held every time it opens.
var _stash: Dictionary = {}

func _ready() -> void:
	_upgrades = SaveManager.get_section(UPGRADES_SECTION, {})
	_stash = SaveManager.get_section(STASH_SECTION, {})
	reload_purse()

## Re-reads the purse from the save section, then pays any grant it has not had.
##
## Split out of `_ready()` so the grant has a seam a test can drive: a rule that
## only ever runs at autoload boot can otherwise only be checked by relaunching
## the app, which is how a silently-broken first-run gift ships.
##
## An empty section and a save from before the grant existed take the SAME path —
## both simply own less than the floor and are topped up to it — so there is no
## "first run" branch left to disagree with the migration one.
func reload_purse() -> void:
	var stored := SaveManager.get_section(SECTION, {})
	for currency: String in WalletRules.ALL:
		_purse[currency] = WalletRules.clamp_balance(currency,
			WalletRules.sanitize(stored.get(currency, 0)))
	if WalletRules.sanitize(stored.get(GRANT_KEY, 0)) >= GRANT_ID:
		return
	# A floor, never a reset: a player who is already richer than the grant keeps
	# what they earned. `_apply` persists and signals, so a HUD that is already
	# on screen when a grant lands repaints instead of showing a stale balance.
	for currency: String in WalletRules.ALL:
		_apply(currency, maxi(balance(currency), int(STARTER[currency])))
	_store()
	SaveManager.set_section_fields(SECTION, {GRANT_KEY: GRANT_ID})

# --- Reading ------------------------------------------------------------------

## The current balance of `currency`.
func balance(currency: String) -> int:
	return int(_purse.get(currency, 0))

func coins() -> int:
	return balance(WalletRules.COINS)

func gems() -> int:
	return balance(WalletRules.GEMS)

func can_afford(currency: String, amount: int) -> bool:
	return amount <= 0 or balance(currency) >= amount

# --- Writing ------------------------------------------------------------------

## Credits `amount` (a non-positive amount is a no-op, never a silent debit —
## callers that mean to charge must say `spend`).
##
## `reason` is a short slug for the ledger ("run_payout", "badge", "ad"). It is
## optional so no existing caller breaks, but every real earn site should pass
## one: an unexplained credit is exactly the thing players write in asking about.
func add(currency: String, amount: int, reason: String = "") -> void:
	if amount <= 0 or not WalletRules.ALL.has(currency):
		return
	_apply(currency, balance(currency) + amount)
	_log(currency, amount, reason)

## Debits `amount` if the purse covers it. Returns whether it went through, and
## is the ONLY way a balance goes down — a caller that ignores the result has an
## unpaid feature, not a free one.
func spend(currency: String, amount: int, reason: String = "") -> bool:
	if not WalletRules.ALL.has(currency):
		return false
	if amount <= 0:
		return true
	var have := balance(currency)
	if have < amount:
		return false
	_apply(currency, have - amount)
	_log(currency, -amount, reason)
	return true

## Sets a balance outright (restore paths, dev tools, tests). Clamped like any
## other write, and deliberately NOT logged — it is not a transaction.
func set_balance(currency: String, amount: int) -> void:
	if not WalletRules.ALL.has(currency):
		return
	_apply(currency, amount)

func _apply(currency: String, raw: int) -> void:
	var next := WalletRules.clamp_balance(currency, raw)
	if next == int(_purse.get(currency, 0)):
		return
	_purse[currency] = next
	_store()
	balance_changed.emit(currency, next)

# --- Purchases ----------------------------------------------------------------

## True when the player owns shop theme `id`. Delegates to EntitlementManager so
## there is exactly ONE answer to "is this theme unlocked" in the app — including
## the grandfather rule for players who earned it back when it was a badge payout.
func owns_theme(id: String) -> bool:
	return EntitlementManager.is_theme_unlocked(id)

## Buys shop theme `id` with gems. Returns false — changing nothing — when the
## id is not a shop theme, is already owned, or the purse will not cover it.
##
## This is the ONLY writer of the owned-themes record. EntitlementManager reads
## that section directly (it loads far earlier than this autoload), so the write
## must land synchronously before anyone asks, which SaveManager guarantees.
func buy_theme(id: String) -> bool:
	if not Entitlements.theme_is_shop(id) or owns_theme(id):
		return false
	var price := Entitlements.theme_price(id)
	if not spend(WalletRules.GEMS, price, "theme:" + id):
		return false
	SaveManager.set_section_fields(EntitlementManager.OWNED_THEMES_SECTION,
		{id: _now()})
	theme_bought.emit(id)
	return true

## True when the player owns badge cosmetic `id`.
##
## Asks the PRICE table first, and treats "not priced" as "free": the three
## starter frames and every achievement-earned title ship without an entry in
## EconomyRules.COSMETICS, and reading them as locked-with-a-missing-number would
## take decorations off badges that already wear them.
func owns_cosmetic(id: String) -> bool:
	if not EconomyRules.is_cosmetic(id):
		return true
	return SaveManager.section_has_key(COSMETICS_SECTION, id)

## Buys badge cosmetic `id` with gems. Returns false — changing nothing — when
## the id is not priced, is already owned, or the purse will not cover it.
##
## Unknown ids are refused BEFORE the spend for the same reason `buy_bundle`
## refuses them: `cosmetic_price` reports 0 for one and `spend` waves a zero
## charge through, so without this guard a typo would hand out a free decoration
## that nothing can draw and log a phantom transaction for it.
func buy_cosmetic(id: String) -> bool:
	if not EconomyRules.is_cosmetic(id) or owns_cosmetic(id):
		return false
	if not spend(WalletRules.GEMS, EconomyRules.cosmetic_price(id), "cosmetic:" + id):
		return false
	SaveManager.set_section_fields(COSMETICS_SECTION, {id: _now()})
	cosmetic_bought.emit(id)
	return true

## How many levels of permanent upgrade `id` the player owns (0 if none).
func upgrade_level(id: String) -> int:
	return WalletRules.sanitize(_upgrades.get(id, 0))

## Buys one level of permanent upgrade `id` with gems. Returns false — changing
## nothing — for an unknown upgrade, one already at max level, or an unaffordable
## one.
func buy_upgrade(id: String) -> bool:
	var level := upgrade_level(id)
	if EconomyRules.upgrade_max_level(id) <= 0 or EconomyRules.upgrade_maxed(id, level):
		return false
	if not spend(WalletRules.GEMS, EconomyRules.upgrade_price(id), "upgrade:" + id):
		return false
	var next := level + 1
	_upgrades[id] = next
	SaveManager.set_section_fields(UPGRADES_SECTION, {id: next})
	upgrade_bought.emit(id, next)
	return true

# --- Consumable stash ---------------------------------------------------------
## Pre-bought consumables (EconomyRules.BUNDLES): coins buy a pack in the Shop,
## the pack is spent before coins are at the point of use. See use_consumable —
## it is the ONE place that ordering lives.

## How many of consumable `id` the player holds (0 if none).
func stash(id: String) -> int:
	return WalletRules.sanitize(_stash.get(id, 0))

## Buys one pack of `id` with coins. Returns false — changing nothing — for an
## unknown bundle or a purse that will not cover it.
##
## Unknown ids are refused BEFORE the spend: `bundle_price` reports 0 for one,
## and `spend` treats a zero charge as a success, so without this guard a typo
## would hand out a free pack of nothing and log a phantom transaction.
func buy_bundle(id: String) -> bool:
	if not EconomyRules.is_bundle(id):
		return false
	if not spend(WalletRules.COINS, EconomyRules.bundle_price(id), "bundle:" + id):
		return false
	_set_stash(id, stash(id) + EconomyRules.bundle_count(id))
	return true

## Takes ONE `id` out of the stash. Returns whether one was there to take — the
## caller falls back to coins when it was not.
func consume(id: String) -> bool:
	var held := stash(id)
	if held <= 0:
		return false
	_set_stash(id, held - 1)
	return true

## Pays for one `id`: from the stash when the player holds one, from coins
## otherwise. Returns false only when NEITHER covered it, and takes nothing in
## that case.
##
## Every point of use goes through this rather than ordering the two itself. A
## site that checked coins first would silently charge a player who had already
## paid for the pack, and one that forgot the fallback would refuse a purchase
## the purse could afford — neither shows up as anything but a confused review.
func use_consumable(id: String, coin_price: int) -> bool:
	if consume(id):
		return true
	return spend(WalletRules.COINS, coin_price, id)

## True when `use_consumable` would succeed. Offer sites gate on THIS, never on
## the coin balance alone: a player holding two revives and no coins must still
## be offered the revive they already bought.
func can_use(id: String, coin_price: int) -> bool:
	return stash(id) > 0 or can_afford(WalletRules.COINS, coin_price)

func _set_stash(id: String, count: int) -> void:
	var next := maxi(0, count)
	if next == stash(id):
		return
	_stash[id] = next
	SaveManager.set_section_fields(STASH_SECTION, {id: next})
	stash_changed.emit(id, next)

# --- Ledger -------------------------------------------------------------------

## The recent transactions, newest first: [{currency, amount, reason, at}, …].
## `amount` is signed — negative is a spend — so the Shop can render one list
## without needing two shapes.
func ledger() -> Array:
	var sec := SaveManager.get_section(LEDGER_SECTION, {})
	var entries: Array = sec.get("entries", [])
	return entries

## Records one transaction. Silent for an unexplained move: a credit with no
## reason is almost always a test or a restore path, and listing it as a blank
## row would be worse than omitting it.
func _log(currency: String, signed_amount: int, reason: String) -> void:
	if reason.is_empty():
		return
	var sec := SaveManager.get_section(LEDGER_SECTION, {})
	var entries: Array = sec.get("entries", [])
	entries.push_front({
		"currency": currency,
		"amount": signed_amount,
		"reason": reason,
		"at": _now(),
	})
	if entries.size() > LEDGER_MAX:
		entries.resize(LEDGER_MAX)
	SaveManager.set_section(LEDGER_SECTION, {"entries": entries})

func _now() -> int:
	return int(Time.get_unix_time_from_system())

# --- Persistence --------------------------------------------------------------

## Field-merge rather than a whole-section replace: the section is small, but
## this keeps any key a later pass adds (lifetime earned, last shop visit) from
## being wiped by a balance write that predates it.
##
## The merge is also what leaves a pre-removal save's dead "energy" / "energy_at"
## fields sitting harmlessly in the section: nothing reads them and
## `WalletRules.ALL` no longer lists energy, so they are inert — which is a
## better answer than a migration that can only ever go wrong on a real save.
func _store() -> void:
	SaveManager.set_section_fields(SECTION, _purse.duplicate())
