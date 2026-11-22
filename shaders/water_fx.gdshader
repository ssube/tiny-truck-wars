shader_type canvas_item;
render_mode blend_disabled, unshaded;
// The water's visual detail, one texel per quarter tile, kept on the GPU and
// never read back (gameplay reads the CPU water). The buffer is never
// cleared: last frame's state is read from the screen texture and stepped.
//   r foam       carried by the current, gathers where the flow converges, fades
//   g silt       carried by the current, slowly settles out (the water clears)
//   b ripple h   a damped wave equation: wakes, splashes, rain drops
//   a ripple v
// This frame's splashes come in as uniforms and are added here (a blended
// draw into an HDR buffer is not a dependable add in every renderer).

uniform sampler2D state : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D water_tex : filter_linear, repeat_disable;
uniform sampler2D flow_tex : filter_linear, repeat_disable;
uniform vec2 map_px = vec2(1024.0, 640.0);
uniform vec2 texels = vec2(256.0, 160.0);
uniform float dt = 0.016;
uniform float foam_life = 2.5;
uniform float silt_clear = 12.0;
uniform float converge_foam = 0.02;
uniform float wave_c2 = 10.0;
uniform float ripple_damping = 1.6;
uniform float rain = 0.0;
uniform float rain_drop = 0.6;
const int MAX_SPLASHES = 64;
// x, y (texels), radius (texels); foam, silt, ripple.
uniform vec4 splash_at[MAX_SPLASHES];
uniform vec4 splash_amount[MAX_SPLASHES];
uniform int splash_count = 0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 texel = 1.0 / texels;
	float level = texture(water_tex, uv).r;
	if (level < -32.0) {
		COLOR = vec4(0.0);
	} else {
		vec2 flow = texture(flow_tex, uv).rg;
		vec2 back = uv - flow * dt / map_px;
		vec4 carried = texture(state, back);
		float foam = carried.r * exp(-dt / foam_life);
		float silt = carried.g * exp(-dt / silt_clear);
		// Foam gathers where the current converges (eddies, the lee of things).
		float div = (texture(flow_tex, uv + vec2(texel.x, 0.0)).r - texture(flow_tex, uv - vec2(texel.x, 0.0)).r
			+ texture(flow_tex, uv + vec2(0.0, texel.y)).g - texture(flow_tex, uv - vec2(0.0, texel.y)).g) * 0.5;
		foam += max(-div, 0.0) * converge_foam * dt;
		vec4 here = texture(state, uv);
		float h = here.b;
		float v = here.a;
		float lap = texture(state, uv + vec2(texel.x, 0.0)).b + texture(state, uv - vec2(texel.x, 0.0)).b
			+ texture(state, uv + vec2(0.0, texel.y)).b + texture(state, uv - vec2(0.0, texel.y)).b - 4.0 * h;
		v += wave_c2 * lap * dt;
		v *= exp(-ripple_damping * dt);
		h += v * dt;
		vec2 here_texel = uv * texels;
		for (int k = 0; k < MAX_SPLASHES; k++) {
			if (k >= splash_count) break;
			float d = length(here_texel - splash_at[k].xy) / max(splash_at[k].z, 0.5);
			if (d < 1.0) {
				float w = (1.0 - d * d);
				foam += splash_amount[k].x * w;
				silt += splash_amount[k].y * w;
				h += splash_amount[k].z * w;
			}
		}
		if (rain > 0.0) {
			vec2 cell = floor(uv * texels);
			float drop = hash(cell + floor(TIME * 7.0) * 13.0);
			if (drop > 1.0 - rain * 0.004) h += rain_drop;
		}
		COLOR = vec4(clamp(foam, 0.0, 1.0), clamp(silt, 0.0, 1.0), clamp(h, -4.0, 4.0), clamp(v, -40.0, 40.0));
	}
}
