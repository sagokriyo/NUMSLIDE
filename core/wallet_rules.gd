class_name WalletRules
extends RefCounted
## WalletRules — the pure arithmetic behind the player's purse: what a balance
## may hold.
##
## Zero node/UI/autoload dependencies, exactly like GameBoard and GameModes, so
## every branch here is unit-testable WITHOUT booting a screen. `Wallet` (the
## autoload) owns persistence and signals and delegates every calculation to
## these statics.
##
## NOTE ON SCOPE: this is the shape of the economy, not its balance — the rates,
## prices and payouts all live in `EconomyRules`. What IS settled here is the
## contract every one of those relies on: balances are non-negative integers.
##
## THE PURSE HOLDS TWO CURRENCIES, and deliberately no more. Energy — a capped,
## wall-clock-refilling third currency that gated Fling runs — was removed
## outright: it is the one balance a player could not earn by playing, so the
## only thing it could do was stop them playing. Nothing here has a ceiling or a
## clock any more, which is why `regen` / `seconds_to_next` / the cap band are
## gone rather than merely unused.

## Currency ids. These double as the keys of the "wallet" save section, so
## renaming one is a save migration, not a rename.
const COINS := "coins"
const GEMS := "gems"
const ALL: Array[String] = [COINS, GEMS]

## Balances are stored as JSON numbers and the save file is plaintext on device,
## so every read passes through here: a hand-edited float, a negative, a string
## or a null all resolve to a sane int rather than propagating into the HUD.
static func sanitize(value: Variant) -> int:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return maxi(0, int(value))
		_:
			return 0

## `value` clamped to what `currency` is allowed to hold. Neither currency has a
## ceiling — only a floor — but every write still goes through here so the ONE
## place that decides what a balance may be stays one place.
static func clamp_balance(_currency: String, value: int) -> int:
	return maxi(0, value)

## m:ss / h:mm:ss for a countdown label. Negative and absurd inputs clamp rather
## than rendering "-1:-3", which is what a drifting device clock would produce.
##
## Still here with the energy clock gone: the Shop's "today's bounties reset in"
## line counts down the same way, and that is a real clock the player reads.
static func format_countdown(seconds: int) -> String:
	var s := maxi(0, seconds)
	var h: int = s / 3600
	var m: int = (s % 3600) / 60
	var sec: int = s % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, sec]
	return "%d:%02d" % [m, sec]
