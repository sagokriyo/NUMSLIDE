class_name Pace
extends RefCounted
## Pace: the four grades a finished board is marked against, and NUMSLIDE's
## answer to "who am I playing".
##
## A sliding puzzle has no opponent, and a solo game with nothing on the other
## side of the board is a game with no stakes. So the board itself sets the
## terms: every scramble is dealt with a PAR, and the run is graded on how far
## under it you came home. Par is not a designer's guess, it is derived from the
## board actually dealt (its total tile distance), so a shallow scramble asks
## less and a brutal one asks more, and the grade means the same thing on every
## board of every size.
##
## The four tiers are a LADDER, exactly as the sibling project's rivals were,
## and they plug into the same machinery: `Progression` banks a rung, the win
## streak counts consecutive runs at Sharp or better, `GameStats` remembers the
## best grade ever reached, and `EconomyRules` pays a bonus that climbs with it.
## Nothing about that plumbing had to change; only who is on the other side.

const STEADY := "steady"
const SHARP := "sharp"
const EXPERT := "expert"
const PERFECT := "perfect"
## A board finished with the solver's help. Off the ladder entirely: it pays a
## token bonus, moves no streak and sets no record. The honest result of asking
## for the answer.
const ASSISTED := "assisted"

## The ladder, weakest first. A grade's rung is its place here, 1 to 4.
const LADDER: Array[String] = [STEADY, SHARP, EXPERT, PERFECT]

## What each grade is called on screen.
const TITLES := {
	STEADY: "Steady",
	SHARP: "Sharp",
	EXPERT: "Expert",
	PERFECT: "Perfect",
	ASSISTED: "Assisted",
}

## One short line per grade, for the run-over card.
const LINES := {
	STEADY: "Solved. Now do it in fewer.",
	SHARP: "Under par. Clean run.",
	EXPERT: "Well under par. That was read, not guessed.",
	PERFECT: "You barely wasted a move.",
	ASSISTED: "Solved with help. It does not count for the ladder.",
}

## The hue each grade wears, for the pips and the run-over card.
const HUES := {
	STEADY: Color("8FA6C4"),
	SHARP: Color("5BD6E5"),
	EXPERT: Color("A98BF7"),
	PERFECT: Color("F5C542"),
	ASSISTED: Color("6E7C90"),
}

## The multiples of the board's own distance each grade is worth. A run is
## graded against the first one of these it comes in under.
const PERFECT_FACTOR := 0.95
const EXPERT_FACTOR := 1.20
const SHARP_FACTOR := 1.60

## The floor a par is never set below, so a nearly-solved board still asks for
## something and a three-move finish is not automatically Perfect.
const PAR_FLOOR := 8

## The grade's rung: 1 Steady .. 4 Perfect, 0 for anything off the ladder.
static func rung(id: String) -> int:
	var idx := LADDER.find(id)
	return idx + 1

static func title(id: String) -> String:
	return String(TITLES.get(id, "Solved"))

static func line(id: String) -> String:
	return String(LINES.get(id, ""))

static func hue(id: String) -> Color:
	return HUES.get(id, Color("8FA6C4"))

## The par for a board as it was DEALT: its total tile distance, floored. Read
## once when the run begins, never recomputed, or the target would move every
## time the player made progress.
static func par_for(board: SlideBoard) -> int:
	if board == null:
		return PAR_FLOOR
	return maxi(PAR_FLOOR, int(round(float(board.manhattan()) * EXPERT_FACTOR)))

## The distance a par was derived from, recovered from the par itself. Grading
## works off this so a saved run only has to carry one number.
static func distance_of(par: int) -> float:
	return float(par) / EXPERT_FACTOR

## The grade a finished board earns. `assisted` marks a run the solver helped.
static func grade(moves: int, par: int, assisted: bool = false) -> String:
	if assisted:
		return ASSISTED
	var dist := distance_of(par)
	if float(moves) <= dist * PERFECT_FACTOR:
		return PERFECT
	if float(moves) <= dist * EXPERT_FACTOR:
		return EXPERT
	if float(moves) <= dist * SHARP_FACTOR:
		return SHARP
	return STEADY

## The move count each grade would need on this par. For the run-over card's
## "next grade at N moves" line and the target readout during play.
static func threshold(id: String, par: int) -> int:
	var dist := distance_of(par)
	match id:
		PERFECT:
			return int(floor(dist * PERFECT_FACTOR))
		EXPERT:
			return int(floor(dist * EXPERT_FACTOR))
		SHARP:
			return int(floor(dist * SHARP_FACTOR))
	return 0

## The grade one rung above `id`, or "" at the top. Drives the "so close" line.
static func next_up(id: String) -> String:
	var idx := LADDER.find(id)
	if idx < 0 or idx >= LADDER.size() - 1:
		return ""
	return LADDER[idx + 1]
