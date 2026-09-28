@tool
extends Node
## Native 3D input/UI adapter for the existing sculpt model, actions and sessions.
signal active_changed(value: bool)
signal compact_extension_preview_ready
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Actions = preload("res://addons/ember_import/ember_voxel_sculpt_actions.gd")
const Sessions = preload("res://addons/ember_import/ember_world_edit_sessions.gd")
const Fragment = preload("res://addons/ember_import/ember_voxel_fragment.gd")
const WorldEditTrace = preload("res://addons/ember_import/ember_world_edit_trace.gd")
const LandscapeV2Experiment = preload("res://addons/ember_import/ember_landscape_v2_experiment.gd")
const CompactBrush = preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
const CompactBrushMath = preload("res://scripts/prototypes/ember_terrain_pilot_brush_math.gd")
const WorkshopTheme = preload("res://addons/ember_import/ember_voxel_workshop_theme.gd")
const BrushParameters = preload("res://addons/ember_import/ember_world_brush_parameters.gd")
const CompactMapExtension = preload("res://addons/ember_import/ember_compact_map_extension.gd")
const CompactExtensionPreview = preload("res://addons/ember_import/ember_compact_map_extension_preview.gd")
const TerrainDiagnostics = preload("res://addons/ember_import/ember_terrain_diagnostics.gd")
const HoverGridShader = preload("res://shaders/ember_terrain_hover_grid.gdshader")
const SETTINGS := "user://ember_world_editor.cfg"
const EXPERIMENT_SCENE := "res://scenes/landscape_v2_experimental.tscn"
const EXPERIMENT_SURFACE := "res://content/world_surfaces/landscape_v2_experimental_surface.tres"
const BRUSH_STEP_BUDGET_USEC := 4000
const BRUSH_BACKLOG_STEP_BUDGET_USEC := 6000
const TOOL_ICONS := {
	"raise": &"ArrowUp", "lower": &"ArrowDown", "add": &"Add", "remove": &"Remove",
	"smooth": &"EditorPathSmoothHandle", "level": &"PlaneMesh", "shore": &"GradientTexture1D",
	"generator": &"Noise", "grab": &"ToolMove", "paint": &"Paint", "sand": &"NoiseTexture2D",
	"water": &"GradientTexture2D", "dry": &"Eraser", "objects": &"MeshInstance3D",
}
const TOOL_LABELS := {
	"raise": "Поднять", "lower": "Опустить", "add": "Добавить", "remove": "Убрать",
	"smooth": "Сгладить", "level": "Площадка", "shore": "Берег и дно",
	"generator": "Неровности", "grab": "Тянуть", "paint": "Покрасить", "sand": "Песок",
	"water": "Вода", "dry": "Убрать воду", "objects": "Объекты",
}
const TOOL_HINTS := {
	"raise": "Поднять землю плавным мазком.", "lower": "Опустить землю плавным мазком.",
	"add": "Добавить объём на поверхности.", "remove": "Убрать объём на поверхности.",
	"smooth": "Смягчить переходы высоты.", "level": "Выровнять площадку по точке или высоте.",
	"shore": "Сформировать спуск берега и дна.", "generator": "Добавить неровности заданной крупности.",
	"grab": "Потянуть часть поверхности.", "paint": "Покрасить поверхность выбранным цветом.",
	"sand": "Нанести крупные пятна песка.", "water": "Добавить открытый уровень воды.",
	"dry": "Убрать воду на участке.", "objects": "Расставить выбранный voxel-объект.",
}
var sessions := Sessions.new()
var actions := Actions.new()
var plugin: EditorPlugin
var active := false
var entry := {}
var scene: Node3D
var map: EmberMapLoader
var toolbar: HBoxContainer
var sidebar: PanelContainer
var inspector_panel: PanelContainer
var inspector_title: Label
var inspector_hint: Label
var inspector_icon: TextureRect
var material_title: Label
var tool_settings_title: Label
var tool_list: VBoxContainer
var object_shelf_toggle: Button
var _ui_theme: Theme
var _ui_icons := {}
var _tool_buttons: Array[Button] = []
var enabled: Button
var target_choice: OptionButton
var category: OptionButton
var category_buttons: Array[Button] = []
var tools: OptionButton
var radius: SpinBox
var radius_slider: HSlider
var parameter_sliders: Array[HSlider] = []
var _brush_parameter_controls: Dictionary = {}
var depth: SpinBox
var coarse_depth: SpinBox
var terrain_edit_scale: OptionButton
var terrain_height_step: OptionButton
var brush_shape: OptionButton
var plane_height: SpinBox
var water_height: SpinBox
var shore_width: SpinBox
var softness: SpinBox
var compact_feature_scale: SpinBox
var compact_detail: SpinBox
var compact_seed: SpinBox
var compact_direction: OptionButton
var compact_level_from_point: CheckBox
var shore_direction: OptionButton
var palette: OptionButton
var palette_swatch: ColorRect
var palette_row: HBoxContainer
var open_canvas_button: Button
var create_ground_button: Button
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
var _trace := WorldEditTrace.new()
var _compact_trace := TerrainDiagnostics.new()
var _trace_button: Button
var _terrain_diagnostics_button: Button
var _terrain_diagnostics_summary: Label
var _job_queued_usec := 0
var _experiment_toggle: CheckBox
var _experiment: RefCounted
var _experiment_stroke := false
var _experiment_baking := false
var _experiment_waiting_exact := false
var _experiment_settle_frames := 0
var _experiment_dirty_indices := {}
var _compact_brush := CompactBrush.new()
var _compact_grid_view_key := ""
var _compact_grid_material: ShaderMaterial
var _compact_grid_projection: WeakRef
var _compact_grid_visible_tiles := {}
var _compact_hover_grid_stats := {}
var _compact_extension_preview: Node3D
var _compact_extension_candidate := {}

func _compact_active() -> bool:
	return not entry.is_empty() and entry.get("compact", false)

func _set_busy(value: bool) -> void:
	for control in [target_choice,category,tools,palette,sand_palette,clip,shore_direction,compact_direction,compact_level_from_point,terrain_edit_scale,terrain_height_step,brush_shape]:
		if is_instance_valid(control): control.disabled = value
	for control in [radius,depth,coarse_depth,plane_height,water_height,shore_width,softness,compact_feature_scale,compact_detail,compact_seed]:
		if is_instance_valid(control): control.editable = not value
	for button in _target_buttons:
		if is_instance_valid(button): button.disabled = value
	for button in category_buttons:
		if is_instance_valid(button): button.disabled = value
	for slider in parameter_sliders:
		if is_instance_valid(slider): slider.editable = not value
	if is_instance_valid(_experiment_toggle): _experiment_toggle.disabled = value

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
	actions.source_changed.connect(_on_experiment_source_changed)
	sessions.changed.connect(_refresh_dirty_status)
	sessions.changed.connect(func(): _recovery_due = Time.get_ticks_msec()+10000)
	var config := ConfigFile.new()
	if config.load(SETTINGS) == OK:
		recent_objects = config.get_value("objects","recent",PackedStringArray())
		favorite_objects = config.get_value("objects","favorites",PackedStringArray())
	set_process(true)
	set_process_input(true)


func preview_compact_extension(direction: String, mode: String) -> String:
	clear_compact_extension_preview()
	var root := EditorInterface.get_edited_scene_root() as Node3D
	var target := root.find_child("Map", true, false) as EmberMapLoader if root != null else null
	if target == null or target.compact_terrain == null:
		return "Откройте компактную карту в 3D-редакторе."
	if direction not in CompactMapExtension.DIRECTIONS or mode not in CompactMapExtension.MODES:
		return "Выберите сторону и тип участка."
	if scene != root:
		scene_changed(root)
	var draft := sessions.open_map(target, root)
	if draft.is_empty():
		return sessions.error
	var before: EmberTerrainPilotResource = draft.resource
	if target.authored_size_blocks != Vector2i(before.width / 16, before.depth / 16):
		return "Размер сцены и земли не совпадает. Сначала сохраните или исправьте карту."
	var after: EmberTerrainPilotResource = CompactMapExtension.expanded(before, direction, mode)
	if after == null:
		return "Предел тестовой карты — %d блоков по каждой оси." % (CompactMapExtension.Creation.MAX_EXTENDED_SECTIONS * CompactMapExtension.Creation.SECTION_BLOCKS)
	var preview := CompactExtensionPreview.new() as Node3D
	target.add_child(preview, false, Node.INTERNAL_MODE_BACK)
	if not preview.call("show_candidate", target, before, after, direction):
		preview.free()
		return "3D-предпросмотр земли сейчас недоступен."
	_compact_extension_preview = preview
	_compact_extension_candidate = {"target": weakref(target), "before": before, "after": after, "direction": direction, "mode": mode}
	preview.connect("preview_built", func() -> void:
		if _compact_extension_preview == preview:
			compact_extension_preview_ready.emit()
	)
	return ""


func clear_compact_extension_preview() -> void:
	_compact_extension_candidate.clear()
	if is_instance_valid(_compact_extension_preview):
		_compact_extension_preview.call("clear_preview")
		_compact_extension_preview.hide()
		_compact_extension_preview.queue_free()
	_compact_extension_preview = null


func extend_compact_map(direction: String, mode := CompactMapExtension.MODE_CONTINUE) -> String:
	var root := EditorInterface.get_edited_scene_root() as Node3D
	var target := root.find_child("Map", true, false) as EmberMapLoader if root != null else null
	if target == null or target.compact_terrain == null:
		return "Откройте компактную карту в 3D-редакторе."
	if direction not in CompactMapExtension.DIRECTIONS or mode not in CompactMapExtension.MODES:
		return "Выберите сторону и тип участка."
	if scene != root:
		scene_changed(root)
	cancel_stroke()
	var draft := sessions.open_map(target, root)
	if draft.is_empty():
		return sessions.error
	var before: EmberTerrainPilotResource = draft.resource
	if target.authored_size_blocks != Vector2i(before.width / 16, before.depth / 16):
		return "Размер сцены и земли не совпадает. Сначала сохраните или исправьте карту."
	var cached := _compact_extension_candidate
	var after: EmberTerrainPilotResource = cached.get("after") if not cached.is_empty() and cached.get("target") is WeakRef and cached.target.get_ref() == target and cached.get("before") == before and cached.get("direction") == direction and cached.get("mode") == mode else CompactMapExtension.expanded(before, direction, mode)
	if after == null:
		return "Предел тестовой карты — %d блоков по каждой оси." % (CompactMapExtension.Creation.MAX_EXTENDED_SECTIONS * CompactMapExtension.Creation.SECTION_BLOCKS)
	clear_compact_extension_preview()
	var before_blocks := target.authored_size_blocks
	var after_blocks := Vector2i(after.width / 16, after.depth / 16)
	var old_positions := {}
	var new_positions := {}
	var shift: Vector3 = CompactMapExtension.scene_shift(direction, target.imported_tile_size)
	for group_name in ["Terrain", "Props", "Regions"]:
		var group := target.get_node_or_null(group_name) as Node3D
		if group == null: continue
		old_positions[group_name] = group.position
		new_positions[group_name] = group.position + shift
	var history := sessions.undo as EditorUndoRedoManager
	history.create_action("Расширить компактную карту: " + direction, UndoRedo.MERGE_DISABLE, root)
	Callable(history, "add_do_method").callv([self, "_apply_compact_extension", target, draft, after, after_blocks, new_positions, direction])
	Callable(history, "add_undo_method").callv([self, "_apply_compact_extension", target, draft, before, before_blocks, old_positions, direction])
	history.commit_action()
	return ""


