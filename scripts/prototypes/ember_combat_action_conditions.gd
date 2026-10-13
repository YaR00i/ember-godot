extends RefCounted
## Stateless application predicates; ActionResource owns data, Combat owns timing.
const StatusRules = preload("res://scripts/prototypes/ember_combat_status_rules.gd")
const Items = preload("res://scripts/ember_item_catalog.gd")
const Equipment = preload("res://scripts/ember_equipment.gd")
const STATUS_FIELDS := ["actor_required_status_ids", "actor_forbidden_status_ids", "target_required_status_ids", "target_forbidden_status_ids"]
const VALUE_FIELD := "value_conditions"
const EQUIPMENT_FIELD := "equipment_conditions"
const FIELDS := STATUS_FIELDS + [VALUE_FIELD, EQUIPMENT_FIELD]
const EQUIPMENT_MODES := {"item": "Надет предмет", "occupied": "Слот занят", "empty": "Слот пуст"}
const MAX_POINTS := 1000000
const SUBJECT_LABELS := {"actor": "Исполнитель", "target": "Цель"}
const STAT_LABELS := {"hp": "HP", "mp": "MP"}
const COMPARISON_LABELS := {"gte": "≥", "lte": "≤"}
const UNIT_LABELS := {"points": "очков", "percent": "% максимума"}
const LABELS := {"actor_required_status_ids": "Исполнитель должен иметь", "actor_forbidden_status_ids": "Исполнитель не должен иметь", "target_required_status_ids": "Цель должна иметь", "target_forbidden_status_ids": "Цель не должна иметь"}

static func validation_errors(raw: Variant, target_mode: String, check_item_settings := true) -> Array[String]:
	var errors: Array[String] = []
	if not raw is Dictionary: return ["Условия применения должны быть словарём."]
	var known := PackedStringArray()
	for key in STATUS_FIELDS:
		var values: Variant = raw.get(key, PackedStringArray())
		if typeof(values) not in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
			errors.append(LABELS[key] + ": нужен список статусов.")
			continue
		var seen := {}
		if not values.is_empty() and known.is_empty(): known = StatusRules.StatusCatalog.ids()
		for id in values:
			if not id is String or id not in known:
				errors.append(LABELS[key] + ": неизвестный статус «%s»." % str(id))
			if seen.has(id): errors.append(LABELS[key] + ": статус повторяется «%s»." % str(id))
			seen[id] = true
	var values: Variant = raw.get(VALUE_FIELD, [])
	if not values is Array: errors.append("Условия HP/MP должны быть списком.")
	else:
		var seen: Array = []
		var bounds := {}
		for index in values.size():
			var row: Variant = values[index]
			var row_errors := value_errors(row)
			for error in row_errors: errors.append("Условие HP/MP %d: %s" % [index + 1, error])
			if not row_errors.is_empty(): continue
			if row in seen: errors.append("Условие HP/MP повторяется: " + value_summary(row))
			seen.append(row)
			if target_mode == "cell" and row.subject == "target": errors.append("Для цели-клетки условия HP/MP доступны только исполнителю.")
			var key: String = ("self" if target_mode == "self" else row.subject) + ":" + row.stat + ":" + row.unit
			var limits: Vector2i = bounds.get(key, Vector2i(0, 100 if row.unit == "percent" else MAX_POINTS))
			if row.comparison == "gte": limits.x = maxi(limits.x, row.value)
			else: limits.y = mini(limits.y, row.value)
			bounds[key] = limits
			if limits.x > limits.y: errors.append("Противоречащие пороги HP/MP: " + value_summary(row))
	errors.append_array(_equipment_validation(raw.get(EQUIPMENT_FIELD, []), target_mode, check_item_settings))
	if not errors.is_empty(): return errors
	for subject in ["actor", "target"]:
		for id in raw.get(subject + "_required_status_ids", []):
			if id in raw.get(subject + "_forbidden_status_ids", []):
				errors.append("%s: статус «%s» одновременно необходим и запрещён." % ["Исполнитель" if subject == "actor" else "Цель", StatusRules.display_name(id)])
	if target_mode == "cell" and (not raw.get("target_required_status_ids", []).is_empty() or not raw.get("target_forbidden_status_ids", []).is_empty()):
		errors.append("Условия статусов цели требуют бойца; для цели-клетки задайте условия исполнителя.")
	if target_mode == "self":
		for pair in [["actor_required_status_ids", "target_forbidden_status_ids"], ["target_required_status_ids", "actor_forbidden_status_ids"]]:
			for id in raw.get(pair[0], []):
				if id in raw.get(pair[1], []): errors.append("Для приёма на себя статус «%s» одновременно необходим и запрещён." % StatusRules.display_name(id))
	return errors

