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


float contact_hash(float value) {
	return fract(sin(value * 12.9898 + 37.719) * 43758.5453);
}


void fragment() {
	float frame = floor(TIME * animation_fps);
	vec2 pixel_uv = vec2(
		floor(UV.x * pixel_density) / pixel_density,
		floor(UV.y * pixel_density) / pixel_density
	);
	vec2 centered = pixel_uv * 2.0 - vec2(1.0);
	vec2 calm_centered = centered;
	float radius = length(calm_centered);
	float angle = atan(calm_centered.y, calm_centered.x);
	float sector = floor((angle + 3.14159265) / 6.2831853 * 20.0);
	float keep = step(0.24, contact_hash(sector));
	float outer_ring = step(0.70, radius) * (1.0 - step(0.91, radius));
	float inner_ring = step(0.48, radius) * (1.0 - step(0.58, radius));
	float pulse = sin(frame * 0.16 + contact_hash(sector + 9.0) * 6.2831853) * 0.5 + 0.5;
	pulse = floor(clamp(pulse, 0.0, 0.999) * 3.0) / 2.0;
	float calm_arcs = keep * max(outer_ring, inner_ring * (0.30 + pulse * 0.26));

	// Only the local bow wave stays attached to the actor. The two side trails
	// are world-history geometry owned by EmberWaterContact3D, so turns no
	// longer rotate already emitted water marks.
	float bow_radius = length(vec2(calm_centered.x, (calm_centered.y - 0.18) * 1.35));
	float bow_arc = step(0.58, bow_radius) * (1.0 - step(0.72, bow_radius));
	bow_arc *= step(0.06, calm_centered.y) * step(abs(calm_centered.x), 0.56);
	float moving_arcs = bow_arc * (0.72 + pulse * 0.28);
	float arcs = max(calm_arcs * mix(1.0, 0.58, motion_strength), moving_arcs * motion_strength);
	float moving_tint = clamp(motion_strength * 0.32 + pulse * 0.18, 0.0, 1.0);
	ALBEDO = mix(contact_shadow, contact_color, 0.64 + moving_tint);
	EMISSION = contact_color * arcs * mix(0.018, 0.032, motion_strength);
	ALPHA = arcs * alpha_scale * mix(0.78, 1.0, motion_strength);
	if (water_mask_enabled) {
		ALPHA *= texture(water_mask, UV).r;
	}
}
