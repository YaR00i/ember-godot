@tool
extends Node
## Native 3D input/UI adapter for the existing sculpt model, actions and sessions.
signal active_changed(value: bool)
signal compact_extension_preview_ready
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Selection=preload("res://addons/ember_import/ember_voxel_selection.gd")
const Groups=preload("res://addons/ember_import/ember_voxel_groups.gd")
const VolumeSmooth=preload("res://addons/ember_import/ember_voxel_volume_smooth.gd")
const Actions = preload("res://addons/ember_import/ember_voxel_sculpt_actions.gd")
const Sessions = preload("res://addons/ember_import/ember_world_edit_sessions.gd")
const Fragment = preload("res://addons/ember_import/ember_voxel_fragment.gd")
const WorldEditTrace = preload("res://addons/ember_import/ember_world_edit_trace.gd")
const LandscapeV2Experiment = preload("res://addons/ember_import/ember_landscape_v2_experiment.gd")
const CompactBrush = preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
const CompactBrushMath = preload("res://scripts/prototypes/ember_terrain_pilot_brush_math.gd")
const WorkshopTheme = preload("res://addons/ember_import/ember_voxel_workshop_theme.gd")
const BrushParameters = preload("res://addons/ember_import/ember_world_brush_parameters.gd")
const BrushProfiles = preload("res://addons/ember_import/ember_voxel_brush_profiles.gd")
const CompactMapExtension = preload("res://addons/ember_import/ember_compact_map_extension.gd")
const CompactExtensionPreview = preload("res://addons/ember_import/ember_compact_map_extension_preview.gd")
const TerrainGeneration = preload("res://addons/ember_import/ember_compact_terrain_generation.gd")
const TerrainGenerationPanel = preload("res://addons/ember_import/ember_compact_terrain_generation_dialog.gd")
const TerrainPlan = preload("res://scripts/ember_terrain_plan_resource.gd")
const TerrainPlanPanel = preload("res://addons/ember_import/ember_terrain_plan_dialog.gd")
const Plot = preload("res://addons/ember_import/ember_plot_construction.gd")
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
var pick_target_button:Button
var _changing_context:=false
var _context_pointer:=Vector2.ZERO
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
var compact_detail_pattern: OptionButton
var compact_shape_action: OptionButton
var compact_shape_strength: HSlider
var compact_shape_radius: OptionButton
var _shape_settings: VBoxContainer
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
var _smooth_retired:Array[RefCounted]=[]
var top_cache := {}
var amount_cache := {}
var last_cell := Model.INVALID_CELL
var stroke_mode := ""
var stroke_radius := 16
var stroke_depth := 4
var stroke_palette := 1
var stroke_options := {}
var _clear_shared_mask:Button
var surface_plane_mode:OptionButton
var surface_plane_offset:SpinBox
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
const PATH_POINT_RADIUS := 9.0
const PATH_HIT_RADIUS := 21.0
var _plan_hover_index := -1
var _plan_insert_hover := Vector2.INF
var _plan_selected_id := ""
var _street_preview := {}
var _plan_target: WeakRef
var _plan_point_mode:="move"
var _plan_point_index:=-1
var _plan_drag:Dictionary={}
var _plot_tool := ""
var _plot_street_front := {}
var _street_bridge := {}
var _surface_road_support := ""
var _surface_road_preview := {}
var _surface_bridge_offer := {}
var _road_join := {}
var _branch_edit := {}
var _plot_house_id := ""
var _plot_wall_opening := Plot.WALL_SOLID
var _plot_opening_options: Dictionary = {}
var _plot_entry_portico := false
var _plot_entry_canopy := 3.0
var _plot_wall_color := Color("e1c9a2")
var _plot_wall_finish := 0
var _plot_pilaster_hit: Dictionary = {}
var _plot_roof_options: Dictionary = {}
var _plot_window_name := ""
var _plot_finish_name := ""
var _plot_finish_group := Plot.FINISH_SURFACE
var _plot_balcony_depth := 2.25
var _plot_balcony_columns := false
var _plot_railing_style := Plot.RAIL_METAL
var _plot_edge_anchors := PackedVector2Array()
var _plot_edge_style := Plot.EDGE_STONE
var _plot_edge_depth := 1.5
var _plot_hedge_height := Plot.HEDGE_HEIGHT_M
var _plot_hedge_leaf_scale := 1.0
var _plot_hedge_autumn := false
var _plot_fountain_style := Plot.FOUNTAIN_GARDEN
var _plot_level := 0
var _plot_anchor := Vector2.INF
var _plot_arc_through := Vector2.INF
var _plot_arc_walk := false
var _plot_tower_ports := 0
var _plot_floor_shape := ""
var _plot_corner_cuts := Vector4.ZERO
var _plot_follow_floor := false
var _plot_wall_depth := Plot.WALL_DEPTH_M
var _plot_walk_width := Plot.ARC_WALK_WIDTH_M
var _plot_tower_height := 0.0
var _plot_docking := false
var _plot_docks: Array[Dictionary] = []
var _plot_start_dock := {}
var _plot_hover_dock := {}
var _plot_cursor := Vector2.INF
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
var _detail_brush_workspace: VBoxContainer
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
	_panel_host.register_panel("details",_detail_brush_workspace,{
		"viewport_tools": true, "cancel": plugin._stop_scene_object_brush,
		"closed": func(): if is_instance_valid(plugin._detail_brush): plugin._detail_brush.deactivate()})


func can_leave_panel() -> bool:
	return _panel_host.can_leave()


func _prepare_parameter_panel() -> void:
	if plugin != null: plugin._stop_scene_object_brush()
	cancel_stroke(); cancel_section_selection(); _plan_selection = ""; selecting = false; region_preview = Rect2i()
	_reset_plot_tool()
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
		_plan_cancel_drag()
		_reset_plot_tool()
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
	_reset_plot_tool()
	_clear_street_preview()
	_plan_selection = ""; selecting = false; region_preview = Rect2i()
	_plan_drag.clear();_path_points=PackedVector2Array()
	hover.clear()
	clear_terrain_generation_preview()
	if is_instance_valid(_generation_panel): _generation_panel.hide()
	if is_instance_valid(_plan_panel):_plan_panel.set_compact(false)
	_show_workspace(true)
	_plan_target = weakref(map)
	if not is_instance_valid(_plan_panel):
		_plan_panel = TerrainPlanPanel.new()
		_terrain_workspace.add_child(_plan_panel)
		_plan_panel.action_requested.connect(_terrain_plan_action)
	if not _plan_panel.selection_changed.is_connected(_select_plan_region):_plan_panel.selection_changed.connect(_select_plan_region)
	_refresh_terrain_plan(true)

func _refresh_terrain_plan(reveal := false) -> void:
	if not is_instance_valid(_plan_panel) or _plan_target == null: return
	_clear_street_preview()
	var target: EmberMapLoader = _plan_target.get_ref()
	if not is_instance_valid(target) or target != map: _plan_panel.hide(); return
	var plan: Resource = TerrainPlan.read(target)
	_plan_panel.show_plan(plan if plan != null else TerrainPlan.new(), _plan_selected_id, reveal)
	_plan_selected_id = _plan_panel.selected_id()
	var roofs: Array[Node3D] = []
	var props := target.get_node_or_null("Props")
	if props != null:
		for node in props.get_children():
			if node is Node3D and node.has_meta(Plot.ROOF_META) and node.get_meta(Plot.META, "") == _plan_selected_id:
				roofs.append(node)
	_plan_panel.show_roofs(roofs)
	_refresh_plot_window()
	_refresh_plot_finish()
	var selected_index:int=plan.index_of(_plan_selected_id) if plan!=null else -1
	if selected_index>=0 and not TerrainPlan.Influence.plan_is_path(plan.regions[selected_index]) and _plan_point_mode in ["insert","remove"]:_plan_point_mode="move"
	_plan_panel.set_point_mode(_plan_point_mode)
	_plan_panel.set_branch_pending(not _branch_edit.is_empty())
	_update_overlay()

func commit_terrain_plan(target: EmberMapLoader, plan: Resource, prepared_road: Node3D = null, street_fronts: Array[Node3D] = []) -> String:
	if not is_instance_valid(target) or scene == null: return "Карта была закрыта."
	var draft := sessions.open_map(target, scene)
	if draft.is_empty(): return sessions.error
	if plan != null:
		var extent := Vector2i(draft.resource.width / 16, draft.resource.depth / 16)
		for branch: Dictionary in plan.regions:
			if not branch.get("road_join") is Dictionary or not branch.get("points_m") is PackedVector2Array or branch.points_m.is_empty():
				continue
			var host_index: int = plan.index_of(str(branch.road_join.get("host", "")))
			var fraction: Variant = branch.road_join.get("fraction")
			if host_index < 0 or not fraction is float or not (fraction > 0.0 and fraction < 1.0) or not branch.get("parameters") is Dictionary or branch.get("kind") != "road":
				continue
			var host: Dictionary = plan.regions[host_index]
			if not host.get("points_m") is PackedVector2Array:
				continue
			var curve := TerrainPlan.Influence.path_curve(host.points_m)
			branch.points_m[0] = curve.sample_baked(curve.get_baked_length() * branch.road_join.fraction)
			branch.bounds = _plan_path_bounds(branch, branch.parameters, extent)
		var errors: Array[String] = plan.validation_errors(extent)
		if not errors.is_empty(): return errors[0]
	var before: Resource = TerrainPlan.read(target)
	if TerrainPlan.same(before, plan) and prepared_road == null: return ""
	var baked := _surface_road_delta(target, before, plan, prepared_road)
	if baked.has("error"):
		return baked.error
	baked.added.append_array(street_fronts)
	var history: Object = sessions.undo
	if history is EditorUndoRedoManager:
		(history as EditorUndoRedoManager).create_action("Изменить план областей", UndoRedo.MERGE_DISABLE, scene)
		Callable(history, "add_do_method").callv([self, "_apply_terrain_plan", draft, plan, baked.added, baked.removed])
		Callable(history, "add_undo_method").callv([self, "_apply_terrain_plan", draft, before, baked.removed, baked.added])
		for node in baked.added: history.add_do_reference(node)
		for node in baked.removed: history.add_undo_reference(node)
		(history as EditorUndoRedoManager).commit_action()
	else:
		(history as UndoRedo).create_action("Изменить план областей", UndoRedo.MERGE_DISABLE)
		(history as UndoRedo).add_do_method(_apply_terrain_plan.bind(draft, plan, baked.added, baked.removed))
		(history as UndoRedo).add_undo_method(_apply_terrain_plan.bind(draft, before, baked.removed, baked.added))
		for node in baked.added: history.add_do_reference(node)
		for node in baked.removed: history.add_undo_reference(node)
		(history as UndoRedo).commit_action()
	return ""

func _apply_terrain_plan(draft: Dictionary, plan: Resource, added: Array[Node3D] = [], removed: Array[Node3D] = []) -> void:
	_clear_street_preview()
	sessions.set_plan(draft, plan)
	if not added.is_empty() or not removed.is_empty():
		var props: Node = draft.target.get_ref().get_node("Props")
		_swap_plot_nodes(scene, props, removed, added)
	clear_terrain_generation_preview()
	if is_instance_valid(_generation_panel) and _generation_panel.visible and not _generation_context.get("plan_id", "").is_empty():
		_generation_panel.set_pending("План изменился. Откройте область снова и обновите предпросмотр.")
	_refresh_terrain_plan()
	_sync_plan_context()


func _surface_road_prop(target: EmberMapLoader, id: String) -> EmberVoxelProp:
	var support: EmberVoxelProp
	for prop in target.get_tree().get_nodes_in_group(&"ember_solid_surface"):
		if not target.is_ancestor_of(prop) or prop.placement_id != id:
			continue
		if support != null:
			return null
		support = prop
	return support


func _build_surface_road(target: EmberMapLoader, region: Dictionary) -> Dictionary:
	var support := _surface_road_prop(target, region.support_placement_id)
	var projection := target._visual_surface_projection as EmberTerrainPilotProjection
	var props := target.get_node_or_null("Props") as Node3D
	if support == null or projection == null or props == null:
		return {"error": "Опора дороги не найдена. Выберите объёмный уступ на этой карте."}
	var rect := Rect2(region.bounds)
	var low := projection.to_global(Vector3(rect.position.x * 16.0, 0, rect.position.y * 16.0))
	var high := projection.to_global(Vector3(rect.end.x * 16.0, 0, rect.end.y * 16.0))
	if not projection.detail_area_ready(Rect2(Vector2(low.x, low.z), Vector2(high.x - low.x, high.z - low.z))):
		return {"error": "Подождите, пока загрузится точная земля вдоль дороги."}
	var bridge_requested: bool = region.get("bridge_over_gap", false)
	var sample := func(point: Vector2) -> Dictionary:
		var world := projection.to_global(Vector3(point.x * 16.0, 0, point.y * 16.0))
		var hit := target.surface_floor_sample_with_candidates(world, [support])
		if hit.get("solid", false):
			hit.position = props.to_local(hit.position)
		if bridge_requested and hit.get("submerged", false):
			var water := projection.water_surface_sample(world)
			if water.get("wet", false):
				hit.road_water_y = props.to_local(water.position).y
		return hit
	var place := func(point: Vector2) -> Vector3:
		return props.to_local(projection.to_global(Vector3(point.x * 16.0, 0, point.y * 16.0)))
	return Plot.make_surface_road(region, sample, target.imported_tile_size, place)


func _surface_road_delta(target: EmberMapLoader, before: Resource, after: Resource, prepared: Node3D) -> Dictionary:
	var added: Array[Node3D] = []
	var removed: Array[Node3D] = []
	var props := target.get_node_or_null("Props")
	var current := {}
	if props != null:
		for child in props.get_children():
			if child.owner != null and child.has_meta(Plot.SURFACE_ROAD_META):
				current[child.get_meta(Plot.SURFACE_ROAD_META)] = child
	for region: Dictionary in after.regions if after != null else []:
		if not region.has("support_placement_id") or not region.get("enabled", true):
			continue
		var old_index: int = before.index_of(region.id) if before != null else -1
		if current.has(region.id) and old_index >= 0 and region == before.regions[old_index] and (prepared == null or prepared.get_meta(Plot.SURFACE_ROAD_META) != region.id):
			current.erase(region.id)
			continue
		var built: Dictionary = {"node": prepared} if prepared != null and prepared.get_meta(Plot.SURFACE_ROAD_META, "") == region.id else _build_surface_road(target, region)
		if built.has("error"):
			for node in added:
				if node != prepared: node.free()
			return built
		added.append(built.node)
	removed.assign(current.values())
	return {"added": added, "removed": removed}

func _terrain_plan_action(action: String, id: String, value: String) -> void:
	if _plan_target == null or _plan_target.get_ref() != map: return
	if action in ["extend_branch", "preview_branch"]:
		var plan: Resource = TerrainPlan.read(map)
		var index: int = plan.index_of(id) if plan != null else -1
		if index < 0 or not plan.regions[index].has("road_join"):
			return
		if action == "preview_branch":
			_preview_branch_edits()
			return
		var branch: Dictionary = _branch_edit.get("region", plan.regions[index])
		_plan_selection = "extend_road_branch"
		selecting = true
		_plan_selected_id = id
		_path_points = branch.points_m.duplicate()
		_path_hover = Vector2(-1,-1)
		_plan_panel.set_branch_pending(false)
		_plan_panel.set_status("Щёлкайте после последней точки. Enter оставит новые точки в черновике · Esc отменит продолжение.")
		_update_overlay()
		return
	if _plan_selection == "extend_road_branch":
		_plan_panel.set_status("Завершите продолжение клавишей Enter или отмените его клавишей Esc.")
		return
	if not _branch_edit.is_empty() and action not in ["point_mode", "generate"]:
		_plan_panel.set_status("Сначала примерьте правки ответвления или отмените их клавишей Esc.")
		return
	if action == "generate" and not _branch_edit.is_empty():
		_preview_branch_edits()
		return
	if action == "surface_bridge_preview":
		if _surface_bridge_offer.is_empty():
			return
		var offer := _surface_bridge_offer.duplicate()
		if not TerrainPlan.same(TerrainPlan.read(map), offer.original):
			_clear_surface_road_preview()
			_plan_panel.set_status("План изменился. Enter обновит профиль.")
			return
		offer.region.bridge_over_gap = true
		offer.region.bridge_rise_m = _plan_panel.bridge_profile_rise()
		offer.region.bridge_supports = _plan_panel.bridge_profile_supports()
		offer.region.bridge_railing = _plan_panel.bridge_profile_railing()
		var planks: Variant = _plan_panel.bridge_plank_roughness()
		if planks == null:
			offer.region.erase("bridge_plank_roughness")
		else:
			offer.region.bridge_plank_roughness = planks
		_preview_surface_road(offer.plan, offer.region, offer.original)
		var focus := get_viewport().gui_get_focus_owner()
		if is_instance_valid(focus):
			focus.release_focus()
		_update_overlay()
		return
	if action.begins_with("street_"):
		_street_plot_action(action, id, value)
		return
	if action in ["plot_grid", "plot_round_radius"]:
		_update_overlay()
		return
	_clear_street_preview()
	if action=="point_mode":
		if _branch_edit.is_empty():
			_reset_plot_tool()
		_plan_point_mode=value;_plan_point_index=-1;_plan_hover_index=-1;_plan_insert_hover=Vector2.INF;_plan_drag.clear();_path_points=PackedVector2Array();_update_overlay();return
	_reset_plot_tool()
	if action not in ["compose","groves"]: _plan_selected_id = id
	var original: Resource = TerrainPlan.read(map)
	var plan: Resource = original.working_copy() if original != null else TerrainPlan.new()
	var index: int = plan.index_of(id)
	var supported: bool = index >= 0 and plan.regions[index].has("support_placement_id")
	if action == "generate" and supported:
		if is_instance_valid(_generation_panel): _generation_panel.hide()
		_plan_selection = ""
		selecting = false
		_path_points.clear()
		_plan_panel.set_compact(false)
		_plan_panel.set_status("Дорога следует земле и уступу. «Линия и профиль» открывает правку.")
		return
	if action in ["add", "add_plateau", "add_lake", "add_coast", "add_river", "add_mountain", "add_road", "add_surface_road", "add_road_branch", "add_grove", "add_placement", "add_plot", "bounds"]:
		if action == "bounds" and index < 0: return
		if action == "bounds" and plan.regions[index].has("plot_frame"):
			_plan_point_mode = "move"
			_plan_panel.set_point_mode("move")
			_plan_panel.set_status("Потяните угол участка. Границы двигаются по его сетке.")
			_update_overlay()
			return
		if action == "add_road_branch" and (index < 0 or plan.regions[index].get("kind") != "road" or not plan.regions[index].get("enabled", true) or supported or plan.regions[index].has("road_join")):
			return
		clear_terrain_generation_preview(); cancel_stroke()
		_plan_panel.set_status("Выделите область в 3D · Esc отменяет.")
		_plan_selection = action; selecting = true; create_region = false
		region_anchor = Vector2i(-1, -1); region_preview = Rect2i()
		_path_points = PackedVector2Array(); _path_hover = Vector2(-1,-1)
		if action in ["add_river","add_road","add_surface_road","add_road_branch","add_coast"] or (action == "bounds" and plan.regions[index].get("kind") in ["river","road","coast"]):
			_plan_selection = action if action != "bounds" else "path_line"
			if supported and action == "bounds":
				_surface_road_support = plan.regions[index].support_placement_id
				_path_points = plan.regions[index].points_m.duplicate()
			var path_hint := "Кликайте точки берега: море будет справа по ходу линии." if _plan_path_kind()=="coast" else "Кликайте точки дороги по суше." if _plan_path_kind() == "road" else "Кликайте точки от одного водоёма к другому."
			if action == "add_surface_road":
				path_hint = "Сначала щёлкните по объёмному уступу, затем наметьте дорогу."
			elif action == "add_road_branch":
				path_hint = "Щёлкните по выбранной дороге, затем наметьте ответвление."
			elif supported:
				path_hint = "Измените линию дороги. Enter примеряет полотно по земле и уступу."
			var focus := get_viewport().gui_get_focus_owner()
			if is_instance_valid(focus):
				focus.release_focus()
			var enter_hint := " Enter — предпросмотр." if supported or action in ["add_surface_road","add_road_branch"] else " Enter — сохранить линию."
			_plan_panel.set_status(path_hint+enter_hint+" Backspace — убрать точку, Esc — отменить.")
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
	if plan.regions[index].get("kind") == "construction" and action in ["generate", "plot_house", "plot_apple_tree", "plot_fountain", "plot_fence", "plot_street_front", "plot_wall", "plot_arc_wall", "plot_round_corner", "plot_floor", "plot_column", "plot_entry", "plot_edge", "plot_cornice", "plot_pilaster", "plot_balcony", "plot_railing", "plot_roof", "plot_roof_select", "plot_roof_apply", "plot_window_pick", "plot_window_apply", "plot_finish_pick", "plot_finish_apply", "plot_finish_reset", "plot_level"]:
		if is_instance_valid(_generation_panel): _generation_panel.hide()
		_generation_context = {}
		_plan_panel.set_compact(false)
		if action == "generate":
			_plan_panel.set_status("Жёлтый контур — граница участка. Выберите этаж и инструмент строительства.")
		elif action == "plot_level":
			_plan_panel.set_status("Выбран этаж %d." % (int(value) + 1))
		elif action in ["plot_roof_select", "plot_roof_apply"]:
			_plan_panel.set_status(_edit_plot_roof(value, action == "plot_roof_apply"))
		elif action == "plot_window_apply":
			_plan_panel.set_status(_apply_plot_window())
		elif action in ["plot_finish_apply", "plot_finish_reset"]:
			_plan_panel.set_status(_apply_plot_finish(action == "plot_finish_reset"))
		elif action == "plot_finish_pick":
			_plot_tool = action
			_plot_level = _plan_panel._buttons.plot_level.selected
			_plot_finish_name = ""
			_refresh_plot_finish()
			_plan_panel.set_status("Этаж %d. Щёлкните по нужной поверхности, дверному полотну или раме проёма." % (_plot_level + 1))
		else:
			_plot_tool = action
			_plot_wall_depth = _plan_panel._buttons.plot_wall_depth.value
			_plot_walk_width = _plan_panel._buttons.plot_walk_width.value
			if action in ["plot_wall", "plot_arc_wall", "plot_round_corner", "plot_floor", "plot_column", "plot_cornice", "plot_pilaster", "plot_balcony", "plot_railing", "plot_roof", "plot_window_pick"]:
				_plot_level = _plan_panel._buttons.plot_level.selected
				if action == "plot_floor" and value == "fortress":
					_plot_level = 0
				var props := map.get_node_or_null("Props") as Node3D
				if (_plot_level > 0 or action in ["plot_column", "plot_cornice", "plot_roof"]) and (props == null or not is_finite(_plot_level_y(props))):
					_reset_plot_tool()
					_plan_panel.set_status("Положите перекрытие или проведите стену первого этажа.")
					_update_overlay()
					return
			match action:
				"plot_house":
					_plot_house_id = value
					_plan_panel.set_status("Щёлкните по земле внутри участка.")
				"plot_apple_tree":
					_plan_panel.set_status("Щёлкните по земле, чтобы посадить яблоню.")
				"plot_fountain":
					_plot_fountain_style = _plan_panel._buttons.fountain_style.selected
					_plan_panel.set_status("Щёлкните по ровной земле внутри участка. Контур показывает край чаши.")
				"plot_fence":
					_plan_panel.set_status("Отметьте начало и конец ограды. Проход 1,5 м будет посередине.")
				"plot_street_front":
					_plan_panel.set_status("Щёлкните по соседней дороге. Enter ставит ограду и подход · Esc отменяет.")
				"plot_wall":
					_plot_wall_opening = int(value)
					_plot_wall_color = _plan_panel._buttons.wall_color.color
					_plot_wall_finish = _plan_panel._buttons.wall_finish.selected
					_plot_opening_options = _plan_panel.opening_options(_plot_wall_opening)
					if not Plot.opening_fits(_plot_opening_options):
						var error := _plot_opening_error(_plot_opening_options)
						_reset_plot_tool()
						_plan_panel.set_status(error)
					else:
						_plan_panel.set_status("Этаж %d. Отметьте два конца стены. Esc отменяет." % (_plot_level + 1))
				"plot_floor":
					if value == "chamfer":
						_plot_floor_shape = value
						var controls: Dictionary = _plan_panel._buttons
						_plot_corner_cuts = Vector4(controls.plot_cut_СЗ.value, controls.plot_cut_СВ.value,
							controls.plot_cut_ЮВ.value, controls.plot_cut_ЮЗ.value)
						_plan_panel.set_status("Этаж %d. Отметьте два угла прямоугольника. Срезы видны на контуре." % (_plot_level + 1))
					elif value in ["round", "half"]:
						_plot_floor_shape = value
						_plan_panel.set_status("Отметьте центр и край площадки (радиус 1,5–12 м). Для полукруга край задаёт выпуклую сторону.")
					elif value in ["tower", "fortress"]:
						for option in [_plan_panel._buttons.plot_tower_port_0, _plan_panel._buttons.plot_tower_port_1]:
							if option.selected > 0:
								_plot_tower_ports |= 1 << (option.selected - 1)
						if _plot_tower_ports == 0:
							_reset_plot_tool()
							_plan_panel.set_status("Выберите хотя бы одну грань для прохода башни.")
						elif value == "fortress":
							_plot_tower_height = _plan_panel._buttons.plot_tower_height.value
							_plot_wall_color = _plan_panel._buttons.wall_color.color
							_plot_wall_finish = _plan_panel._buttons.wall_finish.selected
							_plan_panel.set_status("Башня %.2f м. Отметьте два угла основания." % _plot_tower_height)
						else:
							_plan_panel.set_status("Этаж %d. Отметьте два угла площадки башни." % (_plot_level + 1))
					else:
						_plan_panel.set_status("Этаж %d. Отметьте два противоположных угла перекрытия." % (_plot_level + 1))
				"plot_arc_wall":
					_plot_wall_color = _plan_panel._buttons.wall_color.color
					_plot_wall_finish = _plan_panel._buttons.wall_finish.selected
					_plot_arc_walk = _plan_panel._buttons.plot_arc_walk.button_pressed
					_plot_docking = _plot_arc_walk and _plan_panel._buttons.plot_arc_dock.button_pressed
					if _plot_arc_walk and not _plot_docking and _plot_level >= 2:
						_reset_plot_tool()
						_plan_panel.set_status("Для хода выберите первый или второй этаж стены.")
					elif _plot_arc_walk:
						if _plot_docking:
							_plot_docks = _plot_available_docks()
							_plan_panel.set_status("Выберите отмеченный проход первой башни. Он задаст ширину и высоту хода.")
						else:
							_plan_panel.set_status("Ход на уровне %d-го этажа. Начните внутри площадки первой башни." % (_plot_level + 2))
					else:
						_plan_panel.set_status("Этаж %d. Отметьте начало дуговой стены." % (_plot_level + 1))
				"plot_round_corner":
					_plot_cursor = Vector2.INF
					_plan_panel.set_status("Этаж %d. Задайте радиус и наведите на верхний край стыка двух глухих стен." % (_plot_level + 1))
				"plot_entry":
					_plot_entry_portico = _plan_panel._buttons.entry_portico.button_pressed
					_plot_entry_canopy = _plan_panel._buttons.entry_canopy.value
					_plan_panel.set_status("Отметьте два конца крыльца вдоль стены. Ступени будут справа по направлению линии.")
				"plot_column":
					_plot_wall_color = _plan_panel._buttons.wall_color.color
					_plan_panel.set_status("Этаж %d. Щёлкните по узлу сетки на перекрытии." % (_plot_level + 1))
				"plot_edge":
					_plot_edge_style = _plan_panel._buttons.edge_style.selected
					_plot_edge_depth = _plan_panel._buttons.edge_depth.value
					_plot_hedge_height = _plan_panel._buttons.hedge_height.value
					_plot_hedge_leaf_scale = _plan_panel._buttons.hedge_leaf_size.value / 100.0
					_plot_hedge_autumn = _plan_panel._buttons.hedge_season.selected == 1
					if _plan_panel._buttons.edge_snap.button_pressed:
						_plot_edge_anchors = _plot_entry_anchors()
					_plan_panel.set_status("Отметьте два конца вдоль стены. Полоса ляжет справа от линии.")
				"plot_cornice":
					_plan_panel.set_status("Этаж %d. Отметьте два конца вдоль верха стены. Выступ будет справа." % (_plot_level + 1))
				"plot_pilaster":
					_plan_panel.set_status("Этаж %d. Щёлкните по глухой части стены со стороны фасада." % (_plot_level + 1))
				"plot_balcony":
					if _plot_level == 0:
						_reset_plot_tool()
						_plan_panel.set_status("Для балкона выберите второй или третий этаж.")
					else:
						_plot_balcony_depth = _plan_panel._buttons.balcony_depth.value
						_plot_balcony_columns = _plan_panel._buttons.balcony_columns.button_pressed
						_plan_panel.set_status("Отметьте два конца вдоль фасада. Балкон выступит вправо по направлению линии.")
				"plot_railing":
					_plot_railing_style = _plan_panel._buttons.railing_style.selected
					_plot_follow_floor = value == "round"
					_plan_panel.set_status("Щёлкните у края круглой площадки там, где нужен вход." if _plot_follow_floor
						else "Этаж %d. Отметьте два конца перил на перекрытии." % (_plot_level + 1))
				"plot_window_pick":
					_plot_window_name = ""
					_refresh_plot_window()
					_plan_panel.set_status("Этаж %d. Щёлкните по стене с окном или дверью." % (_plot_level + 1))
				"plot_roof":
					var props := map.get_node_or_null("Props") as Node3D
					if not _plot_has_floor(props):
						_reset_plot_tool()
						_plan_panel.set_status("Сначала проведите стену или положите перекрытие на выбранном этаже.")
					else:
						_plot_roof_options = _plan_panel.roof_options()
						_plot_follow_floor = value == "round"
						_plan_panel.set_status("Щёлкните внутри круглой, полукруглой или гранёной площадки." if _plot_follow_floor
							else "Крыша над этажом %d. Отметьте два противоположных угла." % (_plot_level + 1))
		_update_overlay()
		return
	if action == "generate":
		edit_region = plan.regions[index].bounds; _refresh_scope()
		_plan_panel.hide(); _ensure_generation_panel()
		var kind: String = plan.regions[index].get("kind", "generation")
		if kind in ["grove","placement"]:
			_generation_context = {"target":weakref(map),"area":edit_region,"grove":true,"plan_id":id,"plan_version":original.data()}
			_generation_panel.open_placement(edit_region,plan.regions[index].parameters,GrovePlanner.choices(true))
			_plan_panel.set_compact(true);_plan_panel.show();_refresh_terrain_plan()
			return
		var composition: bool = kind in ["plateau","lake","river","mountain","road","coast"]
		_generation_context = {"target": weakref(map), "area": edit_region, "plan_id": id, "plan_version": original.data(), "composition": composition}
		if composition: _generation_panel.open_influence(edit_region, plan.regions[index].parameters,kind)
		else: _generation_panel.open_plan(edit_region, plan.regions[index].parameters)
		_plan_panel.set_compact(true);_plan_panel.show();_refresh_terrain_plan()
		return
	if action == "name": plan.regions[index].name = value.strip_edges()
	elif action == "delete": plan.regions.remove_at(index); _plan_selected_id = ""
	elif action == "toggle": plan.regions[index].enabled = not plan.regions[index].get("enabled", true)
	elif action == "reverse" and plan.regions[index].get("kind") in ["river","coast"]:
		var points: PackedVector2Array = plan.regions[index].points_m.duplicate(); points.reverse(); plan.regions[index].points_m = points
		if plan.regions[index].kind=="coast":plan.regions[index].bounds=_plan_path_bounds(plan.regions[index],plan.regions[index].parameters,Vector2i(entry.resource.width/16,entry.resource.depth/16))
	var error := commit_terrain_plan(map, plan)
	_plan_panel.set_status(error if not error.is_empty() else "План изменён · Ctrl+Z отменяет · Ctrl+S сохраняет сцену.")
	_refresh_terrain_plan()

