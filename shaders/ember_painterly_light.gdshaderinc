// Opt-in LAB light response in the existing terrain renderer; no depth changes.
uniform bool painterly_enabled = false;
uniform bool painterly_rim_enabled = true;
uniform bool painterly_grass_enabled = true;
uniform bool painterly_blades = false;
uniform bool painterly_grass_masses = false;
uniform bool painterly_grass_color = false;
uniform float painterly_grass_low = 0.64;
uniform vec3 painterly_grass_cool = vec3(0.96, 1.0, 1.04);
uniform vec3 painterly_grass_warm = vec3(1.075, 1.0, 0.94);
uniform float painterly_grass_tint_strength = 1.0;
uniform float painterly_grass_shadow_fill = 0.07;
uniform vec3 painterly_grass_shadow_color = vec3(0.62, 0.90, 1.02);
varying float painterly_blade_height;
uniform float painterly_rim_strength : hint_range(0.0, 2.0) = 0.7;
uniform float painterly_band_softness : hint_range(0.01, 0.2) = 0.055;

float ember_painted_hash(vec2 p) {
	// Integer addressing keeps shared cell corners bit-identical. A sine hash
	// can expose lattice seams after GPU floating-point reassociation.
	uvec2 cell = uvec2(ivec2(p));
	uint h = cell.x * 1597334677u ^ cell.y * 3812015801u;
	h = (h ^ (h >> 16u)) * 2246822519u;
	h = (h ^ (h >> 13u)) * 3266489917u;
	return float((h ^ (h >> 16u)) & 0x00ffffffu) / 16777216.0;
}

float ember_painted_noise(vec2 p) {
	vec2 cell = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(ember_painted_hash(cell), ember_painted_hash(cell + vec2(1,0)), f.x),
		mix(ember_painted_hash(cell + vec2(0,1)), ember_painted_hash(cell + vec2(1)), f.x), f.y);
}

vec2 ember_painted_grass_steps(vec3 normal, vec3 light) {
	float nl = max(dot(normal, light), 0.0);
	float edge = max(0.018, fwidth(nl));
	return vec2(smoothstep(0.48 - edge, 0.48 + edge, nl),
		smoothstep(0.73 - edge, 0.73 + edge, nl));
}

vec3 ember_grass_light_tint(vec3 normal, vec3 light, vec3 lit_pigment, vec3 cool, vec3 warm, float strength) {
	// A restrained hue ramp follows the accepted light bands exactly.
	// No independent colour noise/clouds and no painted-on yellow stains.
	vec2 steps = ember_painted_grass_steps(normal, light);
	vec3 tint = mix(cool, vec3(1.0), steps.x);
	tint = mix(tint, warm, steps.y);
	tint = mix(vec3(1.0), tint, strength);
	vec3 luma = vec3(0.2126, 0.7152, 0.0722);
	return tint * dot(lit_pigment, luma) / max(dot(lit_pigment * tint, luma), 0.00001);
}

vec3 ember_painted_grass_tint(vec3 normal, vec3 light, vec3 lit_pigment) {
	return ember_grass_light_tint(normal,light,lit_pigment,painterly_grass_cool,painterly_grass_warm,painterly_grass_tint_strength);
}

vec3 ember_grass_masses_normal(vec3 world_position) {
	vec2 p = world_position.xz;
	float bend = ember_painted_noise(p * 0.65) - 0.5;
	vec2 uv = vec2(p.x + p.y * 0.32, p.y + bend * 0.45) * vec2(1.6, 3.4);
	vec2 slope = vec2(ember_painted_noise(uv), ember_painted_noise(uv + vec2(9.2, 3.7))) - 0.5;
	return normalize(vec3(slope.x * 1.6, 1.0, slope.y * 1.6));
}

vec3 ember_painted_grass_normal(vec3 form, vec3 world_position) {
	if (painterly_enabled && painterly_grass_masses) {
		// Connected oblique brush masses in world metres, shared by ground
		// and cards. The sun shades the mass, not each card's random yaw.
		return ember_grass_masses_normal(world_position);
	}
	// Broad connected patches; small tapered marks only break their boundaries.
	// Anchored to world metres: neither camera motion nor time slides the paint.
	vec2 p = world_position.xz;
	vec2 brush_uv = vec2(p.x + p.y * 0.22, p.y) * vec2(12.0, 3.5);
	float stroke = ember_painted_noise(brush_uv) - 0.5;
	float fine_fade = 1.0 - smoothstep(0.3, 1.0, length(fwidth(brush_uv)));
	vec2 patches = vec2(ember_painted_noise(p * 1.5), ember_painted_noise(p * 1.5 + vec2(8.7,3.1))) - 0.5;
	patches += vec2(stroke * 0.20 * fine_fade);
	return normalize(form + vec3(patches.x, 0.0, patches.y) * 0.75);
}

vec2 ember_painterly_light(vec3 form, vec3 detail, vec3 rim_normal, vec3 grass_normal,
		vec3 view, vec3 light, float grass_weight, float stone_weight) {
	float nl = max(dot(form, light), 0.0);
	float width = max(painterly_band_softness, fwidth(nl));
	float bands = 0.20 * smoothstep(0.0, width, nl)
		+ 0.27 * smoothstep(0.24 - width, 0.24 + width, nl)
		+ 0.28 * smoothstep(0.53 - width, 0.53 + width, nl)
		+ 0.25 * smoothstep(0.80 - width, 0.80 + width, nl);
	// Fine relief shades within the broad bands instead of fragmenting them.
	float relief = clamp(dot(detail, light) - dot(form, light), -0.35, 0.35);
	float diffuse = max(bands + relief * 0.22, 0.0);
	float grass_nl = max(dot(grass_normal, light), 0.0);
	float grass_width = max(0.055, fwidth(grass_nl));
	float grass_light = 0.55 * smoothstep(0.0, grass_width, grass_nl)
		+ 0.22 * smoothstep(0.46 - grass_width, 0.46 + grass_width, grass_nl)
		+ 0.23 * smoothstep(0.70 - grass_width, 0.70 + grass_width, grass_nl);
	if (painterly_grass_masses) {
		vec2 steps = ember_painted_grass_steps(grass_normal, light);
		// A wrapped three-tone response avoids black pits from imaginary
		// brush slopes. Real object shadows still multiply this in light().
		grass_light = painterly_grass_low + (1.0-painterly_grass_low)*0.5*(steps.x+steps.y);
	}
	diffuse = mix(diffuse, grass_light, grass_weight);
	// Use the interpolated macro normal for continuous edges. POM detail must
	// not create a luminous outline around every tiny cavity.
	float nv = max(dot(rim_normal, view), 0.0);
	float rim = 1.0 - smoothstep(0.10, 0.32, nv);
	// Backlight may reach a grazing face even when its N.L is slightly negative.
	rim *= smoothstep(-0.25, 0.25, dot(rim_normal, light));
	// Keep the sun-facing edge for lateral as well as back lighting. Only
	// near-frontal light suppresses it; N.L and shadows select the lit side.
	rim *= (1.0 - smoothstep(0.65, 0.90, dot(view, light))) * stone_weight;
	rim *= painterly_rim_enabled ? painterly_rim_strength : 0.0;
	return vec2(diffuse, rim);
}
