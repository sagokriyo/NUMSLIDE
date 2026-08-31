class_name ExtrudedWord
extends Control
## ExtrudedWord — a chunky, dimensional wordmark built entirely on the 2D canvas.
##
## True 3D TextMesh can't tessellate Malam Poek's hand-drawn, self-intersecting
## outlines, so we fake the depth the way title cards do: the glyphs are stamped
## many times, each copy nudged along an extrusion vector and shaded darker the
## deeper it sits, then the bright **gradient-shaded front face** is laid on top.
## The result is a tactile, beveled "3D 2048" that matches the bubble font and
## costs one `_draw`. Colours are the brand violet→pink→orange sweep.
##
## On top of that the digits are INFLATED (see `puff` / `_balloon_body`): every
## glyph is stamped as a dilated copy of itself before the fill, which fattens the
## strokes, rounds every corner and leaves a shaded band around the letter — dark
## underneath, lit on the crown — so "2048" reads as four fluffy, air-filled
## balloons rather than four flat cut-outs.

@export var text := "2048"

## The board tiles the four digits are painted from, low to high, index-matched
## to "2048" — dressed through CandyFace.color so the word wears the tiles' own
## vivid candy paint. Home, the sign-in screen and Candy Pop's confetti all read
## this list: it used to be written out at each site, and three copies of a
## palette are three chances for the word and the things thrown at it to stop
## matching.
const WORDMARK_TILES: Array[int] = [2, 16, 256, 2048]
@export var font_size := 200
@export var c0 := Color("7B5CF0")
@export var c1 := Color("E0529C")
@export var c2 := Color("F2913D")
## Extrusion direction + length, in design px (down-right reads as lifted light).
@export var extrude := Vector2(6, 10)
@export var layers := 15
## How far the glyphs INFLATE, as a fraction of font_size. The digits are stamped
## as dilated (outline) shapes before the fill, which fattens every stroke, rounds
## every corner and shrinks the counters — the bubble font blown up into balloons.
## The dilation band wears the tile's edge-lit rim over its own body colour (see
## `_balloon_body`), and the shader's lit-crown-over-dark-underside ramp does the
## rest, so the fat edge reads as an air-filled body rather than a sticker.
## This is where the FLUFF comes from — the material is the tiles', flat and
## identical on every surface, and only the shape it is painted onto is round.
## The counters are no longer this dial's concern: every digit is SEALED solid
## (see _seal_polys — the 0's eye, the 4's notch and the 8's windows are filled
## with body colour by design), so the cap is purely about the outer
## silhouette: past ~0.045 the balloons swallow their neighbours' air.
const PUFF_DEFAULT := 0.041

## The rim ring's width, also as a fraction of font_size — the tile's edge-lit
## border (CandyFace layer 3), which is ~2.75% of a tile's side and lands here at
## a digit's proportions. It is stamped OUTSIDE the body dilation, not carved out
## of it: a hole that seals shut must fill with BODY colour, and when the rim was
## the outer part of one shared dilation the sealed counter of the 0 filled with
## near-white instead and read as a milky patch under the face.
const RIM_FRAC := 0.021

## The full silhouette inflation: the FATTEST digit's dilation (the borrowed 4
## inflates PUFF_SOFTEN_MAX times further than its siblings — see PUFF_SOFTEN)
## plus the ring around it. Layout code that fits the word to a screen width
## (Home's and Auth's hero sizing) must reserve air off THIS, never off `puff`
## alone, or every gap it books comes up short and the balloons overlap on a
## narrow phone — which is exactly how the 4 came to kiss the 8.
const PUFF_SOFTEN_MAX := 2.3
const SILHOUETTE_FRAC := PUFF_DEFAULT * PUFF_SOFTEN_MAX + RIM_FRAC
@export var puff := PUFF_DEFAULT:
	set(v): puff = maxf(v, 0.0); _remeasure()

var _font: Font
var _measure: Vector2
var _ink_cache: Dictionary = {}   # char -> ink Rect2 (see _ink_rect)
# How dark the active theme's backdrop is (0 bright .. 1 night). Sampled once at
# _ready (the wordmark is rebuilt on every theme change, so once is enough) and
# fed to the shader + the glint painter: glass in a dark room keeps its white
# fire, so the corner gleam and the sparkle scale up with this.
var _env_dark := 0.0
# The room's KEY-LIGHT COLOUR: pure white in a plain studio, leaned toward the
# theme's luxe material accent (ThemeManager.board_accent — the same colour the
# board frame rim and tile sheen already wear), so the word's white fire is
# lit by ITS OWN world: bronze on Clockwork, forge amber on Nova Forge, phosphor
# on the CRT. Matte worlds (paper, sand, onyx — accent alpha 0) fall through to
# the pure white rig, exactly as their boards fall through to no luxe treatment.
# Sampled once at _ready, like _env_dark: the wordmark rebuilds on theme change.
var _fire := Color(1, 1, 1)
# How many ink boxes the shader's glyph_ybox was last synced from. Glyphs only
# rasterise on their first draw, so the first sync runs off estimates — the end
# of _draw re-syncs once the cache has grown and the real boxes are known.
var _synced_inks := -1

# --- Glass finish -----------------------------------------------------------------
# A canvas shader over every stamped copy, lighting the glyph bodies with the
# BOARD TILES' OWN material (CandyFace._glass_face), layer for layer and number
# for number: the same body endpoints (lightened 0.20 → darkened 0.28), the same
# diagonal glass streak at the same alpha and transition width, the same top
# inner highlight, the same bottom inner shade and the same corner gleam. The
# word and the tiles are ONE material under one up-left light — that is what
# makes the hero and the shards drifting behind it read as the same object
# family instead of two different substances sharing a palette.
#
# This REPLACED the crystal rig (2026-08, user ask: "the material should be the
# same as the game tile"). What went with it — and must not creep back, because
# each one is a "cut optical glass" cue rather than a tile cue: the see-through
# window (transmission ran at 0.88; that transparency IS what read as
# crystallise), the chromatic dispersion, the mirrored internal-reflection
# fetch, the painted interior arcs, the squared-and-sunk base, the razor glaze
# ellipse, and the dark dense bevel contour stamped inside the rim.
#
# The geometry still differs, and should: a digit is a ROUND, air-filled body,
# not a flat slab. The tile's paint is applied as-is; the fluff comes from the
# shape it is applied to — a fatter dilation, rounder corners, and the tile's
# own lit-crown-over-dark-underside ramp reading as volume on a curved form.
#
# The streak runs across EACH DIGIT (see `glyph_box`), not across the whole word —
# a word-wide diagonal lit the first digit and left the last one flat, which is
# why the sweep was removed the first time round.
#
# Overlays are alpha-composited white/black, weighted by glyph alpha. NOTE: D3D12
# renders DESCENDING smoothstep edges black — keep every smoothstep ascending and
# invert with `1.0 - …` instead.
static var _gloss_shader: Shader

## THE FLOOR — opt-in. A soft contact shadow under each digit and a compressed,
## blurred, fading reflection of its inflated silhouette, the way a polished
## black table reflects a toy. OFF by default: Home's hero was art-directed
## floorless ("remove the shadow and reduce the gap" — the band the floor needs
## under the word pushed the tagline down), so a screen or a studio composition
## that wants the floor asks for it. Drawn on an UN-shadered child, because the
## gloss shader adds white light across its canvas and would grey the shadow.
var floor_reflection := false:
	set(v):
		floor_reflection = v
		if is_inside_tree():
			_rebuild_ground()
			_remeasure()
var _ground: Node2D
static var _ground_fade_shader: Shader

static func _get_ground_fade_shader() -> Shader:
	if _ground_fade_shader == null:
		_ground_fade_shader = Shader.new()
		_ground_fade_shader.code = """
shader_type canvas_item;
uniform float fade_y0 = 0.0;
uniform float fade_y1 = 100.0;
varying vec2 v_pos;
void vertex() { v_pos = VERTEX; }
void fragment() {
	COLOR.a *= 1.0 - smoothstep(fade_y0, fade_y1, v_pos.y);
}
"""
	return _ground_fade_shader

func _rebuild_ground() -> void:
	if _ground != null:
		_ground.queue_free()
		_ground = null
	if not floor_reflection:
		return
	_ground = Node2D.new()
	_ground.draw.connect(_draw_ground_layer)
	var gm := ShaderMaterial.new()
	gm.shader = _get_ground_fade_shader()
	_ground.material = gm
	add_child(_ground)

## The floor itself: one soft dark pool per digit hugging the baseline, then
## the silhouette mirrored and foreshortened (-0.55) in three low-alpha stamps a
## hair apart — the blur of a polished, not mirror-perfect, surface — dissolving
## with distance through the fade material. Only SHAPES are mirrored, never
## the faces: no duplicated eyes, no ghost characters, no floating copies.
func _draw_ground_layer() -> void:
	if _font == null or _ground == null or layers > 0:
		return
	var fs := float(font_size)
	var pad := Vector2(fs * 0.12, fs * 0.34)
	var origin := pad + Vector2(-optical_dx * fs, _font.get_ascent(font_size))
	var total: float = maxf(_measure.x, 1.0)
	if _ground.material is ShaderMaterial:
		var fm := _ground.material as ShaderMaterial
		fm.set_shader_parameter("fade_y0", origin.y + fs * 0.05)
		fm.set_shader_parameter("fade_y1", origin.y + fs * 0.34)
	var x := 0.0
	for i in text.length():
		var ch := text[i]
		var adv := _advance(ch)
		var scx := origin.x + x + adv * 0.5
		var sw := adv * 1.05 + fs * (_puff_of(ch) + RIM_FRAC) * 1.6
		_ground.draw_texture_rect(CandyFace.glow_dot(),
			Rect2(scx - sw * 0.5, origin.y - fs * 0.06, sw, fs * 0.24), false, Color(0, 0, 0, 0.50))
		x += adv + _gap()
	var sy := -0.50
	var pivot_y := origin.y + fs * 0.04
	_ground.draw_set_transform_matrix(
		Transform2D(0.0, Vector2(1.0, sy), 0.0, Vector2(0.0, pivot_y * (1.0 - sy))))
	x = 0.0
	for i in text.length():
		var ch := text[i]
		var adv := _advance(ch)
		var col: Color = glyph_colors[i] if glyph_colors.size() == text.length() \
			else _grad(clampf((x + adv * 0.5) / total, 0.0, 1.0))
		# Darker than the digit — a polished black floor returns a dim image —
		# and blurred wider, dissolving through the fade material.
		var rc := col.darkened(0.25)
		rc.a = 0.085
		# The BASE puff, not the borrowed 4's boosted one: at full dilation its
		# open notch fills in and the pool reflects a slab, not a 4.
		var m := _offset_mesh(ch, fs * (puff + RIM_FRAC))
		for bx: float in [-0.018, 0.0, 0.018]:
			_stamp_mesh(_ground, m, origin + Vector2(x + bx * fs, 0.0), rc)
		x += adv + _gap()
	_ground.draw_set_transform_matrix(Transform2D())

# The lite-GPU twin: identical program, but `screen_tex` is a PLAIN sampler fed
# AppScreen's reduced-res backdrop target instead of a hint_screen_texture.
# Declaring hint_screen_texture AT ALL makes the engine copy the framebuffer for
# this draw, so the swap must happen at the declaration, not in a branch. The
# backdrop texture is full-screen, so SCREEN_UV addresses it unchanged and every
# refraction/reflection term lands on the same pixels it did before.
static var _gloss_shader_lite: Shader

static func _get_gloss_shader(lite: bool = false) -> Shader:
	if lite:
		if _gloss_shader_lite == null:
			_gloss_shader_lite = Shader.new()
			_gloss_shader_lite.code = _get_gloss_shader(false).code.replace(
				"uniform sampler2D screen_tex : hint_screen_texture, filter_linear;",
				"uniform sampler2D screen_tex : filter_linear;")
		return _gloss_shader_lite
	if _gloss_shader == null:
		_gloss_shader = Shader.new()
		_gloss_shader.code = """
shader_type canvas_item;
uniform float y_top = 0.0;
uniform float y_bot = 100.0;
// (centre_x, half_width) per digit in item space — see _sync_glyph_boxes.
uniform vec2 glyph_box[8];
// (ink top y, ink height) per digit in item space, inflated by the puff — the
// glyph's REAL body, not the font's em box. Every vertical lighting term rides
// this, so the glaze/wet/shade land on the blob instead of on the padding.
uniform vec2 glyph_ybox[8];
uniform int glyph_count = 0;
// The DEEP-BODY extras (0 = flat tile paint and nothing else): the whisper of
// the room seen through the heart of each digit, the refraction that bends it,
// and the Fresnel fire along the silhouette. A tile is 4 mm of glass and is
// simply opaque; a digit is a thick body, so a little of what is behind it
// still gets through — at a fraction of the old strength. The backdrop comes
// from AppScreen's BackBufferCopy, snapshotted BEFORE this control draws. No
// extra screen read is paid: the frosted cards already rely on the same copy.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float glass : hint_range(0.0, 1.0) = 0.0;
// How dark the active theme's room is (0 = bright studio, 1 = night scene).
// Polished glass in a dark room KEEPS its white fire — the corner gleam and the
// silhouette's Fresnel scale up with this, while the body's paint stays put.
// Without it the dark themes read smoky rather than lit.
uniform float env_dark = 0.0;
// The key light's COLOUR (script-side `_fire`): the fire terms — the corner
// gleam and the silhouette's Fresnel — carry it, so the word is lit by its
// theme's own room rather than a hardcoded studio white. Always near-white;
// exactly vec3(1) on matte worlds. The tile's own white overlays (the diagonal
// streak, the top inner highlight) deliberately stay PURE white, exactly as
// CandyFace paints them: the room's colour belongs in the light, not in the
// material, and those two are the material.
uniform vec3 fire_tint = vec3(1.0);
// GYRO PARALLAX: the device tilt (phone gravity; desktop falls back to the
// slow turn sway). The whole light rig follows it — the corner gleam slides,
// the internal reflection swings to the wall you tipped toward, and the caustic
// pool slides across the floor of the body — so tilting the phone reads as
// turning a real object in your hand.
uniform vec2 tilt = vec2(0.0);
// REFRACTION SHIMMER (0 off / 1 on, follows `animate` so reduce-motion stays
// still): a very slow wobble of the refraction offset, so the room seen through
// the digits breathes like still water rather than sitting frozen.
uniform float shimmer = 0.0;
// FORM LIGHTING (1 = on): the body is lit from GEOMETRY — nested insets of the
// sealed silhouette with per-vertex normals (see _form_balloon) — so every
// painted layer below (the box-coordinate streak, crown band, corner gleam)
// steps aside and the vertex colours pass through untouched. Box coordinates
// cannot follow a curved silhouette; the polygons can.
uniform float form_lit = 0.0;
varying vec2 v_pos;
void vertex() { v_pos = VERTEX; }
void fragment() {
	vec4 src = COLOR;   // form-lit bodies hand this straight back at the end
	// Which digit this fragment sits on, as a -1..1 coordinate ACROSS THAT DIGIT,
	// plus that digit's own vertical ink bounds. Every lighting term rides these,
	// so each digit is lit across its own round body however the font packs it.
	float u = 0.0;
	vec2 yb = vec2(y_top, max(y_bot - y_top, 1.0));
	vec2 bx = vec2(0.0, 1.0);
	for (int i = 0; i < glyph_count; i++) {
		float lu = (v_pos.x - glyph_box[i].x) / max(glyph_box[i].y, 1.0);
		float inn = step(abs(lu), 1.0);
		u = mix(u, clamp(lu, -1.0, 1.0), inn);
		yb = mix(yb, glyph_ybox[i], inn);
		bx = mix(bx, glyph_box[i], inn);
	}
	float t = clamp((v_pos.y - yb.x) / max(yb.y, 1.0), 0.0, 1.0);
	// The tile's own y/hw axis: -1 at the crown, +1 at the base. Every number
	// below is lifted straight out of CandyFace._glass_face, where the face
	// spans -hw..hw in both axes — so `u` stands in for x/hw and `v` for y/hw
	// and the layer stack ports across unchanged.
	float v = t * 2.0 - 1.0;

	// --- LAYER 4: the body -----------------------------------------------------
	// The tile's exact endpoints, LINEAR between them: lightened(0.20) at the
	// crown, darkened(0.28) at the base. The crystal build eased this with
	// t^1.7 and sank the base into a squared saturated deep — a rigid slab's
	// shading. A straight ramp from a lit crown to a dark underside is both how
	// the tiles are painted AND how an air-filled body shades, which is why
	// matching the tile material is what brings the fluff back.
	vec3 rgb = mix(COLOR.rgb + (vec3(1.0) - COLOR.rgb) * 0.20, COLOR.rgb * 0.72, t);

	// --- THE GLASS, laid over the tile paint -----------------------------------
	// A tile is 4 mm of glass and reads simply opaque; a digit is a fat body of
	// the SAME material, and a fat body of glass bends light. So the tile's
	// paint above is the identity and this is the thickness: the room refracting
	// through the core, its colours splitting on the way, the scene mirroring
	// along the inside walls, and light pooling low inside the way it pools in
	// the bottom of CandyFace.draw_ball's sphere — which is this exact material
	// on a round body, and therefore the reference for every number here.
	//
	// The one hard rule, and the whole difference from the crystal rig this
	// replaced: the glass is HUE-LOCKED. Everything transmitted is multiplied by
	// the body's own colour at full strength, never mixed toward a neutral
	// filter. Crystal wants a colourless core; a glass TILE keeps its colour all
	// the way through, and that is what stops the digits going milky.
	if (glass > 0.001) {
		float rad = clamp(max(abs(u), abs(v)), 0.0, 1.0);
		float clarity = (1.0 - smoothstep(0.05, 0.86, rad)) * glass * 0.34;
		// THE FACE CUSHION: the eyes and mouth are drawn through this same
		// material, so transmission thins them against a dark backdrop. It is
		// suppressed hard in a soft oval where the face lives — the features
		// always rest on the digit's own solid colour, on every theme.
		vec2 fc = vec2((v_pos.x - bx.x) / max(bx.y * 0.62, 1.0),
			(v_pos.y - (yb.x + yb.y * 0.50)) / max(yb.y * 0.36, 1.0));
		clarity *= 1.0 - (1.0 - smoothstep(0.70, 1.05, length(fc))) * 0.94;
		// REFRACTION: rays entering the thick body bend toward the centre of the
		// form — flat through the middle, hardest at the silhouette where the
		// surface turns away — so the backdrop is sampled offset along the local
		// normal and whatever drifts behind the word visibly warps inside each
		// digit. The shimmer breathes that offset (off under reduce-motion).
		vec2 nrm = vec2(u, v);
		vec2 duv = -nrm * (0.24 + 1.05 * rad * rad) * SCREEN_PIXEL_SIZE * 54.0 * glass;
		duv *= 1.0 + 0.09 * shimmer * sin(TIME * 0.7 + (u + t) * 2.4);
		// CHROMATIC DISPERSION: the three channels bend by slightly different
		// amounts, fringing anything seen through the body. This is the cue that
		// says light is being SPLIT rather than tinted, and it is cheap here
		// because the sampler is AppScreen's half-res backdrop target.
		vec3 behind;
		behind.r = texture(screen_tex, SCREEN_UV + duv * 0.86).r;
		behind.g = texture(screen_tex, SCREEN_UV + duv).g;
		behind.b = texture(screen_tex, SCREEN_UV + duv * 1.18).b;
		// Hue-locked, and carried by the body's own scattered light so the core
		// can never sink toward a grey smear on a dark theme.
		rgb = mix(rgb, behind * (rgb * 1.7 + 0.16) + rgb * 0.34,
			clamp(clarity, 0.0, 1.0));
		// INTERNAL REFLECTION: what you see bouncing around inside thick glass
		// is a dimmed, mirrored image of the SCENE. Sample displaced along
		// +normal (the opposite wall — the refraction above went along -normal),
		// tint it by the body and weight it by rad^2 so it lives against the
		// inside of the walls and leaves the core alone. Drifting tiles glide
		// along the inner faces of the digits.
		vec2 tuv = SCREEN_UV + (nrm + tilt * 0.55) * SCREEN_PIXEL_SIZE
			* (40.0 + 64.0 * rad) * glass;
		vec3 tir = texture(screen_tex, tuv).rgb;
		rgb = mix(rgb, tir * (rgb * 1.4 + 0.22), pow(rad, 2.2) * 0.22 * glass);
		// THE CAUSTIC POOL: light focused through the body pools bright at the
		// lower inside, in the body's own hue lifted toward white — the exact
		// term draw_ball paints across the bottom of a sphere of this material.
		// It is the single strongest "light is bending in here" cue that costs
		// no texture read at all.
		vec2 cv = vec2((u + tilt.x * 0.20) / 0.66, (t - 0.74) / 0.22);
		float caustic = (1.0 - smoothstep(0.35, 1.0, length(cv))) * 0.26 * glass;
		rgb = mix(rgb, mix(COLOR.rgb, vec3(1.0), 0.60), clamp(caustic * COLOR.a, 0.0, 1.0));
		// (NO FRESNEL. It was the crystal rig's edge term and it is the one that
		// washed this material out: `rad` is a BOX distance, so it peaks along
		// the top and bottom of every ink box — including mid-stroke, nowhere
		// near an edge — and its lift cancelled almost exactly the
		// darkened(0.28) base the tile ramp had just applied. A tile's bright
		// edge is STAMPED, and so is this word's: the rim and the inner
		// reflection ring in _balloon_body follow the real silhouette, which no
		// per-fragment term here can see.)
	}

	// --- LAYER 5: the diagonal glass streak ------------------------------------
	// The tile's signature mark: the face splits along a soft diagonal running
	// bottom-left -> top-right, the upper-left half reading lighter, with a
	// narrower brighter ridge riding just above the split. CandyFace clips its
	// polygons on `f = x + y`; here that is `u + v`. On near-white bodies a 0.10
	// white overlay vanishes, so the alpha climbs with luminance by exactly the
	// same rule.
	float lum = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	float streak_a = 0.14 + 0.08 * clamp((lum - 0.75) / 0.25, 0.0, 1.0);
	float f = u + v;
	// The lit half plus its falloff band: full strength out to f = -0.34 (the
	// tile's k = 0.34 * hw), fading to nothing by f = +0.34.
	float streak = streak_a * (1.0 - smoothstep(-0.34, 0.34, f));
	// The second, narrower bright band riding just above the diagonal: 0 at
	// f = -0.646 climbing to half strength right at the split, then gone.
	streak += 0.5 * streak_a * smoothstep(-0.646, -0.34, f)
		* (1.0 - smoothstep(-0.35, -0.33, f));
	rgb = mix(rgb, vec3(1.0), clamp(streak * COLOR.a, 0.0, 1.0));

	// --- LAYER 6: the top inner highlight --------------------------------------
	// A white band hugging the inside of the crown, 0.36 -> 0 over a tenth of
	// the body's height. THE fluff cue: a broad lit crown sitting over a dark
	// underside is how an inflated body is painted, and it is the tile's own
	// layer 6 — no soft-body invention required.
	// Broader than the tile's own tenth: a toy's crown light is a wide soft
	// sheet, and a thin bright line reads as a flat chip, not a round body.
	float hl = 0.50 * (1.0 - smoothstep(0.0275, 0.19, t));
	rgb = mix(rgb, vec3(1.0), clamp(hl * COLOR.a, 0.0, 1.0));

	// --- LAYER 7: the bottom inner shade ---------------------------------------
	// The underside sinks deeper and from higher up: the darker belly is the
	// single strongest "this is a thick round object" cue on a black floor.
	float shade = 0.26 * smoothstep(0.70, 0.97, t);
	rgb = mix(rgb, vec3(0.0), clamp(shade * COLOR.a, 0.0, 1.0));

	// --- LAYER 8a: the corner gleam --------------------------------------------
	// The tile tucks a soft bloom into its top-left corner. A digit has no
	// corner, so it rides the upper-left shoulder of the ink box instead, at the
	// same radius and the same pow(1 - d, 1.6) falloff the glow-dot texture has.
	// The gyro slides it, which is what turns a tilt into moving light. (Layer
	// 8b, the hot specular pair seated on the rim, is painted per glyph in
	// _glyph_spec — it has to sit ON the silhouette, which only the script knows.)
	// Tighter and quieter than the tile's own 0.24: a tile is a small flat chip
	// where that bloom lands in an empty corner, and a digit is a big round body
	// where the same bloom lands square on the crown, already lit by layer 6.
	vec2 gv = vec2((u + 0.50 - tilt.x * 0.30) / 0.64,
		(v + 0.50 + tilt.y * 0.16) / 0.64);
	float gleam = pow(clamp(1.0 - length(gv), 0.0, 1.0), 1.6)
		* 0.28 * (1.0 + 0.22 * env_dark);
	rgb = mix(rgb, fire_tint, clamp(gleam * COLOR.a, 0.0, 1.0));
	COLOR = mix(vec4(rgb, COLOR.a), src, step(0.5, form_lit));
}
"""
	return _gloss_shader
## The DEEP-BODY extras: 0 draws the tile material and nothing else, 1 adds the
## whisper of the room seen through the heart of each digit, the refraction that
## bends it, and the Fresnel fire along the silhouette. The digits stay
## essentially OPAQUE either way — this is a thickness cue, not a window (see the
## shader's `glass` uniform). Needs an ancestor BackBufferCopy — AppScreen
## provides one, so any screen built on it gets this for free.
var glass := 0.0:
	set(value):
		glass = value
		if material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_parameter("glass", 0.0 if layers <= 0 else glass)

## Animatable: small offset (px) applied to the whole stack — used for a subtle
## parallax "turn" by shifting the front relative to the depth direction.
## While the word is ANIMATING, _process's idle-throttled cadence owns redraws —
## Home and Sign-in tween this in an endless sway loop, and a direct
## queue_redraw here re-recorded the whole word every tween tick, silently
## defeating the 30 Hz idle throttle. A still word (reduce-motion) has no
## _process running, so there the setter must redraw itself.
var turn := 0.0:
	set(v):
		turn = v
		if not animate:
			queue_redraw()

# --- Living animation (opt-in) --------------------------------------------------
## When on, the wordmark runs three continuous layers of life, all drawn with
## canvas transforms inside _draw (so they never fight Control-scale tweens like
## the Home tap-bounce):
##   • jelly — the whole word squashes/stretches like soft jelly (bottom pivot)
##   • flow  — the palette sweep sloshes back and forth through the digits
##   • stunts — every few seconds ONE random digit does a trick (hop / spin /
##     shiver / squish), so the word reads as four little characters.
## Off by default; Home enables it when reduce-motion is off.
var animate := false:
	set(v):
		animate = v
		if is_inside_tree():
			set_process(v)
		# The refraction shimmer is motion, so it follows this flag into the
		# shader — reduce-motion gets perfectly still glass.
		if material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_parameter("shimmer", 1.0 if v else 0.0)
		queue_redraw()