func _apply_compact_extension(target: EmberMapLoader, draft: Dictionary, source: EmberTerrainPilotResource, blocks: Vector2i, positions: Dictionary, direction := "") -> void:
	var projection := target._visual_surface_projection as EmberTerrainPilotProjection if is_instance_valid(target) else null
	if projection != null and not direction.is_empty():
		projection.open_resized_document(source, draft.resource, direction, CompactMapExtension.Creation.SECTION_BLOCKS * EmberTerrainPilotResource.CELLS_PER_BLOCK)
	draft.resource = source
	target.authored_size_blocks = blocks
	for group_name in positions:
		var group := target.get_node_or_null(group_name) as Node3D
		if group != null: group.position = positions[group_name]
	sessions.preview(draft)
	sessions.changed.emit()
	if map == target:
		_refresh_scope()
		_refresh_target_actions()

func build_toolbar() -> Control:
	toolbar = HBoxContainer.new()
	var base_theme := EditorInterface.get_editor_theme() if Engine.is_editor_hint() else ThemeDB.get_default_theme()
	_ui_theme = WorkshopTheme.build(base_theme)
	toolbar.theme = _ui_theme
	enabled = Button.new()
	enabled.text = "Редактировать мир"
	enabled.icon = _editor_icon(&"World3D")
	enabled.theme_type_variation = &"WorkshopToolButton"
	enabled.tooltip_text = "Кисти земли и расстановка объектов прямо в 3D-виде"
	enabled.toggle_mode = true
	enabled.toggled.connect(_toggle)
	toolbar.add_child(enabled)
	var save_button := Button.new()
	save_button.text = "Сохранить мир"
	save_button.icon = _editor_icon(&"Save")
	save_button.tooltip_text = "Сохранить сцену и все черновики мира · Ctrl+S"
	save_button.pressed.connect(save_all)
	save_button.hide()
	toolbar.add_child(save_button)
	return toolbar

func _editor_icon(name: StringName) -> Texture2D:
	if not Engine.is_editor_hint(): return null
	if _ui_icons.has(name): return _ui_icons[name]
	var editor_theme := EditorInterface.get_editor_theme()
	if not editor_theme.has_icon(name,&"EditorIcons"): return null
	var original := editor_theme.get_icon(name,&"EditorIcons") as Texture2D
	var pixels := original.get_image()
	if pixels == null: return original
	var mask := Image.create(pixels.get_width(),pixels.get_height(),false,Image.FORMAT_RGBA8)
	for y in pixels.get_height():
		for x in pixels.get_width():
			var pixel := pixels.get_pixel(x,y)
			mask.set_pixel(x,y,Color(1,1,1,pixel.a))
	var icon := ImageTexture.create_from_image(mask)
	_ui_icons[name] = icon
	return icon

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

func _slider_spin(parent: Node, title: String, minimum: float, maximum: float, initial: float, step := 1.0) -> SpinBox:
	var group := VBoxContainer.new()
	parent.add_child(group)
	var label := Label.new()
	label.text = title
	label.add_theme_color_override("font_color",WorkshopTheme.MUTED)
	group.add_child(label)
	var row := HBoxContainer.new()
	group.add_child(row)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = initial
	spin.set_meta("parameter_group",group)
	spin.custom_minimum_size.x = 82
	row.add_child(spin)
	slider.value_changed.connect(func(value: float): spin.value = value)
	spin.value_changed.connect(func(value: float): slider.set_value_no_signal(value))
	parameter_sliders.append(slider)
	if title == "Радиус · блоки": radius_slider = slider
	return spin

func _brush_choice(parent: Node, id: String) -> OptionButton:
	var spec := BrushParameters.definition(id)
	var items: Array[String] = []
	items.assign(spec.items)
	return _choice(parent,items)

func _brush_spin(parent: Node, id: String) -> SpinBox:
	var spec := BrushParameters.definition(id)
	return _spin(parent,str(spec.title),float(spec.min),float(spec.max),float(spec.initial),float(spec.get("step",1.0)))

func _brush_slider(parent: Node, id: String) -> SpinBox:
	var spec := BrushParameters.definition(id)
	return _slider_spin(parent,str(spec.title),float(spec.min),float(spec.max),float(spec.initial),float(spec.get("step",1.0)))

