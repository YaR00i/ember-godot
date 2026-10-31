@tool
class_name EmberVoxelCatalog
extends RefCounted
## Native-only runtime/editor catalog. Historical discovery belongs only to
## the explicit EmberVoxelLegacyImporter migration tools.

const NATIVE_DIR := "res://content/voxel_models"
const MetadataStorage=preload("res://scripts/prototypes/ember_derived_data_cache.gd")
const METADATA_VERSION:=1 # Bump when the metadata projection/schema changes.
static var metadata_cache_directory:="user://ember-voxel-catalog-cache"
static var metadata_hits:=0
static var metadata_misses:=0
static var metadata_live_reads:=0
static var _metadata_disk:=MetadataStorage.new()
static var _metadata_writes:=0


static func definitions(metadata_only := false) -> Dictionary:
	var result := {}
	if DirAccess.dir_exists_absolute(NATIVE_DIR):
		for path in _resource_paths():
			if metadata_only:
				var metadata:=_metadata_definition(path)
				if not metadata.is_empty():result[metadata.id]=metadata
				continue
			var resource := ResourceLoader.load(path) as EmberVoxelModelResource
			if resource == null or resource.model_id.strip_edges().is_empty():
				continue
			var definition := resource.to_definition()
			definition["_owner"] = "godot"
			result[resource.model_id] = definition
	return result


static func _metadata_of(resource:EmberVoxelModelResource)->Dictionary:
	if resource==null or resource.model_id.strip_edges().is_empty():return {}
	return {"id":resource.model_id,"nameRu":resource.display_name,"tags":Array(resource.tags),
		"model":{"voxelsPerBlock":resource.normalized_density(),"sizeBlocks":{"x":resource.size_blocks.x,"y":resource.size_blocks.y,"z":resource.size_blocks.z}},"_owner":"godot"}


static func _valid_metadata(value:Variant)->bool:
	if not value is Dictionary or value.size()!=5 or not value.get("id") is String or value.id.strip_edges().is_empty() or not value.get("nameRu") is String or not value.get("tags") is Array or value.get("_owner")!="godot":return false
	for tag in value.tags:
		if not tag is String:return false
	var model:Variant=value.get("model")
	if not model is Dictionary or model.size()!=2 or not model.get("voxelsPerBlock") is int or model.voxelsPerBlock not in [16,32] or not model.get("sizeBlocks") is Dictionary or model.sizeBlocks.size()!=3:return false
	for axis in ["x","y","z"]:
		if not model.sizeBlocks.get(axis) is int:return false
	return true


static func _metadata_key(path:String,fingerprint:String)->String:
	return MetadataStorage.digest([METADATA_VERSION,Engine.get_version_info().hex,FileAccess.get_sha256("res://scripts/ember_voxel_model_resource.gd"),path,fingerprint])


static func _metadata_definition(path:String)->Dictionary:
	# Preserve ResourceLoader.REUSE semantics, including unsaved Inspector edits.
	# Never persist that in-memory draft under the hash of an older file.
	if ResourceLoader.has_cached(path):
		metadata_live_reads+=1
		return _metadata_of(ResourceLoader.load(path) as EmberVoxelModelResource)
	var fingerprint:="" if metadata_cache_directory.is_empty() else FileAccess.get_sha256(path)
	if fingerprint.is_empty():return _metadata_of(ResourceLoader.load(path) as EmberVoxelModelResource)
	_metadata_disk.directory=metadata_cache_directory;_metadata_disk.max_bytes=1024*1024
	var key:=_metadata_key(path,fingerprint)
	var saved:Dictionary=_metadata_disk.read(key)
	if _valid_metadata(saved.get("metadata")):
		metadata_hits+=1;return saved.metadata
	metadata_misses+=1
	var metadata:=_metadata_of(ResourceLoader.load(path) as EmberVoxelModelResource)
	if not metadata.is_empty() and FileAccess.get_sha256(path)==fingerprint:
		_metadata_disk.write(key,{"metadata":metadata},func():return false)
		_metadata_writes+=1
		if _metadata_writes==1 or _metadata_writes%16==0:_metadata_disk.trim(16*1024*1024)
	return metadata


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
