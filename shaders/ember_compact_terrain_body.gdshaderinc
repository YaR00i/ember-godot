// Opt-in only for streamed detail MultiMeshes. Ground/objects keep this off.
uniform bool world_detail_fade_enabled = false;
uniform vec3 world_detail_anchor = vec3(0.0);
uniform vec2 world_detail_fade_range = vec2(256.0, 384.0);
#ifdef EMBER_FLOWER_COVER
render_mode cull_disabled;
uniform sampler2D flower_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 flower_tint : source_color = vec4(1.0);
uniform float flower_palette_slot = 0.0;
#else
render_mode cull_back;
#endif

// Palette indices stay in vertex COLOR.a. Artwork can change without remeshing.
uniform sampler2D role_lookup : filter_nearest, repeat_disable;
uniform sampler2D pattern_atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D side_pattern_atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D finish_lookup : filter_nearest, repeat_disable;
uniform sampler2D detail_lookup : filter_nearest, repeat_disable;
uniform sampler2D surface_lookup : filter_nearest, repeat_disable;
uniform bool independent_surface_enabled = false;
uniform bool smooth_surface_enabled = false;
uniform sampler2DArray png_albedo_bank : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D png_lookup : filter_nearest, repeat_disable;
#ifdef EMBER_MATERIAL_COLOUR_PROBE
// Colour-only LAB binding uses the existing PNG owner without turning colour
// into height. Other slots and normal production variants keep the old path.
uniform int colour_probe_slot = -1;
// A pigment-only probe can retain the previous bank layer for optical height.
uniform int colour_probe_height_slot = -1;
uniform vec4 colour_probe_height_png = vec4(0.0);
uniform bool colour_probe_shared_height = false;
#endif
uniform sampler2D png_mean_lookup : filter_nearest, repeat_disable;
uniform sampler2D png_tint_lookup : filter_nearest, repeat_disable;
uniform sampler2D palette_color_lookup : filter_nearest, repeat_disable;
uniform sampler2D roughness_atlas : filter_nearest, repeat_disable;
uniform sampler2D side_roughness_atlas : filter_nearest, repeat_disable;
uniform float texture_span = 64.0;
uniform int toon_steps : hint_range(3, 5) = 4;
uniform float band_floor : hint_range(0.0, 0.5) = 0.19;
uniform float local_light_softness : hint_range(0.0, 1.0) = 1.0;
uniform float terrain_side_fill : hint_range(0.0, 3.0) = 1.2;
uniform int material_light_mode : hint_enum("Previous", "Soft materials", "Toy plastic") = 0;
uniform bool material_gray_preview = false;
uniform bool surface_detail_enabled = true;
uniform float underwater_caustics : hint_range(0.0, 1.0) = 0.0;
uniform bool reflection_pass_enabled = false;
uniform float caustic_water_level = 16.02;
uniform float water_wave_height_voxels = 3.2;
uniform vec2 caustic_sun_offset = vec2(0.31, -0.54);
uniform float wave_speed = 0.42;
uniform float wave_irregularity = 0.85;
uniform float local_bob_strength = 0.45;
uniform float preview_time = -1.0;
uniform float sand_wet_strength = 0.0;
#include "res://shaders/ember_world_anomaly.gdshaderinc"
#include "res://shaders/ember_voxel_light.gdshaderinc"
#include "res://shaders/ember_compact_sea_swash.gdshaderinc"
#include "res://shaders/ember_diorama_light.gdshaderinc"
#include "res://shaders/ember_material_light.gdshaderinc"
#include "res://shaders/ember_terrain_surface_detail.gdshaderinc"
#include "res://shaders/ember_compact_study_wave.gdshaderinc"
#include "res://shaders/ember_material_texture_mapping.gdshaderinc"
#include "res://shaders/ember_painterly_light.gdshaderinc"
varying vec2 painterly_weights;
uniform sampler2D style_rim_lookup : filter_nearest, repeat_disable;
uniform bool style_rim_profiles_enabled = false;
varying float style_rim_weight;
uniform sampler2D grass_light_lookup : filter_nearest, repeat_disable;
uniform bool grass_light_profiles_enabled = false;
varying float grass_profile_weight;
varying vec3 grass_profile_values;
varying vec3 grass_profile_cool;
varying vec3 grass_profile_warm;
// Alpha reuses this varying's spare component for the material span in metres.
varying vec4 grass_profile_shadow;

varying vec3 terrain_position;
varying vec3 terrain_normal;
varying vec3 terrain_world_position;
varying vec3 terrain_world_normal;
varying vec3 texture_projection_normal;
// Opt-in probe for derived solid hulls (default off keeps every other surface unchanged).
// Mode 1: object-local periodic projection chosen by a continuous per-vertex form normal
// (CUSTOM0.xyz) instead of the facet plane; solid_form_rim feeds the same normal to the rim.
uniform int solid_projection_mode = 0;
uniform bool solid_form_rim = false;
uniform float solid_local_unit_m = 1.0;
// Pattern frequency is independent of physical edge widths and depth amplitude.
uniform float solid_pattern_scale = 1.0;
uniform vec3 solid_texture_unit_m = vec3(1.0);
uniform float solid_blend_sharpness : hint_range(2.0, 48.0) = 16.0;
uniform float solid_height_blend : hint_range(0.0, 16.0) = 0.0;
// Share of the facet plane in axis choice: 0 = fully continuous, 1 = facet-only.
uniform float solid_facet_bias : hint_range(0.0, 1.0) = 0.0;
// Rim band for solid hulls: (inner, outer) facing range; default equals the shared rim.
uniform vec2 solid_rim_edge = vec2(0.10, 0.32);
// Cells per model unit for the voxel look: the pattern is read once per voxel (0 = off).
uniform float solid_pixel_cells = 0.0;
// Rim frame: the width (metres) comes from the material (style_rim_lookup alpha); the rim is limited to a
// strip along silhouette edges of solid hulls (CUSTOM1..3), never thinner than solid_rim_min_px pixels.
uniform float solid_rim_min_px = 1.5;
#if defined(EMBER_TERRAIN_BANK_DEPTH) || defined(EMBER_GRASS_COVER)
// Column ground has no solid-hull custom channels. Keep those attributes
// only in the object variant, leaving room for the existing optical depth.
const vec3 solid_edge_dist=vec3(0.0);
const vec3 solid_form_local=vec3(0.0);
#else
varying vec3 solid_edge_dist;
varying vec3 solid_form_local;
#endif
varying float palette_slot;
varying flat vec3 smooth_slots;
#ifdef EMBER_DIORAMA_READABILITY
#include "res://shaders/ember_diorama_readability.gdshaderinc"
#endif
#ifdef EMBER_MATERIAL_LOOK_STUDY
#include "res://shaders/ember_material_look_study.gdshaderinc"
#endif
#ifdef EMBER_BEVEL_STUDY
#include "res://shaders/ember_bevel_light.gdshaderinc"
#endif

#ifdef EMBER_SOLID_MATERIAL_LAYERS
#include "res://shaders/ember_solid_material_layers.gdshaderinc"
#define EMBER_PALETTE_INDEX smooth_slots.x
#else
#define EMBER_PALETTE_INDEX (palette_slot * 255.0)
#endif