static func value_errors(raw: Variant) -> Array[String]:
	if not raw is Dictionary: return ["нужна запись условия."]
	for key in ["subject", "stat", "comparison", "unit", "value"]:
		if not raw.has(key): return ["отсутствует поле «%s»." % key]
	if raw.size() != 5: return ["неизвестные поля условия."]
	for pair in [["subject", SUBJECT_LABELS], ["stat", STAT_LABELS], ["comparison", COMPARISON_LABELS], ["unit", UNIT_LABELS]]:
		if not raw[pair[0]] is String or not pair[1].has(raw[pair[0]]): return ["неизвестное значение «%s»." % pair[0]]
	if typeof(raw.value) != TYPE_INT or raw.value < 0: return ["порог должен быть неотрицательным целым числом."]
	if raw.value > (100 if raw.unit == "percent" else MAX_POINTS): return ["порог превышает %d." % (100 if raw.unit == "percent" else MAX_POINTS)]
	return []

static func value_summary(row: Dictionary) -> String:
	return "%s: %s %s %d %s" % [SUBJECT_LABELS[row.subject], STAT_LABELS[row.stat], COMPARISON_LABELS[row.comparison], row.value, UNIT_LABELS[row.unit]]

static func equipment_shape_errors(raw: Variant) -> Array[String]:
	if not raw is Dictionary: return ["нужна запись условия экипировки."]
	for key in ["subject", "slot", "mode", "item_id"]:
		if not raw.has(key) or not raw[key] is String: return ["нужно строковое поле «%s»." % key]
	if raw.size() != 4: return ["неизвестные поля условия экипировки."]
	if not SUBJECT_LABELS.has(raw.subject) or not EQUIPMENT_MODES.has(raw.mode): return ["неизвестный участник или вид условия экипировки."]
	if raw.slot not in Equipment.SLOTS and not (raw.mode == "item" and raw.slot.is_empty()): return ["выберите один из пяти слотов; любой слот доступен только для предмета."]
	if raw.mode == "item" and (raw.item_id.is_empty() or raw.item_id != raw.item_id.strip_edges()): return ["выберите надетый предмет."]
	if raw.mode != "item" and not raw.item_id.is_empty(): return ["условие занятости слота не должно содержать предмет."]
	return []

static func _equipment_validation(raw: Variant, target_mode: String, check_item_settings: bool) -> Array[String]:
	var errors: Array[String] = []
	if not raw is Array: return ["Условия экипировки должны быть списком."]
	var seen: Array = []
	var items := {}
	var known: Array = []
	var known_loaded := false
	var slots := {}
	var any_items := {}
	for index in raw.size():
		var row: Variant = raw[index]
		var row_errors := equipment_shape_errors(row)
		for error in row_errors: errors.append("Условие экипировки %d: %s" % [index + 1, error])
		if not row_errors.is_empty(): continue
		if row in seen: errors.append("Условие экипировки повторяется.")
		seen.append(row)
		if target_mode == "cell" and row.subject == "target": errors.append("Для цели-клетки условия экипировки доступны только исполнителю.")
		var allowed: Array = Equipment.SLOTS
		if row.mode == "item":
			if not known_loaded:
				known = Items.native_ids()
				known_loaded = true
			if row.item_id not in known:
				errors.append("Не найден предмет «%s»." % row.item_id)
				continue
			if check_item_settings:
				if not items.has(row.item_id): items[row.item_id] = Items.definition(row.item_id)
				allowed = Equipment.slots_for_item(items[row.item_id])
				if allowed.is_empty() or (not row.slot.is_empty() and row.slot not in allowed):
					errors.append("Предмет «%s» нельзя надеть в выбранный слот." % row.item_id)
					continue
		var subject: String = "self" if target_mode == "self" else row.subject
		if not slots.has(subject): slots[subject] = {}
		if row.slot.is_empty():
			if not any_items.has(subject): any_items[subject] = {}
			any_items[subject][row.item_id] = allowed
			continue
		var constraint: Dictionary = slots[subject].get(row.slot, {})
		if (row.mode == "empty" and not constraint.is_empty() and not constraint.has("empty")) or (row.mode != "empty" and constraint.has("empty")):
			errors.append("Слот «%s» одновременно должен быть пустым и занятым." % Equipment.SLOT_LABELS[row.slot])
		if row.mode == "item" and constraint.has("item") and constraint.item != row.item_id:
			errors.append("В слоте «%s» требуются два разных предмета." % Equipment.SLOT_LABELS[row.slot])
		constraint[row.mode] = row.item_id
		slots[subject][row.slot] = constraint
	if not errors.is_empty(): return errors
	for subject in any_items:
		var required := {}
		for id in any_items[subject]:
			var candidates: Array[String] = []
			var fixed := false
			for slot in any_items[subject][id]:
				var constraint: Dictionary = slots[subject].get(slot, {})
				if constraint.get("item", "") == id: fixed = true
				if not constraint.has("empty") and (not constraint.has("item") or constraint.item == id): candidates.append(slot)
			if not fixed: required[id] = candidates
		if not _equipment_slots_fit(required, required.keys(), 0, []): errors.append("Требуемые предметы не помещаются в доступные слоты экипировки.")
	return errors

