shader_type sky;
render_mode use_debanding;

uniform vec3 zenith_color : source_color = vec3(0.031, 0.039, 0.11);
uniform vec3 horizon_color : source_color = vec3(0.071, 0.086, 0.188);
uniform vec3 fog_color : source_color = vec3(0.33, 0.09, 0.32);
uniform float fog_mix : hint_range(0.0, 1.0) = 0.22;
uniform vec3 moon_dir = vec3(0.15, 0.55, 0.82);
uniform vec3 moon_color : source_color = vec3(0.82, 0.88, 1.0);
uniform float moon_size : hint_range(0.01, 0.12) = 0.032;
uniform float stars : hint_range(0.0, 1.0) = 0.85;

float hash13(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void sky() {
	vec3 eye = normalize(EYEDIR);
	float up = eye.y;
	vec3 hz = mix(horizon_color, fog_color, fog_mix);
	vec3 col = mix(hz, zenith_color, smoothstep(-0.08, 0.62, up));

	float star_cell = hash13(floor(eye * 220.0));
	float star = step(1.0 - stars * 0.018, star_cell) * smoothstep(0.02, 0.28, up);
	col += vec3(0.72, 0.78, 1.0) * star;

	vec3 md = normalize(moon_dir);
	float d = dot(eye, md);
	float disc = smoothstep(1.0 - moon_size, 1.0 - moon_size * 0.55, d);
	float crater = 0.82 + 0.18 * hash13(floor(eye * 90.0 + md * 8.0));
	float halo = smoothstep(1.0 - moon_size * 4.2, 1.0 - moon_size, d) * 0.16;
	col += moon_color * (disc * crater + halo);

	COLOR = col;
}
