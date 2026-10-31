shader_type spatial;
render_mode cull_front, specular_disabled;
uniform sampler2D base_texture : source_color, filter_linear_mipmap;
uniform vec3 outline_color : source_color = vec3(0.2,0.16,0.27);
uniform float outline_strength = 0.45;
uniform float outline_width = 0.35;
uniform float alpha_cutoff = 0.5;
void vertex() {
	vec4 clip=PROJECTION_MATRIX*MODELVIEW_MATRIX*vec4(VERTEX,1.0);
	vec3 normal=normalize((MODELVIEW_MATRIX*vec4(NORMAL,0.0)).xyz);
	clip.xy+=normal.xy*(0.6+outline_width*1.4)*2.0/VIEWPORT_SIZE*clip.w;
	POSITION=clip;
}
void fragment() {
	ALBEDO=mix(texture(base_texture,UV).rgb,outline_color,outline_strength);
	ROUGHNESS=1.0;
	SPECULAR=0.0;
	ALPHA=texture(base_texture,UV).a*step(0.001,outline_strength);
	ALPHA_SCISSOR_THRESHOLD=alpha_cutoff;
}
