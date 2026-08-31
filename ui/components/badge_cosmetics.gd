class_name BadgeCosmetics
extends RefCounted
## BadgeCosmetics — everything a player dresses their rank badge with beyond the
## shield itself: the NAMEPLATE their name sits on, the TITLE they wear under it,
## and the EFFECT the emblem gives off.
##
## Frames are deliberately NOT here. `TierBadge.add_frame` already owned them
## before this file existed and every badge in the app calls it, so moving them
## would have meant touching the Profile portrait, the identity sheet preview and
## the share card to gain nothing. TierBadge owns the frame catalogue; this file
## owns the other three slots and the rules they share.
##
## Three slots, and they are earned in two different ways on purpose:
##
##   plate   gem-priced decoration      (EconomyRules.COSMETICS)
##   effect  gem-priced decoration      (EconomyRules.COSMETICS)
##   title   EARNED IN PLAY, never sold
##
## A title is a claim about what you have done — "Mountain Mover", "Devoted" —
## and a claim you can buy is not a claim. Selling one would also be the first
## thing in the economy that lets gems stand in for play, which is exactly the
## line `EconomyRules` is written to hold. Plates and effects say nothing about
## the player, so they are safe to sell.
##
## Everything equipped lives in the "profile" save section beside the name and
## the aura (`plate`, `effect`, `title`) — identity, not property. OWNERSHIP
## lives in the wallet. That split is what lets un-equipping a plate be free and
## a wipe of one leave the other alone.
##
## Every reader here goes through `plate_of` / `effect_of` / `title_of`, which
## re-check ownership on the way out. A save that names a cosmetic the player
## does not own — an old save, a shortened catalogue, a hand-edited file — must
## render as "none" rather than hand out the decoration for free.

const SECTION := "profile"

# =============================================================================
# NAMEPLATES
# =============================================================================

## The banner the player name sits on. Index 0 is bare — the shipped look, and
## the one every existing profile is already wearing.
const PLATES := ["None", "Foil", "Carbon", "Aurora", "Ember"]
const PLATE_IDS := ["none", "foil", "carbon", "aurora", "ember"]

## The cosmetic id owning plate index `i` ("" when out of range).
static func plate_cosmetic_id(i: int) -> String:
	if i < 0 or i >= PLATE_IDS.size():
		return ""
	return "plate_" + String(PLATE_IDS[i])

## The plate the player has equipped AND owns, 0 otherwise.
static func plate_of(p: Dictionary) -> int:
	var i := int(p.get("plate", 0))
	if i <= 0 or i >= PLATES.size():
		return 0
	return i if Wallet.owns_cosmetic(plate_cosmetic_id(i)) else 0

## Wraps `label` in its nameplate and hands back what to add to the layout. Plate
## 0 returns the label untouched, so a bare name costs no extra nodes.
##
## A MarginContainer rather than a PanelContainer: the backdrop has to be able to
## bleed WIDER than the text (a nameplate that hugs a three-letter name reads as a
## text field), and only a full-rect child inside a margin can do that.
static func plate_for(label: Control, index: int, accent: Color) -> Control:
	if index <= 0 or index >= PLATES.size():
		return label
	var holder := MarginContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Generous on the long axis: a plate that hugs the letters reads as a
	# highlighter pen, and the whole point of a nameplate is that the name is
	# MOUNTED on something.
	holder.add_theme_constant_override("margin_left", int(DesignSystem.SPACE_XL))
	holder.add_theme_constant_override("margin_right", int(DesignSystem.SPACE_XL))
	holder.add_theme_constant_override("margin_top", int(DesignSystem.SPACE_SM))
	holder.add_theme_constant_override("margin_bottom", int(DesignSystem.SPACE_SM))
	for layer in _plate_layers(index, accent):
		holder.add_child(layer)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(label)
	return holder

