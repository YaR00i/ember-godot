// Shared optical wave field. Every water-facing shader samples these exact
// functions so a crest keeps the same shape, position and timing at a shore.

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


vec2 rotate_wave_direction(vec2 direction, float angle) {
	float sine = sin(angle);
	float cosine = cos(angle);
	return vec2(direction.x * cosine - direction.y * sine,
		direction.x * sine + direction.y * cosine);
}


vec2 shaped_wave(float phase, float sharpness) {
	// Return height and its phase derivative together, so sharpening a crest
	// also changes the normal that produces its light instead of painting an
	// unrelated bright stripe over a rounded wave.
	float sine = sin(phase);
	float base = max(sine * 0.5 + 0.5, 0.0001);
	float exponent = mix(1.0, 2.35, sharpness);
	return vec2(pow(base, exponent) * 2.0 - 1.0,
		exponent * pow(base, exponent - 1.0) * cos(phase));
}


vec3 legacy_wave_state(vec2 point, float seconds) {
	// Exact Review2 field retained behind wave_natural_mix=0.
	vec2 direction_a = vec2(0.8, 0.6);
	vec2 direction_b = vec2(-0.35, 0.93675);
	float wave_bend = broad_value_noise(point * 0.55 + vec2(13.2, 7.4)) * 2.6;
	float phase_a = dot(point, direction_a) * 6.283185 + wave_bend - seconds * wave_speed;
	float phase_b = dot(point, direction_b) * 9.424778 - wave_bend * 0.6 + seconds * wave_speed * 0.73;
	vec2 slope = direction_a * cos(phase_a) + direction_b * cos(phase_b) * 0.45;
	float height = (sin(phase_a) + sin(phase_b) * 0.45) / 1.20;
	return vec3(slope, height);
}


vec3 natural_wave_state(vec2 point, float seconds) {
	// A compact directional spectrum: long swell owns the silhouette, a
	// neighbouring system breaks repetition, and two small components roughen
	// the edge. Low-frequency interference creates sets of stronger waves and
	// quieter gaps without per-cell random flicker.
	float direction_angle = radians(wave_direction_degrees);
	vec2 direction_a = vec2(cos(direction_angle), sin(direction_angle));
	vec2 side_a = vec2(-direction_a.y, direction_a.x);
	float spread = radians(wave_direction_spread);
	vec2 direction_b = rotate_wave_direction(direction_a, spread);
	vec2 direction_c = rotate_wave_direction(direction_a, -spread * 0.72 - 0.08);
	vec2 direction_d = rotate_wave_direction(direction_a, spread * 1.35 + 0.11);

	float time_phase = seconds * wave_speed;
	float variation = wave_scale_variation;
	float secondary_scale = mix(1.24, 1.72, variation);
	float ripple_scale = mix(2.25, 3.85, variation);
	float fine_scale = ripple_scale * 1.47;
	float bend = (broad_value_noise(point * 0.36 + vec2(13.2, 7.4)) - 0.5)
		* mix(0.30, 1.45, variation);
	float cross_bend = sin(dot(point, side_a) * 0.64 + time_phase * 0.08)
		* variation * 0.62;

	float group_a = sin(dot(point, direction_a) * 1.10 - time_phase * 0.16
		+ sin(dot(point, side_a) * 0.43) * 0.48) * 0.5 + 0.5;
	float group_b = sin(dot(point, direction_b) * 0.57 + time_phase * 0.07 + 1.9) * 0.5 + 0.5;
	float group_shape = smoothstep(0.16, 0.84, group_a * 0.72 + group_b * 0.28);
	float group_envelope = mix(1.0, mix(0.48, 1.22, group_shape), wave_grouping);

	float phase_a = dot(point, direction_a) * 6.283185 + bend + cross_bend - time_phase;
	float phase_b = dot(point, direction_b) * 6.283185 * secondary_scale
		- bend * 0.38 - time_phase * sqrt(secondary_scale) + 1.7;
	float phase_c = dot(point, direction_c) * 6.283185 * ripple_scale
		+ bend * 0.18 - time_phase * sqrt(ripple_scale) + 4.1;
	float phase_d = dot(point, direction_d) * 6.283185 * fine_scale
		- bend * 0.12 - time_phase * sqrt(fine_scale) + 0.8;

	vec2 wave_a = shaped_wave(phase_a, wave_crest_sharpness);
	vec2 wave_b = shaped_wave(phase_b, wave_crest_sharpness * 0.72);
	vec2 wave_c = shaped_wave(phase_c, wave_crest_sharpness * 0.28);
	vec2 wave_d = shaped_wave(phase_d, wave_crest_sharpness * 0.18);
	float amplitude_a = 0.66 * group_envelope;
	float amplitude_b = mix(0.14, 0.28, variation);
	float amplitude_c = 0.085 * wind_ripple_strength;
	float amplitude_d = 0.050 * wind_ripple_strength;
	float height = wave_a.x * amplitude_a + wave_b.x * amplitude_b
		+ wave_c.x * amplitude_c + wave_d.x * amplitude_d;
	vec2 slope = direction_a * wave_a.y * amplitude_a
		+ direction_b * wave_b.y * amplitude_b * min(secondary_scale, 1.45)
		+ direction_c * wave_c.y * amplitude_c * min(ripple_scale, 2.15)
		+ direction_d * wave_d.y * amplitude_d * min(fine_scale, 2.35);
	return vec3(slope, height);
}


