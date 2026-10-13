// Opt-in presentation LAB; no mesh, physical field or authored paint changes.
// Texel-centre derivative extrapolation follows the technique described by
// tentabrobpy: https://godotshaders.com/shader/texel-space-quantization/
// Our grid uses world metres and the existing dominant texture projection.
uniform int look_study_mode = 0;
uniform float look_study_pixel_m = 0.0625;
uniform float look_study_light_levels = 8.0;
uniform float look_study_facet_steps = 6.0;
varying vec3 look_study_position;

vec2 ember_look_plane(vec3 value, vec3 axis) {
	if (axis.y >= axis.x && axis.y >= axis.z) return value.xz;
	if (axis.x >= axis.z) return value.zy;
	return value.xy;
}

vec3 ember_look_sample(vec3 position, vec3 normal) {
	vec3 axis = abs(normal);
	vec2 uv = ember_look_plane(position, axis) / max(look_study_pixel_m, 0.0078125);
	// Derive before choosing the axis; no derivative across divergent planes.
	vec2 dx = ember_look_plane(dFdx(position), axis) / max(look_study_pixel_m, 0.0078125);
	vec2 dy = ember_look_plane(dFdy(position), axis) / max(look_study_pixel_m, 0.0078125);
	float determinant = dx.x * dy.y - dy.x * dx.y;
	if (abs(determinant) < 0.0000001) return vec3(0.0);
	vec2 difference = floor(uv) + vec2(0.5) - uv;
	vec2 delta = vec2(dy.y * difference.x - dy.x * difference.y,
		-dx.y * difference.x + dx.x * difference.y) / determinant;
	vec3 shift = dFdx(position) * delta.x + dFdy(position) * delta.y;
	float safe = 1.0 - smoothstep(1.25, 2.0, length(shift) / max(look_study_pixel_m, 0.0078125));
	// Subpixel cells return to filtered shading instead of flickering in the distance.
	float footprint = max(length(dx), length(dy));
	float weight = safe * (1.0 - smoothstep(0.5, 1.25, footprint));
	return vec3(delta, weight);
}

vec3 ember_look_extrapolate(vec3 value, vec3 sample_delta) {
	return value + (dFdx(value) * sample_delta.x + dFdy(value) * sample_delta.y) * sample_delta.z;
}

vec3 ember_look_world_normal(vec3 value) {
	vec3 normal = normalize(value);
	if (look_study_mode != 1) return normal;
	vec3 stepped = round(normal * look_study_facet_steps) / max(look_study_facet_steps, 1.0);
	return dot(stepped, stepped) > 0.00001 ? normalize(stepped) : normal;
}

vec3 ember_look_pixel_colour_position(vec3 position, vec3 normal) {
	if (look_study_mode != 2) return position;
	vec3 sample_delta = ember_look_sample(position, normal);
	return ember_look_extrapolate(position, sample_delta);
}

vec3 ember_look_stepped_contribution(vec3 contribution, vec3 light_colour) {
	vec3 unit_light = contribution * PI / max(light_colour, vec3(0.00001));
	float brightness = dot(unit_light, vec3(0.2126, 0.7152, 0.0722));
	float levels = max(look_study_light_levels, 2.0);
	float stepped = floor(max(brightness, 0.0) * levels + 0.5) / levels;
	return brightness > 0.00001 ? contribution * stepped / brightness : contribution;
}
