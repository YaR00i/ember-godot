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


static func model_json_path(model_id: String) -> String:
	return pack_root().path_join("voxels").path_join("models").path_join("%s.json" % model_id)


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
