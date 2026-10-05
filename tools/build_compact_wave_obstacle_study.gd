extends SceneTree
## New disposable scene; the existing user water scene/resource are read only.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed := load("res://scenes/compact_sky_reflection_study.tscn") as PackedScene
	var scene := packed.instantiate()
	scene.name = "CompactWaveObstacleStudy"
	scene.map_id = "compact_wave_obstacle_study"
	scene.sandbox_storage_root = "user://ember-compact-wave-obstacle-study"
	var map := scene.get_node("Map") as EmberMapLoader
	map.map_id = scene.map_id
	for region in scene.find_children("*","EmberRegion",true,false):
		region.map_id = scene.map_id
		region.region_id = "compact_wave_obstacle_study_start"
	scene.get_node("CanvasLayer/Gate").text = "EMBER · WAVE OBSTACLE STUDY"
	var terrain := map.compact_terrain as EmberTerrainPilotResource
	var stone := scene.get_node("Map/Props/WaterContactStone") as Node3D
	# The source rig is already immersed after lowering its mean water level.
	# Derive this height from the authored water, rather than lowering it again.
	stone.position.y = float(terrain.origin_y + terrain.water_levels[terrain.column_index(
		int(stone.position.x), int(stone.position.z))]) - 1.0
	var visual := stone.get_node("StoneMesh") as MeshInstance3D
	visual.mesh = visual.mesh.duplicate()
	(visual.mesh as BoxMesh).size = Vector3(24,13,12)
	stone.rotation.y = 0.2
	var sea := preload("res://scripts/prototypes/ember_compact_sea_swash.gd").new()
	sea.build(terrain)
	var center := Vector2.ZERO
	var score := INF
	for item in sea.records:
		if item.z > -10.0 or item.z < -14.0: continue
		var point := Vector2(item.x,item.y)
		var next_score := absf(point.x-float(terrain.width)*0.36) + absf(point.y-float(terrain.depth)*0.30)*0.15
		if next_score < score:
			score = next_score
			center = point
	assert(score < INF,"study needs a real sea bank")
	var column := terrain.column_index(int(center.x),int(center.y))
	var sea_stone := Node3D.new()
	sea_stone.name = "SeaWaveDivider"
	sea_stone.position = Vector3(center.x,float(terrain.origin_y+terrain.water_levels[column])-1.0,center.y)
	scene.get_node("Map/Props").add_child(sea_stone)
	sea_stone.owner = scene
	var mesh := MeshInstance3D.new()
	mesh.name = "StoneMesh"
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).size = Vector3(22,13,12)
	mesh.position.y = 6.5
	mesh.material_override = visual.get_surface_override_material(0)
	sea_stone.add_child(mesh)
	mesh.owner = scene
	var contact := EmberWaterContact3D.new()
	contact.name = "WaterContact"
	contact.static_surface_foam_footprint = true
	sea_stone.add_child(contact)
	contact.owner = scene
	var study := scene.get_node("PlanarReflection")
	study.obstacle_wave_mode = 1
	study.obstacle_wave_strength = 1.0
	study.river_crest_whiteness = 0.45
	var result := PackedScene.new()
	assert(result.pack(scene)==OK)
	assert(ResourceSaver.save(result,"res://scenes/compact_wave_obstacle_study.tscn")==OK)
	print("OBSTACLE_SCENE sea=",center," source_resource=",terrain.resource_path)
	scene.free()
	quit()
