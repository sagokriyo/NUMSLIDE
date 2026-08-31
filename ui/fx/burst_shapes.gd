class_name BurstShapes
extends RefCounted
## The particle SHAPES a merge burst throws.
##
## Every burst used to fire the same soft radial dot, so a merge on Autumn threw
## the same thing as a merge on Ruby — only the colour changed. A material reads
## from its silhouette long before its hue: a maple leaf tumbles, a gem falls
## hard and glints, a petal hangs in the air, a blood drop stretches as it flies.
## These are those silhouettes.
##
## Every bake here is a pure white/greyscale MASK with no palette input — the
## particle system tints it per-emitter at render time — so one copy serves every
## theme and every board. They are cached `static`ally for the same reason
## BoardFx caches its own sprites: a fresh board is built on every gameplay entry
## and a per-pixel Callable bake is far too expensive to pay again each time.
##
## uv runs -1..1 on both axes. Where a shape has to look ROUND, remember the bake
## is square but the particle is drawn square too, so no aspect correction is
## needed here (unlike the board_fx landmark bakes, which are drawn into
## non-square rects).

static var _cache: Dictionary = {}

## Bake `id` once and hand back the shared texture.
static func get_tex(id: String) -> Texture2D:
	var hit: Texture2D = _cache.get(id)
	if hit != null:
		return hit
	var made: Texture2D = _bake(id)
	_cache[id] = made
	return made

static func _bake(id: String) -> Texture2D:
	match id:
		"petal":    return _shape(28, 28, _fn_petal)
		"leaf":     return _shape(34, 30, _fn_leaf)
		"gem":      return _shape(28, 32, _fn_gem)
		"shard":    return _shape(20, 40, _fn_shard)
		"star4":    return _shape(34, 34, _fn_star4)
		"pixel":    return _shape(12, 12, _fn_pixel)
		"drop":     return _shape(16, 30, _fn_drop)
		"sprinkle": return _shape(14, 30, _fn_sprinkle)
		"barb":     return _shape(16, 40, _fn_barb)
		"hex":      return _shape(28, 26, _fn_hex)
		"fold":     return _shape(28, 28, _fn_fold)
		"grain":    return _shape(10, 10, _fn_grain)
		"scale":    return _shape(24, 20, _fn_scale)
		# Emblems (tile crests) — baked larger than the burst shapes because they
		# are shown at ~60% of a tile, not as 20 px particles.
		"ring":      return _shape(64, 64, _fn_ring)
		"crescent":  return _shape(64, 64, _fn_crescent)
		"star5":     return _shape(64, 64, _fn_star5)
		"heart":     return _shape(64, 60, _fn_heart)
		"coin":      return _shape(64, 64, _fn_coin)
		"snowflake": return _shape(64, 64, _fn_snowflake)
		_:          return _shape(16, 16, _fn_grain)

static func _shape(w: int, h: int, fn: Callable) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var uv := Vector2(
				float(x) / float(w - 1) * 2.0 - 1.0,
				float(y) / float(h - 1) * 2.0 - 1.0)
			img.set_pixelv(Vector2i(x, y), fn.call(uv) as Color)
	return ImageTexture.create_from_image(img)

# --- Soft, drifting materials -------------------------------------------------