func build_sidebar() -> Control:
	sidebar = PanelContainer.new()
	sidebar.custom_minimum_size.x = 232
	inspector_panel = PanelContainer.new()
	inspector_panel.custom_minimum_size.x = 302
	if _ui_theme == null:
		var base_theme := EditorInterface.get_editor_theme() if Engine.is_editor_hint() else ThemeDB.get_default_theme()
		_ui_theme = WorkshopTheme.build(base_theme)
	sidebar.theme = _ui_theme
	inspector_panel.theme = _ui_theme
	sidebar.add_theme_stylebox_override("panel",WorkshopTheme._box(WorkshopTheme.SURFACE_LOW,WorkshopTheme.BORDER,5))
	inspector_panel.add_theme_stylebox_override("panel",WorkshopTheme._box(WorkshopTheme.SURFACE_LOW,WorkshopTheme.BORDER,5))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 220
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var inspector_layout := VBoxContainer.new()
	inspector_panel.add_child(inspector_layout)
	var inspector_scroll := ScrollContainer.new()
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_layout.add_child(inspector_scroll)
	var settings := VBoxContainer.new()
	settings.custom_minimum_size.x = 286
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_scroll.add_child(settings)
	var inspector_header := HBoxContainer.new()
	settings.add_child(inspector_header)
	inspector_icon = TextureRect.new()
	inspector_icon.custom_minimum_size = Vector2(20,20)
	inspector_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	inspector_icon.modulate = WorkshopTheme.AMBER
	inspector_header.add_child(inspector_icon)
	inspector_title = Label.new()
	inspector_title.text = "Параметры кисти"
	inspector_header.add_child(inspector_title)
	inspector_hint = Label.new()
	inspector_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector_hint.add_theme_color_override("font_color",WorkshopTheme.MUTED)
	settings.add_child(inspector_hint)
	var title := Label.new()
	title.text = "EMBER · МИР"
	box.add_child(title)
	target_choice = _choice(box,["Земля карты","Voxel-объект"])
	target_choice.tooltip_text = "Что меняет кисть: землю карты или выбранный voxel-объект. Объект редактируется как уникальный экземпляр."
	target_choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	target_choice.item_selected.connect(_target_changed)
	var pick_object := _button(box,"Выбрать объект",func(): picking_object = true; _status("Нажмите на voxel-объект в сцене. Остальные экземпляры не изменятся."))
	pick_object.icon = _editor_icon(&"ToolSelect")
	open_canvas_button = _button(box,"Открыть в Canvas",open_canvas)
	open_canvas_button.icon = _editor_icon(&"Edit")
	create_ground_button = _button(box,"Создать землю",func():
		cancel_stroke()
		target_choice.select(0)
		_target_changed(0)
		if _compact_active():
			_status("Компактная земля уже занимает карту. Меняйте её кистями ниже.")
			return
		selecting = true
		create_region = true
		region_anchor = Vector2i(-1,-1)
		_status("Потяните прямоугольник рядом с готовым берегом. Создание не меняет остальные объекты.")
	)
	create_ground_button.icon = _editor_icon(&"Add")
	category = _choice(box,["Форма","Покраска","Вода","Объекты"])
	category.tooltip_text = "Раздел инструментов мира"
	category.item_selected.connect(_category_changed)
	category.hide()
	var section_title := Label.new()
	section_title.text = "ИНСТРУМЕНТЫ"
	section_title.add_theme_color_override("font_color",WorkshopTheme.MUTED)
	box.add_child(section_title)
	var category_grid := GridContainer.new()
	category_grid.columns = 2
	box.add_child(category_grid)
	for i in 4:
		var group_index := i
		var button := Button.new()
		button.text = ["Форма","Цвет","Вода","Объект"][i]
		button.icon = _editor_icon([&"HeightMapShape3D",&"Paint",&"GradientTexture2D",&"MeshInstance3D"][i])
		button.toggle_mode = true
		button.theme_type_variation = &"WorkshopSegmentButton"
		button.custom_minimum_size.x = 106
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = ["Рельеф и генерация","Покраска поверхности","Вода","Размещение voxel-объектов"][i]
		button.pressed.connect(func(): category.select(group_index); _category_changed(group_index))
		category_grid.add_child(button)
		category_buttons.append(button)
	tools = _choice(box,[])
	tools.hide()
	tools.item_selected.connect(func(_index): cancel_stroke(); _tool_changed())
	tool_list = VBoxContainer.new()
	box.add_child(tool_list)
	material_title = Label.new()
	material_title.text = "ЦВЕТ ПОВЕРХНОСТИ"
	material_title.add_theme_color_override("font_color",WorkshopTheme.MUTED)
	settings.add_child(material_title)
	palette_row = HBoxContainer.new()
	settings.add_child(palette_row)
	palette = _choice(palette_row,[])
	palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_swatch = ColorRect.new()
	palette_swatch.custom_minimum_size = Vector2(24,24)
	palette_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	palette_row.add_child(palette_swatch)
	sand_palette = _choice(settings,[])
	palette.item_selected.connect(func(_index): cancel_stroke(); _refresh_palette_swatch())
	sand_palette.item_selected.connect(func(_index): cancel_stroke())
	tool_settings_title = Label.new()
	tool_settings_title.add_theme_color_override("font_color",WorkshopTheme.MUTED)
	settings.add_child(tool_settings_title)
	advanced = VBoxContainer.new()
	settings.add_child(advanced)
	plane_height = _brush_spin(advanced,"plane_height")
	water_height = _brush_spin(advanced,"water_height")
	shore_width = _brush_slider(advanced,"shore_width")
	shore_direction = _brush_choice(advanced,"shore_direction")
	softness = _brush_slider(advanced,"softness")
	compact_level_from_point = CheckBox.new()
	compact_level_from_point.text = str(BrushParameters.definition("level_from_point").title)
	compact_level_from_point.button_pressed = true
	advanced.add_child(compact_level_from_point)
	compact_feature_scale = _brush_slider(advanced,"feature_scale")
	compact_detail = _brush_slider(advanced,"detail")
	compact_seed = _brush_spin(advanced,"seed")
	compact_direction = _brush_choice(advanced,"direction")
	compact_level_from_point.toggled.connect(func(_value): cancel_stroke(); _tool_changed())
	for parameter in [compact_feature_scale,compact_detail,compact_seed]:
		parameter.value_changed.connect(func(_value): cancel_stroke())
	compact_direction.item_selected.connect(func(_value): cancel_stroke())
	for parameter in [plane_height,water_height,shore_width,softness]:
		parameter.value_changed.connect(func(_value): cancel_stroke())
	shore_direction.item_selected.connect(func(_index): cancel_stroke())
	var view_toggle := Button.new()
	view_toggle.text = "Область и вид ▸"
	view_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	view_toggle.toggle_mode = true
	settings.add_child(view_toggle)
	var view_settings := VBoxContainer.new()
	settings.add_child(view_settings)
	view_settings.hide()
	view_toggle.toggled.connect(func(open: bool): view_settings.visible = open; view_toggle.text = "Область и вид ▾" if open else "Область и вид ▸")
	scope_label = Label.new()
	scope_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	view_settings.add_child(scope_label)
	_button(view_settings,"Ограничить участок",func(): cancel_stroke(); selecting = true; create_region = false; region_anchor = Vector2i(-1,-1); _status("Потяните прямоугольник рабочей области."))
	_button(view_settings,"Вся поверхность",func(): cancel_stroke(); edit_region = Rect2i(); _refresh_scope())
	clip = CheckBox.new()
	clip.text = "Обрезать по границе"
	clip.button_pressed = true
	view_settings.add_child(clip)
	clip.toggled.connect(func(_value): cancel_stroke())
	_experiment_toggle = CheckBox.new()
	_experiment_toggle.text = "Landscape V2 Experimental · копия карты"
	_experiment_toggle.tooltip_text = "Только отдельная сцена-копия. Во время мазка — высоты и GPU-preview; точные воксели после отпускания."
	_experiment_toggle.visible = false
	view_settings.add_child(_experiment_toggle)
	_experiment_toggle.toggled.connect(_toggle_experiment)
	hide_water = CheckBox.new()
	hide_water.text = "Рабочий вид · скрыть воду"
	view_settings.add_child(hide_water)
	hide_water.toggled.connect(_set_working_water)
	object_parameters = VBoxContainer.new()
	settings.add_child(object_parameters)
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
	object_shelf_toggle = Button.new()
	object_shelf_toggle.text = "Избранное / последние ▾"
	object_shelf_toggle.toggle_mode = true
	object_shelf_toggle.button_pressed = true
	settings.add_child(object_shelf_toggle)
	favorites_box = VBoxContainer.new()
	settings.add_child(favorites_box)
	object_shelf_toggle.toggled.connect(func(value): favorites_box.visible = value)
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
	var extra := VBoxContainer.new()
	settings.add_child(extra)
	var extra_toggle := Button.new()
	extra_toggle.text = "Дополнительно ▸"
	extra_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	extra_toggle.toggle_mode = true
	settings.add_child(extra_toggle)
	settings.move_child(extra_toggle,extra.get_index())
	extra_toggle.toggled.connect(func(open: bool): extra.visible = open; extra_toggle.text = "Дополнительно ▾" if open else "Дополнительно ▸")
	extra.hide()
	_button(extra,"Восстановить аварийные черновики",func():
		if scene != null: _status("Восстановлено: %d. %s" % [sessions.restore_recovery(scene),sessions.error])
	)
	_trace_button = _button(extra,"Начать запись 3D",_toggle_trace)
	_trace_button.tooltip_text = "Записывает наведение без нажатия, мазки и кадры основной 3D-вкладки. JSON сохраняется в user://."
	_terrain_diagnostics_button = _button(extra,"Измерить производительность карты",_capture_terrain_diagnostics)
	_terrain_diagnostics_button.tooltip_text = "90 кадров в 3D и накопленные этапы сборки земли. Отчёт только в user://; карта не меняется."
	_button(extra,"Открыть папку записей",_open_trace_folder)
	_terrain_diagnostics_summary = Label.new()
	_terrain_diagnostics_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_terrain_diagnostics_summary.add_theme_color_override("font_color",WorkshopTheme.MUTED)
	extra.add_child(_terrain_diagnostics_summary)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 286
	inspector_layout.add_child(status)
	var parameters := VBoxContainer.new()
	settings.add_child(parameters)
	settings.move_child(parameters,2)
	var brush_title := Label.new()
	brush_title.text = "КИСТЬ"
	brush_title.add_theme_color_override("font_color",WorkshopTheme.MUTED)
	settings.add_child(brush_title)
	settings.move_child(brush_title,2)
	terrain_edit_scale = _brush_choice(parameters,"edit_scale")
	terrain_edit_scale.tooltip_text = "Каждая карта хранит 16×16 колонок на блок. Основной рельеф делит блок на четыре квадрата 8×8 вокселей; средний и детальный режимы уточняют ту же землю."
	terrain_edit_scale.item_selected.connect(func(_index): cancel_stroke(); brush_shape.select(1 if terrain_edit_scale.selected == 2 else 0); _refresh_brush_scale_settings(); _tool_changed(); _update_overlay())
	terrain_height_step = _brush_choice(parameters,"height_step")
	terrain_height_step.tooltip_text = "Высота одной ступени при редактировании квадратных ячеек. 8 вокселей состоят из двух ступеней по 4."
	terrain_height_step.item_selected.connect(func(_index): cancel_stroke(); _tool_changed())
	brush_shape = _brush_choice(parameters,"shape")
	brush_shape.tooltip_text = "Выбирает форму следа кисти. Ячейки самой земли в обоих случаях остаются квадратными."
	brush_shape.item_selected.connect(func(_index): cancel_stroke(); _update_overlay())
	radius = _brush_slider(parameters,"radius")
	depth = _brush_slider(parameters,"strength_detail")
	coarse_depth = _brush_slider(parameters,"strength_steps")
	_brush_parameter_controls = {
		"edit_scale":terrain_edit_scale, "height_step":terrain_height_step, "shape":brush_shape,
		"radius":_parameter_group(radius), "strength_detail":_parameter_group(depth),
		"strength_steps":_parameter_group(coarse_depth), "palette":palette_row, "sand_palette":sand_palette,
		"plane_height":plane_height.get_parent(), "water_height":water_height.get_parent(),
		"shore_width":_parameter_group(shore_width), "shore_direction":shore_direction,
		"softness":_parameter_group(softness), "level_from_point":compact_level_from_point,
		"feature_scale":_parameter_group(compact_feature_scale), "detail":_parameter_group(compact_detail),
		"seed":compact_seed.get_parent(), "direction":compact_direction,
	}
	radius.value_changed.connect(func(_value): cancel_stroke(); _update_overlay())
	depth.value_changed.connect(func(_value): cancel_stroke())
	coarse_depth.value_changed.connect(func(_value): cancel_stroke())
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
	inspector_panel.hide()
	return sidebar

func _status(message: String) -> void:
	if is_instance_valid(status): status.text = message

func _experimental_allowed() -> bool:
	return is_instance_valid(scene) and scene.scene_file_path == EXPERIMENT_SCENE and not entry.is_empty() and entry.get("object_session") == null and str(entry.get("path", "")) == EXPERIMENT_SURFACE and entry.resource.normalized_density() == 16

func _experimental_enabled() -> bool:
	return is_instance_valid(_experiment_toggle) and _experiment_toggle.button_pressed and _experimental_allowed()

func _refresh_experiment_gate() -> void:
	if not is_instance_valid(_experiment_toggle): return
	var allowed := _experimental_allowed()
	_experiment_toggle.visible = allowed
	if not allowed and _experiment_toggle.button_pressed:
		_experiment_toggle.set_pressed_no_signal(false)
		_clear_experiment()

func _toggle_experiment(enabled_now: bool) -> void:
	if _experiment_waiting_exact:
		_experiment_toggle.set_pressed_no_signal(true)
		_status("Дождитесь точной Surface перед переключением Legacy / Landscape V2.")
		return
	cancel_stroke()
	if _trace.recording: _stop_trace()
	if _compact_trace.recording: _stop_compact_trace()
	if enabled_now and not _experimental_allowed():
		_experiment_toggle.set_pressed_no_signal(false)
		_status("Landscape V2 доступен только в отдельной экспериментальной копии карты.")
		return
	if enabled_now:
		_prepare_experiment()
	else:
		_clear_experiment()
		_status("Legacy: обычная кисть Surface. Для сравнения используйте те же радиус и глубину.")

func _prepare_experiment() -> void:
	_clear_experiment()
	if not _experimental_enabled(): return
	for group in entry.resource.voxel_groups:
		if bool(group.get("locked", false)):
			_experiment_toggle.set_pressed_no_signal(false)
			_status("Эксперимент выключен: на копии есть заблокированные воксели, для них нужен отдельный контракт.")
			return
	_experiment = LandscapeV2Experiment.new()
	_experiment.begin_prepare(entry.resource,map,sessions.frame(entry))
	_status("Landscape V2: подготавливаю временную карту высот…")

func _clear_experiment() -> void:
	if _experiment != null: _experiment.clear()
	_experiment = null
	_experiment_stroke = false
	_experiment_baking = false
	_experiment_waiting_exact = false
	_experiment_settle_frames = 0
	_experiment_dirty_indices.clear()

func _on_experiment_source_changed(_indices: PackedInt32Array) -> void:
	if _experimental_enabled() and not dragging and not _experiment_waiting_exact:
		call_deferred("_restart_experiment_after_history")

func _restart_experiment_after_history() -> void:
	if _experimental_enabled() and not dragging and not _experiment_waiting_exact:
		_prepare_experiment()

func _trace_projection() -> Node:
	if entry.is_empty(): return null
	var target: Node = entry.target.get_ref()
	if not is_instance_valid(target): return null
	return target._visual_surface_projection if target is EmberMapLoader else entry.preview if is_instance_valid(entry.preview) else null

func _attach_trace_projection() -> void:
	if _compact_active(): return
	var projection := _trace_projection()
	if is_instance_valid(projection): projection.editor_diagnostic_sink = _trace if _trace.recording else null