# The smoothed device tilt driving the shader's parallax light rig. On a phone
# it follows gravity; on desktop it borrows the slow `turn` sway so the effect
# exists (and is testable) everywhere.
var _tilt := Vector2.ZERO
var _tilt_sent := Vector2(INF, INF)   # last tilt pushed to the shader — gates the upload
var _t := 0.0                 # animation clock
var _redraw_acc := 2.0 / 90.0   # idle-throttle accumulator, phase-seeded (see _process)
var _origin0 := Vector2.ZERO  # front-face origin (stunt pivots), set in _draw

## Theme "goods" — a costume id dressing the digits for the active theme:
##   "scarf"   knitted scarves on the icy themes        "crown"  royal gold
##   "leaf"    a perched autumn leaf                    "blush"  kawaii cheeks
##   "bubbles" ocean bubbles drifting up past the word  "star"   a perched star
## Empty = plain. Set by Home from the theme's board style / motif.
var dress := "":
	set(v): dress = v; queue_redraw()
var _base_xf := Transform2D() # the jelly transform, composed under stunt xforms
var _stunt_glyph := -1
var _stunt_kind := 0          # 0 hop · 1 spin · 2 shiver · 3 squish (4 = full dance)
var _stunt_p := 1.0           # stunt progress; >= 1.0 means idle
var _stunt_wait := 2.5        # seconds until the next stunt

# --- Reactions (poked by Home) ---------------------------------------------------
## How far the word cowers (0..1): it shrinks toward its baseline and trembles —
## used while the long-press confetti bomb charges. Tweened from outside.
var cower := 0.0:
	set(v):
		cower = clampf(v, 0.0, 1.0)
		if cower > 0.01:
			_wake_t = _t
		# Tweened from Home for seconds at a time while the confetti bomb
		# charges — like `turn`, a direct per-tick redraw here defeats the idle
		# throttle. The animating word redraws on _process's cadence; only a
		# still word (reduce-motion) needs the setter to redraw for it.
		if not animate:
			queue_redraw()
var _irr_t0 := -10.0          # when the last irritation started (on the _t clock)
var _irr_amp := 0.0           # how annoyed (rapid taps stack this up)
var _dance_t0 := -10.0        # when the last dance started

# Each digit is an INDIVIDUAL — but only in TEMPERAMENT, never in construction.
# The four share ONE master face (see the FACE_* block below); this table holds
# what's left of each one's character: how fast pokes make it mad, its signature
# move, and a WHISPER of resting flavour. `brow` and `smile` are small deltas on
# the master face, not their own face systems — the art-directed unification
# ("same eyes, same mouth, same family") caps them at a few percent.
#   brow  — resting brow delta (+ raised / − lowered), applied at 15% strength
#   smile — resting smile flavour, a few percent of mouth width/openness
#   move  — signature stunt kind when poked (see _stunt_xf)
const PERSONA := [
#   tongue — how far the tongue shows in the resting smile (0 hidden .. 1 out)
#   brow_r — a resting lift of the RIGHT brow only (the cheeky look)
	{"temper": 0.30, "brow": 0.15, "smile": 0.55, "move": 0, "tongue": 0.50, "brow_r": 0.0},   # "2" — playful, confident
	{"temper": 0.10, "brow": 0.40, "smile": 1.00, "move": 1, "tongue": 0.66, "brow_r": 0.0},   # "0" — happy, friendly
	{"temper": 0.55, "brow": -0.05, "smile": 0.35, "move": 2, "tongue": 0.82, "brow_r": 0.30}, # "4" — mischievous, energetic
	{"temper": 0.40, "brow": 0.10, "smile": 1.20, "move": 5, "tongue": 0.60, "brow_r": 0.0},   # "8" — cheerful, lovable
]

## Resting lean per digit (radians) — a posed cast, not four glyphs on a rail.
## Kept SMALL: the family reads through one level face band running across all
## four digits, and a strong lean tips a digit's eye line visibly off that band.
const POSE_TILT := [0.02, 0.0, -0.016, 0.022]

# --- THE MASTER FACE ------------------------------------------------------------
# One character construction shared by every digit — same eyes, same spacing,
# same eye line, same cheeks, same mouth seat — so "2048" reads as four members
# of one character family rather than four unrelated mascots. Only the DIGIT
# SHAPE and a whisper of expression distinguish them. All fractions of
# font_size (divided by the digit's FAMILY_SCALE in animate mode, so the
# features land pixel-identical however big the body stands).
const FACE_EYE_R := 0.116       # master eye half-width — big, full, cute (not huge)
const FACE_EYE_SEP := 0.148     # eye centre offset from the face centre
## The FACE BAND: one shared eye-line height for the whole word — a fraction of
## the tallest glyph's ink height, up from the baseline. Faces used to anchor on
## each glyph's own ink box, which put every face at its own height; the band is
## the horizontal guideline the reference draws through all eight eyes.
const FACE_BAND := 0.615
const FACE_MOUTH_DY := 0.215    # mouth centre below the eye line
const FACE_CHEEK_DY := 0.142    # cheek centre below the eye line
const FACE_CHEEK_DX := 0.205    # cheek centre out from the face centre
## Per-glyph face-centre nudge (fraction of the advance): the 4's visual mass
## leans right of its ink centre (the open notch top-left is air), so its face
## slides a hair toward the stem. Everyone else's ink centre IS their mass.
const FACE_DX := {}
## The one family cheek — a soft rose pad, identical on all four bodies.
const _CHEEK_SOFT := Color(1.0, 0.44, 0.58, 0.19)
const _CHEEK_CORE := Color(1.0, 0.34, 0.50, 0.27)
## Extra balloon dilation per glyph. The 4 is the family's one angular
## silhouette: FreeType's stroker rounds corners with a radius equal to the
## outline width, so a fatter dilation IS the softening — the 4 keeps its
## structure but its corners and junctions turn pillowy like its siblings'.
const PUFF_SOFTEN := {"4": PUFF_SOFTEN_MAX}

func _puff_of(ch: String) -> float:
	return puff * float(PUFF_SOFTEN.get(ch, 1.0))

# --- THE 4's OWN GLYPH ------------------------------------------------------------
# The brand face (Malam Poek) draws a closed, blocky bubble 4 that no amount of
# dilation turns into the reference's open, crossbar 4 — so that ONE digit
# borrows its letterform from Baloo 2 (already shipped for Carnival's
# headings), at a size fitted so its cap height matches the brand digits, on
# the same baseline, in the same paint, sealed and inflated like its siblings.
# Art-directed ("you can use another four like in the reference"). The other
# three stay in the brand face, and `_font` IS still the brand face —
# test_theme_visuals pins that the logo never follows a theme's typography.
const ALT_GLYPH_FONT := "res://assets/fonts/Baloo2-VariableFont_wght.ttf"
const ALT_GLYPHS := {"4": 800}       # char -> wght of the borrowed face
static var _alt_font: Font
var _alt_size := 0                   # the borrowed face's size, fitted per font_size

static func _get_alt_font() -> Font:
	if _alt_font == null and not ALT_GLYPHS.is_empty() and ResourceLoader.exists(ALT_GLYPH_FONT):
		var base := load(ALT_GLYPH_FONT) as FontFile
		if base != null:
			var fv := FontVariation.new()
			fv.base_font = base
			fv.variation_opentype = {"wght": int(ALT_GLYPHS.values()[0])}
			_alt_font = fv
	return _alt_font

## The face and size THIS character draws with. Everything that touches a glyph
## (advances, ink boxes, contours, every stamp) goes through these two, so the
## borrowed 4 is a first-class digit everywhere and not a special case.
func _glyph_font(ch: String) -> Font:
	if ALT_GLYPHS.has(ch):
		var f := _get_alt_font()
		if f != null:
			return f
	return _font

func _glyph_size(ch: String) -> int:
	return _alt_size if (ALT_GLYPHS.has(ch) and _alt_size > 0 and _get_alt_font() != null) else font_size

## Fit the borrowed face: scale it so its "4" stands as tall as the brand "0".
func _fit_alt_size() -> void:
	_alt_size = font_size
	var alt := _get_alt_font()
	if alt == null:
		return
	var hb := _raw_ink_height(_font, font_size, "0")
	var ha := _raw_ink_height(alt, font_size, "4")
	if hb > 0.0 and ha > 0.0:
		_alt_size = maxi(8, int(round(float(font_size) * hb / ha)))

## A glyph's ink height straight from the text server (outline bounds, so it
## needs no rasterised cache).
static func _raw_ink_height(f: Font, size: int, ch: String) -> float:
	if f == null:
		return 0.0
	var rids := f.get_rids()
	if rids.is_empty():
		return 0.0
	var ts := TextServerManager.get_primary_interface()
	var rid: RID = rids[0]
	var gid := ts.font_get_glyph_index(rid, size, ch.unicode_at(0), 0)
	var data: Dictionary = ts.font_get_glyph_contours(rid, size, gid)
	var pts: PackedVector3Array = data.get("points", PackedVector3Array())
	if pts.is_empty():
		return 0.0
	var lo := INF
	var hi := -INF
	for q in pts:
		lo = minf(lo, q.y)
		hi = maxf(hi, q.y)
	return hi - lo

## SEASONAL DRESS: date-driven costume override, layered over the theme-driven
## mapping (screens check this FIRST). Uses only costumes that already exist —
## no new art: deep winter wraps everyone in knitwear, Valentine week blushes
## the cheeks, the spooky nights get the perched star. Returns "" outside the
## festive windows so the theme's own dress applies.
static func seasonal_dress() -> String:
	var d := Time.get_date_dict_from_system()
	var m: int = d["month"]
	var day: int = d["day"]
	if (m == 12 and day >= 20) or (m == 1 and day <= 2):
		return "scarf"
	if m == 2 and day >= 10 and day <= 16:
		return "blush"
	if m == 10 and day >= 29:
		return "star"
	return ""

## Resting gaze — the whole family faces the PLAYER, all eight pupils in the
## same spot with the same catchlights (the sideways per-digit "blocking" this
## replaces made each pair of eyes read as a different design). Every live
## reaction in the priority chain (pointer, pokes, fights…) still overrides it.
const REST_GAZE := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]

## Per-digit "family" sizing: each digit stands at its OWN size, always >= 1.0 —
## the word only ever grows a digit, never shrinks one below the base. Scaled
## around each glyph's baseline (see _draw_face) so the four stand at different
## heights on the same floor, like a little family. Index-matched to "2048".
## Narrow on purpose: the bodies may differ a little, but past ~6% the size
## spread reads as different characters, not one family at different heights.
const FAMILY_SCALE := [1.05, 1.0, 1.03, 1.06]
var _poke_anger: Array[float] = []   # per-digit annoyance; builds per poke, decays
var _poked := -1                     # who was poked last
var _react_t0 := -10.0               # the siblings' reaction window
var _amaze_t0 := -10.0               # wide-eyed wonder (confetti storms, new themes)
var _amaze_dur := 0.0

# Each digit has a MIND of its own: an independent quirk clock. Every few seconds
# a digit privately does its personality's thing — the shy 2 glances around
# nervously, the goofy 0 hops for no reason, the grumpy 4 heaves a big sigh
# (eyes shut, brows down), the chill 8 has a lazy stretch. Unsynchronised, so
# the word never reads as one animation.
const _QUIRK_DUR := 0.8
var _quirk_t0: Array[float] = []     # when each digit's current quirk started
var _quirk_next: Array[float] = []   # when each digit's next quirk fires

# Fights: keep poking an already-angry digit and it BLAMES ITS NEIGHBOUR — the
# two square up and shove each other in an alternating scuffle while the rest
# gawp. Ends on its own; both walk away huffy.
const _BRAWL_DUR := 1.5
var _brawl_t0 := -10.0
var _brawl_a := -1
var _brawl_b := -1

# The social layer: the digits look at the pointer (they see the tap coming),
# hold little glance-conversations with each other, and doze off when ignored.
var _last_mouse := Vector2.ZERO
var _look_until := -10.0      # while _t < this, all eyes follow the pointer
var _talk_t0 := -10.0         # when the current glance-conversation started
var _talk_dur := 1.2
var _talk_wait := 4.0         # seconds until the next conversation
var _talk_a := 0              # the two digits currently talking
var _talk_b := 1
var _wake_t := 0.0            # last interaction — long quiet = sleepy eyes

# --- Interaction sparkle (pokes, petting) + halo dust ---------------------------
## Transient glitter stars: poking a digit bursts a handful from its body, and a
## slow petting stroke sheds them along the finger's path. Each spark flies out,
## decelerates and twinkles away in under a second. Pure decoration — spawned
## only while `animate` (reduce-motion never sees one).
var _sparks: Array[Dictionary] = []
var _pet_spark_t := -10.0
var _emit_next := 0.0        # when the next random star sheds off the word
# FROST BREATH (cold themes only): little fog clouds — a big one after every
# sneeze, a small idle exhale from a random digit now and then. Each puff
# rises, spreads and thins away over ~1.5s.
var _puffs: Array[Dictionary] = []
var _breath_next := 6.0
## Halo dust: for a few seconds after a celebration (amaze — confetti storms,
## fresh themes) a faint ring of micro-sparkles orbits the word like settling
## dust catching the light.
var _halo_t0 := -100.0
var _halo_dur := 0.0

## `speed` scales the fling (1.0 = a poke burst; low values drift), `life` is
## seconds until the spark twinkles out.
func _spawn_sparks(at: Vector2, n: int, spread: float, speed: float = 1.0,
		life: float = 0.9) -> void:
	if not animate:
		return
	var fs := float(font_size)
	for k in n:
		var a := randf() * TAU
		_sparks.append({
			"p": at + Vector2(cos(a), sin(a)) * randf() * spread,
			"v": (Vector2(cos(a), sin(a)) * (fs * (0.12 + randf() * 0.35))
				+ Vector2(0.0, -fs * 0.16)) * speed,
			"t0": _t,
			"life": life,
			"r": fs * (0.016 + randf() * 0.018)})

## The centre of digit `i`'s body in this control's local space (spark origin).
func _glyph_center_local(i: int) -> Vector2:
	var fs := float(font_size)
	var pad := Vector2(fs * 0.12, fs * 0.34)
	var x := pad.x - optical_dx * fs
	for k in mini(i, text.length()):
		x += _advance(text[k]) + _gap()
	var adv := _advance(text[i])
	return Vector2(x + adv * 0.5, pad.y + _font.get_ascent(font_size) - fs * 0.38)

## A happy little dance: the digits hop in sequence, a wave rolling through the word.
func dance() -> void:
	_dance_t0 = _t
	_wake_t = _t
	queue_redraw()

## Poke ONE digit: it performs its persona's signature move (yelp-hop, cartwheel,
## fuming, backflip) and its own anger builds — poke the same digit repeatedly and
## THAT digit gets mad (the grumpy 4 much faster than the goofy 0). The siblings
## get a reaction window: they turn to watch, giggling or unimpressed by temper.
func poke(i: int) -> void:
	if i < 0 or i >= text.length():
		return
	_wake_t = _t
	# Poking a digit that is ALREADY fuming starts a FIGHT: it blames a neighbour
	# and the two scuffle — alternating shoves, gritted teeth — while the others
	# gawp. The brawl replaces the signature move for this poke.
	if i < _poke_anger.size() and _poke_anger[i] >= 0.6 \
			and (_t - _brawl_t0) >= _BRAWL_DUR and text.length() >= 2:
		_brawl_t0 = _t
		_brawl_a = i
		if i == 0:
			_brawl_b = 1
		elif i == text.length() - 1:
			_brawl_b = i - 1
		else:
			_brawl_b = i + (1 if randi() % 2 == 0 else -1)
		# Both walk away from a scuffle huffy.
		_poke_anger[i] = 1.4
		if _brawl_b < _poke_anger.size():
			_poke_anger[_brawl_b] = maxf(_poke_anger[_brawl_b], 0.9)
		_react_t0 = _t
		_poked = i
		queue_redraw()
		return
	if i < _poke_anger.size():
		var temper: float = PERSONA[i % PERSONA.size()]["temper"]
		_poke_anger[i] = clampf(_poke_anger[i] + 0.25 + 0.55 * temper, 0.0, 1.4)
	_poked = i
	_react_t0 = _t
	_stunt_glyph = i
	_stunt_kind = int(PERSONA[i % PERSONA.size()]["move"])
	_stunt_p = 0.0
	# The poke knocks a little burst of glitter off the crystal — with the
	# glass's own tiny chime.
	_spawn_sparks(_glyph_center_local(i), 50, float(font_size) * 0.12)
	AudioManager.play_sfx("crystal_ting", 0.15)
	queue_redraw()

## Progress (0..1) of digit `i`'s current idle quirk, or -1.0 when idle-idle.
func _quirk_p(i: int) -> float:
	if i >= _quirk_t0.size():
		return -1.0
	var q := (_t - _quirk_t0[i]) / _QUIRK_DUR
	return q if (q >= 0.0 and q < 1.0) else -1.0

## Wide-eyed wonder: eyes go big and dart around (mostly upward — following the
## confetti), brows sky-high. Fired for particle storms and fresh themes.
func amaze(dur: float = 2.0) -> void:
	_amaze_t0 = _t
	_amaze_dur = dur
	_wake_t = _t
	# Celebrations kick up HALO DUST: a faint ring of micro-sparkles orbiting
	# the word for a few seconds afterwards, like settling dust catching light.
	_halo_t0 = _t
	_halo_dur = dur + 2.5
	queue_redraw()

# --- Petting, taffy pull + tickle ------------------------------------------------
## A slow stroke across the word is a PET: digits near the finger lean into it,
## close their eyes blissfully and purr (a tiny rapid tremble). Home drives this
## from the wordmark's drag handling. Riding the same stroke:
##   • TAFFY PULL — the digit the stroke grabbed first is dragged sideways,
##     leaning and stretching toward the finger; on release it springs back
##     with a damped wobble and throws off a spray of stars.
##   • TICKLE — a fast back-and-forth scrub (5+ direction flips in ~1.5s) and
##     the whole cast breaks into giggles.
var _petting := false
var _pet_x := 0.0          # finger x in this control's coordinates
var _pull_glyph := -1      # who got grabbed (-1 = nobody)
var _pull_anchor := 0.0    # where the stroke began
var _pull := 0.0           # current sideways pull in px (clamped)
var _spring_v := 0.0       # snap-back spring velocity
var _pet_last_x := 0.0
var _pet_dir := 0
var _tickle_flips := 0
var _tickle_t0 := -10.0
var _giggle_t0 := -10.0

func set_petting(on: bool, x: float = 0.0) -> void:
	var fs := float(font_size)
	if on:
		_wake_t = _t
		if not _petting:
			_pull_glyph = glyph_at(Vector2(x, 0.0))
			_pull_anchor = x
			_pet_last_x = x
			_pet_dir = 0
			_tickle_flips = 0
			_tickle_t0 = _t
		else:
			var dx := x - _pet_last_x
			if absf(dx) > 3.0:
				var d := 1 if dx > 0.0 else -1
				if _pet_dir != 0 and d != _pet_dir:
					if _t - _tickle_t0 > 1.5:
						_tickle_flips = 0
						_tickle_t0 = _t
					_tickle_flips += 1
					if _tickle_flips >= 5:
						_tickle_flips = 0
						_giggle_t0 = _t
				_pet_dir = d
				_pet_last_x = x
		if _pull_glyph >= 0:
			_pull = clampf(x - _pull_anchor, -fs * 0.30, fs * 0.30)
	elif _petting:
		# Release: the taffy snaps back (the spring runs in _process) and a
		# real pull throws off stars as it lets go.
		if _pull_glyph >= 0 and absf(_pull) > fs * 0.06:
			_spawn_sparks(_glyph_center_local(_pull_glyph), 20, fs * 0.10)
			AudioManager.play_sfx("crystal_ting", 0.2)
		_spring_v = 0.0
	_petting = on
	_pet_x = x
	queue_redraw()

## The MORNING GREETING: the cast wakes with the player — instantly sleepy
## (droopy lids, slow yawns, the doze they normally earn after 25 quiet
## seconds), then startles awake and rolls into a little dance. Fired by Home
## on the session's first morning visit.
func morning() -> void:
	_wake_t = _t - 26.0
	_look_until = -10.0
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_callback(func():
		amaze(1.6)
		dance())

# --- Ducking -------------------------------------------------------------------
## A background tile just got FLUNG at the word: everyone flinches — a quick
## shrink-flinch with wide eyes tracking the incoming tile. Throttled so a
## ricocheting tile doesn't strobe the cast.
var _duck_t0 := -10.0
var _duck_from := 0.0      # the tile's x in this control's coordinates

func duck(from_local_x: float) -> void:
	if _t - _duck_t0 < 0.9:
		return
	_duck_t0 = _t
	_duck_from = from_local_x
	_wake_t = _t
	queue_redraw()

## Which digit sits under `local_pos` (this control's coordinates), or -1.
func glyph_at(local_pos: Vector2) -> int:
	if _font == null:
		return -1
	# The draw pad, minus the same optical-centering shift the draw origin takes.
	var x := local_pos.x - font_size * (0.12 - optical_dx)
	if x < 0.0:
		return -1
	var acc := 0.0
	for i in text.length():
		var adv := _advance(text[i])
		if x <= acc + adv:
			return i
		acc += adv + _gap()
	return -1

## An annoyed reaction: a fast angry shudder (with a grumpy hunker) that decays.
## `level` scales both the violence and how long the huff lasts.
func irritate(level: float = 1.0) -> void:
	_irr_t0 = _t
	_irr_amp = clampf(level, 0.3, 2.0)
	_wake_t = _t
	queue_redraw()
## Optional multi-stop colour sweep. When it holds 2+ colours the glyph gradient
## samples across all of them (one hue flows into the next across "2048"),
## overriding c0/c1/c2. Used to make the wordmark carry the whole theme palette.
var palette_colors: PackedColorArray = PackedColorArray():
	set(v):
		palette_colors = v
		queue_redraw()

## Exact per-glyph colours (index-matched to `text`). When the length matches it
## overrides the gradient AND the flow entirely — used to dress each digit in a
## specific board tile colour so the word matches the tiles exactly.
var glyph_colors: PackedColorArray = PackedColorArray():
	set(v):
		glyph_colors = v
		_lit_cache.clear()
		queue_redraw()
		if _ground != null:
			_ground.queue_redraw()

static func make(txt: String, size: int, a: Color, b: Color, d: Color) -> ExtrudedWord:
	var w := ExtrudedWord.new()
	w.text = txt
	w.font_size = size
	w.c0 = a
	w.c1 = b
	w.c2 = d
	return w

func _ready() -> void:
	# The wordmark keeps the Malam Poek brand face: its chunky, FILLED bubble glyphs
	# read as the inflated balloons the reference wants. (A thinner geometric font
	# renders as wispy outlines under the glass finish.) Colours stay per-theme.
	# brand_font by name: every font slot is sealed now (no theme changes any
	# typeface), and the logo reads its own named slot so that stays explicit —
	# test_theme_visuals pins that the wordmark draws in the brand face.
	_font = ThemeManager.brand_font
	if _font == null:
		_font = ThemeManager.display_font
	_poke_anger.resize(text.length())
	_poke_anger.fill(0.0)
	# Every digit's private quirk clock starts out of phase, so their little
	# habits never sync up into one choreographed motion.
	_quirk_t0.resize(text.length())
	_quirk_t0.fill(-10.0)
	_quirk_next.resize(text.length())
	for k in _quirk_next.size():
		_quirk_next[k] = randf_range(3.0, 9.0)
	var m := ShaderMaterial.new()
	# Lite path: refract the reduced-res backdrop target instead of the live
	# screen — with no hint_screen_texture user left, the engine never copies
	# the framebuffer for this word at all. Falls back to the screen-reading
	# program when no AppScreen backdrop exists (desktop, bare probes).
	var backdrop := _find_backdrop()
	if backdrop != null:
		m.shader = _get_gloss_shader(true)
		m.set_shader_parameter("screen_tex", backdrop)
	else:
		# Debug tripwire: on the lite path this fallback silently reinstates the
		# framebuffer copy + tiler flush the backdrop target exists to remove.
		if OS.is_debug_build() and AppScreen.lite_gpu():
			push_warning("ExtrudedWord: no AppScreen backdrop above %s — screen-reading gloss shader on the lite path" % get_path())
		m.shader = _get_gloss_shader()
	material = m
	# `glass` is normally set before the node enters the tree, when there is no
	# material yet for its setter to push to — so replay it here.
	m.set_shader_parameter("glass", 0.0 if layers <= 0 else glass)
	var bg: Color = ThemeManager.color("bg0")
	_env_dark = clampf((0.55 - bg.get_luminance()) * 2.2, 0.0, 1.0)
	m.set_shader_parameter("env_dark", _env_dark)
	# The themed key light (see _fire): 0.40 keeps it a LEAN, not a paint job —
	# the fire must still read as light, and the word's legibility rides on the
	# whites staying near-white.
	var acc: Color = ThemeManager.board_accent()
	_fire = Color(1, 1, 1).lerp(Color(acc.r, acc.g, acc.b, 1.0), 0.40 * acc.a)
	m.set_shader_parameter("fire_tint", Vector3(_fire.r, _fire.g, _fire.b))
	m.set_shader_parameter("shimmer", 1.0 if animate else 0.0)
	# (There is no `lite` uniform any more. It gated the chromatic-dispersion
	# taps and the mirrored-scene fetch — three of the four dependent screen
	# reads — and both went with the crystal look they existed to sell, leaving
	# ONE tap on every tier. The lite SHADER VARIANT above is untouched and is
	# still what matters on device: swapping hint_screen_texture for a plain
	# sampler is what stops the engine copying the framebuffer for this word.)
	_rebuild_ground()
	set_process(animate)
	_remeasure()

## The lite backdrop source, if an AppScreen ancestor provides one (see
## AppScreen.backdrop_texture / GlassPanel._find_backdrop — same contract).
func _find_backdrop() -> Texture2D:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("backdrop_texture"):
			var tex: Variant = n.call("backdrop_texture")
			if tex is Texture2D:
				return tex
		n = n.get_parent()
	return null

