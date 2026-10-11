@tool
extends Node
## Disposable comparison of sharp planar scene reflection and sky radiance.
## It reads the existing compact terrain projection; it owns no map data.

const Regions = preload("res://scripts/prototypes/ember_compact_water_regions.gd")
const STUDY_EXTENT_CELLS := 22 * 384 # Same bounded 528 m envelope as terrain sections.


func terrain_extent_error(extent: Vector2i) -> String:
	return "Карта превышает проверяемую оболочку участков 528 м по оси." if maxi(extent.x, extent.y) > STUDY_EXTENT_CELLS else ""


func _study_document(document: EmberTerrainPilotResource) -> EmberTerrainPilotResource:
	if document == null or not terrain_extent_error(Vector2i(document.width, document.depth)).is_empty(): return null
	# Read-only compatibility view for the existing small water laboratory.
	# The saved/edited terrain remains sectioned; large maps never allocate it.
	return document

@export_range(0.0, 1.0, 0.01) var scene_reflection := 0.0
@export_range(0.0, 1.0, 0.01) var sky_roughness := 0.0
@export_range(0.0, 1.0, 0.01) var sky_reflection := 0.15
@export_range(0.5, 1.5, 0.05) var reflection_resolution_scale := 1.0
@export_range(0.0, 0.02, 0.0002) var reflection_distortion := 0.002
@export_range(0.0, 4.0, 0.1) var wave_height_voxels := 3.2
@export_range(0.0, 3.0, 0.01) var river_flow_speed := 1.1
@export_range(0.0, 1.0, 0.01) var river_wave_mix := 0.8
@export_range(0.0, 1.0, 0.01) var shore_foam_strength := 0.60
@export_range(0.4, 6.0, 0.1) var shore_foam_width_voxels := 1.8
@export_range(0.0, 1.0, 0.01) var shore_foam_sharpness := 0.70
@export_range(0.0, 4.0, 0.05) var shore_foam_motion_voxels := 1.25
@export_range(0.0, 1.0, 0.01) var river_crest_whiteness := 0.10
@export_range(0.0, 1.0, 0.01) var object_foam_strength := 0.50
@export_range(0.15, 3.0, 0.05) var object_foam_width_voxels := 0.55
@export_range(0.0, 1.0, 0.01) var object_foam_sharpness := 0.92
@export_range(3.0, 14.0, 0.1) var river_wave_spacing_blocks := 8.0
@export_range(0.0, 1.0, 0.01) var river_arc_opening := 0.65
@export_range(0.2, 4.0, 0.05) var river_crest_width_voxels := 0.75
@export_range(0.0, 1.0, 0.01) var river_crest_sharpness := 1.0
@export_range(0.0, 1.0, 0.01) var river_foam_variation := 0.45
@export_range(0.0, 1.0, 0.01) var water_glint_strength := 0.32
@export_range(0.4, 3.0, 0.05) var ripple_cell_scale := 1.1
@export_range(0.0, 1.0, 0.05) var ripple_morph_strength := 0.75
@export_range(0.05, 2.0, 0.05) var ripple_morph_speed := 0.6
@export_range(0.0, 511.0, 1.0) var water_detail_begin_m := 40.0
@export_range(1.0, 512.0, 1.0) var water_detail_end_m := 100.0
@export_range(0.0, 1.0, 0.01) var foam_trail_strength := 0.38
@export_range(0.3, 4.0, 0.1) var foam_trail_lifetime := 2.2
@export_range(0.0, 1.0, 0.01) var shore_foam_breakup := 0.40
@export_range(0.0, 1.0, 0.01) var foam_width_pulse := 0.45
@export_range(-0.75, 0.0, 0.05) var water_level_offset_voxels := 0.0
@export_range(0.0, 4.0, 0.1) var sea_swash_height := 2.8
@export_range(4.0, 16.0, 0.1) var sea_swash_period := 9.0
@export_range(0.0, 16.0, 0.5) var sea_swash_reach := 10.0
@export_range(6.0, 20.0, 0.5) var sea_approach_distance := 20.0
@export_range(0.0, 1.0, 0.01) var sea_approach_strength := 0.65
@export_range(0.0, 1.0, 0.01) var sea_foam_strength := 1.0
@export_range(0.0, 1.0, 0.01) var sea_foam_trail_strength := 0.38
@export_range(0.3, 4.0, 0.1) var sea_foam_trail_lifetime := 2.2
@export_range(0.0, 1.0, 0.01) var sand_wet_strength := 0.55
@export_range(3.0, 20.0, 0.5) var sand_drying_seconds := 12.0
@export_range(0.0, 1.0, 0.01) var waterfall_strength := 1.0
@export_range(0.2, 2.0, 0.05) var waterfall_speed := 1.0
@export_range(0.0, 1.0, 0.01) var waterfall_irregularity := 0.65
@export_range(0.0, 1.0, 0.01) var waterfall_foam_strength := 0.75
@export_range(0.0, 1.0, 0.01) var reaction_strength := 0.65
@export_range(0.2, 3.0, 0.05) var reaction_spread_speed := 0.45
@export_range(0.0, 1.0, 0.01) var reaction_opening := 0.70
@export_range(0.05, 1.0, 0.05) var reaction_birth_seconds := 0.35
@export_range(0.0, 0.5, 0.01) var local_bob_strength := 0.45
@export_range(0.0, 0.04, 0.001) var refraction_strength := 0.035
@export_range(0.0, 1.0, 0.01) var underwater_haze := 0.55
@export_range(0.0, 1.0, 0.01) var underwater_caustics := 0.80
@export_range(0.0, 1.0, 0.01) var underwater_shafts := 0.42
@export_enum("Выключено", "Запечённый цикл", "Живая симуляция") var obstacle_wave_mode := 0
@export_range(0.0, 1.0, 0.05) var obstacle_wave_strength := 0.85

const WATER_LAYER := 2
const REFLECTION_PASS_LAYER := 1 << 19
const REFRACTION_PASS_LAYER := 1 << 18
const RiverPhase = preload("res://scripts/prototypes/ember_compact_river_phase.gd")

