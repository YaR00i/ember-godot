@tool
extends Control
## Canvas-only interaction overlay. SelectionPanel and SculptActions remain owners.
const Gesture = preload("res://addons/ember_import/ember_voxel_selection_gesture.gd")
const Fragment = preload("res://addons/ember_import/ember_voxel_fragment.gd")
const Selection = preload("res://addons/ember_import/ember_voxel_selection.gd")
const SurfaceMarquee = preload("res://addons/ember_import/ember_voxel_surface_marquee.gd")
const Stamp = preload("res://addons/ember_import/ember_voxel_stamp.gd")
var _stamp: Resource
var _stamp_controls: VBoxContainer
var _stamp_mode: OptionButton
var _stamp_mirror: OptionButton
var _stamp_anchor: OptionButton
var _stamp_part := 0
var _surface_marquee: RefCounted
var _surface_bounds := {}
var _depth := 1
var _gesture_mode := 3
var workspace: Control
var dragging := false
var transforming := false
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _operation := 0
var _job: RefCounted
var _job_rect := Rect2()
var _finish := false
var _prior := {}
var _ghost: MultiMeshInstance3D
var _hover: MeshInstance3D
var _controls: VBoxContainer
var _numbers: Array[SpinBox] = []
var _axis: OptionButton
var _turns: OptionButton
var _copy: CheckBox
var _apply: Button
var _hint: Label
var _indices := PackedInt32Array()
var _plan := {}
var _pending := false
var _offset := Vector3i.ZERO
var _arrow_axis := -1
var _arrow_start := Vector2.ZERO
var _arrow_value := 0
var _center := Vector3.ZERO
var _snapshot := {}
var _syncing := false
var _source: EmberVoxelModelResource
var _committing := false
var _ready_rect := Rect2(-9999,-9999,0,0)
var _region := Rect2i()
var _height := -1
var _query_camera := Transform3D.IDENTITY
var _query_size := Vector2.ZERO
var _query_zoom := 0.0

func operation_hint() -> String:
	return ["Новое выделение", "Добавить к выделению", "Убрать из выделения"][_operation]

func setup(owner_workspace: Control) -> void:
	workspace = owner_workspace
	workspace._selection_panel.selection_changed.connect(func(has_selection: bool) -> void:
		if not has_selection and transforming and not _committing and _stamp == null:
			cancel_gesture())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ghost = MultiMeshInstance3D.new()
	workspace._surface_root.add_child(_ghost)
	_hover = MeshInstance3D.new()
	workspace._surface_root.add_child(_hover)
	var outline := ImmediateMesh.new()
	outline.surface_begin(Mesh.PRIMITIVE_LINES)
	var box := AABB(Vector3.ZERO,Vector3.ONE)
	for edge in [[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]]:
		outline.surface_add_vertex(box.get_endpoint(edge[0]))
		outline.surface_add_vertex(box.get_endpoint(edge[1]))
	outline.surface_end()
	_hover.mesh = outline
	_hover.material_override = _material(Color(0.1,1,1,1))
	_hover.hide()
	_controls = VBoxContainer.new()
	workspace._selection_panel.add_child(_controls)
	_controls.hide()
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls.add_child(_hint)
	for axis in ["X", "Y", "Z"]:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "Сдвиг " + axis + " · vox"
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(label)
		var number := SpinBox.new()
		number.min_value = -4096
		number.max_value = 4096
		number.value_changed.connect(_changed.unbind(1))
		row.add_child(number)
		_numbers.append(number)
		_controls.add_child(row)
	_axis = OptionButton.new()
	for label in ["Вокруг X", "Вокруг Y", "Вокруг Z"]:
		_axis.add_item(label)
	_axis.select(1)
	_controls.add_child(_axis)
	_turns = OptionButton.new()
	for label in ["Без поворота", "+90°", "180°", "−90°"]:
		_turns.add_item(label)
	_controls.add_child(_turns)
	_copy = CheckBox.new()
	_copy.text = "Копия · оставить исходный фрагмент"
	_controls.add_child(_copy)
	_axis.item_selected.connect(_changed.unbind(1))
	_turns.item_selected.connect(_changed.unbind(1))
	_copy.toggled.connect(_changed.unbind(1))
	_stamp_controls = VBoxContainer.new()
	_controls.add_child(_stamp_controls)
	_stamp_mode = _stamp_options(["Добавить · занятое сохранить","Заменить · цвет и материал"])
	_stamp_mirror = _stamp_options(["Без отражения","Отразить X","Отразить Y","Отразить Z"])
	_stamp_anchor = _stamp_options(["Опора: нижний угол","Опора: центр основания","Опора: центр объёма"])
	_apply = Button.new()
	_apply.text = "Применить · Enter"
	_apply.pressed.connect(commit)
	_controls.add_child(_apply)
	var cancel := Button.new()
	cancel.text = "Отмена · Esc"
	cancel.pressed.connect(cancel_gesture)
	_controls.add_child(cancel)

