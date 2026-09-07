shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 base_color : source_color = vec4(0.20, 0.27, 0.37, 1.0);
uniform vec4 accent_color : source_color = vec4(0.45, 0.60, 0.78, 1.0);
uniform float pattern_mode : hint_range(0.0, 4.0, 1.0) = 0.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.8;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float emission_strength : hint_range(0.0, 2.0) = 0.0;

float stripe(float coordinate, float frequency, float width) {
	float distance_to_line = abs(fract(coordinate * frequency) - 0.5);
	return 1.0 - smoothstep(width, width + 0.06, distance_to_line);
}

void fragment() {
	vec2 uv = UV;
	float detail = 0.0;
	if (pattern_mode < 0.5) {
		// Cut-stone border and a subtle central inset.
		vec2 edge = abs(uv - vec2(0.5));
		detail = smoothstep(0.34, 0.47, max(edge.x, edge.y)) * 0.55;
	} else if (pattern_mode < 1.5) {
		// Calm water bands, deliberately static in editor and runtime.
		detail = stripe(uv.y + sin(uv.x * 12.0) * 0.045, 3.0, 0.10) * 0.62;
	} else if (pattern_mode < 2.5) {
		// Crossing diagonal seams read as heated cracks from the combat camera.
		float crack_a = stripe(uv.x + uv.y, 2.8, 0.055);
		float crack_b = stripe(uv.x - uv.y, 3.6, 0.035);
		detail = max(crack_a, crack_b) * 0.78;
	} else if (pattern_mode < 3.5) {
		// Faceted ice without a texture dependency.
		float facet_a = stripe(uv.x + uv.y * 0.55, 3.2, 0.055);
		float facet_b = stripe(uv.y - uv.x * 0.35, 3.8, 0.045);
		detail = max(facet_a, facet_b) * 0.66;
	} else {
		// Dense hazard bands for blocked cells.
		detail = stripe(uv.x + uv.y, 5.0, 0.12) * 0.48;
	}
	ALBEDO = mix(base_color.rgb, accent_color.rgb, detail);
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	EMISSION = accent_color.rgb * detail * emission_strength;
}
