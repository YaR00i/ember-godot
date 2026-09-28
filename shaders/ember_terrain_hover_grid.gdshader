shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back, blend_mix;

uniform vec2 fade_center;
uniform float brush_radius = 8.0;
uniform float fade_radius = 24.0;
uniform bool square_brush = true;
uniform vec2 selected_origin;
uniform float selected_size = 8.0;
uniform float subblock_size = 8.0;
uniform float block_size = 16.0;

varying vec2 terrain_xz;
varying vec3 terrain_normal;

void vertex() {
	terrain_xz = VERTEX.xz;
	terrain_normal = NORMAL;
}

float grid_line(vec2 position, float spacing, float width_px) {
	vec2 phase = mod(position, vec2(spacing));
	vec2 distance_to_line = min(phase, vec2(spacing) - phase);
	vec2 pixel = max(fwidth(position) * width_px, vec2(0.045));
	vec2 line = vec2(1.0) - smoothstep(vec2(0.0), pixel, distance_to_line);
	return max(line.x, line.y);
}

void fragment() {
	if (terrain_normal.y < 0.9) {
		discard;
	}
	vec2 delta = abs(terrain_xz - fade_center);
	float distance_to_brush = square_brush ? max(delta.x, delta.y) : length(delta);
	if (distance_to_brush >= fade_radius) {
		discard;
	}
	float fade = 1.0 - smoothstep(brush_radius, fade_radius, distance_to_brush);
	float subblock = grid_line(terrain_xz, subblock_size, 1.4);
	float block = grid_line(terrain_xz, block_size, 1.6);
	float white_alpha = max(subblock * 0.57, block * 0.82);

	vec2 from_start = terrain_xz - selected_origin;
	vec2 from_end = selected_origin + vec2(selected_size) - terrain_xz;
	float inside = step(0.0, min(min(from_start.x, from_start.y), min(from_end.x, from_end.y)));
	float edge_distance = min(min(from_start.x, from_start.y), min(from_end.x, from_end.y));
	float pixel_width = max(max(fwidth(terrain_xz.x), fwidth(terrain_xz.y)) * 1.8, 0.06);
	float yellow_edge = inside * (1.0 - smoothstep(0.0, pixel_width, edge_distance));
	float yellow_alpha = max(inside * 0.16, yellow_edge * 0.98);
	float alpha = max(white_alpha, yellow_alpha) * fade;
	if (alpha <= 0.001) {
		discard;
	}
	ALBEDO = mix(vec3(1.0), vec3(1.0, 0.84, 0.28), clamp(yellow_alpha * 1.6, 0.0, 1.0));
	ALPHA = alpha;
}
