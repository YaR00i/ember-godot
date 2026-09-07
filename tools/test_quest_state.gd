extends SceneTree
## Quest marker status/icon projection plus live agent_sandbox binding.

const QuestState = preload("res://scripts/ember_quest_state.gd")
const SANDBOX_SCENE := "res://scenes/agent_sandbox.tscn"


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	quit(await _run())


func _run() -> int:
	var errors: Array[String] = []
	_test_projection(errors)
	await _test_live_markers(errors)
	if not errors.is_empty():
		printerr("FAIL quest state")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS quest state")
	print("  authored available/active/done -> original Sprite3D status SVG")
	print("  native quest + action binding follows persisted EmberExploreState projection")
	print("  completed giver event hides instead of showing a false quest-done icon")
	return 0


func _test_projection(errors: Array[String]) -> void:
	if QuestState.resolve_status("", "", {}) != "available":
		errors.append("missing authored status did not default to available")
	if QuestState.resolve_status("active", "q", {"q": true}) != "done":
		errors.append("true quest flag did not resolve to done")
	if QuestState.resolve_status("available", "q", {"q": "active"}) != "active":
		errors.append("typed quest flag did not override authored status")
	if QuestState.resolve_icon_id("quest", "available") != "quest_available":
		errors.append("quest alias did not resolve to quest_available")
	if QuestState.resolve_icon_id("quest_available", "done") != "quest_done":
		errors.append("stock authored icon froze instead of following marker state")
	if QuestState.marker_icon_path("quest", "active") != "res://assets/world_markers/quest_active.svg":
		errors.append("active quest marker did not resolve its original SVG")
	if QuestState.marker_icon_path("unknown_custom", "done") != "res://assets/world_markers/quest_done.svg":
		errors.append("unknown custom marker did not retain a readable status fallback")
	var near_lod := QuestState.marker_lod(100.0)
	var middle_lod := QuestState.marker_lod(230.0)
	var far_lod := QuestState.marker_lod(300.0)
	if near_lod != Vector2.ONE:
		errors.append("near quest marker did not retain its authored screen size")
	if not (middle_lod.x < 1.0 and middle_lod.y < 1.0 and middle_lod.y > 0.0):
		errors.append("distant quest marker does not shrink and fade together")
	if far_lod.y != 0.0:
		errors.append("quest marker did not disappear at the hide distance")
	var authored := EmberSceneAuthoring.normalized_interact_values({
		"kind": "quest_marker",
		"trigger_id": "notice",
		"script_id": "sandbox_notice_read",
		"quest_id": "sandbox_notice_quest",
		"icon_id": "quest",
		"quest_status": "active",
	})
	if (
		str(authored.get("script_id", "")) != "sandbox_notice_read"
		or str(authored.get("quest_id", "")) != "sandbox_notice_quest"
		or str(authored.get("icon_id", "")) != "quest"
		or str(authored.get("quest_status", "")) != "active"
	):
		errors.append("scene authoring normalization dropped quest modifier fields")
	var quest_definition := EmberQuestCatalog.definition("sandbox_notice_quest")
	var quest_objectives: Array = quest_definition.get("objectives", [])
	if quest_objectives.is_empty():
		errors.append("sandbox quest has no objectives for marker projection")
		return
	var final_definition: Dictionary = quest_objectives[-1]
	var final_flag := str(final_definition.get("flagId", ""))
	var fresh := EmberQuestCatalog.projection(quest_definition, {})
	var start := QuestState.marker_projection(fresh, [
		{"type": "set_flag", "flag": "sandbox_notice_status", "value": "active"},
	], "available")
	if str(start.get("role", "")) != "start" or not bool(start.get("visible", false)):
		errors.append("start event did not produce the available quest marker")
	var final_objective := QuestState.marker_projection(fresh, [
		{"type": "set_flag", "flag": final_flag, "value": true},
	], "active")
	if bool(final_objective.get("visible", true)) or str(final_objective.get("reason", "")) != "quest_not_started":
		errors.append("future objective marker is visible before the quest starts")
	var ready_flags := {"sandbox_notice_status": "active"}
	for index in range(quest_objectives.size() - 1):
		var objective: Dictionary = quest_objectives[index]
		ready_flags[str(objective.get("flagId", ""))] = true
	var after_first := EmberQuestCatalog.projection(quest_definition, ready_flags)
	final_objective = QuestState.marker_projection(after_first, [
		{"type": "set_flag", "flag": final_flag, "value": true},
	], "active")
	if (
		not bool(final_objective.get("visible", false))
		or str(final_objective.get("status", "")) != "done"
		or str(final_objective.get("reason", "")) != "final_objective"
	):
		errors.append("last unlocked objective did not become a completion marker")
	var completed_flags := ready_flags.duplicate(true)
	completed_flags[final_flag] = true
	var completed := EmberQuestCatalog.projection(quest_definition, completed_flags)
	final_objective = QuestState.marker_projection(completed, [
		{"type": "set_flag", "flag": final_flag, "value": true},
	], "active")
	if bool(final_objective.get("visible", true)):
		errors.append("completed objective marker did not disappear")
	var turn_in := QuestState.marker_projection(completed, [
		{"type": "set_flag", "flag": "sandbox_notice_status", "value": "done"},
	], "done")
	if not bool(turn_in.get("visible", false)) or str(turn_in.get("status", "")) != "done":
		errors.append("ready turn-in event did not show the completion marker")


