extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
const FLAG := "autumn_leaf_pile_revealed"
const PICKUP := "autumn_leaf_bottle"
class StubMap extends EmberMapLoader:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _exit_tree() -> void: pass
class Host extends "res://scripts/ember_explore_scene.gd":
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _exit_tree() -> void: pass
var errors: Array[String] = []
var host: Host
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
	var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true; event.position = Vector2(100,100)
	Input.parse_input_event(event); await process_frame; await physics_frame
	event = InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT
	Input.parse_input_event(event)
func pickup() -> Node3D:
	for body in get_nodes_in_group("ember_world_item_bodies"):
		if host.is_ancestor_of(body) and body.pickup_id == PICKUP and not body.is_queued_for_deletion(): return body
	return null
func restore_slot(state: EmberExploreState, slot: int) -> void:
	var loaded := EmberExploreState.new(); loaded.storage_root = state.storage_root
	check(loaded.load_slot(slot), "cold load failed for slot " + str(slot))
	state.adopt_loaded_save(loaded); loaded.free(); await frames(5)
func check_leaf_continuity(pile: Node3D) -> void:
	var packed: PackedScene = pile.scatter_effect
	var first := packed.instantiate(); var second := packed.instantiate()
	host.add_child(first); host.add_child(second)
	first.set_physics_process(false); second.set_physics_process(false)
	first.play(pile.global_transform, 16.0, Vector3.FORWARD)
	second.play(pile.global_transform, 16.0, Vector3.FORWARD)
	check(first.leaf_transforms.size() == 240 and first._leaf_parts.size() == 240 and first.get_child_count() == 4, "all source cards must fly in four batches")
	var source := (pile.get_node("PileVisual").mesh as ArrayMesh).surface_get_arrays(0)
	var count := 0
	for variant in 4:
		var batch: MultiMeshInstance3D = first.get_child(variant)
		var other: MultiMeshInstance3D = second.get_child(variant)
		check(batch.multimesh != other.multimesh, "simultaneous flights share writable instance buffer")
		check(batch.material_override.shader.resource_path == "res://shaders/ember_tree_leaf_cards.gdshader", "pile scatter lost shared tree shader")
		var card := (batch.multimesh.mesh as ArrayMesh).surface_get_arrays(0)
		count += batch.multimesh.instance_count
		for instance in batch.multimesh.instance_count:
			var index := instance * 4 + variant
			var pose := batch.multimesh.get_instance_transform(instance)
			for vertex in 6:
				check((first.global_transform * (pose * card[Mesh.ARRAY_VERTEX][vertex])).is_equal_approx(pile.global_transform * source[Mesh.ARRAY_VERTEX][index * 6 + vertex]), "leaf disappeared or jumped at transition: %d" % index)
				check(card[Mesh.ARRAY_TEX_UV][vertex].is_equal_approx(source[Mesh.ARRAY_TEX_UV][index * 6 + vertex]), "scatter changed leaf artwork")
	check(count == 240 and (pile.get_node("PileVisual").mesh as ArrayMesh).get_aabb().end.y > 9.0, "leaf mound missing cards or raised silhouette")
	first._physics_process(0.2)
	check(first.get_child(0).multimesh.get_instance_transform(0) != second.get_child(0).multimesh.get_instance_transform(0), "one flight changed another flight")
	first._physics_process(2.0)
	for index in first._leaf_parts.size():
		check(first.get_child(index % 4).multimesh.get_instance_transform(index / 4).basis.get_scale().is_equal_approx(first.leaf_transforms[index].basis.get_scale()), "leaf shrank before flight completed")
	first._physics_process(0.35)
	for index in first._leaf_parts.size():
		var ratio: Vector3 = first.get_child(index % 4).multimesh.get_instance_transform(index / 4).basis.get_scale() / first.leaf_transforms[index].basis.get_scale()
		check(ratio.is_equal_approx(Vector3.ONE * 0.5), "leaf did not shrink gradually at end of flight")
	first.free(); second.free()
