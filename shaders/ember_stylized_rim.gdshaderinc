#ifndef EMBER_STYLIZED_RIM_INCLUDED
#define EMBER_STYLIZED_RIM_INCLUDED
// Pure shared form response. The caller supplies light energy, visibility,
// material strength and tint. No emission or per-texture-leaf edge detection.
instance uniform bool ember_style_rim_master = true;

float ember_stylized_rim(vec3 normal, vec3 view, vec3 light, float weight) {
	float nv = max(dot(normal, view), 0.0);
	if (!ember_style_rim_master) { return 0.0; }
	float rim = 1.0 - smoothstep(0.10, 0.32, nv);
	rim *= smoothstep(-0.25, 0.25, dot(normal, light));
	rim *= (1.0 - smoothstep(0.65, 0.90, dot(view, light))) * weight;
	return rim;
}
#endif
