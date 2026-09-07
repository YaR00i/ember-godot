@tool
extends EditorPlugin

const EmberToolsDock = preload("res://addons/ember_import/ember_tools_dock.gd")
const EmberVoxelPropGizmo = preload("res://addons/ember_import/ember_voxel_prop_gizmo.gd")
const EmberStandaloneTriggerGizmo = preload("res://addons/ember_import/ember_standalone_trigger_gizmo.gd")
const EmberObjectInspector = preload("res://addons/ember_import/ember_object_inspector_plugin.gd")
const EmberCameraRigInspector = preload("res://addons/ember_import/ember_camera_rig_inspector_plugin.gd")
const EmberBattlefieldInspector = preload("res://addons/ember_import/ember_battlefield_inspector_plugin.gd")
const EmberVoxelSurfaceInspector = preload("res://addons/ember_import/ember_voxel_surface_inspector_plugin.gd")
const EmberVoxelSurfaceInspectorPanel = preload("res://addons/ember_import/ember_voxel_surface_inspector_panel.gd")
const EmberBattlefieldTileLibraryInspector = preload("res://addons/ember_import/ember_battlefield_tile_library_inspector_plugin.gd")
const EmberEncounterInspector = preload("res://addons/ember_import/ember_encounter_inspector_plugin.gd")
const EmberBattlefieldActions = preload("res://addons/ember_import/ember_battlefield_editor_actions.gd")
const EmberBattlefieldPainter = preload("res://addons/ember_import/ember_battlefield_3d_painter.gd")
const EmberWorldSurfaceSelectorScript = preload("res://addons/ember_import/ember_world_surface_selector.gd")
const EmberVoxelSculptModel = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const EmberInspectorActions = preload("res://addons/ember_import/ember_object_inspector_actions.gd")
const EmberGraphWorkspace = preload("res://addons/ember_import/ember_graph_workspace.gd")
const COMBAT_LAB_SCENE := "res://scenes/combat_lab.tscn"
const COMBAT_ARENA_E2_SCENE := "res://scenes/combat/arenas/colored_crossing.tscn"
const COMBAT_ARENA_E3_SCENE := "res://scenes/combat/arenas/thaw_keeper.tscn"
const SURFACE_MAIN_SCREEN := "Surface Canvas"
const SURFACE_WORKSPACE_NODE := "EmberSurfaceCanvasWorkspace"
const GRAPH_LAYOUT_SECTION := "EmberGraph"
const GRAPH_LAYOUT_WORKSPACE := "workspace_layout"

var _dock: VBoxContainer
var _confirm: ConfirmationDialog
var _voxel_gizmo: EditorNode3DGizmoPlugin
var _trigger_gizmo: EditorNode3DGizmoPlugin
var _object_inspector: EditorInspectorPlugin
var _camera_rig_inspector: EditorInspectorPlugin
var _battlefield_inspector: EditorInspectorPlugin
var _voxel_surface_inspector: EditorInspectorPlugin
var _battlefield_tile_library_inspector: EditorInspectorPlugin
var _encounter_inspector: EditorInspectorPlugin
var _battlefield_paint_actions: EmberBattlefieldEditorActions
var _battlefield_painter: EmberBattlefield3DPainter
var _battlefield_toolbar: Control
var _world_surface_selector: RefCounted
var _world_surface_toolbar: Control
var _interact_actions: EmberObjectInspectorActions
var _graph_workspace: EmberGraphWorkspace
var _last_selected_voxel: EmberVoxelProp
var _last_selected_trigger: EmberInteract


