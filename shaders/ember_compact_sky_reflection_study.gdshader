shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// Minimal depth-and-swell study. The existing terrain Resource owns the floor;
// the opt-in refined water mesh supplies depth in vertex alpha (voxels / 64).
uniform vec3 shallow_color : source_color = vec3(0.12, 0.72, 0.78);
uniform vec3 deep_color : source_color = vec3(0.025, 0.34, 0.66);
uniform vec3 absorption_per_block = vec3(1.55, 0.75, 0.32);
uniform float deep_start_blocks : hint_range(0.0, 4.0) = 0.20;
uniform float deep_end_blocks : hint_range(0.1, 4.0) = 2.35;
uniform float wave_height_voxels : hint_range(0.0, 4.0) = 1.25;
uniform float wave_speed : hint_range(0.0, 2.0) = 0.42;
uniform float refraction_strength : hint_range(0.0, 0.04) = 0.018;
uniform float wave_irregularity : hint_range(0.0, 1.0) = 0.85;
uniform float local_bob_strength : hint_range(0.0, 0.5) = 0.24;
uniform float sky_reflection_strength : hint_range(0.0, 1.0) = 0.55;
uniform float sky_reflection_roughness : hint_range(0.0, 1.0) = 0.19;
uniform float sky_normal_strength : hint_range(0.0, 1.0) = 0.36;
uniform sampler2D planar_reflection : repeat_disable, filter_linear;
uniform sampler2D floor_refraction : repeat_disable, filter_linear;
uniform float floor_camera_available = 0.0;
uniform float planar_reflection_mix : hint_range(0.0, 1.0) = 0.0;
uniform float planar_reflection_distortion : hint_range(0.0, 0.02) = 0.002;
uniform mat4 reflection_view_projection;
uniform float planar_fresnel_power : hint_range(1.0, 8.0) = 3.0;
uniform float water_level_world = 16.02;
uniform float water_level_offset_voxels = 0.0;
uniform float preview_time = -1.0;
uniform sampler2D water_flow_map : repeat_disable, filter_linear;
uniform sampler2D river_phase_map : repeat_disable, filter_linear;
uniform vec2 flow_map_extent_blocks = vec2(48.0, 48.0);
uniform sampler2D terrain_height_map : repeat_disable, filter_nearest;
uniform sampler2D shore_distance_map : repeat_disable, filter_linear;
uniform float shore_field_available = 0.0;
uniform float shore_foam_strength : hint_range(0.0, 1.0) = 0.0;
uniform float shore_foam_width_voxels : hint_range(0.4, 8.0) = 1.8;
uniform float shore_foam_sharpness : hint_range(0.0, 1.0) = 0.7;
uniform float shore_foam_motion_voxels : hint_range(0.0, 4.0) = 1.25;
uniform float river_crest_whiteness : hint_range(0.0, 1.0) = 0.10;
uniform sampler2D object_contact_distance_map : repeat_disable, filter_linear;
uniform float object_contact_available = 0.0;
uniform float object_foam_strength : hint_range(0.0, 1.0) = 0.50;
uniform float object_foam_width_voxels = 0.55;
uniform float object_foam_sharpness = 0.92;
uniform float river_wave_spacing_blocks = 8.0;
uniform float river_arc_opening = 0.65;
uniform float river_crest_width_voxels = 0.75;
uniform float river_crest_sharpness = 1.0;
uniform float river_foam_variation = 0.45;
uniform float water_glint_strength = 0.32;
// Camera distance is measured in authoring metres (16 compact cells = 1 m).
// Only optical microdetail changes; displacement and field history stay shared.
uniform float water_detail_begin_m = 40.0;
uniform float water_detail_end_m = 100.0;
uniform sampler2D ripple_cell_field : filter_linear_mipmap, repeat_enable;
uniform float ripple_field_available = 0.0;
uniform float ripple_cell_scale = 1.1;
uniform float ripple_morph_strength = 0.75;
uniform float ripple_morph_speed = 0.6;
uniform float foam_trail_strength = 0.38;
uniform float foam_trail_lifetime = 2.2;
uniform float shore_foam_breakup = 0.40;
uniform float foam_width_pulse = 0.45;
uniform vec4 object_shapes[8];
uniform vec2 object_shape_meta[8];
uniform int object_shape_count = 0;
uniform vec4 reaction_samples[12];
uniform vec4 reaction_details[12];
uniform int reaction_count = 0;
uniform float reaction_strength = 0.65;
uniform float reaction_spread_speed = 0.45;
uniform float reaction_opening = 0.70;
uniform float reaction_birth_seconds = 0.35;
uniform vec2 terrain_origin_xz = vec2(0.0);
uniform vec2 flow_origin_xz = vec2(0.0);
uniform ivec2 terrain_extent_cells = ivec2(1);
uniform float river_flow_enabled = 0.0;
uniform float river_flow_speed : hint_range(0.0, 3.0) = 1.1;
uniform float river_wave_mix : hint_range(0.0, 1.0) = 0.8;
uniform sampler2D floor_screen : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;

varying vec2 water_point;
varying vec3 water_world_position;
varying vec2 swash_cell_point;
uniform float sea_swash_strength = 0.0;
uniform float sea_swash_time = 0.0;
uniform float sea_swash_period = 9.0;
uniform float sea_foam_strength = 1.0;
uniform float sea_foam_trail_strength = 0.38;
uniform float sea_foam_trail_lifetime = 2.2;
uniform sampler2D sea_foam_age : filter_linear, repeat_disable;
#include "res://shaders/ember_compact_sea_swash.gdshaderinc"
#include "res://shaders/ember_compact_waterfall.gdshaderinc"


#include "res://shaders/ember_compact_study_wave.gdshaderinc"
#include "res://shaders/ember_compact_wave_obstacles.gdshaderinc"

vec2 study_flow(vec2 point) {
	vec2 local = point - flow_origin_xz / 16.0;
	return texture(water_flow_map, local / flow_map_extent_blocks).rg * 2.0 - 1.0;
}

float study_river_distance(vec2 point) {
	vec2 local = point - flow_origin_xz / 16.0;
	return texture(river_phase_map, local / flow_map_extent_blocks).r;
}

