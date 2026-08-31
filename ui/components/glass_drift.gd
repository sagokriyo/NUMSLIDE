class_name GlassDrift
extends Control
## Home's glass-tile identity, distilled for secondary screens: a calm field of
## LARGE glass shards carrying X and O — painted with the board's own CandyFace material —
## drifting slowly up behind the content, under a legibility scrim so text always
## wins. No physics, no grabbing: pure atmosphere, so the layer stays cheap on
## the menus it decorates. Mount via AppScreen.add_glass_drift(); skipped
## entirely under reduce-motion (a still shard field reads as clutter, not calm).

const _VALUES := [2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048]

var _shards: Array = []   # [{n:Control, v:Vector2, ph:float, wr:float, amp:float}]
var _scrim: ColorRect
var _acc := 0.0           # banked delta — the drift steps at 30 Hz, not every frame

## CALM mode, for content-dense screens. Set before the node enters the tree
## (AppScreen.add_glass_drift(true) does).
##
## The default mix is tuned for Home: sparse content, so big NEAR shards at full
## vividness read as atmosphere. On a dense screen — the Shop is six sections of
## rows, chips and prices — the same shard parks a bright 196pt block on top of a
## number, and a price you cannot read is not atmosphere. Calm keeps the identity
## (same material, same motion, same field) and drops the near band entirely:
## every shard is small and hazed toward the backdrop, under a heavier scrim.
var calm := false

## An optional wash pulled through the whole field — the Badge page sets it to
## the player's rank metal, so the air behind a Diamond profile is cold and the
## air behind an Infinity one is violet.
##
## Applied to the shard COLOUR rather than as a scrim over the layer: a coloured
## sheet would tint the text drawn on top of it too, and the whole reason this
## layer can be this visible is that content always wins. Alpha 0 = off, which is
## every screen but one.
var rank_tint: Color = Color(0, 0, 0, 0)

## One shard's face, painted with the board's own glass material (the exact
## painter TileView uses on the grid) — rim, wet top band, diagonal streak.
class ShardFace extends Control:
	var vivid: Color = Color.WHITE
	var number: int = 1
	func _draw() -> void:
		var hw := minf(size.x, size.y) * 0.5
		CandyFace.draw_face_soft(self, size * 0.5, hw, vivid, true)
		# The piece of this game: a number on the tile, in the tile's own hue.
		TileFace.draw_number(self, size * 0.5, hw, number, vivid.lightened(0.35), 1.0, 0.0)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spawn.call_deferred()
	# The haze tint and scrim are mixed from the theme's own backdrop, so a theme
	# switch re-deals the whole field in the new palette's air.
	ThemeManager.theme_changed.connect(func(_p):
		_clear()
		_spawn())

func _clear() -> void:
	for e in _shards:
		var n: Control = (e as Dictionary)["n"]
		if is_instance_valid(n):
			n.queue_free()
	_shards.clear()
	if is_instance_valid(_scrim):
		_scrim.queue_free()
	_scrim = null

func _spawn() -> void:
	if bool(SettingsManager.get_value("reduce_motion")) or not is_inside_tree():
		return
	var vp := UI.canvas_size(self)
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	# Fewer live shards on phones — same rationale as Home's field: animated
	# Controls are a steady per-frame tax on a mobile GPU/CPU.
	var count := 7 if OS.has_feature("mobile") else 11
	if calm:
		# Fewer, as well as smaller: the calm field is meant to be noticed only
		# once, on the way to reading something else.
		#
		# DENSER than it was (4/6). At four shards on a phone the field was not
		# so much calm as absent — a screen's worth of backdrop with two or three
		# tiles adrift in it reads as a rendering glitch rather than as
		# atmosphere. The band is unchanged, so nothing got louder; there is
		# simply enough of it now to register as a field.
		count = 6 if OS.has_feature("mobile") else 9
	for i in count:
		# Two depth bands. FAR shards are smaller and hazed toward the backdrop —
		# atmosphere that can never fight the content. NEAR shards are the big
		# statement pieces (larger than Home's, per this layer's whole point:
		# these screens wanted the tiles bigger and unmistakable).
		var far: bool = calm or ((i % 5) < 3)
		# The far band spans a WIDER range than it did (was 60-104), so a calm
		# field grades through several depths instead of arriving as one size of
		# shard repeated. `depth` below is normalised across whichever band the
		# shard landed in, so the haze still runs the full distance either way.
		# The ceiling stays clear of the near band's 120 floor — the two must not
		# overlap, or "calm" stops being a size guarantee (test_menu_ambience
		# mirrors this ceiling and pins exactly that).
		var sz: float = randf_range(52.0, 112.0) if far else randf_range(120.0, 196.0)
		var depth: float = clampf(inverse_lerp(52.0, 112.0, sz) if far \
			else inverse_lerp(120.0, 196.0, sz), 0.0, 1.0)
		var value := int(_VALUES[(i * 2) % _VALUES.size()])
		# Each shard IS the game tile for its value: the board's own per-value
		# colour (CandyFace.color), not a generic accent pair — a drifting "512"
		# must be unmistakably the 512 tile from gameplay. Depth is carried by
		# COLOUR, not opacity (modulate would dissolve the glass material's
		# internal overlay contrast — see Home's _spawn_toys note): near shards
		# stay at the board's full vividness, only the far band hazes toward the
		# backdrop for atmosphere.
		var haze: float = lerpf(0.55, 0.38, depth) if far else 0.0
		var vivid := _depth_tint(CandyFace.color(value), haze)
		var alpha: float = lerpf(0.75, 0.88, depth) if far else 1.0
		if calm:
			# Ghosted as well as small. On a dense page a shard at far-band SIZE is
			# still a shard at far-band OPACITY, and it will sooner or later drift
			# across a price. At this alpha it reads as depth in the backdrop and
			# never competes with a numeral drawn on top of it.
			alpha *= 0.42
		var node := _make_shard(sz, value, vivid, alpha)
		node.position = Vector2(randf_range(0.0, maxf(0.0, vp.x - sz)),
			randf_range(0.0, maxf(0.0, vp.y - sz)))
		add_child(node)
		var drift := Vector2(randf_range(-6.0, 6.0), -lerpf(10.0, 18.0, depth)) if far \
			else Vector2(randf_range(-9.0, 9.0), -lerpf(18.0, 32.0, depth))
		_shards.append({"n": node, "v": drift, "ph": randf() * TAU,
			"wr": randf_range(0.4, 0.8), "amp": deg_to_rad(randf_range(2.0, 5.0))})

	# Legibility scrim — one soft wash of the theme's own backdrop over the whole
	# field, so every label keeps its contrast no matter which shard drifts
	# beneath it. Text simply always wins.
	_scrim = ColorRect.new()
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The SAME 0.34 wash as Home's field, so the shards read at the same
	# visibility on every screen that carries them — one identity, one air. The
	# frosted cards already re-frost whatever drifts beneath them, which is what
	# keeps a full-vivid shard from fighting a card's own text.
	var c: Color = ThemeManager.color("bg0")
	c.a = 0.46 if calm else 0.34
	_scrim.color = c
	add_child(_scrim)

