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
const TerrainGeneration = preload("res://addons/ember_import/ember_compact_terrain_generation.gd")
const TerrainGenerationPanel = preload("res://addons/ember_import/ember_compact_terrain_generation_dialog.gd")
const TerrainPlan = preload("res://scripts/ember_terrain_plan_resource.gd")
const TerrainPlanPanel = preload("res://addons/ember_import/ember_terrain_plan_dialog.gd")
const TerrainComposition = preload("res://addons/ember_import/ember_terrain_plan_composition.gd")
const GrovePlanner = preload("res://addons/ember_import/ember_grove_planner.gd")
const GrovePreview = preload("res://addons/ember_import/ember_grove_preview.gd")
const SectionSelection = preload("res://addons/ember_import/ember_compact_section_selection.gd")
const TerrainDiagnostics = preload("res://addons/ember_import/ember_terrain_diagnostics.gd")
const MaterialPatternDialog = preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
const WorldLookPanel = preload("res://addons/ember_import/ember_world_look_panel.gd")
const TerrainPattern = preload("res://scripts/ember_compact_terrain_pattern.gd")
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
var look_panel: VBoxContainer
var material_title: Label
var surface_role_title: Label
var surface_role_choice: OptionButton
var material_variant_choice: OptionButton
var material_slot_button: Button
var material_pattern_button: Button
var material_pattern_dialog: MaterialPatternDialog
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
var _generation_panel: VBoxContainer
var _generation_button: Button
var _generation_job: RefCounted
var _generation_preview: Node3D
var _generation_context := {}
var _plan_panel: VBoxContainer
var _plan_button: Button
var _plan_selection := "" # Empty/new/bounds: only active while selecting in 3D.
var _path_points := PackedVector2Array()
var _path_hover := Vector2(-1,-1)
var _path_draw_cache := {}
var _plan_selected_id := ""
var _plan_target: WeakRef
var _panel_host := preload("res://addons/ember_import/ember_world_panel_host.gd").new()
# Mode queries below are views of the single route, never separate lifecycle state.
var _terrain_workspace: VBoxContainer
var _tools_workspace: VBoxContainer
var _workspace_tools_button: Button
var _workspace_terrain_button: Button
var _workspace_tabs: HBoxContainer
var _map_creation_workspace: VBoxContainer
var _map_creation_mode: bool:
	get: return _panel_host.is_active("map")
var _material_workspace: VBoxContainer
var _object_brush_workspace: VBoxContainer
var _object_brush_body: VBoxContainer
var _object_brush_title: Label
var _object_brush_scroll: ScrollContainer
var _object_brush_stop: Button
var _object_brush_mode: bool:
	get: return _panel_host.is_active("objects")
var _object_parameters_parent: Node
var _object_parameters_index := 0
var _object_brush_controls: Dictionary = {}
var _material_mode: bool:
	get: return _panel_host.is_active("material")
var _material_bound_map: WeakRef
var _material_bound_index := -1
var _material_bound_id := ""
var _material_choices: Array[Dictionary] = []
var placement_panel: VBoxContainer
var _placement_workspace: VBoxContainer
var _placement_mode: bool:
	get: return _panel_host.is_active("placement")
var shape_panel: VBoxContainer
var _shape_workspace: VBoxContainer
var _shape_mode: bool:
	get: return _panel_host.is_active("shape")
var duplicate_panel: VBoxContainer
var _duplicate_workspace: VBoxContainer
var merge_panel: VBoxContainer
var _merge_workspace: VBoxContainer
var split_panel: VBoxContainer
var _split_workspace: VBoxContainer
var conversion_panel: VBoxContainer
var _conversion_workspace: VBoxContainer
var _duplicate_mode: bool:
	get: return _panel_host.is_active("duplicate")

func configure_panel_host() -> void:
	_panel_host.configure(self)
	_panel_host.register_panel("placement",_placement_workspace,{
		"preview": placement_panel,"button": plugin._placement_bottom_button,
		"pending": placement_panel.is_dirty,"cancel": placement_panel.cancel_edit,
		"blocked": func(): placement_panel._status.text = "В расстановке есть правки. Нажмите «Применить» или «Отмена» перед сменой инструмента."})
	_panel_host.register_panel("shape",_shape_workspace,{
		"preview": shape_panel,"button": plugin._shape_bottom_button,
		"pending": shape_panel.is_dirty,"cancel": shape_panel.cancel_edit,
		"blocked": func(): shape_panel._status.text = "В новой форме есть параметры или предпросмотр. Нажмите «Создать» или «Отмена» перед сменой инструмента."})
	_panel_host.register_panel("duplicate",_duplicate_workspace,{
		"preview": duplicate_panel,"button": plugin._duplicate_bottom_button,
		"pending": duplicate_panel.is_dirty,"cancel": duplicate_panel.cancel_edit,
		"blocked": func(): duplicate_panel._status.text = "Ряд копий ещё не создан. Нажмите «Создать копии» или «Отмена» перед сменой инструмента."})
	_panel_host.register_panel("merge",_merge_workspace,{
		"preview": merge_panel,"button": plugin._merge_bottom_button,
		"pending": merge_panel.is_dirty,"cancel": merge_panel.cancel_edit,
		"blocked": func(): merge_panel._status.text = "Операция с выбранными деталями ещё не подтверждена. Нажмите «Склеить»/«Разобрать» или «Отмена» перед сменой инструмента."})
	_panel_host.register_panel("split",_split_workspace,{
		"preview": split_panel,"button": plugin._split_bottom_button,
		"pending": split_panel.is_dirty,"cancel": split_panel.cancel_edit,
		"blocked": func(): split_panel._status.text = "Разрезание ещё не подтверждено. Нажмите «Разрезать» или «Отмена» перед сменой инструмента."})
	_panel_host.register_panel("conversion",_conversion_workspace,{
		"preview": conversion_panel,"button": plugin._conversion_bottom_button,
		"pending": conversion_panel.is_dirty,"cancel": conversion_panel.cancel_edit,
		"blocked": func(): conversion_panel._status.text = "Преобразование ещё не подтверждено. Нажмите «Преобразовать» или «Отмена» перед сменой инструмента."})
	_panel_host.register_panel("material",_material_workspace,{
		"preview": material_pattern_dialog,"button": plugin._material_pattern_bottom_button,
		"pending": material_pattern_dialog.is_dirty,"cancel": material_pattern_dialog.cancel_edit,
		"history_key": material_pattern_dialog.handle_history_key,"persist_scene": true,
		"closed": func(): _material_bound_map = null; _material_choices.clear(); _material_bound_index = -1,
		"blocked": func(): material_pattern_dialog._message.text = "В рисунке есть правки. Нажмите «Сохранить» или «Отмена» перед сменой инструмента."})
	_panel_host.register_panel("map",_map_creation_workspace,{
		"cancel": plugin._cancel_compact_map_creation,
		"pending": func(): return is_instance_valid(plugin._compact_map_panel) and plugin._compact_map_panel.is_dirty(),
		"blocked": func(): plugin._compact_map_panel._status.text = "В новой карте есть параметры или предпросмотр. Нажмите «Создать карту» или «Отмена» перед сменой инструмента."})
	_panel_host.register_panel("objects",_object_brush_workspace,{
		"prepare_tools": false,"viewport_tools": true,"cancel": plugin._stop_scene_object_brush,
		"opened": func():
			object_parameters.reparent(_object_brush_body); _object_brush_body.move_child(object_parameters,1); object_parameters.show(),
		"closed": func():
			object_parameters.reparent(_object_parameters_parent); _object_parameters_parent.move_child(object_parameters,_object_parameters_index)
			object_parameters.visible = category.selected == 3})


func can_leave_panel() -> bool:
	return _panel_host.can_leave()


func _prepare_parameter_panel() -> void:
	if plugin != null: plugin._stop_scene_object_brush()
	cancel_stroke(); cancel_section_selection(); _plan_selection = ""; selecting = false; region_preview = Rect2i()
	clear_terrain_generation_preview(); clear_compact_extension_preview()
	if is_instance_valid(_generation_panel) and _generation_panel.visible:
		_generation_panel.set_pending("Предпросмотр закрыт. Обновите его перед применением.")


func _parameter_toolbars() -> Array:
	return [plugin._voxel_object_toolbar,plugin._world_surface_toolbar,plugin._battlefield_toolbar] if plugin != null else []


func _present_parameter_panel(route: Dictionary) -> void:
	_tools_workspace.hide(); _terrain_workspace.hide(); _workspace_tabs.hide(); sidebar.hide()
	route.page.show(); inspector_panel.show()
	if plugin != null:
		plugin._set_world_editor_dock_active(active); plugin._world_editor_dock.make_visible()
		if route.has("preview"):
			route.button.show(); plugin.make_bottom_panel_item_visible(route.preview)


func _hide_parameter_panel(route: Dictionary) -> void:
	route.page.hide(); _workspace_tabs.show()
	if plugin != null and route.has("preview"):
		if route.button.button_pressed: plugin.hide_bottom_panel()
		route.button.hide()


func _restore_parameter_workspace(terrain: bool) -> void:
	inspector_panel.visible = active
	_show_workspace(terrain if active else false)
	if plugin != null: plugin._set_world_editor_dock_active(active)


func show_duplicate_panel() -> void:
	_panel_host.open("duplicate")

func _close_duplicate_workspace() -> void:
	_panel_host.close("duplicate")

func _close_merge_workspace() -> void:
	_panel_host.close("merge")

func _close_split_workspace() -> void:
	_panel_host.close("split")

func _close_conversion_workspace() -> void:
	_panel_host.close("conversion")

func show_shape_panel() -> void:
	_panel_host.open("shape")

func _close_shape_workspace() -> void:
	_panel_host.close("shape")

func show_placement_panel() -> void:
	_panel_host.open("placement")

func _close_placement_workspace() -> void:
	_panel_host.close("placement")

func _show_material_workspace() -> void:
	_panel_host.open("material")

func _close_material_workspace() -> void:
	_panel_host.close("material")

func _on_material_variant_opened(id: String, role: String) -> void:
	_material_bound_id = id
	if _material_bound_map == null or _material_bound_map.get_ref() != map:
		_material_bound_index = -1; return
	for choice in _material_choices:
		if choice.id == id and choice.role == role:
			_material_bound_index = choice.index; break


func _sync_object_brush_controls() -> void:
	if plugin == null or not is_instance_valid(plugin._object_brush): return
	for property in _object_brush_controls:
		_object_brush_controls[property].set_value_no_signal(plugin._object_brush.get(property))
	_object_brush_title.text = "Кисть объектов · %s" % plugin._object_brush.model_id


func show_object_brush_panel() -> void:
	if plugin == null or not plugin._object_brush.active: return
	_sync_object_brush_controls()
	if active:
		_show_workspace(false); _category_changed(3,false)
	else: _panel_host.open("objects")
	plugin._world_editor_dock.make_visible()

func close_object_brush_panel() -> void:
	_panel_host.close("objects")

func show_map_creation_panel(panel: Control) -> void:
	if panel.get_parent() == null: _map_creation_workspace.add_child(panel)
	_panel_host.open("map")

func close_map_creation_panel() -> void:
	_panel_host.close("map")


func _show_workspace(terrain: bool) -> void:
	if not can_leave_panel(): return
	if not is_instance_valid(_terrain_workspace): return
	if is_instance_valid(sidebar): sidebar.visible = active and not terrain
	_tools_workspace.visible = not terrain
	_terrain_workspace.visible = terrain
	_workspace_tools_button.set_pressed_no_signal(not terrain)
	_workspace_terrain_button.set_pressed_no_signal(terrain)
	if not terrain:
		cancel_section_selection()
		if not _plan_selection.is_empty():
			_plan_selection = ""; selecting = false; region_preview = Rect2i()
		clear_terrain_generation_preview()
		if is_instance_valid(_generation_panel): _generation_panel.hide()
	if plugin != null and is_instance_valid(plugin._world_editor_dock):
		plugin._world_editor_dock.make_visible()

