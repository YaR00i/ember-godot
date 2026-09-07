@tool
class_name EmberDialogueStore
extends RefCounted
## Canonical dialogue projection/writer. Native Godot Resources are preferred;
## legacy JOI scenes/*.json remain a compatibility source until migrated.

const ActionStore = preload("res://addons/ember_import/ember_action_script_store.gd")
const GraphModel = preload("res://addons/ember_import/ember_dialogue_graph_model.gd")
const Catalog = preload("res://scripts/ember_dialogue_catalog.gd")
const USES := ["talk", "shop_intro"]
const MAX_STEPS := 128


static func document(dialogue_id: String) -> Dictionary:
	var clean_id := dialogue_id.strip_edges()
	if not ActionStore.valid_id(clean_id):
		return {}
	return Catalog.document(clean_id)


static func owner(dialogue_id: String) -> String:
	return Catalog.owner(dialogue_id)


static func source_path(dialogue_id: String) -> String:
	return (
		Catalog.native_path(dialogue_id)
		if owner(dialogue_id) == "native"
		else EmberPack.scene_path(dialogue_id)
	)


static func snapshot(dialogue_id: String) -> Dictionary:
	return Catalog.snapshot(dialogue_id)


static func restore_snapshot(snapshot_value: Dictionary) -> int:
	return Catalog.restore(snapshot_value)


static func migrate_to_native(dialogue_id: String) -> int:
	var current := document(dialogue_id)
	if current.is_empty():
		return ERR_DOES_NOT_EXIST
	return Catalog.write_native(current)


static func exists(dialogue_id: String) -> bool:
	return not document(dialogue_id).is_empty()


static func suggested_id(source: String) -> String:
	return ActionStore.suggested_id(source).trim_suffix("_actions") + "_talk"


static func projection(raw: Dictionary) -> Dictionary:
	if raw.is_empty():
		return {"ok": true, "cards": [], "error": ""}
	var steps_by_id := {}
	var raw_steps: Variant = raw.get("steps", [])
	if typeof(raw_steps) != TYPE_ARRAY:
		return _projection_error("steps должен быть массивом.")
	for raw_step in raw_steps:
		if typeof(raw_step) != TYPE_DICTIONARY:
			return _projection_error("Все шаги должны быть объектами.")
		var step: Dictionary = raw_step
		var step_id := str(step.get("id", "")).strip_edges()
		if step_id.is_empty() or steps_by_id.has(step_id):
			return _projection_error("ID шагов пусты или повторяются.")
		steps_by_id[step_id] = step
	var current := str(raw.get("startStepId", "")).strip_edges()
	var cards: Array[Dictionary] = []
	var used := {}
	var reached_end := false
	for _guard in range(MAX_STEPS):
		if not steps_by_id.has(current):
			return _projection_error("Маршрут ведёт в отсутствующий шаг %s." % current)
		if used.has(current):
			return _projection_error("Циклический диалог пока не редактируется карточками.")
		var step: Dictionary = steps_by_id[current]
		used[current] = true
		match str(step.get("type", "")):
			"end":
				if step.has("nextEventId"):
					return _projection_error("end.nextEventId требует полного graph editor.")
				reached_end = true
				break
			"dialogue":
				var special := _dialogue_special_field(step)
				if not special.is_empty():
					return _projection_error("Шаг %s использует %s; нужен полный VN editor." % [current, special])
				cards.append({
					"kind": "line",
					"speaker": str(step.get("speaker", "")),
					"portraitKey": str(step.get("portraitKey", "neutral")),
					"nameRu": str(step.get("nameRu", step.get("speaker", ""))),
					"textRu": str(step.get("textRu", "")),
				})
				current = str(step.get("next", ""))
			"choice":
				if step.has("actors") or step.has("bgArtId"):
					return _projection_error("Выбор %s использует stage/background." % current)
				var options: Variant = step.get("options", [])
				if typeof(options) != TYPE_ARRAY or options.size() < 2:
					return _projection_error("Выбор %s должен иметь минимум два ответа." % current)
				var projected_options: Array[Dictionary] = []
				var common_next := ""
				for raw_option in options:
					if typeof(raw_option) != TYPE_DICTIONARY:
						return _projection_error("Ответ выбора %s повреждён." % current)
					var option: Dictionary = raw_option
					var reply_id := str(option.get("next", ""))
					if not steps_by_id.has(reply_id):
						return _projection_error("Ответ ведёт в отсутствующий шаг %s." % reply_id)
					var reply: Dictionary = steps_by_id[reply_id]
					if str(reply.get("type", "")) != "dialogue" or not _dialogue_special_field(reply).is_empty():
						return _projection_error("Каждый ответ пока должен вести в одну простую реплику.")
					if used.has(reply_id):
						return _projection_error("Ответные реплики не должны использоваться повторно.")
					used[reply_id] = true
					var set_flags: Dictionary = option.get("setFlags", {}) if typeof(option.get("setFlags", {})) == TYPE_DICTIONARY else {}
					if set_flags.size() > 1:
						return _projection_error("Первый карточный editor поддерживает один флаг на ответ.")
					var flag_id := str(set_flags.keys()[0]) if not set_flags.is_empty() else ""
					projected_options.append({
						"labelRu": str(option.get("labelRu", "")),
						"speaker": str(reply.get("speaker", "")),
						"portraitKey": str(reply.get("portraitKey", "neutral")),
						"nameRu": str(reply.get("nameRu", reply.get("speaker", ""))),
						"textRu": str(reply.get("textRu", "")),
						"flag": flag_id,
						"value": set_flags.get(flag_id, true),
					})
					var reply_next := str(reply.get("next", ""))
					if common_next.is_empty():
						common_next = reply_next
					elif common_next != reply_next:
						return _projection_error("Ветки выбора должны сходиться в один следующий шаг.")
				cards.append({"kind": "choice", "promptRu": str(step.get("promptRu", "")), "options": projected_options})
				current = common_next
			_:
				return _projection_error("Шаг %s имеет тип %s; карточный editor его не меняет." % [current, step.get("type", "")])
	if not reached_end:
		return _projection_error("Диалог превышает безопасный предел %d шагов." % MAX_STEPS)
	if used.size() != steps_by_id.size():
		return _projection_error("В сцене есть несвязанные или вложенные ветки; нужен graph editor.")
	return {"ok": true, "cards": cards, "error": ""}


