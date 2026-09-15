extends Node3D
## Interactive Forward+ tuning stand for the existing water ShaderMaterial.
## It edits an in-memory duplicate and exports values to user:// only.

const WATER_PATH := "res://materials/ember_voxel_surface_water.tres"
const FOAM_PATH := "res://materials/ember_voxel_surface_foam.tres"
const CONTACT_PATH := "res://materials/ember_water_contact.tres"
const EXPORT_PATH := "user://water-lab-selection.json"
const WaterContact := preload("res://scripts/ember_water_contact_3d.gd")
const LabProjection := preload("res://tools/water_lab_projection.gd")
const FIELD_SIZE := Vector2(22.0, 15.0)
const FIELD_CENTER_X := 4.25
const CAMERA_FOCUS := Vector3(2.35, 0.15, 0.0)
const DEFAULT_CAMERA_DISTANCE := 23.5
const HIDDEN_EXPORT_KEYS := [
	# Preset internals removed from the main UI still travel with a copied setup.
	# Otherwise applying the JSON to the canonical material could silently lose
	# the selected Review2 highlight mode or bottom-light blend.
	"pixel_highlight_mix",
	"pixel_highlight_core",
	"pixel_highlight_strength",
	"reflection_pixel_strength",
	"sun_glitter_threshold",
	"pixel_highlight_smooth_motion",
	"pixel_highlight_travel_speed",
	"pixel_highlight_edge_wobble",
	"pixel_highlight_wobble_speed",
	"surface_crest_width",
	"stylized_shadow_pixel_size",
]

const GROUPS := {
	"Волны": [
		{"key":"wave_natural_mix", "name":"Натуральное разнообразие", "min":0.0, "max":1.0, "step":0.01},
		{"key":"wave_direction_degrees", "name":"Направление", "min":-180.0, "max":180.0, "step":1.0},
		{"key":"wave_length", "name":"Размер основной волны", "min":0.5, "max":4.0, "step":0.01},
		{"key":"wave_strength", "name":"Высота и наклон", "min":0.02, "max":0.25, "step":0.005},
		{"key":"wave_speed", "name":"Общая скорость", "min":0.0, "max":1.2, "step":0.01},
		{"key":"wave_scale_variation", "name":"Разнообразие размеров", "min":0.0, "max":1.0, "step":0.01},
		{"key":"wave_grouping", "name":"Группы и спокойные промежутки", "min":0.0, "max":1.0, "step":0.01},
		{"key":"wave_direction_spread", "name":"Разброс направлений", "min":0.0, "max":60.0, "step":1.0},
		{"key":"wind_ripple_strength", "name":"Мелкая ветровая рябь", "min":0.0, "max":1.0, "step":0.01},
		{"key":"wave_crest_sharpness", "name":"Острота гребней", "min":0.0, "max":1.0, "step":0.01},
	],
	"Блики": [
		{"key":"highlight_strength", "name":"Общая сила бликов", "min":0.0, "max":0.6, "step":0.01},
		{"key":"surface_roughness", "name":"Размер мягкого блика", "min":0.12, "max":0.65, "step":0.01},
		{"key":"sun_glitter_strength", "name":"Яркие солнечные вспышки", "min":0.0, "max":2.0, "step":0.01},
		{"key":"pixel_highlight_threshold", "name":"Размер резких бликов", "min":0.94, "max":0.998, "step":0.001},
		{"key":"pixel_highlight_color", "name":"Цвет бликов", "type":"color"},
		{"key":"pixel_highlight_view_dependence", "name":"Зависимость от камеры · 0 = стабильно", "min":0.0, "max":1.0, "step":0.01},
	],
	"Цвет": [
		{"key":"layered_water_mix", "name":"Объёмные волны референса", "min":0.0, "max":1.0, "step":0.01},
		{"key":"water_tint", "name":"Бирюзовый цвет", "type":"color"},
		{"key":"water_light_tone", "name":"Цвет мелководья", "type":"color"},
		{"key":"water_deep_tone", "name":"Цвет глубины", "type":"color"},
		{"key":"wave_shadow_tone", "name":"Тёмная сторона волны", "type":"color"},
		{"key":"wave_crest_tone", "name":"Светлая сторона волны", "type":"color"},
		{"key":"wave_band_strength", "name":"Контраст объёма волн", "min":0.0, "max":1.0, "step":0.01},
		{"key":"tint_strength", "name":"Сила бирюзы", "min":0.0, "max":0.5, "step":0.01},
		{"key":"tone_strength", "name":"Перелив цвета", "min":0.0, "max":1.0, "step":0.01},
		{"key":"scene_depth_mix", "name":"Глубина по настоящему дну", "min":0.0, "max":1.0, "step":0.01},
		{"key":"underwater_depth_range", "name":"Глубина до плотной воды", "min":0.25, "max":4.0, "step":0.05},
		{"key":"shallow_opacity", "name":"Плотность мелководья", "min":0.2, "max":1.0, "step":0.01},
		{"key":"deep_opacity", "name":"Плотность глубины", "min":0.2, "max":1.0, "step":0.01},
	],
	"Свет и тень": [
		{"key":"flow_network_strength", "name":"Белая сетка волн", "min":0.0, "max":1.0, "step":0.01},
		{"key":"flow_network_warp", "name":"Изгиб сетки", "min":0.0, "max":0.5, "step":0.01},
		{"key":"surface_crest_strength", "name":"Светлая кромка волны", "min":0.0, "max":1.0, "step":0.01},
		{"key":"stylized_shadow_mix", "name":"Пиксельная тень", "min":0.0, "max":1.0, "step":0.01},
		{"key":"stylized_shadow_threshold", "name":"Граница тени", "min":0.0, "max":1.0, "step":0.01},
		{"key":"underwater_light_mix", "name":"Видимость света на дне", "min":0.0, "max":0.6, "step":0.01},
		{"key":"underwater_caustic_strength", "name":"Яркость света на дне", "min":0.0, "max":1.0, "step":0.01},
		{"key":"underwater_caustic_width", "name":"Ширина световых лент", "min":0.0, "max":1.0, "step":0.01},
		{"key":"underwater_caustic_color", "name":"Цвет света на дне", "type":"color"},
		{"key":"reflection_strength", "name":"Цвет отражения неба", "min":0.0, "max":0.4, "step":0.01},
	],
	"Берег": [
		{"key":"shore_effect_strength", "name":"Сила береговых волн", "min":0.0, "max":1.0, "step":0.01},
		{"key":"shore_wave_transform", "name":"Переход к мелководью", "min":0.0, "max":1.0, "step":0.01},
		{"key":"shore_shoaling_distance", "name":"Дальность перестройки волн", "min":1.0, "max":8.0, "step":0.05},
		{"key":"shore_deep_depth", "name":"Глубина начала перестройки", "min":0.1, "max":1.0, "step":0.01},
		{"key":"shore_shallow_depth", "name":"Глубина разрушения", "min":0.0, "max":0.8, "step":0.01},
		{"key":"shore_refraction_strength", "name":"Поворот гребней к берегу", "min":0.0, "max":1.0, "step":0.01},
		{"key":"shore_wavelength_compression", "name":"Сжатие волн на мелководье", "min":0.0, "max":0.68, "step":0.01},
		{"key":"shore_shoaling_strength", "name":"Рост и крутизна волны", "min":0.0, "max":1.0, "step":0.01},
		{"key":"shore_crest_coherence", "name":"Связность берегового гребня", "min":0.0, "max":1.0, "step":0.01},
		{"key":"shore_break_threshold", "name":"Порог разрушения гребня", "min":0.25, "max":1.2, "step":0.01},
		{"key":"shore_break_softness", "name":"Мягкость зоны разрушения", "min":0.02, "max":0.30, "step":0.01},
		{"key":"shore_break_distance", "name":"Максимальная зона разрушения", "min":0.25, "max":4.0, "step":0.05},
		{"key":"shore_foam_width", "name":"Ширина связной пены", "min":0.03, "max":0.4, "step":0.01},
		{"key":"shore_runup_distance", "name":"Дальность наката на берег", "min":0.0, "max":2.0, "step":0.05},
		{"key":"shore_runup_speed", "name":"Скорость наката", "min":0.1, "max":2.0, "step":0.01},
		{"key":"shore_wet_trace", "name":"Мокрый след", "min":0.0, "max":1.0, "step":0.01},
		{"key":"shore_reflection_strength", "name":"Сила обратной волны", "min":0.0, "max":1.0, "step":0.01},
		{"key":"shore_reflection_distance", "name":"Дальность обратной волны", "min":0.25, "max":4.0, "step":0.05},
		{"key":"underwater_caustic_wave_link", "name":"Связь света на дне с волной", "min":0.0, "max":1.0, "step":0.01},
		{"key":"visual_wave_height", "name":"Настоящая высота · A/B", "min":0.0, "max":0.08, "step":0.005},
		{"key":"visual_wave_shore_fade", "name":"Затухание высоты у берега", "min":0.05, "max":1.5, "step":0.05},
	],
}