## A blossom petal: narrow where it was attached, swelling to a broad rounded
## tip with a heart-notch cut into it. The first version measured a near-circular
## ellipse and put the notch out at the rim, which produced a plain disc.
static func _fn_petal(uv: Vector2) -> Color:
	# t: 0 at the base (bottom of the bake), 1 at the tip.
	var t := clampf((0.92 - uv.y) / 1.84, 0.0, 1.0)
	if t <= 0.0 or t >= 1.0:
		return Color(0, 0, 0, 0)
	# Width profile: a narrow stalk opening into a broad blade.
	var hw: float = 0.74 * pow(sin(pow(t, 0.55) * PI), 1.25)
	var a: float = 1.0 - smoothstep(hw - 0.14, hw, absf(uv.x))
	# The notch: a bite out of the very tip, which is what says "petal".
	var notch := Vector2(uv.x / 0.30, (uv.y + 0.86) / 0.34).length()
	a *= smoothstep(0.55, 1.05, notch)
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	# Brighter down the midrib, so the petal has a fold rather than reading flat.
	var b: float = 0.66 + 0.34 * (1.0 - smoothstep(0.0, 0.42, absf(uv.x) / maxf(hw, 0.01)))
	b *= 0.84 + 0.16 * t
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A maple leaf: five lobes off a central point, with a stem and visible veins.
static func _fn_leaf(uv: Vector2) -> Color:
	var ang := atan2(uv.y + 0.15, uv.x)
	var r := Vector2(uv.x, uv.y + 0.15).length()
	# Five lobes: the radius swings with the angle.
	var lobe: float = 0.60 + 0.34 * absf(cos(ang * 2.5))
	# Notches between the lobes cut back toward the centre.
	lobe -= 0.16 * pow(clampf(1.0 - absf(cos(ang * 2.5)), 0.0, 1.0), 0.6)
	var a: float = 1.0 - smoothstep(lobe - 0.10, lobe, r)
	# The stem.
	if absf(uv.x) < 0.055 and uv.y > 0.42:
		a = maxf(a, 1.0)
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	# Veins radiating from the leaf's base.
	var vein: float = 1.0 - smoothstep(0.0, 0.10, absf(fposmod(ang * 5.0 / PI, 1.0) - 0.5))
	var b: float = 0.62 + 0.26 * vein + 0.18 * (1.0 - r)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A single wing scale — the iridescent dust a butterfly leaves on your fingers.
static func _fn_scale(uv: Vector2) -> Color:
	var p := Vector2(uv.x * 1.1, uv.y)
	var a := 1.0 - smoothstep(0.70, 1.0, p.length())
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	# Fine ribs across it — the diffraction grating that makes a morpho blue.
	var rib: float = 0.5 + 0.5 * sin(uv.x * 15.0)
	var b: float = 0.55 + 0.45 * rib
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A torn paper fleck: a ragged quad with one clean cut edge and one torn one.
static func _fn_fold(uv: Vector2) -> Color:
	# A quad, rotated a little, with the lower edge chewed.
	var tear: float = 0.16 * absf(sin(uv.x * 9.0)) + 0.08 * absf(sin(uv.x * 23.0))
	if absf(uv.x) > 0.82 or uv.y < -0.78 or uv.y > 0.62 - tear:
		return Color(0, 0, 0, 0)
	# A crease down the middle: one half catches the light, the other does not.
	var b: float = 0.95 if uv.x < 0.06 else 0.58
	return Color(b, b, b, 1.0)

# --- Hard, fast materials -----------------------------------------------------

