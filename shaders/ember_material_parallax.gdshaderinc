// Common bounded ray search. The caller supplies material_depth_height_at:
// this solver does not know palette roles, artwork, terrain cells or masks.
vec3 material_depth_intersection(vec3 origin, vec3 n, vec3 view_direction, float amplitude) {
	float cosine = max(dot(n, view_direction), 0.04);
	vec3 ray_span = view_direction * amplitude / cosine;
	float previous = 0.0;
	float crossing = 1.0;
	int steps = clamp(material_depth_steps, 8, 64);
	for (int i=1; i<=64; i++) {
		if (i>steps) break;
		float layer = float(i) / float(steps);
		vec3 p = origin + ray_span * (0.5-layer);
		if (layer >= 1.0-material_depth_height_at(p, n)) { crossing=layer; break; }
		previous=layer;
	}
	for (int i=0; i<5; i++) {
		float layer = (previous+crossing)*0.5;
		vec3 p = origin + ray_span * (0.5-layer);
		if (layer >= 1.0-material_depth_height_at(p, n)) crossing=layer;
		else previous=layer;
	}
	return origin + ray_span * (0.5-crossing);
}

float material_depth_shadow_at(vec3 hit, vec3 n, float amplitude) {
	if (!material_depth_shadows) return 1.0;
	vec3 sun = normalize(material_depth_sun_direction);
	float cosine = dot(sun, n);
	if (cosine<=0.06) return 1.0;
	float start = material_depth_height_at(hit, n);
	for (int i=1; i<=8; i++) {
		float rise = float(i)*0.125;
		vec3 p = hit + sun * amplitude * rise / cosine;
		if (material_depth_height_at(p, n) > start+rise+0.025) return 0.45;
	}
	return 1.0;
}