func _clear_street_preview() -> void:
	if _street_preview.is_empty():
		return
	for front: Node3D in _street_preview.fronts.values():
		front.free()
	_street_preview.clear()
	if is_instance_valid(_plan_panel):
		_plan_panel.show_street_preview(0, 0)
	_update_overlay()


func _street_plot_obstacles(props: Node3D, projection: Node3D) -> Dictionary:
	var occupied := PackedVector2Array()
	for child in props.get_children():
		if child is Node3D:
			occupied.append(_plot_local_grid(projection, child.global_position))
	var solids: Array[Rect2] = []
	for prop in props.get_tree().get_nodes_in_group(&"ember_solid_surface"):
		if prop is not EmberVoxelProp or not props.is_ancestor_of(prop):
			continue
		var box: AABB = prop.surface_floor_bounds()
		if not box.has_volume():
			continue
		var foot := Rect2(_plot_local_grid(projection, box.position), Vector2.ZERO)
		for corner in [box.position + Vector3(box.size.x, 0, 0), box.position + Vector3(0, 0, box.size.z), box.end]:
			foot = foot.expand(_plot_local_grid(projection, corner))
		solids.append(foot)
	return {"anchors": occupied, "solids": solids}


func _prepare_street_plots(plan: Resource, road: Dictionary, options: Dictionary, props: Node3D, projection: EmberTerrainPilotProjection, block := {}) -> Dictionary:
	var source: EmberTerrainPilotResource = entry.resource
	var cell_size := EmberTerrainPilotResource.CELLS_PER_BLOCK
	var extent := Vector2i(source.width / cell_size, source.depth / cell_size)
	var occupied := _street_plot_obstacles(props, projection)
	var fronts := {}
	var layouts := {}
	var corridors := {}
	var accepted: Array[PackedVector2Array] = []
	var outline: PackedVector2Array = block.get("outline", PackedVector2Array())
	var reserved: Array[PackedVector2Array] = []
	if options.entries:
		for solid: Rect2 in occupied.solids:
			reserved.append(PackedVector2Array([solid.position, Vector2(solid.end.x, solid.position.y), solid.end, Vector2(solid.position.x, solid.end.y)]))
	for region: Dictionary in plan.regions:
		var kind: String = region.get("kind", "")
		if kind == "construction" or (region.get("enabled", true) and kind in ["lake", "grove", "placement"]):
			reserved.append(TerrainPlan.Influence.plan_controls(region))
		elif options.entries and region.get("enabled", true) and kind in ["road", "river"]:
			var line := TerrainPlan.Influence.path_curve(region.points_m)
			var edge := float(region.parameters.edge_m if kind == "road" else region.parameters.shore_m)
			var radius := float(region.parameters.width_m) * 0.5 + edge
			corridors[region.id] = Geometry2D.offset_polyline(line.get_baked_points(), radius, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
	var surface := _plot_ground.bind(props)
	var available := func(lot: Dictionary, access: Dictionary, outside: bool) -> bool:
		var bounds: Rect2i = lot.bounds
		var frame := TerrainPlan.Influence.plot_frame(lot)
		var area := TerrainPlan.Influence.plot_rect(lot).grow(0.5)
		var corners := TerrainPlan.Influence.plan_controls(lot)
		var inverse := frame.affine_inverse()
		if not outline.is_empty():
			if not TerrainPlan.Influence.street_block_fits(corners, outline, outside):
				return false
			var clearance := TerrainPlan.Influence.rectangle_points(TerrainPlan.Influence.plot_rect(lot).grow(options.gap), frame)
			for prior in accepted:
				if not Geometry2D.intersect_polygons(clearance, prior).is_empty():
					return false
		for point in occupied.anchors:
			if area.has_point(inverse * point):
				return false
		for solid: Rect2 in occupied.solids:
			if solid.intersects(Rect2(bounds)) and not Geometry2D.intersect_polygons(corners, TerrainPlan.Influence.rectangle_points(solid)).is_empty():
				return false
		if not EmberTerrainPilotResource.Sections.is_dry_rectangle(source, Rect2i(bounds.position * cell_size, bounds.size * cell_size)):
			return false
		if not options.entries:
			accepted.append(corners)
			return true
		var layout := TerrainPlan.Influence.street_frontage(access, lot)
		if layout.is_empty():
			return false
		var envelope := TerrainPlan.Influence.street_plot_envelope(lot, layout)
		if not outline.is_empty() and not TerrainPlan.Influence.street_block_fits(envelope, outline, outside):
			return false
		for road_id in corridors:
			if road_id == access.id:
				continue
			for corridor: PackedVector2Array in corridors[road_id]:
				if not Geometry2D.intersect_polygons(corridor, envelope).is_empty():
					return false
		for prior in reserved:
			if not Geometry2D.intersect_polygons(prior, envelope).is_empty():
				return false
		for point in occupied.anchors:
			if Geometry2D.is_point_in_polygon(point, envelope):
				return false
		var front := Plot.make_street_front(layout, surface, map.imported_tile_size)
		if front == null:
			return false
		reserved.append(envelope)
		accepted.append(corners)
		fronts[frame.origin] = front
		layouts[frame.origin] = layout
		return true
	var inside_seeds: Array = block.get("seeds", [{"road": road, "side": options.side}])
	var outside_seeds: Array = block.get("outside_seeds", [])
	var scope: String = options.get("scope", "inside") if not block.is_empty() else "inside"
	var sides := [false, true] if scope == "both" else [scope == "outside"]
	var lots: Array[Dictionary] = []
	var capacity: int = TerrainPlan.MAX_REGIONS - plan.regions.size()
	for outside: bool in sides:
		# Leave room for the outside in a combined preview even near the map limit.
		var limit := mini(20, capacity - lots.size())
		if scope == "both" and not outside:
			limit = mini(limit, ceili(capacity * 0.5))
		var stop := lots.size() + limit
		for seed: Dictionary in (outside_seeds if outside else inside_seeds):
			lots.append_array(TerrainPlan.Influence.street_plot_candidates(seed.road, plan.regions, extent, options.size, seed.side,
				options.gap, options.setback, stop - lots.size(), available.bind(seed.road, outside), options.get("anchor", Vector2.INF)))
			if lots.size() >= stop:
				break
	return {"lots": lots, "fronts": fronts, "layouts": layouts, "occupied": occupied, "revision": projection.column_revision()}


func _street_plot_action(action: String, id: String, value := "", point := Vector2.INF) -> void:
	if action in ["street_select_all", "street_deselect_all"]:
		if _street_preview.is_empty() or _street_preview.id != id:
			return
		var excluded: Dictionary = _street_preview.excluded
		var count: int = _street_preview.lots.size()
		excluded.clear()
		if action == "street_deselect_all":
			for slot in count:
				excluded[slot] = true
		_plan_panel.show_street_preview(count - excluded.size(), count)
		_update_overlay()
		return
	if action == "street_clear":
		if not _street_preview.is_empty():
			_clear_street_preview()
			_plan_panel.set_status("Предпросмотр убран.")
		return
	var plan: Resource = TerrainPlan.read(map)
	var index: int = plan.index_of(id) if plan != null else -1
	if index < 0 or plan.regions[index].get("kind") != "road" or entry.is_empty():
		return
	var road: Dictionary = plan.regions[index]
	if action in ["street_bridge_style", "street_bridge_deck", "street_bridge_rail", "street_bridge_snap"]:
		if not _street_bridge.is_empty():
			if action == "street_bridge_style":
				_street_bridge.style = value
			_street_bridge.options = _plan_panel.bridge_options()
			var preview: StaticBody3D = _street_bridge.get("node")
			if is_instance_valid(preview):
				if action == "street_bridge_snap":
					if _plot_tool == "street_bridge_edit":
						_plan_panel.set_status(_preview_street_bridge_style(Vector2.ZERO, _street_bridge.get("previous")))
					else:
						_clear_street_bridge_preview()
						_plan_panel.set_status("Стык изменён. Щёлкните по второй дороге ещё раз.")
				else:
					Plot.style_street_bridge(preview, _street_bridge.style, map.imported_tile_size, _street_bridge.options)
		return
	if action in ["street_bridge", "street_bridge_edit"]:
		if not _plan_selection.is_empty():
			_plan_panel.set_status("Завершите текущий контур или отмените его Esc.")
			return
		if action == "street_bridge" and not road.get("enabled", true):
			_plan_panel.set_status("Включите дорогу, чтобы поставить мост.")
			return
		clear_terrain_generation_preview()
		_clear_street_preview()
		_reset_plot_tool()
		_plan_cancel_drag()
		_generation_context.clear()
		if is_instance_valid(_generation_panel):
			_generation_panel.hide()
		_plan_panel.set_compact(true)
		var style: OptionButton = _plan_panel._buttons.street_bridge_style
		_plot_tool = action
		_street_bridge = {"first_road": id, "style": style.get_selected_metadata(), "options": _plan_panel.bridge_options()}
		_plan_panel.set_status("Щёлкните по готовому мосту. Enter применяет облик · Esc отменяет." if action == "street_bridge_edit" else
			"Щёлкните по выбранной дороге, затем по второй. Enter ставит мост · Esc отменяет.")
		_update_overlay()
		return
	if action == "street_panel":
		clear_terrain_generation_preview()
		_generation_context.clear()
		if is_instance_valid(_generation_panel):
			_generation_panel.hide()
		_plan_panel.set_compact(false)
		_plan_panel.set_status("Задайте сторону и размеры, затем нажмите «Показать участки».")
		return
	if not road.get("enabled", true):
		_clear_street_preview()
		_plan_panel.set_status("Включите дорогу, чтобы разметить участки.")
		return
	if action in ["street_preview", "street_block_preview", "street_place"]:
		if not _plan_selection.is_empty():
			_plan_panel.set_status("Завершите текущий контур или отмените его Esc.")
			return
		_clear_street_preview()
		_reset_plot_tool()
		_plan_cancel_drag()
		var manual := action == "street_place"
		if manual and not point.is_finite():
			_plan_selected_id = id
			_plot_tool = action
			_plan_panel.set_status("Щёлкните с нужной стороны улицы. Esc отменяет.")
			return
		var props := map.get_node_or_null("Props") as Node3D
		var projection := map._visual_surface_projection as EmberTerrainPilotProjection
		if props == null or not is_instance_valid(projection):
			_plan_panel.set_status("Дождитесь загрузки поверхности улицы.")
			return
		var options: Dictionary = _plan_panel.street_plot_options()
		if manual:
			options.anchor = point
		var block := {}
		if action == "street_block_preview":
			block = TerrainPlan.Influence.street_block(id, plan.regions)
			if block.is_empty():
				_plan_panel.set_status("Не найдено одно кольцо улиц. Соедините концы улиц точка в точку и выберите улицу на кольце.")
				return
		var draft := _prepare_street_plots(plan, road, options, props, projection, block)
		var lots: Array[Dictionary] = draft.lots
		if lots.is_empty():
			if manual:
				_plot_tool = action
				_plan_panel.set_status("Здесь участок не помещается. Щёлкните в другом месте или уменьшите размеры.")
				return
			_plan_panel.set_status("На выбранной стороне квартала нет места. Уменьшите размеры участков или отступ." if not block.is_empty()
				else "Нет свободных участков с таким отступом и входом. Измените размеры, сторону или отключите входы." if options.entries
				else "На этой стороне нет свободного места. Попробуйте меньшие размеры или другую сторону.")
			return
		draft.merge({"id": id, "original": plan.working_copy(), "excluded": {}})
		_street_preview = draft
		_plan_panel.show_street_preview(lots.size(), lots.size())
		_plan_panel.set_status("Участок привязан к улице. Нажмите «Создать участки» или Esc." if manual
			else "Квартал · доступных мест: %d. Щелчок меняет выбор." % lots.size() if not block.is_empty()
			else "Щёлкните по лишнему участку, чтобы исключить его. Затем нажмите «Создать участки».")
		_update_overlay()
	elif action == "street_apply" and _street_preview.get("id") == id:
		var proposed: Array[Dictionary] = _street_preview.lots
		var excluded: Dictionary = _street_preview.excluded
		var props := map.get_node_or_null("Props") as Node3D
		var projection := map._visual_surface_projection as EmberTerrainPilotProjection
		if props == null or not is_instance_valid(projection) or projection.column_revision() != _street_preview.revision \
				or not TerrainPlan.same(plan, _street_preview.original) or _street_plot_obstacles(props, projection) != _street_preview.occupied:
			_clear_street_preview()
			_plan_panel.set_status("Дорога или свободное место изменились. Постройте предпросмотр заново.")
			return
		var next: Resource = plan.working_copy()
		next.upgrade_local_layers()
		var prefix := "street_%s_%s" % [OS.get_process_id(), Time.get_ticks_usec()]
		var added := 0
		var fronts: Array[Node3D] = []
		for slot in proposed.size():
			if excluded.has(slot):
				continue
			var plot_id := "%s_%d" % [prefix, slot]
			var lot := proposed[slot].duplicate()
			lot.merge({"id": plot_id, "name": "Участок у дороги %d" % (next.regions.size() + 1),
				"kind": "construction", "parameters": {}})
			next.regions.append(lot)
			var key: Vector2 = lot.plot_frame.origin
			var front: Node3D = _street_preview.fronts.get(key)
			if front != null:
				front.set_meta(Plot.META, plot_id)
				front.set_meta(Plot.STREET_FRONT_META, _street_preview.layouts[key].road)
				fronts.append(front)
				_street_preview.fronts.erase(key)
			added += 1
		if added > 0:
			var error := commit_terrain_plan(map, next, null, fronts)
			if not error.is_empty():
				for front in fronts:
					front.free()
				_clear_street_preview()
			_plan_panel.set_status("Создано участков: %d. Входов к улице: %d. Выберите участок, чтобы строить." % [added, fronts.size()] if error.is_empty() else error)


func _finish_terrain_plan_selection(bounds_m: Rect2i) -> void:
	if _plan_selection.is_empty(): return
	var original: Resource = TerrainPlan.read(map)
	var plan: Resource = original.working_copy() if original != null else TerrainPlan.new()
	var added_plot := _plan_selection == "add_plot"
	if _plan_selection in ["add", "add_plateau", "add_lake", "add_mountain", "add_grove", "add_placement", "add_plot"]:
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
		elif added_plot:
			plan.upgrade_local_layers()
			plan.regions[-1].kind = "construction"
			plan.regions[-1].name = "Строительный участок %d" % plan.regions.size()
			plan.regions[-1].parameters = {}
		if _plan_selection in ["add","add_plateau","add_lake","add_mountain"]:
			plan.upgrade_local_layers();plan.regions[-1].parameters.terrain_sampling="fine16"
			if _plan_selection=="add_mountain":plan.regions[-1].parameters.merge({"mountain_shape":"massif","shape_seed":7},true)
		_plan_selected_id = id
	else:
		var index: int = plan.index_of(_plan_selected_id)
		if index >= 0: plan.regions[index].bounds = bounds_m
	_plan_selection = ""
	var error := commit_terrain_plan(map, plan)
	_refresh_terrain_plan(true)
	var index: int = plan.index_of(_plan_selected_id)
	var plot_resized: bool = not added_plot and index >= 0 and plan.regions[index].get("kind") == "construction"
	var message := "Границы изменены. Дома и ограды остались на своих местах." if plot_resized else "Область добавлена в план. Земля не изменена."
	_plan_panel.set_status(error if not error.is_empty() else message)
	if added_plot and error.is_empty():
		_terrain_plan_action("generate", _plan_selected_id, "")


func _reset_plot_tool() -> void:
	_branch_edit.clear()
	_road_join.clear()
	_clear_surface_road_preview()
	_surface_road_support = ""
	_clear_plot_street_front()
	_clear_street_bridge_preview()
	_street_bridge.clear()
	_plot_tool = ""
	_plot_house_id = ""
	_plot_wall_opening = Plot.WALL_SOLID
	_plot_opening_options = {}
	_plot_entry_portico = false
	_plot_edge_anchors.clear()
	_plot_pilaster_hit.clear()
	_plot_roof_options.clear()
	_plot_level = 0
	_plot_anchor = Vector2.INF
	_plot_arc_through = Vector2.INF
	_plot_arc_walk = false
	_plot_tower_ports = 0
	_plot_floor_shape = ""
	_plot_follow_floor = false
	_plot_tower_height = 0.0
	_plot_docking = false
	_plot_docks.clear()
	_plot_start_dock = {}
	_plot_hover_dock = {}
	_plot_cursor = Vector2.INF


func _clear_plot_street_front() -> void:
	var preview: Node3D = _plot_street_front.get("node")
	if is_instance_valid(preview):
		if preview.get_parent() != null:
			preview.get_parent().remove_child(preview)
		preview.queue_free()
	_plot_street_front.clear()


func _preview_plot_street_front(point: Vector2) -> String:
	_clear_plot_street_front()
	var plan: Resource = TerrainPlan.read(map)
	var index: int = plan.index_of(_plan_selected_id) if plan != null else -1
	var props := map.get_node_or_null("Props") as Node3D
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	if index < 0 or props == null or projection == null or plan.regions[index].kind != "construction":
		return "Выберите строительный участок."
	var road := {}
	var closest := INF
	for region: Dictionary in plan.regions:
		if region.get("kind") != "road" or not region.get("enabled", true):
			continue
		var curve := TerrainPlan.Influence.path_curve(region.points_m)
		var distance := curve.get_closest_point(point).distance_to(point)
		if distance <= float(region.parameters.width_m) * 0.5 + 0.25 and distance < closest:
			road = region
			closest = distance
	if road.is_empty():
		return "Щёлкните по полотну соседней дороги."
	var layout := TerrainPlan.Influence.street_frontage(road, plan.regions[index])
	if layout.is_empty():
		return "Здесь ограда не стыкуется с обочиной. Выберите другую дорогу или поправьте границы участка."
	var neighbors: Array[PackedVector2Array] = []
	for region: Dictionary in plan.regions:
		if region.id != _plan_selected_id and region.get("kind") == "construction":
			neighbors.append(TerrainPlan.Influence.plan_controls(region))
	var surface := func(sample: Vector2) -> Vector3:
		for bounds in neighbors:
			if Geometry2D.is_point_in_polygon(sample, bounds):
				return Vector3.INF
		return _plot_ground(sample, props)
	var node := Plot.make_street_front(layout, surface, map.imported_tile_size)
	if node == null:
		return "Для ограды и подхода нужна сухая земля без резких перепадов и свободное место между участками."
	var previous: Node3D
	for child in props.get_children():
		if child is Node3D and child.get_meta(Plot.META, "") == _plan_selected_id and child.has_meta(Plot.STREET_FRONT_META):
			previous = child
			break
	_plot_street_front = {"node":node, "previous":previous,
		"road":road.id, "regions":plan.regions.duplicate(true), "revision":projection.column_revision()}
	node.process_mode = Node.PROCESS_MODE_DISABLED
	props.add_child(node)
	return "Вход к дороге «%s». Enter — поставить · Esc — отменить." % road.name


func _commit_plot_street_front() -> String:
	if _plot_street_front.is_empty():
		return "Сначала щёлкните по соседней дороге."
	var plan: Resource = TerrainPlan.read(map)
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	if plan == null or projection == null or plan.regions != _plot_street_front.regions or projection.column_revision() != _plot_street_front.revision:
		_clear_plot_street_front()
		return "План или земля изменились. Выберите дорогу снова."
	var node: Node3D = _plot_street_front.node
	var props := node.get_parent() as Node3D
	var previous: Node3D = _plot_street_front.previous
	var road_id: String = _plot_street_front.road
	props.remove_child(node)
	node.process_mode = Node.PROCESS_MODE_INHERIT
	node.set_meta(Plot.META, _plan_selected_id)
	node.set_meta(Plot.STREET_FRONT_META, road_id)
	_plot_street_front.erase("node")
	_reset_plot_tool()
	_commit_plot_node(props, node, "Поставить ограду и вход к дороге", previous)
	return "Ограда и подход поставлены · Ctrl+Z отменяет · Ctrl+S сохраняет."


func _clear_street_bridge_preview() -> void:
	var previous: StaticBody3D = _street_bridge.get("previous")
	if is_instance_valid(previous):
		_show_street_bridge_source(previous, true)
	_street_bridge.erase("previous")
	var preview: Node3D = _street_bridge.get("node")
	if is_instance_valid(preview):
		if preview.get_parent() != null:
			preview.get_parent().remove_child(preview)
		preview.queue_free()
	_street_bridge.erase("node")


func _show_street_bridge_source(body: StaticBody3D, show_source: bool) -> void:
	for part in body.get_children():
		if part is MeshInstance3D:
			RenderingServer.instance_set_visible(part.get_instance(), show_source and part.is_visible_in_tree())


func _street_bridge_at(pixel: Vector2, props: Node3D) -> StaticBody3D:
	if not is_instance_valid(camera):
		return null
	var origin := camera.project_ray_origin(pixel)
	var ray := camera.project_ray_normal(pixel)
	var previous: StaticBody3D
	var nearest := INF
	for piece in props.get_children():
		if piece is not StaticBody3D or not piece.has_meta(Plot.STREET_BRIDGE_META) or not piece.is_visible_in_tree():
			continue
		for part in piece.get_children():
			if part is not MeshInstance3D or not part.is_visible_in_tree():
				continue
			var inverse: Transform3D = part.global_transform.affine_inverse()
			var hit: Variant = part.get_aabb().intersects_ray(inverse * origin, inverse.basis * ray)
			if hit != null:
				var distance := origin.distance_squared_to(part.to_global(hit))
				if distance < nearest:
					nearest = distance
					previous = piece
	return previous


func _preview_street_bridge_style(pixel: Vector2, previous: StaticBody3D = null) -> String:
	_clear_street_bridge_preview()
	var props := map.get_node_or_null("Props") as Node3D
	if props == null:
		return "Щёлкните по готовому мосту."
	if not is_instance_valid(previous):
		previous = _street_bridge_at(pixel, props)
	if previous == null or previous.get_parent() != props:
		return "Щёлкните по готовому мосту."
	var preview: StaticBody3D
	var plan: Resource = TerrainPlan.read(map)
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	var snap: String = _street_bridge.options.snap
	if snap != "keep" and snap != previous.get_meta(Plot.BRIDGE_SNAP_META, "axis"):
		var deck := previous.get_node_or_null("DeckShape") as CollisionShape3D
		if plan == null or projection == null or deck == null or not deck.shape is BoxShape3D:
			return "Не удалось прочитать стыки моста."
		var ids: PackedStringArray = previous.get_meta(Plot.STREET_BRIDGE_META)
		var saved_axes: PackedVector2Array = previous.get_meta(Plot.BRIDGE_AXES_META, PackedVector2Array())
		var docks: Array[Dictionary] = []
		for index in ids.size():
			var road_index: int = plan.index_of(ids[index])
			if road_index < 0 or not plan.regions[road_index].get("enabled", true):
				return "Обе дороги должны быть в плане и включены."
			var road: Dictionary = plan.regions[road_index]
			var side := -1.0 if index == 0 else 1.0
			var end := previous.to_global(Vector3(0.0, 0.0, deck.shape.size.z * side * 0.5))
			var curve := TerrainPlan.Influence.path_curve(road.points_m)
			var anchor := saved_axes[index] if saved_axes.size() == 2 else _plot_local_grid(projection, end)
			docks.append({"point": curve.get_closest_point(anchor), "curve": curve,
				"width": road.parameters.width_m, "id": road.id})
		if docks.size() != 2:
			return "Для перестыковки нужны две дороги."
		var result := _build_street_bridge_candidate(docks[0], docks[1], props, projection)
		preview = _street_bridge.get("node")
		if preview == null:
			return result
		if _street_bridge.style == "broken":
			preview.set_meta(Plot.BRIDGE_MATERIAL_META, previous.get_meta(Plot.BRIDGE_MATERIAL_META, previous.get_meta(Plot.BRIDGE_STYLE_META, "wood")))
			if _street_bridge.options.deck == "preset" and previous.has_meta(Plot.BRIDGE_DECK_META):
				preview.set_meta(Plot.BRIDGE_DECK_META, previous.get_meta(Plot.BRIDGE_DECK_META))
			if _street_bridge.options.rail == "preset" and previous.has_meta(Plot.BRIDGE_RAIL_META):
				preview.set_meta(Plot.BRIDGE_RAIL_META, previous.get_meta(Plot.BRIDGE_RAIL_META))
			Plot.style_street_bridge(preview, "broken", map.imported_tile_size, _street_bridge.options)
	else:
		preview = previous.duplicate() as StaticBody3D
		if not Plot.style_street_bridge(preview, _street_bridge.style, map.imported_tile_size, _street_bridge.options):
			preview.free()
			return "Не удалось прочитать размеры настила."
	preview.remove_meta(Plot.STREET_BRIDGE_META)
	preview.process_mode = Node.PROCESS_MODE_DISABLED
	_show_street_bridge_source(previous, false)
	if preview.get_parent() == null:
		props.add_child(preview, true)
	_street_bridge.node = preview
	_street_bridge.previous = previous
	_street_bridge.previous_transform = previous.transform
	_street_bridge.edit_regions = plan.regions.duplicate(true) if plan != null else []
	_street_bridge.edit_revision = projection.column_revision() if projection != null else -1
	return "Разрыв настила примерен. Enter — применить · Esc — отменить." if _street_bridge.style == "broken" else "Облик примерен. Enter — применить · Esc — отменить."


func _pick_street_bridge_point(point: Vector2) -> String:
	var plan: Resource = TerrainPlan.read(map)
	var props := map.get_node_or_null("Props") as Node3D
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	if plan == null or props == null or projection == null or _street_bridge.is_empty():
		return "Откройте план дорог."
	var first: Dictionary = _street_bridge.get("start", {})
	var dock := {}
	var nearest := INF
	for road: Dictionary in plan.regions:
		if road.get("kind") != "road" or not road.get("enabled", true):
			continue
		if (road.id == _street_bridge.first_road) != first.is_empty():
			continue
		var curve := TerrainPlan.Influence.path_curve(road.points_m)
		var center := curve.get_closest_point(point)
		var distance := point.distance_to(center)
		var width := float(road.parameters.width_m)
		if distance <= width * 0.5 + 0.25 and distance < nearest:
			nearest = distance
			dock = {"id": road.id, "point": center, "width": width, "curve": curve}
	if dock.is_empty():
		return "Щёлкните по выбранной дороге." if first.is_empty() else "Щёлкните по полотну другой дороги."
	var dock_grid: Vector2 = dock.point * 16.0
	var dock_world := projection.to_global(Vector3(dock_grid.x, 0, dock_grid.y))
	var dock_xz := Vector2(dock_world.x, dock_world.z)
	if not projection.detail_area_ready(Rect2(dock_xz, Vector2.ZERO)):
		return "Дождитесь точной земли у стыка и щёлкните снова."
	if not _plot_ground(dock.point, props).is_finite():
		return "Стык должен опираться на сухую часть дороги."
	if first.is_empty():
		_street_bridge.start = dock
		_street_bridge.regions = plan.regions.duplicate(true)
		_street_bridge.revision = projection.column_revision()
		return "Первый стык отмечен. Щёлкните по второй дороге."
	_clear_street_bridge_preview()
	if plan.regions != _street_bridge.regions or projection.column_revision() != _street_bridge.revision:
		_street_bridge.erase("start")
		return "План или земля изменились. Выберите первый стык заново."
	return _build_street_bridge_candidate(first, dock, props, projection)


func _build_street_bridge_candidate(first: Dictionary, dock: Dictionary, props: Node3D, projection: EmberTerrainPilotProjection) -> String:
	var a_point: Vector2 = first.point
	var b_point: Vector2 = dock.point
	var snap: String = _street_bridge.options.snap
	if snap != "axis":
		snap = "edge"
		a_point = TerrainPlan.Influence.bridge_road_edge(first.curve, first.point, dock.point, first.width * 0.5)
		b_point = TerrainPlan.Influence.bridge_road_edge(dock.curve, dock.point, first.point, dock.width * 0.5)
	if not a_point.is_finite() or not b_point.is_finite():
		return "По этому направлению нет двух свободных краёв дороги. Выберите другие точки."
	var length := a_point.distance_to(b_point)
	if length < 2.0 or length > 32.0:
		return "Для моста нужен пролёт от 2 до 32 м."
	var width := minf(3.0, minf(first.width, dock.width))
	var tile := map.imported_tile_size
	var first_world := projection.to_global(Vector3(a_point.x * 16.0, 0, a_point.y * 16.0))
	var last_world := projection.to_global(Vector3(b_point.x * 16.0, 0, b_point.y * 16.0))
	var a := Vector2(first_world.x, first_world.z)
	var b := Vector2(last_world.x, last_world.z)
	var footprint := Rect2(a.min(b), (a - b).abs()).grow(width * tile * 0.5)
	if not projection.detail_area_ready(footprint):
		return "Дождитесь точной земли под пролётом и щёлкните снова."
	var start := _plot_ground(a_point, props) + Vector3.UP * tile * 0.05
	var end := _plot_ground(b_point, props) + Vector3.UP * tile * 0.05
	if not start.is_finite() or not end.is_finite():
		return "Стыкам нужна сухая земля."
	if absf(end.y - start.y) > length * tile * 0.2:
		return "Перепад слишком большой. Выберите стыки ближе по высоте."
	var axis := a_point.direction_to(b_point)
	var side := Vector2(-axis.y, axis.x)
	var spans_gap := false
	var rows := ceili(length / 0.25)
	for row in range(rows + 1):
		var ratio := float(row) / rows
		var sample := a_point.lerp(b_point, ratio)
		var deck := lerpf(start.y, end.y, ratio)
		for offset: float in [-width * 0.5, 0.0, width * 0.5]:
			var grid := (sample + side * offset) * 16.0
			var world := projection.to_global(Vector3(grid.x, 0, grid.y))
			var floor := projection.floor_surface_sample(world)
			if not floor.get("solid", false):
				return "Пролёт выходит за пределы подготовленной земли."
			var ground := props.to_local(floor.position).y
			var water := projection.water_surface_sample(world)
			var wet: bool = water.get("wet", false)
			var clearance := deck - ground
			if row in [0, rows] and (wet or absf(clearance) > tile * 0.22):
				return "По всей ширине въезда нужна сухая ровная опора."
			if clearance < -tile * 0.08 or (wet and deck < props.to_local(water.position).y + tile * 0.08):
				return "Настил пересекает землю или воду. Сдвиньте стыки."
			if wet or clearance > tile * 0.35:
				spans_gap = true
	if not spans_gap:
		return "Между выбранными точками нет воды или перепада под настилом."
	var node := Plot.make_street_bridge(start, end, width, tile, _street_bridge.style, _street_bridge.options)
	node.set_meta(Plot.BRIDGE_SNAP_META, snap)
	node.set_meta(Plot.BRIDGE_AXES_META, PackedVector2Array([first.point, dock.point]))
	node.process_mode = Node.PROCESS_MODE_DISABLED
	props.add_child(node, true)
	_street_bridge.node = node
	_street_bridge.second_road = dock.id
	return "Мост примерен. Enter — поставить · другой щелчок — сменить второй стык · Esc — отменить."


func _commit_street_bridge() -> String:
	var node: Node3D = _street_bridge.get("node")
	if not is_instance_valid(node):
		return "Щёлкните по готовому мосту." if _plot_tool == "street_bridge_edit" else "Выберите оба стыка для предпросмотра моста."
	if _plot_tool == "street_bridge_edit":
		var previous: StaticBody3D = _street_bridge.get("previous")
		var parent := node.get_parent() as Node3D
		var edited_plan: Resource = TerrainPlan.read(map)
		var edited_projection := map._visual_surface_projection as EmberTerrainPilotProjection
		if not is_instance_valid(previous) or previous.get_parent() != parent or previous.transform != _street_bridge.previous_transform \
			or edited_plan == null or edited_projection == null or edited_plan.regions != _street_bridge.edit_regions \
			or edited_projection.column_revision() != _street_bridge.edit_revision:
			_reset_plot_tool()
			return "Мост изменился. Примерьте облик заново."
		node.set_meta(Plot.STREET_BRIDGE_META, previous.get_meta(Plot.STREET_BRIDGE_META))
		parent.remove_child(node)
		node.name = previous.name
		node.process_mode = previous.process_mode
		_street_bridge.erase("node")
		_reset_plot_tool()
		_commit_plot_node(parent, node, "Изменить облик моста", previous)
		if node.get_meta(Plot.BRIDGE_STYLE_META) == "broken":
			return "Мост разрушен, проход разорван · Ctrl+Z отменяет · Ctrl+S сохраняет."
		return "Облик моста обновлён · Ctrl+Z отменяет · Ctrl+S сохраняет."
	var plan: Resource = TerrainPlan.read(map)
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	if plan == null or projection == null or plan.regions != _street_bridge.regions or projection.column_revision() != _street_bridge.revision:
		_reset_plot_tool()
		return "План или земля изменились. Включите инструмент моста заново."
	var props := node.get_parent() as Node3D
	props.remove_child(node)
	node.process_mode = Node.PROCESS_MODE_INHERIT
	node.set_meta(Plot.STREET_BRIDGE_META, PackedStringArray([_street_bridge.first_road, _street_bridge.second_road]))
	_street_bridge.erase("node")
	_reset_plot_tool()
	_commit_plot_node(props, node, "Поставить мост между дорогами")
	return "Мост поставлен · Ctrl+Z отменяет · Ctrl+S сохраняет."


func _plot_ground(point: Vector2, parent: Node3D) -> Vector3:
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	if not is_instance_valid(projection) or entry.is_empty():
		return Vector3.INF
	var source: EmberTerrainPilotResource = entry.resource
	var grid := point * 16.0
	var cell := Vector2i(grid.floor())
	if not source.has_column(cell.x, cell.y):
		return Vector3.INF
	var index := source.column_index(cell.x, cell.y)
	if source.column_value("water_levels", index) > source.column_value("heights", index):
		return Vector3.INF
	var hit := projection.floor_surface_sample(projection.to_global(Vector3(grid.x, 0, grid.y)))
	return parent.to_local(hit.position) if hit.get("solid", false) else Vector3.INF


func _plot_level_y(props: Node3D) -> float:
	return Plot.level_origin(props, _plan_selected_id, map.imported_tile_size) + _plot_level * Plot.WALL_HEIGHT_M * map.imported_tile_size


func _plot_has_floor(props: Node3D) -> bool:
	for member in props.get_children():
		if member.get_meta(Plot.META, "") == _plan_selected_id and int(member.get_meta(Plot.LEVEL_META, 0)) == _plot_level:
			if member.has_node("Wall") or member.has_node("Slab"):
				return true
	return false


func _plot_entry_anchors() -> PackedVector2Array:
	var props := map.get_node_or_null("Props")
	var points := PackedVector2Array()
	if props == null:
		return points
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	if not is_instance_valid(projection):
		return points
	for node in props.get_children():
		if node is Node3D and node.get_meta(Plot.META, "") == _plan_selected_id and node.has_node("Entry"):
			for corner in Plot.entry_corners(node):
				var local := projection.to_local(corner)
				points.append(Vector2(local.x, local.z) / 16.0)
	return points


func _plot_plane_y(props: Node3D) -> float:
	var offset := Plot.WALL_HEIGHT_M * map.imported_tile_size if _plot_tool in ["plot_cornice", "plot_roof"] else 0.0
	if _plot_tool in ["plot_column", "plot_railing"]:
		offset = Plot.BALCONY_TOP * map.imported_tile_size
	return _plot_level_y(props) + offset


func _plot_click(point: Vector2) -> String:
	var plan: Resource = TerrainPlan.read(map)
	var index: int = plan.index_of(_plan_selected_id) if plan != null else -1
	if index < 0 or plan.regions[index].get("kind") != "construction":
		return "Выберите строительный участок."
	var region: Dictionary = plan.regions[index]
	var frame := TerrainPlan.Influence.plot_frame(region)
	var inverse := frame.affine_inverse()
	var bounds := TerrainPlan.Influence.plot_rect(region)
	if not point.is_finite() or not bounds.has_point(inverse * point):
		return "Выберите точку внутри участка."
	var props := map.get_node_or_null("Props") as Node3D
	if props == null or not is_instance_valid(scene):
		return "На карте нет контейнера объектов."
	if _plot_tool == "plot_round_corner":
		return _round_plot_corner(props, point, bounds, inverse)
	var ground := _plot_ground(point, props)
	if not ground.is_finite():
		return "Здесь нужна сухая земля."
	var node: Node3D
	var label := "Поставить дом на участке"
	if _plot_tool == "plot_house":
		var path := EmberVoxelPrefab.prefab_path(_plot_house_id)
		var packed := ResourceLoader.load(path) as PackedScene if ResourceLoader.exists(path) else null
		if packed == null or not EmberVoxelPrefab.validate_packed(_plot_house_id, packed).get("ok", false):
			return "Готовый шаблон дома не найден."
		var prop := EmberSceneAuthoring.make_model_instance(scene, packed, _plot_house_id, ground)
		if prop == null:
			return "Не удалось открыть шаблон дома."
		prop.configure_voxel_scale(prop.voxels_per_block, map.imported_tile_size)
		prop.rotation.y -= frame.get_rotation()
		node = prop
	elif _plot_tool == "plot_apple_tree":
		node = Plot.make_apple_tree(ground)
		label = "Поставить яблоню"
	elif _plot_tool == "plot_fountain":
		var radius: float = Plot.FOUNTAIN_RADII[_plot_fountain_style]
		if not bounds.encloses(Rect2(inverse * point - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)):
			return "Чаша фонтана должна целиком поместиться на участке."
		node = Plot.make_fountain(point, _plot_fountain_style, _plot_ground.bind(props), map.imported_tile_size)
		if node == null:
			return "Для чаши нужна ровная сухая площадка."
		label = "Поставить фонтан"
	elif _plot_follow_floor:
		var roof := _plot_tool == "plot_roof"
		var target := _plot_contour_target(props, point, roof)
		if target.is_empty():
			return "Выберите круглую, полукруглую или гранёную площадку." if roof else "Щёлкните у края круглой площадки."
		var floor: Node3D = target.floor
		var profile: Dictionary = target.profile
		var tile := map.imported_tile_size
		if roof:
			if not _plot_outline_fits(bounds, target.center, Plot.contour_roof_outline(profile), inverse):
				return "Крыша со свесом должна поместиться на участке."
			node = Plot.make_contour_roof(profile, _plot_roof_options.height, _plot_roof_options.color, tile)
			label = "Поставить крышу по контуру"
		else:
			node = Plot.make_round_railing(profile, point - target.center, tile, _plot_railing_style)
			label = "Поставить перила с входом"
		node.position = floor.position + Vector3.UP * (Plot.WALL_HEIGHT_M * tile if roof else 0.0)
	elif _plot_tool == "plot_column":
		if not _plot_floor_supports_segment(props, ground, ground):
			return "Выберите узел на перекрытии этого этажа."
		node = Plot.make_column(ground, _plot_level_y(props), map.imported_tile_size, _plot_wall_color)
		label = "Поставить колонну"
	elif _plot_tool in ["plot_fence", "plot_wall", "plot_arc_wall", "plot_floor", "plot_entry", "plot_edge", "plot_cornice", "plot_roof", "plot_balcony", "plot_railing"]:
		if not _plot_anchor.is_finite():
			if _plot_docking:
				_plot_start_dock = _plot_dock_at(point)
				if _plot_start_dock.is_empty():
					return "Выберите свободный проход площадки башни на уровне настила."
				_plot_anchor = _plot_start_dock.point
			else:
				_plot_anchor = point
			return "Отметьте точку на изгибе." if _plot_tool == "plot_arc_wall" else "Начало отмечено. Выберите вторую точку."
		if not bounds.has_point(inverse * _plot_anchor):
			return "Первая точка оказалась за границей участка. Отмените линию Esc."
		if _plot_tool == "plot_wall":
			var minimum := Plot.minimum_wall_length(_plot_wall_opening, _plot_opening_options)
			if _plot_anchor.distance_to(point) < minimum or _plot_anchor.distance_to(point) > Plot.MAX_FENCE_M:
				return "Длина стены должна быть от %s до 48 м." % minimum
			node = Plot.make_wall(_plot_anchor, point, _plot_wall_opening, _plot_ground.bind(props), map.imported_tile_size,
				_plot_level_y(props), _plot_level == 0, _plot_wall_neighbors(props), _plot_opening_options, _plot_wall_color, _plot_wall_finish, _plot_wall_depth)
			if node == null:
				return "Для стены нужна сухая ровная площадка."
			label = "Провести стену"
		elif _plot_tool == "plot_arc_wall":
			if not _plot_arc_through.is_finite():
				if _plot_anchor.distance_to(point) < 0.5:
					return "Отметьте изгиб хотя бы в 0,5 м от начала."
				_plot_arc_through = point
				return "Выберите отмеченный проход второй башни." if _plot_docking else "Отметьте конец дуги. Esc отменяет построение."
			var arc := _plot_arc_layout(point)
			if arc.is_empty():
				if _plot_docking:
					var dock := _plot_dock_at(point)
					if dock.is_empty():
						return "Выберите свободный проход другой башни."
					if not _plot_docks_match(dock):
						return "Выберите проход той же ширины и на той же высоте."
					return "Ход не помещается между гранями. Перенесите точку изгиба дальше от входов."
				if _plot_arc_walk:
					return "Для хода нужен более широкий поворот. Дуга до 180° и длиной до 48 м."
				return "Выберите конец, чтобы получилась дуга до 180° и длиной до 48 м."
			for edge: PackedVector2Array in [arc.left, arc.right]:
				for edge_point in edge:
					if not bounds.has_point(inverse * edge_point):
						return "Стена должна целиком поместиться на участке."
			var base_y := Plot.level_origin(props, _plan_selected_id, map.imported_tile_size) if _plot_arc_walk else _plot_level_y(props)
			var walk_height := Plot.WALL_HEIGHT_M * (_plot_level + 1) if _plot_arc_walk else 0.0
			if _plot_docking:
				walk_height = (_plot_start_dock.y - base_y) / map.imported_tile_size - Plot.FLOOR_TOP_M
			node = Plot.make_arc_wall(arc, _plot_ground.bind(props), map.imported_tile_size, base_y,
				_plot_arc_walk or _plot_level == 0, _plot_wall_neighbors(props), _plot_wall_color, _plot_wall_finish, walk_height)
			if node == null:
				return "Для дуги нужна сухая ровная площадка."
			if _plot_docking:
				node.set_meta(Plot.DOCKED_WALK_META, true)
			label = "Провести дуговую стену с ходом" if _plot_arc_walk else "Провести дуговую стену"
		elif _plot_tool == "plot_floor":
			var tile := map.imported_tile_size
			var pose := _plot_frame_pose(frame, props)
			var surface := _plot_frame_ground.bind(frame, pose.affine_inverse(), props)
			if not _plot_floor_shape.is_empty():
				var layout := _plot_contour_layout(point)
				if layout.profile.is_empty():
					if _plot_floor_shape == "chamfer":
						return "Уменьшите срезы или увеличьте площадку. На каждой стороне должно остаться 0,5 м."
					return "Выберите радиус от 1,5 до 12 м."
				if not _plot_outline_fits(bounds, layout.center, Plot.floor_outline(layout.profile), inverse):
					return "Вся площадка должна поместиться на участке."
				node = Plot.make_contour_floor(layout.center, layout.profile, _plot_ground.bind(props), tile, _plot_level_y(props))
				if node == null:
					return "Нужна сухая земля без выступов над площадкой."
				label = "Положить площадку по контуру"
			elif _plot_tower_height > 0.0:
				node = Plot.make_fortress_tower(inverse * _plot_anchor, inverse * point, surface, tile, _plot_level_y(props),
					_plot_tower_height, _plot_wall_depth, _plot_walk_width, _plot_tower_ports, _plot_wall_color, _plot_wall_finish)
				if node == null:
					return "Башне нужна ровная сухая земля и место для стен и проходов."
				node.transform = pose * node.transform
				label = "Построить башню"
			else:
				node = Plot.make_floor(inverse * _plot_anchor, inverse * point, surface, tile, _plot_level_y(props))
				if node == null:
					return "Нужно сухое основание и стороны перекрытия от 1 до 48 м."
				label = "Положить перекрытие"
				if _plot_tower_ports != 0 and not Plot.add_tower_ports(node, _plot_tower_ports, tile, _plot_walk_width):
					node.free()
					return "Стороны площадки должны быть хотя бы на 1 м шире хода."
				node.transform = pose * node.transform
		elif _plot_tool == "plot_entry":
			for corner in Plot.entry_outline(_plot_anchor, point):
				if not bounds.has_point(inverse * corner):
					return "Крыльцо и ступени должны целиком поместиться на участке."
			node = Plot.make_entry(_plot_anchor, point, _plot_ground.bind(props), map.imported_tile_size, _plot_entry_portico, _plot_entry_canopy)
			if node == null:
				return "Для крыльца нужна сухая ровная площадка и ширина от 2 до 12 м."
			label = "Поставить крыльцо"
		elif _plot_tool == "plot_edge":
			for corner in Plot.strip_outline(_plot_anchor, point, _plot_edge_depth):
				if not bounds.has_point(inverse * corner):
					return "Вся полоса должна поместиться на участке."
			node = Plot.make_edge(_plot_anchor, point, _plot_edge_depth, _plot_edge_style, _plot_ground.bind(props),
				map.imported_tile_size, _plot_hedge_height, _plot_hedge_leaf_scale, _plot_hedge_autumn)
			if node == null:
				return "Нужна сухая ровная площадка и длина от 1 до 48 м."
			label = "Провести полосу у дома"
		elif _plot_tool == "plot_cornice":
			var first := _plot_ground(_plot_anchor, props)
			if not first.is_finite():
				return "Выберите сухое место под фасадом."
			node = Plot.make_cornice(first, ground, _plot_plane_y(props), map.imported_tile_size)
			if node == null:
				return "Длина карниза должна быть от 1 до 48 м."
			label = "Провести карниз"
		elif _plot_tool == "plot_balcony":
			for corner in Plot.strip_outline(_plot_anchor, point, _plot_balcony_depth):
				if not bounds.has_point(inverse * corner):
					return "Балкон должен целиком поместиться на участке."
			var first := _plot_ground(_plot_anchor, props)
			if not first.is_finite() or not _plot_balcony_wall(props, first, ground):
				return "Отметьте концы вдоль стены выбранного этажа."
			node = Plot.make_balcony(_plot_anchor, point, _plot_balcony_depth, _plot_balcony_columns,
				_plot_ground.bind(props), _plot_level_y(props), map.imported_tile_size)
			if node == null:
				return "Ширина балкона от 2,5 до 18 м. Под колоннами нужна сухая опора."
			label = "Поставить балкон"
		elif _plot_tool == "plot_railing":
			if _plot_anchor.distance_to(point) < 0.5 or _plot_anchor.distance_to(point) > Plot.MAX_FENCE_M:
				return "Длина перил от 0,5 до 48 м."
			var first := _plot_ground(_plot_anchor, props)
			if not first.is_finite() or not _plot_floor_supports_segment(props, first, ground):
				return "Вся линия перил должна идти по перекрытию выбранного этажа."
			node = Plot.make_railing(first, ground, _plot_level_y(props), map.imported_tile_size, _plot_railing_style)
			if node == null:
				return "Не удалось поставить перила на эту линию."
			label = "Поставить перила"
		elif _plot_tool == "plot_roof":
			var first_point := inverse * _plot_anchor
			var last_point := inverse * point
			var size := (first_point - last_point).abs()
			var outline := Plot.roof_outline(size, _plot_roof_options.bay)
			outline.position += first_point.min(last_point)
			if not bounds.encloses(outline):
				return "Крыша со свесом должна поместиться на участке."
			var first := _plot_ground(_plot_anchor, props)
			if not first.is_finite():
				return "Под первым углом нужна сухая земля."
			node = Plot.make_roof(size, _plot_roof_options.shape, _plot_roof_options.height, _plot_roof_options.color, map.imported_tile_size, _plot_roof_options.bay)
			if node == null:
				return "Стороны крыши от 2 до 48 м. Для выступа нужен скат и запас 1 м с каждой стороны."
			var pose := _plot_frame_pose(frame, props)
			var reverse := pose.affine_inverse()
			var a := reverse * first
			var b := reverse * ground
			node.position = Vector3(minf(a.x, b.x), _plot_plane_y(props), minf(a.z, b.z))
			node.transform = pose * node.transform
			label = "Поставить крышу"
		else:
			var points := Plot.fence_points(_plot_anchor, point)
			if points.is_empty():
				return "Длина ограды с проходом должна быть от 3,5 до 48 м."
			node = Plot.make_fence(points, _plot_ground.bind(props), map.imported_tile_size)
			if node == null:
				return "Проведите ограду по сухой земле без резких перепадов."
			label = "Провести ограду с проходом"
	else:
		return "Выберите инструмент строительства."
	node.set_meta(Plot.META, _plan_selected_id)
	if _plot_tool in ["plot_wall", "plot_arc_wall", "plot_floor", "plot_column", "plot_cornice", "plot_roof", "plot_balcony", "plot_railing"]:
		node.set_meta(Plot.LEVEL_META, 0 if _plot_arc_walk else _plot_level)
	_commit_plot_node(props, node, label)
	_reset_plot_tool()
	return "Готово · Ctrl+Z отменяет · Ctrl+S сохраняет."


func _plot_wall_neighbors(props: Node3D) -> Array[Node3D]:
	var neighbors: Array[Node3D] = []
	for other in props.get_children():
		if other is Node3D and other.has_node("Wall") and not other.has_node("Railing") and other.get_meta(Plot.META, "") == _plan_selected_id and int(other.get_meta(Plot.LEVEL_META, 0)) == _plot_level:
			neighbors.append(other)
	return neighbors


func _plot_available_docks() -> Array[Dictionary]:
	var props := map.get_node_or_null("Props") as Node3D
	var projection: Node3D = map._visual_surface_projection
	var docks: Array[Dictionary] = []
	if props == null or not is_instance_valid(projection):
		return docks
	var occupied := PackedVector3Array()
	var towers: Array[Node3D] = []
	var tile := map.imported_tile_size
	for piece in props.get_children():
		if piece is not Node3D or piece.get_meta(Plot.META, "") != _plan_selected_id:
			continue
		if piece.has_meta(Plot.TOWER_PORTS_META):
			towers.append(piece)
		elif piece.has_meta(Plot.DOCKED_WALK_META):
			var mesh := piece.get_node("Wall/ArcSurface") as MeshInstance3D
			var deck_y: float = piece.position.y + mesh.get_aabb().end.y
			var ends := Plot.wall_ends(piece)
			for index in [0, 2]:
				var point := _plot_local_grid(projection, piece.to_global(ends[index]))
				occupied.append(Vector3(point.x, deck_y, point.y))
	for tower in towers:
		var corners := Plot.tower_faces(tower)
		var deck_y := tower.position.y + Plot.FLOOR_TOP_M * tile
		var width := float(tower.get_meta(Plot.WALK_WIDTH_META, Plot.ARC_WALK_WIDTH_M))
		for side in 4:
			if not (int(tower.get_meta(Plot.TOWER_PORTS_META)) & (1 << side)):
				continue
			var a := corners[side]
			var b := corners[(side + 1) % 4]
			var center := (a + b) * 0.5
			var tangent := a.direction_to(b)
			var point := _plot_local_grid(projection, tower.to_global(Vector3(center.x, 0, center.y)))
			var taken := false
			for used in occupied:
				if Vector2(used.x, used.z).distance_to(point) < 0.01 and absf(used.y - deck_y) <= 0.003 * tile:
					taken = true
					break
			if taken:
				continue
			var outside := tower.to_global(Vector3(center.x - tangent.y, 0, center.y + tangent.x))
			docks.append({"tower": tower, "point": point, "y": deck_y, "width": width,
				"direction": (_plot_local_grid(projection, outside) - point).normalized()})
	return docks


func _plot_local_grid(projection: Node3D, world: Vector3) -> Vector2:
	var local := projection.to_local(world)
	return Vector2(local.x, local.z) / 16.0


func _selected_plot_frame() -> Transform2D:
	var plan: Resource = TerrainPlan.read(map)
	var index: int = plan.index_of(_plan_selected_id) if plan != null else -1
	return TerrainPlan.Influence.plot_frame(plan.regions[index]) if index >= 0 else Transform2D.IDENTITY


func _plot_frame_pose(frame: Transform2D, props: Node3D) -> Transform3D:
	if frame == Transform2D.IDENTITY:
		return Transform3D.IDENTITY
	var origin := props.to_local(_plot_grid_world(map._visual_surface_projection, props, frame.origin, 0.0))
	return Transform3D(Basis(Vector3.UP, -frame.get_rotation()), origin)


func _plot_frame_ground(point: Vector2, frame: Transform2D, inverse: Transform3D, props: Node3D) -> Vector3:
	var ground := _plot_ground(frame * point, props)
	return inverse * ground if ground.is_finite() else Vector3.INF


func _plot_dock_at(point: Vector2) -> Dictionary:
	if _plot_hover_dock.get("point", Vector2.INF) == point and point.is_finite():
		return _plot_hover_dock
	return {}


func _plot_dock_under_pointer(pixel: Vector2, props: Node3D) -> Dictionary:
	var nearest := {}
	var limit := 16.0 * 16.0
	for dock in _plot_docks:
		if not is_instance_valid(dock.tower) or dock.tower.get_parent() == null or dock.tower == _plot_start_dock.get("tower"):
			continue
		var distance := pixel.distance_squared_to(_plot_dock_pixel(dock, props))
		if distance < limit:
			limit = distance
			nearest = dock
	return nearest


func _plot_dock_pixel(dock: Dictionary, props: Node3D) -> Vector2:
	var world := _plot_grid_world(map._visual_surface_projection, props, dock.point, dock.y)
	return Vector2.INF if camera.is_position_behind(world) else camera.unproject_position(world)


func _plot_docks_match(dock: Dictionary) -> bool:
	return is_equal_approx(dock.width, _plot_start_dock.width) and absf(dock.y - _plot_start_dock.y) < 0.01


func _plot_arc_layout(point: Vector2) -> Dictionary:
	if _plot_docking:
		var dock := _plot_dock_at(point)
		if dock.is_empty() or _plot_start_dock.is_empty() or not _plot_docks_match(dock):
			return {}
		return Plot.docked_wall_arc(_plot_anchor, _plot_arc_through, dock.point, _plot_start_dock.direction, dock.direction, dock.width)
	var width := _plot_walk_width if _plot_arc_walk else _plot_wall_depth
	return Plot.wall_arc(_plot_anchor, _plot_arc_through, point, width)


func _plot_corner_layout(props: Node3D, point: Vector2, bounds: Rect2, inverse := Transform2D.IDENTITY) -> Dictionary:
	if not point.is_finite() or not bounds.has_point(inverse * point):
		return {}
	var projection: Node3D = map._visual_surface_projection
	if not is_instance_valid(projection):
		return {}
	var walls := []
	var corner := Vector2.INF
	var nearest := 0.45 * 0.45
	for wall in _plot_wall_neighbors(props):
		var ends := Plot.wall_ends(wall)
		if ends.is_empty():
			continue
		var points := PackedVector2Array()
		for index in [0, 2]:
			var local := projection.to_local(wall.to_global(ends[index]))
			var grid := Vector2(local.x, local.z) / 16.0
			points.append(grid)
			var distance := point.distance_squared_to(grid)
			if distance < nearest:
				nearest = distance
				corner = grid
		walls.append({"wall": wall, "points": points})
	if not corner.is_finite():
		return {}
	var sides := []
	for piece in walls:
		var wall: Node3D = piece.wall
		var points: PackedVector2Array = piece.points
		var curved := wall.has_meta(Plot.ARC_ENDS_META)
		var at_start := points[0].distance_to(corner) < 0.001
		var at_end := points[1].distance_to(corner) < 0.001
		if not at_start and not at_end:
			if not curved and Geometry2D.get_closest_point_to_segment(corner, points[0], points[1]).distance_to(corner) < 0.001:
				return {"error": "На развилке можно скруглить угол только после разделения стен."}
			continue
		if curved or not wall.has_node("Wall/Plaster") or not wall.has_node("Wall/PlasterShape"):
			return {"error": "Нужен стык двух прямых глухих стен."}
		sides.append({"wall": wall, "at_start": at_start, "far": points[1 if at_start else 0]})
	if sides.size() != 2:
		return {"error": "Нужен стык ровно двух стен без развилки."}
	var a: Vector2 = sides[0].far - corner
	var b: Vector2 = sides[1].far - corner
	if absf(a.normalized().cross(b.normalized())) < 0.01:
		return {"error": "Выберите стык, на котором стены меняют направление."}
	var depth := Plot.wall_depth(sides[0].wall)
	if not is_equal_approx(depth, Plot.wall_depth(sides[1].wall)):
		return {"error": "Для скругления выберите две стены одинаковой толщины."}
	var arc := Plot.rounded_wall_corner(sides[0].far, corner, sides[1].far, _plan_panel._buttons.plot_round_radius.value, depth)
	if arc.is_empty():
		return {"error": "Уменьшите радиус или выберите угол с более длинными стенами."}
	var floor_y: float = sides[0].wall.position.y
	var tolerance := map.imported_tile_size * 0.125
	if not is_equal_approx(floor_y, sides[1].wall.position.y):
		return {"error": "Стены должны стоять на одной высоте."}
	for edge: PackedVector2Array in [arc.left, arc.right]:
		for sample in edge:
			if not bounds.has_point(inverse * sample):
				return {"error": "Скругление должно целиком лежать внутри участка."}
			var ground := _plot_ground(sample, props)
			if not ground.is_finite() or (_plot_level == 0 and absf(ground.y - floor_y) > tolerance):
				return {"error": "Для скругления нужна сухая ровная земля."}
	return {"arc": arc, "sides": sides, "floor_y": floor_y, "corner": corner}


func _round_plot_corner(props: Node3D, point: Vector2, bounds: Rect2, inverse: Transform2D) -> String:
	var layout := _plot_corner_layout(props, point, bounds, inverse)
	if not layout.has("arc"):
		return layout.get("error", "Щёлкните по общему концу двух глухих стен.")
	var tile := map.imported_tile_size
	var curve := Plot.make_arc_wall(layout.arc, _plot_ground.bind(props), tile, layout.floor_y, _plot_level == 0, [], Color.WHITE, 0)
	if curve == null:
		return "Не удалось построить дугу на выбранном этаже."
	var original: Array[Node3D] = []
	var replacement: Array[Node3D] = []
	for side in layout.sides:
		original.append(side.wall)
		replacement.append(Plot.shorten_solid_wall(side.wall, side.at_start, layout.arc.cut * tile, tile))
	var wall_face := original[0].get_node("Wall/Plaster") as MeshInstance3D
	var curved_face := curve.get_node("Wall/ArcSurface") as MeshInstance3D
	curved_face.mesh.surface_set_material(0, wall_face.get_active_material(0))
	curve.set_meta(Plot.META, _plan_selected_id)
	curve.set_meta(Plot.LEVEL_META, _plot_level)
	replacement.append(curve)
	_commit_plot_nodes(props, replacement, "Скруглить угол стены", original)
	_reset_plot_tool()
	return "Угол скруглён · Ctrl+Z отменяет · Ctrl+S сохраняет."


func _plot_floor_supports_segment(props: Node3D, first: Vector3, last: Vector3) -> bool:
	var spans: Array[Vector2] = []
	var level_y := _plot_level_y(props)
	var tolerance := 0.001 * map.imported_tile_size
	for piece in props.get_children():
		if not piece is Node3D or piece.get_meta(Plot.META, "") != _plan_selected_id or int(piece.get_meta(Plot.LEVEL_META, 0)) != _plot_level:
			continue
		if absf(piece.position.y - level_y) > tolerance:
			continue
		if piece.has_meta(Plot.CONTOUR_FLOOR_META):
			var inverse: Transform3D = piece.transform.affine_inverse()
			var from := inverse * first / map.imported_tile_size
			var to := inverse * last / map.imported_tile_size
			var radial := Plot.contour_floor_span(piece.get_meta(Plot.CONTOUR_FLOOR_META), Vector2(from.x, from.z), Vector2(to.x, to.z))
			if radial.x <= radial.y:
				spans.append(radial)
			continue
		var slab := piece.get_node_or_null("Slab/FloorShape") as CollisionShape3D
		if slab == null or not slab.shape is BoxShape3D:
			continue
		var inverse: Transform3D = (piece.transform * slab.transform).affine_inverse()
		var start := inverse * first
		var delta := inverse.basis * (last - first)
		var half := (slab.shape as BoxShape3D).size * 0.5 + Vector3.ONE * tolerance
		var span := Vector2(0, 1)
		for axis in [Vector3.AXIS_X, Vector3.AXIS_Z]:
			if is_zero_approx(delta[axis]):
				if absf(start[axis]) > half[axis]:
					span = Vector2(1, 0)
					break
				continue
			var enter: float = (-half[axis] - start[axis]) / delta[axis]
			var leave: float = (half[axis] - start[axis]) / delta[axis]
			span.x = maxf(span.x, minf(enter, leave))
			span.y = minf(span.y, maxf(enter, leave))
		if span.x <= span.y:
			spans.append(span)
	spans.sort()
	var covered := 0.0
	for span in spans:
		if span.x > covered:
			break
		covered = maxf(covered, span.y)
	return covered >= 1.0


func _plot_contour_target(props: Node3D, point: Vector2, roof: bool) -> Dictionary:
	var projection: Node3D = map._visual_surface_projection
	var target := {}
	var nearest := INF
	for piece in props.get_children():
		if piece is not Node3D or not piece.has_meta(Plot.CONTOUR_FLOOR_META) or piece.get_meta(Plot.META, "") != _plan_selected_id \
				or int(piece.get_meta(Plot.LEVEL_META, 0)) != _plot_level:
			continue
		var profile: Dictionary = piece.get_meta(Plot.CONTOUR_FLOOR_META)
		if not roof and (profile.has("points") or profile.half):
			continue
		var center := _plot_local_grid(projection, piece.global_position)
		var offset := point - center
		var distance := offset.length() if roof else absf(offset.length() - profile.radius)
		var inside: bool = Plot.contour_floor_span(profile, offset, offset).x == 0 if roof else distance <= 0.65
		if inside and distance < nearest:
			target = {"floor": piece, "profile": profile, "center": center}
			nearest = distance
	return target


func _plot_contour_layout(point: Vector2) -> Dictionary:
	if _plot_floor_shape == "chamfer":
		var frame := _selected_plot_frame()
		var profile := Plot.chamfer_profile(frame.affine_inverse().basis_xform(point - _plot_anchor).abs(), _plot_corner_cuts)
		if profile.has("points"):
			frame.origin = Vector2.ZERO
			profile.points = frame * profile.points
		return {"center": (_plot_anchor + point) * 0.5, "profile": profile}
	return {"center": _plot_anchor, "profile": Plot.round_profile(_plot_anchor, point, _plot_floor_shape == "half")}


func _plot_outline_fits(bounds: Rect2, center: Vector2, outline: PackedVector2Array, inverse := Transform2D.IDENTITY) -> bool:
	for offset in outline:
		if not bounds.has_point(inverse * (center + offset)):
			return false
	return true


func _plot_balcony_wall(props: Node3D, first: Vector3, last: Vector3) -> bool:
	var start := Vector2(first.x, first.z)
	var delta := Vector2(last.x, last.z) - start
	if delta.is_zero_approx():
		return false
	var direction := delta.normalized()
	var tolerance := map.imported_tile_size * 0.01
	var runs := PackedVector2Array()
	for node in props.get_children():
		if node is not Node3D or node.get_meta(Plot.META, "") != _plan_selected_id or int(node.get_meta(Plot.LEVEL_META, 0)) != _plot_level:
			continue
		var span := Plot.wall_end(node)
		if span <= 0.0:
			continue
		var end: Vector3 = node.transform * Vector3(span, 0, 0)
		var a := Vector2(node.position.x, node.position.z) - start
		var b := Vector2(end.x, end.z) - start
		if maxf(absf(a.cross(direction)), absf(b.cross(direction))) <= tolerance:
			runs.append(Vector2(minf(a.dot(direction), b.dot(direction)), maxf(a.dot(direction), b.dot(direction))))
	runs.sort()
	var covered := 0.0
	for run in runs:
		if run.x > covered + tolerance:
			break
		covered = maxf(covered, run.y)
	return covered >= delta.length() - tolerance


func _edit_plot_roof(name: String, apply: bool) -> String:
	_plan_panel._buttons.plot_roof_apply.disabled = true
	if name.is_empty():
		return "Выберите крышу участка."
	var props := map.get_node_or_null("Props") as Node3D
	var original := props.get_node_or_null(NodePath(name)) as Node3D if props != null else null
	if original == null or not original.has_meta(Plot.ROOF_META) or original.get_meta(Plot.META, "") != _plan_selected_id:
		return "Крыша больше не доступна."
	_plan_panel._buttons.plot_roof_apply.disabled = false
	var before: Dictionary = original.get_meta(Plot.ROOF_META)
	if not apply:
		_plan_panel.set_roof_options(before)
		return "Измените высоту или цвет крыши по контуру." if before.has("round") else "Измените форму, высоту или цвет выбранной крыши."
	var after: Dictionary = _plan_panel.roof_options()
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	var origin := _plot_local_grid(projection, original.global_position)
	var plan: Resource = TerrainPlan.read(map)
	var region: Dictionary = plan.regions[plan.index_of(_plan_selected_id)]
	var bounds := TerrainPlan.Influence.plot_rect(region)
	var inverse := TerrainPlan.Influence.plot_frame(region).affine_inverse()
	var replacement: Node3D
	if before.has("round"):
		if before.height == after.height and before.color == after.color:
			return "Параметры крыши уже совпадают."
		if not _plot_outline_fits(bounds, origin, Plot.contour_roof_outline(before.round), inverse):
			return "Крыша со свесом должна поместиться на участке."
		replacement = Plot.make_contour_roof(before.round, after.height, after.color, map.imported_tile_size)
	else:
		if before == after.merged({"size": before.size}):
			return "Параметры крыши уже совпадают."
		var footprint := Plot.roof_outline(before.size, after.bay)
		footprint.position += inverse * origin
		if not bounds.encloses(footprint):
			return "Крыша со свесом должна поместиться на участке."
		replacement = Plot.make_roof(before.size, after.shape, after.height, after.color, map.imported_tile_size, after.bay)
	if replacement == null:
		return "Для выступа нужен скат, высота от 0,75 м и запас 1 м с каждой стороны."
	Plot.copy_piece_finish(original, replacement, Plot.FINISH_SURFACE)
	Plot.copy_piece_finish(original, replacement, Plot.FINISH_FRAME)
	replacement.name = original.name
	replacement.transform = original.transform
	replacement.set_meta(Plot.META, _plan_selected_id)
	replacement.set_meta(Plot.LEVEL_META, original.get_meta(Plot.LEVEL_META, 0))
	_commit_plot_node(props, replacement, "Изменить крышу", original)
	return "Крыша обновлена · Ctrl+Z отменяет · Ctrl+S сохраняет."


func _plot_window_wall() -> Node3D:
	if _plot_window_name.is_empty() or not is_instance_valid(map):
		return null
	var wall := map.get_node_or_null(NodePath("Props/" + _plot_window_name)) as Node3D
	if wall == null or wall.get_meta(Plot.META, "") != _plan_selected_id or Plot.placed_opening_kind(wall) == Plot.WALL_SOLID:
		return null
	return wall


func _refresh_plot_window() -> void:
	var wall := _plot_window_wall()
	if wall == null:
		_plot_window_name = ""
		_plan_panel.show_window({}, {}, 0.0)
		return
	var tile := map.imported_tile_size
	_plan_panel.show_window(Plot.placed_opening_options(wall, tile), Plot.window_wall_finish(wall), Plot.wall_end(wall) / tile)


func _plot_opening_error(options: Dictionary) -> String:
	if options.get("double_leaf", false) and float(options.width) < Plot.DOUBLE_DOOR_MIN_WIDTH:
		return "Для двух створок нужна ширина проёма от 1,5 м."
	return "Верх проёма должен быть не выше 2,875 м."


func _apply_plot_window() -> String:
	var wall := _plot_window_wall()
	if wall == null:
		return "Выберите окно или дверь участка."
	var tile := map.imported_tile_size
	var kind := Plot.placed_opening_kind(wall)
	var options: Dictionary = _plan_panel.opening_options(kind)
	if options.is_empty() or _plan_panel._buttons.wall_opening.selected != kind:
		return "Включите «Настроить проём»."
	if not Plot.opening_fits(options):
		return _plot_opening_error(options)
	options.center = _plan_panel._buttons.window_center.value if kind == Plot.WALL_WINDOW else Plot.placed_opening_options(wall, tile).center
	var half := float(options.width) * 0.5 * tile
	var center := float(options.center) * tile
	var props := wall.get_parent() as Node3D
	var inverse := wall.transform.affine_inverse()
	for node in props.get_children():
		if node is Node3D and node.has_node("Pilaster"):
			var local: Vector3 = inverse * node.position
			if absf(local.y) < 0.01 and is_equal_approx(absf(local.z), tile * Plot.WALL_DEPTH_M * 0.5):
				if absf(center - local.x) < half + tile * Plot.PILASTER_HALF_WIDTH:
					return "Проём пересекает пилястру."
	var next := Plot.remake_opening_wall(wall, options, _plan_panel._buttons.wall_color.color, _plan_panel._buttons.wall_finish.selected, tile)
	if next == null:
		return "Оставьте по 0,25 м стены по краям проёма."
	_commit_plot_node(props, next, "Изменить проём и стену", wall)
	return "Проём обновлён · Ctrl+Z отменяет · Ctrl+S сохраняет."


func _plot_finish_piece() -> Node3D:
	if _plot_finish_name.is_empty() or not is_instance_valid(map):
		return null
	var piece := map.get_node_or_null(NodePath("Props/" + _plot_finish_name)) as Node3D
	if piece == null or piece.get_meta(Plot.META, "") != _plan_selected_id:
		return null
	return piece


func _refresh_plot_finish() -> void:
	var piece := _plot_finish_piece()
	if piece == null:
		_plot_finish_name = ""
		_plan_panel.show_piece_finish("", {})
		return
	var title := Plot.finish_title(piece, _plot_finish_group)
	_plan_panel.show_piece_finish("%s · %s" % [title, piece.name], Plot.piece_finish(piece, map.imported_tile_size, _plot_finish_group))


func _apply_plot_finish(reset: bool) -> String:
	var piece := _plot_finish_piece()
	if piece == null or Plot.finish_parts(piece, _plot_finish_group).is_empty():
		return "Выберите деталь для отделки."
	var material: StandardMaterial3D
	var tile := map.imported_tile_size
	if not reset:
		var buttons: Dictionary = _plan_panel._buttons
		material = Plot.wall_finish(buttons.finish_color.color, buttons.finish_texture.selected, tile)
		if material.albedo_texture != null:
			material.uv1_scale *= buttons.finish_scale.value
	var replacement := piece.duplicate() as Node3D
	Plot.set_piece_finish(replacement, material, _plot_finish_group)
	_commit_plot_node(piece.get_parent() as Node3D, replacement, "Изменить отделку", piece)
	return "Исходная отделка восстановлена." if reset else "Отделка обновлена · Ctrl+Z отменяет · Ctrl+S сохраняет."


func _commit_plot_node(props: Node3D, node: Node3D, label: String, previous: Node3D = null) -> void:
	var removed: Array[Node3D] = []
	if previous != null:
		removed.append(previous)
	_commit_plot_nodes(props, [node], label, removed)


func _commit_plot_nodes(props: Node3D, added: Array[Node3D], label: String, removed: Array[Node3D]) -> void:
	var history: Object = sessions.undo
	if history is EditorUndoRedoManager:
		history.create_action(label, UndoRedo.MERGE_DISABLE, scene)
		history.add_do_method(self, "_swap_plot_nodes", scene, props, removed, added)
		history.add_undo_method(self, "_swap_plot_nodes", scene, props, added, removed)
	else:
		history.create_action(label)
		history.add_do_method(_swap_plot_nodes.bind(scene, props, removed, added))
		history.add_undo_method(_swap_plot_nodes.bind(scene, props, added, removed))
	for node in added:
		history.add_do_reference(node)
	for node in removed:
		history.add_undo_reference(node)
	history.commit_action()


func _swap_plot_nodes(root: Node, props: Node, removed: Array[Node3D], added: Array[Node3D]) -> void:
	for node in removed:
		if node.get_parent() == props:
			props.remove_child(node)
	for node in added:
		if node.get_parent() != props:
			Plot.attach(root, props, node)
	sessions.changed.emit()

func _plan_path_kind() -> String:
	if _plan_selection == "add_coast":return "coast"
	if _plan_selection in ["add_road","add_surface_road","add_road_branch","extend_road_branch"]: return "road"
	if _plan_selection == "add_river": return "river"
	var plan: Resource = TerrainPlan.read(map)
	var index: int = plan.index_of(_plan_selected_id) if plan != null else -1
	return plan.regions[index].get("kind","") if index >= 0 else ""

func _plan_path_bounds(region: Dictionary, parameters: Dictionary, extent: Vector2i) -> Rect2i:
	if region.kind=="coast":return TerrainPlan.Influence.coast_bounds(region.points_m,parameters,extent)
	return TerrainPlan.Influence.path_bounds(region.points_m,parameters.width_m,parameters.edge_m if region.kind == "road" else parameters.shore_m,extent)

func _finish_plan_path() -> void:
	if _plan_selection == "extend_road_branch":
		var error := _stage_branch_points(_path_points)
		if not error.is_empty():
			_plan_panel.set_status(error)
			return
		_plan_point_index = _path_points.size() - 1
		_plan_panel.set_point_selection(_plan_point_index, _path_points.size())
		_plan_selection = ""
		selecting = false
		_path_points.clear()
		_path_hover = Vector2(-1,-1)
		_plan_panel.set_status("Продолжение в черновике. Можно править точки или открыть предпросмотр.")
		return
	if not _surface_road_preview.is_empty():
		_apply_surface_road_preview()
		return
	var extent := Vector2i(entry.resource.width/16,entry.resource.depth/16)
	var error := TerrainPlan.Influence.path_error(_path_points,extent)
	if not error.is_empty(): _plan_panel.set_status(error); return
	var original: Resource = TerrainPlan.read(map)
	var plan: Resource = original.working_copy() if original != null else TerrainPlan.new()
	plan.upgrade_local_layers()
	var index: int = plan.index_of(_plan_selected_id)
	var kind := _plan_path_kind()
	if _plan_selection in ["add_river","add_road","add_surface_road","add_road_branch","add_coast"]:
		var new_id := "%s_%s_%s" % [kind,OS.get_process_id(),Time.get_ticks_usec()]
		plan.regions.append({"id":new_id,"name":("Море %d" if kind=="coast" else "Дорога %d" if kind == "road" else "Река %d") % (plan.regions.size()+1),"kind":kind,"enabled":true,"parameters":(TerrainPlan.Influence.COAST_DEFAULTS if kind=="coast" else TerrainPlan.Influence.ROAD_DEFAULTS if kind == "road" else TerrainPlan.Influence.RIVER_DEFAULTS).duplicate()})
		index = plan.regions.size()-1
		plan.regions[index].parameters.terrain_sampling="fine16"
		if _plan_selection == "add_road_branch":
			var host_index: int = original.index_of(_road_join.get("host", ""))
			if host_index < 0:
				_plan_panel.set_status("Сначала выберите точку на главной дороге.")
				return
			var host: Dictionary = original.regions[host_index]
			var direction_error := _branch_direction_error(host, _road_join.fraction, _path_points)
			if not direction_error.is_empty():
				_plan_panel.set_status(direction_error)
				return
			plan.regions[index].road_join = _road_join.duplicate()
			plan.regions[index].name = "Ответвление · " + host.name.left(100)
			plan.regions[index].parameters = host.parameters.duplicate(true)
			plan.regions[index].parameters.width_m = minf(3.0, host.parameters.width_m)
			plan.regions[index].parameters.terrain_sampling = "fine16"
		if kind=="coast":
			plan.regions[index].parameters.water_m=TerrainPlan.Influence.existing_water_level_m(entry.resource)
		if _plan_selection == "add_surface_road":
			if _surface_road_support.is_empty():
				_plan_panel.set_status("Сначала выберите объёмный уступ.")
				return
			plan.regions[index].support_placement_id = _surface_road_support
			plan.regions[index].parameters.width_m = 2.0
			plan.regions[index].parameters.surface = "paving"
	if index < 0: return
	if plan.regions[index].get("points_m") != _path_points:
		plan.regions[index].erase("bridge_over_gap")
		plan.regions[index].erase("bridge_rise_m")
		plan.regions[index].erase("bridge_supports")
		plan.regions[index].erase("bridge_plank_roughness")
		plan.regions[index].erase("bridge_railing")
	plan.regions[index].points_m = _path_points.duplicate()
	plan.regions[index].bounds = _plan_path_bounds(plan.regions[index],plan.regions[index].parameters,extent)
	if _plan_selection == "add_road_branch":
		_preview_road_branch(plan, plan.regions[index], original)
		return
	if plan.regions[index].has("support_placement_id") and plan.regions[index].get("enabled", true):
		_preview_surface_road(plan, plan.regions[index], original)
		return
	_plan_selected_id = plan.regions[index].id
	error = commit_terrain_plan(map,plan)
	if not error.is_empty(): _plan_panel.set_status(error); return
	_plan_selection = ""; selecting = false; _path_points = PackedVector2Array(); _path_hover = Vector2(-1,-1)
	_refresh_terrain_plan(true)
	_plan_panel.set_status("Линия сохранена в плане. Откройте параметры, затем предпросмотр и применение. Земля пока не изменена.")


func _preview_road_branch(plan: Resource, branch: Dictionary, original: Resource) -> void:
	_ensure_generation_panel()
	_plan_selection = ""
	selecting = false
	_path_points.clear()
	_road_join.clear()
	_branch_edit.clear()
	_plan_panel.hide()
	_generation_context = {"target": weakref(map), "area": branch.bounds, "composition": true,
		"plan_version": original.data(), "input_plan": plan, "branch_id": branch.id}
	_generation_panel.open_road_branch(branch.bounds, branch.parameters)
	_prepare_terrain_generation(branch.parameters)


func _branch_direction_error(host: Dictionary, fraction: float, points: PackedVector2Array) -> String:
	var axis := TerrainPlan.Influence.path_curve(host.points_m)
	var station := axis.get_baked_length() * fraction
	var tangent := axis.sample_baked(station - 0.25).direction_to(axis.sample_baked(station + 0.25))
	if absf(tangent.dot(points[0].direction_to(points[1]))) > 0.75 or points[-1].distance_to(axis.get_closest_point(points[-1])) <= float(host.parameters.width_m) * 0.5 + 0.5:
		return "Выведите ответвление в сторону от главной дороги."
	return ""


func _stage_branch_points(points: PackedVector2Array) -> String:
	var plan: Resource = TerrainPlan.read(map)
	var index: int = plan.index_of(_plan_selected_id) if plan != null else -1
	if index < 0 or not plan.regions[index].has("road_join"):
		return "Выберите ответвление."
	if not _branch_edit.is_empty() and plan.data() != _branch_edit.version:
		return "План изменился. Отмените черновик и повторите правку."
	var branch: Dictionary = plan.regions[index].duplicate(true)
	var extent := Vector2i(entry.resource.width / 16, entry.resource.depth / 16)
	var error := TerrainPlan.Influence.path_error(points, extent)
	if not error.is_empty():
		return error
	branch.points_m = points.duplicate()
	branch.points_m[0] = plan.regions[index].points_m[0]
	if branch.points_m == plan.regions[index].points_m:
		_branch_edit.clear()
		_plan_panel.set_branch_pending(false)
		_update_overlay()
		return ""
	var host_index: int = plan.index_of(branch.road_join.host)
	if host_index < 0:
		return "Главная дорога больше недоступна."
	error = _branch_direction_error(plan.regions[host_index], branch.road_join.fraction, branch.points_m)
	if not error.is_empty():
		return error
	for point in TerrainPlan.Influence.path_curve(branch.points_m).get_baked_points():
		if not Rect2(Vector2.ZERO, Vector2(extent)).has_point(point):
			return "Изгиб линии выходит за карту."
	branch.bounds = _plan_path_bounds(branch, branch.parameters, extent)
	_branch_edit = {"region": branch, "version": plan.data()}
	_plan_panel.set_branch_pending(true)
	_update_overlay()
	return ""


func _preview_branch_edits() -> void:
	if _branch_edit.is_empty():
		return
	var original: Resource = TerrainPlan.read(map)
	if original == null or original.data() != _branch_edit.version:
		_plan_panel.set_status("План изменился. Отмените черновик и повторите правку.")
		return
	var branch: Dictionary = _branch_edit.region
	var next: Resource = original.working_copy()
	next.regions[next.index_of(branch.id)] = branch
	_preview_road_branch(next, branch, original)


func _clear_surface_road_preview() -> void:
	_surface_bridge_offer.clear()
	if is_instance_valid(_plan_panel):
		_plan_panel.set_road_profile({})
	var previous: Node3D = _surface_road_preview.get("previous")
	if is_instance_valid(previous):
		_show_surface_road_source(previous, true)
	var node: Node3D = _surface_road_preview.get("node")
	if is_instance_valid(node):
		node.free()
	_surface_road_preview.clear()


func _show_surface_road_source(node: Node3D, shown: bool) -> void:
	if node is MeshInstance3D:
		RenderingServer.instance_set_visible(node.get_instance(), shown and node.is_visible_in_tree())
	for part in node.find_children("*", "MeshInstance3D", true, false):
		RenderingServer.instance_set_visible(part.get_instance(), shown and part.is_visible_in_tree())


func _preview_surface_road(plan: Resource, region: Dictionary, original: Resource) -> void:
	_clear_surface_road_preview()
	var built := _build_surface_road(map, region)
	var profile: Dictionary = built.get("profile", {})
	var offer: bool = profile.get("spans", []).size() == 1
	if offer:
		_surface_bridge_offer = {"plan": plan, "region": region, "original": original}
	var problem: String = built.get("error", "") if region.get("bridge_over_gap", false) or not offer else ""
	_plan_panel.set_road_profile(profile, problem, offer, float(region.get("bridge_rise_m", 0.0)), region.get("bridge_supports", "none"), region.get("bridge_plank_roughness"), region.get("bridge_railing", "stone"))
	if built.has("error"):
		_plan_panel.set_status(built.error)
		return
	var support := _surface_road_prop(map, region.support_placement_id)
	var node: Node3D = built.node
	var props := map.get_node("Props")
	var previous: Node3D
	for child in props.get_children():
		if child is Node3D and child.get_meta(Plot.SURFACE_ROAD_META, "") == region.id:
			previous = child
			_show_surface_road_source(previous, false)
			break
	node.process_mode = Node.PROCESS_MODE_DISABLED
	props.add_child(node)
	_surface_road_preview = {"node": node, "plan": plan, "original": original,
		"previous": previous,
		"support": weakref(support), "signature": support.detail_surface_signature(),
		"revision": map._visual_surface_projection.column_revision(), "id": region.id}
	_plan_panel.set_status("Мост примерен. Enter — поставить · Esc — отменить." if region.get("bridge_over_gap", false) else "Опора по всей линии. Enter — применить · Esc — отменить.")


func _apply_surface_road_preview() -> void:
	var draft := _surface_road_preview.duplicate()
	var support: EmberVoxelProp = draft.support.get_ref()
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	if support == null or not is_instance_valid(projection) or _surface_road_prop(map, support.placement_id) != support or support.detail_surface_signature() != draft.signature or projection.column_revision() != draft.revision or not TerrainPlan.same(TerrainPlan.read(map), draft.original):
		_clear_surface_road_preview()
		_plan_panel.set_status("Земля или уступ изменились. Enter обновит примерку.")
		return
	var node: Node3D = draft.node
	node.get_parent().remove_child(node)
	node.name = "SurfaceRoad"
	node.process_mode = Node.PROCESS_MODE_INHERIT
	var bridge := node.has_node("StreetBridge")
	_surface_road_preview.erase("node")
	_clear_surface_road_preview()
	var error := commit_terrain_plan(map, draft.plan, node)
	if not error.is_empty():
		node.free()
		_plan_panel.set_status(error)
		return
	_plan_selected_id = draft.id
	_plan_selection = ""
	selecting = false
	_path_points.clear()
	_refresh_terrain_plan(true)
	_plan_panel.set_status(("Мост и подходы поставлены" if bridge else "Дорога по уступу поставлена") + " · Ctrl+Z отменяет · Ctrl+S сохраняет.")

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
	if parameters.has("terrain_operation") or parameters.has("terrain_sampling") or parameters.has("mountain_shape") or parameters.get("land_shape","island")=="mainland":plan.upgrade_local_layers()
	if plan.regions[index].get("kind") == "grove" and parameters.has("clearance_m"): plan.regions[index].kind = "placement"
	if plan.regions[index].get("kind") in ["river","road","coast"]:
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
	for control in [surface_plane_mode,target_choice,category,tools,palette,sand_palette,surface_role_choice,material_variant_choice,material_slot_button,material_pattern_button,clip,shore_direction,compact_direction,compact_detail_pattern,compact_shape_action,compact_shape_radius,compact_level_from_point,terrain_edit_scale,terrain_height_step,brush_shape]:
		if is_instance_valid(control): control.disabled = value
	for control in [surface_plane_offset,radius,depth,coarse_depth,plane_height,water_height,shore_width,softness,compact_feature_scale,compact_detail,compact_seed]:
		if is_instance_valid(control): control.editable = not value
	for button in _target_buttons:
		if is_instance_valid(button): button.disabled = value
	for i in _tool_buttons.size():
		_tool_buttons[i].disabled=value or tools.is_item_disabled(i)
	for button in category_buttons:
		if is_instance_valid(button): button.disabled = value
	if is_instance_valid(compact_shape_strength):compact_shape_strength.editable=not value
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
		_generation_panel.paint_protection_requested.connect(_set_paint_protection)
	if is_instance_valid(_plan_panel) and _plan_panel.get_index()>_generation_panel.get_index():
		_terrain_workspace.move_child(_plan_panel,_generation_panel.get_index())

func _set_paint_protection(locked: bool) -> void:
	var target: EmberMapLoader=(_generation_context.target as WeakRef).get_ref() if _generation_context.get("target") is WeakRef else null
	var area: Rect2i=_generation_context.get("area",Rect2i())
	if not is_instance_valid(target) or not area.has_area() or area.size.x>32 or area.size.y>32:
		_generation_panel.set_pending("Выберите существующую область до 32×32 м.");return
	var draft: Dictionary=sessions.open_map(target,scene)
	if draft.is_empty():_generation_panel.set_pending(sessions.error);return
	if not Rect2i(0,0,draft.resource.width,draft.resource.depth).encloses(Rect2i(area.position*16,area.size*16)):
		_generation_panel.set_pending("Область выходит за границы земли.");return
	var previous: Resource=TerrainPlan.read(target)
	var next: Resource=previous.working_copy() if previous!=null else TerrainPlan.new()
	next.protect_paint_area(Rect2i(area.position*16,area.size*16),locked)
	var message:=commit_terrain_plan(target,next)
	if not message.is_empty():_generation_panel.set_pending(message);return
	if not _generation_context.get("plan_id","").is_empty():_generation_context.plan_version=next.data()
	_generation_panel.set_pending("Покраска выделения защищена. Ctrl+Z отменяет защиту; обновите предпросмотр." if locked else "Защита выделения снята. Ctrl+Z возвращает её; обновите предпросмотр.")


func _prepare_terrain_generation(parameters: Dictionary) -> void:
	if _generation_context.get("grove",false): _prepare_grove(parameters); return
	var context := {"target": _generation_context.get("target"), "area": _generation_context.get("area", Rect2i()), "addition": _generation_context.get("addition", false), "plan_id": _generation_context.get("plan_id", ""), "plan_version": _generation_context.get("plan_version", {}), "composition": _generation_context.get("composition", false)}
	if _generation_context.has("input_plan"):
		context.input_plan = _generation_context.input_plan
		context.branch_id = _generation_context.branch_id
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
		var input: Resource = context.get("input_plan", plan).working_copy()
		var selected_road := {}
		if context.has("branch_id"):
			var branch: Dictionary = input.regions[input.index_of(context.branch_id)]
			branch.parameters = parameters.duplicate(true)
			branch.bounds = _plan_path_bounds(branch, branch.parameters, Vector2i(draft.resource.width/16,draft.resource.depth/16))
			var old_index: int = plan.index_of(branch.id)
			selected_road = (plan.regions[old_index] if old_index >= 0 else branch).duplicate()
			selected_road.branch_edit = true
		if not context.plan_id.is_empty():
			var index: int = input.index_of(context.plan_id)
			if input.regions[index].get("kind") == "road":
				selected_road = input.regions[index].duplicate()
			input.regions[index].parameters = parameters.duplicate(true)
			if parameters.has("terrain_sampling") or parameters.has("mountain_shape") or parameters.get("land_shape","island")=="mainland":input.upgrade_local_layers()
			if input.regions[index].get("kind") in ["river","road","coast"]: input.regions[index].bounds = _plan_path_bounds(input.regions[index],parameters,Vector2i(draft.resource.width/16,draft.resource.depth/16))
		_generation_job = TerrainComposition.new()
		prepared = _generation_job.begin(draft.resource, input, selected_road)
	else:
		_generation_job = TerrainGeneration.new()
		prepared = _generation_job.begin(draft.resource, context.area, parameters, context.addition,TerrainPlan.read(target))
	if not prepared:
		_generation_panel.set_pending(_generation_job.error)
		_generation_job = null
		return
	_generation_context["draft"] = draft
	_generation_context["version"] = draft.resource.working_copy()
	_generation_context["layout"] = Sessions.compact_layout(target).positions
	_generation_context["terrain_operation"] = parameters.get("terrain_operation","generate")
	if parameters.get("terrain_operation","")=="coverage":
		var paint_plan: Resource=TerrainPlan.read(target)
		_generation_context.paint_plan_version=paint_plan.data() if paint_plan!=null else {}
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
	_generation_context.erase("grove_applying")
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
	_generation_context.protected_paint_columns=_generation_job.protected_paint_columns if not _generation_context.get("composition",false) else 0
	var preview_tiles: Array[Vector2i] = []
	var reuse_road_tiles := false
	if _generation_context.get("composition", false):
		reuse_road_tiles = _generation_job.local_road
		_generation_context.output_plan = _generation_job.output_plan
		_generation_context.validated_sections = _generation_job.validated_sections
		_generation_context.protected_blocks = _generation_job.protected_blocks.keys()
		var tiles := {}
		for key: Vector2i in _generation_job.changed_tiles:
			for z in range(key.y - 1, key.y + 2):
				for x in range(key.x - 1, key.x + 2):
					if not reuse_road_tiles and absi(x - key.x) + absi(z - key.y) > 1:
						continue
					if x >= 0 and z >= 0 and x * 64 < candidate.width and z * 64 < candidate.depth:
						tiles[Vector2i(x,z)] = true
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
	var prepare_water: bool = _generation_context.get("composition", false) and not _generation_context.has("branch_id")
	if not preview.show_area(target, candidate, bounds, _generation_context.selection.get("offset", Vector2i.ZERO), preview_tiles, prepare_water, reuse_road_tiles):
		preview.queue_free()
		_generation_panel.set_pending("3D-предпросмотр пока недоступен. Дождитесь открытия карты.")
		return
	_generation_preview = preview
	_generation_panel.set_pending("Строю 3D-предпросмотр…")
	preview.preview_built.connect(func():
		if _generation_preview == preview and is_instance_valid(_generation_panel):
			if _generation_context.get("composition", false):
				_generation_panel.set_ready("Предпросмотр областей готов · защищено мест: %d. Изменения применятся одной командой Undo." % _generation_context.protected_blocks.size()); _update_overlay(); return
			var operation: String=_generation_context.get("terrain_operation","generate")
			var result_text: String={"detail":"Предпросмотр фактуры готов. Покраска и вода сохраняются; применение — одна команда Undo.","coverage":"Предпросмотр покрытий готов. Форма земли и вода сохраняются; применение — одна команда Undo."}.get(operation,"Предпросмотр готов · расчёт %.0f мс. Применение заменит форму выбранной земли; отмена вернёт прежний вид."%profile_ms)
			if operation=="coverage":result_text+=" Защищено ручной покраски: %.1f м²."%(float(_generation_context.get("protected_paint_columns",0))/256.0)
			_generation_panel.set_ready("Предпросмотр готов. Добавится %d участков; прежняя земля сохранится." % _generation_context.selection.keys.size() if _generation_context.addition else result_text)
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
	var projection := target._visual_surface_projection as EmberTerrainPilotProjection if is_instance_valid(target) else null
	var prepared: Dictionary = _generation_preview.take_prepared_tiles() if is_instance_valid(projection) and is_instance_valid(_generation_preview) else {}
	clear_terrain_generation_preview()
	if not prepared.is_empty():
		projection.stage_dry_preview(context.candidate, prepared)
	var message := commit_terrain_composition(target, context) if context.get("composition", false) else commit_selected_sections(target, context) if context.get("addition", false) else commit_terrain_generation(target, context.draft, context.version, context.candidate,context.get("paint_plan_version"))
	if is_instance_valid(projection):
		projection.clear_staged_dry_preview()
	if message.is_empty():
		if context.has("branch_id"):
			_plan_selected_id = context.branch_id
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
	if _generation_context.get("grove_applying",false):
		_process_grove_publication();return
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
	var message := _grove_commit_error(target,context)
	if not message.is_empty(): _generation_panel.set_pending(message); return
	_generation_context=context
	_generation_context.grove_applying=true
	_generation_job=context.grove_prepared
	_generation_job.begin_publication(target.get_node("Props"))
	_generation_panel.set_pending("Подключаю объекты: 0 / %d · можно отменить."%_generation_job.placements.size())

func _process_grove_publication() -> void:
	var prepared:RefCounted=_generation_job
	prepared.step_publication(4000)
	if not prepared.error.is_empty():
		var message:String=prepared.error
		clear_terrain_generation_preview();_generation_panel.set_pending(message);return
	var progress:Vector2i=prepared.publication_progress()
	_generation_panel.set_pending("Подключаю объекты: %d / %d · можно отменить."%[progress.x,progress.y])
	if not prepared.publication_finished():return
	var context:=_generation_context.duplicate()
	var target:EmberMapLoader=context.target.get_ref()
	var message:=_grove_commit_error(target,context)
	if not message.is_empty():
		clear_terrain_generation_preview();_generation_panel.set_pending(message);return
	var delta:Dictionary=prepared.take_publication()
	_generation_job=null
	_generation_context.erase("grove_applying")
	message=_commit_grove_delta(target,context,delta)
	if not message.is_empty():
		clear_terrain_generation_preview();_generation_panel.set_pending(message);return
	_close_generation_panel();_status("Расстановка применена · Ctrl+Z отменяет · Ctrl+S сохраняет сцену.")

func _grove_commit_error(target: EmberMapLoader, context: Dictionary) -> String:
	if not is_instance_valid(target): return "Карта была закрыта."
	var draft: Dictionary = context.get("draft",{})
	if not sessions.entries.values().has(draft) or draft.target.get_ref() != target: return "Черновик изменился."
	var job: RefCounted = context.get("grove_prepared")
	var plan: Resource = TerrainPlan.read(target)
	if job == null or plan == null or plan.data() != context.plan_version or not draft.resource.same_terrain_data(context.version) or Sessions.compact_layout(target).positions != context.layout or job.stale():
		return "Земля, объекты или источники объектов изменились. Обновите предпросмотр."
	return ""

func commit_grove(target: EmberMapLoader, context: Dictionary) -> String:
	var message:=_grove_commit_error(target,context)
	if not message.is_empty():return message
	var job:RefCounted=context.grove_prepared
	var delta: Dictionary = job.finalize(target.get_node("Props"))
	if delta.is_empty(): return job.error
	return _commit_grove_delta(target,context,delta)

func _commit_grove_delta(target: EmberMapLoader, context: Dictionary, delta: Dictionary) -> String:
	var plan:Resource=TerrainPlan.read(target)
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
	_sync_plan_context()

func commit_terrain_generation(target: EmberMapLoader, draft: Dictionary, before_version: EmberTerrainPilotResource, candidate: EmberTerrainPilotResource,expected_paint_plan: Variant=null) -> String:
	if not is_instance_valid(target) or candidate == null: return "Карта была закрыта."
	if draft.get("target") is not WeakRef or draft.target.get_ref() != target or not sessions.entries.values().has(draft): return "Черновик карты изменился."
	var before: EmberTerrainPilotResource = draft.resource
	if not before.same_terrain_data(before_version): return "Земля изменилась после предпросмотра. Подготовьте рельеф заново."
	if expected_paint_plan!=null:
		var plan: Resource=TerrainPlan.read(target)
		if (plan.data() if plan!=null else {})!=expected_paint_plan:return "Защита покраски или план изменились. Обновите предпросмотр."
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
	_split_workspace = VBoxContainer.new(); _split_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(_split_workspace); _split_workspace.hide()
	_conversion_workspace = VBoxContainer.new(); _conversion_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(_conversion_workspace); _conversion_workspace.hide()
	_object_brush_workspace = VBoxContainer.new(); _object_brush_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_brush_workspace = VBoxContainer.new(); _detail_brush_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var detail_scroll := ScrollContainer.new(); detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; _detail_brush_workspace.add_child(detail_scroll)
	detail_scroll.add_child(plugin._detail_brush.build_panel())
	_button(plugin._detail_brush.panel,"Рисовать в 3D",func(): plugin._activate_detail_brush())
	_button(plugin._detail_brush.panel,"Закрыть кисть",func(): _panel_host.cancel_active())
	workspace.add_child(_detail_brush_workspace); _detail_brush_workspace.hide()
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
	look_panel.terrain_materials_requested.connect(_open_material_pattern)
	look_toggle.toggled.connect(func(open: bool): look_panel.visible = open; look_toggle.text = "Вид мира ▾" if open else "Вид мира ▸")
	var title := Label.new()
	title.text = "EMBER · МИР"
	box.add_child(title)
	target_choice = _choice(box,["Земля карты","Voxel-объект"])
	target_choice.tooltip_text = "Что меняет кисть: землю карты или выбранный voxel-объект. Объект редактируется как уникальный экземпляр."
	target_choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	target_choice.item_selected.connect(_target_changed)
	var target_caption:=Label.new();target_caption.text="ЦЕЛЬ РЕДАКТИРОВАНИЯ";box.add_child(target_caption)
	box.move_child(target_caption,target_choice.get_index())
	pick_target_button = _button(box,"Выбрать цель · Alt+Q",func():picking_object=not picking_object;_refresh_context_label())
	pick_target_button.toggle_mode=true
	pick_target_button.icon = _editor_icon(&"ToolSelect")
	pick_target_button.tooltip_text="Выберите землю или объект следующим щелчком. Alt+Q сразу выбирает цель под курсором; черновики сохраняются."
	_target_buttons.append(pick_target_button)
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
	material_pattern_dialog.light_profile_previewed.connect(_on_material_light_previewed)
	material_pattern_dialog.pattern_scale_previewed.connect(_on_material_scale_previewed)
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
	surface_plane_mode=_choice(advanced,["Площадка · по высоте","Поверхность · выровнять","Поверхность · срезать"])
	surface_plane_mode.select(1)
	surface_plane_mode.tooltip_text="По поверхности: направление и плоскость фиксируются при начале мазка. Срез только удаляет объём."
	surface_plane_mode.item_selected.connect(func(_index):cancel_stroke();_tool_changed())
	surface_plane_offset=_brush_spin(advanced,"surface_plane_offset")
	surface_plane_offset.value_changed.connect(func(_value):cancel_stroke())
	plane_height = _brush_spin(advanced,"plane_height")
	water_height = _brush_spin(advanced,"water_height")
	shore_width = _brush_slider(advanced,"shore_width")
	shore_direction = _brush_choice(advanced,"shore_direction")
	softness = _brush_slider(advanced,"softness")
	softness.tooltip_text="Край кисти «Тянуть»:0% — жёсткий,100% — мягкий. То же значение используется в Canvas."
	compact_level_from_point = CheckBox.new()
	compact_level_from_point.text = str(BrushParameters.definition("level_from_point").title)
	compact_level_from_point.button_pressed = true
	advanced.add_child(compact_level_from_point)
	compact_feature_scale = _brush_slider(advanced,"feature_scale")
	compact_detail_pattern = _brush_choice(settings,"detail_pattern")
	compact_detail_pattern.tooltip_text="Фактура покрытия: каменные выступы, песчаные гребни и тихие неровности грунта. Сохраняет покраску и подводное дно; PNG выбирается в прежнем материале."
	compact_detail_pattern.item_selected.connect(func(_value):cancel_stroke();_tool_changed())
	compact_shape_action=OptionButton.new();settings.add_child(compact_shape_action)
	for shape_choice in ["Править общие высоты","Гладкий вид · скруглить здесь","Гладкий вид · не скруглять","Гладкий вид · снять правило"]:compact_shape_action.add_item(shape_choice)
	compact_shape_action.item_selected.connect(func(_value):cancel_stroke();_tool_changed();_refresh_brush_scale_settings();_update_overlay())
	_shape_settings=VBoxContainer.new();settings.add_child(_shape_settings)
	var shape_title:=Label.new();shape_title.text="Округление / защита · сила";_shape_settings.add_child(shape_title)
	compact_shape_strength=HSlider.new();compact_shape_strength.max_value=1.0;compact_shape_strength.step=0.05;compact_shape_strength.value=1.0;_shape_settings.add_child(compact_shape_strength)
	compact_shape_radius=OptionButton.new();_shape_settings.add_child(compact_shape_radius)
	for value in [1,2,3]:compact_shape_radius.add_item("Радиус округления: %d клеток"%value)
	compact_shape_radius.select(2)
	compact_shape_strength.value_changed.connect(func(_value):cancel_stroke())
	compact_shape_radius.item_selected.connect(func(_value):cancel_stroke())
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
	_button(settings,"Кисть деталей · трава / камушки…",func(): if plugin != null: plugin._activate_detail_brush())
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
	_clear_shared_mask=_button(parameters,"Снять маску Canvas",func():sessions.clear_brush_mask(entry);_tool_changed())
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
	surface_plane_mode.reparent(parameters);parameters.move_child(surface_plane_mode,0)
	surface_plane_offset.get_parent().reparent(parameters)
	settings.move_child(compact_detail_pattern,2)
	settings.move_child(compact_shape_action,2)
	settings.move_child(_shape_settings,3)
	_brush_parameter_controls = {
		"surface_plane_mode":surface_plane_mode,"surface_plane_offset":surface_plane_offset.get_parent(),
		"edit_scale":terrain_edit_scale, "height_step":terrain_height_step, "shape":brush_shape,
		"radius":_parameter_group(radius), "strength_detail":_parameter_group(depth),
		"strength_steps":_parameter_group(coarse_depth), "palette":palette_row, "sand_palette":sand_palette,
		"plane_height":plane_height.get_parent(), "water_height":water_height.get_parent(),
		"shore_width":_parameter_group(shore_width), "shore_direction":shore_direction,
		"softness":_parameter_group(softness), "level_from_point":compact_level_from_point,
		"feature_scale":_parameter_group(compact_feature_scale), "detail":_parameter_group(compact_detail),
		"seed":compact_seed.get_parent(), "direction":compact_direction,"detail_pattern":compact_detail_pattern,
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
	if is_instance_valid(map):
		var anomaly := map.get_node_or_null("WorldAnomaly")
		if anomaly != null: anomaly.set_authoring_active(true)
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
	_reset_plot_tool()
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
	_plan_drag.clear();_path_points=PackedVector2Array();_plan_point_index=-1
	_plot_window_name = ""
	_plot_finish_name = ""
	_reset_plot_tool()
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
	if _changing_context:return
	var target:Node=map if index==0 else null
	if index==1 and Engine.is_editor_hint():
		var selected:=EditorInterface.get_selection().get_selected_nodes()
		if selected.size()==1:target=EmberObjectInspectorModel.voxel_owner(selected[0])
	if target==null:
		picking_object=true;_refresh_context_label();_status("Выберите землю или объект в сцене · Alt+Q под курсором")
	elif not activate_context(target):_refresh_context_label()

func _context_busy()->bool:
	if dragging or job!=null or not queue.is_empty() or not grab.is_empty() or _compact_brush.active() or not _plan_drag.is_empty() or _generation_job!=null:return true
	if plugin!=null:
		if plugin._object_brush._dragging:return true
		var workspace:=EditorInterface.get_editor_main_screen().find_child(plugin.SURFACE_WORKSPACE_NODE,true,false) as EmberVoxelSculptWorkspace
		if workspace!=null and workspace.is_visible_in_tree() and not workspace.can_switch_world_context():return true
	return false

func activate_context(target:Node,sync_selection:=true)->bool:
	if _changing_context or not is_instance_valid(scene) or not is_instance_valid(target) or (target!=scene and not scene.is_ancestor_of(target)):return false
	if target!=map and not target is EmberVoxelProp:return false
	if _context_busy() or not can_leave_panel():
		_status("Завершите текущий жест или предпросмотр перед сменой цели.");return false
	if not entry.is_empty() and entry.target.get_ref()==target:
		picking_object=false;_refresh_context_label()
		if sync_selection:_sync_context_selection(target)
		return true
	var next:Dictionary=sessions.open_map(map,scene) if target==map else sessions.open_object(target,scene)
	if next.is_empty():_status(sessions.error);return false
	var preferred:=_mode();var brush_radius:=radius.value;var group:=category.selected
	if plugin!=null:
		var workspace:=EditorInterface.get_editor_main_screen().find_child(plugin.SURFACE_WORKSPACE_NODE,true,false) as EmberVoxelSculptWorkspace
		if workspace!=null and workspace.is_visible_in_tree() and not workspace._world_entry.is_empty():
			preferred=BrushProfiles.world_mode_for_tool(workspace._selected_tool_id())
			brush_radius=float(workspace._radius.get_selected_metadata())/workspace._resource.normalized_density()
			_adopt_canvas_brush_settings(workspace)
	_changing_context=true
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
	entry=next;edit_region=entry.get("scope",Rect2i());picking_object=false;hover.clear()
	target_choice.select(1 if target is EmberVoxelProp else 0)
	actions.history_context=scene
	sessions.preview(entry)
	_attach_trace_projection()
	if _compact_active():_compact_brush.configure(entry,sessions.undo,scene)
	for i in 4:
		if preferred in BrushProfiles.world_modes(i,_compact_active()):group=i;break
	_refresh_palette();_category_changed(group,true,preferred)
	_restore_context_radius(brush_radius)
	_changing_context=false
	_refresh_context_label()
	_refresh_target_actions()
	if hide_water.button_pressed: _set_working_water(true)
	_refresh_scope()
	_refresh_experiment_gate()
	if _material_mode: _show_material_workspace()
	if sync_selection:_sync_context_selection(target)
	_update_overlay()
	return true

func _restore_context_radius(value:float)->void:
	# A target's edit stride must not quantize the physical radius of the previous target.
	var step:=radius.step;radius.step=0.0
	radius.value=clampf(value,radius.min_value,radius.max_value)
	radius.step=step

func _refresh_context_label()->void:
	if not is_instance_valid(target_choice):return
	var object:Node=entry.target.get_ref() if not entry.is_empty() else null
	target_choice.set_item_text(1,"Объект · "+str(object.name) if object is EmberVoxelProp else "Объект")
	target_choice.select(1 if object is EmberVoxelProp else 0)
	target_choice.tooltip_text="Цель: "+str(scene.get_path_to(object)) if is_instance_valid(object) and is_instance_valid(scene) else "Выберите землю или объект"
	if is_instance_valid(pick_target_button):pick_target_button.set_pressed_no_signal(picking_object)

func _sync_context_selection(target:Node)->void:
	if not Engine.is_editor_hint() or not is_instance_valid(target) or not target.is_inside_tree():return
	_changing_context=true
	var selection:=EditorInterface.get_selection();selection.clear();selection.add_node(target)
	EditorInterface.inspect_object(target)
	_changing_context=false

func context_selection_changed(selected:Array)->void:
	if not active or _changing_context or selected.size()!=1:return
	var target:=_context_target(selected[0])
	if target==null or (not entry.is_empty() and entry.target.get_ref()==target):return
	var workspace:=EditorInterface.get_editor_main_screen().find_child(plugin.SURFACE_WORKSPACE_NODE,true,false) as EmberVoxelSculptWorkspace if plugin!=null else null
	var in_canvas:=workspace!=null and workspace.is_visible_in_tree() and not workspace._world_entry.is_empty()
	if activate_context(target,false):
		if in_canvas:_open_canvas_entry(entry)
	elif not entry.is_empty():_sync_context_selection(entry.target.get_ref())

func _refresh_target_actions() -> void:
	if is_instance_valid(_generation_button): _generation_button.visible = _compact_active()
	if is_instance_valid(_plan_button): _plan_button.visible = _compact_active()
	if is_instance_valid(_workspace_terrain_button): _workspace_terrain_button.disabled = not _compact_active()
	if is_instance_valid(create_ground_button): create_ground_button.visible = target_choice.selected == 0 and not _compact_active()
	if is_instance_valid(open_canvas_button): open_canvas_button.visible = target_choice.selected == 1 or not _compact_active()
	if is_instance_valid(_terrain_diagnostics_button): _terrain_diagnostics_button.visible = _compact_active()
	if is_instance_valid(_terrain_diagnostics_summary): _terrain_diagnostics_summary.visible = _compact_active() and not _terrain_diagnostics_summary.text.is_empty()

func _category_changed(index: int, stop_scene_brush := true, preferred_mode := "") -> void:
	cancel_stroke()
	if plugin != null and stop_scene_brush: plugin._stop_scene_object_brush()
	category.select(index)
	for i in category_buttons.size(): category_buttons[i].set_pressed_no_signal(i == index)
	_refresh_brush_scale_settings()
	tools.clear()
	var modes:Array=BrushProfiles.world_modes(index,_compact_active())
	var unavailable:=not preferred_mode.is_empty() and preferred_mode not in modes
	if unavailable:modes.append(preferred_mode)
	var volume:bool=not entry.is_empty() and entry.target.get_ref() is EmberVoxelProp and entry.resource.tree_surface.is_empty()
	for mode in modes:tools.add_item(BrushProfiles.world_title(mode,volume));tools.set_item_metadata(tools.item_count-1,mode)
	if tools.item_count > 0: tools.select(0)
	if preferred_mode in modes:tools.select(modes.find(preferred_mode))
	if unavailable:tools.set_item_disabled(modes.size()-1,true)
	for button in _tool_buttons: _target_buttons.erase(button); button.free()
	_tool_buttons.clear()
	for i in modes.size():
		var tool_index := i
		var button := Button.new()
		button.text = tools.get_item_text(i)
		button.icon = _editor_icon(TOOL_ICONS.get(str(modes[i]),&"ToolSelect"))
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.theme_type_variation = &"WorkshopToolButton"
		button.tooltip_text = "Инструмент: %s" % tools.get_item_text(i)
		if unavailable and i==modes.size()-1:
			button.text+=" · недоступно";button.disabled=true;button.tooltip_text="Кисть сохранена, но эта цель её не поддерживает. Выберите доступный инструмент."
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
	if _shape_rule_active():return "detail"
	return "coarse" if terrain_edit_scale.selected == 0 else "medium" if terrain_edit_scale.selected == 1 else "detail"

func _shape_rule_active() -> bool:
	return _compact_active() and _mode()=="smooth" and is_instance_valid(compact_shape_action) and compact_shape_action.selected>0

func _shape_rule_code() -> int:
	if compact_shape_action.selected==1:return CompactBrush.SurfaceRules.round_code(compact_shape_strength.value,compact_shape_radius.selected+1)
	if compact_shape_action.selected==2:return CompactBrush.SurfaceRules.protect_code(compact_shape_strength.value) if compact_shape_strength.value>0 else 0
	return 0

func _tool_changed() -> void:
	if not is_instance_valid(palette): return
	for i in _tool_buttons.size():
		_tool_buttons[i].set_pressed_no_signal(i == tools.selected)
	var coarse_profile := _compact_active() and terrain_edit_scale.selected != 2
	var active_parameters := BrushParameters.active_for(_mode(),_compact_active(),coarse_profile,compact_level_from_point.button_pressed,compact_detail_pattern.selected==1,_volume_smooth_target(),_surface_plane_active())
	if _mode()=="level" and _volume_smooth_target():active_parameters.append("surface_plane_mode")
	if is_instance_valid(inspector_title): inspector_title.text = ("Земля · высоты" if _compact_active() else "Объект · объём" if target_choice.selected==1 else "Земля · объём")+" · "+tools.get_item_text(tools.selected) if tools.selected>=0 else "Параметры кисти"
	if is_instance_valid(inspector_hint): inspector_hint.text = "Ступени по %s блока. Ячейки %s выравниваются." % ["¼" if terrain_height_step.selected == 0 else "½", "8×8 вокселей" if terrain_edit_scale.selected == 0 else "2×2 вокселя"] if coarse_profile and category.selected == 0 else TOOL_HINTS.get(_mode(),"")
	if _compact_active() and _mode()=="generator" and compact_detail_pattern.selected==1:
		inspector_hint.text="Выступы камня, гребни песка и неровности грунта. Сохраняет выбранные покрытия."
	if target_choice.selected==1 and _mode() in ["raise","lower","level","shore","generator"]:inspector_hint.text="Работает по верхней поверхности формы. Боковая лепка — «Лепка · объём» в Canvas."
	if is_instance_valid(inspector_icon): inspector_icon.texture = _editor_icon(TOOL_ICONS.get(_mode(),&"ToolSelect"))
	for parameter_id: String in _brush_parameter_controls:
		var control: Control = _brush_parameter_controls[parameter_id]
		control.visible = parameter_id in active_parameters
	var volume_smooth:=_mode()=="smooth" and _volume_smooth_target()
	depth.max_value=8.0 if volume_smooth else 32.0
	var strength_group:Control=depth.get_meta("parameter_group")
	(strength_group.get_child(1).get_child(0) as HSlider).max_value=depth.max_value
	(strength_group.get_child(0) as Label).text="Сила сглаживания · vox" if volume_smooth else "Глубина · vox"
	if volume_smooth:inspector_hint.text="Сглаживает объём со всех сторон прежним расчётом Canvas. Материалы сохраняются; один Undo на мазок, Esc отменяет."
	if _surface_plane_active():
		(strength_group.get_child(0) as Label).text="Глубина влияния · vox"
		inspector_hint.text="Плоскость по первому касанию; направление не меняется до конца мазка. Смещение вглубь отрицательное. Материалы сохраняются."

	compact_shape_action.visible=_compact_active() and _mode()=="smooth"
	var shape_allowed: bool=_compact_active() and entry.resource.width*entry.resource.depth<=map.smooth_column_limit()
	for i in [1,2,3]:compact_shape_action.set_item_disabled(i,not shape_allowed)
	if not shape_allowed and compact_shape_action.selected>0:compact_shape_action.select(0)
	_shape_settings.visible=_shape_rule_active() and compact_shape_action.selected!=3
	compact_shape_radius.visible=_shape_rule_active() and compact_shape_action.selected==1
	if _shape_rule_active():
		for id in ["edit_scale","height_step","strength_detail","strength_steps"]:_brush_parameter_controls[id].hide()
		inspector_hint.text="Правило гладкого облика; общие высоты и покраска сохраняются. Один мазок — одно Undo; обновление после отпускания мыши. Первое применение: карта до32×32м."
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
	var protection:=sessions.brush_guard(entry,_brush_mask_kind()) if not entry.is_empty() else {}
	_clear_shared_mask.visible=protection.get("enabled",false) or protection.get("invalid",false)
	_clear_shared_mask.text="Обновить защиту Canvas" if protection.get("invalid",false) else "Снять маску Canvas"
	if protection.get("enabled",false):inspector_hint.text+="\nМаска Canvas: "+("точные ячейки." if protection.kind=="voxels" else "отпечаток грани." if protection.kind=="columns" else "инструмент недоступен, пока маска включена.")
	if protection.get("region",Rect2i()).has_area() or protection.get("height",-1)>=0:inspector_hint.text+="\nРабочая область/срез Canvas сохраняют защиту; изменить их можно в Canvas."
	if not _context_tool_available():
		inspector_hint.text="Кисть не поддерживает активную маску Canvas. Снимите маску перед действием." if protection.get("enabled",false) and _brush_mask_kind()==BrushProfiles.MASK_NONE else "Эта кисть недоступна для выбранной цели. Выберите доступный инструмент; прежняя кисть сохранена."
		hover.clear();_update_overlay()

func _brush_mask_kind()->String:
	var mode:=_mode()
	if BrushProfiles.WORLD_TOOLS.has(mode):return BrushProfiles.mask_kind(BrushProfiles.WORLD_TOOLS[mode],_volume_smooth_target() and (mode=="smooth" or _surface_plane_active()))
	return BrushProfiles.MASK_COLUMNS if mode in ["shore","generator"] else BrushProfiles.MASK_VOXELS if mode=="sand" else BrushProfiles.MASK_NONE

func _context_tool_available()->bool:
	if entry.is_empty() or _mode() not in BrushProfiles.world_modes(category.selected,_compact_active()):return false
	if category.selected==3:return true
	var state:Dictionary=entry.get("canvas_guard",{})
	return not (state.get("selection",{}).get("mask_enabled",false) and _brush_mask_kind()==BrushProfiles.MASK_NONE)


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
	radius.max_value=minf(8.0,float(BrushProfiles.MAX_RADIUS_VOXELS)/entry.resource.normalized_density()) if not _compact_active() else 8.0
	radius_slider.max_value=radius.max_value
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
	if not _compact_active() or not is_instance_valid(material_pattern_dialog) or plugin == null: return
	if not _material_mode and not can_leave_panel(): return
	var index := int(palette.get_selected_metadata()) if palette.selected >= 0 else -1
	if index < 0 or entry.resource.surface_role_for_palette(index).is_empty():
		index = entry.resource.palette_surface_roles.find("grass")
		if index <= 0:
			for slot in range(1, entry.resource.palette.size()):
				if not entry.resource.surface_role_for_palette(slot).is_empty():
					index = slot
					break
	if index <= 0:
		_status("Назначьте общий материал одному из слотов земли.")
		return
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
		var defaults := EmberVoxelSurfaceMaterials.WORLD_GROUND_MATERIALS
		for material_role: String in defaults:
			var material_id: String = defaults[material_role]
			if not _material_choices.any(func(choice): return choice.id == material_id):
				_material_choices.append({"id":material_id, "role":material_role, "index":-1})
		if not _material_choices.any(func(choice): return choice.id == "paving"):
			_material_choices.append({"id":"paving", "role":"stone", "index":-1})
		material_pattern_dialog.set_variant_choices(_material_choices)
	material_pattern_dialog.cheap_ground_profile=true
	if role.is_empty() or not material_pattern_dialog.open_variant(id, role):
		_status("Рисунок выбранного материала не найден или повреждён."); return
	_show_material_workspace()


func _on_material_pattern_saved(pattern: TerrainPattern, id: String) -> void:
	if id == "moss":
		preload("res://scripts/ember_object_moss.gd").preset = pattern.duplicate()
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection if is_instance_valid(map) else null
	if projection != null:
		projection.set_shared_material_pattern(pattern)
	_status("Паттерн %s сохранён. Карты с этим вариантом обновятся без пересборки земли." % id)

func _on_material_light_previewed(pattern: TerrainPattern, id: String) -> void:
	var projection:=map._visual_surface_projection as EmberTerrainPilotProjection if is_instance_valid(map) else null
	if projection!=null:projection.preview_shared_material_light(pattern,id)


func _on_material_scale_previewed(pattern: TerrainPattern, id: String) -> void:
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection if is_instance_valid(map) else null
	if projection != null:
		projection.preview_shared_material_scale(pattern, id)


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

func open_object_canvas(prop:EmberVoxelProp)->bool:
	if not activate_context(prop,false):return false
	return _open_canvas_entry(entry)

func open_canvas() -> void:
	if entry.is_empty():return
	if entry.get("compact",false):
		_status("Компактная земля редактируется прямо в 3D. Canvas остаётся для voxel-объектов.")
		return
	cancel_stroke()
	_open_canvas_entry(entry)

func _open_canvas_entry(next:Dictionary)->bool:
	if plugin==null:return false
	var workspace := EditorInterface.get_editor_main_screen().find_child(plugin.SURFACE_WORKSPACE_NODE,true,false) as EmberVoxelSculptWorkspace
	if workspace==null:_status("Surface Canvas отключён.");return false
	if not workspace.world_context_return_requested.is_connected(_return_from_canvas):workspace.world_context_return_requested.connect(_return_from_canvas)
	workspace.configure_forms(sessions,save_all)
	if (workspace._world_entry!=next or workspace._resource!=next.resource):
		if not workspace.open_world_draft(next,sessions,save_all):return false
	else:workspace.restore_world_guard()
	var tool_id:int=BrushProfiles.WORLD_TOOLS.get(_mode(),int(_mode().trim_prefix("canvas:")) if _mode().begins_with("canvas:") else -1)
	if tool_id>=0:
		workspace._activate_tool_id(tool_id)
		workspace.set_world_brush_radius(radius.value)
		workspace.set_world_brush_settings(depth.value,softness.value)
		if tool_id==Model.TOOL_LEVEL and _volume_smooth_target():workspace.set_surface_plane_settings(surface_plane_mode.selected,surface_plane_offset.value,depth.value)
	plugin._connect_generator_library(workspace)
	EditorInterface.set_main_screen_editor(plugin.SURFACE_MAIN_SCREEN)
	return true

func _adopt_canvas_brush_settings(workspace:EmberVoxelSculptWorkspace)->void:
	var settings:=workspace.world_brush_settings()
	if settings.has("depth"):
		depth.max_value=32.0;depth.set_value_no_signal(settings.depth)
	if settings.has("softness"):softness.set_value_no_signal(settings.softness)
	var config:=workspace.surface_plane_settings()
	if config.is_empty():return
	surface_plane_mode.select(config.mode);surface_plane_offset.set_value_no_signal(config.offset);depth.max_value=32.0;depth.set_value_no_signal(config.depth)

func _return_from_canvas(target:Node3D)->void:
	var workspace:=EditorInterface.get_editor_main_screen().find_child(plugin.SURFACE_WORKSPACE_NODE,true,false) as EmberVoxelSculptWorkspace
	if workspace==null or not activate_context(target):return
	_adopt_canvas_brush_settings(workspace)
	var mode:=BrushProfiles.world_mode_for_tool(workspace._selected_tool_id())
	var group:=category.selected
	for i in 4:
		if mode in BrushProfiles.world_modes(i,_compact_active()):group=i;break
	_changing_context=true;_category_changed(group,true,mode);_changing_context=false
	_restore_context_radius(float(workspace._radius.get_selected_metadata())/workspace._resource.normalized_density())
	EditorInterface.set_main_screen_editor("3D")

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
	if dragging or job != null or not grab.is_empty() or not _plan_drag.is_empty() or _plot_anchor.is_finite() or (plugin != null and plugin._object_brush._dragging):
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
	if _generation_context.get("grove_applying",false) and event is InputEventKey and event.pressed and not event.echo and event.is_command_or_control_pressed() and event.keycode==KEY_Z:
		clear_terrain_generation_preview()
		_generation_panel.set_pending("Подключение отменено. Обновите предпросмотр.")
		get_viewport().set_input_as_handled();return
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
	return projection.pick_ground_top(origin,origin+camera.project_ray_normal(position)*camera.far,_mode()=="paint")

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

func _context_target(node:Node)->Node:
	var object:=EmberObjectInspectorModel.voxel_owner(node)
	if object!=null:return object
	if not is_instance_valid(map) or not is_instance_valid(node):return null
	if node==map:return map
	for ground in [map.get_node_or_null("Terrain"),map._visual_surface_projection]:
		if is_instance_valid(ground) and (ground==node or ground.is_ancestor_of(node)):return map
	return null

func _pick_context(position: Vector2) -> void:
	if not is_instance_valid(camera):return
	var origin := camera.project_ray_origin(position)
	var ray := PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(position)*camera.far)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(ray)
	var target:=_context_target(hit.get("collider"))
	if target!=null:activate_context(target)
	else:_status("Под курсором нет редактируемой земли или объекта. Текущая цель сохранена.")

func forward_input(next_camera: Camera3D, event: InputEvent) -> int:
	if _panel_host.blocks_viewport_tools():
		return _panel_host.forward_input(event,get_viewport().gui_get_focus_owner())
	if not active: return EditorPlugin.AFTER_GUI_INPUT_PASS
	var received_usec := Time.get_ticks_usec() if _trace.recording and event is InputEventMouse else 0
	var scheduled_usec := int(event.get_meta("ember_scheduled_usec",0)) if received_usec > 0 else 0
	camera = next_camera
	if event is InputEventMouse:_context_pointer=event.position
	if event is InputEventKey and event.pressed and not event.echo and event.alt_pressed and not event.is_command_or_control_pressed() and event.keycode==KEY_Q:
		var focus:=get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):return EditorPlugin.AFTER_GUI_INPUT_PASS
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):_status("Завершите жест перед сменой цели.");return EditorPlugin.AFTER_GUI_INPUT_STOP
		_pick_context(_context_pointer);return EditorPlugin.AFTER_GUI_INPUT_STOP
	if picking_object and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		_pick_context(event.position);return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _section_mode: return _forward_section_selection(event)
	# Plan gestures own their viewport input, including while coast parameters
	# are open. The general recipe guard below must only block terrain painting.
	if _plan_map_active(): return _forward_compact(event)
	if not _context_tool_available() and not selecting:
		if event is InputEventKey and event.pressed and event.is_command_or_control_pressed() and event.keycode==KEY_S:save_all();return EditorPlugin.AFTER_GUI_INPUT_STOP
		return EditorPlugin.AFTER_GUI_INPUT_PASS
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
	if event is InputEventKey and (focused is LineEdit or focused is TextEdit):
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if _plan_selection in ["add_river","add_road","add_surface_road","add_road_branch","extend_road_branch","add_coast","path_line"]:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and is_instance_valid(focused):
			focused.release_focus()
		return _forward_plan_path(event)
	if _plan_map_active():
		if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and is_instance_valid(focused):focused.release_focus()
		if not _street_preview.is_empty(): return _forward_street_preview(event)
		if not _plot_tool.is_empty(): return _forward_plot(event)
		return _forward_plan_map(event)
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
				_compact_brush.stamp_surface(hover,_compact_bounds())
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
				if _shape_rule_active():mode=["smooth","shape_round","shape_protect","shape_clear"][compact_shape_action.selected]
				if event.ctrl_pressed:
					mode = {"raise":"lower","lower":"raise","water":"dry","dry":"water"}.get(mode,mode)
				var selected_palette := int(palette.get_selected_metadata()) if palette.selected >= 0 else 1
				var direction: int = [0,1,-1][compact_direction.selected]
				var target_world := roundi(plane_height.value) if mode == "level" and not compact_level_from_point.button_pressed else -99999
				var coarse_profile := terrain_edit_scale.selected != 2
				var height_step := (CompactBrushMath.QUARTER_BLOCK_HEIGHT_STEP if terrain_height_step.selected == 0 else CompactBrushMath.HALF_BLOCK_HEIGHT_STEP) if coarse_profile else 1
				var height_strength := roundi(coarse_depth.value) * height_step if coarse_profile else roundi(depth.value)
				if _compact_trace.recording:
					_compact_trace.begin_brush_stroke({"mode": mode, "radius_blocks": radius.value,
						"edit_scale": _compact_edit_scale(), "brush_shape": "square" if brush_shape.selected == 0 else "circle",
						"height_step_voxels": height_step, "strength_voxels": height_strength,
						"feature_scale": compact_feature_scale.value, "detail": compact_detail.value,"material_detail":compact_detail_pattern.selected==1})
					_compact_trace.stage("press_pick", press_pick_usec)
				var begin_started := Time.get_ticks_usec() if _compact_trace.recording else 0
				if _compact_brush.begin(mode,radius.value,height_strength,selected_palette,roundi(water_height.value),roundi(compact_feature_scale.value),roundi(compact_detail.value),roundi(compact_seed.value),direction,target_world,_compact_edit_scale(),"square" if brush_shape.selected == 0 else "circle",height_step,compact_detail_pattern.selected==1,_shape_rule_code() if _shape_rule_active() else 0):
					if begin_started > 0:
						_compact_trace.stage("brush_begin", Time.get_ticks_usec() - begin_started)
						_compact_brush.diagnostic_sink = _compact_trace
					dragging = true
					_set_busy(true)
					var first_started := Time.get_ticks_usec() if _compact_trace.recording else 0
					_compact_brush.stamp_surface(hover,_compact_bounds())
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
					_compact_brush.stamp_surface(final_pick,_compact_bounds())
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

