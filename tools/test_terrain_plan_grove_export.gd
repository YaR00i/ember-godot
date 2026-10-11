extends SceneTree
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1,"Pass exported grove fixture scene path")
	var scene := (ResourceLoader.load(args[0]) as PackedScene).instantiate()
	var map := scene.get_node("Map") as EmberMapLoader
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node := pending.pop_back() as Node
		assert(not node.has_meta(Plan.META) and not node.has_meta(Plan.GROVE_MEMBER_META) and not node.has_meta(Plan.GROVE_GROUP_META),"Authoring grove data leaked into export")
		for child in node.get_children(): pending.append(child)
	var count := 0
	for prop in map.get_node("Props").get_children():
		assert(prop is EmberVoxelProp,"Grove is no longer an ordinary voxel prop")
		assert(prop.scene_file_path.begins_with("res://prefabs/voxels/"),"Native prefab reference lost")
		assert(prop.get_node("Mesh").mesh != null and prop.get_node("Collision/Shape").shape != null,"Grove geometry/collision lost")
		count += 1
	assert(count > 0,"Export lost grove trees")
	var terrain := map.compact_terrain
	assert(terrain.column_value("heights",terrain.column_index(192,192)) == 96,"Grove changed or lost terrain")
	scene.free()
	print("TERRAIN_GROVE_EXPORT PASS trees=",count," authoring data omitted / ordinary prefab meshes and collision retained")
	quit()
