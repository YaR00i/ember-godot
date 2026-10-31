// Texel Space Quantization (tentabrobpy, CC0):
// https://godotshaders.com/shader/texel-space-quantization/
// Shared lighting only. Pigment, optical depth and physical geometry keep their owners.
uniform bool voxel_light_enabled = false;
uniform bool voxel_light_anomaly = false;
uniform float voxel_light_cell = 0.0625;
uniform float voxel_light_levels = 8.0;

vec2 ember_texel_plane(vec3 value, vec3 axis) {
	if (axis.y >= axis.x && axis.y >= axis.z) return value.xz;
	if (axis.x >= axis.z) return value.zy;
	return value.xy;
}

// Thin grass faces need the cell centre on their actual geometric plane.
// Transform this small displacement as a vector: extrapolating view-position
// derivatives on these faces produced unstable shadow samples even with TAA.
vec3 ember_texel_plane_shift(vec3 position, vec3 normal, float cell) {
	cell = max(cell, 0.00001);
	vec3 axis = abs(normal);
	if (max(axis.x, max(axis.y, axis.z)) < 0.00001) return vec3(0.0);
	vec3 shift = vec3(0.0);
	if (axis.y >= axis.x && axis.y >= axis.z) {
		shift.xz = (floor(position.xz / cell) + vec2(0.5)) * cell - position.xz;
		shift.y = -dot(normal.xz, shift.xz) / normal.y;
	} else if (axis.x >= axis.z) {
		shift.zy = (floor(position.zy / cell) + vec2(0.5)) * cell - position.zy;
		shift.x = -dot(normal.zy, shift.zy) / normal.x;
	} else {
		shift.xy = (floor(position.xy / cell) + vec2(0.5)) * cell - position.xy;
		shift.z = -dot(normal.xy, shift.xy) / normal.z;
	}
	return shift;
}

// The Jacobian always comes from the continuous surface, including when target
// is a discontinuous POM hit. Return screen displacement and its filtering weight.
vec3 ember_texel_sample(vec3 origin, vec3 target, vec3 normal, float cell, float relief_cell) {
	cell = max(cell, 0.00001);
	vec3 axis = abs(normal);
	vec2 uv = ember_texel_plane(target, axis);
	vec2 dx = ember_texel_plane(dFdx(origin), axis) / cell;
	vec2 dy = ember_texel_plane(dFdy(origin), axis) / cell;
	float determinant = dx.x * dy.y - dy.x * dx.y;
	if (abs(determinant) < 0.0000001) return vec3(0.0);
	vec2 centre = (floor(uv / cell) + vec2(0.5)) * cell;
	if (relief_cell > 0.0) {
		// Never sample another height layer while retaining this hit's DEPTH.
		vec2 minimum = floor(uv / relief_cell) * relief_cell;
		centre = clamp(centre, minimum + relief_cell * 0.001, minimum + relief_cell * 0.999);
	}
	vec2 difference = (centre - uv) / cell;
	vec2 delta = vec2(dy.y * difference.x - dy.x * difference.y,
		-dx.y * difference.x + dx.x * difference.y) / determinant;
	vec3 shift = dFdx(origin) * delta.x + dFdy(origin) * delta.y;
	float safe = 1.0 - smoothstep(1.25, 2.0, length(shift) / cell);
	float footprint = max(length(dx), length(dy));
	return vec3(delta, safe * (1.0 - smoothstep(0.5, 1.25, footprint)));
}

vec3 ember_texel_extrapolate(vec3 value, vec3 sample_delta) {
	return value + (dFdx(value) * sample_delta.x + dFdy(value) * sample_delta.y) * sample_delta.z;
}

float ember_voxel_light_weight(vec3 world_position) {
	if (voxel_light_enabled) return 1.0;
	if (voxel_light_anomaly && ember_anomaly_prepared && ember_anomaly_band_look.y > 1.5)
		return ember_anomaly_weight(world_position);
	return 0.0;
}

vec3 ember_texel_light_steps(vec3 contribution, vec3 light_colour, float levels) {
	vec3 unit_light = contribution * PI / max(light_colour, vec3(0.00001));
	float brightness = dot(unit_light, vec3(0.2126, 0.7152, 0.0722));
	levels = max(levels, 2.0);
	float stepped = floor(max(brightness, 0.0) * levels + 0.5) / levels;
	return brightness > 0.00001 ? contribution * stepped / brightness : contribution;
}