## The plate behind a name, as ONE translucent glass bar.
##
## It was a GradientPanel — and twice wrong for it. The obvious problem is that
## GradientPanel's shader mixes col_a and col_b as RGB and takes its alpha from
## the rounded mask alone, so the colour alphas were silently discarded and the
## "translucent" plate went on rendering as a solid slab. The deeper problem is
## that a filled rectangle under a name is a STICKER: it sits on the card instead
## of belonging to it, and it punched an opaque block through the badge page's
## frosted pane, which is the one surface in the app whose whole identity is that
## you can see through it.
##
## So a plate is now built from the app's own glass box — same lit rim, same
## thicker top edge catching light from above — retinted per style and set to a
## PILL radius, which is the shape the rest of the app gives to something that
## holds a single line of text.
static func _plate_layers(index: int, accent: Color) -> Array:
	var id := String(PLATE_IDS[index])
	var out: Array = []
	## How much of the surface a plate keeps. Low enough that the frost, the
	## shard field and the alcove all read through it.
	const A := 0.34
	var tint := Color(0, 0, 0, 0)
	var rim := Color(1, 1, 1, 0.28)
	match id:
		"foil":
			# Brushed metal: cool and pale, with the brightest lip of the four.
			tint = Color(Color("C7D4E6"), A)
			rim = Color(1, 1, 1, 0.72)
		"carbon":
			# The quiet one, for players whose badge is already loud (Infinity, the
			# Prism frame): almost nothing but a rim.
			tint = Color(Color("10131A"), A + 0.20)
			rim = Color(1, 1, 1, 0.30)
		"aurora":
			tint = Color(accent.lerp(Color("6B4FD8"), 0.35), A)
			rim = Color(accent.lerp(Color.WHITE, 0.55), 0.80)
		"ember":
			tint = Color(Color("E0662B"), A)
			rim = Color(Color("FFD9A0"), 0.78)
		_:
			return out

	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UI.glass_box(1, DesignSystem.RADIUS_PILL)
	sb.bg_color = tint
	sb.border_color = rim
	# Content margins live on the MarginContainer that wraps the label, not here:
	# this box is a backdrop behind it, and margins on both would double up.
	sb.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", sb)
	out.append(panel)
	return out

## The ink a name must be printed in to survive its plate.
##
## Now that the plates are TRANSLUCENT, the answer is the theme's own text colour
## for all of them — and that is a consequence, not a shortcut. A plate at 42%
## barely shifts the surface under the name, so the ink the page already uses on
## that surface is the ink that works; the hard-coded near-black that Foil needed
## when it was an opaque sheet of metal would now be near-black on a dark theme,
## which is the exact disappearing-name failure this function exists to prevent.
##
## Kept as a function rather than deleted at the call sites: it is the ONE place
## the question is answered, so a future opaque plate has somewhere to say so.
static func plate_ink(index: int, fallback: Color) -> Color:
	return fallback

# =============================================================================
# TITLES
# =============================================================================

## What the player is CALLED, under their name. Earned in play, never sold.
##
## `need` is the rule, in one of three forms:
##   ""            always available (the empty title)
##   "ach:<id>"    that achievement is unlocked
##   "tier:<n>"    that mastery tier index is reached
##
## Encoded as a string rather than as a Callable so the whole catalogue stays a
## constant a test can walk — `test_badge_cosmetics.gd` checks every `need` here
## names something that actually exists, which is the failure this shape exists
## to make loud: a title gated on a typo is a title nobody can ever wear, and it
## looks completely fine in the picker.
const TITLES := [
	{"id": "", "text": "No title", "need": ""},
	{"id": "climber", "text": "Climber", "need": "tier:0"},
	{"id": "starsmith", "text": "Star Smith", "need": "ach:tower_star"},
	{"id": "perfectionist", "text": "Perfectionist", "need": "ach:perfect_run"},
	{"id": "architect", "text": "Mountain Mover", "need": "ach:grand_8192"},
	{"id": "voidwalker", "text": "Void Walker", "need": "ach:antimatter_2048"},
	{"id": "cartographer", "text": "Cartographer", "need": "ach:constellation_3"},
	{"id": "devoted", "text": "Devoted", "need": "ach:streak_30"},
	{"id": "limitless", "text": "Limitless", "need": "tier:6"},
]

## The title definition for `id`, or an empty dictionary.
static func title_def(id: String) -> Dictionary:
	for t: Dictionary in TITLES:
		if String(t["id"]) == id:
			return t
	return {}

## Whether the player has earned title `t`. An unparseable rule reads as NOT
## earned: a title nobody can wear is a bug worth seeing, a title everybody wears
## by accident is a bug nobody reports.
static func title_earned(t: Dictionary) -> bool:
	var need := String(t.get("need", ""))
	if need.is_empty():
		return true
	var parts := need.split(":")
	if parts.size() != 2:
		return false
	match String(parts[0]):
		"ach":
			return Achievements.is_unlocked(String(parts[1]))
		"tier":
			var ratio: float = GameStats.best_mastery_ratio()["ratio"]
			return TierBadge.current_index(ratio) >= int(String(parts[1]))
	return false

