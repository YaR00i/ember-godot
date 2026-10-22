#ifdef EMBER_OBJECT_LEAF_CARDS_STUDY
#ifdef EMBER_OBJECT_VOXEL_LEAVES
render_mode cull_back;
varying vec3 voxel_leaf_form_normal;
uniform float voxel_leaf_rim_form_weight : hint_range(0.0,1.0) = 1.0;
#else
render_mode cull_disabled;
#endif
varying vec3 leaf_card_group_normal;
#else
render_mode cull_back;
#endif

uniform int toon_steps : hint_range(3, 5) = 4;
#ifdef EMBER_OBJECT_FACETED_LEAVES
uniform sampler2D faceted_leaf_shape : filter_linear_mipmap, repeat_disable;
uniform float faceted_leaf_shape_amount : hint_range(0.0,1.0) = 0.0;
uniform int faceted_leaf_shape_kind : hint_enum("Rhombus", "Triangle", "Rectangle") = 0;
#endif
uniform float band_floor : hint_range(0.0, 0.5) = 0.19;
uniform float local_light_softness : hint_range(0.0, 1.0) = 1.0;
#include "res://shaders/ember_stylized_rim.gdshaderinc"
uniform bool object_style_rim_enabled = false;
uniform bool object_style_rim_profiles_enabled = false;
uniform vec2 object_style_rim_profiles[7];
uniform float object_style_rim_strength : hint_range(0.0, 1.0) = 0.0;
#include "res://shaders/ember_diorama_light.gdshaderinc"
#ifdef EMBER_OBJECT_PAINTED_BARK_STUDY
varying flat vec2 painted_bark_frames;
#endif
#include "res://shaders/ember_voxel_surface_light.gdshaderinc"
#include "res://shaders/ember_object_look_clip.gdshaderinc"
#ifdef EMBER_OBJECT_PAINTED_FOLIAGE_STUDY
#include "res://shaders/ember_painted_foliage_study.gdshaderinc"
#endif
#ifdef EMBER_OBJECT_BARK_STUDY
#include "res://shaders/ember_object_bark_study.gdshaderinc"
#endif
#ifdef EMBER_OBJECT_PAINTED_BARK_STUDY
#include "res://shaders/ember_painted_bark_study.gdshaderinc"
#endif

