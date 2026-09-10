extends SceneTree
## D2.2a gate: one native Encounter Resource powers authoring, action execution
## and the existing grid resolver without a parallel combat schema.

const ENCOUNTER_ID := "colored_crossing_demo"
const Catalog := preload("res://scripts/prototypes/ember_encounter_catalog.gd")
const Visuals := preload("res://scripts/prototypes/ember_encounter_visuals.gd")
const Store := preload("res://addons/ember_import/ember_action_script_store.gd")
const EncounterPanel := preload("res://addons/ember_import/ember_encounter_inspector_panel.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var encounter := Catalog.definition(ENCOUNTER_ID)
	if encounter == null:
		errors.append("canonical encounter Resource is missing")
	else:
		_test_resource(encounter, errors)
		_test_visuals(encounter, errors)
		_test_inspector(encounter, errors)
	_test_action_step(errors)
	if not errors.is_empty():
		printerr("FAIL encounter Resource")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS encounter Resource")
	print("  one .tres selects battlefield, roster, result flags and continuation")
	print("  visual picker and Inspector use the same canonical resource")
	print("  start_battle is a validated terminal action step")
	print("  combat state consumes authored deployment order")
	return 0


func _test_resource(encounter: EmberEncounterResource, errors: Array[String]) -> void:
	var validation := encounter.validation_errors()
	if not validation.is_empty():
		errors.append("encounter validation failed: %s" % " | ".join(validation))
	if ENCOUNTER_ID not in Catalog.ids():
		errors.append("encounter is absent from the shared catalog")
	if encounter.victory_xp != 35:
		errors.append("encounter lost its authored equal-party XP reward")
	var state := encounter.initial_state()
	for count in range(1, 5):
		var active: Array[String] = []
		active.assign(["mira", "orik", "sena", "protagonist"].slice(0, count))
		var partial := encounter.initial_state({}, 51, active)
		if EmberPartyState.combat_hero_ids(partial).size() != count or not encounter.active_party_errors(active).is_empty():
			errors.append("compatible active subset did not create exactly %d heroes" % count)
	var incompatible := encounter.duplicate(true) as EmberEncounterResource
	incompatible.party_unit_ids = PackedStringArray(["mira"])
	if incompatible.active_party_errors(["orik"]).is_empty() or not incompatible.initial_state({}, 51, ["orik"]).is_empty():
		errors.append("unsupported active hero was silently intersected")
	incompatible = encounter.duplicate(true) as EmberEncounterResource
	incompatible.battlefield = encounter.battlefield.duplicate(true) as EmberBattlefieldResource
	incompatible.battlefield.party_deployment_cells.resize(1)
	if incompatible.active_party_errors(["mira", "orik"]).is_empty() or not incompatible.initial_state({}, 51, ["mira", "orik"]).is_empty():
		errors.append("insufficient cells were silently truncated")
	var units: Dictionary = state.get("units", {})
	if units.size() != encounter.party_unit_ids.size() + encounter.enemy_unit_ids.size():
		errors.append("encounter roster did not become combat units")
	for index in encounter.party_unit_ids.size():
		var unit: Dictionary = units.get(encounter.party_unit_ids[index], {})
		if unit.get("cell", Vector2i(-1, -1)) != encounter.battlefield.party_deployment_cells[index]:
			errors.append("party deployment order is not canonical")
	for index in encounter.enemy_unit_ids.size():
		var unit: Dictionary = units.get(encounter.enemy_unit_ids[index], {})
		if unit.get("cell", Vector2i(-1, -1)) != encounter.battlefield.enemy_deployment_cells[index]:
			errors.append("enemy deployment order is not canonical")
	var path := "user://encounter_resource_roundtrip.tres"
	if ResourceSaver.save(encounter, path) != OK:
		errors.append("encounter could not be saved")
	else:
		var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as EmberEncounterResource
		if reopened == null or reopened.content_signature() != encounter.content_signature():
			errors.append("encounter changed after save/reopen")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_visuals(encounter: EmberEncounterResource, errors: Array[String]) -> void:
	var entries := Visuals.entries()
	if entries.size() < 1 or str(entries[0].get("id", "")) != ENCOUNTER_ID:
		errors.append("visual encounter library lost its canonical entry")
	var image := Visuals.image(encounter)
	if image.is_empty() or image.get_width() != 112 or image.get_height() != 88:
		errors.append("encounter mini-map was not generated")


func _test_inspector(encounter: EmberEncounterResource, errors: Array[String]) -> void:
	var panel := EncounterPanel.new() as EmberEncounterInspectorPanel
	panel.setup(encounter, null)
	if panel.find_child("EncounterPreview", true, false) == null:
		errors.append("Encounter Inspector lost its visual preview")
	if panel.find_child("OpenEncounterArena", true, false) == null:
		errors.append("Encounter Inspector lost arena navigation")
	if panel.find_child("EncounterValidation", true, false) == null:
		errors.append("Encounter Inspector lost validation feedback")
	var summary := panel.find_child("EncounterSummary", true, false) as Label
	if summary == null or "35 XP каждому" not in summary.text:
		errors.append("Encounter Inspector does not explain the authored XP reward")
	panel.free()


func _test_action_step(errors: Array[String]) -> void:
	if "start_battle" not in Store.STEP_TYPES:
		errors.append("action palette has no start_battle step")
	var queue := EmberActionScript.queue_for("colored_crossing_start")
	var steps: Array = queue.get("steps", [])
	if not bool(queue.get("ok", false)) or steps.size() != 2:
		errors.append("runtime queue did not resolve talk + battle")
	elif str((steps[1] as Dictionary).get("encounterId", "")) != ENCOUNTER_ID:
		errors.append("runtime queue lost the encounter reference")
	var invalid := {
		"id": "bad_battle_order",
		"nameRu": "Неверный порядок",
		"steps": [
			{"type": "start_battle", "encounterId": ENCOUNTER_ID},
			{"type": "set_flag", "flag": "unreachable", "value": true},
		],
	}
	if Store.validation_errors(invalid).is_empty():
		errors.append("writer accepted steps after terminal battle")
