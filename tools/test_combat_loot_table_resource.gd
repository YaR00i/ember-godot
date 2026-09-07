extends SceneTree
## Loot authoring gate: shared Resources, deterministic pure roll, visual item
## rows and Undo/Redo without a second inventory owner.

const Catalog := preload("res://scripts/prototypes/ember_combat_loot_table_catalog.gd")
const LootPanel := preload("res://addons/ember_import/ember_combat_loot_table_inspector_panel.gd")
const UnitCatalog := preload("res://scripts/prototypes/ember_combat_unit_catalog.gd")


func _init() -> void:
	var errors: Array[String] = []
	var expected := PackedStringArray(["swamp_elite_drops", "swamp_raider_drops", "swamp_spirit_drops"])
	if PackedStringArray(Catalog.ids()) != expected:
		errors.append("loot catalog lost authored tables")
	for table in Catalog.resources():
		if not table.validation_errors().is_empty():
			errors.append("table %s invalid: %s" % [table.table_id, " | ".join(table.validation_errors())])
		var first := table.roll("stable-test-key")
		var second := table.roll("stable-test-key")
		if first != second:
			errors.append("table %s produced a different preview for one battle key" % table.table_id)
		var path := "user://loot_%s.tres" % table.table_id
		if ResourceSaver.save(table, path) != OK:
			errors.append("table %s could not be saved" % table.table_id)
		else:
			var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as EmberCombatLootTableResource
			if reopened == null or reopened.content_signature() != table.content_signature():
				errors.append("table %s changed after save/reopen" % table.table_id)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var wisp := UnitCatalog.resource("wisp")
	if wisp == null or wisp.loot_table == null or wisp.loot_table.table_id != "swamp_spirit_drops":
		errors.append("enemy Resource lost its shared loot table")
	var editable := Catalog.resource("swamp_spirit_drops").duplicate(true) as EmberCombatLootTableResource
	var history := UndoRedo.new()
	var panel := LootPanel.new() as EmberCombatLootTableInspectorPanel
	panel.setup(editable, null, history)
	if (
		panel.find_child("CombatLootEntry_0", true, false) == null
		or panel.find_child("CombatLootItem_0", true, false) == null
		or panel.find_child("CombatLootAddEntry", true, false) == null
	):
		errors.append("loot Inspector lost its visual rows or library entry point")
	var before := editable.entries[0].chance_percent
	panel.call("_change_number", 37.5, 0, "chance_percent")
	if not is_equal_approx(editable.entries[0].chance_percent, 37.5):
		errors.append("visual loot row did not commit its chance")
	else:
		history.undo()
		if not is_equal_approx(editable.entries[0].chance_percent, before):
			errors.append("loot table Undo did not restore the row")
		history.redo()
		if not is_equal_approx(editable.entries[0].chance_percent, 37.5):
			errors.append("loot table Redo did not restore the edit")
	history.clear_history(false)
	history.free()
	panel.free()
	if not errors.is_empty():
		printerr("FAIL combat loot table Resource")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS combat loot table Resource")
	print("  enemy types reference shared native loot tables")
	print("  rolls are deterministic for one battle result key")
	print("  Inspector uses item icons, signed rows and Undo/Redo")
	quit(0)
