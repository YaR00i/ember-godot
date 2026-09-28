@tool
extends Node3D
## Playable disposable editor for the compact terrain pilot. The projection
## node itself is identical in Godot's editor viewport and in this scene.

const PilotProjection = preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const BrushMath = preload("res://scripts/prototypes/ember_terrain_pilot_brush_math.gd")
const CELLS_PER_BLOCK := 16
const MAX_BRUSH_RADIUS_BLOCKS := 8.0

@export var terrain_source: TerrainResource
@export var draft_path := "user://ember_terrain_pilot_draft.res"
@export_range(0.0625, 8.0, 0.0625) var brush_radius_blocks := 0.3125
@export_range(1, 32, 1) var brush_depth_voxels := 4
@export_range(4, 64, 1) var relief_feature_scale := 16
@export_range(0, 5, 1) var relief_detail := 0
@export var relief_seed := 371
@export_range(-1, 1, 1) var relief_direction := 0
@export var plateau_from_point := true
@export var plateau_target_world := 0
var projection: Node3D
var _camera: Camera3D
var _help: Label
var _brush_spin: SpinBox
var _tool_choice: OptionButton
var _depth_row: Control
var _plateau_row: Control
var _generator_row: Control
var _depth_spin: SpinBox
var _height_spin: SpinBox
var _sample_height_check: CheckBox
var _scale_spin: SpinBox
var _detail_spin: SpinBox
var _seed_spin: SpinBox
var _direction_choice: OptionButton
var _brush_cursor: MeshInstance3D
var _brush_cursor_mesh: ImmediateMesh
var _brush_cursor_material: StandardMaterial3D
var _hover_cell := Vector2i(-1, -1)
var _undo := UndoRedo.new()
var _stroke_mode := 0
var _stroke_indices := PackedInt32Array()
var _stroke_touched := PackedByteArray()
var _stroke_baseline_heights := PackedInt32Array()
var _stroke_baseline_tops := PackedByteArray()
var _stroke_baseline_waters := PackedInt32Array()
var _stroke_baseline_water_colors := PackedByteArray()
var _stroke_influence := PackedInt32Array()
var _stroke_target_height := -1
var _stroke_noise: FastNoiseLite
var _last_stamp_cell := Vector2i(-1, -1)
var _orbiting := false
var _yaw := 0.35
var _pitch := 0.9
var _distance := 490.0
var _status := ""


func _ready() -> void:
	_camera = get_node_or_null("Camera3D") as Camera3D
	projection = PilotProjection.new()
	projection.name = "TerrainProjection"
	projection.source = terrain_source
	add_child(projection)
	if _camera != null and terrain_source != null:
		_update_camera()
	if not Engine.is_editor_hint():
		_make_help()
		_make_brush_cursor()
		_update_help()


func _exit_tree() -> void:
	_undo.clear_history()
	_undo.free()


func _process(_delta: float) -> void:
	if _help != null:
		_update_help()


func begin_stroke(mode: int) -> void:
	if projection == null or projection.get("document") == null or mode < 1 or mode > 11:
		return
	if _stroke_mode != 0:
		end_stroke()
	_stroke_mode = mode
	_last_stamp_cell = Vector2i(-1, -1)
	var document: TerrainResource = projection.get("document")
	_stroke_indices = PackedInt32Array()
	_stroke_touched = PackedByteArray()
	_stroke_touched.resize(document.heights.size())
	_stroke_influence = PackedInt32Array()
	if mode in [7, 8, 10]:
		_stroke_influence.resize(document.heights.size())
	_stroke_target_height = -1
	_stroke_baseline_heights = document.heights.duplicate()
	_stroke_baseline_tops = document.top_materials.duplicate()
	_stroke_baseline_waters = document.water_levels.duplicate()
	_stroke_baseline_water_colors = document.water_materials.duplicate()
	_stroke_noise = null
	if mode == 9:
		if not plateau_from_point:
			_stroke_target_height = clampi(plateau_target_world - document.origin_y, 1, document.height_limit)
	if mode == 10:
		_stroke_noise = FastNoiseLite.new()
		_stroke_noise.seed = maxi(0, relief_seed)
		_stroke_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_stroke_noise.frequency = 1.0 / float(clampi(relief_feature_scale, 4, 64))
		_stroke_noise.fractal_type = FastNoiseLite.FRACTAL_FBM if relief_detail > 0 else FastNoiseLite.FRACTAL_NONE
		_stroke_noise.fractal_octaves = clampi(relief_detail, 1, 5)
		_stroke_noise.fractal_gain = 0.5
		_stroke_noise.fractal_lacunarity = 2.0


