shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// A small world-space footprint ripple used by actors and opted-in props.
// Geometry supplies placement at the canonical water plane; the shader only
// breaks two rings into calm pixel-art arcs.
uniform vec3 contact_color : source_color = vec3(0.88, 1.0, 0.93);
uniform vec3 contact_shadow : source_color = vec3(0.42, 0.86, 0.82);
uniform float alpha_scale : hint_range(0.0, 1.0) = 0.62;
uniform float pixel_density : hint_range(8.0, 48.0, 1.0) = 24.0;
uniform float animation_fps : hint_range(0.0, 8.0, 0.25) = 3.0;
instance uniform float motion_strength : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D water_mask : filter_nearest, repeat_disable;
uniform bool water_mask_enabled = false;
uniform bool flow_reaction_enabled = false;
uniform float preview_time = -1.0;
uniform float wave_speed : hint_range(0.0, 2.0) = 0.48;
uniform float wave_length : hint_range(0.25, 8.0) = 3.71;
uniform float wave_direction_degrees : hint_range(-180.0, 180.0) = 180.0;
uniform vec2 object_coordinate = vec2(2.5, 1.2);
uniform float reaction_strength : hint_range(0.0, 1.0) = 0.58;
// Normalized against the helper quad: a 3 m quad and a 1.0 x 0.9 m rock use
// approximately vec2(0.33, 0.30). Rounded footprints also cover actors.
uniform vec2 object_half_extent = vec2(0.33, 0.30);
uniform float object_roundness : hint_range(0.0, 0.5) = 0.03;
uniform float contact_line_width : hint_range(0.005, 0.12) = 0.026;
uniform float contact_line_strength : hint_range(0.0, 1.0) = 0.72;
uniform float reaction_line_width : hint_range(0.005, 0.12) = 0.024;
uniform float reaction_distance : hint_range(0.02, 0.5) = 0.12;


float contact_hash(float value) {
	return fract(sin(value * 12.9898 + 37.719) * 43758.5453);
}


float rounded_box_sdf(vec2 point, vec2 half_extent, float roundness) {
	vec2 core = max(half_extent - vec2(roundness), vec2(0.001));
	vec2 offset = abs(point) - core;
	return length(max(offset, vec2(0.0)))
		+ min(max(offset.x, offset.y), 0.0) - roundness;
}


float thin_line(float distance_to_line, float width) {
	return 1.0 - smoothstep(width * 0.45, width * 1.35, abs(distance_to_line));
}


