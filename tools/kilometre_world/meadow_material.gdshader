shader_type spatial;
render_mode cull_disabled;
uniform sampler2D grass_paint : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D zone_color : source_color, filter_linear, repeat_disable;
uniform sampler2D field_height : filter_linear, repeat_disable;
uniform float paint_period = 4.;
uniform float gloss = 0.4;
uniform vec4 tint_color : source_color = vec4(1.);
uniform float tint_mix = 0.;
uniform bool sun_shadows = true;
uniform vec3 field_anchor;
varying vec3 tint;
varying float blade_tip;
varying vec3 ground_normal;
void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	vec2 uv = base.xz/1000.+0.5/1024.;
	vec2 step_uv=vec2(1./1024.,0.);
	float floor_y=textureLod(field_height,uv,0.).r;
	ground_normal=normalize(vec3(textureLod(field_height,uv-step_uv,0.).r-textureLod(field_height,uv+step_uv,0.).r,2.*1000./1024.,
		textureLod(field_height,uv-step_uv.yx,0.).r-textureLod(field_height,uv+step_uv.yx,0.).r));
	tint = textureLod(grass_paint,base.xz/paint_period,1.).rgb * clamp(textureLod(zone_color,uv,0.).g*2.+0.55,0.7,1.35);
	tint=mix(tint,tint_color.rgb,tint_mix);
	blade_tip = clamp(VERTEX.y/0.17,0.,1.);
	VERTEX *= 1.-smoothstep(29.,40.,distance(base.xz,field_anchor.xz));
	VERTEX.y+=(floor_y-base.y)/length(MODEL_MATRIX[1].xyz);
}
void fragment() {
	ALBEDO = tint*mix(vec3(0.83,0.86,0.75),vec3(1.27,1.24,1.05),blade_tip);
	ROUGHNESS=0.65;
}
void light() {
	DIFFUSE_LIGHT+=LIGHT_COLOR*ATTENUATION*max(dot(NORMAL,LIGHT),0.)/PI;
}
