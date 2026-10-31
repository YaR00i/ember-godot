extends SceneTree
const Storage=preload("res://scripts/prototypes/ember_derived_data_cache.gd")
const Bundle=preload("res://scripts/prototypes/ember_terrain_prepared_bundle.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var directory:="user://ember-tests/world-bundle-%d"%Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(directory)
	var packer:=PCKPacker.new()
	var pack:=directory.path_join("fixture.pck")
	assert(packer.pck_start(ProjectSettings.globalize_path(pack))==OK)
	var keys:Dictionary={}
	var sequence:=0
	for canonical in Storage.SHIPPED_CACHES:
		var spec:Array=Storage.SHIPPED_CACHES[canonical]
		var key:=Storage.digest(["world-bundle-fixture",directory,sequence]);sequence+=1
		var store:=Storage.new();store.directory=directory.path_join(str(sequence));store.extension=spec[1]
		store.write(key,{"sentinel":sequence},func():return false)
		var name:String=spec[0]+"/"+key+spec[1]
		assert(Bundle._valid_name(name))
		assert(packer.add_file(Storage.PACKAGED_ROOT.path_join(name),ProjectSettings.globalize_path(store.path(key)))==OK)
		keys[canonical]=[key,sequence]
	assert(packer.flush()==OK and ProjectSettings.load_resource_pack(pack))
	Storage.diagnostics_enabled=true
	for canonical in keys:
		var store:=Storage.new();store.directory=canonical;store.extension=Storage.SHIPPED_CACHES[canonical][1]
		var key:String=keys[canonical][0]
		assert(not FileAccess.file_exists(store.path(key)))
		assert(store.read(key).get("sentinel")==keys[canonical][1] and store.packaged_hits==1)
		assert(not FileAccess.file_exists(store.path(key)),"shipped record copied into local cache")
		store.directory=directory.path_join("custom")
		assert(store.read(key).is_empty(),"isolated custom directory inherited shipped data")
	assert(not Bundle._valid_name("details/../escape.edc"))
	assert(not Bundle._valid_name("unexpected/"+"a".repeat(64)+".edc"))
	assert(not Storage.diagnostics_snapshot().is_empty())
	print("WORLD_PREPARED_CACHE PASS seven categories/empty-local/no-copy/custom-isolation/names/counters")
	quit()
