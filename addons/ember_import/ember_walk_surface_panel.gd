@tool
extends VBoxContainer
## Native editor controls. Preview RIDs use the scene world without adding nodes,
## collision, a copied scene or a private camera to the author's scene tree.
const Session = preload("res://addons/ember_import/ember_walk_surface_session.gd")
const Surface = preload("res://addons/ember_import/ember_walk_surface.gd")
const Mask = preload("res://addons/ember_import/ember_walk_surface_mask.gd")
signal closed
var session: RefCounted
var _undo: Object
var _numbers: Array[SpinBox] = []
var _status: Label
var _apply: Button
var _visible: CheckBox
var _fields: GridContainer
var _scroll: ScrollContainer
var _busy := false
var _instances: Array[RID] = []
var _meshes: Array[Mesh] = []
var _target_id := 0
var _tools: HFlowContainer
var _brush: OptionButton
var _brush_size: SpinBox
var _gap: SpinBox
var _tolerance: SpinBox
var _draft_undo: Button
var _draft_redo: Button
var _undo_masks: Array[Dictionary] = []
var _redo_masks: Array[Dictionary] = []
var _stroke_before: Dictionary = {}
var _last_cell := Vector2i(-1,-1)
var _cursor := RID()
var _cursor_mesh: Mesh
var _hover_cell := Vector2i(-1,-1)
var _labels: Array[Label] = []
var _advanced: CheckButton
var _replace: Button


func _init() -> void:
	name = "EmberWalkSurfacePanel"
	custom_minimum_size.y = 175
	var header := HBoxContainer.new()
	add_child(header)
	var info := Label.new()
	info.text = "Опора · черновик в основном 3D-окне"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(info)
	_visible = CheckBox.new()
	_visible.text = "Показать черновик"
	_visible.button_pressed = true
	_visible.toggled.connect(_set_preview_visible)
	header.add_child(_visible)
	_apply = Button.new()
	_apply.text = "Применить"
	_apply.disabled = true
	_apply.pressed.connect(_commit)
	header.add_child(_apply)
	var cancel := Button.new()
	cancel.text = "Отмена"
	cancel.pressed.connect(cancel_edit)
	header.add_child(cancel)
	_tools = HFlowContainer.new()
	add_child(_tools)
	var generate := Button.new()
	generate.text = "По геометрии"
	generate.pressed.connect(_generate)
	_tools.add_child(generate)
	_gap = _tool_number("Щель, vox",0,32,2)
	_tolerance = _tool_number("Допуск, vox",1,16,2)
	_brush = OptionButton.new()
	for caption in ["Просмотр", "Убрать", "Вернуть"]:
		_brush.add_item(caption)
	_tools.add_child(_brush)
	_brush.item_selected.connect(func(_index): _abort_stroke(); _clear_cursor())
	_brush_size = _tool_number("Кисть, vox",1,16,1)
	_draft_undo = Button.new()
	_draft_undo.text = "↶ Мазок"
	_draft_undo.pressed.connect(_history.bind(false))
	_tools.add_child(_draft_undo)
	_draft_redo = Button.new()
	_draft_redo.text = "↷"
	_draft_redo.pressed.connect(_history.bind(true))
	_tools.add_child(_draft_redo)
	_advanced = CheckButton.new()
	_advanced.text = "Положение"
	_tools.add_child(_advanced)
	_advanced.toggled.connect(func(value): _fields.visible = value; _scroll.visible = value)
	_replace = Button.new()
	_replace.text = "Оставить эту опору"
	_replace.tooltip_text = "Применить текущую разметку и отключить совпадающие опоры. Undo вернёт их коллизию. Узлы и исходные доски не удаляются."
	_replace.pressed.connect(_commit.bind(true))
	_tools.add_child(_replace)
	_replace.hide()
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.custom_minimum_size.y = 112
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	_fields = grid
	scroll.resized.connect(_update_columns)
	for caption in ["Ширина X", "Длина Z", "Центр X", "Высота Y", "Центр Z", "Наклон X°", "Поворот Y°", "Наклон Z°"]:
		var row := HBoxContainer.new()
		grid.add_child(row)
		var label := Label.new()
		label.text = caption
		_labels.append(label)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var number := SpinBox.new()
		number.min_value = -100000
		number.max_value = 100000
		number.step = 0.01
		number.custom_minimum_size.x = 105
		row.add_child(number)
		_numbers.append(number)
		number.value_changed.connect(_refresh.unbind(1))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_status.text = "Выберите настил или опору → Ещё… → Поверхность прохода…"
	_fields.hide()
	_tools.hide()
	visibility_changed.connect(_on_visibility_changed)

