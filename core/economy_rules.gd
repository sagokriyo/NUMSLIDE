class_name EconomyRules
extends RefCounted
## EconomyRules — every number in the coin/gem economy: what play pays out, what
## each sink costs, and where the anti-farm brakes sit.
##
## Zero node/UI/autoload dependencies, exactly like GameBoard, GameModes and
## WalletRules, so every branch is unit-testable without booting a screen or
## waiting on a clock — callers pass the day's running total in rather than
## having this read a save. `Progression` owns WHEN these are called; `Wallet`
## owns the balances; this file owns HOW MUCH, and it is the only place to
## retune. WalletRules is its sibling: that one is the purse's plumbing (what a
## balance may hold), this one is the economy's policy.
##
## THE SHAPE, in one line: coins buy consumables, gems buy permanent things.
##
## Coins come from everything and are spent constantly (undo, revert, revive,
## Tower swaps). Gems come only from milestones — badges, constellations, first
## sight of a big tile — and buy things you keep forever (shop themes, permanent
## upgrades).
##
## NO MODE COSTS ANYTHING TO START. There used to be a third currency, energy,
## which Fling alone charged one of per run — a faucet limiter on the fastest
## earner in the game. It is gone, and with it the only thing in the app that
## could answer "can I play right now?" with no. The brake it provided now comes
## entirely from DAILY_SOFT_CAP, which halves payouts rather than refusing play:
## a limit on what a day can EARN, never on what a day can PLAY.
##
## TIER-NEUTRAL BY DESIGN. Nothing here asks whether the player is premium, and
## nothing may be added that does. Premium buys unlimited undo, no ads, and the
## premium themes/modes; if it ALSO multiplied payouts, every price below would
## be zero for exactly the people who paid, and the economy would be dead weight
## for them. Keep the two systems disjoint.

# =============================================================================
# EARNING — coins
# =============================================================================

## Score needed per coin from the base payout. The divisor is deliberately
## coarse: a run's coins should track how FAR the player got, not tick up
## visibly as the score does.
const SCORE_PER_COIN := 250
## The most a single run's base payout can pay, before bonuses. Caps the tail on
## a marathon Classic run so a six-hour session cannot outpay a week of play.
const RUN_BASE_CAP := 200
## Reaching the mode's win target.
const WIN_BONUS := 100
## Each tile value the player has NEVER built before, in any mode. This is the
## anti-restart-farm lever: depth pays, repetition does not.
const NEW_BEST_BONUS := 25
## The day's first finished series, any board.
const FIRST_RUN_OF_DAY := 50
## The FIRST time each mode's win target is ever reached — once per mode, for
## life. Deliberately large: this is the nudge that gets a player who has settled
## into one mode to finish another, which is worth more than any daily payout.
const FIRST_CLEAR_BONUS := 200

# =============================================================================
# THE SERIES SCORE — what a finished series is worth in points
# =============================================================================

## Points one round win is worth on the series score. The score is what
## `run_payout` turns into coins (score / SCORE_PER_COIN), what the per-mode
## record keeps, and what the Best Series boards rank, so it lives here with the
## rest of the numbers rather than in the conductor.
const ROUND_POINTS := 100

## What each GRADE adds to a solved board. The ladder pays for precision:
## Steady is "you finished" and pays nothing, Perfect means you barely wasted a
## move and pays the most. A board finished with the solver's help ("assisted")
## pays a token bonus, so asking for the answer still banks something without
## out-earning a run the player actually read.
##
## Every grade id in `Pace.LADDER` must be here, plus Pace.ASSISTED; the
## progression suite fails when the two drift.
const PACE_BONUS := {"steady": 0, "sharp": 60, "expert": 180, "perfect": 450, "assisted": 40}