func _shared_mask_normal()->Vector3i:
	if dragging:
		var guard:Dictionary=stroke_options.get("guard",{})
		return Model.axis_normal(guard.normal) if guard.get("enabled",false) else Vector3i.ZERO
	var selection:Dictionary=entry.get("canvas_guard",{}).get("selection",{})
	return Model.axis_normal(selection.get("mask_normal",Vector3i.UP)) if selection.get("mask_enabled",false) else Vector3i.ZERO

func _center(pick: Dictionary, mode := "") -> Vector3i:
	if pick.is_empty(): return Model.INVALID_CELL
	if mode == "": mode = stroke_mode if dragging else _mode()
	if mode=="add":
		var normal:=_shared_mask_normal()
		if normal!=Vector3i.ZERO and pick.get("hit",Model.INVALID_CELL)!=Model.INVALID_CELL:
			var adjacent:Vector3i=pick.hit+normal
			return adjacent if Model.contains(adjacent,entry.resource.grid_size()) else Model.INVALID_CELL
		return pick.get("adjacent",Model.INVALID_CELL)
	return pick.get("adjacent",Model.INVALID_CELL) if pick.get("empty_floor",false) else pick.get("hit",Model.INVALID_CELL)

func _surface_plane_active()->bool:
	return _mode()=="level" and _volume_smooth_target() and surface_plane_mode.selected>0

