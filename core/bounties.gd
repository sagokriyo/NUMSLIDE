class_name Bounties
extends RefCounted
## Bounties — the three daily tasks, and the pure rules behind them.
##
## Zero node/UI/autoload dependencies, like its siblings in core/: the day's
## selection is derived from the DATE STRING rather than from a random draw or a
## stored roll, so it is reproducible from nothing but "what day is it". That is
## what makes it testable, and it also means a player who reinstalls mid-day gets
## the same three tasks back instead of a fresh set (and cannot reroll by wiping
## the save).
##
## WHY BOUNTIES EXIST. Payouts alone reward whatever the player already does.
## Bounties are the one part of the economy that asks for something specific —
## "birth two stars", "reach 512" — which is what gets a Classic-only player to
## open Tower once. They are also the reason to open the app on a day you had not
## planned to play. Every task is satisfiable by NORMAL play in one sitting; none
## asks for a purchase, a streak, or a login.
##
## `Progression` observes play and advances these; `EconomyRules` owns the coin
## rates; this file owns WHICH tasks and WHAT COUNTS.

## How many run at once. Three is enough to guarantee at least one is a
## comfortable fit for whatever the player feels like playing.
const DAILY_COUNT := 3

## What a bounty measures. Each kind maps to exactly one thing Progression
## already sees, so adding a task never means adding a new observation point:
##
##   turns  — marks placed, cumulative across series
##   rounds — rounds won, cumulative
##   runs   — series finished
##   wins   — series won
##   pace   — finish a board graded at least this far up the ladder (1 Steady to
##            4 Perfect; progress is 0 or `goal`, so a Perfect finishes an
##            Expert task)
const KIND_TURNS := "turns"
const KIND_ROUNDS := "rounds"
const KIND_RUNS := "runs"
const KIND_WINS := "wins"
const KIND_PACE := "pace"

## The pool the day's three are drawn from. `coins` is the payout, scaled to how
## much play the task actually asks for — a task worth less than a run's ordinary
## payout would be a chore rather than a reason.
##
## Deliberately NO task that names a mode the player may not own: Quantum, Cube,
## Orbit and Arena are premium, so a bounty demanding one would be a daily
## reminder of a locked door. Every task here can be finished on Classic.
##
## Nor any task that demands Oracle. It never loses a solved board, so "beat
## Oracle" is not a day's play, it is a wall; the ladder task stops at Sage and
## a win over Oracle finishes it anyway (the rival kind is a threshold).
const DEFS: Array[Dictionary] = [
	{"id": "turns_100", "kind": KIND_TURNS, "goal": 100, "coins": 120,
		"title": "Place 100 marks", "detail": "On any board."},
	{"id": "turns_250", "kind": KIND_TURNS, "goal": 250, "coins": 220,
		"title": "Place 250 marks", "detail": "On any board."},
	{"id": "rounds_5", "kind": KIND_ROUNDS, "goal": 5, "coins": 150,
		"title": "Win 5 rounds", "detail": "Rounds, not whole series."},
	{"id": "rounds_12", "kind": KIND_ROUNDS, "goal": 12, "coins": 260,
		"title": "Win 12 rounds", "detail": "Rounds, not whole series."},
	{"id": "runs_3", "kind": KIND_RUNS, "goal": 3, "coins": 150,
		"title": "Finish 3 series", "detail": "Any board, win or lose."},
	{"id": "win_1", "kind": KIND_WINS, "goal": 1, "coins": 200,
		"title": "Win a series", "detail": "On any board."},
	{"id": "win_3", "kind": KIND_WINS, "goal": 3, "coins": 320,
		"title": "Win 3 series", "detail": "On any board."},
	{"id": "pace_expert", "kind": KIND_PACE, "goal": 3, "coins": 200,
		"title": "Solve one at Expert", "detail": "Well under the board's par."},
]

## The definition for `id`, or an empty Dictionary. A save carrying a retired id
## resolves to empty rather than crashing the card that renders it.
static func definition(id: String) -> Dictionary:
	for def: Dictionary in DEFS:
		if String(def["id"]) == id:
			return def
	return {}

## The three bounty ids for `date` ("YYYY-MM-DD"), always in the same order for
## the same date.
##
## Selection walks the pool from a date-derived offset with a co-prime stride, so
## the three are guaranteed DISTINCT (no rejection loop, no chance of a repeat)
## and the set rotates rather than clustering. A plain "pick 3 at random" would
## need a seeded RNG, which is exactly the impurity this avoids.
static func for_date(date: String) -> Array[String]:
	var out: Array[String] = []
	var n := DEFS.size()
	if n == 0:
		return out
	var count: int = mini(DAILY_COUNT, n)
	var seed_value: int = absi(hash(date))
	var start: int = seed_value % n
	var stride: int = coprime_stride(seed_value, n)
	for i in count:
		var idx: int = (start + i * stride) % n
		out.append(String(DEFS[idx]["id"]))
	return out

## A stride that shares no factor with `n`, so stepping by it visits distinct
## slots. Falls back to 1, which is trivially co-prime with everything.
static func coprime_stride(seed_value: int, n: int) -> int:
	if n <= 1:
		return 1
	var candidate: int = 1 + (absi(seed_value / maxi(n, 1)) % (n - 1))
	for step in n:
		var s: int = 1 + ((candidate - 1 + step) % (n - 1))
		if _gcd(s, n) == 1:
			return s
	return 1

static func _gcd(a: int, b: int) -> int:
	var x := absi(a)
	var y := absi(b)
	while y != 0:
		var t := y
		y = x % y
		x = t
	return x

## What `id` needs to be complete (0 for an unknown id, which therefore reads as
## already done rather than as an unreachable task).
static func goal(id: String) -> int:
	return int(definition(id).get("goal", 0))

static func coins(id: String) -> int:
	return int(definition(id).get("coins", 0))

static func kind(id: String) -> String:
	return String(definition(id).get("kind", ""))

## True once `progress` meets `id`'s goal.
static func complete(id: String, progress: int) -> bool:
	return progress >= goal(id)

## How much `event_kind` (carrying `amount`) advances `id`. Zero when the event
## is irrelevant to this task.
##
## rival is the odd one: it is a THRESHOLD, not a tally, so a "beat Sage" task is
## completed outright by beating Oracle and untouched by beating Rook. Treating
## it as a tally would let three wins over Pip "add up" to Sage, which is not
## what the copy says.
static func advance(id: String, event_kind: String, amount: int) -> int:
	var k := kind(id)
	if k.is_empty() or k != event_kind or amount <= 0:
		return 0
	if k == KIND_PACE:
		return goal(id) if amount >= goal(id) else 0
	return amount