func set_brush_radius_blocks(value: float) -> void:
	var next_radius := float(clampi(roundi(value * CELLS_PER_BLOCK), 1, int(MAX_BRUSH_RADIUS_BLOCKS * CELLS_PER_BLOCK))) / CELLS_PER_BLOCK
	if is_equal_approx(brush_radius_blocks, next_radius):
		return
	if _stroke_mode != 0:
		cancel_stroke()
	brush_radius_blocks = next_radius
	if _brush_spin != null:
		_brush_spin.set_value_no_signal(next_radius)
	_draw_brush_cursor()
	if _help != null:
		_update_help()


func brush_radius_cells() -> int:
	return clampi(roundi(brush_radius_blocks * CELLS_PER_BLOCK), 1, int(MAX_BRUSH_RADIUS_BLOCKS * CELLS_PER_BLOCK))


func stamp_cell(x: int, z: int) -> void:
	if _stroke_mode == 0:
		return
	var current := Vector2i(x, z)
	if _last_stamp_cell.x < 0:
		_stamp_point(x, z)
	else:
		var spacing := maxf(1.0, float(brush_radius_cells()) * 0.5)
		var steps := maxi(1, ceili(Vector2(_last_stamp_cell).distance_to(Vector2(current)) / spacing))
		for step in range(1, steps + 1):
			var point := Vector2(_last_stamp_cell).lerp(Vector2(current), float(step) / float(steps))
			_stamp_point(roundi(point.x), roundi(point.y))
	_last_stamp_cell = current


func _stamp_point(x: int, z: int) -> void:
	var document: TerrainResource = projection.get("document")
	if x < 0 or z < 0 or x >= document.width or z >= document.depth:
		return
	if _stroke_mode == 9 and _stroke_target_height < 0:
		_stroke_target_height = document.heights[document.column_index(x, z)]
		plateau_target_world = document.origin_y + _stroke_target_height
		if _height_spin != null:
			_height_spin.set_value_no_signal(plateau_target_world)
	var indices := PackedInt32Array()
	var heights := PackedInt32Array()
	var tops := PackedByteArray()
	var waters := PackedInt32Array()
	var water_colors := PackedByteArray()
	var radius := brush_radius_cells()
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dz * dz > radius * radius:
				continue
			var px := x + dx
			var pz := z + dz
			if px < 0 or pz < 0 or px >= document.width or pz >= document.depth:
				continue
			var index := document.column_index(px, pz)
			if _stroke_touched[index] != 0 and _stroke_mode not in [7, 8, 10]:
				continue
			var prior := Vector4i(document.heights[index], document.top_materials[index], document.water_levels[index], document.water_materials[index])
			var next := prior
			match _stroke_mode:
				1: next.x = mini(document.height_limit, next.x + 1)
				2: next.x = maxi(1, next.x - 1)
				3: next.y = 2
				4: next.y = 3
				5:
					next.z = 32
					next.w = 5
				6:
					next.z = 0
					next.w = 0
				7, 8:
					var influence: float = BrushMath.falloff(dx, dz, radius)
					var amount: int = BrushMath.relief_amount(influence, brush_depth_voxels)
					if amount <= _stroke_influence[index]:
						continue
					_stroke_influence[index] = amount
					var baseline_height: int = _stroke_baseline_heights[index]
					next.x = clampi(baseline_height + (amount if _stroke_mode == 7 else -amount), 1, document.height_limit)
				9: next.x = _stroke_target_height
				10:
					var influence: float = BrushMath.falloff(dx, dz, radius)
					var strength := roundi(influence * 4096.0)
					if strength <= _stroke_influence[index]:
						continue
					_stroke_influence[index] = strength
					var offset: int = BrushMath.noise_offset(_stroke_noise, px, pz, influence, brush_depth_voxels, relief_detail, relief_direction)
					next.x = clampi(_stroke_baseline_heights[index] + offset, 1, document.height_limit)
				11:
					var influence: float = BrushMath.falloff(dx, dz, radius)
					next.x = clampi(BrushMath.smooth_height(_stroke_baseline_heights, document.width, document.depth, px, pz, brush_depth_voxels, influence), 1, document.height_limit)
			if next == prior:
				continue
			if _stroke_touched[index] == 0:
				_stroke_touched[index] = 1
				_stroke_indices.append(index)
			indices.append(index)
			heights.append(next.x)
			tops.append(next.y)
			waters.append(next.z)
			water_colors.append(next.w)
	if not indices.is_empty():
		projection.set("camera_anchor", Vector2i(x, z))
		projection.call("apply_columns", indices, heights, tops, waters, water_colors)
		_draw_brush_cursor()


