extends SceneTree
const Catalog = preload("res://addons/ember_import/ember_game_systems_catalog.gd")
const Session = preload("res://addons/ember_import/ember_game_systems_session.gd")
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const Workspace = preload("res://addons/ember_import/ember_graph_workspace.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const Party = preload("res://scripts/ember_party_state.gd")
const Equipment = preload("res://scripts/ember_equipment.gd")
const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
var _errors: Array[String] = []
var _created: Array[String] = []
var _undo := UndoRedo.new()

func _init() -> void:
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	Maps.prepare(self, "user://game-systems-operations-%d" % OS.get_process_id())
	_run.call_deferred()

func _run() -> void:
	for info in Catalog.MODULES:
		var module := str(info[0])
		if not Store.SPECS.has(Store.kind(module)): continue
		var records := Catalog.entries(module)
		_check(not records.is_empty(), "native source missing for " + module)
		if not records.is_empty(): _round_trip(module, records[0])
	_test_shared_copy()
	_test_conflicts()
	_test_delete()
	await _test_ui()
	await _test_item_library()
	_undo.clear_history(false)
	_undo.free()
	for path in _created: Store.restore({"path": path, "exists": false})
	if not _errors.is_empty():
		printerr("FAIL game systems operations: ", "; ".join(_errors))
		quit(1)
		return
	print("PASS game systems operations: native kinds copy/draft/save/reopen, UID/bytes/Undo/conflicts/delete; unified item filters, seven forms, hidden metadata, signed bonuses/hero restrictions and real combat preview/commit")
	quit(0)

func _round_trip(module: String, record: Dictionary) -> void:
	var source_hash := Store.signature(str(record.path))
	var source := ResourceLoader.load(str(record.path), "", ResourceLoader.CACHE_MODE_IGNORE)
	var session := Session.new()
	session.configure(_undo)
	var id := "operations_fixture_" + module
	_check(session.create(module, id, "Fixture copy", source), "copy could not start " + module)
	var path := session.path
	_created.append(path)
	_check(not FileAccess.file_exists(path), "copy wrote a file before Save " + module)
	var property := "definition" if Store.kind(module) == "item" else "display_name"
	var before: Variant = session.draft.get(property)
	var after: Variant = before.duplicate(true) if before is Dictionary else "Changed fixture"
	if after is Dictionary: after["nameRu"] = "Changed fixture"
	var expected: Variant = Store.ItemStore.normalized_document(after) if after is Dictionary else after
	session.set_value(property, after)
	session.undo()
	_check(session.draft.get(property) == before, "draft Undo failed " + module)
	session.redo()
	_check(session.draft.get(property) == after, "draft Redo failed " + module)
	_check(session.save(), "copy Save failed " + module + ": " + session.last_error)
	if not FileAccess.file_exists(path): return
	_check(not session.has_changes(), "clean publication remained dirty " + module)
	var published_hash := Store.signature(path)
	var uid := ResourceLoader.get_resource_uid(path)
	_undo.undo()
	_check(not FileAccess.file_exists(path), "publication Undo did not remove new file " + module)
	_undo.redo()
	_check(Store.signature(path) == published_hash, "publication Redo changed exact bytes " + module)
	_check(ResourceLoader.get_resource_uid(path) == uid, "publication Redo changed UID " + module)
	session.open(module, {"path": path, "resource": null})
	_check(not session.has_changes(), "reopened record is dirty " + module)
	_check(session.draft.get(property) == expected, "save/reopen changed data " + module)
	var next: Variant = after.duplicate(true) if after is Dictionary else "Second edit"
	if next is Dictionary: next["nameRu"] = "Second edit"
	session.set_value(property, next)
	_check(session.save(), "existing Save failed " + module + ": " + session.last_error)
	_check(ResourceLoader.get_resource_uid(path) == uid, "existing Save changed stable UID " + module)
	_undo.undo()
	_check(Store.signature(path) == published_hash, "existing Save Undo changed original bytes " + module)
	_check(Store.signature(str(record.path)) == source_hash, "copy changed its source " + module)
	session.discard()

func _test_shared_copy() -> void:
	var action := Catalog.Actions.resource("earth_wall")
	var copy := Store.clone(action)
	_check(copy.effect_steps[0] == action.effect_steps[0], "external effect was silently forked")
	copy.effect_steps.clear()
	_check(not action.effect_steps.is_empty(), "copy shared its mutable root array")
	var table := Catalog.Loot.resources()[0]
	var table_copy := Store.clone(table)
	var original := table.entries[0].minimum_count
	table_copy.entries[0].minimum_count = original + 10
	_check(table.entries[0].minimum_count == original, "internal loot row remained shared")
	var session := Session.new()
	_check(not session.create("action", "earth_wall", "Collision", action), "duplicate ID overwrote existing action")
	_check(session.create("effect", "operations_fixture_invalid", "Incomplete effect"), "blank effect draft could not start")
	_check(not session.save() and not FileAccess.file_exists(session.path), "invalid draft reached native catalog")
	session.discard()

func _test_conflicts() -> void:
	var path := Store.path_for("item", "operations_fixture_item")
	var before := Store.snapshot(path)
	var session := Session.new()
	session.configure(_undo)
	session.open("item", {"path": path, "resource": null})
	var data: Dictionary = session.draft.definition.duplicate(true)
	data["nameRu"] = "Local draft"
	session.set_value("definition", data)
	var external := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	external.definition["nameRu"] = "External edit"
	_check(Store.write("item", external, path) == OK, "external conflict setup failed")
	var external_hash := Store.signature(path)
	_check(not session.save() and Store.signature(path) == external_hash, "Save overwrote an externally changed file")
	Store.restore(before)
	session.open("item", {"path": path, "resource": ResourceLoader.load(path)})
	session._live_source.definition["nameRu"] = "Unsaved Inspector edit"
	_check(not session.save(), "Save ignored unsaved live source changes")
	Store.restore(before)
	session.discard()

func _test_delete() -> void:
	var path := Store.path_for("item", "operations_fixture_item")
	var record := {"path": path, "id": "operations_fixture_item", "name": "Fixture", "resource": null}
	var before := Store.signature(path)
	var session := Session.new()
	session.configure(_undo)
	_check(session.remove("item", record, before), "unreferenced fixture delete failed: " + session.last_error)
	_check(not FileAccess.file_exists(path), "Delete left the file active")
	var backup := "user://ember-editor-resource-backups/operations_fixture_item-" + before + ".tres"
	_check(Store.signature(backup) == before, "Delete did not preserve exact backup")
	_undo.undo()
	_check(Store.signature(path) == before, "Delete Undo did not restore exact bytes")
	var reference := "res://content/action_scripts/operations_fixture_reference.tres"
	var file := FileAccess.open(reference, FileAccess.WRITE)
	file.store_string('[gd_resource type="Resource" format=3]\n[resource]\nresource_name = "operations_fixture_item"\n')
	file.close()
	_check(not session.remove("item", record, before), "Delete ignored an incoming authored ID reference")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(reference))
	session.discard()