## Aerial perspective: a shard recedes by hazing toward the backdrop it sits in.
## The saturation lift first is CandyFace.color's own expectation — the painter
## builds rim/streak/body out from a vivid input.
func _depth_tint(c: Color, haze: float) -> Color:
	var vivid := Color.from_hsv(c.h, clampf(c.s * 1.32, 0.0, 1.0), clampf(c.v * 1.08, 0.0, 1.0))
	if rank_tint.a > 0.0:
		# A QUARTER of the way at most: a shard has to stay recognisably its own
		# tile's colour, or the field stops being the board's tiles and becomes an
		# abstract wash that happens to be tile-shaped.
		vivid = vivid.lerp(Color(rank_tint.r, rank_tint.g, rank_tint.b),
			0.25 * rank_tint.a)
	return vivid.lerp(ThemeManager.color("bg0"), clampf(haze, 0.0, 1.0))

func _make_shard(sz: float, value: int, vivid: Color, alpha: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(sz, sz)
	holder.size = Vector2(sz, sz)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.pivot_offset = Vector2(sz, sz) * 0.5
	var face := ShardFace.new()
	face.vivid = vivid
	face.size = Vector2(sz, sz)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The ramp index picks the tile's hue; the NUMBER on it is that rung's place
	# in the ramp, so the field reads as tiles that fell off a board rather than
	# as a set of unrelated digits.
	face.number = maxi(1, _VALUES.find(value) + 1)
	holder.add_child(face)
	holder.modulate = Color(1, 1, 1, alpha)
	return holder

func _process(delta: float) -> void:
	if _shards.is_empty() or delta <= 0.0:
		return
	# Ambient drift needs no 120 Hz precision: bank the delta and step at 30 Hz —
	# the same distance covered (~1 px per step at these speeds), at a quarter of
	# the transform-dirtying cost. Same at-rest cadence as Home's toy field and
	# ThemePreview; this was the one per-frame loop that never got the treatment.
	_acc += delta
	if _acc < 1.0 / 30.0:
		return
	var step := _acc
	_acc = 0.0
	var vp := UI.canvas_size(self)
	for e in _shards:
		var s: Dictionary = e
		var n: Control = s["n"]
		if not is_instance_valid(n):
			continue
		n.position += (s["v"] as Vector2) * step
		# Idle tumble — a slow sinusoidal sway around upright.
		s["ph"] = float(s["ph"]) + step * float(s["wr"])
		n.rotation = sin(float(s["ph"])) * float(s["amp"])
		# Wrap around every edge, never trapped — with a margin of its own size
		# so a shard fully leaves before re-entering from the far side.
		var sz := n.size.x
		if n.position.y < -sz:
			n.position.y = vp.y
			n.position.x = randf_range(0.0, maxf(0.0, vp.x - sz))
		elif n.position.y > vp.y + sz:
			n.position.y = -sz
		if n.position.x < -sz:
			n.position.x = vp.x
		elif n.position.x > vp.x + sz:
			n.position.x = -sz
