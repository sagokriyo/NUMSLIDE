class_name GlassPanel
extends PanelContainer
## GlassPanel — a real frosted-glass surface. It samples and blurs the backdrop
## behind the card (via AppScreen's BackBufferCopy) and lays a theme-tinted frost
## over it, so the card reads as a clean pane over a soft wash instead of a flat
## translucent rectangle. Because it frosts whatever is *actually* behind it, it
## adapts to light and dark themes on its own — no per-theme edge tricks.
##
## An opaque rounded StyleBoxFlat gives the pane its silhouette (rounded, anti-
## aliased corners) and its content padding; the glass shader paints the frosted
## glass into that shape. Palette-derived uniforms restyle it with the theme.
##
## ONE MATERIAL, EVERY SILHOUETTE. Cards, ModalOverlay, the bottom nav, the
## currency pills, Home's identity capsule and the gameplay control buttons are
## all this pane at different radii — see `radius`. What separates a shard from a
## panel is that it has NO EDGE: the flat `UI.glass_box` stylebox draws a 1px
## hairline around itself, and a screen of those reads as line art rather than
## glass, which is why the surfaces the player actually looks at are all here.
## glass_box survives for the incidental plaques and tickets that are drawn ON a
## card, where a frosted pane over a frosted pane would say nothing.

const _SHADER: Shader = preload("res://ui/shaders/glass.gdshader")
const _SHADER_LITE: Shader = preload("res://ui/shaders/glass_lite.gdshader")

## The lite path frosts AppScreen's reduced-res backdrop target instead of the
## live screen (no BackBufferCopy, no mip chain — see glass_lite.gdshader).
## Found by walking ancestors, so cards inside modals hosted on an AppScreen
## get it too; a pane with no AppScreen above it (shouldn't happen in shipping
## trees) falls back to the screen-reading shader and still renders.
## The wash the pane frosts (AppScreen.frost_texture), or null when there is no
## AppScreen above — a bare pane then falls back to the screen-reading shader.
func _find_backdrop() -> Texture2D:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("frost_texture"):
			var tex: Variant = n.call("frost_texture")
			if tex is Texture2D:
				return tex
		n = n.get_parent()
	return null

var elevation: int = 1
## Frost strength override, 0..1. Negative keeps the per-theme default below.
##
## For panes that are READ AND TYPED INTO rather than looked at — the identity
## sheet's two text fields sat over a page whose own headings showed clean through
## the glass, behind the very characters the player was editing. Opt-in, because
## the default really is meant to be very see-through (that is the material).
var opacity_override: float = -1.0
## The pane's corner radius. RADIUS_PILL turns the same material into a chip or a
## capsule, which is the whole reason the app's pills no longer hand-roll a flat
## bordered box: ONE shard, several silhouettes. Set it before the pane enters
## the tree — the stylebox is built once, in _enter_tree.
var radius: float = DesignSystem.RADIUS_LG
# Dense grids (Statistics' stat cells) need a tighter pad than the default card
# air, or their clipped single-line labels lose the width the text needs.
var content_margin: float = DesignSystem.SPACE_LG
## Per-side padding for the panes that are not square about it — the identity
## capsule wants its badge nearly flush left and real air after the text. Any
## side left NEGATIVE falls back to `content_margin`, so a pane that wants
## uniform air still sets one number. Read in _enter_tree with everything else.
var margin_left: float = -1.0
var margin_right: float = -1.0
var margin_top: float = -1.0
var margin_bottom: float = -1.0
## Pushes the frost this fraction of the way from its per-theme milk toward
## opaque (0 = the card default). A LERP rather than a multiplier so it reads the
## same on both ends of the palette range — the lights already start at 0.40, and
## scaling that by the factor a dark theme needs would render a light pill in
## flat white.
##
## It exists for the PILLS (see UI.glass_pill). A card is large, sits on textured
## backdrop and carries its own content, so a 3% veil is enough to say glass. A
## chip is a tenth the area over whatever happens to be behind it, and at the
## card's weight the Undo button on a dark board simply was not there — the
## frost has to do alone what the card gets from its size.
var frost_boost: float = 0.0

