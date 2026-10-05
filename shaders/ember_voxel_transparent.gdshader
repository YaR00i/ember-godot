shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, specular_disabled;

uniform int toon_steps : hint_range(3, 5) = 4;
uniform float band_floor : hint_range(0.0, 0.5) = 0.19;
uniform float local_light_softness : hint_range(0.0, 1.0) = 1.0;
#include "res://shaders/ember_diorama_light.gdshaderinc"

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = clamp(COLOR.a, 0.08, 1.0);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	DIFFUSE_LIGHT += ember_diorama_diffuse(ALBEDO, NORMAL, LIGHT, LIGHT_COLOR,
		ATTENUATION, LIGHT_IS_DIRECTIONAL, max(float(toon_steps), 2.0), band_floor, local_light_softness);
}
