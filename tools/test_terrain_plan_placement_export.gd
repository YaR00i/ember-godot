extends SceneTree
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args(); assert(args.size() == 1,"Pass exported placement fixture")
	var scene := (ResourceLoader.load(args[0]) as PackedScene).instantiate()
	var map := scene.get_node("Map") as EmberMapLoader; var pending: Array[Node] = [scene]; var models := {}; var count := 0
	while not pending.is_empty():
		var node := pending.pop_back() as Node
		assert(not node.has_meta(Plan.META) and not node.has_meta(Plan.GROVE_MEMBER_META) and not node.has_meta(Plan.GROVE_GROUP_META),"Authoring placement leaked into export")
		for child in node.get_children(): pending.append(child)
	for prop in map.get_node("Props").get_children():
		assert(prop is EmberVoxelProp and prop.scene_file_path.begins_with("res://prefabs/voxels/"),"Ordinary native prop lost")
		assert(prop.get_node("Mesh").mesh != null and prop.get_node("Collision/Shape").shape != null,"Mesh/collision lost")
		models[prop.model_id] = true; count += 1
	assert(models.size() == 3 and count >= 3,"Mixed set lost in PCK")
	assert(map.compact_terrain.column_value("heights",map.compact_terrain.column_index(192,192)) == 96,"Placement changed terrain")
	scene.free(); print("PLACEMENT_EXPORT PASS count=",count," models=",models.keys()," authoring data omitted / ordinary geometry retained"); quit()
