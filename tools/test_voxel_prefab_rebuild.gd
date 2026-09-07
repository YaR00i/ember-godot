extends SceneTree
## Headless Wave 2 smoke: targeted prefab rebuild must not rewrite the authored map.

const MAP_PATH := "res://scenes/fan_town.tscn"
const MODEL_ID := "vox_fan_lantern_stone"
const TILE_SIZE := 16.0


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	_validate_first_mesh_install(errors)
	var map_hash_before := FileAccess.get_sha256(MAP_PATH)
	var placements_before := _load_placements(errors)
	var prefab_uid_before := EmberVoxelPrefab.resource_uid_from_header(EmberVoxelPrefab.prefab_path(MODEL_ID))
	var live_map_packed := ResourceLoader.load(MAP_PATH, "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	var live_root := live_map_packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) if live_map_packed else null
	var live_prop := _find_prop(live_root)
	var live_visual := live_prop.get_node_or_null("Mesh") as MeshInstance3D if live_prop else null
	var live_mesh := live_visual.mesh if live_visual else null
	if placements_before.is_empty():
		errors.append("контрольный prefab отсутствует на fan_town")
	if live_mesh == null:
		errors.append("не удалось получить live Mesh до rebuild")

	var prefab_hash_before := FileAccess.get_sha256(EmberVoxelPrefab.prefab_path(MODEL_ID))
	var mesh_path := EmberVoxelPrefab.mesh_path(MODEL_ID, false)
	var mesh_hash_before := FileAccess.get_sha256(mesh_path)
	var prefab_modified_before := FileAccess.get_modified_time(EmberVoxelPrefab.prefab_path(MODEL_ID))
	var mesh_modified_before := FileAccess.get_modified_time(mesh_path)
	var stats := {}
	EmberVoxelPrefab.begin_import()
	var packed := EmberVoxelPrefab.ensure_saved(MODEL_ID, TILE_SIZE, stats)
	var report := EmberVoxelPrefab.validate_packed(MODEL_ID, packed)
	if not bool(report["ok"]):
		errors.append_array(report["errors"])
	var rebuilt_root := packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) if packed else null
	var rebuilt_visual := rebuilt_root.get_node_or_null("Mesh") as MeshInstance3D if rebuilt_root else null
	var rebuilt_mesh := rebuilt_visual.mesh if rebuilt_visual else null
	if live_mesh != rebuilt_mesh:
		# v1.97 intentionally migrates baked world meshes to a new normalized
		# resource path. The open instance keeps its old, correctly sized mesh;
		# the rebuilt prefab uses the block mesh after reopen.
		var before_size := _physical_mesh_size(live_visual)
		var after_size := _physical_mesh_size(rebuilt_visual)
		if not before_size.is_equal_approx(after_size):
			errors.append("normalized rebuild changed visible world footprint: %s -> %s" % [before_size, after_size])
		if rebuilt_mesh == null or rebuilt_mesh.resource_path.find("_block.res") < 0:
			errors.append("normalized rebuild did not install the block-space mesh resource")
	_validate_transparency_surface(rebuilt_visual, errors)

	var map_hash_after := FileAccess.get_sha256(MAP_PATH)
	if map_hash_before != map_hash_after:
		errors.append("targeted rebuild изменил файл карты")
	var prefab_uid_after := EmberVoxelPrefab.resource_uid_from_header(EmberVoxelPrefab.prefab_path(MODEL_ID))
	if prefab_uid_before == ResourceUID.INVALID_ID or prefab_uid_before != prefab_uid_after:
		errors.append("targeted rebuild изменил UID prefab")
	if FileAccess.get_sha256(EmberVoxelPrefab.prefab_path(MODEL_ID)) != prefab_hash_before:
		errors.append("проверка актуального prefab неожиданно переписала .tscn")
	if FileAccess.get_sha256(mesh_path) != mesh_hash_before:
		errors.append("проверка актуального prefab неожиданно переписала mesh")
	if FileAccess.get_modified_time(EmberVoxelPrefab.prefab_path(MODEL_ID)) != prefab_modified_before:
		errors.append("проверка актуального prefab обновила timestamp .tscn")
	if FileAccess.get_modified_time(mesh_path) != mesh_modified_before:
		errors.append("проверка актуального prefab обновила timestamp mesh")
	var placements_after := _load_placements(errors, true)
	if placements_before != placements_after:
		errors.append("targeted rebuild изменил transforms/placement_id")
	if rebuilt_root:
		rebuilt_root.free()
	if live_root:
		live_root.free()

	if not errors.is_empty():
		printerr("FAIL voxel prefab rebuild")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS voxel prefab reuse/rebuild gate: ", MODEL_ID)
	print("  verified: ", " + ".join(report["checks"]))
	print("  ready prefab reused without rewriting live renderer resources")
	print("  placements preserved: ", placements_before.size())
	print("  normalized mesh migration preserves the visible world footprint")
	print("  prefab uid preserved: ", ResourceUID.id_to_text(prefab_uid_after))
	print("  map sha256 preserved: ", map_hash_after)
	return 0


