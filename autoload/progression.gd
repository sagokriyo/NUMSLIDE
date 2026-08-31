extends Node
## Progression — the one funnel every mode reports play through.
##
## In the 2048 code base this replaced, each mode hand-wired its own subset of
## the progression calls and three of the four quietly under-reported. The fix
## was structural rather than more call sites: there is exactly ONE path from
## "something happened in a series" to GameStats / Achievements / best_scores /
## AdManager / Wallet, and the conductor walks it.
##
## The conductor calls four things per series and nothing else:
##   begin_run(mode)                    a series is starting — resets the
##                                      per-run economy counters. Starting is
##                                      free in every mode, so this cannot refuse
##   record_turn()                      one committed move
##   record_undo()                      the player took a move back
##   record_series(mode, won, …)        the series is over — bank everything:
##                                      the score, the per-mode record, the
##                                      crowns, the coins and gems
##
## `record_win`, `record_merges` and `conclude` are the older, finer-grained
## calls the 2048 funnel offered. They still work (the pre-series conductor and
## its flow test walk them), and record_series is built on top of them rather
## than beside them, so the two paths cannot pay differently.
##
## THE ECONOMY HANGS HERE TOO, for the same reason. Coins and gems are paid out
## by the calls above — never by a screen — so a new mode earns correctly by
## walking the same path it already walks for stats and achievements, and no
## mode can quietly pay double or nothing. Wallet holds the balances,
## EconomyRules holds the rates; this file decides WHEN.
##
## This owns POLICY (what a turn means, which rival counts, when a streak is
## evaluated, what counts as a bankable series); GameStats and Achievements stay
## dumb stores underneath it, and keep their own APIs so their regression suites
## are untouched.
##
## Autoload order: AFTER GameStats, Achievements, AdManager and Wallet (it drives
## all four) and after SaveManager; BEFORE SceneRouter. Wallet was moved above
## this autoload when the economy landed — every payout below calls into it, and
## an autoload may only reference those declared before it.

## A board the solver finished for you. It is banked as a game played, but it
## pays and sets NOTHING: no coins, no score, no best, no crown, no mastery,
## no win streak, no grade on the ladder. Matches the conductor's own id and
## the "assisted" key in EconomyRules.PACE_BONUS.
const ASSISTED_RUN := Pace.ASSISTED

## Per-mode best SERIES score, keyed by mode id. One shared store so every mode
## has its own separate record and none can overwrite another's.
const BEST_SECTION := "best_scores"

## Today's economy counters: what has been paid out from play, how many runs
## have finished, and how much of the daily ad allowance is spent. Rolls over on
## the date changing rather than on a timer, so closing the app overnight is the
## same as leaving it open.
const DAILY_SECTION := "economy_daily"

## Today's bounty progress: {date, progress: {id: n}, paid: {id: true}}.
const BOUNTY_SECTION := "bounties"

## The first time each mode's win target was ever reached: {mode_id: unix}. A
## lifetime record, not a daily one — the bonus is a one-off per mode, and it is
## what pushes a player past whichever mode they started in.
const FIRST_CLEARS_SECTION := "first_clears"

# --- Per-run state ------------------------------------------------------------
## Tiles the player has NEVER built before, banked during THIS run. The payout
## rewards depth, so this is the number that separates a genuine climb from a
## restart farm — and it has to be counted as the merges happen, because by the
## time conclude() runs the lifetime stat has already moved.
var _new_bests_this_run := 0
## Retries the run has bought so far. Any at all blocks purity badges and keeps
## the score off the public leaderboard (see conclude) — a bought second life is
## still a fine run, just not a clean one — and the count is what every game-over
## screen counts down against EconomyRules.RETRIES_PER_RUN.
var _continues_used := 0
## The mode of the run in progress, so an earn hook that fires mid-run knows
## which multiplier applies without every call site passing it.
var _run_mode := ""
## The highest tile this run has already been PAID a milestone for (see
## EconomyRules.TILE_MILESTONE_MIN). A high-water mark rather than a set, which is
## what makes the payout un-farmable within a run: rebuild a 2048 after a sweep,
## or merge two 1024s a second time, and the rung is already behind the mark.
var _milestone_top := 0
## The rung most recently paid and what it paid, for the screen that has to SHOW
## it. Orbit has no game over, so it has no Rewards page to route to — the receipt
## line exists, but nothing ever reads it — and a payout the player never sees is
## a payout that did not happen as far as the loop is concerned.
var _last_milestone: Dictionary = {}

## THE RUN'S RECEIPT — every coin and gem this run has paid, itemised in the
## order it was earned. Each entry is {"id", "label", "coins", "gems"}.
##
## Built here rather than on the Rewards screen, and that is the whole point. The
## payouts arrive from six different places at four different moments — a first
## tile mid-merge, a first clear the instant the target is built, a star as it is
## born, a badge through a signal, the run payout and the streak at conclude() —
## and there is no moment at which a screen could stand outside all of them and
## ask "what did that run pay". Progression is already the only thing that sees
## every one, so it is the only thing that can keep the receipt. A screen that
## assembled its own would be a seventh place to forget a line, which is the
## exact failure this autoload exists to prevent.
##
## The Rewards screen takes this with `take_reward()` and it is cleared by the
## next `begin_run()`, so an abandoned run's receipt can never be shown against
## the next one's balances.
var _reward_lines: Array[Dictionary] = []

