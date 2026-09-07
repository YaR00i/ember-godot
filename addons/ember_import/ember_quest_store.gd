@tool
class_name EmberQuestStore
extends RefCounted
## Validation/writer boundary for quest descriptions. Progress is not written here.

const Catalog = preload("res://scripts/ember_quest_catalog.gd")


static func document(quest_id: String) -> Dictionary:
	return Catalog.definition(quest_id)


static func document_for_status_flag(status_flag_id: String) -> Dictionary:
	return Catalog.definition_for_status_flag(status_flag_id)


static func document_for_progress_flag(flag_id: String) -> Dictionary:
	var clean := flag_id.strip_edges()
	if clean.is_empty():
		return {}
	for quest_id in Catalog.ids():
		var quest := Catalog.definition(quest_id)
		if clean in Catalog.progress_flag_ids(quest):
			return quest
	return {}


static func ids() -> Array[String]:
	return Catalog.ids()


static func source_path(quest_id: String) -> String:
	return Catalog.native_path(quest_id)


static func flag_reference_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for quest_id in ids():
		var source := document(quest_id)
		if source.is_empty():
			continue
		var quest := normalized_document(source)
		var title := str(quest.get("titleRu", quest_id))
		var status_flag := str(quest.get("statusFlagId", ""))
		if not status_flag.is_empty():
			result.append({
				"id": status_flag,
				"label": "◆ %s\nСтатус задания" % title,
				"tooltip": "%s\nQuest: %s\nОбщий статус: active / done / true" % [status_flag, quest_id],
			})
		var objectives: Variant = quest.get("objectives", [])
		if typeof(objectives) != TYPE_ARRAY:
			continue
		for raw_objective in objectives:
			if typeof(raw_objective) != TYPE_DICTIONARY:
				continue
			var objective: Dictionary = raw_objective
			var flag_id := str(objective.get("flagId", "")).strip_edges()
			if flag_id.is_empty():
				continue
			result.append({
				"id": flag_id,
				"label": "%s %s\n%s" % [
					"◇" if bool(objective.get("optional", false)) else "□",
					title,
					str(objective.get("textRu", objective.get("id", flag_id))),
				],
				"tooltip": "%s\nQuest: %s\nЦель: %s%s" % [
					flag_id,
					quest_id,
					str(objective.get("id", "")),
					" (необязательная)" if bool(objective.get("optional", false)) else "",
				],
			})
	return result


static func event_reference_entries(quest_id_filter := "") -> Array[Dictionary]:
	## Editor-only presets. The selected token is resolved back to the existing
	## set_flag action; tokens never enter gameplay data or save files.
	var result: Array[Dictionary] = []
	for quest_id in ids():
		if not quest_id_filter.strip_edges().is_empty() and quest_id != quest_id_filter.strip_edges():
			continue
		var quest := normalized_document(document(quest_id))
		if quest.is_empty():
			continue
		var title := str(quest.get("titleRu", quest_id))
		var status_flag := str(quest.get("statusFlagId", ""))
		if not status_flag.is_empty():
			result.append({
				"id": event_token(quest_id, "start"),
				"label": "▶ %s\nНачать задание" % title,
				"tooltip": "%s = active\nИгрок увидит задание как принятое." % status_flag,
			})
			result.append({
				"id": event_token(quest_id, "complete"),
				"label": "✓ %s\nЗавершить задание" % title,
				"tooltip": "%s = done\nЯвно завершает всё задание." % status_flag,
			})
		var objectives: Array = quest.get("objectives", [])
		for raw_objective in objectives:
			if typeof(raw_objective) != TYPE_DICTIONARY:
				continue
			var objective: Dictionary = raw_objective
			var objective_id := str(objective.get("id", ""))
			var flag_id := str(objective.get("flagId", ""))
			if objective_id.is_empty() or flag_id.is_empty():
				continue
			result.append({
				"id": event_token(quest_id, "objective", objective_id),
				"label": "%s %s\n%s" % [
					"◇" if bool(objective.get("optional", false)) else "□",
					title,
					str(objective.get("textRu", objective_id)),
				],
				"tooltip": "%s = true\nВыполняет только эту цель." % flag_id,
			})
	return result


static func event_token(quest_id: String, operation: String, objective_id := "") -> String:
	return "quest://%s/%s/%s" % [quest_id, operation, objective_id]


static func quest_id_for_event(token: String) -> String:
	var clean := token.strip_edges()
	if not clean.begins_with("quest://"):
		return ""
	var parts := clean.trim_prefix("quest://").split("/", false)
	return str(parts[0]) if parts.size() >= 2 else ""


static func action_for_event(token: String) -> Dictionary:
	var quest_id := quest_id_for_event(token)
	if quest_id.is_empty():
		return {}
	return action_for_event_in_document(token, document(quest_id))


