@tool
extends Node
## Native 3D input/UI adapter for the existing sculpt model, actions and sessions.
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Actions = preload("res://addons/ember_import/ember_voxel_sculpt_actions.gd")
const Sessions = preload("res://addons/ember_import/ember_world_edit_sessions.gd")
const Fragment = preload("res://addons/ember_import/ember_voxel_fragment.gd")
const SETTINGS := "user://ember_world_editor.cfg"
var sessions := Sessions.new()
var actions := Actions.new()
var plugin: EditorPlugin
var active := false
var entry := {}
var scene: Node3D
var map: EmberMapLoader
var toolbar: HBoxContainer
var sidebar: PanelContainer
var enabled: Button
var target_choice: OptionButton
var category: OptionButton
var tools: OptionButton
var radius: SpinBox
var depth: SpinBox
var plane_height: SpinBox
var water_height: SpinBox
var shore_width: SpinBox
var softness: SpinBox
var shore_direction: OptionButton
var palette: OptionButton
var sand_palette: OptionButton
var clip: CheckBox
var hide_water: CheckBox
var status: Label
var scope_label: Label
var favorites_box: VBoxContainer
var library_favorites: HFlowContainer
var library_favorites_panel: VBoxContainer
var object_parameters: VBoxContainer
var advanced: VBoxContainer
var close_dialog: ConfirmationDialog
var recent_objects: PackedStringArray = []
var favorite_objects: PackedStringArray = []
var camera: Camera3D
var hover := {}
var edit_region := Rect2i()
var selecting := false
var create_region := false
var region_anchor := Vector2i(-1,-1)
var region_preview := Rect2i()
var picking_object := false
var dragging := false
var released := false
var baseline: EmberVoxelModelResource
var delta := {}
var queue: Array[Dictionary] = []
var job: RefCounted
var top_cache := {}
var amount_cache := {}
var last_cell := Model.INVALID_CELL
var stroke_mode := ""
var stroke_radius := 16
var stroke_depth := 4
var stroke_palette := 1
var stroke_options := {}
var grab := {}
var stroke_started := 0
var last_stroke_usec := 0
var last_history_bytes := 0
var _focusing := false
var _background_water: Array[WeakRef] = []
var _recovery_due := 0
var _last_recovery := 0
var _target_buttons: Array[Button] = []

func _set_busy(value: bool) -> void:
	for control in [target_choice,category,tools,palette,sand_palette,clip,shore_direction]:
		if is_instance_valid(control): control.disabled = value
	for control in [radius,depth,plane_height,water_height,shore_width,softness]:
		if is_instance_valid(control): control.editable = not value
	for button in _target_buttons:
		if is_instance_valid(button): button.disabled = value

func _set_working_water(hidden: bool) -> void:
	sessions.set_water_hidden(hidden)
	if scene == null: return
	var nodes: Array[Node] = [scene]
	while not nodes.is_empty():
		var node := nodes.pop_back()
		for child in node.get_children(): nodes.append(child)
		if node is MeshInstance3D and node.mesh != null:
			for surface_index in node.mesh.get_surface_count():
				var material: Material = node.get_active_material(surface_index)
				if material is ShaderMaterial and material.get_shader_parameter("background_water") == true:
					RenderingServer.instance_set_visible(node.get_instance(),node.is_visible_in_tree() and not hidden)
					if hidden: _background_water.append(weakref(node))
	if not hidden: _background_water.clear()

func configure(owner_plugin: EditorPlugin, history: Object) -> void:
	plugin = owner_plugin
	sessions.configure(history,_save_native_scene)
	actions.configure(history)
	sessions.changed.connect(_refresh_dirty_status)
	sessions.changed.connect(func(): _recovery_due = Time.get_ticks_msec()+10000)
	var config := ConfigFile.new()
	if config.load(SETTINGS) == OK:
		recent_objects = config.get_value("objects","recent",PackedStringArray())
		favorite_objects = config.get_value("objects","favorites",PackedStringArray())
	set_process(true)
	set_process_input(true)

func build_toolbar() -> Control:
	toolbar = HBoxContainer.new()
	enabled = Button.new()
	enabled.text = "Редактировать мир"
	enabled.toggle_mode = true
	enabled.toggled.connect(_toggle)
	toolbar.add_child(enabled)
	return toolbar

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	if parent != object_parameters and parent != favorites_box and "Сохранить" not in text: _target_buttons.append(button)
	return button

func _choice(parent: Node, items: Array[String]) -> OptionButton:
	var choice := OptionButton.new()
	for item in items: choice.add_item(item)
	parent.add_child(choice)
	return choice

func _spin(parent: Node, title: String, minimum: float, maximum: float, initial: float, step := 1.0) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = initial
	spin.custom_minimum_size.x = 95
	row.add_child(spin)
	return spin

