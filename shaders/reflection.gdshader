shader_type canvas_item;
// A vehicle mirrored in the water it stands in: flipped about its waterline,
// tinted toward the water, wavering, and fading with distance from the line.

uniform vec3 water_tint : source_color = vec3(0.20, 0.28, 0.28);
uniform float strength : hint_range(0.0, 1.0) = 0.0;
// How far (share of the sprite) below the waterline the reflection reaches.
uniform float reach : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	// The sprite is flipped: UV.y 0 is now the waterline.
	float sway = sin(UV.y * 40.0 + TIME * 4.0) * 0.012 * UV.y;
	vec4 c = texture(TEXTURE, vec2(UV.x + sway, UV.y));
	float fade = clamp(1.0 - UV.y / max(reach, 0.01), 0.0, 1.0);
	float a = c.a * strength * fade;
	a = a > 0.4 ? 0.45 : (a > 0.15 ? 0.25 : 0.0);
	COLOR = vec4(mix(c.rgb, water_tint, 0.55), a);
}
