class_name EmberCombatTransition
extends RefCounted
## Process-local handoff between exploration and the existing Combat Lab scene.

const Catalog := preload("res://scripts/prototypes/ember_encounter_catalog.gd")
const CombatResult := preload("res://scripts/prototypes/ember_combat_result.gd")
const COMBAT_SCENE := "res://scenes/combat_lab.tscn"

static var _pending_encounter_id := ""
static var _active_encounter_id := ""
static var _return_scene_path := ""
static var _return_action_id := ""
static var _return_steps: Array[Dictionary] = []
static var _pending_party_snapshot: Dictionary = {}
static var _active_party_snapshot: Dictionary = {}
static var _pending_inventory_snapshot: Dictionary = {}
static var _active_inventory_snapshot: Dictionary = {}
static var _result_applied := false


static func change_scene(
	tree: SceneTree,
	encounter_id: String,
	progress: EmberExploreState = null,
) -> Error:
	var encounter := Catalog.definition(encounter_id)
	if tree == null or encounter == null or not encounter.validation_errors().is_empty():
		return ERR_INVALID_DATA
	if not encounter.can_start(progress):
		return ERR_ALREADY_EXISTS
	if tree.current_scene == null or tree.current_scene.scene_file_path.is_empty():
		return ERR_CANT_RESOLVE
	_pending_encounter_id = encounter.encounter_id
	_pending_party_snapshot = progress.combat_party_snapshot() if progress != null else {}
	_pending_inventory_snapshot = progress.combat_inventory_snapshot() if progress != null else {}
	_active_party_snapshot = {}
	_active_inventory_snapshot = {}
	_return_scene_path = tree.current_scene.scene_file_path
	_result_applied = false
	_return_steps.clear()
	var error := tree.change_scene_to_file(COMBAT_SCENE)
	if error != OK:
		clear_for_test()
	return error


static func consume_encounter() -> EmberEncounterResource:
	if _pending_encounter_id.is_empty():
		return null
	_active_encounter_id = _pending_encounter_id
	_pending_encounter_id = ""
	_active_party_snapshot = _pending_party_snapshot.duplicate(true)
	_pending_party_snapshot = {}
	_active_inventory_snapshot = _pending_inventory_snapshot.duplicate(true)
	_pending_inventory_snapshot = {}
	_result_applied = false
	return Catalog.definition(_active_encounter_id)


static func active_party_snapshot() -> Dictionary:
	return _active_party_snapshot.duplicate(true)


static func active_inventory_snapshot() -> Dictionary:
	return _active_inventory_snapshot.duplicate(true)


static func finish(
	tree: SceneTree,
	outcome: String,
	progress: EmberExploreState,
	combat_state: Dictionary = {},
) -> Error:
	if tree == null or outcome not in ["victory", "defeat"]:
		return ERR_INVALID_DATA
	if _result_applied:
		return ERR_ALREADY_IN_USE
	var encounter := Catalog.definition(_active_encounter_id)
	if encounter == null:
		return ERR_INVALID_DATA
	# Set this before mutating progress or changing scenes. A double click, Enter
	# repeat, or a delayed UI signal must never grant the outcome twice.
	_result_applied = true
	var flag_id := encounter.flag_for_outcome(outcome).strip_edges()
	var report := CombatResult.build(encounter, combat_state, outcome)
	if progress != null:
		progress.apply_combat_result(
			combat_state,
			false,
			int(report.get("xpReward", 0)),
			outcome == "victory",
		)
		if not flag_id.is_empty():
			progress.set_flag(flag_id, true, false)
		progress.apply_combat_counters(report.get("counterDeltas", {}), false)
		progress.save_autosave()
		progress.arm_saved_spawn_restore()
	_return_action_id = encounter.action_for_outcome(outcome).strip_edges()
	_return_steps.clear()
	for raw_step in report.get("lootSteps", []):
		if typeof(raw_step) == TYPE_DICTIONARY:
			_return_steps.append((raw_step as Dictionary).duplicate(true))
	var return_path := _return_scene_path
	_active_encounter_id = ""
	_active_party_snapshot = {}
	_active_inventory_snapshot = {}
	_return_scene_path = ""
	if return_path.is_empty() or not ResourceLoader.exists(return_path):
		_return_action_id = ""
		_return_steps.clear()
		return ERR_FILE_NOT_FOUND
	return tree.change_scene_to_file(return_path)


static func consume_return_action() -> String:
	var result := _return_action_id
	_return_action_id = ""
	return result


static func consume_return_steps() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for step in _return_steps:
		result.append(step.duplicate(true))
	_return_steps.clear()
	return result


static func clear_for_test() -> void:
	_pending_encounter_id = ""
	_active_encounter_id = ""
	_pending_party_snapshot = {}
	_active_party_snapshot = {}
	_pending_inventory_snapshot = {}
	_active_inventory_snapshot = {}
	_return_scene_path = ""
	_return_action_id = ""
	_return_steps.clear()
	_result_applied = false
