@tool
class_name EmberDialogueGraphModel
extends RefCounted
## Pure structural operations for the existing JOI dialogue JSON graph.
## It does not own serialization or runtime traversal.

const ActionStore = preload("res://addons/ember_import/ember_action_script_store.gd")
const SUPPORTED_TYPES := ["dialogue", "choice", "splash", "set_flag", "grant_cinders", "end"]
const AUTHORING_TYPES := ["dialogue", "choice", "splash", "set_flag", "end"]


static func normalized_document(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	if typeof(result.get("steps", [])) != TYPE_ARRAY:
		result["steps"] = []
	if typeof(result.get("editorLayout", {})) != TYPE_DICTIONARY:
		result["editorLayout"] = {}
	if result.has("editorGroups") and typeof(result.get("editorGroups")) != TYPE_ARRAY:
		result["editorGroups"] = []
	return result


static func steps_by_id(document: Dictionary) -> Dictionary:
	var result := {}
	var raw_steps: Variant = document.get("steps", [])
	if typeof(raw_steps) != TYPE_ARRAY:
		return result
	for raw_step in raw_steps:
		if typeof(raw_step) == TYPE_DICTIONARY:
			var step: Dictionary = raw_step
			var step_id := str(step.get("id", "")).strip_edges()
			if not step_id.is_empty():
				result[step_id] = step
	return result


static func edges(document: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_steps: Variant = document.get("steps", [])
	if typeof(raw_steps) != TYPE_ARRAY:
		return result
	for raw_step in raw_steps:
		if typeof(raw_step) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = raw_step
		var source_id := str(step.get("id", "")).strip_edges()
		if str(step.get("type", "")) == "choice":
			var options: Variant = step.get("options", [])
			if typeof(options) != TYPE_ARRAY:
				continue
			for option_index in options.size():
				var raw_option: Variant = options[option_index]
				if typeof(raw_option) != TYPE_DICTIONARY:
					continue
				var option: Dictionary = raw_option
				result.append({
					"from": source_id,
					"port": option_index,
					"label": str(option.get("labelRu", option.get("id", "Ответ %d" % (option_index + 1)))),
					"to": str(option.get("next", "")).strip_edges(),
				})
		elif step.has("next"):
			result.append({
				"from": source_id,
				"port": 0,
				"label": "Далее",
				"to": str(step.get("next", "")).strip_edges(),
			})
	return result


static func replace_edge(
	document: Dictionary,
	source_id: String,
	source_port: int,
	target_id: String,
) -> Dictionary:
	var result := normalized_document(document)
	var steps: Array = result.get("steps", []).duplicate(true)
	for index in steps.size():
		if typeof(steps[index]) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = (steps[index] as Dictionary).duplicate(true)
		if str(step.get("id", "")) != source_id:
			continue
		if str(step.get("type", "")) == "choice":
			var options: Array = step.get("options", []).duplicate(true)
			if source_port < 0 or source_port >= options.size() or typeof(options[source_port]) != TYPE_DICTIONARY:
				return result
			var option: Dictionary = (options[source_port] as Dictionary).duplicate(true)
			option["next"] = target_id
			options[source_port] = option
			step["options"] = options
		elif source_port == 0 and str(step.get("type", "")) != "end":
			step["next"] = target_id
		else:
			return result
		steps[index] = step
		result["steps"] = steps
		return result
	return result


static func add_step(document: Dictionary, step_type: String, position: Vector2) -> Dictionary:
	var result := normalized_document(document)
	var kind := step_type if step_type in AUTHORING_TYPES else "dialogue"
	var step_id := unique_step_id(result, _step_prefix(kind))
	var steps: Array = result.get("steps", []).duplicate(true)
	steps.append(default_step(kind, step_id))
	result["steps"] = steps
	var layout: Dictionary = result.get("editorLayout", {}).duplicate(true)
	layout[step_id] = {"x": position.x, "y": position.y}
	result["editorLayout"] = layout
	if str(result.get("startStepId", "")).is_empty():
		result["startStepId"] = step_id
	return result


static func remove_steps(document: Dictionary, step_ids: Array[String]) -> Dictionary:
	var result := normalized_document(document)
	if step_ids.is_empty():
		return result
	var removed := {}
	for step_id in step_ids:
		removed[step_id] = true
	var kept: Array[Dictionary] = []
	for raw_step in result.get("steps", []):
		if typeof(raw_step) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = (raw_step as Dictionary).duplicate(true)
		if removed.has(str(step.get("id", ""))):
			continue
		if str(step.get("type", "")) == "choice":
			var options: Array = step.get("options", []).duplicate(true)
			for index in options.size():
				if typeof(options[index]) != TYPE_DICTIONARY:
					continue
				var option: Dictionary = (options[index] as Dictionary).duplicate(true)
				if removed.has(str(option.get("next", ""))):
					option["next"] = ""
				options[index] = option
			step["options"] = options
		elif removed.has(str(step.get("next", ""))):
			step["next"] = ""
		kept.append(step)
	result["steps"] = kept
	var layout: Dictionary = result.get("editorLayout", {}).duplicate(true)
	for step_id in step_ids:
		layout.erase(step_id)
	result["editorLayout"] = layout
	var groups: Array = []
	for raw_group in result.get("editorGroups", []):
		if typeof(raw_group) != TYPE_DICTIONARY:
			continue
		var group: Dictionary = (raw_group as Dictionary).duplicate(true)
		var members: Array = group.get("members", []).duplicate()
		for step_id in step_ids:
			members.erase(step_id)
		if not members.is_empty():
			group["members"] = members
			groups.append(group)
	result["editorGroups"] = groups
	if removed.has(str(result.get("startStepId", ""))):
		result["startStepId"] = str(kept[0].get("id", "")) if not kept.is_empty() else ""
	return result


static func set_start(document: Dictionary, step_id: String) -> Dictionary:
	var result := normalized_document(document)
	if steps_by_id(result).has(step_id):
		result["startStepId"] = step_id
	return result


static func set_step_field(document: Dictionary, step_id: String, field: String, value: Variant) -> Dictionary:
	var result := normalized_document(document)
	var steps: Array = result.get("steps", []).duplicate(true)
	for index in steps.size():
		if typeof(steps[index]) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = (steps[index] as Dictionary).duplicate(true)
		if str(step.get("id", "")) == step_id:
			step[field] = value
			steps[index] = step
			result["steps"] = steps
			break
	return result


static func set_document_field(document: Dictionary, field: String, value: Variant) -> Dictionary:
	var result := normalized_document(document)
	result[field] = value
	return result


static func background_override_count(document: Dictionary) -> int:
	var count := 0
	for raw_step in document.get("steps", []):
		if typeof(raw_step) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = raw_step
		if str(step.get("type", "")) in ["dialogue", "choice"] and not str(
			step.get("bgArtId", "")
		).strip_edges().is_empty():
			count += 1
	return count


static func inherit_scene_background(document: Dictionary) -> Dictionary:
	## Removes only per-node background overrides. The scene default and every
	## unrelated/unknown key remain untouched, so this is a lossless migration.
	var result := normalized_document(document)
	var steps: Array = result.get("steps", []).duplicate(true)
	for index in steps.size():
		if typeof(steps[index]) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = (steps[index] as Dictionary).duplicate(true)
		if str(step.get("type", "")) not in ["dialogue", "choice"]:
			continue
		step.erase("bgArtId")
		steps[index] = step
	result["steps"] = steps
	return result


static func set_primary_actor_field(
	document: Dictionary,
	step_id: String,
	field: String,
	value: Variant,
) -> Dictionary:
	var result := normalized_document(document)
	var steps: Array = result.get("steps", []).duplicate(true)
	for index in steps.size():
		if typeof(steps[index]) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = (steps[index] as Dictionary).duplicate(true)
		if str(step.get("id", "")) != step_id:
			continue
		var actors: Array = step.get("actors", []).duplicate(true)
		if actors.is_empty() or typeof(actors[0]) != TYPE_DICTIONARY:
			return result
		var actor: Dictionary = (actors[0] as Dictionary).duplicate(true)
		actor[field] = value
		actors[0] = actor
		step["actors"] = actors
		steps[index] = step
		result["steps"] = steps
		break
	return result


static func add_primary_actor(document: Dictionary, step_id: String) -> Dictionary:
	var result := normalized_document(document)
	var steps: Array = result.get("steps", []).duplicate(true)
	for index in steps.size():
		if typeof(steps[index]) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = (steps[index] as Dictionary).duplicate(true)
		if str(step.get("id", "")) != step_id:
			continue
		var actors: Array = step.get("actors", []).duplicate(true)
		if not actors.is_empty():
			return result
		var side := str(step.get("portraitSide", "left"))
		actors.append({
			"id": "main",
			"speaker": str(step.get("speaker", "actor")),
			"portraitKey": str(step.get("portraitKey", "neutral")),
			"x": 75.0 if side == "right" else 25.0,
			"y": 100.0,
			"scale": 1.0,
			"z": 1.0,
		})
		step["actors"] = actors
		steps[index] = step
		result["steps"] = steps
		break
	return result


static func remove_primary_actor(document: Dictionary, step_id: String) -> Dictionary:
	var result := normalized_document(document)
	var steps: Array = result.get("steps", []).duplicate(true)
	for index in steps.size():
		if typeof(steps[index]) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = (steps[index] as Dictionary).duplicate(true)
		if str(step.get("id", "")) != step_id:
			continue
		var actors: Array = step.get("actors", []).duplicate(true)
		if actors.is_empty():
			return result
		actors.remove_at(0)
		if actors.is_empty():
			step.erase("actors")
		else:
			step["actors"] = actors
		steps[index] = step
		result["steps"] = steps
		break
	return result


static func set_choice_option_field(
	document: Dictionary,
	step_id: String,
	option_index: int,
	field: String,
	value: Variant,
) -> Dictionary:
	var result := normalized_document(document)
	var steps: Array = result.get("steps", []).duplicate(true)
	for index in steps.size():
		if typeof(steps[index]) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = (steps[index] as Dictionary).duplicate(true)
		if str(step.get("id", "")) != step_id or str(step.get("type", "")) != "choice":
			continue
		var options: Array = step.get("options", []).duplicate(true)
		if option_index >= 0 and option_index < options.size() and typeof(options[option_index]) == TYPE_DICTIONARY:
			var option: Dictionary = (options[option_index] as Dictionary).duplicate(true)
			option[field] = value
			options[option_index] = option
			step["options"] = options
			steps[index] = step
			result["steps"] = steps
		break
	return result


static func add_group(document: Dictionary, title: String, members: Array[String]) -> Dictionary:
	var result := normalized_document(document)
	var clean_members: Array[String] = []
	var known_steps := steps_by_id(result)
	for step_id in members:
		if known_steps.has(step_id) and step_id not in clean_members:
			clean_members.append(step_id)
	if clean_members.is_empty():
		return result
	var groups: Array = result.get("editorGroups", []).duplicate(true)
	for index in groups.size():
		if typeof(groups[index]) != TYPE_DICTIONARY:
			continue
		var group: Dictionary = (groups[index] as Dictionary).duplicate(true)
		var old_members: Array = group.get("members", []).duplicate()
		for step_id in clean_members:
			old_members.erase(step_id)
		group["members"] = old_members
		groups[index] = group
	groups = groups.filter(func(group: Variant) -> bool:
		return typeof(group) == TYPE_DICTIONARY and not (group as Dictionary).get("members", []).is_empty()
	)
	groups.append({
		"id": _unique_group_id(groups),
		"title": title.strip_edges() if not title.strip_edges().is_empty() else "Новая группа",
		"members": clean_members,
	})
	result["editorGroups"] = groups
	return result


static func rename_group(document: Dictionary, group_id: String, title: String) -> Dictionary:
	var result := normalized_document(document)
	var groups: Array = result.get("editorGroups", []).duplicate(true)
	for index in groups.size():
		if typeof(groups[index]) != TYPE_DICTIONARY:
			continue
		var group: Dictionary = (groups[index] as Dictionary).duplicate(true)
		if str(group.get("id", "")) == group_id:
			group["title"] = title.strip_edges() if not title.strip_edges().is_empty() else "Группа"
			groups[index] = group
			break
	result["editorGroups"] = groups
	return result


static func set_group_collapsed(document: Dictionary, group_id: String, collapsed: bool) -> Dictionary:
	var result := normalized_document(document)
	var groups: Array = result.get("editorGroups", []).duplicate(true)
	for index in groups.size():
		if typeof(groups[index]) != TYPE_DICTIONARY:
			continue
		var group: Dictionary = (groups[index] as Dictionary).duplicate(true)
		if str(group.get("id", "")) == group_id:
			group["collapsed"] = collapsed
			groups[index] = group
			break
	result["editorGroups"] = groups
	return result


static func add_members_to_group(
	document: Dictionary,
	group_id: String,
	members: Array[String],
) -> Dictionary:
	var result := normalized_document(document)
	var known_steps := steps_by_id(result)
	var clean_members: Array[String] = []
	for step_id in members:
		if known_steps.has(step_id) and step_id not in clean_members:
			clean_members.append(step_id)
	if clean_members.is_empty():
		return result
	var groups: Array = result.get("editorGroups", []).duplicate(true)
	var target_found := false
	for index in groups.size():
		if typeof(groups[index]) != TYPE_DICTIONARY:
			continue
		var group: Dictionary = (groups[index] as Dictionary).duplicate(true)
		var old_members: Array = group.get("members", []).duplicate()
		for step_id in clean_members:
			old_members.erase(step_id)
		if str(group.get("id", "")) == group_id:
			target_found = true
			for step_id in clean_members:
				if step_id not in old_members:
					old_members.append(step_id)
		group["members"] = old_members
		groups[index] = group
	if not target_found:
		return result
	groups = groups.filter(func(group: Variant) -> bool:
		return typeof(group) == TYPE_DICTIONARY and not (group as Dictionary).get("members", []).is_empty()
	)
	result["editorGroups"] = groups
	return result


static func remove_members_from_groups(document: Dictionary, members: Array[String]) -> Dictionary:
	var result := normalized_document(document)
	var groups: Array = []
	for raw_group in result.get("editorGroups", []):
		if typeof(raw_group) != TYPE_DICTIONARY:
			continue
		var group: Dictionary = (raw_group as Dictionary).duplicate(true)
		var kept_members: Array = group.get("members", []).duplicate()
		for step_id in members:
			kept_members.erase(step_id)
		if not kept_members.is_empty():
			group["members"] = kept_members
			groups.append(group)
	result["editorGroups"] = groups
	return result


static func remove_groups(document: Dictionary, group_ids: Array[String]) -> Dictionary:
	var result := normalized_document(document)
	var groups: Array = []
	for raw_group in result.get("editorGroups", []):
		if typeof(raw_group) == TYPE_DICTIONARY and str(raw_group.get("id", "")) not in group_ids:
			groups.append((raw_group as Dictionary).duplicate(true))
	result["editorGroups"] = groups
	return result


static func duplicate_steps(document: Dictionary, step_ids: Array[String], offset: Vector2) -> Dictionary:
	return _paste_step_payload(
		normalized_document(document), copy_steps(document, step_ids), offset, false
	)


static func copy_steps(document: Dictionary, step_ids: Array[String]) -> Dictionary:
	var result := normalized_document(document)
	var selected := {}
	for step_id in step_ids:
		selected[step_id] = true
	var copied_steps: Array[Dictionary] = []
	for raw_step in result.get("steps", []):
		if typeof(raw_step) == TYPE_DICTIONARY and selected.has(str(raw_step.get("id", ""))):
			copied_steps.append((raw_step as Dictionary).duplicate(true))
	var copied_layout := {}
	var layout: Dictionary = result.get("editorLayout", {})
	for step in copied_steps:
		var step_id := str(step.get("id", ""))
		if typeof(layout.get(step_id, {})) == TYPE_DICTIONARY:
			copied_layout[step_id] = (layout.get(step_id, {}) as Dictionary).duplicate(true)
	return {"kind": "dialogue", "steps": copied_steps, "layout": copied_layout}


static func paste_steps(document: Dictionary, payload: Dictionary, position: Vector2) -> Dictionary:
	return _paste_step_payload(normalized_document(document), payload, position, true)


static func _paste_step_payload(
	result: Dictionary,
	payload: Dictionary,
	position_or_offset: Vector2,
	anchor_at_position: bool,
) -> Dictionary:
	var originals: Array[Dictionary] = []
	for raw_step in payload.get("steps", []):
		if typeof(raw_step) == TYPE_DICTIONARY and not str(raw_step.get("id", "")).is_empty():
			originals.append((raw_step as Dictionary).duplicate(true))
	if originals.is_empty():
		return {"document": result, "newIds": [], "idMap": {}}
	var destination_ids := steps_by_id(result)
	var used := destination_ids.duplicate()
	var id_map := {}
	var new_ids: Array[String] = []
	for original in originals:
		var old_id := str(original.get("id", "step"))
		var prefix := "%s_copy" % old_id if ActionStore.valid_id("%s_copy" % old_id) else "step_copy"
		var suffix := 1
		var new_id := "%s_%d" % [prefix, suffix]
		while used.has(new_id):
			suffix += 1
			new_id = "%s_%d" % [prefix, suffix]
		used[new_id] = true
		id_map[old_id] = new_id
		new_ids.append(new_id)
	var steps: Array = result.get("steps", []).duplicate(true)
	var layout: Dictionary = result.get("editorLayout", {}).duplicate(true)
	var source_layout: Dictionary = payload.get("layout", {})
	var source_origin := Vector2.ZERO
	var has_source_origin := false
	if anchor_at_position:
		for original in originals:
			var old_id := str(original.get("id", ""))
			var raw_position: Variant = source_layout.get(old_id, {})
			if typeof(raw_position) != TYPE_DICTIONARY:
				continue
			var candidate := Vector2(
				float((raw_position as Dictionary).get("x", 0.0)),
				float((raw_position as Dictionary).get("y", 0.0)),
			)
			if not has_source_origin:
				source_origin = candidate
				has_source_origin = true
			else:
				source_origin.x = minf(source_origin.x, candidate.x)
				source_origin.y = minf(source_origin.y, candidate.y)
	for original in originals:
		var clone := original.duplicate(true)
		var old_id := str(original.get("id", ""))
		var new_id := str(id_map.get(old_id, ""))
		clone["id"] = new_id
		if str(clone.get("type", "")) == "choice":
			var options: Array = clone.get("options", []).duplicate(true)
			for index in options.size():
				if typeof(options[index]) != TYPE_DICTIONARY:
					continue
				var option: Dictionary = (options[index] as Dictionary).duplicate(true)
				var target := str(option.get("next", ""))
				if id_map.has(target):
					option["next"] = id_map[target]
				elif not target.is_empty() and not destination_ids.has(target):
					option["next"] = ""
				options[index] = option
			clone["options"] = options
		elif clone.has("next"):
			var target := str(clone.get("next", ""))
			if id_map.has(target):
				clone["next"] = id_map[target]
			elif not target.is_empty() and not destination_ids.has(target):
				clone["next"] = ""
		steps.append(clone)
		var source: Dictionary = (
			source_layout.get(old_id, {}).duplicate(true)
			if typeof(source_layout.get(old_id, {})) == TYPE_DICTIONARY
			else {}
		)
		var source_position := Vector2(
			float(source.get("x", 0.0)), float(source.get("y", 0.0))
		)
		var pasted_position := (
			position_or_offset + source_position - source_origin
			if anchor_at_position and has_source_origin
			else source_position + position_or_offset
		)
		layout[new_id] = {
			"x": pasted_position.x,
			"y": pasted_position.y,
		}
	result["steps"] = steps
	result["editorLayout"] = layout
	return {"document": result, "newIds": new_ids, "idMap": id_map}


static func unique_step_id(document: Dictionary, prefix: String) -> String:
	var used := steps_by_id(document)
	var clean_prefix := prefix if ActionStore.valid_id(prefix) else "step"
	var index := 1
	while used.has("%s_%d" % [clean_prefix, index]):
		index += 1
	return "%s_%d" % [clean_prefix, index]


static func default_step(step_type: String, step_id: String) -> Dictionary:
	match step_type:
		"choice":
			return {
				"id": step_id,
				"type": "choice",
				"promptRu": "Выберите ответ",
				"options": [
					{"id": "option_1", "labelRu": "Первый ответ", "next": ""},
					{"id": "option_2", "labelRu": "Второй ответ", "next": ""},
				],
			}
		"set_flag":
			return {"id": step_id, "type": "set_flag", "flag": "new_flag", "value": true, "next": ""}
		"splash":
			return {
				"id": step_id,
				"type": "splash",
				"artId": "",
				"captionRu": "Новая заставка",
				"next": "",
			}
		"end":
			return {"id": step_id, "type": "end"}
	return {
		"id": step_id,
		"type": "dialogue",
		"speaker": "guide",
		"portraitKey": "neutral",
		"nameRu": "Проводник",
		"textRu": "Новая реплика",
		"next": "",
	}


static func merge_simple_editor_fields(base: Dictionary, edited: Dictionary) -> Dictionary:
	## The card editor rebuilds IDs, while the graph owns IDs and edges. Merge only
	## authored labels/text/flags back into matching traversal groups.
	var result := normalized_document(base)
	var base_groups := _simple_groups(result)
	var edited_groups := _simple_groups(edited)
	if base_groups.size() != edited_groups.size():
		return result
	var base_steps := steps_by_id(result)
	var edited_steps := steps_by_id(edited)
	for index in base_groups.size():
		var base_group: Dictionary = base_groups[index]
		var edited_group: Dictionary = edited_groups[index]
		if str(base_group.get("kind", "")) != str(edited_group.get("kind", "")):
			return result
		var base_main_id := str(base_group.get("main", ""))
		var edited_main_id := str(edited_group.get("main", ""))
		if not base_steps.has(base_main_id) or not edited_steps.has(edited_main_id):
			return result
		var base_main: Dictionary = base_steps[base_main_id]
		var edited_main: Dictionary = edited_steps[edited_main_id]
		if str(base_group.get("kind", "")) == "line":
			_copy_fields(base_main, edited_main, ["speaker", "portraitKey", "nameRu", "textRu"])
		else:
			base_main["promptRu"] = str(edited_main.get("promptRu", ""))
			var base_options: Array = base_main.get("options", [])
			var edited_options: Array = edited_main.get("options", [])
			var base_replies: Array = base_group.get("replies", [])
			var edited_replies: Array = edited_group.get("replies", [])
			if base_options.size() != edited_options.size() or base_replies.size() != edited_replies.size():
				return result
			for option_index in base_options.size():
				var base_option: Dictionary = base_options[option_index]
				var edited_option: Dictionary = edited_options[option_index]
				base_option["labelRu"] = str(edited_option.get("labelRu", ""))
				if edited_option.has("setFlags"):
					base_option["setFlags"] = (edited_option.get("setFlags", {}) as Dictionary).duplicate(true)
				else:
					base_option.erase("setFlags")
				base_options[option_index] = base_option
				var base_reply_id := str(base_replies[option_index])
				var edited_reply_id := str(edited_replies[option_index])
				if base_steps.has(base_reply_id) and edited_steps.has(edited_reply_id):
					_copy_fields(base_steps[base_reply_id], edited_steps[edited_reply_id], ["speaker", "portraitKey", "nameRu", "textRu"])
			base_main["options"] = base_options
	result["nameRu"] = str(edited.get("nameRu", result.get("nameRu", "")))
	if edited.has("use"):
		result["use"] = edited.get("use")
	return result


static func validation_errors(document: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for diagnostic in validation_diagnostics(document):
		errors.append(str(diagnostic.get("message", "")))
	return errors


static func validation_diagnostics(document: Dictionary) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	var dialogue_id := str(document.get("id", "")).strip_edges()
	if not ActionStore.valid_id(dialogue_id):
		_add_diagnostic(diagnostics, "ID диалога недопустим.")
	if str(document.get("nameRu", "")).strip_edges().is_empty():
		_add_diagnostic(diagnostics, "Укажите название диалога.")
	var raw_steps: Variant = document.get("steps", [])
	if typeof(raw_steps) != TYPE_ARRAY or raw_steps.is_empty():
		_add_diagnostic(diagnostics, "Диалог должен содержать ноды.")
		return diagnostics
	var ids := {}
	var end_count := 0
	for raw_step in raw_steps:
		if typeof(raw_step) != TYPE_DICTIONARY:
			_add_diagnostic(diagnostics, "Все ноды должны быть объектами.")
			continue
		var step: Dictionary = raw_step
		var step_id := str(step.get("id", "")).strip_edges()
		if not ActionStore.valid_id(step_id):
			_add_diagnostic(diagnostics, "ID ноды '%s' недопустим." % step_id, step_id)
		elif ids.has(step_id):
			_add_diagnostic(diagnostics, "ID ноды '%s' повторяется." % step_id, step_id)
		else:
			ids[step_id] = true
		var kind := str(step.get("type", ""))
		if kind == "end":
			end_count += 1
		if kind not in SUPPORTED_TYPES:
			_add_diagnostic(diagnostics, "Нода %s имеет неподдерживаемый тип %s." % [step_id, kind], step_id)
		if kind == "choice":
			var choice_errors: Array[String] = []
			_validate_choice(step, step_id, choice_errors)
			for message in choice_errors:
				_add_diagnostic(diagnostics, message, step_id)
	if end_count == 0:
		_add_diagnostic(diagnostics, "Добавьте хотя бы одну ноду Конец.")
	var start_id := str(document.get("startStepId", "")).strip_edges()
	if not ids.has(start_id):
		_add_diagnostic(diagnostics, "Стартовая нода '%s' не найдена." % start_id)
	for edge in edges(document):
		var target_id := str(edge.get("to", ""))
		if target_id.is_empty():
			_add_diagnostic(
				diagnostics,
				"Выход %s · %s не подключён." % [edge.get("from", "?"), edge.get("label", "Далее")],
				str(edge.get("from", "")),
				int(edge.get("port", -1)),
			)
		elif not ids.has(target_id):
			_add_diagnostic(
				diagnostics,
				"Выход %s ведёт в отсутствующую ноду %s." % [edge.get("from", "?"), target_id],
				str(edge.get("from", "")),
				int(edge.get("port", -1)),
			)
	if ids.has(start_id):
		var reachable := _reachable_ids(document, start_id)
		for step_id in ids:
			if not reachable.has(step_id):
				_add_diagnostic(diagnostics, "Нода %s недостижима от старта." % step_id, step_id)
	var group_errors: Array[String] = []
	_validate_groups(document, ids, group_errors)
	for message in group_errors:
		_add_diagnostic(diagnostics, message)
	return diagnostics


static func _add_diagnostic(
	diagnostics: Array[Dictionary],
	message: String,
	step_id: String = "",
	port: int = -1,
) -> void:
	diagnostics.append({"message": message, "stepId": step_id, "port": port})


static func _validate_choice(step: Dictionary, step_id: String, errors: Array[String]) -> void:
	var options: Variant = step.get("options", [])
	if typeof(options) != TYPE_ARRAY or options.size() < 2:
		errors.append("Выбор %s должен иметь минимум два ответа." % step_id)
		return
	var option_ids := {}
	for index in options.size():
		if typeof(options[index]) != TYPE_DICTIONARY:
			errors.append("Ответ %d выбора %s повреждён." % [index + 1, step_id])
			continue
		var option: Dictionary = options[index]
		var option_id := str(option.get("id", "")).strip_edges()
		if not ActionStore.valid_id(option_id) or option_ids.has(option_id):
			errors.append("Ответ %d выбора %s имеет пустой/повторный ID." % [index + 1, step_id])
		else:
			option_ids[option_id] = true
		if str(option.get("labelRu", "")).strip_edges().is_empty():
			errors.append("Ответ %d выбора %s не имеет текста." % [index + 1, step_id])


static func _reachable_ids(document: Dictionary, start_id: String) -> Dictionary:
	var by_id := steps_by_id(document)
	var result := {}
	var pending: Array[String] = [start_id]
	while not pending.is_empty():
		var step_id := pending.pop_back()
		if result.has(step_id) or not by_id.has(step_id):
			continue
		result[step_id] = true
		var step: Dictionary = by_id[step_id]
		for edge in edges({"steps": [step]}):
			var target := str(edge.get("to", ""))
			if not target.is_empty() and not result.has(target):
				pending.append(target)
	return result


static func _simple_groups(document: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var by_id := steps_by_id(document)
	var current := str(document.get("startStepId", ""))
	var used := {}
	while by_id.has(current) and not used.has(current):
		used[current] = true
		var step: Dictionary = by_id[current]
		var kind := str(step.get("type", ""))
		if kind == "end":
			break
		if kind == "dialogue":
			result.append({"kind": "line", "main": current})
			current = str(step.get("next", ""))
		elif kind == "choice":
			var replies: Array[String] = []
			var common_next := ""
			for raw_option in step.get("options", []):
				if typeof(raw_option) != TYPE_DICTIONARY:
					return []
				var reply_id := str(raw_option.get("next", ""))
				if not by_id.has(reply_id) or str((by_id[reply_id] as Dictionary).get("type", "")) != "dialogue":
					return []
				replies.append(reply_id)
				var reply_next := str((by_id[reply_id] as Dictionary).get("next", ""))
				if common_next.is_empty():
					common_next = reply_next
				elif common_next != reply_next:
					return []
			result.append({"kind": "choice", "main": current, "replies": replies})
			current = common_next
		else:
			return []
	return result


static func _copy_fields(target: Dictionary, source: Dictionary, fields: Array[String]) -> void:
	for field in fields:
		target[field] = source.get(field, target.get(field, ""))


static func _step_prefix(step_type: String) -> String:
	match step_type:
		"choice": return "choice"
		"splash": return "splash"
		"set_flag": return "flag"
		"end": return "end"
	return "line"


static func _unique_group_id(groups: Array) -> String:
	var used := {}
	for raw_group in groups:
		if typeof(raw_group) == TYPE_DICTIONARY:
			used[str(raw_group.get("id", ""))] = true
	var index := 1
	while used.has("group_%d" % index):
		index += 1
	return "group_%d" % index


static func _validate_groups(document: Dictionary, step_ids: Dictionary, errors: Array[String]) -> void:
	var raw_groups: Variant = document.get("editorGroups", [])
	if typeof(raw_groups) != TYPE_ARRAY:
		errors.append("editorGroups должен быть массивом.")
		return
	var group_ids := {}
	var owners := {}
	for raw_group in raw_groups:
		if typeof(raw_group) != TYPE_DICTIONARY:
			errors.append("Повреждена editor-группа.")
			continue
		var group: Dictionary = raw_group
		var group_id := str(group.get("id", "")).strip_edges()
		if not ActionStore.valid_id(group_id) or group_ids.has(group_id):
			errors.append("Editor-группа имеет пустой/повторный ID.")
		else:
			group_ids[group_id] = true
		if group.has("collapsed") and typeof(group.get("collapsed")) != TYPE_BOOL:
			errors.append("Группа %s имеет неверное collapsed-состояние." % group_id)
		var members: Variant = group.get("members", [])
		if typeof(members) != TYPE_ARRAY or members.is_empty():
			errors.append("Группа %s не содержит нод." % group_id)
			continue
		for raw_member in members:
			var member := str(raw_member)
			if not step_ids.has(member):
				errors.append("Группа %s ссылается на отсутствующую ноду %s." % [group_id, member])
			elif owners.has(member):
				errors.append("Нода %s входит сразу в две группы." % member)
			else:
				owners[member] = group_id
