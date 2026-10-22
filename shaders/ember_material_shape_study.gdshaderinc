// Coordinate-only style layer. The accepted light/rim/shadow equations stay shared.
uniform int material_shape_mode = 0;
uniform float material_shape_strength : hint_range(0.0,1.0) = 0.7;
vec2 ember_material_shape_point(vec2 p) {
	if (material_shape_mode==0) return p;
	float span=material_shape_mode==1?0.36:0.0625;
	vec2 cell=floor(p/span), f=fract(p/span);
	vec2 centre=vec2(0.5);
	if (material_shape_mode==1) {
		centre=f.x+f.y<1.0?vec2(1.0/3.0):vec2(2.0/3.0);
	}
	float footprint=max(length(dFdx(p)),length(dFdy(p)))/span;
	float weight=(1.0-smoothstep(0.5,1.25,footprint))*material_shape_strength;
	return mix(p,(cell+centre)*span,weight);
}