func _close_generation_panel() -> void:
	clear_terrain_generation_preview()
	_generation_panel.hide()
	if _generation_context.get("composition", false) or not _generation_context.get("plan_id", "").is_empty():
		_open_terrain_plan()
	else:
		_show_workspace(false)


func _open_terrain_plan() -> void:
	if not can_leave_panel(): return
	if not _compact_active(): return
	cancel_section_selection()
	cancel_stroke()
	_plan_selection = ""; selecting = false; region_preview = Rect2i()
	clear_terrain_generation_preview()
	if is_instance_valid(_generation_panel): _generation_panel.hide()
	_show_workspace(true)
	_plan_target = weakref(map)
	if not is_instance_valid(_plan_panel):
		_plan_panel = TerrainPlanPanel.new()
		_terrain_workspace.add_child(_plan_panel)
		_plan_panel.action_requested.connect(_terrain_plan_action)
		_plan_panel.selection_changed.connect(func(id): _plan_selected_id = id; _update_overlay())
	_refresh_terrain_plan(true)

func _refresh_terrain_plan(reveal := false) -> void:
	if not is_instance_valid(_plan_panel) or _plan_target == null: return
	var target: EmberMapLoader = _plan_target.get_ref()
	if not is_instance_valid(target) or target != map: _plan_panel.hide(); return
	var plan: Resource = TerrainPlan.read(target)
	_plan_panel.show_plan(plan if plan != null else TerrainPlan.new(), _plan_selected_id, reveal)
	_plan_selected_id = _plan_panel.selected_id()
	_update_overlay()

func commit_terrain_plan(target: EmberMapLoader, plan: Resource) -> String:
	if not is_instance_valid(target) or scene == null: return "Карта была закрыта."
	var draft := sessions.open_map(target, scene)
	if draft.is_empty(): return sessions.error
	if plan != null:
		var errors: Array[String] = plan.validation_errors(Vector2i(draft.resource.width / 16, draft.resource.depth / 16))
		if not errors.is_empty(): return errors[0]
	var before: Resource = TerrainPlan.read(target)
	if TerrainPlan.same(before, plan): return ""
	var history: Object = sessions.undo
	if history is EditorUndoRedoManager:
		(history as EditorUndoRedoManager).create_action("Изменить план областей", UndoRedo.MERGE_DISABLE, scene)
		Callable(history, "add_do_method").callv([self, "_apply_terrain_plan", draft, plan])
		Callable(history, "add_undo_method").callv([self, "_apply_terrain_plan", draft, before])
		(history as EditorUndoRedoManager).commit_action()
	else:
		(history as UndoRedo).create_action("Изменить план областей", UndoRedo.MERGE_DISABLE)
		(history as UndoRedo).add_do_method(_apply_terrain_plan.bind(draft, plan))
		(history as UndoRedo).add_undo_method(_apply_terrain_plan.bind(draft, before))
		(history as UndoRedo).commit_action()
	return ""

func _apply_terrain_plan(draft: Dictionary, plan: Resource) -> void:
	sessions.set_plan(draft, plan)
	clear_terrain_generation_preview()
	if is_instance_valid(_generation_panel) and _generation_panel.visible and not _generation_context.get("plan_id", "").is_empty():
		_generation_panel.set_pending("План изменился. Откройте область снова и обновите предпросмотр.")
	_refresh_terrain_plan()

func _terrain_plan_action(action: String, id: String, value: String) -> void:
	if _plan_target == null or _plan_target.get_ref() != map: return
	if action not in ["compose","groves"]: _plan_selected_id = id
	var original: Resource = TerrainPlan.read(map)
	var plan: Resource = original.working_copy() if original != null else TerrainPlan.new()
	var index: int = plan.index_of(id)
	if action in ["add", "add_plateau", "add_lake", "add_river", "add_mountain", "add_road", "add_grove", "add_placement", "bounds"]:
		if action == "bounds" and index < 0: return
		clear_terrain_generation_preview(); cancel_stroke()
		_plan_panel.set_status("Выделите область в 3D · Esc отменяет.")
		_plan_selection = action; selecting = true; create_region = false
		region_anchor = Vector2i(-1, -1); region_preview = Rect2i()
		_path_points = PackedVector2Array(); _path_hover = Vector2(-1,-1)
		if action in ["add_river","add_road"] or (action == "bounds" and plan.regions[index].get("kind") in ["river","road"]):
			_plan_selection = action if action in ["add_river","add_road"] else "path_line"
			var path_hint := "Кликайте точки дороги по суше." if _plan_path_kind() == "road" else "Кликайте точки от одного водоёма к другому."
			_plan_panel.set_status(path_hint+" Enter — сохранить линию, Backspace — убрать точку, Esc — отменить. Камера работает как обычно.")
			_status(path_hint+" Enter завершает · Esc отменяет.")
			_update_overlay(); return
		_status("Потяните прямоугольник области плана в 3D · Esc отменяет.")
		return
	_plan_selection = ""; selecting = false; region_preview = Rect2i()
	if action == "groves":
		_plan_panel.hide(); _ensure_generation_panel()
		_generation_context = {"target":weakref(map),"area":Rect2i(),"grove":true,"plan_id":"","plan_version":original.data()}
		_generation_panel.open_placement(Rect2i(),TerrainPlan.Influence.PLACEMENT_DEFAULTS,GrovePlanner.choices(true),false)
		return
	if action == "compose":
		_plan_panel.hide(); _ensure_generation_panel()
		_generation_context = {"target": weakref(map), "area": Rect2i(), "composition": true, "plan_id": "", "plan_version": original.data()}
		_generation_panel.open_influence(Rect2i(), TerrainPlan.Influence.DEFAULTS, "plateau", false)
		return
	if index < 0: return
	if action == "generate":
		edit_region = plan.regions[index].bounds; _refresh_scope()
		_plan_panel.hide(); _ensure_generation_panel()
		var kind: String = plan.regions[index].get("kind", "generation")
		if kind in ["grove","placement"]:
			_generation_context = {"target":weakref(map),"area":edit_region,"grove":true,"plan_id":id,"plan_version":original.data()}
			_generation_panel.open_placement(edit_region,plan.regions[index].parameters,GrovePlanner.choices(true))
			return
		var composition: bool = kind in ["plateau","lake","river","mountain","road"]
		_generation_context = {"target": weakref(map), "area": edit_region, "plan_id": id, "plan_version": original.data(), "composition": composition}
		if composition: _generation_panel.open_influence(edit_region, plan.regions[index].parameters,kind)
		else: _generation_panel.open_plan(edit_region, plan.regions[index].parameters)
		return
	if action == "name": plan.regions[index].name = value.strip_edges()
	elif action == "delete": plan.regions.remove_at(index); _plan_selected_id = ""
	elif action == "toggle": plan.regions[index].enabled = not plan.regions[index].get("enabled", true)
	elif action == "reverse" and plan.regions[index].get("kind") == "river":
		var points: PackedVector2Array = plan.regions[index].points_m.duplicate(); points.reverse(); plan.regions[index].points_m = points
	var error := commit_terrain_plan(map, plan)
	_plan_panel.set_status(error if not error.is_empty() else "План изменён · Ctrl+Z отменяет · Ctrl+S сохраняет сцену.")
	_refresh_terrain_plan()

func _finish_terrain_plan_selection(bounds_m: Rect2i) -> void:
	if _plan_selection.is_empty(): return
	var original: Resource = TerrainPlan.read(map)
	var plan: Resource = original.working_copy() if original != null else TerrainPlan.new()
	if _plan_selection in ["add", "add_plateau", "add_lake", "add_mountain", "add_grove", "add_placement"]:
		var id := "area_%s_%s" % [OS.get_process_id(), Time.get_ticks_usec()]
		plan.regions.append({"id": id, "name": "Область %d" % (plan.regions.size() + 1), "bounds": bounds_m, "parameters": TerrainGeneration.Math.DEFAULTS.duplicate(true)})
		if _plan_selection in ["add_plateau","add_lake"]:
			var lake := _plan_selection == "add_lake"
			if lake: plan.upgrade_local_layers()
			else: plan.schema_version = maxi(plan.schema_version,2)
			plan.regions[-1].kind = "lake" if lake else "plateau"; plan.regions[-1].enabled = true
			plan.regions[-1].name = ("Озеро %d" if lake else "Плато %d") % plan.regions.size()
			plan.regions[-1].parameters = (TerrainPlan.Influence.LAKE_DEFAULTS if lake else TerrainPlan.Influence.DEFAULTS).duplicate(true)
		elif _plan_selection == "add_mountain":
			plan.upgrade_local_layers(); plan.regions[-1].kind = "mountain"; plan.regions[-1].enabled = true
			plan.regions[-1].name = "Гора %d" % plan.regions.size()
			plan.regions[-1].parameters = TerrainPlan.Influence.mountain_defaults(bounds_m)
		elif _plan_selection == "add_grove":
			plan.upgrade_local_layers(); plan.regions[-1].kind = "grove"; plan.regions[-1].enabled = true
			plan.regions[-1].name = "Роща %d"%plan.regions.size()
			plan.regions[-1].parameters = TerrainPlan.Influence.GROVE_DEFAULTS.duplicate(true)
			var variants := GrovePlanner.choices()
			if not variants.is_empty(): plan.regions[-1].parameters.model_ids = PackedStringArray([variants[0].id])
		elif _plan_selection == "add_placement":
			plan.upgrade_local_layers(); plan.regions[-1].kind = "placement"; plan.regions[-1].enabled = true
			plan.regions[-1].name = "Объекты %d"%plan.regions.size()
			plan.regions[-1].parameters = TerrainPlan.Influence.PLACEMENT_DEFAULTS.duplicate(true)
		_plan_selected_id = id
	else:
		var index: int = plan.index_of(_plan_selected_id)
		if index >= 0: plan.regions[index].bounds = bounds_m
	_plan_selection = ""
	var error := commit_terrain_plan(map, plan)
	_refresh_terrain_plan(true)
	_plan_panel.set_status(error if not error.is_empty() else "Область добавлена в план. Земля не изменена.")

func _plan_path_kind() -> String:
	if _plan_selection == "add_road": return "road"
	if _plan_selection == "add_river": return "river"
	var plan: Resource = TerrainPlan.read(map)
	var index: int = plan.index_of(_plan_selected_id) if plan != null else -1
	return plan.regions[index].get("kind","") if index >= 0 else ""

func _plan_path_bounds(region: Dictionary, parameters: Dictionary, extent: Vector2i) -> Rect2i:
	return TerrainPlan.Influence.path_bounds(region.points_m,parameters.width_m,parameters.edge_m if region.kind == "road" else parameters.shore_m,extent)

