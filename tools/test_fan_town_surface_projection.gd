extends SceneTree
## G3 gate for the actual saved fan_town scene and canonical world Surface.

const SCENE_PATH := "res://scenes/fan_town.tscn"
const SURFACE_PATH := "res://content/world_surfaces/fan_town_surface.tres"
const EXPECTED_SOURCE_HASH := "ef5fb669ac57bbd115227edcf1265010f200f98f1b39c7f8912653f05245ccf5"
const EXPECTED_PROVENANCE := "legacy-joi://content/ember/maps/fan_town.json"
const MapLoader = preload("res://scripts/ember_map_loader.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var errors: Array[String] = []
	var scene_hash := FileAccess.get_sha256(SCENE_PATH)
	var surface_hash := FileAccess.get_sha256(SURFACE_PATH)
	var load_started := Time.get_ticks_usec()
	var packed := ResourceLoader.load(
		SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	var scene_load_usec := Time.get_ticks_usec() - load_started
	if packed == null:
		_finish(["fan_town.tscn could not be loaded"])
		return
	var authored := packed.instantiate()
	var authored_map := authored.get_node_or_null("Map") as EmberMapLoader
	if authored_map == null:
		errors.append("fan_town.tscn has no EmberMapLoader Map")
	else:
		if (
			authored_map.visual_surface == null
			or authored_map.visual_surface.resource_path != SURFACE_PATH
		):
			errors.append("fan_town.tscn does not own the canonical Surface link")
		if authored_map.authored_size_blocks != Vector2i(32, 32):
			errors.append("fan_town.tscn has the wrong authored Surface bounds")
		if not authored_map.use_visual_surface_physics:
			errors.append("fan_town.tscn did not opt into Surface physics")
	var surface := (
		authored_map.visual_surface
		if authored_map != null
		else null
	) as EmberVoxelModelResource
	if surface == null:
		authored.free()
		_finish(errors)
		return
	if (
		surface.size_blocks != Vector3i(32, 1, 32)
		or surface.grid_size() != Vector3i(512, 48, 512)
		or not surface.physical
		or surface.imported_from != EXPECTED_PROVENANCE
		or surface.imported_source_hash != EXPECTED_SOURCE_HASH
		or not surface.validation_errors().is_empty()
	):
		errors.append("canonical fan_town Surface metadata or validation is invalid")
	authored.free()

	var map := MapLoader.new()
	map.map_id = "fan_town"
	map.imported_tile_size = 16.0
	map.authored_size_blocks = Vector2i(32, 32)
	map.use_visual_surface_physics = true
	map.visual_surface = surface
	var terrain := Node3D.new()
	terrain.name = "Terrain"
	map.add_child(terrain)
	var terrain_mesh := MeshInstance3D.new()
	terrain_mesh.name = "Mesh"
	terrain_mesh.mesh = BoxMesh.new()
	terrain.add_child(terrain_mesh)
	var terrain_collision := StaticBody3D.new()
	terrain_collision.name = "Collision"
	terrain.add_child(terrain_collision)
	root.add_child(map)
	await process_frame
	var projection := map.get_node_or_null("DerivedVoxelWorldSurface")
	if projection == null:
		errors.append("fan_town did not create its derived Surface projection")
		map.queue_free()
		await process_frame
		_finish(errors)
		return
	if not terrain_mesh.visible or not terrain_collision.visible:
		errors.append("fan_town fallback disappeared before the Surface was ready")

	var physics_started := Time.get_ticks_usec()
	var deadline := physics_started + 15000000
	while not bool(projection.call("physics_is_ready")) and Time.get_ticks_usec() < deadline:
		await process_frame
	var physics_wall_usec := Time.get_ticks_usec() - physics_started
	if not bool(projection.call("physics_is_ready")):
		errors.append("fan_town physical Surface did not finish within 15 seconds")
	elif int(projection.call("collision_chunk_count")) != 64:
		errors.append("fan_town did not build exactly 64 collision chunks")
	if terrain_collision.visible or terrain_collision.collision_layer != 0:
		errors.append("fan_town legacy collision remained active after native physics")

	var sample_point := Vector3(16.5 * 16.0, 128.0, 29.5 * 16.0)
	var floor_sample: Dictionary = map.surface_floor_sample(sample_point)
	if not bool(floor_sample.get("solid", false)):
		errors.append("fan_town Surface has no floor at the southern route sample")
	var route := map.surface_navigation_path(
		Vector3(16.5 * 16.0, 0.0, 29.5 * 16.0),
		Vector3(16.5 * 16.0, 0.0, 28.5 * 16.0),
	)
	if route.size() < 2:
		errors.append("fan_town Surface cannot route between neighboring southern blocks")
	await physics_frame
	await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(
		sample_point,
		Vector3(sample_point.x, -128.0, sample_point.z),
		1,
	)
	var hit := root.world_3d.direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		errors.append("PhysicsServer ray did not hit fan_town Surface collision")

	var visual_started := Time.get_ticks_usec()
	deadline = visual_started + 25000000
	while not bool(projection.call("is_projection_complete")) and Time.get_ticks_usec() < deadline:
		await process_frame
	var visual_wall_usec := Time.get_ticks_usec() - visual_started
	if not bool(projection.call("is_projection_complete")):
		errors.append("fan_town visual Surface did not finish within 25 seconds")
	elif int(projection.call("rendered_chunk_count")) != 1024:
		errors.append("fan_town did not build exactly 1024 visual chunks")
	if terrain_mesh.visible:
		errors.append("fan_town legacy visual remained active after native projection")

	if FileAccess.get_sha256(SCENE_PATH) != scene_hash:
		errors.append("runtime gate changed fan_town.tscn")
	if FileAccess.get_sha256(SURFACE_PATH) != surface_hash:
		errors.append("runtime gate changed fan_town_surface.tres")
	print(
		"  fan_town saved load %.1f ms, physics ready %.1f ms, visual ready %.1f ms"
		% [
			float(scene_load_usec) / 1000.0,
			float(physics_wall_usec) / 1000.0,
			float(visual_wall_usec) / 1000.0,
		]
	)
	map.queue_free()
	await process_frame
	_finish(errors)


func _finish(errors: Array[String]) -> void:
	if errors.is_empty():
		print("PASS fan_town physical Surface projection")
		print("  saved scene owns one dense Surface; legacy terrain remains an atomic fallback")
		quit(0)
	else:
		printerr("FAIL fan_town physical Surface projection")
		for error in errors:
			printerr(" - ", error)
		quit(1)