func build_sidebar() -> Control:
	sidebar = PanelContainer.new()
	sidebar.custom_minimum_size.x = 270
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 260
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var title := Label.new()
	title.text = "EMBER · РЕДАКТОР МИРА"
	box.add_child(title)
	target_choice = _choice(box,["Земля карты","Выбранный объект · уникальная правка"])
	target_choice.item_selected.connect(_target_changed)
	_button(box,"Выбрать объект в сцене",func(): picking_object = true; _status("Нажмите на voxel-объект в сцене. Остальные экземпляры не изменятся."))
	_button(box,"Открыть цель в Canvas",open_canvas)
	_button(box,"Создать землю · выделить место",func():
		cancel_stroke()
		target_choice.select(0)
		_target_changed(0)
		selecting = true
		create_region = true
		region_anchor = Vector2i(-1,-1)
		_status("Потяните прямоугольник рядом с готовым берегом. Создание не меняет остальные объекты.")
	)
	category = _choice(box,["Форма","Покраска","Вода","Объекты"])
	category.item_selected.connect(_category_changed)
	tools = _choice(box,[])
	tools.item_selected.connect(func(_index): cancel_stroke(); _tool_changed())
	palette = _choice(box,[])
	sand_palette = _choice(box,[])
	palette.item_selected.connect(func(_index): cancel_stroke())
	sand_palette.item_selected.connect(func(_index): cancel_stroke())
	advanced = VBoxContainer.new()
	box.add_child(advanced)
	plane_height = _spin(advanced,"Плоскость · мир",-512,512,0)
	water_height = _spin(advanced,"Вода · мир",-512,512,-8)
	shore_width = _spin(advanced,"Длина спуска · блоки",0.25,16,6,0.25)
	shore_direction = _choice(advanced,["Глубже · +X","Глубже · −X","Глубже · +Z","Глубже · −Z"])
	softness = _spin(advanced,"Мягкость · %",0,100,75)
	for parameter in [plane_height,water_height,shore_width,softness]:
		parameter.value_changed.connect(func(_value): cancel_stroke())
	shore_direction.item_selected.connect(func(_index): cancel_stroke())
	scope_label = Label.new()
	scope_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(scope_label)
	_button(box,"Ограничить участок",func(): cancel_stroke(); selecting = true; create_region = false; region_anchor = Vector2i(-1,-1); _status("Потяните прямоугольник рабочей области."))
	_button(box,"Вся поверхность",func(): cancel_stroke(); edit_region = Rect2i(); _refresh_scope())
	clip = CheckBox.new()
	clip.text = "Обрезать по границе"
	clip.button_pressed = true
	box.add_child(clip)
	clip.toggled.connect(func(_value): cancel_stroke())
	hide_water = CheckBox.new()
	hide_water.text = "Рабочий вид · скрыть воду"
	box.add_child(hide_water)
	hide_water.toggled.connect(_set_working_water)
	object_parameters = VBoxContainer.new()
	box.add_child(object_parameters)
	for spec in [["Шаг · блоки","spacing_blocks",0.05,64,1,0.05],["Поворот Y","yaw_degrees",-180,180,0,1],["Масштаб","scale_factor",0.05,10,1,0.05],["Заглубление · vox","bury_vox",-64,64,0,0.5]]:
		var control := _spin(object_parameters,spec[0],spec[2],spec[3],spec[4],spec[5])
		var property: String = spec[1]
		control.value_changed.connect(func(value):
			if plugin != null and is_instance_valid(plugin._object_brush): plugin._object_brush.set(property,value)
		)
	_button(object_parameters,"Библиотека объектов",func(): if plugin != null: plugin._open_voxel_object_library())
	_button(object_parameters,"★ Закрепить текущий объект",func():
		if plugin != null and plugin._object_brush.model_id != "":
			var id: String = plugin._object_brush.model_id
			if id not in favorite_objects: favorite_objects.append(id)
			_save_settings()
			_refresh_favorites()
	)
	var shelf := Button.new()
	shelf.text = "Избранное / последние ▾"
	shelf.toggle_mode = true
	shelf.button_pressed = true
	box.add_child(shelf)
	favorites_box = VBoxContainer.new()
	box.add_child(favorites_box)
	shelf.toggled.connect(func(value): favorites_box.visible = value)
	if plugin != null and is_instance_valid(plugin._object_library):
		library_favorites_panel = VBoxContainer.new()
		plugin._object_library.add_child(library_favorites_panel)
		plugin._object_library.move_child(library_favorites_panel,1)
		var fold := _button(library_favorites_panel,"Мир · избранное и последние ▾",func(): library_favorites.visible = not library_favorites.visible)
		fold.alignment = HORIZONTAL_ALIGNMENT_LEFT
		library_favorites = HFlowContainer.new()
		library_favorites_panel.add_child(library_favorites)
		library_favorites_panel.hide()
	_refresh_favorites()
	_button(box,"Сохранить всё · Ctrl+S",save_all)
	_button(box,"Восстановить аварийные черновики",func():
		if scene != null: _status("Восстановлено: %d. %s" % [sessions.restore_recovery(scene),sessions.error])
	)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 250
	box.add_child(status)
	var parameters := HBoxContainer.new()
	toolbar.add_child(parameters)
	radius = _spin(parameters,"Радиус · блоки",0.0625,8,1,0.0625)
	depth = _spin(parameters,"Глубина · vox",1,32,4)
	radius.value_changed.connect(func(_value): cancel_stroke(); _update_overlay())
	depth.value_changed.connect(func(_value): cancel_stroke())
	close_dialog = ConfirmationDialog.new()
	close_dialog.title = "Черновики редактора мира"
	close_dialog.dialog_text = "Есть несохранённая земля или объекты. Сохранить всё перед выходом?"
	close_dialog.ok_button_text = "Сохранить и выйти"
	close_dialog.add_button("Отменить изменения и выйти",false,"discard")
	close_dialog.confirmed.connect(func(): if save_all(): _deactivate())
	close_dialog.custom_action.connect(func(action): if action == "discard": sessions.discard(scene); close_dialog.hide(); _deactivate())
	close_dialog.canceled.connect(func(): enabled.set_pressed_no_signal(true))
	add_child(close_dialog)
	_category_changed(0)
	sidebar.hide()
	parameters.hide()
	return sidebar

func _status(message: String) -> void:
	if is_instance_valid(status): status.text = message

func _refresh_dirty_status() -> void:
	if is_instance_valid(enabled): enabled.text = "Редактировать мир%s" % (" · %d*" % sessions.dirty_count(scene) if sessions.dirty_count(scene) > 0 else "")
	_update_overlay()