func _tool_number(caption: String, low: int, high: int, value: int) -> SpinBox:
	var row := HBoxContainer.new()
	_tools.add_child(row)
	var label := Label.new()
	label.text = caption
	row.add_child(label)
	var number := SpinBox.new()
	number.min_value = low
	number.max_value = high
	number.step = 1
	number.value = value
	number.custom_minimum_size.x = 60
	row.add_child(number)
	return number


func _update_columns() -> void:
	_fields.columns = clampi(floori((_scroll.size.x - 16.0) / 240.0), 1, 4)
	_scroll.custom_minimum_size.y = minf(180.0, _fields.get_combined_minimum_size().y + 8.0)


func open_for(selected: Node3D, scene: Node, undo: Object) -> bool:
	_clear_preview()
	_clear_cursor()
	_undo_masks.clear()
	_redo_masks.clear()
	_stroke_before = {}
	_brush.select(0)
	session = Session.new()
	_undo = undo
	_target_id = 0
	if not session.open(selected, scene):
		_status.text = session.error
		session = null
		_apply.disabled = true
		_fields.hide()
		_tools.hide()
		_scroll.hide()
		return false
	if session.target != null:
		_target_id = session.target.get_instance_id()
	_busy = true
	var pos: Vector3 = session.initial_pose.origin
	var angles: Vector3 = session.initial_pose.basis.get_euler() * 180.0 / PI
	var values := [session.initial_size.x, session.initial_size.y, pos.x, pos.y, pos.z, angles.x, angles.y, angles.z]
	for index in values.size():
		_numbers[index].value = values[index]
	_busy = false
	_fields.show()
	_tools.show()
	_update_columns()
	if not session.initial_mask.is_empty():
		session.plan_mask(session.initial_mask,session.initial_pose)
		_sync_mask_fields()
		_render_preview()
	else:
		_sync_mask_fields()
		_refresh()
	return true


func _context_valid() -> bool:
	if session == null:
		return false
	if not is_instance_valid(session.scene) or not session.scene.is_inside_tree():
		return false
	if not is_instance_valid(session.parent) or not session.parent.is_inside_tree():
		return false
	if not is_instance_valid(session.context_target) or not session.context_target.is_inside_tree():
		return false
	if session.scene != session.parent and not session.scene.is_ancestor_of(session.parent):
		return false
	if not session.parent.global_transform.is_equal_approx(session._parent_world):
		return false
	if not session.planned_mask.is_empty() and not session.geometry_current():
		return false
	if _target_id != 0 and not is_instance_id_valid(_target_id):
		return false
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() != session.scene:
		return false
	return true


func _process(_dt: float) -> void:
	if session != null and not _context_valid():
		cancel_edit("Сцена или родитель изменились. Откройте поверхность заново.")


func scene_context_changed(scene: Node) -> void:
	if session != null and scene != session.scene:
		cancel_edit("Черновик отменён при смене сцены.")


