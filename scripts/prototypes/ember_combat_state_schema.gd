extends RefCounted
## Runtime boundary validation for dictionary snapshots. Dictionaries remain the
## serialization-neutral value format, but malformed state is rejected before
## the resolver reads dozens of string keys.

const StatusCatalog := preload("res://scripts/prototypes/ember_combat_status_catalog.gd")

const REQUIRED_UNIT_KEYS := [
	"id", "name", "team", "hp", "maxHp", "mp", "maxMp", "speed",
	"nextAt", "statuses", "actions", "resistances", "statusResistances",
]
const RESULT_DICTIONARY_KEYS := [
	"damage", "fixedDamage", "setStatuses", "removeStatuses", "moves",
	"cellChanges", "restoreHp", "restoreMp", "inventoryCost",
]


static func validation_errors(state: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if typeof(state.get("units", null)) != TYPE_DICTIONARY:
		errors.append("Состояние боя: units должен быть Dictionary.")
		return errors
	if typeof(state.get("holds", null)) != TYPE_DICTIONARY:
		errors.append("Состояние боя: holds должен быть Dictionary.")
	if typeof(state.get("log", null)) != TYPE_ARRAY:
		errors.append("Состояние боя: log должен быть Array.")
	if not state.has("turn") or int(state.get("turn", 0)) <= 0:
		errors.append("Состояние боя: turn должен быть положительным.")
	if not state.has("rngSeed"):
		errors.append("Состояние боя: отсутствует rngSeed.")
	var units: Dictionary = state.get("units", {})
	for raw_id in units:
		var unit_id := str(raw_id)
		if typeof(units[raw_id]) != TYPE_DICTIONARY:
			errors.append("Боец %s должен быть Dictionary." % unit_id)
			continue
		var unit: Dictionary = units[raw_id]
		for key in REQUIRED_UNIT_KEYS:
			if not unit.has(key):
				errors.append("Боец %s: отсутствует поле %s." % [unit_id, key])
		if str(unit.get("id", "")) != unit_id:
			errors.append("Боец %s: внутренний id не совпадает с ключом." % unit_id)
		if str(unit.get("team", "")) not in ["hero", "enemy"]:
			errors.append("Боец %s: неизвестная сторона." % unit_id)
		if typeof(unit.get("statuses", null)) != TYPE_DICTIONARY:
			errors.append("Боец %s: statuses должен быть Dictionary." % unit_id)
		else:
			for raw_status_id in unit.get("statuses", {}):
				var status_id := str(raw_status_id)
				if StatusCatalog.resource(status_id) == null:
					errors.append("Боец %s: неизвестный статус %s." % [unit_id, status_id])
				elif int((unit.get("statuses", {}) as Dictionary)[raw_status_id]) <= 0:
					errors.append("Боец %s: статус %s требует положительную длительность." % [
						unit_id, status_id,
					])
		if typeof(unit.get("actions", null)) != TYPE_ARRAY:
			errors.append("Боец %s: actions должен быть Array." % unit_id)
	if state.has("grid"):
		_validate_grid(state.get("grid", {}), errors)
	return errors


static func result_validation_errors(resolved: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not bool(resolved.get("ok", false)):
		return errors
	for key in ["stateTurn", "stateHash", "actorId", "actionId"]:
		if not resolved.has(key):
			errors.append("Результат preview: отсутствует поле %s." % key)
	for key in RESULT_DICTIONARY_KEYS:
		if typeof(resolved.get(key, null)) != TYPE_DICTIONARY:
			errors.append("Результат preview: %s должен быть Dictionary." % key)
	return errors


static func first_error(state: Dictionary) -> String:
	var errors := validation_errors(state)
	return "" if errors.is_empty() else errors[0]


static func first_result_error(resolved: Dictionary) -> String:
	var errors := result_validation_errors(resolved)
	return "" if errors.is_empty() else errors[0]


static func _validate_grid(raw: Variant, errors: Array[String]) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("Состояние боя: grid должен быть Dictionary.")
		return
	var grid := raw as Dictionary
	if int(grid.get("width", 0)) <= 0 or int(grid.get("height", 0)) <= 0:
		errors.append("Состояние боя: grid требует положительные width и height.")
	if typeof(grid.get("cells", null)) != TYPE_DICTIONARY:
		errors.append("Состояние боя: grid.cells должен быть Dictionary.")
