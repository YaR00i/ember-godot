extends SceneTree
## Authorable native footwear -> shared party projection/grid/effects/save.
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const Session = preload("res://addons/ember_import/ember_game_systems_session.gd")
const Form = preload("res://addons/ember_import/ember_game_systems_draft_editor.gd")
const Party = preload("res://scripts/ember_party_state.gd")
const Gear = preload("res://scripts/ember_equipment.gd")
const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid = preload("res://scripts/prototypes/ember_combat_grid.gd")
const Terrain = preload("res://scripts/prototypes/ember_combat_terrain.gd")
const Effect = preload("res://scripts/prototypes/ember_combat_effect_resource.gd")
const Action = preload("res://scripts/prototypes/ember_combat_action_resource.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const ID := "footwear_fixture_boots"
const ACTION := "footwear_fixture_push_wet"
const DIRECTORY := "user://ember-tests/footwear"
var _errors: Array[String] = []
var _paths: Array[String] = []
var _history := UndoRedo.new()
var _items := {}

func _init() -> void:
	var path := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if path != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not path.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("FAIL footwear gate refused non-disposable project")
		quit.call_deferred(2)
		return
	Maps.prepare(self, DIRECTORY)
	root.size = Vector2i(1280, 900)
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok: _errors.append(message)

func _run() -> void:
	_authoring()
	_runtime()
	_history.clear_history(false)
	_history.free()
	_paths.reverse()
	for path in _paths: Store.restore({"path": path, "exists": false})
	if _errors.is_empty(): print("PASS game systems footwear: saved optional properties/validation/hidden metadata/Undo/Redo/Discard/UID/fitting, slot-only neutral and signed bonuses, real equip/unequip/v2 save/load, grid MOVE/JUMP, push threshold/Wet duration/AI/preview-commit and unchanged cells")
	else: printerr("FAIL footwear: ", "; ".join(_errors))
	quit(0 if _errors.is_empty() else 1)

func _authoring() -> void:
	var session := Session.new()
	session.configure(_history)
	_check(session.create("equipment", ID, "Обувь проверки"), "footwear draft failed")
	_paths.append(session.path)
	var doc := Store.ItemStore.normalized_document({"id": ID, "nameRu": "Обувь проверки", "kind": "shoes", "allowedHeroIds": ["mira"], "futureData": {"keep": true}})
	session.set_value("definition", doc)
	var form := Form.new()
	root.add_child(form)
	form.setup(session)
	for pair in [["ItemMoveBonus", 2], ["ItemJumpBonus", 1], ["ItemPushResistanceBonus", 2], ["ItemWetResistanceBonus", 1]]:
		var number := form.find_child(pair[0], true, false) as SpinBox
		_check(number != null and number.is_visible_in_tree(), "footwear control missing/hidden: " + pair[0])
		if number != null: number.value = pair[1]
	form.call("_undo_draft")
	_check(session.draft.definition.get("wetResistanceBonus", 0) == 0, "shoe field Undo failed")
	form.call("_redo_draft")
	_check(session.draft.definition.get("wetResistanceBonus") == 1, "shoe field Redo failed")
	var item_form := form.find_child("GameSystemsItemDraft", true, false)
	item_form.call("_show_preview", true)
	var fitting := item_form.get("_preview") as Control
	var hero := fitting.find_child("EquipmentPreviewHero", true, false) as OptionButton
	for index in hero.item_count:
		if hero.get_item_metadata(index) == "mira":
			hero.select(index)
			hero.item_selected.emit(index)
	var changes: Dictionary = fitting.get("_comparison").changes
	_check(changes.get("moveRange") == 2 and changes.get("jumpHeight") == 1 and changes.get("pushResistance") == 2 and changes.get("statusResistances.wet") == 1, "fitting did not use unsaved shoe properties")
	_check(session.save(), "shoe Save failed: " + session.last_error)
	var sha := Store.signature(session.path)
	var uid := ResourceLoader.get_resource_uid(session.path)
	_check(session.open("item", {"path": session.path, "resource": null}) and session.draft.definition.moveBonus == 2 and session.draft.definition.futureData.keep, "Save/reopen lost bonus or extension metadata")
	for value in ["bad", true, [], 1.5, INF, 999]:
		var bad := doc.duplicate(true)
		bad.moveBonus = value
		_check(not Store.ItemStore.validation_errors(bad).is_empty(), "invalid footwear number accepted: " + str(value))
	var draft: Dictionary = session.draft.definition.duplicate(true)
	draft.moveBonus = 3
	session.set_value("definition", draft)
	session.discard()
	_check(Store.signature(Store.path_for("item", ID)) == sha and ResourceLoader.get_resource_uid(Store.path_for("item", ID)) == uid, "Discard changed saved item/UID")
	form.free()
	_items = Store.Catalog.Items.definitions()
	var action := Action.new()
	action.action_id = ACTION
	action.display_name = "Проверочный мокрый толчок"
	action.hint = "Толчок силой 2 и Мокрый на 3 хода."
	action.requirements_text = "Противник в дальности."
	action.effect = Action.Effect.EFFECT_CHAIN
	action.scaling = Action.Scaling.NONE
	action.range_cells = 99
	for push in [true, false]:
		var effect := Effect.new()
		effect.effect_id = ACTION + ("_push" if push else "_wet")
		effect.display_name = "Толчок" if push else "Мокрый"
		effect.description = "Проверка свойств обуви."
		if push:
			effect.operation = Effect.Operation.PUSH
			effect.force = 2
		else:
			effect.status_id = "wet"
			effect.status_duration = 3
		var path := Store.path_for("effect", effect.effect_id)
		_paths.append(path)
		_check(Store.write("effect", effect, path) == OK, "effect fixture invalid")
		action.effect_steps.append(Store.Catalog.Effects.resource(effect.effect_id))
	var path := Store.path_for("action", ACTION)
	_paths.append(path)
	_check(Store.write("action", action, path) == OK, "action fixture invalid: " + str(Store.validation("action", action)))

func _runtime() -> void:
	var progress := EmberExploreState.new()
	progress.persistence_enabled = false
	_check(progress.reset_new_game(), "new game failed")
	progress.inventory[ID] = 1
	var bare := progress.party_member_view("mira")
	_check(progress.equip_item_for_member("mira", ID).ok, "owner could not equip footwear")
	var worn := progress.party_member_view("mira")
	_check(worn.moveRange == bare.moveRange + 2 and worn.jumpHeight == bare.jumpHeight + 1 and worn.pushResistance == bare.pushResistance + 2 and worn.statusResistances.wet == bare.statusResistances.wet + 1, "derived bonuses missing/double applied")
	var state := Party.apply_to_combat_state(Grid.initial_state(), progress.party, _items)
	var baseline := Grid.initial_state()
	var saved_grid: Dictionary = state.grid.duplicate(true)
	_check(Vector2i(5, 2) not in Grid.reachable_cells(baseline, "mira") and Vector2i(5, 2) in Grid.reachable_cells(state, "mira"), "MOVE bonus did not unlock actual destination")
	var high := Vector2i(2, 2)
	for cell in state.grid.cells.values(): cell.elevation = 0
	state.grid.cells[Terrain.cell_key(high)].elevation = int(bare.jumpHeight) + 1
	baseline = state.duplicate(true)
	baseline.units.mira.jumpHeight = bare.jumpHeight
	_check(high not in Grid.reachable_cells(baseline, "mira") and high in Grid.reachable_cells(state, "mira"), "JUMP bonus did not cross actual height threshold")
	_check(Party.apply_to_combat_state(Grid.initial_state(), progress.party, _items).grid == saved_grid, "shoe changed battlefield surface/tags")
	_push_wet(progress)
	var map := Maps.save_map("footwear_map", DIRECTORY)
	_check(map != null, "save map fixture failed")
	progress._map_id = "footwear_map"
	progress.storage_root = DIRECTORY.path_join("saves")
	progress.persistence_enabled = true
	_check(progress.save_slot(0), "shoe save publication failed")
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(progress.save_path(0)))
	_check(not payload.party.mira.has("moveRange") and payload.party.mira.equipment.shoes == ID, "save stores derived shoe stats / lost ID")
	progress.unequip_slot_for_member("mira", "shoes")
	_check(progress.party_member_view("mira").moveRange == bare.moveRange and progress.party_member_view("mira").statusResistances == bare.statusResistances, "unequip did not restore neutral stats")
	_check(progress.load_slot(0) and progress.party_member_view("mira").moveRange == worn.moveRange, "Load did not derive saved shoes")
	var negative := _items.duplicate(true)
	negative[ID].moveBonus = -12
	negative[ID].jumpBonus = -8
	var lower := Party.derived_stats("mira", progress.party.mira, negative)
	_check(lower.moveRange == 0 and lower.jumpHeight == 0, "negative footwear did not clamp at zero")
	var wrong_slot := Gear.empty()
	wrong_slot.accessory1 = ID
	_check(Gear.footwear_bonuses(wrong_slot, _items).moveBonus == 0, "item outside shoes slot provided shoe bonuses")
	progress.free()

