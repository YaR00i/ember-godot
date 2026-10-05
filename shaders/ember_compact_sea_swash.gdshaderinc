uniform float sea_swash_available = 0.0;
uniform sampler2D sea_swash_info : filter_nearest, repeat_disable;
uniform sampler2D sea_swash_state : filter_linear, repeat_disable;
uniform vec2 sea_swash_origin = vec2(0.0);
uniform vec2 sea_swash_extent = vec2(1.0);

vec4 coastal_info(vec2 world_point) {
	vec2 uv = (world_point - sea_swash_origin) / sea_swash_extent;
	if (sea_swash_available < 0.5 || any(lessThan(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) { return vec4(0.0); }
	return texture(sea_swash_info, uv);
}

vec4 coastal_state(vec2 world_point) {
	vec2 uv = (world_point - sea_swash_origin) / sea_swash_extent;
	if (sea_swash_available < 0.5 || any(lessThan(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) { return vec4(0.0); }
	return texelFetch(sea_swash_state, ivec2(floor(world_point - sea_swash_origin)), 0);
}

float coastal_surface(vec2 world_point) {
	vec2 uv = (world_point - sea_swash_origin) / sea_swash_extent;
	return textureLod(sea_swash_state, uv, 0.0).r;
}
