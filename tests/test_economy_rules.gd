extends "res://regression/headless/harness/script_test_base.gd"
## Headless unit tests for EconomyRules — every payout, price and brake.
##
## Run:  godot --headless --path . --script res://regression/headless/harness/headless_boot.gd -- --test=res://tests/test_economy_rules.gd
##
## Pure data — no autoloads, no clock — so every branch is exercised directly and
## the boundaries (the daily soft cap, the undo price ceiling, the streak
## flattening) are pinned at their exact values rather than "about right". The
## rates themselves are a design decision and may be retuned; what must not
## change silently is the SHAPE — depth pays more than repetition, the cap
## halves rather than zeroes, prices escalate, and premium is never consulted.

func run_tests() -> void:
	_test_run_payout_base()
	_test_run_payout_bonuses()
	_test_mode_multiplier()
	_test_daily_soft_cap()
	_test_streak_payout()
	_test_first_tile_gems()
	_test_tile_milestone_ladder()
	_test_undo_price_ladder()
	_test_upgrades()
	_test_no_mode_costs_anything_to_start()
	_test_shape_invariants()

# --- Base payout --------------------------------------------------------------
func _test_run_payout_base() -> void:
	print("test_run_payout_base:")
	# score/SCORE_PER_COIN, floored.
	var a: Dictionary = EconomyRules.run_payout("classic", 0, false, 0, false, 0)
	check_eq("a zero score pays nothing", int(a["coins"]), 0)
	var b: Dictionary = EconomyRules.run_payout("classic",
		EconomyRules.SCORE_PER_COIN - 1, false, 0, false, 0)
	check_eq("just under one coin's worth pays nothing", int(b["coins"]), 0)
	var c: Dictionary = EconomyRules.run_payout("classic",
		EconomyRules.SCORE_PER_COIN, false, 0, false, 0)
	check_eq("exactly one coin's worth pays 1", int(c["coins"]), 1)
	var d: Dictionary = EconomyRules.run_payout("classic", 10_000, false, 0, false, 0)
	check_eq("10k pays 10000/250", int(d["coins"]), 40)
	# A negative score cannot become a credit or a debit.
	var neg: Dictionary = EconomyRules.run_payout("classic", -5000, false, 0, false, 0)
	check_eq("a negative score pays nothing", int(neg["coins"]), 0)

	# THE CAP ON THE TAIL: a marathon run cannot outpay a week of play.
	var huge: Dictionary = EconomyRules.run_payout("classic",
		EconomyRules.SCORE_PER_COIN * 100_000, false, 0, false, 0)
	check_eq("the base payout is capped", int(huge["base"]), EconomyRules.RUN_BASE_CAP)

func _test_run_payout_bonuses() -> void:
	print("test_run_payout_bonuses:")
	var won: Dictionary = EconomyRules.run_payout("classic", 0, true, 0, false, 0)
	check_eq("a win alone pays WIN_BONUS", int(won["coins"]), EconomyRules.WIN_BONUS)
	var first: Dictionary = EconomyRules.run_payout("classic", 0, false, 0, true, 0)
	check_eq("the day's first run pays FIRST_RUN_OF_DAY",
		int(first["coins"]), EconomyRules.FIRST_RUN_OF_DAY)
	var depth: Dictionary = EconomyRules.run_payout("classic", 0, false, 3, false, 0)
	check_eq("three new best tiles pay 3x the depth bonus",
		int(depth["coins"]), 3 * EconomyRules.NEW_BEST_BONUS)
	var neg_depth: Dictionary = EconomyRules.run_payout("classic", 0, false, -4, false, 0)
	check_eq("a negative depth count cannot pay out", int(neg_depth["coins"]), 0)
	# Everything stacks, and `base`/`bonus` itemise it for the game-over line.
	var all: Dictionary = EconomyRules.run_payout("classic", 2500, true, 1, true, 0)
	check_eq("base is itemised separately", int(all["base"]), 10)
	check_eq("bonus is itemised separately", int(all["bonus"]),
		EconomyRules.WIN_BONUS + EconomyRules.FIRST_RUN_OF_DAY
			+ EconomyRules.NEW_BEST_BONUS)
	check_eq("coins is base + bonus", int(all["coins"]),
		int(all["base"]) + int(all["bonus"]))

	# DEPTH BEATS REPETITION — the anti-restart-farm rule, stated as a test.
	# One run that built a new tile must beat the same score with nothing new.
	var deep: Dictionary = EconomyRules.run_payout("classic", 2500, false, 1, false, 0)
	var flat: Dictionary = EconomyRules.run_payout("classic", 2500, false, 0, false, 0)
	check("a run that broke new ground pays more than one that did not",
		int(deep["coins"]) > int(flat["coins"]))