## Every title the player may equip right now, in catalogue order.
static func earned_titles() -> Array:
	var out: Array = []
	for t: Dictionary in TITLES:
		if title_earned(t):
			out.append(t)
	return out

## The title the player has equipped AND earned, "" otherwise. A title lost to a
## wiped save (or to a catalogue edit) falls off the badge rather than staying
## printed under a name that can no longer claim it.
static func title_of(p: Dictionary) -> String:
	var id := String(p.get("title", ""))
	if id.is_empty():
		return ""
	var def := title_def(id)
	if def.is_empty() or not title_earned(def):
		return ""
	return String(def["text"])

# =============================================================================
# EMBLEM EFFECTS
# =============================================================================

## What the badge gives OFF — the slot above the frame. A frame is an object
## around the shield; an effect is the shield doing something.
const EFFECTS := ["None", "Embers", "Shards", "Pulse", "Sparks"]
const EFFECT_IDS := ["none", "embers", "shards", "pulse", "sparks"]

static func effect_cosmetic_id(i: int) -> String:
	if i < 0 or i >= EFFECT_IDS.size():
		return ""
	return "effect_" + String(EFFECT_IDS[i])

## The effect the player has equipped AND owns, 0 otherwise.
static func effect_of(p: Dictionary) -> int:
	var i := int(p.get("effect", 0))
	if i <= 0 or i >= EFFECTS.size():
		return 0
	return i if Wallet.owns_cosmetic(effect_cosmetic_id(i)) else 0

## Mounts effect `effect` on a `box`-sized badge stack.
##
## Every effect here is PURE MOTION, so reduce-motion drops all of them entirely
## rather than leaving a still frame of one: a paused ember is a dot parked
## beside a badge, which reads as a rendering fault rather than as a decoration.
## The frames degrade to a drawing because they ARE a drawing; these do not.
static func add_effect(parent: Control, box: float, effect: int, accent: Color) -> void:
	if effect <= 0 or effect >= EFFECT_IDS.size():
		return
	if bool(SettingsManager.get_value("reduce_motion")):
		return
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(layer)
	match String(EFFECT_IDS[effect]):
		"embers": _embers(layer, box, accent)
		"shards": _shards(layer, box)
		"pulse": _pulse(layer, box, accent)
		"sparks": _sparks(layer, box, accent)

## Warm motes lifting off the shield and going out, each on its own clock.
static func _embers(layer: Control, box: float, accent: Color) -> void:
	for i in 11:
		var sz := randf_range(box * 0.052, box * 0.105)
		var dot := TierBadge._burst_dot(Color("FFB25E").lerp(accent, randf_range(0.0, 0.4)))
		dot.size = Vector2(sz, sz)
		layer.add_child(dot)
		_ember_cycle(dot, box, sz, true)

## One ember: appear low on the shield, rise, fade, then start again from a new
## spot. Re-armed from `finished` rather than looped, so each mote keeps its own
## randomised path instead of all seven repeating one baked arc forever.
static func _ember_cycle(dot: Control, box: float, sz: float, first: bool) -> void:
	if not is_instance_valid(dot):
		return
	var x := randf_range(box * 0.22, box * 0.78)
	dot.position = Vector2(x - sz * 0.5, box * randf_range(0.55, 0.80))
	dot.modulate.a = 0.0
	var rise := box * randf_range(0.45, 0.78)
	var dur := randf_range(1.0, 1.8)
	# A short first delay too: a decoration that takes two seconds to show its
	# first mote looks broken for two seconds.
	var delay := randf_range(0.0, 0.7) if first else randf_range(0.0, 0.35)
	var drift := randf_range(-box * 0.10, box * 0.10)
	var tw := dot.create_tween().set_parallel()
	tw.tween_property(dot, "position",
		dot.position + Vector2(drift, -rise), dur).set_delay(delay) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	var ta := dot.create_tween()
	ta.tween_interval(delay)
	ta.tween_property(dot, "modulate:a", randf_range(0.85, 1.0), dur * 0.30)
	ta.tween_property(dot, "modulate:a", 0.0, dur * 0.65)
	ta.finished.connect(func(): _ember_cycle(dot, box, sz, false))

