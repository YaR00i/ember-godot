extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
const Actions = preload("res://addons/ember_import/ember_object_inspector_actions.gd")
const Workspace = preload("res://addons/ember_import/ember_graph_workspace.gd")
func _initialize() -> void:
	if not Fixture.prepare(self): quit(2); return
	_run.call_deferred()
func frames(count: int) -> void:
	for i in count: await physics_frame
func _run() -> void:
	var state := root.get_node("EmberExploreProgress") as EmberExploreState
	state.persistence_enabled = false
	state.restore_enabled = false
	state.reset_new_game()
	state.world_items.clear()
	state.inventory.clear()
	var scene := Node3D.new()
	scene.name = "MechanismFixture"
	root.add_child(scene)
	current_scene = scene
	var actions := Actions.new()
	var history := UndoRedo.new()
	actions.configure(history)
	var kit := actions.create_pressure_gate(scene, Vector3.ZERO)
	assert(kit != null)
	var id: String = kit.get_node("Crate").pickup_id
	history.undo()
	assert(kit.get_parent() == null)
	history.redo()
	assert(kit.get_parent() == scene and kit.get_node("Crate").pickup_id == id)
	var workspace := Workspace.new()
	root.add_child(workspace)
	assert(workspace.find_child("CreatePressureGate", true, false) != null)
	var player := EmberPlayer.new()
	player.progress_state = state
	player.position = Vector3(-40, 0.2, 42)
	scene.add_child(player)
	player.set_physics_process(false)
	await frames(55)
	assert(not kit.pressed and kit.openness < 0.01 and not kit.blocked)
	var query := PhysicsRayQueryParameters3D.create(Vector3(0, 12, 10), Vector3(0, 12, -40), 1)
	assert(scene.get_world_3d().direct_space_state.intersect_ray(query).collider == kit.get_node("Gate"))
	player._try_interact()
	var crate: RigidBody3D = kit.get_node("Crate")
	assert(crate.is_carried())
	player.position = Vector3(-40, 0.2, 24)
	await frames(5)
	assert(not kit.pressed)
	player._try_interact()
	assert(not crate.is_carried())
	await frames(100)
	assert(kit.pressed and kit.openness > 0.99)
	assert(scene.get_world_3d().direct_space_state.intersect_ray(query).is_empty())
	# Save uses authored closed pose, not transient animated door position.
	crate.capture_progress()
	state.storage_root = "user://ember-tests/pressure-gate-%d" % OS.get_process_id()
	state.persistence_enabled = true
	assert(state.save_autosave())
	state.persistence_enabled = false
	var pose: Vector3 = kit.get_node("Gate").position
	kit.get_node("Gate").position = kit._closed
	var packed := PackedScene.new()
	assert(packed.pack(scene) == OK)
	assert(ResourceSaver.save(packed, "user://pressure-gate-authoring.tscn") == OK)
	kit.get_node("Gate").position = pose
	var loaded := (load("user://pressure-gate-authoring.tscn") as PackedScene).instantiate()
	var loaded_kit: Node3D = loaded.get_node(NodePath(str(kit.name)))
	assert(loaded_kit.get_node("Crate").pickup_id == id)
	assert(loaded_kit.component("plate").crate_path == NodePath("../Crate") and loaded_kit.component("door").target_path == NodePath("../Gate"))
	assert(loaded_kit.get_node("Crate").get_node_or_null("Pickup") == null)
	assert(loaded_kit.get_node("Find").get_node_or_null("Pickup") == null)
	# Unsaved second creation is absent after reopening the saved document.
	var unsaved := actions.create_pressure_gate(scene, Vector3(350, 0, 0))
	assert(unsaved != null and loaded.get_node_or_null(NodePath(str(unsaved.name))) == null)
	history.undo()
	assert(unsaved.get_parent() == null)
	history.clear_history()
	if is_instance_valid(unsaved): unsaved.free()
	# Lift crate, stand in passage: hold open; leave passage: close.
	player.position = Vector3(-40, 0.2, 12)
	player._try_interact()
	assert(crate.is_carried())
	player.position = Vector3(0, 0.2, -20)
	await frames(12)
	assert(not kit.pressed and kit.blocked and kit.openness > 0.99)
	player.position = Vector3(-40, 0.2, 40)
	await frames(60)
	assert(not kit.blocked and kit.openness < 0.01)
	# Persisted crate pose is recomputed after a fresh scene instance/load.
	player.free()
	history.clear_history()
	assert(state.load_autosave())
	scene.remove_child(kit)
	kit.free()
	root.add_child(loaded)
	await frames(100)
	assert(loaded_kit.pressed and loaded_kit.openness > 0.99)
	# Findings are ordinary persistent world items; repeat/load never respawns them.
	var find: RigidBody3D = loaded_kit.get_node("Find")
	var find_id: String = find.pickup_id
	assert(state.pickup_world_item(find_id, false).ok)
	assert(not state.pickup_world_item(find_id, false).ok)
	state.storage_root = "user://ember-tests/pressure-gate-%d" % OS.get_process_id()
	state.persistence_enabled = true
	assert(state.save_autosave())
	var restored := EmberExploreState.new()
	restored.persistence_enabled = false
	restored.storage_root = state.storage_root
	assert(restored.load_autosave() and restored.world_items[find_id].count == 0)
	loaded.queue_free()
	scene.queue_free()
	workspace.queue_free()
	restored.free()
	history.clear_history()
	history.free()
	await process_frame
	# User-visible play mode is on the existing stage, with its own save state.
	var stage: Node3D = load("res://scenes/prototypes/camera_preset_study.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	stage.start_mechanism_trial()
	await frames(5)
	assert(stage._mechanism.get_node("TrialPlayer")._defeated == false)
	stage._mechanism.find_child("RestartTrial", true, false).pressed.emit()
	await process_frame
	await frames(5)
	assert(stage._mechanism.get_node("TrialPlayer") != null)
	stage._mechanism.find_child("LeaveTrial", true, false).pressed.emit()
	await process_frame
	assert(stage._mechanism == null)
	stage.queue_free()
	await process_frame
	print("PASS pressure gate: F carry/place, containment/settle, live open/close collision, occupied passage, scene Undo/Redo/save/reopen, persistent crate/find and existing stage play mode")
	quit()