func _push_wet(progress: EmberExploreState) -> void:
	var state := Party.apply_to_combat_state(Combat.initial_state(), progress.party, _items)
	for id in state.units:
		state.units[id].nextAt = 1000.0
		if state.units[id].team == "hero" and id != "mira": state.units[id].hp = 0
	state.units.wisp.nextAt = 0.0
	state.units.wisp.zone = 0
	state.units.mira.zone = 1
	state.units.wisp.actions = [ACTION]
	var preview := {}
	for seed in range(1, 100):
		state.rngSeed = seed
		preview = Combat.preview(state, ACTION, "mira")
		if preview.get("ok", false) and preview.get("hit", false): break
	_check(preview.get("ok", false) and preview.get("hit", false), "could not prepare real hit for footwear")
	var after := Combat.commit(state, preview)
	_check(not preview.moves.has("mira") and after.units.mira.zone == 1, "push ignored worn resistance threshold")
	_check(after.units.mira.statuses.get("wet") == 2, "footwear did not shorten actual Wet application")
	var ai := Combat.enemy_command(state)
	_check(ai.get("ok", false) and not ai.moves.has("mira") and ai.setStatuses.get("mira", {}).get("wet") == 2, "AI did not use footwear rules")
	var bare := state.duplicate(true)
	bare.units.mira.pushResistance -= 2
	bare.units.mira.statusResistances.wet -= 1
	var normal := Combat.preview(bare, ACTION, "mira")
	_check(normal.moves.has("mira") and normal.setStatuses.get("mira", {}).get("wet") == 3, "barefoot control does not show push/Wet difference")
	var immune := state.duplicate(true)
	immune.units.mira.statusResistances.wet = 3
	_check(not Combat.preview(immune, ACTION, "mira").setStatuses.get("mira", {}).has("wet"), "full Wet resistance did not block short application")