func _toggle(value: bool) -> void:
	if not value:
		cancel_stroke()
		if sessions.dirty_count(scene) > 0:
			enabled.set_pressed_no_signal(true)
			close_dialog.popup_centered(Vector2i(530,180))
			return
		_deactivate()
		return
	active = true
	if is_instance_valid(library_favorites_panel): library_favorites_panel.show()
	sidebar.show()
	toolbar.get_child(1).show()
	if plugin != null:
		plugin._stop_scene_object_brush()
		plugin._voxel_object_toolbar.hide()
		plugin._world_surface_toolbar.hide()
		plugin._battlefield_toolbar.hide()
		plugin._world_surface_selector._select_button.set_pressed_no_signal(false)
		plugin._battlefield_painter._enabled.set_pressed_no_signal(false)
		if is_instance_valid(plugin._walk_surface_panel) and plugin._walk_surface_panel.get("_brush") != null: plugin._walk_surface_panel._brush.select(0)
		scene_changed(EditorInterface.get_edited_scene_root())
	for current in sessions.entries.values():
		if current.scene.get_ref() == scene: sessions.preview(current)

func _deactivate() -> void:
	_set_working_water(false)
	active = false
	if is_instance_valid(library_favorites_panel): library_favorites_panel.hide()
	enabled.set_pressed_no_signal(false)
	sidebar.hide()
	toolbar.get_child(1).hide()
	selecting = false
	picking_object = false
	hover.clear()
	if plugin != null:
		plugin._stop_scene_object_brush()
		plugin._voxel_object_toolbar.show()
		plugin._world_surface_toolbar.show()
		plugin._battlefield_toolbar.show()
	for current in sessions.entries.values():
		var target: Node = current.target.get_ref()
		sessions._show_originals(current,true)
		if target is EmberMapLoader: target.set_editor_surface_preview(null)
		if is_instance_valid(current.preview): current.preview.free(); current.preview = null
	_update_overlay()

func scene_changed(root: Node) -> void:
	for reference in _background_water:
		var node: MeshInstance3D = reference.get_ref()
		if is_instance_valid(node): RenderingServer.instance_set_visible(node.get_instance(),node.is_visible_in_tree())
	_background_water.clear()
	cancel_stroke()
	sessions.write_recovery()
	scene = root as Node3D
	map = root as EmberMapLoader if root is EmberMapLoader else root.find_child("Map",true,false) as EmberMapLoader if root != null else null
	entry = {}
	edit_region = Rect2i()
	if active: _target_changed(target_choice.selected)

func _target_changed(index: int) -> void:
	cancel_stroke()
	create_region = false
	selecting = false
	if not entry.is_empty(): entry.scope = edit_region
	entry = {}
	if scene == null or map == null:
		_status("Откройте сцену Ember с узлом Map.")
		return
	if index == 0:
		entry = sessions.open_map(map,scene)
	else:
		var selection := EditorInterface.get_selection().get_selected_nodes() if Engine.is_editor_hint() else []
		if selection.size() == 1 and selection[0] is EmberVoxelProp: entry = sessions.open_object(selection[0],scene)
		else: picking_object = true
	if not entry.is_empty():
		edit_region = entry.get("scope",Rect2i())
		actions.history_context = scene
		sessions.preview(entry)
		_refresh_palette()
		_status("%s · один мазок — одно Undo · Ctrl+S сохраняет всё" % entry.resource.display_name)
	else: _status(sessions.error if index == 0 else "Выберите voxel-объект кнопкой или нажмите на него в сцене.")
	if hide_water.button_pressed: _set_working_water(true)
	_refresh_scope()
	_tool_changed()

func _category_changed(index: int) -> void:
	cancel_stroke()
	if plugin != null: plugin._stop_scene_object_brush()
	tools.clear()
	var names: Array = [["Поднять","Опустить","Лепка · добавить","Лепка · убрать","Сгладить","Площадка","Берег и дно","Генератор рельефа","Тянуть · мягко"],["Покрасить","Песок · крупные пятна"],["Вода · открытый уровень","Убрать воду"],["Расстановка объектов"]][index]
	var modes: Array = [["raise","lower","add","remove","smooth","level","shore","generator","grab"],["paint","sand"],["water","dry"],["objects"]][index]
	for i in names.size(): tools.add_item(names[i]); tools.set_item_metadata(i,modes[i])
	object_parameters.visible = index == 3
	_tool_changed()

func _mode() -> String:
	return str(tools.get_selected_metadata()) if tools.selected >= 0 else "raise"

func _tool_changed() -> void:
	if not is_instance_valid(palette): return
	palette.visible = category.selected != 3
	sand_palette.visible = _mode() == "sand"
	plane_height.get_parent().visible = category.selected != 3
	water_height.get_parent().visible = category.selected == 2
	shore_width.get_parent().visible = _mode() == "shore"
	shore_direction.visible = _mode() == "shore"
	softness.get_parent().visible = _mode() == "grab"

func _refresh_palette() -> void:
	if entry.is_empty(): return
	radius.min_value = 1.0/entry.resource.normalized_density()
	radius.step = radius.min_value
	for choice in [palette,sand_palette]:
		choice.clear()
		for index in range(1,entry.resource.palette.size()):
			var color: Color = entry.resource.palette[index]
			choice.add_item("Цвет %d · #%s" % [index,color.to_html(false)])
			choice.set_item_metadata(choice.item_count-1,index)
	if sand_palette.item_count > 2: sand_palette.select(2)

func _refresh_scope() -> void:
	if is_instance_valid(scope_label): scope_label.text = "Участок: %s" % edit_region if edit_region.has_area() else "Вся доступная поверхность"
	_update_overlay()

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("objects","recent",recent_objects)
	config.set_value("objects","favorites",favorite_objects)
	config.save(SETTINGS)

func remember_object(id: String) -> void:
	if id in recent_objects: recent_objects.remove_at(recent_objects.find(id))
	recent_objects.insert(0,id)
	if recent_objects.size() > 6: recent_objects.resize(6)
	_save_settings()
	_refresh_favorites()
	category.select(3)
	tools.clear()
	tools.add_item("Расстановка объектов")
	tools.set_item_metadata(0,"objects")
	object_parameters.show()
	_tool_changed()
	_status("Кисть объекта: %s. Выбор сохраняется между мазками." % id)