func _physical_mesh_size(visual: MeshInstance3D) -> Vector3:
	if visual == null or visual.mesh == null:
		return Vector3.ZERO
	return visual.mesh.get_aabb().size * visual.scale.abs()


func _validate_first_mesh_install(errors: Array[String]) -> void:
	var temp_path := "user://ember_first_mesh_install.res"
	var temp_absolute := ProjectSettings.globalize_path(temp_path)
	if FileAccess.file_exists(temp_absolute):
		DirAccess.remove_absolute(temp_absolute)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3.ZERO,
		Vector3.RIGHT,
		Vector3.FORWARD,
	])
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var installed := EmberVoxelPrefab._install_mesh_resource(built, temp_path)
	if installed != built:
		errors.append("first mesh save reopened a not-yet-scanned resource instead of keeping live identity")
	if not FileAccess.file_exists(temp_absolute):
		errors.append("first mesh save did not write its resource")
	if ResourceLoader.load(temp_path, "", ResourceLoader.CACHE_MODE_REUSE) != built:
		errors.append("first mesh save did not register the built resource in cache")
	if FileAccess.file_exists(temp_absolute):
		DirAccess.remove_absolute(temp_absolute)


func _validate_transparency_surface(visual: MeshInstance3D, errors: Array[String]) -> void:
	var mesh := visual.mesh as ArrayMesh if visual else null
	if mesh == null:
		return
	var found_opaque := false
	var found_transparent := false
	for surface in mesh.get_surface_count():
		var surface_name := mesh.surface_get_name(surface)
		if surface_name == "opaque":
			found_opaque = true
		if surface_name != "transparent":
			continue
		found_transparent = true
		var mat := mesh.surface_get_material(surface) as ShaderMaterial
		if mat == null or mat.shader == null or mat.shader.resource_path != "res://shaders/ember_voxel_transparent.gdshader":
			errors.append("transparent surface не использует отдельный toon alpha shader")
		var arrays := mesh.surface_get_arrays(surface)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var has_alpha := false
		for color in colors:
			if color.a < 0.999:
				has_alpha = true
				break
		if not has_alpha:
			errors.append("transparent surface потерял vertex alpha из Ember JSON")
	if not found_opaque:
		errors.append("контрольный фонарь потерял opaque surface")
	if not found_transparent:
		errors.append("контрольный фонарь не получил transparent surface")


func _load_placements(errors: Array[String], replace_cache := false) -> Dictionary:
	var cache_mode := ResourceLoader.CACHE_MODE_REPLACE if replace_cache else ResourceLoader.CACHE_MODE_REUSE
	var packed := ResourceLoader.load(MAP_PATH, "", cache_mode) as PackedScene
	if packed == null:
		errors.append("не удалось загрузить %s" % MAP_PATH)
		return {}
	var root := packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	var result := {}
	_collect(root, root, result)
	root.free()
	return result


func _collect(root: Node, node: Node, result: Dictionary) -> void:
	if node is EmberVoxelProp:
		var prop := node as EmberVoxelProp
		if prop.model_id == MODEL_ID:
			result[str(root.get_path_to(prop))] = [prop.transform, prop.placement_id]
	for child in node.get_children():
		_collect(root, child, result)


func _find_prop(node: Node) -> EmberVoxelProp:
	if node == null:
		return null
	if node is EmberVoxelProp and (node as EmberVoxelProp).model_id == MODEL_ID:
		return node as EmberVoxelProp
	for child in node.get_children():
		var found := _find_prop(child)
		if found:
			return found
	return null
