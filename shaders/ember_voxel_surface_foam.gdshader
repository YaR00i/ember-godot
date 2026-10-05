shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

// The Surface mesher owns every real wet/dry boundary and stores signed shore
// distance in UV.x, boundary kind in UV.y and the waterward direction in UV2.
// The shader turns that stable geometry into approach, runup and reflection.
uniform vec3 foam_color : source_color = vec3(0.90, 1.0, 0.94);
uniform vec3 foam_shadow : source_color = vec3(0.58, 0.90, 0.84);
uniform float alpha_scale : hint_range(0.0, 1.0) = 0.64;
uniform float pixel_density : hint_range(8.0, 32.0, 1.0) = 16.0;
uniform float animation_fps : hint_range(0.0, 6.0, 0.25) = 2.0;
uniform float systemic_shore_strength : hint_range(0.0, 1.0) = 0.82;
// Optional Shore Lab overlay. Production contact strips keep mode 0 and retain
// the geometry-owned sparse shoreline above.
uniform int shore_lab_mode = 0; // 1: beach runup, 2: wall contact
uniform float preview_time = -1.0;
uniform float shore_boundary_x = -4.75;
uniform float shore_split_z = 0.0;
uniform float shore_zone_gap = 1.35;
uniform float shore_zone_outer = 6.65;
uniform float shore_break_distance : hint_range(0.25, 4.0) = 1.35;
uniform float shore_runup_distance : hint_range(0.0, 2.0) = 1.05;
uniform float shore_foam_width : hint_range(0.03, 0.4) = 0.09;
uniform float shore_wet_trace : hint_range(0.0, 1.0) = 0.42;
uniform float shore_reflection_strength : hint_range(0.0, 1.0) = 0.50;
uniform float shore_reflection_distance : hint_range(0.25, 4.0) = 2.35;
uniform float shore_response_distance : hint_range(1.0, 8.0) = 4.0;
uniform float shore_wave_transform : hint_range(0.0, 1.0) = 0.0;
uniform float shore_shoaling_distance : hint_range(1.0, 8.0) = 4.5;
uniform float shore_shallow_depth : hint_range(0.0, 0.8) = 0.10;
uniform float shore_deep_depth : hint_range(0.1, 1.0) = 0.72;
uniform float shore_refraction_strength : hint_range(0.0, 1.0) = 0.86;
uniform float shore_wavelength_compression : hint_range(0.0, 0.68) = 0.42;
uniform float shore_shoaling_strength : hint_range(0.0, 1.0) = 0.48;
uniform float shore_crest_coherence : hint_range(0.0, 1.0) = 0.76;
uniform float shore_break_threshold : hint_range(0.25, 1.2) = 0.78;
uniform float shore_break_softness : hint_range(0.02, 0.30) = 0.10;
uniform float shore_runup_speed : hint_range(0.1, 2.0) = 0.72;
uniform float wave_length : hint_range(0.25, 8.0) = 1.6;
uniform float wave_speed : hint_range(0.0, 2.0) = 0.35;
uniform float wave_strength : hint_range(0.02, 0.25) = 0.10;
uniform float wave_direction_degrees : hint_range(-180.0, 180.0) = 36.87;
uniform float wave_natural_mix : hint_range(0.0, 1.0) = 0.0;
uniform float wave_direction_spread : hint_range(0.0, 60.0, 1.0) = 18.0;
uniform float wave_scale_variation : hint_range(0.0, 1.0) = 0.55;
uniform float wave_grouping : hint_range(0.0, 1.0) = 0.58;
uniform float wind_ripple_strength : hint_range(0.0, 1.0) = 0.18;
uniform float wave_crest_sharpness : hint_range(0.0, 1.0) = 0.25;
uniform float coordinate_scale = 0.0;
uniform vec3 wet_color : source_color = vec3(0.10, 0.48, 0.45);

#include "res://shaders/ember_water_wave.gdshaderinc"

varying vec2 surface_coordinate;


float shore_cycle(vec2 coordinate, float seconds) {
	float angle = radians(wave_direction_degrees);
	vec2 direction = vec2(cos(angle), sin(angle));
	vec2 boundary_point = vec2(shore_boundary_x, coordinate.y) / max(wave_length, 0.001);
	float phase_warp = sin(coordinate.y * 0.47) * 0.42 + sin(coordinate.y * 0.91 + 1.3) * 0.18;
	float phase = dot(boundary_point, direction) * 6.283185 + phase_warp - seconds * wave_speed;
	return fract(-phase / 6.283185);
}