func _toggle_trace() -> void:
	if _compact_active():
		if _compact_trace.recording:
			_stop_compact_trace()
		else:
			_start_compact_trace()
		return
	if _trace.recording:
		_stop_trace()
		return
	_trace.start()
	var projection := _trace_projection()
	_trace.metadata = {"fps_limit":Engine.max_fps,"vsync_mode":DisplayServer.window_get_vsync_mode(),"command_line":OS.get_cmdline_args(),"renderer":ProjectSettings.get_setting("rendering/renderer/rendering_method","not_measured"),"editor_viewport":"Godot main 3D tab via EditorPlugin._forward_3d_gui_input","target":"map" if entry.get("object_session") == null else "object","comparison_mode":"landscape_v2_experimental" if _experimental_enabled() else "legacy","viewport_instance_id":camera.get_viewport().get_instance_id() if is_instance_valid(camera) else -1,"preexisting_visual_pending":projection.pending_chunk_count() if is_instance_valid(projection) else -1,"preexisting_physics_pending":projection.pending_physics_chunk_count() if is_instance_valid(projection) else -1}
	_attach_trace_projection()
	if is_instance_valid(_trace_button): _trace_button.text = "Остановить и сохранить запись"
	_status("Запись мазков включена. Работайте кистью в основной 3D-вкладке; после обновления нажмите остановку.")


func _start_compact_trace() -> void:
	if not is_instance_valid(map) or _compact_brush.active():
		_status("Завершите текущий мазок перед началом записи.")
		return
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	var viewport := EditorInterface.get_editor_viewport_3d(0) if Engine.is_editor_hint() else null
	if projection == null or projection.document == null or viewport == null:
		_status("3D-вид компактной карты сейчас недоступен для записи.")
		return
	var metadata := {"scene_path": scene.scene_file_path if is_instance_valid(scene) else "",
		"map_id": map.map_id, "map_size_columns": [projection.document.width, projection.document.depth],
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"),
		"fps_limit": Engine.max_fps, "vsync_mode": DisplayServer.window_get_vsync_mode()}
	if not _compact_trace.start_brush_recording(metadata, viewport, projection):
		_status("Не удалось начать запись 3D-вида.")
		return
	if is_instance_valid(_trace_button): _trace_button.text = "Остановить и сохранить запись"
	_status("Запись включена. Поводите кистью без нажатия до паузы; при желании сделайте мазок. Затем остановите запись.")


func _stop_compact_trace() -> void:
	if _compact_brush.active():
		_status("Отпустите кисть перед остановкой записи.")
		return
	var report: Dictionary = _compact_trace.stop_brush_recording()
	_compact_brush.diagnostic_sink = null
	if is_instance_valid(_trace_button): _trace_button.text = "Начать запись 3D"
	if report.is_empty(): return
	var recovery: Dictionary = sessions.last_recovery_profile
	var recovery_started := int(recovery.get("started_usec", -1))
	if recovery_started >= int(report.started_usec) and recovery_started <= int(report.started_usec) + int(report.duration_usec):
		report["periodic_recovery"] = {"started_at_usec": recovery_started - int(report.started_usec),
			"completed_at_usec": int(recovery.completed_usec) - int(report.started_usec),
			"snapshot_usec": int(recovery.snapshot_usec), "worker_write_usec": int(recovery.write_usec),
			"result": int(recovery.result)}
	var path: String = TerrainDiagnostics.save_report(report)
	if path.is_empty():
		_status("Не удалось сохранить запись в user://.")
		return
	_status("Запись %d наведений и %d мазков сохранена: %s" % [report.hovers.size(), report.strokes.size(), ProjectSettings.globalize_path(path)])


func _compact_trace_step(kind: String, started_usec: int) -> void:
	if not _compact_trace.recording:
		return
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection if is_instance_valid(map) else null
	_compact_trace.brush_step(kind, Time.get_ticks_usec() - started_usec,
		_compact_brush.changed_column_count(), projection.pending_tile_count() if projection != null else -1)


func _open_trace_folder() -> void:
	var directory: String = TerrainDiagnostics.REPORT_DIRECTORY if _compact_active() else "user://"
	var absolute_path := ProjectSettings.globalize_path(directory)
	if DirAccess.make_dir_recursive_absolute(absolute_path) != OK:
		_status("Не удалось создать папку записей: %s" % absolute_path)
		return
	if OS.shell_show_in_file_manager(absolute_path) != OK:
		_status("Не удалось открыть папку записей: %s" % absolute_path)

