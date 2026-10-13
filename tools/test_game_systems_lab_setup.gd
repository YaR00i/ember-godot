extends SceneTree
const Setup = preload("res://scripts/prototypes/ember_combat_lab_setup.gd")
const Dialog = preload("res://addons/ember_import/ember_game_systems_lab_setup_dialog.gd")
const Hub = preload("res://addons/ember_import/ember_game_systems_workspace.gd")
const Units = preload("res://scripts/prototypes/ember_combat_unit_catalog.gd")
const Items = preload("res://scripts/ember_item_catalog.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const Transition = preload("res://scripts/ember_combat_transition.gd")
var _errors: Array[String] = []
var _fixtures: Array[String] = []

func _init() -> void:
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if actual != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not actual.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("FAIL test setup refused non-disposable project")
		quit.call_deferred(2)
		return
	root.size = Vector2i(1600, 900)
	root.gui_embed_subwindows = true
	Maps.prepare(self, "user://game-systems-setup-%d" % OS.get_process_id())
	_run.call_deferred()

func _save(resource: Resource, path: String) -> void:
	_check(ResourceSaver.save(resource, path) == OK, "fixture save failed")
	_fixtures.append(path)

func _run() -> void:
	var custom := Units.resource("mira").duplicate(true) as EmberCombatUnitResource
	custom.unit_id = "setup_custom_hero"
	custom.display_name = "Тестовый герой"
	custom.max_hp = 87
	custom.strength = 23
	_save(custom, Units.ROOT.path_join(custom.unit_id + ".tres"))
	for slot in ["weapon", "armor", "shoes", "accessory"]:
		var item := EmberItemResource.new()
		item.item_id = "setup_" + slot
		item.definition = {"nameRu": "Тест " + slot, "kind": "weapon_jrpg" if slot == "weapon" else slot, "slot": slot, "stackMax": 1, "atk": 7, "def": 3, "hpBonus": 6, "mpBonus": 2, "allowedHeroIds": ["mira"] if slot == "weapon" else []}
		_save(item, "res://content/items/" + item.item_id + ".tres")
	var encounter := load("res://content/combat/encounters/colored_crossing_demo.tres").duplicate(true) as EmberEncounterResource
	encounter.encounter_id = "setup_encounter_fixture"
	encounter.party_unit_ids = PackedStringArray(["mira", custom.unit_id])
	_save(encounter, "res://content/combat/encounters/" + encounter.encounter_id + ".tres")
	encounter = ResourceLoader.load(_fixtures[-1], "", ResourceLoader.CACHE_MODE_IGNORE) as EmberEncounterResource
	var original := encounter.initial_state()
	_check(Setup.apply(original, Setup.prepare(encounter, {})) == original, "default setup changed authored stats")
	var equipment := {"weapon": "setup_weapon", "armor": "setup_armor", "shoes": "setup_shoes", "accessory1": "setup_accessory", "accessory2": "setup_accessory"}
	var raw := {"party": {"mira": {"level": 9, "equipment": equipment}}, "inventory": {"herb": 3}}
	var prepared := Setup.prepare(encounter, raw)
	_check(prepared.get("ok", false), "valid setup refused: " + str(prepared.get("error", "")))
	if prepared.get("ok", false):
		_check(prepared.derived.mira == EmberPartyState.derived_stats("mira", raw.party.mira, Items.definitions()), "setup duplicated or changed campaign formulas")
		var projected := Setup.apply(original, prepared)
		_check(projected.units.mira.level == 9 and projected.units.mira.hp == projected.units.mira.maxHp and projected.units.mira.mp == projected.units.mira.maxMp, "test projection lost level/full health")
		_check(projected.units[custom.unit_id] == original.units[custom.unit_id], "unconfigured hero changed")
		projected.units.mira.equipment.weapon = null
		_check(raw.party.mira.equipment.weapon == "setup_weapon" and not original.units.mira.has("equipment"), "projection mutated input")
	var custom_input := {"party": {custom.unit_id: {"level": 5, "equipment": EmberEquipment.empty()}}}
	var cached_custom := ResourceLoader.load(_fixtures[0]) as EmberCombatUnitResource
	cached_custom.strength = 900
	var custom_prepared := Setup.prepare(encounter, custom_input)
	_check(custom_prepared.get("ok", false) and custom_prepared.derived[custom.unit_id].maxHp == 95 and custom_prepared.derived[custom.unit_id].str == 30, "custom native hero does not use its own card and shared level rules")
	for invalid in [null, [], {"unexpected": true}, {"party": []}, {"inventory": []}, {"party": {"wisp": {"level": 1, "equipment": EmberEquipment.empty()}}}, {"inventory": {"herb": 0}}, {"inventory": {"herb": 100}}, {"inventory": {"herb": 1.5}}, {"inventory": {"setup_weapon": 1}}, {"inventory": {"missing": 1}}]:
		_check(not Setup.prepare(encounter, invalid).get("ok", true), "invalid setup accepted: " + str(invalid))
	for level in [0, 100, 1.5, "9", true]:
		var invalid := raw.duplicate(true)
		invalid.party.mira.level = level
		_check(not Setup.prepare(encounter, invalid).get("ok", true), "invalid level accepted")
	for slot_value in ["missing", "herb", "setup_shoes", 3, ""]:
		var invalid := raw.duplicate(true)
		invalid.party.mira.equipment.weapon = slot_value
		_check(not Setup.prepare(encounter, invalid).get("ok", true), "invalid weapon accepted")
	var missing_slot := raw.duplicate(true)
	missing_slot.party.mira.equipment.erase("accessory2")
	_check(not Setup.prepare(encounter, missing_slot).get("ok", true), "partial slot set accepted")
	var extra_slot := raw.duplicate(true)
	extra_slot.party.mira.equipment["head"] = null
	_check(not Setup.prepare(encounter, extra_slot).get("ok", true), "legacy sixth slot accepted")
	var restricted := custom_input.duplicate(true)
	restricted.party[custom.unit_id].equipment.weapon = "setup_weapon"
	_check(not Setup.prepare(encounter, restricted).get("ok", true), "hero restriction bypassed")
	var written := Setup.write_request(encounter.resource_path, raw)
	var args := PackedStringArray([Transition.LIBRARY_TEST_PREFIX + encounter.resource_path, Transition.LIBRARY_SETUP_PREFIX + str(written.path)])
	var request := Transition.library_test_request(args)
	_check(request.get("ok", false), "request file did not roundtrip JSON numeric counts/levels: " + str(request.get("error", "")))
	args.append(Transition.LIBRARY_SETUP_PREFIX + str(written.path))
	_check(not Transition.library_test_request(args).get("ok", true), "duplicate setup request accepted")
	_check(not Transition.library_test_request(PackedStringArray([Transition.LIBRARY_SETUP_PREFIX + str(written.path)])).get("ok", true), "orphan setup request accepted")
	_check(not Setup.read_request(str(written.path), encounter, "res://content/combat/encounters/another.tres").get("ok", true), "request allowed different encounter")
	_check(not Setup.read_request("res://outside.json", encounter, encounter.resource_path).get("ok", true), "unsafe setup path accepted")
	for bad_text in ["{broken", JSON.stringify({"version": 2, "encounterPath": encounter.resource_path, "setup": raw}), " ".repeat(Setup.MAX_REQUEST_BYTES + 1)]:
		var file := FileAccess.open(str(written.path), FileAccess.WRITE)
		file.store_string(bad_text)
		file.close()
		_check(not Setup.read_request(str(written.path), encounter, encounter.resource_path).get("ok", true), "corrupt/version/oversized request accepted")
	DirAccess.remove_absolute(str(written.path))
	await _test_dialog(encounter, raw)
	for path in _fixtures: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if _errors.is_empty(): print("PASS game systems Lab setup: shared math, custom saved hero, five slots/restrictions, default parity, strict transport, native controls Undo/Redo/Cancel/reopen, dirty guard and detached input")
	else: printerr("FAIL Lab setup: ", "; ".join(_errors))
	quit(0 if _errors.is_empty() else 1)

func _test_dialog(encounter: EmberEncounterResource, remembered: Dictionary) -> void:
	var dialog := Dialog.new()
	root.add_child(dialog)
	dialog.open_setup(encounter, remembered)
	await process_frame
	var level := dialog.find_child("LabSetupLevel", true, false) as SpinBox
	level.value = 12
	_check(dialog.find_child("LabSetupLevel", true, false) == level and not level.is_queued_for_deletion(), "level edit replaced the focused control")
	_check(dialog.snapshot().party.mira.level == 12 and remembered.party.mira.level == 9, "native level edited remembered input")
	(dialog.find_child("LabSetupUndo", true, false) as Button).pressed.emit()
	_check(dialog.snapshot().party.mira.level == 9, "local Undo failed")
	(dialog.find_child("LabSetupRedo", true, false) as Button).pressed.emit()
	_check(dialog.snapshot().party.mira.level == 12, "local Redo failed")
	var shoes := dialog.find_child("LabSetupSlot_shoes", true, false) as OptionButton
	shoes.select(0)
	shoes.item_selected.emit(0)
	_check(dialog.snapshot().party.mira.equipment.shoes == null, "native slot did not edit")
	var count := dialog.find_child("LabSetupCount_herb", true, false) as SpinBox
	count.value = 0
	_check(dialog.find_child("LabSetupCount_herb", true, false) == count and not count.is_queued_for_deletion(), "count edit replaced the focused control")
	_check(not dialog.snapshot().inventory.has("herb"), "native bag zero did not remove count")
	var hero := dialog.find_child("LabSetupHero", true, false) as OptionButton
	hero.select(1)
	hero.item_selected.emit(1)
	(dialog.find_child("LabSetupCustom", true, false) as CheckBox).button_pressed = true
	_check(dialog.snapshot().party.has("setup_custom_hero"), "custom roster hero not configurable")
	dialog.get_cancel_button().pressed.emit()
	dialog.hide()
	dialog.open_setup(encounter, remembered)
	_check(dialog.snapshot() == remembered and remembered.party.mira.level == 9, "Cancel/reopen preserved canceled changes")
	(dialog.find_child("LabSetupReset", true, false) as Button).pressed.emit()
	_check(dialog.snapshot().is_empty(), "authored reset failed")
	dialog.undo()
	_check(dialog.snapshot() == remembered, "reset cannot Undo")
	dialog.hide()
	dialog.free()
	var hub := Hub.new()
	root.add_child(hub)
	hub.setup()
	hub.call("select_module", "encounter", encounter.encounter_id)
	hub.call("begin_edit")
	hub.get("_session").set_value("victory_xp", encounter.victory_xp + 1)
	_check(not hub.call("_configure_selected_encounter").get("ok", true) and hub.has_unsaved_changes(), "settings bypassed dirty authoring guard")
	hub.call("discard_changes")
	hub.call("select_module", "encounter", encounter.encounter_id)
	hub.call("_configure_selected_encounter")
	_check(hub.get("_lab_setup_context").is_empty() and not hub.has_unsaved_changes(), "opening settings changed resource/session")
	hub.get("_lab_setup_dialog").hide()
	hub.free()

func _check(condition: bool, message: String) -> void:
	if not condition: _errors.append(message)