# UI metadata only. Saved values belong to this existing scene controller.
# Both the editor panel and the runtime comparison route to those properties.
const WATER_VALUES := {
	"water_detail_begin_m": ["Полные детали до, м", 0.0, 511.0, 1.0, "Дальность деталей"],
	"water_detail_end_m": ["Упрощённые детали от, м", 1.0, 512.0, 1.0, "Дальность деталей"],
	"obstacle_wave_mode": ["Обтекание препятствий", 0.0, 2.0, 1.0, "Волны и препятствия", ["Выключено", "Запечённый цикл", "Живая симуляция"]],
	"obstacle_wave_strength": ["Сила обтекания", 0.0, 1.0, 0.05, "Волны и препятствия"],
	"wave_height_voxels": ["Высота волн", 0.0, 4.0, 0.1, "Поверхность и течение"],
	"river_flow_speed": ["Скорость реки", 0.0, 3.0, 0.01, "Поверхность и течение"],
	"river_wave_mix": ["Сила речных волн", 0.0, 1.0, 0.01, "Поверхность и течение"],
	"river_wave_spacing_blocks": ["Расстояние между волнами", 3.0, 14.0, 0.1, "Поверхность и течение"],
	"river_arc_opening": ["Раскрытие дуг", 0.0, 1.0, 0.01, "Поверхность и течение"],
	"local_bob_strength": ["Мелкая рябь", 0.0, 0.5, 0.01, "Поверхность и течение"],
	"water_glint_strength": ["Блики на ряби", 0.0, 1.0, 0.01, "Поверхность и течение"],
	"ripple_cell_scale": ["Размер ячеек ряби", 0.4, 3.0, 0.05, "Поверхность и течение"],
	"ripple_morph_strength": ["Изменение рисунка ряби", 0.0, 1.0, 0.05, "Поверхность и течение"],
	"ripple_morph_speed": ["Скорость изменения ряби", 0.05, 2.0, 0.05, "Поверхность и течение"],
	"water_level_offset_voxels": ["Смещение уровня воды, вокс.", -0.75, 0.0, 0.05, "Поверхность и течение"],
	"sea_swash_height": ["Высота морского набега", 0.0, 4.0, 0.1, "Море и берег"],
	"sea_swash_period": ["Период морской волны, с", 4.0, 16.0, 0.1, "Море и берег"],
	"sea_swash_reach": ["Дальность набега, вокс.", 0.0, 16.0, 0.5, "Море и берег"],
	"sea_approach_distance": ["Начало волны от берега, вокс.", 6.0, 20.0, 0.5, "Море и берег"],
	"sea_approach_strength": ["Сила волны до берега", 0.0, 1.0, 0.01, "Море и берег"],
	"sea_foam_strength": ["Пена морской волны", 0.0, 1.0, 0.01, "Море и берег"],
	"sea_foam_trail_strength": ["Морские пенные разводы", 0.0, 1.0, 0.01, "Море и берег"],
	"sea_foam_trail_lifetime": ["Затухание морских разводов, с", 0.3, 4.0, 0.1, "Море и берег"],
	"sand_wet_strength": ["Мокрый след на песке", 0.0, 1.0, 0.01, "Море и берег"],
	"sand_drying_seconds": ["Высыхание песка, с", 3.0, 20.0, 0.5, "Море и берег"],
	"waterfall_strength": ["Сила водопада", 0.0, 1.0, 0.01, "Водопад"],
	"waterfall_speed": ["Скорость водопада", 0.2, 2.0, 0.05, "Водопад"],
	"waterfall_irregularity": ["Неровность струи", 0.0, 1.0, 0.01, "Водопад"],
	"waterfall_foam_strength": ["Пена под водопадом", 0.0, 1.0, 0.01, "Водопад"],
	"river_crest_whiteness": ["Белизна гребня", 0.0, 1.0, 0.01, "Пена и кромка"],
	"river_crest_width_voxels": ["Толщина линии гребня", 0.2, 4.0, 0.05, "Пена и кромка"],
	"river_crest_sharpness": ["Чёткость гребня", 0.0, 1.0, 0.01, "Пена и кромка"],
	"river_foam_variation": ["Неровность гребня", 0.0, 1.0, 0.01, "Пена и кромка"],
	"foam_trail_strength": ["Пенные разводы", 0.0, 1.0, 0.01, "Пена и кромка"],
	"foam_trail_lifetime": ["Затухание разводов, с", 0.3, 4.0, 0.1, "Пена и кромка"],
	"shore_foam_breakup": ["Разрывы береговой пены", 0.0, 1.0, 0.01, "Пена и кромка"],
	"foam_width_pulse": ["Изменение толщины пены", 0.0, 1.0, 0.01, "Пена и кромка"],
	"shore_foam_strength": ["Пена у берега", 0.0, 1.0, 0.01, "Пена и кромка"],
	"shore_foam_width_voxels": ["Ширина береговой пены", 0.4, 6.0, 0.1, "Пена и кромка"],
	"shore_foam_sharpness": ["Чёткость береговой пены", 0.0, 1.0, 0.01, "Пена и кромка"],
	"shore_foam_motion_voxels": ["Ход береговой пены", 0.0, 4.0, 0.05, "Пена и кромка"],
	"object_foam_strength": ["Пена у объектов", 0.0, 1.0, 0.01, "Пена и кромка"],
	"object_foam_width_voxels": ["Ширина кромки объекта", 0.15, 3.0, 0.05, "Пена и кромка"],
	"object_foam_sharpness": ["Чёткость кромки объекта", 0.0, 1.0, 0.01, "Пена и кромка"],
	"reaction_strength": ["Сила реакции на движение", 0.0, 1.0, 0.01, "След от движения"],
	"reaction_spread_speed": ["Скорость расхождения", 0.2, 3.0, 0.05, "След от движения"],
	"reaction_opening": ["Раскрытие следа", 0.0, 1.0, 0.01, "След от движения"],
	"reaction_birth_seconds": ["Время появления следа", 0.05, 1.0, 0.05, "След от движения"],
	"scene_reflection": ["Отражение объектов", 0.0, 1.0, 0.01, "Отражения и глубина"],
	"reflection_resolution_scale": ["Размер отражения", 0.5, 1.5, 0.05, "Отражения и глубина"],
	"reflection_distortion": ["Рябь отражения", 0.0, 0.02, 0.0002, "Отражения и глубина"],
	"sky_roughness": ["Размытость неба", 0.0, 1.0, 0.01, "Отражения и глубина"],
	"sky_reflection": ["Сила отражения неба", 0.0, 1.0, 0.01, "Отражения и глубина"],
	"refraction_strength": ["Искажение под водой", 0.0, 0.04, 0.001, "Отражения и глубина"],
	"underwater_haze": ["Синева под водой", 0.0, 1.0, 0.01, "Отражения и глубина"],
	"underwater_caustics": ["Свет на дне", 0.0, 1.0, 0.01, "Отражения и глубина"],
	"underwater_shafts": ["Лучи в воде", 0.0, 1.0, 0.01, "Отражения и глубина"],
}

var _viewport: SubViewport
var _camera: Camera3D
var _floor_viewport: SubViewport
var _floor_camera: Camera3D
var _material: ShaderMaterial
var _ground_material: ShaderMaterial
var _shaft_material: ShaderMaterial
var _shaft_volume: FogVolume
var _water_height := 16.02
var _base_water_height := 16.02
var _sea_swash: RefCounted
var _waterfall: RefCounted
var _waterfall_update_ms := 0
var _waterfall_button: Button
var _waterfall_camera_initialized := false
var _waterfall_controls_initialized := false
var _water_group_toggles := {}
var _sea_update_ms := 0
var _prepared := false
var _study_target: Node3D
var _follow: EmberFollowCamera
var _hero_target: Node3D
var _hero_fov := 40.0
var _water_view := true
var _river_view := true
var _camera_button: Button
var _dive_button: Button
var _river_button: Button
var _environment: Environment
var _terrain: EmberTerrainPilotResource
var _flow_texture: ImageTexture
var _height_texture: ImageTexture
var _shore_texture: ImageTexture
var _contact_texture: ImageTexture
var _phase_texture: ImageTexture
var _water_regions: RefCounted
var runtime_water_activity_enabled := true # Runtime experiment switch; no authored setting.
var _region_projection_id := 0
var _region_staged := false
var _fields_build_count := 0
var _field_revision := -1
var _projection_id := 0
var _preview_poll_ms := 0
var _contact_signature := 0
var _parameter_signature := 0
var _underwater_view := false
var _surface_target_position := Vector3.ZERO
var _surface_distance := 410.0
var _surface_polar := 1.14
var _surface_yaw := 0.48
var _surface_contacts: Array[EmberWaterContact3D] = []
var _reaction_preview := false
var _reaction_clock := 0.0
var _reaction_prop: Node3D
var _reaction_start := Vector3.ZERO
var _apply_button: Button
var _apply_status: Label
var _apply_pending_ms := 0
var _wave_obstacles: RefCounted
var _obstacle_signature := 0
var _obstacle_status: Label
var _obstacle_poll_ms := 0
var _obstacle_shapes_signature := 0
var _obstacle_settings_signature := 0
var _obstacle_runtime_motion := false


func water_settings_snapshot() -> Dictionary:
	var values: Dictionary = {}
	for key in WATER_VALUES: values[key] = get(key)
	return values


