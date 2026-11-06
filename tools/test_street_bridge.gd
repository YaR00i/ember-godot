extends SceneTree

const Plot = preload("res://addons/ember_import/ember_plot_construction.gd")
const TILE := 16.0

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bridge := Plot.make_street_bridge(Vector3.ZERO, Vector3(0, 0, 8.0 * TILE), 3.0, TILE, "stone")
	root.add_child(bridge)
	_check(await _walk(bridge) == "crossed", "intact stone bridge supports a walk across")
	_check(Plot.style_street_bridge(bridge, "broken", TILE), "break an existing bridge")
	await physics_frame
	await physics_frame
	var space := bridge.get_world_3d().direct_space_state
	for x in [-1.4, 0.0, 1.4]:
		var middle := bridge.position + Vector3(x * TILE, 0, 0)
		_check(_hit_floor(space, middle).is_empty(), "no floor across the gap at x=%s" % x)
	for z in [0.6, 7.4]:
		_check(not _hit_floor(space, Vector3(0, 0, z * TILE)).is_empty(), "approach stays solid at z=%s" % z)
	_check(await _walk(bridge) == "fell", "character falls at the gap")
	_check(Plot.style_street_bridge(bridge, "wood", TILE), "restore an intact bridge")
	_check(await _walk(bridge) == "crossed", "restored bridge supports the same walk")
	bridge.queue_free()
	print("STREET_BRIDGE ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)


func _walk(bridge: StaticBody3D) -> String:
	var actor := CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	actor.floor_snap_length = TILE * 0.25
	actor.position = bridge.position + Vector3(0, TILE * 0.05, -3.2 * TILE)
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = TILE * 0.26
	capsule.height = TILE * 1.5
	collider.shape = capsule
	collider.position.y = capsule.height * 0.5
	actor.add_child(collider)
	root.add_child(actor)
	var outcome := "stalled"
	for tick in 180:
		await physics_frame
		actor.velocity.y -= TILE * 9.8 / 60.0
		actor.velocity.z = TILE * 3.2
		actor.move_and_slide()
		if actor.position.y < -TILE * 0.4:
			outcome = "fell"
			break
		if actor.position.z >= bridge.position.z + 3.0 * TILE and actor.is_on_floor():
			outcome = "crossed"
			break
	actor.queue_free()
	return outcome


func _hit_floor(space: PhysicsDirectSpaceState3D, point: Vector3) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 4.0, point - Vector3.UP * 5.0, 1))


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
