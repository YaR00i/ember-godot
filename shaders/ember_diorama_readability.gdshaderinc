// Temporary optical comparison; preserve coordinates, pigment, height and geometry.
uniform float readability_quiet_strength = 0.0;
uniform float readability_colour_mip = 3.0;

vec3 ember_readability_colour(vec2 uv,float layer,vec3 original) {
	if (readability_quiet_strength < 0.00001) return original;
	float footprint = max(length(dFdx(uv)),length(dFdy(uv))) * float(textureSize(png_albedo_bank,0).x);
	float lod = max(readability_colour_mip,log2(max(footprint,1.0)));
	vec3 broad = textureLod(png_albedo_bank,vec3(uv,layer),lod).rgb;
	return mix(original,broad,readability_quiet_strength);
}