func _test_live_markers(errors: Array[String]) -> void:
	var progress := root.get_node_or_null("EmberExploreProgress") as EmberExploreState
	if progress == null:
		errors.append("EmberExploreProgress autoload is missing")
		return
	progress.persistence_enabled = false
	progress.restore_enabled = false
	progress.reset_new_game()
	if change_scene_to_file(SANDBOX_SCENE) != OK:
		errors.append("could not start agent_sandbox")
		return
	await process_frame
	await process_frame
	var available := _interact_for_placement(current_scene, "sbx_quest_sign")
	var active := _interact_for_placement(current_scene, "sbx_quest_active")
	var final := _interact_for_placement(current_scene, "sbx_quest_done")
	if available == null or active == null or final == null:
		errors.append("agent_sandbox lost one of its three quest markers")
		return
	var available_state := available.effective_quest_marker_projection()
	var active_state := active.effective_quest_marker_projection()
	if str(available_state.get("role", "")) != "start" or not bool(available_state.get("visible", false)):
		errors.append("sandbox quest giver did not project its start event")
	if str(active_state.get("role", "")) != "objective" or bool(active_state.get("visible", true)):
		errors.append("sandbox future objective is visible before quest acceptance")
	var final_state := final.effective_quest_marker_projection()
	if str(final_state.get("role", "")) != "objective" or bool(final_state.get("visible", true)):
		errors.append("sandbox final objective is visible before its prerequisites")
	if available.resolved_action_script_id() != "sandbox_notice":
		errors.append("native quest giver did not resolve sandbox_notice")
	if (
		available.quest_id != "sandbox_notice_quest"
		or available.script_id != "sandbox_notice"
		or available.effective_quest_id() != "sandbox_notice_quest"
	):
		errors.append("sandbox quest giver regressed to the ambiguous legacy flag binding")
	if not available.is_in_group("ember_interact"):
		errors.append("actionable quest marker did not expose F")
	if active.is_in_group("ember_interact"):
		errors.append("hidden future objective still claimed F before quest acceptance")
	if final.is_in_group("ember_interact"):
		errors.append("locked final objective claimed F before its prerequisites")
	var direct := EmberInteract.new()
	direct.name = "DirectQuestBindingProbe"
	direct.kind = "quest_marker"
	direct.quest_id = "sandbox_notice_quest"
	direct.script_id = "sandbox_chain"
	current_scene.add_child(direct)
	await process_frame
	if direct.effective_quest_id() != "sandbox_notice_quest":
		errors.append("native quest_id binding did not resolve its Resource")
	if direct.effective_quest_status_flag_id() != "sandbox_notice_status":
		errors.append("native quest marker did not derive statusFlagId from its Resource")
	if direct.resolved_action_script_id() != "sandbox_chain" or not direct.is_in_group("ember_interact"):
		errors.append("native quest marker did not keep a separate actionable chain")
	progress.set_flag("sandbox_notice_status", "active", false)
	await process_frame
	if direct.effective_quest_status() != "active":
		errors.append("native quest marker did not react to its derived status flag")
	direct.queue_free()
	progress.clear_flags(["sandbox_notice_status"], false)
	var available_marker := available.get_node_or_null("QuestMarker") as Node3D
	var active_marker := active.get_node_or_null("QuestMarker") as Node3D
	var done_marker := final.get_node_or_null("QuestMarker") as Node3D
	var available_icon := available.get_node_or_null("QuestMarker/Icon") as Sprite3D
	var active_icon := active.get_node_or_null("QuestMarker/Icon") as Sprite3D
	var done_icon := final.get_node_or_null("QuestMarker/Icon") as Sprite3D
	if (
		available_marker == null or active_marker == null or done_marker == null
		or available_icon == null or active_icon == null or done_icon == null
	):
		errors.append("quest marker billboards were not created")
		return
	if available_icon.pixel_size > 0.002:
		errors.append("quest marker billboard regressed to an oversized editor scale")
	if not available_icon.centered or available_icon.offset != Vector2.ZERO:
		errors.append("quest marker SVG is not centered on its LOD pivot")
	if (
		available_icon.texture == null or active_icon.texture == null or done_icon.texture == null
		or available_icon.texture.resource_path != "res://assets/world_markers/quest_available.svg"
	):
		errors.append("quest marker status SVGs were not assigned")
	var prop := available.get_parent() as Node3D
	var mesh := prop.get_node_or_null("Mesh") as MeshInstance3D
	var bounds := mesh.get_aabb()
	var top_center := bounds.position + Vector3(
		bounds.size.x * 0.5,
		bounds.size.y,
		bounds.size.z * 0.5,
	)
	var expected_anchor := available.transform.affine_inverse() * (
		mesh.transform * top_center + Vector3.UP * 4.0
	)
	if not available_marker.position.is_equal_approx(expected_anchor):
		errors.append("quest marker is not anchored above the visible mesh center")
	progress.set_flag("sandbox_notice_status", "active", false)
	progress.set_flag("sandbox_notice_read", true, false)
	await process_frame
	if (
		bool(available.effective_quest_marker_projection().get("visible", true))
		or not bool(active.effective_quest_marker_projection().get("visible", false))
		or bool(final.effective_quest_marker_projection().get("visible", true))
		or active_icon.texture.resource_path != "res://assets/world_markers/quest_active.svg"
	):
		errors.append("runtime did not hide the giver and reveal the middle objective marker")
	if str(available.effective_quest_marker_projection().get("status", "")) == "done":
		errors.append("resolved giver still projects a false completed-quest icon")
	progress.set_flag("sandbox_notice_quest_objective_2", true, false)
	await process_frame
	var final_event_flag := ""
	var final_queue := EmberActionScript.queue_for(final.resolved_action_script_id())
	for raw_step in final_queue.get("steps", []):
		if typeof(raw_step) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = raw_step
		if str(step.get("type", "")) == "set_flag":
			final_event_flag = str(step.get("flag", ""))
			break
	var quest_definition := EmberQuestCatalog.definition(final.effective_quest_id())
	var quest_objectives: Array = quest_definition.get("objectives", [])
	var event_is_last_objective := (
		not quest_objectives.is_empty()
		and str((quest_objectives[-1] as Dictionary).get("flagId", "")) == final_event_flag
	)
	var expected_event_icon := (
		"res://assets/world_markers/quest_done.svg"
		if event_is_last_objective
		else "res://assets/world_markers/quest_active.svg"
	)
	if (
		bool(active.effective_quest_marker_projection().get("visible", true))
		or not bool(final.effective_quest_marker_projection().get("visible", false))
		or done_icon.texture.resource_path != expected_event_icon
	):
		errors.append("runtime did not advance from the middle to the next objective marker")
	if final_event_flag.is_empty():
		errors.append("sandbox next-objective marker has no set_flag event")
		return
	progress.set_flag(final_event_flag, true, false)
	await process_frame
	if bool(final.effective_quest_marker_projection().get("visible", true)):
		errors.append("runtime did not hide the completed objective marker")
	progress.reset_new_game()


func _interact_for_placement(scene: Node, placement_id: String) -> EmberInteract:
	var props := scene.get_node_or_null("Map/Props")
	if props == null:
		return null
	for child in props.get_children():
		var prop := child as EmberVoxelProp
		if prop != null and prop.placement_id == placement_id:
			return prop.get_node_or_null("Interact") as EmberInteract
	return null
