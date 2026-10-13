extends SceneTree
## Disposable native form -> saved recipe -> new game -> battle -> old save.
const Start = preload("res://scripts/ember_game_start_resource.gd")
const Party = preload("res://scripts/ember_party_state.gd")
const Gear = preload("res://scripts/ember_equipment.gd")
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const Session = preload("res://addons/ember_import/ember_game_systems_session.gd")
const Form = preload("res://addons/ember_import/ember_game_systems_draft_editor.gd")
const Hub = preload("res://addons/ember_import/ember_game_systems_workspace.gd")
const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const DIRECTORY := "user://ember-tests/game-start"
const WEAPON := "start_fixture_sword"
var _errors: Array[String] = []
var _history := UndoRedo.new()
var _session
var _form: Control

func _init() -> void:
	var path := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if path != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not path.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("FAIL start gate refused non-disposable project")
		quit.call_deferred(2)
		return
	root.size = Vector2i(1280, 900)
	Maps.prepare(self, DIRECTORY)
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok: _errors.append(message)

func _run() -> void:
	var original := Store.snapshot(Start.DEFAULT_PATH)
	var weapon := Store.blank("item", WEAPON, "Стартовый меч проверки")
	weapon.definition = Store.ItemStore.normalized_document({"id": WEAPON, "nameRu": "Стартовый меч проверки", "kind": "weapon_jrpg", "atk": 12, "hpBonus": 9, "mpBonus": 3, "allowedHeroIds": ["mira"]})
	_check(Store.write("item", weapon, Store.path_for("item", WEAPON)) == OK, "item fixture publication failed")
	_session = Session.new()
	_session.configure(_history)
	_validation()
	_authoring()
	_runtime()
	_session.discard()
	if _form != null: _form.free()
	_history.clear_history(false)
	_history.free()
	_check(Store.restore(original) == OK, "failed to restore start fixture bytes")
	Store.restore({"path": Store.path_for("item", WEAPON), "exists": false})
	_finish()

func _finish() -> void:
	if _errors.is_empty(): print("PASS game systems start: native levels/five-slot pickers/shared bag, validation/Undo/Redo/Discard/Save/reopen/publication/UID/links, neutral defaults/new game/full HP-MP/battle/deep isolation/no duplicate grants and existing save preservation")
	else: printerr("FAIL game start: ", "; ".join(_errors))
	quit(0 if _errors.is_empty() else 1)

func _validation() -> void:
	var config := Start.new()
	var items := EmberItemCatalog.definitions()
	_check(config.prepare(items).party == Party.new_game(items) and config.prepare(items).inventory == {"coin": 20}, "neutral start changes previous gameplay")
	for levels in [{"mira": 0}, {"mira": 100}, {"mira": 1.5}, {"unknown": 1}]:
		config.hero_levels = levels
		_check(not config.validation_errors(items).is_empty(), "invalid level accepted")
	config.hero_levels = {}
	for raw in [1, {"weapon": WEAPON}, {"head": null}]:
		config.hero_equipment = {"mira": raw}
		_check(not config.validation_errors(items).is_empty(), "invalid slots accepted")
	for id in ["herb", "missing", WEAPON]:
		var gear := Gear.empty()
		gear.armor = id
		config.hero_equipment = {"mira": gear}
		_check(not config.validation_errors(items).is_empty(), "invalid armor accepted")
	var gear := Gear.empty()
	gear.weapon = WEAPON
	config.hero_equipment = {"orik": gear}
	_check(not config.validation_errors(items).is_empty(), "hero restriction ignored")
	config.hero_equipment = {}
	for bag in [{"coin": -1}, {"coin": 1.5}, {"missing": 1}, {"traveler_tunic": 2}, {1: 1}]:
		config.inventory = bag
		_check(not config.validation_errors(items).is_empty(), "invalid bag accepted")
	config.inventory = {}
	_check(config.validation_errors(items).is_empty(), "empty bag rejected")
	_check(not _session.create("start", "other", "Другой старт") and Store.path_for("start", "other").is_empty(), "singleton copy allowed")
	_check(not _session.remove("start", {"path": Start.DEFAULT_PATH}, Store.signature(Start.DEFAULT_PATH)), "singleton delete allowed")
	_check(Store.remove_with_backup(Start.DEFAULT_PATH) == ERR_UNAUTHORIZED, "store deleted singleton")
	var hub := Hub.new()
	root.add_child(hub)
	hub.configure(_history)
	hub.setup()
	hub.select_module("start", "default")
	_check(hub.get("_new_button").disabled and hub.get("_copy_button").disabled, "singleton creation buttons active")
	hub.free()

func _mount() -> void:
	if _form != null: _form.free()
	_form = Form.new()
	root.add_child(_form)
	_form.setup(_session)

func _pick(name: String, id: String) -> void:
	var choice := _form.find_child(name, true, false) as OptionButton
	if choice == null:
		_check(false, "picker missing: " + name)
		return
	for index in choice.item_count:
		if choice.get_item_metadata(index) == id:
			choice.select(index)
			choice.item_selected.emit(index)
			return
	_check(false, "picker option missing: " + name + "/" + id)

