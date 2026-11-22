shader_type canvas_item;
// A ground vehicle's sprite: sunk into ruts and water (its lowest rows hidden
// below the ground line, with a line of mud where it meets it) and caked in
// mud from the bottom up. The node moves the sprite down by the sink.

uniform float sink_rows = 0.0;   // texture rows below the ground line
uniform float bottom_row = 48.0; // lowest opaque row of the current texture
uniform float body_rows = 32.0;  // opaque height of the current texture
uniform float grime : hint_range(0.0, 1.0) = 0.0;
uniform vec3 mud_dark : source_color = vec3(0.22, 0.16, 0.10);
uniform vec3 mud_light : source_color = vec3(0.36, 0.27, 0.17);
uniform vec3 water_line : source_color = vec3(0.30, 0.36, 0.33);
uniform float in_water = 0.0;
// A wet hull is darker and a little richer (paint soaked, most of all
// olive and green), with rare glints on top; it dries over time.
uniform float wet = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
	float above = bottom_row - px.y; // rows above the sprite's bottom
	float h = hash(px);
	if (c.a > 0.5) {
		// Caked mud climbs from the bottom with grime, in ragged clumps.
		float reach = grime * body_rows * 0.55 + (h - 0.5) * 5.0;
		if (above < reach) c.rgb = mix(c.rgb, h > 0.55 ? mud_light : mud_dark, 0.85);
	}
	if (c.a > 0.5 && wet > 0.0) {
		float grey = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		float green = clamp((c.g - max(c.r, c.b)) * 4.0, 0.0, 1.0);
		vec3 soaked = mix(vec3(grey), c.rgb, 1.25) * (0.72 - 0.08 * green);
		c.rgb = mix(c.rgb, soaked, wet);
		if (h > 0.97 && above > body_rows * 0.6) c.rgb = mix(c.rgb, vec3(0.85, 0.9, 0.9), 0.3 * wet);
	}
	if (above < sink_rows) {
		c.a = 0.0;
	} else if (above < sink_rows + 1.0 && c.a > 0.5 && sink_rows > 0.5) {
		c.rgb = mix(mud_dark, water_line, in_water);
	}
	COLOR = c;
}
