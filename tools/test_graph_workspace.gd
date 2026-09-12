extends SceneTree
## Full-size editor graph smoke: canonical action/dialogue documents become native
## GraphNodes without changing their schema, while existing safe editors remain.

const Workspace = preload("res://addons/ember_import/ember_graph_workspace.gd")
const ActionStore = preload("res://addons/ember_import/ember_action_script_store.gd")
const DialogueStore = preload("res://addons/ember_import/ember_dialogue_store.gd")
const DialogueGraphModel = preload("res://addons/ember_import/ember_dialogue_graph_model.gd")
const QuestStore = preload("res://addons/ember_import/ember_quest_store.gd")
const QuestUsageIndex = preload("res://addons/ember_import/ember_quest_usage_index.gd")
const SculptModel = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const TEMP_SCRIPT_ID := "ember_test_graph_workspace"
const TEMP_DIALOGUE_ID := "ember_test_graph_dialogue"
const TEMP_ORPHAN_USAGE_ID := "ember_test_graph_orphan_usage"
var _requested_scene_path := NodePath("")
var _requested_bind_path := NodePath("")
var _requested_bind_token := ""
var _requested_bind_quest: Dictionary = {}
var _requested_unbind_path := NodePath("")
var _requested_unbind_event: Dictionary = {}
var _requested_remove_event: Dictionary = {}
var _requested_action_save: Dictionary = {}


func _init() -> void:
	root.size = Vector2i(1280, 720)
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	quit(await _run())


func _run() -> int:
	var errors: Array[String] = []
	var old_document := ActionStore.document(TEMP_SCRIPT_ID)
	var old_dialogue := DialogueStore.document(TEMP_DIALOGUE_ID)
	ActionStore.delete_document(TEMP_SCRIPT_ID)
	DialogueStore.delete_document(TEMP_DIALOGUE_ID)
	var workspace_host := Control.new()
	workspace_host.name = "GraphWorkspaceTestHost"
	workspace_host.size = Vector2(1280.0, 720.0)
	root.add_child(workspace_host)
	var workspace := Workspace.new() as EmberGraphWorkspace
	workspace_host.add_child(workspace)
	workspace.action_save_requested.connect(_capture_action_save)
	await process_frame
	await process_frame
	_test_visible_layout(errors, workspace)
	await _test_split_layout(errors, workspace)
	_test_primary_action_save(errors, workspace)
	workspace_host.size = Vector2(1600.0, 900.0)
	await process_frame
	await process_frame
	_test_voxel_surface_entry(errors, workspace)
	_test_node_palette(errors, workspace)
	_test_action_graph(errors, workspace)
	_test_action_duplicate(errors, workspace)
	_test_action_clipboard(errors, workspace)
	_test_dialogue_graph(errors, workspace)
	_test_inline_dialogue_fields(errors, workspace)
	_test_vn_properties(errors, workspace)
	await process_frame
	await process_frame
	await _test_live_vn_preview(errors, workspace)
	_test_dialogue_duplicate(errors, workspace)
	_test_dialogue_clipboard(errors, workspace)
	_test_node_diagnostics(errors, workspace)
	_test_unsaved_draft_guard(errors, workspace)
	_test_dialogue_groups(errors, workspace)
	_test_dialogue_node_authoring(errors, workspace)
	_test_complex_read_only(errors, workspace)
	_test_quest_event_authoring(errors, workspace)
	_test_quest_graph(errors, workspace)
	_test_loot_library(errors, workspace)
	await process_frame
	await process_frame
	_test_standalone_action_save(errors)
	_test_standalone_dialogue_graph_save(errors)
	workspace.free()
	workspace_host.free()
	_restore_fixture(old_document)
	_restore_dialogue_fixture(old_dialogue)
	if not errors.is_empty():
		printerr("FAIL graph workspace")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS graph workspace")
	print("  stable document/tool rows keep GraphEdit visible at 1280x720 and 1600x900")
	print("  primary Save routes every graph kind and editor layout restores the split ratio")
	print("  full-size native GraphEdit renders action and dialogue connections")
	print("  minimap/zoom/arrange coexist with the existing safe property editors")
	print("  searchable palette creates dialogue/action nodes directly from wires")
	print("  action +Node/Delete/connection reorder use a local reversible draft")
	print("  Ctrl+D duplicates selected action steps as one reversible block")
	print("  Ctrl+C/X/V copies and cuts action blocks through local history")
	print("  named choice ports mutate canonical options[].next with draft Undo/Redo")
	print("  broken and unreachable dialogue branches block graph save")
	print("  complex VN fields survive structural graph mutations")
	print("  camera survives rebuilds and dialogue editorLayout survives save")
	print("  dialogue +Node/Delete/set-start mutate one validated canonical draft")
	print("  inline node fields and persistent GraphFrame groups share the same draft")
	print("  canonical VN background/portrait/stage fields are editable without flattening actors")
	print("  live preview renders unsaved VN/text scenes and traverses their canonical branches")
	print("  Ctrl+D duplicates dialogue branches with remapped internal edges")
	print("  dialogue clipboard remaps IDs and drops missing cross-resource targets")
	print("  node badges expose broken ports and focus the first validation error")
	print("  resource navigation pauses before discarding an unsaved local draft")
	print("  first-class quest graph edits the Resource and objective projection inline")
	print("  compact Quest Flow overview drills into one event cluster without backlink webs")
	print("  overview/focus/all-links keep independent camera state and canonical writers")
	print("  Quest Flow projects linked action/dialogue event writers as read-only navigable nodes")
	print("  selected scene objects expose guided quest start/objective/complete binding")
	print("  quest-event presets author canonical set_flag nodes in action/dialogue graphs")
	print("  enemy loot tables have a searchable central visual library")
	print("  Surface Canvas has a dedicated enabled main-screen and is absent from the Graph selector")
	print("  standalone action document save participates in Undo/Redo")
	return 0


