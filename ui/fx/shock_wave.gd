class_name ShockWave
extends Control
## A screen-space refraction ring: one expanding band that BENDS everything
## drawn beneath it — the world, the board, the glass — like a pressure wave
## through water, with a faint bright rim riding the crest.
##
## Structure: [BackBufferCopy, shader quad], in that draw order. The copy is
## NOT optional: every AppScreen already owns a BackBufferCopy taken BEFORE the
## content draws (that early snapshot is what glass cards frost with), and a
## screen-reading item samples the LATEST copy, not the live screen. Without a
## fresh copy here the quad repaints that UI-less backdrop over the whole scene
## for the wave's lifetime — board, tiles and HUD visibly blink out for ~0.6 s
## on every 512+ merge (the "milestone glitch"). Both nodes ride this node's
## visibility, so the extra copy exists only while a wave is live.
##
## Cost model: while a wave is live the quad samples the screen texture at full
## resolution (one backbuffer copy per frame on GL). That is exactly the cost
## the menu-backdrop rework removed from EVERY frame, so this node is a MOMENT
## effect and nothing else: it fires on 512+ merges, the supernova and the
## giant-tile pulses, runs ~0.6 s, and is `visible = false` (zero cost) the
## rest of the time. Never drive it per-frame or per-swipe.
##
## fire() self-guards on reduce_motion, so call sites stay clean. The tween
## rides Engine.time_scale on purpose — during the supernova's slow-mo the
## ripple crawls with the world, which is the shot.
##
## Placement: a full-rect child ABOVE the play field and below modal layers
## (modals are added later, so they refract nothing). D3D12 note: every
## smoothstep in the shader ascends (RULES / d3d12-reversed-smoothstep).

const _CODE := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 centre = vec2(0.5, 0.5);
uniform float radius = 0.0;    // in width-normalised units
uniform float width = 0.07;
uniform float strength = 0.0;  // uv displacement at the crest
uniform float ar = 0.46;       // viewport width / height
void fragment() {
	vec2 d = SCREEN_UV - centre;
	d.y /= ar;                            // circular in SCREEN pixels
	float dist = length(d);
	float ring = 1.0 - smoothstep(0.0, width, abs(dist - radius));
	vec2 dir = dist > 0.0001 ? d / dist : vec2(0.0, 0.0);
	dir.y *= ar;                          // back to uv units
	vec4 c = texture(screen_tex, SCREEN_UV - dir * (ring * strength));
	c.rgb += vec3(ring * strength * 2.2); // the crest catches light
	COLOR = c;
}
"""

static var _shader: Shader

var _quad: ColorRect
var _mat: ShaderMaterial
var _tw: Tween

func _init() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = _CODE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The fresh screen copy the quad samples — see the class doc for why the
	# AppScreen copy cannot be reused. Drawn (and paid for) only while live.
	var bbc := BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(bbc)
	_quad = ColorRect.new()
	_quad.color = Color(1, 1, 1, 1)   # the shader owns every pixel; the rect just spans
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_quad.material = _mat
	_quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_quad)
	_quad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## Launch one wave from `canvas_pos` (canvas/design coordinates — the same space
## `merged_at` emits). `strength` is the crest displacement in uv units: 0.012
## reads as a shiver, 0.05 bends the whole scene. One wave at a time; a fire
## while live restarts from the new epicentre (rare enough not to matter).
func fire(canvas_pos: Vector2, strength: float = 0.022, dur: float = 0.6) -> void:
	if SettingsManager.reduce_motion():
		return
	if not is_inside_tree():
		return
	var cs: Vector2 = get_viewport().get_visible_rect().size
	if cs.x <= 0.0 or cs.y <= 0.0:
		return
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_mat.set_shader_parameter("centre", canvas_pos / cs)
	_mat.set_shader_parameter("ar", cs.x / cs.y)
	_mat.set_shader_parameter("width", 0.07)
	_mat.set_shader_parameter("strength", strength)
	_mat.set_shader_parameter("radius", 0.0)
	visible = true
	_tw = create_tween().set_parallel(true)
	_tw.tween_method(func(v: float) -> void:
		_mat.set_shader_parameter("radius", v), 0.0, 0.85, dur) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tw.tween_method(func(v: float) -> void:
		_mat.set_shader_parameter("strength", v), strength, 0.0, dur) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	_tw.chain().tween_callback(func() -> void: visible = false)

## True while a wave is crossing — the test surface, and the cost gauge.
func live() -> bool:
	return visible
