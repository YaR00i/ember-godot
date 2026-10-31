shader_type sky;
uniform bool distant_clouds_enabled = true;
uniform vec3 cloud_highlight = vec3(0.70);
uniform vec3 cloud_shadow = vec3(0.32);

float hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1,0)), f.x),
		mix(hash2(i + vec2(0,1)), hash2(i + vec2(1,1)), f.x), f.y);
}
float cloud_layer(vec2 p) {
	return noise2(p) * 0.55 + noise2(p * 2.1) * 0.28 + noise2(p * 4.3) * 0.12 + noise2(p * 8.5) * 0.05;
}
void sky() {
	float elevation = max(EYEDIR.y, 0.0);
	vec3 horizon = vec3(0.63, 0.77, 0.86);
	vec3 zenith = vec3(0.08, 0.26, 0.52);
	vec3 color = mix(horizon, zenith, pow(elevation, 0.45));
	if (EYEDIR.y < 0.0) {
		color = mix(horizon, vec3(0.25, 0.37, 0.45), smoothstep(0.0, 0.6, -EYEDIR.y));
	}
	if (LIGHT0_ENABLED) {
		float sun_dot = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
		color += LIGHT0_COLOR * LIGHT0_ENERGY * (pow(sun_dot, 32.0) * 0.12 + smoothstep(0.9998, 0.99996, sun_dot) * 2.0);
	}
	if (distant_clouds_enabled && abs(EYEDIR.y) < 0.24) {
		// Cloud banks at flight level. No overhead projected cloud plane.
		vec2 azimuth = normalize(EYEDIR.xz);
		vec2 p = azimuth * 3.4 + vec2(5.2, 2.8);
		float field = cloud_layer(p);
		float turrets = noise2(p * 4.0) * 0.025;
		float top = 0.045 + smoothstep(0.35, 0.72, field) * 0.13 + turrets;
		float cap = 1.0 - smoothstep(top - 0.035, top, EYEDIR.y);
		float base = smoothstep(-0.075, -0.015, EYEDIR.y);
		float coverage = cap * base * smoothstep(0.33, 0.52, field);
		float light = smoothstep(-0.01, top, EYEDIR.y);
		vec3 cloud_color = mix(cloud_shadow, cloud_highlight, 0.35 + light * 0.65);
		// Atmospheric perspective integrates the remote banks into the horizon.
		cloud_color = mix(cloud_color, horizon, 0.25);
		color = mix(color, cloud_color, coverage);
	}
	COLOR = color;
}
