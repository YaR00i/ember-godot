@tool
class_name EmberVoxelLegacyImporter
extends RefCounted
## One-way migration adapter. It reads the frozen JOI pair and writes a
## Godot-owned EmberVoxelModelResource. It never writes back to JOI.

const NATIVE_DIR := "res://content/voxel_models"


static func destination_path(model_id: String) -> String:
	return "%s/%s.tres" % [NATIVE_DIR, model_id.strip_edges()]


static func import_model(model_id: String, destination := "", overwrite := false) -> Dictionary:
	model_id = model_id.strip_edges()
	if model_id.is_empty():
		return _failure("model_id is empty")
	if destination.is_empty():
		destination = destination_path(model_id)
	if ResourceLoader.exists(destination) and not overwrite:
		return _failure("native resource already exists: %s" % destination)
	var preview := preview_model(model_id)
	if not bool(preview.get("ok", false)):
		return preview
	var resource: EmberVoxelModelResource = preview.get("resource")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
	var save_error := ResourceSaver.save(resource, destination)
	if save_error != OK:
		return _failure("cannot save %s (%s)" % [destination, save_error])
	return {
		"ok": true,
		"path": destination,
		"resource": resource,
		"sourceHash": resource.imported_source_hash,
	}


static func preview_model(model_id: String) -> Dictionary:
	## Builds the exact native Resource in memory without saving it. The parity
	## gate is therefore allowed to inspect legacy input before any project write.
	model_id = model_id.strip_edges()
	if model_id.is_empty():
		return _failure("model_id is empty")
	var json_path := EmberPack.model_json_path(model_id)
	var parsed: Variant = EmberPack.parse_json_file(json_path)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failure("legacy JSON is missing: %s" % json_path)
	var definition := parsed as Dictionary
	var raw_model: Variant = definition.get("model", {})
	if typeof(raw_model) != TYPE_DICTIONARY:
		return _failure("legacy JSON has no model dictionary")
	var model := raw_model as Dictionary
	var resource := EmberVoxelModelResource.new()
	resource.model_id = str(definition.get("id", model.get("id", model_id))).strip_edges()
	resource.display_name = str(definition.get("nameRu", model.get("nameRu", resource.model_id)))
	resource.tags = PackedStringArray(_strings(definition.get("tags", model.get("tags", []))))
	resource.voxels_per_block = 32 if int(model.get("voxelsPerBlock", 16)) == 32 else 16
	resource.size_blocks = _size_blocks(model.get("sizeBlocks", {}))
	resource.height_voxels = int(model.get("heightVoxels", resource.voxels_per_block))
	resource.material = _dictionary(model.get("material", {}))
	resource.physical = bool(model.get("physical", true))
	resource.emissive = _bytes(model.get("emissive", []))
	resource.shine = _bytes(model.get("shine", []))
	resource.transparency = _bytes(model.get("transparency", []))
	resource.transmittance = _bytes(model.get("transmittance", []))
	resource.emissive_casts_light = bool(model.get("emissiveCastsLight", false))
	resource.emissive_light_range = float(model.get("emissiveLightRange", 18.0))
	resource.emissive_light_shadows = bool(model.get("emissiveLightShadows", false))
	resource.emissive_light_soft_rings = bool(model.get("emissiveLightSoftRings", true))
	resource.emissive_light_soft_shadows = bool(model.get("emissiveLightSoftShadows", true))
	resource.emissive_strength = float(model.get("emissiveStrength", 1.0))
	resource.emissive_suppress_host_shadow = bool(model.get("emissiveSuppressHostShadow", false))
	resource.emissive_torch_flicker = bool(model.get("emissiveTorchFlicker", false))
	resource.emissive_light_offset = _vector3(model.get("emissiveLightOffset", {}))
	resource.emissive_lights = _dictionaries(model.get("emissiveLights", []))

	var vox_path := _legacy_vox_path(model_id, definition)
	var doc := VoxParser.parse_file(vox_path) if not vox_path.is_empty() else {}
	if not doc.is_empty():
		_apply_vox_document(resource, doc)
	else:
		resource.palette = _palette(model.get("palette", []))
		resource.voxels = _bytes(model.get("voxels", []))
	resource.imported_from = "legacy-joi://content/ember/voxels/models/%s.json" % model_id
	resource.imported_source_hash = _source_hash(json_path, vox_path)

	var errors := resource.validation_errors()
	if not errors.is_empty():
		return {"ok": false, "error": "; ".join(errors), "errors": errors}
	return {
		"ok": true,
		"resource": resource,
		"sourceHash": resource.imported_source_hash,
		"legacyDefinition": definition.duplicate(true),
		"voxDocument": doc.duplicate(true),
		"sourcePaths": {"json": json_path, "vox": vox_path},
	}


