extends RefCounted
## Generated mechanics inputs, never an authored level. Runtime files live in
## user://; editor-open/save files require the guarded disposable test project.
const Native = preload("res://tools/fixtures/ember_voxel_native_test_fixture.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const SCENE := "res://tools/fixtures/generated_editor_mechanics.tscn"
const MAP_ID := "qa_editor_mechanics"

static func saved_property(scene: PackedScene, path: String, property: String, fallback: Variant = null) -> Variant:
	var state := scene.get_state()
	for node in state.get_node_count():
		var node_path := str(state.get_node_path(node)).trim_prefix("./")
		if node_path != path and not node_path.ends_with("/"+path):continue
		for field in state.get_node_property_count(node):
			if state.get_node_property_name(node,field) == property:return state.get_node_property_value(node,field)
		var instance := state.get_node_instance(node)
		if instance != null:return saved_property(instance,".",property,fallback)
	return fallback

static func prop(name: String, slab := false) -> EmberVoxelProp:
	var source := Native.source(Native.IDS[1] if slab else Native.IDS[0])
	var result := EmberVoxelPrefab.prepare_resource(source).instantiate() as EmberVoxelProp
	result.name = name
	result.placement_id = "fixture_" + name
	return result

static func make_scene() -> Node3D:
	var scene := Node3D.new()
	scene.name = "EditorMechanicsFixture"
	scene.set_script(load("res://scripts/world_canvas.gd"))
	scene.set("map_id",MAP_ID)
	var map := EmberMapLoader.new()
	map.name = "Map"; map.map_id = MAP_ID
	map.native_cutaway_enabled = false
	map.authored_size_blocks = Vector2i(40,30)
	map.camera_distance = 200.0
	scene.add_child(map)
	var terrain := Node3D.new(); terrain.name = "Terrain"; map.add_child(terrain)
	var floor := StaticBody3D.new(); floor.name = "StoneQuay"; terrain.add_child(floor)
	var collision := CollisionShape3D.new(); collision.name = "Collision"
	var box := BoxShape3D.new(); box.size = Vector3(640,4,480)
	collision.shape = box; collision.position = Vector3(320,-2,240); floor.add_child(collision)
	var wall := CollisionShape3D.new(); wall.shape = BoxShape3D.new()
	var wall_shape := BoxShape3D.new(); wall_shape.size = Vector3(2,40,480); wall.shape = wall_shape
	wall.position = Vector3(64,16,240); floor.add_child(wall)
	var deck := Node3D.new(); deck.name = "TimberPier"; terrain.add_child(deck)
	var assembly := Node3D.new(); assembly.name = "Visual"; deck.add_child(assembly)
	for i in 12:
		var part := prop("Part%d" % i,true); part.position = Vector3(180+i*2,0,100)
		assembly.add_child(part)
	var water := Node3D.new(); water.name = "BayWater"; terrain.add_child(water)
	var visual := MeshInstance3D.new(); visual.name = "Visual"; water.add_child(visual)
	var water_mesh := BoxMesh.new(); water_mesh.size = Vector3(64,1,480)
	water_mesh.material = EmberVoxelSurfaceMaterials.water_material().duplicate()
	water_mesh.material.set_shader_parameter("background_water",true)
	visual.mesh = water_mesh; visual.position = Vector3(32,-1,240)
	var props := Node3D.new(); props.name = "Props"; map.add_child(props)
	var n := 0
	for label in ["CargoA","CargoB","CargoC","BarrelA","BarrelB","EditableBlock"]:
		var object := prop(label); object.position = Vector3(240+n*20,0,180); n += 1
		props.add_child(object)
	var post := StaticBody3D.new(); post.name = "MooringPost96_240"; props.add_child(post)
	post.position = Vector3(96,0,240)
	var post_visual := MeshInstance3D.new(); post_visual.name = "Visual"
	var post_mesh := BoxMesh.new(); post_mesh.size = Vector3(4,16,4); post_visual.mesh = post_mesh
	post_visual.position.y = 8; post.add_child(post_visual)
	var post_collision := CollisionShape3D.new(); post_collision.name = "Collision"
	var post_shape := BoxShape3D.new(); post_shape.size = Vector3(4,16,4); post_collision.shape = post_shape
	post_collision.position.y = 8; post.add_child(post_collision)
	var regions := Node3D.new(); regions.name = "Regions"; map.add_child(regions)
	var start := Maps._region(MAP_ID,"entry","player_start",Vector3(192,0,120)); regions.add_child(start)
	var layer := CanvasLayer.new(); layer.name = "CanvasLayer"; scene.add_child(layer)
	var hud := Label.new(); hud.name = "Gate"; layer.add_child(hud)
	Maps._set_owner(scene,scene)
	return scene

static func save(directory: String) -> PackedScene:
	if not directory.begins_with("user://ember-tests/"):return null
	DirAccess.make_dir_recursive_absolute(directory)
	var scene := make_scene()
	scene.set("sandbox_storage_root",directory.path_join("play"))
	var packed := PackedScene.new(); var error := packed.pack(scene); scene.free()
	if error != OK:return null
	if ResourceSaver.save(packed,directory.path_join(MAP_ID+".tscn")) != OK:return null
	packed.take_over_path(EmberMapTransition.scene_path(MAP_ID))
	return packed

static func prepare_editor() -> String:
	if not Native.install():push_error("Disposable mechanics fixture required");return ""
	var scene := make_scene()
	var source := EmberVoxelModelResource.new()
	source.model_id = "qa_editor_ground"; source.display_name = "Synthetic editor ground"
	# This fixture covers editor transactions. Full-map budgets remain owned by
	# test_surface_large_profile, rather than repeating a retired level's size.
	source.voxels_per_block = 16; source.size_blocks = Vector3i(20,4,8); source.height_voxels = 64
	source.physical = true; source.palette = PackedColorArray([Color.TRANSPARENT,Color.BROWN,Color.GREEN,Color.GRAY])
	source.material = {"preset":"world_surface"}
	var size := source.grid_size()
	# VoxMesher stores complete X/Z layers, then advances Y.
	var filled := PackedByteArray(); filled.resize(size.x*size.z*32); filled.fill(1)
	var empty := PackedByteArray(); empty.resize(size.x*size.z*(size.y-32))
	var voxels := PackedByteArray()
	voxels.append_array(filled); voxels.append_array(empty)
	source.voxels = voxels
	var path := "res://content/world_surfaces/qa_editor_ground.tres"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if ResourceSaver.save(source,path) != OK:scene.free();return ""
	source.take_over_path(path)
	var map := scene.get_node("Map") as EmberMapLoader
	map.authored_size_blocks = Vector2i(20,8)
	map.visual_surface = source; map.surface_origin = Vector3(0,-32,0)
	var packed := PackedScene.new(); var error := packed.pack(scene); scene.free()
	return SCENE if error == OK and ResourceSaver.save(packed,SCENE) == OK else ""
