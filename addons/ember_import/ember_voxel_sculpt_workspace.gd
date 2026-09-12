@tool
class_name EmberVoxelSculptWorkspace
extends Control
## Style-first 4x4 surface canvas. This is a visual/UX gate, not the final
## chunked world format. It edits the canonical Godot voxel Resource and uses
## the same VoxMesher/materials as preview and runtime.

const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Actions = preload("res://addons/ember_import/ember_voxel_sculpt_actions.gd")
const NativePreview = preload("res://scripts/ember_voxel_native_mesher.gd")
const SurfaceMaterials = preload("res://scripts/ember_voxel_surface_materials.gd")
const SurfaceMesher = preload("res://scripts/ember_voxel_surface_mesher.gd")
const NavigationGuard = preload("res://addons/ember_import/ember_surface_navigation_guard.gd")
const EditorViewStore = preload("res://addons/ember_import/ember_surface_editor_view_store.gd")
const EditBounds = preload("res://scripts/ember_voxel_edit_bounds.gd")
const SliceControl = preload("res://addons/ember_import/ember_surface_slice_control.gd")
const PalettePanel = preload("res://addons/ember_import/ember_voxel_palette_panel.gd")
const SelectionPanel = preload("res://addons/ember_import/ember_voxel_selection_panel.gd")
const GroupsPanel = preload("res://addons/ember_import/ember_voxel_groups_panel.gd")
const Groups = preload("res://addons/ember_import/ember_voxel_groups.gd")
const BrushProfiles = preload("res://addons/ember_import/ember_voxel_brush_profiles.gd")
const WorkshopTheme = preload("res://addons/ember_import/ember_voxel_workshop_theme.gd")
const PREVIEW_CHUNK_SIZE := 16
const PREVIEW_REBUILD_BUDGET_USEC := 6000
const MAX_VIEWPORT_DIMENSION := 4096
const DEFAULT_CAMERA_TARGET := Vector3(2.0, 0.12, 2.0)

enum ViewAction {
	WORLD_CAMERA,
	BATTLE_CAMERA,
	TOP_CAMERA,
	FIT_SURFACE,
	CENTER_CAMERA,
	CAMERA_SETTINGS,
	GRID_OVERLAY,
	REGION_OVERLAY,
}

enum CanvasMode {
	BRUSH,
	SELECTION,
	SELECTION_TRANSFORM,
	STAMP_LIBRARY,
	STAMP_DRAFT,
	COLOR_PICK,
	REGION_SELECT,
	GENERATOR,
}

signal status_changed(message: String, color: Color)
signal generator_assets_changed(model_id: String)

var _object_session: RefCounted
var _generator_panel: VBoxContainer
var _generator_preview: Node3D
var _extraction_go_to_3d := false
var _scene_context: Node3D
var _context_controls: HFlowContainer
var _context_toggle: CheckButton
var _context_opacity: SpinBox
var _context_refresh: Button
var _context_poll := 0.0

var _editor_interface: EditorInterface
var _actions: EmberVoxelSculptActions
var _resource: EmberVoxelModelResource
var _resource_path := ""
var _saved_voxels := PackedByteArray()
var _saved_palette := PackedColorArray()
var _saved_transparency := PackedByteArray()
var _saved_surface_fill_levels := PackedInt32Array()
var _saved_surface_fill_materials := PackedByteArray()
var _saved_surface_fill_palette := PackedByteArray()
var _saved_voxel_groups: Array[Dictionary] = []
var _saved_schema_version := 1
var _saved_size_blocks := Vector3i.ONE
var _saved_height_voxels := 16
var _saved_growth_channels := {}
var _part_selector: OptionButton
var _displayed_grid := Vector3i.ZERO
var _grow_button: Button
var create_object_callback: Callable
var _navigation_guard: ConfirmationDialog
var _view_store: RefCounted
var _show_grid := true
var _show_region := true
var _slice_height := -1
var _slice_control: VBoxContainer

var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera3D
var _surface_root: Node3D
var _chunk_meshes: Dictionary = {}
var _pending_preview_chunks: Dictionary = {}
var _native_preview: RefCounted
var _grid: MeshInstance3D
var _cursor: MeshInstance3D
var _ramp_anchor_marker: MeshInstance3D
var _precision_line_preview: MultiMeshInstance3D
var _region_overlay: MeshInstance3D
var _tool: ItemList
var _radius: OptionButton
var _depth: SpinBox
var _follow_surface: CheckButton
var _application_mode: OptionButton
var _brush_shape: OptionButton
var _volume_operation: OptionButton
var _relief_mode: OptionButton
var _relief_direction: OptionButton
var _relief_geometry: OptionButton
var _relief_generator_style: OptionButton
var _relief_generator_direction: OptionButton
var _relief_generator_scale: OptionButton
var _relief_generator_detail: OptionButton
var _relief_variant_button: Button
var _relief_seed_value := 0
var _region_select_button: Button
var _region_label: Label
var _height_limit: OptionButton
var _buildup_rate: OptionButton
var _smooth_strength: OptionButton
var _smooth_mode: OptionButton
var _smooth_fill_pits: CheckButton
var _palette: OptionButton
var _palette_panel: VBoxContainer
var _displayed_palette := PackedColorArray()
var _picking_color := false
var _selection_panel: VBoxContainer
var _selection_interaction: Control
var _stamp_panel: VBoxContainer
var _groups_panel: VBoxContainer
var _displayed_groups: Array[Dictionary] = []
var _locked_indices: Dictionary = {}
var _isolated_group_indices := PackedInt32Array()
var _hidden_group_indices := PackedInt32Array()
var _isolation_resource: EmberVoxelModelResource
var _material_preset: OptionButton
var _material_scope: OptionButton
var _material_tolerance: OptionButton
var _surface_fill_material: OptionButton
var _surface_fill_level: OptionButton
var _surface_fill_inset: OptionButton
var _surface_fill_tint: OptionButton
var _coarse: CheckBox
var _title: Label
var _dirty_label: Label
var _object_name_input: LineEdit
var _workshop_context_label: Label
var _active_tool_label: Label
var _tool_rail: VBoxContainer
var _sidebar_panel: VBoxContainer
var _operation_panel: VBoxContainer
var _sidebar_tabs: TabContainer
var _parts_sections: TabContainer
var _select_tool_button: Button
var _stamp_tool_button: Button
var _tool_rail_toggle: Button
var _sidebar_toggle: Button
var _view_menu: MenuButton
var _surface_layer_view: OptionButton
var _play_owner_button: Button
var _reset_button: Button
var _resource_path_label: Label
var _camera_popup: PopupPanel
var _camera_yaw_control: SpinBox
var _camera_pitch_control: SpinBox
var _camera_size_control: SpinBox
var _camera_margin_control: SpinBox
var _status: Label
var _info: Label
var _footer_stats: Label
var _workshop_preset_name := ""
var _non_brush_tool_visibility: Dictionary = {}
var _tool_profiles: Dictionary = {}
var _active_profile_tool := -1
var _restoring_tool_profile := false
var _canvas_mode := CanvasMode.BRUSH
var _last_brush_item := 0
var _switching_canvas_mode := false
var _canvas_pattern_context := false

var _yaw := deg_to_rad(45.0)
var _pitch := deg_to_rad(-48.0)
var _ortho_size := 5.8
var _camera_fit_margin := 1.70
var _camera_target := DEFAULT_CAMERA_TARGET
var _orbiting := false
var _panning := false
var _stroke_active := false
var _stroke_tool_id := -1
var _stroke_before := PackedByteArray()
var _stroke_live_values := PackedByteArray()
var _stroke_changes: Dictionary = {}
var _stroke_before_transparency := PackedByteArray()
var _stroke_live_transparency := PackedByteArray()
var _stroke_material_changes: Dictionary = {}
var _stroke_smart_fill_applied := false
var _stroke_rejected := false
var _stroke_top_cache: Dictionary = {}
var _stroke_relief_amount_cache: Dictionary = {}
var _stroke_relief_center_height_cache: Dictionary = {}
var _stroke_shell_foundation_cache: Dictionary = {}
var _stroke_smooth_column_cache: Dictionary = {}
var _stroke_generator_column_cache: Dictionary = {}
var _stroke_heightfield := PackedInt32Array()
var _stroke_normal := Vector3i.ZERO
var _last_stroke_normal := Vector3i.ZERO
var _stroke_face_plane := -999999
var _single_face_stopped := false
var _surface_heightfield := PackedInt32Array()
var _heightfield_source_voxels := PackedByteArray()
var _last_stroke_cell := Model.INVALID_CELL
var _stroke_input_cell := Model.INVALID_CELL
var _stroke_distance_to_next := 1.0
var _stroke_smoothed_position := Vector2.ZERO
var _has_stroke_smoothed_position := false
var _surface_normal_cache_key: Array = []
var _surface_normal_cache_value := Vector3.ZERO
var _pending_stroke_position := Vector2.ZERO
var _has_pending_stroke_position := false
var _relief_hold_center := Model.INVALID_CELL
var _relief_hold_elapsed := 0.0
var _relief_applied_height := 0
var _stroke_level_target_y := -1
var _ramp_anchor_cell := Model.INVALID_CELL
var _precision_line_anchor_cell := Model.INVALID_CELL
var _precision_line_target_cell := Model.INVALID_CELL
var _precision_line_normal := Vector3i.ZERO
var _precision_line_preview_indices := PackedInt32Array()
var _region_anchor_block := Vector2i(-1, -1)
var _edit_region_blocks := Rect2i()
var _region_preview_blocks := Rect2i()


func setup(
	editor_interface: EditorInterface,
	undo_redo: Object,
	view_store: RefCounted = null,
) -> void:
	_editor_interface = editor_interface
	_actions = Actions.new() as EmberVoxelSculptActions
	_actions.configure(undo_redo)
	_actions.source_changed.connect(_on_source_changed)
	_native_preview = NativePreview.new()
	_view_store = view_store if view_store != null else EditorViewStore.new()
	_load_tool_profiles()


func _ready() -> void:
	visibility_changed.connect(_on_workspace_visibility_changed)


func _on_workspace_visibility_changed() -> void:
	if not is_visible_in_tree():
		_return_to_last_brush()
		if is_instance_valid(_groups_panel):
			_groups_panel.cancel_isolation()
		if is_instance_valid(_palette_panel):
			_palette_panel.cancel_edit()
		_flush_pending_stroke_position()
		_finish_stroke()
		_cancel_precision_line(false)
		_remember_current_editor_view()
		_orbiting = false
		_panning = false