static func _apply_vox_document(resource: EmberVoxelModelResource, doc: Dictionary) -> void:
	var first: Dictionary = (doc.get("models", []) as Array)[0]
	var ember_size := VoxMesher.ember_size(first.get("size", Vector3i.ONE))
	var density := resource.normalized_density()
	resource.size_blocks = Vector3i(
		maxi(1, ceili(float(ember_size.x) / density)),
		maxi(1, ceili(float(ember_size.y) / density)),
		maxi(1, ceili(float(ember_size.z) / density)),
	)
	resource.height_voxels = ember_size.y
	var grid := resource.grid_size()
	resource.voxels.resize(grid.x * grid.y * grid.z)
	resource.voxels.fill(0)
	for raw in first.get("voxels", []):
		var voxel := raw as Dictionary
		var e := VoxMesher.vox_to_ember(int(voxel.x), int(voxel.y), int(voxel.z))
		if e.x < grid.x and e.y < grid.y and e.z < grid.z:
			resource.voxels[VoxMesher.cell_index(e.x, e.y, e.z, grid.x, grid.z)] = int(voxel.i)
	resource.palette = _vox_palette(doc.get("palette", PackedByteArray()))


static func _legacy_vox_path(model_id: String, definition: Dictionary) -> String:
	var mesh := _dictionary(definition.get("mesh", {}))
	var relative := str(mesh.get("file", "voxels/models/%s.vox" % model_id)).replace("\\", "/")
	var candidate := EmberPack.pack_root().path_join(relative)
	return candidate if FileAccess.file_exists(candidate) else ""


static func _source_hash(json_path: String, vox_path: String) -> String:
	var parts := [FileAccess.get_sha256(json_path)]
	if not vox_path.is_empty():
		parts.append(FileAccess.get_sha256(vox_path))
	return ":".join(parts).sha256_text()


static func _size_blocks(raw: Variant) -> Vector3i:
	var value := _dictionary(raw)
	return Vector3i(
		maxi(1, int(value.get("x", 1))),
		maxi(1, int(value.get("y", 1))),
		maxi(1, int(value.get("z", 1))),
	)


static func _palette(raw: Variant) -> PackedColorArray:
	var result := PackedColorArray()
	if typeof(raw) != TYPE_ARRAY:
		return result
	for value in raw:
		result.append(EmberLights.hex_color(str(value), Color.TRANSPARENT))
	return result


static func _vox_palette(raw: Variant) -> PackedColorArray:
	var bytes: PackedByteArray = raw if typeof(raw) == TYPE_PACKED_BYTE_ARRAY else PackedByteArray()
	var result := PackedColorArray()
	for index in 256:
		var offset := index * 4
		result.append(Color8(bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3]))
	return result


static func _bytes(raw: Variant) -> PackedByteArray:
	var result := PackedByteArray()
	if typeof(raw) != TYPE_ARRAY and typeof(raw) != TYPE_PACKED_BYTE_ARRAY:
		return result
	for value in raw:
		result.append(clampi(int(value), 0, 255))
	return result


static func _strings(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(raw) == TYPE_ARRAY or typeof(raw) == TYPE_PACKED_STRING_ARRAY:
		for value in raw:
			result.append(str(value))
	return result


static func _dictionaries(raw: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(raw) == TYPE_ARRAY:
		for value in raw:
			if typeof(value) == TYPE_DICTIONARY:
				result.append((value as Dictionary).duplicate(true))
	return result


static func _dictionary(raw: Variant) -> Dictionary:
	return (raw as Dictionary).duplicate(true) if typeof(raw) == TYPE_DICTIONARY else {}


static func _vector3(raw: Variant) -> Vector3:
	var value := _dictionary(raw)
	return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "errors": [message]}
