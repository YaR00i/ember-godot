shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

uniform sampler2D height_field : filter_linear, repeat_disable;
uniform sampler2D density_field : filter_linear, repeat_disable;
uniform sampler2D ground_color : source_color, filter_linear, repeat_disable;
uniform sampler2D painted_grass : source_color, filter_linear_mipmap, repeat_enable;
uniform float paint_period = 4.0;
uniform sampler2D flower_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float sample_count = 1024.0;
uniform float size_m = 1000.0;
uniform float reach = 32.0;
uniform float width_scale=1.0;
uniform float height_scale=1.0;
uniform float gloss=0.4;
uniform float wind_amount=1.0;
uniform float wind_speed=1.0;
uniform vec2 wind_direction=vec2(1.,0.);
uniform vec4 tint_color : source_color = vec4(1.);
uniform float tint_mix=0.;
uniform bool sun_shadows=true;
uniform float patch_mix=0.;
uniform float patch_size=2.;
varying vec3 pigment;
varying float leaf_tip;

void vertex() {
	vec2 root_xz = MODEL_MATRIX[3].xz;
	vec2 uv = root_xz / size_m + vec2(0.5 / sample_count);
	float h = textureLod(height_field, uv, 0.0).r;
	vec2 density = textureLod(density_field, uv, 0.0).rg;
#ifdef FLOWERS
	float chance = density.g;
#else
	float chance = density.r;
	float field=0.5+0.5*sin(root_xz.x/patch_size*2.1+cos(root_xz.y/patch_size))*cos(root_xz.y/patch_size*2.0);
	chance=mix(chance,step(field,chance),patch_mix);
#endif
	float random = fract(sin(dot(floor(root_xz * 31.0), vec2(12.9898, 78.233))) * 43758.5453);
	float fade = 1.0 - smoothstep(reach * 0.72, reach, distance(CAMERA_POSITION_WORLD.xz, root_xz));
	if (random >= chance || any(lessThan(root_xz, vec2(0.0))) || any(greaterThanEqual(root_xz, vec2(size_m)))) {
		VERTEX = vec3(0.0);
	} else {
#ifndef FLOWERS
		VERTEX *= vec3(2.4*width_scale,2.6*height_scale,2.4*width_scale) * mix(0.85,1.18,random);
#endif
		VERTEX *= fade;
		vec2 world_wind=wind_direction;
		vec2 local_wind=vec2(dot(MODEL_MATRIX[0].xz,world_wind),dot(MODEL_MATRIX[2].xz,world_wind));
		VERTEX.xz += local_wind*sin(TIME * wind_speed * 1.75 + root_xz.x * 0.37 + root_xz.y * 0.55) * VERTEX.y * 0.16*wind_amount;
	}
	// Instance bases rotate about Y and have unit scale, so height is in metres.
	VERTEX.y += h;
	pigment = textureLod(ground_color, uv, 0.0).rgb * mix(0.80,1.24,random);
#ifndef FLOWERS
	vec3 paint = textureLod(painted_grass, root_xz / paint_period, 2.0).rgb;
	float tip = clamp(VERTEX.y - h, 0.0, 0.4) * 2.5;
	leaf_tip=tip;
	pigment = mix(mix(pigment,paint,0.80),tint_color.rgb,tint_mix) * mix(vec3(0.70,0.81,0.63),vec3(1.50,1.45,1.02),tip);
#endif
	NORMAL = vec3(0.,1.,0.);
}
#ifndef FLOWERS
void light() {
	float shade=LIGHT_IS_DIRECTIONAL && !sun_shadows ? 1. : ATTENUATION;
	DIFFUSE_LIGHT+=LIGHT_COLOR*shade*max(dot(NORMAL,LIGHT),0.)/PI;
	SPECULAR_LIGHT+=LIGHT_COLOR*shade*gloss*mix(0.12,1.,leaf_tip)*pow(max(dot(-LIGHT,VIEW),0.),8.);
}
#endif

void fragment() {
	ALBEDO = pigment;
#ifdef FLOWERS
	vec4 atlas = texture(flower_atlas, UV);
	ALBEDO = atlas.rgb;
	ALPHA = atlas.a;
	ALPHA_SCISSOR_THRESHOLD = 0.35;
#endif
	ROUGHNESS = 0.92;
}