func _process(delta: float) -> void:
	_sync_object_name_input()
	if is_instance_valid(_scene_context) and _scene_context.visible:
		_context_poll += delta
		if _context_poll >= 0.5:
			_context_poll = 0.0
			_sync_context_frame()
	_drain_preview_chunk()
	_flush_pending_stroke_position()
	if not _stroke_active or _relief_hold_center == Model.INVALID_CELL:
		return
	if not Rect2(Vector2.ZERO, _viewport_container.size).has_point(
		_viewport_container.get_local_mouse_position()
	):
		return
	var tool_id := _selected_tool_id()
	if not _is_relief_tool(tool_id) or _is_relief_generator():
		return
	var height_limit := int(_height_limit.get_item_metadata(_height_limit.selected))
	var rate := float(_buildup_rate.get_item_metadata(_buildup_rate.selected))
	_relief_hold_elapsed += delta
	var desired_height := Model.buildup_height(_relief_hold_elapsed, rate, height_limit)
	if desired_height <= _relief_applied_height:
		return
	_apply_stroke_centers(
		[_relief_hold_center], desired_height, _relief_applied_height
	)
	_relief_applied_height = desired_height


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if _generator_active() and event is InputEventKey and event.pressed and not event.echo:
		if event.is_command_or_control_pressed() and event.keycode in [KEY_Z, KEY_Y]:
			if event.keycode == KEY_Y or event.shift_pressed:
				_generator_panel.redo_parameters()
			else:
				_generator_panel.undo_parameters()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE:
			_generator_panel._clear_preview()
			get_viewport().set_input_as_handled()
			return
	if is_instance_valid(_object_name_input) and _object_name_input.has_focus():
		return
	if event is InputEventKey and is_instance_valid(_selection_interaction) and _selection_interaction.handle(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and is_instance_valid(_selection_panel) and _selection_panel.busy():
			if _selection_panel.busy():
				_selection_panel.cancel_search()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and _canvas_mode != CanvasMode.BRUSH:
			_return_to_last_brush()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_S and event.is_command_or_control_pressed():
			_save()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey:
		var anchor_key := event as InputEventKey
		if (
			anchor_key.pressed and not anchor_key.echo and anchor_key.keycode == KEY_ESCAPE
			and _precision_line_anchor_cell != Model.INVALID_CELL
		):
			_cancel_precision_line()
			get_viewport().set_input_as_handled()
			return
		if (
			anchor_key.pressed and not anchor_key.echo
			and anchor_key.keycode in [KEY_ENTER, KEY_KP_ENTER]
			and _precision_line_anchor_cell != Model.INVALID_CELL
		):
			_commit_precision_line()
			get_viewport().set_input_as_handled()
			return
		if (
			anchor_key.pressed and not anchor_key.echo and anchor_key.keycode == KEY_ESCAPE
			and (
				_region_anchor_block != Vector2i(-1, -1)
				or (is_instance_valid(_region_select_button) and _region_select_button.button_pressed)
			)
		):
			_cancel_region_selection()
			get_viewport().set_input_as_handled()
			return
		if (
			anchor_key.pressed and not anchor_key.echo and anchor_key.keycode == KEY_ESCAPE
			and _ramp_anchor_cell != Model.INVALID_CELL
		):
			_cancel_ramp_anchor()
			get_viewport().set_input_as_handled()
			return
	if not _stroke_active:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
			_pending_stroke_position = _viewport_container.get_local_mouse_position()
			_has_pending_stroke_position = true
			_flush_pending_stroke_position(true)
			_finish_stroke()
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			_cancel_stroke()
			get_viewport().set_input_as_handled()


func ensure_ui() -> void:
	if get_child_count() == 0:
		_build()


func open_pilot() -> void:
	ensure_ui()
	var absolute := ProjectSettings.globalize_path(Model.PILOT_PATH)
	var pilot: EmberVoxelModelResource
	if not FileAccess.file_exists(absolute):
		pilot = Model.make_pilot()
		DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
		var create_error := ResourceSaver.save(pilot, Model.PILOT_PATH)
		if create_error != OK:
			_set_status("Не удалось создать Surface Canvas: %s" % error_string(create_error), true)
			return
	else:
		pilot = ResourceLoader.load(
			Model.PILOT_PATH, "", ResourceLoader.CACHE_MODE_REPLACE
		) as EmberVoxelModelResource
	if pilot == null:
		_set_status("Surface Canvas Resource не загрузился", true)
		return
	open_surface(pilot, Model.PILOT_PATH)


func open_surface(
	resource: EmberVoxelModelResource,
	resource_path: String,
	initial_region_blocks := Rect2i(),
) -> void:
	ensure_ui()
	_flush_pending_stroke_position()
	_finish_stroke()
	if _resource == resource and resource != null:
		# Opening another area of the same map must not reset the saved baseline.
		_cancel_ramp_anchor(false)
		_cancel_precision_line(false)
		_region_select_button.set_pressed_no_signal(false)
		_region_anchor_block = Vector2i(-1, -1)
		_region_preview_blocks = Rect2i()
		_edit_region_blocks = _clamped_block_region(
			initial_region_blocks, resource.size_blocks.x, resource.size_blocks.z
		)
		_rebuild_visual()
		_update_region_label(_edit_region_blocks)
		_fit_camera_to_surface(false)
		show_current_status()
		return
	if has_unsaved_changes():
		_navigation_guard.request(
			_resource.display_name,
			_open_surface_unchecked.bind(resource, resource_path, initial_region_blocks),
		)
		return
	_open_surface_unchecked(resource, resource_path, initial_region_blocks)


func open_object(session: RefCounted) -> void:
	ensure_ui()
	_flush_pending_stroke_position()
	_finish_stroke()
	if has_unsaved_changes():
		_navigation_guard.request(_resource.display_name, _open_object_after_navigation.bind(session))
		return
	_open_object_unchecked(session)


func _open_object_after_navigation(session: RefCounted) -> void:
	# Saving the outgoing shared model may have changed the incoming source.
	# Resolve its fresh draft only after that transaction has finished.
	if not session.refresh_before_open():
		_set_status(session.error, true)
		return
	_open_object_unchecked(session)


func _open_object_unchecked(session: RefCounted) -> void:
	_open_surface_unchecked(session.draft, "")
	_object_session = session
	_context_controls.visible = true
	_grow_button.visible = session.can_grow_canvas()
	_title.text = "CANVAS · %s" % session.draft.display_name
	_resource_path_label.text = session.label()
	_play_owner_button.visible = false
	_set_status(session.label() + " · файлы появятся только после сохранения правок")
	_sync_generator_panel()


func request_close(continuation: Callable, cancel: Callable) -> void:
	ensure_ui()
	_flush_pending_stroke_position()
	_finish_stroke()
	_remember_current_editor_view()
	if not has_unsaved_changes():
		if continuation.is_valid():
			continuation.call()
		return
	_navigation_guard.request_close(_resource.display_name, continuation, cancel)


func cancel_navigation_request() -> void:
	if is_instance_valid(_navigation_guard) and _navigation_guard.visible:
		_navigation_guard.hide()
		_navigation_guard.clear_request()


func save_changes() -> bool:
	return _save()


func unsaved_status() -> String:
	if not has_unsaved_changes():
		return ""
	return "Surface «%s» содержит несохранённые правки." % _resource.display_name


func export_editor_view_data() -> Dictionary:
	_remember_current_editor_view()
	return _view_store.call("export_data") as Dictionary if _view_store != null else {}


func import_editor_view_data(data: Dictionary) -> void:
	if _view_store == null:
		_view_store = EditorViewStore.new()
	_view_store.call("import_data", data)
	_load_tool_profiles()
	if is_instance_valid(_tool):
		_restore_tool_profile(_selected_base_tool_id())


func _open_surface_unchecked(
	resource: EmberVoxelModelResource, resource_path: String,
	initial_region_blocks := Rect2i(),
) -> void:
	if _object_session != null:
		_object_session.release_projection_cache()
	_object_session = null
	_context_controls.visible = false
	_context_toggle.set_pressed_no_signal(false)
	_toggle_scene_context(false)
	_grow_button.visible = false
	_disconnect_resource()
	_cancel_ramp_anchor(false)
	_region_select_button.set_pressed_no_signal(false)
	_region_anchor_block = Vector2i(-1, -1)
	_region_preview_blocks = Rect2i()
	_resource = resource
	if _actions != null:
		_actions.active_part = 0
	_resource_path = resource_path
	if _resource == null:
		_set_status("Surface Canvas Resource не загрузился", true)
		return
	_saved_voxels = _resource.voxels.duplicate()
	_saved_palette = _resource.palette.duplicate()
	_saved_transparency = _resource.transparency.duplicate()
	_saved_surface_fill_levels = _resource.surface_fill_levels.duplicate()
	_saved_surface_fill_materials = _resource.surface_fill_materials.duplicate()
	_saved_surface_fill_palette = _resource.surface_fill_palette.duplicate()
	_saved_voxel_groups = _resource.voxel_groups.duplicate(true)
	_saved_schema_version = _resource.schema_version
	_saved_size_blocks = _resource.size_blocks
	_saved_height_voxels = _resource.height_voxels
	_capture_growth_channels()
	_displayed_grid = _resource.grid_size()
	_show_grid = true
	_show_region = true
	_slice_height = -1
	_slice_control.configure(_resource.grid_size().y)
	_surface_layer_view.select(0)
	var view_popup := _view_menu.get_popup()
	view_popup.set_item_checked(view_popup.get_item_index(ViewAction.GRID_OVERLAY), true)
	view_popup.set_item_checked(view_popup.get_item_index(ViewAction.REGION_OVERLAY), true)
	var width := _resource.size_blocks.x
	var depth := _resource.size_blocks.z
	_edit_region_blocks = _clamped_block_region(initial_region_blocks, width, depth)
	_yaw = deg_to_rad(45.0)
	_pitch = deg_to_rad(-48.0)
	_camera_fit_margin = 1.70
	_camera_target = Vector3(float(width) * 0.5, DEFAULT_CAMERA_TARGET.y, float(depth) * 0.5)
	_ortho_size = maxf(5.2, float(maxi(width, depth)) * 1.35)
	var restored_view := false
	if not initial_region_blocks.has_area() and _view_store != null:
		var view_state: Dictionary = _view_store.call("recall", _editor_view_key())
		if not view_state.is_empty():
			_restore_editor_view_state(view_state)
			restored_view = true
	_update_slice_tools()
	if is_instance_valid(_title):
		_title.text = "SURFACE CANVAS · %s" % _resource.display_name.to_upper()
	if is_instance_valid(_resource_path_label):
		_resource_path_label.text = _resource_path
	if is_instance_valid(_reset_button):
		_reset_button.visible = _resource_path == Model.PILOT_PATH
		_reset_button.disabled = _resource_path != Model.PILOT_PATH
		_reset_button.tooltip_text = (
			"Вернуть тестовый 4×4 холст к исходному виду."
			if _resource_path == Model.PILOT_PATH
			else "У авторской поверхности нет скрытого шаблона: используйте Ctrl+Z."
		)
	if is_instance_valid(_play_owner_button):
		var owner_scene := _owner_scene_path()
		_play_owner_button.visible = not owner_scene.is_empty()
		_play_owner_button.disabled = owner_scene.is_empty()
		_play_owner_button.tooltip_text = (
			"Сохранить Surface и запустить именно карту %s, а не главную сцену проекта."
			% str(_resource.material.get("semanticOwner", ""))
		)
	_refresh_palette()
	_refresh_groups()
	_update_workshop_shell()
	_rebuild_visual()
	_rebuild_region_overlay()
	_update_region_label(_edit_region_blocks)
	if restored_view:
		_update_camera()
		_sync_camera_controls()
	else:
		_fit_camera_to_surface(false)
	_sync_generator_panel()
	_set_status(
		("%d×%d блоков · область %d×%d · LMB рисует · RMB вращает · MMB сдвигает"
		% [width, depth, _edit_region_blocks.size.x, _edit_region_blocks.size.y])
		if _edit_region_blocks.has_area()
		else "%d×%d блоков · LMB рисует · RMB вращает · MMB сдвигает · колесо приближает" % [width, depth]
	)


func _clamped_block_region(region: Rect2i, width: int, depth: int) -> Rect2i:
	if not region.has_area():
		return Rect2i()
	var minimum := Vector2i(
		clampi(region.position.x, 0, maxi(0, width - 1)),
		clampi(region.position.y, 0, maxi(0, depth - 1)),
	)
	var maximum_exclusive := Vector2i(
		clampi(region.end.x, minimum.x + 1, width),
		clampi(region.end.y, minimum.y + 1, depth),
	)
	return Rect2i(minimum, maximum_exclusive - minimum)


func has_unsaved_changes() -> bool:
	return (
		_resource != null
		and (
			_resource.voxels != _saved_voxels
			or _resource.size_blocks != _saved_size_blocks
			or _resource.height_voxels != _saved_height_voxels
			or _resource.palette != _saved_palette
			or _resource.transparency != _saved_transparency
			or _resource.surface_fill_levels != _saved_surface_fill_levels
			or _resource.surface_fill_materials != _saved_surface_fill_materials
			or _resource.surface_fill_palette != _saved_surface_fill_palette
			or _resource.voxel_groups != _saved_voxel_groups
			or _resource.voxel_part_ids != _saved_growth_channels.get("voxel_part_ids", PackedInt32Array())
			or _resource.merge_parts != _saved_growth_channels.get("merge_parts", PackedStringArray())
			or _resource.collision_voxels != _saved_growth_channels.get("collision_voxels", PackedByteArray())
			or _resource.schema_version != _saved_schema_version
		)
	)


func _editor_view_key() -> String:
	return EditorViewStore.resource_key(_resource, _resource_path)


func _capture_editor_view_state() -> Dictionary:
	var layer := "combined"
	if is_instance_valid(_surface_layer_view) and _surface_layer_view.selected >= 0:
		layer = str(_surface_layer_view.get_item_metadata(_surface_layer_view.selected))
	return {
		"yaw": _yaw,
		"pitch": _pitch,
		"ortho_size": _ortho_size,
		"fit_margin": _camera_fit_margin,
		"camera_target": _camera_target,
		"edit_region": _edit_region_blocks,
		"slice_height": _slice_height,
		"show_grid": _show_grid,
		"show_region": _show_region,
		"layer_view": layer,
	}


func _remember_current_editor_view() -> void:
	if _view_store == null:
		return
	_store_active_tool_profile()
	if _view_store.has_method("remember_brush_profiles"):
		_view_store.call("remember_brush_profiles", _tool_profiles)
	if _resource != null:
		_view_store.call("remember", _editor_view_key(), _capture_editor_view_state())


func _restore_editor_view_state(state: Dictionary) -> void:
	if _resource == null:
		return
	var restored := EditorViewStore.normalize(state)
	_yaw = float(restored.yaw)
	_pitch = float(restored.pitch)
	_ortho_size = float(restored.ortho_size)
	_camera_fit_margin = float(restored.fit_margin)
	_camera_target = restored.camera_target as Vector3
	_edit_region_blocks = _clamped_block_region(
		restored.edit_region as Rect2i,
		_resource.size_blocks.x,
		_resource.size_blocks.z,
	)
	var saved_slice := int(restored.slice_height)
	_slice_height = clampi(saved_slice, 1, _resource.grid_size().y) if saved_slice >= 1 else -1
	_show_grid = bool(restored.show_grid)
	_show_region = bool(restored.show_region)
	_select_option_metadata(_surface_layer_view, str(restored.layer_view))
	_slice_control.restore_view(_slice_height)
	var popup := _view_menu.get_popup()
	popup.set_item_checked(popup.get_item_index(ViewAction.GRID_OVERLAY), _show_grid)
	popup.set_item_checked(popup.get_item_index(ViewAction.REGION_OVERLAY), _show_region)


func discard_changes() -> void:
	_cancel_stroke()
	_cancel_precision_line(false)
	if is_instance_valid(_groups_panel):
		_groups_panel.cancel_isolation()
	if _resource == null:
		return
	_resource.voxels = _saved_voxels.duplicate()
	_resource.size_blocks = _saved_size_blocks
	_resource.height_voxels = _saved_height_voxels
	for channel in _saved_growth_channels:
		_resource.set(channel, _saved_growth_channels[channel].duplicate())
	_resource.palette = _saved_palette.duplicate()
	_resource.transparency = _saved_transparency.duplicate()
	_resource.surface_fill_levels = _saved_surface_fill_levels.duplicate()
	_resource.surface_fill_materials = _saved_surface_fill_materials.duplicate()
	_resource.surface_fill_palette = _saved_surface_fill_palette.duplicate()
	_resource.voxel_groups = _saved_voxel_groups.duplicate(true)
	_resource.schema_version = _saved_schema_version
	_resource.emit_changed()
	_refresh_palette()
	_refresh_groups()
	_sync_canvas_dimensions()
	_rebuild_visual()
	show_current_status()


func show_current_status() -> void:
	if _resource == null:
		_set_status("Surface Canvas ещё не открыт")
	elif has_unsaved_changes():
		_set_status("НЕ СОХРАНЕНО · Ctrl+Z работает через общую историю Godot", false, Color(1.0, 0.72, 0.30))
	else:
		_set_status("Surface Canvas сохранён · LMB рисует · RMB вращает · MMB сдвигает · колесо приближает")


func _build() -> void:
	var base_theme := EditorInterface.get_editor_theme() if Engine.is_editor_hint() else ThemeDB.get_default_theme()
	theme = WorkshopTheme.build(base_theme)
	_navigation_guard = NavigationGuard.new()
	_navigation_guard.configure(_save, discard_changes)
	add_child(_navigation_guard)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var header := HFlowContainer.new()
	header.name = "VoxelSculptHeader"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 6)
	root.add_child(header)
	_title = Label.new()
	_title.text = "ВОКСЕЛЬНАЯ МАСТЕРСКАЯ"
	_title.modulate = Color(0.96, 0.72, 0.32)
	_title.add_theme_font_size_override("font_size", 14)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_title)
	var workspace_actions := HFlowContainer.new()
	workspace_actions.name = "VoxelWorkshopWorkspaceActions"
	workspace_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace_actions.add_theme_constant_override("h_separation", 6)
	workspace_actions.add_theme_constant_override("v_separation", 4)
	var create_object := Button.new()
	create_object.text = "+ Объект"
	create_object.pressed.connect(func():
		if create_object_callback.is_valid():
			request_close(create_object_callback, Callable())
	)
	workspace_actions.add_child(create_object)
	_grow_button = Button.new()
	_grow_button.text = "Расширить холст…"
	_grow_button.visible = false
	_grow_button.pressed.connect(_show_canvas_growth)
	workspace_actions.add_child(_grow_button)
	_view_menu = MenuButton.new()
	_view_menu.name = "VoxelSurfaceViewMenu"
	_view_menu.text = "Вид"
	_view_menu.tooltip_text = "Ракурс, кадрирование и точные настройки камеры."
	var view_popup := _view_menu.get_popup()
	view_popup.add_item("Камера мира", ViewAction.WORLD_CAMERA)
	view_popup.add_item("Камера боя", ViewAction.BATTLE_CAMERA)
	view_popup.add_item("Сверху", ViewAction.TOP_CAMERA)
	view_popup.add_separator("", 100)
	view_popup.add_item("Вписать поверхность · Home", ViewAction.FIT_SURFACE)
	view_popup.add_item("Вернуть центр", ViewAction.CENTER_CAMERA)
	view_popup.add_separator("", 101)
	view_popup.add_item("Точные настройки…", ViewAction.CAMERA_SETTINGS)
	view_popup.add_separator("", 102)
	view_popup.add_check_item("Сетка блоков · G", ViewAction.GRID_OVERLAY)
	view_popup.set_item_checked(view_popup.get_item_index(ViewAction.GRID_OVERLAY), _show_grid)
	view_popup.add_check_item("Рамка рабочей области", ViewAction.REGION_OVERLAY)
	view_popup.set_item_checked(view_popup.get_item_index(ViewAction.REGION_OVERLAY), _show_region)
	view_popup.id_pressed.connect(_on_view_action)
	workspace_actions.add_child(_view_menu)
	_surface_layer_view = OptionButton.new()
	_surface_layer_view.name = "VoxelSurfaceLayerView"
	_surface_layer_view.tooltip_text = (
		"Дно + вода показывает финальный вид. Только дно временно скрывает "
		+ "water overlay, чтобы спокойно рисовать камни, пятна и глубину. "
		+ "Сохранённая маска воды при этом не меняется."
	)
	_surface_layer_view.add_item("Слои · дно + вода")
	_surface_layer_view.set_item_metadata(0, "combined")
	_surface_layer_view.add_item("Слои · только дно")
	_surface_layer_view.set_item_metadata(1, "floor")
	_surface_layer_view.item_selected.connect(_on_surface_layer_view_changed)
	workspace_actions.add_child(_surface_layer_view)
	_play_owner_button = Button.new()
	_play_owner_button.name = "PlayVoxelSurfaceOwner"
	_play_owner_button.text = "▶ Играть карту"
	_play_owner_button.tooltip_text = "Сохранить Surface и запустить связанную world-сцену."
	_play_owner_button.visible = false
	_play_owner_button.pressed.connect(_play_owner_scene)
	workspace_actions.add_child(_play_owner_button)
	_tool_rail_toggle = Button.new()
	_tool_rail_toggle.name = "ToggleVoxelWorkshopTools"
	_tool_rail_toggle.text = "Инструменты"
	_tool_rail_toggle.tooltip_text = "Показать или скрыть левую панель инструментов."
	_tool_rail_toggle.theme_type_variation = &"WorkshopToolButton"
	_tool_rail_toggle.toggle_mode = true
	_tool_rail_toggle.button_pressed = true
	_tool_rail_toggle.toggled.connect(func(pressed: bool) -> void:
		if is_instance_valid(_tool_rail):
			_tool_rail.visible = pressed
	)
	header.add_child(_tool_rail_toggle)
	_sidebar_toggle = Button.new()
	_sidebar_toggle.name = "ToggleVoxelWorkshopSidebar"
	_sidebar_toggle.text = "Панели"
	_sidebar_toggle.tooltip_text = "Показать или скрыть палитру, части и библиотеку."
	_sidebar_toggle.theme_type_variation = &"WorkshopToolButton"
	_sidebar_toggle.toggle_mode = true
	_sidebar_toggle.button_pressed = true
	_sidebar_toggle.toggled.connect(func(pressed: bool) -> void:
		if is_instance_valid(_sidebar_panel):
			_sidebar_panel.visible = pressed
	)
	header.add_child(_sidebar_toggle)
	_dirty_label = Label.new()
	_dirty_label.name = "VoxelWorkshopDirtyState"
	_dirty_label.text = "Сохранено"
	_dirty_label.modulate = Color(0.54, 0.64, 0.74)
	header.add_child(_dirty_label)
	var save := Button.new()
	save.name = "SaveVoxelSurfacePilot"
	save.text = "Сохранить"
	save.theme_type_variation = &"WorkshopPrimaryButton"
	save.tooltip_text = "Сохранить текущую Surface в её Godot Resource."
	save.pressed.connect(_save)
	header.add_child(save)

	var context_bar := HFlowContainer.new()
	context_bar.name = "VoxelWorkshopContextBar"
	context_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context_bar.add_theme_constant_override("h_separation", 8)
	context_bar.add_theme_constant_override("v_separation", 3)
	root.add_child(context_bar)
	var object_name_label := Label.new()
	object_name_label.text = "Объект"
	context_bar.add_child(object_name_label)
	_object_name_input = LineEdit.new()
	_object_name_input.name = "VoxelWorkshopObjectName"
	_object_name_input.custom_minimum_size.x = 180.0
	_object_name_input.max_length = 80
	_object_name_input.placeholder_text = "—"
	_object_name_input.editable = false
	_object_name_input.text_submitted.connect(_submit_object_name)
	_object_name_input.focus_exited.connect(_commit_object_name)
	_object_name_input.gui_input.connect(_on_object_name_gui_input)
	context_bar.add_child(_object_name_input)
	_workshop_context_label = Label.new()
	_workshop_context_label.name = "VoxelWorkshopContext"
	_workshop_context_label.text = "›  Модель —  ›  Часть —  ›  Пресет —"
	_workshop_context_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workshop_context_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_workshop_context_label.tooltip_text = "Текущий объект сцены, voxel-модель, часть склейки и пресет штампа."
	context_bar.add_child(_workshop_context_label)
	root.add_child(workspace_actions)

	_context_controls = HFlowContainer.new()
	_context_controls.visible = false
	root.add_child(_context_controls)
	_context_toggle = CheckButton.new()
	_context_toggle.text = "Показать окружение"
	_context_toggle.tooltip_text = "Снимок видимой геометрии сцены. Кисть меняет только выбранный объект. Свет остаётся студийным светом Canvas."
	_context_toggle.toggled.connect(_toggle_scene_context)
	_context_controls.add_child(_context_toggle)
	_context_opacity = SpinBox.new()
	_context_opacity.custom_minimum_size.x = 160
	_context_opacity.prefix = "Фон"
	_context_opacity.suffix = "%"
	_context_opacity.min_value = 0
	_context_opacity.max_value = 100
	_context_opacity.step = 5
	_context_opacity.value = 60
	_context_opacity.editable = false
	_context_opacity.value_changed.connect(func(value: float):
		if is_instance_valid(_scene_context):
			_scene_context.set_opacity(value / 100.0)
	)
	_context_controls.add_child(_context_opacity)
	_context_refresh = Button.new()
	_context_refresh.text = "Обновить окружение"
	_context_refresh.disabled = true
	_context_refresh.pressed.connect(_refresh_scene_context)
	_context_controls.add_child(_context_refresh)
	var tool_settings := HFlowContainer.new()
	tool_settings.name = "VoxelSculptToolSettings"
	tool_settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_settings.add_theme_constant_override("h_separation", 5)
	tool_settings.add_theme_constant_override("v_separation", 4)
	root.add_child(tool_settings)
	_active_tool_label = Label.new()
	_active_tool_label.name = "VoxelSculptActiveTool"
	_active_tool_label.text = "Объём · добавить"
	_active_tool_label.custom_minimum_size.x = 150.0
	_active_tool_label.modulate = Color(0.60, 0.82, 0.94)
	tool_settings.add_child(_active_tool_label)
	_radius = OptionButton.new()
	_radius.name = "VoxelSculptRadius"
	for value in [1, 2, 4, 6, 8, 12, 16, 24, 32]:
		_radius.add_item("Радиус %d vox" % value)
		_radius.set_item_metadata(_radius.item_count - 1, value)
	_radius.select(2)
	_radius.item_selected.connect(func(_index: int) -> void: _on_brush_setting_changed())
	tool_settings.add_child(_radius)
	_depth = SpinBox.new()
	_depth.name = "VoxelSculptDepth"
	_depth.prefix = "Глубина "
	_depth.suffix = " vox"
	_depth.min_value = 1
	_depth.max_value = 32
	_depth.step = 1
	_depth.value = 1
	_depth.custom_minimum_size.x = 166.0
	_depth.tooltip_text = (
		"Фиксированная глубина одного мазка. Повторное проведение до отпускания "
		+ "LMB не добавляет следующий слой."
	)
	_depth.value_changed.connect(func(_value: float) -> void: _on_brush_setting_changed())
	tool_settings.add_child(_depth)
	_application_mode = OptionButton.new()
	_application_mode.name = "VoxelSculptApplication"
	_application_mode.tooltip_text = (
		"Мазок рисует свободно; Точка применяет один отпечаток; "
		+ "Линия выбирается двумя точками и применяется только после preview."
	)
	_application_mode.add_item("Нанесение · мазок")
	_application_mode.set_item_metadata(0, BrushProfiles.APPLICATION_STROKE)
	_application_mode.add_item("Нанесение · точка")
	_application_mode.set_item_metadata(1, BrushProfiles.APPLICATION_POINT)
	_application_mode.add_item("Нанесение · линия A→B")
	_application_mode.set_item_metadata(2, BrushProfiles.APPLICATION_LINE)
	_application_mode.item_selected.connect(func(_index: int) -> void: _on_brush_setting_changed())
	tool_settings.add_child(_application_mode)
	_brush_shape = OptionButton.new()
	_brush_shape.name = "VoxelSculptShape"
	_brush_shape.tooltip_text = (
		"Круг подходит для органики; квадрат даёт ровное сечение балок, пазов и рамок."
	)
	_brush_shape.add_item("Форма · круг")
	_brush_shape.set_item_metadata(0, BrushProfiles.SHAPE_CIRCLE)
	_brush_shape.add_item("Форма · квадрат")
	_brush_shape.set_item_metadata(1, BrushProfiles.SHAPE_SQUARE)
	_brush_shape.item_selected.connect(func(_index: int) -> void: _on_brush_setting_changed())
	tool_settings.add_child(_brush_shape)
	_follow_surface = CheckButton.new()
	_follow_surface.name = "VoxelSculptFollowSurface"
	_follow_surface.text = "Направление: по поверхности"
	_follow_surface.set_pressed_no_signal(true)
	_follow_surface.tooltip_text = (
		"Включено: мазок следует видимым граням без перемычки через угол. "
		+ "Выключено: режим «Только одна грань» честно останавливается на её краю."
	)
	_follow_surface.toggled.connect(func(_active: bool) -> void: _on_brush_setting_changed())
	tool_settings.add_child(_follow_surface)
	_volume_operation = OptionButton.new()
	_volume_operation.name = "VoxelSculptVolumeOperation"
	_volume_operation.tooltip_text = "Одна кисть объёма: добавить перед гранью или снять видимые воксели."
	_volume_operation.add_item("Операция · добавить")
	_volume_operation.set_item_metadata(0, Model.TOOL_ADD)
	_volume_operation.add_item("Операция · убрать")
	_volume_operation.set_item_metadata(1, Model.TOOL_REMOVE)
	_volume_operation.item_selected.connect(_on_brush_profile_changed)
	tool_settings.add_child(_volume_operation)
	_relief_mode = OptionButton.new()
	_relief_mode.name = "VoxelSculptReliefMode"
	_relief_mode.tooltip_text = (
		"Наращивание — прежняя управляемая глина с ростом при удержании. "
		+ "Генератор рисует устойчивый природный рисунок, закреплённый в модели."
	)
	_relief_mode.add_item("Режим · наращивание")
	_relief_mode.set_item_metadata(0, BrushProfiles.RELIEF_BUILDUP)
	_relief_mode.add_item("Режим · генератор")
	_relief_mode.set_item_metadata(1, BrushProfiles.RELIEF_GENERATOR)
	_relief_mode.item_selected.connect(func(_index: int) -> void: _on_brush_setting_changed())
	_relief_mode.visible = false
	tool_settings.add_child(_relief_mode)
	_relief_direction = OptionButton.new()
	_relief_direction.name = "VoxelSculptReliefDirection"
	_relief_direction.tooltip_text = "Направление непрерывного нарастания при удержании LMB."
	_relief_direction.add_item("Направление · вверх")
	_relief_direction.set_item_metadata(0, 1)
	_relief_direction.add_item("Направление · вниз")
	_relief_direction.set_item_metadata(1, -1)
	_relief_direction.item_selected.connect(_on_brush_profile_changed)
	_relief_direction.visible = false
	tool_settings.add_child(_relief_direction)
	_relief_geometry = OptionButton.new()
	_relief_geometry.name = "VoxelSculptReliefGeometry"
	_relief_geometry.tooltip_text = "Сплошной режим заполняет объём; оболочка перестраивает только видимую поверхность и стенки."
	_relief_geometry.add_item("Геометрия · сплошная")
	_relief_geometry.set_item_metadata(0, "solid")
	_relief_geometry.add_item("Геометрия · оболочка")
	_relief_geometry.set_item_metadata(1, "shell")
	_relief_geometry.item_selected.connect(_on_brush_profile_changed)
	_relief_geometry.visible = false
	tool_settings.add_child(_relief_geometry)
	_relief_generator_style = OptionButton.new()
	_relief_generator_style.name = "VoxelSculptReliefGeneratorStyle"
	_relief_generator_style.tooltip_text = (
		"Почва даёт мягкие естественные перепады; гребни создают более резкие "
		+ "складки, берега и каменистые формы."
	)
	_relief_generator_style.add_item("Характер · почва")
	_relief_generator_style.set_item_metadata(0, BrushProfiles.RELIEF_SOIL)
	_relief_generator_style.add_item("Характер · гребни")
	_relief_generator_style.set_item_metadata(1, BrushProfiles.RELIEF_RIDGES)
	_relief_generator_style.item_selected.connect(func(_index: int) -> void: _on_brush_setting_changed())
	_relief_generator_style.visible = false
	tool_settings.add_child(_relief_generator_style)
	_relief_generator_direction = OptionButton.new()
	_relief_generator_direction.name = "VoxelSculptReliefGeneratorDirection"
	_relief_generator_direction.tooltip_text = (
		"Оба создаёт бугры и ямки вокруг исходной поверхности. Можно ограничить "
		+ "генератор только подъёмом или только углублением."
	)
	for entry in [["Направление · оба", 0], ["Направление · вверх", 1], ["Направление · вниз", -1]]:
		_relief_generator_direction.add_item(entry[0])
		_relief_generator_direction.set_item_metadata(
			_relief_generator_direction.item_count - 1, entry[1]
		)
	_relief_generator_direction.item_selected.connect(func(_index: int) -> void: _on_brush_setting_changed())
	_relief_generator_direction.visible = false
	tool_settings.add_child(_relief_generator_direction)
	_relief_generator_scale = OptionButton.new()
	_relief_generator_scale.name = "VoxelSculptReliefGeneratorScale"
	_relief_generator_scale.tooltip_text = "Размер повторяющихся природных форм в art-вокселях."
	for value in [4, 8, 16, 32, 64]:
		_relief_generator_scale.add_item("Размер формы · %d vox" % value)
		_relief_generator_scale.set_item_metadata(
			_relief_generator_scale.item_count - 1, value
		)
	_relief_generator_scale.select(2)
	_relief_generator_scale.item_selected.connect(func(_index: int) -> void: _on_brush_setting_changed())
	_relief_generator_scale.visible = false
	tool_settings.add_child(_relief_generator_scale)
	_relief_generator_detail = OptionButton.new()
	_relief_generator_detail.name = "VoxelSculptReliefGeneratorDetail"
	_relief_generator_detail.tooltip_text = (
		"Лёгкие оставляют редкие мягкие перепады в 1–2 вокселя. "
		+ "Остальные варианты сохраняют прежнюю плотную форму: больше — мельче и шероховатее."
	)
	for entry in [
		["Детали · лёгкие", 0],
		["Детали · мало", 1],
		["Детали · средне", 3],
		["Детали · много", 5],
	]:
		_relief_generator_detail.add_item(entry[0])
		_relief_generator_detail.set_item_metadata(
			_relief_generator_detail.item_count - 1, entry[1]
		)
	_relief_generator_detail.select(2)
	_relief_generator_detail.item_selected.connect(func(_index: int) -> void: _on_brush_setting_changed())
	_relief_generator_detail.visible = false
	tool_settings.add_child(_relief_generator_detail)
	_relief_variant_button = Button.new()
	_relief_variant_button.name = "VoxelSculptReliefVariant"
	_relief_variant_button.text = "Другой вариант"
	_relief_variant_button.tooltip_text = "Меняет устойчивый рисунок для следующих мазков."
	_relief_variant_button.pressed.connect(_on_relief_variant_pressed)
	_relief_variant_button.visible = false
	tool_settings.add_child(_relief_variant_button)
	_height_limit = OptionButton.new()
	_height_limit.name = "VoxelSculptHeightLimit"
	_height_limit.tooltip_text = (
		"Максимальный подъём/спуск одной колонки относительно формы при нажатии LMB. "
		+ "Повторные отсчёты внутри жеста не превышают предел."
	)
	for value in [1, 2, 4, 8, 12, 16, 20, 24]:
		_height_limit.add_item("Предел %d vox" % value)
		_height_limit.set_item_metadata(_height_limit.item_count - 1, value)
	_height_limit.select(3)
	_height_limit.visible = false
	tool_settings.add_child(_height_limit)
	_buildup_rate = OptionButton.new()
	_buildup_rate.name = "VoxelSculptBuildupRate"
	_buildup_rate.tooltip_text = (
		"Реальная скорость удержания: первый voxel появляется сразу, затем центр "
		+ "получает указанное число art-вокселей в секунду до выбранного предела."
	)
	for entry in [
		["Очень медленно · 1 vox/сек", 1],
		["Медленно · 2 vox/сек", 2],
		["Средне · 4 vox/сек", 4],
		["Быстро · 8 vox/сек", 8],
		["Очень быстро · 16 vox/сек", 16],
		["Экстремально · 32 vox/сек", 32],
	]:
		_buildup_rate.add_item(entry[0])
		_buildup_rate.set_item_metadata(_buildup_rate.item_count - 1, entry[1])
	_buildup_rate.select(3)
	_buildup_rate.visible = false
	tool_settings.add_child(_buildup_rate)
	_smooth_strength = OptionButton.new()
	_smooth_strength.name = "VoxelSculptSmoothStrength"
	_smooth_strength.tooltip_text = (
		"Максимальное изменение высоты одной колонки за один LMB-жест. "
		+ "Новый жест продолжает сглаживание."
	)
	for value in [1, 2, 4, 8]:
		_smooth_strength.add_item("Сила %d vox" % value)
		_smooth_strength.set_item_metadata(_smooth_strength.item_count - 1, value)
	_smooth_strength.select(1)
	_smooth_strength.visible = false
	tool_settings.add_child(_smooth_strength)
	_smooth_mode = OptionButton.new()
	_smooth_mode.name = "VoxelSculptSmoothMode"
	_smooth_mode.tooltip_text = (
		"Ступени усредняют ближайших соседей. Общий уровень берётся по устойчивой "
		+ "высоте вокруг всей области кисти."
	)
	_smooth_mode.add_item("Режим · ступени")
	_smooth_mode.set_item_metadata(0, BrushProfiles.SMOOTH_LOCAL)
	_smooth_mode.add_item("Режим · общий уровень")
	_smooth_mode.set_item_metadata(1, BrushProfiles.SMOOTH_COMMON)
	_smooth_mode.item_selected.connect(func(_index: int) -> void: _on_brush_setting_changed())
	_smooth_mode.visible = false
	tool_settings.add_child(_smooth_mode)
	_smooth_fill_pits = CheckButton.new()
	_smooth_fill_pits.name = "VoxelSculptSmoothFillPits"
	_smooth_fill_pits.text = "Обрабатывать ямки"
	_smooth_fill_pits.set_pressed_no_signal(true)
	_smooth_fill_pits.tooltip_text = (
		"Включено: поднимает впадины и опускает выступы к общему уровню. "
		+ "Выключено: только снимает бугорки."
	)
	_smooth_fill_pits.toggled.connect(func(_active: bool) -> void: _on_brush_setting_changed())
	_smooth_fill_pits.visible = false
	tool_settings.add_child(_smooth_fill_pits)
	_coarse = CheckBox.new()
	_coarse.name = "VoxelSculptCoarse"
	_coarse.text = "Крупно 2×2×2"
	_coarse.tooltip_text = "Один legacy-воксель равен 2×2×2 новой 32-grid сетки."
	_coarse.toggled.connect(_on_coarse_toggled)
	tool_settings.add_child(_coarse)
	_palette = OptionButton.new()
	_palette.name = "VoxelSculptPalette"
	_palette.custom_minimum_size.x = 150.0
	_palette.item_selected.connect(func(item: int) -> void: _select_palette_color(int(_palette.get_item_metadata(item))))
	tool_settings.add_child(_palette)
	_material_preset = OptionButton.new()
	_material_preset.name = "VoxelSculptMaterialPreset"
	_material_preset.custom_minimum_size.x = 190.0
	_material_preset.tooltip_text = (
		"Добавляет тонкий слой воды над нарисованным дном. Для пруда с единой "
		+ "высотой используйте «Заливка уровня»; цвет камней задаётся кистью «Красить»."
	)
	for entry in [
		["Без воды", 0],
		["Вода · прозрачная", 208],
		["Вода · заметная", 176],
		["Вода · едва видимая", 232],
	]:
		_material_preset.add_item(entry[0])
		_material_preset.set_item_metadata(_material_preset.item_count - 1, entry[1])
	_material_preset.select(1)
	_material_preset.visible = false
	tool_settings.add_child(_material_preset)
	_material_scope = OptionButton.new()
	_material_scope.name = "VoxelSculptMaterialScope"
	_material_scope.tooltip_text = (
		"Кисть рисует обычным мазком. Связанная область выбирает от клика "
		+ "соседние верхние воксели похожего цвета на одной высоте дна."
	)
	_material_scope.add_item("Применение · кисть")
	_material_scope.set_item_metadata(0, "brush")
	_material_scope.add_item("Применение · связанная область")
	_material_scope.set_item_metadata(1, "connected")
	_material_scope.item_selected.connect(_on_material_scope_changed)
	_material_scope.visible = false
	tool_settings.add_child(_material_scope)
	_material_tolerance = OptionButton.new()
	_material_tolerance.name = "VoxelSculptMaterialTolerance"
	_material_tolerance.tooltip_text = (
		"Допустимое отличие RGB-цвета от точки клика. Выбор всегда остаётся "
		+ "связным и не переходит на другую высоту дна."
	)
	for entry in [
		["Цвет · точно", 0.0],
		["Цвет · близкий 5%", 0.05],
		["Цвет · похожий 10%", 0.10],
		["Цвет · широкий 20%", 0.20],
	]:
		_material_tolerance.add_item(entry[0])
		_material_tolerance.set_item_metadata(_material_tolerance.item_count - 1, entry[1])
	_material_tolerance.select(1)
	_material_tolerance.visible = false
	tool_settings.add_child(_material_tolerance)
	_surface_fill_material = OptionButton.new()
	_surface_fill_material.name = "VoxelSculptSurfaceFillMaterial"
	_surface_fill_material.tooltip_text = (
		"Тип независимого слоя. Сейчас доступна вода; этот же контракт позже "
		+ "принимает лаву, яд, туман и другие плоские заполнения."
	)
	_surface_fill_material.add_item("Слой · вода")
	_surface_fill_material.set_item_metadata(0, Model.SURFACE_FILL_WATER)
	_surface_fill_material.add_item("Слой · удалить")
	_surface_fill_material.set_item_metadata(1, Model.SURFACE_FILL_NONE)
	_surface_fill_material.item_selected.connect(_on_surface_fill_options_changed)
	_surface_fill_material.visible = false
	tool_settings.add_child(_surface_fill_material)
	_surface_fill_level = OptionButton.new()
	_surface_fill_level.name = "VoxelSculptSurfaceFillLevel"
	_surface_fill_level.tooltip_text = (
		"Авто находит естественный край впадины. Ручной режим поднимает плоскость "
		+ "на выбранное число art-вокселей от точки клика и отклоняет протечки."
	)
	for entry in [
		["Уровень · авто до края", 0],
		["Уровень · +1 vox", 1],
		["Уровень · +2 vox", 2],
		["Уровень · +4 vox", 4],
		["Уровень · +8 vox", 8],
		["Уровень · +16 vox", 16],
	]:
		_surface_fill_level.add_item(entry[0])
		_surface_fill_level.set_item_metadata(_surface_fill_level.item_count - 1, entry[1])
	_surface_fill_level.item_selected.connect(_on_surface_fill_options_changed)
	_surface_fill_level.visible = false
	tool_settings.add_child(_surface_fill_level)
	_surface_fill_inset = OptionButton.new()
	_surface_fill_inset.name = "VoxelSculptSurfaceFillInset"
	_surface_fill_inset.tooltip_text = (
		"В автоуровне опускает поверхность ниже найденного края, чтобы берег "
		+ "оставался виден. Для очень мелкой впадины вода остаётся над дном."
	)
	for entry in [
		["Берег · на 1 vox ниже", 1],
		["Берег · вровень", 0],
		["Берег · на 2 vox ниже", 2],
	]:
		_surface_fill_inset.add_item(entry[0])
		_surface_fill_inset.set_item_metadata(_surface_fill_inset.item_count - 1, entry[1])
	_surface_fill_inset.visible = false
	tool_settings.add_child(_surface_fill_inset)
	_surface_fill_tint = OptionButton.new()
	_surface_fill_tint.name = "VoxelSculptSurfaceFillTint"
	_surface_fill_tint.tooltip_text = (
		"Оттенок всего связного водоёма при заливке. Авто использует цвет воды; "
		+ "цвет из палитры тонирует только воду, сохраняя нарисованное дно."
	)
	_surface_fill_tint.visible = false
	tool_settings.add_child(_surface_fill_tint)
	# Tool families may expose a different number of controls, but changing the
	# active mode must not make the Canvas jump under the pointer.
	tool_settings.custom_minimum_size.y = 70.0

	var split := HSplitContainer.new()
	split.name = "VoxelSculptMainSplit"
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 960
	root.add_child(split)
	var canvas_area := HBoxContainer.new()
	canvas_area.name = "VoxelSculptCanvasArea"
	canvas_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_area.add_theme_constant_override("separation", 6)
	split.add_child(canvas_area)

	_tool_rail = VBoxContainer.new()
	_tool_rail.name = "VoxelSculptToolRail"
	_tool_rail.custom_minimum_size.x = 168.0
	_tool_rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tool_rail.add_theme_constant_override("separation", 5)
	canvas_area.add_child(_tool_rail)
	var tools_heading := Label.new()
	tools_heading.text = "ОСНОВНЫЕ ИНСТРУМЕНТЫ"
	tools_heading.modulate = Color(0.60, 0.82, 0.94)
	_tool_rail.add_child(tools_heading)
	_select_tool_button = Button.new()
	_select_tool_button.name = "VoxelWorkshopSelectionTool"
	_select_tool_button.text = "⌗ Выделение · V"
	_select_tool_button.tooltip_text = "Выделить воксели рамкой, перенести, скопировать или отделить."
	_select_tool_button.toggle_mode = true
	_select_tool_button.theme_type_variation = &"WorkshopToolButton"
	_select_tool_button.pressed.connect(_open_selection_tool)
	_tool_rail.add_child(_select_tool_button)
	_stamp_tool_button = Button.new()
	_stamp_tool_button.name = "VoxelWorkshopStampTool"
	_stamp_tool_button.text = "▦ Штамп · библиотека"
	_stamp_tool_button.tooltip_text = "Открыть сохранение, выбор и размещение объёмных штампов."
	_stamp_tool_button.toggle_mode = true
	_stamp_tool_button.theme_type_variation = &"WorkshopToolButton"
	_stamp_tool_button.pressed.connect(_open_stamp_library)
	_tool_rail.add_child(_stamp_tool_button)
	var brushes_heading := Label.new()
	brushes_heading.text = "КИСТИ И ФОРМА"
	brushes_heading.modulate = Color(0.54, 0.64, 0.74)
	_tool_rail.add_child(brushes_heading)
	_tool = ItemList.new()
	_tool.name = "VoxelSculptTool"
	_tool.select_mode = ItemList.SELECT_SINGLE
	_tool.max_columns = 1
	_tool.same_column_width = true
	_tool.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tool.custom_minimum_size = Vector2(168.0, 170.0)
	for entry in [
		["▧ Лепка · объём", Model.TOOL_ADD],
		["▣ Покраска", Model.TOOL_PAINT],
		["◐ Материал / вода", Model.TOOL_MATERIAL],
		["▰ Заливка уровня", Model.TOOL_SURFACE_FILL],
		["⛰ Рельеф", Model.TOOL_RAISE],
		["▬ Площадка", Model.TOOL_LEVEL],
		["≈ Сгладить", Model.TOOL_SMOOTH],
		["╱ Склон A → B", Model.TOOL_RAMP],
	]:
		_tool.add_item(entry[0])
		_tool.set_item_metadata(_tool.item_count - 1, entry[1])
	_tool.select(0)
	_tool.item_selected.connect(_on_tool_selected)
	_tool_rail.add_child(_tool)
	_tool_rail.add_child(HSeparator.new())
	_palette_panel = PalettePanel.new()
	_palette_panel.name = "VoxelWorkshopPersistentPalette"
	_palette_panel.color_selected.connect(_select_palette_color)
	_palette_panel.operation_requested.connect(_apply_palette_operation)
	_palette_panel.pick_requested.connect(_toggle_color_pick)
	_palette_panel.editing_started.connect(_finish_palette_gesture)
	_tool_rail.add_child(_palette_panel)
	canvas_area.add_child(VSeparator.new())

	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "VoxelSculptViewportContainer"
	_viewport_container.custom_minimum_size = Vector2(240.0, 240.0)
	_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_container.focus_mode = Control.FOCUS_ALL
	# Stretch decouples layout minimum from the previous render-target size.
	# Otherwise opening a dock permanently locks the Canvas at its old width.
	_viewport_container.stretch = true
	_viewport_container.resized.connect(_sync_viewport_size)
	_viewport_container.gui_input.connect(_on_viewport_input)
	canvas_area.add_child(_viewport_container)
	_build_viewport()

	_sidebar_panel = VBoxContainer.new()
	_sidebar_panel.name = "VoxelWorkshopSidebar"
	# The real editor runs at 125% DPI on the primary authoring setup. This width
	# keeps the native work tabs visible without sacrificing the compact Canvas.
	_sidebar_panel.custom_minimum_size.x = 340.0
	_sidebar_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sidebar_panel.add_theme_constant_override("separation", 6)
	split.add_child(_sidebar_panel)
	_operation_panel = VBoxContainer.new()
	_operation_panel.name = "VoxelWorkshopActiveOperation"
	_operation_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_operation_panel.add_theme_constant_override("separation", 5)
	_sidebar_panel.add_child(_operation_panel)
	_sidebar_tabs = TabContainer.new()
	_sidebar_tabs.name = "VoxelWorkshopSidebarTabs"
	_sidebar_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sidebar_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sidebar_tabs.get_tab_bar().theme_type_variation = &"WorkshopTabBar"
	_sidebar_panel.add_child(_sidebar_tabs)

	var parts_tab := VBoxContainer.new()
	parts_tab.name = "Части"
	parts_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parts_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sidebar_tabs.add_child(parts_tab)
	_parts_sections = TabContainer.new()
	_parts_sections.name = "VoxelWorkshopPartsSections"
	_parts_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_parts_sections.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_parts_sections.get_tab_bar().theme_type_variation = &"WorkshopSubTabBar"
	parts_tab.add_child(_parts_sections)
	var selection_scroll := ScrollContainer.new()
	selection_scroll.name = "Выделение"
	selection_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	selection_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	selection_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_parts_sections.add_child(selection_scroll)
	var selection_tab := VBoxContainer.new()
	selection_tab.name = "VoxelWorkshopSelectionTab"
	selection_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_tab.add_theme_constant_override("separation", 8)
	selection_scroll.add_child(selection_tab)
	_selection_panel = SelectionPanel.new()
	_selection_panel.configure_history(_actions)
	_selection_panel.activation_requested.connect(_toggle_voxel_selection)
	_selection_panel.paint_requested.connect(_paint_voxel_selection)
	_selection_panel.transform_requested.connect(_transform_voxel_selection)
	_selection_panel.extract_requested.connect(_extract_voxel_selection)
	_selection_panel.selection_changed.connect(func(has_selection: bool) -> void: _groups_panel.set_can_create(has_selection))
	selection_tab.add_child(_selection_panel)
	_selection_interaction = preload("res://addons/ember_import/ember_voxel_selection_interaction.gd").new()
	_viewport_container.add_child(_selection_interaction)
	_selection_interaction.setup(self)

	var stamp_tab := VBoxContainer.new()
	stamp_tab.name = "Библиотека"
	stamp_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stamp_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stamp_tab.add_theme_constant_override("separation", 8)
	_sidebar_tabs.add_child(stamp_tab)
	_stamp_panel = preload("res://addons/ember_import/ember_voxel_stamp_panel.gd").new()
	_stamp_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stamp_tab.add_child(_stamp_panel)
	_stamp_panel.setup(self)
	_generator_panel = preload("res://addons/ember_import/ember_voxel_generator_panel.gd").new()
	_generator_panel.name = "Генератор"
	_sidebar_tabs.add_child(_generator_panel)
	_generator_panel.preview_changed.connect(_show_generator_preview)
	_generator_panel.assets_changed.connect(_on_generator_assets_changed)
	_sidebar_tabs.set_tab_hidden(_generator_panel.get_index(), true)
	_sidebar_tabs.tab_changed.connect(func(_index: int):
		if _generator_active():
			_generator_panel.context["manual_dirty"] = has_unsaved_changes()
			_switch_canvas_mode(CanvasMode.GENERATOR)
		else:
			_generator_panel._clear_preview()
			if _canvas_mode == CanvasMode.GENERATOR:
				_return_to_last_brush()
	)
	var groups_scroll := ScrollContainer.new()
	groups_scroll.name = "Группы"
	groups_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	groups_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	groups_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	groups_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_parts_sections.add_child(groups_scroll)
	var groups_tab := VBoxContainer.new()
	groups_tab.name = "VoxelWorkshopGroupsTab"
	groups_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	groups_tab.add_theme_constant_override("separation", 8)
	groups_scroll.add_child(groups_tab)
	_groups_panel = GroupsPanel.new()
	_groups_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_groups_panel.operation_requested.connect(_apply_group_operation)
	_groups_panel.select_requested.connect(_select_group_members)
	_groups_panel.isolate_requested.connect(_set_group_isolation)
	_groups_panel.visibility_requested.connect(_set_hidden_group_indices)
	groups_tab.add_child(_groups_panel)
	groups_tab.add_child(HSeparator.new())
	var part_heading := Label.new()
	part_heading.text = "ЧАСТЬ ДЛЯ НОВЫХ ВОКСЕЛЕЙ"
	part_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	part_heading.modulate = Color(0.60, 0.82, 0.94)
	groups_tab.add_child(part_heading)
	_part_selector = OptionButton.new()
	_part_selector.fit_to_longest_item = false
	_part_selector.clip_text = true
	_part_selector.tooltip_text = "К какой части склейки относятся новые воксели. Существующие воксели сохраняют свою часть; группы выделения от этого не меняются."
	_part_selector.item_selected.connect(_on_workshop_part_selected)
	groups_tab.add_child(_part_selector)
	var view_scroll := ScrollContainer.new()
	view_scroll.name = "Вид"
	view_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	view_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	view_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_parts_sections.add_child(view_scroll)
	var view_tab := VBoxContainer.new()
	view_tab.name = "VoxelWorkshopViewTab"
	view_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_tab.add_theme_constant_override("separation", 8)
	view_scroll.add_child(view_tab)
	_slice_control = SliceControl.new()
	_slice_control.change_requested.connect(_on_height_slice_changed)
	view_tab.add_child(_slice_control)
	view_tab.add_child(HSeparator.new())
	var region_heading := Label.new()
	region_heading.text = "РАБОЧАЯ ОБЛАСТЬ"
	region_heading.modulate = Color(0.60, 0.82, 0.94)
	view_tab.add_child(region_heading)
	_region_label = Label.new()
	_region_label.name = "VoxelSculptRegionLabel"
	_region_label.text = "Область: вся"
	_region_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_region_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	view_tab.add_child(_region_label)
	_region_select_button = Button.new()
	_region_select_button.name = "VoxelSculptRegionSelect"
	_region_select_button.text = "Выделить участок"
	_region_select_button.toggle_mode = true
	_region_select_button.tooltip_text = (
		"Два клика задают прямоугольную маску. Поверхность остаётся общей, "
		+ "но кисти не меняют контекст за границей участка."
	)
	_region_select_button.toggled.connect(_on_region_select_toggled)
	view_tab.add_child(_region_select_button)
	var whole_region := Button.new()
	whole_region.name = "VoxelSculptWholeRegion"
	whole_region.text = "Использовать всю поверхность"
	whole_region.pressed.connect(_use_whole_region)
	view_tab.add_child(whole_region)
	view_tab.add_child(HSeparator.new())
	var resource_heading := Label.new()
	resource_heading.text = "РЕСУРС"
	resource_heading.modulate = Color(0.60, 0.82, 0.94)
	view_tab.add_child(resource_heading)
	_resource_path_label = Label.new()
	_resource_path_label.text = Model.PILOT_PATH
	_resource_path_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_resource_path_label.modulate = Color(0.54, 0.64, 0.74)
	view_tab.add_child(_resource_path_label)
	_reset_button = Button.new()
	_reset_button.name = "ResetVoxelSurfacePilot"
	_reset_button.text = "Сбросить тестовый холст"
	_reset_button.tooltip_text = "Только для встроенного pilot Resource. Ctrl+Z отменяет."
	_reset_button.pressed.connect(_reset_pilot)
	view_tab.add_child(_reset_button)

	var footer := HFlowContainer.new()
	footer.name = "VoxelWorkshopFooter"
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_theme_constant_override("h_separation", 12)
	footer.add_theme_constant_override("v_separation", 4)
	_info = Label.new()
	_info.name = "VoxelWorkshopHelpStrip"
	_info.custom_minimum_size = Vector2(440.0, 30.0)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.size_flags_stretch_ratio = 1.6
	_info.clip_text = true
	_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_info.modulate = Color(0.60, 0.82, 0.94)
	footer.add_child(_info)
	_status = Label.new()
	_status.name = "VoxelSculptStatus"
	_status.custom_minimum_size = Vector2(260.0, 30.0)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.modulate = Color(0.66, 0.74, 0.84)
	footer.add_child(_status)
	_footer_stats = Label.new()
	_footer_stats.name = "VoxelWorkshopFooterStats"
	_footer_stats.text = "0 vox · сетка —"
	_footer_stats.modulate = Color(0.54, 0.64, 0.74)
	footer.add_child(_footer_stats)
	root.add_child(footer)
	_build_camera_popup()
	_on_tool_selected(0)