float shared_crest_line(vec3 wave, vec2 travel_direction) {
	// A crest is the narrow ridge where height is positive and the directional
	// slope passes through zero. Selecting the whole high area makes a soft blob;
	// selecting this ridge keeps the old readable line while still deriving it
	// from the exact water field.
	float positive_crest = smoothstep(0.10, 0.40, wave.z);
	float width_factor = clamp(shore_foam_width / 0.40, 0.0, 1.0);
	float ridge_width = mix(0.08, 0.17, width_factor);
	float directional_slope = abs(dot(wave.xy, travel_direction));
	float ridge = 1.0 - smoothstep(ridge_width, ridge_width * 2.15, directional_slope);
	return positive_crest * ridge;
}


void vertex() {
	float block_scale = coordinate_scale > 0.0
		? coordinate_scale
		: max(length(MODEL_MATRIX[0].xyz), 0.001);
	surface_coordinate = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz / block_scale;
}


void fragment() {
	if (shore_lab_mode == 1) {
		float seconds = preview_time >= 0.0 ? preview_time : TIME;
		vec2 graphic_coordinate = (floor(surface_coordinate * 16.0) + vec2(0.5)) / 16.0;
		float cycle = shore_cycle(graphic_coordinate, seconds);
		float bend = sin(graphic_coordinate.y * 0.73 + 0.4) * 0.085
			+ sin(graphic_coordinate.y * 1.67 + 1.7) * 0.035;
		float land_distance = max(shore_boundary_x - graphic_coordinate.x, 0.0);
		// The surface crest reaches the boundary near cycle 0.44. It then climbs
		// the beach, pauses briefly at maximum reach and drains back before the
		// next crest arrives. Both directions use one continuous front.
		float runup = smoothstep(0.42, 0.69, cycle);
		float backwash = smoothstep(0.72, 0.98, cycle);
		float runup_envelope = runup * (1.0 - backwash);
		float front = shore_runup_distance * runup_envelope;
		float active = smoothstep(0.40, 0.46, cycle) * (1.0 - smoothstep(0.97, 1.0, cycle));
		float foam = 1.0 - smoothstep(
			shore_foam_width * 0.38,
			shore_foam_width * 0.82,
			abs(land_distance - front - bend)
		);
		float beach_zone = smoothstep(
			shore_split_z + shore_zone_gap,
			shore_split_z + shore_zone_gap + 0.16,
			graphic_coordinate.y
		) * (1.0 - smoothstep(
			shore_split_z + shore_zone_outer - 0.16,
			shore_split_z + shore_zone_outer,
			graphic_coordinate.y
		));
		foam *= active * beach_zone;
		float water_sheet = (1.0 - smoothstep(
			front + shore_foam_width * 0.25,
			front + shore_foam_width * 1.25,
			land_distance
		)) * active * beach_zone;
		float trace_life = smoothstep(0.57, 0.72, cycle)
			* (1.0 - smoothstep(0.92, 1.0, cycle));
		float trace_reach = shore_runup_distance * (0.90 + bend * 0.22);
		float wet_trace = (1.0 - smoothstep(
			trace_reach - shore_foam_width,
			trace_reach + shore_foam_width * 1.8,
			land_distance
		)) * trace_life * beach_zone * shore_wet_trace;
		float wet = max(water_sheet * 0.62, wet_trace) * (1.0 - foam * 0.30);
		float connected_variation = 0.82 + 0.18 * (sin(graphic_coordinate.y * 0.61 + 0.6) * 0.5 + 0.5);
		ALBEDO = mix(foam_shadow, wet_color, clamp(water_sheet * 0.82 + wet * 0.36, 0.0, 1.0));
		ALBEDO = mix(ALBEDO, foam_color, foam);
		EMISSION = foam_color * foam * 0.014;
		ALPHA = clamp(water_sheet * 0.27 + wet * 0.32
			+ foam * alpha_scale * connected_variation, 0.0, 0.82);
	} else if (shore_lab_mode == 2) {
		float seconds = preview_time >= 0.0 ? preview_time : TIME;
		vec2 graphic_coordinate = (floor(surface_coordinate * 16.0) + vec2(0.5)) / 16.0;
		float cycle = shore_cycle(graphic_coordinate, seconds);
		float distance_to_boundary = abs(graphic_coordinate.x - shore_boundary_x);
		float impact = 1.0 - smoothstep(0.035, 0.12, abs(cycle - 0.46));
		float contact = 1.0 - smoothstep(
			shore_foam_width * 0.34,
			shore_foam_width * 0.72,
			distance_to_boundary
		);
		float wall_zone = smoothstep(
			shore_split_z - shore_zone_outer,
			shore_split_z - shore_zone_outer + 0.16,
			graphic_coordinate.y
		) * (1.0 - smoothstep(
			shore_split_z - shore_zone_gap - 0.16,
			shore_split_z - shore_zone_gap,
			graphic_coordinate.y
		));
		contact *= wall_zone;
		float impact_line = contact * impact;
		float standing_contact = contact * 0.24;
		float reflection_phase = clamp((cycle - 0.46) / 0.54, 0.0, 1.0);
		float reflected_front = reflection_phase * shore_reflection_distance;
		float reflected = 1.0 - smoothstep(
			shore_foam_width * 0.28,
			shore_foam_width * 0.68,
			abs(distance_to_boundary - reflected_front)
		);
		reflected *= smoothstep(0.46, 0.50, cycle)
			* (1.0 - smoothstep(0.88, 1.0, reflection_phase));
		reflected *= exp(-distance_to_boundary * 0.52) * shore_reflection_strength * wall_zone;
		float visible_contact = max(standing_contact, max(impact_line, reflected));
		ALBEDO = mix(foam_shadow, foam_color, clamp(0.30 + impact * 0.58 + reflected * 0.42, 0.0, 1.0));
		EMISSION = foam_color * max(impact_line, reflected * 0.62) * 0.014;
		ALPHA = visible_contact * alpha_scale;
	} else {
		float metadata_length = length(UV2);
		if (metadata_length > 0.5) {
			float seconds = preview_time >= 0.0 ? preview_time : TIME;
			vec2 inward = UV2 / metadata_length;
			vec2 graphic_coordinate = (floor(surface_coordinate * pixel_density) + vec2(0.5))
				/ pixel_density;
			float signed_distance = sign(UV.x)
				* floor(abs(UV.x) * pixel_density + 0.5) / pixel_density;
			vec2 boundary_coordinate = graphic_coordinate - inward * signed_distance;
			float wall = step(0.5, UV.y);
			float water_distance = max(signed_distance, 0.0);
			float land_distance = max(-signed_distance, 0.0);
			float depth_factor = clamp(COLOR.b, 0.0, 1.0);
			float wave_scale = max(wave_length, 0.001);
			float shore_amount = water_shore_amount(water_distance, shore_shoaling_distance)
				* water_shallow_amount(depth_factor, shore_shallow_depth, shore_deep_depth)
				* shore_wave_transform;
			vec2 travel_direction = water_shore_travel_direction(
				inward, wall, shore_amount, shore_refraction_strength
			);
			vec3 local_wave = water_shore_wave_state(
				graphic_coordinate, seconds, water_distance, depth_factor, inward, wall,
				shore_wave_transform, shore_shoaling_distance,
				shore_shallow_depth, shore_deep_depth,
				shore_refraction_strength, shore_wavelength_compression,
				shore_shoaling_strength, shore_crest_coherence
			);
			vec3 boundary_wave = water_shore_wave_state(
				boundary_coordinate, seconds, 0.0, shore_shallow_depth, inward, wall,
				shore_wave_transform, shore_shoaling_distance,
				shore_shallow_depth, shore_deep_depth,
				shore_refraction_strength, shore_wavelength_compression,
				shore_shoaling_strength, shore_crest_coherence
			);

			// The breaker is the narrow ridge of the visible water wave itself. No
			// second phase or independently travelling front exists here.
			float shore_band = 1.0 - smoothstep(
				shore_break_distance * 0.72,
				shore_break_distance,
				water_distance
			);
			float breaking = water_break_factor(
				local_wave, depth_factor, shore_shallow_depth, wave_strength,
				shore_break_threshold, shore_break_softness
			);
			float incoming = shared_crest_line(local_wave, travel_direction)
				* shore_band * breaking;
			incoming *= step(-0.001, signed_distance);
			float boundary_break = water_break_factor(
				boundary_wave, shore_shallow_depth, shore_shallow_depth, wave_strength,
				shore_break_threshold, shore_break_softness
			);
			float impact = shared_crest_line(boundary_wave, travel_direction) * boundary_break;
			float contact = 1.0 - smoothstep(
				shore_foam_width * 0.34,
				shore_foam_width * 0.82,
				abs(signed_distance)
			);

			// Mirroring the same field across a hard boundary reverses its normal
			// travel without inventing another wave. The reflected copy only exists
			// where the original crest has already crossed the wall line.
			vec2 reflected_coordinate = graphic_coordinate - inward * water_distance * 2.0;
			vec3 reflected_wave = water_shore_wave_state(
				reflected_coordinate, seconds, water_distance, depth_factor, inward, wall,
				shore_wave_transform, shore_shoaling_distance,
				shore_shallow_depth, shore_deep_depth,
				shore_refraction_strength, shore_wavelength_compression,
				shore_shoaling_strength, shore_crest_coherence
			);
			float reflected = shared_crest_line(reflected_wave, travel_direction);
			reflected *= exp(-water_distance / max(shore_reflection_distance, 0.001));
			// The derived response mesh is finite. Fade before its far edge so a
			// reflected crest dissolves into open water instead of ending on the
			// last row of geometry as a straight cut.
			float reflection_fade_width = max(shore_reflection_distance * 0.45, 0.65);
			float reflection_edge_fade = 1.0 - smoothstep(
				max(shore_response_distance - reflection_fade_width, 0.0),
				shore_response_distance,
				water_distance
			);
			reflected *= reflection_edge_fade;
			reflected *= shore_reflection_strength * wall * step(-0.001, signed_distance);

			// On a low bank the very same crest continues over the derived land
			// strip. Distance only attenuates it; shape and timing stay continuous
			// through the wet/dry boundary.
			float land_mask = (1.0 - smoothstep(
				shore_runup_distance * 0.78,
				shore_runup_distance,
				land_distance
			)) * (1.0 - wall) * step(-0.001, -signed_distance);
			// Measure the age of this exact dominant crest after it crossed the
			// boundary. Its world-space front is deliberately narrower than one
			// voxel step, so a single wave cannot light several terraces at once.
			float boundary_phase = dominant_wave_phase(
				boundary_coordinate / wave_scale, seconds
			);
			float phase_age = mod(1.570796 - boundary_phase, 6.283185);
			float runup_age = phase_age / max(wave_speed, 0.05);
			float front_distance = runup_age * shore_runup_speed;
			float crest_time = seconds - runup_age;
			vec3 boundary_crest_wave = water_shore_wave_state(
				boundary_coordinate, crest_time,
				0.0, 0.0, inward, 0.0,
				shore_wave_transform, shore_shoaling_distance,
				shore_shallow_depth, shore_deep_depth,
				shore_refraction_strength, shore_wavelength_compression,
				shore_shoaling_strength, shore_crest_coherence
			);
			float runup_break = water_break_factor(
				boundary_crest_wave, 0.0, shore_shallow_depth, wave_strength,
				shore_break_threshold, shore_break_softness
			);
			float front_active = 1.0 - smoothstep(
				shore_runup_distance * 0.86,
				shore_runup_distance,
				front_distance
			);
			float runup_foam = 1.0 - smoothstep(
				shore_foam_width * 0.42,
				shore_foam_width * 1.08,
				abs(land_distance - front_distance)
			);
			runup_foam *= land_mask * front_active * runup_break * 1.25;
			// Only a quiet translucent sheet remains behind the single white edge.
			float water_sheet = 1.0 - smoothstep(
				front_distance + shore_foam_width * 0.20,
				front_distance + shore_foam_width * 1.20,
				land_distance
			);
			water_sheet *= land_mask * front_active * runup_break * 0.28;
			float trace_life = smoothstep(
				shore_runup_distance * 0.52,
				shore_runup_distance * 0.88,
				front_distance
			) * (1.0 - smoothstep(
				shore_runup_distance,
				shore_runup_distance * 2.15,
				front_distance
			));
			float wet_trace = (1.0 - smoothstep(
				shore_runup_distance * 0.72,
				shore_runup_distance,
				land_distance
			)) * trace_life * land_mask * shore_wet_trace;

			float standing_contact = contact * mix(0.07, 0.20, wall);
			float visible_foam = max(incoming * 1.25, max(contact * impact, max(reflected, runup_foam)));
			visible_foam = max(visible_foam, standing_contact);
			float wet = max(water_sheet * 0.62, wet_trace) * (1.0 - visible_foam * 0.30);
			ALBEDO = mix(foam_shadow, wet_color, clamp(water_sheet * 0.82 + wet * 0.36, 0.0, 1.0));
			ALBEDO = mix(ALBEDO, foam_color, visible_foam);
			EMISSION = foam_color * max(contact * impact, max(reflected, runup_foam)) * 0.014;
			ALPHA = clamp(
				water_sheet * 0.27 + wet * 0.32
					+ visible_foam * alpha_scale * COLOR.a,
				0.0,
				0.84
			) * systemic_shore_strength;
		} else {
			// Compatibility for already-derived meshes until their chunk is rebuilt.
			vec2 pixel = floor(surface_coordinate * pixel_density);
			float frame = floor(TIME * animation_fps);
			float drift = sin((pixel.x + pixel.y) * 0.72 + frame * 0.22) * 0.5 + 0.5;
			float stepped = floor(clamp(drift, 0.0, 0.999) * 3.0) / 2.0;
			ALBEDO = mix(foam_shadow, foam_color, 0.68 + stepped * 0.32);
			EMISSION = foam_color * 0.012;
			ALPHA = COLOR.a * alpha_scale * (0.72 + stepped * 0.18);
		}
	}
}
