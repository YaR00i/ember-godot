class_name EmberQuestState
extends RefCounted
## Pure quest-marker projection shared by runtime, Inspector and tests.
## Mirrors JOI resolveQuestMarkerStatus: script_id is the progress flag key.

const STATUSES := ["available", "active", "done"]
const MARKER_FULL_SIZE_DISTANCE := 140.0
const MARKER_FADE_DISTANCE := 190.0
const MARKER_HIDE_DISTANCE := 300.0
const MARKER_MIN_SCALE := 0.4
const MARKER_ICON_PATHS := {
	"quest_available": "res://assets/world_markers/quest_available.svg",
	"quest_active": "res://assets/world_markers/quest_active.svg",
	"quest_done": "res://assets/world_markers/quest_done.svg",
}


static func resolve_status(authored: String, flag_id: String, flags: Dictionary) -> String:
	var from_flag: Variant = flags.get(flag_id, null) if not flag_id.is_empty() else null
	if typeof(from_flag) == TYPE_STRING and str(from_flag) in STATUSES:
		return str(from_flag)
	if from_flag == true:
		return "done"
	if authored in STATUSES:
		return authored
	return "available"


static func resolve_icon_id(authored: String, status: String) -> String:
	var clean := authored.strip_edges()
	# The three stock quest icons describe state, not an instance override. An
	# authored custom icon stays fixed; a stock one follows the event projection.
	if not clean.is_empty() and clean not in [
		"quest", "quest_available", "quest_active", "quest_done",
	]:
		return clean
	return "quest_%s" % status


static func marker_projection(
	quest: Dictionary,
	action_steps: Array,
	authored_status := "available",
) -> Dictionary:
	## Derives the world-marker role from the existing quest flags written by
	## this object's action chain. No marker role/key is serialized separately.
	var fallback_status := str(quest.get("status", authored_status))
	if fallback_status not in STATUSES:
		fallback_status = "available"
	var fallback := {
		"role": "summary",
		"objectiveId": "",
		"objectiveText": "",
		"status": fallback_status,
		"authoringStatus": fallback_status,
		"visible": true,
		"reason": "summary",
		"recognized": false,
	}
	if quest.is_empty():
		return fallback
	var status_flag_id := str(quest.get("statusFlagId", "")).strip_edges()
	var objectives_by_flag := {}
	for raw_objective in quest.get("objectives", []):
		if typeof(raw_objective) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = raw_objective
		var flag_id := str(objective.get("flagId", "")).strip_edges()
		if not flag_id.is_empty():
			objectives_by_flag[flag_id] = objective
	var roles: Array[Dictionary] = []
	for raw_step in action_steps:
		if typeof(raw_step) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = raw_step
		if str(step.get("type", "")) != "set_flag":
			continue
		var flag_id := str(step.get("flag", "")).strip_edges()
		var value: Variant = step.get("value", null)
		if not status_flag_id.is_empty() and flag_id == status_flag_id:
			if typeof(value) == TYPE_STRING and str(value) == "active":
				roles.append({"role": "start"})
			elif (
				(typeof(value) == TYPE_BOOL and bool(value))
				or (typeof(value) == TYPE_STRING and str(value) == "done")
			):
				roles.append({"role": "complete"})
			continue
		if objectives_by_flag.has(flag_id) and _completion_value(value):
			var objective: Dictionary = objectives_by_flag[flag_id]
			roles.append({
				"role": "objective",
				"objectiveId": str(objective.get("id", "")),
			})
	if roles.is_empty():
		return fallback

	var explicit_status := str(quest.get("explicitStatus", fallback_status))
	var completed := int(quest.get("completed", 0))
	var quest_started := explicit_status != "available" or completed > 0
	var start_role := _first_role(roles, "start")
	if not start_role.is_empty() and explicit_status == "available" and completed == 0:
		return _marker_result("start", "", "", "available", true, "quest_available")

	for role in roles:
		if str(role.get("role", "")) != "objective":
			continue
		var objective := _objective_by_id(
			quest.get("objectives", []), str(role.get("objectiveId", ""))
		)
		if objective.is_empty():
			continue
		var objective_id := str(objective.get("id", ""))
		var objective_text := str(objective.get("textRu", objective_id))
		if bool(objective.get("done", false)):
			continue
		if not quest_started:
			return _marker_result(
				"objective", objective_id, objective_text, "active", false, "quest_not_started"
			)
		if bool(objective.get("locked", false)):
			return _marker_result(
				"objective", objective_id, objective_text, "active", false, "prerequisites"
			)
		if bool(objective.get("available", false)):
			var finishes_quest := _is_last_required_objective(quest, objective_id)
			return _marker_result(
				"objective",
				objective_id,
				objective_text,
				"done" if finishes_quest else "active",
				true,
				"final_objective" if finishes_quest else "current_objective",
			)

	var complete_role := _first_role(roles, "complete")
	if not complete_role.is_empty():
		var ready := bool(quest.get("objectivesComplete", false))
		if int(quest.get("required", 0)) == 0:
			ready = explicit_status == "active"
		return _marker_result(
			"complete", "", "", "done", ready and explicit_status != "done",
			"ready_to_complete" if ready else "objectives_incomplete",
		)

	var hidden_role: Dictionary = roles[0]
	return _marker_result(
		str(hidden_role.get("role", "summary")),
		str(hidden_role.get("objectiveId", "")),
		"",
		"active",
		false,
		"event_already_resolved" if explicit_status != "available" else "quest_not_started",
	)