func _open_selection_tool() -> void:
	_switch_canvas_mode(
		CanvasMode.BRUSH
		if _canvas_mode in [CanvasMode.SELECTION, CanvasMode.SELECTION_TRANSFORM]
		else CanvasMode.SELECTION,
		true,
	)


func _open_stamp_library() -> void:
	_switch_canvas_mode(
		CanvasMode.BRUSH
		if _canvas_mode in [CanvasMode.STAMP_LIBRARY, CanvasMode.STAMP_DRAFT]
		else CanvasMode.STAMP_LIBRARY,
		true,
	)


func _show_stamp_library_mode(announce := false) -> void:
	_apply_canvas_mode(CanvasMode.STAMP_LIBRARY, announce)


func _select_workshop_stamp(display_name: String) -> void:
	_workshop_preset_name = display_name.strip_edges()
	_update_workshop_shell()


func _show_stamp_operation(display_name: String, pattern := false) -> void:
	_select_workshop_stamp(display_name)
	_apply_canvas_mode(CanvasMode.STAMP_DRAFT, false, pattern)


func _set_non_brush_tool_context(active: bool, keep_palette := false) -> void:
	var controls: Array[Control] = [
		_radius, _depth, _application_mode, _brush_shape, _follow_surface,
		_volume_operation, _relief_direction, _relief_geometry, _height_limit,
		_buildup_rate, _smooth_strength, _smooth_mode, _smooth_fill_pits,
		_coarse, _palette, _material_preset,
		_material_scope, _material_tolerance, _surface_fill_material,
		_surface_fill_level, _surface_fill_inset, _surface_fill_tint,
	]
	if active:
		if _non_brush_tool_visibility.is_empty():
			for control in controls:
				if is_instance_valid(control):
					_non_brush_tool_visibility[control] = control.visible
		for control in controls:
			if is_instance_valid(control):
				control.visible = false
		if keep_palette and is_instance_valid(_palette):
			_palette.visible = true
		return
	for raw_control in _non_brush_tool_visibility:
		var control := raw_control as Control
		if is_instance_valid(control):
			control.visible = bool(_non_brush_tool_visibility[raw_control])
	_non_brush_tool_visibility.clear()


func _switch_canvas_mode(next_mode: int, announce := false) -> void:
	if _switching_canvas_mode:
		return
	_switching_canvas_mode = true
	if is_instance_valid(_selection_interaction) and _selection_interaction.transforming:
		_selection_interaction.cancel_gesture(false)
	_flush_pending_stroke_position()
	_finish_stroke()
	_cancel_ramp_anchor(false)
	_cancel_precision_line(false)
	if next_mode != CanvasMode.COLOR_PICK:
		_set_color_pick(false)
	if next_mode != CanvasMode.REGION_SELECT:
		_region_anchor_block = Vector2i(-1, -1)
		_region_preview_blocks = Rect2i()
		if is_instance_valid(_region_select_button):
			_region_select_button.set_pressed_no_signal(false)
		_rebuild_region_overlay()
	_apply_canvas_mode(next_mode, announce)
	_switching_canvas_mode = false


func _apply_canvas_mode(next_mode: int, announce := false, pattern := false) -> void:
	_canvas_mode = next_mode
	if next_mode != CanvasMode.GENERATOR and _generator_active():
		_sidebar_tabs.current_tab = 0
	_canvas_pattern_context = pattern if next_mode == CanvasMode.STAMP_DRAFT else false
	var brush_mode := next_mode == CanvasMode.BRUSH
	var selection_mode := next_mode in [CanvasMode.SELECTION, CanvasMode.SELECTION_TRANSFORM]
	var stamp_mode := next_mode in [CanvasMode.STAMP_LIBRARY, CanvasMode.STAMP_DRAFT]
	if is_instance_valid(_tool):
		if brush_mode:
			_last_brush_item = clampi(_last_brush_item, 0, maxi(0, _tool.item_count - 1))
			_tool.select(_last_brush_item)
		else:
			_tool.deselect_all()
	if is_instance_valid(_select_tool_button):
		_select_tool_button.set_pressed_no_signal(selection_mode)
	if is_instance_valid(_stamp_tool_button):
		_stamp_tool_button.set_pressed_no_signal(stamp_mode)
	if is_instance_valid(_selection_panel):
		_selection_panel.set_selection_overlay_suspended(not selection_mode)
		_selection_panel.set_mask_suspended(
			not selection_mode
			and (
				not brush_mode
				or BrushProfiles.mask_kind(_selected_tool_id()) == BrushProfiles.MASK_NONE
			)
		)
		_selection_panel.set_active(
			selection_mode or next_mode == CanvasMode.STAMP_DRAFT
		)
	_set_non_brush_tool_context(
		not brush_mode,
		_canvas_pattern_context or next_mode == CanvasMode.COLOR_PICK,
	)
	if is_instance_valid(_cursor) and not brush_mode:
		_cursor.hide()
	if is_instance_valid(_sidebar_panel) and (selection_mode or stamp_mode):
		_sidebar_panel.visible = true
	if is_instance_valid(_sidebar_toggle) and (selection_mode or stamp_mode):
		_sidebar_toggle.set_pressed_no_signal(true)
	if selection_mode:
		if is_instance_valid(_sidebar_tabs):
			_sidebar_tabs.current_tab = 0
		if is_instance_valid(_parts_sections):
			_parts_sections.current_tab = 0
	elif stamp_mode and is_instance_valid(_sidebar_tabs):
		_sidebar_tabs.current_tab = 1
	match next_mode:
		CanvasMode.GENERATOR:
			_active_tool_label.text = "Генератор · рецепт"
			_info.text = "Настройки справа меняют рецепт, не исходник. Соберите предпросмотр; RMB/MMB/колесо управляют камерой."
			_set_status("Генератор активен · исходник не изменится · вариант сохраняется отдельно")
		CanvasMode.BRUSH:
			_update_tool_help(_selected_tool_id())
			if _resource != null:
				_set_status("Кисть активна · LMB рисует · Esc отменяет незавершённый жест")
			if is_instance_valid(_viewport_container):
				_update_cursor(_viewport_container.get_local_mouse_position())
		CanvasMode.SELECTION:
			_active_tool_label.text = "Выделение · область"
			_info.text = "Протяните рамку на Canvas. Shift добавляет, Ctrl убирает; действия с выбранным фрагментом находятся во вкладке «Части»."
			_set_status("Выделение активно · V или Esc возвращает последнюю кисть")
		CanvasMode.SELECTION_TRANSFORM:
			_active_tool_label.text = "Выделение · перенос"
			_info.text = "Настройте перенос, копию или поворот сверху панели. Предпросмотр не меняет модель; Enter применяет один шаг Undo."
		CanvasMode.STAMP_LIBRARY:
			_active_tool_label.text = "Штамп · библиотека"
			_info.text = "Выберите карточку штампа, затем разместите её на Canvas. ЛКМ на Canvas в библиотеке ничего не меняет."
			_set_status(
				"Библиотека штампов открыта · выберите пресет или сохраните текущее выделение"
				if announce else "Библиотека штампов · выберите пресет для размещения"
			)
		CanvasMode.STAMP_DRAFT:
			_update_tool_help(_selected_tool_id())
		CanvasMode.COLOR_PICK:
			_set_color_pick(true)
			_active_tool_label.text = "Пипетка · цвет"
			_info.text = "Щёлкните по вокселю, чтобы взять его цвет · Esc возвращает последнюю кисть."
			_set_status("Пипетка активна · выберите цвет на модели")
		CanvasMode.REGION_SELECT:
			if is_instance_valid(_region_select_button):
				_region_select_button.set_pressed_no_signal(true)
			_active_tool_label.text = "Рабочая область · два угла"
			_info.text = "Укажите два угла рабочей области. Кисти будут ограничены голубой рамкой · Esc отменяет."
			_set_status("Выделение участка: кликните первый угол · Esc отменяет")


func _return_to_last_brush() -> void:
	_switch_canvas_mode(CanvasMode.BRUSH)


func _show_selection_operation() -> void:
	_apply_canvas_mode(CanvasMode.SELECTION_TRANSFORM)


func _show_selection_mode() -> void:
	_apply_canvas_mode(CanvasMode.SELECTION)


func _on_workshop_part_selected(index: int) -> void:
	if _actions != null:
		_actions.active_part = index
	_update_workshop_shell()


func _update_workshop_shell() -> void:
	if is_instance_valid(_dirty_label):
		_dirty_label.text = "Не сохранено" if _resource != null and has_unsaved_changes() else "Сохранено"
		_dirty_label.modulate = (
			Color(1.0, 0.72, 0.30)
			if _resource != null and has_unsaved_changes()
			else Color(0.54, 0.64, 0.74)
		)
	if _resource == null:
		_sync_object_name_input(true)
		if is_instance_valid(_workshop_context_label):
			_workshop_context_label.text = "›  Модель —  ›  Часть —  ›  Пресет —"
		if is_instance_valid(_footer_stats):
			_footer_stats.text = "0 vox · сетка —"
		return
	var part := "Добавленное"
	if is_instance_valid(_part_selector) and _part_selector.visible and _part_selector.selected >= 0:
		part = _part_selector.get_item_text(_part_selector.selected).trim_prefix("Новые воксели → ")
	var model := _resource.model_id if not _resource.model_id.is_empty() else _resource_path.get_file().get_basename()
	if model.is_empty():
		model = "без ID"
	_sync_object_name_input()
	if is_instance_valid(_workshop_context_label):
		var model_name := _resource.display_name if not _resource.display_name.is_empty() else model
		var preset_name := _workshop_preset_name if not _workshop_preset_name.is_empty() else "—"
		_workshop_context_label.text = "›  Модель %s (%s)  ›  Часть %s  ›  Пресет %s" % [
			model_name,
			model,
			part,
			preset_name,
		]
		_workshop_context_label.tooltip_text = (
			"Voxel-модель: %s · ID: %s · часть: %s · пресет: %s"
			% [model_name, model, part, preset_name]
		)
	if is_instance_valid(_footer_stats):
		var occupied := _resource.voxels.size() - _resource.voxels.count(0)
		_footer_stats.text = "%d vox · сетка %d" % [occupied, _resource.normalized_density()]


func _sync_object_name_input(force := false) -> void:
	if not is_instance_valid(_object_name_input):
		return
	var can_rename: bool = _object_session != null and _object_session.has_method("target_name") and _object_session.has_method("rename_target") and not _object_session.target_name().is_empty()
	_object_name_input.editable = can_rename
	_object_name_input.tooltip_text = (
		"Имя выбранного экземпляра в дереве сцены. Enter или переход к другому полю применяет; Esc отменяет ввод."
		if can_rename
		else "Surface редактируется как ресурс; отдельного объекта сцены для переименования здесь нет."
	)
	if not can_rename:
		_object_name_input.text = ""
		return
	if force or not _object_name_input.has_focus():
		var current_name: String = _object_session.target_name()
		if _object_name_input.text != current_name:
			_object_name_input.text = current_name


func _submit_object_name(_submitted: String) -> void:
	_commit_object_name()
	_object_name_input.release_focus()


func _commit_object_name() -> void:
	if _object_session == null or not _object_session.has_method("target_name") or not _object_session.has_method("rename_target") or not is_instance_valid(_object_name_input):
		return
	var previous_name: String = _object_session.target_name()
	if _object_name_input.text.strip_edges() == previous_name:
		_object_name_input.text = previous_name
		return
	var result: Dictionary = _object_session.rename_target(_object_name_input.text)
	if not bool(result.get("ok", false)):
		_object_name_input.text = previous_name
		_set_status(str(result.get("error", "Не удалось переименовать объект")), true)
		return
	_object_name_input.text = str(result.get("name", previous_name))
	_set_status("Объект переименован · сохраните сцену обычным Ctrl+S в 3D")


func _on_object_name_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_object_name_input.text = _object_session.target_name() if _object_session != null and _object_session.has_method("target_name") else ""
		_object_name_input.release_focus()
		_object_name_input.accept_event()


func _build_camera_popup() -> void:
	_camera_popup = PopupPanel.new()
	_camera_popup.name = "VoxelSurfaceCameraPopup"
	add_child(_camera_popup)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(330.0, 0.0)
	panel.add_theme_constant_override("separation", 7)
	_camera_popup.add_child(panel)
	var title := Label.new()
	title.text = "КАМЕРА SURFACE CANVAS"
	title.modulate = Color(0.60, 0.82, 0.94)
	panel.add_child(title)
	var hint := Label.new()
	hint.text = "RMB вращение · MMB сдвиг · колесо масштаб · Home вписать"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(hint)
	_camera_yaw_control = _camera_spin("VoxelSurfaceCameraYaw", "Поворот", -180.0, 180.0, 1.0, "°", panel)
	_camera_pitch_control = _camera_spin("VoxelSurfaceCameraPitch", "Наклон", -88.0, 88.0, 1.0, "°", panel)
	_camera_size_control = _camera_spin("VoxelSurfaceCameraSize", "Масштаб", 1.5, 128.0, 0.25, "", panel)
	_camera_margin_control = _camera_spin("VoxelSurfaceCameraMargin", "Запас кадра", 1.0, 2.5, 0.05, "×", panel)
	_camera_yaw_control.value_changed.connect(_on_camera_yaw_changed)
	_camera_pitch_control.value_changed.connect(_on_camera_pitch_changed)
	_camera_size_control.value_changed.connect(_on_camera_size_changed)
	_camera_margin_control.value_changed.connect(_on_camera_margin_changed)
	var actions := HBoxContainer.new()
	panel.add_child(actions)
	var fit := Button.new()
	fit.text = "Вписать поверхность"
	fit.pressed.connect(_fit_camera_to_surface)
	actions.add_child(fit)
	var top := Button.new()
	top.text = "Сверху"
	top.pressed.connect(_set_top_camera)
	actions.add_child(top)
	_sync_camera_controls()


