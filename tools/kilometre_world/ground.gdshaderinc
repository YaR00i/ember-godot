uniform sampler2D ember_color : source_color, filter_linear, repeat_disable;
uniform sampler2D surface_weights : filter_linear, repeat_disable;
uniform sampler2D grass_paint : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_paint : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_paint : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grass_period;
uniform float stone_period;
uniform float sand_period;
uniform float waterline;
uniform bool has_weights = false;

vec3 ground_paint(vec3 p, vec3 n) {
	vec2 uv = p.xz / 1000.0 + vec2(0.5/1024.0);
	vec3 broad = texture(ember_color,uv).rgb;
	vec2 weights = texture(surface_weights,uv).rg;
	if (!has_weights) {
		weights = vec2(smoothstep(0.10,0.28,1.0-n.y),1.0-smoothstep(0.0,1.8,p.y-waterline));
	}
	vec3 grass = texture(grass_paint,p.xz/grass_period).rgb;
	vec3 stone = texture(stone_paint,p.xz/stone_period).rgb;
	vec3 sand = texture(sand_paint,p.xz/sand_period).rgb;
	vec3 pigment=mix(mix(grass,stone,weights.r),sand,weights.g) * clamp(broad.g*2.0+0.55,0.7,1.35);
	if(abs(p.y-bank_level)<0.45 && bank_runup_m>0.0) {
		float seconds=bank_test_seconds<0. ? TIME : bank_test_seconds;
		float wash=max(bank_wave(p.xz,seconds).x,bank_wave(p.xz,seconds-1.1).x)*bank_runup_m;
		pigment*=mix(1.,0.69,smoothstep(0.,0.055,bank_level+wash-p.y));
	}
	return pigment;
}
