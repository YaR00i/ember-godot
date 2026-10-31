extends SceneTree
const Grove=preload("res://addons/ember_import/ember_grove_planner.gd")
const Plan=preload("res://scripts/ember_terrain_plan_resource.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("GROVE_STORAGE_FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var dir:="user://ember-tests/grove-storage-"+str(OS.get_process_id());DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var base:=Node3D.new();base.name="Object"
	var mesh:=MeshInstance3D.new();mesh.name="Mesh";mesh.mesh=BoxMesh.new();base.add_child(mesh);mesh.owner=base
	var packed:=PackedScene.new();packed.pack(base);ResourceSaver.save(packed,dir.path_join("native.tscn"));base.free()
	var scene:=Node3D.new();root.add_child(scene);var map:=Node3D.new();map.name="Map";scene.add_child(map);map.owner=scene
	var props:=Node3D.new();props.name="Props";map.add_child(props);props.owner=scene
	var object:Node3D=ResourceLoader.load(dir.path_join("native.tscn")).instantiate();props.add_child(object);object.owner=scene
	object.set_meta(Plan.GROVE_MEMBER_META,{"region":"shore","slot":0});object.position=Vector3(3,4,5);object.set_meta("authored","keep")
	var addition:=Node3D.new();addition.name="AuthoredAddition";object.add_child(addition);addition.owner=scene;addition.position=Vector3(1,2,3)
	var image:=Image.create(256,256,false,Image.FORMAT_RGBA8);image.fill(Color.RED)
	var material:=StandardMaterial3D.new();material.albedo_texture=ImageTexture.create_from_image(image);object.get_node("Mesh").material_override=material
	var runtime:=Node3D.new();runtime.name="DerivedRuntime";object.add_child(runtime)
	var snapshot:PackedScene=Grove.snapshot(map)
	check(snapshot!=null,"snapshot exists")
	var path:=dir.path_join("snapshot.tscn");ResourceSaver.save(snapshot,path)
	var bytes:=FileAccess.open(path,FileAccess.READ).get_length()
	check(bytes<32*1024,"snapshot excludes derived textures and keeps native prefab reference")
	var text:=FileAccess.get_file_as_string(path)
	check("native.tscn" in text and not "ImageTexture" in text,"snapshot stores authored instance data")
	object.position=Vector3.ZERO;object.remove_meta("authored");addition.position=Vector3.ZERO
	check(Grove.restore_snapshot(map,scene,snapshot).is_empty(),"restore succeeds")
	check(object.position==Vector3(3,4,5) and object.get_meta("authored","")=="keep","restore retains authored pose and metadata")
	check(object.get_node("AuthoredAddition").position==Vector3(1,2,3),"restore retains authored child")
	check(not object.has_node("DerivedRuntime"),"runtime cache is not restored as authored content")
	var again:=Grove.snapshot(map);ResourceSaver.save(again,dir.path_join("again.tscn"))
	check(FileAccess.open(dir.path_join("again.tscn"),FileAccess.READ).get_length()<32*1024,"repeated Discard does not flatten the prefab")
	print("GROVE_SNAPSHOT_STORAGE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"snapshot_bytes":bytes}))
	scene.free();await process_frame;quit(0 if errors.is_empty() else 1)
