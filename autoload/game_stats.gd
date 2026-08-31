extends Node
## GameStats — lifetime player statistics, in NUMSLIDE terms.
##
## Aggregates across every series ever played. Progression reports outcomes
## through record_*(); this rolls them into persisted totals and emits
## `stats_changed` so the Statistics screen and Home summary stay live. It is a
## DUMB STORE: what counts as a win, which rival counts, when a streak breaks,
## all of that is Progression's policy. This file only adds up.
##
## A "game" here is one finished SERIES (first to N rounds). Rounds are counted
## separately, so the win rate is the series win rate and "rounds won" is the
## grind underneath it.

signal stats_changed

## Emitted once per completed series, with that series' own result (NOT the
## lifetime totals). PlayGames observes it to submit leaderboard scores; nothing
## in the game loop depends on it. The second value is the player's best series
## WIN STREAK after this game, which is what the cross-mode board ranks.
signal game_ended(score: int, win_streak: int, mode_id: String)

const SECTION := "stats"
const HISTORY_SECTION := "score_history"
const HISTORY_MAX := 12

## Per-mode series records, written by Progression.record_series and read by
## the shell: {mode_id: {series_played, series_won, rounds_won, rounds_lost,
## best_streak, current_streak, grades_reached: {pace_id: n}, best_grade,
## best_streak}}. Named here rather than in Progression because this autoload
## loads first and `best_mastery_ratio` reads it.
const MODE_RECORDS_SECTION := "mode_records"

## What a mode's record looks like before it has one. Every reader goes through
## mode_record(), so a key added here lands on every screen at once.
const MODE_RECORD_DEFAULTS := {
	"series_played": 0,
	"series_won": 0,
	"rounds_won": 0,
	"rounds_lost": 0,
	"best_streak": 0,
	"current_streak": 0,
	"grades_reached": {},
	"best_grade": "",
}

## Ceiling for ONE game's duration (24h). Anything longer is clock noise, not
## play time — an app left suspended for days, or a device clock that jumped.
const MAX_GAME_SECONDS := 86400.0

const DEFAULTS := {
	# Series.
	"games_played": 0,
	"games_won": 0,
	"best_score": 0,
	"total_score": 0,
	# Rounds inside those series.
	"rounds_played": 0,
	"rounds_won": 0,
	# Series won in a row against a rival. A loss resets; pass-and-play and the
	# Daily puzzle leave it alone (see Progression.record_series).
	"current_win_streak": 0,
	"best_win_streak": 0,
	# The strongest rival ever beaten, as a rung on Pace.LADDER: 0 nobody,
	# 1 Pip, 2 Rook, 3 Sage, 4 Oracle.
	"grades_reached": 0,
	"total_moves": 0,
	"total_play_seconds": 0.0,
	"longest_session_seconds": 0.0,
	"current_streak_days": 0,
	"max_streak_days": 0,
	"undos_used": 0,
	"last_played_unix": 0,
	# LOCAL calendar day (days since 1970-01-01) of the last recorded game — what
	# the day streak actually counts. 0 on a save written before this existed;
	# _last_local_day() then derives it from last_played_unix.
	"last_played_day": 0,
	# DEAD KEYS from the 2048 code base. Kept so an old save still loads and an
	# old reader still finds a number; nothing on the series path writes them.
	"highest_tile": 0,
	"total_merges": 0,
	"modes": {},   # legacy per-mode totals {games, wins, time, best}; see mode_record()
}

var _s: Dictionary = {}

func _ready() -> void:
	var stored := SaveManager.get_section(SECTION, {})
	_s = DEFAULTS.duplicate(true)
	for k in stored.keys():
		if _s.has(k):
			_s[k] = stored[k]

func get_stat(key: String) -> Variant:
	return _s.get(key, DEFAULTS.get(key))

func average_score() -> int:
	var n: int = _s["games_played"]
	return 0 if n == 0 else int(round(float(_s["total_score"]) / n))

## Series won over series played.
func win_rate() -> float:
	var n: int = _s["games_played"]
	return 0.0 if n == 0 else float(_s["games_won"]) / n

## Rounds won over rounds played.
func round_win_rate() -> float:
	var n: int = int(_s.get("rounds_played", 0))
	return 0.0 if n == 0 else float(int(_s.get("rounds_won", 0))) / n

