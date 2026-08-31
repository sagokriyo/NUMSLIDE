class_name AppScreen
extends Control
## AppScreen — the base for every full-screen destination.
##
## Handles the things every screen needs so individual screens stay focused on
## their own content:
##   • a layered premium background (deep base + a soft ambient glow for depth)
##   • device safe-area insets (notches, home indicators) applied as padding
##   • a consistent content frame with generous margins
##   • live restyle when the theme changes
##   • a calm entrance animation (content rises + fades in)
##
## Subclasses override build_content(root: VBoxContainer) and add their widgets.
## They never touch anchors, backgrounds, or safe areas.

var content: VBoxContainer       # where subclasses add their UI
var _nav: BottomNav              # the five-tab bar, on the screens that own a tab
var _frame: MarginContainer
var _bg: TextureRect
var _bg_grad: GradientTexture2D
var _glow: TextureRect
var _blobs: Array[TextureRect] = []   # soft pastel depth blobs
var _living_fx: BoardFx               # theme's living particle ambience on screens without their own
var _bbc: BackBufferCopy               # backdrop snapshot glass cards frost + blur
var _vignette: TextureRect            # app-wide edge grade (premium cinema falloff)
var _vig_grad: GradientTexture2D
var _rays: ColorRect                  # night additive rays (moon + stardust), dark themes
var _rays_mat: ShaderMaterial
var _day_wash: TextureRect            # light themes: soft dawn-sky colour wash
var _day_wash_grad: GradientTexture2D
var _day_rays: ColorRect              # light themes: cathedral sunbeams + bokeh (normal blend)
var _day_mat: ShaderMaterial
# Mobile ("lite") path: the ENTIRE decorative backdrop — gradient, glow, sky
# shaders, depth blobs, living ambience, vignette, and any screen-owned layers
# (Home's toys/scrim) — renders into this reduced-resolution SubViewport and is
# laid over the screen by one _backdrop_view blit. Glass cards and the wordmark
# then blur/refract THIS texture instead of the live framebuffer, which removes
# every BackBufferCopy, every mid-frame tiler flush and the per-frame screen
# mip-chain — the costs that kept Home under 50 fps on tablets. See
# _build_backdrop_target.
var _backdrop_vp: SubViewport
var _backdrop_canvas: Control      # design-space root inside the vp (scale = _BACKDROP_SCALE)
var _backdrop_view: TextureRect
var _backdrop_view_mat: ShaderMaterial   # the blit + folded film-grain mix (see _BACKDROP_BLIT)
var _sky_ticker: _SkyTicker        # lite: the 30 Hz re-arm for the sky AND backdrop targets
# Lite: the two sky programs get their OWN tiny target inside the backdrop —
# quarter resolution, refreshed at 30 Hz. The device bisect (2026-08-01, cool
# run) showed the sky was the LAST layer tipping Home frames over the 16.7 ms
# pacing boundary: hiding it took the screen from 40/58 oscillation to a locked
# 60.0 fps with 18 ms worst frames. Its drift is glacial (time_scale 0.03) and
# its content is pure soft light, so a quarter-res 30 Hz render is visually
# indistinguishable at ~1/16th of the cost. See _build_sky_lite_target.
var _sky_vp: SubViewport
var _sky_canvas: Control
var _sky_view: TextureRect
var _sky_view_mat: ShaderMaterial
# Lite: the sky's MOTES (night stardust / day bokeh) drawn at NATIVE resolution
# in the main tree. Star points are 2-6 px of crisp detail — at quarter res
# they read as mush (device-rejected, 2026-08-01) — but their math needs none
# of the beam/atan work, so a full-res mote-only pass is a fraction of the old
# full-sky cost. The quarter-res target keeps only the soft shafts.
var _dust_rect: ColorRect
var _dust_mat: ShaderMaterial
## Subclasses that run their own entrance (e.g. a per-card stagger) set this true
## so the base whole-screen fade doesn't double up.
var custom_entrance := false
## A content rebuild is already queued for the end of this frame — see
## _queue_content_rebuild, which coalesces repeat triggers into one rebuild.
var _rebuild_pending := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_living_fx()
	_build_vignette()
	_build_frame()
	# Before build_content: the bar is what decides the frame's bottom inset, so
	# a screen's first layout has to already know the strip is spoken for.
	_build_bottom_nav()
	ThemeManager.theme_changed.connect(_on_theme_changed)
	build_content(content)
	on_ready()
	_animate_in()

## Override: build the screen's content into `root`.
func build_content(_root: VBoxContainer) -> void:
	pass

## Override: post-build hook (e.g. start timers, connect signals).
func on_ready() -> void:
	pass

## Override: react to a theme change. Default repaints the backdrop NOW (the
## recolour must land on the signal frame — see _paint_background) and defers
## the content teardown + rebuild to the end of the frame, so the emitter's
## call stack never carries the whole widget rebuild in-signal.
func _on_theme_changed(_palette: Dictionary) -> void:
	_paint_background()
	_queue_content_rebuild()

## Queues ONE deferred content rebuild, coalescing repeat triggers (theme +
## entitlement + profile changes can all land on the same frame). End state is
## identical to the old in-signal rebuild — the work just moves off the
## emitting frame — and a screen freed before the flush drops the call safely.
func _queue_content_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	_run_queued_rebuild.call_deferred()

## The deferred entry point checks the flag rather than rebuilding blindly: a
## SYNCHRONOUS rebuild in the same frame (e.g. Themes' _show_page) clears
## _rebuild_pending via _rebuild_content, and this queued call must then be a
## no-op — otherwise the page is torn down and rebuilt twice in one frame (the
## adversarial review's double-rebuild finding).
func _run_queued_rebuild() -> void:
	if not _rebuild_pending:
		return
	_rebuild_content()

## Override → true on screens whose rebuild must keep the reader where they were.
##
## A rebuild frees the whole content tree, taking the ScrollContainer with it — so
## by default any screen that rebuilds mid-session snaps back to the top. That is
## invisible on a screen you rebuild only on a theme change, and it is glaring on
## one that rebuilds on every PURCHASE: buy an upgrade near the bottom of the Shop
## and the storefront teleports. Opt-in rather than global, because screens that
## rebuild to show a DIFFERENT page (Themes' _show_page) genuinely do want the top.
func preserves_scroll_on_rebuild() -> bool:
	return false

func _rebuild_content() -> void:
	_rebuild_pending = false
	var keep := 0
	if preserves_scroll_on_rebuild():
		var old := _find_content_scroll(content)
		if old != null:
			keep = old.scroll_vertical
	for c in content.get_children():
		c.queue_free()
	build_content(content)
	if keep > 0:
		_apply_kept_scroll.call_deferred(keep)

## The content tree's own vertical scroller (the first one that scrolls
## vertically, so a horizontal rail nested inside it is skipped).
##
## Named for the base class rather than the obvious `_find_v_scroll` /
## `_restore_scroll`: subclasses are free to hold members of their own, and
## `themes.gd` already owns a `_restore_scroll` flag for its own page-change
## scroll handling. A base-class member that shadows one is a hard PARSE error in
## every subclass, not a warning — which the parse gate catches and `--import`
## alone does not.
## SKIPS anything queued for deletion, and that is the whole trick. queue_free()
## is deferred, so during a rebuild the OLD content tree is still parented
## alongside the new one — and it sorts FIRST, so a naive search hands back the
## scroller that is about to be freed. Writing the kept offset into it restores
## the position of a node nobody will ever see again, and the real page stays at
## the top. (Found by the flow assertion, not by reading the code.)
func _find_content_scroll(n: Node) -> ScrollContainer:
	if n.is_queued_for_deletion():
		return null
	if n is ScrollContainer:
		var sc := n as ScrollContainer
		if sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			return sc
	for c in n.get_children():
		var found := _find_content_scroll(c)
		if found != null:
			return found
	return null

## Written twice on purpose: the fresh container has not laid out yet, so its
## scroll bar's max_value is still 0 and the first write clamps to nothing. The
## second lands after the layout pass with the real range in place.
##
## The scroller is looked up AGAIN after the await rather than captured once —
## between the two writes the old tree finishes being freed, and a captured
## reference is either dead or points at the wrong container.
func _apply_kept_scroll(value: int) -> void:
	var first := _find_content_scroll(content)
	if first != null:
		first.scroll_vertical = value
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var second := _find_content_scroll(content)
	if second != null:
		second.scroll_vertical = value

# --- Living theme ambience ----------------------------------------------------
## Override → true on screens that build and manage their OWN BoardFx (Home,
## Gameplay, the physics modes, How to Play) so the effect never runs twice.
func has_own_fx() -> bool:
	return false

## The theme's living particles/effects behind the content on every screen that
## doesn't run its own. Dropped just BELOW the frost snapshot (_bbc) so glass cards
## frost the living FX too (the gameplay card look), and below the content frame —
## like Home: a calm half-faded backdrop, but opaque-world reward motifs (keyboard
## / black hole / fluid) read at full strength so they aren't washed out. BoardFx
## owns its own sizing and theme-rebuild.
func _build_living_fx() -> void:
	if has_own_fx():
		return
	_living_fx = BoardFx.new()
	_living_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_living_fx.modulate.a = _living_fx_alpha()
	# Menu backdrop: a thinner field at half-rate simulation (see BoardFx) — the
	# calm half-faded ambience keeps its character without the gameplay screen's
	# full per-frame particle bill on every menu.
	_living_fx.ambience_scale = 0.55
	# Backdrop slot: beneath the frost source, so glass captures the FX too.
	place_in_backdrop(_living_fx)
	# Keep the dim correct across theme switches (opaque motifs stay full strength).
	ThemeManager.theme_changed.connect(func(_p):
		if is_instance_valid(_living_fx):
			_living_fx.modulate.a = _living_fx_alpha())

