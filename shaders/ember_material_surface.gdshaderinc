// Material properties only. Existing scene lights and the diorama response remain owners.
#include "res://shaders/ember_diorama_light.gdshaderinc"
uniform vec4 base_color : source_color = vec4(1.0);
uniform bool use_vertex_color = true;
uniform float surface_roughness : hint_range(0.04, 1.0) = 1.0;
uniform float surface_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float highlight_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 highlight_color : source_color = vec3(1.0);
uniform float highlight_color_strength : hint_range(0.0, 1.0) = 0.0;
uniform float iridescence_strength : hint_range(0.0, 1.0) = 0.0;
uniform float iridescence_frequency : hint_range(0.5, 6.0) = 2.0;
uniform int texture_kind : hint_range(0, 3) = 0;
uniform float texture_scale : hint_range(0.2, 16.0) = 3.0;
uniform float texture_strength : hint_range(0.0, 0.3) = 0.0;
uniform float texture_relief : hint_range(0.0, 0.05) = 0.0;
uniform float opacity : hint_range(0.02, 1.0) = 1.0;
uniform float transmission_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 transmission_color : source_color = vec3(0.75, 1.0, 0.45);
uniform float emission_energy : hint_range(0.0, 16.0) = 0.0;
uniform vec3 emission_color : source_color = vec3(1.0, 0.65, 0.2);
uniform bool emission_follow_base = true;
uniform int toon_steps : hint_range(3, 5) = 4;
uniform float band_floor : hint_range(0.0, 0.5) = 0.19;
uniform float local_light_softness : hint_range(0.0, 1.0) = 1.0;
varying vec3 material_position;

void vertex() {
	material_position = VERTEX;
}

float material_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float material_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(material_hash(cell), material_hash(cell+vec3(1,0,0)), f.x),
		mix(material_hash(cell+vec3(0,1,0)), material_hash(cell+vec3(1,1,0)), f.x), f.y),
		mix(mix(material_hash(cell+vec3(0,0,1)), material_hash(cell+vec3(1,0,1)), f.x),
		mix(material_hash(cell+vec3(0,1,1)), material_hash(cell+vec3(1,1,1)), f.x), f.y), f.z);
}

vec3 material_spectral_tint(float angle, float frequency) {
	// Artistic angular colour variation, not physical dispersion/refraction.
	return 0.55 + 0.45 * cos(vec3(0.0, 2.0944, 4.1888) + angle * frequency * 6.283185);
}

void fragment() {
	vec4 source = base_color * (use_vertex_color ? COLOR : vec4(1.0));
	ALBEDO = source.rgb;
	ROUGHNESS = surface_roughness;
	if (texture_kind > 0 && (texture_strength > 0.0 || texture_relief > 0.0)) {
		vec3 p = material_position * texture_scale;
		float pattern = material_noise(p * (texture_kind == 3 ? 2.0 : 0.65));
		if (texture_kind == 1) {
			pattern = 0.5 + 0.5 * sin(p.x * 6.283185 + material_noise(p * vec3(0.6,0.12,0.6)) * 3.0);
		}
		float footprint = max(length(dFdx(p)), length(dFdy(p))) * (texture_kind == 1 ? 6.283185 : texture_kind == 3 ? 2.0 : 1.0);
		float visibility = 1.0 - smoothstep(0.18, 0.55, footprint);
		float height = (pattern - 0.5) * visibility;
		ALBEDO *= 1.0 + height * texture_strength;
		ROUGHNESS = clamp(ROUGHNESS + height * texture_strength * 0.25, 0.04, 1.0);
		vec3 dx = dFdx(VERTEX);
		vec3 dy = dFdy(VERTEX);
		vec3 r1 = cross(dy, NORMAL);
		vec3 r2 = cross(NORMAL, dx);
		float determinant = dot(dx, r1);
		vec3 gradient = sign(determinant) * (dFdx(height) * r1 + dFdy(height) * r2);
		if (abs(determinant) > 0.00000001) {
			NORMAL = normalize(abs(determinant) * NORMAL - texture_relief * gradient);
		}
	}
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
	vec3 sum_direction = LIGHT + VIEW;
	vec3 half_vector = sum_direction / max(length(sum_direction), 0.0001);
	float ndotv = max(dot(NORMAL, VIEW), 0.0001);
	float ndoth = clamp(dot(NORMAL, half_vector), 0.0, 1.0);
	float alpha = max(ROUGHNESS * ROUGHNESS, 0.002);
	float denominator = 1.0 - ndoth * ndoth + ndoth * ndoth * alpha * alpha;
	float distribution = alpha * alpha / max(3.14159265 * denominator * denominator, 0.00000001);
	// GGX distribution + Smith visibility + Schlick Fresnel, matching Godot's terms.
	float visibility = 0.5 / max(mix(2.0 * ndotl * ndotv, ndotl + ndotv, alpha), 0.0001);
	vec3 f0 = mix(vec3(0.16 * highlight_strength * highlight_strength), ALBEDO, surface_metallic);
	vec3 fresnel = f0 + (vec3(1.0) - f0) * pow(1.0 - max(dot(VIEW, half_vector), 0.0), 5.0);
	vec3 tint = mix(vec3(1.0), highlight_color, highlight_color_strength);
	tint *= mix(vec3(1.0), material_spectral_tint(1.0 - ndotv, iridescence_frequency), iridescence_strength);
	SPECULAR_LIGHT += fresnel * distribution * visibility * ndotl * LIGHT_COLOR * ATTENUATION
		* SPECULAR_AMOUNT * max(highlight_strength, surface_metallic) * tint;
}
