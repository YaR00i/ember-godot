class_name EmberLights
extends RefCounted
## OmniLight3D / DirectionalLight3D from Ember authored fields.
## Energy / fog follow JOI `threeLighting.ts` + `fogDensity.ts` so the night
## village is readable. Not a second schema.

const FOG_EXP2_DENSITY_AT_ONE := 0.02
const FOG_HAZE_AS_FOG := 0.28
const FOG_HAZE_DENSITY := 0.003
const TOON_SHADER: Shader = preload("res://shaders/ember_voxel_toon.gdshader")
const TOON_TRANSPARENT_SHADER: Shader = preload("res://shaders/ember_voxel_transparent.gdshader")
const SKY_SHADER: Shader = preload("res://shaders/ember_night_sky.gdshader")
## Layer 1 = world casters (terrain, props, player). Layer 2 = lamp ShadowBody
## so Omni cube maps do not eat their own host cage (fill stays on the street).
const SHADOW_LAYER_WORLD := 1
const SHADOW_LAYER_LAMP_HOST := 2
## Explicit stress ceiling. Production remains 8 until populated-scene retesting.
const MAX_OMNI_SHADOWS := 16


static func fog_density(fog: float, haze := 0.0) -> float:
	var f := clampf(fog, 0.0, 1.0)
	var h := clampf(haze, 0.0, 1.0)
	var amt := minf(1.0, f + h * FOG_HAZE_AS_FOG)
	if amt <= 0.0 and h <= 0.0:
		return 0.0
	return amt * FOG_EXP2_DENSITY_AT_ONE + h * FOG_HAZE_DENSITY


static func night_ambient_energy(fill_intensity: float, ambient_alpha: float) -> float:
	var night := clampf(ambient_alpha, 0.0, 1.0)
	return maxf(0.012, (0.18 - night * 0.12) * fill_intensity * 0.28)


static func lamp_point_color(lamp_color: Color, face_color: Color) -> Color:
	return Color(
		lamp_color.r * 0.62 + face_color.r * 0.38,
		lamp_color.g * 0.62 + face_color.g * 0.38,
		lamp_color.b * 0.62 + face_color.b * 0.38,
	)


static func omni_energy(strength0: float, falloff: float, lamp_power: float, night: float) -> float:
	var s0 := clampf(strength0, 0.0, 1.0)
	var fo := clampf(falloff, 0.0, 1.0)
	var night_boost := 1.0 + clampf(night, 0.0, 1.0) * 0.55
	var joi := (7.0 + s0 * 16.0) * (0.7 + fo * 0.55) * maxf(0.35, lamp_power) * night_boost
	return maxf(6.0, joi * 0.92)


static func moon_energy(sun_intensity: float, fill_intensity: float, night: float, scale := 1.0) -> float:
	var n := clampf(night, 0.0, 1.0)
	return maxf(0.5, (1.05 + n * 0.35) * maxf(0.4, sun_intensity) * (0.45 + fill_intensity) * scale)


static func night_sun_energy(sun_intensity: float, fill_intensity: float, ambient_alpha: float) -> float:
	var night := clampf(ambient_alpha, 0.0, 1.0)
	return maxf(0.02, (2.55 - night * 0.45) * fill_intensity * maxf(0.0, sun_intensity))


static func make_sky_material(
	night: float,
	fog: float,
	fog_col: Color,
	moon_dir: Vector3,
	moon_col: Color,
	star_amount: float,
	moon_size: float,
	fog_mix: float,
) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SKY_SHADER
	var n := clampf(night, 0.0, 1.0)
	var zenith := Color(0.031, 0.039, 0.11).lerp(Color(0.43, 0.67, 0.9), 1.0 - n)
	var horizon := Color(0.071, 0.086, 0.188).lerp(Color(0.75, 0.82, 0.92), 1.0 - n)
	mat.set_shader_parameter("zenith_color", zenith)
	mat.set_shader_parameter("horizon_color", horizon)
	mat.set_shader_parameter("fog_color", fog_col)
	mat.set_shader_parameter("fog_mix", clampf(fog * 0.55 + fog_mix, 0.0, 0.7))
	mat.set_shader_parameter("moon_dir", moon_dir.normalized())
	mat.set_shader_parameter("moon_color", moon_col)
	mat.set_shader_parameter("moon_size", moon_size)
	mat.set_shader_parameter("stars", star_amount * n)
	return mat


static func voxel_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TOON_SHADER
	mat.set_shader_parameter("toon_steps", 4)
	mat.set_shader_parameter("band_floor", 0.19)
	mat.set_shader_parameter("local_light_softness", 1.0)
	return mat


