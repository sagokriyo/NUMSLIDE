class_name RulesSprint
extends SlideRules
## Rush: one clock, and the boards never stop coming.
##
## THE CLOCK IS THE BOARD. Solving does not end the run here, it re-deals: the
## tray clears, a fresh scramble drops in, and the solve buys seconds back on a
## clock that has been draining the whole time. The run ends when the clock
## does, and the score is boards cleared. That is the whole difference from
## Classic, and it is a difference in the RULE rather than a timer bolted onto
## one, because `outcome` here never reports a solved board as over.
##
## Each board is a touch shorter than the last so the pressure climbs, and the
## seconds a solve pays back shrink with it, which is what turns a long run into
## a losing race rather than a plateau.

## Seconds on the clock at the start of a run.
const START_SECONDS := 60.0
## Seconds a solve pays back on the first board.
const REWARD_SECONDS := 22.0
## The floor a reward decays to, however deep the run goes.
const REWARD_FLOOR := 9.0
## How much of the reward each cleared board takes off the next one.
const REWARD_DECAY := 0.88

## Scramble depth of the first board, and the ceiling it climbs to.
const FIRST_SCRAMBLE := 24
const SCRAMBLE_STEP := 6
const MAX_SCRAMBLE := 90

## Boards cleared this run. The score.
var cleared: int = 0

## The re-deal needs randomness, and the seed belongs to the run rather than the
## rule, so the conductor hands one in. An unseeded rule still deals boards; it
## just deals the same ones every run.
var _rng := RandomNumberGenerator.new()

func rule_id() -> String:
	return "sprint"

## Pins the run's randomness. Called once when the run begins.
func seed_rng(seed_value: int) -> void:
	_rng.seed = seed_value
	cleared = 0

## Seconds the NEXT solve is worth, given what has been cleared already.
func reward_seconds() -> float:
	return maxf(REWARD_FLOOR, REWARD_SECONDS * pow(REWARD_DECAY, float(cleared)))

## How hard the next board is dealt.
func next_scramble_steps() -> int:
	return mini(MAX_SCRAMBLE, FIRST_SCRAMBLE + cleared * SCRAMBLE_STEP)

## Rush is never over because a board came out. Only the clock ends a run, and
## the clock is the conductor's.
func outcome(_board: SlideBoard) -> Dictionary:
	return {"over": false, "solved": false}

## A solved board is a CLEARED board: bank it and tell the view to celebrate and
## reload rather than to stop.
##
## IT DOES NOT RE-DEAL HERE, and that is not a stylistic choice. `apply` has to
## be a plain board transition or nothing can search on it: the solver walks a
## board home by applying candidate moves to clones, and a rule that scrambled
## the board the instant a move solved it destroyed every solution at the exact
## moment it was found. IDA* could never reach a finished position, so the hint,
## the auto-solve and the tests all ran until their budgets died. The rule says
## the board came out; `deal_next` is the separate step, and the conductor takes
## it when it has finished celebrating.
func _judge(board: SlideBoard, events: Array[Dictionary]) -> void:
	if not board.is_solved():
		return
	events.append({"type": "cleared", "seconds": reward_seconds()})

## Banks the cleared board and returns the new count.
##
## APPLY COUNTS NOTHING, for the same reason it does not re-deal. The solver
## explores by applying candidate moves, and it applies a great many of them
## that the player never plays; a counter incremented inside `apply` climbed
## once per line the search looked at, so a single solve banked three boards
## and paid three rewards. Every run of the search is now free of side effects,
## and the two things a clear actually changes happen here and in `deal_next`,
## both called once, by the conductor, for the move the player really made.
func bank_clear() -> int:
	cleared += 1
	return cleared

## Scrambles the tray again for the next board of the run, a touch deeper than
## the last. Called by the conductor once it has banked the clear.
func deal_next(board: SlideBoard) -> void:
	scramble(board, _rng, next_scramble_steps())

## The opening board. Shallower than a Classic scramble on purpose: the first
## one has to be solvable inside the first few seconds or the run never starts.
func scramble_steps() -> int:
	return FIRST_SCRAMBLE