func _stamp_options(labels: Array) -> OptionButton:
	var control := OptionButton.new()
	control.fit_to_longest_item = false
	control.clip_text = true
	for label in labels:
		control.add_item(label)
	control.item_selected.connect(_changed.unbind(1))
	_stamp_controls.add_child(control)
	return control

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = color
	return material

func begin_transform() -> void:
	if workspace._selection_panel.busy() or workspace._selection_panel.selected.is_empty():
		return
	cancel_gesture()
	_indices = workspace._selection_panel.selection_indices()
	_start_transform()

func begin_stamp(preset: Resource) -> void:
	if workspace._resource == null:
		return
	cancel_gesture()
	_stamp = preset.duplicate(true)
	_start_transform()
	_stamp_mode.select(0)
	_stamp_mirror.select(0)
	_stamp_anchor.select(clampi(_stamp.anchor,0,2))
	_numbers[0].value = workspace._resource.grid_size().x/2
	_numbers[2].value = workspace._resource.grid_size().z/2
	_changed()
	workspace._set_status("Штамп · ЛКМ задаёт положение · Enter применяет · Esc отменяет")

func _start_transform() -> void:
	_snapshot = workspace._resource.to_definition().duplicate(true)
	_source = workspace._resource
	_source.changed.connect(_source_changed)
	_region = workspace._edit_region_blocks
	_height = workspace._slice_height
	transforming = true
	_syncing = true
	for number in _numbers:
		number.value = 0
	_turns.select(0)
	_copy.set_pressed_no_signal(false)
	_copy.visible = _stamp == null
	_stamp_controls.visible = _stamp != null
	for i in 3:
		_numbers[i].get_parent().get_child(0).text = ("Опора " if _stamp != null else "Сдвиг ")+["X","Y","Z"][i]+" · vox"
	_syncing = false
	_controls.show()
	workspace._selection_panel.move_child(_controls,0 if _stamp != null else workspace._selection_panel.get_child_count()-1)
	var ancestor := _controls.get_parent()
	while ancestor != null and not ancestor is ScrollContainer:
		ancestor = ancestor.get_parent()
	if ancestor is ScrollContainer:
		ancestor.ensure_control_visible.call_deferred(_controls)
	workspace._selection_panel.set_active(true)
	_changed()

func _changed() -> void:
	if _syncing or not transforming:
		return
	if _stamp != null:
		workspace._update_tool_help(workspace._selected_tool_id())
	_offset = Vector3i(int(_numbers[0].value),int(_numbers[1].value),int(_numbers[2].value))
	_pending = true
	_apply.disabled = true

func cancel_gesture() -> void:
	var was_stamp := _stamp != null
	_surface_marquee = null
	_surface_bounds = {}
	_ready_rect = Rect2(-9999,-9999,0,0)
	if _source != null and _source.changed.is_connected(_source_changed):
		_source.changed.disconnect(_source_changed)
	_source = null
	_stamp = null
	if was_stamp and is_instance_valid(workspace):
		workspace._update_tool_help(workspace._selected_tool_id())
	dragging = false
	transforming = false
	_finish = false
	_job = null
	_pending = false
	_arrow_axis = -1
	if is_instance_valid(_ghost):
		_ghost.hide()
	if is_instance_valid(_controls):
		_controls.hide()
	queue_redraw()