func _apply_in_editor() -> void:
	var scene := get_parent()
	if not EngineDebugger.is_active() or scene.scene_file_path.is_empty(): return
	_apply_button.disabled = true
	_apply_status.text = "Передаём настройки…"
	_apply_pending_ms = Time.get_ticks_msec()
	var sun := scene.get_node_or_null("Map/Look/Sun") as DirectionalLight3D
	EngineDebugger.send_message("ember_water:apply", [scene.scene_file_path, scene.get_path_to(self), water_settings_snapshot(), EmberLights.sun_look_snapshot(sun)])


func _capture_water_message(message: String, data: Array) -> bool:
	if message != "result": return false
	_apply_pending_ms = 0
	if is_instance_valid(_apply_button): _apply_button.disabled = false
	if is_instance_valid(_apply_status) and data.size() == 1 and data[0] is Dictionary:
		_apply_status.text = str(data[0].get("message", "Не удалось перенести настройки."))
	return true


func _exit_tree() -> void:
	if _water_regions != null: _water_regions.close()
	if not Engine.is_editor_hint() and EngineDebugger.has_capture("ember_water"):
		EngineDebugger.unregister_message_capture("ember_water")
	var map := water_settings_map() if get_parent() != null else null
	var projection := map.get("_visual_surface_projection") as EmberTerrainPilotProjection if is_instance_valid(map) else null
	if is_instance_valid(projection) and projection.get_instance_id() in [_projection_id, _region_projection_id]:
		projection.set_water_surface_offset(0.0)
		projection.clear_water_regions()
		projection.set_sea_swash(null)
		projection.set_waterfall(null)
		projection.set_wave_obstacles(null)


func _reflection_size() -> Vector2i:
	var source_size: Vector2i = get_viewport().size
	return Vector2i(maxi(1, roundi(float(source_size.x) * reflection_resolution_scale)),
		maxi(1, roundi(float(source_size.y) * reflection_resolution_scale)))


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if EngineDebugger.is_active():
		EngineDebugger.register_message_capture("ember_water", _capture_water_message)
	_viewport = SubViewport.new()
	_viewport.name = "PlanarReflectionViewport"
	_viewport.size = _reflection_size()
	_viewport.transparent_bg = true
	_viewport.world_3d = get_viewport().world_3d
	_viewport.render_target_update_mode = (SubViewport.UPDATE_ALWAYS
		if scene_reflection > 0.0 else SubViewport.UPDATE_DISABLED)
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.name = "MirroredCamera"
	_viewport.add_child(_camera)
	_camera.make_current()
	_floor_viewport = SubViewport.new()
	_floor_viewport.name = "UnderwaterFloorViewport"
	_floor_viewport.size = get_viewport().size
	_floor_viewport.transparent_bg = true
	_floor_viewport.world_3d = get_viewport().world_3d
	_floor_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_floor_viewport)
	_floor_camera = Camera3D.new()
	_floor_camera.name = "UnderwaterFloorCamera"
	_floor_camera.cull_mask = REFRACTION_PASS_LAYER
	_floor_viewport.add_child(_floor_camera)
	_floor_camera.make_current()
	_create_controls()


func _process(_delta: float) -> void:
	if _apply_pending_ms > 0 and Time.get_ticks_msec() - _apply_pending_ms > 5000:
		_apply_pending_ms = 0
		_apply_button.disabled = false
		_apply_status.text = "Редактор не ответил. Перезапустите F6 после обновления плагина."
	_prepare_water()
	if not _prepared:
		return
	_refresh_sea_swash()
	_refresh_waterfall()
	_refresh_wave_obstacles()
	if Engine.is_editor_hint():
		_sync_sun_direction()
		_refresh_editor_preview()
		return
	_update_reaction_preview(_delta)
	_sync_sun_direction()
	_upload_surface_contacts()
	initialize_startup_camera()
	var source := get_viewport().get_camera_3d()
	if source == null:
		return
	_update_underwater(source.global_position)
	var above_surface := source.global_position.y >= _water_height
	_floor_viewport.render_target_update_mode = (SubViewport.UPDATE_ALWAYS
		if above_surface else SubViewport.UPDATE_DISABLED)
	_viewport.render_target_update_mode = (SubViewport.UPDATE_ALWAYS
		if above_surface and scene_reflection > 0.0 else SubViewport.UPDATE_DISABLED)
	if _viewport.size != _reflection_size():
		_viewport.size = _reflection_size()
	if _floor_viewport.size != get_viewport().size:
		_floor_viewport.size = get_viewport().size
	_camera.projection = source.projection
	_camera.fov = source.fov
	_camera.size = source.size
	_camera.near = source.near
	_camera.far = source.far
	_camera.keep_aspect = source.keep_aspect
	# The extra layer identifies this camera in the terrain shader, which cuts
	# away the submerged ground from the reflected view.
	source.cull_mask &= ~(REFLECTION_PASS_LAYER | REFRACTION_PASS_LAYER)
	_camera.cull_mask = (source.cull_mask & ~WATER_LAYER) | REFLECTION_PASS_LAYER
	_floor_camera.projection = source.projection
	_floor_camera.fov = source.fov
	_floor_camera.size = source.size
	_floor_camera.near = source.near
	_floor_camera.far = source.far
	_floor_camera.keep_aspect = source.keep_aspect
	_floor_camera.global_transform = source.global_transform
	# Reflect the camera across the water plane. Reversing the right axis keeps
	# a right-handed Godot camera for the projected mirror view.
	var basis := source.global_transform.basis
	var right := -basis.x
	right.y = -right.y
	var up := basis.y
	up.y = -up.y
	var backward := basis.z
	backward.y = -backward.y
	var position := source.global_position
	position.y = 2.0 * _water_height - position.y
	_camera.global_transform = Transform3D(Basis(right, up, backward), position)
	var reflection_view := Projection(_camera.get_camera_projection()) * Projection(_camera.get_camera_transform().affine_inverse())
	_set_water_parameter_if_changed("reflection_view_projection", reflection_view, scene_reflection > 0.0)


func _refresh_editor_preview() -> void:
	if Time.get_ticks_msec() < _preview_poll_ms:
		return
	_preview_poll_ms = Time.get_ticks_msec() + 250
	var map := get_parent().get_node_or_null("Map") as EmberMapLoader
	if map == null:
		return
	var projection := map.get("_visual_surface_projection") as EmberTerrainPilotProjection
	# Reuse the previous masks during a stroke, then derive them once it settles.
	if projection == null or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	if projection.get_instance_id() != _projection_id or projection.column_revision() != _field_revision:
		_prepare_water()
		return
	var contacts := _current_contact_signature(map)
	if contacts != _contact_signature:
		_contact_texture = _make_contact_texture(projection.document, projection, map)
		_material.set_shader_parameter("object_contact_distance_map", _contact_texture)
		_material.set_shader_parameter("object_contact_available", 1.0 if not _surface_contacts.is_empty() else 0.0)
		_sync_region_parameters()
		_contact_signature = contacts
	if _current_parameter_signature() != _parameter_signature:
		_apply_parameters()


func _current_contact_signature(map: EmberMapLoader) -> int:
	var shapes: Array = []
	for node in map.find_children("*", "EmberWaterContact3D", true, false):
		var contact := node as EmberWaterContact3D
		shapes.append([contact.get_instance_id(), contact.static_surface_foam_footprint,
			contact.foam_footprint_shape(_water_height)])
	return hash(shapes)


func _current_parameter_signature() -> int:
	var values: Array = []
	for key in WATER_VALUES:
		values.append(get(key))
	return hash(values)


func water_settings_map() -> EmberMapLoader:
	return get_parent().get_node_or_null("Map") as EmberMapLoader


func refresh_water_settings() -> void:
	_apply_parameters()
	_refresh_sea_swash()
	_refresh_waterfall()
	_refresh_wave_obstacles()