func _finish_plan_path() -> void:
	var extent := Vector2i(entry.resource.width/16,entry.resource.depth/16)
	var error := TerrainPlan.Influence.path_error(_path_points,extent)
	if not error.is_empty(): _plan_panel.set_status(error); return
	var original: Resource = TerrainPlan.read(map)
	var plan: Resource = original.working_copy() if original != null else TerrainPlan.new()
	plan.upgrade_local_layers()
	var index: int = plan.index_of(_plan_selected_id)
	var kind := _plan_path_kind()
	if _plan_selection in ["add_river","add_road"]:
		_plan_selected_id = "%s_%s_%s" % [kind,OS.get_process_id(),Time.get_ticks_usec()]
		plan.regions.append({"id":_plan_selected_id,"name":("Дорога %d" if kind == "road" else "Река %d") % (plan.regions.size()+1),"kind":kind,"enabled":true,"parameters":(TerrainPlan.Influence.ROAD_DEFAULTS if kind == "road" else TerrainPlan.Influence.RIVER_DEFAULTS).duplicate()})
		index = plan.regions.size()-1
	if index < 0: return
	plan.regions[index].points_m = _path_points.duplicate()
	plan.regions[index].bounds = _plan_path_bounds(plan.regions[index],plan.regions[index].parameters,extent)
	error = commit_terrain_plan(map,plan)
	if not error.is_empty(): _plan_panel.set_status(error); return
	_plan_selection = ""; selecting = false; _path_points = PackedVector2Array(); _path_hover = Vector2(-1,-1)
	_refresh_terrain_plan(true)
	_plan_panel.set_status("Линия сохранена в плане. Откройте параметры, затем предпросмотр и применение. Земля пока не изменена.")

func _save_terrain_plan_parameters(parameters: Dictionary) -> void:
	var target: EmberMapLoader = _generation_context.get("target").get_ref() if _generation_context.get("target") is WeakRef else null
	if not is_instance_valid(target): return
	var original: Resource = TerrainPlan.read(target)
	if original == null: return
	var plan: Resource = original.working_copy()
	var index: int = plan.index_of(_generation_context.get("plan_id", ""))
	if index < 0: return
	if plan.regions[index].bounds != _generation_context.get("area"):
		_generation_panel.set_pending("Границы изменились. Откройте область снова."); return
	plan.regions[index].parameters = parameters.duplicate(true)
	if plan.regions[index].get("kind") == "grove" and parameters.has("clearance_m"): plan.regions[index].kind = "placement"
	if plan.regions[index].get("kind") in ["river","road"]:
		plan.regions[index].bounds = _plan_path_bounds(plan.regions[index],parameters,Vector2i(entry.resource.width/16,entry.resource.depth/16))
	var error := commit_terrain_plan(target, plan)
	if error.is_empty(): _generation_context.plan_version = plan.data(); _generation_context.area = plan.regions[index].bounds
	var result_hint := "Подготовьте предпросмотр для расстановки объектов." if plan.regions[index].get("kind") in ["grove","placement"] else "Подготовьте предпросмотр для изменения земли."
	_generation_panel.set_pending(error if not error.is_empty() else "Параметры сохранены в плане · Ctrl+S сохраняет сцену. "+result_hint)
var _section_mode := false
var _section_dragging := false
var _section_anchor := Vector2i.ZERO
var _section_rect := Rect2i()
var _section_controls: HBoxContainer
var _section_label: Label
var _section_next: Button
var _section_error_dialog: AcceptDialog
var _section_hidden_controls: Array[Dictionary] = []

func _compact_active() -> bool:
	return not entry.is_empty() and entry.get("compact", false)

func _set_busy(value: bool) -> void:
	for control in [target_choice,category,tools,palette,sand_palette,surface_role_choice,material_variant_choice,material_slot_button,material_pattern_button,clip,shore_direction,compact_direction,compact_level_from_point,terrain_edit_scale,terrain_height_step,brush_shape]:
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


func _open_terrain_generation() -> void:
	if not can_leave_panel(): return
	cancel_stroke()
	if not _compact_active(): _status("Выберите компактную землю."); return
	# The session owns the current terrain extent, including unsaved changes.
	# Scene metadata can still describe a different footprint on older study maps.
	var terrain: EmberTerrainPilotResource = entry.resource
	var area := edit_region if edit_region.has_area() else Rect2i(Vector2i.ZERO, Vector2i(terrain.width / 16, terrain.depth / 16))
	if area.size.x > TerrainGeneration.MAX_BLOCKS or area.size.y > TerrainGeneration.MAX_BLOCKS:
		_status("Сначала выделите область до 96×96 м через «Область и вид → Ограничить участок».")
		return
	clear_compact_extension_preview()
	_ensure_generation_panel()
	_generation_context = {"area": area, "target": weakref(map)}
	_generation_panel.open_for(area)


func _ensure_generation_panel() -> void:
	clear_terrain_generation_preview()
	_show_workspace(true)
	if is_instance_valid(_plan_panel): _plan_panel.hide()
	if not is_instance_valid(_generation_panel):
		_generation_panel = TerrainGenerationPanel.new()
		_terrain_workspace.add_child(_generation_panel)
		_generation_panel.preview_requested.connect(_prepare_terrain_generation)
		_generation_panel.settings_changed.connect(clear_terrain_generation_preview)
		_generation_panel.visibility_changed.connect(func():
			if not _generation_panel.visible: clear_terrain_generation_preview()
		)
		_generation_panel.apply_requested.connect(_submit_terrain_generation)
		_generation_panel.cancel_requested.connect(_close_generation_panel)
		_generation_panel.select_area_requested.connect(func(): begin_section_selection(true))
		_generation_panel.plan_settings_requested.connect(_save_terrain_plan_parameters)
		_generation_panel.return_plan_requested.connect(_open_terrain_plan)


func _prepare_terrain_generation(parameters: Dictionary) -> void:
	if _generation_context.get("grove",false): _prepare_grove(parameters); return
	var context := {"target": _generation_context.get("target"), "area": _generation_context.get("area", Rect2i()), "addition": _generation_context.get("addition", false), "plan_id": _generation_context.get("plan_id", ""), "plan_version": _generation_context.get("plan_version", {}), "composition": _generation_context.get("composition", false)}
	clear_terrain_generation_preview()
	_generation_context = context
	var target: EmberMapLoader = context.target.get_ref() if context.get("target") is WeakRef else null
	if not is_instance_valid(target): _generation_panel.set_pending("Карта была закрыта."); return
	if not context.plan_id.is_empty():
		var plan: Resource = TerrainPlan.read(target)
		var index: int = plan.index_of(context.plan_id) if plan != null else -1
		if index < 0 or plan.data() != context.plan_version or plan.regions[index].bounds != context.area:
			_generation_panel.set_pending("План изменился. Откройте область снова."); return
	var draft := sessions.open_map(target, scene)
	if draft.is_empty(): _generation_panel.set_pending(sessions.error); return
	var prepared := false
	if context.composition:
		var plan: Resource = TerrainPlan.read(target)
		if plan == null or plan.data() != context.plan_version:
			_generation_panel.set_pending("План изменился. Откройте его снова."); return
		var input: Resource = plan.working_copy()
		if not context.plan_id.is_empty():
			var index: int = input.index_of(context.plan_id)
			input.regions[index].parameters = parameters.duplicate(true)
			if input.regions[index].get("kind") in ["river","road"]: input.regions[index].bounds = _plan_path_bounds(input.regions[index],parameters,Vector2i(draft.resource.width/16,draft.resource.depth/16))
		_generation_job = TerrainComposition.new()
		prepared = _generation_job.begin(draft.resource, input)
	else:
		_generation_job = TerrainGeneration.new()
		prepared = _generation_job.begin(draft.resource, context.area, parameters, context.addition)
	if not prepared:
		_generation_panel.set_pending(_generation_job.error)
		_generation_job = null
		return
	_generation_context["draft"] = draft
	_generation_context["version"] = draft.resource.working_copy()
	_generation_context["layout"] = Sessions.compact_layout(target).positions
	_generation_context["selection"] = _generation_job.addition.duplicate()
	_generation_panel.set_pending("Подготавливаю землю…")


func clear_terrain_generation_preview() -> void:
	if _generation_job != null: _generation_job.cancel(); _generation_job = null
	if is_instance_valid(_generation_preview):
		_generation_preview.clear_preview()
		_generation_preview.hide()
		_generation_preview.queue_free()
	_generation_preview = null
	_generation_context.erase("candidate")
	_generation_context.erase("draft")
	_generation_context.erase("version")
	_generation_context.erase("output_plan")
	_generation_context.erase("protected_blocks")
	_generation_context.erase("validated_sections")
	_generation_context.erase("grove_prepared")
	_update_overlay()


func _process_terrain_generation() -> void:
	if _generation_job == null: return
	if _generation_context.get("grove",false): _process_grove(); return
	_generation_job.step(4000)
	if not _generation_job.error.is_empty():
		_generation_panel.set_pending(_generation_job.error); clear_terrain_generation_preview(); return
	_generation_panel.set_pending("Подготовка земли: %d%%" % roundi(_generation_job.progress() * 100.0))
	if not _generation_job.finished: return
	var target: EmberMapLoader = _generation_context.target.get_ref()
	var candidate: EmberTerrainPilotResource = _generation_job.candidate
	var bounds: Rect2i = _generation_job.bounds
	var profile_ms := float(_generation_job.elapsed_us) / 1000.0
	var preview_tiles: Array[Vector2i] = []
	if _generation_context.get("composition", false):
		_generation_context.output_plan = _generation_job.output_plan
		_generation_context.validated_sections = _generation_job.validated_sections
		_generation_context.protected_blocks = _generation_job.protected_blocks.keys()
		var tiles := {}
		for key: Vector2i in _generation_job.changed_tiles:
			for delta in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if (key + delta).x >= 0 and (key + delta).y >= 0 and (key + delta).x * 64 < candidate.width and (key + delta).y * 64 < candidate.depth: tiles[key + delta] = true
		preview_tiles.assign(tiles.keys())
		for key in preview_tiles:
			bounds = bounds.merge(Rect2i(key * 64, Vector2i.ONE * 64).intersection(Rect2i(0, 0, candidate.width, candidate.depth)))
		if preview_tiles.is_empty():
			_generation_context["candidate"] = candidate
			_generation_job = null
			_generation_panel.set_ready("Рельеф и вода уже совпадают. Можно применить состояние плана · защищено мест: %d." % _generation_context.protected_blocks.size()); _update_overlay(); return
	_generation_job = null
	if not is_instance_valid(target): _generation_panel.set_pending("Карта была закрыта."); return
	_generation_context["candidate"] = candidate
	var preview := CompactExtensionPreview.new() as Node3D
	target.add_child(preview, false, Node.INTERNAL_MODE_BACK)
	if not preview.show_area(target, candidate, bounds, _generation_context.selection.get("offset", Vector2i.ZERO), preview_tiles,_generation_context.get("composition",false)):
		preview.queue_free()
		_generation_panel.set_pending("3D-предпросмотр пока недоступен. Дождитесь открытия карты.")
		return
	_generation_preview = preview
	_generation_panel.set_pending("Строю 3D-предпросмотр…")
	preview.preview_built.connect(func():
		if _generation_preview == preview and is_instance_valid(_generation_panel):
			if _generation_context.get("composition", false):
				_generation_panel.set_ready("Предпросмотр областей готов · защищено мест: %d. Изменения применятся одной командой Undo." % _generation_context.protected_blocks.size()); _update_overlay(); return
			_generation_panel.set_ready("Предпросмотр готов. Добавится %d участков; прежняя земля сохранится." % _generation_context.selection.keys.size() if _generation_context.addition else "Предпросмотр готов · расчёт %.0f мс. Применение заменит выбранную землю; отмена вернёт прежний вид." % profile_ms)
	)


func _submit_terrain_generation() -> void:
	if _generation_context.get("grove",false): _submit_grove(); return
	if not _generation_context.has("candidate"): return
	var context := _generation_context.duplicate()
	var target: EmberMapLoader = context.target.get_ref()
	if context.get("composition", false) or not context.get("plan_id", "").is_empty():
		var plan: Resource = TerrainPlan.read(target) if is_instance_valid(target) else null
		if plan == null or plan.data() != context.plan_version:
			_generation_panel.set_pending("План изменился. Подготовьте предпросмотр заново."); clear_terrain_generation_preview(); return
	clear_terrain_generation_preview()
	var message := commit_terrain_composition(target, context) if context.get("composition", false) else commit_selected_sections(target, context) if context.get("addition", false) else commit_terrain_generation(target, context.draft, context.version, context.candidate)
	if message.is_empty():
		_close_generation_panel()
	else:
		_generation_panel.set_pending(message)
	_status("Участки добавлены и выбраны для редактирования · Ctrl+Z отменяет · Ctrl+S сохраняет." if message.is_empty() and context.get("addition", false) else "Рельеф применён. Можно править кистями, отменить или сохранить карту." if message.is_empty() else message)

