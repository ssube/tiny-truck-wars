shader_type canvas_item;
render_mode blend_add;
// Firelight on the ground around a fire: warm, flickering, in stepped rings.

uniform vec3 glow_color : source_color = vec3(1.0, 0.55, 0.2);
uniform float strength : hint_range(0.0, 2.0) = 0.5;
uniform float seed = 0.0;
uniform float texels = 24.0;

void fragment() {
	vec2 uv = (floor(UV * texels) + 0.5) / texels;
	float d = length(uv - 0.5) * 2.0;
	float flicker = 0.85 + 0.15 * sin(TIME * 11.0 + seed * 7.0) * sin(TIME * 4.3 + seed);
	float k = clamp(1.0 - d, 0.0, 1.0);
	k = floor(k * 4.0) / 4.0;
	COLOR = vec4(glow_color * k * strength * flicker, 1.0);
}
