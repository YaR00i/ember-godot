extends SceneTree
## Read-only comparison of stale fan_town prefabs against the exact tree that
## current legacy sources would build. Results go only to user://.

const Inventory = preload("res://addons/ember_import/ember_content_migration_report.gd")
const Parity = preload("res://addons/ember_import/ember_voxel_migration_parity.gd")
const OUTPUT_PATH := "user://ember_fan_town_stale_prefab_profile.json"


func _init() -> void:
	quit(_run())


func _run() -> int:
	var inventory := Inventory.build()
	var model_ids: Array[String] = []
	for raw_entry in Inventory.filtered_entries(inventory, "voxel", "scene_used"):
		var entry: Dictionary = raw_entry
		if (
			str(entry.get("owner", "")) == "legacy"
			and str(entry.get("derived_status", "")) == "stale"
			and "res://scenes/fan_town.tscn" in entry.get("referenced_in", [])
		):
			model_ids.append(str(entry.get("id", "")))
	model_ids.sort()
	var before := _watched_hashes(model_ids)
	var started := Time.get_ticks_msec()
	var entries: Array[Dictionary] = []
	var exact_count := 0
	for model_id in model_ids:
		var result := _inspect(model_id)
		entries.append(result)
		if bool(result.get("exact", false)):
			exact_count += 1
	var duration_ms := Time.get_ticks_msec() - started
	var after := _watched_hashes(model_ids)
	var errors: Array[String] = []
	if model_ids.size() != 25:
		errors.append("expected 25 stale fan_town prefabs, found %d" % model_ids.size())
	if before != after:
		errors.append("read-only profile changed source, Resource or prefab files")
	for entry in entries:
		if bool(entry.get("inspect_error", false)):
			errors.append("%s could not be compared" % entry.get("id", ""))
	var report := {
		"schema": 1,
		"duration_ms": duration_ms,
		"total": model_ids.size(),
		"exact": exact_count,
		"changed": model_ids.size() - exact_count,
		"entries": entries,
	}
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		errors.append("profile JSON could not be written to user://")
	else:
		file.store_string(JSON.stringify(report, "  ", false) + "\n")
		file.close()
	print("PROFILE fan_town stale prefabs · %d ms · exact %d/%d" % [
		duration_ms, exact_count, model_ids.size(),
	])
	for entry in entries:
		var differences: Array = entry.get("differences", [])
		print("  %s: %s" % [
			entry.get("id", ""),
			"signature-only" if differences.is_empty() else "; ".join(differences),
		])
	print("  JSON: ", ProjectSettings.globalize_path(OUTPUT_PATH))
	if not errors.is_empty():
		printerr("FAIL fan_town stale-prefab profile")
		for error in errors:
			printerr(" - ", error)
		return 1
	return 0


func _inspect(model_id: String) -> Dictionary:
	var differences: Array[String] = []
	var topology_changes: Array[String] = []
	var packed := ResourceLoader.load(
		EmberVoxelPrefab.prefab_path(model_id), "", ResourceLoader.CACHE_MODE_REPLACE
	) as PackedScene
	var current := packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) as EmberVoxelProp if packed else null
	var future := EmberVoxelPrefab.make_preview_instance(model_id, 16.0)
	if current == null or future == null:
		if current != null:
			current.free()
		if future != null:
			future.free()
		return {
			"id": model_id,
			"exact": false,
			"inspect_error": true,
			"differences": ["current or future prefab tree is missing"],
		}
	_compare_value("model id", current.model_id, future.model_id, differences)
	_compare_value("density", current.voxels_per_block, future.voxels_per_block, differences)
	_compare_value("world adapter", current.block_world_size, future.block_world_size, differences)
	var current_visual := current.get_node_or_null("Mesh") as MeshInstance3D
	var future_visual := future.get_node_or_null("Mesh") as MeshInstance3D
	_compare_mesh_nodes(
		"visual", current_visual, future_visual,
		1.0 / float(current.voxels_per_block), differences, topology_changes,
	)
	_compare_collision(current, future, differences)
	_compare_omni(current, future, differences)
	_compare_shadow_body(model_id, current, differences, topology_changes)
	current.free()
	future.free()
	return {
		"id": model_id,
		"exact": differences.is_empty(),
		"inspect_error": false,
		"differences": differences,
		"topology_changes": topology_changes,
	}


