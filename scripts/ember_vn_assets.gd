class_name EmberVnAssets
extends RefCounted
## Shared VN asset catalog. New backgrounds are Godot Resources; the existing
## JOI art registry and portrait registries remain read-only compatibility input.

const Pack = preload("res://scripts/ember_pack.gd")
const NativeBackground = preload("res://scripts/ember_vn_background.gd")
const NativePortrait = preload("res://scripts/ember_vn_portrait.gd")

const NATIVE_BACKGROUND_DIR := "res://content/vn_backgrounds"
const NATIVE_BACKGROUND_ASSET_DIR := "res://assets/vn_backgrounds"
const NATIVE_PORTRAIT_DIR := "res://content/vn_portraits"
const NATIVE_PORTRAIT_ASSET_DIR := "res://assets/vn_portraits"
const SUPPORTED_BACKGROUND_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp", "svg"]

var _arts: Dictionary = {}
var _portraits: Dictionary = {}
var _native_portraits: Dictionary = {}
var _textures: Dictionary = {}
var _images: Dictionary = {}


func _init() -> void:
	reload()


func reload() -> void:
	_arts.clear()
	_portraits.clear()
	_native_portraits.clear()
	_textures.clear()
	_images.clear()
	_load_native_backgrounds()
	_load_native_portraits()
	var raw: Variant = Pack.parse_json_file(Pack.pack_root().path_join("arts").path_join("registry.json"))
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var entries: Variant = (raw as Dictionary).get("arts", [])
	if typeof(entries) != TYPE_ARRAY:
		return
	for value in entries:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = value
		var art_id := str(entry.get("id", "")).strip_edges()
		var path := str(entry.get("path", "")).strip_edges()
		# Native .tres entries are the writable Godot owner. Legacy JOI JSON is
		# read-only compatibility input and cannot overwrite a migrated ID.
		if not art_id.is_empty() and not path.is_empty() and not _arts.has(art_id):
			_arts[art_id] = entry.duplicate(true)


func art_path(art_id: String) -> String:
	var entry: Variant = _arts.get(art_id, {})
	return _entry_path(entry as Dictionary) if typeof(entry) == TYPE_DICTIONARY else ""


func native_background_directory() -> String:
	return NATIVE_BACKGROUND_ASSET_DIR


func native_portrait_directory() -> String:
	return NATIVE_PORTRAIT_ASSET_DIR


func import_background(source_path: String) -> Dictionary:
	var source := source_path.strip_edges().replace("\\", "/")
	if not FileAccess.file_exists(source):
		return {"ok": false, "error": "Файл не найден: %s" % source}
	var extension := source.get_extension().to_lower()
	if extension not in SUPPORTED_BACKGROUND_EXTENSIONS:
		return {"ok": false, "error": "Поддерживаются PNG, JPG, WebP и SVG"}
	if extension == "svg":
		var svg_error := _validate_svg(source)
		if not svg_error.is_empty():
			return {"ok": false, "error": svg_error}
	else:
		var probe := Image.load_from_file(source)
		if probe == null or probe.is_empty():
			return {"ok": false, "error": "Godot не смог прочитать изображение"}
	var base_id := _safe_asset_id(source.get_file().get_basename())
	if base_id.is_empty():
		base_id = "background_%d" % Time.get_unix_time_from_system()
	var art_id := _unique_background_id(base_id)
	var asset_path := NATIVE_BACKGROUND_ASSET_DIR.path_join("%s.%s" % [art_id, extension])
	var resource_path := NATIVE_BACKGROUND_DIR.path_join("%s.tres" % art_id)
	for directory in [NATIVE_BACKGROUND_ASSET_DIR, NATIVE_BACKGROUND_DIR]:
		var mkdir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
			return {"ok": false, "error": "Не удалось создать %s" % directory}
	var copy_error := DirAccess.copy_absolute(source, ProjectSettings.globalize_path(asset_path))
	if copy_error != OK:
		return {"ok": false, "error": "Не удалось скопировать изображение (%s)" % copy_error}
	var background := NativeBackground.new() as EmberVnBackground
	background.id = art_id
	background.display_name = source.get_file().get_basename().replace("_", " ")
	background.image_path = asset_path
	background.kind = "cg"
	var save_error := ResourceSaver.save(background, resource_path)
	if save_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(asset_path))
		return {"ok": false, "error": "Не удалось сохранить Resource (%s)" % save_error}
	reload()
	return {
		"ok": true,
		"id": art_id,
		"assetPath": asset_path,
		"resourcePath": resource_path,
	}