void vertex() {
	if (world_detail_fade_enabled) {
		vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float keep = 1.0 - smoothstep(world_detail_fade_range.x, world_detail_fade_range.y, distance(root.xz, world_detail_anchor.xz));
		VERTEX *= keep;
	}
#ifdef EMBER_PAINTERLY_STUDY
	painterly_blade_height = clamp(VERTEX.y / 0.14, 0.0, 1.0);
#endif
	terrain_position = VERTEX;
	ember_anomaly_vertex(VERTEX, NORMAL, MODEL_MATRIX, VERTEX_ID);
	if (ember_anomaly_grass_roots) {
		float weight = ember_anomaly_weight((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
		float shift = ember_anomaly_band_look.y > 1.5 ? INSTANCE_CUSTOM.y : INSTANCE_CUSTOM.x;
		VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(0.0, shift * weight, 0.0);
	}
	terrain_normal = NORMAL;
	terrain_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	terrain_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
#ifdef EMBER_FLOWER_COVER
	// Keep normal local texture UVs; ground pigment/light still uses its existing palette slot.
	palette_slot = flower_palette_slot / 255.0;
	smooth_slots = vec3(flower_palette_slot);
#else
	#ifdef EMBER_SOLID_MATERIAL_LAYERS
	palette_slot = UV2.y;
#else
	palette_slot = COLOR.a;
#endif
	smooth_slots = vec3(UV,UV2.x)*255.0;
#endif
#if !defined(EMBER_TERRAIN_BANK_DEPTH) && !defined(EMBER_GRASS_COVER)
	solid_form_local = CUSTOM0.xyz;
	// Silhouette test per vertex: an edge frames the rim only when this facet faces the camera
	// and the neighbouring facet across that (convex) edge faces away. Meshes without the data
	// (all zero) keep distance 0 = no restriction.
	vec3 edge_distance = CUSTOM1.xyz;
	vec3 neighbour0 = CUSTOM2.xyz;
	vec3 neighbour1 = CUSTOM3.xyz;
	vec3 neighbour2 = vec3(CUSTOM1.w, CUSTOM2.w, CUSTOM3.w);
	if (dot(neighbour0, neighbour0) + dot(neighbour1, neighbour1) + dot(neighbour2, neighbour2) > 0.5) {
		vec3 to_camera = normalize(CAMERA_POSITION_WORLD - terrain_world_position);
		float facing = dot(terrain_world_normal, to_camera);
		edge_distance.x = (facing > 0.0 && dot(MODEL_NORMAL_MATRIX * neighbour0, to_camera) < 0.0) ? edge_distance.x : 1000000.0;
		edge_distance.y = (facing > 0.0 && dot(MODEL_NORMAL_MATRIX * neighbour1, to_camera) < 0.0) ? edge_distance.y : 1000000.0;
		edge_distance.z = (facing > 0.0 && dot(MODEL_NORMAL_MATRIX * neighbour2, to_camera) < 0.0) ? edge_distance.z : 1000000.0;
	}
	solid_edge_dist = edge_distance;
#endif
}

vec2 mirrored_tile(vec2 uv) {
	return 1.0 - abs(fract(uv * 0.5) * 2.0 - 1.0);
}

vec4 artwork_pixel(ivec2 pixel, bool side_artwork) {
	if (side_artwork) {
		return texelFetch(side_pattern_atlas, pixel, 0);
	}
	return texelFetch(pattern_atlas, pixel, 0);
}

vec3 png_colour_sample(vec2 uv,float layer,vec2 uv_dx,vec2 uv_dy) {
#ifdef EMBER_MATERIAL_LOOK_STUDY
	// Use the unquantized footprint: discontinuous cell-centre UV derivatives
	// would choose different mip levels at alternating cell boundaries.
	if (look_study_mode==2) return textureGrad(png_albedo_bank,vec3(uv,layer),uv_dx,uv_dy).rgb;
#endif
	vec3 result = texture(png_albedo_bank,vec3(uv,layer)).rgb;
#ifdef EMBER_DIORAMA_READABILITY
	result = ember_readability_colour(uv,layer,result);
#endif
	return result;
}

vec3 png_tile(vec2 uv,float layer,bool periodic,vec2 uv_dx,vec2 uv_dy) {
	if (periodic) return png_colour_sample(uv,layer,uv_dx,uv_dy);
	vec2 blend=ember_texture_seam_blend(uv,false);
	vec3 a=mix(png_colour_sample(uv,layer,uv_dx,uv_dy),png_colour_sample(uv+vec2(0.5,0.0),layer,uv_dx,uv_dy),blend.x);
	vec3 b=mix(png_colour_sample(uv+vec2(0.0,0.5),layer,uv_dx,uv_dy),png_colour_sample(uv+vec2(0.5),layer,uv_dx,uv_dy),blend.x);
	return mix(a,b,blend.y);
}

vec2 ember_axis_uv(vec3 p, int axis) {
	return axis == 0 ? p.zy : (axis == 1 ? p.xz : p.xy);
}

// Object-local periodic projection. Weights come from a continuous form normal, so both
// facets sharing an edge evaluate the same function there. Two taps (top two axes);
// textureGrad uses derivatives of the continuous local position, not of a switching UV.
vec3 ember_solid_local_rgb(int slot, float layer, float span_m) {
	vec3 local_position = terrain_position;
	vec3 gradient_position = terrain_position * solid_texture_unit_m / (max(span_m, 0.125)*solid_pattern_scale);
	if (solid_pixel_cells > 0.0) {
		// Step slightly inside the voxel behind the face, then use the voxel centre.
		vec3 inward = normalize(solid_form_local) * (0.25 / solid_pixel_cells);
		local_position = (floor((terrain_position - inward) * solid_pixel_cells) + 0.5) / solid_pixel_cells;
	}
	vec3 p = local_position * solid_texture_unit_m / (max(span_m, 0.125)*solid_pattern_scale);
	vec3 dpx = dFdx(gradient_position), dpy = dFdy(gradient_position);
	vec3 w = pow(abs(normalize(solid_form_local)), vec3(solid_blend_sharpness));
	w /= max(dot(w, vec3(1.0)), 0.00001);
	if (solid_facet_bias > 0.0) {
		vec3 wf = pow(abs(normalize(terrain_normal)), vec3(solid_blend_sharpness));
		w = mix(w, wf / max(dot(wf, vec3(1.0)), 0.00001), solid_facet_bias);
	}
	int a0 = w.x >= w.y ? (w.x >= w.z ? 0 : 2) : (w.y >= w.z ? 1 : 2);
	vec3 rest = w;
	rest[a0] = -1.0;
	int a1 = rest.x >= rest.y ? (rest.x >= rest.z ? 0 : 2) : (rest.y >= rest.z ? 1 : 2);
	vec2 g0x = ember_axis_uv(dpx, a0), g0y = ember_axis_uv(dpy, a0);
	vec2 g1x = ember_axis_uv(dpx, a1), g1y = ember_axis_uv(dpy, a1);
	vec3 c0 = textureGrad(png_albedo_bank, vec3(ember_axis_uv(p, a0), layer), g0x, g0y).rgb;
	vec3 c1 = textureGrad(png_albedo_bank, vec3(ember_axis_uv(p, a1), layer), g1x, g1y).rgb;
	float w0 = w[a0], w1 = w[a1];
	if (solid_height_blend > 0.0) {
		// Painted value decides the overlap, so the transition follows brush shapes.
		vec3 luma = vec3(0.2126, 0.7152, 0.0722);
		float mean_l = dot(texelFetch(png_mean_lookup, ivec2(slot, 0), 0).rgb, luma);
		float h0 = w0 + (dot(c0, luma) - mean_l) * solid_height_blend;
		float h1 = w1 + (dot(c1, luma) - mean_l) * solid_height_blend;
		float top = max(h0, h1);
		w0 = max(h0 - (top - 0.15), 0.0001);
		w1 = max(h1 - (top - 0.15), 0.0001);
	}
	vec3 rgb=(c0 * w0 + c1 * w1) / (w0 + w1);
#ifdef EMBER_SOLID_MATERIAL_LAYERS
	float face_weight=stone_face_weight();
	if(face_weight>0.0)rgb=mix(rgb,stone_colour(terrain_position,layer,span_m),face_weight);
#endif
	return rgb;
}

vec3 slot_albedo_at(int slot, vec3 world_position, vec3 world_normal) {
	vec4 png=texelFetch(png_lookup,ivec2(slot,0),0);
	vec3 n=abs(normalize(world_normal));
	if(png.r>0.5) {
		vec3 p=ember_texture_coordinates(world_position,png.g);
		vec3 texture_dx=vec3(0.0),texture_dy=vec3(0.0);
#ifdef EMBER_MATERIAL_LOOK_STUDY
		texture_dx=dFdx(p);texture_dy=dFdy(p);
#ifdef EMBER_TERRAIN_BANK_DEPTH
		// The hit moves discontinuously across relief steps. Keep the texture
		// footprint on the original surface and snap colour like its height.
		texture_dx=dFdx(ember_texture_coordinates(terrain_world_position,png.g));
		texture_dy=dFdy(ember_texture_coordinates(terrain_world_position,png.g));
		if (look_study_mode==2) p=ember_texture_cell_coordinates(p);
#else
		p=ember_texture_coordinates(ember_look_pixel_colour_position(world_position,world_normal),png.g);
#endif
#endif
		vec3 rgb;
		bool periodic=png.a>0.5;
		bool solid_local=periodic && solid_projection_mode==1 && dot(solid_form_local,solid_form_local)>0.0;
		if(periodic)n=abs(texture_projection_normal);
		if(solid_local) {
			rgb=ember_solid_local_rgb(slot,png.r-1.0,png.g);
		}else if(abs(png.b)>3.5 || periodic) {
			vec3 weights=ember_texture_axis_weights(n);
			rgb=vec3(0.0);
			if(weights.x>0.00001)rgb+=png_tile(p.zy,png.r-1.0,periodic,texture_dx.zy,texture_dy.zy)*weights.x;
			if(weights.y>0.00001)rgb+=png_tile(p.xz,png.r-1.0,periodic,texture_dx.xz,texture_dy.xz)*weights.y;
			if(weights.z>0.00001)rgb+=png_tile(p.xy,png.r-1.0,periodic,texture_dx.xy,texture_dy.xy)*weights.z;
		}else{rgb=png_tile(p.xz,png.r-1.0,periodic,texture_dx.xz,texture_dy.xz);}
		vec3 mean=texelFetch(png_mean_lookup,ivec2(slot,0),0).rgb;
		return texelFetch(png_tint_lookup,ivec2(slot,0),0).rgb*clamp(rgb/max(mean,vec3(0.001)),vec3(0.55),vec3(1.65));
	}
	if(texelFetch(role_lookup,ivec2(slot,0),0).r>0.0) {
		vec3 pattern_position=solid_projection_mode==1?terrain_position*solid_texture_unit_m/solid_pattern_scale:terrain_position;
		vec2 position=n.y>0.5?pattern_position.xz:(n.x>0.5?pattern_position.zy:pattern_position.xy);
		vec3 surface=texelFetch(surface_lookup,ivec2(slot,0),0).rgb;
		vec2 uv=mirrored_tile(position/(texture_span*max(surface.r,0.125)/4.0));
		ivec2 pixel=clamp(ivec2(floor(uv*16.0)),ivec2(0),ivec2(15));
		return artwork_pixel(ivec2(pixel.x,slot*16+pixel.y),n.y<0.5).rgb;
	}
	return texelFetch(palette_color_lookup,ivec2(slot,0),0).rgb;
}

vec3 slot_albedo(int slot) {
	return slot_albedo_at(slot, terrain_world_position, terrain_world_normal);
}

// Optional feature of the same renderer. Default materials keep automatic
// fragment depth and do not compile ray marching, samplers or light changes.
#ifdef EMBER_TERRAIN_MATERIAL_DEPTH
#include "res://shaders/ember_terrain_material_depth.gdshaderinc"
#endif

#ifndef EMBER_TERRAIN_CHEAP
vec3 png_relief_tile(vec2 uv,float layer,bool periodic) {
	if (periodic) return textureLod(png_albedo_bank,vec3(uv,layer),5.0).rgb;
	// Blur only the optical height, preserving sharp albedo and avoiding paint grain.
	vec2 f=fract(uv),edge=min(f,vec2(1.0)-f);
	vec2 blend=vec2(1.0)-smoothstep(vec2(0.0),vec2(0.018),edge);
	vec3 rgb=textureLod(png_albedo_bank,vec3(uv,layer),5.0).rgb;
	if(blend.x>0.0)rgb=mix(rgb,textureLod(png_albedo_bank,vec3(uv+vec2(0.5,0.0),layer),5.0).rgb,blend.x);
	if(blend.y>0.0) {
		vec3 other=textureLod(png_albedo_bank,vec3(uv+vec2(0.0,0.5),layer),5.0).rgb;
		if(blend.x>0.0)other=mix(other,textureLod(png_albedo_bank,vec3(uv+vec2(0.5),layer),5.0).rgb,blend.x);
		rgb=mix(rgb,other,blend.y);
	}
	return rgb;
}

float slot_optical_height(int slot, float shared_amplitude) {
#ifdef EMBER_MATERIAL_COLOUR_PROBE
	if(slot==colour_probe_slot)return 0.0;
#ifdef EMBER_TERRAIN_MATERIAL_DEPTH
	if(colour_probe_shared_height && slot==colour_probe_height_slot) {
		return (material_depth_height_at(terrain_world_position,texture_projection_normal)-0.5)*shared_amplitude;
	}
#endif
#endif
	vec4 png=texelFetch(png_lookup,ivec2(slot,0),0);
#ifdef EMBER_MATERIAL_COLOUR_PROBE
	if(slot==colour_probe_height_slot)png=colour_probe_height_png;
#endif
	float amount=texelFetch(finish_lookup,ivec2(slot,0),0).b*0.3;
	if(png.r<0.5 || png.b<0.0 || amount<0.0001)return 0.0;
	vec3 p=ember_texture_coordinates(terrain_world_position,png.g);
	// First heightfield slice follows top artwork; steep sides fade below.
	// Avoid differentiating triplanar weights, which reveals the fine mesh.
	vec3 rgb=png_relief_tile(p.xz,png.r-1.0,png.a>0.5);
	return dot(rgb,vec3(0.2126,0.7152,0.0722))*amount*2.0;
}
#endif

float submerged_side_weight() {
	if (!reflection_pass_enabled) {
		return 0.0;
	}
	float side = 1.0 - abs(terrain_normal.y);
	if (side < 0.5) {
		return 0.0;
	}
	float depth = caustic_water_level - terrain_world_position.y;
	float wave_reach = water_wave_height_voxels * 1.5;
	if (depth > wave_reach + 1.5) {
		return side;
	}
	if (depth < -wave_reach - 0.5) {
		return 0.0;
	}
	float seconds = preview_time >= 0.0 ? preview_time : TIME;
	float surface_y = caustic_water_level + wave_state(
		terrain_world_position.xz / 16.0, seconds).z * water_wave_height_voxels;
	return side * smoothstep(-0.5, 1.5, surface_y - terrain_world_position.y);
}

// 1 on the rim strip along convex hull edges, 0 beyond it (always 1 when the limit is off).

float solid_rim_frame(float width_m) {
	if (width_m <= 0.0) return 1.0;
	float distance_m = min(solid_edge_dist.x, min(solid_edge_dist.y, solid_edge_dist.z)) * solid_local_unit_m;
	float aa = max(fwidth(distance_m), 0.00001);

	float width = max(width_m, solid_rim_min_px * aa);
	return 1.0 - smoothstep(width - aa * 0.5, width + aa * 0.5, distance_m);

}



#include "res://shaders/ember_material_transitions.gdshaderinc"

void fragment() {
#ifdef EMBER_FLOWER_COVER
	// Reject transparent card texels before terrain artwork/light profiles.
	// Keep the same alpha sample and threshold as the final scissor output.
	vec4 flower = texture(flower_atlas, UV);
	if (flower.a < 0.55) discard;
#endif
 // Source-local coordinates on rocks; one metre-scaled world grid on ground/grass.
 vec3 light_origin = solid_projection_mode == 1 ? terrain_position : terrain_world_position;
 bool voxel_anomaly_surface = ember_anomaly_prepared && !ember_anomaly_grass_roots;
#ifdef EMBER_SOLID_DEPTH
 // Artwork keeps its authored reference, but lighting belongs to the morphed
 // surface. Extrapolating from the collapsed reference jumps between stair faces.
 if (solid_projection_mode == 1 && voxel_anomaly_surface)
  light_origin = (solid_depth_world_to_local * vec4(terrain_world_position, 1.0)).xyz;
#endif
 vec3 light_axis = solid_projection_mode == 1 ? terrain_normal : terrain_world_normal;
 vec3 voxel_sample = ember_texel_sample(light_origin, light_origin, light_axis, voxel_light_cell, 0.0);
 float voxel_weight = ember_voxel_light_weight(terrain_world_position);
 voxel_sample.z *= voxel_weight;
 vec3 continuous_view_dx = dFdx(VERTEX), continuous_view_dy = dFdy(VERTEX);
	#ifdef EMBER_BEVEL_STUDY
	bevel_light_mask = 0.0;
	#endif
	texture_projection_normal = ember_texture_surface_normal(terrain_world_position, terrain_world_normal);
	painterly_weights = vec2(0.0);
	style_rim_weight=0.0;
	float rim_width_sum = 0.0;
	grass_profile_weight=0.0;
	grass_profile_values=vec3(0.0);grass_profile_cool=vec3(0.0);grass_profile_warm=vec3(0.0);grass_profile_shadow=vec4(0.0);
	ivec3 painted_slots = smooth_surface_enabled ? ivec3(round(smooth_slots)) : ivec3(int(round(EMBER_PALETTE_INDEX)));
	vec3 painted_blend = smooth_surface_enabled ? max(COLOR.rgb,vec3(0.0)) : vec3(1.0,0.0,0.0);
	painted_blend /= max(dot(painted_blend,vec3(1.0)),0.00001);
#ifdef EMBER_FLOWER_COVER
	// The card vertex path writes flower_palette_slot to all three slots.
	// Resolve its single profile at compile time; generic grass can still mix.
	const int profile_count=1;
	painted_blend=vec3(1.0,0.0,0.0);
#elif defined(EMBER_GRASS_COVER)
	// Cover meshes carry one pigment slot per triangle. They never blend
	// neighbouring terrain layers or need the terrain's transition masks.
	bool single_cover=painted_slots.x==painted_slots.y && painted_slots.y==painted_slots.z;
	int profile_count=single_cover ? 1 : 3;
	if(single_cover)painted_blend=vec3(1.0,0.0,0.0);
	else painted_blend=ember_material_transition_weights(painted_blend,painted_slots,terrain_world_position/16.0,texture_projection_normal);
#else
	painted_blend=ember_material_transition_weights(painted_blend,painted_slots,solid_projection_mode==1 ? terrain_position*solid_texture_unit_m : terrain_world_position/16.0,texture_projection_normal);
	const int profile_count=3;
#endif
	if(painterly_enabled || grass_light_profiles_enabled || style_rim_profiles_enabled) for (int i=0; i<profile_count; i++) {
		float role = texelFetch(role_lookup,ivec2(painted_slots[i],0),0).b * 255.0;
		painterly_weights.x += painted_blend[i] * (abs(role - 1.0) < 0.1 ? 1.0 : 0.0);
		// LAB stone slot is explicit, same slot bound by the existing depth study.
		vec4 rim_profile=style_rim_profiles_enabled ? texelFetch(style_rim_lookup,ivec2(painted_slots[i],0),0).rgba : vec4(0.0);
		painterly_weights.y += painted_blend[i] * (painted_slots[i] == 1 && rim_profile.r<0.5 ? 1.0 : 0.0);
		style_rim_weight += painted_blend[i]*rim_profile.r*rim_profile.g*rim_profile.b;
		rim_width_sum += painted_blend[i]*rim_profile.r*rim_profile.g*rim_profile.b*rim_profile.a;
		if(grass_light_profiles_enabled && abs(role-1.0)<0.1) {
			vec4 settings=texelFetch(grass_light_lookup,ivec2(painted_slots[i],0),0);
			float weight=painted_blend[i]*settings.a;
			grass_profile_weight+=weight;grass_profile_values+=weight*settings.rgb;
			grass_profile_cool+=weight*texelFetch(grass_light_lookup,ivec2(painted_slots[i],1),0).rgb;
			grass_profile_warm+=weight*texelFetch(grass_light_lookup,ivec2(painted_slots[i],2),0).rgb;
			grass_profile_shadow+=weight*texelFetch(grass_light_lookup,ivec2(painted_slots[i],3),0);
		}
	}
	painterly_weights.x *= painterly_grass_enabled ? 1.0 : 0.0;
	if(grass_profile_weight>0.00001) {
		grass_profile_values/=grass_profile_weight;grass_profile_cool/=grass_profile_weight;
		grass_profile_warm/=grass_profile_weight;grass_profile_shadow/=grass_profile_weight;
	}
#ifdef EMBER_TERRAIN_MATERIAL_DEPTH
	DEPTH = FRAGCOORD.z;
	material_depth_light = 1.0;
	float selected_depth_amount=material_depth_amplitude_m;
	bool selected_depth_enabled=material_depth_enabled;
#ifdef EMBER_MATERIAL_BANK_DEPTH
	int dominant=painted_blend.x>=painted_blend.y ? 0 : 1;
	if (painted_blend.z>painted_blend[dominant]) dominant=2;
	int terrain_depth_slot=painted_slots[dominant];
	if(material_depth_bank_enabled) {
	vec4 depth_profile=texelFetch(terrain_depth_profiles,ivec2(terrain_depth_slot,0),0);
	// Pack the palette slot beside LOD in the existing fragment/light value.
	// This preserves the renderer's varying budget.
	material_depth_lod=float(terrain_depth_slot)*16.0;
	selected_depth_amount=depth_profile.g*terrain_depth_world_unit*painted_blend[dominant];
	selected_depth_enabled=material_depth_enabled && depth_profile.r>0.5;
	}
#endif
#ifdef EMBER_TERRAIN_SECONDARY_DEPTH
	material_depth_lod=0.0;
	if(material_depth_secondary_enabled) {
		material_depth_lod=-1.0;
		if(material_depth_weight(terrain_world_position)<=0.00001)material_depth_lod=0.0;
	}
	bool secondary_profile=material_depth_lod<0.0;
	if(secondary_profile) {
		selected_depth_amount=material_depth_secondary_amplitude_m;
		selected_depth_enabled=material_depth_secondary_enabled;
	}
#endif
#ifdef EMBER_SOLID_MATERIAL_LAYERS
 vec4 stone_depth_edge=vec4(0.0,1.0,0.0,1000.0);
 if(stone_weathering_weight()>0.0){
  stone_depth_edge=stone_edge(terrain_position);
  selected_depth_amount*=mix(1.0,0.9,stone_weathering_weight());
 }
#endif
	vec3 depth_footprint=fwidth(terrain_world_position / material_depth_span());
#ifdef EMBER_MATERIAL_BANK_DEPTH
	if(material_depth_bank_enabled)depth_footprint/=terrain_depth_world_unit;
#endif
#ifdef EMBER_TERRAIN_SECONDARY_DEPTH
	// Different material spans must not create artificial derivatives at the
	// coverage boundary. Evaluate both uniform footprints before selecting.
	vec3 primary_footprint=fwidth(terrain_world_position / max(texelFetch(png_lookup,ivec2(material_depth_slots.x,0),0).g,0.125));
	vec3 secondary_footprint=fwidth(terrain_world_position / max(texelFetch(png_lookup,ivec2(material_depth_secondary_slots.x,0),0).g,0.125));
	depth_footprint=secondary_profile?secondary_footprint:primary_footprint;
#endif
	material_depth_lod = clamp(log2(max(length(depth_footprint) * float(material_depth_image_size()),1.0)),0.0,6.0);
#ifdef EMBER_MATERIAL_BANK_DEPTH
	if(material_depth_bank_enabled)material_depth_lod+=float(terrain_depth_slot)*16.0;
#endif
#ifdef EMBER_TERRAIN_SECONDARY_DEPTH
	if(secondary_profile)material_depth_lod=-material_depth_lod-1.0;
#endif
	vec3 depth_normal = texelFetch(png_lookup,ivec2(material_depth_current_slots().x,0),0).a>0.5 ? texture_projection_normal : normalize(terrain_world_normal);
	vec3 depth_view_direction = normalize(CAMERA_POSITION_WORLD - terrain_world_position);
	float depth_facing = dot(depth_normal, depth_view_direction);
	float depth_distance_fade = 1.0 - smoothstep(material_depth_fade_near_m, material_depth_fade_far_m, length(VERTEX));
	float depth_amplitude = selected_depth_amount * depth_distance_fade * smoothstep(0.04, 0.12, depth_facing);
	bool depth_water_pass=reflection_pass_enabled;
#ifdef EMBER_TERRAIN_BANK_DEPTH
	// The flag means water passes exist; only their cameras omit POM.
	depth_water_pass=reflection_pass_enabled && (CAMERA_VISIBLE_LAYERS & ((1u<<19u)|(1u<<18u)))!=0u;
#endif
	bool depth_active = selected_depth_enabled && depth_amplitude > 0.00001 && !IN_SHADOW_PASS && !depth_water_pass && material_depth_weight(terrain_world_position)>0.00001;
#endif
	// The mirrored study camera sits below the surface. Ground below that
	// plane must not appear as a reflection of the shore. Camera layer masks
	// classify only camera passes, never a light's shadow projection.
	if (!IN_SHADOW_PASS && reflection_pass_enabled && (CAMERA_VISIBLE_LAYERS & (1u << 19u)) != 0u
			&& terrain_world_position.y < caustic_water_level + 0.05) {
		discard;
	}
	// The refraction camera contains only the submerged terrain.
	if (!IN_SHADOW_PASS && reflection_pass_enabled && (CAMERA_VISIBLE_LAYERS & (1u << 18u)) != 0u
			&& terrain_world_position.y >= caustic_water_level - 0.05) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	CLEARCOAT = material_light_mode == 2 ? 0.35 : 0.0;
	CLEARCOAT_ROUGHNESS = 0.20;
	int palette_index = int(round(EMBER_PALETTE_INDEX));
	int has_pattern = int(round(texelFetch(role_lookup, ivec2(palette_index, 0), 0).r * 255.0));
	if (has_pattern > 0 && !smooth_surface_enabled && texelFetch(png_lookup,ivec2(palette_index,0),0).r<0.5) {
		vec3 finish = texelFetch(finish_lookup, ivec2(palette_index, 0), 0).rgb;
		ROUGHNESS = 1.0 - finish.r * 0.78;
		if (material_light_mode > 0) {
			// Same authored gloss; give it a perceptually useful roughness range.
			ROUGHNESS = clamp(1.0 - sqrt(finish.r) * 1.25, 0.22, 0.98);
			SPECULAR = sqrt(0.25 + finish.g * 0.75);
		}
		vec3 normal_axis = abs(terrain_normal);
		bool has_side_pattern = texelFetch(role_lookup, ivec2(palette_index, 0), 0).g > 0.0;
		bool side_artwork = has_side_pattern && normal_axis.y < 0.5;
		vec2 position = normal_axis.y > 0.5 ? terrain_position.xz :
			(normal_axis.x > 0.5 ? terrain_position.zy : terrain_position.xy);
		vec3 surface = independent_surface_enabled ? texelFetch(surface_lookup,ivec2(palette_index,0),0).rgb : vec3(4.0,0.0,0.0);
		float span = texture_span*max(surface.r,0.125)/4.0;
		vec2 uv = mirrored_tile(position / span);
		float art_fade = surface.b > 0.5 ? 1.0-smoothstep(0.5,1.5,length(fwidth(position/span*16.0))) : 1.0;
		ivec2 pixel = clamp(ivec2(floor(uv * 16.0)), ivec2(0), ivec2(15));
		ALBEDO = mix(COLOR.rgb,artwork_pixel(ivec2(pixel.x, palette_index * 16 + pixel.y), side_artwork).rgb,art_fade);
		if (surface_detail_enabled && surface.g > 0.001) {
			float rough_pixel=normal_axis.y < 0.5 ? texelFetch(side_roughness_atlas,ivec2(pixel.x,palette_index*16+pixel.y),0).r : texelFetch(roughness_atlas,ivec2(pixel.x,palette_index*16+pixel.y),0).r;
			ROUGHNESS=clamp(ROUGHNESS+(rough_pixel-0.5)*2.0*surface.g*art_fade,0.22,1.0);
		}
#ifndef EMBER_TERRAIN_CHEAP
		if (finish.b > 0.0 && (normal_axis.y > 0.5 || side_artwork) && (surface.b < 0.5 || surface_detail_enabled)) {
			vec2 tile_phase = fract(position / span * 0.5);
			vec2 mirror_sign = vec2(tile_phase.x < 0.5 ? 1.0 : -1.0,
				tile_phase.y < 0.5 ? 1.0 : -1.0);
			int row = palette_index * 16 + pixel.y;
			float left_height = artwork_pixel(ivec2(max(pixel.x - 1, 0), row), side_artwork).a;
			float right_height = artwork_pixel(ivec2(min(pixel.x + 1, 15), row), side_artwork).a;
			float near_height = artwork_pixel(ivec2(pixel.x, palette_index * 16 + max(pixel.y - 1, 0)), side_artwork).a;
			float far_height = artwork_pixel(ivec2(pixel.x, palette_index * 16 + min(pixel.y + 1, 15)), side_artwork).a;
			float relief = finish.b * (has_side_pattern ? 0.65 : 0.3)*art_fade;
			vec3 tangent = normal_axis.x > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
			vec3 bitangent = normal_axis.y > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
			vec3 painted_normal = normalize(terrain_normal
				+ tangent * (left_height - right_height) * relief * mirror_sign.x
				+ bitangent * (near_height - far_height) * relief * mirror_sign.y);
			NORMAL = normalize((VIEW_MATRIX * vec4(MODEL_NORMAL_MATRIX * painted_normal, 0.0)).xyz);
		}
#endif
		vec3 detail = texelFetch(detail_lookup,ivec2(palette_index,0),0).rgb;
		float detail_role = texelFetch(role_lookup,ivec2(palette_index,0),0).b*255.0;
#ifdef EMBER_TERRAIN_CHEAP
		if (surface_detail_enabled && detail_role > 0.5 && detail.b > 0.001) {
#else
		if (surface_detail_enabled && detail_role > 0.5 && (detail.r > 0.001 || detail.b > 0.001)) {
#endif
			// World-sized local coordinates, same field across tile boundaries.
			vec2 p = position/16.0/max(detail.g,0.03);
			float fade = 1.0-smoothstep(0.35,1.2,length(fwidth(p)));
			if (fade > 0.001) {
				vec3 grain = ember_terrain_detail(p,detail_role);
				vec3 tangent = normal_axis.x > 0.5 ? vec3(0,0,1) : vec3(1,0,0);
				vec3 bitangent = normal_axis.y > 0.5 ? vec3(0,0,1) : vec3(0,1,0);
				vec3 view_tangent = normalize((VIEW_MATRIX*vec4(MODEL_NORMAL_MATRIX*tangent,0.0)).xyz);
				vec3 view_bitangent = normalize((VIEW_MATRIX*vec4(MODEL_NORMAL_MATRIX*bitangent,0.0)).xyz);
#ifndef EMBER_TERRAIN_CHEAP
				NORMAL = normalize(NORMAL+(view_tangent*grain.x+view_bitangent*grain.y)*detail.r*fade);
#endif
				ROUGHNESS = clamp(ROUGHNESS+grain.z*detail.b*fade,0.22,1.0);
			}
		}
	}
	bool use_smooth_baseline = smooth_surface_enabled;
#ifdef EMBER_TERRAIN_MATERIAL_DEPTH
	use_smooth_baseline = use_smooth_baseline && !depth_active;
#endif
	if(use_smooth_baseline) {
		ivec3 slots=ivec3(round(smooth_slots));
		vec3 weights=painted_blend;
		if(solid_projection_mode==1 && slots.x==slots.y && slots.y==slots.z)ALBEDO=slot_albedo(slots.x);
#ifdef EMBER_PAINTERLY_STUDY
		// Flat palette IDs keep this decision coherent across the triangle.
		// Reuse the pigment but retain the exact weighted expression.
		else if(painterly_blades && slots.x==slots.y && slots.y==slots.z) {
			vec3 pigment=slot_albedo(slots.x);
			ALBEDO=pigment*weights.x+pigment*weights.y+pigment*weights.z;
		}
#endif
#ifdef EMBER_TERRAIN_BANK_DEPTH
		// A single painted material needs one pigment sample, with the same weights.
		else if(slots.x==slots.y && slots.y==slots.z) {
			vec3 pigment=slot_albedo(slots.x);
			ALBEDO=pigment*weights.x+pigment*weights.y+pigment*weights.z;
		}
#endif
		else ALBEDO=slot_albedo(slots.x)*weights.x+slot_albedo(slots.y)*weights.y+slot_albedo(slots.z)*weights.z;
		ROUGHNESS=0.98;SPECULAR=0.05;
#ifndef EMBER_TERRAIN_CHEAP
		// Optional fine optical relief follows the existing PNG artwork and
		// material's authored relief amount. Coarse volume still lives in terrain.
		float bump_m=0.0;
		for(int i=0;i<3;i++) {
			int slot=slots[i];
#ifdef EMBER_MATERIAL_COLOUR_PROBE
			if(slot==colour_probe_slot)continue;
#endif
			vec4 png_entry=texelFetch(png_lookup,ivec2(slot,0),0);
			if(png_entry.r>0.5 && png_entry.b>=0.0) {
				bump_m+=weights[i]*texelFetch(finish_lookup,ivec2(slot,0),0).b*0.3;
			}
		}
		float shared_amplitude=0.0;
#ifdef EMBER_TERRAIN_MATERIAL_DEPTH
		shared_amplitude=depth_amplitude;
#endif
		vec3 heights=vec3(slot_optical_height(slots.x,shared_amplitude),slot_optical_height(slots.y,shared_amplitude),slot_optical_height(slots.z,shared_amplitude));
		vec3 n=normalize(terrain_world_normal);
		vec3 dx=dFdx(terrain_world_position),dy=dFdy(terrain_world_position);
		vec3 r1=cross(dy,n),r2=cross(n,dx);
		float det=dot(dx,r1);
		// Blend gradients, not height derivatives: material borders must not
		// become fake ridges or reveal per-triangle blend interpolation.
		vec3 gradient=r1*dot(dFdx(heights),weights)+r2*dot(dFdy(heights),weights);
		if(surface_detail_enabled && bump_m>0.0001) {
			if(abs(det)>0.00000001) {
				vec3 slope=sign(det)*gradient/abs(det);
				slope*=min(1.0,0.30/max(length(slope),0.00001));
#ifdef EMBER_MATERIAL_COLOUR_PROBE
				if(!colour_probe_shared_height)
#endif
				slope*=smoothstep(0.62,0.9,abs(n.y));
				vec3 painted_normal=normalize(n-slope);
				NORMAL=normalize((VIEW_MATRIX*vec4(painted_normal,0.0)).xyz);
			}
		}
#endif
	}else if(texelFetch(png_lookup,ivec2(palette_index,0),0).r>0.5) {
		ALBEDO=slot_albedo(palette_index);ROUGHNESS=0.98;SPECULAR=0.05;
	}
	if (material_light_mode == 2) {
		ROUGHNESS = 0.24;
		SPECULAR = 0.5;
	}
#ifdef EMBER_TERRAIN_MATERIAL_DEPTH
	if (depth_active) {
		vec3 n = depth_normal;
		float amplitude = depth_amplitude;
		vec3 hit = material_depth_intersection(terrain_world_position, n, depth_view_direction, amplitude EMBER_DEPTH_ARGUMENT);
		ALBEDO = material_depth_albedo(hit, n);
#ifdef EMBER_SOLID_DEPTH
		// The selected profile owns the ray, never the other painted colours.
		if(material_depth_bank_enabled && smooth_surface_enabled) {
			vec3 pigment=ALBEDO;
			ALBEDO=vec3(0.0);
			for(int i=0;i<3;i++)ALBEDO+=(painted_slots[i]==terrain_depth_slot?pigment:slot_albedo(painted_slots[i]))*painted_blend[i];
		}
#endif
#ifdef EMBER_TERRAIN_BANK_DEPTH
		if(painted_slots.x==painted_slots.y && painted_slots.y==painted_slots.z) {
			vec3 pigment=slot_albedo_at(painted_slots.x,hit,n);
			ALBEDO=pigment*painted_blend.x+pigment*painted_blend.y+pigment*painted_blend.z;
		}else ALBEDO=slot_albedo_at(painted_slots.x,hit,n)*painted_blend.x+slot_albedo_at(painted_slots.y,hit,n)*painted_blend.y+slot_albedo_at(painted_slots.z,hit,n)*painted_blend.z;
#endif
		ROUGHNESS = 0.98;
		SPECULAR = 0.05;
		vec3 tangent = normalize(cross(abs(n.y) > 0.9 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0), n));
		vec3 bitangent = cross(n, tangent);
		vec3 lighting_hit = hit;
#ifdef EMBER_TERRAIN_BANK_DEPTH
 if (voxel_weight > 0.0) {
  voxel_sample = ember_texel_sample(terrain_world_position, hit, n, voxel_light_cell, material_depth_span() * terrain_depth_world_unit / 32.0);
  voxel_sample.z *= voxel_weight;
  lighting_hit += (dFdx(terrain_world_position) * voxel_sample.x + dFdy(terrain_world_position) * voxel_sample.y) * voxel_sample.z;
 }
#endif
		float epsilon = max(material_depth_span() * exp2(material_depth_mip()) / float(material_depth_image_size()), 0.001);
#ifdef EMBER_MATERIAL_BANK_DEPTH
		if(material_depth_bank_enabled)epsilon*=terrain_depth_world_unit;
#endif
#ifdef EMBER_MATERIAL_LOOK_STUDY
		if (look_study_mode == 2) {
			// POM already found the visible step. A second screen-space
			// extrapolation moves its colour, normal and shadow apart.
#ifdef EMBER_TERRAIN_BANK_DEPTH
			epsilon = max(epsilon, material_depth_span() * terrain_depth_world_unit / 64.0);
#else
			lighting_hit += ember_look_pixel_colour_position(terrain_world_position, n) - terrain_world_position;
			epsilon = max(epsilon, look_study_pixel_m * 0.5);
#endif
		}
#endif
		float dh_t = (EMBER_DEPTH_HEIGHT_AT(lighting_hit + tangent * epsilon, n EMBER_DEPTH_ARGUMENT) - EMBER_DEPTH_HEIGHT_AT(lighting_hit - tangent * epsilon, n EMBER_DEPTH_ARGUMENT)) * amplitude / (2.0 * epsilon);
		float dh_b = (EMBER_DEPTH_HEIGHT_AT(lighting_hit + bitangent * epsilon, n EMBER_DEPTH_ARGUMENT) - EMBER_DEPTH_HEIGHT_AT(lighting_hit - bitangent * epsilon, n EMBER_DEPTH_ARGUMENT)) * amplitude / (2.0 * epsilon);
		vec3 relief_normal=n;
#ifdef EMBER_SOLID_DEPTH
		// Projection follows the true plane; lighting retains the object's authored
		// smooth/form normals instead of exposing its internal tessellation.
		relief_normal=normalize(terrain_world_normal);
#endif
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(relief_normal - tangent * dh_t - bitangent * dh_b), 0.0)).xyz);
#ifdef EMBER_BEVEL_STUDY
		if (bevel_light_enabled) {
			bevel_light_mask = ember_bevel_mask(vec2(dh_t,dh_b), EMBER_DEPTH_HEIGHT_AT(hit,n EMBER_DEPTH_ARGUMENT));
		}
#endif
		LIGHT_VERTEX = (VIEW_MATRIX * vec4(hit, 1.0)).xyz;
		vec4 clip_position = PROJECTION_MATRIX * vec4(LIGHT_VERTEX, 1.0);
		DEPTH = clip_position.z / clip_position.w;
		material_depth_light = material_depth_shadow_at(lighting_hit, n, amplitude EMBER_DEPTH_ARGUMENT);
	}