func _test_ui() -> void:
	var workspace := Workspace.new()
	workspace.configure(null, _undo)
	workspace.size = Vector2(1280, 720)
	root.add_child(workspace)
	workspace.open_resource("systems", "systems_library")
	var hub := workspace.get("_game_systems_workspace") as Control
	hub.call("select_module", "item", "herb")
	hub.call("begin_edit")
	var form := hub.find_child("GameSystemsItemDraft", true, false) as EmberItemEditor
	var name := form.find_child("ItemNameRu", true, false) as LineEdit
	name.text = "Unsaved UI fixture"
	name.text_changed.emit(name.text)
	_check(hub.call("has_unsaved_changes"), "form change did not dirty the session")
	var search := hub.find_child("GameSystemsSearch", true, false) as LineEdit
	search.text = "another item"
	search.text_changed.emit(search.text)
	_check(not hub.get("_pending").is_empty() and hub.find_child("GameSystemsItemDraft", true, false) != null, "search silently hid a dirty draft")
	hub.get("_discard_dialog").canceled.emit()
	workspace.call("_request_navigation", "dialogue", "colored_crossing_intro", false)
	_check(workspace.get("_current_kind") == "systems", "Graph navigation bypassed system draft guard")
	workspace.call("_cancel_discard_navigation")
	_check(hub.call("has_unsaved_changes"), "navigation Cancel lost a draft")
	hub.get("_session").undo()
	_check(not hub.call("has_unsaved_changes"), "UI draft Undo did not restore clean state")
	hub.call("select_module", "status", "wet")
	hub.call("begin_edit")
	var status_name: String = hub.get("_session").draft.display_name
	name.text_changed.emit("late old-form event")
	_check(hub.get("_session").draft.display_name == status_name, "retired form callback modified the new draft")
	workspace.free()
	await process_frame

