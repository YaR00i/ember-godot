extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
const Actions = preload("res://addons/ember_import/ember_object_inspector_actions.gd")
const Store = preload("res://addons/ember_import/ember_quest_store.gd")
const ActionStore = preload("res://addons/ember_import/ember_action_script_store.gd")
const Workspace = preload("res://addons/ember_import/ember_graph_workspace.gd")
var errors: Array[String] = []

func _init() -> void:
	if not Fixture.prepare(self):
		quit(2)
		return
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)

func frames() -> void:
	for index in 8:
		await physics_frame
	await process_frame

func _run() -> void:
	var state := root.get_node("EmberExploreProgress") as EmberExploreState
	state.persistence_enabled = false
	state.flags.clear()
	var scene := Node3D.new()
	scene.name = "ReachFixture"
	root.add_child(scene)
	current_scene = scene
	var ui := EmberInteractionUi.new()
	ui.economy_state = state
	root.add_child(ui)
	var player := EmberPlayer.new()
	player.progress_state = state
	player.interaction_ui = ui
	player.position = Vector3(100, 0, 100)
	scene.add_child(player)
	player.set_physics_process(false)
	var workspace := Workspace.new()
	root.add_child(workspace)
	workspace.set_scene_root(scene)
	workspace.open_resource("quest", "interaction_quest")
	(workspace.find_child("GraphNewQuest", true, false) as Button).pressed.emit()
	workspace.call("_add_quest_objective", "main")
	var quest: Dictionary = workspace.get("_quest_draft").duplicate(true)
	var quest_id := str(quest.id)
	var objective_id := str(quest.objectives[1].id)
	var flag := str(quest.objectives[1].flagId)
	var history := UndoRedo.new()
	var actions := Actions.new()
	actions.configure(history)
	var zones: Array[EmberInteract] = []
	workspace.quest_reach_zone_requested.connect(func(_anchor: NodePath, target_id: String, draft: Dictionary) -> void:
		var zone := actions.create_quest_reach_zone(scene, Vector3(0, 4, 0), target_id, draft)
		if zone != null:
			zones.append(zone)
	)
	(workspace.find_child("CreateQuestReachZone_1", true, false) as Button).pressed.emit()
	check(zones.size() == 1, "Graph button did not create a zone")
	if zones.is_empty():
		quit(1)
		return
	var zone := zones[0]
	var chain_id := zone.script_id
	var path := scene.get_path_to(zone)
	check(zone.activation_mode == "enter" and not zone.is_in_group("ember_interact"), "reach zone requires F")
	check(zone.owner == scene and zone.get_node("Shape").owner == scene, "zone is not scene owned")
	check(ActionStore.document(chain_id).steps.size() == 1, "dependent goal unexpectedly starts or rewards quest")
	history.undo()
	check(not scene.has_node(path) and not ActionStore.exists(chain_id) and Store.document(quest_id).is_empty(), "Undo did not remove zone, Action and new Quest together")
	history.redo()
	check(scene.has_node(path) and ActionStore.exists(chain_id) and not Store.document(quest_id).is_empty(), "Redo did not restore zone and resources")
	check(actions.create_quest_reach_zone(scene, Vector3.ZERO, objective_id, quest) == null, "duplicate reach zone accepted")
	var invalid := quest.duplicate(true)
	invalid.objectives[1].progressMode = "counter"
	invalid.objectives[1].counterEventId = "battle_win"
	check(actions.create_quest_reach_zone(scene, Vector3.ZERO, objective_id, invalid) == null, "counter goal accepted as flag zone")
	# Real Area3D / CharacterBody3D entry goes through the existing player and UI.
	await frames()
	player.position = Vector3.ZERO
	await frames()
	check(not state.flags.get(flag, false), "early entry bypassed prerequisite")
	ui.close()
	player.position = Vector3(100, 0, 100)
	await frames()
	var first := actions.create_quest_reach_zone(scene, Vector3(48, 4, 0), "main", quest)
	check(first != null, "first goal zone could not be created")
	await frames()
	player.position = Vector3(48, 0, 0)
	await frames()
	check(state.flags.get(str(quest.objectives[0].flagId), false), "entry did not complete first goal")
	check(state.flags.get(str(quest.statusFlagId), "") == "active", "first entry did not start quest")
	player.position = Vector3(100, 0, 100)
	await frames()
	player.position = Vector3.ZERO
	await frames()
	check(state.flags.get(flag, false), "valid re-entry did not complete goal")
	await frames()
	check(not zone.runtime_available() and not zone.monitoring, "completed zone still activates: route=%s monitoring=%s flags=%s" % [zone.runtime_route(), zone.monitoring, state.flags])
	var completed := state.flags.duplicate(true)
	player.position = Vector3(100, 0, 100)
	await frames()
	player.position = Vector3.ZERO
	await frames()
	check(state.flags == completed, "repeat entry changed quest progress")
	# Persistent progress comes from the existing save owner, not zone-local state.
	state.persistence_enabled = true
	state.set_world_context("reach_fixture", player, 16.0)
	check(state.save_slot(1), "save failed")
	var cold := EmberExploreState.new()
	root.add_child(cold)
	check(cold.load_slot(1) and cold.flags.get(flag, false), "cold load lost completion")
	check(not zone.runtime_available(cold.flags), "loaded completed zone became available")
	cold.queue_free()
	state.persistence_enabled = false
	player.queue_free()
	await process_frame
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK and ResourceSaver.save(packed, "user://reach_scene.tscn") == OK, "scene save failed")
	var reopened := (ResourceLoader.load("user://reach_scene.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var restored := reopened.get_node_or_null(path) as EmberInteract
	check(restored != null and restored.script_id == chain_id and restored.activation_mode == "enter" and restored.condition_flag_id == flag and restored.condition_value == false, "scene reopen lost zone binding")
	reopened.free()
	workspace.set_scene_root(scene)
	workspace.accept_quest_binding_save()
	await process_frame
	workspace.call("_set_quest_focus", "quest_root")
	workspace.call("_set_quest_focus", objective_id)
	var select := workspace.find_child("CreateQuestReachZone_1", true, false) as Button
	check(select != null and select.text == "Выбрать место на карте →", "reopened Graph offers duplicate creation")
	var capture := OS.get_environment("EMBER_REACH_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(1600, 1000)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	history.clear_history()
	check(is_instance_valid(zone) and zone.is_inside_tree(), "clearing history deleted committed zone")
	history.free()
	ui.queue_free()
	workspace.queue_free()
	scene.queue_free()
	await process_frame
	Fixture.verify_sources(errors)
	if errors.is_empty():
		print("PASS quest reach zone: Graph/create/select, early entry, real player entry, repeat, Undo/Redo, scene reopen, cold load, validation")
		quit(0)
	else:
		for error in errors:
			printerr("FAIL ", error)
		quit(1)
