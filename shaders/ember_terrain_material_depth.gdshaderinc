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
#ifdef EMBER_TERRAIN_BANK_DEPTH
#define EMBER_MATERIAL_BANK_DEPTH
#endif
#ifdef EMBER_SOLID_DEPTH
#define EMBER_MATERIAL_BANK_DEPTH
#endif
#ifdef EMBER_MATERIAL_BANK_DEPTH
uniform bool material_depth_bank_enabled = false;
uniform sampler2DArray terrain_depth_bank : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D terrain_depth_profiles : filter_nearest, repeat_disable;
uniform float terrain_depth_world_unit = 16.0;
#endif
#ifdef EMBER_TERRAIN_BANK_DEPTH
uniform int terrain_world_look = 0;
#endif
#ifdef EMBER_SOLID_DEPTH
// Solid hulls (detailed look): no new varyings (the budget is full). Both values are written only in
// fragment(); the rock material never reads painterly_weights.x / painterly_blade_height.
#define material_depth_light painterly_weights.x
#define material_depth_lod painterly_blade_height
uniform mat4 solid_depth_world_to_local = mat4(1.0);
#else
varying float material_depth_light;
#ifdef EMBER_TERRAIN_BANK_DEPTH
// Ground never uses the blade-root varying in fragment/light. Reuse it for
// packed palette/LOD, as the existing solid-depth path does.
#define material_depth_lod painterly_blade_height
#else
varying float material_depth_lod;
#endif
#endif

#ifdef EMBER_TERRAIN_SECONDARY_DEPTH
// One shared ray search, with one coverage-selected material input per fragment.
uniform bool material_depth_secondary_enabled = false;
uniform sampler2D material_depth_secondary_height : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D material_depth_secondary_coverage : filter_linear, repeat_disable;
uniform ivec2 material_depth_secondary_slots = ivec2(1, 2);
uniform float material_depth_secondary_amplitude_m = 0.008;
uniform vec3 material_depth_secondary_sun_direction = vec3(0.4, 0.8, 0.2);
// Nonnegative LOD = primary; -(LOD+1) = secondary. This packs the profile bit
// into an existing fragment/light value instead of exceeding the varying limit.
#endif

float material_depth_mip() {
#ifdef EMBER_MATERIAL_BANK_DEPTH
	if(material_depth_bank_enabled)return mod(material_depth_lod,16.0);
#endif
#ifdef EMBER_TERRAIN_SECONDARY_DEPTH
	if(material_depth_lod<0.0)return -material_depth_lod-1.0;
#endif
	return material_depth_lod;
}

ivec2 material_depth_current_slots() {
#ifdef EMBER_MATERIAL_BANK_DEPTH
	if(material_depth_bank_enabled)return ivec2(int(floor(material_depth_lod/16.0)));
#endif
#ifdef EMBER_TERRAIN_SECONDARY_DEPTH
	if(material_depth_lod<0.0)return material_depth_secondary_slots;
#endif
	return material_depth_slots;
}

float material_depth_mask_pixel(ivec2 p) {
#ifdef EMBER_TERRAIN_SECONDARY_DEPTH
	if(material_depth_lod<0.0)return texelFetch(material_depth_secondary_coverage,p,0).r;
#endif
	return texelFetch(material_depth_coverage,p,0).r;
}

float material_depth_tile_pixel(vec2 uv) {
#ifdef EMBER_TERRAIN_BANK_DEPTH
	if (terrain_world_look == 2) uv = ember_texture_cell_coordinates(vec3(uv, 0.0)).xy;
#endif
#ifdef EMBER_MATERIAL_BANK_DEPTH
	if(material_depth_bank_enabled) {
	float layer=max(texelFetch(terrain_depth_profiles,ivec2(material_depth_current_slots().x,0),0).r-1.0,0.0);
	return textureLod(terrain_depth_bank,vec3(uv,layer),material_depth_mip()).r;
	}
#endif
#ifdef EMBER_TERRAIN_SECONDARY_DEPTH
	if(material_depth_lod<0.0)return textureLod(material_depth_secondary_height,uv,material_depth_mip()).r;
#endif
	return textureLod(material_depth_height,uv,material_depth_lod).r;
}