func _check(condition: bool, error: String) -> void:
	if not condition: _errors.append(error)

func _choose(form: Control, node_name: String, value: String) -> void:
	var option := form.find_child(node_name, true, false) as OptionButton
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			option.item_selected.emit(index)
			return
	_check(false, "option missing: " + node_name + " " + value)

func _test_item_library() -> void:
	var workspace := Workspace.new()
	workspace.configure(null, _undo)
	workspace.size = Vector2(1280, 720)
	root.add_child(workspace)
	workspace.open_resource("systems", "systems_library")
	var hub := workspace.get("_game_systems_workspace") as Control
	_check(hub.find_child("GameSystemsModule_equipment", true, false) == null, "equipment retained a second library screen")
	hub.call("select_module", "equipment", "traveler_tunic")
	_check(hub.get("_module") == "item" and hub.get("_category_id") == "equipment", "equipment link did not resolve to shared filter")
	_check(hub.get("_records").size() == Catalog.Items.ids().size(), "filtered library lost canonical items")
	_check(hub.get("_list").get_root().get_child_count() == 1, "equipment filter included consumables")
	hub.call("begin_edit")
	var form := hub.find_child("GameSystemsItemDraft", true, false) as EmberItemEditor
	_check(form.get("_equipment_fields").visible and not form.get("_use_fields").visible, "armor form showed unrelated consumable controls")
	form.call("_show_preview", true)
	_choose(form, "EquipmentPreviewHero", "mira")
	(form.find_child("EquipmentPreviewLevel", true, false) as SpinBox).value = 3
	_choose(form, "EquipmentPreviewSlot_armor", "traveler_tunic")
	_check(not hub.call("has_unsaved_changes"), "fitting settings dirtied gameplay draft")
	_check(form.get("_preview").get("_comparison").changes.maxHp == 0, "published item comparison should have no HP delta")
	var bonus := form.find_child("ItemHpBonus", true, false) as SpinBox
	bonus.value = 15
	_check(form.get("_preview").get("_comparison").changes.maxHp == 15, "unsaved bonus did not update fitting immediately")
	_choose(hub, "GameSystemsItemFilter", "consumable")
	_check(hub.get("_category_id") == "equipment" and hub.call("has_unsaved_changes"), "filter discarded an equipment draft")
	hub.get("_discard_dialog").canceled.emit()
	_check(hub.get("_session").draft.definition.get("hpBonus") == 15, "filter Cancel lost bonus")
	hub.get("_draft_editor").call("_undo_draft")
	_check(not hub.call("has_unsaved_changes"), "numeric form input generated duplicate draft Undo steps")
	form = hub.find_child("GameSystemsItemDraft", true, false) as EmberItemEditor
	var comparison: Dictionary = form.get("_preview").get("_comparison")
	_check(form.get("_preview").visible and comparison.hero == "mira" and comparison.level == 3 and comparison.replacedId == "traveler_tunic" and comparison.changes.maxHp == 0, "Undo lost fitting context or left stale stats")
	hub.call("_close_draft")
	_check(hub.get("_library").visible, "return to library did not restore list and filters")
	hub.call("select_module", "item")
	_choose(hub, "GameSystemsItemFilter", "armor")
	hub.get("_create_id").text = "operations_fixture_library"
	hub.get("_create_name").text = "Проверочная экипировка"
	hub.call("_create_draft")
	var session = hub.get("_session")
	_created.append(session.path)
	_check(session.draft.definition.kind == "armor" and session.draft.definition.slot == "armor", "new item ignored its type filter")
	var data: Dictionary = session.draft.definition.duplicate(true)
	data["futureMetadata"] = {"keep": [1, 2, 3]}
	data["allowedHeroIds"] = PackedStringArray(["mira", "future_hero"])
	data["slot"] = "armor"
	session.set_value("definition", data)
	hub.call("_mount_draft")
	form = hub.find_child("GameSystemsItemDraft", true, false) as EmberItemEditor
	(form.find_child("ItemHpBonus", true, false) as SpinBox).value = 15
	(form.find_child("ItemMpBonus", true, false) as SpinBox).value = -3
	var allowed := form.find_child("ItemAllowedHeroes", true, false) as LineEdit
	allowed.text = "mira, future_hero, mira"
	allowed.text_changed.emit(allowed.text)
	_check(session.draft.definition.allowedHeroIds == ["mira", "future_hero"], "hero normalization dropped unknown IDs or retained duplicates")
	_check(Party.equipment_allowed(session.draft.definition, "mira") and not Party.equipment_allowed(session.draft.definition, "orik"), "authored restrictions did not reach Party owner")
	var eq := Equipment.empty()
	eq.armor = "operations_fixture_library"
	var baseline := Party.derived_stats("mira", {"level": 1})
	var projected := Party.derived_stats("mira", {"level": 1, "equipment": eq}, {"operations_fixture_library": session.draft.definition})
	_check(projected.maxHp == baseline.maxHp + 15 and projected.maxMp == maxi(0, baseline.maxMp - 3), "authored signed bonuses did not reach derived runtime stats")
	_choose(form, "EquipmentPreviewHero", "orik")
	_check(not form.get("_preview").get("_comparison").ok, "fitting showed a blocked hero as compatible")
	_choose(form, "EquipmentPreviewHero", "mira")
	_check(form.get("_preview").get("_comparison").ok, "fitting rejected allowed hero")
	# All seven types use this form; hidden values and extension metadata survive.
	for kind in Store.ItemStore.KINDS:
		_choose(form, "ItemKind", kind)
		_check(session.draft.definition.futureMetadata == {"keep": [1, 2, 3]} and session.draft.definition.hpBonus == 15, "type switch lost hidden properties: " + kind)
		_check(form.get("_equipment_fields").visible == (kind in ["weapon_jrpg", "armor", "shoes", "accessory"]), "wrong fields for " + kind)
		_check(session.draft.definition.slot == "armor", "type switch lost the inactive armor slot")
	_choose(form, "ItemKind", "accessory")
	_choose(form, "EquipmentPreviewTargetSlot", "accessory2")
	_check(form.get("_preview").get("_comparison").slot == "accessory2" and form.get("_preview").get("_comparison").ok, "fitting could not target second accessory")
	_choose(form, "ItemKind", "consumable")
	_choose(form, "ItemUseIn", "both")
	(form.find_child("ItemHpRestore", true, false) as SpinBox).value = 12
	(form.find_child("ItemCombatRange", true, false) as SpinBox).value = 3
	(form.find_child("ItemCombatDelay", true, false) as SpinBox).value = 175
	_check(form.get("_combat_delay").get_parent().visible, "combat use settings stayed hidden")
	var path: String = session.path
	_check(not FileAccess.file_exists(path), "item UI published before Save")
	hub.call("_save_draft")
	_check(FileAccess.file_exists(path), "composed item Save failed: " + session.last_error)
	_check(hub.get("_category_id").is_empty() and hub.call("selected_record").get("id") == "operations_fixture_library", "type change hid the saved item behind its old filter")
	hub.call("begin_edit")
	var saved: Dictionary = hub.get("_session").draft.definition
	_check(not saved.has("loadouts") and not saved.has("preview") and not saved.has("level"), "editor fitting context leaked into item Resource")
	_check(saved.get("combatDelay") == 175 and saved.get("combatRange") == 3 and saved.get("mpBonus") == -3 and saved.get("allowedHeroIds") == ["mira", "future_hero"] and saved.get("futureMetadata") == {"keep": [1, 2, 3]}, "item properties did not survive native save/reopen")
	var state := Combat.initial_state(17)
	var actor_id := Combat.current_unit_id(state)
	state.units[actor_id].hp = maxi(1, int(state.units[actor_id].maxHp) - 5)
	state = Combat.with_inventory(state, {"operations_fixture_library": 1}, {"operations_fixture_library": saved})
	var command := Combat.command_definition(state, "item:operations_fixture_library")
	_check(command.get("delay") == 175 and command.get("range") == 3, "item parameters did not reach combat command")
	var preview := Combat.preview(state, "item:operations_fixture_library", actor_id)
	_check(bool(preview.get("ok", false)), "authored item could not preview in combat")
	var committed := Combat.commit(state, preview)
	_check(int(committed.get("inventory", {}).get("operations_fixture_library", 0)) == 0, "authored combat item did not consume one stack")
	var invalid := saved.duplicate(true)
	invalid.combatDelay = 0
	_check(not Store.ItemStore.validation_errors(invalid).is_empty(), "zero combat delay was accepted")
	invalid = saved.duplicate(true)
	invalid.kind = "armor"
	invalid.slot = "none"
	_check(not Store.ItemStore.validation_errors(invalid).is_empty(), "unequippable armor was accepted")
	workspace.free()
	await process_frame