func _refresh_favorites() -> void:
	if not is_instance_valid(favorites_box): return
	for child in favorites_box.get_children(): child.queue_free()
	if is_instance_valid(library_favorites):
		for child in library_favorites.get_children(): child.queue_free()
	var ids := favorite_objects.duplicate()
	for id in recent_objects:
		if id not in ids: ids.append(id)
	for id in ids:
		if is_instance_valid(library_favorites):
			var shortcut := _button(library_favorites,("★ " if id in favorite_objects else "")+id,func(): plugin._activate_object_brush(id))
			shortcut.tooltip_text = id
			shortcut.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			shortcut.custom_minimum_size.x = 150
			shortcut.text = shortcut.text.left(30)
		var row := HBoxContainer.new()
		favorites_box.add_child(row)
		var pick := _button(row,("★ " if id in favorite_objects else "")+id,func():
			if plugin != null: plugin._activate_object_brush(id)
		)
		pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		pick.custom_minimum_size.x = 205
		if id in favorite_objects:
			_button(row,"×",func(): favorite_objects.remove_at(favorite_objects.find(id)); _save_settings(); _refresh_favorites())

func open_canvas() -> void:
	if entry.is_empty() or plugin == null: return
	cancel_stroke()
	var workspace := EditorInterface.get_editor_main_screen().find_child(plugin.SURFACE_WORKSPACE_NODE,true,false) as EmberVoxelSculptWorkspace
	if workspace != null and workspace.open_world_draft(entry,sessions,save_all): EditorInterface.set_main_screen_editor(plugin.SURFACE_MAIN_SCREEN)

func _save_native_scene() -> int:
	return EditorInterface.save_scene() if Engine.is_editor_hint() else OK

func save_all(defer_scene_save := false) -> bool:
	var workspace: EmberVoxelSculptWorkspace
	if Engine.is_editor_hint() and plugin != null:
		workspace = EditorInterface.get_editor_main_screen().find_child(plugin.SURFACE_WORKSPACE_NODE,true,false) as EmberVoxelSculptWorkspace
		if workspace != null and not workspace._world_entry.is_empty() and (workspace._stroke_active or (workspace._grab_interaction != null and workspace._grab_interaction.active)):
			var message := "Завершите мазок Canvas или отмените его Esc перед общим сохранением."
			_status(message)
			workspace._set_status(message,true)
			return false
		if workspace != null and not workspace._world_entry.is_empty() and workspace.visible and workspace._generator_active() and workspace._generator_panel.creation != null:
			var message := "Предпросмотр нового варианта ещё не объект карты. Сохраните его кнопкой генератора «Сохранить вариацию и поставить» или снимите предпросмотр."
			_status(message)
			workspace._set_status(message,true)
			return false
		if workspace != null and not workspace._world_entry.is_empty(): workspace._commit_object_name()
	if dragging or job != null or not grab.is_empty() or (plugin != null and plugin._object_brush._dragging):
		_status("Завершите мазок или отмените его Esc перед сохранением.")
		return false
	if scene == null: return false
	var saved := sessions.save_all(scene,defer_scene_save)
	_status("Завершаю штатное сохранение сцены…" if saved and defer_scene_save else "Карта и изменённые объекты сохранены." if saved else "Сохранение остановлено: " + sessions.error)
	if saved and defer_scene_save: saved = _finish_native_scene_save()
	if workspace != null and not workspace._world_entry.is_empty(): workspace._set_status("Карта и изменённые объекты сохранены." if saved else sessions.error,not saved)
	if not saved and Engine.is_editor_hint(): EditorInterface.mark_scene_as_unsaved()
	return saved

func _finish_native_scene_save() -> bool:
	if sessions.pending_native_save.is_empty(): return false
	var pending: Dictionary = sessions.pending_native_save
	var root: Node = pending.root.get_ref()
	# Godot has already saved/marked its scene in the native external-data hook.
	# Publish the updated owned native PackedScene, not a second recursive editor
	# Save/progress task. This also handles Save-and-close without touching the
	# newly active scene. No custom scene format or second map owner is involved.
	var packed: PackedScene = pending.packed
	packed.take_over_path(pending.path)
	var result := ResourceSaver.save(packed,pending.path,ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS)
	var saved := sessions.finish_native_save(result)
	_status("Карта и изменённые объекты сохранены." if saved else sessions.error)
	if not saved and is_instance_valid(root) and EditorInterface.get_edited_scene_root() == root: EditorInterface.mark_scene_as_unsaved()
	return saved

func _input(event: InputEvent) -> void:
	# Global save is intentionally independent of viewport/text focus. Brush
	# shortcuts remain exclusively in forward_input and never consume text input.
	if Engine.is_editor_hint() and event is InputEventKey and event.pressed and not event.echo and event.is_command_or_control_pressed() and event.keycode == KEY_S and is_instance_valid(scene) and sessions.dirty_count(scene) > 0:
		save_all()
		get_viewport().set_input_as_handled()
	elif Engine.is_editor_hint() and plugin != null and event is InputEventKey and event.pressed and not event.echo and event.is_command_or_control_pressed() and event.keycode == KEY_S and is_instance_valid(scene):
		var workspace := EditorInterface.get_editor_main_screen().find_child(plugin.SURFACE_WORKSPACE_NODE,true,false) as EmberVoxelSculptWorkspace
		if workspace != null and workspace.visible and not workspace._world_entry.is_empty():
			save_all()
			get_viewport().set_input_as_handled()

func unsaved_status(for_scene: String) -> String:
	var count := 0
	for current in sessions.entries.values():
		var root: Node = current.scene.get_ref()
		if sessions.dirty(current) and (for_scene == "" or (is_instance_valid(root) and root.scene_file_path == for_scene)): count += 1
	return "Редактор мира: %d несохранённых черновиков." % count if count > 0 else ""

