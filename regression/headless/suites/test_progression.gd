extends "res://regression/headless/harness/script_test_base.gd"
## The progression funnel in NUMSLIDE terms: one finished board reported
## through Progression.record_series lands in the per-mode record, the lifetime
## stats, the purse (through the daily cap), the crowns and the rank ladder.
## Plus the drift checks: every mode in every catalog, every grade priced.
##
## Run:  godot --headless --path . --script res://regression/headless/harness/headless_boot.gd -- --test=res://regression/headless/suites/test_progression.gd
##
## PINS ITS OWN WORLD. Every save section the funnel touches is snapshotted,
## wiped to a known state (an empty purse, a fresh day, nothing unlocked) and
## restored at the end — and the autoloads that cache those sections in memory
## (GameStats, Achievements, Wallet, AdManager) are reloaded from the restored
## sections, so the developer's save comes back exactly as it was.

## Every section a series can dirty. "mode_records" is the funnel's own; the
## rest are the stats, history, badges, best series, the day's counters, the
## bounty board, the first clears, the purse and its ledger, the ad cadence, and
## the profile (the rank-up ceremony stamps `seen_tier` there).
const GUARDED_SECTIONS := [
	"stats", "score_history", "achievements", "best_scores", "economy_daily",
	"bounties", "first_clears", "wallet", "ledger", "ads", "mode_records", "profile",
]

var _snapshots: Dictionary = {}
var _had: Dictionary = {}
var _saved_tier: int = 0

func run_tests() -> void:
	_snapshot()
	_fresh_world()
	_test_catalog_drift()
	_test_series_score()
	_test_first_series_win()
	_test_lost_series()
	_test_assisted_run()
	_test_mastery_and_ratio()
	_test_top_grade_and_ladder()
	_test_daily_cap()
	_test_retired_mode_and_undo()
	_test_legacy_path()
	_restore()

# --- The pinned world ------------------------------------------------------------
func _snapshot() -> void:
	for sec: String in GUARDED_SECTIONS:
		_had[sec] = SaveManager.has_section(sec)
		_snapshots[sec] = SaveManager.get_section(sec, {})
	_saved_tier = int(SceneRouter._last_tier)

func _restore() -> void:
	for sec: String in GUARDED_SECTIONS:
		if bool(_had.get(sec, false)):
			SaveManager.set_section(sec, _snapshots[sec])
		else:
			SaveManager.clear_section(sec)
	_reload_autoloads()
	SceneRouter._last_tier = _saved_tier
	SaveManager.flush()

## Nothing played, nothing unlocked, an empty purse, a fresh day.
func _fresh_world() -> void:
	for sec: String in GUARDED_SECTIONS:
		SaveManager.clear_section(sec)
	var today := Time.get_date_string_from_system()
	SaveManager.set_section("economy_daily",
		{"date": today, "runs": 0, "coins_from_play": 0, "ad_coins": 0})
	SaveManager.set_section("bounties", {"date": today, "progress": {}, "paid": {}})
	# The grant stamp keeps reload_purse from paying the starter purse: the
	# checks below count coins from zero.
	SaveManager.set_section("wallet",
		{WalletRules.COINS: 0, WalletRules.GEMS: 0, Wallet.GRANT_KEY: Wallet.GRANT_ID})
	_reload_autoloads()
	# The rank-up ceremony is a screen, not a rule: keep it out of a unit suite
	# by telling the router every tier is already celebrated.
	SceneRouter._last_tier = TierBadge.count()

## Re-reads every cached section so memory matches the save, the way a boot
## would. Mirrors each autoload's own _ready.
func _reload_autoloads() -> void:
	var stored: Dictionary = SaveManager.get_section("stats", {})
	var fresh: Dictionary = GameStats.DEFAULTS.duplicate(true)
	for k in stored.keys():
		if fresh.has(k):
			fresh[k] = stored[k]
	GameStats._s = fresh
	Achievements._unlocked = SaveManager.get_section("achievements", {})
	Wallet.reload_purse()
	AdManager._games_since_ad = int(SaveManager.get_section("ads", {}).get("games_since_ad", 0))
	AdManager._pending_interstitial = false
	Progression.begin_run("")

## One series through the funnel, returning its receipt.
func _series(mode: String, won: bool, rw: int, rl: int, pace_id: String,
		undo: bool = false, elapsed: float = 60.0) -> Array:
	Progression.begin_run(mode)
	Progression.record_series(mode, won, rw, rl, pace_id, undo, elapsed)
	return Progression.take_reward()