func _stop_trace() -> void:
	var report := _trace.stop()
	var projection := _trace_projection()
	if is_instance_valid(projection) and projection.editor_diagnostic_sink == _trace: projection.editor_diagnostic_sink = null
	if is_instance_valid(_trace_button): _trace_button.text = "Начать запись 3D"
	if report.is_empty(): return
	var path := "user://ember_world_edit_trace_%d.json" % Time.get_ticks_usec()
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		_status("Не удалось сохранить диагностику: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	_status("Запись %d мазков сохранена: %s%s" % [report.strokes.size(),ProjectSettings.globalize_path(path)," · отображение ещё в очереди" if not report.pending_visual_at_stop.is_empty() or not report.pending_physics_at_stop.is_empty() else ""])

func _capture_terrain_diagnostics() -> void:
	if _compact_trace.recording:
		_status("Сначала остановите запись мазков, затем измерьте 90 кадров отдельно.")
		return
	if not _compact_active() or not is_instance_valid(map):
		_status("Откройте компактную карту для замера.")
		return
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	var viewport := EditorInterface.get_editor_viewport_3d(0) if Engine.is_editor_hint() else null
	if projection == null or viewport == null:
		_status("3D-проекция карты сейчас недоступна для замера.")
		return
	_terrain_diagnostics_button.disabled = true
	if is_instance_valid(_trace_button): _trace_button.disabled = true
	_status("Измеряю 90 кадров 3D. Оставьте этот вид открытым на несколько секунд…")
	var report: Dictionary = await TerrainDiagnostics.capture(get_tree(), viewport, projection)
	if is_instance_valid(_terrain_diagnostics_button): _terrain_diagnostics_button.disabled = false
	if is_instance_valid(_trace_button): _trace_button.disabled = false
	if report.is_empty():
		_status("Не удалось получить счётчики 3D-вида.")
		return
	report["map_id"] = map.map_id if is_instance_valid(map) else "map_closed_during_capture"
	report["scene_path"] = scene.scene_file_path if is_instance_valid(scene) else ""
	var path: String = TerrainDiagnostics.save_report(report)
	if path.is_empty():
		_status("Не удалось сохранить отчёт в user://.")
		return
	var terrain: Dictionary = report.terrain
	var view: Dictionary = report.viewport
	_terrain_diagnostics_summary.text = "Грани %.0f мс · Mesh %.0f мс · коллизия %.0f мс\nКадр p95 %.1f мс · 3D draw calls %.0f + тени %.0f\nGPU 3D %s · %d/%d участков" % [
		float(terrain.geometry_us) / 1000.0, float(terrain.mesh_resource_us) / 1000.0,
		float(terrain.collision_shape_us + terrain.collision_attach_us) / 1000.0, float(view.frame_interval_ms_p95),
		float(view.visible_draw_calls_median), float(view.shadow_draw_calls_median),
		"%.1f мс" % float(view.render_gpu_ms_median) if bool(report.gpu_timer_available) else "н/д",
		int(terrain.built_tiles), int(terrain.built_tiles) + int(terrain.pending_tiles)]
	_terrain_diagnostics_summary.show()
	_status("Отчёт сохранён: %s" % ProjectSettings.globalize_path(path))

func _refresh_dirty_status() -> void:
	var started := Time.get_ticks_usec() if _compact_trace.recording else 0
	if is_instance_valid(enabled): enabled.text = "Редактировать мир%s" % (" · %d*" % sessions.dirty_count(scene) if sessions.dirty_count(scene) > 0 else "")
	_update_overlay()
	if started > 0: _compact_trace.record_dirty_status(Time.get_ticks_usec() - started)

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
	active_changed.emit(true)
	if is_instance_valid(library_favorites_panel): library_favorites_panel.show()
	sidebar.show()
	inspector_panel.show()
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
	if _trace.recording: _stop_trace()
	if _compact_trace.recording: _stop_compact_trace()
	_clear_experiment()
	if is_instance_valid(_experiment_toggle): _experiment_toggle.set_pressed_no_signal(false)
	_set_working_water(false)
	active = false
	active_changed.emit(false)
	if is_instance_valid(library_favorites_panel): library_favorites_panel.hide()
	enabled.set_pressed_no_signal(false)
	sidebar.hide()
	inspector_panel.hide()
	toolbar.get_child(1).hide()
	selecting = false
	picking_object = false
	hover.clear()
	if plugin != null:
		plugin._stop_scene_object_brush()
		plugin._voxel_object_toolbar.show()
		plugin._world_surface_selector.refresh_context()
		plugin._battlefield_painter.refresh_context()
	for current in sessions.entries.values():
		var target: Node = current.target.get_ref()
		sessions._show_originals(current,true)
		if target is EmberMapLoader:
			if current.get("compact", false): target.set_editor_terrain_preview(null)
			else: target.set_editor_surface_preview(null)
		if is_instance_valid(current.preview): current.preview.free(); current.preview = null
	_update_overlay()

func scene_changed(root: Node) -> void:
	clear_compact_extension_preview()
	_clear_compact_grid_overlay()
	if _trace.recording: _stop_trace()
	if _compact_trace.recording:
		cancel_stroke()
		_stop_compact_trace()
	for reference in _background_water:
		var node: MeshInstance3D = reference.get_ref()
		if is_instance_valid(node): RenderingServer.instance_set_visible(node.get_instance(),node.is_visible_in_tree())
	_background_water.clear()
	cancel_stroke()
	_clear_experiment()
	if is_instance_valid(_experiment_toggle): _experiment_toggle.set_pressed_no_signal(false)
	sessions.write_recovery()
	scene = root as Node3D
	map = root as EmberMapLoader if root is EmberMapLoader else root.find_child("Map",true,false) as EmberMapLoader if root != null else null
	if map != null and map.compact_terrain != null and is_instance_valid(terrain_edit_scale):
		terrain_edit_scale.select(0)
		terrain_height_step.select(0)
		brush_shape.select(0)
	entry = {}
	edit_region = Rect2i()
	if active: _target_changed(target_choice.selected)
	_refresh_experiment_gate()

func _target_changed(index: int) -> void:
	cancel_stroke()
	if _trace.recording: _stop_trace()
	if _compact_trace.recording: _stop_compact_trace()
	create_region = false
	selecting = false
	if not entry.is_empty(): entry.scope = edit_region
	entry = {}
	if scene == null or map == null:
		_refresh_target_actions()
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
		_attach_trace_projection()
		if _compact_active(): _compact_brush.configure(entry, sessions.undo, scene)
		_refresh_palette()
		_category_changed(category.selected)
		_status("%s · один мазок — одно Undo · Ctrl+S сохраняет всё" % ("Компактная земля" if _compact_active() else entry.resource.display_name))
	else: _status(sessions.error if index == 0 else "Выберите voxel-объект кнопкой или нажмите на него в сцене.")
	_refresh_target_actions()
	if hide_water.button_pressed: _set_working_water(true)
	_refresh_scope()
	_tool_changed()
	_refresh_experiment_gate()

func _refresh_target_actions() -> void:
	if is_instance_valid(create_ground_button): create_ground_button.visible = target_choice.selected == 0 and not _compact_active()
	if is_instance_valid(open_canvas_button): open_canvas_button.visible = target_choice.selected == 1 or not _compact_active()
	if is_instance_valid(_terrain_diagnostics_button): _terrain_diagnostics_button.visible = _compact_active()
	if is_instance_valid(_terrain_diagnostics_summary): _terrain_diagnostics_summary.visible = _compact_active() and not _terrain_diagnostics_summary.text.is_empty()

func _category_changed(index: int, stop_scene_brush := true) -> void:
	cancel_stroke()
	if plugin != null and stop_scene_brush: plugin._stop_scene_object_brush()
	category.select(index)
	for i in category_buttons.size(): category_buttons[i].set_pressed_no_signal(i == index)
	_refresh_brush_scale_settings()
	tools.clear()
	var names: Array = ([
		["Рельеф ↑","Рельеф ↓","Сгладить","Площадка","Неровности"], ["Покрасить"],
		["Вода · открытый уровень","Убрать воду"], ["Расстановка объектов"],
	] if _compact_active() else [
		["Поднять","Опустить","Лепка · добавить","Лепка · убрать","Сгладить","Площадка","Берег и дно","Генератор рельефа","Тянуть · мягко"],
		["Покрасить","Песок · крупные пятна"], ["Вода · открытый уровень","Убрать воду"], ["Расстановка объектов"],
	])[index]
	var modes: Array = ([
		["raise","lower","smooth","level","generator"], ["paint"], ["water","dry"], ["objects"],
	] if _compact_active() else [
		["raise","lower","add","remove","smooth","level","shore","generator","grab"], ["paint","sand"], ["water","dry"], ["objects"],
	])[index]
	for i in names.size(): tools.add_item(names[i]); tools.set_item_metadata(i,modes[i])
	if tools.item_count > 0: tools.select(0)
	for button in _tool_buttons: _target_buttons.erase(button); button.free()
	_tool_buttons.clear()
	for i in names.size():
		var tool_index := i
		var button := Button.new()
		button.text = TOOL_LABELS.get(str(modes[i]),names[i])
		button.icon = _editor_icon(TOOL_ICONS.get(str(modes[i]),&"ToolSelect"))
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.theme_type_variation = &"WorkshopToolButton"
		button.tooltip_text = "Инструмент: %s" % names[i]
		button.pressed.connect(func():
			tools.select(tool_index)
			cancel_stroke()
			_tool_changed()
		)
		tool_list.add_child(button)
		_tool_buttons.append(button)
		_target_buttons.append(button)
	object_parameters.visible = index == 3
	category.icon = _editor_icon([&"HeightMapShape3D",&"Paint",&"GradientTexture2D",&"MeshInstance3D"][index])
	object_shelf_toggle.visible = index == 3
	favorites_box.visible = index == 3 and object_shelf_toggle.button_pressed
	_tool_changed()

func _mode() -> String:
	return str(tools.get_selected_metadata()) if tools.selected >= 0 else "raise"

func _compact_edit_scale() -> String:
	return "coarse" if terrain_edit_scale.selected == 0 else "medium" if terrain_edit_scale.selected == 1 else "detail"

func _tool_changed() -> void:
	if not is_instance_valid(palette): return
	for i in _tool_buttons.size():
		_tool_buttons[i].set_pressed_no_signal(i == tools.selected)
	var coarse_profile := _compact_active() and terrain_edit_scale.selected != 2
	var active_parameters := BrushParameters.active_for(_mode(),_compact_active(),coarse_profile,compact_level_from_point.button_pressed)
	if is_instance_valid(inspector_title): inspector_title.text = "Параметры · %s" % tools.get_item_text(tools.selected) if tools.selected >= 0 else "Параметры кисти"
	if is_instance_valid(inspector_hint): inspector_hint.text = "Ступени по %s блока. Ячейки %s выравниваются." % ["¼" if terrain_height_step.selected == 0 else "½", "8×8 вокселей" if terrain_edit_scale.selected == 0 else "2×2 вокселя"] if coarse_profile and category.selected == 0 else TOOL_HINTS.get(_mode(),"")
	if is_instance_valid(inspector_icon): inspector_icon.texture = _editor_icon(TOOL_ICONS.get(_mode(),&"ToolSelect"))
	for parameter_id: String in _brush_parameter_controls:
		var control: Control = _brush_parameter_controls[parameter_id]
		control.visible = parameter_id in active_parameters
	material_title.visible = "palette" in active_parameters
	material_title.text = "ЦВЕТ ВОДЫ" if category.selected == 2 else "ЦВЕТ ПОВЕРХНОСТИ"
	if is_instance_valid(tool_settings_title):
		var headings := {"level":"ПЛОЩАДКА","shore":"БЕРЕГ И ДНО","generator":"НЕРОВНОСТИ","grab":"ПЕРЕМЕЩЕНИЕ","water":"ВОДА"}
		tool_settings_title.text = headings.get(_mode(),"ДОПОЛНИТЕЛЬНО")
		tool_settings_title.visible = advanced.get_children().any(func(control): return control.visible)

func _parameter_group(control: SpinBox) -> Control:
	return control.get_meta("parameter_group",control.get_parent()) as Control

func _refresh_palette() -> void:
	if entry.is_empty(): return
	_refresh_brush_scale_settings()
	for choice in [palette,sand_palette]:
		choice.clear()
		for index in range(1,entry.resource.palette.size()):
			var color: Color = entry.resource.palette[index]
			choice.add_item("Цвет %d · #%s" % [index,color.to_html(false)])
			choice.set_item_metadata(choice.item_count-1,index)
	if sand_palette.item_count > 2: sand_palette.select(2)
	_refresh_palette_swatch()

func _refresh_brush_scale_settings() -> void:
	if not is_instance_valid(radius) or entry.is_empty(): return
	var profile := CompactBrushMath.edit_profile(_compact_edit_scale()) if _compact_active() else {}
	var steps_per_block: float = float(EmberTerrainPilotResource.CELLS_PER_BLOCK) / float(profile.cell_stride) if _compact_active() else entry.resource.normalized_density()
	radius.min_value = 1.0 / steps_per_block
	radius.step = radius.min_value
	radius_slider.min_value = radius.min_value
	radius_slider.step = radius.step

func _refresh_palette_swatch() -> void:
	if not is_instance_valid(palette_swatch): return
	palette_swatch.color = WorkshopTheme.SURFACE_RAISED
	if entry.is_empty() or palette.selected < 0: return
	var index := int(palette.get_selected_metadata())
	if index >= 0 and index < entry.resource.palette.size(): palette_swatch.color = entry.resource.palette[index]

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
	_category_changed(3,false)
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
	if _compact_active():
		_status("Компактная земля редактируется прямо в 3D. Canvas остаётся для voxel-объектов.")
		return
	cancel_stroke()
	var workspace := EditorInterface.get_editor_main_screen().find_child(plugin.SURFACE_WORKSPACE_NODE,true,false) as EmberVoxelSculptWorkspace
	if workspace != null and workspace.open_world_draft(entry,sessions,save_all): EditorInterface.set_main_screen_editor(plugin.SURFACE_MAIN_SCREEN)

func _save_native_scene() -> int:
	return EditorInterface.save_scene() if Engine.is_editor_hint() else OK

func save_all(defer_scene_save := false) -> bool:
	if _experiment_waiting_exact or _experiment_baking:
		_status("Дождитесь точного отображения экспериментального мазка перед сохранением.")
		return false
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
	# Global save is independent of viewport focus. Undo/Redo still belongs to
	# Godot; this only repairs a stale input mask before Godot handles the key.
	if Engine.is_editor_hint() and active and _compact_active() and event is InputEventKey and event.pressed and not event.echo and event.is_command_or_control_pressed() and event.keycode in [KEY_Z,KEY_Y] and not _compact_brush.active():
		var focused := get_viewport().gui_get_focus_owner()
		if not (focused is LineEdit or focused is TextEdit): _repair_compact_mouse_mask()
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
	var grid_started := Time.get_ticks_usec() if _compact_trace.recording else 0
	_sync_compact_grid()
	if grid_started > 0:
		var grid_elapsed := Time.get_ticks_usec() - grid_started
		if _compact_brush.active(): _compact_trace.stage("grid_preview", grid_elapsed)
		else: _compact_hover_grid_stats["sync_usec"] = grid_elapsed
	if plugin != null: plugin.update_overlays()

func _pick_compact(position: Vector2) -> Dictionary:
	if not _compact_active() or camera == null or map == null: return {}
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	if projection == null: return {}
	var origin := camera.project_ray_origin(position)
	return projection.pick_ground_top(origin,origin+camera.project_ray_normal(position)*camera.far)

func _pick(position: Vector2) -> Dictionary:
	if entry.is_empty() or camera == null: return {}
	var frame: Transform3D = sessions.frame(entry)
	if is_zero_approx(frame.basis.determinant()): return {}
	var inverse := frame.affine_inverse()
	var origin: Vector3 = inverse * camera.project_ray_origin(position)
	var direction: Vector3 = inverse.basis * camera.project_ray_normal(position)
	var result: Dictionary = _experiment.pick(origin,direction) if _experiment_stroke and _experiment != null else Model.pick(entry.resource,origin,direction)
	if result.is_empty():
		var local_height: float = (plane_height.value-entry.origin.y) / (map.imported_tile_size if entry.target.get_ref() is EmberMapLoader else maxf(frame.basis.y.length(),0.001))
		var point = Plane(Vector3.UP,local_height).intersects_ray(origin,direction)
		if point != null:
			var cell := Vector3i(Vector3(point) * entry.resource.normalized_density())
			if Model.contains(cell,entry.resource.grid_size()): result = {"hit":Model.INVALID_CELL,"adjacent":cell,"normal":Vector3i.UP,"empty_floor":true}
	return result

func _region_frame() -> Transform3D:
	if _compact_active(): return map.global_transform*Transform3D(Basis.IDENTITY*map.imported_tile_size,Vector3.ZERO)
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
	var footprint: Vector2i = map.authored_size_blocks if create_region or entry.is_empty() or _compact_active() else Vector2i(entry.resource.size_blocks.x,entry.resource.size_blocks.z)
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
	var received_usec := Time.get_ticks_usec() if _trace.recording and event is InputEventMouse else 0
	var scheduled_usec := int(event.get_meta("ember_scheduled_usec",0)) if received_usec > 0 else 0
	camera = next_camera
	if _compact_active() and category.selected != 3:
		return _forward_compact(event)
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
		if event.is_command_or_control_pressed() and event.keycode in [KEY_Z,KEY_Y]:
			if _experiment_waiting_exact:
				_status("Сначала дождитесь перехода на точную землю, затем Undo/Redo.")
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			cancel_stroke()
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
			var pick_started := Time.get_ticks_usec() if _trace.recording and dragging else 0
			hover = _pick(event.position)
			if dragging and not released:
				if _trace.recording: _trace.stage("input_pick",Time.get_ticks_usec()-pick_started)
				if _trace.recording: _trace.input("move",received_usec,event.position,_center(hover),scheduled_usec)
				var enqueue_started := Time.get_ticks_usec() if _trace.recording else 0
				_queue_pick(hover)
				if _trace.recording: _trace.stage("input_enqueue",Time.get_ticks_usec()-enqueue_started)
		var overlay_started := Time.get_ticks_usec() if _trace.recording and dragging else 0
		_update_overlay()
		if _trace.recording and dragging: _trace.stage("input_overlay_ui",Time.get_ticks_usec()-overlay_started)
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
			elif dragging:
				released = true
				var pick_started := Time.get_ticks_usec() if _trace.recording else 0
				var final_pick := _pick(event.position)
				if _trace.recording: _trace.stage("input_pick",Time.get_ticks_usec()-pick_started)
				if _trace.recording: _trace.input("release",received_usec,event.position,_center(final_pick),scheduled_usec)
				var enqueue_started := Time.get_ticks_usec() if _trace.recording else 0
				_queue_pick(final_pick)
				if _trace.recording: _trace.stage("input_enqueue",Time.get_ticks_usec()-enqueue_started)
		elif not dragging and grab.is_empty():
			if _experimental_enabled() and (_experiment == null or not _experiment.prepared):
				_status("Landscape V2: дождитесь подготовки временной поверхности.")
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			var pick_started := Time.get_ticks_usec() if _trace.recording else 0
			hover = _pick(event.position)
			if _mode() == "grab": _begin_grab(event.position)
			else: _begin_stroke(hover,event.ctrl_pressed,received_usec,event.position,scheduled_usec,Time.get_ticks_usec()-pick_started if _trace.recording else 0)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _forward_compact(event: InputEvent) -> int:
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_command_or_control_pressed() and event.keycode in [KEY_Z,KEY_Y]:
			if _compact_brush.active():
				cancel_stroke()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			_repair_compact_mouse_mask()
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if event.is_command_or_control_pressed() and event.keycode == KEY_S:
			save_all()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_ESCAPE:
			cancel_stroke()
			selecting = false
			region_preview = Rect2i()
			_update_overlay()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode in [KEY_BRACKETLEFT,KEY_BRACKETRIGHT]:
			if not dragging: radius.value += radius.step * (-1 if event.keycode == KEY_BRACKETLEFT else 1)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouse and (event.alt_pressed or event.button_mask & (MOUSE_BUTTON_MASK_RIGHT|MOUSE_BUTTON_MASK_MIDDLE)):
		if dragging: cancel_stroke()
		hover.clear()
		_update_overlay()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion:
		var hover_started := Time.get_ticks_usec() if _compact_trace.recording and not dragging and not selecting else 0
		var hover_pick_usec := 0
		if selecting:
			var block := _plane_cell(event.position)
			if region_anchor.x >= 0 and block.x >= 0:
				region_preview = Rect2i(region_anchor.min(block),region_anchor.max(block)-region_anchor.min(block)+Vector2i.ONE)
		else:
			var pick_started := Time.get_ticks_usec() if _compact_trace.recording else 0
			hover = _pick_compact(event.position)
			if pick_started > 0:
				var elapsed_pick := Time.get_ticks_usec() - pick_started
				if dragging: _compact_trace.stage("input_pick", elapsed_pick)
				else: hover_pick_usec = elapsed_pick
			if dragging and not hover.is_empty():
				var stamp_started := Time.get_ticks_usec() if _compact_trace.recording else 0
				_compact_brush.stamp(hover.cell,_compact_bounds())
				if stamp_started > 0: _compact_trace_step("move", stamp_started)
		var overlay_started := Time.get_ticks_usec() if hover_started > 0 else 0
		_update_overlay()
		if hover_started > 0:
			var cell := hover.get("cell", Vector2i(-1, -1)) as Vector2i
			_compact_trace.record_hover({"cell": [cell.x, cell.y],
				"radius_blocks": radius.value, "pick_usec": hover_pick_usec,
				"overlay_usec": Time.get_ticks_usec() - overlay_started,
				"input_usec": Time.get_ticks_usec() - hover_started,
				"grid": _compact_hover_grid_stats})
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if selecting:
			var block := _plane_cell(event.position)
			if event.pressed: region_anchor = block
			elif region_anchor.x >= 0 and block.x >= 0:
				edit_region = Rect2i(region_anchor.min(block),region_anchor.max(block)-region_anchor.min(block)+Vector2i.ONE)
				selecting = false
				region_preview = Rect2i()
				_refresh_scope()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.pressed:
			var press_pick_started := Time.get_ticks_usec() if _compact_trace.recording else 0
			hover = _pick_compact(event.position)
			var press_pick_usec := Time.get_ticks_usec() - press_pick_started if press_pick_started > 0 else 0
			if not hover.is_empty():
				var mode := _mode()
				if event.ctrl_pressed:
					mode = {"raise":"lower","lower":"raise","water":"dry","dry":"water"}.get(mode,mode)
				var selected_palette := int(palette.get_selected_metadata()) if palette.selected >= 0 else 1
				var direction := compact_direction.selected
				var target_world := roundi(plane_height.value) if mode == "level" and not compact_level_from_point.button_pressed else -99999
				var coarse_profile := terrain_edit_scale.selected != 2
				var height_step := (CompactBrushMath.QUARTER_BLOCK_HEIGHT_STEP if terrain_height_step.selected == 0 else CompactBrushMath.HALF_BLOCK_HEIGHT_STEP) if coarse_profile else 1
				var height_strength := roundi(coarse_depth.value) * height_step if coarse_profile else roundi(depth.value)
				if _compact_trace.recording:
					_compact_trace.begin_brush_stroke({"mode": mode, "radius_blocks": radius.value,
						"edit_scale": _compact_edit_scale(), "brush_shape": "square" if brush_shape.selected == 0 else "circle",
						"height_step_voxels": height_step, "strength_voxels": height_strength,
						"feature_scale": compact_feature_scale.value, "detail": compact_detail.value})
					_compact_trace.stage("press_pick", press_pick_usec)
				var begin_started := Time.get_ticks_usec() if _compact_trace.recording else 0
				if _compact_brush.begin(mode,radius.value,height_strength,selected_palette,roundi(water_height.value),roundi(compact_feature_scale.value),roundi(compact_detail.value),roundi(compact_seed.value),direction,target_world,_compact_edit_scale(),"square" if brush_shape.selected == 0 else "circle",height_step):
					if begin_started > 0:
						_compact_trace.stage("brush_begin", Time.get_ticks_usec() - begin_started)
						_compact_brush.diagnostic_sink = _compact_trace
					dragging = true
					_set_busy(true)
					var first_started := Time.get_ticks_usec() if _compact_trace.recording else 0
					_compact_brush.stamp(hover.cell,_compact_bounds())
					if first_started > 0: _compact_trace_step("first", first_started)
				elif _compact_trace.recording:
					_compact_trace.finish_brush_stroke(0, true)
		else:
			if dragging:
				var release_pick_started := Time.get_ticks_usec() if _compact_trace.recording else 0
				var final_pick := _pick_compact(event.position)
				if release_pick_started > 0: _compact_trace.stage("release_pick", Time.get_ticks_usec() - release_pick_started)
				if not final_pick.is_empty():
					var final_started := Time.get_ticks_usec() if _compact_trace.recording else 0
					_compact_brush.stamp(final_pick.cell,_compact_bounds())
					if final_started > 0: _compact_trace_step("release", final_started)
				var changed_columns := _compact_brush.changed_column_count() if _compact_trace.recording else 0
				var end_started := Time.get_ticks_usec() if _compact_trace.recording else 0
				_compact_brush.end()
				_compact_brush.diagnostic_sink = null
				if end_started > 0:
					_compact_trace.stage("undo_commit", Time.get_ticks_usec() - end_started)
					_compact_trace.finish_brush_stroke(changed_columns)
				dragging = false
				_set_busy(false)
				sessions.changed.emit()
				_status("Мазок применён · Ctrl+Z отменяет · Ctrl+S сохраняет карту")
		_update_overlay()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _repair_compact_mouse_mask() -> void:
	# Godot's native Undo refuses any nonzero mouse mask. A release outside its
	# window can leave the cached mask pressed after our stroke has ended.
	Input.flush_buffered_events()
	var mask := Input.get_mouse_button_mask() & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)
	for button in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
		var bit: int = 1 << (int(button) - 1)
		if mask & bit == 0: continue
		var release := InputEventMouseButton.new()
		release.button_index = button
		release.button_mask = mask & ~bit
		release.pressed = false
		Input.parse_input_event(release)
		mask &= ~bit
	Input.flush_buffered_events()