func _compare_mesh_nodes(
	label: String,
	current: MeshInstance3D,
	future: MeshInstance3D,
	voxel_size: float,
	differences: Array[String],
	topology_changes: Array[String],
) -> void:
	if (current == null) != (future == null):
		differences.append("%s node presence" % label)
		return
	if current == null:
		return
	if not current.position.is_equal_approx(future.position):
		differences.append("%s position" % label)
	if current.cast_shadow != future.cast_shadow:
		differences.append("%s shadow mode" % label)
	var mesh_errors: Array[String] = []
	var checks: Array[String] = []
	Parity._compare_meshes(current.mesh as ArrayMesh, future.mesh as ArrayMesh, mesh_errors, checks)
	if not mesh_errors.is_empty():
		topology_changes.append(label)
	if not _same_keys(
		_mesh_face_keys(current.mesh as ArrayMesh, voxel_size, true),
		_mesh_face_keys(future.mesh as ArrayMesh, voxel_size, true),
	):
		differences.append("%s voxel faces/colors" % label)


func _compare_collision(current: EmberVoxelProp, future: EmberVoxelProp, differences: Array[String]) -> void:
	var current_shape := current.get_node_or_null("Collision/Shape") as CollisionShape3D
	var future_shape := future.get_node_or_null("Collision/Shape") as CollisionShape3D
	if (current_shape == null) != (future_shape == null):
		differences.append("collision presence")
		return
	if current_shape == null:
		return
	if not current_shape.position.is_equal_approx(future_shape.position):
		differences.append("collision position")
	var current_concave := current_shape.shape as ConcavePolygonShape3D
	var future_concave := future_shape.shape as ConcavePolygonShape3D
	if current_concave == null or future_concave == null:
		differences.append("collision shape type")
		return
	var voxel_size := 1.0 / float(current.voxels_per_block)
	if not _same_keys(
		_triangle_face_keys(current_concave.get_faces(), voxel_size, "collision", Color.WHITE),
		_triangle_face_keys(future_concave.get_faces(), voxel_size, "collision", Color.WHITE),
	):
		differences.append("collision voxel faces")


func _compare_omni(current: EmberVoxelProp, future: EmberVoxelProp, differences: Array[String]) -> void:
	var current_light := current.get_node_or_null("Omni") as OmniLight3D
	var future_light := future.get_node_or_null("Omni") as OmniLight3D
	if (current_light == null) != (future_light == null):
		differences.append("Omni presence")
		return
	if current_light == null:
		return
	if (
		not current_light.position.is_equal_approx(future_light.position)
		or not is_equal_approx(current_light.omni_range, future_light.omni_range)
		or not is_equal_approx(current_light.light_energy, future_light.light_energy)
		or not current_light.light_color.is_equal_approx(future_light.light_color)
		or current_light.shadow_enabled != future_light.shadow_enabled
	):
		differences.append("Omni settings")


func _compare_shadow_body(
	model_id: String,
	current: EmberVoxelProp,
	differences: Array[String],
	topology_changes: Array[String],
) -> void:
	var definition := EmberVoxelCatalog.definition(model_id)
	var model := EmberVoxelPrefab.model_of(definition)
	var resource_report := EmberVoxelLegacyImporter.preview_model(model_id)
	var resource: EmberVoxelModelResource = resource_report.get("resource")
	var expected: ArrayMesh = null
	if resource != null:
		var voxel_size := 1.0 / float(resource.normalized_density())
		expected = EmberVoxelPrefab._body_mesh(
			model_id, definition, model, voxel_size, resource.grid_size()
		)
	var current_body := current.get_node_or_null("ShadowBody") as MeshInstance3D
	if (current_body == null) != (expected == null):
		differences.append("shadow body presence")
		return
	if current_body == null:
		return
	var mesh_errors: Array[String] = []
	var checks: Array[String] = []
	Parity._compare_meshes(current_body.mesh as ArrayMesh, expected, mesh_errors, checks)
	if not mesh_errors.is_empty():
		topology_changes.append("shadow body")
	var voxel_size := 1.0 / float(resource.normalized_density())
	if not _same_keys(
		_mesh_face_keys(current_body.mesh as ArrayMesh, voxel_size, false),
		_mesh_face_keys(expected, voxel_size, false),
	):
		differences.append("shadow body voxel faces")


