extends SceneTree
const Groups = preload("res://addons/ember_import/ember_voxel_groups.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const PATH := "user://ember_groups_test.tres"
var errors: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_model()
	root.size = Vector2i(1280, 720)
	var resource := _fixture()
	var original := resource.voxels.duplicate()
	var undo := UndoRedo.new()
	var workspace := Workspace.new()
	workspace.setup(null, undo)
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.open_surface(resource, PATH)
	for frame in 4:
		await process_frame
	var selection: VBoxContainer = workspace.get("_selection_panel")
	var panel: VBoxContainer = workspace.get("_groups_panel")
	var indices := PackedInt32Array([_index(resource, Vector3i(2, 1, 2)), _index(resource, Vector3i(3, 1, 2))])
	selection.call("set_selection", indices)
	workspace.call("_apply_group_operation", {"kind": "create", "name": "Берег"})
	_check(resource.voxel_groups.size() == 1 and resource.schema_version == EmberVoxelModelResource.SCHEMA_VERSION, "create did not persist canonical group/schema")
	_check(str(resource.voxel_groups[0].id) == "берег" and resource.voxel_groups[0].indices == indices, "create lost unicode name or members")
	_check(resource.voxel_groups[0].color is Color, "create did not assign group color")
	_check(workspace.has_unsaved_changes() and undo.has_undo(), "group creation missing dirty/Undo")
	workspace.call("_apply_group_operation", {"kind": "rename", "id": "берег", "name": "Кромка воды"})
	_check(resource.voxel_groups[0].name == "Кромка воды" and resource.voxel_groups[0].id == "берег", "rename changed stable id")
	workspace.call("_apply_group_operation", {"kind": "lock", "id": "берег", "locked": true})
	_check(resource.voxel_groups[0].locked and workspace.get("_locked_indices").size() == 2, "lock cache not refreshed")
	var authored_color := Color("45bfe8")
	workspace.call("_apply_group_operation", {"kind": "color", "id": "берег", "color": authored_color})
	_check(resource.voxel_groups[0].color == authored_color, "group color was not persisted")
	undo.undo()
	_check(resource.voxel_groups[0].color != authored_color, "group color Undo failed")
	undo.redo()
	_check(resource.voxel_groups[0].color == authored_color, "group color Redo failed")
	# Batch paint respects lock and still changes an unlocked selected voxel.
	var open_index := _index(resource, Vector3i(4, 1, 2))
	selection.call("set_selection", PackedInt32Array([indices[0], open_index]))
	await _settle(selection)
	workspace.call("_select_palette_color", 2)
	selection.call("_request_paint")
	_check(resource.voxels[indices[0]] == 1 and resource.voxels[open_index] == 2, "locked selection paint was not filtered")
	undo.undo()
	_check(resource.voxels == original, "paint Undo failed")
	# Direct sculpt live merge and material center share the same locked gate.
	workspace.call("_prepare_stroke", Model.TOOL_PAINT)
	var dirty := {}
	workspace.call("_merge_live_changes", {
		indices[0]: {"before": 1, "after": 2}, open_index: {"before": 1, "after": 2},
	}, dirty)
	workspace.call("_finish_stroke")
	_check(resource.voxels[indices[0]] == 1 and resource.voxels[open_index] == 2, "brush live gate changed locked voxel")
	undo.undo()
	var tools: ItemList = workspace.get("_tool")
	for item in tools.item_count:
		if int(tools.get_item_metadata(item)) == Model.TOOL_MATERIAL:
			tools.select(item)
			workspace.call("_on_tool_selected", item)
	workspace.call("_prepare_stroke", Model.TOOL_MATERIAL)
	dirty.clear()
	workspace.call("_apply_material_center", Vector3i(2, 1, 2), dirty)
	workspace.call("_finish_stroke")
	_check(resource.transparency[indices[0]] == 0, "material brush changed locked voxel")
	# Replace members, select group and isolate without mutating canonical voxels.
	selection.call("set_selection", PackedInt32Array([open_index]))
	workspace.call("_apply_group_operation", {"kind": "replace", "id": "берег"})
	_check(resource.voxel_groups[0].indices == PackedInt32Array([open_index]), "replace members failed")
	workspace.call("_select_group_members", resource.voxel_groups[0].indices)
	_check(selection.call("selection_indices") == PackedInt32Array([open_index]), "select group failed")
	workspace.call("_set_group_isolation", PackedInt32Array([open_index]), true)
	var isolated: EmberVoxelModelResource = workspace.get("_isolation_resource")
	_check(isolated != null and isolated.voxels[open_index] == resource.voxels[open_index], "isolate omitted group member")
	_check(isolated.voxels[indices[0]] == 0 and resource.voxels[indices[0]] == 1, "isolate mutated/showed outside source")
	_check(isolated.surface_fill_materials.is_empty(), "isolate retained water")
	workspace.call("_set_group_isolation", PackedInt32Array(), false)
	_check(workspace.get("_isolation_resource") == null, "isolate did not restore full view")
	workspace.call("_set_hidden_group_indices", PackedInt32Array([open_index]))
	var hidden_preview: EmberVoxelModelResource = workspace.get("_isolation_resource")
	_check(hidden_preview != null and hidden_preview.voxels[open_index] == 0, "hidden group remained visible")
	_check(not hidden_preview.surface_fill_materials.is_empty(), "visibility filter unexpectedly hid water")
	_check(resource.voxels[open_index] != 0, "visibility filter mutated source voxels")
	workspace.call("_set_hidden_group_indices", PackedInt32Array())
	var visible_toggle: CheckButton = panel.find_child("VoxelGroupVisible", true, false)
	visible_toggle.button_pressed = false
	_check(panel.call("hidden_indices") == PackedInt32Array([open_index]), "visibility UI lost hidden group membership")
	_check(workspace.get("_isolation_resource") != null, "visibility UI did not rebuild preview")
	visible_toggle.button_pressed = true
	_check(workspace.get("_isolation_resource") == null, "visibility UI did not restore preview")
	_check(bool(workspace.call("_save")), "save failed")
	var reopened := ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	_check(reopened != null and reopened.voxel_groups == resource.voxel_groups and reopened.validation_errors().is_empty(), "group round trip failed")
	# Delete is reversible and discard restores saved groups in the same Resource.
	var isolate_toggle: CheckButton = panel.find_child("VoxelGroupIsolate", true, false)
	isolate_toggle.button_pressed = true
	workspace.call("_apply_group_operation", {"kind": "delete", "id": "берег"})
	_check(resource.voxel_groups.is_empty() and workspace.get("_isolation_resource") == null and not isolate_toggle.button_pressed, "delete failed to clear group/isolation")
	undo.undo()
	_check(resource.voxel_groups.size() == 1, "delete Undo failed")
	workspace.call("_apply_group_operation", {"kind": "rename", "id": "берег", "name": "Черновик"})
	workspace.discard_changes()
	_check(resource.voxel_groups == reopened.voxel_groups and not workspace.has_unsaved_changes(), "discard did not restore saved groups")
	# A group change while isolated must rebuild the derived copy and never recurse.
	panel.call("sync", resource.voxel_groups, "берег")
	workspace.call("_set_group_isolation", resource.voxel_groups[0].indices, true)
	workspace.call("_apply_group_operation", {"kind": "lock", "id": "берег", "locked": false})
	_check(workspace.get("_isolation_resource") != null and not resource.voxel_groups[0].locked, "isolated group update lost state")
	if "--visual" in OS.get_cmdline_user_args():
		var sidebar_scroll := panel.get_parent().get_parent() as ScrollContainer
		sidebar_scroll.ensure_control_visible(panel)
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://ember_groups_test.png")
		print("VISUAL: ", ProjectSettings.globalize_path("user://ember_groups_test.png"))
	workspace.free()
	undo.clear_history()
	undo.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	for error in errors:
		printerr(error)
	if errors.is_empty():
		print("PASS voxel groups: canonical CRUD, stable id, lock gates, isolation, Undo/Redo, save/discard")
	quit(0 if errors.is_empty() else 1)


func _test_model() -> void:
	var input: Array[Dictionary] = [
		{"id": "rocks", "name": "Rocks", "indices": PackedInt32Array([3, 2, 2, 99]), "locked": true},
		{"id": "rocks", "indices": PackedInt32Array([1])},
		{"id": "empty", "indices": PackedInt32Array()},
	]
	var groups := Groups.normalized(input, 8)
	_check(groups.size() == 1 and groups[0].indices == PackedInt32Array([2, 3]), "normalization did not sort/deduplicate/bound")
	_check(groups[0].color is Color, "normalization did not backfill color")
	_check(Groups.locked_indices(groups) == {2:true, 3:true}, "locked union failed")
	var created := Groups.apply(groups, {"kind": "create", "name": "Rocks", "indices": PackedInt32Array([1])}, 8)
	_check(created.selected == "rocks_2" and created.groups.size() == 2, "unique stable id failed")
	_check(Groups.apply(groups, {"kind": "replace", "id": "rocks", "indices": PackedInt32Array()}, 8).has("error"), "empty replacement accepted")
	_check(Groups.apply(groups, {"kind": "delete", "id": "missing"}, 8).has("error"), "missing group mutation accepted")
	var recolored := Groups.apply(groups, {"kind": "color", "id": "rocks", "color": Color("123456")}, 8)
	_check(recolored.groups[0].color == Color("123456"), "color operation failed")
	var invalid := _fixture()
	invalid.voxel_groups = [{"id": "bad", "indices": PackedInt32Array([3, 2])}]
	_check(not invalid.validation_errors().is_empty(), "resource validation accepted unsorted group")


func _settle(panel: VBoxContainer) -> void:
	for frame in 300:
		if not panel.call("busy"):
			return
		await process_frame
	_check(false, "selection overlay did not settle")


func _fixture() -> EmberVoxelModelResource:
	var resource := EmberVoxelModelResource.new()
	resource.model_id = "groups_test"
	resource.display_name = "Группы · тест"
	resource.height_voxels = 4
	resource.palette = PackedColorArray([Color.TRANSPARENT, Color(0.2, 0.6, 0.3), Color(0.8, 0.4, 0.2)])
	var size := resource.grid_size()
	resource.voxels.resize(size.x * size.y * size.z)
	for z in range(2, 7):
		for x in range(2, 7):
			resource.voxels[Model.index_of(Vector3i(x, 1, z), size)] = 1
	resource.transparency.resize(resource.voxels.size())
	resource.surface_fill_levels.resize(size.x * size.z)
	resource.surface_fill_materials.resize(size.x * size.z)
	resource.surface_fill_palette.resize(size.x * size.z)
	resource.surface_fill_levels.fill(2)
	resource.surface_fill_materials.fill(1)
	return resource


func _index(resource: EmberVoxelModelResource, cell: Vector3i) -> int:
	return Model.index_of(cell, resource.grid_size())


func _check(condition: bool, message: String) -> void:
	if not condition and message not in errors:
		errors.append(message)
