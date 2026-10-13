// Optional binding for the existing terrain renderer. Any paired material
// can supply these textures/slots; Source and physical height remain owners.
uniform bool material_depth_enabled = false;
uniform sampler2D material_depth_height : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D material_depth_coverage : filter_linear, repeat_disable;
uniform float material_depth_amplitude_m : hint_range(0.0, 0.08, 0.001) = 0.04;
uniform int material_depth_steps : hint_range(8, 64, 1) = 32;
uniform float material_depth_fade_near_m = 6.0;
uniform float material_depth_fade_far_m = 14.0;
uniform ivec2 material_depth_slots = ivec2(1, 2);
uniform vec2 material_depth_origin_m = vec2(0.0);
uniform vec3 material_depth_sun_direction = vec3(0.4, 0.8, 0.2);
uniform bool material_depth_shadows = true;
varying float material_depth_light;
varying float material_depth_lod;

float material_depth_span() {
	// One scale owner for colour and height: the bound material Pattern.
	return max(texelFetch(png_lookup, ivec2(material_depth_slots.x,0), 0).g, 0.125);
}

float material_depth_weight(vec3 p) {
	vec2 cell = (p.xz - material_depth_origin_m) * 16.0;
	ivec2 lo = ivec2(floor(cell));
	vec2 t = fract(cell);
	ivec2 last = textureSize(material_depth_coverage, 0) - ivec2(1);
	float a = texelFetch(material_depth_coverage, clamp(lo, ivec2(0), last), 0).r;
	float b = texelFetch(material_depth_coverage, clamp(lo + ivec2(1, 0), ivec2(0), last), 0).r;
	float c = texelFetch(material_depth_coverage, clamp(lo + ivec2(0, 1), ivec2(0), last), 0).r;
	float d = texelFetch(material_depth_coverage, clamp(lo + ivec2(1), ivec2(0), last), 0).r;
	// The same diagonal/interpolation as the existing smooth mesh.
	return clamp(t.x + t.y <= 1.0 ? a + (b-a)*t.x + (c-a)*t.y : d + (c-d)*(1.0-t.x) + (b-d)*(1.0-t.y), 0.0, 1.0);
}

float material_depth_tile(vec2 uv) {
	bool periodic = texelFetch(png_lookup, ivec2(material_depth_slots.x,0), 0).a > 0.5;
	vec2 blend = ember_texture_seam_blend(uv, periodic);
	float a = textureLod(material_depth_height, uv, material_depth_lod).r;
	if (blend.x>0.0) a=mix(a,textureLod(material_depth_height,uv+vec2(0.5,0.0),material_depth_lod).r,blend.x);
	if (blend.y>0.0) {
		float b=textureLod(material_depth_height,uv+vec2(0.0,0.5),material_depth_lod).r;
		if (blend.x>0.0) b=mix(b,textureLod(material_depth_height,uv+vec2(0.5),material_depth_lod).r,blend.x);
		a=mix(a,b,blend.y);
	}
	return a;
}

float material_depth_height_at(vec3 p, vec3 n) {
	vec3 tile = ember_texture_coordinates(p, material_depth_span());
	vec3 w = ember_texture_axis_weights(n);
	float solid = 0.0;
	if(w.x>0.00001) solid+=material_depth_tile(tile.zy)*w.x;
	if(w.y>0.00001) solid+=material_depth_tile(tile.xz)*w.y;
	if(w.z>0.00001) solid+=material_depth_tile(tile.xy)*w.z;
	return mix(0.5, solid, material_depth_weight(p));
}

vec3 material_depth_albedo(vec3 p, vec3 n) {
	return mix(slot_albedo_at(material_depth_slots.y, p, n), slot_albedo_at(material_depth_slots.x, p, n), material_depth_weight(p));
}

#include "res://shaders/ember_material_parallax.gdshaderinc"