## Row ids the receipt uses. Named rather than typed inline at six call sites,
## because the Rewards screen picks an icon per id and a typo would silently draw
## the fallback for the rest of the app's life.
const REWARD_RUN := "run"
const REWARD_WIN := "win"
const REWARD_FIRST_OF_DAY := "first_of_day"
const REWARD_NEW_BEST := "new_best"
const REWARD_FIRST_CLEAR := "first_clear"
const REWARD_FIRST_TILE := "first_tile"
const REWARD_TILE_MILESTONE := "tile_milestone"
const REWARD_BADGE := "badge"
const REWARD_STREAK := "streak"
const REWARD_CAPPED := "capped"

func _ready() -> void:
	# Every badge pays gems. Hanging that off the signal rather than off ~30 call
	# sites is the same structural argument this whole autoload exists for: a
	# payout nobody has to remember to write cannot be forgotten by mode #5.
	Achievements.unlocked.connect(_on_badge_unlocked)

# --- Run lifecycle ------------------------------------------------------------
## A run is starting. Resets the per-run economy counters.
##
## STARTING A RUN COSTS NOTHING, in every mode. This used to return a bool —
## false meant "Fling's energy purse is empty, show the out-of-energy modal and
## stay put" — and it was the only way the app could refuse to start a game.
## Energy is gone, so the refusal is gone with it, and the signature says so:
## a bool nobody could ever see as false is an invitation to keep writing dead
## branches against it.
func begin_run(mode_id: String) -> void:
	_new_bests_this_run = 0
	_continues_used = 0
	_run_mode = mode_id
	_milestone_top = 0
	_last_milestone = {}
	# A receipt belongs to ONE run. Clearing it here rather than when it is read
	# is what makes an abandoned run harmless: quit mid-game and the lines simply
	# never get shown, instead of surfacing on the next run's Rewards screen
	# against balances they had nothing to do with.
	_reward_lines.clear()

## A SAVED run is being picked up again. Re-arms the funnel for `mode_id` and
## tells it how high the restored board already stands.
##
## Not `begin_run`, and the difference is the whole reason this exists. A resumed
## run is not a new one: its depth bonus has been accruing since it started, and
## calling begin_run here would zero `_new_bests_this_run` and quietly throw away
## every new-best tile the player built before they closed the app.
##
## `top_tile` is the restored board's highest, and it seeds the milestone
## high-water mark. Without it a resumed run pays its 2048 rung a SECOND time —
## which on a board that cannot end (the only kind that pays these) is not a
## rounding error but a farm: build 2048, leave, resume, merge two 1024s again,
## get paid again, forever. See EconomyRules.TILE_MILESTONE_MIN.
func resume_run(mode_id: String, top_tile: int) -> void:
	_run_mode = mode_id
	_milestone_top = maxi(_milestone_top, maxi(top_tile, 0))
	_last_milestone = {}

## The player bought their way past a game over. Marks the run permanently, which
## is what keeps a purchased second life out of the purity badges, and spends one
## of the run's RETRIES_PER_RUN.
func record_continue() -> void:
	_continues_used += 1

func used_continue() -> bool:
	return _continues_used > 0

## Retries this run can still take. Every mode's game-over screen offers one
## while this is above zero and prints the number; none gates on anything else.
func continues_left() -> int:
	return maxi(0, EconomyRules.RETRIES_PER_RUN - _continues_used)

# --- The run's receipt --------------------------------------------------------
## Adds one line to the run's receipt. Zero-value lines are dropped, so the
## Rewards screen never draws "+0 coins" for a bonus that did not fire.
##
## NEGATIVE lines are kept, and that is not an oversight: the daily cap's cut is
## recorded as what it took (see REWARD_CAPPED), so the receipt can show the full
## earnings and the deduction separately and still total to what was banked.
##
## Called ALONGSIDE the credit, never instead of it: this records what happened,
## `Wallet.add` is what makes it true. Keeping them adjacent at each site is
## deliberate — a receipt assembled later, from the daily counters, would be a
## second opinion about the payout and the two would eventually disagree.
func _note_reward(id: String, label: String, coins: int, gems: int = 0) -> void:
	if coins == 0 and gems == 0:
		return
	_reward_lines.append({"id": id, "label": label, "coins": coins, "gems": gems})

## The run's receipt, and clears it — so a screen rebuild (a theme change on the
## Rewards page) cannot double-count and a second reader gets nothing rather than
## a stale copy. Callers that only want to LOOK use `has_reward()`.
func take_reward() -> Array[Dictionary]:
	var out := _reward_lines.duplicate(true)
	_reward_lines.clear()
	var typed: Array[Dictionary] = []
	for line: Dictionary in out:
		typed.append(line)
	return typed

## True when the finished run paid anything at all. The game-over actions ask
## this before routing to the Rewards screen: a run that scored nothing has no
## receipt, and a celebration page showing an empty ledger is worse than no page.
func has_reward() -> bool:
	return not _reward_lines.is_empty()

## What the un-taken receipt totals, as {"coins": int, "gems": int}. Used by the
## Rewards screen to work out the balances to count UP FROM — the money is
## already banked by the time the page opens, so the animation runs from
## `Wallet.coins() - earned` rather than pretending to credit it a second time.
func reward_totals(lines: Array[Dictionary]) -> Dictionary:
	var coins := 0
	var gems := 0
	for line: Dictionary in lines:
		coins += int(line.get("coins", 0))
		gems += int(line.get("gems", 0))
	return {"coins": coins, "gems": gems}