## Coins for building 2048, and every doubling above it, PAID EVERY TIME — in the
## modes listed below and nowhere else.
##
## WHY THIS EXISTS. Orbit is a TOY, and that is a decision rather than an
## oversight: a sphere of 32 faces with five or six neighbours each never jams, so
## the run cannot end and the player banks whenever they choose to stop (see
## GameModes.Mode.mastery_target and scenes/orbit/orbit.gd). Which makes every
## other coin payout in this file the wrong shape for it. `run_payout`'s base pays
## for how far a run got before something stopped it, and on a board that cannot
## stop anyone that is a reward for patience — the player who taps longest wins,
## which is not a game. This pays for the one thing on an unloseable board that is
## still an accomplishment: how HIGH you built.
##
## REPEATABLE ON PURPOSE, which every other large number in this file is not. The
## first 2048 already pays FIRST_CLEAR_BONUS and first_tile_gems, once for life;
## the second pays nothing, and for a mode with an ending that is right, because
## the run itself was the risk. A toy has no risk to price, so its loop has to be
## "come back, build something big, get paid" or it is a one-evening novelty.
##
## THE LADDER DOUBLES, which makes it rate-FLAT rather than generous. Each rung
## takes roughly twice the play of the one below, so an hour of Orbit pays about
## the same whether it ends at 2048 or at 8192. Depth is rewarded; sitting on the
## same board past the point of interest is not paid twice for it.
##
## THE BRAKE, and read this before adding a mode below. A repeatable payout on a
## board that CANNOT END is the only faucet in this economy with no natural stop
## — every other one is bounded by something (a run has to end, a mode is
## first-cleared once, a day holds three bounties). So this is the one payout that
## halves ITSELF past DAILY_SOFT_CAP, at its own call site in
## `Progression._pay_tile_milestones`. Everything routed through
## `_credit_from_play` merely counts against the cap; for this, counting is not
## enough.
const TILE_MILESTONE_MIN := 2048
## What the 2048 rung pays. Each rung above it doubles: 4096 pays 500, 8192 pays
## 1000. Sized against the things coins actually buy — one 2048 is a revive
## (REVIVE_PRICE) with change, and about a fifth of DAILY_SOFT_CAP.
const TILE_MILESTONE_BASE := 250
## The modes that pay for height instead of for survival, i.e. the ones whose
## board cannot end. Adding an id here is a product decision, not a tuning tweak:
## on a board that CAN be lost, `run_payout`'s win bonus and NEW_BEST_BONUS
## already price this exact thing, and paying it again would pay twice.
##
## EMPTY, and that is the correct answer for this game. It is 2048's lever, and
## the one mode still on it was Orbit, back when Orbit was a sphere of sliding
## tiles with five or six neighbours a face and therefore no way to jam. Orbit
## is a sliding puzzle now: a board that cannot jam is a board that cannot end
## ends it long before that, so it is priced by the same win bonus as every
## other board. The lever is kept because it is pure and tested and the next
## endless board will want it; nothing calls it while this list is empty.
const TILE_MILESTONE_MODES: Array[String] = []

## Per-mode payout multipliers, applied to the BASE payout only (never to
## bonuses — a win is worth the same everywhere). Any mode absent here is 1.0.
##
## WHAT THIS LEVER IS FOR. The base payout is score / SCORE_PER_COIN, and score
## rates differ by BOARD, not by effort: `tools/mode_economy_sim.gd` plays every
## mode's pure core under one greedy policy and reports score per move. Measured
## (20 games, runs played to their natural jam where a board can jam):
##
##   classic 4x4     12.3      challenger 5x5   18.1      grand 6x6      ~16.5*
##   hex 19 cells    17.5      antimatter 4x4    5.9      orbit 32 faces 18.4*
##   cube 2/3/4/5    16.9* / 8.3 / 15.0* / 9.4*  (average across the four ~12.4)
##
## (* measured against a move cap the run had not yet reached, so those are
## floors — the rate climbs as tiles grow. Grand and the solids are expensive to
## play to a true jam; the corrected modes below are all natural endings.)
##
## The multiplier corrects a board's rate back toward Classic's — but ONLY for
## modes whose win target does not already price the board in. Challenger and
## Grand out-earn Classic per move and are left alone deliberately: they also
## demand 4096 and 8192, so their coins-per-goal is already honest. The modes
## that keep Classic's 2048 on a board that plays nothing like Classic's are the
## ones that need correcting, and they are exactly the ones added last.
##
##   * antimatter 2.0 — the same 4x4, the same swipe, the same 2048 goal, and
##     LESS THAN HALF the score per move: an annihilation clears two tiles and
##     pays nothing for them. Uncorrected, the hardest board in the game pays the
##     least, which is the one outcome an economy must never produce.
##   * hex 0.7 — a swipe board like Classic's (so per-move really is per-minute
##     here) running 42% hotter on 19 cells, for the same 2048.
##   * orbit 0.7 — the highest rate measured, on the one board that CANNOT END.
##     Every other mode risks a run; Orbit banks whenever the player chooses to
##     stop. Rate parity and zero risk point the same way.
##
## Cube is deliberately absent, i.e. 1.0: its rate swings with the size the
## player picks (2x2x2 is the fastest board in the game, 3x3x3 is slower than
## Classic) and averages out at Classic's, while the payout formula only ever
## sees the mode id — a per-size rate would have to be threaded through the
## funnel, and the daily soft cap already bounds the 2x2x2 tail.
##
## Fling sits at 1.0 — i.e. it is absent below — and that is a CONSEQUENCE of
## removing energy, not an independent retune. Its 1.5 was never a rate
## correction: Fling is short and forgiving and was allowed to pay best per
## minute *because* energy capped how many Fling runs a day could contain. The
## multiplier and the energy charge were one decision. Delete the brake and keep
## the bonus and the game's fastest board becomes an unlimited coin faucet —
## exactly the outcome the brake existed to prevent — so the bonus goes with it.
const MODE_MULTIPLIER := {
	# Blind is played without the numbers, so a board takes far longer than the
	# same tray face up; the payout follows the time, not the board count.
	"fog": 1.5,
	# Rush needs no correction: it already pays per board cleared, so a long run
	# and a short one are priced by the same number of boards.
}

