// Material properties only. Existing scene lights and the diorama response remain owners.
#include "res://shaders/ember_diorama_light.gdshaderinc"
uniform vec4 base_color : source_color = vec4(1.0);
uniform bool use_vertex_color = true;
uniform float surface_roughness : hint_range(0.04, 1.0) = 1.0;
uniform float surface_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float highlight_strength : hint_range(0.0, 1.0) = 0.0;
uniform float opacity : hint_range(0.02, 1.0) = 1.0;
uniform float transmission_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 transmission_color : source_color = vec3(0.75, 1.0, 0.45);
uniform float emission_energy : hint_range(0.0, 16.0) = 0.0;
uniform vec3 emission_color : source_color = vec3(1.0, 0.65, 0.2);
uniform bool emission_follow_base = true;
uniform int toon_steps : hint_range(3, 5) = 4;
uniform float band_floor : hint_range(0.0, 0.5) = 0.19;
uniform float local_light_softness : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 source = base_color * (use_vertex_color ? COLOR : vec4(1.0));
	ALBEDO = source.rgb;
	ROUGHNESS = surface_roughness;
	METALLIC = surface_metallic;
	SPECULAR = highlight_strength;
	EMISSION = (emission_follow_base ? source.rgb : emission_color) * emission_energy;
#ifdef EMBER_MATERIAL_TRANSPARENT
	ALPHA = clamp(source.a * opacity, 0.02, 1.0);
#endif
}

void light() {
	// Godot's final compose applies ALBEDO; pass unit albedo to avoid squaring it.
	DIFFUSE_LIGHT += ember_diorama_diffuse(vec3(1.0), NORMAL, LIGHT, LIGHT_COLOR,
		ATTENUATION, LIGHT_IS_DIRECTIONAL, float(toon_steps), band_floor,
		local_light_softness) * (1.0 - surface_metallic);
	// Artistic thin-leaf transmission, driven by a real light, not emission.
	float back = pow(max(dot(-NORMAL, LIGHT), 0.0), 1.4);
	DIFFUSE_LIGHT += transmission_color * LIGHT_COLOR * ATTENUATION * back
		* transmission_strength * (1.0 - surface_metallic);
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	vec3 half_vector = normalize(LIGHT + VIEW);
	float lobe = pow(max(dot(NORMAL, half_vector), 0.0), mix(160.0, 8.0, surface_roughness));
	vec3 f0 = mix(vec3(0.08 * highlight_strength), ALBEDO, surface_metallic);
	vec3 fresnel = f0 + (vec3(1.0) - f0) * pow(1.0 - max(dot(VIEW, half_vector), 0.0), 5.0);
	SPECULAR_LIGHT += fresnel * lobe * ndotl * LIGHT_COLOR * ATTENUATION
		* SPECULAR_AMOUNT * max(highlight_strength, surface_metallic);
}
