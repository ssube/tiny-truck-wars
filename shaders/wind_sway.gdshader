shader_type canvas_item;
// Leans the upper part of a picture with the map's wind, in whole texels so
// pixel art stays crisp: trees. Each texel row moves as one, by whole
// texels, however far the picture is zoomed in. TtwWeatherSystem sets
// ttw_wind (the steady wind, px/s) and ttw_wind_clock (game seconds) every
// tick; the gust below repeats TtwWeatherSystem.gust, so trees bend
// together and a gust rolls across a wood. A 20 px/s wind leans a picture `lean_pixels`.
//
// The lean grows from nothing at `rest_v` (texture v, 1 = the bottom row) to
// `lean_pixels` per unit of wind at `full_v` and above. For an atlas frame in a
// single-row strip v is still the frame's own height.

global uniform vec2 ttw_wind;
global uniform float ttw_wind_clock;

uniform float lean_pixels = 2.0;
uniform float rest_v : hint_range(0.0, 1.0) = 1.0;
uniform float full_v : hint_range(0.0, 1.0) = 0.0;
// Texels to widen the quad on each side so a lean is not cut at the edge.
// Only for a whole texture (not an atlas frame): v and u past 0..1 are empty.
uniform float grow_pixels = 0.0;
// Wraps instead (a repeating backdrop layer: the next copy is the same picture).
uniform bool wraps = false;
// Phase by each column's world x (a wide backdrop: the gust rolls across it)
// rather than by the picture's origin (one tree bends as one).
uniform bool per_column = false;

varying float phase;
varying vec4 tint;

float gust(float clock, float p) {
	return clamp(0.62 + 0.24 * sin(clock * 0.31 + p) + 0.17 * sin(clock * 0.83 + p * 2.3) + 0.11 * sin(clock * 1.9 + p * 0.7), 0.15, 1.2);
}

void vertex() {
	if (grow_pixels > 0.0) {
		float side = UV.x < 0.5 ? -1.0 : 1.0;
		VERTEX.x += side * grow_pixels;
		UV.x += side * grow_pixels * TEXTURE_PIXEL_SIZE.x;
	}
	vec2 world = per_column ? (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy : MODEL_MATRIX[3].xy;
	phase = mod(world.x * 0.0137, 6.2831853);
	tint = COLOR;
}

void fragment() {
	// One lean per texel row, from the row's centre: a texel row covers
	// several screen rows when zoomed in, and leaning each of them on its own
	// split the row into screen-pixel steps.
	float row_v = (floor(UV.y / TEXTURE_PIXEL_SIZE.y) + 0.5) * TEXTURE_PIXEL_SIZE.y;
	float reach = clamp((rest_v - row_v) / max(rest_v - full_v, 0.0001), 0.0, 1.0);
	// Bends more near the top, like a stem: quadratic, not a straight shear.
	float lean = (ttw_wind.x / 20.0) * gust(ttw_wind_clock, phase) * lean_pixels * reach * reach;
	vec2 uv = UV;
	uv.x -= round(lean) * TEXTURE_PIXEL_SIZE.x;
	if (wraps) {
		uv.x = fract(uv.x);
	}
	vec4 colour = texture(TEXTURE, uv);
	if (grow_pixels > 0.0 && (uv.x < 0.0 || uv.x > 1.0)) {
		colour.a = 0.0;
	}
	COLOR = colour * tint;
}