func _has_line(lines: Array, id: String) -> bool:
	for line: Dictionary in lines:
		if String(line.get("id", "")) == id:
			return true
	return false

func _line_coins(lines: Array, id: String) -> int:
	for line: Dictionary in lines:
		if String(line.get("id", "")) == id:
			return int(line.get("coins", 0))
	return 0

# --- Drift: every mode in every catalog, every grade priced -----------------------
func _test_catalog_drift() -> void:
	print("test_catalog_drift:")
	var modes := GameModes.all()
	check("the catalog was read", not modes.is_empty())
	for m in modes:
		check("'%s' has a win crown" % m.id, Achievements.MODE_WIN_ACHIEVEMENT.has(m.id))
		var crown := String(Achievements.MODE_WIN_ACHIEVEMENT.get(m.id, ""))
		check("'%s' crown '%s' is in DEFS" % [m.id, crown], Achievements.DEFS.has(crown))
		check("'%s' pays first-win gems" % m.id, EconomyRules.MODE_WIN_GEMS.has(m.id))
		check("'%s' has a Best Series board" % m.id,
			PlayGamesIds.LEADERBOARD_BEST_SCORE_BY_MODE.has(m.id))
		check("'%s' has a mastery yardstick" % m.id, m.mastery_yardstick() > 0)
	for id in Achievements.MODE_MASTERY_ACHIEVEMENT:
		check("mastery crown '%s' names a mode" % id, GameModes.has_mode(String(id)))
		check("mastery crown '%s' rides on a win crown" % id,
			Achievements.MODE_WIN_ACHIEVEMENT.has(id))
		check("mastery crown '%s' is in DEFS" % id,
			Achievements.DEFS.has(String(Achievements.MODE_MASTERY_ACHIEVEMENT[id])))
	for id in Pace.LADDER:
		check("PACE_BONUS prices '%s'" % id, EconomyRules.PACE_BONUS.has(id))
	check("PACE_BONUS prices the assisted run", EconomyRules.PACE_BONUS.has(Progression.ASSISTED_RUN))
	for key in EconomyRules.PACE_BONUS:
		check("PACE_BONUS key '%s' is a grade or the assisted run" % key,
			Pace.LADDER.has(String(key)) or String(key) == Progression.ASSISTED_RUN)
	check("the ladder pays for strength",
		EconomyRules.pace_bonus("steady") <= EconomyRules.pace_bonus("sharp")
			and EconomyRules.pace_bonus("sharp") < EconomyRules.pace_bonus("expert")
			and EconomyRules.pace_bonus("expert") < EconomyRules.pace_bonus("perfect"))
	for id in ["first_solve", "perfect_pace", "perfect_run", "streak_7", "streak_30"]:
		check("the funnel's badge '%s' is in DEFS" % id, Achievements.DEFS.has(id))
	check_eq("DEFS and the Play Games catalog hold the same ids",
		PlayGamesIds.ACHIEVEMENTS.size(), Achievements.DEFS.size())
	for id in Achievements.DEFS:
		check("'%s' has a Play Games slot" % id, PlayGamesIds.ACHIEVEMENTS.has(id))

# --- The series score -----------------------------------------------------------------
func _test_series_score() -> void:
	print("test_series_score:")
	check_eq("three rounds against Perfect, won",
		EconomyRules.series_score(3, true, "perfect"),
		3 * EconomyRules.ROUND_POINTS + int(EconomyRules.PACE_BONUS["perfect"]))
	check_eq("three rounds against Perfect, lost: no bonus",
		EconomyRules.series_score(3, false, "perfect"), 3 * EconomyRules.ROUND_POINTS)
	check_eq("an assisted board pays its token bonus",
		EconomyRules.series_score(3, true, Progression.ASSISTED_RUN),
		3 * EconomyRules.ROUND_POINTS + int(EconomyRules.PACE_BONUS["assisted"]))
	check_eq("a negative round count scores nothing", EconomyRules.series_score(-2, false, "steady"), 0)
	check_eq("an unknown grade pays no bonus", EconomyRules.pace_bonus("nobody"), 0)