func _unhandled_input(event: InputEvent) -> void:
	if not _water_view or _follow == null or not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed:
		return
	if mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
		_follow.follow_distance = maxf(75.0, _follow.follow_distance / 1.14)
	elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_follow.follow_distance = minf(1200.0, _follow.follow_distance * 1.14)


func startup_preparation_status() -> Dictionary:
	var map := water_settings_map()
	if map == null or map.compact_terrain == null:
		return {"ready": false, "text": "Не удалось найти данные воды. Проверьте карту в редакторе."}
	var extent_error := terrain_extent_error(Vector2i(map.compact_terrain.width, map.compact_terrain.depth))
	if not extent_error.is_empty(): return {"ready": false, "text": extent_error}
	if not _prepared:
		return {"ready": false, "text": "Подключаем воду" if _water_regions != null and _water_regions.ready else "Готовим берега и воду"}
	if obstacle_wave_mode != 0 and obstacle_wave_strength > 0.001 and (_wave_obstacles == null or not _wave_obstacles.ready):
		return {"ready": false, "text": "Готовим волны у препятствий"}
	return {"ready": true, "text": "Вода готова"}


func initialize_startup_camera() -> void:
	_prepare_camera()
	if not _waterfall_camera_initialized and _follow != null and _waterfall != null and not _waterfall.info.is_empty():
		_show_waterfall()
		_waterfall_camera_initialized = true


func _prepare_camera() -> void:
	if _follow != null:
		return
	_follow = get_tree().get_first_node_in_group("ember_follow_camera") as EmberFollowCamera
	if _follow == null:
		return
	_hero_target = _follow.target
	_hero_fov = _follow.fov
	_study_target = Node3D.new()
	_study_target.name = "WaterViewTarget"
	get_parent().add_child(_study_target)
	var map := get_parent().get_node("Map") as EmberMapLoader
	_terrain = map.compact_terrain as EmberTerrainPilotResource
	_study_target.global_position = Vector3(float(_terrain.width) * 0.49,
		_water_height, float(_terrain.depth) * 0.70)
	_surface_target_position = _study_target.global_position
	_environment = (get_parent().get_node("Map/Look/WorldEnvironment") as WorldEnvironment).environment
	var reflection_environment := _environment.duplicate() as Environment
	reflection_environment.background_mode = Environment.BG_COLOR
	reflection_environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	_camera.environment = reflection_environment
	_floor_camera.environment = reflection_environment
	_follow.target = _study_target
	_follow.pitch_lock = false
	_follow.polar_min = 0.20
	_follow.polar_max = 2.30
	_follow.polar_angle = 1.14
	_follow.follow_distance = 410.0
	_follow.look_height = 0.0
	_follow.yaw = 0.48
	_follow.fov = 55.0
	if get_parent().get_node_or_null("Map/Props/SeaWaveDivider") != null:
		var stone := get_parent().get_node("Map/Props/WaterContactStone") as Node3D
		_study_target.global_position = Vector3(stone.global_position.x, _water_height, stone.global_position.z)
		_follow.follow_distance = 190.0
		_follow.polar_angle = 1.02


func _toggle_camera() -> void:
	if _follow == null:
		return
	if _underwater_view:
		_set_underwater_view(false)
	_water_view = not _water_view
	_follow.target = _study_target if _water_view else _hero_target
	_follow.follow_distance = (410.0 if _river_view else 640.0) if _water_view else 200.0
	_follow.polar_angle = (1.14 if _river_view else 1.45) if _water_view else 0.88
	if _water_view:
		_follow.yaw = 0.48 if _river_view else 2.54
	_follow.look_height = 0.0 if _water_view else 34.0
	_follow.fov = 55.0 if _water_view else _hero_fov
	_camera_button.text = "Камера: вода (переключить)" if _water_view else "Камера: герой (переключить)"
	_dive_button.disabled = not _water_view


func _toggle_river_view() -> void:
	if _follow == null or _terrain == null:
		return
	if _underwater_view:
		_set_underwater_view(false)
	_river_view = not _river_view
	_study_target.global_position = (Vector3(float(_terrain.width) * 0.49, _water_height,
		float(_terrain.depth) * 0.70) if _river_view else Vector3(float(_terrain.width) * 0.47,
		_water_height, float(_terrain.depth) * 0.46))
	var obstacle_probe := get_parent().get_node_or_null("Map/Props/SeaWaveDivider") as Node3D
	if obstacle_probe != null:
		var prop := get_parent().get_node("Map/Props/WaterContactStone") as Node3D if _river_view else obstacle_probe
		_study_target.global_position = Vector3(prop.global_position.x, _water_height, prop.global_position.z)
	if _water_view:
		_follow.follow_distance = 410.0 if _river_view else 640.0
		_follow.polar_angle = 1.14 if _river_view else 1.45
		_follow.yaw = 0.48 if _river_view else 2.54
		_follow.reset_follow_height()
		if obstacle_probe != null:
			_follow.follow_distance = 190.0
			_follow.polar_angle = 1.02
	_river_button.text = "К морю" if _river_view else "К реке"


func _toggle_underwater_view() -> void:
	_set_underwater_view(not _underwater_view)


func _show_waterfall() -> void:
	if _waterfall == null or _waterfall.info.is_empty() or _follow == null: return
	if _underwater_view: _set_underwater_view(false)
	var map := water_settings_map()
	var projection := map.get("_visual_surface_projection") as Node3D
	var center: Vector2 = _waterfall.info.impact
	_study_target.global_position = projection.to_global(Vector3(center.x,
		lerpf(float(_waterfall.info.bottom), float(_waterfall.info.top), 0.40), center.y))
	_follow.target = _study_target
	_water_view = true
	_follow.follow_distance = 105.0
	_follow.polar_angle = 0.94
	# View from downstream; the upstream bank otherwise hides the falling sheet.
	_follow.yaw = atan2(float(_waterfall.info.direction.x), float(_waterfall.info.direction.y)) - 0.68
	_follow.look_height = 0.0
	_follow.fov = 55.0
	_follow.reset_follow_height()


func _set_underwater_view(enabled: bool) -> void:
	if _follow == null or _terrain == null:
		return
	if enabled == _underwater_view:
		return
	_underwater_view = enabled
	if enabled:
		_surface_target_position = _study_target.global_position
		_surface_distance = _follow.follow_distance
		_surface_polar = _follow.polar_angle
		_surface_yaw = _follow.yaw
		var deep := _find_deep_water_point()
		var floor_index := _terrain.column_index(floori(deep.x), floori(deep.y))
		var floor_height := float(_terrain.origin_y + _terrain.column_value("heights", floor_index))
		_study_target.global_position = Vector3(deep.x,
			minf(_water_height - 7.0, floor_height + 19.0), deep.y)
		_follow.follow_distance = 24.0
		_follow.polar_angle = 1.05
	else:
		_study_target.global_position = _surface_target_position
		_follow.follow_distance = _surface_distance
		_follow.polar_angle = _surface_polar
		_follow.yaw = _surface_yaw
	_follow.reset_follow_height()
	_dive_button.text = "Над водой (переключить)" if enabled else "Под воду (переключить)"


func _find_deep_water_point() -> Vector2:
	var best := Vector2i(_terrain.width / 2, _terrain.depth / 2)
	var best_score := -1.0
	for z in range(32, _terrain.depth - 32, 16):
		for x in range(32, _terrain.width - 32, 16):
			var index := _terrain.column_index(x, z)
			var level := _terrain.column_value("water_levels", index)
			var depth := level - _terrain.column_value("heights", index)
			if _terrain.column_value("water_materials", index) <= 0 or depth < 16:
				continue
			var room := true
			for offset in [Vector2i(-24, 0), Vector2i(24, 0),
					Vector2i(0, -24), Vector2i(0, 24)]:
				var neighbour := _terrain.column_index(x + offset.x, z + offset.y)
				if _terrain.column_value("water_materials", neighbour) <= 0 or _terrain.column_value("water_levels", neighbour) != level or level - _terrain.column_value("heights", neighbour) < 14:
					room = false
					break
			if not room:
				continue
			var center_distance := Vector2(x - _terrain.width / 2, z - _terrain.depth / 2).length()
			var score := float(depth) - center_distance * 0.02
			if score > best_score:
				best_score = score
				best = Vector2i(x, z)
	return Vector2(best.x + 0.5, best.y + 0.5)


