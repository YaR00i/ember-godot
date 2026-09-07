@tool
class_name EmberActionScriptStore
extends RefCounted
## Canonical action-chain projection/writer. Native Godot Resources are
## preferred; legacy JOI scripts/*.json remain fallback until migrated.

const Catalog = preload("res://scripts/ember_action_catalog.gd")

const STEP_TYPES := [
	"talk",
	"give_item",
	"set_flag",
	"wait",
	"open_shop",
	"change_map",
	"start_battle",
	"run_script",
]


static func document(script_id: String) -> Dictionary:
	var clean_id := script_id.strip_edges()
	if not valid_id(clean_id):
		return {}
	return Catalog.document(clean_id)


static func owner(script_id: String) -> String:
	return Catalog.owner(script_id)


static func source_path(script_id: String) -> String:
	return (
		Catalog.native_path(script_id)
		if owner(script_id) == "native"
		else EmberPack.script_path(script_id)
	)


static func snapshot(script_id: String) -> Dictionary:
	return Catalog.snapshot(script_id)


static func restore_snapshot(snapshot_value: Dictionary) -> int:
	return Catalog.restore(snapshot_value)


static func migrate_to_native(script_id: String) -> int:
	var current := document(script_id)
	if current.is_empty():
		return ERR_DOES_NOT_EXIST
	return Catalog.write_native(current)


static func exists(script_id: String) -> bool:
	return valid_id(script_id.strip_edges()) and not Catalog.owner(script_id).is_empty()


static func valid_id(script_id: String) -> bool:
	if script_id.is_empty():
		return false
	var expression := RegEx.new()
	if expression.compile("^[a-z0-9][a-z0-9_-]*$") != OK:
		return false
	return expression.search(script_id) != null


static func suggested_id(source: String) -> String:
	var clean := source.strip_edges().to_lower()
	var expression := RegEx.new()
	expression.compile("[^a-z0-9_-]+")
	clean = expression.sub(clean, "_", true).strip_edges().trim_prefix("_").trim_suffix("_")
	if clean.is_empty() or not clean[0].is_valid_int():
		return "%s_actions" % (clean if not clean.is_empty() else "object")
	return "object_%s_actions" % clean


static func default_step(step_type: String) -> Dictionary:
	match step_type:
		"talk": return {"type": step_type, "dialogueId": ""}
		"give_item": return {"type": step_type, "itemId": "", "count": 1}
		"set_flag": return {"type": step_type, "flag": "", "value": true}
		"wait": return {"type": step_type, "sec": 0.0}
		"open_shop": return {"type": step_type, "shopId": ""}
		"change_map": return {"type": step_type, "targetMapId": "", "targetRegionId": ""}
		"start_battle": return {"type": step_type, "encounterId": ""}
		"run_script": return {"type": step_type, "scriptId": ""}
	return {"type": step_type}


static func normalized_document(raw: Dictionary) -> Dictionary:
	var script_id := str(raw.get("id", "")).strip_edges()
	var result := raw.duplicate(true)
	result["id"] = script_id
	result["nameRu"] = str(raw.get("nameRu", script_id)).strip_edges()
	var steps: Array = []
	var raw_steps: Variant = raw.get("steps", [])
	if typeof(raw_steps) == TYPE_ARRAY:
		for raw_step in raw_steps:
			if typeof(raw_step) == TYPE_DICTIONARY:
				steps.append(_normalized_step(raw_step))
	result["steps"] = steps
	return result


