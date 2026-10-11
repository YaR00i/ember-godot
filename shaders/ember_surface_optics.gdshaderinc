// Thin/solid screen refraction approximation, in view space (Godot Forward+).
// Same depth reconstruction and Beer-Lambert approach as Ember water, without
// shore/wave state or another viewport. The caller owns optical path length.
vec3 ember_optics_view_position(vec2 uv, float depth, mat4 inverse_projection) {
	vec4 position = inverse_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
	return position.xyz / max(abs(position.w), 0.000001) * sign(position.w);
}
vec2 ember_optics_project(vec3 position, mat4 projection) {
	vec4 clip = projection * vec4(position, 1.0);
	return clip.xy / max(abs(clip.w), 0.000001) * sign(clip.w) * 0.5 + 0.5;
}
vec2 ember_optics_offset(vec3 position, vec3 normal, vec3 view_direction,
	mat4 projection, float ior, float path_length) {
	vec3 incident = -normalize(view_direction);
	vec3 transmitted = refract(incident, normalize(normal), 1.0 / max(ior, 1.0));
	return ember_optics_project(position + transmitted * path_length, projection)
		- ember_optics_project(position + incident * path_length, projection);
}
vec3 ember_optics_transmission(vec3 tint, float body_opacity, float path_length) {
	vec3 absorption = (vec3(1.0) - clamp(tint, vec3(0.0), vec3(1.0))) * body_opacity * 2.0;
	return exp(-absorption * path_length);
}

// Smooth static 3D value field. Local coordinates/seed keep inclusions attached
// to the source; no TIME, screen-coordinate noise, CPU texture or ray marching.
float ember_optics_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
float ember_optics_cloud_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(ember_optics_hash(cell), ember_optics_hash(cell+vec3(1,0,0)),f.x),
		mix(ember_optics_hash(cell+vec3(0,1,0)),ember_optics_hash(cell+vec3(1,1,0)),f.x),f.y),
		mix(mix(ember_optics_hash(cell+vec3(0,0,1)),ember_optics_hash(cell+vec3(1,0,1)),f.x),
		mix(ember_optics_hash(cell+vec3(0,1,1)),ember_optics_hash(cell+vec3(1,1,1)),f.x),f.y),f.z);
}
float ember_optics_cloud(vec3 local_position, float scale, float seed) {
	vec3 p = local_position * scale + vec3(seed*0.173, seed*0.317, seed*0.113);
	float field = ember_optics_cloud_noise(p)*0.72 + ember_optics_cloud_noise(p*2.07+vec3(8.3,2.1,5.7))*0.28;
	return smoothstep(0.34,0.72,field);
}

// Three bounded irregular fracture sheets, sampled at two interior depths by
// the caller. Their width is derivative-filtered; no 27-cell Voronoi/raymarch.
float ember_optics_cracks(vec3 position, float scale, float width, float seed) {
	vec3 p = position * scale;
	float result = 0.0;
	for (int i=0; i<3; i++) {
		vec3 direction = i==0 ? normalize(vec3(0.73,0.51,-0.29))
			: (i==1 ? normalize(vec3(-0.23,0.81,0.53)) : normalize(vec3(0.41,-0.31,0.86)));
		float phase = dot(p,direction) + seed * (0.037+float(i)*0.011);
		phase += sin(dot(p,vec3(0.91,0.37,0.61))+float(i)*2.1)*0.055;
		float band = floor(phase);
		float center = 0.18+0.64*ember_optics_hash(vec3(band,float(i)*7.0,seed+19.3));
		float distance = abs(fract(phase)-center)/scale;
		float local_width = width*mix(0.55,1.5,ember_optics_hash(vec3(band,seed,float(i)+31.7)));
		float aa = max(local_width, fwidth(distance)*0.75);
		float sheet = 1.0-smoothstep(aa*0.35,aa*1.8,distance);
		float patch = smoothstep(0.2,0.7,ember_optics_hash(floor(p*0.65)+float(i)*13.0+seed));
		result = max(result,sheet*mix(0.25,1.0,patch));
	}
	return result;
}
float ember_optics_bubbles(vec3 position, float scale, float seed) {
	vec3 p = position*scale;
	vec3 cell = floor(p);
	float random = ember_optics_hash(cell+seed);
	vec3 center = vec3(0.25)+vec3(ember_optics_hash(cell+seed+3.1),ember_optics_hash(cell+seed+7.3),ember_optics_hash(cell+seed+9.7))*0.5;
	float radius = mix(0.045,0.15,random*random);
	float d = length(fract(p)-center);
	float aa = max(length(fwidth(p))*0.35,0.008);
	float ring = 1.0-smoothstep(aa,aa*2.0,abs(d-radius));
	float center_scatter = 0.12*(1.0-smoothstep(radius*0.2,radius,d));
	return (ring+center_scatter)*step(0.38,random);
}
