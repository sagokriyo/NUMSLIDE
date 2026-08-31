extends "res://regression/headless/harness/script_test_base.gd"
## Headless unit tests for the PlayGamesIds catalog (pure data, no autoloads).
## Run:  godot --headless --path . --script res://regression/headless/harness/headless_boot.gd -- --test=res://tests/test_play_games_ids.gd
##
## This is the tripwire for catalog↔DEFS drift, so the achievement expectation is
## DERIVED FROM THE REAL autoload/achievements.gd DEFS — never a hand-copied list.
## A hardcoded list cannot see DEFS grow, and that is exactly how tower_star /
## constellation_1 / constellation_3 reached players with no Play slot (unlocked
## locally, silently never mirrored) while this file stayed green.
##
## DEFS is read off the SCRIPT at runtime via load() — the constant, not the
## autoload node — so the test keeps its "no autoloads, no instancing" contract
## (achievements.gd's _ready() touches SaveManager; we never instantiate it).

## regression/headless/suites/test_progression.gd checks the same drift with the
## autoloads live; keep both in step.
const ACHIEVEMENTS_SCRIPT := "res://autoload/achievements.gd"
## The leaderboard expectation is derived from the MODE CATALOG for the same
## reason the achievement one is derived from DEFS: a hand-copied list of three
## modes is exactly what let seven later modes ship with a recorded best score
## and nowhere to rank it. GameModes is pure data with no autoload dependency
## (unlike Achievements, which is a node) so it is named directly.

func run_tests() -> void:
	_test_achievement_catalog()
	_test_leaderboard_catalog()
	_test_lookups()
	_test_dormant_until_configured()

func _test_achievement_catalog() -> void:
	print("test_achievement_catalog:")
	var defs_ids: Array = _defs_ids()
	# Guard the derivation itself: an empty read would make every check below
	# vacuously true — the failure mode that let the last drift through.
	check("Achievements.DEFS was read (expectation is live, not a hardcoded copy)",
		not defs_ids.is_empty())
	check("catalog and DEFS hold the same number of ids",
		PlayGamesIds.ACHIEVEMENTS.size() == defs_ids.size())
	# Forward: an unmapped DEFS id can never be mirrored to Play.
	for id: String in defs_ids:
		check("every Achievements.DEFS id has a catalog slot: '%s'" % id,
			PlayGamesIds.ACHIEVEMENTS.has(id))
	# Reverse: a catalog key DEFS no longer defines is a dead slot (typo or retirement).
	for key: String in PlayGamesIds.ACHIEVEMENTS.keys():
		check("no stale catalog slot: '%s' is still a DEFS id" % key, defs_ids.has(key))

func _test_leaderboard_catalog() -> void:
	print("test_leaderboard_catalog:")
	var mode_ids: Array = _mode_ids()
	# Same guard as the achievement side: an empty derivation would make every
	# check below vacuously true.
	check("GameModes._CONFIGS was read (expectation is live, not a hardcoded copy)",
		not mode_ids.is_empty())
	# Forward: a mode with no board records a best score that ranks nowhere.
	for mode: String in mode_ids:
		check("best-score board slot for mode '%s'" % mode,
			PlayGamesIds.LEADERBOARD_BEST_SCORE_BY_MODE.has(mode))
	# Reverse: a board for a mode that no longer exists is a dead slot.
	for key: String in PlayGamesIds.LEADERBOARD_BEST_SCORE_BY_MODE.keys():
		check("no stale board slot: '%s' is still a mode" % key, mode_ids.has(key))

func _test_lookups() -> void:
	print("test_lookups:")
	check("achievement() returns '' for an unmapped id",
		PlayGamesIds.achievement("first_merge").is_empty())
	check("achievement() returns '' for an UNKNOWN id (no crash)",
		PlayGamesIds.achievement("no_such_achievement").is_empty())
	check("best_score_leaderboard() returns '' for an unmapped mode",
		PlayGamesIds.best_score_leaderboard("classic").is_empty())
	check("best_score_leaderboard() returns '' for an UNKNOWN mode (no crash)",
		PlayGamesIds.best_score_leaderboard("no_such_mode").is_empty())

func _test_dormant_until_configured() -> void:
	print("test_dormant_until_configured:")
	# Ships empty → PlayGames skips achievement/leaderboard calls entirely rather
	# than firing garbage ids at Play. Flips to true once the real ids are pasted in.
	check("is_configured() is false while the catalog is empty",
		not PlayGamesIds.is_configured())

# --- helpers ---------------------------------------------------------------------
## The LIVE achievement ids, read off autoload/achievements.gd's DEFS constant.
## The script is loaded, never instantiated: reading a const needs no node, no
## autoload and no scene tree. Returns [] if the script can't be read, which the
## caller asserts on rather than silently passing an empty expectation.
func _defs_ids() -> Array:
	var ach_script: Variant = load(ACHIEVEMENTS_SCRIPT)
	if not (ach_script is GDScript):
		return []
	var defs: Dictionary = (ach_script as GDScript).get_script_constant_map().get("DEFS", {})
	return defs.keys()

## The LIVE mode ids, straight off the catalog.
func _mode_ids() -> Array:
	var out: Array = []
	for m in GameModes.all():
		out.append(m.id)
	return out