static func validation_errors(raw: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for diagnostic in validation_diagnostics(raw):
		errors.append(str(diagnostic.get("message", "")))
	return errors


static func validation_diagnostics(raw: Dictionary) -> Array[Dictionary]:
	var document_value := normalized_document(raw)
	var diagnostics: Array[Dictionary] = []
	var script_id := str(document_value.get("id", ""))
	if not valid_id(script_id):
		_add_diagnostic(diagnostics, "ID: только a-z, 0-9, _ и -, первый символ — буква или цифра.")
	if str(document_value.get("nameRu", "")).is_empty():
		_add_diagnostic(diagnostics, "Укажите понятное название цепочки.")
	var steps: Array = document_value.get("steps", [])
	if steps.is_empty():
		_add_diagnostic(diagnostics, "Добавьте хотя бы один шаг.")
	for index in steps.size():
		var step: Dictionary = steps[index]
		var step_type := str(step.get("type", ""))
		if step_type not in STEP_TYPES:
			_add_diagnostic(diagnostics, "Шаг %d: неподдерживаемый тип %s." % [index + 1, step_type], index)
			continue
		match step_type:
			"talk":
				var dialogue_id := str(step.get("dialogueId", ""))
				if dialogue_id.is_empty():
					_add_diagnostic(diagnostics, "Шаг %d: выберите диалог." % [index + 1], index)
				elif dialogue_id not in EmberInteractionContent.dialogue_ids():
					_add_diagnostic(diagnostics, "Шаг %d: диалог %s не найден." % [index + 1, dialogue_id], index)
			"give_item":
				var item_id := str(step.get("itemId", ""))
				if item_id.is_empty():
					_add_diagnostic(diagnostics, "Шаг %d: выберите предмет." % [index + 1], index)
				elif item_id not in EmberInteractionContent.item_ids():
					_add_diagnostic(diagnostics, "Шаг %d: предмет %s не найден." % [index + 1, item_id], index)
			"set_flag":
				if str(step.get("flag", "")).is_empty():
					_add_diagnostic(diagnostics, "Шаг %d: укажите флаг." % [index + 1], index)
			"open_shop":
				var shop_id := str(step.get("shopId", ""))
				if shop_id.is_empty():
					_add_diagnostic(diagnostics, "Шаг %d: выберите магазин." % [index + 1], index)
				elif shop_id not in EmberInteractionContent.shop_ids():
					_add_diagnostic(diagnostics, "Шаг %d: магазин %s не найден." % [index + 1, shop_id], index)
			"change_map":
				var target_map_id := str(step.get("targetMapId", ""))
				var target_region_id := str(step.get("targetRegionId", ""))
				if target_map_id.is_empty():
					_add_diagnostic(diagnostics, "Шаг %d: выберите целевую карту." % [index + 1], index)
				elif target_map_id not in EmberInteractionContent.map_ids():
					_add_diagnostic(diagnostics, "Шаг %d: карта %s не найдена." % [index + 1, target_map_id], index)
				elif not target_region_id.is_empty() and target_region_id not in EmberInteractionContent.region_ids(target_map_id):
					_add_diagnostic(diagnostics, "Шаг %d: точка %s не найдена на карте %s." % [index + 1, target_region_id, target_map_id], index)
				if index != steps.size() - 1:
					_add_diagnostic(diagnostics, "Шаг %d: смена карты должна завершать цепочку." % [index + 1], index)
			"start_battle":
				var encounter_id := str(step.get("encounterId", ""))
				if encounter_id.is_empty():
					_add_diagnostic(diagnostics, "Шаг %d: выберите боевую встречу." % [index + 1], index)
				elif EmberEncounterCatalog.definition(encounter_id) == null:
					_add_diagnostic(diagnostics, "Шаг %d: встреча %s не найдена." % [index + 1, encounter_id], index)
				if index != steps.size() - 1:
					_add_diagnostic(diagnostics, "Шаг %d: бой должен завершать текущую цепочку. Продолжение задаётся в ресурсе встречи." % [index + 1], index)
			"run_script":
				var nested_id := str(step.get("scriptId", ""))
				if nested_id.is_empty():
					_add_diagnostic(diagnostics, "Шаг %d: выберите вложенную цепочку." % [index + 1], index)
				elif nested_id == script_id:
					_add_diagnostic(diagnostics, "Шаг %d: цепочка не может запускать саму себя." % [index + 1], index)
				elif nested_id not in EmberInteractionContent.action_script_ids():
					_add_diagnostic(diagnostics, "Шаг %d: цепочка %s не найдена." % [index + 1, nested_id], index)
	return diagnostics


static func _add_diagnostic(diagnostics: Array[Dictionary], message: String, step_index: int = -1) -> void:
	diagnostics.append({
		"message": message,
		"stepIndex": step_index,
		"stepId": "step_%d" % (step_index + 1) if step_index >= 0 else "",
		"port": -1,
	})


static func write_document(raw: Dictionary) -> int:
	var errors := validation_errors(raw)
	if not errors.is_empty():
		push_error("Ember action chain: %s" % " ".join(errors))
		return ERR_INVALID_DATA
	var value := normalized_document(raw)
	# Existing legacy scripts keep their owner until explicit migration. New
	# documents and already migrated chains are native Resources.
	return (
		Catalog.write_legacy(value)
		if owner(str(value.id)) == "legacy"
		else Catalog.write_native(value)
	)


static func delete_document(script_id: String) -> int:
	var clean_id := script_id.strip_edges()
	if not valid_id(clean_id):
		return ERR_INVALID_PARAMETER
	var native_error := Catalog.delete_native(clean_id)
	return native_error if native_error != OK else Catalog.delete_legacy(clean_id)


static func _normalized_step(raw: Dictionary) -> Dictionary:
	var step_type := str(raw.get("type", "")).strip_edges()
	match step_type:
		"talk":
			return {"type": step_type, "dialogueId": str(raw.get("dialogueId", "")).strip_edges()}
		"give_item":
			return {
				"type": step_type,
				"itemId": str(raw.get("itemId", "")).strip_edges(),
				"count": maxi(1, roundi(float(raw.get("count", 1)))),
			}
		"set_flag":
			var value: Variant = raw.get("value", true)
			if typeof(value) not in [TYPE_BOOL, TYPE_STRING, TYPE_INT, TYPE_FLOAT]:
				value = true
			return {"type": step_type, "flag": str(raw.get("flag", "")).strip_edges(), "value": value}
		"wait":
			return {"type": step_type, "sec": maxf(0.0, float(raw.get("sec", 0.0)))}
		"open_shop":
			return {"type": step_type, "shopId": str(raw.get("shopId", "")).strip_edges()}
		"change_map":
			var result := {
				"type": step_type,
				"targetMapId": str(raw.get("targetMapId", "")).strip_edges(),
			}
			var target_region_id := str(raw.get("targetRegionId", "")).strip_edges()
			if not target_region_id.is_empty():
				result["targetRegionId"] = target_region_id
			return result
		"start_battle":
			return {
				"type": step_type,
				"encounterId": str(raw.get("encounterId", "")).strip_edges(),
			}
		"run_script":
			return {"type": step_type, "scriptId": str(raw.get("scriptId", "")).strip_edges()}
	return raw.duplicate(true)