## Theme tile shards drifting off the badge — the board own colours, so the
## effect belongs to whatever palette is loaded rather than to a fixed hue.
static func _shards(layer: Control, box: float) -> void:
	const RAMP := [2, 4, 8, 16, 32, 64, 128]
	for i in 8:
		var v: int = RAMP[i % RAMP.size()]
		var piece := TierBadge._shard(ThemeManager.tile_style(v)["bg"])
		var sz := randf_range(box * 0.075, box * 0.135)
		piece.size = Vector2(sz, sz)
		piece.pivot_offset = Vector2(sz, sz) * 0.5
		layer.add_child(piece)
		_shard_cycle(piece, box, sz, true)

static func _shard_cycle(piece: Control, box: float, sz: float, first: bool) -> void:
	if not is_instance_valid(piece):
		return
	var ang := randf() * TAU
	var from := Vector2(box, box) * 0.5 + Vector2(cos(ang), sin(ang)) * box * 0.30
	piece.position = from - Vector2(sz, sz) * 0.5
	piece.rotation = randf_range(-0.5, 0.5)
	piece.modulate.a = 0.0
	var dur := randf_range(1.4, 2.3)
	var delay := randf_range(0.0, 0.9) if first else randf_range(0.0, 0.5)
	var tw := piece.create_tween().set_parallel()
	tw.tween_property(piece, "position",
		piece.position + Vector2(cos(ang), sin(ang)) * box * 0.32, dur).set_delay(delay)
	tw.tween_property(piece, "rotation",
		piece.rotation + randf_range(-1.2, 1.2), dur).set_delay(delay)
	var ta := piece.create_tween()
	ta.tween_interval(delay)
	ta.tween_property(piece, "modulate:a", randf_range(0.75, 1.0), dur * 0.35)
	ta.tween_property(piece, "modulate:a", 0.0, dur * 0.6)
	ta.finished.connect(func(): _shard_cycle(piece, box, sz, false))

## Rings leaving the badge like a struck bell — two of them, half a beat apart,
## so the pulse reads as continuous without either ring being on screen for long.
static func _pulse(layer: Control, box: float, accent: Color) -> void:
	for i in 3:
		var ring := ProgressRing.new()
		ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ring.thickness = maxf(3.0, box * 0.030)
		ring.track_color = Color(0, 0, 0, 0)
		ring.color_a = accent
		ring.color_b = accent.lerp(Color.WHITE, 0.5)
		ring.value = 1.0
		ring.pivot_offset = Vector2(box, box) * 0.5
		ring.scale = Vector2(0.62, 0.62)
		ring.modulate.a = 0.0
		layer.add_child(ring)
		var offset := float(i) * 0.62
		ring.tree_entered.connect(func():
			var tw := ring.create_tween().set_loops()
			tw.tween_interval(offset)
			tw.set_parallel(true)
			tw.tween_property(ring, "scale", Vector2(1.34, 1.34), 1.5) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tw.tween_property(ring, "modulate:a", 0.95, 0.28)
			tw.chain().tween_property(ring, "modulate:a", 0.0, 1.0)
			tw.chain().tween_interval(1.86 - offset)
			tw.chain().tween_callback(func():
				ring.scale = Vector2(0.62, 0.62)))

## Quick bright flecks — the fastest of the four, and the only one that reads at
## a glance on a small badge (the Home capsule, the trophy rail).
static func _sparks(layer: Control, box: float, accent: Color) -> void:
	for i in 14:
		var sz := randf_range(box * 0.040, box * 0.078)
		var dot := TierBadge._burst_dot(Color.WHITE.lerp(accent, randf_range(0.0, 0.5)))
		dot.size = Vector2(sz, sz)
		layer.add_child(dot)
		_spark_cycle(dot, box, sz, float(i) * 0.11)

static func _spark_cycle(dot: Control, box: float, sz: float, delay: float) -> void:
	if not is_instance_valid(dot):
		return
	var ang := randf() * TAU
	var d := Vector2(cos(ang), sin(ang))
	var from := Vector2(box, box) * 0.5 + d * box * randf_range(0.24, 0.40)
	dot.position = from - Vector2(sz, sz) * 0.5
	dot.modulate.a = 0.0
	var tw := dot.create_tween()
	tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(dot, "position", dot.position + d * box * 0.24, 0.40) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(dot, "modulate:a", 1.0, 0.10)
	tw.chain().tween_property(dot, "modulate:a", 0.0, 0.26)
	tw.chain().tween_interval(randf_range(0.25, 0.9))
	tw.finished.connect(func(): _spark_cycle(dot, box, sz, 0.0))