func _camera_spin(
	control_name: String,
	label_text: String,
	minimum: float,
	maximum: float,
	step: float,
	suffix: String,
	parent: VBoxContainer,
) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 120.0
	row.add_child(label)
	var spin := SpinBox.new()
	spin.name = control_name
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.suffix = suffix
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	return spin


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "VoxelSculptViewport"
	_viewport.size = Vector2i(960, 640)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport_container.add_child(_viewport)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#101923")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#9eb3c8")
	environment.ambient_light_energy = 0.72
	environment_node.environment = environment
	_viewport.add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-58.0, -38.0, 0.0)
	light.light_color = Color("#ffe1b2")
	light.light_energy = 1.25
	light.shadow_enabled = true
	_viewport.add_child(light)
	_surface_root = Node3D.new()
	_surface_root.name = "SurfaceChunks"
	_viewport.add_child(_surface_root)
	_scene_context = preload("res://addons/ember_import/ember_voxel_canvas_context.gd").new()
	_scene_context.name = "ObjectSceneContext"
	_scene_context.visible = false
	_viewport.add_child(_scene_context)
	_grid = MeshInstance3D.new()
	_grid.name = "GameplayBlockOverlay"
	_viewport.add_child(_grid)
	_region_overlay = MeshInstance3D.new()
	_region_overlay.name = "VoxelSculptRegionOverlay"
	_region_overlay.visible = false
	_viewport.add_child(_region_overlay)
	_cursor = MeshInstance3D.new()
	_cursor.name = "BrushCursor"
	_cursor.visible = false
	var cursor_material := StandardMaterial3D.new()
	cursor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cursor_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cursor_material.albedo_color = Color(1.0, 0.75, 0.24, 0.38)
	_cursor.material_override = cursor_material
	_viewport.add_child(_cursor)
	_precision_line_preview = MultiMeshInstance3D.new()
	_precision_line_preview.name = "PrecisionLinePreview"
	_precision_line_preview.visible = false
	_precision_line_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_viewport.add_child(_precision_line_preview)
	_ramp_anchor_marker = MeshInstance3D.new()
	_ramp_anchor_marker.name = "RampAnchor"
	_ramp_anchor_marker.visible = false
	var anchor_mesh := CylinderMesh.new()
	anchor_mesh.top_radius = 0.10
	anchor_mesh.bottom_radius = 0.10
	anchor_mesh.height = 0.035
	anchor_mesh.radial_segments = 20
	_ramp_anchor_marker.mesh = anchor_mesh
	var anchor_material := StandardMaterial3D.new()
	anchor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	anchor_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	anchor_material.albedo_color = Color(0.20, 0.90, 1.0, 0.82)
	_ramp_anchor_marker.material_override = anchor_material
	_viewport.add_child(_ramp_anchor_marker)
	_camera = Camera3D.new()
	_camera.name = "SculptCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_viewport.add_child(_camera)
	_update_camera()
	_sync_viewport_size.call_deferred()


func _sync_viewport_size() -> void:
	if _viewport == null or _viewport_container == null:
		return
	var requested := Vector2i(
		maxi(1, roundi(_viewport_container.size.x)),
		maxi(1, roundi(_viewport_container.size.y)),
	)
	var largest := maxi(requested.x, requested.y)
	_viewport_container.stretch_shrink = maxi(1, ceili(float(largest) / MAX_VIEWPORT_DIMENSION))


func _refresh_palette() -> void:
	var selected := int(_palette.get_item_metadata(_palette.selected)) if _palette.selected >= 0 else 1
	var tint := _surface_fill_tint.selected
	if _resource != null and _displayed_palette.size() != _resource.palette.size():
		selected = _matching_palette_index(selected)
		tint = _matching_palette_index(tint)
	_palette.clear()
	_surface_fill_tint.clear()
	_surface_fill_tint.add_item("Вода · оттенок авто")
	_surface_fill_tint.set_item_metadata(0, 0)
	if _resource == null:
		_palette_panel.sync(null, 1)
		_displayed_palette = PackedColorArray()
		return
	for index in range(1, _resource.palette.size()):
		_palette.add_icon_item(PalettePanel.swatch(_resource.palette[index], 18), "Цвет %d · #%s" % [index, _resource.palette[index].to_html(false)])
		_palette.set_item_metadata(_palette.item_count - 1, index)
		_surface_fill_tint.add_item("Вода · цвет %d" % index)
		_surface_fill_tint.set_item_metadata(_surface_fill_tint.item_count - 1, index)
	_surface_fill_tint.select(clampi(tint, 0, _surface_fill_tint.item_count - 1))
	_displayed_palette = _resource.palette.duplicate()
	_select_palette_color(selected)


func _matching_palette_index(index: int) -> int:
	if index > 0 and index < _displayed_palette.size():
		var color := _displayed_palette[index]
		if index < _resource.palette.size() and _resource.palette[index] == color:
			return index
		var match_index := _resource.palette.find(color)
		if match_index > 0:
			return match_index
	return index


func _finish_palette_gesture() -> void:
	_flush_pending_stroke_position()
	_finish_stroke()
	_set_color_pick(false)


func _select_palette_color(index: int) -> void:
	if _resource == null or _palette.item_count == 0:
		return
	_set_color_pick(false)
	index = clampi(index, 1, _resource.palette.size() - 1)
	_palette.select(index - 1)
	_palette_panel.sync(_resource, index)


func _apply_palette_operation(resource: EmberVoxelModelResource, operation: Dictionary) -> void:
	if resource != _resource or resource == null:
		return
	_finish_palette_gesture()
	var tint := _surface_fill_tint.selected
	var result := _actions.apply_palette(resource, operation)
	if result.has("error"):
		_set_status(str(result["error"]), true)
		return
	if operation.get("kind") == "merge":
		var removed := int(operation["index"])
		if tint == removed:
			tint = int(operation["target"])
		tint -= 1 if tint > removed else 0
	elif operation.get("kind") == "ramp" and tint > 0:
		var source := int(operation["index"])
		var ramp_size := (operation.get("colors", PackedColorArray()) as PackedColorArray).size()
		if tint == source:
			tint = source + ramp_size / 2
		elif tint > source:
			tint += ramp_size - 1
	_surface_fill_tint.select(clampi(tint, 0, _surface_fill_tint.item_count - 1))
	_select_palette_color(int(result["selected"]))
	_set_status(str(result["label"]) + " · вся модель · Ctrl+Z отменить · Ctrl+S сохранить")


func _toggle_color_pick() -> void:
	if _resource == null:
		return
	_switch_canvas_mode(
		CanvasMode.BRUSH if _canvas_mode == CanvasMode.COLOR_PICK else CanvasMode.COLOR_PICK
	)


func _set_color_pick(active: bool) -> void:
	_picking_color = active
	if is_instance_valid(_palette_panel):
		_palette_panel.set_pick_active(active)
	if is_instance_valid(_viewport_container):
		_viewport_container.mouse_default_cursor_shape = Control.CURSOR_CROSS if active else Control.CURSOR_ARROW


func _pick_palette_color(position: Vector2) -> void:
	var pick := _pick_at(position)
	if not pick.has("hit") or _resource == null:
		return
	var index := Model.index_of(pick["hit"], _resource.grid_size())
	_select_palette_color(int(_resource.voxels[index]))
	_return_to_last_brush()
	_set_status("Цвет взят с вокселя · теперь можно рисовать")


func _toggle_voxel_selection() -> void:
	_switch_canvas_mode(
		CanvasMode.BRUSH
		if _canvas_mode in [CanvasMode.SELECTION, CanvasMode.SELECTION_TRANSFORM]
		else CanvasMode.SELECTION
	)


func _transform_voxel_selection() -> void:
	_finish_palette_gesture()
	if _resource == null or _selection_panel.busy():
		return
	_selection_interaction.begin_transform()

func _extract_voxel_selection(cut: bool) -> void:
	_finish_palette_gesture()
	_finish_stroke()
	if _resource == null or _selection_panel.busy():
		return
	if _selection_interaction.transforming or _selection_interaction.dragging:
		_set_status("Сначала примените или отмените текущий жест (Enter / Esc)",true)
		return
	if has_unsaved_changes():
		_set_status("Сначала сохраните правки Canvas. Выделение останется; затем повторите отделение.",true)
		return
	var extraction := preload("res://addons/ember_import/ember_voxel_extraction_session.gd").new()
	var indices: PackedInt32Array = _selection_panel.selection_indices()
	if not extraction.prepare(_object_session,_resource,indices,cut):
		_set_status(extraction.error,true)
		return
	var source := _resource
	var dialog := ConfirmationDialog.new()
	dialog.title = "Вырезать фрагмент" if cut else "Скопировать фрагмент"
	dialog.dialog_text = "Выделено: %d vox → отдельный объект Fragment на том же месте.\n%s\nБез переключателя ниже вы продолжите работу в Canvas исходного объекта.\nОдно Undo отменяет операцию; файлы автоматически не удаляются." % [indices.size(),"Выбранные воксели исчезнут из исходного объекта." if cut else "Исходный объект останется без изменений; копия совпадёт с ним по положению."]
	var go_to_3d := CheckBox.new()
	go_to_3d.name = "ExtractionGoTo3D"
	go_to_3d.text = "Перейти в 3D к новой детали"
	go_to_3d.button_pressed = _extraction_go_to_3d
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(640,180)
	var description := Label.new()
	description.custom_minimum_size.x = 640
	description.text = dialog.dialog_text
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.dialog_text = ""
	dialog.add_child(content)
	content.add_child(description)
	content.add_child(go_to_3d)
	var edit := _object_session
	dialog.get_ok_button().text = "Вырезать" if cut else "Скопировать"
	dialog.get_cancel_button().text = "Отмена"
	dialog.dialog_hide_on_ok = false
	dialog.confirmed.connect(func() -> void:
		if _resource != source or has_unsaved_changes():
			_set_status("Canvas изменился; откройте отделение заново",true)
			dialog.queue_free()
			return
		var prop: EmberVoxelProp = extraction.commit(_actions._undo_redo)
		if prop == null:
			_set_status(extraction.error,true)
			dialog.queue_free()
			return
		_selection_interaction.cancel_gesture()
		_extraction_go_to_3d = go_to_3d.button_pressed
		extraction.state_applied.connect(_refresh_extraction_canvas.bind(edit))
		if not _extraction_go_to_3d:
			_refresh_extraction_canvas(edit)
			dialog.queue_free()
			return
		_disconnect_resource()
		_object_session = null
		_context_toggle.set_pressed_no_signal(false)
		_toggle_scene_context(false)
		_set_status("Фрагмент создан. Сохраните сцену в 3D; Ctrl+Z отменяет отделение.")
		dialog.queue_free()
		if Engine.is_editor_hint():
			EditorInterface.set_main_screen_editor("3D")
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(680,300))

func _refresh_extraction_canvas(edit: RefCounted) -> void:
	if _object_session != edit:
		return
	if has_unsaved_changes():
		_set_status("Состояние сцены изменилось через Undo/Redo. Черновик оставлен; перед сохранением откройте объект заново.",true)
		return
	var view := _capture_editor_view_state()
	var context_visible := _context_toggle.button_pressed
	if not edit.refresh_before_open():
		_disconnect_resource()
		_set_status("Сцена обновлена, но Canvas не удалось открыть: " + str(edit.error),true)
		return
	_open_object_unchecked(edit)
	_restore_editor_view_state(view)
	_context_toggle.button_pressed = context_visible
	if Engine.is_editor_hint():
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(edit._target.get_ref())
	_set_status("Canvas обновлён · фрагмент — отдельный объект в сцене · сохраните сцену в 3D")

func _paint_voxel_selection(indices: PackedInt32Array) -> void:
	_finish_palette_gesture()
	if _resource == null or _palette.selected < 0:
		return
	var color := int(_palette.get_selected_metadata())
	var changes := {}
	var protected := 0
	for index in indices:
		var cell := SelectionPanel.Selection.cell_of(index, _resource.grid_size())
		if not _cell_in_edit_region(cell) or index < 0 or index >= _resource.voxels.size():
			continue
		if _locked_indices.has(index):
			protected += 1
			continue
		var before := int(_resource.voxels[index])
		if before > 0 and before != color:
			changes[index] = {"before": before, "after": color}
	if not _actions.apply_stroke(_resource, changes):
		_set_status("Изменений нет · %d вокселей защищены группами" % protected if protected > 0 else "Выбранные воксели уже этого цвета", protected > 0)
		return
	_set_status("Окрашено %d вокселей%s · форма и вода сохранены · Ctrl+Z отменяет" % [changes.size(), " · защищено %d" % protected if protected > 0 else ""])


func _refresh_groups(preferred_id := "") -> void:
	if _part_selector != null:
		_part_selector.clear()
		_part_selector.visible = _resource != null and not _resource.merge_parts.is_empty()
		_part_selector.add_item("Новые воксели → Добавленное")
		if _resource != null:
			for part in _resource.merge_parts:
				_part_selector.add_item("Новые воксели → " + part)
		_part_selector.disabled = _actions == null
		if _actions != null:
			_actions.active_part = clampi(_actions.active_part,0,_part_selector.item_count-1)
			_part_selector.select(_actions.active_part)
	if _resource == null:
		_displayed_groups = []
		_locked_indices.clear()
		_groups_panel.sync([], "")
		_update_workshop_shell()
		return
	_displayed_groups = _resource.voxel_groups.duplicate(true)
	_locked_indices = Groups.locked_indices(_resource.voxel_groups)
	_groups_panel.sync(_resource.voxel_groups, preferred_id)
	_groups_panel.set_can_create(not _selection_panel.selected.is_empty())
	_update_workshop_shell()


func _apply_group_operation(operation: Dictionary) -> void:
	if _resource == null:
		return
	_finish_palette_gesture()
	if operation.get("kind") in ["create", "replace"]:
		operation = operation.duplicate()
		operation["indices"] = _selection_panel.selection_indices()
	var result := _actions.apply_groups(_resource, operation)
	if result.has("error"):
		_set_status(str(result["error"]), true)
		_refresh_groups(_groups_panel.selected_id())
		return
	_refresh_groups(str(result.get("selected", "")))
	_set_status(str(result["label"]) + " · Ctrl+Z отменяет · Ctrl+S сохраняет")


func _select_group_members(indices: PackedInt32Array, color := SelectionPanel.DEFAULT_OVERLAY_COLOR) -> void:
	_selection_panel.set_selection(indices, color)
	_groups_panel.set_can_create(not indices.is_empty())
	_set_status("Группа выбрана: %d вокселей" % indices.size())


func _set_group_isolation(indices: PackedInt32Array, enabled: bool) -> void:
	_isolated_group_indices = indices.duplicate() if enabled else PackedInt32Array()
	_rebuild_group_view_filter()
	_set_status("Изоляция группы · вода скрыта · данные не изменены" if enabled else "Полный просмотр восстановлен" if _hidden_group_indices.is_empty() else "Скрытые группы не показаны · данные не изменены")


func _set_hidden_group_indices(indices: PackedInt32Array) -> void:
	_hidden_group_indices = indices.duplicate()
	_rebuild_group_view_filter()
	_set_status("Полный просмотр восстановлен" if indices.is_empty() else "Скрыто вокселей групп: %d · только вид редактора" % indices.size())


func _rebuild_group_view_filter() -> void:
	_isolation_resource = null
	if _resource != null and (not _isolated_group_indices.is_empty() or not _hidden_group_indices.is_empty()):
		_isolation_resource = _resource.duplicate(true) as EmberVoxelModelResource
		var values := _resource.voxels.duplicate()
		if not _isolated_group_indices.is_empty():
			values.fill(0)
			for index in _isolated_group_indices:
				if index >= 0 and index < values.size():
					values[index] = _resource.voxels[index]
		else:
			for index in _hidden_group_indices:
				if index >= 0 and index < values.size():
					values[index] = 0
		_isolation_resource.voxels = values
		if not _isolated_group_indices.is_empty():
			_isolation_resource.surface_fill_levels = PackedInt32Array()
			_isolation_resource.surface_fill_materials = PackedByteArray()
			_isolation_resource.surface_fill_palette = PackedByteArray()
	_rebuild_visual()


func _rebuild_visual(indices := PackedInt32Array(), rebuild_grid := true) -> void:
	if _resource == null or _surface_root == null:
		return
	var grid_size := _resource.grid_size()
	if (
		_surface_heightfield.size() != grid_size.x * grid_size.z
		or (indices.is_empty() and _resource.voxels != _heightfield_source_voxels)
	):
		_surface_heightfield = Model.column_heights(
			_resource.voxels, grid_size, _resource.palette.size() - 1
		)
	elif not indices.is_empty():
		_surface_heightfield = Model.refresh_column_heights(
			_surface_heightfield,
			_resource.voxels,
			grid_size,
			indices,
			_resource.palette.size() - 1,
		)
	_heightfield_source_voxels = _resource.voxels
	_pending_preview_chunks.clear()
	var chunks := _all_preview_chunks() if indices.is_empty() else _affected_preview_chunks(indices)
	if indices.is_empty() and chunks.size() > 64:
		for chunk in chunks:
			_pending_preview_chunks[chunk] = false
	else:
		for chunk in chunks:
			_rebuild_chunk(chunk)
	if rebuild_grid:
		_rebuild_grid()
	_rebuild_region_overlay()
	_update_cursor(_viewport_container.get_local_mouse_position())


func _queue_visual_rebuild(indices: PackedInt32Array, draft_relief := false) -> void:
	if _resource == null:
		return
	for chunk in _affected_preview_chunks(indices):
		# Exact rebuild always wins over a still-pending draft for this chunk.
		if not _pending_preview_chunks.has(chunk) or not draft_relief:
			_pending_preview_chunks[chunk] = draft_relief


func _drain_preview_chunk() -> void:
	if _pending_preview_chunks.is_empty() or _resource == null:
		return
	var deadline := Time.get_ticks_usec() + PREVIEW_REBUILD_BUDGET_USEC
	while not _pending_preview_chunks.is_empty():
		var chunk := Vector2i(-1, -1)
		for pending in _pending_preview_chunks:
			chunk = pending
			break
		if chunk.x < 0:
			break
		var draft_relief := bool(_pending_preview_chunks.get(chunk, false))
		_pending_preview_chunks.erase(chunk)
		_rebuild_chunk(chunk, draft_relief)
		# Always make progress, but keep multiple fast native chunks inside one
		# frame instead of stretching a dry large Surface over hundreds of frames.
		if Time.get_ticks_usec() >= deadline:
			break
	if _pending_preview_chunks.is_empty():
		_update_cursor(_viewport_container.get_local_mouse_position())


func _rebuild_chunk(chunk: Vector2i, draft_relief := false) -> void:
	var preview_resource := _isolation_resource if _isolation_resource != null else _resource
	var size := preview_resource.grid_size()
	var region_min := Vector3i(chunk.x * PREVIEW_CHUNK_SIZE, 0, chunk.y * PREVIEW_CHUNK_SIZE)
	if region_min.x >= size.x or region_min.z >= size.z:
		return
	var region_size := Vector3i(
		mini(PREVIEW_CHUNK_SIZE, size.x - region_min.x),
		size.y,
		mini(PREVIEW_CHUNK_SIZE, size.z - region_min.z),
	)
	var voxel_size := 1.0 / float(preview_resource.normalized_density())
	var opaque := SurfaceMaterials.opaque_material()
	var transparent := SurfaceMaterials.water_material()
	var foam := SurfaceMaterials.foam_material()
	var include_water := _shows_water_overlay() and _isolation_resource == null
	var preview_transparency := (
		preview_resource.transparency if include_water else PackedByteArray()
	)
	var has_water := (
		include_water
		and SurfaceMesher.region_has_water_overlay(
			preview_resource, region_min, region_size
		)
	)
	# The stock draft is cheaper while LMB is held. Voxel Tools produces the
	# exact greedy mesh after pointer-up, without blocking every buildup tick.
	var projection: Dictionary = (
		_native_preview.build_region(
			preview_resource.voxels,
			size,
			preview_resource.palette,
			preview_transparency,
			region_min,
			region_size,
			voxel_size,
			opaque,
			transparent,
			_slice_height,
		)
		if (
			not draft_relief
			and not has_water
			and _native_preview != null
			and NativePreview.available()
		)
		else {}
	)
	var mesh := projection.get("mesh") as Mesh
	if mesh == null:
		mesh = SurfaceMesher.build_region(
			preview_resource,
			region_min,
			region_size,
			voxel_size,
			draft_relief,
			include_water,
			_slice_height,
		)
		projection = {"position": Vector3.ZERO, "scale": Vector3.ONE}
	for surface_index in mesh.get_surface_count():
		var surface_name: StringName = mesh.surface_get_name(surface_index)
		mesh.surface_set_material(
			surface_index,
			transparent if surface_name == "water"
			else foam if surface_name == "water_foam"
			else opaque,
		)
	var visual := _chunk_meshes.get(chunk) as MeshInstance3D
	if visual == null:
		visual = MeshInstance3D.new()
		visual.name = "Chunk_%d_%d" % [chunk.x, chunk.y]
		_surface_root.add_child(visual)
		_chunk_meshes[chunk] = visual
	visual.position = projection.get("position", Vector3.ZERO)
	visual.scale = projection.get("scale", Vector3.ONE)
	visual.mesh = mesh if mesh.get_surface_count() > 0 else null
	visual.visible = true


func _shows_water_overlay() -> bool:
	if _slice_height >= 0:
		return false
	if not is_instance_valid(_surface_layer_view) or _surface_layer_view.selected < 0:
		return true
	return String(
		_surface_layer_view.get_item_metadata(_surface_layer_view.selected)
	) != "floor"


func _on_surface_layer_view_changed(_index: int) -> void:
	_flush_pending_stroke_position()
	_finish_stroke()
	_cancel_precision_line(false)
	if _resource == null:
		return
	_rebuild_visual(PackedInt32Array(), false)
	_set_status(
		"Вид: дно + вода · финальный water overlay виден."
		if _shows_water_overlay()
		else "Вид: только дно · вода временно скрыта, её маска сохранена."
	)


func _on_height_slice_changed(enabled: bool, height: int) -> void:
	if _resource == null:
		return
	_flush_pending_stroke_position()
	_finish_stroke()
	_cancel_ramp_anchor(false)
	_cancel_precision_line(false)
	_cancel_region_selection()
	_slice_height = clampi(height, 1, _resource.grid_size().y) if enabled else -1
	_update_slice_tools()
	# A spinbox may emit repeatedly. Replace the queue, not the whole model;
	# hide stale full-height meshes until their clipped chunks are ready.
	_pending_preview_chunks.clear()
	for visual in _chunk_meshes.values():
		visual.visible = false
	for chunk in _all_preview_chunks():
		_pending_preview_chunks[chunk] = false
	_rebuild_grid()
	_rebuild_region_overlay()
	_update_cursor(_viewport_container.get_local_mouse_position())
	_set_status(
		"Срез: нижние %d vox · верх защищён · вода скрыта" % _slice_height
		if enabled else "Полная высота восстановлена · данные не изменены"
	)


func _slice_allows_tool(tool_id: int) -> bool:
	return _slice_height < 0 or tool_id in [
		Model.TOOL_ADD, Model.TOOL_REMOVE, Model.TOOL_PAINT, Model.TOOL_MATERIAL,
	]


func _update_slice_tools() -> void:
	for item in _tool.item_count:
		var base_tool := int(_tool.get_item_metadata(item))
		_tool.set_item_disabled(item, not _slice_allows_tool(_resolved_base_tool(base_tool)))
	if not _slice_allows_tool(_selected_tool_id()):
		var paint_item := _find_tool_item(Model.TOOL_PAINT)
		if paint_item >= 0:
			_tool.select(paint_item) # Existing paint tool, not a second implementation.
	_material_scope.disabled = _slice_height >= 0
	if _slice_height >= 0:
		_material_scope.select(0) # Explicit local brush; hidden voxels cannot link a flood.
	_surface_layer_view.disabled = _slice_height >= 0
	_on_tool_selected(0)


func _all_preview_chunks() -> Array[Vector2i]:
	var chunks: Array[Vector2i] = []
	var size := _resource.grid_size()
	var count_x := ceili(float(size.x) / PREVIEW_CHUNK_SIZE)
	var count_z := ceili(float(size.z) / PREVIEW_CHUNK_SIZE)
	# A world map can contain hundreds of preview chunks. Build the selected
	# authoring scope first so opening a distant rectangle never waits for every
	# row before it to render; unchanged surrounding context follows afterwards.
	var priority := Rect2i()
	if _edit_region_blocks.has_area():
		var density := _resource.normalized_density()
		var priority_from := Vector2i(
			floori(float(_edit_region_blocks.position.x * density) / PREVIEW_CHUNK_SIZE),
			floori(float(_edit_region_blocks.position.y * density) / PREVIEW_CHUNK_SIZE),
		)
		var priority_end := Vector2i(
			ceili(float(_edit_region_blocks.end.x * density) / PREVIEW_CHUNK_SIZE),
			ceili(float(_edit_region_blocks.end.y * density) / PREVIEW_CHUNK_SIZE),
		)
		priority = Rect2i(priority_from, priority_end - priority_from)
		for z in range(priority.position.y, priority.end.y):
			for x in range(priority.position.x, priority.end.x):
				chunks.append(Vector2i(x, z))
	for z in count_z:
		for x in count_x:
			var chunk := Vector2i(x, z)
			if not priority.has_area() or not priority.has_point(chunk):
				chunks.append(chunk)
	return chunks


func _affected_preview_chunks(indices: PackedInt32Array) -> Array[Vector2i]:
	var found := {}
	var size := _resource.grid_size()
	var layer_size := size.x * size.z
	var count_x := ceili(float(size.x) / PREVIEW_CHUNK_SIZE)
	var count_z := ceili(float(size.z) / PREVIEW_CHUNK_SIZE)
	for index in indices:
		var flat := int(index) % layer_size
		var x := flat % size.x
		var z := floori(float(flat) / float(size.x))
		var center := Vector2i(
			floori(float(x) / PREVIEW_CHUNK_SIZE),
			floori(float(z) / PREVIEW_CHUNK_SIZE),
		)
		var offsets: Array[Vector2i] = [Vector2i.ZERO]
		if x % PREVIEW_CHUNK_SIZE == 0:
			offsets.append(Vector2i.LEFT)
		if x % PREVIEW_CHUNK_SIZE == PREVIEW_CHUNK_SIZE - 1:
			offsets.append(Vector2i.RIGHT)
		if z % PREVIEW_CHUNK_SIZE == 0:
			offsets.append(Vector2i.UP)
		if z % PREVIEW_CHUNK_SIZE == PREVIEW_CHUNK_SIZE - 1:
			offsets.append(Vector2i.DOWN)
		for offset in offsets:
			var chunk := center + offset
			if chunk.x >= 0 and chunk.y >= 0 and chunk.x < count_x and chunk.y < count_z:
				found[chunk] = true
	var chunks: Array[Vector2i] = []
	for chunk in found:
		chunks.append(chunk)
	return chunks


func _rebuild_grid() -> void:
	if _resource == null:
		return
	var immediate := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.68, 0.20, 0.76)
	immediate.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var density := _resource.normalized_density()
	var size := _resource.grid_size()
	for block_x in range(0, _resource.size_blocks.x + 1):
		var vx := mini(block_x * density, size.x - 1)
		for z in size.z:
			var y := _top_height(vx, z) + 0.012
			immediate.surface_add_vertex(Vector3(float(block_x), y, float(z) / density))
			immediate.surface_add_vertex(Vector3(float(block_x), y, float(z + 1) / density))
	for block_z in range(0, _resource.size_blocks.z + 1):
		var vz := mini(block_z * density, size.z - 1)
		for x in size.x:
			var y := _top_height(x, vz) + 0.012
			immediate.surface_add_vertex(Vector3(float(x) / density, y, float(block_z)))
			immediate.surface_add_vertex(Vector3(float(x + 1) / density, y, float(block_z)))
	immediate.surface_end()
	_grid.mesh = immediate
	_grid.visible = _show_grid