static func _marker_result(
	role: String,
	objective_id: String,
	objective_text: String,
	status: String,
	visible: bool,
	reason: String,
) -> Dictionary:
	return {
		"role": role,
		"objectiveId": objective_id,
		"objectiveText": objective_text,
		"status": status,
		"authoringStatus": status,
		"visible": visible,
		"reason": reason,
		"recognized": true,
	}


static func _first_role(roles: Array[Dictionary], role_name: String) -> Dictionary:
	for role in roles:
		if str(role.get("role", "")) == role_name:
			return role
	return {}


static func _objective_by_id(raw_objectives: Variant, objective_id: String) -> Dictionary:
	if typeof(raw_objectives) != TYPE_ARRAY:
		return {}
	for raw_objective in raw_objectives:
		if (
			typeof(raw_objective) == TYPE_DICTIONARY
			and str((raw_objective as Dictionary).get("id", "")) == objective_id
		):
			return raw_objective
	return {}


static func _is_last_required_objective(quest: Dictionary, objective_id: String) -> bool:
	var remaining_required := 0
	var current_is_required := false
	for raw_objective in quest.get("objectives", []):
		if typeof(raw_objective) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = raw_objective
		if bool(objective.get("optional", false)) or bool(objective.get("done", false)):
			continue
		remaining_required += 1
		if str(objective.get("id", "")) == objective_id:
			current_is_required = true
	return current_is_required and remaining_required == 1


static func _completion_value(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_BOOL and bool(value))
		or (typeof(value) == TYPE_STRING and str(value) == "done")
	)


static func glyph(status: String) -> String:
	match status:
		"active": return "◆"
		"done": return "✓"
	return "!"


static func marker_icon_path(authored: String, status: String) -> String:
	var resolved := resolve_icon_id(authored, status)
	if MARKER_ICON_PATHS.has(resolved):
		return str(MARKER_ICON_PATHS[resolved])
	# Unknown legacy/custom IDs keep their authored data, but runtime gets a
	# readable status icon until a matching visual-library asset is authored.
	return str(MARKER_ICON_PATHS.get("quest_%s" % status, MARKER_ICON_PATHS.quest_available))


static func color(status: String) -> Color:
	match status:
		"active": return Color(0.38, 0.76, 1.0)
		"done": return Color(0.48, 0.92, 0.56)
	return Color(1.0, 0.76, 0.18)


static func marker_lod(distance: float) -> Vector2:
	var shrink_t := clampf(
		(distance - MARKER_FULL_SIZE_DISTANCE)
		/ (MARKER_HIDE_DISTANCE - MARKER_FULL_SIZE_DISTANCE),
		0.0,
		1.0,
	)
	var fade_t := clampf(
		(distance - MARKER_FADE_DISTANCE)
		/ (MARKER_HIDE_DISTANCE - MARKER_FADE_DISTANCE),
		0.0,
		1.0,
	)
	return Vector2(
		lerpf(1.0, MARKER_MIN_SCALE, smoothstep(0.0, 1.0, shrink_t)),
		1.0 - smoothstep(0.0, 1.0, fade_t),
	)