func _volume_smooth_target()->bool:
	return not entry.is_empty() and entry.target.get_ref() is EmberVoxelProp and entry.resource.tree_surface.is_empty() and not entry.resource.solid_surface.is_empty()

func _begin_stroke(pick: Dictionary, inverse := false, input_usec := 0, input_position := Vector2.ZERO, scheduled_usec := 0, pick_usec := 0) -> void:
	if entry.is_empty(): return
	var protection:=sessions.brush_guard(entry,_brush_mask_kind())
	if protection.get("invalid",false) or protection.get("enabled",false) and _brush_mask_kind()==BrushProfiles.MASK_NONE:
		_status("Защита Canvas не позволяет этот мазок. Снимите маску или обновите область в Canvas.");return
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
	stroke_options.guard=protection
	if stroke_mode=="smooth" and _volume_smooth_target():stroke_options.locked=Groups.locked_indices(baseline.voxel_groups)
	if _surface_plane_active():
		var normal:Vector3i=pick.get("normal",Vector3i.UP)
		var n:=Model.averaged_surface_normal(baseline.voxels,baseline.grid_size(),center,normal,Model.surface_normal_radius(stroke_radius),normal)
		stroke_options.plane_normal=n
		stroke_options.plane_point=Vector3(center)+Vector3(normal)*0.5+n*surface_plane_offset.value
		stroke_options.cut_only=surface_plane_mode.selected==2
		stroke_options.locked=Groups.locked_indices(baseline.voxel_groups)

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
	var normal:Vector3i=pick.get("normal",Vector3i.UP)
	if stroke_mode in ["add","remove","paint"] and _shared_mask_normal()!=Vector3i.ZERO:normal=_shared_mask_normal()
	if stroke_mode in ["add","remove","paint"]:
		var count := clampi(ceili(Vector3(cell-previous).length()/maxf(1,stroke_radius*0.4)),1,2048)
		for i in range(1,count+1):
			var sample := {"from":Vector3i(Vector3(previous).lerp(Vector3(cell),float(i)/count)),"to":Vector3i(Vector3(previous).lerp(Vector3(cell),float(i)/count)),"normal":normal}
			if _trace.recording: sample.queued_usec = queued_at
			queue.append(sample)
		appended = count
	else:
		var sample := {"from":previous,"to":cell,"normal":normal}
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
	if stroke_options.has("plane_normal"):
		var next:=Model.SurfacePlaneJob.new()
		next.values=baseline.voxels;next.parts=baseline.voxel_part_ids;next.size=baseline.grid_size()
		next.radius=stroke_radius;next.depth=stroke_depth
		next.plane_point=stroke_options.plane_point;next.plane_normal=stroke_options.plane_normal;next.cut_only=stroke_options.cut_only
		next.segments=[sample];next.segments.append_array(queue);queue.clear()
		next.task_id=WorkerThreadPool.add_task(next.run,false,"World surface plane")
		return next
	if stroke_mode=="smooth" and _volume_smooth_target():
		var next:=VolumeSmooth.new()
		next.values=baseline.voxels;next.parts=baseline.voxel_part_ids;next.size=baseline.grid_size()
		next.radius=stroke_radius;next.kernel=clampi(stroke_depth,1,8)
		next.segments=[sample]
		# Coalesce pending input into the same local calculation, never a whole-object pass.
		next.segments.append_array(queue);queue.clear()
		next.task_id=WorkerThreadPool.add_task(next.run,false,"World volume smooth")
		return next
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