func _update_underwater(camera_position: Vector3) -> void:
	if _environment == null or _terrain == null:
		return
	var x := floori(camera_position.x)
	var z := floori(camera_position.z)
	var submerged := false
	if x >= 0 and x < _terrain.width and z >= 0 and z < _terrain.depth:
		var index := _terrain.column_index(x, z)
		var surface := float(_terrain.origin_y + _terrain.column_value("water_levels", index)) + 0.02 + water_level_offset_voxels
		var floor_height := float(_terrain.origin_y + _terrain.column_value("heights", index))
		submerged = (_terrain.column_value("water_materials", index) > 0
			and camera_position.y < surface and camera_position.y > floor_height + 1.0)
	_environment.fog_enabled = submerged
	if _shaft_volume != null and _shaft_volume.visible != submerged:
		_shaft_volume.visible = submerged
		_environment.volumetric_fog_enabled = submerged and underwater_shafts > 0.001
		if _ground_material != null:
			_ground_material.set_shader_parameter("underwater_caustics",
				underwater_caustics if submerged else 0.0)
		if _water_regions != null: _water_regions.set_ground_parameter("underwater_caustics", underwater_caustics if submerged else 0.0)
	if submerged:
		var depth_blocks := maxf((_water_height - camera_position.y) / 16.0, 0.0)
		_environment.fog_light_color = Color(0.06, 0.57, 0.72).lerp(
			Color(0.025, 0.24, 0.48), clampf(depth_blocks * 0.23, 0.0, 1.0))
		_environment.fog_density = 0.0015 + underwater_haze * 0.006
		_environment.fog_sky_affect = 0.75
		_environment.fog_sun_scatter = 0.14


func _prepare_water() -> void:
	var map := water_settings_map()
	if map == null: return
	var projection := map.get("_visual_surface_projection") as EmberTerrainPilotProjection
	if projection == null or projection.document == null: return
	_material = projection.get("_water_material") as ShaderMaterial
	_ground_material = projection.get("_ground_material") as ShaderMaterial
	if _material == null: return
	_terrain = _study_document(projection.document)
	if _terrain == null: return
	if _water_regions == null or _region_projection_id != projection.get_instance_id():
		if _water_regions != null: _water_regions.close()
		_water_regions = Regions.new()
		_region_projection_id = projection.get_instance_id()
		_region_staged = false
		_prepared = false
	if _prepared and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): return
	if _water_regions._revision != projection.column_revision():
		projection.cancel_water_regions()
		_region_staged = false
		_apply_parameters()
		_water_regions.request(_terrain, projection.column_revision())
	if _prepared and _field_revision == projection.column_revision(): return
	if not _water_regions.prepare(3000, _material, _ground_material, Vector2(projection.global_position.x, projection.global_position.z)): return
	if not _region_staged:
		projection.stage_water_regions(_water_regions)
		_region_staged = true
	if projection.pending_tile_count() > 0 or not _water_regions.gpu_ready(): return
	var publish_started := Time.get_ticks_usec()
	_water_regions.commit()
	_sea_swash = _water_regions
	_waterfall = _water_regions.waterfall
	_flow_texture = _water_regions.flow_texture
	_phase_texture = _water_regions.phase_texture
	_material.set_shader_parameter("water_flow_map", _flow_texture)
	_material.set_shader_parameter("river_phase_map", _phase_texture)
	_material.set_shader_parameter("flow_origin_xz", Vector2(projection.global_position.x, projection.global_position.z))
	_material.set_shader_parameter("flow_map_extent_blocks", Vector2(_terrain.width, _terrain.depth) / 16.0)
	_material.set_shader_parameter("river_flow_enabled", 1.0 if _terrain.has_flow() else 0.0)
	_material.set_shader_parameter("shore_field_available", 1.0)
	_material.set_shader_parameter("ripple_cell_field", preload("res://scripts/prototypes/ember_compact_ripple_field.gd").texture())
	_material.set_shader_parameter("ripple_field_available", 1.0)
	_base_water_height = _water_regions.stats.get("base_water_height", 16.02)
	_water_height = _base_water_height + water_level_offset_voxels
	_make_contact_texture(_terrain, projection, map)
	_material.set_shader_parameter("object_contact_available", 1.0 if not _surface_contacts.is_empty() else 0.0)
	if not Engine.is_editor_hint():
		for tile: Node3D in projection._tiles.values():
			(tile.get_node("Water") as MeshInstance3D).layers = WATER_LAYER
			(tile.get_node("Ground") as MeshInstance3D).layers |= REFRACTION_PASS_LAYER
		_ground_material.set_shader_parameter("reflection_pass_enabled", true)
		_create_underwater_light(map)
		_material.set_shader_parameter("planar_reflection", _viewport.get_texture())
		_material.set_shader_parameter("floor_refraction", _floor_viewport.get_texture())
	_material.set_shader_parameter("floor_camera_available", 0.0 if Engine.is_editor_hint() else 1.0)
	_bind_waterfall(projection)
	_apply_parameters()
	projection.commit_water_regions(_water_regions)
	if is_instance_valid(_river_button): _river_button.visible = not _water_regions.dry_tiles.is_empty()
	_field_revision = projection.column_revision()
	_projection_id = projection.get_instance_id()
	_contact_signature = _current_contact_signature(map)
	_wave_obstacles = null
	_obstacle_signature = 0
	_fields_build_count += 1
	_region_staged = false
	_prepared = true
	_water_regions.stats["publish_us"] = Time.get_ticks_usec() - publish_started


func _make_contact_texture(document: EmberTerrainPilotResource,
		projection: EmberTerrainPilotProjection, map: EmberMapLoader) -> ImageTexture:
	# The existing contact components provide the footprint. Only this trial
	# paints opt-in primitive props directly onto the moving water surface.
	var contacts: Array[Dictionary] = []
	_surface_contacts.clear()
	for node in map.find_children("*", "EmberWaterContact3D", true, false):
		var contact := node as EmberWaterContact3D
		contact.set_surface_integrated(false)
		if not contact.static_surface_foam_footprint:
			continue
		if contacts.size() >= 8:
			continue
		var footprint := contact.foam_footprint_shape(_water_height)
		if footprint.is_empty():
			continue
		contacts.append({"owner": contact, "shape": footprint})
		_surface_contacts.append(contact)
	for entry in contacts: entry.owner.set_surface_integrated(true)
	_upload_surface_contacts()
	return null


