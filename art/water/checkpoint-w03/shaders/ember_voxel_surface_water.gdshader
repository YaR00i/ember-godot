shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx, specular_occlusion_disabled;
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
uniform float reflection_strength : hint_range(0.0, 0.4) = 0.0; // Optional artistic tint, not captured reflection.
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
// Smooth optical waves only: the canonical water plane and collision do not move.
uniform float wave_length : hint_range(0.25, 8.0) = 1.6;
uniform float wave_speed : hint_range(0.0, 2.0) = 0.35;
uniform float wave_strength : hint_range(0.0, 0.3) = 0.10;
uniform float surface_roughness : hint_range(0.12, 1.0) = 0.28;
// 0.36 gives dielectric F0 ~= 0.021 (water), also used by sky/probe reflections.
uniform float highlight_strength : hint_range(0.0, 0.6) = 0.36;
uniform float body_emission : hint_range(0.0, 0.1) = 0.0;
uniform bool decorative_glints = false; // Existing dash controls remain optional, separate from real light.
uniform float patch_strength : hint_range(0.0, 1.0) = 0.35;
// Size in the existing block-coordinate space (1/16 = one authored voxel).
// Only the optical normal is sampled in cells; time, body and VIEW stay continuous.
uniform float reflection_pixel_size : hint_range(0.015625, 0.5, 0.015625) = 0.0625;
uniform float reflection_pixel_strength : hint_range(0.0, 1.0) = 1.0;
// Stylized light network in this material, not light projected onto the bottom.
uniform float flow_network_strength : hint_range(0.0, 1.0) = 0.60;
uniform float flow_network_deep_ratio : hint_range(0.0, 1.0) = 0.32;
uniform float flow_network_warp : hint_range(0.0, 0.5) = 0.18;
uniform float flow_pixel_density : hint_range(8.0, 64.0, 1.0) = 32.0;

varying vec2 surface_coordinate;
varying vec3 surface_world_normal;


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


vec2 optical_wave_slope(vec2 point, float seconds) {
	vec2 direction_a = vec2(0.8, 0.6);
	vec2 direction_b = vec2(-0.35, 0.93675);
	float wave_bend = broad_value_noise(point * 0.55 + vec2(13.2, 7.4)) * 2.6;
	return direction_a * cos(dot(point, direction_a) * 6.283185 + wave_bend - seconds * wave_speed)
		+ direction_b * cos(dot(point, direction_b) * 9.424778 - wave_bend * 0.6 + seconds * wave_speed * 0.73) * 0.45;
}


float flowing_ripple_network(vec2 coordinate, vec2 wave_slope, float seconds) {
	// Advect and bend the old shared network with the existing optical waves.
	// Seconds remain continuous, independent of legacy stepped colour animation.
	float phase = seconds * wave_speed * 1.4;
	vec2 point = coordinate + wave_slope * flow_network_warp;
	vec2 bend = vec2(broad_value_noise(point * 0.6 + vec2(phase * 0.12, 7.4)),
		broad_value_noise(point * 0.6 + vec2(13.2, -phase * 0.09))) - vec2(0.5);
	point += bend * flow_network_warp;
	float network = connected_ripple_network(floor(point * flow_pixel_density), phase);
	// A few soft gaps and variations prevent a uniformly painted closed mesh.
	float openings = broad_value_noise(point * 1.7 + vec2(phase * 0.16, -phase * 0.11));
	return network * smoothstep(0.05, 0.16, openings);
}


void vertex() {
	// Region meshes keep coordinates from the complete Surface Resource, so the
	// sparse line pattern crosses technical chunk boundaries without seams.
	float block_scale = coordinate_scale > 0.0 ? coordinate_scale : max(length(MODEL_MATRIX[0].xyz), 0.001);
	surface_coordinate = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz / block_scale;
	surface_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}