float study_river_phase(vec2 point, float seconds) {
	vec2 local = point - flow_origin_xz / 16.0;
	vec2 channel = texture(river_phase_map, local / flow_map_extent_blocks).rg;
	// A rounded front across the channel. Bounded curvature uses the same
	// derived centerline at both banks, independent of local flow speed.
	float radius = mix(0.30, 3.0, river_arc_opening);
	float bow = (sqrt(channel.y * channel.y + radius * radius) - radius) * 1.35;
	float frequency = 6.2831853 / max(river_wave_spacing_blocks, 3.0);
	return (channel.x + bow) * frequency + sin(channel.x * 0.43 + seconds * 0.13) * 0.12
		- seconds * (wave_speed * 0.65 + river_flow_speed * 0.92);
}

float study_foam_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

float study_foam_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 weight = fract(point);
	weight = weight * weight * (3.0 - 2.0 * weight);
	return mix(mix(study_foam_hash(cell), study_foam_hash(cell + vec2(1.0, 0.0)), weight.x),
		mix(study_foam_hash(cell + vec2(0.0, 1.0)), study_foam_hash(cell + vec2(1.0, 1.0)), weight.x), weight.y);
}

vec3 study_waterfall_threads(float lateral, float phase) {
	// One direction-aligned pattern crosses the lip onto the falling sheet.
	float grain = study_foam_noise(vec2(lateral * 0.82 + sin(phase * 0.45) * 0.25, phase * 0.55));
	float breaks = study_foam_noise(vec2(lateral * 0.31 + 13.7, phase * 2.3));
	float ribbons = sin(lateral * 0.7 + sin(phase * 0.75) * 0.3) * 0.08;
	return vec3(grain, breaks, ribbons);
}

vec2 study_foam_drift(vec2 point, float seconds) {
	// Two bounded flow-map phases avoid stretched noise and visible resets.
	vec2 flow = river_flow_enabled > 0.5 ? study_flow(point) : vec2(0.16, 0.09);
	float cycle = seconds * (0.12 + river_flow_speed * 0.07);
	float a = fract(cycle);
	float b = fract(cycle + 0.5);
	float weight = abs(a * 2.0 - 1.0);
	return vec2(study_foam_noise((point - flow * a * 1.2) * vec2(2.3, 3.1)),
		study_foam_noise((point - flow * b * 1.2) * vec2(2.3, 3.1) + vec2(11.7, 4.3)))
		* vec2(1.0 - weight, weight);
}

float study_surface_grain(vec2 point, float seconds) {
	vec2 drift = study_foam_drift(point, seconds);
	return drift.x + drift.y;
}

vec2 study_ripple_slope(vec2 point, float seconds) {
	if (ripple_field_available > 0.5) {
		float time = seconds * ripple_morph_speed;
		vec2 k_a = vec2(0.61, 0.37);
		vec2 k_b = vec2(-0.29, 0.73);
		float a = dot(point, k_a) + time * 0.29;
		float b = dot(point, k_b) - time * 0.23;
		float size = 1.8 / max(ripple_cell_scale, 0.4);
		float warp = ripple_morph_strength * 0.75;
		vec2 local = point * size + vec2(sin(a), sin(b)) * warp;
		vec2 field = texture(ripple_cell_field, local / 12.0).rg;
		// Chain rule keeps the normals attached to the breathing cell pattern.
		vec2 slope = field * size + (field.x * cos(a) * k_a + field.y * cos(b) * k_b) * warp;
		vec2 secondary = texture(ripple_cell_field,
			(vec2(-local.y, local.x) * 0.73 + vec2(time * 0.11, -time * 0.08) * ripple_morph_strength + vec2(4.7, 2.3)) / 12.0).rg;
		float blend = (0.12 + (sin(time * 0.19 + dot(point, vec2(0.13, -0.17))) * 0.5 + 0.5) * 0.22) * ripple_morph_strength;
		return (slope * (1.0 - blend) + vec2(secondary.y, -secondary.x) * size * blend) * 3.0;
	}
	// Oblique, smoothly bent waves have no Cartesian noise-cell boundaries.
	// Foam keeps its own grain; differentiating that value noise exposed its
	// square cells in a sharp sun reflection even on a perfectly flat mesh.
	vec2 bend_a = vec2(0.37, 0.63);
	vec2 bend_b = vec2(-0.58, 0.29);
	float a = dot(point, bend_a) + seconds * 0.13;
	float b = dot(point, bend_b) - seconds * 0.11;
	float bend = sin(a) * 0.51 + sin(b) * 0.34;
	vec2 gradient = cos(a) * bend_a * 0.51 + cos(b) * bend_b * 0.34;
	vec2 k_a = vec2(8.21, 4.59);
	vec2 k_b = vec2(-5.72, 11.22);
	vec2 k_c = vec2(12.34, -7.27);
	return cos(dot(point, k_a) + bend) * (k_a + gradient) * 0.10
		+ cos(dot(point, k_b) - bend * 0.71 + 1.7) * (k_b - gradient * 0.71) * 0.07
		+ cos(dot(point, k_c) + bend * 0.43 + 0.8) * (k_c + gradient * 0.43) * 0.035;
}

vec2 study_fine_slope(vec2 point, float seconds) {
	vec2 flow = river_flow_enabled > 0.5 ? study_flow(point) : vec2(0.0);
	flow = mix(vec2(0.16, 0.09), flow, smoothstep(0.015, 0.18, length(flow)));
	float cycle = seconds * 0.18;
	float a = fract(cycle);
	float b = fract(cycle + 0.5);
	float weight = abs(a * 2.0 - 1.0);
	return mix(study_ripple_slope(point - flow * a * 1.2, seconds),
		study_ripple_slope(point - flow * b * 1.2, seconds), weight);
}

vec4 study_coastal_normal_sample(ivec2 cell) {
	if (any(lessThan(cell, ivec2(0))) || any(greaterThanEqual(cell, ivec2(sea_swash_extent)))) {
		return vec4(0.0);
	}
	return texelFetch(sea_swash_state, cell, 0);
}

