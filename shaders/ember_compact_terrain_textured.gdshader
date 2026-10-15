shader_type spatial;
render_mode cull_back;

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
varying vec3 grass_profile_shadow;

varying vec3 terrain_position;
varying vec3 terrain_normal;
varying vec3 terrain_world_position;
varying vec3 terrain_world_normal;
varying vec3 texture_projection_normal;
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

void vertex() {
#ifdef EMBER_PAINTERLY_STUDY
	painterly_blade_height = clamp(VERTEX.y / 0.14, 0.0, 1.0);
#endif
	terrain_position = VERTEX;
	terrain_normal = NORMAL;
	terrain_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	terrain_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	palette_slot = COLOR.a;
	smooth_slots = vec3(UV,UV2.x)*255.0;
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

vec3 slot_albedo_at(int slot, vec3 world_position, vec3 world_normal) {
	vec4 png=texelFetch(png_lookup,ivec2(slot,0),0);
	vec3 n=abs(normalize(world_normal));
	if(png.r>0.5) {
		vec3 p=ember_texture_coordinates(world_position,png.g);
		vec3 texture_dx=vec3(0.0),texture_dy=vec3(0.0);
#ifdef EMBER_MATERIAL_LOOK_STUDY
		texture_dx=dFdx(p);texture_dy=dFdy(p);
		p=ember_texture_coordinates(ember_look_pixel_colour_position(world_position,world_normal),png.g);
#endif
		vec3 rgb;
		bool periodic=png.a>0.5;
		if(periodic)n=abs(texture_projection_normal);
		if(png.b>3.5 || periodic) {
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
		vec2 position=n.y>0.5?terrain_position.xz:(n.x>0.5?terrain_position.zy:terrain_position.xy);
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

float slot_optical_height(int slot) {
	vec4 png=texelFetch(png_lookup,ivec2(slot,0),0);
	float amount=texelFetch(finish_lookup,ivec2(slot,0),0).b*0.3;
	if(png.r<0.5 || amount<0.0001)return 0.0;
	vec3 p=ember_texture_coordinates(terrain_world_position,png.g);
	// First heightfield slice follows top artwork; steep sides fade below.
	// Avoid differentiating triplanar weights, which reveals the fine mesh.
	vec3 rgb=png_relief_tile(p.xz,png.r-1.0,png.a>0.5);
	return dot(rgb,vec3(0.2126,0.7152,0.0722))*amount*2.0;
}

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

void fragment() {
	#ifdef EMBER_BEVEL_STUDY
	bevel_light_mask = 0.0;
	#endif
	texture_projection_normal = ember_texture_surface_normal(terrain_world_position, terrain_world_normal);
	painterly_weights = vec2(0.0);
	style_rim_weight=0.0;
	grass_profile_weight=0.0;
	grass_profile_values=vec3(0.0);grass_profile_cool=vec3(0.0);grass_profile_warm=vec3(0.0);grass_profile_shadow=vec3(0.0);
	ivec3 painted_slots = smooth_surface_enabled ? ivec3(round(smooth_slots)) : ivec3(int(round(palette_slot * 255.0)));
	vec3 painted_blend = smooth_surface_enabled ? max(COLOR.rgb,vec3(0.0)) : vec3(1.0,0.0,0.0);
	painted_blend /= max(dot(painted_blend,vec3(1.0)),0.00001);
	if(painterly_enabled || grass_light_profiles_enabled || style_rim_profiles_enabled) for (int i=0; i<3; i++) {
		float role = texelFetch(role_lookup,ivec2(painted_slots[i],0),0).b * 255.0;
		painterly_weights.x += painted_blend[i] * (abs(role - 1.0) < 0.1 ? 1.0 : 0.0);
		// LAB stone slot is explicit, same slot bound by the existing depth study.
		vec3 rim_profile=style_rim_profiles_enabled ? texelFetch(style_rim_lookup,ivec2(painted_slots[i],0),0).rgb : vec3(0.0);
		painterly_weights.y += painted_blend[i] * (painted_slots[i] == 1 && rim_profile.r<0.5 ? 1.0 : 0.0);
		style_rim_weight += painted_blend[i]*rim_profile.r*rim_profile.g*rim_profile.b;
		if(grass_light_profiles_enabled && abs(role-1.0)<0.1) {
			vec4 settings=texelFetch(grass_light_lookup,ivec2(painted_slots[i],0),0);
			float weight=painted_blend[i]*settings.a;
			grass_profile_weight+=weight;grass_profile_values+=weight*settings.rgb;
			grass_profile_cool+=weight*texelFetch(grass_light_lookup,ivec2(painted_slots[i],1),0).rgb;
			grass_profile_warm+=weight*texelFetch(grass_light_lookup,ivec2(painted_slots[i],2),0).rgb;
			grass_profile_shadow+=weight*texelFetch(grass_light_lookup,ivec2(painted_slots[i],3),0).rgb;
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
	material_depth_lod = clamp(log2(max(length(fwidth(terrain_world_position / material_depth_span())) * float(textureSize(material_depth_height,0).x),1.0)),0.0,6.0);
	vec3 depth_normal = texelFetch(png_lookup,ivec2(material_depth_slots.x,0),0).a>0.5 ? texture_projection_normal : normalize(terrain_world_normal);
	vec3 depth_view_direction = normalize(CAMERA_POSITION_WORLD - terrain_world_position);
	float depth_facing = dot(depth_normal, depth_view_direction);
	float depth_distance_fade = 1.0 - smoothstep(material_depth_fade_near_m, material_depth_fade_far_m, length(VERTEX));
	float depth_amplitude = material_depth_amplitude_m * depth_distance_fade * smoothstep(0.04, 0.12, depth_facing);
	bool depth_active = material_depth_enabled && depth_amplitude > 0.00001 && !IN_SHADOW_PASS && !reflection_pass_enabled && material_depth_weight(terrain_world_position)>0.00001;
#endif
	// The mirrored study camera sits below the surface. Ground below that
	// plane must not appear as a reflection of the shore.
	if (reflection_pass_enabled && (CAMERA_VISIBLE_LAYERS & (1u << 19u)) != 0u
			&& terrain_world_position.y < caustic_water_level + 0.05) {
		discard;
	}
	// The refraction camera contains only the submerged terrain.
	if (reflection_pass_enabled && (CAMERA_VISIBLE_LAYERS & (1u << 18u)) != 0u
			&& terrain_world_position.y >= caustic_water_level - 0.05) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	CLEARCOAT = material_light_mode == 2 ? 0.35 : 0.0;
	CLEARCOAT_ROUGHNESS = 0.20;
	int palette_index = int(round(palette_slot * 255.0));
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
		vec3 detail = texelFetch(detail_lookup,ivec2(palette_index,0),0).rgb;
		float detail_role = texelFetch(role_lookup,ivec2(palette_index,0),0).b*255.0;
		if (surface_detail_enabled && detail_role > 0.5 && (detail.r > 0.001 || detail.b > 0.001)) {
			// World-sized local coordinates, same field across tile boundaries.
			vec2 p = position/16.0/max(detail.g,0.03);
			float fade = 1.0-smoothstep(0.35,1.2,length(fwidth(p)));
			if (fade > 0.001) {
				vec3 grain = ember_terrain_detail(p,detail_role);
				vec3 tangent = normal_axis.x > 0.5 ? vec3(0,0,1) : vec3(1,0,0);
				vec3 bitangent = normal_axis.y > 0.5 ? vec3(0,0,1) : vec3(0,1,0);
				vec3 view_tangent = normalize((VIEW_MATRIX*vec4(MODEL_NORMAL_MATRIX*tangent,0.0)).xyz);
				vec3 view_bitangent = normalize((VIEW_MATRIX*vec4(MODEL_NORMAL_MATRIX*bitangent,0.0)).xyz);
				NORMAL = normalize(NORMAL+(view_tangent*grain.x+view_bitangent*grain.y)*detail.r*fade);
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
		vec3 weights=max(COLOR.rgb,vec3(0.0));weights/=max(dot(weights,vec3(1.0)),0.00001);
		ALBEDO=slot_albedo(slots.x)*weights.x+slot_albedo(slots.y)*weights.y+slot_albedo(slots.z)*weights.z;
		ROUGHNESS=0.98;SPECULAR=0.05;
		// Optional fine optical relief follows the existing PNG artwork and
		// material's authored relief amount. Coarse volume still lives in terrain.
		float bump_m=0.0;
		for(int i=0;i<3;i++) {
			int slot=slots[i];
			if(texelFetch(png_lookup,ivec2(slot,0),0).r>0.5) {
				bump_m+=weights[i]*texelFetch(finish_lookup,ivec2(slot,0),0).b*0.3;
			}
		}
		vec3 heights=vec3(slot_optical_height(slots.x),slot_optical_height(slots.y),slot_optical_height(slots.z));
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
				slope*=smoothstep(0.62,0.9,abs(n.y));
				vec3 painted_normal=normalize(n-slope);
				NORMAL=normalize((VIEW_MATRIX*vec4(painted_normal,0.0)).xyz);
			}
		}
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
		vec3 hit = material_depth_intersection(terrain_world_position, n, depth_view_direction, amplitude);
		ALBEDO = material_depth_albedo(hit, n);
		ROUGHNESS = 0.98;
		SPECULAR = 0.05;
		vec3 tangent = normalize(cross(abs(n.y) > 0.9 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0), n));
		vec3 bitangent = cross(n, tangent);
		float epsilon = max(material_depth_span() * exp2(material_depth_lod) / float(textureSize(material_depth_height, 0).x), 0.001);
		float dh_t = (material_depth_height_at(hit + tangent * epsilon, n) - material_depth_height_at(hit - tangent * epsilon, n)) * amplitude / (2.0 * epsilon);
		float dh_b = (material_depth_height_at(hit + bitangent * epsilon, n) - material_depth_height_at(hit - bitangent * epsilon, n)) * amplitude / (2.0 * epsilon);
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n - tangent * dh_t - bitangent * dh_b), 0.0)).xyz);
#ifdef EMBER_BEVEL_STUDY
		if (bevel_light_enabled) {
			bevel_light_mask = ember_bevel_mask(vec2(dh_t,dh_b), material_depth_height_at(hit,n));
		}
#endif
		LIGHT_VERTEX = (VIEW_MATRIX * vec4(hit, 1.0)).xyz;
		vec4 clip_position = PROJECTION_MATRIX * vec4(LIGHT_VERTEX, 1.0);
		DEPTH = clip_position.z / clip_position.w;
		material_depth_light = material_depth_shadow_at(hit, n, amplitude);
	}
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
#ifdef EMBER_MATERIAL_LOOK_STUDY
	look_study_position = terrain_world_position;
	vec3 look_sample_delta = ember_look_sample(terrain_world_position, texture_projection_normal);
	// Reuse the existing fragment-to-light channel; Forward+ has a fixed budget.
	texture_projection_normal = terrain_world_normal;
	if (look_study_mode == 2 && !IN_SHADOW_PASS) {
		look_study_position = ember_look_extrapolate(terrain_world_position, look_sample_delta);
		texture_projection_normal = normalize(ember_look_extrapolate(terrain_world_normal, look_sample_delta));
		NORMAL = normalize(ember_look_extrapolate(NORMAL, look_sample_delta));
		// Sample real lighting/shadows at the texel centre. POM DEPTH stays exact.
		LIGHT_VERTEX = ember_look_extrapolate(LIGHT_VERTEX, look_sample_delta);
	}
#endif
}