func _enter_tree() -> void:
	_configure_fullscreen_playtest()
	add_tool_menu_item("Ember: Reimport map from pack…", _ask_reimport)
	add_tool_menu_item("Ember: Open Combat Lab", _open_combat_lab)
	add_tool_menu_item("Ember: Open Combat Content", _open_combat_content)
	add_tool_menu_item("Ember: Open Loot Library", _open_loot_library)
	add_tool_menu_item("Ember: Run Combat Lab", _run_combat_lab)
	add_tool_menu_item("Ember: Open Battle Arena · E2", _open_combat_arena_e2)
	add_tool_menu_item("Ember: Open Battle Arena · E3", _open_combat_arena_e3)
	_voxel_gizmo = EmberVoxelPropGizmo.new()
	add_node_3d_gizmo_plugin(_voxel_gizmo)
	_trigger_gizmo = EmberStandaloneTriggerGizmo.new()
	add_node_3d_gizmo_plugin(_trigger_gizmo)
	_dock = EmberToolsDock.new()
	# Keep this identity distinct from the legacy right-slot dock name "Ember".
	# Godot restores dock placement by Control.name from editor_layout.cfg.
	_dock.name = "EmberMigrationWorkflow"
	_dock.reimport_requested.connect(_ask_reimport)
	_dock.duplicate_requested.connect(_duplicate_voxel_prop)
	_dock.standalone_trigger_requested.connect(_create_standalone_trigger)
	_dock.voxel_prop_requested.connect(_create_voxel_prop)
	_dock.voxel_migrate_requested.connect(_migrate_voxel_from_library)
	_dock.voxel_batch_migrate_requested.connect(_migrate_voxel_batch_from_dashboard)
	_dock.close_requested.connect(_close_migration_panel)
	add_control_to_bottom_panel(_dock, "Ember Migration")
	_interact_actions = EmberInspectorActions.new()
	_interact_actions.configure(get_undo_redo())
	_interact_actions.scene_binding_changed.connect(_on_scene_binding_changed)
	_interact_actions.voxel_model_changed.connect(_on_voxel_model_changed)
	_graph_workspace = EmberGraphWorkspace.new()
	_graph_workspace.name = "EmberGraphWorkspace"
	_graph_workspace.configure(get_editor_interface(), get_undo_redo())
	_graph_workspace.action_save_requested.connect(_save_action_script_from_graph)
	_graph_workspace.action_migrate_requested.connect(_migrate_action_script_from_graph)
	_graph_workspace.dialogue_save_requested.connect(_save_dialogue_from_graph)
	_graph_workspace.dialogue_migrate_requested.connect(_migrate_dialogue_from_graph)
	_graph_workspace.quest_save_requested.connect(_save_quest_from_graph)
	_graph_workspace.shop_save_requested.connect(_save_shop_from_editor)
	_graph_workspace.shop_migrate_requested.connect(_migrate_shop_from_editor)
	_graph_workspace.item_save_requested.connect(_save_item_from_editor)
	_graph_workspace.item_migrate_requested.connect(_migrate_item_from_editor)
	_graph_workspace.scene_node_requested.connect(_select_graph_scene_node)
	_graph_workspace.quest_event_bind_requested.connect(_bind_graph_quest_event)
	_graph_workspace.quest_event_unbind_requested.connect(_unbind_graph_quest_event)
	_graph_workspace.quest_event_remove_requested.connect(_remove_graph_quest_event)
	EditorInterface.get_editor_main_screen().add_child(_graph_workspace)
	_graph_workspace.set_scene_root(EditorInterface.get_edited_scene_root())
	_make_visible(false)
	_object_inspector = EmberObjectInspector.new()
	_object_inspector.configure(
		_rebuild_from_inspector,
		_save_interact_from_inspector,
		_remove_interact_from_inspector,
		_save_chain_from_inspector,
		_remove_chain_from_inspector,
		_save_standalone_from_inspector,
		_remove_standalone_from_inspector,
		_save_standalone_chain_from_inspector,
		_remove_standalone_chain_from_inspector,
		_save_standalone_bounds_from_inspector,
		_save_dialogue_from_inspector,
		_save_shop_from_editor,
		_migrate_shop_from_editor,
		_save_item_from_editor,
		_migrate_item_from_editor,
		_save_quest_from_inspector,
	)
	add_inspector_plugin(_object_inspector)
	_camera_rig_inspector = EmberCameraRigInspector.new()
	_camera_rig_inspector.configure(get_editor_interface())
	add_inspector_plugin(_camera_rig_inspector)
	_battlefield_inspector = EmberBattlefieldInspector.new()
	_battlefield_inspector.configure(get_undo_redo())
	add_inspector_plugin(_battlefield_inspector)
	_voxel_surface_inspector = EmberVoxelSurfaceInspector.new()
	_voxel_surface_inspector.configure(get_editor_interface(), _open_surface_from_inspector)
	add_inspector_plugin(_voxel_surface_inspector)
	_battlefield_tile_library_inspector = EmberBattlefieldTileLibraryInspector.new()
	add_inspector_plugin(_battlefield_tile_library_inspector)
	_encounter_inspector = EmberEncounterInspector.new()
	_encounter_inspector.configure(get_editor_interface(), get_undo_redo())
	add_inspector_plugin(_encounter_inspector)
	_battlefield_paint_actions = EmberBattlefieldActions.new() as EmberBattlefieldEditorActions
	_battlefield_paint_actions.configure(get_undo_redo())
	_battlefield_painter = EmberBattlefieldPainter.new() as EmberBattlefield3DPainter
	_battlefield_painter.configure(self, get_editor_interface(), _battlefield_paint_actions)
	_battlefield_painter.surface_edit_requested.connect(_open_battlefield_surface)
	_battlefield_toolbar = _battlefield_painter.build_toolbar()
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _battlefield_toolbar)
	_world_surface_selector = EmberWorldSurfaceSelectorScript.new()
	_world_surface_selector.configure(self, get_editor_interface())
	_world_surface_selector.surface_edit_requested.connect(_open_world_surface)
	_world_surface_toolbar = _world_surface_selector.build_toolbar()
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _world_surface_toolbar)
	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()
	print("[Ember Migration] v2.64.1 loaded: staged combat command selection")
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Полный reimport Ember-карты"
	_confirm.dialog_text = "Look / Terrain / Props / Regions будут пересозданы из pack.\nРучные позиции и вложенные правки сцены будут потеряны."
	_confirm.ok_button_text = "Переимпортировать и сохранить"
	_confirm.confirmed.connect(_reimport_and_save)
	add_child(_confirm)
	if not scene_changed.is_connected(_on_scene_changed):
		scene_changed.connect(_on_scene_changed)
	var selection := EditorInterface.get_selection()
	if selection and not selection.selection_changed.is_connected(_refresh_voxel_gizmos):
		selection.selection_changed.connect(_refresh_voxel_gizmos)
	_refresh_voxel_gizmos()


