@tool
class_name EmberQuestUsageIndex
extends RefCounted
## Editor-only reverse index for quest events. It projects existing action and
## dialogue set_flag writers without copying them into EmberQuestResource.

const QuestStore = preload("res://addons/ember_import/ember_quest_store.gd")
const ActionCatalog = preload("res://scripts/ember_action_catalog.gd")
const DialogueCatalog = preload("res://scripts/ember_dialogue_catalog.gd")


static func entries(quest_value: Dictionary) -> Array[Dictionary]:
	var action_documents: Array[Dictionary] = []
	for action_id in ActionCatalog.ids():
		var document := ActionCatalog.document(action_id)
		if not document.is_empty():
			action_documents.append(document)
	var dialogue_documents: Array[Dictionary] = []
	for dialogue_id in DialogueCatalog.ids():
		var document := DialogueCatalog.document(dialogue_id)
		if not document.is_empty():
			dialogue_documents.append(document)
	return entries_for_documents(quest_value, action_documents, dialogue_documents)


static func entries_for_documents(
	quest_value: Dictionary,
	action_documents: Array[Dictionary],
	dialogue_documents: Array[Dictionary],
) -> Array[Dictionary]:
	var quest := QuestStore.normalized_document(quest_value)
	var targets := _targets_by_flag(quest)
	if targets.is_empty():
		return []
	var result: Array[Dictionary] = []
	var used_ids := {}
	for document in action_documents:
		_scan_action(document, targets, result, used_ids)
	for document in dialogue_documents:
		_scan_dialogue(document, targets, result, used_ids)
	result.sort_custom(_entry_less)
	return result


static func scene_entries(
	scene_root: Node,
	quest_value: Dictionary,
	event_entries: Array[Dictionary],
) -> Array[Dictionary]:
	## Scene backlinks are a read-only projection of the currently edited scene.
	## Stable NodePaths are used only for editor navigation and never serialized.
	if scene_root == null:
		return []
	var quest := QuestStore.normalized_document(quest_value)
	var quest_id := str(quest.get("id", ""))
	var event_ids_by_document := {}
	for entry in event_entries:
		var key := _document_key(
			str(entry.get("documentKind", "")),
			str(entry.get("documentId", "")),
		)
		if key == ":":
			continue
		var ids: Array = event_ids_by_document.get(key, [])
		ids.append(str(entry.get("id", "")))
		event_ids_by_document[key] = ids
	var result: Array[Dictionary] = []
	_collect_scene_entries(scene_root, scene_root, quest_id, event_ids_by_document, result)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("nodePath", "")) < str(right.get("nodePath", ""))
	)
	return result


static func _collect_scene_entries(
	scene_root: Node,
	current: Node,
	quest_id: String,
	event_ids_by_document: Dictionary,
	result: Array[Dictionary],
) -> void:
	if current is EmberInteract:
		var interact := current as EmberInteract
		var script_id := interact.resolved_action_script_id().strip_edges()
		var keys: Array[String] = []
		for document_kind in ["action", "dialogue"]:
			var key := _document_key(document_kind, script_id)
			if event_ids_by_document.has(key):
				keys.append(key)
		if not keys.is_empty():
			var event_ids: Array[String] = []
			for key in keys:
				for raw_id in event_ids_by_document.get(key, []):
					var event_id := str(raw_id)
					if event_id not in event_ids:
						event_ids.append(event_id)
			var owner_node := _authoring_owner(interact)
			var node_path := str(scene_root.get_path_to(interact))
			result.append({
				"id": "scene:%s" % node_path,
				"nodePath": node_path,
				"ownerPath": str(scene_root.get_path_to(owner_node)),
				"ownerName": str(owner_node.name),
				"interactName": str(interact.name),
				"kind": interact.kind,
				"activation": interact.activation_title(),
				"scriptId": script_id,
				"questId": interact.effective_quest_id(),
				"matchesQuest": interact.effective_quest_id() == quest_id,
				"eventIds": event_ids,
			})
	for child in current.get_children():
		_collect_scene_entries(scene_root, child, quest_id, event_ids_by_document, result)


static func _authoring_owner(interact: EmberInteract) -> Node:
	var current: Node = interact
	while current != null:
		if current is EmberVoxelProp:
			return current
		current = current.get_parent()
	return interact


static func _document_key(kind: String, document_id: String) -> String:
	return "%s:%s" % [kind.strip_edges(), document_id.strip_edges()]


static func _targets_by_flag(quest: Dictionary) -> Dictionary:
	var result := {}
	var status_flag := str(quest.get("statusFlagId", "")).strip_edges()
	if not status_flag.is_empty():
		result[status_flag] = {
			"targetKind": "quest",
			"targetId": "quest_root",
			"targetLabel": str(quest.get("titleRu", quest.get("id", ""))),
		}
	for raw_objective in quest.get("objectives", []):
		if typeof(raw_objective) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = raw_objective
		var flag_id := str(objective.get("flagId", "")).strip_edges()
		if flag_id.is_empty():
			continue
		result[flag_id] = {
			"targetKind": "objective",
			"targetId": str(objective.get("id", "")),
			"targetLabel": str(objective.get("textRu", objective.get("id", ""))),
		}
	return result