vec3 water_wave_state(vec2 point, float seconds) {
	return mix(legacy_wave_state(point, seconds), natural_wave_state(point, seconds), wave_natural_mix);
}


float dominant_wave_phase(vec2 point, float seconds) {
	float direction_angle = radians(wave_direction_degrees);
	vec2 direction = vec2(cos(direction_angle), sin(direction_angle));
	vec2 side = vec2(-direction.y, direction.x);
	float time_phase = seconds * wave_speed;
	float bend = (broad_value_noise(point * 0.36 + vec2(13.2, 7.4)) - 0.5)
		* mix(0.18, 0.58, wave_scale_variation);
	float cross_bend = sin(dot(point, side) * 0.64 + time_phase * 0.08)
		* wave_scale_variation * 0.24;
	return dot(point, direction) * 6.283185 + bend + cross_bend - time_phase;
}


vec3 dominant_wave_state(vec2 point, float seconds) {
	// The offshore field contains several crossing systems. As a wave enters
	// shallow water, refraction organises those systems around one carrier crest
	// instead of letting every small component break independently.
	float direction_angle = radians(wave_direction_degrees);
	vec2 direction = vec2(cos(direction_angle), sin(direction_angle));
	vec2 side = vec2(-direction.y, direction.x);
	float time_phase = seconds * wave_speed;
	float group_a = sin(dot(point, direction) * 1.10 - time_phase * 0.16
		+ sin(dot(point, side) * 0.43) * 0.48) * 0.5 + 0.5;
	float group_b = sin(dot(point, rotate_wave_direction(direction, radians(wave_direction_spread)))
		* 0.57 + time_phase * 0.07 + 1.9) * 0.5 + 0.5;
	float group_shape = smoothstep(0.16, 0.84, group_a * 0.72 + group_b * 0.28);
	float group_envelope = mix(1.0, mix(0.48, 1.22, group_shape), wave_grouping);
	float phase = dominant_wave_phase(point, seconds);
	vec2 wave = shaped_wave(phase, max(wave_crest_sharpness, 0.42));
	float amplitude = 0.78 * group_envelope;
	return vec3(direction * wave.y * amplitude, wave.x * amplitude);
}


float water_shore_amount(float shore_distance, float transition_distance) {
	return 1.0 - smoothstep(0.0, max(transition_distance, 0.001), shore_distance);
}


float water_shallow_amount(
	float depth_factor,
	float shallow_depth,
	float deep_depth
) {
	return 1.0 - smoothstep(
		min(shallow_depth, deep_depth - 0.001),
		max(deep_depth, shallow_depth + 0.001),
		depth_factor
	);
}


vec2 water_shore_travel_direction(
	vec2 inward,
	float wall,
	float shore_amount,
	float refraction_strength
) {
	float angle = radians(wave_direction_degrees);
	vec2 offshore_direction = vec2(cos(angle), sin(angle));
	vec2 shoreward_direction = -normalize(inward);
	float refraction = shore_amount * refraction_strength * (1.0 - wall);
	vec2 mixed_direction = mix(offshore_direction, shoreward_direction, refraction);
	return normalize(mixed_direction + vec2(0.00001, 0.0));
}