#endif
#ifdef EMBER_FLOWER_COVER
	ALPHA = flower.a;
	ALPHA_SCISSOR_THRESHOLD = 0.55;
	// Tint only the green painted foliage into the accepted ground/grass pigment.
	float green = step(flower.r * 0.94, flower.g) * step(flower.b * 1.3, flower.g);
	vec3 plant = ALBEDO * mix(0.78, 1.12, clamp(flower.g, 0.0, 1.0));
	ALBEDO = mix(flower.rgb, plant, green * 0.88) * flower_tint.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
#endif
	if (material_gray_preview) {
		ALBEDO = vec3(0.32);
	}
#ifdef EMBER_PAINTERLY_STUDY
	if (painterly_blades) {
		// Shared ground pigment; the darker base reads as a shallow plant mass.
		if (painterly_enabled && painterly_grass_masses) {
			ALBEDO *= mix(0.98, 1.0, smoothstep(0.0, 0.75, painterly_blade_height));
			// Ambient also treats neighbouring cards as one painted canopy.
			NORMAL = normalize(mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0));
		} else {
			ALBEDO *= mix(0.68, 1.06, smoothstep(0.0, 0.75, painterly_blade_height));
		}
	}
#endif
#ifndef EMBER_GRASS_COVER
	float submerged_side = submerged_side_weight();
	vec4 coast = coastal_info(terrain_world_position.xz);
	float wetness = coastal_state(terrain_world_position.xz).b * coast.a * sand_wet_strength;
	ALBEDO *= 1.0 - wetness * 0.36;
	ROUGHNESS = mix(ROUGHNESS, 0.35, wetness);
	// A vertical submerged face receives blue ambient bounce and less direct
	// seabed light; the refraction camera must not turn shaded sides pale sand.
	ALBEDO *= mix(vec3(1.0), vec3(0.28, 0.45, 0.55), submerged_side);
	EMISSION = ALBEDO * (1.0 - abs(terrain_normal.y))
		* mix(0.16, 0.0, submerged_side) * (material_light_mode == 0 ? 1.0 : 0.0);
	if (underwater_caustics > 0.001 && terrain_normal.y > 0.5) {
		float depth = caustic_water_level - terrain_world_position.y;
		if (depth > 0.5) {
			vec2 surface_point = (terrain_world_position.xz - caustic_sun_offset * depth) / 16.0;
			float seconds = preview_time >= 0.0 ? preview_time : TIME;
			float focus = study_caustic_focus(surface_point, seconds);
			float fade = exp(-depth * 0.028);
			EMISSION += vec3(0.50, 1.08, 1.14) * focus * fade * underwater_caustics;
		}
	}
