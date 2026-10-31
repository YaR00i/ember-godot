shader_type spatial;
render_mode cull_disabled, specular_disabled;

// The companion's palette and six soft bands, driven by scene lights/shadows.
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
	float diffuse = clamp(dot(normalize(NORMAL), LIGHT) * 0.5 + 0.5 + shade_shift * 0.18, 0.0, 1.0);
	float feather = mix(0.055, 0.012, clamp(shade_toony, 0.0, 1.0));
	float band = 0.0;
	for (int i = 1; i < 6; i++) {
		band += smoothstep(float(i) / 6.0 - feather, float(i) / 6.0 + feather, diffuse);
	}
	band /= 5.0;
	vec3 shade = mix(vec3(1.0), shade_factor / max(base_factor.rgb, vec3(0.001)), shade_blend);
	shade *= (1.0 - extra_shade) * mix(vec3(1.0), shadow_tint, 0.7);
	vec3 ramp = mix(vec3(1.0), shade, clamp((1.0 - band) * shadow_strength, 0.0, 1.0));
	ramp *= mix(0.4, 1.0, band);
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	float edge = pow(rim, mix(2.0, 0.7, hoshi_edge_width));
	// Both accents disappear with the occluded light; no glowing silhouette in shade.
	vec3 accent = vec3(rim * rim_strength) + hoshi_edge_color * edge * hoshi_edge_strength * 0.25;
	DIFFUSE_LIGHT += (ramp + accent) * ATTENUATION * LIGHT_COLOR * direct_strength / PI;
}