## Coins from play in one day, past which payouts HALVE (they never drop to
## zero — a run that pays nothing reads as a bug, not as a limit). Roughly a
## handful of Fling rounds plus a couple of long grid runs.
##
## THE ONLY BRAKE LEFT. With energy gone this is what stops a marathon session
## from outpaying a week; it is deliberately a soft one, because a limit that
## halves a reward is a nudge and a limit that refuses a run is a wall.
##
## WHAT IT MEASURES, exactly, because it used to measure less than it claimed:
## every coin that scales with HOW MUCH IS PLAYED — the end-of-run payout, the
## streak coins riding on it, the Tower star bonus, and the first-clear bonus.
## `Progression._credit_from_play` is the one door they all go through now; the
## star bonus in particular skipped it, and Tower puts no limit on how many stars
## a session can birth.
##
## What it deliberately does NOT measure: bounty claims and rewarded-ad coins.
## Both are fixed daily allowances that already bound themselves (three tasks a
## day, MAX_AD_COINS_PER_DAY ads a day), so neither grows by playing longer —
## which is the only thing this constant exists to answer.
const DAILY_SOFT_CAP := 1200
## What a payout is multiplied by once DAILY_SOFT_CAP is passed.
const OVER_CAP_RATE := 0.5

## Escalating coin reward for playing on consecutive days, flattening at day 7
## so a 200-day streak is a habit rather than an income.
const STREAK_COIN_STEP := 25
const STREAK_COIN_MAX_DAY := 7

# =============================================================================
# EARNING — gems (milestones only; never grindable)
# =============================================================================

## Any achievement badge. 22 badges in the catalog (Achievements.DEFS), so this
## is the bulk of a player's lifetime gem supply — 220 of roughly 600 gems.
##
## THE COUNT IS A PRICE. Every badge added hands every player another 10 gems for
## life, against the 415 the full shop costs (Entitlements.SHOP_THEMES), so the
## catalog size and the shop ladder have to be retuned together or the shop
## quietly becomes free. The five mastery rungs added +50 to the supply.
const GEMS_PER_BADGE := 10
## Reaching a 7-day streak — and every 7 days after that, for as long as it holds.
const GEMS_PER_WEEK_STREAK := 15
## How many unbroken days one GEMS_PER_WEEK_STREAK payout costs.
##
## THE ONLY RENEWABLE GEM FAUCET, on purpose. Everything else on this shelf is
## once-per-life: 22 badges, three first tiles, one constellation per seven Tower
## stars. Finish the badge list and the gem supply STOPS — roughly 485 lifetime
## gems against a 575 shop-and-upgrade ladder, so the end-game player is left
## with an unfinished storefront and no road to it, which is the one failure an
## economy cannot recover from.
##
## A week of unbroken play is the slowest faucet that still runs forever, and it
## is the one that cannot be farmed in a sitting: the streak is measured in real
## days, so seven of them cost seven days no matter how much is played inside
## them. See streak_gems() — the day-7 payout used to fire once and never again.
const GEMS_STREAK_EVERY := 7

## The first time — ever, in any mode — the player builds one of these tiles.
## Once each, for life. Keyed by tile value.
const GEMS_FIRST_TILE := {
	2048: 25,
	4096: 50,
	8192: 100,
}