func _living_fx_alpha() -> float:
	return 1.0 if ThemeManager.bg_motif() in ["circuit", "blackhole", "metaballs"] else 0.5

## Opt-in for screens that want Home's glass-shard identity behind their
## content: a calm field of large drifting glass number-tiles (GlassDrift owns
## its own scrim, theme-rebuild and reduce-motion skip). Dropped just BENEATH
## the frost snapshot so glass cards frost the shards too — the same slot the
## living FX ride in — and a sibling of `content`, so it survives the theme
## rebuild that tears content down.
## `calm` drops the field to its far band only — for content-dense screens where
## a full-size shard lands on a number rather than beside it. See GlassDrift.calm.
## Returns the layer, so a screen that wants to colour its own air (the Badge
## page tints the field with the player's RANK) can reach it without a second
## lookup. Every other caller simply ignores the return.
func add_glass_drift(calm: bool = false) -> GlassDrift:
	var drift := GlassDrift.new()
	drift.calm = calm
	place_in_backdrop(drift)
	return drift

# --- Vignette -----------------------------------------------------------------
## A colour-grade vignette on EVERY screen: transparent through the middle, the
## edges sinking into a deep shade of the theme's own base so the centre (content,
## wordmark, cards) pops forward — the reference's cinema look. Sits just below the
## frost snapshot so glass cards frost the graded backdrop, and below the content
## frame so the top bar (profile / book / gear) and cards stay at full strength —
## the grade dims the backdrop, never the UI drawn on top of it.
func _build_vignette() -> void:
	_vig_grad = GradientTexture2D.new()
	_vig_grad.fill = GradientTexture2D.FILL_RADIAL
	_vig_grad.fill_from = Vector2(0.5, 0.5)
	_vig_grad.fill_to = Vector2(0.5, 1.0)
	_vig_grad.width = 256
	_vig_grad.height = 256
	_vignette = TextureRect.new()
	_vignette.texture = _vig_grad
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place_in_backdrop(_vignette)   # above bg / glow / FX, below the frost + content
	_paint_vignette()

## A LIGHT theme whose partner colour (accent2) is neutral is asking for a
## neutral page: no pastel depth blobs, no accent glow, no sepia light-leak in
## the corners. The house style for light themes is warm and airy - a pink and a
## peach blob and sun-kissed corners - which suits a sketchbook or a spring
## morning and turns white marble peach and a grey page pink. Derived from the
## palette rather than a flag, so a theme opts in by what it IS: Carrara and
## Mono today (test_theme_visuals pins the roster).
static func neutral_page(p: Dictionary) -> bool:
	if not bool(p.get("is_light", false)):
		return false
	var partner: Color = p.get("accent2", Color(1, 0, 0))
	return partner.s < 0.12

## Re-tint on theme change: the edge tone is a deep shade of the palette's own
## base so the grade never clashes (a hard navy would muddy light themes).
func _paint_vignette() -> void:
	if _vig_grad == null:
		return
	var p := ThemeManager.palette()
	var is_light: bool = bool(p.get("is_light", false))
	var base: Color = p.get("bg0", Color(0.01, 0.02, 0.06))
	# Light themes get a WARM light-leak instead of a grey shadow — the corners feel
	# sun-kissed (soft sepia gold) rather than grimy. Dark themes keep the deep grade.
	var edge: Color = base.darkened(0.30).lerp(Color(0.60, 0.45, 0.26), 0.5) if is_light else base.darkened(0.80)
	# Lifted again with the contrast pass. The grade is the other half of that work:
	# the pass opens the gap between a surface and the page, and the vignette decides
	# how much page there is to open it against — sinking the corners is what leaves
	# the centre carrying the whole screen. Kept gentler on light themes, where the
	# same depth reads as dirt rather than as fall-off.
	var a: float = 0.36 if is_light else 0.78
	if neutral_page(p):
		edge = base.darkened(0.45)   # a plain shadow, not a sepia leak
		a = 0.22
	# Five stops for DEPTH: the frame stays clear through the middle, then the grade
	# ramps in earlier than it used to (0.26) and rolls through two mid tones before
	# sinking to its deepest at the corners. The extra stop is what keeps a grade
	# this strong from reading as a ring — with four it had to climb too fast
	# somewhere, and the eye finds that edge every time.
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.26, 0.56, 0.80, 1.0])
	g.colors = PackedColorArray([
		Color(edge.r, edge.g, edge.b, 0.0),
		Color(edge.r, edge.g, edge.b, 0.0),
		Color(edge.r, edge.g, edge.b, a * 0.22),
		Color(edge.r, edge.g, edge.b, a * 0.60),
		Color(edge.r, edge.g, edge.b, a)])
	_vig_grad.gradient = g

# --- Light rays ---------------------------------------------------------------
## Soft crepuscular "god rays" spilling from a light source just above the top
## edge. Additive so they read as LIGHT (not a grey overlay), angular streaks
## radiating from the source with 1-D value noise for organic width variation,
## fading out by mid-screen. Cheap: one hash-noise band, three octaves. All the
## character — colour, intensity, the source's off-centre position — is driven
## per theme in _paint_rays, so each palette casts its own believable light.
## (D3D12: only ascending smoothstep, per the reversed-smoothstep gotcha.)
const _RAYS_SHADER := """
shader_type canvas_item;
render_mode blend_add;

uniform mediump vec4 ray_color : source_color = vec4(1.0, 0.96, 0.9, 1.0);
uniform mediump float intensity = 0.16;
uniform mediump float dust_intensity = 0.55;
uniform mediump float source_glow = 0.5;         // brightness of the light's origin bloom
uniform mediump float source_radius = 0.30;      // how far the origin bloom spills down-screen
uniform mediump float source_falloff = 2.2;      // high = sharp sun core; low = soft moon disc
uniform mediump float night = 0.0;               // 1 = moonlight + stardust instead of sunbeams
// highp (default) below: source/seed feed the angle + hash inputs, aspect
// feeds the mote cell math, and time_scale/motion multiply TIME — none of
// these may quantise (gaming/knowledge 03 §1).
uniform vec2 source = vec2(0.5, -0.12);
uniform float aspect = 0.46;
uniform float seed = 0.0;
uniform float time_scale = 0.03;
uniform float motion = 1.0;              // 0 → dust holds still (probes/screenshots)
// Lite: 1 removes the mote layer from THIS pass — the crisp star points are
// re-drawn at native res by the dedicated dust pass (see _DUST_NIGHT), while
// the soft shafts stay in the quarter-res target. 0 everywhere else.
uniform mediump float shafts_only = 0.0;
// Lite: the in-target quad covers only the band this program can light (every
// term is zero past UV.y 0.96 — the shaft fade below); suv rebuilds the
// full-screen UV over that band, so every surviving texel computes from
// identical coordinates. Defaults are the exact identity for full-rect quads.
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);

// Sinless hashes (Hoskins-style): fract/mul only. The sin() the old ones leaned
// on is a transcendental — cheap on desktop, genuinely expensive on phone GPUs,
// and these shaders evaluate ~10 hashes per pixel over the whole screen. The
// noise CHARACTER is identical; only the (random) layout instance changes.
float hash1(float x) { x = fract(x * 0.1031); x *= x + 33.33; return fract(x * (x + x)); }
float hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float n1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash1(i), hash1(i + 1.0), f);
}
float beams(float x) {
	float s = 0.0;
	s += 0.55 * n1(x * 1.0 + seed);
	s += 0.30 * n1(x * 2.3 + seed * 1.7);
	s += 0.15 * n1(x * 5.1 + seed * 2.9);
	return s;
}
void fragment() {
	// Precision: the coordinate spine (suv/rel/ang, duv/cell/gi), the hashes
	// and every TIME term stay highp; everything downstream of the noise —
	// masks, fades, blooms, twinkle, mixes — is mediump (knowledge 03 §1).
	vec2 apx = vec2(aspect, 1.0);
	vec2 suv = UV * uv_scale + uv_offset;   // full-screen UV, whatever the quad covers
	vec2 rel = suv - source;
	rel.x *= aspect;                        // real angles, undo the portrait stretch
	float ang = atan(rel.x, rel.y);         // 0 = straight down from the source
	// Two noise bands at different frequencies + drift give wide shafts with finer
	// filaments inside them, so the light looks structured, not like a flat glow.
	mediump float b = beams(ang * 11.0 + TIME * time_scale);
	b = smoothstep(0.32, 0.90, b);          // carve soft shafts out of the noise
	b *= 1.0 - smoothstep(0.15, 1.60, abs(ang));   // concentrate near the shaft column
	// Emerge under the top edge and reach WELL down the screen so the shafts cross
	// the darker mid-region (where they read) instead of hiding in the top glow.
	mediump float fade = smoothstep(-0.10, 0.18, suv.y) * (1.0 - smoothstep(0.20, 0.96, suv.y));
	mediump float rayfield = b * fade;      // 0..1, where the light actually is

	// The SOURCE itself glows — light is brightest where it is born. By day a sharp
	// warm sun core sits just above the top edge; by night a softer, wider moon disc
	// (source_radius / source_falloff are set per theme). sd is computed in
	// highp (the subtraction) then carried mediump — it only feeds masks.
	mediump float sd = length((suv - source) * apx);
	mediump float bloom = pow(1.0 - smoothstep(0.0, source_radius, sd), source_falloff);

	// Motes: sparse round grains at jittered spots with a slow twinkle. By DAY they
	// glint ONLY inside the shafts (dust caught in sunbeams). By NIGHT they also
	// drift free across the upper sky as STARDUST — the night's "something else":
	// a moonlit haze of floating stars rather than hard shafts.
	//
	// Tuned to read as STARS, not haze: each grain is a hard point with a small
	// halo (a narrow falloff, then squared to pull the shoulder in tighter), there
	// are fewer of them so the ones that remain are individually legible, and they
	// sink and twinkle at about half the old rate. A wide falloff over many dim
	// grains averages out to fog — which is what this looked like before.
	vec2 duv = suv * apx;
	duv.y += TIME * 0.006 * motion;          // the motes sink slowly (frozen if still)
	vec2 cell = duv * 130.0;
	vec2 gi = floor(cell);
	mediump vec2 gf = fract(cell) - 0.5;
	mediump float present = step(0.71, hash2(gi));   // ~29% of cells carry a grain
	mediump vec2 jit = vec2(hash2(gi + 3.1), hash2(gi + 8.7)) - 0.5;
	mediump float d = length(gf - jit * 0.6);
	mediump float core = 1.0 - smoothstep(0.01, 0.15, d);
	mediump float grain = core * core * present;     // squared: sharp core, fast shoulder
	mediump float tw = 0.62 + 0.38 * sin(TIME * 1.2 * motion + hash2(gi) * 40.0);
	mediump float sky = 1.0 - smoothstep(0.0, 0.78, suv.y);   // upper-sky mask for stardust
	mediump float dust_field = mix(rayfield, max(rayfield, sky * 0.85), night);
	mediump float dust = grain * tw * dust_field;

	// A wide, faint aura around the source — a whisper of radiant halo that lends a
	// divine touch without blowing the top out (kept low on purpose).
	mediump float halo = pow(1.0 - smoothstep(0.0, source_radius * 2.2, sd), source_falloff * 0.55);

	// Sunbeams carry the day; at night the shafts fall back to a whisper and the
	// moon-bloom + drifting stardust carry the look instead.
	mediump float shaft_scale = mix(1.0, 0.58, night);
	mediump float a = rayfield * intensity * shaft_scale
			+ bloom * source_glow
			+ halo * source_glow * 0.15
			+ dust * dust_intensity * (1.0 - shafts_only);
	COLOR = vec4(ray_color.rgb, a);
}
"""