vec2 study_coastal_slope(vec2 point) {
	// Differentiate the same bilinear surface, excluding uncovered/missing
	// cells. Zero in the sparse field is absence of water, not a height-zero
	// water cliff at the river guard, film edge or field boundary.
	vec2 local = point - sea_swash_origin - vec2(0.5);
	ivec2 cell = ivec2(floor(local));
	vec2 weight = fract(local);
	vec4 a = study_coastal_normal_sample(cell);
	vec4 b = study_coastal_normal_sample(cell + ivec2(1, 0));
	vec4 c = study_coastal_normal_sample(cell + ivec2(0, 1));
	vec4 d = study_coastal_normal_sample(cell + ivec2(1, 1));
	float reference = coastal_state(point).r;
	float h_a = a.a > 0.05 ? a.r : reference;
	float h_b = b.a > 0.05 ? b.r : reference;
	float h_c = c.a > 0.05 ? c.r : reference;
	float h_d = d.a > 0.05 ? d.r : reference;
	return vec2(mix(h_b - h_a, h_d - h_c, weight.y),
		mix(h_c - h_a, h_d - h_b, weight.x));
}

float study_shore_distance(vec2 point) {
	vec2 cells = point * 16.0 - terrain_origin_xz;
	vec2 uv = clamp((cells + 0.5) / vec2(terrain_extent_cells), vec2(0.0), vec2(1.0));
	return texture(shore_distance_map, uv).r * (255.0 / 3.0);
}

float study_foam_web(vec2 point) {
	// Jittered cells plus a smooth warp make connected, curved foam threads.
	// No regular grid, and no independently travelling train of white lines.
	vec2 warp = vec2(study_foam_noise(point * 0.65),
		study_foam_noise(point * 0.65 + vec2(7.3, 2.1))) - vec2(0.5);
	point += warp * 0.85;
	vec2 cell = floor(point);
	vec2 local = fract(point);
	float first = 10.0;
	float second = 10.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 seed = cell + offset;
			vec2 jitter = vec2(study_foam_hash(seed), study_foam_hash(seed + vec2(19.3, 3.7)));
			float distance = length(offset + vec2(0.15) + jitter * 0.70 - local);
			if (distance < first) { second = first; first = distance; }
			else { second = min(second, distance); }
		}
	}
	float edge = second - first;
	float width = mix(0.025, 0.055, study_foam_noise(point * 1.4 + vec2(3.1, 8.7)));
	float feather = max(fwidth(edge) * 0.7, 0.009);
	return 1.0 - smoothstep(width, width + feather, edge);
}

float study_foam_trail_pattern(vec2 texture_point, float age, float lifetime) {
	float life = 1.0 - smoothstep(lifetime * 0.20, lifetime, age);
	float islands = study_foam_noise(texture_point * 0.65 + vec2(5.7, 12.1));
	float dissolve = smoothstep(0.18 + (1.0 - life) * 0.46, 0.78, islands);
	return study_foam_web(texture_point) * life
		* mix(1.0, dissolve, smoothstep(0.0, lifetime * 0.6, age));
}

float study_sea_foam_trails(vec2 point) {
	if (sea_foam_trail_strength <= 0.001 || sea_swash_strength <= 0.001 || sea_swash_available < 0.5) { return 0.0; }
	vec2 cells = point * 16.0;
	vec4 coast = coastal_info(cells);
	if (coast.a < 0.5 || coastal_state(cells).a <= 0.05) { return 0.0; }
	float age = texture(sea_foam_age, (cells - sea_swash_origin) / sea_swash_extent).r;
	float lifetime = min(max(sea_foam_trail_lifetime, 0.3), sea_swash_period * 0.75);
	if (age >= lifetime) { return 0.0; }
	// Same irregular connected web as the river, with restrained sea drift.
	vec2 texture_point = point * vec2(3.3, 2.7);
	texture_point += vec2(sin(sea_swash_time * 0.23 + point.y * 0.7),
		cos(sea_swash_time * 0.19 + point.x * 0.6)) * 0.13;
	float attachment = mix(1.0, 0.72, smoothstep(0.0, lifetime, age));
	// Threads emerge gradually behind the foam line, instead of switching
	// an entire cell to full white at the first age-map write.
	float birth = smoothstep(0.0, min(0.25, lifetime * 0.2), age);
	return study_foam_trail_pattern(texture_point, age, lifetime) * attachment * birth * sea_foam_trail_strength;
}

float study_foam_trails(vec2 point, float seconds) {
	if (foam_trail_strength <= 0.001 || river_flow_enabled < 0.5 || river_flow_speed <= 0.001) { return 0.0; }
	float speed = length(study_flow(point));
	if (speed < 0.005) { return 0.0; }
	float phase = study_river_phase(point, seconds);
	float clock = wave_speed * 0.65 + river_flow_speed * 0.92;
	// Time since the last crest passed this point. Foam is born behind that
	// crest, rather than becoming a second independently moving wave train.
	float age = mod(1.5707963 - phase, 6.2831853) / max(clock, 0.001);
	float lifetime = min(max(foam_trail_lifetime, 0.3), 6.2831853 / clock * 0.90);
	// Threads reach the crest itself, then dissolve into separate fading pieces.
	vec2 channel = texture(river_phase_map,
		(point - flow_origin_xz / 16.0) / flow_map_extent_blocks).rg;
	float drift = seconds * clock * max(river_wave_spacing_blocks, 3.0) / 6.2831853 * 0.20;
	vec2 texture_point = vec2((channel.x - drift) * 1.6, channel.y * 3.4);
	texture_point += vec2(sin(seconds * 0.29 + channel.y * 2.3),
		cos(seconds * 0.23 + channel.x * 0.6)) * 0.10;
	float shore_distance = shore_field_available > 0.5 ? study_shore_distance(point) : 40.0;
	float river_source = river_crest_whiteness * river_wave_mix * smoothstep(2.0, 7.0, shore_distance);
	float shore_source = shore_foam_strength * 0.55 * smoothstep(1.0, 3.0, shore_distance)
		* (1.0 - smoothstep(6.0 + shore_foam_width_voxels, 14.0 + shore_foam_width_voxels, shore_distance));
	return study_foam_trail_pattern(texture_point, age, lifetime) * max(river_source, shore_source) * foam_trail_strength;
}