## Gems paid the FIRST time each mode's win target is ever reached — the gem half
## of the first-clear reward, scaled to how hard that particular board is to beat.
##
## ONCE PER MODE, FOR LIFE, and that is what makes it a milestone rather than a
## grind. It rides on exactly the latch `FIRST_CLEAR_BONUS` already uses
## (`Progression._pay_first_clear`), so beating Classic a hundred times pays these
## gems exactly once. That matters more here than anywhere else on this shelf:
## a skilled player can reach 2048 in Classic in twenty minutes, so a per-WIN gem
## payout would be a gem faucet with a tap on it, and the whole "gems come only
## from milestones; never grindable" rule at the top of this file would be a
## comment describing something that used to be true.
##
## WHY IT EXISTS. Winning paid 100 coins and nothing else, in every mode, at every
## difficulty. So the hardest board in the game and the roomiest one handed out
## the same reward for goals that are nothing alike — and the gem economy, which
## needs supply badly (22 badges and three first tiles is 395 gems against a
## catalogue that asks 1,375), took nothing at all from the single most
## significant thing a player ever does.
##
## HOW THE NUMBERS ARE SET. By how hard that mode's OWN target is to reach, which
## is a different question from the score rate `MODE_MULTIPLIER` corrects — and
## the reason this is its own table rather than a reuse of that one. That lever is
## per-move economics measured by `tools/mode_economy_sim.gd`; this one is "how
## big an achievement is finishing this board", which also takes in the win target
## itself, whether the board can be lost, and whether undo exists to lean on.
##
##   15  hex, orbit          — the roomiest boards, 2048 on 19 and 32 cells, and
##                             the highest measured score rates in the game.
##                             Orbit additionally CANNOT end, so its target is
##                             the only one in the game that cannot be failed.
##   20  classic, lattice    — the 4x4 baseline; the lattice is roomy but reading
##                             a 3D board back is its own difficulty.
##   25  merge_drop, fling,  — 2048 with no undo to lean on. Merge Drop and Fling
##       tower                 are physics, Tower is a one-way column drop; a
##                             misplaced tile in any of the three is permanent.
##   30  cube                — 2048 spread across six faces you cannot all see.
##   45  antimatter          — 2048 on a 4x4 where annihilation DESTROYS the
##                             material a run is built from: measured at less
##                             than half Classic's score per move, the lowest
##                             rate of any board.
##   45  challenger          — 4096. One more doubling than the 2048 modes, and
##                             the extra room of a 5x5 does not cover it.
##   70  grand               — 8192, the longest goal in the game.
##
## A mode ABSENT here pays no first-clear gems, which is silent on screen — so
## `test_progression.gd` fails when a winnable mode is missing rather than letting
## a new board ship with half a first clear.
const MODE_WIN_GEMS := {
	# The first board solved on each mode. The plain tray pays the entry rate,
	# the rules that punish a wrong order pay for their minutes, and the solid
	# pays the most.
	"classic": 15,
	"sprint": 20,
	"twist": 25,
	"lock": 30,
	"fog": 45,
}

# =============================================================================
# SPENDING — coins (consumables)
# =============================================================================

## The first PAID undo in a run (i.e. the one after the free budget is spent).
## Each further paid undo in the SAME run doubles, which is what stops a player
## rewinding a whole board for pocket change — see undo_price().
const UNDO_BASE_PRICE := 25
## Ceiling on the doubling, so a very long run cannot reach absurd prices.
const UNDO_MAX_PRICE := 400
## Step back five committed moves at once. Grid modes only — Merge Drop and
## Fling keep no undo history (they are physics, not turns).
const REVERT_5_PRICE := 150
## How many moves "revert" steps back.
const REVERT_5_STEPS := 5
## Carry on from a game over. The economy's main coin drain.
##
## In the grid modes a retry REWINDS the board REVERT_5_STEPS committed moves
## through the run's own history, so the player replays the corner they walked
## into instead of being handed a board they never built. The physics wells keep
## no history and dissolve their lowest bodies instead.
## The Hint helpline, the same shape as every other: a small free budget per
## series, then a flat coin price. Oracle's move, shown on the tray.
## Arena's powers (bomb, swap, freeze, shield): one free per series, then coins.
const FREE_POWERS_PER_SERIES := 1
const ARENA_POWER_PRICE := 25
const FREE_HINTS_PER_SERIES := 1
const HINT_PRICE := 30
## Blitz: extra seconds on the move clock, bought mid-round.
const FREE_TIME_BOOSTS_PER_SERIES := 1
const TIME_BOOST_PRICE := 20
const TIME_BOOST_SECONDS := 3.0

