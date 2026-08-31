class_name PipelineWarmup
extends Control
## Draws one tiny instance of every code-built canvas material the first real
## screens use, so their Vulkan pipelines compile behind the splash animation
## instead of hitching the first Home frame or the first scroll (canvas
## pipelines are excluded from the engine's automatic precompilation — studio
## rule 3.14/9.5, gaming/RULES.md). Measured motivation: the one frame-drop
## left on the reference tablet was the FIRST fling revealing below-fold cards
## whose materials had never been drawn. Coverage now also spans the code-built
## effect families that used to compile at route entry: BoardFx's five motif
## statics, the active theme's shader-backed RewardFx effect, CrystalStorm's
## shared storm pass, MergeBlob's premult blit and the themed-icon tint.
##
## The whole strip lives in a 24 px corner at ~2% opacity for a few frames,
## then frees itself. Opacity must stay ABOVE zero: an invisible canvas item
## is culled before it ever reaches the GPU, compiling nothing.
##
## It also answers `backdrop_texture()` with a 4×4 placeholder so GlassPanel /
## ExtrudedWord pick their LITE shaders here exactly as they will on a real
## AppScreen — warming the desktop screen-reading variant instead would compile
## the wrong pipeline AND reintroduce a backbuffer copy during the splash.

const _LIFE_FRAMES := 6

var _placeholder: ImageTexture
var _frames := 0

static func attach(host: Node) -> void:
	host.add_child(PipelineWarmup.new())

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.02
	position = Vector2.ZERO
	scale = Vector2(0.06, 0.06)
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.1, 0.2, 1.0))
	_placeholder = ImageTexture.create_from_image(img)

func backdrop_texture() -> Texture2D:
	return _placeholder

func frost_texture() -> Texture2D:
	return _placeholder

