extends RefCounted
## Small saved native maps for mechanics gates, never author maps. Logical
## res:// destinations are process-local Resource aliases; writes use user://.

const ExploreScene = preload("res://scripts/ember_explore_scene.gd")
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")


static func save_map(map_id: String, directory: String, doors: Array[Dictionary] = [], returns: Array[Dictionary] = [], chests: Array[Dictionary] = [], tile_size: float = 16.0, interactions: Array[Dictionary] = [], scripted_regions: Array[Dictionary] = [], debug_damage: float = 0.0, plain_props: Array[Dictionary] = []) -> PackedScene:
	if not directory.begins_with("user://ember-tests/") or not map_id.is_valid_identifier(): return null
	var scene := Node3D.new()
	scene.name = map_id
	scene.set_script(ExploreScene)
	scene.set("map_id", map_id)
	scene.set("player_debug_damage", debug_damage)
	var map := EmberMapLoader.new()
	map.name = "Map"
	map.map_id = map_id
	map.imported_tile_size = tile_size
	map.hydrate_legacy_regions = false
	map.native_cutaway_enabled = false
	map.authored_size_blocks = Vector2i(4, 4)
	map.compact_terrain = _ground()
	scene.add_child(map)
	var regions := Node3D.new()
	regions.name = "Regions"
	regions.position = Vector3(2, 0, 3)
	map.add_child(regions)
	var entries := Node3D.new()
	entries.name = "Entries"
	entries.position = Vector3(1, 0, 2)
	regions.add_child(entries)
	entries.add_child(_region(map_id, "entry", "player_start", Vector3(29, 4, 11)))
	for definition in scripted_regions:
		var region := _region(map_id, definition.id, "trigger", definition.position)
		region.script_id = definition.script
		regions.add_child(region)
	for destination in returns:
		var region := _region(map_id, destination.id, "trigger", destination.position)
		region.target_map_id = destination.map
		region.target_region_id = destination.region
		regions.add_child(region)
	for definition in chests:
		var chest := _region(map_id, definition.id, "chest", definition.position)
		chest.loot_ids.assign(definition.loot)
		chest.closed_model_id = definition.get("closed_model", "")
		chest.open_model_id = definition.get("open_model", "")
		if definition.get("saved_visual") is PackedScene:
			var visual := (definition.saved_visual as PackedScene).instantiate()
			visual.name = "ChestVisual"
			chest.add_child(visual)
		(entries if definition.get("nested", false) else regions).add_child(chest)
	var props := Node3D.new()
	props.name = "Props"
	map.add_child(props)
	for definition in interactions:
		var prop := EmberVoxelProp.new() if definition.get("marker_mesh", false) else Node3D.new()
		prop.name = definition.id
		prop.position = definition.position
		if prop is EmberVoxelProp:
			prop.placement_id = definition.id
			var mesh := MeshInstance3D.new()
			mesh.name = "Mesh"
			var box := BoxMesh.new()
			box.size = Vector3(3, 8, 3)
			mesh.mesh = box
			mesh.position = Vector3(1, 4, 2)
			prop.add_child(mesh)
		props.add_child(prop)
		prop.add_child(EmberSceneAuthoring.make_interact(definition.values, tile_size))
	for destination in doors:
		var prop := Node3D.new()
		prop.name = destination.id
		props.add_child(prop)
		var door := EmberInteract.new()
		door.name = "Interact"
		door.kind = "door"
		door.target_map_id = destination.map
		door.target_region_id = destination.region
		prop.add_child(door)
	for definition in plain_props:
		var prop := EmberVoxelProp.new()
		prop.name = definition.id
		prop.placement_id = definition.id
		prop.block_world_size = tile_size
		prop.position = definition.get("position", Vector3.ZERO)
		props.add_child(prop)
	var layer := CanvasLayer.new()
	layer.name = "CanvasLayer"
	scene.add_child(layer)
	var hud := Label.new()
	hud.name = "Gate"
	layer.add_child(hud)
	_set_owner(scene, scene)
	var packed := PackedScene.new()
	var error := packed.pack(scene)
	scene.free()
	if error != OK: return null
	var path := directory.path_join(map_id + ".tscn")
	if ResourceSaver.save(packed, path) != OK: return null
	var reopened := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if reopened != null: reopened.take_over_path(EmberMapTransition.scene_path(map_id))
	return reopened


static func prepare(tree: SceneTree, directory: String) -> Dictionary:
	var support := directory.path_join("item-support")
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) if directory.begins_with("user://ember-tests/") else ERR_INVALID_PARAMETER
	var state := {"error": error, "progress_isolated": false}
	ProjectSettings.set_setting("ember/pack_path", support)
	var isolate := func(node: Node) -> void:
		if not node is EmberExploreState: return
		var progress := node as EmberExploreState
		progress.persistence_enabled = false
		progress.restore_enabled = false
		progress.storage_root = directory.path_join("save-v2")
		progress.legacy_storage_root = directory.path_join("save-v1")
		state.progress_isolated = not progress.is_node_ready()
	tree.root.child_entered_tree.connect(isolate)
	var progress := tree.root.get_node_or_null("EmberExploreProgress")
	if progress != null: isolate.call(progress)
	return state


static func _region(map_id: String, id: String, kind: String, position: Vector3) -> EmberRegion:
	var region := EmberRegion.new()
	region.name = id
	region.map_id = map_id
	region.region_id = id
	region.kind = kind
	region.position = position
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(4, 40, 4)
	shape.shape = box
	region.add_child(shape)
	return region


static func _set_owner(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		# Keep an instanced prefab's children owned by that instance. Packing
		# them again as outer-scene children would duplicate its mesh nodes.
		if child.scene_file_path.is_empty(): _set_owner(child, root)


static func _ground() -> Terrain:
	var terrain := Terrain.new()
	terrain.width = 64
	terrain.depth = 64
	terrain.palette = PackedColorArray([Color.TRANSPARENT, Color.BROWN])
	var count := terrain.width * terrain.depth
	terrain.heights.resize(count)
	terrain.heights.fill(4)
	terrain.top_materials.resize(count)
	terrain.top_materials.fill(1)
	terrain.base_materials = terrain.top_materials.duplicate()
	terrain.cap_depths.resize(count)
	terrain.cap_depths.fill(1)
	terrain.water_levels.resize(count)
	terrain.water_materials.resize(count)
	return terrain