func _process(delta: float) -> void:
	_t += delta
	# GYRO PARALLAX: smooth the device tilt into the shader. A phone reports
	# real gravity; on desktop (gravity reads zero) the slow turn sway stands
	# in, so the light rig never sits perfectly dead anywhere.
	var grav := Input.get_gravity()
	var want := Vector2(turn / 6.0 * 0.35, 0.0)
	if grav.length() > 2.0:
		want = Vector2(clampf(grav.x / 9.8, -1.0, 1.0),
			clampf(-grav.z / 9.8, -1.0, 1.0) * 0.6)
	_tilt = _tilt.lerp(want, 1.0 - pow(0.05, delta))
	# Upload only on real change: once the lerp converges (desktop always, phone
	# whenever the device rests) this was still a RenderingServer round-trip
	# every single frame.
	if material is ShaderMaterial and _tilt.distance_squared_to(_tilt_sent) > 0.0000004:
		_tilt_sent = _tilt
		(material as ShaderMaterial).set_shader_parameter("tilt", _tilt)
	# The taffy spring: after release the pulled digit oscillates home.
	if not _petting and _pull_glyph >= 0:
		_spring_v += -_pull * 140.0 * delta
		_spring_v *= pow(0.006, delta)
		_pull += _spring_v * delta
		if absf(_pull) < 0.4 and absf(_spring_v) < 2.0:
			_pull = 0.0
			_pull_glyph = -1
	# Grudges fade: each digit's own poke-anger cools on its own.
	for k in _poke_anger.size():
		if _poke_anger[k] > 0.0:
			_poke_anger[k] = maxf(_poke_anger[k] - delta * 0.35, 0.0)
	# Each digit's private mind: fire its next quirk when its own clock says so
	# (never mid-stunt or mid-brawl — real reactions outrank idle habits).
	for k in _quirk_next.size():
		if _t >= _quirk_next[k]:
			var busy: bool = (k == _stunt_glyph and _stunt_p < 1.0) \
				or ((_t - _brawl_t0) < _BRAWL_DUR and (k == _brawl_a or k == _brawl_b))
			if not busy:
				_quirk_t0[k] = _t
			_quirk_next[k] = _t + randf_range(6.0, 12.0)
	if _stunt_p < 1.0:
		var prev_p := _stunt_p
		_stunt_p = minf(_stunt_p + delta / 0.65, 1.0)   # a stunt lasts ~0.65s
		# The ACHOO: right at the snap of a sneeze the digit sprays a burst of
		# stars — crystal dust knocked loose — that scatters and twinkles out.
		if _stunt_kind == 6 and _stunt_glyph >= 0 and prev_p < 0.45 and _stunt_p >= 0.45:
			var fss := float(font_size)
			_spawn_sparks(_glyph_center_local(_stunt_glyph) + Vector2(0.0, fss * 0.10),
				60, fss * 0.08, 0.8, 1.3)
			AudioManager.play_sfx("sneeze", 0.08)
			# On the cold themes the achoo condenses: a proper fog puff blooms
			# in front of the sneezer and drifts away.
			if dress == "scarf":
				_puffs.append({"p": _glyph_center_local(_stunt_glyph)
					+ Vector2(fss * 0.04, fss * 0.16), "t0": _t, "big": true})
	else:
		_stunt_wait -= delta
		if _stunt_wait <= 0.0:
			# Weighted picker: mostly the small solo tricks, sometimes a group
			# dance, rarely a sneeze chain or the 0 rolling away down the baseline.
			var roll := randi() % 12
			# On the COLD themes (the scarf-wearing icy set) and at NIGHT (dark
			# backdrops) the cast catches the sniffles: a good share of ordinary
			# rolls turn into an achoo — which also sprays stars (see the burst
			# in the stunt clock above). Warm daylight themes keep sneezes rare.
			if (dress == "scarf" or _env_dark > 0.5) and roll < 8 and randi() % 3 == 0:
				roll = 10
			if roll < 8:
				_stunt_kind = roll % 4
				_stunt_glyph = randi() % maxi(text.length(), 1)
			elif roll < 10:
				_stunt_kind = 4
				_stunt_glyph = -1
				dance()
			elif roll == 10:
				_stunt_kind = 6   # sneeze — knocks the neighbours sideways
				_stunt_glyph = randi() % maxi(text.length(), 1)
			else:
				var zero := text.find("0")
				if zero >= 0:
					_stunt_kind = 7   # the 0 rolls away and comes back
					_stunt_glyph = zero
				else:
					_stunt_kind = 4
					_stunt_glyph = -1
					dance()
			_stunt_p = 0.0
			_stunt_wait = randf_range(3.5, 6.5)
	# Interaction/emission sparks fly, decelerate and twinkle out.
	if not _sparks.is_empty():
		var alive: Array[Dictionary] = []
		for s in _sparks:
			s["p"] = (s["p"] as Vector2) + (s["v"] as Vector2) * delta
			s["v"] = (s["v"] as Vector2) * pow(0.10, delta)
			if _t - float(s["t0"]) < float(s.get("life", 0.9)):
				alive.append(s)
		_sparks = alive
	# Random emissions: every couple of seconds the crystal sheds one star from
	# a random spot on a random digit; it drifts gently away and fades — slower
	# and longer-lived than a poke burst.
	# The idle star shed is a prism-mode twinkle: on the form-lit body it reads
	# as a painted white dot (art-directed: no random dots on the material).
	if layers > 0 and _t >= _emit_next:
		_emit_next = _t + randf_range(0.8, 1.8)
		var fse := float(font_size)
		_spawn_sparks(_glyph_center_local(randi() % maxi(text.length(), 1))
			+ Vector2(randf_range(-fse * 0.28, fse * 0.28), randf_range(-fse * 0.30, fse * 0.22)),
			6, fse * 0.09, 0.35, 1.8)
	# Frost breath: cull spent puffs, and on the cold themes let a random digit
	# exhale a small visible breath every so often.
	if not _puffs.is_empty():
		var live: Array[Dictionary] = []
		for pf in _puffs:
			if _t - float(pf["t0"]) < 1.5:
				live.append(pf)
		_puffs = live
	if dress == "scarf" and _t >= _breath_next:
		_breath_next = _t + randf_range(7.0, 14.0)
		_puffs.append({"p": _glyph_center_local(randi() % maxi(text.length(), 1))
			+ Vector2(float(font_size) * 0.03, float(font_size) * 0.15),
			"t0": _t, "big": false})
	# A slow petting stroke sheds glitter along the finger's path.
	if _petting and _t - _pet_spark_t > 0.07:
		_pet_spark_t = _t
		var fs := float(font_size)
		_spawn_sparks(Vector2(_pet_x + randf_range(-fs * 0.10, fs * 0.10),
			fs * 0.34 + _font.get_ascent(font_size) - fs * 0.50), 5, fs * 0.08)
	# Pointer awareness: whenever the finger/cursor moves or lands, every digit
	# turns to look at it for a couple of seconds — they see the tap coming.
	var mp := get_local_mouse_position()
	if mp.distance_to(_last_mouse) > 6.0:
		_last_mouse = mp
		_look_until = _t + 2.2
		_wake_t = _t
	# Glance-conversations: every few seconds two digits catch each other's eye
	# and hold it for a moment (the partner raises a sceptical brow).
	if _t - _talk_t0 >= _talk_dur and text.length() >= 2:
		_talk_wait -= delta
		if _talk_wait <= 0.0:
			_talk_a = randi() % text.length()
			_talk_b = (_talk_a + 1 + randi() % (text.length() - 1)) % text.length()
			_talk_t0 = _t
			_talk_dur = randf_range(0.9, 1.7)
			_talk_wait = randf_range(3.5, 7.5)
	# IDLE THROTTLE: re-recording the whole word (faces, rims, glints, the glitter
	# field, the ground reflection) is the most expensive single draw on the menu
	# screens. At rest every motion here is slow ambience — breath, twinkle — so a
	# 30 Hz redraw is visually identical and halves the cost. Anything FAST (a
	# stunt, a dance, a poke spring, petting, sparks in flight) gets the full frame
	# rate back instantly via _lively().
	_redraw_acc += delta
	if _lively() or _redraw_acc >= 1.0 / 30.0:
		# fmod, not zero: the seed keeps this 30 Hz tick a third of a period off
		# Home's toy step and the sky ticker, so the three heavy ticks never
		# share a frame — a hard reset would let them drift back into sync.
		_redraw_acc = fmod(_redraw_acc, 1.0 / 30.0)
		queue_redraw()

## True while any fast reaction/effect is playing — those need per-frame redraws;
## everything else ambles slowly enough for the 30 Hz idle cadence.
func _lively() -> bool:
	return _stunt_p < 1.0 \
		or (_t - _dance_t0) < 0.8 \
		or (_t - _brawl_t0) < _BRAWL_DUR \
		or (_t - _irr_t0) < 1.1 \
		or (_t - _duck_t0) < 0.6 \
		or (_t - _react_t0) < 0.9 \
		or (_t - _giggle_t0) < 1.2 \
		or (_t - _amaze_t0) < _amaze_dur \
		or _petting or _pull_glyph >= 0
	# Deliberately NOT here:
	#  • _sparks — the idle crystal sheds slow-drifting stars every couple of
	#    seconds, which kept this true ~90% of the time and silently disabled
	#    the throttle; the fast spark moments (pokes, petting, releases) are
	#    already covered by the reaction windows above.
	#  • the glitter field — every mote holds its place and only twinkles, which
	#    is exactly the slow ambience the 30 Hz cadence was sized for.
	#  • cower — held for the SECONDS the confetti bomb charges: a slow shrink
	#    plus a nervous tremble, both of which read fine on the 30 Hz cadence,
	#    while the charge fills the screen with its own full-rate swirl. Keeping
	#    it here made the whole hold phase pay the word's full-rate bill.

## Extra horizontal air between glyphs (px). The chunky display font packs its
## digits nearly touching; a small positive spacing lets the candy characters
## stand shoulder-to-shoulder instead of overlapping.
var letter_spacing: float = 0.0:
	set(v): letter_spacing = v; _remeasure()

## The real horizontal step added between glyphs: the author's letter_spacing plus
## the air the inflation eats. Blowing the digits up fattens each one by `puff` on
## every side, so without this the balloons would swallow their neighbours; with
## it they stand shoulder-to-shoulder, just kissing.
func _gap() -> float:
	# Booked off the fattest dilation in the word, not the base puff: the gaps
	# are uniform, and one over-inflated digit (the 4) must not swallow its
	# neighbour's air.
	var soft := 1.0
	for k in text.length():
		soft = maxf(soft, float(PUFF_SOFTEN.get(text[k], 1.0)))
	return letter_spacing + float(font_size) * (puff * soft + RIM_FRAC) * 1.5

## Per-character advance, cached. Font.get_string_size shapes the string through
## the TextServer on EVERY call, and the living word asks for the same four
## digits' advances dozens of times per redraw (faces, ground, hit tests).
## Cleared with the ink cache whenever the font size changes.
var _adv_cache: Dictionary = {}

func _advance(ch: String) -> float:
	var v: float = _adv_cache.get(ch, -1.0)
	if v < 0.0:
		v = _glyph_font(ch).get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _glyph_size(ch)).x
		_adv_cache[ch] = v
	return v

func _remeasure() -> void:
	if _font == null:
		return
	_ink_cache.clear()          # ink boxes are per font_size
	_adv_cache.clear()          # advances are per font_size too
	_seal_cache.clear()         # contours are per font_size as well
	_offset_cache.clear()
	_mesh_cache.clear()         # the triangulations ride the contours
	_lit_cache.clear()
	_fit_alt_size()             # the borrowed 4 refits to the new size first
	# Glyph by glyph: the digits no longer share one face, so the string measure
	# is the sum of each character's own advance (plus the gaps) and the tallest
	# character's height.
	_measure = Vector2.ZERO
	for k in text.length():
		var chk := text[k]
		_measure.x += _advance(chk)
		_measure.y = maxf(_measure.y,
			_glyph_font(chk).get_string_size(chk, HORIZONTAL_ALIGNMENT_LEFT, -1, _glyph_size(chk)).y)
	_measure.x += _gap() * float(maxi(text.length() - 1, 0))
	# Reserve room for the extrusion tail + a little breathing space for glyph
	# ascenders/descenders the advance-width measure doesn't include.
	var pad := Vector2(font_size * 0.12, font_size * 0.34)
	custom_minimum_size = _measure + extrude * float(layers) + pad * 2.0
	if layers <= 0:
		# Flat mode (Home's candy digits): the box ends just under the baseline —
		# the digits are sealed blobs sitting ON the baseline, and there is no
		# floor beneath them any more (the reflection pool was art-directed out,
		# with the empty band it reserved before the tagline). Only the balloon
		# inflation and the fattest digit's dilation need air below.
		custom_minimum_size.y = pad.y + _font.get_ascent(font_size) \
			+ float(font_size) * (SILHOUETTE_FRAC + 0.05)
		if floor_reflection:
			custom_minimum_size.y += float(font_size) * 0.26   # the pool's band
	if _ground != null:
		_ground.queue_redraw()
	# Tell the glass shader where the glyphs actually live, so the crown light and
	# the base shade land on the numbers rather than the padding, and the diagonal
	# streak runs across each digit rather than across the whole word.
	_sync_glyph_boxes(pad)
	queue_redraw()

## Push the per-digit horizontal bounds the glass streak rides on: one
## (centre_x, half_width) per glyph, in the same item space the shader reads from
## VERTEX. The half-extent is widened by the inflation because the balloon is
## fatter than its advance box — measured off the advance alone, the streak's
## transition lands inside the digit's silhouette instead of on its edge.
func _sync_glyph_boxes(pad: Vector2) -> void:
	if not (material is ShaderMaterial) or _font == null:
		return
	var sm := material as ShaderMaterial
	sm.set_shader_parameter("y_top", pad.y)
	sm.set_shader_parameter("y_bot", pad.y + _measure.y)
	var boxes := PackedVector2Array()
	var yboxes := PackedVector2Array()
	var fs := float(font_size)
	var asc := _font.get_ascent(font_size)
	var gx := pad.x - optical_dx * fs
	for i in mini(text.length(), 8):     # the shader's array is 8 long
		var adv := _advance(text[i])
		boxes.append(Vector2(gx + adv * 0.5, adv * 0.5 + fs * (_puff_of(text[i]) + RIM_FRAC)))
		# The glyph's REAL vertical body: its ink box (baseline-relative, y up as
		# negative), inflated by the puff — so the shader's glaze/wet/shade land on
		# the blob itself, not on the em box's ascent padding.
		var ink := _ink_rect(text[i])
		var infl := fs * (_puff_of(text[i]) + RIM_FRAC)
		yboxes.append(Vector2(pad.y + asc + ink.position.y - infl,
			ink.size.y + infl * 2.0))
		gx += adv + _gap()
	sm.set_shader_parameter("glyph_box", boxes)
	sm.set_shader_parameter("glyph_ybox", yboxes)
	sm.set_shader_parameter("glyph_count", boxes.size())
	sm.set_shader_parameter("form_lit", 1.0 if (layers <= 0 and MATERIAL_FORM_LIT) else 0.0)
	# A tile is opaque: in flat mode the transmission/refraction term stays off
	# whatever `glass` a screen asked for (the crystal-era translucency).
	sm.set_shader_parameter("glass", 0.0 if layers <= 0 else glass)
	_synced_inks = _ink_cache.size()

## Optical centering: the display font packs its glyph INK right-of-centre in
## the advance boxes, so the drawn word sits visibly right of its layout box.
## The draw origin shifts left by this fraction of font_size to centre the ink
## (calibrated on 400x866 probe shots: margin diff responds ~2px per 0.01,
## crossing zero at 0.05).
@export var optical_dx := 0.05

## PERF_TRACE=1 developer probe (gameplay.gd's pattern, resolved once at class
## load): accumulates wall time per pass of _draw and prints the split every 120
## redraws, so a slow wordmark names the pass that costs it. Off, it is one
## static bool read per section.
static var _PERF_TRACE: bool = OS.get_environment("PERF_TRACE") == "1"
var _tr_acc: Dictionary = {}
var _tr_draws := 0

func _tr(key: String, t0: int) -> int:
	var now := Time.get_ticks_usec()
	_tr_acc[key] = int(_tr_acc.get(key, 0)) + (now - t0)
	return now

func _tr_report() -> void:
	_tr_draws += 1
	if _tr_draws % 120 != 0:
		return
	var keys := _tr_acc.keys()
	keys.sort_custom(func(a, b): return int(_tr_acc[a]) > int(_tr_acc[b]))
	var total := 0
	for k in keys:
		total += int(_tr_acc[k])
	var line := "WORD TRACE per draw (%d draws, %.2fms total):" % [_tr_draws, float(total) / 120.0 / 1000.0]
	for k in keys:
		line += " %s=%.2fms" % [k, float(_tr_acc[k]) / 120.0 / 1000.0]
	print(line)
	_tr_acc.clear()

func _draw() -> void:
	if _font == null:
		return
	var trace := _PERF_TRACE
	var t0 := Time.get_ticks_usec() if trace else 0
	# Baseline-anchored origin, padded, with the extrusion tail kept inside the box.
	var pad := Vector2(font_size * 0.12, font_size * 0.34)
	var origin := pad + Vector2(-optical_dx * font_size, _font.get_ascent(font_size))
	_origin0 = origin

	# Jelly + reactions: the whole word squashes/stretches around a bottom-centre
	# pivot, shrinks when cowering, and shudders when irritated — all one canvas
	# transform, so it composes under the stunts and never touches the Control's
	# own scale (which the Home tap-bounce tweens).
	_base_xf = Transform2D()
	if animate:
		# Soft-body language, and now WANTED: these are inflated digits, not a
		# sculpture. Two out-of-phase swells so the squash never reads as a
		# metronome. (The crystal build ran this at 0.007/0.004 — a rigid piece
		# holds its shape, which is exactly the stiffness being undone here.)
		var sq := sin(_t * 1.9) * 0.016 + sin(_t * 1.1 + 1.7) * 0.009
		# Irritation: a fast horizontal shudder + a grumpy hunker, decaying away.
		var irr_dur := 0.5 + 0.25 * _irr_amp
		var irr_age := _t - _irr_t0
		var irr_k := 0.0
		if irr_age >= 0.0 and irr_age < irr_dur:
			irr_k = (1.0 - irr_age / irr_dur) * _irr_amp
		var jitter := Vector2(sin(_t * 70.0) * font_size * 0.035 * irr_k, 0.0)
		# Cowering: shrink toward the baseline with a nervous tremble.
		if cower > 0.01:
			jitter += Vector2(sin(_t * 41.0), cos(_t * 37.0)) * font_size * 0.008 * cower
		# The gentle float: the whole sculpture drifts a few px on a slow swell —
		# the "hovering product shot" cue, far below the threshold of bounce.
		jitter += Vector2(0.0, sin(_t * 0.45) * font_size * 0.006)
		# Ducking a flung tile: a quick flinch-shrink that recovers on its own.
		var duck_age := _t - _duck_t0
		var duck_env := 0.0
		if duck_age >= 0.0 and duck_age < 0.55:
			duck_env = sin(PI * duck_age / 0.55)
		var shrink := 1.0 - 0.18 * cower - 0.09 * duck_env
		# The breathing swell: the word fills with air and lets it out again, on
		# a clock slow enough to feel like breath rather than a pulse.
		var breath := 1.0 + 0.011 * sin(_t * 0.7)
		shrink *= breath
		var sc := Vector2((1.0 + sq + 0.05 * irr_k) * shrink,
			(1.0 - sq - 0.06 * irr_k) * shrink)
		var pivot := Vector2(_measure.x * 0.5 + pad.x, _measure.y + pad.y)
		_base_xf = Transform2D(0.0, sc, 0.0, pivot - pivot * sc + jitter)
	draw_set_transform_matrix(_base_xf)

	# The glitter field's BACK half draws UNDER the glyph stack: those motes sit
	# behind the crystal, so the word occludes them and the field reads as depth.
	if animate and layers > 0:
		_draw_glitter_field(pad, false)
	if trace:
		t0 = _tr("glitter_back", t0)

	if layers > 0:
		# Back-to-front extrusion body. Each wall copy still carries the brand sweep
		# (so the sides glow violet→pink→orange) but darkened with depth, so the form
		# reads as a coloured solid rather than a flat drop shadow.
		for i in range(layers, 0, -1):
			var f := float(i) / float(layers)          # 1 = deepest, ~0 = near front
			var off := extrude * float(i) + Vector2(turn * f, 0.0)
			_draw_face(origin + off, 0.28 + 0.34 * (1.0 - f))
	else:
		# Flat mode (layers = 0): no long 3D prism — but not a flat sticker either.
		# A coloured bloom + halo in each digit's own hue, then THE UNDERSIDE: a
		# short stack of darkened copies stepped down-right, so every digit has a
		# front face, a rounded bevel (the rim ring), a dark side and a belly it
		# stands on. Three steps is thickness; fifteen is the loading screen's prism.
		_draw_face(origin + Vector2(font_size * 0.045, font_size * 0.075), 0.9, true)
		if trace:
			t0 = _tr("shadow", t0)
		for k in [4, 3, 2, 1]:
			_draw_face(origin + Vector2(font_size * 0.005 * float(k), font_size * 0.015 * float(k)),
				0.40 + 0.06 * float(4 - k))
	if trace:
		t0 = _tr("walls/belly", t0)

	# Bright gradient front face on top.
	_draw_face(origin + Vector2(turn, 0.0), 1.0)
	if trace:
		t0 = _tr("front", t0)

	# Word-level theme goods (bubbles / perched star) ride the jelly transform.
	if animate:
		_draw_extras()
		if trace:
			t0 = _tr("extras", t0)
		# The glitter field's FRONT half: the motes scattered over the face of the
		# word (the back half went under the glyphs).
		if layers > 0:
			_draw_glitter_field(pad, true)
		if trace:
			t0 = _tr("glitter_front", t0)
		# Interaction sparks (pokes, petting) and post-celebration halo dust.
		_draw_sparks()
		if layers > 0:
			_draw_halo_dust(pad)
		# Frost breath drifting off the cold cast.
		_draw_puffs()
		if trace:
			t0 = _tr("sparks/halo/puffs", t0)

	# Zzz — while the word sleeps, little z's drift up from its shoulder.
	if animate and (_t - _wake_t) > 25.0 and _t >= _look_until:
		var zbase := Vector2(pad.x + _measure.x * 0.96, pad.y + font_size * 0.10)
		for k in 3:
			var ph := fposmod(_t * 0.4 + float(k) * 0.33, 1.0)
			var zp := zbase + Vector2(font_size * (0.06 + 0.10 * float(k)) + ph * font_size * 0.22,
				-ph * font_size * 0.5)
			var za := sin(ph * PI) * 0.55
			var zs := int(font_size * (0.13 + 0.035 * float(k)))
			_font.draw_string(get_canvas_item(), zp, "z", HORIZONTAL_ALIGNMENT_LEFT, -1,
				zs, Color(0.13, 0.13, 0.16, za))
	draw_set_transform_matrix(Transform2D())
	if _ground != null:
		_ground.transform = _base_xf
	# Glyphs rasterise on their first draw — once the ink cache has grown past what
	# the shader was synced from, re-push the REAL per-digit ink boxes so the
	# glaze/wet/shade land on the actual blobs instead of the estimates.
	if _ink_cache.size() != _synced_inks:
		_sync_glyph_boxes(pad)
	if trace:
		_tr("zzz/sync", t0)
		_tr_report()
## Draws the word glyph-by-glyph, tinting each glyph by its horizontal position
## so the three-stop gradient flows across the whole word, then scaling the
## brightness (1.0 = front face, <1.0 = a darker extrusion wall). `shadow` stamps
## the pass as a soft halo in the glyph's own hue instead (the flat mode's
## ground — the spec's ambient bloom rather than a grey drop shadow).
func _draw_face(origin: Vector2, bright: float, shadow: bool = false) -> void:
	var x := 0.0
	var total: float = maxf(_measure.x, 1.0)
	for i in text.length():
		var ch := text[i]
		var adv := _advance(ch)
		var f: float = clampf((x + adv * 0.5) / total, 0.0, 1.0)
		var col: Color = glyph_colors[i] if glyph_colors.size() == text.length() else _grad(f)
		if shadow:
			# The ambient halo behind the digit: a soft bloom of its own hue lifted
			# toward white. ONLY the soft bloom — this pass used to stamp an offset
			# copy of the glyph too, which showed through the counters as a pale
			# ghost crescent inside the 0's eye on light themes.
			# The tile's LAYER 1, at the tile's own numbers: the hue lifted 35%
			# toward white at alpha 0.30. Kept TIGHT — a wide halo fogs the
			# silhouette into a pale backdrop, where the tiles' bloom hugs the
			# shape it belongs to.
			var halo := col.lerp(Color(1, 1, 1), 0.35)
			var bcx := origin.x + x + adv * 0.5
			var bcy := origin.y - font_size * 0.34
			var bw := adv * 1.3
			var bh := font_size * 1.3
			draw_texture_rect(CandyFace.glow_dot(),
				Rect2(bcx - bw * 0.5, bcy - bh * 0.5, bw, bh), false,
				Color(halo.r, halo.g, halo.b, 0.30))
			x += adv + _gap()
			continue
		if bright < 1.0:
			col = col.darkened(1.0 - bright)
		# Dance: a hop-wave rolling left→right through the digits (pure translation,
		# identical in every layer pass, so each digit's 3D prism hops as one solid).
		var pos := origin + Vector2(x, 0.0)
		if animate:
			var d := (_t - _dance_t0) - float(i) * 0.09
			if d >= 0.0 and d <= 0.38:
				pos.y -= font_size * 0.20 * sin(PI * d / 0.38)
			# Every digit is a character: it rides its own idle body-language
			# transform (plus its stunt, when it's the stunt digit), composed under
			# the jelly. The pivot is the FRONT face's glyph centre for every layer,
			# so the whole 3D prism moves rigidly instead of shearing apart.
			var pivot := _origin0 + Vector2(x + adv * 0.5, -font_size * 0.30)
			draw_set_transform_matrix(_base_xf * _glyph_xf(i, pivot))
			var trace := _PERF_TRACE and bright >= 1.0
			var t0 := Time.get_ticks_usec() if trace else 0
			if bright >= 1.0:
				_balloon_body(pos, ch, col)
			else:
				_puff_stamp(pos, ch, col)
			if trace:
				t0 = _tr("f.balloon", t0)
			# The form-lit balloon (flat mode) already IS the whole front body,
			# shaded vertex by vertex; a flat fill on top would erase the light.
			if not (bright >= 1.0 and layers <= 0 and MATERIAL_FORM_LIT):
				_glyph_font(ch).draw_string(get_canvas_item(), pos, ch,
					HORIZONTAL_ALIGNMENT_LEFT, -1, _glyph_size(ch), col)
				_stamp_seal(self, pos, ch, col)
			if trace:
				t0 = _tr("f.string+seal", t0)
			if bright >= 1.0:
				_glyph_spec(pos, adv, ch, col)
				# Flush the rim glints while THIS glyph's transform is still
				# active — the queued rects are in its local space.
				_flush_glints()
				if trace:
					t0 = _tr("f.spec", t0)
				_draw_eyes(i, _face_anchor(pos, ch), adv, col)
				if trace:
					t0 = _tr("f.eyes", t0)
				_draw_dress(i, pos, adv)
				if trace:
					t0 = _tr("f.dress", t0)
			draw_set_transform_matrix(_base_xf)
		else:
			if bright >= 1.0:
				_balloon_body(pos, ch, col)
			else:
				_puff_stamp(pos, ch, col)
			# The form-lit balloon (flat mode) already IS the whole front body,
			# shaded vertex by vertex; a flat fill on top would erase the light.
			if not (bright >= 1.0 and layers <= 0 and MATERIAL_FORM_LIT):
				_glyph_font(ch).draw_string(get_canvas_item(), pos, ch,
					HORIZONTAL_ALIGNMENT_LEFT, -1, _glyph_size(ch), col)
				_stamp_seal(self, pos, ch, col)
			if bright >= 1.0:
				_glyph_spec(pos, adv, ch, col)
		x += adv + _gap()
	# Still-mode rim glints all share the base transform — one flush for the word.
	_flush_glints()

