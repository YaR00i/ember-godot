@tool
extends RefCounted
## Local editor preferences. Gameplay only receives the existing Setup payload.
const Setup = preload("res://scripts/prototypes/ember_combat_lab_setup.gd")
const DEFAULT_PATH := "user://ember-library-lab/presets.json"
const MAX_BYTES := 1048576
const MAX_PRESETS := 256
var path: String
var rename_override: Callable # Focused publication fault injection in fixtures.

func _init(storage_path := DEFAULT_PATH) -> void:
	path = storage_path

func read() -> Dictionary:
	if not _safe_path(): return _fail("Наборы должны храниться в локальной папке редактора.")
	if DirAccess.dir_exists_absolute(path): return _fail("Путь наборов занят папкой.")
	var source := path
	if not FileAccess.file_exists(source):
		if FileAccess.file_exists(path + ".previous"): source = path + ".previous"
		else: return {"ok": true, "records": [], "hash": "", "recovered": false}
	var result := _read_file(source)
	if result.get("ok", false): result["recovered"] = source != path
	return result

func save(encounter: EmberEncounterResource, name: String, setup: Dictionary, expected_hash: String, id := "") -> Dictionary:
	if encounter == null: return _fail("Выберите сохранённую встречу.")
	name = name.strip_edges()
	if not _valid_name(name): return _fail("Укажите название от 1 до 80 символов, в одну строку.")
	var prepared := Setup.prepare(encounter, setup)
	if not prepared.get("ok", false): return prepared
	var current := read()
	if not current.get("ok", false): return current
	if current.hash != expected_hash: return _stale()
	var heroes := roster(encounter)
	var rows: Array = current.records.duplicate(true)
	var index := -1
	for i in rows.size():
		if rows[i].id == id: index = i
		elif rows[i].heroes == heroes and rows[i].name.to_lower() == name.to_lower():
			return _fail("Набор с таким названием уже есть для этого состава. Выберите его и нажмите «Обновить».")
	if not id.is_empty() and (index < 0 or rows[index].heroes != heroes): return _fail("Выбранный набор удалён или относится к другому составу.")
	if id.is_empty():
		if rows.size() >= MAX_PRESETS: return _fail("Слишком много наборов: удалите ненужные.")
		id = Crypto.new().generate_random_bytes(16).hex_encode()
	var record := {"id": id, "name": name, "heroes": heroes, "setup": prepared.setup.duplicate(true)}
	if index < 0: rows.append(record)
	else: rows[index] = record
	var result := _publish(rows, expected_hash)
	if result.get("ok", false): result["id"] = id
	return result

func remove(id: String, expected_hash: String) -> Dictionary:
	var current := read()
	if not current.get("ok", false): return current
	if current.hash != expected_hash: return _stale()
	var rows: Array = current.records.duplicate(true)
	var found := false
	for i in range(rows.size() - 1, -1, -1):
		if rows[i].id == id:
			rows.remove_at(i)
			found = true
	if not found: return _fail("Набор уже удалён. Обновите список.")
	return _publish(rows, expected_hash)

func undo_delete(expected_hash: String) -> Dictionary:
	if not _safe_path(): return _fail("Некорректная папка наборов.")
	var previous := _read_file(path + ".previous")
	if not previous.get("ok", false): return previous
	return _publish(previous.records, expected_hash)

static func roster(encounter: EmberEncounterResource) -> Array:
	var heroes: Array = []
	for id in encounter.party_unit_ids: heroes.append(str(id))
	heroes.sort()
	return heroes

func _read_file(source: String) -> Dictionary:
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null: return _fail("Не удалось прочитать наборы. Исходный файл сохранён.")
	if file.get_length() > MAX_BYTES: return _fail("Файл наборов слишком велик. Исходный файл сохранён.")
	var bytes := file.get_buffer(file.get_length())
	var error := file.get_error()
	file.close()
	if error != OK: return _fail("Не удалось полностью прочитать наборы.")
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK: return _fail("Файл наборов повреждён. Исходный файл сохранён.")
	var data: Variant = parser.data
	if not data is Dictionary or data.size() not in [2, 3] or not Setup._whole(data.get("version"), 1, 1) or not data.get("presets") is Array:
		return _fail("Неподдерживаемый формат наборов. Исходный файл сохранён.")
	if data.size() == 3 and (not data.get("revision") is String or data.revision.length() != 32):
		return _fail("Некорректная версия записи наборов.")
	if data.presets.size() > MAX_PRESETS: return _fail("Слишком много записей наборов.")
	var ids := {}
	var names := {}
	for record in data.presets:
		if not _valid_record(record): return _fail("Некорректная запись набора. Исходный файл сохранён.")
		var key: String = JSON.stringify(record.heroes) + "|" + record.name.to_lower()
		if ids.has(record.id) or names.has(key): return _fail("В файле есть дубли наборов. Исходный файл сохранён.")
		ids[record.id] = true
		names[key] = true
		record["setup"] = Setup.normalized_input(record.setup)
	return {"ok": true, "records": data.presets, "hash": _hash(bytes)}

