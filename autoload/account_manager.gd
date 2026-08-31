## AccountManager — the game's identity facade.
##
## Identity is Google Play Games Services (PGS), the only provider: the OS signs
## the player in (one automatic prompt per launch, or manually via sign_in()),
## and PGS supplies a gamer tag + avatar. There is no email, no password, no
## app-level account, and no sign-out (PGS sessions are managed by the OS in the
## Play Games settings).
##
## This facade exists so screens never couple to the PGS adapter directly —
## the backend behind it can change without touching the frontend contract:
##   signals: auth_changed(), profile_changed(), sign_in_failed()
##   queries: is_configured(), is_signed_in(), display_name(), icon_uri(),
##            player_level()
##   actions: sign_in()
##
## Loads AFTER PlayGames (see project.godot) so _ready() can connect to it.
extends Node

signal auth_changed()
signal profile_changed()
signal sign_in_failed()

## Legacy Firebase session persistence (removed in the de-Firebase pivot).
## Cleared once on boot so the old plaintext refresh token leaves existing saves.
const LEGACY_SECTION := "account"

## True between an explicit sign_in() call and the authentication result — the
## automatic launch prompt must not surface failure UI, only manual attempts do.
var _manual_attempt := false

func _ready() -> void:
	SaveManager.clear_section(LEGACY_SECTION)
	PlayGames.authenticated.connect(_on_authenticated)
	PlayGames.player_loaded.connect(_on_player_loaded)

## True when an identity provider exists on this platform (PGS plugin present —
## Android builds only; false in the editor and on desktop).
func is_configured() -> bool:
	return PlayGames.is_available()

func is_signed_in() -> bool:
	return PlayGames.is_authenticated()

## The PGS gamer tag ("" until profile_changed has fired).
func display_name() -> String:
	return PlayGames.display_name()

## The PGS avatar uri ("" when absent).
func icon_uri() -> String:
	return PlayGames.icon_uri()

## The Play Games player level (0 until the player loads or when PGS omits it).
func player_level() -> int:
	return PlayGames.player_level()

## Interactive PGS sign-in prompt. PGS already auto-prompts once per launch;
## this is the manual entry point for a player who declined it.
func sign_in() -> void:
	_manual_attempt = true
	PlayGames.sign_in()

func _on_authenticated(is_authenticated: bool) -> void:
	if not is_authenticated and _manual_attempt:
		sign_in_failed.emit()
	_manual_attempt = false
	auth_changed.emit()

func _on_player_loaded(_display_name: String, _icon_uri: String) -> void:
	profile_changed.emit()
