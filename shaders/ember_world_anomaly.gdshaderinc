// One world-space field, evaluated on the unchanged authored surface. No
// clipping, time noise or second shell: the same triangles travel to the look.
instance uniform vec4 ember_anomaly_sphere : instance_index(0) = vec4(0.0);
instance uniform vec2 ember_anomaly_band_look : instance_index(1) = vec2(1.0, 1.0);
uniform bool ember_anomaly_prepared = false;
uniform bool ember_anomaly_grow_cells = false;
uniform bool ember_anomaly_shrink_cards = false;
uniform bool ember_anomaly_grass_roots = false;
uniform int ember_anomaly_grass_form = 0;
uniform sampler2D ember_anomaly_targets : filter_nearest, repeat_disable;

float ember_anomaly_weight(vec3 world_position) {
	if (ember_anomaly_sphere.w <= 0.0) { return 0.0; }
	float width = max(ember_anomaly_band_look.x, 0.0001);
	return 1.0 - smoothstep(ember_anomaly_sphere.w - width * 0.5,
		ember_anomaly_sphere.w + width * 0.5,
		length(world_position - ember_anomaly_sphere.xyz));
}

vec3 ember_anomaly_target(int vertex_id, int channel) {
	ivec2 size = textureSize(ember_anomaly_targets, 0);
	int index = vertex_id * 4 + channel;
	return texelFetch(ember_anomaly_targets, ivec2(index % size.x, index / size.x), 0).xyz;
}

void ember_anomaly_vertex(inout vec3 position, inout vec3 normal, mat4 model, int vertex_id) {
	if (!ember_anomaly_prepared) { return; }
	vec3 reference = position;
	if (ember_anomaly_grass_form > 0 && ember_anomaly_band_look.y > 1.5) {
		float growth = ember_anomaly_weight((model * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
		position *= ember_anomaly_grass_form == 1 ? 1.0 - growth : growth;
		return;
	}
	if (ember_anomaly_grass_form == 2) { position = vec3(0.0); return; }
	if (ember_anomaly_grow_cells) {
		// TreeLookBake emits each face as six vertices [0,2,1,0,3,2].
		// Tangent coordinates at a cube corner belong to two cells: flooring
		// VERTEX alone leaves a full quad even at zero growth.
		vec3 n = round(normal);
		vec3 u = abs(n.y) < 0.5 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		vec3 v = cross(n, u);
		int corner = vertex_id % 6;
		vec2 sign_corner = corner == 0 || corner == 3 ? vec2(-1.0) : corner == 2 ? vec2(1.0, -1.0) : corner == 4 ? vec2(-1.0, 1.0) : vec2(1.0);
		vec3 centre = position - (u * sign_corner.x + v * sign_corner.y + n) * 0.03125;
		centre = (floor(centre / 0.0625 + vec3(0.0001)) + vec3(0.5)) * 0.0625;
		float growth = ember_anomaly_band_look.y > 1.5 ? ember_anomaly_weight((model * vec4(centre, 1.0)).xyz) : 0.0;
		position = mix(centre, position, growth);
		return;
	}
	if (ember_anomaly_shrink_cards && ember_anomaly_band_look.y > 1.5) {
		reference = ember_anomaly_target(vertex_id, 2);
	}
	float weight = ember_anomaly_weight((model * vec4(reference, 1.0)).xyz);
	if (weight <= 0.0) { return; }
	int channel = ember_anomaly_band_look.y > 1.5 ? 2 : 0;
	position = mix(position, ember_anomaly_target(vertex_id, channel), weight);
	normal = normalize(mix(normal, ember_anomaly_target(vertex_id, channel + 1), weight) + vec3(0.0000001));
}