## The plain inflation, no shading: used by the passes BEHIND the front face (the
## extrusion walls, the flat mode's bloom) so they fatten with the balloon instead
## of peeking out from under it as a thinner silhouette.
func _puff_stamp(pos: Vector2, ch: String, col: Color) -> void:
	if puff <= 0.0:
		return
	if _is_alt(ch) or layers <= 0:
		_fill_offset(pos, ch, float(font_size) * (_puff_of(ch) + RIM_FRAC), col)
		return
	_glyph_font(ch).draw_string_outline(get_canvas_item(), pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1,
		_glyph_size(ch), maxi(1, int(round(float(font_size) * (_puff_of(ch) + RIM_FRAC)))), col)

## THE BALLOON BODY, stamped as the TILE's own two layers (CandyFace layers 3
## and 4) — dilated copies of the glyph, back to front. FreeType's stroker
## rounds every corner as it dilates, so the fatter the dilation the rounder and
## fluffier the silhouette; that dilation is where the balloon comes from, and
## the paint on top of it is the tile's, unaltered:
##   rim   — the edge-lit border: the whole shape dilated by puff + RIM_FRAC in
##           `vivid.lerp(white, 0.78)`, opaque, exactly the tile's layer 3. The
##           shader's body ramp then darkens it toward the base on its own,
##           landing within a couple of percent of the tile's 0.78 -> 0.50 rim.
##   body   — the same shape dilated by puff alone, so the visible ring is a
##           constant RIM_FRAC all the way round. Stamped INSIDE the rim rather
##           than carved out of one shared dilation, because a counter that
##           seals shut has to fill with BODY colour: the other way round, the
##           0's closed eye filled with near-white and read as a milky patch
##           sitting under its face.
##   inner  — a hairline of the body's own hue lifted toward white, one more
##           step in: the reflection running along the inside of a glass shell,
##           which is what CandyFace.draw_ball paints on a round body of this
##           same material. It is the shape-following half of the glassiness;
##           the refraction and the caustic pool are the shader's half.
## There is NO dark band anywhere in the stack. The crystal build stamped a
## squared "dense" contour between rim and body — the cut-glass bevel that read
## as a hard edge rather than a soft one — and the tiles have no such thing.
func _balloon_body(pos: Vector2, ch: String, col: Color) -> void:
	if layers <= 0 and MATERIAL_FORM_LIT:
		_form_balloon(pos, ch, col)
		return
	# Flat mode: EVERY digit's balloon is built from its seal polygons, not from
	# font outline stamps — the stroker's antialiasing blurred the edge-lit rim
	# on the brand digits while the borrowed 4's polygon rim stayed crisp, and
	# the family read as three matte digits beside one outlined one. One
	# construction, one rim, on all four (user-directed).
	if _is_alt(ch) or layers <= 0:
		_alt_balloon(pos, ch, col)
		return
	var ci := get_canvas_item()
	var fs := float(font_size)
	# _puff_of, not puff: the 4 dilates a little further than its siblings — the
	# stroker's corner rounding grows with the outline, so the extra band is
	# what softens its blocky notch into the family's pillowy modelling language.
	var p: int = maxi(2, int(round(fs * _puff_of(ch))))
	var ring: int = maxi(2, int(round(fs * RIM_FRAC)))
	var rim := col.lerp(_fire, 0.78)
	var gf := _glyph_font(ch)
	var gs := _glyph_size(ch)
	gf.draw_string_outline(ci, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, gs, p + ring, rim)
	gf.draw_string_outline(ci, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, gs, p, col)
	# The inner reflection is a RING, so it costs two more stamps: one that lays
	# the sheen down a short way inside the body edge, and one that paints the
	# body straight back over everything further in. (draw_string_outline fills
	# the whole dilated shape, not its outline — a single sheen stamp would
	# flood the entire interior.) Sub-pixel widths are pointless, so both are
	# skipped outright at small font sizes.
	var gap: int = maxi(1, int(round(fs * 0.011)))
	var band: int = maxi(1, int(round(fs * 0.009)))
	var inner: int = p - gap
	if inner - band >= 1 and fs >= 40.0:
		var sheen := col.lerp(_fire, 0.34)
		gf.draw_string_outline(ci, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1,
			gs, inner, Color(sheen.r, sheen.g, sheen.b, 0.55))
		gf.draw_string_outline(ci, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1,
			gs, inner - band, col)

## Where THIS digit's face sits. Horizontally: the centre of its own INK (the
## advance box is padded differently per glyph, and a face centred on it floats
## beside the digit), nudged by FACE_DX where a glyph's ink centre isn't its
## solid mass (the 4). Vertically: NOT the glyph's own ink — the word-wide FACE
## BAND, one eye-line height shared by all four digits, so the eight eyes sit on
## a single horizontal guideline the way the character-family reference draws
## them. The features are drawn into the same canvas item the material lights,
## so the shader's top coat (streak, crown highlight, corner gleam) passes over
## the face and it reads as being under the surface, not printed on it.
func _face_anchor(pos: Vector2, ch: String) -> Vector2:
	var ink := _ink_rect(ch)
	return pos + Vector2(ink.position.x + ink.size.x * 0.5
		+ _advance(ch) * float(FACE_DX.get(ch, 0.0)), -_face_band() * FACE_BAND)

## The shared cap the face band hangs off: the tallest glyph ink in the word.
## Off the WORD, not each glyph, or every face inherits its own body's height
## quirks — which is exactly the per-digit drift the band exists to remove.
func _face_band() -> float:
	var h := 0.0
	for k in text.length():
		h = maxf(h, _ink_rect(text[k]).size.y)
	return h if h > 0.0 else float(font_size) * 0.72

## The glyph's INK box, relative to the pen position (x right, y up from the
## baseline as a negative offset). The advance box is both wider than the drawn
## shape AND padded differently per digit, so anchoring the highlight to it put
## every digit's catch somewhere else on its body — which is exactly what read as
## inconsistent lighting. Cached per character once the glyph is rasterised; until
## then a centred estimate stands in.
func _ink_rect(ch: String) -> Rect2:
	if _ink_cache.has(ch):
		return _ink_cache[ch]
	var gf := _glyph_font(ch)
	var gs := _glyph_size(ch)
	var adv := gf.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, gs).x
	var guess := Rect2(adv * 0.10, -float(font_size) * 0.72, adv * 0.80, float(font_size) * 0.72)
	var rids := gf.get_rids()
	if rids.is_empty():
		return guess
	var ts := TextServerManager.get_primary_interface()
	var rid: RID = rids[0]
	var gid := ts.font_get_glyph_index(rid, gs, ch.unicode_at(0), 0)
	var key := Vector2i(gs, 0)
	var sz := ts.font_get_glyph_size(rid, key, gid)
	var off := ts.font_get_glyph_offset(rid, key, gid)
	if sz.x <= 1.0 or sz.y <= 1.0:
		return guess                          # not in the glyph cache yet
	var r := Rect2(off, sz)
	_ink_cache[ch] = r
	return r

# char -> the glyph's body contours (pen-relative, +y down), for _stamp_seal.
var _seal_cache: Dictionary = {}

## The glyph's SEAL: its silhouette as filled polygons with every counter
## CLOSED. The dilation stamps shrink a counter by the outline width but the
## big holes (the 0's eye, the 4's notch, the 8's two windows) survive as
## residual gaps, and through a glass body they read as dark blobs punched in
## the face — the 0's merged with its mouth into a gasp, the 4's floated over
## its eye like a rogue brow. Art-directed shut: the family are solid inflated
## candy blobs, the way the reference draws them.
##
## The brand face is hand-drawn: a digit is several OVERLAPPING outlines, not
## one clean loop, so "the biggest contour" is not the silhouette. Instead every
## contour is flattened (TrueType conic / cubic off-curve points evaluated, not
## dropped — the 8 has five on-curve points in total) and kept when it WINDS
## the same way as the largest one: same winding = a body piece, opposite
## winding = a counter. Same-colour overdraw unions the pieces. Points come
## back pen-relative in pixels with +y DOWN, exactly draw_string's space.
func _seal_polys(ch: String) -> Array[PackedVector2Array]:
	if _seal_cache.has(ch):
		return _seal_cache[ch]
	var out: Array[PackedVector2Array] = []
	var gf := _glyph_font(ch)
	var gs := _glyph_size(ch)
	var rids := gf.get_rids()
	if rids.is_empty():
		return out                            # font not live yet — retry next draw
	var ts := TextServerManager.get_primary_interface()
	var rid: RID = rids[0]
	var gid := ts.font_get_glyph_index(rid, gs, ch.unicode_at(0), 0)
	var data: Dictionary = ts.font_get_glyph_contours(rid, gs, gid)
	if not (data.has("points") and data.has("contours")):
		_seal_cache[ch] = out
		return out
	var pts: PackedVector3Array = data["points"]
	var ends: PackedInt32Array = data["contours"]
	var polys: Array[PackedVector2Array] = []
	var areas: Array[float] = []
	var start := 0
	for e_idx in ends:
		var e: int = mini(int(e_idx), pts.size() - 1)
		var poly := _flatten_contour(pts, start, e)
		start = e + 1
		if poly.size() < 3:
			continue
		var area := 0.0                        # signed shoelace: the winding
		for k in poly.size():
			var a := poly[k]
			var b := poly[(k + 1) % poly.size()]
			area += a.x * b.y - b.x * a.y
		polys.append(poly)
		areas.append(area * 0.5)
	var big := 0.0
	for a in areas:
		if absf(a) > absf(big):
			big = a
	for k in polys.size():
		if areas[k] * big > 0.0 and absf(areas[k]) > absf(big) * 0.02:
			out.append(polys[k])
	_seal_cache[ch] = out
	return out

## One TrueType contour, points[start..end], as a dense polygon. Tags: 1 = on
## curve, 0 = conic control (consecutive conics imply an on-point midway),
## 2 = cubic control (pairs). Each curve is sampled in a few steps — the seal
## only has to land within the body dilation ring of the true outline.
func _flatten_contour(pts: PackedVector3Array, start: int, end: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := end - start + 1
	if n < 2:
		return out
	# Rotate so the walk begins on an on-curve point (or a synthesised one).
	var first_on := -1
	for k in n:
		if int(pts[start + k].z) == 1:
			first_on = k
			break
	var seq: Array[Vector3] = []
	if first_on < 0:
		var p0: Vector3 = pts[start]
		var p1: Vector3 = pts[start + n - 1]
		seq.append(Vector3((p0.x + p1.x) * 0.5, (p0.y + p1.y) * 0.5, 1.0))
		for k in n:
			seq.append(pts[start + k])
	else:
		for k in n:
			seq.append(pts[start + ((first_on + k) % n)])
	seq.append(seq[0])                         # close the loop
	var cur := Vector2(seq[0].x, seq[0].y)
	out.append(cur)
	var k := 1
	while k < seq.size():
		var p: Vector3 = seq[k]
		var tag := int(p.z)
		if tag == 1:
			cur = Vector2(p.x, p.y)
			out.append(cur)
			k += 1
		elif tag == 2 and k + 2 < seq.size():
			var c1 := Vector2(p.x, p.y)
			var c2 := Vector2(seq[k + 1].x, seq[k + 1].y)
			var nxt := Vector2(seq[k + 2].x, seq[k + 2].y)
			for s in range(1, 7):
				var t := float(s) / 6.0
				out.append(cur.bezier_interpolate(c1, c2, nxt, t))
			cur = nxt
			k += 3
		else:
			var c := Vector2(p.x, p.y)
			var nxt: Vector2
			var q: Vector3 = seq[k + 1] if k + 1 < seq.size() else seq[0]
			if int(q.z) == 1:
				nxt = Vector2(q.x, q.y)
				k += 2
			else:                              # implied on-point between conics
				nxt = (c + Vector2(q.x, q.y)) * 0.5
				k += 1
			for s in range(1, 6):
				var t := float(s) / 5.0
				out.append(cur.lerp(c, t).lerp(c.lerp(nxt, t), t))
			cur = nxt
	return out

## Whether `ch` draws in the borrowed face (see ALT_GLYPHS).
func _is_alt(ch: String) -> bool:
	return ALT_GLYPHS.has(ch) and _get_alt_font() != null

# (ch, dilation px) -> the seal pushed out by that much, for the borrowed glyph.
var _offset_cache: Dictionary = {}

## The seal dilated by `d` px, round-joined — the same shape FreeType's stroker
## makes of a glyph outline, built from geometry instead. Cached per (ch, d):
## the balloon asks for the same four dilations on every redraw.
func _offset_polys(ch: String, d: float) -> Array[PackedVector2Array]:
	var key := "%s:%.1f" % [ch, d]
	if _offset_cache.has(key):
		return _offset_cache[key]
	var out: Array[PackedVector2Array] = []
	var seal := _seal_polys(ch)
	if seal.is_empty():
		return out                            # not live yet — no caching, retry
	for poly in seal:
		for grown in Geometry2D.offset_polygon(poly, d, Geometry2D.JOIN_ROUND):
			if grown.size() >= 3:
				out.append(grown)
	_offset_cache[key] = out
	return out

func _fill_offset(pos: Vector2, ch: String, d: float, col: Color) -> void:
	_stamp_mesh(self, _offset_mesh(ch, d), pos, col)

# --- STAMP MESHES ------------------------------------------------------------------
## Every seal / dilation stamp is drawn from a triangulation built ONCE per
## (glyph, dilation) and replayed, never from `draw_colored_polygon`.
##
## `draw_colored_polygon` ear-clips its polygon on the CPU on EVERY draw, and a
## round-joined dilation of a hand-drawn digit is hundreds of points. The flat
## wordmark stamps ~50 of those per redraw (four underside passes, the front
## balloon's four rings and the seal on each of five passes, times four digits),
## so the triangulation — plus a per-point GDScript loop to translate each
## polygon to its pen — was the redraw itself: measured on Home with PERF_TRACE,
## 14.5 ms of an 18 ms redraw, which at the 30 Hz idle cadence (and full rate
## through every stunt) was the Home hitch that made scrolling and confetti
## stutter on every phone. Cached indices + one Transform2D multiply in C++ per
## stamp draw the identical pixels for ~1 ms. Geometry comes from the same
## _offset_polys / _seal_polys caches, so what is drawn does not change — only
## how many times it is triangulated.
var _mesh_cache: Dictionary = {}   # "ch:d" / "ch:seal" -> {"p": points, "i": indices}

func _offset_mesh(ch: String, d: float) -> Dictionary:
	var key := "%s:%.1f" % [ch, d]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var polys := _offset_polys(ch, d)
	if polys.is_empty():
		return {}                             # font not live yet — no caching
	var m := _build_mesh(polys)
	_mesh_cache[key] = m
	return m

func _seal_mesh(ch: String) -> Dictionary:
	var key := ch + ":seal"
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var polys := _seal_polys(ch)
	if polys.is_empty():
		return {}
	var m := _build_mesh(polys)
	_mesh_cache[key] = m
	return m

## One index buffer for the whole stamp: every polygon is triangulated once and
## its triangles are appended after the points already gathered. A ring that
## cannot be triangulated is skipped — the polygon path drew nothing for it
## either (canvas_item_add_polygon fails the same way, loudly).
static func _build_mesh(polys: Array[PackedVector2Array]) -> Dictionary:
	var pts := PackedVector2Array()
	var idx := PackedInt32Array()
	for poly in polys:
		var tris := Geometry2D.triangulate_polygon(poly)
		if tris.is_empty():
			continue
		var base := pts.size()
		pts.append_array(poly)
		for t in tris:
			idx.append(base + t)
	return {"p": pts, "i": idx}

## Draws a cached stamp with its pen at `pos` on `onto`'s canvas item, in one
## flat colour. The translate is a PackedVector2Array × Transform2D — C++, not a
## per-point script loop.
static func _stamp_mesh(onto: CanvasItem, m: Dictionary, pos: Vector2, col: Color) -> void:
	if m.is_empty():
		return
	var idx: PackedInt32Array = m["i"]
	if idx.is_empty():
		return
	var pts: PackedVector2Array = Transform2D(0.0, pos) * (m["p"] as PackedVector2Array)
	# One colour for the whole array (the server broadcasts a single entry), so
	# a stamp allocates nothing but its translated points.
	RenderingServer.canvas_item_add_triangle_array(onto.get_canvas_item(), idx, pts,
		PackedColorArray([col]))

# --- FORM LIGHTING -----------------------------------------------------------------
# The premium-toy material (art-directed 2026-08-27: "the shine must follow the
# form of the number"). Each digit's sealed silhouette is drawn as a stack of
# INSETS, outermost first, and every vertex carries a real 3D normal: along a
# rounded pillow bevel at the edge (horizontal at the rim, upright a bevel-
# radius in) and a soft dome across the face (tilting away from the digit's
# own centre). One studio key light from the upper left front, a weak fill
# from the lower right, an ambient floor, a Blinn-Phong clearcoat specular and
# a reflection fresnel along the silhouette are evaluated per vertex and
# Gouraud-interpolated across each ring — so the highlight sweeps around
# every curve, the belly falls into shadow, and the edges carry a soft
# luminous rim that comes from light, not from an outline.
# NOT metal (the specular is white clearcoat over the body colour, the diffuse
# keeps the paint), NOT glass (opaque), NOT painted (no streak, no dots).
# Cached per glyph + colour; only the pen offset changes per frame.
## THE MATERIAL SWITCH. false = the CLASSIC TILE FINISH (art-directed 2026-08-27:
## "the same material and finish as the classic tile"): the balloon stamps plus
## the gloss shader's tile layers — lit crown to darkened base, the diagonal
## glass streak, the crown highlight, the base shade, the corner gleam and its
## hot catch, the edge-lit rim — opaque, exactly as CandyFace paints a tile.
## true = the studio form lighting below (one Delaunay mesh per digit lit from
## geometry), kept intact for a future pass; it is what the shader's `form_lit`
## uniform gates. Either way the SHAPES (seal, borrowed 4, underside, faces)
## are the same.
const MATERIAL_FORM_LIT := false
static var _LIGHT_KEY := Vector3(-0.50, -0.66, 0.56).normalized()
static var _LIGHT_FILL := Vector3(0.45, 0.55, 0.70).normalized()
const FORM_BEVEL := 0.40          # bevel radius as a fraction of the digit's short side
const FORM_RINGS := 18            # contours across the bevel
const FORM_DOME_STEP := 0.14      # interior contour step, as a fraction of the bevel
const FORM_SAMPLES := 112         # vertices per contour (every strip shares them)
var _lit_cache: Dictionary = {}   # "ch|rgb" -> {"p": points, "c": colours, "i": indices}

## The body is ONE triangle mesh per digit (see _lit_mesh), drawn under the
## current glyph transform. Contours are stitched into strips that SHARE their
## vertex colours, so the shading is continuous across the whole surface —
## nested flat fills, the first cut of this, stepped visibly from ring to ring.
func _form_balloon(pos: Vector2, ch: String, col: Color) -> void:
	var m := _lit_mesh(ch, col)
	if m.is_empty():
		return
	var pts: PackedVector2Array = Transform2D(0.0, pos) * (m["p"] as PackedVector2Array)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), m["i"], pts, m["c"])

func _lit_mesh(ch: String, col: Color) -> Dictionary:
	var key := ch + "|" + col.to_html(false)
	if _lit_cache.has(key):
		return _lit_cache[key]
	var seal := _seal_polys(ch)
	if seal.is_empty():
		return {}                             # font not live yet — no caching
	var fs := float(font_size)
	var outer := fs * (_puff_of(ch) + RIM_FRAC)   # the inflated silhouette
	var ink := _ink_rect(ch)
	var bevel := minf(ink.size.x, ink.size.y) * FORM_BEVEL + outer
	# The contour schedule: the quarter-circle bevel (at angle a the surface
	# sits (1 - cos a) of the radius in from the rim, its normal leaning cos a
	# outward), then the dome across the flat top, sampled inward until the
	# stroke runs out.
	var levels: Array = []                    # [inset px, lean, up]
	for k in FORM_RINGS + 1:
		var ang := (float(k) / float(FORM_RINGS)) * PI * 0.5
		levels.append([bevel * (1.0 - cos(ang)), cos(ang), sin(ang)])
	var inset := bevel
	for _k in 40:
		inset += bevel * FORM_DOME_STEP
		levels.append([inset, 0.0, 1.0])
	# THE POINT CLOUD: every contour, resampled at an even spacing and lit at
	# its own normal, then triangulated as ONE Delaunay mesh. Stitching strips
	# between neighbouring contours was the first cut, and it twisted wherever
	# a contour bent back on itself (the 2's spine, the 4's junctions) — a
	# Delaunay mesh simply joins each point to its nearest neighbours, across
	# levels, and the colours interpolate smoothly through every concavity.
	var spacing := maxf(fs * 0.02, 3.0)
	var P := PackedVector2Array()
	var C := PackedColorArray()
	var outer_polys: Array = []               # the level-0 silhouette pieces
	var outer_area := 0.0
	for poly in _offset_polys(ch, outer):
		var ar := 0.0
		for k in poly.size():
			var q1: Vector2 = poly[k]
			var q2: Vector2 = poly[(k + 1) % poly.size()]
			ar += q1.x * q2.y - q2.x * q1.y
		outer_area += absf(ar) * 0.5
	for li in levels.size():
		var lv: Array = levels[li]
		var raw: Array = _offset_polys(ch, outer - float(lv[0]))
		var any := false
		for poly in raw:
			var ring := _clean_ring(poly)
			if ring.is_empty():
				continue
			any = true
			if li == 0:
				outer_polys.append(ring)
			var per := 0.0
			var area := 0.0
			for k in ring.size():
				var q1 := ring[k]
				var q2 := ring[(k + 1) % ring.size()]
				per += q1.distance_to(q2)
				area += q1.x * q2.y - q2.x * q1.y
			var n := clampi(int(round(per / spacing)), 8, 400)
			var pts := _resample_ring(ring, n, PackedVector2Array())
			# A contour that has collapsed to a sliver is the CREST of a thin
			# stroke, where the surface is flat: lit as dome, not as bevel. Lit
			# as bevel, each sliver guesses its own outward side and the crest
			# breaks into a jagged light/dark seam (the spine of the 2).
			var lean := float(lv[1])
			var up := float(lv[2])
			# Thinness, not size: a long thin contour is a crest too (area over
			# perimeter is roughly its half-width).
			if absf(area) * 0.5 < outer_area * 0.03 or absf(area) * 0.5 / maxf(per, 1.0) < fs * 0.03:
				lean = 0.0
				up = 1.0
			P.append_array(pts)
			C.append_array(_light_ring(pts, lean, up, col, ink))
		if not any:
			break
	var I := PackedInt32Array()
	if P.size() >= 3:
		var tris := Geometry2D.triangulate_delaunay(P)
		for t in range(0, tris.size() - 2, 3):
			var ia := tris[t]
			var ib := tris[t + 1]
			var ic := tris[t + 2]
			# The hull bridges every concavity (the 2's curl to its base, the 4's
			# notch): a triangle is kept only if its centre lies INSIDE the
			# silhouette. Every triangle is tested — bridges with one inner
			# corner slipped through a silhouette-only test.
			var cen := (P[ia] + P[ib] + P[ic]) / 3.0
			var inside := false
			for op in outer_polys:
				if Geometry2D.is_point_in_polygon(cen, op):
					inside = true
					break
			if not inside:
				continue
			I.append(ia)
			I.append(ib)
			I.append(ic)
	var mesh := {"p": P, "c": C, "i": I}
	_lit_cache[key] = mesh
	return mesh

## A contour resampled to `n` points by arc length, oriented like every other
## contour and started at the point nearest the previous contour's start — so
## consecutive contours pair up vertex for vertex and the strips never twist.
static func _resample_ring(poly: PackedVector2Array, n: int, prev: PackedVector2Array) -> PackedVector2Array:
	var pts := poly
	var area := 0.0
	for k in pts.size():
		var a := pts[k]
		var b := pts[(k + 1) % pts.size()]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		pts = PackedVector2Array()
		for k in range(poly.size() - 1, -1, -1):
			pts.append(poly[k])
	var start := 0
	if not prev.is_empty():
		var best := INF
		for k in pts.size():
			var d := pts[k].distance_squared_to(prev[0])
			if d < best:
				best = d
				start = k
	var m := pts.size()
	var total := 0.0
	for k in m:
		total += pts[(start + k) % m].distance_to(pts[(start + k + 1) % m])
	var out := PackedVector2Array()
	out.resize(n)
	var seg := 0
	var seg_start := 0.0
	var seg_len := pts[start].distance_to(pts[(start + 1) % m])
	for j in n:
		var target := total * float(j) / float(n)
		while seg < m - 1 and target > seg_start + seg_len:
			seg_start += seg_len
			seg += 1
			seg_len = pts[(start + seg) % m].distance_to(pts[(start + seg + 1) % m])
		var f := 0.0 if seg_len <= 0.0001 else clampf((target - seg_start) / seg_len, 0.0, 1.0)
		out[j] = pts[(start + seg) % m].lerp(pts[(start + seg + 1) % m], f)
	return out