func _rebuild_region_overlay() -> void:
	if is_instance_valid(_selection_panel):
		_selection_panel.sync(_resource, _edit_region_blocks, _slice_height, _surface_root)
	if _region_overlay == null or _resource == null:
		return
	var region := (
		_region_preview_blocks
		if _region_preview_blocks.size.x > 0 and _region_preview_blocks.size.y > 0
		else _edit_region_blocks
	)
	if region.size.x <= 0 or region.size.y <= 0:
		_region_overlay.visible = false
		_region_overlay.mesh = null
		return
	var density := _resource.normalized_density()
	var size := _resource.grid_size()
	var x0 := clampi(region.position.x * density, 0, size.x - 1)
	var z0 := clampi(region.position.y * density, 0, size.z - 1)
	var x1 := clampi((region.position.x + region.size.x) * density, 1, size.x)
	var z1 := clampi((region.position.y + region.size.y) * density, 1, size.z)
	var immediate := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.20, 0.90, 1.0, 0.96)
	immediate.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var lift := 0.026
	for x in range(x0, x1):
		var next_x := mini(x + 1, size.x - 1)
		var top_y0 := _top_height(x, z0) + lift
		var top_y1 := _top_height(next_x, z0) + lift
		immediate.surface_add_vertex(Vector3(float(x) / density, top_y0, float(z0) / density))
		immediate.surface_add_vertex(Vector3(float(x + 1) / density, top_y1, float(z0) / density))
		var bottom_sample_z := z1 - 1
		var bottom_y0 := _top_height(x, bottom_sample_z) + lift
		var bottom_y1 := _top_height(next_x, bottom_sample_z) + lift
		immediate.surface_add_vertex(Vector3(float(x) / density, bottom_y0, float(z1) / density))
		immediate.surface_add_vertex(Vector3(float(x + 1) / density, bottom_y1, float(z1) / density))
	for z in range(z0, z1):
		var next_z := mini(z + 1, size.z - 1)
		var left_y0 := _top_height(x0, z) + lift
		var left_y1 := _top_height(x0, next_z) + lift
		immediate.surface_add_vertex(Vector3(float(x0) / density, left_y0, float(z) / density))
		immediate.surface_add_vertex(Vector3(float(x0) / density, left_y1, float(z + 1) / density))
		var right_sample_x := x1 - 1
		var right_y0 := _top_height(right_sample_x, z) + lift
		var right_y1 := _top_height(right_sample_x, next_z) + lift
		immediate.surface_add_vertex(Vector3(float(x1) / density, right_y0, float(z) / density))
		immediate.surface_add_vertex(Vector3(float(x1) / density, right_y1, float(z + 1) / density))
	immediate.surface_end()
	_region_overlay.mesh = immediate
	_region_overlay.visible = _show_region or _region_preview_blocks.has_area()


func _top_height(x: int, z: int) -> float:
	var size := EditBounds.visible_size(_resource.grid_size(), _slice_height)
	var column_index := x + z * size.x
	if (
		_slice_height < 0
		and column_index >= 0
		and column_index < _surface_heightfield.size()
	):
		var top := int(_surface_heightfield[column_index])
		if _slice_height >= 0:
			top = mini(top, _slice_height - 1)
		return float(top + 1) / _resource.normalized_density() if top >= 0 else 0.0
	for y in range(size.y - 1, -1, -1):
		if _resource.voxels[Model.index_of(Vector3i(x, y, z), size)] != 0:
			return float(y + 1) / _resource.normalized_density()
	return 0.0


func _on_viewport_input(event: InputEvent) -> void:
	# Navigation owns RMB/MMB/wheel before a stamp or selection can consume hover
	# motion. Tool drafts stay armed while the author changes the view.
	if _handle_camera_input(event):
		accept_event()
		return
	if _generator_active():
		# Camera remains live, but recipe preview is never a sculpt target.
		accept_event()
		return
	if is_instance_valid(_selection_interaction) and _selection_interaction.handle(event):
		accept_event()
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_V and not key.is_command_or_control_pressed():
			_toggle_voxel_selection()
			accept_event()
			return
		if key.pressed and not key.echo and key.keycode == KEY_I and not key.is_command_or_control_pressed():
			_toggle_color_pick()
			accept_event()
			return
		if key.pressed and not key.echo and key.keycode == KEY_HOME:
			_fit_camera_to_surface()
			accept_event()
		elif key.pressed and not key.echo and key.keycode == KEY_G and not key.is_command_or_control_pressed():
			_on_view_action(ViewAction.GRID_OVERLAY)
			accept_event()
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed:
			_viewport_container.grab_focus()
		if button.button_index == MOUSE_BUTTON_LEFT and _picking_color:
			if button.pressed:
				_pick_palette_color(button.position)
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_LEFT and _selection_panel.active:
			if button.pressed:
				var pick := _pick_at(button.position)
				if pick.has("hit"):
					_selection_panel.choose(
						pick["hit"], button.shift_pressed, button.ctrl_pressed,
						Model.axis_normal(pick.get("normal", Vector3i.UP) as Vector3i),
					)
			accept_event()
			return
		if (
			button.button_index == MOUSE_BUTTON_LEFT
			and is_instance_valid(_region_select_button)
			and _region_select_button.button_pressed
		):
			if button.pressed:
				_handle_region_click(button.position)
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_LEFT and _canvas_mode != CanvasMode.BRUSH:
			# Library and helper modes are navigation-only until their own gesture
			# explicitly consumes LMB above. Never leak a click into the last brush.
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				match _application_kind():
					BrushProfiles.APPLICATION_POINT:
						_begin_stroke(button.position)
						_finish_stroke()
					BrushProfiles.APPLICATION_LINE:
						_handle_precision_line_click(button.position)
					_:
						_begin_stroke(button.position)
			elif _application_kind() == BrushProfiles.APPLICATION_STROKE:
				_pending_stroke_position = button.position
				_has_pending_stroke_position = true
				_flush_pending_stroke_position(true)
				_finish_stroke()
			accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _stroke_active and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			# Mouse devices can emit many events between editor frames. Keep only
			# the newest endpoint; line_cells() fills the path from the last
			# processed point, preserving a continuous stroke without event bursts.
			_pending_stroke_position = motion.position
			_has_pending_stroke_position = true
		elif _canvas_mode == CanvasMode.BRUSH:
			_update_cursor(motion.position)
		elif is_instance_valid(_cursor):
			_cursor.hide()


func _handle_camera_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT:
			if button.pressed:
				_viewport_container.grab_focus()
			_orbiting = button.pressed
			return true
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			if button.pressed:
				_viewport_container.grab_focus()
			_panning = button.pressed
			return true
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera_at(button.position, 0.88)
			_refresh_stamp_hover(button.position)
			return true
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera_at(button.position, 1.12)
			_refresh_stamp_hover(button.position)
			return true
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _panning:
			_pan_camera(motion.relative)
			_refresh_stamp_hover(motion.position)
			return true
		if _orbiting:
			_yaw -= motion.relative.x * 0.008
			_pitch = clampf(
				_pitch - motion.relative.y * 0.008,
				deg_to_rad(-88.0),
				deg_to_rad(88.0),
			)
			_update_camera()
			_sync_camera_controls()
			_refresh_stamp_hover(motion.position)
			return true
	return false


func _refresh_stamp_hover(position: Vector2) -> void:
	if (
		_canvas_mode != CanvasMode.STAMP_DRAFT
		or not is_instance_valid(_selection_interaction)
	):
		return
	var hover := InputEventMouseMotion.new()
	hover.position = position
	_selection_interaction.handle(hover)


func _pick_at(position: Vector2, stroke_baseline := false) -> Dictionary:
	if _resource == null or _camera == null or _viewport == null:
		return {}
	var scale := Vector2(_viewport.size) / _viewport_container.size.max(Vector2.ONE)
	var viewport_position := position * scale
	var pick_resource := _isolation_resource if _isolation_resource != null else _resource
	var pick_values := PackedByteArray()
	if (
		stroke_baseline
		and _isolation_resource == null
		and _stroke_before.size() == _resource.voxels.size()
	):
		pick_values = _stroke_before
	return Model.pick(
		pick_resource,
		_camera.project_ray_origin(viewport_position),
		_camera.project_ray_normal(viewport_position),
		_slice_height,
		_object_session != null and _selected_tool_id() == Model.TOOL_ADD,
		pick_values,
	)


func _target_cell(pick: Dictionary) -> Vector3i:
	var tool_id := _selected_tool_id()
	var cell: Vector3i = (
		pick.get("adjacent", Model.INVALID_CELL)
		if tool_id == Model.TOOL_ADD
		else pick.get("hit", Model.INVALID_CELL)
	)
	return cell if _cell_in_edit_region(cell) else Model.INVALID_CELL


func _surface_axis_for_pick(pick: Dictionary, previous := Vector3i.ZERO) -> Vector3i:
	var picked_normal := Model.axis_normal(
		pick.get("normal", Vector3i.UP) as Vector3i
	)
	var hit: Vector3i = pick.get("hit", Model.INVALID_CELL)
	if hit == Model.INVALID_CELL:
		return picked_normal
	var sample_resource := _isolation_resource if _isolation_resource != null else _resource
	if sample_resource == null:
		return picked_normal
	var values: PackedByteArray = sample_resource.voxels
	if (
		_stroke_active
		and _isolation_resource == null
		and _stroke_before.size() == _resource.voxels.size()
	):
		values = _stroke_before
	var radius := int(_radius.get_item_metadata(_radius.selected)) if _radius.selected >= 0 else 1
	var reference_normal := Model.axis_normal(previous)
	var view_normal: Vector3 = pick.get("view_normal", Vector3.ZERO)
	var cache_key := [
		sample_resource.get_instance_id(), hit, picked_normal, reference_normal,
		view_normal, radius, _stroke_active,
	]
	var area_normal := _surface_normal_cache_value
	if cache_key != _surface_normal_cache_key:
		area_normal = Model.averaged_surface_normal(
			values,
			sample_resource.grid_size(),
			hit,
			picked_normal,
			Model.surface_normal_radius(radius),
			reference_normal,
			view_normal,
		)
		_surface_normal_cache_key = cache_key
		_surface_normal_cache_value = area_normal
	return Model.stable_surface_axis(area_normal, picked_normal, previous)


func _oriented_brush_normal(pick: Dictionary, previous := Vector3i.ZERO) -> Vector3i:
	# A live mask describes a signed face, not only a set of allowed cells. Use
	# that face as the operation direction so a ray landing on the neighbouring
	# top face of a thin edge still extends the selected side as advertised.
	if is_instance_valid(_selection_panel) and _selection_panel.mask_brushes_enabled():
		var mask_direction := Model.axis_normal(_selection_panel.mask_normal())
		if mask_direction != Vector3i.ZERO:
			return mask_direction
	return _surface_axis_for_pick(pick, previous)


func _oriented_stroke_spacing() -> int:
	var radius := int(_radius.get_item_metadata(_radius.selected)) if _radius.selected >= 0 else 1
	return maxi(1, roundi(float(radius) * 0.5))


func _on_region_select_toggled(active: bool) -> void:
	if active:
		_region_anchor_block = Vector2i(-1, -1)
		_region_preview_blocks = Rect2i()
		_rebuild_region_overlay()
		_switch_canvas_mode(CanvasMode.REGION_SELECT)
	elif _canvas_mode == CanvasMode.REGION_SELECT:
		_return_to_last_brush()
		_set_status("Рабочая область не изменена")


func _handle_region_click(position: Vector2) -> void:
	var pick := _pick_at(position)
	var cell: Vector3i = pick.get("hit", Model.INVALID_CELL)
	if cell == Model.INVALID_CELL or not Model.contains(cell, _resource.grid_size()):
		_set_status("Выделение: кликните по поверхности карты", true)
		return
	var density := _resource.normalized_density()
	var block := Vector2i(
		floori(float(cell.x) / float(density)),
		floori(float(cell.z) / float(density)),
	)
	if _region_anchor_block == Vector2i(-1, -1):
		_region_anchor_block = block
		_region_preview_blocks = Rect2i(block, Vector2i.ONE)
		_rebuild_region_overlay()
		_update_region_label(_region_preview_blocks, true)
		_set_status("Первый угол выбран · кликните противоположный угол · Esc отменяет")
		return
	var minimum := Vector2i(
		mini(_region_anchor_block.x, block.x),
		mini(_region_anchor_block.y, block.y),
	)
	var maximum := Vector2i(
		maxi(_region_anchor_block.x, block.x),
		maxi(_region_anchor_block.y, block.y),
	)
	_edit_region_blocks = Rect2i(minimum, maximum - minimum + Vector2i.ONE)
	_region_anchor_block = Vector2i(-1, -1)
	_region_preview_blocks = Rect2i()
	_region_select_button.set_pressed_no_signal(false)
	_rebuild_region_overlay()
	_update_region_label(_edit_region_blocks)
	_return_to_last_brush()
	_set_status(
		"Участок %d×%d выбран · все кисти ограничены голубой рамкой"
		% [_edit_region_blocks.size.x, _edit_region_blocks.size.y],
		false,
		Color(0.20, 0.90, 1.0),
	)


func _cancel_region_selection() -> void:
	_region_anchor_block = Vector2i(-1, -1)
	_region_preview_blocks = Rect2i()
	if is_instance_valid(_region_select_button):
		_region_select_button.set_pressed_no_signal(false)
	_rebuild_region_overlay()
	_update_region_label(_edit_region_blocks)
	_set_status("Выделение отменено · прежняя рабочая область сохранена")


func _use_whole_region() -> void:
	_cancel_stroke()
	_cancel_ramp_anchor(false)
	_cancel_precision_line(false)
	_region_anchor_block = Vector2i(-1, -1)
	_region_preview_blocks = Rect2i()
	_edit_region_blocks = Rect2i()
	if is_instance_valid(_region_select_button):
		_region_select_button.set_pressed_no_signal(false)
	_rebuild_region_overlay()
	_update_region_label(_edit_region_blocks)
	_set_status("Рабочая область: вся непрерывная поверхность")


func _cell_in_edit_region(cell: Vector3i) -> bool:
	if cell == Model.INVALID_CELL or _resource == null:
		return false
	if cell.y < 0 or cell.y >= EditBounds.visible_size(_resource.grid_size(), _slice_height).y:
		return false
	if _edit_region_blocks.size.x <= 0 or _edit_region_blocks.size.y <= 0:
		return true
	var density := _resource.normalized_density()
	return _edit_region_blocks.has_point(Vector2i(
		floori(float(cell.x) / float(density)),
		floori(float(cell.z) / float(density)),
	))


func _update_region_label(region: Rect2i, selecting := false) -> void:
	if not is_instance_valid(_region_label):
		return
	if region.size.x <= 0 or region.size.y <= 0:
		_region_label.text = "Область: вся"
		_region_label.tooltip_text = "Кисти могут менять всю поверхность."
		return
	var last := region.position + region.size - Vector2i.ONE
	_region_label.text = "%s: X%d–%d · Z%d–%d" % [
		"Угол A" if selecting else "Область",
		region.position.x + 1,
		last.x + 1,
		region.position.y + 1,
		last.y + 1,
	]
	_region_label.tooltip_text = _region_label.text


func _on_tool_selected(index: int) -> void:
	_store_active_tool_profile()
	_last_brush_item = clampi(index, 0, maxi(0, _tool.item_count - 1))
	_switch_canvas_mode(CanvasMode.BRUSH)
	var tool_id := _selected_tool_id()
	var base_tool := _selected_base_tool_id()
	_restore_tool_profile(base_tool)
	tool_id = _selected_tool_id()
	_selection_panel.set_tool_support(BrushProfiles.mask_kind(tool_id))
	var oriented_brush := _is_oriented_brush_tool(tool_id)
	_volume_operation.visible = base_tool == Model.TOOL_ADD
	var relief := _is_relief_tool(tool_id)
	_relief_mode.visible = base_tool == Model.TOOL_RAISE
	_height_limit.visible = relief
	_update_relief_controls()
	var smooth := _is_smooth_tool(tool_id)
	_smooth_strength.visible = smooth
	_smooth_mode.visible = smooth
	_smooth_fill_pits.visible = (
		smooth and _smooth_mode.selected >= 0
		and str(_smooth_mode.get_selected_metadata()) == BrushProfiles.SMOOTH_COMMON
	)
	var material_tool := _is_material_tool(tool_id)
	var surface_fill_tool := _is_surface_fill_tool(tool_id)
	_depth.visible = oriented_brush and not (
		material_tool and _material_scope.selected >= 0
		and str(_material_scope.get_item_metadata(_material_scope.selected)) == "connected"
	)
	_application_mode.visible = _depth.visible
	_brush_shape.visible = _depth.visible
	_follow_surface.visible = (
		_depth.visible and _application_kind() == BrushProfiles.APPLICATION_STROKE
	)
	_palette.visible = not material_tool and not surface_fill_tool
	_palette.disabled = tool_id == Model.TOOL_LOWER
	_material_preset.visible = material_tool
	_material_scope.visible = material_tool
	_surface_fill_material.visible = surface_fill_tool
	_update_surface_fill_controls()
	_update_material_scope_controls()
	_update_smooth_controls()
	_update_tool_help(tool_id)
	if _slice_height >= 0:
		_info.text += "\n\nСрез защищает верх. " + (
			"Материал наносится локально; водный эффект виден после отключения среза."
			if material_tool else "Кисть меняет только видимые нижние слои."
		)
	if is_instance_valid(_viewport_container):
		_update_cursor(_viewport_container.get_local_mouse_position())


func _selected_tool_id() -> int:
	if _stroke_active:
		return _stroke_tool_id
	return _resolved_base_tool(_selected_base_tool_id())


func _selected_base_tool_id() -> int:
	if not is_instance_valid(_tool):
		return Model.TOOL_ADD
	var selected := _tool.get_selected_items()
	var item := selected[0] if not selected.is_empty() else _last_brush_item
	return int(_tool.get_item_metadata(clampi(item, 0, maxi(0, _tool.item_count - 1))))


func _resolved_base_tool(base_tool: int) -> int:
	var volume_operation := (
		int(_volume_operation.get_selected_metadata())
		if is_instance_valid(_volume_operation) and _volume_operation.selected >= 0
		else Model.TOOL_ADD
	)
	var relief_direction := (
		int(_relief_direction.get_selected_metadata())
		if is_instance_valid(_relief_direction) and _relief_direction.selected >= 0
		else 1
	)
	var relief_geometry := (
		str(_relief_geometry.get_selected_metadata())
		if is_instance_valid(_relief_geometry) and _relief_geometry.selected >= 0
		else "solid"
	)
	if base_tool == Model.TOOL_RAISE and _relief_mode_kind() == BrushProfiles.RELIEF_GENERATOR:
		relief_direction = 1
		relief_geometry = "solid"
	return BrushProfiles.resolved_tool(
		base_tool, volume_operation, relief_direction, relief_geometry
	)


func _find_tool_item(base_tool: int) -> int:
	for item in _tool.item_count:
		if int(_tool.get_item_metadata(item)) == base_tool:
			return item
	return -1


func _on_brush_profile_changed(_index: int) -> void:
	_flush_pending_stroke_position()
	_finish_stroke()
	_cancel_ramp_anchor(false)
	_on_tool_selected(0)


func _load_tool_profiles() -> void:
	var saved := {}
	if _view_store != null and _view_store.has_method("recall_brush_profiles"):
		saved = _view_store.call("recall_brush_profiles") as Dictionary
	_tool_profiles = BrushProfiles.normalize_profiles(saved)


func _store_active_tool_profile() -> void:
	if (
		_restoring_tool_profile
		or _active_profile_tool < 0
		or not is_instance_valid(_radius)
		or not is_instance_valid(_depth)
		or not is_instance_valid(_coarse)
		or not is_instance_valid(_follow_surface)
		or not is_instance_valid(_application_mode)
		or not is_instance_valid(_brush_shape)
		or not is_instance_valid(_smooth_mode)
		or not is_instance_valid(_smooth_fill_pits)
		or not is_instance_valid(_relief_mode)
		or not is_instance_valid(_relief_generator_style)
		or not is_instance_valid(_relief_generator_direction)
		or not is_instance_valid(_relief_generator_scale)
		or not is_instance_valid(_relief_generator_detail)
	):
		return
	var radius := int(_radius.get_item_metadata(_radius.selected)) if _radius.selected >= 0 else 4
	_tool_profiles[_active_profile_tool] = BrushProfiles.normalize_profile({
		"radius": radius,
		"depth": int(_depth.value),
		"coarse": _coarse.button_pressed,
		"follow_surface": _follow_surface.button_pressed,
		"direction_behavior_version": BrushProfiles.DIRECTION_BEHAVIOR_VERSION,
		"application": _application_mode.get_selected_metadata(),
		"shape": _brush_shape.get_selected_metadata(),
		"smooth_mode": _smooth_mode.get_selected_metadata(),
		"smooth_fill_pits": _smooth_fill_pits.button_pressed,
		"relief_mode": _relief_mode.get_selected_metadata(),
		"relief_direction": _relief_direction.get_selected_metadata(),
		"relief_geometry": _relief_geometry.get_selected_metadata(),
		"relief_style": _relief_generator_style.get_selected_metadata(),
		"relief_generator_direction": _relief_generator_direction.get_selected_metadata(),
		"relief_scale": _relief_generator_scale.get_selected_metadata(),
		"relief_detail": _relief_generator_detail.get_selected_metadata(),
		"relief_seed": _relief_seed_value,
	})


func _restore_tool_profile(base_tool: int) -> void:
	if not is_instance_valid(_radius) or not is_instance_valid(_depth):
		return
	_restoring_tool_profile = true
	var profile := BrushProfiles.normalize_profile(
		_tool_profiles.get(base_tool, {}) as Dictionary
	)
	_select_option_metadata(_radius, int(profile.radius))
	_depth.set_value_no_signal(float(profile.depth))
	_coarse.set_pressed_no_signal(bool(profile.coarse))
	_follow_surface.set_pressed_no_signal(bool(profile.follow_surface))
	_select_option_metadata(_application_mode, str(profile.application))
	_select_option_metadata(_brush_shape, str(profile.shape))
	_select_option_metadata(_smooth_mode, str(profile.smooth_mode))
	_smooth_fill_pits.set_pressed_no_signal(bool(profile.smooth_fill_pits))
	_select_option_metadata(_relief_mode, str(profile.relief_mode))
	_select_option_metadata(_relief_direction, int(profile.relief_direction))
	_select_option_metadata(_relief_geometry, str(profile.relief_geometry))
	_select_option_metadata(_relief_generator_style, str(profile.relief_style))
	_select_option_metadata(
		_relief_generator_direction, int(profile.relief_generator_direction)
	)
	_select_option_metadata(_relief_generator_scale, int(profile.relief_scale))
	_select_option_metadata(_relief_generator_detail, int(profile.relief_detail))
	_relief_seed_value = int(profile.relief_seed)
	_active_profile_tool = base_tool
	_sync_coarse_depth()
	_sync_direction_label()
	_restoring_tool_profile = false


func _on_brush_setting_changed() -> void:
	if _restoring_tool_profile:
		return
	_flush_pending_stroke_position()
	_finish_stroke()
	_cancel_precision_line(false)
	_sync_coarse_depth()
	_sync_direction_label()
	_store_active_tool_profile()
	_update_material_scope_controls()
	_update_relief_controls()
	_update_smooth_controls()
	_update_tool_help(_selected_tool_id())
	if is_instance_valid(_viewport_container):
		_update_cursor(_viewport_container.get_local_mouse_position())


func _on_coarse_toggled(_active: bool) -> void:
	_on_brush_setting_changed()


func _relief_mode_kind() -> String:
	if not is_instance_valid(_relief_mode) or _relief_mode.selected < 0:
		return BrushProfiles.RELIEF_BUILDUP
	return str(_relief_mode.get_selected_metadata())


func _is_relief_generator() -> bool:
	return (
		_selected_base_tool_id() == Model.TOOL_RAISE
		and _relief_mode_kind() == BrushProfiles.RELIEF_GENERATOR
	)


func _update_relief_controls() -> void:
	if not is_instance_valid(_relief_mode):
		return
	var relief := _selected_base_tool_id() == Model.TOOL_RAISE
	var generator := relief and _relief_mode_kind() == BrushProfiles.RELIEF_GENERATOR
	_relief_direction.visible = relief and not generator
	_relief_geometry.visible = relief and not generator
	_buildup_rate.visible = relief and not generator
	_relief_generator_style.visible = generator
	_relief_generator_direction.visible = generator
	_relief_generator_scale.visible = generator
	_relief_generator_detail.visible = generator
	_relief_variant_button.visible = generator
	for item in _height_limit.item_count:
		var value := int(_height_limit.get_item_metadata(item))
		_height_limit.set_item_text(
			item, ("Высота %d vox" if generator else "Предел %d vox") % value
		)
	_relief_variant_button.tooltip_text = (
		"Текущий вариант: %d. Нажмите, чтобы получить другой устойчивый рисунок."
		% _relief_seed_value
	)


func _on_relief_variant_pressed() -> void:
	_flush_pending_stroke_position()
	_finish_stroke()
	_relief_seed_value = (_relief_seed_value + 1) % 2147483647
	_store_active_tool_profile()
	_update_relief_controls()
	_update_tool_help(_selected_tool_id())
	if is_instance_valid(_viewport_container):
		_update_cursor(_viewport_container.get_local_mouse_position())


func _update_smooth_controls() -> void:
	if not is_instance_valid(_smooth_mode) or not is_instance_valid(_smooth_fill_pits):
		return
	_smooth_fill_pits.visible = (
		_smooth_mode.visible and _smooth_mode.selected >= 0
		and str(_smooth_mode.get_selected_metadata()) == BrushProfiles.SMOOTH_COMMON
	)


func _sync_coarse_depth() -> void:
	if not is_instance_valid(_depth) or not is_instance_valid(_coarse):
		return
	if _coarse.button_pressed:
		_depth.min_value = 2
		_depth.step = 2
		var even_depth := ceili(_depth.value / 2.0) * 2
		_depth.set_value_no_signal(even_depth)
	else:
		_depth.min_value = 1
		_depth.step = 1


func _sync_direction_label() -> void:
	if not is_instance_valid(_follow_surface):
		return
	_follow_surface.text = (
		"Направление: по поверхности"
		if _follow_surface.button_pressed
		else "Направление: только одна грань"
	)


func _application_kind() -> String:
	if (
		not is_instance_valid(_application_mode)
		or not _application_mode.visible
		or _application_mode.selected < 0
	):
		return BrushProfiles.APPLICATION_STROKE
	return str(_application_mode.get_selected_metadata())


func _brush_footprint_shape() -> String:
	if not is_instance_valid(_brush_shape) or _brush_shape.selected < 0:
		return BrushProfiles.SHAPE_CIRCLE
	return str(_brush_shape.get_selected_metadata())