func _compare_value(label: String, current: Variant, future: Variant, differences: Array[String]) -> void:
	if current != future:
		differences.append(label)


func _mesh_face_keys(mesh: ArrayMesh, voxel_size: float, include_color: bool) -> Dictionary:
	var result := {}
	if mesh == null:
		return result
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var triangle_vertices := PackedVector3Array()
		var triangle_normals := PackedVector3Array()
		var triangle_colors := PackedColorArray()
		if indices.is_empty():
			triangle_vertices = vertices
			triangle_normals = normals
			triangle_colors = colors
		else:
			for index in indices:
				triangle_vertices.append(vertices[index])
				triangle_normals.append(normals[index] if index < normals.size() else Vector3.ZERO)
				triangle_colors.append(colors[index] if index < colors.size() else Color.WHITE)
		var surface_name := mesh.surface_get_name(surface_index)
		for index in range(0, triangle_vertices.size(), 3):
			var normal := triangle_normals[index]
			if normal.is_zero_approx():
				normal = (triangle_vertices[index + 1] - triangle_vertices[index]).cross(
					triangle_vertices[index + 2] - triangle_vertices[index]
				).normalized()
			var color := triangle_colors[index] if include_color else Color.WHITE
			_append_triangle_cells(
				result,
				triangle_vertices[index], triangle_vertices[index + 1], triangle_vertices[index + 2],
				normal, voxel_size, surface_name, color,
			)
	return result


func _triangle_face_keys(
	faces: PackedVector3Array,
	voxel_size: float,
	surface_name: String,
	color: Color,
) -> Dictionary:
	var result := {}
	for index in range(0, faces.size(), 3):
		var normal := (faces[index + 1] - faces[index]).cross(
			faces[index + 2] - faces[index]
		).normalized()
		_append_triangle_cells(
			result, faces[index], faces[index + 1], faces[index + 2],
			normal, voxel_size, surface_name, color,
		)
	return result


func _append_triangle_cells(
	result: Dictionary,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	normal: Vector3,
	voxel_size: float,
	surface_name: String,
	color: Color,
) -> void:
	var absolute := normal.abs()
	var axis := 0
	if absolute.y > absolute.x and absolute.y >= absolute.z:
		axis = 1
	elif absolute.z > absolute.x and absolute.z > absolute.y:
		axis = 2
	var component := normal[axis]
	var sign := 1 if component >= 0.0 else -1
	var axes := [0, 1, 2]
	axes.erase(axis)
	var u_axis: int = axes[0]
	var v_axis: int = axes[1]
	var plane := roundi(a[axis] / voxel_size)
	var u_min := roundi(minf(a[u_axis], minf(b[u_axis], c[u_axis])) / voxel_size)
	var u_max := roundi(maxf(a[u_axis], maxf(b[u_axis], c[u_axis])) / voxel_size)
	var v_min := roundi(minf(a[v_axis], minf(b[v_axis], c[v_axis])) / voxel_size)
	var v_max := roundi(maxf(a[v_axis], maxf(b[v_axis], c[v_axis])) / voxel_size)
	for u in range(u_min, u_max):
		for v in range(v_min, v_max):
			var key := "%s|%d|%d|%d|%d|%d|%s" % [
				surface_name, axis, sign, plane, u, v, color.to_html(true),
			]
			result[key] = true


func _same_keys(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for key in left:
		if not right.has(key):
			return false
	return true


func _watched_hashes(model_ids: Array[String]) -> Dictionary:
	var result := {}
	for model_id in model_ids:
		var preview := EmberVoxelLegacyImporter.preview_model(model_id)
		var paths: Dictionary = preview.get("sourcePaths", {})
		for key in ["json", "vox"]:
			_add_hash(result, str(paths.get(key, "")))
		_add_hash(result, EmberVoxelCatalog.native_path(model_id))
		_add_hash(result, EmberVoxelPrefab.prefab_path(model_id))
		_add_hash(result, EmberVoxelPrefab.mesh_path(model_id))
		_add_hash(result, EmberVoxelPrefab.mesh_path(model_id, true))
	return result


func _add_hash(result: Dictionary, path: String) -> void:
	if path.is_empty():
		return
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	result[path] = FileAccess.get_sha256(absolute) if FileAccess.file_exists(absolute) else "missing"
