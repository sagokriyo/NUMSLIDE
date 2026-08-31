extends Node
## SettingsManager — user preferences (audio, theme, accessibility, haptics).
##
## Holds the authoritative copy of every preference, persists it through
## SaveManager, and emits a signal on change so any listening system updates
## live. Volumes are stored 0..1 (linear) and applied to audio buses by
## AudioManager which listens to `setting_changed`.
##
## Everything that enters the store is conformed to the schema first — the type of
## its DEFAULTS entry, clamped to its RANGES entry — on LOAD and on WRITE alike.
## A wrong-typed or out-of-range value is refused with a warning instead of being
## persisted verbatim for every consumer to defend itself against.

signal setting_changed(key: String, value: Variant)

const SECTION := "settings"

## Bumped whenever a one-time migration is added to _migrate(). The stored copy
## rides in the settings section under VERSION_KEY, so each migration runs on the
## boot that finds the save behind it and never again — the same version gate
## SaveManager uses for the save file itself.
const SETTINGS_VERSION := 1
const VERSION_KEY := "_version"

# Defaults define the schema. Anything missing from disk falls back here; keys
# in an old save that are no longer listed are simply ignored on load.
const DEFAULTS := {
	"sfx_volume": 0.8,
	"sound_enabled": true,         # master mute for all one-shot SFX
	"ambience_id": "",             # one of AudioManager.AMBIENCE_IDS, or "" for silence
	"ambience_volume": 0.7,
	"theme": "starforged",
	"haptics_enabled": true,
	"reduce_motion": false,        # removes confetti + drifting shard fields only
	"tilt_parallax": true,         # backdrop shifts gently with the phone's tilt
	"haptic_strength": "medium",   # "light" | "medium" | "strong" — vibration intensity
	"tile_speed": "normal",        # "slow" | "normal" | "fast" — tile animation timing
	"random_theme_each_game": false, # pick a random unlocked theme at each new game
	"slide_size": 4,               # 3, 4 or 5 — the tray Classic deals
}

# The sane range of every NUMERIC setting — both sliders live in 0..1 (settings.gd
# builds them min 0.0, max 1.0). Clamped here so no consumer has to clamp for
# itself: a stray caller or a hand-edited save can never hand the audio bus a 500%
# volume, nor make the Settings slider read back a value its own knob cannot show.
const RANGES := {
	"sfx_volume": {"min": 0.0, "max": 1.0},
	# The trays Classic offers. Below 3 the puzzle is trivial; above 5 a solve
	# stops being a sitting and the numerals stop fitting the glass.
	"slide_size": {"min": 3, "max": 5},
}

var _values: Dictionary = {}

func _ready() -> void:
	var stored := SaveManager.get_section(SECTION, {})
	_values = DEFAULTS.duplicate(true)
	for k in stored.keys():
		if _values.has(k):
			# Conform on load too: the save is plaintext on device, so a corrupted or
			# hand-edited entry falls back to its default instead of riding along and
			# poisoning every later read (and comparison) of that key.
			var clean: Variant = _sanitize(String(k), stored[k])
			if typeof(clean) == TYPE_NIL:
				push_warning("SettingsManager: stored '%s' is malformed (%s); using the default."
					% [String(k), var_to_str(stored[k])])
			else:
				_values[k] = clean
	var stored_version := int(stored.get(VERSION_KEY, 0))
	if stored_version < SETTINGS_VERSION:
		_migrate(stored_version)
		_persist()   # stamps VERSION_KEY, so a one-time migration can never re-fire

## One-time, version-gated migrations, oldest first. A save with no version at all
## reads as 0, so pre-versioning saves still get every step exactly once.
func _migrate(_from_version: int) -> void:
	# Nothing to migrate: NUMSLIDE ships version 1, and a key that is no longer in
	# DEFAULTS is simply ignored on load.
	pass

func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))

