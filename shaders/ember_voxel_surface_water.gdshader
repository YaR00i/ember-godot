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
// Natural wave composition is opt-in so Review2 and authored material defaults
// remain exact. The selected water uses one dominant system, a crossing system
// and restrained wind ripples, all derived from this shared state.
uniform float wave_natural_mix : hint_range(0.0, 1.0) = 0.0;
uniform float wave_direction_degrees : hint_range(-180.0, 180.0, 1.0) = 36.87;
uniform float wave_direction_spread : hint_range(0.0, 60.0, 1.0) = 18.0;
uniform float wave_scale_variation : hint_range(0.0, 1.0) = 0.55;
uniform float wave_grouping : hint_range(0.0, 1.0) = 0.58;
uniform float wind_ripple_strength : hint_range(0.0, 1.0) = 0.18;
uniform float wave_crest_sharpness : hint_range(0.0, 1.0) = 0.25;
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
// Optional layered art direction: one coherent wave field drives the water
// body values, lit crest rims and physical sun glitter. Zero preserves W03+.
uniform float layered_water_mix : hint_range(0.0, 1.0) = 0.0;
uniform vec3 wave_shadow_tone : source_color = vec3(0.025, 0.30, 0.38);
uniform vec3 wave_crest_tone : source_color = vec3(0.36, 0.86, 0.84);
uniform float wave_band_strength : hint_range(0.0, 1.0) = 0.72;
uniform float surface_crest_strength : hint_range(0.0, 1.0) = 0.34;
uniform float surface_crest_width : hint_range(0.02, 0.35) = 0.12;
uniform float sun_glitter_strength : hint_range(0.0, 2.0) = 0.55;
uniform float sun_glitter_threshold : hint_range(0.96, 0.9995, 0.0005) = 0.996;
// Optional direct-sun treatment. At zero the W03 GGX response is unchanged.
uniform float pixel_highlight_mix : hint_range(0.0, 1.0) = 0.0;
uniform float pixel_highlight_threshold : hint_range(0.90, 0.999, 0.001) = 0.986;
uniform float pixel_highlight_core : hint_range(0.90, 0.999, 0.001) = 0.996;
uniform float pixel_highlight_strength : hint_range(0.0, 2.0) = 1.15;
uniform float pixel_highlight_cell_size : hint_range(0.03125, 0.5, 0.03125) = 0.125;
uniform float pixel_highlight_view_dependence : hint_range(0.0, 1.0) = 1.0;
uniform float pixel_highlight_smooth_motion : hint_range(0.0, 1.0) = 0.0;
uniform float pixel_highlight_edge_wobble : hint_range(0.0, 0.25, 0.01) = 0.0;
uniform float pixel_highlight_travel_speed : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float pixel_highlight_wobble_speed : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float pixel_highlight_cohesion : hint_range(0.0, 1.0) = 0.0;
uniform vec2 pixel_highlight_flow_direction = vec2(0.8, 0.6);
uniform float pixel_highlight_flow_speed : hint_range(0.0, 0.5, 0.01) = 0.18;
uniform float pixel_highlight_shape_scale : hint_range(0.1, 2.0, 0.05) = 0.65;
uniform float pixel_highlight_shape_threshold : hint_range(0.2, 0.8, 0.01) = 0.54;
uniform vec3 pixel_highlight_color : source_color = vec3(0.92, 1.0, 1.0);
uniform float stylized_shadow_mix : hint_range(0.0, 1.0) = 0.0;
uniform float stylized_shadow_threshold : hint_range(0.0, 1.0) = 0.52;
uniform float stylized_shadow_pixel_size : hint_range(0.03125, 0.5, 0.03125) = 0.125;
uniform float stylized_shadow_steps : hint_range(1.0, 4.0, 1.0) = 2.0;
// Optional screen-space view through the water. Transparent water is absent
// from these opaque buffers; the sample therefore contains the visible bottom.
uniform sampler2D underwater_screen : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D underwater_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform float underwater_light_mix : hint_range(0.0, 1.0) = 0.0;
uniform float underwater_caustic_strength : hint_range(0.0, 1.0) = 0.42;
uniform float underwater_caustic_width : hint_range(0.0, 1.0) = 0.50;
uniform vec3 underwater_caustic_color : source_color = vec3(0.90, 1.0, 0.84);
uniform float underwater_refraction_strength : hint_range(0.0, 0.02) = 0.004;
uniform float underwater_pixel_size : hint_range(1.0, 8.0, 1.0) = 2.0;
uniform float underwater_depth_range : hint_range(0.1, 4.0) = 1.5;
// Surface meshes normally carry authored depth in UV.x. A laboratory plane has
// ordinary UVs, so it can opt into the actual opaque floor distance instead.
// Zero preserves every authored water chunk and its four deliberate UV bands.
uniform float scene_depth_mix : hint_range(0.0, 1.0) = 0.0;
// Shore Lab is an opt-in visual prototype. Defaults preserve every authored
// water surface; the lab supplies one voxel-derived boundary coordinate later.
uniform float shore_effect_strength : hint_range(0.0, 1.0) = 0.0;
uniform bool shore_geometry_driven = false;
uniform float shore_boundary_x = -4.75;
uniform float shore_split_z = 0.0;
uniform float shore_zone_gap = 1.35;
uniform float shore_zone_outer = 6.65;
uniform float shore_break_distance : hint_range(0.25, 4.0) = 1.35;
uniform float shore_foam_width : hint_range(0.03, 0.4) = 0.09;
uniform float shore_runup_distance : hint_range(0.0, 2.0) = 1.05;
uniform float shore_wet_trace : hint_range(0.0, 1.0) = 0.42;
uniform float shore_reflection_strength : hint_range(0.0, 1.0) = 0.50;
uniform float shore_reflection_distance : hint_range(0.25, 4.0) = 2.35;
uniform float shore_wave_transform : hint_range(0.0, 1.0) = 0.0;
uniform float shore_shoaling_distance : hint_range(1.0, 8.0) = 4.5;
uniform float shore_shallow_depth : hint_range(0.0, 0.8) = 0.10;
uniform float shore_deep_depth : hint_range(0.1, 1.0) = 0.72;
uniform float shore_refraction_strength : hint_range(0.0, 1.0) = 0.86;
uniform float shore_wavelength_compression : hint_range(0.0, 0.68) = 0.42;
uniform float shore_shoaling_strength : hint_range(0.0, 1.0) = 0.48;
uniform float shore_crest_coherence : hint_range(0.0, 1.0) = 0.76;
uniform float shore_break_threshold : hint_range(0.25, 1.2) = 0.78;
uniform float shore_break_softness : hint_range(0.02, 0.30) = 0.10;
uniform float shore_runup_speed : hint_range(0.1, 2.0) = 0.72;
uniform float underwater_caustic_wave_link : hint_range(0.0, 1.0) = 0.0;
uniform float visual_wave_height : hint_range(0.0, 0.08) = 0.0;
uniform float visual_wave_shore_fade : hint_range(0.05, 1.5) = 0.55;