## The strongest rival ever beaten, as a persona id ("" for nobody yet).
func best_grade_id() -> String:
	var rung: int = int(_s.get("grades_reached", 0))
	if rung <= 0 or rung > Pace.LADDER.size():
		return ""
	return Pace.LADDER[rung - 1]

## Called once per move from gameplay (through Progression.record_turn).
func record_move(merges_this_move: int = 0) -> void:
	_s["total_moves"] += 1
	_s["total_merges"] += merges_this_move
	# Durable without a disk write per move: the counter lands in SaveManager,
	# which marks itself dirty and coalesces the real write over its quiet window.
	# A synchronous write per move is exactly what caused the on-device
	# micro-stutter, while leaving the counter in memory only made its durability
	# an accident of some LATER write. The OS pause/close hooks flush instantly,
	# so a crash costs at most ~1s of moves. set_section_fields, not _stage():
	# staging deep-copies the WHOLE section per move, the field merge copies only
	# the counter. Deliberately no stats_changed: nothing may rebuild live stat UI
	# mid-move.
	SaveManager.set_section_fields(SECTION, {"total_moves": _s["total_moves"]})

## Legacy: the 2048 funnel's merge counter. Nothing on the series path calls
## this; it stays so `Progression.record_merges` keeps working until the
## conductor is switched over.
func record_merges(count: int) -> void:
	_s["total_merges"] += count

## Called whenever the player uses Undo.
func record_undo() -> void:
	_s["undos_used"] = int(_s.get("undos_used", 0)) + 1
	_persist()

## Legacy: the 2048 funnel's high-water tile. Nothing on the series path calls
## this; see record_merges.
func note_highest_tile(value: int) -> void:
	if value > int(_s["highest_tile"]):
		_s["highest_tile"] = value
		_persist()

## Legacy entry, kept for the pre-series conductor and its flow test. `highest`
## was the 2048 top tile; the conductor's hack passed the rounds won in its
## place, which is exactly what the series path counts, so it is read as that.
## No rival is known here, so the win streak and the rival rung stay put.
func record_game_end(score: int, highest: int, won: bool, duration: float, mode_id: String = "") -> void:
	record_series(score, won, maxi(highest, 0), 0, 0, duration, mode_id)

## One finished series. `duration` in seconds; an implausible one is dropped
## (see _sane_duration) while the game itself still counts.
##
## `pace_rung` is the rival's place on Pace.LADDER (1 Pip .. 4 Oracle), or
## 0 when the series was not a ladder duel (pass-and-play, the Daily puzzle, the
## legacy path). Only a ladder duel moves the win streak or the rivals-beaten
## mark; Progression decides that and passes 0 for everything else.
func record_series(score: int, won: bool, rounds_won: int, rounds_lost: int,
		pace_rung: int, duration: float, mode_id: String = "") -> void:
	var played := _sane_duration(duration)
	_s["games_played"] += 1
	if won:
		_s["games_won"] += 1
	_s["total_score"] += score
	_s["best_score"] = max(int(_s["best_score"]), score)
	_s["rounds_played"] = int(_s.get("rounds_played", 0)) + maxi(rounds_won, 0) + maxi(rounds_lost, 0)
	_s["rounds_won"] = int(_s.get("rounds_won", 0)) + maxi(rounds_won, 0)
	_s["total_play_seconds"] += played
	_s["longest_session_seconds"] = max(float(_s["longest_session_seconds"]), played)
	if pace_rung > 0:
		if won:
			_s["current_win_streak"] = int(_s.get("current_win_streak", 0)) + 1
			_s["best_win_streak"] = max(int(_s.get("best_win_streak", 0)), int(_s["current_win_streak"]))
			_s["grades_reached"] = max(int(_s.get("grades_reached", 0)), pace_rung)
		else:
			_s["current_win_streak"] = 0
	if mode_id != "":
		var modes: Dictionary = _s.get("modes", {})
		var m: Dictionary = modes.get(mode_id, {})
		m["games"] = int(m.get("games", 0)) + 1
		m["wins"] = int(m.get("wins", 0)) + (1 if won else 0)
		m["time"] = float(m.get("time", 0.0)) + played
		m["best"] = max(int(m.get("best", 0)), score)
		modes[mode_id] = m
		_s["modes"] = modes
	_update_streak()
	_persist()
	game_ended.emit(score, int(_s.get("best_win_streak", 0)), mode_id)

