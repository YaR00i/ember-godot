extends SceneTree
const Patch = preload("res://scripts/ember_grass_patch.gd")
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Bundle = preload("res://scripts/prototypes/ember_terrain_prepared_bundle.gd")
const Storage = preload("res://scripts/prototypes/ember_derived_data_cache.gd")
const Preparation = preload("res://scripts/ember_detail_preparation.gd")
var directory := "user://ember-tests/grass-bundle-%d" % Time.get_ticks_usec()
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); printerr("GRASS_PACKAGE_FAIL ",message)

func save_fixture(height: int, second_cell: bool, rock_x: float, patch_count := 3) -> void:
	var terrain := Terrain.new()
	terrain.width=512; terrain.depth=64; terrain.height_limit=96
	terrain.palette=PackedColorArray([Color.TRANSPARENT,Color.GREEN])
	terrain.palette_surface_roles=PackedStringArray(["","grass"])
	terrain.palette_material_ids=PackedStringArray(["","cartoon_grass"])
	for channel in Terrain.Sections.CHANNELS:
		var values: Variant=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
		values.resize(terrain.width*terrain.depth)
		values.fill(24 if channel=="heights" else 1 if channel in ["top_materials","base_materials"] else 0)
		if channel=="heights":
			for z in range(24,42):
				for x in range(24,42): values[x+z*terrain.width]=height
		terrain.set(channel,values)
	var scene:=Node3D.new()
	var map:=EmberMapLoader.new();map.name="Map";scene.add_child(map);map.owner=scene
	map.compact_terrain=terrain.sectioned_copy();map.compact_ground_style=1;map.world_look=0
	var props:=Node3D.new();props.name="Props";map.add_child(props);props.owner=scene
	for i in patch_count:
		var patch:=Patch.new();patch.name="Grass%d"%i;props.add_child(patch);patch.owner=scene
		patch.position.x=i*192;patch.painted_only=true
		patch.density_cells={Vector2i(8,8):200}
		if i==0 and second_cell:patch.density_cells={Vector2i(8,8):200,Vector2i(9,8):200}
	var rock:=EmberVoxelProp.new();rock.name="Rock";props.add_child(rock);rock.owner=scene
	rock.position=Vector3(rock_x,50,34);rock.add_to_group(&"ember_solid_surface",true)
	var box:=BoxMesh.new();box.size=Vector3(20,4,20)
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,box.get_mesh_arrays())
	var visual:=MeshInstance3D.new();visual.name="Mesh";rock.add_child(visual);visual.owner=scene;visual.mesh=mesh
	var body:=StaticBody3D.new();body.name="Collision";rock.add_child(body);body.owner=scene
	var shape:=CollisionShape3D.new();shape.name="Shape";body.add_child(shape);shape.owner=scene;shape.shape=box.create_trimesh_shape()
	var packed:=PackedScene.new()
	check(packed.pack(scene)==OK and ResourceSaver.save(packed,directory.path_join("map.tscn"))==OK,"save fixture")
	scene.free()

func bake() -> Dictionary:
	var log: Array=[]
	var code:=OS.execute(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),
		"--script","res://tools/prepare_grass_positions.gd","--","--source="+directory.path_join("map.tscn"),
		"--output="+directory.path_join("bundle")],log,true)
	check(code==0,"builder exit " + str(code))
	if code!=0:printerr(log);return {}
	var inspected:=Bundle.inspect(directory.path_join("bundle"))
	check(inspected.error=="","inspect published manifest")
	return inspected.get("manifest",{}).get("patches",{})

func looks(key: String) -> Dictionary:
	var store:=Storage.new();store.magic="EDSCATR1";store.directory=directory.path_join("bundle/details")
	return store.read(key).get("looks",{})

func settle(map: EmberMapLoader, patches: Array) -> bool:
	var until:=Time.get_ticks_msec()+30000
	var quiet:=0
	while Time.get_ticks_msec()<until:
		await process_frame
		var busy:bool=map._visual_surface_projection.pending_tile_count()>0
		for patch:Patch in patches: busy=busy or patch._dirty or patch._rebuilding
		quiet=0 if busy else quiet+1
		if quiet>=3:return true
	return false