# --- The first series ever won ----------------------------------------------------
func _test_first_series_win() -> void:
	print("test_first_series_win:")
	check_eq("a fresh world has no rank", float(GameStats.best_mastery_ratio()["ratio"]), 0.0)
	check("nothing is unlocked to begin with", Achievements.unlocked_count() == 0)
	var coins0: int = Wallet.coins()
	var gems0: int = Wallet.gems()
	var lines := _series("classic", true, 3, 1, "sharp")
	var score := EconomyRules.series_score(3, true, "sharp")

	var rec: Dictionary = GameStats.mode_record("classic")
	check_eq("classic: one series played", int(rec["series_played"]), 1)
	check_eq("classic: one series won", int(rec["series_won"]), 1)
	check_eq("classic: three rounds won", int(rec["rounds_won"]), 3)
	check_eq("classic: one round lost", int(rec["rounds_lost"]), 1)
	check_eq("classic: streak of one", int(rec["current_streak"]), 1)
	check_eq("classic: best streak of one", int(rec["best_streak"]), 1)
	check_eq("classic: Sharp reached once", int((rec["grades_reached"] as Dictionary).get("sharp", 0)), 1)
	check_eq("classic: Sharp is the best grade", String(rec["best_grade"]), "sharp")

	check_eq("lifetime: one game", int(GameStats.get_stat("games_played")), 1)
	check_eq("lifetime: one win", int(GameStats.get_stat("games_won")), 1)
	check_eq("lifetime: four rounds played", int(GameStats.get_stat("rounds_played")), 4)
	check_eq("lifetime: three rounds won", int(GameStats.get_stat("rounds_won")), 3)
	check_eq("lifetime: win streak one", int(GameStats.get_stat("current_win_streak")), 1)
	check_eq("lifetime: best win streak one", int(GameStats.get_stat("best_win_streak")), 1)
	check_eq("lifetime: Sharp is rung two", int(GameStats.get_stat("grades_reached")), 2)
	check_eq("lifetime: best grade id", GameStats.best_grade_id(), "sharp")
	check_eq("the best series is the score", Progression.best_score("classic"), score)
	check_eq("the day streak started", int(GameStats.get_stat("current_streak_days")), 1)

	check("the Classic crown unlocked", Achievements.is_unlocked("classic_series"))
	check("First Board unlocked", Achievements.is_unlocked("first_solve"))
	check("Perfect Run unlocked (no undo)", Achievements.is_unlocked("perfect_run"))
	check("Classic Master is still locked", not Achievements.is_unlocked("classic_master"))
	check("the first clear is spent", Progression.has_first_clear("classic"))

	# Coins: the series payout (first of the day, and a new best on this board,
	# since nothing had been scored on it before), the day-1 streak and the first
	# clear. Gems: the first clear and one per badge. Every coin from play counts
	# against the cap.
	var payout: Dictionary = EconomyRules.run_payout("classic", score, true, 1, true, 0)
	var expected_coins: int = int(payout["coins"]) + EconomyRules.streak_payout(1) \
		+ EconomyRules.FIRST_CLEAR_BONUS
	check_eq("coins paid", Wallet.coins() - coins0, expected_coins)
	check_eq("gems paid", Wallet.gems() - gems0,
		EconomyRules.mode_win_gems("classic") + 3 * EconomyRules.GEMS_PER_BADGE)
	check_eq("the cap saw every coin", Progression.coins_earned_today(), expected_coins)
	var totals: Dictionary = Progression.reward_totals(lines)
	check_eq("the receipt totals the coins", int(totals["coins"]), expected_coins)
	check_eq("the receipt totals the gems", int(totals["gems"]), Wallet.gems() - gems0)
	check("the receipt names the win", _has_line(lines, Progression.REWARD_WIN))
	check("the receipt names the first clear", _has_line(lines, Progression.REWARD_FIRST_CLEAR))
	check("the receipt names the day's opener", _has_line(lines, Progression.REWARD_FIRST_OF_DAY))
	check("the receipt names the streak", _has_line(lines, Progression.REWARD_STREAK))
	check("the receipt names a badge", _has_line(lines, Progression.REWARD_BADGE))
	check("the receipt is taken once", not Progression.has_reward())

	var hist: Array = GameStats.score_history()
	check_eq("history holds the series", hist.size(), 1)
	if hist.size() == 1:
		var e: Dictionary = hist[0]
		check_eq("history names the grade", String(e.get("pace", "")), "sharp")
		check("history records the win", bool(e.get("won", false)))
		check_eq("history names the mode", String(e.get("mode", "")), "classic")