static func _valid_record(raw: Variant) -> bool:
	if not raw is Dictionary or raw.size() != 4: return false
	if not raw.get("id") is String or raw.id.length() != 32: return false
	for character in raw.id:
		if character not in "0123456789abcdef": return false
	if not raw.get("name") is String or not _valid_name(raw.name): return false
	if not raw.get("heroes") is Array or raw.heroes.is_empty() or raw.heroes.size() > 64: return false
	var sorted: Array = raw.heroes.duplicate()
	for id in sorted:
		if not id is String or id.is_empty(): return false
	sorted.sort()
	if sorted != raw.heroes or sorted.size() != _unique_count(sorted): return false
	# Catalog validity is checked on Save/launch, so missing items remain visible
	# in the setup form and can be corrected instead of being silently dropped.
	if not raw.get("setup") is Dictionary: return false
	for key in raw.setup:
		if key not in ["party", "inventory"] or not raw.setup[key] is Dictionary: return false
	for hero in raw.setup.get("party", {}):
		if hero not in sorted: return false
		var member: Variant = raw.setup.party[hero]
		if not member is Dictionary or member.size() != 2 or not Setup._whole(member.get("level"), 1, EmberPartyState.MAX_LEVEL): return false
		if not member.get("equipment") is Dictionary or member.equipment.size() != EmberEquipment.SLOTS.size(): return false
		for slot in EmberEquipment.SLOTS:
			if not member.equipment.has(slot): return false
			var item: Variant = member.equipment[slot]
			if item != null and (not item is String or item.is_empty()): return false
	for item in raw.setup.get("inventory", {}):
		if not item is String or item.is_empty() or not Setup._whole(raw.setup.inventory[item], 1, 2147483647): return false
	return true

static func _unique_count(values: Array) -> int:
	var ids := {}
	for id in values: ids[id] = true
	return ids.size()

static func _valid_name(value: String) -> bool:
	if value.is_empty() or value.length() > 80 or value != value.strip_edges(): return false
	for character in value:
		if character.unicode_at(0) < 32: return false
	return true

func _publish(records: Array, expected_hash: String) -> Dictionary:
	var current := read()
	if not current.get("ok", false): return current
	if current.hash != expected_hash: return _stale()
	# Even a no-op Save invalidates another window's pending delete-undo,
	# because its .previous backup now belongs to the newer publication.
	var revision := Crypto.new().generate_random_bytes(16).hex_encode()
	var bytes := JSON.stringify({"version": 1, "revision": revision, "presets": records}, "\t").to_utf8_buffer()
	if bytes.size() > MAX_BYTES: return _fail("Наборы не сохранены: превышен размер файла.")
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK: return _fail("Не удалось создать папку наборов.")
	var staged := path + ".%d-%d.tmp" % [OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null: return _fail("Не удалось записать наборы.")
	var stored := file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	var checked := _read_file(staged)
	if not stored or error != OK or not checked.get("ok", false) or checked.get("hash") != _hash(bytes):
		DirAccess.remove_absolute(staged)
		return _fail("Наборы не сохранены: проверка записи не прошла.")
	current = read()
	if not current.get("ok", false) or current.hash != expected_hash:
		DirAccess.remove_absolute(staged)
		return _stale()
	var had_source := FileAccess.file_exists(path)
	var previous := path + ".previous"
	if had_source:
		# Windows rename can remove an existing destination before moving.
		# Preserve the source first; never publish over the only good copy.
		if FileAccess.file_exists(previous): error = DirAccess.remove_absolute(previous)
		if error == OK: error = _rename(path, previous)
	if error == OK: error = _rename(staged, path)
	if error != OK:
		if not FileAccess.file_exists(path) and FileAccess.file_exists(previous): _rename(previous, path)
		if FileAccess.file_exists(staged): DirAccess.remove_absolute(staged)
		return _fail("Не удалось сохранить наборы. Прежняя версия сохранена.")
	return {"ok": true, "hash": checked.hash}

func _rename(from: String, to: String) -> Error:
	return rename_override.call(from, to) if rename_override.is_valid() else DirAccess.rename_absolute(from, to)

func _safe_path() -> bool:
	return path.begins_with("user://") and path.simplify_path() == path and path.get_extension() == "json"

static func _hash(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

static func _stale() -> Dictionary:
	return _fail("Наборы изменились в другом окне. Обновите список; текущие настройки отряда сохранены.")

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