func _update_overlay() -> void:
	if plugin != null: plugin.update_overlays()

func _pick(position: Vector2) -> Dictionary:
	if entry.is_empty() or camera == null: return {}
	var frame: Transform3D = sessions.frame(entry)
	if is_zero_approx(frame.basis.determinant()): return {}
	var inverse := frame.affine_inverse()
	var origin: Vector3 = inverse * camera.project_ray_origin(position)
	var direction: Vector3 = inverse.basis * camera.project_ray_normal(position)
	var result := Model.pick(entry.resource,origin,direction)
	if result.is_empty():
		var local_height: float = (plane_height.value-entry.origin.y) / (map.imported_tile_size if entry.target.get_ref() is EmberMapLoader else maxf(frame.basis.y.length(),0.001))
		var point = Plane(Vector3.UP,local_height).intersects_ray(origin,direction)
		if point != null:
			var cell := Vector3i(Vector3(point) * entry.resource.normalized_density())
			if Model.contains(cell,entry.resource.grid_size()): result = {"hit":Model.INVALID_CELL,"adjacent":cell,"normal":Vector3i.UP,"empty_floor":true}
	return result

func _region_frame() -> Transform3D:
	return map.global_transform*Transform3D(Basis.IDENTITY*map.imported_tile_size,Vector3.ZERO) if create_region or entry.is_empty() else sessions.frame(entry)

func _region_height() -> float:
	var frame := _region_frame()
	return (plane_height.value-frame.origin.y)/maxf(frame.basis.y.length(),0.001)

func _plane_cell(position: Vector2) -> Vector2i:
	if map == null or camera == null: return Vector2i(-1,-1)
	var inverse := _region_frame().affine_inverse()
	var point = Plane(Vector3.UP,_region_height()).intersects_ray(inverse * camera.project_ray_origin(position),inverse.basis * camera.project_ray_normal(position))
	if point == null: return Vector2i(-1,-1)
	var cell := Vector2i(floori(point.x),floori(point.z))
	var footprint: Vector2i = map.authored_size_blocks if create_region or entry.is_empty() else Vector2i(entry.resource.size_blocks.x,entry.resource.size_blocks.z)
	return cell if cell.x >= 0 and cell.y >= 0 and cell.x < footprint.x and cell.y < footprint.y else Vector2i(-1,-1)

func _pick_object(position: Vector2) -> void:
	cancel_stroke()
	var origin := camera.project_ray_origin(position)
	var ray := PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(position)*camera.far)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(ray)
	var node: Node = hit.get("collider")
	while node != null and not node is EmberVoxelProp: node = node.get_parent()
	if node is EmberVoxelProp and scene.is_ancestor_of(node):
		if not entry.is_empty(): entry.scope = edit_region
		entry = sessions.open_object(node,scene)
		if not entry.is_empty():
			edit_region = entry.get("scope",Rect2i())
			target_choice.select(1)
			picking_object = false
			actions.history_context = scene
			_refresh_palette()
			_status("Правим только %s · остальные экземпляры защищены" % node.name)
			_refresh_scope()
	else: _status("Нужен voxel-объект. Простые 3D-формы автоматически не преобразуются.")

func forward_input(next_camera: Camera3D, event: InputEvent) -> int:
	if not active: return EditorPlugin.AFTER_GUI_INPUT_PASS
	camera = next_camera
	if event is InputEventKey and (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)): return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.alt_pressed: return EditorPlugin.AFTER_GUI_INPUT_PASS
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit: return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_command_or_control_pressed() and event.keycode == KEY_S:
			save_all()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_ESCAPE:
			cancel_stroke()
			selecting = false
			picking_object = false
			region_preview = Rect2i()
			_update_overlay()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode in [KEY_BRACKETLEFT,KEY_BRACKETRIGHT]:
			if dragging or not grab.is_empty(): return EditorPlugin.AFTER_GUI_INPUT_STOP
			radius.value += radius.step * (-1 if event.keycode == KEY_BRACKETLEFT else 1)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_F and not event.is_command_or_control_pressed() and not hover.is_empty():
			_focus_cursor()
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if event.is_command_or_control_pressed() and event.keycode in [KEY_Z,KEY_Y]: cancel_stroke()
	if event is InputEventMouse and (event.alt_pressed or event.button_mask & (MOUSE_BUTTON_MASK_RIGHT|MOUSE_BUTTON_MASK_MIDDLE)):
		if not released or not grab.is_empty(): cancel_stroke()
		hover.clear()
		_update_overlay()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
		if not released or not grab.is_empty(): cancel_stroke()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if category.selected == 3 and not selecting and not picking_object:
		return plugin._object_brush.forward_input(camera,event) if plugin != null else EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion:
		if selecting:
			var cell := _plane_cell(event.position)
			if region_anchor.x >= 0 and cell.x >= 0: region_preview = Rect2i(region_anchor.min(cell),region_anchor.max(cell)-region_anchor.min(cell)+Vector2i.ONE)
		elif not grab.is_empty():
			grab.position = event.position
			grab.pending = true
		else:
			hover = _pick(event.position)
			if dragging and not released: _queue_pick(hover)
		_update_overlay()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if picking_object and event.pressed: _pick_object(event.position); return EditorPlugin.AFTER_GUI_INPUT_STOP
		if selecting:
			var cell := _plane_cell(event.position)
			if event.pressed: region_anchor = cell
			elif region_anchor.x >= 0 and cell.x >= 0:
				edit_region = Rect2i(region_anchor.min(cell),region_anchor.max(cell)-region_anchor.min(cell)+Vector2i.ONE)
				selecting = false
				region_preview = Rect2i()
				if create_region: _create_ground()
				_refresh_scope()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if not event.pressed:
			if not grab.is_empty(): grab.released = true; grab.position = event.position; grab.pending = true
			elif dragging: released = true; _queue_pick(_pick(event.position))
		elif not dragging and grab.is_empty():
			hover = _pick(event.position)
			if _mode() == "grab": _begin_grab(event.position)
			else: _begin_stroke(hover,event.ctrl_pressed)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _center(pick: Dictionary, mode := "") -> Vector3i:
	if pick.is_empty(): return Model.INVALID_CELL
	if mode == "": mode = stroke_mode if dragging else _mode()
	if mode == "add": return pick.get("adjacent",Model.INVALID_CELL)
	return pick.get("adjacent",Model.INVALID_CELL) if pick.get("empty_floor",false) else pick.get("hit",Model.INVALID_CELL)

