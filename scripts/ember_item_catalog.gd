class_name EmberItemCatalog
extends RefCounted
## Shared native item and pixel-icon storage for editor/runtime. No legacy reads.

const ItemResource = preload("res://scripts/ember_item_resource.gd")
const NATIVE_DIR := "res://content/items"
const IconResource = preload("res://scripts/ember_item_icon_resource.gd")
const ICON_DIR := "res://content/item_icons"


static func definition(item_id: String) -> Dictionary:
	var clean := item_id.strip_edges()
	if not _valid_id(clean):
		return {}
	return native_definition(clean)


static func definitions() -> Dictionary:
	var result := {}
	for item_id in native_ids():
		var native := native_definition(item_id)
		if not native.is_empty():
			result[item_id] = native
	return result


static func native_definition(item_id: String) -> Dictionary:
	var clean := item_id.strip_edges()
	if not _valid_id(clean):
		return {}
	var path := native_path(clean)
	if not ResourceLoader.exists(path):
		return {}
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberItemResource
	return resource.to_definition() if resource != null else {}


static func owner(item_id: String) -> String:
	var clean := item_id.strip_edges()
	if not _valid_id(clean):
		return ""
	if ResourceLoader.exists(native_path(clean)):
		return "native"
	return ""


static func ids() -> Array[String]:
	return native_ids()


static func native_ids() -> Array[String]:
	return _resource_ids(NATIVE_DIR)


static func icon_ids() -> Array[String]:
	return _resource_ids(ICON_DIR)


static func icon_definition(icon_id: String) -> Dictionary:
	var clean := icon_id.strip_edges()
	if not _valid_id(clean): return {}
	var path := ICON_DIR.path_join(clean + ".tres")
	if not ResourceLoader.exists(path): return {}
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as IconResource
	return resource.to_definition() if resource != null else {}


static func icon_definitions() -> Dictionary:
	var result := {}
	for icon_id in icon_ids():
		var icon := icon_definition(icon_id)
		if not icon.is_empty(): result[icon_id] = icon
	return result


static func _resource_ids(directory: String) -> Array[String]:
	var result: Array[String] = []
	if not DirAccess.dir_exists_absolute(directory): return result
	for filename in DirAccess.get_files_at(directory):
		# Exported Resources can be listed through their remap filenames.
		filename = filename.trim_suffix(".remap")
		if filename.get_extension().to_lower() != "tres": continue
		var id := filename.get_basename()
		if _valid_id(id) and id not in result: result.append(id)
	result.sort()
	return result


static func native_path(item_id: String) -> String:
	return NATIVE_DIR.path_join("%s.tres" % item_id.strip_edges())


static func write_native(definition_value: Dictionary) -> int:
	var item_id := str(definition_value.get("id", "")).strip_edges()
	if not _valid_id(item_id):
		return ERR_INVALID_PARAMETER
	var mkdir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(NATIVE_DIR))
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		return mkdir_error
	var resource := ItemResource.new() as EmberItemResource
	resource.item_id = item_id
	resource.definition = definition_value.duplicate(true)
	return ResourceSaver.save(resource, native_path(item_id))


static func delete_native(item_id: String) -> int:
	var clean := item_id.strip_edges()
	if not _valid_id(clean):
		return ERR_INVALID_PARAMETER
	var path := native_path(clean)
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else OK


static func snapshot(item_id: String) -> Dictionary:
	return {"id": item_id, "native": native_definition(item_id)}


static func restore(snapshot_value: Dictionary) -> int:
	var item_id := str(snapshot_value.get("id", "")).strip_edges()
	if not _valid_id(item_id):
		return ERR_INVALID_PARAMETER
	var native: Dictionary = snapshot_value.get("native", {})
	return delete_native(item_id) if native.is_empty() else write_native(native)


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
