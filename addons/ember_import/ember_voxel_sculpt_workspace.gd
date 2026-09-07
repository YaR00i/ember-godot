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

signal status_changed(message: String, color: Color)

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
var _region_overlay: MeshInstance3D
var _tool: ItemList
var _radius: OptionButton
var _volume_operation: OptionButton
var _relief_direction: OptionButton
var _relief_geometry: OptionButton
var _region_select_button: Button
var _region_label: Label
var _height_limit: OptionButton
var _buildup_rate: OptionButton
var _smooth_strength: OptionButton
var _palette: OptionButton
var _palette_panel: VBoxContainer
var _displayed_palette := PackedColorArray()
var _picking_color := false
var _selection_panel: VBoxContainer
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
var _active_tool_label: Label
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
var _stroke_heightfield := PackedInt32Array()
var _surface_heightfield := PackedInt32Array()
var _heightfield_source_voxels := PackedByteArray()
var _last_stroke_cell := Model.INVALID_CELL
var _pending_stroke_position := Vector2.ZERO
var _has_pending_stroke_position := false
var _relief_hold_center := Model.INVALID_CELL
var _relief_hold_elapsed := 0.0
var _relief_applied_height := 0
var _stroke_level_target_y := -1
var _ramp_anchor_cell := Model.INVALID_CELL
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


func _ready() -> void:
	visibility_changed.connect(_on_workspace_visibility_changed)


func _on_workspace_visibility_changed() -> void:
	if not is_visible_in_tree():
		if is_instance_valid(_selection_panel):
			_selection_panel.set_active(false)
		if is_instance_valid(_groups_panel):
			_groups_panel.cancel_isolation()
		_set_color_pick(false)
		if is_instance_valid(_palette_panel):
			_palette_panel.cancel_edit()
		_flush_pending_stroke_position()
		_finish_stroke()
		_remember_current_editor_view()
		_orbiting = false
		_panning = false


func _process(delta: float) -> void:
	_drain_preview_chunk()
	_flush_pending_stroke_position()
	if not _stroke_active or _relief_hold_center == Model.INVALID_CELL:
		return
	if not Rect2(Vector2.ZERO, _viewport_container.size).has_point(
		_viewport_container.get_local_mouse_position()
	):
		return
	var tool_id := _selected_tool_id()
	if not _is_relief_tool(tool_id):
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
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and is_instance_valid(_selection_panel) and (_selection_panel.active or _selection_panel.busy()):
			if _selection_panel.busy():
				_selection_panel.cancel_search()
			else:
				_selection_panel.set_active(false)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and _picking_color:
			_set_color_pick(false)
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
			_flush_pending_stroke_position()
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


