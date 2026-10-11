// Optional CUSTOM0 = semantic role, perceptual roughness, dielectric F0, grain.
// Legacy meshes have no custom attribute and retain their existing diffuse path.
#include "res://shaders/ember_material_light.gdshaderinc"
uniform bool surface_response_enabled = true;
uniform bool surface_gray_preview = false;
uniform float surface_roughness_scale : hint_range(0.25, 2.0) = 1.0;
uniform float surface_specular_scale : hint_range(0.0, 2.0) = 1.0;
uniform float surface_grain_scale : hint_range(0.0, 2.0) = 1.0;
varying flat vec4 surface_parameters;
varying vec3 surface_local_position;
varying flat vec3 surface_axis_x;
varying flat vec3 surface_axis_y;
varying flat vec3 surface_axis_z;

void vertex() {
	surface_parameters = CUSTOM0;
	surface_local_position = VERTEX;
	surface_axis_x = MODELVIEW_NORMAL_MATRIX[0];
	surface_axis_y = MODELVIEW_NORMAL_MATRIX[1];
	surface_axis_z = MODELVIEW_NORMAL_MATRIX[2];
}

bool ember_object_surface_active() {
	return surface_response_enabled && surface_parameters.x > 0.5;
}

vec3 ember_object_grain(vec3 position) {
	float role = surface_parameters.x;
	if (role > 1.5 && role < 2.5) {
		// Long local-Y fibres belong to bark. Their phase never follows the camera.
		return vec3(sin(position.x * 76.0 + sin(position.y * 5.0 + position.z * 9.0)),
			0.12 * sin(position.y * 19.0),
			sin(position.z * 61.0 + sin(position.y * 4.2 + position.x * 7.0)));
	}
	vec3 p = position * (role > 2.5 && role < 3.5 ? 38.0 : 26.0);
	// Oblique, unequal phases avoid a repeated checker pattern on voxel faces.
	return vec3(sin(dot(p, vec3(0.91, 0.27, 0.61)) + sin(p.z * 1.37)),
		sin(dot(p, vec3(0.39, 1.13, 0.17)) + sin(p.x * 0.73)),
		sin(dot(p, vec3(0.23, 0.57, 1.07)) + sin(p.y * 1.19)));
}

float ember_object_grain_fade(vec3 position) {
	// Highest authored frequency is bark's fine fibres.
	float frequency = surface_parameters.x > 1.5 && surface_parameters.x < 2.5 ? 76.0 : 38.0;
	return 1.0 - smoothstep(0.7, 2.0, length(fwidth(position * frequency)));
}

float ember_object_surface_roughness(vec3 position) {
	float fade = ember_object_grain_fade(position);
	if (fade <= 0.001 || surface_grain_scale <= 0.001) { return clamp(surface_parameters.y * surface_roughness_scale, 0.12, 1.0); }
	vec3 grain = ember_object_grain(position);
	float role = surface_parameters.x;
	float variation = role < 1.5 ? 0.12 : (role < 2.5 ? 0.09 : (role < 3.5 ? 0.06 : 0.02));
	float finish = surface_parameters.y + grain.x * grain.z * variation * surface_grain_scale * fade;
	return clamp(finish * surface_roughness_scale, 0.12, 1.0);
}

vec3 ember_object_surface_normal(vec3 normal, vec3 position) {
	// Static micro-normal only: geometry and collision stay identical. Smooth
	// analytic grain fades when it is smaller than a pixel (no temporal shimmer).
	float fade = ember_object_grain_fade(position);
	if (fade <= 0.001 || surface_grain_scale <= 0.001) { return normal; }
	vec3 grain = ember_object_grain(position);
	grain = normalize(mat3(surface_axis_x, surface_axis_y, surface_axis_z) * grain + vec3(0.000001));
	vec3 tangent_grain = grain - normal * dot(grain, normal);
	return normalize(normal + tangent_grain * surface_parameters.w * surface_grain_scale * fade);
}

float ember_object_surface_diffuse(vec3 normal, vec3 light_direction, vec3 view_direction) {
	float nl = max(dot(normal, light_direction), 0.0);
	vec3 halfway = normalize(light_direction + view_direction + vec3(0.000001));
	float f0 = clamp(surface_parameters.z * surface_specular_scale, 0.0, 0.16);
	float fresnel = ember_surface_fresnel(max(dot(view_direction, halfway), 0.0), f0);
	// Godot applies ALBEDO in final composition and LIGHT_COLOR includes PI.
	return ember_surface_diffuse(nl, fresnel);
}

vec3 ember_object_surface_specular(vec3 normal, vec3 light_direction, vec3 view_direction, float roughness) {
	if (surface_specular_scale <= 0.0) { return vec3(0.0); }
	float nl = max(dot(normal, light_direction), 0.0);
	float nv = max(dot(normal, view_direction), 0.0001);
	vec3 half_direction = normalize(light_direction + view_direction);
	float nh = max(dot(normal, half_direction), 0.0);
	float vh = max(dot(view_direction, half_direction), 0.0);
	float f0 = clamp(surface_parameters.z * surface_specular_scale, 0.0, 0.16);
	return vec3(nl * ember_surface_fresnel(vh, f0) * ember_surface_specular(nl, nv, nh, roughness));
}