# --- A lost series still counts ---------------------------------------------------
func _test_lost_series() -> void:
	print("test_lost_series:")
	var lines := _series("classic", false, 1, 3, "expert")
	var rec: Dictionary = GameStats.mode_record("classic")
	check_eq("classic: two series played", int(rec["series_played"]), 2)
	check_eq("classic: still one won", int(rec["series_won"]), 1)
	check_eq("classic: rounds lost add up", int(rec["rounds_lost"]), 4)
	check_eq("classic: the streak broke", int(rec["current_streak"]), 0)
	check_eq("classic: the best streak stands", int(rec["best_streak"]), 1)
	check_eq("lifetime: two games", int(GameStats.get_stat("games_played")), 2)
	check_eq("lifetime: still one win", int(GameStats.get_stat("games_won")), 1)
	check_eq("lifetime: the win streak reset", int(GameStats.get_stat("current_win_streak")), 0)
	check_eq("lifetime: Expert was not beaten", int(GameStats.get_stat("grades_reached")), 2)
	check_eq("the best series stands", Progression.best_score("classic"),
		EconomyRules.series_score(3, true, "sharp"))
	check("a one-round loss pays nothing", lines.is_empty())
	check_eq("history keeps the loss", GameStats.score_history().size(), 2)
	# A series lost to nothing at all is still a game played.
	_series("classic", false, 0, 3, "steady")
	check_eq("a 0-3 loss is a game played", int(GameStats.get_stat("games_played")), 3)

# --- Pass-and-play is nobody's record -----------------------------------------------
func _test_assisted_run() -> void:
	print("test_assisted_run:")
	var games0: int = int(GameStats.get_stat("games_played"))
	_series("twist", true, 3, 2, Progression.ASSISTED_RUN)
	check("an assisted board leaves no mode record", not GameStats.has_mode_record("twist"))
	check("an assisted board earns no crown", not Achievements.is_unlocked("twist_series"))
	check_eq("an assisted board is still a game played", int(GameStats.get_stat("games_played")), games0 + 1)
	check_eq("an assisted board still posts a best series", Progression.best_score("twist"),
		EconomyRules.series_score(3, true, Progression.ASSISTED_RUN))
	check_eq("an assisted board leaves the win streak alone",
		int(GameStats.get_stat("current_win_streak")), 0)

# --- Mastery and the rank ladder --------------------------------------------------
func _test_mastery_and_ratio() -> void:
	print("test_mastery_and_ratio:")
	var yard: int = GameModes.get_mode("classic").mastery_yardstick()
	# Four more wins: half the ladder.
	for i in 4:
		_series("classic", true, 3, 0, "steady")
	var best: Dictionary = GameStats.best_mastery_ratio()
	check_eq("Classic carries the rank", String(best["mode_id"]), "classic")
	check_near("five of ten is half the ladder", float(best["ratio"]), 5.0 / float(yard))
	check_eq("half the ladder is Silver", TierBadge.current_index(float(best["ratio"])), 1)
	check("Classic Master is still locked at five", not Achievements.is_unlocked("classic_master"))
	for i in yard - 6:
		_series("classic", true, 3, 0, "steady")
	check_eq("one short of the ladder", int(GameStats.mode_record("classic")["series_won"]), yard - 1)
	check("Classic Master is locked one short", not Achievements.is_unlocked("classic_master"))
	_series("classic", true, 3, 0, "steady")
	check("Classic Master unlocks at the yardstick", Achievements.is_unlocked("classic_master"))
	check_near("the ladder is complete", float(GameStats.best_mastery_ratio()["ratio"]), 1.0)
	check_eq("a complete ladder is Gold", TierBadge.current_index(1.0), 2)
	check_eq("beating Steady never raises the rung", int(GameStats.get_stat("grades_reached")), 2)
	check_eq("Sharp stays Classic's best grade", String(GameStats.mode_record("classic")["best_grade"]), "sharp")
	_series("classic", true, 3, 0, "steady")
	_series("classic", true, 3, 0, "steady")
	# Not clamped: twelve series on a ten-series yardstick is 1.2, and the rank
	# ladder keeps climbing past Gold on it (Platinum at twice the yardstick).
	check_near("the ratio climbs past the yardstick",
		float(GameStats.best_mastery_ratio()["ratio"]), 1.2)
	# Blind has a win crown and no mastery crown: a full ladder there adds exactly
	# one badge, and never trips on a missing table entry.
	var n0: int = Achievements.unlocked_count()
	for i in GameModes.get_mode("fog").mastery_yardstick():
		_series("fog", true, 2, 0, "steady")
	check_eq("a mode with no mastery crown adds only its own crown",
		Achievements.unlocked_count(), n0 + 1)
	check_eq("the Blind ladder is complete too",
		int(GameStats.mode_record("fog")["series_won"]),
		GameModes.get_mode("fog").mastery_yardstick())

