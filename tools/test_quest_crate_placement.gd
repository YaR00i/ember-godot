extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
const Actions = preload("res://addons/ember_import/ember_object_inspector_actions.gd")
const Store = preload("res://addons/ember_import/ember_quest_store.gd")
const Workspace = preload("res://addons/ember_import/ember_graph_workspace.gd")
var errors: Array[String] = []
var capture_directory := ""

func capture(label: String) -> void:
	if capture_directory.is_empty():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_directory.path_join("crate-" + label + ".png"))

func _init() -> void:
	if not Fixture.prepare(self):
		quit(2)
		return
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)

func frames(count: int) -> void:
	for index in count:
		await physics_frame

func _run() -> void:
	var state := root.get_node("EmberExploreProgress") as EmberExploreState
	state.persistence_enabled = false
	state.world_items.clear()
	state.flags.clear()
	var scene := Node3D.new()
	scene.name = "CratePlacementFixture"
	root.add_child(scene)
	current_scene = scene
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	(floor_shape.shape as BoxShape3D).size = Vector3(240, 2, 240)
	floor_shape.position.y = -1
	floor_body.add_child(floor_shape)
	scene.add_child(floor_body)
	var player := EmberPlayer.new()
	player.progress_state = state
	player.position = Vector3(0, 0, 12)
	scene.add_child(player)
	player.set_physics_process(false)
	var workspace := Workspace.new()
	root.add_child(workspace)
	workspace.set_scene_root(scene)
	workspace.open_resource("quest", "interaction_quest")
	(workspace.find_child("GraphNewQuest", true, false) as Button).pressed.emit()
	var quest: Dictionary = workspace.get("_quest_draft")
	var quest_id := str(quest.id)
	var flag := str(quest.objectives[0].flagId)
	var history := UndoRedo.new()
	var actions := Actions.new()
	actions.configure(history)
	var compounds: Array[Node3D] = []
	var handler := func(_anchor: NodePath, objective_id: String, document: Dictionary) -> void:
		var result := actions.create_quest_object_placement(scene, Vector3(0, 0.15, 0), Vector3(64, 0, 0), objective_id, document)
		if result != null:
			compounds.append(result)
	workspace.quest_object_placement_requested.connect(handler)
	(workspace.find_child("CreateQuestObjectPlacement_0", true, false) as Button).pressed.emit()
	check(compounds.size() == 1, "Graph button did not create the crate and target zone")
	if compounds.is_empty():
		quit(1)
		return
	var compound := compounds[0]
	var crate = compound.get_node("Crate")
	var zone = compound.get_node("TargetZone")
	capture_directory = OS.get_environment("EMBER_CRATE_CAPTURE_DIR")
	if not capture_directory.is_empty():
		workspace.hide()
		var camera := Camera3D.new()
		scene.add_child(camera)
		camera.position = Vector3(120, 92, 120)
		camera.look_at(Vector3(32, 8, 0))
		camera.current = true
		var sun := DirectionalLight3D.new()
		scene.add_child(sun)
		sun.rotation_degrees = Vector3(-45, -30, 0)
		sun.shadow_enabled = true
		var world := WorldEnvironment.new()
		world.environment = Environment.new()
		world.environment.background_mode = Environment.BG_COLOR
		world.environment.background_color = Color(0.52, 0.7, 0.8)
		world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		world.environment.ambient_light_color = Color(0.65, 0.72, 0.8)
		scene.add_child(world)
		var ground := MeshInstance3D.new()
		ground.mesh = PlaneMesh.new()
		(ground.mesh as PlaneMesh).size = Vector2(240, 240)
		scene.add_child(ground)
	check(crate.carryable and zone.target_pickup_id == crate.pickup_id, "placement did not bind the persistent crate identity")
	check(str(Store.document(quest_id).objectives[0].textRu) == "Поставить ящик в отмеченную зону", "default objective did not get a readable goal")
	history.undo()
	check(compound.get_parent() == null and Store.document(quest_id).is_empty(), "one Undo did not remove the placement and new quest")
	history.redo()
	check(compound.get_parent() == scene and not Store.document(quest_id).is_empty(), "Redo did not restore the placement")
	await frames(12)
	await capture("start")
	player.call("_try_interact")
	check(crate.is_carried() and player.has_meta("ember_carried_item"), "F route did not lift the crate")
	check(state.inventory.get("quest_crate", 0) == 0, "carrying incorrectly granted an inventory item")
	player.position = Vector3(64, 0, 24)
	await frames(12)
	check(crate.global_position.distance_to(Vector3(64, 8, 4)) < 0.1, "crate did not follow its carrier")
	check(not state.flags.get(flag, false), "crate in hands completed the target zone")
	await capture("held")
	# The existing F route must prefer the held crate even near other prompts.
	check(player.call("_nearest") == crate.get_node("Pickup"), "held crate did not retain F priority")
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 1
	var block_shape := CollisionShape3D.new()
	block_shape.shape = BoxShape3D.new()
	(block_shape.shape as BoxShape3D).size = Vector3(12, 24, 12)
	blocker.add_child(block_shape)
	scene.add_child(blocker)
	blocker.position = Vector3(64, 12, 0)
	await frames(3)
	player.call("_try_interact")
	check(crate.is_carried(), "blocked placement dropped the crate into occupied space")
	blocker.queue_free()
	await frames(3)
	player.call("_try_interact")
	check(not crate.is_carried() and not player.has_meta("ember_carried_item"), "second F did not put the crate down")
	await frames(60)
	if not state.flags.get(flag, false):
		print("ZONE DEBUG ", crate.global_position, " velocity=", crate.linear_velocity, " accepted=", zone.accepts_body(crate), " overlaps=", zone.get_overlapping_bodies().size(), " flag=", zone.completion_flag())
	check(state.flags.get(flag, false), "settled crate did not complete the target objective")
	check(crate.global_position.distance_to(Vector3(64, 0, 0)) < 1.0, "placed crate did not settle on the physical floor")
	await capture("placed")
	state.persistence_enabled = true
	state.set_world_context("landscape_compact", player, 16.0)
	check(state.save_slot(1), "placement save failed")
	var loaded := EmberExploreState.new()
	loaded.storage_root = state.storage_root
	check(loaded.load_slot(1), "cold placement save did not reopen")
	check(loaded.flags.get(flag, false) and loaded.world_items.has(crate.pickup_id), "cold load lost the objective or persistent crate")
	if loaded.world_items.has(crate.pickup_id):
		check(Vector3(loaded.world_items[crate.pickup_id].position[0], loaded.world_items[crate.pickup_id].position[1], loaded.world_items[crate.pickup_id].position[2]).distance_to(crate.global_position) < 0.1, "cold load lost the crate's placed position")
	loaded.free()
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK, "placement scene could not pack")
	var path := "user://crate-placement-roundtrip.tscn"
	check(ResourceSaver.save(packed, path) == OK, "placement scene did not save")
	var reopened := (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var saved_compound := reopened.get_node(NodePath(str(compound.name)))
	check(saved_compound.get_node("Crate").pickup_id == crate.pickup_id and saved_compound.get_node("TargetZone").target_pickup_id == crate.pickup_id, "scene reopen lost the crate-zone identity")
	check(saved_compound.get_node("Crate").get_node_or_null("Pickup") == null, "runtime pickup helper leaked into the authored scene")
	reopened.free()
	check(actions.create_quest_object_placement(scene, Vector3.ZERO, Vector3(64,0,0), "main", quest) == null, "duplicate placement was created for one objective")
	workspace.accept_quest_binding_save()
	check((workspace.find_child("CreateQuestObjectPlacement_0", true, false) as Button).text == "Выбрать зону на карте →", "saved objective did not expose its scene zone")
	workspace.quest_object_placement_requested.disconnect(handler)
	history.clear_history()
	check(is_instance_valid(compound) and compound.get_parent() == scene, "clearing history deleted the committed placement")
	workspace.queue_free()
	await process_frame
	for error in errors:
		push_error(error)
	print("PASS crate placement: Graph/Undo/Redo/F carry/blocked drop/zone/save/cold load/scene roundtrip" if errors.is_empty() else "FAIL crate placement")
	quit(0 if errors.is_empty() else 1)
