@tool
class_name EmberWorldSurfaceSelector
extends RefCounted
## Editor-only rectangle selector for a map-owned voxel Surface. Selection is a
## transient editing scope; it never creates or serializes a patch Resource.

const INVALID_CELL := Vector2i(-9999, -9999)

signal surface_edit_requested(map: EmberMapLoader, region_blocks: Rect2i)

var _plugin: EditorPlugin
var _editor_interface: EditorInterface
var _toolbar: HBoxContainer
var _select_button: Button
var _open_button: Button
var _more_menu: MenuButton
var _status: Label
var _map: EmberMapLoader
var _camera: Camera3D
var _grid := {}
var _anchor := INVALID_CELL
var _hover := INVALID_CELL
var _region := Rect2i()
var _dragging := false
var _press_position := Vector2.ZERO


func configure(plugin: EditorPlugin, editor_interface: EditorInterface) -> void:
	_plugin = plugin
	_editor_interface = editor_interface


func build_toolbar() -> Control:
	_toolbar = HBoxContainer.new()
	_toolbar.name = "EmberWorldSurfaceToolbar"
	_toolbar.tooltip_text = "Выделение части общей voxel-поверхности открытой Ember-карты."

	_select_button = Button.new()
	_select_button.name = "WorldSurfaceRegionToggle"
	_select_button.text = "Выделить участок"
	_select_button.toggle_mode = true
	_select_button.tooltip_text = (
		"Протяните ЛКМ по карте или укажите два угла отдельными кликами. "
		+ "Esc отменяет выбор."
	)
	_select_button.toggled.connect(_on_select_toggled)
	_toolbar.add_child(_select_button)

	_open_button = Button.new()
	_open_button.name = "WorldSurfaceOpenRegionButton"
	_open_button.text = "Открыть область"
	_open_button.tooltip_text = "Открыть выделенный прямоугольник общей Surface без копирования данных."
	_open_button.pressed.connect(_open_region)
	_toolbar.add_child(_open_button)

	_more_menu = MenuButton.new()
	_more_menu.name = "WorldSurfaceMoreMenu"
	_more_menu.text = "Ещё…"
	_more_menu.tooltip_text = "Операции со всей художественной Surface карты."
	_more_menu.get_popup().add_item("Открыть всю карту", 0)
	_more_menu.get_popup().id_pressed.connect(_on_toolbar_action)
	_toolbar.add_child(_more_menu)

	_status = Label.new()
	_status.name = "WorldSurfaceSelectionStatus"
	_status.custom_minimum_size.x = 128.0
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_toolbar.add_child(_status)
	refresh_context()
	return _toolbar


func shutdown() -> void:
	_map = null
	_camera = null
	_grid.clear()
	_plugin = null
	_editor_interface = null


func refresh_context() -> void:
	var next_map := _resolve_map()
	if next_map != _map:
		_map = next_map
		_anchor = INVALID_CELL
		_hover = INVALID_CELL
		_region = Rect2i()
		_dragging = false
		_grid = _surface_grid_for_map(_map)
	var valid := is_instance_valid(_map) and _grid_width() > 0 and _grid_depth() > 0
	if is_instance_valid(_toolbar):
		_toolbar.visible = valid
	if is_instance_valid(_select_button):
		_select_button.disabled = not valid
		if not valid:
			_select_button.set_pressed_no_signal(false)
	if is_instance_valid(_open_button):
		_open_button.disabled = not valid or not _region.has_area()
	if is_instance_valid(_more_menu):
		_more_menu.disabled = not valid
	_set_status(
		"Карта %s · %d×%d" % [_map.map_id, _grid_width(), _grid_depth()]
		if valid
		else "Откройте обычную Ember-карту"
	)
	_request_overlay()


func forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if not is_instance_valid(_select_button) or not _select_button.button_pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if not is_instance_valid(_map):
		refresh_context()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	_camera = viewport_camera
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_anchor = INVALID_CELL
		_hover = INVALID_CELL
		_dragging = false
		_select_button.set_pressed_no_signal(false)
		_set_status("Выделение отменено")
		_request_overlay()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion:
		var motion_cell := _pick_cell(viewport_camera, event.position)
		if _valid_cell(motion_cell):
			_hover = motion_cell
		_update_preview_status()
		_request_overlay()
		return (
			EditorPlugin.AFTER_GUI_INPUT_STOP
			if _dragging
			else EditorPlugin.AFTER_GUI_INPUT_PASS
		)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			if not _dragging:
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			_dragging = false
			var release_cell := _pick_cell(viewport_camera, event.position)
			if _valid_cell(release_cell):
				_hover = release_cell
			if (
				_valid_cell(_hover)
				and (
					_hover != _anchor
					or event.position.distance_to(_press_position) >= 6.0
				)
			):
				_finalize_region(_hover)
			else:
				_set_status("Первый угол %s · протяните или кликните второй" % _cell_label(_anchor))
			_request_overlay()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		var picked := _pick_cell(viewport_camera, event.position)
		if _valid_cell(_anchor) and not _dragging:
			if not _valid_cell(picked):
				_set_status("Курсор вне карты · выберите второй угол")
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			_hover = picked
			_finalize_region(_hover)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		_hover = picked
		if not _valid_cell(_hover):
			_set_status("Курсор вне карты · наведите на Terrain")
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		_anchor = _hover
		_dragging = true
		_press_position = event.position
		_set_status("Первый угол %s · тяните ЛКМ" % _cell_label(_anchor))
		_request_overlay()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func draw_overlay(overlay: Control) -> void:
	if not is_instance_valid(_camera) or not is_instance_valid(_map):
		return
	var shown := _region
	if _valid_cell(_anchor) and _valid_cell(_hover):
		shown = rectangle_for_cells(_anchor, _hover)
	if not shown.has_area():
		return
	var top_world := _selection_top_world(shown)
	var local_corners := [
		Vector3(float(shown.position.x) * _tile_size(), top_world, float(shown.position.y) * _tile_size()),
		Vector3(float(shown.end.x) * _tile_size(), top_world, float(shown.position.y) * _tile_size()),
		Vector3(float(shown.end.x) * _tile_size(), top_world, float(shown.end.y) * _tile_size()),
		Vector3(float(shown.position.x) * _tile_size(), top_world, float(shown.end.y) * _tile_size()),
	]
	var points := PackedVector2Array()
	for local in local_corners:
		var world := _map.to_global(local)
		if _camera.is_position_behind(world):
			return
		points.append(_camera.unproject_position(world))
	overlay.draw_colored_polygon(points, Color(0.16, 0.78, 1.0, 0.13))
	points.append(points[0])
	overlay.draw_polyline(points, Color(0.20, 0.90, 1.0, 0.96), 4.0, true)
	for index in range(points.size() - 1):
		overlay.draw_circle(points[index], 6.0, Color(0.72, 0.96, 1.0, 1.0))
	var center := Vector2.ZERO
	for index in range(points.size() - 1):
		center += points[index]
	center /= 4.0
	overlay.draw_string(
		ThemeDB.fallback_font,
		center + Vector2(8.0, -8.0),
		"%d × %d" % [shown.size.x, shown.size.y],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		16,
		Color(0.82, 0.97, 1.0, 1.0),
	)


static func rectangle_for_cells(first: Vector2i, second: Vector2i) -> Rect2i:
	var minimum := Vector2i(mini(first.x, second.x), mini(first.y, second.y))
	var maximum := Vector2i(maxi(first.x, second.x), maxi(first.y, second.y))
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)


func selected_region() -> Rect2i:
	return _region


func _on_select_toggled(active: bool) -> void:
	_anchor = INVALID_CELL
	_hover = INVALID_CELL
	_dragging = false
	_set_status(
		"Протяните ЛКМ или задайте два угла · Esc отменяет"
		if active
		else _context_status()
	)
	_request_overlay()


func _open_region() -> void:
	if is_instance_valid(_map) and _region.has_area():
		surface_edit_requested.emit(_map, _region)


func _open_whole() -> void:
	if is_instance_valid(_map):
		surface_edit_requested.emit(_map, Rect2i())


func _on_toolbar_action(action_id: int) -> void:
	if action_id == 0:
		_open_whole()


func _pick_cell(viewport_camera: Camera3D, screen_position: Vector2) -> Vector2i:
	var ray_origin := viewport_camera.project_ray_origin(screen_position)
	var ray_direction := viewport_camera.project_ray_normal(screen_position)
	var hit_position := Vector3(INF, INF, INF)
	var world := _map.get_world_3d()
	if world != null:
		var query := PhysicsRayQueryParameters3D.create(
			ray_origin,
			ray_origin + ray_direction * 100000.0,
			1,
		)
		var hit := world.direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			hit_position = hit.get("position", hit_position)
	if not is_inf(hit_position.x):
		var hit_cell := cell_for_local_point(
			_map.to_local(hit_position), _tile_size(), _grid_width(), _grid_depth()
		)
		if _valid_cell(hit_cell):
			return hit_cell
	# A prop or helper outside the map can win the physics ray. Always retry on
	# the map-local ground plane instead of treating that unrelated hit as miss.
	var local_origin := _map.to_local(ray_origin)
	var local_far := _map.to_local(ray_origin + ray_direction * 100000.0)
	var local_direction := (local_far - local_origin).normalized()
	var fallback: Variant = Plane(Vector3.UP, 0.0).intersects_ray(local_origin, local_direction)
	if fallback == null:
		return INVALID_CELL
	return cell_for_local_point(
		fallback as Vector3, _tile_size(), _grid_width(), _grid_depth()
	)


