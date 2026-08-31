extends Node
## AdManager — the single seam for (optional) interstitial ads in the free tier.
##
## Policy (deliberately MINIMAL, and tunable for testing): at most one
## interstitial after a COMPLETED game, and never more often than every
## SHOW_EVERY_N_GAMES games. Premium players (the "no_ads" capability) never see
## an ad — the entitlement check below is the only thing that decision needs.
##
## Flow is "arm then present": when a game ends we COUNT it and, if the cadence is
## due, arm an interstitial; it is shown later via present_pending() once the
## game-over modal is dismissed, so an ad never overlaps that modal.
##
## Phase 1 status: this is the GATING + CADENCE layer only. There is no real ad
## network wired yet — _present_interstitial() is a documented stub (it just logs
## in debug builds) until the Google AdMob native plugin lands in a later phase.
## Integrating AdMob then means filling in _present_interstitial() (and running the
## post-ad action on its close callback) and nothing else changes.
##
## Autoload order: declared after EntitlementManager and SaveManager (it reads
## both), and before SceneRouter.

const SECTION := "ads"

# --- Tunables (safe to change during testing) ---------------------------------
## Master switch for the whole ad system. Premium always overrides this to off.
const ENABLED := true
## Show an interstitial at most once per this many completed games (1 = every
## game). Bumped to 2 so the free experience stays light.
const SHOW_EVERY_N_GAMES := 2

var _games_since_ad := 0
var _pending_interstitial := false

func _ready() -> void:
	var data := SaveManager.get_section(SECTION, {})
	_games_since_ad = int(data.get("games_since_ad", 0))
	# Reset the cadence the moment a player goes premium so a later refund never
	# drops them back in mid-cadence.
	EntitlementManager.premium_changed.connect(_on_premium_changed)

func _on_premium_changed(is_premium_now: bool) -> void:
	if is_premium_now:
		_games_since_ad = 0
		_pending_interstitial = false
		_persist()

## Called by gameplay when a game finishes. Counts the game and ARMS an
## interstitial if the cadence is due (presented later, see present_pending).
func notify_game_completed() -> void:
	if not _should_serve_ads():
		return
	_games_since_ad += 1
	if _games_since_ad >= SHOW_EVERY_N_GAMES:
		_games_since_ad = 0
		_pending_interstitial = true
	_persist()

## Present an armed interstitial (if any) over `host`. Call when LEAVING the
## game-over screen so the ad never covers the game-over modal.
func present_pending(host: Node) -> void:
	if not _pending_interstitial:
		return
	_pending_interstitial = false
	_present_interstitial(host)

func _should_serve_ads() -> bool:
	if not ENABLED:
		return false
	return not EntitlementManager.has_capability("no_ads")

func _persist() -> void:
	SaveManager.set_section(SECTION, {"games_since_ad": _games_since_ad})

# --- The actual ad presentation (stub until AdMob is integrated) --------------
func _present_interstitial(_host: Node) -> void:
	# TODO(ads-phase): integrate Google AdMob via a Godot Android plugin and show
	# a real interstitial here. Until then this is a no-op so the free game runs
	# unchanged; the cadence + gating above are already correct and testable.
	# When wiring AdMob, run the caller's post-ad action on the ad CLOSE callback.
	if OS.is_debug_build():
		print("[AdManager] (stub) interstitial would show now.")
