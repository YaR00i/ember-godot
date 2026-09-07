extends SceneTree
## Native background import owns new authoring data as Godot Resources while
## retaining the JOI JSON registry as a read-only compatibility source.

const VnAssets = preload("res://scripts/ember_vn_assets.gd")
const Pack = preload("res://scripts/ember_pack.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var nonce := str(Time.get_ticks_usec())
	var source_path := "user://ember_native_background_test_%s.svg" % nonce
	var source := FileAccess.open(source_path, FileAccess.WRITE)
	if source == null:
		printerr("FAIL native VN background library: could not create source fixture")
		return 1
	source.store_string(
		"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"64\" height=\"36\" viewBox=\"0 0 64 36\">"
		+ "<rect width=\"64\" height=\"36\" fill=\"#332255\"/></svg>"
	)
	source.close()
	var registry_path := Pack.pack_root().path_join("arts").path_join("registry.json")
	var registry_before := FileAccess.get_file_as_string(registry_path)
	var assets := VnAssets.new() as EmberVnAssets
	var imported := assets.import_background(ProjectSettings.globalize_path(source_path))
	var asset_path := str(imported.get("assetPath", ""))
	var resource_path := str(imported.get("resourcePath", ""))
	if not bool(imported.get("ok", false)):
		errors.append("native background import failed: %s" % imported.get("error", "unknown"))
	else:
		var art_id := str(imported.get("id", ""))
		if art_id.is_empty() or not FileAccess.file_exists(asset_path):
			errors.append("native background import did not copy the image into res://assets")
		if not FileAccess.file_exists(resource_path):
			errors.append("native background import did not create a .tres descriptor")
		var reopened := VnAssets.new() as EmberVnAssets
		var found_entry: Dictionary = {}
		for entry in reopened.art_entries():
			if str(entry.get("id", "")) == art_id:
				found_entry = entry
				break
		if found_entry.is_empty() or not bool(found_entry.get("native", false)):
			errors.append("native .tres background did not survive catalog reload")
		if reopened.art_path(art_id) != ProjectSettings.globalize_path(asset_path):
			errors.append("native background path did not resolve through the shared catalog")
	if FileAccess.get_file_as_string(registry_path) != registry_before:
		errors.append("native import modified the legacy JOI arts/registry.json")
	_cleanup_exact(resource_path)
	_cleanup_exact(asset_path)
	_cleanup_exact(source_path)
	if not errors.is_empty():
		printerr("FAIL native VN background library")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS native VN background library")
	print("  imported image + .tres reopen without writing legacy JOI JSON")
	return 0


func _cleanup_exact(path: String) -> void:
	if path.is_empty():
		return
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