func _configure_fullscreen_playtest() -> void:
	# Godot cannot change window mode while the game is embedded in the editor.
	# Ember battles deliberately use fullscreen, so keep playtests in a normal
	# game process. Headless gates must never mutate a developer's editor prefs.
	if DisplayServer.get_name() == "headless":
		return
	var settings := EditorInterface.get_editor_settings()
	if int(settings.get_setting("run/window_placement/game_embed_mode")) != -1:
		settings.set_setting("run/window_placement/game_embed_mode", -1)


func _exit_tree() -> void:
	remove_tool_menu_item("Ember: Reimport map from pack…")
	remove_tool_menu_item("Ember: Open Combat Lab")
	remove_tool_menu_item("Ember: Open Combat Content")
	remove_tool_menu_item("Ember: Open Loot Library")
	remove_tool_menu_item("Ember: Run Combat Lab")
	remove_tool_menu_item("Ember: Open Battle Arena · E2")
	remove_tool_menu_item("Ember: Open Battle Arena · E3")
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	var selection := EditorInterface.get_selection()
	if selection and selection.selection_changed.is_connected(_refresh_voxel_gizmos):
		selection.selection_changed.disconnect(_refresh_voxel_gizmos)
	if _voxel_gizmo:
		remove_node_3d_gizmo_plugin(_voxel_gizmo)
		_voxel_gizmo = null
	if _trigger_gizmo:
		remove_node_3d_gizmo_plugin(_trigger_gizmo)
		_trigger_gizmo = null
	if _object_inspector:
		remove_inspector_plugin(_object_inspector)
		_object_inspector = null
	if _camera_rig_inspector:
		remove_inspector_plugin(_camera_rig_inspector)
		_camera_rig_inspector = null
	if _battlefield_inspector:
		remove_inspector_plugin(_battlefield_inspector)
		_battlefield_inspector = null
	if _voxel_surface_inspector:
		remove_inspector_plugin(_voxel_surface_inspector)
		_voxel_surface_inspector = null
	if _battlefield_tile_library_inspector:
		remove_inspector_plugin(_battlefield_tile_library_inspector)
		_battlefield_tile_library_inspector = null
	if _encounter_inspector:
		remove_inspector_plugin(_encounter_inspector)
		_encounter_inspector = null
	if _battlefield_painter:
		_battlefield_painter.shutdown()
		_battlefield_painter = null
	if _battlefield_toolbar:
		remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _battlefield_toolbar)
		_battlefield_toolbar.queue_free()
		_battlefield_toolbar = null
	if _world_surface_selector:
		_world_surface_selector.shutdown()
		_world_surface_selector = null
	if _world_surface_toolbar:
		remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _world_surface_toolbar)
		_world_surface_toolbar.queue_free()
		_world_surface_toolbar = null
	_battlefield_paint_actions = null
	if _graph_workspace:
		_graph_workspace.queue_free()
		_graph_workspace = null
	_interact_actions = null
	if _dock:
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
	if _confirm:
		_confirm.queue_free()


func _open_combat_lab() -> void:
	EditorInterface.open_scene_from_path(COMBAT_LAB_SCENE)


func _open_combat_content() -> void:
	EditorInterface.set_main_screen_editor("Ember Graph")
	if _graph_workspace != null:
		_graph_workspace.open_resource("combat_content", "combat_library")


func _open_loot_library() -> void:
	EditorInterface.set_main_screen_editor("Ember Graph")
	if _graph_workspace != null:
		_graph_workspace.open_resource("loot", "")


func _run_combat_lab() -> void:
	if EditorInterface.is_playing_scene():
		EditorInterface.stop_playing_scene()
	EditorInterface.play_custom_scene(COMBAT_LAB_SCENE)


func _open_combat_arena_e2() -> void:
	EditorInterface.open_scene_from_path(COMBAT_ARENA_E2_SCENE)


func _open_combat_arena_e3() -> void:
	EditorInterface.open_scene_from_path(COMBAT_ARENA_E3_SCENE)