static func document_from_cards(header: Dictionary, cards: Array[Dictionary]) -> Dictionary:
	var main_ids: Array[String] = []
	for index in cards.size():
		main_ids.append("choice_%d" % (index + 1) if str(cards[index].get("kind", "")) == "choice" else "line_%d" % (index + 1))
	var steps: Array[Dictionary] = []
	var layout := {}
	for index in cards.size():
		var card := cards[index]
		var step_id := main_ids[index]
		var next_id := main_ids[index + 1] if index + 1 < main_ids.size() else "end"
		layout[step_id] = {"x": 40 + index * 280, "y": 80}
		if str(card.get("kind", "")) == "choice":
			var options: Array[Dictionary] = []
			var raw_options: Array = card.get("options", [])
			for option_index in raw_options.size():
				var option: Dictionary = raw_options[option_index]
				var reply_id := "%s_reply_%d" % [step_id, option_index + 1]
				var option_value := {
					"id": "option_%d" % (option_index + 1),
					"labelRu": str(option.get("labelRu", "")).strip_edges(),
					"next": reply_id,
				}
				var flag_id := str(option.get("flag", "")).strip_edges()
				if not flag_id.is_empty():
					option_value["setFlags"] = {flag_id: option.get("value", true)}
				options.append(option_value)
				steps.append(_dialogue_step(reply_id, option, next_id))
				layout[reply_id] = {"x": 40 + (index + 1) * 280, "y": 20 + option_index * 140}
			steps.append({"id": step_id, "type": "choice", "promptRu": str(card.get("promptRu", "")).strip_edges(), "options": options})
		else:
			steps.append(_dialogue_step(step_id, card, next_id))
	steps.append({"id": "end", "type": "end"})
	layout["end"] = {"x": 40 + cards.size() * 280, "y": 80}
	return {
		"id": str(header.get("id", "")).strip_edges(),
		"nameRu": str(header.get("nameRu", "")).strip_edges(),
		"use": str(header.get("use", "talk")) if str(header.get("use", "talk")) in USES else "talk",
		"startStepId": main_ids[0] if not main_ids.is_empty() else "end",
		"steps": steps,
		"editorLayout": layout,
	}


