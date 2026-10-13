@tool
extends RefCounted
## Transient test input adapter, never a gameplay Resource or save format.
const Units = preload("res://scripts/prototypes/ember_combat_unit_catalog.gd")
const Items = preload("res://scripts/ember_item_catalog.gd")
const ItemStore = preload("res://addons/ember_import/ember_item_store.gd")
const REQUEST_ROOT := "user://ember-library-lab/requests"
const MAX_REQUEST_BYTES := 131072

static func prepare(encounter: EmberEncounterResource, raw: Variant, items: Dictionary = {}, units: Dictionary = {}) -> Dictionary:
	if not raw is Dictionary: return _fail("Настройки теста должны быть объектом.")
	for key in raw:
		if key not in ["party", "inventory"]: return _fail("Неизвестное поле настроек: " + str(key))
	var party: Variant = raw.get("party", {})
	var inventory: Variant = raw.get("inventory", {})
	if not party is Dictionary or not inventory is Dictionary: return _fail("Отряд и сумка должны быть объектами.")
	if items.is_empty(): items = Items.definitions()
	if units.is_empty():
		for unit in Units.resources("hero"): units[unit.unit_id] = unit
	var projections := {}
	for hero_id in party:
		if not hero_id is String or hero_id not in encounter.party_unit_ids or not units.has(hero_id):
			return _fail("Герой не входит в сохранённую встречу: " + str(hero_id))
		var member: Variant = party[hero_id]
		if not member is Dictionary: return _fail("Некорректные настройки героя: " + hero_id)
		for key in member:
			if key not in ["level", "equipment"]: return _fail("Неизвестное поле героя: " + str(key))
		if not _whole(member.get("level"), 1, EmberPartyState.MAX_LEVEL): return _fail("Уровень героя должен быть от 1 до 99: " + hero_id)
		var equipment: Variant = member.get("equipment")
		if not equipment is Dictionary or equipment.size() != EmberEquipment.SLOTS.size(): return _fail("Укажите пять слотов экипировки: " + hero_id)
		for slot in EmberEquipment.SLOTS:
			if not equipment.has(slot): return _fail("Отсутствует слот: " + slot)
			var item_id: Variant = equipment[slot]
			if item_id == null: continue
			if not item_id is String or not items.has(item_id): return _fail("Предмет не найден: " + str(item_id))
			var item: Dictionary = items[item_id]
			if not ItemStore.validation_errors(item).is_empty(): return _fail("Исправьте карточку предмета: " + item_id)
			if slot not in EmberEquipment.slots_for_item(item) or not EmberPartyState.equipment_allowed(item, hero_id):
				return _fail("Предмет не подходит герою или слоту: " + item_id)
		var unit: EmberCombatUnitResource = units[hero_id]
		projections[hero_id] = EmberPartyState.derived_stats_for_unit(unit, member, items)
	var bag := {}
	for item_id in inventory:
		if not item_id is String or not items.has(item_id): return _fail("Расходник не найден: " + str(item_id))
		var item: Dictionary = items[item_id]
		if str(item.get("kind", "")) != "consumable" or not ItemStore.validation_errors(item).is_empty(): return _fail("Выберите корректный расходник: " + item_id)
		if not _whole(inventory[item_id], 1, int(item.get("stackMax", 1))): return _fail("Количество расходника выходит за размер стека: " + item_id)
		bag[item_id] = int(inventory[item_id])
	return {"ok": true, "setup": normalized_input(raw), "derived": projections, "inventory": bag}

static func normalized_input(raw: Dictionary) -> Dictionary:
	# JSON numbers reopen as floats. Canonicalize validated whole values so
	# loaded preferences compare with native controls/Undo as the same input.
	var result := raw.duplicate(true)
	for hero_id in result.get("party", {}):
		result.party[hero_id]["level"] = int(result.party[hero_id].level)
	for item_id in result.get("inventory", {}):
		result.inventory[item_id] = int(result.inventory[item_id])
	return result

static func apply(state: Dictionary, prepared: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	var party: Dictionary = prepared.get("setup", {}).get("party", {})
	for hero_id in party:
		# Full HP/MP and zero XP are test initial state, not campaign progress.
		result.units[hero_id] = EmberPartyState.project_combat_member(result.units[hero_id], party[hero_id], prepared.derived[hero_id])
	return result

static func write_request(path: String, setup: Dictionary) -> Dictionary:
	var folder := ProjectSettings.globalize_path(REQUEST_ROOT)
	if DirAccess.make_dir_recursive_absolute(folder) != OK: return _fail("Не удалось подготовить настройки теста.")
	var file_path := folder.path_join("setup-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()])
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null: return _fail("Не удалось записать настройки теста.")
	file.store_string(JSON.stringify({"version": 1, "encounterPath": path, "setup": setup}))
	file.close()
	return {"ok": true, "path": file_path}

static func read_request(path: String, encounter: EmberEncounterResource, encounter_path: String) -> Dictionary:
	if path.simplify_path() != path or path.get_base_dir() != ProjectSettings.globalize_path(REQUEST_ROOT) or path.get_extension() != "json":
		return _fail("Настройки теста должны находиться в папке запросов Lab.")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _fail("Настройки теста не найдены.")
	if file.get_length() > MAX_REQUEST_BYTES: return _fail("Файл настроек теста слишком велик.")
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK: return _fail("Не удалось прочитать настройки теста.")
	var data: Variant = parser.data
	if not data is Dictionary or data.get("version") != 1 or data.get("encounterPath") != encounter_path:
		return _fail("Настройки относятся к другой встрече или версии.")
	return prepare(encounter, data.get("setup"))

static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