func _prepare_grove(parameters: Dictionary) -> void:
	var context := _generation_context.duplicate()
	clear_terrain_generation_preview(); _generation_context = context
	var target := (context.target as WeakRef).get_ref() as EmberMapLoader
	var plan: Resource = TerrainPlan.read(target)
	if not is_instance_valid(target) or plan == null or plan.data() != context.plan_version:
		_generation_panel.set_pending("План изменился. Откройте область расстановки снова."); return
	var input: Resource = plan.working_copy()
	if not context.plan_id.is_empty():
		var index: int = input.index_of(context.plan_id)
		if index < 0: _generation_panel.set_pending("Область расстановки удалена."); return
		input.regions[index].parameters = parameters.duplicate(true)
		if input.regions[index].get("kind") == "grove" and parameters.has("clearance_m"):
			input.upgrade_local_layers(); input.regions[index].kind = "placement"
	var draft := sessions.open_map(target,scene)
	if draft.is_empty(): _generation_panel.set_pending(sessions.error); return
	_generation_job = GrovePlanner.new()
	if not _generation_job.begin(draft.resource,target,scene,input):
		_generation_panel.set_pending(_generation_job.error); _generation_job = null; return
	_generation_context.draft = draft; _generation_context.version = draft.resource.working_copy()
	_generation_context.layout = Sessions.compact_layout(target).positions
	_generation_panel.set_pending("Подготавливаю расстановку объектов…")

func _process_grove() -> void:
	_generation_job.step(4000)
	if not _generation_job.finished: return
	var job: RefCounted = _generation_job; _generation_job = null
	if not job.error.is_empty(): _generation_panel.set_pending(job.error); return
	var target := (_generation_context.target as WeakRef).get_ref() as EmberMapLoader
	if not is_instance_valid(target): return
	_generation_context.grove_prepared = job
	var preview := GrovePreview.new(); target.add_child(preview,false,Node.INTERNAL_MODE_BACK)
	_generation_preview = preview
	preview.preview_built.connect(func():
		if _generation_preview == preview: _generation_panel.set_ready("Объектов: %d · защищено ручных правок/удалений: %d. Применение не меняет землю."%[job.placements.size(),job.protected_members.size()]))
	preview.show_job(job)
	_generation_panel.set_pending("Строю предпросмотр рощи…")

func _submit_grove() -> void:
	if not _generation_context.has("grove_prepared"): return
	var context := _generation_context.duplicate()
	clear_terrain_generation_preview()
	var target := (context.target as WeakRef).get_ref() as EmberMapLoader
	var message := commit_grove(target,context)
	if not message.is_empty(): _generation_panel.set_pending(message); return
	_close_generation_panel(); _status("Расстановка применена · Ctrl+Z отменяет · Ctrl+S сохраняет сцену.")

func commit_grove(target: EmberMapLoader, context: Dictionary) -> String:
	if not is_instance_valid(target): return "Карта была закрыта."
	var draft: Dictionary = context.get("draft",{})
	if not sessions.entries.values().has(draft) or draft.target.get_ref() != target: return "Черновик изменился."
	var job: RefCounted = context.get("grove_prepared")
	var plan: Resource = TerrainPlan.read(target)
	if job == null or plan == null or plan.data() != context.plan_version or not draft.resource.same_terrain_data(context.version) or Sessions.compact_layout(target).positions != context.layout or job.stale():
		return "Земля, объекты или источники объектов изменились. Обновите предпросмотр."
	var delta: Dictionary = job.finalize(target.get_node("Props"))
	if delta.is_empty(): return job.error
	var problems: Array[String] = delta.plan.validation_errors(Vector2i(context.version.width/16,context.version.depth/16))
	if not problems.is_empty():
		for prop in delta.added: prop.free()
		return problems[0]
	if TerrainPlan.same(plan,delta.plan):
		for prop in delta.added: prop.free()
		return ""
	var history: Object = sessions.undo
	if history is EditorUndoRedoManager:
		(history as EditorUndoRedoManager).create_action("Применить расстановку объектов",UndoRedo.MERGE_DISABLE,scene)
		Callable(history,"add_do_method").callv([self,"_apply_grove_delta",context.draft,delta,delta.plan,true])
		Callable(history,"add_undo_method").callv([self,"_apply_grove_delta",context.draft,delta,plan,false])
		for prop in delta.added: (history as EditorUndoRedoManager).add_do_reference(prop)
		for prop in delta.removed: (history as EditorUndoRedoManager).add_undo_reference(prop)
		(history as EditorUndoRedoManager).commit_action()
	else:
		(history as UndoRedo).create_action("Применить расстановку объектов",UndoRedo.MERGE_DISABLE)
		(history as UndoRedo).add_do_method(_apply_grove_delta.bind(context.draft,delta,delta.plan,true))
		(history as UndoRedo).add_undo_method(_apply_grove_delta.bind(context.draft,delta,plan,false))
		for prop in delta.added: (history as UndoRedo).add_do_reference(prop)
		for prop in delta.removed: (history as UndoRedo).add_undo_reference(prop)
		(history as UndoRedo).commit_action()
	return ""

func _apply_grove_delta(draft: Dictionary, delta: Dictionary, plan: Resource, forward: bool) -> void:
	GrovePlanner.apply_delta(delta,forward)
	sessions.set_plan(draft,plan)
	if Engine.is_editor_hint(): EditorInterface.mark_scene_as_unsaved()
	_refresh_terrain_plan()


func commit_terrain_composition(target: EmberMapLoader, context: Dictionary) -> String:
	if not is_instance_valid(target): return "Карта была закрыта."
	var draft: Dictionary = context.draft
	if not sessions.entries.values().has(draft) or draft.target.get_ref() != target: return "Черновик изменился."
	if not draft.resource.same_terrain_data(context.version) or Sessions.compact_layout(target).positions != context.layout: return "Земля изменилась после предпросмотра. Обновите его."
	var plan: Resource = TerrainPlan.read(target)
	if plan == null or plan.data() != context.plan_version: return "План изменился после предпросмотра."
	if Vector2i(context.candidate.width, context.candidate.depth) != Vector2i(draft.resource.width, draft.resource.depth): return "Локальные области не меняют размер карты."
	var extent_error := _compact_extent_error(scene, context.candidate)
	if not extent_error.is_empty(): return extent_error
	var validation_scope: Array[Vector2i] = []
	validation_scope.assign(context.get("validated_sections", []))
	var errors: Array[String] = context.candidate.validation_errors(validation_scope)
	errors.append_array(context.output_plan.validation_errors(Vector2i(context.candidate.width / 16, context.candidate.depth / 16)))
	if not errors.is_empty(): return errors[0]
	var history: Object = sessions.undo
	var original: EmberTerrainPilotResource = draft.resource
	if history is EditorUndoRedoManager:
		(history as EditorUndoRedoManager).create_action("Применить локальные области", UndoRedo.MERGE_DISABLE, scene)
		Callable(history, "add_do_method").callv([self, "_apply_composed_terrain", target, draft, context.candidate, context.output_plan])
		Callable(history, "add_undo_method").callv([self, "_apply_composed_terrain", target, draft, original, plan])
		(history as EditorUndoRedoManager).commit_action()
	else:
		(history as UndoRedo).create_action("Применить локальные области", UndoRedo.MERGE_DISABLE)
		(history as UndoRedo).add_do_method(_apply_composed_terrain.bind(target, draft, context.candidate, context.output_plan))
		(history as UndoRedo).add_undo_method(_apply_composed_terrain.bind(target, draft, original, plan))
		(history as UndoRedo).commit_action()
	return ""

func _apply_composed_terrain(target: EmberMapLoader, draft: Dictionary, terrain: EmberTerrainPilotResource, plan: Resource) -> void:
	if not is_instance_valid(target): return
	sessions.set_plan(draft, plan)
	_apply_generated_terrain(target, draft, terrain)
	_refresh_terrain_plan()

func commit_terrain_generation(target: EmberMapLoader, draft: Dictionary, before_version: EmberTerrainPilotResource, candidate: EmberTerrainPilotResource) -> String:
	if not is_instance_valid(target) or candidate == null: return "Карта была закрыта."
	if draft.get("target") is not WeakRef or draft.target.get_ref() != target or not sessions.entries.values().has(draft): return "Черновик карты изменился."
	var before: EmberTerrainPilotResource = draft.resource
	if not before.same_terrain_data(before_version): return "Земля изменилась после предпросмотра. Подготовьте рельеф заново."
	if Vector2i(candidate.width, candidate.depth) != Vector2i(before.width, before.depth): return "Генерация не может изменять размер карты."
	var validation := candidate.validation_errors()
	if not validation.is_empty(): return validation[0]
	var extent_error := _compact_extent_error(scene, candidate)
	if not extent_error.is_empty(): return extent_error
	var history: Object = sessions.undo
	if history is EditorUndoRedoManager:
		(history as EditorUndoRedoManager).create_action("Сгенерировать рельеф области", UndoRedo.MERGE_DISABLE, scene)
		Callable(history, "add_do_method").callv([self, "_apply_generated_terrain", target, draft, candidate])
		Callable(history, "add_undo_method").callv([self, "_apply_generated_terrain", target, draft, before])
		(history as EditorUndoRedoManager).commit_action()
	else:
		(history as UndoRedo).create_action("Сгенерировать рельеф области", UndoRedo.MERGE_DISABLE)
		(history as UndoRedo).add_do_method(Callable(self, "_apply_generated_terrain").bind(target, draft, candidate))
		(history as UndoRedo).add_undo_method(Callable(self, "_apply_generated_terrain").bind(target, draft, before))
		(history as UndoRedo).commit_action()
	return ""


func _apply_generated_terrain(target: EmberMapLoader, draft: Dictionary, source: EmberTerrainPilotResource) -> void:
	if not is_instance_valid(target): return
	draft.resource = source
	sessions.preview(draft)
	sessions.changed.emit()


func preview_compact_extension(direction: String, mode: String, section_index := -1, address := Vector2i(-1, -1)) -> String:
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
		return "Размер сцены не совпадает с землёй.\nНажмите «Исправить размер сцены»."
	var after: EmberTerrainPilotResource = CompactMapExtension.at_address(before, address, mode) if address.x >= 0 else CompactMapExtension.expanded(before, direction, mode, section_index)
	if after == null:
		return "Участок занят, адрес недоступен или достигнут предел размера карты."
	var extent_error := _compact_extent_error(root, after)
	if not extent_error.is_empty(): return extent_error
	var preview := CompactExtensionPreview.new() as Node3D
	target.add_child(preview, false, Node.INTERNAL_MODE_BACK)
	if not preview.call("show_candidate", target, before, after, "address" if address.x >= 0 else direction, section_index, address):
		preview.free()
		return "3D-предпросмотр земли сейчас недоступен."
	_compact_extension_preview = preview
	_compact_extension_candidate = {"target": weakref(target), "before": before, "after": after, "direction": direction, "mode": mode, "section_index": section_index, "address": address}
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