void light() {
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
		vec3 rim_form=normalize(mat3(VIEW_MATRIX)*normalize(look_form));
		SPECULAR_LIGHT+=LIGHT_COLOR*terrain_light_attenuation*ember_stylized_rim(rim_form,VIEW,LIGHT,style_rim_weight)/PI;
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
		vec3 grass_world_normal=ember_grass_masses_normal(look_position);
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
			DIFFUSE_LIGHT+=LIGHT_COLOR*mix(vec3(0.85,0.96,1.0),grass_profile_shadow,shade)*shade*grass_profile_values.b*grass_profile_weight/PI;
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
		float sheen = texelFetch(finish_lookup, ivec2(int(round(palette_slot * 255.0)), 0), 0).g;
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
		bool has_side_pattern = texelFetch(role_lookup, ivec2(int(round(palette_slot * 255.0)), 0), 0).g > 0.0;
		float side = has_side_pattern ? (1.0 - abs(terrain_normal.y)) * 0.55 : 1.0 - abs(NORMAL.y);
		float submerged_side = submerged_side_weight();
		DIFFUSE_LIGHT += shadow_tint * previous_light_color * terrain_side_fill * side
			* mix(1.0, terrain_light_attenuation, submerged_side);
	}
	int palette_index = int(round(palette_slot * 255.0));
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
	if (look_study_mode == 2) {
		DIFFUSE_LIGHT = look_previous_diffuse + ember_look_stepped_contribution(DIFFUSE_LIGHT - look_previous_diffuse, LIGHT_COLOR);
	}
#endif
}
