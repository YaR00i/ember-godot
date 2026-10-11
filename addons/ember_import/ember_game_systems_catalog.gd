@tool
extends RefCounted
## Editor-only, read-only projection. Existing Resources/catalogs remain owners.

const Items = preload("res://scripts/ember_item_catalog.gd")
const Equipment = preload("res://scripts/ember_equipment.gd")
const Statuses = preload("res://scripts/prototypes/ember_combat_status_catalog.gd")
const Effects = preload("res://scripts/prototypes/ember_combat_effect_catalog.gd")
const Actions = preload("res://scripts/prototypes/ember_combat_action_catalog.gd")
const Units = preload("res://scripts/prototypes/ember_combat_unit_catalog.gd")
const Ai = preload("res://scripts/prototypes/ember_combat_ai_profile_catalog.gd")
const Loot = preload("res://scripts/prototypes/ember_combat_loot_table_catalog.gd")
const Encounters = preload("res://scripts/prototypes/ember_encounter_catalog.gd")
const MODULES := [
	["item", "Библиотека предметов", "Все предметы игры: экипировка, расходники, материалы и ключевые предметы. Один источник для сумки, магазинов и лута."],
	["status", "Статусы", "Длительность, повторное наложение, модификаторы урона и условия снятия состояний."],
	["effect", "Эффекты", "Переиспользуемые шаги: статус, лечение, толчок, клетка и перемещение."],
	["action", "Приёмы", "Цель, дальность, стоимость и последовательность эффектов."],
	["unit", "Бойцы", "Герои и враги: характеристики, приёмы, ИИ и награды."],
	["ai", "Поведение ИИ", "Существующие профили выбора боевых команд."],
	["encounter", "Встречи", "Поле, арена, состав участников и результат боя."],
	["field", "Боевые поля", "Клетки, высоты и расстановка; декор арены редактируется отдельно."],
	["loot", "Лут", "Общие таблицы выдачи предметов после боя."],
	["lab", "Лаборатория", "Общая Combat Lab. Сохранённую встречу можно запустить кнопкой проверки в разделе «Встречи»."],
]


static func refresh() -> void:
	for catalog in [Statuses, Effects, Actions, Ai]:
		catalog.refresh()


static func entries(module: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if module in ["item", "equipment"]:
		for id in Items.ids():
			var data := Items.definition(id)
			if module == "equipment" and Equipment.slot_for_item(data).is_empty():
				continue
			result.append({"id": id, "name": data.get("nameRu", id), "description": data.get("notesRu", ""), "path": Items.native_path(id), "data": data, "resource": null})
	elif module == "encounter":
		for id in Encounters.ids():
			result.append(_record(Encounters.definition(id), "encounter_id"))
	elif module == "field":
		var dir := DirAccess.open("res://content/combat/battlefields")
		if dir != null:
			for file in dir.get_files():
				if file.ends_with(".tres"):
					var resource := load("res://content/combat/battlefields/" + file) as EmberBattlefieldResource
					if resource != null: result.append(_record(resource, "field_id"))
	elif module == "lab":
		result.append({"id": "combat_lab", "name": "Боевая лаборатория", "description": "Существующая сцена для проверки боя, расстановки и возврата результата.", "path": "res://scenes/combat_lab.tscn", "data": {}, "resource": null})
	else:
		var catalog: Variant = {"status": Statuses, "effect": Effects, "action": Actions, "unit": Units, "ai": Ai, "loot": Loot}.get(module)
		var id_key := str({"status": "status_id", "effect": "effect_id", "action": "action_id", "unit": "unit_id", "ai": "profile_id", "loot": "table_id"}.get(module, ""))
		if catalog != null:
			for resource in catalog.resources(): result.append(_record(resource, id_key))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return result


static func _record(resource: Resource, id_key: String) -> Dictionary:
	var data: Dictionary = resource.call("to_definition") if resource.has_method("to_definition") else {}
	return {"id": str(resource.get(id_key)), "name": str(resource.get("display_name")), "description": str(data.get("description", data.get("hint", ""))), "path": resource.resource_path, "data": data, "resource": resource}


static func relations(module: String, record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var resource := record.get("resource") as Resource
	if module == "action" and resource != null:
		for effect in resource.get("effect_steps"):
			if effect != null: _link(result, "effect", str(effect.get("effect_id")), "Эффект")
	elif module == "unit" and resource != null:
		for id in resource.get("action_ids"): _link(result, "action", id, "Приём")
		_link(result, "ai", str(resource.get("ai_profile_id")), "ИИ")
		var table := resource.get("loot_table") as Resource
		if table != null: _link(result, "loot", str(table.get("table_id")), "Лут")
	elif module == "effect" and resource != null:
		_link(result, "status", str(resource.get("status_id")), "Статус")
		for key in ["remove_status_ids", "spread_status_ids"]:
			for id in resource.get(key): _link(result, "status", id, "Статус")
	elif module == "encounter" and resource != null:
		for key in ["party_unit_ids", "enemy_unit_ids"]:
			for id in resource.get(key): _link(result, "unit", id, "Участник")
		var field := resource.get("battlefield") as Resource
		if field != null: _link(result, "field", str(field.get("field_id")), "Поле")
	elif module == "loot" and resource != null:
		for entry in resource.get("entries"):
			if entry != null: _link(result, "item", str(entry.get("item_id")), "Предмет")
	elif module in ["item", "equipment"]:
		for table in Loot.resources():
			for entry in table.entries:
				if entry != null and entry.item_id == str(record.id): _link(result, "loot", table.table_id, "Источник лута")
	return result


static func _link(result: Array[Dictionary], module: String, id: String, label: String) -> void:
	if id.is_empty(): return
	var link := {"module": module, "id": id, "label": "%s · %s" % [label, id]}
	if link not in result: result.append(link)

static func incoming(module: String, record: Dictionary) -> Array[String]:
	# Explicit request only: never rescan the project on each text input.
	var result: Array[String] = []
	var target := "item" if module == "equipment" else module
	for info in MODULES:
		if info[0] in ["equipment", "lab"]: continue
		for source in entries(str(info[0])):
			if source.path == record.path: continue
			for relation in relations(str(info[0]), source):
				if relation.module == target and relation.id == record.id:
					var label := "%s · %s" % [info[1], source.name]
					if label not in result: result.append(label)
	var uid := ResourceLoader.get_resource_uid(str(record.path))
	var uid_text := ResourceUID.id_to_text(uid) if uid != ResourceUID.INVALID_ID else ""
	_scan_incoming("res://scenes", record, uid_text, result)
	_scan_incoming("res://scripts", record, uid_text, result)
	_scan_incoming("res://content", record, uid_text, result)
	return result

static func _scan_incoming(folder: String, record: Dictionary, uid: String, result: Array[String]) -> void:
	var dir := DirAccess.open(folder)
	if dir == null: return
	for child in dir.get_directories(): _scan_incoming(folder.path_join(child), record, uid, result)
	for file in dir.get_files():
		var path := folder.path_join(file)
		if path == record.path: continue
		var extension := file.get_extension()
		if extension in ["tscn", "tres", "res"]:
			for dependency in ResourceLoader.get_dependencies(path):
				if str(record.path) in dependency or (not uid.is_empty() and dependency.begins_with(uid)):
					if path not in result: result.append(path)
		if extension in ["gd", "tscn", "tres"]:
			var text := FileAccess.get_file_as_string(path)
			if ('"' + str(record.id) + '"') in text or ("'" + str(record.id) + "'") in text:
				var candidate := "Текстовый ID · " + path
				if candidate not in result: result.append(candidate)