## Legacy per-mode totals: {games, wins, time, best}. Empty dict if never
## played. The series records the shell reads are mode_record().
func mode_stats(mode_id: String) -> Dictionary:
	var modes: Dictionary = _s.get("modes", {})
	return modes.get(mode_id, {})

## One mode's series record, defaulted, as a copy. Never empty: a mode that has
## never been played reads as zeros, so no screen has to guard the keys.
func mode_record(mode_id: String) -> Dictionary:
	var rec: Dictionary = MODE_RECORD_DEFAULTS.duplicate(true)
	var stored := SaveManager.get_keyed(MODE_RECORDS_SECTION, mode_id, {})
	for k in stored.keys():
		if rec.has(k):
			rec[k] = stored[k]
	return rec

## True once `mode_id` has a series on record.
func has_mode_record(mode_id: String) -> bool:
	return SaveManager.has_keyed(MODE_RECORDS_SECTION, mode_id)

## The player's best "mastery ratio" across every mode played: series won in a
## mode, divided by THAT mode's own yardstick (GameModes.Mode.mastery_yardstick,
## ten series unless the mode names its own). Mastering any mode means ratio
## 1.0 whatever its yardstick, which is what makes the Tier badge normalized
## across boards instead of one mode's grind trivializing another's.
##
## Clamped to 0..1: the rank ladder asks "how far to mastery", and a mode
## mastered twice over is still mastered. Walks the CATALOG rather than the
## save, so a retired mode id an old save still carries cannot inflate the
## answer, and ties break on catalog order rather than dictionary iteration.
## Defaults to Classic (ratio 0.0) when nothing has been played yet.
func best_mastery_ratio() -> Dictionary:
	var best_ratio := 0.0
	var best_mode := "classic"
	var records := SaveManager.get_section(MODE_RECORDS_SECTION, {})
	for mode in GameModes.all():
		if not records.has(mode.id) or typeof(records[mode.id]) != TYPE_DICTIONARY:
			continue
		var yard: int = mode.mastery_yardstick()
		if yard <= 0:
			continue
		var rec: Dictionary = records[mode.id]
		# Not clamped: the rank ladder climbs past Gold on multiples of the yardstick
		# (Platinum at twice it, and so on), the way the siblings' tile ladder does.
		var ratio := float(int(rec.get("series_won", 0))) / float(yard)
		if ratio > best_ratio:
			best_ratio = ratio
			best_mode = mode.id
	return {"ratio": best_ratio, "mode_id": best_mode}

## Append a completed series to the dated history (keeps the most recent N).
## A series with a rival named is always kept, a loss included: the Recent
## Runs rail is a record of what was played, not a highlight reel. The legacy
## call (no rival) keeps its old rule and skips a scoreless run.
func add_score_entry(score: int, mode_id: String, pace_id: String = "", won: bool = false) -> void:
	if score <= 0 and pace_id.is_empty():
		return
	var sec := SaveManager.get_section(HISTORY_SECTION, {})
	var hist: Array = sec.get("entries", [])
	hist.append({"score": score, "mode": mode_id, "pace": pace_id, "won": won,
		"t": int(Time.get_unix_time_from_system())})
	while hist.size() > HISTORY_MAX:
		hist.pop_front()
	sec["entries"] = hist
	SaveManager.set_section(HISTORY_SECTION, sec)

## Series history, most-recent first. Each entry: {score, mode, rival, won, t}.
## Entries from before rivals were recorded carry no `rival` and no `won`.
func score_history() -> Array:
	var sec := SaveManager.get_section(HISTORY_SECTION, {})
	var hist: Array = sec.get("entries", [])
	var out := hist.duplicate()
	out.reverse()
	return out

