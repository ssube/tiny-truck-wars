shader_type canvas_item;
// The ground of one chunk (TtwTerrainView). The camera looks down at a tilt:
// a point at height h (px) is drawn tilt_k * h px up the screen. Relief
// (ruts, berms, loose mud, standing water) is ray-marched along that fixed
// screen direction (parallax occlusion), per world pixel so it stays crisp.
// Macro elevation is shading only; cliffs get a rock band.
//
// Tiers (TtwTerrainView picks one per chunk from distance and zoom):
//   0 full: parallax march, self-shadow, material detail normals, imprints, water sheen
//   1 mid:  no march or shadow; relief normals, imprints, simple water
//   2 far:  flat albedo + relief shading, water colour by depth
// While a chunk changes tier, both are drawn and cross-faded (lod_mix).

render_mode unshaded;

// Chunk cell layers: CHUNK_TEXELS square, APRON cells around the chunk.
uniform sampler2D deform_tex : filter_linear, repeat_disable;
uniform sampler2D loose_tex : filter_linear, repeat_disable;
uniform sampler2D wet_tex : filter_linear, repeat_disable;
uniform sampler2D track_tex : filter_nearest, repeat_disable;
uniform sampler2D angle_tex : filter_nearest, repeat_disable;
uniform sampler2D wear_tex : filter_nearest, repeat_disable;
uniform sampler2D scorch_tex : filter_linear, repeat_disable;
// Oil on the ground (cell) and afloat on the water (tile, TtwWater's slick).
uniform sampler2D oil_tex : filter_linear, repeat_disable;
// Snow: the tile's authored snow, what was taken from each cell, and the
// map-wide level (TtwSnowSystem): depth = base + level - gone.
uniform sampler2D snow_gone_tex : filter_linear, repeat_disable;
global uniform float ttw_snow;
global uniform float ttw_thaw;
// Whole-map tile layers.
uniform sampler2D surface_tex : filter_nearest, repeat_disable;
// The smooth whole-map tile layers in one texture (TtwTerrainView.TILE_*):
// 0 elevation, 1 water level, 2 oil slick afloat, 3 authored snow. One
// texture unit for four: a GL device may have only 16 for this shader.
uniform sampler2DArray tile_layers : filter_linear, repeat_disable;
// The water's colour per tile (alpha: how far it replaces water_shallow and
// water_deep; 0 leaves them).
uniform sampler2D water_color_tex : hint_default_transparent, filter_linear, repeat_disable;
// The water's current per tile (px/s), from the simulation.
uniform sampler2D flow_tex : filter_linear, repeat_disable;
// The water's GPU detail (TtwWaterFx): foam, silt, ripple height, ripple speed.
uniform sampler2D fx_tex : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;

uniform vec2 chunk_origin_px;
uniform vec2 map_tiles = vec2(64.0);
uniform float tile_px = 16.0;
uniform float cell_px = 2.0;
uniform float apron_cells = 8.0;
uniform float chunk_texels = 144.0;

// Debug overlays (TtwTerrainView.Overlay): 0 none, 1 wear, 2 wetness,
// 3 relief, 4 loose mud, 5 tread prints, 6 scorch, 7 water depth,
// 8 material, 9 elevation, 10 oil, 11 snow depth.
uniform int overlay = 0;
uniform int lod = 0;
uniform int lod_from = 0;
uniform float lod_mix : hint_range(0.0, 1.0) = 1.0;

