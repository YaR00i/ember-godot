shader_type fog;

// Forward+ study only. Each froxel looks back along the sun ray to the same
// moving surface field that lights the seabed.
uniform float ray_strength : hint_range(0.0, 1.0) = 0.35;
uniform float caustic_water_level = 16.02;
uniform vec2 caustic_sun_offset = vec2(0.31, -0.54);
uniform float wave_speed = 0.42;
uniform float wave_irregularity = 0.85;
uniform float local_bob_strength = 0.45;
uniform float preview_time = -1.0;

#include "res://shaders/ember_compact_study_wave.gdshaderinc"

void fog() {
	float depth = caustic_water_level - WORLD_POSITION.y;
	if (depth < 0.0 || depth > 64.0) {
		DENSITY = 0.0;
	} else {
		vec2 surface_point = (WORLD_POSITION.xz - caustic_sun_offset * depth) / 16.0;
		float seconds = preview_time >= 0.0 ? preview_time : TIME;
		float focus = study_caustic_focus(surface_point, seconds);
		float fade = exp(-depth * 0.026);
		DENSITY = 0.006 * focus * fade * ray_strength;
		ALBEDO = vec3(0.60, 0.88, 1.0);
		EMISSION = vec3(1.1, 1.5, 1.8) * focus * fade * ray_strength;
	}
}
