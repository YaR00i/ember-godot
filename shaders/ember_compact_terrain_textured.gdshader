shader_type spatial;
render_mode cull_back;

// Palette indices stay in vertex COLOR.a. Artwork can change without remeshing.
uniform sampler2D role_lookup : filter_nearest, repeat_disable;
uniform sampler2D pattern_atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D side_pattern_atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D finish_lookup : filter_nearest, repeat_disable;
uniform float texture_span = 64.0;
uniform int toon_steps : hint_range(3, 5) = 4;
uniform float band_floor : hint_range(0.0, 0.5) = 0.19;
uniform float local_light_softness : hint_range(0.0, 1.0) = 1.0;
uniform float terrain_side_fill : hint_range(0.0, 3.0) = 1.2;
uniform int material_light_mode : hint_enum("Previous", "Soft materials", "Toy plastic") = 0;
uniform bool material_gray_preview = false;
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
#include "res://shaders/ember_compact_study_wave.gdshaderinc"

varying vec3 terrain_position;
varying vec3 terrain_normal;
varying vec3 terrain_world_position;
varying float palette_slot;

void vertex() {
	terrain_position = VERTEX;
	terrain_normal = NORMAL;
	terrain_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	palette_slot = COLOR.a;
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
	if (has_pattern > 0) {
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
		vec2 uv = mirrored_tile(position / texture_span);
		ivec2 pixel = clamp(ivec2(floor(uv * 16.0)), ivec2(0), ivec2(15));
		ALBEDO = artwork_pixel(ivec2(pixel.x, palette_index * 16 + pixel.y), side_artwork).rgb;
		if (finish.b > 0.0 && (normal_axis.y > 0.5 || side_artwork)) {
			vec2 tile_phase = fract(position / texture_span * 0.5);
			vec2 mirror_sign = vec2(tile_phase.x < 0.5 ? 1.0 : -1.0,
				tile_phase.y < 0.5 ? 1.0 : -1.0);
			int row = palette_index * 16 + pixel.y;
			float left_height = artwork_pixel(ivec2(max(pixel.x - 1, 0), row), side_artwork).a;
			float right_height = artwork_pixel(ivec2(min(pixel.x + 1, 15), row), side_artwork).a;
			float near_height = artwork_pixel(ivec2(pixel.x, palette_index * 16 + max(pixel.y - 1, 0)), side_artwork).a;
			float far_height = artwork_pixel(ivec2(pixel.x, palette_index * 16 + min(pixel.y + 1, 15)), side_artwork).a;
			float relief = finish.b * (has_side_pattern ? 0.65 : 0.3);
			vec3 tangent = normal_axis.x > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
			vec3 bitangent = normal_axis.y > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
			vec3 painted_normal = normalize(terrain_normal
				+ tangent * (left_height - right_height) * relief * mirror_sign.x
				+ bitangent * (near_height - far_height) * relief * mirror_sign.y);
			NORMAL = normalize((VIEW_MATRIX * vec4(MODEL_NORMAL_MATRIX * painted_normal, 0.0)).xyz);
		}
	}
	if (material_light_mode == 2) {
		ROUGHNESS = 0.24;
		SPECULAR = 0.5;
	}
	if (material_gray_preview) {
		ALBEDO = vec3(0.32);
	}
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
}

void light() {
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
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * nl / PI
			* (1.0 - fresnel) * transmission;
		float specular = ember_surface_specular(nl, nv, nh, ROUGHNESS) * fresnel * transmission;
		if (coat > 0.0) {
			specular += ember_surface_specular(nl, nv, nh, 0.20) * coat_fresnel;
		}
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * nl * specular;
	} else {
	// Godot applies ALBEDO during final composition. Keep one palette tint.
	DIFFUSE_LIGHT += ember_diorama_diffuse(vec3(1.0), NORMAL, LIGHT, LIGHT_COLOR,
		ATTENUATION, LIGHT_IS_DIRECTIONAL, max(float(toon_steps), 2.0),
		band_floor, local_light_softness);
	// The stepped sides are only a few pixels high on screen. Keep a restrained
	// light-coloured bounce so they read as faces instead of black gaps.
	if (LIGHT_IS_DIRECTIONAL) {
		bool has_side_pattern = texelFetch(role_lookup, ivec2(int(round(palette_slot * 255.0)), 0), 0).g > 0.0;
		float side = has_side_pattern ? (1.0 - abs(terrain_normal.y)) * 0.55 : 1.0 - abs(NORMAL.y);
		float submerged_side = submerged_side_weight();
		DIFFUSE_LIGHT += shadow_tint * LIGHT_COLOR * terrain_side_fill * side
			* mix(1.0, ATTENUATION, submerged_side);
	}
	int palette_index = int(round(palette_slot * 255.0));
	vec2 finish = texelFetch(finish_lookup, ivec2(palette_index, 0), 0).rg;
	if (finish.y > 0.0) {
		vec3 halfway = normalize(LIGHT + VIEW);
		float focus = pow(max(dot(NORMAL, halfway), 0.0), mix(10.0, 72.0, finish.x));
		float highlight = smoothstep(0.06, 0.55, focus);
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * highlight
			* max(dot(NORMAL, LIGHT), 0.0) * finish.y * 0.42;
	}
	}
}