# --- Per-turn events ----------------------------------------------------------
## One committed turn: a grid swipe that moved something, a Merge Drop release,
## a Fling throw, a Tower drop. Merges are reported separately because the
## physics modes resolve them asynchronously, long after the turn itself.
func record_turn() -> void:
	GameStats.record_move(0)
	_advance_bounties(Bounties.KIND_TURNS, 1)

## `count` tiles fused this turn, the biggest of them becoming `highest_value`.
## Grid modes report once per move (count = merges.size()); the physics modes
## and Tower report once per fuse (count = 1).
##
## Returns true when `highest_value` is a tile the player has NEVER built before
## in any mode. That answer is computed BEFORE the lifetime stat moves, so
## callers get a truthful "first ever" without having to sequence their own
## calls — the grid code used to carry a comment warning about exactly that
## ordering trap.
func record_merges(mode_id: String, count: int, highest_value: int) -> bool:
	if count <= 0:
		return false
	var first_ever: bool = highest_value > int(GameStats.get_stat("highest_tile"))
	GameStats.record_merges(count)
	Achievements.report_solve()
	if highest_value > 0:
		GameStats.note_highest_tile(highest_value)
		Achievements.report_tile_reached(highest_value, mode_id)
	if first_ever:
		# Counted now, paid at conclude() — the run's depth bonus. Doing it here is
		# the only place the "never built before" answer is still true.
		_new_bests_this_run += 1
		# The three headline tiles also pay gems, once each for life. This is a
		# milestone, not a grind: the second 2048 pays nothing.
		var gems: int = EconomyRules.first_tile_gems(highest_value)
		if gems > 0:
			Wallet.add(WalletRules.GEMS, gems, "first_tile:%d" % highest_value)
			_note_reward(REWARD_FIRST_TILE,
				"First %d ever" % highest_value, 0, gems)
	# And the toy's payout, which is the opposite kind of thing to every line
	# above it: repeatable, paid mid-run, and earned by HEIGHT rather than by
	# surviving. Only the boards that cannot end get past the guard inside.
	if highest_value >= EconomyRules.TILE_MILESTONE_MIN:
		_pay_tile_milestones(highest_value)
	return first_ever

func record_undo() -> void:
	GameStats.record_undo()

## The mode's win target was reached. Undo-free wins earn Perfect Run.
##
## A BOUGHT second life counts against purity exactly as an undo does, and that
## rule lives here rather than in four screens: a mode that forgot to pass it
## would quietly hand out Perfect Run for a revived board, and nothing would say
## so. Callers keep passing only what they know (their own undo flag); the funnel
## adds what it knows.
func record_win(used_undo: bool) -> void:
	Achievements.report_win(used_undo or used_continue())
	_advance_bounties(Bounties.KIND_WINS, 1)
	_pay_first_clear()

## A one-off COIN AND GEM bonus the first time each mode's target is ever
## reached. Uses the run's own mode (from begin_run) rather than a parameter, so
## no caller has to be taught about it — and a mode that forgot to call begin_run
## simply pays nothing rather than paying for the wrong mode.
##
## THE GEMS RIDE ON THIS LATCH ON PURPOSE. Winning a mode is the single most
## significant thing a player does, and until now it paid 100 coins flat whether
## the board was Orbit (which cannot be lost) or Grand (8192). Gems are what the
## economy pays milestones in, so this is where the difficulty is priced —
## `EconomyRules.MODE_WIN_GEMS`. It is the once-per-mode-for-life latch below and
## not `record_win` precisely because a per-win gem payout would be grindable:
## Classic's 2048 is repeatable in twenty minutes, and gems buy permanent things.
##
## The coins go through `_credit_from_play` (they scale with play, so the daily
## soft cap must see them); the gems do not, because eleven lifetime awards
## cannot be farmed by playing longer, which is the only question that cap exists
## to answer.
func _pay_first_clear() -> void:
	if _run_mode.is_empty():
		return
	if SaveManager.section_has_key(FIRST_CLEARS_SECTION, _run_mode):
		return
	SaveManager.set_section_fields(FIRST_CLEARS_SECTION,
		{_run_mode: int(Time.get_unix_time_from_system())})
	_credit_from_play(EconomyRules.FIRST_CLEAR_BONUS, "first_clear:" + _run_mode)
	var gems: int = EconomyRules.mode_win_gems(_run_mode)
	if gems > 0:
		Wallet.add(WalletRules.GEMS, gems, "first_clear:" + _run_mode)
	_note_reward(REWARD_FIRST_CLEAR,
		"First %s win" % GameModes.get_mode(_run_mode).title,
		EconomyRules.FIRST_CLEAR_BONUS, gems)

## True once `mode_id`'s win target has ever been reached (the first-clear bonus
## is spent). The mode picker reads this to show which goals are still open.
func has_first_clear(mode_id: String) -> bool:
	return SaveManager.section_has_key(FIRST_CLEARS_SECTION, mode_id)

