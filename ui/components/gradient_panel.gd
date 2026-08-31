class_name GradientPanel
extends ColorRect
## GradientPanel — a crisp, anti-aliased rounded-rectangle filled with a linear
## colour gradient. Powers the reference's coloured mode tiles, the violet→blue
## "Continue" pill, the circular play buttons and any rounded gradient surface.
##
## A ColorRect (so it draws a full-rect quad) with a small SDF shader that both
## rounds the corners and paints the gradient. Set a very large `corner_radius`
## to get a pill or a circle. Children (labels, glyphs) render normally on top.

var col_a: Color = Color.WHITE:
	set(value): col_a = value; _push()
var col_b: Color = Color.WHITE:
	set(value): col_b = value; _push()
## Corner radius in pixels; clamped to half the shorter side at draw time.
var corner_radius: float = 28.0:
	set(value): corner_radius = value; _push()
## Gradient travel direction (e.g. Vector2(1,1) diagonal, Vector2(1,0) horizontal).
var grad_dir: Vector2 = Vector2(1.0, 1.0):
	set(value): grad_dir = value; _push()
## Animated specular sweep intensity (0 = off). A soft diagonal highlight band
## travels across the surface, clipped to the rounded mask so it works on pills
## and circles alike. Opt-in: enabled only on the primary "play" affordances.
var sheen: float = 0.0:
	set(value): sheen = value; _push()
## Candy finish intensity (0 = off): an inner rim light hugging the top edge
## plus a glossy cap high on the face — the board tiles' sugar-glaze read.
## Opt-in: used by Home's floating toy tiles.
var candy: float = 0.0:
	set(value): candy = value; _push()

var _mat: ShaderMaterial
static var _shader: Shader

static func make(a: Color, b: Color, radius: float = 28.0, dir: Vector2 = Vector2(1.0, 1.0)) -> GradientPanel:
	var g := GradientPanel.new()
	g.col_a = a
	g.col_b = b
	g.corner_radius = radius
	g.grad_dir = dir
	return g

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	_mat = ShaderMaterial.new()
	_mat.shader = _get_shader()
	material = _mat
	resized.connect(_push)
	_push()

func _push() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("col_a", col_a)
	_mat.set_shader_parameter("col_b", col_b)
	_mat.set_shader_parameter("box_size", size)
	_mat.set_shader_parameter("radius", corner_radius)
	_mat.set_shader_parameter("grad_dir", grad_dir)
	_mat.set_shader_parameter("sheen", sheen)
	_mat.set_shader_parameter("candy", candy)

static func _get_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type canvas_item;
uniform vec4 col_a : source_color = vec4(1.0);
uniform vec4 col_b : source_color = vec4(1.0);
uniform vec2 box_size = vec2(100.0, 100.0);
uniform float radius = 28.0;
uniform vec2 grad_dir = vec2(1.0, 1.0);
uniform float sheen = 0.0;
uniform float candy = 0.0;

float sd_round_rect(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * box_size;
	float r = min(radius, min(box_size.x, box_size.y) * 0.5);
	float d = sd_round_rect(p, box_size * 0.5, r);
	float aa = fwidth(d) + 0.0001;
	float alpha = 1.0 - smoothstep(-aa, aa, d);
	vec2 n = normalize(grad_dir);
	float denom = abs(n.x) + abs(n.y);
	float t = clamp(dot(UV, n) / max(denom, 0.0001), 0.0, 1.0);
	vec3 col = mix(col_a.rgb, col_b.rgb, t);
	// Glossy premium sheen: a broad white wash down from the top, a CRISP specular
	// ridge just under the top edge (the reflection line polished metal/glass carry),
	// and a deeper base shade — more contrast, same hue, so every pill and tile reads
	// polished rather than flat-filled.
	// (ascending edges: reversed smoothstep is undefined in GLSL and dies on D3D12)
	float top = (1.0 - smoothstep(0.0, 0.50, UV.y)) * 0.24;
	float ridge = (1.0 - smoothstep(0.04, 0.14, UV.y)) * 0.22;
	float bottom = smoothstep(0.55, 1.0, UV.y) * 0.16;
	col = mix(col, vec3(1.0), top);
	col = mix(col, vec3(1.0), ridge);
	col = mix(col, col * 0.80, bottom);
	// Candy finish: an inner rim light hugging the top edge plus a glossy cap
	// high on the face — the sugar-glaze the board's tiles wear. Opt-in.
	// (ascending smoothstep edges only — descending dies on D3D12)
	if (candy > 0.001) {
		float rim = smoothstep(-2.8, -0.9, d) * (1.0 - smoothstep(0.16, 0.5, UV.y));
		col = mix(col, vec3(1.0), rim * 0.55 * candy);
		vec2 gp = (UV - vec2(0.5, 0.24)) / vec2(0.42, 0.20);
		float cap = 1.0 - smoothstep(0.5, 1.0, length(gp));
		col = mix(col, vec3(1.0), cap * 0.18 * candy);
	}
	// Animated specular sweep — a soft diagonal highlight crossing the surface.
	if (sheen > 0.001) {
		float phase = fract((UV.x * 0.7 + UV.y * 0.3) - TIME * 0.22);
		float streak = pow(1.0 - abs(phase - 0.5) * 2.0, 8.0);
		col = mix(col, vec3(1.0), streak * 0.45 * sheen);
	}
	COLOR = vec4(col, alpha);
}
"""
	return _shader