func _activate_tool_id(tool_id: int) -> bool:
	## Compatibility entry for tests and editor commands while the rail exposes
	## compact families instead of every concrete backend operation.
	var base_tool := BrushProfiles.base_tool(tool_id)
	var item := _find_tool_item(base_tool)
	if item < 0:
		return false
	if base_tool == Model.TOOL_ADD:
		_select_option_metadata(_volume_operation, tool_id)
	_tool.deselect_all()
	_tool.select(item)
	_on_tool_selected(item)
	if base_tool == Model.TOOL_RAISE:
		_select_option_metadata(_relief_mode, BrushProfiles.RELIEF_BUILDUP)
		_select_option_metadata(
			_relief_direction,
			-1 if tool_id in [Model.TOOL_LOWER, Model.TOOL_SHELL_LOWER] else 1,
		)
		_select_option_metadata(
			_relief_geometry,
			"shell" if tool_id in [Model.TOOL_SHELL_RAISE, Model.TOOL_SHELL_LOWER] else "solid",
		)
		_on_brush_setting_changed()
	return true


func _select_option_metadata(option: OptionButton, value: Variant) -> void:
	for item in option.item_count:
		if option.get_item_metadata(item) == value:
			option.select(item)
			return


func _update_tool_help(tool_id: int) -> void:
	if not is_instance_valid(_info):
		return
	if is_instance_valid(_selection_interaction) and _selection_interaction._stamp != null:
		var placement: int = _selection_interaction._stamp_application.selected
		if _selection_interaction._is_pattern():
			_active_tool_label.text = "Паттерн · " + ["один","путь","линия A→B"][placement]
			match placement:
				1:
					_info.text = "Ведите ЛКМ по поверхности: отпускание завершает черновик. Ctrl+Z правит его, Enter применяет весь путь одним Undo."
				2:
					_info.text = "Первый клик задаёт A и плоскость, второй — B. Проверьте черновик и нажмите Enter; автоповорота по пути нет."
				_:
					_info.text = "Наведите настоящий отпечаток, ЛКМ фиксирует черновик, Enter применяет. Глубина идёт наружу при добавлении и внутрь при вырезании."
			return
		_active_tool_label.text = "Штамп · " + ["один","путь","линия A→B","россыпь"][placement]
		match placement:
			1:
				_info.text = "Ведите ЛКМ по поверхности: отпускание завершает черновик. Ctrl+Z правит его, Enter применяет весь путь одним Undo."
			2:
				_info.text = "Первый клик задаёт A, второй — B. Проверьте черновик, при необходимости исправьте Ctrl+Z и нажмите Enter."
			3:
				_info.text = "Ведите ЛКМ по поверхности. После отпускания правьте черновик, выберите вариант и нажмите Enter для одного Undo."
			_:
				_info.text = "Наведите настоящий отпечаток · ЛКМ фиксирует черновик · Enter применяет · Esc отменяет."
		return
	var title := "Объём · добавить"
	var help := "Фиксированный слой перед видимой гранью. Повтор внутри жеста не наращивает глубину; Ctrl+Z отменяет весь мазок."
	if _is_relief_generator():
		var style := (
			"гребни"
			if str(_relief_generator_style.get_selected_metadata()) == BrushProfiles.RELIEF_RIDGES
			else "почва"
		)
		var direction := int(_relief_generator_direction.get_selected_metadata())
		var direction_text := "бугры и ямки"
		if direction > 0:
			direction_text = "только вверх"
		elif direction < 0:
			direction_text = "только вниз"
		var detail_text := "плотная фактура"
		if int(_relief_generator_detail.get_selected_metadata()) == 0:
			detail_text = "редкие мягкие перепады в 1–2 вокселя"
		_active_tool_label.text = "Рельеф · генератор · %s" % style
		_info.text = (
			"Ведите LMB: %s; рисунок закреплён в координатах модели (%s). "
			+ "Повтор внутри жеста не накапливается; новый вариант меняет рисунок."
		) % [detail_text, direction_text]
		return
	match tool_id:
		Model.TOOL_REMOVE:
			title = "Объём · убрать"
			help = "Снимает фиксированную глубину внутрь видимой грани. Esc отменяет текущий жест."
		Model.TOOL_PAINT:
			title = "Красить"
			help = "Меняет цвет на фиксированную глубину внутрь формы, не меняя её объём."
		Model.TOOL_MATERIAL:
			title = "Материал / вода"
			help = (
				"Добавляет отдельную прозрачную воду над voxel-дном. Связанная область "
				+ "берёт похожий цвет одной высоты; «Без воды» снимает overlay."
			)
		Model.TOOL_SURFACE_FILL:
			title = "Заливка уровня"
			help = (
				"Кликните по дну впадины: автоуровень найдёт ближайший край и положит "
				+ "отдельную плоскость, не меняя дно, рельеф или коллизию. "
				+ "Открытая область безопасно отклоняется."
			)
		Model.TOOL_RAISE:
			title = "Рельеф · наращивание вверх · сплошной"
			help = "Удерживайте LMB: холм растёт с выбранной скоростью до заданного предела."
		Model.TOOL_SHELL_RAISE:
			title = "Рельеф · наращивание вверх · оболочка"
			help = "Поднимает верх и открытые стенки, не заполняя скрытый объём под горой."
		Model.TOOL_LOWER:
			title = "Рельеф · наращивание вниз · сплошной"
			help = "Удерживайте LMB: поверхность опускается с выбранной скоростью до предела."
		Model.TOOL_SHELL_LOWER:
			title = "Рельеф · наращивание вниз · оболочка"
			help = "Опускает верх полой формы и перестраивает только видимые стенки впадины."
		Model.TOOL_LEVEL:
			title = "Выровнять площадку"
			help = "Берёт высоту первой точки и протягивает одну плоскость до отпускания LMB."
		Model.TOOL_SMOOTH:
			var common_level := (
				is_instance_valid(_smooth_mode) and _smooth_mode.selected >= 0
				and str(_smooth_mode.get_selected_metadata()) == BrushProfiles.SMOOTH_COMMON
			)
			if common_level:
				title = "Сгладить · общий уровень"
				help = (
					"Сводит выступы%s к устойчивой высоте вокруг кисти не больше выбранной силы за жест."
					% (" и ямки" if _smooth_fill_pits.button_pressed else "")
				)
			else:
				title = "Сгладить · ступени"
				help = "Приближает колонки к высоте соседей не больше выбранной силы за один жест."
		Model.TOOL_RAMP:
			title = "Склон A → B"
			help = "Первый клик ставит A, второй соединяет реальные высоты цельным проходом. Esc отменяет A."
	if _is_oriented_brush_tool(tool_id) and is_instance_valid(_application_mode) and _application_mode.visible:
		match _application_kind():
			BrushProfiles.APPLICATION_STROKE:
				help += (
					" Мазок следует поверхности; на углу начинается новый сегмент без перемычки."
					if _follow_surface.button_pressed
					else " Только одна грань: мазок честно останавливается на её краю."
				)
			BrushProfiles.APPLICATION_POINT:
				help += " Точка применяет ровно один отпечаток на клик."
			BrushProfiles.APPLICATION_LINE:
				help += " Линия: кликните A, наведите B, затем кликните или нажмите Enter; Esc отменяет preview."
	if is_instance_valid(_active_tool_label):
		_active_tool_label.text = title
	_info.text = help


func _is_relief_tool(tool_id: int) -> bool:
	return tool_id in [
		Model.TOOL_RAISE,
		Model.TOOL_LOWER,
		Model.TOOL_SHELL_RAISE,
		Model.TOOL_SHELL_LOWER,
	]


func _is_oriented_brush_tool(tool_id: int) -> bool:
	return tool_id in [
		Model.TOOL_ADD,
		Model.TOOL_REMOVE,
		Model.TOOL_PAINT,
		Model.TOOL_MATERIAL,
	]


func _is_shell_relief_tool(tool_id: int) -> bool:
	return tool_id in [Model.TOOL_SHELL_RAISE, Model.TOOL_SHELL_LOWER]


func _is_shell_lower_tool(tool_id: int) -> bool:
	return tool_id == Model.TOOL_SHELL_LOWER


func _is_level_tool(tool_id: int) -> bool:
	return tool_id == Model.TOOL_LEVEL


func _is_smooth_tool(tool_id: int) -> bool:
	return tool_id == Model.TOOL_SMOOTH


func _is_ramp_tool(tool_id: int) -> bool:
	return tool_id == Model.TOOL_RAMP


func _is_material_tool(tool_id: int) -> bool:
	return tool_id == Model.TOOL_MATERIAL


func _is_surface_fill_tool(tool_id: int) -> bool:
	return tool_id == Model.TOOL_SURFACE_FILL


func _on_material_scope_changed(_index: int) -> void:
	_update_material_scope_controls()
	if _selected_tool_id() == Model.TOOL_MATERIAL:
		_update_tool_help(Model.TOOL_MATERIAL)


func _on_surface_fill_options_changed(_index: int) -> void:
	_update_surface_fill_controls()


func _update_surface_fill_controls() -> void:
	if (
		not is_instance_valid(_surface_fill_material)
		or not is_instance_valid(_surface_fill_level)
		or not is_instance_valid(_surface_fill_inset)
	):
		return
	var fill_tool := _selected_tool_id() == Model.TOOL_SURFACE_FILL
	var deleting := (
		_surface_fill_material.selected >= 0
		and int(_surface_fill_material.get_item_metadata(
			_surface_fill_material.selected
		)) == Model.SURFACE_FILL_NONE
	)
	_surface_fill_level.visible = fill_tool and not deleting
	_surface_fill_tint.visible = fill_tool and not deleting
	var auto_level := (
		_surface_fill_level.selected >= 0
		and int(_surface_fill_level.get_item_metadata(_surface_fill_level.selected)) == 0
	)
	_surface_fill_inset.visible = fill_tool and not deleting and auto_level


func _update_material_scope_controls() -> void:
	if not is_instance_valid(_material_scope) or not is_instance_valid(_material_tolerance):
		return
	var tool_id := _selected_tool_id()
	var material_tool := tool_id == Model.TOOL_MATERIAL
	var connected := material_tool and _material_scope.selected >= 0 and str(
		_material_scope.get_item_metadata(_material_scope.selected)
	) == "connected"
	_material_tolerance.visible = connected
	var point_fill := tool_id == Model.TOOL_SURFACE_FILL
	_radius.visible = not connected and not point_fill
	_coarse.visible = not connected and not point_fill
	_depth.visible = _is_oriented_brush_tool(tool_id) and not connected
	_application_mode.visible = _depth.visible
	_brush_shape.visible = _depth.visible
	_follow_surface.visible = (
		_depth.visible and _application_kind() == BrushProfiles.APPLICATION_STROKE
	)


func _begin_stroke(position: Vector2) -> void:
	if _resource == null or _actions == null:
		return
	var tool_id := _selected_tool_id()
	if not _slice_allows_tool(tool_id):
		_set_status("Эта кисть работает со всей колонкой · выключите срез", true)
		return
	if _is_surface_fill_tool(tool_id):
		_apply_surface_fill_click(position)
		return
	if _is_ramp_tool(tool_id):
		_handle_ramp_click(position)
		return
	_prepare_stroke(tool_id)
	if not _extend_stroke(position):
		_clear_stroke_state()


func _apply_surface_fill_click(position: Vector2) -> void:
	var pick := _pick_at(position)
	var cell: Vector3i = pick.get("hit", Model.INVALID_CELL)
	if cell == Model.INVALID_CELL or not _cell_in_edit_region(cell):
		_set_status("Заливка: кликните по дну внутри рабочей области", true)
		return
	var size := _resource.grid_size()
	var column_count := size.x * size.z
	var levels := Model.normalized_int_channel(
		_resource.surface_fill_levels, column_count
	)
	var materials := Model.normalized_channel(
		_resource.surface_fill_materials, column_count
	)
	var palette_values := Model.normalized_channel(
		_resource.surface_fill_palette, column_count
	)
	var fill_material := int(
		_surface_fill_material.get_item_metadata(_surface_fill_material.selected)
		if _surface_fill_material.selected >= 0
		else Model.SURFACE_FILL_WATER
	)
	var selection: Dictionary
	if fill_material == Model.SURFACE_FILL_NONE:
		selection = {
			"columns": PackedInt32Array(),
			"level": 0,
			"spill_level": 0,
			"truncated": false,
			"open": false,
		}
	else:
		var manual_raise := int(
			_surface_fill_level.get_item_metadata(_surface_fill_level.selected)
			if _surface_fill_level.selected >= 0
			else 0
		)
		var edge_inset := int(
			_surface_fill_inset.get_item_metadata(_surface_fill_inset.selected)
			if _surface_fill_inset.selected >= 0
			else 1
		)
		selection = Model.surface_fill_selection(
			_resource,
			cell,
			manual_raise,
			_edit_region_blocks,
			_surface_heightfield,
			Model.MAX_SURFACE_FILL_COLUMNS,
			edge_inset,
		)
	if bool(selection.get("truncated", false)):
		_set_status(
			"Заливка слишком велика · выделите меньшую рабочую область вокруг водоёма",
			true,
		)
		return
	if bool(selection.get("open", false)):
		_set_status(
			"Заливка не выполнена: впадина открыта или выходит за область поиска",
			true,
		)
		return
	var next_columns := selection.get("columns", PackedInt32Array()) as PackedInt32Array
	var replacement := Model.surface_fill_replacement_columns(
		_resource,
		Vector2i(cell.x, cell.z),
		next_columns,
		fill_material,
		_edit_region_blocks,
	)
	if bool(replacement.get("truncated", false)):
		_set_status(
			"Старая и новая заливки вместе слишком велики · уменьшите водоём",
			true,
		)
		return
	if bool(replacement.get("escaped_scope", false)):
		_set_status(
			"Рабочая область режет существующую воду · расширьте область или выберите всю карту",
			true,
		)
		return
	var affected_columns := replacement.get(
		"columns", PackedInt32Array()
	) as PackedInt32Array
	if affected_columns.is_empty():
		_set_status(
			"На этой точке нет заливки" if fill_material == Model.SURFACE_FILL_NONE
			else "Автоуровень не нашёл замкнутую впадину",
			true,
		)
		return
	var level := int(selection.get("level", 0))
	var spill_level := int(selection.get("spill_level", level))
	var palette_index := (
		int(_surface_fill_tint.get_selected_metadata())
		if _surface_fill_tint.selected >= 0 else 0
	)
	# Clear the complete previous family before writing the new mask. Columns
	# excluded by a lower level must not survive as high water shelves.
	for raw_column in affected_columns:
		var column := int(raw_column)
		levels[column] = 0
		materials[column] = 0
		palette_values[column] = 0
	if fill_material != Model.SURFACE_FILL_NONE:
		for raw_column in next_columns:
			var column := int(raw_column)
			levels[column] = level
			materials[column] = fill_material
			palette_values[column] = palette_index
	else:
		var has_remaining_fill := false
		for value in materials:
			if int(value) != Model.SURFACE_FILL_NONE:
				has_remaining_fill = true
				break
		if not has_remaining_fill:
			levels = PackedInt32Array()
			materials = PackedByteArray()
			palette_values = PackedByteArray()
	if not _actions.apply_surface_fill(
		_resource, levels, materials, palette_values, affected_columns
	):
		_set_status("Заливка уже имеет выбранные параметры", true)
		return
	_set_status(
		("Слой удалён: %d колонок · Ctrl+Z отменяет" % affected_columns.size())
		if fill_material == Model.SURFACE_FILL_NONE
		else (
			"Вода: %d колонок · уровень %d vox%s · дно и рельеф не изменены · Ctrl+Z отменяет"
			% [
				next_columns.size(),
				level,
				(" · край %d" % spill_level) if spill_level != level else "",
			]
		),
		false,
		Color(0.20, 0.90, 1.0),
	)


func _prepare_stroke(tool_id: int) -> void:
	_stroke_tool_id = tool_id
	_stroke_active = true
	_stroke_before = _resource.voxels.duplicate()
	# Packed arrays are reference types in GDScript. Keep one live buffer for the
	# whole gesture instead of copying the 128x24x128 canvas at every buildup level.
	_stroke_live_values = _resource.voxels
	_stroke_changes.clear()
	_stroke_before_transparency = _resource.transparency.duplicate()
	_stroke_live_transparency = Model.normalized_channel(
		_resource.transparency, _resource.voxels.size()
	)
	_stroke_material_changes.clear()
	_stroke_smart_fill_applied = false
	_stroke_rejected = false
	_stroke_top_cache.clear()
	_stroke_relief_amount_cache.clear()
	_stroke_relief_center_height_cache.clear()
	_stroke_shell_foundation_cache.clear()
	_stroke_smooth_column_cache.clear()
	_stroke_generator_column_cache.clear()
	_stroke_heightfield = PackedInt32Array()
	_stroke_normal = Vector3i.ZERO
	_last_stroke_normal = Vector3i.ZERO
	_stroke_face_plane = -999999
	_single_face_stopped = false
	_stroke_input_cell = Model.INVALID_CELL
	_stroke_distance_to_next = 1.0
	_stroke_smoothed_position = Vector2.ZERO
	_has_stroke_smoothed_position = false
	_surface_normal_cache_key.clear()
	_surface_normal_cache_value = Vector3.ZERO
	if _is_smooth_tool(tool_id) or _is_relief_generator():
		if _surface_heightfield.size() != _resource.grid_size().x * _resource.grid_size().z:
			_surface_heightfield = Model.column_heights(
				_stroke_before, _resource.grid_size(), _resource.palette.size() - 1
			)
		_stroke_heightfield = _surface_heightfield.duplicate()
	_stroke_level_target_y = -1
	_last_stroke_cell = Model.INVALID_CELL
	_has_pending_stroke_position = false


func _handle_ramp_click(position: Vector2) -> void:
	var pick := _pick_at(position)
	if pick.is_empty():
		_set_status("Склон: выберите поверхность внутри холста", true)
		return
	var cell: Vector3i = pick.get("hit", Model.INVALID_CELL)
	if cell == Model.INVALID_CELL or not Model.contains(cell, _resource.grid_size()):
		_set_status("Склон: точка должна лежать на видимой поверхности", true)
		return
	if not _cell_in_edit_region(cell):
		_set_status("Склон: обе точки должны быть внутри голубой рабочей области", true)
		return
	if _ramp_anchor_cell == Model.INVALID_CELL:
		_ramp_anchor_cell = cell
		_show_ramp_anchor(cell)
		_set_status(
			"Склон: точка A выбрана · кликните точку B · Esc отменяет",
			false,
			Color(0.20, 0.90, 1.0),
		)
		return
	var from := _ramp_anchor_cell
	_cancel_ramp_anchor(false)
	_prepare_stroke(Model.TOOL_RAMP)
	var radius := int(_radius.get_item_metadata(_radius.selected))
	var palette_index := int(_palette.get_item_metadata(_palette.selected)) if _palette.selected >= 0 else 1
	var changes := Model.ramp_segment_changes(
		_resource,
		_stroke_before,
		from,
		cell,
		palette_index,
		radius,
		_coarse.button_pressed,
		_surface_heightfield,
	)
	var dirty := {}
	_merge_live_changes(changes, dirty)
	_finish_live_changes(dirty, Model.TOOL_RAMP, -1)
	_finish_stroke()


func _show_ramp_anchor(cell: Vector3i) -> void:
	if _ramp_anchor_marker == null or _resource == null:
		return
	var density := float(_resource.normalized_density())
	_ramp_anchor_marker.position = Vector3(
		(float(cell.x) + 0.5) / density,
		(float(cell.y) + 1.6) / density,
		(float(cell.z) + 0.5) / density,
	)
	_ramp_anchor_marker.visible = true


func _cancel_ramp_anchor(show_message := true) -> void:
	if _ramp_anchor_cell == Model.INVALID_CELL:
		return
	_ramp_anchor_cell = Model.INVALID_CELL
	if _ramp_anchor_marker != null:
		_ramp_anchor_marker.visible = false
	if show_message:
		_set_status("Точка A склона отменена")


func _handle_precision_line_click(position: Vector2) -> void:
	if _resource == null or not _is_oriented_brush_tool(_selected_tool_id()):
		return
	if _precision_line_anchor_cell == Model.INVALID_CELL:
		var pick := _pick_at(position)
		if pick.is_empty():
			_set_status("Линия: выберите первую грань внутри Canvas", true)
			return
		var cell := _target_cell(pick)
		var normal := Model.axis_normal(pick.get("normal", Vector3i.ZERO) as Vector3i)
		if cell == Model.INVALID_CELL or normal == Vector3i.ZERO:
			_set_status("Линия: точка A должна лежать на доступной грани", true)
			return
		_begin_precision_line(cell, normal)
		return
	var target := _precision_line_target_at(position)
	if target == Model.INVALID_CELL:
		_set_status("Линия: точка B вне выбранной плоскости Canvas", true)
		return
	_set_precision_line_target(target)
	_commit_precision_line()


func _begin_precision_line(cell: Vector3i, normal: Vector3i) -> bool:
	if (
		_resource == null
		or not Model.contains(cell, _resource.grid_size())
		or not _cell_in_edit_region(cell)
	):
		return false
	_precision_line_anchor_cell = cell
	_precision_line_normal = Model.axis_normal(normal)
	if _precision_line_normal == Vector3i.ZERO:
		_cancel_precision_line(false)
		return false
	_set_precision_line_target(cell)
	return true


func _precision_line_target_at(position: Vector2) -> Vector3i:
	if (
		_precision_line_anchor_cell == Model.INVALID_CELL
		or _resource == null
		or _camera == null
		or _viewport == null
	):
		return Model.INVALID_CELL
	var scale := Vector2(_viewport.size) / _viewport_container.size.max(Vector2.ONE)
	var viewport_position := position * scale
	var origin := _camera.project_ray_origin(viewport_position)
	var direction := _camera.project_ray_normal(viewport_position)
	var axis := Model.axis_index(_precision_line_normal)
	var hit_cell := (
		_precision_line_anchor_cell - _precision_line_normal
		if _selected_tool_id() == Model.TOOL_ADD
		else _precision_line_anchor_cell
	)
	var boundary := float(hit_cell[axis])
	if _precision_line_normal[axis] > 0:
		boundary += 1.0
	var plane_position := Vector3.ZERO
	plane_position[axis] = boundary / float(_resource.normalized_density())
	var intersection: Variant = Plane(Vector3(_precision_line_normal), plane_position).intersects_ray(
		origin, direction
	)
	if intersection == null:
		return Model.INVALID_CELL
	var point := intersection as Vector3
	var density := float(_resource.normalized_density())
	var target := Vector3i(
		floori(point.x * density),
		floori(point.y * density),
		floori(point.z * density),
	)
	target[axis] = _precision_line_anchor_cell[axis]
	return target if Model.contains(target, _resource.grid_size()) and _cell_in_edit_region(target) else Model.INVALID_CELL


func _set_precision_line_target(target: Vector3i) -> bool:
	if (
		_precision_line_anchor_cell == Model.INVALID_CELL
		or _resource == null
		or not Model.contains(target, _resource.grid_size())
		or not _cell_in_edit_region(target)
	):
		return false
	var axis := Model.axis_index(_precision_line_normal)
	target[axis] = _precision_line_anchor_cell[axis]
	if target == _precision_line_target_cell:
		return true
	_precision_line_target_cell = target
	var centers := Model.line_cells(_precision_line_anchor_cell, target)
	_precision_line_preview_indices = _precision_line_indices(centers, _precision_line_normal)
	_show_precision_line_preview(_precision_line_preview_indices)
	var delta := target - _precision_line_anchor_cell
	_set_status(
		"Линия A→B · ΔX %d · ΔY %d · ΔZ %d · длина %d vox · изменится %d · клик/Enter применяет · Esc отменяет"
		% [delta.x, delta.y, delta.z, centers.size(), _precision_line_preview_indices.size()],
		false,
		Color(0.20, 0.90, 1.0),
	)
	return true


func _precision_line_indices(centers: Array[Vector3i], normal: Vector3i) -> PackedInt32Array:
	var found := {}
	if _resource == null:
		return PackedInt32Array()
	var tool_id := _selected_tool_id()
	var radius := int(_radius.get_item_metadata(_radius.selected))
	var depth := int(_depth.value)
	var coarse := _coarse.button_pressed
	var shape := _brush_footprint_shape()
	var palette_index := int(_palette.get_item_metadata(_palette.selected)) if _palette.selected >= 0 else 1
	if _is_material_tool(tool_id):
		var amount := int(
			_material_preset.get_item_metadata(_material_preset.selected)
			if _material_preset.selected >= 0
			else 0
		)
		for center in centers:
			var indices := Model.oriented_material_stroke_indices(
				_resource, _resource.voxels, center, normal, radius, depth, coarse, shape
			)
			for raw_index in indices:
				var index := int(raw_index)
				var current_amount := (
					int(_resource.transparency[index])
					if index < _resource.transparency.size()
					else 0
				)
				if _precision_preview_allows_index(index) and current_amount != amount:
					found[index] = true
	else:
		for center in centers:
			var changes := Model.oriented_stroke_changes(
				_resource,
				_resource.voxels,
				center,
				normal,
				tool_id,
				palette_index,
				radius,
				depth,
				coarse,
				shape,
			)
			changes = Model.changes_in_block_region(
				changes,
				_resource.grid_size(),
				_resource.normalized_density(),
				_edit_region_blocks,
			)
			for raw_index in changes:
				var index := int(raw_index)
				if _precision_preview_allows_index(index):
					found[index] = true
	var sorted: Array[int] = []
	for raw_index in found:
		sorted.append(int(raw_index))
	sorted.sort()
	return PackedInt32Array(sorted)


func _precision_preview_allows_index(index: int) -> bool:
	return (
		index >= 0
		and index < _resource.voxels.size()
		and _selection_panel.allows_brush_index(index)
		and not _locked_indices.has(index)
		and EditBounds.contains_index(index, _resource.grid_size(), _slice_height)
	)


func _show_precision_line_preview(indices: PackedInt32Array) -> void:
	if not is_instance_valid(_precision_line_preview) or _resource == null or indices.is_empty():
		if is_instance_valid(_precision_line_preview):
			_precision_line_preview.visible = false
		return
	var density := float(_resource.normalized_density())
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * (1.018 / density)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = (
		Color(1.0, 0.38, 0.30, 0.46)
		if _selected_tool_id() == Model.TOOL_REMOVE
		else Color(0.20, 0.90, 1.0, 0.42)
	)
	mesh.material = material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = indices.size()
	var size := _resource.grid_size()
	var layer_size := size.x * size.z
	for preview_index in indices.size():
		var index := int(indices[preview_index])
		var flat := index % layer_size
		var cell := Vector3i(flat % size.x, index / layer_size, flat / size.x)
		multi.set_instance_transform(
			preview_index,
			Transform3D(Basis.IDENTITY, (Vector3(cell) + Vector3.ONE * 0.5) / density),
		)
	_precision_line_preview.multimesh = multi
	_precision_line_preview.visible = true


func _commit_precision_line() -> bool:
	if (
		_precision_line_anchor_cell == Model.INVALID_CELL
		or _precision_line_target_cell == Model.INVALID_CELL
		or _resource == null
	):
		return false
	var centers := Model.line_cells(
		_precision_line_anchor_cell, _precision_line_target_cell
	)
	var normal := _precision_line_normal
	var tool_id := _selected_tool_id()
	_cancel_precision_line(false)
	_prepare_stroke(tool_id)
	_apply_oriented_stroke_segments([{"centers": centers, "normal": normal}])
	_finish_stroke()
	return true


func _cancel_precision_line(show_message := true) -> void:
	var had_anchor := _precision_line_anchor_cell != Model.INVALID_CELL
	_precision_line_anchor_cell = Model.INVALID_CELL
	_precision_line_target_cell = Model.INVALID_CELL
	_precision_line_normal = Vector3i.ZERO
	_precision_line_preview_indices = PackedInt32Array()
	if is_instance_valid(_precision_line_preview):
		_precision_line_preview.multimesh = null
		_precision_line_preview.visible = false
	if show_message and had_anchor:
		_set_status("Линия A→B отменена")