## A cut gem seen face on: a brilliant. A flat table in the middle, a ring of
## crown facets around it, and a hard octagonal girdle. The silhouette must be
## FLAT-SIDED — the first version soft-stepped a barely-varying radius, which
## scalloped the edge into a flower.
static func _fn_gem(uv: Vector2) -> Color:
	# Octagon by half-plane test: inside iff it is behind all eight edges.
	var d := -1e9
	for k in 8:
		var ang: float = TAU * float(k) / 8.0 + PI / 8.0
		d = maxf(d, uv.x * cos(ang) + uv.y * sin(ang))
	if d > 0.88:
		return Color(0, 0, 0, 0)
	var a: float = 1.0 - smoothstep(0.84, 0.88, d)
	var pang := atan2(uv.y, uv.x)
	# Crown facets: eight wedges, alternating light and dark so the stone has
	# structure rather than a gradient.
	var wedge: float = fposmod(pang / (TAU / 8.0) + 0.5, 1.0)
	var b: float = 0.38 + 0.34 * (1.0 - absf(wedge - 0.5) * 2.0)
	# The table: a flat, bright octagon in the centre.
	if d < 0.42:
		b = 0.95
	# The girdle catches a hard line of light all the way round.
	b = maxf(b, (1.0 - smoothstep(0.0, 0.07, absf(d - 0.80))) * 0.85)
	# One specular burn on the upper-left crown.
	b += (1.0 - smoothstep(0.0, 0.34, Vector2(uv.x + 0.30, uv.y + 0.32).length())) * 0.45
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A splinter of glass or ice: a long thin wedge, brightest along one edge.
static func _fn_shard(uv: Vector2) -> Color:
	var t := clampf((uv.y + 1.0) * 0.5, 0.0, 1.0)
	# A wedge, widest a third of the way down, tapering to both ends.
	var hw: float = 0.62 * sin(pow(t, 0.75) * PI)
	if absf(uv.x) > hw:
		return Color(0, 0, 0, 0)
	var a: float = 1.0 - smoothstep(hw - 0.14, hw, absf(uv.x))
	# One lit edge and one dark, so it reads as a solid with thickness.
	var b: float = 0.35 + 0.65 * clampf(0.5 - uv.x / maxf(hw, 0.01) * 0.5, 0.0, 1.0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A four-point sparkle — the "kirakira" star, with a hot core.
static func _fn_star4(uv: Vector2) -> Color:
	var ax := absf(uv.x)
	var ay := absf(uv.y)
	# Two crossed needles: distance falls off fast across each arm.
	var h: float = (1.0 - smoothstep(0.0, 0.10, ay)) * (1.0 - smoothstep(0.10, 1.0, ax))
	var v: float = (1.0 - smoothstep(0.0, 0.10, ax)) * (1.0 - smoothstep(0.10, 1.0, ay))
	var core: float = 1.0 - smoothstep(0.02, 0.26, uv.length())
	var a := clampf(maxf(maxf(h, v), core), 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

## A hard-edged pixel — no falloff at all, which is the entire point on a CRT.
static func _fn_pixel(uv: Vector2) -> Color:
	if absf(uv.x) > 0.82 or absf(uv.y) > 0.82:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, 1)

## A liquid drop in flight: a round head with a tail drawn out behind it.
static func _fn_drop(uv: Vector2) -> Color:
	# Head at the bottom, tail stretching up — drawn to be used with align_y.
	var head := Vector2(uv.x, (uv.y - 0.52) * 1.25).length() / 0.48
	var a: float = 1.0 - smoothstep(0.86, 1.0, head)
	if uv.y < 0.52:
		var t := (0.52 - uv.y) / 1.52
		var hw: float = 0.46 * pow(1.0 - t, 1.7)
		a = maxf(a, 1.0 - smoothstep(hw * 0.5, hw, absf(uv.x)))
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	# A specular highlight on the shoulder of the head.
	var b: float = 0.66
	b += (1.0 - smoothstep(0.0, 0.30, Vector2(uv.x + 0.16, uv.y - 0.38).length())) * 0.34
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A sugar sprinkle: a stubby capsule with rounded ends.
static func _fn_sprinkle(uv: Vector2) -> Color:
	var y := clampf(uv.y, -0.58, 0.58)
	var d := Vector2(uv.x, uv.y - y).length()
	var a: float = 1.0 - smoothstep(0.34, 0.46, d)
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	# Round it: bright along the upper-left of the capsule.
	var b: float = 0.55 + 0.45 * clampf(0.5 - uv.x * 0.9, 0.0, 1.0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A feather barb: a long taper with a fine central quill.
static func _fn_barb(uv: Vector2) -> Color:
	var t := clampf((uv.y + 1.0) * 0.5, 0.0, 1.0)
	var hw: float = 0.52 * sin(pow(t, 0.6) * PI) + 0.04
	if absf(uv.x) > hw:
		return Color(0, 0, 0, 0)
	var a: float = 1.0 - smoothstep(hw - 0.16, hw, absf(uv.x))
	# The quill, and the barbules combing off it.
	var quill: float = 1.0 - smoothstep(0.0, 0.06, absf(uv.x))
	var comb: float = 0.5 + 0.5 * sin(uv.y * 34.0)
	var b: float = 0.42 + 0.34 * comb + quill * 0.36
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A wax cell: a flat hexagon with a lit rim.
static func _fn_hex(uv: Vector2) -> Color:
	var ang := atan2(uv.y, uv.x)
	var hexr: float = 0.84 / maxf(cos(fposmod(ang, PI / 3.0) - PI / 6.0), 0.5)
	var r := uv.length()
	if r > hexr:
		return Color(0, 0, 0, 0)
	var a: float = 1.0 - smoothstep(hexr - 0.12, hexr, r)
	var b: float = 0.55 + 0.45 * smoothstep(hexr * 0.5, hexr, r)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A grain of sand or dust: a small soft disc, barely irregular. The wobble runs
## at a high frequency and a low amplitude — at three lobes it came out a
## rounded triangle, which is not what dust looks like.
static func _fn_grain(uv: Vector2) -> Color:
	var wob: float = 0.90 + 0.06 * sin(atan2(uv.y, uv.x) * 7.0)
	var a: float = 1.0 - smoothstep(wob * 0.45, wob, uv.length())
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

# --- Emblems (tile crests) ------------------------------------------------------
# Watermark marks a 2048+ tile wears under its numeral (TileView). Same contract
# as everything above: pure white/grey masks, tinted by the wearer.

## An open circle — the ensō, a full moon, a bubble: a soft ring with a slightly
## hotter inner edge so it reads brushed rather than mechanical.
static func _fn_ring(uv: Vector2) -> Color:
	var d := absf(uv.length() - 0.64)
	var a: float = 1.0 - smoothstep(0.08, 0.18, d)
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	var b: float = 0.78 + 0.22 * (1.0 - smoothstep(0.0, 0.09, d))
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A crescent moon: a disc with a second disc bitten out of its upper right.
static func _fn_crescent(uv: Vector2) -> Color:
	var body: float = 1.0 - smoothstep(0.74, 0.84, uv.length())
	var bite: float = 1.0 - smoothstep(0.58, 0.70, (uv - Vector2(0.34, -0.14)).length())
	var a := clampf(body - bite, 0.0, 1.0)
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	var b: float = 0.80 + 0.20 * (1.0 - uv.length())
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A five-point star, point up, with a brighter heart.
static func _fn_star5(uv: Vector2) -> Color:
	var r := uv.length()
	var ang := atan2(uv.y, uv.x) + PI * 0.5
	# 0 on a spike's axis, 1 midway between two spikes.
	var k: float = absf(fposmod(ang, TAU / 5.0) / (TAU / 5.0) - 0.5) * 2.0
	var edge: float = lerpf(0.92, 0.40, pow(k, 0.75))
	var a: float = 1.0 - smoothstep(edge - 0.10, edge, r)
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	var b: float = 0.70 + 0.30 * (1.0 - smoothstep(0.0, 0.55, r))
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A soft heart — the classic implicit curve, with a catch-light on one lobe.
static func _fn_heart(uv: Vector2) -> Color:
	var p := Vector2(uv.x * 1.25, -uv.y * 1.25 + 0.12)
	var q: float = p.x * p.x + p.y * p.y - 1.0
	var f: float = q * q * q - p.x * p.x * p.y * p.y * p.y
	var a: float = 1.0 - smoothstep(-0.06, 0.08, f)
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	var b: float = 0.72
	b += (1.0 - smoothstep(0.0, 0.40, (uv - Vector2(-0.30, -0.28)).length())) * 0.28
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A struck coin face-on: a raised rim, an inner ring, a specular burn.
static func _fn_coin(uv: Vector2) -> Color:
	var r := uv.length()
	var a: float = 1.0 - smoothstep(0.84, 0.92, r)
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	var b: float = 0.55
	b = maxf(b, (1.0 - smoothstep(0.0, 0.09, absf(r - 0.76))) * 0.95)
	b = maxf(b, (1.0 - smoothstep(0.0, 0.06, absf(r - 0.48))) * 0.78)
	b += (1.0 - smoothstep(0.0, 0.42, (uv + Vector2(0.28, 0.28)).length())) * 0.26
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A six-armed snowflake: needle arms with a short cross-bar partway out.
static func _fn_snowflake(uv: Vector2) -> Color:
	var r := uv.length()
	if r > 0.95:
		return Color(0, 0, 0, 0)
	var ang := atan2(uv.y, uv.x)
	# Fold into one arm: angular distance from the nearest of the six axes.
	var k: float = absf(fposmod(ang, TAU / 6.0) - TAU / 12.0)
	var d: float = sin(k) * r   # perpendicular distance from the arm's centreline
	var arm: float = (1.0 - smoothstep(0.035, 0.075, d)) * (1.0 - smoothstep(0.78, 0.90, r))
	var twig := 0.0
	for tr_v in [0.36, 0.60]:
		var ring_r: float = tr_v
		var seg: float = 1.0 - smoothstep(0.0, 0.08, absf(r - ring_r))
		twig = maxf(twig, seg * (1.0 - smoothstep(0.08, 0.20, d)))
	var core: float = 1.0 - smoothstep(0.04, 0.16, r)
	var a := clampf(maxf(maxf(arm, twig * 0.85), core), 0.0, 1.0)
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)