## The deepest insets of a thin stroke collapse into slivers, and Clipper
## leaves near-duplicate consecutive points on round joins; either makes the
## triangulator reject the ring (a logged "Invalid polygon data" per frame).
## Consecutive points closer than half a pixel are merged and anything under
## a few square pixels is dropped. Returns an empty array for a rejected ring.
static func _clean_ring(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in poly:
		if out.is_empty() or out[out.size() - 1].distance_squared_to(q) > 0.25:
			out.append(q)
	if out.size() >= 2 and out[0].distance_squared_to(out[out.size() - 1]) <= 0.25:
		out.remove_at(out.size() - 1)
	if out.size() < 3:
		return PackedVector2Array()
	var area := 0.0
	for k in out.size():
		var a := out[k]
		var b := out[(k + 1) % out.size()]
		area += a.x * b.y - b.x * a.y
	if absf(area) * 0.5 < 6.0:
		return PackedVector2Array()
	return out

## Per-vertex lighting for one ring. `lean` is the bevel normal's horizontal
## share (1 at the rim, 0 on the flat), `up` its vertical share.
func _light_ring(poly: PackedVector2Array, lean: float, up: float, col: Color,
		ink: Rect2) -> PackedColorArray:
	var n := poly.size()
	var colors := PackedColorArray()
	colors.resize(n)
	# Outward = away from the shape. Decided ONCE per ring at its rightmost
	# vertex, where outward is unambiguously +x: probing a point a few px off
	# an arbitrary edge lands INSIDE a thin stroke and flipped whole rings dark.
	var kx := 0
	for k in n:
		if poly[k].x > poly[kx].x:
			kx = k
	var ex := poly[(kx + 1) % n] - poly[(kx - 1 + n) % n]
	var sign := 1.0 if Vector2(-ex.y, ex.x).x >= 0.0 else -1.0
	var cx := ink.position.x + ink.size.x * 0.5
	var cy := ink.position.y + ink.size.y * 0.5
	var half := Vector3(_LIGHT_KEY.x, _LIGHT_KEY.y, _LIGHT_KEY.z + 1.0).normalized()
	# A white clearcoat on a near-white body clips to flat white — the pale 2
	# keeps its specular quieter so its curvature still reads.
	var pale := clampf((col.get_luminance() - 0.72) * 3.2, 0.0, 1.0)
	for k in n:
		var prev := poly[(k - 1 + n) % n]
		var next := poly[(k + 1) % n]
		var e := next - prev
		var nrm := Vector2(-e.y, e.x).normalized() * sign
		# The face dome: the flat top of the pillow still bulges, leaning away
		# from the digit's centre — that is what sweeps one broad highlight across
		# the upper-left of every body instead of lighting the face flat.
		var dome := Vector2((poly[k].x - cx) / maxf(ink.size.x, 1.0),
			(poly[k].y - cy) / maxf(ink.size.y, 1.0)).limit_length(0.5) * 0.50 * up
		var N := Vector3(nrm.x * lean + dome.x, nrm.y * lean + dome.y, up).normalized()
		var diff := maxf(N.dot(_LIGHT_KEY), 0.0)
		var fill := maxf(N.dot(_LIGHT_FILL), 0.0) * 0.16
		# Two speculars: a tight clearcoat catch on the bevel (where the normal
		# turns fast) and a broad soft sheet across the dome — one studio light
		# sweeping the face, not a hot dot.
		var ndh := maxf(N.dot(half), 0.0)
		# Broad and wrapping: a lower exponent spreads the clearcoat into one
		# soft curved sheet that follows the bevel round, instead of a hot spot.
		var spec := (pow(ndh, 22.0) * 0.50 * lean + pow(ndh, 7.0) * 0.50 * up) \
			* (1.0 - 0.55 * pale)
		# The edge glow is REFLECTION in the body's own hue — never a white line.
		var fres := pow(1.0 - clampf(N.z, 0.0, 1.0), 2.8) * 0.15
		# The belly: ambient falls off toward the base of the body.
		var ao := 1.0 - 0.32 * clampf((poly[k].y - ink.position.y) / maxf(ink.size.y, 1.0), 0.0, 1.0)
		# THE TILE'S OWN COLOUR GRADE. The lighting decides WHERE the body is lit,
		# but the tones it lands on are the board tile's exact ramp — CandyFace
		# paints a tile from lightened(0.20) at the crown to darkened(0.28) at
		# the base with the raw colour as its mid — so the wordmark and the
		# tiles of the worn theme read as one paint job (art-directed: "colour
		# grade the same as the tiles"). Multiplying the colour by the light
		# instead sank every digit a tone or two below its tile.
		var lit := (0.33 + 0.72 * diff + fill) * ao
		var tone := clampf((lit - 0.22) / 0.82, 0.0, 1.0)
		var c := col.darkened(0.28).lerp(col.lightened(0.20), tone)
		var coat := Color(1, 1, 1).lerp(col, 0.12)
		var rim := col.lerp(Color(1, 1, 1), 0.30)
		c = Color(minf(c.r + coat.r * spec + rim.r * fres, 1.0),
			minf(c.g + coat.g * spec + rim.g * fres, 1.0),
			minf(c.b + coat.b * spec + rim.b * fres, 1.0), 1.0)
		colors[k] = c
	return colors

## The balloon for the BORROWED glyph: the same rim / body / inner-sheen stack
## as _balloon_body, stamped from dilated seal polygons rather than font
## outlines. Baloo's strokes are far thinner than the brand bubbles, and this is
## where the 4 gains its mass: PUFF_SOFTEN inflates it until its strokes stand
## as fat as its siblings' — geometry, so the fattening is exact at any size.
func _alt_balloon(pos: Vector2, ch: String, col: Color) -> void:
	var fs := float(font_size)
	var p := fs * _puff_of(ch)
	var ring := fs * RIM_FRAC
	_fill_offset(pos, ch, p + ring, col.lerp(_fire, 0.78))
	_fill_offset(pos, ch, p, col)
	var gap := fs * 0.011
	var band := fs * 0.009
	var inner := p - gap
	if inner - band >= 1.0 and fs >= 40.0:
		var sheen := col.lerp(_fire, 0.34)
		_fill_offset(pos, ch, inner, Color(sheen.r, sheen.g, sheen.b, 0.55))
		_fill_offset(pos, ch, inner - band, col)

## Fill the seal in `col` with the pen at `pos`, on `onto`'s canvas (the front
## face and the ground reflection stamp it on different items).
func _stamp_seal(onto: CanvasItem, pos: Vector2, ch: String, col: Color) -> void:
	_stamp_mesh(onto, _seal_mesh(ch), pos, col)

## The finishing marks, all placed off THIS digit's ink box — the same fractions
## of the same shape on every digit — so all four catch the light in the same
## spot, at the same size, however wide or narrow the glyph is.
##
## LAYER 8b of the tile material: CandyFace seats a hot white disc with a tighter
## hotter core inside it on the tile's upper-left rim, and that pair is the one
## mark that reads "polished". It lives here rather than in the shader because it
## has to sit ON the silhouette, which only the script knows the shape of. Its
## alpha follows the tile's rule — bumped on near-white bodies, where a 0.70 dot
## would otherwise sink into a pale rim.
func _glyph_spec(pos: Vector2, _adv: float, ch: String, col: Color) -> void:
	var fs := float(font_size)
	var ink := _ink_rect(ch)
	# Seated INSIDE the shader's corner gleam (which pools around u,v = -0.50):
	# the tile's catch sits in its bloom, and a hot dot dropped on unlit body
	# instead reads as a sticker.
	var spec := pos + ink.position + Vector2(ink.size.x * 0.22, ink.size.y * 0.19)
	var pale: float = clampf((col.get_luminance() - 0.72) * 3.2, 0.0, 1.0)
	var spec_a: float = 0.82 + 0.12 * pale
	# The tile's hot catch (CandyFace layer 8b) belongs to the classic finish;
	# only the form-lit body (MATERIAL_FORM_LIT) does without it, taking its
	# specular off the geometry instead.
	if layers > 0 or not MATERIAL_FORM_LIT:
		if pale > 0.5:
			# The tile's own trick on off-white fills: a soft darker contact ring
			# so the white catch still separates from the rim it sits on.
			draw_circle(spec, fs * 0.030, Color(0, 0, 0, 0.06), true, -1.0, true)
		draw_circle(spec, fs * 0.021, Color(1, 1, 1, spec_a), true, -1.0, true)
		draw_circle(spec + Vector2(-fs * 0.005, -fs * 0.005), fs * 0.011,
			Color(1, 1, 1, minf(spec_a + 0.15, 1.0)), true, -1.0, true)
	# On the form-lit body every sparkle reads as a painted white dot — the
	# polished toy carries its shine in the material alone (art-directed).
	if layers <= 0:
		return
	# The GLINTS: tiny 4-point stars where light breaks on the RIM (never on the
	# body — a sparkle out in the middle of the face reads as dirt). Each
	# twinkles on its own clock, swelling and dimming out of phase. With
	# animation off they hold a fixed sparkle.
	var ph := pos.x * 0.11
	_glint(pos + ink.position + Vector2(ink.size.x * 0.06, -fs * puff * 0.4),
		fs * 0.046, 0.5 + 0.5 * sin(_t * 2.1 + ph), _fire)
	_glint(pos + ink.position + Vector2(ink.size.x * 0.90, ink.size.y * 0.74),
		fs * 0.042, 0.5 + 0.5 * sin(_t * 1.6 + ph + 2.6), _fire)
	_glint(pos + ink.position + Vector2(ink.size.x * 0.14, ink.size.y * 0.88),
		fs * 0.036, 0.5 + 0.5 * sin(_t * 1.9 + ph + 4.1), _fire)
	_glint(pos + ink.position + Vector2(ink.size.x * 0.82, ink.size.y * 0.12),
		fs * 0.034, 0.5 + 0.5 * sin(_t * 2.4 + ph + 1.3), _fire)
	# (No back-surface hairline. The displaced far-wall contour is a cue for a
	# body you can see THROUGH — it belonged to the crystal rig and reads as a
	# printing misregistration on an opaque tile finish.)

## THE GLITTER FIELD: a fixed constellation of motes dusted over an oval around
## the word — they hold their places and only TWINKLE, each on its own clock.
##
## They used to ORBIT (84 motes revolving 14–22 s per lap, half crossing the face
## and half returning behind the digits). Travelling motes cost a full
## trig-and-place pass per mote per redraw and, worse, kept the whole field in
## motion at every moment, so nothing about the layer could ever be reused. A
## stationary field is bought once (`_bake_field`) and replayed: per redraw a mote
## is one `sin` for its twinkle plus the queue append. The layer still reads as
## live crystal dust because the sparkle — not the travel — is what the eye picks
## up at 6–18 px.
##
## Depth survives the freeze: motes baked BEHIND the word occupy `[0,
## _field_split)` and are drawn before the glyph stack (`front = false`), so the
## crystal genuinely occludes them; the front slice `[_field_split, N)` lands on
## the faces. Sorting the bake that way keeps each draw a contiguous walk with no
## per-mote depth test. Mote shape/colour stays theme-aware via `dress`.
const _FIELD_N := 84

var _field_p := PackedVector2Array()    # mote centre, item space
var _field_r := PackedFloat32Array()    # mote radius (near-factor already folded in)
var _field_s := PackedFloat32Array()    # twinkle speed, rad/s
var _field_h := PackedFloat32Array()    # twinkle phase
var _field_n := PackedFloat32Array()    # near factor — scales the twinkle's peak
var _field_split := 0                   # where the front-of-the-word motes begin
var _field_key := Vector3(INF, INF, INF)

## Bakes the constellation for the current layout, back-half motes first. Cheap
## enough to re-run on any layout change (font size, text, spacing), which is the
## only thing that can move a mote now.
func _bake_field(pad: Vector2) -> void:
	var fs := float(font_size)
	var key := Vector3(_measure.x, _measure.y, fs)
	if key.is_equal_approx(_field_key) and _field_p.size() == _FIELD_N:
		return
	_field_key = key
	var c := Vector2(pad.x + _measure.x * 0.5,
		pad.y + _font.get_ascent(font_size) - fs * 0.36)
	var rx := _measure.x * 0.58
	var ry := fs * 0.58
	_field_p.clear()
	_field_r.clear()
	_field_s.clear()
	_field_h.clear()
	_field_n.clear()
	# Two passes so the array comes out sorted back-then-front. Placement rides
	# irrational strides (no randf): an even, non-gridded scatter that is bit-for-bit
	# identical on every rebuild, so a theme change never re-shuffles the dust.
	for pass_front in 2:
		for k in _FIELD_N:
			var fk := float(k)
			var d := fposmod(fk * 0.4301597091, 1.0)
			var is_front := d >= 0.5
			if is_front != (pass_front == 1):
				continue
			var ang := TAU * fposmod(fk * 0.7548776662, 1.0)
			# sqrt spreads the motes evenly over the oval's AREA rather than
			# bunching them at its centre.
			var rad := sqrt(fposmod(fk * 0.5698402909, 1.0))
			# Motes in front of the crystal read nearer: bigger, brighter, and
			# varied; the ones behind it sit uniformly small and dim.
			var near := 0.62
			if is_front:
				near += 0.76 * (d - 0.5)
			_field_p.append(c + Vector2(cos(ang) * rx * rad, sin(ang) * ry * rad))
			_field_r.append(fs * (0.017 + 0.010 * float(k % 3)) * near)
			# 2.0–4.6 rad/s — a 1.4–3.1 s cycle per mote. Faster than the orbit's
			# lazy shimmer (the travel used to carry the liveliness; now the
			# twinkle has to) but far under any flash threshold: well below one
			# peak per second each, and every peak is a smooth sine fade.
			_field_s.append(2.0 + fposmod(fk * 0.71, 2.6))
			_field_h.append(fk * 1.7)
			_field_n.append(near)
		if pass_front == 0:
			_field_split = _field_p.size()

func _draw_glitter_field(pad: Vector2, front: bool) -> void:
	_bake_field(pad)
	# Motes catch the room's key light; a dress costume still outranks it below.
	var mcol := _fire
	var flakes := false
	match dress:
		"scarf":
			flakes = true
			mcol = Color(0.85, 0.94, 1.0)
		"crown":
			mcol = Color(1.0, 0.85, 0.45)
		"star":
			mcol = Color(0.90, 0.87, 1.0)
	var from: int = _field_split if front else 0
	var to: int = _field_p.size() if front else _field_split
	var bloom_k := 0.14 + 0.16 * (1.0 - _env_dark)
	for k in range(from, to):
		var p := _field_p[k]
		var mr := _field_r[k]
		# SQUARED twinkle: the old linear ramp made a stationary mote read as a
		# slow breath. Squaring holds each one dim for most of its cycle and snaps
		# it bright for a moment — a glitter flash instead of a pulse.
		var s := 0.5 + 0.5 * sin(_t * _field_s[k] + _field_h[k])
		var tw := (0.14 + 0.86 * s * s) * _field_n[k]
		# The soft WHITE LIGHT behind each mote: white spikes alone vanish on
		# light themes — the bloom grows as the theme gets brighter.
		var bloom := bloom_k * tw
		if bloom > 0.03:
			var bw := mr * 5.0
			# Flakes queue like every other sparkle (they draw from a baked
			# texture — see _flake), so their bloom queues too and the whole
			# field flushes as a handful of batched calls.
			_q_bloom_r.append(Rect2(p.x - bw * 0.5, p.y - bw * 0.5, bw, bw))
			_q_bloom_c.append(Color(_fire.r, _fire.g, _fire.b, bloom))
		if flakes:
			_flake(p, mr * 1.25, tw, mcol)
		else:
			_glint(p, mr, tw, mcol)
	_flush_glints()

## Frost breath: each puff is three overlapping soft clouds that rise, spread
## and thin away — visible breath in cold air, not smoke (it stays faint).
func _draw_puffs() -> void:
	var fs := float(font_size)
	for pf in _puffs:
		var age := (_t - float(pf["t0"])) / 1.5
		var big: bool = bool(pf["big"])
		var base: Vector2 = pf["p"]
		var rise := base + Vector2(fs * 0.05 * age, -fs * (0.10 + 0.14 * age))
		var psc := (0.5 + 1.1 * age) * (1.35 if big else 0.85)
		var a := (1.0 - age) * (0.24 if big else 0.16)
		for c in 3:
			var off := Vector2(sin(float(c) * 2.1 + _t * 0.8), cos(float(c) * 1.7)) \
				* fs * 0.045 * psc
			var r := fs * (0.085 + 0.02 * float(c)) * psc
			draw_texture_rect(CandyFace.glow_dot(),
				Rect2(rise + off - Vector2(r, r), Vector2(r * 2.0, r * 2.0)),
				false, Color(1, 1, 1, a))

## Interaction/emission sparks: each flies from its spawn point and twinkles out
## over its own lifetime.
func _draw_sparks() -> void:
	for s in _sparks:
		var age := (_t - float(s["t0"])) / maxf(float(s.get("life", 0.9)), 0.01)
		_glint(s["p"], float(s["r"]), clampf(1.0 - age, 0.0, 1.0), _fire)
	_flush_glints()

## Halo dust: for a few seconds after a celebration, a faint ring of
## micro-sparkles orbits the word slowly — settling dust catching the light.
## The whole ring eases in and out over its lifetime, so it never pops.
func _draw_halo_dust(pad: Vector2) -> void:
	var age := _t - _halo_t0
	if age < 0.0 or age >= _halo_dur or _halo_dur <= 0.0:
		return
	var fs := float(font_size)
	var env := sin(PI * clampf(age / _halo_dur, 0.0, 1.0))
	var c := Vector2(pad.x + _measure.x * 0.5,
		pad.y + _font.get_ascent(font_size) - fs * 0.35)
	for k in 80:
		var fk := float(k)
		var ang := TAU * fk / 80.0 + _t * 0.22
		var rx := _measure.x * 0.56 + sin(_t * 0.9 + fk * 1.3) * fs * 0.05
		var p := c + Vector2(cos(ang) * rx, sin(ang) * fs * 0.62)
		var tw := 0.5 + 0.5 * sin(_t * (2.0 + fposmod(fk * 0.43, 1.0)) + fk * 2.2)
		_glint(p, fs * (0.009 + 0.007 * float(k % 3)), tw * env * 0.7, _fire)
	_flush_glints()

## A tiny 4-point star glint — four tapered spikes crossing a hot core — scaled
## and faded by `k` (0..1) so it twinkles instead of sitting painted on. `col`
## tints the spikes (theme motes); the core stays white-hot regardless.
##
## Drawn from a BAKED texture, not live polygons: a glint is 6–18 px on screen
## and the word paints dozens per frame (the glitter field, the rim glints, the
## post-celebration halo dust) — two tessellated polygons plus an AA circle per
## star was a real slice of the redraw bill for shapes smaller than a fingertip.
## The bake is the same crossed tapered spikes; the hot core rides on the shared
## CandyFace.glow_dot so it stays white however the spikes are tinted.
static var _glint_spikes: ImageTexture

static func _glint_tex() -> ImageTexture:
	if _glint_spikes == null:
		const N := 64
		var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
		for y in N:
			for x in N:
				var u := (float(x) / float(N - 1)) * 2.0 - 1.0
				var v := (float(y) / float(N - 1)) * 2.0 - 1.0
				# Two crossed thin rhombi (|x| + |y|/0.16 <= 1 and its transpose),
				# with a narrow smooth edge standing in for the old AA.
				var h := 1.0 - (absf(u) + absf(v) / 0.16)
				var w := 1.0 - (absf(v) + absf(u) / 0.16)
				var a := clampf(maxf(h, w) * 14.0, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_glint_spikes = ImageTexture.create_from_image(img)
	return _glint_spikes

## Sparkles queue instead of painting immediately: a glint is a spike-texture
## rect plus a glow-dot core, so painting them inline alternates textures every
## star — and every texture swap ends the canvas batch, which made the sparkle
## layers most of Home's draw calls (~250 of ~850 at rest). Each sparkle GROUP
## (glitter-field half, dust, one glyph's rim glints) queues its rects and then
## _flush_glints() paints all blooms, all spikes, all cores consecutively — a
## handful of batched calls. Group order (behind/in front of the glyphs) is
## unchanged; only sub-sparkle stacking inside one group reorders, invisible at
## these sizes. Queued rects are in the CURRENT draw transform, so every group
## must flush before the transform changes (see _draw_face's per-glyph flush).
var _q_bloom_r: Array[Rect2] = []
var _q_bloom_c := PackedColorArray()
var _q_spike_r: Array[Rect2] = []
var _q_spike_c := PackedColorArray()
var _q_flake_r: Array[Rect2] = []
var _q_flake_c := PackedColorArray()
var _q_core_r: Array[Rect2] = []
var _q_core_c := PackedColorArray()

func _flush_glints() -> void:
	for i in _q_bloom_r.size():
		draw_texture_rect(CandyFace.glow_dot(), _q_bloom_r[i], false, _q_bloom_c[i])
	for i in _q_spike_r.size():
		draw_texture_rect(_glint_tex(), _q_spike_r[i], false, _q_spike_c[i])
	for i in _q_flake_r.size():
		draw_texture_rect(_flake_tex(), _q_flake_r[i], false, _q_flake_c[i])
	for i in _q_core_r.size():
		draw_texture_rect(CandyFace.glow_dot(), _q_core_r[i], false, _q_core_c[i])
	_q_bloom_r.clear()
	_q_bloom_c.clear()
	_q_spike_r.clear()
	_q_spike_c.clear()
	_q_flake_r.clear()
	_q_flake_c.clear()
	_q_core_r.clear()
	_q_core_c.clear()

func _glint(c: Vector2, r: float, k: float, col: Color = Color(1, 1, 1)) -> void:
	if k < 0.05:
		return
	var a := minf((0.16 + 0.55 * k) * (1.0 + 0.35 * _env_dark), 1.0)
	var rr := r * (0.55 + 0.45 * k)
	_q_spike_r.append(Rect2(c.x - rr, c.y - rr, rr * 2.0, rr * 2.0))
	_q_spike_c.append(Color(col.r, col.g, col.b, a))
	# The white-hot core: the soft shared radial at a size whose opaque centre
	# matches the old rr*0.15 hard dot.
	var cr := rr * 0.4
	_q_core_r.append(Rect2(c.x - cr, c.y - cr, cr * 2.0, cr * 2.0))
	_q_core_c.append(Color(1, 1, 1, minf(a + 0.25, 1.0)))

## A tiny six-arm snowflake mote (the icy themes' glitter): three crossed
## hairlines and a bright core, twinkling exactly like a glint.
##
## QUEUED from a BAKED texture, exactly like _glint — this path used to be the
## one sparkle that still painted inline (three AA draw_lines + a circle, with
## its bloom rect interleaved), so on the icy themes every one of the 84 field
## motes ended the canvas batch twice. Measured on glacier_dawn's Home: the
## wordmark carried ~600 extra draw calls and the screen ran 2.7× the frame
## cost of every other theme — all of it this loop. The bake freezes the
## thickness-to-arm ratio at its mid-twinkle value (the same trade _glint_tex
## accepted); at 6–18 px on screen the difference does not survive rasterising.
static var _flake_arms: ImageTexture

static func _flake_tex() -> ImageTexture:
	if _flake_arms == null:
		const N := 64
		var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
		for y in N:
			for x in N:
				var u := (float(x) / float(N - 1)) * 2.0 - 1.0
				var v := (float(y) / float(N - 1)) * 2.0 - 1.0
				# Three crossed bars at the live loop's angles (PI*arm/3 + 0.3),
				# half-thickness 0.12 of the arm half-length — the live ratio at
				# the twinkle midpoint — with a narrow smooth edge as the old AA.
				var a := 0.0
				for arm in 3:
					var th := PI * float(arm) / 3.0 + 0.3
					var d := Vector2(cos(th), sin(th))
					var along := absf(u * d.x + v * d.y)
					var across := absf(u * d.y - v * d.x)
					if along <= 1.0:
						a = maxf(a, clampf((0.12 - across) * 22.0, 0.0, 1.0))
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_flake_arms = ImageTexture.create_from_image(img)
	return _flake_arms

func _flake(c: Vector2, r: float, k: float, col: Color) -> void:
	if k < 0.05:
		return
	var a := minf((0.14 + 0.45 * k) * (1.0 + 0.35 * _env_dark), 1.0)
	var rr := r * (0.6 + 0.4 * k)
	_q_flake_r.append(Rect2(c.x - rr, c.y - rr, rr * 2.0, rr * 2.0))
	_q_flake_c.append(Color(col.r, col.g, col.b, a))
	# The core rides the shared glow_dot: the radial's opaque centre matches the
	# old hard rr*0.18 circle at ~2.7× its radius (same ratio _glint uses).
	var cr := rr * 0.48
	_q_core_r.append(Rect2(c.x - cr, c.y - cr, cr * 2.0, cr * 2.0))
	_q_core_c.append(Color(1, 1, 1, minf(a + 0.2, 1.0)))

## A digit's idle "character" — each has its own sway speed, tilt amount and bob
## phase, so the four read as four different personalities. The stunt transform
## composes on top when this digit is mid-trick.
func _glyph_xf(i: int, pivot: Vector2) -> Transform2D:
	var spd: float = [1.1, 1.7, 1.4, 0.9][i % 4]
	# Sway amplitudes kept SMALL: each digit still breathes on its own clock,
	# but past ~0.015 rad the tilts stagger the shared eye line and the family's
	# level face band — the reference's strongest unity cue — falls apart.
	var amp: float = [0.011, 0.009, 0.014, 0.011][i % 4]
	var rot: float = POSE_TILT[i % POSE_TILT.size()] + sin(_t * spd + float(i) * 2.1) * amp
	var bob := sin(_t * spd * 0.8 + float(i) * 1.3) * font_size * 0.012
	# When a sibling gets poked, the easy-going digits giggle (a quick fading
	# shoulder-shake); the grumpy ones don't dignify it with movement.
	var react_age := _t - _react_t0
	if react_age >= 0.0 and react_age < 0.9 and i != _poked \
			and float(PERSONA[i % PERSONA.size()]["temper"]) < 0.6:
		bob += sin(_t * 18.0 + float(i)) * font_size * 0.009 * (1.0 - react_age / 0.9)
	# Family sizing: this digit's own resting size (always >= 1.0 — the word only
	# ever grows a digit, never shrinks one), so the four stand at their own heights.
	var fam: float = FAMILY_SCALE[i % FAMILY_SCALE.size()]
	var sc := Vector2.ONE * fam
	# Petting: digits near the stroking finger lean into it, swell a touch, and
	# purr (a tiny fast tremble). Falloff by distance, so the pet has a focus.
	if _petting:
		var reach := clampf(1.0 - absf(pivot.x - _pet_x) / (font_size * 1.3), 0.0, 1.0)
		if reach > 0.0:
			rot += -signf(pivot.x - _pet_x) * 0.09 * reach
			bob += sin(_t * 30.0) * font_size * 0.006 * reach
			sc = Vector2.ONE * (1.0 + 0.04 * reach)
	# A sneeze blasts the neighbours: each gets shoved away from the sneezer, a
	# beat later the further they stand — the domino ripple.
	if _stunt_kind == 6 and _stunt_p < 1.0 and i != _stunt_glyph and _stunt_glyph >= 0:
		var k := (_stunt_p - 0.5) * 0.65 - absf(float(i - _stunt_glyph)) * 0.06
		if k >= 0.0 and k <= 0.30:
			rot += signf(float(i - _stunt_glyph)) * 0.15 * sin(PI * k / 0.30)
	var shove := 0.0
	# The digit's own mind: its private idle quirk, in its personality's dialect.
	var qp := _quirk_p(i)
	if qp >= 0.0:
		match i % 4:
			0:   # shy 2 — a nervous little shrink-and-recover
				sc *= 1.0 - 0.05 * sin(PI * qp)
			1:   # goofy 0 — hops for no reason at all
				bob -= font_size * 0.08 * sin(PI * qp)
			2:   # grumpy 4 — a big slow sigh: shoulders sag
				sc = Vector2(sc.x * (1.0 + 0.03 * sin(PI * qp)),
					sc.y * (1.0 - 0.06 * sin(PI * qp)))
				bob += font_size * 0.02 * sin(PI * qp)
			_:   # chill 8 — a lazy side-to-side stretch
				rot += 0.06 * sin(TAU * qp)
	# The scuffle: both fighters lunge-shove at each other in alternating beats,
	# leaning into every hit; the recoil reads in the rotation.
	var brawl_age := _t - _brawl_t0
	if brawl_age >= 0.0 and brawl_age < _BRAWL_DUR and (i == _brawl_a or i == _brawl_b):
		var opp := _brawl_b if i == _brawl_a else _brawl_a
		var toward := signf(float(opp - i))
		var ph := brawl_age * 9.0 + (0.0 if i == _brawl_a else PI)
		var lunge := maxf(0.0, sin(ph))
		var fade := 1.0 - brawl_age / _BRAWL_DUR
		shove += toward * font_size * 0.11 * lunge * fade
		rot += toward * 0.13 * lunge * fade
	# The taffy pull: the grabbed digit leans and stretches toward the finger
	# (or oscillates home on the release spring).
	if i == _pull_glyph and absf(_pull) > 0.01:
		shove += _pull * 0.55
		sc.x *= 1.0 + absf(_pull) / (float(font_size) * 2.6)
	# Giggles: the tickled cast shakes shoulder-to-shoulder for a beat.
	var gig := _t - _giggle_t0
	if gig >= 0.0 and gig < 1.3:
		var gf := 1.0 - gig / 1.3
		bob += sin(_t * 26.0 + float(i) * 1.1) * font_size * 0.012 * gf
		rot += sin(_t * 19.0 + float(i)) * 0.02 * gf
	var xf := Transform2D(rot, sc, 0.0, Vector2.ZERO)
	xf.origin = pivot + Vector2(shove, bob) - xf.basis_xform(pivot)
	if i == _stunt_glyph and _stunt_p < 1.0:
		xf = xf * _stunt_xf(pivot)
	return xf

## A filled ellipse — `draw_circle` only does circles, and a toon eye reads as an
## eye because it is taller than it is wide.
func _ellipse(c: Vector2, rx: float, ry: float, col: Color, segments: int = 24) -> void:
	var pts := PackedVector2Array()
	for k in segments:
		var a := TAU * float(k) / float(segments)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)

## A closed-eye LINE: one thin smooth stroke from corner to corner, bowed upward
## by `bow` through its middle (0 = flat), antialiased, uniform width. The
## whole closed eye, and the cap of a half-closed one, is this and nothing else.
func _eye_line(c: Vector2, half_w: float, bow: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	var n := 14
	for k in n + 1:
		var f := float(k) / float(n)
		pts.append(c + Vector2(lerpf(-half_w, half_w, f), -bow * sin(PI * f)))
	draw_polyline(pts, col, width, true)

## A lash stroke: a TAPERED band following an elliptical arc — fat in the middle,
## thinning to nothing at both corners, the way a drawn eyelid does. A uniform
## polyline reads as a pencil mark; this reads as a lid. Angles are Godot's (+y
## down), so PI → TAU sweeps the TOP half of the ellipse.
func _lash(c: Vector2, rx: float, ry: float, a0: float, a1: float,
		col: Color, thick: float) -> void:
	var n := 16
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for k in n + 1:
		var f := float(k) / float(n)
		var a := lerpf(a0, a1, f)
		var p := c + Vector2(cos(a) * rx, sin(a) * ry)
		# Outward normal of the ellipse at this angle (kept a hair off zero so the
		# polygon never collapses into degenerate points).
		var nrm := Vector2(cos(a) / maxf(rx, 0.001), sin(a) / maxf(ry, 0.001)).normalized()
		var w := thick * maxf(sin(PI * f), 0.10) * 0.5
		top.append(p + nrm * w)
		bot.append(p - nrm * w)
	var poly := PackedVector2Array()
	poly.append_array(top)
	for k in range(bot.size() - 1, -1, -1):
		poly.append(bot[k])
	draw_colored_polygon(poly, col)

## A brow: a tapered band from `p_in` to `p_out`, bowed upward by `bow` through
## its middle. The bow is always toward the top of the screen (not the stroke's
## normal) so the left and right brows arch the same way.
func _brow(p_in: Vector2, p_out: Vector2, bow: float, col: Color, thick: float) -> void:
	var n := 12
	var d := p_out - p_in
	var nrm := Vector2(-d.y, d.x).normalized()
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for k in n + 1:
		var f := float(k) / float(n)
		var p := p_in.lerp(p_out, f) - Vector2(0.0, bow * sin(PI * f))
		var w := thick * (0.30 + 0.70 * sin(PI * f)) * 0.5
		top.append(p + nrm * w)
		bot.append(p - nrm * w)
	var poly := PackedVector2Array()
	poly.append_array(top)
	for k in range(bot.size() - 1, -1, -1):
		poly.append(bot[k])
	draw_colored_polygon(poly, col)

## The character eyes + brows, drawn on the front face only (they ride the
## digit's own transform). Each digit blinks on its own schedule; where it LOOKS
## is a social priority chain:
##   scared (cower) → stares at the forming bomb, brows sky-high
##   annoyed (taps) → half-lidded angry rattle, brows in a hard V
##   pointer moved  → everyone watches the finger (they see the tap coming)
##   a digit stunts → the OTHERS all turn to watch the show, one brow raised
##   conversations  → two digits catch each other's eye; the partner is sceptical
##   ignored 25s+   → droopy sleepy lids, pupils sinking
##   otherwise      → idle wander
func _draw_eyes(i: int, anchor: Vector2, _adv: float, body_col: Color) -> void:
	# THE FACE UNIT: font_size divided by this digit's family scale. The face is
	# drawn inside the glyph's scaled transform (animate mode), so without the
	# division the biggest digit wears the biggest face — the exact "different
	# proportions" the master face exists to remove. Every feature measure below
	# rides `fu`, so all four faces land pixel-identical whatever the body does.
	var fam: float = FAMILY_SCALE[i % FAMILY_SCALE.size()] if animate else 1.0
	var fu := float(font_size) / fam
	var r := fu * FACE_EYE_R
	var sep := fu * FACE_EYE_SEP
	var irr_dur := 0.5 + 0.25 * _irr_amp
	var irr_age := _t - _irr_t0
	var irr_k := 0.0
	if irr_age >= 0.0 and irr_age < irr_dur:
		irr_k = (1.0 - irr_age / irr_dur) * _irr_amp
	var dance_d := (_t - _dance_t0) - float(i) * 0.09
	var happy := dance_d >= 0.0 and dance_d <= 0.38
	var period := 2.6 + float(i) * 0.83
	var blinking := fposmod(_t + float(i) * 1.9, period) < 0.12
	var pointer_on := _t < _look_until
	var stunting_other := _stunt_p < 1.0 and _stunt_glyph >= 0 and i != _stunt_glyph
	var talking := (_t - _talk_t0) < _talk_dur and (i == _talk_a or i == _talk_b)
	var sleepy := (_t - _wake_t) > 25.0 and not pointer_on and irr_k <= 0.0 and cower <= 0.1
	var amazed := (_t - _amaze_t0) < _amaze_dur
	var reacting := (_t - _react_t0) < 0.9 and i != _poked and _poked >= 0
	var duck_age := _t - _duck_t0
	var ducking := duck_age >= 0.0 and duck_age < 0.55
	# Being petted: blissful closed eyes for the digits under the stroking finger.
	if _petting and absf(anchor.x - _pet_x) < font_size * 0.9:
		happy = true
	# Tickled: the whole cast giggles.
	if (_t - _giggle_t0) >= 0.0 and (_t - _giggle_t0) < 1.3:
		happy = true
	# Mid-sneeze the sneezer's eyes slam shut.
	if i == _stunt_glyph and _stunt_kind == 6 and _stunt_p > 0.35 and _stunt_p < 0.75:
		blinking = true
	# The scuffle: fighters wear full fury; everyone else is a gawping spectator.
	var brawl_on := (_t - _brawl_t0) < _BRAWL_DUR
	var fighting := brawl_on and (i == _brawl_a or i == _brawl_b)
	# The digit's private quirk face: the 0's joy-hop squint, the 4's shut-eyed sigh.
	var qp := _quirk_p(i)
	if qp >= 0.0:
		match i % 4:
			1:
				happy = true
			2:
				blinking = blinking or (qp > 0.25 and qp < 0.8)
	# THIS digit's own temper: its personal poke-grudge stacked on the global huff.
	var my_anger := irr_k
	if i < _poke_anger.size():
		my_anger = maxf(my_anger, _poke_anger[i])
	if fighting:
		my_anger = 1.0
	var persona: Dictionary = PERSONA[i % PERSONA.size()]

	# --- Where this digit is looking (the priority chain above) ---
	# At rest: facing the player, plus a small SHARED wander so no stare goes
	# glassy. One phase for the whole word on purpose — the family glances
	# around together, which keeps all eight pupils (and their catchlights) in
	# the same relative spot; per-digit phases made each pair of eyes read as
	# its own design.
	var look: Vector2 = REST_GAZE[i % REST_GAZE.size()] \
		+ Vector2(sin(_t * 0.6), cos(_t * 0.45)) * 0.10
	if qp >= 0.0 and i % 4 == 0:
		# The shy 2's nervous glance: eyes dart around quickly during its quirk.
		look = Vector2(sin(_t * 7.0 + float(i)), cos(_t * 5.3)) * 0.5
	if sleepy:
		look = Vector2(0.0, 0.55)                        # pupils sink, half asleep
	if talking:
		var partner := _talk_b if i == _talk_a else _talk_a
		look = Vector2(clampf(float(partner - i), -1.0, 1.0) * 0.62, 0.12)
	if stunting_other:
		look = Vector2(clampf(float(_stunt_glyph - i), -1.0, 1.0) * 0.62, 0.10)
	if pointer_on:
		look = ((_last_mouse - anchor) / 260.0).limit_length(0.62)
	if reacting:
		# A sibling just got poked — everyone snaps to the victim, pointer or not.
		look = Vector2(clampf(float(_poked - i), -1.0, 1.0) * 0.62, 0.10)
	if amazed:
		# Wonder: eyes dart around, mostly upward — following the confetti.
		look = Vector2(sin(_t * 3.1 + float(i) * 1.1),
			-absf(cos(_t * 2.3 + float(i) * 1.7))) * 0.5
	if fighting:
		# Locked onto the opponent, nose to nose.
		var opp := _brawl_b if i == _brawl_a else _brawl_a
		look = Vector2(clampf(float(opp - i), -1.0, 1.0) * 0.62, 0.10)
	elif brawl_on:
		# Everyone else watches the fight.
		var midf := (float(_brawl_a) + float(_brawl_b)) * 0.5
		look = Vector2(clampf(midf - float(i), -1.0, 1.0) * 0.62, 0.08)
	if ducking:
		# Incoming tile! Everyone tracks the projectile.
		look = Vector2(clampf((_duck_from - anchor.x) / 240.0, -0.62, 0.62), -0.15)
	if cower > 0.1:
		look = Vector2(0.0, 0.7)                         # locked on the bomb
	if my_anger > 0.0:
		look += Vector2(sin(_t * 70.0) * 0.3 * my_anger, 0.0)

	# --- Brow mood --------------------------------------------------------------
	# One master resting height for the whole family; the persona contributes a
	# WHISPER (15%), so the 4 sits a hair lower-browed without wearing a
	# different face. Moods below still move brows freely — they're transient.
	var raise: float = 0.32 + float(persona["brow"]) * 0.15
	var anger := clampf(my_anger, 0.0, 1.0)              # inner ends slam down
	var one_brow := stunting_other or (talking and i == _talk_b)   # sceptical
	if cower > 0.1 or amazed or ducking:
		raise = 1.0                                      # scared / amazed: sky-high
	elif brawl_on and not fighting:
		raise = maxf(raise, 0.6)                         # ooh, a fight!
	elif happy:
		raise = maxf(raise, 0.6)
	elif sleepy:
		raise = -0.25                                    # brows sag low
	# Quirk brows: the shy 2's darting glance lifts them; the 4's sigh drops them.
	if qp >= 0.0:
		match i % 4:
			0:
				raise += 0.25
			2:
				raise = minf(raise, -0.4)
	# Giggling at the poked sibling — the easy-going squint; the grumps just stare.
	if reacting and float(persona["temper"]) < 0.6:
		happy = true

	var wide := 1.0 + 0.30 * maxf(maxf(cower, 0.8 if amazed else 0.0),
		maxf(0.9 if ducking else 0.0, 0.6 if (brawl_on and not fighting) else 0.0))
	# ONE FAMILY INK for brows, lashes and mouth — a warm near-black shared by
	# all four digits. It used to be a deep shade of each body's own hue, which
	# tinted the 2's lashes green and the 8's red: four feature colours reading
	# as four different faces. The flip to near-white survives for truly DARK
	# bodies only (the 2048 navy on some themes) — legibility outranks
	# uniformity there, and on those themes the whole word flips together.
	var hue_ink := Color(0.17, 0.11, 0.09)
	var ink := hue_ink
	if body_col.get_luminance() < 0.16:
		ink = Color(0.95, 0.97, 1.0)
	# Lashes are the ONE feature that never flips to white on a dark digit: they
	# ride the edge of the white sclera, so a deep ink always reads there — and a
	# pale lash line floating over the body reads as a second eyebrow.
	var lash_ink := hue_ink
	# The iris is a real three-tone toon iris — a deep rim, a saturated mid, and
	# a warmer lit crescent low down where light bounces up through it. ONE
	# shared warm espresso for the whole family: it sits on the white sclera, so
	# it reads on every body, and the per-digit body-hue irises it replaces
	# (green 2, red 8…) were the single loudest "four different eye designs" cue.
	# Reference eyes: a NEAR-BLACK bead of a pupil (a whisper of warm brown in
	# its rim and a lifted floor so it still reads as a sphere, never a flat dot).
	var iris_mid := Color(0.13, 0.09, 0.09)
	var iris_deep := Color(0.07, 0.05, 0.06)
	var iris_lit := Color(0.24, 0.16, 0.14)
	# Brows are PART of the master face: the reference family wears the same
	# thin high brow on all four digits at rest, so they always draw — moods
	# (anger, surprise, sleepiness, the sceptical one-brow …) move them rather
	# than summon them.
	var show_brow := true
	for s in [-1.0, 1.0]:
		var c := anchor + Vector2(s * sep, 0.0)
		if show_brow:
			# Brow: a short stroke above the eye. Raised with mood (the sceptical
			# one-brow raise lifts only the right one), inner end dropping with
			# anger. Drawn as a bowed, tapered band — a straight hairline reads as
			# a pencil mark where a real brow thickens through its middle.
			var b_raise := raise + (0.55 if one_brow and s > 0.0 else 0.0) \
				+ (float(persona.get("brow_r", 0.0)) if s > 0.0 else 0.0)
			var by := -r * (1.5 + 0.5 * b_raise)
			var drop := r * 0.5 * anger
			var p_in := c + Vector2(-s * r * 0.85, by + drop)
			var p_out := c + Vector2(s * r * 0.85, by - drop * 0.3)
			_brow(p_in, p_out, r * 0.22, ink, maxf(2.5, font_size * 0.020))

		var ex := r * wide                               # eye half-width
		var ey := r * wide                               # ROUND, like the reference
		# A raised lid — the angry squint after a poke, the drowsy droop — is
		# a CLOSED eye here: the half-lid (the body sliding down over the white)
		# read as an eyelid, which the family does not wear. One line, always.
		var lid := 0.0
		if my_anger > 0.05:
			lid = clampf(0.25 + 0.35 * my_anger, 0.0, 0.6)
		elif sleepy:
			lid = 0.42 + 0.06 * sin(_t * 0.9)
		if happy or blinking or lid > 0.0:
			# A closed eye is ONE thin line and nothing else — a gentle upward arc
			# for the happy squint, near-flat for a blink. No lid, no lash, no
			# crease: the tapered lash polygons were user-rejected as bad eyelids
			# ("just leave a line when the eyes are closed, that's all").
			# Happy arcs up; a blink is flat; an angry squint bows DOWN a touch.
			var bow := ey * (0.38 if happy else (-0.10 if my_anger > 0.05 else 0.06))
			_eye_line(c + Vector2(0.0, ey * 0.10), ex * 0.90, bow,
				lash_ink, maxf(2.0, fu * 0.014))
			continue
		# THE SOCKET: a soft dark bloom, so the eye sits IN the body rather than
		# being stuck on the front of it. This is the whole "set into the
		# material" effect — a dimple of shadow under the surface, with the
		# tile's streak and crown highlight then sweeping over the top of it.
		# Kept TIGHT: with the master face's bigger, closer-set eyes, the wide
		# 3.4× blooms of the two sockets overlapped between them and the overlap
		# read as a dark NOSE — a feature the family does not have.
		draw_texture_rect(CandyFace.glow_dot(),
			Rect2(c - Vector2(ex * 1.32, ey * 1.32), Vector2(ex * 2.64, ey * 2.64)),
			false, Color(0, 0, 0, 0.27))
		# Sclera, with the shadow the upper lid casts down onto it.
		_ellipse(c, ex, ey, Color(0.99, 0.99, 1.0))
		# (No lid shadow on the sclera and no lash stroke over it — both read as
		# eyelids, and the family wears NONE: a clean white, the pupil, the
		# catchlights and the brow. User-directed.)
		# The iris rides the look direction, kept inside the sclera. FULL on
		# purpose (0.74 of the eye) — a big dark iris filling most of the white
		# is the "cute" read; a small floating iris is the "startled" one.
		var pc := c + look * Vector2(ex, ey) * 0.24
		var ir := ex * 0.70
		draw_circle(pc, ir, iris_deep)                   # deep outer rim
		draw_circle(pc + Vector2(0.0, ir * 0.10), ir * 0.88, iris_mid)
		draw_circle(pc + Vector2(0.0, ir * 0.40), ir * 0.48, iris_lit)   # lit floor
		# Catchlights, the reference pair: one BIG primary up-left, one small
		# secondary down-right — the pair that sells wet, glossy eyes.
		draw_circle(pc + Vector2(-ir * 0.36, -ir * 0.38), ir * 0.30, Color(1, 1, 1, 0.98))
		draw_circle(pc + Vector2(ir * 0.40, ir * 0.40), ir * 0.13, Color(1, 1, 1, 0.75))
		# The glossy dome: a soft sheen across the upper half of the pupil, the
		# wet curve the reference eyes carry between the two catches.
		draw_texture_rect(CandyFace.glow_dot(),
			Rect2(pc.x - ir * 0.9, pc.y - ir * 1.05, ir * 1.8, ir * 1.1),
			false, Color(1, 1, 1, 0.10))
		# Lids (the digit's own colour sliding down), capped by their own lash line:
		# hard when angry, heavy when sleepy.
		# (An open eye wears no lash line and no half-lid — see above.)
		# SET INTO THE BODY, but SHARP: the deep socket already seats the eye
		# below the surface; over it lies only a thin veil of the digit's own
		# colour and a whisper of surface sheen. Heavy veils were user-rejected
		# — they ghosted the features, and a ghost face reads as printed on
		# frosted glass rather than moulded into a solid.
		_ellipse(c - Vector2(0.0, ey * 0.30), ex * 0.92, ey * 0.52,
			Color(body_col.r, body_col.g, body_col.b, 0.12))
		draw_texture_rect(CandyFace.glow_dot(),
			Rect2(c.x - ex * 0.8, c.y - ey * 1.05, ex * 1.6, ey * 0.7),
			false, Color(1, 1, 1, 0.13))
		# MOULDED IN: the body's surface curls back over the eye's lower edge —
		# a soft shadow crescent under it, so the eye sits in a hollow of the
		# digit rather than on its skin.
		draw_texture_rect(CandyFace.glow_dot(),
			Rect2(c.x - ex * 1.1, c.y + ey * 0.30, ex * 2.2, ey * 1.1),
			false, Color(0, 0, 0, 0.11))

	# --- Cheeks: the family blush ---------------------------------------------
	# One soft rose pad per side, identical on all four digits — same size, same
	# seat off the face band, same colours — always on. Subtle by design: they
	# support the face rather than dominate it (the "blush" costume layers its
	# sparkles over these same seats when a theme or the calendar asks).
	var ck := fu * 0.060
	for s2 in [-1.0, 1.0]:
		var cc := anchor + Vector2(s2 * fu * FACE_CHEEK_DX, fu * FACE_CHEEK_DY)
		draw_texture_rect(CandyFace.glow_dot(),
			Rect2(cc - Vector2(ck * 1.55, ck * 1.30), Vector2(ck * 3.1, ck * 2.6)),
			false, _CHEEK_SOFT)
		draw_texture_rect(CandyFace.glow_dot(),
			Rect2(cc - Vector2(ck * 0.95, ck * 0.80), Vector2(ck * 1.9, ck * 1.6)),
			false, _CHEEK_CORE)

	# --- Mouth: the rest of the face ------------------------------------------
	# One mouth per digit, below the eyes, sharing the same mood chain:
	# "O" gasp (amazed / ducking / cowering) → gritted teeth (angry) → open grin
	# (happy / petted) → slow yawns (sleepy) → the family's resting smile.
	# The SAME seat and size for every digit, hung off the face band in face
	# units — the 8 included, so the four faces read as one family.
	var mc := anchor + Vector2(0.0, fu * FACE_MOUTH_DY)
	var mr := fu * 0.058
	var mw := maxf(2.0, fu * 0.014)
	# The expression is PERSONA-FLAVOURED: the same situation pulls a different
	# mouth per digit — the shy 2 worries, the goofy 0 sticks its tongue out, the
	# grumpy 4 goes flat and unimpressed, the chill 8 smirks.
	var pid := i % 4
	var mouth := "rest"
	if fighting:
		mouth = "shout"                                  # both fighters yell
	elif my_anger > 0.3:
		mouth = "teeth"
	elif amazed or ducking or cower > 0.1:
		match pid:
			0: mouth = "worry"                           # the 2 wobbles with fear
			1: mouth = "tongue" if amazed else "o"       # the 0 ENJOYS chaos
			_: mouth = "o"
	elif brawl_on:
		mouth = ["worry", "grin", "flat", "rest"][pid]   # spectating a fight
	elif happy:
		mouth = "tongue" if pid == 1 else "grin"
	elif sleepy:
		mouth = "yawn"
	elif stunting_other:
		mouth = ["o_small", "grin", "flat", "rest"][pid]  # watching a trick
	# (the 8 used to smirk at rest — now it wears the same gentle persona bow
	# as everyone else, just sized/positioned for its solid waist)
	# The mouth's own socket, under it exactly as the eyes have one — the dimple
	# that says the feature is moulded INTO the body rather than drawn on.
	draw_texture_rect(CandyFace.glow_dot(),
		Rect2(mc - Vector2(mr * 1.9, mr * 1.25), Vector2(mr * 3.8, mr * 2.5)),
		false, Color(0, 0, 0, 0.20))
	_draw_mouth(mouth, mc, mr, mw, ink, float(persona["smile"]), float(persona.get("tongue", 0.62)))
	# The lower lip's shadow on the chin: the mouth is a hollow in the body, and a
	# hollow darkens the skin just beneath its lip.
	draw_texture_rect(CandyFace.glow_dot(),
		Rect2(mc.x - mr * 1.3, mc.y + mr * 0.25, mr * 2.6, mr * 1.3),
		false, Color(0, 0, 0, 0.12))
	# The mouth is set into the body at the same depth as the eyes: its own soft
	# socket underneath, a thin veil of the body's colour over it, and a whisper
	# of surface sheen — matched to theirs, or the smile floats on the surface
	# while the eyes sit inside.
	_ellipse(mc - Vector2(0.0, mr * 0.35), mr * 1.55, mr * 0.85,
		Color(body_col.r, body_col.g, body_col.b, 0.09))
	draw_texture_rect(CandyFace.glow_dot(),
		Rect2(mc.x - mr * 1.3, mc.y - mr * 1.15, mr * 2.6, mr * 1.15),
		false, Color(1, 1, 1, 0.06))

## The inside of an open mouth. A deep red-brown, NOT black — a black hole in the
## face is the thing that makes drawn mouths look like stickers.
const _THROAT := Color(0.24, 0.055, 0.10)
const _TONGUE := Color(0.90, 0.36, 0.47)

## A real open mouth, layered the way a 3D toddler cartoon builds one: the dark
## throat, a white upper tooth row tucked under the top lip, a fat tongue rolling
## up off the floor, a lip line around the whole opening and a wet gleam on the
## lower lip. `flat_top` squares the upper lip into a grin (0 leaves a round "O"),
## `tongue` is how far the tongue rides up (0 = out of sight at the back, 1 =
## lolling over the bottom lip).
func _draw_open(mc: Vector2, hw: float, hh: float, ink: Color, teeth: bool,
		tongue: float, flat_top: float) -> void:
	var n := 30
	var shape := PackedVector2Array()
	for k in n:
		var a := TAU * float(k) / float(n)
		var p := Vector2(cos(a) * hw, sin(a) * hh)
		if p.y < 0.0:
			# Ease the top toward a straight lip line: a grin is flat on top and
			# round underneath, where a gasp stays a full oval.
			p.y = lerpf(p.y, -hh * 0.58, flat_top)
		shape.append(mc + p)
	draw_colored_polygon(shape, _THROAT)
	# The tongue: a fat rounded pad low in the mouth with its own lit crown and a
	# soft centre crease, rising with `tongue`.
	var ty := mc.y + hh * lerpf(0.58, -0.10, clampf(tongue, 0.0, 1.0))
	var trx := hw * 0.62
	var try_ := hh * 0.52
	_ellipse(Vector2(mc.x, ty), trx, try_, _TONGUE)
	_ellipse(Vector2(mc.x, ty + try_ * 0.10), trx * 0.80, try_ * 0.72,
		_TONGUE.lightened(0.18))
	draw_line(Vector2(mc.x, ty - try_ * 0.55), Vector2(mc.x, ty + try_ * 0.25),
		Color(0.72, 0.24, 0.34, 0.55), maxf(1.5, hh * 0.06), true)
	if teeth:
		# The upper row: a band hugging the top lip, its lower edge bowed down,
		# with faint separators. Drawn AFTER the tongue — the teeth overlap it.
		var top_y := mc.y - hh * (0.58 if flat_top > 0.5 else 0.86)
		var band := hh * 0.34
		var tw := hw * (0.86 if flat_top > 0.5 else 0.62)
		var row := PackedVector2Array()
		var steps := 12
		for k in steps + 1:
			var f := float(k) / float(steps)
			row.append(Vector2(mc.x + lerpf(-tw, tw, f), top_y))
		for k in steps + 1:
			var f := float(k) / float(steps)
			var fx := 1.0 - f
			row.append(Vector2(mc.x + lerpf(-tw, tw, fx),
				top_y + band * (0.55 + 0.45 * sin(PI * fx))))
		draw_colored_polygon(row, Color(0.98, 0.97, 0.95))
		for tx in [-0.34, 0.0, 0.34]:
			var gx: float = mc.x + tw * float(tx)
			draw_line(Vector2(gx, top_y + band * 0.10), Vector2(gx, top_y + band * 0.74),
				Color(0.74, 0.70, 0.72, 0.55), maxf(1.2, hh * 0.04), true)
	# The lip line around the opening, and the wet gleam catching the lower lip.
	var rim := PackedVector2Array(shape)
	rim.append(shape[0])
	draw_polyline(rim, Color(ink.r, ink.g, ink.b, 0.55), maxf(1.5, hh * 0.09), true)
	draw_line(mc + Vector2(-hw * 0.34, hh * 0.80), mc + Vector2(hw * 0.30, hh * 0.80),
		Color(1, 1, 1, 0.22), maxf(1.5, hh * 0.10), true)

## Draws one mouth expression centred at `mc`. `mr` scales it, `mw` is the stroke
## width, `col` the ink, `sm` the persona's resting smile (+smile / −frown).
func _draw_mouth(kind: String, mc: Vector2, mr: float, mw: float, col: Color, sm: float,
		tongue: float = 0.62) -> void:
	match kind:
		"o":
			_draw_open(mc, mr * 0.62, mr * 0.74, col, false, 0.18, 0.0)
		"o_small":
			_draw_open(mc, mr * 0.42, mr * 0.50, col, false, 0.12, 0.0)
		"shout":                                         # a wide, tall open yell
			_draw_open(mc, mr * 0.74, mr * 1.02, col, true, 0.30, 0.30)
		"teeth":                                         # gritted: a clenched tooth row
			var slit := Rect2(mc - Vector2(mr * 0.95, mr * 0.34),
				Vector2(mr * 1.9, mr * 0.68))
			draw_rect(slit, _THROAT)
			# The tooth row itself, inset inside the dark slit so the gums read.
			var trow := Rect2(slit.position + Vector2(mr * 0.06, mr * 0.07),
				slit.size - Vector2(mr * 0.12, mr * 0.14))
			draw_rect(trow, Color(0.98, 0.97, 0.95))
			for tx in [-0.30, 0.0, 0.30]:
				var gx: float = mc.x + mr * 1.9 * float(tx)
				draw_line(Vector2(gx, trow.position.y), Vector2(gx, trow.end.y),
					Color(0.72, 0.68, 0.70, 0.75), maxf(1.5, mw * 0.5), true)
			draw_polyline(PackedVector2Array([slit.position, Vector2(slit.end.x, slit.position.y),
				slit.end, Vector2(slit.position.x, slit.end.y), slit.position]),
				Color(col.r, col.g, col.b, 0.55), maxf(1.5, mw * 0.6), true)
		"grin":                                          # a real open smile
			_draw_open(mc, mr * 1.16, mr * 0.82, col, true, 0.28, 1.0)
		"tongue":                                        # grin with a cheeky tongue
			_draw_open(mc, mr * 1.16, mr * 0.88, col, true, 0.92, 1.0)
		"worry":                                         # a nervous wavy line
			var prev := mc + Vector2(-mr, 0.0)
			for s in range(1, 13):
				var fx := float(s) / 11.0
				var p := mc + Vector2(lerpf(-mr, mr, fx), sin(fx * TAU * 1.5) * mr * 0.22)
				draw_line(prev, p, col, mw, true)
				prev = p
		"flat":                                          # unimpressed — real closed lips
			_draw_lips(mc, mr * 1.20, 0.0, mr * 0.40, col)
		"smirk":                                         # flat left, curling up right
			var prev := mc + Vector2(-mr * 0.85, mr * 0.05)
			for s in range(1, 11):
				var fx := float(s) / 9.0
				var p := mc + Vector2(lerpf(-mr * 0.85, mr * 0.85, fx), mr * 0.05 - mr * 0.55 * fx * fx)
				draw_line(prev, p, col, mw, true)
				prev = p
		"yawn":                                          # slowly opening/closing
			var yawn := maxf(0.0, sin(_t * 0.55))
			_draw_open(mc, mr * (0.40 + 0.18 * yawn), mr * (0.30 + 0.62 * yawn),
				col, false, 0.24, 0.0)
		_:                                               # rest — the family smile
			# ONE resting mouth for the whole family: a small open smile (flat
			# top, round underneath, the tongue just showing) — the reference's
			# master mouth. The persona flavours it by a few percent of width
			# and openness, never with its own construction: the closed-lips /
			# smirk mouths this replaces gave every digit a different resting
			# mouth, which is exactly the "four unrelated mascots" read.
			var f := clampf(sm, 0.0, 1.3)
			_draw_open(mc, mr * (1.02 + 0.07 * f), mr * (0.74 + 0.05 * f),
				col, false, tongue, 1.0)

## A real closed mouth: a filled crescent — the lip line curves through tapered
## corners (curled up for a smile, down for a frown) and is thickest at the
## middle, so it reads as actual lips where a hairline arc read as a pencil
## stroke. `curl` is how far the corners sit above (+) or below (−) the centre.
func _draw_lips(mc: Vector2, half_w: float, curl: float, thick: float, col: Color) -> void:
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	var n := 16
	for k in n + 1:
		var fx := float(k) / float(n)
		var xx := lerpf(-half_w, half_w, fx)
		var cy := -curl * pow(fx * 2.0 - 1.0, 2.0)
		# Tapered thickness (kept a hair above zero so the polygon never collapses
		# into degenerate corner points the triangulator could choke on).
		var w := maxf(thick * pow(maxf(sin(PI * fx), 0.0), 0.7), thick * 0.06)
		top.append(mc + Vector2(xx, cy - w * 0.5))
		bot.append(mc + Vector2(xx, cy + w * 0.5))
	var poly := PackedVector2Array()
	poly.append_array(top)
	for k in range(bot.size() - 1, -1, -1):
		poly.append(bot[k])
	# The shadow the lip casts on the chin: without it a pale lip on a dark digit
	# reads as a scratch rather than a mouth.
	var drop := PackedVector2Array()
	for pnt in poly:
		drop.append(pnt + Vector2(0.0, thick * 0.42))
	draw_colored_polygon(drop, Color(0, 0, 0, 0.20))
	draw_colored_polygon(poly, col)
	# A soft catch-light along the lower lip — the same wet gleam the eyes carry,
	# so the mouth reads as real glossy lips rather than painted-on ink.
	draw_line(mc + Vector2(-half_w * 0.42, thick * 0.72),
		mc + Vector2(half_w * 0.42, thick * 0.72),
		Color(1, 1, 1, 0.22), maxf(2.0, thick * 0.18), true)

# --- Theme goods (costumes) ----------------------------------------------------
## Per-digit accessories for the active theme, drawn inside the glyph's own
## transform so props ride every hop, dance and shiver. Word-level goods
## (bubbles, the orbiting star) live in _draw_extras below.
func _draw_dress(i: int, pos: Vector2, adv: float) -> void:
	if dress.is_empty():
		return
	var fs := float(font_size)
	var cx := pos.x + adv * 0.5
	var ch := text[i] if i < text.length() else "0"
	var fit := _acc_fit(ch)
	# Where props seat on THIS digit (absolute canvas coords, inside the glyph xf):
	#   cap    — the top-of-head point a hat rests on (nudged to the digit's mass)
	#   neck_y — the band height for a scarf (the 8 ties at its waist)
	#   ear_y  — ear height for the earmuff cups
	var cap := Vector2(cx + adv * float(fit["cap_dx"]), pos.y + fs * float(fit["cap_y"]))
	var neck_y: float = pos.y + fs * float(fit["scarf_y"])
	var neck_w: float = adv * float(fit["scarf_w"])
	var ear_y: float = pos.y + fs * float(fit["ear_y"])
	match dress:
		"scarf":
			# The winter set — each digit wears its OWN piece, fitted to its body:
			# a red scarf on the 2's base, a knit beanie on the 0's dome, earmuffs
			# over the 4, a gold scarf tied at the 8's waist.
			match i % 4:
				0: _draw_scarf(i, cx, neck_y, adv, fs, neck_w, Color("C94F45"))
				1: _draw_beanie(i, cap, adv, fs)
				2: _draw_earmuffs(i, cap, ear_y, adv, fs)
				3: _draw_scarf(i, cx, neck_y, adv, fs, neck_w, Color("E0AE43"))
		"crown":
			# One crown, worn by the last digit — the 2048 gold itself.
			if i == text.length() - 1:
				_draw_crown(cap, adv, fs)
		"leaf":
			# Leaves perch on alternating digits so the word isn't a hedge.
			if (i % 2) == 0:
				_draw_leaf(i, Vector2(cap.x + adv * 0.30, cap.y + fs * 0.03), fs)
		"blush":
			# The costume AMPLIFIES the master face's always-on cheeks — same
			# seats off the face band, bigger and sparklier — rather than
			# painting a second pair somewhere else (two blushes read as a smudge).
			var fa := _face_anchor(pos, ch)
			_draw_blush(fa.x, fa.y + fs * FACE_CHEEK_DY, adv, fs)

## Per-glyph accessory FIT — where each prop seats on THIS digit's body, so it
## reads as worn rather than pasted. All in font-size units up from the baseline
## (y) or fractions of the glyph advance (x / widths):
##   cap_y   — top-of-head seat for hats (crown / beanie)
##   cap_dx  — horizontal nudge to the digit's visual centre (the 4 leans right)
##   cap_w   — half-width of the head at the cap
##   scarf_y — the scarf band's height (the 8 ties at its waist, the 2 at its base)
##   scarf_w — half-width of the scarf band
##   ear_y   — ear height for the earmuff cups
const _ACC_FIT := {
	"2": {"cap_y": -0.60, "cap_dx": 0.00, "cap_w": 0.32, "scarf_y": -0.05, "scarf_w": 0.48, "ear_y": -0.40},
	"0": {"cap_y": -0.66, "cap_dx": 0.00, "cap_w": 0.32, "scarf_y": -0.09, "scarf_w": 0.44, "ear_y": -0.42},
	"4": {"cap_y": -0.63, "cap_dx": 0.07, "cap_w": 0.26, "scarf_y": -0.05, "scarf_w": 0.44, "ear_y": -0.40},
	"8": {"cap_y": -0.66, "cap_dx": 0.00, "cap_w": 0.32, "scarf_y": -0.05, "scarf_w": 0.44, "ear_y": -0.42},
}

func _acc_fit(ch: String) -> Dictionary:
	return _ACC_FIT.get(ch, {"cap_y": -0.63, "cap_dx": 0.0, "cap_w": 0.30,
		"scarf_y": -0.06, "scarf_w": 0.46, "ear_y": -0.41})

## A plush knitted scarf wrapping the digit's neck/base: a chunky 2-tone wool band
## shaded as a fat round tube (bright top roll, deep lower fold), with fat rib
## columns, a fat layered knot at the front and ONE full tapering tail with a soft
## fringe. Seated LOW (its `y` fit) so it wraps the base clear of the face.
func _draw_scarf(i: int, cx: float, y: float, _adv: float, fs: float,
		w_half: float, main: Color) -> void:
	var light := main.lightened(0.24)
	var glow := main.lightened(0.46)
	var dark := main.darkened(0.30)
	var deep := main.darkened(0.50)
	var h := fs * 0.076                       # chunky band half-thickness at the front
	var bow := fs * 0.030                     # how far the band dips at the front
	# One edge function drives every strip so they share the same wrap. `e` runs
	# -1 (top edge) .. +1 (bottom edge); the band thins as it turns off the sides.
	var edge := func(fx: float, e: float) -> Vector2:
		var b := sin(fx * PI)                 # 0 at the ends, 1 at the front
		var half := h * (0.5 + 0.5 * b)
		var xx := cx - w_half + fx * w_half * 2.0
		var yy := y + b * bow + sin(fx * TAU + _t * 1.1 + float(i)) * fs * 0.0025
		return Vector2(xx, yy + e * half)
	var strip := func(e0: float, e1: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var n := 24
		for k in n + 1:
			pts.append(edge.call(float(k) / float(n), e0))
		for k in n + 1:
			pts.append(edge.call(1.0 - float(k) / float(n), e1))
		return pts
	# Soft drop shadow onto the digit body, just under the band.
	draw_colored_polygon(strip.call(0.5, 1.8), Color(0, 0, 0, 0.15))
	# Wool body shaded as a fat round tube: mid fill, a broad lit upper crown, a
	# bright top gleam, then a shaded lower fold and a deep base shadow.
	draw_colored_polygon(strip.call(-1.0, 1.0), main)
	draw_colored_polygon(strip.call(-1.0, 0.15), light)
	draw_colored_polygon(strip.call(-1.0, -0.5), glow)
	draw_colored_polygon(strip.call(0.5, 1.0), dark)
	draw_colored_polygon(strip.call(0.82, 1.0), deep)
	# Fat knit rib columns: chunky alternating light/shadow vertical stitches.
	for k in 18:
		var fx := (float(k) + 0.5) / 18.0
		var top: Vector2 = edge.call(fx, -0.9)
		var bot: Vector2 = edge.call(fx, 0.9)
		var shade: Color = glow if (k % 2 == 0) else deep
		draw_line(top, bot, Color(shade.r, shade.g, shade.b, 0.5),
			maxf(1.6, fs * 0.010), true)
	# A bright knit-row highlight tracing the top roll and a deep seam along the base.
	var hi := PackedVector2Array()
	var lo := PackedVector2Array()
	for k in 25:
		var fx := float(k) / 24.0
		hi.append(edge.call(fx, -0.6))
		lo.append(edge.call(fx, 0.72))
	draw_polyline(hi, Color(glow.r, glow.g, glow.b, 0.7), maxf(1.6, fs * 0.008), true)
	draw_polyline(lo, Color(deep.r, deep.g, deep.b, 0.5), maxf(1.6, fs * 0.008), true)
	# Rounded dark seams where the band turns out of sight at each end.
	draw_line(edge.call(0.015, -1.0), edge.call(0.015, 1.0),
		Color(deep.r, deep.g, deep.b, 0.6), maxf(1.8, fs * 0.010), true)
	draw_line(edge.call(0.985, -1.0), edge.call(0.985, 1.0),
		Color(deep.r, deep.g, deep.b, 0.6), maxf(1.8, fs * 0.010), true)
	# --- The knot + a single hanging tail (draped onto the front-left shoulder,
	# so a base tie like the 8's falls beside the digit rather than over the face) ---
	var sway := sin(_t * 1.3 + float(i) * 1.1) * 0.10
	var kp: Vector2 = edge.call(0.34, 0.30)
	var dirv := Vector2(-0.22 + sin(sway) * 0.5, 1.0).normalized()
	var perp := Vector2(-dirv.y, dirv.x)
	var tl := fs * 0.26
	var w0 := fs * 0.062                      # tail half-width at the knot
	var w1 := fs * 0.046                      # …and down at the fringe
	var a0 := kp + dirv * fs * 0.02
	var aend := a0 + dirv * tl
	# tail drop shadow, offset down the drape direction.
	draw_colored_polygon(PackedVector2Array([
		a0 - perp * w0 + dirv * fs * 0.02, a0 + perp * w0 + dirv * fs * 0.02,
		aend + perp * w1 + dirv * fs * 0.03, aend - perp * w1 + dirv * fs * 0.03]),
		Color(0, 0, 0, 0.13))
	# tail cloth (mid), then a lit left edge + a shaded right edge for round volume.
	draw_colored_polygon(PackedVector2Array([
		a0 - perp * w0, a0 + perp * w0,
		aend + perp * w1, aend - perp * w1]), main)
	draw_colored_polygon(PackedVector2Array([
		a0 - perp * w0, a0 - perp * w0 * 0.22,
		aend - perp * w1 * 0.22, aend - perp * w1]), glow)
	draw_colored_polygon(PackedVector2Array([
		a0 + perp * w0 * 0.28, a0 + perp * w0,
		aend + perp * w1, aend + perp * w1 * 0.28]), dark)
	# knit rib lines running down the tail (lit on the left, shaded on the right).
	for r in [-0.56, -0.19, 0.19, 0.56]:
		var rl: Color = glow if (float(r) < 0.0) else deep
		draw_line(a0 + perp * w0 * float(r), aend + perp * w1 * float(r),
			Color(rl.r, rl.g, rl.b, 0.4), maxf(1.3, fs * 0.006), true)
	# the knot: a fat layered wrap over the band-to-tail join, lit on top.
	draw_circle(kp + dirv * fs * 0.014 + perp * fs * 0.004, fs * 0.052, deep)
	draw_circle(kp + dirv * fs * 0.008, fs * 0.045, dark)
	draw_circle(kp + dirv * fs * 0.002 - perp * fs * 0.006, fs * 0.033, main)
	draw_circle(kp - perp * fs * 0.010 - dirv * fs * 0.006, fs * 0.017,
		Color(glow.r, glow.g, glow.b, 0.85))
	draw_circle(kp - perp * fs * 0.016 - dirv * fs * 0.012, fs * 0.007,
		Color(1, 1, 1, 0.7))
	# fringe: a fuller fan of short two-tone yarn strands off the tail end.
	for k in 6:
		var fo := aend + perp * (w1 * (0.85 - 0.34 * float(k)))
		var fdir := dirv.rotated((float(k) - 2.5) * 0.10)
		var fl := fs * (0.038 + 0.006 * sin(float(k) * 1.7))
		draw_line(fo, fo + fdir * fl, dark, maxf(1.4, fs * 0.007), true)
		draw_line(fo, fo + fdir * fl * 0.7, Color(main.r, main.g, main.b, 0.75),
			maxf(1.1, fs * 0.004), true)

## A plush knit beanie hugging the digit's cap: a domed crown with a lit crown and
## a shaded far side, fat knit gore ribs, a thick folded cream brim with chunky rib,
## and a big fluffy layered pom-pom on top.
func _draw_beanie(i: int, cap: Vector2, adv: float, fs: float) -> void:
	var bob := sin(_t * 1.3 + float(i)) * fs * 0.005
	var c := Vector2(cap.x, cap.y + bob)
	var w := adv * 0.44                        # dome half-width
	var dome_h := fs * 0.25
	var main := Color("3FA79A")
	var lit := main.lightened(0.30)
	var glow := main.lightened(0.5)
	var dark := main.darkened(0.32)
	var brim := Color("F0E8D7")
	var brim_lit := Color("FFFCF3")
	var brim_dark := Color("D2C6AC")
	var base_y := c.y + fs * 0.02              # brim seats slightly into the cap
	var tip := Vector2(c.x + w * 0.10, base_y - dome_h)   # a hint of slouch
	# --- domed crown (half-ellipse blended toward the slouched tip) ---
	var dome := PackedVector2Array()
	var n := 22
	for k in n + 1:
		var a := PI + PI * float(k) / float(n)
		var t := float(k) / float(n)
		var p := Vector2(c.x + cos(a) * w, base_y + sin(a) * dome_h)
		p.x += (tip.x - c.x) * sin(t * PI) * 0.5
		dome.append(p)
	draw_colored_polygon(dome, main)
	# Shaded far (lower-right) side of the dome — it turns away from the light.
	var shp := PackedVector2Array()
	for k in n + 1:
		var a := PI + PI * (0.5 + 0.5 * float(k) / float(n))
		shp.append(Vector2(c.x + cos(a) * w, base_y + sin(a) * dome_h))
	shp.append(Vector2(c.x, base_y))
	draw_colored_polygon(shp, Color(dark.r, dark.g, dark.b, 0.42))
	# Lit upper-left crown (the light hits upper-left everywhere in-app).
	var litp := PackedVector2Array()
	for k in n + 1:
		var a := PI + PI * 0.5 * float(k) / float(n)
		litp.append(Vector2(c.x + cos(a) * w * 0.92, base_y + sin(a) * dome_h * 0.92))
	litp.append(Vector2(c.x, base_y))
	draw_colored_polygon(litp, Color(lit.r, lit.g, lit.b, 0.55))
	# Fat knit gore ribs fanning up into the tip, alternating lit/shaded columns.
	for gk in [-0.74, -0.48, -0.22, 0.04, 0.3, 0.56]:
		var g0 := Vector2(c.x + float(gk) * w, base_y)
		var prev := g0
		var rib_col: Color = glow if (float(gk) < -0.08) else dark
		for k in range(1, 8):
			var t := float(k) / 7.0
			var p := g0.lerp(tip, t) + Vector2(sin(t * PI) * float(gk) * w * -0.12, 0.0)
			draw_line(prev, p, Color(rib_col.r, rib_col.g, rib_col.b, 0.4),
				maxf(1.4, fs * 0.007), true)
			prev = p
	# A bright gleam arcing over the crown.
	draw_arc(Vector2(c.x - w * 0.14, base_y - dome_h * 0.18), dome_h * 0.92,
		PI * 1.14, PI * 1.6, 12, Color(glow.r, glow.g, glow.b, 0.5), maxf(1.6, fs * 0.008), true)
	# --- folded brim: a thick rounded cream band across the base ---
	var bw := w * 1.08
	draw_line(Vector2(c.x - bw, base_y + fs * 0.006), Vector2(c.x + bw, base_y + fs * 0.006),
		brim_dark, fs * 0.094, true)
	draw_line(Vector2(c.x - bw, base_y - fs * 0.004), Vector2(c.x + bw, base_y - fs * 0.004),
		brim, fs * 0.070, true)
	draw_line(Vector2(c.x - bw * 0.94, base_y - fs * 0.022),
		Vector2(c.x + bw * 0.94, base_y - fs * 0.022), brim_lit, fs * 0.018, true)
	# chunky rib ticks on the brim
	for k in 13:
		var bx := lerpf(c.x - bw * 0.88, c.x + bw * 0.88, float(k) / 12.0)
		draw_line(Vector2(bx, base_y - fs * 0.036), Vector2(bx, base_y + fs * 0.038),
			Color(brim_dark.r, brim_dark.g, brim_dark.b, 0.55), maxf(1.3, fs * 0.006), true)
	# --- big fluffy pom-pom on the tip: layered cream yarn ball ---
	var pc := tip + Vector2(0.0, -fs * 0.04)
	draw_circle(pc + Vector2(fs * 0.006, fs * 0.008), fs * 0.056, brim_dark)      # shadow base
	# fluffy outer tufts ringing the ball
	for k in 12:
		var a := TAU * float(k) / 12.0
		draw_circle(pc + Vector2(cos(a), sin(a)) * fs * 0.044, fs * 0.019,
			brim if (k % 2 == 0) else brim_dark)
	draw_circle(pc, fs * 0.048, brim)
	# wound-yarn arcs for a knit read
	for ya in [0.2, 1.3, 2.4, 3.5, 4.6, 5.7]:
		draw_arc(pc, fs * 0.030, float(ya), float(ya) + 0.85, 8,
			Color(brim_dark.r, brim_dark.g, brim_dark.b, 0.55), maxf(1.2, fs * 0.005), true)
	draw_circle(pc + Vector2(-fs * 0.014, -fs * 0.016), fs * 0.016, Color(1, 1, 1, 0.95))

## Headphone-style earmuffs: a thick sprung two-tone band arcing over the cap down
## to a deep plush cup at each ear — a double pile of fuzzy tufts ringing a cushioned
## centre, lit with a soft cushion glow and a specular.
func _draw_earmuffs(_i: int, cap: Vector2, ear_y: float, adv: float, fs: float) -> void:
	var band := Color("7B5FC9")
	var band_lit := band.lightened(0.36)
	var band_dark := band.darkened(0.30)
	var fur := Color("A98BE6")
	var fur_lit := fur.lightened(0.26)
	var fur_glow := fur.lightened(0.44)
	var fur_dark := fur.darkened(0.3)
	var ex := adv * 0.42                        # cup offset from the digit centre
	var pr := fs * 0.066                        # plush cup radius
	var apex := Vector2(cap.x, cap.y - fs * 0.04)
	var pL := Vector2(cap.x - ex, ear_y - pr * 0.5)
	var pR := Vector2(cap.x + ex, ear_y - pr * 0.5)
	# --- the sprung band: a quadratic from cup-top over the apex to cup-top,
	# stacked shadow / body / highlight for a rounded metal-and-pad read ---
	var band_pts := PackedVector2Array()
	var n := 24
	for k in n + 1:
		var t := float(k) / float(n)
		var u := 1.0 - t
		band_pts.append(pL * (u * u) + apex * (2.0 * u * t) + pR * (t * t))
	var band_sh := PackedVector2Array()
	for p in band_pts:
		band_sh.append(p + Vector2(0.0, fs * 0.008))
	draw_polyline(band_sh, Color(0, 0, 0, 0.13), maxf(3.5, fs * 0.026), true)
	draw_polyline(band_pts, band_dark, maxf(3.5, fs * 0.026), true)
	draw_polyline(band_pts, band, maxf(2.6, fs * 0.018), true)
	var band_hi := PackedVector2Array()
	for p in band_pts:
		band_hi.append(p + Vector2(0.0, -fs * 0.008))
	draw_polyline(band_hi, Color(band_lit.r, band_lit.g, band_lit.b, 0.9), maxf(1.6, fs * 0.008), true)
	# --- the two deep plush cups seated at ear height ---
	for s in [-1.0, 1.0]:
		var pc := Vector2(cap.x + float(s) * ex, ear_y)
		# a connector nub where the band meets the cup
		draw_circle(pc + Vector2(0.0, -pr * 0.96), pr * 0.42, band_dark)
		draw_circle(pc + Vector2(0.0, -pr * 0.96), pr * 0.30, band)
		# soft drop shadow under the cup
		draw_circle(pc + Vector2(fs * 0.006, fs * 0.008), pr * 1.02, Color(0, 0, 0, 0.12))
		# two rings of fuzzy tufts for a deep plush pile
		for k in 14:
			var a := TAU * float(k) / 14.0
			draw_circle(pc + Vector2(cos(a), sin(a)) * pr * 0.9, pr * 0.34, fur_dark)
		for k in 12:
			var a := TAU * (float(k) + 0.5) / 12.0
			draw_circle(pc + Vector2(cos(a), sin(a)) * pr * 0.7, pr * 0.3, fur)
		# cushioned centre: keep the lavender colour reading — a modest lit side and
		# a small soft specular rather than a washed-white core.
		draw_circle(pc, pr * 0.82, fur)
		draw_circle(pc + Vector2(-pr * 0.12, -pr * 0.12), pr * 0.5,
			Color(fur_lit.r, fur_lit.g, fur_lit.b, 0.7))
		draw_circle(pc + Vector2(-pr * 0.2, -pr * 0.22), pr * 0.24,
			Color(fur_glow.r, fur_glow.g, fur_glow.b, 0.55))
		draw_circle(pc + Vector2(-pr * 0.24, -pr * 0.26), pr * 0.12, Color(1, 1, 1, 0.7))

## A bigger, richer gold crown seated on the cap: a jewelled base band with a
## beaded rim and a diagonal sheen, five tall faceted points (lit left slope, dark
## right slope), five band gems and five tip jewels — each a faceted, sparkling
## stone drawn by CrownPainter._gem.
##
## BAKED: the crown is ~95 immediate canvas ops, and it ran on every redraw all
## year round on the treasure themes. It is rigid — its only motion is the bob
## below — so it is rendered ONCE into a texture (CrownBake: at the wearing
## digit's resting FAMILY_SCALE, under the same 2x MSAA the main viewport gives
## the live ops) and stamped here as ONE draw_texture_rect riding the same glyph
## transform + bob the live ops rode. Until the bake lands (a frame or two), the
## live ops keep drawing, so no frame ever misses its crown — the swap is proven
## texel-equivalent by tools/costume_bake_check.gd.
func _draw_crown(cap: Vector2, adv: float, fs: float) -> void:
	var bob := sin(_t * 1.1) * fs * 0.006
	var c := Vector2(cap.x, cap.y + bob)
	var fam: float = FAMILY_SCALE[(text.length() - 1) % FAMILY_SCALE.size()]
	var tex := _crown_skin(adv, fs, fam)
	if tex != null:
		# Rect sized from the TEXTURE (the bake target ceils to whole texels), so
		# texels map 1:1 back through the fam scale — sizing from the footprint
		# would smear every texel by the ceil()'d fraction.
		var foot := CrownPainter.rect_for(c, adv, fs)
		draw_texture_rect(tex, Rect2(foot.position,
			Vector2(float(tex.get_width()), float(tex.get_height())) / fam), false)
		return
	CrownPainter.paint(self, c, adv, fs)

# --- Crown bake state (one texture per layout; layout changes re-bake) ----------
var _crown_tex: ImageTexture
var _crown_key := Vector3(-1.0, -1.0, -1.0)   # (adv, fs, fam) the cached bake matches
var _crown_vp: CrownBake
var _crown_vp_frame := -1
# Latched when a readback yields nothing (headless host has no render target):
# the live path simply keeps drawing, exactly as before the bake existed.
var _crown_bake_dead := false

## The baked crown for this (adv, fs, fam), or null while it is not ready (the
## caller draws the live ops meanwhile). Kicks the bake on the first miss. No
## awaits anywhere on this path: the viewport is added deferred (this runs inside
## the draw pass) and collected on a later draw once it has certainly rendered.
func _crown_skin(adv: float, fs: float, fam: float) -> Texture2D:
	var key := Vector3(adv, fs, fam)
	if _crown_tex != null and _crown_key == key:
		return _crown_tex
	if _crown_bake_dead:
		return null
	if _crown_vp == null:
		_crown_key = key
		_crown_tex = null
		_crown_vp = CrownBake.new()
		_crown_vp.setup(adv, fs, fam)
		add_child.call_deferred(_crown_vp)
		_crown_vp_frame = Engine.get_frames_drawn()
		return null
	if _crown_key != key:
		# Layout moved mid-bake: drop the in-flight target; next draw re-kicks.
		_crown_vp.queue_free()
		_crown_vp = null
		return null
	if Engine.get_frames_drawn() < _crown_vp_frame + 2:
		return null                     # target not guaranteed rendered yet
	var tex := _crown_vp.collect()
	_crown_vp.queue_free()
	_crown_vp = null
	if tex == null:
		_crown_bake_dead = true
		return null
	_crown_tex = tex
	return _crown_tex

## The offscreen target the crown bakes into, and the readback that turns its
## premultiplied render into a straight-alpha texture the word can stamp through
## its ordinary mix blend (the word's canvas carries the gloss ShaderMaterial, so
## a premult-blend material cannot ride the stamp the way BallBakery's does).
class CrownBake extends SubViewport:
	var _fam := 1.0

	func setup(adv: float, fs: float, fam: float) -> void:
		_fam = fam
		var foot := CrownPainter.rect_for(Vector2.ZERO, adv, fs)
		size = Vector2i(int(ceil(foot.size.x * fam)), int(ceil(foot.size.y * fam)))
		transparent_bg = true
		disable_3d = true
		# Match the main viewport's msaa_2d = 2x so the baked edges carry the same
		# AA the live ops get. GLES3 has no 2D MSAA at all (the live ops render
		# without it there too — still matched), and setting it would only print a
		# warning per bake on device logs, so it is gated on the RUNNING renderer.
		if RenderingServer.get_current_rendering_method() != "gl_compatibility":
			msaa_2d = Viewport.MSAA_2X
		render_target_update_mode = SubViewport.UPDATE_ONCE
		var painter := CrownPainter.new()
		painter.bake_adv = adv
		painter.bake_fs = fs
		painter.bake_at = -foot.position
		add_child(painter)

	func _enter_tree() -> void:
		# Bake at the wearing digit's resting FAMILY_SCALE via the canvas
		# transform, so the on-screen stamp is ~1:1 texels at rest — the SAME ops
		# the live path draws, with line-width floors and AA landing identically.
		# Set HERE, not in setup(): before the viewport is in the tree its canvas
		# is not attached yet and the RenderingServer rejects the transform.
		canvas_transform = Transform2D().scaled(Vector2(_fam, _fam))

	## Premult -> straight alpha, in half-float texels so the un-premultiply stays
	## exact to well under an 8-bit step (a re-quantised RGBA8 divide would put
	## the fringe texels a step or two off the live ops). Returns null when there
	## is nothing to read (headless host).
	func collect() -> ImageTexture:
		var img := get_texture().get_image()
		if img == null or img.is_empty():
			return null
		img.convert(Image.FORMAT_RGBAH)
		for y in img.get_height():
			for x in img.get_width():
				var p := img.get_pixel(x, y)
				if p.a > 0.0001:
					img.set_pixel(x, y, Color(minf(p.r / p.a, 1.0),
						minf(p.g / p.a, 1.0), minf(p.b / p.a, 1.0), p.a))
		return ImageTexture.create_from_image(img)

## The crown's ops, verbatim from the pre-bake live path — one painter shared by
## the live fallback, the bake target and the equivalence probe, so all three are
## the same picture by construction.
class CrownPainter extends Node2D:
	var bake_adv := 0.0
	var bake_fs := 0.0
	var bake_at := Vector2.ZERO

	func _draw() -> void:
		paint(self, bake_at, bake_adv, bake_fs)

	## The stamp/bake footprint around the crown centre `c`: half-width covers the
	## body (adv * 0.46) plus the tip gems, cast shadow and AA feathers; the top
	## covers the point tips + their jewels, the bottom the band beads + shadow.
	static func rect_for(c: Vector2, adv: float, fs: float) -> Rect2:
		var half_w := adv * 0.46 + fs * 0.06
		return Rect2(c.x - half_w, c.y - fs * 0.32, half_w * 2.0, fs * 0.44)

	static func paint(ci: CanvasItem, c: Vector2, adv: float, fs: float) -> void:
		var w := adv * 0.46                         # half width (bigger)
		var gold := Color("F6C63C")
		var gold_lit := Color("FFEEAE")
		var gold_glow := Color("FFFBEA")
		var gold_dark := Color("B5791A")
		var gold_deep := Color("87590F")
		var base_y := c.y + fs * 0.02               # seats slightly into the cap
		var band_y := c.y - fs * 0.05               # where the band meets the points
		var tip_y := c.y - fs * 0.2                 # taller point tips
		var dip_y := c.y - fs * 0.055               # valleys between the points
		var L := c.x - w
		var R := c.x + w
		# --- silhouette: base band + five points ---
		var poly := PackedVector2Array([
			Vector2(L, base_y),
			Vector2(c.x, base_y + fs * 0.014),
			Vector2(R, base_y),
			Vector2(R, tip_y),
			Vector2(c.x + w * 0.75, dip_y),
			Vector2(c.x + w * 0.5, tip_y - fs * 0.008),
			Vector2(c.x + w * 0.25, dip_y),
			Vector2(c.x, tip_y - fs * 0.028),
			Vector2(c.x - w * 0.25, dip_y),
			Vector2(c.x - w * 0.5, tip_y - fs * 0.008),
			Vector2(c.x - w * 0.75, dip_y),
			Vector2(L, tip_y),
		])
		# soft cast shadow behind the whole crown
		var shp := PackedVector2Array()
		for p in poly:
			shp.append(p + Vector2(fs * 0.007, fs * 0.009))
		ci.draw_colored_polygon(shp, Color(0, 0, 0, 0.16))
		ci.draw_colored_polygon(poly, gold)
		# dark right-hand slopes of each point (the shaded facet side)
		var slopes_dark := [
			[Vector2(R, tip_y), Vector2(c.x + w * 0.75, dip_y)],
			[Vector2(c.x + w * 0.5, tip_y - fs * 0.008), Vector2(c.x + w * 0.25, dip_y)],
			[Vector2(c.x, tip_y - fs * 0.028), Vector2(c.x - w * 0.25, dip_y)],
			[Vector2(c.x - w * 0.5, tip_y - fs * 0.008), Vector2(c.x - w * 0.75, dip_y)],
		]
		for sd in slopes_dark:
			var seg: Array = sd
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			ci.draw_line(a, b, gold_dark, maxf(1.6, fs * 0.008), true)
		# lit left slopes of the points (catch the upper-left light)
		var slopes_lit := [
			[Vector2(L, tip_y), Vector2(c.x - w * 0.75, dip_y)],
			[Vector2(c.x - w * 0.5, tip_y - fs * 0.008), Vector2(c.x - w * 0.25, dip_y)],
			[Vector2(c.x, tip_y - fs * 0.028), Vector2(c.x + w * 0.25, dip_y)],
			[Vector2(c.x + w * 0.5, tip_y - fs * 0.008), Vector2(c.x + w * 0.75, dip_y)],
		]
		for sl in slopes_lit:
			var seg: Array = sl
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			ci.draw_line(a, b, gold_lit, maxf(1.5, fs * 0.007), true)
		# --- the base band, with a lit top fold and a bright diagonal sheen ---
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(L, base_y), Vector2(c.x, base_y + fs * 0.014), Vector2(R, base_y),
			Vector2(R, band_y), Vector2(c.x, band_y - fs * 0.006), Vector2(L, band_y)]), gold)
		ci.draw_line(Vector2(L, band_y), Vector2(c.x, band_y - fs * 0.006), gold_glow, maxf(1.6, fs * 0.007), true)
		ci.draw_line(Vector2(c.x, band_y - fs * 0.006), Vector2(R, band_y), gold_glow, maxf(1.6, fs * 0.007), true)
		ci.draw_line(Vector2(L + w * 0.22, base_y - fs * 0.006), Vector2(c.x + w * 0.12, band_y + fs * 0.004),
			Color(gold_glow.r, gold_glow.g, gold_glow.b, 0.7), maxf(1.4, fs * 0.006), true)
		# beaded lower rim of the band
		for bk in 9:
			var bx := lerpf(L + fs * 0.012, R - fs * 0.012, float(bk) / 8.0)
			ci.draw_circle(Vector2(bx, base_y + fs * 0.003), fs * 0.008, gold_lit)
		# dark rim outline
		ci.draw_polyline(poly + PackedVector2Array([poly[0]]), gold_deep, maxf(1.8, fs * 0.007), true)
		# --- five gems set into the band ---
		var gems := [Color("E5556E"), Color("58C6E8"), Color("6BD98C"), Color("58C6E8"), Color("E5556E")]
		for gi in 5:
			var gx := c.x + (float(gi) - 2.0) * w * 0.4
			var gy := (base_y + band_y) * 0.5
			var gcol: Color = gems[gi]
			_gem(ci, Vector2(gx, gy), fs * 0.023, gcol)
		# --- faceted jewel on each of the five point tips ---
		var tips := [Vector2(R, tip_y), Vector2(c.x + w * 0.5, tip_y - fs * 0.008),
			Vector2(c.x, tip_y - fs * 0.028), Vector2(c.x - w * 0.5, tip_y - fs * 0.008),
			Vector2(L, tip_y)]
		var tcols := [Color("58C6E8"), Color("E5556E"), Color("FFF1B0"), Color("E5556E"), Color("58C6E8")]
		for ti in 5:
			var tp: Vector2 = tips[ti]
			var tcol: Color = tcols[ti]
			_gem(ci, tp + Vector2(0.0, -fs * 0.008), fs * 0.026, tcol)

	## A faceted round jewel: a dark setting, the gem body, a shaded lower facet
	## and a bright upper facet, a crisp rim and a hot sparkle — so band + tip
	## stones read as cut gems rather than flat dots.
	static func _gem(ci: CanvasItem, ctr: Vector2, r: float, col: Color) -> void:
		var lit := col.lightened(0.42)
		var dark := col.darkened(0.42)
		ci.draw_circle(ctr + Vector2(0.0, r * 0.08), r * 1.14, Color(0, 0, 0, 0.28))   # setting shadow
		ci.draw_circle(ctr, r, col)
		# lower shaded facet
		ci.draw_colored_polygon(PackedVector2Array([
			ctr + Vector2(-r, 0.0), ctr + Vector2(r, 0.0), ctr + Vector2(0.0, r)]),
			Color(dark.r, dark.g, dark.b, 0.6))
		# upper lit facet
		ci.draw_colored_polygon(PackedVector2Array([
			ctr + Vector2(-r * 0.82, -r * 0.2), ctr + Vector2(r * 0.82, -r * 0.2),
			ctr + Vector2(0.0, -r * 0.92)]), Color(lit.r, lit.g, lit.b, 0.85))
		ci.draw_arc(ctr, r, 0.0, TAU, 16, Color(1, 1, 1, 0.32), maxf(1.0, r * 0.14), true)
		ci.draw_circle(ctr + Vector2(-r * 0.3, -r * 0.32), r * 0.22, Color(1, 1, 1, 0.95))