func _compact_bounds() -> Rect2i:
	return Rect2i(edit_region.position * EmberTerrainPilotResource.CELLS_PER_BLOCK, edit_region.size * EmberTerrainPilotResource.CELLS_PER_BLOCK) if clip.button_pressed and edit_region.has_area() else Rect2i()

func _center(pick: Dictionary, mode := "") -> Vector3i:
	if pick.is_empty(): return Model.INVALID_CELL
	if mode == "": mode = stroke_mode if dragging else _mode()
	if mode == "add": return pick.get("adjacent",Model.INVALID_CELL)
	return pick.get("adjacent",Model.INVALID_CELL) if pick.get("empty_floor",false) else pick.get("hit",Model.INVALID_CELL)

func _begin_stroke(pick: Dictionary, inverse := false, input_usec := 0, input_position := Vector2.ZERO, scheduled_usec := 0, pick_usec := 0) -> void:
	if entry.is_empty(): return
	stroke_mode = _mode()
	if inverse:
		stroke_mode = {"raise":"lower","lower":"raise","add":"remove","remove":"add","water":"dry","dry":"water"}.get(stroke_mode,stroke_mode)
	if _experimental_enabled() and stroke_mode not in ["level","raise","lower"]:
		_status("Landscape V2 Experimental: для ручного gate доступны Площадка, Поднять и Опустить. Переключите Legacy для других инструментов.")
		return
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
	var baseline_started := Time.get_ticks_usec() if _trace.recording else 0
	baseline = entry.resource.duplicate_model()
	var baseline_usec := Time.get_ticks_usec()-baseline_started if _trace.recording else 0
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
	if _trace.recording:
		_trace.begin_stroke({"tool":stroke_mode,"mode":"landscape_v2_experimental" if _experimental_enabled() else "legacy","radius_blocks":radius.value,"radius_voxels":stroke_radius,"depth_voxels":stroke_depth,"palette":stroke_palette,"input_source":"main_3d_forward_input" if input_usec > 0 else "direct_call_not_real_input","resource_grid":[entry.resource.grid_size().x,entry.resource.grid_size().y,entry.resource.grid_size().z]},input_usec if input_usec > 0 else stroke_started,input_position,center,scheduled_usec)
		_trace.stage("input_pick",pick_usec)
		_trace.stage("baseline_snapshot",baseline_usec)
	last_cell = Model.INVALID_CELL
	_experiment_stroke = _experimental_enabled()
	if _experiment_stroke:
		var scope := Rect2i(edit_region.position*density,edit_region.size*density) if clip.button_pressed and edit_region.has_area() else Rect2i()
		_experiment.begin_stroke(baseline,stroke_mode,stroke_radius,stroke_depth,int(stroke_options.level),stroke_palette,scope,_trace_projection(),int(stroke_options.empty_floor))
		if _trace.recording: _trace.milestone("experimental_preview_shown")
	var enqueue_started := Time.get_ticks_usec() if _trace.recording else 0
	_queue_pick(pick)
	if _trace.recording: _trace.stage("input_enqueue",Time.get_ticks_usec()-enqueue_started)

