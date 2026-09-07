shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_toon, specular_disabled;

// A nearly clear shallow-water sheet. The authored voxel floor supplies almost
// all color/detail; the shader adds a gentle tint, broad tone drift and one
// connected pixel-cell network. World-space coordinates keep it seamless across
// Surface preview chunks.
uniform vec3 water_tint : source_color = vec3(0.18, 0.82, 0.78);
uniform vec3 water_light_tone : source_color = vec3(0.36, 0.94, 0.82);
uniform vec3 water_deep_tone : source_color = vec3(0.08, 0.58, 0.62);
uniform vec3 ripple_color : source_color = vec3(0.88, 1.0, 0.94);
uniform vec3 sky_reflection_color : source_color = vec3(0.58, 0.90, 0.93);
uniform vec3 glint_color : source_color = vec3(0.94, 1.0, 0.88);
uniform float tint_strength : hint_range(0.0, 0.5) = 0.18;
uniform float tone_strength : hint_range(0.0, 0.35) = 0.18;
uniform float tone_alpha : hint_range(0.0, 0.2) = 0.035;
uniform float alpha_scale : hint_range(0.0, 1.0) = 0.45;
uniform float depth_alpha : hint_range(0.0, 0.25) = 0.08;
uniform float ripple_alpha : hint_range(0.0, 1.0) = 0.30;
uniform float reflection_strength : hint_range(0.0, 0.4) = 0.14;
uniform float reflection_alpha : hint_range(0.0, 0.2) = 0.035;
uniform float glint_strength : hint_range(0.0, 1.0) = 0.48;
uniform float glint_alpha : hint_range(0.0, 0.4) = 0.10;
uniform float glint_cell_size : hint_range(12.0, 48.0, 1.0) = 26.0;
uniform float glint_density : hint_range(0.0, 0.5) = 0.14;
uniform float pixel_density : hint_range(8.0, 32.0, 1.0) = 16.0;
uniform float network_cell_size : hint_range(6.0, 24.0, 1.0) = 10.0;
uniform float network_width : hint_range(0.01, 0.4, 0.005) = 0.025;
uniform float animation_fps : hint_range(0.0, 8.0, 0.25) = 2.5;

varying vec2 surface_coordinate;


float ember_water_hash(vec2 value) {
	value = fract(value * vec2(123.34, 456.21));
	value += dot(value, value + 45.32);
	return fract(value.x * value.y);
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
	float broad = (
		sin(pixel.x * 0.075 + pixel.y * 0.045 + phase * 0.7)
		+ sin(pixel.x * -0.035 + pixel.y * 0.09 - phase * 0.52)
	) * 0.25 + 0.5;
	return floor(clamp(broad, 0.0, 0.999) * 4.0) / 3.0;
}


float sparse_glint(float ripple, vec2 pixel, float frame) {
	// The connected network remains the base ripple. Only a few stable coarse
	// cells become bright crests, so highlights read as authored pixel clusters
	// rather than full-screen procedural sparkle.
	vec2 glint_cell = floor(pixel / glint_cell_size);
	float seed = ember_water_hash(glint_cell + vec2(41.0, 73.0));
	float selected = 1.0 - step(glint_density, seed);
	float pulse = sin(frame * 0.08 + seed * 6.2831853) * 0.5 + 0.5;
	pulse = floor(clamp(pulse, 0.0, 0.999) * 3.0) / 2.0;
	return ripple * selected * mix(0.28, 1.0, pulse);
}


void vertex() {
	// Region meshes keep coordinates from the complete Surface Resource, so the
	// sparse line pattern crosses technical chunk boundaries without seams.
	surface_coordinate = VERTEX.xz;
}


void fragment() {
	float frame = floor(TIME * animation_fps);
	vec2 pixel = floor(surface_coordinate * pixel_density);
	float phase = frame * 0.035;
	float ripple = connected_ripple_network(pixel, phase);
	float glint = sparse_glint(ripple, pixel, frame);
	float tone = stepped_tone_drift(pixel, phase);
	// UV.x is supplied by the shared Surface mesher: 0 is ankle-deep and 1
	// means four or more art voxels. The bands stay deliberately discrete.
	float depth_band = floor(clamp(UV.x, 0.0, 0.999) * 4.0) / 3.0;
	float local_tint = tint_strength * mix(0.32, 1.0, depth_band);
	float local_tone = tone_strength * mix(0.42, 1.0, depth_band);
	vec3 depth_color = mix(water_light_tone, water_deep_tone, depth_band);
	vec3 tone_color = mix(depth_color, water_light_tone, tone * 0.42);
	vec3 clear_tint = mix(COLOR.rgb, water_tint, local_tint);
	vec3 water_body = mix(clear_tint, tone_color, local_tone);
	// Quantized Fresnel is our restrained sky reflection. It responds to the
	// editor/runtime camera but keeps the flat diorama bands from the reference.
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float reflection = floor(clamp(1.0 - facing, 0.0, 0.999) * 4.0) / 3.0;
	water_body = mix(
		water_body,
		sky_reflection_color,
		reflection * reflection_strength
	);
	ALBEDO = mix(water_body, ripple_color, ripple * 0.52);
	ALBEDO = mix(ALBEDO, glint_color, glint * glint_strength);
	ROUGHNESS = 0.94;
	METALLIC = 0.0;
	EMISSION = ripple_color * ripple * 0.012 + glint_color * glint * 0.025;
	float body_alpha = (
		COLOR.a * alpha_scale
		+ tone * tone_alpha
		+ depth_band * depth_alpha
		+ reflection * reflection_alpha
	);
	ALPHA = clamp(
		max(body_alpha, max(ripple * ripple_alpha, glint * (ripple_alpha + glint_alpha))),
		0.035,
		0.42
	);
}
