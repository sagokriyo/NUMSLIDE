class_name TierBadge
extends RefCounted
## TierBadge — the "tile mastery" rank ladder rendered with the painted shield
## art (assets/images/badges/*). One source of truth for the seven tiers, the
## progression rule, and the badge view.
##
## Used by the profile medallion rail, the profile rank emblem, and the home
## profile icon, so a player's emblem everywhere tracks the same progression.
##
## Progress is difficulty-normalized: each tier is a MULTIPLE of whichever
## mode's own win target the player is closest to (or past). Reaching a mode's
## own win target always means ratio 1.0 ("Gold" — you won THAT mode), whether
## it's Classic's 2048 or Grand's 8192 — no mode can shortcut another's
## ladder just because its board makes bigger numbers. See
## GameStats.best_mastery_ratio(). For Classic specifically (win target 2048)
## these ratios reduce to exactly today's absolute thresholds (512/1024/…/32768),
## so nothing changes for a player whose best mode is Classic.
const TIERS := [
	{"name": "Bronze",   "tex": "res://assets/images/badges/bronze.png",   "ratio": 0.25, "accent": Color("D2925E")},
	{"name": "Silver",   "tex": "res://assets/images/badges/silver.png",   "ratio": 0.5,  "accent": Color("C2CAD6")},
	{"name": "Gold",     "tex": "res://assets/images/badges/gold.png",     "ratio": 1.0,  "accent": Color("F4C13E")},
	{"name": "Platinum", "tex": "res://assets/images/badges/platinum.png", "ratio": 2.0,  "accent": Color("C2D6DF")},
	{"name": "Diamond",  "tex": "res://assets/images/badges/diamond.png",  "ratio": 4.0,  "accent": Color("6FD3EC")},
	{"name": "Master",   "tex": "res://assets/images/badges/master.png",   "ratio": 8.0,  "accent": Color("E0B84B")},
	{"name": "Infinity", "tex": "res://assets/images/badges/infinity.png", "ratio": 16.0, "accent": Color("9A7BF5")},
]

## What each rank is made OF, beyond its shield art: the light it gives off and
## the way it celebrates. One row per TIERS entry, same order.
##
## The ladder used to be seven pictures wearing one glow and one burst, so the
## only thing that changed between Bronze and Infinity was the PNG. A metal is
## the rest of the difference — Bronze smoulders, Diamond splits light, Infinity
## drifts — and it is read by the hero aura, the tap celebration and the page's
## own shard field, so a rank looks like itself everywhere at once.
##
## `aura`/`aura2` are the two-stop glow (hot centre, deep floor). `burst` names a
## recipe in `_BURST_STYLES`. `air` is the tint the page ambience takes, kept
## nearer the shield's own accent than the aura is: it is a wash behind text, and
## the hot centre colour at that size is a stain.
const METALS := [
	{"aura": Color("FF9A4D"), "aura2": Color("C2451E"), "burst": "ember",  "air": Color("E08A46")},
	{"aura": Color("E4ECF6"), "aura2": Color("8FA4BE"), "burst": "spark",  "air": Color("C2CAD6")},
	{"aura": Color("FFD76A"), "aura2": Color("E09A1E"), "burst": "star",   "air": Color("F4C13E")},
	{"aura": Color("F0F7FF"), "aura2": Color("9FC0D6"), "burst": "shard",  "air": Color("C2D6DF")},
	{"aura": Color("A8ECFF"), "aura2": Color("4FA8D8"), "burst": "prism",  "air": Color("6FD3EC")},
	{"aura": Color("FFE08A"), "aura2": Color("B8791E"), "burst": "star",   "air": Color("E0B84B")},
	{"aura": Color("C4A6FF"), "aura2": Color("5B3FCF"), "burst": "nebula", "air": Color("9A7BF5")},
]

## The metal for tier `i`, clamped exactly the way `tier()` is. Unranked (-1)
## deliberately clamps to Bronze rather than returning an empty dictionary: an
## unranked player is shown the faded Bronze shield everywhere, so the light
## around it should be Bronze's too.
static func metal(i: int) -> Dictionary:
	return METALS[clampi(i, 0, METALS.size() - 1)]

static func count() -> int:
	return TIERS.size()

static func tier(i: int) -> Dictionary:
	return TIERS[clampi(i, 0, TIERS.size() - 1)]

static func tier_ratio(i: int) -> float:
	return float(tier(i)["ratio"])

## Index of the highest tier whose ratio the player's best mastery ratio has
## reached, or -1 when no tier is earned yet.
static func current_index(ratio: float) -> int:
	var idx := -1
	for i in TIERS.size():
		if ratio >= tier_ratio(i):
			idx = i
	return idx

