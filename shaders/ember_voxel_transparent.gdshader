shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back;

uniform int toon_steps : hint_range(3, 5) = 4;
uniform float band_floor : hint_range(0.0, 0.5) = 0.19;
uniform float local_light_softness : hint_range(0.0, 1.0) = 1.0;
#include "res://shaders/ember_diorama_light.gdshaderinc"
#include "res://shaders/ember_voxel_surface_light.gdshaderinc"

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = clamp(COLOR.a, 0.08, 1.0);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	if (surface_gray_preview && surface_parameters.x > 0.5) { ALBEDO = vec3(0.45); }
	if (ember_object_surface_active()) {
		ROUGHNESS = ember_object_surface_roughness(surface_local_position);
		SPECULAR = clamp(surface_parameters.z * surface_specular_scale / 0.08, 0.0, 1.0);
		NORMAL = ember_object_surface_normal(NORMAL, surface_local_position);
	}
}

void light() {
	if (ember_object_surface_active()) {
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT * ember_object_surface_specular(NORMAL, LIGHT, VIEW, ROUGHNESS);
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ember_object_surface_diffuse(NORMAL, LIGHT, VIEW);
	} else {
	DIFFUSE_LIGHT += ember_diorama_diffuse(ALBEDO, NORMAL, LIGHT, LIGHT_COLOR,
		ATTENUATION, LIGHT_IS_DIRECTIONAL, max(float(toon_steps), 2.0), band_floor, local_light_softness);
	}
}