func _begin_stroke(pick: Dictionary, inverse := false) -> void:
	if entry.is_empty(): return
	stroke_mode = _mode()
	if inverse:
		stroke_mode = {"raise":"lower","lower":"raise","add":"remove","remove":"add","water":"dry","dry":"water"}.get(stroke_mode,stroke_mode)
	var center := _center(pick,stroke_mode)
	if center == Model.INVALID_CELL: return
	if stroke_mode in ["water","dry"] and entry.object_session != null:
		_status("Воду редактируем на общей земле карты; выберите «Земля карты».")
		return
	var density: int = entry.resource.normalized_density()
	# Existing fill schema stores the boundary above the last water voxel.
	# SurfaceMesher returns level-1 and renders that voxel's top at level.
	var level := roundi((water_height.value-entry.origin.y)*density/map.imported_tile_size)
	if stroke_mode == "water" and (level < 1 or level > entry.resource.height_voxels):
		_status("Уровень воды вне вертикального диапазона земли. Выберите высоту внутри неё.")
		return
	baseline = entry.resource.duplicate_model()
	delta = {"__sizes":{}}
	top_cache.clear()
	amount_cache.clear()
	stroke_radius = maxi(1,roundi(radius.value*entry.resource.normalized_density()))
	stroke_depth = roundi(depth.value)
	stroke_palette = int(palette.get_selected_metadata()) if palette.selected >= 0 else 1
	stroke_options = {"level":level if stroke_mode in ["water","dry"] else center.y,"secondary":sand_palette.get_selected_metadata() if sand_palette.selected >= 0 else stroke_palette,"shore":{"origin":Vector2(center.x,center.z),"height":center.y,"direction":shore_direction.selected,"width":shore_width.value*density,"roughness":15}}
	dragging = true
	_set_busy(true)
	released = false
	stroke_options["empty_floor"] = roundi((plane_height.value-entry.origin.y)*density/map.imported_tile_size)-1 if entry.target.get_ref() is EmberMapLoader else -1
	stroke_started = Time.get_ticks_usec()
	last_cell = Model.INVALID_CELL
	_queue_pick(pick)

func _queue_pick(pick: Dictionary) -> void:
	var cell := _center(pick)
	if cell == Model.INVALID_CELL or cell == last_cell: return
	var previous := cell if last_cell == Model.INVALID_CELL else last_cell
	if stroke_mode in ["add","remove","paint"]:
		var count := clampi(ceili(Vector3(cell-previous).length()/maxf(1,stroke_radius*0.4)),1,2048)
		for i in range(1,count+1):
			queue.append({"from":Vector3i(Vector3(previous).lerp(Vector3(cell),float(i)/count)),"to":Vector3i(Vector3(previous).lerp(Vector3(cell),float(i)/count)),"normal":pick.get("normal",Vector3i.UP)})
	else: queue.append({"from":previous,"to":cell,"normal":pick.get("normal",Vector3i.UP)})
	last_cell = cell

func _create_ground() -> void:
	create_region = false
	entry = sessions.create_ground(map,scene)
	if entry.is_empty(): _status(sessions.error); return
	_refresh_palette()
	var density: int = entry.resource.normalized_density()
	baseline = entry.resource.duplicate_model()
	delta = {"__sizes":{}}
	stroke_mode = "foundation"
	stroke_radius = density
	stroke_depth = 32
	stroke_palette = 1
	stroke_options = {"level":roundi((plane_height.value-entry.origin.y)*density/map.imported_tile_size)}
	top_cache.clear()
	amount_cache.clear()
	dragging = true
	_set_busy(true)
	released = true
	stroke_started = Time.get_ticks_usec()
	queue.append({"from":Vector3i(edit_region.position.x*density,0,edit_region.position.y*density),"to":Vector3i(edit_region.end.x*density-1,0,edit_region.end.y*density-1),"normal":Vector3i.UP})
	actions.history_context = scene
	_status("Создаю новую землю по выбранному прямоугольнику…")

func _new_job(sample: Dictionary) -> RefCounted:
	var next := Model.StrokeJob.new()
	next.source = baseline
	next.from = sample.from
	next.to = sample.to
	next.normal = sample.normal
	next.mode = stroke_mode
	next.radius = stroke_radius
	next.depth = stroke_depth
	next.palette = stroke_palette
	next.options = stroke_options
	var density: int = baseline.normalized_density()
	next.region = Rect2i(edit_region.position*density,edit_region.size*density) if (clip.button_pressed or stroke_mode == "foundation") and edit_region.has_area() else Rect2i()
	next.top_cache = top_cache
	next.amount_cache = amount_cache
	next.initialize()
	return next

func _write_values(channel: String, updates: Dictionary) -> PackedInt32Array:
	var values: Variant = entry.resource.get(channel)
	var changed := PackedInt32Array()
	if not delta.has(channel): delta[channel] = {}
	if not delta.__sizes.has(channel): delta.__sizes[channel] = Vector2i(values.size(),values.size())
	# One COW channel copy per batch, never one dense copy per voxel.
	for index in updates:
		if index < 0 or index >= values.size(): continue
		var after: int = updates[index]
		var before := int(values[index])
		if before == after: continue
		if not delta[channel].has(index): delta[channel][index] = Vector2i(before,after)
		else: delta[channel][index].y = after
		values[index] = after
		changed.append(index)
	entry.resource.set(channel,values)
	return changed