const REVIVE_PRICE := 250
## Retries one run may take, in every mode. A retry is a purchase, never a free
## budget, so this cap is what keeps a rich purse from replaying the same dead
## board forever: the game-over screen counts it down and stops offering one at
## zero. Counted per run by Progression (continues_left).
const RETRIES_PER_RUN := 3
## One extra Tower ammo swap, once the run's swap budget is empty.
const TOWER_SWAP_PRICE := 40
## Re-deal the incoming Tower piece, once the run's free rerolls are spent.
const TOWER_REROLL_PRICE := 40
## Rerolls a Tower run starts with, free.
##
## A reroll may never be free without limit: TowerGrid re-rolls the deal from a
## seeded stream precisely so undo-and-redrop replays the same tiles rather than
## letting a player shop for a deal. A budget and then a price is that same rule
## enforced with coins instead of with a locked door.
const FREE_TOWER_REROLLS := 1

# =============================================================================
# SPENDING — coins (SWEEP: the helpline every board offers)
# =============================================================================

## SWEEP — dissolve the smallest tiles on the board, mid-run.
##
## The same relief the revive hands out at a game over (`GameBoard.clear_lowest`
## and its three siblings) taken one step EARLIER: while the run can still be
## saved by playing, instead of only after it is already dead.
##
## WHY IT EXISTS. Undo belongs to boards that take turns, so five modes had a
## coin sink and the rest had nothing — Merge Drop, Fling and Orbit could not
## spend a coin at any price, and a mode with no sink is a mode the economy does
## not reach. Sweep is the one helpline every board can honestly offer, because
## every board has a smallest tile.
##
## THE SHAPE is deliberately the one Tower's swaps and the grid's undo already
## have: a small budget FREE every run, then a flat coin price per use. Free-then-
## priced is what makes a helpline part of play rather than a paywall — every
## player meets it, most never pay for it, and a player having a bad run has
## somewhere for their coins to go.
##
## FLAT, not escalating, and that is the whole difference from `undo_price`. An
## undo rewinds a decision, so repeat use has to hurt or a player rewinds a whole
## board for pocket change. A sweep DELETES the player's own smallest tiles,
## which is its own brake: sweeping repeatedly strips the board of the material
## the run is built from. The price does not need to do work the mechanic already
## does — and a flat price is also what lets sweeps be sold in a pack (see
## BUNDLES) without a stash walking past a limit.
const SWEEP_PRICE := 60
## Sweeps a run starts with, free. Same reasoning as the free undo budget: the
## first one is how the player learns the button exists.
const FREE_SWEEPS_PER_RUN := 1

## One more turn of the hex rim, once the run's free spins are spent.
##
## Cheaper than a sweep because it is a smaller favour: a spin rearranges the
## outer ring and DELETES nothing, it is fully undoable, and it cannot by itself
## open a jam the way three dissolved tiles can. It is priced at all because
## "three and then the button dies" was the one helpline in the game that ran out
## with nothing behind it.
const HEX_SPIN_PRICE := 30
## Turns of the hex rim a run starts with, free.
##
## Lives here rather than in the hex screen now that it has a price beside it —
## the screen's own constant said as much ("the day Spin is sold, the number
## moves there"). Three, unchanged: the free allowance is not what is being
## retuned, only what happens after it.
const FREE_HEX_SPINS := 3

# =============================================================================
# SPENDING — coins (consumable bundles, the Shop's coin sink)
# =============================================================================

## Pre-bought consumables, sold in packs.
##
## Every coin price above is charged at the POINT OF USE, which left coins with
## no home in the Shop at all: a player could bank thousands and the storefront
## had nothing to sell them. A bundle is the SAME consumable bought ahead in a
## pack at a discount. The stash is always spent before coins are (see
## `Wallet.use_consumable`), so buying one changes WHEN a player pays and how
## much — never what the game lets them do.
##
## The plain undo is deliberately NOT sold here. Its price doubles per purchase
## within a run (`undo_price`), and that ladder is the only thing stopping a
## player rewinding a whole board for pocket change; a stash spent ahead of it
## would walk straight past the rule it exists to enforce. Everything below is
## FLAT-priced at the point of use, so selling it in advance cannot bend a
## limit — it can only move a payment earlier.
##
## `unit` is what ONE costs at the point of use, and is the very constant the
## spend site charges — so `bundle_saving()` can show a real discount without a
## second copy of the price that could drift. Keep `price` strictly below
## `count * unit` or the pack is a worse deal than buying singly, which the
## suite checks rather than trusts.
## The packs are THIS GAME'S HELPLINES, bought ahead and cheaper than one at a
## time. Every id here is the id the point of use passes to
## `Wallet.use_consumable`, which spends a held one before it charges coins, so
## a pack the Shop sells is a pack the board actually spends. An id that drifts
## from a call site is a pack a player buys and can never use, which is why the
## four ids below are named as constants at the point of use too.
##
## `unit` is what one costs without a pack, so a card can show the saving.
const BUNDLES := {
	"undo": {
		"title": "Undo Pack",
		"detail": "Take a move back, five times.",
		"count": 5, "price": 100, "unit": UNDO_BASE_PRICE,
	},
	"hint": {
		"title": "Hint Pack",
		"detail": "Oracle shows you the move, five times.",
		"count": 5, "price": 120, "unit": HINT_PRICE,
	},
	"time_boost": {
		"title": "Time Pack",
		"detail": "Three more seconds on the clock, five times.",
		"count": 5, "price": 80, "unit": TIME_BOOST_PRICE,
	},
	"power": {
		"title": "Power Pack",
		"detail": "Five powers for Arena: bomb, swap, freeze or shield.",
		"count": 5, "price": 100, "unit": ARENA_POWER_PRICE,
	},
}