## How many tiers are unlocked (for summary counts).
static func unlocked_count(ratio: float) -> int:
	return current_index(ratio) + 1

## The ratio that unlocks the next tier, or -1.0 when already at the top tier.
static func next_threshold_ratio(ratio: float) -> float:
	var idx := current_index(ratio)
	if idx + 1 >= TIERS.size():
		return -1.0
	return tier_ratio(idx + 1)

## Progress (0..1) from the current tier's ratio threshold toward the next one.
static func progress_to_next(ratio: float) -> float:
	var idx := current_index(ratio)
	if idx + 1 >= TIERS.size():
		return 1.0
	var lo := 0.0 if idx < 0 else tier_ratio(idx)
	var hi := tier_ratio(idx + 1)
	return clampf((ratio - lo) / (hi - lo), 0.0, 1.0)

## A sized badge image. `locked` keeps the badge's own colour (so Infinity stays
## purple) but fades it so earned tiers clearly stand out.
static func make_view(box: float, tier_index: int, locked: bool) -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = Vector2(box, box)
	rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture = load(String(tier(tier_index)["tex"])) as Texture2D
	if locked:
		rect.modulate = Color(1, 1, 1, 0.6)
	return rect

## A badge sitting on a soft accent glow — lifts it off the card and softens any
## faint edge so badges look clean on light themes too.
static func make_glowing(box: float, tier_index: int, locked: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(box, box)
	holder.add_child(accent_glow(box))
	var view := make_view(box, tier_index, locked)
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.custom_minimum_size = Vector2.ZERO
	holder.add_child(view)
	return holder

## The badge-aura palette a player can pick from in the identity sheet.
## Index -1 (or out of range) = the default: the theme / tier accent.
const AURAS := [
	Color("F4C13E"),  # gold
	Color("6FD3EC"),  # ice
	Color("9A7BF5"),  # violet
	Color("F178B6"),  # pink
	Color("57C77A"),  # green
	Color("F4713E"),  # ember
]

## The aura the player chose (profile section "avatar"), or `fallback`.
static func aura_color(avatar: int, fallback: Color) -> Color:
	if avatar < 0 or avatar >= AURAS.size():
		return fallback
	return AURAS[avatar]

## A soft radial accent glow sized to sit behind a `box`-sized badge. `tint`
## overrides the theme accent (the player's chosen aura); alpha 0 = default.
static func accent_glow(box: float, tint: Color = Color(0, 0, 0, 0)) -> TextureRect:
	var glow := TextureRect.new()
	var gt := GradientTexture2D.new()
	var grad := Gradient.new()
	var a: Color = ThemeManager.color("accent") if tint.a <= 0.0 else tint
	grad.set_color(0, Color(a.r, a.g, a.b, 0.40))
	grad.set_color(1, Color(a.r, a.g, a.b, 0.0))
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	glow.texture = gt
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := box * 0.12
	glow.offset_left = -pad; glow.offset_top = -pad
	glow.offset_right = pad; glow.offset_bottom = pad
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return glow

## A slow diagonal light glint sweeping across the badge art every few seconds,
## masked by the badge's own alpha so only the shield shines — polished metal,
## not a rectangle of light. Ascending smoothstep edges only: descending
## edges render black on D3D12.
static var _shine_shader: Shader

const _SHINE_CODE := "
shader_type canvas_item;
uniform float period = 4.6;
uniform float band = 0.14;
uniform float strength = 0.5;
void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	float pos = mix(-0.5, 1.5, fract(TIME / period));
	float d = (UV.x + UV.y) * 0.5;
	float glint = (1.0 - smoothstep(0.0, band, abs(d - pos))) * strength;
	COLOR = base + vec4(vec3(glint * base.a), 0.0);
}"

static func shine_material(period: float = 4.6) -> ShaderMaterial:
	if _shine_shader == null:
		_shine_shader = Shader.new()
		_shine_shader.code = _SHINE_CODE
	var mat := ShaderMaterial.new()
	mat.shader = _shine_shader
	mat.set_shader_parameter("period", period)
	return mat

