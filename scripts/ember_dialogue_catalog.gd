class_name EmberDialogueCatalog
extends RefCounted
## Shared editor/runtime dialogue storage. Native Resources win by ID; legacy
## JOI scenes/*.json remain read-only fallback until explicitly migrated.

const DialogueResource = preload("res://scripts/ember_dialogue_resource.gd")
const NATIVE_DIR := "res://content/dialogues"


static func document(dialogue_id: String) -> Dictionary:
	var clean := dialogue_id.strip_edges()
	if not _valid_id(clean):
		return {}
	var native := native_document(clean)
	return native if not native.is_empty() else legacy_document(clean)


static func native_document(dialogue_id: String) -> Dictionary:
	var path := native_path(dialogue_id)
	if not FileAccess.file_exists(path):
		return {}
	var resource := ResourceLoader.load(
		path, "", ResourceLoader.CACHE_MODE_IGNORE
	) as EmberDialogueResource
	return resource.to_document() if resource != null else {}


static func legacy_document(dialogue_id: String) -> Dictionary:
	var path := EmberPack.scene_path(dialogue_id)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = EmberPack.parse_json_file(path)
	return (parsed as Dictionary).duplicate(true) if typeof(parsed) == TYPE_DICTIONARY else {}


static func owner(dialogue_id: String) -> String:
	if FileAccess.file_exists(native_path(dialogue_id)):
		return "native"
	if FileAccess.file_exists(EmberPack.scene_path(dialogue_id)):
		return "legacy"
	return ""


static func ids() -> Array[String]:
	var known := {}
	var absolute_native := ProjectSettings.globalize_path(NATIVE_DIR)
	if DirAccess.dir_exists_absolute(absolute_native):
		for filename in DirAccess.get_files_at(absolute_native):
			if filename.get_extension().to_lower() == "tres":
				var dialogue_id := filename.get_basename()
				if _valid_id(dialogue_id):
					known[dialogue_id] = true
	var legacy_dir := EmberPack.pack_root().path_join("scenes")
	if DirAccess.dir_exists_absolute(legacy_dir):
		for filename in DirAccess.get_files_at(legacy_dir):
			if filename.get_extension().to_lower() == "json":
				var dialogue_id := filename.get_basename()
				if _valid_id(dialogue_id):
					known[dialogue_id] = true
	var result: Array[String] = []
	for dialogue_id in known:
		result.append(str(dialogue_id))
	result.sort()
	return result


static func native_path(dialogue_id: String) -> String:
	return NATIVE_DIR.path_join("%s.tres" % dialogue_id.strip_edges())


static func write_native(document_value: Dictionary) -> int:
	var dialogue_id := str(document_value.get("id", "")).strip_edges()
	if not _valid_id(dialogue_id):
		return ERR_INVALID_PARAMETER
	var mkdir_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(NATIVE_DIR)
	)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		return mkdir_error
	var resource := DialogueResource.new() as EmberDialogueResource
	resource.dialogue_id = dialogue_id
	resource.document = document_value.duplicate(true)
	return ResourceSaver.save(resource, native_path(dialogue_id))


static func write_legacy(document_value: Dictionary) -> int:
	var dialogue_id := str(document_value.get("id", "")).strip_edges()
	if not _valid_id(dialogue_id):
		return ERR_INVALID_PARAMETER
	return _write_legacy_text(
		dialogue_id, JSON.stringify(document_value, "  ", false) + "\n"
	)


static func _write_legacy_text(dialogue_id: String, contents: String) -> int:
	var path := EmberPack.scene_path(dialogue_id)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		return mkdir_error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(contents)
	file.flush()
	file.close()
	return OK


static func delete_native(dialogue_id: String) -> int:
	var path := native_path(dialogue_id)
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else OK


static func delete_legacy(dialogue_id: String) -> int:
	var path := EmberPack.scene_path(dialogue_id)
	return DirAccess.remove_absolute(path) if FileAccess.file_exists(path) else OK


static func snapshot(dialogue_id: String) -> Dictionary:
	var legacy_path := EmberPack.scene_path(dialogue_id)
	return {
		"id": dialogue_id,
		"native": native_document(dialogue_id),
		"legacy": legacy_document(dialogue_id),
		"legacy_text": FileAccess.get_file_as_string(legacy_path) if FileAccess.file_exists(legacy_path) else "",
	}


static func restore(snapshot_value: Dictionary) -> int:
	var dialogue_id := str(snapshot_value.get("id", "")).strip_edges()
	if not _valid_id(dialogue_id):
		return ERR_INVALID_PARAMETER
	var native: Dictionary = snapshot_value.get("native", {})
	var legacy: Dictionary = snapshot_value.get("legacy", {})
	var error := delete_native(dialogue_id) if native.is_empty() else write_native(native)
	if error != OK:
		return error
	if legacy.is_empty():
		return delete_legacy(dialogue_id)
	var legacy_text := str(snapshot_value.get("legacy_text", ""))
	return _write_legacy_text(dialogue_id, legacy_text) if not legacy_text.is_empty() else write_legacy(legacy)


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