func end_stroke() -> void:
	if _stroke_mode == 0:
		return
	_stroke_mode = 0
	if _stroke_indices.is_empty():
		_clear_stroke_plan()
		return
	var document: TerrainResource = projection.get("document")
	var indices := _stroke_indices.duplicate()
	var before_heights := PackedInt32Array()
	var before_tops := PackedByteArray()
	var before_waters := PackedInt32Array()
	var before_water_colors := PackedByteArray()
	var after_heights := PackedInt32Array()
	var after_tops := PackedByteArray()
	var after_waters := PackedInt32Array()
	var after_water_colors := PackedByteArray()
	for index in indices:
		before_heights.append(_stroke_baseline_heights[index])
		before_tops.append(_stroke_baseline_tops[index])
		before_waters.append(_stroke_baseline_waters[index])
		before_water_colors.append(_stroke_baseline_water_colors[index])
		after_heights.append(document.heights[index])
		after_tops.append(document.top_materials[index])
		after_waters.append(document.water_levels[index])
		after_water_colors.append(document.water_materials[index])
	_undo.create_action("Terrain pilot stroke")
	_undo.add_do_method(Callable(projection, "apply_columns").bind(indices, after_heights, after_tops, after_waters, after_water_colors))
	_undo.add_undo_method(Callable(projection, "apply_columns").bind(indices, before_heights, before_tops, before_waters, before_water_colors))
	_undo.commit_action(false)
	_status = "Мазок: %d колонок" % indices.size()
	_clear_stroke_plan()


func cancel_stroke() -> void:
	if _stroke_mode == 0:
		return
	_stroke_mode = 0
	if _stroke_indices.is_empty():
		_clear_stroke_plan()
		return
	var indices := _stroke_indices.duplicate()
	var heights := PackedInt32Array()
	var tops := PackedByteArray()
	var waters := PackedInt32Array()
	var water_colors := PackedByteArray()
	for index in indices:
		heights.append(_stroke_baseline_heights[index])
		tops.append(_stroke_baseline_tops[index])
		waters.append(_stroke_baseline_waters[index])
		water_colors.append(_stroke_baseline_water_colors[index])
	projection.call("apply_columns", indices, heights, tops, waters, water_colors)
	_clear_stroke_plan()
	_draw_brush_cursor()
	_status = "Мазок отменён"


func _clear_stroke_plan() -> void:
	_last_stamp_cell = Vector2i(-1, -1)
	_stroke_indices = PackedInt32Array()
	_stroke_touched = PackedByteArray()
	_stroke_baseline_heights = PackedInt32Array()
	_stroke_baseline_tops = PackedByteArray()
	_stroke_baseline_waters = PackedInt32Array()
	_stroke_baseline_water_colors = PackedByteArray()
	_stroke_influence = PackedInt32Array()
	_stroke_target_height = -1
	_stroke_noise = null


func undo_stroke() -> void:
	if _stroke_mode == 0 and _undo.has_undo():
		_undo.undo()
		_draw_brush_cursor()
		_status = "Отмена"


func redo_stroke() -> void:
	if _stroke_mode == 0 and _undo.has_redo():
		_undo.redo()
		_draw_brush_cursor()
		_status = "Повтор"


func save_draft() -> Error:
	if _stroke_mode != 0:
		end_stroke()
	var result: Error = projection.call("save_document", draft_path)
	_status = "Черновик сохранён" if result == OK else "Ошибка сохранения: %d" % result
	return result