#else
	// Cover has no shoreline layer, but retains its previous side bounce.
	EMISSION = ALBEDO * (1.0 - abs(terrain_normal.y)) * 0.16 * (material_light_mode == 0 ? 1.0 : 0.0);
#endif
#ifdef EMBER_MATERIAL_LOOK_STUDY
	look_study_position = terrain_world_position;
	vec3 look_sample_delta = ember_look_sample(terrain_world_position, texture_projection_normal);
	// Reuse the existing fragment-to-light channel; Forward+ has a fixed budget.
	texture_projection_normal = terrain_world_normal;
	if (look_study_mode == 2 && voxel_weight <= 0.0 && !voxel_light_anomaly && !IN_SHADOW_PASS) {
		look_study_position = ember_look_extrapolate(terrain_world_position, look_sample_delta);
		texture_projection_normal = normalize(ember_look_extrapolate(terrain_world_normal, look_sample_delta));
#ifdef EMBER_TERRAIN_MATERIAL_DEPTH
		// POM normals were already evaluated at the material-cell centre.
		// Extrapolating their discontinuities again produces bright speckles.
		if (!depth_active) NORMAL = normalize(ember_look_extrapolate(NORMAL, look_sample_delta));
#else
		NORMAL = normalize(ember_look_extrapolate(NORMAL, look_sample_delta));
#endif
		// Keep the exact POM hit; only a plain surface needs texel-centre lighting.
#ifdef EMBER_TERRAIN_MATERIAL_DEPTH
		if (!depth_active) LIGHT_VERTEX = ember_look_extrapolate(LIGHT_VERTEX, look_sample_delta);
#else
		LIGHT_VERTEX = ember_look_extrapolate(LIGHT_VERTEX, look_sample_delta);
#endif
	}