func _flush_pending_stroke_position(exact_position := false) -> void:
	if not _stroke_active or not _has_pending_stroke_position:
		return
	var position := _pending_stroke_position
	_has_pending_stroke_position = false
	_extend_stroke(position, exact_position)


func _stop_single_face_stroke() -> bool:
	_single_face_stopped = true
	_set_status(
		"Только одна грань · край достигнут · отпустите LMB для другой стороны",
		false,
		Color(1.0, 0.72, 0.30),
	)
	return true


func _extend_stroke(position: Vector2, exact_position := false) -> bool:
	var tool_id := _selected_tool_id()
	var oriented := _is_oriented_brush_tool(tool_id)
	var sculpt_like := oriented or _is_relief_tool(tool_id) or _is_smooth_tool(tool_id)
	var sample_position := position
	if sculpt_like:
		if not _has_stroke_smoothed_position or exact_position:
			_stroke_smoothed_position = position
			_has_stroke_smoothed_position = true
		else:
			# A short low-pass removes single-frame pointer spikes. Spatial dab
			# placement below still owns density, so this does not create buildup.
			_stroke_smoothed_position = _stroke_smoothed_position.lerp(position, 0.65)
		sample_position = _stroke_smoothed_position
	# Relief and Smooth must not raycast against geometry they have already
	# changed during this gesture; otherwise a mound can pull its own cursor.
	var pick := _pick_at(sample_position, sculpt_like)
	if pick.is_empty():
		_relief_hold_center = Model.INVALID_CELL
		if oriented and _stroke_normal != Vector3i.ZERO and not _follow_surface.button_pressed:
			return _stop_single_face_stroke()
		if _last_stroke_cell == Model.INVALID_CELL:
			_set_status("Кисть не попала в Surface Canvas", true)
		return false
	var picked_normal := Model.axis_normal(pick.get("normal", Vector3i.UP) as Vector3i)
	if oriented:
		var previous_normal := _last_stroke_normal
		if previous_normal == Vector3i.ZERO:
			previous_normal = _stroke_normal
		var surface_normal := _oriented_brush_normal(pick, previous_normal)
		if surface_normal == Vector3i.ZERO:
			surface_normal = picked_normal
		var center := Model.INVALID_CELL
		if _stroke_normal == Vector3i.ZERO:
			# The first dab chooses the averaged visible side. Subsequent single-face
			# samples are constrained to its exact plane below.
			center = Model.oriented_target_cell(
				pick, surface_normal, tool_id, _resource.grid_size()
			)
			_stroke_normal = surface_normal
			_last_stroke_normal = surface_normal
			_stroke_face_plane = Model.surface_face_plane(
				pick.get("hit", Model.INVALID_CELL), surface_normal
			)
			if _stroke_face_plane <= -999999 and bool(pick.get("empty_floor", false)):
				var face_axis := Model.axis_index(surface_normal)
				_stroke_face_plane = center[face_axis]
		elif not _follow_surface.button_pressed:
			if _single_face_stopped:
				return _stop_single_face_stroke()
			var face_resource := _isolation_resource if _isolation_resource != null else _resource
			var face_values: PackedByteArray = face_resource.voxels
			if (
				_isolation_resource == null
				and _stroke_before.size() == _resource.voxels.size()
			):
				face_values = _stroke_before
			center = Model.single_face_target_cell(
				face_values,
				face_resource.grid_size(),
				pick,
				_stroke_normal,
				_stroke_face_plane,
				tool_id,
				face_resource.normalized_density(),
			)
			if center == Model.INVALID_CELL:
				return _stop_single_face_stroke()
			surface_normal = _stroke_normal
		else:
			# Surface-following Add uses the averaged normal rather than a transient
			# one-voxel stair face reported by the raw ray.
			center = Model.oriented_target_cell(
				pick, surface_normal, tool_id, _resource.grid_size()
			)
		if not _cell_in_edit_region(center):
			center = Model.INVALID_CELL
		if center == Model.INVALID_CELL:
			_relief_hold_center = Model.INVALID_CELL
			if _last_stroke_cell == Model.INVALID_CELL:
				_set_status("Для наращивания нужна свободная грань внутри холста", true)
			return false
		var active_normal := _stroke_normal if not _follow_surface.button_pressed else surface_normal
		var spacing := _oriented_stroke_spacing()
		var centers: Array[Vector3i] = []
		if _stroke_input_cell == Model.INVALID_CELL or active_normal != _last_stroke_normal:
			# A real face switch begins a fresh tangent-plane segment. Never connect
			# its first dab through empty 3D space to the previous plane.
			centers.append(center)
			_stroke_distance_to_next = float(spacing)
		else:
			var sampled := Model.spaced_stroke_segment(
				_stroke_input_cell,
				center,
				_stroke_distance_to_next,
				spacing,
				_last_stroke_cell,
			)
			centers.assign(sampled.points)
			_stroke_distance_to_next = float(sampled.distance_to_next)
		_stroke_input_cell = center
		_last_stroke_normal = active_normal
		if not centers.is_empty():
			_last_stroke_cell = centers[-1]
			return _apply_oriented_stroke_segments([{
				"centers": centers, "normal": active_normal,
			}])
		return true
	var center := _target_cell(pick)
	if center == Model.INVALID_CELL:
		_relief_hold_center = Model.INVALID_CELL
		if _last_stroke_cell == Model.INVALID_CELL:
			_set_status("Для наращивания нужна свободная грань внутри холста", true)
		return false
	var segment_from := center if _last_stroke_cell == Model.INVALID_CELL else _last_stroke_cell
	var centers: Array[Vector3i] = [center]
	if (
		_last_stroke_cell != Model.INVALID_CELL
		and not _is_relief_tool(tool_id)
		and not _is_level_tool(tool_id)
		and not _is_smooth_tool(tool_id)
	):
		centers = Model.line_cells(_last_stroke_cell, center)
	_last_stroke_cell = center
	_last_stroke_normal = picked_normal
	if _is_level_tool(tool_id):
		if _stroke_level_target_y < 0:
			_stroke_level_target_y = center.y
		_relief_hold_center = Model.INVALID_CELL
		return _apply_level_segment(segment_from, center)
	if _is_smooth_tool(tool_id):
		_relief_hold_center = Model.INVALID_CELL
		return _apply_smooth_segment(segment_from, center)
	if _is_relief_tool(tool_id):
		if _is_relief_generator():
			_relief_hold_center = Model.INVALID_CELL
			return _apply_generative_relief_segment(segment_from, center)
		if (
			_relief_hold_center == Model.INVALID_CELL
			or _relief_hold_center.x != center.x
			or _relief_hold_center.z != center.z
		):
			_relief_hold_center = center
			var center_key := Vector2i(center.x, center.z)
			var size := _resource.grid_size()
			var column_index := center.x + center.z * size.x
			var previous_height := maxi(
				int(_stroke_relief_center_height_cache.get(center_key, 0)),
				int(_stroke_relief_amount_cache.get(column_index, 0)),
			)
			var height_limit := int(
				_height_limit.get_item_metadata(_height_limit.selected)
			)
			_relief_applied_height = mini(height_limit, previous_height + 1)
			var applied := _apply_relief_segment(
				segment_from,
				center,
				_relief_applied_height,
				previous_height,
			)
			_stroke_relief_center_height_cache[center_key] = _relief_applied_height
			var rate := float(_buildup_rate.get_item_metadata(_buildup_rate.selected))
			_relief_hold_elapsed = float(_relief_applied_height - 1) / maxf(0.01, rate)
			return applied
		# Pointer motion inside the same voxel must not bypass timed buildup and
		# jump directly to the selected height cap.
		return true
	return _apply_stroke_centers(centers)


func _apply_level_segment(from: Vector3i, to: Vector3i) -> bool:
	var radius := int(_radius.get_item_metadata(_radius.selected))
	var palette_index := int(_palette.get_item_metadata(_palette.selected)) if _palette.selected >= 0 else 1
	var changes := Model.level_segment_changes(
		_resource,
		from,
		to,
		_stroke_level_target_y,
		palette_index,
		radius,
		_coarse.button_pressed,
	)
	var dirty := {}
	_merge_live_changes(changes, dirty)
	return _finish_live_changes(dirty, Model.TOOL_LEVEL, -1)


func _apply_smooth_segment(from: Vector3i, to: Vector3i) -> bool:
	var radius := int(_radius.get_item_metadata(_radius.selected))
	var strength := int(
		_smooth_strength.get_item_metadata(_smooth_strength.selected)
	)
	var palette_index := int(_palette.get_item_metadata(_palette.selected)) if _palette.selected >= 0 else 1
	var changes := Model.smooth_segment_changes(
		_resource,
		_stroke_before,
		from,
		to,
		palette_index,
		radius,
		strength,
		_coarse.button_pressed,
		_stroke_top_cache,
		_stroke_smooth_column_cache,
		_stroke_heightfield,
		_smooth_mode.selected >= 0
		and str(_smooth_mode.get_selected_metadata()) == BrushProfiles.SMOOTH_COMMON,
		_smooth_fill_pits.button_pressed,
	)
	var dirty := {}
	_merge_live_changes(changes, dirty)
	return _finish_live_changes(dirty, Model.TOOL_SMOOTH, -1)


func _apply_relief_segment(
	from: Vector3i,
	to: Vector3i,
	relief_height: int,
	relief_previous_height := 0,
) -> bool:
	var tool_id := _selected_tool_id()
	var radius := int(_radius.get_item_metadata(_radius.selected))
	var palette_index := int(_palette.get_item_metadata(_palette.selected)) if _palette.selected >= 0 else 1
	var center_key := Vector2i(to.x, to.z)
	var center_height := int(_stroke_relief_center_height_cache.get(center_key, 0))
	var changes := (
		_shell_relief_changes(
			_resource,
			_stroke_before,
			from,
			to,
			palette_index,
			radius,
			relief_height,
			_coarse.button_pressed,
			_stroke_top_cache,
			relief_previous_height,
			_stroke_relief_amount_cache,
			_stroke_shell_foundation_cache,
		)
		if _is_shell_relief_tool(tool_id)
		else Model.relief_segment_changes(
			_resource,
			_stroke_before,
			from,
			to,
			tool_id,
			palette_index,
			radius,
			relief_height,
			_coarse.button_pressed,
			_stroke_top_cache,
			relief_previous_height,
			_stroke_relief_amount_cache,
		)
	)
	_stroke_relief_center_height_cache[center_key] = maxi(center_height, relief_height)
	var dirty := {}
	_merge_live_changes(changes, dirty)
	return _finish_live_changes(dirty, tool_id, relief_height)


func _apply_generative_relief_segment(from: Vector3i, to: Vector3i) -> bool:
	var radius := int(_radius.get_item_metadata(_radius.selected))
	var amplitude := int(_height_limit.get_item_metadata(_height_limit.selected))
	var palette_index := (
		int(_palette.get_item_metadata(_palette.selected)) if _palette.selected >= 0 else 1
	)
	var changes := Model.generative_relief_segment_changes(
		_resource,
		_stroke_before,
		from,
		to,
		palette_index,
		radius,
		amplitude,
		int(_relief_generator_scale.get_selected_metadata()),
		int(_relief_generator_detail.get_selected_metadata()),
		_relief_seed_value,
		int(_relief_generator_direction.get_selected_metadata()),
		str(_relief_generator_style.get_selected_metadata()),
		_coarse.button_pressed,
		_stroke_top_cache,
		_stroke_generator_column_cache,
		_stroke_heightfield,
	)
	var dirty := {}
	_merge_live_changes(changes, dirty)
	return _finish_live_changes(dirty, Model.TOOL_RAISE, -1)


func _shell_relief_changes(
	resource: EmberVoxelModelResource,
	baseline_values: PackedByteArray,
	from: Vector3i,
	to: Vector3i,
	palette_index: int,
	radius: int,
	height: int,
	coarse: bool,
	top_cache: Dictionary,
	previous_height: int,
	amount_cache: Dictionary,
	foundation_cache: Dictionary,
) -> Dictionary:
	if _is_shell_lower_tool(_selected_tool_id()):
		return Model.shell_lower_segment_changes(
			resource, baseline_values, from, to, palette_index, radius, height,
			coarse, top_cache, previous_height, amount_cache, foundation_cache,
		)
	return Model.shell_relief_segment_changes(
		resource, baseline_values, from, to, palette_index, radius, height,
		coarse, top_cache, previous_height, amount_cache, foundation_cache,
	)


func _apply_oriented_stroke_segments(segments: Array[Dictionary]) -> bool:
	var tool_id := _selected_tool_id()
	var radius := int(_radius.get_item_metadata(_radius.selected))
	var depth := int(_depth.value)
	var shape := _brush_footprint_shape()
	var palette_index := int(_palette.get_item_metadata(_palette.selected)) if _palette.selected >= 0 else 1
	var dirty := {}
	for segment in segments:
		var normal: Vector3i = segment.get("normal", Vector3i.UP)
		var centers: Array = segment.get("centers", [])
		for raw_center in centers:
			var center: Vector3i = raw_center
			if _is_material_tool(tool_id):
				_apply_material_center(center, dirty, normal, true)
				continue
			var changes := Model.oriented_stroke_changes(
				_resource,
				_stroke_before,
				center,
				normal,
				tool_id,
				palette_index,
				radius,
				depth,
				_coarse.button_pressed,
				shape,
			)
			_merge_live_changes(changes, dirty)
	return _finish_live_changes(dirty, tool_id, -1)


func _apply_stroke_centers(
	centers: Array[Vector3i],
	relief_height := -1,
	relief_previous_height := 0,
) -> bool:
	var tool_id := _selected_tool_id()
	var radius := int(_radius.get_item_metadata(_radius.selected))
	var palette_index := int(_palette.get_item_metadata(_palette.selected)) if _palette.selected >= 0 else 1
	var dirty := {}
	for line_center in centers:
		if _is_material_tool(tool_id):
			_apply_material_center(line_center, dirty)
			continue
		var changes := {}
		if _is_relief_tool(tool_id):
			var active_height := relief_height
			if active_height < 1:
				active_height = int(_height_limit.get_item_metadata(_height_limit.selected))
			var center_key := Vector2i(line_center.x, line_center.z)
			var center_height := int(
				_stroke_relief_center_height_cache.get(center_key, 0)
			)
			if active_height <= center_height:
				continue
			changes = (
				_shell_relief_changes(
					_resource,
					_stroke_before,
					line_center,
					line_center,
					palette_index,
					radius,
					active_height,
					_coarse.button_pressed,
					_stroke_top_cache,
					maxi(relief_previous_height, center_height),
					_stroke_relief_amount_cache,
					_stroke_shell_foundation_cache,
				)
				if _is_shell_relief_tool(tool_id)
				else Model.relief_changes(
					_resource,
					_stroke_before,
					line_center,
					tool_id,
					palette_index,
					radius,
					active_height,
					_coarse.button_pressed,
					_stroke_top_cache,
					maxi(relief_previous_height, center_height),
					_stroke_relief_amount_cache,
				)
			)
			_stroke_relief_center_height_cache[center_key] = active_height
		else:
			changes = Model.stroke_changes(
				_resource,
				line_center,
				tool_id,
				palette_index,
				radius,
				_coarse.button_pressed,
			)
		_merge_live_changes(changes, dirty)
	return _finish_live_changes(dirty, tool_id, relief_height)


func _apply_material_center(
	center: Vector3i,
	dirty: Dictionary,
	normal := Vector3i.UP,
	oriented := false,
) -> void:
	var connected := _slice_height < 0 and _material_scope.selected >= 0 and str(
		_material_scope.get_item_metadata(_material_scope.selected)
	) == "connected"
	if connected and _stroke_smart_fill_applied:
		return
	var indices := PackedInt32Array()
	if connected:
		_stroke_smart_fill_applied = true
		var tolerance := float(
			_material_tolerance.get_item_metadata(_material_tolerance.selected)
			if _material_tolerance.selected >= 0
			else 0.0
		)
		var selection := Model.connected_surface_material_indices(
			_resource,
			center,
			tolerance,
			_edit_region_blocks,
			_surface_heightfield,
		)
		if bool(selection.get("truncated", false)):
			_stroke_rejected = true
			_set_status(
				"Связанная область слишком велика · сначала ограничьте её голубой рабочей областью",
				true,
			)
			return
		indices = selection.get("indices", PackedInt32Array()) as PackedInt32Array
	else:
		var radius := int(_radius.get_item_metadata(_radius.selected))
		indices = (
			Model.oriented_material_stroke_indices(
				_resource,
				_stroke_before,
				center,
				normal,
				radius,
				int(_depth.value),
				_coarse.button_pressed,
				_brush_footprint_shape(),
			)
			if oriented
			else Model.material_stroke_indices(
				_resource, center, radius, _coarse.button_pressed
			)
		)
		indices = Model.indices_in_block_region(
			indices,
			_resource.grid_size(),
			_resource.normalized_density(),
			_edit_region_blocks,
		)
	var amount := int(
		_material_preset.get_item_metadata(_material_preset.selected)
		if _material_preset.selected >= 0
		else 0
	)
	for index in indices:
		var voxel_index := int(index)
		if not _selection_panel.allows_brush_index(voxel_index):
			continue
		if _locked_indices.has(voxel_index):
			_stroke_rejected = true
			_set_status("Защищённая группа не изменена", true)
			continue
		if not EditBounds.contains_index(voxel_index, _resource.grid_size(), _slice_height):
			continue
		if int(_stroke_live_transparency[voxel_index]) == amount:
			continue
		_stroke_live_transparency[voxel_index] = amount
		dirty[voxel_index] = true
		var before_amount := (
			int(_stroke_before_transparency[voxel_index])
			if voxel_index < _stroke_before_transparency.size()
			else 0
		)
		if amount == before_amount:
			_stroke_material_changes.erase(voxel_index)
		else:
			_stroke_material_changes[voxel_index] = true
	_resource.transparency = _stroke_live_transparency


func _merge_live_changes(changes: Dictionary, dirty: Dictionary) -> void:
	if _resource != null:
		changes = Model.changes_in_block_region(
			changes,
			_resource.grid_size(),
			_resource.normalized_density(),
			_edit_region_blocks,
		)
	var live_values := _stroke_live_values
	for raw_index in changes:
		var index := int(raw_index)
		if not _selection_panel.allows_brush_index(index):
			continue
		if _locked_indices.has(index):
			_stroke_rejected = true
			_set_status("Защищённая группа не изменена", true)
			continue
		if not EditBounds.contains_index(index, _resource.grid_size(), _slice_height):
			continue
		var after := int((changes[raw_index] as Dictionary).get("after", live_values[index]))
		live_values[index] = after
		dirty[index] = true
		var original := int(_stroke_before[index])
		if after == original:
			_stroke_changes.erase(index)
		else:
			_stroke_changes[index] = {"before": original, "after": after}


func _finish_live_changes(dirty: Dictionary, tool_id: int, relief_height: int) -> bool:
	if dirty.is_empty():
		return true
	var dirty_indices := _dictionary_indices(dirty)
	_queue_visual_rebuild(
		dirty_indices, _is_relief_tool(tool_id) or _is_smooth_tool(tool_id)
	)
	var change_count := (
		_stroke_material_changes.size() if _is_material_tool(tool_id) else _stroke_changes.size()
	)
	var message := "Мазок: %d art voxels · отпустите LMB · Esc отменяет жест" % change_count
	if _is_relief_tool(tool_id):
		var height_limit := int(_height_limit.get_item_metadata(_height_limit.selected))
		if _is_relief_generator():
			var style := (
				"гребни"
				if str(_relief_generator_style.get_selected_metadata()) == BrushProfiles.RELIEF_RIDGES
				else "почва"
			)
			message = "Генератор · %s · высота %d vox · %d изменений · Esc отменяет" % [
				style, height_limit, _stroke_changes.size(),
			]
		else:
			var mode := (
				"Оболочка вниз"
				if _is_shell_lower_tool(tool_id)
				else "Оболочка вверх"
				if _is_shell_relief_tool(tool_id)
				else "Углубление"
				if tool_id == Model.TOOL_LOWER
				else "Нарастание"
			)
			var rate := int(_buildup_rate.get_item_metadata(_buildup_rate.selected))
			message = "%s %d/%d vox · %d vox/сек · Esc отменяет" % [
				mode, relief_height, height_limit, rate,
			]
	elif _is_level_tool(tool_id):
		message = "Плоскость: высота %d vox · %d изменений · Esc отменяет" % [
			_stroke_level_target_y + 1, _stroke_changes.size(),
		]
	elif _is_smooth_tool(tool_id):
		var strength := int(
			_smooth_strength.get_item_metadata(_smooth_strength.selected)
		)
		var smooth_kind := (
			"общий уровень%s" % (" + ямки" if _smooth_fill_pits.button_pressed else "")
			if _smooth_mode.selected >= 0
			and str(_smooth_mode.get_selected_metadata()) == BrushProfiles.SMOOTH_COMMON
			else "ступени"
		)
		message = "Сглаживание · %s: сила %d vox · %d изменений · Esc отменяет" % [
			smooth_kind, strength, _stroke_changes.size(),
		]
	elif _is_ramp_tool(tool_id):
		message = "Склон A → B: %d изменений" % _stroke_changes.size()
	elif _is_material_tool(tool_id):
		message = (
			"Связанная область: %d voxels · один Undo · Esc отменяет" % change_count
			if _stroke_smart_fill_applied
			else "Материал: %d voxels · форма и цвет не меняются · Esc отменяет" % change_count
		)
	_set_status(message, false, Color(1.0, 0.72, 0.30))
	return true


func _finish_stroke() -> void:
	if not _stroke_active:
		return
	var before := _stroke_before
	var after := _resource.voxels.duplicate() if _resource != null else PackedByteArray()
	var material_tool := _is_material_tool(_selected_tool_id())
	var before_transparency := _stroke_before_transparency
	var after_transparency := (
		_resource.transparency.duplicate() if _resource != null else PackedByteArray()
	)
	var clear_transient_selection := BrushProfiles.mask_kind(_stroke_tool_id) == "columns"
	var indices := _dictionary_indices(
		_stroke_material_changes if material_tool else _stroke_changes
	)
	var rejected := _stroke_rejected
	_clear_stroke_state()
	if _resource == null or indices.is_empty():
		if not rejected:
			_set_status("Мазок ничего не изменил")
		return
	var committed := (
		_actions.commit_applied_transparency_stroke(
			_resource, before_transparency, after_transparency, indices
		)
		if material_tool
		else _actions.commit_applied_stroke(_resource, before, after, indices)
	)
	if not committed:
		_set_status("Не удалось добавить мазок в историю Undo", true)
		return
	if _selection_panel.preserves_mask_after_commit():
		_selection_panel.preserve_next_source_change(clear_transient_selection)
	_resource.emit_changed()
	if not material_tool:
		_surface_heightfield = Model.refresh_column_heights(
			_surface_heightfield,
			_resource.voxels,
			_resource.grid_size(),
			indices,
			_resource.palette.size() - 1,
		)
		_heightfield_source_voxels = _resource.voxels
	# Replace any cheap hold-preview with the exact volumetric mesh after the
	# gesture. It remains queued one chunk per frame, so pointer-up never stalls.
	_queue_visual_rebuild(indices, false)
	_rebuild_grid()
	_rebuild_region_overlay()
	_update_cursor(_viewport_container.get_local_mouse_position())
	_set_status(
		"Изменено %d art voxels · один Ctrl+Z отменяет весь мазок" % indices.size(),
		false,
		Color(1.0, 0.72, 0.30),
	)


func _cancel_stroke() -> void:
	if not _stroke_active:
		return
	var material_tool := _is_material_tool(_selected_tool_id())
	var indices := _dictionary_indices(
		_stroke_material_changes if material_tool else _stroke_changes
	)
	if _resource != null:
		_resource.voxels = _stroke_before.duplicate()
		_resource.transparency = _stroke_before_transparency.duplicate()
		_selection_panel.preserve_next_source_change()
		_resource.emit_changed()
	_clear_stroke_state()
	if not indices.is_empty():
		_rebuild_visual(indices)
	_set_status("Текущий мазок отменён")


func _clear_stroke_state() -> void:
	_stroke_active = false
	_stroke_tool_id = -1
	_stroke_before = PackedByteArray()
	_stroke_live_values = PackedByteArray()
	_stroke_changes.clear()
	_stroke_before_transparency = PackedByteArray()
	_stroke_live_transparency = PackedByteArray()
	_stroke_material_changes.clear()
	_stroke_smart_fill_applied = false
	_stroke_rejected = false
	_stroke_top_cache.clear()
	_stroke_relief_amount_cache.clear()
	_stroke_relief_center_height_cache.clear()
	_stroke_shell_foundation_cache.clear()
	_stroke_smooth_column_cache.clear()
	_stroke_generator_column_cache.clear()
	_stroke_heightfield = PackedInt32Array()
	_last_stroke_cell = Model.INVALID_CELL
	_stroke_normal = Vector3i.ZERO
	_last_stroke_normal = Vector3i.ZERO
	_stroke_face_plane = -999999
	_single_face_stopped = false
	_stroke_input_cell = Model.INVALID_CELL
	_stroke_distance_to_next = 1.0
	_stroke_smoothed_position = Vector2.ZERO
	_has_stroke_smoothed_position = false
	_has_pending_stroke_position = false
	_relief_hold_center = Model.INVALID_CELL
	_relief_hold_elapsed = 0.0
	_relief_applied_height = 0
	_stroke_level_target_y = -1


func _dictionary_indices(values: Dictionary) -> PackedInt32Array:
	var indices := PackedInt32Array()
	for raw_index in values:
		indices.append(int(raw_index))
	return indices


