shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

// Minimal depth-and-swell study. The existing terrain Resource owns the floor;
// the opt-in refined water mesh supplies depth in vertex alpha (voxels / 64).
uniform vec3 shallow_color : source_color = vec3(0.12, 0.72, 0.78);
uniform vec3 deep_color : source_color = vec3(0.025, 0.34, 0.66);
uniform vec3 absorption_per_block = vec3(1.55, 0.75, 0.32);
uniform float deep_start_blocks : hint_range(0.0, 4.0) = 0.20;
uniform float deep_end_blocks : hint_range(0.1, 4.0) = 2.35;
uniform float wave_height_voxels : hint_range(0.0, 2.0) = 1.25;
uniform float wave_speed : hint_range(0.0, 2.0) = 0.42;
uniform float refraction_strength : hint_range(0.0, 0.015) = 0.007;
uniform float preview_time = -1.0;
uniform sampler2D floor_screen : hint_screen_texture, repeat_disable, filter_linear;

varying vec2 water_point;


vec3 wave_state(vec2 point, float seconds) {
	vec2 direction_a = normalize(vec2(0.66, 0.75));
	vec2 direction_b = normalize(vec2(0.50, 0.87));
	float phase_a = dot(point, direction_a) * 6.283185 / 3.6 - seconds * wave_speed;
	float phase_b = dot(point, direction_b) * 6.283185 / 2.4 - seconds * wave_speed * 1.16 + 1.7;
	float height = sin(phase_a) + sin(phase_b) * 0.18;
	vec2 slope = direction_a * cos(phase_a) * (6.283185 / 3.6)
		+ direction_b * cos(phase_b) * (6.283185 / 2.4) * 0.18;
	return vec3(slope, height);
}


void vertex() {
	water_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz / 16.0;
	float seconds = preview_time >= 0.0 ? preview_time : TIME;
	VERTEX.y += wave_state(water_point, seconds).z * wave_height_voxels;
}


void fragment() {
	float seconds = preview_time >= 0.0 ? preview_time : TIME;
	float depth_blocks = clamp(COLOR.a, 0.0, 1.0) * 4.0;
	float depth_mix = smoothstep(deep_start_blocks, deep_end_blocks, depth_blocks);
	vec2 slope = wave_state(water_point, seconds).xy * (wave_height_voxels / 16.0);
	vec2 floor_uv = clamp(SCREEN_UV + slope * refraction_strength * smoothstep(0.0, 1.0, depth_blocks), vec2(0.001), vec2(0.999));
	vec3 floor_color = textureLod(floor_screen, floor_uv, 0.0).rgb;
	vec3 transmission = exp(-absorption_per_block * depth_blocks);
	vec3 water_color = mix(shallow_color, deep_color, depth_mix);
	ALBEDO = floor_color * transmission + water_color * (vec3(1.0) - transmission);
	// The shader has already composed the opaque floor and the water layer.
	ALPHA = 1.0;
}
