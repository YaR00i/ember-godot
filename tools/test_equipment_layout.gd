extends SceneTree
## Native save/layout conversion and explicit two-accessory ownership gate.
const Fixture = preload("res://tools/fixtures/ember_party_test_fixture.gd")
const Party = preload("res://scripts/ember_party_state.gd")
const Equipment = preload("res://scripts/ember_equipment.gd")
var _setup: Dictionary
var _errors: Array[String] = []
var _extra: Array[String] = []
const ACCESSORY := "layout_fixture_accessory"
const SHOES := "layout_fixture_shoes"

func _init() -> void:
	root.size = Vector2i(1280, 720)
	_setup = Fixture.prepare(self)
	if _setup.refused:
		quit.call_deferred(2)
		return
	_run.call_deferred()

func _run() -> void:
	for item in [
		{"id": ACCESSORY, "nameRu": "Проверочный аксессуар", "kind": "accessory", "atk": 2, "def": 1, "hpBonus": 5, "stackMax": 1, "allowedHeroIds": ["mira"]},
		{"id": SHOES, "nameRu": "Проверочная обувь", "kind": "shoes", "def": 2, "mpBonus": 3, "allowedHeroIds": ["mira"]},
	]:
		var path := EmberItemCatalog.native_path(item.id)
		_check(not FileAccess.file_exists(path), "fixture ID collision")
		_check(EmberItemCatalog.write_native(item) == OK, "could not publish fixture item")
		_extra.append(path)
	_test_slots()
	await _test_inventory_ui()
	_test_legacy_save()
	Fixture.verify_sources(_setup, _errors)
	for path in _extra: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not _errors.is_empty(): printerr("FAIL equipment layout: ", "; ".join(_errors))
	else: print("PASS equipment layout: five slots, two accessories/explicit swap/refund, footwear/hero compatibility, native UI, old save mapping/stack overflow/unknown IDs/idempotence/bytes and v2 reopen")
	quit(0 if _errors.is_empty() else 1)

func _test_slots() -> void:
	_check(Equipment.SLOTS == ["weapon", "armor", "shoes", "accessory1", "accessory2"], "canonical slots differ from GDD")
	var state := EmberExploreState.new()
	state.persistence_enabled = false
	state.reset_new_game()
	state.inventory = {ACCESSORY: 3, SHOES: 1, Fixture.WEAPON: 1, Fixture.ARMOR: 1}
	_check(bool(state.equip_item_for_member("orik", ACCESSORY).get("ok")), "accessory should be universal")
	_check(not bool(state.equip_item_for_member("orik", SHOES).get("ok")), "restricted footwear accepted wrong hero")
	_check(bool(state.equip_item_for_member("mira", SHOES).get("ok")), "footwear could not be equipped")
	_check(bool(state.equip_item_for_member("mira", ACCESSORY).get("ok")), "first accessory failed")
	_check(bool(state.equip_item_for_member("mira", ACCESSORY).get("ok")), "second accessory failed")
	var eq: Dictionary = state.party.mira.equipment
	_check(eq.accessory1 == ACCESSORY and eq.accessory2 == ACCESSORY, "automatic equip did not fill both accessory slots")
	var before := state.party_member_view("mira")
	_check(int(before.def) == Party.derived_stats("mira", {}).def + 4, "both accessories and shoes did not contribute defense")
	state.inventory[ACCESSORY] = 1
	_check(bool(state.equip_item_for_member("mira", ACCESSORY, "accessory2").get("ok")), "explicit accessory2 swap failed")
	_check(int(state.inventory.get(ACCESSORY, 0)) == 1, "swap destroyed owned accessory at stack cap")
	var bag := state.inventory.duplicate(true)
	_check(not bool(state.equip_item_for_member("mira", ACCESSORY, "weapon").get("ok")), "accessory entered incompatible explicit slot")
	_check(state.inventory == bag, "invalid slot consumed inventory")
	state.unequip_slot_for_member("mira", "accessory1")
	state.unequip_slot_for_member("mira", "accessory2")
	_check(int(state.inventory.get(ACCESSORY, 0)) == 3, "unequip truncated existing ownership to stackMax")
	state.free()