func import_portrait(source_path: String, speaker_id: String) -> Dictionary:
	var source := source_path.strip_edges().replace("\\", "/")
	var speaker := _safe_asset_id(speaker_id)
	if speaker.is_empty():
		return {"ok": false, "error": "Сначала выберите персонажа"}
	if not FileAccess.file_exists(source):
		return {"ok": false, "error": "Файл не найден: %s" % source}
	var extension := source.get_extension().to_lower()
	if extension not in SUPPORTED_BACKGROUND_EXTENSIONS:
		return {"ok": false, "error": "Поддерживаются PNG, JPG, WebP и SVG"}
	if extension == "svg":
		var svg_error := _validate_svg(source)
		if not svg_error.is_empty():
			return {"ok": false, "error": svg_error}
	else:
		var probe := Image.load_from_file(source)
		if probe == null or probe.is_empty():
			return {"ok": false, "error": "Godot не смог прочитать изображение"}
	var base_key := _safe_asset_id(source.get_file().get_basename())
	if base_key.is_empty():
		base_key = "expression_%d" % Time.get_unix_time_from_system()
	var portrait_key := _unique_portrait_key(speaker, base_key)
	var asset_dir := NATIVE_PORTRAIT_ASSET_DIR.path_join(speaker)
	var asset_path := asset_dir.path_join("%s.%s" % [portrait_key, extension])
	var resource_path := NATIVE_PORTRAIT_DIR.path_join("%s__%s.tres" % [speaker, portrait_key])
	for directory in [asset_dir, NATIVE_PORTRAIT_DIR]:
		var mkdir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
			return {"ok": false, "error": "Не удалось создать %s" % directory}
	var copy_error := DirAccess.copy_absolute(source, ProjectSettings.globalize_path(asset_path))
	if copy_error != OK:
		return {"ok": false, "error": "Не удалось скопировать портрет (%s)" % copy_error}
	var portrait := NativePortrait.new() as EmberVnPortrait
	portrait.speaker_id = speaker
	portrait.portrait_key = portrait_key
	portrait.display_name = source.get_file().get_basename().replace("_", " ")
	portrait.image_path = asset_path
	var save_error := ResourceSaver.save(portrait, resource_path)
	if save_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(asset_path))
		return {"ok": false, "error": "Не удалось сохранить Resource (%s)" % save_error}
	reload()
	return {
		"ok": true,
		"speakerId": speaker,
		"portraitKey": portrait_key,
		"assetPath": asset_path,
		"resourcePath": resource_path,
	}


func art_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for art_id in _arts:
		var entry: Dictionary = (_arts[art_id] as Dictionary).duplicate(true)
		entry["exists"] = FileAccess.file_exists(art_path(str(art_id)))
		result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("captionRu", a.get("id", ""))).naturalnocasecmp_to(
			str(b.get("captionRu", b.get("id", "")))
		) < 0
	)
	return result


func speaker_ids() -> Array[String]:
	var known := {}
	for speaker in _native_portraits:
		known[str(speaker)] = true
	var root := Pack.pack_root().path_join("portraits")
	if DirAccess.dir_exists_absolute(root):
		for speaker in DirAccess.get_directories_at(root):
			if FileAccess.file_exists(root.path_join(speaker).path_join("registry.json")):
				known[speaker] = true
	var result: Array[String] = []
	for speaker in known:
		result.append(str(speaker))
	result.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return result


