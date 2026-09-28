extends SceneTree

const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1200, 800)
	var terrain := TerrainResource.new()
	terrain.width = 64
	terrain.depth = 64
	terrain.palette = PackedColorArray([Color.TRANSPARENT, Color.GREEN])
	var count := terrain.width * terrain.depth
	terrain.heights.resize(count)
	terrain.heights.fill(8)
	terrain.top_materials.resize(count)
	terrain.top_materials.fill(1)
	terrain.base_materials.resize(count)
	terrain.base_materials.fill(1)
	terrain.cap_depths.resize(count)
	terrain.water_levels.resize(count)
	terrain.water_materials.resize(count)
	var projection := EmberTerrainPilotProjection.new()
	projection.source = terrain
	root.add_child(projection)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(32, 70, 105)
	camera.look_at(Vector3(32, 8, 32))
	camera.current = true
	await process_frame
	var failed := 0
	for z in [0, 8, 16, 32, 48, 56, 63]:
		for x in [0, 8, 16, 32, 48, 56, 63]:
			var target := Vector3(float(x) + 0.5, 8, float(z) + 0.5)
			var screen := camera.unproject_position(target)
			var start := camera.project_ray_origin(screen)
			var hit := projection.pick_ground_top(start, start + camera.project_ray_normal(screen) * camera.far)
			if hit.get("cell") != Vector2i(x, z):
				failed += 1
				print("HOVER_MISS target=", Vector2i(x,z), " got=", hit.get("cell", Vector2i(-1,-1)))
	print("COMPACT_HOVER_PICK tested=49 failures=", failed)
	quit(0 if failed == 0 else 1)