func extend_compact_map(direction: String, mode := CompactMapExtension.MODE_CONTINUE, section_index := -1, address := Vector2i(-1, -1)) -> String:
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
		return "Размер сцены не совпадает с землёй.\nНажмите «Исправить размер сцены»."
	var cached := _compact_extension_candidate
	var cached_matches: bool = not cached.is_empty() and cached.get("target") is WeakRef and cached.target.get_ref() == target and cached.get("before") == before and cached.get("direction") == direction and cached.get("mode") == mode and cached.get("section_index", -1) == section_index and cached.get("address", Vector2i(-1, -1)) == address
	var after: EmberTerrainPilotResource = cached.get("after") if cached_matches else CompactMapExtension.at_address(before, address, mode) if address.x >= 0 else CompactMapExtension.expanded(before, direction, mode, section_index)
	if after == null:
		return "Участок занят, адрес недоступен или достигнут предел размера карты."
	var extent_error := _compact_extent_error(root, after)
	if not extent_error.is_empty(): return extent_error
	clear_compact_extension_preview()
	var before_blocks := target.authored_size_blocks
	var after_blocks := Vector2i(after.width / 16, after.depth / 16)
	var old_positions := {}
	var new_positions := {}
	var shift: Vector3 = CompactMapExtension.scene_shift(direction, target.imported_tile_size) if address.x < 0 else Vector3.ZERO
	for group_name in ["Terrain", "Props", "Regions"]:
		var group := target.get_node_or_null(group_name) as Node3D
		if group == null: continue
		old_positions[group_name] = group.position
		new_positions[group_name] = group.position + shift
	var history := sessions.undo as EditorUndoRedoManager
	history.create_action("Расширить компактную карту: " + direction, UndoRedo.MERGE_DISABLE, root)
	Callable(history, "add_do_method").callv([self, "_apply_compact_extension", target, draft, after, after_blocks, new_positions, direction if address.x < 0 else ""])
	Callable(history, "add_undo_method").callv([self, "_apply_compact_extension", target, draft, before, before_blocks, old_positions, direction if address.x < 0 else ""])
	history.commit_action()
	return ""


func repair_compact_map_extent() -> String:
	var root := EditorInterface.get_edited_scene_root()
	var target := root.find_child("Map", true, false) as EmberMapLoader if root != null else null
	if target == null or target.compact_terrain == null: return "Откройте компактную карту."
	var draft := sessions.open_map(target, root)
	if draft.is_empty(): return sessions.error
	return commit_compact_extent_repair(target, draft, root)


func commit_compact_extent_repair(target: EmberMapLoader, draft: Dictionary, root: Node) -> String:
	if not is_instance_valid(target) or not is_instance_valid(root) or not root.is_ancestor_of(target): return "Карта была закрыта."
	if draft.get("target") is not WeakRef or draft.target.get_ref() != target or not sessions.entries.values().has(draft): return "Черновик карты изменился."
	var source: EmberTerrainPilotResource = draft.resource
	var validation := source.validation_errors()
	if not validation.is_empty(): return validation[0]
	var expected := Vector2i(source.width / 16, source.depth / 16)
	if target.authored_size_blocks == expected: return ""
	var history: Object = sessions.undo
	if history is EditorUndoRedoManager:
		(history as EditorUndoRedoManager).create_action("Исправить размер компактной сцены", UndoRedo.MERGE_DISABLE, root)
		Callable(history, "add_do_method").callv([self, "_apply_compact_extent_repair", target, draft, expected])
		Callable(history, "add_undo_method").callv([self, "_apply_compact_extent_repair", target, draft, target.authored_size_blocks])
		(history as EditorUndoRedoManager).commit_action()
	else:
		(history as UndoRedo).create_action("Исправить размер компактной сцены", UndoRedo.MERGE_DISABLE)
		(history as UndoRedo).add_do_method(Callable(self, "_apply_compact_extent_repair").bind(target, draft, expected))
		(history as UndoRedo).add_undo_method(Callable(self, "_apply_compact_extent_repair").bind(target, draft, target.authored_size_blocks))
		(history as UndoRedo).commit_action()
	return ""


func _apply_compact_extent_repair(target: EmberMapLoader, draft: Dictionary, blocks: Vector2i) -> void:
	target.authored_size_blocks = blocks
	sessions.preview(draft)
	sessions.changed.emit()
	if map == target: _refresh_scope()


func _compact_extent_error(root: Node, source: EmberTerrainPilotResource) -> String:
	for node in root.get_children():
		if node.has_method("terrain_extent_error"):
			var message := str(node.call("terrain_extent_error", Vector2i(source.width, source.depth)))
			if not message.is_empty(): return message
	return ""


func _apply_compact_extension(target: EmberMapLoader, draft: Dictionary, source: EmberTerrainPilotResource, blocks: Vector2i, positions: Dictionary, direction := "") -> void:
	# The legacy side-extension command shifts source coordinates without moving
	# Map. Signed 3D selection handles its own Map rebase before this method.
	if not positions.has("Map") and direction in ["west", "north"]:
		var offset := Vector2i((source.width - draft.resource.width) / 16 if direction == "west" else 0,
			(source.depth - draft.resource.depth) / 16 if direction == "north" else 0)
		var plan: Resource = TerrainPlan.read(target)
		if plan != null and offset != Vector2i.ZERO: sessions.set_plan(draft, plan.translated(offset))
	var projection := target._visual_surface_projection as EmberTerrainPilotProjection if is_instance_valid(target) else null
	if projection != null and not direction.is_empty():
		projection.open_resized_document(source, draft.resource, direction, CompactMapExtension.Creation.SECTION_BLOCKS * EmberTerrainPilotResource.CELLS_PER_BLOCK)
	draft.resource = source
	target.authored_size_blocks = blocks
	for group_name in positions:
		var group := target.get_node_or_null(group_name) as Node3D
		if group != null:
			if not draft.has("compact_layout_delta"): draft.compact_layout_delta = {}
			draft.compact_layout_delta[group_name] = draft.compact_layout_delta.get(group_name, Vector3.ZERO) + positions[group_name] - group.position
			group.position = positions[group_name]
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
	_section_controls = HBoxContainer.new()
	_section_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_section_controls)
	_section_label = Label.new()
	_section_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_section_label.custom_minimum_size.x = 180
	_section_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_section_controls.add_child(_section_label)
	_section_next = Button.new()
	_section_next.text = "Далее: рельеф и вода"
	_section_next.pressed.connect(_confirm_section_selection)
	_section_controls.add_child(_section_next)
	var cancel_section := Button.new()
	cancel_section.text = "Отмена"
	cancel_section.pressed.connect(cancel_section_selection)
	_section_controls.add_child(cancel_section)
	_section_controls.hide()
	return toolbar


func begin_section_selection(keep_area := false) -> void:
	if not can_leave_panel(): return
	var root := EditorInterface.get_edited_scene_root()
	var target := root.find_child("Map", true, false) as EmberMapLoader if root != null else null
	if target == null or target.compact_terrain == null:
		_status("Откройте компактную карту, чтобы выбрать новые участки."); return
	if not active: enabled.button_pressed = true
	if scene != root: scene_changed(root)
	cancel_stroke()
	clear_terrain_generation_preview()
	clear_compact_extension_preview()
	if is_instance_valid(_generation_panel): _generation_panel.hide()
	map = target
	target_choice.select(0)
	_target_changed(0)
	if entry.is_empty(): _status(sessions.error); return
	_category_changed(0)
	selecting = false
	picking_object = false
	hover.clear()
	_section_mode = true
	_section_dragging = false
	if not keep_area: _section_rect = Rect2i()
	_show_section_controls(true)
	_update_section_selection()
	_status("Выберите пустое место в 3D: щёлкните для одного участка или потяните прямоугольник · Enter — далее · Esc — отмена.")


func cancel_section_selection() -> void:
	_section_mode = false
	_section_dragging = false
	_section_rect = Rect2i()
	_show_section_controls(false)
	_update_overlay()


func _show_section_controls(value: bool) -> void:
	if not is_instance_valid(_section_controls): return
	_section_controls.visible = value
	if value and _section_hidden_controls.is_empty():
		# Keep this step legible in a narrow native 3D viewport. Restore each
		# prior visibility rather than changing the normal toolbar's layout.
		for child in toolbar.get_children():
			if child is Button and child != enabled:
				_section_hidden_controls.append({"node": weakref(child), "visible": child.visible})
				child.hide()
	elif not value:
		for saved in _section_hidden_controls:
			var child: Control = saved.node.get_ref()
			if is_instance_valid(child): child.visible = saved.visible
		_section_hidden_controls.clear()


func _update_section_selection() -> void:
	var selection := SectionSelection.plan(entry.resource, _section_rect)
	_section_next.disabled = not selection.error.is_empty()
	_section_label.text = "%d новых · %d×%d м" % [selection.keys.size(), _section_rect.size.x * 24, _section_rect.size.y * 24] if selection.error.is_empty() else "Выберите новые участки"
	_section_label.tooltip_text = selection.error
	if not selection.error.is_empty() and _section_rect.has_area(): _status(selection.error)
	_update_overlay()


func _confirm_section_selection() -> void:
	if not _section_mode: return
	var selection := SectionSelection.plan(entry.resource, _section_rect)
	if not selection.error.is_empty(): _status(selection.error); return
	# Extent validation is cheap and uses the same gate as Apply.
	var proposed := entry.resource.duplicate(false) as EmberTerrainPilotResource
	proposed.width = selection.extent.x * EmberTerrainPilotResource.Sections.CELLS
	proposed.depth = selection.extent.y * EmberTerrainPilotResource.Sections.CELLS
	var extent_error := _compact_extent_error(scene, proposed)
	if not extent_error.is_empty():
		_show_section_extent_error(extent_error, Vector2i(proposed.width, proposed.depth) / EmberTerrainPilotResource.CELLS_PER_BLOCK)
		return
	_section_mode = false
	_show_section_controls(false)
	_ensure_generation_panel()
	_generation_context = {"area": Rect2i(_section_rect.position * 24, _section_rect.size * 24), "target": weakref(map), "addition": true}
	_generation_panel.open_for(_generation_context.area, selection.keys.size())
	_update_overlay()


func _show_section_extent_error(message: String, proposed_blocks: Vector2i) -> void:
	_status(message)
	if not is_instance_valid(_section_error_dialog):
		_section_error_dialog = AcceptDialog.new()
		_section_error_dialog.title = "Не удалось добавить выбранные участки"
		_section_error_dialog.ok_button_text = "Понятно"
		_section_error_dialog.dialog_autowrap = true
		_section_error_dialog.wrap_controls = false
		EditorInterface.get_base_control().add_child(_section_error_dialog)
	_section_error_dialog.dialog_text = "После добавления размер карты: %d×%d м.\n\n%s\n\nВыделение сохранено: можно закрыть это окно и изменить область." % [proposed_blocks.x, proposed_blocks.y, message]
	var available := EditorInterface.get_base_control().size
	var requested := Vector2i(mini(560, int(available.x * 0.9)), mini(320, int(available.y * 0.8)))
	_section_error_dialog.max_size = requested
	_section_error_dialog.popup_centered(requested)


func _section_point(position: Vector2) -> Variant:
	var projection := map._visual_surface_projection as Node3D
	if not is_instance_valid(projection): return null
	var inverse := projection.global_transform.affine_inverse()
	var origin := inverse * camera.project_ray_origin(position)
	var direction := inverse.basis * camera.project_ray_normal(position)
	var source: EmberTerrainPilotResource = entry.resource
	# The construction plane uses the current land's centre height. Unlike
	# terrain picking it also exists outside the footprint, on every side.
	var height := source.origin_y + source.column_value("heights", source.column_index(source.width / 2, source.depth / 2))
	var point = Plane(Vector3.UP, float(height)).intersects_ray(origin, direction)
	if point == null: return null
	return Vector2i(floori(point.x / EmberTerrainPilotResource.Sections.CELLS), floori(point.z / EmberTerrainPilotResource.Sections.CELLS))


