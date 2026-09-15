// Shared light response only. Water/alpha retain their own fragment behaviour.
uniform float shadow_tint_strength : hint_range(0.0, 1.0) = 0.42;
uniform vec3 shadow_tint : source_color = vec3(0.48, 0.76, 0.82);
uniform float band_softness : hint_range(0.01, 0.2) = 0.065;

vec3 ember_diorama_diffuse(vec3 base, vec3 normal, vec3 direction, vec3 color,
	float attenuation, bool directional, float steps, float floor_value, float local_softness) {
	float ndotl = max(dot(normal, direction), 0.0);
	float hard = mix(floor_value, 1.0, clamp(floor(ndotl * steps) / (steps - 1.0), 0.0, 1.0));
	if (!directional) {
		float soft = mix(floor_value, 1.0, smoothstep(0.0, 0.72, ndotl));
		return base * color * attenuation * mix(hard, soft, local_softness) * step(0.0001, ndotl);
	}
	// A cool Moon keeps its established night response. Warmth follows the
	// authored light colour, so a node name alone cannot activate the style.
	float warm = smoothstep(0.015, 0.13, (color.r - color.b) / max(max(color.r, color.g), max(color.b, 0.001)));
	if (warm <= 0.001) {
		return base * color * smoothstep(0.18, 0.62, attenuation) * hard * step(0.0001, ndotl);
	}
	float style = warm * shadow_tint_strength;
	float bands = 0.0;
	for (int i = 1; i < 5; i++) {
		float threshold = float(i) / steps;
		bands += smoothstep(threshold - band_softness, threshold + band_softness, ndotl) * step(float(i), steps - 1.0);
	}
	float mellow = mix(floor_value, 1.0, bands / (steps - 1.0));
	float shadow = mix(smoothstep(0.18, 0.62, attenuation), smoothstep(0.02, 0.98, attenuation), warm);
	float direct = mix(hard, mellow, warm) * shadow * step(0.0001, ndotl);
	// Cheap indirect hue shift, bounded by the actual directional irradiance.
	// No emission, screen-space AO, world noise or per-voxel edge treatment.
	float luma = dot(base, vec3(0.2126, 0.7152, 0.0722));
	vec3 cool_base = mix(base * vec3(0.66, 0.91, 1.08), shadow_tint * luma, 0.28);
	vec3 bounce = cool_base * (1.0 - direct) * style * 0.28;
	vec3 sunlight = mix(color, color * vec3(1.06, 0.98, 0.86), warm);
	return sunlight * base * direct + max(color.r, max(color.g, color.b)) * bounce;
}
