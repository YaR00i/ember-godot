// Static quantized surface cells, separate from authored colour/pixel heights.
// Three bounded samples, no textures, time, geometry or per-frame CPU rebuild.
float ember_terrain_detail_hash(vec2 p) {
	vec3 q=fract(vec3(p.xyx)*0.1031); q+=dot(q,q.yzx+33.33);
	return fract((q.x+q.y)*q.z);
}
float ember_terrain_detail_height(vec2 p, float role) {
	vec2 cell=floor(p);
	float fine=ember_terrain_detail_hash(cell+vec2(19.7,3.1));
	float cluster=ember_terrain_detail_hash(floor(cell*0.31));
	float value;
	if (role < 1.5) {
		// Broken, short grass groups rather than parallel continuous stripes.
		float blade=ember_terrain_detail_hash(vec2(cell.x,floor(cell.y*0.5)));
		value=mix(cluster,blade,0.65)*mix(0.3,1.0,fine);
	} else {
		// Small grains in larger clods; no animated surface or colour repaint.
		value=mix(cluster,fine,0.58);
	}
	return floor(value*5.0)/4.0;
}
vec3 ember_terrain_detail(vec2 p, float role) {
	float center=ember_terrain_detail_height(p,role);
	float x=ember_terrain_detail_height(p+vec2(1,0),role)-center;
	float y=ember_terrain_detail_height(p+vec2(0,1),role)-center;
	return vec3(-x,-y,center*2.0-1.0);
}