func _upload_surface_contacts() -> void:
	if _material == null:
		return
	var shapes := PackedVector4Array()
	var metadata := PackedVector2Array()
	var wakes := PackedVector4Array()
	var wake_details := PackedVector4Array()
	shapes.resize(8)
	metadata.resize(8)
	wakes.resize(12)
	wake_details.resize(12)
	var count := 0
	var wake_count := 0
	for contact in _surface_contacts:
		if not is_instance_valid(contact): continue
		var footprint := contact.foam_footprint_shape(_water_height)
		if not footprint.is_empty() and count < 8:
			var center: Vector2 = footprint["center"] / 16.0
			var half: Vector2 = footprint.get("half", Vector2.ONE * float(footprint.get("radius", 0.0))) / 16.0
			shapes[count] = Vector4(center.x, center.y, half.x, half.y)
			metadata[count] = Vector2(1.0 if footprint["kind"] == "circle" else 0.0, float(footprint.get("angle", 0.0)))
			count += 1
		for sample in contact.surface_wake_samples(12 - wake_count):
			if wake_count >= 12: break
			var point: Vector3 = sample["position"]
			var forward: Vector2 = sample["forward"]
			wakes[wake_count] = Vector4(point.x / 16.0, point.z / 16.0, float(sample["age"]), float(sample.get("strength", 1.0)))
			wake_details[wake_count] = Vector4(forward.x, forward.y, float(sample["life"]), float(sample["radius"]))
			wake_count += 1
	_set_water_parameter_if_changed("object_shapes", shapes)
	_set_water_parameter_if_changed("object_shape_meta", metadata)
	_set_water_parameter_if_changed("object_shape_count", count)
	_set_water_parameter_if_changed("reaction_samples", wakes)
	_set_water_parameter_if_changed("reaction_details", wake_details)
	_set_water_parameter_if_changed("reaction_count", wake_count)


func _set_water_parameter_if_changed(key: String, value: Variant, regional := true) -> void:
	# Read the base material so rebind/Undo and direct preview edits stay visible.
	if _material.get_shader_parameter(key) != value:
		_material.set_shader_parameter(key, value)
	# Regions own separate caches; a newly bound region still receives its value.
	if regional and _water_regions != null:
		_water_regions.set_water_parameter(key, value)


func _toggle_reaction_preview() -> void:
	if Engine.is_editor_hint(): return
	if _reaction_prop == null:
		_reaction_prop = get_parent().get_node_or_null("Map/Props/WaterContactStone") as Node3D
		if _reaction_prop == null: return
		_reaction_start = _reaction_prop.position
	_reaction_preview = not _reaction_preview
	_reaction_clock = 0.0
	if not _reaction_preview:
		_reaction_prop.position = _reaction_start
		var contact := _reaction_prop.get_node_or_null("WaterContact") as EmberWaterContact3D
		if contact != null:
			contact.reset_motion_tracking()


func _update_reaction_preview(delta: float) -> void:
	if not _reaction_preview or not is_instance_valid(_reaction_prop): return
	_reaction_clock += delta
	# Smooth starts/stops; the contact owner samples actual motion. A short
	# course in the wet middle of the study avoids changing authored transforms.
	_reaction_prop.position = _reaction_start + Vector3(-5.0, 0.0, 22.0) * sin(_reaction_clock * 0.75)


func _create_underwater_light(map: EmberMapLoader) -> void:
	if _ground_material == null or _shaft_volume != null:
		return
	if _terrain == null:
		_terrain = map.compact_terrain as EmberTerrainPilotResource
	if _environment == null:
		_environment = (map.get_node("Look/WorldEnvironment") as WorldEnvironment).environment
	var sun := map.get_node("Look/Sun") as DirectionalLight3D
	var ray := -sun.global_transform.basis.z
	var offset := Vector2(ray.x, ray.z) / maxf(absf(ray.y), 0.2)
	_ground_material.set_shader_parameter("caustic_water_level", _water_height)
	_ground_material.set_shader_parameter("caustic_sun_offset", offset)
	if _water_regions != null: _water_regions.set_ground_parameter("caustic_sun_offset", offset)
	_shaft_material = ShaderMaterial.new()
	_shaft_material.shader = load("res://shaders/ember_compact_underwater_light_study.gdshader")
	_shaft_material.set_shader_parameter("caustic_water_level", _water_height)
	_shaft_material.set_shader_parameter("caustic_sun_offset", offset)
	if _water_regions != null: _water_regions.set_ground_parameter("caustic_sun_offset", offset)
	_shaft_volume = FogVolume.new()
	_shaft_volume.name = "UnderwaterLightStudy"
	_shaft_volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	_shaft_volume.size = Vector3(float(_terrain.width), 80.0, float(_terrain.depth))
	_shaft_volume.position = Vector3(float(_terrain.width) * 0.5,
		_water_height - 40.0, float(_terrain.depth) * 0.5)
	_shaft_volume.material = _shaft_material
	_shaft_volume.visible = false
	map.add_child(_shaft_volume)
	_environment.volumetric_fog_density = 0.0


var _last_sun_ray := Vector3(INF, INF, INF)

func _sync_sun_direction() -> void:
	var sun := get_parent().get_node_or_null("Map/Look/Sun") as DirectionalLight3D
	if sun == null: return
	var ray := -sun.global_basis.z
	if ray.is_equal_approx(_last_sun_ray): return
	_last_sun_ray = ray
	var offset := Vector2(ray.x, ray.z) / maxf(absf(ray.y), 0.2)
	for material in [_ground_material, _shaft_material]:
		if material != null: material.set_shader_parameter("caustic_sun_offset", offset)
	if _water_regions != null: _water_regions.set_ground_parameter("caustic_sun_offset", offset)


func _bind_waterfall(projection: EmberTerrainPilotProjection) -> void:
	var available := _waterfall != null and _waterfall.state_texture != null
	_material.set_shader_parameter("waterfall_available", 1.0 if available else 0.0)
	if is_instance_valid(_waterfall_button): _waterfall_button.visible = available
	if not available: return
	if not _waterfall_controls_initialized and not _water_group_toggles.is_empty():
		for group in _water_group_toggles: _water_group_toggles[group].button_pressed = group == "Водопад"
		_waterfall_controls_initialized = true
	var center: Vector2 = _waterfall.info.center
	_material.set_shader_parameter("waterfall_source", Vector4(center.x + projection.global_position.x,
		center.y + projection.global_position.z, float(_waterfall.info.top) + projection.global_position.y,
		float(_waterfall.info.bottom) + projection.global_position.y))
	_material.set_shader_parameter("waterfall_direction", _waterfall.info.direction)
	_material.set_shader_parameter("waterfall_width", _waterfall.info.width)
	_material.set_shader_parameter("waterfall_origin", Vector2(projection.global_position.x, projection.global_position.z) + Vector2(_waterfall.bounds.position))
	_material.set_shader_parameter("waterfall_extent", Vector2(_waterfall.bounds.size))
	_material.set_shader_parameter("waterfall_state", _waterfall.state_texture)
	_waterfall_update_ms = 0
	_refresh_waterfall()


func _refresh_waterfall() -> void:
	if _waterfall == null or _waterfall.state_texture == null or _material == null: return
	var now := Time.get_ticks_msec()
	var fixed_time: float = _material.get_shader_parameter("preview_time")
	if fixed_time < 0.0 and now < _waterfall_update_ms: return
	_waterfall_update_ms = now + 50
	_waterfall.advance(fixed_time if fixed_time >= 0.0 else float(now) / 1000.0,
		waterfall_strength, waterfall_speed, waterfall_foam_strength)


func _refresh_sea_swash() -> void:
	if _sea_swash == null or _material == null: return
	var now := Time.get_ticks_msec()
	var fixed_time: float = _material.get_shader_parameter("preview_time")
	if fixed_time < 0.0 and now < _sea_update_ms: return
	_sea_update_ms = now + 50
	var simulation_time := fixed_time if fixed_time >= 0.0 else float(now) / 1000.0
	_refresh_region_activity(fixed_time)
	_sea_swash.advance(simulation_time,
		sea_swash_height, sea_swash_period, sea_swash_reach, water_level_offset_voxels, sand_drying_seconds,
		sea_approach_distance, sea_approach_strength)
	_material.set_shader_parameter("sea_swash_time", simulation_time)
	if _water_regions != null: _water_regions.set_water_parameter("sea_swash_time", simulation_time)