int material_depth_image_size() {
#ifdef EMBER_MATERIAL_BANK_DEPTH
	if(material_depth_bank_enabled)return textureSize(terrain_depth_bank,0).x;
#endif
#ifdef EMBER_TERRAIN_SECONDARY_DEPTH
	if(material_depth_lod<0.0)return textureSize(material_depth_secondary_height,0).x;
#endif
	return textureSize(material_depth_height,0).x;
}

float material_depth_span() {
	// One scale owner for colour and height: the bound material Pattern.
	return max(texelFetch(png_lookup, ivec2(material_depth_current_slots().x,0), 0).g, 0.125);
}

#ifdef EMBER_SOLID_DEPTH
float material_depth_weight(vec3 p) {
	if(material_depth_bank_enabled)return 1.0;
	// A solid may carry several painted materials. The selected profile owns
	// its palette slot, not every face of a layered object.
	return int(round(EMBER_PALETTE_INDEX)) == material_depth_current_slots().x ? 1.0 : 0.0;
}
#else
float material_depth_weight(vec3 p) {
#ifdef EMBER_TERRAIN_BANK_DEPTH
	return 1.0;
#else
	vec2 cell = (p.xz - material_depth_origin_m) * 16.0;
	ivec2 lo = ivec2(floor(cell));
	vec2 t = fract(cell);
	ivec2 last = textureSize(material_depth_coverage, 0) - ivec2(1);
#ifdef EMBER_TERRAIN_SECONDARY_DEPTH
	if(material_depth_lod<0.0)last=textureSize(material_depth_secondary_coverage,0)-ivec2(1);
#endif
	float a = material_depth_mask_pixel(clamp(lo, ivec2(0), last));
	float b = material_depth_mask_pixel(clamp(lo + ivec2(1, 0), ivec2(0), last));
	float c = material_depth_mask_pixel(clamp(lo + ivec2(0, 1), ivec2(0), last));
	float d = material_depth_mask_pixel(clamp(lo + ivec2(1), ivec2(0), last));
	// The same diagonal/interpolation as the existing smooth mesh.
	return clamp(t.x + t.y <= 1.0 ? a + (b-a)*t.x + (c-a)*t.y : d + (c-d)*(1.0-t.x) + (b-d)*(1.0-t.y), 0.0, 1.0);
#endif
}
#endif

float material_depth_tile(vec2 uv) {
	bool periodic = texelFetch(png_lookup, ivec2(material_depth_current_slots().x,0), 0).a > 0.5;
	vec2 blend = ember_texture_seam_blend(uv, periodic);
	float a = material_depth_tile_pixel(uv);
	if (blend.x>0.0) a=mix(a,material_depth_tile_pixel(uv+vec2(0.5,0.0)),blend.x);
	if (blend.y>0.0) {
		float b=material_depth_tile_pixel(uv+vec2(0.0,0.5));
		if (blend.x>0.0) b=mix(b,material_depth_tile_pixel(uv+vec2(0.5)),blend.x);
		a=mix(a,b,blend.y);
	}
	return a;
}

#ifdef EMBER_SOLID_DEPTH
// Detailed look of solid hulls: the same object-local, form-normal mapping as the colour
// (solid_projection_mode 1), so colour, height and normals describe the same features and the depth
// follows the object when it moves, turns or is scaled (solid_depth_world_to_local is set by the prop).
vec3 solid_depth_tile_position(vec3 p) {
	return (solid_depth_world_to_local * vec4(p, 1.0)).xyz * solid_texture_unit_m / (material_depth_span()*solid_pattern_scale);
}

