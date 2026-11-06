shader_type spatial;
render_mode cull_disabled, specular_disabled;

// First Hoshi lighting variant: soft bands and a sun rim gated by scene shadows.
uniform sampler2D base_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 base_factor = vec4(1.0);
uniform vec3 shade_factor = vec3(1.0);
uniform float shade_shift = -0.3;
uniform float shade_toony = 0.8;
uniform float shade_blend = 0.72;
uniform float extra_shade = 0.1;
uniform float alpha_cutoff = 0.5;
uniform float rim_strength = 0.04;
uniform float shadow_strength = 0.73;
uniform vec3 shadow_tint : source_color = vec3(1.0);
uniform vec3 hoshi_edge_color : source_color = vec3(1.0);
uniform float hoshi_edge_strength = 0.08;
uniform float hoshi_edge_width = 0.4;
uniform float direct_strength = 0.72;

uniform float solar_edge_strength : hint_range(0.0, 2.0) = 1.18;
uniform float solar_edge_width : hint_range(0.13, 0.6) = 0.40;

void fragment() {
	vec4 texel = texture(base_texture, UV);
	ALBEDO = texel.rgb * base_factor.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	// Ambient is provided by the map, not a character-following studio lamp.
	ALPHA = texel.a * base_factor.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
}

void light() {
	float facing = dot(normalize(NORMAL), LIGHT);
	float key = smoothstep(-0.07, 0.16, facing);
	float fill = smoothstep(0.42, 0.76, facing);
	vec3 shadow = vec3(0.33, 0.41, 0.53);
	vec3 lit = vec3(0.87, 0.88, 0.90);
	vec3 ramp = mix(shadow, lit, key);
	ramp = mix(ramp, vec3(1.0), fill * 0.35);
	vec3 n = normalize(NORMAL);
	float view_facing = clamp(dot(n, normalize(VIEW)), 0.0, 1.0);
	float silhouette = 1.0 - smoothstep(0.12, solar_edge_width, view_facing);
	float upper = mix(0.30, 1.0, smoothstep(-0.12, 0.42, n.y));
	float facing_sun = smoothstep(0.025, 0.40, dot(n, LIGHT));
	vec3 solar_edge = vec3(1.0, 0.86, 0.60) * silhouette * upper * facing_sun * solar_edge_strength;
	DIFFUSE_LIGHT += (ramp * 0.55 * smoothstep(-0.015, 0.12, facing) + solar_edge) * ATTENUATION * LIGHT_COLOR / PI;
}
