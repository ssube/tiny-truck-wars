shader_type canvas_item;
// Flames on a quad: heat rising from the bottom edge, torn by two noise
// layers scrolling up at different speeds, cut into a five-colour palette
// (crisp, like the rest of the pixel art).

uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float seed = 0.0;
uniform vec2 texels = vec2(12.0, 18.0);

void fragment() {
	vec2 uv = (floor(UV * texels) + 0.5) / texels;
	float n = texture(noise_tex, vec2(uv.x * 0.8 + seed, uv.y * 0.6 + TIME * 1.3)).r;
	float n2 = texture(noise_tex, vec2(uv.x * 1.7 - seed, uv.y * 1.1 + TIME * 2.2)).r;
	// UV y runs down the quad: the bottom (y = 1) burns hottest.
	float rise = uv.y;
	float width = 1.0 - abs(uv.x - 0.5) * 2.0;
	float heat = (rise * 1.15 * pow(width, 0.7) + (n * 0.6 + n2 * 0.4 - 0.5) * 0.9) * intensity;
	vec4 c = vec4(0.0);
	if (heat > 0.85) c = vec4(1.0, 0.96, 0.70, 1.0);
	else if (heat > 0.62) c = vec4(1.0, 0.74, 0.22, 1.0);
	else if (heat > 0.42) c = vec4(0.92, 0.36, 0.08, 1.0);
	else if (heat > 0.28) c = vec4(0.45, 0.12, 0.05, 0.85);
	COLOR = c;
}