void fragment() {
	float frame = floor(TIME * animation_fps);
	vec2 pixel_uv = vec2(
		floor(UV.x * pixel_density) / pixel_density,
		floor(UV.y * pixel_density) / pixel_density
	);
	vec2 centered = pixel_uv * 2.0 - vec2(1.0);
	if (flow_reaction_enabled) {
		// Keep the actual water/object intersection separate from the moving
		// response. This makes a thin stable contact seam for props and actors,
		// while this lab/prop branch responds to the shared water direction.
		// Runtime actors use the motion-strength branch below.
		float seconds = preview_time >= 0.0 ? preview_time : TIME;
		float direction_angle = radians(wave_direction_degrees);
		vec2 wave_direction = vec2(cos(direction_angle), sin(direction_angle));
		vec2 response_direction = wave_direction;
		float phase = dot(object_coordinate / max(wave_length, 0.001), wave_direction)
			* 6.283185 - seconds * wave_speed;
		float crest = sin(phase) * 0.5 + 0.5;
		// With the lab quad lying in XZ, UV Y points against world Z.
		vec2 footprint_position = vec2(centered.x, -centered.y);
		float footprint_distance = rounded_box_sdf(
			footprint_position, object_half_extent, object_roundness
		);
		float contact_seam = thin_line(footprint_distance, contact_line_width);

		float along = dot(footprint_position, response_direction);
		float side = dot(footprint_position, vec2(-response_direction.y, response_direction.x));
		float oscillation = (crest - 0.5) * reaction_line_width * 1.4;
		float outer_distance = reaction_distance + oscillation;
		float response_shell = thin_line(footprint_distance - outer_distance, reaction_line_width);
		float front_arc = response_shell * (1.0 - smoothstep(-0.04, 0.18, along));

		float body_radius = max(object_half_extent.x, object_half_extent.y);
		float downstream = max(along - body_radius * 0.35, 0.0);
		float side_target = object_half_extent.x + reaction_distance * 0.58
			+ downstream * 0.20 + sin(phase + downstream * 4.0) * reaction_line_width * 0.75;
		float side_arms = thin_line(abs(side) - side_target, reaction_line_width);
		side_arms *= smoothstep(body_radius * 0.12, body_radius * 0.48, along)
			* (1.0 - smoothstep(body_radius + 0.32, body_radius + 0.62, along));

		// The contact seam stays present, while the detached response swells only
		// when the shared incoming crest reaches the obstacle.
		float crest_response = mix(0.24, 1.0, smoothstep(0.34, 0.82, crest));
		float bright_reaction = max(front_arc, side_arms * 0.62)
			* reaction_strength * crest_response;
		float sheltered = smoothstep(body_radius * 0.16, body_radius * 0.46, along)
			* (1.0 - smoothstep(object_half_extent.x * 0.50, object_half_extent.x * 1.05, abs(side)))
			* (1.0 - smoothstep(body_radius + 0.22, body_radius + 0.52, along));

		float pale_mix = clamp(contact_seam + bright_reaction * 0.62, 0.0, 1.0);
		ALBEDO = mix(contact_shadow * 0.56, contact_color, pale_mix);
		EMISSION = contact_color * (contact_seam * contact_line_strength + bright_reaction) * 0.012;
		ALPHA = clamp(
			contact_seam * contact_line_strength * alpha_scale
			+ bright_reaction * alpha_scale * 0.62
			+ sheltered * reaction_strength * 0.055,
			0.0,
			0.62
		);
	} else {
		vec2 calm_centered = centered;
		float radius = length(calm_centered);
		float angle = atan(calm_centered.y, calm_centered.x);
		float sector = floor((angle + 3.14159265) / 6.2831853 * 20.0);
		float keep = step(0.24, contact_hash(sector));
		// Runtime actors keep a continuous one-pixel seam at their feet. Calm
		// water and motion responses live outside it instead of replacing it.
		float contact_seam = thin_line(radius - 0.56, 0.032);
		float outer_ring = thin_line(radius - 0.80, 0.030);
		float pulse = sin(frame * 0.16 + contact_hash(sector + 9.0) * 6.2831853) * 0.5 + 0.5;
		pulse = floor(clamp(pulse, 0.0, 0.999) * 3.0) / 2.0;
		float calm_arcs = keep * outer_ring * (0.22 + pulse * 0.18);
		float bow_radius = length(vec2(calm_centered.x, (calm_centered.y - 0.18) * 1.35));
		float bow_arc = thin_line(bow_radius - 0.69, 0.032);
		bow_arc *= step(0.06, calm_centered.y) * step(abs(calm_centered.x), 0.56);
		float moving_arcs = bow_arc * (0.72 + pulse * 0.28);
		float arcs = max(calm_arcs * mix(1.0, 0.58, motion_strength), moving_arcs * motion_strength);
		float moving_tint = clamp(motion_strength * 0.32 + pulse * 0.18, 0.0, 1.0);
		ALBEDO = mix(contact_shadow, contact_color, 0.58 + moving_tint + contact_seam * 0.28);
		EMISSION = contact_color * (contact_seam * 0.45 + arcs) * mix(0.012, 0.024, motion_strength);
		ALPHA = clamp(
			contact_seam * alpha_scale * 0.74
			+ arcs * alpha_scale * mix(0.52, 0.90, motion_strength),
			0.0,
			0.62
		);
	}
	if (water_mask_enabled) {
		ALPHA *= texture(water_mask, UV).r;
	}
}
