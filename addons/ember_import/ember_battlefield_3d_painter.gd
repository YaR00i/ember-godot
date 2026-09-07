@tool
class_name EmberBattlefield3DPainter
extends RefCounted
## Native 3D viewport brush adapter. It previews a stroke in the overlay and
## commits one Battlefield Resource Undo action on left-button release.

const INVALID_CELL := Vector2i(-9999, -9999)
const Palette := preload("res://addons/ember_import/ember_battlefield_editor_palette.gd")
const TileLibrary := preload("res://scripts/prototypes/ember_battlefield_tile_library.gd")

signal surface_edit_requested(field: EmberBattlefieldResource)

enum PaintShape {
	BRUSH,
	RECTANGLE,
	FILL,
}

enum ToolbarAction {
	TILE_LIBRARY,
	RESIZE_FIELD,
	OPEN_SURFACE,
}

var _plugin: EditorPlugin
var _editor_interface: EditorInterface
var _actions: EmberBattlefieldEditorActions
var _toolbar: HBoxContainer
var _enabled: Button
var _brush: OptionButton
var _shape: OptionButton
var _group_id: LineEdit
var _more_menu: MenuButton
var _status: Label
var _world: EmberCombatGrid3DWorld
var _camera: Camera3D
var _hover_cell := INVALID_CELL
var _stroke_anchor := INVALID_CELL
var _stroke_cells: Array[Vector2i] = []
var _stroke_active := false


func configure(
	plugin: EditorPlugin,
	editor_interface: EditorInterface,
	actions: EmberBattlefieldEditorActions,
) -> void:
	_plugin = plugin
	_editor_interface = editor_interface
	_actions = actions


func build_toolbar() -> Control:
	_toolbar = HBoxContainer.new()
	_toolbar.name = "EmberBattlefield3DToolbar"
	_toolbar.tooltip_text = "Рисование semantic Battlefield Resource прямо в 3D."

	_enabled = Button.new()
	_enabled.name = "Battlefield3DPaintToggle"
	_enabled.text = "Поле боя"
	_enabled.toggle_mode = true
	_enabled.tooltip_text = "Включить 3D-кисти Ember. Обычное выделение ЛКМ временно отключается."
	_enabled.toggled.connect(_on_enabled_toggled)
	_toolbar.add_child(_enabled)

	_brush = OptionButton.new()
	_brush.name = "Battlefield3DBrush"
	Palette.populate(_brush)
	_brush.tooltip_text = "Alt+ЛКМ по клетке — пипетка поверхности и группы."
	_brush.item_selected.connect(_on_brush_selected)
	_toolbar.add_child(_brush)

	_shape = OptionButton.new()
	_shape.name = "Battlefield3DShape"
	for entry in [
		["Кисть", PaintShape.BRUSH],
		["Прямоугольник", PaintShape.RECTANGLE],
		["Заливка", PaintShape.FILL],
	]:
		_shape.add_item(str(entry[0]))
		_shape.set_item_metadata(_shape.item_count - 1, int(entry[1]))
	_shape.tooltip_text = "Кисть рисует линию; прямоугольник и заливка применяются одним Undo."
	_shape.item_selected.connect(_on_shape_selected)
	_toolbar.add_child(_shape)

	_group_id = LineEdit.new()
	_group_id.name = "Battlefield3DGroup"
	_group_id.placeholder_text = "Группа (авто)"
	_group_id.custom_minimum_size.x = 112.0
	_group_id.tooltip_text = "Пусто: Wet → tide, Ember → ember."
	_toolbar.add_child(_group_id)

	_more_menu = MenuButton.new()
	_more_menu.name = "Battlefield3DMoreMenu"
	_more_menu.text = "Ещё…"
	_more_menu.tooltip_text = "Библиотека тайлов, размер поля и художественная Surface."
	var more_popup := _more_menu.get_popup()
	more_popup.add_item("Библиотека тайлов…", ToolbarAction.TILE_LIBRARY)
	more_popup.add_item("Размер поля…", ToolbarAction.RESIZE_FIELD)
	more_popup.add_separator()
	more_popup.add_item("Открыть всю арену в Surface", ToolbarAction.OPEN_SURFACE)
	more_popup.id_pressed.connect(_on_toolbar_action)
	_toolbar.add_child(_more_menu)

	_status = Label.new()
	_status.name = "Battlefield3DStatus"
	_status.text = "Выберите арену"
	_status.custom_minimum_size.x = 96.0
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_toolbar.add_child(_status)
	refresh_context()
	return _toolbar