func _test_voxel_surface_entry(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	var kind := workspace.find_child("GraphKind", true, false) as OptionButton
	var found := false
	if kind != null:
		for index in kind.item_count:
			if str(kind.get_item_metadata(index)) == "voxel_sculpt":
				found = true
				break
	if found:
		errors.append("Voxel Surface is still buried in the Ember Graph content selector")
	var enabled_plugins: PackedStringArray = ProjectSettings.get_setting(
		"editor_plugins/enabled", PackedStringArray()
	)
	if "res://addons/ember_surface_canvas/plugin.cfg" not in enabled_plugins:
		errors.append("dedicated Surface Canvas main-screen plugin is not enabled")
	var sculpt := workspace.find_child("VoxelSurfaceSculptWorkspace", true, false) as EmberVoxelSculptWorkspace
	if sculpt == null:
		errors.append("Voxel Surface pilot workspace is missing")
		return
	sculpt.ensure_ui()
	sculpt.open_pilot()
	var scoped_surface := SculptModel.make_pilot()
	var scoped_region := Rect2i(1, 1, 2, 2)
	sculpt.open_surface(scoped_surface, "user://scoped_surface.tres", scoped_region)
	if sculpt.get("_edit_region_blocks") != scoped_region:
		errors.append("world viewport region was not forwarded into Surface Canvas")
	sculpt.call("_fit_camera_to_surface", false)
	var scoped_target: Vector3 = sculpt.get("_camera_target")
	if not Vector2(scoped_target.x, scoped_target.z).is_equal_approx(Vector2(2.0, 2.0)):
		errors.append("Surface camera did not focus the selected world region")
	sculpt.open_pilot()
	for control_name in [
		"VoxelSculptHeader", "VoxelSculptToolSettings", "VoxelSculptToolRail",
		"VoxelWorkshopSidebar", "VoxelWorkshopSidebarTabs", "VoxelWorkshopPartsSections",
		"VoxelSurfaceViewMenu", "VoxelSurfaceLayerView",
		"VoxelSculptActiveTool",
		"VoxelSculptViewportContainer",
		"VoxelSculptTool", "VoxelSculptRadius", "VoxelSculptHeightLimit",
		"VoxelSculptBuildupRate", "VoxelSculptSmoothStrength", "VoxelSculptCoarse",
		"VoxelSculptSmoothMode", "VoxelSculptSmoothFillPits",
		"VoxelSculptVolumeOperation", "VoxelSculptReliefMode",
		"VoxelSculptReliefDirection", "VoxelSculptReliefGeometry",
		"VoxelSculptReliefGeneratorStyle", "VoxelSculptReliefGeneratorDirection",
		"VoxelSculptReliefGeneratorScale", "VoxelSculptReliefGeneratorDetail",
		"VoxelSculptReliefVariant",
		"VoxelSculptMaterialPreset", "VoxelSculptMaterialScope",
		"VoxelSculptMaterialTolerance",
		"VoxelSculptRegionSelect", "VoxelSculptWholeRegion", "VoxelSculptRegionLabel",
		"VoxelSculptRegionOverlay",
		"VoxelSurfaceCameraPopup", "VoxelSurfaceCameraYaw",
		"VoxelSurfaceCameraPitch", "VoxelSurfaceCameraSize", "VoxelSurfaceCameraMargin",
		"PlayVoxelSurfaceOwner", "SaveVoxelSurfacePilot",
	]:
		if workspace.find_child(control_name, true, false) == null:
			errors.append("Voxel Surface pilot lost authoring control %s" % control_name)
	var viewport_container := workspace.find_child(
		"VoxelSculptViewportContainer", true, false
	) as SubViewportContainer
	var sculpt_viewport := workspace.find_child("VoxelSculptViewport", true, false) as SubViewport
	if viewport_container != null and sculpt_viewport != null:
		viewport_container.size = Vector2(12000.0, 6000.0)
		sculpt.call("_sync_viewport_size")
		if maxi(sculpt_viewport.size.x, sculpt_viewport.size.y) > 4096:
			errors.append("Voxel Surface viewport can still exceed the safe GPU texture limit")
	var camera_target_before: Vector3 = sculpt.get("_camera_target")
	sculpt.call("_pan_camera", Vector2(80.0, -40.0))
	var camera_target_after: Vector3 = sculpt.get("_camera_target")
	if camera_target_after.is_equal_approx(camera_target_before):
		errors.append("Voxel Surface MMB pan did not move the camera target")
	sculpt.call("_center_camera")
	var centered_target: Vector3 = sculpt.get("_camera_target")
	var expected_target: Vector3 = sculpt.call("_default_camera_target")
	if not centered_target.is_equal_approx(expected_target):
		errors.append("Voxel Surface Center did not restore the default camera target")
	var size_control := workspace.find_child("VoxelSurfaceCameraSize", true, false) as SpinBox
	if size_control != null:
		size_control.value = 1.5
		sculpt.call("_fit_camera_to_surface")
		if float(sculpt.get("_ortho_size")) <= 1.5:
			errors.append("Voxel Surface Fit did not restore a readable whole-surface frame")
	var view_menu := workspace.find_child("VoxelSurfaceViewMenu", true, false) as MenuButton
	if view_menu == null:
		errors.append("Voxel Surface View menu lost camera presets or settings")
	else:
		# Check stable actions, not a fixed total that also counts separators.
		for action_id in range(8):
			var item := view_menu.get_popup().get_item_index(action_id)
			if item < 0 or view_menu.get_popup().is_item_separator(item):
				errors.append("Voxel Surface View menu lost action %d" % action_id)
	var layer_view := workspace.find_child("VoxelSurfaceLayerView", true, false) as OptionButton
	if layer_view == null or layer_view.item_count != 2:
		errors.append("Voxel Surface lost its floor/water viewport modes")
	else:
		layer_view.select(1)
		sculpt.call("_on_surface_layer_view_changed", 1)
		if bool(sculpt.call("_shows_water_overlay")):
			errors.append("floor-only viewport mode did not hide the water overlay")
		layer_view.select(0)
		sculpt.call("_on_surface_layer_view_changed", 0)
		if not bool(sculpt.call("_shows_water_overlay")):
			errors.append("combined viewport mode did not restore the water overlay")
	var tool := workspace.find_child("VoxelSculptTool", true, false) as ItemList
	var radius := workspace.find_child("VoxelSculptRadius", true, false) as OptionButton
	var rate := workspace.find_child("VoxelSculptBuildupRate", true, false) as OptionButton
	var smooth_strength := workspace.find_child(
		"VoxelSculptSmoothStrength", true, false
	) as OptionButton
	var tool_ids: Array[int] = []
	for index in tool.item_count:
		tool_ids.append(int(tool.get_item_metadata(index)))
	if tool.get_parent().name != "VoxelSculptToolRail":
		errors.append("Voxel Surface tools are no longer owned by the vertical tool rail")
	if radius.get_parent().name != "VoxelSculptToolSettings":
		errors.append("Voxel Surface radius left the contextual tool-settings row")
	var region_button := workspace.find_child("VoxelSculptRegionSelect", true, false)
	var current_sidebar := sculpt.find_child("VoxelWorkshopSidebar", true, false)
	if (
		region_button == null
		or current_sidebar == null
		or not current_sidebar.is_ancestor_of(region_button)
	):
		errors.append("Voxel Surface edit-region controls left the resizable sidebar")
	if tool.item_count != 8:
		errors.append("Voxel Surface compact rail should expose 8 families, got %d" % tool.item_count)
	if SculptModel.TOOL_ADD not in tool_ids or SculptModel.TOOL_RAISE not in tool_ids:
		errors.append("Voxel Surface compact rail lost volume or relief family")
	if SculptModel.TOOL_LEVEL not in tool_ids:
		errors.append("Voxel Surface pilot lost the fixed-plane terrace brush")
	if SculptModel.TOOL_SMOOTH not in tool_ids:
		errors.append("Voxel Surface pilot lost the neighbor-height smoothing brush")
	if SculptModel.TOOL_RAMP not in tool_ids:
		errors.append("Voxel Surface pilot lost the two-point ramp brush")
	for concrete_tool in [
		SculptModel.TOOL_ADD, SculptModel.TOOL_REMOVE,
		SculptModel.TOOL_RAISE, SculptModel.TOOL_LOWER,
		SculptModel.TOOL_SHELL_RAISE, SculptModel.TOOL_SHELL_LOWER,
	]:
		if not bool(sculpt.call("_activate_tool_id", concrete_tool)):
			errors.append("Voxel Surface family controls cannot activate tool %d" % concrete_tool)
		elif int(sculpt.call("_selected_tool_id")) != concrete_tool:
			errors.append("Voxel Surface family resolved to wrong tool %d" % concrete_tool)
	if SculptModel.TOOL_MATERIAL not in tool_ids:
		errors.append("Voxel Surface pilot lost material-channel painting")
	else:
		var material_tool_index := tool_ids.find(SculptModel.TOOL_MATERIAL)
		tool.select(material_tool_index)
		sculpt.call("_on_tool_selected", material_tool_index)
		var scope := workspace.find_child(
			"VoxelSculptMaterialScope", true, false
		) as OptionButton
		var tolerance := workspace.find_child(
			"VoxelSculptMaterialTolerance", true, false
		) as OptionButton
		scope.select(1)
		sculpt.call("_on_material_scope_changed", 1)
		if not tolerance.visible or radius.visible:
			errors.append("smart material selection did not expose tolerance contextually")
		scope.select(0)
		sculpt.call("_on_material_scope_changed", 0)
		if tolerance.visible or not radius.visible:
			errors.append("material brush mode did not restore radius controls")
	if SculptModel.TOOL_SURFACE_FILL not in tool_ids:
		errors.append("Voxel Surface pilot lost level-fill authoring")
	else:
		var fill_tool_index := tool_ids.find(SculptModel.TOOL_SURFACE_FILL)
		tool.select(fill_tool_index)
		sculpt.call("_on_tool_selected", fill_tool_index)
		var fill_material := workspace.find_child(
			"VoxelSculptSurfaceFillMaterial", true, false
		) as OptionButton
		var fill_level := workspace.find_child(
			"VoxelSculptSurfaceFillLevel", true, false
		) as OptionButton
		var fill_inset := workspace.find_child(
			"VoxelSculptSurfaceFillInset", true, false
		) as OptionButton
		if (
			fill_material == null or fill_level == null or fill_inset == null
			or not fill_material.visible or not fill_level.visible or not fill_inset.visible
			or radius.visible
		):
			errors.append("level fill did not expose its point-tool controls contextually")
		elif int(fill_inset.get_item_metadata(fill_inset.selected)) != 1:
			errors.append("level fill did not default to a visible one-voxel shoreline")
	if workspace.find_child("RampAnchor", true, false) == null:
		errors.append("Voxel Surface ramp lost its visible point-A marker")
	var radii: Array[int] = []
	for index in radius.item_count:
		radii.append(int(radius.get_item_metadata(index)))
	if radii != [1, 2, 4, 6, 8, 12, 16, 24, 32]:
		errors.append("Voxel Surface radius presets are incomplete: %s" % radii)
	var rates: Array[int] = []
	for index in rate.item_count:
		rates.append(int(rate.get_item_metadata(index)))
	if rates != [1, 2, 4, 8, 16, 32]:
		errors.append("Voxel Surface buildup presets are incomplete: %s" % rates)
	var strengths: Array[int] = []
	for index in smooth_strength.item_count:
		strengths.append(int(smooth_strength.get_item_metadata(index)))
	if strengths != [1, 2, 4, 8]:
		errors.append("Voxel Surface smoothing strengths are incomplete: %s" % strengths)
	var owner_surface := SculptModel.make_world_surface(
		"agent_sandbox",
		"Agent Sandbox",
		{
			"width": 1,
			"depth": 1,
			"heights": PackedInt32Array([1]),
			"tileIds": PackedInt32Array([1]),
		},
		{1: Color("#6f9147")},
	)
	sculpt.open_surface(owner_surface, "user://owner_surface.tres")
	var play_owner := workspace.find_child("PlayVoxelSurfaceOwner", true, false) as Button
	if (
		play_owner == null or not play_owner.visible
		or sculpt.call("_owner_scene_path") != "res://scenes/agent_sandbox.tscn"
	):
		errors.append("world Surface did not expose its exact owner-scene Play action")
	sculpt.open_pilot()


func _test_loot_library(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	workspace.open_resource("loot", "swamp_elite_drops")
	var kind := workspace.find_child("GraphKind", true, false) as OptionButton
	var library := workspace.find_child("CombatLootLibraryWorkspace", true, false) as Control
	var list := workspace.find_child("CombatLootLibraryList", true, false) as ItemList
	var search := workspace.find_child("CombatLootLibrarySearch", true, false) as LineEdit
	var editor := workspace.find_child("CombatLootCentralEditor", true, false) as Control
	var graph_split := workspace.find_child("GraphSplit", true, false) as Control
	if _selected_metadata(kind) != "loot":
		errors.append("loot library is not reachable from the Ember Graph kind selector")
	if library == null or not library.visible or graph_split == null or graph_split.visible:
		errors.append("loot mode did not replace GraphEdit with the central catalog")
	if list == null or list.item_count != 3:
		errors.append("loot catalog did not show all three authored tables")
	elif search == null:
		errors.append("loot catalog lost its search field")
	else:
		search.text = "warden"
		library.call("_refresh_list")
		if list.item_count != 1 or str(list.get_item_metadata(0)) != "swamp_elite_drops":
			errors.append("loot search did not index assigned enemy names/IDs")
		search.text = ""
		library.call("_refresh_list")
	if editor == null or editor.find_child("CombatLootEntry_0", true, false) == null:
		errors.append("selected loot table did not open its visual row editor")


func _test_quest_event_authoring(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	var start_token := QuestStore.event_token("sandbox_notice_quest", "start")
	var objective_token := QuestStore.event_token(
		"sandbox_notice_quest", "objective", "read_notice"
	)
	workspace.open_resource("action", "sandbox_chain")
	if workspace.find_child("GraphAddQuestEvent", true, false) == null:
		errors.append("Ember Graph toolbar has no guided quest-event action")
	var before_action: Dictionary = workspace.get("_action_draft")
	var before_action_count := (before_action.get("steps", []) as Array).size()
	workspace.call("_apply_quest_event", start_token)
	var action_draft: Dictionary = workspace.get("_action_draft")
	var action_steps: Array = action_draft.get("steps", [])
	var action_event: Dictionary = action_steps[-1] if not action_steps.is_empty() else {}
	if action_steps.size() != before_action_count + 1:
		errors.append("action graph quest preset did not add one local draft node")
	elif action_event.get("type", "") != "set_flag" or action_event.get("flag", "") != "sandbox_notice_status" or action_event.get("value") != "active":
		errors.append("action graph quest start did not compile to canonical set_flag")
	(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()

	workspace.open_resource("dialogue", "sandbox_notice_talk")
	var before_dialogue: Dictionary = workspace.get("_dialogue_draft")
	var before_dialogue_count := (before_dialogue.get("steps", []) as Array).size()
	workspace.call("_apply_quest_event", objective_token)
	var dialogue_draft: Dictionary = workspace.get("_dialogue_draft")
	var dialogue_steps: Array = dialogue_draft.get("steps", [])
	var dialogue_event: Dictionary = dialogue_steps[-1] if not dialogue_steps.is_empty() else {}
	if dialogue_steps.size() != before_dialogue_count + 1:
		errors.append("dialogue graph quest preset did not add one local draft node")
	elif dialogue_event.get("type", "") != "set_flag" or dialogue_event.get("flag", "") != "sandbox_notice_read" or dialogue_event.get("value") != true:
		errors.append("dialogue branch objective did not compile to canonical set_flag")
	else:
		var step_id := str(dialogue_event.get("id", ""))
		if workspace.find_child("Inline_%s_quest_event" % step_id, true, false) == null:
			errors.append("dialogue set_flag node has no inline quest-event picker")
	(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()


func _test_quest_graph(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	var old_orphan_usage := ActionStore.snapshot(TEMP_ORPHAN_USAGE_ID)
	ActionStore.write_document({
		"id": TEMP_ORPHAN_USAGE_ID,
		"nameRu": "Осиротевшее событие Quest Flow",
		"steps": [{
			"type": "set_flag",
			"flag": "sandbox_notice_read",
			"value": true,
		}],
	})
	var scene_fixture := Node3D.new()
	scene_fixture.name = "QuestSceneFixture"
	var scene_prop := EmberVoxelProp.new()
	scene_prop.name = "QuestSign"
	scene_fixture.add_child(scene_prop)
	var scene_interact := EmberInteract.new()
	scene_interact.name = "Interact"
	scene_interact.kind = "quest_marker"
	scene_interact.quest_id = "sandbox_notice_quest"
	scene_interact.script_id = "sandbox_notice"
	scene_prop.add_child(scene_interact)
	var unbound_prop := EmberVoxelProp.new()
	unbound_prop.name = "UnboundQuestProp"
	unbound_prop.placement_id = "unbound_quest_prop"
	scene_fixture.add_child(unbound_prop)
	workspace.set_scene_root(scene_fixture)
	workspace.set_scene_selection(unbound_prop)
	if not workspace.scene_node_requested.is_connected(_capture_scene_node_request):
		workspace.scene_node_requested.connect(_capture_scene_node_request)
	if not workspace.quest_event_bind_requested.is_connected(_capture_quest_event_bind):
		workspace.quest_event_bind_requested.connect(_capture_quest_event_bind)
	if not workspace.quest_event_unbind_requested.is_connected(_capture_quest_event_unbind):
		workspace.quest_event_unbind_requested.connect(_capture_quest_event_unbind)
	if not workspace.quest_event_remove_requested.is_connected(_capture_quest_event_remove):
		workspace.quest_event_remove_requested.connect(_capture_quest_event_remove)
	workspace.open_resource("quest", "sandbox_notice_quest")
	var graph := workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	var kind := workspace.find_child("GraphKind", true, false) as OptionButton
	var resource := workspace.find_child("GraphResource", true, false) as OptionButton
	var add_objective := workspace.find_child("GraphAddQuestObjective", true, false) as Button
	var new_quest := workspace.find_child("GraphNewQuest", true, false) as Button
	var baseline_document: Dictionary = workspace.get("_quest_draft")
	var baseline_count := (baseline_document.get("objectives", []) as Array).size()
	var baseline_edges := QuestStore.dependency_edges(baseline_document).size()
	var baseline_usages := QuestUsageIndex.entries(baseline_document).size()
	var scene_usages := QuestUsageIndex.scene_entries(
		scene_fixture,
		baseline_document,
		QuestUsageIndex.entries(baseline_document),
	)
	var baseline_scene_nodes := scene_usages.size()
	var baseline_candidate_nodes := 1
	var baseline_scene_edges := 0
	for scene_usage in scene_usages:
		baseline_scene_edges += ((scene_usage as Dictionary).get("eventIds", []) as Array).size()
	if _selected_metadata(kind) != "quest":
		errors.append("quest resources have no first-class Ember Graph mode")
	if _selected_metadata(resource) != "sandbox_notice_quest":
		errors.append("quest selector did not expose the authored quest Resource")
	if (
		graph == null
		or _graph_nodes(graph).size() != baseline_count + 1
		or graph.connections.size() != baseline_edges
	):
		errors.append("default Quest Flow is not a compact objective-only overview")
	_assert_graph_connection_ports(errors, graph, "compact quest overview")
	if int(workspace.call("_quest_dependency_input_port")) != 0:
		errors.append("compact quest overview did not remap dependency input to port 0")
	if (
		workspace.find_child("OpenQuestRootEvents", true, false) == null
		or workspace.find_child("OpenQuestObjectiveEvents_0", true, false) == null
	):
		errors.append("compact quest nodes have no event drill-down actions")
	for graph_node in _graph_nodes(graph):
		if str(graph_node.get_meta("quest_role", "")) in ["usage", "scene", "scene_candidate"]:
			errors.append("compact Quest Flow still renders the event backlink web")
			break
	var focus_objective := workspace.find_child(
		"OpenQuestObjectiveEvents_0", true, false
	) as Button
	if focus_objective != null:
		graph.zoom = 1.1
		focus_objective.pressed.emit()
		graph.zoom = 0.85
		var focused_objectives := 0
		var focused_usages := 0
		var focused_candidate := false
		for graph_node in _graph_nodes(graph):
			match str(graph_node.get_meta("quest_role", "")):
				"objective": focused_objectives += 1
				"usage": focused_usages += 1
				"scene_candidate": focused_candidate = true
		if (
			str(workspace.get("_quest_focus_target")) != "read_notice"
			or focused_objectives != 1
			or focused_usages == 0
			or not focused_candidate
		):
			errors.append("objective drill-down did not isolate its events and selected scene object")
		_assert_graph_connection_ports(errors, graph, "focused quest events")
		if int(workspace.call("_quest_dependency_input_port")) != 1:
			errors.append("focused quest events did not retain dependency input port 1")
		var overview_button := workspace.find_child("GraphQuestOverview", true, false) as Button
		if overview_button == null or not overview_button.visible:
			errors.append("focused quest subgraph has no visible breadcrumb back to overview")
		elif not str((workspace.find_child("GraphQuestFocusLabel", true, false) as Label).text).contains("Прочитать"):
			errors.append("focused quest subgraph has no readable breadcrumb label")
		else:
			overview_button.pressed.emit()
			if not is_equal_approx(graph.zoom, 1.1):
				errors.append("quest overview camera was lost after returning from a focused subgraph")
			var mode_states: Dictionary = workspace.get("_view_states")
			if (
				not mode_states.has("quest:sandbox_notice_quest:overview")
				or not mode_states.has("quest:sandbox_notice_quest:focus:read_notice")
			):
				errors.append("quest overview and focused subgraph do not keep separate view state")
	var all_links := workspace.find_child("GraphQuestAllLinks", true, false) as Button
	if all_links == null:
		errors.append("Quest Flow has no diagnostic all-links mode")
	else:
		all_links.pressed.emit()
	_assert_graph_connection_ports(errors, graph, "all-links quest diagnostics")
	if (
		graph == null
		or _graph_nodes(graph).size() != baseline_count + 1 + baseline_usages + baseline_scene_nodes + baseline_candidate_nodes
		or graph.connections.size() != baseline_count + baseline_edges + baseline_usages + baseline_scene_edges
	):
		errors.append("quest graph did not project its root/objective/dependency wires")
	var usage_nodes: Array[GraphNode] = []
	for graph_node in _graph_nodes(graph):
		if str(graph_node.get_meta("quest_role", "")) == "usage":
			usage_nodes.append(graph_node)
	if usage_nodes.size() != baseline_usages:
		errors.append("quest flow lost computed action/dialogue usage nodes")
	for usage_node in usage_nodes:
		if usage_node.get_combined_minimum_size().y > 180.0:
			errors.append("quest usage node expands into a tall empty card")
			break
		if not usage_node.draggable:
			errors.append("computed quest usage node cannot be arranged by the author")
			break
		if (
			str(usage_node.get_meta("document_kind", "")).is_empty()
			or str(usage_node.get_meta("document_id", "")).is_empty()
			or usage_node.find_child("OpenLinkedGraph", true, false) == null
		):
			errors.append("quest usage node cannot navigate to its canonical source")
			break
	var orphan_remove_button: Button
	for usage_node in usage_nodes:
		var candidate := usage_node.find_child("RemoveOrphanedQuestEvent_*", true, false) as Button
		if candidate != null:
			orphan_remove_button = candidate
			break
	if orphan_remove_button == null:
		errors.append("orphaned action usage has no removable Quest Flow action")
	else:
		_requested_remove_event = {}
		orphan_remove_button.pressed.emit()
		if str(_requested_remove_event.get("documentKind", "")) != "action":
			errors.append("orphaned Quest Flow removal lost its canonical action writer")
	var scene_nodes: Array[GraphNode] = []
	var scene_candidate: GraphNode
	for graph_node in _graph_nodes(graph):
		if str(graph_node.get_meta("quest_role", "")) == "scene":
			scene_nodes.append(graph_node)
		elif str(graph_node.get_meta("quest_role", "")) == "scene_candidate":
			scene_candidate = graph_node
	if scene_nodes.size() != baseline_scene_nodes:
		errors.append("quest flow lost open-scene Interact backlinks")
	elif not scene_nodes.is_empty():
		var select_scene := scene_nodes[0].find_child("SelectQuestSceneNode", true, false) as Button
		if select_scene == null:
			errors.append("quest scene backlink has no navigation action")
		else:
			_requested_scene_path = NodePath("")
			select_scene.pressed.emit()
			if str(_requested_scene_path) != "QuestSign/Interact":
				errors.append("quest scene backlink did not request its stable scene NodePath")
		var linked_usage: GraphNode
		for connection in graph.connections:
			if StringName(connection.get("from_node", "")) != scene_nodes[0].name:
				continue
			linked_usage = graph.get_node_or_null(
				NodePath(str(connection.get("to_node", "")))
			) as GraphNode
			if linked_usage != null and str(linked_usage.get_meta("document_kind", "")) == "action":
				break
			linked_usage = null
		if linked_usage == null:
			errors.append("quest scene backlink has no removable action-event wire")
		else:
			_requested_unbind_path = NodePath("")
			_requested_unbind_event = {}
			workspace.call(
				"_on_disconnection_request",
				scene_nodes[0].name, 0, linked_usage.name, 0,
			)
			if str(_requested_unbind_path) != "QuestSign":
				errors.append("disconnecting a green wire lost its authoring owner path")
			elif str(_requested_unbind_event.get("documentKind", "")) != "action":
				errors.append("disconnecting a green wire lost its exact action event")
	if scene_candidate == null or not scene_candidate.draggable:
		errors.append("selected unbound scene object has no draggable green Quest Flow node")
	var saved_view_states: Dictionary = (workspace.get("_view_states") as Dictionary).duplicate(true)
	var synthetic_positions := {
		"quest_root": Vector2(10.0, 20.0),
		"objective:read_notice": Vector2(30.0, 40.0),
		"action:derived:event": Vector2(50.0, 60.0),
	}
	workspace.set("_view_states", {
		str(workspace.call("_view_key")): {
			"scroll": Vector2.ZERO,
			"zoom": 1.0,
			"positions": synthetic_positions,
		},
	})
	var layout_projection: Dictionary = workspace.call(
		"_apply_cached_quest_layout", baseline_document
	)
	var projected_layout: Dictionary = layout_projection.get("editorLayout", {})
	if projected_layout.has("action:derived:event"):
		errors.append("computed quest usage position leaked into Quest Resource editorLayout")
	workspace.set("_view_states", saved_view_states)
	if (
		workspace.find_child("InlineQuest_titleRu", true, false) == null
		or workspace.find_child("InlineQuest_statusFlagId", true, false) == null
		or workspace.find_child("InlineQuestObjective_0_textRu", true, false) == null
		or workspace.find_child("InlineQuestObjective_0_progressMode", true, false) == null
		or workspace.find_child("InlineQuestObjective_0_combatCounter", true, false) == null
		or workspace.find_child("InlineQuestObjective_0_requiredCount", true, false) == null
	):
		errors.append("quest graph nodes lost inline text/combat-counter authoring fields")
	var bind_start := workspace.find_child("BindQuestStartToSelection", true, false) as Button
	var bind_complete := workspace.find_child("BindQuestCompleteToSelection", true, false) as Button
	var bind_objective := workspace.find_child("BindQuestObjective_0_ToSelection", true, false) as Button
	if bind_start == null or bind_complete == null or bind_objective == null:
		errors.append("Quest Flow nodes have no guided scene-object binding actions")
	elif bind_start.disabled or bind_objective.disabled:
		errors.append("Quest Flow did not recognize the selected scene-owned voxel")
	else:
		_requested_bind_path = NodePath("")
		_requested_bind_token = ""
		_requested_bind_quest = {}
		bind_objective.pressed.emit()
		if str(_requested_bind_path) != "UnboundQuestProp":
			errors.append("guided quest binding did not emit the selected authoring owner path")
		elif _requested_bind_token != QuestStore.event_token(
			"sandbox_notice_quest", "objective", "read_notice"
		):
			errors.append("guided quest binding emitted the wrong objective event token")
		elif str(_requested_bind_quest.get("id", "")) != "sandbox_notice_quest":
			errors.append("guided quest binding did not include the current quest draft")
	if scene_candidate != null:
		_requested_bind_path = NodePath("")
		_requested_bind_token = ""
		workspace.call(
			"_on_connection_request",
			scene_candidate.name, 0,
			StringName("quest_objective_0"), 3,
		)
		if str(_requested_bind_path) != "UnboundQuestProp":
			errors.append("green drag-to-bind lost the selected scene owner")
		elif _requested_bind_token != QuestStore.event_token(
			"sandbox_notice_quest", "objective", "read_notice"
		):
			errors.append("green drag-to-bind emitted the wrong objective event")
		_requested_bind_token = ""
		workspace.call(
			"_on_connection_request",
			scene_candidate.name, 0,
			StringName("quest_root"), 2,
		)
		if _requested_bind_token != QuestStore.event_token(
			"sandbox_notice_quest", "complete"
		):
			errors.append("root completion drag port emitted the wrong quest event")
	var original_title := str((workspace.get("_quest_draft") as Dictionary).get("titleRu", ""))
	workspace.call("_begin_quest_inline_edit")
	workspace.call("_set_quest_document_field", "Изменённое тестовое задание", "titleRu")
	workspace.call("_commit_quest_inline_edit")
	(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
	if str((workspace.get("_quest_draft") as Dictionary).get("titleRu", "")) != original_title:
		errors.append("quest inline Undo did not restore the Resource title")
	(workspace.find_child("GraphDraftRedo", true, false) as Button).pressed.emit()
	if str((workspace.get("_quest_draft") as Dictionary).get("titleRu", "")) != "Изменённое тестовое задание":
		errors.append("quest inline Redo did not restore the edited title")
	(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
	if add_objective == null:
		errors.append("quest graph has no visible add-objective action")
	else:
		add_objective.pressed.emit()
		var draft: Dictionary = workspace.get("_quest_draft")
		if (draft.get("objectives", []) as Array).size() != baseline_count + 1:
			errors.append("quest graph did not append an objective to the local draft")
		elif (
			_graph_nodes(graph).size() != baseline_count + 2 + baseline_usages + baseline_scene_nodes + baseline_candidate_nodes
			or graph.connections.size() != baseline_count + baseline_edges + 1 + baseline_usages + baseline_scene_edges
		):
			errors.append("new quest objective was not connected to the quest root")
		else:
			var source_id := str(((draft.get("objectives", []) as Array)[0] as Dictionary).get("id", ""))
			var target_node_name := StringName("quest_objective_%d" % baseline_count)
			(workspace.find_child("GraphQuestOverview", true, false) as Button).pressed.emit()
			workspace.call(
				"_on_connection_request",
				StringName("quest_objective_0"), 0,
				target_node_name, 0,
			)
			_assert_graph_connection_ports(errors, graph, "authored quest dependency")
			draft = workspace.get("_quest_draft")
			var objectives: Array = draft.get("objectives", [])
			var dependencies: Array = (objectives[baseline_count] as Dictionary).get("requiresObjectiveIds", [])
			if dependencies != [source_id] or graph.connections.size() != baseline_edges + 1:
				errors.append("quest wire did not persist objective prerequisite")
			var before_cycle := draft.duplicate(true)
			workspace.call(
				"_on_connection_request",
				target_node_name, 0,
				StringName("quest_objective_0"), 0,
			)
			if workspace.get("_quest_draft") != before_cycle:
				errors.append("quest graph accepted a dependency cycle")
			(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
			objectives = (workspace.get("_quest_draft") as Dictionary).get("objectives", [])
			if not ((objectives[baseline_count] as Dictionary).get("requiresObjectiveIds", []) as Array).is_empty():
				errors.append("quest dependency wire Undo did not remove the prerequisite")
			(workspace.find_child("GraphDraftRedo", true, false) as Button).pressed.emit()
			objectives = (workspace.get("_quest_draft") as Dictionary).get("objectives", [])
			if (objectives[baseline_count] as Dictionary).get("requiresObjectiveIds", []) != [source_id]:
				errors.append("quest dependency wire Redo did not restore the prerequisite")
		# Return to the one-objective baseline regardless of the dependency history.
		for _index in 4:
			if ((workspace.get("_quest_draft") as Dictionary).get("objectives", []) as Array).size() <= baseline_count:
				break
			(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
		if ((workspace.get("_quest_draft") as Dictionary).get("objectives", []) as Array).size() != baseline_count:
			errors.append("quest objective add is not reversible")
	if new_quest == null:
		errors.append("quest graph has no visible create-quest action")
	else:
		new_quest.pressed.emit()
		var id_input := workspace.find_child("InlineQuest_id", true, false) as LineEdit
		if id_input == null or not id_input.editable:
			errors.append("new quest did not expose an editable Resource ID")
		if not bool(workspace.call("_has_unsaved_draft")):
			errors.append("new unsaved quest can be discarded without a navigation guard")
		if _graph_nodes(graph).size() != 2 or graph.connections.size() != 0:
			errors.append("new quest draft did not render its initial objective")
	workspace.set_scene_root(null)
	scene_fixture.free()
	ActionStore.restore_snapshot(old_orphan_usage)


func _capture_scene_node_request(node_path: NodePath) -> void:
	_requested_scene_path = node_path


func _capture_action_save(document: Dictionary) -> void:
	_requested_action_save = document.duplicate(true)


func _capture_quest_event_bind(
	scene_path: NodePath,
	event_token: String,
	quest_document: Dictionary,
) -> void:
	_requested_bind_path = scene_path
	_requested_bind_token = event_token
	_requested_bind_quest = quest_document.duplicate(true)


func _capture_quest_event_unbind(scene_path: NodePath, event_entry: Dictionary) -> void:
	_requested_unbind_path = scene_path
	_requested_unbind_event = event_entry.duplicate(true)


func _capture_quest_event_remove(event_entry: Dictionary) -> void:
	_requested_remove_event = event_entry.duplicate(true)


func _test_visible_layout(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	var graph := workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	var editor_scroll := workspace.find_child("GraphEditorScroll", true, false) as ScrollContainer
	var document_toolbar := workspace.find_child("GraphDocumentToolbar", true, false) as HBoxContainer
	var tool_row := workspace.find_child("GraphToolRow", true, false) as HBoxContainer
	var secondary_popup := workspace.find_child("GraphSecondaryToolsPopup", true, false) as PopupPanel
	var status := workspace.find_child("GraphStatus", true, false) as Label
	if workspace.size.x < 1200.0 or workspace.size.y < 700.0:
		errors.append("main-screen workspace did not expand to its editor parent")
	if graph == null or graph.size.x < 500.0 or graph.size.y < 400.0:
		errors.append("GraphEdit received no visible layout rectangle")
	if editor_scroll == null or editor_scroll.size.x < 300.0 or editor_scroll.size.y < 400.0:
		errors.append("graph property column received no visible layout rectangle")
	elif editor_scroll.size_flags_horizontal & Control.SIZE_EXPAND:
		errors.append("graph property column can still jump wider for a long selected node title")
	var selection_label := workspace.find_child("GraphSelectionLabel", true, false) as Label
	if (
		selection_label == null
		or not selection_label.clip_text
		or selection_label.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS
	):
		errors.append("selected node title is not constrained inside the property column")
	if document_toolbar == null or tool_row == null:
		errors.append("graph navigation and local tools are not separated into stable rows")
	elif document_toolbar.size.y > 42.0 or tool_row.size.y > 42.0:
		errors.append("graph header still wraps and steals graph height at 1280x720")
	if secondary_popup == null:
		errors.append("secondary graph commands have no compact overflow popup")
	else:
		for control_name in ["GraphDuplicateNodes", "GraphClipboardMenu", "GraphGroupName"]:
			var control := workspace.find_child(control_name, true, false) as Control
			if control == null or not secondary_popup.is_ancestor_of(control):
				errors.append("%s was not moved out of the primary tool row" % control_name)
	if status == null or status.get_parent() == document_toolbar or status.size.x > workspace.size.x:
		errors.append("graph diagnostics can still be pushed outside the visible workspace")
	elif not status.clip_text or status.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS:
		errors.append("graph diagnostics do not clip predictably on a narrow editor")
	var save := workspace.find_child("SaveDialogueGraph", true, false) as Button
	if save == null or not save.visible or not document_toolbar.is_ancestor_of(save):
		errors.append("primary graph save is not stable beside document navigation")
	for graph_node in _graph_nodes(graph):
		if graph_node.size.x < 200.0 or graph_node.size.y < 70.0:
			errors.append("GraphNode exists but has no visible rectangle")
			break


func _test_split_layout(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	var split := workspace.find_child("GraphSplit", true, false) as HSplitContainer
	if split == null:
		return
	var target_offset := roundi(split.size.x * 0.62)
	split.split_offset = target_offset
	split.dragged.emit(target_offset)
	var saved: Dictionary = workspace.export_editor_layout()
	if not saved.has("split_ratio"):
		errors.append("graph split ratio is not exported for editor layout persistence")
		return
	split.split_offset = 850
	workspace.import_editor_layout(saved)
	await process_frame
	await process_frame
	if absi(split.split_offset - target_offset) > 2:
		errors.append("graph property split ratio was not restored (%d != %d, saved %s)" % [
			split.split_offset, target_offset, saved,
		])


func _test_primary_action_save(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	workspace.open_resource("action", "sandbox_chain")
	_requested_action_save = {}
	var save := workspace.find_child("SaveDialogueGraph", true, false) as Button
	if save == null or save.disabled:
		errors.append("stable document row did not expose a valid action Save")
		return
	save.pressed.emit()
	if str(_requested_action_save.get("id", "")) != "sandbox_chain":
		errors.append("primary document Save did not route the current action draft")


func _test_action_graph(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	workspace.open_resource("action", "sandbox_chain")
	var storage_owner := workspace.find_child("ActionStorageOwner", true, false) as Label
	var migrate_resource := workspace.find_child("MigrateActionResource", true, false) as Button
	if storage_owner == null or migrate_resource == null:
		errors.append("action chain did not expose its canonical storage owner/migration action")
	elif ActionStore.owner("sandbox_chain") == "legacy" and migrate_resource.disabled:
		errors.append("legacy action chain did not expose explicit migration to a Godot Resource")
	elif ActionStore.owner("sandbox_chain") == "native" and not migrate_resource.disabled:
		errors.append("already-native action chain still exposed a destructive migration action")
	var graph := workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	var nodes := _graph_nodes(graph)
	var initial_count := nodes.size()
	if graph == null or nodes.size() < 4:
		errors.append("sandbox_chain did not render as action nodes")
	elif graph.connections.size() != nodes.size() - 1:
		errors.append("linear action graph did not connect consecutive steps")
	elif not graph.minimap_enabled or not graph.show_arrange_button:
		errors.append("GraphEdit navigation controls are not enabled")
	if workspace.find_child("ActionChainEditor", true, false) == null:
		errors.append("action graph lost its existing safe property editor")
	elif nodes.size() >= 2:
		workspace.call("_on_node_selected", nodes[1])
		var action_steps := workspace.find_child("ActionSteps", true, false) as VBoxContainer
		if _visible_child_count(action_steps) != 1:
			errors.append("selecting an action node did not isolate its property card")
		var show_all := workspace.find_child("ShowAllGraphCards", true, false) as Button
		show_all.pressed.emit()
		if _visible_child_count(action_steps) != action_steps.get_child_count():
			errors.append("show all did not restore every action card")
		var linked := workspace.find_child("OpenLinkedGraph", true, false) as Button
		if linked == null:
			errors.append("talk node did not expose linked-dialogue navigation")
		else:
			linked.pressed.emit()
			var kind := workspace.find_child("GraphKind", true, false) as OptionButton
			var resource := workspace.find_child("GraphResource", true, false) as OptionButton
			if _selected_metadata(kind) != "dialogue" or _selected_metadata(resource) != "sandbox_notice_talk":
				errors.append("linked-dialogue navigation did not switch graph resources")
	workspace.open_resource("action", "sandbox_chain")
	graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	var add_type := workspace.find_child("GraphAddActionType", true, false) as OptionButton
	_select_option(add_type, "wait")
	(workspace.find_child("GraphAddActionNode", true, false) as Button).pressed.emit()
	if _graph_nodes(graph).size() != initial_count + 1:
		errors.append("graph +Node did not add an action draft step")
	var undo := workspace.find_child("GraphDraftUndo", true, false) as Button
	var redo := workspace.find_child("GraphDraftRedo", true, false) as Button
	undo.pressed.emit()
	if _graph_nodes(graph).size() != initial_count:
		errors.append("local graph undo did not restore the action draft")
	redo.pressed.emit()
	if _graph_nodes(graph).size() != initial_count + 1:
		errors.append("local graph redo did not restore the added node")
	var reordered_nodes := _graph_nodes(graph)
	workspace.call("_on_connection_request", reordered_nodes[0].name, 0, reordered_nodes[-1].name, 0)
	var draft: Dictionary = workspace.get("_action_draft")
	var draft_steps: Array = draft.get("steps", [])
	if str((draft_steps[1] as Dictionary).get("type", "")) != "wait":
		errors.append("dragged action connection did not reorder target after source")
	(workspace.find_child("GraphDeleteActionNodes", true, false) as Button).pressed.emit()
	if _graph_nodes(graph).size() != initial_count:
		errors.append("Delete did not remove the selected action node from draft")
	undo = workspace.find_child("GraphDraftUndo", true, false) as Button
	undo.pressed.emit()
	if _graph_nodes(graph).size() != initial_count + 1:
		errors.append("local undo did not restore a deleted action node")


func _test_node_palette(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	workspace.open_resource("dialogue", "sandbox_branch")
	var graph := workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	workspace.call("_on_graph_popup_request", Vector2(500.0, 300.0))
	var search := workspace.find_child("GraphNodePaletteSearch", true, false) as LineEdit
	var items := workspace.find_child("GraphNodePaletteList", true, false) as ItemList
	if search == null or items == null or items.item_count != 5:
		errors.append("dialogue right-click palette did not list authoring node types")
		return
	search.text = "флаг"
	search.text_changed.emit(search.text)
	if items.item_count != 1 or str(items.get_item_metadata(0)) != "set_flag":
		errors.append("node palette search did not filter by localized type name")
	else:
		items.item_activated.emit(0)
		var draft: Dictionary = workspace.get("_dialogue_draft")
		var steps: Array = draft.get("steps", [])
		var added: Dictionary = steps[-1]
		var position: Dictionary = draft.get("editorLayout", {}).get(str(added.get("id", "")), {})
		if str(added.get("type", "")) != "set_flag":
			errors.append("palette activated the wrong dialogue node type")
		if not is_equal_approx(float(position.get("x", 0.0)), 500.0):
			errors.append("right-click palette lost the requested graph position")
	(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
	graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	var agent := _node_for_step(graph, "agent_r")
	workspace.call("_on_connection_to_empty", agent.name, 0, Vector2(460.0, 360.0))
	_select_palette_type(items, "end")
	var dialogue_draft: Dictionary = workspace.get("_dialogue_draft")
	var dialogue_steps: Array = dialogue_draft.get("steps", [])
	var wire_target_id := str((dialogue_steps[-1] as Dictionary).get("id", ""))
	var updated_agent: Dictionary = DialogueGraphModel.steps_by_id(dialogue_draft).get("agent_r", {})
	if str(updated_agent.get("next", "")) != wire_target_id:
		errors.append("connection-to-empty did not wire source to the created dialogue node")
	(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
	graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	var end_node := _node_for_step(graph, "end")
	workspace.call("_on_connection_from_empty", end_node.name, 0, Vector2(520.0, 380.0))
	items = workspace.find_child("GraphNodePaletteList", true, false) as ItemList
	if items.item_count != 4:
		errors.append("input-to-empty palette offered an end node without an output")
	_select_palette_type(items, "set_flag")
	dialogue_draft = workspace.get("_dialogue_draft")
	dialogue_steps = dialogue_draft.get("steps", [])
	var inserted_flag: Dictionary = dialogue_steps[-1]
	if str(inserted_flag.get("next", "")) != "end":
		errors.append("connection-from-empty did not wire created dialogue node to target")
	(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
	workspace.open_resource("action", "sandbox_chain")
	graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	var initial_action_count := _graph_nodes(graph).size()
	workspace.call("_on_connection_to_empty", _graph_nodes(graph)[0].name, 0, Vector2(420.0, 260.0))
	items = workspace.find_child("GraphNodePaletteList", true, false) as ItemList
	_select_palette_type(items, "wait")
	var action_steps: Array = (workspace.get("_action_draft") as Dictionary).get("steps", [])
	if action_steps.size() != initial_action_count + 1 or str((action_steps[1] as Dictionary).get("type", "")) != "wait":
		errors.append("action wire palette did not insert the new step after its source")
	(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()


func _test_action_duplicate(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	workspace.open_resource("action", "sandbox_chain")
	var graph := workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	var nodes := _graph_nodes(graph)
	var initial_count := nodes.size()
	nodes[0].selected = true
	nodes[1].selected = true
	workspace.call("_on_node_selected", nodes[1])
	(workspace.find_child("GraphDuplicateNodes", true, false) as Button).pressed.emit()
	var steps: Array = (workspace.get("_action_draft") as Dictionary).get("steps", [])
	if steps.size() != initial_count + 2:
		errors.append("action duplicate did not insert all selected steps")
	elif str((steps[2] as Dictionary).get("type", "")) != str((steps[0] as Dictionary).get("type", "")):
		errors.append("action duplicate changed copied step order")
	(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
	if (workspace.get("_action_draft") as Dictionary).get("steps", []).size() != initial_count:
		errors.append("local Undo did not remove duplicated action block")


func _test_action_clipboard(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	workspace.open_resource("action", TEMP_SCRIPT_ID)
	var graph := workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	var nodes := _graph_nodes(graph)
	var initial_steps: Array = (workspace.get("_action_draft") as Dictionary).get("steps", [])
	var initial_count := initial_steps.size()
	var first_type := str((initial_steps[0] as Dictionary).get("type", ""))
	var second_type := str((initial_steps[1] as Dictionary).get("type", ""))
	nodes[0].selected = true
	nodes[1].selected = true
	workspace.call("_on_node_selected", nodes[1])
	workspace.call("_copy_selected_nodes")
	var clipboard: Dictionary = workspace.get("_node_clipboard")
	if str(clipboard.get("kind", "")) != "action" or clipboard.get("steps", []).size() != 2:
		errors.append("action Ctrl+C did not capture the selected ordered block")
		return
	workspace.call("_paste_nodes")
	var steps: Array = (workspace.get("_action_draft") as Dictionary).get("steps", [])
	if steps.size() != initial_count + 2:
		errors.append("action Ctrl+V did not insert the copied block")
		return
	if str((steps[2] as Dictionary).get("type", "")) != first_type or str((steps[3] as Dictionary).get("type", "")) != second_type:
		errors.append("action Ctrl+V changed copied order or inserted at the wrong position")
	workspace.call("_cut_selected_nodes")
	if (workspace.get("_action_draft") as Dictionary).get("steps", []).size() != initial_count:
		errors.append("action Ctrl+X did not remove the selected pasted block")
	workspace.call("_paste_nodes")
	if (workspace.get("_action_draft") as Dictionary).get("steps", []).size() != initial_count + 2:
		errors.append("action clipboard was lost after Ctrl+X")
	var undo_event := InputEventKey.new()
	undo_event.keycode = KEY_Z
	undo_event.ctrl_pressed = true
	undo_event.pressed = true
	workspace.call("_input", undo_event)
	if (workspace.get("_action_draft") as Dictionary).get("steps", []).size() != initial_count:
		errors.append("Ctrl+Z did not revert one action paste")
	var redo_event := InputEventKey.new()
	redo_event.keycode = KEY_Z
	redo_event.ctrl_pressed = true
	redo_event.shift_pressed = true
	redo_event.pressed = true
	workspace.call("_input", redo_event)
	if (workspace.get("_action_draft") as Dictionary).get("steps", []).size() != initial_count + 2:
		errors.append("Ctrl+Shift+Z did not restore one action paste")
	workspace.call("_input", undo_event)


func _test_dialogue_graph(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	workspace.open_resource("dialogue", "sandbox_branch")
	var graph := workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	if _graph_nodes(graph).size() != 4:
		errors.append("sandbox_branch did not render all four graph steps")
	elif graph.connections.size() != 4:
		errors.append("choice graph did not render both branch and convergence edges")
	if workspace.find_child("DialogueEditor", true, false) == null:
		errors.append("dialogue graph lost its existing card property editor")
	else:
		for node in _graph_nodes(graph):
			if str(node.get_meta("step_id", "")) == "agent_r":
				workspace.call("_on_node_selected", node)
				break
		var dialogue_cards := workspace.find_child("DialogueCards", true, false) as VBoxContainer
		var selected_label := workspace.find_child("GraphSelectionLabel", true, false) as Label
		if _visible_child_count(dialogue_cards) != 1 or not selected_label.text.contains("agent_r"):
			errors.append("reply-node selection did not focus its parent choice card")
	var choice_node := _node_for_step(graph, "ask")
	if choice_node == null or choice_node.get_output_port_count() != 2:
		errors.append("choice did not expose one named output port per answer")
	elif choice_node.find_child("ChoicePort_0", true, false) == null or choice_node.find_child("ChoicePort_1", true, false) == null:
		errors.append("choice output rows lost their visible answer labels")
	else:
		var walk_node := _node_for_step(graph, "walk_r")
		var agent_node := _node_for_step(graph, "agent_r")
		workspace.call("_on_connection_request", choice_node.name, 0, walk_node.name, 0)
		var draft: Dictionary = workspace.get("_dialogue_draft")
		var options: Array = (DialogueGraphModel.steps_by_id(draft)["ask"] as Dictionary).get("options", [])
		if str((options[0] as Dictionary).get("next", "")) != "walk_r":
			errors.append("choice port 0 did not update its own options[].next")
		var save := workspace.find_child("SaveDialogueGraph", true, false) as Button
		if save == null or not save.disabled:
			errors.append("duplicate choice target did not block graph save as an unreachable branch")
		graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
		choice_node = _node_for_step(graph, "ask")
		agent_node = _node_for_step(graph, "agent_r")
		workspace.call("_on_connection_request", choice_node.name, 1, agent_node.name, 0)
		draft = workspace.get("_dialogue_draft")
		options = (DialogueGraphModel.steps_by_id(draft)["ask"] as Dictionary).get("options", [])
		if str((options[1] as Dictionary).get("next", "")) != "agent_r":
			errors.append("choice port 1 did not retain its independent target")
		if not DialogueStore.graph_validation_errors(draft).is_empty():
			errors.append("valid swapped choice branches failed graph validation")
		var undo := workspace.find_child("GraphDraftUndo", true, false) as Button
		var redo := workspace.find_child("GraphDraftRedo", true, false) as Button
		undo.pressed.emit()
		if DialogueStore.graph_validation_errors(workspace.get("_dialogue_draft")).is_empty():
			errors.append("dialogue draft undo did not restore the invalid intermediate branch")
		redo.pressed.emit()
		if not DialogueStore.graph_validation_errors(workspace.get("_dialogue_draft")).is_empty():
			errors.append("dialogue draft redo did not restore the valid branch graph")
		graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
		choice_node = _node_for_step(graph, "ask")
		workspace.call("_on_disconnection_request", choice_node.name, 0, StringName(), 0)
		if DialogueStore.graph_validation_errors(workspace.get("_dialogue_draft")).is_empty():
			errors.append("disconnected named choice output was not diagnosed")
		(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
		graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
		agent_node = _node_for_step(graph, "agent_r")
		var moved_position := Vector2(777.0, 333.0)
		agent_node.position_offset = moved_position
		graph.zoom = 1.25
		graph.scroll_offset = Vector2(180.0, 70.0)
		var expected_scroll := graph.scroll_offset
		workspace.call("_capture_view_state")
		workspace.call("_apply_dialogue_draft", workspace.get("_dialogue_draft"))
		graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
		agent_node = _node_for_step(graph, "agent_r")
		if not agent_node.position_offset.is_equal_approx(moved_position):
			errors.append("dialogue node position reset during graph rebuild")
		if not is_equal_approx(graph.zoom, 1.25) or not graph.scroll_offset.is_equal_approx(expected_scroll):
			errors.append("graph camera reset during dialogue draft rebuild")
		var saved_documents: Array[Dictionary] = []
		workspace.dialogue_save_requested.connect(func(document: Dictionary) -> void:
			saved_documents.append(document.duplicate(true))
		, CONNECT_ONE_SHOT)
		(workspace.find_child("SaveDialogueGraph", true, false) as Button).pressed.emit()
		if saved_documents.is_empty():
			errors.append("valid dialogue graph did not emit save after moving nodes")
		else:
			var saved_layout: Dictionary = saved_documents[0].get("editorLayout", {})
			var saved_agent: Dictionary = saved_layout.get("agent_r", {})
			if not is_equal_approx(float(saved_agent.get("x", 0.0)), moved_position.x) or not is_equal_approx(float(saved_agent.get("y", 0.0)), moved_position.y):
				errors.append("saved dialogue graph lost moved editorLayout position")


func _test_complex_read_only(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	workspace.open_resource("dialogue", "hu_tao_clear_demo")
	var graph := workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	if _graph_nodes(graph).is_empty():
		errors.append("complex VN scene disappeared instead of rendering read-only")
	if workspace.find_child("DialogueUnsupported", true, false) == null:
		errors.append("complex VN graph did not preserve the explicit read-only guard")
	if workspace.find_child("SaveDialogue", true, false) != null:
		errors.append("complex VN graph exposed a destructive save button")
	var document := DialogueStore.document("hu_tao_clear_demo")
	var swapped := DialogueGraphModel.replace_edge(document, "choice", 0, "fluster_reply")
	swapped = DialogueGraphModel.replace_edge(swapped, "choice", 1, "brave_reply")
	var intro: Dictionary = DialogueGraphModel.steps_by_id(swapped).get("intro", {})
	# bgArtId is an optional per-node override now that a VN scene can own one
	# default background. Structural mutations must preserve the required actor
	# identity fields without inventing an override that the author removed.
	if not intro.has("actors") or not intro.has("portraitSide"):
		errors.append("structural graph mutation stripped complex VN node fields")
	if str(swapped.get("defaultBgArtId", "")) != str(document.get("defaultBgArtId", "")):
		errors.append("structural graph mutation stripped the VN scene background")
	if not DialogueStore.graph_validation_errors(swapped).is_empty():
		errors.append("valid complex VN branch swap failed canonical graph validation")


func _test_inline_dialogue_fields(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	workspace.open_resource("dialogue", "sandbox_branch")
	var overview_name := workspace.find_child("DialogueName", true, false) as LineEdit
	if overview_name != null and overview_name.editable:
		errors.append("right dialogue overview remained editable beside inline node fields")
	var graph := workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	var agent_node := _node_for_step(graph, "agent_r")
	var text_input := agent_node.find_child("Inline_agent_r_textRu", true, false) as TextEdit
	if text_input == null:
		errors.append("dialogue node did not expose its text as an inline editor")
	else:
		var old_text := text_input.text
		text_input.focus_entered.emit()
		text_input.text = "Inline graph text"
		text_input.text_changed.emit()
		text_input.focus_exited.emit()
		var draft: Dictionary = workspace.get("_dialogue_draft")
		if str((DialogueGraphModel.steps_by_id(draft)["agent_r"] as Dictionary).get("textRu", "")) != "Inline graph text":
			errors.append("inline dialogue text did not update canonical draft")
		(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
		draft = workspace.get("_dialogue_draft")
		if str((DialogueGraphModel.steps_by_id(draft)["agent_r"] as Dictionary).get("textRu", "")) != old_text:
			errors.append("local Undo did not restore an inline dialogue edit")
	graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	var choice := _node_for_step(graph, "ask")
	var option_input := choice.find_child("InlineChoiceLabel_0", true, false) as LineEdit
	if option_input == null:
		errors.append("choice node did not expose answer labels inline")
	else:
		option_input.focus_entered.emit()
		option_input.text = "Новый ответ"
		option_input.text_changed.emit(option_input.text)
		option_input.focus_exited.emit()
		var draft: Dictionary = workspace.get("_dialogue_draft")
		var options: Array = (DialogueGraphModel.steps_by_id(draft)["ask"] as Dictionary).get("options", [])
		if str((options[0] as Dictionary).get("labelRu", "")) != "Новый ответ":
			errors.append("inline choice label updated the wrong field")
	var with_flag := DialogueGraphModel.add_step(
		workspace.get("_dialogue_draft"), "set_flag", Vector2(1180.0, 320.0)
	)
	var flag_steps: Array = with_flag.get("steps", [])
	var flag_id := str((flag_steps[-1] as Dictionary).get("id", ""))
	workspace.call("_push_dialogue_draft", with_flag)
	var flag_input := workspace.find_child("Inline_%s_flag" % flag_id, true, false) as LineEdit
	var flag_library := workspace.find_child("Inline_%s_flag_library" % flag_id, true, false) as Button
	if flag_input == null or flag_library == null:
		errors.append("set_flag node did not expose the quest flag reference library")
	else:
		workspace.call("_apply_inline_quest_flag", "sandbox_notice_read", flag_id, flag_input)
		var picked_flag: Dictionary = DialogueGraphModel.steps_by_id(workspace.get("_dialogue_draft")).get(flag_id, {})
		if str(picked_flag.get("flag", "")) != "sandbox_notice_read":
			errors.append("quest flag library updated the wrong graph field")
		(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
		picked_flag = DialogueGraphModel.steps_by_id(workspace.get("_dialogue_draft")).get(flag_id, {})
		if str(picked_flag.get("flag", "")) != "new_flag":
			errors.append("local Undo did not restore a quest flag library choice")
	var bool_input := workspace.find_child("InlineFlagValue_bool", true, false) as OptionButton
	if bool_input == null:
		errors.append("set_flag node did not expose the shared typed value editor inline")
	else:
		bool_input.focus_entered.emit()
		bool_input.select(1)
		bool_input.item_selected.emit(1)
		bool_input.focus_exited.emit()
		var flag_step: Dictionary = DialogueGraphModel.steps_by_id(workspace.get("_dialogue_draft")).get(flag_id, {})
		if flag_step.get("value", true) != false:
			errors.append("inline typed flag editor did not update canonical draft")
		(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
		flag_step = DialogueGraphModel.steps_by_id(workspace.get("_dialogue_draft")).get(flag_id, {})
		if flag_step.get("value", false) != true:
			errors.append("local Undo did not restore an inline typed flag edit")


func _test_vn_properties(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	workspace.open_resource("dialogue", "hu_tao_clear_demo")
	var storage_owner := workspace.find_child("DialogueStorageOwner", true, false) as Label
	var migrate_resource := workspace.find_child("MigrateDialogueResource", true, false) as Button
	if storage_owner == null or migrate_resource == null:
		errors.append("dialogue scene did not expose its canonical storage owner/migration action")
	elif DialogueStore.owner("hu_tao_clear_demo") == "legacy" and migrate_resource.disabled:
		errors.append("legacy dialogue did not expose explicit migration to a Godot Resource")
	elif DialogueStore.owner("hu_tao_clear_demo") == "native" and not migrate_resource.disabled:
		errors.append("already-native dialogue still exposed a destructive migration action")
	var default_bg := workspace.find_child("DialogueDefaultBgArtId", true, false) as OptionButton
	var default_bg_preview := workspace.find_child(
		"DialogueDefaultBgArtId_preview", true, false
	) as TextureRect
	if default_bg == null or _selected_metadata(default_bg).is_empty():
		errors.append("VN scene did not expose canonical defaultBgArtId")
	elif _option_has_metadata(default_bg, "hu_tao_bunny_tease"):
		errors.append("background picker leaked portrait-kind arts into its choices")
	if default_bg_preview == null:
		errors.append("VN background picker lost its safe adjacent visual preview")
	if default_bg != null and default_bg.fit_to_longest_item:
		errors.append("VN background picker can still widen the editor sidebar")
	if workspace.find_child("DialogueDefaultBgArtId_import", true, false) == null:
		errors.append("VN background picker did not expose project import")
	if workspace.find_child("DialogueDefaultBgArtId_library", true, false) == null:
		errors.append("VN background picker did not expose the shared visual library")
	if workspace.find_child("OpenVnBackgroundFolder", true, false) == null:
		errors.append("VN scene did not explain where native backgrounds live")
	var inherit_all := workspace.find_child("InheritSceneBackgroundAll", true, false) as Button
	if inherit_all == null:
		errors.append("VN scene did not expose one-action background inheritance migration")
	else:
		var before_count := DialogueGraphModel.background_override_count(
			workspace.get("_dialogue_draft")
		)
		var injected_override := before_count == 0
		if injected_override:
			var with_override := DialogueGraphModel.set_step_field(
				workspace.get("_dialogue_draft"),
				"intro",
				"bgArtId",
				str((workspace.get("_dialogue_draft") as Dictionary).get("defaultBgArtId", ""))
			)
			workspace.call("_push_dialogue_draft", with_override)
			before_count = DialogueGraphModel.background_override_count(
				workspace.get("_dialogue_draft")
			)
			inherit_all = workspace.find_child("InheritSceneBackgroundAll", true, false) as Button
		if inherit_all == null or inherit_all.disabled:
			errors.append("VN scene background migration stayed disabled with a node override")
			return
		inherit_all.pressed.emit()
		var inherited_draft: Dictionary = workspace.get("_dialogue_draft")
		if DialogueGraphModel.background_override_count(inherited_draft) != 0:
			errors.append("scene background migration did not clear node overrides")
		var inherited_graph := workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
		var inherited_intro := _node_for_step(inherited_graph, "intro")
		var inherited_picker := inherited_intro.find_child(
			"Inline_intro_bgArtId", true, false
		) as OptionButton
		if _selected_metadata(inherited_picker) != "" or not inherited_picker.get_item_text(0).contains(
			"Фон сцены"
		):
			errors.append("node picker did not explain inherited scene background")
		(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
		if DialogueGraphModel.background_override_count(workspace.get("_dialogue_draft")) != before_count:
			errors.append("Undo did not restore per-node background overrides")
		if injected_override:
			(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
	var graph := workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	var intro := _node_for_step(graph, "intro")
	var side := intro.find_child("Inline_intro_portraitSide", true, false) as OptionButton
	var bg := intro.find_child("Inline_intro_bgArtId", true, false) as OptionButton
	var speaker := intro.find_child("Inline_intro_speaker", true, false) as OptionButton
	var portrait := intro.find_child("Inline_intro_portraitKey", true, false) as OptionButton
	var speaker_preview := intro.find_child("Inline_intro_speaker_preview", true, false) as TextureRect
	var portrait_preview := intro.find_child("Inline_intro_portraitKey_preview", true, false) as TextureRect
	if side == null or str(side.get_item_metadata(side.selected)) != "right":
		errors.append("dialogue node did not expose canonical portraitSide")
	if bg == null:
		errors.append("dialogue node did not expose its background override picker")
	elif _selected_metadata(bg).is_empty() and not bg.get_item_text(0).contains("Фон сцены"):
		errors.append("dialogue node did not explain its inherited scene background")
	if _selected_metadata(speaker) != "hu_tao" or _selected_metadata(portrait) != "bunny_tease":
		errors.append("dialogue identity did not resolve speaker/portrait registries")
	if speaker_preview == null or portrait_preview == null:
		errors.append("dialogue identity picker lost its safe adjacent visual previews")
	if intro.find_child("Inline_intro_speaker_library", true, false) == null:
		errors.append("dialogue speaker did not expose the shared visual library")
	if intro.find_child("Inline_intro_portraitKey_library", true, false) == null:
		errors.append("dialogue expression did not expose the shared visual library")
	if intro.find_child("Inline_intro_portraitKey_import", true, false) == null:
		errors.append("dialogue identity did not expose native portrait import")
	else:
		_select_option(portrait, "bunny_shy")
		portrait.item_selected.emit(portrait.selected)
		var identity_step: Dictionary = DialogueGraphModel.steps_by_id(workspace.get("_dialogue_draft")).get("intro", {})
		var identity_actors: Array = identity_step.get("actors", [])
		if str(identity_step.get("portraitKey", "")) != "bunny_shy" or str((identity_actors[0] as Dictionary).get("portraitKey", "")) != "bunny_shy":
			errors.append("portrait picker did not synchronize dialogue and primary actor identity")
		(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
		graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
		intro = _node_for_step(graph, "intro")
	var actor_toggle := intro.find_child("InlineActorToggle_intro", true, false) as Button
	if actor_toggle == null:
		errors.append("VN dialogue node did not expose staged actor controls")
		return
	actor_toggle.button_pressed = true
	actor_toggle.toggled.emit(true)
	var actor_speaker := intro.find_child("InlineActor_intro_speaker", true, false) as OptionButton
	var actor_portrait := intro.find_child("InlineActor_intro_portraitKey", true, false) as OptionButton
	if _selected_metadata(actor_speaker) != "hu_tao" or _selected_metadata(actor_portrait) != "bunny_tease":
		errors.append("staged actor identity did not use portrait picker controls")
	var actor_x := intro.find_child("InlineActor_intro_x", true, false) as SpinBox
	if actor_x == null:
		errors.append("staged actor editor did not expose actor position")
	else:
		actor_x.focus_entered.emit()
		actor_x.value = 61.5
		actor_x.value_changed.emit(61.5)
		actor_x.get_line_edit().focus_exited.emit()
		var step: Dictionary = DialogueGraphModel.steps_by_id(workspace.get("_dialogue_draft")).get("intro", {})
		var actors: Array = step.get("actors", [])
		var actor: Dictionary = actors[0] if not actors.is_empty() else {}
		if not is_equal_approx(float(actor.get("x", 0.0)), 61.5):
			errors.append("inline staged actor position did not update canonical actors[0]")
		if not bool(actor.get("lockY", false)) or not actor.has("floorY"):
			errors.append("staged actor edit stripped unknown/advanced actor fields")
		(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
		step = DialogueGraphModel.steps_by_id(workspace.get("_dialogue_draft")).get("intro", {})
		actors = step.get("actors", [])
		if actors.is_empty() or not is_equal_approx(float((actors[0] as Dictionary).get("x", 0.0)), 50.0):
			errors.append("Undo did not restore staged actor position")
	workspace.open_resource("dialogue", "sandbox_branch")
	graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	var agent := _node_for_step(graph, "agent_r")
	actor_toggle = agent.find_child("InlineActorToggle_agent_r", true, false) as Button
	actor_toggle.button_pressed = true
	actor_toggle.toggled.emit(true)
	var add_actor := agent.find_child("InlineActorAdd_agent_r", true, false) as Button
	if add_actor == null:
		errors.append("plain dialogue node did not offer a staged actor")
	else:
		add_actor.pressed.emit()
		var agent_step: Dictionary = DialogueGraphModel.steps_by_id(workspace.get("_dialogue_draft")).get("agent_r", {})
		if (agent_step.get("actors", []) as Array).size() != 1:
			errors.append("add actor did not create canonical actors[0]")
		(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
	var with_splash := DialogueGraphModel.add_step(
		workspace.get("_dialogue_draft"), "splash", Vector2(900.0, 500.0)
	)
	var splash_steps: Array = with_splash.get("steps", [])
	if str((splash_steps[-1] as Dictionary).get("type", "")) != "splash":
		errors.append("dialogue palette/model still cannot author canonical splash nodes")


func _test_live_vn_preview(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	workspace.open_resource("dialogue", "hu_tao_clear_demo")
	var open := workspace.find_child("OpenVnPreview", true, false) as Button
	if open == null or open.disabled:
		errors.append("dialogue workspace did not expose live scene preview")
		return
	open.pressed.emit()
	await process_frame
	await process_frame
	var preview := workspace.find_child("EmberVnPreview", true, false) as EmberVnPreview
	if preview == null:
		errors.append("live scene preview window did not create its renderer")
		return
	var actor_layer := preview.find_child("VnPreviewActors", true, false) as Control
	var dialogue_layer := preview.find_child("VnPreviewDialoguePanel", true, false) as PanelContainer
	if actor_layer == null or dialogue_layer == null or actor_layer.z_index >= dialogue_layer.z_index:
		errors.append("VN portraits can cover the dialogue text layer")
	if preview.get("_assets") != workspace.get("_vn_assets"):
		errors.append("picker and live preview do not share one decoded-image cache")
	var document := DialogueStore.document("hu_tao_clear_demo")
	document["defaultBgArtId"] = "hu_tao_clear_placeholder"
	document = DialogueGraphModel.set_step_field(document, "intro", "bgArtId", "")
	preview.set_document(document, "intro")
	var state := preview.view_state()
	if str(state.get("kind", "")) != "dialogue" or int(state.get("actorCount", 0)) != 1:
		errors.append("VN preview did not render the selected dialogue actor state")
	if str(state.get("bgArtId", "")) != "hu_tao_clear_placeholder":
		errors.append("empty node bgArtId did not inherit defaultBgArtId in shared scene state")
	var assets := EmberVnAssets.new()
	if not FileAccess.file_exists(assets.art_path("hu_tao_clear_placeholder")):
		errors.append("VN preview could not resolve a valid pack art registry path")
	preview.advance()
	state = preview.view_state()
	if str(state.get("kind", "")) != "choice" or int(state.get("choiceCount", 0)) != 2:
		errors.append("VN preview did not traverse dialogue into canonical choice")
	preview.choose(0)
	if preview.current_step_id() != "brave_reply":
		errors.append("VN preview choice did not follow options[].next")
	preview.back()
	if preview.current_step_id() != "choice":
		errors.append("VN preview history did not restore the previous node")
	workspace.open_resource("dialogue", "sandbox_branch")
	preview = workspace.find_child("EmberVnPreview", true, false) as EmberVnPreview
	state = preview.view_state()
	if str(state.get("kind", "")) != "choice" or int(state.get("actorCount", -1)) != 0:
		errors.append("text-only scene did not refresh in the same preview renderer")
	var graph := workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	workspace.call("_on_node_selected", _node_for_step(graph, "agent_r"))
	workspace.call("_set_inline_step_value", "agent_r", "textRu", "Live unsaved line")
	state = preview.view_state()
	if str(state.get("stepId", "")) != "agent_r" or str(state.get("body", "")) != "Live unsaved line":
		errors.append("VN preview did not update from the unsaved graph draft")
	(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()


func _test_dialogue_groups(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	workspace.open_resource("dialogue", "sandbox_branch")
	var graph := workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	var agent := _node_for_step(graph, "agent_r")
	var walk := _node_for_step(graph, "walk_r")
	agent.selected = true
	walk.selected = true
	workspace.call("_on_node_selected", walk)
	var group_name := workspace.find_child("GraphGroupName", true, false) as LineEdit
	group_name.text = "Ответы игрока"
	(workspace.find_child("GraphCreateGroup", true, false) as Button).pressed.emit()
	var draft: Dictionary = workspace.get("_dialogue_draft")
	var groups: Array = draft.get("editorGroups", [])
	if groups.size() != 1:
		errors.append("selected dialogue nodes did not create one editorGroup")
		return
	var members: Array = (groups[0] as Dictionary).get("members", [])
	if "agent_r" not in members or "walk_r" not in members:
		errors.append("editorGroup lost one of the selected member nodes")
	graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	var frame := _first_graph_frame(graph)
	if frame == null or graph.get_attached_nodes_of_frame(frame.name).size() != 2:
		errors.append("editorGroup did not render as a native GraphFrame with attached nodes")
	else:
		workspace.call("_on_node_selected", frame)
		group_name = workspace.find_child("GraphGroupName", true, false) as LineEdit
		group_name.text_submitted.emit("Ветка ответа")
		groups = (workspace.get("_dialogue_draft") as Dictionary).get("editorGroups", [])
		if str((groups[0] as Dictionary).get("title", "")) != "Ветка ответа":
			errors.append("GraphFrame rename did not update editorGroups")
		graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
		frame = _first_graph_frame(graph)
		var toggle := frame.find_child("ToggleGraphGroup_group_1", true, false) as Button
		if toggle == null:
			errors.append("GraphFrame titlebar did not expose collapse control")
		else:
			toggle.pressed.emit()
			groups = (workspace.get("_dialogue_draft") as Dictionary).get("editorGroups", [])
			if not bool((groups[0] as Dictionary).get("collapsed", false)):
				errors.append("collapse control did not persist editor-only group state")
			graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
			if _node_for_step(graph, "agent_r") != null or _node_for_step(graph, "walk_r") != null:
				errors.append("collapsed GraphFrame kept member GraphNodes and their invalid port cache alive")
			var compact := _group_element(graph, "group_1") as GraphNode
			if compact == null:
				errors.append("collapsed group did not render a compact proxy node")
				return
			if compact.size.x > 380.0 or compact.size.y > 120.0:
				errors.append("collapsed group proxy did not shrink to compact size")
			if compact.get_input_port_count() < 1 or compact.get_output_port_count() < 1:
				errors.append("collapsed group proxy lost its external input/output ports")
			var proxy_connections := 0
			for connection in graph.connections:
				if connection.get("from_node") == compact.name or connection.get("to_node") == compact.name:
					proxy_connections += 1
			if proxy_connections < 2:
				errors.append("collapsed group proxy did not preserve boundary wires")
			var before_move: Dictionary = (
				(workspace.get("_dialogue_draft") as Dictionary).get("editorLayout", {}).get("agent_r", {})
			)
			compact.position_offset += Vector2(40.0, 20.0)
			workspace.call("_on_end_node_move")
			var after_move: Dictionary = (
				(workspace.get("_dialogue_draft") as Dictionary).get("editorLayout", {}).get("agent_r", {})
			)
			if not is_equal_approx(float(after_move.get("x", 0.0)), float(before_move.get("x", 0.0)) + 40.0):
				errors.append("moving collapsed GraphFrame did not move member editorLayout")
			graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
			compact = _group_element(graph, "group_1") as GraphNode
			(compact.find_child("ToggleGraphGroup_group_1", true, false) as Button).pressed.emit()
			graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
			if _node_for_step(graph, "agent_r") == null or _node_for_step(graph, "ask") == null:
				errors.append("expand control did not restore member GraphNodes")
		graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
		frame = _first_graph_frame(graph)
		var ask := _node_for_step(graph, "ask")
		workspace.call("_on_graph_elements_linked_to_frame_request", [ask], frame.name)
		groups = (workspace.get("_dialogue_draft") as Dictionary).get("editorGroups", [])
		members = (groups[0] as Dictionary).get("members", [])
		if "ask" not in members:
			errors.append("dropping a dialogue node onto GraphFrame did not persist membership")
		workspace.call("_show_all_cards")
		graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
		ask = _node_for_step(graph, "ask")
		ask.selected = true
		workspace.call("_on_node_selected", ask)
		(workspace.find_child("GraphRemoveGroup", true, false) as Button).pressed.emit()
		groups = (workspace.get("_dialogue_draft") as Dictionary).get("editorGroups", [])
		members = (groups[0] as Dictionary).get("members", [])
		if "ask" in members or "agent_r" not in members:
			errors.append("remove-from-group deleted the frame or wrong members")
		(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
		graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
		frame = _first_graph_frame(graph)
		workspace.call("_on_node_selected", frame)
		(workspace.find_child("GraphRemoveGroup", true, false) as Button).pressed.emit()
		if not (workspace.get("_dialogue_draft") as Dictionary).get("editorGroups", []).is_empty():
			errors.append("Ungroup did not remove editor-only frame metadata")
		(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
		if (workspace.get("_dialogue_draft") as Dictionary).get("editorGroups", []).is_empty():
			errors.append("local Undo did not restore removed dialogue group")


func _test_dialogue_duplicate(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	workspace.open_resource("dialogue", "sandbox_branch")
	var graph := workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	for step_id in ["ask", "agent_r", "walk_r"]:
		_node_for_step(graph, step_id).selected = true
	workspace.call("_on_node_selected", _node_for_step(graph, "walk_r"))
	var duplicate := workspace.find_child("GraphDuplicateNodes", true, false) as Button
	if duplicate == null or duplicate.disabled:
		errors.append("selected dialogue branch did not enable duplicate command")
		return
	duplicate.pressed.emit()
	var draft: Dictionary = workspace.get("_dialogue_draft")
	var steps: Array = draft.get("steps", [])
	if steps.size() != 7:
		errors.append("dialogue duplicate did not append all selected steps")
		return
	var choice_copy: Dictionary = steps[4]
	var agent_copy: Dictionary = steps[5]
	var walk_copy: Dictionary = steps[6]
	var options: Array = choice_copy.get("options", [])
	if str((options[0] as Dictionary).get("next", "")) != str(agent_copy.get("id", "")):
		errors.append("dialogue duplicate did not remap first internal choice edge")
	if str((options[1] as Dictionary).get("next", "")) != str(walk_copy.get("id", "")):
		errors.append("dialogue duplicate did not remap second internal choice edge")
	if str(agent_copy.get("next", "")) != "end" or str(walk_copy.get("next", "")) != "end":
		errors.append("dialogue duplicate changed shared external continuation")
	var layout: Dictionary = draft.get("editorLayout", {})
	var copied_position: Dictionary = layout.get(str(choice_copy.get("id", "")), {})
	if not is_equal_approx(float(copied_position.get("x", 0.0)), 100.0):
		errors.append("dialogue duplicate did not offset copied editorLayout")
	graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	var selected_copies := 0
	for graph_node in _graph_nodes(graph):
		if graph_node.selected:
			selected_copies += 1
	if selected_copies != 3:
		errors.append("dialogue duplicate did not select the new branch")
	(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
	if (workspace.get("_dialogue_draft") as Dictionary).get("steps", []).size() != 4:
		errors.append("local Undo did not remove duplicated dialogue branch")


func _test_dialogue_clipboard(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	workspace.open_resource("dialogue", "sandbox_branch")
	var graph := workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	for step_id in ["ask", "agent_r", "walk_r"]:
		_node_for_step(graph, step_id).selected = true
	workspace.call("_on_node_selected", _node_for_step(graph, "walk_r"))
	workspace.call("_copy_selected_nodes")
	var clipboard: Dictionary = workspace.get("_node_clipboard")
	if str(clipboard.get("kind", "")) != "dialogue" or clipboard.get("steps", []).size() != 3:
		errors.append("dialogue Ctrl+C did not capture the selected branch")
		return
	workspace.call("_paste_nodes")
	var draft: Dictionary = workspace.get("_dialogue_draft")
	var steps: Array = draft.get("steps", [])
	if steps.size() != 7:
		errors.append("dialogue Ctrl+V did not append the selected branch")
		return
	var choice_copy: Dictionary = steps[4]
	var agent_copy: Dictionary = steps[5]
	var walk_copy: Dictionary = steps[6]
	var options: Array = choice_copy.get("options", [])
	if str((options[0] as Dictionary).get("next", "")) != str(agent_copy.get("id", "")):
		errors.append("dialogue clipboard did not remap its first internal edge")
	if str((options[1] as Dictionary).get("next", "")) != str(walk_copy.get("id", "")):
		errors.append("dialogue clipboard did not remap its second internal edge")
	workspace.call("_cut_selected_nodes")
	if (workspace.get("_dialogue_draft") as Dictionary).get("steps", []).size() != 4:
		errors.append("dialogue Ctrl+X did not remove the pasted branch")
	workspace.call("_paste_nodes")
	if (workspace.get("_dialogue_draft") as Dictionary).get("steps", []).size() != 7:
		errors.append("dialogue clipboard was lost after Ctrl+X")
	(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
	if (workspace.get("_dialogue_draft") as Dictionary).get("steps", []).size() != 4:
		errors.append("one local Undo did not revert one dialogue paste")
	var destination := {
		"id": "clipboard_destination",
		"nameRu": "Clipboard destination",
		"startStepId": "root",
		"steps": [{"id": "root", "type": "end"}],
	}
	var single_payload := DialogueGraphModel.copy_steps(
		DialogueStore.document("sandbox_branch"), ["agent_r"]
	)
	var cross_resource := DialogueGraphModel.paste_steps(
		destination, single_payload, Vector2(100.0, 100.0)
	)
	var cross_steps: Array = (cross_resource.get("document", {}) as Dictionary).get("steps", [])
	if cross_steps.size() != 2 or str((cross_steps[1] as Dictionary).get("next", "missing")) != "":
		errors.append("cross-resource dialogue paste kept a target missing from destination")


func _test_node_diagnostics(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	workspace.open_resource("dialogue", "sandbox_branch")
	var graph := workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	var choice := _node_for_step(graph, "ask")
	workspace.call("_on_disconnection_request", choice.name, 0, StringName(), 0)
	graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	choice = _node_for_step(graph, "ask")
	var badge := choice.find_child("NodeDiagnosticBadge", true, false) as Button
	var warning := choice.find_child("NodeDiagnosticMessage", true, false) as Label
	var node_diagnostics: Array = choice.get_meta("diagnostics", [])
	if badge == null or warning == null or node_diagnostics.is_empty():
		errors.append("broken dialogue output did not render diagnostics on its source node")
	else:
		var found_port := false
		for diagnostic in node_diagnostics:
			if int((diagnostic as Dictionary).get("port", -1)) == 0:
				found_port = true
				break
		if not found_port:
			errors.append("node diagnostic lost the exact broken choice port")
	var focus_error := workspace.find_child("GraphFocusDiagnostic", true, false) as Button
	if focus_error == null or not focus_error.visible:
		errors.append("invalid graph did not expose a visible focus-error action")
	else:
		focus_error.pressed.emit()
		if not choice.selected:
			errors.append("focus-error action did not select the offending node")
	(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
	graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	choice = _node_for_step(graph, "ask")
	if choice.find_child("NodeDiagnosticBadge", true, false) != null:
		errors.append("node diagnostic badge remained after repairing the graph")
	workspace.open_resource("action", "sandbox_chain")
	var action_document: Dictionary = workspace.get("_action_draft")
	var action_steps: Array = action_document.get("steps", []).duplicate(true)
	var invalid_step: Dictionary = (action_steps[0] as Dictionary).duplicate(true)
	invalid_step["dialogueId"] = ""
	action_steps[0] = invalid_step
	action_document["steps"] = action_steps
	workspace.call("_push_action_draft", action_document)
	graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	if _node_for_step(graph, "step_1").find_child("NodeDiagnosticBadge", true, false) == null:
		errors.append("action validation did not attach its error to the exact step node")


func _test_unsaved_draft_guard(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	workspace.open_resource("dialogue", "sandbox_branch")
	var changed := DialogueGraphModel.add_step(
		workspace.get("_dialogue_draft"), "dialogue", Vector2(900.0, 500.0)
	)
	workspace.call("_push_dialogue_draft", changed)
	workspace.call("_request_navigation", "dialogue", "sandbox_notice_talk", false)
	if str(workspace.get("_current_id")) != "sandbox_branch":
		errors.append("unsaved draft guard allowed resource navigation before confirmation")
	if (workspace.get("_pending_navigation") as Dictionary).is_empty():
		errors.append("unsaved draft guard did not remember the requested destination")
	var resource := workspace.find_child("GraphResource", true, false) as OptionButton
	if _selected_metadata(resource) != "sandbox_branch":
		errors.append("unsaved draft guard did not restore the visible resource selector")
	workspace.call("_cancel_discard_navigation")
	if str(workspace.get("_current_id")) != "sandbox_branch" or not workspace.call("_has_unsaved_draft"):
		errors.append("canceling discard did not keep the current dirty draft")
	workspace.call("_request_navigation", "dialogue", "sandbox_notice_talk", false)
	workspace.call("_confirm_discard_navigation")
	if str(workspace.get("_current_id")) != "sandbox_notice_talk":
		errors.append("confirmed discard did not open the pending graph resource")
	if not (workspace.get("_pending_navigation") as Dictionary).is_empty():
		errors.append("confirmed discard left stale navigation state")


func _test_dialogue_node_authoring(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	workspace.open_resource("dialogue", "sandbox_branch")
	var graph := workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	var initial_count := _graph_nodes(graph).size()
	graph.zoom = 1.25
	graph.scroll_offset = Vector2(160.0, 60.0)
	var add_type := workspace.find_child("GraphAddDialogueType", true, false) as OptionButton
	_select_option(add_type, "dialogue")
	(workspace.find_child("GraphAddDialogueNode", true, false) as Button).pressed.emit()
	graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	if _graph_nodes(graph).size() != initial_count + 1:
		errors.append("dialogue +Node did not append a canonical draft step")
		return
	var draft: Dictionary = workspace.get("_dialogue_draft")
	var steps: Array = draft.get("steps", [])
	var new_id := str((steps[-1] as Dictionary).get("id", ""))
	var new_node := _node_for_step(graph, new_id)
	var layout: Dictionary = draft.get("editorLayout", {})
	if new_id.is_empty() or new_node == null or not layout.has(new_id):
		errors.append("new dialogue node lost its unique ID or editorLayout entry")
	if DialogueStore.graph_validation_errors(draft).is_empty():
		errors.append("unconnected new dialogue node did not block graph save")
	var end_node := _node_for_step(graph, "end")
	workspace.call("_on_connection_request", new_node.name, 0, end_node.name, 0)
	graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	new_node = _node_for_step(graph, new_id)
	var agent_node := _node_for_step(graph, "agent_r")
	workspace.call("_on_connection_request", agent_node.name, 0, new_node.name, 0)
	draft = workspace.get("_dialogue_draft")
	if not DialogueStore.graph_validation_errors(draft).is_empty():
		errors.append("connected new dialogue node did not become a valid graph branch")
	graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	new_node = _node_for_step(graph, new_id)
	workspace.call("_on_node_selected", new_node)
	var set_start := workspace.find_child("GraphSetDialogueStart", true, false) as Button
	if set_start == null or set_start.disabled:
		errors.append("selected dialogue node did not enable Set Start")
	else:
		set_start.pressed.emit()
		if str((workspace.get("_dialogue_draft") as Dictionary).get("startStepId", "")) != new_id:
			errors.append("Set Start did not update canonical startStepId")
		if DialogueStore.graph_validation_errors(workspace.get("_dialogue_draft")).is_empty():
			errors.append("Set Start failed to diagnose newly unreachable old branch")
		(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
	graph = workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
	new_node = _node_for_step(graph, new_id)
	workspace.call("_on_node_selected", new_node)
	(workspace.find_child("GraphDeleteActionNodes", true, false) as Button).pressed.emit()
	if _graph_nodes(workspace.find_child("EmberGraphEdit", true, false) as GraphEdit).size() != initial_count:
		errors.append("Delete did not remove a selected dialogue node")
	if DialogueStore.graph_validation_errors(workspace.get("_dialogue_draft")).is_empty():
		errors.append("deleting a targeted dialogue node did not expose its broken incoming edge")
	(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
	if _graph_nodes(workspace.find_child("EmberGraphEdit", true, false) as GraphEdit).size() != initial_count + 1:
		errors.append("dialogue draft undo did not restore deleted node and layout")


func _test_standalone_action_save(errors: Array[String]) -> void:
	var history := UndoRedo.new()
	var actions := EmberObjectInspectorActions.new()
	actions.configure(history)
	var context := Node.new()
	var document := {
		"id": TEMP_SCRIPT_ID,
		"nameRu": "Graph workspace smoke",
		"steps": [
			{"type": "talk", "dialogueId": "sandbox_guard_talk"},
			{"type": "set_flag", "flag": "graph_smoke_done", "value": true},
		],
	}
	if not actions.save_action_script(document, context):
		errors.append("standalone graph action save rejected a valid document")
	else:
		if not ActionStore.exists(TEMP_SCRIPT_ID):
			errors.append("standalone graph action save did not write its canonical document")
		history.undo()
		if ActionStore.exists(TEMP_SCRIPT_ID):
			errors.append("undo did not remove the standalone graph action document")
		history.redo()
		if not ActionStore.exists(TEMP_SCRIPT_ID):
			errors.append("redo did not restore the standalone graph action document")
	history.clear_history(false)
	history.free()
	context.free()


func _test_standalone_dialogue_graph_save(errors: Array[String]) -> void:
	var history := UndoRedo.new()
	var actions := EmberObjectInspectorActions.new()
	actions.configure(history)
	var context := Node.new()
	var document := DialogueStore.document("sandbox_branch")
	document["id"] = TEMP_DIALOGUE_ID
	document["nameRu"] = "Graph dialogue smoke"
	document = DialogueGraphModel.add_group(document, "Saved frame", ["agent_r", "walk_r"])
	document = DialogueGraphModel.set_group_collapsed(document, "group_1", true)
	if not actions.save_dialogue_graph(document, context):
		errors.append("dialogue graph save rejected a valid canonical document")
	else:
		if not DialogueStore.exists(TEMP_DIALOGUE_ID):
			errors.append("dialogue graph save did not write canonical JSON")
		else:
			var saved_groups: Array = DialogueStore.document(TEMP_DIALOGUE_ID).get("editorGroups", [])
			if saved_groups.size() != 1:
				errors.append("dialogue graph save dropped editorGroups metadata")
			elif not bool((saved_groups[0] as Dictionary).get("collapsed", false)):
				errors.append("dialogue graph save dropped collapsed frame state")
		history.undo()
		if DialogueStore.exists(TEMP_DIALOGUE_ID):
			errors.append("undo did not remove standalone dialogue graph JSON")
		history.redo()
		if not DialogueStore.exists(TEMP_DIALOGUE_ID):
			errors.append("redo did not restore standalone dialogue graph JSON")
	history.clear_history(false)
	history.free()
	context.free()


func _graph_nodes(graph: GraphEdit) -> Array[GraphNode]:
	var result: Array[GraphNode] = []
	if graph == null:
		return result
	for child in graph.get_children():
		if child is GraphNode:
			result.append(child)
	return result


func _assert_graph_connection_ports(
	errors: Array[String],
	graph: GraphEdit,
	context: String,
) -> void:
	if graph == null:
		return
	for connection in graph.connections:
		var source := graph.get_node_or_null(
			NodePath(str(connection.get("from_node", "")))
		) as GraphNode
		var target := graph.get_node_or_null(
			NodePath(str(connection.get("to_node", "")))
		) as GraphNode
		if source == null or target == null:
			errors.append("%s has a connection with a missing GraphNode" % context)
			continue
		var from_port := int(connection.get("from_port", -1))
		var to_port := int(connection.get("to_port", -1))
		if from_port < 0 or from_port >= source.get_output_port_count():
			errors.append("%s has an out-of-range output port" % context)
		if to_port < 0 or to_port >= target.get_input_port_count():
			errors.append("%s has an out-of-range input port" % context)


func _node_for_step(graph: GraphEdit, step_id: String) -> GraphNode:
	for node in _graph_nodes(graph):
		if str(node.get_meta("step_id", "")) == step_id:
			return node
	return null


func _first_graph_frame(graph: GraphEdit) -> GraphFrame:
	for child in graph.get_children():
		if child is GraphFrame and not child.is_queued_for_deletion():
			return child
	return null


func _group_element(graph: GraphEdit, group_id: String) -> GraphElement:
	for child in graph.get_children():
		if child is GraphElement and not child.is_queued_for_deletion() and str(child.get_meta("group_id", "")) == group_id:
			return child
	return null


func _visible_child_count(container: Container) -> int:
	if container == null:
		return 0
	var count := 0
	for child in container.get_children():
		if child.visible:
			count += 1
	return count


func _selected_metadata(option: OptionButton) -> String:
	return "" if option == null or option.selected < 0 else str(option.get_item_metadata(option.selected))


func _select_palette_type(items: ItemList, step_type: String) -> void:
	for index in items.item_count:
		if str(items.get_item_metadata(index)) == step_type:
			items.item_activated.emit(index)
			return


func _select_option(option: OptionButton, value: String) -> void:
	if option == null:
		return
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return


func _option_has_metadata(option: OptionButton, value: String) -> bool:
	if option == null:
		return false
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			return true
	return false


func _restore_fixture(old_document: Dictionary) -> void:
	if old_document.is_empty():
		ActionStore.delete_document(TEMP_SCRIPT_ID)
	else:
		ActionStore.write_document(old_document)


func _restore_dialogue_fixture(old_document: Dictionary) -> void:
	if old_document.is_empty():
		DialogueStore.delete_document(TEMP_DIALOGUE_ID)
	else:
		DialogueStore.write_graph_document(old_document)
