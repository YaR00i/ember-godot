shader_type spatial;
render_mode cull_disabled;

uniform vec4 rope_color : source_color = vec4(0.27, 0.13, 0.05, 1.0);
uniform bool free_end = false;
uniform float load_progress = 0.0;
uniform float load_amount = 0.0;
uniform float phase = 0.0;

void vertex() {
	float t = UV.x;
	float envelope = free_end ? t * t : 4.0 * t * (1.0 - t);
	float wave = sin(phase - t * 5.0);
	if (free_end) {
		float weight = max(0.0, 1.0 - abs(t - load_progress) * 3.2);
		VERTEX.z += (wave * 2.7 + 0.5 * weight) * envelope * load_amount;
	} else {
		// Same span response as rope_offset(): each half runs to its fixed anchor.
		float sag = min(t, load_progress) * (1.0 - max(t, load_progress));
		VERTEX.y -= 10.0 * sag * load_amount;
		VERTEX.z += wave * 0.65 * envelope * load_amount;
	}
}

void fragment() {
	ALBEDO = rope_color.rgb;
	ROUGHNESS = 0.86;
}
