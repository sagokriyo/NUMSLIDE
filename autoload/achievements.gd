extends Node
## Achievements — definitions, unlock evaluation, and persistence.
##
## Achievements are declared as data (id → {title, detail, icon, hidden}). The
## gameplay loop pushes events here via the report_* methods; this evaluates
## conditions, persists unlocks, and emits `unlocked` so the UI can present a
## tasteful toast. Logic and presentation stay fully separated.

signal unlocked(id: String, def: Dictionary)

const SECTION := "achievements"

# Order here is the display order. `hidden` ones are masked until earned.
# EVERY mode gets its OWN crown, gated by that mode's real win_target, instead of
# one global ladder: solving a Classic 3x3 does not quietly count as beating the
# Cube. The Tier badge (see TierBadge/GameStats.best_mastery_ratio) is the
# difficulty-normalized bragging number; these are the concrete goalposts.
#
# EVERY crown here has medal art (assets/images/medals/<id>.png), baked by
# tools/medal_bake.tscn from the app's own painters; add the id to that tool's
# hue table and re-run it when adding an entry here. That matters more than
# it sounds: badge.gd's trophy rail SKIPS an achievement with no art entirely
# (_trophy_medal returns null), so an unpainted crown was absent from the trophy
# case even once earned, with no warning anywhere. A new entry added here MUST
# ship its PNG with it, or it earns silently into an empty shelf.
const DEFS := {
	"first_solve":        {"title": "First Board",      "detail": "Solve your first board.",                     "icon": "merge"},
	"classic_series":     {"title": "In Order",         "detail": "Solve a board in Classic.",                   "icon": "tile", "icon_label": "1"},
	"sprint_series":      {"title": "Against the Clock","detail": "Clear a board in Rush.",                      "icon": "tile", "icon_label": "60"},
	"lock_series":        {"title": "Welded Shut",      "detail": "Solve a board in Lockdown.",                  "icon": "tile", "icon_label": "16"},
	"twist_series":       {"title": "Four at a Time",   "detail": "Solve a board in Twist.",                     "icon": "tile", "icon_label": "9"},
	"fog_series":         {"title": "Lights Out",       "detail": "Solve a board in Blind.",                     "icon": "tile", "icon_label": "?"},
	"classic_master":     {"title": "Classic Master",   "detail": "Solve ten boards in Classic.",                "icon": "trophy"},
	"lock_master":        {"title": "Lockdown Master",  "detail": "Solve ten boards in Lockdown.",               "icon": "trophy"},
	"twist_master":       {"title": "Twist Master",     "detail": "Solve ten boards in Twist.",                  "icon": "trophy"},
	"perfect_pace":       {"title": "Not One Wasted",   "detail": "Finish a board graded Perfect.",              "icon": "star", "hidden": true},
	"perfect_run":        {"title": "Perfect Run",      "detail": "Solve a board without a single undo.",        "icon": "trophy"},
	"streak_7":           {"title": "Steady Hand",      "detail": "Complete a 7-day streak.",                    "icon": "calendar", "hidden": true},
	"streak_30":          {"title": "Devoted",          "detail": "Complete a 30-day streak.",                   "icon": "flame",    "hidden": true},
}

## mode_id -> the achievement it unlocks on reaching that mode's own win target.
##
## ONE table, EVERY mode. In the sibling project this started life as an `elif`
## ladder inside the report hook with the winning number written in by hand,
## which is why four modes added later reached their targets and unlocked
## NOTHING: there was no list for them to be missing from. A mode absent here now
## fails regression/headless/suites/test_progression.gd rather than going quiet.
const MODE_WIN_ACHIEVEMENT := {
	"classic": "classic_series", "sprint": "sprint_series",
	"lock": "lock_series", "twist": "twist_series",
	"fog": "fog_series",
}