func _open_battlefield_surface(field: EmberBattlefieldResource) -> void:
	if field == null or _graph_workspace == null:
		return
	var surface := field.visual_surface
	var surface_path := EmberVoxelSculptModel.surface_save_path(
		surface,
		surface.resource_path if surface != null else "",
	)
	if surface_path.is_empty():
		surface_path = EmberVoxelSculptModel.battle_surface_path(field.field_id)
	if surface != null and not field.visual_surface_matches_field():
		push_warning(
			"Ember Surface: %s имеет размер %dx%d, а поле боя %dx%d. "
			+ "Сохраните старую поверхность и очистите Visual Surface перед созданием новой."
			% [surface.display_name, surface.size_blocks.x, surface.size_blocks.z, field.width, field.height]
		)
		return
	if surface == null and ResourceLoader.exists(surface_path):
		surface = ResourceLoader.load(
			surface_path, "", ResourceLoader.CACHE_MODE_REPLACE
		) as EmberVoxelModelResource
		if surface != null and (
			surface.size_blocks.x != field.width or surface.size_blocks.z != field.height
		):
			surface = null
			surface_path = "%s/%s_surface_%dx%d.tres" % [
				EmberVoxelSculptModel.BATTLE_SURFACE_DIRECTORY,
				field.field_id.to_lower().validate_filename().replace(" ", "_"),
				field.width,
				field.height,
			]
	if surface == null:
		surface = EmberVoxelSculptModel.make_battlefield_surface(
			field.field_id,
			field.display_name,
			field.width,
			field.height,
			field.elevations,
			field.terrain_kinds,
			field.blocked,
		)
		var absolute := ProjectSettings.globalize_path(surface_path)
		DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
		var save_error := ResourceSaver.save(
			surface, surface_path, ResourceSaver.FLAG_CHANGE_PATH
		)
		if save_error != OK:
			push_error("Ember Surface: не удалось создать %s: %s" % [surface_path, error_string(save_error)])
			return
		surface.take_over_path(surface_path)
		get_editor_interface().get_resource_filesystem().scan()
	elif not EmberVoxelSculptModel.is_writable_resource_path(surface.resource_path):
		# v2.19 initially saved the bytes but did not change the in-memory
		# Resource path, so saving Battlefield could embed a second 1–2 MB copy.
		# Externalize the exact current object before opening it again.
		var externalize_error := ResourceSaver.save(
			surface, surface_path, ResourceSaver.FLAG_CHANGE_PATH
		)
		if externalize_error != OK:
			push_error("Ember Surface: не удалось вынести embedded поверхность: %s" % error_string(externalize_error))
			return
		surface.take_over_path(surface_path)
		field.notify_authoring_changed()
		if EmberVoxelSculptModel.is_writable_resource_path(field.resource_path):
			var owner_save_error := ResourceSaver.save(field, field.resource_path)
			if owner_save_error != OK:
				push_error(
					"Ember Surface: внешний файл сохранён, но Battlefield link не обновлён: %s"
					% error_string(owner_save_error)
				)
				return
		get_editor_interface().get_resource_filesystem().scan()
	if field.visual_surface != surface:
		_battlefield_paint_actions.assign_visual_surface(field, surface)
	_open_surface_canvas(surface, surface_path)


func _open_surface_from_inspector(surface: EmberVoxelModelResource) -> void:
	if surface == null:
		return
	if "battlefield" in surface.tags:
		var field_path := EmberVoxelSculptModel.battlefield_resource_path_for_surface(surface)
		var field := load(field_path) as EmberBattlefieldResource if not field_path.is_empty() else null
		if field != null and field.visual_surface == surface:
			_open_battlefield_surface(field)
			return
	var save_path := EmberVoxelSculptModel.surface_save_path(surface, surface.resource_path)
	_open_surface_canvas(surface, save_path if not save_path.is_empty() else surface.resource_path)


func _open_world_surface(map: EmberMapLoader, region_blocks: Rect2i) -> void:
	if map == null or _graph_workspace == null:
		return
	var raw: Variant = EmberPack.parse_json_file(EmberPack.map_path(map.map_id))
	if typeof(raw) != TYPE_DICTIONARY:
		push_warning("Ember Surface: исходная геометрия карты %s не найдена" % map.map_id)
		return
	var map_data := raw as Dictionary
	var grid := EmberTileMesher.surface_grid(map_data)
	var width := int(grid.get("width", 0))
	var depth := int(grid.get("depth", 0))
	if width < 1 or depth < 1:
		push_warning("Ember Surface: карта %s не содержит поверхности" % map.map_id)
		return
	var surface_path := EmberVoxelSculptModel.world_surface_path(map.map_id)
	var surface := map.visual_surface
	if surface == null and ResourceLoader.exists(surface_path):
		surface = ResourceLoader.load(
			surface_path, "", ResourceLoader.CACHE_MODE_REPLACE
		) as EmberVoxelModelResource
	if surface != null and (
		surface.size_blocks.x != width or surface.size_blocks.z != depth
	):
		push_warning(
			"Ember Surface: размер %s — %dx%d, карта — %dx%d. "
			+ "Сохраните старый Resource и очистите Visual Surface перед пересозданием."
			% [surface.display_name, surface.size_blocks.x, surface.size_blocks.z, width, depth]
		)
		return
	if surface == null:
		var display_name := str(map.get_parent().name) if map.get_parent() != null else map.map_id
		surface = EmberVoxelSculptModel.make_world_surface(
			map.map_id,
			display_name,
			grid,
			EmberTileMesher.tileset_colors(str(map_data.get("tilesetId", "village_16"))),
		)
		var absolute := ProjectSettings.globalize_path(surface_path)
		DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
		var save_error := ResourceSaver.save(
			surface, surface_path, ResourceSaver.FLAG_CHANGE_PATH
		)
		if save_error != OK:
			push_error("Ember Surface: не удалось создать %s: %s" % [surface_path, error_string(save_error)])
			return
		surface.take_over_path(surface_path)
		get_editor_interface().get_resource_filesystem().scan()
	elif not EmberVoxelSculptModel.is_writable_resource_path(surface.resource_path):
		var externalize_error := ResourceSaver.save(
			surface, surface_path, ResourceSaver.FLAG_CHANGE_PATH
		)
		if externalize_error != OK:
			push_error("Ember Surface: не удалось вынести embedded поверхность: %s" % error_string(externalize_error))
			return
		surface.take_over_path(surface_path)
		EditorInterface.mark_scene_as_unsaved()
	if map.visual_surface != surface:
		var undo_redo := get_undo_redo()
		undo_redo.create_action("Назначить общую Surface карте %s" % map.map_id)
		undo_redo.add_do_property(map, "visual_surface", surface)
		undo_redo.add_undo_property(map, "visual_surface", map.visual_surface)
		undo_redo.add_do_method(map, "notify_property_list_changed")
		undo_redo.add_undo_method(map, "notify_property_list_changed")
		undo_redo.commit_action()
		EditorInterface.mark_scene_as_unsaved()
	_open_surface_canvas(surface, surface_path, region_blocks)