const REFERENCE_PRESET := {
	"wave_natural_mix":1.0,
	"layered_water_mix":1.0,
	"wave_shadow_tone":Color("064a67"),
	"wave_crest_tone":Color("43c5c5"),
	"wave_band_strength":0.70,
	"surface_crest_strength":0.22,
	"surface_crest_width":0.11,
	"sun_glitter_strength":0.52,
	"sun_glitter_threshold":0.9985,
	"pixel_highlight_mix":0.0,
	"pixel_highlight_color":Color("e8ffff"),
	"reflection_pixel_strength":0.0,
	"wave_length":2.3,
	"wave_strength":0.09,
	"wave_speed":0.42,
	"surface_roughness":0.38,
	"highlight_strength":0.11,
	"water_tint":Color("079caa"),
	"water_light_tone":Color("36bcc3"),
	"water_deep_tone":Color("064f75"),
	"tint_strength":0.38,
	"tone_strength":0.24,
	"shallow_opacity":0.48,
	"deep_opacity":0.68,
	"flow_network_strength":0.0,
	"reflection_strength":0.10,
	"stylized_shadow_mix":1.0,
	"stylized_shadow_pixel_size":0.1875,
	"underwater_light_mix":0.14,
	"underwater_caustic_strength":0.45,
	"underwater_caustic_color":Color("91dc62"),
}

const SYNCED_PRESET := {
	# User-selected Review2 balance with the volume pass mixed in. The shader
	# now derives both layers from the same wave state instead of crossing two
	# unrelated diagonal fields.
	"layered_water_mix":0.4,
	"wave_natural_mix":0.49,
	"wave_direction_degrees":180.0,
	"wave_direction_spread":34.0,
	"wave_scale_variation":1.0,
	"wave_grouping":0.58,
	"wind_ripple_strength":0.18,
	"wave_crest_sharpness":0.25,
	"wave_shadow_tone":Color("064a67"),
	"wave_crest_tone":Color("43c5c5"),
	"wave_band_strength":0.70,
	"surface_crest_strength":0.22,
	"surface_crest_width":0.105,
	"sun_glitter_strength":0.50,
	"sun_glitter_threshold":0.9995,
	"pixel_highlight_mix":1.0,
	"pixel_highlight_threshold":0.968,
	"pixel_highlight_core":0.996,
	"pixel_highlight_strength":0.72,
	"pixel_highlight_color":Color("d8ffff"),
	"pixel_highlight_view_dependence":1.0,
	"pixel_highlight_smooth_motion":0.0,
	"pixel_highlight_travel_speed":1.0,
	"pixel_highlight_edge_wobble":0.0,
	"pixel_highlight_wobble_speed":1.0,
	"reflection_pixel_strength":0.0,
	"wave_length":3.71,
	"wave_strength":0.225,
	"wave_speed":0.48,
	"surface_roughness":0.35,
	"highlight_strength":0.11,
	"water_tint":Color("079caa"),
	"water_light_tone":Color("36bcc3"),
	"water_deep_tone":Color("064f75"),
	"tint_strength":0.38,
	"tone_strength":0.24,
	"shallow_opacity":0.48,
	"deep_opacity":0.68,
	"flow_network_strength":0.16,
	"flow_network_warp":0.21,
	"reflection_strength":0.10,
	"stylized_shadow_mix":1.0,
	"stylized_shadow_threshold":0.53,
	"stylized_shadow_pixel_size":0.0625,
	"underwater_light_mix":0.16,
	"underwater_caustic_strength":0.75,
	"underwater_caustic_color":Color("91dc62"),
}

const SHORE_LAB_PRESET := {
	"scene_depth_mix":1.0,
	"underwater_depth_range":1.75,
	"shallow_opacity":0.48,
	"deep_opacity":0.68,
	"shore_effect_strength":0.68,
	"shore_wave_transform":1.0,
	"shore_shoaling_distance":4.5,
	"shore_shallow_depth":0.10,
	"shore_deep_depth":0.72,
	"shore_refraction_strength":0.86,
	"shore_wavelength_compression":0.42,
	"shore_shoaling_strength":0.48,
	"shore_crest_coherence":0.76,
	"shore_break_threshold":0.78,
	"shore_break_softness":0.07,
	"shore_boundary_x":-4.75,
	"shore_split_z":0.0,
	"shore_zone_gap":1.35,
	"shore_zone_outer":6.65,
	"shore_break_distance":3.20,
	"shore_foam_width":0.08,
	"shore_runup_distance":1.05,
	"shore_runup_speed":0.38,
	"shore_wet_trace":0.42,
	"shore_reflection_strength":0.76,
	"shore_reflection_distance":2.35,
	"underwater_light_mix":0.58,
	"underwater_caustic_strength":0.88,
	"underwater_caustic_width":0.35,
	"underwater_caustic_color":Color("b9e978"),
	"underwater_caustic_wave_link":1.0,
	"visual_wave_height":0.04,
	"visual_wave_shore_fade":0.55,
}