func commit() -> void:
	if not transforming or _pending or _apply.disabled:
		return
	_committing = true
	var valid: bool = workspace._resource.to_definition() == _snapshot and workspace._actions.apply_fragment(workspace._resource,_plan)
	_committing = false
	if not valid:
		_hint.text = "Модель изменилась. Отмените и выберите фрагмент заново."
		_apply.disabled = true
		return
	workspace._selection_panel.set_selection(_plan.selected)
	var message := "Штамп применён" if _stamp != null else "Фрагмент применён"
	cancel_gesture()
	workspace._set_status(message + " · Ctrl+Z отменяет · Ctrl+S сохраняет")

func _source_changed() -> void:
	if not _committing:
		cancel_gesture()

func handle(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_S and event.is_command_or_control_pressed() and transforming:
			_hint.text = "Сначала примените операцию (Enter) или отмените её (Esc), затем сохраните."
			return true
		if event.keycode == KEY_ESCAPE and (dragging or _finish or transforming):
			cancel_gesture()
			return true
		if event.keycode == KEY_ENTER and transforming:
			# Let native numeric fields submit their pending text first.
			if workspace.get_viewport().gui_get_focus_owner() is LineEdit:
				return false
			commit()
			return true
	if not workspace._selection_panel.active or workspace._resource == null:
		return false
	if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT and (dragging or _finish):
		cancel_gesture() # Never mix a rectangle query with a changing camera.
	if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT:
		_arrow_axis = -1
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if transforming:
			if event.pressed:
				for axis in 3:
					var segment := _arrow(axis)
					if Geometry2D.get_closest_point_to_segment(event.position,segment[0],segment[1]).distance_to(event.position) < 10:
						_arrow_axis = axis
						_arrow_start = event.position
						_arrow_value = _offset[axis]
						break
				if _stamp != null and _arrow_axis < 0:
					var pick: Dictionary = workspace._pick_at(event.position)
					var cell: Vector3i = pick.get("adjacent",Vector3i(-1,-1,-1)) if _stamp_mode.selected == 0 else pick.get("hit",Vector3i(-1,-1,-1))
					if cell.x >= 0 and cell.y >= 0 and cell.z >= 0:
						for i in 3:
							_numbers[i].value = cell[i]
			else:
				_arrow_axis = -1
			return true
		if workspace._selection_panel._mode.selected not in [3,4]:
			return false
		if event.pressed:
			if workspace._selection_panel.busy():
				return true
			cancel_gesture()
			_gesture_mode = workspace._selection_panel._mode.selected
			_depth = int(workspace._selection_panel._depth.value)
			if _gesture_mode == 4:
				var pick: Dictionary = workspace._pick_at(event.position)
				if not pick.has("hit") or not workspace._cell_in_edit_region(pick.hit):
					workspace._set_status("Начните рамку на грани объекта",true)
					return true
				var ray := _ray(event.position)
				_surface_marquee = SurfaceMarquee.new()
				if not _surface_marquee.begin(pick.hit,ray[0],ray[1],workspace._resource.normalized_density()):
					cancel_gesture()
					workspace._set_status("Не удалось определить грань. Начните ближе к её середине.",true)
					return true
			dragging = true
			_from = event.position
			_to = _from
			_prior = workspace._selection_panel.selected.duplicate()
			_source = workspace._resource
			_source.changed.connect(_source_changed)
			_region = workspace._edit_region_blocks
			_height = workspace._slice_height
			_query_camera = workspace._camera.global_transform
			_query_size = workspace._viewport_container.size
			_query_zoom = workspace._camera.size
			_operation = 2 if event.ctrl_pressed else 1 if event.shift_pressed else workspace._selection_panel._operation.selected
			workspace._set_status(operation_hint() + " · протяните рамку · Esc отменяет")
		else:
			if dragging:
				_to = event.position
				dragging = false
				_finish = true
		queue_redraw()
		return true
	if event is InputEventMouseMotion:
		if transforming and _arrow_axis >= 0:
			var unit := Vector3.ZERO
			unit[_arrow_axis] = 1.0 / workspace._resource.normalized_density()
			var direction := _screen(_center+unit)-_screen(_center)
			if direction.length_squared() > 0.01:
				_numbers[_arrow_axis].value = _arrow_value + roundi((event.position-_arrow_start).dot(direction)/direction.length_squared())
			return true
		if dragging:
			_to = event.position
			queue_redraw()
			return true
	return false

func _process(_delta: float) -> void:
	if workspace == null:
		return
	if not workspace.is_visible_in_tree() or not workspace._selection_panel.active:
		cancel_gesture()
		_hover.hide()
		return
	if (transforming or dragging or _finish) and workspace._resource != _source:
		cancel_gesture()
		return
	if (transforming or dragging or _finish) and (_region != workspace._edit_region_blocks or _height != workspace._slice_height):
		cancel_gesture()
		return
	if (dragging or _finish) and (_query_camera != workspace._camera.global_transform or _query_size != workspace._viewport_container.size or _query_zoom != workspace._camera.size):
		cancel_gesture()
		return
	if (dragging or _finish) and (workspace._selection_panel._mode.selected != _gesture_mode or (_gesture_mode == 4 and int(workspace._selection_panel._depth.value) != _depth)):
		cancel_gesture()
		return
	workspace._cursor.hide()
	if _stamp != null and (workspace._selection_panel._mask.button_pressed or workspace._groups_panel.isolation_enabled() or not workspace._hidden_group_indices.is_empty()):
		cancel_gesture()
		workspace._set_status("Отпечаток отменён: изменена маска или видимость групп.",true)
		return
	if _stamp != null and _stamp_part != workspace._actions.active_part:
		_stamp_part = workspace._actions.active_part
		_changed()
	if dragging or _finish:
		if _surface_marquee != null:
			var ray := _ray(_to)
			_surface_bounds = _surface_marquee.bounds(ray[0],ray[1],_depth)
			if _surface_bounds.has("error"):
				workspace._set_status(_surface_bounds.error,true)
				cancel_gesture()
				return
		var rect := Rect2(_from,_to-_from).abs()
		if rect.size.x < 3 or rect.size.y < 3:
			rect = Rect2(_to-Vector2(3,3),Vector2(6,6))
		if dragging and _job == null and rect == _ready_rect:
			return
		if _job == null:
			var query_source: EmberVoxelModelResource = workspace._isolation_resource if workspace._isolation_resource != null else workspace._resource
			if _surface_marquee != null:
				_job = Selection.new()
				_job.start_box(query_source,_surface_bounds.low,_surface_bounds.high,workspace._edit_region_blocks,workspace._slice_height)
			else:
				_job = Gesture.new()
				_job.source = query_source
				_job.camera = workspace._camera
				_job.rectangle = rect
				_job.viewport_scale = Vector2(workspace._viewport.size)/workspace._viewport_container.size
				_job.through = workspace._selection_panel._through.selected == 1
				_job.region = workspace._edit_region_blocks
				_job.height = workspace._slice_height
			_job_rect = rect
			workspace._set_status(operation_hint() + " · поиск в рамке… Esc отменяет; геометрия не меняется")
		var deadline := Time.get_ticks_usec()+3000
		while not _job.done and Time.get_ticks_usec() < deadline:
			_job.step(32)
		if _job.done:
			if _job_rect == rect:
				var failure: String = _job.error
				_ready_rect = rect
				workspace._set_status(_job.error if not _job.error.is_empty() else operation_hint() + " · в рамке: %d vox · отпустите мышь" % _job.indices.size())
				if _job.error.is_empty():
					_show_cells(_job.indices,Color(0.1,1,1,0.5))
					if _finish:
						var combined := Selection.combine(_prior,_job.indices,_operation)
						if combined.size() <= Selection.LIMIT:
							workspace._selection_panel.set_selection(PackedInt32Array(combined.keys()))
						else:
							failure = "Суммарное выделение превышает лимит; прежнее сохранено"
				if _finish:
					cancel_gesture()
					workspace._set_status(failure if not failure.is_empty() else "Выделено: %d vox · переносите стрелками через «Перенос / копия / поворот…»" % workspace._selection_panel.selected.size(),not failure.is_empty())
			_job = null
	elif transforming and _pending:
		_pending = false
		if _stamp == null:
			_plan = Fragment.plan(workspace._resource,_indices,_offset,_axis.selected,_turns.selected,_copy.button_pressed,workspace._edit_region_blocks,workspace._slice_height)
		else:
			_plan = Stamp.plan(workspace._resource,_stamp,_offset,_axis.selected,_turns.selected,_stamp_mirror.selected-1,_stamp_anchor.selected,_stamp_mode.selected == 1,workspace._actions.active_part,workspace._edit_region_blocks,workspace._slice_height)
		_apply.disabled = _plan.has("error")
		_hint.text = _plan.get("error","Тяните стрелки X/Y/Z. Enter применяет, Esc отменяет. Оранжевое — исходное, голубое — результат.")
		if _stamp != null and not _plan.has("error"):
			_hint.text = "Штамп: "+_stamp.display_name+". ЛКМ — опора, стрелки/числа — сдвиг. Enter — отпечаток, Esc — отмена. Пустоты не стирают."
		_show_transform()
	var mouse: Vector2 = workspace._viewport_container.get_local_mouse_position()
	_hover.visible = not dragging and not _finish and not transforming and Rect2(Vector2.ZERO,size).has_point(mouse)
	if _hover.visible:
		var pick: Dictionary = workspace._pick_at(mouse)
		_hover.visible = pick.has("hit") and workspace._cell_in_edit_region(pick.hit)
		if _hover.visible:
			var density := float(workspace._resource.normalized_density())
			_hover.position = Vector3(pick.hit)/density-Vector3.ONE*0.002/density
			_hover.scale = Vector3.ONE*1.004/density
	queue_redraw()

func _show_cells(indices: PackedInt32Array, color: Color) -> void:
	var cells: Array[Vector3] = []
	for index in indices:
		cells.append(Vector3(Selection.cell_of(index,workspace._resource.grid_size())))
	_show_positions(cells,color)

func _show_positions(cells: Array[Vector3], color: Color, colors := PackedColorArray()) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = not colors.is_empty()
	var mesh := BoxMesh.new()
	var density := float(workspace._resource.normalized_density())
	mesh.size = Vector3.ONE*1.01/density
	mesh.material = _material(color)
	mesh.material.vertex_color_use_as_albedo = not colors.is_empty()
	multi.mesh = mesh
	multi.instance_count = cells.size()
	for index in cells.size():
		multi.set_instance_transform(index,Transform3D(Basis.IDENTITY,(cells[index]+Vector3.ONE*0.5)/density))
		if not colors.is_empty():
			multi.set_instance_color(index,colors[index])
	_ghost.multimesh = multi
	_ghost.show()

func _show_transform() -> void:
	if _stamp != null:
		_show_stamp()
		return
	var low := workspace._resource.grid_size() as Vector3i
	var high := Vector3i.ZERO
	for index in _indices:
		var cell := Selection.cell_of(index,workspace._resource.grid_size())
		low = low.min(cell)
		high = high.max(cell)
	var cells: Array[Vector3] = []
	for index in _indices:
		var cell := Selection.cell_of(index,workspace._resource.grid_size())-low
		var extent := high-low+Vector3i.ONE
		for turn in _turns.selected:
			var transformed := Fragment.rotate_cell(cell,extent,_axis.selected)
			cell = transformed.cell
			extent = transformed.extent
		cells.append(Vector3(cell+low+_offset))
	_center = (Vector3(low+high)*0.5+Vector3(_offset)+Vector3.ONE*0.5)/workspace._resource.normalized_density()
	_show_positions(cells,Color(1,0.15,0.15,0.5) if _plan.has("error") else Color(0.1,1,1,0.5))

func _show_stamp() -> void:
	var cells: Array[Vector3] = []
	var colors := PackedColorArray()
	_center = (Vector3(_offset)+Vector3.ONE*0.5)/workspace._resource.normalized_density()
	if _plan.has("error"):
		cells.assign(_plan.get("positions",[]))
		_show_positions(cells,Color(1,0.15,0.15,0.5))
		return
	var values: PackedByteArray = _plan.properties.get("voxels",workspace._resource.voxels)
	var palette: PackedColorArray = _plan.properties.get("palette",workspace._resource.palette)
	for index in _plan.selected:
		cells.append(Vector3(Selection.cell_of(index,workspace._resource.grid_size())))
		colors.append(palette[values[index]])
	_show_positions(cells,Color(1,1,1,0.8),colors)

func _screen(point: Vector3) -> Vector2:
	return workspace._camera.unproject_position(point)*workspace._viewport_container.size/Vector2(workspace._viewport.size)

func _ray(point: Vector2) -> Array[Vector3]:
	var pixel: Vector2 = point*Vector2(workspace._viewport.size)/workspace._viewport_container.size
	return [workspace._camera.project_ray_origin(pixel),workspace._camera.project_ray_normal(pixel)]

func _arrow(axis: int) -> PackedVector2Array:
	var unit := Vector3.ZERO
	unit[axis] = 1
	var start := _screen(_center)
	var direction := (_screen(_center+unit)-start).normalized()
	return PackedVector2Array([start+direction*16,start+direction*90])

func _draw() -> void:
	if dragging or _finish:
		var label := operation_hint()
		var width := ThemeDB.fallback_font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x + 24
		draw_rect(Rect2(8,8,width,32),Color(0.04,0.08,0.12,0.95))
		draw_string(ThemeDB.fallback_font,Vector2(20,31),label,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color(0.3,1,1))
	if is_instance_valid(_hover) and _hover.visible:
		var box := AABB(Vector3.ZERO,Vector3.ONE)
		for edge in [[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]]:
			draw_line(_screen(_hover.transform*box.get_endpoint(edge[0])),_screen(_hover.transform*box.get_endpoint(edge[1])),Color(0.1,1,1),2,true)
	if (dragging or _finish) and _surface_marquee != null and _surface_bounds.has("box"):
		var box: AABB = _surface_bounds.box
		for edge in [[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]]:
			draw_line(_screen(box.get_endpoint(edge[0])),_screen(box.get_endpoint(edge[1])),Color(0.1,1,1),2,true)
	elif dragging or _finish:
		var rectangle := Rect2(_from,_to-_from).abs()
		draw_rect(rectangle,Color(0.1,0.9,1,0.12),true)
		draw_rect(rectangle,Color(0.1,1,1),false,2)
	if transforming:
		for axis in 3:
			var points := _arrow(axis)
			var color: Color = [Color(1,0.3,0.3),Color(0.3,1,0.4),Color(0.4,0.7,1)][axis]
			draw_line(points[0],points[1],color,4,true)
			var direction := (points[1]-points[0]).normalized()
			draw_colored_polygon(PackedVector2Array([points[1],points[1]-direction.rotated(0.5)*14,points[1]-direction.rotated(-0.5)*14]),color)
			draw_string(ThemeDB.fallback_font,points[1]+Vector2(5,-5),["X","Y","Z"][axis],HORIZONTAL_ALIGNMENT_LEFT,-1,18,color)

func _exit_tree() -> void:
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	if is_instance_valid(_hover):
		_hover.queue_free()
