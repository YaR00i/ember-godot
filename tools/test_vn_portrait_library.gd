extends SceneTree
## Native expression import remains available after catalog reload and never
## mutates the legacy JOI portrait registry.

const VnAssets = preload("res://scripts/ember_vn_assets.gd")
const Pack = preload("res://scripts/ember_pack.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var nonce := str(Time.get_ticks_usec())
	var speaker := "ember_test_speaker_%s" % nonce
	var source_path := "user://ember_native_portrait_%s.svg" % nonce
	var source := FileAccess.open(source_path, FileAccess.WRITE)
	if source == null:
		printerr("FAIL native VN portrait library: could not create source fixture")
		return 1
	source.store_string(
		"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"32\" height=\"48\" viewBox=\"0 0 32 48\">"
		+ "<rect width=\"32\" height=\"48\" fill=\"#c96a88\"/></svg>"
	)
	source.close()
	var legacy_registry := Pack.pack_root().path_join("portraits").path_join("hu_tao").path_join(
		"registry.json"
	)
	var registry_before := FileAccess.get_file_as_string(legacy_registry)
	var assets := VnAssets.new() as EmberVnAssets
	var imported := assets.import_portrait(ProjectSettings.globalize_path(source_path), speaker)
	var asset_path := str(imported.get("assetPath", ""))
	var resource_path := str(imported.get("resourcePath", ""))
	if not bool(imported.get("ok", false)):
		errors.append("native portrait import failed: %s" % imported.get("error", "unknown"))
	else:
		var portrait_key := str(imported.get("portraitKey", ""))
		var reopened := VnAssets.new() as EmberVnAssets
		if speaker not in reopened.speaker_ids():
			errors.append("native portrait speaker did not survive catalog reload")
		if not reopened.has_portrait(speaker, portrait_key):
			errors.append("native portrait expression did not survive catalog reload")
		if reopened.portrait_path(speaker, portrait_key) != ProjectSettings.globalize_path(asset_path):
			errors.append("native portrait path did not resolve through the shared catalog")
		var found_native := false
		for entry in reopened.portrait_entries(speaker):
			if str(entry.get("key", "")) == portrait_key and bool(entry.get("native", false)):
				found_native = true
				break
		if not found_native or not FileAccess.file_exists(resource_path):
			errors.append("native portrait .tres metadata is missing")
	if FileAccess.get_file_as_string(legacy_registry) != registry_before:
		errors.append("native portrait import modified a legacy JOI registry")
	_cleanup_exact(resource_path)
	_cleanup_exact(asset_path)
	_cleanup_exact(source_path)
	if not errors.is_empty():
		printerr("FAIL native VN portrait library")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS native VN portrait library")
	print("  imported expression + .tres reopen without writing legacy JOI JSON")
	return 0


func _cleanup_exact(path: String) -> void:
	if path.is_empty():
		return
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