## A one-shot celebration burst centred on a `box`-sized badge: tile shards —
## little rounded squares wearing the ACTIVE theme's own tile ramp colours —
## fly outward spinning, with a few soft light dots between them, fade, and
## free themselves.
## One burst recipe per metal (see METALS). "star" is the shipped celebration and
## every default still lands on it, so nothing that already called this changes.
##
##  shard_every  every Nth piece is a soft light dot, the rest are tile shards;
##               0 means NO shards — the prism and nebula bursts are pure light.
##  spread       throw distance as a fraction of the badge box.
##  dur          how long a piece lives.
##  grav         downward drift added after the throw (negative rises).
##  hue          the dot colour; alpha 0 means "use the caller's tint".
##  spin         shard tumble, in radians.
##  size         piece scale.
##  rainbow      each dot takes its own hue around the wheel (Diamond only).
const _BURST_STYLES := {
	"ember":  {"shard_every": 4, "spread": 0.62, "dur": 0.75, "grav": 0.55,
		"hue": Color("FFB25E"), "spin": 1.4, "size": 1.00, "rainbow": false},
	"spark":  {"shard_every": 5, "spread": 0.95, "dur": 0.45, "grav": 0.0,
		"hue": Color("EAF2FF"), "spin": 2.6, "size": 0.75, "rainbow": false},
	"star":   {"shard_every": 3, "spread": 0.70, "dur": 0.60, "grav": 0.0,
		"hue": Color(0, 0, 0, 0), "spin": 2.4, "size": 1.00, "rainbow": false},
	"shard":  {"shard_every": 2, "spread": 0.78, "dur": 0.65, "grav": 0.18,
		"hue": Color(0, 0, 0, 0), "spin": 2.0, "size": 1.15, "rainbow": false},
	"prism":  {"shard_every": 0, "spread": 0.88, "dur": 0.70, "grav": 0.0,
		"hue": Color(0, 0, 0, 0), "spin": 0.0, "size": 1.05, "rainbow": true},
	"nebula": {"shard_every": 0, "spread": 0.55, "dur": 1.15, "grav": -0.20,
		"hue": Color("C4A6FF"), "spin": 0.0, "size": 1.60, "rainbow": false},
}

## The burst recipe named `style`, falling back to the shipped "star" for an
## unknown one — a celebration must never be the thing that throws.
static func burst_style(style: String) -> Dictionary:
	return _BURST_STYLES.get(style, _BURST_STYLES["star"])

static func sparkle_burst(parent: Control, box: float, tint: Color, dots: int = 12,
		style: String = "star") -> void:
	const RAMP := [2, 4, 8, 16, 32, 64, 128, 256]
	var rec := burst_style(style)
	var shard_every: int = int(rec["shard_every"])
	var spread: float = float(rec["spread"])
	var dur: float = float(rec["dur"])
	var grav: float = float(rec["grav"])
	var spin: float = float(rec["spin"])
	var scale_f: float = float(rec["size"])
	var rainbow: bool = bool(rec["rainbow"])
	var hue: Color = rec["hue"]
	for i in dots:
		# `shard_every` 0 means light only; otherwise every Nth piece is the dot.
		var is_shard := shard_every > 0 and (i % shard_every != 0)
		var piece: Control
		var sz: float
		if is_shard:
			var v: int = RAMP[randi() % RAMP.size()]
			var col: Color = ThemeManager.tile_style(v)["bg"]
			piece = _shard(col)
			sz = randf_range(10.0, 20.0) * scale_f
		else:
			var base: Color = tint if hue.a <= 0.0 else hue
			if rainbow:
				# Diamond splits the light: each dot takes its own place on the
				# wheel, kept pale so the badge still reads as the subject.
				base = Color.from_hsv(fmod(float(i) / float(maxi(dots, 1)) + tint.h, 1.0),
					0.42, 1.0)
			piece = _burst_dot(Color.WHITE.lerp(base, randf_range(0.2, 0.7)))
			sz = randf_range(8.0, 16.0) * scale_f
		piece.position = Vector2(box, box) * 0.5 - Vector2(sz, sz) * 0.5
		piece.size = Vector2(sz, sz)
		piece.pivot_offset = Vector2(sz, sz) * 0.5
		parent.add_child(piece)
		var ang := TAU * (float(i) + randf() * 0.8) / float(dots)
		# The shipped throw range, scaled by the recipe — at "star" (spread 0.70)
		# this is exactly the 0.45–0.80 the celebration has always used.
		var reach := randf_range(0.45, 0.80) * (spread / 0.70)
		var dest := piece.position + Vector2(cos(ang), sin(ang)) * box * reach
		dest.y += box * grav * randf_range(0.5, 1.0)
		var tw := piece.create_tween().set_parallel()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(piece, "position", dest, dur)
		if is_shard and spin > 0.0:
			tw.tween_property(piece, "rotation", randf_range(-spin, spin), dur)
		tw.tween_property(piece, "modulate:a", 0.0, dur * 0.83).set_delay(dur * 0.17)
		tw.chain().tween_callback(piece.queue_free)