## Pays every unpaid milestone rung up to `value` — 2048, 4096, 8192 and on up.
## See EconomyRules.TILE_MILESTONE_MIN for what this is for and why only the
## boards that cannot end pay it.
##
## Walks the rungs rather than paying just the top one, so a run that jumps two at
## once is paid for both. In practice a merge only ever doubles, but `clear_lowest`
## and a corrupted save can both hand this a value the run never stepped through,
## and paying the ladder is the reading that stays honest either way.
##
## THE HALVING IS HERE AND IN NO OTHER PAYOUT, which needs its reason recorded.
## `_credit_from_play` counts coins against DAILY_SOFT_CAP without cutting them,
## and for every other earn hook that is right, because each is bounded by
## something the player cannot repeat at will — a run has to END, a mode is
## first-cleared once for life, a day holds three bounties and three ads. This one
## is bounded by nothing at all: Orbit's sphere never jams, so the only limit on
## how many rungs a day can hold is how long somebody keeps tapping. Counting a
## faucet the cap cannot close, and then not closing it, is how the cap ends up
## measuring everything and stopping nothing.
##
## Re-asked per rung on purpose: a ladder that crosses the cap partway is paid in
## full up to it and halved after, rather than being judged once at the bottom.
func _pay_tile_milestones(value: int) -> void:
	if _run_mode.is_empty():
		return
	var rung: int = EconomyRules.TILE_MILESTONE_MIN
	# `rung > 0` guards the overflow: doubling past 2^63 wraps negative, the
	# comparison stays true, and the funnel hangs mid-merge. `value` comes from a
	# board that comes from a save file, so "it can only ever be a real tile" is
	# not a guarantee this code is allowed to make.
	while rung > 0 and rung <= value:
		if rung <= _milestone_top:
			rung *= 2
			continue
		var coins: int = EconomyRules.tile_milestone_coins(_run_mode, rung)
		if coins <= 0:
			rung *= 2
			continue
		var banked: int = int(_daily().get("coins_from_play", 0))
		if banked >= EconomyRules.DAILY_SOFT_CAP:
			coins = int(round(float(coins) * EconomyRules.OVER_CAP_RATE))
		_credit_from_play(coins, "tile_milestone:%d" % rung)
		_note_reward(REWARD_TILE_MILESTONE, "%d built" % rung, coins)
		_last_milestone = {"value": rung, "coins": coins}
		rung *= 2
	_milestone_top = maxi(_milestone_top, value)

## The rung most recently paid this run, as {"value", "coins"}, or empty before
## the first one. NOT destructive — the milestone modal may be rebuilt by a theme
## change while it is open, and a getter that emptied itself would redraw the
## ceremony with no number on it.
func last_tile_milestone() -> Dictionary:
	return _last_milestone.duplicate()

# --- A finished series --------------------------------------------------------
## THE ONE THING A FINISHED SERIES REPORTS. Banks the score through the same
## path `conclude` uses, keeps the per-mode record, and unlocks what the result
## earned: the mode's crown on a win, its mastery crown at the yardstick, Oracle
## Slayer for beating Oracle, First Line for the first round ever won, Perfect
## Run for an undo-free win. Coins and gems follow from those through the
## payouts below, so the conductor never touches Wallet or Achievements.
##
##   mode_id        the mode the series was played in
##   won            the player took the series (the conductor's own verdict)
##   rounds_won /   the round tally, from the player's side
##   rounds_lost
##   pace_id        a Pace grade id, or ASSISTED_RUN for a solver-assisted board
##   used_undo      any undo at all, for Perfect Run
##   elapsed        wall-clock seconds the series took
##
## WHAT COUNTS. A pass-and-play series is banked but is nobody's record (see
## ASSISTED_RUN): a board the solver closed out is a game played and nothing
## more — no score, no coins, no best, no bounty progress.
func record_series(mode_id: String, won: bool, rounds_won: int, rounds_lost: int,
		pace_id: String, used_undo: bool, elapsed: float) -> void:
	var mode := GameModes.get_mode(mode_id)
	# A series that forgot begin_run still pays for its OWN mode, never a stale one.
	_run_mode = mode_id
	var duel := pace_id != ASSISTED_RUN
	var score := EconomyRules.series_score(rounds_won, won, pace_id)
	var rung := _pace_rung(pace_id) if duel else 0
	if duel and rounds_won > 0:
		Achievements.unlock("first_solve")
	if duel:
		var rec := _note_mode_series(mode_id, won, rounds_won, rounds_lost, pace_id)
		if won:
			# record_win pays the first clear and Perfect Run; the crown rides on
			# the mode's own win target exactly as the tile funnel gated it.
			record_win(used_undo)
			Achievements.report_tile_reached(mode.win_target, mode_id)
			if int(rec.get("series_won", 0)) >= mode.mastery_yardstick():
				var mastery := String(Achievements.MODE_MASTERY_ACHIEVEMENT.get(mode_id, ""))
				if not mastery.is_empty():
					Achievements.unlock(mastery)
			if pace_id == Pace.PERFECT:
				Achievements.unlock("perfect_pace")
	if duel and rounds_won > 0:
		_advance_bounties(Bounties.KIND_ROUNDS, rounds_won)
	if won and rung > 0:
		_advance_bounties(Bounties.KIND_PACE, rung)
	_bank_series(mode_id, score, won, rounds_won, rounds_lost, rung, pace_id, elapsed)

## The grade's rung on the ladder: 1 Steady .. 4 Perfect, 0 for anything else.
func _pace_rung(pace_id: String) -> int:
	var idx: int = Pace.LADDER.find(pace_id)
	return idx + 1 if idx >= 0 else 0

