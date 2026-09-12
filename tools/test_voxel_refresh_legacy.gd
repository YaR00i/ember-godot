extends SceneTree
## Read author assets only; publish/Undo/reopen solely in unique user:// fixtures.
const Refresh = preload("res://addons/ember_import/ember_voxel_scene_refresh.gd")
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
var errors: Array[String] = []
var fixture := "user://ember-tests/legacy-refresh-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]

func _init() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)

func _bounds(prop: EmberVoxelProp) -> AABB:
	var mesh := prop.get_node("Mesh") as MeshInstance3D
	return mesh.transform * mesh.mesh.get_aabb()

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var undo := UndoRedo.new()
	var ids: Array[String] = []
	var tested := 0
	for suffix in ["awning_stripe", "banner", "bench", "birch", "chimney", "crystal_magic", "fence", "flowerbox", "flowers", "fountain", "grass", "hitch", "lantern_paper", "laundry", "mage_sign", "mail_box", "oak", "pine", "porch", "produce", "sapling", "shop_front", "stall", "statue"]:
		ids.append("vox_fan_" + suffix)
	ids.append_array(["vox_merge_60949294_0", "vox_merge_60959363_1", "vox_shape_block_15328782_canvas_117422242_part_32556083_0", "vox_shape_block_15328782_canvas_117422242_part_32556083_2", "vox_shape_block_15328782_canvas_117422242_part_32556083_4_canvas_121360778", "vox_shape_block_15328782_canvas_117422242_part_32556083_9"])
	for id in ids:
		var original := EmberVoxelPrefab.prefab_path(id)
		if not FileAccess.file_exists(original): continue
		tested += 1
		var source_path := str(EmberVoxelPrefab.source_paths(id).source)
		var source_hash := FileAccess.get_sha256(source_path)
		var original_hash := FileAccess.get_sha256(original)
		var path := fixture.path_join(id + ".tscn")
		var bytes := FileAccess.get_file_as_bytes(original)
		check(Store.restore_derived_prefab(bytes, path).ok, id + " fixture copy")
		var prop := (ResourceLoader.load(path) as PackedScene).instantiate() as EmberVoxelProp
		scene.add_child(prop)
		var socket := Node3D.new()
		socket.position = Vector3(2, 3, 4)
		prop.get_node("Mesh").add_child(socket)
		var socket_pose := socket.global_transform
		var frame: Transform3D = prop.get_node("Mesh").transform
		var bounds := _bounds(prop)
		var old_mesh: Mesh = prop.get_node("Mesh").mesh
		var operation := Refresh.new()
		operation.prefab_directory = fixture
		var result := operation.rebuild_catalog_model(id, scene, undo)
		check(result.ok, id + ": " + str(result.get("error", "")))
		if result.ok:
			check(_bounds(prop).is_equal_approx(bounds) and prop.get_node("Mesh").transform == frame and socket.global_transform.is_equal_approx(socket_pose), id + " frame/bounds/authored child changed")
			check(EmberVoxelPrefab.resource_uid_from_header(path) != ResourceUID.INVALID_ID, id + " publication UID absent")
			undo.undo()
			check(FileAccess.get_file_as_bytes(path) == bytes and prop.get_node("Mesh").mesh == old_mesh, id + " Undo not exact")
			undo.redo()
			var reopened := (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as EmberVoxelProp
			check(_bounds(reopened).is_equal_approx(bounds), id + " canonical prefab reopen changes bounds")
			reopened.free()
		check(FileAccess.get_sha256(original) == original_hash and FileAccess.get_sha256(source_path) == source_hash, id + " author files changed")
		undo.clear_history()
		prop.free()
	undo.free()
	scene.free()
	for message in errors: push_error(message)
	print("Voxel legacy refresh: ", "PASS" if errors.is_empty() else "FAIL", " · ", errors.size(), " / ", tested, " author regressions (read-only; unavailable fixtures skipped)")
	quit(0 if errors.is_empty() else 1)
