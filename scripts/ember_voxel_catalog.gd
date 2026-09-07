@tool
class_name EmberVoxelCatalog
extends RefCounted
## Native-first catalog. Godot Resources are the writable owner; the JOI pack
## is a temporary read-only import queue until the migration report is clean.

const NATIVE_DIR := "res://content/voxel_models"


static func definitions() -> Dictionary:
	var result := {}
	if DirAccess.dir_exists_absolute(NATIVE_DIR):
		for filename in DirAccess.get_files_at(NATIVE_DIR):
			if filename.get_extension().to_lower() not in ["tres", "res"]:
				continue
			var resource := ResourceLoader.load(NATIVE_DIR.path_join(filename)) as EmberVoxelModelResource
			if resource == null or resource.model_id.strip_edges().is_empty():
				continue
			var definition := resource.to_definition()
			definition["_owner"] = "godot"
			result[resource.model_id] = definition
	var directory := EmberPack.pack_root().path_join("voxels").path_join("models")
	if not DirAccess.dir_exists_absolute(directory):
		return result
	for filename in DirAccess.get_files_at(directory):
		if filename.get_extension().to_lower() != "json":
			continue
		var raw: Variant = EmberPack.parse_json_file(directory.path_join(filename))
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var definition := (raw as Dictionary).duplicate(true)
		var model_id := str(definition.get("id", filename.get_basename())).strip_edges()
		if not model_id.is_empty() and not result.has(model_id):
			definition["id"] = model_id
			definition["_owner"] = "legacy_import"
			result[model_id] = definition
	return result


static func definition(model_id: String) -> Dictionary:
	model_id = model_id.strip_edges()
	var native := native_resource(model_id)
	if native != null:
		var result := native.to_definition()
		result["_owner"] = "godot"
		return result
	var json_path := EmberPack.model_json_path(model_id)
	var raw: Variant = EmberPack.parse_json_file(json_path) if FileAccess.file_exists(json_path) else null
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var legacy := (raw as Dictionary).duplicate(true)
	legacy["id"] = model_id
	legacy["_owner"] = "legacy_import"
	return legacy


static func native_path(model_id: String) -> String:
	return "%s/%s.tres" % [NATIVE_DIR, model_id.strip_edges()]


static func native_resource(model_id: String) -> EmberVoxelModelResource:
	var path := native_path(model_id)
	if not FileAccess.file_exists(ProjectSettings.globalize_path(path)):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as EmberVoxelModelResource


static func owner(model_id: String) -> String:
	return str(definition(model_id).get("_owner", ""))


static func ids() -> Array[String]:
	var result: Array[String] = []
	for model_id in definitions():
		result.append(str(model_id))
	result.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return result
