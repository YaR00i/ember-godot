shader_type fog;

uniform float cloud_time = 0.0;
uniform vec3 sun_direction = vec3(0.3, 0.8, 0.4);
uniform vec3 sun_color = vec3(1.5);
uniform vec3 highlight_color = vec3(0.70);
uniform vec3 shadow_color = vec3(0.32);
uniform float density_scale = 1.0;
uniform float shadow_strength = 1.0;
uniform float transport_phase = 0.0;
uniform float wind_scale = 1.0;
uniform float edge_softness = 0.26;
uniform float rim_strength = 0.0;
uniform float rim_width = 0.35;
uniform float rim_steps = 0.0;
uniform vec3 rim_color = vec3(0.85);
uniform vec3 view_position = vec3(0.0);

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1,0,0)), f.x),
		mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x),
		mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z);
}

float smooth_union(float a, float b) {
	float h = max(0.14 - abs(a - b), 0.0) / 0.14;
	return min(a, b) - h * h * 0.035;
}

float cloud_density(vec3 p) {
	vec3 drift = vec3(cloud_time * 0.009, 0.0, cloud_time * 0.003) * wind_scale;
	float n = noise3(p * 3.5 - drift) * 0.55
		+ noise3(p * 8.0 - drift * 1.4) * 0.30
		+ noise3(p * 16.0 - drift * 1.8) * 0.15;
	// Unequal lobes form a broad base and irregular rising turrets.
	float shape = length((p - vec3(-0.37,-0.30,0.06)) / vec3(0.52,0.38,0.65));
	shape = smooth_union(shape, length((p - vec3(0.28,-0.26,0.08)) / vec3(0.60,0.42,0.63)));
	shape = smooth_union(shape, length((p - vec3(-0.25,0.02,-0.08)) / vec3(0.43,0.60,0.49)));
	shape = smooth_union(shape, length((p - vec3(0.19,0.26,-0.13)) / vec3(0.41,0.62,0.43)));
	shape = smooth_union(shape, length((p - vec3(0.48,0.03,0.12)) / vec3(0.34,0.46,0.43)));
	shape = smooth_union(shape, length((p - vec3(-0.51,0.00,0.20)) / vec3(0.32,0.37,0.42)));
	float edge = 1.0 - smoothstep(1.0 - edge_softness, 1.0, shape + (0.5 - n) * 0.42);
	float bottom = smoothstep(-0.79, -0.57, p.y);
	// Every cell approaches zero before the native volume box ends.
	float bounds_fade = smoothstep(0.0, 0.08, 1.0 - max(abs(p.x), max(abs(p.y), abs(p.z))));
	return edge * bottom * bounds_fade * mix(0.008, 0.016, n) * density_scale;
}

void fog() {
	vec3 p = UVW * 2.0 - 1.0;
	float density = cloud_density(p);
	float optical_depth = 0.0;
	// Sample the same density field toward the scene sun: upper lobes occlude
	// lower ones. This approximates single scattering, not terrain shadow maps.
	for (int step_index = 1; step_index <= 5; step_index++) {
		vec3 sample_p = p + normalize(sun_direction) * (float(step_index) * 85.0) * 2.0 / SIZE;
		optical_depth += cloud_density(sample_p) * 85.0;
	}
	// A short multiple-scattering approximation preserves light within thick
	// lobes, with progressively weaker extinction at each additional order.
	float sunlight = (exp(-optical_depth * 0.85)
		+ 0.35 * exp(-optical_depth * 0.22)
		+ 0.15 * exp(-optical_depth * 0.06)) / 1.5;
	DENSITY = floor(density * 1024.0 + 0.5) / 1024.0;
	ALBEDO = vec3(0.0);
	// Godot multiplies EMISSION by density before packing its fog buffer.
	// Multiplying here again loses weak blue values in its R11G11B10 format.
	// Natural daylight uses neutral colors: density changes brightness, never hue.
	float sun_energy = dot(sun_color, vec3(0.2126, 0.7152, 0.0722));
	vec3 radiance = mix(shadow_color, highlight_color, mix(1.0, clamp(sunlight * sun_energy / 1.5, 0.0, 1.0), shadow_strength));
	if (rim_strength > 0.0 && density > 0.0005) {
		// Density gradient supplies a soft volume boundary, not a mesh outline.
		vec3 gradient = vec3(cloud_density(p + vec3(0.025,0,0)) - density,
			cloud_density(p + vec3(0,0.025,0)) - density,
			cloud_density(p + vec3(0,0,0.025)) - density) / SIZE;
		vec3 normal = -gradient / max(length(gradient), 0.00000001);
		vec3 view_dir = normalize(view_position - WORLD_POSITION);
		float grazing = 1.0 - smoothstep(0.0, rim_width, abs(dot(normal, view_dir)));
		float facing_sun = smoothstep(-0.15, 0.7, dot(normal, normalize(sun_direction)));
		float skin = 1.0 - smoothstep(0.003, 0.010, density);
		float rim = grazing * facing_sun * skin;
		if (rim_steps >= 1.0) {
			rim = floor(rim * rim_steps + 0.5) / rim_steps;
		}
		radiance += rim_color * rim_strength * rim * clamp(sun_energy / 1.5, 0.0, 1.0);
	}
	// Match all transport channels to the coarser blue precision in Godot 4.7.
	// Otherwise a weak white sample can retain red/green but lose blue entirely.
	// Shared temporal threshold preserves weak edge light in expectation.
	// Nearest rounding produced extinction with no light: a false dark shell.
	float threshold = fract(hash3(WORLD_POSITION * 0.173) + transport_phase * 0.61803398875);
	vec3 transport_bins = floor(radiance * DENSITY * 255.0 + threshold);
	EMISSION = DENSITY > 0.0 ? (transport_bins + vec3(0.25)) / (255.0 * DENSITY) : vec3(0.0);
}
