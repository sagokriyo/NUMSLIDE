extends Node
## PlayGames — the Google Play Games Services adapter.
##
## Same shape as BillingService: wraps the native plugin behind a clean GDScript
## API, no-ops gracefully off-device (editor / desktop / a build without the
## plugin), warns instead of crashing, and keeps a redacted diagnostics log that
## also prints to `adb logcat` (`Select-String "PlayGames"`).
##
## IDENTITY (the whole point): PGS is the game's sole identity — it signs the
## player in and supplies the gamer tag, avatar uri and stable player id.
## Sign-in is terminal here: there is no app backend and no token exchange
## behind it. Screens consume identity through the AccountManager facade, which
## connects to `authenticated` / `player_loaded`. See
## docs/premium/phase-play-games.md.
##
## REWARDS: mirrors the game's own progression into Play Games — Achievements
## `unlocked` → unlock_achievement, GameStats `game_ended` → submit_score —
## keyed through PlayGamesIds and skipped while that catalog ships empty.
##
## Autoload order: AFTER GodotPlayGameServices (the plugin's own autoload, which
## we initialize) and AFTER Achievements + GameStats (whose signals we mirror);
## BEFORE AccountManager (whose _ready() connects to our signals).

signal authenticated(is_authenticated: bool)
signal player_loaded(display_name: String, icon_uri: String)
signal diagnostics_changed()

## One board's ranked entries arrived (or failed to). `mode_id` is OUR mode id,
## not the Play Console board id — the adapter reverse-maps it so no screen has
## to know the catalogue. `entries` is an array of plain Dictionaries (see
## `_normalize_score`), never addon objects: the Leaderboard screen renders from
## data it could equally be handed by a test, which is the only way a page that
## can ONLY be populated on a signed-in device is testable at all.
##
## `error` is "" on success and a short reason otherwise, so the page can say
## which precondition failed instead of showing an empty list either way.
signal board_loaded(mode_id: String, entries: Array, error: String)

## Diagnostics ring buffer size (mirrors BillingService).
const LOG_MAX := 24

var _sign_in: PlayGamesSignInClient
var _achievements: PlayGamesAchievementsClient
var _leaderboards: PlayGamesLeaderboardsClient
var _players: PlayGamesPlayersClient

var _available := false
var _authenticated := false
## Guards the interactive prompt to ONE automatic attempt per app launch. The
## flag is in-memory only, so a signed-out player is prompted once on every
## launch; persisting a decline across launches is a listed future tuning item.
var _interactive_sign_in_tried := false
var _player_id := ""
var _display_name := ""
var _icon_uri := ""
var _player_level := 0
var _log: Array[String] = []

func _ready() -> void:
	# The plugin's own autoload requires manual initialization before ANY client is
	# used — it returns PLUGIN_NOT_FOUND off-device, which is our dormant path.
	var err: int = GodotPlayGameServices.initialize()
	if err != GodotPlayGameServices.PlayGamesPluginError.OK:
		_log_event("plugin ABSENT (editor/desktop, or missing from the build) — PGS dormant")
		return
	_available = true
	_log_event("plugin FOUND → initialized")

	# v3+ exposes the feature clients as Nodes (not autoloads), so we own them.
	_sign_in = PlayGamesSignInClient.new()
	_achievements = PlayGamesAchievementsClient.new()
	_leaderboards = PlayGamesLeaderboardsClient.new()
	_players = PlayGamesPlayersClient.new()
	for c: Node in [_sign_in, _achievements, _leaderboards, _players]:
		add_child(c)

	_sign_in.user_authenticated.connect(_on_user_authenticated)
	_achievements.achievement_unlocked.connect(_on_achievement_unlocked)
	_leaderboards.score_submitted.connect(_on_score_submitted)
	_leaderboards.top_scores_loaded.connect(_on_top_scores_loaded)
	_players.current_player_loaded.connect(_on_current_player_loaded)

	# Mirror the game's own progression into PGS. Gameplay code stays untouched:
	# Achievements already evaluates every condition and emits `unlocked`.
	Achievements.unlocked.connect(_on_local_achievement_unlocked)
	GameStats.game_ended.connect(_on_game_ended)

	# PGS signs in automatically if the player is already signed into Play Games.
	_log_event("→ is_authenticated()")
	_sign_in.is_authenticated()

