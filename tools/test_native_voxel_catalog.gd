extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_voxel_native_test_fixture.gd")
const Packer = preload("res://tools/fixtures/ember_native_catalog_pack_fixture.gd")
var _state: Dictionary

func _init() -> void:
	if FileAccess.file_exists("res://.voxel-native-pack-reader"):
		Fixture.Maps.prepare(self, "user://ember-tests/native-voxel-pack-%d" % OS.get_process_id())
		_read.call_deferred()
		return
	_state = Fixture.prepare(self)
	if _state.refused:
		quit.call_deferred(2)
		return
	_run.call_deferred()

func _run() -> void:
	var errors: Array[String] = []
	Fixture.check_detached(_state, errors)
	_check_native(errors, false)
	var binary := EmberVoxelCatalog.native_resource("vox_fan_crate_stack").duplicate_model()
	binary.model_id = "binary_fixture"
	var path := EmberVoxelCatalog.NATIVE_DIR.path_join("binary_fixture.res")
	if ResourceSaver.save(binary, path) != OK or EmberVoxelCatalog.owner("binary_fixture") != "godot" or str(EmberVoxelPrefab.source_paths("binary_fixture").source) != path:
		errors.append("standalone native res lookup failed")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not errors.is_empty():
		printerr("FAIL native voxel catalog: ", "; ".join(errors))
		quit(1)
		return
	var marker := FileAccess.open("res://.voxel-native-pack-reader", FileAccess.WRITE)
	marker.store_string("binary resource reader")
	marker.close()
	var packed := Packer.build(_state.directory, [EmberVoxelCatalog.NATIVE_DIR])
	if packed.is_empty():
		quit(1)
		return
	print("VOXEL_PACK: ", packed)
	print("PASS native voxel catalog; poison/missing JSON, metadata, preview mesh/collision, standalone res")
	quit(0)

func _read() -> void:
	var errors: Array[String] = []
	_check_native(errors, true)
	if not errors.is_empty():
		printerr("FAIL native voxel PCK: ", "; ".join(errors))
		quit(1)
		return
	print("PASS native voxel PCK; metadata/geometry/preview without source tres or JOI")
	quit(0)

func _check_native(errors: Array[String], packed: bool) -> void:
	var definitions := EmberVoxelCatalog.definitions(true)
	var expected_count := int(FileAccess.get_file_as_string("res://.voxel-native-count"))
	if expected_count < 1 or definitions.size() != expected_count or EmberVoxelCatalog.ids().size() != expected_count: errors.append("native shelf lost author models")
	for id in definitions:
		var definition: Dictionary = definitions[id]
		if definition.get("_owner") != "godot": errors.append("shelf includes historical owner")
		for channel in ["voxels", "collisionVoxels", "palette", "voxelGroups"]:
			if definition.model.has(channel): errors.append("metadata expanded geometry: " + id)
	for id in ["vox_fan_crate_stack", "vox_fan_barrel"]:
		var resource := EmberVoxelCatalog.native_resource(id)
		if resource == null or not resource.validation_errors().is_empty():
			errors.append("native source invalid: " + id)
			continue
		var path := str(EmberVoxelPrefab.source_paths(id).source)
		if packed and (FileAccess.file_exists(path) or not ResourceLoader.exists(path)): errors.append("binary remap failed")
		var definition := EmberVoxelCatalog.definition(id)
		var expected := VoxMesher.build_from_ember_model(definition.model, VoxMesher.normalized_voxel_size(definition.model))
		var prop := EmberVoxelPrefab.make_preview_instance(id)
		if prop == null:
			errors.append("native preview missing: " + id)
			continue
		var visual := prop.get_node_or_null("Mesh") as MeshInstance3D
		if visual == null or visual.mesh.get_surface_count() != expected.get_surface_count() or not visual.mesh.get_aabb().is_equal_approx(expected.get_aabb()): errors.append("preview mesh bounds changed")
		if resource.physical and prop.get_node_or_null("Collision/Shape") == null: errors.append("native collision lost")
		prop.free()
	if not EmberVoxelCatalog.definition("retired_model").is_empty(): errors.append("PCK revived retired source")