vec3 water_shore_wave_state(
	vec2 coordinate,
	float seconds,
	float shore_distance,
	float depth_factor,
	vec2 inward,
	float wall,
	float transform_strength,
	float transition_distance,
	float shallow_depth,
	float deep_depth,
	float refraction_strength,
	float wavelength_compression,
	float shoaling_strength,
	float crest_coherence
) {
	float metadata_valid = step(0.5, length(inward));
	float distance_amount = water_shore_amount(shore_distance, transition_distance);
	float depth_amount = water_shallow_amount(depth_factor, shallow_depth, deep_depth);
	float shore_amount = distance_amount * depth_amount * transform_strength * metadata_valid;
	float beach_amount = shore_amount * (1.0 - wall);
	float angle = radians(wave_direction_degrees);
	vec2 offshore_direction = vec2(cos(angle), sin(angle));
	vec2 offshore_side = vec2(-offshore_direction.y, offshore_direction.x);
	vec2 travel_direction = water_shore_travel_direction(
		inward, wall, shore_amount, refraction_strength
	);
	vec2 travel_side = vec2(-travel_direction.y, travel_direction.x);
	vec2 boundary = coordinate - normalize(inward) * shore_distance;
	vec2 local = coordinate - boundary;
	float compression = 1.0 / max(1.0 - wavelength_compression * beach_amount, 0.32);
	vec2 refracted_coordinate = boundary
		+ offshore_direction * dot(local, travel_direction) * compression
		+ offshore_side * dot(local, travel_side);
	vec2 sample_coordinate = mix(coordinate, refracted_coordinate, beach_amount);
	vec2 point = sample_coordinate / max(wave_length, 0.001);
	vec3 state = water_wave_state(point, seconds);
	vec3 carrier = dominant_wave_state(point, seconds);
	state = mix(state, carrier, beach_amount * crest_coherence);

	// Reorient the derivative back into physical water space. The phase is
	// compressed in the direction of travel, so the visible normal grows steeper
	// as wavelength shortens instead of merely changing the painted pattern.
	float longitudinal = dot(state.xy, offshore_direction);
	float lateral = dot(state.xy, offshore_side);
	vec2 refracted_slope = travel_direction * longitudinal * compression
		+ travel_side * lateral;
	state.xy = mix(state.xy, refracted_slope, beach_amount);
	float pre_break = smoothstep(0.08, 0.72, beach_amount);
	float after_break = 1.0 - smoothstep(0.82, 1.0, beach_amount) * 0.58;
	float shoaling_gain = 1.0 + shoaling_strength * pre_break * after_break;
	state.xy *= shoaling_gain;
	state.z *= shoaling_gain;
	// Once the bottom is extremely close, the organised crest has already
	// broken. Its remaining body becomes a shallow sheet while foam continues
	// the energy visually on the separate shore surface.
	float broken_water = (1.0 - smoothstep(0.02, max(shallow_depth + 0.10, 0.12), depth_factor))
		* beach_amount;
	state.xy *= mix(1.0, 0.34, broken_water);
	state.z *= mix(1.0, 0.46, broken_water);
	return state;
}


float water_break_factor(
	vec3 wave,
	float depth_factor,
	float shallow_depth,
	float visual_wave_strength,
	float break_threshold,
	float break_softness
) {
	// H/depth ~= 0.78 is the physical reference. The normalised lab depth is
	// deliberately stylised, but preserving the ratio gives the right behaviour:
	// a larger crest breaks earlier while a small crest reaches farther in.
	float local_depth = mix(0.045, 0.90, clamp(depth_factor, 0.0, 1.0));
	// The visible water state is damped after the crest has broken. Recover the
	// incident height for this test; otherwise damping the surface also disables
	// the foam that is meant to carry the lost crest energy.
	float post_break_depth = 1.0 - smoothstep(
		0.02,
		max(shallow_depth + 0.10, 0.12),
		depth_factor
	);
	float visible_height_scale = mix(1.0, 0.46, post_break_depth);
	float incident_height = max(wave.z, 0.0) / max(visible_height_scale, 0.20);
	float relative_height = incident_height * visual_wave_strength;
	float ratio = relative_height / max(local_depth, 0.025);
	return smoothstep(
		max(break_threshold - break_softness, 0.01),
		break_threshold + break_softness,
		ratio
	);
}
