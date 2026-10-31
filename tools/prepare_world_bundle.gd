extends SceneTree
## Collect only existing derived records after a complete native preparation run.
const Storage=preload("res://scripts/prototypes/ember_derived_data_cache.gd")
const Bundle=preload("res://scripts/prototypes/ember_terrain_prepared_bundle.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	if not ProjectSettings.get_setting("application/config/custom_user_dir_name","").begins_with("EmberBuildProbe-"):
		printerr("Run only in an isolated EmberBuildProbe profile.");quit(2);return
	var inputs:Dictionary={};var categories:Dictionary={}
	for directory in Storage.SHIPPED_CACHES:
		var spec:Array=Storage.SHIPPED_CACHES[directory]
		var count:=0
		for file in DirAccess.get_files_at(directory):
			if file.ends_with(spec[1]):inputs[spec[0]+"/"+file]=directory.path_join(file);count+=1
		categories[spec[0]]=count
	var result:=Bundle.write(Bundle.ROOT,inputs,{"source":"res://scenes/landscape_compact.tscn","source_sha256":FileAccess.get_sha256("res://scenes/landscape_compact.tscn"),"godot_hex":Engine.get_version_info().hex,"categories":categories})
	if not result.error.is_empty():printerr(result.error);quit(1);return
	print("WORLD_BUNDLE_READY ",JSON.stringify({"files":result.files.size(),"bytes":result.manifest.total_bytes,"categories":categories}))
	quit()