# --- Public API ---------------------------------------------------------------
func is_available() -> bool:
	return _available

func is_authenticated() -> bool:
	return _authenticated

func display_name() -> String:
	return _display_name

func icon_uri() -> String:
	return _icon_uri

## The stable per-game PGS player id ("" until the player loads). No consumer
## yet — captured for future keying.
func player_id() -> String:
	return _player_id

## The Play Games player level (0 until the player loads, or when PGS omits
## level info from the payload — real levels start at 1).
func player_level() -> int:
	return _player_level

## Manual sign-in, for the rare player who declined or isn't signed into Play Games.
func sign_in() -> void:
	if not _available:
		return
	_log_event("→ sign_in() [manual]")
	_sign_in.sign_in()

## Native PGS UI.
func show_achievements() -> void:
	if _available:
		_achievements.show_achievements()

func show_leaderboards() -> void:
	if _available:
		_leaderboards.show_all_leaderboards()

# --- Ranked entries -----------------------------------------------------------
## How many rows one board's page asks for. The plugin caps a page at 25; ten is
## what a phone screen shows without turning the standings into a scroll job.
const BOARD_PAGE_SIZE := 10

## Our mode id -> the Play Console board id we asked for, so the reply (which
## carries only the board id) can be mapped back. Cleared per reply.
var _board_requests: Dictionary = {}

## Asks for `mode_id`'s top entries. Returns the reason it could not, or "" when
## a request actually went out — the caller shows that reason rather than an
## empty list, because "nobody has played this" and "you are signed out" look
## identical once the rows are gone.
##
## Every failure is answered SYNCHRONOUSLY through the return value rather than
## by emitting; only a real request produces `board_loaded`. A page that had to
## wait for a signal to learn it was signed out would show a spinner forever.
func request_board(mode_id: String, force_reload: bool = true) -> String:
	if not _available:
		return "unavailable"
	if not _authenticated:
		return "signed_out"
	var board := PlayGamesIds.best_score_leaderboard(mode_id)
	if board.is_empty():
		return "not_configured"
	_board_requests[board] = mode_id
	_log_event("→ load_top_scores(%s)" % mode_id)
	_leaderboards.load_top_scores(board,
		PlayGamesLeaderboardVariant.TimeSpan.TIME_SPAN_ALL_TIME,
		PlayGamesLeaderboardVariant.Collection.COLLECTION_PUBLIC,
		BOARD_PAGE_SIZE, force_reload)
	return ""

func _on_top_scores_loaded(leaderboard_id: String,
		leaderboard_scores: PlayGamesLeaderboardScores) -> void:
	var mode_id := String(_board_requests.get(leaderboard_id, ""))
	_board_requests.erase(leaderboard_id)
	if mode_id.is_empty():
		_log_event("← top_scores for an unrequested board — ignored")
		return
	# A failed load arrives as an EMPTY payload rather than as an error, the same
	# way current_player does (see _on_current_player_loaded). Reporting that as
	# "no players yet" would be a lie on a board that simply did not answer, so
	# the two are told apart by the object being null at all.
	if leaderboard_scores == null:
		_log_event("← top_scores(%s): load failed" % mode_id)
		board_loaded.emit(mode_id, [], "failed")
		return
	var entries: Array = []
	for score: PlayGamesLeaderboardScore in leaderboard_scores.scores:
		entries.append(_normalize_score(score))
	_log_event("← top_scores(%s): %d entries" % [mode_id, entries.size()])
	board_loaded.emit(mode_id, entries, "")

## One addon score object flattened to the fields a row actually draws.
##
## Plain Dictionaries on purpose. The addon's classes only exist where the plugin
## does, so a screen typed against them could not be built — or tested — anywhere
## else, and this page has to render on desktop and in CI.
##
## `is_you` is resolved HERE, against the cached player id, because it is the one
## field the screen cannot work out for itself: display names are not unique.
func _normalize_score(score: PlayGamesLeaderboardScore) -> Dictionary:
	var holder_id := ""
	if score.score_holder != null:
		holder_id = score.score_holder.player_id
	return {
		"rank": score.rank,
		"display_rank": score.display_rank,
		"score": score.raw_score,
		"display_score": score.display_score,
		"name": score.score_holder_display_name,
		"icon_uri": score.score_holder_icon_image_uri,
		"player_id": holder_id,
		"is_you": not holder_id.is_empty() and holder_id == _player_id,
	}