func _apply_batch(changes: Dictionary, notify_projection := true, inherited:Dictionary={}) -> void:
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
			if not Selection.guard_allows(index,size,stroke_options.get("guard",{}),entry.resource.normalized_density()):continue
			if stroke_options.get("locked",{}).has(index):continue
			if (stroke_mode=="smooth" and _volume_smooth_target() or stroke_options.has("plane_normal")) and clip.button_pressed and edit_region.has_area():
				var point:=Vector2i(int(index)%size.x,(int(index)/size.x)%size.z)
				var density:int=entry.resource.normalized_density()
				if not Rect2i(edit_region.position*density,edit_region.size*density).has_point(point):continue
			var value: int = changes[index].after
			updates.voxels[index] = value
			if updates.has("collision_voxels"):
				if value == 0: updates.collision_voxels[index] = 0
				elif baseline.voxels[index] == 0: updates.collision_voxels[index] = 1
			if updates.has("voxel_part_ids"):
				if value==0:updates.voxel_part_ids[index]=0
				elif inherited.has(index):updates.voxel_part_ids[index]=inherited[index]
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
	for retired in _smooth_retired.duplicate():
		if WorkerThreadPool.is_task_completed(retired.task_id):
			WorkerThreadPool.wait_for_task_completion(retired.task_id);_smooth_retired.erase(retired)
	if not _plan_drag.is_empty() and _plan_drag.get("watch_release",false) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):_plan_finish_drag()
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
	if job is VolumeSmooth or job is Model.SurfacePlaneJob:
		if WorkerThreadPool.is_task_completed(job.task_id):
			WorkerThreadPool.wait_for_task_completion(job.task_id)
			if not job.cancelled:_apply_batch(job.changes,true,job.owners)
			job=null;_job_queued_usec=0
	elif job != null:
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
	if job is VolumeSmooth or job is Model.SurfacePlaneJob:
		job.cancelled=true;_smooth_retired.append(job)
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
	var protection:=sessions.brush_guard(entry,BrushProfiles.MASK_NONE)
	if protection.get("enabled",false) or protection.get("invalid",false):_status("«Тянуть»: снимите маску Canvas перед деформацией.");return
	var region:Rect2i=protection.get("region",Rect2i())
	if clip.button_pressed and edit_region.has_area():
		if region.has_area():
			region=region.intersection(edit_region)
			if not region.has_area():_status("Рабочие области не пересекаются.");return
		else:region=edit_region
	if hover.is_empty() or hover.get("hit",Model.INVALID_CELL) == Model.INVALID_CELL: return
	var frame: Transform3D = sessions.frame(entry)
	var center := Vector3(hover.hit)+Vector3.ONE*0.5
	var plane := Plane((frame.basis.inverse()*camera.global_basis.z).normalized(),center/entry.resource.normalized_density())
	var anchor = plane.intersects_ray(frame.affine_inverse()*camera.project_ray_origin(position),frame.basis.inverse()*camera.project_ray_normal(position))
	if anchor == null: return
	grab = {"region":region,"height":protection.get("height",-1),"baseline":entry.resource.duplicate_model(),"frame":frame,"plane":plane,"anchor":anchor,"center":center,"position":position,"pending":false,"released":false,"displacement":Vector3.ZERO,"planned":Vector3.ZERO,"job":null,"plan":{},"radius":radius.value*entry.resource.normalized_density()}
	_set_busy(true)

