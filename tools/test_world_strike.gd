extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
const Item = preload("res://scripts/ember_world_item_3d.gd")
const SOURCE := "res://content/voxel_models/quest_carry_crate.tres"
var errors: Array[String] = []
var capture_dir := ""
func _init() -> void:
	if not Fixture.prepare(self): quit(2); return
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: errors.append(message)
func frames(n: int) -> void:
	for i in n: await physics_frame
func shot(label: String) -> void:
	if capture_dir.is_empty(): return
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir.path_join(label + ".png"))
func click() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true; event.position = Vector2(100, 100)
	Input.parse_input_event(event)
	await process_frame; await physics_frame
	event = InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = false
	Input.parse_input_event(event)
func _run() -> void:
	var state := root.get_node("EmberExploreProgress") as EmberExploreState
	state.persistence_enabled = false; state.world_items.clear(); state.flags.clear()
	var source_hash := FileAccess.get_sha256(SOURCE)
	var baked := (load("res://prefabs/items/quest_crate_break.scn") as PackedScene).instantiate()
	var source := load(SOURCE) as EmberVoxelModelResource
	check(baked.get_meta("voxel_source_sha256") == source_hash, "fragment bake is stale")
	for part in baked.get_children():
		var colors: PackedColorArray = part.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		for color in colors:
			var valid := false
			for entry in source.palette:
				if absf(color.r - entry.r) < 0.005 and absf(color.g - entry.g) < 0.005 and absf(color.b - entry.b) < 0.005: valid = true; break
			if not valid: check(false, "fragment lost canonical palette"); break
	baked.free()
	var scene := Node3D.new(); root.add_child(scene); current_scene = scene
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new(); floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(240, 2, 240); floor_shape.position.y = -1
	floor_body.add_child(floor_shape); scene.add_child(floor_body)
	var kit := load("res://prefabs/items/physical_crates.tscn").instantiate() as Node3D
	scene.add_child(kit)
	var small = kit.get_node("SmallCrate"); var large = kit.get_node("LargeCrate")
	var player := EmberPlayer.new(); player.progress_state = state; player.position = Vector3(-24, 0.1, 20)
	scene.add_child(player); player.set_physics_process(false)
	var inventory_ui := EmberInventoryUi.new(); inventory_ui.progress_state = state
	root.add_child(inventory_ui); player.inventory_ui = inventory_ui
	await frames(65)
	var inventory_before := state.inventory.duplicate(true)
	# Input must reach the unhandled stage only after UI has had its chance.
	inventory_ui.open(); await click(); await frames(15)
	check(int(state.world_items[small.pickup_id].count) == 1 and get_nodes_in_group("ember_world_strike_effects").is_empty(), "open inventory allowed a world strike")
	inventory_ui.close()
	var panel := Panel.new(); panel.position = Vector2.ZERO; panel.size = Vector2(1280, 800); root.add_child(panel)
	await process_frame; await click(); await frames(15)
	check(get_nodes_in_group("ember_world_strike_effects").is_empty(), "GUI click reached world strike")
	panel.queue_free(); await process_frame
	state.combat_party_locked = true
	check(not player.world_strike(), "combat handoff allowed exploration strike")
	state.combat_party_locked = false
	# A wall inside the reach volume still blocks the line of impact.
	var wall := StaticBody3D.new(); var wall_shape := CollisionShape3D.new(); wall_shape.shape = BoxShape3D.new()
	wall_shape.shape.size = Vector3(20, 30, 2); wall.add_child(wall_shape); wall.position = Vector3(-24, 15, 12); scene.add_child(wall)
	await frames(3); player.set("_next_world_strike_ms", 0)
	check(not player.world_strike() and int(state.world_items[small.pickup_id].count) == 1, "strike passed through wall")
	wall.queue_free(); await frames(3)
	player.position = Vector3(24, 0.1, 28); player.set("_next_world_strike_ms", 0)
	check(not player.world_strike() and int(state.world_items[large.pickup_id].count) == 1, "large crate was broken")
	player.position = Vector3(-24, 0.1, 6); small.take(player); await frames(2)
	player.set("_next_world_strike_ms", 0)
	check(small.is_carried() and not player.world_strike(), "held crate allowed strike")
	small.recover_from_void(); player.position = Vector3(80, 0.1, 80); player.set("_next_world_strike_ms", 0)
	check(not player.world_strike(), "empty strike hit distant crate")
	# A real plate must lose the physical crate when it is destroyed.
	var plate = kit.get_node("Circuit/WeightPlate"); plate.required_weight = 0.25
	small.position = Vector3(24, 0.2, -64); small.linear_velocity = Vector3.ZERO
	player.position = Vector3(24, 0.1, -44); await frames(70)
	check(plate.value, "crate did not press plate before strike")
	capture_dir = OS.get_environment("EMBER_STRIKE_CAPTURE_DIR")
	if not capture_dir.is_empty():
		var floor_visual := MeshInstance3D.new(); floor_visual.mesh = BoxMesh.new(); floor_visual.mesh.size = Vector3(240, 2, 240); floor_visual.position.y = -1
		var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.4, 0.48, 0.26); floor_visual.material_override = mat; scene.add_child(floor_visual)
		var camera := Camera3D.new(); scene.add_child(camera); camera.position = Vector3(114, 100, 80); camera.look_at(Vector3(24, 12, -48)); camera.current = true
		var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-55, -30, 0); scene.add_child(sun)
		await shot("before-strike")
	state.persistence_enabled = true; state.set_world_context("landscape_compact", player, 16.0)
	var writes := [0]; var saved := func(_path): writes[0] += 1
	state.saved.connect(saved)
	player.set("_next_world_strike_ms", 0)
	var started := Time.get_ticks_usec(); await click()
	check(int(state.world_items["physics_small_crate"].count) == 0, "LMB did not commit destruction")
	check(writes[0] == 1 and state.inventory == inventory_before, "destruction duplicated save or gave inventory items")
	check(not state.destroy_world_item("physics_small_crate") and writes[0] == 1, "repeat destruction saved twice")
	var effects := get_nodes_in_group("ember_world_break_effects")
	check(effects.size() == 1 and effects[0].get("_parts").size() == 8, "wrong number of baked fragments")
	await shot("crate-fragments")
	print("STRIKE observed frame path us=", Time.get_ticks_usec() - started)
	await frames(10); check(not plate.value, "destroyed crate still pressed plate")
	check(not is_instance_valid(small), "destroyed body retained collision/prompt")
	var loaded := EmberExploreState.new(); loaded.storage_root = state.storage_root
	check(loaded.load_autosave() and int(loaded.world_items["physics_small_crate"].count) == 0, "cold save resurrected broken crate")
	var restored := Item.new(); restored.pickup_id = "physics_small_crate"; restored.item_id = "quest_crate"; restored.progress_state = loaded
	scene.add_child(restored); await frames(2)
	check(not is_instance_valid(restored), "authored registration resurrected destroyed crate")
	loaded.free(); state.saved.disconnect(saved); state.persistence_enabled = false
	await frames(90)
	check(get_nodes_in_group("ember_world_break_effects").is_empty() and get_nodes_in_group("ember_world_strike_effects").is_empty(), "cosmetic effects did not clean up")
	# Burst load is explicitly bounded, with no RigidBody debris/save records.
	var effect_scene := load("res://prefabs/items/quest_crate_break.scn") as PackedScene
	var record_count := state.world_items.size()
	for i in 6:
		var effect = effect_scene.instantiate(); scene.add_child(effect); effect.play(Transform3D.IDENTITY, 16.0, Vector3.FORWARD)
	check(get_nodes_in_group("ember_world_break_effects").size() <= 4 and state.world_items.size() == record_count, "fragment burst exceeded budget or wrote world items")
	await frames(90)
	check(get_nodes_in_group("ember_world_break_effects").is_empty(), "burst effects leaked")
	check(FileAccess.get_sha256(SOURCE) == source_hash, "strike modified canonical voxel model")
	inventory_ui.queue_free(); scene.queue_free(); await process_frame; await process_frame
	for error in errors: push_error(error)
	print("PASS world strike: native LMB/UI/wall/reach/held/big guards, voxel fragments, plate release, one save/cold load, source immutable and bounded cleanup" if errors.is_empty() else "FAIL world strike")
	quit(0 if errors.is_empty() else 1)