#endif
 if (!IN_SHADOW_PASS && voxel_weight > 0.0) {
  vec3 voxel_view_shift = continuous_view_dx * voxel_sample.x + continuous_view_dy * voxel_sample.y;
  if (voxel_anomaly_surface) {
   // The cell centre stays on this geometric plane. Screen derivatives across
   // unfolding risers otherwise sample shadows above/below neighbouring faces.
   vec3 plane_shift = ember_texel_plane_shift(light_origin, light_axis, voxel_light_cell);
   if (solid_projection_mode == 1) plane_shift = mat3(MODEL_MATRIX) * plane_shift;
   voxel_view_shift = mat3(VIEW_MATRIX) * plane_shift;
  }
#ifdef EMBER_PAINTERLY_STUDY
  if (painterly_blades) {
   LIGHT_VERTEX += mat3(VIEW_MATRIX) * ember_texel_plane_shift(terrain_world_position, terrain_world_normal, voxel_light_cell) * voxel_sample.z;
  } else
#endif
  LIGHT_VERTEX += voxel_view_shift * voxel_sample.z;
  if (!voxel_anomaly_surface) {
#ifdef EMBER_TERRAIN_MATERIAL_DEPTH
  if (!depth_active) NORMAL = normalize(ember_texel_extrapolate(NORMAL, voxel_sample));
#else
  NORMAL = normalize(ember_texel_extrapolate(NORMAL, voxel_sample));
#endif
  }
 }
	// Solid hulls: the rim (read in light()) follows the continuous form normal and is limited
	// to a thin strip along convex edges. texture_projection_normal is free after fragment().
	if (solid_form_rim && dot(solid_form_local, solid_form_local) > 0.0) {
		texture_projection_normal = normalize(MODEL_NORMAL_MATRIX * solid_form_local);
	}
	float rim_width_m = style_rim_weight > 0.0 ? rim_width_sum / style_rim_weight : 0.0;
	style_rim_weight *= solid_rim_frame(rim_width_m);
	// Solid hulls only (never painterly): tell light() whether the thin frame band applies.
	if (solid_form_rim && dot(solid_form_local, solid_form_local) > 0.0) painterly_weights.y = rim_width_m > 0.0 ? 1.0 : 0.0;
