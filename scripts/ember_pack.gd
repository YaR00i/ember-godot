class_name EmberPack
extends RefCounted
## Resolves the JOI `content/ember` pack. No second JSON schema.

const VOXELS_PER_BLOCK := 16


static func pack_root() -> String:
	var override := str(ProjectSettings.get_setting("ember/pack_path", ""))
	if override.strip_edges() != "":
		return override.replace("\\", "/")
	var here := ProjectSettings.globalize_path("res://").rstrip("/\\")
	return here.path_join("..").path_join("joi-conductor").path_join("content").path_join("ember")


static func map_path(map_id: String) -> String:
	return pack_root().path_join("maps").path_join("%s.json" % map_id)


static func tileset_path(tileset_id: String) -> String:
	return pack_root().path_join("tilesets").path_join("%s.json" % tileset_id)


static func model_json_path(model_id: String) -> String:
	return pack_root().path_join("voxels").path_join("models").path_join("%s.json" % model_id)


static func script_path(script_id: String) -> String:
	return pack_root().path_join("scripts").path_join("%s.json" % script_id)


static func scene_path(scene_id: String) -> String:
	return pack_root().path_join("scenes").path_join("%s.json" % scene_id)


static func shop_catalog_path() -> String:
	return pack_root().path_join("shops").path_join("catalog.json")


static func item_catalog_path() -> String:
	return pack_root().path_join("items").path_join("catalog.json")


static func stage_path(stage_id: String) -> String:
	return pack_root().path_join("stages").path_join("%s.json" % stage_id)


static func layer_data(map: Dictionary, name: String) -> Array:
	var layers: Array = map.get("layers", [])
	for layer in layers:
		if typeof(layer) == TYPE_DICTIONARY and str(layer.get("name", "")) == name:
			var data: Variant = layer.get("data", [])
			return data if typeof(data) == TYPE_ARRAY else []
	return []


static func read_text(path: String) -> String:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		push_error("ember pack: cannot read %s (%s)" % [path, FileAccess.get_open_error()])
		return ""
	return fa.get_as_text()


static func parse_json_file(path: String) -> Variant:
	var text := read_text(path)
	if text.is_empty():
		return null
	return JSON.parse_string(text)
