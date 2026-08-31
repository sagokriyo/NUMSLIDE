class_name BoardFx
extends Control
## BoardFx — the gameplay screen's living ambience. Every theme gets a *signature*
## effect chosen by its identity (ThemeData.background_id), layered over gentle
## colour motion drawn from the palette:
##
##   snow        a Christmas village under blown snow  (Arctic)
##   petals      a cherry in flower, shedding         (Sakura Pink)
##   rain        fast vertical streaks (+lightning)   (Thunderstorm, Crimson)
##   rain_gold / rain_silver / rain_diamond           (the "Raining …" themes)
##   butterflies a moonlit grove, and it is full      (Butterfly Grove)
##   plumage     a peacock train, shed                (Peacock)
##   marble      a sculpture hall, veins growing      (Carrara)
##   noir        light through blinds on true black   (Noir)
##   mono        a hairline grid and one red dot      (Mono)
##   wash        pigment blooming on wet paper        (Aquarelle)
##   bismuth     hopper crystals, the oxide film      (Bismuth)
##   altitude    above the clouds, balloons rising    (Altitude)
##   lagoon      caustics, palm shadows, a turtle     (Lagoon)
##   savanna     a low sun, acacias, a herd crossing  (Savanna)
##   redwood     old growth, god rays, spores         (Redwood)
##   flecks      a sketchbook page drawing on itself  (Paper)
##   neon_rain   bright neon streaks                  (Neon Rain, Toxic, Cyber)
##   code        matrix-style falling glyph columns   (Matrix)
##   embers      glowing sparks rising + flicker      (Inferno, Ember, Volcanic)
##   bubbles     bubbles rising + wobble              (Ocean, Coral, Teal Abyss)
##   stars       a twinkling, drifting starfield      (Space, Nebula, Gold Stars)
##   fireflies   warm dots that wander + blink        (Firefly Night, Forest)
##   aurora      flowing aurora bands (shader)        (Aurora)
##   fog         huge soft clouds drifting sideways   (Shadow Fog, Phantom)
##   confetti    multi-colour bits falling + spinning (Candy Pop, Pixel Retro)
##   blood_moon  huge red moon + drifting blood fog   (Blood Moon)
##   sunset      low sun + glow + cloud bands         (Sunset Dusk, Golden Hour)
##   nebula      drifting coloured gas + starfield    (Cosmic Nebula, Galaxy …)
##   grid        synthwave perspective grid + sun     (Vaporwave)
##   leaves      autumn maple leaves tumbling down    (Autumn)
##   lanterns    warm paper lanterns rising           (Lantern Festival)
##   gems        coloured faceted gems raining        (Emerald, Ruby, Sapphire)
##   balloons    colourful balloons drifting up       (Balloon Party)
##   fireworks   periodic firework bursts in the sky  (Carnival)
##   hearts      sparkly hearts floating up           (Kawaii)
##   motes       quiet floating dust (default)        (Desert, Zen …)
##   biolum      the deep sea: sea pens, medusae, marine snow, and light that
##               ANSWERS the player                    (Bioluminescence)
##
## Purely decorative and never eats input — with one exception, called out here
## because it breaks the rule the rest of the file follows: `biolum` and the
## reward motifs REACT, through on_swipe / on_merge / on_touch / celebrate below.
## Rebuilds on theme change so switching
## themes restyles it live.

# The five generic particle masks. Like the shaped sprites below (see
# `_shape_cache`) these are pure white/greyscale silhouettes with NO theme input —
# their builders take no arguments and every colour in them is a shade of white;
# the particle system tints them per-emitter at render time. So one copy serves
# every BoardFx instance and every theme, and they are `static` for exactly the
# reason `_shape_cache` is: gameplay keeps TWO BoardFx alive at once (the
# full-screen ambience plus the clipped in-grid layer, gameplay.gd:106 and :266)
# and a fresh pair is built on every gameplay entry, so a per-instance copy meant
# the same bytes resident two or more times over — measured at 69,632 B of render
# texture memory for the duplicate `_round` (128×128) + `_dot` (24×24) alone.
static var _round_tex: GradientTexture2D   # big soft radial — the background wash blobs
static var _dot_tex: GradientTexture2D     # small soft radial — flakes, stars, embers, motes
static var _streak_tex: GradientTexture2D  # thin vertical gradient — rain / code
static var _ring_tex: GradientTexture2D    # hollow ring — bubbles
static var _square_tex: ImageTexture       # solid square — confetti
# Premium shaped sprites (baked metallic shading in RGB; tinted by the particle).
var _coin_tex: ImageTexture         # gold/silver coin — disc + rim + specular
var _ingot_tex: ImageTexture        # gold bar / "brick" — beveled rounded rect
var _gem_tex: ImageTexture          # faceted diamond
var _shard_tex: ImageTexture        # thin ice crystal sliver
var _leaf_tex: ImageTexture         # bamboo / autumn leaf
var _orb_tex: ImageTexture          # soft ghost orb (bright rim, hollow core)
var _disc_tex: ImageTexture         # clean solid disc — the sun (sunset / synthwave)
var _moon_tex: ImageTexture         # moon disc with maria (blood moon)
var _crescent_tex: ImageTexture     # crescent moon (Arabian Night)
var _bubble_tex: ImageTexture       # realistic bubble (ring + highlight)
var _balloon_tex: ImageTexture      # party balloon (Balloon Party)
var _heart_tex: ImageTexture        # soft heart (Kawaii)
var _lantern_tex: ImageTexture      # paper lantern — glowing body, cap + tassel (Lantern Festival)
var _sparkle_tex: ImageTexture      # 4-point "kirakira" star (Anime / Kawaii)
var _aurora_ray_tex: ImageTexture   # soft vertical aurora curtain/ray
var _aurora_mat: ShaderMaterial
var _grid_mat: ShaderMaterial        # synthwave perspective grid floor
var _ribbon_mat: ShaderMaterial      # icy aurora ribbon (Glacier Dawn)
var _caustics_mat: ShaderMaterial    # underwater caustics (Coral Depths)
var _scan_mat: ShaderMaterial        # CRT scanlines + glitch (Toxic Neon)
## The motif shaders compile ONCE per process (ui/screen.gd pattern) — the const
## sources always produce the same program; the ShaderMaterials above stay
## per-instance so each BoardFx owns its own uniforms.
static var _aurora_shader: Shader
static var _grid_shader: Shader
static var _ribbon_shader: Shader
static var _caustics_shader: Shader
static var _scan_shader: Shader
var _vp: Vector2 = Vector2.ZERO      # viewport size — the layout reference
var _gen: int = 0                    # build generation — stops stale async loops
## <1.0 marks a MENU-BACKDROP instance (Home / Sign-in / Settings…): every
## emitter's field thins by this factor and the slow drifting fields simulate at
## 30 Hz on every platform, not just phones — behind cards at half alpha the
## difference is invisible, and the menus stop paying the gameplay ambience's
## full per-frame bill. Gameplay keeps the authored density (1.0). Set BEFORE
## the node enters the tree.
var ambience_scale: float = 1.0
## The palette this layer renders — the ACTIVE theme normally, but the Themes
## screen's card-backdrop captures override it so a card can photograph ITS
## theme's world without wearing it (see ThemePreview). Set BEFORE the node
## enters the tree, same contract as ambience_scale. Every theme read in this
## file funnels through _pal()/_motif()/_pc — never ThemeManager directly.
var palette_override: Dictionary = {}
## B1/B2 — a CLIP-WINDOW hint for an instance the host confines to a sub-rect
## (gameplay's in-grid layer inside an FxClip). Returns the visible window in
## this fx's LOCAL space — FxClip's counter-offset keeps that equal to screen
## space, so the host passes the board's global rect. Set BEFORE add_child.
## Invalid (the default) = full-screen instance, nothing changes.
##   B1 (phones only, AppScreen.lite_gpu()): every `_emit` field keeps its
##   authored DENSITY but only simulates its visible share — `amount` scales by
##   the visible-area fraction and ALL fields run at 30 Hz. Stochastic, so it is
##   lite-gated: the desktop G5 pixel shots (arctic snow lives in a gated
##   gameplay shot) keep their exact particle sample.
##   B2 (every platform): the reward-fx layer gets the window and skips
##   per-element draws that fall wholly outside it — byte-identical inside the
##   clip, since FxClip scissors those pixels anyway (see reward_fx.gd Base).
var clip_rect: Callable = Callable()
## Bounded retry budget for B1: at first build the host's layout pass may not
## have sized the board yet (window reads 0×0), so `_rebuild` re-defers itself
## a few times until the window is real. Never resets — it only exists to ride
## out entry-frame layout, and an exhausted budget just builds unscaled.
var _clip_retries: int = 0
var _rebuild_queued: bool = false    # dedupes deferred rebuilds (theme roll, C4)
var _reward: RewardFx.Base = null    # the active reward-theme effect (reactive)
## Arctic's village — the pieces of it that answer the player (see _snow_react),
## plus the sleigh, which `celebrate()` scrambles. Cleared and re-collected on
## every build, because a rebuild frees the nodes these point at, so every use
## is guarded by is_instance_valid.
var _snow_lights: Array = []
var _snow_smoke: CPUParticles2D = null
var _snow_smoke_v: float = 0.0
var _snow_flaring: bool = false
var _snow_sleigh: TextureRect = null
## The run's JOURNEY tier (0..3): how deep the current game has climbed, driven
## by the board's highest tile (gameplay._journey_tier — 512/2048/8192 are the
## thresholds). The world deepens with it: a generic depth grade over every
## theme plus bespoke stages on hero worlds (_journey_dress). Stays 0 outside a
## run — menus and the theme-card previews never set it.
var _journey := 0
## Bioluminescence only — the reactive light (see "The phenomenon" below).
## `_bio_bloom` is the full-frame overlay a reaction lights; `_bio_pulse` is the
## tween that owns it, killed rather than stacked when reactions come fast.
## `_bio_touch` / `_bio_sparks` throttle the finger trail: on_touch fires on
## every drag event, and swipe frames are this theme's tightest budget.
var _bio_bloom: ColorRect = null
var _bio_pulse: Tween = null
var _bio_touch: Vector2 = Vector2(INF, INF)
var _bio_sparks: int = 0

const _AURORA_CODE := """
shader_type canvas_item;
// Flowing aurora — domain-warped GRADIENT-noise curtains that stream upward and drift
// sideways forever. Gradient (not value) noise => no grid banding; the warp keeps the
// rays organic and curved; the time terms keep the whole field flowing so it can never
// freeze into a static line. Colour: green hem -> teal -> magenta tips, in the sky.
uniform vec4 base : source_color = vec4(0.02, 0.03, 0.09, 1.0);
uniform vec4 col_low : source_color = vec4(0.15, 1.00, 0.45, 1.0);  // green hem
uniform vec4 col_mid : source_color = vec4(0.20, 0.85, 0.95, 1.0);  // teal
uniform vec4 col_high : source_color = vec4(0.95, 0.25, 0.80, 1.0); // magenta tips
uniform float speed = 0.6;
uniform float intensity = 1.0;

vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}
float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);   // quintic smoothing
	return mix(mix(dot(hash22(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
				   dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
			   mix(dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
				   dot(hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * gnoise(p); p *= 2.0; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	// Full-height curtains: the bright hem sits near the BOTTOM of the page and
	// the rays stream all the way UP, thinning toward the very top — standing
	// under the aurora, not watching a band pinned to the sky.
	float hem = 0.90;
	float above = hem - uv.y;                       // >0 => higher up the page
	// Band envelope: brightest just above the low hem, then reaching almost the
	// whole way up before gently thinning out at the very top.
	float env = smoothstep(-0.03, 0.05, above) * (1.0 - smoothstep(0.52, 0.92, above));

	// Slow flowing domain warp, then vertical-ray curtains sampled from it. Every
	// coordinate carries a time term => the curtains continuously stream and morph
	// (the stronger -y term keeps the light visibly CLIMBING the page).
	float warp = fbm(vec2(uv.x * 1.5 - t * 0.05, uv.y * 1.2 + t * 0.03));
	vec2 cp = vec2(uv.x * 3.5 + warp * 1.8 + t * 0.08, uv.y * 1.4 - t * 0.10);
	float curtain = clamp(fbm(cp) + 0.5, 0.0, 1.0);
	curtain = pow(curtain, 1.8);
	float shim = clamp(fbm(cp * 2.3 + vec2(t * 0.15, 0.0)) + 0.5, 0.0, 1.0);
	curtain *= 0.55 + 0.45 * shim;

	float dens = curtain * env;
	vec3 c = mix(col_low.rgb, col_mid.rgb, smoothstep(0.0, 0.30, above));
	c = mix(c, col_high.rgb, smoothstep(0.30, 0.78, above));
	COLOR = vec4(base.rgb + c * dens * intensity * 1.6, 1.0);
}
"""

# A faint aurora/ice ribbon confined to the top sky — transparent elsewhere so it
# overlays the snow (Glacier Dawn).
const _RIBBON_CODE := """
shader_type canvas_item;
uniform vec4 col_a : source_color = vec4(0.5, 0.9, 1.0, 1.0);
uniform vec4 col_b : source_color = vec4(0.78, 0.86, 1.0, 1.0);
uniform float speed = 0.08;
uniform float intensity = 0.5;
void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	float curtain = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float sway = sin(t*0.5 + fi*1.7 + uv.y*2.0)*0.18 + sin(t*0.3 + fi*3.0 + uv.y*3.5)*0.08;
		float band = fract(uv.x*1.4 + sway + fi*0.5);
		curtain += pow(1.0 - abs(band - 0.5)*2.0, 8.0);
	}
	curtain = clamp(curtain, 0.0, 1.0);
	float env = smoothstep(0.0, 0.10, uv.y) * (1.0 - smoothstep(0.30, 0.62, uv.y));
	vec3 c = mix(col_a.rgb, col_b.rgb, clamp(uv.y*2.2, 0.0, 1.0));
	COLOR = vec4(c, curtain * env * intensity);
}
"""

# Underwater caustics: bright light webs rippling, strongest near the surface.
const _CAUSTICS_CODE := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform float speed = 0.4;
uniform float intensity = 0.22;
float cwave(vec2 p, float t) {
	return sin(p.x*8.0 + t) * sin(p.y*8.0 + t*1.3) + sin((p.x + p.y)*6.0 - t*0.7);
}
void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	float v = abs(cwave(uv, t) + cwave(uv*1.7 + vec2(0.3), t*1.2) * 0.6);
	float caustic = pow(clamp(1.0 - v*0.35, 0.0, 1.0), 3.0);
	float env = 1.0 - smoothstep(0.0, 0.95, uv.y);
	COLOR = vec4(tint.rgb, caustic * env * intensity);
}
"""

# Drifting CRT scanlines plus an occasional bright glitch bar.
# G4 mediump: colour/mask math only. The sin/floor ARGUMENTS stay highp — they
# carry TIME (FP16 quantises accumulating phases within minutes) — and hash()
# stays highp end to end: fract-of-large-number exceeds the FP16 mantissa.
# Desktop GPUs ignore mediump, so the G5 gate path renders bit-identically.
const _SCAN_CODE := """
shader_type canvas_item;
uniform mediump vec4 tint : source_color = vec4(0.3, 1.0, 0.3, 1.0);
uniform mediump float intensity = 0.05;
float hash(float n) { return fract(sin(n) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	mediump float line = 0.5 + 0.5 * sin((uv.y * 220.0) - TIME * 3.0);
	mediump float scan = pow(line, 3.0) * intensity;
	float seg = floor(TIME * 3.0);
	mediump float bar = (1.0 - smoothstep(0.0, 0.03, abs(uv.y - hash(seg))))
		* step(0.92, hash(seg + 0.5)) * 0.10;
	COLOR = vec4(tint.rgb, scan + bar);
}
"""

# Synthwave floor: a neon perspective grid receding to a horizon, the lines flowing
# toward the viewer. Only painted below `horizon`; the sky above is transparent.
# G4 mediump: only the 0..1 line masks and the colour uniform. Everything the
# grid coordinates touch stays highp — `grid_line` runs fract() over values that
# carry TIME * speed (unbounded accumulator) and ±13-cell perspective coords,
# both past FP16's mantissa; `p`/`depth` feed those coords, so they stay too.
# Desktop GPUs ignore mediump, so the G5 gate path renders bit-identically.
const _GRID_CODE := """
shader_type canvas_item;
uniform mediump vec4 line_col : source_color = vec4(1.0, 0.25, 0.8, 1.0);
uniform float speed = 0.30;
uniform float horizon = 0.60;
float grid_line(float coord, float w) {
	float f = fract(coord);
	return 1.0 - smoothstep(0.0, w, min(f, 1.0 - f));
}
void fragment() {
	vec2 uv = UV;
	if (uv.y < horizon) {
		COLOR = vec4(0.0);
	} else {
		float p = (uv.y - horizon) / (1.0 - horizon);   // 0 at horizon → 1 at bottom
		float depth = 1.0 / (p + 0.06);                  // large (dense) near horizon
		mediump float lh = grid_line(depth * 0.5 - TIME * speed, 0.06);
		mediump float lv = grid_line((uv.x - 0.5) * depth * 1.5, 0.06);
		mediump float g = max(lh, lv);
		COLOR = vec4(line_col.rgb, g * p * 0.7);
	}
}
"""

func _ready() -> void:
	# NO anchors: this node owns its rect. Anchored, its size gets re-derived by
	# the parent's layout pass — and Home's per-frame parallax `position` writes
	# pin whatever size that pass computed (0×0 before the parent is laid out).
	# A canvas item with a degenerate rect renders briefly, then gets culled —
	# the Rainbow Keys keyboard / black hole / fluid silently vanishing on Home.
	# _rebuild sets `size = _vp` explicitly instead, and with plain top-left
	# anchors nothing ever overrides it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# No clip_contents: this Control's own size can lag a frame behind layout, and
	# clipping to a 0×0 rect would hide everything. We lay children out in screen
	# space using the viewport size, so the node sits at the origin and fills it.
	# C4: the theme signal fires mid-frame (theme roll on game entry, live theme
	# switch); respawning every emitter synchronously inside the dispatch spiked
	# that frame. On phones the whole respawn now lands at the end-of-frame
	# flush instead — still before draw, so the visible end state is identical.
	# DESKTOP KEEPS THE SYNCHRONOUS RESPAWN: the equivalence drivers re-seed the
	# global RNG immediately AFTER applying a theme (g5_pixel_diff.gd `_pin_theme`
	# → `seed(RNG_SEED)`, no frame between), so a deferred rebuild on a
	# still-alive backdrop would consume post-seed randf()s and shift every
	# stochastic layout the gate then captures against its goldens.
	ThemeManager.theme_changed.connect(func(_p):
		if AppScreen.lite_gpu():
			_queue_rebuild()
		else:
			_rebuild())
	get_viewport().size_changed.connect(_rebuild)
	_queue_rebuild()

# --- Build --------------------------------------------------------------------
## Deferred, deduplicated rebuild: several triggers in one frame (theme roll +
## entry, B1's layout retry) collapse into a single respawn at the flush.
func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_do_queued_rebuild.call_deferred()

func _do_queued_rebuild() -> void:
	if not _rebuild_queued:
		return   # a synchronous rebuild (viewport resize) already ran this frame
	_rebuild()

func _rebuild() -> void:
	_rebuild_queued = false
	# B1: a clipped instance sizes its fields to the visible window, but on the
	# entry frame the host's layout pass may not have sized the board yet. Retry
	# next flush (bounded) instead of building an unscaled field; phones only —
	# desktop never scales, so it never needs to wait.
	if clip_rect.is_valid() and AppScreen.lite_gpu() \
			and _clip_retries < 8 and is_inside_tree():
		var win: Rect2 = clip_rect.call()
		if win.size.x <= 0.0 or win.size.y <= 0.0:
			_clip_retries += 1
			_queue_rebuild()
			return
	for c in get_children():
		c.queue_free()
	_reward = null
	_paper_art.clear()
	_grove_perches.clear()
	_fairy_n = 0
	_bio_bloom = null
	_bio_pulse = null
	_bio_touch = Vector2(INF, INF)
	_bio_sparks = 0
	_vp = UI.canvas_size(self)
	if _vp.x <= 0.0 or _vp.y <= 0.0:
		return
	_gen += 1   # invalidate any async loops spawned by the previous build
	size = _vp  # own the rect (see _ready) — a 0×0 item eventually gets culled
	var motif := _motif()

	# Background. Aurora paints its own; star themes use the starfield itself as
	# the backdrop (no cloud wash); everything else floats over a gentle palette
	# wash so the board never feels flat.
	if motif == "aurora":
		_build_aurora()
	elif motif == "neon" or motif == "toxic":
		# Brighter magenta/cyan glow so it reads as a neon city haze.
		_build_wash([_pc("accent"), _pc("accent2")], 0.20)
	elif motif not in ["stars", "space", "desert_night", "nebula", "grid", "sunset", "desert",
			"circuit", "blackhole", "starmap", "inkwash", "metaballs", "koi", "katana", "zen_sand",
			"forge", "skywriter", "star_atlas", "flecks", "mono", "noir", "marble",
			"wash", "bismuth", "savanna", "redwood", "altitude"]:
		# These motifs paint their own backdrop (gas clouds / grid / sky / dunes /
		# keyboard / accretion disk / pond / SHEET OF PAPER …), so the generic wash
		# would only muddy them — on Paper it was a literal grey smudge in the
		# middle of an otherwise clean page.
		_build_wash()

	match motif:
		"snow":          _m_snow()
		"petals":        _m_petals()
		"rain":
			_m_rain(_white(0.55), 360.0, 640.0, true)
			_storm_ground()
		"code":          _m_code()
		"embers":        _m_embers()
		"bubbles":       _m_bubbles()
		"stars":         _m_stars()
		"space":         _m_space()
		"fireflies":     _m_fireflies()
		"firefly_night": _m_firefly_night()
		"fog":           _m_fog()
		"confetti":      _m_confetti()
		"arcade_pop":    _m_arcade()
		"candy":         _m_candy()
		"lightdust":     _m_lightdust()
		"stardrift":     _m_stardrift()
		"flecks":        _m_flecks()
		"anime":         _m_anime()
		"neon":          _m_neon()
		"neon_rain":     _m_rain(_pc("accent").lightened(0.15), 320.0, 600.0, false)
		"aurora":        pass   # _build_aurora already added the starfield
		# --- Premium signature motifs (shape-driven, name-specific) ---
		"rain_gold":     _m_rain_gold()
		"rain_silver":   _m_rain_silver()
		"rain_diamond":  _m_rain_diamond()
		"crystal":       _m_crystal()
		"embers_lux":    _m_embers_lux()
		"deep_sea":      _m_deep_sea()
		"biolum":        _m_biolum()
		"moonlit":       _m_moonlit()
		"phantom":       _m_phantom()
		"shadow":        _m_shadow()
		"desert_night":  _m_desert_night()
		"desert":        _m_desert()
		"toxic":         _m_toxic()
		# --- Name-accurate signature motifs (sky / celestial / seasonal) ---
		"blood_moon":    _m_blood_moon()
		"sunset":        _m_sunset()
		"nebula":        _m_nebula()
		"grid":          _m_grid()
		"leaves":        _m_leaves()
		"lanterns":      _m_lanterns()
		"gems":          _m_gems()
		# --- Playful motifs (party / fun) ---
		"balloons":      _m_balloons()
		"fireworks":     _m_fireworks()
		"hearts":        _m_hearts()
		# --- Reward motifs (badge-earned themes; reactive — see RewardFx).
		# Origami is premium, not badge-earned, but rides the same reactive
		# plumbing: every swipe/merge folds a paper animal (RewardFx.Origami).
		"circuit", "origami", "blackhole", "starmap", "inkwash", "serpent", \
		"koi", "metaballs", "katana", "gears", "stained_glass", \
		"forge", "skywriter", "star_atlas":
			_m_reward(motif)
		# --- New premium ambient motifs ---
		"bonsai":        _m_bonsai()
		"zen_sand":      _m_zen_sand()
		# --- 2026-08 additions ---
		"honeycomb":     _m_honeycomb()
		"butterflies":   _m_butterflies()
		"plumage":       _m_plumage()
		# --- The ten of 2026-08-27 (docs/themes/ten-premium-themes.md) ---
		"marble":        _m_marble()
		"noir":          _m_noir()
		"mono":          _m_mono()
		"wash":          _m_wash()
		"bismuth":       _m_bismuth()
		"altitude":      _m_altitude()
		"lagoon":        _m_lagoon()
		"savanna":       _m_savanna()
		"redwood":       _m_redwood()
		"motes", _:      _m_motes()
	_journey_dress()

# --- The journey: the world deepens as the run climbs ----------------------------
## The tier ladder: which journey tier a run's highest tile has earned. The
## thresholds are the game's own drama beats — 512 (the first big-merge slow-mo),
## 2048 (the goal) and 8192 (the giants) — so the world deepens exactly when the
## run's story does. Pure; pinned by test_visual_wonders.
func journey_tier_for(highest: int) -> int:
	if highest >= 8192:
		return 3
	if highest >= 2048:
		return 2
	if highest >= 512:
		return 1
	return 0

## Sets the run's journey tier and re-dresses the world when it changes. The
## shift rides a soft modulate dip (the world exhales, changes, and comes back)
## unless reduce motion is on — then it is a clean rebuild on the next flush.
## Idempotent per tier: gameplay calls this freely after merges.
func set_journey_tier(t: int) -> void:
	t = clampi(t, 0, 3)
	if t == _journey:
		return
	_journey = t
	if is_inside_tree() and not SettingsManager.reduce_motion():
		var back: float = modulate.a   # menus dim this layer; return to whatever it was
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", back * 0.55, 0.35) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(_queue_rebuild)
		tw.tween_property(self, "modulate:a", back, 0.6) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	else:
		_queue_rebuild()

## The tier's dressing, applied after the motif build so it grades whatever the
## world just drew. Two parts:
##   * every theme: a depth grade — dark worlds sink toward their deep gradient
##     stop, light worlds warm toward dusk — so ANY run visibly travels;
##   * hero worlds: bespoke stages. Space's galaxy band doubles at tier 2 (you
##     are entering the core); the ocean grows the coral_depths reef at 2048 —
##     the surface run has descended to the sea floor.
func _journey_dress() -> void:
	if _journey <= 0:
		return
	var motif := _motif()
	if motif == "space" and _journey >= 2:
		_galaxy_band()   # a second pass brightens the band: the core approaches
	if motif == "bubbles" and _journey >= 2:
		_reef()          # the deep begins where the reef does
	if motif == "snow" and _journey >= 2:
		_deep_winter()   # the storm closes in over the village
	if motif == "altitude":
		if _journey >= 3:
			_altitude_stratosphere()   # the sky goes indigo and the stars come out
		elif _journey >= 2:
			_warm_hour(0.22)           # golden hour
	if motif == "lagoon":
		if _journey >= 3:
			_lagoon_manta(_gen)        # a manta's shadow crosses the sand
		elif _journey >= 2:
			_warm_hour(0.18)
	if motif == "savanna":
		if _journey >= 3:
			_galaxy_band()             # the Milky Way over the plain
			_emit({"from": "all", "tex": _dot(), "color": _white(1.0),
				"alpha": 0.8, "amount": 40, "lifetime": 6.0, "dir": Vector3(0, 0, 0),
				"spread": 180.0, "vmin": 0.0, "vmax": 1.0, "smin": 0.2, "smax": 0.5,
				"twinkle": true})
		elif _journey >= 2:
			_dusk_veil(0.24)           # the sun is down, the sky goes violet
	if motif == "redwood":
		if _journey >= 3:
			_god_rays(_pc("accent"), 0.10, 0.24)   # the sun breaks through
			_warm_hour(0.12)
		elif _journey >= 2:
			_ground_fog()              # the mist comes in
	var grade := ColorRect.new()
	grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := _pal()
	var deep: Color = (p.get("bg_grad", Color(0, 0, 0)) as Color).darkened(0.35)
	if bool(p.get("is_light", false)):
		# A light world doesn't blacken — it dusks toward its own accent.
		deep = (p.get("bg_grad", Color(1, 1, 1)) as Color).lerp(_pc("accent"), 0.35)
	var depth_a: float = [0.0, 0.10, 0.18, 0.26][_journey]
	grade.color = Color(deep.r, deep.g, deep.b, depth_a)
	add_child(grade)

# --- 2026-08 ambient motifs -----------------------------------------------------
func _m_honeycomb() -> void:
	# Honeycomb, lit from behind.
	#
	# Two earlier passes drew the comb LITERALLY — slabs of hexagons across the
	# top and bottom of the screen — and both read as a cartoon pattern however
	# carefully the cells were shaded, because a wall of tessellated hexagons is
	# a wallpaper by definition and the board has to sit on top of it.
	#
	# So the comb is out of focus instead. What is actually on screen is the
	# LIGHT inside a hive: soft hexagonal bokeh drifting through the warm dark
	# the way out-of-focus highlights do, honey drawing down in slow threads and
	# letting go, pollen hanging in the light, and real bees crossing on their
	# own errands. Comb is unmistakable in it, and nothing in it is a pattern.
	var amber: Color = _pc("gold").lerp(_white(1.0), 0.25)
	# The light itself: warm above, deepening to old wax below.
	_hive_light(amber)
	# Hexagonal bokeh at three depths. Big, soft and slow — a highlight the lens
	# cannot resolve, not a tile.
	var bokeh := _shaped("hc_bokeh", 64, 56, _fn_hex_bokeh)
	_emit({"from": "all", "tex": bokeh, "color": amber,
		"alpha": 0.13, "amount": 10, "lifetime": 20.0, "dir": Vector3(0.05, -1, 0),
		"spread": 30.0, "vmin": 3.0, "vmax": 10.0, "smin": 2.6, "smax": 4.6,
		"spin": 0.10, "turb": 0.4})
	_emit({"from": "all", "tex": bokeh, "color": amber,
		"alpha": 0.20, "amount": 14, "lifetime": 16.0, "dir": Vector3(0.08, -1, 0),
		"spread": 34.0, "vmin": 5.0, "vmax": 16.0, "smin": 1.2, "smax": 2.4,
		"spin": 0.16, "turb": 0.6})
	_emit({"from": "all", "tex": bokeh, "color": _pc("accent").lerp(_white(1.0), 0.35),
		"alpha": 0.30, "amount": 16, "lifetime": 13.0, "dir": Vector3(0.10, -1, 0),
		"spread": 40.0, "vmin": 8.0, "vmax": 24.0, "smin": 0.5, "smax": 1.1,
		"spin": 0.22, "turb": 0.8})
	# Pollen: fine warm dust suspended in the light, drifting up as often as down.
	_emit({"from": "all", "tex": _dot(), "color": _pc("gold").lerp(_white(1.0), 0.45),
		"alpha": 0.55, "amount": 46, "lifetime": 11.0, "dir": Vector3(0, -1, 0),
		"spread": 180.0, "vmin": 3.0, "vmax": 12.0, "smin": 0.2, "smax": 0.6,
		"twinkle": true})
	# The bees: few, slow, crossing sideways. Tinted WHITE so the bake's own
	# amber-and-black comes through — a bee tinted brown is a fly.
	_emit({"from": "all", "tex": _bee(), "color": _white(1.0),
		"alpha": 0.9, "amount": 6, "lifetime": 13.0, "dir": Vector3(1, 0.10, 0),
		"spread": 26.0, "vmin": 34.0, "vmax": 78.0, "smin": 0.55, "smax": 1.0,
		"turb": 1.0, "orbit": 0.06})
	_edge_glow(amber, 0.06, 0.16, true)
	# Honey drawing down out of the light above and letting go.
	_honey_threads(_gen, _vp.y * 0.015)

## The inside of a hive as LIGHT rather than as geometry: warm at the top where
## the sun comes through the wall, falling away into old wax at the floor.
func _hive_light(amber: Color) -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.30), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 4
	tex.height = 160
	var wash := TextureRect.new()
	wash.texture = tex
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash.size = _vp
	wash.modulate = Color(amber.r, amber.g, amber.b, 0.16)
	add_child(wash)
	var tw := wash.create_tween().set_loops()
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(wash, "modulate:a", 0.22, 7.0)
	tw.tween_property(wash, "modulate:a", 0.13, 7.5)

## An out-of-focus comb cell: a hexagon with almost no edge left, carrying the
## faint brighter rim that every real bokeh highlight has. Tinted and stacked at
## low alpha it reads as light through comb, which a crisp hexagon never does.
func _fn_hex_bokeh(uv: Vector2) -> Color:
	var q := Vector2(absf(uv.x), absf(uv.y))
	var hexd: float = maxf(q.x, q.x * 0.5 + q.y * 0.8660254)
	# A soft body, and a slightly brighter ring just inside the edge.
	var body: float = 1.0 - smoothstep(0.20, 0.96, hexd)
	var rim: float = 1.0 - smoothstep(0.0, 0.20, absf(hexd - 0.82))
	var a: float = clampf(body * 0.95 + rim * 0.30, 0.0, 1.0)
	if a <= 0.01:
		return Color(0, 0, 0, 0)
	var b: float = clampf(0.55 + rim * 0.30 + body * 0.20, 0.0, 1.0)
	return Color(b, b, b, a)

func _m_butterflies() -> void:
	# Butterfly Grove at dusk, and the grove is FULL.
	#
	# The first pass put twelve monarchs on the screen: orange specks, three
	# emitters, a warm corner sun. Against this palette — a deep blue-navy night
	# with a cobalt accent — orange was the one colour in the theme that could not
	# be there, and a dozen of anything reads as a few stray insects rather than a
	# grove. So: blue morphos and pale luminous whites, seventy-odd of them at six
	# depths, each one GLOWING, because the aura is baked into the sprite itself
	# (see `_bfly_morpho`) rather than chased with a second particle field that
	# could never stay in step with the first.
	#
	# They wander. Every layer carries `orbit` as well as `turb`, so no butterfly
	# ever crosses the frame in a straight line — a straight-flying butterfly is
	# a moth, and the difference is entirely in the path.
	_moonlit_clearing()
	_grove_forest(false)
	var morpho := _bfly_morpho()
	var fairy := _bfly_fairy()
	# FAR — small, dim, slow: the depth of the clearing.
	_emit({"from": "all", "tex": morpho, "color": _white(1.0),
		"alpha": 0.40, "amount": 22, "lifetime": 19.0, "dir": Vector3(0.30, -1, 0),
		"spread": 65.0, "vmin": 8.0, "vmax": 22.0, "smin": 0.42, "smax": 0.68,
		"spin": 0.35, "turb": 1.0, "orbit": 0.14})
	_emit({"from": "all", "tex": fairy, "color": _white(1.0),
		"alpha": 0.34, "amount": 18, "lifetime": 20.0, "dir": Vector3(-0.24, -1, 0),
		"spread": 70.0, "vmin": 7.0, "vmax": 20.0, "smin": 0.40, "smax": 0.66,
		"spin": 0.30, "turb": 1.0, "orbit": 0.12})
	# MID — the body of the flight.
	_emit({"from": "all", "tex": morpho, "color": _white(1.0),
		"alpha": 0.85, "amount": 16, "lifetime": 15.0, "dir": Vector3(0.20, -1, 0),
		"spread": 72.0, "vmin": 16.0, "vmax": 40.0, "smin": 0.80, "smax": 1.30,
		"spin": 0.55, "turb": 1.0, "orbit": 0.22})
	_emit({"from": "all", "tex": fairy, "color": _white(1.0),
		"alpha": 0.80, "amount": 12, "lifetime": 16.0, "dir": Vector3(-0.16, -1, 0),
		"spread": 76.0, "vmin": 14.0, "vmax": 36.0, "smin": 0.76, "smax": 1.24,
		"spin": 0.50, "turb": 1.0, "orbit": 0.20})
	# NEAR — a few crossing right past the lens, big and bright.
	_emit({"from": "all", "tex": morpho, "color": _white(1.0),
		"alpha": 0.95, "amount": 5, "lifetime": 12.0, "dir": Vector3(-0.28, -1, 0),
		"spread": 58.0, "vmin": 28.0, "vmax": 62.0, "smin": 1.75, "smax": 2.50,
		"spin": 0.75, "turb": 1.0, "orbit": 0.30})
	_emit({"from": "all", "tex": fairy, "color": _white(1.0),
		"alpha": 0.92, "amount": 4, "lifetime": 12.0, "dir": Vector3(0.26, -1, 0),
		"spread": 60.0, "vmin": 26.0, "vmax": 58.0, "smin": 1.65, "smax": 2.35,
		"spin": 0.70, "turb": 1.0, "orbit": 0.28})
	# The dust they leave behind them — cold blue-white, hanging in the air.
	_emit({"from": "all", "tex": _dot(),
		"iramp": _ramp_cols([Color(0.72, 0.90, 1.0), Color(1.0, 1.0, 1.0),
			Color(0.46, 0.72, 1.0)]),
		"alpha": 0.55, "amount": 40, "lifetime": 12.0, "dir": Vector3(0.10, -1, 0),
		"spread": 90.0, "vmin": 3.0, "vmax": 14.0, "smin": 0.18, "smax": 0.55,
		"twinkle": true})
	# Bokeh: big, soft, out-of-focus lights hanging in the air between the
	# trunks. Nothing in the scene casts them — they are the CAMERA's, and they
	# are what separates an enchanted clearing from a dark field with insects.
	_emit({"from": "all", "tex": _round(),
		"iramp": _ramp_cols([_pc("accent").lerp(_white(1.0), 0.55),
			Color(0.72, 0.92, 1.0), _pc("accent2").lerp(_white(1.0), 0.4)]),
		"alpha": 0.13, "amount": 12, "lifetime": 20.0, "dir": Vector3(0.10, -1, 0),
		"spread": 60.0, "vmin": 2.0, "vmax": 9.0, "smin": 1.6, "smax": 3.8})
	# Wisps drawn up out of the flower bed, the way warm air lifts off a garden.
	_emit({"from": "bottom", "tex": _dot(), "color": _white(1.0),
		"alpha": 0.50, "amount": 18, "lifetime": 10.0, "dir": Vector3(0.05, -1, 0),
		"spread": 26.0, "vmin": 10.0, "vmax": 34.0, "smin": 0.25, "smax": 0.7,
		"turb": 0.9, "twinkle": true})
	# The sky it is all happening under.
	_emit({"from": "all", "tex": _dot(), "color": _white(0.9),
		"alpha": 0.45, "amount": 34, "lifetime": 9.0, "dir": Vector3(0, -1, 0),
		"spread": 180.0, "vmin": 0.5, "vmax": 3.0, "smin": 0.12, "smax": 0.34,
		"twinkle": true})
	_edge_glow(_pc("accent"), 0.05, 0.16, false)
	_grove_flowers()
	# The near edge of the clearing, in FRONT of everything: the reason the
	# flight reads as happening inside a wood rather than against a backdrop.
	_grove_forest(true)
	# And the ones you actually watch — see `_fairy_flight`. Two are put in the
	# air immediately so the clearing is never empty on the entry frame.
	_fairy_one(true)
	_fairy_one(false)
	_fairy_flight(_gen)

## The GROVE.
##
## For a long time this theme was called Butterfly Grove and contained no trees:
## a flower bed along the bottom, a moon, and insects in an empty blue box. A
## grove is trees, and everything magical about a night grove comes from them —
## the canopy that breaks the moonlight into shafts, the trunks that give the
## dark a depth, the vines hanging into frame, and the light that is only
## remarkable because it is surrounded by so much unlit wood.
##
## Trunks are DRAWN, not baked, on one canvas item painted once: tapered polygon
## limbs off a bezier spine (the same `_taper_poly` / `_bez_pts` pair Sakura's
## cherry is built from). At near-black over a near-black sky the shape carries
## the whole read, and a per-pixel bake at any affordable resolution turns a
## branch into a rectangle.
##
##   near = false  the wood BEHIND everything — mid-distance trunks, the canopy
##                 across the top, and the vines hanging out of it.
##   near = true   the one trunk in FRONT of everything, hard against the left
##                 edge and almost black: the near edge of the clearing, and the
##                 reason the butterflies read as being INSIDE it.
func _grove_forest(near: bool) -> void:
	var sky: Color = _pc("bg0")
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.size = _vp
	canvas.draw.connect(_draw_grove_wood.bind(canvas, near, sky))
	add_child(canvas)
	canvas.queue_redraw()
	if near:
		return
	# --- The canopy: leaf masses along the top, broken so the moon gets in.
	var mass := _shaped("bg_leafmass", 72, 54, _fn_leaf_mass)
	for i in 11:
		var leaf := TextureRect.new()
		leaf.texture = mass
		leaf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		leaf.stretch_mode = TextureRect.STRETCH_SCALE
		leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.22, 0.44)
		leaf.size = Vector2(w, w * (54.0 / 72.0))
		leaf.pivot_offset = leaf.size * 0.5
		leaf.position = Vector2(_vp.x * (-0.06 + 0.112 * float(i)),
			_vp.y * randf_range(-0.05, 0.09)) - leaf.size * 0.5
		leaf.rotation = randf_range(-0.4, 0.4)
		var deep: Color = Color(0.05, 0.13, 0.16).lerp(sky, randf_range(0.0, 0.35))
		leaf.modulate = Color(deep.r, deep.g, deep.b, randf_range(0.80, 1.0))
		add_child(leaf)
		var sway := leaf.create_tween().set_loops()
		sway.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		var base: float = leaf.rotation
		var amp: float = randf_range(0.012, 0.030)
		sway.tween_property(leaf, "rotation", base + amp, randf_range(3.2, 5.4))
		sway.tween_property(leaf, "rotation", base - amp, randf_range(3.4, 5.8))
	# --- Vines hanging out of the canopy, each carrying a lit blossom or two.
	for i in 5:
		var vine := Control.new()
		vine.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vine.size = _vp
		var x: float = 0.08 + 0.21 * float(i) + randf_range(-0.04, 0.04)
		var drop: float = randf_range(0.16, 0.40)
		vine.draw.connect(_draw_vine.bind(vine, x, drop))
		add_child(vine)
		vine.queue_redraw()
		# The blossom on the end of it, lit, breathing.
		var bud := TextureRect.new()
		bud.texture = _round()
		bud.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bud.stretch_mode = TextureRect.STRETCH_SCALE
		bud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bd: float = _vp.x * randf_range(0.05, 0.10)
		bud.size = Vector2(bd, bd)
		bud.position = Vector2(_vp.x * (x + 0.035), _vp.y * drop) - bud.size * 0.5
		var lit: Color = _pc("accent").lerp(_white(1.0), randf_range(0.4, 0.8))
		var ba: float = randf_range(0.20, 0.38)
		bud.modulate = Color(lit.r, lit.g, lit.b, ba)
		add_child(bud)
		var bt := bud.create_tween().set_loops()
		bt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		bt.tween_interval(randf_range(0.0, 2.0))
		bt.tween_property(bud, "modulate:a", ba * 1.8, randf_range(2.2, 3.6))
		bt.tween_property(bud, "modulate:a", ba * 0.5, randf_range(2.4, 4.0))
	# --- Glowing fungus on the floor of the clearing: small caps, each with its
	# own pool of light. Nothing says "enchanted wood" faster.
	var cap := _shaped("bg_shroom", 40, 34, _fn_glow_cap)
	for i in 7:
		var xf: float = lerpf(0.05, 0.95, (float(i) + randf_range(0.1, 0.9)) / 7.0)
		var ch: float = _vp.y * randf_range(0.018, 0.038)
		var pool := TextureRect.new()
		pool.texture = _round()
		pool.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pool.stretch_mode = TextureRect.STRETCH_SCALE
		pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pool.size = Vector2(ch * 7.0, ch * 5.0)
		pool.position = Vector2(_vp.x * xf, _vp.y * 0.995 - ch * 0.6) - pool.size * 0.5
		var glow: Color = _pc("accent2").lerp(_white(1.0), 0.5)
		var pa: float = randf_range(0.10, 0.20)
		pool.modulate = Color(glow.r, glow.g, glow.b, pa)
		add_child(pool)
		var pt := pool.create_tween().set_loops()
		pt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		pt.tween_interval(randf_range(0.0, 3.0))
		pt.tween_property(pool, "modulate:a", pa * 1.9, randf_range(2.6, 4.2))
		pt.tween_property(pool, "modulate:a", pa * 0.5, randf_range(2.8, 4.6))
		_landmark(cap, xf, ch / _vp.y, 40.0 / 34.0,
			glow.lerp(_white(1.0), 0.35), randf_range(0.6, 0.9), 0.998)

## Trunk skeletons: [w0, w1, p0..p3] in viewport fractions, exactly as Sakura's.
const _GV_MID := [
	[0.040, 0.012, Vector2(0.20, 1.04), Vector2(0.22, 0.72), Vector2(0.17, 0.44), Vector2(0.21, 0.10)],
	[0.030, 0.010, Vector2(0.62, 1.04), Vector2(0.60, 0.76), Vector2(0.65, 0.50), Vector2(0.61, 0.16)],
	[0.052, 0.016, Vector2(0.88, 1.04), Vector2(0.92, 0.70), Vector2(0.86, 0.40), Vector2(0.91, 0.02)],
	[0.024, 0.008, Vector2(0.40, 1.04), Vector2(0.38, 0.80), Vector2(0.43, 0.58), Vector2(0.39, 0.30)],
]
const _GV_NEAR := [
	[0.150, 0.085, Vector2(-0.02, 1.10), Vector2(0.03, 0.72), Vector2(-0.03, 0.36), Vector2(0.02, -0.08)],
	[0.070, 0.020, Vector2(0.02, 0.46), Vector2(0.12, 0.38), Vector2(0.20, 0.28), Vector2(0.30, 0.13)],
]

func _draw_grove_wood(c: Control, near: bool, sky: Color) -> void:
	var limbs: Array = _GV_NEAR if near else _GV_MID
	for li in limbs.size():
		var e: Array = limbs[li]
		var pts := _bez_pts(e[2], e[3], e[4], e[5], 14)
		var w0: float = float(e[0]) * _vp.x
		var w1: float = float(e[1]) * _vp.x
		# Distance is CONTRAST at night: the far trunks wash toward the sky,
		# the near one is almost the darkest thing in the frame.
		var bark: Color = Color(0.015, 0.035, 0.050)
		if not near:
			bark = bark.lerp(sky, 0.20 + 0.16 * float(li))
		c.draw_colored_polygon(_taper_poly(pts, w0, w1), bark)
		# The moonlit edge down one side. On the near trunk this is the only
		# thing separating it from the background at all.
		var rim := PackedVector2Array()
		for p in pts:
			rim.append(p + Vector2(w0 * 0.36, 0.0))
		var lit: Color = _pc("accent").lerp(_white(1.0), 0.4)
		c.draw_colored_polygon(_taper_poly(rim, w0 * 0.14, w1 * 0.14),
			Color(lit.r, lit.g, lit.b, 0.10 if near else 0.06))
		# Boughs off the mid trunks, reaching into the canopy.
		if near or li == 3:
			continue
		for k in 2:
			var t: float = 0.62 + 0.18 * float(k)
			var i: int = mini(int(t * float(pts.size() - 1)), pts.size() - 2)
			var at: Vector2 = pts[i]
			var side: float = 1.0 if (li + k) % 2 == 0 else -1.0
			var tip: Vector2 = at + Vector2(side * _vp.x * 0.22, -_vp.y * 0.10)
			var mid: Vector2 = at.lerp(tip, 0.5) + Vector2(0.0, -_vp.y * 0.02)
			c.draw_colored_polygon(
				_taper_poly(_bez_px(at, mid, mid, tip, 8), w1 * 1.8, w1 * 0.4), bark)

## One vine: a long slack curve out of the canopy, hair-thin, with a lit tip.
func _draw_vine(c: Control, x: float, drop: float) -> void:
	var a := Vector2(_vp.x * x, -_vp.y * 0.02)
	var d := Vector2(_vp.x * (x + 0.035), _vp.y * drop)
	var b := a.lerp(d, 0.4) + Vector2(_vp.x * 0.05, 0.0)
	var e := a.lerp(d, 0.75) + Vector2(-_vp.x * 0.02, 0.0)
	var pts := _bez_px(a, b, e, d, 16)
	var vine: Color = _pc("accent").lerp(Color(0.04, 0.10, 0.14), 0.72)
	c.draw_polyline(pts, Color(vine.r, vine.g, vine.b, 0.75), maxf(_vp.x * 0.004, 1.2), true)
	# Leaves stepping down it.
	for i in range(2, pts.size() - 1, 3):
		var run: Vector2 = (pts[i + 1] - pts[i - 1]).normalized()
		var nrm := Vector2(-run.y, run.x) * (1.0 if i % 2 == 0 else -1.0)
		var lf: float = _vp.x * 0.022
		c.draw_colored_polygon(PackedVector2Array([
			pts[i], pts[i] + nrm * lf + run * lf * 0.5,
			pts[i] + nrm * lf * 0.6 + run * lf * 1.5]),
			Color(vine.r, vine.g, vine.b, 0.65))

## The magic in Butterfly Grove: HERO butterflies, flown by hand.
##
## A particle field can give you seventy butterflies, but it cannot give you
## ONE — every particle in a field shares a single lifetime, a single path law
## and a single alpha curve, so nothing in it can be the thing you watch, and
## nothing in it can flap. Real butterfly mechanics are four motions happening
## at once on different clocks, and the field can supply none of them:
##
##   the WING BEAT   scale.x pumping, never fully closed (a closed butterfly
##                   shows a hairline, so 0.34 is as shut as these get)
##   the BOB         every downstroke lifts the animal — a butterfly rises and
##                   sinks a body-length per beat, which is why its flight
##                   looks like it is falling upstairs
##   the BANK        a lazy roll into each turn
##   the WANDER      four waypoints on an eased curve, never a straight line
##
## So the sprite hangs inside a CARRIER. The carrier owns the wander; the sprite
## owns the beat, the bob and the bank, each on its own tween with its own
## period. Nothing in the four is ever in step with anything else, which is the
## entire difference between a butterfly and a moth.
##
## The wake is the other trick worth naming: a CPUParticles2D on the carrier with
## `local_coords = false`, so its sparks are emitted into WORLD space and stay
## where they were born while the butterfly flies on.
const _FAIRY_ALIVE := 4      # heroes kept in the air at once

var _grove_perches: Array = []   # flower heads a butterfly can land on
var _fairy_n: int = 0            # heroes currently in the air

func _fairy_flight(gen: int) -> void:
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(1.4, 3.4)).timeout
		if gen != _gen or not is_inside_tree():
			return
		if _fairy_n >= _FAIRY_ALIVE:
			continue
		# One in three goes down to the bed and settles on a flower instead of
		# crossing the frame. A grove where nothing ever LANDS is an aquarium.
		if randf() < 0.34 and not _grove_perches.is_empty():
			_fairy_settle(randf() < 0.5)
		else:
			_fairy_one(randf() < 0.55)

## The sprite, its halo and its wake, assembled inside a carrier. Returns
## [carrier, sprite] — the caller flies the carrier.
func _fairy_rig(pale: bool, w: float) -> Array:
	var carrier := Control.new()
	carrier.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carrier.size = Vector2.ZERO
	add_child(carrier)
	_fairy_n += 1
	carrier.tree_exited.connect(func() -> void: _fairy_n = maxi(_fairy_n - 1, 0))
	var fly := TextureRect.new()
	fly.texture = _bfly_fairy() if pale else _bfly_morpho()
	fly.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fly.stretch_mode = TextureRect.STRETCH_SCALE
	fly.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly.size = Vector2(w, w * (44.0 / 48.0))
	fly.pivot_offset = fly.size * 0.5
	fly.position = -fly.size * 0.5
	carrier.add_child(fly)
	# The light it carries, behind it, breathing on its own clock.
	var halo := TextureRect.new()
	halo.texture = _round()
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_SCALE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.size = fly.size * 2.8
	halo.position = -(halo.size - fly.size) * 0.5
	var glow: Color = Color(0.82, 0.95, 1.0) if pale else Color(0.34, 0.66, 1.0)
	halo.modulate = Color(glow.r, glow.g, glow.b, 0.0)
	fly.add_child(halo)
	fly.move_child(halo, 0)
	var wake := CPUParticles2D.new()
	wake.texture = _dot()
	wake.local_coords = false
	wake.amount = 20
	wake.lifetime = 1.7
	wake.randomness = 0.8
	wake.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	wake.emission_sphere_radius = w * 0.22
	wake.direction = Vector2(0, 1)
	wake.spread = 180.0
	wake.gravity = Vector2(0.0, 12.0)
	wake.initial_velocity_min = 2.0
	wake.initial_velocity_max = 15.0
	wake.scale_amount_min = 0.16
	wake.scale_amount_max = 0.52
	wake.color_initial_ramp = _ramp_cols([Color(1.0, 1.0, 1.0),
		Color(0.74, 0.92, 1.0), _pc("accent").lerp(_white(1.0), 0.4)])
	wake.color_ramp = _alpha_ramp(Color(1, 1, 1), 0.85, true)
	wake.emitting = true
	carrier.add_child(wake)
	# --- the four motions, each on its own clock (see the note above).
	var beat: float = randf_range(0.20, 0.32)
	var flap := fly.create_tween().set_loops()
	flap.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	flap.tween_property(fly, "scale:x", 0.34, beat)
	flap.tween_property(fly, "scale:x", 1.0, beat)
	# The bob rides the beat but runs a touch slower, so the two drift in and
	# out of phase instead of locking — a locked bob reads as a bouncing icon.
	var lift: float = w * 0.22
	var bob := fly.create_tween().set_loops()
	bob.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	bob.tween_property(fly, "position:y", -fly.size.y * 0.5 - lift, beat * 1.17)
	bob.tween_property(fly, "position:y", -fly.size.y * 0.5 + lift * 0.6, beat * 1.17)
	fly.rotation = deg_to_rad(randf_range(-12.0, 12.0))
	var bank := fly.create_tween().set_loops()
	bank.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	bank.tween_property(fly, "rotation", fly.rotation + 0.24, randf_range(0.9, 1.6))
	bank.tween_property(fly, "rotation", fly.rotation - 0.24, randf_range(0.9, 1.6))
	# The settle path has to be able to STOP the beat and the bob — a resting
	# butterfly fans slowly, and a looping flap tween left running would fight
	# the fan for `scale:x` and win half the frames.
	fly.set_meta("flap", flap)
	fly.set_meta("bob", bob)
	var pulse := halo.create_tween().set_loops()
	pulse.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(halo, "modulate:a", 0.60, randf_range(0.9, 1.5))
	pulse.tween_property(halo, "modulate:a", 0.24, randf_range(1.0, 1.7))
	return [carrier, fly]

## One crossing the frame: on from one side, out the other, wandering the whole
## way, at one of three depths.
func _fairy_one(pale: bool) -> void:
	var depth: float = randf()
	var w: float = _vp.x * lerpf(0.09, 0.24, depth * depth)
	var rig := _fairy_rig(pale, w)
	var carrier: Control = rig[0]
	var fly: TextureRect = rig[1]
	fly.modulate = Color(1, 1, 1, 0.0)
	var dir: float = 1.0 if randf() < 0.5 else -1.0
	var y0: float = _vp.y * randf_range(0.08, 0.80)
	var pts: Array[Vector2] = []
	for k in 5:
		var t: float = float(k) / 4.0
		var x: float = lerpf(-w * 1.6, _vp.x + w * 1.6, t if dir > 0.0 else 1.0 - t)
		var y: float = y0 if k == 0 else clampf(y0 + randf_range(-0.26, 0.26) * _vp.y,
			-_vp.y * 0.04, _vp.y * 0.92)
		pts.append(Vector2(x, y))
	carrier.position = pts[0]
	# Slower the closer it is: a near butterfly crossing at a far one's speed
	# reads as a bird.
	var leg: float = lerpf(2.2, 3.8, depth)
	var path := carrier.create_tween()
	for k in range(1, pts.size()):
		path.tween_property(carrier, "position", pts[k], leg) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	path.tween_callback(carrier.queue_free)
	var fade := fly.create_tween()
	fade.tween_property(fly, "modulate:a", 1.0, 0.7)
	fade.tween_interval(leg * 4.0 - 1.6)
	fade.tween_property(fly, "modulate:a", 0.0, 0.9)

## One that comes down to the bed, LANDS on a flower, fans its wings there and
## then lifts off again. The landing is the mechanic that sells the rest: a
## grove where every butterfly only ever transits is an aquarium.
func _fairy_settle(pale: bool) -> void:
	var perch: Vector2 = _grove_perches[randi() % _grove_perches.size()]
	var w: float = _vp.x * randf_range(0.13, 0.20)
	var rig := _fairy_rig(pale, w)
	var carrier: Control = rig[0]
	var fly: TextureRect = rig[1]
	fly.modulate = Color(1, 1, 1, 0.0)
	var side: float = 1.0 if perch.x < _vp.x * 0.5 else -1.0
	carrier.position = perch + Vector2(-side * _vp.x * 0.55, -_vp.y * 0.30)
	var approach := carrier.create_tween()
	approach.tween_property(carrier, "position",
		perch + Vector2(-side * w * 1.2, -w * 1.1), 2.6) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	# The last of it is a hover, then a drop onto the head.
	approach.tween_property(carrier, "position", perch - Vector2(0.0, w * 0.42), 1.1) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	var fade := fly.create_tween()
	fade.tween_property(fly, "modulate:a", 1.0, 0.7)
	approach.tween_callback(func() -> void:
		if not is_instance_valid(fly):
			return
		# Settled: the beat stops and becomes the slow fan a resting butterfly
		# does — wide open, most of the way shut, open again.
		var flap_t: Tween = fly.get_meta("flap")
		if flap_t != null and flap_t.is_valid():
			flap_t.kill()
		var bob_t: Tween = fly.get_meta("bob")
		if bob_t != null and bob_t.is_valid():
			bob_t.kill()
		fly.position.y = -fly.size.y * 0.5
		var rest := fly.create_tween().set_loops(4)
		rest.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		rest.tween_property(fly, "scale:x", 0.46, randf_range(1.1, 1.8))
		rest.tween_property(fly, "scale:x", 1.0, randf_range(1.1, 1.8)))
	# ...and then it goes. Off the top, still wandering.
	var leave := carrier.create_tween()
	leave.tween_interval(3.7 + randf_range(5.0, 9.0))
	leave.tween_property(carrier, "position",
		perch + Vector2(side * _vp.x * 0.30, -_vp.y * 0.34), 3.0) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	leave.tween_property(carrier, "position",
		perch + Vector2(side * _vp.x * 0.62, -_vp.y * 0.85), 3.2) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	leave.parallel().tween_property(fly, "modulate:a", 0.0, 2.0).set_delay(1.4)
	leave.tween_callback(carrier.queue_free)

## The clearing they are flying in: a low moon off the corner, its light coming
## down through the canopy, and mist standing between the trunks. The first pass
## lit this scene with a warm corner SUN, which is why the butterflies read as
## specks — there was no cold light for anything to glow against.
## (Not `_moonlit_grove`, which is Moonlit Bamboo's stand of culms.)
func _moonlit_clearing() -> void:
	var moonlight: Color = _pc("accent").lerp(_white(1.0), 0.55)
	# The moon itself, low and off to the left, behind the trees.
	for e_v in [[1.5, 0.10], [0.9, 0.13], [0.34, 0.30]]:
		var e: Array = e_v
		var g := TextureRect.new()
		g.texture = _round()
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_SCALE
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = _vp.x * float(e[0])
		g.size = Vector2(d, d)
		g.position = Vector2(_vp.x * 0.16, _vp.y * 0.22) - g.size * 0.5
		g.modulate = Color(moonlight.r, moonlight.g, moonlight.b, float(e[1]))
		add_child(g)
		var tw := g.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(g, "modulate:a", float(e[1]) * 1.5, randf_range(5.0, 7.5))
		tw.tween_property(g, "modulate:a", float(e[1]) * 0.7, randf_range(5.5, 8.0))
	# Shafts of it coming down between the trunks.
	for i in 4:
		var ray := TextureRect.new()
		ray.texture = _round()
		ray.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ray.stretch_mode = TextureRect.STRETCH_SCALE
		ray.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.16, 0.34)
		var h: float = _vp.y * randf_range(0.60, 1.05)
		ray.size = Vector2(w, h)
		ray.pivot_offset = Vector2(w * 0.5, 0.0)
		ray.position = Vector2(_vp.x * (0.10 + 0.26 * float(i)) - w * 0.5, -h * 0.05)
		ray.rotation = deg_to_rad(randf_range(-16.0, -6.0))
		var peak: float = randf_range(0.05, 0.10)
		ray.modulate = Color(moonlight.r, moonlight.g, moonlight.b, peak * 0.4)
		add_child(ray)
		var tw2 := ray.create_tween().set_loops()
		tw2.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw2.tween_interval(randf_range(0.0, 3.0))
		tw2.tween_property(ray, "modulate:a", peak, randf_range(4.0, 6.5))
		tw2.tween_property(ray, "modulate:a", peak * 0.25, randf_range(4.5, 7.0))
	# Mist lying along the ground, drifting sideways.
	for i in 5:
		var mist := TextureRect.new()
		mist.texture = _round()
		mist.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mist.stretch_mode = TextureRect.STRETCH_SCALE
		mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mw: float = _vp.x * randf_range(0.55, 1.05)
		mist.size = Vector2(mw, _vp.y * randf_range(0.07, 0.13))
		var x0: float = _vp.x * randf_range(-0.25, 0.85)
		mist.position = Vector2(x0, _vp.y * randf_range(0.76, 0.94) - mist.size.y * 0.5)
		mist.modulate = Color(0.62, 0.76, 1.0, randf_range(0.05, 0.10))
		add_child(mist)
		var mt := mist.create_tween().set_loops()
		mt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		var travel: float = _vp.x * randf_range(0.10, 0.22)
		mt.tween_property(mist, "position:x", x0 + travel, randf_range(11.0, 17.0))
		mt.tween_property(mist, "position:x", x0 - travel, randf_range(11.0, 17.0))

func _m_plumage() -> void:
	# Peacock: the train, SHED. Whole eye-feathers turning slowly down through
	# the frame at three depths with loose iridescent barbs combing across them,
	# and the light sweeping the screen now and then the way a real train flashes
	# when the bird turns.
	#
	# There is no bird, and no fanned display either — both were tried and both
	# read as an ornament parked in a corner. What anyone actually pictures at
	# the word "peacock" is the ocellus, the eye on the feather, so the theme is
	# those, falling.
	# Four depths. The far pair are almost out of focus and carry the room; the
	# near ones are the ones you read the eye on.
	_emit({"from": "all", "tex": _feather(), "color": _white(1.0),
		"alpha": 0.10, "amount": 4, "lifetime": 30.0, "dir": Vector3(0.06, 1, 0),
		"spread": 12.0, "vmin": 3.0, "vmax": 9.0, "smin": 1.8, "smax": 2.7,
		"spin": 0.10, "turb": 0.5})
	_emit({"from": "all", "tex": _feather(), "color": _white(1.0),
		"alpha": 0.34, "amount": 13, "lifetime": 22.0, "dir": Vector3(0.10, 1, 0),
		"spread": 16.0, "vmin": 7.0, "vmax": 18.0, "smin": 0.45, "smax": 0.80,
		"spin": 0.22, "turb": 0.7})
	_emit({"from": "all", "tex": _feather(), "color": _white(1.0),
		"alpha": 0.78, "amount": 9, "lifetime": 18.0, "dir": Vector3(0.13, 1, 0),
		"spread": 20.0, "vmin": 14.0, "vmax": 34.0, "smin": 0.75, "smax": 1.15,
		"spin": 0.34, "turb": 0.8})
	# A few close to the lens, big and slow, turning as they fall.
	_emit({"from": "top", "tex": _feather(), "color": _white(1.0),
		"alpha": 0.94, "amount": 3, "lifetime": 17.0, "dir": Vector3(0.18, 1, 0),
		"spread": 24.0, "vmin": 22.0, "vmax": 46.0, "smin": 1.30, "smax": 1.85,
		"spin": 0.48, "turb": 0.9})
	# Loose barbs: fine teal and gold filaments combing sideways off the train.
	_emit({"from": "all", "tex": _dot(), "color": _pc("accent"),
		"alpha": 0.55, "amount": 40, "lifetime": 10.0, "dir": Vector3(0.6, 0.4, 0),
		"spread": 40.0, "vmin": 16.0, "vmax": 52.0, "smin": 0.2, "smax": 0.55,
		"twinkle": true})
	_emit({"from": "all", "tex": _dot(), "color": _pc("gold").lerp(_white(1.0), 0.3),
		"alpha": 0.45, "amount": 20, "lifetime": 12.0, "dir": Vector3(0.4, 0.5, 0),
		"spread": 46.0, "vmin": 10.0, "vmax": 34.0, "smin": 0.2, "smax": 0.5,
		"twinkle": true})
	# The iridescence itself: broad teal and gold blooms turning over each other
	# behind the fall, so the dark has the colour a train has when the bird
	# moves. Without it the background is one flat teal box.
	for e_v in [[0.24, 0.30, 0.80], [0.74, 0.22, 0.62], [0.50, 0.72, 0.95],
			[0.12, 0.82, 0.55]]:
		var e: Array = e_v
		var bloom := TextureRect.new()
		bloom.texture = _round()
		bloom.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bloom.stretch_mode = TextureRect.STRETCH_SCALE
		bloom.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = _vp.x * float(e[2]) * 1.6
		bloom.size = Vector2(d, d * 0.8)
		bloom.position = Vector2(_vp.x * float(e[0]), _vp.y * float(e[1])) - bloom.size * 0.5
		var c: Color = _pc("accent") if randf() < 0.6 else _pc("gold")
		var ba: float = randf_range(0.05, 0.10)
		bloom.modulate = Color(c.r, c.g, c.b, ba)
		add_child(bloom)
		move_child(bloom, 0)
		var bt := bloom.create_tween().set_loops()
		bt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		bt.tween_interval(randf_range(0.0, 4.0))
		bt.tween_property(bloom, "modulate:a", ba * 2.2, randf_range(5.0, 8.0))
		bt.tween_property(bloom, "modulate:a", ba * 0.5, randf_range(5.5, 8.5))
	_shimmer_sweep(_pc("accent"), _gen)
	_edge_glow(_pc("accent"), 0.06, 0.18, true)

# --- The ten premium worlds of 2026-08-27 ---------------------------------------
# Scaffolded together (docs/themes/ten-premium-themes.md) and built out a batch
# at a time. A world that is not authored yet runs the quiet motes, so the
# catalogue is never inert while it waits; each stub below is replaced in turn.
func _m_marble() -> void:
	# Carrara: a sculpture hall. White stone with the veins running through it,
	# brass dust hanging in a skylight, and low plinths along the floor with a
	# sphere, a column and an obelisk on them. Nothing in it moves fast: marble
	# does not move, so the veins are drawn ONCE; what lives is the light (a
	# cloud crossing the skylight), the dust turning in the beam, and a merge,
	# which cracks a fresh vein out of the tile (_marble_crack).
	var stone: Color = _pc("bg0")
	var ink: Color = _pc("text")
	# The skylight: warm light falling from above centre.
	var lamp := TextureRect.new()
	lamp.texture = _round()
	lamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lamp.stretch_mode = TextureRect.STRETCH_SCALE
	lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ld: float = _vp.x * 2.0
	lamp.size = Vector2(ld, ld * 0.8)
	lamp.position = Vector2(_vp.x * 0.5, _vp.y * 0.02) - lamp.size * 0.5
	lamp.modulate = Color(1.0, 0.99, 0.95, 0.34)
	add_child(lamp)
	# The veins. Five, walking in from the top and left edges: grey with a
	# soft bleed, and now and then one in brass.
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.size = _vp
	var veins: Array = []
	# Three long flows, each with a branch; one of them brass.
	for i in 3:
		var from_left: bool = i != 1
		var start: Vector2 = Vector2(-0.04, randf_range(0.05, 0.85)) if from_left \
			else Vector2(randf_range(0.15, 0.85), -0.04)
		var ang: float = randf_range(-0.35, 0.35) if from_left else randf_range(1.2, 1.9)
		veins.append_array(_marble_flow(start * _vp, ang, i == 2))
	canvas.set_meta("veins", veins)
	canvas.set_meta("grow", 1.0)
	canvas.draw.connect(_draw_marble_veins.bind(canvas))
	add_child(canvas)
	canvas.queue_redraw()
	# A cloud crossing the skylight: the wall dims a little and brightens again.
	var cloud := TextureRect.new()
	cloud.texture = _round()
	cloud.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cloud.stretch_mode = TextureRect.STRETCH_SCALE
	cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cloud.size = Vector2(_vp.x * 1.4, _vp.y * 0.55)
	cloud.position = Vector2(-cloud.size.x, -_vp.y * 0.12)
	cloud.modulate = Color(ink.r, ink.g, ink.b, 0.07)
	add_child(cloud)
	var ct := cloud.create_tween().set_loops()
	ct.tween_property(cloud, "position:x", _vp.x, 34.0).set_trans(Tween.TRANS_SINE)
	ct.tween_interval(9.0)
	ct.tween_callback(func() -> void: cloud.position.x = -cloud.size.x)
	# Brass dust in the beam.
	_emit({"from": "all", "tex": _dot(), "color": _pc("gold").lerp(_white(1.0), 0.25),
		"alpha": 0.55, "amount": 24, "lifetime": 13.0, "dir": Vector3(0, -1, 0),
		"spread": 180.0, "vmin": 2.0, "vmax": 8.0, "smin": 0.18, "smax": 0.5,
		"twinkle": true, "turb": 0.5})
	# The floor: only a shadow gathering along the bottom of the wall.
	var floor_shade := TextureRect.new()
	floor_shade.texture = _round()
	floor_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	floor_shade.stretch_mode = TextureRect.STRETCH_SCALE
	floor_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_shade.size = Vector2(_vp.x * 2.2, _vp.y * 0.34)
	floor_shade.position = Vector2((_vp.x - floor_shade.size.x) * 0.5, _vp.y * 0.98 - floor_shade.size.y * 0.5)
	floor_shade.modulate = Color(ink.r, ink.g, ink.b, 0.08)
	add_child(floor_shade)

## A vein that FLOWS: three cubic segments joined with continuous tangents, the
## heading drifting a little at each join, and one thinner branch leaving the
## main flow part-way. Returns the drawer's records (main + branch).
func _marble_flow(start: Vector2, ang: float, gold: bool) -> Array:
	var pts := PackedVector2Array()
	var p: Vector2 = start
	var seg: float = _vp.x * 0.42
	for k in 3:
		var a1: float = ang + randf_range(-0.45, 0.45)
		var c1: Vector2 = p + Vector2(cos(ang), sin(ang)) * seg * 0.38
		var q: Vector2 = p + Vector2(cos(a1), sin(a1)) * seg
		var c2: Vector2 = q - Vector2(cos(a1), sin(a1)) * seg * 0.38
		var part := _bez_px(p, c1, c2, q, 18)
		if k > 0:
			part = part.slice(1)
		pts.append_array(part)
		p = q
		ang = a1
	var w: float = _vp.x * (0.0030 if gold else 0.0045)
	var out: Array = [{"pts": pts, "w": w, "gold": gold}]
	# The branch: off the middle third, at an angle, thinner, shorter.
	var bi: int = int(pts.size() * randf_range(0.3, 0.6))
	var b0: Vector2 = pts[bi]
	var run: Vector2 = (pts[bi + 1] - pts[bi]).normalized()
	var side: float = 1.0 if randf() < 0.5 else -1.0
	var bang: float = run.angle() + side * randf_range(0.5, 0.9)
	var bl: float = seg * randf_range(0.5, 0.8)
	var bq: Vector2 = b0 + Vector2(cos(bang), sin(bang)) * bl
	var bc1: Vector2 = b0 + run * bl * 0.3
	var bc2: Vector2 = bq - Vector2(cos(bang + side * 0.3), sin(bang + side * 0.3)) * bl * 0.3
	out.append({"pts": _bez_px(b0, bc1, bc2, bq, 14), "w": w * 0.6, "gold": gold})
	return out

## One vein: a random walk with momentum, in pixels, from `start` heading `ang`.
## Curl drifts slowly so the line wanders the way a vein does rather than
## jittering; `gold` picks the brass drawing.
func _marble_vein(start: Vector2, ang: float, n: int, step: float, gold: bool) -> Dictionary:
	var pts := PackedVector2Array()
	var p: Vector2 = start
	var curl: float = randf_range(-0.05, 0.05)
	for i in n:
		pts.append(p)
		ang += curl + randf_range(-0.22, 0.22)
		curl = clampf(curl + randf_range(-0.02, 0.02), -0.09, 0.09)
		p += Vector2(cos(ang), sin(ang)) * step * randf_range(0.7, 1.3)
	return {"pts": pts, "w": _vp.x * (0.0035 if gold else 0.006), "gold": gold}

## Draws a canvas's veins up to its `grow` fraction (1.0 = whole vein): a soft
## wide bleed under a thin hard core, the way a vein sits IN the stone rather
## than on it.
func _draw_marble_veins(c: Control) -> void:
	var veins: Array = c.get_meta("veins")
	var grow: float = float(c.get_meta("grow", 1.0))
	var stone: Color = _pc("bg0")
	var ink: Color = _pc("text")
	var grey: Color = ink.lerp(stone, 0.42)
	var gold: Color = _pc("gold")
	for v_v in veins:
		var v: Dictionary = v_v
		var all: PackedVector2Array = v["pts"]
		var n: int = mini(int(ceil(grow * float(all.size()))), all.size())
		if n < 3:
			continue
		var pts: PackedVector2Array = all.slice(0, n)
		var w: float = float(v["w"])
		if bool(v["gold"]):
			c.draw_colored_polygon(_taper_poly(pts, w * 2.4, w * 0.6),
				Color(gold.r, gold.g, gold.b, 0.16))
			c.draw_colored_polygon(_taper_poly(pts, w, w * 0.25),
				Color(gold.r, gold.g, gold.b, 0.62))
		else:
			c.draw_colored_polygon(_taper_poly(pts, w * 5.0, w * 2.0),
				Color(grey.r, grey.g, grey.b, 0.10))
			c.draw_colored_polygon(_taper_poly(pts, w * 2.2, w * 0.9),
				Color(grey.r, grey.g, grey.b, 0.16))
			c.draw_colored_polygon(_taper_poly(pts, w, w * 0.3),
				Color(grey.r, grey.g, grey.b, 0.42))

## The merge: a short vein cracks out of the tile, holds, and fades back into
## the stone. Grown over half a second through the same drawer as the wall.
func _marble_crack(at: Vector2, strength: float) -> void:
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.size = _vp
	var v := _marble_vein(at, randf_range(0.0, TAU), 10 + int(strength * 8.0),
		_vp.x * 0.012, randf() < 0.25)
	canvas.set_meta("veins", [v])
	canvas.set_meta("grow", 0.0)
	canvas.draw.connect(_draw_marble_veins.bind(canvas))
	add_child(canvas)
	var tw := canvas.create_tween()
	tw.tween_method(func(g: float) -> void:
		canvas.set_meta("grow", g)
		canvas.queue_redraw(), 0.0, 1.0, 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_interval(3.5)
	tw.tween_property(canvas, "modulate:a", 0.0, 3.0)
	tw.tween_callback(canvas.queue_free)

## The floor of the hall, in the ground band: a hairline where wall meets
## floor, three plinths, and on them a sphere, a fluted column and an obelisk.
## The obelisk alone crosses a little way into the board glass, for depth.
func _marble_hall(stone: Color) -> void:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = _vp
	c.draw.connect(_draw_marble_hall.bind(c, stone))
	add_child(c)
	c.queue_redraw()

func _draw_marble_hall(c: Control, stone: Color) -> void:
	var ink: Color = _pc("text")
	var floor_y: float = _vp.y * 0.868
	var shade := Color(ink.r, ink.g, ink.b, 0.07)
	var deep := Color(ink.r, ink.g, ink.b, 0.13)
	var lit := Color(1, 1, 1, 0.75)
	c.draw_rect(Rect2(0.0, floor_y, _vp.x, _vp.y - floor_y), Color(ink.r, ink.g, ink.b, 0.07))
	c.draw_line(Vector2(0.0, floor_y), Vector2(_vp.x, floor_y), Color(ink.r, ink.g, ink.b, 0.14), 1.5)
	# Plinths: [x0, x1, height], as fractions of the frame.
	for e_v in [[0.10, 0.28, 0.058], [0.43, 0.57, 0.082], [0.72, 0.90, 0.048]]:
		var e: Array = e_v
		var x0: float = _vp.x * float(e[0])
		var x1: float = _vp.x * float(e[1])
		var h: float = _vp.y * float(e[2])
		var top: float = floor_y - h
		c.draw_rect(Rect2(x0 - 4.0, floor_y, (x1 - x0) + 8.0, 5.0), shade)
		c.draw_rect(Rect2(x0, top, x1 - x0, h), stone.darkened(0.10))
		c.draw_rect(Rect2(x0, top, x1 - x0, 2.0), lit)
		c.draw_rect(Rect2(x1 - 3.0, top, 3.0, h), deep)
	# The sphere, on the middle plinth: lit from the upper left.
	var r: float = _vp.x * 0.052
	var sc := Vector2(_vp.x * 0.50, floor_y - _vp.y * 0.082 - r)
	c.draw_circle(sc + Vector2(r * 0.15, r * 0.10), r * 1.02, Color(ink.r, ink.g, ink.b, 0.10))
	c.draw_circle(sc, r, stone.lightened(0.5))
	c.draw_circle(sc + Vector2(r * 0.18, r * 0.20), r * 0.82, stone.darkened(0.04))
	c.draw_circle(sc + Vector2(-r * 0.35, -r * 0.35), r * 0.22, Color(1, 1, 1, 0.85))
	# The obelisk, on the right plinth: a taper with one lit face.
	var ox: float = _vp.x * 0.81
	var ob: float = floor_y - _vp.y * 0.048
	var oh: float = _vp.y * 0.11
	var ow: float = _vp.x * 0.05
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(ox - ow * 0.5, ob), Vector2(ox + ow * 0.5, ob),
		Vector2(ox + ow * 0.3, ob - oh), Vector2(ox - ow * 0.3, ob - oh)]), stone.darkened(0.05))
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(ox - ow * 0.5, ob), Vector2(ox, ob),
		Vector2(ox, ob - oh * 0.98), Vector2(ox - ow * 0.3, ob - oh)]), Color(1, 1, 1, 0.45))
	# The column, on the left plinth: fluting as hairlines, a capital and a base.
	var cx0: float = _vp.x * 0.15
	var cw: float = _vp.x * 0.075
	var ch: float = _vp.y * 0.075
	var cb: float = floor_y - _vp.y * 0.058
	c.draw_rect(Rect2(cx0, cb - ch, cw, ch), stone.darkened(0.03))
	for k in 5:
		var fx: float = cx0 + cw * (0.12 + 0.19 * float(k))
		c.draw_line(Vector2(fx, cb - ch + 3.0), Vector2(fx, cb - 2.0), Color(ink.r, ink.g, ink.b, 0.10), 1.0)
	c.draw_rect(Rect2(cx0 - 3.0, cb - ch - 4.0, cw + 6.0, 4.0), stone.darkened(0.08))
	c.draw_rect(Rect2(cx0 - 3.0, cb - 3.0, cw + 6.0, 3.0), stone.darkened(0.08))

func _m_noir() -> void:
	# Noir: true black, and the only light in the room is what comes through
	# the blinds. Bars of ivory light lie across the wall at a slant and creep
	# as the hour passes; smoke turns in them; rain runs down the glass. A merge
	# is a flashbulb (_noir_flash). There is no colour anywhere, on purpose.
	# A BLACK SLATE. Nothing is pictured: the grain of the stone, one soft pool
	# of ivory light from above that breathes, a slow sheen crossing it, and a
	# little dust in the light. The restraint is the theme.
	var ivory: Color = _pc("accent")
	var grain := TextureRect.new()
	grain.texture = _shaped("noir_grain", 128, 128, _fn_slate_grain)
	grain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grain.stretch_mode = TextureRect.STRETCH_TILE
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grain.size = _vp
	grain.modulate = Color(ivory.r, ivory.g, ivory.b, 0.08)
	add_child(grain)
	var pool := TextureRect.new()
	pool.texture = _round()
	pool.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pool.stretch_mode = TextureRect.STRETCH_SCALE
	pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pd: float = _vp.x * 1.7
	pool.size = Vector2(pd, pd)
	pool.position = Vector2(_vp.x * 0.5, _vp.y * 0.08) - pool.size * 0.5
	pool.modulate = Color(ivory.r, ivory.g, ivory.b, 0.09)
	add_child(pool)
	var pt := pool.create_tween().set_loops()
	pt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	pt.tween_property(pool, "modulate:a", 0.14, 7.0)
	pt.tween_property(pool, "modulate:a", 0.08, 7.5)
	_emit({"from": "all", "tex": _dot(), "color": ivory,
		"alpha": 0.28, "amount": 16, "lifetime": 16.0, "dir": Vector3(0.05, -1, 0),
		"spread": 180.0, "vmin": 1.5, "vmax": 5.0, "smin": 0.14, "smax": 0.36,
		"twinkle": true, "turb": 0.4})
	_shimmer_sweep(ivory, _gen)
	_edge_glow(ivory, 0.02, 0.05, false)

## The grain of a slate: fine hashed speckle with a few broader, fainter bands,
## tiled over the black at very low alpha. A surface, not a void.
func _fn_slate_grain(uv: Vector2) -> Color:
	var p: Vector2 = (uv + Vector2(1.0, 1.0)) * 64.0
	var fine: float = _hash2(Vector2(floor(p.x), floor(p.y)))
	var band: float = 0.5 + 0.5 * sin(uv.y * 9.0 + sin(uv.x * 4.0) * 1.5)
	var b: float = 0.35 + 0.65 * fine
	return Color(b, b, b, 0.35 + 0.45 * band * fine)

## The city outside the window, along the floor of the frame: a far row in
## the haze and a near row with its windows lit ivory, a water tank or an
## aerial on the odd roof. The blinds' bars lie over it, so what the player
## sees is the town through the slats.
func _noir_skyline(ivory: Color) -> void:
	for far_v in [true, false]:
		var far: bool = far_v
		var xs := randf_range(-0.05, -0.01)
		while xs < 1.04:
			var bw: float = randf_range(0.05, 0.10) if far else randf_range(0.07, 0.14)
			var bh: float = randf_range(0.07, 0.115) if far else randf_range(0.045, 0.09)
			var b := TextureRect.new()
			b.texture = _noir_building(randi() % 3)
			b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			b.stretch_mode = TextureRect.STRETCH_SCALE
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.size = Vector2(_vp.x * bw, _vp.y * bh)
			b.position = Vector2(_vp.x * xs, _vp.y * 0.885 - b.size.y)
			b.modulate = Color(ivory.r, ivory.g, ivory.b, 0.30) if far else Color(1, 1, 1, 0.9)
			add_child(b)
			if not far and randf() < 0.45:
				var mast := ColorRect.new()
				mast.color = Color(0.02, 0.02, 0.02, 1.0)
				mast.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var thin := randf() < 0.6
				mast.size = Vector2(_vp.x * 0.005, _vp.y * randf_range(0.015, 0.035)) if thin \
					else Vector2(b.size.x * 0.35, _vp.y * 0.012)
				mast.position = b.position + Vector2(b.size.x * randf_range(0.25, 0.7), -mast.size.y)
				add_child(mast)
			xs += bw * (randf_range(0.6, 0.8) if far else randf_range(0.8, 1.0))

func _noir_building(v: int) -> ImageTexture:
	var sd := float(v) * 11.3
	return _shaped("noir_bld_%d" % v, 40, 120, _fn_noir_building.bind(sd))

## A facade at night: near-black, with a scatter of windows lit warm and one
## in five of them brighter, the way a block of flats reads after midnight.
func _fn_noir_building(uv: Vector2, sd: float) -> Color:
	var p := uv * 0.5 + Vector2(0.5, 0.5)
	var cols := 4.0
	var rows := 12.0
	var cell := Vector2(floor(p.x * cols), floor(p.y * rows))
	var f := Vector2(p.x * cols - cell.x, p.y * rows - cell.y)
	if f.x <= 0.28 or f.x >= 0.72 or f.y <= 0.22 or f.y >= 0.78:
		return Color(0.02, 0.02, 0.025, 1.0)
	if _hash2(cell + Vector2(sd, sd * 0.7)) < 0.70:
		return Color(0.035, 0.035, 0.04, 1.0)
	var b := 0.30 + 0.45 * _hash2(cell + Vector2(1.7, sd + 9.2))
	if _hash2(cell + Vector2(sd + 3.1, 5.5)) > 0.8:
		b = 0.95
	return Color(0.95 * b, 0.91 * b, 0.84 * b, 1.0)

## The light through the blinds: slats of ivory brightest at the right (the
## window is that way) and fading out to the left, strongest mid-wall, with the
## dark stripe of the frame's mullion cut through every band.
func _draw_noir_blinds(c: Control, ivory: Color) -> void:
	var w: float = c.size.x
	var h: float = c.size.y
	var pitch: float = h * 0.036
	var slat: float = pitch * 0.55
	var x0: float = w * 0.08
	var x1: float = w * 0.97
	var gap0: float = w * 0.60
	var gap1: float = gap0 + w * 0.025
	var y: float = h * 0.04
	while y < h * 0.98:
		var env: float = sin(clampf((y / h - 0.04) / 0.94, 0.0, 1.0) * PI)
		var a: float = 0.14 * (0.55 + 0.45 * env)
		for seg_v in [[x0, gap0], [gap1, x1]]:
			var seg: Array = seg_v
			var sx0: float = float(seg[0])
			var sx1: float = float(seg[1])
			var pts := PackedVector2Array([Vector2(sx0, y), Vector2(sx1, y),
				Vector2(sx1, y + slat), Vector2(sx0, y + slat)])
			var cols := PackedColorArray([
				Color(ivory.r, ivory.g, ivory.b, a * 0.15), Color(ivory.r, ivory.g, ivory.b, a),
				Color(ivory.r, ivory.g, ivory.b, a), Color(ivory.r, ivory.g, ivory.b, a * 0.15)])
			c.draw_polygon(pts, cols)
		y += pitch

## The merge: a flashbulb. One ivory frame, gone in a third of a second, never
## more than twice a second (a multi-merge frame is one flash, not a strobe),
## and not at all under reduce motion.
var _noir_flash_t: float = -10.0

func _noir_flash(strength: float) -> void:
	if SettingsManager.reduce_motion():
		return
	var now: float = float(Time.get_ticks_msec()) * 0.001
	if now - _noir_flash_t < 0.45:
		return
	_noir_flash_t = now
	var flash := ColorRect.new()
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.position = Vector2.ZERO
	flash.size = _vp
	var ivory: Color = _pc("accent")
	flash.color = Color(ivory.r, ivory.g, ivory.b, 0.0)
	add_child(flash)
	var tw := flash.create_tween()
	tw.tween_property(flash, "color:a", clampf(0.05 + 0.04 * strength, 0.0, 0.12), 0.05)
	tw.tween_property(flash, "color:a", 0.0, 0.34).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(flash.queue_free)

func _m_mono() -> void:
	# Mono: a page ruled in hairlines, and one red dot. That is the whole world,
	# and the restraint is the point: nothing here is decorated, so the board is
	# the only thing on screen with any weight. The dot walks the grid on a slow
	# clock, one axis at a time; a merge is one red ring; a swipe nudges the
	# rule (_mono_nudge).
	var ink: Color = _pc("text")
	var grid := Control.new()
	grid.name = "MonoGrid"
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.size = _vp
	grid.draw.connect(_draw_mono_grid.bind(grid, ink))
	add_child(grid)
	grid.queue_redraw()
	var d: float = _vp.x * 0.058
	var dot := TextureRect.new()
	dot.texture = _disc()
	dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dot.stretch_mode = TextureRect.STRETCH_SCALE
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.size = Vector2(d, d)
	dot.pivot_offset = dot.size * 0.5
	dot.position = _mono_point() - dot.size * 0.5
	dot.modulate = _pc("accent")
	add_child(dot)
	_mono_walk(dot, _gen)

func _draw_mono_grid(c: Control, ink: Color) -> void:
	var pitch: float = _vp.x / 12.0
	var thin := Color(ink.r, ink.g, ink.b, 0.10)
	var heavy := Color(ink.r, ink.g, ink.b, 0.18)
	var x: float = 0.0
	var i := 0
	while x <= _vp.x + 1.0:
		c.draw_line(Vector2(x, 0.0), Vector2(x, _vp.y), heavy if i % 4 == 0 else thin, 1.0)
		x += pitch
		i += 1
	var y: float = 0.0
	i = 0
	while y <= _vp.y + 1.0:
		c.draw_line(Vector2(0.0, y), Vector2(_vp.x, y), heavy if i % 4 == 0 else thin, 1.0)
		y += pitch
		i += 1
	# Registration marks in the corners: a circle crossed by two hairlines.
	var m: float = _vp.x * 0.03
	var mark := Color(ink.r, ink.g, ink.b, 0.22)
	for p_v in [Vector2(m * 1.6, m * 1.6), Vector2(_vp.x - m * 1.6, m * 1.6),
			Vector2(m * 1.6, _vp.y - m * 1.6), Vector2(_vp.x - m * 1.6, _vp.y - m * 1.6)]:
		var p: Vector2 = p_v
		c.draw_arc(p, m * 0.5, 0.0, TAU, 32, mark, 1.0)
		c.draw_line(p - Vector2(m, 0.0), p + Vector2(m, 0.0), mark, 1.0)
		c.draw_line(p - Vector2(0.0, m), p + Vector2(0.0, m), mark, 1.0)

## A grid intersection in one of the two clear bands (the sky above the score
## panel's shadow, the floor between the board and the tray).
func _mono_point() -> Vector2:
	var pitch: float = _vp.x / 12.0
	var rows: Array = []
	var k := 1
	while pitch * float(k) < _vp.y:
		var f: float = pitch * float(k) / _vp.y
		if (f > 0.05 and f < 0.31) or (f > 0.76 and f < 0.87):
			rows.append(k)
		k += 1
	var row: int = int(rows[randi() % rows.size()]) if not rows.is_empty() else 2
	var col: int = 1 + randi() % 11
	return Vector2(pitch * float(col), pitch * float(row))

## The dot's walk: every few seconds it moves to another intersection, along
## the rule (one axis, then the other), never cutting across a cell.
func _mono_walk(dot: TextureRect, gen: int) -> void:
	while is_inside_tree() and gen == _gen and is_instance_valid(dot):
		await get_tree().create_timer(randf_range(5.0, 9.0)).timeout
		if gen != _gen or not is_inside_tree() or not is_instance_valid(dot):
			return
		if SettingsManager.reduce_motion():
			continue
		var to: Vector2 = _mono_point() - dot.size * 0.5
		var tw := dot.create_tween()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(dot, "position:x", to.x, 1.4)
		tw.tween_property(dot, "position:y", to.y, 1.2)

## The swipe: the whole rule shifts a few pixels the way the board moved and
## settles back. Nothing is thrown; Mono does not throw things.
func _mono_nudge(dir: Vector2) -> void:
	var grid := get_node_or_null("MonoGrid") as Control
	if grid == null or SettingsManager.reduce_motion():
		return
	var tw := grid.create_tween()
	tw.tween_property(grid, "position", dir * _vp.x * 0.012, 0.10) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(grid, "position", Vector2.ZERO, 0.35) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

const _WASH_PIGMENTS := ["F2C94C", "E88BA8", "9B7FD1", "3D7AB8", "2E5C8A", "E07A5F"]

func _m_wash() -> void:
	# Aquarelle: pigment on wet cold-press paper. Blooms of colour spread with
	# the darker rim a backrun leaves, hold while the paper is wet and sink into
	# it; some let a drip run. A sky wash lies across the top and a bleed of
	# prussian blue pools along the floor. A merge is a fresh drop of the tile's
	# own colour (_wash_drop); a swipe tilts the sheet and the wet paint runs
	# with it (_wash_run).
	var acc: Color = _pc("accent")
	var sky := TextureRect.new()
	sky.texture = _sky_ramp([Color(acc.r, acc.g, acc.b, 0.20), Color(acc.r, acc.g, acc.b, 0.0)])
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.size = Vector2(_vp.x, _vp.y * 0.34)
	add_child(sky)
	var pool := TextureRect.new()
	pool.texture = _round()
	pool.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pool.stretch_mode = TextureRect.STRETCH_SCALE
	pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pool.size = Vector2(_vp.x * 1.6, _vp.y * 0.22)
	pool.position = Vector2((_vp.x - pool.size.x) * 0.5, _vp.y * 0.86 - pool.size.y * 0.5)
	var pr := Color("2E5C8A")
	pool.modulate = Color(pr.r, pr.g, pr.b, 0.16)
	add_child(pool)
	# The sheet the paint lives on, so a swipe can move it as one thing.
	var layer := Control.new()
	layer.name = "WashLayer"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.size = _vp
	add_child(layer)
	_wash_strokes()
	for i in 3:
		_wash_bloom(layer, _wash_spot(), _wash_pigment(), true)
	_wash_blooms(layer, _gen)
	# Pigment specks in the water.
	var pig: Array = []
	for h in _WASH_PIGMENTS:
		pig.append(Color(String(h)))
	_emit({"from": "all", "tex": _dot(), "iramp": _ramp_cols(pig),
		"alpha": 0.4, "amount": 26, "lifetime": 11.0, "dir": Vector3(0, -1, 0),
		"spread": 180.0, "vmin": 2.0, "vmax": 7.0, "smin": 0.16, "smax": 0.4,
		"twinkle": true, "turb": 0.6})

## The painter's strokes: wide wet sweeps across the sky and along the floor,
## each a tapered bezier with a drier, thinner stroke laid over it so the edge
## breaks the way a loaded brush does.
func _wash_strokes() -> void:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = _vp
	var strokes: Array = []
	# [y at the left, y at the right, sag, width frac of height, pigment, alpha]
	for e_v in [[0.10, 0.20, 0.06, 0.075, "3D7AB8", 0.34], [0.26, 0.17, -0.05, 0.05, "9B7FD1", 0.28],
			[0.83, 0.79, 0.03, 0.055, "2E5C8A", 0.32], [0.90, 0.86, -0.02, 0.03, "E07A5F", 0.26]]:
		var e: Array = e_v
		var y0: float = _vp.y * float(e[0])
		var y1: float = _vp.y * float(e[1])
		var sag: float = _vp.y * float(e[2])
		var a := Vector2(-_vp.x * 0.06, y0)
		var b := Vector2(_vp.x * 1.06, y1)
		var c1 := Vector2(_vp.x * 0.30, y0 + sag)
		var c2 := Vector2(_vp.x * 0.70, y1 + sag)
		strokes.append({"pts": _bez_px(a, c1, c2, b, 24), "w": _vp.y * float(e[3]),
			"col": Color(String(e[4])), "a": float(e[5])})
	c.set_meta("strokes", strokes)
	c.draw.connect(_draw_wash_strokes.bind(c))
	add_child(c)
	c.queue_redraw()

func _draw_wash_strokes(c: Control) -> void:
	var strokes: Array = c.get_meta("strokes")
	for s_v in strokes:
		var s: Dictionary = s_v
		var pts: PackedVector2Array = s["pts"]
		var w: float = float(s["w"])
		var col: Color = s["col"]
		var a: float = float(s["a"])
		c.draw_colored_polygon(_taper_poly(pts, w * 0.8, w * 1.1), Color(col.r, col.g, col.b, a))
		# The drier pass rides the lower edge, thinner and a shade darker.
		var low := PackedVector2Array()
		for p in pts:
			low.append(p + Vector2(0.0, w * 0.32))
		var d: Color = col.darkened(0.2)
		c.draw_colored_polygon(_taper_poly(low, w * 0.30, w * 0.18), Color(d.r, d.g, d.b, a * 0.9))

func _wash_pigment() -> Color:
	return Color(String(_WASH_PIGMENTS[randi() % _WASH_PIGMENTS.size()]))

## Somewhere in the two clear bands, mostly; the odd one lands behind the glass.
func _wash_spot() -> Vector2:
	var r := randf()
	var fy: float
	if r < 0.45:
		fy = randf_range(0.04, 0.34)
	elif r < 0.85:
		fy = randf_range(0.62, 0.92)
	else:
		fy = randf_range(0.34, 0.62)
	return Vector2(_vp.x * randf_range(0.05, 0.95), _vp.y * fy)

## One bloom: a soft body of pigment and the darker ring of its edge, scaled up
## as one node. `instant` blooms are already spread (the frame is never bare);
## the rest spread over several seconds, hold, and sink into the paper.
func _wash_bloom(layer: Control, at: Vector2, col: Color, instant: bool,
		life: float = 26.0, size_frac: float = -1.0, spread: float = -1.0) -> Control:
	var b := Control.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d: float = _vp.x * (size_frac if size_frac > 0.0 else randf_range(0.22, 0.42))
	b.size = Vector2(d, d)
	b.position = at - b.size * 0.5
	b.pivot_offset = b.size * 0.5
	var body := TextureRect.new()
	body.texture = _shaped("wash_bloom", 96, 96, _fn_wash_bloom)
	body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	body.stretch_mode = TextureRect.STRETCH_SCALE
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size = b.size
	body.modulate = Color(col.r, col.g, col.b, 0.62)
	body.rotation = randf_range(0.0, TAU)
	body.pivot_offset = body.size * 0.5
	b.add_child(body)
	layer.add_child(b)
	var tw := b.create_tween()
	if instant:
		b.scale = Vector2.ONE * randf_range(0.7, 1.0)
		tw.tween_interval(life * randf_range(0.3, 0.6))
	else:
		b.scale = Vector2(0.15, 0.15)
		b.modulate.a = 0.0
		tw.set_parallel(true)
		tw.tween_property(b, "scale", Vector2.ONE * randf_range(0.8, 1.05),
			spread if spread > 0.0 else randf_range(6.0, 9.0)) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(b, "modulate:a", 1.0, 1.2)
		tw.chain().tween_interval(life * 0.4)
		if randf() < 0.35:
			_wash_drip(layer, at + Vector2(randf_range(-d * 0.2, d * 0.2), d * 0.18), col)
	tw.chain().tween_property(b, "modulate:a", 0.0, life * 0.5)
	tw.chain().tween_callback(b.queue_free)
	return b

## A backrun, the thing watercolour does that nothing else does: flat pigment
## through the middle, pooling darker toward an edge that wanders, then
## stopping hard. Baked once as a mask and tinted per bloom.
func _fn_wash_bloom(uv: Vector2) -> Color:
	var r := uv.length()
	var ang := atan2(uv.y, uv.x)
	# Two or three slow lobes and a little roughness: a puddle, not a flower.
	var wob: float = 0.90 + 0.06 * sin(ang * 3.0 + 1.3) + 0.03 * sin(ang * 7.0 + 0.4) \
		+ 0.015 * sin(ang * 17.0)
	var e: float = r / wob
	if e > 1.0:
		return Color(0, 0, 0, 0)
	# Thin through the middle, the pigment having run to the edge; granulated
	# everywhere, the way pigment settles into the tooth of the paper.
	var body: float = 0.30 + 0.22 * (1.0 - e) * (1.0 - e)
	var rim: float = smoothstep(0.66, 0.97, e)
	var grain: float = 0.80 + 0.20 * _hash2(uv * 37.0)
	var a: float = clampf(body + rim * 0.62, 0.0, 1.0) * grain * (1.0 - smoothstep(0.975, 1.0, e))
	var b: float = 1.0 - rim * 0.40
	return Color(b, b, b, a)

## A run of paint out of the bottom of a bloom: a streak that lengthens slowly,
## then sinks in with the rest.
func _wash_drip(layer: Control, from: Vector2, col: Color) -> void:
	var s := TextureRect.new()
	s.texture = _streak()
	s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	s.stretch_mode = TextureRect.STRETCH_SCALE
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w: float = _vp.x * 0.014
	var reach: float = _vp.y * randf_range(0.08, 0.2)
	s.size = Vector2(w, reach)
	s.pivot_offset = Vector2(w * 0.5, 0.0)
	s.scale = Vector2(1.0, 0.05)
	s.position = from - Vector2(w * 0.5, 0.0)
	s.modulate = Color(col.r, col.g, col.b, 0.32)
	layer.add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "scale:y", 1.0, randf_range(4.0, 7.0)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_interval(8.0)
	tw.tween_property(s, "modulate:a", 0.0, 9.0)
	tw.tween_callback(s.queue_free)

func _wash_blooms(layer: Control, gen: int) -> void:
	while is_inside_tree() and gen == _gen and is_instance_valid(layer):
		await get_tree().create_timer(randf_range(3.5, 6.0)).timeout
		if gen != _gen or not is_inside_tree() or not is_instance_valid(layer):
			return
		if layer.get_child_count() >= 6:
			continue
		_wash_bloom(layer, _wash_spot(), _wash_pigment(), false)

## The merge: a drop of the tile's own colour lands on the page and spreads.
func _wash_drop(at: Vector2, value: int) -> void:
	var layer := get_node_or_null("WashLayer") as Control
	if layer == null:
		return
	var style := ThemeManager.tile_style_for(_pal(), value)
	var col: Color = _saturate(style["bg"] as Color)
	_wash_bloom(layer, at, col, false, 14.0, randf_range(0.16, 0.24), 1.2)

## The swipe: the sheet tilts and the wet paint runs a little way with it.
func _wash_run(dir: Vector2) -> void:
	var layer := get_node_or_null("WashLayer") as Control
	if layer == null or SettingsManager.reduce_motion():
		return
	var tw := layer.create_tween()
	tw.tween_property(layer, "position", dir * _vp.x * 0.02, 0.5) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(layer, "position", Vector2.ZERO, 1.6) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

const _BISMUTH_FILM := ["E8C95A", "D2408A", "5A3FB0", "2BB8A0", "2E7CE6"]

func _m_bismuth() -> void:
	# Bismuth: hopper crystals, the square stepped spirals the metal grows
	# into, wearing the oxide film that turns them every colour at once. DRAWN,
	# never baked: nested squares with a lit edge and a shadowed edge, each step
	# set a little off the last so the stack spirals. One hero crystal in the
	# sky band, a cluster along the floor, the film's colour turning slowly over
	# all of them, and iridescent dust between. A merge grows a step (_bismuth_step).
	# The film first: thin-film interference drifting over the dark, the light
	# a bismuth surface throws when it turns. The crystals sit IN that light and
	# show as edges.
	_bismuth_film()
	var hero := Vector2(_vp.x * 0.50, _vp.y * 0.235)
	var glow := TextureRect.new()
	glow.texture = _round()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gd: float = _vp.x * 1.1
	glow.size = Vector2(gd, gd)
	glow.position = hero - glow.size * 0.5
	var acc: Color = _pc("accent")
	glow.modulate = Color(acc.r, acc.g, acc.b, 0.07)
	add_child(glow)
	var gt := glow.create_tween().set_loops()
	gt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	gt.tween_property(glow, "modulate:a", 0.12, 6.0)
	gt.tween_property(glow, "modulate:a", 0.06, 6.5)
	var canvas := Control.new()
	canvas.name = "Hoppers"
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.size = _vp
	var crystals: Array = []
	# [x, y, size as a fraction of the width, rotation in degrees, steps]
	for e_v in [[0.50, 0.235, 0.34, 12.0, 8], [0.14, 0.845, 0.20, -20.0, 6],
			[0.84, 0.835, 0.26, 8.0, 7]]:
		var e: Array = e_v
		crystals.append({"c": Vector2(_vp.x * float(e[0]), _vp.y * float(e[1])),
			"s": _vp.x * float(e[2]), "rot": deg_to_rad(float(e[3])), "steps": int(e[4]),
			"phase": randf(), "dir": 1 if randf() < 0.5 else -1})
	canvas.set_meta("crystals", crystals)
	canvas.set_meta("phase", 0.0)
	canvas.draw.connect(_draw_bismuth.bind(canvas))
	add_child(canvas)
	canvas.queue_redraw()
	# The film turns: the whole colour walk drifts round the wheel, slowly.
	var tw := canvas.create_tween().set_loops()
	# Redrawn at ~10 Hz, not every frame: the walk moves 1/48 of the wheel a
	# second, so a redraw every sixth frame is invisible and costs a sixth.
	tw.tween_method(func(ph: float) -> void:
		if Engine.get_process_frames() % 6 == 0:
			canvas.set_meta("phase", ph)
			canvas.queue_redraw(), 0.0, 1.0, 48.0)
	var film: Array = []
	for h in _BISMUTH_FILM:
		film.append(Color(String(h)))
	# Iridescent dust, and a few loose facets tumbling.
	_emit({"from": "all", "tex": _dot(), "iramp": _ramp_cols(film),
		"alpha": 0.55, "amount": 24, "lifetime": 12.0, "dir": Vector3(0, -1, 0),
		"spread": 180.0, "vmin": 3.0, "vmax": 10.0, "smin": 0.18, "smax": 0.45,
		"twinkle": true, "turb": 0.5})
	_shimmer_sweep(_pc("accent2"), _gen)
	_edge_glow(acc, 0.05, 0.14, true)

## Thin-film interference over the dark: a slow noise field mapped through a
## cosine palette, brightest in a soft pool behind the hero crystal. Hosted in
## the low-res shader layer like the aurora.
const _FILM_CODE := """
shader_type canvas_item;
uniform float speed = 0.03;
uniform float alpha = 0.16;

vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}
float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(dot(hash22(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
				   dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
			   mix(dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
				   dot(hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * gnoise(p); p *= 2.0; a *= 0.5; }
	return v;
}
void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	float n = fbm(vec2(uv.x * 2.2 + t, uv.y * 3.0 - t * 0.6))
		+ 0.5 * fbm(vec2(uv.x * 5.0 - t * 0.4, uv.y * 4.0 + t));
	vec3 col = 0.5 + 0.5 * cos(6.2831 * (n * 1.6 + vec3(0.0, 0.33, 0.67)));
	float v = 1.0 - smoothstep(0.30, 0.95, length((uv - vec2(0.5, 0.35)) * vec2(1.0, 0.75)));
	COLOR = vec4(col, alpha * (0.30 + 0.70 * v));
}
"""
static var _film_shader: Shader = null

func _bismuth_film() -> void:
	if _film_shader == null:
		_film_shader = Shader.new()
		_film_shader.code = _FILM_CODE
	var mat := ShaderMaterial.new()
	mat.shader = _film_shader
	mat.set_shader_parameter("alpha", 0.26)
	_shader_layer(mat)

## The oxide film's colour at `t` (cycles): gold, magenta, violet, teal, blue.
func _bismuth_col(t: float) -> Color:
	var n: int = _BISMUTH_FILM.size()
	var f: float = fposmod(t, 1.0) * float(n)
	var i: int = int(floor(f)) % n
	var j: int = (i + 1) % n
	return Color(String(_BISMUTH_FILM[i])).lerp(Color(String(_BISMUTH_FILM[j])), f - floor(f))

## A square of half-side `half` about `centre`, turned by `rot`.
func _sq(centre: Vector2, half: float, rot: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		out.append(centre + (k as Vector2).rotated(rot) * half)
	return out

func _draw_bismuth(c: Control) -> void:
	var crystals: Array = c.get_meta("crystals")
	var phase: float = float(c.get_meta("phase", 0.0))
	for cr_v in crystals:
		var cr: Dictionary = cr_v
		var centre: Vector2 = cr["c"]
		var s: float = float(cr["s"])
		var rot: float = float(cr["rot"])
		var steps: int = int(cr["steps"])
		var dir: float = float(int(cr["dir"]))
		var ph0: float = float(cr["phase"])
		for i in steps:
			var f: float = float(i) / float(steps)
			var half: float = s * 0.5 * (1.0 - 0.86 * f)
			var a: float = rot + dir * float(i) * (PI * 0.5)
			var off: Vector2 = Vector2(cos(a), sin(a)) * s * 0.035 * float(i)
			var col: Color = _saturate(_bismuth_col(ph0 + phase + f * 0.9))
			var ctr: Vector2 = centre + off
			# A crystal in the dark: the faces barely there, the RISERS a shade
			# darker still, and the light living on the edges - the film's colour
			# along the two edges toward the light, shadow along the two away.
			c.draw_colored_polygon(_sq(ctr, half, rot), Color(0.0, 0.0, 0.0, 0.30))
			var riser: float = maxf(half * 0.16, 1.5)
			var face := _sq(ctr, half - riser, rot)
			var fc: Color = col.darkened(0.72)
			var cols := PackedColorArray([Color(fc.r, fc.g, fc.b, 0.55), Color(fc.r, fc.g, fc.b, 0.40),
				Color(fc.r, fc.g, fc.b, 0.30), Color(fc.r, fc.g, fc.b, 0.40)])
			c.draw_polygon(face, cols)
			var hi := Color(col.r, col.g, col.b, 0.85)
			var lo := Color(col.r, col.g, col.b, 0.22)
			c.draw_line(face[0], face[1], hi, 1.6, true)
			c.draw_line(face[0], face[3], hi, 1.6, true)
			c.draw_line(face[1], face[2], lo, 1.2, true)
			c.draw_line(face[2], face[3], lo, 1.2, true)
			# The outer wall's lit edge too, so the step has thickness.
			var outer := _sq(ctr, half, rot)
			c.draw_line(outer[0], outer[1], Color(col.r, col.g, col.b, 0.35), 1.0, true)
			c.draw_line(outer[0], outer[3], Color(col.r, col.g, col.b, 0.35), 1.0, true)
			# The specular: one white sliver where the top step catches the lamp.
			if i == steps - 1:
				c.draw_line(face[0], face[1], Color(1, 1, 1, 0.75), 2.0, true)

## The merge: a new step grows out of the tile, turning as it spreads.
func _bismuth_step(at: Vector2, strength: float) -> void:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = _vp
	c.set_meta("crystals", [{"c": at, "s": minf(_vp.x, _vp.y) * 0.05,
		"rot": randf_range(0.0, TAU), "steps": 4, "phase": randf(), "dir": 1}])
	c.set_meta("phase", 0.0)
	c.pivot_offset = at
	c.scale = Vector2(0.3, 0.3)
	c.draw.connect(_draw_bismuth.bind(c))
	add_child(c)
	c.queue_redraw()
	var tw := c.create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE * (2.2 + strength), 0.6) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(c, "rotation", 0.5, 0.6)
	tw.tween_property(c, "modulate:a", 0.0, 0.55).set_delay(0.15)
	tw.chain().tween_callback(c.queue_free)

# --- Shared bake maths for the landscape worlds ------------------------------------
## Soft coverage of an ellipse (centre `c`, radii `r`) at `p`: 1 inside, 0 out.
func _ell(p: Vector2, c: Vector2, r: Vector2) -> float:
	var d: float = ((p - c) / r).length()
	return 1.0 - smoothstep(0.90, 1.06, d)

## Soft coverage of a stroke from `a` to `b`, half-width `w0` at `a` tapering
## to `w1` at `b`. Thin parts are swept SEGMENTS, never triangles.
func _stroke(p: Vector2, a: Vector2, b: Vector2, w0: float, w1: float) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-5), 0.0, 1.0)
	var d := (p - (a + ab * t)).length()
	var w := lerpf(w0, w1, t)
	return 1.0 - smoothstep(w * 0.85, w * 1.08, d)

## A warm grade over the whole frame: golden hour.
func _warm_hour(a: float) -> void:
	var veil := ColorRect.new()
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(1.0, 0.72, 0.30, a)
	add_child(veil)

## A violet grade: dusk.
func _dusk_veil(a: float) -> void:
	var veil := ColorRect.new()
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.17, 0.09, 0.22, a)
	add_child(veil)

## A frond: a rachis swept from `base` along `dir` for `length`, bending under
## its own weight by `droop`, with leaflets in pairs off it. Palms and ferns
## both; `col` carries the alpha, so a shadow and a leaf are the same drawing.
func _draw_frond(c: Control, base: Vector2, dir: Vector2, length: float, w: float,
		col: Color, n: int, droop: float) -> void:
	var d := dir.normalized()
	var nrm := Vector2(-d.y, d.x)
	var tip: Vector2 = base + d * length + nrm * droop * length
	var mid: Vector2 = base + d * length * 0.5 + nrm * droop * length * 0.22
	var pts := _bez_px(base, mid, mid, tip, 16)
	c.draw_colored_polygon(_taper_poly(pts, w, w * 0.25), col)
	for i in n:
		var t: float = 0.12 + 0.84 * float(i) / float(maxi(n - 1, 1))
		var idx: int = mini(int(t * float(pts.size() - 1)), pts.size() - 2)
		var at: Vector2 = pts[idx]
		var run: Vector2 = (pts[idx + 1] - at).normalized()
		var reach: float = length * 0.30 * (1.0 - 0.55 * t)
		for side_v in [1.0, -1.0]:
			var side: float = float(side_v)
			var ln: Vector2 = Vector2(-run.y, run.x) * side
			var leaf_tip: Vector2 = at + (run * 0.55 + ln * 0.85).normalized() * reach
			var lmid: Vector2 = at.lerp(leaf_tip, 0.5) + ln * reach * 0.10
			c.draw_colored_polygon(
				_taper_poly(_bez_px(at, lmid, lmid, leaf_tip, 6), w * 0.9, w * 0.12), col)

## A cumulus: a heap of rounded tops on a flat base, lit from above and a
## little from the left, the underside going grey.
func _fn_cumulus(uv: Vector2) -> Color:
	var a := 0.0
	for e_v in [[-0.50, 0.25, 0.38], [-0.15, -0.05, 0.50], [0.25, -0.18, 0.46],
			[0.60, 0.15, 0.38], [0.05, 0.30, 0.55]]:
		var e: Array = e_v
		a = maxf(a, _ell(uv, Vector2(float(e[0]), float(e[1])),
			Vector2(float(e[2]), float(e[2]))))
	a *= 1.0 - smoothstep(0.55, 0.68, uv.y)
	if a <= 0.01:
		return Color(0, 0, 0, 0)
	var b: float = clampf(0.78 + 0.22 * (-uv.y) - 0.10 * uv.x, 0.45, 1.0)
	b = lerpf(b, 0.60, smoothstep(0.25, 0.65, uv.y))
	return Color(b, b, b, a)

## A hot-air balloon: the envelope in gores, the throat, two ropes, a basket.
## Brightness carries the gores so a tint gives each balloon its own colour.
func _fn_hot_balloon(uv: Vector2) -> Color:
	var env: float = _ell(uv, Vector2(0.0, -0.32), Vector2(0.60, 0.60))
	if _in_tri(uv, Vector2(-0.56, -0.12), Vector2(0.56, -0.12), Vector2(0.0, 0.52)):
		env = 1.0
	var rope: float = maxf(_stroke(uv, Vector2(-0.11, 0.48), Vector2(-0.12, 0.72), 0.02, 0.02),
		_stroke(uv, Vector2(0.11, 0.48), Vector2(0.12, 0.72), 0.02, 0.02))
	var basket: float = 1.0 if (absf(uv.x) < 0.17 and uv.y > 0.70 and uv.y < 0.92) else 0.0
	var a: float = maxf(env, maxf(rope, basket))
	if a <= 0.01:
		return Color(0, 0, 0, 0)
	var b: float
	if basket > 0.0:
		b = 0.32
	elif rope > env:
		b = 0.30
	else:
		var ang: float = atan2(uv.x, -(uv.y + 0.32))
		var gore: float = 1.0 if int(floor((ang + PI) / (PI / 5.0))) % 2 == 0 else 0.62
		b = gore * clampf(0.70 + 0.30 * (1.0 - absf(uv.x) / 0.62) - 0.15 * maxf(uv.y, 0.0), 0.3, 1.0)
	return Color(b, b, b, a)

## A sea turtle from above: shell, head, four flippers, a stub of tail; the
## scutes as brightness cells so the shell reads patterned under the tint.
func _fn_turtle(uv: Vector2) -> Color:
	var shell: float = _ell(uv, Vector2(0.0, 0.0), Vector2(0.55, 0.66))
	var head: float = _ell(uv, Vector2(0.0, -0.82), Vector2(0.18, 0.17))
	var fl: float = maxf(_stroke(uv, Vector2(-0.40, -0.30), Vector2(-0.92, -0.62), 0.16, 0.08),
		_stroke(uv, Vector2(0.40, -0.30), Vector2(0.92, -0.62), 0.16, 0.08))
	fl = maxf(fl, maxf(_stroke(uv, Vector2(-0.35, 0.45), Vector2(-0.72, 0.78), 0.13, 0.06),
		_stroke(uv, Vector2(0.35, 0.45), Vector2(0.72, 0.78), 0.13, 0.06)))
	var tail: float = _stroke(uv, Vector2(0.0, 0.62), Vector2(0.0, 0.92), 0.06, 0.02)
	var a: float = maxf(maxf(shell, head), maxf(fl, tail))
	if a <= 0.01:
		return Color(0, 0, 0, 0)
	var b := 0.58
	if shell > 0.5:
		var cell: float = _hash2(Vector2(floor(uv.x * 3.5 + 0.5 * floor(uv.y * 3.5)), floor(uv.y * 3.5)))
		b = 0.55 + 0.35 * cell
		var d: float = (uv / Vector2(0.55, 0.66)).length()
		b += 0.18 * smoothstep(0.78, 0.95, d)
	return Color(b, b, b, a)

## A manta from above: two long wings, a body, the whip of a tail. A shadow.
func _fn_manta(uv: Vector2) -> Color:
	var a: float = maxf(_stroke(uv, Vector2(0.0, 0.05), Vector2(-0.95, 0.15), 0.42, 0.06),
		_stroke(uv, Vector2(0.0, 0.05), Vector2(0.95, 0.15), 0.42, 0.06))
	a = maxf(a, _ell(uv, Vector2(0.0, -0.05), Vector2(0.28, 0.5)))
	a = maxf(a, _stroke(uv, Vector2(0.0, 0.40), Vector2(0.0, 0.98), 0.05, 0.015))
	if a <= 0.01:
		return Color(0, 0, 0, 0)
	return Color(0.5, 0.5, 0.5, a)

## A giraffe in PROFILE, walking right: the sloped body, the neck, the small
## head with its ossicones, four legs and a tail. Silhouette only.
func _fn_giraffe(uv: Vector2) -> Color:
	var a: float = _ell(uv, Vector2(-0.05, 0.28), Vector2(0.42, 0.22))
	a = maxf(a, _stroke(uv, Vector2(0.28, 0.20), Vector2(0.60, -0.72), 0.13, 0.08))
	a = maxf(a, _ell(uv, Vector2(0.68, -0.80), Vector2(0.17, 0.09)))
	a = maxf(a, _ell(uv, Vector2(0.82, -0.78), Vector2(0.09, 0.07)))
	a = maxf(a, _stroke(uv, Vector2(0.60, -0.86), Vector2(0.58, -0.98), 0.03, 0.02))
	a = maxf(a, _stroke(uv, Vector2(0.70, -0.88), Vector2(0.70, -0.99), 0.03, 0.02))
	a = maxf(a, _stroke(uv, Vector2(0.55, -0.84), Vector2(0.42, -0.90), 0.04, 0.02))
	for leg_v in [[0.24, 0.40, 0.30], [0.10, 0.42, 0.14], [-0.22, 0.42, -0.30], [-0.36, 0.40, -0.44]]:
		var leg: Array = leg_v
		a = maxf(a, _stroke(uv, Vector2(float(leg[0]), float(leg[1])),
			Vector2(float(leg[2]), 0.96), 0.06, 0.04))
	a = maxf(a, _stroke(uv, Vector2(-0.46, 0.20), Vector2(-0.58, 0.55), 0.03, 0.02))
	if a <= 0.01:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

## An elephant in PROFILE, walking left: the body, the domed head, the trunk in
## two sweeps, four columns of leg, a tail. Silhouette only.
func _fn_elephant(uv: Vector2) -> Color:
	var a: float = _ell(uv, Vector2(0.12, 0.0), Vector2(0.58, 0.42))
	a = maxf(a, _ell(uv, Vector2(-0.55, -0.20), Vector2(0.30, 0.30)))
	a = maxf(a, _stroke(uv, Vector2(-0.78, -0.05), Vector2(-0.92, 0.35), 0.11, 0.08))
	a = maxf(a, _stroke(uv, Vector2(-0.92, 0.35), Vector2(-0.84, 0.85), 0.08, 0.05))
	for leg_v in [[-0.30, 0.30, -0.34], [-0.08, 0.32, -0.10], [0.30, 0.32, 0.32], [0.52, 0.28, 0.56]]:
		var leg: Array = leg_v
		a = maxf(a, _stroke(uv, Vector2(float(leg[0]), float(leg[1])),
			Vector2(float(leg[2]), 0.96), 0.13, 0.11))
	a = maxf(a, _stroke(uv, Vector2(0.68, -0.05), Vector2(0.80, 0.40), 0.03, 0.02))
	if a <= 0.01:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

func _cumulus() -> ImageTexture:
	return _shaped("alt_cumulus", 96, 64, _fn_cumulus)

func _m_altitude() -> void:
	# Altitude: above the clouds. Cumulus at three depths drifting across a
	# clear sky, hot-air balloons rising through them, the sun's glare in the
	# top corner with its flare down the frame, a skein of birds now and then,
	# and below the board a sea of cloud with one peak standing through it.
	# A swipe leaves a contrail (_altitude_contrail); the giants' tier climbs
	# into the stratosphere (_journey_dress).
	var white := _white(1.0)
	var warm := Color(1.0, 0.97, 0.88)
	var sun := TextureRect.new()
	sun.texture = _round()
	sun.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sun.stretch_mode = TextureRect.STRETCH_SCALE
	sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sd: float = _vp.x * 0.9
	sun.size = Vector2(sd, sd)
	sun.position = Vector2(_vp.x * 0.86, _vp.y * 0.04) - sun.size * 0.5
	sun.modulate = Color(warm.r, warm.g, warm.b, 0.55)
	add_child(sun)
	var st := sun.create_tween().set_loops()
	st.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	st.tween_property(sun, "modulate:a", 0.68, 6.0)
	st.tween_property(sun, "modulate:a", 0.50, 6.5)
	# The flare: a few soft discs down the line from the sun.
	for k_v in [[0.72, 0.16, 0.10, 0.10], [0.60, 0.26, 0.05, 0.14], [0.46, 0.38, 0.13, 0.07]]:
		var k: Array = k_v
		var f := TextureRect.new()
		f.texture = _round()
		f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		f.stretch_mode = TextureRect.STRETCH_SCALE
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fd: float = _vp.x * float(k[2])
		f.size = Vector2(fd, fd)
		f.position = Vector2(_vp.x * float(k[0]), _vp.y * float(k[1])) - f.size * 0.5
		var fc: Color = warm if int(float(k[2]) * 100.0) % 2 == 0 else _pc("accent").lerp(white, 0.5)
		f.modulate = Color(fc.r, fc.g, fc.b, float(k[3]))
		add_child(f)
	# Cumulus: far and slow, then near and quick.
	_emit({"from": "all", "tex": _cumulus(), "color": white,
		"alpha": 0.55, "amount": 8, "lifetime": 40.0, "dir": Vector3(1, 0.02, 0),
		"spread": 4.0, "vmin": 4.0, "vmax": 9.0, "smin": 1.2, "smax": 2.4, "turb": 0.1})
	_emit({"from": "all", "tex": _cumulus(), "color": white,
		"alpha": 0.92, "amount": 5, "lifetime": 30.0, "dir": Vector3(1, 0.01, 0),
		"spread": 3.0, "vmin": 9.0, "vmax": 16.0, "smin": 2.6, "smax": 4.4, "turb": 0.05})
	_altitude_floor()
	# Balloons, each its own colour, rising through the whole frame.
	_emit({"from": "bottom", "tex": _shaped("alt_balloon", 40, 64, _fn_hot_balloon),
		"iramp": _ramp_cols([Color("E84A5F"), Color("FFB03B"), Color("2A9DF4"), Color("F6F1E9")]),
		"alpha": 0.95, "amount": 5, "lifetime": 36.0, "dir": Vector3(0.05, -1, 0),
		"spread": 10.0, "vmin": 5.0, "vmax": 11.0, "smin": 1.0, "smax": 2.0, "turb": 0.3})
	_dawn_birds(_gen)
	_altitude_flights(_gen)
	_edge_glow(warm, 0.06, 0.14, true)

## An airliner in profile: fuselage, swept wing with its engine, the fin.
func _fn_airliner(uv: Vector2) -> Color:
	var a: float = _stroke(uv, Vector2(-0.90, 0.05), Vector2(0.75, 0.0), 0.11, 0.09)
	a = maxf(a, _ell(uv, Vector2(0.80, 0.0), Vector2(0.14, 0.09)))
	if _in_tri(uv, Vector2(-0.88, 0.05), Vector2(-0.58, 0.05), Vector2(-0.92, -0.50)):
		a = 1.0
	a = maxf(a, _stroke(uv, Vector2(-0.86, 0.02), Vector2(-0.62, -0.12), 0.05, 0.02))
	a = maxf(a, _stroke(uv, Vector2(0.08, 0.06), Vector2(-0.36, 0.34), 0.09, 0.03))
	a = maxf(a, _ell(uv, Vector2(-0.06, 0.22), Vector2(0.11, 0.06)))
	if a <= 0.01:
		return Color(0, 0, 0, 0)
	var b: float = 0.92 - 0.25 * clampf(uv.y + 0.2, 0.0, 1.0)
	return Color(b, b, b, a)

## Every so often a plane crosses the sky band, its contrail growing behind it.
func _altitude_flights(gen: int) -> void:
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(14.0, 30.0)).timeout
		if gen != _gen or not is_inside_tree():
			return
		var dir: float = 1.0 if randf() < 0.5 else -1.0
		var y: float = _vp.y * randf_range(0.19, 0.29)
		var w: float = _vp.x * 0.11
		var x0: float = -w * 1.5 if dir > 0.0 else _vp.x + w * 0.5
		var x1: float = _vp.x + w * 0.5 if dir > 0.0 else -w * 1.5
		var trail := TextureRect.new()
		trail.texture = _streak()
		trail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		trail.stretch_mode = TextureRect.STRETCH_SCALE
		trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		trail.size = Vector2(w * 0.10, 1.0)
		trail.pivot_offset = Vector2(trail.size.x * 0.5, 0.0)
		trail.rotation = deg_to_rad(-90.0 * dir)
		trail.position = Vector2(x0 + w * 0.5, y + w * 0.02)
		trail.modulate = Color(1, 1, 1, 0.55)
		add_child(trail)
		var plane := TextureRect.new()
		plane.texture = _shaped("alt_airliner", 64, 28, _fn_airliner)
		plane.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		plane.stretch_mode = TextureRect.STRETCH_SCALE
		plane.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plane.size = Vector2(w, w * 0.44)
		plane.pivot_offset = plane.size * 0.5
		plane.scale = Vector2(dir, 1.0)
		plane.position = Vector2(x0, y)
		plane.modulate = Color(0.96, 0.97, 1.0, 0.92)
		add_child(plane)
		var dur := randf_range(12.0, 17.0)
		var tw := plane.create_tween()
		tw.set_parallel(true)
		tw.tween_property(plane, "position:x", x1, dur)
		tw.tween_property(trail, "scale:y", absf(x1 - x0), dur)
		await tw.finished
		if is_instance_valid(plane):
			plane.queue_free()
		if is_instance_valid(trail):
			var ft := trail.create_tween()
			ft.tween_property(trail, "modulate:a", 0.0, 6.0)
			ft.tween_callback(trail.queue_free)

## The cloud sea along the floor, and the one peak that stands through it.
func _altitude_floor() -> void:
	var white := _white(1.0)
	# The peak first, so the near clouds can bury its foot.
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = _vp
	c.draw.connect(func() -> void:
		var apex := Vector2(_vp.x * 0.74, _vp.y * 0.745)
		var bl := Vector2(_vp.x * 0.58, _vp.y * 0.88)
		var br := Vector2(_vp.x * 0.92, _vp.y * 0.88)
		var foot := Vector2(_vp.x * 0.77, _vp.y * 0.88)
		# Distance: the rock leans toward the sky it stands against.
		var slate: Color = Color(0.42, 0.48, 0.58).lerp(_pc("bg0"), 0.35)
		c.draw_colored_polygon(PackedVector2Array([apex, foot, bl]), slate.darkened(0.45))
		c.draw_colored_polygon(PackedVector2Array([apex, br, foot]), slate)
		c.draw_line(apex, foot, slate.darkened(0.6), 1.5, true)
		# The snow: the top of both faces, the lit one whiter.
		var s := 0.34
		c.draw_colored_polygon(PackedVector2Array([apex, apex.lerp(foot, s), apex.lerp(bl, s)]),
			Color(0.88, 0.92, 0.97))
		c.draw_colored_polygon(PackedVector2Array([apex, apex.lerp(br, s), apex.lerp(foot, s)]),
			Color(1.0, 1.0, 1.0)))
	add_child(c)
	c.queue_redraw()
	# The sea: big tops overlapping along the floor, the nearest brightest.
	for e_v in [[-0.02, 0.86, 0.46, 0.80], [0.30, 0.84, 0.42, 0.85], [0.62, 0.87, 0.50, 0.9],
			[0.95, 0.85, 0.44, 0.85], [0.16, 0.90, 0.56, 1.0], [0.50, 0.91, 0.60, 1.0],
			[0.84, 0.90, 0.54, 1.0]]:
		var e: Array = e_v
		var cl := TextureRect.new()
		cl.texture = _cumulus()
		cl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cl.stretch_mode = TextureRect.STRETCH_SCALE
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * float(e[2])
		cl.size = Vector2(w, w * 0.66)
		cl.position = Vector2(_vp.x * float(e[0]), _vp.y * float(e[1])) - cl.size * 0.5
		cl.modulate = Color(white.r, white.g, white.b, float(e[3]))
		add_child(cl)
		var home: float = cl.position.x
		var tw := cl.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(cl, "position:x", home + _vp.x * 0.03, randf_range(9.0, 14.0))
		tw.tween_property(cl, "position:x", home - _vp.x * 0.03, randf_range(9.0, 14.0))

## The swipe: a contrail crosses the sky the way the board moved. Horizontal
## moves only; a plane does not fly up the screen.
func _altitude_contrail(dir: Vector2) -> void:
	if absf(dir.x) < 0.5 or SettingsManager.reduce_motion():
		return
	var s := TextureRect.new()
	s.texture = _streak()
	s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	s.stretch_mode = TextureRect.STRETCH_SCALE
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.size = Vector2(5.0, _vp.x * 0.55)
	s.pivot_offset = s.size * 0.5
	s.rotation = deg_to_rad(90.0 if dir.x > 0.0 else -90.0) + deg_to_rad(randf_range(-6.0, 6.0))
	var y: float = _vp.y * randf_range(0.20, 0.30)
	s.position = Vector2(-_vp.x * 0.3 if dir.x > 0.0 else _vp.x * 1.3, y) - s.size * 0.5
	s.modulate = Color(1, 1, 1, 0.0)
	add_child(s)
	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "position:x", (_vp.x * 1.3 if dir.x > 0.0 else -_vp.x * 0.3) - s.size.x * 0.5, 1.6) \
		.set_trans(Tween.TRANS_SINE)
	tw.tween_property(s, "modulate:a", 0.55, 0.3)
	tw.chain().tween_property(s, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(s.queue_free)

## The giants' tier: the stratosphere. The sky goes indigo and stars come out.
func _altitude_stratosphere() -> void:
	var veil := TextureRect.new()
	veil.texture = _sky_ramp([Color(0.04, 0.05, 0.20, 0.72), Color(0.10, 0.20, 0.45, 0.30)])
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.size = _vp
	add_child(veil)
	_emit({"from": "all", "tex": _dot(), "color": _white(1.0),
		"alpha": 0.8, "amount": 46, "lifetime": 6.0, "dir": Vector3(0, 0, 0),
		"spread": 180.0, "vmin": 0.0, "vmax": 1.0, "smin": 0.18, "smax": 0.45, "twinkle": true})

func _m_lagoon() -> void:
	# Lagoon: shallow tropical water in daylight. Caustics webbing over the sand
	# (shader), the sand itself rippled along the floor, the shadows of palm
	# fronds swaying across the top of the frame, a turtle crossing with its own
	# shadow on the sand under it, small fish darting, the odd bubble and the
	# sun's sparkle on the surface. The giants' tier sends a manta's shadow
	# across (_journey_dress).
	var teal: Color = _pc("accent")
	_caustics(Color(1.0, 0.98, 0.85))
	_caustics_mat.set_shader_parameter("intensity", 0.40)   # noon, not the reef's dusk
	_lagoon_floor()
	_lagoon_fronds()
	_lagoon_life(_gen)
	_emit({"from": "bottom", "tex": _bubble(), "color": _white(1.0),
		"alpha": 0.5, "amount": 8, "lifetime": 9.0, "dir": Vector3(0, -1, 0),
		"spread": 12.0, "vmin": 10.0, "vmax": 22.0, "smin": 0.3, "smax": 0.7, "turb": 0.6})
	_emit({"from": "all", "tex": _sparkle(), "color": _white(1.0),
		"alpha": 0.7, "amount": 12, "lifetime": 4.0, "dir": Vector3(0, -1, 0),
		"spread": 180.0, "vmin": 0.0, "vmax": 2.0, "smin": 0.3, "smax": 0.7, "twinkle": true})
	_edge_glow(teal, 0.05, 0.12, false)

## The sand: a warm wash pooled low, with the ripples the surge leaves in it.
func _lagoon_floor() -> void:
	var sand := TextureRect.new()
	sand.texture = _round()
	sand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sand.stretch_mode = TextureRect.STRETCH_SCALE
	sand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sand.size = Vector2(_vp.x * 2.0, _vp.y * 0.34)
	sand.position = Vector2((_vp.x - sand.size.x) * 0.5, _vp.y * 0.90 - sand.size.y * 0.5)
	var sc := Color("F2C078")
	sand.modulate = Color(sc.r, sc.g, sc.b, 0.42)
	add_child(sand)
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = _vp
	c.draw.connect(func() -> void:
		var pale := Color(1.0, 0.98, 0.92, 0.55)
		for i in 7:
			var y: float = _vp.y * (0.775 + 0.021 * float(i))
			var pts := PackedVector2Array()
			var x := -10.0
			while x < _vp.x + 10.0:
				pts.append(Vector2(x, y + sin(x * 0.045 + float(i) * 1.7) * 3.0
					+ sin(x * 0.011 + float(i)) * 2.0))
				x += 8.0
			c.draw_polyline(pts, pale, 1.5, true))
	add_child(c)
	c.queue_redraw()

## Palm fronds over the frame's top corners, as SHADOWS on the water, each on
## its own slow sway.
func _lagoon_fronds() -> void:
	var shade: Color = _pc("accent").darkened(0.60)
	var col := Color(shade.r, shade.g, shade.b, 0.28)
	# [base x, base y, angle deg, length frac of the height, droop]
	for e_v in [[-0.02, -0.02, 38.0, 0.50, 0.22], [0.10, -0.05, 64.0, 0.40, 0.18],
			[1.03, -0.03, 128.0, 0.46, -0.22], [0.92, -0.06, 106.0, 0.34, -0.16]]:
		var e: Array = e_v
		var base := Vector2(_vp.x * float(e[0]), _vp.y * float(e[1]))
		var ang: float = deg_to_rad(float(e[2]))
		# The sway rotates a bare PIVOT and the frond is drawn on a child of it:
		# Control.set_rotation queues a redraw of the node it is called on, so
		# swaying the drawing itself rebuilt ~20 tapered polygons per frond
		# every frame (measured: Lagoon idled at 5 ms/frame against 1 ms for
		# every other world). A child is not invalidated by its parent moving.
		var pivot := Control.new()
		pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pivot.size = _vp
		pivot.pivot_offset = base
		add_child(pivot)
		var c := Control.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.size = _vp
		c.draw.connect(func() -> void:
			_draw_frond(c, base, Vector2(cos(ang), sin(ang)), _vp.y * float(e[3]),
				_vp.x * 0.022, col, 9, float(e[4])))
		pivot.add_child(c)
		c.queue_redraw()
		var tw := pivot.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(pivot, "rotation", 0.035, randf_range(4.5, 7.0))
		tw.tween_property(pivot, "rotation", -0.035, randf_range(4.5, 7.0))

## The turtle crossing the sand with its shadow under it, and fish darting.
func _lagoon_life(gen: int) -> void:
	var tex := _shaped("lagoon_turtle", 64, 64, _fn_turtle)
	var w: float = _vp.x * 0.15
	var shadow := TextureRect.new()
	shadow.texture = tex
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.stretch_mode = TextureRect.STRETCH_SCALE
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.size = Vector2(w, w)
	shadow.pivot_offset = shadow.size * 0.5
	shadow.modulate = Color(0.0, 0.15, 0.18, 0.22)
	add_child(shadow)
	var turtle := TextureRect.new()
	turtle.texture = tex
	turtle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	turtle.stretch_mode = TextureRect.STRETCH_SCALE
	turtle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turtle.size = Vector2(w, w)
	turtle.pivot_offset = turtle.size * 0.5
	turtle.modulate = Color(0.18, 0.32, 0.22, 0.95)
	add_child(turtle)
	for i in 3:
		var fish := TextureRect.new()
		fish.texture = _shaped("reef_fish_r", 80, 46, _fn_fish)
		fish.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fish.stretch_mode = TextureRect.STRETCH_SCALE
		fish.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fw: float = _vp.x * randf_range(0.05, 0.08)
		fish.size = Vector2(fw, fw * 0.58)
		fish.pivot_offset = fish.size * 0.5
		var fc: Color = _pc("accent").darkened(0.35)
		fish.modulate = Color(fc.r, fc.g, fc.b, 0.75)
		add_child(fish)
		_lagoon_fish(fish, gen)
	_lagoon_turtle(turtle, shadow, gen)

func _lagoon_turtle(turtle: TextureRect, shadow: TextureRect, gen: int) -> void:
	while is_inside_tree() and gen == _gen and is_instance_valid(turtle):
		var dir: float = 1.0 if randf() < 0.5 else -1.0
		var y: float = _vp.y * randf_range(0.77, 0.85)
		var x0: float = -turtle.size.x * 1.2 if dir > 0.0 else _vp.x + turtle.size.x * 0.2
		var x1: float = _vp.x + turtle.size.x * 0.2 if dir > 0.0 else -turtle.size.x * 1.2
		turtle.position = Vector2(x0, y)
		turtle.rotation = deg_to_rad(90.0 * dir)
		shadow.rotation = turtle.rotation
		var dur := randf_range(48.0, 70.0)
		var tw := turtle.create_tween()
		tw.set_parallel(true)
		tw.tween_property(turtle, "position:x", x1, dur)
		# The shadow lies on the sand a little behind and below the swimmer.
		tw.tween_method(func(_v: float) -> void:
			if is_instance_valid(shadow):
				shadow.position = turtle.position + Vector2(_vp.x * 0.02, _vp.y * 0.014), 0.0, 1.0, dur)
		var bob := turtle.create_tween().set_loops()
		bob.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		bob.tween_property(turtle, "rotation", turtle.rotation + 0.06, 2.4)
		bob.tween_property(turtle, "rotation", turtle.rotation - 0.06, 2.4)
		await tw.finished
		if is_instance_valid(bob):
			bob.kill()
		if gen != _gen or not is_inside_tree():
			return
		await get_tree().create_timer(randf_range(4.0, 12.0)).timeout

func _lagoon_fish(fish: TextureRect, gen: int) -> void:
	while is_inside_tree() and gen == _gen and is_instance_valid(fish):
		var dir: float = 1.0 if randf() < 0.5 else -1.0
		var y: float = _vp.y * randf_range(0.77, 0.87)
		var span: float = _vp.x * randf_range(0.25, 0.6)
		var x0: float = _vp.x * randf_range(0.0, 0.7)
		fish.position = Vector2(x0, y)
		fish.scale = Vector2(dir, 1.0)
		fish.modulate.a = 0.0
		var tw := fish.create_tween()
		tw.set_parallel(true)
		tw.tween_property(fish, "position:x", x0 + span * dir, randf_range(5.0, 9.0)) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(fish, "position:y", y + _vp.y * randf_range(-0.03, 0.03), randf_range(5.0, 9.0))
		tw.tween_property(fish, "modulate:a", 0.75, 1.0)
		tw.chain().tween_property(fish, "modulate:a", 0.0, 1.2)
		await tw.finished
		if gen != _gen or not is_inside_tree():
			return
		await get_tree().create_timer(randf_range(2.0, 7.0)).timeout

## The giants' tier: a manta's shadow crosses the sand every so often.
func _lagoon_manta(gen: int) -> void:
	while is_inside_tree() and gen == _gen:
		var m := TextureRect.new()
		m.texture = _shaped("lagoon_manta", 80, 48, _fn_manta)
		m.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		m.stretch_mode = TextureRect.STRETCH_SCALE
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * 0.55
		m.size = Vector2(w, w * 0.6)
		m.pivot_offset = m.size * 0.5
		var dir: float = 1.0 if randf() < 0.5 else -1.0
		m.rotation = deg_to_rad(90.0 * dir)
		m.position = Vector2(-w * 1.2 if dir > 0.0 else _vp.x + w * 0.2, _vp.y * randf_range(0.74, 0.84))
		m.modulate = Color(0.0, 0.12, 0.16, 0.30)
		add_child(m)
		var tw := m.create_tween()
		tw.tween_property(m, "position:x", _vp.x + w * 0.2 if dir > 0.0 else -w * 1.2, randf_range(16.0, 24.0))
		await tw.finished
		if is_instance_valid(m):
			m.queue_free()
		if gen != _gen or not is_inside_tree():
			return
		await get_tree().create_timer(randf_range(14.0, 26.0)).timeout

func _m_savanna() -> void:
	# Savanna: the sun going down over the plain. A painted sky, plum at the
	# zenith through amber to the orange at the horizon; the sun low and huge
	# with the heat shimmering across it; dust on the air; acacias flat-topped
	# against the light and a herd crossing in profile below the board; a skein
	# of birds high up. A merge puts a flock up out of the grass (_savanna_flock);
	# the goal brings dusk and the giants bring the Milky Way (_journey_dress).
	var sky := TextureRect.new()
	sky.texture = _sky_ramp([Color("2B1636"), Color("6E2F52"), Color("C4506A"), Color("FF8A3A"), Color("FFC46B")])
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.size = Vector2(_vp.x, _vp.y * 0.86)
	add_child(sky)
	var sunc := Vector2(_vp.x * 0.60, _vp.y * 0.245)
	var halo := TextureRect.new()
	halo.texture = _round()
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_SCALE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hd: float = _vp.x * 1.1
	halo.size = Vector2(hd, hd)
	halo.position = sunc - halo.size * 0.5
	halo.modulate = Color(1.0, 0.72, 0.30, 0.30)
	add_child(halo)
	var ht := halo.create_tween().set_loops()
	ht.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	ht.tween_property(halo, "modulate:a", 0.40, 5.0)
	ht.tween_property(halo, "modulate:a", 0.28, 5.5)
	var sun := TextureRect.new()
	sun.texture = _disc()
	sun.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sun.stretch_mode = TextureRect.STRETCH_SCALE
	sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d: float = _vp.x * 0.34
	sun.size = Vector2(d, d)
	sun.position = sunc - sun.size * 0.5
	sun.modulate = Color(1.0, 0.80, 0.40)
	add_child(sun)
	# The heat: bands of hotter air lying across the sun, drifting.
	for i in 3:
		var band := ColorRect.new()
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.size = Vector2(d * 0.92, 3.0)
		band.position = Vector2(sunc.x - band.size.x * 0.5, sunc.y - d * 0.30 + d * 0.22 * float(i))
		band.color = Color(1.0, 0.42, 0.16, 0.30)
		add_child(band)
		var home: float = band.position.y
		var bt := band.create_tween().set_loops()
		bt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		bt.tween_property(band, "position:y", home + 6.0, randf_range(2.5, 4.0))
		bt.tween_property(band, "position:y", home - 6.0, randf_range(2.5, 4.0))
	# Dust on the air, low over the plain.
	var dust := _emit({"from": "all", "tex": _round(), "color": Color("E8B07A"),
		"alpha": 0.10, "amount": 10, "lifetime": 18.0, "dir": Vector3(1, 0, 0),
		"spread": 10.0, "vmin": 6.0, "vmax": 14.0, "smin": 1.4, "smax": 2.6, "turb": 0.4})
	dust.position = Vector2(_vp.x * 0.5, _vp.y * 0.80)
	dust.emission_rect_extents = Vector2(_vp.x * 0.6, _vp.y * 0.06)
	_savanna_ground()
	_savanna_herd(_gen)
	_dawn_birds(_gen)
	_edge_glow(Color("FF8A3A"), 0.06, 0.16, false)

## The plain: the horizon's haze, the dark ground, the grass, and the acacias.
func _savanna_ground() -> void:
	var haze := TextureRect.new()
	haze.texture = _round()
	haze.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	haze.stretch_mode = TextureRect.STRETCH_SCALE
	haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	haze.size = Vector2(_vp.x * 2.0, _vp.y * 0.22)
	haze.position = Vector2((_vp.x - haze.size.x) * 0.5, _vp.y * 0.85 - haze.size.y * 0.5)
	haze.modulate = Color(1.0, 0.55, 0.25, 0.30)
	add_child(haze)
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = _vp
	c.draw.connect(_draw_savanna_ground.bind(c))
	add_child(c)
	c.queue_redraw()

func _draw_savanna_ground(c: Control) -> void:
	var ground_y: float = _vp.y * 0.858
	var earth := Color("1A0C08")
	var ink := Color("120806")
	c.draw_rect(Rect2(0.0, ground_y, _vp.x, _vp.y - ground_y), earth)
	# The far tree, in the haze.
	_draw_acacia(c, Vector2(_vp.x * 0.80, ground_y + 2.0), _vp.y * 0.06, _vp.x * 0.20,
		ink.lerp(Color("FF8A3A"), 0.35))
	# The grass: tufts along the whole horizon, a few taller.
	for i in 70:
		var x: float = _vp.x * (float(i) + randf()) / 70.0
		var h: float = randf_range(4.0, 12.0) * (2.2 if randf() < 0.12 else 1.0)
		var lean: float = randf_range(-3.0, 3.0)
		c.draw_colored_polygon(PackedVector2Array([Vector2(x - 1.5, ground_y + 1.0),
			Vector2(x + 1.5, ground_y + 1.0), Vector2(x + lean, ground_y - h)]), ink)
	# The near tree.
	_draw_acacia(c, Vector2(_vp.x * 0.20, ground_y + 2.0), _vp.y * 0.10, _vp.x * 0.34, ink)

## An acacia: a trunk, branches fanning up, and the flat umbrella of the crown.
func _draw_acacia(c: Control, base: Vector2, h: float, w: float, col: Color) -> void:
	var top := base - Vector2(0.0, h)
	var fork: Vector2 = base - Vector2(0.0, h * 0.55)
	c.draw_colored_polygon(_taper_poly(_bez_px(base, base - Vector2(w * 0.02, h * 0.3),
		fork + Vector2(w * 0.02, h * 0.1), fork, 8), w * 0.05, w * 0.035), col)
	for k_v in [[-0.34, 0.92], [-0.12, 1.0], [0.14, 0.98], [0.36, 0.90]]:
		var k: Array = k_v
		var tip: Vector2 = Vector2(base.x + w * float(k[0]), top.y + h * (1.0 - float(k[1])) * 0.9)
		var mid: Vector2 = fork.lerp(tip, 0.5) + Vector2(0.0, h * 0.06)
		c.draw_colored_polygon(_taper_poly(_bez_px(fork, mid, mid, tip, 8), w * 0.03, w * 0.008), col)
	# The crown: three flattened masses side by side, the middle highest, with a
	# ragged underside.
	for m_v in [[-0.22, 0.10, 0.30, 0.10], [0.0, 0.0, 0.34, 0.12], [0.24, 0.12, 0.28, 0.09]]:
		var m: Array = m_v
		var cx: float = base.x + w * float(m[0])
		var cy: float = top.y + h * float(m[1])
		var rx: float = w * float(m[2])
		var ry: float = h * float(m[3])
		var pts := PackedVector2Array()
		for i in 28:
			var t: float = TAU * float(i) / 28.0
			var r: float = 1.0
			if sin(t) > 0.0:
				r = 0.84 + 0.16 * _hash2(Vector2(float(i), cx))
			pts.append(Vector2(cx + cos(t) * rx * r, cy + sin(t) * ry * r * (1.6 if sin(t) > 0.0 else 1.0)))
		c.draw_colored_polygon(pts, col)

## The herd: two giraffes and an elephant crossing the plain in profile, each
## on its own pace, respawning from the far side when it has gone.
func _savanna_herd(gen: int) -> void:
	var gtex := _shaped("savanna_giraffe", 64, 88, _fn_giraffe)
	var etex := _shaped("savanna_elephant", 88, 64, _fn_elephant)
	var ink := Color("12080A")
	# [texture, height frac, x offset in the line, aspect]
	for e_v in [[gtex, 0.088, 0.0, 64.0 / 88.0], [gtex, 0.058, 0.16, 64.0 / 88.0],
			[etex, 0.062, 0.34, 88.0 / 64.0]]:
		var e: Array = e_v
		var a := TextureRect.new()
		a.texture = e[0]
		a.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		a.stretch_mode = TextureRect.STRETCH_SCALE
		a.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h: float = _vp.y * float(e[1])
		a.size = Vector2(h * float(e[3]), h)
		a.pivot_offset = Vector2(a.size.x * 0.5, a.size.y)
		a.modulate = Color(ink.r, ink.g, ink.b, 0.96)
		add_child(a)
		_savanna_walk(a, gen, float(e[2]))

func _savanna_walk(a: TextureRect, gen: int, lead: float) -> void:
	var first := true
	while is_inside_tree() and gen == _gen and is_instance_valid(a):
		var ground: float = _vp.y * 0.862
		var x0: float = _vp.x * (0.15 + lead) if first else -a.size.x * (1.2 + lead * 3.0)
		first = false
		a.position = Vector2(x0, ground - a.size.y)
		# The elephant bakes facing left; it walks with the herd, so it flips.
		a.scale = Vector2(-1.0 if a.size.x > a.size.y else 1.0, 1.0)
		var dur: float = (_vp.x * 1.4 - x0) / (_vp.x * randf_range(0.012, 0.018))
		var tw := a.create_tween()
		tw.tween_property(a, "position:x", _vp.x * 1.2, dur)
		var bob := a.create_tween().set_loops()
		bob.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		bob.tween_property(a, "position:y", ground - a.size.y - 2.0, 0.9)
		bob.tween_property(a, "position:y", ground - a.size.y, 0.9)
		await tw.finished
		if is_instance_valid(bob):
			bob.kill()
		if gen != _gen or not is_inside_tree():
			return
		await get_tree().create_timer(randf_range(6.0, 16.0)).timeout

## The merge: a few birds go up out of the grass under it and away.
func _savanna_flock(at: Vector2) -> void:
	var n := maxi(int(5.0 * _particle_scale()), 3)
	var side: float = 1.0 if randf() < 0.5 else -1.0
	for i in n:
		var b := TextureRect.new()
		b.texture = _shaped("dawn_bird", 40, 26, _fn_dawn_bird)
		b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		b.stretch_mode = TextureRect.STRETCH_SCALE
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.03, 0.05)
		b.size = Vector2(w, w * 0.65)
		b.pivot_offset = b.size * 0.5
		b.scale = Vector2(side, 1.0)
		b.position = at + Vector2(randf_range(-w, w), randf_range(-w * 0.5, w * 0.5)) - b.size * 0.5
		b.modulate = Color(0.07, 0.03, 0.04, 0.0)
		add_child(b)
		var tw := b.create_tween()
		tw.set_parallel(true)
		tw.tween_property(b, "modulate:a", 0.9, 0.12)
		tw.tween_property(b, "position", b.position + Vector2(side * _vp.x * randf_range(0.25, 0.45),
			-_vp.y * randf_range(0.10, 0.20)), randf_range(1.6, 2.4)) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		tw.chain().tween_property(b, "modulate:a", 0.0, 0.6)
		tw.chain().tween_callback(b.queue_free)

func _m_redwood() -> void:
	# Redwood: old growth. Trunks standing up through the frame's edges with
	# their bark fissured and one side lit, the canopy closing over the top,
	# god rays coming down through it, mist lying along the floor, ferns in it,
	# and pollen turning in the light. A merge lifts a shaft of light at the
	# tile (_redwood_light); the goal brings the mist in and the giants bring
	# the sun through (_journey_dress).
	var fog: Color = _pc("bg0").lerp(_white(1.0), 0.35)
	var gold: Color = _pc("accent")
	var mass := _shaped("bg_leafmass", 72, 54, _fn_leaf_mass)
	for e_v in [[0.05, -0.02, 0.50], [0.40, -0.06, 0.42], [0.80, -0.03, 0.55]]:
		var e: Array = e_v
		var m := TextureRect.new()
		m.texture = mass
		m.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		m.stretch_mode = TextureRect.STRETCH_SCALE
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * float(e[2])
		m.size = Vector2(w, w * 0.75)
		m.position = Vector2(_vp.x * float(e[0]), _vp.y * float(e[1])) - m.size * 0.5
		m.modulate = Color(0.04, 0.08, 0.05, 0.92)
		add_child(m)
	_god_rays(gold, 0.05, 0.14)
	_redwood_trunks()
	var mist := _emit({"from": "all", "tex": _round(), "color": fog,
		"alpha": 0.07, "amount": 8, "lifetime": 20.0, "dir": Vector3(1, 0, 0),
		"spread": 8.0, "vmin": 4.0, "vmax": 10.0, "smin": 1.8, "smax": 3.2, "turb": 0.5})
	mist.position = Vector2(_vp.x * 0.5, _vp.y * 0.84)
	mist.emission_rect_extents = Vector2(_vp.x * 0.7, _vp.y * 0.08)
	_emit({"from": "all", "tex": _dot(), "color": gold.lerp(_white(1.0), 0.3),
		"alpha": 0.55, "amount": 40, "lifetime": 12.0, "dir": Vector3(0.2, -1, 0),
		"spread": 180.0, "vmin": 2.0, "vmax": 7.0, "smin": 0.16, "smax": 0.45,
		"twinkle": true, "turb": 0.6})
	_emit({"from": "all", "tex": _round(), "color": gold,
		"alpha": 0.10, "amount": 10, "lifetime": 16.0, "dir": Vector3(0.1, -1, 0),
		"spread": 180.0, "vmin": 2.0, "vmax": 6.0, "smin": 0.6, "smax": 1.4, "turb": 0.4})
	_redwood_deer(_gen)
	_redwood_ferns()
	_edge_glow(gold, 0.05, 0.12, true)

## The trunks: two far ones in the haze, two near ones hard against the edges,
## each a buttressed column with a lit side and dark fissures down the bark.
func _redwood_trunks() -> void:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = _vp
	c.draw.connect(_draw_redwood_trunks.bind(c))
	add_child(c)
	c.queue_redraw()

func _draw_redwood_trunks(c: Control) -> void:
	var bark := Color("3A1A12")
	var lit := Color("8A3F2E")
	var dark := Color("1E0C08")
	var fog: Color = _pc("bg0").lerp(_white(1.0), 0.30)
	# [x, base width frac, top width frac, haze]
	for e_v in [[0.30, 0.060, 0.045, 0.55], [0.66, 0.045, 0.035, 0.62],
			[0.05, 0.13, 0.09, 0.0], [0.95, 0.09, 0.065, 0.0]]:
		var e: Array = e_v
		var x: float = _vp.x * float(e[0])
		var w0: float = _vp.x * float(e[1])
		var w1: float = _vp.x * float(e[2])
		var hz: float = float(e[3])
		var body: Color = bark.lerp(fog, hz)
		var poly := PackedVector2Array([
			Vector2(x - w0 * 0.70, _vp.y * 1.02), Vector2(x - w0 * 0.5, _vp.y * 0.90),
			Vector2(x - w1 * 0.5, -_vp.y * 0.02), Vector2(x + w1 * 0.5, -_vp.y * 0.02),
			Vector2(x + w0 * 0.5, _vp.y * 0.90), Vector2(x + w0 * 0.70, _vp.y * 1.02)])
		c.draw_colored_polygon(poly, body)
		# The lit side, a strip down the left third.
		var l: Color = lit.lerp(fog, hz)
		c.draw_colored_polygon(PackedVector2Array([
			Vector2(x - w0 * 0.5, _vp.y * 0.90), Vector2(x - w1 * 0.5, -_vp.y * 0.02),
			Vector2(x - w1 * 0.18, -_vp.y * 0.02), Vector2(x - w0 * 0.14, _vp.y * 0.90)]),
			Color(l.r, l.g, l.b, 0.55))
		# Fissures: dark seams wandering down the bark.
		if hz > 0.3:
			continue
		for k in 6:
			var fx: float = x + w0 * randf_range(-0.42, 0.42)
			var a := Vector2(fx, _vp.y * randf_range(-0.02, 0.3))
			var b := Vector2(fx + randf_range(-w0 * 0.1, w0 * 0.1), _vp.y * randf_range(0.6, 1.02))
			var m1 := a.lerp(b, 0.35) + Vector2(randf_range(-w0 * 0.08, w0 * 0.08), 0.0)
			var m2 := a.lerp(b, 0.7) + Vector2(randf_range(-w0 * 0.08, w0 * 0.08), 0.0)
			c.draw_colored_polygon(_taper_poly(_bez_px(a, m1, m2, b, 10), w0 * 0.05, w0 * 0.02),
				Color(dark.r, dark.g, dark.b, 0.7))

## A buck in PROFILE, walking right: the body, the neck up to a small head
## with ears and a rack of antlers, four legs, the flag of a tail.
func _fn_deer(uv: Vector2) -> Color:
	var a: float = _ell(uv, Vector2(0.0, 0.15), Vector2(0.42, 0.22))
	a = maxf(a, _stroke(uv, Vector2(0.30, 0.02), Vector2(0.55, -0.45), 0.11, 0.08))
	a = maxf(a, _ell(uv, Vector2(0.62, -0.55), Vector2(0.16, 0.10)))
	a = maxf(a, _ell(uv, Vector2(0.76, -0.52), Vector2(0.08, 0.06)))
	a = maxf(a, _stroke(uv, Vector2(0.58, -0.62), Vector2(0.50, -0.80), 0.04, 0.02))
	a = maxf(a, _stroke(uv, Vector2(0.66, -0.64), Vector2(0.70, -0.82), 0.04, 0.02))
	for t_v in [[0.60, -0.66, 0.45, -0.98], [0.52, -0.84, 0.40, -0.95],
			[0.64, -0.66, 0.72, -0.98], [0.68, -0.84, 0.80, -0.94]]:
		var t: Array = t_v
		a = maxf(a, _stroke(uv, Vector2(float(t[0]), float(t[1])),
			Vector2(float(t[2]), float(t[3])), 0.03, 0.012))
	for leg_v in [[0.25, 0.30, 0.30], [0.15, 0.32, 0.12], [-0.20, 0.32, -0.28], [-0.32, 0.30, -0.40]]:
		var leg: Array = leg_v
		a = maxf(a, _stroke(uv, Vector2(float(leg[0]), float(leg[1])),
			Vector2(float(leg[2]), 0.96), 0.05, 0.03))
	a = maxf(a, _stroke(uv, Vector2(-0.42, 0.05), Vector2(-0.50, 0.25), 0.04, 0.02))
	if a <= 0.01:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

## Every so often a buck crosses the floor behind the ferns, stops to graze,
## and goes on.
func _redwood_deer(gen: int) -> void:
	var deer := TextureRect.new()
	deer.texture = _shaped("redwood_deer", 64, 88, _fn_deer)
	deer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	deer.stretch_mode = TextureRect.STRETCH_SCALE
	deer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h: float = _vp.y * 0.09
	deer.size = Vector2(h * 64.0 / 88.0, h)
	deer.pivot_offset = Vector2(deer.size.x * 0.5, deer.size.y)
	deer.modulate = Color(0.10, 0.06, 0.04, 0.0)
	add_child(deer)
	_redwood_deer_walk(deer, gen)

func _redwood_deer_walk(deer: TextureRect, gen: int) -> void:
	while is_inside_tree() and gen == _gen and is_instance_valid(deer):
		await get_tree().create_timer(randf_range(8.0, 22.0)).timeout
		if gen != _gen or not is_inside_tree() or not is_instance_valid(deer):
			return
		var dir: float = 1.0 if randf() < 0.5 else -1.0
		var ground: float = _vp.y * 0.888
		var x0: float = -deer.size.x * 1.2 if dir > 0.0 else _vp.x + deer.size.x * 0.2
		var xm: float = _vp.x * randf_range(0.3, 0.7)
		var x1: float = _vp.x + deer.size.x * 0.2 if dir > 0.0 else -deer.size.x * 1.2
		deer.scale = Vector2(dir, 1.0)
		deer.position = Vector2(x0, ground - deer.size.y)
		deer.modulate.a = 0.0
		var tw := deer.create_tween()
		tw.tween_property(deer, "modulate:a", 0.92, 1.5)
		tw.parallel().tween_property(deer, "position:x", xm, randf_range(14.0, 20.0))
		tw.tween_interval(randf_range(3.0, 6.0))
		tw.tween_property(deer, "position:x", x1, randf_range(14.0, 20.0))
		tw.parallel().tween_property(deer, "modulate:a", 0.0, 3.0).set_delay(11.0)
		var bob := deer.create_tween().set_loops()
		bob.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		bob.tween_property(deer, "position:y", ground - deer.size.y - 1.5, 0.7)
		bob.tween_property(deer, "position:y", ground - deer.size.y, 0.7)
		await tw.finished
		if is_instance_valid(bob):
			bob.kill()
		if gen != _gen or not is_inside_tree():
			return

## Ferns along the floor, in the mist: fronds fanning up from a crown.
func _redwood_ferns() -> void:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = _vp
	var fern := Color("3F7A46")
	var fog: Color = _pc("bg0").lerp(_white(1.0), 0.30)
	c.draw.connect(func() -> void:
		# [x, y, length frac of the height, haze]
		for e_v in [[0.12, 0.885, 0.10, 0.0], [0.30, 0.895, 0.075, 0.25], [0.55, 0.89, 0.085, 0.15],
				[0.76, 0.90, 0.07, 0.3], [0.92, 0.885, 0.095, 0.0]]:
			var e: Array = e_v
			var base := Vector2(_vp.x * float(e[0]), _vp.y * float(e[1]))
			var col: Color = fern.lerp(fog, float(e[3]))
			for ang_v in [-118.0, -95.0, -70.0, -50.0]:
				var ang: float = deg_to_rad(float(ang_v) + randf_range(-6.0, 6.0))
				_draw_frond(c, base, Vector2(cos(ang), sin(ang)), _vp.y * float(e[2]) * randf_range(0.8, 1.0),
					_vp.x * 0.012, Color(col.r, col.g, col.b, 0.92), 7, 0.25 * signf(cos(ang))))
	add_child(c)
	c.queue_redraw()

## The merge: a shaft of light stands up at the tile for a moment.
func _redwood_light(at: Vector2, strength: float) -> void:
	var ray := TextureRect.new()
	ray.texture = _round()
	ray.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ray.stretch_mode = TextureRect.STRETCH_SCALE
	ray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w: float = _vp.x * 0.16
	var h: float = _vp.y * 1.4
	ray.size = Vector2(w, h)
	ray.pivot_offset = Vector2(w * 0.5, 0.0)
	ray.rotation = deg_to_rad(randf_range(-10.0, 10.0))
	ray.position = Vector2(at.x - w * 0.5, -_vp.y * 0.35)
	var gold: Color = _pc("accent")
	ray.modulate = Color(gold.r, gold.g, gold.b, 0.0)
	add_child(ray)
	var tw := ray.create_tween()
	tw.tween_property(ray, "modulate:a", clampf(0.10 + 0.08 * strength, 0.0, 0.26), 0.18)
	tw.tween_property(ray, "modulate:a", 0.0, 0.9).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(ray.queue_free)

## A wax comb cell: a hexagon with a thick lit rim around a darker well, so a
## drifting cell reads as a piece of comb with depth rather than a flat icon.
func _hexcell() -> ImageTexture:
	return _shaped("hexcell", 30, 30, _fn_hexcell)

func _fn_hexcell(uv: Vector2) -> Color:
	var hexd := 0.0
	for k in 3:
		var th := float(k) * PI / 3.0
		hexd = maxf(hexd, absf(uv.x * cos(th) + uv.y * sin(th)))
	var a := 1.0 - smoothstep(0.78, 0.92, hexd)
	if a <= 0.01:
		return Color(0, 0, 0, 0)
	# Hollow: the well is mostly open so a drifting cell never reads as a solid
	# blob, and the rim carries the light.
	var rim := smoothstep(0.46, 0.76, hexd)
	var b := 0.20 + rim * 0.80
	b += clampf((-uv.x - uv.y) * 0.14, -0.10, 0.18)
	return Color(1, 1, 1, a * clampf(b, 0.0, 1.0))

## A butterfly seen from above, wings spread, GLOWING — baked in full colour
## with its own aura, so the emitters pass white and every insect on the screen
## carries its light with it.
##
## Two things this bake does that the one before it did not. First, the pattern
## is a BLUE MORPHO, not a monarch: Butterfly Grove is a deep blue-navy theme
## with a cobalt accent, and orange was the single colour in the palette that
## could not be in it. Second, the halo is part of the SPRITE. Glow chased with
## a second particle field can never stay in step with the first — the dot and
## the butterfly drift apart within a second — so the falloff is baked around
## the wings and travels with them for free.
##
## The wings are drawn at ~0.72 of the old radii to leave the bake room for that
## halo; the sprite is emitted proportionally larger to compensate.
func _butterfly() -> ImageTexture:
	return _bfly_morpho()

## The blue morpho: cobalt at the wing root burning out to cyan at the margin,
## a near-black border, and the pale margin crescents the real animal has.
func _bfly_morpho() -> ImageTexture:
	return _shaped("bfly_morpho", 48, 44, _fn_bfly_morpho)

## The pale one — white shading to ice at the roots, and a wider, softer halo.
## Two species is the difference between a flight and a repeated sprite.
func _bfly_fairy() -> ImageTexture:
	return _shaped("bfly_fairy", 48, 44, _fn_bfly_fairy)

func _fn_bfly_morpho(uv: Vector2) -> Color:
	return _bfly_wings(uv, false)

func _fn_bfly_fairy(uv: Vector2) -> Color:
	return _bfly_wings(uv, true)

func _bfly_wings(uv: Vector2, pale: bool) -> Color:
	var ax := absf(uv.x)
	# Normalised wing radii, not coverage masks: the border, the venation and
	# the margin spots all need to know how far INTO the wing a pixel sits, and
	# a coverage mask only knows about the last few pixels at the edge.
	var fr := Vector2((ax - 0.34) / 0.37, (uv.y + 0.22) / 0.44).length()
	var hr := Vector2((ax - 0.28) / 0.31, (uv.y - 0.30) / 0.34).length()
	var rw := minf(fr, hr)                     # 0 wing centre .. 1 wing edge
	var body := Vector2(uv.x * 10.1, uv.y * 1.38).length()
	var wing: float = maxf(1.0 - smoothstep(0.97, 1.03, rw), 1.0 - smoothstep(0.90, 1.02, body))
	# The halo: a soft fall-off carried OUTSIDE the silhouette. RADIAL, from the
	# thorax — the obvious version, a fall-off on `rw`, is the min() of two
	# ellipse fields, and outside the wings that surface is a rounded RECTANGLE,
	# so every butterfly on the screen glowed as a little blue square.
	var aura: Color = Color(0.34, 0.62, 1.0) if not pale else Color(0.74, 0.90, 1.0)
	var gr: float = Vector2(uv.x * 0.80, uv.y * 0.92).length()
	var halo: float = pow(clampf(1.0 - gr, 0.0, 1.0), 1.8) * (0.34 if not pale else 0.46)
	var a: float = clampf(maxf(wing, halo), 0.0, 1.0)
	if a <= 0.015:
		return Color(0, 0, 0, 0)
	if wing <= 0.02:
		return Color(aura.r, aura.g, aura.b, a)
	var th := atan2(uv.y + 0.05, ax + 0.04)    # fan angle out of the wing root
	var field: Color = Color(0.12, 0.34, 0.94)
	var outer: Color = Color(0.40, 0.82, 1.0)
	var frame: Color = Color(0.02, 0.04, 0.14)
	var spot: Color = Color(0.86, 0.95, 1.0)
	if pale:
		field = Color(0.72, 0.90, 1.0)
		outer = Color(1.0, 1.0, 1.0)
		frame = Color(0.42, 0.66, 0.98)
		spot = Color(1.0, 1.0, 1.0)
	# Iridescence: the morpho's blue is structural, so it BRIGHTENS outward
	# rather than fading — the opposite of a pigment wing.
	var col: Color = field.lerp(outer, smoothstep(0.05, 0.80, rw))
	# Fine venation fanning from the root, gone before it reaches the margin.
	var vein: float = pow(absf(sin(th * 7.0)), 10.0) * (1.0 - smoothstep(0.70, 0.95, rw))
	col = col.lerp(frame, vein * (0.40 if not pale else 0.22))
	# The dark margin band, well INSIDE the silhouette so it actually shows.
	col = col.lerp(frame, smoothstep(0.68, 0.94, rw))
	# Pale crescents riding that band.
	if rw > 0.74 and rw < 0.93 and sin(th * 11.0) > 0.55:
		col = col.lerp(spot, 0.75)
	if body < 0.9:
		col = Color(0.06, 0.07, 0.14).lerp(Color(0.30, 0.40, 0.62), 0.45) \
			if not pale else Color(0.52, 0.64, 0.86)
	# Where the halo is stronger than the wing, it wins — that is the light
	# bleeding over the outline, which is what makes the edge glow instead of
	# ending in a hard line.
	if halo > wing:
		col = col.lerp(aura, clampf((halo - wing) * 1.4, 0.0, 1.0))
	return Color(col.r, col.g, col.b, a)

## One eye-feather of a peacock train, in COLOUR.
##
## Three passes went into the bin before this one, and each failed the same way
## — by drawing the vane as SPIKES. A comb of separate hairs down a shaft is not
## a feather; it is fletching, and every version that cut the alpha per barb
## came out looking like the flights on an arrow.
##
## What a train feather actually is:
##
##   * A long bare QUILL for most of its length. The lower half carries almost
##     no vane at all — just a scatter of loose barbs (the "herl") drifting off
##     it. Fill that half with plume and the feather reads as a leaf.
##   * A broad soft PLUME that swells to its widest a little below the eye and
##     closes above it. Its body is CONTINUOUS: the barbs there touch, hook to
##     each other and hold a surface. That surface is what carries the colour.
##   * A ragged FRINGE, and only in the outermost fifth, where the barbs finally
##     come apart into separate hairs and end at slightly different distances.
##   * The OCELLUS at the top: a kidney pupil of near-black indigo, a hard
##     cobalt iris, a copper zone that does not close all the way round, and a
##     wide gold-green field that fades into the plume with no edge at all.
##
## So the alpha here comes from a smooth envelope, and the barbs only modulate
## BRIGHTNESS inside it — the striation you can see across a real vane — until
## the outer fifth, where they take over the alpha and break the outline.
##
## The colour of the vane is BROWN. Bronze and umber, warm near the shaft,
## dusty at the ends. The gold belongs to the eye and to nothing else; a pass
## that ran green-gold through the whole vane produced feathers that looked like
## ears of wheat.
##
## The simplified twin is Confetti._fn_feather (the celebration throws the same
## feathers); keep the eye radii and the profile in step.
func _feather() -> ImageTexture:
	return _shaped("pc_eyefeather", 118, 300, _fn_eye_feather)

func _fn_eye_feather(uv: Vector2) -> Color:
	const AR := 2.54      # bake 118x300
	var sy := uv.y * AR
	var t := clampf((sy + AR) / (AR * 2.0), 0.0, 1.0)        # 0 tip, 1 base
	var a := 0.0
	var col := Color(0, 0, 0)
	# A train feather bows; everything below is measured off the bowed centre
	# line, not off x = 0.
	var cx: float = uv.x - 0.11 * sin(t * PI)
	var ax := absf(cx)
	var side: float = 1.0 if cx >= 0.0 else -1.0

	# --- The plume -------------------------------------------------------------
	# One smooth envelope: widest a little below the eye, closing above it, and
	# almost nothing at the base. A gaussian is exactly the right shape and it
	# costs one exp.
	# The proportion that makes this a TRAIN feather and not an arrowhead: the
	# ocellus is the WIDEST part of the whole feather, and the plume below it is
	# narrower and tapering. A plume as wide as its eye gives a cone with a knob
	# on the end, which is what the pass before this drew.
	var env: float = exp(-pow((sy + 0.90) / 1.60, 2.0))
	# The floor is the HERL: the loose barbs that carry on down the bare shaft
	# long after the plume proper has closed. Without it the feather ends in a
	# clean point and reads as a spoon.
	var spray: float = 0.58 * env + 0.050 + 0.06 * smoothstep(0.35, 0.95, t)
	if ax < spray * 1.20:
		var along: float = ax / maxf(spray, 0.01)
		# Barbs leave the shaft at about 25 degrees and sweep toward the tip, so
		# a point's barb index is its y plus a share of its x.
		var idx: float = (sy + ax * 0.46) * 11.0
		var barb: float = absf(fposmod(idx, 1.0) - 0.5) * 2.0   # 0 on a barb, 1 between
		# The body: continuous out to 0.66, then handed over to the fringe.
		var body: float = 1.0 - smoothstep(0.66, 1.02, along)
		# The fringe: the barbs come apart and end raggedly, each at its own
		# distance. This is the ONLY place alpha is cut per barb.
		var jag: float = 1.06 + 0.15 * sin(idx * 2.3) + 0.06 * sin(idx * 7.1)
		var fringe: float = (1.0 - smoothstep(0.34, 0.72, barb)) \
			* smoothstep(0.58, 0.70, along) * (1.0 - smoothstep(jag - 0.20, jag, along))
		var va: float = clampf(maxf(body, fringe), 0.0, 1.0)
		va *= smoothstep(0.012, 0.055, ax)                      # the shaft's own gap
		if va > a:
			a = va
			# Bronze at the shaft, warm brown through the middle, dusty umber at
			# the ends — and the barb striation as a BRIGHTNESS ripple, not a
			# hole, which is the whole difference between a vane and a comb.
			var shade: float = 0.88 + 0.20 * (1.0 - barb)
			col = Color(0.34, 0.23, 0.12).lerp(Color(0.49, 0.35, 0.18),
				smoothstep(0.0, 0.48, along))
			col = col.lerp(Color(0.27, 0.21, 0.14), smoothstep(0.58, 1.0, along) * 0.75)
			col = Color(col.r * shade, col.g * shade, col.b * shade)
			# The vane is iridescent, so one side of every barb carries a cool
			# sheen — but it only ever TINTS the brown, it never replaces it.
			col = col.lerp(Color(0.18, 0.34, 0.30),
				clampf(0.34 - side * 0.24, 0.0, 0.5) * (1.0 - along) * 0.50)
			# The plume warms toward the eye, where the gold begins — a narrow
			# band, so the brown still owns the feather.
			col = col.lerp(Color(0.52, 0.42, 0.16),
				clampf(1.0 - absf(sy + 1.20) / 0.80, 0.0, 1.0) * 0.32)

	# --- The shaft -------------------------------------------------------------
	var quill: float = 0.036 - 0.020 * (1.0 - t)
	if ax < quill and sy > -1.95:
		a = 1.0
		var q: float = clampf(1.0 - ax / maxf(quill, 0.001), 0.0, 1.0)
		col = Color(0.26, 0.18, 0.10).lerp(Color(0.50, 0.39, 0.24), q)

	# --- The ocellus -----------------------------------------------------------
	# Big, and sitting just ABOVE the widest point of the plume. Placed any
	# higher it runs off the top of the bake and all that survives is a sliver
	# of iris — which is what the previous numbers did, and it left the feather
	# looking like a leaf with a scratch on it.
	var ex: float = cx / 0.90
	var ey: float = (sy + 1.42) / 0.72
	var r: float = Vector2(ex, ey).length()
	var ang := atan2(ey, ex)
	# Its rim wobbles, because it too is made of barb ends.
	r *= 1.0 + 0.050 * sin(ang * 3.0 + 0.6) + 0.028 * sin(ang * 7.0 - 1.1) \
		+ 0.014 * sin(ang * 17.0)
	if r < 1.40:
		# The PUPIL is a KIDNEY — a disc with a smaller disc bitten out of its
		# lower edge. A round pupil is the one thing that turns a painted
		# ocellus into a dartboard.
		var pr: float = Vector2(ex / 0.40, (ey + 0.10) / 0.34).length()
		var bite: float = Vector2(ex / 0.30, (ey + 0.50) / 0.26).length()
		var pupil: float = (1.0 - smoothstep(0.88, 1.04, pr)) * smoothstep(0.82, 1.06, bite)
		# Zones, outermost first, each blending into the last with no hard edge.
		var c := Color(0.34, 0.38, 0.14)                                        # gold-green field
		c = c.lerp(Color(0.70, 0.58, 0.20), 1.0 - smoothstep(0.82, 1.24, r))    # old gold
		# The copper zone does not close: it thins at the top of the eye, which
		# is how a real ocellus is asymmetric.
		var copper: float = (1.0 - smoothstep(0.56, 0.90, r)) \
			* clampf(0.55 + 0.45 * sin(ang + 1.9), 0.0, 1.0)
		c = c.lerp(Color(0.62, 0.31, 0.09), copper)
		c = c.lerp(Color(0.06, 0.34, 0.36), 1.0 - smoothstep(0.42, 0.66, r))    # inner teal
		c = c.lerp(Color(0.08, 0.42, 0.78), 1.0 - smoothstep(0.24, 0.46, r))    # cobalt iris
		c = c.lerp(Color(0.03, 0.05, 0.14), pupil)                              # the pupil
		# The barbs run through the eye too — the colour sits ON them — so it
		# carries the same striation the plume does, packed much tighter.
		var eidx: float = (sy + ax * 0.46) * 11.0
		var eb: float = absf(fposmod(eidx, 1.0) - 0.5) * 2.0
		c = Color(c.r, c.g, c.b) * (0.82 + 0.30 * (1.0 - eb))
		# ONE hot spot, off centre. Structural colour never lights evenly.
		var spec: float = 1.0 - smoothstep(0.0, 0.80, Vector2(ex + 0.30, ey + 0.34).length())
		c = c.lerp(Color(0.80, 0.98, 0.96), spec * 0.30)
		# ...and the eye's own edge is a fade INTO the plume, not a cut — and it
		# is painted OVER it, not max()-ed against it. Every earlier pass wrote
		# the eye with `if ea > a`, and since the plume's own alpha is already
		# 1.0 everywhere the eye sits, that test could never pass: the ocellus
		# only ever appeared in the gaps between barbs, as a sliver. Which is
		# why the feather kept coming out as a leaf with a scratch on it.
		var ea: float = 1.0 - smoothstep(1.04, 1.36, r)
		if ea > 0.01:
			col = c if a <= 0.02 else col.lerp(c, ea)
			a = maxf(a, ea)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0))

## A honey bee: fuzzy amber-and-black abdomen, dark thorax and head, wings drawn
## as pale BLUR arcs — a bee in flight shows no wing shape, and a solid pair
## reads as a moth. Full colour, so the emitters pass white.
func _bee() -> ImageTexture:
	return _shaped("bee", 26, 22, _fn_bee)

func _fn_bee(uv: Vector2) -> Color:
	var half := 0.34 * sqrt(clampf(1.0 - pow((uv.x - 0.05) / 0.94, 2.0), 0.0, 1.0))
	var body := 1.0 - smoothstep(half - 0.09, half, absf(uv.y))
	var wy := absf(uv.y)
	# A hard-edged pane at half alpha reads as a grey PLATE, not a wing. Real
	# wings at wingbeat speed are a faint blur, so this fades gradually from the
	# root outward and stays well under a third alpha.
	var wing := (1.0 - smoothstep(0.30, 1.06,
		Vector2((uv.x - 0.12) / 0.66, (wy - 0.46) / 0.26).length())) * 0.32
	var a := clampf(maxf(body, wing), 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var col := Color(0.86, 0.90, 0.96)
	if body > wing:
		var stripe: float = fposmod(floorf((uv.x + 0.05) * 6.4), 2.0)
		col = Color(0.98, 0.72, 0.12) if stripe > 0.5 else Color(0.16, 0.12, 0.06)
		if uv.x < -0.44:
			col = Color(0.12, 0.10, 0.06)
		elif uv.x < -0.10:
			col = Color(0.34, 0.24, 0.10)
		col = col.lerp(Color(1, 1, 1), clampf(-uv.y * 0.30, 0.0, 0.26))
		col = col.lerp(Color(0, 0, 0), clampf(uv.y * 0.26, 0.0, 0.22))
	return Color(col.r, col.g, col.b, a)

# --- Reward motifs (reactive) ---------------------------------------------------
## The ten badge-earned themes live in RewardFx (scenes/gameplay/reward_fx.gd):
## each is a self-contained Control that paints its own signature effect AND
## responds to gameplay through the on_swipe / on_merge hooks below.
func _m_reward(motif: String) -> void:
	# Origami Sky is the one reward motif with no world of its own — the folded
	# animals were flying over an empty gradient. Its paper landscape goes down
	# FIRST so the birds pass in front of it.
	if motif == "origami":
		_origami_range()
	_reward = RewardFx.make(motif)
	if _reward != null:
		# B2: hand the host's clip window through (invalid Callable on the
		# full-screen instance = unclipped). Set BEFORE add_child so the effect's
		# _build already sees it. The effect skips per-element draws that fall
		# wholly outside the window — see reward_fx.gd Base.clip_window().
		_reward.clip_win = clip_rect
		# The palette override rides along too, so a card-backdrop capture of a
		# reward world paints in the CARD's theme, not the wearer's.
		_reward.pal_override = palette_override
		add_child(_reward)

# --- Premium ambient motifs (First Bloom / Zen Garden / Origami Sky) -----------
## First Bloom — dusk hanami: blossom petals in the theme's own pink drift down
## in two depths under a warm canopy glow, while a few pollen motes rise in the
## last light so the garden breathes both ways.
# Blossom-pad tips of the bonsai bake (texture uv space, -1..1) — where the
# clusters bloom and new buds pop open.
const _BONSAI_TIPS := [
	Vector2(0.5, -0.3), Vector2(0.3, 0.12), Vector2(0.2, 0.55),
	Vector2(-0.45, -0.55), Vector2(0.05, -0.35), Vector2(-0.2, 0.05),
]

func _m_bonsai() -> void:
	var pink := _pc("accent")
	# The tree itself: a gnarled bonsai reaching over the lower band, its pads
	# already dotted with the first blossoms — and every few seconds a new bud
	# POPS open (the theme's namesake moment).
	# Sized off the BOTTOM BAND's height (not screen width) so the whole tree —
	# pads included — stays below the board on any aspect.
	var h: float = _vp.y * 0.245
	var w: float = h
	var origin := Vector2(-_vp.x * 0.04, _vp.y * 1.01 - h)
	var branch := TextureRect.new()
	branch.texture = _shaped("bonsai_branch", 160, 160, _fn_bonsai)
	branch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	branch.stretch_mode = TextureRect.STRETCH_SCALE
	branch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	branch.size = Vector2(w, h)
	branch.position = origin
	branch.modulate = Color(0.17, 0.12, 0.10, 0.96)   # dark bark silhouette
	add_child(branch)
	var soft_pink := pink.lerp(_white(1.0), 0.35)
	for tip_v in _BONSAI_TIPS:
		var tip: Vector2 = tip_v
		for k in 4:
			_bonsai_blossom(origin + Vector2((tip.x * 0.5 + 0.5) * w, (tip.y * 0.5 + 0.5) * h)
				+ Vector2(randf_range(-34.0, 34.0), randf_range(-22.0, 14.0)), soft_pink, false)
	_bonsai_buds(_gen, origin, Vector2(w, h))
	_emit({"from": "all", "tex": _petal(), "color": pink.lightened(0.12),
		"alpha": 0.8, "amount": 34, "lifetime": 14.0, "dir": Vector3(0.12, 1, 0),
		"spread": 16.0, "vmin": 22.0, "vmax": 55.0, "smin": 0.6, "smax": 1.5,
		"spin": 1.8, "turb": 0.9})
	_emit({"from": "all", "tex": _petal(), "color": pink.lerp(_white(1.0), 0.4),
		"alpha": 0.5, "amount": 22, "lifetime": 16.0, "dir": Vector3(0.08, 1, 0),
		"spread": 20.0, "vmin": 12.0, "vmax": 30.0, "smin": 0.3, "smax": 0.8,
		"spin": 1.2, "turb": 0.7})
	_emit({"from": "bottom", "tex": _dot(), "color": _pc("gold").lightened(0.2),
		"alpha": 0.35, "amount": 14, "lifetime": 12.0, "dir": Vector3(0, -1, 0),
		"spread": 26.0, "vmin": 8.0, "vmax": 22.0, "smin": 0.5, "smax": 1.2, "turb": 1.0})
	_edge_glow(pink.lerp(_white(1.0), 0.3), 0.05, 0.10, true)
	_bloom_garden()

## One blossom on the tree: a soft pink bloom. `pop` scales it in with a springy
## open. Settled blossoms breathe faintly instead.
func _bonsai_blossom(pos: Vector2, pink: Color, pop: bool) -> TextureRect:
	var b := TextureRect.new()
	b.texture = _dot()
	b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d: float = randf_range(15.0, 26.0)
	b.size = Vector2(d, d)
	b.pivot_offset = b.size * 0.5
	b.position = pos - b.size * 0.5
	var bright := pink.lerp(_white(1.0), 0.2)
	b.modulate = Color(bright.r, bright.g, bright.b, randf_range(0.75, 0.95))
	add_child(b)
	if pop:
		b.scale = Vector2.ZERO
		var tw := b.create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(b, "scale", Vector2.ONE, 0.7)
	else:
		var base_a := b.modulate.a
		var tw := b.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(b, "modulate:a", base_a * 0.7, randf_range(2.5, 4.0))
		tw.tween_property(b, "modulate:a", base_a, randf_range(2.5, 4.0))
	return b

## The budding loop: every few seconds a new blossom pops open on a random pad
## tip. Capped — the oldest bloom fades as the newest opens, so spring never ends.
func _bonsai_buds(gen: int, origin: Vector2, dim: Vector2) -> void:
	var blooms: Array = []
	var pink: Color = _pc("accent").lerp(_white(1.0), 0.35)
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(3.0, 6.5)).timeout
		if gen != _gen or not is_inside_tree():
			return
		var tip: Vector2 = _BONSAI_TIPS[randi() % _BONSAI_TIPS.size()]
		var pos := origin + Vector2((tip.x * 0.5 + 0.5) * dim.x, (tip.y * 0.5 + 0.5) * dim.y) \
			+ Vector2(randf_range(-36.0, 36.0), randf_range(-24.0, 14.0))
		blooms.append(_bonsai_blossom(pos, pink, true))
		if blooms.size() > 24:
			var old_v = blooms.pop_front()
			var old := old_v as TextureRect
			if old != null and is_instance_valid(old):
				var ft := old.create_tween()
				ft.tween_property(old, "modulate:a", 0.0, 1.2)
				ft.tween_callback(old.queue_free)

## The bonsai silhouette: a gnarled S-curved trunk stepping into layered pads —
## segment distance field, thick at the roots, tapering into the twigs.
func _fn_bonsai(uv: Vector2) -> Color:
	var segs := [
		Vector2(-0.8, 1.0), Vector2(-0.55, 0.55), Vector2(-0.55, 0.55), Vector2(-0.65, 0.15),
		Vector2(-0.65, 0.15), Vector2(-0.35, -0.2),
		Vector2(-0.35, -0.2), Vector2(0.05, -0.35), Vector2(0.05, -0.35), Vector2(0.5, -0.3),
		Vector2(-0.65, 0.15), Vector2(-0.2, 0.05), Vector2(-0.2, 0.05), Vector2(0.3, 0.12),
		Vector2(-0.55, 0.55), Vector2(-0.15, 0.5), Vector2(-0.15, 0.5), Vector2(0.2, 0.55),
		Vector2(-0.35, -0.2), Vector2(-0.45, -0.55),
	]
	var a := 0.0
	var i := 0
	while i < segs.size():
		var p1: Vector2 = segs[i]
		var p2: Vector2 = segs[i + 1]
		var mean_h := (p1.y + p2.y) * 0.5
		var th := lerpf(0.13, 0.035, clampf((1.0 - mean_h) * 0.5, 0.0, 1.0))
		a = maxf(a, 1.0 - smoothstep(th * 0.7, th, _seg_dist(uv, p1, p2)))
		i += 2
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	var b := 0.85 + 0.15 * clampf(-uv.y, 0.0, 1.0)   # bark lit faintly from above
	return Color(b, b, b, clampf(a, 0.0, 1.0))

## Zen Garden — a temple garden painted as its own backdrop: a LIT field of
## raked sand (grain, sun pool, warm shade), a flagstone path winding up to a
## vermilion torii gate, a maple and a pine leaning in from the corners, a
## stone lantern with a warm ember, three faceted river stones in their rake
## rings, fallen leaves — and slow ripple rings breathing out of the stones
## while the odd maple leaf drifts down the screen.
# A LANDSCAPE view: sky + horizon + gate in the top band, the stream, bridge,
# lantern and rocks in the foreground band (y > 0.74) — the bands the opaque
# board never covers, so the scenery frames the board in gameplay.
const _ZEN_STONES: Array = [
	[Vector2(0.13, 0.935), 1.0], [Vector2(0.56, 0.958), 0.6]]
const _ZEN_LANTERN := Vector2(0.185, 0.905)   # the tōrō standing by the path
const _ZEN_POND := Vector2(0.80, 0.885)       # the koi pool the river swells into
var _zen_grass: Array = []                    # swaying tufts, kicked by the wind

func _m_zen_sand() -> void:
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED   # grain tiles
	canvas.size = _vp
	canvas.draw.connect(_draw_zen_sand.bind(canvas))
	add_child(canvas)
	canvas.queue_redraw()
	# A sparse fall of maple leaves keeps the garden alive without ever
	# disturbing its calm.
	_emit({"from": "top", "tex": _leaf(), "color": Color(0.82, 0.38, 0.20),
		"alpha": 0.85, "amount": 7, "lifetime": 15.0, "dir": Vector3(0.15, 1, 0),
		"spread": 16.0, "vmin": 16.0, "vmax": 38.0, "smin": 0.6, "smax": 1.1,
		"spin": 1.6, "turb": 0.9})
	_zen_ripples(_gen)
	# --- The koi: a slow patrol around the pond, nose-first on its orbit.
	var pivot := Control.new()
	pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot.position = _ZEN_POND * _vp
	add_child(pivot)
	var koi := TextureRect.new()
	koi.texture = _shaped("zen_koi", 44, 20, _fn_zen_koi)
	koi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	koi.stretch_mode = TextureRect.STRETCH_SCALE
	koi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kw := _vp.x * 0.048
	koi.size = Vector2(kw, kw * 0.45)
	koi.position = Vector2(_vp.x * 0.072, -koi.size.y * 0.5)
	koi.rotation = PI * 0.5
	pivot.add_child(koi)
	# The pond is seen from across the garden, so the orbit is squashed flat.
	pivot.scale = Vector2(1.0, 0.38)
	var orbit := pivot.create_tween().set_loops()
	orbit.tween_property(pivot, "rotation", TAU, 15.0).as_relative()
	# --- Incense: a thin wisp climbing from the lantern's ember.
	var smoke := CPUParticles2D.new()
	smoke.position = _ZEN_LANTERN * _vp + Vector2(0, -_vp.y * 0.040)
	smoke.amount = 7
	smoke.lifetime = 6.0
	smoke.preprocess = 3.0
	smoke.texture = _round()
	smoke.direction = Vector2(0, -1)
	smoke.spread = 8.0
	smoke.initial_velocity_min = 6.0
	smoke.initial_velocity_max = 14.0
	smoke.gravity = Vector2(2.0, -5.0)
	smoke.orbit_velocity_min = -0.015
	smoke.orbit_velocity_max = 0.015
	smoke.scale_amount_min = 0.12
	smoke.scale_amount_max = 0.4
	smoke.color = Color(0.78, 0.76, 0.72, 0.15)
	add_child(smoke)
	# --- Morning mist drifting across the gate.
	for i in 2:
		var m := TextureRect.new()
		m.texture = _round()
		m.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		m.stretch_mode = TextureRect.STRETCH_SCALE
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.size = Vector2(_vp.x * 0.85, _vp.y * 0.07)
		var mx := _vp.x * (0.02 + 0.13 * float(i))
		m.position = Vector2(mx, _vp.y * (0.135 + 0.038 * float(i)))
		m.modulate = Color(1, 1, 1, 0.13)
		add_child(m)
		var mt := m.create_tween().set_loops()
		mt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		mt.tween_property(m, "position:x", mx + _vp.x * 0.07, 16.0 + 7.0 * float(i))
		mt.tween_property(m, "position:x", mx - _vp.x * 0.05, 15.0 + 6.0 * float(i))
	# --- Living light: the SUN crosses the sky through the session; by evening
	# the lantern's glow takes over and fireflies wake around the water.
	var sun := Control.new()
	sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var halo := TextureRect.new()
	halo.texture = _round()
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_SCALE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hd := _vp.x * 0.42
	halo.size = Vector2(hd, hd)
	halo.position = -Vector2(hd, hd) * 0.5
	halo.modulate = Color(1.0, 0.86, 0.55, 0.42)
	sun.add_child(halo)
	var disc := TextureRect.new()
	disc.texture = _round()
	disc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	disc.stretch_mode = TextureRect.STRETCH_SCALE
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dd := _vp.x * 0.085
	disc.size = Vector2(dd, dd)
	disc.position = -Vector2(dd, dd) * 0.5
	disc.modulate = Color(1.0, 0.82, 0.42, 1.0)
	sun.add_child(disc)
	sun.position = Vector2(_vp.x * 0.24, _vp.y * 0.082)
	add_child(sun)
	var st := sun.create_tween()
	st.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	st.tween_property(sun, "position", Vector2(_vp.x * 0.78, _vp.y * 0.062), 300.0)
	var dusk := ColorRect.new()
	dusk.color = Color(0.10, 0.07, 0.14, 0.0)
	dusk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dusk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dusk)
	dusk.create_tween().tween_property(dusk, "color:a", 0.18, 300.0)
	var ember := TextureRect.new()
	ember.texture = _round()
	ember.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ember.stretch_mode = TextureRect.STRETCH_SCALE
	ember.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ed := _vp.y * 0.14
	ember.size = Vector2(ed, ed)
	ember.position = _ZEN_LANTERN * _vp - Vector2(ed, ed) * 0.5
	ember.modulate = Color(1.0, 0.66, 0.26, 0.0)
	add_child(ember)
	ember.create_tween().tween_property(ember, "modulate:a", 0.5, 300.0)
	var flies := CPUParticles2D.new()
	flies.position = Vector2(0.74, 0.85) * _vp
	flies.amount = 9
	flies.lifetime = 6.0
	flies.texture = _dot()
	flies.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	flies.emission_rect_extents = Vector2(_vp.x * 0.26, _vp.y * 0.05)
	flies.direction = Vector2(0, -1)
	flies.spread = 180.0
	flies.initial_velocity_min = 4.0
	flies.initial_velocity_max = 14.0
	flies.orbit_velocity_min = -0.05
	flies.orbit_velocity_max = 0.05
	flies.scale_amount_min = 0.8
	flies.scale_amount_max = 1.8
	flies.color = Color(1.0, 0.85, 0.42)
	flies.modulate.a = 0.0
	add_child(flies)
	var ft := flies.create_tween()
	ft.tween_interval(240.0)
	ft.tween_property(flies, "modulate:a", 0.9, 30.0)
	# --- Grass: living tufts rooted on the ground — small along the horizon,
	# reeds by the water, bold clumps at our feet — all bowing to the gusts.
	_zen_grass.clear()
	for g_v in [[0.05, 0.245, 0.5], [0.31, 0.24, 0.45], [0.57, 0.245, 0.5], [0.90, 0.24, 0.45],
			[0.575, 0.79, 0.6], [0.85, 0.765, 0.55], [0.06, 0.925, 1.1], [0.27, 0.965, 0.9],
			[0.42, 0.905, 0.8], [0.58, 0.968, 1.0], [0.34, 0.925, 0.85], [0.50, 0.935, 1.05]]:
		var g: Array = g_v
		var tuft := TextureRect.new()
		tuft.texture = _shaped("zen_grass", 44, 40, _fn_zen_grass)
		tuft.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tuft.stretch_mode = TextureRect.STRETCH_SCALE
		tuft.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gs: float = 52.0 * float(g[2]) * (_vp.x / 1080.0)
		tuft.size = Vector2(gs, gs * 0.9)
		tuft.pivot_offset = Vector2(gs * 0.5, gs * 0.9)   # sway from the roots
		tuft.position = Vector2(float(g[0]), float(g[1])) * _vp - tuft.pivot_offset
		tuft.modulate = _pc("accent").lerp(Color(0.40, 0.58, 0.36), randf_range(0.25, 0.75))
		add_child(tuft)
		_zen_grass.append(tuft)
		var sway := tuft.create_tween().set_loops()
		sway.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		sway.tween_property(tuft, "rotation", randf_range(0.03, 0.08), randf_range(1.6, 2.6))
		sway.tween_property(tuft, "rotation", randf_range(-0.08, -0.03), randf_range(1.6, 2.6))
	_zen_wind(_gen)
	_zen_teahouse()

## Sand grain: a sparse speckle of darker pits and lit crystals, tiled across
## the field so the sand reads as material instead of flat paint.
func _zen_grain() -> ImageTexture:
	return _shaped("zen_grain", 128, 128, func(_uv: Vector2) -> Color:
		var r := randf()
		if r < 0.05:
			return Color(0.30, 0.26, 0.18, randf_range(0.06, 0.14))
		if r > 0.955:
			return Color(1, 1, 1, randf_range(0.08, 0.18))
		return Color(0, 0, 0, 0))

func _draw_zen_sand(c: Control) -> void:
	# Perf-bench scope (regression/perf/SPEC.md §4.2). BoardFx declares no _process
	# and no _draw of its own — this signal-connected painter is the file's ONLY
	# per-frame GDScript; everything else is engine-side particles/shaders/tweens.
	# No-op (one has_meta, measured 0.0093 µs) unless a bench is running.
	var scoped: bool = Engine.has_meta("bench_scope")
	if scoped:
		Engine.get_meta("bench_scope").call(true, "BoardFx._draw_zen_sand")
	# A LANDSCAPE, not a map: warm sky over a horizon, the torii standing on
	# the ground with the flagstone path running from our feet up to it, hills
	# and the pagoda in the haze, trees flanking the gate, and the stream
	# crossing the foreground under a side-on arched bridge before pooling
	# into the koi pond. Perspective is painted: things shrink toward the gate.
	var sand := _pc("bg0")
	var hor := _vp.y * 0.205   # the horizon line
	# --- The sky: warm morning light, palest at the top of the world.
	c.draw_polygon(PackedVector2Array([
		Vector2.ZERO, Vector2(_vp.x, 0), Vector2(_vp.x, hor), Vector2(0, hor)]),
		PackedColorArray([Color(0.99, 0.955, 0.875), Color(0.99, 0.955, 0.875),
			Color(0.955, 0.895, 0.775), Color(0.955, 0.895, 0.775)]))
	# --- Hills asleep in the haze, the far pagoda standing on the taller one.
	var haze := sand.lerp(Color(0.36, 0.32, 0.44), 0.45)
	haze.a = 0.42
	for h_v in [[0.20, 0.34, 0.045], [0.86, 0.30, 0.068]]:
		var h: Array = h_v
		c.draw_set_transform(Vector2(float(h[0]) * _vp.x, hor), 0.0,
			Vector2(float(h[1]) * _vp.x / 100.0, float(h[2]) * _vp.y / 100.0))
		c.draw_circle(Vector2.ZERO, 100.0, haze)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var gxp := _vp.x * 0.86
	var ty := hor - _vp.y * 0.062
	for tier_w in [0.062, 0.048, 0.035]:
		var tw2: float = tier_w * _vp.x
		var th := _vp.y * 0.014
		c.draw_polygon(PackedVector2Array([
			Vector2(gxp - tw2, ty), Vector2(gxp + tw2, ty),
			Vector2(gxp + tw2 * 0.52, ty - th), Vector2(gxp - tw2 * 0.52, ty - th)]),
			PackedColorArray([haze]))
		c.draw_rect(Rect2(gxp - tw2 * 0.34, ty - th - _vp.y * 0.013,
			tw2 * 0.68, _vp.y * 0.013), haze)
		ty -= th + _vp.y * 0.013
	c.draw_rect(Rect2(gxp - 1.5, ty - _vp.y * 0.010, 3.0, _vp.y * 0.010), haze)
	# --- The ground: raked sand rolling from the horizon to our feet.
	c.draw_polygon(PackedVector2Array([
		Vector2(0, hor), Vector2(_vp.x, hor), _vp, Vector2(0, _vp.y)]),
		PackedColorArray([sand.lightened(0.045), sand.lightened(0.045),
			sand.darkened(0.10), sand.darkened(0.10)]))
	c.draw_texture_rect(_zen_grain(), Rect2(Vector2(0, hor), Vector2(_vp.x, _vp.y - hor)),
		true, Color(1, 1, 1, 0.5))
	c.draw_line(Vector2(0, hor), Vector2(_vp.x, hor), sand.darkened(0.16), 1.5)
	var t := _pc("text")
	var fcol := Color(t.r, t.g, t.b, 0.10)
	var hcol := Color(1, 1, 1, 0.28)
	# Furrows in PERSPECTIVE: tight faint combing near the horizon opening into
	# broad strokes at our feet.
	for li in 26:
		var tt := (float(li) + 0.5) / 26.0
		var fy := lerpf(hor + _vp.y * 0.012, _vp.y * 1.01, pow(tt, 1.6))
		var amp := lerpf(1.2, 6.5, tt)
		var pts := PackedVector2Array()
		var hp := PackedVector2Array()
		var x := -20.0
		while x <= _vp.x + 20.0:
			var wave := sin(x * 0.0075 + float(li) * 0.9) * amp \
				+ sin(x * 0.021 + float(li) * 2.3) * amp * 0.3
			pts.append(Vector2(x, fy + wave))
			hp.append(Vector2(x, fy + wave - lerpf(1.0, 2.6, tt)))
			x += 20.0
		c.draw_polyline(pts, Color(fcol.r, fcol.g, fcol.b, fcol.a * lerpf(0.5, 1.1, tt)),
			lerpf(1.2, 3.0, tt))
		c.draw_polyline(hp, Color(1, 1, 1, 0.28 * lerpf(0.5, 1.1, tt)), lerpf(0.8, 1.5, tt))
	# --- The river: born under the hills, flowing DOWN the garden toward us —
	# a thread at the horizon widening in perspective, sliding UNDER the bridge
	# and swelling into the koi pool before it leaves at our feet.
	var wat := Color(0.15, 0.32, 0.35)
	var r_ctr := PackedVector2Array()
	var r_hw := PackedFloat32Array()
	for k in 33:
		var rt := float(k) / 32.0
		var uu2 := 1.0 - rt
		var rx := (0.665 * (uu2 * uu2) + 0.73 * (2.0 * uu2 * rt) + 0.815 * (rt * rt)) * _vp.x
		var ry := lerpf(hor + _vp.y * 0.004, _vp.y * 1.02, pow(rt, 1.28))
		r_ctr.append(Vector2(rx + sin(rt * 9.0) * _vp.x * 0.012 * rt, ry))
		# Width grows with nearness, and bulges into the pool basin near t≈0.86.
		r_hw.append((lerpf(0.010, 0.130, pow(rt, 1.35)) \
			* (1.0 + 0.55 * exp(-pow((rt - 0.86) / 0.09, 2.0)))) * _vp.x)
	var bank_lft := PackedVector2Array()
	var bank_rgt := PackedVector2Array()
	for k in r_ctr.size():
		bank_lft.append(r_ctr[k] - Vector2(r_hw[k], 0))
		bank_rgt.append(r_ctr[k] + Vector2(r_hw[k], 0))
	var water_poly := PackedVector2Array()
	water_poly.append_array(bank_lft)
	var wrev := bank_rgt.duplicate()
	wrev.reverse()
	water_poly.append_array(wrev)
	c.draw_polyline(bank_lft, sand.darkened(0.14), 5.0)
	c.draw_polyline(bank_rgt, sand.darkened(0.14), 5.0)
	c.draw_polygon(water_poly, PackedColorArray([wat]))
	# Sky light resting on the koi pool, and current lines riding the flow.
	var pool_c := _ZEN_POND * _vp
	c.draw_texture_rect(_round(), Rect2(pool_c + Vector2(-_vp.x * 0.075, -_vp.y * 0.030),
		Vector2(_vp.x * 0.15, _vp.y * 0.040)), false, Color(0.62, 0.80, 0.76, 0.26))
	for fl in 2:
		var fpts := PackedVector2Array()
		for k in range(7, r_ctr.size()):
			var off2 := (float(fl) - 0.5) * 1.35
			fpts.append(r_ctr[k] + Vector2(r_hw[k] * off2 * 0.55 \
				+ sin(float(k) * 0.7 + float(fl) * 2.0) * 3.0, 0))
		c.draw_polyline(fpts, Color(0.55, 0.78, 0.76, 0.30 - 0.08 * float(fl)), 1.8)
	# Pebbles hugging both banks, bolder as the river nears our feet.
	var srng := RandomNumberGenerator.new()
	srng.seed = 777
	for k in range(2, r_ctr.size(), 2):
		var t4 := float(k) / float(r_ctr.size() - 1)
		for side3 in [-1.0, 1.0]:
			var bp3 := r_ctr[k] + Vector2(
				(r_hw[k] + srng.randf_range(4.0, 14.0)) * side3,
				srng.randf_range(-6.0, 6.0))
			c.draw_circle(bp3, lerpf(1.5, 7.0, t4) + srng.randf_range(0.0, 2.0),
				Color(0.55, 0.55, 0.53).lightened(srng.randf_range(-0.07, 0.09)))
	# --- The path: flagstones from our feet straight up to the gate, shrinking
	# with distance. The river keeps to the garden's right, so they never meet —
	# the bridge is the garden's own crossing, further along the bank.
	var prng := RandomNumberGenerator.new()
	prng.seed = 20480
	var stone_col := Color(0.63, 0.61, 0.56)
	for k in 14:
		var tt2 := (float(k) + 0.5) / 14.0
		var py := lerpf(_vp.y * 1.0, hor + _vp.y * 0.025, pow(tt2, 0.82))
		var px2 := _vp.x * 0.42 + sin(tt2 * 3.1) * _vp.x * 0.035 * (1.0 - tt2) \
			+ (1.0 if k % 2 == 0 else -1.0) * lerpf(26.0, 4.0, tt2) \
			+ _vp.x * 0.08 * tt2
		var fr := lerpf(52.0, 9.0, pow(tt2, 0.9)) * (_vp.x / 1080.0)
		c.draw_set_transform(Vector2(px2, py), 0.0, Vector2(1.0, 0.42))
		c.draw_circle(Vector2(3.0, 8.0), fr, Color(0.1, 0.08, 0.05, 0.18))
		var spts := PackedVector2Array()
		for v in 10:
			var ang := float(v) / 10.0 * TAU
			spts.append(Vector2(cos(ang), sin(ang)) * fr * prng.randf_range(0.84, 1.12))
		c.draw_polygon(spts, PackedColorArray([stone_col.lightened(prng.randf_range(-0.04, 0.07))]))
		c.draw_circle(Vector2(-fr * 0.10, -fr * 0.16), fr * 0.70, stone_col.lightened(0.12))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# --- The bridge, side-on as we see it: a wooden arch vaulting the river
	# just above the koi pool, feet on STONE FOOTINGS on both banks — the
	# water slides visibly UNDER it on its way to the pool at our feet.
	var bk := 0
	var bdd := 1e12
	for k in r_ctr.size():
		var dv := absf(r_ctr[k].y - _vp.y * 0.805)
		if dv < bdd:
			bdd = dv
			bk = k
	var bc := Vector2(r_ctr[bk].x, r_ctr[bk].y)
	var brr: float = r_hw[bk] * 1.55
	var wood := Color(0.42, 0.27, 0.15)
	for foot in [-1.0, 1.0]:
		var fx2: float = bc.x + foot * brr * 0.96
		c.draw_set_transform(Vector2(fx2, bc.y + 2.0), 0.0, Vector2(1.0, 0.5))
		c.draw_circle(Vector2.ZERO, _vp.x * 0.026, Color(0.55, 0.54, 0.50))
		c.draw_circle(Vector2(-_vp.x * 0.006, -_vp.x * 0.006), _vp.x * 0.019,
			Color(0.64, 0.63, 0.58))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	c.draw_arc(bc + Vector2(0, brr * 0.40), brr * 1.04, PI + 0.34, TAU - 0.34, 48,
		Color(0.09, 0.18, 0.20, 0.35), 8.0)   # reflection in the water
	c.draw_arc(bc + Vector2(0, brr * 0.52), brr, PI + 0.35, TAU - 0.35, 48, wood, 11.0)
	c.draw_arc(bc + Vector2(0, brr * 0.52), brr * 1.24, PI + 0.42, TAU - 0.42, 48,
		wood.lightened(0.14), 5.0)
	for k in 5:
		var post_dx := (float(k) - 2.0) * brr * 0.40
		var deck_y := bc.y + brr * 0.52 - sqrt(maxf(brr * brr - post_dx * post_dx, 0.0))
		var rail_y := bc.y + brr * 0.52 \
			- sqrt(maxf(pow(brr * 1.24, 2.0) - post_dx * post_dx, 0.0))
		c.draw_rect(Rect2(bc.x + post_dx - 2.4, rail_y, 4.8, deck_y - rail_y),
			wood.lightened(0.07))
	# --- The torii, STANDING on the ground at the path's end.
	var tor := Color(0.66, 0.19, 0.13)
	var tor_dark := tor.darkened(0.28)
	var cap_col := Color(0.13, 0.11, 0.11)
	var gx := _vp.x * 0.5
	var gw := _vp.x * 0.205
	var gy := _vp.y * 0.085
	var gh := hor + _vp.y * 0.012
	var pw := _vp.x * 0.020
	var px := _vp.x * 0.118
	var rise := _vp.y * 0.010
	var beam_h := _vp.y * 0.0145
	for side2 in [-1.0, 1.0]:
		var cx: float = gx + side2 * px
		c.draw_set_transform(Vector2(cx, gh + 3.0), 0.0, Vector2(1.0, 0.35))
		c.draw_circle(Vector2.ZERO, pw * 1.7, Color(0.1, 0.08, 0.05, 0.22))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		c.draw_rect(Rect2(cx - pw * 0.5, gy + beam_h * 0.6, pw, gh - gy),
			tor if side2 < 0.0 else tor_dark)
		c.draw_rect(Rect2(cx - pw * 0.75, gh - _vp.y * 0.006, pw * 1.5, _vp.y * 0.008),
			cap_col)
	c.draw_polygon(PackedVector2Array([
		Vector2(gx - gw, gy - rise), Vector2(gx, gy),
		Vector2(gx, gy + beam_h), Vector2(gx - gw, gy + beam_h - rise * 0.4)]),
		PackedColorArray([tor]))
	c.draw_polygon(PackedVector2Array([
		Vector2(gx, gy), Vector2(gx + gw, gy - rise),
		Vector2(gx + gw, gy + beam_h - rise * 0.4), Vector2(gx, gy + beam_h)]),
		PackedColorArray([tor_dark]))
	c.draw_polygon(PackedVector2Array([
		Vector2(gx - gw - pw * 0.4, gy - rise - beam_h * 0.42), Vector2(gx, gy - beam_h * 0.42),
		Vector2(gx + gw + pw * 0.4, gy - rise - beam_h * 0.42),
		Vector2(gx + gw, gy - rise * 0.2), Vector2(gx, gy + beam_h * 0.12),
		Vector2(gx - gw, gy - rise * 0.2)]), PackedColorArray([cap_col]))
	c.draw_rect(Rect2(gx - gw * 0.82, gy + _vp.y * 0.034, gw * 1.64, beam_h * 0.75), tor)
	c.draw_rect(Rect2(gx - pw * 0.4, gy + beam_h, pw * 0.8, _vp.y * 0.020), tor_dark)
	# --- The trees, rooted on the horizon: a maple in autumn colour left of
	# the gate, a pine to its right, both with their feet in a soft shadow.
	for tree_v in [[0.115, true], [0.885, false]]:
		var tree: Array = tree_v
		var tx: float = float(tree[0]) * _vp.x
		var is_maple: bool = tree[1]
		var base_y := hor + _vp.y * 0.010
		var top_y := _vp.y * (0.088 if is_maple else 0.105)
		c.draw_set_transform(Vector2(tx, base_y + 2.0), 0.0, Vector2(1.0, 0.32))
		c.draw_circle(Vector2.ZERO, _vp.x * 0.045, Color(0.1, 0.08, 0.05, 0.20))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		c.draw_polygon(PackedVector2Array([
			Vector2(tx - _vp.x * 0.009, base_y), Vector2(tx + _vp.x * 0.009, base_y),
			Vector2(tx + _vp.x * 0.004, top_y + _vp.y * 0.05),
			Vector2(tx - _vp.x * 0.004, top_y + _vp.y * 0.05)]),
			PackedColorArray([Color(0.26, 0.18, 0.14)]))
		var crown_cols: Array = [Color(0.55, 0.20, 0.12, 0.95), Color(0.74, 0.32, 0.15, 0.95),
			Color(0.88, 0.48, 0.20, 0.92)] if is_maple else \
			[Color(0.16, 0.27, 0.18, 0.95), Color(0.25, 0.40, 0.25, 0.95),
			Color(0.36, 0.52, 0.31, 0.92)]
		for b in 6:
			var brng := float(b) * 1.9 + (0.0 if is_maple else 1.0)
			var bo := Vector2(sin(brng) * 0.052, cos(brng * 1.3) * 0.030) * _vp.x
			var brad := _vp.x * (0.072 - float(b) * 0.006)
			var bcol: Color = crown_cols[mini(b / 2, crown_cols.size() - 1)]
			c.draw_texture_rect(_round(), Rect2(
				Vector2(tx, top_y) + bo - Vector2(brad, brad),
				Vector2(brad, brad) * 2.0), false, bcol)
	# --- The stone lantern, standing by the path in the foreground.
	var lp0 := _ZEN_LANTERN * _vp
	var ls := _vp.y * 0.0165
	var rock_grey := Color(0.53, 0.52, 0.47)
	c.draw_set_transform(lp0 + Vector2(0, ls * 3.0), 0.0, Vector2(1.0, 0.38))
	c.draw_circle(Vector2.ZERO, ls * 2.6, Color(0.1, 0.08, 0.05, 0.24))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	c.draw_rect(Rect2(lp0 + Vector2(-ls * 1.7, ls * 2.2), Vector2(ls * 3.4, ls * 0.8)),
		rock_grey.darkened(0.12))
	c.draw_rect(Rect2(lp0 + Vector2(-ls * 0.42, ls * 0.6), Vector2(ls * 0.84, ls * 1.7)),
		rock_grey.darkened(0.06))
	c.draw_texture_rect(_dot(), Rect2(lp0 + Vector2(-ls * 2.4, -ls * 2.4),
		Vector2(ls * 4.8, ls * 4.8)), false, Color(1.0, 0.72, 0.30, 0.30))
	c.draw_rect(Rect2(lp0 + Vector2(-ls * 1.05, -ls * 0.9), Vector2(ls * 2.1, ls * 1.55)),
		rock_grey)
	c.draw_rect(Rect2(lp0 + Vector2(-ls * 0.55, -ls * 0.62), Vector2(ls * 1.1, ls * 1.0)),
		Color(1.0, 0.80, 0.42))
	c.draw_polygon(PackedVector2Array([
		lp0 + Vector2(-ls * 1.9, -ls * 0.9), lp0 + Vector2(0, -ls * 2.1),
		lp0 + Vector2(ls * 1.9, -ls * 0.9)]), PackedColorArray([rock_grey.darkened(0.18)]))
	c.draw_circle(lp0 + Vector2(0, -ls * 2.3), ls * 0.34, rock_grey.darkened(0.10))
	# --- The rocks, sitting on the sand inside their raked rings (ellipses now:
	# we are looking ACROSS the garden, not down at it).
	var dim := _pc("text_dim")
	for s_v in _ZEN_STONES:
		var s: Array = s_v
		var sp: Vector2 = (s[0] as Vector2) * _vp
		var rr: float = minf(_vp.x, _vp.y) * 0.14 * float(s[1])
		c.draw_set_transform(sp, 0.0, Vector2(1.0, 0.42))
		c.draw_texture_rect(_round(), Rect2(-Vector2(rr, rr) * 1.5, Vector2(rr, rr) * 3.0),
			false, sand.darkened(0.02))
		for k in 3:
			var r := rr * (0.62 + 0.24 * float(k))
			var fade := 1.0 - float(k) * 0.2
			c.draw_arc(Vector2.ZERO, r, 0.0, TAU, 72,
				Color(fcol.r, fcol.g, fcol.b, fcol.a * fade), 2.4)
			c.draw_arc(Vector2.ZERO, r - 2.2, 0.0, TAU, 72, Color(1, 1, 1, 0.24 * fade), 1.2)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(sp.x * 7.0 + sp.y * 13.0)
		var base := dim.darkened(0.42)
		var sr := rr * 0.44
		c.draw_set_transform(sp + Vector2(sr * 0.15, sr * 0.28), 0.0, Vector2(1.0, 0.4))
		c.draw_circle(Vector2.ZERO, sr * 1.15, Color(0.1, 0.08, 0.05, 0.28))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for layer in 3:
			var lr := sr * (1.0 - float(layer) * 0.26)
			var off := Vector2(-sr * 0.10, -sr * 0.16) * float(layer)
			var pts2 := PackedVector2Array()
			for k in 12:
				var ang := float(k) / 12.0 * TAU
				var rad := lr * rng.randf_range(0.86, 1.14)
				pts2.append(sp + off + Vector2(cos(ang) * rad, sin(ang) * rad * 0.72) \
					- Vector2(0, sr * 0.35))
			c.draw_polygon(pts2, PackedColorArray([base.lightened(0.10 * float(layer) + 0.02)]))
		var moss := _pc("accent")
		c.draw_texture_rect(_round(), Rect2(sp + Vector2(sr * 0.30, sr * 0.02) \
			- Vector2(sr, sr) * 0.42, Vector2(sr, sr) * 0.84),
			false, Color(moss.r, moss.g, moss.b, 0.28))
	# --- Fallen leaves resting on the foreground sand.
	var leaves: Array = [
		[Vector2(0.36, 0.905), 0.7, Color(0.80, 0.34, 0.20)],
		[Vector2(0.60, 0.928), -0.5, Color(0.86, 0.54, 0.18)],
		[Vector2(0.48, 0.968), 1.9, Color(0.74, 0.28, 0.24)]]
	for l_v in leaves:
		var l: Array = l_v
		var lp: Vector2 = (l[0] as Vector2) * _vp
		var lsz := Vector2(24.0, 40.0)
		c.draw_set_transform(lp, float(l[1]), Vector2.ONE)
		c.draw_texture_rect(_dot(), Rect2(-lsz * 0.42 + Vector2(2.5, 3.5), lsz * 0.9),
			false, Color(0.1, 0.08, 0.05, 0.26))
		c.draw_texture_rect(_leaf(), Rect2(-lsz * 0.5, lsz), false, l[2])
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if scoped:
		Engine.get_meta("bench_scope").call(false, "BoardFx._draw_zen_sand")

func _zen_ripples(gen: int) -> void:
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(5.0, 9.0)).timeout
		if gen != _gen or not is_inside_tree():
			return
		var stone: Array = _ZEN_STONES[randi() % _ZEN_STONES.size()]
		_zen_ring((stone[0] as Vector2) * _vp)

## One slow rake-ring breathing outward — the garden's heartbeat, shared by
## the idle ripples and the reactive pebble drops.
func _zen_ring(p: Vector2, strength: float = 1.0) -> void:
	var ring := TextureRect.new()
	ring.texture = _ring()
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.stretch_mode = TextureRect.STRETCH_SCALE
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Squashed flat: the ring lies ON the ground we are looking across.
	const D0 := 70.0
	ring.size = Vector2(D0, D0 * 0.42)
	ring.position = p - ring.size * 0.5
	ring.pivot_offset = ring.size * 0.5
	var t := _pc("text")
	ring.modulate = Color(t.r, t.g, t.b, 0.0)
	add_child(ring)
	var tw := ring.create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(ring, "modulate:a", 0.15 * strength, 0.9)
	tw.parallel().tween_property(ring, "scale", Vector2(3.4, 3.4), 4.4)
	tw.tween_property(ring, "modulate:a", 0.0, 1.5)
	tw.tween_callback(ring.queue_free)

## REACTIVE zen: every committed swipe pulls fresh rake strokes through the
## sand along the move's direction; they linger a moment, then the sand
## forgets them.
func _zen_rake(dir: Vector2) -> void:
	if dir.length() < 0.1:
		return
	_zen_gust(dir, 1.0)   # the move IS a wind: grass bows, leaves tear loose
	for i in 4:
		var mark := TextureRect.new()
		mark.texture = _streak()
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_SCALE
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ln := randf_range(90.0, 190.0) * (_vp.x / 1080.0)
		mark.size = Vector2(3.5, ln)
		mark.pivot_offset = mark.size * 0.5
		mark.rotation = dir.angle() - PI * 0.5
		var t := _pc("text")
		mark.modulate = Color(t.r, t.g, t.b, 0.0)
		var p := Vector2(randf_range(0.12, 0.88) * _vp.x, randf_range(0.12, 0.88) * _vp.y)
		mark.position = p - mark.size * 0.5
		add_child(mark)
		var tw := mark.create_tween()
		tw.tween_property(mark, "modulate:a", 0.26, 0.12).set_delay(float(i) * 0.04)
		tw.parallel().tween_property(mark, "position",
			mark.position + dir.normalized() * 60.0, 0.5) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_interval(1.2)
		tw.tween_property(mark, "modulate:a", 0.0, 0.9)
		tw.tween_callback(mark.queue_free)

## REACTIVE zen: a merge drops a pebble into the sand where it happened — a
## plop, a rake-ring spreading, and the garden slowly swallowing the stone.
func _zen_pebble(pos: Vector2) -> void:
	if get_tree() == null:
		return
	var live := get_tree().get_nodes_in_group("zen_pebbles")
	while live.size() >= 6 and not live.is_empty():
		var old: Node = live.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var peb := TextureRect.new()
	peb.add_to_group("zen_pebbles")
	peb.texture = _shaped("zen_drop_pebble", 26, 22, _fn_zen_pebble)
	peb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	peb.stretch_mode = TextureRect.STRETCH_SCALE
	peb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d := randf_range(24.0, 36.0) * (_vp.x / 1080.0)
	peb.size = Vector2(d, d * 0.85)
	peb.position = pos - peb.size * 0.5
	peb.pivot_offset = peb.size * 0.5
	peb.rotation = randf_range(-0.6, 0.6)
	add_child(peb)
	_zen_ring(pos, 1.4)
	var tw := peb.create_tween()
	tw.tween_property(peb, "scale", Vector2.ONE, 0.28) \
		.from(Vector2(1.7, 1.7)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(5.0)
	tw.tween_property(peb, "modulate:a", 0.0, 1.4)
	tw.tween_callback(peb.queue_free)

## A dropped pebble: lumpy silhouette, lit from the top-left.
func _fn_zen_pebble(uv: Vector2) -> Color:
	var ang := atan2(uv.y, uv.x)
	var edge := 0.80 + 0.10 * sin(ang * 3.0 + 0.8) + 0.05 * sin(ang * 5.0)
	if uv.length() > edge:
		return Color(0, 0, 0, 0)
	var b := 0.60 - uv.y * 0.16 - uv.x * 0.06
	return Color(b, b, b * 0.94, 1.0)

## The idle breeze: every few seconds a soft gust crosses the garden on its
## own, so the grass never stands perfectly still for long.
func _zen_wind(gen: int) -> void:
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(7.0, 12.0)).timeout
		if gen != _gen or not is_inside_tree():
			return
		_zen_gust(Vector2(1.0 if randf() < 0.5 else -1.0, randf_range(-0.2, 0.2)),
			randf_range(0.45, 0.85))

## One gust: every tuft bows downwind (staggered, springing back elastically)
## and a few autumn leaves tear loose and tumble across the garden with it.
func _zen_gust(dir: Vector2, strength: float) -> void:
	if dir.length() < 0.1:
		return
	var lean := 0.34 * strength * (1.0 if dir.x >= 0.0 else -1.0)
	if absf(dir.x) < 0.15:
		lean = 0.20 * strength * (1.0 if randf() < 0.5 else -1.0)
	for t_v in _zen_grass:
		if not is_instance_valid(t_v):
			continue
		var tuft: TextureRect = t_v
		var kick := tuft.create_tween()
		kick.tween_interval(randf_range(0.0, 0.20))
		kick.tween_property(tuft, "rotation", lean * randf_range(0.7, 1.3), 0.26) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		kick.tween_property(tuft, "rotation", 0.04, 1.2) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var across := dir.x >= 0.0
	for i in randi_range(2, 4):
		var lf := TextureRect.new()
		lf.texture = _leaf()
		lf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lf.stretch_mode = TextureRect.STRETCH_SCALE
		lf.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ld := randf_range(18.0, 30.0) * (_vp.x / 1080.0)
		lf.size = Vector2(ld, ld * 1.65)
		lf.pivot_offset = lf.size * 0.5
		lf.modulate = [Color(0.82, 0.38, 0.20), Color(0.88, 0.56, 0.20),
			Color(0.74, 0.28, 0.24)][i % 3]
		var start := Vector2((-50.0) if across else (_vp.x + 50.0),
			randf_range(0.08, 0.92) * _vp.y)
		lf.position = start
		add_child(lf)
		var fly := lf.create_tween()
		fly.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		fly.tween_property(lf, "position", Vector2(
			(_vp.x + 60.0) if across else -60.0,
			start.y + randf_range(-0.06, 0.14) * _vp.y),
			randf_range(1.6, 2.8) / maxf(strength, 0.4))
		fly.tween_callback(lf.queue_free)
		var spin := lf.create_tween().set_loops()
		spin.tween_property(lf, "rotation", TAU, randf_range(0.7, 1.3)).as_relative()

## A grass tuft: five blades fanning from the roots, each its own paper-flat
## brightness (tinted moss-green per tuft at spawn).
func _fn_zen_grass(uv: Vector2) -> Color:
	var blades: Array = [[-0.72, 0.30], [-0.38, 0.62], [0.0, 0.95], [0.36, 0.66], [0.70, 0.34]]
	for i in blades.size():
		var b: Array = blades[i]
		var tip := Vector2(float(b[0]), 1.0 - 2.0 * float(b[1]))
		var root := Vector2(float(b[0]) * 0.10, 1.0)
		if _in_tri(uv, root + Vector2(-0.10, 0.0), root + Vector2(0.10, 0.0), tip):
			var g := 0.68 + 0.30 * (float(i % 3) / 2.0)
			return Color(g, g, g, 1.0)
	return Color(0, 0, 0, 0)

func _in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p - b).cross(a - b)
	var d2 := (p - c).cross(b - c)
	var d3 := (p - a).cross(c - a)
	var neg := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var pos := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (neg and pos)

## The koi from above: an orange teardrop with a white saddle and a soft tail.
func _fn_zen_koi(uv: Vector2) -> Color:
	var body := pow(uv.x * 0.92 + 0.12, 2.0) / 1.0 + (uv.y * uv.y) / 0.40
	if body < 1.0:
		if absf(uv.x - 0.30) < 0.16:
			return Color(0.97, 0.94, 0.88, 1)
		return Color(0.95, 0.45, 0.14, 1)
	if uv.x < -0.55 and absf(uv.y) < (uv.x + 1.05) * 0.85:
		return Color(0.95, 0.52, 0.22, 0.9)
	return Color(0, 0, 0, 0)

## Gameplay forwards every committed swipe here. Reward themes answer through
## RewardFx; the zen garden rakes the sand and the abyss drags a wake of light
## across the water. Every other theme ignores it.
func on_swipe(dir: Vector2i) -> void:
	if _reward != null and is_instance_valid(_reward):
		_reward.on_swipe(dir)
		return
	var motif := _motif()
	match motif:
		"zen_sand": _zen_rake(Vector2(dir))
		"biolum":   _biolum_wake(Vector2(dir))
		"mono":     _mono_nudge(Vector2(dir))
		"wash":
			_wash_run(Vector2(dir))
			_react_swipe(motif, Vector2(dir))
		"altitude":
			_altitude_contrail(Vector2(dir))
			_react_swipe(motif, Vector2(dir))
		_:          _react_swipe(motif, Vector2(dir))

## Gameplay forwards every merge here with its GLOBAL screen position; the tile's
## own colour rides along so effects can answer in the exact hue that just merged.
func on_merge(global_pos: Vector2, value: int) -> void:
	var local: Vector2 = global_pos - get_global_rect().position
	if _reward != null and is_instance_valid(_reward):
		var style := ThemeManager.tile_style_for(_pal(), value)
		var tint: Color = (style["bg"] as Color).lightened(0.25)
		_reward.on_merge(local, value, tint)
		return
	# The bigger the tile, the harder the world is hit.
	var step: int = int(round(log(maxf(float(absi(value)), 2.0)) / log(2.0)))
	var strength: float = clampf(0.70 + float(step) * 0.07, 0.70, 1.50)
	var motif := _motif()
	match motif:
		"zen_sand": _zen_pebble(local)
		"biolum":   _biolum_flash(local, strength)
		"snow":
			# Both: the powder the recipe table throws, and the village itself
			# answering — hearths up in the windows, chimney pushing harder.
			_react_merge(motif, local, strength)
			_snow_react(strength)
		"marble":
			_react_merge(motif, local, strength)
			_marble_crack(local, strength)
		"noir":
			_react_merge(motif, local, strength)
			_noir_flash(strength)
		"wash":
			_react_merge(motif, local, strength)
			_wash_drop(local, value)
		"bismuth":
			_react_merge(motif, local, strength)
			_bismuth_step(local, strength)
		"redwood":
			_react_merge(motif, local, strength)
			_redwood_light(local, strength)
		_:          _react_merge(motif, local, strength)

## Gameplay forwards the player's finger here (press + drag) in GLOBAL screen
## coords; the active reward effect surfaces toward it and the abyss ignites
## plankton under it. Converted to local space like on_merge; every other theme
## ignores it. Fires on EVERY drag event — see _biolum_touch on the throttle.
func on_touch(global_pos: Vector2) -> void:
	var local: Vector2 = global_pos - get_global_rect().position
	if _reward != null and is_instance_valid(_reward):
		_reward.on_touch(local)
	elif _motif() == "biolum":
		_biolum_touch(local)

## A celebration beat (the Home wordmark tap): reward themes flare their whole
## world at once, the zen garden answers with every stone rippling together, and
## the abyss sets the whole bloom off.
func celebrate() -> void:
	if _reward != null and is_instance_valid(_reward):
		_reward.on_celebrate()
		return
	var motif := _motif()
	match motif:
		"zen_sand":
			for s_v in _ZEN_STONES:
				_zen_ring(((s_v as Array)[0] as Vector2) * _vp, 1.4)
			_zen_gust(Vector2(1.0 if randf() < 0.5 else -1.0, 0.0), 1.0)
		"biolum":
			_biolum_celebrate()
		"snow":
			_react_celebrate(motif)
			_snow_react(1.5)
			_sleigh_fly()     # and somebody crosses the moon
		"noir":
			_react_celebrate(motif)
			_noir_flash(1.5)
		_:
			_react_celebrate(motif)

# --- The catalogue answers the player -----------------------------------------
#
# Bioluminescence proved the point: an ambience that REACTS stops being a
# wallpaper. Doing that fifty-two times over as bespoke code would be fifty-two
# chances to drift, so everything except the three bespoke worlds (the reward
# themes through RewardFx, the zen garden, the abyss) is driven from one table
# of recipes and three primitives.
#
# A recipe says what the WORLD throws when the player moves it, in that world's
# own material: Arctic throws powder, Autumn throws leaves, Raining Gold throws
# coins, Carnival throws confetti. The merge burst on the BOARD (board_view
# _emit_merge_burst) is the tile's reaction; this is the room's.
#
# Cost: ONE CPUParticles2D per reaction — a single node with its field simulated
# in engine code, not a dozen Controls each dragging a Tween — capped at
# _REACT_LIVE at once, because a 4x4 swipe can land eight merges on one frame and
# swipe frames are the budget this must not overspend.
const _REACT := {
	# --- water / air ---------------------------------------------------------
	"snow":          {"tex": "snowflake", "col": "white",   "n": 14, "spd": 120.0, "grav": 70.0,  "spin": 1.6, "life": 1.1, "size": 0.5},
	"petals":        {"tex": "petal",     "col": "accent",  "n": 13, "spd": 130.0, "grav": 60.0,  "spin": 2.6, "life": 1.3, "size": 0.9},
	"bubbles":       {"tex": "bubble",    "col": "white",   "n": 14, "spd": 110.0, "grav": -90.0, "spin": 0.0, "life": 1.2, "size": 0.7, "ring": true},
	"deep_sea":      {"tex": "bubble",    "col": "accent2", "n": 14, "spd": 120.0, "grav": -80.0, "spin": 0.0, "life": 1.2, "size": 0.7, "ring": true},
	"rain":          {"tex": "dot",       "col": "white",   "n": 16, "spd": 150.0, "grav": 260.0, "spin": 0.0, "life": 0.7, "size": 0.35, "ring": true},
	"neon_rain":     {"tex": "dot",       "col": "accent",  "n": 16, "spd": 160.0, "grav": 240.0, "spin": 0.0, "life": 0.7, "size": 0.4,  "ring": true},
	"fog":           {"tex": "round",     "col": "accent",  "n": 10, "spd": 70.0,  "grav": -20.0, "spin": 0.0, "life": 1.9, "size": 1.2, "alpha": 0.30},
	"shadow":        {"tex": "round",     "col": "accent2", "n": 10, "spd": 65.0,  "grav": -18.0, "spin": 0.0, "life": 2.0, "size": 1.3, "alpha": 0.26},
	"aurora":        {"tex": "sparkle",   "col": "accent2", "n": 14, "spd": 140.0, "grav": -40.0, "spin": 1.0, "life": 1.2, "size": 0.6},
	# --- fire / light --------------------------------------------------------
	"embers":        {"tex": "dot",       "col": "FF8A3C",  "n": 18, "spd": 150.0, "grav": -130.0,"spin": 0.0, "life": 1.2, "size": 0.45},
	"embers_lux":    {"tex": "dot",       "col": "FFB74A",  "n": 18, "spd": 150.0, "grav": -130.0,"spin": 0.0, "life": 1.2, "size": 0.45},
	"lanterns":      {"tex": "lantern",   "col": "FFB25C",  "n": 8,  "spd": 90.0,  "grav": -120.0,"spin": 0.4, "life": 1.6, "size": 0.7},
	"firefly_night": {"tex": "dot",       "col": "FFE87A",  "n": 14, "spd": 90.0,  "grav": -50.0, "spin": 0.0, "life": 1.6, "size": 0.5},
	"fireflies":     {"tex": "dot",       "col": "FFE87A",  "n": 14, "spd": 90.0,  "grav": -50.0, "spin": 0.0, "life": 1.6, "size": 0.5},
	# Daybreak: the move IS a gust — fresh leaves lift off the merge (and stream
	# across on a swipe), rising on the same negative gravity the dust rode.
	"lightdust":     {"tex": "leaf",      "col": "8FCF5C",  "n": 12, "spd": 115.0, "grav": -70.0, "spin": 3.0, "life": 1.5, "size": 0.55, "ring": true},
	"moonlit":       {"tex": "leaf",      "col": "accent",  "n": 12, "spd": 110.0, "grav": 55.0,  "spin": 2.2, "life": 1.4, "size": 0.8},
	"toxic":         {"tex": "dot",       "col": "6BFF5A",  "n": 16, "spd": 170.0, "grav": 0.0,   "spin": 0.0, "life": 0.9, "size": 0.5,  "ring": true},
	"neon":          {"tex": "dot",       "col": "accent",  "n": 16, "spd": 180.0, "grav": 0.0,   "spin": 0.0, "life": 0.8, "size": 0.5,  "ring": true},
	# --- sky / space ---------------------------------------------------------
	"stars":         {"tex": "sparkle",   "col": "white",   "n": 14, "spd": 150.0, "grav": 0.0,   "spin": 0.8, "life": 1.1, "size": 0.55},
	"space":         {"tex": "sparkle",   "col": "white",   "n": 14, "spd": 160.0, "grav": 0.0,   "spin": 0.8, "life": 1.1, "size": 0.55},
	"stardrift":     {"tex": "sparkle",   "col": "accent",  "n": 13, "spd": 130.0, "grav": 0.0,   "spin": 0.7, "life": 1.2, "size": 0.5},
	"nebula":        {"tex": "round",     "col": "accent2", "n": 12, "spd": 95.0,  "grav": 0.0,   "spin": 0.0, "life": 2.2, "size": 1.1, "alpha": 0.32},
	"blood_moon":    {"tex": "dot",       "col": "C42A22",  "n": 14, "spd": 130.0, "grav": 180.0, "spin": 0.0, "life": 1.0, "size": 0.5,  "ring": true},
	"sunset":        {"tex": "dot",       "col": "gold",    "n": 14, "spd": 120.0, "grav": -60.0, "spin": 0.0, "life": 1.4, "size": 0.6},
	"phantom":       {"tex": "orb",       "col": "accent",  "n": 10, "spd": 100.0, "grav": -60.0, "spin": 0.0, "life": 1.6, "size": 0.9},
	"grid":          {"tex": "square",    "col": "accent2", "n": 14, "spd": 170.0, "grav": 0.0,   "spin": 1.2, "life": 0.9, "size": 0.5,  "ring": true},
	# --- earth / material ----------------------------------------------------
	"leaves":        {"tex": "leaf",      "col": "D2691E",  "n": 13, "spd": 120.0, "grav": 80.0,  "spin": 3.0, "life": 1.5, "size": 0.9},
	"desert":        {"tex": "dot",       "col": "E8C06A",  "n": 16, "spd": 130.0, "grav": 90.0,  "spin": 0.0, "life": 1.1, "size": 0.5},
	"desert_night":  {"tex": "dot",       "col": "E8C06A",  "n": 16, "spd": 130.0, "grav": 90.0,  "spin": 0.0, "life": 1.1, "size": 0.5},
	"crystal":       {"tex": "shard",     "col": "white",   "n": 14, "spd": 180.0, "grav": 150.0, "spin": 2.0, "life": 1.0, "size": 0.7},
	"gems":          {"tex": "gem",       "col": "board",   "n": 14, "spd": 190.0, "grav": 220.0, "spin": 1.6, "life": 1.0, "size": 0.7},
	"rain_gold":     {"tex": "coin",      "col": "FFD24A",  "n": 12, "spd": 190.0, "grav": 320.0, "spin": 2.0, "life": 1.0, "size": 0.8},
	"rain_silver":   {"tex": "ingot",     "col": "E4EAF6",  "n": 10, "spd": 170.0, "grav": 320.0, "spin": 1.6, "life": 1.0, "size": 0.7},
	"rain_diamond":  {"tex": "gem",       "col": "EAF6FF",  "n": 14, "spd": 190.0, "grav": 280.0, "spin": 1.8, "life": 1.0, "size": 0.6},
	"honeycomb":     {"tex": "hex",       "col": "F5B02E",  "n": 12, "spd": 120.0, "grav": 160.0, "spin": 1.0, "life": 1.2, "size": 0.7},
	"bonsai":        {"tex": "petal",     "col": "FFAFC8",  "n": 13, "spd": 110.0, "grav": 55.0,  "spin": 2.4, "life": 1.5, "size": 0.8},
	"butterflies":   {"tex": "butterfly", "col": "accent",  "n": 10, "spd": 110.0, "grav": -30.0, "spin": 0.6, "life": 1.7, "size": 0.8},
	"plumage":       {"tex": "feather",   "col": "accent",  "n": 11, "spd": 120.0, "grav": 45.0,  "spin": 1.4, "life": 1.6, "size": 0.9},
	# --- the ten of 2026-08-27 -----------------------------------------------
	"marble":        {"tex": "shard",     "col": "white",   "n": 12, "spd": 140.0, "grav": 220.0, "spin": 1.6, "life": 1.0, "size": 0.5},
	"noir":          {"tex": "sparkle",   "col": "F2E8D5",  "n": 10, "spd": 120.0, "grav": 0.0,   "spin": 0.5, "life": 0.9, "size": 0.5,  "ring": true},
	"mono":          {"tex": "dot",       "col": "E63B2E",  "n": 6,  "spd": 90.0,  "grav": 0.0,   "spin": 0.0, "life": 0.8, "size": 0.35, "ring": true},
	"wash":          {"tex": "round",     "col": "accent2", "n": 8,  "spd": 60.0,  "grav": 20.0,  "spin": 0.0, "life": 1.8, "size": 1.0,  "alpha": 0.35, "ring": true},
	"bismuth":       {"tex": "square",    "col": "hue",     "n": 14, "spd": 150.0, "grav": 0.0,   "spin": 1.2, "life": 1.0, "size": 0.5,  "ring": true},
	"altitude":      {"tex": "cloud",     "col": "white",   "n": 8,  "spd": 80.0,  "grav": -25.0, "spin": 0.2, "life": 1.8, "size": 0.9,  "alpha": 0.85},
	"lagoon":        {"tex": "bubble",    "col": "white",   "n": 12, "spd": 120.0, "grav": 120.0, "spin": 0.0, "life": 1.0, "size": 0.45, "ring": true},
	"savanna":       {"tex": "dot",       "col": "E8B07A",  "n": 16, "spd": 120.0, "grav": -40.0, "spin": 0.0, "life": 1.4, "size": 0.5},
	"redwood":       {"tex": "dot",       "col": "F2C46B",  "n": 14, "spd": 80.0,  "grav": -60.0, "spin": 0.0, "life": 1.8, "size": 0.4},
	"flecks":        {"tex": "dot",       "col": "accent",  "n": 12, "spd": 100.0, "grav": 30.0,  "spin": 0.0, "life": 1.4, "size": 0.4,  "ring": true},
	"code":          {"tex": "square",    "col": "3CFF6A",  "n": 14, "spd": 150.0, "grav": 200.0, "spin": 0.0, "life": 0.9, "size": 0.4},
	# --- playful -------------------------------------------------------------
	"confetti":      {"tex": "square",    "col": "hue",     "n": 18, "spd": 190.0, "grav": 300.0, "spin": 3.0, "life": 1.1, "size": 0.7},
	"arcade_pop":    {"tex": "square",    "col": "hue",     "n": 18, "spd": 200.0, "grav": 380.0, "spin": 0.0, "life": 0.9, "size": 0.6},
	"candy":         {"tex": "dot",       "col": "hue",     "n": 18, "spd": 170.0, "grav": 300.0, "spin": 0.0, "life": 1.0, "size": 0.7},
	"balloons":      {"tex": "balloon",   "col": "hue",     "n": 8,  "spd": 90.0,  "grav": -140.0,"spin": 0.5, "life": 1.8, "size": 0.9},
	"hearts":        {"tex": "heart",     "col": "accent",  "n": 12, "spd": 120.0, "grav": -60.0, "spin": 1.0, "life": 1.5, "size": 0.7},
	"fireworks":     {"tex": "sparkle",   "col": "hue",     "n": 20, "spd": 220.0, "grav": 120.0, "spin": 1.0, "life": 1.1, "size": 0.6},
	"anime":         {"tex": "sparkle",   "col": "white",   "n": 14, "spd": 130.0, "grav": -30.0, "spin": 0.6, "life": 1.3, "size": 0.7},
	"motes":         {"tex": "dot",       "col": "accent",  "n": 12, "spd": 110.0, "grav": 0.0,   "spin": 0.0, "life": 1.3, "size": 0.5},
}
## The recipe for a motif with no entry of its own — including any theme authored
## after this table. Never a dead end, never a crash.
const _REACT_FALLBACK := {"tex": "dot", "col": "accent", "n": 12, "spd": 130.0,
	"grav": 0.0, "spin": 0.0, "life": 1.2, "size": 0.5}
## Concurrent reaction emitters. Eight merges can land on one frame.
const _REACT_LIVE := 6

## The world's answer to one merge, in the theme's own material.
func _react_merge(motif: String, at: Vector2, strength: float) -> void:
	var r: Dictionary = _REACT.get(motif, _REACT_FALLBACK)
	_react_burst(at, r, strength)
	if bool(r.get("ring", false)):
		_react_ring(at, _react_col(String(r["col"])), strength)

## ...and to a swipe: the same material blown across the frame the way the board
## just moved. One emitter, streaming from the edge the move came FROM.
func _react_swipe(motif: String, dir: Vector2) -> void:
	if dir == Vector2.ZERO or _react_live() >= _REACT_LIVE:
		return
	var r: Dictionary = _REACT.get(motif, _REACT_FALLBACK)
	var ps := _react_particles(r, 0.9)
	ps.amount = maxi(int(float(r.get("n", 12)) * 0.55 * _particle_scale()), 3)
	ps.lifetime = 1.1
	ps.direction = dir
	ps.spread = 22.0
	ps.gravity = Vector2(dir.x, dir.y) * 40.0
	ps.initial_velocity_min = float(r.get("spd", 130.0)) * 1.6
	ps.initial_velocity_max = float(r.get("spd", 130.0)) * 2.8
	# Emit from a strip along the edge the swipe came from, so the gust crosses
	# the whole frame rather than puffing out of the middle of it.
	ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	ps.position = _vp * 0.5 - Vector2(dir.x, dir.y) * _vp * 0.55
	ps.emission_rect_extents = Vector2(
		lerpf(_vp.x * 0.5, _vp.x * 0.04, absf(dir.x)),
		lerpf(_vp.y * 0.5, _vp.y * 0.04, absf(dir.y)))
	_react_add(ps)

## A celebration: the room goes off at once.
func _react_celebrate(motif: String) -> void:
	for i in 3:
		var at := Vector2(_vp.x * randf_range(0.15, 0.85), _vp.y * randf_range(0.18, 0.82))
		_react_merge(motif, at, 1.4)

## One outward burst of the theme's own material.
func _react_burst(at: Vector2, r: Dictionary, strength: float) -> void:
	if _react_live() >= _REACT_LIVE:
		return                        # a multi-merge frame degrades, never piles up
	var ps := _react_particles(r, strength)
	ps.position = at
	ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	ps.emission_sphere_radius = maxf(minf(_vp.x, _vp.y) * 0.012, 3.0)
	_react_add(ps)

## The shared body of every reaction emitter: one-shot, explosive, self-freeing.
func _react_particles(r: Dictionary, strength: float) -> CPUParticles2D:
	var ps := CPUParticles2D.new()
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.randomness = 0.6
	ps.texture = _react_tex(String(r.get("tex", "dot")))
	ps.amount = maxi(int(float(r.get("n", 12)) * strength * _particle_scale()), 3)
	ps.lifetime = float(r.get("life", 1.2))
	ps.direction = Vector2(0, -1)
	ps.spread = 180.0
	ps.gravity = Vector2(0, float(r.get("grav", 0.0)))
	var spd: float = float(r.get("spd", 130.0)) * lerpf(0.85, 1.35, clampf(strength - 0.6, 0.0, 1.0))
	ps.initial_velocity_min = spd * 0.35
	ps.initial_velocity_max = spd
	var sz: float = float(r.get("size", 0.5))
	ps.scale_amount_min = sz * 0.55
	ps.scale_amount_max = sz * 1.5
	var spin: float = float(r.get("spin", 0.0))
	if spin > 0.0:
		ps.angle_min = -180.0
		ps.angle_max = 180.0
		ps.angular_velocity_min = -spin * 90.0
		ps.angular_velocity_max = spin * 90.0
	var col_id := String(r.get("col", "accent"))
	var a: float = float(r.get("alpha", 0.95))
	if col_id == "hue":
		ps.color_initial_ramp = _rainbow()
		ps.color_ramp = _alpha_ramp(Color(1, 1, 1), a, false)
	else:
		ps.color_ramp = _alpha_ramp(_react_col(col_id), a, false)
	return ps

## Adds a reaction emitter and frees it once its field has died.
func _react_add(ps: CPUParticles2D) -> void:
	ps.emitting = true
	add_child(ps)
	var t := ps.create_tween()
	t.tween_interval(ps.lifetime + 0.25)
	t.tween_callback(ps.queue_free)

## How many reaction emitters are alive right now.
func _react_live() -> int:
	var n := 0
	for c in get_children():
		if c is CPUParticles2D and (c as CPUParticles2D).one_shot:
			n += 1
	return n

## An expanding ripple, for the worlds that answer with a surface rather than
## with debris: water, sand, plasma, glass.
func _react_ring(at: Vector2, col: Color, strength: float) -> void:
	var ring := TextureRect.new()
	ring.texture = _ring()
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.stretch_mode = TextureRect.STRETCH_SCALE
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d: float = minf(_vp.x, _vp.y) * 0.10
	ring.size = Vector2(d, d)
	ring.pivot_offset = ring.size * 0.5
	ring.position = at - ring.size * 0.5
	ring.modulate = Color(col.r, col.g, col.b, 0.5)
	add_child(ring)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2.ONE * (2.6 + strength), 0.55) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(ring, "modulate:a", 0.0, 0.55)
	tw.chain().tween_callback(ring.queue_free)

## Recipe texture ids -> the shared sprite bakes.
func _react_tex(id: String) -> Texture2D:
	match id:
		"snowflake": return _snowflake()
		"petal":     return _petal()
		"leaf":      return _leaf()
		"gem":       return _gem()
		"shard":     return _shard()
		"coin":      return _coin()
		"ingot":     return _ingot()
		"bubble":    return _bubble()
		"balloon":   return _balloon()
		"heart":     return _heart()
		"lantern":   return _lantern()
		"sparkle":   return _sparkle()
		"orb":       return _orb()
		"square":    return _square()
		"round":     return _round()
		"hex":       return _hexcell()
		"butterfly": return _butterfly()
		"feather":   return _feather()
		"cloud":     return _cumulus()
		_:           return _dot()

## Recipe colour ids -> a live colour. Anything else is read as an HTML literal,
## so a recipe can name a MATERIAL the palette does not carry (a maple leaf is
## not the theme accent, and Autumn's accent is not orange).
func _react_col(id: String) -> Color:
	match id:
		"accent":  return _pc("accent")
		"accent2": return _pc("accent2")
		"gold":    return _pc("gold")
		"white":   return _white(1.0)
		"board":
			var luxe: Color = ThemeManager.board_accent_for(_pal())
			return _pc("accent") if luxe.a <= 0.0 else Color(luxe.r, luxe.g, luxe.b)
		_:
			return Color(id) if Color.html_is_valid(id) else _pc("accent")

# --- Background layers ---------------------------------------------------------
func _build_wash(cols: Array = [], alpha: float = 0.15) -> void:
	# Two big, soft, slowly wandering colour blobs — quiet depth under the motif.
	if cols.is_empty():
		cols = [_pc("accent"), _pc("gold")]
	for i: int in [0, 1]:
		var blob := TextureRect.new()
		blob.texture = _round()
		blob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		blob.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var d: float = minf(_vp.x, _vp.y) * 1.3
		blob.size = Vector2(d, d)
		var col: Color = cols[i % cols.size()]
		# Subtle: the per-theme motif (snow/rain/embers/…) is the identity, not this.
		blob.modulate = Color(col.r, col.g, col.b, alpha)
		var home := Vector2(lerpf(-d * 0.2, _vp.x - d * 0.8, float(i)),
			lerpf(_vp.y * 0.08, _vp.y * 0.5, float(i)))
		blob.position = home
		add_child(blob)
		var off := Vector2(_vp.x * 0.16, _vp.y * 0.1)
		var tw := blob.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(blob, "position", home + off, 12.0)
		tw.tween_property(blob, "position", home - off * 0.6, 13.0)
		tw.tween_property(blob, "position", home, 11.0)

func _build_aurora() -> void:
	var p := _pal()
	if _aurora_mat == null:
		if _aurora_shader == null:
			_aurora_shader = Shader.new()
			_aurora_shader.code = _AURORA_CODE
		_aurora_mat = ShaderMaterial.new()
		_aurora_mat.shader = _aurora_shader
	_aurora_mat.set_shader_parameter("base", Color(p["bg0"]))
	_aurora_mat.set_shader_parameter("col_low", _saturate(p["accent"]))     # green hem
	_aurora_mat.set_shader_parameter("col_mid", Color(0.20, 0.85, 0.95))    # teal
	_aurora_mat.set_shader_parameter("col_high", Color(0.95, 0.25, 0.80))   # magenta tips
	_aurora_mat.set_shader_parameter("intensity", 1.0)
	_aurora_mat.set_shader_parameter("speed", 0.6)
	# The aurora's noise field is the most expensive fragment shader in the game —
	# hosted at reduced resolution (visually identical for soft curtains).
	_shader_layer(_aurora_mat)
	_m_stars()   # a starfield over the flowing aurora reads beautifully
	_aurora_curtains()
	_aurora_shore()

## Discrete curtain rays hanging over the shader field. The shader gives the
## slow flowing wash; these give the vertical STRUCTURE a real aurora has —
## bright ribs with dark gaps between them, each breathing on its own clock and
## drifting sideways at its own pace.
func _aurora_curtains() -> void:
	var cols: Array = [_saturate(_pc("accent")), Color(0.25, 0.90, 0.95),
		Color(0.60, 0.45, 1.00), Color(0.95, 0.35, 0.80)]
	var n := 9
	for i in n:
		var ray := TextureRect.new()
		ray.texture = _ray()
		ray.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ray.stretch_mode = TextureRect.STRETCH_SCALE
		ray.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.10, 0.22)
		var h: float = _vp.y * randf_range(0.42, 0.72)
		ray.size = Vector2(w, h)
		ray.pivot_offset = Vector2(w * 0.5, 0.0)
		ray.rotation = deg_to_rad(randf_range(-9.0, 9.0))
		var x: float = _vp.x * (float(i) + randf_range(0.1, 0.9)) / float(n)
		ray.position = Vector2(x - w * 0.5, -_vp.y * randf_range(0.02, 0.12))
		var c: Color = cols[i % cols.size()]
		var peak: float = randf_range(0.16, 0.30)
		ray.modulate = Color(c.r, c.g, c.b, peak * 0.35)
		add_child(ray)
		var tw := ray.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(randf_range(0.0, 2.5))
		tw.tween_property(ray, "modulate:a", peak, randf_range(3.0, 5.5))
		tw.tween_property(ray, "modulate:a", peak * 0.25, randf_range(3.5, 6.0))
		# The curtain also slides slowly along its own length of sky.
		var slide := ray.create_tween().set_loops()
		slide.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		var dx: float = _vp.x * randf_range(0.03, 0.09)
		slide.tween_property(ray, "position:x", ray.position.x + dx, randf_range(9.0, 14.0))
		slide.tween_property(ray, "position:x", ray.position.x, randf_range(9.0, 14.0))

## The shore under the lights: a far island ridge with a village at its foot —
## a handful of warm windows and one slow lighthouse — and the still water in
## front of it holding the aurora's reflection. It sits in the bottom band, the
## strip the board never covers, so the sky above stays entirely sky.
func _aurora_shore() -> void:
	var green: Color = _saturate(_pc("accent"))
	var water_y: float = _vp.y * 0.885
	# The water: a dark band with a green shimmer laid over it.
	var water := ColorRect.new()
	water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	water.color = Color(0.02, 0.05, 0.09, 0.75)
	water.size = Vector2(_vp.x, _vp.y - water_y)
	water.position = Vector2(0.0, water_y)
	add_child(water)
	for i in 3:
		var sheen := TextureRect.new()
		sheen.texture = _round()
		sheen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sheen.stretch_mode = TextureRect.STRETCH_SCALE
		sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sheen.size = Vector2(_vp.x * randf_range(0.5, 0.9), (_vp.y - water_y) * 0.7)
		sheen.position = Vector2(_vp.x * randf_range(0.0, 0.5), water_y + (_vp.y - water_y) * 0.15)
		sheen.modulate = Color(green.r, green.g, green.b, 0.06)
		add_child(sheen)
		var wt := sheen.create_tween().set_loops()
		wt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		wt.tween_property(sheen, "modulate:a", 0.16, randf_range(3.0, 5.0))
		wt.tween_property(sheen, "modulate:a", 0.05, randf_range(3.5, 5.5))
	# The island ridge, sitting on the waterline.
	var ridge := TextureRect.new()
	ridge.texture = _shaped("aurora_ridge", 176, 56, _fn_ridge)
	ridge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ridge.stretch_mode = TextureRect.STRETCH_SCALE
	ridge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rw: float = _vp.x * 1.05
	var rh: float = rw * (90.0 / 280.0)
	ridge.size = Vector2(rw, rh)
	ridge.position = Vector2(_vp.x * 0.5 - rw * 0.5, water_y - rh)
	ridge.modulate = Color(0.03, 0.07, 0.10, 0.97)
	add_child(ridge)
	# The village: warm windows scattered along the shoreline, each on its own
	# slow flicker, and their reflections smeared on the water below.
	var wins := [0.18, 0.23, 0.27, 0.30, 0.36, 0.62, 0.66, 0.70, 0.75, 0.80]
	for wx_v in wins:
		var wx: float = wx_v
		var win := TextureRect.new()
		win.texture = _dot()
		win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		win.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = _vp.x * randf_range(0.008, 0.014)
		win.size = Vector2(d, d)
		var wy: float = water_y - rh * randf_range(0.06, 0.22)
		win.position = Vector2(_vp.x * wx, wy) - win.size * 0.5
		win.modulate = Color(1.0, 0.80, 0.42, 0.85)
		add_child(win)
		var tw := win.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(randf_range(0.0, 2.0))
		tw.tween_property(win, "modulate:a", 0.35, randf_range(1.6, 3.2))
		tw.tween_property(win, "modulate:a", 0.9, randf_range(1.6, 3.2))
		# Its reflection: a soft smear directly below, on the water.
		var refl := TextureRect.new()
		refl.texture = _dot()
		refl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		refl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		refl.size = Vector2(d * 0.8, d * 3.4)
		refl.position = Vector2(_vp.x * wx - refl.size.x * 0.5, water_y + d * 0.4)
		refl.modulate = Color(1.0, 0.80, 0.42, 0.22)
		add_child(refl)
	# The lighthouse on the point. It has to be BIG: it is the only man-made
	# vertical on the horizon, and a thin bar reads as a fence post.
	var lx: float = _vp.x * 0.855
	var lh: float = _vp.y * 0.185
	var ly: float = water_y - lh
	_landmark(_shaped("aurora_light", 56, 144, _fn_lighthouse), 0.855, 0.185,
		90.0 / 230.0, Color(0.90, 0.93, 0.97), 0.95, water_y / _vp.y)
	# The lamp itself, in the lantern room at the top.
	var lamp := TextureRect.new()
	lamp.texture = _dot()
	lamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ld: float = lh * 0.22
	lamp.size = Vector2(ld, ld)
	lamp.position = Vector2(lx - ld * 0.5, ly + lh * 0.10 - ld * 0.5)
	lamp.modulate = Color(1.0, 0.94, 0.72, 0.95)
	add_child(lamp)
	var lampt := lamp.create_tween().set_loops()
	lampt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	lampt.tween_property(lamp, "modulate:a", 1.0, 1.1)
	lampt.tween_property(lamp, "modulate:a", 0.55, 1.3)
	var beam_pivot := Control.new()
	beam_pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beam_pivot.position = Vector2(lx, ly + lh * 0.10)
	add_child(beam_pivot)
	var beam := TextureRect.new()
	beam.texture = _round()
	beam.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	beam.stretch_mode = TextureRect.STRETCH_SCALE
	beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beam.size = Vector2(_vp.x * 0.70, _vp.y * 0.055)
	beam.pivot_offset = Vector2(0.0, beam.size.y * 0.5)
	beam.position = Vector2(0.0, -beam.size.y * 0.5)
	beam.modulate = Color(1.0, 0.95, 0.78, 0.10)
	beam_pivot.add_child(beam)
	var sweep := beam_pivot.create_tween().set_loops()
	sweep.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	sweep.tween_property(beam_pivot, "rotation", deg_to_rad(-205.0), 5.5)
	sweep.tween_property(beam_pivot, "rotation", deg_to_rad(-160.0), 5.5)

# --- Motifs -------------------------------------------------------------------
## One depth layer of believable rain: long thin drops (dedicated raindrop
## texture), aligned to their fall, accelerating under gravity, at this layer's
## own speed/size/slant band. Stack three for near/mid/far depth.
func _rain_layer(col: Color, alpha: float, amount: int, vmin: float, vmax: float,
		smin: float, smax: float, slant: float) -> void:
	_emit({"from": "top", "tex": _raindrop(), "color": col, "alpha": alpha,
		"amount": amount, "lifetime": 2.6, "dir": Vector3(slant, 1, 0), "spread": 2.0,
		"vmin": vmin, "vmax": vmax, "smin": smin, "smax": smax,
		"gravity": 420.0, "align": true})

func _m_snow() -> void:
	# Christmas Eve, somewhere north.
	#
	# The world is BUILT back-to-front because a BoardFx child list *is* the
	# paint order: night sky, two ranks of snow peaks, the far half of the
	# snowfall, the village on its snow line, then the near half of the snowfall
	# and the wind. Splitting the flake stack around the village is the whole
	# trick — the far grains and mid crystals fall BEHIND the buildings and the
	# near crystals and driven snow fall in FRONT of them, which is what puts
	# the houses inside the weather instead of behind a wall of it.
	#
	# This replaced a daylit expedition camp (an igloo and a snowman on a pale
	# blue field). The palette moved with it: Arctic is a dark theme now, so the
	# scene reads by LIGHT — lit windows, a lantern, a fir strung with lights,
	# moonlight on snow — rather than by cold shadow on white.
	# A rebuild frees every node the reaction handles point at, so they are
	# dropped BEFORE anything new is built rather than left dangling.
	_snow_lights.clear()
	_snow_smoke = null
	_snow_sleigh = null
	_snow_flaring = false
	_winter_sky()
	_snow_ranges()
	_snowfall(false)
	_winter_village()
	_snowfall(true)
	_top_garland()

## Night over the village: stars biased to the top of the sky, the moon low
## enough to clear the score panel, its halo, one bright four-point star over
## the village, and a column of moonlight down the air. Nothing here moves
## sideways — a drifting emitter would put stars inside the mountains.
func _winter_sky() -> void:
	var star := Color(0.88, 0.94, 1.0)
	for i in 34:
		var d := TextureRect.new()
		d.texture = _dot()
		d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		d.stretch_mode = TextureRect.STRETCH_SCALE
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Squared sample: most stars land high, and the ones near the horizon
		# come out smaller and dimmer because haze eats them.
		var t := randf()
		var deep: float = t * t
		var sz: float = _vp.x * randf_range(0.007, 0.019) * lerpf(1.0, 0.62, deep)
		d.size = Vector2(sz, sz)
		d.position = Vector2(randf() * _vp.x - sz * 0.5,
			_vp.y * lerpf(0.015, 0.60, deep) - sz * 0.5)
		var a: float = randf_range(0.30, 0.85) * lerpf(1.0, 0.45, deep)
		d.modulate = Color(star.r, star.g, star.b, a)
		add_child(d)
		# The faintest stars never twinkle: at that alpha the blink is invisible
		# anyway, and skipping it drops a third of the loops this sky runs
		# behind every menu.
		if a < 0.42:
			continue
		var tw := d.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(d, "modulate:a", a * 0.25, randf_range(1.3, 3.2))
		tw.tween_property(d, "modulate:a", a, randf_range(1.3, 3.2))
	var mc := Vector2(_vp.x * 0.765, _vp.y * 0.238)
	var md: float = _vp.x * 0.150
	var halo := TextureRect.new()
	halo.texture = _round()
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_SCALE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.size = Vector2(md * 3.2, md * 3.2)
	halo.position = mc - halo.size * 0.5
	halo.modulate = Color(0.68, 0.82, 1.0, 0.12)
	add_child(halo)
	var ht := halo.create_tween().set_loops()
	ht.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	ht.tween_property(halo, "modulate:a", 0.19, 4.5)
	ht.tween_property(halo, "modulate:a", 0.10, 5.0)
	# A FULL moon, in two passes. _moon() alone is a sphere lit from the upper
	# left, so on its own it reads as a grey rock hanging in the sky — which is
	# wrong here twice over, because tonight the moon IS the light source and
	# everything below it is lit from its side. So: a clean bright disc, with the
	# cratered bake laid over it at low alpha purely for the maria.
	var disc := TextureRect.new()
	disc.texture = _disc()
	disc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	disc.stretch_mode = TextureRect.STRETCH_SCALE
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.size = Vector2(md, md)
	disc.position = mc - disc.size * 0.5
	# Over-driven past 1.0 on purpose: _fn_disc was authored as a SUN for a light
	# sky and its body tops out at 0.78 grey, which under a plain white tint is
	# exactly the dull pebble this pass replaced.
	disc.modulate = Color(1.85, 1.88, 1.92, 1.0)
	add_child(disc)
	# A tight bloom, so the disc sits IN the sky instead of on top of it.
	var bloom := TextureRect.new()
	bloom.texture = _dot()
	bloom.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bloom.stretch_mode = TextureRect.STRETCH_SCALE
	bloom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bloom.size = Vector2(md * 1.7, md * 1.7)
	bloom.position = mc - bloom.size * 0.5
	bloom.modulate = Color(0.86, 0.93, 1.0, 0.30)
	add_child(bloom)
	var moon := TextureRect.new()
	moon.texture = _moon()
	moon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	moon.stretch_mode = TextureRect.STRETCH_SCALE
	moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	moon.size = Vector2(md, md)
	moon.position = mc - moon.size * 0.5
	moon.modulate = Color(0.84, 0.90, 1.0, 0.13)
	add_child(moon)
	# The star over the village, turning very slowly so its arms sweep.
	var flare := TextureRect.new()
	flare.texture = _sparkle()
	flare.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flare.stretch_mode = TextureRect.STRETCH_SCALE
	flare.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fw: float = _vp.x * 0.115
	flare.size = Vector2(fw, fw)
	flare.pivot_offset = flare.size * 0.5
	flare.position = Vector2(_vp.x * 0.205 - fw * 0.5, _vp.y * 0.115 - fw * 0.5)
	flare.modulate = Color(1.0, 0.96, 0.84, 0.85)
	add_child(flare)
	var ft := flare.create_tween().set_loops()
	ft.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	ft.tween_property(flare, "modulate:a", 0.55, 2.4)
	ft.tween_property(flare, "modulate:a", 0.92, 2.8)
	var fr := flare.create_tween().set_loops()
	fr.tween_property(flare, "rotation", TAU, 60.0).from(0.0)
	# Moonlight standing in the air. Wide, very faint, and breathing — this is
	# what stops a night sky reading as flat black.
	var beam := TextureRect.new()
	beam.texture = _round()
	beam.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	beam.stretch_mode = TextureRect.STRETCH_SCALE
	beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beam.size = Vector2(_vp.x * 0.80, _vp.y * 1.15)
	beam.position = Vector2(_vp.x * 0.70 - beam.size.x * 0.5, -_vp.y * 0.12)
	beam.modulate = Color(0.62, 0.80, 1.0, 0.06)
	add_child(beam)
	var bt := beam.create_tween().set_loops()
	bt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	bt.tween_property(beam, "modulate:a", 0.12, 5.4)
	bt.tween_property(beam, "modulate:a", 0.05, 6.2)
	_meteor(randf_range(3.0, 9.0))
	_meteor(randf_range(11.0, 20.0))
	_sleigh_setup()

## Two ranks of snow peaks between the sky and the village. ONE bake drawn
## twice: the far rank is wider, taller, washed toward the sky by haze and
## FLIPPED, so the two ridge lines never repeat a silhouette; the near rank is
## smaller, darker in the rock and brighter in the snow, and its foot is buried
## by the treeline.
##
## The draw aspect matters more than the crest maths here: the bake is stretched
## roughly three times wider than tall on screen, so a crest that looks alpine
## in uv space arrives as rolling hills. _peaks_tex is authored steep to survive
## that, which is why its bumps are so narrow.
func _snow_ranges() -> void:
	var tex := _peaks_tex()
	var haze := Color(0.36, 0.48, 0.70)
	var near := Color(0.82, 0.90, 1.0)
	# [x centre, width, height, base y, haze, alpha, flipped] — all fractions.
	# The peaks deliberately reach ABOVE the board's bottom edge: the board is
	# frosted glass, so the tops read through it and the range gains the depth
	# it cannot get from the 12% of screen height left clear underneath.
	for e_v in [[0.44, 1.40, 0.265, 0.858, 0.66, 0.72, true],
			[0.58, 1.02, 0.190, 0.880, 0.14, 1.00, false]]:
		var e: Array = e_v
		var w: float = _vp.x * float(e[1])
		var h: float = _vp.y * float(e[2])
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.flip_h = bool(e[6])
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.size = Vector2(w, h)
		r.position = Vector2(_vp.x * float(e[0]) - w * 0.5, _vp.y * float(e[3]) - h)
		var c := near.lerp(haze, float(e[4]))
		r.modulate = Color(c.r, c.g, c.b, float(e[5]))
		add_child(r)

## The snowfall, in two halves so the village can stand between them. `near`
## picks the front half. Every layer shares one slant because one wind blows
## across the whole world; the near layers just fall faster and swirl harder.
func _snowfall(near: bool) -> void:
	if not near:
		# Pin-sized grains far off in the murk, then the flurry, then the first
		# layer with real six-armed structure in it.
		_emit({"from": "all", "tex": _dot(), "color": _white(0.85), "alpha": 0.30,
			"amount": 90, "lifetime": 16.0, "dir": Vector3(0.34, 1, 0), "spread": 8.0,
			"vmin": 14.0, "vmax": 34.0, "smin": 0.16, "smax": 0.4, "turb": 0.5})
		_emit({"from": "all", "tex": _dot(), "color": _white(0.92), "alpha": 0.50,
			"amount": 60, "lifetime": 13.0, "dir": Vector3(0.40, 1, 0), "spread": 10.0,
			"vmin": 30.0, "vmax": 70.0, "smin": 0.5, "smax": 1.2, "turb": 0.7})
		_emit({"from": "all", "tex": _snowflake(), "color": _white(1.0), "alpha": 0.70,
			"amount": 24, "lifetime": 12.0, "dir": Vector3(0.44, 1, 0), "spread": 12.0,
			"vmin": 40.0, "vmax": 92.0, "smin": 0.7, "smax": 1.4, "spin": 0.5,
			"turb": 0.9})
		return
	_emit({"from": "all", "tex": _snowflake(), "color": _white(1.0), "alpha": 0.78,
		"amount": 10, "lifetime": 9.0, "dir": Vector3(0.52, 1, 0), "spread": 14.0,
		"vmin": 70.0, "vmax": 130.0, "smin": 1.3, "smax": 2.1, "spin": 0.8,
		"orbit": 0.015})
	_wind_gusts()

## The wind itself, which is the part the old daylit camp had no answer for.
## Two fields nothing else shares: driven snow crossing almost flat, and low
## veils of spindrift lifting off the drifts. Both ride a gust tween, so the
## wind arrives, blows and drops away again — the difference between weather
## and a screensaver.
func _wind_gusts() -> void:
	_gust(_emit({"from": "all", "tex": _dot(), "color": _white(1.0), "alpha": 0.30,
		"amount": 34, "lifetime": 3.2, "dir": Vector3(1, 0.28, 0), "spread": 5.0,
		"vmin": 260.0, "vmax": 470.0, "smin": 0.30, "smax": 0.85}), 0.20, 1.0, 3.4, 5.2)
	_gust(_emit({"from": "bottom", "tex": _round(), "color": _white(1.0), "alpha": 0.09,
		"amount": 6, "lifetime": 7.0, "dir": Vector3(1, -0.30, 0), "spread": 9.0,
		"vmin": 90.0, "vmax": 185.0, "smin": 3.5, "smax": 8.0,
		"turb": 0.4}), 0.28, 1.0, 4.4, 6.2)

## Rides one layer's brightness up and down, so a wind field pulses instead of
## running at one flat rate forever.
func _gust(node: CanvasItem, lo: float, hi: float, up: float, down: float) -> void:
	node.modulate = Color(1, 1, 1, lo)
	var tw := node.create_tween().set_loops()
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "modulate:a", hi, up)
	tw.tween_property(node, "modulate:a", lo, down)

## The village on its snow line. Everything measures from ONE ground y — the
## buildings' feet, the treeline, the drifts — so the ground reads as ground.
## It sits at 0.872 because that is the last clear band on the gameplay screen:
## the tray of Undo / Redo / Rewind owns everything below it, and a village whose
## feet are behind a button is a village standing in a wall.
func _winter_village() -> void:
	var ground: float = _vp.y * 0.872
	# The snowfield: one very soft sheet of moonlit snow lying under the whole
	# village, wider than the screen so it never shows an edge.
	var field := TextureRect.new()
	field.texture = _round()
	field.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	field.stretch_mode = TextureRect.STRETCH_SCALE
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.size = Vector2(_vp.x * 3.0, _vp.y * 0.44)
	field.position = Vector2((_vp.x - field.size.x) * 0.5,
		ground + _vp.y * 0.10 - field.size.y * 0.5)
	field.modulate = Color(0.54, 0.72, 0.96, 0.26)
	add_child(field)
	# A treeline running off both sides of the village, receding into the dark.
	var fir_tex := _shaped("arctic_fir", 44, 94, _fn_fir)
	for e_v in [[0.015, 0.150, 0.55], [0.10, 0.115, 0.30], [0.175, 0.085, 0.14],
			[0.395, 0.075, 0.10], [0.545, 0.100, 0.22], [0.72, 0.090, 0.18],
			[0.925, 0.135, 0.46], [0.985, 0.105, 0.28]]:
		var e: Array = e_v
		var fh: float = _vp.y * float(e[1])
		var fw: float = fh * (70.0 / 150.0)
		var fir := TextureRect.new()
		fir.texture = fir_tex
		fir.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fir.stretch_mode = TextureRect.STRETCH_SCALE
		fir.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fir.size = Vector2(fw, fh)
		fir.position = Vector2(_vp.x * float(e[0]) - fw * 0.5, ground - fh)
		# Night firs: the bake's own green goes almost black and only the snow
		# it carries keeps any light. Nearer trees stand a shade further out of
		# the dark than the ones behind them.
		var d: float = float(e[2])
		fir.modulate = Color(lerpf(0.20, 0.42, d), lerpf(0.30, 0.54, d),
			lerpf(0.36, 0.62, d), 0.95)
		add_child(fir)
	# A second cabin further back and further off, so the place reads as a
	# village rather than as one house alone on a mountain.
	# Five buildings and a church, smallest and dimmest furthest off. The ones at
	# the edges stand a little higher on the slope, which is the cheapest depth
	# cue there is and the reason the row does not read as a shelf.
	_lodge(Vector2(_vp.x * 0.012, ground - _vp.y * 0.016), _vp.x * 0.13, true)
	_lodge(Vector2(_vp.x * 0.100, ground - _vp.y * 0.010), _vp.x * 0.17, true)
	_steeple(Vector2(_vp.x * 0.470, ground - _vp.y * 0.004), _vp.y * 0.128)
	_lodge(Vector2(_vp.x * 0.985, ground - _vp.y * 0.012), _vp.x * 0.15, true)
	_lodge(Vector2(_vp.x * 0.315, ground), _vp.x * 0.29, false)
	_yule_fir(Vector2(_vp.x * 0.605, ground), _vp.y * 0.112)
	_snowman_figure(Vector2(_vp.x * 0.855, ground + _vp.y * 0.008), _vp.x * 0.16)
	# The drifts, laid down LAST so the village stands in the snow rather than
	# on top of it.
	for i in 4:
		var drift := TextureRect.new()
		drift.texture = _round()
		drift.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drift.stretch_mode = TextureRect.STRETCH_SCALE
		drift.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.7, 1.3)
		var h: float = _vp.y * randf_range(0.05, 0.09)
		drift.size = Vector2(w, h)
		# Only the crown of each blob clears the snow line. Centred ON it, a
		# drift is a pale wash straight across the front of the houses.
		drift.position = Vector2(_vp.x * (0.06 + 0.30 * float(i)) - w * 0.5,
			ground - h * randf_range(0.16, 0.30))
		drift.modulate = Color(0.72, 0.86, 1.0, 0.22)
		add_child(drift)
	_frozen_creek(ground)

## The house at the back of the village: log walls under a deep load of snow,
## two lit windows, a wreath on the door, a string of lights along the eaves and
## a chimney with the fire still going.
##
## The bake is 180x171 and the snow line it stands on is at sy = 0.78 in its own
## screen-space metric, NOT at the bake's bottom edge — so the house is placed by
## that line or it floats. Every ornament hung on it (window glow, smoke, lights)
## is positioned through the same two conversions, which is why they are lambdas
## rather than a pile of magic numbers.
func _lodge(base: Vector2, w: float, far: bool) -> void:
	const AR := 0.95		# bake 180x171, drawn at h = 0.95 * w
	const FOOT := 0.78		# the snow line, in the bake's sy
	var h: float = w * AR
	var pos := Vector2(base.x - w * 0.5, base.y - h * (FOOT / AR + 1.0) * 0.5)
	# uv.x -> screen x, and the bake's screen-space y -> screen y.
	var px := func(ux: float) -> float: return pos.x + w * (ux + 1.0) * 0.5
	var py := func(sy: float) -> float: return pos.y + h * (sy / AR + 1.0) * 0.5
	var warm := Color(1.0, 0.74, 0.34)
	# Aerial perspective, the same wash the far rank of peaks wears.
	var tint := Color(0.66, 0.78, 0.94, 1.0) if far else Color(1, 1, 1, 1)
	var lit: float = 0.55 if far else 1.0
	# The light the windows throw onto the snow, laid down first so the house
	# stands IN its own glow rather than beside it.
	var spill := TextureRect.new()
	spill.texture = _round()
	spill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spill.stretch_mode = TextureRect.STRETCH_SCALE
	spill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spill.size = Vector2(w * 2.1, h * 1.25)
	spill.position = Vector2(base.x - spill.size.x * 0.5, base.y - spill.size.y * 0.62)
	spill.modulate = Color(warm.r, warm.g, warm.b, 0.15 * lit)
	add_child(spill)
	var st := spill.create_tween().set_loops()
	st.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	st.tween_property(spill, "modulate:a", 0.26 * lit, 2.8)
	st.tween_property(spill, "modulate:a", 0.13 * lit, 3.2)
	var house := TextureRect.new()
	house.texture = _shaped("lodge", 180, 171, _fn_lodge)
	house.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	house.stretch_mode = TextureRect.STRETCH_SCALE
	house.mouse_filter = Control.MOUSE_FILTER_IGNORE
	house.size = Vector2(w, h)
	house.position = pos
	house.modulate = tint
	add_child(house)
	# Firelight in the two windows: the glass is baked warm, but the FLICKER has
	# to be a node, and a soft glow over each one is what makes the light look
	# like it is coming out of the house instead of painted on it.
	for wx_v in [-0.34, 0.34]:
		var wx: float = wx_v
		var glow := TextureRect.new()
		glow.texture = _dot()
		glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glow.stretch_mode = TextureRect.STRETCH_SCALE
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gw: float = w * 0.34
		glow.size = Vector2(gw, gw * 0.92)
		var cx: float = px.call(wx)
		var cy: float = py.call(0.24)
		glow.position = Vector2(cx - glow.size.x * 0.5, cy - glow.size.y * 0.5)
		glow.modulate = Color(1.0, 0.72, 0.30, 0.42)
		glow.set_meta("rest_a", 0.42)
		add_child(glow)
		# Only the near lodge answers merges: a flare on a cabin eight pixels
		# wide is a wasted tween.
		if not far:
			_snow_lights.append(glow)
		var gt := glow.create_tween().set_loops()
		gt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		gt.tween_property(glow, "modulate:a", 0.58, randf_range(1.1, 1.8))
		gt.tween_property(glow, "modulate:a", 0.34, randf_range(1.3, 2.1))
	if far:
		return
	# Lights along both eaves. Warm / red / green, blinking out of step, which
	# is the one detail that says Christmas from across the room.
	var bulbs := [Color(1.0, 0.82, 0.42), Color(0.96, 0.28, 0.28),
		Color(0.36, 0.92, 0.46), Color(1.0, 0.82, 0.42), Color(0.44, 0.78, 1.0)]
	for side_v in [-1.0, 1.0]:
		var side: float = side_v
		for i in 6:
			var t: float = (float(i) + 0.5) / 6.0
			var ux: float = side * lerpf(0.10, 0.88, t)
			# The eave line the string hangs from, plus a little sag.
			var sy: float = -0.64 + absf(ux) * 0.6444 + 0.055
			sy += 0.035 * sin(t * PI)
			var bulb := TextureRect.new()
			bulb.texture = _dot()
			bulb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			bulb.stretch_mode = TextureRect.STRETCH_SCALE
			bulb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var bw: float = w * 0.075
			bulb.size = Vector2(bw, bw)
			bulb.position = Vector2(px.call(ux) - bw * 0.5, py.call(sy) - bw * 0.5)
			var c: Color = bulbs[(i + int(side) + 5) % bulbs.size()]
			bulb.modulate = Color(c.r, c.g, c.b, 0.9)
			add_child(bulb)
			var bt := bulb.create_tween().set_loops()
			bt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			bt.tween_property(bulb, "modulate:a", 0.30, randf_range(0.9, 2.2))
			bt.tween_property(bulb, "modulate:a", 0.95, randf_range(0.9, 2.2))
	# Smoke off the chimney, leaning downwind with the snow.
	var smoke := CPUParticles2D.new()
	smoke.position = Vector2(px.call(0.385), py.call(-0.97))
	smoke.amount = maxi(int(20.0 * _particle_scale()), 5)
	smoke.lifetime = 6.0
	smoke.preprocess = 2.0
	smoke.texture = _round()
	smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = w * 0.02
	smoke.direction = Vector2(0.42, -1)
	smoke.spread = 16.0
	smoke.initial_velocity_min = 14.0
	smoke.initial_velocity_max = 34.0
	smoke.scale_amount_min = 0.4
	smoke.scale_amount_max = 1.8
	smoke.color_ramp = _alpha_ramp(Color(0.78, 0.84, 0.94), 0.44, false)
	smoke.emitting = true
	add_child(smoke)
	_snow_smoke = smoke
	_snow_smoke_v = smoke.initial_velocity_max

## The church, the tallest thing standing on the snow line. Same placement
## contract as the lodge and for the same reason: the bake's own snow line sits
## at sy = 1.55, not at its bottom edge, so the tower is placed by that or it
## floats above the drifts.
func _steeple(base: Vector2, h: float) -> void:
	const AR := 1.75        # bake 80x140
	const FOOT := 1.55
	var w: float = h / AR
	var pos := Vector2(base.x - w * 0.5, base.y - h * (FOOT / AR + 1.0) * 0.5)
	var spill := TextureRect.new()
	spill.texture = _round()
	spill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spill.stretch_mode = TextureRect.STRETCH_SCALE
	spill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spill.size = Vector2(w * 3.0, h * 0.55)
	spill.position = Vector2(base.x - spill.size.x * 0.5, base.y - spill.size.y * 0.62)
	spill.modulate = Color(1.0, 0.78, 0.38, 0.10)
	add_child(spill)
	var sp := spill.create_tween().set_loops()
	sp.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	sp.tween_property(spill, "modulate:a", 0.18, 3.4)
	sp.tween_property(spill, "modulate:a", 0.08, 3.9)
	var st := TextureRect.new()
	st.texture = _shaped("steeple", 80, 140, _fn_steeple)
	st.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	st.stretch_mode = TextureRect.STRETCH_SCALE
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	st.size = Vector2(w, h)
	st.position = pos
	add_child(st)

## The tree the village decorated: the treeline's own fir bake, grown, strung
## with lights and topped with a star. The lights are placed against the CONE,
## not scattered in its bounding box — a bauble floating off the silhouette
## reads as a bug, not as a decoration.
func _yule_fir(base: Vector2, h: float) -> void:
	var w: float = h * (70.0 / 150.0)
	var pos := Vector2(base.x - w * 0.5, base.y - h)
	# A warm pool of light under the tree, so the string reads as lighting the
	# snow rather than as dots on a dark shape.
	var pool := TextureRect.new()
	pool.texture = _round()
	pool.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pool.stretch_mode = TextureRect.STRETCH_SCALE
	pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pool.size = Vector2(w * 3.4, h * 0.95)
	pool.position = Vector2(base.x - pool.size.x * 0.5, base.y - pool.size.y * 0.66)
	pool.modulate = Color(1.0, 0.80, 0.44, 0.13)
	add_child(pool)
	var pt := pool.create_tween().set_loops()
	pt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	pt.tween_property(pool, "modulate:a", 0.22, 3.1)
	pt.tween_property(pool, "modulate:a", 0.11, 3.6)
	var tree := TextureRect.new()
	tree.texture = _shaped("arctic_fir", 44, 94, _fn_fir)
	tree.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tree.stretch_mode = TextureRect.STRETCH_SCALE
	tree.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tree.size = Vector2(w, h)
	tree.position = pos
	tree.modulate = Color(0.46, 0.62, 0.66, 1.0)
	add_child(tree)
	# The string. _fn_fir's cone runs from a point at uv.y = -0.98 out to a half
	# width of about 0.82 at the foot of the lowest bough, so the safe radius at
	# any height is that width taken in a bit — hence the 0.72.
	var bulbs := [Color(1.0, 0.84, 0.44), Color(0.98, 0.30, 0.30),
		Color(0.38, 0.94, 0.50), Color(0.46, 0.80, 1.0), Color(1.0, 0.62, 0.86)]
	for i in 15:
		var t: float = (float(i) + 0.6) / 15.0
		var uy: float = lerpf(-0.86, 0.60, t)
		var hw: float = lerpf(0.07, 0.80, t) * 0.72
		var ux: float = randf_range(-hw, hw)
		var bulb := TextureRect.new()
		bulb.texture = _dot()
		bulb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bulb.stretch_mode = TextureRect.STRETCH_SCALE
		bulb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bw: float = w * 0.19
		bulb.size = Vector2(bw, bw)
		bulb.position = Vector2(pos.x + w * (ux + 1.0) * 0.5 - bw * 0.5,
			pos.y + h * (uy + 1.0) * 0.5 - bw * 0.5)
		var c: Color = bulbs[i % bulbs.size()]
		bulb.modulate = Color(c.r, c.g, c.b, 0.92)
		add_child(bulb)
		var bt := bulb.create_tween().set_loops()
		bt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		bt.tween_property(bulb, "modulate:a", 0.26, randf_range(0.8, 2.0))
		bt.tween_property(bulb, "modulate:a", 0.95, randf_range(0.8, 2.0))
	var star := TextureRect.new()
	star.texture = _sparkle()
	star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	star.stretch_mode = TextureRect.STRETCH_SCALE
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sw: float = w * 0.85
	star.size = Vector2(sw, sw)
	star.pivot_offset = star.size * 0.5
	star.position = Vector2(base.x - sw * 0.5, pos.y - sw * 0.22)
	star.modulate = Color(1.0, 0.90, 0.52, 0.95)
	add_child(star)
	var sct := star.create_tween().set_loops()
	sct.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	sct.tween_property(star, "scale", Vector2(1.15, 1.15), 1.9)
	sct.tween_property(star, "scale", Vector2(0.92, 0.92), 2.3)
	_gift_pile(base, w)

## The snowman, kept from the camp this scene replaced — he is the one thing on
## the old screen that was already Christmas. Under a night palette he stops
## being cold-shadow blue and simply catches the moon, and the lantern on his
## stick arm is the only warm light on the right-hand side of the world.
func _snowman_figure(base: Vector2, w: float) -> void:
	var h: float = w * 1.533
	var man := TextureRect.new()
	man.texture = _shaped("snowman", 94, 144, _fn_snowman)
	man.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	man.stretch_mode = TextureRect.STRETCH_SCALE
	man.mouse_filter = Control.MOUSE_FILTER_IGNORE
	man.size = Vector2(w, h)
	man.position = Vector2(base.x - w * 0.5, base.y - h)
	man.modulate = Color(0.86, 0.93, 1.0, 1.0)
	add_child(man)
	# The scarf is baked in so it wraps his neck; only the loose END is a node,
	# so it can lift on the wind.
	var tail := ColorRect.new()
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tail.color = Color(0.78, 0.19, 0.26, 0.96)
	tail.size = Vector2(w * 0.30, w * 0.075)
	tail.pivot_offset = Vector2(0.0, tail.size.y * 0.5)
	tail.position = Vector2(base.x + w * 0.11, base.y - h * 0.565)
	add_child(tail)
	var stw := tail.create_tween().set_loops()
	stw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	stw.tween_property(tail, "rotation", -0.34, 1.5)
	stw.tween_property(tail, "rotation", 0.04, 1.9)
	var hook := Vector2(base.x + w * 0.46, base.y - h * 0.575)
	var pivot := Control.new()
	pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot.position = hook
	add_child(pivot)
	var wire := ColorRect.new()
	wire.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wire.color = Color(0.32, 0.30, 0.28, 0.8)
	wire.size = Vector2(maxf(_vp.x * 0.004, 1.0), h * 0.10)
	wire.position = Vector2(-wire.size.x * 0.5, 0.0)
	pivot.add_child(wire)
	var lantern := TextureRect.new()
	lantern.texture = _lantern()
	lantern.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lantern.stretch_mode = TextureRect.STRETCH_SCALE
	lantern.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lw: float = w * 0.26
	lantern.size = Vector2(lw, lw * 1.4)
	lantern.position = Vector2(-lw * 0.5, h * 0.10)
	lantern.modulate = Color(1.0, 0.80, 0.40, 0.95)
	pivot.add_child(lantern)
	var lhalo := TextureRect.new()
	lhalo.texture = _dot()
	lhalo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lhalo.stretch_mode = TextureRect.STRETCH_SCALE
	lhalo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lhalo.size = Vector2(lw * 3.6, lw * 3.6)
	lhalo.position = Vector2(-lhalo.size.x * 0.5,
		h * 0.10 + lw * 0.7 - lhalo.size.y * 0.5)
	lhalo.modulate = Color(1.0, 0.78, 0.38, 0.26)
	pivot.add_child(lhalo)
	var lt := lhalo.create_tween().set_loops()
	lt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	lt.tween_property(lhalo, "modulate:a", 0.42, 1.8)
	lt.tween_property(lhalo, "modulate:a", 0.20, 2.2)
	var sway := pivot.create_tween().set_loops()
	sway.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	sway.tween_property(pivot, "rotation", 0.13, 2.2)
	sway.tween_property(pivot, "rotation", -0.11, 2.5)

## A falling star: one thin streak crossing the upper sky, then a long wait, then
## another. A particle field cannot do "rare", and rare is the entire effect —
## two nodes and two tweens buy something a hundred particles could not.
func _meteor(delay: float) -> void:
	var m := TextureRect.new()
	m.texture = _ray()
	m.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	m.stretch_mode = TextureRect.STRETCH_SCALE
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l: float = _vp.x * randf_range(0.20, 0.32)
	m.size = Vector2(l * 0.085, l)
	m.pivot_offset = m.size * 0.5
	m.modulate = Color(0.94, 0.98, 1.0, 0.0)
	add_child(m)
	var from := Vector2(_vp.x * randf_range(-0.10, 0.45), _vp.y * randf_range(0.01, 0.09))
	var to := from + Vector2(_vp.x * randf_range(0.45, 0.70), _vp.y * randf_range(0.16, 0.26))
	# Point the streak along its own travel, or it falls sideways.
	var dir := to - from
	m.rotation = atan2(dir.y, dir.x) - PI * 0.5
	m.position = from
	var tw := m.create_tween().set_loops()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void: m.position = from)
	tw.tween_property(m, "modulate:a", 0.95, 0.16)
	tw.parallel().tween_property(m, "position", to, 0.80) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tw.tween_property(m, "modulate:a", 0.0, 0.30)
	tw.tween_interval(randf_range(6.0, 15.0))

## A sleigh and its team crossing the sky. It is a silhouette, so it would be
## invisible against a dark sky on its own — the path is routed THROUGH the moon
## and the lead deer carries one warm light, which are the two things that make
## it read. Runs on its own long timer, and again on `celebrate()`.
func _sleigh_setup() -> void:
	var s := TextureRect.new()
	s.texture = _shaped("sleigh", 150, 74, _fn_sleigh)
	s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	s.stretch_mode = TextureRect.STRETCH_SCALE
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w: float = _vp.x * 0.34
	s.size = Vector2(w, w * (74.0 / 150.0))
	s.position = Vector2(-w * 1.4, _vp.y * 0.30)
	s.modulate = Color(0.26, 0.34, 0.50, 0.0)
	add_child(s)
	# The lead deer's lamp, hung on the sprite so it travels with it.
	var nose := TextureRect.new()
	nose.texture = _dot()
	nose.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	nose.stretch_mode = TextureRect.STRETCH_SCALE
	nose.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nw: float = s.size.x * 0.10
	nose.size = Vector2(nw, nw)
	# The lead head sits at uv (-0.89, -0.175) in the bake; same two conversions
	# the lodge uses for its ornaments.
	nose.position = Vector2(s.size.x * (-0.89 + 1.0) * 0.5 - nw * 0.5,
		s.size.y * ((-0.175 / (74.0 / 150.0)) + 1.0) * 0.5 - nw * 0.5)
	nose.modulate = Color(1.0, 0.42, 0.30, 0.85)
	s.add_child(nose)
	_snow_sleigh = s
	var loop := s.create_tween().set_loops()
	loop.tween_interval(randf_range(9.0, 20.0))
	loop.tween_callback(_sleigh_fly)
	loop.tween_interval(22.0)	   # longer than the flight, so runs never stack

func _sleigh_fly() -> void:
	if _snow_sleigh == null or not is_instance_valid(_snow_sleigh):
		return
	var s := _snow_sleigh
	var w: float = s.size.x
	s.position = Vector2(-w * 1.2, _vp.y * 0.305)
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.92, 1.3)
	tw.parallel().tween_property(s, "position",
		Vector2(_vp.x + w * 0.3, _vp.y * 0.185), 13.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(s, "modulate:a", 0.0, 1.5)

## The frozen creek across the front of the village: an ice sheet, a lit shore
## line, and every warm window in the world smeared straight down it.
##
## It sits BELOW the village's feet because that is the only place a reflection
## can go, which on the gameplay screen means partly behind the button tray —
## the buttons are glass, so the smears read through them, and on every menu
## backdrop the whole sheet is in the clear. The alternative was a lake ABOVE
## the snow line, which would have needed the reflections to point upward.
func _frozen_creek(ground: float) -> void:
	var top: float = ground + _vp.y * 0.016
	var h: float = _vp.y * 0.070
	var ice := ColorRect.new()
	ice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ice.color = Color(0.26, 0.42, 0.66, 0.32)
	ice.size = Vector2(_vp.x * 1.1, h)
	ice.position = Vector2(-_vp.x * 0.05, top)
	add_child(ice)
	# The shore: a bright line where the drift stops and the ice starts.
	var shore := ColorRect.new()
	shore.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shore.color = Color(0.82, 0.91, 1.0, 0.42)
	shore.size = Vector2(_vp.x * 1.1, maxf(_vp.y * 0.0022, 1.0))
	shore.position = Vector2(-_vp.x * 0.05, top)
	add_child(shore)
	# Cracks: three hairlines at shallow angles, so the sheet reads as ice and
	# not as a painted stripe.
	for i in 3:
		var crack := ColorRect.new()
		crack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crack.color = Color(0.72, 0.86, 1.0, 0.16)
		crack.size = Vector2(_vp.x * randf_range(0.16, 0.34), maxf(_vp.y * 0.0016, 1.0))
		crack.position = Vector2(_vp.x * (0.10 + 0.32 * float(i)),
			top + h * randf_range(0.25, 0.80))
		crack.rotation = deg_to_rad(randf_range(-9.0, 9.0))
		add_child(crack)
	# The reflections. [source x, width, alpha, colour] — the two lodges, the
	# decorated fir, the snowman's lantern and the moon, in that order.
	for e_v in [[0.100, 0.10, 0.20, Color(1.0, 0.74, 0.34)],
			[0.315, 0.20, 0.42, Color(1.0, 0.74, 0.34)],
			[0.465, 0.09, 0.24, Color(1.0, 0.80, 0.42)],
			[0.605, 0.13, 0.30, Color(1.0, 0.80, 0.44)],
			[0.845, 0.08, 0.22, Color(1.0, 0.78, 0.38)],
			[0.765, 0.11, 0.26, Color(0.78, 0.90, 1.0)]]:
		var e: Array = e_v
		var r := TextureRect.new()
		r.texture = _dot()
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rw: float = _vp.x * float(e[1])
		r.size = Vector2(rw, h * 1.5)
		r.position = Vector2(_vp.x * float(e[0]) - rw * 0.5, top - h * 0.18)
		r.pivot_offset = Vector2(rw * 0.5, 0.0)		# wobble from the shore, not the middle
		var c: Color = e[3]
		var a: float = float(e[2])
		r.modulate = Color(c.r, c.g, c.b, a)
		add_child(r)
		var tw := r.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(r, "scale", Vector2(1.18, 0.92), randf_range(2.2, 3.4))
		tw.tween_property(r, "scale", Vector2(0.88, 1.06), randf_range(2.4, 3.8))

## Presents under the fir, and the pile grows with the run: two at the start of a
## game, one more at each journey tier. The tier is what the whole world already
## deepens on, so the pile is the one place the player can COUNT it.
func _gift_pile(base: Vector2, w: float) -> void:
	var tex := _shaped("gift", 44, 40, _fn_gift)
	var cols := [Color(0.86, 0.22, 0.26), Color(0.24, 0.62, 0.34),
		Color(0.95, 0.74, 0.32), Color(0.62, 0.42, 0.82), Color(0.36, 0.66, 0.92)]
	var n: int = 2 + _journey
	for i in n:
		var g := TextureRect.new()
		g.texture = tex
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_SCALE
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gw: float = w * randf_range(0.30, 0.44)
		g.size = Vector2(gw, gw * (40.0 / 44.0))
		# Spread along the foot of the tree, alternating out from the trunk.
		var side: float = -1.0 if (i % 2) == 0 else 1.0
		var off: float = w * (0.16 + 0.24 * float(i / 2))
		g.position = Vector2(base.x + side * off - gw * 0.5,
			base.y - g.size.y * randf_range(0.80, 1.0))
		var c: Color = cols[i % cols.size()]
		g.modulate = Color(c.r, c.g, c.b, 0.96)
		add_child(g)

## A pine swag hung across the top of the screen. This is the only part of the
## world that dresses the UI rather than the sky — it hangs off the very top
## edge, BEHIND the header (BoardFx is the backdrop layer), so the screen itself
## looks decorated without a single pixel of screen code moving.
func _top_garland() -> void:
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.size = _vp
	canvas.draw.connect(_draw_garland.bind(canvas))
	add_child(canvas)
	canvas.queue_redraw()
	# The bulbs are nodes and not paint, for the one reason anything in this
	# file is a node: they blink.
	var bulbs := [Color(1.0, 0.82, 0.42), Color(0.96, 0.28, 0.28),
		Color(0.36, 0.92, 0.46), Color(0.46, 0.80, 1.0)]
	for i in 13:
		var t: float = (float(i) + 0.5) / 13.0
		var p := _garland_pt(t)
		var b := TextureRect.new()
		b.texture = _dot()
		b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		b.stretch_mode = TextureRect.STRETCH_SCALE
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bw: float = _vp.x * 0.030
		b.size = Vector2(bw, bw)
		b.position = Vector2(p.x - bw * 0.5, p.y + _vp.y * 0.008 - bw * 0.5)
		var c: Color = bulbs[i % bulbs.size()]
		b.modulate = Color(c.r, c.g, c.b, 0.85)
		add_child(b)
		var tw := b.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(b, "modulate:a", 0.24, randf_range(1.0, 2.4))
		tw.tween_property(b, "modulate:a", 0.90, randf_range(1.0, 2.4))

## Where the cord hangs at t along the screen: three shallow swags, so it dips
## and rises across the header instead of sagging in one long curve. Shallow on
## purpose — anything deeper reaches the back arrow and the title.
func _garland_pt(t: float) -> Vector2:
	return Vector2(_vp.x * t, _vp.y * (0.004 + 0.028 * absf(sin(t * PI * 3.0))))

## The swag itself: one canvas item painted once. The cord is a tapered polygon
## through the curve and the needles are short strokes off it, both DETERMINISTIC
## — a _draw can be called again at any time, and a randf in here would make the
## garland twitch every time it was.
func _draw_garland(c: Control) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		pts.append(_garland_pt(float(i) / 48.0))
	var cord := Color(0.10, 0.22, 0.15, 0.95)
	c.draw_colored_polygon(_taper_poly(pts, _vp.y * 0.005, _vp.y * 0.005), cord)
	var needle := Color(0.13, 0.28, 0.18, 0.9)
	for i in 84:
		var t: float = (float(i) + 0.5) / 84.0
		var p := _garland_pt(t)
		# Alternating up/down sprigs, leaning along the cord.
		var up: float = -1.0 if (i % 2) == 0 else 1.0
		var lean: float = 0.5 * sin(float(i) * 2.399)
		var len: float = _vp.y * (0.010 + 0.006 * absf(sin(float(i) * 1.7)))
		var tip := p + Vector2(lean * len, up * len)
		c.draw_colored_polygon(
			_taper_poly(PackedVector2Array([p, tip]), _vp.y * 0.0026, 0.0), needle)

## The village answers a merge: the hearth flares in every lit window and the
## chimney puffs. Guarded by a flag rather than a clock — a 4x4 swipe can land
## eight merges on one frame, and eight overlapping tween sets on the same three
## nodes is the exact overspend _REACT_LIVE exists to stop on the particle side.
func _snow_react(strength: float) -> void:
	if _snow_flaring:
		return
	_snow_flaring = true
	var peak: float = clampf(0.46 + 0.34 * strength, 0.0, 1.0)
	for w_v in _snow_lights:
		var w: TextureRect = w_v
		if not is_instance_valid(w):
			continue
		var base: float = w.get_meta("rest_a", 0.42)
		var tw := w.create_tween()
		tw.tween_property(w, "modulate:a", peak, 0.09)
		tw.tween_property(w, "modulate:a", base, 0.55)
	if _snow_smoke != null and is_instance_valid(_snow_smoke):
		var was: float = _snow_smoke.initial_velocity_max
		_snow_smoke.initial_velocity_max = was * (1.0 + 0.85 * strength)
	var clear := create_tween()
	clear.tween_interval(0.42)
	clear.tween_callback(_snow_react_end)

func _snow_react_end() -> void:
	_snow_flaring = false
	if _snow_smoke != null and is_instance_valid(_snow_smoke):
		_snow_smoke.initial_velocity_max = _snow_smoke_v

## Tier 2 and up: the storm closes in. One more flake layer, faster and denser
## than anything in the base build, and the drifts come up over the village.
func _deep_winter() -> void:
	_emit({"from": "all", "tex": _dot(), "color": _white(1.0), "alpha": 0.45,
		"amount": 46, "lifetime": 8.0, "dir": Vector3(0.62, 1, 0), "spread": 12.0,
		"vmin": 90.0, "vmax": 190.0, "smin": 0.4, "smax": 1.1, "turb": 0.8})
	var ground: float = _vp.y * 0.872
	for i in 3:
		var drift := TextureRect.new()
		drift.texture = _round()
		drift.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drift.stretch_mode = TextureRect.STRETCH_SCALE
		drift.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.6, 1.1)
		var h: float = _vp.y * randf_range(0.055, 0.095)
		drift.size = Vector2(w, h)
		drift.position = Vector2(_vp.x * (0.10 + 0.38 * float(i)) - w * 0.5,
			ground - h * randf_range(0.30, 0.46))
		drift.modulate = Color(0.76, 0.88, 1.0, 0.24)
		add_child(drift)

func _m_petals() -> void:
	# Hanami: standing under a cherry in full flower while it sheds.
	#
	# The petal is its OWN bake here, not the generic `_petal()` oval every other
	# motif drifts. Two reasons, both visible: a cherry petal has a notch cut in
	# its wide end, which is the only detail that separates it from a rose petal
	# or a leaf; and the generic oval shades down to 0.72 brightness, so against
	# a near-white pink sky it came out as a grey-mauve speck. A real petal is
	# TRANSLUCENT — the sky comes through it, so it is barely darker than the sky
	# and often brighter. `_fn_sakura_petal` bakes it that way.
	#
	# The ramp is authored for the same reason. Sakura's tile ramp walks from deep
	# red up to blush, and petals drawn out of its low half came out maroon.
	var ramp := _ramp_cols([Color(1.0, 0.97, 0.98), Color(1.0, 0.86, 0.91),
		Color(1.0, 0.72, 0.83), Color(1.0, 0.58, 0.74)])
	var petal := _sakura_petal()
	# The light the whole scene stands in, before anything falls through it.
	_hanami_light()
	_emit({"from": "all", "tex": petal, "iramp": ramp,
		"alpha": 0.92, "amount": 60, "lifetime": 13.0, "dir": Vector3(0.15, 1, 0),
		"spread": 18.0, "vmin": 30.0, "vmax": 75.0, "smin": 0.7, "smax": 1.7,
		"spin": 2.2, "turb": 0.9})
	_emit({"from": "all", "tex": petal, "iramp": ramp,
		"alpha": 0.62, "amount": 40, "lifetime": 15.0, "dir": Vector3(0.1, 1, 0),
		"spread": 24.0, "vmin": 16.0, "vmax": 44.0, "smin": 0.35, "smax": 1.0,
		"spin": 1.4, "turb": 0.8})
	# A few big, close petals twirling past the "camera".
	_emit({"from": "top", "tex": petal, "iramp": ramp,
		"alpha": 0.95, "amount": 9, "lifetime": 10.0, "dir": Vector3(0.2, 1, 0),
		"spread": 20.0, "vmin": 45.0, "vmax": 95.0, "smin": 2.0, "smax": 3.2,
		"spin": 3.0, "turb": 1.0})
	# The eddy along the ground: petals that have landed getting picked back up
	# and carried sideways. A fall with no floor to it reads as a screensaver.
	_emit({"from": "bottom", "tex": petal, "iramp": ramp,
		"alpha": 0.70, "amount": 16, "lifetime": 7.0, "dir": Vector3(1.0, -0.35, 0),
		"spread": 34.0, "vmin": 28.0, "vmax": 90.0, "smin": 0.5, "smax": 1.1,
		"spin": 2.6, "orbit": 0.20})
	# The canopy overhead: warm blossom light bleeding down from the top edge.
	_edge_glow(_pc("accent").lerp(_white(1.0), 0.35), 0.05, 0.11, true)
	_sakura_tree()

## The sky the grove stands in: a warm low sun off the top right, the haze of
## more blossom on the far bank, and the shafts that come through a canopy.
## Without it the background is one flat pink field and the tree has nothing to
## be lit BY.
func _hanami_light() -> void:
	var warm := Color(1.0, 0.92, 0.84)
	# The sun, well off frame, as a broad bloom rather than a disc.
	for e_v in [[2.4, 0.10], [1.5, 0.13], [0.9, 0.16]]:
		var e: Array = e_v
		var g := TextureRect.new()
		g.texture = _round()
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_SCALE
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = _vp.x * float(e[0])
		g.size = Vector2(d, d)
		g.position = Vector2(_vp.x * 0.92, _vp.y * 0.06) - g.size * 0.5
		g.modulate = Color(warm.r, warm.g, warm.b, float(e[1]))
		add_child(g)
	# Light shafts coming down through the canopy, each on its own slow breath.
	for i in 5:
		var ray := TextureRect.new()
		ray.texture = _round()
		ray.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ray.stretch_mode = TextureRect.STRETCH_SCALE
		ray.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.14, 0.30)
		var h: float = _vp.y * randf_range(0.55, 0.95)
		ray.size = Vector2(w, h)
		ray.pivot_offset = Vector2(w * 0.5, 0.0)
		ray.position = Vector2(_vp.x * (0.18 + 0.20 * float(i)) - w * 0.5, -h * 0.06)
		ray.rotation = deg_to_rad(randf_range(9.0, 19.0))
		var peak: float = randf_range(0.05, 0.10)
		ray.modulate = Color(1.0, 0.96, 0.90, peak * 0.4)
		add_child(ray)
		var tw := ray.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(randf_range(0.0, 3.0))
		tw.tween_property(ray, "modulate:a", peak, randf_range(4.0, 7.0))
		tw.tween_property(ray, "modulate:a", peak * 0.25, randf_range(4.5, 7.5))
	# The far bank: more blossom, too distant to resolve into anything but haze.
	for i in 9:
		var haze := TextureRect.new()
		haze.texture = _round()
		haze.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		haze.stretch_mode = TextureRect.STRETCH_SCALE
		haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hw: float = _vp.x * randf_range(0.24, 0.52)
		haze.size = Vector2(hw, hw * randf_range(0.5, 0.8))
		haze.position = Vector2(_vp.x * (-0.10 + 0.15 * float(i)) - hw * 0.5,
			_vp.y * randf_range(0.80, 0.93) - haze.size.y * 0.5)
		haze.modulate = Color(1.0, 0.80, 0.88, randf_range(0.10, 0.20))
		add_child(haze)

func _m_anime() -> void:
	# Anime — dreamy drifting petals, big twinkling "kirakira" star sparkles, and soft
	# bokeh light for that shoujo shimmer.
	_emit({"from": "all", "tex": _petal(), "color": _pc("accent").lerp(_white(1.0), 0.25),
		"alpha": 0.8, "amount": 46, "lifetime": 13.0, "dir": Vector3(0.15, 1, 0),
		"spread": 18.0, "vmin": 26.0, "vmax": 70.0, "smin": 0.6, "smax": 1.5,
		"spin": 2.0, "turb": 0.9})
	# Kirakira — big 4-point star sparkles twinkling everywhere.
	_emit({"from": "all", "tex": _sparkle(), "color": _pc("accent").lerp(_white(1.0), 0.55),
		"alpha": 0.9, "amount": 26, "lifetime": 5.0, "dir": Vector3(0, -1, 0), "spread": 180.0,
		"vmin": 3.0, "vmax": 10.0, "smin": 0.5, "smax": 1.35, "twinkle": true})
	# Soft dreamy bokeh circles drifting behind it all.
	_emit({"from": "all", "tex": _round(), "color": _pc("accent2").lerp(_white(1.0), 0.4),
		"alpha": 0.12, "amount": 12, "lifetime": 15.0, "dir": Vector3(0.1, -1, 0),
		"spread": 180.0, "vmin": 3.0, "vmax": 9.0, "smin": 1.8, "smax": 3.6})
	_anime_rooftop()
	_anime_doodles()

## Anime — random pen SKETCHES drawn throughout the theme: empty-faced ink
## doodle heads (wild spikes / a shaggy mop / a spiked crop with curtains —
## solid ink hair, an outlined face with nothing in it) drift through the scene
## among the petals, with the occasional neko blob and onigiri between them,
## like the margin of a fan's notebook come loose. The bakes are Confetti's own
## static painters (the bat-silhouette precedent), so the world and the
## celebration draw the SAME doodles. Added AFTER the rooftop: z-order is
## add-order, and a doodle laid under the graded sky is a doodle nobody sees —
## these are sketches drawn ON the scene, not behind it.
func _anime_doodles() -> void:
	var heads: Array = [
		_shaped("anime_doodle_0", 36, 40, func(uv: Vector2) -> Color: return Confetti._anime_head(uv, 0)),
		_shaped("anime_doodle_1", 36, 40, func(uv: Vector2) -> Color: return Confetti._anime_head(uv, 1)),
		_shaped("anime_doodle_2", 36, 40, func(uv: Vector2) -> Color: return Confetti._anime_head(uv, 2)),
	]
	for i in heads.size():
		var head_tex: Texture2D = heads[i]
		_emit({"from": "all", "tex": head_tex, "color": _white(1.0), "alpha": 0.85,
			"amount": 5, "lifetime": 16.0, "dir": Vector3(0.12, 1, 0), "spread": 14.0,
			"vmin": 8.0, "vmax": 20.0, "smin": 1.0, "smax": 1.9, "spin": 0.5, "turb": 0.4})
	_emit({"from": "all", "tex": _shaped("anime_doodle_cat", 30, 28, Confetti._fn_doodle_cat),
		"color": _white(1.0), "alpha": 0.85, "amount": 4, "lifetime": 17.0,
		"dir": Vector3(-0.10, 1, 0), "spread": 14.0, "vmin": 7.0, "vmax": 17.0,
		"smin": 1.0, "smax": 1.7, "spin": 0.5, "turb": 0.4})
	_emit({"from": "all", "tex": _shaped("anime_doodle_onigiri", 28, 30, Confetti._fn_onigiri),
		"color": _white(1.0), "alpha": 0.85, "amount": 4, "lifetime": 17.0,
		"dir": Vector3(0.08, 1, 0), "spread": 14.0, "vmin": 7.0, "vmax": 17.0,
		"smin": 0.9, "smax": 1.6, "spin": 0.5, "turb": 0.4})

func _m_rain(col: Color, vmin: float, vmax: float, lightning: bool) -> void:
	# REAL rain, not a repeating dash pattern: long thin velocity-aligned drops
	# in three depth layers — near drops long, fast and bright; far drops short,
	# slow and faint — every drop accelerating under gravity with varied size
	# and speed so no two streaks ever line up.
	_rain_layer(col, 0.62, 26, vmax * 1.15, vmax * 1.55, 1.05, 1.6, 0.10)
	_rain_layer(col, 0.45, 40, vmin, vmax, 0.65, 1.0, 0.06)
	_rain_layer(col, 0.28, 34, vmin * 0.55, vmin * 0.80, 0.40, 0.65, 0.04)
	if lightning:
		# A real STORM, not just rain: a second sheet slanting hard in the wind,
		# leaf-debris spiralling through the gusts (one-signed orbit — the same
		# swirl mechanic as Carnival's confetti), and the lightning flashes.
		_emit({"from": "top", "tex": _streak(), "color": col, "alpha": 0.30,
			"amount": 28, "lifetime": 4.0, "dir": Vector3(0.38, 1, 0), "spread": 6.0,
			"vmin": vmax * 0.9, "vmax": vmax * 1.35, "smin": 0.7, "smax": 1.5})
		_emit({"from": "all", "tex": _leaf(), "color": Color(0.36, 0.44, 0.40),
			"alpha": 0.55, "amount": 13, "lifetime": 8.0, "dir": Vector3(1, 0.15, 0),
			"spread": 26.0, "vmin": 55.0, "vmax": 135.0, "smin": 0.5, "smax": 1.1,
			"spin": 3.2, "orbit": 0.35})
		# Fine wind-blown spray whipping sideways between the sheets.
		_emit({"from": "all", "tex": _dot(), "color": col, "alpha": 0.30,
			"amount": 26, "lifetime": 5.0, "dir": Vector3(1, 0.25, 0), "spread": 16.0,
			"vmin": 90.0, "vmax": 190.0, "smin": 0.2, "smax": 0.5, "orbit": 0.22})
		_start_lightning()

func _m_diamond() -> void:
	_emit({"from": "all", "tex": _dot(), "color": Color(0.8, 0.95, 1.0), "alpha": 0.9,
		"amount": 60, "lifetime": 9.0, "dir": Vector3(0.05, 1, 0), "spread": 8.0,
		"vmin": 90.0, "vmax": 200.0, "smin": 0.4, "smax": 1.1, "twinkle": true})

func _m_code() -> void:
	_emit({"from": "top", "tex": _streak(), "color": _pc("accent"), "alpha": 0.7,
		"amount": 80, "lifetime": 6.0, "dir": Vector3(0, 1, 0), "spread": 1.0,
		"vmin": 180.0, "vmax": 360.0, "smin": 1.2, "smax": 2.6})

func _m_embers() -> void:
	_emit({"from": "bottom", "tex": _dot(), "color": _pc("accent").lerp(_pc("gold"), 0.4),
		"alpha": 0.85, "amount": 70, "lifetime": 5.5, "dir": Vector3(0, -1, 0),
		"spread": 22.0, "vmin": 34.0, "vmax": 95.0, "smin": 0.4, "smax": 1.4,
		"turb": 0.6, "twinkle": true})

func _m_bubbles() -> void:
	# A sunlit sea: a bright sunbeam shafting in from the top corner + ambient god-rays,
	# rising REALISTIC bubbles (varied sizes, bright rims + highlights), drifting
	# plankton glow, and caustic light rippling over it all.
	_sunbeam_corner(Color(0.72, 0.92, 1.0))
	_god_rays(Color(0.6, 0.9, 1.0), 0.03, 0.08)
	var bcol: Color = _white(1.0).lerp(_pc("accent"), 0.25)
	# Big, slow bubbles rising up the middle.
	_emit({"from": "bottom", "tex": _bubble(), "color": bcol,
		"alpha": 0.6, "amount": 46, "lifetime": 9.0, "dir": Vector3(0, -1, 0),
		"spread": 12.0, "vmin": 20.0, "vmax": 50.0, "smin": 0.5, "smax": 1.4, "turb": 0.7})
	# Small, fast bubbles streaming up — a dense, lively column.
	_emit({"from": "bottom", "tex": _bubble(), "color": bcol,
		"alpha": 0.55, "amount": 64, "lifetime": 7.0, "dir": Vector3(0, -1, 0),
		"spread": 16.0, "vmin": 40.0, "vmax": 95.0, "smin": 0.18, "smax": 0.55, "turb": 0.9})
	# Bubbles EVERYWHERE — a whole-screen field of drifting bubbles of every size, so
	# the water is full of them rather than just a column up the centre.
	_emit({"from": "all", "tex": _bubble(), "color": bcol,
		"alpha": 0.5, "amount": 80, "lifetime": 10.0, "dir": Vector3(0, -1, 0), "spread": 180.0,
		"vmin": 8.0, "vmax": 30.0, "smin": 0.2, "smax": 1.1, "turb": 0.8})
	_caustics(Color(0.4, 0.82, 1.0))
	_sea_floor()

func _m_stars() -> void:
	# A dense, mostly-steady field of small bright pin-point stars …
	_emit({"from": "all", "tex": _dot(), "color": _white(1.0),
		"alpha": 0.95, "amount": 130, "lifetime": 8.0, "dir": Vector3(0, 1, 0),
		"spread": 180.0, "vmin": 1.0, "vmax": 4.0, "smin": 0.28, "smax": 0.7})
	# … plus fewer, larger twinkling stars tinted to the theme for sparkle.
	_emit({"from": "all", "tex": _dot(), "color": _white(1.0).lerp(_pc("accent"), 0.4),
		"alpha": 1.0, "amount": 40, "lifetime": 4.5, "dir": Vector3(0, 1, 0),
		"spread": 180.0, "vmin": 1.0, "vmax": 4.0, "smin": 0.5, "smax": 1.2,
		"twinkle": true})

func _m_space() -> void:
	# Deep space: a truly DENSE sky — the standard field plus a far layer of tiny
	# pin-stars, a tilted milky galaxy band with a bright core, the occasional
	# shooting star, and a distant planet with a soft rim glow.
	_m_stars()
	# The deep field: hundreds of barely-moving pinpricks behind everything.
	_emit({"from": "all", "tex": _dot(), "color": _white(1.0), "alpha": 0.65,
		"amount": 170, "lifetime": 10.0, "dir": Vector3(0, 1, 0), "spread": 180.0,
		"vmin": 0.5, "vmax": 2.5, "smin": 0.16, "smax": 0.42})
	_galaxy_band()
	_shooting_stars(_gen)
	_deep_planets()

## The planets of the deep field. A banded gas giant with a ring system tilted
## across it dominates the upper sky; a smaller rocky world hangs low and far,
## lit from the same side; a tiny moon keeps the giant company. Every one is
## lit from the LEFT so the whole sky agrees about where its star is, and each
## turns slowly enough that you only notice it between games.
func _deep_planets() -> void:
	var accent: Color = _pc("accent")
	# --- The gas giant, upper right ---
	var gc := Vector2(_vp.x * 0.74, _vp.y * 0.13)
	var gd: float = _vp.x * 0.30
	var halo := TextureRect.new()
	halo.texture = _round()
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.size = Vector2(gd * 2.4, gd * 2.4)
	halo.position = gc - halo.size * 0.5
	halo.modulate = Color(accent.r, accent.g, accent.b, 0.15)
	add_child(halo)
	# The ring's BACK half goes down first, so the planet's body covers it.
	var ring_w: float = gd * 2.25
	var ring_tex := _shaped("planet_ring", 200, 200, _fn_planet_ring)
	var ring_back := TextureRect.new()
	ring_back.texture = ring_tex
	ring_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring_back.stretch_mode = TextureRect.STRETCH_SCALE
	ring_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring_back.size = Vector2(ring_w, ring_w * 0.34)
	ring_back.pivot_offset = ring_back.size * 0.5
	ring_back.rotation = deg_to_rad(-15.0)
	ring_back.position = gc - ring_back.size * 0.5
	ring_back.modulate = Color(0.92, 0.86, 0.78, 0.40)
	add_child(ring_back)
	var giant := TextureRect.new()
	giant.texture = _shaped("gas_giant", 128, 128, _fn_gas_giant)
	giant.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	giant.stretch_mode = TextureRect.STRETCH_SCALE
	giant.mouse_filter = Control.MOUSE_FILTER_IGNORE
	giant.size = Vector2(gd, gd)
	giant.position = gc - giant.size * 0.5
	giant.modulate = accent.lerp(Color(0.95, 0.74, 0.52), 0.55)
	add_child(giant)
	# ...and the FRONT half over it, clipped to the lower band by a mask rect.
	var front_clip := Control.new()
	front_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front_clip.clip_contents = true
	front_clip.position = Vector2(gc.x - ring_w * 0.5, gc.y)
	front_clip.size = Vector2(ring_w, ring_w * 0.34)
	add_child(front_clip)
	var ring_front := TextureRect.new()
	ring_front.texture = ring_tex
	ring_front.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring_front.stretch_mode = TextureRect.STRETCH_SCALE
	ring_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring_front.size = ring_back.size
	ring_front.pivot_offset = ring_front.size * 0.5
	ring_front.rotation = ring_back.rotation
	ring_front.position = Vector2(0.0, -ring_front.size.y * 0.5)
	ring_front.modulate = Color(0.96, 0.90, 0.82, 0.52)
	front_clip.add_child(ring_front)
	# A tiny moon on a long slow orbit of the giant.
	var orbit := Control.new()
	orbit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orbit.position = gc
	add_child(orbit)
	var moon := TextureRect.new()
	moon.texture = _moon()
	moon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var md: float = gd * 0.15
	moon.size = Vector2(md, md)
	moon.position = Vector2(gd * 0.95, -gd * 0.30) - moon.size * 0.5
	moon.modulate = Color(0.86, 0.88, 0.96, 0.9)
	orbit.add_child(moon)
	var ot := orbit.create_tween().set_loops()
	ot.tween_property(orbit, "rotation", TAU, 150.0).from(0.0)
	# --- A small rocky world, low and far to the left ---
	var rc := Vector2(_vp.x * 0.14, _vp.y * 0.42)
	var rd: float = _vp.x * 0.11
	var rock := TextureRect.new()
	rock.texture = _shaped("rock_planet", 96, 96, _fn_rock_planet)
	rock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rock.stretch_mode = TextureRect.STRETCH_SCALE
	rock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rock.size = Vector2(rd, rd)
	rock.position = rc - rock.size * 0.5
	rock.modulate = Color(0.62, 0.70, 0.92, 0.85)
	add_child(rock)
	var rhalo := TextureRect.new()
	rhalo.texture = _round()
	rhalo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rhalo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rhalo.size = Vector2(rd * 2.1, rd * 2.1)
	rhalo.position = rc - rhalo.size * 0.5
	rhalo.modulate = Color(0.45, 0.62, 1.0, 0.10)
	add_child(rhalo)

## A tilted milky galaxy band: nested stretched glows — cool blue outer haze,
## violet mid, a warm bright core — breathing slowly across the sky diagonal.
## The touch of real deep space behind the starfield.
func _galaxy_band() -> void:
	var centre := Vector2(_vp.x * 0.38, _vp.y * 0.40)
	var tilt := deg_to_rad(-28.0)
	var layers := [
		[Vector2(_vp.x * 1.55, _vp.y * 0.52), Color(0.50, 0.68, 1.00), 0.10],
		[Vector2(_vp.x * 1.20, _vp.y * 0.32), Color(0.70, 0.52, 1.00), 0.13],
		[Vector2(_vp.x * 0.85, _vp.y * 0.15), Color(1.00, 0.94, 0.86), 0.20],
	]
	for l in layers:
		var entry := l as Array
		var sz: Vector2 = entry[0]
		var col: Color = entry[1]
		var peak: float = entry[2]
		var band := TextureRect.new()
		band.texture = _round()
		band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		band.stretch_mode = TextureRect.STRETCH_SCALE
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.size = sz
		band.pivot_offset = sz * 0.5
		band.rotation = tilt
		band.position = centre - sz * 0.5
		band.modulate = Color(col.r, col.g, col.b, peak * 0.7)
		add_child(band)
		var tw := band.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(band, "modulate:a", peak, randf_range(6.0, 9.0))
		tw.tween_property(band, "modulate:a", peak * 0.55, randf_range(6.0, 9.0))
	# A second, fainter arm crossing the first at a shallower angle — one band is
	# a smear, two reading through each other is a galaxy.
	var arm := TextureRect.new()
	arm.texture = _round()
	arm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arm.stretch_mode = TextureRect.STRETCH_SCALE
	arm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arm.size = Vector2(_vp.x * 1.35, _vp.y * 0.26)
	arm.pivot_offset = arm.size * 0.5
	arm.rotation = deg_to_rad(-9.0)
	arm.position = centre + Vector2(_vp.x * 0.06, _vp.y * 0.10) - arm.size * 0.5
	arm.modulate = Color(0.62, 0.74, 1.00, 0.06)
	add_child(arm)
	var at := arm.create_tween().set_loops()
	at.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	at.tween_property(arm, "modulate:a", 0.11, 8.0)
	at.tween_property(arm, "modulate:a", 0.05, 8.5)
	# Emission knots along the band: warm and cool gas lit from inside.
	for k_v in [[Vector2(0.26, 0.30), Color(1.00, 0.55, 0.72), 0.13],
			[Vector2(0.52, 0.47), Color(0.48, 0.72, 1.00), 0.10],
			[Vector2(0.16, 0.52), Color(0.80, 0.60, 1.00), 0.09]]:
		var k: Array = k_v
		var kf: Vector2 = k[0]
		var knot := TextureRect.new()
		knot.texture = _round()
		knot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		knot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var kd: float = _vp.x * randf_range(0.28, 0.46)
		knot.size = Vector2(kd, kd * 0.72)
		knot.position = Vector2(_vp.x * kf.x, _vp.y * kf.y) - knot.size * 0.5
		var kc: Color = k[1]
		var ka: float = k[2]
		knot.modulate = Color(kc.r, kc.g, kc.b, ka * 0.6)
		add_child(knot)
		var kt := knot.create_tween().set_loops()
		kt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		kt.tween_property(knot, "modulate:a", ka, randf_range(7.0, 10.0))
		kt.tween_property(knot, "modulate:a", ka * 0.5, randf_range(7.0, 10.0))
	# Dense core stars sprinkled along the band itself.
	_emit({"from": "all", "tex": _dot(), "color": Color(1.0, 0.96, 0.88), "alpha": 0.85,
		"amount": 46, "lifetime": 6.0, "dir": Vector3(0, 1, 0), "spread": 180.0,
		"vmin": 0.5, "vmax": 2.0, "smin": 0.2, "smax": 0.55, "twinkle": true})

func _m_fireflies() -> void:
	_emit({"from": "all", "tex": _dot(), "color": _pc("gold").lerp(_pc("accent"), 0.3),
		"alpha": 0.9, "amount": 32, "lifetime": 5.0, "dir": Vector3(0, -1, 0),
		"spread": 180.0, "vmin": 6.0, "vmax": 20.0, "smin": 0.6, "smax": 1.5,
		"turb": 0.9, "twinkle": true})

func _m_firefly_night() -> void:
	# A realistic firefly night: a DENSE field of small, soft, warm fireflies that
	# wander erratically and blink (dim -> glow -> dim, via short lifetimes), a few
	# out-of-focus bokeh glows for depth, a pale moon + moonbeam, and a dark swaying
	# grass silhouette that grounds it as a forest meadow at night.
	var warm: Color = _pc("gold").lerp(Color(0.75, 1.0, 0.35), 0.35)
	# A LOT of clear fireflies drifting/floating, each blinking (they wander via high
	# turbulence and blink via short lifetimes) — dense but soft.
	_emit({"from": "all", "tex": _dot(), "color": warm, "alpha": 0.62,
		"amount": 110, "lifetime": 3.6, "dir": Vector3(0, -1, 0), "spread": 180.0,
		"vmin": 5.0, "vmax": 18.0, "smin": 0.38, "smax": 0.95, "turb": 1.2, "twinkle": true})
	# Brighter blinkers for clear sparkle.
	_emit({"from": "all", "tex": _dot(), "color": warm.lerp(_white(1.0), 0.35), "alpha": 0.88,
		"amount": 36, "lifetime": 2.6, "dir": Vector3(0, -1, 0), "spread": 180.0,
		"vmin": 4.0, "vmax": 14.0, "smin": 0.55, "smax": 1.2, "turb": 1.5, "twinkle": true})
	# Big, faint, slow out-of-focus bokeh for depth.
	_emit({"from": "all", "tex": _dot(), "color": warm, "alpha": 0.10,
		"amount": 10, "lifetime": 7.0, "dir": Vector3(0, -1, 0), "spread": 180.0,
		"vmin": 3.0, "vmax": 8.0, "smin": 2.6, "smax": 5.2, "turb": 0.6, "twinkle": true})
	# A pale moon high in the sky.
	var moon := TextureRect.new()
	moon.texture = _moon()
	moon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var md: float = _vp.x * 0.16
	moon.size = Vector2(md, md)
	moon.position = Vector2(_vp.x * 0.75, _vp.y * 0.10)
	moon.modulate = Color(0.92, 0.96, 0.84, 0.85)
	add_child(moon)
	_moonbeam()
	_grass_silhouette()
	_edge_glow(warm, 0.03, 0.08, false)
	_firefly_pond()

## Dark grass / reed blades along the bottom edge, each swaying gently — the
## meadow foreground under the fireflies. TWO ranks now: a fainter, taller back
## row behind a denser, thicker front row, so it reads as a full grass bed
## rather than scattered blades.
func _grass_silhouette() -> void:
	_grass_row(26, Color(0.02, 0.06, 0.02, 0.55), 0.012, 0.026, 0.20, 0.42, 12.0)
	_grass_row(48, Color(0.01, 0.04, 0.01, 0.85), 0.009, 0.022, 0.12, 0.32, 6.0)

func _grass_row(n: int, col: Color, wmin: float, wmax: float,
		hmin: float, hmax: float, y_off: float) -> void:
	for i in n:
		var blade := ColorRect.new()
		blade.color = col
		blade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bw: float = _vp.x * randf_range(wmin, wmax)
		var bh: float = _vp.y * randf_range(hmin, hmax)
		blade.size = Vector2(bw, bh)
		blade.pivot_offset = Vector2(bw * 0.5, bh)   # pivot at the root
		var bx: float = _vp.x * (float(i) / float(n - 1)) + randf_range(-_vp.x * 0.025, _vp.x * 0.025)
		blade.position = Vector2(bx - bw * 0.5, _vp.y - bh + y_off)
		var base_rot: float = deg_to_rad(randf_range(-7.0, 7.0))
		blade.rotation = base_rot
		add_child(blade)
		var sway: float = deg_to_rad(randf_range(3.0, 8.0))
		var tw := blade.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(blade, "rotation", base_rot + sway, randf_range(2.2, 3.8))
		tw.tween_property(blade, "rotation", base_rot - sway, randf_range(2.2, 3.8))

func _m_fog() -> void:
	_emit({"from": "all", "tex": _dot(), "color": _pc("accent").lerp(_pc("text"), 0.3),
		"alpha": 0.12, "amount": 14, "lifetime": 16.0, "dir": Vector3(1, 0.05, 0),
		"spread": 30.0, "vmin": 6.0, "vmax": 18.0, "smin": 3.5, "smax": 11.0, "turb": 0.4})

func _m_confetti() -> void:
	_emit({"from": "top", "tex": _square(), "color": _pc("accent"), "alpha": 0.9,
		"amount": 60, "lifetime": 4.5, "dir": Vector3(0, 1, 0), "spread": 22.0,
		"vmin": 80.0, "vmax": 220.0, "smin": 1.2, "smax": 2.6, "spin": 4.0,
		"gravity": 120.0, "hue": true})

func _m_motes() -> void:
	_emit({"from": "all", "tex": _dot(), "color": _pc("accent").lerp(_white(1.0), 0.3),
		"alpha": 0.25, "amount": 36, "lifetime": 10.0, "dir": Vector3(0, -1, 0),
		"spread": 180.0, "vmin": 4.0, "vmax": 12.0, "smin": 0.22, "smax": 0.6, "turb": 0.4})

func _m_arcade() -> void:
	# Arcade — a NEON PIXEL STORM: multicolour pixel confetti everywhere (raining from
	# the top AND drifting across the whole screen), plus glowing pixel sparks. Loud,
	# fast, electric. (fx_style "arcade" also multiplies these counts up.)
	_emit({"from": "top", "tex": _square(), "iramp": _rainbow(), "alpha": 0.95,
		"amount": 46, "lifetime": 4.5, "dir": Vector3(0, 1, 0), "spread": 26.0,
		"vmin": 90.0, "vmax": 240.0, "smin": 1.2, "smax": 2.6, "spin": 4.5, "gravity": 130.0})
	_emit({"from": "all", "tex": _square(), "iramp": _rainbow(), "alpha": 0.8,
		"amount": 54, "lifetime": 6.0, "dir": Vector3(0, -1, 0), "spread": 180.0,
		"vmin": 10.0, "vmax": 42.0, "smin": 0.9, "smax": 2.0, "spin": 3.0})
	_emit({"from": "all", "tex": _dot(), "iramp": _two(_pc("accent"), _pc("accent2")),
		"alpha": 0.9, "amount": 40, "lifetime": 5.0, "dir": Vector3(0, -1, 0), "spread": 180.0,
		"vmin": 4.0, "vmax": 14.0, "smin": 0.3, "smax": 0.85, "twinkle": true})
	# A neon frame glow that softly pulses, like an arcade cabinet's bezel.
	_edge_glow(_pc("accent"), 0.05, 0.12, false)
	_ambient_flash(_pc("accent2"), 0.06, 3.5, 7.0)
	_arcade_cabinet()

## You are sitting AT the cabinet: a lit marquee across the top with a rank of
## pixel invaders marching under it, and the control panel along the bottom —
## a ball-top joystick that knocks between its gates and two rows of chunky
## buttons lighting in an attract-mode chase.
func _arcade_cabinet() -> void:
	var accent: Color = _pc("accent")
	var accent2: Color = _pc("accent2")
	# --- The marquee ---
	var marquee := ColorRect.new()
	marquee.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marquee.color = Color(0.04, 0.03, 0.09, 0.9)
	marquee.size = Vector2(_vp.x, _vp.y * 0.075)
	marquee.position = Vector2.ZERO
	add_child(marquee)
	# The lit face of it: a wide soft wash behind the glass, breathing between
	# the theme's two hues so the whole top of the room is coloured light.
	var face := TextureRect.new()
	face.texture = _round()
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_SCALE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.size = Vector2(_vp.x * 1.1, _vp.y * 0.13)
	face.position = Vector2(-_vp.x * 0.05, -_vp.y * 0.035)
	face.modulate = Color(accent.r, accent.g, accent.b, 0.30)
	add_child(face)
	var ft := face.create_tween().set_loops()
	ft.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	ft.tween_property(face, "modulate", Color(accent2.r, accent2.g, accent2.b, 0.42), 2.6)
	ft.tween_property(face, "modulate", Color(accent.r, accent.g, accent.b, 0.30), 2.8)
	var strip := ColorRect.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.color = Color(accent.r, accent.g, accent.b, 0.55)
	strip.size = Vector2(_vp.x, maxf(_vp.y * 0.005, 2.0))
	strip.position = Vector2(0.0, marquee.size.y)
	add_child(strip)
	var mt := strip.create_tween().set_loops()
	mt.tween_property(strip, "color", Color(accent2.r, accent2.g, accent2.b, 0.75), 1.1)
	mt.tween_property(strip, "color", Color(accent.r, accent.g, accent.b, 0.55), 1.1)
	# Marquee bulbs along its underside.
	for i in 14:
		var bulb := TextureRect.new()
		bulb.texture = _dot()
		bulb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bulb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = _vp.x * 0.022
		bulb.size = Vector2(d, d)
		bulb.position = Vector2(_vp.x * (float(i) + 0.5) / 14.0 - d * 0.5,
			marquee.size.y - d * 0.35)
		bulb.modulate = Color(1.0, 0.92, 0.6, 0.35)
		add_child(bulb)
		var bt := bulb.create_tween().set_loops()
		bt.tween_interval(float(i) * 0.09)
		bt.tween_property(bulb, "modulate:a", 0.95, 0.14)
		bt.tween_property(bulb, "modulate:a", 0.35, 0.4)
		bt.tween_interval(1.26 - float(i) * 0.09)
	# --- The neon on the back wall ---
	# Abstract tubing, not signage: bent neon runs that buzz and hold. It is an
	# arcade you are STANDING IN, so nothing here is a game being played.
	var neon_cols: Array = [accent, accent2, Color(1.0, 0.32, 0.52),
		Color(0.42, 1.0, 0.72)]
	for i in 5:
		var tube := TextureRect.new()
		tube.texture = _shaped("arcade_neon_%d" % (i % 3), 128, 128,
			(_fn_neon_zig if i % 3 == 0 else (_fn_neon_arc if i % 3 == 1 else _fn_neon_bolt)))
		tube.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tube.stretch_mode = TextureRect.STRETCH_SCALE
		tube.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tw_: float = _vp.x * randf_range(0.16, 0.28)
		tube.size = Vector2(tw_, tw_)
		tube.pivot_offset = tube.size * 0.5
		tube.rotation = deg_to_rad(randf_range(-14.0, 14.0))
		tube.position = Vector2(_vp.x * (0.06 + 0.22 * float(i)) - tw_ * 0.5,
			_vp.y * randf_range(0.11, 0.30))
		var nc: Color = neon_cols[i % neon_cols.size()]
		tube.modulate = Color(nc.r, nc.g, nc.b, 0.5)
		add_child(tube)
		# A tube warms up, holds, and now and then stutters like failing gas.
		var nt := tube.create_tween().set_loops()
		nt.tween_interval(randf_range(0.5, 3.0))
		nt.tween_property(tube, "modulate:a", 0.85, 0.5)
		nt.tween_interval(randf_range(2.0, 5.0))
		nt.tween_property(tube, "modulate:a", 0.25, 0.06)
		nt.tween_property(tube, "modulate:a", 0.8, 0.09)
		nt.tween_property(tube, "modulate:a", 0.35, 0.07)
		nt.tween_property(tube, "modulate:a", 0.5, 0.4)
	# --- The cabinet line-up along the back ---
	# Four machines standing shoulder to shoulder, each with a lit marquee and a
	# screen glowing an idle attract colour behind its bezel.
	var cab_tex := _shaped("arcade_cab", 100, 190, _fn_arcade_cab)
	var screen_cols: Array = [Color(0.25, 0.85, 1.0), Color(1.0, 0.42, 0.72),
		Color(0.55, 1.0, 0.45), Color(1.0, 0.78, 0.28)]
	for i in 4:
		var cw: float = _vp.x * 0.255
		var ch: float = cw * 2.7
		var x: float = _vp.x * (0.11 + 0.26 * float(i)) - cw * 0.5
		var y: float = _vp.y * 0.995 - ch
		var cab := TextureRect.new()
		cab.texture = cab_tex
		cab.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cab.stretch_mode = TextureRect.STRETCH_SCALE
		cab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cab.size = Vector2(cw, ch)
		cab.position = Vector2(x, y)
		var sc: Color = screen_cols[i % screen_cols.size()]
		# Each machine wears a tint of its own game's colour, so the row reads as
		# four different cabinets rather than four copies of one grey box.
		var body := Color(0.30, 0.31, 0.40).lerp(sc, 0.28)
		cab.modulate = Color(body.r, body.g, body.b, 0.97)
		add_child(cab)
		# The screen glow behind the bezel — an attract-mode wash, no sprites.
		var screen := TextureRect.new()
		screen.texture = _dot()
		screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		screen.stretch_mode = TextureRect.STRETCH_SCALE
		screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.size = Vector2(cw * 0.62, ch * 0.24)
		screen.position = Vector2(x + cw * 0.19, y + ch * 0.30)
		screen.modulate = Color(sc.r, sc.g, sc.b, 0.35)
		add_child(screen)
		var st := screen.create_tween().set_loops()
		st.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		st.tween_interval(randf_range(0.0, 1.5))
		st.tween_property(screen, "modulate:a", 0.65, randf_range(1.2, 2.2))
		st.tween_property(screen, "modulate:a", 0.28, randf_range(1.4, 2.6))
		# Its marquee, lit in the cabinet's own colour.
		var mq := ColorRect.new()
		mq.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mq.color = Color(sc.r, sc.g, sc.b, 0.55)
		mq.size = Vector2(cw * 0.70, ch * 0.045)
		mq.position = Vector2(x + cw * 0.15, y + ch * 0.115)
		add_child(mq)
	# --- The control panel of the machine YOU are standing at ---
	# It sits in front of the line-up, so the room reads with depth: your cabinet
	# in the foreground, the others glowing behind it.
	var panel := ColorRect.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.color = Color(0.09, 0.08, 0.15, 0.98)
	panel.size = Vector2(_vp.x, _vp.y * 0.155)
	panel.position = Vector2(0.0, _vp.y - panel.size.y)
	add_child(panel)
	# The brushed metal sheen across it.
	var sheen := TextureRect.new()
	sheen.texture = _round()
	sheen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sheen.stretch_mode = TextureRect.STRETCH_SCALE
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheen.size = Vector2(_vp.x * 1.2, panel.size.y * 1.6)
	sheen.position = Vector2(-_vp.x * 0.1, panel.position.y - panel.size.y * 0.3)
	sheen.modulate = Color(accent2.r, accent2.g, accent2.b, 0.10)
	add_child(sheen)
	# The bezel lip along its leading edge, catching the marquee light.
	var lip := ColorRect.new()
	lip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lip.color = Color(accent.r, accent.g, accent.b, 0.55)
	lip.size = Vector2(_vp.x, maxf(_vp.y * 0.005, 2.0))
	lip.position = Vector2(0.0, panel.position.y)
	add_child(lip)
	var lip2 := ColorRect.new()
	lip2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lip2.color = Color(0.02, 0.02, 0.05, 0.9)
	lip2.size = Vector2(_vp.x, maxf(_vp.y * 0.010, 3.0))
	lip2.position = Vector2(0.0, panel.position.y + lip.size.y)
	add_child(lip2)
	var panel_y: float = panel.position.y + panel.size.y * 0.52
	# The joystick, left of the panel — it knocks between its gates.
	var stick := TextureRect.new()
	stick.texture = _shaped("arcade_stick", 56, 96, _fn_joystick)
	stick.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stick.stretch_mode = TextureRect.STRETCH_SCALE
	stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sw: float = _vp.x * 0.13
	stick.size = Vector2(sw, sw * 1.71)
	stick.pivot_offset = Vector2(sw * 0.5, stick.size.y * 0.92)   # pivots at its base
	stick.position = Vector2(_vp.x * 0.17 - sw * 0.5, panel_y - stick.size.y * 0.72)
	stick.modulate = Color(1.0, 0.35, 0.45, 0.95)
	add_child(stick)
	var jt := stick.create_tween().set_loops()
	jt.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	jt.tween_property(stick, "rotation", 0.30, 0.22)
	jt.tween_interval(0.5)
	jt.tween_property(stick, "rotation", -0.30, 0.26)
	jt.tween_interval(0.35)
	jt.tween_property(stick, "rotation", 0.0, 0.24)
	jt.tween_interval(0.9)
	# Two rows of buttons, lighting in a chase.
	var btn_tex := _shaped("arcade_button", 52, 52, _fn_arcade_button)
	var btn_cols: Array = [Color(1.0, 0.28, 0.36), Color(1.0, 0.78, 0.2),
		Color(0.35, 0.9, 1.0), Color(0.55, 1.0, 0.5), Color(0.85, 0.5, 1.0),
		Color(1.0, 0.5, 0.75)]
	for i in 6:
		var row: int = 0 if i < 3 else 1
		var col: int = i % 3
		var btn := TextureRect.new()
		btn.texture = btn_tex
		btn.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		btn.stretch_mode = TextureRect.STRETCH_SCALE
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bw: float = _vp.x * 0.088
		btn.size = Vector2(bw, bw)
		btn.position = Vector2(_vp.x * 0.44 + float(col) * bw * 1.28,
			panel_y - bw * (0.85 if row == 0 else -0.15))
		var bc: Color = btn_cols[i]
		btn.modulate = Color(bc.r, bc.g, bc.b, 0.55)
		add_child(btn)
		var bt := btn.create_tween().set_loops()
		bt.tween_interval(float(i) * 0.16)
		bt.tween_property(btn, "modulate:a", 1.0, 0.1)
		bt.tween_property(btn, "modulate:a", 0.55, 0.3)
		bt.tween_interval(1.5 - float(i) * 0.16)

func _m_candy() -> void:
	# Candy land.
	#
	# Built back-to-front, the same way Arctic's village is, because a BoardFx
	# child list IS the paint order: sky, two ranks of frosted hills, the far
	# half of the sprinkle fall, the land itself, then the near half.
	#
	# The field used to be the whole theme and it ran at ARCADE density: forty
	# rainbow squares at up to 2.2x scale under gravity, sixty-four bright
	# sprinkles across the WHOLE screen and sixteen bubbles — about a hundred and
	# seventy particles once the 1.40x multiplier and the global lift were
	# applied, so the tile numerals were being read THROUGH falling confetti.
	# The charm was never the weather. The weather halved and the WORLD arrived:
	# everything below is new, and the theme dropped to `playful` in its .tres,
	# which is where the 1.40x came from.
	_candy_sky()
	_candy_hills()
	_candy_fall(false)
	_candy_land()
	_candy_fall(true)

## The sprinkle fall, in two halves so the land can stand between them. `near`
## picks the front half — the same split Arctic's snow uses, and for the same
## reason: it is what puts the shop INSIDE the weather instead of behind it.
func _candy_fall(near: bool) -> void:
	if not near:
		_emit({"from": "all", "tex": _dot(),
			"iramp": _ramp_cols([Color("FF6FB5"), Color("6FE8D0"), Color("B79CFF"),
				Color("FFD86E"), Color("6EC6FF")]),
			"alpha": 0.38, "amount": 26, "lifetime": 7.0, "dir": Vector3(0, -1, 0),
			"spread": 180.0, "vmin": 8.0, "vmax": 26.0, "smin": 0.28, "smax": 0.8})
		_emit({"from": "bottom", "tex": _bubble(), "color": _pc("accent2"), "alpha": 0.30,
			"amount": 8, "lifetime": 9.0, "dir": Vector3(0, -1, 0), "spread": 40.0,
			"vmin": 20.0, "vmax": 52.0, "smin": 0.6, "smax": 1.3, "turb": 0.7})
		return
	_emit({"from": "top", "tex": _square(), "color": _pc("accent"), "alpha": 0.55,
		"amount": 20, "lifetime": 5.5, "dir": Vector3(0, 1, 0), "spread": 28.0,
		"vmin": 45.0, "vmax": 120.0, "smin": 0.7, "smax": 1.5, "spin": 3.0,
		"gravity": 80.0, "hue": true})

## The sky over the sweet shop: marshmallow clouds, a doughnut where the sun
## should be, gumdrops floating up past it, and bunting across the top.
func _candy_sky() -> void:
	# Clouds, each a little cluster of soft lumps — a single blob reads as a
	# smudge, three overlapping ones read as marshmallow.
	for e_v in [[0.16, 0.075, 0.30, 0.30], [0.52, 0.045, 0.22, 0.22],
			[0.86, 0.100, 0.26, 0.26]]:
		var e: Array = e_v
		var cw: float = _vp.x * float(e[2])
		var cy: float = _vp.y * float(e[1])
		var cloud := Control.new()
		cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cloud.position = Vector2(_vp.x * float(e[0]), cy)
		add_child(cloud)
		for j in 3:
			var lump := TextureRect.new()
			lump.texture = _round()
			lump.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			lump.stretch_mode = TextureRect.STRETCH_SCALE
			lump.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var lw: float = cw * [0.72, 1.0, 0.66][j]
			lump.size = Vector2(lw, lw * 0.66)
			lump.position = Vector2(cw * [-0.34, 0.0, 0.36][j] - lw * 0.5,
				cw * [0.05, -0.02, 0.07][j] - lw * 0.33)
			lump.modulate = Color(1.0, 0.94, 0.96, 0.55)
			cloud.add_child(lump)
		# A long, lazy drift across the sky and back.
		var dr := cloud.create_tween().set_loops()
		dr.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		var home := cloud.position
		dr.tween_property(cloud, "position", home + Vector2(_vp.x * 0.05, 0.0), randf_range(15.0, 22.0))
		dr.tween_property(cloud, "position", home, randf_range(15.0, 22.0))
	# The doughnut, hung where a sun would be: low enough to clear the score
	# panel, which on this screen is the only clear strip of sky there is.
	var dc := Vector2(_vp.x * 0.775, _vp.y * 0.238)
	var dd: float = _vp.x * 0.185
	var halo := TextureRect.new()
	halo.texture = _round()
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_SCALE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.size = Vector2(dd * 3.0, dd * 3.0)
	halo.position = dc - halo.size * 0.5
	halo.modulate = Color(1.0, 0.78, 0.88, 0.16)
	add_child(halo)
	var ht := halo.create_tween().set_loops()
	ht.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	ht.tween_property(halo, "modulate:a", 0.26, 4.2)
	ht.tween_property(halo, "modulate:a", 0.13, 4.8)
	var ring := TextureRect.new()
	ring.texture = _shaped("doughnut", 64, 64, _fn_doughnut)
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.stretch_mode = TextureRect.STRETCH_SCALE
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.size = Vector2(dd, dd)
	ring.pivot_offset = ring.size * 0.5
	ring.position = dc - ring.size * 0.5
	add_child(ring)
	var turn := ring.create_tween().set_loops()
	turn.tween_property(ring, "rotation", TAU, 90.0).from(0.0)
	# Gumdrops floating up through it, each on its own bob.
	var drop_tex := _shaped("gumdrop", 44, 40, _fn_gumdrop)
	var drop_cols := [Color(1.0, 0.42, 0.62), Color(0.46, 0.88, 0.78),
		Color(1.0, 0.80, 0.36), Color(0.70, 0.60, 1.0), Color(0.50, 0.80, 1.0)]
	for i in 7:
		var g := TextureRect.new()
		g.texture = drop_tex
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_SCALE
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gw: float = _vp.x * randf_range(0.035, 0.070)
		g.size = Vector2(gw, gw * (40.0 / 44.0))
		var home := Vector2(_vp.x * ((float(i) + 0.5) / 7.0) + randf_range(-30.0, 30.0),
			_vp.y * randf_range(0.05, 0.30))
		g.position = home
		var c: Color = drop_cols[i % drop_cols.size()]
		g.modulate = Color(c.r, c.g, c.b, 0.80)
		add_child(g)
		var bob := g.create_tween().set_loops()
		bob.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		bob.tween_property(g, "position", home - Vector2(0.0, _vp.y * 0.022), randf_range(2.6, 4.2))
		bob.tween_property(g, "position", home, randf_range(2.6, 4.2))
	_pennant_line(_vp.y * 0.042, _vp.y * 0.048, 12, _vp.x * 0.055,
		[_pc("accent"), _pc("accent2"), Color(1.0, 0.84, 0.42),
		Color(0.72, 0.62, 1.0), Color(1.0, 0.62, 0.78)], 0.92)

## Two ranks of frosted hills between the sky and the land. One bake drawn twice,
## the far rank wider, paler and flipped so the two skylines never repeat — the
## same trick, and the same reasoning, as Arctic's peaks.
func _candy_hills() -> void:
	var tex := _candy_hills_tex()
	var far := Color(0.86, 0.80, 0.96)
	var near := Color(1.0, 0.96, 0.98)
	# [x centre, width, height, base y, fade to far, alpha, flipped]
	for e_v in [[0.44, 1.40, 0.200, 0.868, 0.80, 0.75, true],
			[0.58, 1.02, 0.150, 0.888, 0.12, 1.00, false]]:
		var e: Array = e_v
		var w: float = _vp.x * float(e[1])
		var h: float = _vp.y * float(e[2])
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.flip_h = bool(e[6])
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.size = Vector2(w, h)
		r.position = Vector2(_vp.x * float(e[0]) - w * 0.5, _vp.y * float(e[3]) - h)
		var c := near.lerp(far, float(e[4]))
		r.modulate = Color(c.r, c.g, c.b, float(e[5]))
		add_child(r)

## The land: a candy-cane wood, lollipop trees, cupcakes and the gumball machine,
## all standing on ONE ground line, with a syrup river running across the front.
##
## The line sits at 0.885 because that is the last clear band on the gameplay
## screen. This shop used to stand on `_vp.y * 1.0` — the literal bottom EDGE,
## underneath the Undo / Redo / Rewind tray — so the machine's globe cleared the
## buttons and nothing else in it was ever visible at all.
func _candy_land() -> void:
	var ground: float = _vp.y * 0.885
	# A wood of canes running off both edges, smaller and paler further back.
	var cane_tex := _shaped("candy_cane", 38, 106, _fn_cane)
	for e_v in [[0.020, 0.115, -13.0, 0.30], [0.105, 0.080, 8.0, 0.14],
			[0.400, 0.070, -6.0, 0.10], [0.480, 0.095, 5.0, 0.22],
			[0.830, 0.078, -9.0, 0.16], [0.965, 0.105, 15.0, 0.30]]:
		var e: Array = e_v
		var h: float = _vp.y * float(e[1])
		var w: float = h * (60.0 / 170.0)
		var cane := TextureRect.new()
		cane.texture = cane_tex
		cane.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cane.stretch_mode = TextureRect.STRETCH_SCALE
		cane.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cane.size = Vector2(w, h)
		cane.pivot_offset = Vector2(w * 0.5, h)
		cane.rotation = deg_to_rad(float(e[2]))
		cane.position = Vector2(_vp.x * float(e[0]) - w * 0.5, ground - h)
		var d: float = float(e[3])
		cane.modulate = Color(1.0, lerpf(0.62, 0.44, d), lerpf(0.72, 0.56, d),
			lerpf(0.75, 0.96, d))
		add_child(cane)
	# Cupcakes in a row, the small stuff that fills the gaps between the tall.
	var cake_tex := _shaped("cupcake", 52, 60, _fn_cupcake)
	var cake_cols := [Color(1.0, 0.66, 0.80), Color(0.62, 0.92, 0.84),
		Color(1.0, 0.86, 0.52)]
	for i in 3:
		var cake := TextureRect.new()
		cake.texture = cake_tex
		cake.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cake.stretch_mode = TextureRect.STRETCH_SCALE
		cake.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ch: float = _vp.y * [0.052, 0.062, 0.048][i]
		cake.size = Vector2(ch * (52.0 / 60.0), ch)
		cake.position = Vector2(_vp.x * [0.145, 0.345, 0.900][i] - cake.size.x * 0.5,
			ground - ch)
		var c: Color = cake_cols[i]
		cake.modulate = Color(c.r, c.g, c.b, 0.97)
		add_child(cake)
	# The gumball machine, the hero of the counter.
	var mh: float = _vp.y * 0.118
	var mw: float = mh * (130.0 / 190.0)
	var shine := TextureRect.new()
	shine.texture = _dot()
	shine.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shine.stretch_mode = TextureRect.STRETCH_SCALE
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shine.size = Vector2(mw * 2.2, mw * 2.2)
	shine.position = Vector2(_vp.x * 0.245 - shine.size.x * 0.5,
		ground - mh * 0.72 - shine.size.y * 0.5)
	shine.modulate = Color(1.0, 0.82, 0.90, 0.16)
	add_child(shine)
	var mach := TextureRect.new()
	mach.texture = _shaped("gumball_machine", 82, 120, _fn_gumball)
	mach.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mach.stretch_mode = TextureRect.STRETCH_SCALE
	mach.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mach.size = Vector2(mw, mh)
	mach.position = Vector2(_vp.x * 0.245 - mw * 0.5, ground - mh)
	mach.modulate = Color(1, 1, 1, 0.97)
	add_child(mach)
	# Lollipop trees: the tall canopy of this wood, each turning at its own rate.
	var pop_tex := _shaped("lollipop", 60, 60, _fn_lollipop)
	for e_v in [[0.565, 0.088, 0.105, 26.0], [0.655, 0.112, 0.130, -20.0],
			[0.750, 0.076, 0.092, 31.0], [0.060, 0.066, 0.078, -27.0]]:
		var e: Array = e_v
		var stick_h: float = _vp.y * float(e[2])
		var pd: float = _vp.x * float(e[1])
		var cx: float = _vp.x * float(e[0])
		var stick := _srect(0.0, 0.0, maxf(_vp.x * 0.010, 2.0), stick_h,
			Color(0.99, 0.96, 0.92, 0.9))
		stick.position = Vector2(cx - stick.size.x * 0.5, ground - stick_h)
		var pop := TextureRect.new()
		pop.texture = pop_tex
		pop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pop.stretch_mode = TextureRect.STRETCH_SCALE
		pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pop.size = Vector2(pd, pd)
		pop.pivot_offset = pop.size * 0.5
		pop.position = Vector2(cx - pd * 0.5, ground - stick_h - pd * 0.5)
		pop.modulate = Color(1, 1, 1, 0.97)
		add_child(pop)
		var spin := pop.create_tween().set_loops()
		spin.tween_property(pop, "rotation", TAU, float(e[3])).from(0.0)
	# Gumdrops dropped along the ground, filling the feet of everything else.
	var drop_tex := _shaped("gumdrop", 44, 40, _fn_gumdrop)
	var drop_cols := [Color(1.0, 0.44, 0.64), Color(0.48, 0.90, 0.80),
		Color(1.0, 0.82, 0.38), Color(0.72, 0.62, 1.0), Color(0.52, 0.82, 1.0)]
	for i in 9:
		var g := TextureRect.new()
		g.texture = drop_tex
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_SCALE
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gw: float = _vp.x * randf_range(0.030, 0.052)
		g.size = Vector2(gw, gw * (40.0 / 44.0))
		g.position = Vector2(_vp.x * ((float(i) + 0.5) / 9.0) + randf_range(-16.0, 16.0)
			- gw * 0.5, ground - g.size.y * randf_range(0.85, 1.0))
		var c: Color = drop_cols[i % drop_cols.size()]
		g.modulate = Color(c.r, c.g, c.b, 0.95)
		add_child(g)
	_syrup_river(ground)

## The river of syrup across the front of the land: a poured sheet with a bright
## lip where it starts, and everything above it smeared down its surface.
##
## Reflections can only go BELOW their source, which on the gameplay screen means
## partly behind the button tray — the buttons are glass, so the smears read
## through them, and on every menu backdrop the whole sheet is in the clear.
func _syrup_river(ground: float) -> void:
	var top: float = ground + _vp.y * 0.014
	var h: float = _vp.y * 0.075
	var syrup := ColorRect.new()
	syrup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	syrup.color = Color(0.86, 0.34, 0.52, 0.42)
	syrup.size = Vector2(_vp.x * 1.1, h)
	syrup.position = Vector2(-_vp.x * 0.05, top)
	add_child(syrup)
	var lip := ColorRect.new()
	lip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lip.color = Color(1.0, 0.86, 0.92, 0.55)
	lip.size = Vector2(_vp.x * 1.1, maxf(_vp.y * 0.0026, 1.0))
	lip.position = Vector2(-_vp.x * 0.05, top)
	add_child(lip)
	# [source x, width, alpha, colour] — the machine, the cupcakes, the three
	# lollipop trees and the doughnut overhead.
	for e_v in [[0.145, 0.08, 0.26, Color(1.0, 0.72, 0.84)],
			[0.245, 0.16, 0.38, Color(1.0, 0.60, 0.72)],
			[0.345, 0.08, 0.26, Color(0.68, 0.94, 0.88)],
			[0.565, 0.10, 0.30, Color(1.0, 0.84, 0.50)],
			[0.655, 0.13, 0.34, Color(1.0, 0.66, 0.86)],
			[0.750, 0.09, 0.28, Color(0.74, 0.68, 1.0)],
			[0.775, 0.12, 0.24, Color(1.0, 0.82, 0.90)]]:
		var e: Array = e_v
		var r := TextureRect.new()
		r.texture = _dot()
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rw: float = _vp.x * float(e[1])
		r.size = Vector2(rw, h * 1.5)
		r.position = Vector2(_vp.x * float(e[0]) - rw * 0.5, top - h * 0.18)
		r.pivot_offset = Vector2(rw * 0.5, 0.0)	  # ripple from the bank, not the middle
		var c: Color = e[3]
		r.modulate = Color(c.r, c.g, c.b, float(e[2]))
		add_child(r)
		var tw := r.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(r, "scale", Vector2(1.16, 0.94), randf_range(2.2, 3.4))
		tw.tween_property(r, "scale", Vector2(0.90, 1.05), randf_range(2.4, 3.8))

func _m_lightdust() -> void:
	# Daybreak — a pleasant MORNING, not just sunlit dust: the warm mote field
	# and depth orbs stay, and the morning WIND now shows — fresh leaves carried
	# across the frame on one slow curling gust (one-signed orbit = one wind),
	# faint warm breeze streaks so the air itself reads, and every so often the
	# dawn chorus crosses high over the sunrise (_dawn_birds).
	_emit({"from": "all", "tex": _dot(), "color": _pc("accent").lerp(_white(1.0), 0.4),
		"alpha": 0.42, "amount": 64, "lifetime": 11.0, "dir": Vector3(0, -1, 0),
		"spread": 180.0, "vmin": 4.0, "vmax": 13.0, "smin": 0.25, "smax": 0.7, "twinkle": true})
	_emit({"from": "all", "tex": _round(), "color": _pc("accent").lerp(_white(1.0), 0.55),
		"alpha": 0.14, "amount": 14, "lifetime": 16.0, "dir": Vector3(0.2, -1, 0),
		"spread": 180.0, "vmin": 3.0, "vmax": 9.0, "smin": 1.6, "smax": 3.4})
	# Deep spring greens into gold, never pastel: this is a LIGHT theme, and a
	# pale leaf on the pale lilac sky is simply not there.
	_emit({"from": "all", "tex": _leaf(),
		"iramp": _ramp_cols([Color("6BB84D"), Color("8FCF5C"), Color("D9A83D")]),
		"alpha": 0.55, "amount": 10, "lifetime": 13.0, "dir": Vector3(1, -0.12, 0),
		"spread": 14.0, "vmin": 24.0, "vmax": 50.0, "smin": 0.6, "smax": 1.2,
		"spin": 1.8, "orbit": 0.15, "turb": 0.3})
	_emit({"from": "all", "tex": _streak(), "color": Color(1.0, 0.72, 0.40), "alpha": 0.16,
		"amount": 7, "lifetime": 7.0, "dir": Vector3(1, -0.05, 0), "spread": 7.0,
		"vmin": 55.0, "vmax": 105.0, "smin": 1.2, "smax": 2.4, "align": true})
	_dawn_horizon()
	_dawn_branch()
	_dawn_birds(_gen)
	_dawn_perch_life(_gen)

func _m_stardrift() -> void:
	# Obsidian — a quiet STARDRIFT: a teal starfield drifting across the black, with a
	# few brighter twinkles, so the dark never feels empty.
	_emit({"from": "all", "tex": _dot(), "color": _pc("accent").lerp(_white(1.0), 0.3),
		"alpha": 0.5, "amount": 72, "lifetime": 9.0, "dir": Vector3(0, -1, 0),
		"spread": 180.0, "vmin": 3.0, "vmax": 11.0, "smin": 0.18, "smax": 0.5, "twinkle": true})
	_emit({"from": "all", "tex": _dot(), "color": _pc("accent"), "alpha": 0.85,
		"amount": 24, "lifetime": 5.0, "dir": Vector3(0, -1, 0), "spread": 180.0,
		"vmin": 3.0, "vmax": 11.0, "smin": 0.42, "smax": 0.9, "twinkle": true})
	_obsidian_floor()

func _m_flecks() -> void:
	# Paper — a sketchbook page, open on a desk.
	#
	# What used to be here was a pencil. Literally: two faint coffee rings, a
	# drift of dust, and one pencil lying across the bottom of an otherwise
	# blank screen. The theme is called Paper and the paper was the one thing
	# not being drawn — a sheet with nothing on it is not minimalism, it is an
	# empty frame with a prop in the corner.
	#
	# So the page is a page: laid texture, a ruled margin, a torn top edge and
	# the shadow of the sheet it is lying on. There are old sketches on it,
	# faint, in pencil. And every few seconds another one DRAWS ITSELF, stroke
	# by stroke, holds, and fades back into the paper — which is the one thing
	# a sheet of paper does that nothing else in this app does.
	_paper_page()
	# Graphite dust in the light over the page.
	_emit({"from": "all", "tex": _dot(), "color": _pc("text").lerp(_white(1.0), 0.25),
		"alpha": 0.22, "amount": 40, "lifetime": 12.0, "dir": Vector3(0.15, -1, 0),
		"spread": 180.0, "vmin": 3.0, "vmax": 10.0, "smin": 0.25, "smax": 0.7, "turb": 0.5})
	# Eraser crumbs, heavier, settling rather than floating.
	_emit({"from": "all", "tex": _dot(), "color": _pc("text").lerp(_white(1.0), 0.55),
		"alpha": 0.16, "amount": 14, "lifetime": 9.0, "dir": Vector3(0.05, 1, 0),
		"spread": 40.0, "vmin": 4.0, "vmax": 14.0, "smin": 0.3, "smax": 0.8})
	_paper_desk()
	_paper_sketching(_gen)

## The sheet: its texture, its margin, its torn edge, and the light on it.
func _paper_page() -> void:
	var ink: Color = _pc("text")
	# The light: a soft warm fall from the top left, and the page darkening into
	# the corners. Paper is never evenly lit, and a flat page reads as a colour.
	var lamp := TextureRect.new()
	lamp.texture = _round()
	lamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lamp.stretch_mode = TextureRect.STRETCH_SCALE
	lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ld: float = _vp.x * 2.2
	lamp.size = Vector2(ld, ld)
	lamp.position = Vector2(_vp.x * 0.18, _vp.y * 0.10) - lamp.size * 0.5
	lamp.modulate = Color(1.0, 0.98, 0.92, 0.30)
	add_child(lamp)
	for e_v in [[0.0, 1.0], [1.0, 1.0], [0.0, 0.0], [1.0, 0.0]]:
		var e: Array = e_v
		var vig := TextureRect.new()
		vig.texture = _round()
		vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		vig.stretch_mode = TextureRect.STRETCH_SCALE
		vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vd: float = _vp.x * 1.1
		vig.size = Vector2(vd, vd)
		vig.position = Vector2(_vp.x * float(e[0]), _vp.y * float(e[1])) - vig.size * 0.5
		vig.modulate = Color(0.55, 0.52, 0.46, 0.10)
		add_child(vig)
	# The grain, the ruled lines and the margin, painted once.
	var page := Control.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.size = _vp
	page.draw.connect(_draw_paper_page.bind(page, ink))
	add_child(page)
	page.queue_redraw()

func _draw_paper_page(c: Control, ink: Color) -> void:
	# Laid lines: the fine ribbing a sheet of laid paper is made on. Almost
	# invisible one at a time; together they are the difference between paper
	# and a flat fill.
	var step: float = maxf(_vp.y * 0.0115, 6.0)
	var y: float = step
	while y < _vp.y:
		c.draw_line(Vector2(0.0, y), Vector2(_vp.x, y),
			Color(ink.r, ink.g, ink.b, 0.016), 1.0, false)
		y += step
	# The ruled margin down the left, in the faded red every notebook has.
	var mx: float = _vp.x * 0.115
	c.draw_line(Vector2(mx, 0.0), Vector2(mx, _vp.y), Color(0.80, 0.36, 0.36, 0.16),
		maxf(_vp.x * 0.004, 1.2), true)
	# Punch holes down it, each with the shadow of its own bevel.
	for i in 3:
		var hy: float = _vp.y * (0.22 + 0.28 * float(i))
		var hc := Vector2(mx * 0.48, hy)
		var hr: float = maxf(_vp.x * 0.018, 5.0)
		c.draw_circle(hc, hr, Color(ink.r, ink.g, ink.b, 0.07))
		c.draw_arc(hc, hr, 0.0, TAU, 24, Color(ink.r, ink.g, ink.b, 0.10), 1.4, true)
	# The torn top edge: the sheet has been pulled out of a pad.
	var tear := PackedVector2Array()
	var n := 46
	for i in n + 1:
		var tx: float = _vp.x * float(i) / float(n)
		tear.append(Vector2(tx, _vp.y * (0.012
			+ 0.006 * sin(float(i) * 1.7) + 0.004 * sin(float(i) * 5.3))))
	c.draw_polyline(tear, Color(ink.r, ink.g, ink.b, 0.10), maxf(_vp.y * 0.0016, 1.0), true)
	# A crease running down the sheet, catching the light on one side of it.
	var crease := PackedVector2Array()
	for i in 21:
		var t: float = float(i) / 20.0
		crease.append(Vector2(_vp.x * (0.70 + 0.02 * sin(t * 3.1)), _vp.y * t))
	c.draw_polyline(crease, Color(ink.r, ink.g, ink.b, 0.045), maxf(_vp.x * 0.004, 1.2), true)
	c.draw_polyline(crease, Color(1, 1, 1, 0.35), maxf(_vp.x * 0.0016, 1.0), true)

## Line drawings, in a local -1..1 box. Each is a list of strokes; each stroke a
## list of points. Kept as DATA rather than as bakes because a pencil line is a
## line — a per-pixel bake of one would cost a hundred times as much and come
## out softer, and these have to be drawable a stroke at a time (see
## `_paper_sketching`), which a texture cannot do at all.
func _paper_doodles() -> Array:
	if not _paper_art.is_empty():
		return _paper_art
	# --- a paper crane, three-quarters on
	_paper_art.append([
		PackedVector2Array([Vector2(-0.86, 0.10), Vector2(-0.30, -0.20), Vector2(0.06, 0.04),
			Vector2(0.52, -0.30), Vector2(0.88, -0.02)]),                      # the wings
		PackedVector2Array([Vector2(0.06, 0.04), Vector2(0.10, 0.52), Vector2(-0.16, 0.86)]),  # the tail
		PackedVector2Array([Vector2(0.06, 0.04), Vector2(-0.34, 0.30), Vector2(-0.70, 0.44)]), # the body
		PackedVector2Array([Vector2(-0.30, -0.20), Vector2(-0.44, -0.62), Vector2(-0.72, -0.70),
			Vector2(-0.56, -0.56)]),                                            # neck and head
		PackedVector2Array([Vector2(-0.70, 0.44), Vector2(-0.16, 0.86)]),       # the fold under
	])
	# --- a leaf study
	var leaf := PackedVector2Array()
	for i in 33:
		var t: float = float(i) / 32.0 * TAU
		leaf.append(Vector2(sin(t) * 0.52 * (1.0 + 0.22 * cos(t)), -cos(t) * 0.86))
	var veins: Array = [PackedVector2Array([Vector2(0.0, 0.84), Vector2(0.0, -0.84)])]
	for k in 5:
		var vy: float = 0.52 - 0.30 * float(k)
		var sp: float = 0.30 * (1.0 - absf(vy) * 0.7)
		veins.append(PackedVector2Array([Vector2(0.0, vy),
			Vector2(sp, vy - 0.22), Vector2(sp * 1.15, vy - 0.30)]))
		veins.append(PackedVector2Array([Vector2(0.0, vy),
			Vector2(-sp, vy - 0.22), Vector2(-sp * 1.15, vy - 0.30)]))
	_paper_art.append([leaf] + veins)
	# --- a golden spiral, drawn as one long stroke
	var spiral := PackedVector2Array()
	for i in 90:
		var t2: float = float(i) / 89.0
		var ang: float = t2 * TAU * 2.6
		var rr: float = 0.06 + 0.92 * pow(t2, 1.35)
		spiral.append(Vector2(cos(ang), sin(ang)) * rr)
	_paper_art.append([spiral])
	# --- an impossible cube: the doodle everyone draws in a margin
	_paper_art.append([
		PackedVector2Array([Vector2(-0.62, -0.42), Vector2(0.30, -0.42), Vector2(0.30, 0.50),
			Vector2(-0.62, 0.50), Vector2(-0.62, -0.42)]),
		PackedVector2Array([Vector2(-0.30, -0.78), Vector2(0.62, -0.78), Vector2(0.62, 0.14),
			Vector2(-0.30, 0.14), Vector2(-0.30, -0.78)]),
		PackedVector2Array([Vector2(-0.62, -0.42), Vector2(-0.30, -0.78)]),
		PackedVector2Array([Vector2(0.30, -0.42), Vector2(0.62, -0.78)]),
		PackedVector2Array([Vector2(0.30, 0.50), Vector2(0.62, 0.14)]),
		PackedVector2Array([Vector2(-0.62, 0.50), Vector2(-0.30, 0.14)]),
	])
	# --- a compass rose
	var rose: Array = []
	# Each point is a triangle standing ON the centre — tip out, two base
	# corners either side of it. An earlier pass ran the stroke from the tip
	# THROUGH the centre to the opposite tip, so all four points crossed each
	# other and the rose came out as a tangle of spikes.
	for k in 8:
		var ang2: float = float(k) * PI * 0.25
		var d := Vector2(cos(ang2), sin(ang2))
		# The diagonals are the half-points: shorter, and narrower at the base,
		# so eight points meeting in the middle stay a rose instead of a knot.
		var main: bool = k % 2 == 0
		var s := Vector2(-d.y, d.x) * (0.10 if main else 0.045)
		var reach: float = 0.94 if main else 0.50
		rose.append(PackedVector2Array([d * reach, s, -s, d * reach]))
	var ring := PackedVector2Array()
	for i in 41:
		var t3: float = float(i) / 40.0 * TAU
		ring.append(Vector2(cos(t3), sin(t3)) * 0.44)
	rose.append(ring)
	_paper_art.append(rose)
	return _paper_art

var _paper_art: Array = []

## Every few seconds a drawing appears on the page, one stroke at a time, holds
## while the ink sits, and fades. It is the whole reason the theme is alive:
## nothing else in the app draws itself.
func _paper_sketching(gen: int) -> void:
	# Two already on the page at entry, faint, so the sheet is never blank.
	for i in 2:
		_paper_draw(randi() * 2 + i, true)
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(3.5, 7.0)).timeout
		if gen != _gen or not is_inside_tree():
			return
		_paper_draw(randi(), false)

func _paper_draw(seed_i: int, old: bool) -> void:
	var art: Array = _paper_doodles()
	var strokes: Array = art[seed_i % art.size()]
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size = _vp
	var w: float = _vp.x * randf_range(0.20, 0.34)
	# Kept out of the middle band, where the board sits.
	var cy: float = _vp.y * (randf_range(0.05, 0.26) if randf() < 0.5
		else randf_range(0.72, 0.94))
	# Alternating halves: two doodles dropped independently kept landing in the
	# same corner and reading as one scribble.
	var at := Vector2(_vp.x * (randf_range(0.20, 0.50) if seed_i % 2 == 0
		else randf_range(0.54, 0.86)), cy)
	var lean: float = randf_range(-0.28, 0.28)
	box.set_meta("k", 1.0 if old else 0.0)
	box.draw.connect(_draw_doodle.bind(box, strokes, at, w, lean, _pc("text")))
	add_child(box)
	box.modulate = Color(1, 1, 1, 0.42 if old else 0.0)
	if old:
		return
	# The hand: strokes land one after another, then the drawing sits, then the
	# page takes it back.
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 0.80, 0.35)
	tw.parallel().tween_method(func(v: float) -> void:
		if is_instance_valid(box):
			box.set_meta("k", v)
			box.queue_redraw(),
		0.0, 1.0, randf_range(1.6, 2.8)).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(randf_range(2.5, 5.0))
	tw.tween_property(box, "modulate:a", 0.0, 2.2)
	tw.tween_callback(box.queue_free)

## Draws the first `k` of a drawing's total stroke length — so the tween above
## reads as a hand moving, not as a picture fading up.
func _draw_doodle(c: Control, strokes: Array, at: Vector2, w: float, lean: float,
		ink: Color) -> void:
	var k: float = float(c.get_meta("k", 1.0))
	if k <= 0.0:
		return
	var cs := cos(lean)
	var sn := sin(lean)
	var total := 0.0
	for s_v in strokes:
		var s: PackedVector2Array = s_v
		total += float(s.size() - 1)
	var budget: float = total * k
	var lw: float = maxf(w * 0.016, 1.1)
	var col := Color(ink.r, ink.g, ink.b, 0.42)
	for s_v2 in strokes:
		var s2: PackedVector2Array = s_v2
		if budget <= 0.0:
			return
		var take: int = mini(int(ceil(budget)) + 1, s2.size())
		var pts := PackedVector2Array()
		for i in take:
			var p: Vector2 = s2[i]
			pts.append(at + Vector2(p.x * cs - p.y * sn, p.x * sn + p.y * cs) * w)
		if pts.size() >= 2:
			c.draw_polyline(pts, col, lw, true)
		budget -= float(s2.size() - 1)

func _m_neon() -> void:
	# Cyberpunk city in the rain: a neon skyline glowing along the bottom, soft
	# out-of-focus neon bokeh (magenta + cyan) drifting behind it, and slanted rain
	# streaking down over it all.
	_neon_skyline()
	# drifting bokeh in the full neon spread — cyan, magenta, violet, warm.
	_emit({"from": "all", "tex": _dot(),
		"iramp": _ramp_cols([Color(0.35, 0.88, 1.0), Color(1.0, 0.3, 0.74),
			Color(0.62, 0.5, 1.0), Color(1.0, 0.78, 0.45)]),
		"alpha": 0.3, "amount": 24, "lifetime": 9.0, "dir": Vector3(0, -1, 0),
		"spread": 180.0, "vmin": 4.0, "vmax": 13.0, "smin": 2.2, "smax": 4.8,
		"twinkle": true})
	# the rain catches the neon: streaks in mixed cyan / magenta / warm, not just blue
	_emit({"from": "top", "tex": _streak(),
		"iramp": _ramp_cols([Color(0.4, 0.9, 1.0), Color(1.0, 0.35, 0.78),
			Color(0.7, 0.78, 1.0), Color(1.0, 0.82, 0.5)]),
		"alpha": 0.34, "amount": 32, "lifetime": 5.0, "dir": Vector3(0.06, 1, 0), "spread": 3.0,
		"vmin": 280.0, "vmax": 520.0, "smin": 0.7, "smax": 1.4})
	_ramen_stall()

## A neon skyline along the bottom edge: dark buildings of varied height, each
## studded with neon windows (cyan / theme / magenta), a scatter of them flicker,
## plus a bright neon sign or two and a glow bleeding up off the rooftops.
func _neon_skyline() -> void:
	# Two rows for depth: a tall, dim, dense DISTANT skyline behind, then the
	# detailed NEAR buildings with lit windows and neon signs in front.
	_neon_row(true)
	_neon_row(false)
	# neon bleeding up off the rooftops into the wet haze.
	_edge_glow(_pc("accent").lerp(Color(1.0, 0.26, 0.72), 0.3), 0.06, 0.14, false)

## One row of the skyline. `far` = the distant depth layer (taller, narrower,
## denser, dimmer, few windows); otherwise the detailed near buildings.
func _neon_row(far: bool) -> void:
	var hues := [_pc("accent"), _pc("accent2").lerp(_white(1.0), 0.2), Color(1.0, 0.26, 0.72)]
	var xs := randf_range(-0.06, -0.02)
	while xs < 1.04:
		var bw: float = randf_range(0.055, 0.11) if far else randf_range(0.085, 0.16)
		var bh: float = randf_range(0.22, 0.48) if far else randf_range(0.12, 0.32)
		# EVERY building is a lit facade: the window grid is baked into the texture,
		# so none is ever left a bare shadow. Far ones are dimmed + blue-hazed.
		var b := TextureRect.new()
		b.texture = _neon_building(randi() % 3)
		b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		b.stretch_mode = TextureRect.STRETCH_SCALE
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.size = Vector2(_vp.x * bw, _vp.y * bh)
		b.position = Vector2(_vp.x * xs, _vp.y - b.size.y)
		b.modulate = Color(0.5, 0.6, 0.85, 0.8) if far else Color(1, 1, 1, 1)
		add_child(b)
		# an occasional rooftop antenna or water tank
		if randf() < 0.4:
			var mast := ColorRect.new()
			mast.color = Color(0.03, 0.03, 0.07, 0.98)
			mast.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var thin := randf() < 0.6
			mast.size = Vector2(_vp.x * 0.006, _vp.y * randf_range(0.03, 0.07)) if thin \
				else Vector2(b.size.x * 0.4, _vp.y * 0.02)
			mast.position = b.position + Vector2(b.size.x * randf_range(0.3, 0.7), -mast.size.y)
			add_child(mast)
		# one window flickers for life (near buildings only) — restrained
		if not far:
			for k in 1:
				var win := TextureRect.new()
				win.texture = _dot()
				win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				win.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var wd: float = _vp.x * 0.014
				win.size = Vector2(wd, wd * 1.3)
				var wcol: Color = hues[randi() % hues.size()]
				win.position = b.position + Vector2(randf_range(0.15, 0.85) * b.size.x,
					randf_range(0.12, 0.9) * b.size.y) - win.size * 0.5
				win.modulate = Color(wcol.r, wcol.g, wcol.b, 0.9)
				add_child(win)
				var tw := win.create_tween().set_loops()
				tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
				tw.tween_property(win, "modulate:a", 0.15, randf_range(0.5, 1.4))
				tw.tween_property(win, "modulate:a", 0.9, randf_range(0.5, 1.4))
		# a bright neon sign strip on the taller NEAR buildings — just a few
		if not far and bh > 0.22 and randf() < 0.45:
			var neon := ColorRect.new()
			neon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var sc_col: Color = hues[randi() % hues.size()]
			var vertical := randf() < 0.5
			neon.size = Vector2(_vp.x * 0.01, b.size.y * 0.4) if vertical \
				else Vector2(b.size.x * 0.6, _vp.x * 0.012)
			neon.pivot_offset = neon.size * 0.5
			neon.position = b.position + Vector2(b.size.x * 0.5, b.size.y * 0.35) - neon.size * 0.5
			neon.color = Color(sc_col.r, sc_col.g, sc_col.b, 0.95)
			add_child(neon)
			var glow := TextureRect.new()
			glow.texture = _round()
			glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var gs: float = maxf(neon.size.x, neon.size.y) * 2.4
			glow.size = Vector2(gs, gs)
			glow.position = neon.position + neon.size * 0.5 - glow.size * 0.5
			glow.modulate = Color(sc_col.r, sc_col.g, sc_col.b, 0.4)
			add_child(glow)
			var st := neon.create_tween().set_loops()
			st.tween_property(neon, "modulate:a", 0.5, randf_range(1.2, 2.2))
			st.tween_property(neon, "modulate:a", 1.0, randf_range(1.2, 2.2))
		xs += bw * (randf_range(0.55, 0.75) if far else randf_range(0.7, 0.9))

## A lit skyscraper facade baked once per variant: a dark front with a grid of
## windows, each independently lit (cyan / magenta / warm) or dark. Three variants
## + per-building stretch keep the skyline from repeating.
func _neon_building(v: int) -> ImageTexture:
	var sd := float(v) * 13.7
	return _shaped("neon_bldg_%d" % v, 84, 176, func(uv: Vector2) -> Color:
		return _fn_neon_building(uv, sd))

func _fn_neon_building(uv: Vector2, sd: float) -> Color:
	var p := uv * 0.5 + Vector2(0.5, 0.5)
	var cols := 5.0
	var rows := 14.0
	var cell := Vector2(floor(p.x * cols), floor(p.y * rows))
	var f := Vector2(p.x * cols - cell.x, p.y * rows - cell.y)
	# the dark facade + the frame between windows
	if f.x <= 0.26 or f.x >= 0.74 or f.y <= 0.18 or f.y >= 0.8:
		return Color(0.03, 0.03, 0.07, 1.0)
	# Realistic: most windows are dark; only about a quarter are lit.
	if _hash2(cell + Vector2(sd, sd * 0.7)) < 0.76:
		return Color(0.05, 0.05, 0.1, 1.0)              # an unlit window
	# lit — pick a neon hue and a brightness
	var pick := _hash2(cell + Vector2(sd + 7.3, 2.1))
	var hue := Color(0.32, 0.8, 1.0)                    # cyan
	if pick > 0.72:
		hue = Color(1.0, 0.85, 0.5)                     # warm
	elif pick > 0.4:
		hue = Color(1.0, 0.28, 0.72)                    # magenta
	var b := 0.45 + 0.4 * _hash2(cell + Vector2(1.7, sd + 9.2))
	return Color(hue.r * b, hue.g * b, hue.b * b, 1.0)

## Deterministic 0..1 hash of a cell coordinate (for the window lattice).
func _hash2(v: Vector2) -> float:
	return fposmod(sin(v.dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0)

# --- Premium signature motifs -------------------------------------------------
# Each premium theme gets a shape-driven identity, not a recolour: actual gold
# coins + ingots fall for Raining Gold, faceted gems for Diamond, ice shards for
# Crystal Storm, etc. Layered over the same gentle wash so it stays cohesive.

func _m_rain_gold() -> void:
	# Raining Gold, LITERALLY: gleaming golden rain streaking down in two sheets,
	# gold star-sparkles twinkling across the whole field, and a few big soft
	# molten-gold orbs floating deep in the backdrop. The coins & ingots now
	# live exclusively in the celebration confetti.
	var gold: Color = _pc("gold")
	_rain_layer(gold.lerp(_white(1.0), 0.30), 0.70, 26, 820.0, 1150.0, 1.05, 1.60, 0.07)
	_rain_layer(gold, 0.50, 40, 520.0, 800.0, 0.65, 1.00, 0.05)
	_rain_layer(gold, 0.32, 36, 300.0, 460.0, 0.40, 0.65, 0.04)
	# Gold star-sparkles hanging in the air.
	_emit({"from": "all", "tex": _sparkle(), "color": gold.lerp(_white(1.0), 0.25), "alpha": 0.9,
		"amount": 22, "lifetime": 4.5, "dir": Vector3(0, 1, 0), "spread": 180.0,
		"vmin": 2.0, "vmax": 6.0, "smin": 0.4, "smax": 0.9, "twinkle": true})
	_emit({"from": "all", "tex": _dot(), "color": gold.lerp(_white(1.0), 0.3), "alpha": 0.9,
		"amount": 26, "lifetime": 4.5, "dir": Vector3(0, 1, 0), "spread": 180.0,
		"vmin": 2.0, "vmax": 6.0, "smin": 0.3, "smax": 0.7, "twinkle": true})
	# Big soft golden orbs — the "balls" — drifting slowly deep behind the rain.
	_emit({"from": "all", "tex": _dot(), "color": gold, "alpha": 0.16,
		"amount": 8, "lifetime": 12.0, "dir": Vector3(0, -1, 0), "spread": 180.0,
		"vmin": 3.0, "vmax": 9.0, "smin": 2.6, "smax": 4.6})
	_shimmer_sweep(gold.lerp(_white(1.0), 0.2), _gen)
	_gold_hoard()

func _m_rain_silver() -> void:
	# Raining Silver: the same literal-rain treatment as Raining Gold — sheets of
	# bright silver rain, star-sparkles, and soft moonlit-silver orbs deep behind.
	# Coins & bars live in the confetti.
	var silver := Color(0.86, 0.90, 0.97)
	_rain_layer(silver.lerp(_white(1.0), 0.40), 0.70, 26, 820.0, 1150.0, 1.05, 1.60, 0.07)
	_rain_layer(silver, 0.50, 40, 520.0, 800.0, 0.65, 1.00, 0.05)
	_rain_layer(silver, 0.32, 36, 300.0, 460.0, 0.40, 0.65, 0.04)
	_emit({"from": "all", "tex": _sparkle(), "color": silver.lerp(_white(1.0), 0.3), "alpha": 0.9,
		"amount": 22, "lifetime": 4.5, "dir": Vector3(0, 1, 0), "spread": 180.0,
		"vmin": 2.0, "vmax": 6.0, "smin": 0.4, "smax": 0.9, "twinkle": true})
	_emit({"from": "all", "tex": _dot(), "color": silver, "alpha": 0.9,
		"amount": 26, "lifetime": 4.0, "dir": Vector3(0, 1, 0), "spread": 180.0,
		"vmin": 2.0, "vmax": 6.0, "smin": 0.3, "smax": 0.7, "twinkle": true})
	_emit({"from": "all", "tex": _dot(), "color": silver, "alpha": 0.14,
		"amount": 8, "lifetime": 12.0, "dir": Vector3(0, -1, 0), "spread": 180.0,
		"vmin": 3.0, "vmax": 9.0, "smin": 2.6, "smax": 4.6})
	_shimmer_sweep(Color(0.92, 0.95, 1.0), _gen)
	_silver_vault()

func _m_rain_diamond() -> void:
	# Diamond Rain — and nothing but the rain.
	#
	# What used to be here was a jeweller's TRAY: a velvet pad across the bottom
	# of the frame, fourteen loose stones lying on it and a solitaire RING
	# standing in the middle of the screen. Three things were wrong with it and
	# all three are the same thing. It was a foreground object in a motif whose
	# entire subject is the middle distance, so it fought the board for the eye;
	# it was lit and scaled as a still life while everything else in the frame
	# was weather; and it never moved, so it did not belong to the rain it was
	# sitting under — the falling stones and the parked ring shared no light, no
	# horizon and no clock.
	#
	# So the stones stay in the BACKGROUND, where the theme's name puts them,
	# and the frame gets depth instead of furniture: four falls at four scales,
	# the near one big and slow, the far one a drift of glitter, over a cold
	# refracted sky. Nothing is standing on the floor of this scene.
	var ice := Color(0.86, 0.96, 1.0)
	_diamond_sky()
	var cut := _brilliant()
	# FAR — a haze of stones too distant to resolve into facets.
	_emit({"from": "all", "tex": cut, "color": ice, "alpha": 0.46,
		"amount": 40, "lifetime": 11.0, "dir": Vector3(0.05, 1, 0), "spread": 12.0,
		"vmin": 40.0, "vmax": 90.0, "smin": 0.16, "smax": 0.34, "spin": 0.7})
	# MID — the body of the fall.
	_emit({"from": "all", "tex": cut, "color": ice, "alpha": 0.95,
		"amount": 32, "lifetime": 8.5, "dir": Vector3(0.06, 1, 0), "spread": 10.0,
		"vmin": 90.0, "vmax": 200.0, "smin": 0.42, "smax": 0.85, "spin": 1.1,
		"twinkle": true})
	# NEAR — a few big ones turning past the lens, slow enough to read as cut.
	_emit({"from": "top", "tex": cut, "color": _white(1.0), "alpha": 0.95,
		"amount": 8, "lifetime": 7.5, "dir": Vector3(0.09, 1, 0), "spread": 8.0,
		"vmin": 130.0, "vmax": 260.0, "smin": 1.3, "smax": 2.2, "spin": 1.6})
	# Diamond DUST: the chips, hanging almost still and catching everything.
	_emit({"from": "all", "tex": _dot(),
		"iramp": _ramp_cols([_white(1.0), Color(0.72, 0.92, 1.0),
			Color(0.86, 0.80, 1.0), Color(0.78, 1.0, 0.96)]),
		"alpha": 1.0, "amount": 40, "lifetime": 3.4, "dir": Vector3(0, 1, 0),
		"spread": 180.0, "vmin": 1.0, "vmax": 6.0, "smin": 0.20, "smax": 0.62,
		"twinkle": true})
	# The light catching, and running across the frame.
	_diamond_glints(_gen)
	_ambient_flash(Color(0.82, 0.95, 1.0), 0.14, 5.0, 10.0)
	_shimmer_sweep(_pc("accent"), _gen)
	_edge_glow(ice, 0.05, 0.13, true)
	_edge_glow(ice, 0.04, 0.10, false)

## The sky the stones are falling through: cold refracted light. A diamond has
## nothing to be brilliant AGAINST in a flat black frame — every glint in the
## fall is a reflection of something, so there has to be something.
func _diamond_sky() -> void:
	var ice := Color(0.72, 0.90, 1.0)
	# Slow columns of cold light, like sun through deep ice.
	for i in 5:
		var ray := TextureRect.new()
		ray.texture = _round()
		ray.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ray.stretch_mode = TextureRect.STRETCH_SCALE
		ray.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.18, 0.42)
		ray.size = Vector2(w, _vp.y * randf_range(0.7, 1.2))
		ray.pivot_offset = Vector2(w * 0.5, 0.0)
		ray.position = Vector2(_vp.x * (0.04 + 0.24 * float(i)) - w * 0.5, -_vp.y * 0.08)
		ray.rotation = deg_to_rad(randf_range(-11.0, 11.0))
		var peak: float = randf_range(0.04, 0.09)
		ray.modulate = Color(ice.r, ice.g, ice.b, peak * 0.4)
		add_child(ray)
		var tw := ray.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(randf_range(0.0, 4.0))
		tw.tween_property(ray, "modulate:a", peak, randf_range(4.5, 7.5))
		tw.tween_property(ray, "modulate:a", peak * 0.2, randf_range(5.0, 8.0))
	# The FIRE: broad, very faint spectral washes drifting across each other.
	# This is the one place colour is allowed into the coldest palette in the
	# catalogue, and it is the reason the white stones read as diamond rather
	# than as glass — dispersion is the whole difference.
	# A cold ceiling for it all to hang from — without it the top of the frame
	# is flat black and the far stones have nothing to fall out of.
	for e_v in [[1.9, 0.09, 0.02], [1.2, 0.07, 0.30]]:
		var e: Array = e_v
		var lid := TextureRect.new()
		lid.texture = _round()
		lid.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lid.stretch_mode = TextureRect.STRETCH_SCALE
		lid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = _vp.x * float(e[0])
		lid.size = Vector2(d, d * 0.55)
		lid.position = Vector2(_vp.x * 0.5 - d * 0.5, _vp.y * float(e[2]) - lid.size.y * 0.5)
		lid.modulate = Color(ice.r, ice.g, ice.b, float(e[1]))
		add_child(lid)
	# Cold half of the spectrum only. An earlier pass included a warm gold wash,
	# and where it crossed the cyan one the two multiplied down to olive — the
	# one colour a diamond scene cannot have in it. Dispersion in a white stone
	# throws blue, violet and green far more than it throws yellow anyway.
	var fire := [Color(0.42, 0.82, 1.0), Color(0.86, 0.58, 1.0),
		Color(0.60, 1.0, 0.90), Color(0.62, 0.70, 1.0)]
	for i in fire.size():
		var wash := TextureRect.new()
		wash.texture = _round()
		wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		wash.stretch_mode = TextureRect.STRETCH_SCALE
		wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = _vp.x * randf_range(0.9, 1.5)
		wash.size = Vector2(d, d * randf_range(0.6, 1.0))
		var home := Vector2(_vp.x * randf_range(0.05, 0.95),
			_vp.y * randf_range(0.10, 0.90)) - wash.size * 0.5
		wash.position = home
		var c: Color = fire[i]
		wash.modulate = Color(c.r, c.g, c.b, 0.07)
		add_child(wash)
		var tw2 := wash.create_tween().set_loops()
		tw2.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw2.set_parallel(true)
		tw2.tween_property(wash, "position",
			home + Vector2(randf_range(-0.2, 0.2) * _vp.x, randf_range(-0.15, 0.15) * _vp.y),
			randf_range(13.0, 20.0))
		tw2.tween_property(wash, "modulate:a", randf_range(0.16, 0.26), randf_range(6.0, 9.0))
		tw2.chain().tween_property(wash, "position", home, randf_range(13.0, 20.0))
		tw2.parallel().tween_property(wash, "modulate:a", 0.05, randf_range(6.0, 9.0))

## The twinkle. A stone catching the light is a HARD, brief, four-pointed star
## — the flash is over in a tenth of a second, and it is that speed, not the
## brightness, that reads as a cut surface. A particle field cannot do it: every
## particle in one shares a single alpha curve, so a field twinkles in unison or
## not at all. So the glints are their own loop, popping at random over the
## frame, unattached to any particular stone.
func _diamond_glints(gen: int) -> void:
	var glint := _shaped("dia_glint", 40, 40, _fn_star4_glint)
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(0.16, 0.60)).timeout
		if gen != _gen or not is_inside_tree():
			return
		var g := TextureRect.new()
		g.texture = glint
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_SCALE
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = _vp.x * randf_range(0.05, 0.20)
		g.size = Vector2(d, d)
		g.pivot_offset = g.size * 0.5
		g.position = Vector2(_vp.x * randf_range(0.02, 0.98),
			_vp.y * randf_range(0.02, 0.98)) - g.size * 0.5
		g.rotation = randf() * PI
		# A cold white with a hint of whichever fire it happened to catch.
		var fc: Array = [Color(1, 1, 1), Color(0.82, 0.94, 1.0), Color(1.0, 0.92, 0.98)]
		var c: Color = fc[randi() % fc.size()]
		g.modulate = Color(c.r, c.g, c.b, 0.0)
		add_child(g)
		var tw := g.create_tween()
		tw.tween_property(g, "modulate:a", randf_range(0.55, 1.0), 0.07)
		tw.parallel().tween_property(g, "scale", Vector2(1.25, 1.25), 0.30)
		tw.tween_property(g, "modulate:a", 0.0, randf_range(0.22, 0.45))
		tw.tween_callback(g.queue_free)

func _m_crystal() -> void:
	# Crystal Storm: a driving blizzard of ice shards + faceted gems, fine ice dust,
	# a frost glow and frequent prismatic flashes.
	_emit({"from": "all", "tex": _shard(), "color": Color(0.80, 0.93, 1.0), "alpha": 0.85,
		"amount": 48, "lifetime": 6.0, "dir": Vector3(0.24, 1, 0), "spread": 40.0,
		"vmin": 130.0, "vmax": 320.0, "smin": 0.6, "smax": 1.8, "spin": 2.8})
	_emit({"from": "all", "tex": _gem(), "color": _pc("accent2"), "alpha": 0.9,
		"amount": 24, "lifetime": 5.0, "dir": Vector3(0.1, 1, 0), "spread": 22.0,
		"vmin": 90.0, "vmax": 220.0, "smin": 0.4, "smax": 1.1, "spin": 1.5, "twinkle": true})
	# Fine ice dust driving across for a sense of speed.
	_emit({"from": "all", "tex": _dot(), "color": Color(0.86, 0.95, 1.0), "alpha": 0.5,
		"amount": 60, "lifetime": 6.5, "dir": Vector3(0.28, 1, 0), "spread": 44.0,
		"vmin": 70.0, "vmax": 190.0, "smin": 0.2, "smax": 0.5, "twinkle": true})
	_ambient_flash(Color(0.72, 0.9, 1.0), 0.16, 3.0, 7.0)
	_shimmer_sweep(_pc("accent2"), _gen)
	_edge_glow(Color(0.70, 0.90, 1.0), 0.06, 0.16, true)
	_ice_cavern()

func _m_embers_lux() -> void:
	# Ember Cave: dense rising embers, drifting ash, and a molten glow that breathes
	# up from the cave floor.
	_emit({"from": "bottom", "tex": _dot(), "color": _pc("accent").lerp(_pc("gold"), 0.4),
		"alpha": 0.9, "amount": 84, "lifetime": 5.5, "dir": Vector3(0, -1, 0), "spread": 24.0,
		"vmin": 40.0, "vmax": 115.0, "smin": 0.4, "smax": 1.5, "twinkle": true})
	_emit({"from": "all", "tex": _dot(), "color": Color(0.36, 0.32, 0.30), "alpha": 0.32,
		"amount": 26, "lifetime": 9.0, "dir": Vector3(0.1, -1, 0), "spread": 42.0,
		"vmin": 14.0, "vmax": 40.0, "smin": 0.4, "smax": 1.0})
	_edge_glow(_pc("accent").lerp(_pc("gold"), 0.3), 0.10, 0.24, false)
	_drips(_gen, _pc("accent").lerp(_pc("gold"), 0.3))

func _m_deep_sea() -> void:
	# Coral Depths: a real reef — coral fans swaying on the bottom and fish drifting
	# through — under rising bubbles, drifting plankton and soft caustic light.
	_m_bubbles()
	_reef()
	_emit({"from": "all", "tex": _dot(), "color": _pc("accent").lerp(_white(1.0), 0.4),
		"alpha": 0.6, "amount": 30, "lifetime": 6.0, "dir": Vector3(0, -1, 0), "spread": 180.0,
		"vmin": 4.0, "vmax": 14.0, "smin": 0.25, "smax": 0.6, "twinkle": true})
	_edge_glow(Color(0.4, 0.82, 1.0), 0.05, 0.10, true)
	# Moving caustic light bands rippling down from the surface (shader).
	_caustics(Color(0.42, 0.82, 1.0))
	_reef_bed()

## The reef floor: a mix of branching staghorn coral and gorgonian sea fans in
## muted, realistic hues, swaying in the surge — with fish at two depths, a pair
## drifting far behind the coral and a pair passing in front.
func _reef() -> void:
	# the far fish first, so the coral overlaps them (depth).
	_reef_fish(0, true)
	_reef_fish(1, true)
	var stag := _shaped("coral_stag", 84, 84, _fn_coral)
	var fan := _shaped("coral_seafan", 88, 88, _fn_seafan)
	# Muted reef hues — terracotta, burgundy, dusty violet, olive — not candy.
	var tints := [Color(0.72, 0.38, 0.30), Color(0.55, 0.27, 0.33),
		Color(0.47, 0.36, 0.52), Color(0.58, 0.48, 0.32), Color(0.62, 0.42, 0.44)]
	# [x-frac, sea fan?, width-frac, back row?]
	var pieces := [
		[0.14, 1.0, 0.30, 1.0], [0.52, 0.0, 0.26, 1.0], [0.86, 1.0, 0.28, 1.0],
		[0.05, 0.0, 0.20, 0.0], [0.36, 1.0, 0.19, 0.0], [0.68, 0.0, 0.22, 0.0],
		[0.95, 0.0, 0.17, 0.0],
	]
	for i in pieces.size():
		var e: Array = pieces[i]
		var back := float(e[3]) > 0.5
		var w: float = _vp.x * float(e[2]) * randf_range(0.92, 1.1)
		var h: float = w * randf_range(1.0, 1.25)
		var c := TextureRect.new()
		c.texture = fan if float(e[1]) > 0.5 else stag
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c.stretch_mode = TextureRect.STRETCH_SCALE
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.size = Vector2(w, h)
		c.pivot_offset = Vector2(w * 0.5, h)      # sway from the holdfast
		c.position = Vector2(_vp.x * float(e[0]) - w * 0.5, _vp.y - h + _vp.y * 0.02)
		var t: Color = tints[i % tints.size()]
		if back:
			# the back row sinks into the blue water haze
			t = t.lerp(_pc("bg0"), 0.45)
		c.modulate = Color(t.r, t.g, t.b, 0.42 if back else 0.62)
		add_child(c)
		var amp := 0.018 if back else 0.03        # the surge, gentle and slow
		var sw := c.create_tween().set_loops()
		sw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		sw.tween_property(c, "rotation", amp, randf_range(3.6, 5.2))
		sw.tween_property(c, "rotation", -amp, randf_range(3.6, 5.2))
	_reef_fish(2, false)
	_reef_fish(3, false)

## One fish crossing the water on a slow loop — small, muted, half-lost in the
## haze like a real fish at distance; `far` ones swim deeper, dimmer, slower.
func _reef_fish(i: int, far: bool) -> void:
	var w: float = _vp.x * (randf_range(0.045, 0.065) if far else randf_range(0.06, 0.095))
	var ltr := randf() < 0.5
	var fish := TextureRect.new()
	fish.texture = _shaped("reef_fish_r", 80, 46, _fn_fish)
	fish.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fish.stretch_mode = TextureRect.STRETCH_SCALE
	fish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fish.flip_h = not ltr                          # the bake faces right
	fish.size = Vector2(w, w * 0.57)
	fish.pivot_offset = fish.size * 0.5
	var y0: float = _vp.y * randf_range(0.30, 0.88)
	# Muted, watery tints — silver-blue, olive, dusky rose — hazed when far.
	var tint: Color = [Color(0.70, 0.76, 0.84), Color(0.62, 0.64, 0.48),
		Color(0.72, 0.56, 0.52), Color(0.6, 0.68, 0.72)][i % 4]
	if far:
		tint = tint.lerp(_pc("bg0"), 0.4)
	fish.modulate = Color(tint.r, tint.g, tint.b, 0.55 if far else 0.8)
	fish.position = Vector2((-w * 2.0) if ltr else _vp.x, y0)
	add_child(fish)
	var dur: float = randf_range(24.0, 34.0) if far else randf_range(16.0, 24.0)
	var target: float = (_vp.x + w) if ltr else (-w * 2.0)
	var reset: float = (-w * 2.0) if ltr else (_vp.x + w)
	var cross := fish.create_tween().set_loops()
	cross.tween_property(fish, "position:x", target, dur)
	cross.tween_callback(func(): fish.position.x = reset)
	var bob := fish.create_tween().set_loops()
	bob.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	bob.tween_property(fish, "position:y", y0 - _vp.y * 0.02, randf_range(1.8, 2.8))
	bob.tween_property(fish, "position:y", y0 + _vp.y * 0.02, randf_range(1.8, 2.8))
	# the faint nose-down / nose-up pitch of a swimming fish
	var tilt: float = 0.05 if ltr else -0.05
	var wob := fish.create_tween().set_loops()
	wob.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	wob.tween_property(fish, "rotation", tilt, randf_range(1.8, 2.8))
	wob.tween_property(fish, "rotation", -tilt, randf_range(1.8, 2.8))

# Staghorn branch skeleton as explicit SEGMENT PAIRS (p1, p2 per segment) —
# curved arms built from short chained segments — plus the growth-tip points.
const _STAG_SEGS := [
	Vector2(0.05, 1.0), Vector2(0.0, 0.55), Vector2(0.0, 0.55), Vector2(-0.06, 0.2),
	Vector2(-0.06, 0.2), Vector2(-0.30, -0.08), Vector2(-0.30, -0.08), Vector2(-0.44, -0.45),
	Vector2(-0.44, -0.45), Vector2(-0.50, -0.78),
	Vector2(-0.30, -0.08), Vector2(-0.16, -0.40), Vector2(-0.16, -0.40), Vector2(-0.12, -0.64),
	Vector2(-0.44, -0.45), Vector2(-0.63, -0.60), Vector2(-0.63, -0.60), Vector2(-0.72, -0.84),
	Vector2(-0.06, 0.2), Vector2(0.22, 0.0), Vector2(0.22, 0.0), Vector2(0.38, -0.34),
	Vector2(0.38, -0.34), Vector2(0.45, -0.68),
	Vector2(0.38, -0.34), Vector2(0.57, -0.50), Vector2(0.57, -0.50), Vector2(0.66, -0.78),
	Vector2(0.22, 0.0), Vector2(0.15, -0.33), Vector2(0.15, -0.33), Vector2(0.20, -0.58),
	Vector2(-0.06, 0.2), Vector2(0.02, -0.14), Vector2(0.02, -0.14), Vector2(-0.02, -0.44),
]
const _STAG_TIPS := [
	Vector2(-0.50, -0.78), Vector2(-0.12, -0.64), Vector2(-0.72, -0.84),
	Vector2(0.45, -0.68), Vector2(0.66, -0.78), Vector2(0.20, -0.58), Vector2(-0.02, -0.44),
]

## A staghorn coral: curved, tapering branch chains with pale growth tips —
## the classic Acropora silhouette rather than a straight-armed broom.
func _fn_coral(uv: Vector2) -> Color:
	var a := 0.0
	var i := 0
	while i < _STAG_SEGS.size():
		var p1: Vector2 = _STAG_SEGS[i]
		var p2: Vector2 = _STAG_SEGS[i + 1]
		var mean_h := (p1.y + p2.y) * 0.5
		var th := lerpf(0.115, 0.038, clampf((1.0 - mean_h) * 0.55, 0.0, 1.0))
		a = maxf(a, 1.0 - smoothstep(th * 0.72, th, _seg_dist(uv, p1, p2)))
		i += 2
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	# shading: darker at the base, and PALE growth tips (live Acropora)
	var b := 0.42 + 0.28 * clampf(-uv.y * 0.7 + 0.3, 0.0, 1.0)
	for tp_v in _STAG_TIPS:
		var tp: Vector2 = tp_v
		var k := 1.0 - smoothstep(0.03, 0.14, uv.distance_to(tp))
		b = maxf(b, lerpf(b, 0.95, k))
	return Color(b, b * 0.92, b * 0.9, clampf(a, 0.0, 1.0))

## A gorgonian sea fan: a ragged half-disc membrane of radial ribs with faint
## concentric lattice strands, on a short stem — translucent like the real thing.
func _fn_seafan(uv: Vector2) -> Color:
	var origin := Vector2(0.0, 0.92)
	var d := uv - origin
	var r := d.length()
	var ang := atan2(d.x, -d.y)     # 0 = straight up, ± toward the sides
	var a := 0.0
	var b := 0.5
	if absf(ang) < 1.25:
		var edge := 1.62 + 0.09 * sin(ang * 4.7 + 1.0) + 0.06 * sin(ang * 9.3)
		if r < edge and r > 0.12:
			# radial ribs + faint concentric strands = the fan's mesh
			var rib := pow(0.5 + 0.5 * sin(ang * 30.0), 2.6)
			var ring := pow(0.5 + 0.5 * sin(r * 26.0), 2.0)
			a = 0.16 + 0.62 * rib + 0.18 * ring
			a *= 1.0 - smoothstep(edge - 0.22, edge, r)     # ragged outer fade
			a *= smoothstep(0.12, 0.30, r)                   # open at the base
			b = 0.42 + 0.22 * (r / edge)                     # lighter toward the rim
	# the stem / holdfast
	if absf(uv.x) < 0.05 - (uv.y - 0.6) * 0.02 and uv.y > 0.55:
		a = maxf(a, 0.9)
		b = 0.3
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	return Color(b, b * 0.94, b * 0.9, clampf(a, 0.0, 1.0))

## A realistic side-view reef fish, facing right: fusiform body arched along the
## spine, forked tail, curved dorsal + small anal fin, translucent pectoral,
## counter-shaded flanks (dark back, pale belly), gill-cover line and eye.
func _fn_fish(uv: Vector2) -> Color:
	var x := uv.x
	var y := uv.y
	var a := 0.0
	var fin := 0.0
	# body: half-height profile along the length — pointed snout (x=0.72),
	# deepest just ahead of centre, pinched at the caudal peduncle (x=-0.5)
	var t := clampf((x + 0.5) / 1.22, 0.0, 1.0)
	var hh := 0.34 * pow(sin(PI * pow(t, 0.78)), 0.9)
	if x > -0.5 and x < 0.72 and absf(y) < maxf(hh, 0.05):
		a = 1.0
	# forked caudal fin
	if x <= -0.44 and x > -0.98:
		var u := (-0.44 - x) / 0.54
		if absf(y) < 0.1 + 0.38 * u and absf(y) > 0.30 * u:
			fin = maxf(fin, 0.8)
	# dorsal fin: a low arc riding the back
	if x > -0.28 and x < 0.34:
		var ft := (x + 0.28) / 0.62
		var fh := 0.15 * sin(PI * ft)
		var back := -hh
		if y < back and y > back - fh:
			fin = maxf(fin, 0.75)
	# small anal fin under the rear belly
	if x > -0.3 and x < -0.05:
		var ft2 := (x + 0.3) / 0.25
		var fh2 := 0.09 * sin(PI * ft2)
		if y > hh and y < hh + fh2:
			fin = maxf(fin, 0.7)
	a = maxf(a, fin)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# counter-shading: dark back fading to a pale belly
	var col := lerpf(0.38, 0.95, smoothstep(-0.3, 0.3, y))
	# the gill cover: a faint curved line behind the head
	var gill := absf(uv.distance_to(Vector2(0.58, 0.02)) - 0.3)
	if gill < 0.015 and x < 0.5 and absf(y) < hh:
		col *= 0.78
	# translucent pectoral fin just behind the gill
	var pf := Vector2(x - 0.26, y - 0.06)
	if pf.x < 0.0 and pf.x > -0.22 and absf(pf.y - pf.x * 0.35) < 0.05 + pf.x * 0.14:
		col *= 0.86
	# the eye, set high on the head
	var ed := uv.distance_to(Vector2(0.5, -0.08))
	if ed < 0.075:
		col = 0.06 if ed < 0.05 else 0.85
	return Color(col, col, col, clampf(a, 0.0, 1.0) * (0.85 if fin > 0.0 and fin >= a else 1.0))

func _m_biolum() -> void:
	# Bioluminescence — the abyss, where the only light in the water is alive.
	#
	# Built in DEPTH PLANES rather than as one flat field, which is what the old
	# version was: 194 evenly-lit dots rising through the frame read as a
	# starfield, and five copies of one giant coil over it read as wallpaper.
	# Back to front now: the water column itself, a dim far haze, marine snow
	# sifting DOWN through it (the single cue that separates deep water from deep
	# space — nothing in space falls), then the near plankton you can pick out as
	# individuals, the grove burning on the floor and medusae drifting between.
	# Nothing here is lit from outside; every glow in the frame is an organism.
	var bio: Color = _pc("accent")                        # the flash cyan
	var deep: Color = _pc("accent2")                      # its violet partner
	var bright: Color = bio.lerp(_white(1.0), 0.32)
	_biolum_column(bio, deep)
	# The far haze: dense, dim, slow — depth, not detail.
	_emit({"from": "all", "tex": _dot(), "color": bio.lerp(_white(1.0), 0.55),
		"alpha": 0.40, "amount": 92, "lifetime": 11.0, "dir": Vector3(0.25, -1, 0),
		"spread": 62.0, "vmin": 2.0, "vmax": 7.0, "smin": 0.10, "smax": 0.26,
		"turb": 0.9, "twinkle": true})
	# Marine snow: detritus falling through the column, unlit and unhurried, and
	# the single strongest "this is real footage" cue in the frame — every ROV
	# clip of the deep sea is full of it, and nothing in SPACE falls.
	_emit({"from": "top", "tex": _dot(), "color": _white(1.0).lerp(bio, 0.30),
		"alpha": 0.34, "amount": 46, "lifetime": 15.0, "dir": Vector3(0.10, 1, 0),
		"spread": 24.0, "vmin": 10.0, "vmax": 26.0, "smin": 0.14, "smax": 0.46,
		"turb": 1.2})
	# Foreground snow: big soft flecks falling PAST the lens, out of focus. The
	# cheapest depth cue there is, and the frame reads as a camera in the water
	# rather than as a flat picture of it.
	_emit({"from": "top", "tex": _round(), "color": _white(1.0).lerp(bio, 0.25),
		"alpha": 0.07, "amount": 9, "lifetime": 11.0, "dir": Vector3(0.06, 1, 0),
		"spread": 16.0, "vmin": 34.0, "vmax": 70.0, "smin": 0.10, "smax": 0.24,
		"turb": 0.6})
	# The near plankton: few, big, hot, quick — the layer that reads as creatures.
	_emit({"from": "all", "tex": _dot(), "color": bright,
		"alpha": 1.0, "amount": 26, "lifetime": 6.0, "dir": Vector3(0.20, -1, 0),
		"spread": 72.0, "vmin": 6.0, "vmax": 18.0, "smin": 0.46, "smax": 1.15,
		"turb": 1.5, "twinkle": true})
	# Gas seeping up out of the sediment.
	_emit({"from": "bottom", "tex": _bubble(), "color": bright,
		"alpha": 0.34, "amount": 14, "lifetime": 8.5, "dir": Vector3(0, -1, 0),
		"spread": 14.0, "vmin": 22.0, "vmax": 55.0, "smin": 0.25, "smax": 0.8,
		"turb": 0.8})
	# The violet ceiling: what is left of the light, a long way above.
	_edge_glow(deep, 0.035, 0.085, true)
	_jellyfish()
	_biolum_combs()
	_biolum_grove()
	_biolum_bloom_layer(bio)   # added last: every reaction lights it from above

## The water itself. Two static gradients and no tween: a theme whose middle is
## deliberately empty still has to read as WATER, and painting the floor teal
## under a violet-black surface is what gives the empty half a direction. Costs
## two quads and nothing per frame.
func _biolum_column(bio: Color, deep: Color) -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 0.88, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.12),
		Color(1, 1, 1, 0.55), Color(1, 1, 1, 1)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 4
	tex.height = 160
	var floor_wash := TextureRect.new()
	floor_wash.texture = tex
	floor_wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	floor_wash.stretch_mode = TextureRect.STRETCH_SCALE
	floor_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_wash.size = _vp
	var water: Color = bio.lerp(deep, 0.45)
	floor_wash.modulate = Color(water.r, water.g, water.b, 0.085)
	add_child(floor_wash)
	# A cold violet haze up top, so the column has a far end.
	var ceil_wash := TextureRect.new()
	ceil_wash.texture = tex
	ceil_wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ceil_wash.stretch_mode = TextureRect.STRETCH_SCALE
	ceil_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ceil_wash.size = _vp
	ceil_wash.position = Vector2(0.0, _vp.y)
	ceil_wash.scale = Vector2(1.0, -1.0)          # flipped: the ramp climbs upward
	ceil_wash.modulate = Color(deep.r, deep.g, deep.b, 0.10)
	add_child(ceil_wash)

## The living floor. Every organism in it is a real one — sea pens, gorgonian
## fans, the sediment bank they root in — because "real" is the whole brief for
## this theme and a neon coil is the least real thing that can be drawn in water.
##
## Three rules hold the illusion together, and each one was learned by breaking
## it: bodies are DARK (a shape drawn as bright line-work tints out as neon
## strip-lighting), the light is BLUE-CYAN and almost nothing else (the sea
## swallows every other wavelength within metres, so a magenta plant reads as
## Vaporwave), and depth is carried by ALPHA — the far rank is dim and small and
## sits higher in the frame, the way distance actually works down there.
func _biolum_grove() -> void:
	var bio: Color = _pc("accent")
	var cyan := bio.lerp(Color(0.35, 1.00, 0.92), 0.45)
	var blue := _pc("accent2").lerp(Color(0.30, 0.62, 1.00), 0.55)
	var picks: Array = [cyan, blue, cyan, cyan.lerp(blue, 0.5)]
	# The floor glow the whole grove stands in.
	_edge_glow(cyan, 0.035, 0.09, false)
	_biolum_siphonophores(picks)
	# --- The bed ---
	# [x-frac, height-frac of vp.y, colour, lean, species, depth 0 near .. 1 far]
	var beds := [
		# One colony dominates and is cropped by the frame edge, the rest fall
		# away behind it. An evenly sized row across the bottom reads as a hedge,
		# and nothing in the sea grows in a hedge.
		[0.03, 0.44, 0, 1.0, "pen", 0.0],
		[0.17, 0.15, 1, -1.0, "fan", 0.75],
		[0.30, 0.27, 0, 1.0, "pen", 0.2],
		[0.44, 0.13, 2, 1.0, "pen", 0.7],
		[0.58, 0.21, 1, -1.0, "fan", 0.3],
		[0.71, 0.19, 3, 1.0, "pen", 0.5],
		[0.85, 0.12, 0, -1.0, "fan", 0.6],
		[0.97, 0.30, 2, 1.0, "pen", 0.1],
	]
	for b_v in beds:
		var e: Array = b_v
		var species := String(e[4])
		var far: float = float(e[5])
		var pivot := Control.new()
		pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Distance lifts the base up the frame: the floor recedes, it does not
		# stay level with your feet.
		pivot.position = Vector2(_vp.x * float(e[0]), _vp.y * lerpf(1.02, 0.90, far))
		add_child(pivot)
		var h: float = _vp.y * float(e[1])
		var tex: ImageTexture
		var aspect := 1.0
		if species == "pen":
			tex = _shaped("biolum_pen", 128, 208, _fn_bio_pen)
			aspect = 128.0 / 208.0
		else:
			tex = _shaped("biolum_fan", 150, 118, _fn_bio_fan)
			aspect = 150.0 / 118.0
		var w: float = h * aspect
		var fc: Color = picks[int(e[2])]
		var peak: float = lerpf(0.90, 0.30, far)
		# The bloom AROUND THE LIGHT: a soft glow centred on the organ that emits
		# (a sea pen's polyps are all over its plume, a fan's along its crown), so
		# the animal lights the water around itself. This used to be a 1.45x
		# scaled copy of the sprite offset up the frame, which on a tall bake
		# renders as a second blurred plant hanging above the real one.
		var crown_y: float = -h * (0.50 if species == "fan" else 0.62)
		var halo := TextureRect.new()
		halo.texture = _round()
		halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		halo.stretch_mode = TextureRect.STRETCH_SCALE
		halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hd: float = w * 1.5
		halo.size = Vector2(hd, hd)
		halo.position = Vector2(-hd * 0.5, crown_y - hd * 0.5)
		halo.modulate = Color(fc.r, fc.g, fc.b, 0.09 * peak)
		pivot.add_child(halo)
		var plant := TextureRect.new()
		plant.texture = tex
		plant.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		plant.stretch_mode = TextureRect.STRETCH_SCALE
		plant.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plant.size = Vector2(w, h)
		plant.position = Vector2(-w * 0.5, -h)
		plant.modulate = Color(fc.r, fc.g, fc.b, peak * 0.9)
		pivot.add_child(plant)
		# The animal breathing light — body and bloom on the same slow clock.
		var ph: float = randf_range(0.0, 3.0)
		var pulse := plant.create_tween().set_loops()
		pulse.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		pulse.tween_interval(ph)
		pulse.tween_property(plant, "modulate:a", peak, randf_range(2.4, 3.8))
		pulse.tween_property(plant, "modulate:a", peak * 0.6, randf_range(2.8, 4.4))
		var hpulse := halo.create_tween().set_loops()
		hpulse.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		hpulse.tween_interval(ph)
		hpulse.tween_property(halo, "modulate:a", 0.17 * peak, randf_range(2.4, 3.8))
		hpulse.tween_property(halo, "modulate:a", 0.06 * peak, randf_range(2.8, 4.4))
		# Leaning on the current. A sea pen is a soft animal in slow water: the
		# whole colony sways, it does not nod.
		var sway := pivot.create_tween().set_loops()
		sway.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		var amp: float = randf_range(0.020, 0.048) * float(e[3])
		sway.tween_property(pivot, "rotation", amp, randf_range(6.0, 9.0))
		sway.tween_property(pivot, "rotation", -amp * 0.7, randf_range(6.5, 9.5))
	_biolum_seafloor(cyan)
	# --- Larvae drifting free above the bed ---
	_emit({"from": "all", "tex": _shaped("biolum_seed", 40, 40, _fn_seed_sprite),
		"color": cyan, "alpha": 0.45, "amount": 14, "lifetime": 13.0,
		"dir": Vector3(0.1, -1, 0), "spread": 40.0, "vmin": 6.0, "vmax": 20.0,
		"smin": 0.5, "smax": 1.3, "spin": 0.4, "turb": 1.0, "twinkle": true})
	_biolum_school(_gen)

## Siphonophores: colonial animals that hang in the water column as a chain of
## lit bodies, tens of metres of them, drifting nose-up. They are what the frame
## needed hanging from above — the first pass hung "tendrils" from a canopy,
## which is a rainforest idea. There is no canopy at this depth; there is a
## siphonophore, and it is one of the most-filmed sights in the deep sea.
func _biolum_siphonophores(picks: Array) -> void:
	var chain_tex := _shaped("biolum_chain", 48, 224, _fn_bio_chain)
	# Fixed lanes, clear of the medusae's: a chain hanging dead straight through a
	# bell reads as a puppet string.
	for xf_v in [0.37, 0.68]:
		var xf: float = xf_v
		var pivot := Control.new()
		pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pivot.position = Vector2(_vp.x * (xf + randf_range(-0.04, 0.04)),
			-_vp.y * randf_range(0.02, 0.10))
		add_child(pivot)
		var h: float = _vp.y * randf_range(0.26, 0.44)
		var w: float = h * (48.0 / 224.0)
		var chain := TextureRect.new()
		chain.texture = chain_tex
		chain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		chain.stretch_mode = TextureRect.STRETCH_SCALE
		chain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chain.size = Vector2(w, h)
		chain.position = Vector2(-w * 0.5, 0.0)
		var tc: Color = picks[int(xf * 7.0) % picks.size()]
		chain.modulate = Color(tc.r, tc.g, tc.b, 0.34)
		pivot.add_child(chain)
		var tt := chain.create_tween().set_loops()
		tt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tt.tween_interval(randf_range(0.0, 2.5))
		tt.tween_property(chain, "modulate:a", 0.58, randf_range(2.4, 3.6))
		tt.tween_property(chain, "modulate:a", 0.24, randf_range(2.8, 4.2))
		# The colony trails from a float at the top, so it pivots up there.
		var sw := pivot.create_tween().set_loops()
		sw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		var amp: float = randf_range(0.04, 0.10)
		sw.tween_property(pivot, "rotation", amp, randf_range(5.5, 8.0))
		sw.tween_property(pivot, "rotation", -amp, randf_range(5.5, 8.0))

## The sediment the grove roots in: two dark banks at different distances, the
## near one in FRONT of the plants so their bases disappear into it the way a
## real floor swallows them, and the scatter of small lights a real floor
## carries. Specks, drawn as one barely-moving twinkling field rather than as
## clusters — a bioluminescent seabed is a dusting of points, not a fruit bowl.
func _biolum_seafloor(cyan: Color) -> void:
	var tex := _shaped("biolum_floor", 160, 64, _fn_bio_floor)
	# [y-frac of the crest, height-frac, alpha] — far bank first, near bank over it
	for b_v in [[0.905, 0.10, 0.55], [0.965, 0.14, 0.95]]:
		var b: Array = b_v
		var h: float = _vp.y * float(b[1])
		var bank := TextureRect.new()
		bank.texture = tex
		bank.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bank.stretch_mode = TextureRect.STRETCH_SCALE
		bank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bank.size = Vector2(_vp.x * 1.05, h)
		bank.position = Vector2(-_vp.x * 0.025, _vp.y * float(b[0]))
		# Tinted with the water, not with the light: sediment does not glow.
		var mud: Color = _pc("bg0").lerp(cyan, 0.35)
		bank.modulate = Color(mud.r, mud.g, mud.b, float(b[2]))
		add_child(bank)
	# The dusting: a static-ish twinkling field pinned to the floor.
	_emit({"from": "bottom", "tex": _dot(), "color": cyan.lerp(_white(1.0), 0.25),
		"alpha": 0.75, "amount": 26, "lifetime": 5.0, "dir": Vector3(0, -1, 0),
		"spread": 40.0, "vmin": 1.0, "vmax": 5.0, "smin": 0.14, "smax": 0.40,
		"twinkle": true})

## A school of small lit fish crossing the frame every so often, all together,
## the way real schools move: one direction, one speed, slight vertical spread.
func _biolum_school(gen: int) -> void:
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(5.0, 11.0)).timeout
		if gen != _gen or not is_inside_tree():
			return
		var dir: float = 1.0 if randf() < 0.5 else -1.0
		var y0: float = _vp.y * randf_range(0.12, 0.80)
		var col: Color = _pc("accent").lerp(Color(0.5, 1.0, 0.9), randf_range(0.2, 0.7))
		var n := maxi(int(9.0 * _particle_scale()), 3)
		for i in n:
			var fish := TextureRect.new()
			fish.texture = _shaped("biolum_fish", 48, 22, _fn_lit_fish)
			fish.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			fish.stretch_mode = TextureRect.STRETCH_SCALE
			fish.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var fw: float = _vp.x * randf_range(0.045, 0.075)
			fish.size = Vector2(fw, fw * 0.46)
			fish.pivot_offset = fish.size * 0.5
			fish.scale = Vector2(dir, 1.0)
			var y: float = y0 + _vp.y * randf_range(-0.06, 0.06)
			var x0: float = -fw * 2.0 if dir > 0.0 else _vp.x + fw * 2.0
			fish.position = Vector2(x0 - float(i) * fw * dir * randf_range(0.8, 1.6), y)
			fish.modulate = Color(col.r, col.g, col.b, 0.0)
			add_child(fish)
			var dur: float = randf_range(5.5, 8.0)
			var tw := fish.create_tween()
			tw.set_parallel(true)
			tw.tween_property(fish, "position:x",
				(_vp.x + fw * 3.0) if dir > 0.0 else -fw * 3.0, dur)
			tw.tween_property(fish, "modulate:a", 0.7, 1.0)
			tw.chain().tween_interval(dur - 2.0)
			tw.chain().tween_property(fish, "modulate:a", 0.0, 1.0)
			tw.chain().tween_callback(fish.queue_free)

## Three medusae drifting through the deep. Each bell contracts quick and relaxes
## slow — a real medusa beat — and every contraction PROPELS it, because a jelly
## that pulses without moving is a decoration hanging on a nail. The wander lives
## on a parent pivot so the thrust and the drift keep separate clocks.
func _jellyfish() -> void:
	var tex := _shaped("jellyfish", 80, 124, _fn_jelly)
	# [x-frac, y-frac, width-frac of vp.x, beat phase offset, alpha]
	for e_v in [[0.20, 0.26, 0.24, 0.0, 0.52], [0.82, 0.56, 0.15, 2.1, 0.36],
			[0.54, 0.40, 0.11, 3.4, 0.26]]:
		var e: Array = e_v
		var w: float = _vp.x * float(e[2])
		var rest_a: float = float(e[4])
		var pivot := Control.new()
		pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pivot.position = Vector2(_vp.x * float(e[0]), _vp.y * float(e[1]))
		add_child(pivot)
		var jelly := TextureRect.new()
		jelly.texture = tex
		jelly.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		jelly.stretch_mode = TextureRect.STRETCH_SCALE
		jelly.mouse_filter = Control.MOUSE_FILTER_IGNORE
		jelly.size = Vector2(w, w * (124.0 / 80.0))
		jelly.pivot_offset = Vector2(w * 0.5, w * 0.40)   # pulse from the bell
		jelly.position = -jelly.pivot_offset
		var glowc: Color = _pc("accent").lerp(_white(1.0), 0.30)
		jelly.modulate = Color(glowc.r, glowc.g, glowc.b, rest_a)
		pivot.add_child(jelly)
		var ph: float = float(e[3])
		var hop: float = w * 0.20
		var rest := jelly.position
		# The bell pulse: contract quick, relax slow.
		var pulse := jelly.create_tween().set_loops()
		pulse.tween_interval(ph * 0.4 + 0.01)
		pulse.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(jelly, "scale", Vector2(1.12, 0.90), 0.5)
		pulse.set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(jelly, "scale", Vector2.ONE, 1.9)
		# ...which pushes it: a hop up on the squeeze, a slow sink on the relax.
		var thrust := jelly.create_tween().set_loops()
		thrust.tween_interval(ph * 0.4 + 0.01)
		thrust.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		thrust.tween_property(jelly, "position", rest - Vector2(0.0, hop), 0.5)
		thrust.set_ease(Tween.EASE_IN_OUT)
		thrust.tween_property(jelly, "position", rest, 1.9)
		# It glows brighter on each beat.
		var glow := jelly.create_tween().set_loops()
		glow.tween_interval(ph * 0.4 + 0.01)
		glow.tween_property(jelly, "modulate:a", minf(rest_a * 1.55, 1.0), 0.5)
		glow.tween_property(jelly, "modulate:a", rest_a, 1.9)
		# The lazy wander, carrying the whole animal.
		var home := pivot.position
		var drift := pivot.create_tween().set_loops()
		drift.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		drift.tween_property(pivot, "position",
			home + Vector2(_vp.x * 0.06, -_vp.y * 0.07), randf_range(6.5, 8.5))
		drift.tween_property(pivot, "position", home, randf_range(7.0, 9.0))

## Comb jellies: transparent ovoids that row themselves along on eight bands of
## fused cilia, and the light running down those bands is the single most
## recognisable thing in deep-sea footage. Nearly invisible bodies — a
## ctenophore is 95% water and you only ever see the combs firing.
func _biolum_combs() -> void:
	var tex := _shaped("biolum_comb", 76, 110, _fn_bio_comb)
	for e_v in [[0.30, 0.62, 0.11, 0.0], [0.72, 0.30, 0.085, 1.7]]:
		var e: Array = e_v
		var w: float = _vp.x * float(e[2])
		var comb := TextureRect.new()
		comb.texture = tex
		comb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		comb.stretch_mode = TextureRect.STRETCH_SCALE
		comb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		comb.size = Vector2(w, w * (110.0 / 76.0))
		comb.pivot_offset = comb.size * 0.5
		comb.position = Vector2(_vp.x * float(e[0]), _vp.y * float(e[1])) - comb.pivot_offset
		var cc: Color = _pc("accent").lerp(_white(1.0), 0.22)
		comb.modulate = Color(cc.r, cc.g, cc.b, 0.34)
		add_child(comb)
		# The combs beat continuously: the shimmer never stops, it only travels.
		var beat := comb.create_tween().set_loops()
		beat.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		beat.tween_interval(float(e[3]) * 0.5)
		beat.tween_property(comb, "modulate:a", 0.62, 0.9)
		beat.tween_property(comb, "modulate:a", 0.30, 1.3)
		# Rowing: a slow crawl across the frame on a long loop, tilting as it goes.
		var home := comb.position
		var swim := comb.create_tween().set_loops()
		swim.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		swim.tween_property(comb, "position",
			home + Vector2(_vp.x * 0.16, -_vp.y * 0.10), randf_range(11.0, 15.0))
		swim.tween_property(comb, "position", home, randf_range(12.0, 16.0))
		var tilt := comb.create_tween().set_loops()
		tilt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tilt.tween_property(comb, "rotation", randf_range(0.10, 0.22), randf_range(6.0, 9.0))
		tilt.tween_property(comb, "rotation", randf_range(-0.22, -0.10), randf_range(6.0, 9.0))

## A medusa: a translucent flat-bottomed BELL with a burning margin, the four
## gonads showing through the top of it, oral arms out of the mouth and a fringe
## of tentacles trailing past the frame.
##
## Two earlier bakes got this wrong in instructive ways. The first filled the
## bell with flat mid-grey, which tints out as an opaque dome — a balloon, and
## see-through is the one thing a jellyfish has to look. The second drew the
## margin as a ring on a circular bell and faded it at the mouth, i.e. exactly
## where the margin IS, so the animal rendered as a bright horseshoe. A bell is a
## dome with a FLAT bottom, and the bottom is the brightest line on it.
func _fn_jelly(uv: Vector2) -> Color:
	const AR := 1.55       # bake 80x124
	const MAR := -0.30     # the margin: where the bell's mouth sits
	var sy := uv.y * AR
	var veil := 0.0        # translucent tissue
	var lit := 0.0         # the light in it
	var glow := 0.0
	var e := Vector2(uv.x / 0.95, (sy - MAR) / 1.05)
	var er := e.length()
	if sy <= MAR + 0.03 and er < 1.12:
		var dome: float = 1.0 - smoothstep(0.90, 1.02, er)
		veil = maxf(veil, dome * (0.20 + 0.30 * smoothstep(0.10, 1.0, er)))
		lit = maxf(lit, (1.0 - smoothstep(0.03, 0.13, absf(er - 0.96))) * 0.45)
		glow = maxf(glow, (1.0 - smoothstep(0.30, 1.40, er)) * 0.40)
		# The four gonads: the clover you see through the top of a real bell, and
		# the detail that makes the silhouette read as an animal at a glance.
		var gc := Vector2(uv.x / 0.95, (sy - (MAR - 0.52)) / 0.92)
		var clover: float = pow(clampf(0.5 + 0.5 * cos(atan2(gc.y, gc.x) * 4.0), 0.0, 1.0), 1.5)
		lit = maxf(lit, clover * (1.0 - smoothstep(0.0, 0.17, absf(gc.length() - 0.44))) * 0.62)
	# The margin: bowed and scalloped into lappets.
	if absf(uv.x) < 1.0:
		var mline: float = MAR + 0.20 * pow(uv.x / 0.95, 2.0)
		var md := absf(sy - mline)
		var ends: float = 1.0 - smoothstep(0.82, 1.0, absf(uv.x))
		var scal: float = 0.5 + 0.5 * sin(uv.x * 23.0)
		lit = maxf(lit, (1.0 - smoothstep(0.02, 0.065, md)) * (0.72 + 0.28 * scal) * ends)
		glow = maxf(glow, (1.0 - smoothstep(0.05, 0.36, md)) * 0.45 * ends)
	# Oral arms: four frilled ribbons falling out of the mouth.
	if sy > MAR - 0.05:
		for a_v in [-0.26, -0.09, 0.09, 0.27]:
			var ax: float = a_v
			var wig: float = ax + 0.13 * sin(sy * 3.0 + ax * 12.0)
			var fall: float = 1.0 - smoothstep(MAR, 1.30, sy)
			var hw: float = 0.085 * fall
			var ad := absf(uv.x - wig)
			veil = maxf(veil, (1.0 - smoothstep(hw * 0.30, hw, ad)) * 0.40 * fall)
			lit = maxf(lit, (1.0 - smoothstep(0.002, 0.016, ad)) * 0.42 * fall)
	# Tentacles: a fringe off the margin, trailing out past the frame.
	if sy > MAR:
		for t_v in [-0.92, -0.72, -0.50, 0.46, 0.68, 0.88]:
			var tx: float = t_v
			var wig2: float = tx + 0.09 * sin(sy * 4.1 + tx * 8.0) - 0.06 * (sy - MAR) * tx
			lit = maxf(lit, (1.0 - smoothstep(0.004, 0.018, absf(uv.x - wig2))) * 0.34
				* (1.0 - smoothstep(0.55, 1.60, sy)))
	var a := clampf(maxf(veil, maxf(lit, glow * 0.5)), 0.0, 1.0)
	if a <= 0.015:
		return Color(0, 0, 0, 0)
	var b := clampf(0.20 + lit * 0.80, 0.0, 1.0)
	return Color(b, b, b, a)

# --- The phenomenon: water that answers ---------------------------------------
# Every other theme's ambience is scenery you play in front of. Bioluminescence
# is a REACTION — the light exists BECAUSE something disturbed the water — so
# this theme is wired into the same on_swipe / on_merge / on_touch / celebrate
# hooks gameplay already forwards for the reward themes: a merge ignites a ring
# of plankton where the tiles met, a swipe drags a wake across the column, and
# the finger leaves a trail of sparks behind it. A theme called Bioluminescence
# whose light ignored the player was the biggest thing missing from it.

## The full-frame overlay a reaction lights from above. One ColorRect, alpha 0
## whenever nothing is happening, so at rest it costs a transparent quad.
func _biolum_bloom_layer(bio: Color) -> void:
	_bio_bloom = ColorRect.new()
	_bio_bloom.position = Vector2.ZERO
	_bio_bloom.size = _vp
	_bio_bloom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bio_bloom.color = Color(bio.r, bio.g, bio.b, 0.0)
	add_child(_bio_bloom)

## The whole column brightening for a beat — the bloom answering, under whatever
## local effect fired it.
func _biolum_pulse(strength: float) -> void:
	if _bio_bloom == null or not is_instance_valid(_bio_bloom):
		return
	if _bio_pulse != null and _bio_pulse.is_valid():
		_bio_pulse.kill()   # a fresh reaction owns the overlay: no stacked tweens
	_bio_pulse = _bio_bloom.create_tween()
	_bio_pulse.tween_property(_bio_bloom, "color:a", clampf(0.05 * strength, 0.0, 0.10), 0.09)
	_bio_pulse.tween_property(_bio_bloom, "color:a", 0.0, 0.55)

## A merge: the water breaks and the plankton around it fire. A soft core bloom
## with a ring of individual sparks riding the pressure wave outward.
func _biolum_flash(at: Vector2, strength: float) -> void:
	var hot: Color = _pc("accent").lerp(_white(1.0), 0.45)
	var d: float = minf(_vp.x, _vp.y) * (0.15 + 0.09 * strength)
	var core := TextureRect.new()
	core.texture = _round()
	core.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	core.stretch_mode = TextureRect.STRETCH_SCALE
	core.mouse_filter = Control.MOUSE_FILTER_IGNORE
	core.size = Vector2(d, d)
	core.position = at - core.size * 0.5
	core.pivot_offset = core.size * 0.5
	core.scale = Vector2(0.45, 0.45)
	core.modulate = Color(hot.r, hot.g, hot.b, 0.0)
	add_child(core)
	var ct := core.create_tween()
	ct.tween_property(core, "modulate:a", clampf(0.50 * strength, 0.0, 0.8), 0.10)
	ct.parallel().tween_property(core, "scale", Vector2(1.5, 1.5), 0.62) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	ct.tween_property(core, "modulate:a", 0.0, 0.48)
	ct.tween_callback(core.queue_free)
	var n := maxi(int(11.0 * _particle_scale() * strength), 4)
	for i in n:
		var ang: float = TAU * (float(i) + randf()) / float(n)
		var dir := Vector2(cos(ang), sin(ang))
		var sz: float = d * randf_range(0.085, 0.16)
		var sp := TextureRect.new()
		sp.texture = _dot()
		sp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sp.stretch_mode = TextureRect.STRETCH_SCALE
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sp.size = Vector2(sz, sz)
		sp.position = at + dir * d * 0.20 - sp.size * 0.5
		sp.modulate = Color(hot.r, hot.g, hot.b, 0.0)
		add_child(sp)
		var st := sp.create_tween()
		st.tween_interval(randf_range(0.0, 0.10))
		st.tween_property(sp, "modulate:a", 0.95, 0.08)
		st.parallel().tween_property(sp, "position",
			at + dir * d * randf_range(0.75, 1.35) - sp.size * 0.5, 0.56) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		st.tween_property(sp, "modulate:a", 0.0, 0.30)
		st.tween_callback(sp.queue_free)
	_biolum_pulse(strength)

## A swipe: a wake of light crossing the column the way the board just moved.
func _biolum_wake(dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		return
	var bio: Color = _pc("accent")
	var horiz: bool = absf(dir.x) > absf(dir.y)
	var band := TextureRect.new()
	band.texture = _round()
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.size = Vector2(_vp.x * (0.55 if horiz else 1.9),
		_vp.y * (1.9 if horiz else 0.40))
	var travel: Vector2 = (_vp + band.size) * dir.normalized()
	var mid: Vector2 = _vp * 0.5 - band.size * 0.5
	band.position = mid - travel * 0.5
	band.modulate = Color(bio.r, bio.g, bio.b, 0.0)
	add_child(band)
	var tw := band.create_tween()
	tw.tween_property(band, "position", mid + travel * 0.5, 0.62) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(band, "modulate:a", 0.15, 0.18)
	tw.parallel().tween_property(band, "modulate:a", 0.0, 0.34).set_delay(0.28)
	tw.tween_callback(band.queue_free)
	_biolum_pulse(0.7)

## The finger dragging through the water. on_touch fires on every drag event and
## swipe frames are the one budget this theme cannot overspend, so a spark costs
## a MINIMUM TRAVEL of 34 px and the field is capped at 14 alive at once —
## without both, a slow drag across the board queues one spark per input event.
func _biolum_touch(at: Vector2) -> void:
	if not is_inf(_bio_touch.x) and at.distance_to(_bio_touch) < 34.0:
		return
	_bio_touch = at
	if _bio_sparks >= 14:
		return
	_bio_sparks += 1
	var hot: Color = _pc("accent").lerp(_white(1.0), 0.5)
	var sz: float = minf(_vp.x, _vp.y) * randf_range(0.020, 0.040)
	var sp := TextureRect.new()
	sp.texture = _dot()
	sp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sp.stretch_mode = TextureRect.STRETCH_SCALE
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.size = Vector2(sz, sz)
	sp.position = at + Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0)) \
		- sp.size * 0.5
	sp.pivot_offset = sp.size * 0.5
	sp.scale = Vector2(0.5, 0.5)
	sp.modulate = Color(hot.r, hot.g, hot.b, 0.0)
	add_child(sp)
	var tw := sp.create_tween()
	tw.tween_property(sp, "modulate:a", 0.85, 0.08)
	tw.parallel().tween_property(sp, "scale", Vector2(1.25, 1.25), 0.5) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(sp, "modulate:a", 0.0, 0.42)
	tw.tween_callback(func() -> void:
		_bio_sparks = maxi(_bio_sparks - 1, 0)
		sp.queue_free())

## The celebration beat: the whole bloom goes off at once.
func _biolum_celebrate() -> void:
	_biolum_pulse(1.6)
	for i in 5:
		var at := Vector2(_vp.x * randf_range(0.12, 0.88),
			_vp.y * randf_range(0.15, 0.85))
		var gen := _gen
		get_tree().create_timer(float(i) * 0.09).timeout.connect(
			func() -> void:
				if is_inside_tree() and gen == _gen:
					_biolum_flash(at, 1.2))

func _m_moonlit() -> void:
	# Moonlit Bamboo: fireflies, drifting bamboo leaves, and a pale moonbeam.
	_m_fireflies()
	_emit({"from": "top", "tex": _leaf(), "color": _pc("accent").lerp(_white(1.0), 0.2),
		"alpha": 0.5, "amount": 18, "lifetime": 10.0, "dir": Vector3(0.3, 1, 0), "spread": 26.0,
		"vmin": 26.0, "vmax": 70.0, "smin": 0.7, "smax": 1.6, "spin": 1.4})
	_moonbeam()
	_silhouettes()
	_moonlit_grove()

func _m_phantom() -> void:
	# Phantom Realm, properly haunted: fog wisps, ghost orbs and the spectral
	# flicker — under a pale haunted moon, over a ruined castle skyline with a
	# graveyard of leaning tombstones and dead trees below, and SWARMS of bats
	# beating across the sky.
	_m_fog()
	_ghost_orbs(_gen)
	_ambient_flash(_pc("accent"), 0.10, 4.0, 9.0)
	_haunted_moon()
	_castle_silhouette()
	_bare_trees()
	_graveyard()
	# SWARMS of bats: a big immediate flock so the sky is alive at once, large
	# recurring flocks, and a fast steady trickle of stragglers between them.
	for i in 30:
		_one_bat(float(i))
	_bat_flocks(_gen)
	_bat_swarm(_gen)

## A pale, sickly moon high in the haunted sky, ringed by a spectral halo.
func _haunted_moon() -> void:
	var mc := Vector2(_vp.x * 0.72, _vp.y * 0.12)
	var md: float = _vp.x * 0.16
	var accent: Color = _pc("accent")
	var halo := TextureRect.new()
	halo.texture = _round()
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hd: float = md * 2.8
	halo.size = Vector2(hd, hd)
	halo.position = mc - halo.size * 0.5
	halo.modulate = Color(accent.r, accent.g, accent.b, 0.18)
	add_child(halo)
	var moon := TextureRect.new()
	moon.texture = _moon()
	moon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	moon.size = Vector2(md, md)
	moon.position = mc - moon.size * 0.5
	moon.modulate = Color(0.84, 0.90, 0.78, 0.9)   # sickly bone-pale green-white
	add_child(moon)

## A ruined castle skyline in silhouette along the bottom edge: curtain wall,
## battlement teeth, towers of varied height — and a few windows glowing with
## a slow spectral flicker. Grounds the realm as a PLACE, not just weather.
func _castle_silhouette() -> void:
	var col := Color(0.03, 0.02, 0.07, 0.94)
	var wall_h: float = _vp.y * 0.052
	_srect(0.0, _vp.y - wall_h, _vp.x, wall_h, col)
	# Battlement teeth along the curtain wall.
	var tooth_w: float = _vp.x * 0.020
	var tooth_h: float = wall_h * 0.55
	var tx := 0.0
	while tx < _vp.x:
		_srect(tx, _vp.y - wall_h - tooth_h, tooth_w, tooth_h + 2.0, col)
		tx += tooth_w * 2.0
	# Towers: [x-frac, height-frac, width-frac]
	var towers := [
		[0.04, 0.15, 0.075], [0.21, 0.10, 0.06], [0.46, 0.19, 0.085],
		[0.70, 0.12, 0.065], [0.88, 0.16, 0.075],
	]
	for t in towers:
		var e := t as Array
		var tw_x: float = _vp.x * float(e[0])
		var t_h: float = _vp.y * float(e[1])
		var t_w: float = _vp.x * float(e[2])
		_srect(tw_x, _vp.y - t_h, t_w, t_h, col)
		# Teeth on each tower top.
		var tt_w := t_w / 5.0
		for k in 3:
			_srect(tw_x + float(k) * tt_w * 2.0, _vp.y - t_h - tt_w * 1.4, tt_w, tt_w * 1.4 + 2.0, col)
		# A tall tower earns a flickering window — someone (something) is home.
		if float(e[1]) >= 0.15:
			var win := _srect(tw_x + t_w * 0.4, _vp.y - t_h * 0.72, t_w * 0.16, t_w * 0.30,
				Color(_pc("accent"), 0.0))
			var wt := win.create_tween().set_loops()
			wt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			wt.tween_property(win, "color:a", 0.55, randf_range(1.2, 2.2))
			wt.tween_property(win, "color:a", 0.15, randf_range(1.2, 2.2))

func _srect(x: float, y: float, w: float, h: float, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = Vector2(x, y)
	r.size = Vector2(w, h)
	add_child(r)
	return r

## Big flocks of bats beating across the haunted sky every few seconds.
func _bat_flocks(gen: int) -> void:
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(2.0, 4.5)).timeout
		if gen != _gen or not is_inside_tree():
			return
		var n := randi_range(36, 60)
		for i in n:
			_one_bat(float(i))

## A steady trickle of lone bats crossing between the big flocks, so the night
## sky is never empty of wings.
func _bat_swarm(gen: int) -> void:
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(0.2, 0.55)).timeout
		if gen != _gen or not is_inside_tree():
			return
		_one_bat(randf_range(0.0, 3.0))

## One bat: flies across the screen on a wobbling path, wings beating via a
## fast y-scale flap. Spawned in loose flock formation by _bat_flocks.
func _one_bat(idx: float) -> void:
	var ltr := randf() < 0.5
	var bw: float = randf_range(44.0, 78.0)
	var bat := TextureRect.new()
	bat.texture = _bat()
	bat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bat.stretch_mode = TextureRect.STRETCH_SCALE
	bat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bat.size = Vector2(bw, bw * 0.62)
	bat.pivot_offset = bat.size * 0.5
	bat.flip_h = not ltr
	var y0: float = _vp.y * randf_range(0.06, 0.45) + idx * 26.0
	bat.position = Vector2((-70.0 - idx * 44.0) if ltr else (_vp.x + 70.0 + idx * 44.0), y0)
	bat.modulate = Color(0.06, 0.04, 0.12, 0.9)
	add_child(bat)
	var dur: float = randf_range(4.5, 7.0)
	# The crossing.
	var fly := bat.create_tween()
	fly.tween_property(bat, "position:x", (_vp.x + 90.0) if ltr else -90.0, dur)
	fly.tween_callback(bat.queue_free)
	# The bob — an erratic up/down wander layered on the crossing.
	var bob := bat.create_tween().set_loops()
	bob.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	bob.tween_property(bat, "position:y", y0 - randf_range(14.0, 30.0), randf_range(0.4, 0.7))
	bob.tween_property(bat, "position:y", y0 + randf_range(10.0, 24.0), randf_range(0.4, 0.7))
	# The wing-beat: a vertical squash loop — floored at 0.64 so even mid-beat
	# the wings stay full, never a thin sliver.
	var flap := bat.create_tween().set_loops()
	flap.tween_property(bat, "scale:y", 0.64, randf_range(0.11, 0.17))
	flap.tween_property(bat, "scale:y", 1.0, randf_range(0.11, 0.17))

## Two dead, gnarled trees framing the graveyard, swaying in an eerie wind.
func _bare_trees() -> void:
	var tree := _shaped("phantom_tree", 128, 168, _fn_tree)
	for e_v in [[0.11, 0.32, -1.0], [0.87, 0.36, 1.0]]:
		var e: Array = e_v
		var h: float = _vp.y * float(e[1])
		var w: float = h * 0.85
		var t := TextureRect.new()
		t.texture = tree
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.size = Vector2(w, h)
		t.flip_h = float(e[2]) < 0.0
		t.pivot_offset = Vector2(w * 0.5, h)   # sway from the roots
		t.position = Vector2(_vp.x * float(e[0]) - w * 0.5, _vp.y - h + _vp.y * 0.02)
		add_child(t)
		var sw := t.create_tween().set_loops()
		sw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		sw.tween_property(t, "rotation", 0.016, randf_range(3.5, 5.0))
		sw.tween_property(t, "rotation", -0.016, randf_range(3.5, 5.0))

## A distance field union of branch segments — a bare, forking dead tree.
func _fn_tree(uv: Vector2) -> Color:
	var segs := [
		Vector2(0.0, 1.0), Vector2(0.0, -0.1),
		Vector2(0.0, 0.1), Vector2(-0.55, -0.55),
		Vector2(0.0, 0.0), Vector2(0.5, -0.45),
		Vector2(0.0, -0.15), Vector2(0.18, -0.78),
		Vector2(0.0, 0.25), Vector2(-0.32, -0.82),
		Vector2(-0.55, -0.55), Vector2(-0.82, -0.9),
		Vector2(-0.55, -0.55), Vector2(-0.4, -0.95),
		Vector2(0.5, -0.45), Vector2(0.74, -0.82),
		Vector2(0.5, -0.45), Vector2(0.6, -0.94),
		Vector2(0.18, -0.78), Vector2(0.06, -0.99),
		Vector2(0.18, -0.78), Vector2(0.36, -0.97),
	]
	var a := 0.0
	var i := 0
	while i < segs.size():
		var p1: Vector2 = segs[i]
		var p2: Vector2 = segs[i + 1]
		var th := lerpf(0.11, 0.02, clampf((1.0 - (p1.y + p2.y) * 0.5) * 0.5, 0.0, 1.0))
		a = maxf(a, 1.0 - smoothstep(th * 0.55, th, _seg_dist(uv, p1, p2)))
		i += 2
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	return Color(0.03, 0.02, 0.06, clampf(a, 0.0, 1.0) * 0.96)

## Shortest distance from point `p` to segment a-b (for the tree's branches).
func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-5), 0.0, 1.0)
	return (p - (a + ab * t)).length()

## A row of leaning tombstones just in front of the castle wall.
func _graveyard() -> void:
	var stone := _shaped("tombstone", 64, 96, _fn_tomb)
	for xf_v in [0.17, 0.31, 0.55, 0.69, 0.81]:
		var xf: float = xf_v
		var h: float = _vp.y * randf_range(0.055, 0.085)
		var w: float = h * 0.68
		var s := TextureRect.new()
		s.texture = stone
		s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.size = Vector2(w, h)
		s.pivot_offset = Vector2(w * 0.5, h)
		s.position = Vector2(_vp.x * xf - w * 0.5, _vp.y - h - _vp.y * 0.028)
		s.rotation = randf_range(-0.07, 0.07)   # leaning with age
		add_child(s)

## A weathered tombstone: a slab with a rounded top and a faint cross.
func _fn_tomb(uv: Vector2) -> Color:
	var x := uv.x
	var y := uv.y
	var body := absf(x) < 0.55 and y > -0.2 and y < 0.95
	var top := y <= -0.2 and Vector2(x, y + 0.2).length() < 0.55
	if not (body or top):
		return Color(0, 0, 0, 0)
	var b := 0.09 + 0.06 * (1.0 - absf(x))
	if (absf(x) < 0.1 and y > -0.05 and y < 0.5) or (absf(y - 0.12) < 0.08 and absf(x) < 0.28):
		b *= 0.5   # the engraved cross
	return Color(b, b + 0.005, b + 0.02, 0.94)

func _m_shadow() -> void:
	# Shadow Fog: THIN haze spread EVENLY over the whole screen — many modest
	# wisps drifting both ways everywhere, instead of a few huge banks clumping
	# in one spot — with the slow searchlight sweeping through the murk.
	_emit({"from": "all", "tex": _dot(), "color": _pc("accent").lerp(_pc("text"), 0.3),
		"alpha": 0.07, "amount": 30, "lifetime": 16.0, "dir": Vector3(1, 0.04, 0),
		"spread": 26.0, "vmin": 7.0, "vmax": 20.0, "smin": 2.2, "smax": 5.0, "turb": 0.5})
	_emit({"from": "all", "tex": _dot(), "color": _pc("accent").lerp(_pc("text"), 0.45),
		"alpha": 0.05, "amount": 16, "lifetime": 20.0, "dir": Vector3(-1, 0.03, 0),
		"spread": 22.0, "vmin": 5.0, "vmax": 13.0, "smin": 3.5, "smax": 7.0, "turb": 0.4})
	_searchlight(_pc("accent"))
	_ground_fog()
	_fog_eyes(_gen)
	_fog_shapes()

## Fog has a FLOOR. The even haze above is right for the middle of the frame and
## wrong at the bottom of it: real fog pools, so it is always thickest along the
## ground and the trees at the foot of the screen should be standing IN it, not
## behind it. Six wide soft banks lying across the bottom, each drifting on its
## own clock, plus a low field of big wisps creeping sideways through them.
##
## Quads, not particles, and deliberately: these are enormous — a wisp at this
## size is thirteen times the fill of an ordinary piece, which is the whole
## reason the fog CELEBRATION is capped the way it is (confetti.gd `bomb`). Six
## tweened quads cost a fixed six draws and never scale with anything.
func _ground_fog() -> void:
	var murk: Color = _pc("accent").lerp(_pc("text"), 0.35)
	for i in 6:
		var bank := TextureRect.new()
		bank.texture = _round()
		bank.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bank.stretch_mode = TextureRect.STRETCH_SCALE
		bank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bw: float = _vp.x * randf_range(0.62, 1.15)
		bank.size = Vector2(bw, _vp.y * randf_range(0.10, 0.20))
		var x0: float = _vp.x * (-0.20 + 0.26 * float(i)) + randf_range(-0.06, 0.06) * _vp.x
		# Densest right at the bottom edge, thinning upward.
		var y0: float = _vp.y * (0.99 - 0.055 * float(i % 3)) - bank.size.y * 0.5
		bank.position = Vector2(x0, y0)
		var a: float = 0.135 - 0.022 * float(i % 3)
		bank.modulate = Color(murk.r, murk.g, murk.b, a)
		add_child(bank)
		var drift := bank.create_tween().set_loops()
		drift.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		var travel: float = _vp.x * randf_range(0.10, 0.24) * (1.0 if i % 2 == 0 else -1.0)
		drift.tween_property(bank, "position:x", x0 + travel, randf_range(14.0, 22.0))
		drift.tween_property(bank, "position:x", x0, randf_range(14.0, 22.0))
		var breathe := bank.create_tween().set_loops()
		breathe.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		breathe.tween_interval(randf_range(0.0, 4.0))
		breathe.tween_property(bank, "modulate:a", a * 1.8, randf_range(6.0, 9.0))
		breathe.tween_property(bank, "modulate:a", a * 0.5, randf_range(6.5, 10.0))
	# Big wisps creeping sideways THROUGH the banks, low and slow, so the floor
	# of the fog moves as well as sitting there.
	_emit({"from": "bottom", "tex": _dot(), "color": murk,
		"alpha": 0.10, "amount": 12, "lifetime": 22.0, "dir": Vector3(1, -0.10, 0),
		"spread": 12.0, "vmin": 5.0, "vmax": 15.0, "smin": 5.0, "smax": 10.0,
		"turb": 0.3})

## Something lives in the murk: now and then a pair of glowing eyes opens,
## watches, blinks once, and is gone.
func _fog_eyes(gen: int) -> void:
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(6.0, 12.0)).timeout
		if gen != _gen or not is_inside_tree():
			return
		var pos := Vector2(randf_range(0.15, 0.85) * _vp.x, randf_range(0.30, 0.85) * _vp.y)
		var gap: float = randf_range(30.0, 46.0)
		var watch: float = randf_range(0.6, 1.5)   # both eyes share the same beats
		var col: Color = _pc("accent").lerp(_white(1.0), 0.35)
		for s in [-1.0, 1.0]:
			var eye := TextureRect.new()
			eye.texture = _dot()
			eye.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var d: float = randf_range(13.0, 17.0)
			eye.size = Vector2(d, d * 1.3)
			eye.pivot_offset = eye.size * 0.5
			eye.position = pos + Vector2(float(s) * gap * 0.5, 0.0) - eye.size * 0.5
			eye.modulate = Color(col.r, col.g, col.b, 0.0)
			add_child(eye)
			var tw := eye.create_tween()
			tw.tween_property(eye, "modulate:a", 0.75, 0.9)
			tw.tween_interval(0.7)
			# the blink
			tw.tween_property(eye, "scale:y", 0.08, 0.09)
			tw.tween_property(eye, "scale:y", 1.0, 0.11)
			tw.tween_interval(watch)
			tw.tween_property(eye, "modulate:a", 0.0, 1.1)
			tw.tween_callback(eye.queue_free)

func _m_desert_night() -> void:
	# Desert Midnight: a starfield, the occasional shooting star, warm dune glow.
	_m_stars()
	_edge_glow(_pc("gold"), 0.08, 0.14, false)
	_shooting_stars(_gen)

func _m_desert() -> void:
	# Arabian Night: a warm, cozy, starry desert night. Dark rolling dune silhouettes,
	# a crescent moon with a soft halo, warm lantern lights glowing and gently bobbing,
	# embers drifting up from the dunes, and a warm glow along the horizon.
	var warm: Color = _pc("accent").lerp(Color(1.0, 0.72, 0.34), 0.3)   # lantern amber
	_m_stars()
	# Crescent moon high in the sky with a soft warm halo.
	var mc := Vector2(_vp.x * 0.26, _vp.y * 0.15)
	var md: float = _vp.x * 0.15
	var halo := TextureRect.new()
	halo.texture = _round()
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hd: float = md * 3.2
	halo.size = Vector2(hd, hd)
	halo.position = mc - halo.size * 0.5
	halo.modulate = Color(warm.r, warm.g, warm.b, 0.14)
	add_child(halo)
	var moon := TextureRect.new()
	moon.texture = _crescent()
	moon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	moon.size = Vector2(md, md)
	moon.pivot_offset = moon.size * 0.5
	moon.position = mc - moon.size * 0.5
	moon.rotation = deg_to_rad(-18.0)
	moon.modulate = Color(1.0, 0.95, 0.80, 0.95)
	add_child(moon)
	# Shooting stars streak the desert sky.
	_shooting_stars(_gen)
	# Dark warm dune silhouettes along the bottom.
	_dunes(_pc("bg0").lerp(Color(0.20, 0.13, 0.10), 0.75))
	# The palace — onion domes, minarets, lamplit windows — anchored to the very
	# BOTTOM of the screen (the opaque board hides the middle band), drawn after
	# the dunes so it stands clear of the haze.
	_desert_palace()
	# Fine sand blowing low across the dunes on the night wind.
	_emit({"from": "all", "tex": _dot(), "color": _pc("gold").lerp(_white(1.0), 0.2),
		"alpha": 0.16, "amount": 30, "lifetime": 6.0, "dir": Vector3(1, 0.06, 0),
		"spread": 10.0, "vmin": 80.0, "vmax": 180.0, "smin": 0.2, "smax": 0.5, "turb": 0.5})
	# Warm lantern lights — glowing orbs that gently bob and softly blink.
	_emit({"from": "all", "tex": _dot(), "color": warm, "alpha": 0.85,
		"amount": 20, "lifetime": 8.0, "dir": Vector3(0.03, -1, 0), "spread": 12.0,
		"vmin": 5.0, "vmax": 15.0, "smin": 0.55, "smax": 1.3, "turb": 0.4, "twinkle": true})
	# Soft warm bokeh haloes for depth.
	_emit({"from": "all", "tex": _dot(), "color": warm, "alpha": 0.12,
		"amount": 10, "lifetime": 11.0, "dir": Vector3(0.03, -1, 0), "spread": 12.0,
		"vmin": 4.0, "vmax": 11.0, "smin": 2.4, "smax": 4.6, "turb": 0.3})
	# Warm embers drifting up from the dunes.
	_emit({"from": "bottom", "tex": _dot(), "color": warm.lerp(_white(1.0), 0.25), "alpha": 0.6,
		"amount": 28, "lifetime": 6.0, "dir": Vector3(0.12, -1, 0), "spread": 22.0,
		"vmin": 22.0, "vmax": 62.0, "smin": 0.22, "smax": 0.55, "turb": 0.7, "twinkle": true})
	# Lanterns strung across the top of the night, and the lamp on the dune with
	# its genie curling out of the spout.
	_moroccan_lanterns()
	_genie_lamp()
	# Cozy warm glow along the horizon.
	_edge_glow(warm, 0.06, 0.16, false)

## A row of pierced brass lanterns hanging from the top of the frame, each on
## its own chain, swaying out of step and throwing a patterned glow. Sizes and
## depths vary so the row reads as a market street receding, not a fence.
func _moroccan_lanterns() -> void:
	var tex := _shaped("moroccan_lantern", 72, 110, _fn_moroccan_lantern)
	# [x-frac, drop-frac of vp.y, width-frac of vp.x, alpha]
	var hangs := [[0.10, 0.20, 0.115, 0.95], [0.30, 0.13, 0.085, 0.80],
		[0.52, 0.24, 0.135, 1.0], [0.72, 0.15, 0.090, 0.82],
		[0.90, 0.21, 0.105, 0.90]]
	for h_v in hangs:
		var h: Array = h_v
		var x: float = _vp.x * float(h[0])
		var drop: float = _vp.y * float(h[1])
		var w: float = _vp.x * float(h[2])
		var a: float = float(h[3])
		# The chain it swings from — pivots at the very top of the screen.
		var pivot := Control.new()
		pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pivot.position = Vector2(x, 0.0)
		add_child(pivot)
		var chain := ColorRect.new()
		chain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chain.color = Color(0.85, 0.68, 0.36, 0.35)
		chain.size = Vector2(maxf(_vp.x * 0.004, 1.0), drop)
		chain.position = Vector2(-chain.size.x * 0.5, 0.0)
		pivot.add_child(chain)
		# Its halo, laid under the body.
		var halo := TextureRect.new()
		halo.texture = _dot()
		halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		halo.size = Vector2(w * 3.0, w * 3.0)
		halo.position = Vector2(-halo.size.x * 0.5, drop + w * 0.7 - halo.size.y * 0.5)
		halo.modulate = Color(1.0, 0.72, 0.30, 0.10 * a)
		pivot.add_child(halo)
		var lamp := TextureRect.new()
		lamp.texture = tex
		lamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lamp.stretch_mode = TextureRect.STRETCH_SCALE
		lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lamp.size = Vector2(w, w * 1.53)
		lamp.position = Vector2(-w * 0.5, drop)
		lamp.modulate = Color(1.0, 0.80, 0.42, a)
		pivot.add_child(lamp)
		# The flame inside, guttering.
		var flame := TextureRect.new()
		flame.texture = _dot()
		flame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		flame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flame.size = Vector2(w * 0.34, w * 0.34)
		flame.position = Vector2(-flame.size.x * 0.5, drop + w * 0.72)
		flame.modulate = Color(1.0, 0.92, 0.62, 0.75)
		pivot.add_child(flame)
		var ft := flame.create_tween().set_loops()
		ft.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		ft.tween_property(flame, "modulate:a", 0.95, randf_range(0.8, 1.5))
		ft.tween_property(flame, "modulate:a", 0.6, randf_range(0.8, 1.5))
		var sway := pivot.create_tween().set_loops()
		sway.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		var amp: float = randf_range(0.025, 0.055)
		sway.tween_property(pivot, "rotation", amp, randf_range(3.0, 4.6))
		sway.tween_property(pivot, "rotation", -amp, randf_range(3.0, 4.6))

## The lamp, half-buried on the near dune, and the genie who lives in it: a
## column of smoke curls out of the spout, gathers into a folded-arm figure that
## rises and looms, then thins back into smoke and sinks home. On a long cycle,
## so it is a thing you catch rather than a thing that performs at you.
func _genie_lamp() -> void:
	var teal := _pc("accent").lerp(Color(0.35, 0.92, 0.92), 0.55)
	var base := Vector2(_vp.x * 0.78, _vp.y * 0.955)
	# The lamp itself.
	var lw: float = _vp.x * 0.20
	var lamp := TextureRect.new()
	lamp.texture = _shaped("genie_lamp", 120, 62, _fn_oil_lamp)
	lamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lamp.stretch_mode = TextureRect.STRETCH_SCALE
	lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lamp.size = Vector2(lw, lw * 0.52)
	lamp.position = base - Vector2(lw * 0.5, lw * 0.52)
	lamp.modulate = Color(1.0, 0.82, 0.42, 0.95)
	add_child(lamp)
	var glint := TextureRect.new()
	glint.texture = _dot()
	glint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glint.size = Vector2(lw * 1.6, lw * 1.6)
	glint.position = base - glint.size * 0.5 - Vector2(0.0, lw * 0.2)
	glint.modulate = Color(1.0, 0.86, 0.45, 0.12)
	add_child(glint)
	var gt := glint.create_tween().set_loops()
	gt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	gt.tween_property(glint, "modulate:a", 0.24, 2.6)
	gt.tween_property(glint, "modulate:a", 0.10, 3.0)
	# The spout the genie pours from.
	var spout := base + Vector2(-lw * 0.44, -lw * 0.36)
	# The genie: parented to a pivot at the spout so the whole apparition can
	# sway from its own smoke-tail rather than sliding about.
	var pivot := Control.new()
	pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot.position = spout
	add_child(pivot)
	var gw: float = _vp.x * 0.52
	var genie := TextureRect.new()
	genie.texture = _shaped("genie", 132, 210, _fn_genie)
	genie.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	genie.stretch_mode = TextureRect.STRETCH_SCALE
	genie.mouse_filter = Control.MOUSE_FILTER_IGNORE
	genie.size = Vector2(gw, gw * 1.59)
	genie.pivot_offset = Vector2(gw * 0.5, genie.size.y)   # grows out of the spout
	genie.position = Vector2(-gw * 0.5, -genie.size.y)
	genie.modulate = Color(teal.r, teal.g, teal.b, 0.0)
	genie.scale = Vector2(0.35, 0.35)
	pivot.add_child(genie)
	var rise := genie.create_tween().set_loops()
	rise.tween_interval(4.0)
	rise.set_parallel(true)
	rise.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	rise.tween_property(genie, "scale", Vector2.ONE, 3.2)
	rise.tween_property(genie, "modulate:a", 0.34, 2.4)
	rise.chain().tween_interval(4.5)
	rise.set_parallel(true)
	rise.set_ease(Tween.EASE_IN_OUT)
	rise.tween_property(genie, "scale", Vector2(0.35, 0.35), 3.0)
	rise.tween_property(genie, "modulate:a", 0.0, 3.0)
	rise.chain().tween_interval(6.0)
	var sway := pivot.create_tween().set_loops()
	sway.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	sway.tween_property(pivot, "rotation", 0.05, 4.0)
	sway.tween_property(pivot, "rotation", -0.05, 4.2)
	# Smoke feeding the apparition, always trickling from the spout.
	var smoke := CPUParticles2D.new()
	smoke.position = spout
	smoke.amount = maxi(int(14.0 * _particle_scale()), 4)
	smoke.lifetime = 3.4
	smoke.preprocess = 1.5
	smoke.texture = _round()
	smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = _vp.x * 0.02
	smoke.direction = Vector2(0, -1)
	smoke.spread = 16.0
	smoke.initial_velocity_min = 18.0
	smoke.initial_velocity_max = 46.0
	smoke.scale_amount_min = 0.5
	smoke.scale_amount_max = 1.6
	smoke.color_ramp = _alpha_ramp(teal, 0.16, false)
	smoke.emitting = true
	add_child(smoke)

## The palace skyline: a great central onion dome flanked by two smaller domes
## and a pair of minarets, in dark silhouette, with a few windows glowing warm
## and flickering like lamplight. Anchored to the BOTTOM edge of the screen so
## it lives in the visible band below the board, never hidden behind it.
func _desert_palace() -> void:
	var tex := _shaped("desert_palace", 320, 170, _fn_palace)
	var w: float = _vp.x * 0.82
	var h: float = w * (170.0 / 320.0)
	var base_y: float = _vp.y * 1.005         # the palace sits on the bottom edge
	var px: float = _vp.x * 0.50 - w * 0.5
	var pal := TextureRect.new()
	pal.texture = tex
	pal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pal.stretch_mode = TextureRect.STRETCH_SCALE
	pal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pal.size = Vector2(w, h)
	pal.position = Vector2(px, base_y - h)
	pal.modulate = Color(1, 1, 1, 0.96)
	add_child(pal)
	# Lamplit windows dotted over the palace, each with its own slow flicker.
	var wins := [Vector2(0.50, 0.80), Vector2(0.42, 0.86), Vector2(0.58, 0.86),
		Vector2(0.26, 0.84), Vector2(0.74, 0.84), Vector2(0.50, 0.62)]
	for wv in wins:
		var wf: Vector2 = wv
		var win := TextureRect.new()
		win.texture = _dot()
		win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		win.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = _vp.x * randf_range(0.012, 0.02)
		win.size = Vector2(d, d * 1.4)
		win.position = Vector2(px + wf.x * w, base_y - h + wf.y * h) - win.size * 0.5
		win.modulate = Color(1.0, 0.78, 0.36, 0.0)
		add_child(win)
		var tw := win.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(win, "modulate:a", randf_range(0.6, 0.95), randf_range(1.4, 2.6))
		tw.tween_property(win, "modulate:a", randf_range(0.25, 0.45), randf_range(1.4, 2.6))

## One onion dome (drum + bulb + tapering spire) at column `cx`, sitting on
## `base_y`, bulb radius `r`. uv/coords are the palace bake's -1..1 space, y up = -.
func _onion(x: float, y: float, cx: float, base_y: float, r: float) -> float:
	var lx := x - cx
	var out := 0.0
	# the drum the dome sits on
	if absf(lx) < r * 0.72 and y < base_y and y > base_y - r * 0.5:
		out = 1.0
	# the bulb
	var cy := base_y - r * 0.95
	out = maxf(out, 1.0 - smoothstep(r - 0.02, r, Vector2(lx, y - cy).length()))
	# the spire tapering to a point above the bulb
	var bulb_top := cy - r
	var spire := r * 0.85
	if y < bulb_top and y > bulb_top - spire:
		var t := (bulb_top - y) / spire
		var sw := r * 0.13 * (1.0 - t)
		out = maxf(out, 1.0 - smoothstep(sw * 0.5, sw + 0.004, absf(lx)))
	return out

## One minaret: a slender shaft with a balcony ring and a small onion cap.
func _minaret(x: float, y: float, cx: float) -> float:
	var lx := x - cx
	var out := 0.0
	if absf(lx) < 0.032 and y > -0.36 and y < 0.46:
		out = 1.0
	if absf(lx) < 0.058 and absf(y + 0.30) < 0.018:   # the balcony
		out = 1.0
	return maxf(out, _onion(x, y, cx, -0.36, 0.085))

## The whole palace silhouette in one bake (see _desert_palace).
func _fn_palace(uv: Vector2) -> Color:
	var x := uv.x
	var y := uv.y
	var a := 0.0
	if y > 0.46:                       # the base wall / rampart
		a = 1.0
	a = maxf(a, _onion(x, y, 0.0, 0.46, 0.30))     # great central dome
	a = maxf(a, _onion(x, y, -0.52, 0.46, 0.17))   # side domes
	a = maxf(a, _onion(x, y, 0.52, 0.46, 0.17))
	a = maxf(a, _minaret(x, y, -0.84))             # flanking minarets
	a = maxf(a, _minaret(x, y, 0.84))
	if a < 0.5:
		return Color(0, 0, 0, 0)
	return Color(0.05, 0.03, 0.05, 0.96)

## Soft layered dune crests rising along the bottom edge — big soft radial ellipses,
## tinted warmer toward the front, so they read as heat-hazed dunes fading into haze.
func _dunes(base_col: Color) -> void:
	# A rolling dune SEA: six wide soft humps at staggered heights and horizontal
	# offsets — hazier/paler toward the back, warmer/more solid toward the front — so
	# the crests overlap into layered rolling dunes rather than three flat mounds.
	var layers := 6
	for i in layers:
		var f: float = float(i) / float(layers - 1)     # 0 = far back, 1 = front
		var dune := TextureRect.new()
		dune.texture = _round()
		dune.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		dune.stretch_mode = TextureRect.STRETCH_SCALE
		dune.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(1.3, 2.1)
		var h: float = _vp.y * randf_range(0.5, 0.8)
		dune.size = Vector2(w, h)
		var crest_y: float = _vp.y * lerpf(0.60, 0.92, f) + randf_range(-_vp.y * 0.03, _vp.y * 0.03)
		var cx: float = _vp.x * randf_range(0.1, 0.9)
		dune.position = Vector2(cx - w * 0.5, crest_y)
		var c: Color = base_col.lerp(_pc("bg0"), 0.45 * (1.0 - f)).lerp(_pc("gold"), 0.22 * f)
		dune.modulate = Color(c.r, c.g, c.b, lerpf(0.28, 0.72, f))
		add_child(dune)

## Soft volumetric light shafts descending from the top, each breathing gently —
## sunbeams through water (Ocean) or dust (reusable). Base/peak set the intensity.
func _god_rays(col: Color, base_a: float, peak_a: float) -> void:
	for i in 4:
		var ray := TextureRect.new()
		ray.texture = _round()
		ray.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ray.stretch_mode = TextureRect.STRETCH_SCALE
		ray.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.14, 0.24)
		var h: float = _vp.y * 1.4
		ray.size = Vector2(w, h)
		ray.pivot_offset = Vector2(w * 0.5, 0.0)
		ray.rotation = deg_to_rad(randf_range(-14.0, 14.0))
		ray.position = Vector2(_vp.x * (0.12 + float(i) * 0.24) - w * 0.5, -_vp.y * 0.35)
		ray.modulate = Color(col.r, col.g, col.b, base_a)
		add_child(ray)
		var tw := ray.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(ray, "modulate:a", peak_a, randf_range(4.0, 6.0))
		tw.tween_property(ray, "modulate:a", base_a, randf_range(4.0, 6.5))

func _m_toxic() -> void:
	# Toxic Neon: an acid-green hazard atmosphere — billowing toxic smog, bubbling
	# ooze, floating spores, dripping acid and a radioactive floor glow. (The old
	# magenta/cyan neon haze read as cyberpunk, not toxic.)
	var acid: Color = _pc("accent")
	# Heavy green smog rising and billowing (big, soft, slow).
	_emit({"from": "bottom", "tex": _dot(), "color": acid.darkened(0.15), "alpha": 0.14,
		"amount": 16, "lifetime": 12.0, "dir": Vector3(0.12, -1, 0), "spread": 30.0,
		"vmin": 8.0, "vmax": 26.0, "smin": 4.5, "smax": 10.0})
	# Acid bubbles rising and popping.
	_emit({"from": "bottom", "tex": _ring(), "color": acid, "alpha": 0.55,
		"amount": 24, "lifetime": 7.0, "dir": Vector3(0.05, -1, 0), "spread": 16.0,
		"vmin": 36.0, "vmax": 95.0, "smin": 0.3, "smax": 0.9, "twinkle": true})
	# Floating toxic spores — small bright motes drifting.
	_emit({"from": "all", "tex": _dot(), "color": acid.lightened(0.35), "alpha": 0.7,
		"amount": 30, "lifetime": 6.0, "dir": Vector3(0, -1, 0), "spread": 180.0,
		"vmin": 5.0, "vmax": 16.0, "smin": 0.25, "smax": 0.6, "twinkle": true})
	# Radioactive glow breathing up from the floor + acid drips + faint scanlines.
	_edge_glow(acid, 0.08, 0.22, false)
	_drips(_gen, acid.lightened(0.15))
	_scanlines(acid)

# --- Name-accurate signature motifs (sky / celestial / seasonal) --------------

func _m_blood_moon() -> void:
	# A huge crimson moon hanging in a smoke-choked sky, with blood-red clouds
	# drifting across it and a low glow rising from the horizon.
	var red: Color = _pc("accent")
	var cx: float = _vp.x * 0.70
	var cy: float = _vp.y * 0.19
	# Soft blood halo behind the moon, breathing.
	var halo := TextureRect.new()
	halo.texture = _round()
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hd: float = _vp.x * 0.95
	halo.size = Vector2(hd, hd)
	halo.position = Vector2(cx - hd * 0.5, cy - hd * 0.5)
	halo.modulate = Color(red.r, red.g, red.b, 0.10)
	add_child(halo)
	var htw := halo.create_tween().set_loops()
	htw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	htw.tween_property(halo, "modulate:a", 0.20, 4.5)
	htw.tween_property(halo, "modulate:a", 0.10, 5.0)
	# The blood moon itself — a darkened-red disc with faint maria.
	var moon := TextureRect.new()
	moon.texture = _moon()
	moon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var md: float = _vp.x * 0.42
	moon.size = Vector2(md, md)
	moon.position = Vector2(cx - md * 0.5, cy - md * 0.5)
	moon.modulate = red.lerp(Color(0.82, 0.36, 0.16), 0.5)   # coppery blood-red, not a flat ball
	add_child(moon)
	# Drifting blood clouds + a crimson glow rising from below + distant red
	# heat-lightning that flickers the whole sky now and then.
	_m_fog()
	_edge_glow(red, 0.04, 0.12, false)
	_ambient_flash(red, 0.08, 5.0, 11.0)
	_bloodmoon_ridge()

func _m_sunset() -> void:
	# A warm sun resting on the horizon, a breathing glow around it, and slow
	# cloud bands drifting across the dusk sky.
	var warm: Color = _pc("accent")
	var glow: Color = _pc("gold").lerp(warm, 0.3)
	var horizon: float = _vp.y * 0.66
	var halo := TextureRect.new()
	halo.texture = _round()
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hd: float = _vp.x * 1.1
	halo.size = Vector2(hd, hd)
	halo.position = Vector2((_vp.x - hd) * 0.5, horizon - hd * 0.5)
	halo.modulate = Color(glow.r, glow.g, glow.b, 0.14)
	add_child(halo)
	var htw := halo.create_tween().set_loops()
	htw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	htw.tween_property(halo, "modulate:a", 0.22, 5.0)
	htw.tween_property(halo, "modulate:a", 0.14, 5.5)
	var sun := TextureRect.new()
	sun.texture = _disc()
	sun.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d: float = _vp.x * 0.42
	sun.size = Vector2(d, d)
	sun.position = Vector2((_vp.x - d) * 0.5, horizon - d * 0.5)
	sun.modulate = warm.lerp(_pc("gold"), 0.4)
	add_child(sun)
	_cloud_bands(glow)

func _m_nebula() -> void:
	# Drifting clouds of coloured gas under a dense starfield — an actual nebula
	# rather than a plain starfield.
	var cols: Array = [_pc("accent"), _pc("gold"), _pc("accent2"),
		_pc("accent").lerp(Color(0.6, 0.3, 1.0), 0.5)]
	for i in 4:
		var blob := TextureRect.new()
		blob.texture = _round()
		blob.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		blob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = minf(_vp.x, _vp.y) * randf_range(1.0, 1.6)
		blob.size = Vector2(d, d)
		var col: Color = cols[i % cols.size()]
		var home := Vector2(randf_range(-d * 0.3, _vp.x - d * 0.6),
			randf_range(-d * 0.25, _vp.y - d * 0.45))
		blob.position = home
		blob.modulate = Color(col.r, col.g, col.b, 0.0)
		add_child(blob)
		var peak: float = randf_range(0.12, 0.22)
		var drift := Vector2(randf_range(-40.0, 40.0), randf_range(-30.0, 30.0))
		var tw := blob.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(blob, "modulate:a", peak, randf_range(5.0, 8.0))
		tw.parallel().tween_property(blob, "position", home + drift, randf_range(11.0, 17.0))
		tw.tween_property(blob, "modulate:a", peak * 0.5, randf_range(5.0, 8.0))
		tw.parallel().tween_property(blob, "position", home, randf_range(11.0, 17.0))
	_m_stars()
	_shooting_stars(_gen)
	_protostar()

func _m_grid() -> void:
	# Synthwave: a neon perspective grid floor, a sliced retro sun on the horizon,
	# and a sparse starfield above.
	var horizon: float = _vp.y * 0.60
	var grid := ColorRect.new()
	grid.position = Vector2.ZERO
	grid.size = _vp
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _grid_mat == null:
		if _grid_shader == null:
			_grid_shader = Shader.new()
			_grid_shader.code = _GRID_CODE
		_grid_mat = ShaderMaterial.new()
		_grid_mat.shader = _grid_shader
	_grid_mat.set_shader_parameter("line_col", _pc("accent"))
	_grid_mat.set_shader_parameter("speed", 0.30)
	_grid_mat.set_shader_parameter("horizon", 0.60)
	grid.material = _grid_mat
	add_child(grid)
	# Retro sun sitting on the horizon.
	var sun := TextureRect.new()
	sun.texture = _disc()
	sun.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d: float = _vp.x * 0.5
	sun.size = Vector2(d, d)
	sun.position = Vector2((_vp.x - d) * 0.5, horizon - d * 0.66)
	sun.modulate = _pc("accent").lerp(_pc("gold"), 0.35)
	add_child(sun)
	# Horizontal slits across the lower half of the sun (the retro look).
	for i in 5:
		var slit := ColorRect.new()
		slit.color = _pc("bg0")
		slit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slit.size = Vector2(d, 3.0 + float(i) * 1.6)
		slit.position = Vector2(sun.position.x, horizon - d * 0.30 + float(i) * (d * 0.085))
		add_child(slit)
	_m_stars()
	# Neon geometric bits — little magenta/cyan squares (spinning into diamonds) drifting
	# up through the grid — plus a VHS scanline sheen over the whole retro-future scene.
	_emit({"from": "all", "tex": _square(), "iramp": _two(_pc("accent"), _pc("accent2")),
		"alpha": 0.6, "amount": 34, "lifetime": 9.0, "dir": Vector3(0, -1, 0), "spread": 180.0,
		"vmin": 8.0, "vmax": 28.0, "smin": 0.5, "smax": 1.4, "spin": 2.4, "twinkle": true})
	_vapor_plaza()

func _m_leaves() -> void:
	# Autumn: maple leaves tumbling in three depths — a far drift, the main fall,
	# and a few big foreground leaves twirling past — caught now and then by a
	# swirling gust, over a warm low autumn sun.
	var ramp := _autumn()
	_corner_sun(_pc("gold").lerp(Color(1.0, 0.55, 0.2), 0.4))
	# far drift: small, slow, faint — spawned across the whole frame so the air is
	# full of leaves at once rather than filling slowly from the top.
	_emit({"from": "all", "tex": _leaf(), "iramp": ramp, "alpha": 0.55,
		"amount": 40, "lifetime": 15.0, "dir": Vector3(0.14, 1, 0), "spread": 22.0,
		"vmin": 18.0, "vmax": 46.0, "smin": 0.4, "smax": 0.9, "spin": 1.4, "turb": 0.7})
	# the main fall
	_emit({"from": "top", "tex": _leaf(), "iramp": ramp, "alpha": 0.9,
		"amount": 40, "lifetime": 11.0, "dir": Vector3(0.2, 1, 0), "spread": 26.0,
		"vmin": 34.0, "vmax": 92.0, "smin": 0.8, "smax": 1.7, "spin": 2.2, "turb": 0.85})
	# a few big foreground leaves twirling past the "camera"
	_emit({"from": "top", "tex": _leaf(), "iramp": ramp, "alpha": 0.95,
		"amount": 8, "lifetime": 9.0, "dir": Vector3(0.26, 1, 0), "spread": 22.0,
		"vmin": 60.0, "vmax": 120.0, "smin": 1.9, "smax": 3.0, "spin": 3.0, "turb": 1.0})
	# a swirling gust — leaves caught spiralling sideways on the wind
	_emit({"from": "all", "tex": _leaf(), "iramp": ramp, "alpha": 0.7,
		"amount": 14, "lifetime": 8.0, "dir": Vector3(1, 0.1, 0), "spread": 26.0,
		"vmin": 60.0, "vmax": 150.0, "smin": 0.6, "smax": 1.3, "spin": 3.4, "orbit": 0.34})
	_edge_glow(_pc("gold").lerp(_pc("accent"), 0.4), 0.05, 0.13, false)
	_autumn_tree()

## A big soft low sun glowing off the bottom-left corner, breathing slowly — the
## warm light source behind a falling-leaves or dusk scene.
func _corner_sun(col: Color) -> void:
	var sun := TextureRect.new()
	sun.texture = _round()
	sun.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d: float = _vp.x * 1.1
	sun.size = Vector2(d, d)
	sun.position = Vector2(-d * 0.32, _vp.y - d * 0.52)
	sun.modulate = Color(col.r, col.g, col.b, 0.1)
	add_child(sun)
	var tw := sun.create_tween().set_loops()
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(sun, "modulate:a", 0.18, 6.0)
	tw.tween_property(sun, "modulate:a", 0.1, 6.5)

func _m_lanterns() -> void:
	# A REAL lantern release: three depth layers — distant dim pinpricks far across
	# the valley, the main mid-field, and a few big bright lanterns drifting past up
	# close with glow halos — plus rising embers, the festival's warm glow on the
	# horizon, and stars behind it all. Every lantern meanders on the night air.
	var warm: Color = _pc("gold").lerp(_white(1.0), 0.18)              # bright warm gold
	var deep: Color = _pc("gold").lerp(Color(1.0, 0.45, 0.15), 0.45)   # ember orange
	# FAR — tiny, dim, slow: lanterns already high across the sky.
	_emit({"from": "bottom", "tex": _lantern(), "color": deep, "alpha": 0.55,
		"amount": 24, "lifetime": 20.0, "dir": Vector3(0.04, -1, 0), "spread": 10.0,
		"vmin": 6.0, "vmax": 14.0, "smin": 0.22, "smax": 0.45, "turb": 0.4})
	# MID — the main field of lanterns climbing.
	_emit({"from": "bottom", "tex": _lantern(), "color": warm, "alpha": 0.92,
		"amount": 20, "lifetime": 15.0, "dir": Vector3(0.05, -1, 0), "spread": 13.0,
		"vmin": 12.0, "vmax": 26.0, "smin": 0.6, "smax": 1.1, "turb": 0.5})
	# NEAR — a handful of big bright ones right past the camera, with warm halos.
	_emit({"from": "bottom", "tex": _round(), "color": warm, "alpha": 0.5,
		"amount": 10, "lifetime": 13.0, "dir": Vector3(0.06, -1, 0), "spread": 12.0,
		"vmin": 22.0, "vmax": 40.0, "smin": 1.6, "smax": 2.9, "turb": 0.4})
	_emit({"from": "bottom", "tex": _lantern(), "color": warm.lerp(_white(1.0), 0.12),
		"alpha": 1.0, "amount": 9, "lifetime": 13.0, "dir": Vector3(0.06, -1, 0),
		"spread": 12.0, "vmin": 22.0, "vmax": 40.0, "smin": 1.5, "smax": 2.3, "turb": 0.4})
	# Bright warm embers rising between them.
	_emit({"from": "bottom", "tex": _dot(), "color": warm.lerp(_white(1.0), 0.5), "alpha": 0.9,
		"amount": 22, "lifetime": 10.0, "dir": Vector3(0.05, -1, 0), "spread": 18.0,
		"vmin": 16.0, "vmax": 46.0, "smin": 0.2, "smax": 0.55, "twinkle": true, "turb": 0.8})
	# The festival below the frame warms the horizon.
	_edge_glow(deep, 0.10, 0.20, false)
	_m_stars()
	_lantern_river()

func _m_gems() -> void:
	# Coloured faceted gems raining down, tinted to the theme's gemstone (the
	# board_accent), with sparkle and an occasional prismatic flash.
	var tint: Color = ThemeManager.board_accent_for(_pal())
	if tint.a <= 0.0:
		tint = _pc("accent")
	_emit({"from": "all", "tex": _gem(), "color": tint, "alpha": 0.95,
		"amount": 48, "lifetime": 8.0, "dir": Vector3(0.05, 1, 0), "spread": 10.0,
		"vmin": 80.0, "vmax": 190.0, "smin": 0.5, "smax": 1.2, "spin": 1.0, "twinkle": true})
	# A fuller field of smaller gems drifting slowly across the whole screen.
	_emit({"from": "all", "tex": _gem(), "color": tint, "alpha": 0.7,
		"amount": 30, "lifetime": 9.0, "dir": Vector3(0, -1, 0), "spread": 180.0,
		"vmin": 8.0, "vmax": 26.0, "smin": 0.35, "smax": 0.9, "spin": 0.8, "twinkle": true})
	_emit({"from": "all", "tex": _dot(), "color": tint.lerp(_white(1.0), 0.5), "alpha": 1.0,
		"amount": 30, "lifetime": 3.6, "dir": Vector3(0, 1, 0), "spread": 180.0,
		"vmin": 1.0, "vmax": 4.0, "smin": 0.3, "smax": 0.8, "twinkle": true})
	_ambient_flash(tint.lerp(_white(1.0), 0.3), 0.12, 5.0, 10.0)

# --- Playful motifs (party / fun) ---------------------------------------------
	_gem_geode()

func _m_balloons() -> void:
	# Colourful balloons drifting up and bobbing, with a sprinkle of confetti.
	_emit({"from": "bottom", "tex": _balloon(), "iramp": _rainbow(), "alpha": 0.92,
		"amount": 18, "lifetime": 11.0, "dir": Vector3(0.06, -1, 0), "spread": 12.0,
		"vmin": 24.0, "vmax": 60.0, "smin": 0.9, "smax": 1.9, "spin": 0.4})
	_emit({"from": "top", "tex": _square(), "iramp": _rainbow(), "alpha": 0.8,
		"amount": 20, "lifetime": 5.0, "dir": Vector3(0, 1, 0), "spread": 24.0,
		"vmin": 60.0, "vmax": 160.0, "smin": 1.0, "smax": 2.2, "spin": 4.0, "gravity": 90.0})

func _m_fireworks() -> void:
	# Carnival — a whole fairground, not just a sky: a great ferris wheel turning
	# at the back with its rim bulbs chasing round, bunting and light strings slung
	# across the top, and fireworks blooming over a faint starfield.
	_emit({"from": "all", "tex": _dot(), "color": _white(0.8), "alpha": 0.5,
		"amount": 40, "lifetime": 8.0, "dir": Vector3(0, 1, 0), "spread": 180.0,
		"vmin": 1.0, "vmax": 4.0, "smin": 0.25, "smax": 0.6, "twinkle": true})
	_ferris_wheel()
	_park_lights()
	_fireworks_loop(_gen)


# --- Landmarks for the motifs that were only ever a particle field -------------
# A drifting field says "there is weather here". A LANDMARK says "you are
# somewhere". Each of these anchors its theme to a place, sits in the band the
# board never covers, and costs a handful of static nodes.

## Paper — a working desk. A pencil resting on the sheet, a coffee ring soaked
## into it, and a paper plane crossing the page every so often.
func _paper_desk() -> void:
	var ink := _pc("text")
	# The coffee ring: two overlapping stains, soaked in rather than drawn on.
	for e_v in [[0.78, 0.22, 0.20, 0.16], [0.16, 0.86, 0.13, 0.10]]:
		var e: Array = e_v
		var ring := TextureRect.new()
		ring.texture = _ring()
		ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ring.stretch_mode = TextureRect.STRETCH_SCALE
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = _vp.x * float(e[2])
		ring.size = Vector2(d, d * 0.94)
		ring.position = Vector2(_vp.x * float(e[0]), _vp.y * float(e[1])) - ring.size * 0.5
		ring.modulate = Color(0.55, 0.38, 0.22, float(e[3]))
		add_child(ring)
	# The pencil, lying across the bottom of the sheet at a lazy angle.
	var pencil := TextureRect.new()
	pencil.texture = _shaped("desk_pencil", 138, 16, _fn_pencil)
	pencil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pencil.stretch_mode = TextureRect.STRETCH_SCALE
	pencil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pw: float = _vp.x * 0.62
	pencil.size = Vector2(pw, pw * (26.0 / 220.0))
	pencil.pivot_offset = pencil.size * 0.5
	pencil.rotation = deg_to_rad(-7.0)
	pencil.position = Vector2(_vp.x * 0.20, _vp.y * 0.93)
	pencil.modulate = Color(1, 1, 1, 0.92)
	add_child(pencil)
	# Its shadow, offset and soft.
	var shade := TextureRect.new()
	shade.texture = _round()
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.size = Vector2(pw * 1.05, pencil.size.y * 4.0)
	shade.position = pencil.position + Vector2(0.0, pencil.size.y * 0.9) - Vector2(0.0, shade.size.y * 0.5)
	shade.modulate = Color(ink.r, ink.g, ink.b, 0.06)
	add_child(shade)
	move_child(shade, shade.get_index() - 1)
	# The rest of the desk: an eraser, the shavings the sharpener left, and a
	# clip. One pencil alone on a sheet is a prop; a few things beside it that
	# clearly belong together is a desk somebody works at.
	var eraser := TextureRect.new()
	eraser.texture = _shaped("desk_eraser", 46, 30, _fn_eraser)
	eraser.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eraser.stretch_mode = TextureRect.STRETCH_SCALE
	eraser.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ew: float = _vp.x * 0.135
	eraser.size = Vector2(ew, ew * (30.0 / 46.0))
	eraser.pivot_offset = eraser.size * 0.5
	eraser.rotation = deg_to_rad(13.0)
	eraser.position = Vector2(_vp.x * 0.78, _vp.y * 0.885)
	add_child(eraser)
	var eshade := TextureRect.new()
	eshade.texture = _round()
	eshade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eshade.stretch_mode = TextureRect.STRETCH_SCALE
	eshade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eshade.size = eraser.size * Vector2(1.3, 1.9)
	eshade.position = eraser.position + Vector2(0.0, eraser.size.y * 0.55) - eshade.size * 0.5
	eshade.modulate = Color(ink.r, ink.g, ink.b, 0.07)
	add_child(eshade)
	move_child(eshade, eshade.get_index() - 1)
	# Shavings: curls of painted wood, one per sharpening.
	var curl := _shaped("desk_shaving", 44, 34, _fn_shaving)
	for e2_v in [[0.34, 0.955, 0.075, 0.5], [0.44, 0.925, 0.055, -1.1],
			[0.28, 0.905, 0.045, 2.3], [0.53, 0.965, 0.062, 1.7]]:
		var e2: Array = e2_v
		var sh := TextureRect.new()
		sh.texture = curl
		sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sh.stretch_mode = TextureRect.STRETCH_SCALE
		sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sw: float = _vp.x * float(e2[2])
		sh.size = Vector2(sw, sw * (34.0 / 44.0))
		sh.pivot_offset = sh.size * 0.5
		sh.rotation = float(e2[3])
		sh.position = Vector2(_vp.x * float(e2[0]), _vp.y * float(e2[1])) - sh.size * 0.5
		sh.modulate = Color(1, 1, 1, 0.95)
		add_child(sh)
	# A paper plane crossing the page now and then.
	_paper_planes(_gen)

## A block eraser, seen at a slight angle: a soft rubber slab with rounded
## edges, a paper sleeve round its middle, and a corner worn round with use.
func _fn_eraser(uv: Vector2) -> Color:
	const AR := 0.652     # bake 46x30
	var sy := uv.y / AR
	# A rounded rectangle — rubber has no sharp edges left after a week.
	var d: float = pow(absf(uv.x), 5.0) + pow(absf(sy), 5.0)
	if d > 1.0:
		return Color(0, 0, 0, 0)
	var a: float = 1.0 - smoothstep(0.86, 1.0, d)
	# Lit from above-left; the top face is flat, the sides roll away.
	var lam: float = clampf(0.86 - sy * 0.34 - uv.x * 0.12, 0.30, 1.0)
	var col := Color(1.0, 0.94, 0.86)
	col = Color(col.r * lam, col.g * lam, col.b * lam)
	# The paper sleeve round its waist.
	if absf(uv.x) < 0.34:
		col = Color(0.30, 0.44, 0.72).lerp(Color(0.62, 0.74, 0.94), clampf(0.6 - sy * 0.4, 0.0, 1.0))
		if absf(absf(uv.x) - 0.34) < 0.04:
			col = col.darkened(0.25)
	# The worn corner, greyed with graphite.
	col = col.lerp(Color(0.55, 0.54, 0.56),
		clampf(1.0 - Vector2(uv.x - 0.86, sy - 0.72).length() * 1.6, 0.0, 1.0) * 0.55)
	return Color(col.r, col.g, col.b, a)

## A pencil shaving: the curl of painted wood a sharpener throws off, seen from
## above — a crescent with the paint on its outer edge and raw wood inside.
func _fn_shaving(uv: Vector2) -> Color:
	const AR := 0.773     # bake 44x34
	var sy := uv.y / AR
	var p := Vector2(uv.x, sy)
	var r := p.length()
	var ang := atan2(sy, uv.x)
	# A crescent: an annulus cut to about two-thirds of a turn, with a scalloped
	# outer edge — a shaving is never a clean ring.
	var outer: float = 0.94 + 0.06 * sin(ang * 7.0)
	var inner: float = 0.42 + 0.10 * sin(ang * 5.0 + 1.0)
	if r > outer or r < inner:
		return Color(0, 0, 0, 0)
	if ang > 1.1 and ang < 2.5:
		return Color(0, 0, 0, 0)
	var a: float = (1.0 - smoothstep(outer - 0.10, outer, r)) 		* smoothstep(inner, inner + 0.09, r)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var f: float = (r - inner) / maxf(outer - inner, 0.01)
	# Raw wood inside, the pencil's own yellow lacquer on the outer skin.
	var col := Color(0.94, 0.84, 0.66).lerp(Color(0.72, 0.58, 0.38), pow(1.0 - f, 1.4) * 0.6)
	col = col.lerp(Color(1.0, 0.78, 0.16), smoothstep(0.74, 1.0, f))
	# It curls, so the light runs round it.
	col = col.lerp(Color(1.0, 0.98, 0.92),
		clampf(1.0 - absf(f - 0.45) * 3.0, 0.0, 1.0) * 0.35 * clampf(0.5 - sy, 0.0, 1.0))
	return Color(col.r, col.g, col.b, a)

func _paper_planes(gen: int) -> void:
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(6.0, 13.0)).timeout
		if gen != _gen or not is_inside_tree():
			return
		var plane := TextureRect.new()
		plane.texture = _shaped("paper_plane", 38, 26, _fn_plane)
		plane.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		plane.stretch_mode = TextureRect.STRETCH_SCALE
		plane.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * 0.13
		plane.size = Vector2(w, w * 0.66)
		plane.pivot_offset = plane.size * 0.5
		var dir: float = 1.0 if randf() < 0.5 else -1.0
		plane.scale = Vector2(dir, 1.0)
		var y0: float = _vp.y * randf_range(0.14, 0.80)
		plane.position = Vector2(-w * 2.0 if dir > 0.0 else _vp.x + w, y0)
		plane.rotation = deg_to_rad(-6.0 * dir)
		plane.modulate = Color(1, 1, 1, 0.0)
		add_child(plane)
		var dur := randf_range(4.0, 6.5)
		var tw := plane.create_tween()
		tw.set_parallel(true)
		tw.tween_property(plane, "position:x",
			(_vp.x + w * 2.0) if dir > 0.0 else -w * 2.0, dur).set_trans(Tween.TRANS_LINEAR)
		# It sinks and lifts on the air rather than flying a ruled line.
		tw.tween_property(plane, "position:y", y0 + _vp.y * 0.10, dur * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(plane, "modulate:a", 0.85, 0.6)
		tw.chain().tween_property(plane, "position:y", y0 - _vp.y * 0.04, dur * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.chain().tween_property(plane, "modulate:a", 0.0, 0.6)
		tw.chain().tween_callback(plane.queue_free)

## Daybreak — an actual sunrise: the sun sitting on the horizon with god rays
## fanning off it and low cloud bands catching the light from underneath.
func _dawn_horizon() -> void:
	var warm := Color(1.0, 0.60, 0.26).lerp(_pc("accent"), 0.25)
	var sun_c := Vector2(_vp.x * 0.50, _vp.y * 0.90)
	# The glow the sun sits in, biggest and softest first.
	for e_v in [[3.2, 0.10], [1.9, 0.14], [1.15, 0.22]]:
		var e: Array = e_v
		var g := TextureRect.new()
		g.texture = _round()
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_SCALE
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = _vp.x * float(e[0])
		g.size = Vector2(d, d * 0.72)
		g.position = sun_c - g.size * 0.5
		var a: float = float(e[1]) * 2.6
		g.modulate = Color(warm.r, warm.g, warm.b, a * 0.7)
		add_child(g)
		var tw := g.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(g, "modulate:a", a, randf_range(4.5, 7.0))
		tw.tween_property(g, "modulate:a", a * 0.55, randf_range(5.0, 7.5))
	# God rays fanning up off the horizon, each on its own slow breath.
	for i in 7:
		var ray := TextureRect.new()
		ray.texture = _round()
		ray.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ray.stretch_mode = TextureRect.STRETCH_SCALE
		ray.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.10, 0.20)
		var h: float = _vp.y * randf_range(0.55, 0.95)
		ray.size = Vector2(w, h)
		ray.pivot_offset = Vector2(w * 0.5, h)          # pivots at the horizon
		ray.position = Vector2(sun_c.x - w * 0.5, sun_c.y - h)
		ray.rotation = deg_to_rad(lerpf(-42.0, 42.0, float(i) / 6.0) + randf_range(-4.0, 4.0))
		var peak: float = randf_range(0.16, 0.30)
		ray.modulate = Color(1.0, 0.72, 0.34, peak * 0.4)
		add_child(ray)
		var tw := ray.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(randf_range(0.0, 3.0))
		tw.tween_property(ray, "modulate:a", peak, randf_range(3.5, 6.0))
		tw.tween_property(ray, "modulate:a", peak * 0.3, randf_range(4.0, 6.5))
	# The sun's disc itself, just clearing the horizon.
	var sun := TextureRect.new()
	sun.texture = _dot()
	sun.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sd: float = _vp.x * 0.34
	sun.size = Vector2(sd, sd)
	sun.position = sun_c - sun.size * 0.5
	sun.modulate = Color(1.0, 0.78, 0.34, 0.95)
	add_child(sun)
	# The range the sun is coming up behind. Far ridges first, then the low
	# cloud bands drifting BETWEEN the layers as morning mist, then the near
	# ridges over the top of it - which is the whole reason the bands moved out
	# of last place.
	_dawn_ranges(false)
	# Low cloud bands, lit from beneath.
	_cloud_bands(warm)
	_dawn_ranges(true)

## Daybreak — the range the sun comes up behind. Four ridgelines drawn far to
## near, each sitting LOWER on the frame and less washed by haze than the one
## behind it, so the sky recedes properly instead of stacking flat cut-outs.
##
## The profile leaves a SADDLE at its middle on purpose: the sun sits at x 0.50,
## and a ridge with a summit dead-centre would simply swallow it. Through the
## notch the disc shows half-risen with peaks flanking it, which is the whole
## picture a sunrise is. Split into a far pass and a near pass so `_cloud_bands`
## can drift between them.
func _dawn_ranges(near: bool) -> void:
	var sky: Color = _pc("bg0")
	# [crest y-frac at the SADDLE, relief as a frac of height, x-phase, tint]
	# The saddles sit BELOW the sun's centre (y 0.90) on purpose. Pitched higher,
	# the farthest ridge simply swallows the disc and the sunrise loses its sun -
	# which is exactly what the first placement did.
	var ranges := [
		[0.878, 0.098, 0.00, Color(0.56, 0.52, 0.76)],
		[0.906, 0.082, 2.30, Color(0.44, 0.39, 0.66)],
	]
	if near:
		ranges = [
			[0.940, 0.068, 4.90, Color(0.30, 0.25, 0.50)],
			[0.974, 0.054, 1.15, Color(0.19, 0.15, 0.36)],
		]
	for i in ranges.size():
		var e: Array = ranges[i]
		var t: Color = e[3]
		# Aerial perspective: the far ranges wash toward the sky behind them, and
		# the far PASS washes harder than the near one.
		var haze: float = (0.44 if not near else 0.14) * float(ranges.size() - i) / 2.0
		var canvas := Control.new()
		canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.size = _vp
		canvas.draw.connect(_draw_dawn_ridge.bind(canvas,
			float(e[0]), float(e[1]), float(e[2]), t.lerp(sky, haze), near))
		canvas.add_to_group("dawn_ranges")   # the smoke asserts all four stand
		add_child(canvas)
		canvas.queue_redraw()

## One ridgeline, DRAWN rather than baked. A per-pixel bake of a skyline is a
## texture stretched three-to-one across the frame, and every near-vertical flank
## comes out as a staircase; sampled as a polygon it is sharp at any size, costs
## nothing to build, and lets the sunlit crest be a real line along the top edge
## instead of a second copy of the sprite nudged upward.
##
## `saddle` is where the skyline sits at its LOWEST, `relief` how far the summits
## rise above it, both as fractions of the viewport height. The profile leaves
## its low point around the middle of the frame on purpose: the sun sits at
## x 0.50, and a summit dead-centre simply swallows it - through the notch the
## disc shows half-risen with peaks flanking it, which is the whole picture a
## sunrise is.
func _draw_dawn_ridge(c: Control, saddle: float, relief: float, phase: float,
		tint: Color, near: bool) -> void:
	const STEPS := 96
	var pts := PackedVector2Array()
	var crest := PackedVector2Array()
	for i in STEPS + 1:
		var u := float(i) / float(STEPS)          # 0..1 across the frame
		var x := u * _vp.x
		# Summits are POWER cones, not gaussians: a gaussian shoulder is round
		# and the first cut of this read as a row of jelly hills. Rock has
		# straight flanks.
		var d := u * 2.0 - 1.0                    # -1..1, so 0 is frame centre
		var lift := 0.0
		lift += 1.00 * pow(maxf(0.0, 1.0 - absf(d + 0.72 + 0.10 * sin(phase)) / 0.30), 1.15)
		lift += 0.58 * pow(maxf(0.0, 1.0 - absf(d + 0.30 + 0.08 * sin(phase * 1.7)) / 0.20), 1.30)
		lift += 0.52 * pow(maxf(0.0, 1.0 - absf(d - 0.36 - 0.08 * sin(phase * 1.3)) / 0.19), 1.30)
		lift += 0.92 * pow(maxf(0.0, 1.0 - absf(d - 0.76 - 0.10 * sin(phase * 0.9)) / 0.28), 1.15)
		# Roughness, so no flank is a ruled line.
		lift += 0.055 * sin(d * 9.1 + phase) + 0.028 * sin(d * 23.0 + phase * 2.1)
		var y: float = _vp.y * saddle - _vp.y * relief * maxf(lift, 0.0)
		pts.append(Vector2(x, y))
		crest.append(Vector2(x, y))
	# Close the polygon off the bottom of the frame so the range never shows an
	# edge of its own.
	pts.append(Vector2(_vp.x, _vp.y * 1.05))
	pts.append(Vector2(0.0, _vp.y * 1.05))
	c.draw_colored_polygon(pts, tint)
	# The sunlit crest. Thin, warm and only just there: the light is BEHIND the
	# mountain, so all that reaches us is the edge - and the FAR ridge, the one
	# the sun is actually coming over, catches the most of it. Drawn at equal
	# weight on all four it stops being light and becomes a contour map.
	c.draw_polyline(crest, Color(1.0, 0.78, 0.46, 0.16 if near else 0.34),
		maxf(_vp.y * 0.0018, 1.0), true)

## Daybreak — the branch the morning happens on. A bare limb reaching in from
## the left across the top of the sky, with a few twigs off it, drawn as a
## tapered polygon off a bezier spine (a per-pixel bake cannot hold a twig at
## any affordable resolution - see _draw_grove_wood, which learned it first).
##
## The PERCH POINTS come off the same spine the limb is drawn from, so a bird's
## feet land on the wood rather than near it.
const _DAWN_LIMB := [Vector2(-0.06, 0.336), Vector2(0.19, 0.330),
	Vector2(0.41, 0.212), Vector2(0.67, 0.142)]
## [t along the limb, control offset, tip offset] - all in viewport fractions,
## rooted ON the spine so no twig ever floats off the branch.
## A side branch follows the limb's own run, sweeping forward off it. Angled
## across it instead, they read as wires soldered on.
const _DAWN_TWIGS := [
	[0.18, Vector2(0.024, -0.028), Vector2(0.062, -0.050)],
	[0.44, Vector2(0.028, -0.024), Vector2(0.072, -0.038)],
	[0.62, Vector2(0.022, 0.028), Vector2(0.060, 0.050)],
	[0.86, Vector2(0.030, -0.020), Vector2(0.068, -0.028)],
]
## Where along the limb a bird can sit, and who is sitting there (null = free).
var _dawn_perches: PackedVector2Array = PackedVector2Array()
var _dawn_perch_birds: Array = []

func _dawn_spine() -> PackedVector2Array:
	return _bez_pts(_DAWN_LIMB[0], _DAWN_LIMB[1], _DAWN_LIMB[2], _DAWN_LIMB[3], 26)

func _dawn_branch() -> void:
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.size = _vp
	canvas.draw.connect(_draw_dawn_branch.bind(canvas))
	canvas.add_to_group("dawn_branch")
	add_child(canvas)
	canvas.queue_redraw()
	var spine := _dawn_spine()
	_dawn_perches = PackedVector2Array()
	for f_v in [0.30, 0.52, 0.74, 0.92]:
		var f: float = f_v
		var idx := clampi(int(round(f * float(spine.size() - 1))), 0, spine.size() - 1)
		# Up off the spine by the limb's own half-thickness there, so the feet
		# sit ON the top of the wood.
		_dawn_perches.append(spine[idx] - Vector2(0.0, _vp.x * lerpf(0.0095, 0.0021, f)))
	_dawn_perch_birds.resize(_dawn_perches.size())
	for i in _dawn_perch_birds.size():
		_dawn_perch_birds[i] = null

func _draw_dawn_branch(c: Control) -> void:
	# Almost black against a bright sky: a foreground limb at dawn is a
	# silhouette, and any local colour in it kills the depth.
	var wood := Color(0.13, 0.10, 0.20)
	var spine := _dawn_spine()
	var w0: float = _vp.x * 0.019
	var w1: float = _vp.x * 0.0042
	c.draw_colored_polygon(_taper_poly(spine, w0, w1), wood)
	for e_v in _DAWN_TWIGS:
		var e: Array = e_v
		var idx := clampi(int(round(float(e[0]) * float(spine.size() - 1))), 0, spine.size() - 1)
		var root: Vector2 = spine[idx]
		var ctrl: Vector2 = root + (e[1] as Vector2) * _vp
		var tip: Vector2 = root + (e[2] as Vector2) * _vp
		var tw: float = lerpf(w0, w1, float(e[0]))
		c.draw_colored_polygon(
			_taper_poly(_bez_px(root, ctrl, ctrl, tip, 10), tw * 0.58, tw * 0.12), wood)
	# The sun catches the top edge of the limb - the same light the ridges wear.
	var lit := PackedVector2Array()
	for i in spine.size():
		var t: float = float(i) / float(maxi(spine.size() - 1, 1))
		lit.append(spine[i] - Vector2(0.0, lerpf(w0, w1, t) * 0.34))
	c.draw_polyline(lit, Color(1.0, 0.78, 0.48, 0.30), maxf(_vp.y * 0.0016, 1.0), true)

## The two birds the world's own flock is made of, baked through BoardFx's cache
## from Confetti's STATIC painters - so the bird that lands on this branch is
## provably the same animal that flies in the celebration, rather than a second
## drawing of one.
func _dawn_perch_tex(v: int) -> Texture2D:
	return _shaped("dawn_perch_%d" % v, 44, 56,
		func(uv: Vector2) -> Color: return Confetti._bird_perch_body(uv, v))

func _dawn_fly_tex(v: int, frame: int) -> Texture2D:
	return _shaped("dawn_fly_%d_%d" % [v, frame], 56, 44,
		func(uv: Vector2) -> Color: return Confetti._bird_body(uv, v, frame))

## Life on the branch: birds arrive, sit a while, and leave again. Two are
## already sitting when the world opens so the branch is never provably empty
## (and so the smoke can see it), and from then on each beat either brings one
## in to a free perch or sends a sitting one off.
func _dawn_perch_life(gen: int) -> void:
	for i in mini(2, _dawn_perches.size()):
		_dawn_perch_seat(i)
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(3.0, 6.5)).timeout
		if gen != _gen or not is_inside_tree():
			return
		var free_slots: Array[int] = []
		var taken: Array[int] = []
		for i in _dawn_perch_birds.size():
			var b = _dawn_perch_birds[i]
			if b == null or not is_instance_valid(b):
				_dawn_perch_birds[i] = null
				free_slots.append(i)
			else:
				taken.append(i)
		if not free_slots.is_empty() and (taken.size() < 2 or randf() < 0.55):
			_dawn_perch_arrive(free_slots[randi() % free_slots.size()])
		elif not taken.is_empty():
			_dawn_perch_depart(taken[randi() % taken.size()])

## Put a bird on perch `i` right now, sitting.
func _dawn_perch_seat(i: int) -> void:
	if i < 0 or i >= _dawn_perches.size():
		return
	var b := TextureRect.new()
	b.texture = _dawn_perch_tex(i % 2)
	b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	b.stretch_mode = TextureRect.STRETCH_SCALE
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bw: float = _vp.x * randf_range(0.068, 0.090)
	b.size = Vector2(bw, bw * (56.0 / 44.0))     # the perched bake is 44x56
	# The pivot is its FEET, so a shift on the branch rocks the bird rather than
	# sliding it, and the sprite drops onto the wood by the same offset.
	b.pivot_offset = Vector2(b.size.x * 0.5, b.size.y * 0.95)
	b.position = _dawn_perches[i] - b.pivot_offset
	b.add_to_group("dawn_perched")
	add_child(b)
	_dawn_perch_birds[i] = b
	# Idle: every few seconds a small shift of weight. A perfectly still bird is
	# a decal.
	var t := b.create_tween().set_loops()
	t.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_interval(randf_range(1.4, 3.4))
	t.tween_property(b, "rotation", deg_to_rad(randf_range(-6.0, 6.0)), 0.20)
	t.tween_property(b, "rotation", 0.0, 0.26)

## A bird flies IN from off the left and lands on perch `i`.
func _dawn_perch_arrive(i: int) -> void:
	if i < 0 or i >= _dawn_perches.size():
		return
	var v := i % 2
	var seat: Vector2 = _dawn_perches[i]
	var flier := TextureRect.new()
	flier.texture = _dawn_fly_tex(v, 1)
	flier.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flier.stretch_mode = TextureRect.STRETCH_SCALE
	flier.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fw: float = _vp.x * 0.105
	flier.size = Vector2(fw, fw * (44.0 / 56.0))
	flier.pivot_offset = flier.size * 0.5
	var start := Vector2(-fw, seat.y - _vp.y * randf_range(0.02, 0.10))
	flier.position = start - flier.size * 0.5
	add_child(flier)
	var tw := flier.create_tween()
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(flier, "position", seat - flier.size * 0.5 - Vector2(0.0, fw * 0.30),
		randf_range(1.1, 1.6))
	# The FLARE: wings up as it stalls onto the branch. Every bird does this and
	# without it a landing reads as a sprite teleporting onto the wood.
	tw.parallel().tween_callback(_dawn_wing.bind(flier, v, 0)).set_delay(0.75)
	tw.tween_callback(flier.queue_free)
	tw.tween_callback(_dawn_perch_seat.bind(i))
	# Wingbeat on the way in.
	var beat := flier.create_tween().set_loops()
	for k in 4:
		for fr_v in [1, 0, 1, 2]:
			var fr: int = fr_v
			beat.tween_callback(_dawn_wing.bind(flier, v, fr))
			beat.tween_interval(0.075)

## A sitting bird drops off the branch and flies away.
func _dawn_perch_depart(i: int) -> void:
	if i < 0 or i >= _dawn_perch_birds.size():
		return
	var sitting = _dawn_perch_birds[i]
	_dawn_perch_birds[i] = null
	if sitting != null and is_instance_valid(sitting):
		sitting.queue_free()
	var v := i % 2
	var seat: Vector2 = _dawn_perches[i]
	var flier := TextureRect.new()
	flier.texture = _dawn_fly_tex(v, 0)
	flier.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flier.stretch_mode = TextureRect.STRETCH_SCALE
	flier.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fw: float = _vp.x * 0.105
	flier.size = Vector2(fw, fw * (44.0 / 56.0))
	flier.pivot_offset = flier.size * 0.5
	flier.position = seat - flier.size * 0.5 - Vector2(0.0, fw * 0.20)
	# Away to the right and up, banked onto that line.
	var target := Vector2(_vp.x + fw, seat.y - _vp.y * randf_range(0.10, 0.24))
	flier.rotation = (target - seat).angle()
	add_child(flier)
	var tw := flier.create_tween()
	tw.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tw.tween_property(flier, "position", target - flier.size * 0.5, randf_range(1.0, 1.5))
	tw.tween_callback(flier.queue_free)
	var beat := flier.create_tween().set_loops()
	for k in 4:
		for fr_v in [0, 1, 2, 1]:
			var fr: int = fr_v
			beat.tween_callback(_dawn_wing.bind(flier, v, fr))
			beat.tween_interval(0.065)

func _dawn_wing(flier: TextureRect, v: int, frame: int) -> void:
	if is_instance_valid(flier):
		flier.texture = _dawn_fly_tex(v, frame)

## Daybreak — the dawn chorus: every so often a loose line of small birds
## crosses high over the sunrise, wingbeats coming in bursts with a GLIDE
## between them. The Blood Moon ravens' pattern (crossing tween + squash
## wingbeat), worn lighter: fewer, smaller, deep dawn violet against the pale
## sky instead of black against the moon. One flight greets the entry frame so
## the morning is never provably birdless (and so the smoke can see it).
func _dawn_birds(gen: int) -> void:
	_dawn_bird_pass()
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(8.0, 15.0)).timeout
		if gen != _gen or not is_inside_tree():
			return
		_dawn_bird_pass()

func _dawn_bird_pass() -> void:
	var dir: float = 1.0 if randf() < 0.5 else -1.0
	var y0: float = _vp.y * randf_range(0.08, 0.30)
	var n := maxi(int(7.0 * _particle_scale()), 3)
	for i in n:
		var b := TextureRect.new()
		b.texture = _shaped("dawn_bird", 40, 26, _fn_dawn_bird)
		b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		b.stretch_mode = TextureRect.STRETCH_SCALE
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# A skein has DEPTH: at one flat size they read as a row of printed
		# marks, and at the old 2.8-5.0% of the frame they barely read at all.
		var deep := pow(randf(), 1.4)
		var w: float = _vp.x * lerpf(0.038, 0.086, deep)
		b.size = Vector2(w, w * 0.65)
		b.pivot_offset = b.size * 0.5
		var y: float = y0 + _vp.y * randf_range(-0.075, 0.075)
		b.position = Vector2(
			(-w * 2.0 if dir > 0.0 else _vp.x + w) - float(i) * w * dir * randf_range(1.4, 2.6), y)
		# Deep dawn violet, not black: a silhouette against a PALE sky.
		b.modulate = Color(0.30, 0.24, 0.46, lerpf(0.55, 0.92, deep))
		b.add_to_group("dawn_birds")
		add_child(b)
		var dur := randf_range(6.0, 9.0)
		var tw := b.create_tween()
		tw.set_parallel(true)
		tw.tween_property(b, "position:x",
			(_vp.x + w * 3.0) if dir > 0.0 else -w * 3.0, dur)
		# A shallow climb as it crosses — a morning bird is going somewhere UP.
		tw.tween_property(b, "position:y", y - _vp.y * randf_range(0.02, 0.06), dur)
		# Wingbeats in bursts of three with a glide between — the bird rhythm.
		var beat := b.create_tween().set_loops()
		beat.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		for k in 3:
			beat.tween_property(b, "scale:y", 0.55, randf_range(0.12, 0.18))
			beat.tween_property(b, "scale:y", 1.0, randf_range(0.12, 0.18))
		beat.tween_interval(randf_range(0.35, 0.8))
		tw.chain().tween_callback(b.queue_free)

## A distant bird on the wing: the classic shallow gull-"m" — two arcs lifting
## to the tips off a small body — as a soft mask the flock tints.
func _fn_dawn_bird(uv: Vector2) -> Color:
	var x := absf(uv.x)
	if x > 1.0:
		return Color(0, 0, 0, 0)
	var yc := 0.30 - 0.85 * pow(x, 1.5)          # wing arc, tips raised
	var th := 0.16 * (1.0 - 0.7 * x) + 0.05      # tapering toward the tips
	var wing := 1.0 - smoothstep(th * 0.45, th, absf(uv.y - yc))
	var body: float = 1.0 - smoothstep(0.10, 0.30, Vector2(uv.x, (uv.y - 0.30) * 0.8).length())
	var a := maxf(wing, body)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var bshade := clampf(0.82 - 0.20 * x, 0.5, 1.0)
	return Color(bshade, bshade, bshade, a)

## Obsidian — the floor the stardrift falls onto: a sheet of volcanic glass,
## cracked, with cold light coming up out of the fissures.
func _obsidian_floor() -> void:
	var teal: Color = _pc("accent").lerp(Color(0.25, 0.95, 0.80), 0.6)
	var slab := TextureRect.new()
	slab.texture = _shaped("obsidian_slab", 150, 56, _fn_obsidian)
	slab.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	slab.stretch_mode = TextureRect.STRETCH_SCALE
	slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h: float = _vp.y * 0.20
	slab.size = Vector2(_vp.x * 1.02, h)
	slab.position = Vector2(-_vp.x * 0.01, _vp.y - h)
	slab.modulate = Color(1, 1, 1, 0.95)
	add_child(slab)
	# The light in the fissures, pulsing as if something under it were alive.
	for i in 4:
		var crack := TextureRect.new()
		crack.texture = _round()
		crack.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crack.stretch_mode = TextureRect.STRETCH_SCALE
		crack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.16, 0.34)
		crack.size = Vector2(w, h * 0.55)
		crack.position = Vector2(_vp.x * (0.10 + 0.26 * float(i)) - w * 0.5, _vp.y - h * 0.75)
		var peak: float = randf_range(0.10, 0.20)
		crack.modulate = Color(teal.r, teal.g, teal.b, peak * 0.4)
		add_child(crack)
		var tw := crack.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(randf_range(0.0, 2.5))
		tw.tween_property(crack, "modulate:a", peak, randf_range(2.5, 4.0))
		tw.tween_property(crack, "modulate:a", peak * 0.25, randf_range(3.0, 4.5))
	# The slab's own sheen — obsidian is glass, and glass has a horizon line.
	_edge_glow(teal, 0.04, 0.10, false)

## Candy Pop — the sweet shop: a gumball machine on the counter, a lollipop and
## a pair of candy canes leaning beside it.
## One garland of triangular pennants sagging in a catenary across the screen,
## each flag lifting on the breeze out of step with its neighbours. Extracted
## from the fairground's `_park_lights` when the sweet shop wanted the same
## bunting — the geometry is the fairground's, unchanged.
func _pennant_line(y0: float, sag: float, n: int, flag_w: float,
		cols: Array, alpha: float) -> void:
	var flag_tex := _shaped("fair_pennant", 28, 36, _fn_pennant)
	var line := Control.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
	var prev := Vector2(-_vp.x * 0.05, y0)
	for i in range(n + 1):
		var f: float = float(i) / float(n)
		var x: float = lerpf(-_vp.x * 0.05, _vp.x * 1.05, f)
		# A catenary: deepest in the middle, level at the two anchors.
		var here := Vector2(x, y0 + sag * sin(f * PI))
		var seg := ColorRect.new()
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seg.color = Color(1, 1, 1, 0.16)
		var d := here - prev
		seg.size = Vector2(d.length(), maxf(_vp.x * 0.0035, 1.0))
		seg.pivot_offset = Vector2(0.0, seg.size.y * 0.5)
		seg.position = prev - Vector2(0.0, seg.size.y * 0.5)
		seg.rotation = d.angle()
		line.add_child(seg)
		prev = here
		if i == n:
			break
		var flag := TextureRect.new()
		flag.texture = flag_tex
		flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		flag.stretch_mode = TextureRect.STRETCH_SCALE
		flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flag.size = Vector2(flag_w, flag_w * 1.3)
		flag.pivot_offset = Vector2(flag_w * 0.5, 0.0)
		flag.position = here - Vector2(flag_w * 0.5, 0.0)
		var fc: Color = cols[i % cols.size()]
		flag.modulate = Color(fc.r, fc.g, fc.b, alpha)
		line.add_child(flag)
		var sw := flag.create_tween().set_loops()
		sw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		sw.tween_interval(f * 0.5)
		sw.tween_property(flag, "rotation", 0.14, randf_range(1.5, 2.2))
		sw.tween_property(flag, "rotation", -0.12, randf_range(1.5, 2.2))

## Emerald / Ruby — the geode the stones come out of: a cluster of big crystals
## growing up out of the bottom edge, each catching the light on its own clock.
func _gem_geode() -> void:
	var stone: Color = ThemeManager.board_accent_for(_pal())
	if stone.a <= 0.0:
		stone = _pc("accent")
	var tex := _shaped("geode_crystal", 44, 120, _fn_crystal)
	# [x-frac, height-frac, lean deg, alpha]
	var cluster := [[0.05, 0.24, -13.0, 0.92], [0.17, 0.15, 7.0, 0.78],
		[0.50, 0.11, -4.0, 0.6], [0.85, 0.27, 10.0, 0.95],
		[0.96, 0.17, -8.0, 0.78], [0.71, 0.13, 3.0, 0.66]]
	for e_v in cluster:
		var e: Array = e_v
		var h: float = _vp.y * float(e[1])
		var w: float = h * (70.0 / 190.0) * 1.55
		var c := TextureRect.new()
		c.texture = tex
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c.stretch_mode = TextureRect.STRETCH_SCALE
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.size = Vector2(w, h)
		c.pivot_offset = Vector2(w * 0.5, h)
		c.rotation = deg_to_rad(float(e[2]))
		c.position = Vector2(_vp.x * float(e[0]) - w * 0.5, _vp.y * 1.01 - h)
		var a: float = float(e[3])
		c.modulate = Color(stone.r, stone.g, stone.b, a)
		add_child(c)
		# The glint: a hard, quick flash, then a long wait — a facet catching
		# the light as the world turns, not a lamp on a dimmer.
		var glint := TextureRect.new()
		glint.texture = _shaped("geode_glint", 40, 40, _fn_star4_glint)
		glint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glint.stretch_mode = TextureRect.STRETCH_SCALE
		glint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gd: float = w * 1.1
		glint.size = Vector2(gd, gd)
		glint.position = Vector2(_vp.x * float(e[0]) - gd * 0.5,
			_vp.y * 1.01 - h * randf_range(0.55, 0.85) - gd * 0.5)
		glint.modulate = Color(1, 1, 1, 0.0)
		add_child(glint)
		var tw := glint.create_tween().set_loops()
		tw.tween_interval(randf_range(1.5, 6.0))
		tw.tween_property(glint, "modulate:a", 0.9, 0.12)
		tw.tween_property(glint, "modulate:a", 0.0, 0.5)
	_edge_glow(stone, 0.05, 0.12, false)

## Kawaii — the sky it all floats in: fat clouds, a rainbow arc over them, and a
## cat face that peeks out of a cloud every so often and ducks back in.
func _kawaii_sky() -> void:
	var pink := _pc("accent").lerp(Color(1.0, 0.72, 0.86), 0.5)
	# The rainbow, drawn as nested rings with the top half showing.
	var bands := [Color(1.0, 0.45, 0.55), Color(1.0, 0.72, 0.42),
		Color(1.0, 0.92, 0.50), Color(0.55, 0.92, 0.62),
		Color(0.50, 0.78, 1.0), Color(0.78, 0.60, 1.0)]
	for i in bands.size():
		var arc := TextureRect.new()
		arc.texture = _ring()
		arc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		arc.stretch_mode = TextureRect.STRETCH_SCALE
		arc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# A rainbow is an ARC, not a hoop: the centre of the circle is pushed
		# below the bottom of the screen so only the crown of it is ever in
		# frame. Centring it in the sky drew a full ring hanging in the air.
		var d: float = _vp.x * (2.30 - float(i) * 0.145)
		arc.size = Vector2(d, d)
		arc.position = Vector2(_vp.x * 0.5 - d * 0.5, _vp.y * 1.12 - d * 0.5)
		var c: Color = bands[i]
		arc.modulate = Color(c.r, c.g, c.b, 0.55)
		add_child(arc)
	# Clouds along the bottom band.
	var cloud := _shaped("kawaii_cloud", 160, 80, _fn_cloud)
	for e_v in [[0.16, 0.90, 0.44, 0.92], [0.62, 0.955, 0.56, 0.96],
			[0.92, 0.88, 0.34, 0.8]]:
		var e: Array = e_v
		var w: float = _vp.x * float(e[2])
		var c := TextureRect.new()
		c.texture = cloud
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c.stretch_mode = TextureRect.STRETCH_SCALE
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.size = Vector2(w, w * 0.5)
		c.position = Vector2(_vp.x * float(e[0]) - w * 0.5, _vp.y * float(e[1]) - w * 0.25)
		c.modulate = Color(0.99, 0.80, 0.92, float(e[3]))
		add_child(c)
		var tw := c.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(c, "position:x", c.position.x + _vp.x * 0.03, randf_range(7.0, 11.0))
		tw.tween_property(c, "position:x", c.position.x, randf_range(7.0, 11.0))
	# The cat, peeking over the middle cloud.
	var cat := TextureRect.new()
	cat.texture = _shaped("kawaii_cat", 96, 80, _fn_cat)
	cat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cat.stretch_mode = TextureRect.STRETCH_SCALE
	cat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cw: float = _vp.x * 0.22
	cat.size = Vector2(cw, cw * 0.83)
	var down_pos := Vector2(_vp.x * 0.62 - cw * 0.5, _vp.y * 0.955 - cw * 0.02)
	var up_pos := down_pos - Vector2(0.0, cw * 0.62)
	cat.position = down_pos
	cat.modulate = Color(pink.r * 0.85, pink.g * 0.52, pink.b * 0.70, 0.98)
	add_child(cat)
	move_child(cat, maxi(cat.get_index() - 1, 0))     # behind its cloud
	var peek := cat.create_tween().set_loops()
	peek.tween_interval(randf_range(3.0, 6.0))
	peek.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	peek.tween_property(cat, "position", up_pos, 0.7)
	peek.tween_interval(2.2)
	peek.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	peek.tween_property(cat, "position", down_pos, 0.5)
	peek.tween_interval(randf_range(4.0, 9.0))

## Cosmic Nebula — the thing a nebula is FOR: a protostar deep in the gas that
## gathers, flares into life, and settles again, lighting the cloud around it.
func _protostar() -> void:
	var c := Vector2(_vp.x * 0.66, _vp.y * 0.30)
	var hot := Color(1.0, 0.94, 0.82)
	var halo := TextureRect.new()
	halo.texture = _round()
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_SCALE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hd: float = _vp.x * 0.9
	halo.size = Vector2(hd, hd)
	halo.pivot_offset = halo.size * 0.5
	halo.position = c - halo.size * 0.5
	halo.modulate = Color(hot.r, hot.g, hot.b, 0.05)
	add_child(halo)
	var core := TextureRect.new()
	core.texture = _dot()
	core.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	core.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cd: float = _vp.x * 0.10
	core.size = Vector2(cd, cd)
	core.pivot_offset = core.size * 0.5
	core.position = c - core.size * 0.5
	core.modulate = Color(hot.r, hot.g, hot.b, 0.35)
	add_child(core)
	# Dust falling in toward it — the disc that feeds the star.
	var infall := CPUParticles2D.new()
	infall.position = c
	infall.amount = maxi(int(30.0 * _particle_scale()), 8)
	infall.lifetime = 4.5
	infall.preprocess = 2.0
	infall.texture = _dot()
	infall.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	infall.emission_sphere_radius = _vp.x * 0.55
	infall.direction = Vector2(0, -1)
	infall.spread = 180.0
	infall.initial_velocity_min = 2.0
	infall.initial_velocity_max = 10.0
	infall.radial_accel_min = -70.0
	infall.radial_accel_max = -28.0
	infall.tangential_accel_min = 22.0
	infall.tangential_accel_max = 55.0
	infall.scale_amount_min = 0.2
	infall.scale_amount_max = 0.6
	infall.color_ramp = _alpha_ramp(_pc("accent").lerp(hot, 0.4), 0.55, true)
	infall.emitting = true
	add_child(infall)
	# Dust pillars: the columns of cold gas a nebula is actually famous for,
	# standing in silhouette against the lit gas behind them with their rims
	# burning where the young star is eating into them.
	var pillar := _shaped("cn_pillar", 82, 164, _fn_dust_pillar)
	for e_v in [[0.16, 0.40, 1.0, 0.85], [0.30, 0.28, -1.0, 0.62],
			[0.84, 0.34, -1.0, 0.78], [0.95, 0.22, 1.0, 0.55]]:
		var e: Array = e_v
		var ph2: float = _vp.y * float(e[1])
		var pw2: float = ph2 * (130.0 / 260.0)
		var col2 := TextureRect.new()
		col2.texture = pillar
		col2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		col2.stretch_mode = TextureRect.STRETCH_SCALE
		col2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col2.size = Vector2(pw2, ph2)
		col2.pivot_offset = col2.size * 0.5
		col2.scale = Vector2(float(e[2]), 1.0)
		col2.position = Vector2(_vp.x * float(e[0]) - pw2 * 0.5, _vp.y * 1.01 - ph2)
		var tint2: Color = _pc("bg0").lerp(Color(0.32, 0.14, 0.30), 0.7)
		col2.modulate = Color(tint2.r, tint2.g, tint2.b, float(e[3]))
		add_child(col2)
		# The lit rim where the star is boiling the column away.
		var rim := TextureRect.new()
		rim.texture = pillar
		rim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rim.stretch_mode = TextureRect.STRETCH_SCALE
		rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rim.size = col2.size * 1.06
		rim.pivot_offset = rim.size * 0.5
		rim.scale = col2.scale
		rim.position = col2.position - (rim.size - col2.size) * 0.5
		rim.modulate = Color(1.0, 0.62, 0.42, 0.16)
		add_child(rim)
		move_child(rim, maxi(rim.get_index() - 1, 0))
	# The ignition, on a long cycle.
	var tw := core.create_tween().set_loops()
	tw.tween_interval(randf_range(6.0, 10.0))
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(core, "modulate:a", 1.0, 0.35)
	tw.tween_property(core, "scale", Vector2(1.9, 1.9), 0.35)
	tw.tween_property(halo, "modulate:a", 0.22, 0.35)
	tw.chain().set_parallel(true).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(core, "modulate:a", 0.35, 3.0)
	tw.tween_property(core, "scale", Vector2.ONE, 3.0)
	tw.tween_property(halo, "modulate:a", 0.05, 3.0)


# --- Landmarks, batch 2 --------------------------------------------------------
# Same idea as the first batch: a drifting field is weather, a landmark is a
# PLACE. All of these stand on the ground line of the bottom band — the strip
# the opaque board never covers — so they read without ever fighting the tiles.

## Stand a baked silhouette on the ground line. `aspect` is the bake's w/h, so
## the caller sizes by height and never has to restate the proportion.
##
## Two things happen here that are the difference between a cut-out and an
## object standing in a place:
##
##  * A CONTACT SHADOW. Nothing in the real world meets the ground on a hard
##    line; the darkening under a thing is most of what says it is resting on
##    something rather than pasted over it.
##  * An ATMOSPHERIC TWIN, optionally, set back and to the side: a paler, larger,
##    lower-contrast copy of the same silhouette. Distance desaturates and
##    lightens, so a second copy shifted toward the sky colour reads instantly as
##    "further away" and gives the band depth no single layer can.
##
## `haze` is how strongly the twin is mixed toward `sky` (0 = no twin at all).
func _landmark(tex: Texture2D, x_frac: float, height_frac: float, aspect: float,
		tint: Color, alpha: float = 1.0, base_frac: float = 1.005,
		haze: float = 0.0, sky: Color = Color(0, 0, 0, 0)) -> TextureRect:
	var h: float = _vp.y * height_frac
	var w: float = h * aspect
	var ground: float = _vp.y * base_frac
	# The far twin goes down first, so the near copy layers over it.
	if haze > 0.0:
		var far := TextureRect.new()
		far.texture = tex
		far.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		far.stretch_mode = TextureRect.STRETCH_SCALE
		far.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fh: float = h * 0.72
		var fw: float = fh * aspect
		far.size = Vector2(fw, fh)
		far.position = Vector2(_vp.x * x_frac - fw * 0.5 - w * 0.42, ground - fh - h * 0.02)
		var far_col: Color = tint if sky.a <= 0.0 else tint.lerp(sky, clampf(haze, 0.0, 1.0))
		far.modulate = Color(far_col.r, far_col.g, far_col.b, alpha * 0.55)
		add_child(far)
	# The contact shadow: an ellipse pooled under the footprint, widest and
	# darkest right at the base and gone within a fraction of the height.
	var shadow := TextureRect.new()
	shadow.texture = _round()
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.stretch_mode = TextureRect.STRETCH_SCALE
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.size = Vector2(w * 1.35, h * 0.16)
	shadow.position = Vector2(_vp.x * x_frac - shadow.size.x * 0.5,
		ground - shadow.size.y * 0.55)
	shadow.modulate = Color(0, 0, 0, 0.22 * alpha)
	add_child(shadow)
	var n := TextureRect.new()
	n.texture = tex
	n.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	n.stretch_mode = TextureRect.STRETCH_SCALE
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.size = Vector2(w, h)
	n.pivot_offset = Vector2(w * 0.5, h)
	n.position = Vector2(_vp.x * x_frac - w * 0.5, ground - h)
	n.modulate = Color(tint.r, tint.g, tint.b, alpha)
	add_child(n)
	return n

## Autumn — the tree the leaves are coming off, leaning in from one side, with a
## drift of fallen leaves banked under it. The canopy sways on the same wind
## that is stripping it.
func _autumn_tree() -> void:
	var bark := _pc("bg0").lerp(Color(0.18, 0.10, 0.06), 0.8)
	var tree := _landmark(_shaped("autumn_tree", 124, 150, _fn_autumn_tree),
		0.11, 0.25, 200.0 / 240.0, bark, 0.96)
	tree.pivot_offset = Vector2(tree.size.x * 0.5, tree.size.y)
	var sway := tree.create_tween().set_loops()
	sway.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	sway.tween_property(tree, "rotation", 0.012, randf_range(3.5, 5.0))
	sway.tween_property(tree, "rotation", -0.012, randf_range(3.5, 5.0))
	# The canopy, in leaf colour, over the bare branches.
	# The shaded mass of the crown, behind and slightly below the lit one.
	_landmark(_shaped("autumn_canopy", 130, 112, _fn_autumn_canopy),
		0.09, 0.175, 210.0 / 180.0, Color(0.44, 0.14, 0.05), 0.9, 0.845)
	var canopy := _landmark(_shaped("autumn_canopy", 130, 112, _fn_autumn_canopy),
		0.125, 0.165, 210.0 / 180.0, Color(0.92, 0.46, 0.13), 0.95, 0.865)
	var cs := canopy.create_tween().set_loops()
	cs.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	cs.tween_property(canopy, "rotation", 0.02, randf_range(3.0, 4.4))
	cs.tween_property(canopy, "rotation", -0.02, randf_range(3.0, 4.4))
	# The drift of fallen leaves banked along the ground.
	for i in 4:
		var pile := TextureRect.new()
		pile.texture = _round()
		pile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pile.stretch_mode = TextureRect.STRETCH_SCALE
		pile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.30, 0.55)
		pile.size = Vector2(w, _vp.y * randf_range(0.05, 0.09))
		pile.position = Vector2(_vp.x * (0.05 + 0.30 * float(i)) - w * 0.5,
			_vp.y * 0.985 - pile.size.y * 0.5)
		var c := Color(0.72, 0.32, 0.10).lerp(Color(0.92, 0.62, 0.18), randf())
		pile.modulate = Color(c.r, c.g, c.b, 0.5)
		add_child(pile)

## Blood Moon — the ridge the moon rises behind: a black skyline with a bell
## tower on it, and a wolf that lifts its head to howl every so often.
func _bloodmoon_ridge() -> void:
	var dark := Color(0.05, 0.02, 0.03)
	# A far range behind the near ridge, washed toward the red sky — the oldest
	# trick there is for making a horizon feel deep.
	_landmark(_shaped("bm_ridge", 188, 56, _fn_ridge), 0.62, 0.15, 300.0 / 90.0,
		dark.lerp(Color(0.42, 0.10, 0.10), 0.75), 0.85, 0.86)
	_landmark(_shaped("bm_ridge", 188, 56, _fn_ridge), 0.5, 0.20, 300.0 / 90.0,
		dark, 0.97, 0.99)
	# The bell tower, with one lit window.
	_landmark(_shaped("bm_tower", 56, 138, _fn_bell_tower), 0.82, 0.21, 90.0 / 220.0,
		dark, 0.98, 0.96)
	var win := TextureRect.new()
	win.texture = _dot()
	win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d: float = _vp.x * 0.028
	win.size = Vector2(d, d * 1.3)
	win.position = Vector2(_vp.x * 0.80 - win.size.x * 0.5, _vp.y * 0.79)
	win.modulate = Color(1.0, 0.62, 0.24, 0.7)
	add_child(win)
	var wt := win.create_tween().set_loops()
	wt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	wt.tween_property(win, "modulate:a", 0.9, randf_range(1.4, 2.4))
	wt.tween_property(win, "modulate:a", 0.42, randf_range(1.4, 2.4))
	# The wolf on the ridge. It sits, then throws its head back and holds it.
	# A dead tree on the ridge, and ravens crossing the moon. Both read at a
	# glance from outline alone, which a seated animal at this size does not —
	# two passes at the wolf both came out as an unreadable dark lump.
	_landmark(_shaped("bm_deadtree", 78, 100, _fn_dead_tree), 0.22, 0.20,
		170.0 / 220.0, Color(0.02, 0.01, 0.015), 1.0, 0.855)
	_landmark(_shaped("bm_deadtree", 104, 134, _fn_dead_tree), 0.36, 0.115,
		170.0 / 220.0, Color(0.03, 0.015, 0.02), 0.9, 0.845)
	_raven_flock(_gen)

## Vaporwave — the mall at the end of the world: a classical bust on a plinth,
## two palms, and the grid running away behind them.
func _vapor_plaza() -> void:
	var pink: Color = _pc("accent")
	# Palms, well out at the sides so the grid keeps the middle.
	for e_v in [[0.09, 0.215, -7.0], [0.92, 0.185, 8.0]]:
		var e: Array = e_v
		var palm := _landmark(_shaped("vw_palm", 92, 148, _fn_palm),
			float(e[0]), float(e[1]), 150.0 / 240.0,
			Color(0.42, 0.12, 0.52), 0.98)
		palm.rotation = deg_to_rad(float(e[2]))
		var sw := palm.create_tween().set_loops()
		sw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		sw.tween_property(palm, "rotation", palm.rotation + 0.02, randf_range(4.0, 6.0))
		sw.tween_property(palm, "rotation", palm.rotation - 0.02, randf_range(4.0, 6.0))
	# Broken columns at the edges instead of a bust in the middle. The centre of
	# this composition belongs to the sun and the grid's vanishing point; putting
	# a figure there blocked the only two things the aesthetic is made of.
	for e_v in [[0.19, 0.20, 0.0], [0.82, 0.15, 1.0]]:
		var e: Array = e_v
		var col := _landmark(_shaped("vw_column", 72, 176, _fn_column),
			float(e[0]), float(e[1]), 90.0 / 220.0,
			Color(1, 1, 1), 0.92)
		var ct := col.create_tween().set_loops()
		ct.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		ct.tween_property(col, "modulate:a", 0.92, randf_range(3.0, 4.2))
		ct.tween_property(col, "modulate:a", 0.58, randf_range(3.2, 4.6))
	# A chequer floor stripe at the very bottom, under the grid.
	var floor_band := _srect(0.0, 0.0, _vp.x * 1.02, _vp.y * 0.02,
		Color(pink.r, pink.g, pink.b, 0.28))
	floor_band.position = Vector2(-_vp.x * 0.01, _vp.y * 0.975)


func _zen_teahouse() -> void:
	var wood := Color(0.24, 0.17, 0.12)
	_landmark(_shaped("zen_house", 138, 94, _fn_teahouse), 0.80, 0.19,
		220.0 / 150.0, wood, 0.92, 0.80)
	# Its paper windows, warm from inside.
	for xf_v in [0.755, 0.845]:
		var xf: float = xf_v
		var w := TextureRect.new()
		w.texture = _dot()
		w.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = _vp.x * 0.05
		w.size = Vector2(d, d * 0.8)
		w.position = Vector2(_vp.x * xf - d * 0.5, _vp.y * 0.735)
		w.modulate = Color(1.0, 0.82, 0.48, 0.55)
		add_child(w)
	# The shishi-odoshi: a bamboo pipe on a pivot beside the pond.
	var pivot := Control.new()
	pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot.position = Vector2(_vp.x * 0.30, _vp.y * 0.918)
	# The stand it pivots on, and the basin it knocks against — without these
	# the pipe is an object lying in mid-air, which is what read as a telescope.
	var postw := maxf(_vp.x * 0.008, 2.0)
	var post := _srect(0.0, 0.0, postw, _vp.y * 0.055, Color(0.42, 0.36, 0.20, 0.9))
	post.position = Vector2(_vp.x * 0.30 - postw * 0.5, _vp.y * 0.918)
	var basin := TextureRect.new()
	basin.texture = _round()
	basin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	basin.stretch_mode = TextureRect.STRETCH_SCALE
	basin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	basin.size = Vector2(_vp.x * 0.10, _vp.y * 0.026)
	basin.position = Vector2(_vp.x * 0.30 - basin.size.x * 0.5, _vp.y * 0.962)
	basin.modulate = Color(0.44, 0.46, 0.44, 0.85)
	add_child(basin)
	add_child(pivot)
	var pipe := TextureRect.new()
	pipe.texture = _shaped("zen_pipe", 150, 40, _fn_bamboo_pipe)
	pipe.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pipe.stretch_mode = TextureRect.STRETCH_SCALE
	pipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pw: float = _vp.x * 0.115
	pipe.size = Vector2(pw, pw * (40.0 / 150.0))
	pipe.pivot_offset = Vector2(pw * 0.42, pipe.size.y * 0.5)
	pipe.position = Vector2(-pw * 0.42, -pipe.size.y * 0.5)
	pipe.modulate = Color(0.52, 0.46, 0.26, 0.95)
	pivot.add_child(pipe)
	# Fill slowly, tip fast, knock, swing back. The whole cycle is the joke.
	var cyc := pipe.create_tween().set_loops()
	cyc.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	cyc.tween_property(pipe, "rotation", 0.16, randf_range(4.5, 7.0))
	cyc.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	cyc.tween_property(pipe, "rotation", 0.62, 0.35)
	cyc.tween_callback(func() -> void:
		# The knock: a splash where the pipe strikes the stone.
		if is_inside_tree():
			_zen_ring(Vector2(_vp.x * 0.30, _vp.y * 0.915), 0.8))
	cyc.tween_interval(0.25)
	cyc.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	cyc.tween_property(pipe, "rotation", -0.10, 0.5)
	cyc.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	cyc.tween_property(pipe, "rotation", 0.0, 0.6)


# --- Landmarks, batch 3 --------------------------------------------------------

## Anime — a school rooftop at dusk: the safety railing you are standing behind,
## a distant torii on the hill, and the huge low sun the whole genre is lit by.
func _anime_rooftop() -> void:
	# Anime is a LIGHT theme, so a pale sun on a pale sky disappeared entirely.
	# The fix is a real graded SKY laid over the background: deep violet at the
	# top falling to burnt orange at the horizon. Everything else is read against
	# that gradient, which is what gives the shot its depth.
	var sky := TextureRect.new()
	sky.texture = _sky_ramp([Color(0.28, 0.24, 0.52), Color(0.62, 0.40, 0.62),
		Color(0.96, 0.56, 0.42), Color(1.0, 0.76, 0.46)])
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.size = Vector2(_vp.x, _vp.y * 0.90)
	sky.position = Vector2.ZERO
	sky.modulate = Color(1, 1, 1, 0.82)
	add_child(sky)
	# The sun: a defined disc low on the horizon, with a tight corona. A soft
	# blob reads as a smudge on a bright sky; a disc reads as the sun.
	var sun_c := Vector2(_vp.x * 0.62, _vp.y * 0.775)
	var corona := TextureRect.new()
	corona.texture = _dot()
	corona.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	corona.stretch_mode = TextureRect.STRETCH_SCALE
	corona.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cd: float = _vp.x * 1.15
	corona.size = Vector2(cd, cd * 0.8)
	corona.position = sun_c - corona.size * 0.5
	corona.modulate = Color(1.0, 0.72, 0.36, 0.34)
	add_child(corona)
	var ct := corona.create_tween().set_loops()
	ct.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	ct.tween_property(corona, "modulate:a", 0.48, 4.6)
	ct.tween_property(corona, "modulate:a", 0.26, 5.2)
	var disc := TextureRect.new()
	disc.texture = _shaped("anime_sun", 96, 96, _fn_sun_disc)
	disc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	disc.stretch_mode = TextureRect.STRETCH_SCALE
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sd: float = _vp.x * 0.34
	disc.size = Vector2(sd, sd)
	disc.position = sun_c - disc.size * 0.5
	disc.modulate = Color(1, 1, 1, 0.96)
	add_child(disc)
	# Cloud bands lit from beneath, crossing the sun.
	for i in 5:
		var band := TextureRect.new()
		band.texture = _round()
		band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		band.stretch_mode = TextureRect.STRETCH_SCALE
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.55, 1.15)
		band.size = Vector2(w, _vp.y * randf_range(0.018, 0.038))
		band.position = Vector2(_vp.x * randf_range(-0.1, 0.6),
			_vp.y * (0.60 + 0.055 * float(i)) + randf_range(-6.0, 6.0))
		var warm_band := Color(1.0, 0.62, 0.46).lerp(Color(0.62, 0.34, 0.52), float(i) / 5.0)
		band.modulate = Color(warm_band.r, warm_band.g, warm_band.b, randf_range(0.30, 0.55))
		add_child(band)
		var bt := band.create_tween().set_loops()
		bt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		bt.tween_property(band, "position:x", band.position.x + _vp.x * 0.05, randf_range(14.0, 22.0))
		bt.tween_property(band, "position:x", band.position.x, randf_range(14.0, 22.0))
	# Three hill ranges, each one a step darker and a step further forward — the
	# oldest way there is to build distance out of flat shapes.
	var hill := _shaped("anime_hill", 180, 54, _fn_ridge)
	_landmark(hill, 0.30, 0.115, 300.0 / 90.0, Color(0.72, 0.52, 0.62), 0.85, 0.836)
	_landmark(hill, 0.66, 0.145, 300.0 / 90.0, Color(0.46, 0.30, 0.46), 0.92, 0.862)
	_landmark(hill, 0.20, 0.170, 300.0 / 90.0, Color(0.24, 0.15, 0.30), 0.96, 0.888)
	# The torii on the far hill, and blossom trees on the near one.
	_landmark(_shaped("anime_torii", 84, 72, _fn_torii), 0.845, 0.070,
		130.0 / 110.0, Color(0.52, 0.12, 0.14), 0.95, 0.864)
	for e_v in [[0.10, 0.070], [0.35, 0.055], [0.52, 0.062]]:
		var e: Array = e_v
		_landmark(_shaped("anime_blossom", 88, 82, _fn_blossom_tree),
			float(e[0]), float(e[1]), 140.0 / 130.0,
			Color(1.0, 0.72, 0.82), 0.85, 0.889)
	# The rooftop deck you are standing on. Without it the pale theme background
	# showed under the sky texture as a bright strip along the bottom.
	var deck := _srect(0.0, 0.0, _vp.x * 1.02, _vp.y * 0.18,
		Color(0.16, 0.11, 0.20, 1.0))
	deck.position = Vector2(-_vp.x * 0.01, _vp.y * 0.895)
	# The railing you are standing at — the darkest thing on screen, so the
	# whole sky reads as being beyond it.
	var rail_y: float = _vp.y * 0.918
	var dark := Color(0.10, 0.06, 0.14)
	for i in 12:
		var post := _srect(0.0, 0.0, maxf(_vp.x * 0.013, 2.0), _vp.y * 0.082, dark)
		post.position = Vector2(_vp.x * (float(i) - 0.5) / 11.0 - post.size.x * 0.5, rail_y)
	for yf_v in [0.0, 0.034]:
		var yf: float = yf_v
		var bar := _srect(0.0, 0.0, _vp.x * 1.02, maxf(_vp.y * 0.008, 2.0), dark)
		bar.position = Vector2(-_vp.x * 0.01, rail_y + _vp.y * yf)
	var wall := _srect(0.0, 0.0, _vp.x * 1.02, _vp.y * 0.045, dark)
	wall.position = Vector2(-_vp.x * 0.01, _vp.y * 0.972)

## A vertical sky gradient as a texture — the cheapest way to put a real dusk
## behind everything. Colours run top to bottom.
func _sky_ramp(cols: Array) -> GradientTexture2D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cs := PackedColorArray()
	var n := cols.size()
	for i in n:
		offs.append(float(i) / float(maxi(n - 1, 1)))
		cs.append(cols[i])
	g.offsets = offs
	g.colors = cs
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_LINEAR
	t.fill_from = Vector2(0.0, 0.0)
	t.fill_to = Vector2(0.0, 1.0)
	t.width = 8
	t.height = 256
	return t

## Firefly Night — the pond the fireflies are working over: still water holding
## the moon, a bank of reeds, and a jar of caught fireflies on the grass.
func _firefly_pond() -> void:
	var water_y: float = _vp.y * 0.855
	var water := ColorRect.new()
	water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	water.color = Color(0.03, 0.06, 0.07, 0.72)
	water.size = Vector2(_vp.x, _vp.y - water_y)
	water.position = Vector2(0.0, water_y)
	add_child(water)
	# The moon's road on the water, and a few broken glints along it.
	var road := TextureRect.new()
	road.texture = _round()
	road.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	road.stretch_mode = TextureRect.STRETCH_SCALE
	road.mouse_filter = Control.MOUSE_FILTER_IGNORE
	road.size = Vector2(_vp.x * 0.30, (_vp.y - water_y) * 1.6)
	road.position = Vector2(_vp.x * 0.66 - road.size.x * 0.5, water_y - road.size.y * 0.12)
	road.modulate = Color(0.86, 0.92, 0.80, 0.09)
	add_child(road)
	var rt := road.create_tween().set_loops()
	rt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	rt.tween_property(road, "modulate:a", 0.17, 4.0)
	rt.tween_property(road, "modulate:a", 0.07, 4.6)
	# Reeds along the near bank, in front of the water.
	var reed := _shaped("ff_reed", 38, 126, _fn_reed)
	for e_v in [[0.05, 0.20, -6.0], [0.14, 0.15, 5.0], [0.90, 0.18, 7.0],
			[0.97, 0.13, -4.0], [0.42, 0.11, 3.0]]:
		var e: Array = e_v
		var r := _landmark(reed, float(e[0]), float(e[1]), 60.0 / 200.0,
			Color(0.06, 0.16, 0.10), 0.92)
		r.rotation = deg_to_rad(float(e[2]))
		var sw := r.create_tween().set_loops()
		sw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		sw.tween_property(r, "rotation", r.rotation + 0.035, randf_range(3.0, 4.6))
		sw.tween_property(r, "rotation", r.rotation - 0.035, randf_range(3.0, 4.6))
	# The jar, sitting in the grass with three fireflies shut inside it.
	var jar := _landmark(_shaped("ff_jar", 70, 94, _fn_jar), 0.24, 0.115,
		110.0 / 150.0, Color(0.78, 0.90, 0.82), 0.55)
	var jx: float = _vp.x * 0.24
	var jy: float = _vp.y * 0.945
	for i in 3:
		var f := TextureRect.new()
		f.texture = _dot()
		f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = jar.size.x * 0.16
		f.size = Vector2(d, d)
		f.position = Vector2(jx + jar.size.x * randf_range(-0.22, 0.22) - d * 0.5,
			jy - jar.size.y * randf_range(0.25, 0.62))
		f.modulate = Color(1.0, 0.92, 0.48, 0.0)
		add_child(f)
		var tw := f.create_tween().set_loops()
		tw.tween_interval(randf_range(0.0, 2.2))
		tw.tween_property(f, "modulate:a", 0.95, 0.5)
		tw.tween_property(f, "modulate:a", 0.05, 0.9)
		tw.tween_interval(randf_range(0.4, 1.6))
	# The jar's own glow on the grass around it.
	var pool := TextureRect.new()
	pool.texture = _dot()
	pool.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pool.stretch_mode = TextureRect.STRETCH_SCALE
	pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pool.size = Vector2(jar.size.x * 3.0, jar.size.y * 1.4)
	pool.position = Vector2(jx - pool.size.x * 0.5, jy - pool.size.y * 0.55)
	pool.modulate = Color(1.0, 0.88, 0.42, 0.10)
	add_child(pool)

## Lantern Festival — the river the lanterns are launched onto, the bridge over
## it, and the crowd lining the far bank.
func _lantern_river() -> void:
	var water_y: float = _vp.y * 0.865
	var water := ColorRect.new()
	water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	water.color = Color(0.05, 0.03, 0.06, 0.66)
	water.size = Vector2(_vp.x, _vp.y - water_y)
	water.position = Vector2(0.0, water_y)
	add_child(water)
	# Reflections: warm smears under the lantern field.
	for i in 7:
		var r := TextureRect.new()
		r.texture = _dot()
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.02, 0.05)
		r.size = Vector2(w, (_vp.y - water_y) * randf_range(0.5, 1.1))
		r.position = Vector2(_vp.x * (float(i) + 0.5) / 7.0 - w * 0.5, water_y)
		r.modulate = Color(1.0, 0.66, 0.24, randf_range(0.10, 0.26))
		add_child(r)
		var tw := r.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(r, "size:y", r.size.y * 1.3, randf_range(1.6, 2.8))
		tw.tween_property(r, "size:y", r.size.y, randf_range(1.6, 2.8))
	# The far bank, and the crowd standing on it — a row of small dark figures.
	var bank := _srect(0.0, 0.0, _vp.x * 1.02, _vp.y * 0.03, Color(0.06, 0.04, 0.06, 0.95))
	bank.position = Vector2(-_vp.x * 0.01, water_y - _vp.y * 0.028)
	var person := _shaped("lf_person", 38, 82, _fn_person)
	for i in 13:
		var h: float = _vp.y * randf_range(0.042, 0.058)
		var w: float = h * (60.0 / 130.0)
		var fig := TextureRect.new()
		fig.texture = person
		fig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fig.stretch_mode = TextureRect.STRETCH_SCALE
		fig.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fig.size = Vector2(w, h)
		fig.position = Vector2(_vp.x * (float(i) + randf_range(0.15, 0.85)) / 13.0 - w * 0.5,
			water_y - _vp.y * 0.026 - h)
		fig.modulate = Color(0.05, 0.03, 0.05, 0.95)
		add_child(fig)
	# The bridge, arching across above the crowd.
	var bridge := TextureRect.new()
	bridge.texture = _shaped("lf_bridge", 212, 82, _fn_bridge)
	bridge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bridge.stretch_mode = TextureRect.STRETCH_SCALE
	bridge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bw: float = _vp.x * 1.06
	bridge.size = Vector2(bw, bw * (130.0 / 340.0))
	bridge.position = Vector2(-_vp.x * 0.03, water_y - _vp.y * 0.022 - bridge.size.y)
	bridge.modulate = Color(1, 1, 1, 0.96)
	add_child(bridge)
	# The warm wash the bridge lamps throw down onto their own parapet — the one
	# thing that stops an arch reading as a cut-out.
	var brglow := TextureRect.new()
	brglow.texture = _round()
	brglow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	brglow.stretch_mode = TextureRect.STRETCH_SCALE
	brglow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brglow.size = Vector2(_vp.x * 1.1, bridge.size.y * 1.5)
	brglow.position = Vector2(-_vp.x * 0.05, bridge.position.y - bridge.size.y * 0.25)
	brglow.modulate = Color(1.0, 0.68, 0.28, 0.16)
	add_child(brglow)
	# Lanterns already afloat, drifting down the river with their reflections.
	for i in 6:
		var lit := TextureRect.new()
		lit.texture = _lantern()
		lit.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lit.stretch_mode = TextureRect.STRETCH_SCALE
		lit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lw: float = _vp.x * randf_range(0.045, 0.080)
		lit.size = Vector2(lw, lw * 1.35)
		var lxp: float = _vp.x * randf_range(0.04, 0.96)
		var lyp: float = water_y + (_vp.y - water_y) * randf_range(0.10, 0.62)
		lit.position = Vector2(lxp - lw * 0.5, lyp - lit.size.y * 0.75)
		lit.modulate = Color(1.0, 0.74, 0.34, 0.95)
		add_child(lit)
		var pool := TextureRect.new()
		pool.texture = _dot()
		pool.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pool.stretch_mode = TextureRect.STRETCH_SCALE
		pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pool.size = Vector2(lw * 3.0, lw * 1.5)
		pool.position = Vector2(lxp - pool.size.x * 0.5, lyp - pool.size.y * 0.4)
		pool.modulate = Color(1.0, 0.62, 0.22, 0.24)
		add_child(pool)
		# They drift downstream and turn slowly as they go.
		var dt := lit.create_tween().set_loops()
		dt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		var dx := randf_range(-1.0, 1.0) * _vp.x * 0.05
		dt.tween_property(lit, "position:x", lit.position.x + dx, randf_range(8.0, 13.0))
		dt.tween_property(lit, "position:x", lit.position.x, randf_range(8.0, 13.0))
	# Lamps strung along the bridge's rail.
	for i in 9:
		var lamp := TextureRect.new()
		lamp.texture = _dot()
		lamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = _vp.x * 0.026
		lamp.size = Vector2(d, d)
		var f := (float(i) + 0.5) / 9.0
		# Follow the bridge's arch.
		var arch: float = sin(f * PI) * bridge.size.y * 0.42
		lamp.position = Vector2(_vp.x * f - d * 0.5,
			bridge.position.y + bridge.size.y * 0.55 - arch - d * 0.5)
		lamp.modulate = Color(1.0, 0.72, 0.30, 0.75)
		add_child(lamp)
		var tw := lamp.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(lamp, "modulate:a", 0.95, randf_range(1.2, 2.2))
		tw.tween_property(lamp, "modulate:a", 0.5, randf_range(1.2, 2.2))

## Neon City — the ramen stall under the overpass: a lit awning, a counter, two
## customers on stools, and steam pouring up out of it into the rain.
func _ramen_stall() -> void:
	var warm := Color(1.0, 0.66, 0.28)
	var sx: float = _vp.x * 0.30
	var base: float = _vp.y * 0.985
	# The light it throws onto the wet street, laid down first.
	var spill := TextureRect.new()
	spill.texture = _dot()
	spill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spill.stretch_mode = TextureRect.STRETCH_SCALE
	spill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spill.size = Vector2(_vp.x * 0.72, _vp.y * 0.22)
	spill.position = Vector2(sx - spill.size.x * 0.5, base - spill.size.y * 0.75)
	spill.modulate = Color(warm.r, warm.g, warm.b, 0.20)
	add_child(spill)
	var stall := _landmark(_shaped("nc_stall", 138, 100, _fn_ramen_stall), 0.30, 0.185,
		220.0 / 160.0, Color(0.94, 0.72, 0.40), 0.95)
	# Two customers at the counter, in silhouette against the stall's light.
	var person := _shaped("nc_person", 38, 82, _fn_person)
	for xf_v in [0.235, 0.355]:
		var xf: float = xf_v
		var h: float = _vp.y * 0.085
		var w: float = h * (60.0 / 130.0)
		var fig := TextureRect.new()
		fig.texture = person
		fig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fig.stretch_mode = TextureRect.STRETCH_SCALE
		fig.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fig.size = Vector2(w, h)
		fig.position = Vector2(_vp.x * xf - w * 0.5, base - h * 0.86)
		fig.modulate = Color(0.05, 0.03, 0.06, 0.95)
		add_child(fig)
	# Steam, rolling up off the pots and catching the neon.
	var steam := CPUParticles2D.new()
	steam.position = Vector2(sx, base - stall.size.y * 0.62)
	steam.amount = maxi(int(16.0 * _particle_scale()), 5)
	steam.lifetime = 3.6
	steam.preprocess = 1.6
	steam.texture = _round()
	steam.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	steam.emission_rect_extents = Vector2(stall.size.x * 0.28, 4.0)
	steam.direction = Vector2(0.12, -1)
	steam.spread = 18.0
	steam.initial_velocity_min = 26.0
	steam.initial_velocity_max = 66.0
	steam.scale_amount_min = 0.6
	steam.scale_amount_max = 2.2
	steam.color_ramp = _alpha_ramp(Color(1.0, 0.86, 0.72), 0.16, false)
	steam.emitting = true
	add_child(steam)

## Butterfly Grove — the flowers they are working, and the shaft of sun that
## comes down through the canopy onto them.
## The bed the grove is standing in — a NIGHT garden.
##
## The first pass planted a daylight border: a warm yellow sunbeam, a grass bank
## and nine saturated pink-and-gold blooms, dropped into a midnight-blue clearing
## lit by a cold moon. Warm saturated flowers under a cold light is the one
## combination that always reads as stickers, and that is exactly how they read.
##
## So the whole bed is relit. The flowers are moonflower white, silver-lavender
## and ice-blue campanula (`_fn_flower_kind` carries the night palette now); each
## head sits in its own soft bloom of moonlight, because a white flower at night
## is the brightest thing in the frame and does not have a hard edge; a stand of
## grass and two ferns go in FRONT of them in near-silhouette so the bed has a
## depth rather than a single row; and the light that falls on it is the moon's,
## not a sun's.
func _grove_flowers() -> void:
	var moonlight: Color = _pc("accent").lerp(_white(1.0), 0.62)
	# The bank they are planted in: cool, blue-black, layered so the ground line
	# is broken instead of ruled.
	for i in 6:
		var bank := TextureRect.new()
		bank.texture = _round()
		bank.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bank.stretch_mode = TextureRect.STRETCH_SCALE
		bank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bw2: float = _vp.x * randf_range(0.36, 0.68)
		bank.size = Vector2(bw2, _vp.y * randf_range(0.055, 0.105))
		bank.position = Vector2(_vp.x * (0.02 + 0.20 * float(i)) - bw2 * 0.5,
			_vp.y * randf_range(0.975, 1.0) - bank.size.y * 0.5)
		bank.modulate = Color(0.07, 0.15, 0.18, 0.62)
		add_child(bank)
	# The bed: three species at three depths. A bed of one flower repeated is
	# wallpaper; mixing the FORMS is what makes it read as planted.
	var blooms: Array = [
		_shaped("bg_cosmos", 68, 150, _fn_flower_cosmos),
		_shaped("bg_ranunculus", 68, 150, _fn_flower_ranunculus),
		_shaped("bg_bell", 68, 150, _fn_flower_bell),
	]
	# Night tints — silver, ice, lavender, the palest teal. Nothing saturated,
	# and nothing warm: the only warmth in the bed is the moonflower's throat,
	# which the bake carries.
	var cols: Array = [Color(0.96, 0.98, 1.00), Color(0.80, 0.86, 1.00),
		Color(0.86, 0.82, 1.00), Color(0.78, 0.94, 0.98), Color(1.00, 0.96, 0.92)]
	# Every head is placed INSIDE the frame. `_landmark` centres a bloom on its
	# x-fraction, so an even spread over 0..1 puts the first and last flower
	# half off the screen — which is exactly how they were being cut in half.
	# The rows lay out across the inset span instead.
	const EDGE := 0.10
	# A back row, small and sunk into the dark, before the front row goes in.
	for i in 8:
		var bh: float = _vp.y * randf_range(0.070, 0.110)
		var back_tint: Color = cols[(i * 3) % cols.size()].lerp(_pc("bg0"), 0.52)
		_landmark(blooms[i % 3],
			lerpf(EDGE, 1.0 - EDGE, (float(i) + randf_range(0.15, 0.85)) / 8.0),
			bh / _vp.y, 100.0 / 220.0, back_tint, 0.55, 0.972)
	for i in 9:
		var h: float = _vp.y * randf_range(0.13, 0.23)
		var xf: float = lerpf(EDGE, 1.0 - EDGE, (float(i) + randf_range(0.15, 0.85)) / 9.0)
		var petal_tint: Color = cols[i % cols.size()]
		var f := _landmark(blooms[(i * 2 + 1) % 3], xf, h / _vp.y,
			100.0 / 220.0, petal_tint, randf_range(0.88, 1.0))
		# The moonlight the head is holding. A white flower at night has no
		# hard edge — it is the brightest thing in the frame and it bleeds.
		var glow := TextureRect.new()
		glow.texture = _round()
		glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glow.stretch_mode = TextureRect.STRETCH_SCALE
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gd: float = h * 0.62
		glow.size = Vector2(gd, gd)
		glow.position = Vector2(_vp.x * xf, _vp.y * 1.005 - h * 0.86) - glow.size * 0.5
		var ga: float = randf_range(0.10, 0.20)
		glow.modulate = Color(petal_tint.r, petal_tint.g, petal_tint.b, ga)
		add_child(glow)
		move_child(glow, maxi(f.get_index() - 1, 0))
		var gt := glow.create_tween().set_loops()
		gt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		gt.tween_interval(randf_range(0.0, 2.5))
		gt.tween_property(glow, "modulate:a", ga * 1.7, randf_range(2.8, 4.4))
		gt.tween_property(glow, "modulate:a", ga * 0.6, randf_range(3.0, 4.8))
		# Where a butterfly can land (see `_fairy_settle`). The head sits a
		# little under the top of the plant, which is where `_landmark` puts it.
		_grove_perches.append(Vector2(_vp.x * xf, _vp.y * 1.005 - h * 0.84))
		var sw := f.create_tween().set_loops()
		sw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		var amp := randf_range(0.03, 0.07)
		sw.tween_interval(randf_range(0.0, 1.5))
		sw.tween_property(f, "rotation", amp, randf_range(2.6, 4.2))
		sw.tween_property(f, "rotation", -amp, randf_range(2.6, 4.2))
	# In FRONT of the bed: grass and ferns in near-silhouette, so the border has
	# a near edge as well as a far one and the flowers stand INSIDE it.
	var tuft := _shaped("bg_tuft", 46, 74, _fn_grass_tuft)
	var fern := _shaped("bg_fern", 60, 96, _fn_fern_frond)
	for i in 11:
		var gh: float = _vp.y * randf_range(0.05, 0.12)
		var g2 := _landmark(tuft, lerpf(0.02, 0.98, (float(i) + randf_range(0.0, 1.0)) / 11.0),
			gh / _vp.y, 90.0 / 150.0, Color(0.05, 0.13, 0.16),
			randf_range(0.75, 0.95), 1.02)
		var gsw := g2.create_tween().set_loops()
		gsw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		var gamp := randf_range(0.02, 0.06)
		gsw.tween_interval(randf_range(0.0, 2.0))
		gsw.tween_property(g2, "rotation", gamp, randf_range(2.2, 3.8))
		gsw.tween_property(g2, "rotation", -gamp, randf_range(2.4, 4.0))
	for e_v in [[0.11, 0.17, -0.22], [0.88, 0.15, 0.20], [0.46, 0.11, 0.10]]:
		var e: Array = e_v
		var fr := _landmark(fern, float(e[0]), float(e[1]), 110.0 / 175.0,
			Color(0.04, 0.11, 0.14), 0.92, 1.03)
		fr.rotation = float(e[2])
	# Fireflies, low, among the stems — the only thing in the bed that moves on
	# its own, and the reason the border reads as alive rather than painted.
	_emit({"from": "bottom", "tex": _dot(),
		"iramp": _ramp_cols([Color(0.80, 1.00, 0.78), Color(1.00, 0.96, 0.72),
			Color(0.72, 0.92, 1.00)]),
		"alpha": 0.75, "amount": 14, "lifetime": 7.0, "dir": Vector3(0.2, -1, 0),
		"spread": 60.0, "vmin": 6.0, "vmax": 22.0, "smin": 0.20, "smax": 0.48,
		"twinkle": true})

## First Bloom — the rest of the garden the bonsai sits in: a paper screen
## behind it and a mossed stone beside it.
func _bloom_garden() -> void:
	# The shoji screen, a soft lit panel behind everything.
	var screen := TextureRect.new()
	screen.texture = _shaped("fb_shoji", 240, 180, _fn_shoji)
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_SCALE
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sw_: float = _vp.x * 0.92
	screen.size = Vector2(sw_, sw_ * (180.0 / 240.0))
	screen.position = Vector2(_vp.x * 0.5 - sw_ * 0.5, _vp.y * 0.985 - screen.size.y)
	screen.modulate = Color(1, 1, 1, 0.55)
	add_child(screen)
	var gt := screen.create_tween().set_loops()
	gt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	gt.tween_property(screen, "modulate:a", 0.72, 5.5)
	gt.tween_property(screen, "modulate:a", 0.46, 6.0)
	# A mossed stone at the foot of the tree.
	_landmark(_shaped("fb_stone", 94, 56, _fn_stone), 0.80, 0.075, 150.0 / 90.0,
		Color(0.30, 0.34, 0.30), 0.92)
	_landmark(_shaped("fb_stone", 94, 56, _fn_stone), 0.90, 0.048, 150.0 / 90.0,
		Color(0.26, 0.30, 0.27), 0.85)

func _honey_threads(gen: int, from_y: float) -> void:
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(2.2, 5.5)).timeout
		if gen != _gen or not is_inside_tree():
			return
		var x: float = _vp.x * randf_range(0.08, 0.92)
		var thread := ColorRect.new()
		thread.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thread.color = Color(1.0, 0.78, 0.26, 0.75)
		thread.size = Vector2(maxf(_vp.x * 0.006, 1.5), 0.0)
		thread.position = Vector2(x - thread.size.x * 0.5, from_y)
		add_child(thread)
		var drop := TextureRect.new()
		drop.texture = _dot()
		drop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dd: float = _vp.x * 0.026
		drop.size = Vector2(dd, dd)
		drop.position = Vector2(x - dd * 0.5, from_y)
		drop.modulate = Color(1.0, 0.76, 0.22, 0.9)
		add_child(drop)
		# It stretches, necks, and lets go — honey is slow and then sudden.
		var reach: float = _vp.y * randf_range(0.10, 0.22)
		var tw := thread.create_tween()
		tw.set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(thread, "size:y", reach, 2.4)
		tw.tween_property(drop, "position:y", from_y + reach - dd * 0.5, 2.4)
		tw.chain().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUINT)
		tw.tween_property(drop, "position:y", _vp.y * 1.05, 1.1)
		tw.tween_property(thread, "size:y", 0.0, 0.5)
		tw.tween_property(thread, "modulate:a", 0.0, 0.6)
		tw.chain().tween_callback(thread.queue_free)
		tw.chain().tween_callback(drop.queue_free)

## Peacock — the bird itself, standing at the edge of the frame with its train
## raised, the fan opening and closing on a long slow clock.
## Ravens crossing the moon every so often — a loose skein, not a formation,
## with each bird beating on its own clock.
func _raven_flock(gen: int) -> void:
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(6.0, 13.0)).timeout
		if gen != _gen or not is_inside_tree():
			return
		var dir: float = 1.0 if randf() < 0.5 else -1.0
		var y0: float = _vp.y * randf_range(0.10, 0.34)
		var n := maxi(int(7.0 * _particle_scale()), 3)
		for i in n:
			var b := TextureRect.new()
			b.texture = _shaped("bm_raven", 56, 40, _fn_raven)
			b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			b.stretch_mode = TextureRect.STRETCH_SCALE
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var w: float = _vp.x * randf_range(0.035, 0.070)
			b.size = Vector2(w, w * 0.71)
			b.pivot_offset = b.size * 0.5
			var y: float = y0 + _vp.y * randf_range(-0.05, 0.05)
			b.position = Vector2(
				(-w * 2.0 if dir > 0.0 else _vp.x + w) - float(i) * w * dir * randf_range(1.2, 2.4), y)
			b.modulate = Color(0.03, 0.01, 0.02, 0.9)
			add_child(b)
			var dur := randf_range(5.0, 8.0)
			var tw := b.create_tween()
			tw.set_parallel(true)
			tw.tween_property(b, "position:x",
				(_vp.x + w * 3.0) if dir > 0.0 else -w * 3.0, dur)
			# The wingbeat: a vertical squash, which is all a bird at this size is.
			var beat := b.create_tween().set_loops()
			beat.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			beat.tween_property(b, "scale", Vector2(1.0, 0.55), randf_range(0.16, 0.26))
			beat.tween_property(b, "scale", Vector2(1.0, 1.0), randf_range(0.16, 0.26))
			tw.chain().tween_callback(b.queue_free)


# --- Landmarks, batch 4 --------------------------------------------------------
# The themes that were still nothing but weather: three kinds of rain, a
# blizzard, a storm, a petal fall, a fog and an ocean. Each gets the ground it
# is falling onto.

## Raining Gold — what the gold is falling INTO: a spilled hoard. A chest on its
## side with coin pouring out of it, drifts of coin banked either way, and a
## stack of ingots catching the light.
func _gold_hoard() -> void:
	var gold := Color(1.0, 0.80, 0.30)
	# The drifts, laid first so everything else sits in them.
	for i in 5:
		var drift := TextureRect.new()
		drift.texture = _round()
		drift.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drift.stretch_mode = TextureRect.STRETCH_SCALE
		drift.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.34, 0.66)
		drift.size = Vector2(w, _vp.y * randf_range(0.05, 0.10))
		drift.position = Vector2(_vp.x * (0.02 + 0.24 * float(i)) - w * 0.5,
			_vp.y * randf_range(0.955, 0.995) - drift.size.y * 0.5)
		drift.modulate = Color(gold.r * 0.85, gold.g * 0.68, gold.b * 0.24, 0.55)
		add_child(drift)
	# The chest, tipped over, with its lid open.
	_landmark(_shaped("gold_chest", 124, 88, _fn_chest), 0.24, 0.155,
		200.0 / 140.0, Color(1, 1, 1), 0.97)
	# The ingot stack.
	_landmark(_shaped("gold_ingots", 106, 76, _fn_ingot_stack), 0.78, 0.115,
		170.0 / 120.0, Color(1, 1, 1), 0.97)
	# Loose coin scattered over the drifts, each catching the light on its own.
	var coin := _coin()
	for i in 16:
		var c := TextureRect.new()
		c.texture = coin
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c.stretch_mode = TextureRect.STRETCH_SCALE
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = _vp.x * randf_range(0.028, 0.055)
		c.size = Vector2(d, d * randf_range(0.35, 1.0))     # foreshortened, lying flat
		c.position = Vector2(_vp.x * randf_range(0.02, 0.98) - d * 0.5,
			_vp.y * randf_range(0.930, 0.995))
		c.modulate = Color(gold.r, gold.g, gold.b, randf_range(0.7, 1.0))
		add_child(c)
		var tw := c.create_tween().set_loops()
		tw.tween_interval(randf_range(0.5, 5.0))
		tw.tween_property(c, "modulate:a", 1.0, 0.12)
		tw.tween_property(c, "modulate:a", 0.72, 0.6)
	# The whole hoard glows.
	_edge_glow(gold, 0.09, 0.20, false)

## Raining Silver — a moonlit vault instead of a warm hoard: bars stacked cold
## and square, a chalice on its side, and a much bluer light.
func _silver_vault() -> void:
	var silver := Color(0.86, 0.90, 0.98)
	for i in 4:
		var drift := TextureRect.new()
		drift.texture = _round()
		drift.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drift.stretch_mode = TextureRect.STRETCH_SCALE
		drift.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.34, 0.60)
		drift.size = Vector2(w, _vp.y * randf_range(0.04, 0.08))
		drift.position = Vector2(_vp.x * (0.05 + 0.30 * float(i)) - w * 0.5,
			_vp.y * randf_range(0.960, 0.995) - drift.size.y * 0.5)
		drift.modulate = Color(silver.r * 0.55, silver.g * 0.62, silver.b * 0.78, 0.45)
		add_child(drift)
	_landmark(_shaped("silver_ingots", 106, 76, _fn_ingot_stack), 0.22, 0.125,
		170.0 / 120.0, Color(0.90, 0.94, 1.0), 0.97)
	_landmark(_shaped("silver_ingots", 106, 76, _fn_ingot_stack), 0.74, 0.095,
		170.0 / 120.0, Color(0.78, 0.84, 0.94), 0.9)
	_landmark(_shaped("silver_chalice", 82, 106, _fn_chalice), 0.50, 0.155,
		130.0 / 170.0, Color(0.92, 0.95, 1.0), 0.96)
	_edge_glow(silver, 0.07, 0.16, false)

## Raining Diamond — a jeweller's tray: dark velvet with loose brilliants across
## it and a solitaire ring standing up, throwing hard little glints.
## Crystal Storm — the cave the blizzard is blowing through: ice columns growing
## up from the floor and down from the roof, with the light coming through them.
func _ice_cavern() -> void:
	var ice: Color = _pc("accent").lerp(Color(0.72, 0.94, 1.0), 0.6)
	var spike := _shaped("cs_icicle", 44, 132, _fn_icicle)
	# Stalagmites up from the floor.
	for e_v in [[0.04, 0.20, -6.0], [0.13, 0.13, 5.0], [0.30, 0.09, -3.0],
			[0.72, 0.11, 4.0], [0.87, 0.23, -7.0], [0.97, 0.15, 6.0]]:
		var e: Array = e_v
		var c := _landmark(spike, float(e[0]), float(e[1]), 70.0 / 210.0,
			ice, randf_range(0.55, 0.85))
		c.rotation = deg_to_rad(float(e[2]))
	# Icicles down from the roof — same shape, flipped.
	for e_v in [[0.10, 0.16], [0.26, 0.10], [0.44, 0.19], [0.60, 0.12],
			[0.80, 0.16], [0.93, 0.09]]:
		var e: Array = e_v
		var h: float = _vp.y * float(e[1])
		var w: float = h * (70.0 / 210.0)
		var ic := TextureRect.new()
		ic.texture = spike
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_SCALE
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.size = Vector2(w, h)
		ic.pivot_offset = ic.size * 0.5
		ic.scale = Vector2(1.0, -1.0)
		ic.position = Vector2(_vp.x * float(e[0]) - w * 0.5, -h * 0.02)
		ic.modulate = Color(ice.r, ice.g, ice.b, randf_range(0.5, 0.8))
		add_child(ic)
	_edge_glow(ice, 0.06, 0.15, true)
	_edge_glow(ice, 0.05, 0.12, false)

## Thunderstorm — the ground the rain is hitting: a black hill with one bent
## tree on it, and standing water that flares white when the sky does.
func _storm_ground() -> void:
	var dark := Color(0.04, 0.05, 0.08)
	_landmark(_shaped("st_ridge", 188, 56, _fn_ridge), 0.36, 0.115, 300.0 / 90.0,
		dark.lerp(Color(0.20, 0.26, 0.36), 0.55), 0.85, 0.90)
	_landmark(_shaped("st_ridge", 188, 56, _fn_ridge), 0.68, 0.155, 300.0 / 90.0,
		dark, 0.96, 0.945)
	# One tree, bent by the weather it has stood in.
	var tree := _landmark(_shaped("st_tree", 78, 100, _fn_dead_tree), 0.20, 0.22,
		170.0 / 220.0, dark, 0.97, 0.94)
	tree.rotation = deg_to_rad(7.0)
	var sway := tree.create_tween().set_loops()
	sway.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	sway.tween_property(tree, "rotation", deg_to_rad(10.5), randf_range(1.6, 2.4))
	sway.tween_property(tree, "rotation", deg_to_rad(5.0), randf_range(1.6, 2.4))
	# Standing water across the very bottom, holding the sky.
	var pool := ColorRect.new()
	pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pool.color = Color(0.06, 0.09, 0.14, 0.8)
	pool.size = Vector2(_vp.x, _vp.y * 0.06)
	pool.position = Vector2(0.0, _vp.y * 0.94)
	add_child(pool)
	# Its sheen, which brightens on the same clock the lightning runs on.
	for i in 4:
		var sheen := TextureRect.new()
		sheen.texture = _round()
		sheen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sheen.stretch_mode = TextureRect.STRETCH_SCALE
		sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.22, 0.44)
		sheen.size = Vector2(w, _vp.y * 0.05)
		sheen.position = Vector2(_vp.x * (0.05 + 0.28 * float(i)) - w * 0.5, _vp.y * 0.945)
		sheen.modulate = Color(0.70, 0.82, 1.0, 0.06)
		add_child(sheen)
		var tw := sheen.create_tween().set_loops()
		tw.tween_interval(randf_range(2.0, 6.0))
		tw.tween_property(sheen, "modulate:a", 0.34, 0.06)
		tw.tween_property(sheen, "modulate:a", 0.06, 0.5)

## Sakura Pink — the TREE the petals are coming off.
##
## The first pass hung a single baked "bough" across the top: one brown bar with
## rectangular twigs stuck through a pink polka-dot cloud. It read as clip art
## because a bough with no tree under it has no reason to be where it is, and
## because a 180x112 per-pixel bake cannot hold a branch structure — the twigs
## come out as rectangles at that resolution.
##
## So the wood is DRAWN, not baked: tapered polygon limbs off a real trunk that
## stands on the ground at the bottom of the frame and forks into four limbs
## reaching across the top — cheap (one canvas item, painted once) and sharp at
## any size. Only the blossom is baked, once, as a small cluster of five-petal
## florets that is then scattered along the outer half of every limb at a dozen
## sizes and tints, each drifting on its own clock. A second tree stands well
## back on the right, small and hazed toward the sky, so the grove has depth.
const _SK_WOOD := Color(0.34, 0.21, 0.25)     # wet cherry bark, warm not black

## Each tree is a list of limbs; a limb is [w0, w1, p0, p1, p2, p3] — two widths
## as a fraction of viewport WIDTH and four control points in viewport fractions
## that a cubic bezier is sampled through, so limbs bend instead of running
## straight. Trunk first, then the limbs it forks into.
const _SK_NEAR := [
	# the trunk, standing on the bottom edge and leaning into the frame
	[0.125, 0.032, Vector2(0.09, 1.06), Vector2(0.17, 0.86), Vector2(0.10, 0.66), Vector2(0.175, 0.47)],
	# back limb, low and short — reads as depth behind the trunk
	[0.024, 0.005, Vector2(0.15, 0.68), Vector2(0.06, 0.66), Vector2(-0.01, 0.62), Vector2(-0.08, 0.55)],
	# left limb, sweeping out and up past the frame edge
	[0.032, 0.006, Vector2(0.15, 0.60), Vector2(0.05, 0.52), Vector2(-0.02, 0.40), Vector2(-0.12, 0.26)],
	# right limb, the long one, reaching across the top of the board
	[0.030, 0.006, Vector2(0.165, 0.52), Vector2(0.33, 0.42), Vector2(0.50, 0.31), Vector2(0.66, 0.21)],
	# leader, straight up out of the fork
	[0.028, 0.005, Vector2(0.175, 0.47), Vector2(0.22, 0.32), Vector2(0.16, 0.18), Vector2(0.21, 0.03)],
	# the far reach, out to the opposite corner
	[0.026, 0.005, Vector2(0.175, 0.47), Vector2(0.44, 0.30), Vector2(0.72, 0.20), Vector2(1.02, 0.11)],
]
const _SK_FAR := [
	[0.070, 0.020, Vector2(0.95, 1.06), Vector2(0.91, 0.95), Vector2(0.95, 0.86), Vector2(0.90, 0.76)],
	[0.020, 0.004, Vector2(0.91, 0.80), Vector2(0.80, 0.76), Vector2(0.72, 0.70), Vector2(0.64, 0.63)],
	[0.018, 0.004, Vector2(0.90, 0.77), Vector2(0.96, 0.70), Vector2(1.00, 0.64), Vector2(1.06, 0.58)],
	[0.018, 0.004, Vector2(0.90, 0.76), Vector2(0.88, 0.68), Vector2(0.92, 0.62), Vector2(0.88, 0.55)],
]

func _sakura_tree() -> void:
	var sky: Color = _pc("bg0")
	# The bank the trees stand on, so the trunks meet ground instead of stopping
	# in mid-air at the bottom edge.
	var bank := TextureRect.new()
	bank.texture = _round()
	bank.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bank.stretch_mode = TextureRect.STRETCH_SCALE
	bank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bank.size = Vector2(_vp.x * 1.6, _vp.y * 0.16)
	bank.position = Vector2(-_vp.x * 0.3, _vp.y * 1.01 - bank.size.y * 0.5)
	bank.modulate = Color(0.66, 0.44, 0.52, 0.38)
	add_child(bank)
	# --- The far tree: same skeleton, small, high, and washed toward the sky.
	_sakura_wood(_SK_FAR, _SK_WOOD.lerp(sky, 0.55), 0.55)
	_sakura_blossom(_SK_FAR, 0.62, 0.52, sky, 0.55)
	# --- The near tree, standing at the left with its head over the whole frame.
	_sakura_wood(_SK_NEAR, _SK_WOOD, 1.0)
	_sakura_blossom(_SK_NEAR, 1.0, 1.0, sky, 0.0)
	# Petals already down: pale drifts caught along the foot of the frame.
	for i in 7:
		var drift := TextureRect.new()
		drift.texture = _round()
		drift.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drift.stretch_mode = TextureRect.STRETCH_SCALE
		drift.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.16, 0.40)
		drift.size = Vector2(w, _vp.y * randf_range(0.014, 0.030))
		drift.position = Vector2(_vp.x * randf_range(-0.05, 0.95),
			_vp.y * randf_range(0.965, 1.005) - drift.size.y * 0.5)
		drift.modulate = Color(1.0, 0.78, 0.86, randf_range(0.30, 0.55))
		add_child(drift)

## The wood: one canvas item painted once. Limbs go down as tapered polygons
## with a lighter ridge up one side, then hair-thin twigs fork off the outer half
## of every limb — the part a blossom cluster half buries anyway, which is
## exactly how a cherry in flower looks.
func _sakura_wood(limbs: Array, bark: Color, scale: float) -> void:
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.size = _vp
	canvas.draw.connect(_draw_sakura_wood.bind(canvas, limbs, bark, scale))
	add_child(canvas)
	canvas.queue_redraw()

func _draw_sakura_wood(c: Control, limbs: Array, bark: Color, scale: float) -> void:
	var lit: Color = bark.lerp(Color(0.78, 0.62, 0.60), 0.42)
	for li in limbs.size():
		var e: Array = limbs[li]
		var pts := _bez_pts(e[2], e[3], e[4], e[5], 14)
		var w0: float = float(e[0]) * _vp.x
		var w1: float = float(e[1]) * _vp.x
		c.draw_colored_polygon(_taper_poly(pts, w0, w1), bark)
		# The ridge: the same limb again, thinner and offset a little to the lit
		# side, so the wood turns instead of reading as a flat cut-out.
		var ridge := PackedVector2Array()
		for p in pts:
			ridge.append(p + Vector2(-w0 * 0.16, -w0 * 0.06))
		c.draw_colored_polygon(_taper_poly(ridge, w0 * 0.34, w1 * 0.30),
			Color(lit.r, lit.g, lit.b, 0.55))
		# Twigs off the outer half — three per limb, alternating sides, each a
		# short taper that ends in a point.
		if li == 0:
			continue
		for k in 3:
			var t: float = 0.46 + 0.20 * float(k)
			var i: int = mini(int(t * float(pts.size() - 1)), pts.size() - 2)
			var at: Vector2 = pts[i]
			var run: Vector2 = (pts[i + 1] - at).normalized()
			var side: float = 1.0 if (li + k) % 2 == 0 else -1.0
			var nrm: Vector2 = Vector2(-run.y, run.x) * side
			var reach: float = _vp.x * (0.085 - 0.018 * float(k)) * scale
			var tip: Vector2 = at + (run * 0.55 + nrm * 0.85).normalized() * reach
			var mid: Vector2 = at.lerp(tip, 0.55) + nrm * reach * 0.14
			c.draw_colored_polygon(
				_taper_poly(_bez_px(at, mid, mid, tip, 6), w1 * 1.5, w1 * 0.3), bark)

## A cubic bezier sampled into `n` segments, taking viewport-FRACTION control
## points and returning pixels.
func _bez_pts(a: Vector2, b: Vector2, c2: Vector2, d: Vector2, n: int) -> PackedVector2Array:
	return _bez_px(a * _vp, b * _vp, c2 * _vp, d * _vp, n)

## The same, already in pixels.
func _bez_px(a: Vector2, b: Vector2, c2: Vector2, d: Vector2, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var t: float = float(i) / float(n)
		var u: float = 1.0 - t
		out.append(a * (u * u * u) + b * (3.0 * u * u * t)
			+ c2 * (3.0 * u * t * t) + d * (t * t * t))
	return out

## A polyline swept into a closed polygon that tapers from `w0` to `w1` — the
## shape a branch actually has. Down one side, back up the other.
func _taper_poly(pts: PackedVector2Array, w0: float, w1: float) -> PackedVector2Array:
	var n: int = pts.size()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in n:
		var t: float = float(i) / float(maxi(n - 1, 1))
		var hw: float = lerpf(w0, w1, t) * 0.5
		var run: Vector2
		if i == 0:
			run = pts[1] - pts[0]
		elif i == n - 1:
			run = pts[n - 1] - pts[n - 2]
		else:
			run = pts[i + 1] - pts[i - 1]
		var nrm: Vector2 = Vector2(-run.y, run.x).normalized() * hw
		left.append(pts[i] + nrm)
		right.append(pts[i] - nrm)
	var poly := PackedVector2Array()
	poly.append_array(left)
	for i in range(n - 1, -1, -1):
		poly.append(right[i])
	return poly

## The flower: clusters scattered along the outer half of every limb but the
## trunk, biggest and densest at the tips. Each one drifts on its own slow clock
## so the canopy breathes rather than sitting there.
func _sakura_blossom(limbs: Array, scale: float, alpha: float, sky: Color, haze: float) -> void:
	var cluster := _shaped("sk_cluster", 78, 62, _fn_blossom_cluster)
	for li in limbs.size():
		if li == 0:
			continue
		var e: Array = limbs[li]
		var pts := _bez_pts(e[2], e[3], e[4], e[5], 10)
		for k in 6:
			var t: float = 0.30 + 0.14 * float(k)
			var i: int = clampi(int(t * float(pts.size() - 1)), 0, pts.size() - 1)
			var at: Vector2 = pts[i]
			# Clusters sit ON the limb, thrown to both sides of it.
			var off := Vector2(randf_range(-0.58, 0.58), randf_range(-0.70, 0.50))
			var w: float = _vp.x * randf_range(0.18, 0.30) * scale * (0.72 + 0.42 * t)
			var puff := TextureRect.new()
			puff.texture = cluster
			puff.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			puff.stretch_mode = TextureRect.STRETCH_SCALE
			puff.mouse_filter = Control.MOUSE_FILTER_IGNORE
			puff.size = Vector2(w, w * (62.0 / 78.0))
			puff.pivot_offset = puff.size * 0.5
			puff.position = at + off * puff.size - puff.size * 0.5
			puff.rotation = randf_range(-0.5, 0.5)
			# Every cluster its own shade of the blossom, hazed toward the sky
			# with distance so the far tree sits behind the near one.
			var tint := Color(1.0, randf_range(0.80, 0.94), randf_range(0.86, 0.96))
			if haze > 0.0:
				tint = tint.lerp(sky, haze)
			puff.modulate = Color(tint.r, tint.g, tint.b, alpha * randf_range(0.82, 1.0))
			add_child(puff)
			# Wind: a slow lean, each on its own period, never in step.
			var sway := puff.create_tween().set_loops()
			sway.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			var base: float = puff.rotation
			var amp: float = randf_range(0.018, 0.045)
			var per: float = randf_range(2.6, 4.8)
			sway.tween_property(puff, "rotation", base + amp, per)
			sway.tween_property(puff, "rotation", base - amp, per * 1.15)
		# Sprigs: small single-cluster tufts out past the mass, so the canopy
		# ends in florets against the sky rather than in a clean round edge.
		for k in 5:
			var st: float = 0.42 + 0.14 * float(k)
			var si: int = clampi(int(st * float(pts.size() - 1)), 0, pts.size() - 1)
			var sw: float = _vp.x * randf_range(0.055, 0.10) * scale
			var sprig := TextureRect.new()
			sprig.texture = cluster
			sprig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sprig.stretch_mode = TextureRect.STRETCH_SCALE
			sprig.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sprig.size = Vector2(sw, sw * (62.0 / 78.0))
			sprig.pivot_offset = sprig.size * 0.5
			sprig.position = pts[si] + Vector2(randf_range(-1.6, 1.6),
				randf_range(-1.7, 1.3)) * sprig.size - sprig.size * 0.5
			sprig.rotation = randf_range(-1.0, 1.0)
			var sc2 := Color(1.0, randf_range(0.84, 0.96), randf_range(0.88, 0.98))
			if haze > 0.0:
				sc2 = sc2.lerp(sky, haze)
			sprig.modulate = Color(sc2.r, sc2.g, sc2.b, alpha * randf_range(0.70, 0.95))
			add_child(sprig)

## Shadow Fog — shapes that are only just there: a lamp post with a dying lamp,
## and bare trees receding into the murk at three depths.
func _fog_shapes() -> void:
	var murk: Color = _pc("bg0")
	var tree := _shaped("sf_tree", 78, 100, _fn_dead_tree)
	# Three depths, each paler and smaller — in fog, distance is contrast.
	for e_v in [[0.09, 0.195, 0.92], [0.42, 0.125, 0.55], [0.88, 0.165, 0.75],
			[0.66, 0.095, 0.35]]:
		var e: Array = e_v
		var d: float = float(e[2])
		_landmark(tree, float(e[0]), float(e[1]), 170.0 / 220.0,
			Color(0.05, 0.06, 0.09).lerp(murk, 1.0 - d), d * 0.85, 0.97)
	# The lamp post, and the small failing pool of light under it.
	_landmark(_shaped("sf_lamp", 58, 154, _fn_lamp_post), 0.28, 0.22,
		90.0 / 240.0, Color(0.10, 0.11, 0.15), 0.95, 0.975)
	var lamp_pos := Vector2(_vp.x * 0.28, _vp.y * 0.975 - _vp.y * 0.22 * 0.90)
	var halo := TextureRect.new()
	halo.texture = _dot()
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_SCALE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.size = Vector2(_vp.x * 0.46, _vp.x * 0.46)
	halo.position = lamp_pos - halo.size * 0.5
	halo.modulate = Color(0.86, 0.84, 0.68, 0.14)
	add_child(halo)
	var ht := halo.create_tween().set_loops()
	ht.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	ht.tween_property(halo, "modulate:a", 0.24, randf_range(2.0, 3.2))
	ht.tween_property(halo, "modulate:a", 0.09, randf_range(2.2, 3.6))
	# The light it manages to throw on the ground.
	var pool := TextureRect.new()
	pool.texture = _round()
	pool.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pool.stretch_mode = TextureRect.STRETCH_SCALE
	pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pool.size = Vector2(_vp.x * 0.42, _vp.y * 0.05)
	pool.position = Vector2(_vp.x * 0.28 - pool.size.x * 0.5, _vp.y * 0.965)
	pool.modulate = Color(0.82, 0.80, 0.64, 0.10)
	add_child(pool)

## Ocean — the seabed under all those bubbles: a sand floor with rocks and kelp
## swaying in the same current the bubbles are rising through.
func _sea_floor() -> void:
	var sand := Color(0.62, 0.60, 0.48)
	# The floor: overlapping sand banks.
	for i in 4:
		var bank := TextureRect.new()
		bank.texture = _round()
		bank.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bank.stretch_mode = TextureRect.STRETCH_SCALE
		bank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.5, 0.9)
		bank.size = Vector2(w, _vp.y * randf_range(0.06, 0.11))
		bank.position = Vector2(_vp.x * (0.05 + 0.30 * float(i)) - w * 0.5,
			_vp.y * randf_range(0.955, 0.995) - bank.size.y * 0.5)
		bank.modulate = Color(sand.r, sand.g, sand.b, 0.30)
		add_child(bank)
	# Rocks.
	var rock := _shaped("oc_rock", 94, 56, _fn_stone)
	_landmark(rock, 0.14, 0.075, 150.0 / 90.0, Color(0.32, 0.42, 0.44), 0.85)
	_landmark(rock, 0.86, 0.058, 150.0 / 90.0, Color(0.28, 0.38, 0.42), 0.8)
	# Kelp, swaying from its holdfast.
	var kelp := _shaped("oc_kelp", 44, 150, _fn_kelp)
	for e_v in [[0.06, 0.235], [0.19, 0.185], [0.81, 0.215], [0.95, 0.160], [0.55, 0.130]]:
		var e: Array = e_v
		var k := _landmark(kelp, float(e[0]), float(e[1]), 70.0 / 240.0,
			Color(0.16, 0.44, 0.32), randf_range(0.55, 0.8))
		var sw := k.create_tween().set_loops()
		sw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		var amp := randf_range(0.05, 0.11)
		sw.tween_interval(randf_range(0.0, 2.0))
		sw.tween_property(k, "rotation", amp, randf_range(3.4, 5.0))
		sw.tween_property(k, "rotation", -amp, randf_range(3.4, 5.0))


# --- Landmarks, batch 5 --------------------------------------------------------

## Moonlit Bamboo — what the moonbeam is falling on: a full moon behind the
## grove, a denser stand of culms at both edges, and a stone lantern on the path.
func _moonlit_grove() -> void:
	var jade: Color = _pc("accent")
	# The moon, low and large behind the bamboo.
	var mc := Vector2(_vp.x * 0.66, _vp.y * 0.20)
	var halo := TextureRect.new()
	halo.texture = _round()
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_SCALE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hd: float = _vp.x * 1.05
	halo.size = Vector2(hd, hd)
	halo.position = mc - halo.size * 0.5
	halo.modulate = Color(0.82, 0.94, 0.86, 0.10)
	add_child(halo)
	var ht := halo.create_tween().set_loops()
	ht.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	ht.tween_property(halo, "modulate:a", 0.18, 6.0)
	ht.tween_property(halo, "modulate:a", 0.08, 6.5)
	var moon := TextureRect.new()
	moon.texture = _moon()
	moon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	moon.stretch_mode = TextureRect.STRETCH_SCALE
	moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var md: float = _vp.x * 0.30
	moon.size = Vector2(md, md)
	moon.position = mc - moon.size * 0.5
	moon.modulate = Color(0.90, 0.97, 0.90, 0.92)
	add_child(moon)
	# A deeper stand of bamboo: far culms hazed, near ones nearly black. The
	# existing _silhouettes() draws three; these are the depth behind them.
	var stalk := _shaped("bamboo_stalk", 36, 300, _fn_bamboo)
	for e_v in [[0.20, 0.035, 0.22], [0.30, 0.026, 0.16], [0.44, 0.030, 0.13],
			[0.58, 0.024, 0.11], [0.70, 0.032, 0.18], [0.80, 0.022, 0.10],
			[0.88, 0.034, 0.20], [0.10, 0.028, 0.15]]:
		var e: Array = e_v
		var w: float = _vp.x * float(e[1])
		var culm := TextureRect.new()
		culm.texture = stalk
		culm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		culm.stretch_mode = TextureRect.STRETCH_SCALE
		culm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		culm.size = Vector2(w, _vp.y * 1.25)
		culm.pivot_offset = Vector2(w * 0.5, culm.size.y)
		culm.position = Vector2(_vp.x * float(e[0]) - w * 0.5, _vp.y * 1.02 - culm.size.y)
		var d: float = float(e[2])
		culm.modulate = Color(0.05 + d * 0.25, 0.14 + d * 0.35, 0.08 + d * 0.25, 0.55 + d)
		add_child(culm)
		var sway := culm.create_tween().set_loops()
		sway.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		sway.tween_property(culm, "rotation", randf_range(0.006, 0.016), randf_range(4.5, 6.5))
		sway.tween_property(culm, "rotation", randf_range(-0.016, -0.006), randf_range(4.5, 6.5))
	# The stone lantern on the path, with its small light.
	_landmark(_shaped("mb_toro", 82, 138, _fn_toro), 0.26, 0.20, 130.0 / 220.0,
		Color(0.30, 0.36, 0.32), 0.95)
	var glow := TextureRect.new()
	glow.texture = _dot()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.size = Vector2(_vp.x * 0.22, _vp.x * 0.22)
	glow.position = Vector2(_vp.x * 0.26 - glow.size.x * 0.5,
		_vp.y * 1.005 - _vp.y * 0.20 * 0.62 - glow.size.y * 0.5)
	glow.modulate = Color(1.0, 0.84, 0.46, 0.28)
	add_child(glow)
	var gt := glow.create_tween().set_loops()
	gt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	gt.tween_property(glow, "modulate:a", 0.44, randf_range(1.8, 2.8))
	gt.tween_property(glow, "modulate:a", 0.20, randf_range(2.0, 3.0))
	_edge_glow(jade, 0.04, 0.10, false)

## Coral Depths — a REEF, not three sticks: fan corals standing broadside to the
## current, brain coral domes on the floor, staghorn thickets and anemones whose
## tentacles wave. Layered front to back so the floor has depth.
func _reef_bed() -> void:
	var fan := _shaped("cd_seafan", 96, 108, _fn_seafan_big)
	var brain := _shaped("cd_brain", 96, 66, _fn_brain_coral)
	var anem := _shaped("cd_anemone", 62, 58, _fn_anemone)
	var stag := _shaped("cd_staghorn", 64, 82, _fn_staghorn)
	# Back layer: hazed, small, cool — distance under water is blue.
	var deep: Color = _pc("bg0").lerp(Color(0.20, 0.45, 0.62), 0.5)
	for e_v in [[0.12, 0.10], [0.38, 0.08], [0.62, 0.11], [0.88, 0.09]]:
		var e: Array = e_v
		_landmark(fan, float(e[0]), float(e[1]), 180.0 / 200.0, deep, 0.55, 0.975)
	# Mid layer.
	for e_v in [[0.06, 0.17, 0], [0.26, 0.075, 1], [0.50, 0.16, 3],
			[0.72, 0.065, 1], [0.94, 0.18, 0]]:
		var e: Array = e_v
		var tex: Texture2D = fan
		var asp := 180.0 / 200.0
		var tint := Color(0.86, 0.34, 0.52)
		if int(e[2]) == 1:
			tex = brain
			asp = 160.0 / 110.0
			tint = Color(0.72, 0.52, 0.44)
		elif int(e[2]) == 3:
			tex = stag
			asp = 150.0 / 190.0
			tint = Color(0.94, 0.78, 0.62)
		_landmark(tex, float(e[0]), float(e[1]), asp, tint, 0.85, 0.995)
	# Anemones in front, their tentacles breathing with the current.
	for e_v in [[0.18, 0.085], [0.44, 0.070], [0.80, 0.095]]:
		var e: Array = e_v
		var an := _landmark(anem, float(e[0]), float(e[1]), 140.0 / 130.0,
			Color(0.98, 0.52, 0.70), 0.92)
		var br := an.create_tween().set_loops()
		br.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		br.tween_interval(randf_range(0.0, 1.5))
		br.tween_property(an, "scale", Vector2(1.06, 0.94), randf_range(2.0, 3.0))
		br.tween_property(an, "scale", Vector2.ONE, randf_range(2.2, 3.4))

## Origami Sky — the paper landscape the folded birds are flying over: ranges of
## mountains creased out of flat sheets, each range a paler shade than the one
## in front of it.
func _origami_range() -> void:
	var peak := _shaped("os_range", 180, 78, _fn_paper_range)
	var sky: Color = _pc("bg0")
	# Four ranges, drawn far to near. Each nearer range is SHORTER and sits
	# LOWER than the one behind it, or it simply buries them — which is what
	# happened when they all grew toward the viewer together.
	# [x-frac, height-frac, base-frac, tint]
	var ranges := [
		[0.34, 0.150, 0.815, Color(0.60, 0.56, 0.80)],
		[0.62, 0.130, 0.870, Color(0.50, 0.46, 0.74)],
		[0.28, 0.110, 0.925, Color(0.38, 0.36, 0.62)],
		[0.70, 0.095, 0.985, Color(0.26, 0.25, 0.48)],
	]
	for i in ranges.size():
		var e: Array = ranges[i]
		var h: float = _vp.y * float(e[1])
		var w: float = h * (300.0 / 130.0)
		var r := TextureRect.new()
		r.texture = peak
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.size = Vector2(w, h)
		r.pivot_offset = r.size * 0.5
		# Mirror alternate ranges so the same three peaks never repeat.
		r.scale = Vector2(-1.0 if i % 2 == 0 else 1.0, 1.0)
		r.position = Vector2(_vp.x * float(e[0]) - w * 0.5, _vp.y * float(e[2]) - h)
		var t: Color = e[3]
		# Aerial perspective: the far ranges wash toward the sky behind them.
		var mixed := t.lerp(sky, 0.42 * float(ranges.size() - 1 - i) / 3.0)
		r.modulate = Color(mixed.r, mixed.g, mixed.b, 0.96)
		add_child(r)
	# A big crane, close, gliding across the whole frame every so often.
	_paper_flyby(_gen)

func _paper_flyby(gen: int) -> void:
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(8.0, 16.0)).timeout
		if gen != _gen or not is_inside_tree():
			return
		var crane := TextureRect.new()
		crane.texture = _shaped("os_crane", 110, 74, _fn_paper_crane)
		crane.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crane.stretch_mode = TextureRect.STRETCH_SCALE
		crane.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * 0.42
		crane.size = Vector2(w, w * (120.0 / 180.0))
		crane.pivot_offset = crane.size * 0.5
		var dir: float = 1.0 if randf() < 0.5 else -1.0
		crane.scale = Vector2(dir, 1.0)
		var y0: float = _vp.y * randf_range(0.18, 0.55)
		crane.position = Vector2(-w * 1.5 if dir > 0.0 else _vp.x + w * 0.5, y0)
		crane.modulate = Color(1.0, 0.96, 0.92, 0.0)
		add_child(crane)
		var dur := randf_range(7.0, 10.0)
		var tw := crane.create_tween()
		tw.set_parallel(true)
		tw.tween_property(crane, "position:x",
			(_vp.x + w * 1.5) if dir > 0.0 else -w * 1.5, dur).set_trans(Tween.TRANS_LINEAR)
		tw.tween_property(crane, "modulate:a", 0.92, 1.2)
		tw.tween_property(crane, "rotation", 0.06 * dir, dur * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.chain().tween_property(crane, "rotation", -0.04 * dir, dur * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.chain().tween_property(crane, "modulate:a", 0.0, 1.0)
		tw.chain().tween_callback(crane.queue_free)

# --- Carnival fairground -------------------------------------------------------
## The great wheel, standing at the back of the park: an A-frame on the ground,
## twelve spokes turning slowly, gondolas that stay LEVEL as they ride round
## (counter-rotated at the wheel's own rate), and a ring of rim bulbs chasing
## each other round the circumference. Anchored low so the board covers its
## middle and only the lit upper arc reads.
func _ferris_wheel() -> void:
	var hub := Vector2(_vp.x * 0.56, _vp.y * 0.735)
	var r: float = _vp.x * 0.46
	var warm := _pc("gold").lerp(Color(1.0, 0.86, 0.55), 0.5)
	var accent: Color = _pc("accent")
	var accent2: Color = _pc("accent2")
	const SPOKES := 16
	const TURN := 42.0            # seconds for one full revolution
	# The halo the whole ride sits in — a fairground is visible from the road.
	var glow := TextureRect.new()
	glow.texture = _round()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.size = Vector2(r * 3.4, r * 3.4)
	glow.position = hub - glow.size * 0.5
	glow.modulate = Color(warm.r, warm.g, warm.b, 0.07)
	add_child(glow)
	var gt := glow.create_tween().set_loops()
	gt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	gt.tween_property(glow, "modulate:a", 0.15, 4.5)
	gt.tween_property(glow, "modulate:a", 0.06, 5.0)
	# The A-frame it hangs on, laid down first so the wheel turns in front of it.
	var strut := Color(0.09, 0.06, 0.11, 0.92)
	for s_v in [-1.0, 1.0]:
		var s: float = s_v
		var leg := _srect(0.0, 0.0, r * 0.05, _vp.y - hub.y + r * 0.1, strut)
		leg.pivot_offset = Vector2(leg.size.x * 0.5, 0.0)
		leg.position = hub - Vector2(leg.size.x * 0.5, 0.0)
		leg.rotation = deg_to_rad(19.0 * s)
	# A cross-brace between the legs.
	var brace := _srect(0.0, 0.0, r * 1.0, r * 0.028, strut)
	brace.position = Vector2(hub.x - brace.size.x * 0.5, hub.y + (_vp.y - hub.y) * 0.62)
	# The wheel structure itself, baked whole: two rims, sixteen spokes, a hub.
	var wheel := Control.new()
	wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wheel.position = hub
	add_child(wheel)
	var frame := TextureRect.new()
	frame.texture = _shaped("ferris_frame", 180, 180, _fn_ferris)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size = Vector2(r * 2.0, r * 2.0)
	frame.position = -frame.size * 0.5
	frame.modulate = Color(0.86, 0.80, 0.92, 0.55)
	wheel.add_child(frame)
	# The rim bulbs — two per spoke bay, chasing round the circumference.
	var bulbs := SPOKES * 2
	for i in bulbs:
		var ang: float = TAU * float(i) / float(bulbs)
		var bulb := TextureRect.new()
		bulb.texture = _dot()
		bulb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bulb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = r * 0.085
		bulb.size = Vector2(d, d)
		bulb.position = Vector2(sin(ang), -cos(ang)) * r * 0.965 - bulb.size * 0.5
		var bc: Color = warm if i % 2 == 0 else accent2.lerp(_white(1.0), 0.35)
		bulb.modulate = Color(bc.r, bc.g, bc.b, 0.45)
		wheel.add_child(bulb)
		var chase := bulb.create_tween().set_loops()
		var ph: float = float(i) / float(bulbs) * 1.8
		chase.tween_interval(ph)
		chase.tween_property(bulb, "modulate:a", 1.0, 0.16)
		chase.tween_property(bulb, "modulate:a", 0.45, 0.55)
		chase.tween_interval(maxf(1.8 - ph, 0.01))
	# Gondolas: they ride the rim but never tip — each hangs off a holder that
	# turns backwards at exactly the wheel's rate, and carries its own lamp.
	var cabin_tex := _shaped("fair_cabin", 28, 24, _fn_cabin)
	for i in SPOKES:
		var ang: float = TAU * float(i) / float(SPOKES)
		var level := Control.new()
		level.mouse_filter = Control.MOUSE_FILTER_IGNORE
		level.position = Vector2(sin(ang), -cos(ang)) * r
		wheel.add_child(level)
		var cw: float = r * 0.235
		var cab := TextureRect.new()
		cab.texture = cabin_tex
		cab.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cab.stretch_mode = TextureRect.STRETCH_SCALE
		cab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cab.size = Vector2(cw, cw * 0.85)
		cab.position = Vector2(-cw * 0.5, 0.0)
		var cc: Color = warm if i % 3 == 0 else (accent if i % 3 == 1 else accent2)
		cab.modulate = Color(cc.r, cc.g, cc.b, 0.95)
		level.add_child(cab)
		# The little lamp burning inside it.
		var lamp := TextureRect.new()
		lamp.texture = _dot()
		lamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lamp.size = Vector2(cw * 0.62, cw * 0.62)
		lamp.position = Vector2(-lamp.size.x * 0.5, cw * 0.22)
		lamp.modulate = Color(1.0, 0.88, 0.55, 0.55)
		level.add_child(lamp)
		# Counter-turn: the holder cancels the WHEEL's rotation and nothing else.
		# World rotation = wheel.rotation + level.rotation, and the chair has to
		# hang at world 0 the whole way round, so this must run 0 → -TAU in step
		# with the wheel's 0 → TAU. Seeding it at -ang instead (the obvious-looking
		# "match the mounting angle") pins every chair at a CONSTANT tilt of -ang,
		# which is why the chair at the top of the wheel rode upside down.
		level.rotation = 0.0
		var lv := level.create_tween().set_loops()
		lv.tween_property(level, "rotation", -TAU, TURN).from(0.0)
	# The hub cap, over the spoke roots.
	var cap := TextureRect.new()
	cap.texture = _dot()
	cap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cd: float = r * 0.24
	cap.size = Vector2(cd, cd)
	cap.position = hub - cap.size * 0.5
	cap.modulate = Color(warm.r, warm.g, warm.b, 0.85)
	add_child(cap)
	var spin := wheel.create_tween().set_loops()
	spin.tween_property(wheel, "rotation", TAU, TURN).from(0.0)
	# The stalls along the bottom of the midway, under the ride: striped awnings
	# with a lamp burning over each counter.
	_midway_stalls()
	# A warm glow pooling under the whole park.
	_edge_glow(warm, 0.08, 0.18, false)

## The midway: a row of striped stall awnings across the very bottom of the
## screen, each lit by its own swinging bulb. Ends the park on the ground
## rather than letting the wheel float over nothing.
func _midway_stalls() -> void:
	var tex := _shaped("fair_stall", 78, 52, _fn_stall)
	var stripes: Array = [_pc("accent"), _pc("accent2"), _pc("gold")]
	for i in 4:
		var w: float = _vp.x * randf_range(0.26, 0.34)
		var h: float = w * 0.70
		var x: float = _vp.x * (float(i) * 0.30 - 0.06) + randf_range(-8.0, 8.0)
		var stall := TextureRect.new()
		stall.texture = tex
		stall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stall.stretch_mode = TextureRect.STRETCH_SCALE
		stall.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stall.size = Vector2(w, h)
		stall.position = Vector2(x, _vp.y * 0.995 - h)
		var sc: Color = stripes[i % stripes.size()]
		stall.modulate = Color(sc.r, sc.g, sc.b, 0.72)
		add_child(stall)
		# The bulb over its counter, swinging on its flex.
		var pivot := Control.new()
		pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pivot.position = Vector2(x + w * 0.5, _vp.y * 1.005 - h * 0.72)
		add_child(pivot)
		var bulb := TextureRect.new()
		bulb.texture = _dot()
		bulb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bulb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bd: float = w * 0.16
		bulb.size = Vector2(bd, bd)
		bulb.position = Vector2(-bd * 0.5, h * 0.18)
		bulb.modulate = Color(1.0, 0.90, 0.58, 0.8)
		pivot.add_child(bulb)
		var sw := pivot.create_tween().set_loops()
		sw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		sw.tween_property(pivot, "rotation", 0.10, randf_range(2.2, 3.2))
		sw.tween_property(pivot, "rotation", -0.10, randf_range(2.2, 3.2))

## Bunting and light strings slung across the top of the park: two garlands of
## triangular pennants and one string of bare bulbs, each sagging in a catenary
## and swaying on the night air, with the bulbs blinking down the line.
func _park_lights() -> void:
	var warm := _pc("gold").lerp(Color(1.0, 0.88, 0.6), 0.5)
	var flag_cols: Array = [_pc("accent"), _pc("accent2"), warm,
		_pc("accent").lerp(_white(1.0), 0.45)]
	# Two pennant garlands at different heights, hung from opposite corners.
	# The line itself is `_pennant_line` — the sweet shop wanted the same bunting
	# and this is where it came from, so the geometry lives in one place now.
	for row in 2:
		_pennant_line(_vp.y * (0.055 + float(row) * 0.075),
			_vp.y * (0.075 if row == 0 else 0.055), 13, _vp.x * 0.052,
			flag_cols, 0.9)
	# A bare-bulb string under the bunting, blinking down the line.
	var m := 16
	var y_base: float = _vp.y * 0.185
	var prev_b := Vector2(-_vp.x * 0.05, y_base)
	for i in range(m + 1):
		var f: float = float(i) / float(m)
		var here := Vector2(lerpf(-_vp.x * 0.05, _vp.x * 1.05, f),
			y_base + _vp.y * 0.045 * sin(f * PI))
		var seg := ColorRect.new()
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seg.color = Color(1, 1, 1, 0.12)
		var d := here - prev_b
		seg.size = Vector2(d.length(), maxf(_vp.x * 0.003, 1.0))
		seg.pivot_offset = Vector2(0.0, seg.size.y * 0.5)
		seg.position = prev_b - Vector2(0.0, seg.size.y * 0.5)
		seg.rotation = d.angle()
		add_child(seg)
		prev_b = here
		var bulb := TextureRect.new()
		bulb.texture = _dot()
		bulb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bulb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bd: float = _vp.x * 0.030
		bulb.size = Vector2(bd, bd)
		bulb.position = here - bulb.size * 0.5 + Vector2(0.0, bd * 0.35)
		var bc: Color = warm if i % 2 == 0 else _pc("accent2").lerp(_white(1.0), 0.35)
		bulb.modulate = Color(bc.r, bc.g, bc.b, 0.4)
		add_child(bulb)
		var tw := bulb.create_tween().set_loops()
		tw.tween_interval(f * 1.2)
		tw.tween_property(bulb, "modulate:a", 0.95, 0.25)
		tw.tween_property(bulb, "modulate:a", 0.4, 0.6)
		tw.tween_interval(1.2 - f * 1.2)

## Spawns a firework burst every so often until this build generation is replaced.
func _fireworks_loop(gen: int) -> void:
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(0.7, 1.8)).timeout
		if gen != _gen or not is_inside_tree():
			return
		_one_firework()

func _one_firework() -> void:
	var pos := Vector2(randf_range(_vp.x * 0.15, _vp.x * 0.85),
		randf_range(_vp.y * 0.12, _vp.y * 0.5))
	var col := Color.from_hsv(randf(), 0.6, 1.0)
	var ps := CPUParticles2D.new()
	ps.position = pos
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.amount = 36
	ps.lifetime = randf_range(0.9, 1.4)
	ps.texture = _dot()
	ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	ps.direction = Vector2(0, -1)
	ps.spread = 180.0
	# Real firework physics: sparks burst fast, drag bleeds their speed, then they
	# ARC DOWN under gravity as they burn out — not a symmetric puff.
	ps.gravity = Vector2(0, 150.0)
	ps.initial_velocity_min = 90.0
	ps.initial_velocity_max = 240.0
	ps.damping_min = 40.0
	ps.damping_max = 110.0
	ps.scale_amount_min = 0.4
	ps.scale_amount_max = 1.0
	ps.color_initial_ramp = _two(col, col.lerp(_white(1.0), 0.6))
	# Sparks flare, hold, then cool and die along the fall.
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.9), Color(1, 0.75, 0.55, 0)])
	ps.color_ramp = fade
	ps.emitting = true
	ps.finished.connect(ps.queue_free)
	add_child(ps)
	# The burst's bloom: a soft flash that blows out and fades in a blink.
	var flash := TextureRect.new()
	flash.texture = _round()
	flash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fd: float = randf_range(140.0, 220.0)
	flash.size = Vector2(fd, fd)
	flash.position = pos - flash.size * 0.5
	flash.pivot_offset = flash.size * 0.5
	flash.scale = Vector2(0.4, 0.4)
	flash.modulate = Color(col.lerp(_white(1.0), 0.7), 0.55)
	add_child(flash)
	var tw := flash.create_tween().set_parallel(true).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "scale", Vector2.ONE, 0.3)
	tw.tween_property(flash, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(flash.queue_free)

func _m_hearts() -> void:
	# Kawaii — a fuller cute mix floating up: bright multi-coloured hearts, sweet STARS
	# and fine sparkle dust.
	_emit({"from": "bottom", "tex": _heart(),
		"iramp": _ramp_cols([Color("FF4D94"), Color("FF7EB6"), Color("C89CFF"), Color("FF9ED8")]),
		"alpha": 0.95, "amount": 30, "lifetime": 9.0, "dir": Vector3(0.05, -1, 0),
		"spread": 24.0, "vmin": 22.0, "vmax": 60.0, "smin": 0.5, "smax": 1.4, "spin": 0.6,
		"twinkle": true})
	# Sweet pastel stars drifting up among the hearts.
	_emit({"from": "bottom", "tex": _sparkle(),
		"iramp": _ramp_cols([Color("FFE08A"), Color("FFFFFF"), Color("B7E6FF"), Color("FFC1E0")]),
		"alpha": 0.9, "amount": 22, "lifetime": 8.0, "dir": Vector3(0.05, -1, 0),
		"spread": 26.0, "vmin": 20.0, "vmax": 55.0, "smin": 0.5, "smax": 1.1, "twinkle": true})
	# Fine sparkle dust everywhere.
	_emit({"from": "all", "tex": _dot(), "color": _pc("accent2").lerp(_white(1.0), 0.4),
		"alpha": 0.9, "amount": 30, "lifetime": 4.0, "dir": Vector3(0, 1, 0), "spread": 180.0,
		"vmin": 1.0, "vmax": 4.0, "smin": 0.3, "smax": 0.7, "twinkle": true})
	_kawaii_sky()

## Slow, wide cloud bands drifting sideways across the sky (sunset).
func _cloud_bands(col: Color) -> void:
	for i in 3:
		var c := TextureRect.new()
		c.texture = _round()
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = _vp.x * randf_range(0.7, 1.1)
		var h: float = _vp.y * 0.16
		c.size = Vector2(w, h)
		var y: float = _vp.y * lerpf(0.30, 0.70, float(i) / 2.0)
		c.position = Vector2(randf_range(-w * 0.3, _vp.x - w * 0.5), y - h * 0.5)
		var tint: Color = col.darkened(0.2) if i % 2 == 0 else col
		c.modulate = Color(tint.r, tint.g, tint.b, 0.12)
		add_child(c)
		var home_x: float = c.position.x
		var off: float = _vp.x * 0.12
		var tw := c.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(c, "position:x", home_x + off, randf_range(14.0, 20.0))
		tw.tween_property(c, "position:x", home_x - off, randf_range(14.0, 20.0))

## An autumn-leaf colour gradient (reds → oranges → golds → brown) for the
## per-particle initial ramp.
func _autumn() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	g.colors = PackedColorArray([
		Color(0.86, 0.22, 0.12), Color(0.94, 0.50, 0.14),
		Color(0.96, 0.76, 0.20), Color(0.60, 0.30, 0.10)])
	return g

# --- Premium special effects --------------------------------------------------
## A soft, wide glow band hugging the top (horizon/dawn/caustics) or bottom
## (lava/dune) edge, breathing gently in and out.
func _edge_glow(col: Color, base_a: float, peak_a: float, top: bool) -> void:
	var g := TextureRect.new()
	g.texture = _round()
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w: float = _vp.x * 1.8
	var h: float = _vp.y * 0.5
	g.size = Vector2(w, h)
	var y: float = (-h * 0.55) if top else (_vp.y - h * 0.45)
	g.position = Vector2((_vp.x - w) * 0.5, y)
	g.modulate = Color(col.r, col.g, col.b, base_a)
	add_child(g)
	var tw := g.create_tween().set_loops()
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(g, "modulate:a", peak_a, 5.5)
	tw.tween_property(g, "modulate:a", base_a, 6.0)

## A pale moonbeam shaft slanting down from the upper right, brightening softly.
func _moonbeam() -> void:
	var b := TextureRect.new()
	b.texture = _round()
	b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w: float = _vp.x * 0.55
	var h: float = _vp.y * 1.2
	b.size = Vector2(w, h)
	b.position = Vector2(_vp.x * 0.58 - w * 0.5, -h * 0.2)
	b.modulate = Color(0.86, 0.96, 0.86, 0.07)
	add_child(b)
	var tw := b.create_tween().set_loops()
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(b, "modulate:a", 0.14, 5.0)
	tw.tween_property(b, "modulate:a", 0.06, 5.5)

## An occasional full-screen colour flash (prismatic glint / spectral / glitch).
func _ambient_flash(col: Color, peak: float, lo: float, hi: float) -> void:
	var flash := ColorRect.new()
	flash.position = Vector2.ZERO
	flash.size = _vp
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(col.r, col.g, col.b, 0.0)
	add_child(flash)
	while is_instance_valid(flash) and is_inside_tree():
		await get_tree().create_timer(randf_range(lo, hi)).timeout
		if not is_instance_valid(flash):
			return
		var tw := flash.create_tween()
		tw.tween_property(flash, "color:a", peak, 0.07)
		tw.tween_property(flash, "color:a", 0.0, 0.32)

## Periodic shooting stars streaking across the upper sky (Desert Midnight).
func _shooting_stars(gen: int) -> void:
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(2.6, 6.5)).timeout
		if gen != _gen or not is_inside_tree():
			return
		_one_shooting_star()

func _one_shooting_star() -> void:
	# One in four is a brighter, longer, slower comet for variety.
	var comet := randf() < 0.25
	var s := TextureRect.new()
	s.texture = _streak()
	s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.size = Vector2(6.0 if comet else 4.0, _vp.x * (0.36 if comet else 0.22))
	s.pivot_offset = s.size * 0.5
	s.rotation = deg_to_rad(58.0)
	s.position = Vector2(randf_range(_vp.x * 0.25, _vp.x * 0.92),
		randf_range(_vp.y * 0.05, _vp.y * 0.34))
	s.modulate = Color(1, 1, 1, 0.0)
	add_child(s)
	var travel := Vector2(-_vp.x * 0.5, _vp.y * 0.32)
	var dur: float = 1.2 if comet else 0.85
	var tw := s.create_tween().set_parallel(true)
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(s, "position", s.position + travel, dur)
	tw.tween_property(s, "modulate:a", 1.0 if comet else 0.9, 0.16)
	tw.parallel().tween_property(s, "modulate:a", 0.0, dur * 0.6).set_delay(dur * 0.4)
	await tw.finished
	if is_instance_valid(s):
		s.queue_free()

## A slow diagonal glint sweeping across the board — metallic sparkle for the
## gold / silver / crystal themes.
func _shimmer_sweep(col: Color, gen: int) -> void:
	var s := TextureRect.new()
	s.texture = _round()
	s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w: float = _vp.x * 0.45
	var h: float = _vp.y * 1.7
	s.size = Vector2(w, h)
	s.pivot_offset = s.size * 0.5
	s.rotation = deg_to_rad(20.0)
	add_child(s)
	while is_instance_valid(s) and gen == _gen:
		s.position = Vector2(-w, -_vp.y * 0.35)
		s.modulate = Color(col.r, col.g, col.b, 0.0)
		var tw := s.create_tween()
		tw.set_parallel(true)
		tw.tween_property(s, "position:x", _vp.x + w, 2.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(s, "modulate:a", 0.12, 1.3).set_trans(Tween.TRANS_SINE)
		tw.chain().tween_property(s, "modulate:a", 0.0, 1.3)
		await tw.finished
		if gen != _gen or not is_instance_valid(s):
			return
		await get_tree().create_timer(randf_range(1.6, 3.2)).timeout

## Glowing drips falling from the ceiling (lava for Ember Cave, acid for Toxic).
func _drips(gen: int, col: Color) -> void:
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(0.7, 1.9)).timeout
		if gen != _gen or not is_inside_tree():
			return
		_one_drip(col)

func _one_drip(col: Color) -> void:
	var d := TextureRect.new()
	d.texture = _dot()
	d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.size = Vector2(9.0, 16.0)
	d.modulate = Color(col.r, col.g, col.b, 0.95)
	d.position = Vector2(randf_range(_vp.x * 0.1, _vp.x * 0.9), -24.0)
	add_child(d)
	var dur := randf_range(1.2, 2.0)
	var tw := d.create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(d, "position:y", _vp.y + 40.0, dur)
	tw.tween_property(d, "modulate:a", 0.0, dur * 0.6).set_delay(dur * 0.4)
	await tw.finished
	if is_instance_valid(d):
		d.queue_free()

## Hosts a full-screen procedural shader inside a LOW-RESOLUTION SubViewport that
## linear filtering upscales back to the screen. The soft, low-frequency shaders
## (aurora curtains, caustic webs, the ice ribbon) are visually identical at a
## fraction of the resolution, but the per-pixel noise math — the aurora runs ~12
## octaves of gradient noise per fragment — drops by the shrink factor SQUARED
## (~9× on phones). This is what makes the heavy "living" themes smooth on mobile
## without dimming, thinning or slowing anything. Crisp-edged shaders (the
## synthwave grid, CRT scanlines) must NOT go through this — they'd blur.
func _shader_layer(mat: ShaderMaterial) -> void:
	var container := SubViewportContainer.new()
	container.position = Vector2.ZERO
	container.size = _vp
	container.stretch = true
	container.stretch_shrink = 3 if OS.has_feature("mobile") else 2
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(vp)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	vp.add_child(rect)
	add_child(container)

## A faint aurora/ice ribbon shimmering along the top sky (Glacier Dawn, shader).
func _ribbon(col_a: Color, col_b: Color) -> void:
	if _ribbon_mat == null:
		if _ribbon_shader == null:
			_ribbon_shader = Shader.new()
			_ribbon_shader.code = _RIBBON_CODE
		_ribbon_mat = ShaderMaterial.new()
		_ribbon_mat.shader = _ribbon_shader
	_ribbon_mat.set_shader_parameter("col_a", col_a)
	_ribbon_mat.set_shader_parameter("col_b", col_b)
	_ribbon_mat.set_shader_parameter("speed", 0.08)
	_ribbon_mat.set_shader_parameter("intensity", 0.5)
	_shader_layer(_ribbon_mat)

## Moving underwater caustics rippling down from the surface (Coral Depths, shader).
func _caustics(tint: Color) -> void:
	if _caustics_mat == null:
		if _caustics_shader == null:
			_caustics_shader = Shader.new()
			_caustics_shader.code = _CAUSTICS_CODE
		_caustics_mat = ShaderMaterial.new()
		_caustics_mat.shader = _caustics_shader
	_caustics_mat.set_shader_parameter("tint", tint)
	_caustics_mat.set_shader_parameter("speed", 0.4)
	_caustics_mat.set_shader_parameter("intensity", 0.22)
	_shader_layer(_caustics_mat)

## Drifting CRT scanlines + an occasional glitch bar (Toxic Neon, shader).
func _scanlines(tint: Color) -> void:
	var rect := ColorRect.new()
	rect.position = Vector2.ZERO
	rect.size = _vp
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _scan_mat == null:
		if _scan_shader == null:
			_scan_shader = Shader.new()
			_scan_shader.code = _SCAN_CODE
		_scan_mat = ShaderMaterial.new()
		_scan_mat.shader = _scan_shader
	_scan_mat.set_shader_parameter("tint", tint)
	_scan_mat.set_shader_parameter("intensity", 0.05)
	rect.material = _scan_mat
	add_child(rect)

## A couple of dark bamboo-stalk silhouettes at the edges, swaying gently.
func _silhouettes() -> void:
	# Real bamboo: segmented culms with node rings and leaf tufts, swaying
	# gently from the roots, silhouetted against the moonbeam.
	var stalk_tex := _shaped("bamboo_stalk", 36, 300, _fn_bamboo)
	var leaf_tex := _shaped("bamboo_leaf", 90, 26, _fn_bamboo_leaf)
	var col := Color(0.05, 0.14, 0.08)
	# [x-frac, width-frac of vp.x, alpha, lean direction]
	for e_v in [[0.05, 0.045, 0.62, 1.0], [0.93, 0.05, 0.68, -1.0], [0.15, 0.028, 0.38, 1.0]]:
		var e: Array = e_v
		var pivot := Control.new()
		pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pivot.position = Vector2(_vp.x * float(e[0]), _vp.y * 1.03)
		add_child(pivot)
		var w: float = _vp.x * float(e[1])
		var h: float = _vp.y * 1.18
		var stalk := TextureRect.new()
		stalk.texture = stalk_tex
		stalk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stalk.stretch_mode = TextureRect.STRETCH_SCALE
		stalk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stalk.size = Vector2(w, h)
		stalk.position = Vector2(-w * 0.5, -h)
		stalk.modulate = Color(col.r, col.g, col.b, float(e[2]))
		pivot.add_child(stalk)
		# Leaf blades sprouting from the upper nodes, leaning into the screen.
		for k in 4:
			var leaf := TextureRect.new()
			leaf.texture = leaf_tex
			leaf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var lw: float = w * randf_range(2.6, 4.0)
			leaf.size = Vector2(lw, lw * 0.29)
			leaf.pivot_offset = Vector2(0.0, leaf.size.y * 0.5)
			leaf.position = Vector2(0.0, -h * randf_range(0.55, 0.92))
			var side: float = float(e[3]) * (1.0 if k != 2 else -1.0)
			leaf.rotation = randf_range(0.15, 0.6) if side > 0.0 \
				else PI - randf_range(0.15, 0.6)
			leaf.modulate = Color(col.r, col.g, col.b, float(e[2]) * 0.9)
			pivot.add_child(leaf)
		# The sway, from the base — the whole culm leans as one.
		var tw := pivot.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(pivot, "rotation", 0.018 * float(e[3]), randf_range(4.5, 6.0))
		tw.tween_property(pivot, "rotation", -0.014 * float(e[3]), randf_range(4.5, 6.0))

## A bamboo culm: a cylinder-shaded stalk with a dark node ring and a pale
## collar at every segment joint.
func _fn_bamboo(uv: Vector2) -> Color:
	var ax := absf(uv.x)
	var a := 1.0 - smoothstep(0.66, 0.84, ax)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var b := 0.30 + 0.35 * (1.0 - ax)
	var seg := fposmod(uv.y * 2.4 + 1.0, 0.8)
	if seg < 0.055:
		b *= 0.45     # the dark node ring
	elif seg < 0.10:
		b = minf(b * 1.5, 1.0)   # the pale collar just above it
	return Color(b, b, b, a)

## A slender bamboo leaf blade: widest a third along, tapering to a point.
func _fn_bamboo_leaf(uv: Vector2) -> Color:
	var t := (uv.x + 1.0) * 0.5
	var hw := 0.85 * sin(PI * pow(t, 0.75))
	var a := 1.0 - smoothstep(maxf(hw - 0.25, 0.0), maxf(hw, 0.01), absf(uv.y))
	if t < 0.02 or a <= 0.02:
		return Color(0, 0, 0, 0)
	var b := 0.35 + 0.20 * (1.0 - absf(uv.y))
	return Color(b, b, b, a)

## A large soft light drifting side to side through the murk (Shadow Fog).
func _searchlight(col: Color) -> void:
	var g := TextureRect.new()
	g.texture = _round()
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d: float = _vp.y * 0.85
	g.size = Vector2(d, d)
	g.position = Vector2(-d * 0.5, _vp.y * 0.18)
	g.modulate = Color(col.r, col.g, col.b, 0.09)
	add_child(g)
	var tw := g.create_tween().set_loops()
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(g, "position:x", _vp.x - d * 0.5, 9.0)
	tw.tween_property(g, "position:x", -d * 0.5, 9.0)

## Ghostly orbs that drift along an arc, each trailing a couple of fading echoes.
func _ghost_orbs(gen: int) -> void:
	while is_inside_tree() and gen == _gen:
		await get_tree().create_timer(randf_range(0.7, 1.6)).timeout
		if gen != _gen or not is_inside_tree():
			return
		_one_ghost()

func _one_ghost() -> void:
	var col: Color = _pc("accent").lerp(_white(1.0), 0.3)
	var start := Vector2(randf_range(_vp.x * 0.12, _vp.x * 0.88), _vp.y * randf_range(0.35, 0.85))
	var drift := Vector2(randf_range(-70.0, 70.0), -randf_range(120.0, 250.0))
	for k in 3:
		var o := TextureRect.new()
		o.texture = _orb()
		o.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		o.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sz: float = 58.0 - float(k) * 14.0
		o.size = Vector2(sz, sz)
		o.position = start - o.size * 0.5
		o.modulate = Color(col.r, col.g, col.b, 0.0)
		add_child(o)
		var peak: float = 0.5 - float(k) * 0.13
		var tw := o.create_tween()
		tw.tween_interval(float(k) * 0.13)
		tw.tween_property(o, "modulate:a", peak, 0.5)
		tw.parallel().tween_property(o, "position", (start + drift) - o.size * 0.5, 2.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(o, "modulate:a", 0.0, 0.9)
		tw.tween_callback(o.queue_free)

# --- Generic particle builder -------------------------------------------------
# Uses CPUParticles2D (not GPUParticles2D): GPU particles silently render nothing
# on many Android devices/drivers, while CPU particles work everywhere. The counts
# here (≤130) are trivial for the CPU on mobile.
# Device-tier particle budget: a rough phone-class heuristic (CPU core count is a
# cheap, zero-config proxy) that thins every particle field on weaker hardware so
# the heaviest themes hold their frame rate on low-end phones. Computed once and
# shared across every BoardFx instance. 1.0 = full field.
static var _fx_scale_cache: float = -1.0

func _particle_scale() -> float:
	if _fx_scale_cache < 0.0:
		var cores := OS.get_processor_count()
		var s := 1.0
		if cores <= 4:
			s = 0.6
		elif cores <= 6:
			s = 0.8
		# Phones get a ceiling regardless of core count: modern budget Androids
		# report 8 cores but their per-core speed and GPU fill-rate are nowhere
		# near desktop — full-density fields read as "kind of laggy" there.
		if OS.has_feature("mobile"):
			s = minf(s, 0.7)
		_fx_scale_cache = s
	return _fx_scale_cache

func _emit(p: Dictionary) -> CPUParticles2D:
	var ps := CPUParticles2D.new()
	# Feel profile sets the field density: arcade busiest, then vivid and living,
	# with calm/playful at the authored amount. (See ThemeManager.fx_density —
	# "living" and "vivid" used to be inert labels that ran at calm density.)
	var amt: int = int(p.get("amount", 40))
	amt = int(round(float(amt) * ThemeManager.fx_density_for(_pal())))
	# A gentle global liveliness lift — every theme's ambient field runs a touch
	# denser so the board always feels alive (still thinned by _particle_scale on
	# lower-end phones, so it never costs the frame rate it's decorating).
	amt = int(round(amt * 1.15))
	amt = int(round(float(amt) * _particle_scale()))   # thin the field on lower-end phones
	amt = int(round(float(amt) * ambience_scale))      # ...and on menu backdrops
	# B1 (phones only): a clipped instance keeps the authored DENSITY but only
	# simulates its visible share. BOTH the count and the emission region shrink
	# to the clip window (grown so drifters still enter across the window edge)
	# — scaling the count against a still-full-screen emission box would thin
	# the in-window field to frac² of authored (the adversarial-review finding).
	# amt×frac particles over the region's area = authored density exactly; the
	# unclipped region is the full screen, reproducing the old geometry
	# bit-identically. Stochastic, so it stays behind the clip hint AND
	# lite_gpu(): the desktop G5 gate's particle sample — arctic snow sits in a
	# gated gameplay shot — is untouched.
	var region := Rect2(Vector2.ZERO, _vp)
	var clipped_lite: bool = clip_rect.is_valid() and AppScreen.lite_gpu()
	if clipped_lite:
		var win: Rect2 = clip_rect.call()
		if win.size.x > 0.0 and win.size.y > 0.0:
			region = win.grow(48.0).intersection(Rect2(Vector2.ZERO, _vp))
			var frac: float = clampf(
				(region.size.x * region.size.y) / maxf(_vp.x * _vp.y, 1.0), 0.0, 1.0)
			amt = int(ceil(float(amt) * frac))
	ps.amount = maxi(amt, 1)
	ps.lifetime = float(p.get("lifetime", 8.0))
	# Pre-age the field so it looks established the instant the board appears, but
	# cap it low: preprocess simulates synchronously on the main thread when the
	# emitter starts, so a large value stalls the transition into gameplay. Phones
	# get an even lower cap — with the richer multi-emitter motifs, 3s × every
	# emitter was a visible hitch on scene changes.
	var pre: float = 1.5 if OS.has_feature("mobile") else 3.0
	# Menu backdrops cap hardest: the stacked per-emitter preprocess is the frame
	# hitch you feel when a menu screen appears and you immediately start
	# scrolling. At half alpha behind the frost a younger field is invisible.
	if ambience_scale < 1.0:
		pre = 0.75
	ps.preprocess = minf(ps.lifetime, pre)
	ps.randomness = 0.6
	ps.texture = p.get("tex", _round())
	# Spawn region: across the top, across the bottom, or the whole region (the
	# full screen unclipped; the grown clip window on a clipped phone instance —
	# strips ride the region's edges so falling motifs still enter the window).
	var rc := region.get_center()
	var box := region.size * 0.5
	match String(p.get("from", "all")):
		"top":
			ps.position = Vector2(rc.x, region.position.y - region.size.y * 0.04)
			box = Vector2(region.size.x * 0.55, region.size.y * 0.04)
		"bottom":
			ps.position = Vector2(rc.x, region.end.y + region.size.y * 0.04)
			box = Vector2(region.size.x * 0.55, region.size.y * 0.04)
		_:
			ps.position = rc
	ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	ps.emission_rect_extents = box

	var dir3: Vector3 = p.get("dir", Vector3(0, 1, 0))
	ps.direction = Vector2(dir3.x, dir3.y)
	ps.spread = float(p.get("spread", 10.0))
	ps.gravity = Vector2(0, float(p.get("gravity", 0.0)))
	ps.initial_velocity_min = float(p.get("vmin", 10.0))
	ps.initial_velocity_max = float(p.get("vmax", 30.0))
	# Organic wander: "turb" gives each particle its own light sideways curve, so
	# snow, petals, bubbles, embers and lanterns meander like real things in air or
	# water instead of travelling on rails. (CPUParticles2D has no turbulence field;
	# a small random orbit velocity is the same effect at these speeds.)
	var turb: float = float(p.get("turb", 0.0))
	if p.has("orbit"):
		# One-signed orbit: the whole layer swirls the SAME direction — wind-gust
		# debris, vortex spirals — versus turb's tiny ± wander.
		var ob: float = float(p["orbit"])
		ps.orbit_velocity_min = ob * 0.55
		ps.orbit_velocity_max = ob
	elif turb > 0.0:
		ps.orbit_velocity_min = -0.0075 * turb
		ps.orbit_velocity_max = 0.0075 * turb
	# Half-rate simulation for the SLOW ambience fields on phones — and on menu
	# backdrops on every platform: at ≤120 px/s a 30 Hz step moves a particle
	# under 2px per update — invisible — and it halves the per-frame CPU cost of
	# every drifting field (and its preprocess). Fast streaks (rain, code, gems)
	# keep full rate so they never judder.
	# B1 extends the policy to ALL fields of a clipped instance (phones only):
	# behind the tiles at 0.7 alpha inside the board window, a 30 Hz streak is
	# unreadable — device validation (stall metric) owns the final say.
	if clipped_lite \
			or ((OS.has_feature("mobile") or ambience_scale < 1.0)
			and float(p.get("vmax", 30.0)) <= 120.0):
		ps.fixed_fps = 30
	ps.scale_amount_min = float(p.get("smin", 1.0))
	ps.scale_amount_max = float(p.get("smax", 3.0))
	if bool(p.get("align", false)):
		# Rain drops fly head-first: aligned to their velocity, never rotating.
		ps.particle_flag_align_y = true
	if p.has("spin"):
		var sp: float = float(p["spin"])
		ps.angle_min = -180.0
		ps.angle_max = 180.0
		ps.angular_velocity_min = -sp * 72.0
		ps.angular_velocity_max = sp * 72.0
	var col: Color = p.get("color", Color.WHITE)
	var a: float = float(p.get("alpha", 0.6))
	if p.has("iramp"):
		# Per-particle colour from a custom gradient (e.g. neon magenta/cyan).
		ps.color_initial_ramp = p["iramp"]
		ps.color_ramp = _alpha_ramp(Color(1, 1, 1), a, bool(p.get("twinkle", false)))
	elif bool(p.get("hue", false)):
		# Per-particle random colour (confetti) via the initial ramp.
		ps.color_initial_ramp = _rainbow()
		ps.color_ramp = _alpha_ramp(Color(1, 1, 1), a, false)
	else:
		ps.color_ramp = _alpha_ramp(col, a, bool(p.get("twinkle", false)))
	ps.emitting = true
	add_child(ps)
	# Handed back so a motif can keep driving the field it just asked for — the
	# snow wind tweens the returned node's modulate to make the gusts come and
	# go. Every other call site ignores it.
	return ps

## A lifetime alpha curve: fade in → hold → fade out (or fade in→out for twinkle).
func _alpha_ramp(col: Color, a: float, twinkle: bool) -> Gradient:
	var g := Gradient.new()
	if twinkle:
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([
			Color(col.r, col.g, col.b, 0.0),
			Color(col.r, col.g, col.b, a),
			Color(col.r, col.g, col.b, 0.0)])
	else:
		g.offsets = PackedFloat32Array([0.0, 0.12, 0.85, 1.0])
		g.colors = PackedColorArray([
			Color(col.r, col.g, col.b, 0.0),
			Color(col.r, col.g, col.b, a),
			Color(col.r, col.g, col.b, a),
			Color(col.r, col.g, col.b, 0.0)])
	return g

func _two(c1: Color, c2: Color) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([c1, c2])
	return g

## A per-particle colour ramp from an arbitrary list of bright colours.
func _ramp_cols(cols: Array) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var pc := PackedColorArray()
	var n := cols.size()
	for i in n:
		offs.append(float(i) / float(maxi(n - 1, 1)))
		pc.append(cols[i])
	g.offsets = offs
	g.colors = pc
	return g

func _rainbow() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 0.35, 0.45), Color(1.0, 0.7, 0.3), Color(1.0, 0.95, 0.45),
		Color(0.45, 0.95, 0.6), Color(0.4, 0.75, 1.0), Color(0.8, 0.55, 1.0)])
	return g

# --- Lightning (storm rain) ---------------------------------------------------
func _start_lightning() -> void:
	var flash := ColorRect.new()
	flash.position = Vector2.ZERO
	flash.size = _vp
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(1, 1, 1, 0.0)
	add_child(flash)
	_lightning_loop(flash)

func _lightning_loop(flash: ColorRect) -> void:
	while is_instance_valid(flash) and is_inside_tree():
		await get_tree().create_timer(randf_range(3.5, 8.0)).timeout
		if not is_instance_valid(flash):
			return
		var tw := flash.create_tween()
		tw.tween_property(flash, "color:a", 0.5, 0.06)
		tw.tween_property(flash, "color:a", 0.0, 0.10)
		tw.tween_property(flash, "color:a", 0.35, 0.05)
		tw.tween_property(flash, "color:a", 0.0, 0.25)

# --- Palette helpers ----------------------------------------------------------
func _pal() -> Dictionary:
	return palette_override if not palette_override.is_empty() else ThemeManager.palette()

func _motif() -> String:
	return String(_pal().get("bg_motif", "motes"))

func _pc(key: String) -> Color:
	var c: Color = _pal().get(key, Color.MAGENTA)
	return c

func _white(a: float) -> Color:
	return Color(1, 1, 1, a)

func _saturate(c: Color) -> Color:
	var s: float = clampf(c.s * 1.25 + 0.1, 0.0, 1.0)
	var v: float = clampf(c.v * 1.05, 0.0, 1.0)
	return Color.from_hsv(c.h, s, v, 1.0)

## The theme's OWN 8·16·32 tile colours, for motifs that dress in the exact hues
## the board plays in. Sakura's ambient petals wear the board's mid pinks — the
## same three colours as the petal confetti — so every petal on screen matches.
func _tile_ramp_cols() -> Array:
	var pal := _pal()
	var cols: Array = []
	for v in [8, 16, 32]:
		cols.append(ThemeManager.tile_style_for(pal, v)["bg"])
	return cols

# --- Textures (built once per SESSION, lazily, shared by every instance) ------
# The backing vars are `static` — see the declarations at the top of the file.
# Nothing mutates the returned resource: every call site assigns it straight to a
# `texture` property or hands it to `draw_texture_rect`, so sharing one object is
# the same object graph a second build would have produced.
func _round() -> GradientTexture2D:
	if _round_tex == null:
		# A soft-falloff glow (not a linear ramp): the linear version read as a hard
		# disc with a visible circular edge once tinted — most obvious as the big
		# "dark circle" nebula clouds. Extra stops give it an organic, edgeless fade.
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55),
			Color(1, 1, 1, 0.18), Color(1, 1, 1, 0)])
		_round_tex = GradientTexture2D.new()
		_round_tex.gradient = g
		_round_tex.fill = GradientTexture2D.FILL_RADIAL
		_round_tex.fill_from = Vector2(0.5, 0.5)
		_round_tex.fill_to = Vector2(0.5, 1.0)
		_round_tex.width = 128
		_round_tex.height = 128
	return _round_tex

func _dot() -> GradientTexture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_dot_tex = GradientTexture2D.new()
		_dot_tex.gradient = g
		_dot_tex.fill = GradientTexture2D.FILL_RADIAL
		_dot_tex.fill_from = Vector2(0.5, 0.5)
		_dot_tex.fill_to = Vector2(0.5, 1.0)
		_dot_tex.width = 24
		_dot_tex.height = 24
	return _dot_tex

func _streak() -> GradientTexture2D:
	if _streak_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([
			Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		_streak_tex = GradientTexture2D.new()
		_streak_tex.gradient = g
		_streak_tex.fill = GradientTexture2D.FILL_LINEAR
		_streak_tex.fill_from = Vector2(0.5, 0.0)
		_streak_tex.fill_to = Vector2(0.5, 1.0)
		_streak_tex.width = 6
		_streak_tex.height = 64
	return _streak_tex

func _ring() -> GradientTexture2D:
	if _ring_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.62, 0.82, 1.0])
		g.colors = PackedColorArray([
			Color(1, 1, 1, 0), Color(1, 1, 1, 0),
			Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
		_ring_tex = GradientTexture2D.new()
		_ring_tex.gradient = g
		_ring_tex.fill = GradientTexture2D.FILL_RADIAL
		_ring_tex.fill_from = Vector2(0.5, 0.5)
		_ring_tex.fill_to = Vector2(0.5, 1.0)
		_ring_tex.width = 96
		_ring_tex.height = 96
	return _ring_tex

func _square() -> ImageTexture:
	if _square_tex == null:
		var img := Image.create(6, 6, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_square_tex = ImageTexture.create_from_image(img)
	return _square_tex

# --- Shaped sprites (premium motifs) ------------------------------------------
# Built per-pixel: RGB bakes the metallic shading (rim highlight, bevel, facets)
# and A is the silhouette. The particle's colour multiplies the RGB, so one white
# coin texture reads as gold or silver depending on the tint. uv runs -1..1.
func _shape(w: int, h: int, fn: Callable) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var uv := Vector2(
				float(x) / float(w - 1) * 2.0 - 1.0,
				float(y) / float(h - 1) * 2.0 - 1.0)
			var rgba: Color = fn.call(uv)
			img.set_pixelv(Vector2i(x, y), rgba)
	return ImageTexture.create_from_image(img)

# Shaped sprites are theme-independent (white/metallic masks tinted per particle at
# render time), so bake each one at most ONCE per app session and share it across
# every BoardFx instance and theme switch. The per-pixel Callable bake is costly
# (moon = 96×96 = 9,216 calls) and a fresh BoardFx is created on every gameplay
# entry — without this cache that whole cost was paid again each time, stalling the
# transition into the board.
static var _shape_cache: Dictionary = {}

func _shaped(id: String, w: int, h: int, fn: Callable) -> ImageTexture:
	var cached: ImageTexture = _shape_cache.get(id)
	if cached != null:
		return cached
	var tex := _shape(w, h, fn)
	_shape_cache[id] = tex
	return tex

func _coin() -> ImageTexture:
	if _coin_tex == null:
		_coin_tex = _shaped("coin", 28, 28, _fn_coin)
	return _coin_tex

func _snowflake() -> ImageTexture:
	return _shaped("snowflake", 36, 36, _fn_snowflake)

func _bat() -> ImageTexture:
	return _shaped("bat", 48, 30, _fn_bat)

func _raindrop() -> ImageTexture:
	return _shaped("raindrop", 6, 44, _fn_raindrop)

## A real falling drop: a long thin streak that tapers in from its tail and
## carries a slightly brighter, rounder head at the bottom.
func _fn_raindrop(uv: Vector2) -> Color:
	var ax := absf(uv.x)
	var w := 0.55 + 0.30 * smoothstep(-1.0, 1.0, uv.y)   # thin tail → fuller head
	var a := 1.0 - smoothstep(w * 0.35, w, ax)
	a *= smoothstep(-1.0, -0.55, uv.y)                   # fade in from the tail
	a *= 1.0 - smoothstep(0.82, 1.0, uv.y)               # rounded head end
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var head: float = pow(clampf(1.0 - Vector2(uv.x, (uv.y - 0.72) * 1.6).length(), 0.0, 1.0), 2.0)
	var b := clampf(0.72 + head * 0.28, 0.0, 1.0)
	return Color(b, b, b, a)

## A bold BATMAN-style bat: chunky eared body flanked by two large membrane
## wings that sweep up to pointed tips with scalloped trailing edges, staying
## fat across their span so they never read thin. Same bake as the confetti
## flock so the ambient bats and the celebration bats match.
func _fn_bat(uv: Vector2) -> Color:
	var x := absf(uv.x)
	var y := uv.y
	var a := 0.0
	var body := (1.0 - smoothstep(0.12, 0.20, x)) \
		* (1.0 - smoothstep(0.34, 0.55, absf(y - 0.06)))
	a = maxf(a, body)
	if y < -0.30 and y > -0.74:
		var ear := (1.0 - smoothstep(0.03, 0.085, absf(x - 0.095))) \
			* smoothstep(-0.74, -0.34, y)
		a = maxf(a, ear)
	if x > 0.11:
		var wx := clampf((x - 0.11) / 0.89, 0.0, 1.0)
		var tip := 1.0 - wx
		var center := -0.16 - 0.30 * wx
		var half := 0.46 * pow(clampf(tip, 0.0, 1.0), 0.55)
		var scallop := 0.13 * tip * sin(wx * PI * 3.0)
		var top_edge := center - half
		var bot_edge := center + half + scallop
		if y > top_edge and y < bot_edge:
			var soft := smoothstep(top_edge - 0.05, top_edge + 0.03, y) \
				* (1.0 - smoothstep(bot_edge - 0.04, bot_edge + 0.04, y))
			a = maxf(a, soft * (1.0 - smoothstep(0.95, 1.0, wx)))
	a = clampf(a, 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var b := clampf(0.55 + (-y) * 0.22, 0.30, 0.85)
	return Color(b, b, b, a)

## A real six-armed snow crystal: slender arms every 60° with short branchlets
## near the tips and a bright core — an actual snowflake silhouette, not a dot.
func _fn_snowflake(uv: Vector2) -> Color:
	var r := uv.length()
	if r > 1.0:
		return Color(0, 0, 0, 0)
	var ang := atan2(uv.y, uv.x)
	var sector := absf(fposmod(ang, PI / 3.0) - PI / 6.0)
	var w := 0.16 * (1.05 - r)
	var arm := (1.0 - smoothstep(w * 0.5, maxf(w, 0.001), sector)) \
		* (1.0 - smoothstep(0.85, 1.0, r))
	# Side branchlets: a thin V forking off each arm partway out.
	var br := absf(sector - 0.30 * (1.0 - r))
	var branch := (1.0 - smoothstep(0.02, 0.05, br)) \
		* smoothstep(0.30, 0.55, r) * (1.0 - smoothstep(0.75, 0.95, r))
	var core := pow(clampf(1.0 - r * 2.2, 0.0, 1.0), 1.6)
	var a := clampf(maxf(maxf(arm, branch * 0.8), core), 0.0, 1.0)
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

func _petal() -> ImageTexture:
	return _shaped("petal", 24, 36, _fn_petal)

## A soft oval petal lit from one side — tumbled by the particle's spin, it reads
## as a real falling petal instead of a round dot.
func _fn_petal(uv: Vector2) -> Color:
	var e := (uv.x * uv.x) / 0.30 + (uv.y * uv.y) / 0.95
	var a := 1.0 - smoothstep(0.9, 1.06, e)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var b := clampf(0.72 + (-uv.x) * 0.2, 0.0, 1.0)
	return Color(b, b, b, a)

func _ingot() -> ImageTexture:
	if _ingot_tex == null:
		_ingot_tex = _shaped("ingot", 34, 22, _fn_ingot)
	return _ingot_tex

func _gem() -> ImageTexture:
	if _gem_tex == null:
		_gem_tex = _shaped("gem", 26, 30, _fn_gem)
	return _gem_tex

func _shard() -> ImageTexture:
	if _shard_tex == null:
		_shard_tex = _shaped("shard", 16, 40, _fn_shard)
	return _shard_tex

func _leaf() -> ImageTexture:
	if _leaf_tex == null:
		_leaf_tex = _shaped("leaf", 20, 34, _fn_leaf)
	return _leaf_tex

func _orb() -> ImageTexture:
	if _orb_tex == null:
		_orb_tex = _shaped("orb", 28, 28, _fn_orb)
	return _orb_tex

func _disc() -> ImageTexture:
	if _disc_tex == null:
		_disc_tex = _shaped("disc", 48, 48, _fn_disc)
	return _disc_tex

func _moon() -> ImageTexture:
	if _moon_tex == null:
		_moon_tex = _shaped("moon", 96, 96, _fn_moon)
	return _moon_tex

func _crescent() -> ImageTexture:
	if _crescent_tex == null:
		_crescent_tex = _shaped("crescent", 80, 80, _fn_crescent)
	return _crescent_tex

func _bubble() -> ImageTexture:
	if _bubble_tex == null:
		_bubble_tex = _shaped("bubble", 28, 28, _fn_bubble)
	return _bubble_tex

func _fn_bubble(uv: Vector2) -> Color:
	# A realistic bubble: a bright thin rim, a small specular highlight in the upper
	# left, and a very faint interior fill — a transparent sphere catching the light.
	var r := uv.length()
	if r > 1.0:
		return Color(0, 0, 0, 0)
	var rim := smoothstep(0.72, 0.90, r) * (1.0 - smoothstep(0.94, 1.0, r))
	var hi: float = pow(clampf(1.0 - (uv - Vector2(-0.34, -0.34)).length() * 1.4, 0.0, 1.0), 3.0)
	var fill := (1.0 - smoothstep(0.0, 0.94, r)) * 0.05
	var a := clampf(rim * 0.9 + hi * 0.9 + fill, 0.0, 1.0)
	return Color(1, 1, 1, a)

func _lantern() -> ImageTexture:
	if _lantern_tex == null:
		_lantern_tex = _shaped("lantern", 48, 68, _fn_lantern)
	return _lantern_tex

## A REAL paper lantern: a barrel-shaped body (fullest at the middle, tucked at the
## rings) lit from the flame just below its centre — a hot core cooling toward the
## paper edges — with bamboo rib hoops, faint vertical seams, a dark cap on top, a
## dark bottom ring and a hanging tassel. RGB bakes the shading; A is the
## silhouette. Tinted warm by the particle.
func _fn_lantern(uv: Vector2) -> Color:
	var x := uv.x
	var y := uv.y
	var a := 0.0
	# Body — barrel silhouette: bulges at the waist, tucks in toward both rings.
	var yy := clampf((y + 0.04) / 0.78, -1.0, 1.0)
	var bulge := 0.56 + 0.16 * cos(yy * PI * 0.9)
	var bx := absf(x) / maxf(bulge, 0.2)
	var by := absf(y + 0.04) / 0.78
	var body := pow(bx, 3.0) + pow(by, 4.0)
	if body < 1.05:
		a = 1.0 - smoothstep(0.85, 1.02, body)
	# Cap, bottom ring, tassel — the dark bamboo fittings that sell the shape.
	var dark := false
	if absf(x) < 0.28 and y < -0.78 and y > -0.96:
		a = maxf(a, 1.0)
		dark = true
	if absf(x) < 0.24 and y > 0.70 and y < 0.82:
		a = maxf(a, 1.0)
		dark = true
	if absf(x) < 0.05 and y > 0.82 and y < 0.995:
		a = maxf(a, 0.9)   # tassel — warm, not dark: it catches the glow
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	if dark:
		return Color(0.2, 0.2, 0.2, a)
	# Lit from within: the flame sits just below centre, paper cooling toward edges.
	var flame := clampf(1.0 - Vector2(x * 1.45, (y - 0.12) * 1.1).length(), 0.0, 1.0)
	var b := 0.34 + pow(flame, 1.4) * 0.72
	# Paper texture: horizontal bamboo rib hoops + faint vertical seams.
	b *= 0.86 + 0.14 * cos((y + 0.04) * PI * 4.5)
	b *= 0.94 + 0.06 * cos(x * PI * 2.5)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A single bright soft sunbeam slanting down from a top corner (Ocean surface light).
func _sunbeam_corner(tint: Color) -> void:
	var beam := TextureRect.new()
	beam.texture = _round()
	beam.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	beam.stretch_mode = TextureRect.STRETCH_SCALE
	beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w: float = _vp.x * 0.5
	var h: float = _vp.y * 1.5
	beam.size = Vector2(w, h)
	beam.pivot_offset = Vector2(w * 0.5, 0.0)
	beam.rotation = deg_to_rad(26.0)                 # slant in from the top-right
	beam.position = Vector2(_vp.x * 0.8 - w * 0.5, -_vp.y * 0.15)
	beam.modulate = Color(tint.r, tint.g, tint.b, 0.08)
	add_child(beam)
	var tw := beam.create_tween().set_loops()
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(beam, "modulate:a", 0.18, 5.0)
	tw.tween_property(beam, "modulate:a", 0.08, 5.5)

func _balloon() -> ImageTexture:
	if _balloon_tex == null:
		_balloon_tex = _shaped("balloon", 26, 34, _fn_balloon)
	return _balloon_tex

func _heart() -> ImageTexture:
	if _heart_tex == null:
		_heart_tex = _shaped("heart", 30, 28, _fn_heart)
	return _heart_tex

func _sparkle() -> ImageTexture:
	if _sparkle_tex == null:
		_sparkle_tex = _shaped("sparkle", 24, 24, _fn_sparkle)
	return _sparkle_tex

## A 4-point "kirakira" star: a bright core with four rays tapering to points along
## the axes. A is the star silhouette; tinted by the particle colour.
func _fn_sparkle(uv: Vector2) -> Color:
	var ax := absf(uv.x)
	var ay := absf(uv.y)
	var core := pow(clampf(1.0 - uv.length() * 1.5, 0.0, 1.0), 1.8)
	var hray := clampf(1.0 - ay / (0.14 * (1.0 - ax) + 0.02), 0.0, 1.0)
	var vray := clampf(1.0 - ax / (0.14 * (1.0 - ay) + 0.02), 0.0, 1.0)
	var a := clampf(core + hray * 0.8 + vray * 0.8, 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

func _fn_coin(uv: Vector2) -> Color:
	var r := uv.length()
	var a := 1.0 - smoothstep(0.86, 1.0, r)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var rim := smoothstep(0.55, 0.9, r) * (1.0 - smoothstep(0.92, 1.0, r))
	var spec: float = pow(clampf(1.0 - (uv - Vector2(-0.32, -0.32)).length(), 0.0, 1.0), 2.2)
	var b := clampf(0.50 + rim * 0.45 + spec * 0.6, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_ingot(uv: Vector2) -> Color:
	# Rounded-box silhouette with a beveled top face (top-left catches the light).
	var q := Vector2(absf(uv.x) - 0.74, absf(uv.y) - 0.5)
	var d: float = Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - 0.16
	var a := 1.0 - smoothstep(-0.05, 0.05, d)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var bevel := clampf(0.52 + (-uv.y) * 0.34 + (-uv.x) * 0.12, 0.2, 1.0)
	var strip := (1.0 - smoothstep(0.0, 0.45, absf(uv.y + 0.42))) * 0.22
	var b := clampf(bevel + strip, 0.0, 1.0)
	return Color(b, b, b, a)

## A round brilliant, seen from the side and a little above: the octagonal
## TABLE across the top, the crown facets falling away from it to the girdle,
## and the pavilion converging on a culet. Baked in near-white with a faint
## spectral fringe on two facets — dispersion is the whole difference between a
## diamond and a piece of glass, and no amount of white sparkle supplies it.
##
## Diamond Rain drifted the generic `_gem()` before this: a four-quadrant rhombus
## with one bright half and one dark half, which at fall size read as a grey
## square. The read of a cut stone is FACET COUNT and the hard step in
## brightness between neighbouring facets, so this bake spends its pixels on
## that and nothing else.
func _brilliant() -> ImageTexture:
	return _shaped("brilliant", 40, 44, _fn_brilliant)

func _fn_brilliant(uv: Vector2) -> Color:
	const AR := 1.1       # bake 40x44
	var sy := uv.y * AR
	# --- silhouette: table edge at sy = -0.86, girdle at -0.16, culet at 1.04.
	var half := 0.0
	if sy >= -0.90 and sy < -0.16:
		half = lerpf(0.46, 0.94, (sy + 0.90) / 0.74)
	elif sy >= -0.16 and sy <= 1.04:
		half = 0.94 * (1.0 - pow((sy + 0.16) / 1.20, 0.92))
	if half <= 0.0:
		return Color(0, 0, 0, 0)
	var a: float = 1.0 - smoothstep(half - 0.07, half, absf(uv.x))
	# The halo: the stone is throwing light, so its edge is not a cut line.
	var gr: float = Vector2(uv.x * 0.86, sy * 0.72).length()
	var halo: float = pow(clampf(1.0 - gr, 0.0, 1.0), 2.6) * 0.30
	var b := 0.5
	var tint := Color(1, 1, 1)
	if sy < -0.78:
		# The table: the flat top, and the brightest face on the stone.
		b = 0.97
	elif sy < -0.16:
		# The crown: eight facets alternating bright and dim across the width,
		# with the star facets catching a spectral edge.
		var ci: float = fposmod(floorf((uv.x + 0.94) / 0.235), 2.0)
		b = 0.88 if ci < 0.5 else 0.60
		b += (1.0 - smoothstep(0.0, 0.10, absf(sy + 0.20))) * 0.25   # girdle flash
		if uv.x < -0.45:
			tint = Color(0.80, 0.94, 1.00)                            # blue fire
		elif uv.x > 0.50:
			tint = Color(1.00, 0.90, 0.96)                            # rose fire
	else:
		# The pavilion: facets radiating from the culet, so they converge as
		# they go down instead of staying parallel.
		var down: float = (sy + 0.16) / 1.20
		var across: float = uv.x / maxf(half, 0.001)
		var pi_: float = fposmod(floorf((across + 1.0) * 2.6), 2.0)
		b = 0.74 if pi_ < 0.5 else 0.30
		b -= down * 0.20
		# The culet reflects the table straight back up the stone.
		b += pow(clampf(down - 0.62, 0.0, 1.0) / 0.38, 2.0) * 0.55
		if across < -0.30 and pi_ < 0.5:
			tint = Color(0.82, 1.00, 0.94)                            # green fire
	# The girdle itself: a hard bright line all the way round the widest point.
	b += (1.0 - smoothstep(0.0, 0.055, absf(sy + 0.16))) * 0.35
	b = clampf(b, 0.0, 1.0)
	var col: Color = Color(b, b, b) * tint
	var out: float = clampf(maxf(a, halo), 0.0, 1.0)
	if out <= 0.015:
		return Color(0, 0, 0, 0)
	if a <= 0.02:
		return Color(0.72, 0.88, 1.0, out)
	return Color(col.r, col.g, col.b, out)

func _fn_gem(uv: Vector2) -> Color:
	var m := absf(uv.x) + absf(uv.y)
	var a := 1.0 - smoothstep(0.92, 1.05, m)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	# Four facets at different brightness so it reads as cut, plus a centre sparkle.
	var b := 0.5
	if uv.y < 0.0:
		b = 0.94 if uv.x < 0.0 else 0.78
	else:
		b = 0.62 if uv.x < 0.0 else 0.42
	b += pow(clampf(1.0 - m, 0.0, 1.0), 3.0) * 0.3
	b = clampf(b, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_shard(uv: Vector2) -> Color:
	# Tall thin rhombus — an ice sliver with a bright central spine.
	var m := absf(uv.x) * 2.6 + absf(uv.y)
	var a := 1.0 - smoothstep(0.9, 1.06, m)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var b := clampf(0.55 + (1.0 - absf(uv.x) * 2.6) * 0.4, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_leaf(uv: Vector2) -> Color:
	# Pointed almond/leaf with a faint central vein.
	var e := (uv.x * uv.x) / 0.26 + (uv.y * uv.y) / 0.95
	var a := 1.0 - smoothstep(0.9, 1.06, e)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var vein := (1.0 - smoothstep(0.0, 0.07, absf(uv.x))) * 0.2
	var b := clampf(0.5 + (-uv.x) * 0.18 + vein, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_orb(uv: Vector2) -> Color:
	# Ghostly orb: bright rim, translucent hollow core.
	var r := uv.length()
	if r > 1.0:
		return Color(0, 0, 0, 0)
	var ring := smoothstep(0.4, 0.85, r) * (1.0 - smoothstep(0.9, 1.0, r))
	var core := (1.0 - smoothstep(0.0, 0.6, r)) * 0.4
	var a := clampf(ring * 0.85 + core, 0.0, 1.0)
	return Color(0.9, 0.9, 0.9, a)

func _fn_disc(uv: Vector2) -> Color:
	# A clean solid disc (the sun): soft edge, the top a touch brighter.
	var r := uv.length()
	var a := 1.0 - smoothstep(0.94, 1.0, r)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var b := clampf(0.78 + (-uv.y) * 0.22 - smoothstep(0.6, 1.0, r) * 0.12, 0.4, 1.0)
	return Color(b, b, b, a)

func _fn_moon(uv: Vector2) -> Color:
	# A textured moon SPHERE: directional light from the upper-left (so it curves away
	# into shadow), strong limb darkening at the edge, and several maria / craters of
	# varying depth — so it reads as a real cratered moon, not a flat disc.
	var r := uv.length()
	var a := 1.0 - smoothstep(0.97, 1.0, r)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var z := sqrt(clampf(1.0 - r * r, 0.0, 1.0))                    # sphere normal.z
	var nl := clampf(-0.42 * uv.x - 0.5 * uv.y + 0.75 * z, 0.0, 1.0)  # dot(N, light)
	var b := 0.26 + 0.82 * nl
	b -= (1.0 - smoothstep(0.0, 0.34, (uv - Vector2(-0.28, -0.18)).length())) * 0.20
	b -= (1.0 - smoothstep(0.0, 0.24, (uv - Vector2(0.28, 0.26)).length())) * 0.16
	b -= (1.0 - smoothstep(0.0, 0.16, (uv - Vector2(0.05, -0.38)).length())) * 0.13
	b -= (1.0 - smoothstep(0.0, 0.13, (uv - Vector2(-0.38, 0.30)).length())) * 0.11
	b -= (1.0 - smoothstep(0.0, 0.10, (uv - Vector2(0.42, -0.12)).length())) * 0.09
	b = clampf(b, 0.05, 1.0)
	return Color(b, b, b, a)

func _fn_crescent(uv: Vector2) -> Color:
	# A crescent moon: the full disc with an offset disc carved out of it, brighter
	# along the lit outer rim. Tinted by the sprite colour.
	var r := uv.length()
	var outer := 1.0 - smoothstep(0.93, 1.0, r)
	var rc := (uv - Vector2(0.40, -0.20)).length()          # the carving disc
	var carved := smoothstep(0.66, 0.76, rc)                # 1 outside carve, 0 inside
	var a := outer * carved
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var b := clampf(0.72 + r * 0.30, 0.5, 1.0)              # brighter toward the rim
	return Color(b, b, b, a)

func _fn_balloon(uv: Vector2) -> Color:
	# A teardrop balloon: rounded body with a small knot at the bottom + a glossy
	# highlight. Tinted by the particle colour.
	var e := (uv.x * uv.x) / 0.62 + ((uv.y + 0.06) * (uv.y + 0.06)) / 0.92
	var a := 1.0 - smoothstep(0.92, 1.04, e)
	var knot := 1.0 - smoothstep(0.0, 0.13, Vector2(uv.x, uv.y - 0.92).length())
	a = maxf(a, knot)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var hi: float = pow(clampf(1.0 - (uv - Vector2(-0.32, -0.40)).length(), 0.0, 1.0), 1.8) * 0.5
	var b := clampf(0.60 + hi - smoothstep(0.4, 1.0, e) * 0.12, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_heart(uv: Vector2) -> Color:
	# Implicit heart curve (lobes up, point down) with a glossy highlight.
	var x := uv.x * 1.4
	var y := -uv.y * 1.4
	var t := x * x + y * y - 1.0
	var f := t * t * t - x * x * y * y * y
	var a := 1.0 - smoothstep(-0.06, 0.06, f)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var hi: float = pow(clampf(1.0 - (uv - Vector2(-0.28, -0.34)).length(), 0.0, 1.0), 1.6) * 0.4
	var b := clampf(0.70 + hi, 0.0, 1.0)
	return Color(b, b, b, a)

## A SEA PEN: the real animal — a curved central rachis carrying paired rows of
## polyp-bearing branchlets, a feather standing in the mud. Its light lives in
## the polyps out along the branch tips, which is why the plume glows and the
## shaft stays dark.
##
## The body is baked near-black (b ~= 0.05) on purpose. Every sprite here is
## tinted by ONE modulate colour, so a shape drawn as bright line-work comes out
## as neon strip-lighting — which is exactly what the first grove looked like. A
## dark body carrying its own points of light is how deep-sea footage reads, and
## it is the difference between an organism and a sign.
func _fn_bio_pen(uv: Vector2) -> Color:
	const AR := 1.625     # bake 128x208
	var sy := uv.y * AR
	var body := 0.0       # the light-swallowing colony
	var lit := 0.0        # the polyps
	var glow := 0.0
	var t := clampf((1.0 - uv.y) * 0.5, 0.0, 1.0)      # 0 at the root, 1 at the tip
	var cx: float = 0.42 * sin(t * 2.5) * pow(t, 0.9)  # the curve of the rachis
	var aq := absf(uv.x - cx)                          # how far out along a rib
	var hw: float = lerpf(0.075, 0.014, pow(t, 0.55))
	if t < 0.99:
		body = maxf(body, 1.0 - smoothstep(hw * 0.6, hw, aq))
		lit = maxf(lit, (1.0 - smoothstep(hw * 0.15, hw * 0.7, aq)) * (0.08 + 0.18 * t))
	# The plume, solved as a FIELD rather than as a set of line segments.
	#
	# A rib leaves the shaft and climbs as it goes out, so every point in the
	# plume belongs to the rib rooted at `t0` — its own height minus the climb it
	# has made on the way out (the quadratic term curves each rib upward). That
	# makes the whole feather one closed-form expression: no loop over ribs, one
	# distance per pixel. The first attempt DID loop, over the two nearest rib
	# indices, and drew almost nothing: a rib is four indices long at this slope,
	# so every pixel more than one index from its own root fell outside the test.
	const SLOPE := 0.205
	const RIBS := 17.0
	var t0: float = t - SLOPE * aq - 0.11 * aq * aq
	if t0 > 0.06 and t0 < 0.99:
		var rn: float = floorf(t0 * RIBS)
		var vary: float = 0.86 + 0.14 * sin(rn * 2.399)   # no two ribs the same length
		# The plume rides the UPPER colony: a sea pen has a bare peduncle under it,
		# and a plume that reaches the mud draws a Christmas tree.
		var plume: float = smoothstep(0.24, 0.50, t0) * (1.0 - smoothstep(0.64, 1.0, t0))
		var span: float = (0.10 + 0.66 * plume) * vary
		var outer: float = aq / maxf(span, 0.001)
		if outer < 1.06:
			var dph := absf(fposmod(t0 * RIBS, 1.0) - 0.5)
			const WID := 0.17
			var rib: float = 1.0 - smoothstep(WID * 0.5, WID, dph)
			var soft: float = 1.0 - smoothstep(WID, WID * 2.4, dph)
			var edge: float = 1.0 - smoothstep(0.88, 1.04, outer)
			body = maxf(body, rib * 0.72 * edge)
			# The polyps: the light lives out along the branch, so the plume
			# glows and the shaft stays dark.
			var pol: float = 1.0 - smoothstep(0.0, 0.36,
				absf(fposmod(outer * 9.0, 1.0) - 0.5))
			var wide: float = 1.0 - smoothstep(WID * 0.75, WID * 1.35, dph)
			lit = maxf(lit, wide * smoothstep(0.14, 0.90, outer) * edge
				* (0.66 + 0.34 * pol))
			glow = maxf(glow, soft * smoothstep(0.12, 1.0, outer) * edge * 0.62)
	# The peduncle: the bulb that anchors it, buried in the sediment.
	var pd: float = Vector2(uv.x / 0.16, (sy - AR * 0.94) / 0.22).length()
	body = maxf(body, 1.0 - smoothstep(0.75, 1.0, pd))
	var a := clampf(maxf(body * 0.78, maxf(lit, glow * 0.6)), 0.0, 1.0)
	if a <= 0.015:
		return Color(0, 0, 0, 0)
	var b := clampf(0.05 + lit * 0.95 + glow * 0.22, 0.0, 1.0)
	return Color(b, b, b, a)

## A gorgonian fan rooted in the sediment: a dark holdfast with a crown of
## branches radiating up and out, lit at the tips where the polyps sit. Leaned a
## few degrees off vertical, because a perfectly symmetric fan reads as a
## sunburst icon, and thinned toward the outside so the silhouette breaks up.
func _fn_bio_fan(uv: Vector2) -> Color:
	const AR := 0.787      # bake 150x118
	var sy := uv.y * AR
	var p := Vector2(uv.x, sy - AR)      # rooted at the bottom centre
	var r := p.length()
	var body := 0.0
	var lit := 0.0
	var glow := 0.0
	if p.y <= 0.02 and r < 1.10:
		# The lean, applied to the polar angle only, so the root stays put.
		const LEAN := 0.22
		var pr := Vector2(p.x * cos(LEAN) - p.y * sin(LEAN),
			p.x * sin(LEAN) + p.y * cos(LEAN))
		var ang := atan2(-pr.y, pr.x)
		# Two branch generations: the coarse split, and a finer one over it, so
		# the fan is a colony rather than a comb.
		var coarse: float = pow(clampf(0.5 + 0.5 * sin(ang * 7.0), 0.0, 1.0), 2.6)
		var fine: float = pow(clampf(0.5 + 0.5 * sin(ang * 13.0 + 1.1), 0.0, 1.0), 5.0)
		var spoke: float = maxf(coarse, fine * smoothstep(0.50, 0.92, r) * 0.55)
		var env: float = smoothstep(0.06, 0.30, r) * (1.0 - smoothstep(0.70, 1.06, r))
		body = maxf(body, spoke * env * 0.85)
		lit = maxf(lit, pow(spoke, 1.7) * smoothstep(0.42, 0.96, r)
			* (1.0 - smoothstep(0.88, 1.06, r)) * 0.9)
		glow = maxf(glow, spoke * env * 0.45)
	# The holdfast: a dark bulb with a faintly lit collar.
	body = maxf(body, 1.0 - smoothstep(0.16, 0.26, r))
	# ...an ARC of a collar, not a ring: a full circle draws a hoop lying in the
	# mud, and half of it would be buried anyway.
	if p.y < 0.0:
		lit = maxf(lit, (1.0 - smoothstep(0.02, 0.09, absf(r - 0.22))) * 0.40
			* smoothstep(0.0, 0.10, -p.y))
	glow = maxf(glow, (1.0 - smoothstep(0.05, 0.48, r)) * 0.40)
	var a := clampf(maxf(body * 0.92, maxf(lit, glow * 0.55)), 0.0, 1.0)
	if a <= 0.015:
		return Color(0, 0, 0, 0)
	var b := clampf(0.06 + lit * 0.94 + glow * 0.18, 0.0, 1.0)
	return Color(b, b, b, a)

## A siphonophore: a colony hanging as a chain of lit bodies on a fine stem,
## widest a third of the way down and tapering to nothing. Irregular by design —
## evenly spaced beads on a straight line draw a zipper, which is what the first
## pass drew.
func _fn_bio_chain(uv: Vector2) -> Color:
	const AR := 4.667      # bake 48x224
	var sy := uv.y * AR
	var lit := 0.0
	var glow := 0.0
	var t := clampf((uv.y + 1.0) * 0.5, 0.0, 1.0)      # 0 at the float, 1 at the tip
	var cx: float = 0.72 * sin(t * 3.4) * pow(t, 0.8)
	var stem := absf(uv.x - cx)
	var taper: float = smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(0.86, 1.0, t))
	lit = maxf(lit, (1.0 - smoothstep(0.03, 0.11, stem)) * 0.30 * taper)
	# The zooids: bodies strung down the chain, crowded near the top.
	var seg: float = fposmod(t * 15.0, 1.0)
	var node: float = 1.0 - smoothstep(0.0, 0.28, absf(seg - 0.5))
	var nd: float = Vector2(uv.x - cx, (seg - 0.5) * (AR * 2.0 / 15.0)).length()
	var swell: float = 0.055 + 0.055 * (1.0 - smoothstep(0.0, 0.55, t))
	lit = maxf(lit, node * (1.0 - smoothstep(swell * 0.5, swell, nd)) * taper)
	glow = maxf(glow, node * (1.0 - smoothstep(swell, swell * 4.0, nd)) * 0.6 * taper)
	# The nectophore at the head: the float the whole colony hangs from.
	var fd: float = Vector2(uv.x / 0.55, (sy + AR * 0.93) / 0.30).length()
	lit = maxf(lit, (1.0 - smoothstep(0.55, 1.0, fd)) * 0.7)
	glow = maxf(glow, (1.0 - smoothstep(0.4, 2.2, fd)) * 0.5)
	var a := clampf(maxf(lit, glow * 0.55), 0.0, 1.0)
	if a <= 0.015:
		return Color(0, 0, 0, 0)
	var b := clampf(0.16 + lit * 0.84, 0.0, 1.0)
	return Color(b, b, b, a)

## A comb jelly: a near-invisible ovoid rowed along by eight bands of fused
## cilia. Only the combs read — the body is 95% water — plus the two long
## trailing tentacles it fishes with.
func _fn_bio_comb(uv: Vector2) -> Color:
	const AR := 1.447      # bake 76x110
	var sy := uv.y * AR
	var veil := 0.0
	var lit := 0.0
	var glow := 0.0
	var e := Vector2(uv.x / 0.72, (sy + 0.34) / (AR * 0.80))
	var er := e.length()
	if er < 1.12:
		veil = maxf(veil, (1.0 - smoothstep(0.72, 1.04, er)) * 0.20)
		lit = maxf(lit, (1.0 - smoothstep(0.02, 0.10, absf(er - 0.97))) * 0.28)
		# Four of the eight comb rows face us: plates of light down each band.
		for k_v in [-0.52, -0.19, 0.19, 0.52]:
			var k: float = k_v
			var rx: float = k * 0.70
			var plate: float = 1.0 - smoothstep(0.0, 0.30,
				absf(fposmod(sy * 11.0 + k * 3.0, 1.0) - 0.5))
			var dd := absf(uv.x - rx)
			var on: float = (1.0 - smoothstep(0.60, 1.02, er)) * plate
			lit = maxf(lit, (1.0 - smoothstep(0.018, 0.055, dd)) * on * 0.95)
			glow = maxf(glow, (1.0 - smoothstep(0.03, 0.16, dd)) * on * 0.5)
	# The two fishing tentacles, trailing well past the body.
	if sy > 0.20:
		for t_v in [-0.34, 0.30]:
			var tx: float = t_v
			var wig: float = tx + 0.16 * sin(sy * 3.3 + tx * 9.0)
			lit = maxf(lit, (1.0 - smoothstep(0.004, 0.016, absf(uv.x - wig)))
				* 0.34 * (1.0 - smoothstep(0.9, 1.5, sy)))
	var a := clampf(maxf(veil, maxf(lit, glow * 0.5)), 0.0, 1.0)
	if a <= 0.015:
		return Color(0, 0, 0, 0)
	var b := clampf(0.18 + lit * 0.82, 0.0, 1.0)
	return Color(b, b, b, a)

## The sediment bank: an irregular dark ridge whose crest catches a little of the
## grove's light. Tinted with the WATER rather than the light at the call site —
## mud does not glow, and a bank painted in the accent reads as another plant.
func _fn_bio_floor(uv: Vector2) -> Color:
	var crest := -0.06
	crest -= 0.40 * exp(-pow((uv.x + 0.66) * 2.1, 2.0))
	crest -= 0.24 * exp(-pow((uv.x - 0.06) * 2.9, 2.0))
	crest -= 0.34 * exp(-pow((uv.x - 0.78) * 2.3, 2.0))
	crest += 0.05 * sin(uv.x * 6.0) + 0.025 * sin(uv.x * 17.0)
	var below := uv.y - crest        # >0 = inside the bank
	if below < -0.02:
		return Color(0, 0, 0, 0)
	var a: float = smoothstep(-0.02, 0.05, below)
	# The crest catches the light standing above it; the body of the bank does not.
	var rim: float = 1.0 - smoothstep(0.0, 0.20, below)
	var b: float = 0.04 + rim * 0.40
	return Color(b, b, b, clampf(a, 0.0, 1.0) * 0.95)

## A seed-sprite: a bright core with a corona of fine filaments radiating out,
## like a lit dandelion clock adrift in the water.
func _fn_seed_sprite(uv: Vector2) -> Color:
	var r := uv.length()
	if r > 1.0:
		return Color(0, 0, 0, 0)
	var ang := atan2(uv.y, uv.x)
	# Filaments: bright spokes that fade toward their tips.
	var spoke: float = 0.5 + 0.5 * sin(ang * 11.0)
	var fil: float = pow(spoke, 3.0) * (1.0 - smoothstep(0.15, 1.0, r))
	# The core.
	var core: float = 1.0 - smoothstep(0.03, 0.20, r)
	var a := clampf(core + fil * 0.7, 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var b := clampf(0.55 + core * 0.45 + fil * 0.3, 0.0, 1.0)
	return Color(b, b, b, a)

## A small lit fish, nose to the right: a leaf-shaped body with a forked tail,
## a bright lateral line and a dark eye.
func _fn_lit_fish(uv: Vector2) -> Color:
	var a := 0.0
	var b := 0.6
	# Body: a lens shape, fullest just behind the head.
	var body: float = 1.0 - smoothstep(0.72, 1.0,
		Vector2(uv.x * 0.72, uv.y * 1.7 / (1.0 - 0.25 * uv.x)).length())
	if uv.x > -0.62:
		a = body
	# Tail: a wedge behind the body, notched at the back.
	if uv.x <= -0.44:
		var t := (-uv.x - 0.44) / 0.56
		var hh := lerpf(0.12, 0.78, t)
		var notch: float = smoothstep(0.0, 0.5, absf(uv.y) / maxf(hh, 0.001) - (1.0 - t * 0.7))
		a = maxf(a, (1.0 - smoothstep(hh * 0.5, hh, absf(uv.y))) * (1.0 - notch * 0.9))
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# The lateral line: a bright stripe down the flank.
	b += (1.0 - smoothstep(0.0, 0.16, absf(uv.y))) * 0.45
	# The eye.
	if Vector2(uv.x - 0.52, uv.y + 0.08).length() < 0.13:
		b = 0.12
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0),
		clampf(a, 0.0, 1.0))

## A far shoreline ridge: overlapping hills of different heights with a couple
## of real peaks, plus a fringe of conifers along the crest so it reads as a
## wooded island rather than a smooth hump.
func _fn_ridge(uv: Vector2) -> Color:
	# Crest height as a function of x, in the bake's -1..1 space.
	var x := uv.x
	var crest: float = 0.34
	crest -= 0.55 * exp(-pow((x + 0.55) * 2.6, 2.0))     # the tall peak, left
	crest -= 0.34 * exp(-pow((x - 0.10) * 3.4, 2.0))     # a shoulder
	crest -= 0.46 * exp(-pow((x - 0.72) * 2.9, 2.0))     # the point, right
	crest += 0.05 * sin(x * 9.0) + 0.03 * sin(x * 23.0)  # broken ground
	# Conifers: a saw of little triangles standing on the crest line.
	var tooth: float = absf(fposmod(x * 46.0, 1.0) - 0.5) * 2.0
	var tree: float = 0.055 * (1.0 - tooth)
	if uv.y < crest - tree:
		return Color(0, 0, 0, 0)
	var a: float = 1.0 if uv.y >= crest else smoothstep(crest - tree, crest, uv.y)
	return Color(1, 1, 1, clampf(a, 0.0, 1.0))

## A ball-top joystick, seen head on: the sphere, the shaft under it and the
## dust washer it sits in. The ball is a real sphere on screen — see the ASPECT
## NOTE; getting this metric wrong is what made it read as a wine glass.
func _fn_joystick(uv: Vector2) -> Color:
	const AR := 1.71      # bake 56x96, drawn at h = 1.71 * w
	var a := 0.0
	var b := 0.7
	# The ball: screen-radius 0.60 of the bake's half-width.
	var cy := -0.62
	var ball := Vector2(uv.x, (uv.y - cy) * AR)
	var br := ball.length() / 0.60
	if br < 1.0:
		a = 1.0 - smoothstep(0.92, 1.0, br)
		b = lerpf(0.30, 1.0, clampf(0.60 - ball.x * 0.62 - ball.y * 0.62, 0.0, 1.0))
	# The shaft.
	if uv.y > cy and uv.y < 0.70 and absf(uv.x) < 0.15:
		var sh := 1.0 - smoothstep(0.10, 0.15, absf(uv.x))
		if sh > a:
			a = sh
			b = 0.40 + 0.45 * (1.0 - absf(uv.x) / 0.15)
	# The dust washer: a FLAT DISC lying on the panel, seen almost edge on — an
	# ellipse, not a taper. A taper here is what read as the stem and foot of a
	# wine glass rather than as a joystick sitting in its plate.
	var wd := Vector2((uv.x) / 0.78, (uv.y - 0.80) * AR / 0.30)
	if wd.length() < 1.0:
		var wa := 1.0 - smoothstep(0.90, 1.0, wd.length())
		if wa > a:
			a = wa
			# Domed rubber: brighter at the near edge, darker toward the rim.
			b = lerpf(0.46, 0.20, clampf(wd.length(), 0.0, 1.0))
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0),
		clampf(a, 0.0, 1.0))

## An upright arcade cabinet seen from the front: a marquee head, a recessed
## screen bezel, a sloped control panel and a coin door, with the side panels
## tapering the way a real cab's do. Shaded, so the tint reads as moulded
## plastic rather than a flat card.
func _fn_arcade_cab(uv: Vector2) -> Color:
	var a := 0.0
	var b := 0.5
	# The body: full width at the head, a slight waist at the panel, a plinth.
	var hw := 0.92
	if uv.y > 0.12:
		hw = 0.86
	if uv.y > 0.62:
		hw = 0.94
	if absf(uv.x) > hw:
		return Color(0, 0, 0, 0)
	a = 1.0
	# Vertical moulding: lighter down the middle, darker at the side panels.
	b = lerpf(0.72, 0.34, absf(uv.x) / hw)
	# A dark seam down both outside edges, so a row of these reads as separate
	# machines standing side by side rather than as one continuous shelf.
	b *= smoothstep(0.86, 0.97, 1.0 - absf(uv.x) / hw) * 0.55 + 0.45
	# The marquee head: a lit panel set into a dark hood, inset from the sides.
	if uv.y < -0.78:
		b = 0.20
		if uv.y > -0.95 and absf(uv.x) < 0.74:
			b = 0.88
	# The screen recess — dark, because the glow is a separate lit node.
	if uv.y > -0.72 and uv.y < -0.28 and absf(uv.x) < 0.72:
		b = 0.10
	# The bezel around it.
	if uv.y > -0.76 and uv.y < -0.24 and absf(uv.x) < 0.78 and b > 0.10:
		b = 0.22
	# The control panel, angled toward the player.
	if uv.y > -0.16 and uv.y < 0.10:
		b = lerpf(0.62, 0.30, (uv.y + 0.16) / 0.26)
	# The coin door.
	if uv.y > 0.30 and uv.y < 0.48 and absf(uv.x) < 0.30:
		b = 0.20
	# The plinth in shadow at the floor.
	if uv.y > 0.86:
		b = 0.14
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## Neon tubing, three shapes. Each is a soft-cored glowing line: a bright thin
## filament with a wide halo, which is what makes bent glass read as neon.
func _fn_neon_zig(uv: Vector2) -> Color:
	var pts := [Vector2(-0.80, 0.55), Vector2(-0.30, -0.55), Vector2(0.20, 0.35),
		Vector2(0.78, -0.60)]
	return _neon_from(uv, pts, false)

func _fn_neon_bolt(uv: Vector2) -> Color:
	var pts := [Vector2(0.10, -0.85), Vector2(-0.40, 0.02), Vector2(0.05, 0.02),
		Vector2(-0.20, 0.86)]
	return _neon_from(uv, pts, false)

## An arc of tube — a ring with a quarter missing, the classic bent sign blank.
func _fn_neon_arc(uv: Vector2) -> Color:
	var r := uv.length()
	var ang := atan2(uv.y, uv.x)
	if ang > -0.5 and ang < 0.5:
		return Color(0, 0, 0, 0)
	var d := absf(r - 0.66)
	var core: float = 1.0 - smoothstep(0.02, 0.06, d)
	var halo: float = 1.0 - smoothstep(0.06, 0.30, d)
	var a := clampf(core + halo * 0.45, 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var b := clampf(0.45 + core * 0.55, 0.0, 1.0)
	return Color(b, b, b, a)

## Shared body for the polyline neon shapes: distance to the run, cored+haloed.
func _neon_from(uv: Vector2, pts: Array, closed: bool) -> Color:
	var d := 1e9
	var n := pts.size()
	for i in range(n - 1):
		d = minf(d, _seg_dist(uv, pts[i], pts[i + 1]))
	if closed and n > 1:
		d = minf(d, _seg_dist(uv, pts[n - 1], pts[0]))
	var core: float = 1.0 - smoothstep(0.02, 0.06, d)
	var halo: float = 1.0 - smoothstep(0.06, 0.32, d)
	var a := clampf(core + halo * 0.42, 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var b := clampf(0.45 + core * 0.55, 0.0, 1.0)
	return Color(b, b, b, a)

## A chunky arcade button: a translucent domed cap in a dark bezel, with a
## crescent highlight up top and a soft pool of light in the middle.
func _fn_arcade_button(uv: Vector2) -> Color:
	var r := uv.length()
	if r > 1.0:
		return Color(0, 0, 0, 0)
	var a := 1.0 - smoothstep(0.94, 1.0, r)
	# The bezel ring.
	if r > 0.78:
		return Color(0.22, 0.22, 0.22, a)
	# The cap: brightest where the light hits, falling off toward the rim.
	var b: float = lerpf(1.0, 0.5, smoothstep(0.0, 0.78, r))
	b = lerpf(b, 1.0, (1.0 - smoothstep(0.10, 0.34,
		Vector2(uv.x + 0.22, uv.y + 0.26).length())) * 0.8)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A bare autumn tree: a leaning trunk that forks into branches, thinning as it
## climbs. Drawn as a recursive-looking fan of tapered limbs.
func _fn_autumn_tree(uv: Vector2) -> Color:
	const AR := 1.2       # bake 200x240
	var sy := uv.y * AR
	var a := 0.0
	# The trunk: leaning right, tapering upward, with a flare at the root.
	var lean: float = 0.30 * (1.0 - clampf((sy + 1.2) / 2.4, 0.0, 1.0))
	var cx: float = -0.30 + lean
	var t := clampf((1.2 - sy) / 2.4, 0.0, 1.0)          # 0 at root, 1 at crown
	var hw: float = lerpf(0.32, 0.07, pow(t, 0.7))
	if absf(uv.x - cx) < hw:
		a = 1.0
	# Six limbs off the trunk at rising heights, each thinner than the last.
	for k in 6:
		var f := 0.30 + 0.11 * float(k)
		var root_y: float = 1.2 - f * 2.4
		var side: float = 1.0 if k % 2 == 0 else -1.0
		var root := Vector2(-0.30 + 0.30 * f, root_y)
		var tip := root + Vector2(side * (0.42 + 0.22 * f), -(0.42 + 0.20 * f))
		var d := _seg_dist(Vector2(uv.x, sy), root, tip)
		var lw: float = lerpf(0.075, 0.022, f)
		if d < lw:
			a = maxf(a, 1.0 - smoothstep(lw * 0.6, lw, d))
		# One fork off each limb, so the crown is not a set of spokes.
		var fork := tip + Vector2(side * 0.20, -0.26)
		var d2 := _seg_dist(Vector2(uv.x, sy), tip, fork)
		if d2 < lw * 0.6:
			a = maxf(a, 1.0 - smoothstep(lw * 0.35, lw * 0.6, d2))
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# Bark: vertical striations, lit down the left of the trunk.
	var b: float = 0.55 + 0.30 * (1.0 - smoothstep(0.0, 0.22, absf(uv.x - cx + 0.08)))
	b *= 0.82 + 0.18 * (0.5 + 0.5 * sin(uv.x * 34.0))
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## The canopy over those branches. Not a soft blob: a mass built from many small
## leaf CLUSTERS, so the silhouette breaks into leaves at its rim the way a real
## crown does, and the interior is dappled with the gaps light comes through.
func _fn_autumn_canopy(uv: Vector2) -> Color:
	var a := 0.0
	var lit := 0.0
	# Fourteen clusters on a rough ellipse — enough that the outline is made of
	# leaf-sized bumps rather than four big lobes.
	for k in 14:
		var fk := float(k)
		# Deterministic scatter (no RNG: this bake is shared and cached).
		var ang: float = fk * 2.399963              # the golden angle, so they spread
		var rad: float = 0.30 + 0.52 * sqrt(fposmod(fk * 0.6180339, 1.0))
		var cx: float = cos(ang) * rad * 0.98
		var cy: float = sin(ang) * rad * 0.62 - 0.06
		var rr: float = 0.20 + 0.14 * fposmod(fk * 0.7548, 1.0)
		var d := Vector2(uv.x - cx, (uv.y - cy) * 1.45).length() / rr
		# Each cluster is itself scalloped, which is what puts leaves on the rim.
		var scallop: float = 0.13 * sin(atan2(uv.y - cy, uv.x - cx) * 9.0 + fk * 2.1)
		var m: float = 1.0 - smoothstep(0.80 + scallop, 1.0 + scallop, d)
		if m > a:
			a = m
			# Clusters higher and to the left take the light; the ones below and
			# behind fall into the crown's own shade.
			lit = clampf(0.60 - cx * 0.30 - cy * 0.62, 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# Sky holes: small gaps punched through the interior, never at the rim.
	var hole: float = sin(uv.x * 13.0 + 1.7) * sin(uv.y * 15.0 - 0.6)
	a *= 1.0 - smoothstep(0.55, 0.92, hole) * 0.85
	# Leaf grain over the whole mass, so it is never a flat fill.
	var grain: float = 0.86 + 0.14 * sin(uv.x * 41.0) * sin(uv.y * 37.0)
	var b: float = lerpf(0.34, 1.0, lit) * grain
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A bell tower: a tapering stone shaft, an open belfry arch with the bell
## hanging in it, and a pitched cap.
func _fn_bell_tower(uv: Vector2) -> Color:
	const AR := 2.44      # bake 90x220
	var sy := uv.y * AR
	var a := 0.0
	var t := clampf((sy + 2.44) / 4.88, 0.0, 1.0)
	var hw: float = lerpf(0.42, 0.86, t)
	if absf(uv.x) < hw and sy > -1.72:
		a = 1.0
	# The cap: a pitched roof over the belfry.
	if sy <= -1.72 and sy > -2.30:
		var rt := (sy + 2.30) / 0.58
		if absf(uv.x) < lerpf(0.06, 0.62, rt):
			a = 1.0
	# The belfry opening: an arch cut out of the shaft.
	var arch := Vector2(uv.x / 0.26, (sy + 1.20) / 0.62)
	var open: bool = Vector2(arch.x, maxf(arch.y, 0.0)).length() < 1.0 and sy > -1.68
	if open:
		a = 0.0
		# ...with the bell hanging inside it.
		if Vector2(uv.x / 0.17, (sy + 1.16) / 0.30).length() < 1.0 and sy > -1.42:
			a = 1.0
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

## A wolf, seated in profile facing left, head raised. Proportions matter more
## than detail at this size: a seated canid is very nearly as tall as it is long,
## the chest sits FORWARD of the haunch, and the muzzle is a thin wedge off a
## small skull. Getting those three wrong is what turns it into a lump.
func _fn_wolf(uv: Vector2) -> Color:
	# Bake is square (120x120), so uv is already isotropic.
	var p := uv
	var a := 0.0
	# The haunch it is sitting on, low and to the rear.
	if Vector2((p.x - 0.30) / 0.34, (p.y - 0.45) / 0.42).length() < 1.0:
		a = 1.0
	# The chest: UPRIGHT and forward of the haunch. A seated canid is a column
	# with a lump behind it; sprawling these two apart is what read as a lunge.
	if Vector2(p.x / 0.26, (p.y - 0.20) / 0.44).length() < 1.0:
		a = 1.0
	# The back line joining chest to rump.
	if _seg_dist(p, Vector2(0.0, -0.20), Vector2(0.32, 0.10)) < 0.18:
		a = 1.0
	# The neck, short and rising almost vertically.
	if _seg_dist(p, Vector2(-0.02, -0.12), Vector2(-0.20, -0.52)) < 0.14:
		a = 1.0
	# The skull — small, and nearly over the chest, not out to the side.
	if Vector2((p.x + 0.26) / 0.16, (p.y + 0.62) / 0.14).length() < 1.0:
		a = 1.0
	# The muzzle, a short wedge angled up into the howl.
	if _seg_dist(p, Vector2(-0.34, -0.66), Vector2(-0.60, -0.80)) < 0.060:
		a = 1.0
	# One ear, laid back along the skull.
	if _in_tri(p, Vector2(-0.20, -0.70), Vector2(-0.10, -0.62), Vector2(-0.16, -0.86)):
		a = 1.0
	# The foreleg, straight down to the ground.
	if _seg_dist(p, Vector2(-0.04, 0.14), Vector2(-0.08, 0.84)) < 0.080:
		a = 1.0
	# The rear foot tucked out under the haunch.
	if _seg_dist(p, Vector2(0.16, 0.72), Vector2(0.46, 0.84)) < 0.095:
		a = 1.0
	# The tail, swept out behind and down.
	if _seg_dist(p, Vector2(0.56, 0.40), Vector2(0.86, 0.74)) < 0.080:
		a = 1.0
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

## A palm: a tall curving trunk with a small crown of fronds. The first version
## threw fronds a full bake-width from the crown, so they ran off the edge and
## the tree read as a splayed hand. A palm is mostly TRUNK — the crown spans
## about a third of its height.
func _fn_palm(uv: Vector2) -> Color:
	const AR := 1.6       # bake 150x240
	var sy := uv.y * AR
	var a := 0.0
	var t := clampf((AR - sy) / (AR * 2.0), 0.0, 1.0)     # 0 root, 1 crown
	# The trunk leans and thins as it rises.
	var cx: float = 0.34 * t * t
	var hw: float = lerpf(0.15, 0.055, t)
	if absf(uv.x - cx) < hw and sy > -1.10:
		a = 1.0 - smoothstep(hw * 0.75, hw, absf(uv.x - cx))
	# The crown sits at the very top of the trunk. Pixels well below it can
	# never touch a frond, so they skip the sixteen segment tests entirely.
	var crown := Vector2(0.34, -1.10)
	if sy > -0.20:
		if a <= 0.02:
			return Color(0, 0, 0, 0)
		var b0: float = 0.62 + 0.38 * (0.5 + 0.5 * sin(sy * 14.0))
		b0 *= 0.72 + 0.28 * clampf(0.5 - (uv.x - cx) * 1.4, 0.0, 1.0)
		return Color(clampf(b0, 0.0, 1.0), clampf(b0, 0.0, 1.0), clampf(b0, 0.0, 1.0), a)
	for k in 8:
		var ang: float = PI * (0.10 + 0.11 * float(k))    # a fan, mostly sideways
		var reach := 0.62
		var dir := Vector2(-cos(ang), -absf(sin(ang)) * 0.55)
		var mid := crown + dir * reach * 0.55
		# Fronds arch UP then droop, so the tip falls below the mid-point.
		var tip := crown + Vector2(dir.x * reach, dir.y * reach * 0.35 + 0.30)
		var d := minf(_seg_dist(Vector2(uv.x, sy), crown, mid),
			_seg_dist(Vector2(uv.x, sy), mid, tip))
		var fw: float = 0.075 * (1.0 - 0.45 * float(k) / 8.0)
		if d < fw:
			a = maxf(a, 1.0 - smoothstep(fw * 0.55, fw, d))
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# The trunk's ring scars, and a lit side.
	var b: float = 0.62 + 0.38 * (0.5 + 0.5 * sin(sy * 14.0))
	b *= 0.72 + 0.28 * clampf(0.5 - (uv.x - cx) * 1.4, 0.0, 1.0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A classical bust on a plinth: head, neck, shoulders, and a squat base.
func _fn_bust(uv: Vector2) -> Color:
	const AR := 1.31      # bake 130x170
	var sy := uv.y * AR
	var a := 0.0
	var b := 0.55
	# The plinth.
	if sy > 0.62:
		var t := (sy - 0.62) / 0.69
		if absf(uv.x) < lerpf(0.44, 0.62, t):
			a = 1.0
			b = 0.34 + 0.20 * (1.0 - t)
	# The shoulders, cut off flat the way a bust is.
	if sy > -0.10 and sy <= 0.62:
		var t := (sy + 0.10) / 0.72
		if absf(uv.x) < lerpf(0.30, 0.76, pow(t, 0.6)):
			a = 1.0
			b = 0.62 + 0.34 * clampf(0.5 - uv.x * 0.9, 0.0, 1.0)
	# The neck.
	if sy > -0.40 and sy <= -0.06 and absf(uv.x) < 0.20:
		a = 1.0
		b = 0.50
	# The head, with a straight classical nose in profile-ish three-quarter.
	var head := Vector2(uv.x / 0.40, (sy + 0.80) / 0.50)
	if head.length() < 1.0:
		a = 1.0
		b = 0.66 + 0.34 * clampf(0.55 - head.x * 0.5 - head.y * 0.4, 0.0, 1.0)
	# The hair mass over the crown.
	if Vector2(uv.x / 0.46, (sy + 1.00) / 0.36).length() < 1.0:
		a = 1.0
		b = minf(b, 0.42)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A tea house: a deep hipped roof with upturned eaves over a low timber body.
func _fn_teahouse(uv: Vector2) -> Color:
	const AR := 0.68      # bake 220x150
	var sy := uv.y / AR
	var a := 0.0
	var b := 0.6
	# The roof: a broad shallow triangle whose eaves lift at the ends.
	if sy > -1.30 and sy < 0.10:
		var t := (sy + 1.30) / 1.40
		var hw: float = lerpf(0.08, 1.0, pow(t, 0.85))
		# The eave lift: the lower edge rises toward the tips.
		var lift: float = 0.20 * pow(clampf((absf(uv.x) - 0.45) / 0.55, 0.0, 1.0), 1.6)
		if absf(uv.x) < hw and sy < 0.10 - lift:
			a = 1.0
			b = 0.34 + 0.30 * (1.0 - t)          # dark tile, lighter at the ridge
	# The body under it.
	if sy >= 0.02 and sy < 1.00 and absf(uv.x) < 0.60:
		a = 1.0
		b = 0.62
		# Post-and-panel: vertical timbers.
		if absf(fposmod(uv.x * 5.0, 1.0) - 0.5) > 0.36:
			b = 0.34
	# The veranda step.
	if sy >= 0.94 and absf(uv.x) < 0.72:
		a = 1.0
		b = 0.44
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A bamboo pipe for the shishi-odoshi: a cut culm with a node ring and an open
## mouth at one end.
func _fn_bamboo_pipe(uv: Vector2) -> Color:
	if absf(uv.y) > 0.72:
		return Color(0, 0, 0, 0)
	var a: float = 1.0 - smoothstep(0.58, 0.72, absf(uv.y))
	# Cylinder shading.
	var b: float = 0.52 + 0.48 * (1.0 - absf(uv.y + 0.18) / 0.9)
	# A node ring across the culm.
	if absf(uv.x + 0.10) < 0.05:
		b *= 0.6
	# The open mouth at the right-hand end, in shadow.
	if uv.x > 0.80:
		b *= 0.30
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A lighthouse: a tapered tower with day-mark bands, a corbelled gallery, the
## glazed lantern room and a domed cap. Big enough to be the one man-made
## vertical on the horizon.
func _fn_lighthouse(uv: Vector2) -> Color:
	const AR := 2.56      # bake 90x230
	var sy := uv.y * AR
	var a := 0.0
	var col := Color(0, 0, 0)
	var t := clampf((sy + AR) / (AR * 2.0), 0.0, 1.0)     # 0 top, 1 base
	# The tower: a gentle taper, widest at the foot.
	var hw: float = lerpf(0.30, 0.86, pow(t, 1.25))
	if sy > -1.55 and absf(uv.x) < hw:
		a = 1.0
		# Cylinder shading, lit from the left.
		var f := uv.x / maxf(hw, 0.01)
		var b: float = 0.55 + 0.45 * clampf(0.60 - f * 0.55, 0.0, 1.0)
		col = Color(b, b, b)
		# Day-mark bands: the red-and-white spiral every lighthouse wears.
		if fposmod(t * 5.0, 1.0) < 0.42:
			col = Color(0.78, 0.16, 0.16).lerp(Color(1, 1, 1), b * 0.35)
	# The gallery: a ring that oversails the tower.
	if sy > -1.78 and sy <= -1.55:
		if absf(uv.x) < 0.62:
			a = 1.0
			col = Color(0.32, 0.34, 0.40)
	# The lantern room: glazed, and brighter than anything else here.
	if sy > -2.20 and sy <= -1.78 and absf(uv.x) < 0.44:
		a = 1.0
		col = Color(0.96, 0.90, 0.66)
		# Astragal bars across the glass.
		if absf(fposmod(uv.x * 5.0, 1.0) - 0.5) > 0.34:
			col = Color(0.26, 0.27, 0.32)
	# The domed cap and finial.
	if sy <= -2.20:
		var dome := Vector2(uv.x / 0.46, (sy + 2.20) / 0.34)
		if Vector2(dome.x, minf(dome.y, 0.0)).length() < 1.0:
			a = 1.0
			col = Color(0.24, 0.26, 0.31)
		if absf(uv.x) < 0.05 and sy > -2.72 and sy < -2.48:
			a = 1.0
			col = Color(0.30, 0.32, 0.38)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(col.r, col.g, col.b, a)

## A dead tree: a forked trunk with bare, crooked branches. Unmistakable in
## outline at any size, which is exactly why it is here.
func _fn_dead_tree(uv: Vector2) -> Color:
	const AR := 1.29      # bake 170x220
	var sy := uv.y * AR
	# The crown never reaches the outer margin or above the tallest leader.
	if absf(uv.x) > 0.92 or sy < -1.20:
		return Color(0, 0, 0, 0)
	var p := Vector2(uv.x, sy)
	var a := 0.0
	# The trunk, splitting into two main leaders.
	if _seg_dist(p, Vector2(-0.04, 1.29), Vector2(0.02, 0.10)) < 0.13:
		a = 1.0
	for lead_v in [[0.02, 0.10, -0.42, -0.86], [0.02, 0.10, 0.40, -0.72]]:
		var l: Array = lead_v
		var root := Vector2(float(l[0]), float(l[1]))
		var tip := Vector2(float(l[2]), float(l[3]))
		if _seg_dist(p, root, tip) < 0.075:
			a = 1.0
		# Crooked side branches off each leader — a dead tree is all elbows.
		for k in 3:
			var f := 0.30 + 0.28 * float(k)
			var at := root.lerp(tip, f)
			var side: float = 1.0 if k % 2 == 0 else -1.0
			var out := at + Vector2(side * (0.30 - 0.06 * float(k)), -0.24 + 0.03 * float(k))
			if _seg_dist(p, at, out) < 0.042:
				a = 1.0
			var kink := out + Vector2(side * 0.10, -0.20)
			if _seg_dist(p, out, kink) < 0.028:
				a = 1.0
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

## A broken classical column in MARBLE. Baked in colour, with the two-lamp gel
## of the aesthetic built in: cool light down the left flute, warm bounce up the
## right, veining through the stone and a hard bright break at the top. The flat
## greyscale version read as a lit tube because a single tint over a greyscale
## mask cannot carry two light sources.
func _fn_column(uv: Vector2) -> Color:
	const AR := 2.44      # bake 110x270
	var sy := uv.y * AR
	var a := 0.0
	var col := Color(0, 0, 0)
	var stone := Color(0.88, 0.86, 0.92)
	var shade := Color(0.34, 0.30, 0.46)
	# The stepped plinth.
	if sy > 2.02:
		if absf(uv.x) < 0.96:
			a = 1.0
			col = shade.lerp(stone, 0.42 + 0.30 * clampf(0.5 - uv.x, 0.0, 1.0))
	elif sy > 1.78:
		if absf(uv.x) < 0.80:
			a = 1.0
			col = shade.lerp(stone, 0.55 + 0.30 * clampf(0.5 - uv.x, 0.0, 1.0))
	# The shaft, broken off on a slant that is not level.
	var brk: float = -1.52 + 0.18 * sin(uv.x * 4.2 + 0.7)
	if sy > brk and sy <= 1.78 and absf(uv.x) < 0.64:
		a = 1.0
		var f := uv.x / 0.64
		# Twenty flutes: a channel profile, not a stripe. Each flute is a little
		# cylinder, so it has its own highlight and its own shadow.
		var fl: float = fposmod(f * 5.0 + 0.5, 1.0) - 0.5
		var flute_shade: float = 1.0 - absf(fl) * 1.5
		# The drum itself is round: the terminator runs down it.
		var body: float = clampf(0.62 - f * 0.72, 0.0, 1.0)
		col = shade.lerp(stone, clampf(body * 0.85 + flute_shade * 0.22, 0.0, 1.0))
		# Marble veining.
		var vein: float = sin(sy * 3.1 + uv.x * 6.0) * sin(sy * 1.7 - uv.x * 4.0)
		col = col.lerp(Color(0.52, 0.48, 0.62), clampf(smoothstep(0.72, 0.95, vein), 0.0, 1.0) * 0.45)
		# The two lamps: cyan raking the left edge, magenta the right.
		col = col.lerp(Color(0.45, 0.95, 1.0), clampf(-f * 1.4 - 0.25, 0.0, 1.0) * 0.55)
		col = col.lerp(Color(1.0, 0.42, 0.85), clampf(f * 1.4 - 0.25, 0.0, 1.0) * 0.55)
		# The broken face: raw, bright, unpolished stone.
		if sy < brk + 0.13:
			col = Color(0.96, 0.94, 0.98)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(col.r, col.g, col.b, a)

## A torii gate: two battered pillars, the curved top lintel and the tie beam.
func _fn_torii(uv: Vector2) -> Color:
	const AR := 0.846     # bake 130x110
	var sy := uv.y / AR
	var a := 0.0
	# The two pillars, leaning very slightly inward.
	for s_v in [-1.0, 1.0]:
		var s: float = s_v
		var lean: float = 0.05 * (sy + 1.0)
		if absf(uv.x - s * (0.60 - lean)) < 0.10 and sy > -0.52:
			a = 1.0
	# The kasagi: the top lintel, curving up at both ends.
	var curve: float = -0.72 - 0.14 * uv.x * uv.x
	if sy > curve and sy < curve + 0.20 and absf(uv.x) < 0.96:
		a = 1.0
	# The nuki: the straight tie beam below it.
	if absf(sy + 0.34) < 0.075 and absf(uv.x) < 0.76:
		a = 1.0
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

## A reed: a tall blade with a seed head, bending under its own weight.
func _fn_reed(uv: Vector2) -> Color:
	const AR := 3.33      # bake 60x200
	var sy := uv.y * AR
	var t := clampf((AR - sy) / (AR * 2.0), 0.0, 1.0)    # 0 root, 1 tip
	var cx: float = 0.60 * t * t * t
	var hw: float = lerpf(0.20, 0.05, t)
	var d := absf(uv.x - cx)
	var a: float = 1.0 - smoothstep(hw * 0.6, hw, d)
	# The seed head: a fat catkin at the tip.
	var head := Vector2((uv.x - 0.60) / 0.26, (sy + 2.55) / 0.62)
	if head.length() < 1.0:
		a = maxf(a, 1.0 - smoothstep(0.82, 1.0, head.length()))
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	var b: float = 0.60 + 0.40 * (1.0 - d / maxf(hw, 0.01))
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A jam jar: straight sides, a shoulder, a screw band and a lid, drawn as glass
## (a bright rim and a soft interior, mostly transparent).
func _fn_jar(uv: Vector2) -> Color:
	const AR := 1.36      # bake 110x150
	var sy := uv.y * AR
	var a := 0.0
	var b := 0.5
	# The body.
	if sy > -0.72 and sy < 1.20 and absf(uv.x) < 0.80:
		a = 1.0
		# Glass: bright at the two edges, near-empty through the middle.
		var f := absf(uv.x) / 0.80
		b = 0.20 + 0.80 * smoothstep(0.55, 1.0, f)
	# The shoulder, tucking in toward the neck.
	if sy <= -0.72 and sy > -1.02:
		var t := (-0.72 - sy) / 0.30
		var hw := lerpf(0.80, 0.52, t)
		if absf(uv.x) < hw:
			a = 1.0
			b = 0.24 + 0.76 * smoothstep(0.55, 1.0, absf(uv.x) / hw)
	# The screw band and lid.
	if sy <= -1.02 and sy > -1.30 and absf(uv.x) < 0.56:
		a = 1.0
		b = 0.72
		if absf(fposmod(sy * 14.0, 1.0) - 0.5) > 0.32:
			b = 0.44
	# The base, thicker glass.
	if sy >= 1.10 and absf(uv.x) < 0.80:
		a = 1.0
		b = 0.78
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A standing person in silhouette, seen from behind: head, shoulders, coat.
func _fn_person(uv: Vector2) -> Color:
	const AR := 2.17      # bake 60x130
	var sy := uv.y * AR
	var a := 0.0
	# The head.
	if Vector2(uv.x / 0.38, (sy + 1.72) / 0.42).length() < 1.0:
		a = 1.0
	# Shoulders and body, widening a little to the hem.
	if sy > -1.42:
		var t := clampf((sy + 1.42) / 3.6, 0.0, 1.0)
		var hw: float = lerpf(0.30, 0.78, pow(t, 0.35))
		if absf(uv.x) < hw:
			a = 1.0
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

## An arched stone bridge, baked in colour. The parapet is lamplit from above,
## the arch soffit falls into shadow, and the voussoirs round the arch are cut
## as separate stones. A flat black slab was reading as a hole in the picture.
func _fn_bridge(uv: Vector2) -> Color:
	const AR := 0.382     # bake 340x130
	var sy := uv.y / AR
	var a := 0.0
	var col := Color(0, 0, 0)
	var stone := Color(0.52, 0.46, 0.44)
	# The deck: an arc rising to the middle of the span.
	var crown: float = sqrt(maxf(0.0, 1.0 - uv.x * uv.x))
	var deck: float = -0.34 - 0.62 * crown
	if sy > deck and sy < deck + 0.52:
		a = 1.0
		# Lamplit along the top edge, falling away underneath.
		var t := (sy - deck) / 0.52
		col = stone.lerp(Color(1.0, 0.82, 0.52), (1.0 - t) * 0.75)
		col = col.lerp(Color(0.16, 0.11, 0.12), t * 0.55)
	# The pier below the deck.
	if sy >= deck + 0.52 and absf(uv.x) < 0.92:
		a = 1.0
		col = stone.darkened(0.42)
		# Coursed masonry.
		var course := floorf(sy * 3.2)
		var bx: float = uv.x * 7.0 + fposmod(course, 2.0) * 0.5
		if absf(fposmod(bx, 1.0) - 0.5) > 0.42 or absf(fposmod(sy * 3.2, 1.0) - 0.5) > 0.42:
			col = col.darkened(0.30)
		# The arch cut through it — and its soffit, which is the darkest thing.
		var arch := Vector2(uv.x / 0.46, (sy - 2.30) / 1.62)
		var ar := Vector2(arch.x, minf(arch.y, 0.0)).length()
		if ar < 1.0:
			a = 0.0
		elif ar < 1.22:
			# The voussoirs: wedge stones ringing the arch, catching a little light.
			var ring_ang := atan2(-minf(arch.y, 0.0), arch.x) / PI
			col = stone.lerp(Color(0.72, 0.64, 0.58), 0.35)
			if absf(fposmod(ring_ang * 9.0, 1.0) - 0.5) > 0.40:
				col = col.darkened(0.35)
	# The balustrade posts standing on the deck.
	if sy > deck - 0.40 and sy <= deck:
		if absf(fposmod(uv.x * 18.0, 1.0) - 0.5) < 0.22:
			a = 1.0
			col = stone.lerp(Color(1.0, 0.80, 0.48), 0.45)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(col.r, col.g, col.b, a)

## A ramen stall: a lit awning over a counter, with a noren curtain hanging at
## one end and lanterns at the other. Baked in colour — the lit interior is the
## whole point of it.
func _fn_ramen_stall(uv: Vector2) -> Color:
	const AR := 0.727     # bake 220x160
	var sy := uv.y / AR
	var a := 0.0
	var col := Color(0, 0, 0)
	# The awning.
	if sy > -1.30 and sy < -0.86 and absf(uv.x) < 1.0:
		a = 1.0
		col = Color(0.62, 0.14, 0.12)
		if absf(fposmod(uv.x * 6.0, 1.0) - 0.5) > 0.36:
			col = Color(0.86, 0.80, 0.66)
	# The lit interior under it.
	if sy >= -0.86 and sy < 0.42 and absf(uv.x) < 0.92:
		a = 1.0
		col = Color(1.0, 0.80, 0.42)
		# The back wall's shelves, in shadow against the light.
		if absf(fposmod(sy * 2.6, 1.0) - 0.5) > 0.40:
			col = Color(0.72, 0.44, 0.18)
	# The noren strips hanging at the left end.
	if sy >= -0.86 and sy < -0.20 and uv.x < -0.52:
		a = 1.0
		col = Color(0.16, 0.20, 0.34)
		if absf(fposmod(uv.x * 12.0, 1.0) - 0.5) > 0.40:
			col = Color(0.42, 0.48, 0.66)
	# The counter, and the stall's body below it.
	if sy >= 0.42 and sy < 0.66 and absf(uv.x) < 1.0:
		a = 1.0
		col = Color(0.42, 0.26, 0.14)
	if sy >= 0.66 and absf(uv.x) < 0.90:
		a = 1.0
		col = Color(0.14, 0.10, 0.10)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(col.r, col.g, col.b, a)

## A flower on a tall stem, baked in colour. Three species share this one bake,
## chosen by `kind`, because a bed where every bloom is the same five-petal
## rosette reads as wallpaper — variety of FORM is most of what makes a planted
## bed look real, ahead of variety of colour.
##
##   0  cosmos     eight broad petals, notched at the tip, gold disc centre
##   1  ranunculus tightly layered rings of short petals, no visible centre
##   2  campanula  a nodding bell on a fine arched stem
##
## Shading runs from a pale rim to a saturated throat on every petal, and each
## carries a midrib, so the bloom has form rather than being a flat rosette.
## A mass of foliage: eleven pointed leaves radiating off a short stem, drawn as
## real leaves rather than a soft blob so the canopy has a scalloped edge for
## the moon to come through. Tinted near-black by the grove, so all this bake
## has to survive is silhouette plus a lit top edge.
const _LM_LEAVES := [
	Vector2(-0.74, 0.20), Vector2(-0.52, -0.34), Vector2(-0.22, 0.32),
	Vector2(0.02, -0.44), Vector2(0.26, 0.26), Vector2(0.54, -0.28),
	Vector2(0.76, 0.18), Vector2(-0.38, 0.02), Vector2(0.14, -0.06),
	Vector2(0.44, 0.06), Vector2(-0.06, 0.44),
]

func _fn_leaf_mass(uv: Vector2) -> Color:
	var p := Vector2(uv.x, uv.y * 0.75)      # bake 72x54
	var a := 0.0
	var b := 0.5
	for k in _LM_LEAVES.size():
		var c: Vector2 = _LM_LEAVES[k]
		var ang: float = atan2(c.y, c.x) + 0.5 * fposmod(float(k) * 0.618, 1.0)
		var u := Vector2(cos(ang), sin(ang))
		var d: Vector2 = p - c * 0.55
		var lu: float = d.dot(u)
		var lv: float = d.dot(Vector2(-u.y, u.x))
		var reach: float = 0.34 + 0.14 * fposmod(float(k) * 0.3819, 1.0)
		var t: float = (lu + reach * 0.55) / (reach * 1.55)
		if t < 0.0 or t > 1.0:
			continue
		# An almond leaf: pointed at both ends, widest in the middle.
		var hw: float = reach * 0.42 * sin(t * PI)
		if absf(lv) > hw:
			continue
		var la: float = 1.0 - smoothstep(hw * 0.80, hw, absf(lv))
		if la <= a:
			continue
		a = la
		# Lit along the top, and the midrib takes a little more of it.
		b = 0.30 + 0.44 * clampf(0.5 - p.y * 1.1, 0.0, 1.0)
		b += (1.0 - smoothstep(0.0, hw * 0.22, absf(lv))) * 0.18
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A little glowing cap on a slender stalk — the fungus that grows in a wood
## nobody has walked through. Baked white; the grove tints it and pools its own
## light under it.
func _fn_glow_cap(uv: Vector2) -> Color:
	const AR := 0.85      # bake 40x34
	var sy := uv.y / AR
	var a := 0.0
	var b := 0.5
	# The stalk, swelling a little at the base.
	var sw: float = 0.10 + 0.06 * smoothstep(0.2, 1.0, sy)
	if absf(uv.x) < sw and sy > -0.10:
		a = 1.0
		b = 0.42 + 0.36 * clampf(0.5 - uv.x / maxf(sw, 0.01) * 0.5, 0.0, 1.0)
	# The cap: a dome with a rolled rim, hanging a little over the stalk.
	var cd := Vector2(uv.x / 0.92, (sy + 0.16) / 0.72).length()
	if cd < 1.0 and sy < 0.02:
		a = 1.0
		b = 0.55 + 0.42 * (1.0 - cd)
		b += (1.0 - smoothstep(0.70, 1.0, cd)) * 0.10
		# Gills glowing under the rim.
		if sy > -0.16:
			b = maxf(b, 0.90 - 0.30 * absf(sin(uv.x * 16.0)))
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A tuft of meadow grass: seven blades off one root, each ARCHING over rather
## than standing up (a straight blade reads as a spike), tapering to a point and
## carrying a lit edge down one side. Silhouetted in the grove's foreground, so
## the shading only has to survive being tinted near-black.
func _fn_grass_tuft(uv: Vector2) -> Color:
	const AR := 1.61      # bake 46x74
	var sy := uv.y * AR
	var p := Vector2(uv.x, sy)
	var a := 0.0
	var b := 0.5
	# [lean, height, bow]
	for e_v in [[-0.86, 0.72, -0.34], [-0.50, 1.16, -0.20], [-0.20, 1.52, -0.08],
			[0.08, 1.66, 0.06], [0.36, 1.34, 0.20], [0.66, 0.98, 0.32],
			[0.92, 0.62, 0.44]]:
		var e: Array = e_v
		var lean: float = float(e[0])
		var hgt: float = float(e[1])
		var bow: float = float(e[2])
		var root := Vector2(lean * 0.16, AR)
		var tip := Vector2(lean, AR - hgt * 1.55)
		var mid := root.lerp(tip, 0.55) + Vector2(bow, 0.0)
		var d: float = minf(_seg_dist(p, root, mid), _seg_dist(p, mid, tip))
		# The blade tapers: fat at the root, a hairline at the tip.
		var along: float = clampf((AR - p.y) / maxf(hgt * 1.55, 0.01), 0.0, 1.0)
		var hw: float = lerpf(0.075, 0.004, pow(along, 0.75))
		if d < hw:
			a = 1.0
			b = 0.34 + 0.52 * clampf(1.0 - d / maxf(hw, 0.001), 0.0, 1.0)
			b += lean * 0.10
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A fern frond: a rachis with paired pinnae stepping down it, each pinna
## shorter than the last so the frond tapers to a curled tip. Two of these at
## the edges of the grove's bed is what stops it reading as one flat row.
func _fn_fern_frond(uv: Vector2) -> Color:
	const AR := 1.6       # bake 60x96
	var sy := uv.y * AR
	var p := Vector2(uv.x, sy)
	var a := 0.0
	var b := 0.5
	# The rachis, arching slightly.
	var root := Vector2(0.0, AR)
	var tip := Vector2(0.22, -AR * 0.92)
	var mid := root.lerp(tip, 0.5) + Vector2(-0.16, 0.0)
	var spine: float = minf(_seg_dist(p, root, mid), _seg_dist(p, mid, tip))
	if spine < 0.045:
		a = 1.0
		b = 0.62
	# Pinnae: nine pairs, longest low on the frond, angled up toward the tip.
	for k in 9:
		var t: float = 0.06 + 0.104 * float(k)
		var at: Vector2 = root.lerp(mid, minf(t * 2.0, 1.0)) if t < 0.5 \
			else mid.lerp(tip, (t - 0.5) * 2.0)
		var reach: float = (0.86 - 0.082 * float(k))
		if (p - at).length_squared() > (reach + 0.12) * (reach + 0.12):
			continue
		for s_v in [-1.0, 1.0]:
			var sgn: float = s_v
			var pt: Vector2 = at + Vector2(sgn * reach, -reach * 0.52)
			var d: float = _seg_dist(p, at, pt)
			var along: float = clampf((p - at).length() / maxf(reach, 0.01), 0.0, 1.0)
			var hw: float = lerpf(0.070, 0.006, pow(along, 0.6))
			# Toothed edge — a fern pinna is never a smooth blade.
			hw -= 0.012 * absf(sin(along * 20.0))
			if d < hw:
				a = 1.0
				b = 0.30 + 0.48 * clampf(1.0 - d / maxf(hw, 0.001), 0.0, 1.0)
				b -= sgn * 0.08
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## The three species of the grove. Every colour in here is a NIGHT colour.
##
## The bloom geometry survived the rewrite; the palette did not. These were
## authored as a daylight bed — magenta cosmos, crimson ranunculus, violet
## campanula — and dropped into a deep blue-navy midnight clearing, where they
## read as clip-art stickers pasted along the bottom edge: the one warm, fully
## saturated thing in a scene lit by a cold moon. Night flowers are almost
## colourless. What you actually see is moonlight ON white, which means silver,
## ice and the faintest wash of the flower's own hue, with the throat holding
## the only real colour on the plant.
func _fn_flower_kind(uv: Vector2, kind: int) -> Color:
	const AR := 2.2       # bake 100x220
	var sy := uv.y * AR
	var a := 0.0
	var col := Color(0, 0, 0)
	# Foliage at night is nearly black and reads BLUE, not green.
	var green := Color(0.11, 0.24, 0.22)
	var t := clampf((AR - sy) / (AR * 2.0), 0.0, 1.0)
	# Campanula nods, so its stem arches further over than the others.
	var bend: float = 0.34 if kind == 2 else 0.20
	var cx: float = bend * t * t
	# A flower on a tall stem leaves most of its bake blank; reject the margins
	# before the leaf and petal maths.
	if absf(uv.x) > 0.98:
		return Color(0, 0, 0, 0)
	# --- The stem ---
	if absf(uv.x - cx) < lerpf(0.085, 0.040, t) and sy > -1.52:
		a = 1.0
		# A lit edge down one side turns a bar into a stalk.
		col = green.darkened(0.25).lerp(green.lightened(0.40),
			clampf(0.5 - (uv.x - cx) * 6.0, 0.0, 1.0))
	# --- Leaves: pointed blades with a pale midrib and a serrated edge ---
	for e_v in [[0.30, -1.0, 0.60], [0.55, 1.0, 0.52], [0.74, -1.0, 0.38]]:
		var e: Array = e_v
		var f := float(e[0])
		var at := Vector2(bend * f * f, AR - f * AR * 2.0)
		var reach := float(e[2])
		var tip := at + Vector2(float(e[1]) * reach, -0.34 * reach / 0.6)
		var d := _seg_dist(Vector2(uv.x, sy), at, tip)
		var along := clampf((Vector2(uv.x, sy) - at).length() / maxf(reach, 0.01), 0.0, 1.0)
		var lw: float = 0.15 * sin(along * PI) * (reach / 0.6)
		# Serrations along the blade edge.
		lw -= 0.018 * absf(sin(along * 22.0))
		if d < lw:
			a = 1.0
			var edge := 1.0 - smoothstep(0.0, lw, d)
			col = green.darkened(0.30).lerp(green.lightened(0.28), edge)
			# The midrib.
			if d < lw * 0.14:
				col = green.lightened(0.45)
	# --- The head ---
	# Each species sits at a height that keeps its whole head inside the bake:
	# the ranunculus is the widest, so it hangs lowest.
	var head_y: float = -1.62
	if kind == 1:
		head_y = -1.30
	elif kind == 2:
		head_y = -1.30
	var hc := Vector2(uv.x - bend, sy - head_y)
	var r := hc.length()
	# Most of a tall-flower bake is empty sky above and beside the head, and
	# every pixel of it was paying for the petal search. The head never reaches
	# past r = 1.2, so anything further out skips the whole block. Measured:
	# it is most of the cost of the heaviest bake in the file.
	if r > 1.25:
		if a <= 0.02:
			return Color(0, 0, 0, 0)
		return Color(col.r, col.g, col.b, a)
	var ang := atan2(hc.y, hc.x)
	if kind == 0:
		# Cosmos, built FROM its petals rather than painted inside a circle.
		#
		# The version before this one shaded a polar lobe function — one radius
		# that wobbles eight times round — and that can only ever produce a
		# flat daisy sticker: every petal shares one surface, so none of them
		# can lap over its neighbour, catch its own light or cast a shadow, and
		# the silhouette is a scalloped disc rather than eight separate things.
		# Here each petal is a real oval in its OWN frame, with a ridge down the
		# middle, a rolled edge, a notched tip and a shadow where the petal in
		# front of it lands. Petals are checked three-at-a-time by angle because
		# once they overlap, the nearest by angle is not the nearest by distance.
		var per := 8.0
		var pidx0 := roundf(ang * per / TAU)
		var best_a := 0.0
		for k_v in [-1.0, 0.0, 1.0]:
			var kk: float = k_v
			var pang: float = (pidx0 + kk) * TAU / per
			var u := Vector2(cos(pang), sin(pang))
			var lu: float = hc.dot(u)
			var lv: float = hc.dot(Vector2(-u.y, u.x))
			var pt: float = (lu - 0.08) / 0.84            # 0 at the throat, 1 at the tip
			if pt < -0.06 or pt > 1.10:
				continue
			# A cosmos petal is a broad wedge, widest two-thirds out.
			var hw: float = 0.30 * pow(sin(clampf(pt, 0.0, 1.0) * PI * 0.86 + 0.16), 0.55)
			if hw <= 0.001:
				continue
			var across: float = lv / hw
			# The notch: the tip is cut in on the centre line, which is what
			# makes a cosmos a cosmos and not a marguerite.
			var tip_cut: float = 1.0 - 0.13 * (1.0 - smoothstep(0.0, 0.62, absf(across)))
			if pt > tip_cut:
				continue
			var pa: float = (1.0 - smoothstep(0.86, 1.0, absf(across))) 				* smoothstep(-0.06, 0.06, pt) * (1.0 - smoothstep(tip_cut - 0.06, tip_cut, pt))
			if pa <= best_a:
				continue
			best_a = pa
			a = maxf(a, pa)
			# White at the throat, taking the blue of the night at the rim.
			var c0 := Color(1.0, 1.0, 1.0).lerp(Color(0.64, 0.76, 0.96), pow(clampf(pt, 0.0, 1.0), 1.15))
			# The ridge: a petal is a shallow trough, brightest along its midrib
			# and turning away at both edges.
			c0 = c0.lerp(Color(1.0, 1.0, 1.0), (1.0 - smoothstep(0.0, 0.42, absf(across))) * 0.45)
			c0 = c0.lerp(Color(0.44, 0.56, 0.82), smoothstep(0.56, 1.0, absf(across)) * 0.55)
			# The three veins every cosmos petal carries.
			c0 = c0.lerp(Color(0.52, 0.64, 0.88),
				pow(absf(sin(across * 4.2)), 8.0) * 0.30 * smoothstep(0.15, 1.0, pt))
			# The shadow the petal in FRONT lays across this one — one edge only,
			# which is what gives the bloom its depth.
			c0 = c0.lerp(Color(0.30, 0.40, 0.66),
				clampf(smoothstep(0.30, 1.0, across), 0.0, 1.0) * 0.30 * (1.0 - pt * 0.5))
			col = c0
		if r < 0.19:
			# The throat: the one warm thing on a night flower, and it glows.
			col = Color(1.0, 0.94, 0.72)
			if r > 0.10 and absf(fposmod(ang * 9.0 / TAU, 1.0) - 0.5) > 0.30:
				col = Color(0.86, 0.74, 0.50)
			col = col.lerp(Color(1.0, 1.0, 0.92), (1.0 - smoothstep(0.0, 0.12, r)) * 0.75)
	elif kind == 1:
		# Ranunculus: the bloom is BUILT from its petals rather than painted
		# inside a circle. Every pixel asks which petal lobe it falls in; if the
		# answer is none, it is outside the flower. That makes the silhouette
		# scalloped by construction — a circle with petals drawn on it reads as
		# a dartboard however the inside is shaded, which both earlier passes did.
		var outer: float = 0.78
		var best := 9.0
		var best_ring := 0.0
		var best_pang := 0.0
		for ring_i in 3:
			var ring := float(ring_i)
			# Rings alternate their phase, so petals interleave the way they
			# actually pack, and each ring sits a little further out.
			var per := 5.0 + ring * 2.0
			var pc_r: float = (0.18 + ring * 0.27) * outer
			var lobe_r: float = (0.32 - ring * 0.030) * outer * 1.62
			var pidx := roundf((ang - ring * 0.7) * per / TAU)
			# Check this petal and its two neighbours — the nearest by angle is
			# not always the nearest by distance once the lobes overlap.
			for k in [-1.0, 0.0, 1.0]:
				var pang: float = (pidx + k) * TAU / per + ring * 0.7
				var centre := Vector2(cos(pang), sin(pang)) * pc_r
				var lobe := (hc - centre).length() / lobe_r
				if lobe < best:
					best = lobe
					best_ring = ring
					best_pang = pang
		if best < 1.0:
			a = 1.0 - smoothstep(0.92, 1.0, best)
			var depth: float = best_ring / 2.0
			# Outer petals pale and open, inner ones deep and packed.
			col = Color(0.62, 0.68, 0.90).lerp(Color(1.0, 0.99, 1.0), depth)
			# Each petal is a curled cup: bright where it faces up, shadowed in
			# its own hollow and at the edge where the next petal laps over it.
			var cup: float = clampf(1.0 - best * best, 0.0, 1.0)
			col = col.lerp(Color(1.0, 1.0, 1.0), cup * 0.60)
			col = col.lerp(Color(0.24, 0.30, 0.50), smoothstep(0.66, 1.0, best) * 0.72)
			# A cast shadow from the ring above onto the ring below.
			col = col.lerp(Color(0.32, 0.38, 0.58),
				clampf((1.0 - depth) * 0.32, 0.0, 1.0))
			# The heart stays furled, and keeps a little warmth in it.
			col = col.lerp(Color(0.60, 0.58, 0.52), (1.0 - smoothstep(0.0, 0.20, r)) * 0.8)
	else:
		# Campanula: a nodding bell — a tube that flares into five lobes, seen
		# from slightly below, hanging off the arch of the stem.
		var bx := hc.x
		var by := hc.y
		if by > -0.10 and by < 0.86:
			var bt := (by + 0.10) / 0.96
			# The wall of a bell is a CURVE: it pinches in below the shoulder and
			# then flares out fast at the mouth, and the lip turns outward.
			var hw: float = 0.14 + 0.30 * bt + 0.34 * pow(bt, 4.0)
			# Five lobes round the mouth, which is what a campanula's rim is.
			var scal: float = 0.05 * absf(sin(bx * 9.0)) * smoothstep(0.5, 1.0, bt)
			if absf(bx) < hw - scal:
				a = 1.0
				# A tube: lit down one side, deeply shaded at the other, and
				# darkest right inside the mouth.
				var across := bx / maxf(hw, 0.01)
				col = Color(0.44, 0.52, 0.82).lerp(Color(0.94, 0.97, 1.0),
					clampf(0.55 - across * 0.75, 0.0, 1.0))
				# Deep in the mouth of the bell the light gets in and stays —
				# a lit throat is what makes a hanging bell read as glass.
				col = col.lerp(Color(0.72, 0.86, 1.0), pow(bt, 3.0) * 0.55)
				# Ribs running down the bell.
				var rib: float = 1.0 - smoothstep(0.0, 0.10, absf(fposmod(across * 2.5, 1.0) - 0.5))
				col = col.lerp(Color(0.34, 0.44, 0.74), rib * 0.34)
				# The MOUTH. Without it a campanula bakes as a solid cone —
				# a traffic cone, in the flat tint the bed applies. What says
				# "bell" is being able to see up INSIDE it: the last of the
				# tube goes dark, and the lip in front of that dark stays the
				# brightest line on the flower.
				var mouth: float = smoothstep(0.80, 0.99, bt) * (1.0 - smoothstep(0.55, 0.95, absf(across)))
				col = col.lerp(Color(0.10, 0.16, 0.32), mouth * 0.80)
				var lip: float = smoothstep(0.86, 1.0, bt) * smoothstep(0.60, 0.96, absf(across))
				col = col.lerp(Color(1.0, 1.0, 1.0), lip * 0.75)
				# One specular stripe where the tube turns toward the moon.
				col = col.lerp(Color(1.0, 1.0, 1.0),
					(1.0 - smoothstep(0.0, 0.22, absf(across + 0.44))) * 0.35
					* (1.0 - smoothstep(0.70, 1.0, bt)))
		# The calyx where the bell joins the stem.
		if by <= -0.10 and by > -0.28 and absf(bx) < 0.16:
			a = 1.0
			col = green.lightened(0.10)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(col.r, col.g, col.b, a)

func _fn_flower_cosmos(uv: Vector2) -> Color:
	return _fn_flower_kind(uv, 0)

func _fn_flower_ranunculus(uv: Vector2) -> Color:
	return _fn_flower_kind(uv, 1)

func _fn_flower_bell(uv: Vector2) -> Color:
	return _fn_flower_kind(uv, 2)

## A shoji screen, baked in colour: warm lamplit paper behind a dark timber
## lattice, with the glow of the lamp actually falling off across the panel and
## the silhouette of a branch showing through from the far side.
func _fn_shoji(uv: Vector2) -> Color:
	if absf(uv.x) > 0.99 or absf(uv.y) > 0.99:
		return Color(0, 0, 0, 0)
	# The paper, lit from a lamp low and left behind it.
	var lamp := Vector2(uv.x + 0.34, uv.y - 0.28).length()
	var warmth: float = 1.0 - smoothstep(0.10, 1.35, lamp)
	var col := Color(0.42, 0.34, 0.30).lerp(Color(1.0, 0.86, 0.62), warmth)
	# A branch on the other side of the paper, thrown onto it as a soft shadow.
	var br := minf(
		_seg_dist(uv, Vector2(-0.95, 0.62), Vector2(-0.10, 0.16)),
		_seg_dist(uv, Vector2(-0.10, 0.16), Vector2(0.55, 0.30)))
	col = col.lerp(Color(0.30, 0.22, 0.20), (1.0 - smoothstep(0.03, 0.16, br)) * 0.55)
	# The lattice: mullions and transoms in dark timber, in front of the paper.
	var timber := Color(0.20, 0.13, 0.10)
	if absf(fposmod(uv.x * 4.0, 1.0) - 0.5) > 0.445:
		col = timber
	if absf(fposmod(uv.y * 3.0, 1.0) - 0.5) > 0.445:
		col = timber
	# The outer frame, heavier than the lattice.
	if absf(uv.x) > 0.90 or absf(uv.y) > 0.90:
		col = timber.darkened(0.25)
	return Color(col.r, col.g, col.b, 1.0)

## A garden stone: a rounded boulder with a mossy top and a flat-ish base.
func _fn_stone(uv: Vector2) -> Color:
	const AR := 0.6       # bake 150x90
	var sy := uv.y / AR
	# A lumpy dome, flat where it meets the ground.
	var wob: float = 0.86 + 0.10 * sin(uv.x * 4.0) + 0.05 * sin(uv.x * 9.0 + 1.3)
	var d := Vector2(uv.x / wob, (sy + 0.55) / 1.35).length()
	if d > 1.0 or sy > 0.80:
		return Color(0, 0, 0, 0)
	var a: float = 1.0 - smoothstep(0.92, 1.0, d)
	# Lit from the upper left; moss gathers on the top.
	var lam: float = clampf(0.60 - uv.x * 0.45 - sy * 0.40, 0.0, 1.0)
	var col := Color(0.38, 0.38, 0.36).lerp(Color(0.86, 0.88, 0.86), lam)
	var moss: float = 1.0 - smoothstep(-0.45, 0.15, sy + uv.x * 0.18)
	col = col.lerp(Color(0.34, 0.52, 0.28), moss * 0.65)
	return Color(col.r, col.g, col.b, a)

## A raven, wings mid-beat, seen from below-behind. Two swept arcs and a body.
func _fn_raven(uv: Vector2) -> Color:
	var a := 0.0
	# The body.
	if Vector2(uv.x / 0.20, uv.y / 0.42).length() < 1.0:
		a = 1.0
	# Wings: a swept arc each side, thicker at the shoulder.
	for s_v in [-1.0, 1.0]:
		var s: float = s_v
		var mid := Vector2(s * 0.48, -0.30)
		var tip := Vector2(s * 0.98, 0.06)
		var d := minf(_seg_dist(uv, Vector2(s * 0.10, -0.06), mid),
			_seg_dist(uv, mid, tip))
		if d < 0.13:
			a = maxf(a, 1.0 - smoothstep(0.07, 0.13, d))
	# The tail, a short wedge behind.
	if _in_tri(uv, Vector2(-0.10, 0.34), Vector2(0.10, 0.34), Vector2(0.0, 0.86)):
		a = 1.0
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

## The sun as a DISC: a hard-edged body with limb brightening, not a soft blob.
## On a pale sky a gaussian smudge is invisible; an edge is what reads.
func _fn_sun_disc(uv: Vector2) -> Color:
	var r := uv.length()
	if r > 1.0:
		return Color(0, 0, 0, 0)
	# A crisp limb with just enough softness to avoid aliasing.
	var a: float = 1.0 - smoothstep(0.86, 0.96, r)
	# Brighter at the rim than the centre — a low sun through atmosphere.
	var col := Color(1.0, 0.88, 0.52).lerp(Color(1.0, 0.62, 0.30), smoothstep(0.0, 0.92, r))
	col = col.lerp(Color(1.0, 0.98, 0.90), (1.0 - smoothstep(0.0, 0.45, r)) * 0.55)
	return Color(col.r, col.g, col.b, a)

## A blossom tree in silhouette-with-colour: a dark trunk under a cloud of
## petals, with a few clumps catching the last of the light.
func _fn_blossom_tree(uv: Vector2) -> Color:
	const AR := 0.93      # bake 140x130
	var sy := uv.y / AR
	var a := 0.0
	var col := Color(0, 0, 0)
	# The trunk and two limbs.
	if _seg_dist(Vector2(uv.x, sy), Vector2(0.0, 1.0), Vector2(-0.06, 0.10)) < 0.075:
		a = 1.0
		col = Color(0.26, 0.14, 0.20)
	for s_v in [-1.0, 1.0]:
		var s: float = s_v
		if _seg_dist(Vector2(uv.x, sy), Vector2(-0.06, 0.16),
				Vector2(s * 0.46, -0.34)) < 0.045:
			a = 1.0
			col = Color(0.26, 0.14, 0.20)
	# The blossom mass: overlapping clumps with a scalloped rim.
	for c_v in [Vector3(-0.42, -0.30, 0.44), Vector3(0.06, -0.56, 0.52),
			Vector3(0.46, -0.26, 0.42), Vector3(-0.10, -0.16, 0.38)]:
		var c: Vector3 = c_v
		var d := Vector2(uv.x - c.x, (sy - c.y) * 1.20).length() / c.z
		var scallop: float = 0.12 * sin(atan2(sy - c.y, uv.x - c.x) * 8.0 + c.x * 7.0)
		var m: float = 1.0 - smoothstep(0.84 + scallop, 1.0 + scallop, d)
		if m > a:
			a = m
			# Lit from the lower right, where the sun is.
			var lam: float = clampf(0.5 + (uv.x - c.x) * 0.7 + (sy - c.y) * 0.5, 0.0, 1.0)
			col = Color(0.86, 0.48, 0.62).lerp(Color(1.0, 0.86, 0.88), lam)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(col.r, col.g, col.b, a)

## A treasure chest tipped on its side with the lid open and coin pouring out.
## Baked in colour: banded oak, iron straps, and the gold spilling from it.
func _fn_chest(uv: Vector2) -> Color:
	const AR := 0.7       # bake 200x140
	var sy := uv.y / AR
	var a := 0.0
	var col := Color(0, 0, 0)
	var oak := Color(0.36, 0.21, 0.11)
	var iron := Color(0.24, 0.24, 0.28)
	# The body: a box sitting on the ground, seen slightly from the side.
	if sy > -0.10 and sy < 0.92 and uv.x > -0.86 and uv.x < 0.52:
		a = 1.0
		var t := (sy + 0.10) / 1.02
		col = oak.lerp(oak.lightened(0.35), 1.0 - t)
		# Plank seams.
		if absf(fposmod(uv.x * 5.0, 1.0) - 0.5) > 0.44:
			col = oak.darkened(0.35)
		# Iron straps.
		if absf(uv.x + 0.60) < 0.07 or absf(uv.x - 0.24) < 0.07:
			col = iron.lerp(iron.lightened(0.4), 1.0 - t)
	# The lid, thrown back and open behind the body.
	if sy > -0.98 and sy <= -0.06:
		var lt := (sy + 0.98) / 0.92
		var lx0: float = -0.72 + 0.22 * lt
		var lx1: float = 0.30 + 0.22 * lt
		if uv.x > lx0 and uv.x < lx1:
			a = 1.0
			col = oak.darkened(0.25).lerp(oak.lightened(0.20), lt)
			if absf(fposmod(uv.x * 5.0, 1.0) - 0.5) > 0.44:
				col = oak.darkened(0.5)
	# The gold spilling out of the mouth, and heaped in front of the chest.
	var spill := Vector2((uv.x - 0.62) / 0.52, (sy - 0.62) / 0.42)
	if spill.length() < 1.0:
		a = 1.0
		# Individual coins in the heap, as a disc lattice.
		var cell := Vector2(fposmod(uv.x * 9.0, 1.0) - 0.5, fposmod(sy * 9.0, 1.0) - 0.5)
		var disc: float = 1.0 - smoothstep(0.24, 0.40, cell.length())
		col = Color(0.86, 0.62, 0.14).lerp(Color(1.0, 0.92, 0.52), disc)
		col = col.lerp(Color(0.52, 0.34, 0.06), spill.length() * 0.45)
	# ...and a mound of it inside the open box.
	if sy > -0.20 and sy < 0.28 and uv.x > -0.78 and uv.x < 0.46:
		var mound: float = 1.0 - smoothstep(0.0, 0.34, absf(sy + 0.02))
		if mound > 0.05:
			var cell2 := Vector2(fposmod(uv.x * 10.0, 1.0) - 0.5, fposmod(sy * 10.0, 1.0) - 0.5)
			var disc2: float = 1.0 - smoothstep(0.24, 0.40, cell2.length())
			a = 1.0
			col = col.lerp(Color(0.90, 0.68, 0.18).lerp(Color(1.0, 0.94, 0.60), disc2), mound)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(col.r, col.g, col.b, a)

## A stack of ingots: trapezoid bars in courses, each with a lit top face and a
## darker front, the top course offset like real stacked bullion.
func _fn_ingot_stack(uv: Vector2) -> Color:
	const AR := 0.706     # bake 170x120
	var sy := uv.y / AR
	var a := 0.0
	var b := 0.5
	# Three courses.
	for row_i in 3:
		var row := float(row_i)
		var y0: float = 1.0 - (row + 1.0) * 0.62
		var y1: float = y0 + 0.58
		if sy < y0 or sy > y1:
			continue
		# Higher courses are shorter and offset.
		var half: float = 0.92 - row * 0.22
		var shift: float = (row - 1.0) * 0.06
		if absf(uv.x - shift) > half:
			continue
		var t := (sy - y0) / 0.58
		# Each bar in the course.
		var per := 3.0 - row * 0.0
		var bx: float = fposmod((uv.x - shift + half) / (half * 2.0) * per, 1.0)
		a = 1.0
		# The top face catches the light; the front face falls away.
		b = 0.95 - t * 0.45
		# The bevel between bars.
		if bx < 0.06 or bx > 0.94:
			b *= 0.55
		# A hard lit edge along the top of each course.
		if t < 0.10:
			b = 1.0
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A goblet standing upright: a flaring bowl, a knop, a stem and a spread foot.
## The first pass laid it on its side, where a flaring cone is indistinguishable
## from a megaphone.
func _fn_chalice(uv: Vector2) -> Color:
	const AR := 1.31      # bake 130x170
	var sy := uv.y * AR
	var a := 0.0
	var b := 0.5
	# The bowl: a curve that flares to the rim, not a straight cone.
	if sy > -1.24 and sy < -0.10:
		var t := (sy + 1.24) / 1.14                     # 0 rim, 1 base of bowl
		var hw: float = 0.86 * pow(1.0 - t, 0.55) + 0.10
		if absf(uv.x) < hw:
			a = 1.0
			# Metal: a bright vertical highlight and a dark turning edge.
			var f := uv.x / maxf(hw, 0.01)
			b = 0.30 + 0.55 * clampf(0.60 - f * 0.75, 0.0, 1.0)
			b = maxf(b, (1.0 - smoothstep(0.0, 0.20, absf(f + 0.42))) * 0.98)
			# The rim, a hard bright line.
			if t < 0.055:
				b = 1.0
			# What is in the cup: a dark ellipse of liquid just below the rim.
			if t > 0.055 and t < 0.16:
				b = 0.16
	# The knop.
	if sy >= -0.10 and sy < 0.10 and absf(uv.x) < 0.24:
		a = 1.0
		b = 0.40 + 0.50 * clampf(0.6 - uv.x * 2.0, 0.0, 1.0)
	# The stem.
	if sy >= 0.10 and sy < 0.86 and absf(uv.x) < 0.11:
		a = 1.0
		b = 0.34 + 0.52 * clampf(0.6 - uv.x * 4.5, 0.0, 1.0)
	# The foot, spreading to the ground.
	if sy >= 0.86:
		var ft := (sy - 0.86) / 0.45
		if absf(uv.x) < lerpf(0.16, 0.72, pow(ft, 0.6)):
			a = 1.0
			b = 0.30 + 0.45 * (1.0 - ft) + 0.30 * clampf(0.5 - uv.x * 1.2, 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## An ice column: a tapering spike with internal flaws and a bright core, the
## light passing through it rather than bouncing off.
func _fn_icicle(uv: Vector2) -> Color:
	const AR := 3.0       # bake 70x210
	var sy := uv.y * AR
	var t := clampf((AR - sy) / (AR * 2.0), 0.0, 1.0)     # 0 base, 1 tip
	var hw: float = 0.92 * pow(1.0 - t, 0.85)
	# A slightly irregular profile — ice is not a cone.
	hw *= 0.90 + 0.10 * sin(sy * 5.0)
	if absf(uv.x) > hw:
		return Color(0, 0, 0, 0)
	var a: float = 1.0 - smoothstep(hw - 0.10, hw, absf(uv.x))
	var f := uv.x / maxf(hw, 0.01)
	# Transmission: brightest through the middle, edges catch a hard specular.
	var b: float = 0.30 + 0.45 * (1.0 - absf(f))
	b = maxf(b, (1.0 - smoothstep(0.0, 0.16, absf(f + 0.55))) * 0.95)
	# Internal flaws: bright veils frozen into the column.
	b += (1.0 - smoothstep(0.0, 0.06, absf(t - 0.34 + f * 0.10))) * 0.30
	b += (1.0 - smoothstep(0.0, 0.05, absf(t - 0.62 - f * 0.08))) * 0.22
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A single cherry petal, and the reason Sakura does not drift the generic
## `_petal()` oval: a cherry petal is notched at its wide end (that notch is the
## whole species read), it is TRANSLUCENT, and it curls. The generic oval shades
## to 0.72 brightness, which on a near-white pink sky came out as a grey speck.
## This one stays between 0.88 and 1.05 — the sky passes through it, so it is
## barely darker than what is behind it, and its curled edge catches white.
func _sakura_petal() -> ImageTexture:
	return _shaped("sk_petal", 26, 34, _fn_sakura_petal)

func _fn_sakura_petal(uv: Vector2) -> Color:
	# Narrow at the stem (top), widest two-thirds down, notched at the bottom.
	var t: float = (uv.y + 1.0) * 0.5                       # 0 stem .. 1 tip
	var half: float = 0.30 + 0.34 * sin(pow(t, 0.78) * PI * 0.92)
	var a: float = 1.0 - smoothstep(half - 0.16, half, absf(uv.x))
	a *= 1.0 - smoothstep(0.86, 1.02, t)                    # the tip end
	# The notch: a V cut into the wide end, deepest on the centre line.
	var notch: float = smoothstep(0.62, 0.94, t) * (1.0 - smoothstep(0.0, 0.42, absf(uv.x)))
	a *= 1.0 - notch * 1.35
	a = clampf(a, 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# Translucent: light coming THROUGH, brightest where the petal is thinnest.
	var b: float = 0.90 + 0.14 * (1.0 - absf(uv.x) / maxf(half, 0.01))
	# The curl — one long edge folds up and catches the light white, the other
	# turns away and takes the only real shade on the petal.
	b += (1.0 - smoothstep(0.0, 0.20, absf(uv.x + half * 0.62))) * 0.16
	b -= smoothstep(0.30, 0.95, uv.x / maxf(half, 0.01)) * 0.16
	# Veins fanning from the stem, just enough to be felt at full size.
	b += sin(uv.x * 16.0) * 0.02 * smoothstep(0.15, 1.0, t)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A CLUSTER of cherry blossom — nine five-petal florets crowded into one mass,
## scattered along the limbs by `_sakura_blossom` at a dozen sizes and angles.
##
## Baked in full colour, because pink dots are what the old polka-dot canopy
## was: the flower is only legible if the petals have the notched tip a cherry
## petal has, a white throat, and a stamen boss in the middle. Nine florets at
## 78x62 is roughly one floret per 500 baked pixels — enough for the shape to
## survive being blown up to a quarter of the screen.
const _SK_FLORETS := [
	Vector2(-0.52, -0.18), Vector2(-0.16, -0.44), Vector2(0.22, -0.30),
	Vector2(0.56, -0.06), Vector2(-0.60, 0.24), Vector2(-0.22, 0.14),
	Vector2(0.14, 0.30), Vector2(0.50, 0.36), Vector2(-0.02, -0.06),
]

func _fn_blossom_cluster(uv: Vector2) -> Color:
	# The bake is 78x62, so y is squashed; undo it and work in a round space.
	var p := Vector2(uv.x, uv.y * 0.795)
	var a := 0.0
	var col := Color(0, 0, 0)
	for k in _SK_FLORETS.size():
		var c: Vector2 = _SK_FLORETS[k]
		var rr: float = 0.36 + 0.07 * fposmod(float(k) * 0.618, 1.0)
		var d: Vector2 = p - c
		var r: float = d.length() / rr
		if r > 1.30:
			continue
		var th: float = atan2(d.y, d.x) + float(k) * 0.7
		# Five rounded petals, each NOTCHED at its tip — the cherry signature,
		# and the one detail that stops the floret reading as a daisy.
		var lobe: float = absf(cos(2.5 * th))
		var edge: float = 0.58 + 0.42 * pow(lobe, 0.6) - 0.14 * pow(lobe, 26.0)
		var fa: float = 1.0 - smoothstep(edge - 0.14, edge, r)
		if fa <= a:
			continue
		a = fa
		# White throat bleeding out into the pink of the petal.
		col = Color(1.0, 0.985, 0.99).lerp(Color(0.97, 0.63, 0.77),
			smoothstep(0.10, 1.0, r))
		# The vein up the middle of each petal, and the deeper pink at its base.
		col = col.lerp(Color(0.93, 0.52, 0.68), (1.0 - lobe) * 0.30 * smoothstep(0.30, 0.95, r))
		# The stamen boss: a warm centre with anthers spraying off it. Kept
		# FAINT — a strong yellow eye on every floret turned the canopy into a
		# bed of daisies, which is what the first pass of this bake looked like.
		if r < 0.30:
			var boss: float = 1.0 - smoothstep(0.08, 0.24, r)
			var anther: float = pow(absf(sin(th * 6.0)), 10.0) * (1.0 - smoothstep(0.20, 0.30, r))
			col = col.lerp(Color(1.0, 0.90, 0.74), clampf(boss * 0.26 + anther * 0.30, 0.0, 1.0))
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# The mass turns: lit from above, shaded underneath, so a cluster is a solid
	# and not a sticker.
	var lam: float = clampf(0.62 - p.y * 0.52 - p.x * 0.10, 0.0, 1.0)
	col = col.lerp(Color(0.86, 0.50, 0.64), (1.0 - lam) * 0.38)
	col = col.lerp(Color(1, 1, 1), clampf(lam - 0.72, 0.0, 1.0) * 0.6)
	return Color(col.r, col.g, col.b, a)

## A street lamp: a fluted post, a scrolled bracket and a lantern head.
func _fn_lamp_post(uv: Vector2) -> Color:
	const AR := 2.67      # bake 90x240
	var sy := uv.y * AR
	var a := 0.0
	var b := 0.5
	# The post, tapering upward, on a flared base.
	var t := clampf((AR - sy) / (AR * 2.0), 0.0, 1.0)
	var hw: float = lerpf(0.22, 0.10, t)
	if absf(uv.x) < hw and sy > -1.90:
		a = 1.0
		b = 0.35 + 0.50 * clampf(0.5 - uv.x / maxf(hw, 0.01) * 0.5, 0.0, 1.0)
	if sy > 2.20:
		if absf(uv.x) < 0.52:
			a = 1.0
			b = 0.4
	# The lantern head: a tapered glass box under a little roof.
	if sy > -2.30 and sy <= -1.86:
		var lt := (sy + 2.30) / 0.44
		var lw := lerpf(0.20, 0.42, lt)
		if absf(uv.x) < lw:
			a = 1.0
			b = 0.92
			# Astragals across the glass.
			if absf(fposmod(uv.x * 4.0, 1.0) - 0.5) > 0.36:
				b = 0.30
	# The roof over it.
	if sy > -2.62 and sy <= -2.28:
		var rt := (sy + 2.62) / 0.34
		if absf(uv.x) < lerpf(0.08, 0.56, rt):
			a = 1.0
			b = 0.26
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A kelp frond: a long strap that undulates as it rises, with a gas bladder at
## the base of each blade.
func _fn_kelp(uv: Vector2) -> Color:
	const AR := 3.43      # bake 70x240
	var sy := uv.y * AR
	var t := clampf((AR - sy) / (AR * 2.0), 0.0, 1.0)     # 0 holdfast, 1 tip
	# The stipe wanders as it climbs.
	var cx: float = 0.52 * sin(t * 3.6) * t
	var hw: float = lerpf(0.16, 0.06, t)
	var d := absf(uv.x - cx)
	var a: float = (1.0 - smoothstep(hw * 0.6, hw, d)) * smoothstep(0.0, 0.04, t)
	var b: float = 0.45 + 0.45 * (1.0 - d / maxf(hw, 0.001))
	# Blades: broad straps peeling off alternate sides.
	for k in 5:
		var f := 0.20 + 0.17 * float(k)
		var side: float = 1.0 if k % 2 == 0 else -1.0
		var at := Vector2(0.52 * sin(f * 3.6) * f, AR - f * AR * 2.0)
		var tip := at + Vector2(side * 0.62, -0.50)
		var bd := _seg_dist(Vector2(uv.x, sy), at, tip)
		var along := clampf((Vector2(uv.x, sy) - at).length() / 0.80, 0.0, 1.0)
		var bw: float = 0.15 * sin(along * PI)
		if bd < bw:
			a = maxf(a, 1.0 - smoothstep(bw * 0.5, bw, bd))
			b = maxf(b, 0.38 + 0.34 * (1.0 - bd / maxf(bw, 0.001)))
		# The float at the base of each blade.
		if Vector2(uv.x - at.x, sy - at.y).length() < 0.13:
			a = 1.0
			b = 0.82
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A stone lantern (tōrō): foot, shaft, the lit fire-box with its window, a
## broad cap and a finial. Weathered granite, lit warm from inside the box.
func _fn_toro(uv: Vector2) -> Color:
	const AR := 1.69      # bake 130x220
	var sy := uv.y * AR
	var a := 0.0
	var col := Color(0, 0, 0)
	var granite := Color(0.60, 0.62, 0.58)
	# The foot.
	if sy > 1.10:
		if absf(uv.x) < 0.68:
			a = 1.0
			col = granite.darkened(0.35)
	# The shaft.
	elif sy > 0.10 and absf(uv.x) < 0.24:
		a = 1.0
		col = granite.darkened(0.15).lerp(granite.lightened(0.20),
			clampf(0.5 - uv.x * 2.4, 0.0, 1.0))
	# The platform the fire-box stands on.
	if sy > -0.06 and sy <= 0.16 and absf(uv.x) < 0.60:
		a = 1.0
		col = granite.darkened(0.10)
	# The fire-box, with a square window cut in it.
	if sy > -0.74 and sy <= -0.04 and absf(uv.x) < 0.46:
		a = 1.0
		col = granite.lerp(granite.lightened(0.30), clampf(0.5 - uv.x * 1.6, 0.0, 1.0))
		if absf(uv.x) < 0.26 and sy > -0.62 and sy < -0.16:
			col = Color(1.0, 0.78, 0.40)         # the lit opening
	# The cap: a wide flared roof with curled corners.
	if sy > -1.16 and sy <= -0.70:
		var t := (sy + 1.16) / 0.46
		var lift: float = 0.10 * pow(clampf((absf(uv.x) - 0.50) / 0.44, 0.0, 1.0), 2.0)
		if absf(uv.x) < lerpf(0.30, 0.94, t) and sy < -0.70 - lift:
			a = 1.0
			col = granite.darkened(0.28).lerp(granite.lightened(0.15), 1.0 - t)
	# The finial.
	if sy <= -1.14 and Vector2(uv.x / 0.16, (sy + 1.30) / 0.20).length() < 1.0:
		a = 1.0
		col = granite
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# Weathering: a mottle over the whole stone.
	var moss: float = clampf(sin(uv.x * 9.0) * sin(sy * 7.0), 0.0, 1.0)
	col = col.lerp(Color(0.34, 0.46, 0.30), moss * 0.22)
	return Color(col.r, col.g, col.b, a)

## A gorgonian sea fan: a fine branching mesh on a short trunk, broadside on.
func _fn_seafan_big(uv: Vector2) -> Color:
	const AR := 1.11      # bake 180x200
	var sy := uv.y * AR
	var a := 0.0
	if absf(uv.x) > 0.98:
		return Color(0, 0, 0, 0)
	# The fan's outline: a rounded triangle standing on a stem.
	var t := clampf((AR - sy) / (AR * 2.0), 0.0, 1.0)
	var span: float = 0.95 * sin(pow(t, 0.75) * PI * 0.92)
	if absf(uv.x) < span and sy < 0.90:
		# The mesh: two crossed families of branches, thinning outward.
		var u := uv.x / maxf(span, 0.01)
		var v := t
		var b1: float = absf(fposmod((u * 3.0 + v * 5.0), 1.0) - 0.5) * 2.0
		var b2: float = absf(fposmod((u * -3.0 + v * 5.0), 1.0) - 0.5) * 2.0
		var mesh: float = maxf(smoothstep(0.72, 1.0, b1), smoothstep(0.72, 1.0, b2))
		# Denser near the middle of the fan, open at the rim.
		a = mesh * (1.0 - smoothstep(0.72, 1.0, absf(u))) * smoothstep(0.02, 0.20, v)
	# The trunk and holdfast.
	if sy >= 0.60 and absf(uv.x) < lerpf(0.05, 0.22, clampf((sy - 0.60) / 0.50, 0.0, 1.0)):
		a = 1.0
	if a <= 0.05:
		return Color(0, 0, 0, 0)
	var b: float = 0.55 + 0.45 * clampf(0.5 - uv.x * 0.5, 0.0, 1.0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(a, 0.0, 1.0))

## Brain coral: a dome scored with meandering ridges.
func _fn_brain_coral(uv: Vector2) -> Color:
	const AR := 0.69      # bake 160x110
	var sy := uv.y / AR
	var d := Vector2(uv.x, (sy + 0.55) / 1.45).length()
	if d > 1.0 or sy > 0.62:
		return Color(0, 0, 0, 0)
	var a: float = 1.0 - smoothstep(0.90, 1.0, d)
	# The meanders: a wavy field scored across the dome.
	var wob: float = sin(uv.x * 7.0 + sin(sy * 5.0) * 2.4) + 0.6 * sin(sy * 9.0)
	var groove: float = 1.0 - smoothstep(0.0, 0.35, absf(wob))
	var lam: float = clampf(0.62 - uv.x * 0.42 - sy * 0.45, 0.0, 1.0)
	var b: float = lerpf(0.34, 1.0, lam)
	b *= 1.0 - groove * 0.45
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## Staghorn coral: a thicket of forking tubular branches.
func _fn_staghorn(uv: Vector2) -> Color:
	const AR := 1.27      # bake 150x190
	var sy := uv.y * AR
	# Bounding reject before any segment maths — the thicket never reaches the
	# top of the bake or past its outer trunks.
	if absf(uv.x) > 0.98 or sy < -1.42:
		return Color(0, 0, 0, 0)
	var p := Vector2(uv.x, sy)
	var a := 0.0
	var b := 0.5
	# Three trunks, each forking twice.
	for k in 3:
		var base := Vector2(-0.55 + 0.55 * float(k), 1.27)
		var mid := base + Vector2(0.10 - 0.10 * float(k), -0.85)
		var w0 := 0.11 - 0.015 * float(k)
		if _seg_dist(p, base, mid) < w0:
			a = 1.0
			b = 0.45 + 0.45 * clampf(0.5 - (p.x - base.x) * 3.0, 0.0, 1.0)
		for s_v in [-1.0, 1.0]:
			var s: float = s_v
			var tip := mid + Vector2(s * 0.34, -0.52)
			if _seg_dist(p, mid, tip) < w0 * 0.72:
				a = 1.0
				b = 0.50 + 0.40 * clampf(0.5 - s * 0.5, 0.0, 1.0)
			# The pale growing tips every acropora has.
			if (p - tip).length() < w0 * 0.9:
				a = 1.0
				b = 1.0
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## An anemone: a squat column crowned with a mass of tentacles, each with a
## paler tip. The tentacles radiate from the TOP of the column — measuring them
## from the bake centre (the first attempt) buried them in the column and left
## a cone.
func _fn_anemone(uv: Vector2) -> Color:
	const AR := 0.93      # bake 140x130
	var sy := uv.y / AR
	var a := 0.0
	var b := 0.5
	# The column, standing on the floor.
	if sy > 0.10 and absf(uv.x) < lerpf(0.26, 0.42, clampf((sy - 0.10) / 0.90, 0.0, 1.0)):
		a = 1.0
		b = 0.34 + 0.34 * clampf(0.5 - uv.x * 1.8, 0.0, 1.0)
	# The oral disc sits at the top of the column; tentacles fan from there.
	# Nothing in the crown reaches past ~1.05 from the mouth, so pixels beyond
	# that skip all eleven segment tests.
	var mouth := Vector2(0.0, 0.05)
	var oral := Vector2(uv.x, sy) - mouth
	if oral.length() > 1.05:
		if a <= 0.02:
			return Color(0, 0, 0, 0)
		return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)
	for k in 11:
		# A fan through the upper half, plus a couple that flop sideways.
		var ang: float = PI + PI * (float(k) + 0.5) / 11.0
		var len_k: float = 0.66 + 0.30 * fposmod(float(k) * 0.618, 1.0)
		var tip := Vector2(cos(ang) * len_k, sin(ang) * len_k * 0.80)
		var d := _seg_dist(oral, Vector2.ZERO, tip)
		var along := clampf((oral.length()) / maxf(len_k, 0.01), 0.0, 1.0)
		var w0: float = 0.058 * (1.0 - 0.40 * along)
		if d < w0:
			a = maxf(a, 1.0 - smoothstep(w0 * 0.5, w0, d))
			b = 0.44 + 0.30 * fposmod(float(k) * 0.37, 1.0)
			if (oral - tip).length() < w0 * 2.0:
				b = 1.0
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A paper mountain range. Two things make folded paper read as folded paper,
## and the first two attempts had neither:
##
##  * The peaks are TRIANGULAR. A gaussian hump is a hill; a crease is a straight
##    line, so a folded peak has flat faces meeting at a point.
##  * Each peak has exactly TWO faces, decided by which side of ITS OWN summit
##    the pixel is on. Taking the sign of a summed derivative (the obvious way)
##    flips several times between summits and stripes the whole range.
func _fn_paper_range(uv: Vector2) -> Color:
	# [summit x, summit height above the base line, half-width]
	var peaks := [Vector2(-0.62, 1.34), Vector2(0.04, 0.86), Vector2(0.68, 1.16)]
	var widths := [0.52, 0.40, 0.46]
	var base := 0.66
	var crest := base
	var owner := -1
	for i in peaks.size():
		var pk: Vector2 = peaks[i]
		var hw: float = widths[i]
		# A straight-sided tent, not a bell.
		var t: float = clampf(1.0 - absf(uv.x - pk.x) / hw, 0.0, 1.0)
		var y := base - pk.y * t
		if y < crest:
			crest = y
			owner = i
	if uv.y < crest:
		return Color(0, 0, 0, 0)
	# The face: left of this peak's summit is in shadow, right of it is lit.
	var lit := 0.42
	if owner >= 0:
		var pk2: Vector2 = peaks[owner]
		lit = 0.95 if uv.x > pk2.x else 0.56
	# The ridge crease — a hard bright line right along the fold.
	if uv.y < crest + 0.045:
		lit = 1.0
	# A snow face on the two tall peaks: a second crease part way down.
	if owner >= 0 and (peaks[owner] as Vector2).y > 1.0 and uv.y < crest + 0.30:
		lit = minf(lit + 0.26, 1.0)
	# The skirt, where the sheet folds back under itself.
	if uv.y > crest + 0.95:
		lit *= 0.66
	return Color(lit, lit, lit, 1.0)

## A folded paper crane in profile: the swept wings, the long neck and head, the
## tail, and the hard crease down the body.
func _fn_paper_crane(uv: Vector2) -> Color:
	const AR := 0.667     # bake 180x120
	var sy := uv.y / AR
	var p := Vector2(uv.x, sy)
	var a := 0.0
	var b := 0.0
	# The near wing: a long swept triangle above the body.
	if _in_tri(p, Vector2(-0.10, -0.10), Vector2(-0.95, -1.10), Vector2(0.62, -0.62)):
		a = 1.0
		b = 0.98
	# The far wing, dimmer, behind.
	if _in_tri(p, Vector2(-0.06, 0.02), Vector2(-0.70, 0.86), Vector2(0.66, 0.30)):
		a = 1.0
		b = 0.52
	# The body.
	if _in_tri(p, Vector2(-0.34, -0.18), Vector2(0.72, 0.06), Vector2(-0.20, 0.30)):
		a = 1.0
		b = 0.80
	# The neck and head, thrown forward.
	if _seg_dist(p, Vector2(-0.28, -0.10), Vector2(-1.00, -0.30)) < 0.09:
		a = 1.0
		b = 0.88
	if _in_tri(p, Vector2(-0.96, -0.36), Vector2(-1.15, -0.26), Vector2(-0.94, -0.18)):
		a = 1.0
		b = 0.94
	# The tail.
	if _in_tri(p, Vector2(0.66, -0.02), Vector2(1.10, -0.28), Vector2(0.70, 0.16)):
		a = 1.0
		b = 0.70
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(b, b, b, a)

## A dust pillar: a tall column of cold gas with a bulbous head and a ragged,
## eroded flank, thinning as it rises. The silhouette does all the work — a
## nebula's pillars read purely as dark shapes against lit gas.
func _fn_dust_pillar(uv: Vector2) -> Color:
	const AR := 2.0       # bake 130x260
	var sy := uv.y * AR
	var t := clampf((AR - sy) / (AR * 2.0), 0.0, 1.0)     # 0 base, 1 tip
	# The column narrows upward, with a swelling near the head.
	var hw: float = 0.92 * (1.0 - pow(t, 1.5) * 0.72)
	hw += 0.20 * exp(-pow((t - 0.74) * 5.0, 2.0))
	# Erosion: the flank is chewed at several scales.
	hw -= 0.10 * absf(sin(sy * 2.1)) + 0.06 * absf(sin(sy * 5.3 + 1.2))
	if absf(uv.x) > hw or t > 0.97:
		return Color(0, 0, 0, 0)
	var a: float = 1.0 - smoothstep(hw - 0.10, hw, absf(uv.x))
	a *= 1.0 - smoothstep(0.86, 0.97, t)
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, clampf(a, 0.0, 1.0))

## A pencil lying on its side: hex barrel, a sharpened cone, exposed lead, a
## ferrule and an eraser. Drawn along +x, so the host only has to rotate it.
func _fn_pencil(uv: Vector2) -> Color:
	# The bake is very wide; y is the barrel's thickness.
	#
	# A pencil is a CYLINDER, and the version before this shaded it as a flat
	# strip with one bright stripe near the top — so it read as a printed icon
	# of a pencil rather than an object lying on a page. Everything here is in
	# service of the round: a specular band that runs the whole length at a
	# fixed height, a terminator on the underside, and the hex facets crossing
	# both of them.
	var t := (uv.x + 1.0) * 0.5              # 0 = tip, 1 = eraser
	var col := Color(0, 0, 0)
	var a := 0.0
	var hh := 0.62
	# `f` is how far round the barrel a pixel sits: 0 on the lit ridge, 1 at the
	# silhouette edge. Everything below shades off it.
	var f: float = clampf(absf(uv.y) / hh, 0.0, 1.0)
	# Round shading, lit from above-left, and it never quite goes to black —
	# the page bounces light back into the underside.
	var lam: float = clampf(1.0 - pow(clampf((uv.y + 0.22) / 0.92, 0.0, 1.0), 1.5), 0.10, 1.0)
	var spec: float = pow(clampf(1.0 - absf(uv.y + 0.30) / 0.22, 0.0, 1.0), 1.6)
	# The hex facets: six flats round the barrel, so the shading STEPS.
	var facet: float = 1.0 - 0.10 * absf(sin((uv.y / hh) * PI * 1.5))
	if t < 0.085:
		# The exposed graphite: a dark cone, shiny where it has been used.
		var lt := t / 0.085
		if absf(uv.y) < hh * lerpf(0.06, 0.52, lt):
			a = 1.0
			col = Color(0.16, 0.16, 0.19).lerp(Color(0.46, 0.46, 0.52), spec * 0.9)
			col = col.lerp(Color(0.10, 0.10, 0.12), f * 0.5)
	elif t < 0.235:
		# The sharpened wood: a cone with the grain running along it, and the
		# scalloped ridges a blade sharpener leaves.
		var lt := (t - 0.085) / 0.150
		var cone: float = hh * lerpf(0.52, 1.0, pow(lt, 0.85))
		if absf(uv.y) < cone:
			a = 1.0
			var g: float = 0.86 + 0.10 * sin(uv.y * 22.0 + t * 30.0)
			col = Color(0.93, 0.82, 0.63) * g
			col = col.lerp(Color(0.62, 0.50, 0.34), f * 0.55)
			col = col.lerp(Color(1.0, 0.97, 0.90), spec * 0.55)
			# The facet scallops the sharpener cut into it.
			col = col.lerp(Color(0.74, 0.62, 0.44),
				clampf(sin(lt * PI * 5.0), 0.0, 1.0) * 0.18)
	elif t < 0.845:
		# The painted barrel.
		if absf(uv.y) < hh:
			a = 1.0
			col = Color(1.0, 0.78, 0.14)
			col = Color(col.r * lam * facet, col.g * lam * facet, col.b * lam * facet)
			col = col.lerp(Color(0.58, 0.40, 0.05), pow(f, 2.2) * 0.75)
			col = col.lerp(Color(1.0, 0.99, 0.88), spec * 0.75)
			# The lacquer edge where the paint stops, right at the wood.
			if t < 0.255:
				col = col.lerp(Color(0.80, 0.58, 0.10), 1.0 - smoothstep(0.235, 0.255, t))
	elif t < 0.925:
		# The ferrule, in brushed aluminium — brighter and harder than paint.
		if absf(uv.y) < hh * 1.03:
			a = 1.0
			col = Color(0.86, 0.88, 0.92)
			col = Color(col.r * lam, col.g * lam, col.b * lam)
			col = col.lerp(Color(0.34, 0.36, 0.42), pow(f, 1.7) * 0.85)
			col = col.lerp(Color(1, 1, 1), spec * 0.95)
			# Its crimp rings.
			if absf(fposmod((t - 0.845) * 22.0, 1.0) - 0.5) > 0.30:
				col = col.darkened(0.28)
	else:
		# The eraser: rubber, so it takes light softly and has no specular.
		var et := (t - 0.925) / 0.075
		if absf(uv.y) < hh * (1.0 - 0.30 * pow(clampf(et, 0.0, 1.0), 3.0)):
			a = 1.0
			col = Color(1.0, 0.60, 0.56)
			col = Color(col.r * lam, col.g * lam, col.b * lam)
			col = col.lerp(Color(0.72, 0.34, 0.34), pow(f, 1.8) * 0.55)
			col = col.lerp(Color(1.0, 0.86, 0.84), (1.0 - f) * 0.20)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(col.r, col.g, col.b, a)

## A paper plane in profile: the folded wing, the keel below it, and the crease.
func _fn_plane(uv: Vector2) -> Color:
	# Nose at the right, tail at the left.
	var a := 0.0
	var b := 0.0
	# The upper wing: a long triangle from the nose back to the tail's top.
	if _in_tri(uv, Vector2(0.95, 0.10), Vector2(-0.85, -0.62), Vector2(-0.80, 0.30)):
		a = 1.0
		b = 0.95
	# The keel hanging under it, in shadow.
	if _in_tri(uv, Vector2(0.95, 0.10), Vector2(-0.80, 0.30), Vector2(-0.55, 0.78)):
		a = 1.0
		b = 0.55
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# The centre crease catches a hard line of light.
	var crease := _seg_dist(uv, Vector2(0.95, 0.10), Vector2(-0.80, 0.30))
	b = maxf(b, (1.0 - smoothstep(0.0, 0.05, crease)) * 1.0)
	return Color(b, b, b, a)

## A cracked obsidian slab: a near-black glassy sheet with bright conchoidal
## fracture lines running through it and a lit upper edge.
func _fn_obsidian(uv: Vector2) -> Color:
	var col := Color(0.05, 0.06, 0.08)
	# Glass sheen across the top of the slab.
	col = col.lerp(Color(0.16, 0.22, 0.24), clampf(0.5 - uv.y * 0.9, 0.0, 1.0))
	# Fractures: a handful of long shallow arcs.
	var crack := 1e9
	for k in 5:
		var kx := -0.8 + 0.4 * float(k)
		var arc: float = absf(uv.y - (0.35 * sin((uv.x - kx) * 2.4 + float(k)) - 0.1 + float(k) * 0.02))
		crack = minf(crack, arc + absf(uv.x - kx) * 0.05)
	var line: float = 1.0 - smoothstep(0.01, 0.06, crack)
	col = col.lerp(Color(0.40, 0.85, 0.76), line * 0.75)
	# The top edge of the slab is a hard bright line — glass has an edge.
	col = col.lerp(Color(0.55, 0.80, 0.78), (1.0 - smoothstep(0.0, 0.10, absf(uv.y + 0.92))) * 0.6)
	return Color(col.r, col.g, col.b, 1.0)

## A candy cane: a striped rod with a hooked crook at the top.
func _fn_cane(uv: Vector2) -> Color:
	const AR := 2.83      # bake 60x170
	var sy := uv.y * AR
	var a := 0.0
	# The straight shaft.
	if sy > -1.30 and absf(uv.x - 0.30) < 0.42:
		a = 1.0
	# The crook: a half-ring at the top.
	var hook := Vector2(uv.x + 0.28, (sy + 1.72)).length()
	if absf(hook - 0.58) < 0.42 and sy < -1.20:
		a = 1.0
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# Helical stripes: a diagonal band pattern reads as a twist on a round rod.
	var band: float = fposmod((uv.x * 1.6 + sy * 1.05), 1.0)
	var white_stripe: bool = band < 0.5
	var b: float = 1.0 if white_stripe else 0.42
	# Round the rod: darker at its edges.
	b *= 0.72 + 0.28 * (1.0 - absf(uv.x - 0.30) / 0.42)
	return Color(clampf(b, 0.0, 1.0), clampf(b * (1.0 if white_stripe else 0.45), 0.0, 1.0),
		clampf(b * (1.0 if white_stripe else 0.48), 0.0, 1.0), a)

## A swirl lollipop: a disc with a spiral of colour wound into it.
func _fn_lollipop(uv: Vector2) -> Color:
	var r := uv.length()
	if r > 0.94:
		return Color(0, 0, 0, 0)
	var a: float = 1.0 - smoothstep(0.88, 0.94, r)
	var ang := atan2(uv.y, uv.x)
	# An Archimedean spiral: the band index depends on angle AND radius.
	var s: float = fposmod((ang / TAU) * 3.0 + r * 3.2, 1.0)
	var col := Color(1.0, 0.35, 0.55) if s < 0.34 \
		else (Color(1.0, 0.92, 0.98) if s < 0.67 else Color(0.45, 0.82, 1.0))
	# Sphere shading + a specular pop.
	var lam: float = clampf(0.55 - uv.x * 0.45 - uv.y * 0.5, 0.0, 1.0)
	col = col.darkened(0.35 * (1.0 - lam))
	col = col.lerp(Color(1, 1, 1), (1.0 - smoothstep(0.0, 0.28,
		Vector2(uv.x + 0.30, uv.y + 0.34).length())) * 0.7)
	return Color(col.r, col.g, col.b, a)

## A gumball machine: a glass globe full of sweets on a flared metal base.
func _fn_gumball(uv: Vector2) -> Color:
	const AR := 1.46      # bake 130x190
	var sy := uv.y * AR
	var col := Color(0, 0, 0)
	var a := 0.0
	# The globe.
	var g := Vector2(uv.x, sy + 0.62)
	if g.length() < 0.86:
		a = 1.0
		# The sweets inside: a lattice of coloured discs.
		var cell := Vector2(fposmod(uv.x * 4.2, 1.0) - 0.5, fposmod((sy + 0.62) * 4.2, 1.0) - 0.5)
		var idx := floorf(uv.x * 4.2) + floorf((sy + 0.62) * 4.2) * 3.0
		var pick: float = fposmod(idx * 0.37, 1.0)
		var ball := Color(1.0, 0.35, 0.42)
		if pick > 0.66:
			ball = Color(0.42, 0.80, 1.0)
		elif pick > 0.33:
			ball = Color(1.0, 0.86, 0.35)
		var inside: float = 1.0 - smoothstep(0.30, 0.44, cell.length())
		col = Color(0.90, 0.94, 1.0).lerp(ball, inside * 0.92)
		# Glass: a bright rim and a highlight.
		col = col.lerp(Color(1, 1, 1), (1.0 - smoothstep(0.70, 0.86, g.length())) * 0.0
			+ smoothstep(0.74, 0.86, g.length()) * 0.55)
		col = col.lerp(Color(1, 1, 1), (1.0 - smoothstep(0.0, 0.30,
			Vector2(uv.x + 0.34, sy + 0.94).length())) * 0.8)
	# The neck and the flared base.
	if sy > 0.22 and sy < 0.46 and absf(uv.x) < 0.34:
		a = 1.0
		col = Color(0.86, 0.20, 0.24)
	if sy >= 0.46:
		var t := (sy - 0.46) / 0.54
		if absf(uv.x) < lerpf(0.40, 0.86, t):
			a = 1.0
			col = Color(0.80, 0.16, 0.20).lerp(Color(0.52, 0.08, 0.12), t)
			# The chrome coin plate.
			if t < 0.30 and absf(uv.x) < 0.22:
				col = Color(0.86, 0.88, 0.92)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(col.r, col.g, col.b, a)

## A geode crystal: a tapering hexagonal prism with a pointed termination and
## visible internal facets.
func _fn_crystal(uv: Vector2) -> Color:
	var t := clampf((uv.y + 1.0) * 0.5, 0.0, 1.0)     # 0 = tip, 1 = root
	# A blunt hexagonal prism: it reaches full width fast and stays there. The
	# first version tapered all the way down, which grew a blade of grass.
	var hw: float = 0.94 * smoothstep(0.0, 0.20, t) * lerpf(0.82, 1.0, t)
	if absf(uv.x) > hw:
		return Color(0, 0, 0, 0)
	# HARD sides. A crystal is a cut solid, so its edges must not feather —
	# the soft edge is most of what made these read as foliage.
	var a: float = 1.0 - smoothstep(hw - 0.035, hw, absf(uv.x))
	# Three visible faces of the prism, at strongly separated brightnesses.
	var f := uv.x / maxf(hw, 0.01)
	var b: float = 0.26
	if f < -0.34:
		b = 0.62
	elif f < 0.22:
		b = 1.0
	else:
		b = 0.34
	# The termination: the pyramid facets at the tip are cut across the prism,
	# so they catch the light differently from the shaft below them.
	if t < 0.22:
		b = lerpf(1.0, b, t / 0.22) * 0.95 + 0.20
	# Hard vertical edge lines where the faces meet.
	b = maxf(b, (1.0 - smoothstep(0.0, 0.045, absf(f + 0.34))) * 0.95)
	b = maxf(b, (1.0 - smoothstep(0.0, 0.045, absf(f - 0.22))) * 0.75)
	# Internal flaws — a couple of bright veils inside the stone.
	b += (1.0 - smoothstep(0.0, 0.07, absf(t - 0.52 + f * 0.12))) * 0.28
	b += (1.0 - smoothstep(0.0, 0.05, absf(t - 0.74 - f * 0.10))) * 0.20
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A hard four-point glint with a long horizontal flare — the flash a facet
## throws, as distinct from a soft glow.
func _fn_star4_glint(uv: Vector2) -> Color:
	var ax := absf(uv.x)
	var ay := absf(uv.y)
	var h: float = (1.0 - smoothstep(0.0, 0.055, ay)) * (1.0 - smoothstep(0.06, 1.0, ax))
	var v: float = (1.0 - smoothstep(0.0, 0.055, ax)) * (1.0 - smoothstep(0.06, 0.72, ay))
	var core: float = 1.0 - smoothstep(0.0, 0.16, uv.length())
	var a := clampf(maxf(maxf(h, v), core), 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

## A fat cartoon cloud: three overlapping lobes with a flat base.
func _fn_cloud(uv: Vector2) -> Color:
	const AR := 0.5       # bake 160x80
	var sy := uv.y / AR
	var a := 0.0
	for l_v in [Vector3(-0.52, 0.20, 0.62), Vector3(0.06, -0.18, 0.86),
			Vector3(0.58, 0.24, 0.58)]:
		var l: Vector3 = l_v
		var d := Vector2(uv.x - l.x, (sy - l.y) * 0.55).length() / l.z
		a = maxf(a, 1.0 - smoothstep(0.86, 1.0, d))
	# A flat base — clouds in this idiom sit on a line.
	if sy > 0.62:
		a = 0.0
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# Softly shaded underneath.
	var b: float = 1.0 - clampf(sy * 0.22 + 0.10, 0.0, 0.35)
	return Color(b, b, b, a)

## A cat face peeking: ears, cheeks, closed happy eyes and a small mouth.
func _fn_cat(uv: Vector2) -> Color:
	const AR := 0.833     # bake 96x80
	var sy := uv.y / AR
	var a := 0.0
	# The head.
	var head := Vector2(uv.x, sy * 0.92).length() / 0.86
	if head < 1.0:
		a = 1.0 - smoothstep(0.92, 1.0, head)
	# Two triangular ears.
	for s_v in [-1.0, 1.0]:
		var s: float = s_v
		if _in_tri(Vector2(uv.x, sy), Vector2(s * 0.28, -0.62),
				Vector2(s * 0.80, -0.60), Vector2(s * 0.56, -1.15)):
			a = 1.0
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var b := 1.0
	# Closed, contented eyes: two downward arcs.
	for s_v in [-0.34, 0.34]:
		var s: float = s_v
		var e := Vector2(uv.x - s, (sy + 0.02) * 1.5)
		if absf(e.length() - 0.22) < 0.055 and sy < 0.02:
			b = 0.10
	# The nose and mouth.
	if Vector2(uv.x, (sy - 0.26) * 1.4).length() < 0.09:
		b = 0.25
	# Blush.
	for s_v in [-0.58, 0.58]:
		var s: float = s_v
		if Vector2(uv.x - s, (sy - 0.22) * 1.6).length() < 0.18:
			b = minf(b, 0.62)
	return Color(b, b, b, a)

## A pierced brass lantern: a domed cap, a six-sided body tapering to a finial,
## and star-shaped perforations that let the light through — the holes are cut
## into the SHADING, so the tint reads as brass and the cut-outs as bright.
func _fn_moroccan_lantern(uv: Vector2) -> Color:
	var a := 0.0
	var b := 0.55
	# The ring it hangs by.
	var ring := Vector2(uv.x, (uv.y + 0.90) * 1.6).length()
	if absf(ring - 0.11) < 0.035:
		a = 1.0
	# The cap: a small dome.
	if uv.y > -0.80 and uv.y < -0.52:
		var t := (uv.y + 0.80) / 0.28
		var hw := lerpf(0.10, 0.50, sqrt(t))
		a = maxf(a, 1.0 - smoothstep(hw - 0.05, hw, absf(uv.x)))
		b = 0.85
	# The body: a hexagonal lamp, widest at the shoulder, tapering to the base.
	if uv.y >= -0.52 and uv.y < 0.62:
		var t := (uv.y + 0.52) / 1.14
		var hw: float = 0.50 + 0.22 * sin(t * PI * 0.92)
		var body: float = 1.0 - smoothstep(hw - 0.05, hw, absf(uv.x))
		if body > a:
			a = body
			# Pierced starwork: a lattice of bright holes over dim brass.
			var star: float = absf(sin(uv.x * 13.0)) * absf(sin((uv.y + 0.5) * 11.0))
			b = lerpf(0.30, 1.0, smoothstep(0.45, 0.85, star))
			# Two solid bands, top and bottom of the cage.
			if absf(t - 0.10) < 0.05 or absf(t - 0.90) < 0.05:
				b = 0.75
	# The finial hanging under it.
	if uv.y >= 0.62 and uv.y < 0.92:
		var t := (uv.y - 0.62) / 0.30
		var hw := lerpf(0.16, 0.02, t)
		a = maxf(a, 1.0 - smoothstep(hw - 0.03, hw, absf(uv.x)))
		b = maxf(b, 0.7)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0),
		clampf(a, 0.0, 1.0))

## The lamp itself: a squat brass body with a long spout to the left, a curled
## handle to the right and a domed lid — the storybook oil lamp in silhouette.
func _fn_oil_lamp(uv: Vector2) -> Color:
	var a := 0.0
	var b := 0.75
	# The body: a flattened dome sitting on the sand.
	var body := Vector2(uv.x / 0.62, (uv.y - 0.30) / 0.85)
	if uv.y < 0.62:
		a = maxf(a, 1.0 - smoothstep(0.88, 1.0, body.length()))
	# The lid and its knob.
	if uv.y > -0.72 and uv.y < -0.34 and absf(uv.x) < 0.22:
		a = maxf(a, 1.0)
		b = 0.95
	if uv.y <= -0.72 and Vector2(uv.x, (uv.y + 0.82) * 1.6).length() < 0.13:
		a = 1.0
		b = 1.0
	# The spout: a taper running out to the left and lifting at the tip.
	var sx := (uv.x + 0.30) / -0.72        # 0 at the body, 1 at the tip
	if sx > 0.0 and sx < 1.0:
		var cy: float = 0.10 - 0.42 * sx * sx
		var hh := lerpf(0.24, 0.05, sx)
		a = maxf(a, 1.0 - smoothstep(hh - 0.05, hh, absf(uv.y - cy)))
	# The handle: an open loop off the right shoulder.
	var hc := Vector2(uv.x - 0.66, (uv.y - 0.02) * 1.15)
	if absf(hc.length() - 0.30) < 0.09 and uv.x > 0.42:
		a = maxf(a, 1.0)
		b = 0.6
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# Lit along the top of the belly.
	b *= lerpf(0.55, 1.0, clampf(0.55 - uv.y * 0.55, 0.0, 1.0))
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0),
		clampf(a, 0.0, 1.0))

## The genie: a broad folded-arm torso under a turban, tapering below the waist
## into a smoke tail that thins to nothing at the spout. Soft-edged throughout —
## he is vapour, so every boundary is a gradient, never a cut line.
func _fn_genie(uv: Vector2) -> Color:
	var a := 0.0
	var b := 0.8
	# The tail: a column that narrows to a wisp at the bottom of the bake.
	if uv.y > 0.10:
		var t := (uv.y - 0.10) / 0.90
		var hw: float = lerpf(0.42, 0.05, t * t) * (1.0 + 0.14 * sin(uv.y * 7.0))
		a = maxf(a, (1.0 - smoothstep(hw * 0.35, hw, absf(uv.x))) * (1.0 - t * 0.35))
	# The torso: a wide chest that narrows to the waist.
	if uv.y > -0.34 and uv.y <= 0.22:
		var t := (uv.y + 0.34) / 0.56
		var hw := lerpf(0.72, 0.34, t)
		a = maxf(a, 1.0 - smoothstep(hw * 0.72, hw, absf(uv.x)))
	# Folded arms across the chest — a darker bar so the pose reads.
	if absf(uv.y + 0.06) < 0.10 and absf(uv.x) < 0.66:
		b = 0.55
	# The head.
	var head := Vector2(uv.x, (uv.y + 0.56) * 1.25).length()
	if head < 0.30:
		a = maxf(a, 1.0 - smoothstep(0.20, 0.30, head))
		b = maxf(b, 0.95)
	# The turban and its jewel.
	if uv.y > -0.95 and uv.y < -0.62:
		var t := (uv.y + 0.95) / 0.33
		var hw: float = 0.16 + 0.22 * sin(t * PI * 0.8)
		if absf(uv.x) < hw:
			a = 1.0
			b = 0.7 + 0.3 * (0.5 + 0.5 * sin(uv.x * 22.0))
	if Vector2(uv.x, (uv.y + 0.80) * 1.4).length() < 0.06:
		b = 1.0
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0),
		clampf(a, 0.0, 1.0))

## An igloo: a snow-block dome with a low arched tunnel out the front. The
## block courses are cut into the shading (not the alpha) so the silhouette
## stays a clean dome while the surface still reads as stacked snow bricks.
## ASPECT NOTE for every bake in this file that has to look ROUND: uv runs
## -1..1 on both axes but the host draws it into a rect of size (w, h), so one
## uv-y unit is (h/w) times as long on screen as one uv-x unit. A circle on
## screen is therefore |(dx, dy * h/w)| — the metric each of these carries as
## its own constant. Getting that wrong is what turns a joystick ball into a
## wine glass.
## One peak's profile: 1 at the summit, 0 by wl to its left and wr to its right.
## A CONE with slightly hollow flanks, not a gaussian and not a quartic bump —
## both of those have a flat top, and a line of round-topped hills is exactly
## what the first pass of this range looked like. The two widths are what stops
## the summits reading as a row of tents.
##
## No exp() and no pow(): _peaks_tex evaluates the whole crest THREE times per
## COLUMN to find its own slope, so every term here is paid for four times over.
func _bump(x: float, c: float, wl: float, wr: float) -> float:
	var wd: float = wl if x < c else wr
	var t: float = clampf(absf(x - c) / wd, 0.0, 1.0)
	return (1.0 - t) * (1.0 - 0.30 * t)

## The crest line of the range at x, in the bake's uv.y. Three peaks plus a
## fourth walking off the right edge, over three octaves of broken ground so no
## flank is ever a straight line. The bumps are narrow on purpose — the rank is
## drawn about three times wider than tall, and a crest authored at natural
## proportions arrives on screen as rolling hills.
func _peak_crest(x: float) -> float:
	var c: float = 0.30
	c -= 1.00 * _bump(x, -0.66, 0.34, 0.26)
	c -= 0.62 * _bump(x, -0.10, 0.22, 0.30)
	c -= 0.92 * _bump(x, 0.52, 0.24, 0.34)
	c -= 0.46 * _bump(x, 1.02, 0.28, 0.22)
	c += 0.050 * sin(x * 8.5) + 0.025 * sin(x * 21.0) + 0.012 * sin(x * 47.0)
	return c

## A range of snow peaks, baked in REAL COLOUR (the host tints each rank for
## aerial perspective, so the shading has to live in here or both ranks come out
## as flat cut-outs). The moon stands to the right of the scene, so which way a
## flank is lit falls straight out of the sign of the crest's own slope; snow
## lies deep on the crests and runs down the gullies, and the rock under it
## stays night-dark.
##
## This is the ONE landmark in this file that does not go through _shape(), and
## the reason is measurable: the crest, its slope and the gully phase depend on
## uv.x ALONE, so a per-pixel Callable re-solves 240 columns of maths 120 times
## over — twelve _bump calls and fourteen sines per pixel. It made Arctic the
## most expensive cold build in the catalogue at 204 ms (Butterfly Grove, the
## previous worst, is 195 ms and was itself trimmed down to that). Solving each
## column once and filling down produces the same image for about a tenth of it.
func _peaks_tex() -> ImageTexture:
	var cached: ImageTexture = _shape_cache.get("snow_peaks")
	if cached != null:
		return cached
	const W := 240
	const H := 120
	const E := 0.012
	var crest := PackedFloat32Array()
	var lam := PackedFloat32Array()
	var depth := PackedFloat32Array()
	crest.resize(W)
	lam.resize(W)
	depth.resize(W)
	for x in W:
		var ux: float = float(x) / float(W - 1) * 2.0 - 1.0
		var c: float = _peak_crest(ux)
		crest[x] = c
		# uv.y grows downward, so a POSITIVE slope is ground turned to the right
		# — into the moon.
		var slope: float = (_peak_crest(ux + E) - _peak_crest(ux - E)) / (2.0 * E)
		lam[x] = clampf(0.5 + slope * 0.24, 0.0, 1.0)
		# Snow reaches further down the gullies than the ribs, and thins on the
		# steepest ground where it cannot hold.
		var gully: float = 0.5 + 0.5 * sin(ux * 31.0 + c * 5.0)
		depth[x] = 0.26 + 0.30 * gully - 0.06 * absf(slope)
	var rock_dark := Color(0.07, 0.10, 0.17)
	var rock_lit := Color(0.26, 0.31, 0.42)
	var snow_shade := Color(0.52, 0.65, 0.88)
	var snow_lit := Color(0.97, 0.99, 1.0)
	var white := Color(1, 1, 1)
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for x in W:
		var c: float = crest[x]
		var dep: float = depth[x]
		var rock := rock_dark.lerp(rock_lit, lam[x])
		var sn := snow_shade.lerp(snow_lit, smoothstep(0.12, 0.86, lam[x]))
		for y in H:
			var uy: float = float(y) / float(H - 1) * 2.0 - 1.0
			# The crest edge, and a foot that sinks into haze so a rank never
			# ends on a hard line even where the treeline does not cover it.
			var a: float = smoothstep(c - 0.010, c + 0.014, uy) 				* (1.0 - smoothstep(0.55, 1.0, uy))
			if a <= 0.02:
				continue                       # Image.create starts transparent
			var d: float = uy - c
			var snow: float = 1.0 - smoothstep(dep * 0.5, maxf(dep, 0.04), d)
			var col := rock.lerp(sn, snow)
			# Moonlight catching the very edge of the ridge.
			col = col.lerp(white, (1.0 - smoothstep(0.0, 0.030, d)) * 0.5)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_shape_cache["snow_peaks"] = tex
	return tex

## The village house, baked in real colour for the same reason the snowman
## beside it is: the host tints it plain white, so every value here is the value
## that lands. It reads from the back forward — chimney, then the wall (whose
## top edge IS the roof pitch, which is what gives it a gable instead of a gap),
## the door and its wreath, two lit windows, and finally the roof: plank, a deep
## load of snow, and icicles hanging off the eaves.
func _fn_lodge(uv: Vector2) -> Color:
	const AR := 0.95	  # bake 180x171 — see the ASPECT NOTE
	const FOOT := 0.78	  # the snow line the house stands on
	var sy := uv.y * AR
	if sy > FOOT:
		return Color(0, 0, 0, 0)
	# The pitch. Everything above the walls is measured off this one line.
	var roof: float = -0.64 + absf(uv.x) * 0.6444
	var col := Color(0, 0, 0)
	var a := 0.0
	# --- The chimney, drawn first so the roof crosses in front of it ---
	if uv.x > 0.30 and uv.x < 0.47 and sy > -0.88 and sy < -0.18:
		a = 1.0
		col = Color(0.17, 0.14, 0.14)
		if fposmod(sy * 26.0, 1.0) < 0.14:
			col = col.lerp(Color(0.09, 0.07, 0.07), 0.7)
		# The moon reaches its right cheek.
		col = col.lerp(Color(0.32, 0.29, 0.30),
			clampf((uv.x - 0.30) / 0.17, 0.0, 1.0) * 0.45)
	if uv.x > 0.27 and uv.x < 0.50 and sy > -0.955 and sy <= -0.86:
		a = 1.0
		col = Color(0.92, 0.96, 1.0).lerp(Color(0.62, 0.75, 0.94),
			smoothstep(-0.955, -0.86, sy))
	# --- The walls, running right up under the pitch (so the gable is free) ---
	if absf(uv.x) < 0.62 and sy >= roof:
		a = 1.0
		col = Color(0.20, 0.145, 0.115)
		# Log courses: a dark seam, then the round of the log above it.
		var course: float = fposmod(sy * 11.0, 1.0)
		col = col.lerp(Color(0.06, 0.045, 0.04),
			(1.0 - smoothstep(0.0, 0.14, course)) * 0.9)
		col = col.lerp(Color(0.27, 0.21, 0.17),
			(1.0 - smoothstep(0.14, 0.55, course)) * 0.35)
		col = col.lerp(Color(0.34, 0.30, 0.28),
			clampf(uv.x * 0.5 + 0.5, 0.0, 1.0) * 0.30)
	# The lit attic window in the gable.
	var gw := Vector2(uv.x, (sy + 0.40) * 1.05).length()
	if gw < 0.085 and sy < roof + 0.60:
		a = 1.0
		col = Color(0.94, 0.62, 0.24).lerp(Color(1.0, 0.92, 0.64),
			1.0 - smoothstep(0.0, 0.085, gw))
		if absf(uv.x) < 0.013:
			col = Color(0.12, 0.09, 0.07)
	# --- The door, and the wreath hanging on it ---
	if absf(uv.x) < 0.115 and sy > 0.26:
		a = 1.0
		col = Color(0.12, 0.09, 0.08)
		if fposmod(uv.x * 9.0, 1.0) < 0.10:
			col = col.lerp(Color(0.06, 0.04, 0.04), 0.8)
		# Light leaking round the frame.
		col = col.lerp(Color(1.0, 0.66, 0.26),
			smoothstep(0.085, 0.115, absf(uv.x)) * 0.5)
	var wr := Vector2(uv.x, sy - 0.42).length()
	if wr > 0.050 and wr < 0.096:
		a = 1.0
		var ang: float = atan2(sy - 0.42, uv.x)
		col = Color(0.13, 0.30, 0.16).lerp(Color(0.23, 0.47, 0.25),
			0.5 + 0.5 * sin(ang * 22.0))
		if fposmod(ang * 5.0 / TAU + 0.5, 1.0) < 0.12:
			col = Color(0.86, 0.20, 0.22)
	# --- The two lit windows ---
	for wx_v in [-0.34, 0.34]:
		var wx: float = wx_v
		var dx: float = absf(uv.x - wx)
		var dy: float = absf(sy - 0.24)
		if dx > 0.160 or dy > 0.145:
			continue
		a = 1.0
		if dx > 0.135 or dy > 0.120:
			col = Color(0.10, 0.08, 0.07)	  # the frame
			continue
		# The glass: hot through the middle, falling off toward the corners,
		# with the mullion cross drawn back over the top of it.
		var fall: float = 1.0 - clampf(
			Vector2(dx / 0.135, dy / 0.120).length(), 0.0, 1.0)
		col = Color(0.92, 0.58, 0.20).lerp(Color(1.0, 0.93, 0.66),
			smoothstep(0.05, 0.85, fall))
		if dx < 0.016 or dy < 0.014:
			col = Color(0.13, 0.10, 0.08)
	# --- The roof: plank, snow load, icicles ---
	if absf(uv.x) < 0.92:
		if sy >= roof and sy < roof + 0.055:
			a = 1.0
			col = Color(0.09, 0.07, 0.07)
		var s: float = sin(uv.x * 24.0)
		var ic: float = 0.075 * maxf(s, 0.0) * maxf(s, 0.0)
		if sy >= roof + 0.055 and sy < roof + 0.055 + ic:
			a = 1.0
			col = Color(0.80, 0.90, 1.0)
		var load: float = 0.135 + 0.022 * sin(uv.x * 15.0)
		if sy < roof and sy >= roof - load:
			a = 1.0
			# Lit along the top, blue underneath: the light is the sky.
			col = Color(0.99, 1.0, 1.0).lerp(Color(0.55, 0.69, 0.92),
				smoothstep(0.0, 1.0, (sy - (roof - load)) / maxf(load, 0.01)))
	# --- The drift banked against the house ---
	# It carries its OWN alpha and runs wider than the walls, because a drift
	# painted only where the building already is comes out as the bottom third of
	# the building painted white — a hard-edged white box, which is exactly what
	# the first pass looked like.
	var dtop: float = 0.66 + 0.04 * sin(uv.x * 5.5 + 1.2) - 0.03 * absf(uv.x)
	if sy > dtop:
		var side: float = 1.0 - smoothstep(0.55, 0.92, absf(uv.x))
		var deep: float = smoothstep(dtop, dtop + 0.10, sy)
		var ea: float = clampf(side * deep, 0.0, 1.0)
		if ea > 0.02:
			# Bright along the crown where the sky reaches it, blue in the
			# shadow underneath — the same read as the snow on the roof.
			var dc := Color(0.94, 0.97, 1.0).lerp(Color(0.58, 0.70, 0.90), deep)
			col = dc if a <= 0.02 else col.lerp(dc, ea)
			a = maxf(a, ea)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0))

## The village church: a stone tower under a tall shingled spire, a lit belfry
## and a lit window, with a cross on top. Baked in real colour like the houses
## around it. It is the tallest thing standing on the snow line, which is the
## only reason the village reads as a village and not as a row of huts.
func _fn_steeple(uv: Vector2) -> Color:
	const AR := 1.75	  # bake 80x140 — see the ASPECT NOTE
	const FOOT := 1.55
	var sy := uv.y * AR
	if sy > FOOT:
		return Color(0, 0, 0, 0)
	var col := Color(0, 0, 0)
	var a := 0.0
	# The moon is off to the right, so a right-facing face is the lit one.
	var lit: float = clampf(0.5 + uv.x * 1.1, 0.0, 1.0)
	var stone := Color(0.13, 0.13, 0.16).lerp(Color(0.34, 0.34, 0.38), lit)
	var shingle := Color(0.09, 0.10, 0.14).lerp(Color(0.26, 0.28, 0.34), lit)
	var snow := Color(0.62, 0.74, 0.94).lerp(Color(0.97, 0.99, 1.0), lit)
	var warm := Color(1.0, 0.80, 0.40)
	# --- The cross ---
	if (absf(uv.x) < 0.055 and sy > -1.72 and sy < -1.42) \
			or (absf(sy + 1.635) < 0.032 and absf(uv.x) < 0.17):
		a = 1.0
		col = stone
	# --- The spire: a tall triangle, snow lying along its windward edge ---
	if sy > -1.40 and sy < -0.42:
		var hw: float = 0.46 * (sy + 1.40) / 0.98
		if absf(uv.x) < hw:
			a = 1.0
			col = shingle
			# Shingle courses running across the pitch.
			if fposmod(sy * 9.0, 1.0) < 0.16:
				col = col.lerp(Color(0.05, 0.06, 0.09), 0.7)
			# Snow holds on the left flank, out of the wind.
			var edge: float = (-uv.x - hw * 0.55) / maxf(hw * 0.45, 0.01)
			if edge > 0.0:
				col = col.lerp(snow, clampf(edge, 0.0, 1.0) * 0.85)
	# --- The eaves, with their own load of snow ---
	if sy >= -0.46 and sy < -0.34 and absf(uv.x) < 0.56:
		a = 1.0
		col = snow.lerp(Color(0.55, 0.68, 0.90), smoothstep(-0.46, -0.34, sy))
	if sy >= -0.34 and sy < -0.27 and absf(uv.x) < 0.52:
		a = 1.0
		col = shingle
	# --- The tower ---
	if sy >= -0.27 and absf(uv.x) < 0.40:
		a = 1.0
		col = stone
		# Coursed masonry.
		if fposmod(sy * 7.0, 1.0) < 0.10:
			col = col.lerp(Color(0.06, 0.06, 0.08), 0.8)
	# --- The belfry: a tall arched opening with the bell lit behind it ---
	# Boxed before it is solved, like every other part here - the length() calls
	# below were being run for the whole tower.
	if absf(uv.x) < 0.155 and absf(sy + 0.02) < 0.30:
		a = 1.0
		col = Color(0.05, 0.05, 0.07)
		# The bell, catching the light from inside.
		if Vector2(uv.x, (sy + 0.02) * 1.3).length() < 0.10:
			col = warm.lerp(Color(0.55, 0.38, 0.16), 0.45)
	# --- The lit window, lower down ---
	if absf(uv.x) < 0.145 and absf(sy - 0.78) < 0.24:
		a = 1.0
		var wd: float = Vector2(uv.x / 0.145, (sy - 0.78) / 0.24).length()
		col = warm.lerp(Color(1.0, 0.93, 0.68), 1.0 - clampf(wd, 0.0, 1.0))
		if absf(uv.x) < 0.018 or absf(sy - 0.78) < 0.020:
			col = Color(0.10, 0.09, 0.08)
	# --- The door ---
	if absf(uv.x) < 0.135 and sy > 1.16:
		a = 1.0
		col = Color(0.10, 0.09, 0.09)
		col = col.lerp(warm, smoothstep(0.105, 0.135, absf(uv.x)) * 0.45)
	# --- The drift banked against the foot, with its own alpha ---
	var dtop: float = 1.34 + 0.05 * sin(uv.x * 6.0)
	if sy > dtop:
		var side: float = 1.0 - smoothstep(0.34, 0.62, absf(uv.x))
		var deep: float = smoothstep(dtop, dtop + 0.13, sy)
		var ea: float = clampf(side * deep, 0.0, 1.0)
		if ea > 0.02:
			var dc := Color(0.94, 0.97, 1.0).lerp(Color(0.58, 0.70, 0.90), deep)
			col = dc if a <= 0.02 else col.lerp(dc, ea)
			a = maxf(a, ea)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0))

## A wrapped present: a box with a lid, a ribbon cross and a bow. Baked in VALUE
## only (paper bright, ribbon darker, bow brightest) so one bake serves the whole
## pile and the host tints each box its own colour.
func _fn_gift(uv: Vector2) -> Color:
	const AR := 0.909	  # bake 44x40
	var sy := uv.y * AR
	var a := 0.0
	var b := 0.0
	# The box, lit down its left face.
	if absf(uv.x) < 0.72 and sy > -0.30 and sy < 0.80:
		a = 1.0
		b = lerpf(1.0, 0.62, clampf(uv.x * 0.5 + 0.5, 0.0, 1.0))
	# The lid, a shade brighter and a shade wider.
	if absf(uv.x) < 0.80 and sy >= -0.46 and sy <= -0.30:
		a = 1.0
		b = lerpf(1.0, 0.74, clampf(uv.x * 0.5 + 0.5, 0.0, 1.0))
	# The ribbon: down the front and round the middle.
	if a > 0.02 and (absf(uv.x) < 0.13 or absf(sy - 0.20) < 0.09):
		b *= 0.52
	# The bow: two loops and a knot.
	for lx_v in [-0.21, 0.21]:
		var lx: float = lx_v
		if Vector2((uv.x - lx) / 0.17, (sy + 0.60) / 0.13).length() < 1.0:
			a = 1.0
			b = 0.88
	if Vector2(uv.x / 0.09, (sy + 0.50) / 0.07).length() < 1.0:
		a = 1.0
		b = 0.70
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(b, b, b, a)

## A sleigh and its team, in profile and in silhouette — the host tints the whole
## sprite one dim colour, so this is an alpha MASK and every value in it is 1.0.
## Profile is not a style choice: a reindeer seen from any other angle is a dog
## with a shrub on its head (the crane learned this the hard way — see the
## authoring notes on _fn_bfly_fairy and the origami bird).
func _fn_sleigh(uv: Vector2) -> Color:
	const AR := 0.4933    # bake 150x74 - see the ASPECT NOTE
	var sy := uv.y * AR
	var p := Vector2(uv.x, sy)
	var a := 0.0
	# --- The team: two deer, the lead one further forward -------------------
	# EVERY part here is bounding-boxed before its mask is solved. Without that
	# each pixel of the bake runs thirty-odd segment distances for parts that
	# are nowhere near it, which measured as +100 ms on Arctic's cold build and
	# put it back at the worst in the catalogue. Same fix, same reason, as the
	# origami crane's per-fold boxes.
	if sy > -0.45 and sy < 0.40:
		for cx_v in [-0.58, -0.10]:
			var cx: float = cx_v
			if uv.x < cx - 0.52 or uv.x > cx + 0.30:
				continue
			# Barrel.
			if Vector2((uv.x - cx) / 0.20, (sy - 0.06) / 0.105).length() < 1.0:
				a = 1.0
			# Legs, below the barrel only.
			if sy > 0.10:
				for l_v in [Vector2(cx - 0.11, 0.15), Vector2(cx + 0.12, 0.15)]:
					var l: Vector2 = l_v
					if _seg_dist(p, l, Vector2(l.x + 0.05, 0.35)) < 0.022:
						a = 1.0
			# Tail.
			if sy < 0.06 and uv.x > cx + 0.14:
				if _seg_dist(p, Vector2(cx + 0.19, 0.02), Vector2(cx + 0.25, -0.03)) < 0.020:
					a = 1.0
			# Head end: neck, skull, muzzle, antlers.
			if sy < 0.04 and uv.x < cx - 0.10:
				if _seg_dist(p, Vector2(cx - 0.15, 0.00), Vector2(cx - 0.27, -0.15)) < 0.042:
					a = 1.0
				if Vector2((uv.x - (cx - 0.31)) / 0.080, (sy + 0.175) / 0.050).length() < 1.0:
					a = 1.0
				if _seg_dist(p, Vector2(cx - 0.33, -0.17), Vector2(cx - 0.40, -0.16)) < 0.026:
					a = 1.0
				if sy < -0.14:
					for s_v in [-1.0, 1.0]:
						var sd: float = s_v
						var root := Vector2(cx - 0.30 + sd * 0.03, -0.21)
						var tip := Vector2(cx - 0.34 + sd * 0.10, -0.355)
						if _seg_dist(p, root, tip) < 0.016:
							a = 1.0
						var mid := tip.lerp(root, 0.45)
						if _seg_dist(p, mid, mid + Vector2(-0.07, -0.07)) < 0.013:
							a = 1.0
						if _seg_dist(p, tip, tip + Vector2(-0.06, -0.05)) < 0.012:
							a = 1.0
	# --- The traces, running back from the team to the sleigh ---------------
	if absf(sy - 0.045) < 0.06:
		if _seg_dist(p, Vector2(-0.02, 0.03), Vector2(0.46, 0.08)) < 0.011:
			a = 1.0
		if _seg_dist(p, Vector2(-0.42, 0.02), Vector2(-0.02, 0.04)) < 0.011:
			a = 1.0
	# --- The sleigh: a boat with a high back and a prow that curls forward ---
	if uv.x > 0.28:
		if uv.x < 1.0 and uv.x > 0.46:
			var t: float = (uv.x - 0.46) / 0.54
			var top: float = -0.02 - 0.20 * smoothstep(0.35, 1.0, t)
			if sy > top and sy < 0.26:
				a = 1.0
		if sy < 0.06 and uv.x < 0.52:
			if _seg_dist(p, Vector2(0.47, 0.02), Vector2(0.38, -0.12)) < 0.035:
				a = 1.0
		if sy > 0.16:
			if _seg_dist(p, Vector2(0.40, 0.32), Vector2(1.02, 0.32)) < 0.022:
				a = 1.0
			if _seg_dist(p, Vector2(0.40, 0.32), Vector2(0.33, 0.22)) < 0.020:
				a = 1.0
			for sx_v in [0.56, 0.92]:
				var sx: float = sx_v
				if absf(uv.x - sx) < 0.04 						and _seg_dist(p, Vector2(sx, 0.32), Vector2(sx, 0.20)) < 0.018:
					a = 1.0
		# The driver, and the sack behind him.
		if sy < -0.02 and uv.x > 0.58:
			if Vector2((uv.x - 0.70) / 0.085, (sy + 0.20) / 0.10).length() < 1.0:
				a = 1.0
			if Vector2((uv.x - 0.70) / 0.070, (sy + 0.315) / 0.045).length() < 1.0:
				a = 1.0
			if Vector2((uv.x - 0.90) / 0.105, (sy + 0.14) / 0.10).length() < 1.0:
				a = 1.0
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

## A snowman: three stacked balls with cold blue shadow sides, a coal face and
## buttons, a carrot nose, twiggy arms with branched fingers, and a bucket hat
## tipped over one eye. Colour-baked for the same reason the house is.
func _fn_snowman(uv: Vector2) -> Color:
	const AR := 1.533     # bake 150x230, drawn at h = 1.533 * w — see the ASPECT NOTE
	var lit := Color(1.00, 0.99, 0.98)
	var shade := Color(0.50, 0.65, 0.84)
	var deep := Color(0.30, 0.44, 0.66)
	var coal := Color(0.11, 0.12, 0.16)
	var wool := Color(0.80, 0.20, 0.28)
	var wool_d := Color(0.58, 0.12, 0.20)
	var col := Color(0, 0, 0)
	var a := 0.0
	# Screen-space y, so every round thing below is measured in the same units
	# as x and actually comes out round.
	var sy := uv.y * AR
	# --- Twig arms, behind the body ---
	for s_v in [-1.0, 1.0]:
		var s: float = s_v
		var root := Vector2(s * 0.24, 0.04)
		var tip := Vector2(s * 0.95, -0.26)
		var p := Vector2(uv.x, sy)
		var arm := _seg_dist(p, root, tip)
		var branch: float = minf(
			_seg_dist(p, tip, tip + Vector2(s * 0.14, -0.16)),
			_seg_dist(p, tip, tip + Vector2(s * 0.16, 0.06)))
		var w: float = minf(arm, branch)
		if w < 0.030:
			a = 1.0 - smoothstep(0.020, 0.030, w)
			col = Color(0.38, 0.26, 0.18)
	# --- The three balls ---
	# Centre y is in SCREEN units; each ball rests on the one below with a
	# little overlap, the way rolled snow actually stacks.
	for v_v in [Vector3(0.0, 0.92, 0.60), Vector3(0.0, 0.10, 0.455),
			Vector3(0.0, -0.56, 0.315)]:
		var v: Vector3 = v_v
		var n := Vector2((uv.x - v.x) / v.z, (sy - v.y) / v.z)
		var d := n.length()
		if d >= 1.0:
			continue
		var m: float = 1.0 - smoothstep(0.955, 1.0, d)
		if m <= a and a > 0.5:
			continue
		a = maxf(a, m)
		# Sphere shading: a low sun from the upper left, cold sky bounce above,
		# and a faint bright rim on the shadow side so the ball separates from
		# the sky behind it.
		var nz: float = sqrt(maxf(0.0, 1.0 - d * d))
		var lam: float = clampf(n.x * -0.50 + n.y * -0.60 + nz * 0.62, 0.0, 1.0)
		var c := shade.lerp(lit, smoothstep(0.02, 0.90, lam))
		c = c.lerp(Color(0.80, 0.88, 0.99), clampf(-n.y * 0.5 + 0.5, 0.0, 1.0) * 0.16)
		c = c.lerp(deep, smoothstep(0.90, 1.0, d) * 0.45)
		col = c
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# --- The scarf: baked in, so it actually wraps the neck ---
	# A band round the join between head and body, with a knot at one side.
	var band_y := -0.20
	if absf(sy - band_y) < 0.085 and absf(uv.x) < 0.50:
		var t := (sy - band_y) / 0.085
		col = wool.lerp(wool_d, clampf(t * 0.5 + 0.5, 0.0, 1.0))
		# Knit ribbing.
		if fposmod(uv.x * 26.0, 1.0) < 0.42:
			col = col.lerp(wool_d, 0.35)
		a = 1.0
	if Vector2(uv.x - 0.22, (sy - band_y - 0.02)).length() < 0.10:
		col = wool
		a = 1.0
	# --- The top hat ---
	var hy := sy + 0.86
	var hx: float = uv.x + hy * 0.24
	if hy > -0.44 and hy < -0.02 and absf(hx) < 0.26:
		col = Color(0.19, 0.20, 0.26)
		# A sheen down the left of the crown.
		col = col.lerp(Color(0.34, 0.36, 0.44), clampf(0.5 - hx * 2.2, 0.0, 1.0) * 0.5)
		a = 1.0
	if absf(hy + 0.005) < 0.045 and absf(hx) < 0.44:
		col = Color(0.13, 0.14, 0.19)
		a = 1.0
	# The hat band, matching the scarf.
	if hy > -0.15 and hy < -0.06 and absf(hx) < 0.265:
		col = wool_d
	# --- The face ---
	# Coal eyes with a catchlight each.
	for s_v in [-0.115, 0.115]:
		var s: float = s_v
		var e := Vector2(uv.x - s, sy + 0.66)
		if e.length() < 0.052:
			col = coal
			if Vector2(e.x + 0.018, e.y + 0.018).length() < 0.018:
				col = Color(0.55, 0.60, 0.68)
	# A smile of small coal lumps, curving with the face.
	for i in 5:
		var f := (float(i) - 2.0) / 2.0
		var m := Vector2(f * 0.155, -0.44 + f * f * 0.075)
		if Vector2(uv.x - m.x, sy - m.y).length() < 0.032:
			col = coal
	# The carrot nose, tapering to a point with segment lines.
	var cx := (uv.x - 0.02) / 0.34
	if cx > 0.0 and cx < 1.0:
		var ch := lerpf(0.052, 0.004, cx)
		if absf(sy + 0.545 - cx * 0.05) < ch:
			col = Color(0.95, 0.52, 0.14)
			col = col.lerp(Color(0.72, 0.34, 0.08), clampf((sy + 0.545) * 6.0 + 0.3, 0.0, 1.0) * 0.5)
			if fposmod(cx * 7.0, 1.0) < 0.16:
				col = col.lerp(Color(0.99, 0.72, 0.36), 0.6)
			a = 1.0
	# Coal buttons down the middle ball.
	for by_v in [-0.02, 0.16, 0.34]:
		var by: float = by_v
		if Vector2(uv.x, sy - by).length() < 0.048:
			col = coal
	return Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0))

## A snow-laden fir: stacked boughs with white caps on their upper edges,
## on a short dark trunk.
func _fn_fir(uv: Vector2) -> Color:
	var a := 0.0
	var col := Color(0.20, 0.34, 0.30)
	# The trunk.
	if uv.y > 0.62 and absf(uv.x) < 0.07:
		a = 1.0
		col = Color(0.26, 0.20, 0.17)
	# Three tiers of boughs, each a triangle wider than the one above it.
	for i in 3:
		var top: float = -0.98 + float(i) * 0.52
		var bot: float = top + 0.78
		if uv.y < top or uv.y > bot:
			continue
		var t := (uv.y - top) / (bot - top)
		var hw: float = lerpf(0.04, 0.30 + float(i) * 0.26, t)
		# A ragged edge so the bough is foliage, not a paper triangle.
		hw -= 0.03 * absf(sin(uv.y * 42.0))
		if absf(uv.x) < hw:
			a = 1.0
			# Snow lies on the top third of every tier; needles below it.
			var snow: float = 1.0 - smoothstep(0.10, 0.34, t)
			col = Color(0.18, 0.31, 0.28).lerp(Color(0.96, 0.99, 1.0), snow * 0.92)
			# Shade the right-hand side of each bough.
			col = col.lerp(Color(0.13, 0.22, 0.24), clampf(uv.x / maxf(hw, 0.01), 0.0, 1.0) * 0.35)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(col.r, col.g, col.b, a)

## A banded gas giant: latitude cloud belts, a great storm oval below the
## equator, limb darkening at the edge and a terminator shading the right-hand
## limb into night (the deep field is lit from the left).
func _fn_gas_giant(uv: Vector2) -> Color:
	var r := uv.length()
	var a := 1.0 - smoothstep(0.94, 1.0, r)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# Cloud belts: bands of alternating brightness running with latitude, warped
	# a little so they never look like a barcode.
	var lat: float = uv.y + 0.05 * sin(uv.x * 3.1)
	var belt: float = 0.5 + 0.5 * sin(lat * 11.0)
	var b: float = lerpf(0.62, 1.0, belt * 0.55 + 0.45)
	# The storm — a bright oval in the southern belts.
	var storm := Vector2((uv.x + 0.30) * 1.5, (uv.y - 0.26) * 2.6).length()
	b = lerpf(b, 1.0, (1.0 - smoothstep(0.32, 0.62, storm)) * 0.55)
	# Terminator + limb darkening.
	var lit: float = clampf(0.5 - uv.x * 0.72, 0.0, 1.0)
	b *= lerpf(0.18, 1.0, smoothstep(0.05, 0.75, lit))
	b *= lerpf(0.55, 1.0, 1.0 - smoothstep(0.55, 1.0, r))
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A small rocky world: a cratered disc lit from the left, most of its right
## side already in shadow, so it reads as a body in sunlight rather than a dot.
func _fn_rock_planet(uv: Vector2) -> Color:
	var r := uv.length()
	var a := 1.0 - smoothstep(0.93, 1.0, r)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var b := 0.85
	# A handful of craters, each a soft dark disc with a bright rim.
	for c_v in [Vector3(-0.30, -0.24, 0.26), Vector3(0.12, 0.30, 0.20),
			Vector3(-0.10, 0.02, 0.14), Vector3(0.34, -0.34, 0.12)]:
		var c: Vector3 = c_v
		var d := Vector2(uv.x - c.x, uv.y - c.y).length() / c.z
		b -= (1.0 - smoothstep(0.7, 1.0, d)) * 0.22
		b += (1.0 - smoothstep(0.05, 0.35, absf(d - 1.0))) * 0.12
	var lit: float = clampf(0.5 - uv.x * 0.85, 0.0, 1.0)
	b *= lerpf(0.10, 1.0, smoothstep(0.02, 0.70, lit))
	b *= lerpf(0.6, 1.0, 1.0 - smoothstep(0.6, 1.0, r))
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a)

## A planetary ring seen face-on — the host squashes it into its tilt. Fine
## concentric ringlets with a wide gap a third of the way out, fading at both
## the inner and outer edges so it never ends on a hard line.
func _fn_planet_ring(uv: Vector2) -> Color:
	var r := uv.length()
	if r < 0.56 or r > 0.99:
		return Color(0, 0, 0, 0)
	var t := (r - 0.56) / 0.43
	# Fade in off the inner edge and out at the outer.
	var a: float = smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.82, 1.0, t))
	# The division — a clean dark gap through the middle of the system.
	a *= 1.0 - (1.0 - smoothstep(0.06, 0.14, absf(t - 0.42))) * 0.92
	# Ringlet structure.
	a *= 0.62 + 0.38 * (0.5 + 0.5 * sin(t * 46.0))
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var b: float = 0.80 + 0.20 * (0.5 + 0.5 * sin(t * 46.0))
	return Color(b, b, b, clampf(a, 0.0, 1.0))

## A ferris-wheel chair: a swing seat on a yoke. Two hanger arms come down from
## the pivot to a scalloped canopy, under which sits an open car — back rest,
## seat slab, a safety bar across the front and a valance skirt below. Shaded so
## the canopy catches the light and the footwell falls into shadow.
func _fn_cabin(uv: Vector2) -> Color:
	var a := 0.0
	var b := 0.7
	# The yoke: two arms splaying down from the pivot to the canopy corners.
	for s_v in [-1.0, 1.0]:
		var s: float = s_v
		var arm := _seg_dist(uv, Vector2(0.0, -0.98), Vector2(s * 0.58, -0.46))
		if arm < 0.075:
			a = maxf(a, 1.0 - smoothstep(0.048, 0.075, arm))
			b = 0.55
	# The canopy: a shallow arch with a scalloped hem.
	if uv.y > -0.62 and uv.y < -0.24:
		var t := (uv.y + 0.62) / 0.38
		var hw: float = 0.60 + 0.20 * sin(t * PI * 0.85)
		var scallop: float = 0.03 * absf(sin(uv.x * 11.0))
		if absf(uv.x) < hw - scallop:
			a = 1.0
			# Alternating stripe panels across the canopy.
			b = 0.78 + (0.22 if sin(uv.x * 8.0) >= 0.0 else 0.0)
	# The back rest, rising behind the seat.
	if uv.y >= -0.30 and uv.y < 0.24 and absf(uv.x) < 0.50:
		a = maxf(a, 1.0)
		b = minf(b, 0.52 + 0.18 * (0.5 + 0.5 * sin(uv.x * 16.0)))
	# The seat slab.
	if absf(uv.y - 0.28) < 0.12 and absf(uv.x) < 0.66:
		a = 1.0
		b = 0.92
	# The safety bar across the front of the car.
	if absf(uv.y - 0.05) < 0.055 and absf(uv.x) < 0.62:
		a = 1.0
		b = 1.0
	# The valance skirt hanging under the seat, scalloped like the canopy.
	if uv.y >= 0.40 and uv.y < 0.86:
		var t := (uv.y - 0.40) / 0.46
		var hw := lerpf(0.60, 0.40, t)
		var teeth: float = 0.10 * absf(sin(uv.x * 9.0))
		if absf(uv.x) < hw and uv.y < 0.86 - teeth:
			a = 1.0
			b = lerpf(0.62, 0.34, t)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0),
		clampf(a, 0.0, 1.0))

## The wheel's steel: an outer rim, an inner rim, sixteen spokes and a hub, all
## in one bake so the whole structure is a single draw that simply rotates.
func _fn_ferris(uv: Vector2) -> Color:
	var r := uv.length()
	var a := 0.0
	var b := 0.75
	# The two rims.
	var outer := absf(r - 0.965)
	var inner := absf(r - 0.80)
	if outer < 0.030:
		a = maxf(a, 1.0 - smoothstep(0.016, 0.030, outer))
		b = 1.0
	if inner < 0.020:
		a = maxf(a, 1.0 - smoothstep(0.010, 0.020, inner))
		b = maxf(b, 0.85)
	# Spokes: thin radial members, plus a lattice of shorter cross-braces
	# between the two rims so the structure reads as engineering, not a pie.
	if r < 0.99:
		var ang := atan2(uv.y, uv.x)
		var spoke: float = absf(fposmod(ang * 16.0 / TAU + 0.5, 1.0) - 0.5) * 2.0
		var wobble: float = 0.020 / maxf(r, 0.08)      # constant screen width
		if spoke * PI * r / 8.0 < wobble and r > 0.10:
			a = maxf(a, 0.85)
			b = maxf(b, 0.7)
		# The lattice: zig-zag braces in the band between the rims.
		if r > 0.80 and r < 0.965:
			var zig: float = absf(fposmod(ang * 32.0 / TAU + (r - 0.80) / 0.165, 1.0) - 0.5) * 2.0
			if zig > 0.86:
				a = maxf(a, 0.55)
	# The hub.
	if r < 0.11:
		a = maxf(a, 1.0 - smoothstep(0.07, 0.11, r))
		b = 1.0
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0),
		clampf(a, 0.0, 1.0))

## A midway stall: a pitched striped awning with a scalloped hem, over a dark
## booth on two posts. The hem is cut out of the ALPHA (a real scalloped edge),
## and the stripes run down the pitch, so it reads as canvas rather than as a
## painted block.
func _fn_stall(uv: Vector2) -> Color:
	var a := 0.0
	var b := 0.8
	# The awning: a shallow pitch from the ridge down to the hem, the hem itself
	# scalloped into semicircular tabs.
	var ridge := -0.86
	var hem: float = -0.12 + 0.10 * absf(uv.x)          # the pitch, dropping outward
	var tab: float = 0.13 * sqrt(maxf(0.0, 1.0 - pow(fposmod(uv.x * 5.0, 1.0) * 2.0 - 1.0, 2.0)))
	if uv.y > ridge and uv.y < hem + tab and absf(uv.x) < 0.97:
		a = 1.0
		# Canvas stripes running down the pitch.
		var stripe: float = fposmod(uv.x * 5.0, 1.0)
		b = 0.55 + (0.42 if stripe < 0.5 else 0.0)
		# The pitch shades slightly toward the hem.
		b *= lerpf(1.0, 0.82, clampf((uv.y - ridge) / (hem - ridge), 0.0, 1.0))
		# A dark ridge line along the top.
		if uv.y < ridge + 0.06:
			b = 0.30
	# The booth behind: dark, so the lit counter reads against it.
	if uv.y >= hem and absf(uv.x) < 0.86:
		a = maxf(a, 1.0)
		b = minf(b, 0.18)
	# The lit counter across the front.
	if uv.y > 0.42 and uv.y < 0.62 and absf(uv.x) < 0.90:
		a = 1.0
		b = 0.62
	# The two corner posts.
	for s_v in [-0.88, 0.88]:
		var s: float = s_v
		if absf(uv.x - s) < 0.05 and uv.y > hem - 0.05:
			a = maxf(a, 1.0)
			b = 0.26
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0),
		clampf(a, 0.0, 1.0))

## A rounded dome — the hill profile the frosted range is built from. This is the
## quartic bump _peak_crest deliberately does NOT use: a flat-topped curve makes
## a row of round-topped hills, which is wrong for alps and exactly right for
## something with icing poured over it.
func _dome(x: float, c: float, wd: float) -> float:
	var t: float = clampf(absf(x - c) / wd, 0.0, 1.0)
	var u: float = 1.0 - t * t
	return u * u

## A deterministic 0..1 from a pair of ints — the sprinkle scatter. Integer mix
## rather than the usual fract(sin(dot)) because that is a transcendental per
## pixel and this is called inside a bake loop.
func _hash_i(a: int, b: int) -> float:
	var n: int = a * 374761393 + b * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xFFFF) / 65535.0

## Hills of cake under poured icing, sprinkled. Baked in REAL COLOUR because the
## host tints each rank for depth, so the shading has to live in here.
##
## Column-solved for the same reason Arctic's peaks are: the crest and the icing's
## drip line depend on uv.x ALONE, so a per-pixel Callable would re-solve 240
## columns of maths 120 times over. Only the sprinkle scatter is genuinely
## per-pixel, and it is two integer multiplies.
func _candy_hills_tex() -> ImageTexture:
	var cached: ImageTexture = _shape_cache.get("candy_hills")
	if cached != null:
		return cached
	const W := 240
	const H := 120
	var crest := PackedFloat32Array()
	var drip := PackedFloat32Array()
	crest.resize(W)
	drip.resize(W)
	for x in W:
		var ux: float = float(x) / float(W - 1) * 2.0 - 1.0
		var c: float = 0.34
		c -= 0.62 * _dome(ux, -0.62, 0.52)
		c -= 0.46 * _dome(ux, -0.02, 0.40)
		c -= 0.70 * _dome(ux, 0.58, 0.48)
		c -= 0.34 * _dome(ux, 1.10, 0.42)
		c += 0.018 * sin(ux * 17.0)
		crest[x] = c
		# The icing's lower edge: a shallow wobble with the occasional long run.
		var s: float = maxf(sin(ux * 9.3 + 1.1), 0.0)
		drip[x] = 0.17 + 0.05 * sin(ux * 26.0) + 0.18 * s * s * s
	var icing_hi := Color(1.0, 0.99, 0.99)
	var icing_lo := Color(0.98, 0.84, 0.91)
	var cake_hi := Color(0.95, 0.82, 0.68)
	var cake_lo := Color(0.78, 0.60, 0.50)
	var sprinkles := [Color(1.0, 0.36, 0.56), Color(0.36, 0.86, 0.74),
		Color(1.0, 0.78, 0.30), Color(0.62, 0.52, 1.0), Color(0.42, 0.76, 1.0)]
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for x in W:
		var c: float = crest[x]
		var d: float = drip[x]
		for y in H:
			var uy: float = float(y) / float(H - 1) * 2.0 - 1.0
			var a: float = smoothstep(c - 0.010, c + 0.014, uy) \
				* (1.0 - smoothstep(0.62, 1.0, uy))
			if a <= 0.02:
				continue					   # Image.create starts transparent
			var depth: float = uy - c
			var col: Color
			if depth < d:
				col = icing_hi.lerp(icing_lo, clampf(depth / maxf(d, 0.01), 0.0, 1.0))
				# Sprinkles, on the icing only — they would read as grit on cake.
				var cx: int = int(floorf((float(x) / float(W)) * 108.0))
				var cy: int = int(floorf((float(y) / float(H)) * 54.0))
				if _hash_i(cx, cy) < 0.09:
					col = sprinkles[int(_hash_i(cx + 31, cy - 17) * 4.99)]
			else:
				var t: float = clampf((depth - d) / 0.55, 0.0, 1.0)
				col = cake_hi.lerp(cake_lo, t)
				# A wafer seam through the crumb, so the hill has a section.
				if absf(depth - d - 0.20) < 0.030:
					col = col.lerp(Color(1.0, 0.94, 0.86), 0.55)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_shape_cache["candy_hills"] = tex
	return tex

## A doughnut: dough ring, icing poured over the upper half with a drippy edge,
## sprinkles on the icing and a highlight where the light lands. Real colour —
## the host hangs it in the sky where a sun would go and does not tint it.
func _fn_doughnut(uv: Vector2) -> Color:
	var r := uv.length()
	if r > 1.0 or r < 0.30:
		return Color(0, 0, 0, 0)
	var a: float = (1.0 - smoothstep(0.93, 1.0, r)) * smoothstep(0.30, 0.37, r)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var dough := Color(0.93, 0.74, 0.48)
	# Round the dough off toward both rims so the ring reads as a tube.
	var mid: float = 1.0 - clampf(absf(r - 0.65) / 0.30, 0.0, 1.0)
	var col := dough.lerp(Color(0.72, 0.52, 0.32), 1.0 - mid)
	# The icing, poured over the top with a wandering lower edge.
	var edge: float = 0.06 + 0.16 * sin(uv.x * 7.0 + 1.4) + 0.06 * sin(uv.x * 19.0)
	if uv.y < edge:
		col = Color(0.99, 0.55, 0.74).lerp(Color(1.0, 0.80, 0.88), mid)
		var cx: int = int(floorf((uv.x + 1.0) * 17.0))
		var cy: int = int(floorf((uv.y + 1.0) * 17.0))
		if _hash_i(cx, cy) < 0.16:
			var pick := [Color(1.0, 0.98, 0.62), Color(0.44, 0.88, 0.78),
				Color(0.62, 0.56, 1.0), Color(1.0, 0.99, 0.99)]
			col = pick[int(_hash_i(cx - 7, cy + 11) * 3.99)]
	# A soft highlight on the upper left of the tube.
	var hi: float = clampf(1.0 - Vector2(uv.x + 0.42, uv.y + 0.46).length() / 0.42, 0.0, 1.0)
	col = col.lerp(Color(1, 1, 1), hi * 0.30)
	return Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0))

## A gumdrop: a sugared dome on a flat foot. Baked in VALUE — the host tints each
## one its own colour, so the shading has to survive any hue.
func _fn_gumdrop(uv: Vector2) -> Color:
	const AR := 0.909	  # bake 44x40
	var sy := uv.y * AR
	if sy > 0.78 or sy < -0.82:
		return Color(0, 0, 0, 0)
	# Profile: full width at the foot, narrowing to a rounded tip. sqrt gives the
	# shoulder a gumdrop's curve rather than a cone's straight flank.
	var t: float = clampf((sy + 0.82) / 1.60, 0.0, 1.0)
	var hw: float = 0.86 * sqrt(t) * (0.58 + 0.42 * t)
	if absf(uv.x) > hw:
		return Color(0, 0, 0, 0)
	var a: float = 1.0 - smoothstep(hw - 0.06, hw, absf(uv.x))
	# Lit from the upper left, with a bright sugar rim round the whole edge.
	var lam: float = clampf(0.62 - uv.x * 0.55 - sy * 0.45, 0.0, 1.0)
	var b: float = lerpf(0.52, 1.0, smoothstep(0.0, 0.9, lam))
	b = lerpf(b, 1.0, smoothstep(hw - 0.14, hw - 0.02, absf(uv.x)) * 0.45)
	# Sugar crystals catching the light.
	var cx: int = int(floorf((uv.x + 1.0) * 22.0))
	var cy: int = int(floorf((sy + 1.0) * 22.0))
	if _hash_i(cx + 3, cy + 5) < 0.12:
		b = minf(b + 0.30, 1.0)
	return Color(b, b, b, clampf(a, 0.0, 1.0))

## A cupcake: a fluted case, a swirl of frosting and a cherry. The frosting is
## baked near-WHITE so the host's tint colours it, while the case and the cherry
## keep enough of their own colour to stay case and cherry under any tint.
func _fn_cupcake(uv: Vector2) -> Color:
	const AR := 1.154	  # bake 52x60
	var sy := uv.y * AR
	var col := Color(0, 0, 0)
	var a := 0.0
	# The case: a shallow trapezoid with vertical flutes.
	if sy > 0.10 and sy < 0.98:
		var t: float = (sy - 0.10) / 0.88
		var hw: float = lerpf(0.80, 0.56, t)
		if absf(uv.x) < hw:
			a = 1.0
			col = Color(0.92, 0.80, 0.66)
			# Flutes: a paper case is pleated, and the pleats are what says case.
			var f: float = fposmod(uv.x * 5.5 + 0.5, 1.0)
			col = col.lerp(Color(0.70, 0.56, 0.44), (1.0 - smoothstep(0.0, 0.16, f)) * 0.8)
			col = col.lerp(Color(1.0, 0.94, 0.86), (1.0 - smoothstep(0.16, 0.55, f)) * 0.35)
			# The rim of the case catches the light.
			if sy < 0.20:
				col = col.lerp(Color(1.0, 0.96, 0.90), 0.6)
	# The frosting: a swirl above the case, scalloped at its edge.
	if sy <= 0.14 and sy > -0.86:
		var ft: float = clampf((0.14 - sy) / 1.00, 0.0, 1.0)
		var fw: float = 0.88 * sqrt(1.0 - ft * ft * 0.86)
		fw *= 1.0 - 0.10 * absf(sin(sy * 15.0))
		if absf(uv.x) < fw:
			a = 1.0
			var lam: float = clampf(0.60 - uv.x * 0.60 - sy * 0.30, 0.0, 1.0)
			var b: float = lerpf(0.62, 1.0, smoothstep(0.0, 0.9, lam))
			# The swirl: three turns read as ridges across the frosting.
			b *= 0.90 + 0.10 * sin(sy * 17.0 + uv.x * 3.0)
			col = Color(b, b * 0.985, b * 0.99)
	# The cherry on top.
	if Vector2(uv.x / 0.20, (sy + 0.90) / 0.185).length() < 1.0:
		a = 1.0
		var hl: float = clampf(1.0 - Vector2((uv.x + 0.07) / 0.10,
			(sy + 0.96) / 0.09).length(), 0.0, 1.0)
		col = Color(0.86, 0.16, 0.26).lerp(Color(1.0, 0.72, 0.72), hl * 0.7)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0))

## A bunting pennant: a triangle hanging point-down off the cord, with the
## fabric shading from a bright hem at the top to shadow at the tip.
func _fn_pennant(uv: Vector2) -> Color:
	var top := -0.90
	var tip := 0.92
	if uv.y < top or uv.y > tip:
		return Color(0, 0, 0, 0)
	var t := (uv.y - top) / (tip - top)
	var hw := lerpf(0.88, 0.02, t)
	var a := 1.0 - smoothstep(maxf(hw - 0.09, 0.0), hw, absf(uv.x))
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# A soft fold running down the cloth, plus the hem highlight.
	var fold: float = 0.86 + 0.14 * cos(uv.x * 4.2)
	var b: float = lerpf(1.0, 0.62, t) * fold
	return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0),
		clampf(a, 0.0, 1.0))

func _ray() -> ImageTexture:
	if _aurora_ray_tex == null:
		_aurora_ray_tex = _shaped("aurora_ray", 20, 110, _fn_ray)
	return _aurora_ray_tex

## A soft vertical aurora curtain/ray: brightest through the middle-lower, fading up
## to nothing and out to the sides — so a tall instance reads as a light ray hanging
## in the sky. Tinted by the particle/rect colour.
func _fn_ray(uv: Vector2) -> Color:
	# uv.x in [-1,1] across the width, uv.y in [-1 (top) .. 1 (bottom)].
	var side := clampf(1.0 - absf(uv.x), 0.0, 1.0)
	side = side * side                                               # soft edges
	var vert := smoothstep(-1.0, -0.1, uv.y) * (1.0 - smoothstep(0.55, 1.0, uv.y))
	return Color(1, 1, 1, clampf(side * vert, 0.0, 1.0))
