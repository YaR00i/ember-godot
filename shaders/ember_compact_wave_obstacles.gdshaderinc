// The solver stays outside the material. RG = scattered and total incident
// height, A = wet/solid mask. Up to four bounded patches, same reads in either
// mode; the baked path interpolates two frames of the precomputed cycle.
uniform sampler2D obstacle_baked_field : filter_linear, repeat_disable;
uniform sampler2D obstacle_live_field : filter_linear, repeat_disable;
uniform vec4 obstacle_bounds[4];
uniform vec2 obstacle_details[4];
uniform int obstacle_patch_count = 0;
uniform int obstacle_mode = 0;
uniform float obstacle_strength = 0.0;
uniform float obstacle_time = 0.0;

vec4 obstacle_wave_sample(vec2 world_point, float seconds) {
	for (int i = 0; i < 4; i++) {
		if (i >= obstacle_patch_count) { break; }
		vec4 bounds = obstacle_bounds[i];
		vec2 local = (world_point - bounds.xy) / 4.0;
		if (any(lessThan(local, vec2(0.0))) || any(greaterThan(local, vec2(32.0)))) { continue; }
		vec4 value;
		if (obstacle_mode == 1) {
			float clock = obstacle_details[i].x > 0.5 ? sea_swash_time : (preview_time >= 0.0 ? seconds : obstacle_time);
			float phase = mod(clock / bounds.z * 64.0, 64.0);
			float first = floor(phase);
			float second = mod(first + 1.0, 64.0);
			vec2 dimensions = vec2(264.0, 264.0 * float(obstacle_patch_count));
			vec2 a = vec2(mod(first, 8.0), floor(first / 8.0) + float(i) * 8.0) * 33.0;
			vec2 b = vec2(mod(second, 8.0), floor(second / 8.0) + float(i) * 8.0) * 33.0;
			value = mix(texture(obstacle_baked_field, (a + local + 0.5) / dimensions),
				texture(obstacle_baked_field, (b + local + 0.5) / dimensions), fract(phase));
		} else {
			value = texture(obstacle_live_field, (local + vec2(0.5, float(i) * 33.0 + 0.5))
				/ vec2(33.0, 33.0 * float(obstacle_patch_count)));
		}
		float rim = min(min(local.x, local.y), min(32.0 - local.x, 32.0 - local.y));
		float weight = smoothstep(0.0, 5.0, rim) * value.a * obstacle_strength;
		return vec4(value.r * weight, value.g / max(bounds.w, 0.01), value.b, weight);
	}
	return vec4(0.0);
}

vec2 obstacle_wave_slope(vec2 point, float seconds) {
	if (obstacle_patch_count == 0) { return vec2(0.0); }
	return vec2(obstacle_wave_sample(point + vec2(4.0, 0.0), seconds).r - obstacle_wave_sample(point - vec2(4.0, 0.0), seconds).r,
		obstacle_wave_sample(point + vec2(0.0, 4.0), seconds).r - obstacle_wave_sample(point - vec2(0.0, 4.0), seconds).r) / 8.0;
}
