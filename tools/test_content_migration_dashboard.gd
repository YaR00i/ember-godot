extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_native_editor_test_fixture.gd")
const Report = preload("res://addons/ember_import/ember_content_migration_report.gd")
const Dashboard = preload("res://addons/ember_import/ember_content_migration_dashboard.gd")
var _state: Dictionary
func _init() -> void:
	_state = Fixture.prepare(self)
	if _state.refused:
		quit.call_deferred(2)
		return
	_run.call_deferred()
func _run() -> void:
	var saved := Fixture.diagnostic_source(_state)
	if saved.is_empty():
		quit(1)
		return
	var report := Report.build()
	var dashboard := Dashboard.new()
	root.add_child(dashboard)
	dashboard.set_report(report)
	var list := dashboard.find_child("MigrationEntryList", true, false) as ItemList
	var errors: Array[String] = []
	if list == null or list.item_count != report.totals.total: errors.append("native dashboard omitted rows")
	dashboard.set_filter("voxel", "all", Fixture.ID)
	if list.item_count != 1 or dashboard.visible_entries()[0].id != Fixture.ID: errors.append("native search lost stable ID")
	dashboard.set_filter("voxel", "attention")
	if list.item_count != 1: errors.append("missing native derivative is not visible")
	for name in ["PreflightVoxelMigrationBatch", "MigrateVoxelBatch", "ShowSandboxMigrationBatch", "ShowFanTownReadyMigrationBatch"]:
		if dashboard.find_child(name, true, false) != null: errors.append("legacy controls remain: " + name)
	if dashboard.has_signal("migrate_batch_requested") or dashboard.has_signal("preflight_requested"): errors.append("legacy forwarding remains")
	if not Fixture.unchanged(saved): errors.append("dashboard changed sources")
	dashboard.free()
	if not errors.is_empty():
		printerr("FAIL native content dashboard: ", "; ".join(errors))
		quit(1)
		return
	print("PASS native content dashboard; search/attention/native rows without historical batches/import")
	quit(0)