func _forward_section_selection(event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE: cancel_section_selection(); return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER]: _confirm_section_selection(); return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouse and (event.alt_pressed or event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)):
		_section_dragging = false
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion:
		var point = _section_point(event.position)
		if point != null and _section_dragging:
			_section_rect = Rect2i(_section_anchor.min(point), _section_anchor.max(point) - _section_anchor.min(point) + Vector2i.ONE)
			_update_section_selection()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var point = _section_point(event.position)
		if point == null: return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.pressed:
			_section_anchor = point
			_section_dragging = true
			_section_rect = Rect2i(point, Vector2i.ONE)
		elif _section_dragging:
			_section_rect = Rect2i(_section_anchor.min(point), _section_anchor.max(point) - _section_anchor.min(point) + Vector2i.ONE)
			_section_dragging = false
		_update_section_selection()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func commit_selected_sections(target: EmberMapLoader, context: Dictionary) -> String:
	if not is_instance_valid(target): return "Карта была закрыта."
	var draft: Dictionary = context.draft
	if not sessions.entries.values().has(draft) or draft.target.get_ref() != target: return "Черновик карты изменился."
	var before: EmberTerrainPilotResource = draft.resource
	var candidate: EmberTerrainPilotResource = context.candidate
	if not before.same_terrain_data(context.version) or Sessions.compact_layout(target).positions != context.layout:
		return "Карта изменилась после предпросмотра. Обновите предпросмотр."
	var errors := candidate.validation_errors()
	if not errors.is_empty(): return errors[0]
	var extent_error := _compact_extent_error(scene, candidate)
	if not extent_error.is_empty(): return extent_error
	var offset: Vector2i = context.selection.offset
	var shift := Vector3(offset.x, 0, offset.y) * 24 * target.imported_tile_size
	var positions: Dictionary = context.layout.duplicate()
	for group_name in positions:
		positions[group_name] += -(target.basis * shift) if group_name == "Map" else shift
	var history: Object = sessions.undo
	var after_blocks := Vector2i(candidate.width / 16, candidate.depth / 16)
	var before_blocks := target.authored_size_blocks
	var old_scope := edit_region
	var new_scope: Rect2i = context.selection.area
	if history is EditorUndoRedoManager:
		(history as EditorUndoRedoManager).create_action("Добавить выбранные участки", UndoRedo.MERGE_DISABLE, scene)
		Callable(history, "add_do_method").callv([self, "_apply_selected_sections", target, draft, candidate, after_blocks, positions, new_scope])
		Callable(history, "add_undo_method").callv([self, "_apply_selected_sections", target, draft, before, before_blocks, context.layout, old_scope])
		(history as EditorUndoRedoManager).commit_action()
	else:
		(history as UndoRedo).create_action("Добавить выбранные участки", UndoRedo.MERGE_DISABLE)
		(history as UndoRedo).add_do_method(_apply_selected_sections.bind(target, draft, candidate, after_blocks, positions, new_scope))
		(history as UndoRedo).add_undo_method(_apply_selected_sections.bind(target, draft, before, before_blocks, context.layout, old_scope))
		(history as UndoRedo).commit_action()
	return ""


func _apply_selected_sections(target: EmberMapLoader, draft: Dictionary, source: EmberTerrainPilotResource, blocks: Vector2i, positions: Dictionary, scope: Rect2i) -> void:
	if not is_instance_valid(target): return
	var new_position: Vector3 = positions.get("Map", target.position)
	var displacement: Vector3 = target.basis.inverse() * (target.position - new_position) / target.imported_tile_size
	var plan_offset := Vector2i(roundi(displacement.x), roundi(displacement.z))
	var plan: Resource = TerrainPlan.read(target)
	if plan != null and plan_offset != Vector2i.ZERO: sessions.set_plan(draft, plan.translated(plan_offset))
	draft.compact_layout_delta["Map"] = draft.compact_layout_delta.get("Map", Vector3.ZERO) + new_position - target.position
	target.position = new_position
	_apply_compact_extension(target, draft, source, blocks, positions)
	if map == target:
		edit_region = scope
		clip.button_pressed = true
		_refresh_scope()

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
	if parent == object_parameters:
		button.clip_text = true
		button.tooltip_text = text
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
	var workspace := VBoxContainer.new()
	inspector_panel.add_child(workspace)
	var workspace_tabs := HBoxContainer.new(); _workspace_tabs = workspace_tabs; workspace.add_child(workspace_tabs)
	_workspace_tools_button = Button.new(); _workspace_tools_button.text = "Инструменты"
	_workspace_terrain_button = Button.new(); _workspace_terrain_button.text = "Рельеф"
	for tab in [_workspace_tools_button, _workspace_terrain_button]:
		tab.toggle_mode = true; tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL; workspace_tabs.add_child(tab)
	_workspace_tools_button.button_pressed = true
	_workspace_tools_button.pressed.connect(func(): _show_workspace(false))
	_workspace_terrain_button.pressed.connect(_open_terrain_plan)
	_tools_workspace = inspector_layout
	_tools_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(inspector_layout)
	_terrain_workspace = VBoxContainer.new(); _terrain_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(_terrain_workspace); _terrain_workspace.hide()
	_map_creation_workspace = VBoxContainer.new(); _map_creation_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(_map_creation_workspace); _map_creation_workspace.hide()
	_material_workspace = VBoxContainer.new(); _material_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(_material_workspace); _material_workspace.hide()
	_placement_workspace = VBoxContainer.new(); _placement_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(_placement_workspace); _placement_workspace.hide()
	_shape_workspace = VBoxContainer.new(); _shape_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(_shape_workspace); _shape_workspace.hide()
	_duplicate_workspace = VBoxContainer.new(); _duplicate_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(_duplicate_workspace); _duplicate_workspace.hide()
	_merge_workspace = VBoxContainer.new(); _merge_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(_merge_workspace); _merge_workspace.hide()
	_split_workspace = VBoxContainer.new(); _split_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(_split_workspace); _split_workspace.hide()
	_conversion_workspace = VBoxContainer.new(); _conversion_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(_conversion_workspace); _conversion_workspace.hide()
	_object_brush_workspace = VBoxContainer.new(); _object_brush_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(_object_brush_workspace); _object_brush_workspace.hide()
	_object_brush_scroll = ScrollContainer.new()
	_object_brush_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_object_brush_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_object_brush_workspace.add_child(_object_brush_scroll)
	_object_brush_body = VBoxContainer.new(); _object_brush_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_object_brush_scroll.add_child(_object_brush_body)
	_object_brush_title = Label.new(); _object_brush_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_object_brush_body.add_child(_object_brush_title)
	var object_brush_help := Label.new(); object_brush_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	object_brush_help.text = "ЛКМ — объект; протянуть ЛКМ — мазок. Ctrl+Z отменяет весь мазок. Esc в 3D выключает кисть.\nПКМ / СКМ / Alt — камера. До 256 объектов за мазок, только на физической поверхности."
	_object_brush_body.add_child(object_brush_help)
	_object_brush_stop = Button.new(); _object_brush_stop.text = "Выключить кисть"
	_object_brush_stop.pressed.connect(func(): if plugin != null: plugin._stop_scene_object_brush())
	_object_brush_workspace.add_child(_object_brush_stop)
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
	var look_toggle := Button.new()
	look_toggle.text = "Вид мира ▾"
	look_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	look_toggle.toggle_mode = true
	look_toggle.button_pressed = true
	settings.add_child(look_toggle)
	look_panel = WorldLookPanel.new()
	settings.add_child(look_panel)
	look_toggle.toggled.connect(func(open: bool): look_panel.visible = open; look_toggle.text = "Вид мира ▾" if open else "Вид мира ▸")
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
	_generation_button = _button(box, "Сгенерировать рельеф…", _open_terrain_generation)
	_generation_button.tooltip_text = "Остров, берег и холмы в существующей рабочей области. Сначала предпросмотр; применение отменяется одной командой."
	_plan_button = _button(box, "План областей…", _open_terrain_plan)
	_plan_button.tooltip_text = "Сохраняемая разметка и параметры рельефа; земля меняется только при применении."
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
	surface_role_title = Label.new()
	surface_role_title.text = "РОЛЬ ЦВЕТА · ВСЯ КАРТА"
	surface_role_title.add_theme_color_override("font_color",WorkshopTheme.MUTED)
	settings.add_child(surface_role_title)
	surface_role_choice = _choice(settings,[])
	surface_role_choice.tooltip_text = "Смысл материала выбранного слота карты."
	surface_role_choice.add_item("Без роли")
	surface_role_choice.set_item_metadata(0, "")
	for role in EmberTerrainPilotResource.SURFACE_ROLE_IDS:
		surface_role_choice.add_item(EmberTerrainPilotResource.surface_role_name(role))
		surface_role_choice.set_item_metadata(surface_role_choice.item_count - 1, role)
	material_variant_choice = _choice(settings,[])
	material_variant_choice.tooltip_text = "Именованный паттерн выбранного слота. Один вариант можно использовать на многих картах."
	material_slot_button = Button.new()
	material_slot_button.text = "Добавить материал карты"
	material_slot_button.tooltip_text = "Копирует выбранный слот; новый паттерн можно назначить и покрасить им соседние участки."
	settings.add_child(material_slot_button)
	material_slot_button.pressed.connect(_add_compact_material_slot)
	material_pattern_button = Button.new()
	material_pattern_button.text = "Рисовать паттерн…"
	material_pattern_button.tooltip_text = "Рисование через сетку паттернов Surface Canvas. Вариант хранится отдельно от карты."
	settings.add_child(material_pattern_button)
	material_pattern_button.pressed.connect(_open_material_pattern)
	material_pattern_dialog = MaterialPatternDialog.new()
	material_pattern_dialog.pattern_saved.connect(_on_material_pattern_saved)
	material_pattern_dialog.pattern_created.connect(_on_material_pattern_created)
	material_pattern_dialog.edit_closed.connect(_close_material_workspace)
	material_pattern_dialog.variant_opened.connect(_on_material_variant_opened)
	sand_palette = _choice(settings,[])
	palette.item_selected.connect(func(_index): cancel_stroke(); _refresh_palette_swatch())
	surface_role_choice.item_selected.connect(func(index): set_compact_surface_role(int(palette.get_selected_metadata()), str(surface_role_choice.get_item_metadata(index))))
	material_variant_choice.item_selected.connect(func(index): set_compact_surface_material(int(palette.get_selected_metadata()), entry.resource.surface_role_for_palette(int(palette.get_selected_metadata())), str(material_variant_choice.get_item_metadata(index))))
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
	for spec in [["Шаг · блоки","spacing_blocks",0.05,64,1,0.05],["Поворот Y · °","yaw_degrees",-180,180,0,1],["Масштаб","scale_factor",0.05,10,1,0.05],["Заглубление · vox","bury_vox",-64,64,0,0.5]]:
		var group := VBoxContainer.new(); object_parameters.add_child(group)
		var label := Label.new(); label.text = spec[0]; group.add_child(label)
		var control := SpinBox.new(); control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.min_value = spec[2]; control.max_value = spec[3]; control.step = spec[5]; control.value = spec[4]
		group.add_child(control)
		var property: String = spec[1]
		_object_brush_controls[property] = control
		control.value_changed.connect(func(value):
			if plugin != null and is_instance_valid(plugin._object_brush):
				plugin._object_brush.cancel_stroke()
				plugin._object_brush.set(property,value)
		)
	_button(object_parameters,"Библиотека объектов",func(): if plugin != null: plugin._open_voxel_object_library())
	_button(object_parameters,"★ Закрепить текущий объект",func():
		if plugin != null and plugin._object_brush.model_id != "":
			var id: String = plugin._object_brush.model_id
			if id not in favorite_objects: favorite_objects.append(id)
			_save_settings()
			_refresh_favorites()
	)
	_object_parameters_parent = settings; _object_parameters_index = object_parameters.get_index()
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
	if is_instance_valid(_plan_panel) and _plan_panel.visible: _refresh_terrain_plan()
	_update_overlay()
	if started > 0: _compact_trace.record_dirty_status(Time.get_ticks_usec() - started)