func reopen_draft() -> bool:
	if _stroke_mode != 0:
		cancel_stroke()
	var path := draft_path if FileAccess.file_exists(draft_path) else terrain_source.resource_path
	var opened: bool = projection.call("reopen_document", path)
	if opened:
		_undo.clear_history()
		_draw_brush_cursor()
	_status = "Черновик открыт" if opened else "Ошибка открытия"
	return opened


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or _camera == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_Z:
			undo_stroke()
		elif event.ctrl_pressed and event.keycode == KEY_Y:
			redo_stroke()
		elif event.ctrl_pressed and event.keycode == KEY_S:
			save_draft()
		elif event.keycode == KEY_R:
			reopen_draft()
		elif event.keycode == KEY_ESCAPE:
			cancel_stroke()
		elif event.keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT]:
			set_brush_radius_blocks(brush_radius_blocks + float(-1 if event.keycode == KEY_BRACKETLEFT else 1) / CELLS_PER_BLOCK)
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_distance = maxf(40.0, _distance * 0.85)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_distance = minf(1200.0, _distance * 1.15)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				begin_stroke(_mode_from_keys())
				_stamp_screen(event.position)
			else:
				end_stroke()
	elif event is InputEventMouseMotion:
		if _orbiting:
			_yaw -= event.relative.x * 0.006
			_pitch = clampf(_pitch + event.relative.y * 0.006, 0.12, 1.45)
			_update_camera()
		elif _stroke_mode != 0:
			_stamp_screen(event.position)
		else:
			_update_brush_hover(event.position)


func _mode_from_keys() -> int:
	for key in [KEY_6, KEY_5, KEY_4, KEY_3, KEY_2]:
		if Input.is_key_pressed(key):
			return key - KEY_1 + 1
	return _tool_choice.get_selected_id() if _tool_choice != null else 1


func _stamp_screen(screen: Vector2) -> void:
	var hit := _ground_hit(screen)
	if hit.is_empty():
		return
	_set_hover_cell(hit.position)
	stamp_cell(floori(hit.position.x), floori(hit.position.z))


func _update_brush_hover(screen: Vector2) -> void:
	var hit := _ground_hit(screen)
	if hit.is_empty():
		_hover_cell = Vector2i(-1, -1)
		if _brush_cursor != null:
			_brush_cursor.hide()
		return
	_set_hover_cell(hit.position)


func _ground_hit(screen: Vector2) -> Dictionary:
	var start := _camera.project_ray_origin(screen)
	var end := start + _camera.project_ray_normal(screen) * 2000.0
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, end))


func _set_hover_cell(position: Vector3) -> void:
	var cell := Vector2i(floori(position.x), floori(position.z))
	if cell == _hover_cell:
		return
	_hover_cell = cell
	_draw_brush_cursor()


func _make_brush_cursor() -> void:
	_brush_cursor_mesh = ImmediateMesh.new()
	_brush_cursor_material = StandardMaterial3D.new()
	_brush_cursor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_brush_cursor_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_brush_cursor_material.no_depth_test = true
	_brush_cursor_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_brush_cursor_material.render_priority = 10
	_brush_cursor_material.albedo_color = Color(1.0, 0.73, 0.20, 0.9)
	_brush_cursor = MeshInstance3D.new()
	_brush_cursor.name = "BrushRadiusCursor"
	_brush_cursor.mesh = _brush_cursor_mesh
	_brush_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_brush_cursor.hide()
	add_child(_brush_cursor)


func _draw_brush_cursor() -> void:
	if _brush_cursor == null or _brush_cursor_mesh == null:
		return
	var document: TerrainResource = projection.get("document") if projection != null else null
	if document == null or _hover_cell.x < 0 or _hover_cell.y < 0:
		_brush_cursor.hide()
		return
	var radius := float(brush_radius_cells()) + 0.5
	var half_width := clampf(radius * 0.01, 0.25, 0.8)
	var segments := maxi(48, mini(160, brush_radius_cells() * 2))
	_brush_cursor_mesh.clear_surfaces()
	_brush_cursor_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _brush_cursor_material)
	for i in segments + 1:
		var angle := TAU * float(i) / float(segments)
		for edge_radius in [radius - half_width, radius + half_width]:
			var x: float = float(_hover_cell.x) + 0.5 + cos(angle) * edge_radius
			var z: float = float(_hover_cell.y) + 0.5 + sin(angle) * edge_radius
			var sample_x := clampi(floori(x), 0, document.width - 1)
			var sample_z := clampi(floori(z), 0, document.depth - 1)
			var index := document.column_index(sample_x, sample_z)
			var level := document.heights[index]
			if document.water_materials[index] > 0:
				level = maxi(level, document.water_levels[index])
			_brush_cursor_mesh.surface_add_vertex(Vector3(x, float(document.origin_y + level) + 0.35, z))
	_brush_cursor_mesh.surface_end()
	_brush_cursor.show()


