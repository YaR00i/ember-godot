class_name EmberInteractRules
extends RefCounted
## Pure routing for scene-owned EmberInteract launch rules. Save data remains in
## EmberExploreState.flags; this module only decides which existing action runs.


static func route(
	primary_script_id: String,
	condition_flag_id: String,
	condition_expected: Variant,
	fallback_script_id: String,
	one_shot: bool,
	completion_flag_id: String,
	flags: Dictionary,
) -> Dictionary:
	var completion_key := completion_flag_id.strip_edges()
	if one_shot and not completion_key.is_empty() and flags.get(completion_key, false) == true:
		return {
			"available": false,
			"scriptId": "",
			"primary": false,
			"reason": "already_completed",
		}
	var condition_key := condition_flag_id.strip_edges()
	var condition_met := true
	if not condition_key.is_empty():
		var actual: Variant = flags.get(condition_key, false if typeof(condition_expected) == TYPE_BOOL else null)
		condition_met = actual == condition_expected
	if condition_met:
		return {
			"available": true,
			"scriptId": primary_script_id.strip_edges(),
			"primary": true,
			"reason": "",
		}
	var fallback := fallback_script_id.strip_edges()
	return {
		"available": not fallback.is_empty(),
		"scriptId": fallback,
		"primary": false,
		"reason": "condition_failed",
	}
