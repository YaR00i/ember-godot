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
static var _pending_strategy_snapshot: Array[String] = []
static var _active_strategy_snapshot: Array[String] = []
static var _result_applied := false
static var _party_ids_snapshot: Array[String] = []
static var _locked_progress: WeakRef
static var last_start_error := ""


static func change_scene(
	tree: SceneTree,
	encounter_id: String,
	progress: EmberExploreState = null,
) -> Error:
	last_start_error = ""
	if not _pending_encounter_id.is_empty() or not _active_encounter_id.is_empty():
		last_start_error = "Боевая встреча уже выполняется."
		return ERR_ALREADY_IN_USE
	var encounter := Catalog.definition(encounter_id)
	if tree == null or encounter == null:
		last_start_error = "Встреча содержит некорректные данные."
		return ERR_INVALID_DATA
	var validation := encounter.validation_errors()
	if not validation.is_empty():
		last_start_error = "\n".join(validation)
		return ERR_INVALID_DATA
	if progress != null:
		var roster_errors := encounter.active_party_errors(progress.active_hero_ids)
		if not roster_errors.is_empty():
			last_start_error = "\n".join(roster_errors)
			return ERR_INVALID_DATA
	if not encounter.can_start(progress):
		return ERR_ALREADY_EXISTS
	if tree.current_scene == null or tree.current_scene.scene_file_path.is_empty():
		return ERR_CANT_RESOLVE
	_pending_encounter_id = encounter.encounter_id
	_pending_party_snapshot = progress.combat_party_snapshot() if progress != null else {}
	_pending_inventory_snapshot = progress.combat_inventory_snapshot() if progress != null else {}
	_pending_strategy_snapshot = progress.combat_strategy_snapshot() if progress != null else []
	_party_ids_snapshot = progress.active_hero_ids.duplicate() if progress != null else []
	if progress != null:
		_locked_progress = weakref(progress)
		progress.combat_party_locked = true
	_active_party_snapshot = {}
	_active_inventory_snapshot = {}
	_active_strategy_snapshot = []
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
	_active_strategy_snapshot = _pending_strategy_snapshot.duplicate()
	_pending_strategy_snapshot = []
	_result_applied = false
	return Catalog.definition(_active_encounter_id)


static func active_party_snapshot() -> Dictionary:
	return _active_party_snapshot.duplicate(true)


static func active_hero_ids_snapshot() -> Array[String]:
	return _party_ids_snapshot.duplicate()


static func _unlock_party() -> void:
	if _locked_progress != null:
		var progress := _locked_progress.get_ref() as EmberExploreState
		if progress != null:
			progress.combat_party_locked = false
	_locked_progress = null
	_party_ids_snapshot = []


static func active_inventory_snapshot() -> Dictionary:
	return _active_inventory_snapshot.duplicate(true)


static func active_strategy_snapshot() -> Array[String]:
	return _active_strategy_snapshot.duplicate()


static func finish(
	tree: SceneTree,
	outcome: String,
	progress: EmberExploreState,
	combat_state: Dictionary = {},
) -> Error:
	if tree == null or outcome not in ["victory", "defeat"]:
		return ERR_INVALID_DATA
	# A defeated attempt is never a persistent result. The defeat screen must
	# either rebuild the active encounter from its pre-battle copies or load an
	# existing save through `load_save`; only victory crosses this commit point.
	if outcome == "defeat":
		return ERR_UNAVAILABLE
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
	_unlock_party()
	_active_inventory_snapshot = {}
	_active_strategy_snapshot = []
	_return_scene_path = ""
	if return_path.is_empty() or not ResourceLoader.exists(return_path):
		_return_action_id = ""
		_return_steps.clear()
		return ERR_FILE_NOT_FOUND
	return tree.change_scene_to_file(return_path)


static func load_save(
	tree: SceneTree,
	progress: EmberExploreState,
	save_kind: String,
	slot := -1,
) -> Error:
	if tree == null or progress == null or _active_encounter_id.is_empty():
		return ERR_INVALID_DATA
	var metadata := {}
	if save_kind == "autosave":
		metadata = progress.autosave_metadata()
	elif save_kind == "manual":
		metadata = progress.slot_metadata(slot)
	else:
		return ERR_INVALID_DATA
	if not bool(metadata.get("exists", false)):
		return ERR_FILE_NOT_FOUND
	# Parse, migrate and normalize through the existing save owner, but keep the
	# live autoload untouched until both the save and destination scene are valid.
	var staged := EmberExploreState.new()
	staged.active_slot = progress.active_slot
	staged.storage_root = progress.storage_root
	staged.legacy_storage_root = progress.legacy_storage_root
	staged.persistence_enabled = progress.persistence_enabled
	staged.restore_enabled = progress.restore_enabled
	var loaded := (
		staged.load_autosave()
		if save_kind == "autosave"
		else staged.load_slot(slot)
	)
	if not loaded:
		staged.free()
		return ERR_FILE_CORRUPT
	var target_path := staged.resume_scene_path()
	if target_path.is_empty() or not ResourceLoader.exists(target_path):
		staged.free()
		return ERR_FILE_NOT_FOUND
	var target_scene := ResourceLoader.load(target_path) as PackedScene
	if target_scene == null:
		staged.free()
		return ERR_CANT_OPEN
	var error := tree.change_scene_to_packed(target_scene)
	if error != OK:
		staged.free()
		return error
	progress.adopt_loaded_save(staged)
	staged.free()
	abandon_active_encounter()
	return OK


static func abandon_active_encounter() -> void:
	_unlock_party()
	_pending_encounter_id = ""
	_active_encounter_id = ""
	_pending_party_snapshot = {}
	_active_party_snapshot = {}
	_pending_inventory_snapshot = {}
	_active_inventory_snapshot = {}
	_pending_strategy_snapshot = []
	_active_strategy_snapshot = []
	_return_scene_path = ""
	_return_action_id = ""
	_return_steps.clear()
	_result_applied = false


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
	abandon_active_encounter()