#ifdef EMBER_SOLID_MATERIAL_LAYERS
	stone_finish(terrain_position,mat3(VIEW_MATRIX)*MODEL_NORMAL_MATRIX,ALBEDO,NORMAL,stone_depth_edge);
#endif
}

void light() {
 vec3 voxel_previous_diffuse = DIFFUSE_LIGHT;
	vec3 look_position = terrain_world_position;
	vec3 look_form = terrain_world_normal;
#ifdef EMBER_MATERIAL_LOOK_STUDY
	look_position = look_study_position;
	look_form = ember_look_world_normal(texture_projection_normal);
	vec3 look_previous_diffuse = DIFFUSE_LIGHT;
#endif
	float terrain_light_attenuation = ATTENUATION;
#ifdef EMBER_TERRAIN_MATERIAL_DEPTH
	if (LIGHT_IS_DIRECTIONAL) terrain_light_attenuation *= material_depth_light;
#endif
	if (LIGHT_IS_DIRECTIONAL && style_rim_weight>0.0) {
		vec3 rim_source=(solid_form_rim && dot(solid_form_local,solid_form_local)>0.0) ? texture_projection_normal : normalize(look_form);
		vec3 rim_form=normalize(mat3(VIEW_MATRIX)*rim_source);
		SPECULAR_LIGHT+=LIGHT_COLOR*terrain_light_attenuation*ember_stylized_rim_shaped(rim_form,VIEW,LIGHT,style_rim_weight,(solid_form_rim && painterly_weights.y > 0.5) ? solid_rim_edge : vec2(0.10, 0.32))/PI;
	}
#ifdef EMBER_BEVEL_STUDY
	if (bevel_light_enabled && LIGHT_IS_DIRECTIONAL) {
		float accent = ember_bevel_light(NORMAL, normalize(mat3(VIEW_MATRIX)*normalize(terrain_world_normal)), LIGHT);
		// POM visibility and the world's real shadows both gate the accent.
		accent *= smoothstep(0.5, 0.9, material_depth_light);
		SPECULAR_LIGHT += LIGHT_COLOR * terrain_light_attenuation * accent / PI;
	}
#endif
	float previous_share=1.0-grass_profile_weight;
	vec3 previous_light_color=LIGHT_COLOR*previous_share;
	if(grass_profile_weight>0.00001) {
		// The accepted brush field is calibrated at a four-metre material span.
		// Colour and grass light use one scene-scale-aware material size.
		vec3 grass_position=ember_texture_coordinates(look_position,grass_profile_shadow.a)*4.0;
		vec3 grass_world_normal=ember_grass_masses_normal(grass_position);
		// Ground pigment carries the calm brushwork; thin blades retain their chosen mass lighting.
		bool grass_cover=true;
#ifdef EMBER_PAINTERLY_STUDY
		grass_cover=!painterly_blades;
#endif
		if(grass_cover)grass_world_normal=normalize(terrain_world_normal);
#ifdef EMBER_MATERIAL_LOOK_STUDY
		grass_world_normal=ember_look_world_normal(grass_world_normal);
#endif
		vec3 gn=normalize(mat3(VIEW_MATRIX)*grass_world_normal);
		vec2 steps=ember_painted_grass_steps(gn,LIGHT);
		float brightness=grass_profile_values.r+(1.0-grass_profile_values.r)*0.5*(steps.x+steps.y);
		vec3 tint=material_gray_preview ? vec3(1.0) : ember_grass_light_tint(gn,LIGHT,ALBEDO*LIGHT_COLOR,grass_profile_cool,grass_profile_warm,grass_profile_values.g);
		DIFFUSE_LIGHT+=LIGHT_COLOR*terrain_light_attenuation*brightness*tint*grass_profile_weight/PI;
		if(LIGHT_IS_DIRECTIONAL) {
			float shade=smoothstep(0.08,0.92,1.0-ATTENUATION);
			DIFFUSE_LIGHT+=LIGHT_COLOR*mix(vec3(0.85,0.96,1.0),grass_profile_shadow.rgb,shade)*shade*grass_profile_values.b*grass_profile_weight/PI;
		}
	}
	if(previous_share>0.00001) {
	if (painterly_enabled) {
		vec3 form_normal=normalize(mat3(VIEW_MATRIX)*normalize(look_form));
		vec3 grass_normal=normalize(mat3(VIEW_MATRIX)*ember_painted_grass_normal(normalize(look_form),look_position));
		// Remove the profiled part before shading the remaining material blend.
		vec2 residual=vec2(max(painterly_weights.x-grass_profile_weight,0.0),painterly_weights.y)/max(previous_share,0.00001);
		vec2 response = ember_painterly_light(form_normal, NORMAL,
			form_normal, grass_normal, VIEW, LIGHT,
			residual.x, residual.y);
		vec3 painted_diffuse = previous_light_color * terrain_light_attenuation * response.x / PI;
		if (painterly_grass_color && painterly_grass_masses && !material_gray_preview && painterly_weights.x > 0.00001) {
			painted_diffuse *= mix(vec3(1.0), ember_painted_grass_tint(grass_normal, LIGHT, ALBEDO * LIGHT_COLOR), residual.x);
		}
		DIFFUSE_LIGHT += painted_diffuse;
		if (LIGHT_IS_DIRECTIONAL && painterly_grass_masses && painterly_weights.x > 0.00001) {
			// Small artistic sky-bounce allowance in real directional shadows.
			// ATTENUATION is light visibility, not distance inside a tree crown.
			// No emission: with zero light energy this contribution is also zero.
			float shade = smoothstep(0.08, 0.92, 1.0-ATTENUATION);
			vec3 shade_tint = mix(vec3(0.85, 0.96, 1.0), painterly_grass_shadow_color, shade);
			DIFFUSE_LIGHT += previous_light_color * shade_tint * shade * painterly_grass_shadow_fill * residual.x / PI;
		}
		SPECULAR_LIGHT += previous_light_color * terrain_light_attenuation * response.y / PI;
	} else
	if (material_light_mode > 0) {
		float nl = max(dot(NORMAL, LIGHT), 0.0);
		float nv = max(dot(NORMAL, VIEW), 0.0001);
		vec3 halfway = normalize(LIGHT + VIEW + vec3(0.000001));
		float nh = max(dot(NORMAL, halfway), 0.0);
		float vh = max(dot(VIEW, halfway), 0.0);
		float sheen = texelFetch(finish_lookup, ivec2(int(round(EMBER_PALETTE_INDEX)), 0), 0).g;
		float f0 = material_light_mode == 2 ? 0.04 : 0.04 + 0.12 * sheen;
		float fresnel = ember_surface_fresnel(vh, f0);
		float coat = material_light_mode == 2 ? 0.35 : 0.0;
		float coat_fresnel = ember_surface_fresnel(vh, 0.04) * coat;
		float transmission = 1.0 - coat_fresnel;
		// No permanent side glow or directional fill in these comparisons.
		DIFFUSE_LIGHT += previous_light_color * terrain_light_attenuation * nl / PI
			* (1.0 - fresnel) * transmission;
		float specular = ember_surface_specular(nl, nv, nh, ROUGHNESS) * fresnel * transmission;
		if (coat > 0.0) {
			specular += ember_surface_specular(nl, nv, nh, 0.20) * coat_fresnel;
		}
		SPECULAR_LIGHT += previous_light_color * terrain_light_attenuation * nl * specular;
	} else {
	// Godot applies ALBEDO during final composition. Keep one palette tint.
	DIFFUSE_LIGHT += ember_diorama_diffuse(vec3(1.0), NORMAL, LIGHT, previous_light_color,
		terrain_light_attenuation, LIGHT_IS_DIRECTIONAL, max(float(toon_steps), 2.0),
		band_floor, local_light_softness);
	// The stepped sides are only a few pixels high on screen. Keep a restrained
	// light-coloured bounce so they read as faces instead of black gaps.
	if (LIGHT_IS_DIRECTIONAL) {
		bool has_side_pattern = texelFetch(role_lookup, ivec2(int(round(EMBER_PALETTE_INDEX)), 0), 0).g > 0.0;
		float side = has_side_pattern ? (1.0 - abs(terrain_normal.y)) * 0.55 : 1.0 - abs(NORMAL.y);
		float submerged_side = submerged_side_weight();
		DIFFUSE_LIGHT += shadow_tint * previous_light_color * terrain_side_fill * side
			* mix(1.0, terrain_light_attenuation, submerged_side);
	}
	int palette_index = int(round(EMBER_PALETTE_INDEX));
	vec2 finish = texelFetch(finish_lookup, ivec2(palette_index, 0), 0).rg;
	if (finish.y > 0.0) {
		vec3 halfway = normalize(LIGHT + VIEW);
		float focus = pow(max(dot(NORMAL, halfway), 0.0), mix(10.0, 72.0, finish.x));
		float highlight = smoothstep(0.06, 0.55, focus);
		SPECULAR_LIGHT += previous_light_color * terrain_light_attenuation * highlight
			* max(dot(NORMAL, LIGHT), 0.0) * finish.y * 0.42;
	}
	}
	}
#ifdef EMBER_MATERIAL_LOOK_STUDY
	if (look_study_mode == 2 && !voxel_light_enabled && !voxel_light_anomaly) {
		DIFFUSE_LIGHT = look_previous_diffuse + ember_look_stepped_contribution(DIFFUSE_LIGHT - look_previous_diffuse, LIGHT_COLOR);
	}
#endif
 float voxel_weight = ember_voxel_light_weight(terrain_world_position);
 if (voxel_weight > 0.0) DIFFUSE_LIGHT = voxel_previous_diffuse + mix(DIFFUSE_LIGHT - voxel_previous_diffuse,
  ember_texel_light_steps(DIFFUSE_LIGHT - voxel_previous_diffuse, LIGHT_COLOR, voxel_light_levels), voxel_weight);

}
