// Geometry-driven optical layers for the existing solid material. No geometry displacement.
uniform sampler2D stone_weathering_mask : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_faces : filter_nearest, repeat_disable;
uniform int stone_stage = 1; // Production uses 2; 3 is retained only by the old comparison harness.
uniform bool stone_profile_mode = false;
uniform sampler2D stone_profiles : filter_nearest, repeat_disable;
uniform float stone_model_scale = 1.0;
int stone_face_id(){return int(round(palette_slot));}
vec4 stone_row(int column){return texelFetch(stone_faces,ivec2(column,stone_face_id()),0);}
vec4 stone_profile(){return stone_profile_mode ? texelFetch(stone_profiles,ivec2(int(round(stone_row(5).x)),0),0) : vec4(1.0,0.02,1.0,stone_stage>=2 ? 1.0 : 0.0);}
vec4 stone_variation_profile(){return stone_profile_mode ? texelFetch(stone_profiles,ivec2(int(round(stone_row(5).x)),1),0) : vec4(1.0,1.0,0.0,0.0);}
vec2 stone_variation(){return stone_profile_mode ? texelFetch(stone_profiles,ivec2(int(round(stone_row(5).x)),1),0).xy : vec2(1.0);}
float stone_face_weight(){return stone_stage>=2 ? stone_profile().w*(1.0-ember_anomaly_weight(terrain_world_position)) : 0.0;}
vec2 stone_plane_uv(vec3 p){return vec2(dot(p,stone_row(1).xyz),dot(p,stone_row(2).xyz));}
vec2 stone_uv(vec3 p,float span){
 float seed=stone_row(1).w;float variation=stone_variation().x;float angle=(seed-0.5)*0.8*variation;
 vec3 pattern_position=p*solid_texture_unit_m;
 vec2 uv=stone_plane_uv(pattern_position)/(max(span,0.125)*solid_pattern_scale);
 return mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle)))*uv+vec2(seed*3.1,seed*1.7)*variation;
}
float stone_segment(vec2 p,vec2 a,vec2 b){vec2 v=b-a;return length(p-a-v*clamp(dot(p-a,v)/max(dot(v,v),0.000001),0.0,1.0));}
vec4 stone_edge(vec3 p){
 vec4 closest=vec4(0.0,1.0,0.0,1000.0);int count=int(stone_row(3).w);
 for(int i=0;i<32;i++){if(i>=count)break;vec4 e=stone_row(8+i);float d=max(0.0,dot(p,e.xyz)-e.w);if(d<closest.w)closest=vec4(e.xyz,d);}
 return closest;
}
float stone_seam(vec3 p){
 float d=1000.0;vec2 uv=stone_plane_uv(p);int count=int(stone_row(4).x);
 for(int i=0;i<32;i++){if(i>=count)break;vec4 segment=stone_row(40+i);d=min(d,stone_segment(uv,segment.xy,segment.zw));}
 return d;
}
float stone_crack(vec3 p){
 if(stone_stage<3 || stone_row(4).y<0.5)return 0.0;
 vec2 uv=stone_plane_uv(p);vec4 first=stone_row(80);vec4 last=stone_row(81);
 float d=min(stone_segment(uv,first.xy,first.zw),stone_segment(uv,first.zw,last.xy));
 float aa=max(fwidth(d),0.0007);return 1.0-smoothstep(max(0.0,last.z-aa),last.z+aa,d);
}
vec3 stone_colour(vec3 p,float layer,float span){
 vec2 uv=stone_uv(p,span);
 // Derive the footprint on this face without differentiating discontinuous face offsets.
 vec2 dx=stone_uv(terrain_position+dFdx(terrain_position),span)-stone_uv(terrain_position,span);
 vec2 dy=stone_uv(terrain_position+dFdy(terrain_position),span)-stone_uv(terrain_position,span);
 return textureGrad(png_albedo_bank,vec3(uv,layer),dx,dy).rgb*(1.0-stone_crack(p)*0.42);
}