# --- Plugin signal handlers ---------------------------------------------------
func _on_user_authenticated(is_auth: bool) -> void:
	_authenticated = is_auth
	_log_event("← user_authenticated: %s" % is_auth)
	authenticated.emit(is_auth)
	if not is_auth:
		# is_authenticated() only ASKS — it never prompts. Play Games answers
		# "SIGN_IN_REQUIRED" but its own "sign-in timing strategy" SUPPRESSES the
		# interactive prompt (verified in the GMS log), so auto sign-in alone leaves
		# the player signed out forever. Ask for the prompt explicitly.
		if not _interactive_sign_in_tried:
			_interactive_sign_in_tried = true
			_log_event("not authenticated (prompt was suppressed) → requesting interactive sign_in()")
			_sign_in.sign_in()
		return
	_players.load_current_player(false)

func _on_current_player_loaded(player: PlayGamesPlayer) -> void:
	# A failed load never arrives as null: the plugin emits a player built from an
	# empty payload (all fields ""). Guard on that, or a failed re-load would
	# clobber the cached profile and re-render screens as if no gamer tag existed.
	if player == null or player.player_id.is_empty():
		_log_event("← current_player: load failed (empty payload) — keeping cached profile")
		return
	_player_id = player.player_id
	_display_name = player.display_name
	_icon_uri = player.icon_image_uri if player.has_icon_image else ""
	if player.level_info != null and player.level_info.current_level != null:
		_player_level = player.level_info.current_level.level_number
	_log_event("← current_player: '%s' (level %d)" % [_display_name, _player_level])
	player_loaded.emit(_display_name, _icon_uri)

func _on_achievement_unlocked(is_unlocked: bool, achievement_id: String) -> void:
	_log_event("← achievement_unlocked(%s): %s" % [is_unlocked, achievement_id])

func _on_score_submitted(is_submitted: bool, leaderboard_id: String) -> void:
	_log_event("← score_submitted(%s): %s" % [is_submitted, leaderboard_id])

# --- Mirroring the game's own progression -------------------------------------
## Achievements has already evaluated the condition and persisted the unlock; we
## just forward it. Best-effort and fire-and-forget: a PGS failure must never affect
## the local unlock the player already earned.
func _on_local_achievement_unlocked(id: String, _def: Dictionary) -> void:
	if not _available:
		return
	var pgs_id := PlayGamesIds.achievement(id)
	if pgs_id.is_empty():
		_log_event("achievement '%s' has no Play Console id — skipped (fill core/play_games_ids.gd)" % id)
		return
	_log_event("→ unlock_achievement(%s)" % id)
	_achievements.unlock_achievement(pgs_id)

func _on_game_ended(score: int, highest_tile: int, mode_id: String) -> void:
	if not _available:
		return
	var board := PlayGamesIds.best_score_leaderboard(mode_id)
	if not board.is_empty() and score > 0:
		_log_event("→ submit_score(%s, %d)" % [mode_id, score])
		_leaderboards.submit_score(board, score)
	if not PlayGamesIds.LEADERBOARD_HIGHEST_TILE.is_empty() and highest_tile > 0:
		_log_event("→ submit_score(highest_tile, %d)" % highest_tile)
		_leaderboards.submit_score(PlayGamesIds.LEADERBOARD_HIGHEST_TILE, highest_tile)

# --- Diagnostics --------------------------------------------------------------
## Redacted one-line log of every plugin event; also print()ed so it reaches
## `adb logcat` from a debug export (release builds strip stdout — see the
## debug-keystore trick in docs/premium/phase-play-games.md). SECURITY: never
## record tokens or other credentials here — every line reaches logcat.
func diagnostics_log() -> Array[String]:
	return _log.duplicate()

func _log_event(line: String) -> void:
	_log.append(line)
	if _log.size() > LOG_MAX:
		_log.remove_at(0)
	print("PlayGames: %s" % line)
	diagnostics_changed.emit()