func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("SettingsManager: unknown setting '%s'." % key)
		return
	var clean: Variant = _sanitize(key, value)
	if typeof(clean) == TYPE_NIL:
		push_warning("SettingsManager: '%s' rejected %s — expected a value like %s."
			% [key, var_to_str(value), var_to_str(DEFAULTS[key])])
		return
	# typeof FIRST: `==` between two differently-typed Variants RAISES in GDScript,
	# which used to abort the write mid-guard so the setting silently never applied.
	var current: Variant = _values.get(key)
	if typeof(current) == typeof(clean) and current == clean:
		return
	_values[key] = clean
	_persist()
	setting_changed.emit(key, clean)

## Flips a boolean setting. Anything else — a String enum, a slider, an unknown
## key — is left alone with a warning rather than coerced into a bool.
func toggle(key: String) -> void:
	var current: Variant = get_value(key)
	if typeof(current) != TYPE_BOOL:
		push_warning("SettingsManager: toggle('%s') ignored — not a boolean setting." % key)
		return
	set_value(key, not bool(current))

## Writes the whole value dict out, plus the schema version alongside it. The
## version lives in the SECTION rather than in _values so it can never show up as
## a setting (get_value, the DEFAULTS schema and the screens stay untouched by it).
func _persist() -> void:
	var section := _values.duplicate(true)
	section[VERSION_KEY] = SETTINGS_VERSION
	SaveManager.set_section(SECTION, section)

# --- Type & range discipline -------------------------------------------------
## Returns `value` conformed to this key's schema entry: its type, clamped to its
## RANGES entry. Returns null when the value cannot be honoured (a String for a
## float key, a number for a bool key) — callers warn and drop the write rather
## than storing something the next comparison would raise on.
## Only two widenings are allowed: int -> float (JSON and callers alike hand us 1
## for 1.0) and StringName -> String. Nothing else converts, so a caller's mistake
## surfaces as a warning instead of a silently mangled preference.
func _sanitize(key: String, value: Variant) -> Variant:
	# An unknown key only reaches here if set_value's schema guard was bypassed;
	# with no schema entry to conform to, the value vouches for its own type.
	var want := typeof(DEFAULTS.get(key, value))
	var got := typeof(value)
	if want == TYPE_FLOAT and got == TYPE_INT:
		return _clamped(key, float(value))
	# JSON HAS ONE NUMBER TYPE. An int setting comes back off disk as a float, so
	# refusing it as "malformed" threw the player's choice away on every boot and
	# silently reset it to the default (the tray size picker did exactly that).
	if want == TYPE_INT and got == TYPE_FLOAT and is_equal_approx(float(value), floor(float(value))):
		return int(_clamped(key, float(value)))
	if want == TYPE_STRING and got == TYPE_STRING_NAME:
		return String(value)
	if got != want:
		return null
	if want == TYPE_FLOAT:
		return _clamped(key, float(value))
	if want == TYPE_INT:
		return int(_clamped(key, float(value)))
	return value

## Clamps a numeric setting to its declared range; a key with no RANGES entry
## passes through untouched.
func _clamped(key: String, value: float) -> float:
	if not RANGES.has(key):
		return value
	var r: Dictionary = RANGES[key]
	return clampf(value, float(r["min"]), float(r["max"]))

# --- Typed convenience accessors (read-site clarity) -------------------------
func sfx_volume() -> float: return float(get_value("sfx_volume"))
func sound_enabled() -> bool: return bool(get_value("sound_enabled"))
func theme_id() -> String: return String(get_value("theme"))
func haptics_enabled() -> bool: return bool(get_value("haptics_enabled"))
func haptic_strength() -> String: return String(get_value("haptic_strength"))
func reduce_motion() -> bool: return bool(get_value("reduce_motion"))
func tilt_parallax() -> bool: return bool(get_value("tilt_parallax"))
func tile_speed() -> String: return String(get_value("tile_speed"))
func random_theme_each_game() -> bool: return bool(get_value("random_theme_each_game"))
func slide_size() -> int: return int(get_value("slide_size"))