func _run() -> void:
	var state := root.get_node("EmberExploreProgress") as EmberExploreState
	state.persistence_enabled = false; state.world_items.clear(); state.flags.clear()
	host = Host.new(); host.name = "LeafPileFixture"
	var map := StubMap.new(); map.name = "Map"; host.add_child(map)
	var canvas := CanvasLayer.new(); canvas.name = "CanvasLayer"; host.add_child(canvas)
	var hud := Label.new(); hud.name = "Gate"; canvas.add_child(hud)
	root.add_child(host); current_scene = host
	var floor_body := StaticBody3D.new(); var floor_shape := CollisionShape3D.new(); floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(240, 2, 240); floor_shape.position.y = -1; floor_body.add_child(floor_shape); host.add_child(floor_body)
	var pile := load("res://prefabs/items/autumn_leaf_pile.scn").instantiate() as Area3D; host.add_child(pile)
	state.progress_changed.connect(host._refresh_world_items); host._refresh_world_items()
	var player := EmberPlayer.new(); player.progress_state = state; player.position = Vector3(0, 0.1, 24); host.add_child(player); player.set_physics_process(false)
	var inventory_ui := EmberInventoryUi.new(); inventory_ui.progress_state = state; root.add_child(inventory_ui); player.inventory_ui = inventory_ui
	await frames(30)
	check_leaf_continuity(pile)
	check(pickup() != null and not pickup().visible and pickup().collision_layer == 0 and pickup().freeze, "pickup was exposed before strike")
	var base_inventory := int(state.inventory.get("shore_empty_bottle", 0))
	player._try_interact(); check(int(state.inventory.get("shore_empty_bottle", 0)) == base_inventory, "F collected hidden pickup")
	state.persistence_enabled = true; state.set_world_context("landscape_compact", player, 16.0)
	check(state.save_slot(0), "unrevealed save failed")
	inventory_ui.open(); await click(); inventory_ui.close()
	check(not state.flags.get(FLAG, false), "open inventory scattered pile")
	var wall := StaticBody3D.new(); wall.position = Vector3(0, 15, 18)
	var wall_shape := CollisionShape3D.new(); wall_shape.shape = BoxShape3D.new(); wall_shape.shape.size = Vector3(40, 30, 2); wall.add_child(wall_shape); host.add_child(wall)
	await frames(3); player.set("_next_world_strike_ms", 0)
	check(not player.world_strike() and not state.flags.get(FLAG, false), "strike scattered leaves through wall")
	wall.queue_free(); await frames(3)
	state.combat_party_locked = true
	check(not pile.receive_world_hit(player, Vector3.FORWARD), "combat handoff scattered pile")
	state.combat_party_locked = false
	capture_dir = OS.get_environment("EMBER_LEAF_CAPTURE_DIR")
	if not capture_dir.is_empty():
		var floor_visual := MeshInstance3D.new(); floor_visual.mesh = BoxMesh.new(); floor_visual.mesh.size = Vector3(240, 2, 240); floor_visual.position.y = -1
		var material := StandardMaterial3D.new(); material.albedo_color = Color(0.35,0.42,0.23); floor_visual.material_override = material; host.add_child(floor_visual)
		var camera := Camera3D.new(); host.add_child(camera); camera.position = Vector3(46,48,64); camera.look_at(Vector3(0,4,0)); camera.current = true; camera.fov = 43
		var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-55,-30,0); host.add_child(sun)
		var world := WorldEnvironment.new(); world.environment = Environment.new(); world.environment.background_mode = Environment.BG_COLOR; world.environment.background_color = Color(0.52,0.65,0.75); world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; world.environment.ambient_light_color = Color.WHITE; world.environment.ambient_light_energy = 0.5; host.add_child(world)
		await shot("pile-before")
	var writes := [0]; var saved := func(_path): writes[0] += 1
	state.saved.connect(saved); player.set("_next_world_strike_ms", 0); await click(); await frames(10)
	check(state.flags.get(FLAG, false) and not pile.get_node("PileVisual").visible and pile.collision_layer == 0, "native LMB did not scatter pile")
	check(pickup() != null and pickup().visible and pickup().collision_layer == 4 and not pickup().freeze, "revealed pickup remained hidden/frozen")
	check(int(state.inventory.get("shore_empty_bottle", 0)) == base_inventory and writes[0] == 1, "strike gave inventory loot or duplicated autosave")
	check(not pile.receive_world_hit(player, Vector3.FORWARD) and writes[0] == 1, "repeat strike duplicated reveal")
	var effects := get_nodes_in_group("ember_world_break_effects")
	check(effects.size() == 1 and effects[0].get("_leaf_parts").size() == 240, "leaf scatter did not preserve all source cards")
	check(not player.get("_action_message").contains("ящик"), "leaf strike used crate feedback")
	await shot("pile-scattering")
	check(state.save_slot(1), "revealed-unpicked save failed")
	await frames(180); check(get_nodes_in_group("ember_world_break_effects").is_empty(), "leaf effect did not clean up")
	await shot("pile-revealed")
	await restore_slot(state, 0)
	check(pickup() != null and not pickup().visible and pickup().freeze, "existing pickup did not hide on old save")
	await restore_slot(state, 1)
	check(pickup() != null and pickup().visible and not pickup().freeze, "existing hidden pickup did not resume physics")
	var shape := pickup().get_node("Pickup/Shape") as CollisionShape3D
	player.global_position = Vector3(shape.global_position.x, 0.1, shape.global_position.z + 5.0)
	player._try_interact(); await frames(3)
	check(int(state.inventory.get("shore_empty_bottle", 0)) == base_inventory + 1 and pickup() == null, "F did not collect revealed item exactly once")
	check(int(state.world_items.get(PICKUP, {}).get("count", 1)) == 0, "pickup absence was not stored")
	player._try_interact(); check(int(state.inventory.get("shore_empty_bottle", 0)) == base_inventory + 1, "repeat F duplicated loot")
	check(state.save_slot(2), "collected save failed")
	state.saved.disconnect(saved)
	await restore_slot(state, 0)
	check(pile.get_node("PileVisual").visible and pickup() != null and not pickup().visible, "unrevealed cold restore lost cover")
	await restore_slot(state, 1)
	check(not pile.get_node("PileVisual").visible and pickup() != null and pickup().visible and not pickup().freeze, "revealed cold restore lost pickup")
	await restore_slot(state, 2)
	check(not pile.get_node("PileVisual").visible and pickup() == null and int(state.inventory.get("shore_empty_bottle", 0)) == base_inventory + 1, "collected cold restore respawned loot")
	# Real physics overlap, not a direct call to the trample handler.
	player.global_position = Vector3(0,0.1,40); await frames(4)
	await restore_slot(state,0)
	var other := CharacterBody3D.new(); other.collision_layer = 2
	var other_shape := CollisionShape3D.new(); other_shape.shape = SphereShape3D.new(); other_shape.shape.radius = 3
	other.add_child(other_shape); other.position = Vector3(0,3,0); host.add_child(other)
	await frames(4); check(not state.flags.get(FLAG,false), "unrelated body scattered pile")
	state.combat_party_locked = true
	player.global_position = Vector3(0,0.1,0); await frames(4)
	check(not state.flags.get(FLAG,false), "combat-locked overlap scattered pile")
	player.global_position = Vector3(0,0.1,40); await frames(4)
	state.combat_party_locked = false
	writes[0] = 0; state.saved.connect(saved)
	await shot("walk-before")
	player.velocity = Vector3(0,0,-10); player.global_position = Vector3(0,0.1,0); await frames(6)
	check(state.flags.get(FLAG,false) and not pile.get_node("PileVisual").visible, "walking into pile did not scatter leaves")
	check(pickup() != null and pickup().visible and not pickup().freeze, "walking did not expose pickup")
	check(writes[0] == 1 and int(state.inventory.get("shore_empty_bottle",0)) == base_inventory, "walking duplicated save or gave instant loot")
	await shot("walk-scattering")
	player.global_position = Vector3(0,0.1,40); await frames(4)
	player.global_position = Vector3(0,0.1,0); await frames(4)
	check(writes[0] == 1 and get_nodes_in_group("ember_world_break_effects").size() == 1, "repeat walking duplicated reveal/effect")
	check(state.save_slot(1), "walking reveal save failed")
	state.saved.disconnect(saved)
	await restore_slot(state,0)
	check(pile.get_node("PileVisual").visible and not state.flags.get(FLAG,false), "loading old save under stationary player immediately scattered leaves")
	await restore_slot(state,1)
	check(not pile.get_node("PileVisual").visible and pickup() != null and pickup().visible, "walking reveal did not survive cold load")
	var walk_pickup_center: Vector3 = pickup().get_node("Pickup/Shape").global_position
	player.global_position = Vector3(walk_pickup_center.x,0.1,walk_pickup_center.z+5)
	player._try_interact(); await frames(3)
	check(pickup() == null and int(state.inventory.get("shore_empty_bottle",0)) == base_inventory+1, "F after walking failed")
	await frames(180); check(get_nodes_in_group("ember_world_break_effects").is_empty(), "walking scatter did not clean up")
	var source := (load("res://prefabs/items/autumn_leaf_pile.scn") as PackedScene).instantiate()
	var packed := PackedScene.new(); packed.pack(source); source.free()
	check(ResourceSaver.save(packed, "user://leaf-pile-roundtrip.scn") == OK, "authored scene save failed")
	var reopened := (load("user://leaf-pile-roundtrip.scn") as PackedScene).instantiate()
	check(reopened.revealed_flag_id == reopened.get_node("HiddenPickup").available_flag_id and reopened.get_node("HiddenPickup").pickup_id == PICKUP, "scene reopen lost authored binding")
	reopened.free(); state.progress_changed.disconnect(host._refresh_world_items); state.persistence_enabled = false
	inventory_ui.queue_free(); host.queue_free(); await process_frame; await process_frame
	for error in errors: push_error(error)
	print("PASS leaf pile: strike guards, real player overlap/non-player/combat/reentry guards, gated pickup/F, one reveal, cold saves, source roundtrip and cosmetic cleanup" if errors.is_empty() else "FAIL leaf pile")
	quit(0 if errors.is_empty() else 1)