func _process_grab() -> void:
	if not is_instance_valid(entry.target.get_ref()) or sessions.frame(entry) != grab.frame: cancel_stroke(); return
	if grab.pending:
		grab.pending = false
		var point = grab.plane.intersects_ray(grab.frame.affine_inverse()*camera.project_ray_origin(grab.position),grab.frame.basis.inverse()*camera.project_ray_normal(grab.position))
		if point != null: grab.displacement = (point-grab.anchor)*entry.resource.normalized_density()
	if grab.job == null and not grab.displacement.is_equal_approx(grab.planned):
		grab.planned = grab.displacement
		grab.job = Fragment.start_grab(grab.baseline,grab.center,grab.radius,grab.planned,softness.value,grab.region,grab.height,clip.button_pressed or grab.region.has_area() or grab.height>=0)
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
			var occupied := SectionSelection.complete(source, key)
			var colour := Color(0.6, 0.65, 0.7, 0.7) if occupied else Color(0.3, 0.9, 1.0, 0.95)
			overlay.draw_colored_polygon(polygon, Color(colour, 0.07 if occupied else 0.22))
			polygon.append(polygon[0])
			overlay.draw_polyline(polygon, colour, 2, true)


func _path_pick(position: Vector2) -> Vector2:
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	if not _surface_road_support.is_empty() and is_instance_valid(camera):
		var surface_hit := _path_physics_pick(position)
		var prop := EmberObjectInspectorModel.voxel_owner(surface_hit.get("collider"))
		if prop != null and prop.placement_id == _surface_road_support:
			return _plot_local_grid(projection, surface_hit.position).snapped(Vector2.ONE * 0.25)
	var hit := _pick_compact(position)
	if hit.is_empty(): return Vector2(-1,-1)
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
	var spacing := 0.5 if _surface_road_support.is_empty() else 0.25
	return (Vector2(local.x,local.z)/16.0).snapped(Vector2.ONE*spacing)


func _path_physics_pick(pixel: Vector2) -> Dictionary:
	if not is_instance_valid(camera):
		return {}
	var origin := camera.project_ray_origin(pixel)
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(pixel) * camera.far, 1)
	return camera.get_world_3d().direct_space_state.intersect_ray(ray)


func _road_branch_anchor(point: Vector2) -> Dictionary:
	var plan: Resource = TerrainPlan.read(map)
	var index: int = plan.index_of(_plan_selected_id) if plan != null else -1
	if index < 0 or point.x < 0.0:
		return {}
	var host: Dictionary = plan.regions[index]
	var axis := TerrainPlan.Influence.path_curve(host.points_m)
	var station := axis.get_closest_offset(point)
	var anchor := axis.sample_baked(station)
	var length := axis.get_baked_length()
	var margin := maxf(1.0, float(host.parameters.width_m) * 0.5)
	if anchor.distance_to(point) > margin + 0.3 or station < margin or station > length - margin:
		return {}
	return {"point": anchor, "host": host.id, "fraction": station / length}