## Rolls one series into `mode_id`'s record (GameStats.MODE_RECORDS_SECTION)
## and hands the updated record back, so the caller can read the mastery count
## it just moved without a second read.
func _note_mode_series(mode_id: String, won: bool, rounds_won: int, rounds_lost: int,
		pace_id: String) -> Dictionary:
	var rec := GameStats.mode_record(mode_id)
	rec["series_played"] = int(rec["series_played"]) + 1
	rec["rounds_won"] = int(rec["rounds_won"]) + maxi(rounds_won, 0)
	rec["rounds_lost"] = int(rec["rounds_lost"]) + maxi(rounds_lost, 0)
	if won:
		rec["series_won"] = int(rec["series_won"]) + 1
		rec["current_streak"] = int(rec["current_streak"]) + 1
		rec["best_streak"] = maxi(int(rec["best_streak"]), int(rec["current_streak"]))
		var beaten: Dictionary = rec["grades_reached"]
		beaten[pace_id] = int(beaten.get(pace_id, 0)) + 1
		rec["grades_reached"] = beaten
		if _pace_rung(pace_id) > _pace_rung(String(rec["best_grade"])):
			rec["best_grade"] = pace_id
	else:
		rec["current_streak"] = 0
	SaveManager.set_keyed(GameStats.MODE_RECORDS_SECTION, mode_id, rec)
	return rec

# --- End of run ---------------------------------------------------------------
## Legacy entry: bank a finished run. The pre-series conductor calls this with
## the rounds won where the 2048 funnel took the top tile; record_series is the
## series-shaped door onto the same path.
##
## Returns false when there was nothing to bank (an untouched board), so callers
## keep their "nothing actually happened" guard without restating the rule.
## Callers must still guard against banking the SAME run twice — that is a
## per-screen concern (their `_recorded` latch), since only they know when a run
## restarts.
func conclude(mode_id: String, score: int, highest: int, won: bool, elapsed: float) -> bool:
	if highest <= 0 and score <= 0:
		return false
	_bank_series(mode_id, score, won, maxi(highest, 0), 0, 0, "", elapsed)
	return true

## Banks a finished series into everything that cares: the per-mode best,
## lifetime stats, the dated history, the streak achievements, the payout, the
## bounties and the ad cadence. Every series lands here, a 0-3 loss included:
## a series that was played is a game played, whatever it scored.
func _bank_series(mode_id: String, score: int, won: bool, rounds_won: int,
		rounds_lost: int, pace_rung: int, pace_id: String, elapsed: float) -> void:
	# AN ASSISTED RUN PAYS NOTHING AND SETS NOTHING. It is a game played and it
	# lands in the stats and the history, but there is no best to post (it
	# scored zero), no payout, no bounty progress — a board the solver closed
	# out is the solver's result, not the player's.
	var rewarded := pace_id != ASSISTED_RUN
	# A new record on this board is what the best bonus pays for, so it is
	# noted before the payout reads it.
	if rewarded and submit_best(mode_id, score):
		_new_bests_this_run = 1
	GameStats.record_series(score, won, rounds_won, rounds_lost, pace_rung, elapsed, mode_id)
	GameStats.add_score_entry(score, mode_id, pace_id, won)
	# record_series() advanced the streak counter above, so the achievement is
	# always evaluated against THIS series' result — never a stale one.
	var streak_days: int = int(GameStats.get_stat("current_streak_days"))
	Achievements.report_streak(streak_days)
	if rewarded:
		_pay_for_run(mode_id, score, won, streak_days)
		_advance_bounties(Bounties.KIND_RUNS, 1)
	# Free tier only: count the completed game and arm an interstitial if due. It
	# is PRESENTED later, via present_pending_ad(), so it never covers the
	# series-over modal.
	AdManager.notify_game_completed()

