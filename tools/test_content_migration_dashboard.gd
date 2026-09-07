extends SceneTree
## Guarded dashboard gate: report rows remain read-only and the one bounded
## migration action stays disabled until the exact batch has been reviewed.

const Report = preload("res://addons/ember_import/ember_content_migration_report.gd")
const Dashboard = preload("res://addons/ember_import/ember_content_migration_dashboard.gd")
const Parity = preload("res://addons/ember_import/ember_voxel_migration_parity.gd")
const Batches = preload("res://addons/ember_import/ember_voxel_migration_batches.gd")


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	quit(await _run())


func _run() -> int:
	var errors: Array[String] = []
	var report := Report.build()
	var dashboard := Dashboard.new()
	dashboard.set_report(report)
	var entry_list := dashboard.find_child("MigrationEntryList", true, false) as ItemList
	var summary := dashboard.find_child("MigrationRowsSummary", true, false) as Label
	var detail := dashboard.find_child("MigrationEntryDetail", true, false) as RichTextLabel
	if entry_list == null or summary == null or detail == null:
		errors.append("dashboard is missing its list, summary or detail pane")
	else:
		var total := int((report.get("totals", {}) as Dictionary).get("total", -1))
		if entry_list.item_count != total:
			errors.append("dashboard does not initially show the full inventory")
		dashboard.set_filter("voxel", "sandbox_batch")
		if entry_list.item_count != 6:
			errors.append("sandbox shortcut does not retain its six scene models")
		if not summary.text.contains("уже перенесена в Godot"):
			errors.append("sandbox batch does not explain its completed native state")
		if not detail.text.contains("agent_sandbox"):
			errors.append("selected sandbox row does not explain where the model is used")
		if not detail.text.contains("Владелец: Godot"):
			errors.append("selected sandbox row does not show native ownership")
		dashboard.set_filter("voxel", "fan_town_ready_batch")
		if entry_list.item_count != 7:
			errors.append("fan_town ready batch does not retain its seven reviewed models")
		if not detail.text.contains("fan_town"):
			errors.append("selected fan_town row does not explain where the model is used")
		dashboard.set_filter("vn", "attention", "49bd31e4-b1e2-495d-b57d-eb01994be362")
		if entry_list.item_count != 1 or not detail.text.contains("Файл изображения не найден"):
			errors.append("known missing VN asset cannot be found with combined filters")
	var quick_batch := dashboard.find_child("ShowSandboxMigrationBatch", true, false) as Button
	if quick_batch == null:
		errors.append("dashboard has no one-click sandbox batch filter")
	else:
		dashboard.set_filter("all", "all")
		quick_batch.pressed.emit()
		if dashboard.visible_entries().size() != 6:
			errors.append("one-click sandbox batch filter is not wired")
	var quick_fan_town := dashboard.find_child("ShowFanTownReadyMigrationBatch", true, false) as Button
	if quick_fan_town == null:
		errors.append("dashboard has no one-click fan_town batch filter")
	else:
		dashboard.set_filter("all", "all")
		quick_fan_town.pressed.emit()
		if dashboard.visible_entries().size() != 7:
			errors.append("one-click fan_town batch filter is not wired")
	if _button_with_text(dashboard, "Перенести всё") != null:
		errors.append("dashboard exposes an unjustified bulk migration action")
	var preflight := dashboard.find_child("PreflightVoxelMigrationBatch", true, false) as Button
	var migrate_batch := dashboard.find_child("MigrateVoxelBatch", true, false) as Button
	var preflight_status := dashboard.find_child("MigrationPreflightStatus", true, false) as Label
	var requested_preflight: Array[Array] = []
	var requested_migration: Array[Array] = []
	dashboard.preflight_requested.connect(func(ids: Array[String]) -> void: requested_preflight.append(ids))
	dashboard.migrate_batch_requested.connect(func(ids: Array[String]) -> void: requested_migration.append(ids))
	if preflight == null or migrate_batch == null or preflight_status == null:
		errors.append("dashboard lacks guarded batch preflight controls")
	else:
		var pending_report := report.duplicate(true)
		var completed_report := report.duplicate(true)
		for raw_entry in ((pending_report.get("domains", {}) as Dictionary).get("voxel", {}) as Dictionary).get("entries", []):
			var entry: Dictionary = raw_entry
			if str(entry.get("id", "")) in Batches.model_ids("fan_town_ready"):
				entry["owner"] = "legacy"
				entry["status"] = "legacy"
		for raw_entry in ((completed_report.get("domains", {}) as Dictionary).get("voxel", {}) as Dictionary).get("entries", []):
			var entry: Dictionary = raw_entry
			if str(entry.get("id", "")) in Batches.model_ids("fan_town_ready"):
				entry["owner"] = "native"
				entry["status"] = "native"
		dashboard.set_report(completed_report)
		if not preflight.disabled or not migrate_batch.disabled:
			errors.append("completed fan_town batch still enables migration controls")
		dashboard.set_report(pending_report)
		if preflight.disabled:
			errors.append("pending fan_town candidates do not enable dry-run")
		preflight.pressed.emit()
		if requested_preflight.size() != 1 or requested_preflight[0] != Batches.model_ids("fan_town_ready"):
			errors.append("preflight does not route the seven reviewed candidates")
		var parity := Parity.inspect_batch(requested_preflight[0])
		dashboard.set_preflight(parity)
		if migrate_batch.disabled or not preflight_status.text.contains("7/7"):
			errors.append("successful dry-run does not unlock the exact reviewed batch")
		migrate_batch.pressed.emit()
		if requested_migration.size() != 1 or requested_migration[0] != requested_preflight[0]:
			errors.append("migration request differs from the reviewed batch")
		dashboard.set_report(completed_report)
		if not preflight.disabled or not migrate_batch.disabled:
			errors.append("native inventory does not invalidate the previous dry-run")
	var refresh_events: Array[bool] = []
	var save_events: Array[bool] = []
	dashboard.refresh_requested.connect(func() -> void: refresh_events.append(true))
	dashboard.save_requested.connect(func() -> void: save_events.append(true))
	var refresh := dashboard.find_child("RefreshMigrationDashboard", true, false) as Button
	var save := dashboard.find_child("SaveMigrationDashboardJson", true, false) as Button
	if refresh == null or save == null:
		errors.append("dashboard lacks refresh or JSON export routing")
	else:
		refresh.pressed.emit()
		save.pressed.emit()
		if refresh_events.size() != 1 or save_events.size() != 1:
			errors.append("dashboard actions are not routed back to the workflow")
	if "--visual" in OS.get_cmdline_user_args():
		var host := Control.new()
		host.size = Vector2(1280.0, 720.0)
		root.add_child(host)
		dashboard.position = Vector2(20.0, 20.0)
		dashboard.size = Vector2(1240.0, 680.0)
		host.add_child(dashboard)
		dashboard.set_filter("voxel", "fan_town_ready_batch")
		for frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var screenshot := root.get_texture().get_image()
		screenshot.crop(1280, 720)
		screenshot.save_png("user://ember_content_migration_dashboard_test.png")
		print("VISUAL: ", ProjectSettings.globalize_path("user://ember_content_migration_dashboard_test.png"))
		host.free()
	else:
		dashboard.free()
	if not errors.is_empty():
		printerr("FAIL content migration dashboard")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS content migration dashboard")
	print("  complete inventory + combined filters")
	print("  completed sandbox + seven-entry fan_town batch")
	print("  no unreviewed bulk migration action")
	return 0


func _button_with_text(node: Node, text_value: String) -> Button:
	if node is Button and (node as Button).text == text_value:
		return node as Button
	for child in node.get_children():
		var found := _button_with_text(child, text_value)
		if found != null:
			return found
	return null
