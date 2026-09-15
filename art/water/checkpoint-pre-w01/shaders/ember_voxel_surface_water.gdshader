shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_toon, specular_disabled;
#include "res://shaders/ember_diorama_light.gdshaderinc"

// Cartoon water: broad moving color islands, sparse short glints, restrained
// cell lines. Shared by Surface chunks, placed fills and the harbour backdrop.
uniform float coordinate_scale = 0.0; // 0: normalized block scale of the instance
uniform bool background_water = false;
uniform float patch_cell_size : hint_range(16.0, 96.0) = 40.0;
uniform float palette_strength : hint_range(0.0, 1.0) = 0.12;
uniform float shallow_opacity : hint_range(0.0, 1.0) = 0.56;
uniform float deep_opacity : hint_range(0.0, 1.0) = 0.78;
uniform float preview_time = -1.0; // Native QA can freeze two animation samples.
uniform vec3 water_tint : source_color = vec3(0.18, 0.82, 0.78);
uniform vec3 water_light_tone : source_color = vec3(0.36, 0.94, 0.82);
uniform vec3 water_deep_tone : source_color = vec3(0.08, 0.58, 0.62);
uniform vec3 ripple_color : source_color = vec3(0.88, 1.0, 0.94);
uniform vec3 sky_reflection_color : source_color = vec3(0.58, 0.90, 0.93);
uniform vec3 glint_color : source_color = vec3(0.65, 0.94, 0.86);
uniform float tint_strength : hint_range(0.0, 0.5) = 0.18;
uniform float tone_strength : hint_range(0.0, 1.0) = 0.4;
uniform float tone_alpha : hint_range(0.0, 0.2) = 0.035;
uniform float depth_alpha : hint_range(0.0, 0.25) = 0.08;
uniform float ripple_alpha : hint_range(0.0, 1.0) = 0.30;
uniform float reflection_strength : hint_range(0.0, 0.4) = 0.14;
uniform float reflection_alpha : hint_range(0.0, 0.2) = 0.035;
uniform float glint_strength : hint_range(0.0, 1.0) = 0.28;
uniform float glint_alpha : hint_range(0.0, 0.4) = 0.04;
uniform float glint_cell_size : hint_range(12.0, 48.0, 1.0) = 32.0;
uniform float glint_density : hint_range(0.0, 0.5) = 0.045;
uniform float glint_length : hint_range(1.0, 12.0) = 5.0;
uniform float glint_thickness : hint_range(0.25, 2.0) = 0.8;
uniform float pixel_density : hint_range(8.0, 32.0, 1.0) = 16.0;
uniform float network_cell_size : hint_range(6.0, 24.0, 1.0) = 10.0;
uniform float network_width : hint_range(0.01, 0.4, 0.005) = 0.025;
uniform float animation_fps : hint_range(0.0, 8.0, 0.25) = 2.5;

varying vec2 surface_coordinate;


float ember_water_hash(vec2 value) {
	// All callers hash lattice cells. Integer arithmetic gives the same node
	// value from either neighbouring cell; float/fract hashes can disagree
	// after GPU expression optimization and tear interpolated broad patches.
	uvec2 cell = uvec2(ivec2(value));
	uint hash = (cell.x * 1597334677u) ^ (cell.y * 3812015801u);
	hash = (hash ^ (hash >> 16u)) * 2246822519u;
	hash = (hash ^ (hash >> 13u)) * 3266489917u;
	hash = hash ^ (hash >> 16u);
	return float(hash & 16777215u) / 16777216.0;
}


vec2 ember_water_cell_point(vec2 cell, float phase) {
	float phase_x = ember_water_hash(cell + vec2(17.0, 3.0)) * 6.2831853;
	float phase_y = ember_water_hash(cell + vec2(5.0, 29.0)) * 6.2831853;
	return vec2(0.5) + vec2(
		sin(phase + phase_x),
		cos(phase * 0.83 + phase_y)
	) * 0.24;
}


float connected_ripple_network(vec2 pixel, float phase) {
	vec2 point = pixel / network_cell_size;
	vec2 base_cell = floor(point);
	vec2 local_point = fract(point);
	float nearest = 100.0;
	float second_nearest = 100.0;
	for (int offset_y = -1; offset_y <= 1; offset_y++) {
		for (int offset_x = -1; offset_x <= 1; offset_x++) {
			vec2 offset = vec2(float(offset_x), float(offset_y));
			vec2 delta = offset + ember_water_cell_point(base_cell + offset, phase) - local_point;
			float distance_squared = dot(delta, delta);
			if (distance_squared < nearest) {
				second_nearest = nearest;
				nearest = distance_squared;
			} else if (distance_squared < second_nearest) {
				second_nearest = distance_squared;
			}
		}
	}
	// The border between the two closest cells is a continuous Voronoi network.
	// Pixelized world coordinates keep it graphic instead of smooth/realistic.
	return 1.0 - step(network_width, second_nearest - nearest);
}


float broad_value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	float broad = mix(
		mix(ember_water_hash(cell), ember_water_hash(cell + vec2(1.0, 0.0)), fraction.x),
		mix(ember_water_hash(cell + vec2(0.0, 1.0)), ember_water_hash(cell + vec2(1.0)), fraction.x),
		fraction.y
	);
	return broad;
}