func _open_surface_canvas(
	surface: EmberVoxelModelResource,
	surface_path: String,
	region_blocks := Rect2i(),
) -> void:
	var main_screen := EditorInterface.get_editor_main_screen()
	var workspace := main_screen.find_child(
		SURFACE_WORKSPACE_NODE, true, false
	) as EmberVoxelSculptWorkspace
	if workspace == null:
		# Keep the old embedded workspace as a recovery path when somebody disables
		# only the thin main-screen adapter in Project Settings.
		push_warning("Ember Surface: отдельная вкладка отключена; открыт резервный workspace в Ember Graph.")
		EditorInterface.set_main_screen_editor("Ember Graph")
		if _graph_workspace != null:
			_graph_workspace.open_voxel_surface(surface, surface_path, region_blocks)
		return
	workspace.open_surface(surface, surface_path, region_blocks)
	EditorInterface.set_main_screen_editor(SURFACE_MAIN_SCREEN)


func _rebuild_from_inspector(prop: EmberVoxelProp) -> void:
	if _dock:
		_dock.rebuild_prop(prop)
		prop.notify_property_list_changed()


func _save_interact_from_inspector(prop: EmberVoxelProp, values: Dictionary) -> void:
	if _interact_actions and not _interact_actions.save(prop, values):
		push_warning("Ember Inspector: Interact save target is no longer valid.")


func _remove_interact_from_inspector(prop: EmberVoxelProp) -> void:
	if _interact_actions and not _interact_actions.remove(prop):
		push_warning("Ember Inspector: Interact remove target is no longer valid.")


func _save_chain_from_inspector(prop: EmberVoxelProp, document: Dictionary) -> void:
	if _interact_actions and not _interact_actions.save_chain(prop, document):
		push_warning("Ember Inspector: action-chain save target or document is invalid.")


func _remove_chain_from_inspector(prop: EmberVoxelProp) -> void:
	if _interact_actions and not _interact_actions.remove_chain(prop):
		push_warning("Ember Inspector: action-chain remove target is no longer valid.")


func _save_standalone_from_inspector(interact: EmberInteract, values: Dictionary) -> void:
	if _interact_actions and not _interact_actions.save_standalone(interact, values):
		push_warning("Ember Inspector: standalone Interact save target is no longer valid.")


func _remove_standalone_from_inspector(interact: EmberInteract) -> void:
	if _interact_actions == null or not _interact_actions.remove_standalone(interact):
		push_warning("Ember Inspector: standalone Interact remove target is no longer valid.")
		return
	var selection := EditorInterface.get_selection()
	if selection:
		selection.clear()
	EditorInterface.mark_scene_as_unsaved()


func _save_standalone_chain_from_inspector(interact: EmberInteract, document: Dictionary) -> void:
	if _interact_actions and not _interact_actions.save_standalone_chain(interact, document):
		push_warning("Ember Inspector: standalone action-chain save failed.")


func _remove_standalone_chain_from_inspector(interact: EmberInteract) -> void:
	if _interact_actions and not _interact_actions.remove_standalone_chain(interact):
		push_warning("Ember Inspector: standalone action-chain remove failed.")


func _save_standalone_bounds_from_inspector(interact: EmberInteract, size: Vector3) -> void:
	if _interact_actions and not _interact_actions.save_standalone_bounds(interact, size):
		push_warning("Ember Inspector: standalone trigger bounds save failed.")


func _save_dialogue_from_inspector(document: Dictionary) -> void:
	if _interact_actions and not _interact_actions.save_dialogue(document):
		push_warning("Ember Inspector: dialogue document is invalid or could not be saved.")


func _save_action_script_from_graph(document: Dictionary) -> void:
	if _interact_actions and not _interact_actions.save_action_script(document, self):
		push_warning("Ember Graph: action document is invalid or could not be saved.")


func _migrate_action_script_from_graph(script_id: String) -> void:
	if _interact_actions and not _interact_actions.migrate_action_script(script_id, self):
		push_warning("Ember Graph: action-chain migration could not be completed.")


func _save_dialogue_from_graph(document: Dictionary) -> void:
	if _interact_actions and not _interact_actions.save_dialogue_graph(document, self):
		push_warning("Ember Graph: dialogue document is invalid or could not be saved.")