func _authoring() -> void:
	var record: Dictionary = Store.Catalog.entries("start")[0]
	_check(_session.open("start", record), "existing start draft failed")
	_mount()
	var hash := Store.signature(Start.DEFAULT_PATH)
	(_form.find_child("StartLevel_mira", true, false) as SpinBox).value = 7
	_pick("StartGear_mira_weapon", WEAPON)
	_pick("StartGear_mira_armor", "traveler_tunic")
	(_form.find_child("StartBagCount_coin", true, false) as SpinBox).value = 37
	_pick("StartBagAddItem", "herb")
	(_form.find_child("StartBagAdd", true, false) as Button).pressed.emit()
	(_form.find_child("StartBagCount_herb", true, false) as SpinBox).value = 2
	_check(Store.signature(Start.DEFAULT_PATH) == hash, "draft wrote before Save")
	_session.undo()
	_check(_session.draft.inventory.herb == 1, "bag Undo failed")
	_session.redo()
	_check(_session.draft.inventory.herb == 2, "bag Redo failed")
	var preview := str((_form.find_child("StartStats_mira", true, false) as Label).text)
	_check("сила 0" not in preview and "защита 0" not in preview, "stats preview uses wrong keys")
	_check(Store.validation("start", _session.draft).is_empty() and _session.save(), "recipe Save failed: " + _session.last_error)
	var saved_hash := Store.signature(Start.DEFAULT_PATH)
	var uid := ResourceLoader.get_resource_uid(Start.DEFAULT_PATH)
	_history.undo()
	_check(Store.signature(Start.DEFAULT_PATH) == hash, "global Undo changed original bytes")
	_history.redo()
	_check(Store.signature(Start.DEFAULT_PATH) == saved_hash, "global Redo changed saved bytes")
	_check(_session.open("start", Store.Catalog.entries("start")[0]), "reopen failed")
	_check(_session.draft.hero_levels.mira == 7 and _session.draft.hero_equipment.mira.weapon == WEAPON and _session.draft.inventory.herb == 2, "reopen lost settings")
	_session.set_value("hero_levels", {"mira": 8})
	_session.discard()
	_check(Start.saved().hero_levels.mira == 7 and ResourceLoader.get_resource_uid(Start.DEFAULT_PATH) == uid, "Discard changed saved config/UID")
	_check(Store.Catalog.relations("start", Store.Catalog.entries("start")[0]).any(func(link: Dictionary) -> bool: return link.module == "item" and link.id == WEAPON), "start item usage link missing")
	_check(Store.Catalog.incoming("item", {"id": WEAPON, "path": Store.path_for("item", WEAPON)}).any(func(label: String) -> bool: return "Старт игры" in label), "item incoming start link missing")

func _runtime() -> void:
	var items := EmberItemCatalog.definitions()
	var config := Start.saved()
	var first := config.prepare(items)
	first.party.mira.equipment.weapon = null
	first.inventory.coin = 1
	_check(config.hero_equipment.mira.weapon == WEAPON and config.inventory.coin == 37 and config.prepare(items).party.mira.equipment.weapon == WEAPON, "recipe aliases mutable progress")
	var progress := root.get_node("EmberExploreProgress") as EmberExploreState
	progress.set_process(false)
	progress._item_definitions_cache_ready = false
	_check(progress.reset_new_game(), "new game refused saved recipe")
	var expected := config.prepare(items)
	_check(progress.party == expected.party and progress.inventory == expected.inventory, "runtime did not apply whole recipe")
	_check(not progress.inventory.has(WEAPON) and progress.party.mira.xp == 0, "worn gear also granted to bag / XP not zero")
	var battle := Party.apply_to_combat_state(Combat.initial_state(), progress.party, items)
	_check(battle.units.mira.level == 7 and battle.units.mira.equipment.weapon == WEAPON and battle.units.mira.hp == progress.party.mira.hp, "start failed battle projection")
	_check(progress.reset_new_game() and progress.inventory == expected.inventory, "repeated new game duplicated starter items")
	progress.party.mira.xp = 12
	progress.party.mira.hp = 1
	progress.flags.starter_progress = true
	progress.persistence_enabled = true
	var map := Maps.save_map("starter_map", DIRECTORY)
	_check(map != null, "fixture map failed")
	progress._map_id = "starter_map"
	_check(progress.save_slot(0), "starter save failed")
	config.hero_levels = {"mira": 2}
	config.hero_equipment = {}
	config.inventory = {"coin": 3}
	_check(Store.write("start", config, Start.DEFAULT_PATH) == OK, "second config failed")
	_check(progress.reset_new_game() and progress.party.mira.level == 2, "new game ignored updated recipe")
	_check(progress.load_slot(0) and progress.party.mira.level == 7 and progress.party.mira.hp == 1 and progress.inventory.coin == 37 and progress.flags.starter_progress, "Load reapplied updated start")
	# Invalid explicit reset is atomic and leaves live progress intact.
	var before := {"party": progress.party.duplicate(true), "bag": progress.inventory.duplicate(true), "flags": progress.flags.duplicate(true)}
	config.hero_levels = {"mira": 0}
	_check(ResourceSaver.save(config, Start.DEFAULT_PATH) == OK, "invalid external config fixture failed")
	_check(not progress.reset_new_game() and progress.party == before.party and progress.inventory == before.bag and progress.flags == before.flags, "invalid reset partially erased progress")
	var fallback := EmberExploreState.new()
	fallback._boot_new_game()
	_check(not fallback.persistence_enabled and fallback.party.size() == Party.HERO_IDS.size() and fallback.inventory == {"coin": 20}, "invalid boot did not create safe neutral session")
	fallback.free()
