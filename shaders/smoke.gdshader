shader_type canvas_item;
// A puff of smoke (one particle's quad): a billow cut from noise, lit from the
// sun (top left) so it has a round side and a shadowed side, and lit from
// below by any fire under it (warm on its lower side, strongest while the
// puff is young and close to the flames). Stepped alpha and tones for pixel art.

uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec3 smoke_light : source_color = vec3(0.80, 0.78, 0.74);
uniform vec3 smoke_dark : source_color = vec3(0.28, 0.27, 0.26);
uniform vec3 underlight_color : source_color = vec3(1.0, 0.55, 0.18);
// How much fire lights it from below (0: none, as for exhaust or a smoke screen).
uniform float underlight : hint_range(0.0, 2.0) = 0.0;
uniform float density : hint_range(0.0, 2.0) = 1.0;
uniform vec2 sun = vec2(-0.55, -0.65);
// Texels across the quad: drawn in blocks of this size, crisp at any scale.
uniform float texels = 16.0;

varying float age;
varying float seed;

void vertex() {
	age = INSTANCE_CUSTOM.y;
	seed = INSTANCE_CUSTOM.z;
}

float billow(vec2 uv) {
	vec2 c = uv - 0.5;
	// Big rounded lobes, a little finer texture on them.
	float n = texture(noise_tex, uv * 0.22 + vec2(seed * 7.1, seed * 3.7) + vec2(0.0, -TIME * 0.02)).r;
	float n2 = texture(noise_tex, uv * 0.6 + vec2(seed * 2.3, seed * 9.1)).r;
	return 1.0 - length(c) * 2.0 + (n - 0.5) * 0.8 + (n2 - 0.5) * 0.35;
}

void fragment() {
	vec2 uv = (floor(UV * texels) + 0.5) / texels;
	float shape = billow(uv);
	float a = smoothstep(0.0, 0.3, shape) * COLOR.a * density;
	// Light where the billow rises toward the sun, shade where it falls away.
	vec2 toward = normalize(sun) / texels * 2.0;
	float slope = billow(uv + toward) - shape;
	float light = clamp(0.55 + slope * 4.0 - dot(uv - 0.5, normalize(sun)) * -0.6, 0.0, 1.0);
	vec3 col = mix(smoke_dark, smoke_light, light) * COLOR.rgb;
	float below = clamp((uv.y - 0.35) * 2.0, 0.0, 1.0);
	col += underlight_color * underlight * below * (1.0 - age) * 0.9;
	a = a > 0.7 ? 0.92 : (a > 0.4 ? 0.65 : (a > 0.12 ? 0.32 : 0.0));
	col = floor(col * 12.0 + 0.5) / 12.0;
	COLOR = vec4(col, a);
}