# --- Beating Perfect ---------------------------------------------------------------
func _test_top_grade_and_ladder() -> void:
	print("test_top_grade_and_ladder:")
	_series("twist", true, 3, 0, "perfect")
	check("Not One Wasted unlocks on a Perfect board", Achievements.is_unlocked("perfect_pace"))
	check("the Twist crown unlocks", Achievements.is_unlocked("twist_series"))
	check_eq("Perfect is the top rung", int(GameStats.get_stat("grades_reached")), 4)
	check_eq("the best grade is Perfect", GameStats.best_grade_id(), "perfect")
	check_eq("Twist's best grade is Perfect", String(GameStats.mode_record("twist")["best_grade"]), "perfect")
	check_eq("Classic still carries the rank", String(GameStats.best_mastery_ratio()["mode_id"]), "classic")
	check_eq("the best series overall is ranked", String(Progression.best_score_overall()["mode_id"]), "twist")

# --- The daily soft cap ----------------------------------------------------------------
func _test_daily_cap() -> void:
	print("test_daily_cap:")
	SaveManager.set_section("economy_daily", {
		"date": Time.get_date_string_from_system(), "runs": 1,
		"coins_from_play": EconomyRules.DAILY_SOFT_CAP, "ad_coins": 0,
	})
	check("the cap is reached", Progression.daily_cap_reached())
	var coins0: int = Wallet.coins()
	var lines := _series("classic", true, 3, 0, "steady")
	var score := EconomyRules.series_score(3, true, "steady")
	var payout: Dictionary = EconomyRules.run_payout("classic", score, true, 0, false,
		EconomyRules.DAILY_SOFT_CAP)
	check("the payout is halved", bool(payout["halved"]))
	check_eq("the halved payout is what was paid", Wallet.coins() - coins0, int(payout["coins"]))
	check("the receipt shows the cap's cut", _has_line(lines, Progression.REWARD_CAPPED))
	check("the cut is negative", _line_coins(lines, Progression.REWARD_CAPPED) < 0)
	check_eq("the receipt still totals to what was banked",
		int(Progression.reward_totals(lines)["coins"]), Wallet.coins() - coins0)

# --- A retired mode cannot carry the rank; an undo costs Perfect Run ----------------------
func _test_retired_mode_and_undo() -> void:
	print("test_retired_mode_and_undo:")
	_fresh_world()
	SaveManager.set_keyed(GameStats.MODE_RECORDS_SECTION, "colossus",
		{"series_played": 50, "series_won": 50})
	var best: Dictionary = GameStats.best_mastery_ratio()
	check_eq("a retired mode id is ignored", String(best["mode_id"]), "classic")
	check_eq("...and carries no ratio", float(best["ratio"]), 0.0)
	check_eq("no ratio is unranked", TierBadge.current_index(float(best["ratio"])), -1)
	_series("fog", true, 3, 0, "steady", true)
	check("the Fog crown unlocks", Achievements.is_unlocked("fog_series"))
	check("an undo costs Perfect Run", not Achievements.is_unlocked("perfect_run"))
	check("First Line unlocks on the first round won", Achievements.is_unlocked("first_solve"))
	check_near("one Fog win is a tenth of its ladder",
		float(GameStats.best_mastery_ratio()["ratio"]),
		1.0 / float(GameModes.get_mode("wild").mastery_yardstick()))

# --- The pre-series conductor's calls still work -------------------------------------------
func _test_legacy_path() -> void:
	print("test_legacy_path:")
	_fresh_world()
	Progression.begin_run("fog")
	for i in 3:
		Progression.record_turn()
	check_eq("record_turn counts moves", int(GameStats.get_stat("total_moves")), 3)
	Progression.record_undo()
	check_eq("record_undo counts undos", int(GameStats.get_stat("undos_used")), 1)
	Progression.record_win(false)
	Progression.record_merges("sprint", 1, GameModes.get_mode("sprint").win_target)
	check("the old crown hack still unlocks the crown", Achievements.is_unlocked("sprint_series"))
	var score := EconomyRules.series_score(3, true, "expert")
	check("conclude banks a run", Progression.conclude("fog", score, 3, true, 45.0))
	check_eq("conclude counts the game", int(GameStats.get_stat("games_played")), 1)
	check_eq("conclude posts the best series", Progression.best_score("fog"), score)
	check("conclude refuses an untouched board", not Progression.conclude("fog", 0, 0, false, 5.0))
	check_eq("an untouched board is not a game", int(GameStats.get_stat("games_played")), 1)
	check("the legacy path keeps no mode record", not GameStats.has_mode_record("fog"))