static func voxel_transparent_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TOON_TRANSPARENT_SHADER
	mat.render_priority = 1
	mat.set_shader_parameter("toon_steps", 4)
	mat.set_shader_parameter("band_floor", 0.19)
	mat.set_shader_parameter("local_light_softness", 1.0)
	return mat


static func sun_direction(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(clampf(elevation_deg, 5.0, 85.0))
	var cos_el := cos(el)
	return Vector3(cos_el * cos(az), sin(el), cos_el * sin(az))


static func make_sun(
	azimuth_deg: float,
	elevation_deg: float,
	color: Color,
	intensity: float,
	cast_shadows := true,
) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "Moon"
	light.light_color = color
	light.light_energy = maxf(0.05, intensity)
	light.light_specular = 0.0
	light.light_angular_distance = 0.1
	light.shadow_enabled = cast_shadows
	tune_moon_shadows(light, 520.0)
	var dir := sun_direction(azimuth_deg, elevation_deg)
	# Detached nodes cannot look_at() in 4.x; -Z is the light direction.
	light.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), dir * 80.0)
	return light


static func make_omni(
	id: String,
	world: Vector3,
	color: Color,
	range_tiles: float,
	strength: float,
	cast_shadows: bool,
	tile_size: float,
	lamp_power := 1.0,
	night := 0.5,
	strength0 := 0.62,
	falloff := 0.42,
) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = id
	light.position = world
	light.light_color = color
	light.omni_range = maxf(tile_size, range_tiles * tile_size)
	light.light_energy = omni_energy(strength0, falloff, lamp_power, night) * (0.7 + clampf(strength, 0.0, 1.2) * 0.4)
	light.light_specular = 0.0
	light.omni_attenuation = 1.05
	light.shadow_enabled = cast_shadows
	if cast_shadows:
		tune_omni_shadows(light)
	return light


static func omni_casts_world_shadow(model_id: String) -> bool:
	return model_id.find("lantern") >= 0


static func tune_moon_shadows(
	light: DirectionalLight3D,
	max_distance: float,
	splits := 4,
	bias := 0.14,
	normal_bias := 2.4,
	blur := 1.35,
) -> void:
	light.shadow_bias = bias
	light.shadow_normal_bias = normal_bias
	light.shadow_blur = blur
	light.light_angular_distance = 1.6
	if splits <= 2:
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		light.directional_shadow_split_1 = 0.1
	else:
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		light.directional_shadow_split_1 = 0.07
		light.directional_shadow_split_2 = 0.2
		light.directional_shadow_split_3 = 0.45
	light.directional_shadow_blend_splits = splits > 2
	light.directional_shadow_max_distance = maxf(80.0, max_distance)
	light.directional_shadow_fade_start = 0.82
	light.directional_shadow_pancake_size = 36.0


static func apply_shadow_atlas(dir_size: int, _lamp_size: int, dir_filter: int, lamp_filter: int) -> void:
	var ds := clampi(dir_size, 1024, 8192)
	if RenderingServer.has_method("directional_shadow_atlas_set_size"):
		RenderingServer.directional_shadow_atlas_set_size(ds, false)
	if RenderingServer.has_method("directional_soft_shadow_filter_set_quality"):
		RenderingServer.directional_soft_shadow_filter_set_quality(dir_filter)
	if RenderingServer.has_method("positional_soft_shadow_filter_set_quality"):
		RenderingServer.positional_soft_shadow_filter_set_quality(lamp_filter)


static func tune_omni_shadows(
	light: OmniLight3D,
	bias := 0.18,
	normal_bias := 1.8,
	blur := 0.25,
) -> void:
	light.shadow_bias = bias
	light.shadow_normal_bias = normal_bias
	light.shadow_blur = blur
	light.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
	light.shadow_caster_mask = SHADOW_LAYER_WORLD


static func hex_color(hex: String, fallback: Color = Color(1, 0.69, 0.34)) -> Color:
	var h := hex.strip_edges().trim_prefix("#")
	if h.length() == 3:
		h = "%s%s%s%s%s%s" % [h[0], h[0], h[1], h[1], h[2], h[2]]
	if h.length() < 6:
		return fallback
	return Color(
		h.substr(0, 2).hex_to_int() / 255.0,
		h.substr(2, 2).hex_to_int() / 255.0,
		h.substr(4, 2).hex_to_int() / 255.0,
	)


static func brightest_palette(pal: Array, fallback: Color) -> Color:
	var best := fallback
	var best_luma := fallback.r * 0.3 + fallback.g * 0.59 + fallback.b * 0.11
	for item in pal:
		var hex := str(item)
		if not hex.begins_with("#") or hex.length() < 7:
			continue
		var c := hex_color(hex, fallback)
		var luma := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
		if luma > best_luma:
			best_luma = luma
			best = c
	return best
