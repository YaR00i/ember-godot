shader_type spatial;
render_mode cull_disabled;

uniform sampler2D leaf_paint : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 leaf_tint : source_color = vec4(0.898, 0.933, 0.831, 1.0);
uniform float gap_coverage : hint_range(0.0, 1.0) = 0.66;

float cell_random(vec2 cell) {
	vec3 mixed = fract(cell.xyx * vec3(0.1031, 0.1030, 0.0973));
	mixed += dot(mixed, mixed.yzx + 33.33);
	return fract((mixed.x + mixed.y) * mixed.z);
}

void fragment() {
	// Mesh UVs are measured in meters on the side and across the top.
	vec2 cell_position = UV * 7.0 + 0.54 * sin(UV.yx * vec2(9.3, 7.7))
		+ 0.32 * sin(UV * vec2(19.3, 12.7));
	vec2 cell = floor(cell_position);
	float seed = cell_random(cell + vec2(17.0, 2.0));
	float aperture = mix(0.17, 0.32, cell_random(cell + vec2(3.0, 11.0)));
	vec2 jitter = vec2(cell_random(cell), cell_random(cell + vec2(9.0, 4.0))) * 2.0 - 1.0;
	vec2 from_gap = fract(cell_position) - 0.5 - jitter * (0.47 - aperture);
	float tilt = (seed - 0.5) * 1.4;
	from_gap.x += from_gap.y * tilt;
	float contour = length(from_gap * vec2(1.0, 1.24))
		+ 0.038 * sin(from_gap.x * 32.0 + seed * 9.0) * sin(from_gap.y * 27.0);
	float cut = step(1.0 - gap_coverage, seed) * (1.0 - step(aperture, contour));
	ALPHA = 1.0 - cut;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = texture(leaf_paint, UV).rgb * leaf_tint.rgb * COLOR.rgb;
	ROUGHNESS = 0.85;
}
