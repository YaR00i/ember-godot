// Optional surface-only LAB binding on the existing voxel object shader.
// RGBA is derived from the Recipe's support frames, palette and stroke contour.
uniform bool bark_study_enabled = false;
uniform bool bark_study_pixel = false;
uniform sampler3D bark_study_field : source_color, filter_linear, repeat_disable;
uniform vec3 bark_study_size_m = vec3(1.0);
uniform vec3 bark_study_base : source_color = vec3(0.46, 0.31, 0.22);
uniform float bark_study_pixel_m = 0.0625;
uniform float bark_study_paint_mix = 0.80;
uniform float material_depth_amplitude_m = 0.012;
uniform int material_depth_steps = 24;
uniform vec3 material_depth_sun_direction = vec3(0.4, 0.8, 0.2);
uniform bool material_depth_shadows = true;
varying float bark_study_footprint;
varying float bark_study_shadow;

vec4 ember_bark_field(vec3 p) {
	return texture(bark_study_field, p / bark_study_size_m);
}

float material_depth_height_at(vec3 p, vec3 n) {
	// RGBA8 rounds 0.5 up to 128/255 and 0.08 down to 20/255.
	// Restore the intended inward-only limits after that storage quantization.
	return clamp(ember_bark_field(p).a,0.08,0.5);
}

#include "res://shaders/ember_material_parallax.gdshaderinc"

float ember_bark_fade(vec3 p, float view_distance) {
	// Sampling/filter decisions use the original, unsnapped surface footprint.
	return (1.0-smoothstep(0.035,0.12,bark_study_footprint)) * (1.0-smoothstep(6.0,14.0,view_distance));
}

vec3 ember_bark_albedo(vec3 p, vec3 paint) {
	vec3 q = bark_study_pixel ? (floor(p/bark_study_pixel_m)+0.5)*bark_study_pixel_m : p;
	vec4 field = ember_bark_field(q);
	// The source's vertex paint remains a tint, only the optional LAB blends its
	// generated three-tone bark with the corresponding continuous colour field.
	// Voxel Source palette colours are sRGB values in the current mesher's
	// COLOR channel. Match their interpretation to the source_color texture.
	vec3 linear_paint = mix(paint/12.92,pow((paint+0.055)/1.055,vec3(2.4)),greaterThan(paint,vec3(0.04045)));
	vec3 colour = mix(linear_paint,field.rgb,bark_study_paint_mix);
	return mix(colour,bark_study_base, smoothstep(0.04,0.16,bark_study_footprint)*0.55);
}

vec3 ember_bark_normal(vec3 p, vec3 n, float amplitude) {
	float e = 0.025;
	vec3 gradient = vec3(
		material_depth_height_at(p+vec3(e,0,0),n)-material_depth_height_at(p-vec3(e,0,0),n),
		material_depth_height_at(p+vec3(0,e,0),n)-material_depth_height_at(p-vec3(0,e,0),n),
		material_depth_height_at(p+vec3(0,0,e),n)-material_depth_height_at(p-vec3(0,0,e),n))/(2.0*e);
	return normalize(n-amplitude*(gradient-n*dot(gradient,n)));
}