# =============================================================================
# SPENDING — gems (permanent)
# =============================================================================

## Permanent, once-per-level upgrades. `price` is per level and `max_level` is
## how many times it may be bought. Shop themes are priced separately, in
## Entitlements.SHOP_THEMES, because they are catalog content rather than
## upgrades.
##
## None of these encroach on a premium capability: +2 undos is not "unlimited
## undo". That boundary is the reason the two systems can coexist.
##
## There were three. "Energy Cap" (hold one more energy for Fling) went with the
## currency it widened; the Shop's Upgrades shelf falls back to the "more coming
## soon" row it already carries rather than being padded with an invented
## product. A new upgrade needs a real spend site to attach to — see
## `extra_undo` and `tower_swap`, both of which have one.
const UPGRADES := {
	"extra_undo": {
		"title": "Extra Undo",
		"detail": "One more free undo in every game.",
		"price": 40, "max_level": 2,
	},
	"extra_hint": {
		"title": "Extra Hint",
		"detail": "One more free hint in every series.",
		"price": 40, "max_level": 2,
	},
}

# =============================================================================
# BADGE COSMETICS
# =============================================================================

## Gem prices for the equippable badge decorations — the frames, nameplates and
## emblem effects a player dresses their rank badge with. The catalogue itself
## (what each one looks like, what it is called) is `BadgeCosmetics`; this file
## holds the NUMBERS, as it does for every other price in the game.
##
## Decoration ONLY, and that is what makes selling it honest: nothing here touches
## a rule, a payout, a difficulty or a helpline, so a locked frame costs a player
## nothing but the look. Priced in gems, so a cosmetic is bought once and kept —
## the same deal shop themes get, and the second real sink the gem economy has.
##
## Tier-neutral like the rest of this file: premium buys no discount here, and a
## cosmetic is never sold for money.
##
## An id ABSENT from this table is not free by accident. It is either one of the
## three starter frames (shipped free, and charging for one now would take a
## decoration off a badge that already wears it) or an achievement-earned title,
## which is paid for in play. `test_badge_cosmetics.gd` fails when the catalogue
## and this table disagree in either direction, so a new cosmetic cannot land
## silently unpriced — or priced without existing.
const COSMETICS := {
	# Frames — drawn AROUND the badge (BadgeCosmetics.FRAME_IDS / TierBadge.FRAMES).
	"frame_laurel": 45,
	"frame_flames": 60,
	"frame_circuit": 60,
	"frame_wings": 80,
	"frame_prism": 80,
	"frame_constellation": 100,
	# Nameplates — the banner the player's name sits on.
	"plate_foil": 35,
	"plate_carbon": 35,
	"plate_aurora": 55,
	"plate_ember": 55,
	# Emblem effects — what the badge itself gives off.
	"effect_embers": 40,
	"effect_shards": 40,
	"effect_pulse": 50,
	"effect_sparks": 65,
}

# =============================================================================
# REWARDED ADS
# =============================================================================

## Coins from a rewarded ad, and the daily allowance. Coins are the only thing
## an ad has ever paid since energy left; the offer sites read these two.
const COINS_PER_AD := 100
const MAX_AD_COINS_PER_DAY := 3

# =============================================================================
# PAYOUT MATH
# =============================================================================