func _toggle(value: bool) -> void:
	if not can_leave_panel(): enabled.set_pressed_no_signal(active); return
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
	_plan_selection = ""
	if is_instance_valid(_plan_panel): _plan_panel.hide()
	if is_instance_valid(_generation_panel): _generation_panel.hide()
	clear_terrain_generation_preview()
	cancel_section_selection()
	clear_terrain_generation_preview()
	if is_instance_valid(_generation_panel): _generation_panel.hide()
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
	_panel_host.scene_changed()
	cancel_section_selection()
	clear_terrain_generation_preview()
	if is_instance_valid(_generation_panel): _generation_panel.hide()
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
	if is_instance_valid(look_panel): look_panel.call("set_target",scene,map,sessions.undo)
	if map != null and map.compact_terrain != null and is_instance_valid(terrain_edit_scale):
		terrain_edit_scale.select(0)
		terrain_height_step.select(0)
		brush_shape.select(0)
	entry = {}
	edit_region = Rect2i()
	if active: _target_changed(target_choice.selected)
	_refresh_experiment_gate()
	if _material_mode: _show_material_workspace()

func _target_changed(index: int) -> void:
	if is_instance_valid(_terrain_workspace):
		_terrain_workspace.hide(); _tools_workspace.show()
		if active: sidebar.show()
		_workspace_tools_button.set_pressed_no_signal(true); _workspace_terrain_button.set_pressed_no_signal(false)
	cancel_stroke()
	_plan_selection = ""
	if is_instance_valid(_plan_panel): _plan_panel.hide()
	if is_instance_valid(_generation_panel): _generation_panel.hide()
	clear_terrain_generation_preview()
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
	if _material_mode: _show_material_workspace()

func _refresh_target_actions() -> void:
	if is_instance_valid(_generation_button): _generation_button.visible = _compact_active()
	if is_instance_valid(_plan_button): _plan_button.visible = _compact_active()
	if is_instance_valid(_workspace_terrain_button): _workspace_terrain_button.disabled = not _compact_active()
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
	if index == 3: _sync_object_brush_controls()
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
	material_title.text = "ЦВЕТ ВОДЫ" if category.selected == 2 else "МАТЕРИАЛ ПОВЕРХНОСТИ" if _compact_active() else "ЦВЕТ ПОВЕРХНОСТИ"
	var show_surface_role := _compact_active() and category.selected == 1 and "palette" in active_parameters
	surface_role_title.visible = show_surface_role
	surface_role_choice.visible = show_surface_role
	material_variant_choice.visible = show_surface_role
	material_slot_button.visible = show_surface_role
	material_pattern_button.visible = show_surface_role
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
		var selected_index := int(choice.get_selected_metadata()) if choice.selected >= 0 else -1
		choice.clear()
		for index in range(1,entry.resource.palette.size()):
			var color: Color = entry.resource.palette[index]
			var role: String = entry.resource.surface_role_for_palette(index) if _compact_active() else ""
			var label := "%s · %s · слот %d" % [EmberTerrainPilotResource.surface_role_name(role), entry.resource.material_id_for_palette(index), index] if not role.is_empty() else "Цвет %d · #%s" % [index,color.to_html(false)]
			choice.add_item(label)
			choice.set_item_metadata(choice.item_count-1,index)
		if selected_index >= 1 and selected_index < entry.resource.palette.size():
			choice.select(selected_index - 1)
		elif choice == sand_palette and choice.item_count > 2:
			choice.select(2)
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
	if _compact_active():
		var role: String = entry.resource.surface_role_for_palette(index)
		material_pattern_button.disabled = role.is_empty()
		material_variant_choice.clear()
		if not role.is_empty():
			var ids := EmberVoxelSurfaceMaterials.variants_for_role(role)
			for id in ids:
				material_variant_choice.add_item(id)
				material_variant_choice.set_item_metadata(material_variant_choice.item_count - 1, id)
				if id == entry.resource.material_id_for_palette(index): material_variant_choice.select(material_variant_choice.item_count - 1)
		for item in surface_role_choice.item_count:
			if str(surface_role_choice.get_item_metadata(item)) == role:
				surface_role_choice.select(item)
				break


func _open_material_pattern() -> void:
	if not _compact_active() or palette.selected < 0 or not is_instance_valid(material_pattern_dialog) or plugin == null: return
	if not _material_mode and not can_leave_panel(): return
	var index := int(palette.get_selected_metadata())
	var role: String = entry.resource.surface_role_for_palette(index)
	var id: String = entry.resource.material_id_for_palette(index)
	if not _material_mode:
		_material_bound_map = weakref(map); _material_bound_index = index; _material_bound_id = id
		_material_choices.clear()
		for slot in entry.resource.palette.size():
			var slot_role: String = entry.resource.surface_role_for_palette(slot)
			var slot_id: String = entry.resource.material_id_for_palette(slot)
			if not slot_role.is_empty() and not _material_choices.any(func(choice): return choice.id == slot_id):
				_material_choices.append({"id": slot_id, "role": slot_role, "index": slot})
		material_pattern_dialog.set_variant_choices(_material_choices)
	if role.is_empty() or not material_pattern_dialog.open_variant(id, role):
		_status("Рисунок выбранного материала не найден или повреждён."); return
	_show_material_workspace()


func _on_material_pattern_saved(pattern: TerrainPattern, id: String) -> void:
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection if is_instance_valid(map) else null
	if projection != null:
		projection.set_shared_material_pattern(pattern)
	_status("Паттерн %s сохранён. Карты с этим вариантом обновятся без пересборки земли." % id)


func _on_material_pattern_created(id: String, role: String) -> void:
	var assigned := false
	if _compact_active() and _material_bound_map != null and _material_bound_map.get_ref() == map and _material_bound_index > 0:
		if entry.resource.surface_role_for_palette(_material_bound_index) == role and entry.resource.material_id_for_palette(_material_bound_index) == _material_bound_id:
			assigned = set_compact_surface_material(_material_bound_index, role, id)
	_status("Создан вариант %s. Он назначен исходному материалу карты." % id if assigned else "Создан вариант %s. Выберите его в материалах нужной карты." % id)

func set_compact_surface_role(palette_index: int, role: String) -> bool:
	return set_compact_surface_material(palette_index, role, role)


func set_compact_surface_material(palette_index: int, role: String, id: String) -> bool:
	if not _compact_active() or palette_index <= 0 or palette_index >= entry.resource.palette.size(): return false
	if not role.is_empty() and role not in EmberTerrainPilotResource.SURFACE_ROLE_IDS: return false
	if not id.is_empty():
		var pattern := EmberVoxelSurfaceMaterials.load_compact_terrain_variant(id)
		if pattern == null or pattern.role_id != role or not pattern.validation_errors().is_empty(): return false
	var terrain: EmberTerrainPilotResource = entry.resource
	var before_roles := terrain.palette_surface_roles.duplicate()
	var before_ids := terrain.palette_material_ids.duplicate()
	if terrain.surface_role_for_palette(palette_index) == role and terrain.material_id_for_palette(palette_index) == id: return true
	var after_roles := before_roles.duplicate()
	var after_ids := before_ids.duplicate()
	if after_roles.is_empty(): after_roles.resize(terrain.palette.size())
	if after_ids.is_empty(): after_ids.resize(terrain.palette.size())
	after_roles[palette_index] = role
	after_ids[palette_index] = id
	clear_compact_extension_preview()
	var history := sessions.undo
	var title := "Материал земли · цвет %d" % palette_index
	if history is EditorUndoRedoManager:
		(history as EditorUndoRedoManager).create_action(title, UndoRedo.MERGE_DISABLE, scene)
		Callable(history, "add_do_method").callv([self, "_apply_compact_surface_material", entry, terrain, terrain.palette, after_roles, after_ids])
		Callable(history, "add_undo_method").callv([self, "_apply_compact_surface_material", entry, terrain, terrain.palette, before_roles, before_ids])
		(history as EditorUndoRedoManager).commit_action()
	elif history is UndoRedo:
		(history as UndoRedo).create_action(title, UndoRedo.MERGE_DISABLE)
		(history as UndoRedo).add_do_method(Callable(self, "_apply_compact_surface_material").bind(entry, terrain, terrain.palette, after_roles, after_ids))
		(history as UndoRedo).add_undo_method(Callable(self, "_apply_compact_surface_material").bind(entry, terrain, terrain.palette, before_roles, before_ids))
		(history as UndoRedo).commit_action()
	else:
		return false
	return true

func _add_compact_material_slot() -> void:
	if not _compact_active() or palette.selected < 0: return
	var terrain: EmberTerrainPilotResource = entry.resource
	if terrain.palette.size() >= 256:
		_status("Достигнут предел 255 материалов карты.")
		return
	var selected := int(palette.get_selected_metadata())
	var next_palette := terrain.palette.duplicate()
	next_palette.append(terrain.palette[selected])
	var next_roles := terrain.palette_surface_roles.duplicate()
	if next_roles.is_empty(): next_roles.resize(terrain.palette.size())
	next_roles.append(terrain.surface_role_for_palette(selected))
	var next_ids := terrain.palette_material_ids.duplicate()
	if next_ids.is_empty(): next_ids.resize(terrain.palette.size())
	next_ids.append(terrain.material_id_for_palette(selected))
	var history := sessions.undo
	if history is EditorUndoRedoManager:
		(history as EditorUndoRedoManager).create_action("Добавить материал карты", UndoRedo.MERGE_DISABLE, scene)
		Callable(history, "add_do_method").callv([self, "_apply_compact_surface_material", entry, terrain, next_palette, next_roles, next_ids])
		Callable(history, "add_undo_method").callv([self, "_apply_compact_surface_material", entry, terrain, terrain.palette, terrain.palette_surface_roles, terrain.palette_material_ids])
		(history as EditorUndoRedoManager).commit_action()
	elif history is UndoRedo:
		(history as UndoRedo).create_action("Добавить материал карты")
		(history as UndoRedo).add_do_method(Callable(self, "_apply_compact_surface_material").bind(entry, terrain, next_palette, next_roles, next_ids))
		(history as UndoRedo).add_undo_method(Callable(self, "_apply_compact_surface_material").bind(entry, terrain, terrain.palette, terrain.palette_surface_roles, terrain.palette_material_ids))
		(history as UndoRedo).commit_action()
	else: return
	palette.select(terrain.palette.size() - 2)
	_refresh_palette_swatch()
	_status("Новый слот добавлен. Создайте или выберите вариант и рисуйте им по карте.")


