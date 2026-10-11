shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
#include "res://shaders/ember_voxel_surface_light.gdshaderinc"
#include "res://shaders/ember_surface_optics.gdshaderinc"
uniform sampler2D optics_screen : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D optics_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform float optics_refraction_strength : hint_range(0.0, 0.08) = 0.02;
uniform float optics_clarity : hint_range(0.0, 1.0) = 0.94;
uniform float optics_body_opacity : hint_range(0.0, 1.0) = 0.18;
uniform float optics_ior : hint_range(1.0, 2.5) = 1.45;
uniform float optics_thickness_m : hint_range(0.01, 4.0) = 0.65;
uniform float optics_cloud_strength : hint_range(0.0, 1.0) = 0.0;
uniform float optics_cloud_scale : hint_range(0.25, 12.0) = 3.0;
uniform float optics_cloud_seed = 0.0;
uniform vec4 optics_cloud_light : source_color = vec4(1.0);
uniform vec4 optics_cloud_deep : source_color = vec4(0.38,0.38,0.5,1.0);
uniform float optics_surface_roughness = 0.0;
uniform float optics_surface_detail = 0.0;
uniform float optics_cloud_blur = 1.0;
uniform float optics_cloud_opacity = 0.55;
uniform float optics_absorption_strength = 2.0;
uniform float optics_crack_strength = 0.0;
uniform float optics_crack_scale = 1.5;
uniform float optics_crack_width = 0.004;
uniform float optics_bubble_strength = 0.0;
uniform float optics_bubble_scale = 8.0;
void fragment() {
	ROUGHNESS = ember_object_surface_active() ? ember_object_surface_roughness(surface_local_position) : 0.12;
	NORMAL = ember_object_surface_normal(NORMAL, surface_local_position);
	if (optics_surface_roughness > 0.0) { ROUGHNESS = clamp(optics_surface_roughness*surface_roughness_scale,0.045,1.0); }
	if (optics_surface_detail > 0.001 && surface_grain_scale > 0.001) {
		vec3 grain = mat3(surface_axis_x,surface_axis_y,surface_axis_z)*ember_object_grain(surface_local_position);
		vec3 tangent = grain-NORMAL*dot(grain,NORMAL);
		float fade = ember_object_grain_fade(surface_local_position);
		NORMAL = normalize(NORMAL+tangent*optics_surface_detail*surface_grain_scale*fade);
	}
	float f0 = pow((optics_ior - 1.0) / (optics_ior + 1.0), 2.0);
	SPECULAR = clamp(f0 * surface_specular_scale / 0.08, 0.0, 1.0);
	float fresnel = ember_surface_fresnel(max(dot(NORMAL, VIEW), 0.0), f0 * surface_specular_scale);
	float path_length = optics_thickness_m / max(dot(NORMAL, VIEW), 0.3);
	vec2 offset = ember_optics_offset(VERTEX, NORMAL, VIEW, PROJECTION_MATRIX, optics_ior, path_length)
		* optics_refraction_strength / 0.02;
	// Fade smoothly before clamping to the screen edge; never sample outside it.
	float edge = min(min(SCREEN_UV.x, 1.0-SCREEN_UV.x), min(SCREEN_UV.y, 1.0-SCREEN_UV.y));
	offset *= smoothstep(0.0, 0.035, edge);
	offset = clamp(offset, vec2(-0.08), vec2(0.08));
	vec2 uv = clamp(SCREEN_UV + offset, vec2(0.001), vec2(0.999));
	float depth = textureLod(optics_depth, uv, 0.0).r;
	vec3 behind = ember_optics_view_position(uv, depth, INV_PROJECTION_MATRIX);
	if (depth > 0.000001 && behind.z >= VERTEX.z - 0.01) { uv = SCREEN_UV; }
	float cloud = 0.0;
	if (optics_cloud_strength > 0.001) {
		float fade = 1.0-smoothstep(0.6,1.8,length(fwidth(surface_local_position*optics_cloud_scale)));
		cloud = ember_optics_cloud(surface_local_position,optics_cloud_scale,optics_cloud_seed)*optics_cloud_strength*fade;
	}
	float cracks = 0.0; float bubbles = 0.0;
	if (optics_crack_strength > 0.001 || optics_bubble_strength > 0.001) {
		vec3 local_ray = -normalize(vec3(dot(VIEW,normalize(surface_axis_x)),dot(VIEW,normalize(surface_axis_y)),dot(VIEW,normalize(surface_axis_z))));
		for (int layer=0; layer<2; layer++) {
			vec3 point = surface_local_position+local_ray*optics_thickness_m*(0.16+float(layer)*0.28);
			if (optics_crack_strength > 0.001) { cracks = max(cracks,ember_optics_cracks(point,optics_crack_scale,optics_crack_width,optics_cloud_seed)*optics_crack_strength); }
			if (optics_bubble_strength > 0.001) { bubbles = max(bubbles,ember_optics_bubbles(point,optics_bubble_scale,optics_cloud_seed+float(layer)*5.7)*optics_bubble_strength); }
		}
	}
	float blur = (1.0-optics_clarity)*5.0 + cloud*3.8*optics_cloud_blur;
	vec3 background = textureLod(optics_screen, uv, blur).rgb;
	vec3 tint = surface_gray_preview ? vec3(0.65) : COLOR.rgb;
	float density = 1.0-exp(-cloud*path_length*1.8);
	vec3 light_tint = surface_gray_preview ? vec3(0.82) : optics_cloud_light.rgb;
	vec3 deep_tint = surface_gray_preview ? vec3(0.28) : optics_cloud_deep.rgb;
	// Clear -> palette hue -> deeper absorption. Cloud scatter stays pale;
	// its saturation/blur vary smoothly, rather than becoming a solid decal.
	vec3 absorption_tint = mix(tint,deep_tint,density*0.72);
	vec3 body_tint = mix(tint,light_tint,cloud*0.85);
	float opacity = clamp(optics_body_opacity + density*optics_cloud_opacity,0.0,1.0);
	vec3 transmission = ember_optics_transmission(absorption_tint, opacity, path_length*optics_absorption_strength*0.5);
	float body = clamp(opacity * COLOR.a, 0.0, 1.0);
	// Background is already lit: emit it once, don't light it again. Direct/sky
	// reflection is supplied by the shared surface BRDF and Godot IBL.
	float features = clamp(cracks*0.32+bubbles*0.24,0.0,0.5);
	EMISSION = background * transmission * (1.0-fresnel) * (1.0-body) * (1.0-features);
	ALBEDO = body_tint * body + light_tint * features;
	ALPHA = 1.0; // full composition, captured screen + surface + environment
}
void light() {
	float nl = max(dot(NORMAL, LIGHT), 0.0);
	float nv = max(dot(NORMAL, VIEW), 0.0001);
	vec3 halfway = normalize(LIGHT + VIEW);
	float f0 = pow((optics_ior - 1.0) / (optics_ior + 1.0), 2.0) * surface_specular_scale;
	float fresnel = ember_surface_fresnel(max(dot(VIEW, halfway), 0.0), f0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT * nl * fresnel
		* ember_surface_specular(nl, nv, max(dot(NORMAL, halfway), 0.0), ROUGHNESS);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ember_surface_diffuse(nl, fresnel);
}