func _apply_batch(changes: Dictionary) -> void:
	if changes.is_empty(): return
	var dirty := {}
	var size: Vector3i = entry.resource.grid_size()
	var updates := {}
	if stroke_mode in ["water","dry"]:
		var count := size.x*size.z
		for channel in ["surface_fill_levels","surface_fill_materials","surface_fill_palette"]:
			var values: Variant = entry.resource.get(channel)
			if not delta.__sizes.has(channel): delta.__sizes[channel] = Vector2i(values.size(),count)
			if values.is_empty(): values.resize(count); values.fill(0); entry.resource.set(channel,values)
			updates[channel] = {}
		for index in changes:
			var level: int = changes[index].after
			updates.surface_fill_levels[index] = level
			updates.surface_fill_materials[index] = 1 if level > 0 else 0
			updates.surface_fill_palette[index] = stroke_palette if level > 0 else 0
	else:
		updates.voxels = {}
		if not entry.resource.collision_voxels.is_empty(): updates.collision_voxels = {}
		if not entry.resource.voxel_part_ids.is_empty(): updates.voxel_part_ids = {}
		for index in changes:
			var value: int = changes[index].after
			updates.voxels[index] = value
			if updates.has("collision_voxels"):
				if value == 0: updates.collision_voxels[index] = 0
				elif baseline.voxels[index] == 0: updates.collision_voxels[index] = 1
			if updates.has("voxel_part_ids") and value == 0: updates.voxel_part_ids[index] = 0
	for channel in updates:
		for index in _write_values(channel,updates[channel]): dirty[index] = true
	if not dirty.is_empty(): entry.resource.notify_geometry_changed(PackedInt32Array(dirty.keys()))

func _process(_elapsed: float) -> void:
	if _recovery_due > 0 and Time.get_ticks_msec() >= _recovery_due and Time.get_ticks_msec()-_last_recovery >= 30000 and not dragging and grab.is_empty():
		sessions.write_recovery()
		_last_recovery = Time.get_ticks_msec()
		_recovery_due = 0
	if not grab.is_empty(): _process_grab(); return
	if not dragging: return
	if not is_instance_valid(entry.target.get_ref()): cancel_stroke(); _status("Цель удалена; мазок отменён."); return
	if job == null and not queue.is_empty(): job = _new_job(queue.pop_front())
	if job != null:
		_apply_batch(job.step(4000))
		if job.done: job = null
	if released and job == null and queue.is_empty():
		var channels := delta.duplicate(true)
		for channel in delta:
			if channel == "__sizes": continue
			for index in delta[channel]:
				var pair: Vector2i = delta[channel][index]
				if pair.x == pair.y: channels[channel].erase(index)
			if channels[channel].is_empty(): channels.erase(channel)
		if channels.size() > 1:
			var indices := PackedInt32Array(delta.get("voxels",delta.get("surface_fill_levels",{})).keys())
			actions.commit_applied_delta(entry.resource,channels,indices,"Мир · " + stroke_mode)
		else:
			for channel in delta.__sizes:
				var sizes: Vector2i = delta.__sizes[channel]
				if sizes.x == 0:
					var values: Variant = entry.resource.get(channel)
					values.resize(0)
					entry.resource.set(channel,values)
		last_stroke_usec = Time.get_ticks_usec()-stroke_started
		last_history_bytes = 0
		for channel in channels:
			if channel != "__sizes": last_history_bytes += channels[channel].size()*(6 if entry.resource.get(channel) is PackedByteArray else 12)
		dragging = false
		_set_busy(false)
		baseline = null
		delta.clear()
		_status("Мазок применён · Ctrl+Z отменяет · %d* черновиков" % sessions.dirty_count(scene))
		sessions.changed.emit()

func cancel_stroke() -> void:
	_set_busy(false)
	if not grab.is_empty():
		for field in Sessions.FIELDS: entry.resource.set(field,EmberVoxelModelResource.copy_authoring_value(grab.baseline.get(field)))
		entry.resource.notify_geometry_changed(PackedInt32Array())
		grab.clear()
	if dragging and not entry.is_empty() and baseline != null:
		var channels := delta.duplicate(true)
		channels.erase("__sizes")
		if not channels.is_empty(): actions._apply_delta(entry.resource,delta,false,PackedInt32Array(delta.get("voxels",delta.get("surface_fill_levels",{})).keys()))
	job = null
	queue.clear()
	dragging = false
	released = false
	baseline = null
	delta.clear()

func _begin_grab(position: Vector2) -> void:
	if entry.is_empty() or entry.object_session == null:
		_status("«Тянуть» предназначен для выбранного объекта. Землю поднимайте и сглаживайте кистями рельефа.")
		return
	if hover.is_empty() or hover.get("hit",Model.INVALID_CELL) == Model.INVALID_CELL: return
	var frame: Transform3D = sessions.frame(entry)
	var center := Vector3(hover.hit)+Vector3.ONE*0.5
	var plane := Plane((frame.basis.inverse()*camera.global_basis.z).normalized(),center/entry.resource.normalized_density())
	var anchor = plane.intersects_ray(frame.affine_inverse()*camera.project_ray_origin(position),frame.basis.inverse()*camera.project_ray_normal(position))
	if anchor == null: return
	grab = {"baseline":entry.resource.duplicate_model(),"frame":frame,"plane":plane,"anchor":anchor,"center":center,"position":position,"pending":false,"released":false,"displacement":Vector3.ZERO,"planned":Vector3.ZERO,"job":null,"plan":{},"radius":radius.value*entry.resource.normalized_density()}
	_set_busy(true)

