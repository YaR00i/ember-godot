class_name EmberLights
extends RefCounted
## OmniLight3D / DirectionalLight3D from Ember authored fields.
## Energy is a Godot-scale mapping, not Three MeshToon intensity.


static func sun_direction(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(clampf(elevation_deg, 5.0, 85.0))
	var cos_el := cos(el)
	return Vector3(cos_el * cos(az), sin(el), cos_el * sin(az))


static func make_sun(azimuth_deg: float, elevation_deg: float, color: Color, intensity: float) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.light_color = color
	light.light_energy = maxf(0.15, intensity)
	light.shadow_enabled = true
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	var dir := sun_direction(azimuth_deg, elevation_deg)
	light.position = dir * 80.0
	light.look_at(Vector3.ZERO)
	return light


static func make_omni(
	id: String,
	world: Vector3,
	color: Color,
	range_tiles: float,
	strength: float,
	cast_shadows: bool,
	tile_size: float,
) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = id
	light.position = world
	light.light_color = color
	light.omni_range = maxf(tile_size, range_tiles * tile_size)
	light.light_energy = 1.6 + strength * 4.5
	light.omni_attenuation = 1.4
	light.shadow_enabled = cast_shadows
	if cast_shadows:
		light.shadow_bias = 0.04
		light.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
	return light


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