void fragment() {
	if (ember_object_look_discard(surface_local_position)) { discard; }
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
#ifdef EMBER_OBJECT_PAINTED_FOLIAGE_STUDY
#ifdef EMBER_OBJECT_LEAF_CARDS_STUDY
	NORMAL=normalize(leaf_card_group_normal);
	vec4 leaf=texture(painted_leaf_card_albedo,UV);
#ifndef EMBER_OBJECT_VOXEL_LEAVES
	ALPHA=leaf.a;
#ifdef EMBER_OBJECT_FACETED_LEAVES
	if (faceted_leaf_shape_amount>0.0) {
		vec3 shapes=texture(faceted_leaf_shape,UV).rgb;
		float q=shapes[faceted_leaf_shape_kind];
		float limit=mix(faceted_leaf_shape_kind==1?2.25:1.65,1.0,faceted_leaf_shape_amount);
		float edge=max(fwidth(q)*0.5,0.002);
		ALPHA*=1.0-smoothstep(limit-edge,limit+edge,q);
	}
#endif
	ALPHA_SCISSOR_THRESHOLD=painted_leaf_card_cutoff;
#endif
	ALBEDO=ember_leaf_card_colour(leaf.rgb,COLOR.rgb);
#else
	ALBEDO=ember_painted_foliage_colour(surface_local_position,COLOR.rgb,NORMAL);
#endif
	ROUGHNESS=0.95;
	SPECULAR=0.0;
#endif
	if (surface_gray_preview && surface_parameters.x > 0.5) { ALBEDO = vec3(0.45); }
	if (ember_object_surface_active()) {
		ROUGHNESS = ember_object_surface_roughness(surface_local_position);
		SPECULAR = clamp(surface_parameters.z * surface_specular_scale / 0.08, 0.0, 1.0);
		NORMAL = ember_object_surface_normal(NORMAL, surface_local_position);
	}
#ifdef EMBER_OBJECT_PAINTED_BARK_STUDY
#ifdef EMBER_OBJECT_PAINTED_BARK_RELIEF_STUDY
	painted_bark_form_normal=NORMAL;
#endif
	if (painted_bark_enabled && surface_parameters.x > 1.5 && surface_parameters.x < 2.5) {
		vec3 bark_position=surface_local_position;
#ifdef EMBER_OBJECT_PAINTED_BARK_RELIEF_STUDY
		if(painted_bark_relief_enabled && material_depth_amplitude_m>0.0) {
			mat3 normal_basis=mat3(surface_axis_x,surface_axis_y,surface_axis_z);
			vec3 n=normalize(inverse(normal_basis)*NORMAL);
			vec3 view_direction=normalize(transpose(normal_basis)*VIEW);
			float footprint=max(length(dFdx(bark_position)),length(dFdy(bark_position)));
			float amplitude=material_depth_amplitude_m*(1.0-smoothstep(8.0,18.0,length(VERTEX)))*smoothstep(0.06,0.18,dot(n,view_direction));
			painted_bark_relief_lod=vec2(ember_bark_recess_lod(bark_position,int(round(painted_bark_frames.x))),ember_bark_recess_lod(bark_position,int(round(painted_bark_frames.y))));
			if(amplitude>0.000001) {
				bark_position=material_depth_intersection(bark_position,n,view_direction,amplitude);
				NORMAL=normalize(normal_basis*ember_painted_bark_relief_normal(bark_position,n,amplitude,footprint));
			}
		}
#endif
		ALBEDO=ember_painted_bark_colour(bark_position,COLOR.rgb);
		ROUGHNESS=0.93;
	}
#endif
#ifdef EMBER_OBJECT_BARK_STUDY
	bark_study_shadow = 1.0;
	if (bark_study_enabled && surface_parameters.x > 1.5 && surface_parameters.x < 2.5) {
		vec3 p = surface_local_position;
		bark_study_footprint = max(length(dFdx(p)),length(dFdy(p)));
		mat3 normal_basis = mat3(surface_axis_x,surface_axis_y,surface_axis_z);
		vec3 n = normalize(inverse(normal_basis)*NORMAL);
		vec3 view_direction = normalize(transpose(normal_basis)*VIEW);
		float amplitude = material_depth_amplitude_m * ember_bark_fade(p,length(VERTEX)) * smoothstep(0.06,0.18,dot(n,view_direction));
		vec3 hit = amplitude > 0.00001 ? material_depth_intersection(p,n,view_direction,amplitude) : p;
		ALBEDO = ember_bark_albedo(hit,COLOR.rgb);
		NORMAL = normalize(mat3(surface_axis_x,surface_axis_y,surface_axis_z)*ember_bark_normal(hit,n,amplitude));
		ROUGHNESS = 0.92;
		if (amplitude > 0.00001) {
			vec3 view_hit = VERTEX+transpose(inverse(normal_basis))*(hit-p);
			LIGHT_VERTEX = view_hit;
			bark_study_shadow = material_depth_shadow_at(hit,n,amplitude);
		}
	}
#endif
	// Keep Godot's default LIGHT_VERTEX (= interpolated VERTEX in view space).
	// Rebuilding it through MODEL_MATRIX -> world -> VIEW_MATRIX introduces
	// enough precision drift to self-shadow large voxel surfaces as moire waves.
}