func _test_mode_multiplier() -> void:
	print("test_mode_multiplier:")
	check_eq("an unlisted mode multiplies by 1", EconomyRules.mode_multiplier("classic"), 1.0)
	check_eq("Classic is the baseline the others are measured against",
		EconomyRules.mode_multiplier("classic"), 1.0)
	# FLING IS BACK ON THE BASELINE, and that is load-bearing rather than cosmetic.
	# Its 1.5 bought the game's fastest, most forgiving board a premium rate on the
	# strength of energy capping how many runs a day could hold. Energy is gone;
	# a multiplier above 1.0 here would make Fling the only rational way to earn,
	# with nothing left to bound it but the daily soft cap.
	check_eq("Fling pays at the baseline, now that nothing meters it",
		EconomyRules.mode_multiplier("arena_fling"), 1.0)

	# The multiplier applies to the BASE only — a win is worth the same everywhere,
	# or the "best" mode would quietly become the only one worth winning in. Checked
	# against a mode that IS corrected, so the assertion has a real difference to
	# find rather than comparing a mode to itself.
	var grid: Dictionary = EconomyRules.run_payout("classic", 2500, true, 0, false, 0)
	var slow: Dictionary = EconomyRules.run_payout("fog", 2500, true, 0, false, 0)
	check_eq("the win bonus is mode-independent",
		int(grid["bonus"]), int(slow["bonus"]))
	check("Blind's base is the multiplied one",
		int(slow["base"]) > int(grid["base"]))

	# The rate corrections (tools/mode_economy_sim.gd measured every board under
	# one policy; see MODE_MULTIPLIER for the table). These are DIRECTIONS, pinned
	# as inequalities rather than as the exact numbers, so a retune is free but a
	# sign flip — the thing that would break the economy — is not.
	check("Blind pays MORE per point: a board you cannot see takes minutes",
		EconomyRules.mode_multiplier("fog") > 1.0)
	check("Classic is the baseline", is_equal_approx(EconomyRules.mode_multiplier("classic"), 1.0))
	# Rush is deliberately un-corrected. It already pays per board CLEARED, so a
	# long run and a short one are priced by the same number of boards and there
	# is no series length left for a multiplier to correct for.
	check_eq("Rush stays at the baseline", EconomyRules.mode_multiplier("sprint"), 1.0)
	check("an unknown mode pays the baseline", is_equal_approx(EconomyRules.mode_multiplier("nope"), 1.0))
	# Nothing may be so extreme that a mode becomes the only rational way to earn.
	for mode_id: String in EconomyRules.MODE_MULTIPLIER.keys():
		var mult: float = EconomyRules.mode_multiplier(mode_id)
		check("%s's multiplier is inside the sane band (%.2f)" % [mode_id, mult],
			mult >= 0.5 and mult <= 2.0)
	# A multiplier keyed to a mode that does not exist is dead tuning that reads as
	# live tuning — the kind of thing that is only ever found by looking.
	for mode_id: String in EconomyRules.MODE_MULTIPLIER.keys():
		check("multiplier '%s' names a real mode" % mode_id,
			GameModes.get_mode(mode_id).id == mode_id)

# --- The brakes ---------------------------------------------------------------
func _test_daily_soft_cap() -> void:
	print("test_daily_soft_cap:")
	var under: Dictionary = EconomyRules.run_payout("classic", 2500, false, 0, false,
		EconomyRules.DAILY_SOFT_CAP - 1)
	check("one coin below the cap is not halved", not bool(under["halved"]))
	check_eq("under the cap pays in full", int(under["coins"]), 10)
	# EXACTLY at the cap already bites — the boundary is >=, and a test that only
	# probed "well past" would let an off-by-one through.
	var at: Dictionary = EconomyRules.run_payout("classic", 2500, false, 0, false,
		EconomyRules.DAILY_SOFT_CAP)
	check("exactly at the cap is halved", bool(at["halved"]))
	check_eq("at the cap pays half", int(at["coins"]), 5)
	# HALVED, NEVER ZEROED: a run that pays nothing reads as a bug, not a limit.
	var far: Dictionary = EconomyRules.run_payout("classic", 100_000, true, 2, true,
		EconomyRules.DAILY_SOFT_CAP * 100)
	check("a run far past the cap still pays something", int(far["coins"]) > 0)
	# A negative running total cannot be used to dodge the cap.
	var neg: Dictionary = EconomyRules.run_payout("classic", 2500, false, 0, false, -99999)
	check("a negative daily total does not trip the cap", not bool(neg["halved"]))