func _refresh_region_activity(fixed_time: float) -> void:
	if _water_regions == null: return
	if Engine.is_editor_hint() or fixed_time >= 0.0:
		_water_regions.set_runtime_activity(false)
		return
	var map := water_settings_map()
	var projection := map.get("_visual_surface_projection") as EmberTerrainPilotProjection if is_instance_valid(map) else null
	var observers := PackedVector2Array()
	if projection != null:
		var camera := get_viewport().get_camera_3d()
		var player := get_parent().get_node_or_null("Player") as Node3D
		for observer in [camera, player]:
			if not is_instance_valid(observer): continue
			var point := projection.to_local(observer.global_position)
			observers.append(Vector2(point.x, point.z))
		# Convert world metres conservatively for scaled/rotated terrain instances.
		var metres_per_cell := minf(projection.global_basis.x.length(), projection.global_basis.z.length())
		var metre_world := map.imported_tile_size * minf(map.global_basis.x.length(), map.global_basis.z.length())
		_water_regions.set_runtime_activity(runtime_water_activity_enabled, observers,
			48.0 * metre_world / maxf(metres_per_cell, 0.0001), 8.0 * metre_world / maxf(metres_per_cell, 0.0001))
	else:
		_water_regions.set_runtime_activity(false)


func _refresh_wave_obstacles() -> void:
	if _material == null or _terrain == null: return
	var map := water_settings_map()
	var projection := map.get("_visual_surface_projection") as EmberTerrainPilotProjection if is_instance_valid(map) else null
	if projection == null: return
	if obstacle_wave_mode == 0 or obstacle_wave_strength <= 0.001:
		_material.set_shader_parameter("obstacle_patch_count", 0)
		if _water_regions != null: _water_regions.set_water_parameter("obstacle_patch_count", 0)
		if _wave_obstacles != null:
			_wave_obstacles.advance(_wave_obstacles.current_time, 0, obstacle_wave_strength)
		if is_instance_valid(_obstacle_status): _obstacle_status.text = "Обтекание выключено"
		return
	var now := Time.get_ticks_msec()
	if now >= _obstacle_poll_ms:
		_obstacle_poll_ms = now + 250
		var shapes: Array[Dictionary] = []
		for contact in _surface_contacts:
			if not is_instance_valid(contact): continue
			var shape := contact.foam_footprint_shape(_water_height)
			if shape.is_empty(): continue
			shape.center -= Vector2(projection.global_position.x, projection.global_position.z)
			shapes.append(shape)
		var settings := {"wave_speed": float(_material.get_shader_parameter("wave_speed")),
			"river_speed": river_flow_speed, "wave_height": wave_height_voxels, "river_mix": river_wave_mix,
			"spacing": river_wave_spacing_blocks, "opening": river_arc_opening,
			"sea_period": sea_swash_period, "sea_height": sea_swash_height, "sea_reach": sea_swash_reach,
			"sea_approach": sea_approach_distance, "sea_approach_strength": sea_approach_strength,
			"offset": water_level_offset_voxels}
		var next_signature := hash([shapes, settings, _field_revision])
		var shape_signature := hash(shapes)
		var settings_signature := hash(settings)
		_obstacle_runtime_motion = (not Engine.is_editor_hint() and _wave_obstacles != null
			and shape_signature != _obstacle_shapes_signature and settings_signature == _obstacle_settings_signature)
		# The comparison concerns fixed obstacles. The moving-stone demonstration
		# retains its existing wake rather than rebuilding a cache every frame.
		if not _reaction_preview and not _obstacle_runtime_motion and (_wave_obstacles == null or next_signature != _obstacle_signature):
			_wave_obstacles = preload("res://scripts/prototypes/ember_compact_wave_obstacles.gd").new()
			_wave_obstacles.build(_terrain, shapes, _phase_texture.get_image() if _phase_texture != null else null,
				_shore_texture.get_image() if _shore_texture != null else null, _sea_swash, settings)
			_obstacle_signature = next_signature
			_obstacle_shapes_signature = shape_signature
			_obstacle_settings_signature = settings_signature
			projection.set_wave_obstacles(_wave_obstacles)
	if _wave_obstacles == null: return
	_wave_obstacles.prepare(3000)
	var fixed_time: float = _material.get_shader_parameter("preview_time")
	_wave_obstacles.advance(fixed_time if fixed_time >= 0.0 else float(now) / 1000.0,
		0 if _reaction_preview or _obstacle_runtime_motion else obstacle_wave_mode, obstacle_wave_strength,
		_sea_swash._last_time if _sea_swash != null else -1.0)
	_wave_obstacles.bind(_material, Vector2(projection.global_position.x, projection.global_position.z))
	if _water_regions != null:
		for key in ["obstacle_patch_count", "obstacle_bounds", "obstacle_details", "obstacle_baked_field", "obstacle_live_field", "obstacle_mode", "obstacle_strength", "obstacle_time"]:
			_water_regions.set_water_parameter(key, _material.get_shader_parameter(key))
	if is_instance_valid(_obstacle_status):
		_obstacle_status.text = ("Обтекание: только неподвижные объекты" if _reaction_preview or _obstacle_runtime_motion
			else "Подготовка обтекания…" if not _wave_obstacles.ready else "Нет погружённых препятствий" if _wave_obstacles.patches.is_empty()
			else "Запечённый цикл · расчёт волн отключён" if obstacle_wave_mode == 1
			else "Живая симуляция · расчёт %.2f мс" % (float(_wave_obstacles.update_us) / 1000.0))


func _apply_parameters() -> void:
	if _material == null:
		return
	_water_height = _base_water_height + water_level_offset_voxels
	var map := water_settings_map()
	var projection := map.get("_visual_surface_projection") as EmberTerrainPilotProjection if is_instance_valid(map) else null
	if projection != null:
		projection.set_water_surface_offset(water_level_offset_voxels)
	_material.set_shader_parameter("water_level_world", _water_height)
	_material.set_shader_parameter("sea_swash_strength", sea_swash_height)
	_material.set_shader_parameter("sea_swash_period", sea_swash_period)
	for key in ["sea_foam_strength", "sea_foam_trail_strength", "sea_foam_trail_lifetime"]:
		_material.set_shader_parameter(key, get(key))
	_sea_update_ms = 0
	_waterfall_update_ms = 0
	_obstacle_poll_ms = 0
	if _ground_material != null:
		_ground_material.set_shader_parameter("caustic_water_level", _water_height)
		_ground_material.set_shader_parameter("sand_wet_strength", sand_wet_strength)
	if _shaft_material != null:
		_shaft_material.set_shader_parameter("caustic_water_level", _water_height)
	if _shaft_volume != null:
		_shaft_volume.position.y = _water_height - 40.0
	if _viewport != null:
		_viewport.size = _reflection_size()
		_viewport.render_target_update_mode = (SubViewport.UPDATE_ALWAYS
			if scene_reflection > 0.0 else SubViewport.UPDATE_DISABLED)
	_material.set_shader_parameter("planar_reflection_mix", 0.0 if Engine.is_editor_hint() else scene_reflection)
	_material.set_shader_parameter("planar_reflection_distortion", reflection_distortion)
	_material.set_shader_parameter("sky_reflection_roughness", sky_roughness)
	_material.set_shader_parameter("sky_reflection_strength", sky_reflection)
	_material.set_shader_parameter("wave_height_voxels", wave_height_voxels)
	_material.set_shader_parameter("river_flow_speed", river_flow_speed)
	_material.set_shader_parameter("river_wave_mix", river_wave_mix)
	_material.set_shader_parameter("shore_foam_strength", shore_foam_strength)
	_material.set_shader_parameter("shore_foam_width_voxels", shore_foam_width_voxels)
	_material.set_shader_parameter("shore_foam_sharpness", shore_foam_sharpness)
	_material.set_shader_parameter("shore_foam_motion_voxels", shore_foam_motion_voxels)
	_material.set_shader_parameter("river_crest_whiteness", river_crest_whiteness)
	_material.set_shader_parameter("object_foam_strength", object_foam_strength)
	for key in ["object_foam_width_voxels", "object_foam_sharpness", "river_wave_spacing_blocks",
		"river_arc_opening", "river_crest_width_voxels", "river_crest_sharpness", "reaction_strength",
		"reaction_spread_speed", "reaction_opening", "reaction_birth_seconds", "river_foam_variation",
		"water_glint_strength", "ripple_cell_scale", "ripple_morph_strength", "ripple_morph_speed", "foam_trail_strength", "foam_trail_lifetime", "shore_foam_breakup", "foam_width_pulse",
		"water_detail_begin_m", "water_detail_end_m"]:
		_material.set_shader_parameter(key, get(key))
	for key in ["waterfall_strength", "waterfall_speed", "waterfall_irregularity", "waterfall_foam_strength"]:
		_material.set_shader_parameter(key, get(key))
	_material.set_shader_parameter("local_bob_strength", local_bob_strength)
	_material.set_shader_parameter("refraction_strength", refraction_strength)
	if _ground_material != null:
		_ground_material.set_shader_parameter("local_bob_strength", local_bob_strength)
		_ground_material.set_shader_parameter("water_wave_height_voxels", wave_height_voxels)
		_ground_material.set_shader_parameter("underwater_caustics",
			underwater_caustics if _shaft_volume != null and _shaft_volume.visible else 0.0)
	if _shaft_material != null:
		_shaft_material.set_shader_parameter("local_bob_strength", local_bob_strength)
		_shaft_material.set_shader_parameter("ray_strength", underwater_shafts)
	if _environment != null and _shaft_volume != null:
		_environment.volumetric_fog_enabled = _shaft_volume.visible and underwater_shafts > 0.001
	_sync_region_parameters()
	_parameter_signature = _current_parameter_signature()


