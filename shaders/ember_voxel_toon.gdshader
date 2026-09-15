shader_type spatial;
render_mode cull_back, specular_disabled;

uniform int toon_steps : hint_range(3, 5) = 4;
uniform float band_floor : hint_range(0.0, 0.5) = 0.19;
uniform float local_light_softness : hint_range(0.0, 1.0) = 1.0;
#include "res://shaders/ember_diorama_light.gdshaderinc"

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	// Keep Godot's default LIGHT_VERTEX (= interpolated VERTEX in view space).
	// Rebuilding it through MODEL_MATRIX -> world -> VIEW_MATRIX introduces
	// enough precision drift to self-shadow large voxel surfaces as moire waves.
}

void light() {
	DIFFUSE_LIGHT += ember_diorama_diffuse(ALBEDO, NORMAL, LIGHT, LIGHT_COLOR,
		ATTENUATION, LIGHT_IS_DIRECTIONAL, max(float(toon_steps), 2.0), band_floor, local_light_softness);
}