func portrait_entries(speaker: String) -> Array[Dictionary]:
	var by_key := {}
	var native: Variant = _native_portraits.get(speaker, {})
	if typeof(native) == TYPE_DICTIONARY:
		for portrait_key in native:
			by_key[str(portrait_key)] = (native[portrait_key] as Dictionary).duplicate(true)
	var registry := _portrait_registry(speaker)
	var expressions: Variant = registry.get("expressions", {})
	if typeof(expressions) == TYPE_DICTIONARY:
		for portrait_key in expressions:
			if by_key.has(str(portrait_key)):
				continue
			var raw: Variant = (expressions as Dictionary)[portrait_key]
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = (raw as Dictionary).duplicate(true)
			entry["key"] = str(portrait_key)
			entry["exists"] = FileAccess.file_exists(
				_absolute_path(str(entry.get("path", "")))
			)
			by_key[str(portrait_key)] = entry
	var result: Array[Dictionary] = []
	for portrait_key in by_key:
		var entry: Dictionary = (by_key[portrait_key] as Dictionary).duplicate(true)
		entry["exists"] = FileAccess.file_exists(_entry_path(entry))
		result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("labelRu", a.get("key", ""))).naturalnocasecmp_to(
			str(b.get("labelRu", b.get("key", "")))
		) < 0
	)
	return result


func first_portrait_key(speaker: String) -> String:
	var entries := portrait_entries(speaker)
	if entries.is_empty():
		return "neutral"
	return str(entries[0].get("key", "neutral"))


func has_portrait(speaker: String, portrait_key: String) -> bool:
	for entry in portrait_entries(speaker):
		if str(entry.get("key", "")) == portrait_key:
			return true
	return false


func portrait_path(speaker: String, portrait_key: String) -> String:
	var native: Variant = _native_portraits.get(speaker, {})
	if typeof(native) == TYPE_DICTIONARY:
		var native_entry: Variant = (native as Dictionary).get(portrait_key, {})
		if typeof(native_entry) == TYPE_DICTIONARY and not (native_entry as Dictionary).is_empty():
			var native_path := _entry_path(native_entry as Dictionary)
			if not native_path.is_empty():
				return native_path
	var registry := _portrait_registry(speaker)
	var expressions: Variant = registry.get("expressions", {})
	if typeof(expressions) != TYPE_DICTIONARY:
		return ""
	var raw: Variant = (expressions as Dictionary).get(portrait_key, {})
	if typeof(raw) != TYPE_DICTIONARY:
		return ""
	return _absolute_path(str((raw as Dictionary).get("path", "")))


