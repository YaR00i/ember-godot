shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

// Thin Surface-mask contact foam. Geometry owns the reliable shoreline;
// the shader only gives the line a quiet pixel-art tone drift.
uniform vec3 foam_color : source_color = vec3(0.90, 1.0, 0.94);
uniform vec3 foam_shadow : source_color = vec3(0.58, 0.90, 0.84);
uniform float alpha_scale : hint_range(0.0, 1.0) = 0.64;
uniform float pixel_density : hint_range(8.0, 32.0, 1.0) = 16.0;
uniform float animation_fps : hint_range(0.0, 6.0, 0.25) = 2.0;

varying vec2 surface_coordinate;


void vertex() {
	surface_coordinate = VERTEX.xz;
}


void fragment() {
	vec2 pixel = floor(surface_coordinate * pixel_density);
	float frame = floor(TIME * animation_fps);
	float drift = sin((pixel.x + pixel.y) * 0.72 + frame * 0.22) * 0.5 + 0.5;
	float stepped = floor(clamp(drift, 0.0, 0.999) * 3.0) / 2.0;
	ALBEDO = mix(foam_shadow, foam_color, 0.68 + stepped * 0.32);
	EMISSION = foam_color * 0.012;
	ALPHA = COLOR.a * alpha_scale * (0.72 + stepped * 0.18);
}