float stepped_tone_drift(vec2 pixel, float phase) {
	// Rotate and gently bend the single broad field before palette banding.
	// Axis-aligned interpolation cells must not read as square water tiles.
	vec2 point = vec2(pixel.x * 0.8 - pixel.y * 0.6, pixel.x * 0.6 + pixel.y * 0.8) / patch_cell_size;
	vec2 bend = vec2(broad_value_noise(point * 0.55 + vec2(13.2, 7.4)), broad_value_noise(point * 0.55 + vec2(-5.1, 23.8))) - vec2(0.5);
	float broad = broad_value_noise(point + bend * 0.8 + vec2(phase * 0.12, -phase * 0.07));
	return floor(clamp(broad, 0.0, 0.999) * 3.0) / 2.0;
}


float sparse_glint(vec2 pixel, float frame) {
	// Independent sparse dashes stay visible even with the cell network muted.
	vec2 glint_cell = floor(pixel / glint_cell_size);
	float seed = ember_water_hash(glint_cell + vec2(41.0, 73.0));
	float selected = 1.0 - step(glint_density, seed);
	float pulse = sin(frame * 0.08 + seed * 6.2831853) * 0.5 + 0.5;
	pulse = floor(clamp(pulse, 0.0, 0.999) * 3.0) / 2.0;
	vec2 local = fract(pixel / glint_cell_size);
	float crest_y = 0.3 + seed * 0.35 + sin(frame * 0.06 + seed * 6.28) * 0.08;
	float crest_x = 0.2 + ember_water_hash(glint_cell + vec2(19.0, 11.0)) * 0.6;
	float length_pixels = glint_length * mix(0.7, 1.3, seed);
	float dash = 1.0 - step(length_pixels * 0.5 / glint_cell_size, abs(local.x - crest_x));
	dash *= 1.0 - step(glint_thickness * 0.5 / glint_cell_size, abs(local.y - crest_y));
	return dash * selected * mix(0.28, 1.0, pulse);
}


void vertex() {
	// Region meshes keep coordinates from the complete Surface Resource, so the
	// sparse line pattern crosses technical chunk boundaries without seams.
	float block_scale = coordinate_scale > 0.0 ? coordinate_scale : max(length(MODEL_MATRIX[0].xyz), 0.001);
	surface_coordinate = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz / block_scale;
}


void fragment() {
	float frame = floor((preview_time >= 0.0 ? preview_time : TIME) * animation_fps);
	vec2 pixel = floor(surface_coordinate * pixel_density);
	float phase = frame * 0.07;
	float ripple = connected_ripple_network(pixel, phase);
	float glint = sparse_glint(pixel, frame);
	float tone = stepped_tone_drift(pixel, phase);
	// UV.x is supplied by the shared Surface mesher: 0 is ankle-deep and 1
	// means four or more art voxels. The bands stay deliberately discrete.
	float depth_band = background_water ? 1.0 : floor(clamp(UV.x, 0.0, 0.999) * 4.0) / 3.0;
	vec3 depth_color = mix(water_light_tone, water_deep_tone, depth_band);
	vec3 tone_color = mix(depth_color, water_light_tone, tone * 0.42);
	vec3 water_body = mix(depth_color, water_tint, tint_strength);
	water_body = mix(water_body, tone_color, tone_strength);
	water_body = mix(water_body, water_light_tone, tone * 0.24);
	if (!background_water) { water_body = mix(water_body, COLOR.rgb, palette_strength); }
	// Keep camera reflection continuous: quantized VIEW creates long cuts
	// through unrelated patches under a perspective camera. Only the moving
	// world-space color islands keep deliberately discrete pixel-art bands.
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float reflection = smoothstep(0.0, 1.0, 1.0 - facing);
	water_body = mix(
		water_body,
		sky_reflection_color,
		reflection * reflection_strength
	);
	ALBEDO = mix(water_body, ripple_color, ripple * ripple_alpha);
	ALBEDO = mix(ALBEDO, glint_color, glint * glint_strength);
	ROUGHNESS = 0.94;
	METALLIC = 0.0;
	EMISSION = water_body * 0.10 + glint_color * glint * 0.025;
	float body_alpha = (
		mix(shallow_opacity, deep_opacity, depth_band)
		+ tone * tone_alpha
		+ depth_band * depth_alpha
		+ reflection * reflection_alpha
	);
	ALPHA = clamp(
		background_water ? 1.0 : body_alpha + glint * glint_alpha,
		0.035,
		1.0
	);
}

void light() {
	// Same directional hue family, with water's own fragment/alpha/animation.
	// Godot's stock diffuse (our baseline) uses irradiance / PI.
	float warm = smoothstep(0.015, 0.13, (LIGHT_COLOR.r - LIGHT_COLOR.b) / max(max(LIGHT_COLOR.r, LIGHT_COLOR.g), max(LIGHT_COLOR.b, 0.001)));
	float stock = smoothstep(-ROUGHNESS, max(ROUGHNESS, 0.01), dot(NORMAL, LIGHT));
	vec3 stock_diffuse = LIGHT_COLOR * ATTENUATION * stock / 3.14159265;
	if (!LIGHT_IS_DIRECTIONAL || warm <= 0.001) {
		DIFFUSE_LIGHT += stock_diffuse;
	} else {
		// Stock water multiplies albedo in Godot's final compose. Do not square
		// its body palette by including albedo in custom irradiance as well.
		vec3 styled = ember_diorama_diffuse(vec3(1.0), NORMAL, LIGHT, LIGHT_COLOR,
			ATTENUATION, true, 4.0, 0.19, 1.0) / 3.14159265;
		DIFFUSE_LIGHT += mix(stock_diffuse, styled, warm);
	}
}