void fragment() {
	float seconds = preview_time >= 0.0 ? preview_time : TIME;
	float frame = floor(seconds * animation_fps);
	vec2 wave_point = surface_coordinate / max(wave_length, 0.001);
	float footprint = max(length(dFdx(wave_point)), length(dFdy(wave_point)));
	float wave_visibility = 1.0 - smoothstep(0.08, 0.32, footprint);
	vec2 continuous_slope = optical_wave_slope(wave_point, seconds);
	float cell_size = max(reflection_pixel_size, 0.015625);
	vec2 cell_center = (floor(surface_coordinate / cell_size) + vec2(0.5)) * cell_size;
	// Derivatives must come from the continuous coordinate, never the cell edges.
	float coordinate_footprint = max(length(dFdx(surface_coordinate)), length(dFdy(surface_coordinate)));
	float cell_pixels = cell_size / max(coordinate_footprint, 0.00001);
	float pixel_weight = reflection_pixel_strength * smoothstep(0.75, 2.0, cell_pixels);
	vec2 slope = continuous_slope;
	if (pixel_weight > 0.0) {
		slope = mix(continuous_slope, optical_wave_slope(cell_center / max(wave_length, 0.001), seconds), pixel_weight);
	}
	slope *= wave_strength * wave_visibility;
	vec3 continuous_normal = normalize((VIEW_MATRIX * vec4(normalize(vec3(-continuous_slope.x * wave_strength * wave_visibility, 1.0, -continuous_slope.y * wave_strength * wave_visibility)), 0.0)).xyz);
	vec3 body_facing_normal = NORMAL;
	if (surface_world_normal.y > 0.5) {
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(-slope.x, 1.0, -slope.y)), 0.0)).xyz);
		body_facing_normal = continuous_normal;
	}
	vec2 pixel = floor(surface_coordinate * pixel_density);
	float phase = frame * 0.07;
	float ripple = ripple_alpha > 0.0 ? connected_ripple_network(pixel, phase) : 0.0;
	float glint = decorative_glints ? sparse_glint(pixel, frame) : 0.0;
	float tone = stepped_tone_drift(pixel, phase);
	// UV.x is supplied by the shared Surface mesher: 0 is ankle-deep and 1
	// means four or more art voxels. The bands stay deliberately discrete.
	float depth_band = background_water ? 1.0 : floor(clamp(UV.x, 0.0, 0.999) * 4.0) / 3.0;
	float flow_network = 0.0;
	if (flow_network_strength > 0.0 && surface_world_normal.y > 0.5) {
		flow_network = flowing_ripple_network(surface_coordinate, continuous_slope, seconds);
		flow_network *= 1.0 - smoothstep(0.025, 0.10, coordinate_footprint);
	}
	float flow_weight = flow_network * flow_network_strength * mix(1.0, flow_network_deep_ratio, depth_band);
	vec3 depth_color = mix(water_light_tone, water_deep_tone, depth_band);
	vec3 tone_color = mix(depth_color, water_light_tone, tone * 0.42);
	vec3 water_body = mix(depth_color, water_tint, tint_strength);
	water_body = mix(water_body, tone_color, tone_strength * patch_strength);
	water_body = mix(water_body, water_light_tone, tone * 0.24 * patch_strength);
	if (!background_water) { water_body = mix(water_body, COLOR.rgb, palette_strength); }
	// Keep camera reflection continuous: quantized VIEW creates long cuts
	// through unrelated patches under a perspective camera. Optical cells affect
	// the specular normal; body tint/opacity retain the continuous wave facing.
	float facing = clamp(dot(normalize(body_facing_normal), normalize(VIEW)), 0.0, 1.0);
	float reflection = smoothstep(0.0, 1.0, 1.0 - facing);
	water_body = mix(
		water_body,
		sky_reflection_color,
		reflection * reflection_strength
	);
	ALBEDO = mix(water_body, ripple_color, ripple * ripple_alpha);
	ALBEDO = mix(ALBEDO, glint_color, glint * glint_strength);
	ALBEDO = mix(ALBEDO, ripple_color, flow_weight);
	ROUGHNESS = clamp(surface_roughness + (1.0 - wave_visibility) * 0.08, 0.12, 1.0);
	METALLIC = 0.0;
	SPECULAR = highlight_strength;
	EMISSION = water_body * body_emission;
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
	// Keep broad body shading on the physical plane: toon band thresholds must
	// not turn tiny optical slopes into long painted stripes. Specular uses NORMAL.
	vec3 body_normal = normalize((VIEW_MATRIX * vec4(surface_world_normal, 0.0)).xyz);
	float warm = smoothstep(0.015, 0.13, (LIGHT_COLOR.r - LIGHT_COLOR.b) / max(max(LIGHT_COLOR.r, LIGHT_COLOR.g), max(LIGHT_COLOR.b, 0.001)));
	// Keep the accepted broad diffuse band independent of optical roughness.
	float stock = smoothstep(-0.94, 0.94, dot(body_normal, LIGHT));
	vec3 stock_diffuse = LIGHT_COLOR * ATTENUATION * stock / 3.14159265;
	if (!LIGHT_IS_DIRECTIONAL || warm <= 0.001) {
		DIFFUSE_LIGHT += stock_diffuse;
	} else {
		// Stock water multiplies albedo in Godot's final compose. Do not square
		// its body palette by including albedo in custom irradiance as well.
		vec3 styled = ember_diorama_diffuse(vec3(1.0), body_normal, LIGHT, LIGHT_COLOR,
			ATTENUATION, true, 4.0, 0.19, 1.0) / 3.14159265;
		DIFFUSE_LIGHT += mix(stock_diffuse, styled, warm);
	}
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float ndotv = max(dot(NORMAL, VIEW), 0.0001);
	vec3 sum_direction = LIGHT + VIEW;
	vec3 half_vector = sum_direction / max(length(sum_direction), 0.0001);
	float ndoth = clamp(dot(NORMAL, half_vector), 0.0, 1.0);
	float alpha = max(ROUGHNESS * ROUGHNESS, 0.002);
	float denominator = 1.0 - ndoth * ndoth + ndoth * ndoth * alpha * alpha;
	float distribution = alpha * alpha / max(3.14159265 * denominator * denominator, 0.00000001);
	float visibility = 0.5 / max(mix(2.0 * ndotl * ndotv, ndotl + ndotv, alpha), 0.0001);
	float f0 = 0.16 * highlight_strength * highlight_strength;
	float fresnel = f0 + (1.0 - f0) * pow(1.0 - max(dot(VIEW, half_vector), 0.0), 5.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT
		* distribution * visibility * fresnel * ndotl;
}
