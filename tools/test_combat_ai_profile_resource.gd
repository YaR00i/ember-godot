extends SceneTree
## D2.2f gate: authored profiles rank legal resolver previews and Unit Inspector
## assigns the reusable policy with Undo/Redo.

const ProfileCatalog := preload("res://scripts/prototypes/ember_combat_ai_profile_catalog.gd")
const UnitCatalog := preload("res://scripts/prototypes/ember_combat_unit_catalog.gd")
const Combat := preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid := preload("res://scripts/prototypes/ember_combat_grid.gd")
const ProfilePanel := preload("res://addons/ember_import/ember_combat_ai_profile_inspector_panel.gd")
const UnitPanel := preload("res://addons/ember_import/ember_combat_unit_inspector_panel.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	_test_catalog(errors)
	_test_target_and_reaction_priority(errors)
	_test_low_hp_defense(errors)
	_test_grid_positioning(errors)
	_test_inspector_and_assignment(errors)
	if not errors.is_empty():
		printerr("FAIL combat AI profile Resource")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS combat AI profile Resource")
	print("  reusable profiles rank only valid shared-resolver previews")
	print("  target, reaction, positioning and low-HP behavior remain deterministic")
	print("  profile Inspector and enemy assignment support Undo/Redo")
	return 0


func _test_catalog(errors: Array[String]) -> void:
	var expected := PackedStringArray(["guardian", "opportunist", "relentless"])
	if ProfileCatalog.ids() != expected:
		errors.append("AI profile catalog does not expose the three authored fixtures")
	for profile in ProfileCatalog.resources():
		var validation := profile.validation_errors()
		if not validation.is_empty():
			errors.append("AI profile %s is invalid: %s" % [profile.profile_id, " | ".join(validation)])
	var source := ProfileCatalog.resource("guardian")
	var path := "user://combat_ai_profile_roundtrip.tres"
	if source == null or ResourceSaver.save(source, path) != OK:
		errors.append("AI profile Resource could not be saved")
	else:
		var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as EmberCombatAiProfileResource
		if reopened == null or reopened.content_signature() != source.content_signature():
			errors.append("AI profile Resource changed after save/reopen")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_target_and_reaction_priority(errors: Array[String]) -> void:
	var state := Combat.initial_state()
	_force_turn(state, "wisp")
	_set_hp(state, "mira", 12)
	_set_hp(state, "orik", 2)
	_set_hp(state, "sena", 10)
	_lock_hit_seed(state, "enemy_strike", "orik")
	var command := Combat.enemy_command(state)
	if str(command.get("targetId", "")) != "orik":
		errors.append("lowest-HP target priority did not select Orik")
	var units: Dictionary = state.get("units", {})
	var wisp := (units.get("wisp", {}) as Dictionary).duplicate(true)
	wisp["actions"] = ["enemy_strike", "douse"]
	wisp["mp"] = 10
	units["wisp"] = wisp
	var mira := (units.get("mira", {}) as Dictionary).duplicate(true)
	mira["statuses"] = {"burning": 1}
	units["mira"] = mira
	state["units"] = units
	_lock_hit_seed(state, "douse", "mira")
	command = Combat.enemy_command(state)
	if str(command.get("actionId", "")) != "douse" or str(command.get("targetId", "")) != "mira":
		errors.append("reaction preference did not override ordinary card order")


func _test_low_hp_defense(errors: Array[String]) -> void:
	var state := Combat.initial_state()
	_force_turn(state, "warden")
	_set_hp(state, "warden", 8)
	var command := Combat.enemy_command(state)
	if (
		str(command.get("actionId", "")) != "defend"
		or str(command.get("targetId", "")) != "warden"
	):
		errors.append("guardian did not defend itself below the authored HP threshold")
	_set_hp(state, "warden", 24)
	command = Combat.enemy_command(state)
	if str(command.get("actionId", "")) != "enemy_strike":
		errors.append("guardian defended above its authored HP threshold")


func _test_grid_positioning(errors: Array[String]) -> void:
	var state := Grid.initial_state()
	_keep_alive(state, PackedStringArray(["mira", "wisp"]))
	_set_cell(state, "mira", Vector2i(2, 2))
	_set_cell(state, "wisp", Vector2i(5, 2))
	_force_turn(state, "wisp")
	var original := state.duplicate(true)
	var command := Grid.enemy_command(state)
	if state != original:
		errors.append("enemy grid positioning mutated the source snapshot")
	if (
		not bool(command.get("ok", false))
		or str(command.get("actionId", "")) != "enemy_strike"
		or str(command.get("targetId", "")) != "mira"
		or (command.get("moves", {}) as Dictionary).get("wisp") != Vector2i(3, 2)
	):
		errors.append("enemy did not stage the shortest legal move + melee action")
	var repeated := Grid.enemy_command(state)
	if repeated != command:
		errors.append("enemy grid positioning is not deterministic")
	var committed := Combat.commit(state, command)
	if (
		Combat.unit_definition(committed, "wisp").get("cell") != Vector2i(3, 2)
		or int(Combat.unit_definition(committed, "mira").get("hp", 0)) >= int(Combat.unit_definition(state, "mira").get("hp", 0))
	):
		errors.append("shared commit did not apply the compound enemy move + action")

	state = Grid.initial_state()
	_keep_alive(state, PackedStringArray(["mira", "wisp", "raider"]))
	_set_cell(state, "mira", Vector2i(1, 2))
	_set_cell(state, "wisp", Vector2i(5, 2))
	_set_cell(state, "raider", Vector2i(4, 2))
	_force_turn(state, "wisp")
	command = Grid.enemy_command(state)
	var destination: Variant = (command.get("moves", {}) as Dictionary).get("wisp")
	if (
		not bool(command.get("movementOnly", false))
		or destination == Vector2i(4, 2)
		or destination not in Grid.reachable_cells(state, "wisp")
	):
		errors.append("pursuit fallback ignored occupancy or shared reachability")
	if not str(command.get("summary", "")).contains("без атаки"):
		errors.append("movement-only enemy turn is not explained in the combat log")


func _test_inspector_and_assignment(errors: Array[String]) -> void:
	var profile := ProfileCatalog.resource("opportunist")
	var profile_panel := ProfilePanel.new() as EmberCombatAiProfileInspectorPanel
	profile_panel.setup(profile)
	if (
		profile_panel.find_child("CombatAiProfileSwatch", true, false) == null
		or profile_panel.find_child("CombatAiProfileSummary", true, false) == null
		or profile_panel.find_child("CombatAiProfileValidation", true, false) == null
	):
		errors.append("AI profile Inspector lost visual summary or validation")
	var summary := profile_panel.find_child("CombatAiProfileSummary", true, false) as Label
	if summary == null or not summary.text.contains("Позиция:"):
		errors.append("AI profile Inspector does not explain authored positioning")
	profile_panel.free()
	var unit := UnitCatalog.resource("wisp")
	var history := UndoRedo.new()
	var unit_panel := UnitPanel.new() as EmberCombatUnitInspectorPanel
	unit_panel.setup(unit, null, history)
	if (
		unit_panel.find_child("CombatUnitAiProfileEditor", true, false) == null
		or unit_panel.find_child("CombatUnitAiProfilePicker", true, false) == null
	):
		errors.append("enemy Inspector has no visual AI profile assignment")
	var before := unit.ai_profile_id
	unit_panel.call("_commit_profile", "guardian")
	if unit.ai_profile_id != "guardian":
		errors.append("visual profile assignment did not change the enemy Resource")
	history.undo()
	if unit.ai_profile_id != before:
		errors.append("Undo did not restore the enemy AI profile")
	history.clear_history(false)
	history.free()
	unit_panel.free()


func _force_turn(state: Dictionary, active_id: String) -> void:
	var units: Dictionary = state.get("units", {})
	for raw_id in units:
		var unit: Dictionary = units[raw_id]
		unit["nextAt"] = 0.0 if str(raw_id) == active_id else 100.0
		units[raw_id] = unit
	state["units"] = units


func _lock_hit_seed(state: Dictionary, action_id: String, target_id: String) -> void:
	for seed in range(1, 1000):
		state["rngSeed"] = seed
		if bool(Combat.preview(state, action_id, target_id).get("hit", false)):
			return


func _set_hp(state: Dictionary, unit_id: String, hp: int) -> void:
	var units: Dictionary = state.get("units", {})
	var unit := (units.get(unit_id, {}) as Dictionary).duplicate(true)
	unit["hp"] = hp
	units[unit_id] = unit
	state["units"] = units


func _set_cell(state: Dictionary, unit_id: String, cell: Vector2i) -> void:
	var units: Dictionary = state.get("units", {})
	var unit := (units.get(unit_id, {}) as Dictionary).duplicate(true)
	unit["cell"] = cell
	units[unit_id] = unit
	state["units"] = units


func _keep_alive(state: Dictionary, alive_ids: PackedStringArray) -> void:
	var units: Dictionary = state.get("units", {})
	for raw_id in units:
		var unit := (units.get(raw_id, {}) as Dictionary).duplicate(true)
		if str(raw_id) not in alive_ids:
			unit["hp"] = 0
		units[raw_id] = unit
	state["units"] = units
