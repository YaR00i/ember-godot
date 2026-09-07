class_name EmberActionScript
extends RefCounted
## Read-only action-list queue builder over the existing JOI scripts/scenes.
## Runtime side effects stay in EmberExploreState and EmberInteractionUi.

const MAX_DEPTH := 8


static func queue_for(ref_id: String) -> Dictionary:
	var clean_id := ref_id.strip_edges()
	if clean_id.is_empty():
		return {"ok": false, "steps": [], "error": "Пустой scriptId"}
	var steps: Array[Dictionary] = []
	var found := _append_ref(clean_id, steps, {}, 0)
	return {
		"ok": found,
		"steps": steps,
		"error": "" if found else "Сценарий не найден: %s" % clean_id,
	}


static func _append_ref(
	ref_id: String,
	result: Array[Dictionary],
	visiting: Dictionary,
	depth: int,
) -> bool:
	if depth > MAX_DEPTH or visiting.has(ref_id):
		return false
	var resolved := EmberInteractionContent.resolve_script_ref(ref_id)
	if resolved.is_empty():
		return false
	if str(resolved.get("kind", "")) == "scene":
		result.append({"type": "talk", "dialogueId": ref_id})
		return true
	var data: Dictionary = resolved.get("data", {})
	var raw_steps: Variant = data.get("steps", [])
	if typeof(raw_steps) != TYPE_ARRAY:
		return true
	var nested_visiting := visiting.duplicate()
	nested_visiting[ref_id] = true
	for raw_step in raw_steps:
		if typeof(raw_step) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = raw_step
		if str(step.get("type", "")) == "run_script":
			var nested_id := str(step.get("scriptId", "")).strip_edges()
			if not nested_id.is_empty():
				_append_ref(nested_id, result, nested_visiting, depth + 1)
			continue
		var normalized := _normalize_step(step)
		if not normalized.is_empty():
			result.append(normalized)
	return true


static func _normalize_step(step: Dictionary) -> Dictionary:
	match str(step.get("type", "")):
		"talk":
			var dialogue_id := str(step.get("dialogueId", "")).strip_edges()
			return {"type": "talk", "dialogueId": dialogue_id} if not dialogue_id.is_empty() else {}
		"give_item":
			var item_id := str(step.get("itemId", "")).strip_edges()
			if item_id.is_empty():
				return {}
			var count := maxi(1, roundi(float(step.get("count", 1))))
			return {"type": "give_item", "itemId": item_id, "count": count}
		"set_flag":
			var flag_id := str(step.get("flag", "")).strip_edges()
			var value: Variant = step.get("value", null)
			if flag_id.is_empty() or not _is_flag_value(value):
				return {}
			return {"type": "set_flag", "flag": flag_id, "value": value}
		"wait":
			# Normalization preserves authored timing. EmberInteractionUi owns the
			# asynchronous pause so the resolver remains a pure content boundary.
			return {"type": "wait", "sec": maxf(0.0, float(step.get("sec", 0.0)))}
		"open_shop":
			var shop_id := str(step.get("shopId", "")).strip_edges()
			return {"type": "open_shop", "shopId": shop_id} if not shop_id.is_empty() else {}
		"change_map":
			var target_map_id := str(step.get("targetMapId", "")).strip_edges()
			if target_map_id.is_empty():
				return {}
			var result := {"type": "change_map", "targetMapId": target_map_id}
			var target_region_id := str(step.get("targetRegionId", "")).strip_edges()
			if not target_region_id.is_empty():
				result["targetRegionId"] = target_region_id
			return result
		"start_battle":
			var encounter_id := str(step.get("encounterId", "")).strip_edges()
			return {"type": "start_battle", "encounterId": encounter_id} if not encounter_id.is_empty() else {}
	return {}


static func _is_flag_value(value: Variant) -> bool:
	return (
		typeof(value) == TYPE_BOOL
		or typeof(value) == TYPE_STRING
		or typeof(value) == TYPE_INT
		or (typeof(value) == TYPE_FLOAT and is_finite(float(value)))
	)
