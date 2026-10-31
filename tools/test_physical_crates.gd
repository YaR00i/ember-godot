extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
const Item = preload("res://scripts/ember_world_item_3d.gd")
const Recovery = preload("res://scripts/ember_world_recovery.gd")
const Workshop = preload("res://addons/ember_import/ember_mechanism_workspace.gd")
const Actions = preload("res://addons/ember_import/ember_object_inspector_actions.gd")
class ReturnMap extends EmberMapLoader:
	func spawn_world() -> Vector3: return Vector3(0, 0, 100)
var errors: Array[String] = []
func _init() -> void:
	if not Fixture.prepare(self): quit(2); return
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: errors.append(message)
func frames(n: int) -> void:
	for i in n: await physics_frame
func _run() -> void:
	var state := root.get_node("EmberExploreProgress") as EmberExploreState
	state.persistence_enabled = false; state.world_items.clear(); state.flags.clear()
	var scene := Node3D.new(); root.add_child(scene); current_scene = scene
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new(); floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(640, 2, 640); floor_shape.position.y = -1
	floor_body.add_child(floor_shape); scene.add_child(floor_body)
	var kit := load("res://prefabs/items/physical_crates.tscn").instantiate() as Node3D
	scene.add_child(kit)
	var small = kit.get_node("SmallCrate")
	# This gate exercises transfer/weights/recovery with a surviving load. Impact
	# destruction has its own focused gate; the authored fragile crate is unchanged.
	small.breakable=false
	var large = kit.get_node("LargeCrate")
	var circuit = kit.get_node("Circuit")
	var plate = kit.get_node("Circuit/WeightPlate")
	var player := EmberPlayer.new(); player.progress_state = state
	player.position = Vector3(-24, 0.2, 6); scene.add_child(player); player.set_physics_process(false)
	var recovery := Recovery.new(); recovery.floor_y = -128; scene.add_child(recovery)
	await frames(70)
	check(is_equal_approx(small.mass, 0.25) and is_equal_approx(large.mass, 1.0), "authored masses overwritten")
	check(not large.carryable and large.pushable, "large crate role lost")
	var inventory := state.inventory.duplicate(true); large.take(player)
	check(not large.is_carried() and inventory == state.inventory, "large crate became a pickup")
	player._try_interact(); await frames(2)
	check(small.is_carried(), "F did not lift small crate")
	player.set_physics_process(true)
	Input.action_press("throw_item"); await frames(2); Input.action_release("throw_item")
	player.set_physics_process(false)
	check(not small.is_carried() and not player.has_meta("ember_carried_item"), "G left carrier attached")
	check(small.linear_velocity.length() > 10, "G did not apply a throw impulse")
	var thrown_at: Vector3 = small.global_position; await frames(12)
	check(small.global_position.distance_to(thrown_at) > 3.0, "thrown crate did not fly")
	large.recover_from_void(); player.position = Vector3(24, 0.1, 24)
	player.set_physics_process(true); Input.action_press("move_north")
	await frames(90); Input.action_release("move_north"); player.set_physics_process(false)
	check(large.global_position.z < -2.0, "walking into large crate did not push it")
	player.position = Vector3(-120, 0, 100)
	small.global_position = Vector3(24, 0.2, -64); small.linear_velocity = Vector3.ZERO
	large.global_position = Vector3(120, 0.2, 0); large.linear_velocity = Vector3.ZERO
	await frames(100)
	check(not plate.value and is_equal_approx(plate.sensed_weight, 0.25), "one light crate activated heavy plate")
	player.position = Vector3(24, 0.2, -64); await frames(30)
	check(not plate.value, "weight-zero character activated plate")
	player.position = Vector3(-120, 0, 100)
	var second := Item.new(); second.pickup_id = "second_light"; second.item_id = "quest_crate"
	second.position = Vector3(8, 0.2, -64); scene.add_child(second)
	await frames(100)
	check(plate.value and plate.sensed_weight >= 0.5, "two light crates did not sum")
	second.position = Vector3(-140, 0.2, -64); second.linear_velocity = Vector3.ZERO
	small.position = Vector3(-100, 0.2, 0); small.linear_velocity = Vector3.ZERO
	large.position = Vector3(24, 0.2, -64); large.linear_velocity = Vector3.ZERO
	await frames(100)
	check(plate.value and plate.sensed_weight >= 1.0, "heavy crate did not activate plate")
	small.position = Vector3(500, 0, 0); await frames(5)
	check(small.position.distance_to(Vector3(-24, 0.3, 0)) < 2.0, "quest radius did not return small crate")
	player.position = small.position + Vector3(0, 0, 20)
	small.take(player); await frames(2)
	small.global_position = Vector3(-24, -300, 0)
	recovery.recover_body(small); await frames(2)
	check(not small.is_carried() and not player.has_meta("ember_carried_item"), "recovery retained held metadata")
	large.position = Vector3(24, -400, 0); await frames(20)
	check(large.position.y > -5 and large.linear_velocity.length() < 8, "missed-crossing guard failed")
	check(not plate.value, "plate retained signal after recovery")
	check(state.flags.is_empty(), "technical recovery changed quest flags")
	var controller := preload("res://scripts/ember_explore_scene.gd").new()
	var return_map := ReturnMap.new(); controller.set("_map", return_map); controller.set("_player", player)
	recovery.character_return = controller._recover_fallen_character
	var party_before := state.party.duplicate(true); var hp_before := state.hp
	player.position = Vector3(0, -400, 0); await frames(20)
	check(player.position.distance_to(Vector3(0, 6, 100)) < 0.1, "fallen character did not return to map entry")
	check(state.party == party_before and state.hp == hp_before, "void recovery changed health/party")
	recovery.character_return = Callable(); controller.free(); return_map.free()
	var loose := RigidBody3D.new(); loose.position = Vector3(80, 10, 80); loose.gravity_scale = 0
	scene.add_child(loose); await frames(3); loose.position.y = -400; await frames(20)
	check(loose.position.distance_to(Vector3(80, 10, 80)) < 0.1 and loose.linear_velocity == Vector3.ZERO, "unowned dynamic body was not recovered")
	loose.queue_free()
	state.persistence_enabled = true; state.set_world_context("landscape_compact", player, 16.0)
	check(state.save_slot(1), "save after recovery failed")
	var loaded := EmberExploreState.new(); loaded.storage_root = state.storage_root
	check(loaded.load_slot(1), "cold load failed")
	state.adopt_loaded_save(loaded); small.restore_progress(); large.restore_progress(); loaded.free(); state.persistence_enabled = false
	check(small.linear_velocity == Vector3.ZERO and not small.is_carried() and large.position.y > -5, "load restored invalid physics")
	var history := UndoRedo.new(); var actions := Actions.new(); actions.configure(history)
	var workspace := Workshop.new(); root.add_child(workspace); workspace.setup(scene, actions)
	workspace.focus_component(circuit, "weight_plate")
	(workspace.find_child("MechanismWeight", true, false) as SpinBox).value = 0.75
	workspace._apply_fields()
	check(is_equal_approx(circuit.component("weight_plate").required_weight, 0.75), "UI did not write weight")
	history.undo(); check(is_equal_approx(circuit.component("weight_plate").required_weight, 0.5), "weight Undo failed")
	history.redo(); check(is_equal_approx(circuit.component("weight_plate").required_weight, 0.75), "weight Redo failed")
	var packed := PackedScene.new(); packed.pack(kit)
	var path := "user://physical-crates-roundtrip.tscn"; check(ResourceSaver.save(packed, path) == OK, "scene save failed")
	var reopened := (load(path) as PackedScene).instantiate()
	check(is_equal_approx(reopened.get_node("Circuit").component("weight_plate").required_weight, 0.75), "scene reopen lost weight")
	check(reopened.get_node("LargeCrate").return_radius == 320 and reopened.get_node("LargeCrate").item_mass == 1.0, "reopen lost item settings")
	reopened.free(); history.undo(); workspace.queue_free(); history.clear_history()
	var capture_dir := OS.get_environment("EMBER_PHYSICS_CAPTURE_DIR")
	if not capture_dir.is_empty():
		var camera := Camera3D.new(); scene.add_child(camera); camera.position = Vector3(160, 130, 190); camera.look_at(Vector3(0, 12, -25)); camera.current = true
		var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-55, -30, 0); scene.add_child(sun)
		await process_frame; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture_dir.path_join("physical-crates.png"))
	for error in errors: push_error(error)
	print("PASS physical crates: F/G flight, contact push, summed weights, tether/killbox, save/load and author Undo/reopen" if errors.is_empty() else "FAIL physical crates")
	quit(0 if errors.is_empty() else 1)
