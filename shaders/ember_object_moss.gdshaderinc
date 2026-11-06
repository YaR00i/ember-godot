uniform bool object_moss_enabled = false;
uniform sampler3D object_moss_mask : filter_linear, repeat_disable;
uniform vec3 object_moss_origin;
uniform vec3 object_moss_extent = vec3(1.0);
uniform vec3 object_moss_shadow = vec3(0.135, 0.252, 0.049);
uniform vec3 object_moss_light = vec3(0.288, 0.421, 0.104);

float moss_grain(vec3 cell) {
	vec3 v = fract(cell * vec3(0.1031, 0.11369, 0.13787));
	v += dot(v, v.yzx + 19.19);
	return fract((v.x + v.y) * v.z);
}

float moss_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = smoothstep(vec3(0.0), vec3(1.0), fract(p));
	float a = mix(moss_grain(cell), moss_grain(cell + vec3(1, 0, 0)), f.x);
	float b = mix(moss_grain(cell + vec3(0, 1, 0)), moss_grain(cell + vec3(1, 1, 0)), f.x);
	float c = mix(moss_grain(cell + vec3(0, 0, 1)), moss_grain(cell + vec3(1, 0, 1)), f.x);
	float d = mix(moss_grain(cell + vec3(0, 1, 1)), moss_grain(cell + vec3(1, 1, 1)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

void ember_object_moss(vec3 local, inout vec3 color, inout float roughness, inout float specular) {
	if (!object_moss_enabled) { return; }
	vec3 uv = (local - object_moss_origin) / object_moss_extent;
	float mask = texture(object_moss_mask, uv).r;
	if (mask <= 0.001) { return; }
	// Broad brushwork carries the tone. Small strokes only break up the solid fill.
	float wash = moss_noise(local * 5.5);
	float stroke = moss_noise(local * vec3(24.0, 14.0, 23.0));
	float brushwork = smoothstep(0.43, 0.72, stroke);
	float moss = smoothstep(0.08, 0.78, mask * mix(0.73, 1.26, wash) + mask * (brushwork - 0.5) * 0.13);
	vec3 moss_color = mix(object_moss_shadow, object_moss_light,
		wash * 0.70 + brushwork * 0.30);
	color = mix(color, moss_color, moss * 0.95);
	roughness = mix(roughness, 0.94, moss);
	specular = mix(specular, 0.13, moss);
}