const PHYSICAL_PRESET := {
	# Physical baseline: the moving wave normal, fixed world sun and camera form
	# the GGX highlight. No crest mask and no quantized normal coordinates.
	"pixel_highlight_mix":0.0,
	"layered_water_mix":0.0,
	"wave_natural_mix":1.0,
	"pixel_highlight_cohesion":0.0,
	"pixel_highlight_smooth_motion":1.0,
	"pixel_highlight_travel_speed":1.0,
	"pixel_highlight_edge_wobble":0.0,
	"wave_length":3.6,
	"wave_strength":0.08,
	"wave_speed":0.24,
	"surface_roughness":0.22,
	"highlight_strength":0.24,
	"reflection_pixel_strength":0.0,
	"flow_network_strength":0.0,
	"flow_network_warp":0.10,
	"reflection_strength":0.08,
	"stylized_shadow_mix":1.0,
	"stylized_shadow_pixel_size":0.1875,
	"underwater_light_mix":0.16,
	"underwater_caustic_strength":0.72,
}

const STANDING_PRESET := {
	"layered_water_mix":0.0,
	"wave_natural_mix":0.0,
	"pixel_highlight_mix":1.0,
	"pixel_highlight_threshold":0.991,
	"pixel_highlight_core":0.998,
	"pixel_highlight_strength":1.10,
	"pixel_highlight_color":Color("d8ffff"),
	"pixel_highlight_view_dependence":0.15,
	"pixel_highlight_smooth_motion":1.0,
	"pixel_highlight_travel_speed":0.02,
	"pixel_highlight_edge_wobble":0.08,
	"pixel_highlight_wobble_speed":1.15,
	"wave_length":1.6,
	"wave_strength":0.10,
	"wave_speed":0.35,
	"flow_network_strength":0.22,
	"flow_network_warp":0.16,
	"stylized_shadow_mix":1.0,
	"stylized_shadow_pixel_size":0.1875,
	"underwater_light_mix":0.16,
	"underwater_caustic_strength":0.75,
}

const REVIEW2_PRESET := {
	"layered_water_mix":0.0,
	"wave_natural_mix":0.0,
	"pixel_highlight_mix":1.0,
	"pixel_highlight_threshold":0.968,
	"pixel_highlight_core":0.996,
	"pixel_highlight_strength":0.72,
	"pixel_highlight_color":Color("d8ffff"),
	"pixel_highlight_view_dependence":1.0,
	"pixel_highlight_smooth_motion":0.0,
	"pixel_highlight_travel_speed":1.0,
	"pixel_highlight_edge_wobble":0.0,
	"pixel_highlight_wobble_speed":1.0,
	"wave_length":1.6,
	"wave_strength":0.10,
	"wave_speed":0.35,
	"flow_network_strength":0.34,
	"flow_network_warp":0.18,
}

const SEA_WAVES := {
	"wave_natural_mix":1.0,
	"wave_direction_degrees":36.87,
	"wave_length":1.70,
	"wave_strength":0.10,
	"wave_speed":0.35,
	"wave_scale_variation":0.55,
	"wave_grouping":0.58,
	"wave_direction_spread":18.0,
	"wind_ripple_strength":0.18,
	"wave_crest_sharpness":0.25,
}

const LAKE_WAVES := {
	"wave_natural_mix":1.0,
	"wave_length":1.25,
	"wave_strength":0.065,
	"wave_speed":0.48,
	"wave_scale_variation":0.72,
	"wave_grouping":0.36,
	"wave_direction_spread":38.0,
	"wind_ripple_strength":0.58,
	"wave_crest_sharpness":0.32,
}

const COAST_WAVES := {
	"wave_natural_mix":1.0,
	"wave_length":2.05,
	"wave_strength":0.12,
	"wave_speed":0.31,
	"wave_scale_variation":0.38,
	"wave_grouping":0.74,
	"wave_direction_spread":9.0,
	"wind_ripple_strength":0.22,
	"wave_crest_sharpness":0.76,
}

const SHORE_READABLE_WAVES := {
	# QA candidate: preserve the user's saved colour/highlight/depth treatment,
	# but give the shore one dominant, gently varied incoming system.
	"wave_natural_mix":1.0,
	"wave_direction_degrees":180.0,
	"wave_length":3.20,
	"wave_speed":0.42,
	"wave_scale_variation":0.40,
	"wave_grouping":0.62,
	"wave_direction_spread":9.0,
	"wind_ripple_strength":0.18,
	"wave_crest_sharpness":0.65,
}

const RIVER_WAVES := {
	"wave_natural_mix":1.0,
	"wave_length":1.10,
	"wave_strength":0.055,
	"wave_speed":0.66,
	"wave_scale_variation":0.54,
	"wave_grouping":0.20,
	"wave_direction_spread":12.0,
	"wind_ripple_strength":0.38,
	"wave_crest_sharpness":0.40,
}

