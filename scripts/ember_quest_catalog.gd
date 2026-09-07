class_name EmberQuestCatalog
extends RefCounted
## Quest descriptions are Resources; typed flags remain the only progress owner.

const QuestResource = preload("res://scripts/ember_quest_resource.gd")
const NATIVE_DIR := "res://content/quests"

static var _definition_cache: Dictionary = {}
static var _status_flag_index: Dictionary = {}
static var _status_index_ready := false


static func definition(quest_id: String) -> Dictionary:
	var clean := quest_id.strip_edges()
	if not _valid_id(clean):
		return {}
	var path := native_path(clean)
	if not FileAccess.file_exists(path):
		_definition_cache.erase(clean)
		return {}
	var modified_time := FileAccess.get_modified_time(path)
	var cached: Dictionary = _definition_cache.get(clean, {})
	if int(cached.get("modifiedTime", -1)) == modified_time:
		return (cached.get("definition", {}) as Dictionary).duplicate(true)
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberQuestResource
	var result := resource.to_definition() if resource != null else {}
	_definition_cache[clean] = {
		"modifiedTime": modified_time,
		"definition": result.duplicate(true),
	}
	return result


static func definition_for_status_flag(status_flag_id: String) -> Dictionary:
	var clean := status_flag_id.strip_edges()
	if clean.is_empty():
		return {}
	_ensure_status_index()
	var quest_id := str(_status_flag_index.get(clean, ""))
	return definition(quest_id) if not quest_id.is_empty() else {}


static func definitions() -> Dictionary:
	var result := {}
	for quest_id in ids():
		var value := definition(quest_id)
		if not value.is_empty():
			result[quest_id] = value
	return result


static func ids() -> Array[String]:
	var result: Array[String] = []
	var absolute := ProjectSettings.globalize_path(NATIVE_DIR)
	if DirAccess.dir_exists_absolute(absolute):
		for filename in DirAccess.get_files_at(absolute):
			if filename.get_extension().to_lower() == "tres":
				var quest_id := filename.get_basename()
				if _valid_id(quest_id):
					result.append(quest_id)
	result.sort()
	return result


static func projection(definition_value: Dictionary, flags: Dictionary) -> Dictionary:
	var quest_id := str(definition_value.get("id", "")).strip_edges()
	var status_flag_id := status_flag_id_for(definition_value)
	var explicit_status := EmberQuestState.resolve_status("available", status_flag_id, flags)
	var status := explicit_status
	var objectives: Array[Dictionary] = []
	var required_count := 0
	var completed_count := 0
	var any_completed := false
	var raw_objectives: Variant = definition_value.get("objectives", [])
	var done_by_id := {}
	var text_by_id := {}
	if typeof(raw_objectives) == TYPE_ARRAY:
		for raw_objective in raw_objectives:
			if typeof(raw_objective) != TYPE_DICTIONARY:
				continue
			var source: Dictionary = raw_objective
			var source_id := str(source.get("id", "")).strip_edges()
			var source_flag := str(source.get("flagId", "")).strip_edges()
			var source_value: Variant = flags.get(source_flag, null) if not source_flag.is_empty() else null
			var counter_mode := str(source.get("progressMode", "flag")) == "counter"
			var required := maxi(1, int(source.get("requiredCount", 1)))
			done_by_id[source_id] = (
				_counter_value(source_value) >= required
				if counter_mode
				else _completion_value(source_value)
			)
			text_by_id[source_id] = str(source.get("textRu", source_id))
	if typeof(raw_objectives) == TYPE_ARRAY:
		for raw_objective in raw_objectives:
			if typeof(raw_objective) != TYPE_DICTIONARY:
				continue
			var objective: Dictionary = (raw_objective as Dictionary).duplicate(true)
			var flag_id := str(objective.get("flagId", "")).strip_edges()
			var objective_id := str(objective.get("id", "")).strip_edges()
			var done := bool(done_by_id.get(objective_id, false))
			if str(objective.get("progressMode", "flag")) == "counter":
				objective["currentCount"] = _counter_value(flags.get(flag_id, 0))
				objective["requiredCount"] = maxi(1, int(objective.get("requiredCount", 1)))
			var missing_ids: Array[String] = []
			var missing_texts: Array[String] = []
			var raw_dependencies: Variant = objective.get("requiresObjectiveIds", [])
			if typeof(raw_dependencies) == TYPE_ARRAY:
				for raw_dependency in raw_dependencies:
					var dependency_id := str(raw_dependency).strip_edges()
					if dependency_id.is_empty() or bool(done_by_id.get(dependency_id, false)):
						continue
					missing_ids.append(dependency_id)
					missing_texts.append(str(text_by_id.get(dependency_id, dependency_id)))
			objective["done"] = done
			objective["missingPrerequisiteIds"] = missing_ids
			objective["missingPrerequisiteTexts"] = missing_texts
			objective["locked"] = not done and not missing_ids.is_empty()
			objective["available"] = (
				not done and missing_ids.is_empty() and status != "done"
			)
			objectives.append(objective)
			if done:
				any_completed = true
			if not bool(objective.get("optional", false)):
				required_count += 1
				if done:
					completed_count += 1
	if status == "available" and any_completed:
		status = "active"
	if required_count > 0 and completed_count == required_count:
		status = "done"
	return {
		"id": quest_id,
		"statusFlagId": status_flag_id,
		"explicitStatus": explicit_status,
		"titleRu": str(definition_value.get("titleRu", quest_id)),
		"summaryRu": str(definition_value.get("summaryRu", "")),
		"showWhenAvailable": bool(definition_value.get("showWhenAvailable", false)),
		"status": status,
		"objectives": objectives,
		"completed": completed_count,
		"required": required_count,
		"objectivesComplete": required_count > 0 and completed_count == required_count,
	}


