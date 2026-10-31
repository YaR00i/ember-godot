extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
const Store = preload("res://addons/ember_import/ember_quest_store.gd")
const Zone = preload("res://scripts/ember_quest_object_zone.gd")

class BodyFixture extends RigidBody3D:
	var pickup_id := "test_crate"
	var carried := false
	func is_carried() -> bool:
		return carried

func _init() -> void:
	if not Fixture.prepare(self):
		quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	var errors: Array[String] = []
	var quest := {"id": "zone_fixture", "titleRu": "Поставить ящик", "statusFlagId": "zone_status", "objectives": [
		{"id": "first", "textRu": "Сначала принять", "flagId": "zone_first"},
		{"id": "place", "textRu": "Поставить ящик в зону", "flagId": "zone_place", "requiresObjectiveIds": ["first"]},
	]}
	Store.write_document(quest)
	var progress := root.get_node("EmberExploreProgress") as EmberExploreState
	progress.persistence_enabled = false
	progress.flags.clear()
	var zone := Zone.new()
	zone.quest_id = "zone_fixture"
	zone.objective_id = "place"
	zone.target_pickup_id = "test_crate"
	zone.progress_state = progress
	zone.settle_seconds = 0.1
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(12, 12, 12)
	zone.add_child(shape)
	root.add_child(zone)
	var body := BodyFixture.new()
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.collision_layer = 4
	body.collision_mask = 0
	var body_shape := CollisionShape3D.new()
	body_shape.name = "BodyShape"
	body_shape.shape = BoxShape3D.new()
	(body_shape.shape as BoxShape3D).size = Vector3(4, 4, 4)
	body.add_child(body_shape)
	root.add_child(body)
	body.add_to_group("ember_world_item_bodies")
	body.position = Vector3(5, 0, 0)
	if zone.accepts_body(body):
		errors.append("zone accepted a crate whose centre is inside but its bounds are outside")
	body.position = Vector3.ZERO
	body.pickup_id = "wrong_crate"
	if zone.accepts_body(body):
		errors.append("zone accepted the wrong persistent object")
	body.pickup_id = "test_crate"
	body.carried = true
	if zone.accepts_body(body):
		errors.append("zone accepted a crate still held by the player")
	body.carried = false
	if not zone.accepts_body(body):
		errors.append("zone rejected the correct settled crate")
	for index in 20:
		await physics_frame
	if progress.flags.get("zone_place", false):
		errors.append("physical overlap bypassed the existing quest prerequisite")
	progress.apply_authored_flag("zone_first", true, false)
	body.position = Vector3(30, 0, 0)
	for index in 8:
		await physics_frame
	if progress.flags.get("zone_place", false):
		errors.append("zone completed after the crate left before unlocking")
	body.position = Vector3.ZERO
	for index in 20:
		await physics_frame
	if not progress.flags.get("zone_place", false):
		errors.append("settled overlap did not complete the objective")
	body.position = Vector3(30, 0, 0)
	for index in 8:
		await physics_frame
	if not progress.flags.get("zone_place", false):
		errors.append("moving away erased the committed objective")
	body.queue_free()
	zone.queue_free()
	await process_frame
	for error in errors:
		push_error(error)
	print("PASS object zone: bounds/identity/carried/prerequisite/settle/latch" if errors.is_empty() else "FAIL object zone")
	quit(0 if errors.is_empty() else 1)
