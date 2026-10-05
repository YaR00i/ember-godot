vec3 wave_state(vec2 point, float seconds) {
	float travel = seconds * wave_speed;
	// Interference from four oblique, drifting waves creates local rises without
	// the visible square cells left by value noise at grazing camera angles.
	vec2 drift = point + vec2(travel * 0.17, -travel * 0.11);
	vec2 local_a = vec2(0.73, 0.42) * 1.53;
	vec2 local_b = vec2(-0.51, 0.86) * 1.27;
	vec2 local_c = vec2(0.28, -0.96) * 2.11;
	vec2 local_d = vec2(0.94, 0.34) * 0.91;
	float phase_1 = dot(drift, local_a);
	float phase_2 = dot(drift, local_b);
	float phase_3 = dot(drift, local_c);
	float phase_4 = dot(drift, local_d);
	float local_bend = (sin(phase_1) * cos(phase_2) * 0.62
		+ sin(phase_3) * sin(phase_4) * 0.38) * wave_irregularity;
	vec2 local_bend_slope = ((cos(phase_1) * cos(phase_2) * local_a
		- sin(phase_1) * sin(phase_2) * local_b) * 0.62
		+ (cos(phase_3) * sin(phase_4) * local_c
		+ sin(phase_3) * cos(phase_4) * local_d) * 0.38) * wave_irregularity;
	vec2 direction_a = normalize(vec2(0.78, 0.63));
	vec2 direction_b = normalize(vec2(-0.46, 0.89));
	vec2 direction_c = normalize(vec2(0.65, -0.76));
	vec2 bend_dir_a = vec2(0.37, 0.63) * 0.73;
	vec2 bend_dir_b = vec2(-0.83, 0.18) * 0.53;
	float bend_phase_a = dot(point, bend_dir_a) + travel * 0.24;
	float bend_phase_b = dot(point, bend_dir_b) - travel * 0.17;
	float bend = (sin(bend_phase_a) * 0.62 + sin(bend_phase_b) * 0.37) * wave_irregularity;
	vec2 bend_slope = (cos(bend_phase_a) * bend_dir_a * 0.62
		+ cos(bend_phase_b) * bend_dir_b * 0.37) * wave_irregularity;
	float group_phase = dot(point, vec2(-0.20, 0.98)) * 0.60 + bend * 0.3 + travel * 0.15;
	float group = 0.76 + sin(group_phase) * 0.24 * wave_irregularity;
	vec2 group_slope = cos(group_phase) * 0.24 * wave_irregularity
		* (vec2(-0.20, 0.98) * 0.60 + bend_slope * 0.3);
	float phase_a = dot(point, direction_a) * 1.71 + bend * 0.8 + local_bend * 1.15 - travel;
	float phase_b = dot(point, direction_b) * 2.32 - bend * 0.55 - local_bend * 0.82 - travel * 1.27 + 1.7;
	float phase_c = dot(point, direction_c) * 3.45 + bend * 0.33 + local_bend * 0.41 - travel * 1.66 + 0.8;
	vec2 grad_a = direction_a * 1.71 + bend_slope * 0.8 + local_bend_slope * 1.15;
	vec2 grad_b = direction_b * 2.32 - bend_slope * 0.55 - local_bend_slope * 0.82;
	vec2 grad_c = direction_c * 3.45 + bend_slope * 0.33 + local_bend_slope * 0.41;
	float height = sin(phase_a) * 0.58 * group + sin(phase_b) * 0.24 + sin(phase_c) * 0.07;
	vec2 slope = cos(phase_a) * grad_a * 0.58 * group
		+ sin(phase_a) * group_slope * 0.58
		+ cos(phase_b) * grad_b * 0.24
		+ cos(phase_c) * grad_c * 0.07;
	// This rotating, advected 2D field adds local rises and falls between
	// travelling crests. It drives both mesh height and optical refraction.
	float bob_phase = travel * 1.84 + dot(point, vec2(0.25, -0.18)) + local_bend * 2.4;
	float bob = local_bend * sin(bob_phase) * local_bob_strength;
	vec2 bob_slope = (local_bend_slope * sin(bob_phase)
		+ local_bend * cos(bob_phase) * (vec2(0.25, -0.18) + local_bend_slope * 2.4))
		* local_bob_strength;
	return vec3(slope + bob_slope, height + bob);
}


// Long moving swells used for optical focusing. Local bobbing is filtered
// out by the water column so the caustic pattern stays broad.
vec2 study_caustic_slope(vec2 point, float seconds) {
	float travel = seconds * wave_speed;
	vec2 bend_a = vec2(0.27, 0.53);
	vec2 bend_b = vec2(-0.58, 0.19);
	float bend_phase_a = dot(point, bend_a) + travel * 0.23;
	float bend_phase_b = dot(point, bend_b) - travel * 0.17;
	float bend = sin(bend_phase_a) * 0.57 + sin(bend_phase_b) * 0.38;
	vec2 bend_slope = cos(bend_phase_a) * bend_a * 0.57
		+ cos(bend_phase_b) * bend_b * 0.38;
	vec2 direction_a = normalize(vec2(0.78, 0.63));
	vec2 direction_b = normalize(vec2(-0.46, 0.89));
	vec2 direction_c = normalize(vec2(0.65, -0.76));
	vec2 direction_d = normalize(vec2(-0.87, -0.49));
	float phase_a = dot(point, direction_a) * 2.35 + bend * 0.85 - travel;
	float phase_b = dot(point, direction_b) * 3.27 - bend * 0.62 - travel * 1.29;
	float phase_c = dot(point, direction_c) * 4.13 + bend * 0.35 - travel * 1.67;
	float phase_d = dot(point, direction_d) * 2.79 + bend * 0.51 + travel * 0.71;
	return cos(phase_a) * (direction_a * 2.35 + bend_slope * 0.85) * 0.48
		+ cos(phase_b) * (direction_b * 3.27 - bend_slope * 0.62) * 0.27
		+ cos(phase_c) * (direction_c * 4.13 + bend_slope * 0.35) * 0.13
		+ cos(phase_d) * (direction_d * 2.79 + bend_slope * 0.51) * 0.18;
}


// Refraction shifts the light landing point by the local surface slope.
// Neighbouring rays coming closer together form irregular bright patches.
float study_caustic_focus(vec2 point, float seconds) {
	float step_size = 0.11;
	vec2 middle = study_caustic_slope(point, seconds);
	vec2 along_x = study_caustic_slope(point + vec2(step_size, 0.0), seconds);
	vec2 along_z = study_caustic_slope(point + vec2(0.0, step_size), seconds);
	float convergence = -((along_x.x - middle.x) + (along_z.y - middle.y)) / step_size;
	return smoothstep(0.55, 2.8, convergence);
}
