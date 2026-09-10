extends RefCounted
## Pure status-state rules used by the single combat resolver. Authored names,
## kind and visuals come from StatusCatalog; battle snapshots remain dictionaries.

const StatusCatalog := preload("res://scripts/prototypes/ember_combat_status_catalog.gd")


static func definition(status_id: String) -> Dictionary:
	var authored := StatusCatalog.definition(status_id)
	return authored if not authored.is_empty() else {
		"id": status_id,
		"name": status_id,
		"kind": "debuff",
		"icon": "●",
		"color": Color.WHITE,
	}


static func display_name(status_id: String) -> String:
	return str(definition(status_id).get("name", status_id))


static func has(unit: Dictionary, status_id: String) -> bool:
	return int((unit.get("statuses", {}) as Dictionary).get(status_id, 0)) > 0


static func set_status(
	resolved: Dictionary,
	unit_id: String,
	status_id: String,
	duration: int,
) -> void:
	var all_statuses: Dictionary = resolved.get("setStatuses", {})
	var statuses: Dictionary = all_statuses.get(unit_id, {})
	statuses[status_id] = maxi(int(statuses.get(status_id, 0)), maxi(1, duration))
	all_statuses[unit_id] = statuses
	resolved["setStatuses"] = all_statuses


static func set_hostile_status(
	resolved: Dictionary,
	target: Dictionary,
	status_id: String,
	duration: int,
) -> bool:
	var resistance := int(
		(target.get("statusResistances", {}) as Dictionary).get(status_id, 0)
	)
	var applied_duration := maxi(0, duration - resistance)
	if applied_duration <= 0:
		(resolved.get("notes", []) as Array).append(
			"Устойчивость цели блокирует эффект %s." % display_name(status_id)
		)
		return false
	set_status(resolved, str(target.get("id", "")), status_id, applied_duration)
	if resistance > 0:
		(resolved.get("notes", []) as Array).append(
			"Устойчивость цели сокращает %s до %d хода." % [
				display_name(status_id), applied_duration,
			]
		)
	return true


static func remove_status(resolved: Dictionary, unit_id: String, status_id: String) -> void:
	var all_statuses: Dictionary = resolved.get("removeStatuses", {})
	var statuses: Array = all_statuses.get(unit_id, [])
	if status_id not in statuses:
		statuses.append(status_id)
	all_statuses[unit_id] = statuses
	resolved["removeStatuses"] = all_statuses


static func decay(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var result := {}
	for raw_id in source:
		var duration := int(source[raw_id]) - 1
		if duration > 0:
			result[str(raw_id)] = duration
	return result


static func duration_after_preview(
	state: Dictionary,
	resolved: Dictionary,
	unit_id: String,
	status_id: String,
) -> int:
	var pending: Dictionary = (resolved.get("setStatuses", {}) as Dictionary).get(unit_id, {})
	if pending.has(status_id):
		return int(pending[status_id])
	if status_id in (resolved.get("removeStatuses", {}) as Dictionary).get(unit_id, []):
		return 0
	var units: Dictionary = state.get("units", {})
	var unit: Dictionary = units.get(unit_id, {})
	return int((unit.get("statuses", {}) as Dictionary).get(status_id, 0))
