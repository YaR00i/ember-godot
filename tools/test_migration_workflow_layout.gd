extends SceneTree
## The bottom workflow must never expose its long form as a direct minimum-size
## child. Godot owns the resize/tab strip; Ember content stays scrollable.

const Workflow = preload("res://addons/ember_import/ember_tools_dock.gd")


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	quit(await _run())


func _run() -> int:
	var errors: Array[String] = []
	var dock := Workflow.new()
	dock.call("_build_ui")
	var header := dock.get_node_or_null("WorkflowHeader") as HBoxContainer
	var status := dock.get_node_or_null("WorkflowStatus") as Label
	var scroll := dock.get_node_or_null("WorkflowScroll") as ScrollContainer
	var content := dock.get_node_or_null("WorkflowScroll/WorkflowContent") as VBoxContainer
	if header == null or status == null or scroll == null or content == null:
		errors.append("workflow is not split into fixed header/status and scrollable content")
	else:
		if scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_AUTO:
			errors.append("long workflow content cannot scroll vertically")
		if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			errors.append("workflow can drift horizontally instead of fitting the panel")
		if scroll.size_flags_vertical != Control.SIZE_EXPAND_FILL:
			errors.append("scroll body does not yield to the editor bottom-panel height")
		if content.get_child_count() < 5:
			errors.append("expected workflow sections are not inside the scroll body")
	var close := dock.find_child("CloseMigrationPanel", true, false) as Button
	var close_events: Array[bool] = []
	dock.close_requested.connect(func() -> void: close_events.append(true))
	if close == null:
		errors.append("workflow has no always-visible close action")
	else:
		close.pressed.emit()
		if close_events.size() != 1:
			errors.append("close action does not route to the editor plugin")
	if dock.custom_minimum_size.y > 0.0:
		errors.append("workflow still forces a fixed bottom-panel height")
	if dock.find_child("MigrateSelectedVoxelModel", true, false) == null:
		errors.append("voxel workflow has no Godot migration action")
	if dock.find_child("OpenNativeVoxelModel", true, false) == null:
		errors.append("voxel workflow has no native Resource action")
	var refresh_report := dock.find_child("RefreshContentMigrationReport", true, false) as Button
	var report_summary := dock.find_child("ContentMigrationSummary", true, false) as Label
	if refresh_report == null or report_summary == null:
		errors.append("workflow has no shared G1/G2 inventory")
	else:
		refresh_report.pressed.emit()
		if not report_summary.text.contains("Voxel:") or not report_summary.text.contains("Цепочки:"):
			errors.append("shared G1/G2 inventory did not render its domain summary")
		var measured: Dictionary = dock.get("_content_migration_report")
		if measured.is_empty() or int(measured.get("duration_ms", -1)) < 0:
			errors.append("shared G1/G2 inventory did not retain its read-only report")
	var dashboard := dock.find_child("OpenContentMigrationDashboard", true, false) as Button
	if dashboard == null:
		errors.append("workflow has no filterable G1/G2 detail action")
	elif not dashboard.tooltip_text.contains("не запускает"):
		errors.append("dashboard action does not explain its read-only boundary")
	for legacy_label in ["Эмиссия в JOI · Материал", "Прозрачность в JOI · Материал"]:
		if _button_with_text(dock, legacy_label) != null:
			errors.append("obsolete JOI sculptor action is still visible: %s" % legacy_label)
	if "--visual" in OS.get_cmdline_user_args():
		var host := Control.new()
		host.size = Vector2(1280.0, 720.0)
		root.add_child(host)
		dock.set_script(null)
		dock.position = Vector2(24.0, 20.0)
		dock.size = Vector2(820.0, 680.0)
		host.add_child(dock)
		for frame in 2:
			await process_frame
		var visual_scroll := dock.find_child("WorkflowScroll", true, false) as ScrollContainer
		if visual_scroll != null:
			visual_scroll.scroll_vertical = int(visual_scroll.get_v_scroll_bar().max_value)
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var screenshot := root.get_texture().get_image()
		screenshot.crop(1280, 720)
		screenshot.save_png("user://ember_migration_workflow_test.png")
		print("VISUAL: ", ProjectSettings.globalize_path("user://ember_migration_workflow_test.png"))
		host.free()
	else:
		dock.free()
	if not errors.is_empty():
		printerr("FAIL migration workflow layout")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS migration workflow layout")
	print("  fixed header + close action")
	print("  vertically scrollable grouped content")
	print("  read-only G1/G2 ownership and parity summary")
	print("  filterable G1/G2 detail dashboard route")
	print("  no forced minimum panel height")
	return 0


func _button_with_text(root: Node, text: String) -> Button:
	if root is Button and (root as Button).text == text:
		return root as Button
	for child in root.get_children():
		var found := _button_with_text(child, text)
		if found != null:
			return found
	return null