static func cell_for_local_point(
	local: Vector3,
	tile_size: float,
	width: int,
	depth: int,
	edge_tolerance_tiles := 0.35,
) -> Vector2i:
	if tile_size <= 0.0 or width <= 0 or depth <= 0:
		return INVALID_CELL
	var tolerance := maxf(0.0, edge_tolerance_tiles) * tile_size
	if (
		local.x < -tolerance
		or local.z < -tolerance
		or local.x > float(width) * tile_size + tolerance
		or local.z > float(depth) * tile_size + tolerance
	):
		return INVALID_CELL
	return Vector2i(
		clampi(floori(local.x / tile_size), 0, width - 1),
		clampi(floori(local.z / tile_size), 0, depth - 1),
	)


func _surface_grid_for_map(map: EmberMapLoader) -> Dictionary:
	if not is_instance_valid(map):
		return {}
	var raw: Variant = EmberPack.parse_json_file(EmberPack.map_path(map.map_id))
	if typeof(raw) == TYPE_DICTIONARY:
		return EmberTileMesher.surface_grid(raw as Dictionary)
	if map.visual_surface != null:
		return {
			"width": map.visual_surface.size_blocks.x,
			"depth": map.visual_surface.size_blocks.z,
			"heights": PackedInt32Array(),
		}
	return {}


func _selection_top_world(region: Rect2i) -> float:
	var heights: PackedInt32Array = _grid.get("heights", PackedInt32Array())
	var maximum := 1
	for z in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var index := z * _grid_width() + x
			if index < heights.size():
				maximum = maxi(maximum, int(heights[index]))
	return float(maximum) * _tile_size() / 16.0 + maxf(0.5, _tile_size() * 0.04)


func _resolve_map() -> EmberMapLoader:
	if _editor_interface == null:
		return null
	var selection := _editor_interface.get_selection()
	if selection != null:
		for selected in selection.get_selected_nodes():
			var current := selected as Node
			while current != null:
				if current is EmberMapLoader:
					return current as EmberMapLoader
				current = current.get_parent()
	var root := _editor_interface.get_edited_scene_root()
	if root == null:
		return null
	if root is EmberMapLoader:
		return root as EmberMapLoader
	return root.find_child("Map", true, false) as EmberMapLoader


func _valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _grid_width() and cell.y < _grid_depth()


func _grid_width() -> int:
	return int(_grid.get("width", 0))


func _grid_depth() -> int:
	return int(_grid.get("depth", 0))


func _tile_size() -> float:
	return maxf(0.01, _map.imported_tile_size if is_instance_valid(_map) else 16.0)


func _cell_label(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x + 1, cell.y + 1]


func _update_preview_status() -> void:
	if _valid_cell(_anchor) and _valid_cell(_hover):
		var preview := rectangle_for_cells(_anchor, _hover)
		_set_status("Область %d×%d · второй угол %s" % [preview.size.x, preview.size.y, _cell_label(_hover)])
	elif _valid_cell(_hover):
		_set_status("Клетка %s · протяните ЛКМ" % _cell_label(_hover))


func _finalize_region(second: Vector2i) -> void:
	if not _valid_cell(_anchor) or not _valid_cell(second):
		return
	_region = rectangle_for_cells(_anchor, second)
	_anchor = INVALID_CELL
	_dragging = false
	_select_button.set_pressed_no_signal(false)
	_open_button.disabled = false
	_set_status("Область %d×%d готова · нажмите «Открыть область»" % [_region.size.x, _region.size.y])
	_request_overlay()


func _context_status() -> String:
	if not is_instance_valid(_map):
		return "Откройте обычную Ember-карту"
	if _region.has_area():
		return "Область %d×%d готова" % [_region.size.x, _region.size.y]
	return "Карта %s · %d×%d" % [_map.map_id, _grid_width(), _grid_depth()]


func _request_overlay() -> void:
	if is_instance_valid(_plugin):
		_plugin.update_overlays()


func _set_status(message: String) -> void:
	if is_instance_valid(_status):
		_status.text = message
		_status.tooltip_text = message