## A STATIC picture of what an effect DOES, for a picker tile.
##
## The effects themselves are pure motion, which makes them the one slot a player
## cannot judge from a still: at any given instant half the particles are mid-fade
## and under reduce-motion there is nothing on screen at all. So the picker draws
## a diagram instead of a sample — five options that are legible the moment the
## tab opens, on every device and in every screenshot — and the LIVE preview at
## the top of the sheet shows the real thing once one is chosen.
static func effect_swatch(box: float, effect: int, accent: Color) -> Control:
	var sw := EffectSwatch.new()
	sw.style = String(EFFECT_IDS[effect]) if effect >= 0 and effect < EFFECT_IDS.size() 		else "none"
	sw.accent = accent
	sw.custom_minimum_size = Vector2(box, box)
	return sw

## The diagram itself: one canvas item, drawn once on resize.
class EffectSwatch extends Control:
	var style := "none"
	var accent: Color = Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var box := minf(size.x, size.y)
		if box <= 8.0:
			return
		var c := size * 0.5
		match style:
			"embers": _embers_dia(c, box)
			"shards": _shards_dia(c, box)
			"pulse": _pulse_dia(c, box)
			"sparks": _sparks_dia(c, box)

	## Motes lifting off, drawn as a rising column that shrinks and cools.
	func _embers_dia(c: Vector2, box: float) -> void:
		for i in 7:
			var t := float(i) / 6.0
			var p := c + Vector2(sin(t * 5.0) * box * 0.18, box * (0.36 - t * 0.68))
			draw_circle(p, box * (0.060 - t * 0.032),
				Color(Color("FFB25E").lerp(accent, 0.35), 1.0 - t * 0.45))

	## Tile shards leaving the badge, in the board's own ramp.
	func _shards_dia(c: Vector2, box: float) -> void:
		const RAMP := [8, 32, 128]
		for i in 3:
			var a := -PI * 0.5 + TAU * float(i) / 3.0
			var at := c + Vector2(cos(a), sin(a)) * box * 0.26
			var h := box * 0.17
			draw_rect(Rect2(at - Vector2(h, h) * 0.5, Vector2(h, h)),
				Color(CandyFace.color(RAMP[i]), 1.0), true)

	## Rings leaving like a struck bell.
	func _pulse_dia(c: Vector2, box: float) -> void:
		for i in 3:
			var r := box * (0.14 + 0.14 * float(i))
			draw_arc(c, r, 0.0, TAU, 48,
				Color(accent, 1.0 - 0.24 * float(i)), maxf(3.0, box * 0.034), true)

	## Quick flecks thrown outward.
	func _sparks_dia(c: Vector2, box: float) -> void:
		for i in 8:
			var a := TAU * float(i) / 8.0
			var d := Vector2(cos(a), sin(a))
			var lit := (i % 2) == 0
			draw_line(c + d * box * (0.13 if lit else 0.20),
				c + d * box * (0.38 if lit else 0.30),
				Color(Color.WHITE.lerp(accent, 0.4), 1.0 if lit else 0.7),
				maxf(3.0, box * 0.032), true)

# =============================================================================
# SHARED
# =============================================================================

## Every gem-priced cosmetic this file and TierBadge between them define, as
## `{id: display name}`. The ONE place the three catalogues are walked together —
## the identity sheet prices its pickers from it and the test checks it against
## EconomyRules.COSMETICS in both directions, so a decoration can neither ship
## unpriced nor be priced without existing.
static func priced_catalogue() -> Dictionary:
	var out: Dictionary = {}
	for i in TierBadge.FRAME_IDS.size():
		var id := TierBadge.frame_cosmetic_id(i)
		if EconomyRules.is_cosmetic(id):
			out[id] = String(TierBadge.FRAMES[i]) + " frame"
	for i in PLATE_IDS.size():
		var id := plate_cosmetic_id(i)
		if EconomyRules.is_cosmetic(id):
			out[id] = String(PLATES[i]) + " nameplate"
	for i in EFFECT_IDS.size():
		var id := effect_cosmetic_id(i)
		if EconomyRules.is_cosmetic(id):
			out[id] = String(EFFECTS[i]) + " effect"
	return out