## A fuller little leaf with a stem, perched on a top corner and gently rocking.
## The blade is two quadratic sides meeting at base + tip; a shaded left half and a
## lit right half split along the midrib give it round volume, with a glossy streak,
## a central vein and several side veins. Hue leans on the theme accent.
func _draw_leaf(i: int, base: Vector2, fs: float) -> void:
	var rock := sin(_t * 1.2 + float(i) * 1.1) * 0.22
	var accent := ThemeManager.color("accent")
	var green := Color.from_hsv(lerpf(0.28, accent.h, 0.35), 0.58, 0.72)
	var green_lit := green.lightened(0.28)
	var green_glow := green.lightened(0.5)
	var green_dark := green.darkened(0.3)
	var vein := green.darkened(0.4)
	var stem := green.darkened(0.34)
	var l := fs * 0.2                            # longer blade
	var dirv := Vector2(0.34, -1.0).normalized().rotated(rock)
	var perp := Vector2(-dirv.y, dirv.x)
	var tip := base + dirv * l
	var wid := l * 0.5                           # fuller width
	var ctrl_r := base + dirv * l * 0.5 + perp * wid
	var ctrl_l := base + dirv * l * 0.5 - perp * wid
	# stem below the base, with a lit edge
	draw_line(base, base - dirv * fs * 0.04, stem, maxf(1.8, fs * 0.009), true)
	draw_line(base, base - dirv * fs * 0.03, Color(green_lit.r, green_lit.g, green_lit.b, 0.6),
		maxf(1.1, fs * 0.004), true)
	# blade: right side base->tip, then left side tip->base
	var blade := PackedVector2Array()
	var n := 14
	for k in n + 1:
		var t := float(k) / float(n)
		var u := 1.0 - t
		blade.append(base * (u * u) + ctrl_r * (2.0 * u * t) + tip * (t * t))
	for k in n + 1:
		var t := float(k) / float(n)
		var u := 1.0 - t
		blade.append(tip * (u * u) + ctrl_l * (2.0 * u * t) + base * (t * t))
	# drop shadow
	var shb := PackedVector2Array()
	for p in blade:
		shb.append(p + Vector2(fs * 0.006, fs * 0.008))
	draw_colored_polygon(shb, Color(0, 0, 0, 0.12))
	draw_colored_polygon(blade, green)
	# shaded left half (bounded by the left edge + the midrib)
	var left_half := PackedVector2Array()
	for k in n + 1:
		var t := float(k) / float(n)
		var u := 1.0 - t
		left_half.append(base * (u * u) + ctrl_l * (2.0 * u * t) + tip * (t * t))
	left_half.append(base)
	draw_colored_polygon(left_half, Color(green_dark.r, green_dark.g, green_dark.b, 0.4))
	# lit right half
	var right_half := PackedVector2Array()
	for k in n + 1:
		var t := float(k) / float(n)
		var u := 1.0 - t
		right_half.append(base * (u * u) + ctrl_r * (2.0 * u * t) + tip * (t * t))
	right_half.append(base)
	draw_colored_polygon(right_half, Color(green_lit.r, green_lit.g, green_lit.b, 0.55))
	# central vein + several side veins
	draw_line(base, tip, vein, maxf(1.6, fs * 0.007), true)
	for vk in [0.28, 0.46, 0.64, 0.82]:
		var mp := base.lerp(tip, float(vk))
		var vlen := l * 0.24 * (1.0 - float(vk) * 0.45)
		draw_line(mp, mp + (dirv * 0.5 + perp).normalized() * vlen, vein, maxf(1.1, fs * 0.004), true)
		draw_line(mp, mp + (dirv * 0.5 - perp).normalized() * vlen, vein, maxf(1.1, fs * 0.004), true)
	# a glossy highlight streak riding the lit side
	draw_line(base.lerp(tip, 0.24) + perp * wid * 0.4, base.lerp(tip, 0.72) + perp * wid * 0.22,
		Color(green_glow.r, green_glow.g, green_glow.b, 0.6), maxf(1.4, fs * 0.006), true)