func _apply_compact_surface_material(draft: Dictionary, terrain: EmberTerrainPilotResource, colors: PackedColorArray, roles: PackedStringArray, ids: PackedStringArray) -> void:
	if draft.resource != terrain: return
	terrain.palette = colors.duplicate()
	terrain.palette_surface_roles = roles.duplicate()
	terrain.palette_material_ids = ids.duplicate()
	sessions.preview(draft)
	sessions.changed.emit()
	if entry.get("resource") == terrain: _refresh_palette()

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
	# A west/north candidate compensates Map/group transforms only for display.
	# Restore those before sessions takes its scene snapshot, even when the
	# native editor's _apply_changes hook has not run yet (toolbar Save).
	clear_compact_extension_preview()
	clear_terrain_generation_preview()
	if is_instance_valid(_generation_panel) and _generation_panel.visible:
		_generation_panel.set_pending("Предпросмотр закрыт перед сохранением. Обновите его для применения.")
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
	if not _plan_selection.is_empty() and _compact_active(): footprint = Vector2i(entry.resource.width / 16, entry.resource.depth / 16)
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
	if _panel_host.blocks_viewport_tools():
		return _panel_host.forward_input(event,get_viewport().gui_get_focus_owner())
	if not active: return EditorPlugin.AFTER_GUI_INPUT_PASS
	var received_usec := Time.get_ticks_usec() if _trace.recording and event is InputEventMouse else 0
	var scheduled_usec := int(event.get_meta("ember_scheduled_usec",0)) if received_usec > 0 else 0
	camera = next_camera
	if _section_mode: return _forward_section_selection(event)
	# A dock is nonmodal: camera input still reaches Godot, but inspecting a
	# recipe must not paint the terrain underneath its private preview.
	if is_instance_valid(_terrain_workspace) and _terrain_workspace.visible and not selecting:
		if event is InputEventKey and event.pressed and not event.echo:
			var focus := get_viewport().gui_get_focus_owner()
			if focus is LineEdit or focus is TextEdit: return EditorPlugin.AFTER_GUI_INPUT_PASS
			if event.is_command_or_control_pressed() and event.keycode == KEY_S:
				save_all(); return EditorPlugin.AFTER_GUI_INPUT_STOP
			if event.keycode == KEY_ESCAPE:
				if is_instance_valid(_generation_panel) and _generation_panel.visible: _close_generation_panel()
				else: _show_workspace(false)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if _compact_active() and (category.selected != 3 or not _plan_selection.is_empty()):
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
			if not _plan_selection.is_empty(): _plan_selection = ""; _refresh_terrain_plan(true)
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
	if _plan_selection in ["add_river","add_road","path_line"]: return _forward_plan_path(event)
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
			if not _plan_selection.is_empty(): _plan_selection = ""; _refresh_terrain_plan(true)
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
				_finish_terrain_plan_selection(edit_region)
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
	_process_terrain_generation()
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

func _draw_section_selection(overlay: Control) -> void:
	if not _section_rect.has_area() or entry.is_empty() or _section_rect.size.x > 22 or _section_rect.size.y > 22: return
	var projection := map._visual_surface_projection as Node3D
	if not is_instance_valid(projection): return
	var source: EmberTerrainPilotResource = entry.resource
	var height := float(source.origin_y + source.column_value("heights", source.column_index(source.width / 2, source.depth / 2))) + 1.0
	for z in range(_section_rect.position.y, _section_rect.end.y):
		for x in range(_section_rect.position.x, _section_rect.end.x):
			var key := Vector2i(x, z)
			var polygon := PackedVector2Array()
			for corner in [key, key + Vector2i.RIGHT, key + Vector2i.ONE, key + Vector2i.DOWN]:
				var world_point := projection.to_global(Vector3(corner.x * 384, height, corner.y * 384))
				if camera.is_position_behind(world_point): polygon.clear(); break
				polygon.append(camera.unproject_position(world_point))
			if polygon.size() != 4: continue
			var occupied := SectionSelection.occupied(source, key)
			var colour := Color(0.6, 0.65, 0.7, 0.7) if occupied else Color(0.3, 0.9, 1.0, 0.95)
			overlay.draw_colored_polygon(polygon, Color(colour, 0.07 if occupied else 0.22))
			polygon.append(polygon[0])
			overlay.draw_polyline(polygon, colour, 2, true)


func _path_pick(position: Vector2) -> Vector2:
	var hit := _pick_compact(position)
	if hit.is_empty(): return Vector2(-1,-1)
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	var cell: Vector2i = hit.cell
	var local: Vector3 = projection.to_local(hit.world)
	# Pick the visible water plane rather than a shifted point on the bed.
	for i in 3:
		var index: int = entry.resource.column_index(cell.x,cell.y)
		var level: int = entry.resource.column_value("water_levels",index)
		if level <= entry.resource.column_value("heights",index): break
		var origin := projection.to_local(camera.project_ray_origin(position))
		var ray := projection.global_basis.inverse()*camera.project_ray_normal(position)
		var point: Variant = Plane(Vector3.UP,float(level+entry.resource.origin_y)).intersects_ray(origin,ray)
		if point == null: break
		var next := Vector2i(floori(point.x),floori(point.z))
		if not entry.resource.has_column(next.x,next.y): break
		local = point; cell = next
	return (Vector2(local.x,local.z)/16.0).snapped(Vector2.ONE*0.5)

func _forward_plan_path(event: InputEvent) -> int:
	if event is InputEventMouse and (event.alt_pressed or event.button_mask & (MOUSE_BUTTON_MASK_RIGHT|MOUSE_BUTTON_MASK_MIDDLE)): return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]: return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventKey:
		if event.alt_pressed or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE): return EditorPlugin.AFTER_GUI_INPUT_PASS
		if not event.pressed or event.echo: return EditorPlugin.AFTER_GUI_INPUT_PASS
		if event.is_command_or_control_pressed() and event.keycode in [KEY_Z,KEY_Y]: _open_terrain_plan(); return EditorPlugin.AFTER_GUI_INPUT_PASS
		if event.keycode == KEY_ESCAPE: _open_terrain_plan(); return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode in [KEY_ENTER,KEY_KP_ENTER]: _finish_plan_path(); _update_overlay(); return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_BACKSPACE:
			if not _path_points.is_empty(): _path_points.resize(_path_points.size()-1)
			_update_overlay(); return EditorPlugin.AFTER_GUI_INPUT_STOP
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion:
		_path_hover = _path_pick(event.position); _update_overlay(); return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var point := _path_pick(event.position)
			if point.x < 0: _plan_panel.set_status("На этом месте нет земли. Намечайте линию внутри созданных участков."); return EditorPlugin.AFTER_GUI_INPUT_STOP
			if _path_points.size() >= 32: _plan_panel.set_status("Не больше 32 точек; Enter завершает линию."); return EditorPlugin.AFTER_GUI_INPUT_STOP
			if not _path_points.is_empty() and point.distance_to(_path_points[-1]) < 1: return EditorPlugin.AFTER_GUI_INPUT_STOP
			_path_points.append(point); _path_hover = Vector2(-1,-1)
			_plan_panel.set_status("Точек: %d · Enter — сохранить, Backspace — убрать последнюю, Esc — отменить." % _path_points.size())
			_update_overlay()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _draw_plan_path(overlay: Control, points: PackedVector2Array, color: Color, cache_key: String, direction := true) -> void:
	if points.is_empty(): return
	var cached: Dictionary = _path_draw_cache.get(cache_key,{})
	if cached.get("points") != points:
		cached = {"points":points.duplicate(),"samples":TerrainPlan.Influence.path_curve(points).get_baked_points()}; _path_draw_cache[cache_key] = cached
	var pixels := PackedVector2Array()
	for point: Vector2 in cached.samples:
		var cell := Vector2i(point*16.0)
		if not entry.resource.has_column(cell.x,cell.y): continue
		var index: int = entry.resource.column_index(cell.x,cell.y)
		var height: int = maxi(entry.resource.column_value("heights",index),entry.resource.column_value("water_levels",index))+entry.resource.origin_y
		var world := map._visual_surface_projection.to_global(Vector3(point.x*16.0,height+2,point.y*16.0))
		if camera.is_position_behind(world): pixels.clear(); break
		pixels.append(camera.unproject_position(world))
	if pixels.size() >= 2:
		overlay.draw_polyline(pixels,color,3,true)
		if direction:
			var last := pixels[-1]; var dir := (last-pixels[maxi(0,pixels.size()-4)]).normalized()
			overlay.draw_line(last,last-dir.rotated(0.55)*12,color,2,true); overlay.draw_line(last,last-dir.rotated(-0.55)*12,color,2,true)
	for point in points:
		var cell := Vector2i(point*16.0)
		if not entry.resource.has_column(cell.x,cell.y): continue
		var index: int = entry.resource.column_index(cell.x,cell.y)
		var height: int = maxi(entry.resource.column_value("heights",index),entry.resource.column_value("water_levels",index))+entry.resource.origin_y
		var world := map._visual_surface_projection.to_global(Vector3(point.x*16,height+2,point.y*16))
		if not camera.is_position_behind(world): overlay.draw_circle(camera.unproject_position(world),4,color)

func _draw_terrain_plan(overlay: Control) -> void:
	if _generation_context.has("candidate"):
		var candidate: EmberTerrainPilotResource = _generation_context.candidate
		for point: Vector2i in _generation_context.get("protected_blocks", []):
			var cell := point * 16 + Vector2i(8, 8)
			var height := candidate.origin_y + candidate.column_value("heights", candidate.column_index(cell.x, cell.y))
			var world := map._visual_surface_projection.to_global(Vector3(cell.x, height + 0.5, cell.y))
			if camera.is_position_behind(world): continue
			var pixel := camera.unproject_position(world)
			overlay.draw_line(pixel + Vector2(-3, -3), pixel + Vector2(3, 3), Color(1, 0.75, 0.3), 2)
			overlay.draw_line(pixel + Vector2(-3, 3), pixel + Vector2(3, -3), Color(1, 0.75, 0.3), 2)
	if _plan_selection in ["add_river","add_road","path_line"]:
		var points := _path_points.duplicate()
		if _path_hover.x >= 0 and (points.is_empty() or _path_hover.distance_to(points[-1]) >= 1): points.append(_path_hover)
		_draw_plan_path(overlay,points,Color(0.3,0.9,1),"draft",_plan_path_kind() == "river")
	var plan: Resource = TerrainPlan.read(map)
	if plan == null: return
	for region: Dictionary in plan.regions:
		if region.get("kind") in ["river","road"]:
			_draw_plan_path(overlay,region.points_m,Color(1,0.75,0.3) if region.id == _plan_selected_id else Color(0.4,0.75,0.9,0.65),region.id,region.kind == "river")
			continue
		var rect: Rect2i = region.bounds
		var points := PackedVector2Array()
		for corner in [rect.position, Vector2i(rect.end.x, rect.position.y), rect.end, Vector2i(rect.position.x, rect.end.y), rect.position]:
			var world := _region_frame() * Vector3(corner.x, _region_height(), corner.y)
			if camera.is_position_behind(world): points.clear(); break
			points.append(camera.unproject_position(world))
		if points.is_empty(): continue
		var selected: bool = region.id == _plan_selected_id
		var color := Color(1.0, 0.75, 0.3, 0.95) if selected else Color(0.65, 0.9, 0.7, 0.6)
		overlay.draw_polyline(points, color, 2.5 if selected else 1.5, true)
		overlay.draw_string(ThemeDB.fallback_font, points[0] + Vector2(4, -5), region.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)

func draw_overlay(overlay: Control) -> void:
	if not active or not is_instance_valid(camera): return
	if _section_mode:
		_draw_section_selection(overlay)
		return
	if _compact_active():
		_draw_terrain_plan(overlay)
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
			var height := terrain.column_value("heights", terrain.column_index(sample_x,sample_z))
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
	_panel_host.release()
	clear_terrain_generation_preview()
	if is_instance_valid(_plan_panel): _plan_panel.queue_free()
	if is_instance_valid(_generation_panel): _generation_panel.queue_free()
	if is_instance_valid(_section_error_dialog): _section_error_dialog.queue_free()
	clear_compact_extension_preview()
	_clear_compact_grid_overlay()
	if is_instance_valid(library_favorites_panel): library_favorites_panel.queue_free()
	_set_working_water(false)
	cancel_stroke()
	_clear_experiment()
	if is_instance_valid(material_pattern_dialog) and material_pattern_dialog.get_parent() == null: material_pattern_dialog.free()
	sessions.release()