func shutdown() -> void:
	_cancel_stroke()
	_world = null
	_camera = null
	_plugin = null
	_editor_interface = null
	_actions = null


func refresh_context() -> void:
	_world = _resolve_world()
	var valid := (
		is_instance_valid(_world)
		and _world.battlefield != null
		and _world.battlefield.validation_errors().is_empty()
	)
	if is_instance_valid(_toolbar):
		_toolbar.visible = valid
	if is_instance_valid(_enabled):
		_enabled.disabled = not valid
		if not valid and _enabled.button_pressed:
			_enabled.set_pressed_no_signal(false)
	if is_instance_valid(_more_menu):
		_more_menu.disabled = not valid
	_refresh_active_tool_controls()
	if not valid:
		_cancel_stroke()
		_hover_cell = INVALID_CELL
		_set_status("Выберите корень battle arena")
	else:
		_set_status("Готово · %s" % _world.battlefield.display_name)
	_request_overlay()


func forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if not is_instance_valid(_enabled) or not _enabled.button_pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if not is_instance_valid(_world) or _world.battlefield == null:
		refresh_context()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	_camera = viewport_camera
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _stroke_active:
		_cancel_stroke()
		_set_status("Штрих отменён")
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion:
		_set_hover(_world.editor_pick_cell(viewport_camera, event.position))
		if _stroke_active and bool(event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			match _selected_shape():
				PaintShape.BRUSH:
					if not _single_cell_tool(_selected_tool()):
						_append_stroke_cell(_hover_cell)
				PaintShape.RECTANGLE:
					_preview_rectangle(_hover_cell)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_set_hover(_world.editor_pick_cell(viewport_camera, event.position))
		if event.pressed and event.alt_pressed:
			_pick_brush_from_cell(_hover_cell)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.pressed:
			if not _valid_cell(_hover_cell):
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			_begin_stroke(_hover_cell)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if _stroke_active:
			_commit_stroke()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func draw_overlay(overlay: Control) -> void:
	if not is_instance_valid(_enabled) or not _enabled.button_pressed or not is_instance_valid(_camera):
		return
	var cells := _stroke_cells.duplicate()
	if _valid_cell(_hover_cell) and _hover_cell not in cells:
		cells.append(_hover_cell)
	for cell in cells:
		var corners := _world.editor_cell_corners(cell)
		if corners.size() != 4:
			continue
		var points := PackedVector2Array()
		var behind := false
		for corner in corners:
			if _camera.is_position_behind(corner):
				behind = true
				break
			points.append(_camera.unproject_position(corner))
		if behind:
			continue
		points.append(points[0])
		var color := _tool_color(_selected_tool())
		if cell in _stroke_cells:
			color.a = 0.95
		overlay.draw_polyline(points, color, 3.0, true)


func selected_tool() -> int:
	return _selected_tool()


func stroke_cells() -> Array[Vector2i]:
	return _stroke_cells.duplicate()


func _on_enabled_toggled(active: bool) -> void:
	_cancel_stroke()
	_hover_cell = INVALID_CELL
	_refresh_active_tool_controls()
	_set_status(
		"%s · ЛКМ рисует · Alt+ЛКМ пипетка" % _shape_label()
		if active
		else ("Готово · %s" % _world.battlefield.display_name if is_instance_valid(_world) else "Выберите арену")
	)
	_request_overlay()


func _refresh_active_tool_controls() -> void:
	var active := is_instance_valid(_enabled) and _enabled.button_pressed and not _enabled.disabled
	for control in [_brush, _shape, _group_id]:
		if is_instance_valid(control):
			control.visible = active


func _on_toolbar_action(action_id: int) -> void:
	match action_id:
		ToolbarAction.TILE_LIBRARY:
			_open_tile_library()
		ToolbarAction.RESIZE_FIELD:
			_open_resize_controls()
		ToolbarAction.OPEN_SURFACE:
			_open_surface_editor()


func _set_hover(cell: Vector2i) -> void:
	var next := cell if _valid_cell(cell) else INVALID_CELL
	if next == _hover_cell:
		return
	_hover_cell = next
	if _valid_cell(_hover_cell) and not _stroke_active:
		_set_status("%s · %s" % [_cell_label(_hover_cell), _shape_label()])
	_request_overlay()


func _begin_stroke(cell: Vector2i) -> void:
	_stroke_active = true
	_stroke_anchor = cell
	_stroke_cells.clear()
	match _selected_shape():
		PaintShape.RECTANGLE:
			_preview_rectangle(cell)
		PaintShape.FILL:
			_stroke_cells = _world.battlefield.connected_matching_cells(cell)
			_request_overlay()
		_:
			_append_stroke_cell(cell)
	_set_status("%s · %d клеток · отпустите ЛКМ" % [_shape_label(), _stroke_cells.size()])


func _preview_rectangle(cell: Vector2i) -> void:
	if not _valid_cell(_stroke_anchor) or not _valid_cell(cell):
		return
	_stroke_cells = _world.battlefield.rectangle_cells(_stroke_anchor, cell)
	_set_status("Прямоугольник · %d клеток" % _stroke_cells.size())
	_request_overlay()


func _append_stroke_cell(cell: Vector2i) -> void:
	if not _valid_cell(cell):
		return
	if _single_cell_tool(_selected_tool()) and not _stroke_cells.is_empty():
		return
	var from := cell if _stroke_cells.is_empty() else _stroke_cells[-1]
	for painted_cell in _cells_on_line(from, cell):
		if _valid_cell(painted_cell) and painted_cell not in _stroke_cells:
			_stroke_cells.append(painted_cell)
	_request_overlay()


func _cells_on_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var current := from
	var delta := (to - from).abs()
	var step := Vector2i(1 if from.x < to.x else -1, 1 if from.y < to.y else -1)
	var error := delta.x - delta.y
	while true:
		cells.append(current)
		if current == to:
			break
		var doubled_error := error * 2
		if doubled_error > -delta.y:
			error -= delta.y
			current.x += step.x
		if doubled_error < delta.x:
			error += delta.x
			current.y += step.y
	return cells


func _commit_stroke() -> void:
	var cells := _stroke_cells.duplicate()
	_stroke_active = false
	_stroke_anchor = INVALID_CELL
	_stroke_cells.clear()
	if not cells.is_empty() and _actions != null:
		_actions.paint_cells(
			_world.battlefield,
			cells,
			_selected_tool(),
			_group_id.text,
		)
		_set_status("Применено: %d · Ctrl+Z отменяет" % cells.size())
	_request_overlay()


func _cancel_stroke() -> void:
	_stroke_active = false
	_stroke_anchor = INVALID_CELL
	_stroke_cells.clear()
	_request_overlay()


func _on_brush_selected(_index: int) -> void:
	_cancel_stroke()
	var single_cell := _single_cell_tool(_selected_tool())
	if is_instance_valid(_shape):
		_shape.disabled = single_cell
		if single_cell:
			_shape.select(PaintShape.BRUSH)
	_set_status("Ставится одной клеткой" if single_cell else "%s · готово" % _shape_label())


func _on_shape_selected(_index: int) -> void:
	_cancel_stroke()
	_set_status("%s · готово" % _shape_label())


func _open_tile_library() -> void:
	if _editor_interface == null:
		return
	var library := TileLibrary.default_library()
	if library != null:
		_editor_interface.edit_resource(library)


func _open_resize_controls() -> void:
	if _editor_interface != null and is_instance_valid(_world) and _world.battlefield != null:
		_editor_interface.edit_resource(_world.battlefield)


func _open_surface_editor() -> void:
	if is_instance_valid(_world) and _world.battlefield != null:
		surface_edit_requested.emit(_world.battlefield)


func _pick_brush_from_cell(cell: Vector2i) -> void:
	if not _valid_cell(cell):
		return
	var definition := _world.battlefield.cell_definition(cell)
	var tool := EmberBattlefieldResource.PaintTool.NEUTRAL
	if cell in _world.battlefield.party_deployment_cells:
		tool = EmberBattlefieldResource.PaintTool.PARTY_DEPLOYMENT
	elif cell in _world.battlefield.enemy_deployment_cells:
		tool = EmberBattlefieldResource.PaintTool.ENEMY_DEPLOYMENT
	elif bool(definition.get("blocked", false)):
		tool = EmberBattlefieldResource.PaintTool.BLOCKED
	else:
		match int(definition.get("terrain", EmberBattlefieldResource.TerrainKind.NEUTRAL)):
			EmberBattlefieldResource.TerrainKind.WET:
				tool = EmberBattlefieldResource.PaintTool.WET
			EmberBattlefieldResource.TerrainKind.EMBER:
				tool = EmberBattlefieldResource.PaintTool.EMBER
			EmberBattlefieldResource.TerrainKind.FROZEN:
				tool = EmberBattlefieldResource.PaintTool.FROZEN
	_select_tool(tool)
	_group_id.text = str(definition.get("group", ""))
	_set_status("Пипетка %s · %s" % [_cell_label(cell), _brush.get_item_text(_brush.selected)])
	_request_overlay()


func _resolve_world() -> EmberCombatGrid3DWorld:
	if _editor_interface == null:
		return null
	var selection := _editor_interface.get_selection()
	if selection != null:
		for selected in selection.get_selected_nodes():
			var current := selected as Node
			while current != null:
				if current is EmberCombatGrid3DWorld:
					return current as EmberCombatGrid3DWorld
				current = current.get_parent()
	var root := _editor_interface.get_edited_scene_root()
	return root as EmberCombatGrid3DWorld


func _selected_tool() -> int:
	return int(_brush.get_selected_metadata()) if is_instance_valid(_brush) else EmberBattlefieldResource.PaintTool.NEUTRAL


func _selected_shape() -> int:
	return int(_shape.get_selected_metadata()) if is_instance_valid(_shape) else PaintShape.BRUSH


func _select_tool(tool: int) -> void:
	for index in _brush.item_count:
		if int(_brush.get_item_metadata(index)) == tool:
			_brush.select(index)
			_on_brush_selected(index)
			return


func _valid_cell(cell: Vector2i) -> bool:
	return is_instance_valid(_world) and _world.battlefield != null and _world.battlefield.contains(cell)


func _request_overlay() -> void:
	if is_instance_valid(_plugin):
		_plugin.update_overlays()


func _set_status(message: String) -> void:
	if is_instance_valid(_status):
		_status.text = message
		_status.tooltip_text = message


func _cell_label(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(65 + cell.x), cell.y + 1]


func _tool_color(tool: int) -> Color:
	return Palette.tool_color(tool)


func _shape_label() -> String:
	return _shape.get_item_text(_shape.selected) if is_instance_valid(_shape) else "Кисть"


func _single_cell_tool(tool: int) -> bool:
	return tool in [
		EmberBattlefieldResource.PaintTool.FOCUS,
		EmberBattlefieldResource.PaintTool.PARTY_DEPLOYMENT,
		EmberBattlefieldResource.PaintTool.ENEMY_DEPLOYMENT,
	]
