@tool
class_name EmberVoxelMigrationParity
extends RefCounted
## Strict read-only preflight for legacy voxel migration. JOI access stays
## inside EmberVoxelLegacyImporter; this module only compares transient output.

const Importer = preload("res://scripts/ember_voxel_legacy_importer.gd")
const Mesher = preload("res://scripts/vox_mesher.gd")


static func inspect_batch(model_ids: Array[String]) -> Dictionary:
	var started := Time.get_ticks_msec()
	var entries: Array[Dictionary] = []
	var passed := 0
	for model_id in model_ids:
		var entry := inspect_model(model_id)
		entries.append(entry)
		if bool(entry.get("ok", false)):
			passed += 1
	return {
		"ok": passed == entries.size() and not entries.is_empty(),
		"total": entries.size(),
		"passed": passed,
		"failed": entries.size() - passed,
		"duration_ms": Time.get_ticks_msec() - started,
		"entries": entries,
	}


static func inspect_model(model_id: String) -> Dictionary:
	var errors: Array[String] = []
	var checks: Array[String] = []
	var preview := Importer.preview_model(model_id)
	if not bool(preview.get("ok", false)):
		return {
			"id": model_id,
			"ok": false,
			"errors": preview.get("errors", [preview.get("error", "preview failed")]),
			"checks": checks,
		}
	var resource: EmberVoxelModelResource = preview.get("resource")
	var definition: Dictionary = preview.get("legacyDefinition", {})
	var raw_model: Variant = definition.get("model", {})
	var legacy_model: Dictionary = raw_model if typeof(raw_model) == TYPE_DICTIONARY else {}
	var vox_document: Dictionary = preview.get("voxDocument", {})
	if resource == null:
		errors.append("preview did not produce EmberVoxelModelResource")
		return {"id": model_id, "ok": false, "errors": errors, "checks": checks}

	if resource.model_id != model_id:
		errors.append("model_id changed: %s" % resource.model_id)
	else:
		checks.append("identity")
	var validation := resource.validation_errors()
	if not validation.is_empty():
		errors.append_array(validation)
	else:
		checks.append("validation")
	if resource.imported_source_hash.is_empty():
		errors.append("source hash is empty")
	else:
		checks.append("source hash")
	if not resource.imported_from.begins_with("legacy-joi://"):
		errors.append("provenance is not portable")
	else:
		checks.append("portable provenance")

	_compare_authoring_metadata(resource, definition, legacy_model, errors, checks)
	var density := resource.normalized_density()
	var voxel_size := 1.0 / float(density)
	var legacy_mesh: ArrayMesh
	if vox_document.is_empty():
		legacy_mesh = Mesher.build_from_ember_model(legacy_model, voxel_size)
	else:
		legacy_mesh = Mesher.build_mesh(
			vox_document,
			voxel_size,
			PackedByteArray(),
			Mesher.model_channel(legacy_model, "transparency"),
		)
	var native_definition := resource.to_definition()
	var native_model: Dictionary = native_definition.get("model", {})
	var native_mesh := Mesher.build_from_ember_model(native_model, voxel_size)
	_compare_meshes(legacy_mesh, native_mesh, errors, checks)

	var filled := 0
	for palette_index in resource.voxels:
		if palette_index > 0:
			filled += 1
	return {
		"id": model_id,
		"ok": errors.is_empty(),
		"errors": errors,
		"checks": checks,
		"grid": resource.grid_size(),
		"filled_voxels": filled,
		"palette_colors": resource.palette.size(),
		"mesh_surfaces": native_mesh.get_surface_count(),
		"triangles": _triangle_count(native_mesh),
		"source_hash": resource.imported_source_hash,
		"source_paths": preview.get("sourcePaths", {}).duplicate(true),
	}