## The two sky programs are compiled ONCE per process, not once per screen entry.
##
## `_build_rays()` / `_build_day()` run unconditionally on every AppScreen, so each
## navigation used to hand the RenderingServer two fresh shader sources to parse and
## lower to SPIR-V — for two stacks of which exactly one is ever visible. The source
## text is a `const`, so every compile produced the same program. The ShaderMaterials
## stay PER SCREEN, so every `set_shader_parameter` in `_paint_rays` / `_paint_day` is
## untouched and each screen still owns its own uniforms. Same pattern as
## ui/components/glass_panel.gd, which shares one preloaded Shader across every card.
static var _rays_shader: Shader = null
static var _day_shader: Shader = null
static var _rays_shader_vp: Shader = null   # blend_add stripped — see _build_sky_lite_target
static var _sky_composite: Shader = null

static func _shared_rays_shader() -> Shader:
	if _rays_shader == null:
		var sh := Shader.new()
		sh.code = _RAYS_SHADER
		_rays_shader = sh
	return _rays_shader

static func _shared_day_shader() -> Shader:
	if _day_shader == null:
		var sh := Shader.new()
		sh.code = _DAY_SHADER
		_day_shader = sh
	return _day_shader

## THE LITE GPU PATH — one switch for every phone-class rendering decision.
## `PERF_FORCE_LITE=1` forces it on desktop so probes can screenshot and profile
## the exact path a device runs; it is never set by gates or the shipping app.
static func lite_gpu() -> bool:
	return OS.has_feature("mobile") or OS.get_environment("PERF_FORCE_LITE") == "1"

## True when the OpenGL Compatibility path is actually running. Asked of the
## SERVER, never of the project setting: the engine silently falls back to GL
## when Vulkan init fails, and the setting still claims "mobile" afterwards
## (studio rule 5.2).
##
## Reduced-resolution factor for the whole decorative backdrop. Half resolution
## quarters the fill cost of ~8 stacked layers; the content is soft ambience the
## linear upscale barely touches. `PERF_BACKDROP_SCALE` overrides for A/B tuning.
static func _backdrop_scale() -> float:
	var s := OS.get_environment("PERF_BACKDROP_SCALE")
	return clampf(s.to_float(), 0.2, 1.0) if not s.is_empty() else 0.5

