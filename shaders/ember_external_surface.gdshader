shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Display-only opaque albedo adapter. Shared field/targets/light cells retain
// their existing owners. No edits to the imported StandardMaterial or texture.
#include "res://shaders/ember_world_anomaly.gdshaderinc"
#include "res://shaders/ember_voxel_light.gdshaderinc"
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_albedo_texture = false;
uniform sampler2D palette_color_lookup : filter_nearest, repeat_disable;
uniform float roughness = 0.92;
uniform float metallic = 0.0;
uniform float specular = 0.5;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
varying vec3 reference_position;
varying float look_weight;
varying float cell_light_weight;

void vertex() {
	reference_position = VERTEX;
	look_weight = ember_anomaly_prepared ? ember_anomaly_weight((MODEL_MATRIX * vec4(VERTEX,1.0)).xyz) : 0.0;
	ember_anomaly_vertex(VERTEX, NORMAL, MODEL_MATRIX, VERTEX_ID);
	UV = UV * uv1_scale.xy + uv1_offset.xy;
}

void fragment() {
	vec3 pigment = albedo.rgb;
	if (has_albedo_texture) pigment *= texture(texture_albedo,UV).rgb;
	float voxel_weight = ember_anomaly_band_look.y > 1.5 ? look_weight : 0.0;
	vec3 voxel_pigment = texelFetch(palette_color_lookup,ivec2(int(round(COLOR.a*255.0)),0),0).rgb;
	ALBEDO = mix(pigment,voxel_pigment,voxel_weight);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
	cell_light_weight = voxel_light_enabled ? 1.0 : voxel_light_anomaly ? voxel_weight : 0.0;
	if (!IN_SHADOW_PASS && cell_light_weight > 0.0) {
		vec3 n = normalize(cross(dFdx(reference_position),dFdy(reference_position))+vec3(0.0000001));
		vec3 sample_delta = ember_texel_sample(reference_position,reference_position,n,voxel_light_cell,0.0);
		sample_delta.z *= cell_light_weight;
		LIGHT_VERTEX = ember_texel_extrapolate(VERTEX,sample_delta);
		NORMAL = normalize(ember_texel_extrapolate(NORMAL,sample_delta));
	}
}

float fresnel_weight(float cosine) {
	float m = 1.0-clamp(cosine,0.0,1.0);
	return m*m*m*m*m;
}

void light() {
	// Burley / isotropic GGX, as in Godot's opaque StandardMaterial. Only the
	// voxel part quantizes diffuse light, using the existing map settings.
	float nl = max(dot(NORMAL,LIGHT),0.0);
	float nv = max(dot(NORMAL,VIEW),0.0001);
	vec3 h = normalize(LIGHT+VIEW);
	float lh = clamp(dot(LIGHT,h),0.0,1.0);
	float nh = max(dot(NORMAL,h),0.0);
	float fd90 = 2.0*lh*lh*ROUGHNESS-0.5;
	float diffuse = nl*(1.0+fd90*fresnel_weight(nv))*(1.0+fd90*fresnel_weight(nl))/PI;
	vec3 contribution = LIGHT_COLOR*ATTENUATION*diffuse*(1.0-METALLIC);
	DIFFUSE_LIGHT += mix(contribution,ember_texel_light_steps(contribution,LIGHT_COLOR,voxel_light_levels),cell_light_weight);
	if (nl > 0.0) {
		float alpha = max(ROUGHNESS*ROUGHNESS,0.0001);
		float denominator = 1.0-nh*nh+nh*nh*alpha*alpha;
		float distribution = alpha*alpha/(PI*denominator*denominator);
		float visibility = 0.5/max(mix(2.0*nl*nv,nl+nv,alpha),0.0001);
		vec3 f0 = mix(vec3(0.16*specular*specular),ALBEDO,METALLIC);
		vec3 fresnel = mix(f0,vec3(1.0),fresnel_weight(lh));
		SPECULAR_LIGHT += LIGHT_COLOR*ATTENUATION*SPECULAR_AMOUNT*nl*distribution*visibility*fresnel;
	}
}