#include "res://shaders/ember_water_wave.gdshaderinc"

varying vec2 surface_coordinate;
varying vec3 surface_world_normal;
varying float surface_coordinate_world_scale;
varying vec2 surface_shore_inward;
varying float surface_shore_distance_value;
varying float surface_shore_wall_value;
varying float surface_shore_depth_value;


vec3 surface_wave_state(
	vec2 coordinate,
	float seconds,
	float shore_distance,
	float shore_depth,
	vec2 shore_inward,
	float shore_wall
) {
	if (shore_geometry_driven && length(shore_inward) > 0.5) {
		return water_shore_wave_state(
			coordinate,
			seconds,
			shore_distance,
			shore_depth,
			normalize(shore_inward),
			shore_wall,
			shore_wave_transform,
			shore_shoaling_distance,
			shore_shallow_depth,
			shore_deep_depth,
			shore_refraction_strength,
			shore_wavelength_compression,
			shore_shoaling_strength,
			shore_crest_coherence
		);
	}
	return water_wave_state(coordinate / max(wave_length, 0.001), seconds);
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


float shore_cycle(vec2 coordinate, float seconds) {
	// Sample the dominant directional wave at the boundary. All shore events
	// share this phase, so foam, contact and reflection cannot drift apart.
	float angle = radians(wave_direction_degrees);
	vec2 direction = vec2(cos(angle), sin(angle));
	vec2 boundary_point = vec2(shore_boundary_x, coordinate.y) / max(wave_length, 0.001);
	float phase_warp = (sin(coordinate.y * 0.47) * 0.42
		+ sin(coordinate.y * 0.91 + 1.3) * 0.18) * wave_scale_variation;
	float phase = dot(boundary_point, direction) * 6.283185 + phase_warp - seconds * wave_speed;
	return fract(-phase / 6.283185);
}


float coherent_shore_line(float distance_to_boundary, float front, float width, float along_shore) {
	// Two long harmonics bend the entire line. There is no per-cell random mask,
	// so the crest remains one connected graphic shape while it moves.
	float bend = sin(along_shore * 1.13) * 0.055 + sin(along_shore * 2.41 + 1.7) * 0.025;
	return 1.0 - smoothstep(width * 0.45, width, abs(distance_to_boundary - front - bend));
}


float shared_wave_caustic(
	vec2 coordinate,
	float seconds,
	float shore_distance,
	float shore_depth,
	vec2 shore_inward,
	float shore_wall
) {
	// A small Laplacian approximates where the common wave surface focuses
	// light. This makes bottom light a relative of the wave, not a copied grid.
	float epsilon = max(wave_length, 0.001) * 0.075;
	float center = surface_wave_state(coordinate, seconds, shore_distance, shore_depth, shore_inward, shore_wall).z;
	float neighbours = surface_wave_state(coordinate + vec2(epsilon, 0.0), seconds, shore_distance, shore_depth, shore_inward, shore_wall).z
		+ surface_wave_state(coordinate - vec2(epsilon, 0.0), seconds, shore_distance, shore_depth, shore_inward, shore_wall).z
		+ surface_wave_state(coordinate + vec2(0.0, epsilon), seconds, shore_distance, shore_depth, shore_inward, shore_wall).z
		+ surface_wave_state(coordinate - vec2(0.0, epsilon), seconds, shore_distance, shore_depth, shore_inward, shore_wall).z;
	float curvature = abs(neighbours - center * 4.0) / max(epsilon * epsilon, 0.0001);
	// Width lowers the focusing threshold while keeping one smooth connected
	// band. It expands a crest instead of adding unrelated speckles.
	float focus_edge = mix(10.0, 2.8, underwater_caustic_width);
	float focus_core = focus_edge + mix(8.0, 3.5, underwater_caustic_width);
	float focused = smoothstep(focus_edge, focus_core, curvature);
	return focused * mix(0.58, 1.0, smoothstep(-0.35, 0.70, center));
}


vec2 optical_wave_slope(
	vec2 coordinate,
	float seconds,
	float shore_distance,
	float shore_depth,
	vec2 shore_inward,
	float shore_wall
) {
	return surface_wave_state(coordinate, seconds, shore_distance, shore_depth, shore_inward, shore_wall).xy;
}


vec2 highlight_edge_offset(vec2 coordinate, float seconds) {
	// Low-frequency counter-moving waves make the edge breathe without breaking
	// the clean highlight into independently animated cells.
	float phase = seconds * wave_speed * pixel_highlight_wobble_speed;
	vec2 point = coordinate / max(wave_length, 0.001);
	return vec2(
		sin(point.y * 2.1 + phase * 0.72) + sin((point.x + point.y) * 1.15 - phase * 0.38) * 0.42,
		cos(point.x * 1.8 - phase * 0.61) + cos((point.x - point.y) * 1.05 + phase * 0.31) * 0.38
	) * pixel_highlight_edge_wobble;
}


float connected_highlight_field(vec2 coordinate, vec2 flow_direction) {
	vec2 side = vec2(-flow_direction.y, flow_direction.x);
	// Stretch the static field along the travel axis. Thresholding this smooth
	// field gives broad bent silhouettes; translating the coordinate moves each
	// silhouette intact without rebuilding it from independent cells.
	vec2 shaped = vec2(dot(coordinate, flow_direction) * 0.48, dot(coordinate, side) * 0.82);
	float broad = broad_value_noise(shaped * pixel_highlight_shape_scale + vec2(4.7, 9.3));
	float bend = broad_value_noise(shaped * pixel_highlight_shape_scale * 1.75 + vec2(17.2, 3.8));
	return broad * 0.82 + bend * 0.18;
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
	surface_coordinate_world_scale = block_scale;
	surface_shore_inward = UV2;
	surface_shore_distance_value = max(abs(UV.y) - 0.0001, 0.0);
	surface_shore_wall_value = step(UV.y, -0.00005);
	surface_shore_depth_value = clamp(UV.x, 0.0, 1.0);
	if (visual_wave_height > 0.0 && surface_world_normal.y > 0.5) {
		float seconds = preview_time >= 0.0 ? preview_time : TIME;
		float shore_amount = shore_geometry_driven && length(UV2) > 0.5
			? water_shore_amount(surface_shore_distance_value, shore_shoaling_distance)
				* water_shallow_amount(surface_shore_depth_value, shore_shallow_depth, shore_deep_depth)
				* shore_wave_transform * (1.0 - surface_shore_wall_value)
			: 0.0;
		float shore_fade = mix(1.0, 0.28, smoothstep(0.78, 1.0, shore_amount));
		float height = surface_wave_state(
			surface_coordinate, seconds, surface_shore_distance_value, surface_shore_depth_value,
			UV2, surface_shore_wall_value
		).z;
		VERTEX.y += height * visual_wave_height * shore_fade;
	}
}


void fragment() {
	float seconds = preview_time >= 0.0 ? preview_time : TIME;
	float frame = floor(seconds * animation_fps);
	vec2 wave_point = surface_coordinate / max(wave_length, 0.001);
	float footprint = max(length(dFdx(wave_point)), length(dFdy(wave_point)));
	float wave_visibility = 1.0 - smoothstep(0.08, 0.32, footprint);
	vec2 continuous_slope = optical_wave_slope(
		surface_coordinate, seconds, surface_shore_distance_value, surface_shore_depth_value,
		surface_shore_inward, surface_shore_wall_value
	);
	float layered_wave_height = 0.0;
	if (layered_water_mix > 0.0 && surface_world_normal.y > 0.5) {
		vec3 layered_wave = surface_wave_state(
			surface_coordinate, seconds, surface_shore_distance_value, surface_shore_depth_value,
			surface_shore_inward, surface_shore_wall_value
		);
		continuous_slope = mix(continuous_slope, layered_wave.xy, layered_water_mix);
		layered_wave_height = layered_wave.z;
	}
	float cell_size = max(reflection_pixel_size, 0.015625);
	vec2 cell_center = (floor(surface_coordinate / cell_size) + vec2(0.5)) * cell_size;
	// Derivatives must come from the continuous coordinate, never the cell edges.
	float coordinate_footprint = max(length(dFdx(surface_coordinate)), length(dFdy(surface_coordinate)));
	float cell_pixels = cell_size / max(coordinate_footprint, 0.00001);
	float pixel_weight = reflection_pixel_strength * smoothstep(0.75, 2.0, cell_pixels);
	vec2 slope = continuous_slope;
	if (pixel_weight > 0.0) {
		slope = mix(continuous_slope, optical_wave_slope(
			cell_center, seconds, surface_shore_distance_value, surface_shore_depth_value,
			surface_shore_inward, surface_shore_wall_value
		), pixel_weight);
	}
	slope *= wave_strength * wave_visibility;
	vec3 continuous_normal = normalize((VIEW_MATRIX * vec4(normalize(vec3(-continuous_slope.x * wave_strength * wave_visibility, 1.0, -continuous_slope.y * wave_strength * wave_visibility)), 0.0)).xyz);
	vec3 body_facing_normal = NORMAL;
	if (surface_world_normal.y > 0.5) {
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(-slope.x, 1.0, -slope.y)), 0.0)).xyz);
		body_facing_normal = continuous_normal;
	}
	if (stylized_shadow_mix > 0.0 && surface_world_normal.y > 0.5) {
		float shadow_cell_size = max(stylized_shadow_pixel_size, 0.03125);
		vec2 shadow_cell_center = (floor(surface_coordinate / shadow_cell_size) + vec2(0.5)) * shadow_cell_size;
		vec2 shadow_world_delta = (shadow_cell_center - surface_coordinate) * surface_coordinate_world_scale;
		LIGHT_VERTEX += (VIEW_MATRIX * vec4(shadow_world_delta.x, 0.0, shadow_world_delta.y, 0.0)).xyz;
	}
	vec2 pixel = floor(surface_coordinate * pixel_density);
	float phase = frame * 0.07;
	float ripple = ripple_alpha > 0.0 ? connected_ripple_network(pixel, phase) : 0.0;
	float glint = decorative_glints ? sparse_glint(pixel, frame) : 0.0;
	float tone = stepped_tone_drift(pixel, phase);
	// Authored Surface meshes supply depth in UV.x. Plain laboratory meshes do
	// not, so their opt-in path measures the real distance to the opaque floor.
	float authored_depth_band = background_water ? 1.0 : floor(clamp(UV.x, 0.0, 0.999) * 4.0) / 3.0;
	float depth_band = authored_depth_band;
	if (scene_depth_mix > 0.0 && !background_water && surface_world_normal.y > 0.5) {
		float floor_depth = textureLod(underwater_depth, SCREEN_UV, 0.0).r;
		vec4 floor_reconstructed = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, floor_depth, 1.0);
		vec3 floor_view = floor_reconstructed.xyz / max(floor_reconstructed.w, 0.00001);
		vec3 floor_world = (INV_VIEW_MATRIX * vec4(floor_view, 1.0)).xyz;
		vec3 surface_world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float visible_floor_depth = max(surface_world.y - floor_world.y, 0.0);
		float measured_depth_band = smoothstep(0.10, underwater_depth_range, visible_floor_depth);
		depth_band = mix(authored_depth_band, measured_depth_band, scene_depth_mix);
	}
	float flow_network = 0.0;
	if (flow_network_strength > 0.0 && surface_world_normal.y > 0.5) {
		flow_network = flowing_ripple_network(surface_coordinate, continuous_slope, seconds);
		flow_network *= 1.0 - smoothstep(0.025, 0.10, coordinate_footprint);
	}
	float flow_weight = flow_network * flow_network_strength * mix(1.0, flow_network_deep_ratio, depth_band);
	float shore_light = 0.0;
	float shore_dark = 0.0;
	if (shore_effect_strength > 0.0 && !shore_geometry_driven && surface_world_normal.y > 0.5) {
		float shore_pixel = max(reflection_pixel_size, 0.0625);
		vec2 shore_coordinate = (floor(surface_coordinate / shore_pixel) + vec2(0.5)) * shore_pixel;
		float distance_to_boundary = max(shore_coordinate.x - shore_boundary_x, 0.0);
		float cycle = shore_cycle(shore_coordinate, seconds);
		float beach_mask = smoothstep(
			shore_split_z + shore_zone_gap,
			shore_split_z + shore_zone_gap + 0.18,
			shore_coordinate.y
		) * (1.0 - smoothstep(
			shore_split_z + shore_zone_outer - 0.18,
			shore_split_z + shore_zone_outer,
			shore_coordinate.y
		));
		float wall_mask = smoothstep(
			shore_split_z - shore_zone_outer,
			shore_split_z - shore_zone_outer + 0.18,
			shore_coordinate.y
		) * (1.0 - smoothstep(
			shore_split_z - shore_zone_gap - 0.18,
			shore_split_z - shore_zone_gap,
			shore_coordinate.y
		));
		float approach = clamp(cycle / 0.46, 0.0, 1.0);
		float incoming_active = 1.0 - smoothstep(0.42, 0.48, cycle);
		float incoming_front = mix(shore_break_distance, 0.0, approach);
		float incoming = coherent_shore_line(
			distance_to_boundary, incoming_front, shore_foam_width, shore_coordinate.y
		) * incoming_active;
		float reflection_phase = clamp((cycle - 0.46) / 0.54, 0.0, 1.0);
		float reflected_front = reflection_phase * shore_reflection_distance;
		float reflected = coherent_shore_line(
			distance_to_boundary, reflected_front, shore_foam_width * 0.82, shore_coordinate.y
		);
		reflected *= smoothstep(0.46, 0.50, cycle)
			* (1.0 - smoothstep(0.82, 1.0, reflection_phase));
		reflected *= exp(-distance_to_boundary * 0.72) * shore_reflection_strength;
		float contact = (1.0 - smoothstep(0.0, shore_foam_width * 1.35, distance_to_boundary))
			* (1.0 - smoothstep(0.44, 0.57, abs(cycle - 0.46)));
		float break_gain = smoothstep(0.12, 0.46, cycle);
		float beach_break = incoming * beach_mask * mix(0.52, 1.0, break_gain);
		// A hard wall keeps a thin contact edge, flashes at impact and sends a
		// narrower crest back into the basin. The soft beach does not mirror it.
		float impact = contact * (1.0 - smoothstep(0.035, 0.13, abs(cycle - 0.46)));
		float wall_response = max(incoming * 0.50, max(impact, reflected * 1.45)) * wall_mask;
		float connected_variation = 0.72 + 0.28 * (sin(shore_coordinate.y * 0.73 + 0.6) * 0.5 + 0.5);
		shore_light = clamp(max(beach_break, wall_response) * shore_effect_strength * connected_variation, 0.0, 1.0);
		float dark_front = max(
			incoming_front + shore_foam_width * 1.8,
			reflected_front + shore_foam_width * 2.1
		);
		shore_dark = coherent_shore_line(
			distance_to_boundary, dark_front, shore_foam_width * 2.4, shore_coordinate.y
		);
		shore_dark *= max(incoming_active * 0.55, reflected * 0.75)
			* shore_effect_strength * mix(0.45, 0.72, wall_mask);
	}
	vec3 depth_color = mix(water_light_tone, water_deep_tone, depth_band);
	vec3 tone_color = mix(depth_color, water_light_tone, tone * 0.42);
	vec3 water_body = mix(depth_color, water_tint, tint_strength);
	water_body = mix(water_body, tone_color, tone_strength * patch_strength);
	water_body = mix(water_body, water_light_tone, tone * 0.24 * patch_strength);
	if (!background_water) { water_body = mix(water_body, COLOR.rgb, palette_strength); }
	float wave_shadow_band = 0.0;
	float wave_crest_band = 0.0;
	if (layered_water_mix > 0.0 && surface_world_normal.y > 0.5) {
		// The reference reads through broad value masses first: dark troughs,
		// turquoise body and a lighter upper face. Transitions stay continuous;
		// final pixel treatment can be layered on after the water reads in motion.
		wave_shadow_band = 1.0 - smoothstep(-0.58, -0.10, layered_wave_height);
		wave_crest_band = smoothstep(0.12, 0.68, layered_wave_height);
		water_body = mix(water_body, wave_shadow_tone,
			wave_shadow_band * wave_band_strength * layered_water_mix);
		water_body = mix(water_body, wave_crest_tone,
			wave_crest_band * wave_band_strength * 0.52 * layered_water_mix);
	}
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
	ALBEDO = mix(ALBEDO, water_deep_tone, shore_dark * 0.34);
	ALBEDO = mix(ALBEDO, ripple_color, shore_light * 0.66);
	if (underwater_light_mix > 0.0 && surface_world_normal.y > 0.5) {
		vec2 refracted_uv = SCREEN_UV + NORMAL.xy * underwater_refraction_strength;
		vec2 screen_pixel = max(vec2(underwater_pixel_size), vec2(1.0));
		refracted_uv = (floor(refracted_uv * VIEWPORT_SIZE / screen_pixel) + vec2(0.5))
			* screen_pixel / VIEWPORT_SIZE;
		float raw_depth = textureLod(underwater_depth, refracted_uv, 0.0).r;
		vec4 reconstructed = INV_PROJECTION_MATRIX * vec4(refracted_uv * 2.0 - 1.0, raw_depth, 1.0);
		vec3 bottom_view = reconstructed.xyz / max(reconstructed.w, 0.00001);
		vec3 bottom_world = (INV_VIEW_MATRIX * vec4(bottom_view, 1.0)).xyz;
		vec3 surface_world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float visible_depth = max(surface_world.y - bottom_world.y, 0.0);
		float shallow_visibility = 1.0 - smoothstep(0.15, underwater_depth_range, visible_depth);
		vec3 bottom_sample = textureLod(underwater_screen, refracted_uv, 0.0).rgb;
		vec2 second_coordinate = vec2(-bottom_world.z, bottom_world.x) * 0.78 + vec2(11.0, 7.0);
		float caustic_a = flowing_ripple_network(bottom_world.xz * 0.92, continuous_slope, seconds * 0.83);
		float caustic_b = flowing_ripple_network(second_coordinate, -continuous_slope, seconds * -0.61);
		float caustic = clamp(caustic_a * 0.82 + caustic_b * 0.24, 0.0, 1.0);
		float wave_caustic = shared_wave_caustic(
			bottom_world.xz, seconds, surface_shore_distance_value, surface_shore_depth_value,
			surface_shore_inward, surface_shore_wall_value
		);
		caustic = mix(caustic, wave_caustic, underwater_caustic_wave_link);
		float bottom_luminance = dot(bottom_sample, vec3(0.2126, 0.7152, 0.0722));
		float light_visibility = smoothstep(0.10, 0.58, bottom_luminance);
		// The opaque bottom is already visible through normal alpha blending.
		// Add only the focused light pattern here; mixing the whole screen sample
		// back into ALBEDO would tint the complete water body a second time.
		float bottom_light = caustic * underwater_caustic_strength
			* shallow_visibility * light_visibility * underwater_light_mix;
		ALBEDO += underwater_caustic_color * bottom_light;
	}
	ROUGHNESS = clamp(surface_roughness + (1.0 - wave_visibility) * 0.08, 0.12, 1.0);
	METALLIC = 0.0;
	SPECULAR = highlight_strength;
	EMISSION = water_body * body_emission;
	float body_alpha = (
		mix(shallow_opacity, deep_opacity, depth_band)
		+ tone * tone_alpha
		+ depth_band * depth_alpha
		+ reflection * reflection_alpha
		+ wave_shadow_band * layered_water_mix * 0.10
	);
	ALPHA = clamp(
		background_water ? 1.0 : body_alpha + glint * glint_alpha + shore_light * 0.08,
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
	vec3 body_light_normal = normalize(mix(body_normal, NORMAL, layered_water_mix * 0.62));
	float warm = smoothstep(0.015, 0.13, (LIGHT_COLOR.r - LIGHT_COLOR.b) / max(max(LIGHT_COLOR.r, LIGHT_COLOR.g), max(LIGHT_COLOR.b, 0.001)));
	float light_attenuation = ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL && stylized_shadow_mix > 0.0) {
		// LIGHT_VERTEX was snapped to a world-aligned water cell in fragment(),
		// so the renderer supplies one stable shadow sample per visible block.
		float shifted_attenuation = clamp(ATTENUATION + 0.5 - stylized_shadow_threshold, 0.0, 1.0);
		float shadow_steps = max(stylized_shadow_steps, 1.0);
		float quantized_shadow = floor(shifted_attenuation * shadow_steps + 0.5) / shadow_steps;
		light_attenuation = mix(ATTENUATION, quantized_shadow, stylized_shadow_mix);
	}
	// Keep the accepted broad diffuse band independent of optical roughness.
	float stock = smoothstep(-0.94, 0.94, dot(body_light_normal, LIGHT));
	vec3 stock_diffuse = LIGHT_COLOR * light_attenuation * stock / 3.14159265;
	if (!LIGHT_IS_DIRECTIONAL || warm <= 0.001) {
		DIFFUSE_LIGHT += stock_diffuse;
	} else {
		// Stock water multiplies albedo in Godot's final compose. Do not square
		// its body palette by including albedo in custom irradiance as well.
		vec3 styled = ember_diorama_diffuse(vec3(1.0), body_light_normal, LIGHT, LIGHT_COLOR,
			light_attenuation, true, 4.0, 0.19, 1.0) / 3.14159265;
		DIFFUSE_LIGHT += mix(stock_diffuse, styled, warm);
	}
	float highlight_cell_size = max(pixel_highlight_cell_size, 0.03125);
	vec2 highlight_cell_center = (floor(surface_coordinate / highlight_cell_size) + vec2(0.5)) * highlight_cell_size;
	float highlight_seconds = preview_time >= 0.0 ? preview_time : TIME;
	vec3 specular_normal = NORMAL;
	if (pixel_highlight_mix > 0.0 && surface_world_normal.y > 0.5) {
		vec2 smooth_coordinate = surface_coordinate + highlight_edge_offset(surface_coordinate, highlight_seconds);
		vec2 highlight_coordinate = mix(highlight_cell_center, smooth_coordinate, pixel_highlight_smooth_motion);
		float highlight_wave_seconds = highlight_seconds * mix(1.0, pixel_highlight_travel_speed, pixel_highlight_smooth_motion);
		vec2 highlight_slope = optical_wave_slope(
			highlight_coordinate, highlight_wave_seconds, surface_shore_distance_value, surface_shore_depth_value,
			surface_shore_inward, surface_shore_wall_value
		) * wave_strength;
		specular_normal = normalize((VIEW_MATRIX * vec4(normalize(vec3(-highlight_slope.x, 1.0, -highlight_slope.y)), 0.0)).xyz);
	}
	float ndotl = max(dot(specular_normal, LIGHT), 0.0);
	float ndotv = max(dot(specular_normal, VIEW), 0.0001);
	vec3 sum_direction = LIGHT + VIEW;
	vec3 half_vector = sum_direction / max(length(sum_direction), 0.0001);
	float ndoth = clamp(dot(specular_normal, half_vector), 0.0, 1.0);
	float alpha = max(ROUGHNESS * ROUGHNESS, 0.002);
	float denominator = 1.0 - ndoth * ndoth + ndoth * ndoth * alpha * alpha;
	float distribution = alpha * alpha / max(3.14159265 * denominator * denominator, 0.00000001);
	float visibility = 0.5 / max(mix(2.0 * ndotl * ndotv, ndotl + ndotv, alpha), 0.0001);
	float f0 = 0.16 * highlight_strength * highlight_strength;
	float fresnel = f0 + (1.0 - f0) * pow(1.0 - max(dot(VIEW, half_vector), 0.0), 5.0);
	float smooth_highlight = distribution * visibility * fresnel * ndotl;
	if (layered_water_mix > 0.0) {
		// GGX can exceed display white around the exact mirror direction. Compress
		// that broad energy so only the separate glitter core reaches pure white.
		float compressed_highlight = smooth_highlight / (1.0 + smooth_highlight);
		smooth_highlight = mix(smooth_highlight, compressed_highlight * 0.52, layered_water_mix);
	}
	float direct_highlight = smooth_highlight;
	if (pixel_highlight_mix > 0.0 && surface_world_normal.y > 0.5) {
		// A stylized sun-crest mask stays anchored when the camera orbits. The
		// physical half-vector can be blended back for view-dependent sparkle.
		float flat_ndotl = max(dot(body_normal, LIGHT), 0.0);
		float sun_crest = 0.5 + (ndotl - flat_ndotl) / max(wave_strength * 0.45, 0.01);
		float highlight_alignment = ndoth;
		if (pixel_highlight_view_dependence < 1.0) {
			highlight_alignment = mix(sun_crest, ndoth, pixel_highlight_view_dependence);
		}
		// Whole cells switch between two clean light levels. No per-cell hash:
		// random holes made the previous highlight read as dirty noise.
		float halo = step(pixel_highlight_threshold, highlight_alignment);
		float core = step(pixel_highlight_core, highlight_alignment);
		float highlight_facing = ndotl;
		if (pixel_highlight_cohesion > 0.0) {
			// Advect large connected shapes and quantize only their contour.
			vec2 flow_direction = pixel_highlight_flow_direction / max(length(pixel_highlight_flow_direction), 0.0001);
			vec2 advected_center = highlight_cell_center - flow_direction * highlight_seconds * pixel_highlight_flow_speed;
			float shape = connected_highlight_field(advected_center, flow_direction);
			float shape_halo = step(pixel_highlight_shape_threshold, shape);
			float shape_core = step(pixel_highlight_shape_threshold + 0.13, shape);
			halo = mix(halo, shape_halo, pixel_highlight_cohesion);
			core = mix(core, shape_core, pixel_highlight_cohesion);
			highlight_facing = mix(ndotl, max(dot(body_normal, LIGHT), 0.0), pixel_highlight_cohesion);
		}
		float stepped_highlight = (halo * 0.34 + core * 0.66)
			* pixel_highlight_strength * highlight_strength * 1.6 * highlight_facing;
		direct_highlight = mix(smooth_highlight, stepped_highlight, pixel_highlight_mix);
	}
	vec3 direct_highlight_color = mix(LIGHT_COLOR, pixel_highlight_color, pixel_highlight_mix);
	SPECULAR_LIGHT += direct_highlight_color * light_attenuation * SPECULAR_AMOUNT * direct_highlight;
	if (layered_water_mix > 0.0 && surface_world_normal.y > 0.5) {
		vec3 layered_wave = surface_wave_state(
			surface_coordinate, highlight_seconds, surface_shore_distance_value, surface_shore_depth_value,
			surface_shore_inward, surface_shore_wall_value
		);
		float upper_face = smoothstep(0.18, 0.48, layered_wave.z)
			* (1.0 - smoothstep(0.60, 0.86, layered_wave.z));
		float light_gain = dot(specular_normal, LIGHT) - dot(body_normal, LIGHT);
		float lit_crest = upper_face * smoothstep(-0.015, surface_crest_width, light_gain);
		SPECULAR_LIGHT += pixel_highlight_color * light_attenuation * SPECULAR_AMOUNT
			* lit_crest * surface_crest_strength * layered_water_mix;
		// Sharp flashes remain inside the real half-vector response. A broad
		// coherent gate removes the uniform carpet without per-cell random dirt.
		float glitter_gate = smoothstep(0.60, 0.74,
			broad_value_noise(surface_coordinate * 0.34 + vec2(2.3, 8.7)));
		float glitter_core = smoothstep(sun_glitter_threshold,
			min(sun_glitter_threshold + 0.0025, 0.9999), ndoth);
		float glitter = glitter_core * glitter_gate;
		SPECULAR_LIGHT += pixel_highlight_color * LIGHT_COLOR * light_attenuation * SPECULAR_AMOUNT
			* glitter * sun_glitter_strength * layered_water_mix;
	}
}