## What a finished run pays, itemised.
##
## Returns {"coins", "base", "bonus", "halved"} plus the three bonuses split out
## individually: {"win", "first_of_day", "new_best"}. The itemisation is not
## decoration: the game-over payout line shows the player exactly why they got
## what they got, the Rewards screen draws one row per line, and `halved` is how
## both know to say "daily bonus reached" rather than leaving them to wonder why
## a good run paid less than a worse one this morning.
##
## The split-out keys are the amounts BEFORE the cap halves them, and `bonus` is
## still their sum — a caller that only wants the old three keys is unaffected.
## The Rewards screen shows the lines as earned and then the halving as its own
## line, because "you earned 350, the cap took 175" is a rule a player can learn
## and "you earned 175" is a number they can only distrust.
##
## `earned_today` is the coins ALREADY banked from play today — the caller
## holds that running total, so this stays pure and the soft cap stays testable
## at its exact boundary.
static func run_payout(mode_id: String, score: int, won: bool,
		new_bests: int, first_of_day: bool, earned_today: int) -> Dictionary:
	var base: int = mini(RUN_BASE_CAP, maxi(0, score) / SCORE_PER_COIN)
	base = int(round(float(base) * mode_multiplier(mode_id)))
	var bests: int = maxi(0, new_bests) * NEW_BEST_BONUS
	var win: int = WIN_BONUS if won else 0
	var opener: int = FIRST_RUN_OF_DAY if first_of_day else 0
	var bonus: int = bests + win + opener
	var total: int = base + bonus
	# The soft cap bites on the WHOLE payout, evaluated against the total banked
	# before this run. A run that straddles the boundary is halved in full rather
	# than split at it — simpler to explain, and the difference is a few coins.
	var halved: bool = maxi(0, earned_today) >= DAILY_SOFT_CAP
	if halved:
		total = int(round(float(total) * OVER_CAP_RATE))
	return {
		"coins": maxi(0, total), "base": base, "bonus": bonus, "halved": halved,
		"win": win, "first_of_day": opener, "new_best": bests,
	}

static func mode_multiplier(mode_id: String) -> float:
	return float(MODE_MULTIPLIER.get(mode_id, 1.0))

## The bonus a won series earns against `pace_id` (0 for an unknown id, so a
## stale save can never pay a bonus nobody priced).
static func pace_bonus(pace_id: String) -> int:
	return int(PACE_BONUS.get(pace_id, 0))

## The series score: ROUND_POINTS per round won, plus the rival's bonus when the
## series was won. A lost series still scores its rounds, so a 2-3 loss to Sage
## is worth more than a 0-3 one. Never negative.
static func series_score(rounds_won: int, won: bool, pace_id: String) -> int:
	var score: int = maxi(0, rounds_won) * ROUND_POINTS
	if won:
		score += pace_bonus(pace_id)
	return score

## Coins `mode_id` pays for building exactly `value`. Doubles per rung from
## TILE_MILESTONE_BASE at TILE_MILESTONE_MIN; 0 for a mode that does not pay
## these, for anything below the first rung, and for a value that is not a power
## of two at all (a corrupted save, or a caller passing a SCORE by mistake — the
## one bug here that would otherwise pay out silently and enormously).
##
## Pure, so the screen showing the milestone and the funnel paying it read the
## same number from the same place and cannot drift apart.
static func tile_milestone_coins(mode_id: String, value: int) -> int:
	if not TILE_MILESTONE_MODES.has(mode_id):
		return 0
	return tile_milestone_rung_coins(value)

## What one rung pays, BEFORE the mode gate. Split out so the ladder's
## arithmetic stays testable while TILE_MILESTONE_MODES is empty: the gate and
## the sums are two separate promises, and an empty list must not be able to
## quietly take the sums out of the suite along with itself.
static func tile_milestone_rung_coins(value: int) -> int:
	if value < TILE_MILESTONE_MIN or (value & (value - 1)) != 0:
		return 0
	var rung: int = 0
	var v: int = TILE_MILESTONE_MIN
	while v < value:
		v *= 2
		rung += 1
	return TILE_MILESTONE_BASE << rung

## Gems for clearing `mode_id` for the FIRST time ever (0 for a mode that pays
## none, and for the unknown ids a stale save can carry).
##
## Deliberately NOT multiplied by anything and NOT touched by the daily soft cap:
## it can fire at most eleven times in a lifetime, so there is nothing here for a
## brake to hold back. See MODE_WIN_GEMS.
static func mode_win_gems(mode_id: String) -> int:
	return int(MODE_WIN_GEMS.get(mode_id, 0))

## Coins for playing on day `day` of a streak. Flat past STREAK_COIN_MAX_DAY.
static func streak_payout(day: int) -> int:
	return STREAK_COIN_STEP * clampi(day, 0, STREAK_COIN_MAX_DAY)

