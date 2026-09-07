shader_type spatial;
render_mode cull_back, specular_disabled;

uniform int toon_steps : hint_range(3, 5) = 4;
uniform float band_floor : hint_range(0.0, 0.5) = 0.19;
uniform float local_light_softness : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	// Keep Godot's default LIGHT_VERTEX (= interpolated VERTEX in view space).
	// Rebuilding it through MODEL_MATRIX -> world -> VIEW_MATRIX introduces
	// enough precision drift to self-shadow large voxel surfaces as moire waves.
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float steps = max(float(toon_steps), 2.0);
	float toon_ramp = floor(ndotl * steps) / (steps - 1.0);
	toon_ramp = mix(band_floor, 1.0, clamp(toon_ramp, 0.0, 1.0));
	float ramp = toon_ramp;
	float atten = ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL) {
		// PCF leftover on grazing voxel roofs reads as hair noise in a toon pass.
		atten = smoothstep(0.18, 0.62, ATTENUATION);
	} else {
		// Quantized N.L makes every point light a stack of concentric rings.
		// Keep the moon graphic, but let local fill roll smoothly over surfaces.
		float soft_ndotl = smoothstep(0.0, 0.72, ndotl);
		float soft_ramp = mix(band_floor, 1.0, soft_ndotl);
		ramp = mix(toon_ramp, soft_ramp, local_light_softness);
	}
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * atten * ramp * step(0.0001, ndotl);
}
