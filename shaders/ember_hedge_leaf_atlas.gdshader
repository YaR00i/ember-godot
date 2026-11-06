shader_type spatial;
render_mode cull_disabled;

uniform sampler2D leaf_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D understory_paint : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 leaf_tint : source_color = vec4(0.86, 0.92, 0.75, 1.0);
uniform float leaf_patch_m : hint_range(0.15, 1.25) = 0.5;
uniform bool autumn = false;
uniform bool understory = false;
uniform vec4 dry_canopy_color : source_color = vec4(0.46, 0.29, 0.17, 1.0);
uniform vec4 dry_canopy_highlight : source_color = vec4(0.73, 0.53, 0.32, 1.0);

float patch_random(vec2 cell) {
	vec3 mixed = fract(cell.xyx * vec3(0.1031, 0.1030, 0.0973));
	mixed += dot(mixed, mixed.yzx + 33.33);
	return fract((mixed.x + mixed.y) * mixed.z);
}

vec4 leaf_group(vec2 tile_uv) {
	vec2 cell = floor(tile_uv);
	vec2 variant = mod(cell + vec2(cell.y, cell.x * 2.0), 2.0);
	vec2 group_uv = fract(tile_uv);
	vec2 grad_x = dFdx(tile_uv);
	vec2 grad_y = dFdy(tile_uv);
	float keep = 1.0;
	if (autumn) {
		vec2 random = vec2(patch_random(cell + vec2(3.0, 7.0)), patch_random(cell + vec2(9.0, 15.0)));
		variant = floor(random * 2.0);
		float angle = patch_random(cell + vec2(13.0, 1.0)) * 6.2831853;
		vec2 axis = vec2(cos(angle), sin(angle));
		mat2 turn = mat2(axis, vec2(-axis.y, axis.x));
		float size = mix(0.88, 1.14, patch_random(cell + vec2(19.0, 5.0)));
		group_uv = turn * (group_uv - 0.5 - (random - 0.5) * 0.16) * size + 0.5;
		grad_x = turn * grad_x * size;
		grad_y = turn * grad_y * size;
		keep = (1.0 - step(0.5, max(abs(group_uv.x - 0.5), abs(group_uv.y - 0.5))))
			* step(0.12, patch_random(cell + vec2(5.0, 11.0)));
		group_uv = clamp(group_uv, vec2(0.0), vec2(1.0));
	}
	vec2 derivative_scale = vec2(0.48);
	if (variant.x != variant.y) {
		group_uv.x = 1.0 - group_uv.x;
		derivative_scale.x = -derivative_scale.x;
	}
	vec2 uv = (variant + mix(vec2(0.02), vec2(0.98), group_uv)) * 0.5;
	vec4 leaf = textureGrad(leaf_atlas, uv, grad_x * derivative_scale, grad_y * derivative_scale);
	leaf.a *= keep;
	return leaf;
}

void fragment() {
	// UV is in meters. The darker layers fill some gaps between the outer leaves.
	vec2 leaf_uv = UV * (0.5 / leaf_patch_m);
	vec4 outer = leaf_group(leaf_uv * 2.0);
	vec2 rotated = mat2(vec2(0.866, 0.5), vec2(-0.5, 0.866)) * leaf_uv;
	vec4 inner = leaf_group(rotated * 1.95 + vec2(0.41, 0.67));
	vec4 deep = vec4(0.0);
	if (!autumn) {
		deep = leaf_group((leaf_uv - rotated * 0.6) * 3.15 + vec2(0.79, 0.28));
	}
	float outer_leaf = step(0.46, outer.a);
	float inner_leaf = step(0.46, inner.a);
	ALPHA = 1.0;
	if (!understory) {
		ALPHA = max(max(outer.a, inner.a), deep.a);
	}
	ALPHA_SCISSOR_THRESHOLD = 0.46;
	vec3 leaves = mix(deep.rgb * 0.74, inner.rgb * 0.86, inner_leaf);
	leaves = mix(leaves, outer.rgb, outer_leaf) * leaf_tint.rgb;
	if (understory) {
		float painted_leaves = texture(understory_paint, UV * 1.4).g;
		vec3 leaf_bed = mix(dry_canopy_color.rgb, dry_canopy_highlight.rgb, smoothstep(0.06, 0.26, painted_leaves));
		leaves = mix(leaf_bed, leaves, 0.68 * max(outer_leaf, inner_leaf));
	}
	ALBEDO = leaves * COLOR.rgb;
	BACKLIGHT = ALBEDO * 0.2;
	EMISSION = ALBEDO * (understory ? 0.16 : 0.075);
	ROUGHNESS = 0.85;
}