func _ready() -> void:
	# Frosted card (glass_lite on the lite path via backdrop_texture above,
	# the screen-reading variant on desktop where that IS the shipping path).
	var pane := GlassPanel.new()
	pane.custom_minimum_size = Vector2(64, 48)
	add_child(pane)

	# Candy gradient with the animated sheen + candy branches live.
	var grad := GradientPanel.make(Color(0.5, 0.3, 0.9), Color(0.2, 0.5, 0.9), 12.0)
	grad.candy = 1.0
	grad.sheen = 1.0
	grad.custom_minimum_size = Vector2(64, 32)
	grad.position = Vector2(0, 60)
	add_child(grad)

	# The crystal wordmark: gloss (lite variant here), ground-fade, glitter.
	var word := ExtrudedWord.make("2", 40,
		Color(0.7, 0.4, 0.9), Color(0.3, 0.5, 0.9), Color(0.9, 0.6, 0.3))
	word.glass = 1.0
	word.position = Vector2(0, 110)
	add_child(word)

	# Badge shine sweep (profile capsule, tier screens).
	var badge := TierBadge.make_view(40.0, 0, false)
	badge.position = Vector2(80, 0)
	add_child(badge)

	# The transparent warm viewport. The AppScreen shafts render inside one on
	# the lite path, and BoardFx._shader_layer / RewardFx.Base.shader_layer host
	# their motif shaders inside one on EVERY platform — pipelines key on the
	# render-target format too, so those families must warm in kind. Hosted
	# quads rasterize at the viewport's own 16×16 regardless of this strip's
	# scale/modulate, so coverage in there is guaranteed.
	var vp := SubViewport.new()
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.size = Vector2i(16, 16)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	# The AppScreen sky set, in a framebuffer that matches the real one. The
	# backdrop blit (+ folded grain) draws direct to screen on every lite
	# AppScreen — first bind would otherwise compile at the first screen build.
	if AppScreen.lite_gpu():
		for sh: Shader in [AppScreen._shared_rays_shader_vp(), AppScreen._shared_day_shader()]:
			var quad := ColorRect.new()
			quad.size = Vector2(16, 16)
			var m := ShaderMaterial.new()
			m.shader = sh
			quad.material = m
			vp.add_child(quad)
		# Composite + native-res mote passes + the backdrop blit (folded grain)
		# draw straight to the screen — warm on the strip, not in the viewport.
		var flats: Array[Shader] = [AppScreen._shared_sky_composite_shader(),
			AppScreen._shared_dust_shader(false), AppScreen._shared_dust_shader(true),
			AppScreen._shared_backdrop_blit_shader()]
		for i in flats.size():
			var quad2 := ColorRect.new()
			quad2.size = Vector2(24, 8)
			quad2.position = Vector2(80, 60 + i * 10)
			var m2 := ShaderMaterial.new()
			m2.shader = flats[i]
			quad2.material = m2
			add_child(quad2)

	# --- The shader families the strip used to miss. On GL the first bind
	# compiles synchronously on the render thread (rule 9.5, gaming/RULES.md) —
	# the route-entry hitch — so each draws one tiny quad here instead. Every
	# lazy static is filled through the SAME null-check its owner's builder
	# performs, so the session later binds these exact Shader objects; a private
	# copy would compile a second program and leave the real first bind cold.

	# BoardFx's five motif statics. aurora/ribbon/caustics ship inside
	# _shader_layer's transparent SubViewport; grid + scanlines draw straight
	# to the screen. Warm each against the render target it will really use.
	BoardFx._aurora_shader = _ensure(BoardFx._aurora_shader, BoardFx._AURORA_CODE)
	BoardFx._ribbon_shader = _ensure(BoardFx._ribbon_shader, BoardFx._RIBBON_CODE)
	BoardFx._caustics_shader = _ensure(BoardFx._caustics_shader, BoardFx._CAUSTICS_CODE)
	BoardFx._grid_shader = _ensure(BoardFx._grid_shader, BoardFx._GRID_CODE)
	BoardFx._scan_shader = _ensure(BoardFx._scan_shader, BoardFx._SCAN_CODE)
	_warm(BoardFx._aurora_shader, vp, Vector2.ZERO, Vector2(16, 16))
	_warm(BoardFx._ribbon_shader, vp, Vector2.ZERO, Vector2(16, 16))
	_warm(BoardFx._caustics_shader, vp, Vector2.ZERO, Vector2(16, 16))
	_warm(BoardFx._grid_shader, self, Vector2(80, 100), Vector2(24, 8))
	_warm(BoardFx._scan_shader, self, Vector2(80, 110), Vector2(24, 8))

	# The active theme's RewardFx effect (it dresses Home too, so its material
	# binds on the very first screen). Only three reward motifs carry a
	# ShaderMaterial — all hosted via shader_layer's SubViewport; the rest draw
	# cached textures with the default canvas material, warm from frame one.
	match ThemeManager.bg_motif():
		"blackhole":
			RewardFx.Blackhole._shader = _ensure(
				RewardFx.Blackhole._shader, RewardFx.Blackhole._CODE)
			_warm(RewardFx.Blackhole._shader, vp, Vector2.ZERO, Vector2(16, 16))
		"inkwash":
			RewardFx.InkWash._paper_shader = _ensure(
				RewardFx.InkWash._paper_shader, RewardFx.InkWash._PAPER)
			_warm(RewardFx.InkWash._paper_shader, vp, Vector2.ZERO, Vector2(16, 16))
		"metaballs":
			RewardFx.Metaballs._shader = _ensure(
				RewardFx.Metaballs._shader, RewardFx.Metaballs._CODE)
			_warm(RewardFx.Metaballs._shader, vp, Vector2.ZERO, Vector2(16, 16))

	# The baked-mark blit (MarkBakery, Phase 1): the built-in canvas material's
	# PREMULT_ALPHA blend variant, textured like the real blit.
	var premult := CanvasItemMaterial.new()
	premult.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	var skin := TextureRect.new()
	skin.texture = _placeholder
	skin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	skin.size = Vector2(24, 8)
	skin.position = Vector2(80, 130)
	skin.material = premult
	add_child(skin)

	# The themed-icon luminance tint (UI.icon_material) — its real builder path,
	# so the shared static icon shader is the one warmed here.
	var icon := TextureRect.new()
	icon.texture = _placeholder
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.size = Vector2(24, 8)
	icon.position = Vector2(80, 140)
	icon.material = UI.icon_material(Color.WHITE)
	add_child(icon)

## Fills an owner's lazily-built static exactly as its builder would (same null
## check, same const source), returning the object the owner will keep reusing.
static func _ensure(current: Shader, code: String) -> Shader:
	if current != null:
		return current
	var sh := Shader.new()
	sh.code = code
	return sh

## One tiny warm quad. `host` picks the render target: SubViewport-shipped
## shaders warm inside the warm viewport; direct-to-screen ones warm on the
## strip itself, where the 0.02 modulate keeps alpha ABOVE zero (header note).
func _warm(sh: Shader, host: Node, pos: Vector2, sz: Vector2) -> void:
	var quad := ColorRect.new()
	quad.size = sz
	quad.position = pos
	var m := ShaderMaterial.new()
	m.shader = sh
	quad.material = m
	host.add_child(quad)

func _process(_delta: float) -> void:
	_frames += 1
	if _frames > _LIFE_FRAMES:
		queue_free()