void light() {
#ifdef EMBER_OBJECT_PAINTED_FOLIAGE_STUDY
	// The accepted grass response uses this same leaf math and actual shadows.
	// Here the canopy's own macro normal carries shape; no ground slope noise.
	float rim_weight=0.0;
	float leaf_attenuation=ATTENUATION;
#ifdef EMBER_OBJECT_LEAF_CARDS_STUDY
	rim_weight=painted_leaf_rim_weight;
	if (LIGHT_IS_DIRECTIONAL && painted_leaf_shadow_strength!=1.0) {
		leaf_attenuation=mix(1.0,ATTENUATION,painted_leaf_shadow_strength);
	}
#endif
	vec2 leaf_response=ember_painterly_light(NORMAL,NORMAL,NORMAL,NORMAL,VIEW,LIGHT,1.0,rim_weight);
	float brightness=leaf_response.x;
	vec3 tint=ember_painted_grass_tint(NORMAL,LIGHT,ALBEDO*LIGHT_COLOR);
	DIFFUSE_LIGHT+=LIGHT_COLOR*leaf_attenuation*brightness*tint/PI;
#ifdef EMBER_OBJECT_LEAF_CARDS_STUDY
	if (LIGHT_IS_DIRECTIONAL) {
		if (painted_leaf_rim_weight>0.0) {
			SPECULAR_LIGHT+=LIGHT_COLOR*leaf_attenuation*leaf_response.y*mix(vec3(1.0),ALBEDO,0.45)/PI;
		}
		if (painted_leaf_transmission>0.0) {
			float through=ember_painterly_leaf_transmission(NORMAL,VIEW,LIGHT);
			DIFFUSE_LIGHT+=LIGHT_COLOR*leaf_attenuation*through*painted_leaf_transmission*vec3(1.05,1.03,0.82)/PI;
		}
	}
#endif
	if (LIGHT_IS_DIRECTIONAL) {
		float shade=smoothstep(0.08,0.92,1.0-leaf_attenuation);
		DIFFUSE_LIGHT+=LIGHT_COLOR*mix(vec3(0.85,0.96,1.0),painterly_grass_shadow_color,shade)*shade*painterly_grass_shadow_fill/PI;
	}
#else
	float surface_attenuation = ATTENUATION;
#ifdef EMBER_OBJECT_BARK_STUDY
	if (bark_study_enabled && surface_parameters.x > 1.5 && surface_parameters.x < 2.5 && LIGHT_IS_DIRECTIONAL) {
		surface_attenuation *= bark_study_shadow;
	}
#endif
	if (ember_object_surface_active()) {
		SPECULAR_LIGHT += LIGHT_COLOR * surface_attenuation * SPECULAR_AMOUNT * ember_object_surface_specular(NORMAL, LIGHT, VIEW, ROUGHNESS);
		DIFFUSE_LIGHT += LIGHT_COLOR * surface_attenuation * ember_object_surface_diffuse(NORMAL, LIGHT, VIEW);
	} else {
	DIFFUSE_LIGHT += ember_diorama_diffuse(ALBEDO, NORMAL, LIGHT, LIGHT_COLOR,
		ATTENUATION, LIGHT_IS_DIRECTIONAL, max(float(toon_steps), 2.0), band_floor, local_light_softness);
	}
#endif
	vec2 rim_profile=object_style_rim_profiles_enabled ? object_style_rim_profiles[clamp(int(round(surface_parameters.x)),0,6)] : vec2(object_style_rim_enabled ? 1.0 : 0.0,object_style_rim_strength);
	if (rim_profile.x>0.5 && LIGHT_IS_DIRECTIONAL && rim_profile.y>0.0) {
		// Use real visibility even when the foliage's diffuse shadows are softened.
		// NORMAL is the canopy-group normal on cards and the wood form on bark.
		vec3 rim_normal=NORMAL;
#ifdef EMBER_OBJECT_PAINTED_BARK_RELIEF_STUDY
		if(painted_bark_relief_enabled && material_depth_amplitude_m>0.0) rim_normal=normalize(painted_bark_form_normal);
#endif
#ifdef EMBER_OBJECT_VOXEL_LEAVES
		// The cell stays faceted; the shared rim follows its source leaf group.
		rim_normal=normalize(mix(NORMAL,voxel_leaf_form_normal,voxel_leaf_rim_form_weight));
#endif
		float rim=ember_stylized_rim(rim_normal,VIEW,LIGHT,1.0)*rim_profile.y;
		SPECULAR_LIGHT+=LIGHT_COLOR*ATTENUATION*rim*mix(vec3(1.0),ALBEDO,0.35)/PI;
	}
}