func _migrate_dialogue_from_graph(dialogue_id: String) -> void:
	if _interact_actions and not _interact_actions.migrate_dialogue(dialogue_id, self):
		push_warning("Ember Graph: dialogue migration could not be completed.")


func _save_quest_from_graph(document: Dictionary) -> void:
	if _interact_actions and not _interact_actions.save_quest_document(document, self):
		push_warning("Ember Graph: quest document is invalid or could not be saved.")


func _save_shop_from_editor(document: Dictionary) -> void:
	if _interact_actions and not _interact_actions.save_shop(document, self):
		push_warning("Ember shop: document is invalid, still legacy, or could not be saved.")


func _migrate_shop_from_editor(shop_id: String) -> void:
	if _interact_actions and not _interact_actions.migrate_shop(shop_id, self):
		push_warning("Ember shop: migration could not be completed.")


func _save_item_from_editor(document: Dictionary) -> void:
	if _interact_actions and not _interact_actions.save_item(document, self):
		push_warning("Ember item: document is invalid, still legacy, or could not be saved.")


func _migrate_item_from_editor(item_id: String) -> void:
	if _interact_actions and not _interact_actions.migrate_item(item_id, self):
		push_warning("Ember item: migration could not be completed.")


func _save_quest_from_inspector(interact: EmberInteract, document: Dictionary) -> void:
	if _interact_actions and not _interact_actions.save_quest_for_interact(interact, document):
		push_warning("Ember quest: document or quest-marker target is invalid.")


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if _graph_workspace:
		_graph_workspace.visible = visible


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	var world_result: int = (
		_world_surface_selector.forward_3d_gui_input(viewport_camera, event)
		if _world_surface_selector != null
		else EditorPlugin.AFTER_GUI_INPUT_PASS
	)
	if world_result == EditorPlugin.AFTER_GUI_INPUT_STOP:
		return world_result
	return (
		_battlefield_painter.forward_3d_gui_input(viewport_camera, event)
		if _battlefield_painter != null
		else EditorPlugin.AFTER_GUI_INPUT_PASS
	)


func _forward_3d_force_draw_over_viewport(overlay: Control) -> void:
	if _world_surface_selector != null:
		_world_surface_selector.draw_overlay(overlay)
	if _battlefield_painter != null:
		_battlefield_painter.draw_overlay(overlay)


func _get_window_layout(configuration: ConfigFile) -> void:
	if _graph_workspace != null:
		configuration.set_value(
			GRAPH_LAYOUT_SECTION,
			GRAPH_LAYOUT_WORKSPACE,
			_graph_workspace.export_editor_layout(),
		)


func _set_window_layout(configuration: ConfigFile) -> void:
	if _graph_workspace == null:
		return
	var data: Variant = configuration.get_value(
		GRAPH_LAYOUT_SECTION,
		GRAPH_LAYOUT_WORKSPACE,
		{},
	)
	if data is Dictionary:
		_graph_workspace.import_editor_layout(data as Dictionary)


func _get_plugin_name() -> String:
	return "Ember Graph"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("VisualShader", "EditorIcons")


func _select_graph_scene_node(node_path: NodePath) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var interact := root.get_node_or_null(node_path) as EmberInteract
	if interact == null:
		push_warning("Ember Graph: scene backlink no longer exists: %s" % node_path)
		return
	var target: Node = EmberObjectInspectorModel.voxel_owner(interact)
	if target == null:
		target = interact
	var selection := EditorInterface.get_selection()
	if selection != null:
		selection.clear()
		selection.add_node(target)
	EditorInterface.edit_node(target)
	EditorInterface.set_main_screen_editor("3D")


func _bind_graph_quest_event(
	scene_path: NodePath,
	event_token: String,
	quest_document: Dictionary,
) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or _interact_actions == null:
		return
	var target := root.get_node_or_null(scene_path)
	if target == null:
		push_warning("Ember Graph: selected scene object no longer exists: %s" % scene_path)
		return
	if not _interact_actions.bind_quest_event(
		target, event_token, root, quest_document
	):
		push_warning("Ember Graph: quest event could not be bound to %s." % scene_path)
		return
	EditorInterface.mark_scene_as_unsaved()
	_graph_workspace.call_deferred(
		"accept_quest_binding_save",
		"Событие задания привязано к %s · Ctrl+Z отменяет" % str(target.name),
	)


func _unbind_graph_quest_event(scene_path: NodePath, event_entry: Dictionary) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or _interact_actions == null:
		return
	var target := root.get_node_or_null(scene_path)
	if target == null:
		push_warning("Ember Graph: selected scene object no longer exists: %s" % scene_path)
		return
	var result := _interact_actions.unbind_quest_event(target, event_entry, root)
	var message := str(result.get("message", "Событие задания не удалось отвязать."))
	if not bool(result.get("ok", false)):
		push_warning("Ember Graph: %s" % message)
		_graph_workspace.call_deferred("refresh_quest_scene_projection", message)
		return
	EditorInterface.mark_scene_as_unsaved()
	_graph_workspace.call_deferred(
		"refresh_quest_scene_projection",
		"%s · Ctrl+Z отменяет" % message,
	)


