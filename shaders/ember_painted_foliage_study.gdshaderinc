// Opt-in artwork on the existing solid LAB canopy. No alpha cards, displacement,
// emission, view-facing geometry or Source/normal changes.
#include "res://shaders/ember_painterly_light.gdshaderinc"
uniform sampler2D painted_foliage_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float painted_foliage_period_m = 3.5;
uniform vec3 painted_foliage_paint_reference = vec3(0.15,0.30,0.12);
#ifdef EMBER_OBJECT_LEAF_CARDS_STUDY
uniform sampler2D painted_leaf_card_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool painted_leaf_card_coloured = true;
uniform float painted_leaf_card_cutoff = 0.40;
uniform vec3 painted_leaf_card_plain : source_color = vec3(0.40,0.55,0.30);
// Colour detail only: alpha/silhouette and all shadow geometry stay authored.
uniform float painted_leaf_artwork_strength : hint_range(0.0,1.0) = 1.0;
// Optional two-colour paint ramp. Zero retains the accepted artwork/tint exactly.
uniform float painted_leaf_palette_strength : hint_range(0.0,1.0) = 0.0;
uniform vec3 painted_leaf_palette_primary : source_color = vec3(0.65,0.55,0.35);
uniform vec3 painted_leaf_palette_secondary : source_color = vec3(0.38,0.27,0.15);
uniform float painted_leaf_saturation : hint_range(1.0,1.4) = 1.0;
uniform float painted_leaf_transmission : hint_range(0.0,1.0) = 0.0;
uniform float painted_leaf_rim_weight : hint_range(0.0,1.0) = 0.0;
// Directional receiving response only. Godot combines external and inter-leaf
// shadows in ATTENUATION; this cannot distinguish their casters.
uniform float painted_leaf_shadow_strength : hint_range(0.0,1.0) = 1.0;
#endif

vec3 ember_foliage_linear_paint(vec3 pigment) {
	return mix(pigment/12.92,pow((pigment+vec3(0.055))/1.055,vec3(2.4)),step(vec3(0.04045),pigment));
}

#ifdef EMBER_OBJECT_LEAF_CARDS_STUDY
vec3 ember_leaf_card_colour(vec3 artwork,vec3 pigment) {
	vec3 paint=ember_foliage_linear_paint(pigment)/max(painted_foliage_paint_reference,vec3(0.00001));
	vec3 base=painted_leaf_card_coloured ? mix(painted_leaf_card_plain,artwork,painted_leaf_artwork_strength) : painted_leaf_card_plain;
	vec3 colour=clamp(base*paint,vec3(0.0),vec3(1.0));
	if (painted_leaf_palette_strength>0.0) {
		float tone=smoothstep(0.015,0.55,dot(artwork,vec3(0.2126,0.7152,0.0722)));
		vec3 palette=mix(painted_leaf_palette_secondary,painted_leaf_palette_primary,tone);
		colour=mix(colour,palette,painted_leaf_palette_strength);
	}
	if (painted_leaf_saturation!=1.0) {
		float gray=dot(colour,vec3(0.2126,0.7152,0.0722));
		colour=clamp(mix(vec3(gray),colour,painted_leaf_saturation),vec3(0.0),vec3(1.0));
	}
	return colour;
}
#endif

vec3 ember_painted_foliage_colour(vec3 local_position,vec3 pigment,vec3 view_normal) {
	mat3 basis=mat3(surface_axis_x,surface_axis_y,surface_axis_z);
	vec3 local_normal=normalize(inverse(basis)*view_normal);
	vec3 weights=pow(abs(local_normal),vec3(4.0));weights/=max(dot(weights,vec3(1.0)),0.00001);
	// Local metres prevent pole stretching of the old dome UVs and anchor the
	// paint to the same object when the tree or camera moves.
	vec3 p=local_position/max(painted_foliage_period_m,0.01);
	vec3 artwork=texture(painted_foliage_albedo,p.zy).rgb*weights.x
		+texture(painted_foliage_albedo,p.xz).rgb*weights.y
		+texture(painted_foliage_albedo,p.xy).rgb*weights.z;
	vec3 paint=ember_foliage_linear_paint(pigment)/max(painted_foliage_paint_reference,vec3(0.00001));
	return clamp(artwork*paint,vec3(0.0),vec3(1.0));
}
