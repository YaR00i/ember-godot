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
	current: Dictionary = {},
) -> void:
	var authored := StatusCatalog.resource(status_id)
	var errors: Array = authored.call("validation_errors") if authored != null else ["Статус отсутствует в каталоге."]
	if not errors.is_empty():
		resolved["ok"] = false
		resolved["error"] = "Статус %s: %s" % [status_id, " ".join(errors)]
		return
	var all_statuses: Dictionary = resolved.get("setStatuses", {})
	var statuses: Dictionary = all_statuses.get(unit_id, {})
	var pending := statuses.has(status_id)
	var removed: Array = (resolved.get("removeStatuses", {}) as Dictionary).get(unit_id, [])
	var existing := int(statuses.get(status_id, current.get(status_id, 0))) if status_id not in removed else 0
	var incoming := duration_for(status_id, duration)
	var rules := definition(status_id)
	var next := incoming
	match str(rules.get("reapply", "refresh")):
		"refresh": next = maxi(existing, incoming) if pending else incoming
		"keep_longest": next = maxi(existing, incoming)
		"extend": next = mini(int(rules.get("maxDuration", 12)), existing + incoming)
		"ignore": next = existing if existing > 0 else incoming
	statuses[status_id] = maxi(1, next)
	all_statuses[unit_id] = statuses
	resolved["setStatuses"] = all_statuses
	if status_id in removed:
		removed.erase(status_id)


static func set_hostile_status(
	resolved: Dictionary,
	target: Dictionary,
	status_id: String,
	duration: int,
) -> bool:
	var resistance := int(
		(target.get("statusResistances", {}) as Dictionary).get(status_id, 0)
	)
	var applied_duration := maxi(0, duration_for(status_id, duration) - resistance)
	if applied_duration <= 0:
		(resolved.get("notes", []) as Array).append(
			"Устойчивость цели блокирует эффект %s." % display_name(status_id)
		)
		return false
	set_status(resolved, str(target.get("id", "")), status_id, applied_duration, target.get("statuses", {}))
	if resistance > 0:
		(resolved.get("notes", []) as Array).append(
			"Устойчивость цели сокращает %s до %d хода." % [
				display_name(status_id), applied_duration,
			]
		)
	return bool(resolved.get("ok", true))


static func remove_status(resolved: Dictionary, unit_id: String, status_id: String, cancel_pending := false) -> void:
	var all_statuses: Dictionary = resolved.get("removeStatuses", {})
	var statuses: Array = all_statuses.get(unit_id, [])
	if status_id not in statuses:
		statuses.append(status_id)
	all_statuses[unit_id] = statuses
	resolved["removeStatuses"] = all_statuses
	if cancel_pending:
		var pending: Dictionary = (resolved.get("setStatuses", {}) as Dictionary).get(unit_id, {})
		pending.erase(status_id)


static func duration_for(status_id: String, explicit_duration: int) -> int:
	return maxi(1, explicit_duration if explicit_duration > 0 else int(definition(status_id).get("defaultDuration", 2)))


static func power_bonus(unit: Dictionary) -> int:
	var result := 0
	for status_id in unit.get("statuses", {}):
		if has(unit, str(status_id)): result += int(definition(str(status_id)).get("powerBonus", 0))
	return result


static func damage_amount(unit: Dictionary, amount: int, outgoing: bool) -> int:
	var multiplier := 1.0
	var ids: Array = (unit.get("statuses", {}) as Dictionary).keys()
	ids.sort()
	for status_id in ids:
		if has(unit, str(status_id)):
			multiplier *= float(definition(str(status_id)).get("outgoingDamagePercent" if outgoing else "incomingDamagePercent", 100)) / 100.0
	return maxi(0, ceili(minf(float(amount) * multiplier, 2147483647.0)))


static func remove_after_damage(resolved: Dictionary, unit: Dictionary, amount: int) -> void:
	if amount <= 0: return
	for status_id in unit.get("statuses", {}):
		if has(unit, str(status_id)) and bool(definition(str(status_id)).get("removeOnDamage", false)):
			remove_status(resolved, str(unit.get("id", "")), str(status_id), true)


static func content_hash() -> int:
	var signatures := PackedStringArray()
	for status in StatusCatalog.resources(): signatures.append(str(status.call("content_signature")))
	return hash(signatures)


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
