extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_native_editor_test_fixture.gd")
const Report = preload("res://addons/ember_import/ember_content_migration_report.gd")
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
	var errors: Array[String] = []
	if report.schema != 1 or report.totals.legacy_remaining != 0: errors.append("native report revived legacy owner")
	var total := 0
	for domain_name in ["voxel", "action", "dialogue", "item", "shop", "vn"]:
		if not report.domains.has(domain_name):
			errors.append("domain missing: " + domain_name)
			continue
		var domain: Dictionary = report.domains[domain_name]
		var counts: Dictionary = domain.counts
		if counts.total != counts.native + counts.legacy_remaining + counts.missing or domain.entries.size() != counts.total: errors.append("domain counts inconsistent")
		total += int(counts.total)
	if total != report.totals.total or Report.filtered_entries(report).size() != total: errors.append("report totals inconsistent")
	var model := Report.filtered_entries(report, "voxel", "all", Fixture.ID)
	if model.size() != 1 or model[0].owner != "native" or model[0].derived_status != "missing": errors.append("missing native derivative diagnostic lost")
	var path := str(_state.directory).path_join("diagnostics.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
	var reopened: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	if reopened.get("schema") != 1 or reopened.totals.total != total: errors.append("user diagnostic export/reopen failed")
	if not Fixture.unchanged(saved): errors.append("report changed source files")
	if not errors.is_empty():
		printerr("FAIL native content report: ", "; ".join(errors))
		quit(1)
		return
	print("PASS native content report; counts/missing derivative/filter/user export, frozen source and poison JSON")
	quit(0)