## A tiny rounded tile shard in one of the theme's own tile colours.
##
## The StyleBox is CACHED per colour. A burst builds eight shards, and the tile
## ramp only ever offers eight colours, so the uncached form allocated a fresh
## StyleBoxFlat for a colour it had already built moments earlier — every tap,
## for as long as the player kept tapping. StyleBoxes are immutable once built
## here (nothing mutates one after `_shard` returns), so sharing is safe.
static var _shard_boxes: Dictionary = {}

static func _shard(col: Color) -> Panel:
	var sb: StyleBoxFlat = _shard_boxes.get(col)
	if sb == null:
		# The key is the colour itself, so a theme switch simply starts filling
		# fresh entries. Bounded rather than cleared on theme_changed: this is a
		# static with no signal of its own, and 64 small StyleBoxes is nothing.
		if _shard_boxes.size() > 64:
			_shard_boxes.clear()
		sb = StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(4)
		sb.set_border_width_all(1)
		sb.border_color = Color(1, 1, 1, 0.35)
		sb.anti_aliasing = true
		_shard_boxes[col] = sb
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## The soft light dot between the shards. ONE white radial, baked once and shared
## by every dot ever; the colour arrives through `modulate`.
##
## This used to build a Gradient AND a GradientTexture2D per dot — four fresh 32×32
## textures per burst, each of which is a texture creation and upload on the render
## thread. That is a per-tap hitch, and repeat taps (the thing the badge invites)
## paid it again every time. A white gradient modulated by `col` composites to
## exactly what the per-dot gradient produced, so the look is unchanged.
static var _dot_tex: GradientTexture2D

static func _burst_dot(col: Color) -> TextureRect:
	if _dot_tex == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 0.95))
		grad.set_color(1, Color(1, 1, 1, 0.0))
		_dot_tex = GradientTexture2D.new()
		_dot_tex.gradient = grad
		_dot_tex.fill = GradientTexture2D.FILL_RADIAL
		_dot_tex.fill_from = Vector2(0.5, 0.5)
		_dot_tex.fill_to = Vector2(1.0, 0.5)
		_dot_tex.width = 32
		_dot_tex.height = 32
	var dot := TextureRect.new()
	dot.texture = _dot_tex
	dot.modulate = col
	dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dot.stretch_mode = TextureRect.STRETCH_SCALE
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dot

## NO runtime laurel. There used to be a `laurel()` here that drew two arcs of
## gold leaves flanking the badge, and every screen that showed a badge layered it
## on top. Every badge in assets/images/badges ALREADY carries its own wreath, in
## its own metal (see tools/slice_badges.ps1, which exists to keep those wings
## through the slice) — so the drawn one was a second, always-gold garland over
## art that had one. It crossed the Badge page's halo ring, and over Infinity's
## violet-and-cyan wings it read as a rendering fault rather than as a decoration.
## If a badge should be dressed differently, dress the ART; do not stack a second
## wreath on it.

## Equipable decorative frames around the badge (profile identity sheet).
## Runtime-drawn in the app's own effect language, so they restyle with the
## theme instead of shipping as fixed art.
const FRAMES := ["None", "Halo", "Orbit", "Laurel", "Flames", "Circuit",
	"Wings", "Prism", "Constellation"]

## The stable id behind each frame index, in the SAME order as FRAMES.
##
## The save stores the INDEX (profile.frame), because that is what shipped and
## rewriting it would un-equip every badge in the wild. Ownership needs a NAME,
## though — a price table keyed by position is one insertion away from selling
## the wrong thing — so this is the bridge, and appending is the only legal edit
## to either array. test_badge_cosmetics.gd fails the moment the two differ in
## length or a shipped id moves.
const FRAME_IDS := ["none", "halo", "orbit", "laurel", "flames", "circuit",
	"wings", "prism", "constellation"]

## The three frames that shipped free, and stay free. Charging for one now would
## take a decoration off a badge that already wears it — see EconomyRules.COSMETICS,
## which prices exactly the complement of this set.
const FREE_FRAMES := ["none", "halo", "orbit"]

## The cosmetic id that owns frame index `i` ("" when the index is out of range).
## Wallet.owns_cosmetic hands back true for the free three because they carry no
## price, so callers never need to special-case them.
static func frame_cosmetic_id(i: int) -> String:
	if i < 0 or i >= FRAME_IDS.size():
		return ""
	return "frame_" + String(FRAME_IDS[i])