func _remove_graph_quest_event(event_entry: Dictionary) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if _interact_actions == null:
		return
	var result := _interact_actions.remove_unbound_quest_event(event_entry, root)
	var message := str(result.get("message", "Лишнее событие не удалось удалить."))
	if not bool(result.get("ok", false)):
		push_warning("Ember Graph: %s" % message)
	_graph_workspace.call_deferred(
		"refresh_quest_scene_projection",
		"%s%s" % [message, " · Ctrl+Z отменяет" if bool(result.get("ok", false)) else ""],
	)


func _on_scene_binding_changed() -> void:
	if _graph_workspace:
		_graph_workspace.call_deferred("refresh_quest_scene_projection")


func _create_standalone_trigger(anchor: Node3D) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or _interact_actions == null:
		return
	var world_position := Vector3.ZERO
	if is_instance_valid(anchor) and (anchor == root or root.is_ancestor_of(anchor)):
		world_position = anchor.global_position
		if anchor is EmberVoxelProp:
			world_position.y += 4.0
	else:
		var start := root.find_child("player_start", true, false) as Node3D
		if start != null:
			world_position = start.global_position
	var interact := _interact_actions.create_standalone_trigger(root, world_position)
	if interact == null:
		if _dock:
			_dock.show_status("Не удалось создать самостоятельную зону.", true)
		return
	var selection := EditorInterface.get_selection()
	if selection:
		selection.clear()
		selection.add_node(interact)
	EditorInterface.mark_scene_as_unsaved()
	if _dock:
		_dock.show_status("Создана %s в AuthoredTriggers. Задайте цепочку и размер в Inspector; Ctrl+Z отменяет." % interact.name)


func _close_migration_panel() -> void:
	hide_bottom_panel()


func _migrate_voxel_from_library(model_id: String) -> void:
	if _interact_actions == null or not _interact_actions.migrate_voxel_model(model_id, self):
		if _dock:
			_dock.show_status("Модель %s уже перенесена или legacy-источник недоступен." % model_id, true)


func _migrate_voxel_batch_from_dashboard(model_ids: Array[String]) -> void:
	if _interact_actions == null or not _interact_actions.migrate_voxel_models(model_ids, self):
		if _dock:
			_dock.show_status("Voxel-партия изменилась или не прошла проверку.", true)
		return
	if _dock:
		_dock.call_deferred("_refresh_content_migration_report")
		_dock.show_status("Перенесено %d voxel-моделей · одна операция Ctrl+Z/Redo." % model_ids.size())


func _on_voxel_model_changed(model_id: String) -> void:
	if _dock:
		_dock.call_deferred("accept_voxel_migration_change", model_id)