static func validation_errors(document_value: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var dialogue_id := str(document_value.get("id", ""))
	if not ActionStore.valid_id(dialogue_id):
		errors.append("ID: только a-z, 0-9, _ и -, первый символ — буква или цифра.")
	if str(document_value.get("nameRu", "")).strip_edges().is_empty():
		errors.append("Укажите название диалога.")
	if str(document_value.get("use", "")) not in USES:
		errors.append("Первый редактор поддерживает только talk и shop_intro.")
	var projected := projection(document_value)
	if not bool(projected.get("ok", false)):
		errors.append(str(projected.get("error", "Диалог не поддерживается.")))
	var cards: Array = projected.get("cards", [])
	if cards.is_empty():
		errors.append("Добавьте хотя бы одну реплику или выбор.")
	for card_index in cards.size():
		var card: Dictionary = cards[card_index]
		if str(card.get("kind", "")) == "line":
			_validate_line(card, "Карточка %d" % (card_index + 1), errors)
		else:
			if str(card.get("promptRu", "")).strip_edges().is_empty():
				errors.append("Выбор %d: задайте вопрос." % (card_index + 1))
			var options: Array = card.get("options", [])
			if options.size() < 2:
				errors.append("Выбор %d: нужно минимум два ответа." % (card_index + 1))
			for option_index in options.size():
				var option: Dictionary = options[option_index]
				if str(option.get("labelRu", "")).strip_edges().is_empty():
					errors.append("Выбор %d, ответ %d: укажите текст кнопки." % [card_index + 1, option_index + 1])
				_validate_line(option, "Выбор %d, ответ %d" % [card_index + 1, option_index + 1], errors)
				var flag_id := str(option.get("flag", "")).strip_edges()
				if not flag_id.is_empty() and not _is_flag_value(option.get("value", null)):
					errors.append("Выбор %d, ответ %d: значение флага недопустимо." % [card_index + 1, option_index + 1])
	return errors


static func write_document(document_value: Dictionary) -> int:
	var errors := validation_errors(document_value)
	if not errors.is_empty():
		push_error("Ember dialogue: %s" % " ".join(errors))
		return ERR_INVALID_DATA
	return _write_canonical(document_value)


static func graph_validation_errors(document_value: Dictionary) -> Array[String]:
	return GraphModel.validation_errors(document_value)


static func write_graph_document(document_value: Dictionary) -> int:
	var errors := graph_validation_errors(document_value)
	if not errors.is_empty():
		push_error("Ember dialogue graph: %s" % " ".join(errors))
		return ERR_INVALID_DATA
	return _write_canonical(document_value)


static func _write_canonical(document_value: Dictionary) -> int:
	var dialogue_id := str(document_value.get("id", ""))
	# Existing legacy scenes keep their owner until the explicit migration
	# action. New documents and already migrated scenes are native Resources.
	return (
		Catalog.write_legacy(document_value)
		if owner(dialogue_id) == "legacy"
		else Catalog.write_native(document_value)
	)


static func delete_document(dialogue_id: String) -> int:
	if not ActionStore.valid_id(dialogue_id):
		return ERR_INVALID_PARAMETER
	var native_error := Catalog.delete_native(dialogue_id)
	return native_error if native_error != OK else Catalog.delete_legacy(dialogue_id)


static func _dialogue_step(step_id: String, value: Dictionary, next_id: String) -> Dictionary:
	return {
		"id": step_id,
		"type": "dialogue",
		"speaker": str(value.get("speaker", "")).strip_edges(),
		"portraitKey": str(value.get("portraitKey", "neutral")).strip_edges(),
		"nameRu": str(value.get("nameRu", "")).strip_edges(),
		"textRu": str(value.get("textRu", "")).strip_edges(),
		"next": next_id,
	}


static func _dialogue_special_field(step: Dictionary) -> String:
	for field in ["actors", "bgArtId", "portraitSide"]:
		if step.has(field):
			return field
	return ""


static func _validate_line(value: Dictionary, prefix: String, errors: Array[String]) -> void:
	if str(value.get("speaker", "")).strip_edges().is_empty():
		errors.append("%s: укажите speaker ID." % prefix)
	if str(value.get("nameRu", "")).strip_edges().is_empty():
		errors.append("%s: укажите отображаемое имя." % prefix)
	if str(value.get("textRu", "")).strip_edges().is_empty():
		errors.append("%s: реплика пустая." % prefix)


static func _is_flag_value(value: Variant) -> bool:
	return (
		typeof(value) in [TYPE_BOOL, TYPE_STRING, TYPE_INT]
		or (typeof(value) == TYPE_FLOAT and is_finite(float(value)))
	)


static func _projection_error(message: String) -> Dictionary:
	return {"ok": false, "cards": [], "error": message}
