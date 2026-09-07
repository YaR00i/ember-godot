extends SceneTree
## D2.2d gate: combatants are authored Resources shared by Encounter Inspector
## and the existing pure combat snapshot/resolver.

const Catalog := preload("res://scripts/prototypes/ember_combat_unit_catalog.gd")
const Combat := preload("res://scripts/prototypes/ember_combat_prototype.gd")
const UnitPanel := preload("res://addons/ember_import/ember_combat_unit_inspector_panel.gd")
const EncounterPanel := preload("res://addons/ember_import/ember_encounter_inspector_panel.gd")
const EncounterCatalog := preload("res://scripts/prototypes/ember_encounter_catalog.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	_test_catalog(errors)
	_test_runtime_projection(errors)
	_test_unit_inspector(errors)
	_test_encounter_roster_undo(errors)
	if not errors.is_empty():
		printerr("FAIL combat unit Resource")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS combat unit Resource")
	print("  seven authored .tres definitions include the four-person permanent party")
	print("  runtime snapshots copy movement/Jump/weight/actions without mutating content")
	print("  unit and encounter Inspectors expose visual roster authoring with Undo/Redo")
	print("  enemy AI reads its authored reusable profile")
	return 0


func _test_catalog(errors: Array[String]) -> void:
	var expected := PackedStringArray(["mira", "orik", "protagonist", "raider", "sena", "warden", "wisp"])
	var ids := PackedStringArray(Catalog.ids())
	for unit_id in expected:
		if unit_id not in ids:
			errors.append("combat unit catalog lost %s" % unit_id)
	for unit in Catalog.resources():
		var validation := unit.validation_errors(Combat.action_ids())
		if not validation.is_empty():
			errors.append("unit %s is invalid: %s" % [unit.unit_id, " | ".join(validation)])
	if Array(Catalog.definitions().keys()) != ["mira", "orik", "sena", "protagonist", "wisp", "raider", "warden"]:
		errors.append("authored prototype roster order was not preserved")
	var heroes := Catalog.ids("hero")
	var enemies := Catalog.ids("enemy")
	if heroes.size() != 4 or enemies.size() != 3 or "protagonist" not in heroes or "wisp" not in enemies:
		errors.append("team-filtered combat unit catalog is incorrect")
	var source := Catalog.resource("mira")
	var path := "user://combat_unit_roundtrip.tres"
	if source == null or ResourceSaver.save(source, path) != OK:
		errors.append("combat unit Resource could not be saved")
	else:
		var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as EmberCombatUnitResource
		if reopened == null or reopened.content_signature() != source.content_signature():
			errors.append("combat unit Resource changed after save/reopen")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_runtime_projection(errors: Array[String]) -> void:
	var mira_resource := Catalog.resource("mira")
	var wisp_resource := Catalog.resource("wisp")
	var state := Combat.initial_state()
	var mira := Combat.unit_definition(state, "mira")
	var wisp := Combat.unit_definition(state, "wisp")
	if mira_resource == null or wisp_resource == null:
		return
	if (
		int(mira.get("maxHp", 0)) != mira_resource.max_hp
		or int(mira.get("maxMp", -1)) != mira_resource.max_mp
		or int(mira.get("speed", 0)) != mira_resource.speed
		or int(mira.get("str", 0)) != mira_resource.strength
		or int(mira.get("mag", 0)) != mira_resource.magic
		or int(mira.get("def", -1)) != mira_resource.defense
		or int(mira.get("res", -1)) != mira_resource.resistance
		or int(mira.get("acc", 0)) != mira_resource.accuracy
		or int(mira.get("luck", -1)) != mira_resource.luck
		or int((mira.get("resistances", {}) as Dictionary).get("water", 0)) != mira_resource.water_resistance
		or int((mira.get("resistances", {}) as Dictionary).get("air", 0)) != mira_resource.air_resistance
		or int((mira.get("resistances", {}) as Dictionary).get("earth", 0)) != mira_resource.earth_resistance
		or int(mira.get("jumpHeight", -1)) != mira_resource.jump_height
		or int(mira.get("weightClass", -1)) != mira_resource.weight_class
		or int(mira.get("level", -1)) != mira_resource.combat_level
		or str(mira.get("creatureType", "")) != mira_resource.creature_type_id()
		or str(mira.get("sizeLabel", "")) != mira_resource.size_label()
		or int(mira.get("pushResistance", -1)) != mira_resource.push_resistance
		or mira.get("battleColor", Color.BLACK) != mira_resource.battle_color
		or (mira.get("actions", []) as Array) != Array(mira_resource.action_ids)
	):
		errors.append("runtime unit snapshot drifted from authored Resource")
	if str(wisp.get("aiProfileId", "")) != wisp_resource.ai_profile_id:
		errors.append("enemy snapshot lost its authored AI profile")
	if (
		str(wisp.get("creatureType", "")) != "spirit"
		or int((wisp.get("statusResistances", {}) as Dictionary).get("frozen", 0)) != 1
	):
		errors.append("enemy snapshot lost study type or deterministic effect resistance")
	if str(wisp.get("lootTableId", "")) != wisp_resource.loot_table.table_id:
		errors.append("enemy snapshot lost its authored loot table")
	var units: Dictionary = state.get("units", {})
	mira["hp"] = 1
	units["mira"] = mira
	state["units"] = units
	if mira_resource.max_hp != 18:
		errors.append("mutable battle snapshot changed the authored unit Resource")
	_force_turn(state, "wisp")
	var command := Combat.enemy_command(state)
	if (
		str(command.get("aiProfileId", "")) != wisp_resource.ai_profile_id
		or str(command.get("actionId", "")) != "enemy_strike"
	):
		errors.append("enemy command ignored the Resource AI profile")


func _test_unit_inspector(errors: Array[String]) -> void:
	var unit := Catalog.resource("warden")
	var panel := UnitPanel.new() as EmberCombatUnitInspectorPanel
	panel.setup(unit)
	if (
		panel.find_child("CombatUnitSwatch", true, false) == null
		or panel.find_child("CombatUnitSummary", true, false) == null
		or panel.find_child("CombatUnitValidation", true, false) == null
		or panel.find_child("CombatUnitLootTablePicker", true, false) == null
	):
		errors.append("combat unit Inspector lost visual summary, validation or loot picker")
	var summary := panel.find_child("CombatUnitSummary", true, false) as Label
	if summary == null or "MP " not in summary.text or "Тип Конструкт" not in summary.text or "стойкость 1" not in summary.text:
		errors.append("combat unit Inspector does not expose MP and authored study data")
	panel.free()


func _test_encounter_roster_undo(errors: Array[String]) -> void:
	var source := EncounterCatalog.definition("colored_crossing_demo")
	if source == null:
		errors.append("encounter fixture unavailable for roster authoring")
		return
	var encounter := source.duplicate(true) as EmberEncounterResource
	var history := UndoRedo.new()
	var panel := EncounterPanel.new() as EmberEncounterInspectorPanel
	panel.setup(encounter, null, history)
	if (
		panel.find_child("EncounterRoster_hero_0", true, false) == null
		or panel.find_child("EncounterRoster_enemy_0", true, false) == null
		or panel.find_child("EncounterUnitPicker_hero", true, false) == null
	):
		errors.append("Encounter Inspector lost visual roster controls")
	var before := encounter.party_unit_ids.duplicate()
	panel.call("_move_unit", "hero", 0, 1)
	if encounter.party_unit_ids.size() < 2 or encounter.party_unit_ids[0] != before[1]:
		errors.append("Encounter visual roster did not change deployment order")
	else:
		history.undo()
		if encounter.party_unit_ids != before:
			errors.append("Encounter roster Undo did not restore order")
		history.redo()
		if encounter.party_unit_ids[0] != before[1]:
			errors.append("Encounter roster Redo did not restore authored order")
	history.clear_history(false)
	history.free()
	panel.free()


func _force_turn(state: Dictionary, active_id: String) -> void:
	var units: Dictionary = state.get("units", {})
	for raw_id in units:
		var unit: Dictionary = units[raw_id]
		unit["nextAt"] = 0.0 if str(raw_id) == active_id else 100.0
		units[raw_id] = unit
	state["units"] = units
