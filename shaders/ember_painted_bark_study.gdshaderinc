// A colour-artwork trial on the restored smooth LAB geometry. Height remains
// independent: no luminance-derived depth and no procedural brown cloud field.
uniform bool painted_bark_enabled = true;
uniform sampler2D painted_bark_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 painted_bark_tint : source_color = vec3(1.0);
uniform float painted_bark_strength = 1.0;
uniform bool painted_bark_source_paint = false;
uniform vec3 painted_bark_paint_reference = vec3(0.28314874,0.11697067,0.05780543);
uniform sampler2D painted_bark_supports : filter_nearest, repeat_disable;
uniform float painted_bark_period_m = 3.0;
// Derived voxel look only; zero preserves the accepted smooth material exactly.
uniform float painted_bark_pixel_m = 0.0;

vec4 ember_bark_atlas_texture(sampler2D artwork,vec2 uv) {
	vec2 dx=dFdx(uv), dy=dFdy(uv);
	// atan's circumference seam must not turn a tiny pixel footprint into a
	// whole-atlas mip footprint. Longitudinal derivatives stay unwrapped.
	dx.x=fract(dx.x+0.5)-0.5;dy.x=fract(dy.x+0.5)-0.5;
	vec4 colour=textureGrad(artwork,uv,dx,dy);
	// Narrow wrap treatment for the illustrated atlas's edge, preserving its
	// crisp interior strokes. It does not blend half a tile over the whole face.
	vec2 edge=min(fract(uv),1.0-fract(uv));
	if(edge.x<0.025) {
		vec2 opposite=vec2(1.0-fract(uv.x),uv.y);
		colour=mix(colour,textureGrad(artwork,opposite,dx,dy),0.5*(1.0-smoothstep(0.0,0.025,edge.x)));
	}
	if(edge.y<0.025) {
		vec2 opposite=vec2(uv.x,1.0-fract(uv.y));
		colour=mix(colour,textureGrad(artwork,opposite,dx,dy),0.5*(1.0-smoothstep(0.0,0.025,edge.y)));
	}
	return colour;
}

// xy is continuous UV for filtering; zw is the same existing voxel sample grid.
vec4 ember_bark_support_coordinates(vec3 p,int index) {
	vec4 start=texelFetch(painted_bark_supports,ivec2(0,index),0);
	vec4 axis=texelFetch(painted_bark_supports,ivec2(1,index),0);
	vec4 u=texelFetch(painted_bark_supports,ivec2(2,index),0);
	vec4 v=texelFetch(painted_bark_supports,ivec2(3,index),0);
	vec3 relative=p-start.xyz;
	float projection=clamp(dot(relative,axis.xyz),0.0,start.w);
	vec3 radial=relative-axis.xyz*projection;
	float radius=max(0.65/16.0,mix(axis.w,u.w,projection/start.w));
	vec2 uv=vec2(atan(dot(radial,v.xyz),dot(radial,u.xyz))/6.28318530718+1.0,-(v.w+projection)/painted_bark_period_m);
	if(dot(radial,radial)<radius*radius*0.15 && (projection<0.015 || projection>start.w-0.015)) {
		uv=vec2(dot(relative,u.xyz),dot(relative,v.xyz))/painted_bark_period_m+0.5;
	}
	vec2 discrete=uv;
	if (painted_bark_pixel_m>0.0) {
		// Quantize sample locations on the Source grid, keep the continuous UV
		// derivatives for stable filtering as the camera moves and recedes.
		vec3 q=(floor(p/painted_bark_pixel_m+vec3(0.0001))+0.5)*painted_bark_pixel_m-start.xyz;
		float along=clamp(dot(q,axis.xyz),0.0,start.w);
		vec3 r=q-axis.xyz*along;
		discrete=vec2(atan(dot(r,v.xyz),dot(r,u.xyz))/6.28318530718+1.0,-(v.w+along)/painted_bark_period_m);
		if(dot(r,r)<radius*radius*0.15 && (along<0.015 || along>start.w-0.015)) {
			discrete=vec2(dot(q,u.xyz),dot(q,v.xyz))/painted_bark_period_m+0.5;
		}
	}
	return vec4(uv,discrete);
}

vec3 ember_bark_support_sample(vec3 p,int index) {
	vec4 coords=ember_bark_support_coordinates(p,index);
	if(painted_bark_pixel_m>0.0) {
		vec2 dx=dFdx(coords.xy),dy=dFdy(coords.xy);
		dx.x=fract(dx.x+0.5)-0.5;dy.x=fract(dy.x+0.5)-0.5;
		return textureGrad(painted_bark_albedo,coords.zw,dx,dy).rgb;
	}
	return ember_bark_atlas_texture(painted_bark_albedo,coords.xy).rgb;
}

float ember_bark_support_distance(vec3 p,int index) {
	vec4 start=texelFetch(painted_bark_supports,ivec2(0,index),0);
	vec4 axis=texelFetch(painted_bark_supports,ivec2(1,index),0);
	float r1=texelFetch(painted_bark_supports,ivec2(2,index),0).w;
	vec3 relative=p-start.xyz;
	float projection=clamp(dot(relative,axis.xyz),0.0,start.w);
	vec3 radial=relative-axis.xyz*projection;
	float radius=max(0.65/16.0,mix(axis.w,r1,projection/start.w));
	return dot(radial,radial)/(radius*radius);
}

float ember_bark_support_weight(vec3 p) {
	int first=int(round(painted_bark_frames.x)), second=int(round(painted_bark_frames.y));
	float a=ember_bark_support_distance(p,first),b=ember_bark_support_distance(p,second);
	return first==second?1.0:smoothstep(-0.20,0.20,b-a);
}

vec3 ember_painted_bark_colour(vec3 p, vec3 paint) {
	int first=int(round(painted_bark_frames.x)), second=int(round(painted_bark_frames.y));
	float weight=ember_bark_support_weight(p);
	vec3 colour=mix(ember_bark_support_sample(p,second),ember_bark_support_sample(p,first),weight);
	vec3 linear_paint=mix(paint/12.92,pow((paint+0.055)/1.055,vec3(2.4)),greaterThan(paint,vec3(0.04045)));
	if (painted_bark_source_paint) colour*=clamp(linear_paint/max(painted_bark_paint_reference,vec3(0.00001)),vec3(0.0),vec3(4.0));
	return mix(linear_paint,colour*painted_bark_tint,painted_bark_strength);
}

#ifdef EMBER_OBJECT_PAINTED_BARK_RELIEF_STUDY
#include "res://shaders/ember_painted_bark_relief.gdshaderinc"
#endif