var water: ShaderMaterial
var beach_foam: ShaderMaterial
var wall_foam: ShaderMaterial
var rock_contact_material: ShaderMaterial
var pier_contact_materials: Array[ShaderMaterial] = []
var ship_contact_materials: Array[ShaderMaterial] = []
var pier_water_contact: Node3D
var rock_water_contact: Node3D
var ship_water_contact: Node3D
var ship_probe: Node3D
var ship_phase := 0.0
var original_values := {}
var controls := {}
var status_label: Label
var camera: Camera3D
var sun: DirectionalLight3D
var orbit := Vector2(-0.72, 0.62)
var distance := DEFAULT_CAMERA_DISTANCE
var camera_focus := CAMERA_FOCUS
var updating := false
var paused := false
var paused_time := 3.25
var capture_path := ""
var capture_motion_dir := ""
var capture_quarter_turn := false
var capture_low_angle := false
var capture_start_time := 3.25
var capture_frame_step := 1.0 / 12.0
var capture_preset := ""
var capture_volume_override := -1.0
var capture_bottom_light_override := -1.0
var capture_shore_transform_override := -1.0
var capture_float_overrides := {}
var capture_focus_pier := false


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--motion-dir="):
			capture_motion_dir = argument.trim_prefix("--motion-dir=")
		elif argument == "--camera-quarter":
			capture_quarter_turn = true
		elif argument == "--camera-low":
			capture_low_angle = true
		elif argument == "--focus-pier":
			capture_focus_pier = true
		elif argument == "--flat-water":
			capture_volume_override = 0.0
		elif argument == "--volume-water":
			capture_volume_override = 0.04
		elif argument == "--bottom-light-off":
			capture_bottom_light_override = 0.0
		elif argument == "--shore-transform-off":
			capture_shore_transform_override = 0.0
		elif argument.begins_with("--capture-time="):
			capture_start_time = float(argument.trim_prefix("--capture-time="))
		elif argument.begins_with("--motion-step="):
			capture_frame_step = maxf(float(argument.trim_prefix("--motion-step=")), 0.001)
		elif argument.begins_with("--preset="):
			capture_preset = argument.trim_prefix("--preset=").to_lower()
		elif argument.begins_with("--shader-float="):
			var assignment := argument.trim_prefix("--shader-float=").split("=", true, 1)
			if assignment.size() == 2:
				capture_float_overrides[assignment[0]] = float(assignment[1])
			else:
				push_warning("Water Lab shader override must be key=value: " + argument)
	_build_world()
	_capture_original_values()
	_build_ui()
	_apply_values(SYNCED_PRESET)
	_apply_values(SHORE_LAB_PRESET, "Старт: сохранённая вода, пологий берег и отражающая стенка")
	_load_saved_selection(false)
	_apply_capture_preset()
	if capture_volume_override >= 0.0:
		water.set_shader_parameter("visual_wave_height", capture_volume_override)
	if capture_bottom_light_override >= 0.0:
		water.set_shader_parameter("underwater_light_mix", capture_bottom_light_override)
	if capture_shore_transform_override >= 0.0:
		water.set_shader_parameter("shore_wave_transform", capture_shore_transform_override)
	for key in capture_float_overrides:
		water.set_shader_parameter(key, capture_float_overrides[key])
	_sync_shore_materials()
	if capture_quarter_turn:
		orbit.x += PI * 0.5
	if capture_low_angle:
		orbit.y = 0.28
		distance = 20.0
	if capture_focus_pier:
		camera_focus = Vector3(-1.65, 0.05, 0.0)
		orbit = Vector2(-0.72, 0.43)
		distance = 11.5
	_update_camera()
	if not capture_path.is_empty() or not capture_motion_dir.is_empty():
		water.set_shader_parameter("preview_time", capture_start_time)
		_sync_shore_materials()
		_capture_after_ready.call_deferred()


func _process(delta: float) -> void:
	if ship_probe == null or paused:
		return
	ship_phase += maxf(delta, 0.0)
	ship_probe.position.x = 6.8 + sin(ship_phase * 0.55) * 1.45
	ship_probe.position.z = -3.15 + sin(ship_phase * 0.31) * 0.22


