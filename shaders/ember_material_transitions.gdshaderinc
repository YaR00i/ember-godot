// Chosen grass/soil and soil/stone coverage. Source palette slots bound every change.


float edge_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
float edge_noise(vec3 p) {
	vec3 q = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(edge_hash(q),edge_hash(q+vec3(1,0,0)),f.x),
		mix(edge_hash(q+vec3(0,1,0)),edge_hash(q+vec3(1,1,0)),f.x),f.y),
		mix(mix(edge_hash(q+vec3(0,0,1)),edge_hash(q+vec3(1,0,1)),f.x),
		mix(edge_hash(q+vec3(0,1,1)),edge_hash(q+vec3(1,1,1)),f.x),f.y),f.z);
}
vec3 sharp_edge_weights(vec3 source, ivec3 slots, vec3 position_m) {
	vec3 w = max(source,vec3(0.0));
	float sum = dot(w,vec3(1.0));
	if(sum < 0.00001) return vec3(1.0,0.0,0.0);
	w /= sum;
	if(max(w.x,max(w.y,w.z)) > 0.99999 || (slots.x==slots.y && slots.y==slots.z)) return w;
	// Fixed object/world coordinates; neither time nor camera nor light.
	vec3 p = mat3(vec3(0.80,0.20,-0.54),vec3(0.0,0.90,0.435),vec3(0.60,-0.27,0.72)) * position_m / 0.19;
	vec3 score = w;
	for(int i=0;i<3;i++) {
		if(w[i] <= 0.0) continue;
		vec3 seed = vec3(float(slots[i])) * vec3(7.17,13.31,19.73);
		float density = edge_noise(p+seed) * 0.78 + edge_noise(p*2.73-seed) * 0.22;
		score[i] += (density-0.5) * 0.70 * (4.0*w[i]*(1.0-w[i]));
	}
	float top = max(score.x,max(score.y,score.z));
	// Narrow optical edge with a pixel-size AA floor, never stochastic dither.
	vec3 width = max(vec3(0.10),fwidth(score)*0.75);
	vec3 result = max(score-vec3(top)+width,vec3(0.0))*step(vec3(0.000001),w);
	float total = dot(result,vec3(1.0));
	return total > 0.000001 ? result/total : w;
}


uniform sampler2D material_grass_coverage : filter_linear_mipmap_anisotropic, repeat_enable;
vec3 grass_edge_weights(vec3 source, ivec3 slots, vec3 p, vec3 normal) {
    vec3 base = sharp_edge_weights(source, slots, p);
    vec3 w=max(source,vec3(0)); float total=dot(w,vec3(1));
    if(total<0.00001) return base;
    w/=total;
    int grass=-1; int soil=-1;
    for(int i=0;i<3;i++) {
        if(w[i]<=0.00001) continue;
        int role=int(round(texelFetch(role_lookup,ivec2(slots[i],0),0).b*255.0));
        if(role==1) grass=i;
        if(role==2) soil=i;
    }
    if(grass<0 || soil<0) return base;
    float pair=w[grass]+w[soil];
    float t=w[grass]/max(pair,0.00001);
    if(t<0.00001 || t>0.99999) return base;
    vec3 axis=pow(abs(normal),vec3(4));axis/=max(dot(axis,vec3(1)),0.00001);
    vec3 q=p/0.8;
    float mask=texture(material_grass_coverage,q.zy).r*axis.x+texture(material_grass_coverage,q.xz).r*axis.y+texture(material_grass_coverage,q.xy).r*axis.z;
    // Same authored blade pattern controls the silhouette of the green coverage.
    // The existing painted pair bounds the region; a third layer keeps its sharp weight.
    float score=t+(mask-0.42)*0.96*(4.0*t*(1.0-t));
    float aa=max(0.035,fwidth(score)*0.75);
    float share=smoothstep(0.5-aa,0.5+aa,score);
    float support=base[grass]+base[soil];
    base[grass]=support*share;base[soil]=support*(1.0-share);
    return base;
}



float edge_material_height(int slot, vec3 normal) {
#ifdef EMBER_MATERIAL_BANK_DEPTH
    if(!material_depth_bank_enabled) return 0.5;
    float layer=texelFetch(terrain_depth_profiles,ivec2(slot,0),0).r-1.0;
    if(layer<0.0) return 0.5;
    float span=max(texelFetch(png_lookup,ivec2(slot,0),0).g,0.125);
    vec3 tile=terrain_world_position/(span*terrain_depth_world_unit);
    vec3 axis=ember_texture_axis_weights(normal);
#ifdef EMBER_SOLID_DEPTH
    tile=terrain_position*solid_texture_unit_m/(span*solid_pattern_scale);
    axis=solid_depth_weights();
#endif
    vec3 dx=dFdx(tile),dy=dFdy(tile);
    float value=0.0;
    if(axis.x>0.00001)value+=textureGrad(terrain_depth_bank,vec3(tile.zy,layer),dx.zy,dy.zy).r*axis.x;
    if(axis.y>0.00001)value+=textureGrad(terrain_depth_bank,vec3(tile.xz,layer),dx.xz,dy.xz).r*axis.y;
    if(axis.z>0.00001)value+=textureGrad(terrain_depth_bank,vec3(tile.xy,layer),dx.xy,dy.xy).r*axis.z;
    return value;
#else
    return 0.5;
#endif
}
vec3 ember_material_transition_weights(vec3 source, ivec3 slots, vec3 p, vec3 normal) {
    vec3 base=grass_edge_weights(source,slots,p,normal);
    vec3 w=max(source,vec3(0));float total=dot(w,vec3(1));
    if(total<0.00001) return base;
    w/=total;
    int soil=-1;int rock=-1;
    for(int i=0;i<3;i++) {
        if(w[i]<=0.00001)continue;
        int role=int(round(texelFetch(role_lookup,ivec2(slots[i],0),0).b*255.0));
        if(role==2)soil=i;
        if(role==0)rock=i;
    }
    if(soil<0 || rock<0)return base;
    float t=w[soil]/max(w[soil]+w[rock],0.00001);
    if(t<0.00001 || t>0.99999)return base;
    float stone_h=edge_material_height(slots[rock],normal);
    float soil_h=edge_material_height(slots[soil],normal);
    // Lower stone and higher soil grains retain earth longer at the same painted coverage.
    float score=t+((0.5-stone_h)*0.95+(soil_h-0.5)*0.32)*(4.0*t*(1.0-t));
    float aa=max(0.045,fwidth(score)*0.75);
    float share=smoothstep(0.5-aa,0.5+aa,score);
    float support=base[soil]+base[rock];
    base[soil]=support*share;base[rock]=support*(1.0-share);
    return base;
}
