// Private opt-in binding. Shared bark coordinates/weights and one existing ray solver.
uniform bool painted_bark_relief_enabled = false;
uniform sampler2D painted_bark_recess_mask : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float material_depth_amplitude_m = 0.0;
uniform int material_depth_steps = 16;
uniform vec3 material_depth_sun_direction = vec3(0.4,0.8,0.2);
uniform bool material_depth_shadows = false;
varying vec3 painted_bark_form_normal;
varying vec2 painted_bark_relief_lod;

float ember_bark_recess_lod(vec3 p,int index) {
	vec4 coords=ember_bark_support_coordinates(p,index);
	vec2 dx=dFdx(coords.xy),dy=dFdy(coords.xy);
	dx.x=fract(dx.x+0.5)-0.5;dy.x=fract(dy.x+0.5)-0.5;
	return max(0.0,log2(max(max(length(dx),length(dy))*float(textureSize(painted_bark_recess_mask,0).x),0.00001)));
}

float ember_bark_recess_at(vec3 p,int index,float lod) {
	vec4 coords=ember_bark_support_coordinates(p,index);
	vec2 uv=painted_bark_pixel_m>0.0?coords.zw:coords.xy;
	float recess=textureLod(painted_bark_recess_mask,uv,lod).r;
	if(painted_bark_pixel_m<=0.0) {
		vec2 edge=min(fract(uv),1.0-fract(uv));
		if(edge.x<0.025) recess=mix(recess,textureLod(painted_bark_recess_mask,vec2(1.0-fract(uv.x),uv.y),lod).r,0.5*(1.0-smoothstep(0.0,0.025,edge.x)));
		if(edge.y<0.025) recess=mix(recess,textureLod(painted_bark_recess_mask,vec2(uv.x,1.0-fract(uv.y)),lod).r,0.5*(1.0-smoothstep(0.0,0.025,edge.y)));
	}
	return recess;
}

float material_depth_height_at(vec3 p,vec3 n) {
	int first=int(round(painted_bark_frames.x)),second=int(round(painted_bark_frames.y));
	float recess=mix(ember_bark_recess_at(p,second,painted_bark_relief_lod.y),ember_bark_recess_at(p,first,painted_bark_relief_lod.x),ember_bark_support_weight(p));
	// Mask zero is EXACT neutral; max recess is half the trace range, inward only.
	return 0.5-0.5*clamp(recess,0.0,1.0);
}

#include "res://shaders/ember_material_parallax.gdshaderinc"

vec3 ember_painted_bark_relief_normal(vec3 p,vec3 n,float amplitude,float footprint) {
	float e=max(max(0.004,footprint*1.25),painted_bark_pixel_m);
	vec3 gradient=vec3(
		material_depth_height_at(p+vec3(e,0,0),n)-material_depth_height_at(p-vec3(e,0,0),n),
		material_depth_height_at(p+vec3(0,e,0),n)-material_depth_height_at(p-vec3(0,e,0),n),
		material_depth_height_at(p+vec3(0,0,e),n)-material_depth_height_at(p-vec3(0,0,e),n))/(2.0*e);
	return normalize(n-amplitude*(gradient-n*dot(gradient,n)));
}