float stone_weathering_weight(){return stone_profile_mode && stone_profile().y>0.0 ? stone_variation_profile().z*stone_profile().x*stone_profile().z*(1.0-ember_anomaly_weight(terrain_world_position)) : 0.0;}
vec3 stone_weathering_axes() {
 vec3 w=pow(abs(normalize(solid_form_local)),vec3(4.0));
 return w/max(w.x+w.y+w.z,0.0001);
}
float stone_weathering_coverage_cached(vec3 p, vec4 edge_context, vec3 w, float width_factor) {
 vec3 q=p*solid_texture_unit_m/0.95;
 float m=texture(stone_weathering_mask,q.zy).r*w.x+texture(stone_weathering_mask,q.xz).r*w.y+texture(stone_weathering_mask,q.xy).r*w.z;
 // The nearest edge is cached once in fragment. No edge loop per POM sample.
 vec4 e=edge_context;
 float d=max(0.0,e.w+dot(p-terrain_position,e.xyz))*max(stone_model_scale,0.0001);
 d/=width_factor;
 // The angular painted flakes own the width; no broad constant-width rim.
 float width=0.012+0.05*smoothstep(0.04,0.65,m);
 float spine=smoothstep(0.015,0.18,m)*(1.0-smoothstep(max(0.0,width-0.009),width+0.009,d));
 float patches=smoothstep(0.04,0.28,m)*(1.0-smoothstep(0.004,0.018,d-m*0.10));
 float flecks=smoothstep(0.72,0.9,m)*(1.0-smoothstep(0.25,0.38,d))*0.35;
 return max(spine,max(patches,flecks));
}
float stone_weathering_coverage(vec3 p, vec4 edge_context) {
 return stone_weathering_coverage_cached(p,edge_context,stone_weathering_axes(),max(stone_profile().y/0.02,0.001));
}

void stone_finish(vec3 p,mat3 normal_matrix,inout vec3 albedo,inout vec3 shading_normal,vec4 edge_context){
 if(stone_stage<=0)return;
 vec4 profile=stone_profile();float outside=1.0-ember_anomaly_weight(terrain_world_position);
 float strength=profile.x*profile.z*outside;
 float weathering=stone_weathering_weight();
 vec4 edge=weathering>0.0 ? edge_context : stone_edge(p);
 float scale=max(stone_model_scale,0.0001);
 float d=edge.w*scale;float aa=max(fwidth(d),0.0005);
 float wear=profile.y>0.0 ? 1.0-smoothstep(profile.y*0.7-aa,profile.y*1.1+aa,d) : 0.0;
 float weathered=weathering>0.0 ? stone_weathering_coverage(p,edge_context) : 0.0;
 wear=mix(wear,weathered,weathering);
 vec3 bevel=normalize(normal_matrix*normalize(stone_row(0).xyz-edge.xyz*0.7));
 shading_normal=normalize(mix(shading_normal,bevel,wear*0.55*strength));
 float seam=stone_seam(p)*scale;float seam_aa=max(fwidth(seam),0.0005);
 float crevice=profile.y>0.0 ? 1.0-smoothstep(profile.y*0.4-seam_aa,profile.y*1.3+seam_aa,seam) : 0.0;
 if(weathering>0.0){
  vec3 painted=mix(albedo,albedo*1.18+vec3(0.035,0.033,0.025),weathered*strength*0.72);
  painted*=1.0-crevice*0.12*strength*weathered;
  vec3 previous=albedo*mix(1.0,1.10,wear*strength)*(1.0-crevice*0.24*strength);
  albedo=mix(previous,painted,weathering);
 }else{albedo*=mix(1.0,1.10,wear*strength)*(1.0-crevice*0.24*strength);}
 float seed=stone_row(1).w;
 vec3 tint=mix(vec3(0.96,0.98,1.01),vec3(1.04,1.02,0.99),seed);
 albedo*=mix(vec3(1.0),tint,stone_face_weight()*stone_variation().y);
}
