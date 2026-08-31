extends Node
## Haptics — a thin, intention-named wrapper over device vibration.
##
## Game code asks for a *feeling* ("light", "success", "impact") rather than a
## duration, so we can tune the whole game's tactile language in one place and
## respect the player's haptics toggle. No-ops on desktop and when disabled.

enum Feel { LIGHT, MEDIUM, HEAVY, SUCCESS, WARNING }

# Durations in milliseconds, tuned to feel like iOS-style taps.
const _DURATION := {
	Feel.LIGHT: 12,
	Feel.MEDIUM: 22,
	Feel.HEAVY: 38,
	Feel.SUCCESS: 30,
	Feel.WARNING: 50,
}

# Per-preference multiplier on every buzz length, so a player can soften a harsh
# motor or lengthen a weak one. Applied on top of the per-feel durations above.
const _STRENGTH := {
	"light": 0.6,
	"medium": 1.0,
	"strong": 1.6,
}

var _supported := false

func _ready() -> void:
	_supported = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")

## The player's strength multiplier (defaults to 1.0 for an unknown value).
func _strength_mult() -> float:
	return float(_STRENGTH.get(SettingsManager.haptic_strength(), 1.0))

func fire(feel: Feel) -> void:
	if not _supported or not SettingsManager.haptics_enabled():
		return
	var mult := _strength_mult()
	var ms: int = clampi(int(round(float(_DURATION.get(feel, 20)) * mult)), 4, 90)
	if feel == Feel.SUCCESS:
		# A light–pause–light double-tap reads as "success".
		Input.vibrate_handheld(clampi(int(round(12.0 * mult)), 4, 90))
		await get_tree().create_timer(0.06).timeout
		Input.vibrate_handheld(ms)
	else:
		Input.vibrate_handheld(ms)

# Convenience aliases used at call sites for readability.
func light() -> void: fire(Feel.LIGHT)
func medium() -> void: fire(Feel.MEDIUM)
func heavy() -> void: fire(Feel.HEAVY)
func success() -> void: fire(Feel.SUCCESS)
func warning() -> void: fire(Feel.WARNING)