## Soft kawaii cheek blush: a plush layered rosy glow on each cheek beside the
## mouth — a wide soft halo, a warmer mid, a rosy core — finished with a couple of
## bright little sparkles.
func _draw_blush(cx: float, y: float, _adv: float, fs: float) -> void:
	var gd := CandyFace.glow_dot()
	var halo := Color(1.0, 0.55, 0.7, 0.3)
	var soft := Color(1.0, 0.46, 0.62, 0.48)
	var core := Color(1.0, 0.34, 0.54, 0.64)
	for s in [-1.0, 1.0]:
		var c := Vector2(cx + float(s) * fs * FACE_CHEEK_DX, y)
		var r := fs * 0.062
		draw_texture_rect(gd, Rect2(c - Vector2(r * 1.4, r * 1.4), Vector2(r * 2.8, r * 2.8)), false, halo)
		draw_texture_rect(gd, Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false, soft)
		draw_circle(c, r * 0.4, core)
		# two little sparkles
		draw_line(c + Vector2(-r * 0.3, -r * 0.32), c + Vector2(-r * 0.42, r * 0.05),
			Color(1, 1, 1, 0.55), maxf(1.2, fs * 0.004), true)
		draw_circle(c + Vector2(r * 0.3, -r * 0.2), fs * 0.006, Color(1, 1, 1, 0.7))