vec3 solid_depth_weights() {
	vec3 w = pow(abs(normalize(solid_form_local)), vec3(solid_blend_sharpness));
	w /= max(dot(w, vec3(1.0)), 0.00001);
	if (solid_facet_bias > 0.0) {
		vec3 wf = pow(abs(normalize(terrain_normal)), vec3(solid_blend_sharpness));
		w = mix(w, wf / max(dot(wf, vec3(1.0)), 0.00001), solid_facet_bias);
	}
	return w;
}

float material_depth_height_at(vec3 p, vec3 n) {
	vec3 tile = solid_depth_tile_position(p);
	vec3 w = solid_depth_weights();
	float solid = 0.0;
	if (w.x > 0.00001) solid += material_depth_tile(tile.zy) * w.x;
	if (w.y > 0.00001) solid += material_depth_tile(tile.xz) * w.y;
	if (w.z > 0.00001) solid += material_depth_tile(tile.xy) * w.z;
#ifdef EMBER_SOLID_MATERIAL_LAYERS
	vec3 local=(solid_depth_world_to_local*vec4(p,1.0)).xyz;
	float face_weight=stone_face_weight();
	if(face_weight>0.0)solid=mix(solid,material_depth_tile(stone_uv(local,material_depth_span())),face_weight);
#endif
	return solid;
}

vec3 material_depth_albedo(vec3 p, vec3 n) {
	int slot = material_depth_current_slots().x;
	vec4 png = texelFetch(png_lookup, ivec2(slot, 0), 0);
	vec3 tile = solid_depth_tile_position(p);
	vec3 w = solid_depth_weights();
	vec3 rgb = vec3(0.0);
	if (w.x > 0.00001) rgb += texture(png_albedo_bank, vec3(tile.zy, png.r - 1.0)).rgb * w.x;
	if (w.y > 0.00001) rgb += texture(png_albedo_bank, vec3(tile.xz, png.r - 1.0)).rgb * w.y;
	if (w.z > 0.00001) rgb += texture(png_albedo_bank, vec3(tile.xy, png.r - 1.0)).rgb * w.z;
#ifdef EMBER_SOLID_MATERIAL_LAYERS
	vec3 local=(solid_depth_world_to_local*vec4(p,1.0)).xyz;
	float face_weight=stone_face_weight();
	if(face_weight>0.0)rgb=mix(rgb,stone_colour(local,png.r-1.0,material_depth_span()),face_weight);
#endif
	vec3 mean = texelFetch(png_mean_lookup, ivec2(slot, 0), 0).rgb;
	return texelFetch(png_tint_lookup, ivec2(slot, 0), 0).rgb * clamp(rgb / max(mean, vec3(0.001)), vec3(0.55), vec3(1.65));
}
#else
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
	ivec2 slots=material_depth_current_slots();
	return mix(slot_albedo_at(slots.y, p, n), slot_albedo_at(slots.x, p, n), material_depth_weight(p));
}
#endif

#ifdef EMBER_SOLID_MATERIAL_LAYERS
#define EMBER_DEPTH_CONTEXT , vec4 stone_depth_edge
#define EMBER_DEPTH_ARGUMENT , stone_depth_edge
#define EMBER_DEPTH_HEIGHT_AT stone_material_depth_height_at
float stone_material_depth_height_at(vec3 p,vec3 n,vec4 stone_depth_edge){
 float amount=stone_weathering_weight();
 if(amount<=0.0)return material_depth_height_at(p,n);
 vec3 local=(solid_depth_world_to_local*vec4(p,1.0)).xyz;
 float carved=0.5-0.48*stone_weathering_coverage(local,stone_depth_edge);
 if(amount>=1.0)return carved;
 return mix(material_depth_height_at(p,n),carved,amount);
}
#endif

#include "res://shaders/ember_material_parallax.gdshaderinc"