func _open_surface_unchecked(
	resource: EmberVoxelModelResource, resource_path: String,
	initial_region_blocks := Rect2i(),
) -> void:
	_disconnect_resource()
	_cancel_ramp_anchor(false)
	_region_select_button.set_pressed_no_signal(false)
	_region_anchor_block = Vector2i(-1, -1)
	_region_preview_blocks = Rect2i()
	_resource = resource
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
	_rebuild_visual()
	_rebuild_region_overlay()
	_update_region_label(_edit_region_blocks)
	if restored_view:
		_update_camera()
		_sync_camera_controls()
	else:
		_fit_camera_to_surface(false)
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
			or _resource.palette != _saved_palette
			or _resource.transparency != _saved_transparency
			or _resource.surface_fill_levels != _saved_surface_fill_levels
			or _resource.surface_fill_materials != _saved_surface_fill_materials
			or _resource.surface_fill_palette != _saved_surface_fill_palette
			or _resource.voxel_groups != _saved_voxel_groups
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
	if _resource == null or _view_store == null:
		return
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
	if is_instance_valid(_groups_panel):
		_groups_panel.cancel_isolation()
	if _resource == null:
		return
	_resource.voxels = _saved_voxels.duplicate()
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

	var header := HBoxContainer.new()
	header.name = "VoxelSculptHeader"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 6)
	root.add_child(header)
	_title = Label.new()
	_title.text = "SURFACE CANVAS · STYLE PILOT"
	_title.modulate = Color(0.96, 0.72, 0.32)
	_title.add_theme_font_size_override("font_size", 14)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_title)
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
	header.add_child(_view_menu)
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
	header.add_child(_surface_layer_view)
	_play_owner_button = Button.new()
	_play_owner_button.name = "PlayVoxelSurfaceOwner"
	_play_owner_button.text = "▶ Играть карту"
	_play_owner_button.tooltip_text = "Сохранить Surface и запустить связанную world-сцену."
	_play_owner_button.visible = false
	_play_owner_button.pressed.connect(_play_owner_scene)
	header.add_child(_play_owner_button)
	var save := Button.new()
	save.name = "SaveVoxelSurfacePilot"
	save.text = "Сохранить"
	save.tooltip_text = "Сохранить текущую Surface в её Godot Resource."
	save.pressed.connect(_save)
	header.add_child(save)

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
		_radius.add_item("Кисть %d" % value)
		_radius.set_item_metadata(_radius.item_count - 1, value)
	_radius.select(2)
	tool_settings.add_child(_radius)
	_volume_operation = OptionButton.new()
	_volume_operation.name = "VoxelSculptVolumeOperation"
	_volume_operation.tooltip_text = "Одна кисть объёма: добавить перед гранью или снять видимые воксели."
	_volume_operation.add_item("Операция · добавить")
	_volume_operation.set_item_metadata(0, Model.TOOL_ADD)
	_volume_operation.add_item("Операция · убрать")
	_volume_operation.set_item_metadata(1, Model.TOOL_REMOVE)
	_volume_operation.item_selected.connect(_on_brush_profile_changed)
	tool_settings.add_child(_volume_operation)
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
	_coarse = CheckBox.new()
	_coarse.name = "VoxelSculptCoarse"
	_coarse.text = "Крупно 2×2×2"
	_coarse.tooltip_text = "Один legacy-воксель равен 2×2×2 новой 32-grid сетки."
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

	var split := HSplitContainer.new()
	split.name = "VoxelSculptMainSplit"
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 1050
	root.add_child(split)
	var canvas_area := HBoxContainer.new()
	canvas_area.name = "VoxelSculptCanvasArea"
	canvas_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_area.add_theme_constant_override("separation", 6)
	split.add_child(canvas_area)

	var tool_rail := VBoxContainer.new()
	tool_rail.name = "VoxelSculptToolRail"
	tool_rail.custom_minimum_size.x = 205.0
	tool_rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tool_rail.add_theme_constant_override("separation", 5)
	canvas_area.add_child(tool_rail)
	var tools_heading := Label.new()
	tools_heading.text = "ИНСТРУМЕНТЫ"
	tools_heading.modulate = Color(0.60, 0.82, 0.94)
	tool_rail.add_child(tools_heading)
	_tool = ItemList.new()
	_tool.name = "VoxelSculptTool"
	_tool.select_mode = ItemList.SELECT_SINGLE
	_tool.max_columns = 1
	_tool.same_column_width = true
	_tool.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tool.custom_minimum_size = Vector2(205.0, 260.0)
	for entry in [
		["▧ Объём", Model.TOOL_ADD],
		["▣ Красить", Model.TOOL_PAINT],
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
	tool_rail.add_child(_tool)
	var rail_hint := Label.new()
	rail_hint.text = "LMB — применить\nRMB — вращать\nMMB — сдвинуть"
	rail_hint.modulate = Color(0.54, 0.64, 0.74)
	tool_rail.add_child(rail_hint)
	canvas_area.add_child(VSeparator.new())

	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "VoxelSculptViewportContainer"
	_viewport_container.custom_minimum_size = Vector2(420.0, 360.0)
	_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_container.focus_mode = Control.FOCUS_ALL
	# Own the render-target dimensions explicitly. During main-screen relayout a
	# stretched SubViewportContainer can briefly report a huge intermediate size,
	# which asks Vulkan for a texture above the device limit.
	_viewport_container.stretch = false
	_viewport_container.resized.connect(_sync_viewport_size)
	_viewport_container.gui_input.connect(_on_viewport_input)
	canvas_area.add_child(_viewport_container)
	_build_viewport()

	var sidebar_scroll := ScrollContainer.new()
	sidebar_scroll.name = "VoxelSculptSidebarScroll"
	sidebar_scroll.custom_minimum_size.x = 280.0
	sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sidebar_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(sidebar_scroll)
	var sidebar := VBoxContainer.new()
	sidebar.name = "VoxelSculptSidebar"
	sidebar.custom_minimum_size.x = 272.0
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_constant_override("separation", 8)
	sidebar_scroll.add_child(sidebar)
	var heading := Label.new()
	heading.text = "АКТИВНЫЙ ИНСТРУМЕНТ"
	heading.modulate = Color(0.60, 0.82, 0.94)
	sidebar.add_child(heading)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(_info)
	sidebar.add_child(HSeparator.new())
	_palette_panel = PalettePanel.new()
	_palette_panel.color_selected.connect(_select_palette_color)
	_palette_panel.operation_requested.connect(_apply_palette_operation)
	_palette_panel.pick_requested.connect(_toggle_color_pick)
	_palette_panel.editing_started.connect(_finish_palette_gesture)
	sidebar.add_child(_palette_panel)
	sidebar.add_child(HSeparator.new())
	_selection_panel = SelectionPanel.new()
	_selection_panel.activation_requested.connect(_toggle_voxel_selection)
	_selection_panel.paint_requested.connect(_paint_voxel_selection)
	_selection_panel.selection_changed.connect(func(has_selection: bool) -> void: _groups_panel.set_can_create(has_selection))
	sidebar.add_child(_selection_panel)
	sidebar.add_child(HSeparator.new())
	_groups_panel = GroupsPanel.new()
	_groups_panel.operation_requested.connect(_apply_group_operation)
	_groups_panel.select_requested.connect(_select_group_members)
	_groups_panel.isolate_requested.connect(_set_group_isolation)
	_groups_panel.visibility_requested.connect(_set_hidden_group_indices)
	sidebar.add_child(_groups_panel)
	sidebar.add_child(HSeparator.new())
	_slice_control = SliceControl.new()
	_slice_control.change_requested.connect(_on_height_slice_changed)
	sidebar.add_child(_slice_control)
	sidebar.add_child(HSeparator.new())
	var region_heading := Label.new()
	region_heading.text = "РАБОЧАЯ ОБЛАСТЬ"
	region_heading.modulate = Color(0.60, 0.82, 0.94)
	sidebar.add_child(region_heading)
	_region_label = Label.new()
	_region_label.name = "VoxelSculptRegionLabel"
	_region_label.text = "Область: вся"
	_region_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_region_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sidebar.add_child(_region_label)
	_region_select_button = Button.new()
	_region_select_button.name = "VoxelSculptRegionSelect"
	_region_select_button.text = "Выделить участок"
	_region_select_button.toggle_mode = true
	_region_select_button.tooltip_text = (
		"Два клика задают прямоугольную маску. Поверхность остаётся общей, "
		+ "но кисти не меняют контекст за границей участка."
	)
	_region_select_button.toggled.connect(_on_region_select_toggled)
	sidebar.add_child(_region_select_button)
	var whole_region := Button.new()
	whole_region.name = "VoxelSculptWholeRegion"
	whole_region.text = "Использовать всю поверхность"
	whole_region.pressed.connect(_use_whole_region)
	sidebar.add_child(whole_region)
	sidebar.add_child(HSeparator.new())
	var resource_heading := Label.new()
	resource_heading.text = "РЕСУРС"
	resource_heading.modulate = Color(0.60, 0.82, 0.94)
	sidebar.add_child(resource_heading)
	_resource_path_label = Label.new()
	_resource_path_label.text = Model.PILOT_PATH
	_resource_path_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_resource_path_label.modulate = Color(0.54, 0.64, 0.74)
	sidebar.add_child(_resource_path_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(spacer)
	_reset_button = Button.new()
	_reset_button.name = "ResetVoxelSurfacePilot"
	_reset_button.text = "Сбросить тестовый холст"
	_reset_button.tooltip_text = "Только для встроенного pilot Resource. Ctrl+Z отменяет."
	_reset_button.pressed.connect(_reset_pilot)
	sidebar.add_child(_reset_button)

	_status = Label.new()
	_status.name = "VoxelSculptStatus"
	_status.custom_minimum_size.y = 30.0
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(0.66, 0.74, 0.84)
	root.add_child(_status)
	_build_camera_popup()
	_on_tool_selected(0)


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
	_camera_pitch_control = _camera_spin("VoxelSurfaceCameraPitch", "Наклон", -78.0, -18.0, 1.0, "°", panel)
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
	if largest > MAX_VIEWPORT_DIMENSION:
		var factor := float(MAX_VIEWPORT_DIMENSION) / float(largest)
		requested = Vector2i(
			maxi(1, floori(float(requested.x) * factor)),
			maxi(1, floori(float(requested.y) * factor)),
		)
	if _viewport.size != requested:
		_viewport.size = requested


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
	_selection_panel.set_active(false)
	var active := not _picking_color
	_finish_palette_gesture()
	_set_color_pick(active and _resource != null)


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
	_set_color_pick(false)
	_set_status("Цвет взят с вокселя · теперь можно рисовать")


func _toggle_voxel_selection() -> void:
	var active: bool = not _selection_panel.active
	_finish_palette_gesture()
	_cancel_region_selection()
	_cancel_ramp_anchor(false)
	_selection_panel.set_active(active)


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
	if _resource == null:
		_displayed_groups = []
		_locked_indices.clear()
		_groups_panel.sync([], "")
		return
	_displayed_groups = _resource.voxel_groups.duplicate(true)
	_locked_indices = Groups.locked_indices(_resource.voxel_groups)
	_groups_panel.sync(_resource.voxel_groups, preferred_id)
	_groups_panel.set_can_create(not _selection_panel.selected.is_empty())


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
		if button.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = button.pressed
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = button.pressed
			accept_event()
			return
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_ortho_size = maxf(1.5, _ortho_size * 0.88)
			_update_camera()
			_sync_camera_controls()
			accept_event()
			return
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_ortho_size = minf(128.0, _ortho_size * 1.12)
			_update_camera()
			_sync_camera_controls()
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_LEFT and _picking_color:
			if button.pressed:
				_pick_palette_color(button.position)
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_LEFT and _selection_panel.active:
			if button.pressed:
				var pick := _pick_at(button.position)
				if pick.has("hit"):
					_selection_panel.choose(pick["hit"], button.shift_pressed, button.ctrl_pressed)
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
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_begin_stroke(button.position)
			else:
				_flush_pending_stroke_position()
				_finish_stroke()
			accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _panning:
			_pan_camera(motion.relative)
		elif _orbiting:
			_yaw -= motion.relative.x * 0.008
			_pitch = clampf(_pitch - motion.relative.y * 0.008, deg_to_rad(-78.0), deg_to_rad(-18.0))
			_update_camera()
			_sync_camera_controls()
		elif _stroke_active and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			# Mouse devices can emit many events between editor frames. Keep only
			# the newest endpoint; line_cells() fills the path from the last
			# processed point, preserving a continuous stroke without event bursts.
			_pending_stroke_position = motion.position
			_has_pending_stroke_position = true
		else:
			_update_cursor(motion.position)


func _pick_at(position: Vector2) -> Dictionary:
	if _resource == null or _camera == null or _viewport == null:
		return {}
	var scale := Vector2(_viewport.size) / _viewport_container.size.max(Vector2.ONE)
	var viewport_position := position * scale
	return Model.pick(
		_isolation_resource if _isolation_resource != null else _resource,
		_camera.project_ray_origin(viewport_position),
		_camera.project_ray_normal(viewport_position),
		_slice_height,
	)


func _target_cell(pick: Dictionary) -> Vector3i:
	var tool_id := _selected_tool_id()
	var cell: Vector3i = (
		pick.get("adjacent", Model.INVALID_CELL)
		if tool_id == Model.TOOL_ADD
		else pick.get("hit", Model.INVALID_CELL)
	)
	return cell if _cell_in_edit_region(cell) else Model.INVALID_CELL


func _on_region_select_toggled(active: bool) -> void:
	if active:
		_selection_panel.set_active(false)
	_cancel_stroke()
	_cancel_ramp_anchor(false)
	_region_anchor_block = Vector2i(-1, -1)
	_region_preview_blocks = Rect2i()
	_rebuild_region_overlay()
	if active:
		_set_status("Выделение участка: кликните первый угол · Esc отменяет")
	else:
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


func _on_tool_selected(_index: int) -> void:
	if is_instance_valid(_selection_panel):
		_selection_panel.set_active(false)
	_flush_pending_stroke_position()
	_finish_stroke()
	_cancel_ramp_anchor(false)
	var tool_id := _selected_tool_id()
	var base_tool := _selected_base_tool_id()
	_selection_panel.set_tool_support(BrushProfiles.mask_kind(tool_id))
	_volume_operation.visible = base_tool == Model.TOOL_ADD
	_relief_direction.visible = base_tool == Model.TOOL_RAISE
	_relief_geometry.visible = base_tool == Model.TOOL_RAISE
	var relief := _is_relief_tool(tool_id)
	_height_limit.visible = relief
	_buildup_rate.visible = relief
	_smooth_strength.visible = _is_smooth_tool(tool_id)
	var material_tool := _is_material_tool(tool_id)
	var surface_fill_tool := _is_surface_fill_tool(tool_id)
	_palette.visible = not material_tool and not surface_fill_tool
	_palette.disabled = tool_id == Model.TOOL_LOWER
	_material_preset.visible = material_tool
	_material_scope.visible = material_tool
	_surface_fill_material.visible = surface_fill_tool
	_update_surface_fill_controls()
	_update_material_scope_controls()
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
	return (
		int(_tool.get_item_metadata(selected[0]))
		if not selected.is_empty()
		else Model.TOOL_ADD
	)


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


func _activate_tool_id(tool_id: int) -> bool:
	## Compatibility entry for tests and editor commands while the rail exposes
	## compact families instead of every concrete backend operation.
	var base_tool := BrushProfiles.base_tool(tool_id)
	var item := _find_tool_item(base_tool)
	if item < 0:
		return false
	if base_tool == Model.TOOL_ADD:
		_select_option_metadata(_volume_operation, tool_id)
	elif base_tool == Model.TOOL_RAISE:
		_select_option_metadata(
			_relief_direction,
			-1 if tool_id in [Model.TOOL_LOWER, Model.TOOL_SHELL_LOWER] else 1,
		)
		_select_option_metadata(
			_relief_geometry,
			"shell" if tool_id in [Model.TOOL_SHELL_RAISE, Model.TOOL_SHELL_LOWER] else "solid",
		)
	_tool.select(item)
	_on_tool_selected(item)
	return true


func _select_option_metadata(option: OptionButton, value: Variant) -> void:
	for item in option.item_count:
		if option.get_item_metadata(item) == value:
			option.select(item)
			return


func _update_tool_help(tool_id: int) -> void:
	if not is_instance_valid(_info):
		return
	var title := "Объём · добавить"
	var help := "Добавляет материал перед видимой гранью. Протяните LMB; один жест отменяется одним Ctrl+Z."
	match tool_id:
		Model.TOOL_REMOVE:
			title = "Объём · убрать"
			help = "Снимает видимые воксели кистью. Esc отменяет текущий жест."
		Model.TOOL_PAINT:
			title = "Красить"
			help = "Меняет цвет существующей формы без изменения её объёма."
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
			title = "Рельеф · вверх · сплошной"
			help = "Удерживайте LMB: холм растёт с выбранной скоростью до заданного предела."
		Model.TOOL_SHELL_RAISE:
			title = "Рельеф · вверх · оболочка"
			help = "Поднимает верх и открытые стенки, не заполняя скрытый объём под горой."
		Model.TOOL_LOWER:
			title = "Рельеф · вниз · сплошной"
			help = "Удерживайте LMB: поверхность опускается с выбранной скоростью до предела."
		Model.TOOL_SHELL_LOWER:
			title = "Рельеф · вниз · оболочка"
			help = "Опускает верх полой формы и перестраивает только видимые стенки впадины."
		Model.TOOL_LEVEL:
			title = "Выровнять площадку"
			help = "Берёт высоту первой точки и протягивает одну плоскость до отпускания LMB."
		Model.TOOL_SMOOTH:
			title = "Сгладить ступени"
			help = "Приближает колонки к высоте соседей не больше выбранной силы за один жест."
		Model.TOOL_RAMP:
			title = "Склон A → B"
			help = "Первый клик ставит A, второй соединяет реальные высоты цельным проходом. Esc отменяет A."
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
	_stroke_heightfield = PackedInt32Array()
	if _is_smooth_tool(tool_id):
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


func _flush_pending_stroke_position() -> void:
	if not _stroke_active or not _has_pending_stroke_position:
		return
	var position := _pending_stroke_position
	_has_pending_stroke_position = false
	_extend_stroke(position)


func _extend_stroke(position: Vector2) -> bool:
	var pick := _pick_at(position)
	if pick.is_empty():
		_relief_hold_center = Model.INVALID_CELL
		if _last_stroke_cell == Model.INVALID_CELL:
			_set_status("Кисть не попала в Surface Canvas", true)
		return false
	var center := _target_cell(pick)
	if center == Model.INVALID_CELL:
		_relief_hold_center = Model.INVALID_CELL
		if _last_stroke_cell == Model.INVALID_CELL:
			_set_status("Для наращивания нужна свободная грань внутри холста", true)
		return false
	var tool_id := _selected_tool_id()
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
	if _is_level_tool(tool_id):
		if _stroke_level_target_y < 0:
			_stroke_level_target_y = center.y
		_relief_hold_center = Model.INVALID_CELL
		return _apply_level_segment(segment_from, center)
	if _is_smooth_tool(tool_id):
		_relief_hold_center = Model.INVALID_CELL
		return _apply_smooth_segment(segment_from, center)
	if _is_relief_tool(tool_id):
		if (
			_relief_hold_center == Model.INVALID_CELL
			or _relief_hold_center.x != center.x
			or _relief_hold_center.z != center.z
		):
			_relief_hold_center = center
			var applied := _apply_relief_segment(segment_from, center, 1)
			var center_key := Vector2i(center.x, center.z)
			var size := _resource.grid_size()
			var column_index := center.x + center.z * size.x
			_relief_applied_height = maxi(
				1,
				maxi(
					int(_stroke_relief_center_height_cache.get(center_key, 1)),
					int(_stroke_relief_amount_cache.get(column_index, 1)),
				),
			)
			_stroke_relief_center_height_cache[center_key] = _relief_applied_height
			var rate := float(_buildup_rate.get_item_metadata(_buildup_rate.selected))
			_relief_hold_elapsed = float(_relief_applied_height - 1) / maxf(0.01, rate)
			return applied
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


func _apply_material_center(center: Vector3i, dirty: Dictionary) -> void:
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
		indices = Model.material_stroke_indices(
			_resource, center, radius, _coarse.button_pressed
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
	_queue_visual_rebuild(dirty_indices, _is_relief_tool(tool_id))
	var change_count := (
		_stroke_material_changes.size() if _is_material_tool(tool_id) else _stroke_changes.size()
	)
	var message := "Мазок: %d art voxels · отпустите LMB · Esc отменяет жест" % change_count
	if _is_relief_tool(tool_id):
		var height_limit := int(_height_limit.get_item_metadata(_height_limit.selected))
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
		message = "Сглаживание: сила %d vox · %d изменений · Esc отменяет" % [
			strength, _stroke_changes.size(),
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
		_selection_panel.preserve_next_source_change()
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
	_stroke_heightfield = PackedInt32Array()
	_last_stroke_cell = Model.INVALID_CELL
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
	if _resource == null or _cursor == null or not is_visible_in_tree():
		return
	var pick := _pick_at(position)
	if pick.is_empty():
		_cursor.visible = false
		return
	var cell := _target_cell(pick)
	if cell == Model.INVALID_CELL or not Model.contains(cell, _resource.grid_size()):
		_cursor.visible = false
		return
	var density := float(_resource.normalized_density())
	var radius := int(_radius.get_item_metadata(_radius.selected)) if _radius.selected >= 0 else 1
	var span := maxi(2 if _coarse.button_pressed else 1, radius * 2 - 1)
	var tool_id := _selected_tool_id()
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
	var right := _camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var forward := -_camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var world_per_pixel := _ortho_size / maxf(320.0, _viewport_container.size.y)
	var target_y := _camera_target.y
	_camera_target += (
		-right * relative.x + forward * relative.y
	) * world_per_pixel
	_camera_target.y = target_y
	_update_camera()


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
	_pitch = deg_to_rad(-78.0)
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
	if _resource_path == Model.PILOT_PATH and _resource != null and _actions.reset_pilot(_resource):
		_set_status("Пилот сброшен · НЕ СОХРАНЕНО · Ctrl+Z отменяет", false, Color(1.0, 0.72, 0.30))


func _save() -> bool:
	_flush_pending_stroke_position()
	_finish_stroke()
	if _resource == null:
		return false
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
	if _editor_interface != null:
		_editor_interface.get_resource_filesystem().scan()
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


func _disconnect_resource() -> void:
	_remember_current_editor_view()
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


func _set_status(message: String, error := false, color := Color(0.66, 0.74, 0.84)) -> void:
	if is_instance_valid(_title) and _resource != null:
		_title.text = "SURFACE CANVAS · %s%s" % [
			_resource.display_name.to_upper(), " *" if has_unsaved_changes() else ""
		]
	var actual_color := Color(1.0, 0.45, 0.40) if error else color
	if _status != null:
		_status.text = message
		_status.modulate = actual_color
	status_changed.emit(message, actual_color)