func _plain_material(color: Color, roughness := 0.9) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _box(name_text: String, position_value: Vector3, size_value: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name_text
	node.position = position_value
	var mesh := BoxMesh.new()
	mesh.size = size_value
	node.mesh = mesh
	node.material_override = _plain_material(color)
	add_child(node)
	return node


func _box_collision(
	root: Node3D,
	name_text: String,
	position_value: Vector3,
	size_value: Vector3,
) -> CollisionShape3D:
	var body := StaticBody3D.new()
	body.name = name_text + "Body"
	body.position = position_value
	root.add_child(body)
	var collision := CollisionShape3D.new()
	collision.name = name_text + "Shape"
	var shape := BoxShape3D.new()
	shape.size = size_value
	collision.shape = shape
	body.add_child(collision)
	return collision


func _overlay_plane(
	name_text: String,
	position_value: Vector3,
	size_value: Vector2,
	material: Material,
) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name_text
	node.position = position_value
	var plane := PlaneMesh.new()
	plane.size = size_value
	node.mesh = plane
	node.material_override = material
	add_child(node)
	return node


func _water_surface_mesh() -> ArrayMesh:
	# The lab uses the same metadata contract planned for authored Surface water:
	# UV.y carries signed distance (negative means a hard wall), while UV2 points
	# from the boundary into the water. Per-cell quads keep the hard/soft boundary
	# switch exact and give the optional height pass enough vertices to bend.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	var boundary_x := -4.75
	var maximum_x := FIELD_CENTER_X + FIELD_SIZE.x * 0.5
	var minimum_z := -FIELD_SIZE.y * 0.5
	var maximum_z := FIELD_SIZE.y * 0.5
	var step_size := 0.25
	var width := ceili((maximum_x - boundary_x) / step_size)
	var depth := ceili((maximum_z - minimum_z) / step_size)
	for z_index in depth:
		var z0 := minimum_z + float(z_index) * step_size
		var z1 := minf(z0 + step_size, maximum_z)
		var is_wall := (z0 + z1) * 0.5 < 1.175
		for x_index in width:
			var x0 := boundary_x + float(x_index) * step_size
			var x1 := minf(x0 + step_size, maximum_x)
			var first := vertices.size()
			for vertex in [
				Vector3(x0, 0.0, z1), Vector3(x0, 0.0, z0),
				Vector3(x1, 0.0, z0), Vector3(x1, 0.0, z1),
			]:
				vertices.append(vertex)
				normals.append(Vector3.UP)
				colors.append(Color.WHITE)
				var encoded_distance := maxf(vertex.x - boundary_x, 0.0) + 0.0001
				if is_wall:
					encoded_distance = -encoded_distance
				uvs.append(Vector2(_lab_depth_factor(vertex.x, vertex.z), encoded_distance))
				uv2s.append(Vector2.RIGHT)
			indices.append_array(PackedInt32Array([
				first, first + 1, first + 2,
				first, first + 2, first + 3,
			]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_name(0, "water")
	return mesh


func _lab_depth_factor(x: float, z: float) -> float:
	# These bands match the actual stepped seabed built below. The small sand
	# patch is also a real local shoal, so waves can react before the main beach.
	if x >= -2.65 and x <= -0.45 and z >= 2.30 and z <= 4.70:
		return 0.11
	if x < -3.75:
		return 0.12
	if x < -2.75:
		return 0.19
	if x < -1.75:
		return 0.26
	if x < -0.75:
		return 0.34
	if x < 5.95:
		return 0.41
	return 0.77


func _append_lab_shore_quad(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	uvs: PackedVector2Array,
	uv2s: PackedVector2Array,
	indices: PackedInt32Array,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	boundary: Vector2,
	inward: Vector2,
	is_wall: bool,
) -> void:
	var first := vertices.size()
	for vertex in [a, b, c, d]:
		vertices.append(vertex)
		normals.append(Vector3.UP)
		colors.append(Color(0.88, 1.0, _lab_depth_factor(vertex.x, vertex.z), 0.95))
		uvs.append(Vector2(
			(Vector2(vertex.x, vertex.z) - boundary).dot(inward),
			1.0 if is_wall else 0.0,
		))
		uv2s.append(inward)
	indices.append_array(PackedInt32Array([
		first, first + 1, first + 2,
		first, first + 2, first + 3,
	]))


func _systemic_shore_mesh(beach_tops: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	var boundary_x := -4.75
	var water_x := boundary_x + 4.0
	var inward := Vector2.RIGHT
	# The bridge approach belongs to the hard-bank section, so the same derived
	# response continues under the deck instead of stopping at a hand-made gap.
	for section in [
		[-FIELD_SIZE.y * 0.5, 1.175, true],
		[1.175, FIELD_SIZE.y * 0.5, false],
	]:
		var z0: float = section[0]
		var z1: float = section[1]
		_append_lab_shore_quad(
			vertices, normals, colors, uvs, uv2s, indices,
			Vector3(boundary_x, 0.012, z1), Vector3(boundary_x, 0.012, z0),
			Vector3(water_x, 0.012, z0), Vector3(water_x, 0.012, z1),
			Vector2(boundary_x, (z0 + z1) * 0.5), inward, bool(section[2]),
		)
	for index in beach_tops.size():
		var top: float = beach_tops[index]
		var x_center := -4.95 - float(index) * 0.48
		var x0 := x_center - 0.26
		var x1 := x_center + 0.26
		_append_lab_shore_quad(
			vertices, normals, colors, uvs, uv2s, indices,
			Vector3(x0, top + 0.012, 6.65), Vector3(x0, top + 0.012, 1.35),
			Vector3(x1, top + 0.012, 1.35), Vector3(x1, top + 0.012, 6.65),
			Vector2(boundary_x, 4.0), inward, false,
		)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_name(0, "water_foam")
	return mesh


func _build_world() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a9c8c5")
	environment.ambient_light_energy = 0.24
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("6fa4bd")
	sky_material.sky_horizon_color = Color("d7e0d8")
	sky_material.ground_horizon_color = Color("8fb6a7")
	sky_material.ground_bottom_color = Color("31534b")
	sky.sky_material = sky_material
	environment.sky = sky
	world.environment = environment
	add_child(world)

	sun = DirectionalLight3D.new()
	sun.name = "WaterLabSun"
	# Keep a fixed world-space sun. Its horizontal direction opposes the default
	# camera, so calm wave slopes can physically reflect it into that view.
	var to_sun := Vector3(0.44, 0.75, -0.50).normalized()
	sun.basis = Basis.looking_at(-to_sun, Vector3.UP)
	sun.light_color = Color(1.0, 0.94, 0.80)
	sun.light_energy = 0.90
	sun.light_specular = 1.0
	sun.shadow_enabled = true
	sun.light_angular_distance = 0.0
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)

	# The colour ramp now follows real voxel-height steps. Looking through the
	# water reveals an actual shallow shelf, mid basin and lowered deep floor.
	_box("BottomBase", Vector3(FIELD_CENTER_X, -1.60, 0), Vector3(FIELD_SIZE.x, 0.30, FIELD_SIZE.y), Color("3d6863"))
	# One floor material across all three heights makes depth readable through
	# water transparency instead of through three pre-painted colour stripes.
	var floor_color := Color("9baa83")
	# A voxel shoal descends toward the basin. Besides reading as real bottom
	# geometry through transparent water, these exact steps drive refraction,
	# shoaling and the H/depth breaking condition in the shader.
	var shoal_tops := [-0.18, -0.29, -0.40, -0.51]
	for index in shoal_tops.size():
		var shoal_top: float = shoal_tops[index]
		var shoal_height := shoal_top + 1.45
		_box(
			"ShoreBottomStep%02d" % index,
			Vector3(-4.25 + float(index), -1.45 + shoal_height * 0.5, 0),
			Vector3(1.0, shoal_height, FIELD_SIZE.y),
			floor_color,
		)
	_box("MidBottom", Vector3(2.60, -1.035, 0), Vector3(6.70, 0.83, FIELD_SIZE.y), floor_color)
	_box("DeepBottom", Vector3(10.60, -1.30, 0), Vector3(9.30, 0.30, FIELD_SIZE.y), floor_color)
	_box("ShallowPatch", Vector3(-1.55, -0.25, 3.5), Vector3(2.2, 0.16, 2.4), Color("e0d69b"))
	# One shared incoming wave reaches two voxel boundaries. The upper half is a
	# soft stepped beach; the lower half is a hard vertical wall.
	var beach_color := Color("c9cf78")
	var beach_tops := [-0.04, 0.07, 0.18, 0.29, 0.40]
	for index in beach_tops.size():
		var top: float = beach_tops[index]
		var x_center := -4.95 - float(index) * 0.48
		var height := top + 0.55
		_box(
			"BeachStep%02d" % index,
			Vector3(x_center, -0.55 + height * 0.5, 4.0),
			Vector3(0.52, height, 5.3),
			beach_color.lightened(float(index) * 0.025),
		)
	_box("BeachBack", Vector3(-7.15, 0.18, 4.0), Vector3(1.15, 0.66, 5.3), Color("b6ca70"))
	_box("HarbourWall", Vector3(-5.06, 0.43, -4.0), Vector3(0.62, 1.42, 5.3), Color("708077"))
	_box("HarbourWallTop", Vector3(-5.06, 1.17, -4.0), Vector3(0.78, 0.12, 5.4), Color("9da58c"))
	_box("WallBack", Vector3(-6.45, 0.18, -4.0), Vector3(2.2, 0.66, 5.3), Color("607466"))
	_box("PierApproach", Vector3(-6.45, 0.18, 0.0), Vector3(2.2, 0.66, 2.35), Color("82966d"))

	water = (load(WATER_PATH) as ShaderMaterial).duplicate() as ShaderMaterial
	water.resource_path = ""
	water.set_shader_parameter("coordinate_scale", 1.0)
	water.set_shader_parameter("preview_time", -1.0)
	water.set_shader_parameter("decorative_glints", false)
	water.set_shader_parameter("shore_geometry_driven", true)
	var lab_projection := LabProjection.new()
	lab_projection.name = "LabWaterProjection"
	lab_projection.configure(Vector2(FIELD_CENTER_X, 0.0), FIELD_SIZE, -4.75, 0.0, 1.0)
	add_child(lab_projection)
	var surface := MeshInstance3D.new()
	surface.name = "EditableWater"
	surface.mesh = _water_surface_mesh()
	surface.material_override = water
	add_child(surface)

	beach_foam = (load(FOAM_PATH) as ShaderMaterial).duplicate() as ShaderMaterial
	beach_foam.resource_path = ""
	beach_foam.set_shader_parameter("shore_lab_mode", 0)
	beach_foam.set_shader_parameter("foam_color", Color("e9fff7"))
	beach_foam.set_shader_parameter("foam_shadow", Color("72cfc5"))
	beach_foam.set_shader_parameter("wet_color", Color("2d8e87"))
	beach_foam.set_shader_parameter("alpha_scale", 0.86)
	wall_foam = beach_foam
	var systemic_shore := MeshInstance3D.new()
	systemic_shore.name = "SystemicShoreResponse"
	systemic_shore.mesh = _systemic_shore_mesh(beach_tops)
	systemic_shore.material_override = beach_foam
	add_child(systemic_shore)
	_sync_shore_materials()

	var pier_collisions := Node3D.new()
	pier_collisions.name = "PierCollisionModel"
	add_child(pier_collisions)
	for index in 10:
		var board_position := Vector3(-5.6 + index * 0.45, 0.62, 0.0)
		var board_size := Vector3(0.40, 0.18, 2.25)
		_box("PierBoard%02d" % index, board_position, board_size, Color("b18e52"))
		_box_collision(pier_collisions, "PierBoard%02d" % index, board_position, board_size)
	var pier_post_index := 0
	for x in [-5.3, -1.8]:
		for z in [-0.75, 0.75]:
			var post_position := Vector3(x, 0.10, z)
			var post_size := Vector3(0.16, 1.25, 0.16)
			_box("PierPost%02d" % pier_post_index, post_position, post_size, Color("66543b"))
			_box_collision(pier_collisions, "PierPost%02d" % pier_post_index, post_position, post_size)
			pier_post_index += 1
	pier_water_contact = WaterContact.new()
	pier_water_contact.name = "PierWaterContact"
	pier_water_contact.footprint_mode = WaterContact.FootprintMode.COLLISION_SHAPES
	pier_water_contact.collision_reaction_distance_blocks = 0.19
	pier_water_contact.collision_safety_padding_blocks = 0.13
	pier_water_contact.collision_reaction_strength = 0.90
	pier_collisions.add_child(pier_water_contact)
	pier_water_contact.refresh_now()
	pier_contact_materials = pier_water_contact.interaction_materials()
	for pier_material in pier_contact_materials:
		pier_material.set_shader_parameter("contact_color", Color("e2fff8"))
		pier_material.set_shader_parameter("contact_shadow", Color("318f88"))
		pier_material.set_shader_parameter("alpha_scale", 0.88)
		pier_material.set_shader_parameter("contact_line_strength", 0.92)
		pier_material.set_shader_parameter("pixel_density", 64.0)
	_box("Rock", Vector3(2.5, -0.02, 1.2), Vector3(1.0, 1.20, 0.9), Color("637871"))
	_box("RockTop", Vector3(2.5, 0.68, 1.2), Vector3(0.55, 0.22, 0.50), Color("91a190"))
	var rock_collisions := Node3D.new()
	rock_collisions.name = "RockCollisionModel"
	add_child(rock_collisions)
	_box_collision(rock_collisions, "Rock", Vector3(2.5, -0.02, 1.2), Vector3(1.0, 1.20, 0.9))
	rock_water_contact = WaterContact.new()
	rock_water_contact.name = "RockWaterContact"
	rock_water_contact.footprint_mode = WaterContact.FootprintMode.COLLISION_SHAPES
	rock_water_contact.collision_reaction_distance_blocks = 0.22
	rock_water_contact.collision_reaction_strength = 0.74
	rock_water_contact.collision_reaction_width_blocks = 0.032
	rock_collisions.add_child(rock_water_contact)
	rock_water_contact.refresh_now()
	rock_contact_material = rock_water_contact.interaction_materials()[0]
	rock_contact_material.set_shader_parameter("contact_line_strength", 0.78)
	rock_contact_material.set_shader_parameter("pixel_density", 36.0)

	# A moving hull proves that the same collision-waterline owner follows an
	# arbitrary parent transform and produces history without hand-authored quads.
	ship_probe = Node3D.new()
	ship_probe.name = "MovingHull"
	ship_probe.position = Vector3(6.8, 0.0, -3.15)
	add_child(ship_probe)
	var hull_size := Vector3(2.45, 0.62, 1.05)
	var hull_visual := BoxMesh.new()
	hull_visual.size = hull_size
	var hull_mesh := MeshInstance3D.new()
	hull_mesh.name = "HullMesh"
	hull_mesh.position.y = 0.12
	hull_mesh.mesh = hull_visual
	hull_mesh.material_override = _plain_material(Color("805f45"), 0.72)
	ship_probe.add_child(hull_mesh)
	_box_collision(ship_probe, "Hull", Vector3(0.0, 0.12, 0.0), hull_size)
	var cabin_mesh := MeshInstance3D.new()
	cabin_mesh.name = "HullCabin"
	cabin_mesh.position = Vector3(0.0, 0.62, 0.0)
	var cabin_box := BoxMesh.new()
	cabin_box.size = Vector3(0.85, 0.55, 0.72)
	cabin_mesh.mesh = cabin_box
	cabin_mesh.material_override = _plain_material(Color("d4c48d"))
	ship_probe.add_child(cabin_mesh)
	ship_water_contact = WaterContact.new()
	ship_water_contact.name = "HullWaterContact"
	ship_water_contact.footprint_mode = WaterContact.FootprintMode.COLLISION_SHAPES
	ship_water_contact.collision_reaction_distance_blocks = 0.28
	ship_water_contact.collision_safety_padding_blocks = 0.14
	ship_water_contact.collision_reaction_strength = 0.82
	ship_water_contact.full_wake_speed_blocks = 1.2
	ship_probe.add_child(ship_water_contact)
	ship_water_contact.refresh_now()
	ship_contact_materials = ship_water_contact.interaction_materials()
	for ship_material in ship_contact_materials:
		ship_material.set_shader_parameter("contact_color", Color("e2fff8"))
		ship_material.set_shader_parameter("contact_shadow", Color("318f88"))
		ship_material.set_shader_parameter("alpha_scale", 0.76)
	_sync_shore_materials()

	var reflection := ReflectionProbe.new()
	reflection.name = "WaterLabReflection"
	reflection.position = Vector3(FIELD_CENTER_X, 2, 0)
	reflection.size = Vector3(27, 10, 20)
	reflection.box_projection = true
	reflection.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	reflection.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(reflection)

	camera = Camera3D.new()
	camera.name = "WaterLabCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.2
	camera.far = 80.0
	add_child(camera)
	camera.current = true


func _capture_original_values() -> void:
	for key in _known_export_keys():
		original_values[key] = water.get_shader_parameter(key)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -470.0
	panel.offset_right = -15.0
	panel.offset_top = 15.0
	panel.offset_bottom = -15.0
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "Water Lab"
	heading.add_theme_font_size_override("font_size", 24)
	column.add_child(heading)
	var subtitle := Label.new()
	subtitle.text = "Живой подбор существующего материала воды"
	subtitle.modulate = Color(0.78, 0.86, 0.88)
	column.add_child(subtitle)

	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	_add_button(buttons, "Связано", _apply_synced)
	_add_button(buttons, "Референс", _apply_reference)
	_add_button(buttons, "Физика", _apply_physical)
	_add_button(buttons, "Стоячие", _apply_standing)
	_add_button(buttons, "Review2", _apply_review2)
	_add_button(buttons, "Сброс", _reset_original)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	for group_name in GROUPS:
		var scroll := ScrollContainer.new()
		scroll.name = group_name
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		var group_column := VBoxContainer.new()
		group_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group_column.add_theme_constant_override("separation", 7)
		scroll.add_child(group_column)
		if group_name == "Волны":
			var wave_buttons := HBoxContainer.new()
			group_column.add_child(wave_buttons)
			_add_button(wave_buttons, "Прибой", _apply_shore_readable_waves)
			_add_button(wave_buttons, "Море", _apply_sea_waves)
			_add_button(wave_buttons, "Озеро", _apply_lake_waves)
			_add_button(wave_buttons, "Берег", _apply_coast_waves)
			_add_button(wave_buttons, "Река", _apply_river_waves)
		elif group_name == "Берег":
			var height_buttons := HBoxContainer.new()
			group_column.add_child(height_buttons)
			_add_button(height_buttons, "Плоская", _apply_flat_water)
			_add_button(height_buttons, "Объём 0.04", _apply_volume_water)
		for descriptor in GROUPS[group_name]:
			_add_parameter_control(group_column, descriptor)

	var bottom_buttons := HBoxContainer.new()
	column.add_child(bottom_buttons)
	_add_button(bottom_buttons, "Копировать настройки", _copy_settings)
	_add_button(bottom_buttons, "Загрузить сохранённое", _load_saved_selection)
	_add_button(bottom_buttons, "Пауза", _toggle_pause)
	status_label = Label.new()
	status_label.text = "Готово"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 13)
	column.add_child(status_label)
	var help := Label.new()
	help.text = "Средняя кнопка мыши: вращать · колесо: масштаб · R: камера · Space: пауза\nПодбор меняет только копию на стенде."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(0.72, 0.78, 0.80)
	help.add_theme_font_size_override("font_size", 12)
	column.add_child(help)


func _add_button(parent: Control, title: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	parent.add_child(button)


func _add_parameter_control(parent: VBoxContainer, descriptor: Dictionary) -> void:
	var label := Label.new()
	label.text = descriptor.name
	parent.add_child(label)
	var key: String = descriptor.key
	if descriptor.get("type", "number") == "color":
		var picker := ColorPickerButton.new()
		picker.custom_minimum_size.y = 30
		picker.edit_alpha = false
		picker.color_changed.connect(_on_color_changed.bind(key))
		parent.add_child(picker)
		controls[key] = {"color": picker}
		return
	var row := HBoxContainer.new()
	parent.add_child(row)
	var slider := HSlider.new()
	slider.min_value = descriptor.min
	slider.max_value = descriptor.max
	slider.step = descriptor.step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var spin := SpinBox.new()
	spin.min_value = descriptor.min
	spin.max_value = descriptor.max
	spin.step = descriptor.step
	spin.custom_minimum_size.x = 94
	spin.update_on_text_changed = true
	row.add_child(spin)
	slider.value_changed.connect(_on_number_changed.bind(key, spin))
	spin.value_changed.connect(_on_number_changed.bind(key, slider))
	controls[key] = {"slider": slider, "spin": spin}


func _on_number_changed(value: float, key: String, peer: Range) -> void:
	if updating:
		return
	updating = true
	peer.value = value
	water.set_shader_parameter(key, value)
	if key == "pixel_highlight_threshold":
		# One visual size control owns both bands of the clean Review2 highlight.
		water.set_shader_parameter("pixel_highlight_core", lerpf(value, 0.999, 0.90))
	_sync_shore_materials()
	updating = false
	_show_value(key, value)


func _on_color_changed(value: Color, key: String) -> void:
	if updating:
		return
	water.set_shader_parameter(key, value)
	_sync_shore_materials()
	_show_value(key, value.to_html(false))


func _show_value(key: String, value: Variant) -> void:
	if status_label != null:
		status_label.text = "%s = %s" % [key, str(value)]


func _apply_values(values: Dictionary, message: String = "") -> void:
	for key in values:
		water.set_shader_parameter(key, values[key])
	_sync_shore_materials()
	_sync_controls()
	if status_label != null and not message.is_empty():
		status_label.text = message


func _sync_controls() -> void:
	updating = true
	for key in controls:
		var value = water.get_shader_parameter(key)
		if value == null:
			push_warning("Water Lab control has no shader parameter: " + str(key))
			continue
		var pair: Dictionary = controls[key]
		if pair.has("color"):
			(pair.color as ColorPickerButton).color = value
		else:
			(pair.slider as HSlider).value = value
			(pair.spin as SpinBox).value = value
	updating = false


func _apply_standing() -> void:
	_apply_values(STANDING_PRESET, "Стоячие резкие: почти без переноса, форма дрожит")


func _apply_synced() -> void:
	_apply_values(SYNCED_PRESET, "Связано: сохранённый Review2, объём и блики следуют одной волне")


func _apply_capture_preset() -> void:
	if capture_preset.is_empty() or capture_preset == "saved":
		return
	match capture_preset:
		"synced": _apply_synced()
		"sea": _apply_sea_waves()
		"lake": _apply_lake_waves()
		"coast": _apply_coast_waves()
		"shore-readable": _apply_shore_readable_waves()
		"river": _apply_river_waves()
		"review2": _apply_review2()
		_: push_warning("Water Lab capture preset is unknown: " + capture_preset)


func _apply_sea_waves() -> void:
	_apply_values(SEA_WAVES, "Море: длинные группы волн со слабой ветровой рябью")


func _apply_lake_waves() -> void:
	_apply_values(LAKE_WAVES, "Озеро: короткие ветровые волны с широким разбросом направлений")


func _apply_coast_waves() -> void:
	_apply_values(COAST_WAVES, "Берег: собранные крутые гребни; преломление по глубине добавим с береговым полем")


func _apply_shore_readable_waves() -> void:
	_apply_values(SHORE_READABLE_WAVES, "Прибой: сохранённый вид воды, один читаемый береговой гребень")


func _apply_river_waves() -> void:
	_apply_values(RIVER_WAVES, "Река: быстрые вытянутые формы; завихрения потребуют поля течения и препятствий")


func _apply_flat_water() -> void:
	_apply_values({"visual_wave_height":0.0}, "A/B: каноническая плоская поверхность")


func _apply_volume_water() -> void:
	_apply_values({"visual_wave_height":0.04}, "A/B: небольшая настоящая высота, затухающая у берега")


func _apply_reference() -> void:
	_apply_values(REFERENCE_PRESET, "Референс: тёмные впадины, светлые грани, солнце и подводная каустика")


func _apply_physical() -> void:
	_apply_values(PHYSICAL_PRESET, "Физика: свет, волна и камера формируют единый GGX-блик")


func _apply_review2() -> void:
	_apply_values(REVIEW2_PRESET, "Исходные чистые крупные пиксельные блики Review2")


func _reset_original() -> void:
	_apply_values(original_values, "Возвращён материал до художественного подбора")


func _known_export_keys() -> Array[String]:
	var keys: Array[String] = []
	for group in GROUPS.values():
		for descriptor in group:
			if descriptor.key not in keys:
				keys.append(descriptor.key)
	for key in HIDDEN_EXPORT_KEYS:
		if key not in keys:
			keys.append(key)
	return keys


func _load_saved_selection(show_message := true) -> bool:
	if not FileAccess.file_exists(EXPORT_PATH):
		if show_message and status_label != null:
			status_label.text = "Сохранённых настроек пока нет"
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(EXPORT_PATH))
	if not parsed is Dictionary:
		if show_message and status_label != null:
			status_label.text = "Сохранённый файл не удалось прочитать"
		return false
	var allowed := _known_export_keys()
	var values := {}
	var legacy_painted_depth: bool = not parsed.has("scene_depth_mix")
	var legacy_bottom_light: bool = not parsed.has("underwater_caustic_width")
	for key in parsed:
		if key not in allowed:
			continue
		var source_value = water.get_shader_parameter(key)
		var saved_value = parsed[key]
		if source_value is Color and saved_value is String:
			values[key] = Color(saved_value)
		elif typeof(source_value) in [TYPE_FLOAT, TYPE_INT] and typeof(saved_value) in [TYPE_FLOAT, TYPE_INT]:
			values[key] = saved_value
	# Existing saved selections predate real floor-depth sampling. Keep every
	# artistic wave/highlight choice, but replace their opaque painted bands with
	# the corrected depth source and the new transparent preview baseline.
	if legacy_painted_depth:
		values["scene_depth_mix"] = 1.0
		values["underwater_depth_range"] = 1.75
		values["shallow_opacity"] = minf(float(values.get("shallow_opacity", 0.48)), 0.48)
		values["deep_opacity"] = minf(float(values.get("deep_opacity", 0.68)), 0.68)
	if legacy_bottom_light:
		values["underwater_light_mix"] = 0.58
		values["underwater_caustic_strength"] = 0.88
		values["underwater_caustic_width"] = 0.35
		values["underwater_caustic_color"] = Color("b9e978")
		values["underwater_caustic_wave_link"] = 1.0
		values["visual_wave_height"] = 0.04
	_apply_values(values)
	if status_label != null:
		status_label.text = "Загружен последний сохранённый подбор" if not values.is_empty() else "В сохранённом файле нет знакомых настроек"
	return not values.is_empty()


func _sync_shore_materials() -> void:
	if water == null:
		return
	for foam in [beach_foam, wall_foam]:
		if foam == null:
			continue
		for key in [
			"preview_time",
			"shore_boundary_x",
			"shore_split_z",
			"shore_zone_gap",
			"shore_zone_outer",
			"shore_break_distance",
			"shore_runup_distance",
			"shore_foam_width",
			"shore_wet_trace",
			"shore_reflection_strength",
			"shore_reflection_distance",
			"shore_wave_transform",
			"shore_shoaling_distance",
			"shore_shallow_depth",
			"shore_deep_depth",
			"shore_refraction_strength",
			"shore_wavelength_compression",
			"shore_shoaling_strength",
			"shore_crest_coherence",
			"shore_break_threshold",
			"shore_break_softness",
			"shore_runup_speed",
			"wave_length",
			"wave_strength",
			"wave_speed",
			"wave_direction_degrees",
			"wave_natural_mix",
			"wave_direction_spread",
			"wave_scale_variation",
			"wave_grouping",
			"wind_ripple_strength",
			"wave_crest_sharpness",
			"coordinate_scale",
		]:
			foam.set_shader_parameter(key, water.get_shader_parameter(key))
		foam.set_shader_parameter(
			"systemic_shore_strength",
			water.get_shader_parameter("shore_effect_strength"),
		)
	var contact_materials: Array[ShaderMaterial] = []
	if rock_contact_material != null:
		contact_materials.append(rock_contact_material)
	contact_materials.append_array(pier_contact_materials)
	contact_materials.append_array(ship_contact_materials)
	for contact_material in contact_materials:
		for key in ["preview_time", "wave_length", "wave_speed", "wave_direction_degrees"]:
			contact_material.set_shader_parameter(key, water.get_shader_parameter(key))


func export_settings() -> Dictionary:
	var exported := {}
	var keys := _known_export_keys()
	keys.sort()
	for key in keys:
		var value = water.get_shader_parameter(key)
		exported[key] = value.to_html(false) if value is Color else value
	return exported


func _copy_settings() -> void:
	var text := JSON.stringify(export_settings(), "  ", false) + "\n"
	DisplayServer.clipboard_set(text)
	var file := FileAccess.open(EXPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		status_label.text = "Настройки скопированы и сохранены: " + ProjectSettings.globalize_path(EXPORT_PATH)
	else:
		status_label.text = "Настройки скопированы в буфер"


func _toggle_pause() -> void:
	paused = not paused
	if paused:
		paused_time = Time.get_ticks_msec() / 1000.0
		water.set_shader_parameter("preview_time", paused_time)
		_sync_shore_materials()
		status_label.text = "Анимация остановлена"
	else:
		water.set_shader_parameter("preview_time", -1.0)
		_sync_shore_materials()
		status_label.text = "Анимация запущена"


func _update_camera() -> void:
	camera.position = camera_focus + Vector3(sin(orbit.x) * cos(orbit.y), sin(orbit.y), cos(orbit.x) * cos(orbit.y)) * distance
	camera.look_at(camera_focus)
	camera.size = distance * 0.64


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		orbit.x -= event.relative.x * 0.006
		orbit.y = clampf(orbit.y + event.relative.y * 0.006, 0.22, 1.30)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(10.0, distance - 1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(28.0, distance + 1.0)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			orbit = Vector2(-0.72, 0.62)
			distance = DEFAULT_CAMERA_DISTANCE
			camera_focus = CAMERA_FOCUS
			_update_camera()
		elif event.keycode == KEY_SPACE:
			_toggle_pause()


func _capture_after_ready() -> void:
	for frame in 45:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result := OK
	if not capture_path.is_empty():
		result = get_viewport().get_texture().get_image().save_png(capture_path)
		print("PASS WATER_LAB_CAPTURE path=", capture_path, " result=", result)
	if not capture_motion_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(capture_motion_dir)
		for frame in 48:
			water.set_shader_parameter("preview_time", capture_start_time + float(frame) * capture_frame_step)
			_sync_shore_materials()
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var frame_result := get_viewport().get_texture().get_image().save_png(
				capture_motion_dir.path_join("motion-%03d.png" % frame)
			)
			if frame_result != OK:
				result = frame_result
		print("PASS WATER_LAB_MOTION path=", capture_motion_dir, " frames=48 result=", result)
	get_tree().quit(0 if result == OK else 1)
