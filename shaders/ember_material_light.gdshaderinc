// Surface light only. GGX / correlated Smith visibility / Schlick Fresnel.
// Reference: https://google.github.io/filament/main/filament.html#materialsystem/standardmodel
// Godot LIGHT_COLOR contains PI; both BRDF lobes account for it here.
float ember_surface_fresnel(float view_half, float f0) {
	float edge = 1.0 - clamp(view_half, 0.0, 1.0);
	return f0 + (1.0 - f0) * edge * edge * edge * edge * edge;
}

float ember_surface_specular(float nl, float nv, float nh, float perceptual_roughness) {
	float alpha = max(perceptual_roughness * perceptual_roughness, 0.025);
	float alpha2 = alpha * alpha;
	float denominator = nh * nh * (alpha2 - 1.0) + 1.0;
	float distribution = alpha2 / (PI * denominator * denominator);
	float masking = nl * sqrt(nv * nv * (1.0 - alpha2) + alpha2);
	float shadowing = nv * sqrt(nl * nl * (1.0 - alpha2) + alpha2);
	return distribution * 0.5 / max(masking + shadowing, 0.00001);
}