func _process_grab() -> void:
	if not is_instance_valid(entry.target.get_ref()) or sessions.frame(entry) != grab.frame: cancel_stroke(); return
	if grab.pending:
		grab.pending = false
		var point = grab.plane.intersects_ray(grab.frame.affine_inverse()*camera.project_ray_origin(grab.position),grab.frame.basis.inverse()*camera.project_ray_normal(grab.position))
		if point != null: grab.displacement = (point-grab.anchor)*entry.resource.normalized_density()
	if grab.job == null and not grab.displacement.is_equal_approx(grab.planned):
		grab.planned = grab.displacement
		grab.job = Fragment.start_grab(grab.baseline,grab.center,grab.radius,grab.planned,softness.value,edit_region if clip.button_pressed else Rect2i(),-1,clip.button_pressed)
	if grab.job != null:
		grab.job.step(8192,4000)
		if not grab.job.done: return
		grab.plan = grab.job.result
		grab.job = null
		if not grab.plan.has("error"):
			for property in grab.plan.properties: entry.resource.set(property,grab.plan.properties[property])
			entry.resource.notify_geometry_changed(grab.plan.changed_indices)
		else: _status(grab.plan.error)
	if grab.released and grab.job == null and grab.displacement.is_equal_approx(grab.planned):
		var plan: Dictionary = grab.plan
		for field in Sessions.FIELDS: entry.resource.set(field,EmberVoxelModelResource.copy_authoring_value(grab.baseline.get(field)))
		grab.clear()
		_set_busy(false)
		if not plan.is_empty() and not plan.has("error"): actions.apply_fragment(entry.resource,plan)
		else: entry.resource.notify_geometry_changed(PackedInt32Array())
		_status("Деформация завершена · Ctrl+Z отменяет · Ctrl+S сохраняет всё")

func _focus_cursor() -> void:
	if _focusing or scene == null or entry.is_empty(): return
	_focusing = true
	var marker := MeshInstance3D.new()
	marker.name = "EmberCursorFocus"
	var sphere := SphereMesh.new()
	sphere.radius = maxf(0.5,radius.value*map.imported_tile_size)
	sphere.height = sphere.radius*2
	marker.mesh = sphere
	marker.visible = false
	scene.add_child(marker,false,Node.INTERNAL_MODE_BACK)
	marker.global_position = sessions.frame(entry)*(Vector3(_center(hover))/entry.resource.normalized_density())
	var selection := EditorInterface.get_selection()
	var previous := selection.get_selected_nodes()
	selection.clear()
	selection.add_node(marker)
	get_tree().create_timer(0.15).timeout.connect(func():
		if is_instance_valid(marker):
			selection.remove_node(marker)
			marker.free()
		for node in previous:
			if is_instance_valid(node) and node.is_inside_tree(): selection.add_node(node)
		_focusing = false
	)

func draw_overlay(overlay: Control) -> void:
	if not active or not is_instance_valid(camera): return
	if map != null and (entry.is_empty() or selecting or hover.get("empty_floor",false)):
		var footprint: Vector2i = map.authored_size_blocks if entry.is_empty() or create_region else Vector2i(entry.resource.size_blocks.x,entry.resource.size_blocks.z)
		var frame := _region_frame()
		var height := _region_height()
		for axis in 2:
			for i in (footprint.x+1 if axis == 0 else footprint.y+1):
				var a := frame*Vector3(i if axis == 0 else 0,height,0 if axis == 0 else i)
				var b := frame*Vector3(i if axis == 0 else footprint.x,height,footprint.y if axis == 0 else i)
				if camera.is_position_behind(a) or camera.is_position_behind(b): continue
				overlay.draw_line(camera.unproject_position(a),camera.unproject_position(b),Color(0.3,0.75,0.85,0.3),1,true)
	var rect := region_preview if selecting and region_preview.has_area() else edit_region
	if rect.has_area() and map != null:
		var points := PackedVector2Array()
		for corner in [rect.position,Vector2i(rect.end.x,rect.position.y),rect.end,Vector2i(rect.position.x,rect.end.y),rect.position]:
			var world: Vector3 = _region_frame()*Vector3(corner.x,_region_height(),corner.y)
			if camera.is_position_behind(world): return
			points.append(camera.unproject_position(world))
		overlay.draw_polyline(points,Color(0.3,0.8,1,0.9),2,true)
	if hover.is_empty() or entry.is_empty(): return
	var cell := _center(hover)
	if cell == Model.INVALID_CELL: return
	var frame: Transform3D = sessions.frame(entry)
	var density: int = entry.resource.normalized_density()
	var points := PackedVector2Array()
	var normal: Vector3i = hover.get("normal",Vector3i.UP)
	var tangents := Model.tangent_axes(normal)
	for i in range(65):
		var angle := TAU*i/64.0
		var local := (Vector3(cell)+Vector3.ONE*0.5)/density + radius.value*(Vector3(tangents[0])*cos(angle)+Vector3(tangents[1])*sin(angle))
		if entry.target.get_ref() is EmberMapLoader:
			var x := floori(local.x*density)
			var z := floori(local.z*density)
			var size: Vector3i = entry.resource.grid_size()
			if x >= 0 and z >= 0 and x < size.x and z < size.z:
				var top := Model._top_filled_y(entry.resource.voxels,size,x,z)
				if top >= 0: local.y = float(top+1)/density+0.02
		var world := frame*local
		if camera.is_position_behind(world): return
		points.append(camera.unproject_position(world))
	overlay.draw_polyline(points,Color(1,0.78,0.3,0.95),2,true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: cancel_stroke()

func _exit_tree() -> void:
	if is_instance_valid(library_favorites_panel): library_favorites_panel.queue_free()
	_set_working_water(false)
	cancel_stroke()
	sessions.release()