## Banks the run's coins and rolls today's counters forward.
##
## Split out of conclude() so the payout can be read (and tested) as one thing.
## Everything it needs about the run is either passed in or in the per-run
## counters; the arithmetic itself is EconomyRules', which is what keeps the
## rates tunable without touching this file.
func _pay_for_run(mode_id: String, score: int, won: bool, streak_days: int) -> void:
	var day := _daily()
	var first_of_day: bool = int(day.get("runs", 0)) == 0
	var payout := EconomyRules.run_payout(mode_id, score, won,
		_new_bests_this_run, first_of_day, int(day.get("coins_from_play", 0)))
	# `paid` accumulates EVERY coin this call hands out, not just the run payout.
	# The soft cap is meant to measure "coins from play today", so a bonus that
	# skipped the counter would let the day's total quietly exceed its own cap.
	var paid: int = int(payout["coins"])
	Wallet.add(WalletRules.COINS, paid, "run:" + mode_id)
	# The receipt itemises what was EARNED and then shows the cap's cut as its own
	# line, rather than quietly printing the halved figures. A player who can see
	# "the daily bonus took 175" has learnt a rule; one who only sees a smaller
	# number than this morning has learnt to distrust the payout.
	_note_reward(REWARD_RUN, "Series score", int(payout["base"]))
	_note_reward(REWARD_NEW_BEST, "New best", int(payout["new_best"]))
	_note_reward(REWARD_WIN, "Series won", int(payout["win"]))
	_note_reward(REWARD_FIRST_OF_DAY, "First series today", int(payout["first_of_day"]))
	if bool(payout["halved"]):
		# Negative, and the only line on the receipt that is: this is what the cap
		# TOOK. The screen draws it in the warning colour and totals it in.
		_note_reward(REWARD_CAPPED, "Daily bonus reached",
			paid - int(payout["base"]) - int(payout["bonus"]))
	# The streak reward is a DAILY one, so it rides on the first run of the day
	# rather than on every run — otherwise a ten-run evening pays the streak ten
	# times over.
	if first_of_day and streak_days > 0:
		var streak_coins: int = EconomyRules.streak_payout(streak_days)
		Wallet.add(WalletRules.COINS, streak_coins, "streak:%d" % streak_days)
		paid += streak_coins
		_note_reward(REWARD_STREAK, "Day %d streak" % streak_days, streak_coins,
			EconomyRules.streak_gems(streak_days))
		# Every seventh unbroken day, not only the first seventh — see
		# EconomyRules.GEMS_STREAK_EVERY. This was an equality test against day 7,
		# which paid the habit once and then left a returning player with no gem
		# income at all once their badges were done.
		var streak_gems: int = EconomyRules.streak_gems(streak_days)
		if streak_gems > 0:
			Wallet.add(WalletRules.GEMS, streak_gems, "streak_week")
	day["runs"] = int(day.get("runs", 0)) + 1
	day["coins_from_play"] = int(day.get("coins_from_play", 0)) + paid
	SaveManager.set_section(DAILY_SECTION, day)
	# The run is banked; the next one starts clean even if its screen forgets to
	# call begin_run() (an abandoned run must never gift its depth bonus onward).
	_new_bests_this_run = 0
	# _continues_used is deliberately NOT reset here. Every game-over screen
	# banks the run through conclude() FIRST and asks continues_left() SECOND,
	# so a reset on this line hands the full cap back at every game over — which
	# is exactly how the old once-per-run flag, cleared here, became unlimited.
	# begin_run() is its only reset.

## Every badge pays gems. Wired to the signal in _ready so no unlock site has to
## remember, which is the same reason this autoload exists.
func _on_badge_unlocked(_id: String, def: Dictionary) -> void:
	Wallet.add(WalletRules.GEMS, EconomyRules.GEMS_PER_BADGE, "badge")
	# Badges unlock DURING a run, so their gems belong on that run's receipt. The
	# title comes from the def the signal already carries rather than a second
	# lookup — an id whose def is empty still names the row something true.
	_note_reward(REWARD_BADGE,
		String(def.get("title", "Medal earned")), 0, EconomyRules.GEMS_PER_BADGE)

# --- Daily bounties -----------------------------------------------------------
## Fired when a bounty PAYS, so Home can celebrate it without polling. `coins` is
## what it paid. Since the payout moved to the claim (see _advance_bounties),
## this fires on `claim_bounty` and on the rollover sweep — never merely on
## finishing the task.
signal bounty_completed(id: String, coins: int)

## Fired the moment a bounty's task is FINISHED and its coins are waiting to be
## claimed. The pair matters: "you did it" and "you were paid" are now two
## different moments, and a screen that wants to nudge the player toward the
## Shop needs the first one.
signal bounty_ready(id: String, coins: int)

## Today's three bounty ids. Derived from the date, so this is stable all day and
## needs no stored roll (see Bounties.for_date).
func todays_bounties() -> Array[String]:
	return Bounties.for_date(Time.get_date_string_from_system())

## How far along `id` is today.
func bounty_progress(id: String) -> int:
	var sec := _bounty_state()
	var progress: Dictionary = sec.get("progress", {})
	return int(progress.get(id, 0))

func bounty_paid(id: String) -> bool:
	var sec := _bounty_state()
	var paid: Dictionary = sec.get("paid", {})
	return bool(paid.get(id, false))

## True when `id` is finished but its coins have not been collected — the state
## the Shop draws a Claim button for.
func bounty_claimable(id: String) -> bool:
	if not todays_bounties().has(id):
		return false
	var sec := _bounty_state()
	if bool((sec.get("paid", {}) as Dictionary).get(id, false)):
		return false
	return Bounties.complete(id, int((sec.get("progress", {}) as Dictionary).get(id, 0)))

## Guards the rollover sweep against re-entry: paying a swept bounty fires
## balance_changed, and any listener that reads bounty state would otherwise
## start a second roll inside the first.
var _rolling_bounties := false

## Today's bounty row, rolled over when the date has changed. Reading rolls it,
## exactly like the coin counters — no midnight timer anywhere in the economy.
##
## THE ROLL PAYS ITS DEBTS FIRST. With the payout moved to the claim, a bounty
## can now sit finished-but-unclaimed when midnight arrives, and the old roll
## simply discarded yesterday's row — which would have deleted coins the player
## had already earned. Anything finished and unclaimed is credited on the way
## out, so the claim button is a nicety rather than a deadline.
func _bounty_state() -> Dictionary:
	var sec := SaveManager.get_section(BOUNTY_SECTION, {})
	var today := Time.get_date_string_from_system()
	if String(sec.get("date", "")) == today:
		return sec
	var fresh := {"date": today, "progress": {}, "paid": {}}
	if _rolling_bounties:
		# Re-entered from a sweep payout's own signal. The roll already in flight
		# owns the write; hand back today's shape without touching disk.
		return fresh
	_rolling_bounties = true
	var owed := _unclaimed_in(sec)
	# Persist BEFORE crediting, the same ordering rule the claim uses: a lost
	# reward beats a double payment.
	SaveManager.set_section(BOUNTY_SECTION, fresh)
	for id: String in owed:
		var swept: int = Bounties.coins(id)
		Wallet.add(WalletRules.COINS, swept, "bounty:" + id)
		bounty_completed.emit(id, swept)
	_rolling_bounties = false
	return fresh