func _update_cursor(position: Vector2) -> void:
	if is_instance_valid(_selection_panel) and _selection_panel.active:
		_cursor.hide()
		_show_precision_line_preview(PackedInt32Array())
		return
	if _resource == null or _cursor == null or not is_visible_in_tree():
		return
	if _precision_line_anchor_cell != Model.INVALID_CELL:
		var line_target := _precision_line_target_at(position)
		if line_target != Model.INVALID_CELL:
			_set_precision_line_target(line_target)
		_cursor.visible = false
		return
	var tool_id := _selected_tool_id()
	var pick := _pick_at(position, _stroke_active and _is_oriented_brush_tool(tool_id))
	if pick.is_empty():
		_cursor.visible = false
		if _application_kind() in [BrushProfiles.APPLICATION_POINT, BrushProfiles.APPLICATION_LINE]:
			_show_precision_line_preview(PackedInt32Array())
		return
	var cursor_surface_normal := Vector3i.ZERO
	if (
		_is_oriented_brush_tool(tool_id)
		and _application_kind() == BrushProfiles.APPLICATION_STROKE
	):
		var previous := _last_stroke_normal if _stroke_active else Vector3i.ZERO
		cursor_surface_normal = _surface_axis_for_pick(pick, previous)
	var cell := _target_cell(pick)
	if cursor_surface_normal != Vector3i.ZERO:
		cell = Model.oriented_target_cell(
			pick, cursor_surface_normal, tool_id, _resource.grid_size()
		)
		if not _cell_in_edit_region(cell):
			cell = Model.INVALID_CELL
	if cell == Model.INVALID_CELL or not Model.contains(cell, _resource.grid_size()):
		_cursor.visible = false
		if _application_kind() in [BrushProfiles.APPLICATION_POINT, BrushProfiles.APPLICATION_LINE]:
			_show_precision_line_preview(PackedInt32Array())
		return
	if (
		_is_oriented_brush_tool(tool_id)
		and _application_kind() in [BrushProfiles.APPLICATION_POINT, BrushProfiles.APPLICATION_LINE]
	):
		var preview_normal := Model.axis_normal(
			pick.get("normal", Vector3i.UP) as Vector3i
		)
		_show_precision_line_preview(_precision_line_indices([cell], preview_normal))
		_cursor.visible = false
		return
	var density := float(_resource.normalized_density())
	var radius := int(_radius.get_item_metadata(_radius.selected)) if _radius.selected >= 0 else 1
	var span := radius * 2 if _coarse.button_pressed else radius * 2 - 1
	var relief := _is_relief_tool(tool_id)
	var level := _is_level_tool(tool_id)
	var cursor_height := 2 if _coarse.button_pressed else 1
	if relief and _height_limit.selected >= 0:
		cursor_height = int(_height_limit.get_item_metadata(_height_limit.selected))
	if relief:
		var cone := CylinderMesh.new()
		var edge_radius := float(span) * 0.5 / density
		var tip_radius := 0.5 / density
		cone.height = float(cursor_height) / density
		cone.radial_segments = 16
		cone.rings = 4
		var raising := tool_id in [Model.TOOL_RAISE, Model.TOOL_SHELL_RAISE]
		cone.top_radius = tip_radius if raising else edge_radius
		cone.bottom_radius = edge_radius if raising else tip_radius
		_cursor.mesh = cone
		var direction := 1.0 if raising else -1.0
		_cursor.position = Vector3(
			(float(cell.x) + 0.5) / density,
			(float(cell.y) + 1.0 + direction * float(cursor_height) * 0.5) / density,
			(float(cell.z) + 0.5) / density,
		)
	elif _is_oriented_brush_tool(tool_id):
		var outward := Model.axis_normal(pick.get("normal", Vector3i.UP) as Vector3i)
		if cursor_surface_normal != Vector3i.ZERO:
			outward = cursor_surface_normal
		if _stroke_active and not _follow_surface.button_pressed and _stroke_normal != Vector3i.ZERO:
			outward = _stroke_normal
		var direction := outward if tool_id == Model.TOOL_ADD else -outward
		var depth := int(_depth.value)
		if _coarse.button_pressed:
			depth = ceili(float(depth) / 2.0) * 2
		var axis := Model.axis_index(direction)
		var box := BoxMesh.new()
		var box_size := Vector3(float(span), float(span), float(span)) / density
		box_size[axis] = float(depth) / density
		box.size = box_size
		_cursor.mesh = box
		_cursor.position = (
			Vector3(cell)
			+ Vector3(0.5, 0.5, 0.5)
			+ Vector3(direction) * float(depth - 1) * 0.5
		) / density
	else:
		var box := BoxMesh.new()
		box.size = Vector3(float(span) / density, float(cursor_height) / density, float(span) / density)
		_cursor.mesh = box
		var cursor_cell := cell
		if level and _stroke_level_target_y >= 0:
			cursor_cell.y = _stroke_level_target_y
		_cursor.position = (Vector3(cursor_cell) + Vector3(0.5, 0.5, 0.5)) / density
	_cursor.visible = true


func _update_camera() -> void:
	if _camera == null:
		return
	var distance := 7.0
	var offset := Vector3(
		cos(_pitch) * sin(_yaw),
		-sin(_pitch),
		cos(_pitch) * cos(_yaw),
	) * distance
	_camera.position = _camera_target + offset
	_camera.look_at(_camera_target, Vector3.UP)
	_camera.size = _ortho_size


func _pan_camera(relative: Vector2) -> void:
	if _camera == null:
		return
	var right := _camera.global_transform.basis.x.normalized()
	var up := _camera.global_transform.basis.y.normalized()
	var world_per_pixel := _ortho_size / maxf(320.0, _viewport_container.size.y)
	_camera_target += (
		-right * relative.x + up * relative.y
	) * world_per_pixel
	_update_camera()
	_sync_camera_controls()


func _zoom_camera_at(position: Vector2, factor: float) -> void:
	if _camera == null or _viewport == null or _viewport_container == null:
		return
	var previous_size := _ortho_size
	var next_size := clampf(previous_size * factor, 1.5, 128.0)
	if is_equal_approx(previous_size, next_size):
		return
	var local_size := _viewport_container.size.max(Vector2.ONE)
	var render_size := Vector2(_viewport.size).max(Vector2.ONE)
	var viewport_position := position * render_size / local_size
	var aspect := render_size.x / render_size.y
	var horizontal := (viewport_position.x / render_size.x - 0.5) * aspect
	var vertical := 0.5 - viewport_position.y / render_size.y
	var right := _camera.global_transform.basis.x.normalized()
	var up := _camera.global_transform.basis.y.normalized()
	var anchor_before := right * horizontal * previous_size + up * vertical * previous_size
	var anchor_after := right * horizontal * next_size + up * vertical * next_size
	_camera_target += anchor_before - anchor_after
	_ortho_size = next_size
	_update_camera()
	_sync_camera_controls()


func _center_camera() -> void:
	_camera_target = _default_camera_target()
	_update_camera()
	_sync_camera_controls()
	_set_status("Камера снова смотрит в центр рабочей области")


func _on_view_action(action_id: int) -> void:
	match action_id:
		ViewAction.WORLD_CAMERA:
			_set_camera_preset(false)
		ViewAction.BATTLE_CAMERA:
			_set_camera_preset(true)
		ViewAction.TOP_CAMERA:
			_set_top_camera()
		ViewAction.FIT_SURFACE:
			_fit_camera_to_surface()
		ViewAction.CENTER_CAMERA:
			_center_camera()
		ViewAction.CAMERA_SETTINGS:
			_show_camera_settings()
		ViewAction.GRID_OVERLAY:
			_show_grid = not _show_grid
			_grid.visible = _show_grid
			_view_menu.get_popup().set_item_checked(
				_view_menu.get_popup().get_item_index(action_id), _show_grid
			)
		ViewAction.REGION_OVERLAY:
			_show_region = not _show_region
			_rebuild_region_overlay()
			_view_menu.get_popup().set_item_checked(
				_view_menu.get_popup().get_item_index(action_id), _show_region
			)


func _set_camera_preset(battle: bool) -> void:
	_yaw = deg_to_rad(45.0)
	_pitch = deg_to_rad(-43.0 if battle else -58.0)
	_camera_target = _default_camera_target()
	_fit_camera_to_surface()


func _fit_camera_to_surface(show_status := true) -> void:
	if _camera == null or _resource == null:
		return
	_camera_target = _default_camera_target()
	_update_camera()
	var focus := _camera_focus_region()
	var width := float(focus.size.x)
	var depth := float(focus.size.y)
	var height := maxf(0.25, _surface_height_world(focus))
	var right := _camera.global_transform.basis.x.normalized()
	var up := _camera.global_transform.basis.y.normalized()
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for x in [float(focus.position.x), float(focus.end.x)]:
		for y in [0.0, height]:
			for z in [float(focus.position.y), float(focus.end.y)]:
				var relative := Vector3(x, y, z) - _camera_target
				var projected_x := relative.dot(right)
				var projected_y := relative.dot(up)
				min_x = minf(min_x, projected_x)
				max_x = maxf(max_x, projected_x)
				min_y = minf(min_y, projected_y)
				max_y = maxf(max_y, projected_y)
	var aspect := float(_viewport.size.x) / maxf(1.0, float(_viewport.size.y))
	var required_vertical := maxf(
		maxf(max_y - min_y, (max_x - min_x) / maxf(0.2, aspect)),
		maxf(width, depth),
	)
	_ortho_size = clampf(required_vertical * _camera_fit_margin, 1.5, 128.0)
	_update_camera()
	_sync_camera_controls()
	if show_status:
		_set_status(
			("Рабочая область %d×%d в кадре · масштаб %.2f · запас %.2fx"
			% [focus.size.x, focus.size.y, _ortho_size, _camera_fit_margin])
			if _edit_region_blocks.has_area()
			else "Вся поверхность в кадре · масштаб %.2f · запас %.2fx" % [_ortho_size, _camera_fit_margin]
		)


func _surface_height_world(region := Rect2i()) -> float:
	if _resource == null:
		return 0.0
	var density := _resource.normalized_density()
	var blocks := (
		region
		if region.has_area()
		else Rect2i(Vector2i.ZERO, Vector2i(_resource.size_blocks.x, _resource.size_blocks.z))
	)
	var grid_width := _resource.grid_size().x
	var maximum := -1
	for z in range(blocks.position.y * density, blocks.end.y * density):
		for x in range(blocks.position.x * density, blocks.end.x * density):
			var index := z * grid_width + x
			if index < _surface_heightfield.size():
				var top := int(_surface_heightfield[index])
				if _slice_height >= 0:
					top = mini(top, _slice_height - 1)
				maximum = maxi(maximum, top)
	return float(maximum + 1) / float(density)


func _show_camera_settings() -> void:
	if _camera_popup == null:
		return
	_sync_camera_controls()
	_camera_popup.popup_centered(Vector2i(370, 285))


func _sync_camera_controls() -> void:
	if is_instance_valid(_camera_yaw_control):
		_camera_yaw_control.set_value_no_signal(rad_to_deg(_yaw))
	if is_instance_valid(_camera_pitch_control):
		_camera_pitch_control.set_value_no_signal(rad_to_deg(_pitch))
	if is_instance_valid(_camera_size_control):
		_camera_size_control.set_value_no_signal(_ortho_size)
	if is_instance_valid(_camera_margin_control):
		_camera_margin_control.set_value_no_signal(_camera_fit_margin)


func _on_camera_yaw_changed(value: float) -> void:
	_yaw = deg_to_rad(value)
	_update_camera()


func _on_camera_pitch_changed(value: float) -> void:
	_pitch = deg_to_rad(value)
	_update_camera()


func _on_camera_size_changed(value: float) -> void:
	_ortho_size = value
	_update_camera()


func _on_camera_margin_changed(value: float) -> void:
	_camera_fit_margin = value
	_fit_camera_to_surface(false)


func _set_top_camera() -> void:
	_yaw = deg_to_rad(45.0)
	_pitch = deg_to_rad(-88.0)
	_fit_camera_to_surface()


func _default_camera_target() -> Vector3:
	if _resource == null:
		return DEFAULT_CAMERA_TARGET
	var focus := _camera_focus_region()
	return Vector3(
		float(focus.position.x) + float(focus.size.x) * 0.5,
		maxf(DEFAULT_CAMERA_TARGET.y, _surface_height_world(focus) * 0.5),
		float(focus.position.y) + float(focus.size.y) * 0.5,
	)


func _camera_focus_region() -> Rect2i:
	if _resource == null:
		return Rect2i(Vector2i.ZERO, Vector2i.ONE)
	return (
		_edit_region_blocks
		if _edit_region_blocks.has_area()
		else Rect2i(Vector2i.ZERO, Vector2i(_resource.size_blocks.x, _resource.size_blocks.z))
	)


func _reset_pilot() -> void:
	_finish_stroke()
	_cancel_precision_line(false)
	if _resource_path == Model.PILOT_PATH and _resource != null and _actions.reset_pilot(_resource):
		_set_status("Пилот сброшен · НЕ СОХРАНЕНО · Ctrl+Z отменяет", false, Color(1.0, 0.72, 0.30))


func _save() -> bool:
	# Generator preview is not the sculpt Resource. Route every workshop Save
	# entry point through the same explicit recipe publication transaction.
	if _generator_active():
		_generator_panel.context["manual_dirty"] = has_unsaved_changes()
		var saved: bool = _generator_panel.save_variant()
		_set_status(_generator_panel._info.text, not saved)
		return saved
	_flush_pending_stroke_position()
	_finish_stroke()
	_cancel_precision_line(false)
	if _resource == null:
		return false
	if _object_session != null:
		var result: Dictionary = _object_session.save(_resource)
		if not bool(result.get("ok", false)):
			_set_status(str(result.get("error", "Сохранение не завершено")), true)
			return false
		_resource_path = str(result.get("path", ""))
		_saved_voxels = _resource.voxels.duplicate()
		_saved_palette = _resource.palette.duplicate()
		_saved_transparency = _resource.transparency.duplicate()
		_saved_surface_fill_levels = _resource.surface_fill_levels.duplicate()
		_saved_surface_fill_materials = _resource.surface_fill_materials.duplicate()
		_saved_surface_fill_palette = _resource.surface_fill_palette.duplicate()
		_saved_voxel_groups = _resource.voxel_groups.duplicate(true)
		_saved_schema_version = _resource.schema_version
		_saved_size_blocks = _resource.size_blocks
		_saved_height_voxels = _resource.height_voxels
		_capture_growth_channels()
		_resource_path_label.text = _object_session.label() + " · " + _resource_path
		_set_status("Модель и коллизия обновлены. Сохраните сцену обычным Ctrl+S в 3D.")
		return true
	var errors := _resource.validation_errors()
	if not errors.is_empty():
		_set_status("Сохранение остановлено · %s" % errors[0], true)
		return false
	var save_path := Model.surface_save_path(_resource, _resource_path)
	if save_path.is_empty():
		_set_status(
			"У Surface нет внешнего .tres пути. Откройте её через связанную карту или поле боя.",
			true,
		)
		return false
	var absolute := ProjectSettings.globalize_path(save_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var externalizing := (
		not Model.is_writable_resource_path(_resource_path)
		or not Model.is_writable_resource_path(_resource.resource_path)
		or _resource.resource_path != save_path
	)
	var save_error := ResourceSaver.save(
		_resource,
		save_path,
		ResourceSaver.FLAG_CHANGE_PATH if externalizing else 0,
	)
	if save_error != OK:
		_set_status(
			"Ошибка сохранения %s: %s" % [save_path, error_string(save_error)],
			true,
		)
		return false
	if externalizing:
		_resource.take_over_path(save_path)
		if not _persist_external_owner_link():
			return false
	_resource_path = save_path
	if is_instance_valid(_resource_path_label):
		_resource_path_label.text = save_path
	_saved_voxels = _resource.voxels.duplicate()
	_saved_palette = _resource.palette.duplicate()
	_saved_transparency = _resource.transparency.duplicate()
	_saved_surface_fill_levels = _resource.surface_fill_levels.duplicate()
	_saved_surface_fill_materials = _resource.surface_fill_materials.duplicate()
	_saved_surface_fill_palette = _resource.surface_fill_palette.duplicate()
	_saved_voxel_groups = _resource.voxel_groups.duplicate(true)
	_saved_schema_version = _resource.schema_version
	_saved_size_blocks = _resource.size_blocks
	_saved_height_voxels = _resource.height_voxels
	_capture_growth_channels()
	if _editor_interface != null:
		preload("res://addons/ember_import/ember_editor_filesystem.gd").request(_editor_interface.get_resource_filesystem())
	_set_status(
		("Surface вынесена во внешний Resource и сохранена · %s" % save_path)
		if externalizing
		else "Surface Canvas сохранён · %s" % save_path
	)
	return true


func _persist_external_owner_link() -> bool:
	if _resource == null:
		return false
	if "battlefield" in _resource.tags:
		var owner_path := Model.battlefield_resource_path_for_surface(_resource)
		if owner_path.is_empty():
			_set_status(
				"Surface сохранена, но связанное поле боя не найдено · %s" % _resource.resource_path,
				true,
			)
			return false
		var field := load(owner_path) as EmberBattlefieldResource
		if field == null:
			_set_status("Surface сохранена, но не удалось открыть %s" % owner_path, true)
			return false
		field.visual_surface = _resource
		field.notify_authoring_changed()
		var owner_error := ResourceSaver.save(field, owner_path)
		if owner_error != OK:
			_set_status(
				"Surface сохранена, но ссылка поля боя не обновлена: %s" % error_string(owner_error),
				true,
			)
			return false
	elif "world" in _resource.tags and _editor_interface != null:
		# The world owner is a scene. Keep the external bytes safe and let the
		# normal scene Save serialize its new Resource path.
		_editor_interface.mark_scene_as_unsaved()
	return true


func _owner_scene_path() -> String:
	if _resource == null or not _resource.tags.has("world"):
		return ""
	var owner := str(_resource.material.get("semanticOwner", "")).strip_edges()
	if owner.is_empty():
		return ""
	var path := "res://scenes/%s.tscn" % owner
	return path if ResourceLoader.exists(path) else ""


func _play_owner_scene() -> void:
	var path := _owner_scene_path()
	if path.is_empty():
		_set_status("У Surface нет связанной world-сцены для запуска", true)
		return
	if not _save():
		return
	if _editor_interface == null:
		_set_status("EditorInterface недоступен", true)
		return
	if _editor_interface.is_playing_scene():
		_editor_interface.stop_playing_scene()
	_editor_interface.play_custom_scene(path)
	_set_status("Запущена связанная карта · %s" % path)


func _on_source_changed(indices: PackedInt32Array) -> void:
	_cancel_precision_line(false)
	_surface_normal_cache_key.clear()
	_surface_normal_cache_value = Vector3.ZERO
	_sync_canvas_dimensions()
	if _resource != null and _resource.voxel_groups != _displayed_groups:
		_refresh_groups(_groups_panel.selected_id())
		_hidden_group_indices = _groups_panel.hidden_indices()
		_isolated_group_indices = (
			_groups_panel.current_group().get("indices", PackedInt32Array())
			if _groups_panel.isolation_enabled()
			else PackedInt32Array()
		)
	if not _isolated_group_indices.is_empty() or not _hidden_group_indices.is_empty():
		_rebuild_group_view_filter()
		return
	if _resource != null and _resource.palette != _displayed_palette:
		_refresh_palette()
	_rebuild_visual(indices)
	show_current_status()


func _sync_canvas_dimensions() -> void:
	if _resource == null or _resource.grid_size() == _displayed_grid:
		return
	_displayed_grid = _resource.grid_size()
	for mesh in _chunk_meshes.values():
		mesh.queue_free()
	_chunk_meshes.clear()
	_pending_preview_chunks.clear()
	_edit_region_blocks = Rect2i(Vector2i.ZERO, Vector2i(_resource.size_blocks.x, _resource.size_blocks.z))
	_slice_height = -1
	_slice_control.configure(_displayed_grid.y)
	_slice_control.restore_view(-1)
	_selection_panel.clear_selection(false)
	_surface_heightfield = PackedInt32Array()
	_heightfield_source_voxels = PackedByteArray()
	_cancel_ramp_anchor(false)
	_sync_context_frame()


func _toggle_scene_context(enabled: bool) -> void:
	_context_opacity.editable = enabled
	_context_refresh.disabled = not enabled
	if not enabled:
		_scene_context.visible = false
		_scene_context.clear()
		return
	_refresh_scene_context()


func _refresh_scene_context() -> void:
	if _object_session == null:
		return
	var projection: Dictionary = _object_session.context_projection(_resource)
	var report: Dictionary = projection if projection.has("error") else _scene_context.rebuild(projection.scene, projection.target, projection.frame)
	if report.has("error"):
		_context_toggle.set_pressed_no_signal(false)
		_toggle_scene_context(false)
		_set_status(str(report.error), true)
		return
	_scene_context.set_opacity(_context_opacity.value / 100.0)
	_scene_context.visible = true
	_set_status("Окружение: %d деталей · %.1f мс · только просмотр. После расстановки в 3D нажмите «Обновить окружение»." % [report.count, report.milliseconds])


func _sync_context_frame() -> void:
	if _object_session == null or not is_instance_valid(_scene_context) or not _scene_context.visible:
		return
	var projection: Dictionary = _object_session.context_projection(_resource)
	if projection.has("error") or absf((projection.frame as Transform3D).basis.determinant()) < 0.000001:
		_context_toggle.set_pressed_no_signal(false)
		_toggle_scene_context(false)
		_set_status(str(projection.get("error", "Нулевой масштаб объекта: окружение скрыто.")), true)
		return
	_scene_context.set_frame(projection.frame)


func _capture_growth_channels() -> void:
	for channel in ["emissive", "shine", "transmittance", "collision_voxels", "merge_parts", "voxel_part_ids"]:
		_saved_growth_channels[channel] = _resource.get(channel).duplicate()


func _show_canvas_growth() -> void:
	if _object_session == null or _resource == null:
		return
	_flush_pending_stroke_position()
	_finish_stroke()
	_cancel_precision_line(false)
	var source := _resource
	var dialog := ConfirmationDialog.new()
	dialog.title = "Расширить холст объекта"
	dialog.get_ok_button().text = "Применить"
	var box := VBoxContainer.new()
	dialog.add_child(box)
	var info := Label.new()
	info.text = "Сейчас: %s vox. X/Z — симметрично, Y — вверх.\nГотовая геометрия не сдвигается и не растягивается." % source.grid_size()
	box.add_child(info)
	var controls: Array[SpinBox] = []
	for axis in 3:
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := Label.new()
		label.text = ["Ширина X", "Высота Y", "Глубина Z"][axis]
		label.custom_minimum_size.x = 120
		row.add_child(label)
		var value := SpinBox.new()
		value.min_value = source.grid_size()[axis]
		value.max_value = 8 * source.normalized_density() if axis == 1 else 256
		value.step = 1 if axis == 1 else source.normalized_density()
		value.value = source.grid_size()[axis]
		row.add_child(value)
		controls.append(value)
	var preview := Label.new()
	box.add_child(preview)
	var refresh := func(_unused := 0.0):
		var size := Vector3i(controls[0].value, controls[1].value, controls[2].value)
		var result := preload("res://addons/ember_import/ember_voxel_canvas_growth.gd").plan(source, size)
		preview.text = str(result.error) if result.has("error") else "Будет: %s vox · добавлено пустых ячеек: %d" % [size, size.x * size.y * size.z - source.voxels.size()]
		if not result.has("error") and size.x * size.y * size.z > preload("res://addons/ember_import/ember_voxel_shapes.gd").WARNING_CELLS:
			preview.text += "\nБольшой холст: применение и сохранение могут занять несколько секунд."
		dialog.get_ok_button().disabled = result.has("error")
	for control in controls:
		control.value_changed.connect(refresh)
	dialog.confirmed.connect(func():
		if _resource == source and _object_session != null:
			var result := _actions.grow_canvas(source, Vector3i(controls[0].value, controls[1].value, controls[2].value))
			if result.has("error"):
				_set_status(str(result.error), true)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	refresh.call()
	dialog.popup_centered()


func _disconnect_resource() -> void:
	if is_instance_valid(_generator_panel):
		_generator_panel.close_source()
	_remember_current_editor_view()
	_return_to_last_brush()
	_isolation_resource = null
	_isolated_group_indices = PackedInt32Array()
	_hidden_group_indices = PackedInt32Array()
	if is_instance_valid(_groups_panel):
		_groups_panel.clear_view_filters(false)
		_groups_panel.sync([], "")
	if is_instance_valid(_selection_panel):
		_selection_panel.set_active(false)
		_selection_panel.sync(null, Rect2i(), -1, _surface_root)
	_set_color_pick(false)
	if is_instance_valid(_palette_panel):
		_palette_panel.sync(null, 1)
	_cancel_stroke()
	_cancel_ramp_anchor(false)
	_cancel_precision_line(false)
	_region_anchor_block = Vector2i(-1, -1)
	_region_preview_blocks = Rect2i()
	_edit_region_blocks = Rect2i()
	if is_instance_valid(_region_select_button):
		_region_select_button.set_pressed_no_signal(false)
	_update_region_label(_edit_region_blocks)
	_pending_preview_chunks.clear()
	for visual in _chunk_meshes.values():
		if is_instance_valid(visual):
			(visual as Node).queue_free()
	_chunk_meshes.clear()
	_surface_heightfield = PackedInt32Array()
	_heightfield_source_voxels = PackedByteArray()
	_resource = null
	_resource_path = ""
	_update_workshop_shell()


func _generator_active() -> bool:
	return is_instance_valid(_generator_panel) and is_instance_valid(_sidebar_tabs) and _sidebar_tabs.get_current_tab_control() == _generator_panel


func _on_generator_assets_changed(model_id: String) -> void:
	generator_assets_changed.emit(model_id)
	if _resource != null and _resource.model_id == model_id and not has_unsaved_changes():
		_reload_generator_source.call_deferred(model_id)


func _reload_generator_source(model_id: String) -> void:
	if _resource == null or _resource.model_id != model_id or has_unsaved_changes():
		return
	var was_active := _generator_active()
	if _object_session != null:
		var session := _object_session
		if session.refresh_before_open():
			_open_object_unchecked(session)
	else:
		var source := EmberVoxelCatalog.native_resource(model_id)
		if source != null:
			_open_surface_unchecked(source, source.resource_path)
	if was_active and not _sidebar_tabs.is_tab_hidden(2):
		_sidebar_tabs.current_tab = 2


func _sync_generator_panel() -> void:
	if not is_instance_valid(_generator_panel):
		return
	var context := {}
	if _object_session != null and _object_session.has_method("generator_context"):
		context = _object_session.generator_context()
	elif Engine.is_editor_hint():
		var scene := EditorInterface.get_edited_scene_root() as Node3D
		if scene != null:
			var parent := scene.get_node_or_null("Map/Props") as Node3D
			context = {"root": scene, "parent": parent if parent != null else scene,
				"position": Vector3.ZERO, "world_size": 16.0}
	if not context.is_empty() and _actions != null:
		context["undo"] = _actions._undo_redo
	var supported: bool = _generator_panel.open_source(_resource, context)
	_sidebar_tabs.set_tab_hidden(_generator_panel.get_index(), not supported)


func _show_generator_preview(packed: PackedScene, source: EmberVoxelModelResource) -> void:
	if is_instance_valid(_generator_preview):
		_generator_preview.free()
	_generator_preview = null
	if is_instance_valid(_surface_root):
		_surface_root.visible = packed == null
	if packed == null or source == null or _resource == null:
		return
	_flush_pending_stroke_position()
	_finish_stroke()
	_cursor.hide()
	var prop := packed.instantiate() as EmberVoxelProp
	prop.configure_voxel_scale(source.normalized_density(), 1.0)
	# Use the exact prepared prefab mesh/material, in the existing Canvas viewport.
	var mesh := prop.get_node("Mesh") as MeshInstance3D
	mesh.owner = null
	prop.remove_child(mesh)
	_generator_preview = Node3D.new()
	_generator_preview.name = "GeneratorRecipePreview"
	_generator_preview.add_child(mesh)
	_generator_preview.position = Vector3(_resource.size_blocks.x * 0.5, 0, _resource.size_blocks.z * 0.5)
	_viewport.add_child(_generator_preview)
	prop.free()


func _set_status(message: String, error := false, color := Color(0.66, 0.74, 0.84)) -> void:
	if is_instance_valid(_title) and _resource != null:
		_title.text = "ВОКСЕЛЬНАЯ МАСТЕРСКАЯ · %s%s" % [
			_resource.display_name.to_upper(), " *" if has_unsaved_changes() else ""
		]
	var actual_message := message
	if (
		not error
		and is_instance_valid(_selection_panel)
		and _selection_panel.mask_is_suspended()
		and not message.contains("Маска сохранена")
	):
		actual_message = "Маска сохранена · не действует · " + message
	var actual_color := Color(1.0, 0.45, 0.40) if error else color
	if _status != null:
		_status.text = actual_message
		_status.tooltip_text = actual_message
		_status.modulate = actual_color
	_update_workshop_shell()
	status_changed.emit(actual_message, actual_color)