vec2 study_reaction(vec2 point, float pixel_width) {
	// Expanding rear-facing arcs, emitted by the existing contact motion
	// history. x is a broad height pulse; y is the narrow white line.
	vec2 result = vec2(0.0);
	if (reaction_strength <= 0.001) { return result; }
	for (int i = 0; i < 12; i++) {
		if (i >= reaction_count) { break; }
		vec4 sample = reaction_samples[i];
		vec4 detail = reaction_details[i];
		vec2 relative = point - sample.xy;
		float distance = length(relative);
		vec2 direction = relative / max(distance, 0.001);
		float rear = -dot(direction, detail.xy);
		float sector = smoothstep(mix(0.65, -0.05, reaction_opening),
			mix(0.85, 0.20, reaction_opening), rear);
		float radius = detail.w * 0.75 + sample.z * reaction_spread_speed;
		float offset = distance - radius;
		float birth = smoothstep(0.0, max(reaction_birth_seconds, 0.05), sample.z);
		float life = birth * detail.z * detail.z * sample.w * sector * reaction_strength;
		float pulse = exp(-offset * offset / 0.045) * life;
		float line_width = river_crest_width_voxels / 32.0;
		float feather = max(pixel_width, 0.003);
		float line = (1.0 - smoothstep(line_width, line_width + feather, abs(offset))) * life;
		result += vec2(pulse * 0.23, line);
	}
	return result;
}

vec3 study_river_wave(vec2 point, float seconds, float river_detail) {
	// Distance is integrated along the channel once, not obtained by rotating
	// the whole world at every texel. Speed changes the clock uniformly so the
	// slow banks cannot accumulate a comb of phase-compressed crests.
	float epsilon = 0.0625;
	vec2 gradient = vec2(
		study_river_phase(point + vec2(epsilon, 0.0), seconds) - study_river_phase(point - vec2(epsilon, 0.0), seconds),
		study_river_phase(point + vec2(0.0, epsilon), seconds) - study_river_phase(point - vec2(0.0, epsilon), seconds)) / (2.0 * epsilon);
	float phase = study_river_phase(point, seconds);
	float height = sin(phase) * 0.58;
	vec2 slope = cos(phase) * gradient * 0.58;
	// Short, bounded flow-map cycles carry optical ripples. Two offset phases
	// hide the reset without stretching the texture indefinitely (Valve 2010).
	vec2 velocity = study_flow(point);
	float cycle = seconds * (wave_speed * 0.4 + river_flow_speed * 0.35);
	float a = fract(cycle);
	float b = fract(cycle + 0.5);
	float weight = abs(a * 2.0 - 1.0);
	vec2 local_a = point - velocity * a * 0.65;
	vec2 local_b = point - velocity * b * 0.65 + vec2(2.17, 0.83);
	vec2 ripple_direction = vec2(2.71, 3.37);
	vec2 ripple_a = cos(dot(local_a, ripple_direction)) * ripple_direction;
	vec2 ripple_b = cos(dot(local_b, ripple_direction)) * ripple_direction;
	slope += mix(ripple_a, ripple_b, weight) * 0.035 * river_detail;
	return vec3(slope, height);
}

vec3 study_water_state_with_detail(vec2 point, float seconds, float river_detail) {
	vec3 open_water = wave_state(point, seconds);
	if (river_flow_enabled < 0.5) {
		return open_water;
	}
	vec2 velocity = study_flow(point);
	float speed = min(length(velocity), 1.0);
	if (speed < 0.005) {
		return open_water;
	}
	// A quiet bank is still river water. Do not reintroduce ocean interference
	// along both sides of the channel simply because its current is slower.
	float channel = smoothstep(0.015, 0.18, speed);
	return mix(open_water, study_river_wave(point, seconds, river_detail) * river_wave_mix, channel);
}

vec3 study_reaction_state(vec2 point) {
	if (reaction_count == 0 || reaction_strength <= 0.001) { return vec3(0.0); }
	float epsilon = 0.0625;
	vec2 gradient = vec2(study_reaction(point + vec2(epsilon, 0.0), 0.0).x - study_reaction(point - vec2(epsilon, 0.0), 0.0).x,
		study_reaction(point + vec2(0.0, epsilon), 0.0).x - study_reaction(point - vec2(0.0, epsilon), 0.0).x) / (2.0 * epsilon);
	return vec3(gradient, study_reaction(point, 0.0).x);
}

vec3 study_water_state(vec2 point, float seconds) {
	return study_water_state_with_detail(point, seconds, 1.0) + study_reaction_state(point);
}

float study_wave_amplitude(float depth_voxels, vec2 point) {
	// A full-height crest cannot fit in a one-voxel shelf. The same continuous
	// taper reaches both stitched surface vertices and the moving wall rim.
	float depth_limit = smoothstep(0.0, 12.0, depth_voxels);
	float bank_limit = shore_field_available > 0.5
		? smoothstep(0.25, 3.0, study_shore_distance(point)) : 1.0;
	return wave_height_voxels * depth_limit * bank_limit;
}

float study_foam_width_scale(vec2 point, float seconds, float wave_height) {
	if (foam_width_pulse == 0.0 || wave_height_voxels <= 0.0) { return 1.0; }
	float phase = seconds * 0.85 + study_foam_noise(point * 0.8) * 6.2831853;
	float breathing = sin(phase) * 0.40 + sin(phase * 0.63 + 1.7) * 0.18;
	breathing += clamp(wave_height, -1.0, 1.0) * 0.15;
	return 1.0 + breathing * foam_width_pulse * smoothstep(0.0, 0.5, wave_height_voxels);
}