func check_play(keys: Dictionary) -> void:
	var bundle:=Bundle.inspect(directory.path_join("bundle"))
	var pack:=directory.path_join("grass.pck")
	var packer:=PCKPacker.new()
	check(packer.pck_start(ProjectSettings.globalize_path(pack))==OK,"start fixture PCK")
	for file:Dictionary in bundle.files:
		check(packer.add_file(file.target,ProjectSettings.globalize_path(file.source))==OK,"pack grass record")
	check(packer.flush()==OK and ProjectSettings.load_resource_pack(pack),"mount fixture PCK")
	Preparation.cache_root=directory.path_join("empty-local")
	var scene=(load(directory.path_join("map.tscn")) as PackedScene).instantiate()
	root.add_child(scene)
	var map:EmberMapLoader=scene.get_node("Map")
	var context=Preparation.for_projection(map._visual_surface_projection)
	context.disk.packaged_for_directory=Preparation.cache_root
	context.disk.packaged_directory=Storage.PACKAGED_ROOT.path_join("details")
	var patches:Array=[map.get_node("Props/Grass0"),map.get_node("Props/Grass1"),map.get_node("Props/Grass2")]
	check(await settle(map,patches),"runtime settles")
	for patch:Patch in patches:
		check(patch.detail_disk_hits==1 and patch.detail_generations==0,"runtime reads shipped positions")
		check(patch._detail_transform_cache==looks(keys[str(map.get_path_to(patch))]),"runtime matches baked roots")
		if DisplayServer.get_name()!="headless":
			check(patch._visual.multimesh.get_instance_transform(0).is_equal_approx(patch._detail_transform_cache[0][0]),"Forward+ uploaded root matches package")
	var a:Patch=patches[0];var b:Patch=patches[1]
	var initial:=a._detail_transform_cache.duplicate(true)
	a.density_cells={Vector2i(8,8):200,Vector2i(9,8):200}
	check(await settle(map,patches) and a._detail_transform_cache[0].size()>initial[0].size(),"live mask replaces stale package")
	a.density_cells={Vector2i(8,8):200}
	check(await settle(map,patches) and a._detail_transform_cache==initial,"live mask undo restores cached roots")
	var projection=map._visual_surface_projection
	projection.apply_heights(PackedInt32Array([projection.document.column_index(32,32)]),PackedInt32Array([40]))
	check(await settle(map,patches) and a._detail_transform_cache!=initial,"live terrain edit replaces stale roots")
	var raised:=a._detail_transform_cache.duplicate(true)
	var rock:EmberVoxelProp=map.get_node("Props/Rock")
	# A display look may not occupy the same bounds as the published collision hull.
	var visual:MeshInstance3D=rock.get_node("Mesh")
	rock._hull_mesh=visual.mesh
	var arrays:=rock._hull_mesh.surface_get_arrays(0)
	arrays[Mesh.ARRAY_VERTEX]=Transform3D(Basis.IDENTITY,Vector3(500,0,0))*(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	var proxy:=ArrayMesh.new();proxy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	visual.mesh=proxy
	rock.position.x=34
	check(await settle(map,patches) and a._detail_transform_cache[0].is_empty(),"live obstacle replaces raised roots")
	rock.position.x=226
	check(await settle(map,patches) and a._detail_transform_cache==raised and b._detail_transform_cache[0].is_empty(),"live move updates both areas")
	check(patches[2].detail_generations==0 and patches[2].detail_disk_hits==1,"untouched patch never rebuilt")
	scene.queue_free();await process_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	save_fixture(24,false,-100)
	var initial:=bake()
	if initial.size()!=3:check(false,"all three patches");quit(1);return
	var a:="Props/Grass0";var b:="Props/Grass1";var c:="Props/Grass2"
	var original:=looks(initial[a])
	check(original.size()==3 and not original[0].is_empty(),"prepared roots for all three looks")
	await check_play(initial)
	check(bake()==initial,"unmodified map produces identical addresses")
	save_fixture(24,true,-100)
	var mask:=bake()
	if mask.size()!=3:quit(1);return
	check(mask[a]!=initial[a] and mask[b]==initial[b] and mask[c]==initial[c],"paint is local")
	check(looks(mask[a])[0].size()>original[0].size(),"new painted cell has roots")
	save_fixture(40,false,-100)
	var raised:=bake()
	if raised.size()!=3:quit(1);return
	check(raised[a]!=initial[a] and raised[b]==initial[b] and raised[c]==initial[c],"height edit is local")
	check(looks(raised[a])[0][0].origin.y>original[0][0].origin.y,"roots follow the raised floor")
	save_fixture(24,false,34)
	var blocked:=bake()
	if blocked.size()!=3:quit(1);return
	check(blocked[a]!=initial[a] and looks(blocked[a])[0].is_empty(),"stone prevents grass placement")
	save_fixture(24,false,226,2)
	var moved:=bake()
	if moved.size()!=2:check(false,"removed patch omitted");quit(1);return
	check(moved[a]==initial[a] and looks(moved[a])==original,"moving stone restores original roots")
	check(moved[b]!=initial[b] and looks(moved[b])[0].is_empty(),"new stone bounds invalidate destination")
	save_fixture(24,false,-100,0)
	check(bake().is_empty() and Bundle.inspect(directory.path_join("bundle")).files.is_empty(),"erasing last patch publishes an empty grass manifest")
	if failures.is_empty():print("GRASS_PACKAGE PASS cold/repeat/mask/height/obstacle/return/removal")
	quit(0 if failures.is_empty() else 1)