## MOBILE FILL-RATE, round 2: the whole backdrop stack (gradient, glow, the sky
## programs' ~10 hash evals + atan per pixel, ambience, vignette, Home's toys)
## used to be drawn full-screen, per layer, per frame — 8-10× overdraw at
## 1840×2944 — and then COPIED (BackBufferCopy) with a full mip chain so glass
## could blur it. Here it all renders ONCE into a half-res SubViewport; the main
## pass lays it down with a single blit, and every glass surface samples the
## same texture (see glass_lite.gdshader / ExtrudedWord) — so the lite path has
## ZERO screen-texture readers, no backbuffer copy and no tiler flush at all.
## Inside the target, `_backdrop_canvas` is a DESIGN-SPACE root (full logical
## size, scaled down by node scale), so every layer keeps its coordinates; code
## that asks the viewport for its size reads the `design_size` meta instead
## (see BoardFx). Desktop keeps the direct full-res path and its pixel gates.
func _build_backdrop_target() -> void:
	_backdrop_vp = SubViewport.new()
	_backdrop_vp.disable_3d = true
	_backdrop_vp.transparent_bg = false   # the bg gradient covers it edge to edge
	# The wash is slow decoration: render on demand, not per frame. Armed once
	# here for the first frame; _SkyTicker re-arms it on the SAME 30 Hz tick as
	# the sky target (so the blit never carries a sky staler than the tick that
	# armed both), and fade-in tweens / theme repaint / resize force per-frame
	# mode through _hold_backdrop until their content settles.
	_backdrop_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_backdrop_vp.handle_input_locally = false
	_backdrop_vp.gui_disable_input = true
	# Deliberately NO MSAA here (or on any offscreen target): the project-level
	# 2x msaa_2d covers only the root viewport's geometry edges. These targets
	# hold soft gradients and noise with no polygon silhouettes — samples here
	# would be pure cost. Do not "fix" this to match the project setting.
	_backdrop_vp.msaa_2d = Viewport.MSAA_DISABLED
	add_child(_backdrop_vp)
	# A Control parented DIRECTLY to a Viewport is a root control: the viewport
	# re-anchors it to its own (reduced) rect on every resize, fighting the
	# design-space size set below. The Node2D shim makes the canvas an ordinary
	# Control that keeps whatever size it is given.
	var shim := Node2D.new()
	_backdrop_vp.add_child(shim)
	_backdrop_canvas = Control.new()
	_backdrop_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shim.add_child(_backdrop_canvas)
	_layout_backdrop_target()
	_backdrop_view = TextureRect.new()
	_backdrop_view.texture = _backdrop_vp.get_texture()
	_backdrop_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop_view.stretch_mode = TextureRect.STRETCH_SCALE
	_backdrop_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Film-grain dither, native res, folded into the blit itself (was a second
	# full-screen blended quad directly above it): the big dark gradients are
	# the textbook 8-bit banding case (gaming/knowledge 15 — the low tier has no
	# debanding at all), and the same grain masks the backdrop upscale. A 128²
	# tiling noise at ~3% alpha — one small repeated sampler, and one fewer
	# native-res blended pass. Same texture, same tiling, same mix — see
	# _BACKDROP_BLIT for the exactness argument.
	_backdrop_view_mat = ShaderMaterial.new()
	_backdrop_view_mat.shader = _shared_backdrop_blit_shader()
	_backdrop_view_mat.set_shader_parameter("grain_tex", _shared_grain_texture())
	var dsize: Vector2 = _backdrop_vp.get_meta("design_size")
	_backdrop_view_mat.set_shader_parameter("grain_scale", dsize / 128.0)
	_backdrop_view.material = _backdrop_view_mat
	add_child(_backdrop_view)
	resized.connect(_layout_backdrop_target)
	# Tilt parallax rides the blit: one node eases and every backdrop layer
	# (gradient, sky, blobs, living ambience) comes with it. See _ParallaxTicker.
	add_child(_ParallaxTicker.new(_backdrop_view))

## Signed mono grain: half the texels darken, half lighten, net-zero brightness,
## strength baked into the alpha so the layer needs no shader and no modulate.
static var _grain_tex: ImageTexture = null

static func _shared_grain_texture() -> ImageTexture:
	if _grain_tex == null:
		var rng := RandomNumberGenerator.new()
		rng.seed = 20480802
		var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		for y in 128:
			for x in 128:
				var a := rng.randf() * 0.045
				if rng.randf() < 0.5:
					img.set_pixel(x, y, Color(0, 0, 0, a))
				else:
					img.set_pixel(x, y, Color(1, 1, 1, a))
		_grain_tex = ImageTexture.create_from_image(img)
	return _grain_tex

## The backdrop blit + the film-grain mix in ONE pass. Exactness contract with
## the old two-pass composite (blit quad, then a tiled grain quad blended MIX):
##   • grain texel: grain_scale = design_size / 128 puts every screen pixel on
##     the same tiled texel centre the old 1:1 STRETCH_TILE quad sampled;
##     nearest filtering makes the fetch immune to sub-ulp UV noise.
##   • mix(bq, g.rgb, g.a) IS the fixed-function MIX blend the quad used.
##   • bq re-quantises the bilinear backdrop sample to the 8-bit value the old
##     intermediate framebuffer write produced before the grain blended over
##     it. All blend inputs are then exact 8-bit values, and (255-a)*b + a*g
##     can never land on a rounding boundary (an integer never equals
##     255k+127.5), so the folded result matches the old pipeline bit-for-bit;
##     roundEven matches the round-to-nearest-even unorm store convention.
## Default highp throughout — this is one blit, not a hot shader, and mediump
## could not guarantee the sub-1/255 bound (skill: godot-mobile-shaders §2).
## No screen reads (gl_compatibility locked): TEXTURE is the backdrop target.
const _BACKDROP_BLIT := """
shader_type canvas_item;
uniform sampler2D grain_tex : repeat_enable, filter_nearest;
uniform vec2 grain_scale = vec2(1.0, 1.0);
void fragment() {
	vec4 b = texture(TEXTURE, UV);
	vec4 g = texture(grain_tex, UV * grain_scale);
	vec3 bq = roundEven(b.rgb * 255.0) / 255.0;
	COLOR = vec4(mix(bq, g.rgb, g.a), b.a);
}
"""

static var _backdrop_blit_shader: Shader = null

static func _shared_backdrop_blit_shader() -> Shader:
	if _backdrop_blit_shader == null:
		var sh := Shader.new()
		sh.code = _BACKDROP_BLIT
		_backdrop_blit_shader = sh
	return _backdrop_blit_shader

func _layout_backdrop_target() -> void:
	if _backdrop_vp == null:
		return
	var vp := size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = get_viewport_rect().size
	var s := _backdrop_scale()
	_backdrop_vp.size = Vector2i(maxi(int(vp.x * s), 8), maxi(int(vp.y * s), 8))
	# Layers lay out against the full design size; the node scale shrinks the
	# render into the reduced target. `design_size` is the contract for anything
	# inside that would otherwise ask the (half-sized) viewport how big it is.
	_backdrop_vp.set_meta("design_size", vp)
	_backdrop_canvas.size = vp
	_backdrop_canvas.scale = Vector2(s, s)
	# The grain tiles at NATIVE resolution — retile whenever the screen does.
	if _backdrop_view_mat != null:
		_backdrop_view_mat.set_shader_parameter("grain_scale", vp / 128.0)
	# A resize reshapes the target and every layer inside it: hold per-frame
	# mode through the storm (foldables relayout over several frames), then
	# fall back to the 30 Hz tick. No-op at build time (no ticker yet).
	_hold_backdrop(0.25)

## Forces the backdrop target to render every frame for `seconds` — layer
## tweens (fade_in_backdrop), theme repaint, resize — then drop back to the
## 30 Hz ticked mode. Time-based on purpose: a freed tween can never wedge the
## target in per-frame mode, and under --fixed-fps the expiry is deterministic.
## Lite-path only; a silent no-op on desktop, which has no backdrop target.
func _hold_backdrop(seconds: float) -> void:
	if _sky_ticker == null or _backdrop_vp == null:
		return
	_sky_ticker.hold = maxf(_sky_ticker.hold, seconds)
	_backdrop_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

## Where backdrop-slot layers live: the reduced-res canvas on the lite path, the
## screen itself on desktop. Screens (Home) parent their ambience/toys here.
func backdrop_root() -> Control:
	return _backdrop_canvas if _backdrop_canvas != null else self

## The half-res wash on the lite path (null on desktop, which samples the live
## screen via BackBufferCopy instead). Full-screen, so its UVs are exactly
## SCREEN_UV. BOTH the wordmark's refraction and the cards' frost read this one
## texture — see the note on frost_texture().
func backdrop_texture() -> Texture2D:
	return _backdrop_vp.get_texture() if _backdrop_vp != null else null

## The frost source: the same sharp half-res wash, which glass_lite.gdshader
## blurs itself in five mediump taps.
##
## There WAS a quarter-res pre-blur pass here (blur once per frame, one tap per
## pane) and on paper it is the better shape — the tile-GPU hot-shader ceiling
## is ~4 fetches. It is gone for two measured reasons. It could not run on
## GLES3 at all: a SubViewport whose CONTENT samples another viewport's texture
## never resolves there, so the panes came out flat grey (nesting alone is
## fine — the sky target reads no other viewport and works). And on Vulkan it
## rendered the panes visibly WHITER than the direct path — the extra viewport
## round-trip shifts gamma — which was caught on device as "the blocks are
## whiter". One path, one look, on both renderers. The cost is affordable and
## measured: the phone runs these five taps at a locked 120 fps.
func frost_texture() -> Texture2D:
	return backdrop_texture()

## The night program again, but WITHOUT `render_mode blend_add`: inside the sky
## target it is the only thing drawn onto transparent black, so plain mix
## blending leaves the texture holding exactly `ray_color.rgb * a`
## (premultiplied light). The ADDITIVE step then happens once at composite time.
static func _shared_rays_shader_vp() -> Shader:
	if _rays_shader_vp == null:
		var sh := Shader.new()
		sh.code = _RAYS_SHADER.replace("render_mode blend_add;\n", "")
		_rays_shader_vp = sh
	return _rays_shader_vp

## Composites the quarter-res sky texture into the backdrop. The target holds
## PREMULTIPLIED colour (see above), so `blend_premul_alpha` reproduces both
## moods exactly with one program:
##   • night (`additive = 1`): alpha forced to 0 → dst = dst + rgb   (pure add)
##   • day   (`additive = 0`): dst = rgb + dst·(1−a)                 (normal mix)
const _SKY_COMPOSITE := """
shader_type canvas_item;
render_mode blend_premul_alpha;
uniform mediump float additive = 0.0;
void fragment() {
	// mediump end to end: the source is an 8-bit unorm target FP16 carries
	// exactly, and nothing here feeds cells, hashes or TIME.
	mediump vec4 t = texture(TEXTURE, UV);
	COLOR = vec4(t.rgb, t.a * (1.0 - additive));
}
"""

static func _shared_sky_composite_shader() -> Shader:
	if _sky_composite == null:
		var sh := Shader.new()
		sh.code = _SKY_COMPOSITE
		_sky_composite = sh
	return _sky_composite

## The native-res mote passes (lite only). Same grids, jitter, twinkle and
## masks as the full sky programs — just without beams()/atan, so a full-screen
## pass costs a fraction of the original sky. One approximation, night only:
## the original also brightened motes caught inside a moonbeam shaft
## (dust_field = max(rayfield, sky·0.85)); this pass carries the sky term only,
## so in-shaft motes are a whisper dimmer. Nothing else moved.
const _DUST_NIGHT := """
shader_type canvas_item;
render_mode blend_add;
uniform mediump vec4 ray_color : source_color = vec4(1.0, 0.96, 0.9, 1.0);
uniform mediump float dust_intensity = 0.55;
uniform float aspect = 0.46;
uniform float motion = 1.0;
// The quad covers only the live sky band (mask dies at UV.y 0.78); suv
// rebuilds the full-screen UV over it so every surviving texel is identical.
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
// Precision contract (gaming/knowledge 03 §1): mediump carries the colour /
// mask / twinkle math only. suv/duv/cell/gi, the hashes and every TIME term
// stay highp — fract-of-a-large-number and hours of accumulated TIME both
// exceed the FP16 mantissa. Desktop ignores mediump, so the pixel gate holds.
float hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
void fragment() {
	vec2 suv = UV * uv_scale + uv_offset;
	vec2 duv = suv * vec2(aspect, 1.0);
	duv.y += TIME * 0.006 * motion;
	vec2 cell = duv * 130.0;
	vec2 gi = floor(cell);
	mediump vec2 gf = fract(cell) - 0.5;
	mediump float present = step(0.71, hash2(gi));
	mediump vec2 jit = vec2(hash2(gi + 3.1), hash2(gi + 8.7)) - 0.5;
	mediump float d = length(gf - jit * 0.6);
	mediump float core = 1.0 - smoothstep(0.01, 0.15, d);
	mediump float grain = core * core * present;
	mediump float tw = 0.62 + 0.38 * sin(TIME * 1.2 * motion + hash2(gi) * 40.0);
	mediump float sky = 1.0 - smoothstep(0.0, 0.78, suv.y);
	COLOR = vec4(ray_color.rgb, grain * tw * sky * 0.85 * dust_intensity);
}
"""

const _DUST_DAY := """
shader_type canvas_item;
uniform mediump vec4 bokeh_col : source_color = vec4(1.0, 0.86, 0.92, 1.0);
uniform mediump float bokeh_strength = 0.14;
uniform float aspect = 0.46;
uniform float motion = 1.0;
// The quad covers only the live bokeh band (mask dies at UV.y 0.92); suv
// rebuilds the full-screen UV over it so every surviving texel is identical.
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
// Precision contract: same split as _DUST_NIGHT — mediump for colour/mask
// math, highp for suv/duv/cell/gi, hashes and TIME (see the note there).
float hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
void fragment() {
	vec2 suv = UV * uv_scale + uv_offset;
	vec2 duv = suv * vec2(aspect, 1.0);
	duv.y += TIME * 0.01 * motion;
	vec2 cell = duv * 24.0;
	vec2 gi = floor(cell);
	mediump vec2 gf = fract(cell) - 0.5;
	mediump float present = step(0.78, hash2(gi));
	mediump vec2 jit = vec2(hash2(gi + 3.1), hash2(gi + 8.7)) - 0.5;
	mediump float d = length(gf - jit * 0.7);
	mediump float bcore = 1.0 - smoothstep(0.04, 0.24, d);
	mediump float bok = bcore * bcore * present;
	mediump float bokeh = bok * (1.0 - smoothstep(0.0, 0.92, suv.y));
	COLOR = vec4(bokeh_col.rgb, clamp(bokeh * bokeh_strength, 0.0, 1.0));
}
"""

static var _dust_night_shader: Shader = null
static var _dust_day_shader: Shader = null

static func _shared_dust_shader(is_light: bool) -> Shader:
	if is_light:
		if _dust_day_shader == null:
			var sh := Shader.new()
			sh.code = _DUST_DAY
			_dust_day_shader = sh
		return _dust_day_shader
	if _dust_night_shader == null:
		var sh2 := Shader.new()
		sh2.code = _DUST_NIGHT
		_dust_night_shader = sh2
	return _dust_night_shader

## The sky's own reduced target (lite only) — see the member note for why: the
## sky was the last layer holding Home off a locked 60. Quarter res, 30 Hz.
## The blit TextureRect is added to the backdrop canvas HERE, at the exact
## build point the shader quads would have occupied, so the z-order contract
## (over bg/glow, under blobs/ambience/vignette) is unchanged.
func _build_sky_lite_target() -> void:
	_sky_vp = SubViewport.new()
	_sky_vp.disable_3d = true
	_sky_vp.transparent_bg = true
	_sky_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_sky_vp.handle_input_locally = false
	_sky_vp.gui_disable_input = true
	add_child(_sky_vp)
	var shim := Node2D.new()   # same root-control trap as the backdrop target
	_sky_vp.add_child(shim)
	_sky_canvas = Control.new()
	_sky_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shim.add_child(_sky_canvas)
	_sky_view = TextureRect.new()
	_sky_view.texture = _sky_vp.get_texture()
	_sky_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sky_view.stretch_mode = TextureRect.STRETCH_SCALE
	_sky_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sky_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky_view_mat = ShaderMaterial.new()
	_sky_view_mat.shader = _shared_sky_composite_shader()
	_sky_view.material = _sky_view_mat
	backdrop_root().add_child(_sky_view)
	_layout_sky_target()
	resized.connect(_layout_sky_target)
	# 30 Hz refresh: a dedicated ticker (NOT AppScreen._process — Home overrides
	# that) re-arms UPDATE_ONCE every other-ish frame. The drift is far too slow
	# for the half-step to read; the motes twinkle in their own native pass.
	# The backdrop target re-arms on the SAME tick (see _SkyTicker), so its
	# blit never carries a sky staler than the tick that armed both.
	var ticker := _SkyTicker.new()
	ticker.vp = _sky_vp
	ticker.backdrop_vp = _backdrop_vp
	_sky_ticker = ticker
	add_child(ticker)
	# The native-res mote pass, over the backdrop blit (shafts) and under every
	# crisp layer added later — see the member note.
	_dust_rect = ColorRect.new()
	_dust_rect.color = Color(1, 1, 1, 1)
	_dust_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dust_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dust_mat = ShaderMaterial.new()
	_dust_rect.material = _dust_mat
	add_child(_dust_rect)

func _layout_sky_target() -> void:
	if _sky_vp == null:
		return
	var vp := size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = get_viewport_rect().size
	_sky_vp.size = Vector2i(maxi(int(vp.x * 0.25), 8), maxi(int(vp.y * 0.25), 8))
	_sky_vp.set_meta("design_size", vp)
	_sky_canvas.size = vp
	_sky_canvas.scale = Vector2(0.25, 0.25)

## Tilt parallax (mobile lite path only): eases the backdrop blit a few pixels
## AGAINST the phone's tilt, so the theme's world sits a breath behind the glass
## instead of being painted on it. Riding the blit means one node moves and every
## backdrop layer — gradient, sky, blobs, living ambience — comes with it while
## the content above stays put. The view is overscanned ~2.5% while active so the
## shift can never expose the backdrop's edge. Its own node rather than an
## AppScreen._process so screens that define their own _process keep parallax
## untouched. On hardware with no accelerometer (desktop) the sensor probe reads
## zero for a couple of seconds and the ticker retires itself — the desktop
## full-res path never builds it anyway.
class _ParallaxTicker extends Node:
	const AMP := Vector2(12.0, 8.0)     # design-space px at full tilt
	const OVERSCAN := 1.025
	var view: TextureRect
	var _off := Vector2.ZERO
	var _armed := false                 # overscan applied (a live sensor was seen)
	var _probe := 2.0                   # seconds left to wait for a first reading

	func _init(p_view: TextureRect) -> void:
		view = p_view

	func _process(delta: float) -> void:
		if view == null or not is_instance_valid(view):
			set_process(false)
			return
		var a: Vector3 = Input.get_accelerometer()
		if a == Vector3.ZERO and not _armed:
			# Nothing yet: either no sensor at all or one still warming up. Give
			# it a moment, then stop paying the per-frame read forever.
			_probe -= delta
			if _probe <= 0.0:
				set_process(false)
			return
		if not SettingsManager.tilt_parallax() or SettingsManager.reduce_motion():
			if _armed:
				_armed = false
				_off = Vector2.ZERO
				view.position = Vector2.ZERO
				view.scale = Vector2.ONE
			return
		if not _armed:
			_armed = true
			view.scale = Vector2(OVERSCAN, OVERSCAN)
		view.pivot_offset = view.size * 0.5
		# Portrait mapping: device x-tilt slides the world sideways; forward/back
		# tilt (the z axis) nods it vertically. Upright hold reads near zero on
		# both, so the neutral grip stays perfectly centred.
		var target := Vector2(
			clampf(-a.x / 4.0, -1.0, 1.0) * AMP.x,
			clampf(a.z / 5.0, -1.0, 1.0) * AMP.y)
		_off = _off.lerp(target, minf(delta * 4.0, 1.0))
		view.position = _off

class _SkyTicker extends Node:
	var vp: SubViewport
	# The backdrop target renders on the SAME tick as the sky, never on its own
	# schedule: the backdrop's content is static between ticks (its only moving
	# part is the sky blit), so a skipped frame shows identical pixels, and a
	# tick-aligned re-arm keeps the sky-through-backdrop cadence fixed.
	var backdrop_vp: SubViewport
	# Seconds of forced per-frame mode left (fade-in tweens / theme repaint /
	# resize — see _hold_backdrop). Counted down here, never signal-released:
	# a freed tween cannot wedge the target in UPDATE_ALWAYS. On expiry one
	# UPDATE_ONCE captures the settled state before the tick cadence resumes.
	var hold := 0.0
	# Phase seed: a third of the 30 Hz period off Home's toy step and the word
	# redraw, so the three heavy ticks land on different frames (the fmod reset
	# below preserves the offset for the life of the screen).
	var _acc := 1.0 / 90.0
	func _process(delta: float) -> void:
		if not is_instance_valid(vp):
			return
		_acc += delta
		var tick := _acc >= 1.0 / 30.0
		if tick:
			_acc = fmod(_acc, 1.0 / 30.0)
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		if not is_instance_valid(backdrop_vp):
			return
		if hold > 0.0:
			hold -= delta
			if hold <= 0.0:
				backdrop_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		elif tick:
			backdrop_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

func _build_rays() -> void:
	if lite_gpu():
		_build_sky_lite_target()
	_rays_mat = ShaderMaterial.new()
	_rays_mat.shader = _shared_rays_shader() if _sky_canvas == null else _shared_rays_shader_vp()
	_rays = ColorRect.new()
	_rays.color = Color(1, 1, 1, 1)         # the fragment fully owns COLOR; this just draws the quad
	_rays.material = _rays_mat
	_rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _sky_canvas != null:
		# In-target only: every night term is zero past UV.y 0.96 — the shaft
		# fade dies there, bloom/halo die higher (source_radius caps them), and
		# the motes live in the native dust pass — so the quad stops at the
		# band and uv_scale rebuilds the full-screen UV (texel-identical by
		# construction; the target clears the rest to transparent, which is
		# exactly what the shader produced there). Desktop keeps the full quad.
		_rays.anchor_bottom = 0.96
		_rays_mat.set_shader_parameter("uv_scale", Vector2(1.0, 0.96))
	# Direct path: additive blend lands on the layers beneath, as always.
	# Lite: into the sky target (premultiplied; composited by _sky_view).
	(_sky_canvas if _sky_canvas != null else backdrop_root()).add_child(_rays)

## Light comes in two moods, chosen by the theme's brightness — and, crucially, by
## two DIFFERENT techniques, because you can add light to a dark sky but not to a
## bright one:
##  • NIGHT (dark themes) — the additive `_rays` layer: a cool MOON glow at the
##    origin, faint moonbeams, and drifting STARDUST across the sky.
##  • DAY (light themes) — the `_day_*` stack (normal blend, so it can cast soft
##    SHADOW): a dawn-sky colour wash, cathedral sunbeams whose gaps fall into a
##    cool shade, floating bokeh, and warm sun-kissed corners (the vignette).
## Only one stack is ever visible, so there is no extra cost per theme.
func _paint_rays() -> void:
	if _rays_mat == null or _day_mat == null:
		return
	var p := ThemeManager.palette()
	var is_light: bool = bool(p.get("is_light", false))
	var accent: Color = p.get("accent", Color(1, 1, 1))
	var hue: float = accent.h
	# More off-centre than a hair so the shafts fall on a visible diagonal, not a
	# dead-vertical column — each theme's hue sets which way the light leans.
	var src_x: float = clampf(0.5 + (hue - 0.5) * 0.55, 0.30, 0.70)
	var vp := size
	if vp.x <= 0.0:
		vp = get_viewport_rect().size
	var aspect: float = maxf(vp.x, 1.0) / maxf(vp.y, 1.0)

	_rays.visible = not is_light
	_day_wash.visible = is_light
	_day_rays.visible = is_light
	# Lite: the blit adds at night and mixes by day (see _SKY_COMPOSITE), the
	# quarter target carries shafts only, and the mote pass takes the mood's
	# program at native res.
	if _sky_view_mat != null:
		_sky_view_mat.set_shader_parameter("additive", 0.0 if is_light else 1.0)
	if _dust_rect != null:
		_dust_mat.shader = _shared_dust_shader(is_light)
		# Both dust programs are zero below their per-pixel sky mask (night
		# 0.78 / day 0.92), so the native-res quad covers only the live band —
		# the single biggest transparent-overdraw cut here (studio rule 3.10).
		# uv_scale rebuilds the full-screen UV over the band, texel-identical
		# by construction; the mask's smoothstep reaches zero WITH zero slope,
		# so the quad's new bottom edge cannot read as a line.
		var band := 0.92 if is_light else 0.78
		_dust_rect.anchor_bottom = band
		_dust_mat.set_shader_parameter("uv_scale", Vector2(1.0, band))
		_dust_mat.set_shader_parameter("aspect", aspect)
		_dust_mat.set_shader_parameter("motion", 1.0)
	if is_light:
		_paint_day(p, accent, hue, src_x, aspect)
		return

	# NIGHT: a cool moon + stardust (additive).
	var night_col := Color(0.90, 0.94, 1.0).lerp(accent, 0.5)
	_rays_mat.set_shader_parameter("night", 1.0)
	_rays_mat.set_shader_parameter("shafts_only", 1.0 if _dust_rect != null else 0.0)
	if _dust_rect != null:
		_dust_mat.set_shader_parameter("ray_color", night_col)
		_dust_mat.set_shader_parameter("dust_intensity", 0.56)
	_rays_mat.set_shader_parameter("ray_color", night_col)
	_rays_mat.set_shader_parameter("intensity", 0.24)     # shaft_scale trims this in-shader
	# Stardust glints rather than glows. The grain itself stays sharp and slow; this
	# is purely how much presence it carries. Sharpening cut the lit AREA by roughly
	# 5x on its own and thinning the field cut it again, so brightness is the axis
	# that has to give some back for the other reductions to read at all — pushed
	# below ~0.40 the motes disappear at 1x on a phone. Range in practice: 0.40 for
	# a near-empty sky, 0.56 here, 0.70+ before points start reading as hard specks.
	_rays_mat.set_shader_parameter("dust_intensity", 0.56)
	_rays_mat.set_shader_parameter("source_glow", 0.44)   # a soft luminous moon
	_rays_mat.set_shader_parameter("source_radius", 0.46)
	_rays_mat.set_shader_parameter("source_falloff", 1.7) # gentle disc, no hot core
	_rays_mat.set_shader_parameter("source", Vector2(src_x, -0.12))
	_rays_mat.set_shader_parameter("seed", hue * 10.0)
	_rays_mat.set_shader_parameter("aspect", aspect)
	_rays_mat.set_shader_parameter("time_scale", 0.03)
	_rays_mat.set_shader_parameter("motion", 1.0)

# --- Day sky (light themes) ---------------------------------------------------
## Cathedral sunbeams + bokeh, drawn with NORMAL blend so the shafts read on a
## bright background by CONTRAST — the lit beams warm the air while the gaps fall
## into a soft cool shade. Additive light would be invisible here.
const _DAY_SHADER := """
shader_type canvas_item;

uniform mediump vec4 beam_warm : source_color = vec4(1.0, 0.95, 0.82, 1.0);
uniform mediump vec4 shade_col : source_color = vec4(0.42, 0.40, 0.55, 1.0);
uniform mediump vec4 bokeh_col : source_color = vec4(1.0, 0.86, 0.92, 1.0);
uniform mediump float beam_strength = 0.18;
uniform mediump float shade_strength = 0.10;
uniform mediump float bokeh_strength = 0.14;
// highp (default) below: source/seed feed the angle + hash inputs, aspect
// feeds the bokeh cell math, and time_scale/motion multiply TIME — none of
// these may quantise (gaming/knowledge 03 §1).
uniform vec2 source = vec2(0.5, -0.12);
uniform float aspect = 0.46;
uniform float seed = 0.0;
uniform float time_scale = 0.03;
uniform float motion = 1.0;
// Lite: 1 removes the bokeh layer from THIS pass — the crisp orbs are re-drawn
// at native res by the dedicated dust pass (see _DUST_DAY). 0 everywhere else.
uniform mediump float shafts_only = 0.0;
// Lite: the in-target quad covers only the band this program can light (every
// term is zero past UV.y 0.98 — the fade below); suv rebuilds the full-screen
// UV over that band, so every surviving texel is computed from identical
// coordinates. Defaults are the exact identity for full-rect quads.
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);

// Sinless hashes (Hoskins-style): fract/mul only. The sin() the old ones leaned
// on is a transcendental — cheap on desktop, genuinely expensive on phone GPUs,
// and these shaders evaluate ~10 hashes per pixel over the whole screen. The
// noise CHARACTER is identical; only the (random) layout instance changes.
float hash1(float x) { x = fract(x * 0.1031); x *= x + 33.33; return fract(x * (x + x)); }
float hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float n1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash1(i), hash1(i + 1.0), f);
}
float beams(float x) {
	float s = 0.0;
	s += 0.55 * n1(x * 1.0 + seed);
	s += 0.30 * n1(x * 2.3 + seed * 1.7);
	s += 0.15 * n1(x * 5.1 + seed * 2.9);
	return s;
}
void fragment() {
	// Precision: same split as _RAYS_SHADER — coordinate spine, hashes and
	// TIME terms highp; masks/fades/colour mixes mediump (knowledge 03 §1).
	vec2 apx = vec2(aspect, 1.0);
	vec2 suv = UV * uv_scale + uv_offset;
	vec2 rel = suv - source;
	rel.x *= aspect;
	float ang = atan(rel.x, rel.y);
	mediump float raw = beams(ang * 11.0 + TIME * time_scale);
	mediump float col_mask = 1.0 - smoothstep(0.20, 1.55, abs(ang));
	mediump float fade = smoothstep(-0.10, 0.18, suv.y) * (1.0 - smoothstep(0.28, 0.98, suv.y));
	// Lit shafts vs shadowed gaps — this contrast is what makes beams visible on white.
	mediump float lit = smoothstep(0.34, 0.92, raw) * col_mask * fade;
	mediump float shadow = (1.0 - smoothstep(0.06, 0.42, raw)) * col_mask * fade;

	// Bokeh — sparse translucent orbs drifting down, carrying their own colour so
	// they read on a bright backdrop where additive sparkles cannot. Same treatment
	// as the night stardust: a defined disc with a crisp edge rather than a smudge,
	// fewer of them, and half the drift. On a light ground a soft wide orb has
	// almost no contrast to spend, so definition is what makes it visible at all.
	vec2 duv = suv * apx;
	duv.y += TIME * 0.01 * motion;
	vec2 cell = duv * 24.0;
	vec2 gi = floor(cell);
	mediump vec2 gf = fract(cell) - 0.5;
	mediump float present = step(0.78, hash2(gi));
	mediump vec2 jit = vec2(hash2(gi + 3.1), hash2(gi + 8.7)) - 0.5;
	mediump float d = length(gf - jit * 0.7);
	mediump float bcore = 1.0 - smoothstep(0.04, 0.24, d);
	mediump float bok = bcore * bcore * present;
	mediump float bokeh = bok * (1.0 - smoothstep(0.0, 0.92, suv.y));

	// One straight-alpha colour: weighted-average hue, summed coverage (the three
	// contributions are mostly spatially exclusive, so this reads cleanly).
	// 0.0001 sits inside FP16's normal range (min normal ~6.1e-5), so the
	// guard divide is mediump-safe.
	mediump float wsh = shadow * shade_strength;
	mediump float wbe = lit * beam_strength;
	mediump float wbo = bokeh * bokeh_strength * (1.0 - shafts_only);
	mediump float wsum = wsh + wbe + wbo;
	mediump vec3 col = (shade_col.rgb * wsh + beam_warm.rgb * wbe + bokeh_col.rgb * wbo) / max(wsum, 0.0001);
	COLOR = vec4(col, clamp(wsum, 0.0, 1.0));
}
"""

func _build_day() -> void:
	# Dawn-sky wash: a soft warm gradient at the top gives the flat light backdrop
	# real sky colour (tinted per theme in _paint_day).
	_day_wash_grad = GradientTexture2D.new()
	_day_wash_grad.fill = GradientTexture2D.FILL_LINEAR
	_day_wash_grad.fill_from = Vector2(0.0, 0.0)
	_day_wash_grad.fill_to = Vector2(0.0, 1.0)
	_day_wash_grad.width = 8
	_day_wash_grad.height = 256
	_day_wash = TextureRect.new()
	_day_wash.texture = _day_wash_grad
	_day_wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_day_wash.stretch_mode = TextureRect.STRETCH_SCALE
	_day_wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_day_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_day_wash.visible = false
	backdrop_root().add_child(_day_wash)
	# Cathedral sunbeams + bokeh (normal blend, so shafts can cast soft shadow).
	_day_mat = ShaderMaterial.new()
	_day_mat.shader = _shared_day_shader()
	_day_rays = ColorRect.new()
	_day_rays.color = Color(1, 1, 1, 1)
	_day_rays.material = _day_mat
	_day_rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_day_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_day_rays.visible = false
	if _sky_canvas != null:
		# In-target only: the day fade dies at UV.y 0.98 (bokeh at 0.92), so
		# the quad stops at the band; uv_scale rebuilds the full-screen UV
		# (texel-identical by construction — see _build_rays for the pattern).
		_day_rays.anchor_bottom = 0.98
		_day_mat.set_shader_parameter("uv_scale", Vector2(1.0, 0.98))
	# Lite: into the sky target (normal blend premultiplies onto transparent,
	# which the composite's day mode reproduces exactly).
	(_sky_canvas if _sky_canvas != null else backdrop_root()).add_child(_day_rays)

func _paint_day(p: Dictionary, accent: Color, hue: float, src_x: float, aspect: float) -> void:
	# Dawn wash: a warm pastel sky at the top leaning to the accent, gone by mid-screen.
	var sky := Color(1.0, 0.86, 0.72).lerp(accent, 0.35)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([
		Color(sky.r, sky.g, sky.b, 0.34),
		Color(sky.r, sky.g, sky.b, 0.10),
		Color(sky.r, sky.g, sky.b, 0.0)])
	_day_wash_grad.gradient = g
	# Cathedral beams: warm sunlight in the shafts, a cool shadow of the theme's own
	# text colour in the gaps, bokeh in a soft accent pastel.
	var shade: Color = p.get("text", Color(0.3, 0.3, 0.4))
	var bokeh_col := Color(1.0, 0.92, 0.96).lerp(accent, 0.40)
	_day_mat.set_shader_parameter("shafts_only", 1.0 if _dust_rect != null else 0.0)
	if _dust_rect != null:
		_dust_mat.set_shader_parameter("bokeh_col", bokeh_col)
		_dust_mat.set_shader_parameter("bokeh_strength", 0.13)
	_day_mat.set_shader_parameter("beam_warm", Color(1.0, 0.95, 0.82).lerp(accent, 0.20))
	_day_mat.set_shader_parameter("shade_col", shade.lerp(accent, 0.25))
	_day_mat.set_shader_parameter("bokeh_col", bokeh_col)
	_day_mat.set_shader_parameter("beam_strength", 0.18)
	_day_mat.set_shader_parameter("shade_strength", 0.10)
	# Matches the stardust, and carried a touch higher for the same reason: a defined
	# orb covers far fewer pixels than the soft wide one it replaced, and on a BRIGHT
	# ground there is less contrast to spend in the first place. The beams and shade
	# keep their strengths — only the motes were asked to change.
	_day_mat.set_shader_parameter("bokeh_strength", 0.13)
	_day_mat.set_shader_parameter("source", Vector2(src_x, -0.12))
	_day_mat.set_shader_parameter("seed", hue * 10.0)
	_day_mat.set_shader_parameter("aspect", aspect)
	_day_mat.set_shader_parameter("time_scale", 0.03)
	_day_mat.set_shader_parameter("motion", 1.0)

# --- Background ---------------------------------------------------------------
func _build_background() -> void:
	# Lite path: everything below goes into the reduced-res target instead of the
	# screen — see _build_backdrop_target for the whole story.
	if lite_gpu():
		_build_backdrop_target()

	# A soft diagonal pastel gradient (bg0 → bg_grad) gives the backdrop the
	# reference's calm wash. On dark themes the two stops are close, so it reads
	# as a subtle, premium vignette rather than a hard band.
	_bg_grad = GradientTexture2D.new()
	_bg_grad.fill = GradientTexture2D.FILL_LINEAR
	_bg_grad.fill_from = Vector2(0.0, 0.0)
	_bg_grad.fill_to = Vector2(1.0, 1.0)
	_bg_grad.width = 256
	_bg_grad.height = 256
	_bg = TextureRect.new()
	_bg.texture = _bg_grad
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop_root().add_child(_bg)

	# A single large, very soft radial glow near the top gives the flat dark
	# background quiet depth — the "expensive" feel — without any gradient banding.
	# Positioned by _place_disc (see _layout_discs), never by anchors: the disc has
	# to be free to hang off the screen so its falloff is never cut.
	_glow = TextureRect.new()
	_glow.texture = _make_glow_texture()
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.modulate.a = 0.5
	backdrop_root().add_child(_glow)

	# Theme-tinted light shafts falling from above (built here so they sit over the
	# gradient + glow and are captured by the frost source below). Night uses the
	# additive rays; day uses the cathedral/wash stack — only one shows per theme.
	_build_rays()
	_build_day()
	# Lite: the sky blit must sit where the quads would have — ABOVE the day
	# wash (beams draw over the sky colour), below the blobs added next.
	if _sky_view != null:
		_backdrop_canvas.move_child(_sky_view, _backdrop_canvas.get_child_count() - 1)

	# Soft pastel "blobs" add airy depth (most visible on light themes). Each is a
	# large faint radial disc anchored to a corner; colours are set per theme.
	for i in 3:
		var blob := TextureRect.new()
		blob.texture = _make_glow_texture()
		blob.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		blob.stretch_mode = TextureRect.STRETCH_SCALE
		blob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backdrop_root().add_child(blob)
		_blobs.append(blob)

	# Desktop: a back-buffer copy so glass cards can sample + blur the backdrop
	# behind them. It captures everything drawn before it; screens drop their
	# living FX / flowing tiles just BENEATH it (see place_in_backdrop) so the
	# frost includes the theme's motion too. The content frame draws AFTER it,
	# so cards never frost each other or the UI.
	# Lite: DELIBERATELY ABSENT. Glass samples the backdrop target instead
	# (backdrop_texture()), so no copy, no mip chain and no mid-frame tiler
	# flush exist on device at all — that absence is most of round 2's win.
	if not lite_gpu():
		_bbc = BackBufferCopy.new()
		_bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		add_child(_bbc)

	_paint_background()

## Adds a layer to the backdrop slot — beneath the content frame, over the
## screen's soft wash. Build/insertion ORDER is the z-order contract in both
## paths: callers add bottom-most first, exactly as before.
##
## On desktop that slot is just beneath the frost snapshot (_bbc), so glass
## cards frost the layer. On lite these layers stay in the MAIN tree at native
## resolution — the first cut rendered them inside the half-res target and the
## drifting tiles, star glitters and theme particles (arctic's snowflakes) were
## visibly soft on a tablet panel; device-rejected. Only the genuinely soft
## wash (gradient / glow / blobs / sky) lives in the reduced target now, so
## the frost blurs the wash while everything crisp stays crisp. The one
## visual consequence: layers in this slot no longer appear INSIDE the frost
## blur — through a pane you see them at the pane's see-through weight only,
## which reads near-identically at the frost's low opacity.
func place_in_backdrop(node: Node) -> void:
	if lite_gpu():
		add_child(node)
		if _frame != null:
			move_child(node, _frame.get_index())
	else:
		add_child(node)
		move_child(node, _bbc.get_index())

func _paint_background() -> void:
	# A theme repaint must reach the screen on THIS frame, exactly as it did
	# when the target rendered every frame; the short hold also spans the sky
	# target's next 30 Hz tick so the repainted shafts blit as soon as they
	# render, then the backdrop falls back to the ticked mode.
	_hold_backdrop(0.1)
	var p := ThemeManager.palette()
	var grad := Gradient.new()
	grad.set_color(0, p["bg0"])
	grad.set_color(1, p.get("bg_grad", p["bg0"]))
	_bg_grad.gradient = grad
	var is_light: bool = bool(p.get("is_light", false))
	# A touch more glow on light themes so the violet wash reads near the top.
	var a: float = 0.16 if is_light else 0.10
	if neutral_page(p):
		a = 0.0
	_glow.modulate = Color(p["accent"].r, p["accent"].g, p["accent"].b, a)

	# Tint the depth blobs: airy pastels on light themes, restrained accent on dark.
	var cols: Array = [p["accent"], Color("EF7DB4"), Color("FFB37A")]
	if not is_light:
		cols = [p["accent"], p["accent"], p.get("gold", p["accent"])]
	var blob_a: float = 0.34 if is_light else 0.10
	if neutral_page(p):
		# A neutral page: grey depth only, and little of it (see neutral_page).
		var ink: Color = p["text"]
		cols = [ink, ink, ink]
		blob_a = 0.05
	# The old fill-rate guard (blobs hidden on dark themes on mobile) is retired:
	# the blobs now live inside the half-res backdrop target on the lite path, so
	# the three near-screen quads cost a quarter of what they did when this guard
	# was written — dark themes get their airy depth back on device.
	for i in _blobs.size():
		var c: Color = cols[i]
		_blobs[i].visible = blob_a > 0.0
		_blobs[i].modulate = Color(c.r, c.g, c.b, blob_a if i == 0 else blob_a * 0.85)
	_layout_discs()
	_paint_rays()
	_paint_vignette()

## Places a disc rect so the shared texture's falloff lands entirely INSIDE it.
##
## `_shared_glow` fades to nothing at exactly half its own width (see
## _make_glow_texture), so a rect of side 2r centred on `c` draws a disc of
## radius r whose edge alpha is zero — no matter where the rect sits relative to
## the screen. Everything decorative goes through here for that reason: a
## TextureRect clips at its rect, so any disc whose gradient is still opaque when
## it reaches the rect edge draws a HARD LINE across the screen.
func _place_disc(tr: TextureRect, centre: Vector2, radius: float) -> void:
	tr.size = Vector2(radius * 2.0, radius * 2.0)
	tr.position = centre - Vector2(radius, radius)

## The glow + the three depth blobs, laid out as centre/radius pairs.
##
## These were once rects with the disc baked into a corner of each, which cut the
## bottom-centre blob's falloff off along its own top edge — a hard horizontal
## seam at 0.43 of screen height, on every screen and every palette (measured at
## 5-13/255 per channel; the strongest edge in an otherwise smooth frame). The
## centres and radii below reproduce the old discs EXACTLY, so nothing moves; only
## the previously-clipped part of the falloff is now drawn.
func _layout_discs() -> void:
	if _blobs.size() < 3:
		return
	var vp := size
	if vp.x <= 0.0:
		vp = get_viewport_rect().size
	# Glow: what STRETCH_KEEP_ASPECT_COVERED used to produce — the square texture
	# scaled to cover the screen and centred, so the core sits 0.28 down the
	# covering square and the falloff reaches 0.67 of it.
	if _glow != null:
		var cover := maxf(vp.x, vp.y)
		_place_disc(_glow,
			Vector2(vp.x * 0.5, (vp.y - cover) * 0.5 + cover * 0.28),
			cover * 0.67)
	# Blobs: old rect origin + the texture's core offset (0.5, 0.28) of the side.
	var d := maxf(vp.x, vp.y) * 0.95
	var centres := [
		Vector2(d * 0.18, d * 0.08),            # violet, top-left
		Vector2(vp.x - d * 0.18, d * 0.02),     # pink, top-right
		Vector2(vp.x * 0.5, vp.y - d * 0.32),   # peach, bottom-center
	]
	for i in 3:
		_place_disc(_blobs[i], centres[i], d * 0.67)

## The soft radial disc behind `_glow` AND all three depth blobs.
##
## It is built from literals only — no palette, no viewport, no per-screen state —
## so the four textures every AppScreen used to allocate were bit-identical copies
## of each other (4 x 512² RGBA8 = 4 MiB, of which 3 MiB was pure duplication).
## One shared instance is created on first use and handed to all four. Nothing that
## affects the draw lives on the texture: every TextureRect keeps its own
## modulate / size / position / visible, so the pixels are unchanged.
## Deliberately a resource, never mutated after creation — do not assign a gradient
## or resize it from a caller.
##
## THE INVARIANT: the fill is centred and reaches zero at exactly half the
## texture's width, so alpha is 0 along every edge AND every corner. That is what
## lets a caller hang the disc half off-screen without the TextureRect's own rect
## slicing the falloff into a visible line. The core used to sit at 0.28 height
## with a 0.67 radius, which left alpha 0.58 across the texture's top edge — and
## the bottom-centre blob drew that edge straight across the middle of every
## screen. Keep the fill centred; place and size the disc with _place_disc.
static var _shared_glow: GradientTexture2D = null

func _make_glow_texture() -> GradientTexture2D:
	if _shared_glow != null:
		return _shared_glow
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 512
	tex.height = 512
	_shared_glow = tex
	return tex

# --- Content frame ------------------------------------------------------------
func _build_frame() -> void:
	_frame = MarginContainer.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_safe_area()
	add_child(_frame)

	content = UI.vbox(DesignSystem.SPACE_LG)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(content)

	# Re-apply safe area if the window changes (rotation, foldables).
	get_viewport().size_changed.connect(_apply_safe_area)
	get_viewport().size_changed.connect(_layout_discs)
	# The discs are placed in absolute coordinates rather than by anchors, so any
	# reshape of the screen itself has to re-place them — the viewport signal alone
	# would miss a resize that does not come from the window.
	resized.connect(_layout_discs)

func _apply_safe_area() -> void:
	var pad: float = DesignSystem.SPACE_LG
	var top := pad; var bottom := pad
	var left := pad; var right := pad
	# The DEVICE inset alone (no design padding). The tab bar is placed against
	# this, not against `bottom`, so it hugs the gesture pill instead of floating
	# a whole SPACE_LG above it.
	var inset_bottom := 0.0

	var safe := DisplayServer.get_display_safe_area()
	var win  := DisplayServer.window_get_size()
	if win.x > 0 and win.y > 0:
		# Map physical insets → design pixels using the live viewport scale.
		var vp := get_viewport_rect().size
		var sx := vp.x / float(win.x)
		var sy := vp.y / float(win.y)
		if safe.size.y > 0 and safe.size.y < win.y:
			top    += safe.position.y                              * sy
			inset_bottom = (win.y - safe.position.y - safe.size.y) * sy
			bottom += inset_bottom
		if safe.size.x > 0 and safe.size.x < win.x:
			left  += safe.position.x                              * sx
			right += (win.x - safe.position.x - safe.size.x)     * sx

	# The tab bar is a SIBLING of the frame (so a content rebuild never touches
	# it) pinned across the bottom, and the frame gives back exactly the strip it
	# occupies — otherwise every screen's last card would sit under the bar.
	if is_instance_valid(_nav):
		_nav.anchor_left = 0.0
		_nav.anchor_top = 1.0
		_nav.anchor_right = 1.0
		_nav.anchor_bottom = 1.0
		_nav.offset_left = left
		_nav.offset_right = -right
		_nav.offset_top = -(inset_bottom + NAV_GAP + BottomNav.BAR_HEIGHT)
		_nav.offset_bottom = -(inset_bottom + NAV_GAP)
		bottom = inset_bottom + NAV_GAP + BottomNav.BAR_HEIGHT + NAV_GAP

	_frame.add_theme_constant_override("margin_top",    int(top))
	_frame.add_theme_constant_override("margin_bottom", int(bottom))
	_frame.add_theme_constant_override("margin_left",   int(left))
	_frame.add_theme_constant_override("margin_right",  int(right))

# --- Bottom tab bar -----------------------------------------------------------
## Air between the device inset, the bar, and the content above it.
const NAV_GAP := 12.0

## Override → the BottomNav tab this screen IS ("home", "achievements", "stats",
## "themes", "profile"). Anything else — gameplay, settings, the paywall, the
## boot chain — returns "" and gets no bar. The bar is for the five destinations
## a player moves between, not for every screen that can be on top of the stack.
func nav_tab() -> String:
	return ""

func _build_bottom_nav() -> void:
	var tab := nav_tab()
	if tab.is_empty():
		return
	_nav = BottomNav.new()
	_nav.active_tab = tab
	# Added AFTER _frame, so the bar draws over the content that scrolls beneath
	# its glass; _apply_safe_area then hands the content its inset back.
	add_child(_nav)
	_apply_safe_area()

## True when `p` (global coords) lands on the tab bar. Screens that read raw
## touches out of `_input` ask this before claiming a press — see Home, whose
## grabbable tile field otherwise catches drags THROUGH the bar.
func point_over_nav(p: Vector2) -> bool:
	return is_instance_valid(_nav) and _nav.get_global_rect().has_point(p)

# --- Standard navigation header ----------------------------------------------
## A back chevron + centered title, used by secondary screens.
func nav_header(title_text: String, on_back: Callable = Callable()) -> Control:
	# Reference-style chrome: a circular frosted back chip + a large centered title.
	return UI.top_bar(title_text, func():
		if on_back.is_valid():
			on_back.call()
		else:
			SceneRouter.back())

# --- Backdrop reveal ----------------------------------------------------------
## Reveals the DECORATIVE backdrop from nothing over `duration`, each layer
## returning to the resting alpha the theme gave it.
##
## For screens arriving from a scene that does not share their palette. The router
## crossfades through a flat bg0 curtain, so without this the theme's motif, light
## shafts and depth blobs all land at full strength on frame one — before any
## content is on top of them — and the player gets a beat of bare wallpaper that
## looks nothing like the screen they just left. Faded up behind the entrance, the
## theme *develops* into place instead of cutting in.
##
## The base gradient is deliberately NOT faded: it is the same colour family as the
## curtain, so leaving it opaque is exactly what makes frame one continuous. Fading
## it too would reveal whatever lies behind the screen instead.
##
func fade_in_backdrop(duration: float = 0.8, delay: float = 0.0) -> void:
	# Several fading layers render inside the ticked backdrop target on the
	# lite path; hold it in per-frame mode for the tween's full run so the
	# fade never steps at 30 Hz, then drop back to the ticked cadence.
	_hold_backdrop(delay + duration)
	for layer: CanvasItem in _backdrop_layers():
		var target: float = layer.modulate.a
		layer.modulate.a = 0.0
		var t := layer.create_tween()
		t.tween_property(layer, "modulate:a", target, duration).set_delay(delay) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

## Every decorative layer the base screen owns, skipping the base gradient (see
## fade_in_backdrop) and anything a subclass chose not to build.
func _backdrop_layers() -> Array[CanvasItem]:
	var out: Array[CanvasItem] = []
	for n: CanvasItem in [_glow, _vignette, _living_fx, _rays, _day_wash, _day_rays]:
		if is_instance_valid(n):
			out.append(n)
	for b: TextureRect in _blobs:
		if is_instance_valid(b):
			out.append(b)
	return out

# --- Entrance animation -------------------------------------------------------
func _animate_in() -> void:
	if custom_entrance:
		return
	# A calm fade with a whisper of scale, so the screen "arrives" rather than just
	# appearing. Position is owned by the MarginContainer, so we animate only the
	# things we control (alpha + visual scale) to avoid fighting the layout pass.
	content.pivot_offset = content.size * 0.5
	content.modulate.a = 0.0
	content.scale = Vector2(0.985, 0.985)
	var tw := create_tween().set_parallel(true)
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(content, "modulate:a", 1.0, DesignSystem.DUR_SLOW)
	tw.tween_property(content, "scale", Vector2.ONE, DesignSystem.DUR_SLOW)

## Cascades a list of nodes in (fade + gentle settle), each slightly delayed.
## Scale is used (not position) so it never fights container layout. Call from a
## subclass's on_ready() after one frame so sizes are valid.
func stagger_in(nodes: Array, step: float = 0.05) -> void:
	var i := 0
	for n in nodes:
		if not (n is Control):
			continue
		var c := n as Control
		# Pivot at the bottom-centre so the scale-up reads as each card *rising* into
		# place from just below, with a gentle overshoot, instead of a flat fade.
		c.pivot_offset = Vector2(c.size.x * 0.5, c.size.y)
		c.modulate.a = 0.0
		c.scale = Vector2(0.96, 0.92)
		var t := c.create_tween().set_parallel(true)
		t.tween_property(c, "modulate:a", 1.0, 0.34).set_delay(i * step) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_property(c, "scale", Vector2.ONE, 0.52).set_delay(i * step) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		i += 1