func _forward_plan_path(event: InputEvent) -> int:
	if event is InputEventMouse and (event.alt_pressed or event.button_mask & (MOUSE_BUTTON_MASK_RIGHT|MOUSE_BUTTON_MASK_MIDDLE)):
		if _path_hover.x >= 0.0:
			_path_hover = Vector2(-1,-1)
			_update_overlay()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]: return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventKey:
		if event.alt_pressed or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE): return EditorPlugin.AFTER_GUI_INPUT_PASS
		if not event.pressed or event.echo: return EditorPlugin.AFTER_GUI_INPUT_PASS
		if event.is_command_or_control_pressed() and event.keycode in [KEY_Z,KEY_Y]: _open_terrain_plan(); return EditorPlugin.AFTER_GUI_INPUT_PASS
		if event.keycode == KEY_ESCAPE:
			if _plan_selection == "extend_road_branch":
				_plan_selection = ""
				selecting = false
				_path_points.clear()
				_path_hover = Vector2(-1,-1)
				_plan_panel.set_branch_pending(not _branch_edit.is_empty())
				_plan_panel.set_status("Продолжение отменено.")
				_update_overlay()
			else:
				_open_terrain_plan()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode in [KEY_ENTER,KEY_KP_ENTER]: _finish_plan_path(); _update_overlay(); return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_BACKSPACE:
			_clear_surface_road_preview()
			var minimum := 0
			if _plan_selection == "extend_road_branch":
				var plan: Resource = TerrainPlan.read(map)
				var region: Dictionary = _branch_edit.get("region", plan.regions[plan.index_of(_plan_selected_id)])
				minimum = region.points_m.size()
			if _path_points.size() > minimum: _path_points.resize(_path_points.size()-1)
			_update_overlay(); return EditorPlugin.AFTER_GUI_INPUT_STOP
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion:
		_path_hover = _path_pick(event.position)
		if _plan_selection == "add_road_branch" and _path_points.is_empty():
			_path_hover = _road_branch_anchor(_path_hover).get("point", Vector2(-1,-1))
		_update_overlay()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _plan_selection == "add_surface_road" and _surface_road_support.is_empty():
				var picked := EmberObjectInspectorModel.voxel_owner(_path_physics_pick(event.position).get("collider"))
				if picked == null or picked.placement_id.is_empty() or _surface_road_prop(map, picked.placement_id) != picked:
					_plan_panel.set_status("Щёлкните по объёмному уступу с физической поверхностью.")
				else:
					_surface_road_support = picked.placement_id
					_plan_panel.set_status("Уступ выбран. Наметьте дорогу с земли на его верх.")
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			_clear_surface_road_preview()
			var point := _path_pick(event.position)
			if point.x < 0: _plan_panel.set_status("На этом месте нет земли. Намечайте линию внутри созданных участков."); return EditorPlugin.AFTER_GUI_INPUT_STOP
			if _plan_selection == "add_road_branch" and _path_points.is_empty():
				var anchor := _road_branch_anchor(point)
				if anchor.is_empty():
					_plan_panel.set_status("Выберите точку внутри проезжей части, вдали от концов дороги.")
					return EditorPlugin.AFTER_GUI_INPUT_STOP
				_road_join = {"host": anchor.host, "fraction": anchor.fraction}
				point = anchor.point
			if _path_points.size() >= 32: _plan_panel.set_status("Не больше 32 точек; Enter завершает линию."); return EditorPlugin.AFTER_GUI_INPUT_STOP
			if not _path_points.is_empty() and point.distance_to(_path_points[-1]) < 1: return EditorPlugin.AFTER_GUI_INPUT_STOP
			_path_points.append(point); _path_hover = Vector2(-1,-1)
			var enter_action := "в черновик" if _plan_selection == "extend_road_branch" else "предпросмотр" if _plan_selection == "add_road_branch" else "профиль" if not _surface_road_support.is_empty() else "сохранить"
			_plan_panel.set_status("Точек: %d · Enter — %s, Backspace — убрать последнюю, Esc — отменить." % [_path_points.size(), enter_action])
			_update_overlay()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _draw_plan_path(overlay: Control, points: PackedVector2Array, color: Color, cache_key: String, direction := true, support: EmberVoxelProp = null) -> void:
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
		var world := _path_surface_world(point, support) if is_instance_valid(support) else map._visual_surface_projection.to_global(Vector3(point.x*16.0,height+0.15,point.y*16.0))
		if not world.is_finite(): continue
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
		var world := _path_surface_world(point, support) if is_instance_valid(support) else map._visual_surface_projection.to_global(Vector3(point.x*16,height+0.15,point.y*16))
		if world.is_finite() and not camera.is_position_behind(world): overlay.draw_circle(camera.unproject_position(world),4,color)

func _path_surface_world(point: Vector2, support: EmberVoxelProp = null) -> Vector3:
	if entry.is_empty() or not is_instance_valid(map):
		return Vector3.INF
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	if not is_instance_valid(projection):
		return Vector3.INF
	var world := projection.to_global(Vector3(point.x * 16.0, 0.0, point.y * 16.0))
	var floor_hit := map.surface_floor_sample_with_candidates(world, [support]) if is_instance_valid(support) else projection.floor_surface_sample(world)
	var cell: Vector2i = floor_hit.get("cell", Vector2i(-1,-1))
	var source: EmberTerrainPilotResource = entry.resource
	if not source.has_column(cell.x, cell.y):
		return Vector3.INF
	var index := source.column_index(cell.x, cell.y)
	var level := source.column_value("water_levels", index)
	if level > source.column_value("heights", index):
		var water := projection.to_global(Vector3(point.x * 16.0, source.origin_y + level, point.y * 16.0))
		if not floor_hit.get("solid", false) or water.y > floor_hit.position.y:
			return water
	return floor_hit.get("position", Vector3.INF)


func _path_surface_pixel(point: Vector2, support: EmberVoxelProp = null) -> Vector2:
	var world := _path_surface_world(point, support)
	return camera.unproject_position(world) if world.is_finite() and not camera.is_position_behind(world) else Vector2.INF


func _draw_path_handle(overlay: Control, pixel: Vector2, color: Color, emphasized := false) -> void:
	if not pixel.is_finite():
		return
	var radius := PATH_POINT_RADIUS + (2.0 if emphasized else 0.0)
	overlay.draw_circle(pixel, radius + 2.0, Color(0.03, 0.08, 0.12, 0.9), true, -1, true)
	overlay.draw_circle(pixel, radius, color, false, 2.0, true)
	overlay.draw_circle(pixel, 3.0, color, true, -1, true)


func _draw_path_snap(overlay: Control, point: Vector2, step: float, support: EmberVoxelProp, on_axis := false) -> void:
	var pixel := _path_surface_pixel(point, support)
	if not pixel.is_finite():
		return
	var grid_center := point.snapped(Vector2.ONE * step)
	var grid := PackedVector2Array()
	for z in range(-1, 2):
		for x in range(-1, 2):
			grid.append(_path_surface_pixel(grid_center + Vector2(x, z) * step, support))
	for row in 3:
		for col in 3:
			var i := row * 3 + col
			if not grid[i].is_finite():
				continue
			for next in [i + 1 if col < 2 else -1, i + 3 if row < 2 else -1]:
				if next >= 0 and grid[next].is_finite():
					overlay.draw_line(grid[i], grid[next], Color(0.03, 0.08, 0.12, 0.85), 3.0, true)
					overlay.draw_line(grid[i], grid[next], Color(0.50, 0.88, 1.0, 0.76), 1.0, true)
	var color := Color("ffd477") if on_axis else Color("76ecff")
	_draw_path_handle(overlay, pixel, color, true)
	var font := ThemeDB.fallback_font
	var caption := "%.2f / %.2f м · %s" % [point.x, point.y, "ось дороги" if on_axis else "шаг %.2f м" % step]
	var size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13) + Vector2(12, 7)
	var position := (pixel + Vector2(16, -29)).clamp(Vector2.ZERO, (overlay.size - size).max(Vector2.ZERO))
	overlay.draw_rect(Rect2(position, size), Color(0.03, 0.08, 0.12, 0.92))
	overlay.draw_string(font, position + Vector2(6, font.get_ascent(13) + 3), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)