func _queue_pick(pick: Dictionary) -> void:
	var cell := _center(pick)
	if cell == Model.INVALID_CELL or cell == last_cell: return
	var previous := cell if last_cell == Model.INVALID_CELL else last_cell
	var queued_at := Time.get_ticks_usec() if _trace.recording else 0
	var appended := 0
	if stroke_mode in ["add","remove","paint"]:
		var count := clampi(ceili(Vector3(cell-previous).length()/maxf(1,stroke_radius*0.4)),1,2048)
		for i in range(1,count+1):
			var sample := {"from":Vector3i(Vector3(previous).lerp(Vector3(cell),float(i)/count)),"to":Vector3i(Vector3(previous).lerp(Vector3(cell),float(i)/count)),"normal":pick.get("normal",Vector3i.UP)}
			if _trace.recording: sample.queued_usec = queued_at
			queue.append(sample)
		appended = count
	else:
		var sample := {"from":previous,"to":cell,"normal":pick.get("normal",Vector3i.UP)}
		if _trace.recording: sample.queued_usec = queued_at
		queue.append(sample)
		appended = 1
	if _trace.recording: _trace.queue_sample(appended,queue.size())
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
	if _trace.recording: _trace.write_event(changed.size())
	return changed

func _apply_batch(changes: Dictionary, notify_projection := true) -> void:
	if changes.is_empty(): return
	var prepare_started := Time.get_ticks_usec() if _trace.recording else 0
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
	if _trace.recording: _trace.stage("batch_prepare",Time.get_ticks_usec()-prepare_started)
	var write_started := Time.get_ticks_usec() if _trace.recording else 0
	for channel in updates:
		for index in _write_values(channel,updates[channel]): dirty[index] = true
	if _trace.recording: _trace.stage("draft_write",Time.get_ticks_usec()-write_started)
	if notify_projection and not dirty.is_empty():
		var notify_started := Time.get_ticks_usec() if _trace.recording else 0
		entry.resource.notify_geometry_changed(PackedInt32Array(dirty.keys()))
		if _trace.recording: _trace.stage("notify_and_queue_projection",Time.get_ticks_usec()-notify_started)

func _process(_elapsed: float) -> void:
	var compact_process_started := Time.get_ticks_usec() if _compact_trace.recording else 0
	sessions.poll_recovery()
	if _trace.recording:
		var projection := _trace_projection()
		var oldest_brush_input := _job_queued_usec if job != null else int(queue.front().get("queued_usec",0)) if not queue.is_empty() else 0
		_trace.frame(queue.size(),job != null,projection.pending_chunk_count() if is_instance_valid(projection) else -1,projection.pending_physics_chunk_count() if is_instance_valid(projection) else -1,oldest_brush_input,projection.rendered_chunk_count() if is_instance_valid(projection) else -1,projection.collision_chunk_count() if is_instance_valid(projection) else -1)
	if _recovery_due > 0 and Time.get_ticks_msec() >= _recovery_due and Time.get_ticks_msec()-_last_recovery >= 30000 and not dragging and grab.is_empty():
		if sessions.start_periodic_recovery():
			_last_recovery = Time.get_ticks_msec()
			_recovery_due = 0
	if _compact_active():
		if compact_process_started > 0: _compact_trace.record_editor_process(Time.get_ticks_usec() - compact_process_started)
		return
	if _experimental_enabled() and _experiment != null:
		if not _experiment.prepared and not dragging:
			if _experiment.prepare_step():
				_status("Landscape V2 готов. Площадка / Поднять / Опустить; переключатель сравнивает с Legacy.")
			elif Engine.get_process_frames() % 30 == 0:
				_status("Landscape V2: подготавливаю %s…" % _experiment.preparation_progress())
		if _experiment_waiting_exact and not dragging:
			_experiment.ensure_ground_hidden()
			var exact_projection := _trace_projection()
			if is_instance_valid(exact_projection) and exact_projection.is_projection_complete():
				_experiment_settle_frames += 1
				if _experiment_settle_frames >= 2:
					_experiment.end_visual()
					if _trace.recording: _trace.milestone("experimental_preview_swap")
					_experiment_waiting_exact = false
					_set_busy(false)
					_status("Точная Surface готова · Ctrl+Z / Ctrl+Y проверяют Undo/Redo. Запишите ощущения от перехода.")
			else:
				_experiment_settle_frames = 0
	if not grab.is_empty(): _process_grab(); return
	if not dragging: return
	if not is_instance_valid(entry.target.get_ref()): cancel_stroke(); _status("Цель удалена; мазок отменён."); return
	if _experiment_stroke:
		_process_experiment_stroke()
		return
	if job == null and not queue.is_empty():
		var sample := queue.pop_front()
		_job_queued_usec = int(sample.get("queued_usec",0))
		if _trace.recording: _trace.job_wait(Time.get_ticks_usec()-int(sample.get("queued_usec",Time.get_ticks_usec())))
		var setup_started := Time.get_ticks_usec() if _trace.recording else 0
		job = _new_job(sample)
		if _trace.recording: _trace.stage("job_initialize",Time.get_ticks_usec()-setup_started)
	if job != null:
		var step_started := Time.get_ticks_usec() if _trace.recording else 0
		# Spend a little more on the current job only while later input waits.
		# The same tiles and samples stay ordered; pointer-up still commits once.
		var step_budget := BRUSH_BACKLOG_STEP_BUDGET_USEC if not queue.is_empty() else BRUSH_STEP_BUDGET_USEC
		var changes: Dictionary = job.step(step_budget)
		if _trace.recording: _trace.job_step()
		if _trace.recording: _trace.stage("brush_evaluation",Time.get_ticks_usec()-step_started)
		_apply_batch(changes)
		if job.done: job = null; _job_queued_usec = 0
	if released and job == null and queue.is_empty():
		_finish_stroke()

func _process_experiment_stroke() -> void:
	if _experiment == null:
		cancel_stroke()
		return
	_experiment.ensure_ground_hidden()
	if not _experiment_baking:
		var input_started := Time.get_ticks_usec()
		while not queue.is_empty() and Time.get_ticks_usec() - input_started < BRUSH_STEP_BUDGET_USEC:
			var sample := queue.pop_front()
			if _trace.recording:
				_trace.job_wait(Time.get_ticks_usec()-int(sample.get("queued_usec",Time.get_ticks_usec())))
				_trace.job_step()
			var result: Dictionary = _experiment.apply_sample(sample.from,sample.to)
			if _trace.recording:
				_trace.stage("experimental_height_eval",int(result.height_cpu_usec))
				_trace.stage("experimental_gpu_preview_upload",int(result.upload_cpu_usec))
		if released and queue.is_empty():
			_experiment.begin_bake()
			_experiment_baking = true
			if _trace.recording: _trace.milestone("experimental_bake_started")
	if not _experiment_baking: return
	var bake_started := Time.get_ticks_usec()
	var changes: Dictionary = _experiment.bake_step(baseline,BRUSH_STEP_BUDGET_USEC)
	if _trace.recording:
		_trace.stage("experimental_dirty_bake",maxi(0,Time.get_ticks_usec()-bake_started-_experiment.last_bake_preview_sync_usec))
		if _experiment.last_bake_preview_sync_usec > 0:
			_trace.stage("experimental_post_bake_preview_sync",_experiment.last_bake_preview_sync_usec)
	if not changes.is_empty():
		_apply_batch(changes,false)
		for index in changes: _experiment_dirty_indices[index] = true
	if not _experiment.bake_done(): return
	_experiment_baking = false
	if _trace.recording: _trace.milestone("experimental_bake_finished")
	if not _experiment_dirty_indices.is_empty():
		var notify_started := Time.get_ticks_usec() if _trace.recording else 0
		entry.resource.notify_geometry_changed(PackedInt32Array(_experiment_dirty_indices.keys()))
		if _trace.recording: _trace.stage("notify_and_queue_projection",Time.get_ticks_usec()-notify_started)
		_experiment_waiting_exact = true
		_experiment_settle_frames = 0
	elif not _experiment_waiting_exact:
		_experiment.end_visual()
	_finish_stroke()
	_experiment_stroke = false
	if _experiment_waiting_exact:
		_set_busy(true)
		_status("Landscape V2: можно рисовать следующий мазок; точная Surface и физика догоняют preview.")
	else:
		_status("Landscape V2: мазок ничего не изменил.")
	_experiment_dirty_indices.clear()

