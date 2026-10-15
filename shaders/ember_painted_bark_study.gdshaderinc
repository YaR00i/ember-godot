// A colour-artwork trial on the restored smooth LAB geometry. Height remains
// independent: no luminance-derived depth and no procedural brown cloud field.
uniform bool painted_bark_enabled = true;
uniform sampler2D painted_bark_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 painted_bark_tint : source_color = vec3(1.0);
uniform float painted_bark_strength = 1.0;
uniform sampler2D painted_bark_supports : filter_nearest, repeat_disable;
uniform float painted_bark_period_m = 3.0;

vec3 ember_bark_atlas_sample(vec2 uv) {
	vec2 dx=dFdx(uv), dy=dFdy(uv);
	// atan's circumference seam must not turn a tiny pixel footprint into a
	// whole-atlas mip footprint. Longitudinal derivatives stay unwrapped.
	dx.x=fract(dx.x+0.5)-0.5;dy.x=fract(dy.x+0.5)-0.5;
	vec3 colour=textureGrad(painted_bark_albedo,uv,dx,dy).rgb;
	// Narrow wrap treatment for the illustrated atlas's edge, preserving its
	// crisp interior strokes. It does not blend half a tile over the whole face.
	vec2 edge=min(fract(uv),1.0-fract(uv));
	if(edge.x<0.025) {
		vec2 opposite=vec2(1.0-fract(uv.x),uv.y);
		colour=mix(colour,textureGrad(painted_bark_albedo,opposite,dx,dy).rgb,0.5*(1.0-smoothstep(0.0,0.025,edge.x)));
	}
	if(edge.y<0.025) {
		vec2 opposite=vec2(uv.x,1.0-fract(uv.y));
		colour=mix(colour,textureGrad(painted_bark_albedo,opposite,dx,dy).rgb,0.5*(1.0-smoothstep(0.0,0.025,edge.y)));
	}
	return colour;
}

vec3 ember_bark_support_sample(vec3 p,int index) {
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
	return ember_bark_atlas_sample(uv);
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

vec3 ember_painted_bark_colour(vec3 p, vec3 paint) {
	int first=int(round(painted_bark_frames.x)), second=int(round(painted_bark_frames.y));
	float a=ember_bark_support_distance(p,first),b=ember_bark_support_distance(p,second);
	float weight=first==second?1.0:smoothstep(-0.20,0.20,b-a);
	vec3 colour=mix(ember_bark_support_sample(p,second),ember_bark_support_sample(p,first),weight);
	vec3 linear_paint=mix(paint/12.92,pow((paint+0.055)/1.055,vec3(2.4)),greaterThan(paint,vec3(0.04045)));
	return mix(linear_paint,colour*painted_bark_tint,painted_bark_strength);
}
