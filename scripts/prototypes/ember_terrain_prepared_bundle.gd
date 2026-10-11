@tool
extends RefCounted
## Build-time manifest of existing cache files. Runtime reads the same bytes
## through DerivedDataCache; no authored Resource or alternative payload format.
const Storage = preload("res://scripts/prototypes/ember_derived_data_cache.gd")
const ROOT := "res://build/terrain-prepared"
const VERSION := 1
const MAX_MANIFEST_BYTES := 16 * 1024 * 1024
const MAX_FILES := 65536
const MAX_TOTAL_BYTES := 768 * 1024 * 1024

static func _valid_name(name: String) -> bool:
	var pieces := name.split("/")
	if pieces.size() != 2 or pieces[0] not in ["geometry", "water"]: return false
	var extension := ".edc" if pieces[0] == "geometry" else ".ewc"
	if not pieces[1].ends_with(extension): return false
	var key := pieces[1].trim_suffix(extension)
	if key.length() != 64: return false
	for character in key:
		if character not in "0123456789abcdef": return false
	return true

static func _write_atomic(path: String, bytes: PackedByteArray) -> Error:
	var temporary := path + ".%s-%s.tmp" % [OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_buffer(bytes); file.flush()
	var error := file.get_error(); file.close()
	if error == OK: error = DirAccess.rename_absolute(temporary, path)
	if error != OK: DirAccess.remove_absolute(temporary)
	return error

static func write(root_path: String, inputs: Dictionary, metadata: Dictionary) -> Dictionary:
	if DirAccess.make_dir_recursive_absolute(root_path) != OK: return {"error": "Cannot create bundle directory."}
	var entries := []
	var total := 0
	var names := inputs.keys(); names.sort()
	for name: String in names:
		if not _valid_name(name): return {"error": "Invalid prepared cache name."}
		var bytes := FileAccess.get_file_as_bytes(inputs[name])
		if bytes.size() < Storage.HEADER_BYTES or bytes.size() > 32 * 1024 * 1024: return {"error": "Missing/oversized prepared file: " + name}
		total += bytes.size()
		if total > MAX_TOTAL_BYTES or entries.size() >= MAX_FILES: return {"error": "Bundle exceeds the existing cache budgets."}
		var target := root_path.path_join(name)
		if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK: return {"error": "Cannot create bundle subdirectory."}
		if _write_atomic(target, bytes) != OK: return {"error": "Cannot publish prepared file."}
		entries.append({"name": name, "bytes": bytes.size(), "sha256": Storage.checksum(bytes).hex_encode()})
	var manifest := metadata.duplicate()
	manifest.merge({"version": VERSION, "files": entries, "total_bytes": total}, true)
	var text := JSON.stringify(manifest)
	if text.to_utf8_buffer().size() > MAX_MANIFEST_BYTES: return {"error": "Manifest exceeds its budget."}
	var manifest_path := root_path.path_join("manifest.json")
	if _write_atomic(manifest_path, text.to_utf8_buffer()) != OK: return {"error": "Cannot publish bundle manifest."}
	return inspect(root_path)

static func inspect(root_path: String) -> Dictionary:
	var file := FileAccess.open(root_path.path_join("manifest.json"), FileAccess.READ)
	if file == null or file.get_length() > MAX_MANIFEST_BYTES: return {"error": "Missing/oversized prepared manifest."}
	var manifest: Variant = JSON.parse_string(file.get_as_text()); file.close()
	if not manifest is Dictionary or manifest.get("version") != VERSION or not manifest.get("files") is Array:
		return {"error": "Unsupported prepared manifest."}
	if manifest.files.is_empty() or manifest.files.size() > MAX_FILES: return {"error": "Invalid prepared file count."}
	var files := []
	var seen := {}
	var total := 0
	for entry: Variant in manifest.files:
		if not entry is Dictionary or not entry.get("name") is String or not _valid_name(entry.name) or seen.has(entry.name):
			return {"error": "Invalid/duplicate prepared file name."}
		seen[entry.name] = true
		var path := root_path.path_join(entry.name)
		file = FileAccess.open(path, FileAccess.READ)
		if file == null: return {"error": "Missing prepared file: " + entry.name}
		var size := file.get_length()
		if size < Storage.HEADER_BYTES or size > 32 * 1024 * 1024 or size != entry.get("bytes"): return {"error": "Invalid prepared size: " + entry.name}
		total += size
		if total > MAX_TOTAL_BYTES: return {"error": "Prepared bundle exceeds its budget."}
		var bytes := file.get_buffer(size); file.close()
		if Storage.checksum(bytes).hex_encode() != entry.get("sha256"): return {"error": "Prepared checksum mismatch: " + entry.name}
		files.append({"source": path, "target": Storage.PACKAGED_ROOT.path_join(entry.name)})
	if total != manifest.get("total_bytes"): return {"error": "Invalid prepared total size."}
	return {"error": "", "files": files, "manifest": manifest}