static func action_for_event_in_document(token: String, quest_value: Dictionary) -> Dictionary:
	## Resolves against the supplied authoring draft. This keeps one compiler for
	## saved Resources and unsaved Quest Flow objectives alike.
	var clean := token.strip_edges()
	if not clean.begins_with("quest://"):
		return {}
	var parts := clean.trim_prefix("quest://").split("/", false)
	if parts.size() < 2:
		return {}
	var quest_id := str(parts[0])
	var operation := str(parts[1])
	var quest := normalized_document(quest_value)
	if quest.is_empty() or str(quest.get("id", "")) != quest_id:
		return {}
	match operation:
		"start":
			return {"type": "set_flag", "flag": quest.statusFlagId, "value": "active"}
		"complete":
			return {"type": "set_flag", "flag": quest.statusFlagId, "value": "done"}
		"objective":
			var objective_id := str(parts[2]) if parts.size() > 2 else ""
			for raw_objective in quest.objectives:
				if typeof(raw_objective) == TYPE_DICTIONARY and str(raw_objective.get("id", "")) == objective_id:
					return {
						"type": "set_flag",
						"flag": str(raw_objective.get("flagId", "")),
						"value": true,
					}
	return {}


static func normalized_document(raw: Dictionary) -> Dictionary:
	var raw_layout: Variant = raw.get("editorLayout", {})
	var result := {
		"id": str(raw.get("id", "")).strip_edges(),
		"statusFlagId": str(raw.get("statusFlagId", raw.get("id", ""))).strip_edges(),
		"titleRu": str(raw.get("titleRu", "")).strip_edges(),
		"summaryRu": str(raw.get("summaryRu", "")).strip_edges(),
		"showWhenAvailable": bool(raw.get("showWhenAvailable", false)),
		"objectives": [],
		"editorLayout": (
			(raw_layout as Dictionary).duplicate(true)
			if typeof(raw_layout) == TYPE_DICTIONARY
			else {}
		),
	}
	var objectives: Array = result.objectives
	var raw_objectives: Variant = raw.get("objectives", [])
	if typeof(raw_objectives) == TYPE_ARRAY:
		for raw_objective in raw_objectives:
			if typeof(raw_objective) != TYPE_DICTIONARY:
				continue
			var source: Dictionary = raw_objective
			var dependencies: Array[String] = []
			var raw_dependencies: Variant = source.get("requiresObjectiveIds", [])
			if typeof(raw_dependencies) == TYPE_ARRAY:
				for raw_dependency in raw_dependencies:
					var dependency_id := str(raw_dependency).strip_edges()
					if not dependency_id.is_empty() and dependency_id not in dependencies:
						dependencies.append(dependency_id)
			objectives.append({
				"id": str(source.get("id", "")).strip_edges(),
				"textRu": str(source.get("textRu", "")).strip_edges(),
				"flagId": str(source.get("flagId", "")).strip_edges(),
				"progressMode": (
					"counter" if str(source.get("progressMode", "flag")) == "counter" else "flag"
				),
				"counterEventId": str(source.get("counterEventId", "")).strip_edges(),
				"requiredCount": maxi(1, int(source.get("requiredCount", 1))),
				"optional": bool(source.get("optional", false)),
				"requiresObjectiveIds": dependencies,
			})
	return result