func texture_for_path(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	# Dummy/headless rendering has no preview surface; path resolution remains testable.
	if DisplayServer.get_name() == "headless":
		return null
	if _textures.has(path) and is_instance_valid(_textures[path]):
		return _textures[path] as Texture2D
	var image := _image_for_path(path)
	if image == null or image.is_empty():
		return null
	var texture := ImageTexture.create_from_image(image)
	_textures[path] = texture
	return texture


func art_texture(art_id: String) -> Texture2D:
	return texture_for_path(art_path(art_id))


func portrait_texture(speaker: String, portrait_key: String) -> Texture2D:
	return texture_for_path(portrait_path(speaker, portrait_key))


func art_thumbnail(art_id: String, max_size := 48) -> Texture2D:
	return _thumbnail_for_path(art_path(art_id), max_size)


func portrait_thumbnail(speaker: String, portrait_key: String, max_size := 48) -> Texture2D:
	return _thumbnail_for_path(portrait_path(speaker, portrait_key), max_size)


func _load_native_backgrounds() -> void:
	var absolute_dir := ProjectSettings.globalize_path(NATIVE_BACKGROUND_DIR)
	if not DirAccess.dir_exists_absolute(absolute_dir):
		return
	for filename in DirAccess.get_files_at(absolute_dir):
		if filename.get_extension().to_lower() != "tres":
			continue
		var resource_path := NATIVE_BACKGROUND_DIR.path_join(filename)
		var background := ResourceLoader.load(resource_path) as EmberVnBackground
		if background == null or background.normalized_id().is_empty() or background.image_path.is_empty():
			continue
		var art_id := background.normalized_id()
		_arts[art_id] = {
			"id": art_id,
			"path": background.image_path,
			"kind": background.kind,
			"captionRu": background.caption(),
			"tags": Array(background.tags),
			"native": true,
			"resourcePath": resource_path,
		}


func _load_native_portraits() -> void:
	var absolute_dir := ProjectSettings.globalize_path(NATIVE_PORTRAIT_DIR)
	if not DirAccess.dir_exists_absolute(absolute_dir):
		return
	for filename in DirAccess.get_files_at(absolute_dir):
		if filename.get_extension().to_lower() != "tres":
			continue
		var resource_path := NATIVE_PORTRAIT_DIR.path_join(filename)
		var portrait := ResourceLoader.load(resource_path) as EmberVnPortrait
		if portrait == null:
			continue
		var speaker := portrait.normalized_speaker_id()
		var portrait_key := portrait.normalized_portrait_key()
		if speaker.is_empty() or portrait_key.is_empty() or portrait.image_path.is_empty():
			continue
		if not _native_portraits.has(speaker):
			_native_portraits[speaker] = {}
		(_native_portraits[speaker] as Dictionary)[portrait_key] = {
			"key": portrait_key,
			"labelRu": portrait.caption(),
			"path": portrait.image_path,
			"tags": Array(portrait.tags),
			"native": true,
			"resourcePath": resource_path,
		}


func _entry_path(entry: Dictionary) -> String:
	var raw := str(entry.get("path", "")).strip_edges().replace("\\", "/")
	if raw.begins_with("res://") or raw.begins_with("user://"):
		return ProjectSettings.globalize_path(raw)
	if raw.is_absolute_path():
		return raw
	return _absolute_path(raw)


func _safe_asset_id(raw: String) -> String:
	var output := ""
	var pending_separator := false
	for index in raw.length():
		var code := raw.unicode_at(index)
		var allowed := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		if allowed:
			if pending_separator and not output.is_empty():
				output += "_"
			pending_separator = false
			output += String.chr(code).to_lower()
		else:
			pending_separator = true
	return output.trim_suffix("_")


func _unique_background_id(base_id: String) -> String:
	var candidate := base_id
	var suffix := 2
	while _arts.has(candidate) or FileAccess.file_exists(
		NATIVE_BACKGROUND_DIR.path_join("%s.tres" % candidate)
	):
		candidate = "%s_%d" % [base_id, suffix]
		suffix += 1
	return candidate


func _unique_portrait_key(speaker: String, base_key: String) -> String:
	var candidate := base_key
	var suffix := 2
	while has_portrait(speaker, candidate) or FileAccess.file_exists(
		NATIVE_PORTRAIT_DIR.path_join("%s__%s.tres" % [speaker, candidate])
	):
		candidate = "%s_%d" % [base_key, suffix]
		suffix += 1
	return candidate


func _validate_svg(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return "SVG пуст или недоступен"
	for value in bytes:
		if value < 32 and value not in [9, 10, 13]:
			return "SVG содержит управляющие байты; пересохрани его как UTF-8"
	var text := bytes.get_string_from_utf8()
	if text.contains(String.chr(0xFFFD)):
		return "SVG содержит повреждённый UTF-8"
	var parser := XMLParser.new()
	var open_error := parser.open_buffer(bytes)
	if open_error != OK:
		return "SVG не является корректным XML (%s)" % open_error
	return ""


func _portrait_registry(speaker: String) -> Dictionary:
	var clean := speaker.strip_edges()
	if clean.is_empty():
		return {}
	if _portraits.has(clean):
		return _portraits[clean]
	var path := Pack.pack_root().path_join("portraits").path_join(clean).path_join("registry.json")
	if not FileAccess.file_exists(path):
		_portraits[clean] = {}
		return {}
	var raw: Variant = Pack.parse_json_file(path)
	var registry: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	_portraits[clean] = registry
	return registry


func _thumbnail_for_path(path: String, max_size: int) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path) or DisplayServer.get_name() == "headless":
		return null
	var key := "thumb:%d:%s" % [max_size, path]
	if _textures.has(key) and is_instance_valid(_textures[key]):
		return _textures[key] as Texture2D
	var image := _image_for_path(path)
	if image == null or image.is_empty():
		return null
	var longest := maxi(image.get_width(), image.get_height())
	if longest > max_size:
		var ratio := float(max_size) / float(longest)
		image.resize(
			maxi(1, roundi(image.get_width() * ratio)),
			maxi(1, roundi(image.get_height() * ratio)),
			Image.INTERPOLATE_LANCZOS,
		)
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


func _image_for_path(path: String) -> Image:
	if _images.has(path):
		var cached := _images[path] as Image
		return cached.duplicate() as Image if cached != null else null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	_images[path] = image
	return image.duplicate() as Image


func _absolute_path(relative_path: String) -> String:
	var clean := relative_path.strip_edges().replace("\\", "/")
	if clean.is_empty():
		return ""
	return Pack.pack_root().path_join(clean)