group_uniforms look;
uniform float tilt_k : hint_range(0.0, 1.5) = 0.6;
// Toward the sun: up-left of the screen and above, as pixel art is lit.
uniform vec3 sun_dir = vec3(-0.55, -0.65, 0.6);
uniform float ambient : hint_range(0.0, 1.0) = 0.5;
uniform float relief_light : hint_range(0.0, 6.0) = 2.6;
uniform float cavity_dark : hint_range(0.0, 1.0) = 0.45;
uniform float ridge_light : hint_range(0.0, 1.0) = 0.25;
uniform float light_steps : hint_range(0.0, 16.0) = 6.0;
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.45;
uniform float hillshade : hint_range(0.0, 2.0) = 0.6;
uniform float cliff_slope = 0.9;
uniform float posterize_levels : hint_range(0.0, 64.0) = 0.0;
uniform float relief_max = 6.0;
uniform float relief_min = -9.0;
group_uniforms mud;
uniform vec3 loose_mud_color : source_color = vec3(0.27, 0.20, 0.13);
uniform vec3 wet_tint : source_color = vec3(0.62, 0.58, 0.55);
uniform float wet_gloss : hint_range(0.0, 2.0) = 0.7;
uniform float imprint_strength : hint_range(0.0, 2.0) = 0.8;
uniform float imprint_pitch = 3.0;
uniform float clump_strength : hint_range(0.0, 1.5) = 0.55;
uniform float wet_edge : hint_range(0.0, 1.0) = 0.35;
uniform float spoil_gloss : hint_range(0.0, 2.0) = 0.6;
uniform float crack_width : hint_range(0.0, 0.1) = 0.035;
group_uniforms water;
uniform vec3 water_shallow : source_color = vec3(0.36, 0.42, 0.36);
uniform vec3 water_deep : source_color = vec3(0.14, 0.22, 0.24);
uniform vec3 sky_color : source_color = vec3(0.70, 0.78, 0.82);
uniform float water_depth_px = 10.0;
uniform float water_clarity : hint_range(0.0, 1.0) = 0.35;
// One wave field travelling with the
// current, calmed in the shallows; contact foam on the shore and crest foam
// on the wave tops; absorption by depth; caustics on the floor; the sky at
// grazing angles. Distances are world px.
uniform float color_depth : hint_range(0.1, 30.0) = 7.0;
uniform float wave_height : hint_range(0.0, 3.0) = 0.7;
uniform float wavelength : hint_range(2.0, 80.0) = 22.0;
uniform float peak_sharpness : hint_range(0.0, 1.0) = 0.35;
uniform float wave_speed : hint_range(0.0, 40.0) = 6.0;
uniform vec2 still_direction = vec2(1.0, 0.3);
uniform float shore_fade_depth : hint_range(0.0, 3.0) = 0.35;
uniform float shallow_wave_depth : hint_range(0.0, 8.0) = 2.5;
uniform float foam_depth : hint_range(0.0, 6.0) = 1.4;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.6;
uniform float crest_foam_threshold : hint_range(0.0, 1.0) = 0.55;
uniform float crest_foam_amount : hint_range(0.0, 1.0) = 0.35;
uniform float rapids_foam : hint_range(0.0, 1.0) = 0.5;
uniform vec3 foam_color : source_color = vec3(0.88, 0.92, 0.88);
uniform vec3 caustics_color : source_color = vec3(0.70, 0.92, 0.85);
uniform float caustics_intensity : hint_range(0.0, 2.0) = 0.35;
uniform float refraction_px : hint_range(0.0, 6.0) = 2.0;
uniform float sun_glint : hint_range(0.0, 2.0) = 0.6;
uniform vec3 silt_color : source_color = vec3(0.42, 0.33, 0.21);
uniform float silt_strength : hint_range(0.0, 1.0) = 0.85;
uniform float ripple_normal : hint_range(0.0, 4.0) = 1.4;
group_uniforms snow;
uniform vec3 snow_light : source_color = vec3(0.93, 0.95, 0.98);
uniform vec3 snow_shade : source_color = vec3(0.66, 0.74, 0.88);
uniform vec3 packed_snow : source_color = vec3(0.80, 0.84, 0.90);
uniform vec3 slush : source_color = vec3(0.55, 0.56, 0.55);
uniform float snow_patchiness : hint_range(0.0, 2.0) = 0.8;
group_uniforms oil;
// A thin film's interference colours (a sheen in bands), and how dark oil
// stains dry ground.
uniform float oil_sheen : hint_range(0.0, 1.0) = 0.35;
uniform float oil_stain : hint_range(0.0, 1.0) = 0.6;

varying vec2 local_px;
// The weather's soil moisture (TtwWeatherSystem): rain darkens and wets
// everything a little, on top of each cell's own wetness.
global uniform float ttw_soil;

// Three tones per material id (TtwMaterials order): dark, mid, light. The
// ground is drawn in clusters of these, like hand-made pixel art.
const vec3 PALETTE[18] = vec3[18](
	vec3(0.24, 0.17, 0.11), vec3(0.35, 0.26, 0.17), vec3(0.44, 0.34, 0.23), // mud
	vec3(0.22, 0.32, 0.15), vec3(0.31, 0.43, 0.19), vec3(0.42, 0.53, 0.24), // grass
	vec3(0.34, 0.34, 0.33), vec3(0.42, 0.42, 0.40), vec3(0.49, 0.49, 0.46), // pavement
	vec3(0.37, 0.35, 0.32), vec3(0.50, 0.47, 0.42), vec3(0.62, 0.59, 0.53), // gravel
	vec3(0.60, 0.52, 0.36), vec3(0.69, 0.61, 0.43), vec3(0.77, 0.70, 0.52), // sand
	vec3(0.30, 0.29, 0.28), vec3(0.42, 0.40, 0.38), vec3(0.53, 0.51, 0.48)  // rock
);
const vec3 ROCK_COLOR = vec3(0.42, 0.40, 0.38);

void vertex() {
	local_px = VERTEX;
}

// --- sampling ---------------------------------------------------------------

vec2 cell_uv(vec2 world) {
	vec2 texel = (world - chunk_origin_px) / cell_px + apron_cells;
	return texel / chunk_texels;
}

// Value noise with features about `scale` px across (the noise texture holds
// about 8 features per repeat).
float noise(vec2 world, float scale) {
	return texture(noise_tex, world / (scale * 8.0)).r;
}

// Snow lying at a point (px).
float snow_depth(vec2 world) {
	float base = texture(tile_layers, vec3(world / (map_tiles * tile_px), 3.0)).r;
	return max(0.0, base + ttw_snow - texture(snow_gone_tex, cell_uv(world)).r);
}