static func dependency_edges(raw: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_objective in normalized_document(raw).get("objectives", []):
		var objective: Dictionary = raw_objective
		var dependent_id := str(objective.get("id", ""))
		for raw_prerequisite in objective.get("requiresObjectiveIds", []):
			result.append({
				"from": str(raw_prerequisite),
				"to": dependent_id,
			})
	return result


static func set_dependency(
	raw: Dictionary,
	prerequisite_id: String,
	dependent_id: String,
	enabled: bool,
) -> Dictionary:
	var original := normalized_document(raw)
	var prerequisite := prerequisite_id.strip_edges()
	var dependent := dependent_id.strip_edges()
	if prerequisite.is_empty() or dependent.is_empty() or prerequisite == dependent:
		return original
	var known := {}
	for raw_objective in original.objectives:
		known[str((raw_objective as Dictionary).get("id", ""))] = true
	if not known.has(prerequisite) or not known.has(dependent):
		return original
	var result := original.duplicate(true)
	var objectives: Array = result.objectives
	for index in objectives.size():
		var objective: Dictionary = (objectives[index] as Dictionary).duplicate(true)
		if str(objective.get("id", "")) != dependent:
			continue
		var dependencies: Array = objective.get("requiresObjectiveIds", []).duplicate()
		if enabled and prerequisite not in dependencies:
			dependencies.append(prerequisite)
		elif not enabled:
			dependencies.erase(prerequisite)
		objective["requiresObjectiveIds"] = dependencies
		objectives[index] = objective
		break
	result["objectives"] = objectives
	if enabled and _has_dependency_cycle(result):
		return original
	return normalized_document(result)


static func validation_errors(raw: Dictionary) -> Array[String]:
	var value := normalized_document(raw)
	var errors: Array[String] = []
	if not _valid_id(str(value.id)):
		errors.append("ID задания: только a-z, 0-9, _ и -.")
	if str(value.titleRu).is_empty():
		errors.append("Укажите название задания.")
	if not _valid_id(str(value.statusFlagId)):
		errors.append("Укажите корректный флаг статуса задания.")
	var objectives: Array = value.objectives
	if objectives.is_empty():
		errors.append("Добавьте хотя бы одну цель.")
	var known := {}
	var known_flags := {}
	for raw_objective in objectives:
		var objective: Dictionary = raw_objective
		var objective_id := str(objective.id)
		if not _valid_id(objective_id):
			errors.append("У каждой цели нужен корректный ID.")
		elif known.has(objective_id):
			errors.append("ID целей не должны повторяться: %s." % objective_id)
		known[objective_id] = true
		if str(objective.textRu).is_empty():
			errors.append("У каждой цели нужен видимый текст.")
		if not _valid_id(str(objective.flagId)):
			errors.append("У каждой цели нужен корректный flag ID.")
		elif known_flags.has(str(objective.flagId)):
			errors.append("Флаги выполнения целей не должны повторяться: %s." % objective.flagId)
		else:
			known_flags[str(objective.flagId)] = true
		if str(objective.flagId) == str(value.statusFlagId):
			errors.append("Флаг цели не должен совпадать с общим флагом статуса: %s." % objective.flagId)
		if str(objective.get("progressMode", "flag")) == "counter" and int(objective.get("requiredCount", 1)) < 1:
			errors.append("Для боевой цели укажите количество не меньше 1: %s." % objective_id)
		if str(objective.get("progressMode", "flag")) == "counter" and not _valid_id(str(objective.get("counterEventId", ""))):
			errors.append("Для боевой цели выберите событие: %s." % objective_id)
		if (
			str(objective.get("progressMode", "flag")) == "counter"
			and str(objective.get("counterEventId", "")) == str(objective.flagId)
		):
			errors.append("Событие и личный save key боевой цели должны различаться: %s." % objective_id)
	for raw_objective in objectives:
		var objective: Dictionary = raw_objective
		var objective_id := str(objective.id)
		for raw_dependency in objective.get("requiresObjectiveIds", []):
			var dependency_id := str(raw_dependency)
			if dependency_id == objective_id:
				errors.append("Цель %s не может зависеть от самой себя." % objective_id)
			elif not known.has(dependency_id):
				errors.append("Цель %s зависит от отсутствующей цели %s." % [objective_id, dependency_id])
	if _has_dependency_cycle(value):
		errors.append("Последовательность целей содержит цикл.")
	return errors


static func write_document(raw: Dictionary) -> int:
	var value := normalized_document(raw)
	if not validation_errors(value).is_empty():
		return ERR_INVALID_DATA
	return Catalog.write_native(value)


static func snapshot(quest_id: String) -> Dictionary:
	return Catalog.snapshot(quest_id)


static func restore_snapshot(snapshot_value: Dictionary) -> int:
	return Catalog.restore(snapshot_value)


static func suggested_id(source: String) -> String:
	var clean := source.strip_edges().to_lower()
	var expression := RegEx.new()
	expression.compile("[^a-z0-9_-]+")
	clean = expression.sub(clean, "_", true).strip_edges().trim_prefix("_").trim_suffix("_")
	return "%s_quest" % (clean if not clean.is_empty() else "new")


static func _valid_id(value: String) -> bool:
	if value.is_empty():
		return false
	var expression := RegEx.new()
	return expression.compile("^[a-z0-9][a-z0-9_-]*$") == OK and expression.search(value) != null


static func _has_dependency_cycle(raw: Dictionary) -> bool:
	var dependencies := {}
	for raw_objective in raw.get("objectives", []):
		if typeof(raw_objective) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = raw_objective
		dependencies[str(objective.get("id", ""))] = objective.get("requiresObjectiveIds", [])
	var states := {}
	for objective_id in dependencies:
		if _dependency_visit(str(objective_id), dependencies, states):
			return true
	return false


static func _dependency_visit(objective_id: String, dependencies: Dictionary, states: Dictionary) -> bool:
	var state := int(states.get(objective_id, 0))
	if state == 1:
		return true
	if state == 2:
		return false
	states[objective_id] = 1
	for raw_dependency in dependencies.get(objective_id, []):
		var dependency_id := str(raw_dependency)
		if dependencies.has(dependency_id) and _dependency_visit(dependency_id, dependencies, states):
			return true
	states[objective_id] = 2
	return false
