@tool
extends RefCounted
## Bounded atomic binary transport for disposable derived data. Callers own
## content keys, payload versions and validation. No Resources or live history.
const HEADER_BYTES := 48
const PACKAGED_ROOT := "res://ember-prepared"

var directory := ""
var magic := "EDCACHE1"
var format_version := 1
var extension := ".edc"
var max_bytes := 32 * 1024 * 1024
var packaged_directory := ""
var packaged_for_directory := "" # Isolated test/custom caches never inherit shipped data.
var packaged_hits := 0
var read_us := 0
var write_us := 0
var read_bytes := 0
var written_bytes := 0
var invalid := 0
var failures := 0


static func digest(value: Variant) -> String:
	return checksum(var_to_bytes(value)).hex_encode()


static func checksum(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish()


func path(key: String) -> String:
	return directory.path_join(key + extension)


func read(key: String) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result := _read(key)
	read_us += Time.get_ticks_usec() - started
	return result


func _read(key: String) -> Dictionary:
	var result := _read_file(path(key), key) if not directory.is_empty() else {}
	if not result.is_empty(): return result
	if Engine.is_editor_hint() or directory != packaged_for_directory or packaged_directory.is_empty(): return {}
	result = _read_file(packaged_directory.path_join(key + extension), key)
	if not result.is_empty(): packaged_hits += 1
	return result


func _read_file(file_path: String, key: String) -> Dictionary:
	if not FileAccess.file_exists(file_path): return {}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null: failures += 1; return {}
	var size := file.get_length()
	if size < HEADER_BYTES or size > max_bytes: invalid += 1; return {}
	if file.get_buffer(8).get_string_from_ascii() != magic: invalid += 1; return {}
	var version := file.get_32()
	var raw_size := file.get_32()
	var expected := file.get_buffer(32)
	var compressed := file.get_buffer(size - HEADER_BYTES)
	file.close()
	read_bytes += size
	if version != format_version or raw_size < 1 or raw_size > max_bytes or checksum(compressed) != expected:
		invalid += 1
		return {}
	var raw := compressed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_size: invalid += 1; return {}
	var value: Variant = bytes_to_var(raw) # Object decoding is deliberately disabled.
	if not value is Dictionary or value.get("key") != key: invalid += 1; return {}
	return value


func write(key: String, payload: Dictionary, cancelled: Callable) -> void:
	if directory.is_empty() or cancelled.call(): return
	var started := Time.get_ticks_usec()
	var value := payload.duplicate()
	value.key = key
	var raw := var_to_bytes(value)
	if raw.size() > max_bytes: failures += 1; return
	var compressed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	if compressed.is_empty() or compressed.size() + HEADER_BYTES > max_bytes: failures += 1; return
	if cancelled.call(): return
	if DirAccess.make_dir_recursive_absolute(directory) != OK: failures += 1; return
	var temporary := path(key) + ".%s-%s.tmp" % [OS.get_process_id(), get_instance_id()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: failures += 1; return
	file.store_buffer(magic.to_ascii_buffer())
	file.store_32(format_version)
	file.store_32(raw.size())
	file.store_buffer(checksum(compressed))
	file.store_buffer(compressed)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or cancelled.call():
		DirAccess.remove_absolute(temporary)
		if error != OK: failures += 1
		return
	# The final name becomes visible only after the complete file is closed.
	if DirAccess.rename_absolute(temporary, path(key)) != OK:
		DirAccess.remove_absolute(temporary)
		failures += 1
	else: written_bytes += compressed.size() + HEADER_BYTES
	write_us += Time.get_ticks_usec() - started


func trim(budget_bytes := 256 * 1024 * 1024) -> void:
	if directory.is_empty() or not DirAccess.dir_exists_absolute(directory): return
	var entries: Array[Dictionary] = []
	var total := 0
	for name in DirAccess.get_files_at(directory):
		if not name.ends_with(extension): continue
		var full := directory.path_join(name)
		var file := FileAccess.open(full, FileAccess.READ)
		if file == null: continue
		var size := file.get_length()
		file.close()
		entries.append({"path": full, "size": size, "time": FileAccess.get_modified_time(full)})
		total += size
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	for entry in entries:
		if total <= budget_bytes: break
		if DirAccess.remove_absolute(entry.path) == OK: total -= entry.size