## Lifetime playtime may only ever move FORWARD. A negative duration (the device
## clock rolled back mid-game) would subtract from it, and a wild one would spike
## "longest session" forever — neither is recoverable once persisted, so both are
## clamped away here. Only the duration is dropped; the game still counts.
func _sane_duration(duration: float) -> float:
	if not is_finite(duration) or duration <= 0.0:
		if duration != 0.0:
			push_warning("GameStats: ignoring implausible game duration (%s s)." % str(duration))
		return 0.0
	if duration > MAX_GAME_SECONDS:
		push_warning("GameStats: capping game duration (%s s) at %d s." % [str(duration), int(MAX_GAME_SECONDS)])
		return MAX_GAME_SECONDS
	return duration

## The "DAY STREAK" counts LOCAL CALENDAR days, not rolling 24h windows: two
## plays either side of local midnight are two days even 20 minutes apart, and a
## 25h gap that stays inside one calendar day is still one day. The old
## int((now - last) / 86400.0) got both backwards and drifted with DST.
func _update_streak() -> void:
	var now := int(Time.get_unix_time_from_system())
	var today := _today_local_day()
	var last_day := _last_local_day()
	if last_day <= 0:
		_s["current_streak_days"] = 1                    # first game ever
	else:
		var days_apart := today - last_day
		if days_apart == 1:
			_s["current_streak_days"] = int(_s.get("current_streak_days", 0)) + 1
		elif days_apart > 1:
			_s["current_streak_days"] = 1                # a calendar day was missed
		# days_apart <= 0 -> same local day (or the clock/timezone went backwards):
		# hold. A device clock or a flight west must never break a streak; storing
		# `today` below lets the count resume normally from the next real day.
	if int(_s.get("current_streak_days", 0)) < 1:
		_s["current_streak_days"] = 1                    # a game played is always >= 1
	_s["max_streak_days"] = max(int(_s.get("max_streak_days", 0)), int(_s["current_streak_days"]))
	_s["last_played_day"] = today
	_s["last_played_unix"] = now

## Today's local calendar day. Read from the SYSTEM's own local date, so it is
## timezone- and DST-correct by construction (no offset arithmetic).
func _today_local_day() -> int:
	return _day_number(Time.get_date_dict_from_system(false))

## The local calendar day of the last recorded game. BACKWARD COMPATIBILITY: a
## save written before `last_played_day` existed carries only `last_played_unix`,
## so derive the day from that stamp instead of treating the player as brand new
## (which would silently reset a long streak on their next game).
func _last_local_day() -> int:
	var stored: int = int(_s.get("last_played_day", 0))
	if stored > 0:
		return stored
	var last_unix: int = int(_s.get("last_played_unix", 0))
	if last_unix <= 0:
		return 0
	# The legacy stamp is a UTC instant that never recorded the offset it was
	# taken at; the CURRENT offset is the best approximation available and is
	# accurate to the hour — all a date comparison needs. One game later the
	# stored day takes over and this path is never used again.
	var bias_seconds: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return _day_number(Time.get_datetime_dict_from_unix_time(last_unix + bias_seconds))

## Days since 1970-01-01 for a {year, month, day} dict, using the engine's own
## calendar math (leap years, month lengths) instead of hand-rolled arithmetic.
## The dict is read as a wall-clock date, so both sides of any comparison must be
## built the same way (both LOCAL, as above).
func _day_number(date: Dictionary) -> int:
	var midnight: int = Time.get_unix_time_from_datetime_dict({
		"year": int(date.get("year", 1970)),
		"month": int(date.get("month", 1)),
		"day": int(date.get("day", 1)),
		"hour": 0, "minute": 0, "second": 0,
	})
	return int(floor(float(midnight) / 86400.0))

## Hands the FULL totals to SaveManager WITHOUT emitting; the write is debounced
## there. The per-move hot path bypasses this with a one-field merge (see
## record_move) so a move never deep-copies the whole section.
func _stage() -> void:
	SaveManager.set_section(SECTION, _s)

func _persist() -> void:
	_stage()
	stats_changed.emit()

## Human-friendly duration like "1h 24m" or "3m 12s".
func format_duration(seconds: float) -> String:
	var s := int(seconds)
	@warning_ignore("integer_division")
	var h := s / 3600
	@warning_ignore("integer_division")
	var m := (s % 3600) / 60
	var sec := s % 60
	if h > 0:
		return "%dh %dm" % [h, m]
	if m > 0:
		return "%dm %ds" % [m, sec]
	return "%ds" % sec