static func _compare_authoring_metadata(
	resource: EmberVoxelModelResource,
	definition: Dictionary,
	model: Dictionary,
	errors: Array[String],
	checks: Array[String],
) -> void:
	var expected_name := str(definition.get("nameRu", model.get("nameRu", resource.model_id)))
	var expected_tags := PackedStringArray()
	for value in definition.get("tags", model.get("tags", [])):
		expected_tags.append(str(value))
	if resource.display_name != expected_name:
		errors.append("display name changed")
	if resource.tags != expected_tags:
		errors.append("tags changed")
	if resource.physical != bool(model.get("physical", true)):
		errors.append("physical flag changed")
	if resource.material != _dictionary(model.get("material", {})):
		errors.append("material metadata changed")
	if errors.is_empty():
		checks.append("authoring metadata")


static func _compare_meshes(
	legacy_mesh: ArrayMesh,
	native_mesh: ArrayMesh,
	errors: Array[String],
	checks: Array[String],
) -> void:
	if legacy_mesh == null or native_mesh == null:
		errors.append("legacy or native preview mesh is missing")
		return
	if legacy_mesh.get_surface_count() != native_mesh.get_surface_count():
		errors.append("mesh surface count changed")
		return
	if legacy_mesh.get_surface_count() == 0:
		errors.append("preview mesh is empty")
		return
	for surface_index in legacy_mesh.get_surface_count():
		if legacy_mesh.surface_get_name(surface_index) != native_mesh.surface_get_name(surface_index):
			errors.append("surface %d material channel changed" % surface_index)
			continue
		var legacy_arrays := legacy_mesh.surface_get_arrays(surface_index)
		var native_arrays := native_mesh.surface_get_arrays(surface_index)
		_compare_vectors(
			legacy_arrays[Mesh.ARRAY_VERTEX], native_arrays[Mesh.ARRAY_VERTEX],
			"surface %d vertices" % surface_index, errors,
		)
		_compare_vectors(
			legacy_arrays[Mesh.ARRAY_NORMAL], native_arrays[Mesh.ARRAY_NORMAL],
			"surface %d normals" % surface_index, errors,
		)
		_compare_colors(
			legacy_arrays[Mesh.ARRAY_COLOR], native_arrays[Mesh.ARRAY_COLOR],
			"surface %d colors" % surface_index, errors,
		)
		_compare_indices(
			legacy_arrays[Mesh.ARRAY_INDEX], native_arrays[Mesh.ARRAY_INDEX],
			"surface %d indices" % surface_index, errors,
		)
	if errors.is_empty():
		checks.append("exact visual mesh")
		checks.append("collision source mesh")


static func _compare_vectors(
	legacy: PackedVector3Array,
	native: PackedVector3Array,
	label: String,
	errors: Array[String],
) -> void:
	if legacy.size() != native.size():
		errors.append("%s count changed: %d -> %d" % [label, legacy.size(), native.size()])
		return
	for index in legacy.size():
		if not legacy[index].is_equal_approx(native[index]):
			errors.append("%s differ at %d" % [label, index])
			return


static func _compare_colors(
	legacy: PackedColorArray,
	native: PackedColorArray,
	label: String,
	errors: Array[String],
) -> void:
	if legacy.size() != native.size():
		errors.append("%s count changed: %d -> %d" % [label, legacy.size(), native.size()])
		return
	for index in legacy.size():
		if not legacy[index].is_equal_approx(native[index]):
			errors.append("%s differ at %d" % [label, index])
			return


static func _compare_indices(
	legacy: PackedInt32Array,
	native: PackedInt32Array,
	label: String,
	errors: Array[String],
) -> void:
	if legacy.size() != native.size():
		errors.append("%s count changed: %d -> %d" % [label, legacy.size(), native.size()])
		return
	for index in legacy.size():
		if legacy[index] != native[index]:
			errors.append("%s differ at %d" % [label, index])
			return


static func _triangle_count(mesh: ArrayMesh) -> int:
	var result := 0
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		result += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return result


static func _dictionary(raw: Variant) -> Dictionary:
	return (raw as Dictionary).duplicate(true) if typeof(raw) == TYPE_DICTIONARY else {}