// The ground's height offset (px): deformation and loose mud, with pushed-up
// mud and spoil broken into clumps, and any snow lying on it.
float relief(vec2 world) {
	vec2 uv = cell_uv(world);
	float snow = snow_depth(world);
	float d = texture(deform_tex, uv).r;
	float l = texture(loose_tex, uv).r;
	float heaped = max(d, 0.0) + l;
	if (heaped > 0.05) return d + l + snow + heaped * (noise(world, 3.0) - 0.5) * clump_strength;
	return d + l + snow;
}

float water_level(vec2 world) {
	return texture(tile_layers, vec3(world / (map_tiles * tile_px), 1.0)).r;
}

float elevation(vec2 world) {
	return texture(tile_layers, vec3(world / (map_tiles * tile_px), 0.0)).r;
}

int material_at_tile(ivec2 tile) {
	tile = clamp(tile, ivec2(0), ivec2(map_tiles) - 1);
	return int(texelFetch(surface_tex, tile, 0).r * 255.0 + 0.5);
}


// A material's tone at a point: 0 dark, 1 mid, 2 light, from clustered noise.
int material_tone(int id, vec2 p) {
	float v;
	vec2 cuts = vec2(0.40, 0.62);
	if (id == 0) { v = 0.7 * noise(p, 11.0) + 0.3 * noise(p, 4.0); }
	else if (id == 1) { v = 0.55 * noise(p, 7.0) + 0.45 * noise(p, 2.5); cuts = vec2(0.38, 0.6); }
	else if (id == 2) {
		vec2 slab = abs(fract(p / 32.0) - 0.5);
		if (max(slab.x, slab.y) > 0.47) return 0;
		float crack = abs(noise(p, 41.0) - 0.5);
		if (crack < 0.012) return 0;
		v = 0.8 * noise(p, 24.0) + 0.2 * noise(p, 3.0);
		cuts = vec2(0.30, 0.70);
	}
	else if (id == 3) { v = 0.75 * noise(p, 2.2) + 0.25 * noise(p, 9.0); cuts = vec2(0.42, 0.58); }
	else if (id == 4) { v = sin(p.x * 0.30 + p.y * 0.10 + noise(p, 37.0) * 7.0) * 0.25 + 0.5 + 0.25 * (noise(p, 5.0) - 0.5); cuts = vec2(0.36, 0.66); }
	else { v = 0.6 * noise(p, 13.0) + 0.4 * noise(p, 4.0); }
	return v < cuts.x ? 0 : (v < cuts.y ? 1 : 2);
}

// The fine height (px) a tone stands at.
float tone_height(int id, int tone) {
	const float AMP[6] = float[6](0.7, 1.1, 0.35, 0.8, 0.3, 1.3);
	return float(tone - 1) * AMP[id];
}

