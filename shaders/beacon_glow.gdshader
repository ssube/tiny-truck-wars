shader_type canvas_item;
render_mode blend_add;
// A beacon's light on the ground around its vehicle: amber, in stepped
// rings like firelight, on only while the beacon is lit.
#include "res://shaders/beacon.gdshaderinc"

uniform vec3 beacon_color : source_color = vec3(1.0, 0.6, 0.15);
uniform float beacon_strength : hint_range(0.0, 2.0) = 0.55;
uniform float beacon_phase = 0.0;
uniform float beacon_texels = 20.0;

void fragment() {
	vec2 uv = (floor(UV * beacon_texels) + 0.5) / beacon_texels;
	float k = clamp(1.0 - length(uv - 0.5) * 2.0, 0.0, 1.0);
	k = floor(k * 4.0) / 4.0;
	float on = beacon_lit(beacon_phase) ? 1.0 : 0.0;
	COLOR = vec4(beacon_color * k * beacon_strength * on, 1.0);
}