static func authored_flag_transition(
	flag_id: String,
	value: Variant,
	flags: Dictionary,
) -> Dictionary:
	## Authored action/dialogue writes remain set_flag. When that flag is a
	## quest objective completion, this pure gate enforces its dependencies.
	var clean_flag := flag_id.strip_edges()
	if clean_flag.is_empty() or not _completion_value(value):
		return {"allowed": true, "quest": false, "reason": ""}
	for quest_id in ids():
		var quest := definition(quest_id)
		for raw_objective in quest.get("objectives", []):
			if typeof(raw_objective) != TYPE_DICTIONARY:
				continue
			var objective: Dictionary = raw_objective
			if str(objective.get("flagId", "")).strip_edges() != clean_flag:
				continue
			var projected := projection(quest, flags)
			for raw_projected in projected.get("objectives", []):
				if typeof(raw_projected) != TYPE_DICTIONARY:
					continue
				var projected_objective: Dictionary = raw_projected
				if str(projected_objective.get("id", "")) != str(objective.get("id", "")):
					continue
				var missing: Array = projected_objective.get("missingPrerequisiteTexts", [])
				return {
					"allowed": missing.is_empty(),
					"quest": true,
					"questId": quest_id,
					"objectiveId": str(objective.get("id", "")),
					"objectiveText": str(objective.get("textRu", "")),
					"missingPrerequisiteTexts": missing.duplicate(),
					"reason": "" if missing.is_empty() else "prerequisites_incomplete",
					"message": (
						""
						if missing.is_empty()
						else "Сначала выполните: %s" % ", ".join(missing)
					),
				}
	return {"allowed": true, "quest": false, "reason": ""}


static func counter_objective_updates(
	event_id: String,
	amount: int,
	flags: Dictionary,
) -> Array[Dictionary]:
	## Events are global facts; every quest objective owns its own numeric flag.
	## Only currently available objectives receive the event, preserving sequence.
	var result: Array[Dictionary] = []
	var clean_event := event_id.strip_edges()
	if clean_event.is_empty() or amount <= 0:
		return result
	for quest_id in ids():
		var projected := projection(definition(quest_id), flags)
		for raw_objective in projected.get("objectives", []):
			if typeof(raw_objective) != TYPE_DICTIONARY:
				continue
			var objective: Dictionary = raw_objective
			if (
				str(objective.get("progressMode", "flag")) != "counter"
				or str(objective.get("counterEventId", "")) != clean_event
				or not bool(objective.get("available", false))
			):
				continue
			var current := int(objective.get("currentCount", 0))
			var required := maxi(1, int(objective.get("requiredCount", 1)))
			var applied := mini(amount, maxi(0, required - current))
			if applied > 0:
				result.append({
					"questId": quest_id,
					"objectiveId": str(objective.get("id", "")),
					"flagId": str(objective.get("flagId", "")),
					"amount": applied,
				})
	return result