## The frame index in profile section `p` that the player may actually WEAR:
## 0 when the saved one is out of range or is a decoration they do not own.
##
## THE one reader, and every badge in the app goes through it — the hero, Home's
## capsule, the Profile portrait, the leaderboard row, the share card. It landed
## because two of those started checking ownership and three did not, which is a
## worse state than either: the same badge would wear its frame on Home and lose
## it on the page you tap through to, and nothing anywhere would say why.
##
## The check matters even though the identity sheet only lets a player equip what
## they own. An old save, a hand-edited file, or a decoration moving between the
## free and priced sets all arrive here, and "render it anyway" is how a paid item
## quietly becomes free.
static func equipped_frame(p: Dictionary) -> int:
	var i := int(p.get("frame", 0))
	if i <= 0 or i >= FRAMES.size():
		return 0
	return i if Wallet.owns_cosmetic(frame_cosmetic_id(i)) else 0

## Adds frame `frame` around a `box`-sized badge stack. 0 = none.
##
##   1 "Halo"          a thin bright ring just outside the badge, breathing.
##   2 "Orbit"         three small lights slowly circling it.
##   3 "Laurel"        two rising arcs of leaves, in the badge own colour.
##   4 "Flames"        tongues licking the rim, flickering.
##   5 "Circuit"       an octagonal trace with a pulse running its ring.
##   6 "Wings"         four swept feathers off each flank.
##   7 "Prism"         six facets refracting round the shield, turning slowly.
##   8 "Constellation" nine linked stars, twinkling.
##
## Everything past Orbit is drawn by `FrameArt` — runtime geometry in the theme
## own colours rather than shipped art, so a frame restyles with the palette and
## costs no texture memory.
##
## ALL frame motion is gated on reduce-motion, the halo and orbit included. Those
## two predate the rule and were the last ambient loops in the app still running
## with it on — and a perpetually breathing ring is exactly what the setting
## exists to stop.
static func add_frame(parent: Control, box: float, frame: int, accent: Color) -> void:
	var still := bool(SettingsManager.get_value("reduce_motion"))
	if frame == 1:
		var ring := ProgressRing.new()
		ring.set_anchors_preset(Control.PRESET_FULL_RECT)
		var pad := box * 0.02
		ring.offset_left = -pad; ring.offset_top = -pad
		ring.offset_right = pad; ring.offset_bottom = pad
		ring.thickness = maxf(3.0, box * 0.028)
		ring.track_color = Color(0, 0, 0, 0)
		ring.color_a = Color(1, 1, 1, 0.9)
		ring.color_b = accent
		ring.value = 1.0
		parent.add_child(ring)
		if not still:
			ring.tree_entered.connect(func():
				var tw := ring.create_tween().set_loops()
				tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
				tw.tween_property(ring, "modulate:a", 0.55, 1.4)
				tw.tween_property(ring, "modulate:a", 1.0, 1.4))
	elif frame == 2:
		var orbit := Control.new()
		orbit.set_anchors_preset(Control.PRESET_FULL_RECT)
		orbit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		orbit.pivot_offset = Vector2(box, box) * 0.5
		parent.add_child(orbit)
		for i in 3:
			var dot := _burst_dot(Color.WHITE.lerp(accent, 0.4))
			var sz := box * 0.10
			var ang := TAU * float(i) / 3.0
			dot.size = Vector2(sz, sz)
			dot.position = Vector2(box, box) * 0.5 \
				+ Vector2(cos(ang), sin(ang)) * box * 0.52 - Vector2(sz, sz) * 0.5
			orbit.add_child(dot)
		if not still:
			orbit.tree_entered.connect(func():
				var tw := orbit.create_tween().set_loops()
				tw.tween_property(orbit, "rotation", TAU, 9.0).from(0.0))
	elif frame >= 3 and frame < FRAME_IDS.size():
		_add_art_frame(parent, box, String(FRAME_IDS[frame]), accent, still)

## How far outside the badge box a drawn ornament may reach, as a fraction of
## the box. The art layer is inflated by this on every side, so the box FrameArt
## measures against is `box * (1 + 2 * FRAME_PAD)` and nothing it draws may sit
## more than half of that from the centre.
const FRAME_PAD := 0.22

## Frames that FLICKER rather than move: two static layers cross-fading, because
## per-element alpha would mean one node — and one draw call — per tongue or star.
const _TWO_LAYER_FRAMES := ["flames", "constellation"]

