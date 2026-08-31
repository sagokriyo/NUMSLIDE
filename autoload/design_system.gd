extends Node
## DesignSystem — the single source of truth for non-color design tokens.
##
## Spacing, corner radii, typography scale, motion curves and elevation live
## here so every screen reads from one place. Colours are intentionally NOT
## here: they belong to ThemeManager because they change per theme. Together
## DesignSystem (constant) + ThemeManager (variable) describe the whole look.
##
## Everything is expressed in "design points" at a 1080 x 2340 reference
## resolution. The project stretches with "canvas_items", so points map
## cleanly across phones and tablets.

# --- Spacing scale (8pt grid) -------------------------------------------------
const SPACE_XS := 4.0
const SPACE_SM := 8.0
const SPACE_MD := 16.0
const SPACE_LG := 24.0
const SPACE_XL := 40.0
const SPACE_2XL := 64.0
const SPACE_3XL := 96.0

# --- Layout -------------------------------------------------------------------
## The widest a single content column is ever allowed to grow. The whole UI is
## authored at the 1080-point reference width; with stretch aspect "expand", a
## tablet (or a wide-aspect phone) gets a genuinely wider viewport, so an
## EXPAND_FILL column would stretch past its designed measure and read as
## over-enlarged. Columns wrapped in `UI.constrain_width` hold to this and centre
## the overflow instead, while backgrounds/FX still use the whole screen.
const MAX_CONTENT_WIDTH := 1080.0

# --- Corner radii -------------------------------------------------------------
const RADIUS_SM := 14.0
const RADIUS_MD := 22.0
const RADIUS_LG := 32.0
const RADIUS_XL := 44.0
const RADIUS_PILL := 999.0

# --- Typography (sizes in points) --------------------------------------------
## A restrained type ramp, sized generously for mobile legibility. Display is
## reserved for the score / hero numbers; everything else steps down in rhythm.
## The reading tiers (body / label / caption) are set in Nunito, which has a
## smaller x-height than the display face (Malam Poek), so they're sized a touch
## larger than a bubble-font ramp would need to keep body text comfortably legible.
##
## The floor is the CAPTION: at the 1080-point reference a 1080-px phone draws
## one point per pixel, so caption 36 is ~13.5 sp on a 420-dpi handset, the
## smallest secondary text Android considers readable. The earlier 30 landed
## at ~11 sp and every description line on Settings / Leaderboard / Profile
## read as fine print. Nothing in the app may set type below this token.
const TYPE_DISPLAY := 132
const TYPE_TITLE := 62
const TYPE_HEADLINE := 50
const TYPE_BODY := 44
const TYPE_LABEL := 40
const TYPE_CAPTION := 36

const LETTER_SPACING_TIGHT := -1.0
const LETTER_SPACING_WIDE := 2.0

# --- The house gain -----------------------------------------------------------
## Every size a screen asks for goes through here. The 2048 numbers read small on
## a phone (the user's standing ask is 15–20 % larger type and icons than 2048),
## so the whole ramp runs a gain, hierarchy intact. It COMPOUNDS with
## SceneRouter.UI_SCALE (1.1): on a phone a size here draws at TYPE_GAIN × 1.1
## of its 2048 number. Judge sizes on a phone (or in sp), never in a desktop
## window.
const TYPE_GAIN := 1.10
## The floor, applied AFTER the gain: nothing the player reads may be set below
## it. FitLabel minimums bypass it via `scale_type`, since shrinking is their job.
const TYPE_FLOOR := 32
## Decorative icons grow by this so they keep pace with the text beside them.
const ICON_GAIN := 1.12

## The gain alone, no floor. For a FitLabel's minimum, or anything that must
## stay inside a box it was sized against.
func scale_type(size: int) -> int:
	return int(round(float(size) * TYPE_GAIN))

## The size a label wears for a designed point size.
func type(size: int) -> int:
	return maxi(scale_type(size), TYPE_FLOOR)

## The designed size as is: no gain, no floor. For a fixed composition the gain
## would crowd (a name plate laid over art in a band that is a set fraction of
## the card). Goes through here so the exemption is visible and searchable.
func type_plain(size: int) -> int:
	return size

## The box a decorative icon takes for a designed box.
func icon(box: float) -> float:
	return box * ICON_GAIN

## Whether the player has asked for reduced motion. Every ambient effect asks
## THIS, so one switch reaches the sky, the dust, the sheen, the entrances and
## the confetti alike.
func reduce_motion() -> bool:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null:
		return false
	return bool(sm.get_value("reduce_motion"))

# --- Motion (seconds) ---------------------------------------------------------
## Calm, confident timings. Nothing snaps; nothing drags.
const DUR_INSTANT := 0.08
const DUR_FAST := 0.14
const DUR_BASE := 0.24
const DUR_SLOW := 0.42
const DUR_PAGE := 0.5

# Tile-specific motion. Kept very short so the board feels snappy and swipes
# register instantly; tweens are time-based, so these read smooth at 60Hz and
# smoother still at 90/120Hz. TILE_MOVE_DUR doubles as the per-move input lock.
const TILE_MOVE_DUR := 0.07
const TILE_SPAWN_DUR := 0.09
const TILE_MERGE_DUR := 0.09
const TILE_SPAWN_SCALE := 0.6
const TILE_MERGE_OVERSHOOT := 1.12

## Player-facing tile animation speed: a multiplier on the tile durations above.
## "fast" makes the board snappier, "slow" makes moves easier to follow. The move
## await (and thus the per-move input lock) rides these too, so the whole feel
## scales coherently. Read via the tile_*_dur() accessors below.
const _TILE_SPEED_SCALE := {"slow": 1.7, "normal": 1.0, "fast": 0.5}

func tile_speed_scale() -> float:
	return float(_TILE_SPEED_SCALE.get(SettingsManager.get_value("tile_speed"), 1.0))

func tile_move_dur() -> float: return TILE_MOVE_DUR * tile_speed_scale()
func tile_spawn_dur() -> float: return TILE_SPAWN_DUR * tile_speed_scale()
func tile_merge_dur() -> float: return TILE_MERGE_DUR * tile_speed_scale()

# --- Elevation (soft shadow presets) -----------------------------------------
## Returns shadow parameters {color, size, offset} for a StyleBoxFlat.
## Premium shadows are large, soft, and low-contrast — never a hard drop.
static func shadow(level: int, base: Color) -> Dictionary:
	match level:
		0:
			return {"size": 0, "offset": Vector2.ZERO, "color": Color(0, 0, 0, 0)}
		1:
			return {"size": 8, "offset": Vector2(0, 3), "color": Color(base.r, base.g, base.b, 0.20)}
		2:
			return {"size": 14, "offset": Vector2(0, 6), "color": Color(base.r, base.g, base.b, 0.26)}
		_:
			return {"size": 24, "offset": Vector2(0, 10), "color": Color(base.r, base.g, base.b, 0.32)}

## Convenience: an eased Tween configured the "house" way (smooth, calm).
func ease_out(node: Node) -> Tween:
	var t := node.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	return t

## A gentle spring used for spawns and merges.
func spring(node: Node) -> Tween:
	var t := node.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	return t
