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
 return ember_texel_plane(value, axis);
}

vec3 ember_look_sample(vec3 position, vec3 normal) {
 return ember_texel_sample(position, position, normal, max(look_study_pixel_m, 0.0078125), 0.0);
}

vec3 ember_look_extrapolate(vec3 value, vec3 sample_delta) {
 return ember_texel_extrapolate(value, sample_delta);
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
 return ember_texel_light_steps(contribution, light_colour, look_study_light_levels);
}