func _test_streak_payout() -> void:
	print("test_streak_payout:")
	check_eq("day 0 pays nothing", EconomyRules.streak_payout(0), 0)
	check_eq("day 1 pays one step", EconomyRules.streak_payout(1),
		EconomyRules.STREAK_COIN_STEP)
	check_eq("day 7 pays seven steps", EconomyRules.streak_payout(7),
		EconomyRules.STREAK_COIN_STEP * 7)
	# FLATTENS past the max day: a 200-day streak is a habit, not an income.
	check_eq("day 200 pays the same as day 7",
		EconomyRules.streak_payout(200), EconomyRules.streak_payout(7))
	check_eq("a negative day pays nothing", EconomyRules.streak_payout(-3), 0)

func _test_first_tile_gems() -> void:
	print("test_first_tile_gems:")
	check_eq("2048 pays gems", EconomyRules.first_tile_gems(2048), 25)
	check_eq("4096 pays more", EconomyRules.first_tile_gems(4096), 50)
	check_eq("8192 pays most", EconomyRules.first_tile_gems(8192), 100)
	check_eq("an ordinary tile pays no gems", EconomyRules.first_tile_gems(256), 0)
	check_eq("tile 0 pays no gems", EconomyRules.first_tile_gems(0), 0)
	# The ladder must ASCEND — a bigger tile paying less would be absurd.
	check("the first-tile ladder ascends",
		EconomyRules.first_tile_gems(2048) < EconomyRules.first_tile_gems(4096) \
			and EconomyRules.first_tile_gems(4096) < EconomyRules.first_tile_gems(8192))

# --- Prices -------------------------------------------------------------------
# --- The toy's payout ---------------------------------------------------------
## The repeatable milestone ladder that the boards which CANNOT END pay instead
## of a survival bonus. See EconomyRules.TILE_MILESTONE_MIN.
##
## Every assertion here is a SHAPE, not a rate: the rungs may be retuned, but a
## mode that is not on the list must never pay, a value below the floor must never
## pay, and the ladder must never go down — each of which would be silent money.
func _test_tile_milestone_ladder() -> void:
	print("test_tile_milestone_ladder:")
	# THE GATE. A board that can be lost already prices height through the win
	# bonus and NEW_BEST_BONUS; paying this as well would pay twice, and it
	# would do so invisibly, since nothing on screen names which lever paid.
	# NOBODY IS ON THE LIST, and that is the assertion. Orbit was the last mode
	# on it, as a sphere of sliding tiles that could not jam; it is a board of 32
	# faces that fills in 32 placements now, so it is paid for like every other
	# board and paying it twice would be silent money.
	check("no mode pays tile milestones", EconomyRules.TILE_MILESTONE_MODES.is_empty())
	for mode_id: String in ["classic", "sprint", "lock", "twist", "fog"]:
		check_eq("%s pays no tile milestone" % mode_id,
			EconomyRules.tile_milestone_coins(mode_id, 4096), 0)
	check_eq("an unknown mode pays nothing",
		EconomyRules.tile_milestone_coins("_nope", 4096), 0)
	# THE FLOOR. Everything under 2048 is the ordinary run of play and is paid for
	# by the run payout; only the headline tiles reach this ladder.
	check_eq("1024 is below the floor",
		EconomyRules.tile_milestone_rung_coins(1024), 0)
	check_eq("zero pays nothing", EconomyRules.tile_milestone_rung_coins(0), 0)
	check_eq("a negative value pays nothing",
		EconomyRules.tile_milestone_rung_coins(-4096), 0)
	# NON-POWERS OF TWO pay nothing. The bug this guards is a caller passing a
	# SCORE where a tile value belongs — which is always a huge number, and would
	# otherwise be paid as if it were the top of the ladder.
	check_eq("a score-shaped number is not a rung",
		EconomyRules.tile_milestone_rung_coins(31337), 0)
	check_eq("3000 is not a rung",
		EconomyRules.tile_milestone_rung_coins(3000), 0)
	# THE LADDER ITSELF: doubling from the base at the floor.
	check_eq("2048 pays the base",
		EconomyRules.tile_milestone_rung_coins(2048),
		EconomyRules.TILE_MILESTONE_BASE)
	check_eq("4096 doubles",
		EconomyRules.tile_milestone_rung_coins(4096),
		EconomyRules.TILE_MILESTONE_BASE * 2)
	check_eq("8192 doubles again",
		EconomyRules.tile_milestone_rung_coins(8192),
		EconomyRules.TILE_MILESTONE_BASE * 4)
	check_eq("16384 doubles again",
		EconomyRules.tile_milestone_rung_coins(16384),
		EconomyRules.TILE_MILESTONE_BASE * 8)
	# MONOTONIC, and worth its own assertion because the shift that builds the
	# rung is exactly the kind of arithmetic that wraps into a negative if the
	# ladder is ever extended without thinking about the width.
	var prev := 0
	var rising := true
	var v := EconomyRules.TILE_MILESTONE_MIN
	for _i in range(12):
		var c := EconomyRules.tile_milestone_rung_coins(v)
		if c <= prev:
			rising = false
			break
		prev = c
		v *= 2
	check("the milestone ladder climbs and never wraps", rising)
	# The base is worth having: a rung that paid less than a sweep would not be a
	# reward, and this is the mode's ONLY repeatable payout.
	check("the base rung beats a sweep",
		EconomyRules.TILE_MILESTONE_BASE > EconomyRules.SWEEP_PRICE)

