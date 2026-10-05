uniform float waterfall_available = 0.0;
uniform float waterfall_strength = 1.0;
uniform float waterfall_speed = 1.0;
uniform float waterfall_irregularity = 0.65;
uniform float waterfall_foam_strength = 0.75;
uniform vec4 waterfall_source;
uniform vec2 waterfall_direction = vec2(0.0, -1.0);
uniform float waterfall_width = 1.0;
uniform sampler2D waterfall_state : filter_linear, repeat_disable;
uniform vec2 waterfall_origin = vec2(0.0);
uniform vec2 waterfall_extent = vec2(1.0);

float waterfall_approach_weight(vec3 point) {
	if (waterfall_available < 0.5 || waterfall_strength < 0.001
		|| abs(point.y - waterfall_source.z - water_level_offset_voxels) > 4.0) { return 0.0; }
	vec2 delta = point.xz - waterfall_source.xy;
	float forward = dot(delta, waterfall_direction);
	float side = dot(delta, vec2(waterfall_direction.y, -waterfall_direction.x));
	return smoothstep(-32.0, -4.0, forward) * (1.0 - smoothstep(0.0, 2.0, forward))
		* (1.0 - smoothstep(waterfall_width * 0.5 - 2.0, waterfall_width * 0.5 + 0.5, abs(side)))
		* waterfall_strength;
}

vec2 waterfall_approach_coordinates(vec2 point) {
	vec2 delta = point - waterfall_source.xy;
	float forward = dot(delta, waterfall_direction);
	// The phase gradient decreases towards the lip: the same travelling
	// threads visually accelerate without stretching a texture over time.
	return vec2(dot(delta, vec2(waterfall_direction.y, -waterfall_direction.x)) + waterfall_width * 0.5,
		forward * 0.35 - forward * forward * 0.0054);
}

vec4 waterfall_sample(vec2 point) {
	vec2 uv = (point - waterfall_origin) / waterfall_extent;
	if (waterfall_available < 0.5 || waterfall_strength < 0.001 || any(lessThan(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) { return vec4(0.0); }
	return textureLod(waterfall_state, uv, 0.0);
}

vec2 waterfall_slope(vec2 point) {
	return vec2(waterfall_sample(point + vec2(1.0, 0.0)).r - waterfall_sample(point - vec2(1.0, 0.0)).r,
		waterfall_sample(point + vec2(0.0, 1.0)).r - waterfall_sample(point - vec2(0.0, 1.0)).r) * 0.5;
}
