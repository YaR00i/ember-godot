extends SceneTree
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")

func _init() -> void:
	var directory := "user://ember-tests/vox-axes-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	Maps.prepare(self, directory)
	var path := directory.path_join("asymmetric.vox")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("FAIL native VOX fixture could not write")
		quit(1)
		return
	file.store_buffer("VOX ".to_ascii_buffer())
	file.store_32(150)
	file.store_buffer("MAIN".to_ascii_buffer())
	file.store_32(0)
	file.store_32(48)
	file.store_buffer("SIZE".to_ascii_buffer())
	file.store_32(12)
	file.store_32(0)
	for size in [3, 7, 11]: file.store_32(size)
	file.store_buffer("XYZI".to_ascii_buffer())
	file.store_32(12)
	file.store_32(0)
	file.store_32(2)
	file.store_buffer(PackedByteArray([1, 2, 9, 5, 2, 6, 10, 1]))
	file.close()
	var source_hash := FileAccess.get_sha256(path)
	var document := VoxParser.parse_file(path)
	var model: Dictionary = document.models[0]
	var source := EmberVoxelModelResource.new()
	EmberVoxelLegacyImporter._apply_vox_document(source, document)
	var size := source.grid_size()
	var first := VoxMesher.cell_index(1, 9, 2, size.x, size.z)
	var second := VoxMesher.cell_index(2, 10, 6, size.x, size.z)
	if model.size != Vector3i(3, 7, 11) or VoxMesher.ember_size(model.size) != Vector3i(3, 11, 7) or source.height_voxels != 11 or source.voxels[first] != 5 or source.voxels[second] != 1 or source.voxels.size() - source.voxels.count(0) != 2 or FileAccess.get_sha256(path) != source_hash:
		printerr("FAIL native VOX axis/occupancy/palette/source parity")
		quit(1)
		return
	print("PASS native VOX parser -> axis conversion -> Resource; asymmetric generated input, no historical pack")
	quit(0)
