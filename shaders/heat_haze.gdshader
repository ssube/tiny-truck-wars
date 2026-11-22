shader_type canvas_item;
// The shimmer above a fire: what is behind the quad, nudged by rising noise,
// fading out toward the top.

uniform sampler2D screen : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float haze_strength : hint_range(0.0, 0.02) = 0.004;

void fragment() {
	float n = texture(noise_tex, vec2(UV.x * 0.7, UV.y * 0.5 + TIME * 0.9)).r - 0.5;
	float fade = UV.y * (1.0 - abs(UV.x - 0.5) * 2.0);
	COLOR = texture(screen, SCREEN_UV + vec2(n, n * 0.4) * haze_strength * fade);
}