func _refresh() -> void:
	if _busy or session == null:
		return
	_abort_stroke()
	_apply.disabled = true
	_clear_preview()
	if not _context_valid():
		cancel_edit("Сцена или родитель изменились. Откройте поверхность заново.")
		return
	var size := Vector2(_numbers[0].value, _numbers[1].value)
	var angles := Vector3(_numbers[5].value, _numbers[6].value, _numbers[7].value) * PI / 180.0
	var scale: Vector3 = session.initial_pose.basis.get_scale() if session.planned_mask.is_empty() else session.planned_pose.basis.get_scale()
	var basis := Basis.from_euler(angles) * Basis.from_scale(scale)
	var pose := Transform3D(basis, Vector3(_numbers[2].value, _numbers[3].value, _numbers[4].value))
	var valid: bool = session.plan(size,pose) if session.planned_mask.is_empty() else session.plan_mask(session.planned_mask,pose)
	if not valid:
		_status.text = session.error
		return
	_render_preview()

func _render_preview() -> void:
	_clear_preview()
	_clear_cursor()
	_replace.hide()
	_replace.disabled = true
	_draft_undo.disabled = _undo_masks.is_empty()
	_draft_redo.disabled = _redo_masks.is_empty()
	var voxel: bool = not session.planned_mask.is_empty()
	if voxel and Mask.rectangles(session.planned_mask).size() > Mask.MAX_RECTS:
		_status.text = session.error
		_apply.disabled = true
		return
	var mesh: Mesh = Mask.visual_mesh(session.planned_mask) if voxel else Surface.visual_mesh(session.planned_size)
	if mesh.get_surface_count() > 0:
		_show_mesh(mesh,Color(0.1,0.9,0.75,0.3),false)
	_add_lines(Mask.grid_lines(session.planned_mask) if voxel else Surface.grid_lines(session.planned_size),Color(0.1,1,0.85,0.5))
	var red := PackedVector3Array()
	for index in mini(128, session.warnings.size()):
		var box: AABB = session.warnings[index]
		for edge in [[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]]:
			red.append(box.get_endpoint(edge[0]))
			red.append(box.get_endpoint(edge[1]))
	if not red.is_empty():
		_add_lines(red, Color(1, 0.25, 0.15))
	_status.text = "Невидимая общая опора. Доски и их коллизия не меняются. Черновик не сохраняется."
	if voxel:
		_status.text = "Сетка %d×%d vox · клетка %.3f×%.3f ед. ЛКМ — кисть, Esc — отменить мазок. «Вернуть» восстанавливает только сгенерированную опору." % [session.planned_mask.count.x,session.planned_mask.count.y,session.planned_mask.cell.x,session.planned_mask.cell.y]
	if not session.warnings.is_empty():
		_status.text += " Возможные выступы: %d — красные рамки по габаритам, не проверка свободного прохода." % session.warnings.size()
	_apply.disabled = not session._has_plan
	var conflicts: Array[StaticBody3D] = session.duplicates()
	if not conflicts.is_empty():
		var names := PackedStringArray()
		for node in conflicts:
			names.append(str(node.name))
		_status.text += " Перекрывающие опоры: %s. «Оставить эту опору» применит черновик и отключит эти дубликаты; Undo вернёт их." % ", ".join(names)
		_apply.disabled = true
		_replace.show()
		_replace.disabled = not session._has_plan
	if not session._has_plan:
		_status.text = session.error
	_draft_undo.disabled = _undo_masks.is_empty()
	_draft_redo.disabled = _redo_masks.is_empty()

func _sync_mask_fields() -> void:
	var voxel: bool = not session.planned_mask.is_empty()
	_busy = true
	_labels[0].text = "Ширина, vox" if voxel else "Ширина X"
	_labels[1].text = "Длина, vox" if voxel else "Длина Z"
	_numbers[0].editable = not voxel
	_numbers[1].editable = not voxel
	_brush.disabled = not voxel
	_brush_size.editable = voxel
	_advanced.visible = voxel
	_advanced.set_pressed_no_signal(false)
	_fields.visible = not voxel
	_scroll.visible = not voxel
	if voxel:
		_numbers[0].step = 1
		_numbers[1].step = 1
		_numbers[0].value = session.planned_mask.count.x
		_numbers[1].value = session.planned_mask.count.y
		var pos: Vector3 = session.planned_pose.origin
		var angles: Vector3 = session.planned_pose.basis.get_euler()*180/PI
		for index in 3:
			_numbers[index+2].value = pos[index]
			_numbers[index+5].value = angles[index]
		# Grid indices are integers, but its scene origin may be fractional.
		# Keep the original coordinate precision rather than rounding a prop's
		# placement when merely reopening the saved footprint.
		for index in range(2,5):
			_numbers[index].step = 0.01
	else:
		for number in _numbers:
			number.step = 0.01
	_busy = false

