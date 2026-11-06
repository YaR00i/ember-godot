extends SceneTree
## Bake all painted grass, then collect the other caches of the native preparation run.
const Storage=preload("res://scripts/prototypes/ember_derived_data_cache.gd")
const Bundle=preload("res://scripts/prototypes/ember_terrain_prepared_bundle.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	if not ProjectSettings.get_setting("application/config/custom_user_dir_name","").begins_with("EmberBuildProbe-"):
		printerr("Run only in an isolated EmberBuildProbe profile.");quit(2);return
	var source:="res://scenes/landscape_compact.tscn"
	var grass_root:="user://ember-build-prepared-grass"
	var log: Array=[]
	var status:=OS.execute(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),
		"--script","res://tools/prepare_grass_positions.gd","--","--source="+source,"--output="+grass_root],log,true)
	if status!=0:printerr("Grass preparation failed: ",log);quit(1);return
	var grass:=Bundle.inspect(grass_root)
	if grass.error!="":printerr(grass.error);quit(1);return
	var inputs:Dictionary={};var categories:Dictionary={}
	for directory in Storage.SHIPPED_CACHES:
		var spec:Array=Storage.SHIPPED_CACHES[directory]
		var count:=0
		if DirAccess.dir_exists_absolute(directory):
			for file in DirAccess.get_files_at(directory):
				if file.ends_with(spec[1]):inputs[spec[0]+"/"+file]=directory.path_join(file);count+=1
		categories[spec[0]]=count
	for entry:Dictionary in grass.manifest.files:
		if not inputs.has(entry.name):categories.details+=1
		inputs[entry.name]=grass_root.path_join(entry.name)
	var result:=Bundle.write(Bundle.ROOT,inputs,{"source":source,"source_sha256":FileAccess.get_sha256(source),
		"godot_hex":Engine.get_version_info().hex,"categories":categories,"grass_patches":grass.manifest.patches})
	if not result.error.is_empty():printerr(result.error);quit(1);return
	print("WORLD_BUNDLE_READY ",JSON.stringify({"files":result.files.size(),"bytes":result.manifest.total_bytes,"categories":categories}))
	quit()