float study_shore_foam(vec2 point, float seconds, float wave_height) {
	if (shore_field_available < 0.5 || shore_foam_strength <= 0.001) {
		return 0.0;
	}
	float distance_voxels = study_shore_distance(point);
	if (distance_voxels > 12.0 || distance_voxels < 0.3) {
		return 0.0;
	}
	// The wet bank is the fixed root. Only the outer edge breathes with the
	// arriving wave; narrowing the band must never open a gap at the bank.
	float wave_active = smoothstep(0.0, 0.5, wave_height_voxels);
	float root = 0.3;
	float width = clamp(shore_foam_width_voxels * study_foam_width_scale(point, seconds, wave_height)
		+ clamp(wave_height, -1.0, 1.0) * shore_foam_motion_voxels * wave_active, 0.4, 11.0 - root);
	float feather = max(fwidth(distance_voxels) * 0.25,
		mix(0.85, 0.10, shore_foam_sharpness));
	float band = 1.0 - smoothstep(root + width - feather,
		root + width + feather, distance_voxels);
	float fragments = 0.84 + 0.16 * sin(point.x * 2.7 - point.y * 1.3
		+ wave_height * 3.2 * wave_active);
	float grain = study_surface_grain(point, seconds);
	fragments *= mix(1.0, smoothstep(0.25, 0.43, grain), smoothstep(0.0, 0.55, shore_foam_breakup));
	return clamp(band * fragments * shore_foam_strength, 0.0, 1.0);
}

float study_object_distance(vec2 point) {
	float closest = 1000.0;
	for (int i = 0; i < 8; i++) {
		if (i >= object_shape_count) { break; }
		vec4 shape = object_shapes[i];
		vec2 local = point - shape.xy;
		vec2 meta = object_shape_meta[i];
		float distance;
		if (meta.x > 0.5) {
			distance = length(local) - shape.z;
		} else {
			float c = cos(meta.y);
			float s = sin(meta.y);
			local = vec2(local.x * c + local.y * s, -local.x * s + local.y * c);
			vec2 outside = abs(local) - shape.zw;
			distance = length(max(outside, vec2(0.0))) + min(max(outside.x, outside.y), 0.0);
		}
		closest = min(closest, distance * 16.0);
	}
	return closest;
}

float study_object_foam(vec2 point, float seconds, float wave_height) {
	if (object_contact_available < 0.5 || object_foam_strength <= 0.001) {
		return 0.0;
	}
	float distance_voxels = study_object_distance(point);
	if (distance_voxels < 0.0 || distance_voxels > 8.0) {
		return 0.0;
	}
	float wave_active = smoothstep(0.0, 0.5, wave_height_voxels);
	float width = max(0.15, object_foam_width_voxels * study_foam_width_scale(point, seconds, wave_height));
	float feather = max(fwidth(distance_voxels) * 0.5,
		mix(0.5, 0.025, object_foam_sharpness));
	float band = 1.0 - smoothstep(max(0.0, width - feather), width + feather, distance_voxels);
	float arrival = mix(1.0, mix(0.62, 1.0,
		smoothstep(-0.4, 0.5, wave_height)), wave_active);
	return band * arrival * object_foam_strength;
}

