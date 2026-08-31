shader_type canvas_item;
// Frosted-glass fill for GlassPanel — the LITE-GPU twin of glass.gdshader.
// Instead of the live screen (which forces a BackBufferCopy + a full mip chain
// of the native-res framebuffer every frame), it blurs AppScreen's reduced-res
// backdrop target (see _build_backdrop_target). That texture is full-screen, so
// its UVs are exactly SCREEN_UV, and it is already half resolution — each
// linear tap averages a 2×2 of native pixels for free, so a 9-tap ring matches
// the desktop shader's five mip taps without any mipmaps existing at all.
// Every visual uniform is IDENTICAL to glass.gdshader — same tint, sheen, rim,
// opacity semantics — so a card cannot drift between the two paths.

uniform mediump sampler2D backdrop_tex : filter_linear;
uniform float blur_px : hint_range(0.0, 32.0) = 10.0;  // kept for API compat (blur is baked now)
uniform mediump vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.12);  // milky frost wash
uniform mediump float top_sheen = 0.16;  // soft light down from the top edge
uniform mediump float rim = 0.10;        // faint hairline around the pane
uniform mediump float opacity : hint_range(0.0, 1.0) = 0.85;  // <1 = see-through, real glass
uniform mediump float sheen : hint_range(0.0, 1.0) = 0.0;  // travelling highlight strength (0 = off)
uniform float sheen_period = 9.0;                  // seconds between sweeps
uniform float phase = 0.0;                         // per-pane desync offset

void fragment() {
	// Five taps on the half-res wash — each bilinear fetch already averages a
	// 2x2 of native pixels, so this reaches the softness the old nine
	// full-resolution taps did, at mediump. mediump throughout the colour
	// path: up to 2x fragment throughput on Mali/Adreno; positions and UVs
	// stay highp per the Arm guidance.
	//
	// A quarter-res pre-blur pass used to feed this shader a finished blur for
	// one tap. It is gone deliberately — it could not resolve on GLES3 and it
	// shifted the panes whiter on Vulkan. See AppScreen.frost_texture().
	vec2 t = SCREEN_PIXEL_SIZE * blur_px;
	mediump vec3 c = texture(backdrop_tex, SCREEN_UV).rgb * 0.28;
	c += texture(backdrop_tex, SCREEN_UV + vec2( 0.7,  0.7) * t).rgb * 0.18;
	c += texture(backdrop_tex, SCREEN_UV + vec2(-0.7,  0.7) * t).rgb * 0.18;
	c += texture(backdrop_tex, SCREEN_UV + vec2( 0.7, -0.7) * t).rgb * 0.18;
	c += texture(backdrop_tex, SCREEN_UV + vec2(-0.7, -0.7) * t).rgb * 0.18;

	// Milky frost tint over the blurred backdrop.
	mediump vec3 col = mix(c, tint.rgb, tint.a);

	// Soft top-down sheen + faint rim (ascending smoothsteps only — D3D12).
	col += vec3((1.0 - smoothstep(0.0, 0.16, UV.y)) * top_sheen);
	vec2 de = min(UV, 1.0 - UV);
	col += vec3((1.0 - smoothstep(0.0, 0.02, min(de.x, de.y))) * rim);

	// The travelling sheen band — same clockwork as glass.gdshader.
	if (sheen > 0.0) {
		mediump float g = (UV.x + UV.y) * 0.5;
		float sweep = fract((TIME + phase) / sheen_period);
		mediump float cs = sweep * 5.0 - 2.0;
		mediump float band = smoothstep(cs - 0.22, cs, g) * (1.0 - smoothstep(cs, cs + 0.22, g));
		col += vec3(band * sheen);
	}

	COLOR = vec4(col, COLOR.a * opacity);
}