static func _equipment_slots_fit(required: Dictionary, ids: Array, index: int, used: Array) -> bool:
	if index == ids.size(): return true
	# Only five canonical slots; bounded matching also catches two weapons in any slot.
	if ids.size() - index > Equipment.SLOTS.size() - used.size(): return false
	for slot in required[ids[index]]:
		if slot in used: continue
		used.append(slot)
		if _equipment_slots_fit(required, ids, index + 1, used): return true
		used.pop_back()
	return false

static func equipment_summary(row: Dictionary) -> String:
	var slot: String = Equipment.SLOT_LABELS.get(row.slot, "Любой подходящий слот")
	var result := "%s · %s: %s" % [SUBJECT_LABELS[row.subject], slot, EQUIPMENT_MODES[row.mode]]
	if row.mode == "item":
		var item := Items.definition(row.item_id)
		result += " «%s»" % str(item.get("nameRu", item.get("name", row.item_id)))
	return result

static func has_conditions(raw: Dictionary) -> bool:
	for key in FIELDS:
		if not raw.get(key, []).is_empty(): return true
	return false

static func unit_reason(unit: Dictionary, rules: Dictionary, subject: String) -> String:
	var required: Variant = rules.get(subject + "_required_status_ids", [])
	var forbidden: Variant = rules.get(subject + "_forbidden_status_ids", [])
	var values: Array = rules.get(VALUE_FIELD, [])
	var gear: Array = rules.get(EQUIPMENT_FIELD, [])
	var has_values := false
	for row in values:
		if row.subject == subject: has_values = true
	for row in gear:
		if row.subject == subject: has_values = true
	if required.is_empty() and forbidden.is_empty() and not has_values: return ""
	var name := "Исполнитель" if subject == "actor" else "Цель"
	if unit.is_empty(): return name + ": выберите бойца для проверки условий."
	for id in required:
		if not StatusRules.has(unit, id): return "%s «%s»: нужен статус «%s»." % [name, str(unit.get("name", "")), StatusRules.display_name(id)]
	for id in forbidden:
		if StatusRules.has(unit, id): return "%s «%s»: запрещён статус «%s»." % [name, str(unit.get("name", "")), StatusRules.display_name(id)]
	for row in values:
		if row.subject != subject: continue
		var current: Variant = unit.get(row.stat)
		var maximum: Variant = unit.get("maxHp" if row.stat == "hp" else "maxMp")
		if typeof(current) != TYPE_INT or current < 0: return name + ": некорректное значение " + STAT_LABELS[row.stat] + "."
		var left: int = current
		var right: int = row.value
		if row.unit == "percent":
			if typeof(maximum) != TYPE_INT or maximum <= 0: return name + ": максимум " + STAT_LABELS[row.stat] + " равен нулю или некорректен; задайте условие в очках."
			# Exact cross-products, without rounded percentages or division by zero.
			left *= 100
			right *= maximum
		if (left < right if row.comparison == "gte" else left > right):
			return "%s «%s»: требуется %s, сейчас %d/%d." % [name, str(unit.get("name", "")), value_summary(row), current, int(maximum)]
	if gear.is_empty(): return ""
	var equipment: Variant = unit.get("equipment", {})
	for row in gear:
		if row.subject != subject: continue
		if not equipment is Dictionary: return name + ": некорректная экипировка."
		var candidates: Array = Equipment.SLOTS if row.slot.is_empty() else [row.slot]
		var fulfilled := false
		for slot in candidates:
			var id: Variant = equipment.get(slot)
			if id != null and not id is String: return name + ": некорректный предмет в слоте «%s»." % Equipment.SLOT_LABELS[slot]
			var occupied: bool = id != null and not id.strip_edges().is_empty()
			if row.mode == "empty": fulfilled = not occupied
			elif row.mode == "occupied": fulfilled = occupied
			elif id == row.item_id:
				fulfilled = slot in Equipment.slots_for_item(Items.definition(row.item_id))
			if fulfilled: break
		if not fulfilled: return "%s «%s»: требуется %s." % [name, str(unit.get("name", "")), equipment_summary(row)]
	return ""

static func summary(rules: Dictionary) -> String:
	var lines := PackedStringArray()
	for key in STATUS_FIELDS:
		var names := PackedStringArray()
		for id in rules.get(key, []): names.append(StatusRules.display_name(id))
		if not names.is_empty(): lines.append("%s: %s." % [LABELS[key], ", ".join(names)])
	for row in rules.get(VALUE_FIELD, []):
		lines.append(value_summary(row) + "." if value_errors(row).is_empty() else "Некорректное условие HP/MP: " + str(row))
	for row in rules.get(EQUIPMENT_FIELD, []):
		lines.append(equipment_summary(row) + "." if equipment_shape_errors(row).is_empty() else "Некорректное условие экипировки: " + str(row))
	return "\n".join(lines)