func _test_undo_price_ladder() -> void:
	print("test_undo_price_ladder:")
	check_eq("there is no 0th paid undo", EconomyRules.undo_price(0), 0)
	check_eq("a negative nth costs nothing", EconomyRules.undo_price(-2), 0)
	check_eq("the first paid undo is the base price",
		EconomyRules.undo_price(1), EconomyRules.UNDO_BASE_PRICE)
	check_eq("the second doubles", EconomyRules.undo_price(2),
		EconomyRules.UNDO_BASE_PRICE * 2)
	check_eq("the third doubles again", EconomyRules.undo_price(3),
		EconomyRules.UNDO_BASE_PRICE * 4)
	# CAPPED, and the cap must hold however deep the run goes — an uncapped shift
	# would overflow into nonsense prices.
	check_eq("the ladder caps", EconomyRules.undo_price(50),
		EconomyRules.UNDO_MAX_PRICE)
	check("the cap is never exceeded",
		EconomyRules.undo_price(9999) <= EconomyRules.UNDO_MAX_PRICE)
	# Monotonic: a later undo in a run is never CHEAPER than an earlier one.
	var prev := 0
	var rising := true
	for n in range(1, 30):
		var p := EconomyRules.undo_price(n)
		if p < prev:
			rising = false
			break
		prev = p
	check("the undo ladder never goes down", rising)

func _test_upgrades() -> void:
	print("test_upgrades:")
	check_eq("an unknown upgrade has no price", EconomyRules.upgrade_price("nope"), 0)
	check_eq("an unknown upgrade has no levels", EconomyRules.upgrade_max_level("nope"), 0)
	# An unknown upgrade must read as ALREADY MAXED, or a typo'd id becomes a
	# free, infinitely-buyable nothing.
	check("an unknown upgrade is maxed at level 0",
		EconomyRules.upgrade_maxed("nope", 0))
	for id: String in EconomyRules.UPGRADES.keys():
		check("%s has a positive price" % id, EconomyRules.upgrade_price(id) > 0)
		check("%s has at least one level" % id, EconomyRules.upgrade_max_level(id) > 0)
		check("%s is not maxed at level 0" % id, not EconomyRules.upgrade_maxed(id, 0))
		check("%s is maxed at its max level" % id,
			EconomyRules.upgrade_maxed(id, EconomyRules.upgrade_max_level(id)))
		var def: Dictionary = EconomyRules.UPGRADES[id]
		check("%s has a title" % id, not String(def.get("title", "")).is_empty())
		check("%s has a detail line" % id, not String(def.get("detail", "")).is_empty())
	# Every upgrade must attach to a REAL spend site. "Energy Cap" was removed with
	# the currency it widened, and the failure mode it leaves behind is an upgrade
	# that still sells but changes nothing — gems taken for a promise no code
	# keeps. Pinned by id, because that is the only handle a catalogue entry has.
	check("the retired energy cap upgrade is gone",
		not EconomyRules.UPGRADES.has("energy_cap"))

