shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, specular_disabled;

uniform int toon_steps : hint_range(3, 5) = 4;
uniform float band_floor : hint_range(0.0, 0.5) = 0.19;
uniform float local_light_softness : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = clamp(COLOR.a, 0.08, 1.0);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float steps = max(float(toon_steps), 2.0);
	float toon_ramp = floor(ndotl * steps) / (steps - 1.0);
	toon_ramp = mix(band_floor, 1.0, clamp(toon_ramp, 0.0, 1.0));
	float ramp = toon_ramp;
	float atten = ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL) {
		atten = smoothstep(0.18, 0.62, ATTENUATION);
	} else {
		float soft_ndotl = smoothstep(0.0, 0.72, ndotl);
		float soft_ramp = mix(band_floor, 1.0, soft_ndotl);
		ramp = mix(toon_ramp, soft_ramp, local_light_softness);
	}
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * atten * ramp * step(0.0001, ndotl);
}
