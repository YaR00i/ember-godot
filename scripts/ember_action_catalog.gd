class_name EmberActionCatalog
extends RefCounted
## Shared native-only action storage; runtime and editor use one Resource owner.

const ActionResource = preload("res://scripts/ember_action_resource.gd")
const NATIVE_DIR := "res://content/action_scripts"


static func document(action_id: String) -> Dictionary:
	var clean := action_id.strip_edges()
	if not _valid_id(clean):
		return {}
	return native_document(clean)


static func native_document(action_id: String) -> Dictionary:
	var clean := action_id.strip_edges()
	if not _valid_id(clean):
		return {}
	var path := native_path(clean)
	if not ResourceLoader.exists(path):
		return {}
	var resource := ResourceLoader.load(
		path, "", ResourceLoader.CACHE_MODE_IGNORE
	) as EmberActionResource
	return resource.to_document() if resource != null else {}


static func owner(action_id: String) -> String:
	var clean := action_id.strip_edges()
	if not _valid_id(clean): return ""
	return "native" if ResourceLoader.exists(native_path(clean)) else ""


static func ids() -> Array[String]:
	var result: Array[String] = []
	if not DirAccess.dir_exists_absolute(NATIVE_DIR): return result
	for filename in DirAccess.get_files_at(NATIVE_DIR):
		filename = filename.trim_suffix(".remap")
		if filename.get_extension().to_lower() != "tres": continue
		var id := filename.get_basename()
		if _valid_id(id) and id not in result: result.append(id)
	result.sort()
	return result


static func native_path(action_id: String) -> String:
	return NATIVE_DIR.path_join("%s.tres" % action_id.strip_edges())


static func write_native(document_value: Dictionary) -> int:
	var action_id := str(document_value.get("id", "")).strip_edges()
	if not _valid_id(action_id):
		return ERR_INVALID_PARAMETER
	var mkdir_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(NATIVE_DIR)
	)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		return mkdir_error
	var resource := ActionResource.new() as EmberActionResource
	resource.action_id = action_id
	resource.document = document_value.duplicate(true)
	return ResourceSaver.save(resource, native_path(action_id))


static func delete_native(action_id: String) -> int:
	var clean := action_id.strip_edges()
	if not _valid_id(clean):
		return ERR_INVALID_PARAMETER
	var path := native_path(clean)
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else OK


static func snapshot(action_id: String) -> Dictionary:
	return {"id": action_id, "native": native_document(action_id)}


static func restore(snapshot_value: Dictionary) -> int:
	var id := str(snapshot_value.get("id", "")).strip_edges()
	if not _valid_id(id): return ERR_INVALID_PARAMETER
	var native: Dictionary = snapshot_value.get("native", {})
	return delete_native(id) if native.is_empty() else write_native(native)


static func _valid_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		var allowed := (
			(code >= 48 and code <= 57)
			or (code >= 97 and code <= 122)
			or (index > 0 and code in [45, 95])
		)
		if not allowed:
			return false
	return true