func _init() -> void:
	# Cards are surfaces, not buttons — let touches pass through to an ancestor
	# ScrollContainer (tappable() re-asserts its own filter where a card is tapped).
	mouse_filter = Control.MOUSE_FILTER_PASS

func _enter_tree() -> void:
	var p := ThemeManager.palette()
	# The silhouette + padding: an opaque rounded box the shader paints glass into.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 1)
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	sb.set_content_margin_all(content_margin)
	if margin_left >= 0.0:
		sb.content_margin_left = margin_left
	if margin_right >= 0.0:
		sb.content_margin_right = margin_right
	if margin_top >= 0.0:
		sb.content_margin_top = margin_top
	if margin_bottom >= 0.0:
		sb.content_margin_bottom = margin_bottom
	add_theme_stylebox_override("panel", sb)

	var is_light: bool = bool(p.get("is_light", false))
	var mat := ShaderMaterial.new()
	var backdrop := _find_backdrop()
	if backdrop != null:
		mat.shader = _SHADER_LITE
		mat.set_shader_parameter("backdrop_tex", backdrop)
	else:
		# The screen-reading fallback costs a per-frame framebuffer copy + tiler
		# flush. Legitimate on desktop; on the lite path it means the AppScreen
		# ancestry broke and the zero-screen-reader design silently regressed.
		if OS.is_debug_build() and AppScreen.lite_gpu():
			push_warning("GlassPanel: no AppScreen backdrop above %s — screen-reading glass shader on the lite path" % get_path())
		mat.shader = _SHADER
	# Higher cards blur a touch more, so stacked surfaces read with depth.
	mat.set_shader_parameter("blur_px", 10.0 + float(elevation) * 1.5)
	mat.set_shader_parameter("tint", _tint(is_light))
	# No gloss on the pane: the lit top band and the hairline that used to ring
	# every card reads as fog caught along the edges of the shard, not as glass.
	# The pane is clear material and nothing else, so both are OFF — and the card's
	# contrast is not their job anyway. It comes from the palette: the contrast pass
	# gives everything ON the card (its type, its controls, its dividers) a real
	# step, which is what makes a card read without ever making it a panel.
	mat.set_shader_parameter("top_sheen", 0.0)
	mat.set_shader_parameter("rim", 0.0)
	# Clearer than clear glass used to be: the shader composites to
	# backdrop*(1 - tint.a*opacity) + tint.a*opacity, so the darks now lay a 3.4%
	# white veil where they laid 4.8%, and the lights 17.6% where they laid 23%.
	# What you see through a card is very nearly what is behind it, softened by the
	# blur — which is the ONE thing here that says "glass" and stays.
	var frost: float = 0.34 if not is_light else 0.44
	if opacity_override >= 0.0:
		frost = opacity_override
	mat.set_shader_parameter("opacity", frost)
	# The travelling sheen: a whisper of moving light every ~7–12 s, each pane on
	# its own clock so a screen of cards never flashes in unison. Reduce-motion
	# leaves it at 0 — which also makes the shader's sheen branch dead, exactly
	# as glass.gdshader's comment promises (it was previously always live).
	mat.set_shader_parameter("sheen",
		0.0 if SettingsManager.reduce_motion() else 0.05)
	mat.set_shader_parameter("sheen_period", randf_range(7.0, 12.0))
	mat.set_shader_parameter("phase", randf() * 20.0)
	material = mat

## The milky frost laid over the blurred backdrop: barely a breath of white on the
## darks (the pane is clear glass, not a panel), more on the lights, where a pale
## backdrop through clear glass would leave nothing to see at all.
func _tint(is_light: bool) -> Color:
	var a: float = 0.40 if is_light else 0.10
	return Color(1, 1, 1, a + (1.0 - a) * clampf(frost_boost, 0.0, 1.0))