func _test_inventory_ui() -> void:
	var state := EmberExploreState.new()
	state.persistence_enabled = false
	state.reset_new_game()
	state.inventory = {ACCESSORY: 2, SHOES: 1}
	var ui := EmberInventoryUi.new()
	ui.progress_state = state
	root.add_child(ui)
	await process_frame
	ui.open()
	_check(ui.select_item(ACCESSORY), "UI could not select accessory")
	var target := ui.find_child("InventoryAccessoryTarget", true, false) as OptionButton
	_check(target != null and target.visible, "UI did not offer accessory target slot")
	target.select(2)
	target.item_selected.emit(2)
	ui.confirm()
	_check(state.party.protagonist.equipment.accessory2 == ACCESSORY and state.party.protagonist.equipment.accessory1 == null, "UI explicit second slot did not reach ExploreState")
	for frame in 3: await process_frame
	var scroll := ui.find_child("InventoryContentScroll", true, false) as ScrollContainer
	_check(scroll.get_child(0).get_combined_minimum_size().x <= scroll.size.x + 1, "inventory content overflowed panel width")
	if "--visual" in OS.get_cmdline_user_args():
		for frame in 8: await process_frame
		RenderingServer.force_draw(false)
		var path := "user://equipment-layout-%d.png" % OS.get_process_id()
		_check(root.get_texture().get_image().save_png(path) == OK, "native inventory capture failed")
		print("EQUIPMENT_LAYOUT_CAPTURE ", ProjectSettings.globalize_path(path))
	ui.free()
	state.free()
	await process_frame

func _test_legacy_save() -> void:
	var state := EmberExploreState.new()
	state.persistence_enabled = false
	state.reset_new_game()
	state.storage_root = _setup.directory.path_join("layout-save")
	var payload := state.capture_save("manual", 0)
	payload.inventory = {ACCESSORY: 1, Fixture.ARENA: 999, "unknown_old_helmet": 300, "coin": 20}
	payload.flags = {"layout_progress": true}
	payload.party.mira.level = 3
	payload.party.mira.xp = 47
	payload.party.mira.hp = 7
	payload.party.mira.mp = 4
	payload.party.mira.equipment = {"weapon": Fixture.WEAPON, "arena_weapon": Fixture.ARENA, "head": "unknown_old_helmet", "body": Fixture.ARMOR, "accessory": ACCESSORY}
	# Include known retired slots at their cap, and a duplicate instance in another hero.
	payload.party.orik.equipment = {"head": Fixture.ARMOR, "arena_weapon": Fixture.ARENA}
	var path := state.save_path(0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	var original_sha := FileAccess.get_sha256(path)
	_check(state.load_slot(0), "old v2 load failed")
	_check(FileAccess.get_sha256(path) == original_sha, "load overwrote original old save")
	var member: Dictionary = state.party.mira
	_check(member.equipment.weapon == Fixture.WEAPON and member.equipment.armor == Fixture.ARMOR and member.equipment.accessory1 == ACCESSORY, "approved retained equipment mapping failed")
	_check(member.equipment.shoes == null and member.equipment.accessory2 == null, "migration invented new equipment")
	_check(int(state.inventory.get(Fixture.ARENA)) == 1001 and int(state.inventory.get("unknown_old_helmet")) == 301 and int(state.inventory.get(Fixture.ARMOR)) == 1, "retired item instances were lost/truncated")
	_check(member.level == 3 and member.xp == 47 and member.hp == 7 and member.mp == 4 and state.flags.get("layout_progress") == true, "migration lost progress/vitals")
	var converted_bag := state.inventory.duplicate(true)
	for repeat in 3:
		state.party_view()
		state.capture_save("manual", 0)
	_check(state.inventory == converted_bag, "normalization repeatedly returned retired items")
	_check(state.load_slot(0) and state.inventory == converted_bag, "loading same old file duplicated returned items")
	state.persistence_enabled = true
	var backup := path.get_base_dir().path_join("equipment_migration_backups").path_join(path.get_file() + "-" + original_sha + ".json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(backup.get_base_dir()))
	file = FileAccess.open(backup, FileAccess.WRITE)
	file.store_string("corrupted fixture backup")
	file.close()
	_check(not state.save_slot(0) and FileAccess.get_sha256(path) == original_sha, "failed migration preservation replaced old save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))
	_check(state.save_slot(0), "new canonical loadout Save failed")
	_check(FileAccess.get_sha256(backup) == original_sha, "publication did not retain exact old save migration bytes")
	var saved := EmberPack.parse_json_file(path) as Dictionary
	_check(saved.version == 2 and not saved.party.mira.equipment.has("body") and not saved.party.mira.equipment.has("head"), "canonical loadout kept old keys or broke envelope")
	var loaded := EmberExploreState.new()
	loaded.storage_root = state.storage_root
	_check(loaded.load_slot(0) and loaded.inventory == converted_bag and loaded.party.mira.equipment == member.equipment, "canonical save reopen lost items or duplicated migration")
	loaded.free()
	state.free()

func _check(condition: bool, error: String) -> void:
	if not condition: _errors.append(error)
