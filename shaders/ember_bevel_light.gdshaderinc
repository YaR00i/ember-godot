// LAB light-only accent of the existing POM bevel; no change to its intersection.
uniform bool bevel_light_enabled = true;
uniform float bevel_light_strength : hint_range(0.0, 2.0) = 0.9;
varying float bevel_light_mask;

float ember_bevel_mask(vec2 slope, float height) {
	// Reject flat tops and the bottom of the mortar groove. Select the shoulder.
	return smoothstep(0.16, 0.65, length(slope))
		* smoothstep(0.22, 0.48, height)
		* (1.0 - smoothstep(0.78, 0.90, height));
}

float ember_bevel_light(vec3 detail, vec3 form, vec3 light) {
	float facing = dot(detail, light);
	float gain = facing - max(dot(form, light), 0.0);
	return bevel_light_strength * bevel_light_mask
		* smoothstep(0.025, 0.30, gain) * smoothstep(0.1, 0.5, facing);
}