## Mounts a drawn ornament. The art is padded OUTSIDE the badge box — a frame
## that fitted inside it would be a ring ON the shield rather than around it —
## via `set_anchors_and_offsets_preset`: a bare `set_anchors_preset` keeps the
## node current 0x0 rect behind compensating offsets, and the layer is canvas-
## culled seconds later with nothing on screen to explain why.
static func _add_art_frame(parent: Control, box: float, id: String, accent: Color,
		still: bool) -> void:
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.pivot_offset = Vector2(box, box) * 0.5
	parent.add_child(holder)

	var two := _TWO_LAYER_FRAMES.has(id)
	var layers := 2 if two else 1
	for i in layers:
		var art := FrameArt.new(id, accent, i)
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# 22%: enough annulus outside the shield for an ornament to be its own
		# object, and still inside the 300pt hero badge's own footprint on the
		# card. Every radius in FrameArt is a fraction of THIS padded box, not of
		# the badge — get that wrong and the ornament is clipped by its own node.
		var pad := box * FRAME_PAD
		art.offset_left = -pad; art.offset_top = -pad
		art.offset_right = pad; art.offset_bottom = pad
		holder.add_child(art)
		if not two:
			continue
		art.modulate.a = 1.0 if i == 0 else 0.0
		if still:
			# Still means still: layer 0 stays lit, layer 1 stays dark, and the
			# ornament is simply a drawing.
			continue
		var up := i == 1
		art.tree_entered.connect(func():
			var tw := art.create_tween().set_loops()
			tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			tw.tween_property(art, "modulate:a", 0.0 if up else 1.0, 0.9)
			tw.tween_property(art, "modulate:a", 1.0 if up else 0.0, 0.9))

	if still:
		return
	if id == "prism":
		# The facets turn; the badge under them does not.
		holder.tree_entered.connect(func():
			var tw := holder.create_tween().set_loops()
			tw.tween_property(holder, "rotation", TAU, 26.0).from(0.0))
	elif id == "circuit":
		holder.add_child(_circuit_pulse(box, accent))
	elif id == "wings" or id == "laurel":
		# A slow breath rather than a movement — these two read as solid objects
		# attached to the badge, and anything that slid would detach them.
		holder.tree_entered.connect(func():
			var tw := holder.create_tween().set_loops()
			tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			tw.tween_property(holder, "modulate:a", 0.72, 2.3)
			tw.tween_property(holder, "modulate:a", 1.0, 2.3))

## The bright bead that runs the Circuit frame ring. ONE node walking the same
## eight corners the trace is drawn through, so the pulse cannot drift off its
## own wire.
static func _circuit_pulse(box: float, accent: Color) -> Control:
	var sz := box * 0.075
	var dot := _burst_dot(Color.WHITE.lerp(accent, 0.25))
	dot.size = Vector2(sz, sz)
	# The art layer is padded by FRAME_PAD of the box on every side, so its centre
	# sits at (0.5 + pad) of the badge box and its radius scales by the same
	# factor the trace was drawn with. Derived from the constant rather than
	# written out, or the bead walks off its own wire the next time the pad moves.
	var centre := Vector2(box, box) * (0.5 + FRAME_PAD)
	var r := box * 0.38 * (1.0 + 2.0 * FRAME_PAD)
	var pts: Array = []
	for i in 9:
		var a := TAU * float(i % 8) / 8.0 - PI * 0.5
		pts.append(centre + Vector2(cos(a), sin(a)) * r - Vector2(sz, sz) * 0.5)
	dot.position = pts[0]
	dot.tree_entered.connect(func():
		var tw := dot.create_tween().set_loops()
		for i in range(1, pts.size()):
			var to: Vector2 = pts[i]
			tw.tween_property(dot, "position", to, 0.42)
		tw.tween_interval(1.1))
	return dot

