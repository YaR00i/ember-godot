@tool
extends EditorPlugin
## Run in a disposable native editor with no restored scenes. Pass the same
## user://ember-tests/ directory to two fresh processes, then --warm to the second.
const Bake=preload("res://scripts/ember_tree_look_bake.gd")
const Storage=preload("res://scripts/prototypes/ember_derived_data_cache.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String):
	if not ok:errors.append(label);printerr("EDITOR_TREE_CACHE_FAIL ",label)
func _enter_tree():run.call_deferred()
func geometry(mesh:ArrayMesh)->String:
	var surfaces:Array=mesh.get("_surfaces").duplicate(true)
	for surface:Dictionary in surfaces:surface.erase("material")
	return Storage.digest(surfaces)
func run():
	var args:=OS.get_cmdline_user_args()
	if args.is_empty() or not args[0].begins_with("user://ember-tests/"):
		printerr("Pass an isolated user://ember-tests/ directory");get_tree().quit(2);return
	check(Engine.is_editor_hint() and DisplayServer.get_name()!="headless","native editor context")
	check(Bake.cache_directory==Bake.CACHE_ROOT,"editor initializes default cache path before overrides")
	check(Bake.builds==0 and Bake.disk_hits==0 and Bake._ready_meshes.is_empty(),"fresh process without restored scenes")
	Bake.cache_directory=args[0]
	var warm:=args.has("--warm");var report_path:=args[0].path_join("warm.json" if warm else "cold.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(args[0]))
	var stage:=Node3D.new();get_tree().root.add_child(stage)
	var hashes:Dictionary={};var sources:Dictionary={};var timings:Dictionary={}
	for id in ["vox_painted_oak","vox_painted_birch"]:
		var path:="res://content/voxel_models/%s.tres"%id
		var original:=FileAccess.get_sha256(path);sources[id]=original
		var began:=Time.get_ticks_msec()
		var prop:EmberVoxelProp=load("res://prefabs/voxels/%s.tscn"%id).instantiate();stage.add_child(prop)
		for look in [0,1,2,0]:
			prop.set_world_look(look)
			var key:="%s/%d"%[id,look]
			var stamp:=geometry(prop.get_node("Mesh").mesh)
			if hashes.has(key):check(hashes[key]==stamp,"look return exact "+id)
			hashes[key]=stamp
		timings[id]=Time.get_ticks_msec()-began
		check(FileAccess.get_sha256(path)==original,"immutable Source "+id)
	if warm:
		check(Bake.builds==0 and Bake.disk_hits==4,"fresh process loads all four looks without rebuilding")
		var file:=FileAccess.open(args[0].path_join("cold.json"),FileAccess.READ)
		check(file!=null,"cold report exists")
		if file!=null:
			var cold:Variant=JSON.parse_string(file.get_as_text());file.close()
			check(cold is Dictionary and cold.get("geometry")==hashes and cold.get("sources")==sources,"cold/warm geometry and Source exact")
	else:
		check(Bake.builds==4 and Bake.disk_hits==0,"cold prepares both looks of both species")
		var records:=0
		for name in DirAccess.get_files_at(args[0]):
			if name.ends_with(".edc"):records+=1
		check(records==4,"cold persists four derived records")
	Bake.cache_directory="";check(Bake.cache_directory.is_empty(),"explicit disabled cache remains supported")
	var report:={"pass":errors.is_empty(),"errors":errors,"warm":warm,"builds":Bake.builds,"disk_hits":Bake.disk_hits,"geometry":hashes,"sources":sources,"timings_ms":timings}
	var output:=FileAccess.open(report_path,FileAccess.WRITE);output.store_string(JSON.stringify(report));output.close()
	print("EDITOR_TREE_LOOK_CACHE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"warm":warm,"builds":Bake.builds,"disk_hits":Bake.disk_hits,"timings_ms":timings}))
	stage.free();get_tree().quit(0 if errors.is_empty() else 1)