func _sync_region_parameters() -> void:
	if _water_regions == null or _material == null: return
	var map := water_settings_map()
	var projection := map.get("_visual_surface_projection") as EmberTerrainPilotProjection if map != null else null
	if projection != null: _water_regions.bind(_material, _ground_material, Vector2(projection.global_position.x, projection.global_position.z))


func _create_controls() -> void:
	var canvas := get_parent().get_node_or_null("CanvasLayer") as CanvasLayer
	if canvas == null:
		return
	var panel := PanelContainer.new()
	panel.name = "ReflectionControls"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -420.0
	panel.offset_right = -12.0
	panel.offset_top = -680.0
	panel.offset_bottom = -12.0
	canvas.add_child(panel)
	var rows := VBoxContainer.new()
	panel.add_child(rows)
	var title := Label.new()
	title.text = "Проба воды · RMB вращать · колесо масштаб"
	rows.add_child(title)
	_apply_button = Button.new()
	_apply_button.text = "Применить в редактор"
	_apply_button.disabled = not EngineDebugger.is_active()
	_apply_button.pressed.connect(_apply_in_editor)
	rows.add_child(_apply_button)
	_apply_status = Label.new()
	_apply_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_status.text = "Изменения F6 временные, пока не применены." if EngineDebugger.is_active() else "Перенос доступен при запуске F6 из редактора."
	rows.add_child(_apply_status)
	_camera_button = Button.new()
	_camera_button.text = "Камера: вода (переключить)"
	_camera_button.pressed.connect(_toggle_camera)
	rows.add_child(_camera_button)
	_dive_button = Button.new()
	_dive_button.text = "Под воду (переключить)"
	_dive_button.pressed.connect(_toggle_underwater_view)
	rows.add_child(_dive_button)
	_river_button = Button.new()
	_river_button.name = "RiverViewButton"
	_river_button.text = "К морю"
	_river_button.pressed.connect(_toggle_river_view)
	rows.add_child(_river_button)
	_waterfall_button = Button.new()
	_waterfall_button.name = "WaterfallViewButton"
	_waterfall_button.text = "К водопаду"
	_waterfall_button.visible = false
	_waterfall_button.pressed.connect(_show_waterfall)
	rows.add_child(_waterfall_button)
	var reaction_button := Button.new()
	reaction_button.text = "Проба следа: двигать камень"
	reaction_button.visible = get_parent().get_node_or_null("Map/Props/WaterContactStone") != null
	reaction_button.pressed.connect(_toggle_reaction_preview)
	rows.add_child(reaction_button)
	_obstacle_status = Label.new()
	_obstacle_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_obstacle_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(scroll)
	var water_rows := VBoxContainer.new()
	water_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(water_rows)
	var groups: Dictionary = {}
	var sun := get_parent().get_node_or_null("Map/Look/Sun") as DirectionalLight3D
	if sun != null:
		var light_toggle := Button.new()
		light_toggle.text = "Солнце и свет ▸"
		light_toggle.toggle_mode = true
		water_rows.add_child(light_toggle)
		var light_rows := VBoxContainer.new()
		light_rows.visible = false
		water_rows.add_child(light_rows)
		light_toggle.toggled.connect(func(open: bool): light_rows.visible = open; light_toggle.text = "Солнце и свет" + (" ▾" if open else " ▸"))
		for key in EmberLights.SUN_LOOK_VALUES:
			var spec: Array = EmberLights.SUN_LOOK_VALUES[key]
			var property: String = spec[1]
			var minimum := float(spec[2])
			var span := float(spec[3]) - minimum
			_add_slider(light_rows, spec[0], (EmberLights.sun_look_value(sun, property) - minimum) / span,
				func(value: float): EmberLights.apply_sun_look_value(sun, property, minimum + value * span), minimum, span, float(spec[4]) / span)
	for key in WATER_VALUES:
		var spec: Array = WATER_VALUES[key]
		var group: String = spec[4]
		if not groups.has(group):
			var toggle := Button.new()
			toggle.text = group + " ▾"
			toggle.toggle_mode = true
			toggle.button_pressed = true
			_water_group_toggles[group] = toggle
			water_rows.add_child(toggle)
			var body := VBoxContainer.new()
			water_rows.add_child(body)
			toggle.toggled.connect(func(open: bool): body.visible = open; toggle.text = group + (" ▾" if open else " ▸"))
			groups[group] = body
		var minimum := float(spec[1])
		var span := float(spec[2]) - minimum
		if spec.size() > 5:
			var caption := Label.new()
			caption.text = str(spec[0])
			groups[group].add_child(caption)
			var choice := OptionButton.new()
			choice.name = key
			for item in spec[5]: choice.add_item(str(item))
			choice.select(int(get(key)))
			choice.item_selected.connect(func(index: int): set(key, index); _apply_parameters())
			groups[group].add_child(choice)
			continue
		_add_slider(groups[group], spec[0], (float(get(key)) - minimum) / span,
			func(value: float): set(key, clampf(minimum + value * span, minimum, minimum + span)); _apply_parameters(),
			minimum, span, float(spec[3]) / span)



func _add_slider(rows: VBoxContainer, caption: String, value: float,
		callback: Callable, display_offset := 0.0, display_scale := 1.0, normalized_step := 0.01) -> void:
	var row := HBoxContainer.new()
	rows.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 170.0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = normalized_step
	slider.custom_minimum_size.x = 130.0
	slider.value = value
	slider.value_changed.connect(callback)
	row.add_child(slider)
	var readout := Label.new()
	readout.custom_minimum_size.x = 52.0
	var number_format := "%.4f" if display_scale < 0.03 else "%.3f" if display_scale < 0.2 else "%.2f"
	readout.text = number_format % (value * display_scale + display_offset)
	row.add_child(readout)
	slider.value_changed.connect(func(next_value: float) -> void:
		readout.text = number_format % (next_value * display_scale + display_offset))
