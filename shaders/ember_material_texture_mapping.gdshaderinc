// Shared texture math. World-space metres survive mesh deformation; colour,
// height and finish must use the same coordinates and projection weights.
uniform float ember_texture_world_unit = 1.0;
vec3 ember_texture_coordinates(vec3 world_position, float span_m) {
	return world_position / (max(span_m, 0.125)*ember_texture_world_unit);
}

// Colour and optical height share the same texel centres in the voxel look.
vec3 ember_texture_cell_coordinates(vec3 uv) {
	return (floor(uv * 32.0) + 0.5) / 32.0;
}

vec3 ember_texture_axis_weights(vec3 surface_normal) {
	vec3 w = pow(abs(normalize(surface_normal)), vec3(24.0));
	return w / max(dot(w, vec3(1.0)), 0.00001);
}

vec3 ember_texture_surface_normal(vec3 world_position, vec3 shading_normal) {
	// Interpolated/blended vertex normals can lag behind an extending riser.
	// Projection follows its actual current plane, not that lighting hint.
	vec3 plane = cross(dFdx(world_position), dFdy(world_position));
	if (dot(plane,plane) < 0.000000000001) return normalize(shading_normal);
	plane = normalize(plane);
	return dot(plane,shading_normal) < 0.0 ? -plane : plane;
}

vec2 ember_texture_seam_blend(vec2 uv, bool periodic) {
	// A periodic colour/height pair already agrees across its border. Mixing
	// in a half-tile offset there invents a new strip of unrelated geometry.
	if (periodic) return vec2(0.0);
	vec2 f = fract(uv);
	return vec2(1.0) - smoothstep(vec2(0.0), vec2(0.018), min(f, vec2(1.0)-f));
}