## The runtime-drawn ornaments — everything past the two frames that shipped
## first — in one canvas item per layer.
##
## Drawn ONCE (on resize) and animated only by transform / modulate tweens on the
## node. A frame is permanent furniture on a page the player scrolls, so nothing
## here may re-triangulate its polygons every frame the way a `_process`-driven
## `queue_redraw` would: on Android the currency is draw submissions, not
## triangles. For the same reason every polygon arrives already positioned in
## local space instead of behind a `draw_set_transform`, which would break canvas
## batching between each leaf.
class FrameArt extends Control:
	var style := ""
	var accent: Color = Color.WHITE
	## Which half of a two-layer ornament this is; see _TWO_LAYER_FRAMES.
	var phase := 0

	func _init(p_style: String, p_accent: Color, p_phase: int = 0) -> void:
		style = p_style
		accent = p_accent
		phase = p_phase
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var box := minf(size.x, size.y)
		if box <= 8.0:
			return   # laid out but not yet sized; the resize signal brings us back
		match style:
			"laurel": _laurel(box)
			"flames": _flames(box)
			"circuit": _circuit(box)
			"wings": _wings(box)
			"prism": _prism(box)
			"constellation": _constellation(box)

	# --- Laurel ---------------------------------------------------------------
	## Two arcs of leaves rising from the foot of the badge up each flank, closed
	## by a bud where they meet. In the badge OWN colour, never gold: the shipped
	## shield art already carries a wreath in its own metal, and stacking a second
	## gold one over it is the exact mistake the old `laurel()` was deleted for.
	func _laurel(box: float) -> void:
		var c := size * 0.5
		var r := box * 0.36
		for s in 2:
			var side := -1.0 if s == 0 else 1.0
			for i in 7:
				var t := float(i) / 6.0
				var a := PI * 0.5 + side * (0.10 + t * 0.52) * PI
				var at := c + Vector2(cos(a), sin(a)) * r
				var grow := 1.0 - t * 0.45          # leaves taper toward the tip
				var leaf := _lens(box * 0.075 * grow, box * 0.030 * grow)
				# Splayed out from the tangent, so the wreath opens as it climbs.
				var rot := a + side * 1.15
				var col := accent.lerp(Color.WHITE, 0.10 + t * 0.30)
				draw_colored_polygon(_placed(leaf, at, rot), Color(col, 0.80))
		draw_circle(c + Vector2(0, r * 1.02), box * 0.022,
			Color(accent.lerp(Color.WHITE, 0.5), 0.9))

	## One leaf: a lens (two mirrored arcs) as a convex polygon.
	static func _lens(w: float, h: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		const N := 7
		for i in range(N + 1):
			var x := lerpf(-w, w, float(i) / float(N))
			pts.append(Vector2(x, -h * sqrt(maxf(1.0 - (x / w) * (x / w), 0.0))))
		# The two endpoints are shared by both arcs — repeating them would hand
		# the triangulator a pair of zero-area slivers.
		for i in range(N - 1, 0, -1):
			var x := lerpf(-w, w, float(i) / float(N))
			pts.append(Vector2(x, h * sqrt(maxf(1.0 - (x / w) * (x / w), 0.0))))
		return pts

	## `pts` rotated by `rot` and moved to `at` — computed here rather than with
	## draw_set_transform, which would be a batch break per shape.
	static func _placed(pts: PackedVector2Array, at: Vector2, rot: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		out.resize(pts.size())
		var cs := cos(rot)
		var sn := sin(rot)
		for i in pts.size():
			var p := pts[i]
			out[i] = at + Vector2(p.x * cs - p.y * sn, p.x * sn + p.y * cs)
		return out

	# --- Flames ---------------------------------------------------------------
	## Tongues licking the rim, each a tapered triangle with a hotter core. The
	## two phases differ in tongue height AND angle, so the cross-fade reads as
	## fire moving rather than as a layer fading.
	func _flames(box: float) -> void:
		var c := size * 0.5
		var r := box * 0.34
		# NINE wide tongues, not thirteen thin ones. At thirteen the ring read as
		# a saw blade: the gaps were narrower than the teeth, so the eye joined
		# them into one spiky outline instead of seeing separate flames.
		const N := 9
		for i in N:
			var t := float(i) / float(N)
			var a := TAU * t + (0.30 if phase == 1 else 0.0)
			var lick := 0.18 + 0.22 * absf(sin(t * 9.0 + float(phase) * 2.2))
			var dir := Vector2(cos(a), sin(a))
			var side := Vector2(-dir.y, dir.x)
			var w := r * 0.30
			# The tip LEANS. Symmetrical tongues all the way round read as a sun,
			# which is a perfectly good ornament and not the one this is called.
			# One consistent lean is what makes the ring read as fire moving.
			draw_colored_polygon(PackedVector2Array([
				c + dir * r - side * w,
				c + dir * (r + r * lick) + side * w * 1.15,
				c + dir * r + side * w,
			]), Color(accent.lerp(Color("FFB25E"), 0.45), 0.45))
			draw_colored_polygon(PackedVector2Array([
				c + dir * r - side * w * 0.42,
				c + dir * (r + r * lick * 0.62) + side * w * 0.72,
				c + dir * r + side * w * 0.42,
			]), Color(Color("FFE7B0").lerp(accent, 0.25), 0.55))

	# --- Circuit --------------------------------------------------------------
	## An octagonal trace with a soldered node at each corner and a stub running
	## inward. Polylines and discs only — no fills to triangulate.
	func _circuit(box: float) -> void:
		var c := size * 0.5
		var r := box * 0.38
		var pts := PackedVector2Array()
		for i in 9:
			var a := TAU * float(i % 8) / 8.0 - PI * 0.5
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_polyline(pts, Color(accent, 0.50), maxf(2.0, box * 0.011), true)
		for i in 8:
			var a := TAU * float(i) / 8.0 - PI * 0.5
			var d := Vector2(cos(a), sin(a))
			draw_line(pts[i], pts[i] - d * box * 0.055, Color(accent, 0.32),
				maxf(1.5, box * 0.007), true)
			draw_circle(pts[i], maxf(3.0, box * 0.020),
				Color(accent.lerp(Color.WHITE, 0.45), 0.90))

	# --- Wings ----------------------------------------------------------------
	## Four swept feathers off each flank, longest at the bottom. Each is a
	## tapered quad, convex by construction, so its fill is two triangles.
	func _wings(box: float) -> void:
		var c := size * 0.5
		# Two radii, and both matter. `reach` is where the feathers are ROOTED —
		# outside the shield, or three quarters of every wing is drawn under the
		# badge art and the frame reads as a smudge at its shoulder. `span` is how
		# far they then travel, and root + span must stay inside half the padded
		# box or the wingtips are clipped by their own node.
		var reach := box * 0.30
		var span := box * 0.17
		for s in 2:
			var side := -1.0 if s == 0 else 1.0
			for f in 4:
				var t := float(f) / 3.0
				var ang := deg_to_rad(lerpf(16.0, -46.0, t))
				var dir := Vector2(side * cos(ang), sin(ang))
				var perp := Vector2(-dir.y, dir.x)
				var root := c + Vector2(side * reach, reach * 0.34)
				var tip := root + dir * span * lerpf(1.0, 0.62, t)
				var w0 := reach * lerpf(0.24, 0.14, t)
				var w1 := reach * 0.03
				draw_colored_polygon(PackedVector2Array([
					root - perp * w0, tip - perp * w1, tip + perp * w1, root + perp * w0,
				]), Color(accent.lerp(Color.WHITE, 0.20 + 0.22 * t), 0.72 - 0.10 * t))

	# --- Prism ----------------------------------------------------------------
	## Six facets refracting off the rim, each on its own place on the wheel. The
	## one ornament that leaves the accent behind, because splitting light is the
	## whole idea and a monochrome prism is just a fan.
	func _prism(box: float) -> void:
		var c := size * 0.5
		var r := box * 0.30
		# EIGHT narrow facets on a tight ring. Six wide ones at a third again the
		# radius left the layer entirely at the corners, and what survived read as
		# loose coloured triangles rather than as light bending round a rim.
		const N := 8
		for i in N:
			var a0 := TAU * float(i) / float(N) - PI * 0.5
			var a1 := a0 + TAU / float(N) * 0.72
			var am := (a0 + a1) * 0.5
			var col := Color.from_hsv(fmod(accent.h + float(i) / float(N), 1.0), 0.55, 1.0)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(cos(a0), sin(a0)) * r,
				c + Vector2(cos(am), sin(am)) * r * 1.30,
				c + Vector2(cos(a1), sin(a1)) * r,
			]), Color(col, 0.34))

	# --- Constellation --------------------------------------------------------
	## Nine linked stars around the badge. The link lines are drawn FIRST so the
	## stars sit on the figure rather than behind it.
	func _constellation(box: float) -> void:
		var c := size * 0.5
		var r := box * 0.36
		const N := 9
		var pts := PackedVector2Array()
		for i in N:
			var t := float(i) / float(N)
			var a := TAU * t - PI * 0.5 + (0.12 if phase == 1 else 0.0)
			pts.append(c + Vector2(cos(a), sin(a)) * r
				* (0.88 + 0.15 * sin(t * 7.0 + float(phase))))
		for i in N:
			draw_line(pts[i], pts[(i + 1) % N], Color(accent, 0.20),
				maxf(1.0, box * 0.005), true)
		for i in N:
			var s := box * (0.016 + 0.013 * float((i + phase) % 3))
			var p := pts[i]
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -s * 2.2), p + Vector2(s, 0),
				p + Vector2(0, s * 2.2), p + Vector2(-s, 0),
			]), Color(accent.lerp(Color.WHITE, 0.55), 0.85))
			draw_circle(p, s * 0.55, Color(1, 1, 1, 0.75))

## A tappable badge for the player's *current* tier (home profile icon). Falls
## back to the locked Bronze badge before any tier is earned.
static func make_button(box: float, ratio: float, on_press: Callable) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(box, box)

	var idx := current_index(ratio)
	var view := make_view(box, maxi(idx, 0), idx < 0)
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.custom_minimum_size = Vector2.ZERO
	holder.add_child(view)

	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	btn.pressed.connect(func():
		AudioManager.play_sfx("button_tap", 0.04)
		Haptics.light()
		on_press.call())
	holder.add_child(btn)
	UI.wire_press(holder, btn)
	return holder
