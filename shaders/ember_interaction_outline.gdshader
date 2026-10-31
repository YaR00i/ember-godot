shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, depth_draw_never;
stencil_mode read, compare_not_equal, 64;

uniform vec4 outline_color : source_color = vec4(1.0, 0.84, 0.40, 1.0);
uniform float outline_pixels : hint_range(1.0, 5.0) = 2.5;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_normal = MODELVIEW_NORMAL_MATRIX * NORMAL;
	vec2 direction = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy;
	direction /= max(length(direction), 0.001);
	clip.xy += direction * outline_pixels * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