## NO MODE COSTS ANYTHING TO START, and this file is where that is a RULE rather
## than an accident of nobody having written a charge yet.
##
## There used to be exactly one: `EconomyRules.mode_costs_energy` answered true
## for Fling and Progression.begin_run charged a point before letting the run
## begin. The whole predicate is gone, and its absence is the assertion — a
## start-cost reintroduced anywhere would need a rule to live in, and the rules
## file no longer has a place to put one.
func _test_no_mode_costs_anything_to_start() -> void:
	print("test_no_mode_costs_anything_to_start:")
	# The catalogue holds prices for SINKS (undo, revert, revive, Tower swaps,
	# packs, upgrades) and payouts for earning. Not one of them is keyed to a mode
	# id, which is what makes "free to start" structural rather than a promise.
	for mode: GameModes.Mode in GameModes.all():
		check("no bundle is priced against the mode '%s'" % mode.id,
			not EconomyRules.BUNDLES.has(mode.id))
		check("no upgrade is priced against the mode '%s'" % mode.id,
			not EconomyRules.UPGRADES.has(mode.id))
	# The multiplier is the only per-mode number left, and it SCALES a payout —
	# it can never be a charge, whatever it is retuned to.
	for mode_id: String in EconomyRules.MODE_MULTIPLIER.keys():
		check("the '%s' multiplier pays out rather than charging" % mode_id,
			EconomyRules.mode_multiplier(mode_id) > 0.0)
	# A zero-score run pays zero and never a negative — the arithmetic proof that
	# finishing a run cannot leave a player poorer than starting it.
	for mode: GameModes.Mode in GameModes.all():
		var nothing: Dictionary = EconomyRules.run_payout(mode.id, 0, false, 0, false, 0)
		check_eq("a scoreless %s run pays exactly zero" % mode.id,
			int(nothing["coins"]), 0)

# --- Shape --------------------------------------------------------------------
## The invariants that make the economy coherent, independent of the exact rates.
func _test_shape_invariants() -> void:
	print("test_shape_invariants:")
	# COINS ARE THE HIGH-VOLUME CURRENCY, GEMS THE SCARCE ONE. If a badge ever
	# paid more gems than a theme costs, gems would stop being a decision.
	var cheapest := 999999
	for id in Entitlements.SHOP_THEMES:
		cheapest = mini(cheapest, Entitlements.theme_price(String(id)))
	check("no theme is affordable from a single badge",
		EconomyRules.GEMS_PER_BADGE < cheapest)

	# THE LIFETIME GEM SUPPLY MUST COVER THE CATALOGUE. A shop a completionist
	# cannot finish is a broken promise; one they finish trivially has no ladder.
	# Badge payouts alone are the floor of the supply.
	var badges := 12   # the legacy map is 1:1 with the shop, and every badge pays
	var shop_total := 0
	for id in Entitlements.SHOP_THEMES:
		shop_total += Entitlements.theme_price(String(id))
	check("the shop costs more than the badges that pay for it",
		shop_total > badges * EconomyRules.GEMS_PER_BADGE)

	# A REVIVE MUST COST MORE THAN A RUN PAYS, or dying becomes profitable.
	var best_run: Dictionary = EconomyRules.run_payout("classic", 999_999, true, 1, true, 0)
	check("a revive costs more than a typical run pays",
		EconomyRules.REVIVE_PRICE > int(EconomyRules.run_payout(
			"classic", 5000, false, 0, false, 0)["coins"]))
	check("even an exceptional run does not trivially fund a revive",
		int(best_run["coins"]) < EconomyRules.REVIVE_PRICE * 3)

	# REWIND FIVE MUST BEAT BUYING FIVE UNDOS ONE AT A TIME, or nobody would ever
	# use it and the price would be decoration.
	var five_singles := 0
	for n in range(1, EconomyRules.REVERT_5_STEPS + 1):
		five_singles += EconomyRules.undo_price(n)
	check("rewinding five is cheaper than five escalating undos",
		EconomyRules.REVERT_5_PRICE < five_singles)

	# The ad allowance must be finite, or "watch an ad" becomes an infinite faucet.
	check("ad coins are capped per day", EconomyRules.MAX_AD_COINS_PER_DAY > 0)
	check("an ad pays less than a revive costs",
		EconomyRules.COINS_PER_AD < EconomyRules.REVIVE_PRICE)
