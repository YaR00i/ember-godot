class_name EmberShopCatalog
extends RefCounted
## Shared editor/runtime shop storage. Native per-shop Resources win by ID;
## entries in legacy shops/catalog.json remain a read-only fallback.

const ShopResource = preload("res://scripts/ember_shop_resource.gd")
const NATIVE_DIR := "res://content/shops"


static func definition(shop_id: String) -> Dictionary:
	var clean := shop_id.strip_edges()
	if not _valid_id(clean):
		return {}
	var native := native_definition(clean)
	return native if not native.is_empty() else legacy_definition(clean)


static func native_definition(shop_id: String) -> Dictionary:
	var clean := shop_id.strip_edges()
	if not _valid_id(clean):
		return {}
	var path := native_path(clean)
	if not FileAccess.file_exists(path):
		return {}
	var resource := ResourceLoader.load(
		path, "", ResourceLoader.CACHE_MODE_IGNORE
	) as EmberShopResource
	return resource.to_definition() if resource != null else {}


static func legacy_definition(shop_id: String) -> Dictionary:
	var catalog: Variant = EmberPack.parse_json_file(EmberPack.shop_catalog_path())
	if typeof(catalog) != TYPE_DICTIONARY:
		return {}
	var shops: Variant = catalog.get("shops", [])
	if typeof(shops) != TYPE_ARRAY:
		return {}
	for raw_shop in shops:
		if typeof(raw_shop) == TYPE_DICTIONARY and str(raw_shop.get("id", "")) == shop_id:
			return (raw_shop as Dictionary).duplicate(true)
	return {}


static func owner(shop_id: String) -> String:
	var clean := shop_id.strip_edges()
	if not _valid_id(clean):
		return ""
	if FileAccess.file_exists(native_path(clean)):
		return "native"
	return "legacy" if not legacy_definition(clean).is_empty() else ""


static func ids() -> Array[String]:
	var known := {}
	var absolute_native := ProjectSettings.globalize_path(NATIVE_DIR)
	if DirAccess.dir_exists_absolute(absolute_native):
		for filename in DirAccess.get_files_at(absolute_native):
			if filename.get_extension().to_lower() == "tres":
				var shop_id := filename.get_basename()
				if _valid_id(shop_id):
					known[shop_id] = true
	var catalog: Variant = EmberPack.parse_json_file(EmberPack.shop_catalog_path())
	if typeof(catalog) == TYPE_DICTIONARY:
		var shops: Variant = catalog.get("shops", [])
		if typeof(shops) == TYPE_ARRAY:
			for raw_shop in shops:
				if typeof(raw_shop) == TYPE_DICTIONARY:
					var shop_id := str(raw_shop.get("id", "")).strip_edges()
					if _valid_id(shop_id):
						known[shop_id] = true
	var result: Array[String] = []
	for shop_id in known:
		result.append(str(shop_id))
	result.sort()
	return result


static func native_path(shop_id: String) -> String:
	return NATIVE_DIR.path_join("%s.tres" % shop_id.strip_edges())


static func write_native(definition_value: Dictionary) -> int:
	var shop_id := str(definition_value.get("id", "")).strip_edges()
	if not _valid_id(shop_id):
		return ERR_INVALID_PARAMETER
	var mkdir_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(NATIVE_DIR)
	)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		return mkdir_error
	var resource := ShopResource.new() as EmberShopResource
	resource.shop_id = shop_id
	resource.definition = definition_value.duplicate(true)
	return ResourceSaver.save(resource, native_path(shop_id))


static func delete_native(shop_id: String) -> int:
	var clean := shop_id.strip_edges()
	if not _valid_id(clean):
		return ERR_INVALID_PARAMETER
	var path := native_path(clean)
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else OK


static func snapshot(shop_id: String) -> Dictionary:
	return {"id": shop_id, "native": native_definition(shop_id)}


static func restore(snapshot_value: Dictionary) -> int:
	var shop_id := str(snapshot_value.get("id", "")).strip_edges()
	if not _valid_id(shop_id):
		return ERR_INVALID_PARAMETER
	var native: Dictionary = snapshot_value.get("native", {})
	return delete_native(shop_id) if native.is_empty() else write_native(native)


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
