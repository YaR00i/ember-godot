shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec3 wake_shadow : source_color = vec3(0.42, 0.86, 0.82);
uniform vec3 wake_color : source_color = vec3(0.88, 1.0, 0.93);
uniform float alpha_scale : hint_range(0.0, 1.0) = 0.58;
uniform float animation_fps : hint_range(0.0, 8.0, 0.25) = 3.0;
varying vec3 wake_world_position;


void vertex() {
	wake_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	float frame = floor(TIME * animation_fps);
	float pulse = floor((sin(frame * 0.22 + wake_world_position.x * 0.11 + wake_world_position.z * 0.13) * 0.5 + 0.5) * 3.0) / 2.0;
	ALBEDO = mix(wake_shadow, wake_color, 0.68 + pulse * 0.20);
	EMISSION = wake_color * 0.018;
	ALPHA = COLOR.a * alpha_scale;
}