static func marker_status(
	authored_status: String,
	status_flag_id: String,
	flags: Dictionary,
) -> String:
	var definition_value := definition_for_status_flag(status_flag_id)
	if definition_value.is_empty():
		return EmberQuestState.resolve_status(authored_status, status_flag_id, flags)
	var projected := projection(definition_value, flags)
	var status := str(projected.get("status", authored_status))
	return status if status in EmberQuestState.STATUSES else authored_status


static func marker_status_for_quest(
	authored_status: String,
	quest_id: String,
	flags: Dictionary,
) -> String:
	var definition_value := definition(quest_id)
	if definition_value.is_empty():
		return authored_status if authored_status in EmberQuestState.STATUSES else "available"
	var projected := projection(definition_value, flags)
	var status := str(projected.get("status", authored_status))
	return status if status in EmberQuestState.STATUSES else authored_status


static func status_flag_id_for(definition_value: Dictionary) -> String:
	var explicit := str(definition_value.get("statusFlagId", "")).strip_edges()
	return explicit if not explicit.is_empty() else str(definition_value.get("id", "")).strip_edges()


static func progress_flag_ids(definition_value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var status_flag := status_flag_id_for(definition_value)
	if not status_flag.is_empty():
		result.append(status_flag)
	var objectives: Variant = definition_value.get("objectives", [])
	if typeof(objectives) == TYPE_ARRAY:
		for raw_objective in objectives:
			if typeof(raw_objective) != TYPE_DICTIONARY:
				continue
			var flag_id := str((raw_objective as Dictionary).get("flagId", "")).strip_edges()
			if not flag_id.is_empty() and flag_id not in result:
				result.append(flag_id)
	return result


static func visible_projections(flags: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for quest_id in ids():
		var value := projection(definition(quest_id), flags)
		if str(value.get("status", "available")) != "available" or bool(value.get("showWhenAvailable", false)):
			result.append(value)
	return result


static func native_path(quest_id: String) -> String:
	return NATIVE_DIR.path_join("%s.tres" % quest_id.strip_edges())


static func write_native(definition_value: Dictionary) -> int:
	var quest_id := str(definition_value.get("id", "")).strip_edges()
	if not _valid_id(quest_id):
		return ERR_INVALID_PARAMETER
	var mkdir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(NATIVE_DIR))
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		return mkdir_error
	var resource := QuestResource.new() as EmberQuestResource
	resource.quest_id = quest_id
	resource.definition = definition_value.duplicate(true)
	var result := ResourceSaver.save(resource, native_path(quest_id))
	if result == OK:
		_invalidate(quest_id)
	return result


static func delete_native(quest_id: String) -> int:
	var clean := quest_id.strip_edges()
	if not _valid_id(clean):
		return ERR_INVALID_PARAMETER
	var path := native_path(clean)
	var result := DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else OK
	if result == OK:
		_invalidate(clean)
	return result


static func snapshot(quest_id: String) -> Dictionary:
	return {"id": quest_id, "native": definition(quest_id)}


static func restore(snapshot_value: Dictionary) -> int:
	var quest_id := str(snapshot_value.get("id", "")).strip_edges()
	if not _valid_id(quest_id):
		return ERR_INVALID_PARAMETER
	var native: Dictionary = snapshot_value.get("native", {})
	return delete_native(quest_id) if native.is_empty() else write_native(native)


static func _valid_id(value: String) -> bool:
	if value.is_empty():
		return false
	var expression := RegEx.new()
	return expression.compile("^[a-z0-9][a-z0-9_-]*$") == OK and expression.search(value) != null


static func _completion_value(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_BOOL and bool(value))
		or (typeof(value) == TYPE_STRING and str(value) == "done")
	)


static func _counter_value(value: Variant) -> int:
	return maxi(0, int(value)) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else 0


static func _ensure_status_index() -> void:
	if _status_index_ready:
		return
	_status_flag_index.clear()
	for quest_id in ids():
		var value := definition(quest_id)
		var status_flag := status_flag_id_for(value)
		if not status_flag.is_empty():
			_status_flag_index[status_flag] = quest_id
	_status_index_ready = true


static func _invalidate(quest_id: String) -> void:
	_definition_cache.erase(quest_id)
	_status_flag_index.clear()
	_status_index_ready = false
