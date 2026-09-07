class_name EmberItemCatalog
extends RefCounted
## Shared editor/runtime item storage. Per-item Resources win by ID; items and
## pixel icons in legacy items/catalog.json remain read-only fallbacks.

const ItemResource = preload("res://scripts/ember_item_resource.gd")
const NATIVE_DIR := "res://content/items"


static func definition(item_id: String) -> Dictionary:
	var clean := item_id.strip_edges()
	if not _valid_id(clean):
		return {}
	var native := native_definition(clean)
	return native if not native.is_empty() else legacy_definition(clean)


static func definitions() -> Dictionary:
	var result := legacy_definitions()
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
	if not FileAccess.file_exists(path):
		return {}
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberItemResource
	return resource.to_definition() if resource != null else {}


static func legacy_definition(item_id: String) -> Dictionary:
	return legacy_definitions().get(item_id.strip_edges(), {}).duplicate(true)


static func legacy_definitions() -> Dictionary:
	var result := {}
	var catalog: Variant = EmberPack.parse_json_file(EmberPack.item_catalog_path())
	if typeof(catalog) != TYPE_DICTIONARY:
		return result
	var items: Variant = catalog.get("items", [])
	if typeof(items) != TYPE_ARRAY:
		return result
	for raw_item in items:
		if typeof(raw_item) == TYPE_DICTIONARY:
			var item_id := str(raw_item.get("id", "")).strip_edges()
			if _valid_id(item_id):
				result[item_id] = (raw_item as Dictionary).duplicate(true)
	return result


static func owner(item_id: String) -> String:
	var clean := item_id.strip_edges()
	if not _valid_id(clean):
		return ""
	if FileAccess.file_exists(native_path(clean)):
		return "native"
	return "legacy" if not legacy_definition(clean).is_empty() else ""


static func ids() -> Array[String]:
	var known := {}
	for item_id in legacy_definitions():
		known[item_id] = true
	for item_id in native_ids():
		known[item_id] = true
	var result: Array[String] = []
	for item_id in known:
		result.append(str(item_id))
	result.sort()
	return result


static func native_ids() -> Array[String]:
	var result: Array[String] = []
	var absolute_native := ProjectSettings.globalize_path(NATIVE_DIR)
	if DirAccess.dir_exists_absolute(absolute_native):
		for filename in DirAccess.get_files_at(absolute_native):
			if filename.get_extension().to_lower() == "tres":
				var item_id := filename.get_basename()
				if _valid_id(item_id):
					result.append(item_id)
	result.sort()
	return result


static func icon_ids() -> Array[String]:
	var result: Array[String] = []
	for icon_id in icon_definitions():
		result.append(str(icon_id))
	result.sort()
	return result


static func icon_definition(icon_id: String) -> Dictionary:
	return icon_definitions().get(icon_id.strip_edges(), {}).duplicate(true)


static func icon_definitions() -> Dictionary:
	var result := {}
	var catalog: Variant = EmberPack.parse_json_file(EmberPack.item_catalog_path())
	if typeof(catalog) != TYPE_DICTIONARY:
		return result
	var icons: Variant = catalog.get("icons", [])
	if typeof(icons) != TYPE_ARRAY:
		return result
	for raw_icon in icons:
		if typeof(raw_icon) == TYPE_DICTIONARY:
			var icon_id := str(raw_icon.get("id", "")).strip_edges()
			if not icon_id.is_empty():
				result[icon_id] = (raw_icon as Dictionary).duplicate(true)
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
