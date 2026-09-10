extends SceneTree
## Native layout contract for the persistent 3D object shelf. The shelf keeps
## placement context, catalog and the primary action visible without a modal.

const ObjectLibrary = preload("res://addons/ember_import/ember_voxel_object_library_panel.gd")

var failures := 0
var placed_id := ""


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 420)
	var panel = ObjectLibrary.new()
	root.add_child(panel)
	panel.size = Vector2(root.size)
	panel.open_for(null, true, "Место: рядом с «PierCrates» · смещение +X")
	for frame in 8:
		await process_frame

	check(panel.name == "EmberVoxelObjectLibrary", "object shelf was not constructed")
	check(panel.custom_minimum_size.x <= 760.0, "object shelf minimum width can overflow the editor center")
	check(panel.find_child("VoxelObjectPlacementContext", true, false) != null, "placement context is missing")
	check(panel._context_label.text.contains("PierCrates") and panel._context_label.text.contains("+X"), "placement target is not explicit")
	check(panel.find_child("VoxelObjectLibraryFilters", true, false) != null, "owner filters are missing")
	check(panel._picker != null and not panel._picker._actions.visible, "catalog still shows its duplicate modal action row")
	check(panel.find_child("VoxelObjectLibraryDetails", true, false) != null, "fixed details column is missing")
	check(panel._place_button != null and not panel._place_button.disabled, "primary placement action is unavailable")
	check(panel._place_button.theme_type_variation == &"WorkshopPrimaryButton", "placement action is not visually primary")
	check(panel._name_label.text != "" and panel._id_label.text != "", "selected object details are empty")
	check(panel._metadata_label.text.contains("Размер:"), "selected object scale is not exposed")
	check(panel._place_button.get_global_rect().end.x <= panel.get_global_rect().end.x + 1.0, "placement action overflows the shelf horizontally")
	check(panel._place_button.get_global_rect().end.y <= panel.get_global_rect().end.y + 1.0, "placement action is clipped at compact height")
	check(panel.get_combined_minimum_size().y <= panel.size.y + 1.0, "object details force the shelf beyond its compact height")
	check(panel.find_children("*", "PopupPanel", true, false).is_empty(), "object library still depends on a modal popup")

	var expected_native := 0
	var expected_legacy := 0
	var native_id := ""
	for entry in panel._all_entries:
		if str(entry.get("owner", "")) == "godot":
			expected_native += 1
			if native_id.is_empty():
				native_id = str(entry.get("id", ""))
		elif str(entry.get("owner", "")) == "legacy_import":
			expected_legacy += 1
	var preview_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	preview_image.fill(Color(0.25, 0.5, 0.75))
	var cached_preview := ImageTexture.create_from_image(preview_image)
	panel._apply_filter(native_id)
	panel._on_preview_ready(native_id, cached_preview)
	check(panel._picker.selected_entry().get("texture") == cached_preview, "preview fixture was not attached before filtering")
	(panel._filter_buttons["godot"] as Button).pressed.emit()
	await process_frame
	check(panel._picker._entries.size() == expected_native, "Godot owner filter has the wrong catalog projection")
	check(panel._picker.selected_id() == native_id and panel._picker.selected_entry().get("texture") == cached_preview, "Godot filter drops an in-memory preview")
	(panel._filter_buttons["all"] as Button).pressed.emit()
	await process_frame
	check(panel._picker.selected_id() == native_id and panel._picker.selected_entry().get("texture") == cached_preview, "returning to all objects drops an in-memory preview")
	(panel._filter_buttons["legacy_import"] as Button).pressed.emit()
	await process_frame
	check(panel._picker._entries.size() == expected_legacy, "legacy owner filter has the wrong catalog projection")
	(panel._filter_buttons["all"] as Button).pressed.emit()
	await process_frame
	check(panel._picker._entries.size() == panel._all_entries.size(), "all-objects filter does not restore the catalog")

	panel.place_requested.connect(func(model_id: String, _anchor: Node3D) -> void: placed_id = model_id)
	panel._place_button.pressed.emit()
	check(placed_id == panel._picker.selected_id(), "primary action does not emit the selected canonical model ID")

	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		for frame in 20:
			await process_frame
		var capture := "user://voxel_object_library.png"
		root.get_texture().get_image().save_png(capture)
		print("VOXEL_OBJECT_LIBRARY_CAPTURE ", ProjectSettings.globalize_path(capture))

	root.size = Vector2i(1600, 500)
	panel.size = Vector2(root.size)
	for frame in 3:
		await process_frame
	check(panel._picker.size.x > 700.0, "catalog does not expand at design width")
	check(panel._place_button.get_global_rect().end.x <= panel.get_global_rect().end.x + 1.0, "details column overflows at design width")
	panel._preview_renderer.cancel_pending()
	for frame in 4:
		await process_frame
	panel.free()
	print("test_voxel_object_library_layout: ", "PASS" if failures == 0 else "FAIL", " · ", failures)
	quit(failures)