func _generate() -> void:
	if session == null or not _context_valid():
		return
	_abort_stroke()
	# An existing legacy rectangle may not remember its source. Keep it as
	# the edit target, but let the author select the boards in the 3D scene.
	if Engine.is_editor_hint():
		var selected := EditorInterface.get_selection().get_selected_nodes()
		if selected.size() == 1 and selected[0] is Node3D and not Surface.is_surface(selected[0]):
			if not session.rebind_geometry(selected[0]):
				_clear_preview()
				_apply.disabled = true
				session._has_plan = false
				_status.text = session.error if session.geometry_error.is_empty() else session.geometry_error
				return
	if not session.generate(int(_gap.value),int(_tolerance.value)):
		_clear_preview()
		_apply.disabled = true
		_status.text = session.error
		return
	_undo_masks.clear()
	_redo_masks.clear()
	_brush.select(0)
	_sync_mask_fields()
	_render_preview()

func _history(redo: bool) -> void:
	if session == null or session.planned_mask.is_empty():
		return
	_abort_stroke()
	var source := _redo_masks if redo else _undo_masks
	var destination := _undo_masks if redo else _redo_masks
	if source.is_empty():
		return
	destination.append(session.planned_mask.duplicate(true))
	var data: Dictionary = source.pop_back()
	session.plan_mask(data,session.planned_pose)
	_render_preview()

func _finish_stroke() -> void:
	if _stroke_before.is_empty():
		return
	if session.planned_mask.bits != _stroke_before.bits:
		_undo_masks.append(_stroke_before)
		if _undo_masks.size() > 64:
			_undo_masks.pop_front()
		_redo_masks.clear()
	_stroke_before = {}
	var data: Dictionary = session.planned_mask.duplicate(true)
	session.plan_mask(data,session.planned_pose)
	_render_preview()

func _abort_stroke() -> void:
	if not _stroke_before.is_empty() and session != null:
		session.planned_mask = _stroke_before
	_stroke_before = {}
	_last_cell = Vector2i(-1,-1)

func forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if session == null or not is_visible_in_tree() or not _visible.button_pressed or session.planned_mask.is_empty() or _brush.selected == 0:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if not _context_valid():
		cancel_edit()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not _stroke_before.is_empty():
		_abort_stroke()
		_render_preview()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not _stroke_before.is_empty():
		_finish_stroke()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if not event is InputEventMouse or event.alt_pressed or event.ctrl_pressed or event.shift_pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion and (event.button_mask & ~MOUSE_BUTTON_MASK_LEFT) != 0:
		_clear_cursor()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var inverse: Transform3D = session.world_pose().affine_inverse()
	var from: Vector3 = inverse*camera.project_ray_origin(event.position)
	var direction: Vector3 = inverse.basis*camera.project_ray_normal(event.position)
	if absf(direction.y) < 0.00001:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var distance := -from.y/direction.y
	var cell := Mask.at(from+direction*distance,session.planned_mask)
	if distance < 0 or not Mask.inside(cell,session.planned_mask.count):
		_clear_cursor()
		_last_cell = Vector2i(-1,-1)
		return EditorPlugin.AFTER_GUI_INPUT_STOP if not _stroke_before.is_empty() else EditorPlugin.AFTER_GUI_INPUT_PASS
	_show_cursor(cell)
	if event is InputEventMouseButton and event.pressed:
		_stroke_before = session.planned_mask.duplicate(true)
		_last_cell = cell
	if not _stroke_before.is_empty():
		Mask.paint(session.planned_mask,cell if _last_cell.x < 0 else _last_cell,cell,int(_brush_size.value),_brush.selected == 2)
		_last_cell = cell
	return EditorPlugin.AFTER_GUI_INPUT_STOP

