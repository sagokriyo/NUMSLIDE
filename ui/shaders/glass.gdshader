shader_type canvas_item;
// Frosted-glass fill for GlassPanel: samples the backdrop behind the card (made
// available by AppScreen's BackBufferCopy), blurs it, and lays a theme tint on
// top — so a card reads as a clean frosted pane over a soft wash. Because it
// frosts whatever is actually behind it, it works on light and dark themes alike.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_px : hint_range(0.0, 32.0) = 10.0;  // blur reach, screen pixels
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.12);  // milky frost wash
uniform float top_sheen = 0.16;  // soft light down from the top edge
uniform float rim = 0.10;        // faint hairline around the pane
uniform float opacity : hint_range(0.0, 1.0) = 0.85;  // <1 = see-through, real glass
uniform float sheen : hint_range(0.0, 1.0) = 0.0;  // travelling highlight strength (0 = off)
uniform float sheen_period = 9.0;                  // seconds between sweeps
uniform float phase = 0.0;                         // per-pane desync offset

void fragment() {
	// Frosted blur from the screen texture's MIP CHAIN: each tap at a coarser mip
	// already averages a neighbourhood, so five mip taps match the softness the
	// old 9 full-resolution taps produced at roughly a quarter of the texture
	// bandwidth — the cost that mattered on phone GPUs, paid on every card pixel.
	// Weights sum to 1.0.
	vec2 t = SCREEN_PIXEL_SIZE * blur_px;
	float lod = clamp(log2(max(blur_px * 0.5, 1.0)), 1.0, 3.5);
	vec3 c = textureLod(screen_tex, SCREEN_UV, lod).rgb * 0.28;
	c += textureLod(screen_tex, SCREEN_UV + vec2( 0.7,  0.7) * t, lod).rgb * 0.18;
	c += textureLod(screen_tex, SCREEN_UV + vec2(-0.7,  0.7) * t, lod).rgb * 0.18;
	c += textureLod(screen_tex, SCREEN_UV + vec2( 0.7, -0.7) * t, lod).rgb * 0.18;
	c += textureLod(screen_tex, SCREEN_UV + vec2(-0.7, -0.7) * t, lod).rgb * 0.18;

	// Milky frost tint over the blurred backdrop.
	vec3 col = mix(c, tint.rgb, tint.a);

	// A soft top-down sheen and a faint all-round rim give the pane definition
	// without the "only the edges are lit" flatness — the frosted body carries it.
	// Ascending edges only: a reversed smoothstep (edge0 > edge1) is undefined in
	// GLSL and dies on D3D12, so fade with (1.0 - smoothstep) instead.
	col += vec3((1.0 - smoothstep(0.0, 0.16, UV.y)) * top_sheen);
	vec2 de = min(UV, 1.0 - UV);
	col += vec3((1.0 - smoothstep(0.0, 0.02, min(de.x, de.y))) * rim);

	// The pane is alive: every sheen_period seconds a soft diagonal light band
	// glides across it (then rests off-pane for most of the cycle). Ascending
	// smoothsteps only (D3D12). GlassPanel leaves sheen at 0 under reduce-motion,
	// which compiles this to a dead branch.
	if (sheen > 0.0) {
		float g = (UV.x + UV.y) * 0.5;
		float sweep = fract((TIME + phase) / sheen_period);
		float c = sweep * 5.0 - 2.0;   // crossing takes ~1/3 of the cycle
		float band = smoothstep(c - 0.22, c, g) * (1.0 - smoothstep(c, c + 0.22, g));
		col += vec3(band * sheen);
	}

	// Keep the incoming alpha (so the rounded, anti-aliased corners survive) but scale
	// it by `opacity` so the real backdrop shows through — see-through, like glass.
	COLOR = vec4(col, COLOR.a * opacity);
}
