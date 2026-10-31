extends SceneTree
const Catalog=preload("res://scripts/ember_voxel_catalog.gd")
const Storage=preload("res://scripts/prototypes/ember_derived_data_cache.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String):
	if not ok:errors.append(label);printerr("CATALOG_METADATA_FAIL ",label)
func _initialize():
	var directory:="user://ember-tests/catalog-metadata-%d"%Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	Catalog.metadata_cache_directory=directory.path_join("cache")
	var path:=directory.path_join("fixture.tres")
	var source:=EmberVoxelModelResource.new();source.model_id="metadata_fixture";source.display_name="Original"
	source.tags=PackedStringArray(["one"]);source.voxels_per_block=32;source.size_blocks=Vector3i(2,3,4)
	check(ResourceSaver.save(source,path)==OK,"save user fixture")
	var expected:={"id":"metadata_fixture","nameRu":"Original","tags":["one"],"model":{"voxelsPerBlock":32,"sizeBlocks":{"x":2,"y":3,"z":4}},"_owner":"godot"}
	check(Catalog._metadata_definition(path)==expected,"cold metadata equals previous projection")
	check(not ResourceLoader.has_cached(path),"metadata does not retain dense Resource")
	var hits:=Catalog.metadata_hits
	check(Catalog._metadata_definition(path)==expected and Catalog.metadata_hits==hits+1,"disk metadata hit without source load")
	var copy:=Catalog._metadata_definition(path);copy.tags.append("mutated");copy.model.sizeBlocks.x=99
	check(Catalog._metadata_definition(path)==expected,"caller cannot poison cached metadata")
	var live:=ResourceLoader.load(path) as EmberVoxelModelResource;live.display_name="Unsaved!"
	var current:=Catalog._metadata_definition(path)
	check(current.nameRu=="Unsaved!","live Inspector draft remains authoritative")
	live=null
	check(Catalog._metadata_definition(path)==expected,"unsaved draft never overwrites disk metadata")
	var file:=FileAccess.open(path,FileAccess.READ);var text:=file.get_as_text();file.close()
	var changed:=text.replace('display_name = "Original"','display_name = "Changed!"')
	check(changed.length()==text.length() and changed!=text,"same-size external edit fixture")
	file=FileAccess.open(path,FileAccess.WRITE);file.store_string(changed);file.close()
	var next:=expected.duplicate(true);next.nameRu="Changed!"
	check(Catalog._metadata_definition(path)==next,"content hash rejects same-size same-second stale description")
	var storage:=Storage.new();storage.directory=Catalog.metadata_cache_directory;storage.max_bytes=1024*1024
	var key:=Catalog._metadata_key(path,FileAccess.get_sha256(path))
	var payload:=storage.read(key);payload.metadata.model["voxels"]=PackedByteArray([1,2,3])
	storage.write(key,payload,func():return false)
	check(Catalog._metadata_definition(path)==next,"malformed geometry-bearing metadata is rebuilt")
	file=FileAccess.open(storage.path(key),FileAccess.WRITE);file.store_string("corrupt");file.close()
	check(Catalog._metadata_definition(path)==next,"corrupt transport safely falls back to native Source")
	check(FileAccess.get_sha256(path)==changed.sha256_text(),"catalog never writes Source")
	print("VOXEL_CATALOG_METADATA ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"hits":Catalog.metadata_hits,"misses":Catalog.metadata_misses}))
	quit(0 if errors.is_empty() else 1)
