@tool
class_name EmberVoxelCatalog
extends RefCounted
## Native-only runtime/editor catalog. Historical discovery belongs only to
## the explicit EmberVoxelLegacyImporter migration tools.

const NATIVE_DIR := "res://content/voxel_models"


static func definitions(metadata_only := false) -> Dictionary:
	var result := {}
	if DirAccess.dir_exists_absolute(NATIVE_DIR):
		for path in _resource_paths():
			var resource := ResourceLoader.load(path) as EmberVoxelModelResource
			if resource == null or resource.model_id.strip_edges().is_empty():
				continue
			# Shelf metadata must not expand dense geometry/channel arrays.
			var definition := {
				"id": resource.model_id,
				"nameRu": resource.display_name,
				"tags": Array(resource.tags),
				"model": {
					"voxelsPerBlock": resource.normalized_density(),
					"sizeBlocks": {"x": resource.size_blocks.x, "y": resource.size_blocks.y, "z": resource.size_blocks.z},
				},
			} if metadata_only else resource.to_definition()
			definition["_owner"] = "godot"
			result[resource.model_id] = definition
	return result


static func definition(model_id: String) -> Dictionary:
	model_id = model_id.strip_edges()
	var native := native_resource(model_id)
	if native != null:
		var result := native.to_definition()
		result["_owner"] = "godot"
		return result
	return {}


static func native_path(model_id: String) -> String:
	return "%s/%s.tres" % [NATIVE_DIR, model_id.strip_edges()]


static func native_resource(model_id: String) -> EmberVoxelModelResource:
	var clean := model_id.strip_edges()
	if clean.is_empty() or clean.contains("/") or clean.contains("\\") or clean.contains("..") or clean.contains(":"): return null
	var path := native_path(clean)
	if not ResourceLoader.exists(path):
		path = NATIVE_DIR.path_join(clean + ".res")
		if not ResourceLoader.exists(path): return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as EmberVoxelModelResource


static func owner(model_id: String) -> String:
	return "godot" if native_resource(model_id) != null else ""


static func ids() -> Array[String]:
	var result: Array[String] = []
	for model_id in definitions(true):
		result.append(str(model_id))
	result.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return result


static func _resource_paths() -> Array[String]:
	var result: Array[String] = []
	for filename in DirAccess.get_files_at(NATIVE_DIR):
		filename = filename.trim_suffix(".remap")
		if filename.get_extension().to_lower() not in ["tres", "res"]: continue
		var path := NATIVE_DIR.path_join(filename)
		if path not in result and ResourceLoader.exists(path): result.append(path)
	result.sort()
	return result