func _forward_plot(event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and not event.echo:
		if _plot_tool in ["street_bridge", "street_bridge_edit"] and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_plan_panel.set_status(_commit_street_bridge())
			_update_overlay()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if _plot_tool == "plot_street_front" and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_plan_panel.set_status(_commit_plot_street_front())
			_update_overlay()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_ESCAPE or (event.is_command_or_control_pressed() and event.keycode == KEY_Z and
			(_plot_anchor.is_finite() or _street_bridge.has("node"))):
			_reset_plot_tool()
			_plan_panel.set_status("Действие отменено.")
			_update_overlay()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.is_command_or_control_pressed() and event.keycode == KEY_S:
			if _plot_anchor.is_finite():
				_plan_panel.set_status("Завершите линию или отмените её Esc.")
			else:
				save_all()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	if not event is InputEventMouse or event.alt_pressed or event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if _plot_tool == "street_place":
		if event is InputEventMouseButton and event.pressed:
			var point := _path_pick(event.position)
			if point.x >= 0.0 and point.y >= 0.0:
				_street_plot_action("street_place", _plan_selected_id, "", point)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _plot_tool == "street_bridge_edit":
		if event is InputEventMouseButton and event.pressed:
			_plan_panel.set_status(_preview_street_bridge_style(event.position))
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _plot_tool == "street_bridge":
		if event is InputEventMouseButton and event.pressed:
			var hit := _pick_compact(event.position)
			var projection := map._visual_surface_projection as Node3D
			var message := _pick_street_bridge_point(_plot_local_grid(projection, hit.world)) if not hit.is_empty() else "Щёлкните по полотну дороги."
			_plan_panel.set_status(message)
			_update_overlay()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _plot_tool == "plot_street_front":
		if event is InputEventMouseButton and event.pressed:
			var hit := _pick_compact(event.position)
			var projection := map._visual_surface_projection as Node3D
			var message := _preview_plot_street_front(_plot_local_grid(projection, hit.world)) if not hit.is_empty() else "Щёлкните по соседней дороге."
			_plan_panel.set_status(message)
			_update_overlay()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _plot_tool == "plot_window_pick":
		if event is InputEventMouseButton and event.pressed:
			var wall := _find_plot_wall_face(event.position).get("wall") as Node3D
			if wall != null and Plot.placed_opening_kind(wall) != Plot.WALL_SOLID:
				_plot_window_name = str(wall.name)
				_reset_plot_tool()
				_refresh_plot_window()
				_plan_panel.set_status("Измените параметры проёма или материал стены и примените.")
			else:
				_plan_panel.set_status("Щёлкните по стене с окном или дверью на выбранном этаже.")
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _plot_tool == "plot_finish_pick":
		if event is InputEventMouseButton and event.pressed:
			var selection := _find_plot_finish_piece(event.position)
			if not selection.is_empty():
				_plot_finish_name = str(selection.piece.name)
				_plot_finish_group = selection.group
				_reset_plot_tool()
				_refresh_plot_finish()
				_plan_panel.set_status("Выберите текстуру, оттенок и частоту рисунка, затем примените отделку.")
			else:
				_plan_panel.set_status("На выбранном этаже здесь нет поверхности для отделки.")
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _plot_tool == "plot_pilaster":
		_plot_pilaster_hit = _find_plot_wall_face(event.position)
		if event is InputEventMouseButton and event.pressed:
			_plan_panel.set_status(_place_plot_pilaster())
		_update_overlay()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	_plot_cursor = Vector2.INF
	var world_point := Vector3.INF
	var props := map.get_node_or_null("Props") as Node3D
	if _plot_docking and props != null and (not _plot_anchor.is_finite() or _plot_arc_through.is_finite()):
		_plot_hover_dock = _plot_dock_under_pointer(event.position, props)
		_plot_cursor = _plot_hover_dock.get("point", Vector2.INF)
		if event is InputEventMouseButton and event.pressed:
			_plan_panel.set_status(_plot_click(_plot_cursor) if _plot_cursor.is_finite() else "Выберите отмеченный свободный проход.")
		_update_overlay()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	var height := _plot_pointer_y(props)
	if is_finite(height):
		var inverse := props.global_transform.affine_inverse()
		var hit = Plane(Vector3.UP, height).intersects_ray(
			inverse * camera.project_ray_origin(event.position), inverse.basis * camera.project_ray_normal(event.position))
		if hit != null:
			world_point = props.to_global(hit)
	elif _plot_level == 0 and _plot_tool not in ["plot_column", "plot_cornice", "plot_roof", "plot_railing"]:
		var hit := _pick_compact(event.position)
		if not hit.is_empty():
			world_point = hit.world
	if world_point.is_finite():
		var local: Vector3 = map._visual_surface_projection.to_local(world_point)
		var point := Vector2(local.x, local.z) / 16.0
		var frame := _selected_plot_frame()
		_plot_cursor = frame * (frame.affine_inverse() * point).snapped(Vector2.ONE * Plot.GRID_SNAP_M)
		var nearest := 0.375 * 0.375
		for anchor in _plot_edge_anchors:
			var distance := anchor.distance_squared_to(point)
			if distance < nearest:
				_plot_cursor = anchor
				nearest = distance
	if event is InputEventMouseButton and event.pressed:
		_plan_panel.set_status(_plot_click(_plot_cursor))
	_update_overlay()
	return EditorPlugin.AFTER_GUI_INPUT_STOP


func _find_plot_finish_piece(pixel: Vector2) -> Dictionary:
	var props := map.get_node_or_null("Props") as Node3D
	if props == null or not is_instance_valid(camera):
		return {}
	var origin := camera.project_ray_origin(pixel)
	var ray := camera.project_ray_normal(pixel)
	var nearest := {}
	var distance := INF
	for piece in props.get_children():
		if piece is not Node3D or piece.get_meta(Plot.META, "") != _plan_selected_id or int(piece.get_meta(Plot.LEVEL_META, 0)) != _plot_level:
			continue
		for group in [Plot.FINISH_SURFACE, Plot.FINISH_FRAME, Plot.FINISH_DOOR]:
			for part in Plot.finish_parts(piece, group):
				var inverse := part.global_transform.affine_inverse()
				var local_origin := inverse * origin
				var local_ray := inverse.basis * ray
				var hit = part.get_aabb().intersects_ray(local_origin, local_ray)
				if hit != null and part.mesh is not BoxMesh:
					hit = _nearest_finish_face(part.mesh, local_origin, local_ray)
				if hit != null:
					var depth := origin.distance_squared_to(part.to_global(hit))
					if depth < distance:
						distance = depth
						nearest = {"piece": piece, "group": group}
	return nearest


func _nearest_finish_face(mesh: Mesh, origin: Vector3, ray: Vector3) -> Variant:
	var faces := mesh.get_faces()
	var nearest: Variant = null
	var distance := INF
	for index in range(0, faces.size(), 3):
		var hit = Geometry3D.ray_intersects_triangle(origin, ray, faces[index], faces[index + 1], faces[index + 2])
		if hit != null and origin.distance_squared_to(hit) < distance:
			distance = origin.distance_squared_to(hit)
			nearest = hit
	return nearest


func _find_plot_wall_face(pixel: Vector2) -> Dictionary:
	var props := map.get_node_or_null("Props") as Node3D
	if props == null or not is_instance_valid(camera):
		return {}
	var origin := camera.project_ray_origin(pixel)
	var ray := camera.project_ray_normal(pixel)
	var nearest := {}
	for node in props.get_children():
		if node is not Node3D or node.get_meta(Plot.META, "") != _plan_selected_id or int(node.get_meta(Plot.LEVEL_META, 0)) != _plot_level:
			continue
		var hit := Plot.wall_face_hit(node, origin, ray, map.imported_tile_size)
		if not hit.is_empty() and hit.distance < nearest.get("distance", INF):
			nearest = hit
	return nearest


func _place_plot_pilaster() -> String:
	if not _plot_pilaster_hit.get("fits", false):
		return "Нужен глухой участок стены шириной не менее 0,75 м на выбранном этаже."
	var props := map.get_node_or_null("Props") as Node3D
	var plan: Resource = TerrainPlan.read(map)
	var index: int = plan.index_of(_plan_selected_id) if plan != null else -1
	if props == null or index < 0 or plan.regions[index].get("kind") != "construction":
		return "Выберите строительный участок."
	var point: Vector3 = _plot_pilaster_hit.point
	var local: Vector3 = map._visual_surface_projection.to_local(props.to_global(point))
	if not TerrainPlan.Influence.plot_has_point(plan.regions[index], Vector2(local.x, local.z) / 16.0):
		return "Пилястра должна быть внутри участка."
	var angle: float = _plot_pilaster_hit.angle
	var outward := Vector3.BACK.rotated(Vector3.UP, angle)
	var width := Plot.PILASTER_HALF_WIDTH * 2.0 * map.imported_tile_size
	for node in props.get_children():
		if node is Node3D and node.has_node("Pilaster") and node.basis.z.dot(outward) > 0.99 and node.position.distance_to(point) < width:
			return "На этом месте уже есть пилястра."
	var node := Plot.make_pilaster(point, angle, map.imported_tile_size)
	node.set_meta(Plot.META, _plan_selected_id)
	node.set_meta(Plot.LEVEL_META, _plot_level)
	_commit_plot_node(props, node, "Поставить пилястру")
	_reset_plot_tool()
	return "Готово · Ctrl+Z отменяет · Ctrl+S сохраняет."


func _plot_pointer_y(props: Node3D) -> float:
	if props == null:
		return INF
	if _plot_follow_floor:
		return _plot_level_y(props) + Plot.FLOOR_TOP_M * map.imported_tile_size
	if _plot_tool == "plot_arc_wall" and _plot_arc_walk:
		if not _plot_start_dock.is_empty():
			return _plot_start_dock.y
		return _plot_level_y(props) + (Plot.WALL_HEIGHT_M + Plot.FLOOR_TOP_M) * map.imported_tile_size
	if _plot_tool == "plot_round_corner":
		return _plot_level_y(props) + Plot.WALL_HEIGHT_M * map.imported_tile_size
	if _plot_tool in ["plot_wall", "plot_arc_wall", "plot_floor"]:
		return _plot_level_y(props) + Plot.BALCONY_TOP * map.imported_tile_size
	if _plot_level > 0 or _plot_tool in ["plot_column", "plot_cornice", "plot_roof", "plot_railing"]:
		return _plot_plane_y(props)
	return INF


func _plot_grid_world(projection: Node3D, props: Node3D, point: Vector2, height: float) -> Vector3:
	var local := props.to_local(projection.to_global(Vector3(point.x, 0, point.y) * 16.0))
	local.y = height
	return props.to_global(local)


func _plot_point_pixel(point: Vector2) -> Vector2:
	if not point.is_finite() or not is_instance_valid(camera):
		return Vector2.INF
	var props := map.get_node_or_null("Props") as Node3D
	var height := _plot_pointer_y(props)
	if not is_finite(height):
		return _plan_point_pixel(point) if _plot_level == 0 else Vector2.INF
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	if not is_instance_valid(projection):
		return Vector2.INF
	var world := _plot_grid_world(projection, props, point, height)
	return Vector2.INF if camera.is_position_behind(world) else camera.unproject_position(world)


func _draw_plot_grid(overlay: Control, region: Dictionary) -> void:
	if not is_instance_valid(_plan_panel) or not _plan_panel.visible or not _plan_panel._buttons.plot_grid.button_pressed:
		return
	var props := map.get_node_or_null("Props") as Node3D
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	if props == null or not is_instance_valid(projection) or not is_instance_valid(camera):
		return
	var level: int = _plan_panel._buttons.plot_level.selected
	var bounds := TerrainPlan.Influence.plot_rect(region)
	var frame := TerrainPlan.Influence.plot_frame(region)
	var origin := Plot.level_origin(props, _plan_selected_id, map.imported_tile_size)
	if not is_finite(origin) and level == 0:
		origin = _plot_ground(frame * bounds.get_center(), props).y
	if not is_finite(origin):
		return
	var height := origin + (level * Plot.WALL_HEIGHT_M + Plot.BALCONY_TOP) * map.imported_tile_size
	# Keep the meter lines aligned to the snap origin, even on very large plots.
	var step := maxi(1, ceili(maxi(bounds.size.x, bounds.size.y) / 48.0))
	for x in range(ceili(bounds.position.x / step) * step, floori(bounds.end.x) + 1, step):
		_draw_plot_grid_line(overlay, projection, props, frame * Vector2(x, bounds.position.y), frame * Vector2(x, bounds.end.y), height)
	for z in range(ceili(bounds.position.y / step) * step, floori(bounds.end.y) + 1, step):
		_draw_plot_grid_line(overlay, projection, props, frame * Vector2(bounds.position.x, z), frame * Vector2(bounds.end.x, z), height)
	if _plot_tool not in ["plot_wall", "plot_arc_wall", "plot_floor", "plot_column", "plot_railing"] or not _plot_cursor.is_finite():
		return
	var cursor := frame.affine_inverse() * _plot_cursor
	if not bounds.has_point(cursor):
		return
	var center := _plot_grid_world(projection, props, _plot_cursor, height)
	var x_neighbor := _plot_grid_world(projection, props, frame * (cursor + Vector2.RIGHT * Plot.GRID_SNAP_M), height)
	var z_neighbor := _plot_grid_world(projection, props, frame * (cursor + Vector2.DOWN * Plot.GRID_SNAP_M), height)
	if camera.is_position_behind(center) or camera.is_position_behind(x_neighbor) or camera.is_position_behind(z_neighbor):
		return
	var pixel := camera.unproject_position(center)
	if minf(pixel.distance_to(camera.unproject_position(x_neighbor)), pixel.distance_to(camera.unproject_position(z_neighbor))) < 8.0:
		return
	var lo := (cursor - Vector2.ONE * 2.0).max(bounds.position)
	var hi := (cursor + Vector2.ONE * 2.0).min(bounds.end)
	for x in range(roundi(lo.x / Plot.GRID_SNAP_M), roundi(hi.x / Plot.GRID_SNAP_M) + 1):
		var line := x * Plot.GRID_SNAP_M
		_draw_plot_grid_line(overlay, projection, props, frame * Vector2(line, lo.y), frame * Vector2(line, hi.y), height, 0.18)
	for z in range(roundi(lo.y / Plot.GRID_SNAP_M), roundi(hi.y / Plot.GRID_SNAP_M) + 1):
		var line := z * Plot.GRID_SNAP_M
		_draw_plot_grid_line(overlay, projection, props, frame * Vector2(lo.x, line), frame * Vector2(hi.x, line), height, 0.18)


func _draw_plot_grid_line(overlay: Control, projection: Node3D, props: Node3D, from: Vector2, to: Vector2, height: float, opacity := 0.3) -> void:
	var a := camera.to_local(_plot_grid_world(projection, props, from, height))
	var b := camera.to_local(_plot_grid_world(projection, props, to, height))
	var near_z := -camera.near * 1.01
	if a.z > near_z and b.z > near_z:
		return
	if a.z > near_z:
		a = a.lerp(b, (near_z - a.z) / (b.z - a.z))
	elif b.z > near_z:
		b = b.lerp(a, (near_z - b.z) / (a.z - b.z))
	overlay.draw_line(camera.unproject_position(camera.to_global(a)), camera.unproject_position(camera.to_global(b)),
		Color(0.56, 0.86, 0.91, opacity), 1.0, true)


func _draw_plot_corner(overlay: Control, region: Dictionary) -> void:
	var props := map.get_node_or_null("Props") as Node3D
	if props == null:
		return
	var layout := _plot_corner_layout(props, _plot_cursor, TerrainPlan.Influence.plot_rect(region),
		TerrainPlan.Influence.plot_frame(region).affine_inverse())
	if not layout.has("arc"):
		return
	var color := Color(1.0, 0.7, 0.32)
	var ring: PackedVector2Array = layout.arc.left.duplicate()
	var other: PackedVector2Array = layout.arc.right.duplicate()
	other.reverse()
	ring.append_array(other)
	ring.append(ring[0])
	for index in ring.size() - 1:
		var a := _plot_point_pixel(ring[index])
		var b := _plot_point_pixel(ring[index + 1])
		if a.is_finite() and b.is_finite():
			overlay.draw_line(a, b, color, 3.0, true)
	var corner := _plot_point_pixel(layout.corner)
	if corner.is_finite():
		overlay.draw_circle(corner, 5.0, color, false, 2.0, true)


func _draw_contour_attachment(overlay: Control, region: Dictionary) -> void:
	var props := map.get_node_or_null("Props") as Node3D
	if props == null or not _plot_cursor.is_finite():
		return
	var roof := _plot_tool == "plot_roof"
	var target := _plot_contour_target(props, _plot_cursor, roof)
	if target.is_empty():
		return
	var outline := Plot.contour_roof_outline(target.profile) if roof else Plot.round_rail_path(target.profile, _plot_cursor - target.center, _plot_railing_style)
	if roof and not _plot_outline_fits(TerrainPlan.Influence.plot_rect(region), target.center, outline,
			TerrainPlan.Influence.plot_frame(region).affine_inverse()):
		return
	var height: float = target.floor.position.y + (Plot.WALL_HEIGHT_M if roof else Plot.FLOOR_TOP_M) * map.imported_tile_size
	var projection: Node3D = map._visual_surface_projection
	for index in outline.size() if roof else outline.size() - 1:
		var a := _plot_grid_world(projection, props, target.center + outline[index], height)
		var b := _plot_grid_world(projection, props, target.center + outline[(index + 1) % outline.size()], height)
		if not camera.is_position_behind(a) and not camera.is_position_behind(b):
			overlay.draw_line(camera.unproject_position(a), camera.unproject_position(b), Color(1.0, 0.7, 0.32), 3.0, true)


func _forward_street_preview(event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_street_plot_action("street_clear", _plan_selected_id)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is not InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or event.alt_pressed \
			or event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event.pressed:
		var point := _path_pick(event.position)
		var lots: Array[Dictionary] = _street_preview.lots
		var excluded: Dictionary = _street_preview.excluded
		for slot in lots.size():
			if not TerrainPlan.Influence.plot_has_point(lots[slot], point):
				continue
			if excluded.has(slot):
				excluded.erase(slot)
			else:
				excluded[slot] = true
			_plan_panel.show_street_preview(lots.size() - excluded.size(), lots.size())
			_update_overlay()
			break
	return EditorPlugin.AFTER_GUI_INPUT_STOP


func _draw_street_preview(overlay: Control) -> void:
	var lots: Array[Dictionary] = _street_preview.lots
	for slot in lots.size():
		var lot := lots[slot]
		var pixels := PackedVector2Array()
		for point in TerrainPlan.Influence.plan_controls(lot):
			var pixel := _plan_point_pixel(point)
			if not pixel.is_finite():
				break
			pixels.append(pixel)
		if pixels.size() != 4:
			continue
		var included: bool = not _street_preview.excluded.has(slot)
		var color := Color("74f4d3") if included else Color("a7a9af")
		overlay.draw_colored_polygon(pixels, Color(color, 0.21 if included else 0.08))
		pixels.append(pixels[0])
		overlay.draw_polyline(pixels, Color(0.05, 0.12, 0.13, 0.9), 5.0, true)
		overlay.draw_polyline(pixels, color, 2.0, true)
		var key: Vector2 = lot.plot_frame.origin
		if included and _street_preview.layouts.has(key):
			var layout: Dictionary = _street_preview.layouts[key]
			for run: PackedVector2Array in layout.runs:
				var line := PackedVector2Array()
				for point in run:
					var pixel := _plan_point_pixel(point)
					if pixel.is_finite():
						line.append(pixel)
				if line.size() >= 2:
					overlay.draw_polyline(line, color, 3.0, true)
			var gate := _plan_point_pixel(layout.approach[0])
			var road := _plan_point_pixel(layout.approach[1])
			if gate.is_finite() and road.is_finite():
				var entrance := Color("ffd18a")
				overlay.draw_line(gate, road, entrance, 3.0, true)
				overlay.draw_circle(gate, 5.0, entrance, true, -1.0, true)
		var center := _plan_point_pixel(TerrainPlan.Influence.plan_anchor(lot))
		if center.is_finite():
			overlay.draw_circle(center, 12.0, Color(0.05, 0.12, 0.13, 0.9), true, -1.0, true)
			overlay.draw_string(ThemeDB.fallback_font, center + Vector2(-5, 5), str(slot + 1) if included else "×",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 17, color)


func _draw_terrain_plan(overlay: Control) -> bool:
	if not _street_preview.is_empty():
		_draw_street_preview(overlay)
	if _plot_pilaster_hit.get("fits", false) and is_instance_valid(camera):
		var props := map.get_node_or_null("Props") as Node3D
		if props != null:
			var a := props.to_global(_plot_pilaster_hit.point)
			var b := a + props.global_basis.y * Plot.WALL_HEIGHT_M * map.imported_tile_size
			if not camera.is_position_behind(a) and not camera.is_position_behind(b):
				overlay.draw_line(camera.unproject_position(a), camera.unproject_position(b), Color(1.0, 0.7, 0.32), 4.0, true)
	if _plot_anchor.is_finite() and _plot_cursor.is_finite():
		var points: PackedVector2Array
		if _plot_tool == "plot_roof":
			points = PackedVector2Array()
			var frame := _selected_plot_frame()
			var inverse := frame.affine_inverse()
			var a := inverse * _plot_anchor
			var b := inverse * _plot_cursor
			var origin := a.min(b)
			var border := Plot.roof_border((a - b).abs(), _plot_roof_options.bay)
			for index in border.size():
				points.append(frame * (origin + border[index]))
				points.append(frame * (origin + border[(index + 1) % border.size()]))
		elif _plot_tool == "plot_floor":
			if _plot_floor_shape.is_empty():
				var frame := _selected_plot_frame()
				var inverse := frame.affine_inverse()
				var a := inverse * _plot_anchor
				var b := inverse * _plot_cursor
				var corners := TerrainPlan.Influence.rectangle_points(Rect2(a.min(b), (a - b).abs()), frame)
				points = PackedVector2Array([corners[0], corners[1], corners[1], corners[2], corners[2], corners[3], corners[3], corners[0]])
			else:
				var layout := _plot_contour_layout(_plot_cursor)
				points = PackedVector2Array()
				if not layout.profile.is_empty():
					var rim := Plot.floor_outline(layout.profile)
					for index in rim.size():
						points.append(layout.center + rim[index])
						points.append(layout.center + rim[(index + 1) % rim.size()])
		elif _plot_tool in ["plot_wall", "plot_cornice", "plot_railing"]:
			points = PackedVector2Array([_plot_anchor, _plot_cursor])
		elif _plot_tool == "plot_arc_wall":
			points = PackedVector2Array([_plot_anchor, _plot_cursor])
			if _plot_arc_through.is_finite():
				var arc := _plot_arc_layout(_plot_cursor)
				points = PackedVector2Array([_plot_anchor, _plot_arc_through, _plot_arc_through, _plot_cursor])
				if _plot_docking and arc.is_empty():
					points = PackedVector2Array([_plot_anchor, _plot_arc_through])
				if not arc.is_empty():
					points.clear()
					for edge: PackedVector2Array in [arc.left, arc.right]:
						for index in edge.size() - 1:
							points.append(edge[index])
							points.append(edge[index + 1])
					points.append_array(PackedVector2Array([arc.left[0], arc.right[0], arc.left[-1], arc.right[-1]]))
		elif _plot_tool in ["plot_entry", "plot_edge", "plot_balcony"]:
			var depth := _plot_balcony_depth if _plot_tool == "plot_balcony" else _plot_edge_depth
			var corners := Plot.entry_outline(_plot_anchor, _plot_cursor) if _plot_tool == "plot_entry" else Plot.strip_outline(_plot_anchor, _plot_cursor, depth)
			points = PackedVector2Array([corners[0], corners[1], corners[1], corners[2], corners[2], corners[3], corners[3], corners[0]])
		else:
			points = Plot.fence_points(_plot_anchor, _plot_cursor)
		var props := map.get_node_or_null("Props") as Node3D
		var projection := map._visual_surface_projection as EmberTerrainPilotProjection
		var height := _plot_pointer_y(props)
		if _plot_tool == "plot_arc_wall" and props != null and not is_finite(height) and _plot_level == 0:
			height = _plot_ground(_plot_anchor, props).y
		if is_instance_valid(camera) and projection != null and is_finite(height):
			for start in range(0, points.size(), 2):
				var a := _plot_grid_world(projection, props, points[start], height)
				var b := _plot_grid_world(projection, props, points[start + 1], height)
				if not camera.is_position_behind(a) and not camera.is_position_behind(b):
					overlay.draw_line(camera.unproject_position(a), camera.unproject_position(b), Color(1.0, 0.7, 0.32), 3.0, true)
		else:
			for start in range(0, points.size(), 2):
				var a := _plot_point_pixel(points[start])
				var b := _plot_point_pixel(points[start + 1])
				if a.is_finite() and b.is_finite():
					overlay.draw_line(a, b, Color(1.0, 0.7, 0.32), 3.0, true)
	if _plot_tool == "plot_fountain" and _plot_cursor.is_finite():
		var radius: float = Plot.FOUNTAIN_RADII[_plot_fountain_style]
		var points := PackedVector2Array()
		for index in 25:
			var edge := _plot_cursor + Vector2.from_angle(TAU * float(index) / 24.0) * radius
			var pixel := _plot_point_pixel(edge)
			if pixel.is_finite():
				points.append(pixel)
		if points.size() == 25:
			overlay.draw_polyline(points, Color(1.0, 0.7, 0.32), 2.0, true)
	if _plot_tool in ["plot_wall", "plot_arc_wall", "plot_floor", "plot_column", "plot_apple_tree", "plot_fountain", "plot_fence", "plot_railing"]:
		var anchor := _plot_point_pixel(_plot_anchor)
		var cursor := _plot_point_pixel(_plot_cursor)
		if anchor.is_finite():
			overlay.draw_circle(anchor, 5.0, Color(1.0, 0.7, 0.32), true, -1.0, true)
		if _plot_arc_through.is_finite():
			var through := _plot_point_pixel(_plot_arc_through)
			if through.is_finite():
				overlay.draw_circle(through, 5.0, Color(1.0, 0.7, 0.32), true, -1.0, true)
		if cursor.is_finite():
			overlay.draw_circle(cursor, 6.0, Color(0.13, 0.17, 0.21), true, -1.0, true)
			overlay.draw_circle(cursor, 4.0, Color.WHITE, false, 2.0, true)
	if _plot_docking and (not _plot_anchor.is_finite() or _plot_arc_through.is_finite()):
		var target := _plot_dock_at(_plot_cursor)
		var props := map.get_node_or_null("Props") as Node3D
		for dock in _plot_docks:
			if props == null or not is_instance_valid(dock.tower) or dock.tower == _plot_start_dock.get("tower"):
				continue
			var pixel := _plot_dock_pixel(dock, props)
			if pixel.is_finite():
				var compatible := _plot_start_dock.is_empty() or _plot_docks_match(dock)
				overlay.draw_circle(pixel, 7.0, Color(0.34, 0.95, 0.84) if compatible else Color(0.9, 0.45, 0.35), dock == target, 2.0, true)
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
	var snap_point := Vector2.INF
	var snap_support: EmberVoxelProp
	var snap_axis := false
	if _plan_selection in ["add_river","add_road","add_surface_road","add_road_branch","extend_road_branch","add_coast","path_line"] and _surface_road_preview.is_empty():
		var points := _path_points.duplicate()
		if not _surface_road_support.is_empty():
			snap_support = _surface_road_prop(map, _surface_road_support)
		if _path_hover.x >= 0 and (points.is_empty() or _path_hover.distance_to(points[-1]) >= 1) and not (_plan_selection == "add_surface_road" and snap_support == null):
			snap_point = _path_hover
			snap_axis = _plan_selection == "add_road_branch" and points.is_empty()
			points.append(_path_hover)
		_draw_plan_path(overlay,points,Color(0.3,0.9,1),"draft",_plan_path_kind() == "river",snap_support)
		for point in _path_points:
			_draw_path_handle(overlay, _path_surface_pixel(point, snap_support), Color("76ecff"))
	var plan: Resource = TerrainPlan.read(map)
	if plan == null: return false
	var bridge_start: Dictionary = _street_bridge.get("start", {})
	if not bridge_start.is_empty():
		_draw_plan_path(overlay, PackedVector2Array([bridge_start.point]), Color(0.3, 0.9, 1.0), "bridge")
	var plot_outline := false
	for saved: Dictionary in plan.regions:
		var selected:bool=saved.id==_plan_selected_id
		if selected and _plan_selection == "extend_road_branch":
			continue
		var region:Dictionary=_plan_drag.ghost if selected and not _plan_drag.is_empty() else _branch_edit.get("region", saved) if selected else saved
		if selected and region.get("kind") == "construction":
			plot_outline = true
			if _plan_drag.is_empty() and _plan_selection.is_empty():
				_draw_plot_grid(overlay, region)
				if _plot_tool == "plot_round_corner":
					_draw_plot_corner(overlay, region)
				if _plot_follow_floor:
					_draw_contour_attachment(overlay, region)
		var path:=TerrainPlan.Influence.plan_is_path(region)
		var support: EmberVoxelProp = _plan_path_support(region) if path and selected else null
		var color:=Color(1,0.75,0.3) if selected else Color(0.4,0.75,0.9,0.65)
		if path:
			_draw_plan_path(overlay,region.points_m,color,region.id,region.kind in ["river","coast"] or (selected and not _street_preview.is_empty()),support)
		else:
			var pixels:=PackedVector2Array()
			for point in TerrainPlan.Influence.plan_controls(region):
				var pixel:=_plan_point_pixel(point)
				if not pixel.is_finite():pixels.clear();break
				pixels.append(pixel)
			if pixels.size()==4:
				pixels.append(pixels[0]);overlay.draw_polyline(pixels,color,2.5 if selected else 1.5,true)
				overlay.draw_string(ThemeDB.fallback_font,pixels[0]+Vector2(4,-7),region.name,HORIZONTAL_ALIGNMENT_LEFT,-1,14,color)
		if not selected or not _plan_selection.is_empty():continue
		if _plan_point_mode=="translate":
			var centre:=_plan_point_pixel(TerrainPlan.Influence.plan_anchor(region))
			if centre.is_finite():
				overlay.draw_circle(centre,10,Color(0.05,0.25,0.3,0.9))
				overlay.draw_line(centre-Vector2(7,0),centre+Vector2(7,0),Color.WHITE,2,true)
				overlay.draw_line(centre-Vector2(0,7),centre+Vector2(0,7),Color.WHITE,2,true)
		else:
			var points:=TerrainPlan.Influence.plan_controls(region)
			for i in points.size():
				var pixel := _path_surface_pixel(points[i], support) if path else _plan_point_pixel(points[i])
				if not pixel.is_finite():continue
				if path:
					var locked := i == 0 and region.has("road_join")
					var emphasized := i == _plan_hover_index or i == _plan_point_index
					var ink := Color("ffd477") if locked else Color("76ecff") if emphasized else Color.WHITE
					_draw_path_handle(overlay, pixel, ink, emphasized)
					if i == _plan_hover_index and _plan_point_mode != "insert" or (not _plan_drag.is_empty() and i == _plan_drag.index):
						snap_point = points[i]
						snap_support = support
						snap_axis = locked
				else:
					overlay.draw_rect(Rect2(pixel-Vector2.ONE*5,Vector2.ONE*10),Color.WHITE)
					overlay.draw_circle(pixel,3,Color(0.1,0.7,1))
			if path and _plan_point_mode == "insert" and _plan_insert_hover.is_finite():
				snap_point = _plan_insert_hover
				snap_support = support
	if snap_point.is_finite():
		_draw_path_snap(overlay, snap_point, 0.25 if is_instance_valid(snap_support) else 0.5, snap_support, snap_axis)
	return plot_outline

func draw_overlay(overlay: Control) -> void:
	if not active or not is_instance_valid(camera): return
	if _section_mode:
		_draw_section_selection(overlay)
		return
	if _compact_active():
		var plot_outline := _draw_terrain_plan(overlay)
		var selected_rect := region_preview if selecting and region_preview.has_area() else edit_region
		if selected_rect.has_area() and (selecting or not plot_outline or not _plan_map_active()):
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
	if _mode()=="paint" and hover.get("normal",Vector3.UP).y<=0.8:view_key+="|%s|%s"%[hover.local,hover.normal]
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
	var side:bool=_mode()=="paint" and hover.get("normal",Vector3.UP).y<=0.8
	_compact_grid_material.set_shader_parameter("side_paint",side)
	if side:
		_compact_grid_material.set_shader_parameter("side_center",hover.local)
		_compact_grid_material.set_shader_parameter("side_normal",hover.normal)
		_compact_grid_material.set_shader_parameter("brush_radius",radius.value*16.0)
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
	for retired in _smooth_retired:WorkerThreadPool.wait_for_task_completion(retired.task_id)
	_smooth_retired.clear()
	sessions.release()


# Coast uses the existing plan command/history and 2D overlay. Drag only moves
# the editor's temporary line; validation and a single Undo happen on release.
func _plan_map_active()->bool:
	return _plan_selection.is_empty() and is_instance_valid(_plan_panel) and _plan_panel.visible and is_instance_valid(_terrain_workspace) and _terrain_workspace.visible and _plan_target!=null and _plan_target.get_ref()==map

func _plan_parameters_active()->bool:
	return is_instance_valid(_generation_panel) and _generation_panel.visible and not _generation_context.get("plan_id","").is_empty()

func _select_plan_region(id:String)->void:
	if not _branch_edit.is_empty() and id != _plan_selected_id:
		_refresh_terrain_plan(true)
		_plan_panel.set_status("Сначала примерьте правки ответвления или отмените их клавишей Esc.")
		return
	_plan_selected_id=id;_plan_point_index=-1;_plan_cancel_drag()
	_plan_hover_index = -1
	_plan_insert_hover = Vector2.INF
	var plan: Resource = TerrainPlan.read(map)
	var index: int = plan.index_of(id) if plan != null else -1
	if index >= 0 and plan.regions[index].has("road_join"):
		_plan_point_mode = "move"
		clear_terrain_generation_preview()
		if is_instance_valid(_generation_panel):
			_generation_panel.hide()
		_generation_context = {}
		_refresh_terrain_plan(true)
		_plan_panel.set_status("Жёлтая точка закреплена на главной дороге. Остальные точки можно двигать.")
		return
	_refresh_terrain_plan()
	if not id.is_empty():_terrain_plan_action("generate",id,"")
	_update_overlay()

func _sync_plan_context()->void:
	if not _plan_parameters_active():return
	var plan:Resource=TerrainPlan.read(map)
	var index:int=plan.index_of(_plan_selected_id) if plan!=null else -1
	if index<0:_open_terrain_plan();return
	if _generation_context.get("plan_id","")!=_plan_selected_id:
		_terrain_plan_action("generate",_plan_selected_id,"");return
	var previous:Dictionary={}
	for region:Dictionary in _generation_context.get("plan_version",{}).get("regions",[]):
		if region.id==_plan_selected_id:previous=region;break
	if not previous.is_empty() and (previous.parameters!=plan.regions[index].parameters or previous.get("kind")!=plan.regions[index].get("kind")):
		_terrain_plan_action("generate",_plan_selected_id,"");return
	_generation_context.plan_version=plan.data();_generation_context.area=plan.regions[index].bounds
	_generation_panel.update_plan_bounds(plan.regions[index].bounds)
	_generation_panel.set_pending("Контур изменён. Обнови предпросмотр.")

func _plan_handle_world(point:Vector2)->Vector3:
	if entry.is_empty() or not is_instance_valid(map):return Vector3.INF
	var source:EmberTerrainPilotResource=entry.resource
	var cell:=Vector2i(clampi(floori(point.x*16),0,source.width-1),clampi(floori(point.y*16),0,source.depth-1))
	if not source.has_column(cell.x,cell.y):return Vector3.INF
	var index:=source.column_index(cell.x,cell.y)
	var height:=maxi(source.column_value("heights",index),source.column_value("water_levels",index))+source.origin_y
	return map._visual_surface_projection.to_global(Vector3(point.x*16.0,height+2,point.y*16.0))

func _plan_point_pixel(point:Vector2)->Vector2:
	if not is_instance_valid(camera):return Vector2.INF
	var p:=_plan_handle_world(point)
	return Vector2.INF if not p.is_finite() or camera.is_position_behind(p) else camera.unproject_position(p)

func _plan_path_support(region: Dictionary) -> EmberVoxelProp:
	var id: String = region.get("support_placement_id", "")
	return _surface_road_prop(map, id) if not id.is_empty() else null


func _plan_point_at(points:PackedVector2Array,pixel:Vector2,path := false,support: EmberVoxelProp = null)->int:
	var found:=-1;var nearest:=PATH_HIT_RADIUS if path else 13.0
	for i in points.size():
		var p := _path_surface_pixel(points[i], support) if path else _plan_point_pixel(points[i])
		if p.is_finite() and p.distance_to(pixel)<nearest:nearest=p.distance_to(pixel);found=i
	return found

func _plan_region_at(pixel:Vector2)->String:
	var plan:Resource=TerrainPlan.read(map)
	if plan==null:return ""
	var closest:="";var distance:=13.0
	for region:Dictionary in plan.regions:
		if not TerrainPlan.Influence.plan_is_path(region):continue
		var hit:=_plan_path_hit(region,pixel)
		if hit.distance<distance:distance=hit.distance;closest=region.id
	if not closest.is_empty():return closest
	var point:=_path_pick(pixel)
	if point.x<0:return ""
	var area:=INF
	for region:Dictionary in plan.regions:
		if not TerrainPlan.Influence.plot_has_point(region, point):continue
		if region.get("kind")=="coast":
			if not TerrainPlan.Influence.coast_sample(TerrainPlan.Influence.path_curve(region.points_m),point,region.parameters).is_empty():return region.id
		elif not TerrainPlan.Influence.plan_is_path(region) and region.bounds.get_area()<area:area=region.bounds.get_area();closest=region.id
	return closest

func _plan_path_hit(region:Dictionary,pixel:Vector2)->Dictionary:
	var result:Dictionary={"distance":INF,"point":Vector2.INF}
	var samples:PackedVector2Array=TerrainPlan.Influence.path_curve(region.points_m).get_baked_points()
	if samples.is_empty():
		return result
	var support := _plan_path_support(region)
	var a := _path_surface_pixel(samples[0], support)
	for i in range(1,samples.size()):
		var b := _path_surface_pixel(samples[i], support)
		if a.is_finite() and b.is_finite():
			var projected:=Geometry2D.get_closest_point_to_segment(pixel,a,b)
			var distance:=pixel.distance_to(projected)
			if distance < result.distance:
				var fraction:=0.0 if a.distance_squared_to(b)<0.00001 else a.distance_to(projected)/a.distance_to(b)
				result={"distance":distance,"point":samples[i-1].lerp(samples[i],fraction)}
		a = b
	return result


func _plan_insert_target(region: Dictionary, pixel: Vector2) -> Vector2:
	var on_line := _plan_path_hit(region, pixel)
	if on_line.distance >= PATH_HIT_RADIUS:
		return Vector2.INF
	var step := 0.25 if region.has("support_placement_id") else 0.5
	var point: Vector2 = on_line.point.snapped(Vector2.ONE * step)
	for existing: Vector2 in region.points_m:
		if point.distance_to(existing) < 1.0:
			return Vector2.INF
	return point

func commit_plan_shape(target:EmberMapLoader,id:String,shape:Dictionary)->String:
	var plan:Resource=TerrainPlan.read(target)
	var index:int=plan.index_of(id) if plan!=null else -1
	if index<0:return "Область больше недоступна."
	var draft:=sessions.open_map(target,scene)
	if draft.is_empty():return sessions.error
	var next:Resource=plan.working_copy()
	if TerrainPlan.Influence.plan_is_path(plan.regions[index]):
		var points:PackedVector2Array=shape.points_m
		var extent:=Vector2i(draft.resource.width/16,draft.resource.depth/16)
		var error:=TerrainPlan.Influence.path_error(points,extent)
		if not error.is_empty():return error
		for point in TerrainPlan.Influence.path_curve(points).get_baked_points():
			if not Rect2(Vector2.ZERO,Vector2(extent)).has_point(point):return "Изгиб линии выходит за карту."
		next.regions[index].points_m=points.duplicate()
		next.regions[index].bounds=_plan_path_bounds(next.regions[index],next.regions[index].parameters,extent)
	else:
		next.regions[index].bounds = shape.bounds
		if next.regions[index].has("plot_frame"):
			next.regions[index].plot_frame = shape.plot_frame
			next.regions[index].plot_size_m = shape.plot_size_m
	return commit_terrain_plan(target,next)

func commit_plan_points(target:EmberMapLoader,id:String,points:PackedVector2Array)->String:
	var plan:Resource=TerrainPlan.read(target)
	var index:int=plan.index_of(id) if plan!=null else -1
	if index<0 or not TerrainPlan.Influence.plan_is_path(plan.regions[index]):return "Выберите линию."
	return commit_plan_shape(target,id,{"points_m":points})

func _plan_cancel_drag()->void:
	_plan_drag.clear();_update_overlay()

func _plan_drag_position(pixel:Vector2)->Vector2:
	var projection:Node3D=map._visual_surface_projection
	var origin:=projection.to_local(camera.project_ray_origin(pixel))
	var ray:=projection.global_basis.inverse()*camera.project_ray_normal(pixel)
	var point:Variant=Plane(Vector3.UP,float(_plan_drag.plane_y)).intersects_ray(origin,ray)
	return Vector2.INF if point==null else Vector2(point.x,point.z)/16.0

func _plan_begin_drag(region:Dictionary,index:int,pixel:Vector2,translate:bool)->void:
	if region.has("road_join") and (translate or index == 0):
		_plan_panel.set_status("Начало ответвления закреплено на главной дороге.")
		return
	var handle:Vector2=TerrainPlan.Influence.plan_anchor(region) if translate else TerrainPlan.Influence.plan_controls(region)[index]
	var p := _path_surface_world(handle, _plan_path_support(region)) if TerrainPlan.Influence.plan_is_path(region) else _plan_handle_world(handle)
	if not p.is_finite():return
	clear_terrain_generation_preview()
	if _plan_parameters_active():_generation_panel.set_pending("Перенос контура. Земля пока не меняется.")
	_plan_drag={"index":index,"translate":translate,"region":region.duplicate(true),"ghost":region.duplicate(true),"version":TerrainPlan.read(map).data(),"plane_y":map._visual_surface_projection.to_local(p).y,"watch_release":Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)}
	_plan_drag.anchor=_plan_drag_position(pixel)
	if not _plan_drag.anchor.is_finite():_plan_cancel_drag()

func _forward_plan_map(event:InputEvent)->int:
	if event is InputEventMouse and (event.alt_pressed or event.button_mask&(MOUSE_BUTTON_MASK_RIGHT|MOUSE_BUTTON_MASK_MIDDLE)):
		_plan_hover_index = -1
		_plan_insert_hover = Vector2.INF
		_plan_cancel_drag();return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
		_plan_cancel_drag();return EditorPlugin.AFTER_GUI_INPUT_PASS
	var plan:Resource=TerrainPlan.read(map)
	var index:int=plan.index_of(_plan_selected_id) if plan!=null else -1
	var path:bool=index>=0 and TerrainPlan.Influence.plan_is_path(plan.regions[index])
	var current: Dictionary = _branch_edit.get("region", plan.regions[index]) if index >= 0 else {}
	if event is InputEventKey:
		if not event.pressed or event.echo:return EditorPlugin.AFTER_GUI_INPUT_PASS
		if event.is_command_or_control_pressed() and event.keycode in [KEY_Z,KEY_Y]:
			if not _plan_drag.is_empty():_plan_cancel_drag();return EditorPlugin.AFTER_GUI_INPUT_STOP
			if not _branch_edit.is_empty():
				_branch_edit.clear()
				_refresh_terrain_plan()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if event.keycode == KEY_ENTER and not _branch_edit.is_empty():
			_preview_branch_edits()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode==KEY_ESCAPE:
			if not _plan_drag.is_empty():_plan_cancel_drag()
			elif not _branch_edit.is_empty():
				_branch_edit.clear()
				_refresh_terrain_plan()
				_plan_panel.set_status("Черновик ответвления отменён.")
			else:_plan_point_mode="move";_plan_panel.set_point_mode("move")
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode in [KEY_DELETE,KEY_BACKSPACE] and path and _plan_point_mode!="translate":
			_plan_remove_point(current.points_m,_plan_point_index);return EditorPlugin.AFTER_GUI_INPUT_STOP
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion:
		if not _plan_drag.is_empty():
			var point:=_plan_drag_position(event.position)
			if point.is_finite():_plan_drag.ghost=TerrainPlan.Influence.plan_edit(_plan_drag.region,_plan_drag.index,point-_plan_drag.anchor,_plan_drag.translate);_update_overlay()
		elif path:
			_plan_hover_index = _plan_point_at(current.points_m, event.position, true, _plan_path_support(current))
			_plan_insert_hover = _plan_insert_target(current, event.position) if _plan_point_mode == "insert" else Vector2.INF
			_update_overlay()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_LEFT:return EditorPlugin.AFTER_GUI_INPUT_PASS
	if not event.pressed:
		if not _plan_drag.is_empty():_plan_finish_drag()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if index>=0:
		var region:Dictionary=current
		var points:PackedVector2Array=TerrainPlan.Influence.plan_controls(region)
		if _plan_point_mode=="translate":
			var centre:=_plan_point_pixel(TerrainPlan.Influence.plan_anchor(region))
			if centre.is_finite() and centre.distance_to(event.position)<14:
				_plan_begin_drag(region,-1,event.position,true);return EditorPlugin.AFTER_GUI_INPUT_STOP
		else:
			var hit := _plan_point_at(points, event.position, path, _plan_path_support(region) if path else null)
			if hit >= 0 and _plan_point_mode != "insert":
				_plan_hover_index = hit
				_plan_point_index=hit;_plan_panel.set_point_selection(hit,points.size())
				if path and _plan_point_mode=="remove":_plan_remove_point(points,hit)
				elif _plan_point_mode=="move":_plan_begin_drag(region,hit,event.position,false)
				_update_overlay();return EditorPlugin.AFTER_GUI_INPUT_STOP
		if path and _plan_point_mode=="insert":
			var point := _plan_insert_target(region, event.position)
			if point.is_finite():
				var curve:=TerrainPlan.Influence.path_curve(points)
				var offset:=curve.get_closest_offset(point)
				var where:=1
				while where<points.size()-1 and curve.get_closest_offset(points[where])<offset:where+=1
				var changed:=points.duplicate();changed.insert(where,point)
				var message:=_stage_branch_points(changed) if region.has("road_join") else commit_plan_points(map,_plan_selected_id,changed)
				if message.is_empty():_plan_point_index=where
				_plan_panel.set_status(message if not message.is_empty() else "Точка добавлена.");_update_overlay()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
	var selected:=_plan_region_at(event.position)
	if not selected.is_empty():
		_select_plan_region(selected)
		if _plan_point_mode=="translate" and _branch_edit.is_empty():
			plan=TerrainPlan.read(map);index=plan.index_of(selected)
			_plan_begin_drag(plan.regions[index],-1,event.position,true)
	return EditorPlugin.AFTER_GUI_INPUT_STOP

func _plan_remove_point(points:PackedVector2Array,index:int)->void:
	if index<0 or index>=points.size():return
	if points.size()<=2:_plan_panel.set_status("У линии должны остаться хотя бы две точки.");return
	var changed:=points.duplicate();changed.remove_at(index)
	var plan: Resource = TerrainPlan.read(map)
	var region_index: int = plan.index_of(_plan_selected_id) if plan != null else -1
	var branch: bool = region_index >= 0 and plan.regions[region_index].has("road_join")
	if branch and index == 0:
		_plan_panel.set_status("Начало ответвления закреплено на главной дороге.")
		return
	var message:=_stage_branch_points(changed) if branch else commit_plan_points(map,_plan_selected_id,changed)
	if message.is_empty():_plan_point_index=mini(index,changed.size()-1)
	_plan_panel.set_status(message if not message.is_empty() else "Точка удалена.");_update_overlay()

func _plan_finish_drag()->void:
	var plan:Resource=TerrainPlan.read(map)
	var message:="План изменился во время переноса. Повтори движение."
	var ghost:Dictionary=_plan_drag.ghost
	var valid:bool=plan!=null and plan.data()==_plan_drag.version
	# End the gesture before applying history; callbacks must render the saved shape.
	_plan_cancel_drag()
	var branch := ghost.has("road_join")
	if valid:message=_stage_branch_points(ghost.points_m) if branch else commit_plan_shape(map,_plan_selected_id,ghost)
	_plan_panel.set_status(message if not message.is_empty() else "Точка изменена в черновике. Предпросмотр → Применить." if branch else "Контур сохранён в плане. Предпросмотр → Применить.")