## Gems for reaching day `day` of a streak: GEMS_PER_WEEK_STREAK on every
## GEMS_STREAK_EVERY-th day, nothing on the days between.
##
## The modulo is the renewal. This used to be an equality test against day 7 at
## the call site, which paid a player once for the habit and never again — see
## GEMS_STREAK_EVERY for why that left the end game with no gem income at all.
static func streak_gems(day: int) -> int:
	if day <= 0 or GEMS_STREAK_EVERY <= 0:
		return 0
	return GEMS_PER_WEEK_STREAK if day % GEMS_STREAK_EVERY == 0 else 0

## Gems for building `value` for the first time ever (0 for values that carry no
## first-sight bounty).
static func first_tile_gems(value: int) -> int:
	return int(GEMS_FIRST_TILE.get(value, 0))

# =============================================================================
# PRICING MATH
# =============================================================================

## Price of the `nth` PAID undo within a single run (nth = 1 for the first one
## bought after the free budget runs out). Doubles each time, capped.
##
## The doubling is per-RUN, not lifetime: every run reopens at the base price,
## so the brake shapes one board's decisions without turning into a permanent
## tax on a player who leans on undo.
static func undo_price(nth: int) -> int:
	if nth <= 0:
		return 0
	var steps: int = mini(nth - 1, 8)   # 2^8 already clears the cap; guards overflow
	return mini(UNDO_MAX_PRICE, UNDO_BASE_PRICE * (1 << steps))

## How many tiles one sweep dissolves on a board of `cells` cells.
##
## Scaled to the board, because three tiles is a rescue on a 4x4 and a rounding
## error on a 64-cell lattice. Clamped at BOTH ends, and both ends matter: never
## fewer than three, because a sweep that frees two cells does not open a jam and
## reads as a wasted purchase; never more than six, because a sweep that empties
## a quarter of the board hands the run back rather than helping the player save
## it, and a helpline that plays for you is not help.
##
## Measured against the live boards: classic 16 and hex 19 sweep 3, challenger 25
## and cube 27 sweep 4, orbit 32 sweeps 5, grand 36 sweeps 6, and the 4x4x4
## lattice's 64 clamps to 6.
static func sweep_count(cells: int) -> int:
	return clampi(cells / 6, 3, 6)

## The gem price of one level of `id`, or 0 if the upgrade is unknown.
static func upgrade_price(id: String) -> int:
	var def: Dictionary = UPGRADES.get(id, {})
	return int(def.get("price", 0))

## How many times `id` may be bought (0 for an unknown upgrade).
static func upgrade_max_level(id: String) -> int:
	var def: Dictionary = UPGRADES.get(id, {})
	return int(def.get("max_level", 0))

## True when `level` is already the most of `id` a player may own.
static func upgrade_maxed(id: String, level: int) -> bool:
	return level >= upgrade_max_level(id)

## True when `id` names a gem-priced badge cosmetic.
##
## The question is deliberately "is it PRICED", not "does it exist": a cosmetic
## the catalogue ships free has no entry here, and `Wallet.owns_cosmetic` reads
## exactly that to hand it to everybody.
static func is_cosmetic(id: String) -> bool:
	return COSMETICS.has(id)

## The gem price of cosmetic `id`; 0 when it is free or unknown. `spend` treats a
## zero charge as a success, which is why `Wallet.buy_cosmetic` refuses an
## unpriced id outright instead of leaning on this number.
static func cosmetic_price(id: String) -> int:
	return int(COSMETICS.get(id, 0))

## True when `id` names a consumable sold in packs (see BUNDLES).
static func is_bundle(id: String) -> bool:
	return BUNDLES.has(id)

## How many consumables one pack of `id` holds (0 for an unknown bundle).
static func bundle_count(id: String) -> int:
	var def: Dictionary = BUNDLES.get(id, {})
	return int(def.get("count", 0))

## The coin price of one pack of `id` (0 for an unknown bundle — which `spend`
## treats as free, so `Wallet.buy_bundle` refuses unknown ids outright).
static func bundle_price(id: String) -> int:
	var def: Dictionary = BUNDLES.get(id, {})
	return int(def.get("price", 0))

## What ONE of `id` costs at the point of use, i.e. the price a player pays
## with an empty stash.
static func bundle_unit_price(id: String) -> int:
	var def: Dictionary = BUNDLES.get(id, {})
	return int(def.get("unit", 0))

## Coins saved by buying the pack instead of its contents one at a time. Never
## negative: a pack priced above singles is a catalogue bug, and this reports 0
## rather than advertising a loss as a saving.
static func bundle_saving(id: String) -> int:
	return maxi(0, bundle_count(id) * bundle_unit_price(id) - bundle_price(id))