func _update_camera() -> void:
	if _camera == null or terrain_source == null:
		return
	var center := Vector3(terrain_source.width * 0.5, 0, terrain_source.depth * 0.5)
	_camera.position = center + Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _distance
	_camera.look_at(center)


func _make_help() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := VBoxContainer.new()
	panel.name = "BrushControls"
	panel.position = Vector2(16, 14)
	canvas.add_child(panel)
	_help = Label.new()
	_help.add_theme_color_override("font_color", Color(1, 0.97, 0.84))
	_help.add_theme_color_override("font_shadow_color", Color(0.08, 0.12, 0.11))
	_help.add_theme_constant_override("shadow_offset_x", 2)
	_help.add_theme_constant_override("shadow_offset_y", 2)
	panel.add_child(_help)
	var tool_row := HBoxContainer.new()
	tool_row.name = "ToolRow"
	panel.add_child(tool_row)
	var tool_label := Label.new()
	tool_label.text = "Кисть"
	tool_row.add_child(tool_label)
	_tool_choice = OptionButton.new()
	_tool_choice.name = "TerrainBrush"
	_tool_choice.custom_minimum_size.x = 180
	for tool in [
		[1, "Поднять +1"], [2, "Опустить −1"], [3, "Трава"], [4, "Песок"],
		[5, "Вода"], [6, "Суша"], [7, "Рельеф ↑"], [8, "Рельеф ↓"],
		[9, "Площадка"], [10, "Неровности"], [11, "Сгладить"],
	]:
		_tool_choice.add_item(tool[1], tool[0])
	tool_row.add_child(_tool_choice)
	_tool_choice.item_selected.connect(func(_index): cancel_stroke(); _update_mode_controls())
	var row := HBoxContainer.new()
	row.name = "RadiusRow"
	panel.add_child(row)
	var label := Label.new()
	label.text = "Радиус · блоки"
	row.add_child(label)
	_brush_spin = SpinBox.new()
	_brush_spin.name = "RadiusBlocks"
	_brush_spin.min_value = 1.0 / CELLS_PER_BLOCK
	_brush_spin.max_value = MAX_BRUSH_RADIUS_BLOCKS
	_brush_spin.step = 1.0 / CELLS_PER_BLOCK
	_brush_spin.value = brush_radius_blocks
	_brush_spin.suffix = " бл."
	_brush_spin.custom_minimum_size.x = 116
	row.add_child(_brush_spin)
	_brush_spin.value_changed.connect(set_brush_radius_blocks)
	for preset in [1, 2, 4, 8]:
		var button := Button.new()
		button.name = "RadiusPreset_%d" % preset
		button.text = str(preset)
		button.tooltip_text = "Радиус %d бл. · %d ячеек" % [preset, preset * CELLS_PER_BLOCK]
		row.add_child(button)
		button.pressed.connect(func(): set_brush_radius_blocks(float(preset)))
	_depth_row = HBoxContainer.new()
	_depth_row.name = "DepthRow"
	panel.add_child(_depth_row)
	var depth_label := Label.new()
	depth_label.text = "Глубина · ячейки"
	_depth_row.add_child(depth_label)
	_depth_spin = SpinBox.new()
	_depth_spin.name = "BrushDepth"
	_depth_spin.min_value = 1
	_depth_spin.max_value = 32
	_depth_spin.step = 1
	_depth_spin.value = brush_depth_voxels
	_depth_spin.custom_minimum_size.x = 85
	_depth_row.add_child(_depth_spin)
	_depth_spin.value_changed.connect(func(value: float): cancel_stroke(); brush_depth_voxels = roundi(value))
	_plateau_row = HBoxContainer.new()
	_plateau_row.name = "PlateauRow"
	panel.add_child(_plateau_row)
	_sample_height_check = CheckBox.new()
	_sample_height_check.name = "PlateauFromPoint"
	_sample_height_check.text = "Высота по точке"
	_sample_height_check.button_pressed = plateau_from_point
	_plateau_row.add_child(_sample_height_check)
	_sample_height_check.toggled.connect(func(pressed: bool): cancel_stroke(); plateau_from_point = pressed; _height_spin.editable = not pressed)
	var height_label := Label.new()
	height_label.text = "Высота · мир"
	_plateau_row.add_child(height_label)
	_height_spin = SpinBox.new()
	_height_spin.name = "PlateauWorldHeight"
	_height_spin.min_value = terrain_source.origin_y + 1
	_height_spin.max_value = terrain_source.origin_y + terrain_source.height_limit
	_height_spin.step = 1
	_height_spin.value = plateau_target_world
	_height_spin.editable = not plateau_from_point
	_height_spin.custom_minimum_size.x = 85
	_plateau_row.add_child(_height_spin)
	_height_spin.value_changed.connect(func(value: float): cancel_stroke(); plateau_target_world = roundi(value))
	_generator_row = HBoxContainer.new()
	_generator_row.name = "GeneratorRow"
	panel.add_child(_generator_row)
	var scale_label := Label.new()
	scale_label.text = "Крупность · ячейки"
	_generator_row.add_child(scale_label)
	_scale_spin = SpinBox.new()
	_scale_spin.name = "ReliefScale"
	_scale_spin.min_value = 4
	_scale_spin.max_value = 64
	_scale_spin.step = 1
	_scale_spin.value = relief_feature_scale
	_scale_spin.custom_minimum_size.x = 70
	_generator_row.add_child(_scale_spin)
	_scale_spin.value_changed.connect(func(value: float): cancel_stroke(); relief_feature_scale = roundi(value))
	var detail_label := Label.new()
	detail_label.text = "Деталь"
	_generator_row.add_child(detail_label)
	_detail_spin = SpinBox.new()
	_detail_spin.name = "ReliefDetail"
	_detail_spin.min_value = 0
	_detail_spin.max_value = 5
	_detail_spin.step = 1
	_detail_spin.value = relief_detail
	_detail_spin.custom_minimum_size.x = 65
	_generator_row.add_child(_detail_spin)
	_detail_spin.value_changed.connect(func(value: float): cancel_stroke(); relief_detail = roundi(value))
	var seed_label := Label.new()
	seed_label.text = "Вариант"
	_generator_row.add_child(seed_label)
	_seed_spin = SpinBox.new()
	_seed_spin.name = "ReliefSeed"
	_seed_spin.min_value = 0
	_seed_spin.max_value = 1000000
	_seed_spin.step = 1
	_seed_spin.value = relief_seed
	_seed_spin.custom_minimum_size.x = 90
	_generator_row.add_child(_seed_spin)
	_seed_spin.value_changed.connect(func(value: float): cancel_stroke(); relief_seed = roundi(value))
	var next_seed := Button.new()
	next_seed.text = "Другой рисунок"
	_generator_row.add_child(next_seed)
	next_seed.pressed.connect(func(): _seed_spin.value = mini(1000000, relief_seed + 1))
	_direction_choice = OptionButton.new()
	_direction_choice.name = "ReliefDirection"
	_direction_choice.add_item("Оба", 0)
	_direction_choice.add_item("Вверх", 1)
	_direction_choice.add_item("Вниз", 2)
	_direction_choice.select(0 if relief_direction == 0 else 1 if relief_direction > 0 else 2)
	_generator_row.add_child(_direction_choice)
	_direction_choice.item_selected.connect(func(_index): cancel_stroke(); relief_direction = 0 if _direction_choice.get_selected_id() == 0 else 1 if _direction_choice.get_selected_id() == 1 else -1)
	_update_mode_controls()


func set_tool_mode(mode: int) -> void:
	if _tool_choice == null:
		return
	for item in _tool_choice.item_count:
		if _tool_choice.get_item_id(item) == mode:
			cancel_stroke()
			_tool_choice.select(item)
			_update_mode_controls()
			return


func _update_mode_controls() -> void:
	if _tool_choice == null:
		return
	var mode := _tool_choice.get_selected_id()
	_depth_row.visible = mode in [7, 8, 10, 11]
	_plateau_row.visible = mode == 9
	_generator_row.visible = mode == 10
	if _help != null:
		_update_help()


func _update_help() -> void:
	_help.text = "Проверка новой земли · ЛКМ выбранная кисть · удерживать 2–6 для старых режимов\nПКМ повернуть · колесо приблизить · [ / ] радиус · Ctrl+Z/Y отмена/повтор · Ctrl+S черновик · R открыть · Esc отменить мазок\nКисть: %d ячеек радиус · участки: %d готово / %d в очереди. %s" % [brush_radius_cells(), projection.call("built_tile_count"), projection.call("pending_tile_count"), _status]