// Height-blended material splat at a point: albedo in rgb, detail height in a.
// The tile grid is warped by noise so material edges wander, and where two
// materials meet the one standing higher at that pixel wins.
vec4 splat(vec2 p, out int id) {
	vec2 warp = vec2(noise(p, 29.0), noise(p + vec2(57.0, 13.0), 29.0)) - 0.5;
	vec2 t = p / tile_px - 0.5 + warp * 0.9;
	ivec2 base = ivec2(floor(t));
	vec2 f = fract(t);
	int ids[4] = int[4](material_at_tile(base), material_at_tile(base + ivec2(1, 0)),
		material_at_tile(base + ivec2(0, 1)), material_at_tile(base + ivec2(1, 1)));
	float w[4] = float[4]((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
	int best = 0;
	float best_score = -1e9;
	float best_h = 0.0;
	int best_tone = 1;
	for (int i = 0; i < 4; i++) {
		int tone = material_tone(ids[i], p);
		float h = tone_height(ids[i], tone);
		float score = w[i] * 3.0 + h * 0.6;
		if (score > best_score) { best_score = score; best = i; best_h = h; best_tone = tone; }
	}
	id = ids[best];
	return vec4(PALETTE[ids[best] * 3 + best_tone], best_h);
}

// Wear changes what a material looks like: grass is torn into mud in clumps
// as it wears through, pavement cracks and then breaks up into gravel.
vec4 worn(vec4 base, inout int id, vec2 p) {
	float w = texelFetch(wear_tex, ivec2(cell_uv(p) * chunk_texels), 0).r;
	if (w <= 0.0) return base;
	if (id == 1) {
		if (w >= 1.0 || noise(p, 3.0) * 0.8 + 0.2 < w * 0.9) {
			id = 0;
			int tone = material_tone(0, p);
			return vec4(PALETTE[tone], tone_height(0, tone));
		}
		return vec4(base.rgb * (1.0 - 0.25 * w), base.a);
	}
	if (id == 2) {
		if (w >= 1.0) {
			id = 3;
			int tone = material_tone(3, p);
			return vec4(PALETTE[9 + tone], tone_height(3, tone));
		}
		float crack = abs(noise(p, 9.0) - 0.5);
		if (crack < 0.06 * w) return vec4(PALETTE[6] * 0.85, -0.4);
	}
	return base;
}

// --- tiers ------------------------------------------------------------------

// The ground point seen at screen point `p`, by marching the relief (and the
// standing water's surface) down the tilt. Returns the ground point; `on_water`
// says the ray stopped on the water's surface.
vec2 march(vec2 p, out bool on_water) {
	on_water = false;
	if (tilt_k <= 0.0) return p;
	float step_h = 1.0 / tilt_k; // one world pixel along the screen per step
	float h = relief_max;
	float prev_h = h;
	vec2 g = p + vec2(0.0, h * tilt_k);
	float prev_gap = -1.0;
	for (int i = 0; i < 24 && h >= relief_min; i++) {
		g = p + vec2(0.0, h * tilt_k);
		float ground = relief(g);
		float w = water_level(g);
		float top = max(ground, w);
		float gap = top - h;
		if (gap >= 0.0) {
			// Refine between the last miss and this hit.
			float a = prev_h;
			float b = h;
			for (int j = 0; j < 4; j++) {
				float m = 0.5 * (a + b);
				vec2 q = p + vec2(0.0, m * tilt_k);
				if (max(relief(q), water_level(q)) >= m) b = m; else a = m;
			}
			g = p + vec2(0.0, b * tilt_k);
			on_water = water_level(g) > relief(g) + 0.05;
			return g;
		}
		prev_h = h;
		h -= step_h;
	}
	return g;
}

vec3 relief_normal(vec2 g, float detail_scale) {
	float e = cell_px;
	float hx = relief(g + vec2(e, 0.0)) - relief(g - vec2(e, 0.0));
	float hy = relief(g + vec2(0.0, e)) - relief(g - vec2(0.0, e));
	vec3 n = normalize(vec3(-hx / (2.0 * e) * relief_light, -hy / (2.0 * e) * relief_light, 1.0));
	if (detail_scale > 0.0) {
		int unused;
		float hx2 = splat(g + vec2(1.0, 0.0), unused).a - splat(g - vec2(1.0, 0.0), unused).a;
		float hy2 = splat(g + vec2(0.0, 1.0), unused).a - splat(g - vec2(0.0, 1.0), unused).a;
		n = normalize(n + vec3(-hx2, -hy2, 0.0) * detail_scale * 0.5);
	}
	return n;
}

float self_shadow(vec2 g) {
	vec3 l = normalize(sun_dir);
	vec2 dir = normalize(l.xy);
	float rise = l.z / max(length(l.xy), 1e-3);
	float start = relief(g);
	float lit = 1.0;
	for (int i = 1; i <= 5; i++) {
		float d = float(i) * 1.5;
		float above = relief(g + dir * d) - (start + d * rise);
		lit = min(lit, 1.0 - smoothstep(0.0, 1.5, above));
	}
	return mix(1.0, lit, shadow_strength);
}

float tread_imprint(vec2 g) {
	vec2 uv = cell_uv(g);
	float strength = texture(track_tex, uv).r;
	if (strength <= 0.01) return 0.0;
	float a = texture(angle_tex, uv).r;
	vec2 along = vec2(cos(a), sin(a));
	vec2 across = vec2(-along.y, along.x);
	float u = dot(g, along);
	float v = dot(g, across);
	float chevron = fract((u + abs(fract(v / 6.0) - 0.5) * 3.0) / imprint_pitch);
	return step(0.5, chevron) * clamp(strength, 0.0, 1.0);
}

// Thin-film interference: a film's thickness (plus a little drift) as the
// rainbow bands of oil on water, stepped for pixel art.
vec3 film_colour(float thickness, vec2 g) {
	float phase = thickness * 2.2 + noise(g + vec2(TIME * 2.0, 0.0), 7.0) * 0.8;
	vec3 c = 0.5 + 0.5 * cos(6.2832 * (phase + vec3(0.0, 0.33, 0.67)));
	return floor(c * 4.0 + 0.5) / 4.0;
}

vec3 shade_dry(vec2 g, int tier) {
	int id;
	vec4 s = splat(g, id);
	s = worn(s, id, g);
	vec3 albedo = s.rgb;
	// Burns: charred clumps that thin out toward the edge.
	float burn = texture(scorch_tex, cell_uv(g)).r;
	// Oil: a dark stain, with a sheen where the ground is wet.
	float film = texture(oil_tex, cell_uv(g)).r;
	if (film > 0.002) {
		// Even a thin film shows: the stain and sheen are full by a few hundredths.
		float cover = smoothstep(0.002, 0.03, film);
		albedo = mix(albedo, albedo * 0.35 + vec3(0.02, 0.02, 0.03), cover * oil_stain);
		if (tier < 2) {
			float glossy = clamp(texture(wet_tex, cell_uv(g)).r * 1.5 + 0.3, 0.0, 1.0);
			albedo = mix(albedo, film_colour(film, g) * 0.55, cover * oil_sheen * glossy);
		}
	}
	if (burn > 0.0) {
		float specks = step(0.45 + 0.55 * (1.0 - burn), noise(g, 2.5));
		albedo = mix(albedo, albedo * 0.55, burn * 0.6);
		albedo = mix(albedo, vec3(0.13, 0.11, 0.10), specks * 0.8);
	}
	vec2 uv = cell_uv(g);
	float here = relief(g);
	// How far this point sits below (cavity > 0) or above its surroundings.
	float around = 0.25 * (relief(g + vec2(4.0, 0.0)) + relief(g - vec2(4.0, 0.0)) + relief(g + vec2(0.0, 4.0)) + relief(g - vec2(0.0, 4.0)));
	float cavity = clamp((around - here) / 3.0, -1.0, 1.0);
	// Rut floors are pressed smooth: the ground's clumps flatten to its mid and
	// dark tones, with the tread's pattern pressed in.
	if (here < -1.5 && tier < 2) {
		float pressed = smoothstep(-1.5, -3.5, here);
		float imprint = tread_imprint(g);
		albedo = mix(albedo, albedo * (0.92 - 0.12 * imprint * imprint_strength), pressed);
	}
	float loose = texture(loose_tex, uv).r;
	float wet = clamp(max(texture(wet_tex, uv).r, ttw_soil * 0.8), 0.0, 1.0);
	float ground = relief(g);
	// Loose mud covers whatever it lies on.
	// Loose mud covers whatever it lies on, in clumps with crisp edges.
	int clump = material_tone(0, g + vec2(31.0, 17.0));
	vec3 loose_color = loose_mud_color * (clump == 2 ? 1.18 : (clump == 0 ? 0.82 : 1.0));
	albedo = mix(albedo, loose_color, step(0.15 + 0.35 * noise(g, 3.0), loose));
	// A dark tide line where wet ground meets dry.
	float wx = texture(wet_tex, cell_uv(g + vec2(2.0, 0.0))).r - texture(wet_tex, cell_uv(g - vec2(2.0, 0.0))).r;
	float wy = texture(wet_tex, cell_uv(g + vec2(0.0, 2.0))).r - texture(wet_tex, cell_uv(g - vec2(0.0, 2.0))).r;
	albedo *= 1.0 - clamp(length(vec2(wx, wy)) * 1.5, 0.0, 1.0) * wet_edge;
	// Mud drying out cracks into plates.
	if (id == 0 && wet > 0.02 && wet < 0.45 && loose < 0.1) {
		float dryness = 1.0 - wet / 0.45;
		float crack = min(abs(noise(g, 5.0) - 0.5), abs(noise(g + vec2(37.0, 11.0), 7.0) - 0.5));
		if (crack < crack_width * dryness) albedo *= 0.72;
	}
	// Fresh spoil in deep ruts reads darker.
	albedo *= 1.0 + clamp(ground, -6.0, 3.0) * 0.03;
	if (tier < 2 && here >= -1.5) albedo *= 1.0 - tread_imprint(g) * 0.15 * imprint_strength;
	albedo = mix(albedo, albedo * wet_tint, wet);

	// Snow over it: thin cover breaks into patches; deep, it hides the ground.
	// Packed snow (driven over) is greyer and smooth; thawing, it goes to slush.
	float snow = snow_depth(g);
	float snowed = 0.0;
	if (snow > 0.0) {
		snowed = step(0.5, snow * 1.6 + (noise(g, 5.0) - 0.5) * snow_patchiness);
		bool packed = texture(snow_gone_tex, cell_uv(g)).r > 0.4;
		// Broad, soft drifts: two close tones in large clusters.
		vec3 white = packed ? packed_snow : mix(snow_light * 0.96, snow_light, step(0.5, noise(g, 14.0)));
		white = mix(white, slush, ttw_thaw * (packed ? 0.8 : 0.4) * (1.0 - smoothstep(0.5, 3.0, snow)));
		albedo = mix(albedo, white, snowed);
		wet = max(wet, snowed * ttw_thaw * 0.6);
	}
	vec3 n = tier == 2 ? vec3(0.0, 0.0, 1.0) : relief_normal(g, tier == 0 ? 0.6 * (1.0 - snowed) : 0.0);
	if (tier == 2) {
		float hx = relief(g + vec2(cell_px, 0.0)) - relief(g - vec2(cell_px, 0.0));
		float hy = relief(g + vec2(0.0, cell_px)) - relief(g - vec2(0.0, cell_px));
		n = normalize(vec3(-hx * 0.5 * relief_light, -hy * 0.5 * relief_light, 2.0));
	}
	vec3 l = normalize(sun_dir);
	float light = ambient + (1.0 - ambient) * max(dot(n, l), 0.0) * 1.15;
	if (tier == 0) light *= self_shadow(g);
	light *= 1.0 - max(cavity, 0.0) * cavity_dark;
	light *= 1.0 + max(-cavity, 0.0) * ridge_light;

	// Macro elevation: hillshade, and a rock band on steep drops.
	float e = tile_px * 0.5;
	float ex = elevation(g + vec2(e, 0.0)) - elevation(g - vec2(e, 0.0));
	float ey = elevation(g + vec2(0.0, e)) - elevation(g - vec2(0.0, e));
	vec3 macro_n = normalize(vec3(-ex / (2.0 * e), -ey / (2.0 * e), 1.0));
	light *= 1.0 + (dot(macro_n, l) - l.z) * hillshade;
	float slope = length(vec2(ex, ey)) / (2.0 * e);
	float cliff = smoothstep(cliff_slope, cliff_slope * 1.8, slope);
	albedo = mix(albedo, PALETTE[15 + material_tone(5, g)], cliff);

	if (light_steps > 0.0) light = floor(light * light_steps + 0.5) / light_steps;
	vec3 color = albedo * light;
	// Snow's shadows are blue, and it sparkles in the sun.
	if (snowed > 0.0) {
		color = mix(color, color * snow_shade / max(snow_light, vec3(0.01)), (1.0 - clamp(light, 0.0, 1.0)) * 0.6 * snowed);
		float glint = fract(sin(dot(floor(g), vec2(12.9898, 78.233))) * 43758.5453);
		if (glint > 0.992 && light > 0.9 && tier < 2) color = vec3(1.0);
	}
	// Wet sheen: a tight highlight from the sun toward the viewer; fresh
	// spoil glistens even where the ground is dry.
	wet = max(wet, smoothstep(0.1, 1.0, loose) * spoil_gloss);
	if (tier < 2 && wet > 0.0) {
		vec3 v = normalize(vec3(0.0, 0.6, 0.8));
		vec3 hv = normalize(l + v);
		float spec = pow(max(dot(n, hv), 0.0), 36.0);
		color += sky_color * spec * wet * wet_gloss;
	}

	return color;
}


// --- water ------------------------------------------------------------------

// OpenSimplex2 with derivatives, for caustics (permutation
// polynomial hash credit Stefan Gustavson).
vec4 permute4(vec4 t) { return t * (t * 34.0 + 133.0); }
vec3 os_grad(float hash) {
	vec3 cube = mod(floor(hash / vec3(1.0, 2.0, 4.0)), 2.0) * 2.0 - 1.0;
	vec3 cuboct = cube;
	cuboct[int(hash / 16.0)] = 0.0;
	float type = mod(floor(hash / 8.0), 2.0);
	vec3 rhomb = (1.0 - type) * cube + type * (cuboct + cross(cube, cuboct));
	vec3 g = cuboct * 1.22474487139 + rhomb;
	g *= (1.0 - 0.042942436724648037 * type) * 3.5946317686139184;
	return g;
}
vec4 os_part(vec3 X) {
	vec3 b = floor(X);
	vec4 i4 = vec4(X - b, 2.5);
	vec3 v1 = b + floor(dot(i4, vec4(.25)));
	vec3 v2 = b + vec3(1, 0, 0) + vec3(-1, 1, 1) * floor(dot(i4, vec4(-.25, .25, .25, .35)));
	vec3 v3 = b + vec3(0, 1, 0) + vec3(1, -1, 1) * floor(dot(i4, vec4(.25, -.25, .25, .35)));
	vec3 v4 = b + vec3(0, 0, 1) + vec3(1, 1, -1) * floor(dot(i4, vec4(.25, .25, -.25, .35)));
	vec4 hashes = permute4(mod(vec4(v1.x, v2.x, v3.x, v4.x), 289.0));
	hashes = permute4(mod(hashes + vec4(v1.y, v2.y, v3.y, v4.y), 289.0));
	hashes = mod(permute4(mod(hashes + vec4(v1.z, v2.z, v3.z, v4.z), 289.0)), 48.0);
	vec3 d1 = X - v1; vec3 d2 = X - v2; vec3 d3 = X - v3; vec3 d4 = X - v4;
	vec4 a = max(0.75 - vec4(dot(d1, d1), dot(d2, d2), dot(d3, d3), dot(d4, d4)), 0.0);
	vec4 aa = a * a; vec4 aaaa = aa * aa;
	vec3 g1 = os_grad(hashes.x); vec3 g2 = os_grad(hashes.y);
	vec3 g3 = os_grad(hashes.z); vec3 g4 = os_grad(hashes.w);
	vec4 ex = vec4(dot(d1, g1), dot(d2, g2), dot(d3, g3), dot(d4, g4));
	vec4 derivative = -8.0 * mat4(vec4(d1, 0.), vec4(d2, 0.), vec4(d3, 0.), vec4(d4, 0.)) * (aa * a * ex)
		+ mat4(vec4(g1, 0.), vec4(g2, 0.), vec4(g3, 0.), vec4(g4, 0.)) * aaaa;
	return vec4(derivative.xyz, dot(aaaa, ex));
}
vec4 os_noise(vec3 X) {
	X = dot(X, vec3(2.0 / 3.0)) - X;
	vec4 r = os_part(X) + os_part(X + 144.5);
	return vec4(dot(r.xyz, vec3(2.0 / 3.0)) - r.xyz, r.w);
}

vec2 water_flow(vec2 world) {
	return texture(flow_tex, world / (map_tiles * tile_px)).rg;
}

// The wave field's height (px) at a point: three warped trains travelling
// along `direction`, with sharpened peaks.
float wave_at(vec2 p, vec2 direction, float speed) {
	if (wave_height <= 0.0) return 0.0;
	float k = TAU / max(wavelength, 1.0);
	float travel = TIME * speed;
	vec2 q = p * k;
	vec2 warp = vec2(noise(p * 0.17 + vec2(17.0, 43.0), 9.0), noise(p * 0.21 + vec2(71.0, 9.0), 9.0)) - 0.5;
	q += warp * 5.0;
	vec2 d2 = vec2(direction.x * 0.798 - direction.y * 0.603, direction.x * 0.603 + direction.y * 0.798);
	vec2 d3 = vec2(direction.x * 0.37 + direction.y * 0.929, -direction.x * 0.929 + direction.y * 0.37);
	float a = sin(dot(q, direction) - travel * k);
	float b = sin(dot(q, d2) * 1.731 - travel * k * 0.81 + 1.4);
	float c = sin(dot(q, d3) * 2.417 - travel * k * 0.57);
	float h = (a + b * 0.38 + c * 0.19) / 1.57;
	return wave_height * (h + peak_sharpness * (h * h - 0.3) * 0.65);
}

// Ground seen through `depth` px of water at `g`, with the water over it.
vec3 shade_water(vec2 g, int tier, float depth) {
	vec2 flow = water_flow(g);
	float flow_speed = length(flow);
	vec2 direction = flow_speed > 0.5 ? flow / flow_speed : normalize(still_direction);
	float speed = wave_speed + flow_speed * 0.6;
	float shallow = shallow_wave_depth > 0.0 ? smoothstep(0.0, shallow_wave_depth, depth) : 1.0;
	float h = 0.0;
	vec3 n = vec3(0.0, 0.0, 1.0);
	if (tier < 2) {
		h = wave_at(g, direction, speed);
		vec2 gradient = vec2(wave_at(g + vec2(1.0, 0.0), direction, speed) - h, wave_at(g + vec2(0.0, 1.0), direction, speed) - h);
		n = normalize(vec3(-gradient * shallow, 1.0));
	}
	// The GPU detail: ripples bend the surface, foam and silt ride the current.
	vec2 map_px = map_tiles * tile_px;
	vec4 fx = texture(fx_tex, g / map_px);
	if (tier < 2) {
		float rx = texture(fx_tex, (g + vec2(4.0, 0.0)) / map_px).b - texture(fx_tex, (g - vec2(4.0, 0.0)) / map_px).b;
		float ry = texture(fx_tex, (g + vec2(0.0, 4.0)) / map_px).b - texture(fx_tex, (g - vec2(0.0, 4.0)) / map_px).b;
		n = normalize(n + vec3(-rx, -ry, 0.0) * ripple_normal * shallow);
	}
	// The floor, bent by the surface.
	vec2 floor_point = tier == 0 ? g + n.xy * min(depth, 4.0) * refraction_px : g;
	vec3 transmitted = shade_dry(floor_point, tier);
	if (tier == 0 && caustics_intensity > 0.0) {
		vec3 X = vec3(floor_point * 0.11, mod(TIME, 578.0) * 0.8660254);
		vec4 r = os_noise(X);
		r = os_noise(X - r.xyz / 16.0);
		float pattern = pow(clamp(r.w * 0.5 + 0.5, 0.0, 1.0), 3.0);
		transmitted += caustics_color * pattern * caustics_intensity * exp(-depth / color_depth);
	}
	float absorption = 1.0 - exp(-depth / max(color_depth, 0.1));
	// This water's own colour, where the map gives one: its shallows that
	// colour, its depths the same darkened.
	vec4 own = texture(water_color_tex, g / map_px);
	vec3 shallow_tint = mix(water_shallow, own.rgb, own.a);
	vec3 deep_tint = mix(water_deep, own.rgb * 0.45, own.a);
	vec3 tint = mix(shallow_tint, deep_tint, clamp(depth / water_depth_px, 0.0, 1.0));
	// Silt stirred up by vehicles and blasts, carried off by the current.
	float silt = fx.g * silt_strength;
	tint = mix(tint, silt_color, clamp(silt * 1.4, 0.0, 1.0));
	absorption = mix(absorption, 1.0, clamp(silt * 1.5, 0.0, 1.0));
	vec3 color = mix(transmitted, tint, mix(absorption, 1.0, water_clarity * absorption));
	if (tier < 2) {
		// The sky at grazing angles of the tilt, and the sun's glint.
		vec3 v = normalize(vec3(0.0, 0.6, 0.8));
		float fresnel = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 5.0);
		color = mix(color, sky_color, clamp(0.05 + fresnel * 2.0, 0.0, 0.45) * (1.0 - silt));
		vec3 hv = normalize(normalize(sun_dir) + v);
		color += sky_color * pow(max(dot(n, hv), 0.0), 90.0) * sun_glint * shallow;
		// An oil slick: rainbow bands carried on the current, calming the foam.
		float slick = texture(tile_layers, vec3(g / map_px, 2.0)).r;
		if (slick > 0.01) {
			float cover = smoothstep(0.01, 0.6, slick) * 0.55;
			color = mix(color, film_colour(slick * 3.0, g - direction * TIME * speed * 0.3) * 0.5 + color * 0.5, cover);
		}
		// Contact foam on the shore, broken up and drifting with the current.
		vec2 drift = direction * TIME * speed;
		float breakup = noise(g * 2.3 - drift * 0.6, 9.0);
		float coverage = smoothstep(1.0 - foam_amount, 1.08 - foam_amount, breakup);
		// Still water (a puddle, a pond) keeps only a thin rim; running water a band.
		float moving = smoothstep(2.0, 14.0, flow_speed);
		float band = foam_depth * mix(0.25, 1.0, moving);
		float contact = band > 0.0 ? (1.0 - smoothstep(0.0, band, depth)) * mix(0.6, coverage, moving) : 0.0;
		float rim = noise(g * 7.0 - drift * 1.4, 9.0);
		contact *= 0.65 + 0.35 * smoothstep(0.25, 0.7, rim);
		// Crest foam on the upper band of the waves, more of it in fast water.
		float crest = 0.0;
		if (tier == 0) {
			float amount = clamp(crest_foam_amount + rapids_foam * smoothstep(10.0, 40.0, flow_speed), 0.0, 1.0);
			float elevation = h / max(wave_height, 0.001);
			float level = mix(0.58, 1.12, crest_foam_threshold);
			vec2 across = vec2(-direction.y, direction.x);
			vec2 foam_uv = vec2(dot(g - drift, direction) * 3.1, dot(g - drift, across) * 1.8);
			float detail = noise(foam_uv, 9.0);
			crest = smoothstep(level - 0.05, level + 0.05, elevation) * smoothstep(1.0 - amount - 0.08, 1.0 - amount + 0.08, detail) * shallow;
		}
		// Crisp, in two steps, to sit with the pixel art.
		// Carried foam breaks into patches and streaks, not a smooth sheet.
		float carried = step(noise(g - drift * 0.3, 3.0) * 0.9 + 0.08, fx.r);
		float foam = max(max(contact, crest), carried) * (1.0 - clamp(slick * 3.0, 0.0, 0.9));
		foam = foam > 0.6 ? 1.0 : (foam > 0.3 ? 0.55 : 0.0);
		color = mix(color, foam_color, foam);
	}
	// The shallowest edge fades into the ground instead of ending in a line.
	float shore = shore_fade_depth > 0.0 ? smoothstep(0.0, shore_fade_depth, depth) : 1.0;
	return mix(shade_dry(g, tier), color, shore);
}

vec3 shade_ground(vec2 g, int tier, bool on_water) {
	float depth = water_level(g) - relief(g);
	if (depth > 0.02) return shade_water(g, tier, depth);
	return shade_dry(g, tier);
}

// A value 0..1 as a colour ramp (dark blue, teal, green, yellow, red).
vec3 ramp(float v) {
	v = clamp(v, 0.0, 1.0);
	vec3 a = vec3(0.10, 0.12, 0.40);
	vec3 b = vec3(0.10, 0.55, 0.60);
	vec3 c = vec3(0.35, 0.75, 0.25);
	vec3 d = vec3(0.95, 0.85, 0.20);
	vec3 e = vec3(0.90, 0.20, 0.12);
	if (v < 0.25) return mix(a, b, v / 0.25);
	if (v < 0.5) return mix(b, c, (v - 0.25) / 0.25);
	if (v < 0.75) return mix(c, d, (v - 0.5) / 0.25);
	return mix(d, e, (v - 0.75) / 0.25);
}

// The debug overlay over a greyed picture of the ground, SimCity style.
vec3 overlay_color(vec2 p, vec3 under) {
	vec2 uv = cell_uv(p);
	float v = 0.0;
	bool shown = true;
	if (overlay == 1) v = texelFetch(wear_tex, ivec2(uv * chunk_texels), 0).r;
	else if (overlay == 2) v = texture(wet_tex, uv).r;
	else if (overlay == 3) v = 0.5 + relief(p) / 16.0;
	else if (overlay == 4) v = texture(loose_tex, uv).r / 3.0;
	else if (overlay == 5) v = texture(track_tex, uv).r;
	else if (overlay == 6) v = texture(scorch_tex, uv).r;
	else if (overlay == 7) { float d = water_level(p) - relief(p); shown = d > 0.0; v = d / 12.0; }
	else if (overlay == 8) {
		int id; vec4 s = splat(p, id); s = worn(s, id, p);
		return mix(vec3(dot(under, vec3(0.33))), PALETTE[id * 3 + 2], 0.8);
	}
	else if (overlay == 11) { v = snow_depth(p) / 8.0; }
	else if (overlay == 10) { v = texture(oil_tex, uv).r + texture(tile_layers, vec3(p / (map_tiles * tile_px), 2.0)).r; }
	else if (overlay == 9) { float e = elevation(p); v = fract(e / 32.0); if (fract(e / 4.0) < 0.12) return vec3(0.1); }
	float grey = dot(under, vec3(0.299, 0.587, 0.114));
	if (!shown || (overlay != 3 && overlay != 9 && v <= 0.001)) return vec3(grey * 0.8);
	return mix(vec3(grey), ramp(v), 0.7);
}

vec3 draw_tier(vec2 p, int tier) {
	bool on_water = false;
	vec2 g = tier == 0 ? march(p, on_water) : p;
	return shade_ground(g, tier, on_water);
}

void fragment() {
	// One sample per world pixel, at its centre: crisp at any whole zoom.
	vec2 p = chunk_origin_px + floor(local_px) + 0.5;
	vec3 color = draw_tier(p, lod);
	if (lod_mix < 1.0) color = mix(draw_tier(p, lod_from), color, lod_mix);
	if (posterize_levels > 0.0) color = floor(color * posterize_levels + 0.5) / posterize_levels;
	if (overlay > 0) color = overlay_color(p, color);
	COLOR = vec4(color, 1.0);
}