## mode_id -> the achievement it unlocks on reaching that mode's MASTERY count —
## the second rung, well past solving the board once.
##
## The three RANKED boards carry one. Rush is scored on boards cleared and is
## already a ladder of its own; Blind is a single-sitting achievement where a
## second rung would only ask for repetition.
##
## A mode here MUST also be in MODE_WIN_ACHIEVEMENT — the mastery rung is a
## second rung, not a substitute — and test_progression.gd fails if it is not.
const MODE_MASTERY_ACHIEVEMENT := {
	"classic": "classic_master", "lock": "lock_master", "twist": "twist_master",
}

## The boards-solved count `mode_id`'s mastery crown asks for, or 0 when it has
## no second rung.
##
## DERIVED, never written down a second time — the same rule report_tile_reached
## already follows for the win crown. A mode that declares a `mastery_target`
## above its win target has already named the number its rank ladder measures, so
## the crown asks for exactly that and the badge matches the bar TierBadge uses.
## Every other mode doubles its win target.
static func mastery_threshold(mode_id: String) -> int:
	if not MODE_MASTERY_ACHIEVEMENT.has(mode_id):
		return 0
	var mode := GameModes.get_mode(mode_id)
	var yard: int = mode.mastery_yardstick()
	return yard if yard > mode.win_target else mode.win_target * 2

var _unlocked: Dictionary = {}   # id -> unix timestamp

func _ready() -> void:
	_unlocked = SaveManager.get_section(SECTION, {})

func is_unlocked(id: String) -> bool:
	return _unlocked.has(id)

func unlocked_count() -> int:
	# Count only ids still in DEFS — old saves can carry retired achievement ids,
	# which would otherwise overshoot the total (e.g. "16 / 13").
	var n := 0
	for id in DEFS:
		if _unlocked.has(id):
			n += 1
	return n

## Unix timestamp of the unlock, or 0 when still locked.
func unlocked_at(id: String) -> int:
	return int(_unlocked.get(id, 0))

func total_count() -> int:
	return DEFS.size()

func definition(id: String) -> Dictionary:
	return (DEFS.get(id, {}) as Dictionary).duplicate()

func ordered_ids() -> Array:
	return DEFS.keys()

func unlock(id: String) -> void:
	if not DEFS.has(id) or _unlocked.has(id):
		return
	_unlocked[id] = int(Time.get_unix_time_from_system())
	SaveManager.set_section(SECTION, _unlocked)
	unlocked.emit(id, DEFS[id])

# --- Event hooks called by gameplay ------------------------------------------
func report_solve() -> void:
	unlock("first_solve")

## `value` is BOARDS SOLVED on this mode, not a tile. The name is kept because
## every caller in the shell already uses it and the gate is identical: a mode's
## crown opens at its own win target, its mastery crown at its own yardstick.
func report_tile_reached(value: int, mode_id: String = "") -> void:
	if not MODE_WIN_ACHIEVEMENT.has(mode_id):
		return
	# Gated by the mode's OWN win target (never a re-hardcoded number), so this
	# can never drift from core/game_modes.gd's actual configuration — including
	# the modes whose target is not 2048.
	if value >= GameModes.get_mode(mode_id).win_target:
		unlock(String(MODE_WIN_ACHIEVEMENT[mode_id]))
	# The second rung, for the modes that have one. Evaluated from the SAME event
	# rather than a new report_* call, so no mode screen has to learn about it and
	# none can forget it — the drift that left four modes crownless in the first
	# place. mastery_threshold() returns 0 for a mode without one, and `value` is
	# a real tile, so the guard below is the whole gate.
	var mastery := mastery_threshold(mode_id)
	if mastery > 0 and value >= mastery:
		unlock(String(MODE_MASTERY_ACHIEVEMENT[mode_id]))

func report_win(used_undo: bool) -> void:
	if not used_undo:
		unlock("perfect_run")

func report_streak(days: int) -> void:
	if days >= 7:
		unlock("streak_7")
	if days >= 30:
		unlock("streak_30")