func _show_cursor(cell: Vector2i) -> void:
	if cell == _hover_cell and _cursor.is_valid():
		return
	_clear_cursor()
	_hover_cell = cell
	var diameter := int(_brush_size.value)
	var low := -floori(float(diameter-1)/2)
	var a := (cell+Vector2i(low,low)).max(Vector2i.ZERO)
	var b := (cell+Vector2i(low+diameter,low+diameter)).min(session.planned_mask.count)
	var rect := Rect2i(a,b-a)
	var center := Mask.rect_pose(rect,session.planned_mask)
	var extent: Vector2 = Vector2(rect.size)*session.planned_mask.cell*0.5
	var vertices := PackedVector3Array()
	var corners := [center+Vector3(-extent.x,0,-extent.y),center+Vector3(extent.x,0,-extent.y),center+Vector3(extent.x,0,extent.y),center+Vector3(-extent.x,0,extent.y)]
	for index in 4:
		vertices.append(corners[index])
		vertices.append(corners[(index+1)%4])
	_add_lines(vertices,Color(1,0.85,0.15))
	_cursor = _instances.pop_back()
	_cursor_mesh = _meshes.pop_back()

func _clear_cursor() -> void:
	if _cursor.is_valid():
		RenderingServer.free_rid(_cursor)
	_cursor = RID()
	_cursor_mesh = null
	_hover_cell = Vector2i(-1,-1)


func _show_mesh(mesh: Mesh, color: Color, no_depth: bool) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = no_depth
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_set_material(0, material)
	_meshes.append(mesh)
	var instance := RenderingServer.instance_create()
	_instances.append(instance)
	RenderingServer.instance_set_base(instance, mesh.get_rid())
	RenderingServer.instance_set_scenario(instance, session.parent.get_world_3d().scenario)
	RenderingServer.instance_set_transform(instance, session.world_pose())
	RenderingServer.instance_geometry_set_cast_shadows_setting(instance, RenderingServer.SHADOW_CASTING_SETTING_OFF)
	RenderingServer.instance_set_visible(instance, is_visible_in_tree() and _visible.button_pressed)


func _add_lines(vertices: PackedVector3Array, color: Color) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_show_mesh(mesh, color, true)


func _set_preview_visible(value: bool) -> void:
	if not value or not is_visible_in_tree():
		_abort_stroke()
		_clear_cursor()
	for instance in _instances:
		RenderingServer.instance_set_visible(instance, value and is_visible_in_tree())


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_brush.select(0)
	_set_preview_visible(_visible.button_pressed)


func _clear_preview() -> void:
	for instance in _instances:
		RenderingServer.free_rid(instance)
	_instances.clear()
	_meshes.clear()


func _commit(replace_duplicates := false) -> void:
	_finish_stroke()
	if session == null or (_replace.disabled if replace_duplicates else _apply.disabled):
		return
	if not _context_valid() or session.commit(_undo,replace_duplicates) == null:
		if _context_valid() and not session.duplicates().is_empty():
			_render_preview()
			return
		_clear_preview()
		_status.text = "Сцена или опора изменились. Откройте поверхность заново."
		_apply.disabled = true
		return
	cancel_edit("Поверхность применена. Undo/Redo доступны в редакторе.")


func cancel_edit(message: String = "Черновик отменён.") -> void:
	_abort_stroke()
	_clear_cursor()
	_clear_preview()
	session = null
	_target_id = 0
	_fields.hide()
	_tools.hide()
	_apply.disabled = true
	_replace.hide()
	_status.text = message
	closed.emit()


func _exit_tree() -> void:
	_clear_cursor()
	_clear_preview()
