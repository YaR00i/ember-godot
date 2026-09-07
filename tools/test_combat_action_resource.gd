extends SceneTree
## D2.2e gate: action content, Inspector projection and unit assignment share
## the canonical .tres catalog while formulas remain in Combat resolver.

const ActionCatalog := preload("res://scripts/prototypes/ember_combat_action_catalog.gd")
const UnitCatalog := preload("res://scripts/prototypes/ember_combat_unit_catalog.gd")
const Combat := preload("res://scripts/prototypes/ember_combat_prototype.gd")
const ActionPanel := preload("res://addons/ember_import/ember_combat_action_inspector_panel.gd")
const UnitPanel := preload("res://addons/ember_import/ember_combat_unit_inspector_panel.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	_test_catalog(errors)
	_test_resolver_projection(errors)
	_test_inspector(errors)
	_test_unit_action_undo(errors)
	if not errors.is_empty():
		printerr("FAIL combat action Resource")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS combat action Resource")
	print("  twenty-one combat actions, including twelve personal hero actions, are canonical .tres content")
	print("  resolver reads authored numbers, targets, effects and UI color")
	print("  action Inspector and visual unit assignment support Undo/Redo")
	return 0


func _test_catalog(errors: Array[String]) -> void:
	var expected := PackedStringArray([
		"chill", "defend", "douse", "duo_pulse", "earth_raise", "earth_wall",
		"enemy_strike", "forge_leap", "guard", "gust", "ice_wall", "kindle",
		"lift_throw", "mira_mend", "overheat", "overload", "remote_relay",
		"spark", "steam_breach", "strike", "wind_spread",
	])
	if ActionCatalog.ids() != expected:
		errors.append("action catalog does not expose the twenty-one authored fixtures")
	for action in ActionCatalog.resources():
		var validation := action.validation_errors()
		if not validation.is_empty():
			errors.append("action %s is invalid: %s" % [action.action_id, " | ".join(validation)])
	var source := ActionCatalog.resource("douse")
	var path := "user://combat_action_roundtrip.tres"
	if source == null or ResourceSaver.save(source, path) != OK:
		errors.append("combat action Resource could not be saved")
	else:
		var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as EmberCombatActionResource
		if reopened == null or reopened.content_signature() != source.content_signature():
			errors.append("combat action Resource changed after save/reopen")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_resolver_projection(errors: Array[String]) -> void:
	var douse := ActionCatalog.resource("douse")
	var definition := Combat.action_definition("douse")
	if douse == null:
		return
	if (
		str(definition.get("effect", "")) != douse.effect_id()
		or str(definition.get("target", "")) != douse.target_id()
		or int(definition.get("power", -1)) != douse.power
		or int(definition.get("mpCost", -1)) != douse.mp_cost
		or int(definition.get("accuracyModifier", -99)) != douse.accuracy_modifier
		or str(definition.get("scaling", "")) != douse.scaling_id()
		or str(definition.get("menuGroup", "")) != "magic"
		or str(definition.get("requirements", "")).is_empty()
		or int(definition.get("range", -1)) != douse.range_cells
		or definition.get("uiColor", Color.BLACK) != douse.ui_color
	):
		errors.append("combat resolver projection drifted from action Resource")
	var state := Combat.initial_state()
	var preview := Combat.preview(state, "douse", "wisp")
	if not bool(preview.get("ok", false)) or str(preview.get("actionId", "")) != "douse":
		errors.append("authored action could not enter the shared preview resolver")
	var lift := ActionCatalog.resource("lift_throw")
	if (
		lift == null
		or lift.effect_id() != "lift_throw"
		or lift.target_id() != "unit"
		or lift.throw_range_cells != 3
		or lift.max_lift_weight != 1
		or lift.menu_group_id() != "skill"
	):
		errors.append("lift/throw secondary-target contract drifted from its Resource")
	var gust := ActionCatalog.resource("gust")
	var kindle := ActionCatalog.resource("kindle")
	if gust == null or kindle == null or gust.force != 1 or kindle.force != 2:
		errors.append("authored deterministic push force is missing")
	var wet_pair := ActionCatalog.resource("duo_pulse")
	var steam_pair := ActionCatalog.resource("steam_breach")
	if (
		wet_pair == null
		or wet_pair.partner_unit_id != "mira"
		or wet_pair.partner_range_cells != 3
		or wet_pair.partner_mp_cost != 6
		or wet_pair.partner_delay <= 0
		or steam_pair == null
		or steam_pair.effect_id() != "steam_breach"
		or steam_pair.partner_unit_id != "orik"
		or steam_pair.partner_range_cells != 3
		or steam_pair.force != 3
	):
		errors.append("pair participant/cost/delay contract drifted from action Resources")


func _test_inspector(errors: Array[String]) -> void:
	var action := ActionCatalog.resource("kindle")
	var panel := ActionPanel.new() as EmberCombatActionInspectorPanel
	panel.setup(action)
	if (
		panel.find_child("CombatActionIcon", true, false) == null
		or panel.find_child("CombatActionSwatch", true, false) == null
		or panel.find_child("CombatActionSummary", true, false) == null
		or panel.find_child("CombatActionValidation", true, false) == null
	):
		errors.append("combat action Inspector lost visual summary or validation")
	var summary := panel.find_child("CombatActionSummary", true, false) as Label
	if summary == null or "Магия" not in summary.text or "Условия:" not in summary.text:
		errors.append("combat action Inspector does not explain its radial group and conditions")
	panel.free()
	var pair := ActionCatalog.resource("duo_pulse")
	var pair_panel := ActionPanel.new() as EmberCombatActionInspectorPanel
	pair_panel.setup(pair)
	var pair_summary := pair_panel.find_child("CombatActionSummary", true, false) as Label
	if (
		pair_summary == null
		or "Партнёр: mira" not in pair_summary.text
		or "радиус 3" not in pair_summary.text
		or "MP 6" not in pair_summary.text
	):
		errors.append("combat action Inspector does not expose pair radius, cost and delay")
	pair_panel.free()


func _test_unit_action_undo(errors: Array[String]) -> void:
	var unit := UnitCatalog.resource("mira")
	var undo := UndoRedo.new()
	var panel := UnitPanel.new() as EmberCombatUnitInspectorPanel
	panel.setup(unit, null, undo)
	if panel.find_child("CombatUnitActionEditor", true, false) == null:
		errors.append("unit Inspector has no visual action editor")
		panel.free()
		return
	var original := unit.action_ids.duplicate()
	panel.call("_move_action", 0, 1)
	if unit.action_ids[0] != original[1]:
		errors.append("visual action reorder did not change the Resource")
	undo.undo()
	if unit.action_ids != original:
		errors.append("Undo did not restore action order")
	panel.call("_add_action", "chill")
	if "chill" not in unit.action_ids:
		errors.append("visual action library could not assign an action")
	undo.undo()
	if unit.action_ids != original:
		errors.append("Undo did not remove the assigned action")
	panel.call("_remove_action", 1)
	if unit.action_ids.size() != original.size() - 1:
		errors.append("visual action remove did not change the Resource")
	undo.undo()
	if unit.action_ids != original:
		errors.append("Undo did not restore the removed action")
	panel.free()
	undo.clear_history(false)
	undo.free()