static func _scan_action(
	document: Dictionary,
	targets: Dictionary,
	result: Array[Dictionary],
	used_ids: Dictionary,
) -> void:
	var document_id := str(document.get("id", "")).strip_edges()
	if document_id.is_empty():
		return
	var title := str(document.get("nameRu", document_id)).strip_edges()
	var steps: Variant = document.get("steps", [])
	if typeof(steps) != TYPE_ARRAY:
		return
	for index in steps.size():
		var raw_step: Variant = steps[index]
		if typeof(raw_step) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = raw_step
		if str(step.get("type", "")) != "set_flag":
			continue
		_append_writer(
			result,
			used_ids,
			targets,
			"action",
			document_id,
			title,
			str(step.get("id", "step_%d" % (index + 1))),
			str(step.get("flag", "")),
			step.get("value", true),
			"Шаг %d" % (index + 1),
			index,
		)


static func _scan_dialogue(
	document: Dictionary,
	targets: Dictionary,
	result: Array[Dictionary],
	used_ids: Dictionary,
) -> void:
	var document_id := str(document.get("id", "")).strip_edges()
	if document_id.is_empty():
		return
	var title := str(document.get("nameRu", document_id)).strip_edges()
	var steps: Variant = document.get("steps", [])
	if typeof(steps) != TYPE_ARRAY:
		return
	for index in steps.size():
		var raw_step: Variant = steps[index]
		if typeof(raw_step) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = raw_step
		var step_id := str(step.get("id", "step_%d" % (index + 1)))
		if str(step.get("type", "")) == "set_flag":
			_append_writer(
				result,
				used_ids,
				targets,
				"dialogue",
				document_id,
				title,
				step_id,
				str(step.get("flag", "")),
				step.get("value", true),
				"Нода %s" % step_id,
			)
		var options: Variant = step.get("options", [])
		if typeof(options) != TYPE_ARRAY:
			continue
		for option_index in options.size():
			var raw_option: Variant = options[option_index]
			if typeof(raw_option) != TYPE_DICTIONARY:
				continue
			var option: Dictionary = raw_option
			var set_flags: Variant = option.get("setFlags", {})
			if typeof(set_flags) != TYPE_DICTIONARY:
				continue
			for raw_flag in (set_flags as Dictionary).keys():
				_append_writer(
					result,
					used_ids,
					targets,
					"dialogue",
					document_id,
					title,
					"%s_option_%d" % [step_id, option_index + 1],
					str(raw_flag),
					(set_flags as Dictionary).get(raw_flag, true),
					"Ответ: %s" % str(option.get("labelRu", option_index + 1)),
				)


static func _append_writer(
	result: Array[Dictionary],
	used_ids: Dictionary,
	targets: Dictionary,
	document_kind: String,
	document_id: String,
	document_title: String,
	node_id: String,
	flag_id: String,
	value: Variant,
	location: String,
	writer_index := -1,
) -> void:
	var clean_flag := flag_id.strip_edges()
	if not targets.has(clean_flag):
		return
	var target: Dictionary = targets[clean_flag]
	var entry_id := "%s:%s:%s:%s" % [document_kind, document_id, node_id, clean_flag]
	if used_ids.has(entry_id):
		return
	used_ids[entry_id] = true
	var operation := _operation_for(str(target.get("targetKind", "")), value)
	result.append({
		"id": entry_id,
		"documentKind": document_kind,
		"documentId": document_id,
		"documentTitle": document_title if not document_title.is_empty() else document_id,
		"nodeId": node_id,
		"location": location,
		"writerIndex": writer_index,
		"flag": clean_flag,
		"value": value,
		"operation": operation,
		"operationLabel": _operation_label(operation),
		"targetKind": str(target.get("targetKind", "")),
		"targetId": str(target.get("targetId", "")),
		"targetLabel": str(target.get("targetLabel", "")),
	})


static func _operation_for(target_kind: String, value: Variant) -> String:
	if target_kind == "quest":
		var text := str(value).to_lower()
		if text == "active":
			return "quest_start"
		if text in ["done", "true"]:
			return "quest_complete"
		return "quest_status"
	if value == false or str(value).to_lower() == "false":
		return "objective_reset"
	return "objective_complete"


static func _operation_label(operation: String) -> String:
	match operation:
		"quest_start": return "Начинает задание"
		"quest_complete": return "Завершает задание"
		"objective_complete": return "Выполняет цель"
		"objective_reset": return "Сбрасывает цель"
	return "Меняет статус задания"


static func _entry_less(left: Dictionary, right: Dictionary) -> bool:
	var left_key := "%s|%s|%s|%s" % [
		str(left.get("targetId", "")),
		str(left.get("documentKind", "")),
		str(left.get("documentId", "")),
		str(left.get("nodeId", "")),
	]
	var right_key := "%s|%s|%s|%s" % [
		str(right.get("targetId", "")),
		str(right.get("documentKind", "")),
		str(right.get("documentId", "")),
		str(right.get("nodeId", "")),
	]
	return left_key < right_key