func _create_voxel_prop(model_id: String, anchor: Node3D) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var map := root.find_child("Map", true, false) as EmberMapLoader
	var props := map.get_node_or_null("Props") if map != null else null
	if map == null or props == null:
		if _dock:
			_dock.show_status("Не найден контейнер Map/Props.", true)
		return
	var tile_size := map.imported_tile_size if map.imported_tile_size > 0.0 else 16.0
	var prefab_path := EmberVoxelPrefab.prefab_path(model_id)
	var packed := ResourceLoader.load(
		prefab_path,
		"",
		ResourceLoader.CACHE_MODE_REPLACE,
	) as PackedScene if ResourceLoader.exists(prefab_path) else null
	var report := EmberVoxelPrefab.validate_packed(model_id, packed)
	if packed == null or not bool(report.get("ok", false)):
		var stats := {}
		EmberVoxelPrefab.begin_import()
		packed = EmberVoxelPrefab.ensure_saved(model_id, tile_size, stats)
	if packed == null:
		if _dock:
			_dock.show_status("Prefab %s не собран: проверьте voxel-исходник." % model_id, true)
		return
	report = EmberVoxelPrefab.validate_packed(model_id, packed)
	if not bool(report.get("ok", false)):
		if _dock:
			_dock.show_status("Prefab %s не прошёл проверку: %s" % [model_id, "; ".join(report.get("errors", []))], true)
		return
	var world_position := Vector3.ZERO
	if is_instance_valid(anchor) and (anchor == root or root.is_ancestor_of(anchor)):
		world_position = anchor.global_position + Vector3(tile_size, 0.0, 0.0)
	else:
		var start := root.find_child("player_start", true, false) as Node3D
		if start != null:
			world_position = start.global_position
	var prop := EmberSceneAuthoring.make_model_instance(
		root,
		packed,
		model_id,
		(props as Node3D).to_local(world_position),
	)
	if prop == null:
		if _dock:
			_dock.show_status("Не удалось создать instance %s." % model_id, true)
		return
	prop.configure_voxel_scale(prop.voxels_per_block, tile_size)
	var undo_redo := get_undo_redo()
	undo_redo.create_action("Добавить Ember voxel prefab", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(self, "_add_authored_voxel", props, prop, root)
	undo_redo.add_do_reference(prop)
	undo_redo.add_undo_method(self, "_remove_authored_voxel", props, prop)
	undo_redo.commit_action()


func _add_authored_voxel(parent: Node, prop: EmberVoxelProp, root: Node) -> void:
	EmberSceneAuthoring.attach_model_instance(root, parent, prop)
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(prop)
	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.get_resource_filesystem().scan()
	if _dock:
		_dock.show_status("Добавлен %s в Map/Props · %s. Ctrl+Z отменяет." % [prop.model_id, prop.placement_id])
		_dock.refresh()


func _remove_authored_voxel(parent: Node, prop: EmberVoxelProp) -> void:
	var selection := EditorInterface.get_selection()
	if selection:
		selection.remove_node(prop)
	if prop.get_parent() == parent:
		parent.remove_child(prop)
	EditorInterface.mark_scene_as_unsaved()
	if _dock:
		_dock.show_status("Добавление voxel-prefab отменено.")
		_dock.refresh()


func _on_scene_changed(root: Node) -> void:
	if _graph_workspace:
		_graph_workspace.set_scene_root(root)
	if _dock:
		_dock.refresh()
	if _battlefield_painter:
		_battlefield_painter.refresh_context()
	if _world_surface_selector:
		_world_surface_selector.refresh_context()


func _refresh_voxel_gizmos() -> void:
	if is_instance_valid(_last_selected_voxel):
		_last_selected_voxel.update_gizmos()
	if is_instance_valid(_last_selected_trigger):
		_last_selected_trigger.update_gizmos()
	_last_selected_voxel = null
	_last_selected_trigger = null
	var selection := EditorInterface.get_selection()
	if selection == null:
		if _graph_workspace:
			_graph_workspace.set_scene_selection(null)
		return
	var graph_target: Node
	for selected in selection.get_selected_nodes():
		var current := selected as Node
		while current:
			if current is EmberVoxelProp:
				_last_selected_voxel = current
				_last_selected_voxel.update_gizmos()
				graph_target = current
				break
			if current is EmberInteract and EmberObjectInspectorModel.voxel_owner(current) == null:
				_last_selected_trigger = current
				_last_selected_trigger.update_gizmos()
				graph_target = current
				break
			current = current.get_parent()
		if graph_target != null:
			break
	if _graph_workspace:
		_graph_workspace.set_scene_selection(graph_target)
	if _battlefield_painter:
		_battlefield_painter.refresh_context()
	if _world_surface_selector:
		_world_surface_selector.refresh_context()


func _ask_reimport() -> void:
	if EditorInterface.get_edited_scene_root() == null:
		push_warning("ember import: no edited scene")
		return
	_confirm.popup_centered(Vector2i(520, 220))


func _duplicate_voxel_prop(source: EmberVoxelProp) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or not is_instance_valid(source) or source.get_parent() == null:
		if _dock:
			_dock.show_status("Не удалось определить выбранный scene-owned prefab.", true)
		return
	var map := root.find_child("Map", true, false) as EmberMapLoader
	var tile_size := map.imported_tile_size if map and map.imported_tile_size > 0.0 else 16.0
	var duplicate := EmberSceneAuthoring.make_duplicate(root, source, Vector3(tile_size, 0.0, 0.0))
	if duplicate == null:
		if _dock:
			_dock.show_status("Не удалось создать копию prefab.", true)
		return
	var parent := source.get_parent()
	var undo_redo := get_undo_redo()
	undo_redo.create_action("Дублировать Ember prefab", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(self, "_add_authored_duplicate", parent, source, duplicate, root)
	undo_redo.add_do_reference(duplicate)
	undo_redo.add_undo_method(self, "_remove_authored_duplicate", parent, duplicate)
	undo_redo.commit_action()


func _add_authored_duplicate(
	parent: Node,
	source: EmberVoxelProp,
	duplicate: EmberVoxelProp,
	root: Node,
) -> void:
	EmberSceneAuthoring.attach_duplicate(root, source, parent, duplicate)
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(duplicate)
	EditorInterface.mark_scene_as_unsaved()
	if _dock:
		_dock.show_status("Создан %s · новый placement_id · сдвиг +X. Ctrl+Z отменяет." % duplicate.placement_id)
		_dock.refresh()


func _remove_authored_duplicate(parent: Node, duplicate: EmberVoxelProp) -> void:
	var selection := EditorInterface.get_selection()
	if selection:
		selection.remove_node(duplicate)
	if duplicate.get_parent() == parent:
		parent.remove_child(duplicate)
	EditorInterface.mark_scene_as_unsaved()
	if _dock:
		_dock.show_status("Дублирование отменено.")
		_dock.refresh()


func _pack_save(root: Node) -> void:
	var path := root.scene_file_path
	if path.is_empty():
		EditorInterface.save_scene()
		return
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("ember import: pack failed (%s)" % err)
		return
	ResourceSaver.save(packed, path)


func _reimport_and_save() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		push_warning("ember import: no edited scene")
		return
	var map := root.find_child("Map", true, false) as EmberMapLoader
	if map == null:
		push_warning("ember import: no Map (EmberMapLoader) in scene")
		return
	map.load_map(map.map_id)
	EditorInterface.get_resource_filesystem().scan()
	_pack_save(root)
	if _dock:
		_dock.refresh()