func _finish_stroke() -> void:
	var prepare_started := Time.get_ticks_usec() if _trace.recording else 0
	var channels := delta.duplicate(true)
	for channel in delta:
		if channel == "__sizes": continue
		for index in delta[channel]:
			var pair: Vector2i = delta[channel][index]
			if pair.x == pair.y: channels[channel].erase(index)
		if channels[channel].is_empty(): channels.erase(channel)
	if _trace.recording: _trace.stage("undo_prepare",Time.get_ticks_usec()-prepare_started)
	var changed_primary := (channels.get("voxels",channels.get("surface_fill_levels",{})) as Dictionary).size()
	if channels.size() > 1:
		var indices := PackedInt32Array(delta.get("voxels",delta.get("surface_fill_levels",{})).keys())
		var commit_started := Time.get_ticks_usec() if _trace.recording else 0
		actions.commit_applied_delta(entry.resource,channels,indices,"Мир · " + stroke_mode)
		if _trace.recording: _trace.stage("undo_commit",Time.get_ticks_usec()-commit_started)
	else:
		for channel in delta.__sizes:
			var sizes: Vector2i = delta.__sizes[channel]
			if sizes.x == 0:
				var values: Variant = entry.resource.get(channel)
				values.resize(0)
				entry.resource.set(channel,values)
	last_stroke_usec = Time.get_ticks_usec()-stroke_started
	if _trace.recording: _trace.commit(changed_primary)
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
	if _compact_brush.active():
		var changed_columns := _compact_brush.changed_column_count() if _compact_trace.recording else 0
		_compact_brush.cancel()
		_compact_brush.diagnostic_sink = null
		if _compact_trace.recording: _compact_trace.finish_brush_stroke(changed_columns, true)
		dragging = false
		_set_busy(false)
		sessions.changed.emit()
		_update_overlay()
		return
	var had_experiment := _experiment_stroke or _experiment_waiting_exact
	var keep_exact_preview := _experiment_waiting_exact or (dragging and _experiment_stroke and not _experiment_dirty_indices.is_empty())
	if dragging and _trace.recording: _trace.cancel()
	if keep_exact_preview: _experiment_waiting_exact = true
	_set_busy(false)
	if not grab.is_empty():
		for field in Sessions.FIELDS: entry.resource.set(field,EmberVoxelModelResource.copy_authoring_value(grab.baseline.get(field)))
		entry.resource.notify_geometry_changed(PackedInt32Array())
		grab.clear()
	if dragging and not entry.is_empty() and baseline != null:
		if _experiment_stroke and _experiment != null: _experiment.cancel_stroke()
		var channels := delta.duplicate(true)
		channels.erase("__sizes")
		if not channels.is_empty(): actions._apply_delta(entry.resource,delta,false,PackedInt32Array(delta.get("voxels",delta.get("surface_fill_levels",{})).keys()))
	job = null
	_job_queued_usec = 0
	queue.clear()
	dragging = false
	released = false
	baseline = null
	delta.clear()
	if had_experiment:
		_experiment_stroke = false
		_experiment_baking = false
		_experiment_dirty_indices.clear()
		if keep_exact_preview:
			_experiment_settle_frames = 0
			_set_busy(true)
			_status("Мазок отменён; можно продолжать рисовать, точная Surface догоняет preview.")
		else:
			if _experiment != null: _experiment.end_visual()
			_experiment_waiting_exact = false
			call_deferred("_restart_experiment_after_history")

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
	if _compact_active():
		var selected_rect := region_preview if selecting and region_preview.has_area() else edit_region
		if selected_rect.has_area():
			var outline := PackedVector2Array()
			for corner in [selected_rect.position,Vector2i(selected_rect.end.x,selected_rect.position.y),selected_rect.end,Vector2i(selected_rect.position.x,selected_rect.end.y),selected_rect.position]:
				var frame_point := _region_frame()*Vector3(corner.x,_region_height(),corner.y)
				if camera.is_position_behind(frame_point): return
				outline.append(camera.unproject_position(frame_point))
			overlay.draw_polyline(outline,Color(0.3,0.8,1,0.9),2,true)
		if selecting: return
		if hover.is_empty(): return
		var terrain: EmberTerrainPilotResource = entry.resource
		var projection := map._visual_surface_projection as EmberTerrainPilotProjection
		if projection == null: return
		var points := PackedVector2Array()
		var center: Vector2i = hover.cell
		var profile := CompactBrushMath.edit_profile(_compact_edit_scale())
		var stride: int = profile.cell_stride
		var snapped_center := Vector2(Vector2i(center.x / stride,center.y / stride) * stride) + Vector2.ONE * (float(stride) * 0.5)
		var brush_radius := CompactBrushMath.preview_radius_voxels(radius.value, stride)
		for i in 65:
			var offset := Vector2.ZERO
			if brush_shape.selected == 0:
				var side := mini(i / 16,3)
				var along := 1.0 if i == 64 else float(i % 16) / 16.0
				match side:
					0: offset = Vector2(-1.0 + 2.0 * along,-1.0)
					1: offset = Vector2(1.0,-1.0 + 2.0 * along)
					2: offset = Vector2(1.0 - 2.0 * along,1.0)
					3: offset = Vector2(-1.0,1.0 - 2.0 * along)
			else:
				var angle := TAU * float(i) / 64.0
				offset = Vector2(cos(angle),sin(angle))
			var x := snapped_center.x + offset.x * brush_radius
			var z := snapped_center.y + offset.y * brush_radius
			var sample_x := clampi(floori(x),0,terrain.width-1)
			var sample_z := clampi(floori(z),0,terrain.depth-1)
			var height: int = terrain.heights[terrain.column_index(sample_x,sample_z)]
			var world := projection.to_global(Vector3(x,float(terrain.origin_y+height)+0.35,z))
			if camera.is_position_behind(world): return
			points.append(camera.unproject_position(world))
		overlay.draw_polyline(points,Color(1,0.78,0.3,0.10),8,true)
		overlay.draw_polyline(points,Color(1,0.84,0.48,0.28),4,true)
		overlay.draw_polyline(points,Color(1,0.92,0.72,0.94),1.5,true)
		return
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
				var top := int(_experiment.field.heights[x+z*size.x])-1 if _experiment_stroke and _experiment != null else Model._top_filled_y(entry.resource.voxels,size,x,z)
				if top >= 0: local.y = float(top+1)/density+0.02
		var world := frame*local
		if camera.is_position_behind(world): return
		points.append(camera.unproject_position(world))
	overlay.draw_polyline(points,Color(1,0.78,0.3,0.95),2,true)

func _sync_compact_grid() -> void:
	if _compact_trace.recording and not _compact_brush.active():
		_compact_hover_grid_stats = {"view_changed": 0, "tiles_visible": 0,
			"tiles_created": 0, "tiles_recycled": 0, "tiles_rebuilt": 0, "tiles_evicted": 0,
			"tile_mesh_usec": 0, "tile_node_usec": 0, "material_usec": 0,
			"selection_rebuilt": 0, "selection_mesh_usec": 0, "cache_size": 0,
			"overlay_tiles_changed": 0}
	if not active or not _compact_active() or hover.is_empty() or map == null:
		_clear_compact_grid_overlay()
		return
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	if projection == null or projection.document == null:
		_clear_compact_grid_overlay()
		return
	var center: Vector2i = hover.cell
	var stride: int = CompactBrushMath.edit_profile(_compact_edit_scale()).cell_stride
	var brush_radius := CompactBrushMath.preview_radius_voxels(radius.value, stride)
	var selected_x := center.x / stride * stride
	var selected_z := center.y / stride * stride
	var fade_center := Vector2(selected_x + float(stride) * 0.5, selected_z + float(stride) * 0.5)
	var fade_radius := brush_radius + float(CompactBrushMath.COARSE_CELL_SIZE) * 2.0
	var shape := brush_shape.selected
	var view_key := "%d:%d:%d:%d:%f:%d" % [projection.get_instance_id(), selected_x, selected_z, stride, brush_radius, shape]
	if view_key == _compact_grid_view_key:
		return
	if _compact_trace.recording and not _compact_brush.active():
		_compact_hover_grid_stats["view_changed"] = 1
	_sync_compact_grid_overlay(projection, fade_center, brush_radius, fade_radius, shape, Vector2(selected_x, selected_z), stride)
	_compact_grid_view_key = view_key


func _sync_compact_grid_overlay(projection: EmberTerrainPilotProjection, center: Vector2, brush_radius: float, fade_radius: float, shape: int, selected_origin: Vector2, stride: int) -> void:
	if _compact_grid_projection == null or _compact_grid_projection.get_ref() != projection:
		_clear_compact_grid_overlay()
		_compact_grid_projection = weakref(projection)
	var started := Time.get_ticks_usec() if _compact_trace.recording and not _compact_brush.active() else 0
	if _compact_grid_material == null:
		_compact_grid_material = ShaderMaterial.new()
		_compact_grid_material.shader = HoverGridShader
		_compact_grid_material.set_shader_parameter("subblock_size", float(CompactBrushMath.COARSE_CELL_SIZE))
		_compact_grid_material.set_shader_parameter("block_size", float(EmberTerrainPilotResource.CELLS_PER_BLOCK))
	_compact_grid_material.set_shader_parameter("fade_center", center)
	_compact_grid_material.set_shader_parameter("brush_radius", brush_radius)
	_compact_grid_material.set_shader_parameter("fade_radius", fade_radius)
	_compact_grid_material.set_shader_parameter("square_brush", shape == 0)
	_compact_grid_material.set_shader_parameter("selected_origin", selected_origin)
	_compact_grid_material.set_shader_parameter("selected_size", float(stride))
	if started > 0: _compact_hover_grid_stats["material_usec"] = Time.get_ticks_usec() - started
	var tile_size := EmberTerrainPilotProjection.TILE_SIZE
	var cols := ceili(float(projection.document.width) / tile_size)
	var rows := ceili(float(projection.document.depth) / tile_size)
	var visible := {}
	var visible_tiles: Array[Vector2i] = []
	for tz in range(maxi(0, floori((center.y - fade_radius) / tile_size)), mini(rows, ceili((center.y + fade_radius) / tile_size) + 1)):
		for tx in range(maxi(0, floori((center.x - fade_radius) / tile_size)), mini(cols, ceili((center.x + fade_radius) / tile_size) + 1)):
			var nearest := Vector2(clampf(center.x, float(tx * tile_size), float((tx + 1) * tile_size)), clampf(center.y, float(tz * tile_size), float((tz + 1) * tile_size)))
			var delta := (nearest - center).abs()
			if (maxf(delta.x, delta.y) if shape == 0 else delta.length()) >= fade_radius: continue
			var tile_key := Vector2i(tx, tz)
			visible[tile_key] = true
			visible_tiles.append(tile_key)
	_compact_grid_visible_tiles = visible
	var changed := projection.set_editor_hover_overlay(_compact_grid_material, visible_tiles)
	if started > 0:
		_compact_hover_grid_stats["tiles_visible"] = visible.size()
		_compact_hover_grid_stats["overlay_tiles_changed"] = changed
		_compact_hover_grid_stats["tile_node_usec"] = Time.get_ticks_usec() - started - int(_compact_hover_grid_stats["material_usec"])


func _clear_compact_grid_overlay() -> void:
	if _compact_grid_projection != null:
		var projection := _compact_grid_projection.get_ref() as EmberTerrainPilotProjection
		if is_instance_valid(projection):
			projection.set_editor_hover_overlay(null, [])
	_compact_grid_projection = null
	_compact_grid_visible_tiles.clear()
	_compact_grid_view_key = ""


func _compact_grid_visible_bounds() -> AABB:
	var bounds := AABB()
	var first := true
	var tile_size := EmberTerrainPilotProjection.TILE_SIZE
	for key in _compact_grid_visible_tiles:
		var tile_bounds := AABB(Vector3(key.x * tile_size, 0, key.y * tile_size), Vector3(tile_size, 1, tile_size))
		bounds = tile_bounds if first else bounds.merge(tile_bounds)
		first = false
	return bounds


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: cancel_stroke()

func _exit_tree() -> void:
	clear_compact_extension_preview()
	_clear_compact_grid_overlay()
	if is_instance_valid(library_favorites_panel): library_favorites_panel.queue_free()
	_set_working_water(false)
	cancel_stroke()
	_clear_experiment()
	sessions.release()