## Word-level goods: ocean bubbles wobbling up past the digits, or a tiny star
## perched on the word's shoulder on the space themes. Drawn under the jelly
## transform.
func _draw_extras() -> void:
	if dress == "bubbles":
		for k in 5:
			var ph := fposmod(_t * (0.10 + 0.03 * float(k)) + float(k) * 0.23, 1.0)
			var bx := _origin0.x + _measure.x * (0.12 + 0.19 * float(k)) \
				+ sin((_t + float(k) * 2.1) * 1.3) * font_size * 0.03
			var by := _origin0.y + font_size * 0.1 - ph * font_size * 1.1
			var br := font_size * (0.012 + 0.014 * float(k % 3))
			var a := (1.0 - ph) * 0.5
			var ctr := Vector2(bx, by)
			# a glassy soap bubble: faint fill, crisp rim, a bright crescent glint.
			draw_circle(ctr, br * 0.9, Color(0.72, 0.86, 1.0, a * 0.22))
			draw_arc(ctr, br, 0, TAU, 16, Color(1, 1, 1, a), maxf(2.0, font_size * 0.006), true)
			draw_arc(ctr, br * 0.62, PI * 0.85, PI * 1.5, 6,
				Color(1, 1, 1, a * 0.9), maxf(1.6, font_size * 0.005), true)
			draw_circle(ctr + Vector2(-br * 0.32, -br * 0.34), br * 0.16, Color(1, 1, 1, a * 0.9))
	elif dress == "star":
		# PERCHED, not orbiting — the costume star sits on the word's upper-right
		# shoulder and twinkles, matching the stationary glitter field rather than
		# reintroducing the one travelling light the field gave up.
		var c := _origin0 + Vector2(_measure.x * 0.5, -font_size * 0.30)
		var p := c + Vector2(_measure.x * 0.50, -font_size * 0.30)
		var tw := 0.7 + 0.3 * sin(_t * 6.0)
		var r := font_size * 0.064 * tw
		_draw_sparkle(p, r, Color(1.0, 0.98, 0.86, 0.95))
		# a couple of tiny attendant twinkles trailing off its point
		for k in 2:
			var pp := p - Vector2(font_size * 0.10 * float(k + 1),
				font_size * 0.045 * float(k + 1))
			var ptw := 0.55 + 0.45 * sin(_t * (4.4 + 1.7 * float(k)) + float(k) * 2.1)
			_draw_sparkle(pp, r * (0.34 - 0.12 * float(k)) * ptw,
				Color(1.0, 0.98, 0.9, 0.5))

## A four-point twinkle: a soft glow plus a crisp concave 4-point star.
func _draw_sparkle(p: Vector2, r: float, col: Color) -> void:
	var gd := CandyFace.glow_dot()
	draw_texture_rect(gd, Rect2(p - Vector2(r * 2.2, r * 2.2), Vector2(r * 4.4, r * 4.4)),
		false, Color(col.r, col.g, col.b, col.a * 0.35))
	var star := PackedVector2Array()
	for k in 8:
		var a := TAU * float(k) / 8.0 - PI * 0.5
		var rad := r if (k % 2 == 0) else r * 0.34
		star.append(p + Vector2(cos(a), sin(a)) * rad)
	draw_colored_polygon(star, col)
	draw_circle(p, r * 0.22, Color(1, 1, 1, minf(1.0, col.a + 0.2)))

## The active stunt as a transform around `pivot`: hop (a little jump with a
## landing squash), spin (one full cartwheel), shiver (a quick horizontal
## shudder) or squish (a gummy squash-and-recover).
func _stunt_xf(pivot: Vector2) -> Transform2D:
	var p := _stunt_p
	var off := Vector2.ZERO
	var rot := 0.0
	var sc := Vector2.ONE
	match _stunt_kind:
		0:   # hop — parabolic jump, squashing as it lands
			off = Vector2(0.0, -font_size * 0.22 * sin(PI * p))
			if p > 0.8:
				var l := (p - 0.8) / 0.2
				sc = Vector2(1.0 + 0.10 * sin(PI * l), 1.0 - 0.10 * sin(PI * l))
		1:   # spin — one smooth full turn
			rot = TAU * (p * p * (3.0 - 2.0 * p))   # smoothstep-eased
		2:   # shiver — a rapid shudder that dies out
			off = Vector2(sin(p * 46.0) * font_size * 0.030 * (1.0 - p), 0.0)
		5:   # backflip — a lazy full turn the OTHER way, with a hop and a squash-land
			rot = -TAU * (p * p * (3.0 - 2.0 * p))
			off = Vector2(0.0, -font_size * 0.16 * sin(PI * p))
			if p > 0.85:
				var l := (p - 0.85) / 0.15
				sc = Vector2(1.0 + 0.12 * sin(PI * l), 1.0 - 0.12 * sin(PI * l))
		6:   # sneeze — a slow rear-back… then the ACHOO lunge, then a sniffly recover
			if p < 0.45:
				var b := p / 0.45
				rot = -0.14 * b
				off = Vector2(0.0, -font_size * 0.05 * b)
				sc = Vector2(1.0 - 0.04 * b, 1.0 + 0.06 * b)     # inhale stretch
			elif p < 0.62:
				var l := (p - 0.45) / 0.17
				rot = lerpf(-0.14, 0.30, l)
				off = Vector2(font_size * 0.05 * l, font_size * 0.05 * l)
				sc = Vector2(1.0 + 0.10 * l, 1.0 - 0.12 * l)      # the blast squash
			else:
				var e := (p - 0.62) / 0.38
				rot = 0.30 * (1.0 - e)
				off = Vector2(font_size * 0.05, font_size * 0.05) * (1.0 - e)
		7:   # the 0 rolls away — out along the baseline and back, spin matched to travel
			var x_off := font_size * 0.85 * sin(PI * p)
			off = Vector2(x_off, 0.0)
			rot = x_off / (font_size * 0.34)
		_:   # squish — gummy squash and recover
			var s := 0.16 * sin(PI * p)
			sc = Vector2(1.0 + s, 1.0 - s)
	var xf := Transform2D(rot, sc, 0.0, Vector2.ZERO)
	xf.origin = pivot + off - xf.basis_xform(pivot)
	return xf

func _grad(f: float) -> Color:
	# Flowing colours: the sweep sloshes back and forth through the word (ping-pong,
	# so there's never a hard wrap seam) — the theme's palette endlessly circulating.
	if animate:
		f = pingpong(f + _t * 0.10, 1.0)
	# Multi-stop palette (theme colour story) takes precedence when supplied.
	var n := palette_colors.size()
	if n >= 2:
		var p: float = clampf(f, 0.0, 1.0) * float(n - 1)
		var i: int = int(floor(p))
		if i >= n - 1:
			return palette_colors[n - 1]
		return palette_colors[i].lerp(palette_colors[i + 1], p - float(i))
	return c0.lerp(c1, f * 2.0) if f < 0.5 else c1.lerp(c2, (f - 0.5) * 2.0)