## The ids in `sec` (a bounty row from any date) that are finished and unpaid.
## Reads the row's OWN date rather than today's rotation — the whole point is
## that it describes a day that is already over.
func _unclaimed_in(sec: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var date := String(sec.get("date", ""))
	if date.is_empty():
		return out
	var progress: Dictionary = sec.get("progress", {})
	var paid: Dictionary = sec.get("paid", {})
	for id: String in Bounties.for_date(date):
		if bool(paid.get(id, false)):
			continue
		if Bounties.complete(id, int(progress.get(id, 0))):
			out.append(id)
	return out

## Collects a finished bounty's coins. THE PAYOUT POINT — returns what it paid,
## or 0 when there was nothing to collect.
##
## Claimed, not paid automatically. Finishing a task and being paid for it are
## two separate beats, and collapsing them meant the daily board could only ever
## report history: by the time the player looked, every reward had already
## landed silently mid-run. A claim gives the board something to DO.
##
## The `paid` latch is what stops a re-pay, and it is checked here rather than
## trusted from the caller — a double-tapped button must not pay twice.
func claim_bounty(id: String) -> int:
	if not bounty_claimable(id):
		return 0
	var sec := _bounty_state()
	var paid: Dictionary = sec.get("paid", {})
	paid[id] = true
	sec["paid"] = paid
	SaveManager.set_section(BOUNTY_SECTION, sec)
	# Persist BEFORE crediting: if the credit somehow failed, a paid-but-unbanked
	# bounty is a lost reward, while a banked-but-unpaid one would pay twice.
	var reward: int = Bounties.coins(id)
	Wallet.add(WalletRules.COINS, reward, "bounty:" + id)
	bounty_completed.emit(id, reward)
	return reward

## Advances every one of today's bounties that cares about `event_kind`, and
## announces the ones that just finished.
##
## IT NO LONGER PAYS. The coins wait for `claim_bounty` — see its note for why —
## so this marks progress and emits `bounty_ready`. The `paid` latch still gates
## the walk: progress may keep climbing past the goal (a 150-merge task keeps
## counting), so a claimed bounty must stop being considered.
func _advance_bounties(event_kind: String, amount: int) -> void:
	if amount <= 0:
		return
	var sec := _bounty_state()
	var progress: Dictionary = sec.get("progress", {})
	var paid: Dictionary = sec.get("paid", {})
	var finished: Array[String] = []
	var touched := false
	for id: String in todays_bounties():
		if bool(paid.get(id, false)):
			continue
		var step: int = Bounties.advance(id, event_kind, amount)
		if step <= 0:
			continue
		touched = true
		var was_done: bool = Bounties.complete(id, int(progress.get(id, 0)))
		var next: int = int(progress.get(id, 0)) + step
		progress[id] = next
		# Only the step that CROSSES the goal announces it. Progress keeps
		# climbing afterwards, and an unclaimed bounty would otherwise re-announce
		# itself on every merge for the rest of the run.
		if Bounties.complete(id, next) and not was_done:
			finished.append(id)
	if not touched:
		return
	sec["progress"] = progress
	sec["paid"] = paid
	SaveManager.set_section(BOUNTY_SECTION, sec)
	for id: String in finished:
		bounty_ready.emit(id, Bounties.coins(id))

# --- Today's counters ---------------------------------------------------------
## Credits coins that came FROM PLAY, and counts them against the soft cap.
##
## THE CAP LEAKED, and this is the plug. `DAILY_SOFT_CAP` is documented as the
## only brake left in the economy, but only the end-of-run payout ever advanced
## `coins_from_play` — so the star bonus (50 a star, on a board with no limit on
## how many a session can birth) and the first-clear bonus were both invisible to
## the thing meant to be measuring them. A brake that half the faucets route
## around is not a brake.
##
## What is deliberately NOT routed through here: bounty claims and rewarded-ad
## coins. Both are FIXED daily allowances that already bound themselves — three
## bounties a day, MAX_AD_COINS_PER_DAY ads a day — so they cannot be farmed by
## playing longer, which is the only thing the soft cap exists to answer. Halving
## them once a good session passed the cap would also punish exactly the player
## the daily board is there to bring back tomorrow.
func _credit_from_play(amount: int, reason: String) -> void:
	if amount <= 0:
		return
	Wallet.add(WalletRules.COINS, amount, reason)
	var day := _daily()
	day["coins_from_play"] = int(day.get("coins_from_play", 0)) + amount
	SaveManager.set_section(DAILY_SECTION, day)

## Today's economy row, rolled over when the date has changed. Reading is what
## rolls it — there is no midnight timer, so a session that spans midnight simply
## starts counting against the new day at its next payout.
func _daily() -> Dictionary:
	var sec := SaveManager.get_section(DAILY_SECTION, {})
	var today := Time.get_date_string_from_system()
	if String(sec.get("date", "")) != today:
		return {"date": today, "runs": 0, "coins_from_play": 0, "ad_coins": 0}
	return sec

## Coins paid out from play today — what the soft cap is measured against.
func coins_earned_today() -> int:
	return int(_daily().get("coins_from_play", 0))

## True once today's payouts have passed the soft cap and are being halved. The
## game-over payout line reads this so a smaller-than-expected reward is
## explained on the spot rather than looking like a bug.
func daily_cap_reached() -> bool:
	return coins_earned_today() >= EconomyRules.DAILY_SOFT_CAP

# --- Rewarded ads -------------------------------------------------------------
## Credits a rewarded-ad payout, if today's allowance has room. Returns false
## when the allowance is spent, so the caller can hide the offer rather than
## show a button that silently does nothing.
##
## COINS ONLY. There was a second allowance, counted separately, that paid a
## point of energy — deliberately its own counter so that topping up a dry Fling
## purse did not spend the allowance meant for a short revive fund. With energy
## removed there is one thing an ad can pay for, so there is one counter; a
## `currency` argument is still taken so every offer site names what it is asking
## for, and anything but coins is refused rather than quietly paid in coins.
func grant_ad_reward(currency: String) -> bool:
	if currency != WalletRules.COINS or not ad_reward_available(currency):
		return false
	var day := _daily()
	Wallet.add(currency, EconomyRules.COINS_PER_AD, "ad")
	day["ad_coins"] = int(day.get("ad_coins", 0)) + 1
	SaveManager.set_section(DAILY_SECTION, day)
	return true

## Whether a rewarded-ad offer for `currency` should be shown at all today.
func ad_reward_available(currency: String) -> bool:
	if currency != WalletRules.COINS:
		return false
	return int(_daily().get("ad_coins", 0)) < EconomyRules.MAX_AD_COINS_PER_DAY

# --- Per-mode best series -----------------------------------------------------
## The best SERIES score the player has posted in `mode_id` (see
## EconomyRules.series_score: rounds won, plus the rival's bonus on a win).
func best_score(mode_id: String) -> int:
	return int(SaveManager.get_section(BEST_SECTION, {}).get(mode_id, 0))

## The best series the player holds on any RANKED board, with the board holding
## it: {"score": int, "mode_id": String}. Score 0 and an empty id when none of
## them has been finished yet.
##
## RANKED, not "any mode", and the distinction is the whole point. Only
## GameModes.RANKED_MODES share one series length and rival ladder; a one-round
## Daily solve and a first-to-three Classic series are not two entries in one
## table, so a "highest number anywhere" figure would be a category error dressed
## up as a record — and it would name whichever board scores fastest as the
## player's best game.
##
## Lives HERE, not on the Leaderboard screen that renders it, for two reasons:
## this autoload already owns the best_scores section (one read, not one per
## mode), and the purse strip's leaderboard pill shows the same number — the pill
## IS the door to that page, so the two must never be able to disagree.
##
## Ties break on the catalog's own order, so the answer is stable across reads
## rather than depending on dictionary iteration.
func best_score_overall() -> Dictionary:
	var sec := SaveManager.get_section(BEST_SECTION, {})
	var best := 0
	var best_id := ""
	for mode: GameModes.Mode in GameModes.ranked():
		var score := int(sec.get(mode.id, 0))
		if score > best:
			best = score
			best_id = mode.id
	return {"score": best, "mode_id": best_id}

## Writes `score` as the mode's record if it beats the stored one. Returns true
## only when a NEW record was written, which is what the live mid-run "new best"
## flourish hangs off.
func submit_best(mode_id: String, score: int) -> bool:
	var sec := SaveManager.get_section(BEST_SECTION, {})
	if score <= int(sec.get(mode_id, 0)):
		return false
	sec[mode_id] = score
	SaveManager.set_section(BEST_SECTION, sec)
	return true

# --- Ads ----------------------------------------------------------------------
## Present an interstitial armed by conclude(), if any. Call when the player
## LEAVES the game-over screen (every exit route, or back becomes a free ad
## skip). No-op for premium, and a stub until AdMob lands.
func present_pending_ad(host: Node) -> void:
	AdManager.present_pending(host)

## Hands the finished run's receipt to the Rewards screen, then carries the
## player on to `next`. The ONE call every mode's game-over exits make, for the
## same reason `conclude()` is one call: eleven modes each deciding when a payout
## deserves a page is eleven chances for one of them to decide never.
##
## Falls STRAIGHT THROUGH to `next` when the run paid nothing — an untouched
## board, or a run whose payout the daily cap reduced to zero. A celebration page
## with an empty ledger is worse than no page, and the caller does not have to
## know that rule to get it right.
##
## Always `replace`, so neither this screen nor the board behind it lands in the
## back stack: the run is over, and backing into either of them from wherever the
## player goes next would offer a receipt with nothing left to pay, or a board
## with no game on it.
func present_rewards(mode_id: String, score: int, won: bool,
		next_route: String, next_args: Dictionary = {}) -> void:
	if not has_reward():
		SceneRouter.goto(next_route, next_args, true)
		return
	SceneRouter.goto(SceneRouter.Route["REWARDS"], {
		"mode": mode_id, "score": score, "won": won,
		"next": next_route, "next_args": next_args,
	}, true)