void vertex() {
	water_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz / 16.0;
	swash_cell_point = (MODEL_MATRIX * vec4(UV.x, 0.0, -UV.y - 1.0, 1.0)).xz;
	float seconds = preview_time >= 0.0 ? preview_time : TIME;
	// Wall feet stay on the seabed while the rim moves with the top mesh.
	if (UV.x < -3.0) {
		float fall = clamp(UV.y, 0.0, 1.0);
		float across = -UV.x - 4.0;
		vec3 side = vec3(waterfall_direction.y, 0.0, -waterfall_direction.x);
		float travel = seconds * waterfall_speed;
		VERTEX.y += water_level_offset_voxels;
		float join = (1.0 - smoothstep(0.0, 0.18, fall)) + smoothstep(0.82, 1.0, fall);
		VERTEX.y += study_water_state_with_detail(water_point, seconds, 0.0).z
			* study_wave_amplitude(COLOR.a * 64.0, water_point) * join;
		VERTEX += side * sin(across * 17.0 + fall * 11.0 - travel * 2.1)
			* waterfall_irregularity * 0.32 * smoothstep(0.0, 0.12, fall);
	} else if (UV.y < 1.5) {
		VERTEX.y += water_level_offset_voxels;
		// The short river ripple stays in the optical normal. At the 8-voxel
		// surface spacing it is too short to displace the mesh cleanly.
		VERTEX.y += study_water_state_with_detail(water_point, seconds, 0.0).z
			* study_wave_amplitude(max(clamp(COLOR.a, 0.0, 1.0) * 64.0 + water_level_offset_voxels, 0.0), water_point);
		VERTEX.y += study_reaction(water_point, 0.0).x
			* study_wave_amplitude(max(clamp(COLOR.a, 0.0, 1.0) * 64.0 + water_level_offset_voxels, 0.0), water_point);
		vec2 sample_point = UV.y < -0.5 ? swash_cell_point : water_point * 16.0;
		vec4 coast = coastal_info(sample_point);
		vec4 state = coastal_state(sample_point);
		float influence = coast.a * (1.0 - smoothstep(15.0, 24.0, abs(coast.r)))
			* step(0.001, sea_swash_strength);
		if (UV.y < -0.5) {
			VERTEX.y = max(coastal_surface(water_point * 16.0), coast.g + 0.025);
		} else {
			VERTEX.y = mix(VERTEX.y, state.r, influence);
		}
		if (abs((MODEL_MATRIX * vec4(VERTEX, 1.0)).y - waterfall_source.w - water_level_offset_voxels) < 4.0) {
			VERTEX.y += waterfall_sample(water_point * 16.0).r;
		}
		if (UV.y >= -0.5) { VERTEX.y += obstacle_wave_sample(water_point * 16.0, seconds).r; }
	}
	water_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec2 coast_point = UV.y < -0.5 ? swash_cell_point : water_point * 16.0;
	vec4 coast = coastal_info(coast_point);
	vec4 swash = coastal_state(coast_point);
	if (UV.y < -0.5 && (coast.a < 0.5 || swash.a <= 0.05)) { discard; }
	if (UV.x < -3.0) {
		if (waterfall_available < 0.5 || waterfall_strength < 0.001) { discard; }
		float seconds = preview_time >= 0.0 ? preview_time : TIME;
		float across = -UV.x - 4.0;
		float fall = clamp(UV.y, 0.0, 1.0);
		float travel = seconds * waterfall_speed;
		float phase = sqrt(fall) * 11.0 - 0.3554 - travel * 1.9;
		// Long, interrupted threads travel down the sheet. A stretched grain
		// keeps the falling water distinct from the round foam cells in the pool.
		vec3 pattern = study_waterfall_threads(across * waterfall_width, phase);
		float grain = pattern.x;
		float breaks = pattern.y;
		float edge_cut = waterfall_irregularity * 0.035 * smoothstep(0.0, 0.15, fall) * grain;
		if (across < edge_cut || across > 1.0 - edge_cut) { discard; }
		float threads = smoothstep(0.56, 0.84, grain) * mix(0.24, 0.72, fall) * mix(0.45, 1.0, breaks);
		threads += smoothstep(0.78, 1.0, fall) * (0.12 + breaks * 0.16);
		float ribbons = pattern.z;
		vec3 body = shallow_color * (0.94 + ribbons) + vec3(0.015, 0.045, 0.06);
		// Dense falling water hides the upper river floor. ALPHA=1 alone did
		// not do this while the opaque screen pixel was composed into its colour.
		EMISSION = mix(body, vec3(0.70, 0.95, 1.0), threads);
		ALBEDO = vec3(0.0);
		vec3 normal_world = normalize(vec3(waterfall_direction.x, 0.12, waterfall_direction.y));
		NORMAL = normalize((VIEW_MATRIX * vec4(normal_world, 0.0)).xyz);
		ROUGHNESS = max(sky_reflection_roughness, 0.24);
		SPECULAR = sky_reflection_strength * 0.5;
		ALPHA = 1.0;
	} else if (UV.y > 0.5) {
		// Hide the inside wall face: it painted dark block-shaped rows over
		// the transparent surface when seen from the landward side.
		if (!FRONT_FACING) {
			discard;
		}
		float descent = clamp(UV.y - 1.0, 0.0, 1.0);
		float body_depth = clamp(COLOR.a, 0.0, 1.0) * 4.0;
		vec3 rim = mix(shallow_color, deep_color,
			smoothstep(deep_start_blocks, deep_end_blocks, body_depth));
		vec3 body = mix(rim * 0.96, deep_color * 0.57,
			smoothstep(0.0, 1.0, descent));
		EMISSION = body * 0.85;
		ALBEDO = body * 0.15;
		ROUGHNESS = 0.17;
		SPECULAR = 0.22;
		ALPHA = 1.0;
	} else if (!FRONT_FACING && CAMERA_POSITION_WORLD.y < water_world_position.y - 0.05) {
		// Only an underwater camera sees the underside. Above-water backfaces
		// of steep waves use the ordinary surface path below, avoiding gaps.
		// Looking up refracts the scene above through the very same moving
		// surface normal that distorts the floor when viewed from above.
		float seconds = preview_time >= 0.0 ? preview_time : TIME;
		vec2 slope = study_water_state(water_point, seconds).xy
			* (study_wave_amplitude(clamp(COLOR.a, 0.0, 1.0) * 64.0, water_point) / 16.0);
		vec3 water_normal = normalize(vec3(-slope.x, 1.0, -slope.y));
		vec3 underside_normal = normalize((VIEW_MATRIX * vec4(-water_normal, 0.0)).xyz);
		vec3 flat_underside = normalize((VIEW_MATRIX * vec4(vec3(0.0, -1.0, 0.0), 0.0)).xyz);
		vec2 sky_uv = clamp(SCREEN_UV + (underside_normal.xy - flat_underside.xy)
			* refraction_strength * 3.2, vec2(0.001), vec2(0.999));
		vec3 air_view = textureLod(floor_screen, sky_uv, 0.0).rgb;
		float facing = clamp(dot(underside_normal, VIEW), 0.0, 1.0);
		float inner_reflection = 0.08 + 0.75 * pow(1.0 - facing, 2.4);
		float sun_alignment = clamp(dot(water_normal, normalize(vec3(0.26, 0.85, -0.46))), 0.0, 1.0);
		vec3 transmitted = mix(air_view, shallow_color, 0.26)
			* (0.86 + 0.25 * sun_alignment);
		EMISSION = mix(transmitted, deep_color * 0.65, inner_reflection);
		ALBEDO = vec3(0.0);
		NORMAL = underside_normal;
		ROUGHNESS = 0.10;
		SPECULAR = 0.16;
		ALPHA = 1.0;
	} else {
	float seconds = preview_time >= 0.0 ? preview_time : TIME;
	float depth_blocks = max(clamp(COLOR.a, 0.0, 1.0) * 4.0 + water_level_offset_voxels / 16.0, 0.0);
	float detail_begin = max(water_detail_begin_m, 0.0);
	float detail_end = max(water_detail_end_m, detail_begin + 1.0);
	float camera_distance_m = distance(water_world_position, INV_VIEW_MATRIX[3].xyz) / 16.0;
	float detail_weight = 1.0 - smoothstep(detail_begin, detail_end, camera_distance_m);
	if (UV.y < -0.5) { depth_blocks = max((swash.r - coast.g) / 16.0, 0.0); }
	float depth_mix = smoothstep(deep_start_blocks, deep_end_blocks, depth_blocks);
	// A current changes the travelling waves, not the optical material. The
	// same sun/sky response continues through a river mouth into open water.
	float glint_strength = water_glint_strength;
	// Optical river detail only changes xy. The same base height supplies both
	// contact bands, without resampling the wave (or adding wake displacement).
	vec3 base_wave = study_water_state_with_detail(water_point, seconds, 1.0);
	vec2 slope = (base_wave + study_reaction_state(water_point)).xy
		* (study_wave_amplitude(depth_blocks * 16.0, water_point) / 16.0);
	float coastal_influence = coast.a * (1.0 - smoothstep(15.0, 24.0, abs(coast.r)))
		* step(0.001, sea_swash_strength);
	vec2 coastal_slope = coastal_influence > 0.001 ? study_coastal_slope(water_point * 16.0) : slope;
	slope = mix(slope, coastal_slope, coastal_influence);
	// Optical detail only; no extra vertex displacement or physical surface.
	if (detail_weight > 0.0 && glint_strength != 0.0) {
		slope += study_fine_slope(water_point, seconds) * glint_strength * 0.13
			* smoothstep(0.03, 0.35, depth_blocks) * detail_weight;
	}
	vec4 fall_state = abs(water_world_position.y - waterfall_source.w - water_level_offset_voxels) < 4.0
		? waterfall_sample(water_point * 16.0) : vec4(0.0);
	if (fall_state.a > 0.001) { slope += waterfall_slope(water_point * 16.0); }
	if (UV.y >= -0.5) { slope += obstacle_wave_slope(water_point * 16.0, seconds); }
	float inlet_weight = UV.y < -0.5 ? 0.0 : waterfall_approach_weight(water_world_position);
	vec3 inlet_pattern = vec3(0.0);
	if (inlet_weight > 0.001) {
		vec2 coordinates = waterfall_approach_coordinates(water_point * 16.0);
		inlet_pattern = study_waterfall_threads(coordinates.x, coordinates.y - seconds * waterfall_speed * 1.9);
		vec2 side = vec2(waterfall_direction.y, -waterfall_direction.x);
		slope += (side * (inlet_pattern.x - 0.5) * 0.07
			+ waterfall_direction * (inlet_pattern.y - 0.5) * 0.03) * inlet_weight;
	}
	vec3 water_normal = normalize(vec3(-slope.x * sky_normal_strength, 1.0, -slope.y * sky_normal_strength));
	vec3 view_normal = normalize((VIEW_MATRIX * vec4(water_normal, 0.0)).xyz);
	// The sampled seabed may be just one narrow terrace wide. Full screen-space
	// displacement there pulls dry bank pixels across the water. Keep the open
	// sea's accepted refraction, but taper it on shallows and flowing channels.
	float shallow_refraction = smoothstep(0.25, 1.25, depth_blocks);
	float river_speed = river_flow_enabled > 0.5
		? min(length(study_flow(water_point)), 1.0)
		: 0.0;
	float channel_refraction = mix(1.0, 0.38, smoothstep(0.04, 0.65, river_speed));
	vec2 floor_uv = clamp(SCREEN_UV + view_normal.xy * refraction_strength
		* shallow_refraction * channel_refraction, vec2(0.001), vec2(0.999));
	vec3 transmission = exp(-absorption_per_block * depth_blocks);
	vec3 water_color = mix(shallow_color, deep_color, depth_mix);
	// The separate camera provides a stable seabed at grazing angles.
	vec3 floor_color = water_color;
	if (floor_camera_available >= 0.5) {
		vec4 floor_sample = textureLod(floor_refraction, floor_uv, 0.0);
		floor_color = mix(water_color, floor_sample.rgb, floor_sample.a);
	}
	// The main opaque pass contains characters too. Reconstruct the sampled
	// point so only objects genuinely behind and below this water surface
	// can replace the floor; dry silhouettes cannot smear into the water.
	vec2 scene_uv = floor_camera_available > 0.5 ? floor_uv : SCREEN_UV;
	float sampled_depth = textureLod(scene_depth, scene_uv, 0.0).r;
	vec4 scene_h = INV_PROJECTION_MATRIX * vec4(scene_uv * 2.0 - 1.0, sampled_depth, 1.0);
	vec3 scene_view = scene_h.xyz / max(scene_h.w, 0.00001);
	vec3 scene_world = (INV_VIEW_MATRIX * vec4(scene_view, 1.0)).xyz;
	float water_view_z = (VIEW_MATRIX * vec4(water_world_position, 1.0)).z;
	bool behind_water = sampled_depth > 0.00001
		&& scene_view.z < water_view_z - 0.1
		&& scene_world.y < water_world_position.y - 0.05;
	if (floor_camera_available < 0.5) {
		// Native editor preview has no study camera. Read the opaque scene at
		// the exact water pixel so bank edges cannot be dragged into the river.
		floor_color = mix(water_color, textureLod(floor_screen, SCREEN_UV, 0.0).rgb,
			behind_water ? 1.0 : 0.0);
	} else {
		ivec2 terrain_cell = ivec2(floor(scene_world.xz - terrain_origin_xz));
		bool in_terrain = all(greaterThanEqual(terrain_cell, ivec2(0)))
			&& all(lessThan(terrain_cell, terrain_extent_cells));
		float terrain_height = in_terrain ? texelFetch(terrain_height_map, terrain_cell, 0).r : water_level_world;
		// At a grazing angle a voxel side can reconstruct a few world units
		// above its column. Only a raised object replaces the floor camera.
		bool submerged_object = behind_water && in_terrain
			&& scene_world.y > terrain_height + 5.0;
		floor_color = mix(floor_color, textureLod(floor_screen, floor_uv, 0.0).rgb,
			submerged_object ? 1.0 : 0.0);
	}
	vec3 transmitted_color = floor_color * transmission + water_color * (vec3(1.0) - transmission);
	if (UV.y < -0.5) {
		// The run-up covers dry sand above the refraction camera's mean-water clip.
		// Its opaque terrain pixel supplies the actual sand colour here.
		transmitted_color = textureLod(floor_screen, SCREEN_UV, 0.0).rgb * transmission
			+ water_color * (vec3(1.0) - transmission);
	}
	// Keep the accepted clear-water body. The reflection comes from Godot's
	// Sky radiance and an optional mirrored scene camera, never a glint mask.
	vec3 surface_color = transmitted_color;
	if (planar_reflection_mix > 0.0) {
		float facing = clamp(dot(view_normal, VIEW), 0.0, 1.0);
		float fresnel = 0.035 + 0.965 * pow(1.0 - facing, planar_fresnel_power);
		// Project the actual moving water point into the mirrored camera. Screen
		// coordinates alone slide shore objects across the water as the view moves.
		vec4 reflection_clip = reflection_view_projection * vec4(water_world_position, 1.0);
		vec2 mirror_uv = vec2(reflection_clip.x / max(reflection_clip.w, 0.001) * 0.5 + 0.5,
			0.5 - reflection_clip.y / max(reflection_clip.w, 0.001) * 0.5)
			+ slope * planar_reflection_distortion;
		float reflection_valid = reflection_clip.w > 0.0
			&& all(greaterThanEqual(mirror_uv, vec2(0.0)))
			&& all(lessThanEqual(mirror_uv, vec2(1.0))) ? 1.0 : 0.0;
		vec4 mirrored_scene = textureLod(planar_reflection, clamp(mirror_uv, vec2(0.0), vec2(1.0)), 0.0);
		surface_color = mix(transmitted_color, mirrored_scene.rgb,
			clamp(planar_reflection_mix * fresnel * reflection_valid * mirrored_scene.a, 0.0, 1.0));
	}
	float crest_footprint = shore_field_available > 0.5
		? smoothstep(1.0, 6.0, study_shore_distance(water_point)) : 1.0;
	float phase = study_river_phase(water_point, seconds);
	float crest_height = river_flow_enabled > 0.5 ? sin(phase) * 0.58 : 0.0;
	vec2 channel = texture(river_phase_map,
		(water_point - flow_origin_xz / 16.0) / flow_map_extent_blocks).rg;
	// Grain travels with a front's phase index, rather than sliding over the
	// water on a separate clock. It only shapes foam, never the coarse mesh.
	float front_index = floor(phase / 6.2831853);
	float grain = study_foam_noise(vec2(channel.y * 3.7, front_index * 1.73));
	float gaps = study_foam_noise(vec2(channel.y * 6.3 + 9.1, front_index * 2.31));
	float edge_shift = (grain - 0.5) * river_foam_variation * 1.25 / 16.0
		* 6.2831853 / max(river_wave_spacing_blocks, 3.0);
	float crest_distance = abs(mod(phase + edge_shift - 1.5707963 + 3.1415927, 6.2831853) - 3.1415927);
	float half_width = river_crest_width_voxels / 32.0 * 6.2831853 / max(river_wave_spacing_blocks, 3.0);
	half_width *= mix(1.0, 0.55 + grain * 1.1, river_foam_variation);
	float feather = max(fwidth(phase) * 0.5, 0.001);
	float crisp = 1.0 - smoothstep(half_width, half_width + feather, crest_distance);
	float fragments = mix(1.0, smoothstep(0.12, 0.36, gaps), smoothstep(0.0, 0.6, river_foam_variation));
	crisp *= fragments;
	float soft = smoothstep(0.28 - fwidth(crest_height),
		0.64 + fwidth(crest_height), crest_height)
		* smoothstep(0.005, 0.035, length(slope));
	float crest = mix(soft, crisp, river_crest_sharpness)
		* smoothstep(0.18, 0.60, river_speed) * crest_footprint * river_wave_mix
		* river_crest_whiteness * 0.55;
	vec4 obstacle = UV.y < -0.5 ? vec4(0.0) : obstacle_wave_sample(water_point * 16.0, seconds);
	// Crest/connected foam follow the simulated height and its history, not
	// the old front continuing straight through the obstacle.
	float obstacle_crest = 0.0;
	float obstacle_web = 0.0;
	float obstacle_sea_web = 0.0;
	float river_web = 0.0;
	float sea_web = 0.0;
	float coastal_weight = coast.a * (1.0 - smoothstep(15.0, 24.0, abs(coast.r))) * step(0.001, sea_swash_strength);
	// Skip the procedural web entirely beyond the transition. Multiplying a
	// computed web by zero would still pay its per-fragment cost at a distance.
	if (detail_weight > 0.0) {
		if (coastal_weight < 1.0) { river_web = study_foam_trails(water_point, seconds) * detail_weight; }
		if (coastal_weight > 0.0) { sea_web = study_sea_foam_trails(water_point) * detail_weight; }
	}
	if (obstacle.a > 0.001) {
		obstacle_crest = (1.0 - smoothstep(0.0, 0.22, obstacle.b)) * smoothstep(0.1, 0.4, obstacle.g);
		if (detail_weight > 0.0 && coastal_weight < 0.999 && foam_trail_strength > 0.001) {
			obstacle_web = study_foam_trail_pattern(water_point * vec2(3.3, 2.7), obstacle.b, foam_trail_lifetime) * foam_trail_strength * detail_weight;
		}
		if (detail_weight > 0.0 && coastal_weight > 0.001 && sea_foam_trail_strength > 0.001) {
			obstacle_sea_web = study_foam_trail_pattern(water_point * vec2(3.3, 2.7), obstacle.b, sea_foam_trail_lifetime)
				* sea_foam_trail_strength * smoothstep(0.0, min(0.25, sea_foam_trail_lifetime * 0.2), obstacle.b) * detail_weight;
		}
	}
	crest = mix(crest, obstacle_crest * river_crest_whiteness * 0.55, obstacle.a);
	float waterfall_web = 0.0;
	if (detail_weight > 0.0 && fall_state.a > 0.001 && waterfall_foam_strength > 0.001 && foam_trail_strength > 0.001) {
		waterfall_web = study_foam_trail_pattern(water_point * vec2(3.3, 2.7)
			+ vec2(sin(seconds * 0.18), cos(seconds * 0.21)) * 0.12, fall_state.b, foam_trail_lifetime)
			* foam_trail_strength * fall_state.a * waterfall_strength * waterfall_foam_strength * detail_weight;
	}
	float foam = clamp(study_shore_foam(water_point, seconds, base_wave.z) * (1.0 - coastal_weight)
		+ study_object_foam(water_point, seconds, base_wave.z) + crest + mix(river_web, obstacle_web * river_crest_whiteness, obstacle.a) * (1.0 - coastal_weight)
		+ study_reaction(water_point, length(fwidth(water_point)) * 0.5).y
		+ mix(swash.g * sea_foam_strength + sea_web,
			obstacle_crest * 0.35 * sea_foam_strength + obstacle_sea_web, obstacle.a) * coastal_weight
		+ fall_state.g * mix(0.55, 1.0, study_foam_noise(water_point * 6.3 - vec2(seconds * waterfall_speed * 0.25, 0.0)))
		+ waterfall_web
		+ smoothstep(0.56, 0.84, inlet_pattern.x) * mix(0.45, 1.0, inlet_pattern.y) * inlet_weight * 0.42,
		0.0, 1.0);
	EMISSION = mix(surface_color, vec3(0.70, 0.95, 1.0), foam);
	ALBEDO = vec3(0.0);
	NORMAL = view_normal;
	ROUGHNESS = mix(sky_reflection_roughness, max(sky_reflection_roughness, 0.22), glint_strength);
	SPECULAR = mix(sky_reflection_strength, max(sky_reflection_strength, 0.55), glint_strength);
	// The shader has already composed the opaque floor and the water layer.
	ALPHA = 1.0;
	}
}
