extends SceneTree

const CreationDialog = preload("res://addons/ember_import/ember_compact_map_dialog.gd")
const ExtensionDialog = preload("res://addons/ember_import/ember_compact_map_extension_dialog.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var map := EmberMapLoader.new()
	map.authored_size_blocks = Vector2i(24, 24)
	root.add_child(map)
	var creation := CreationDialog.new()
	var dock := VBoxContainer.new(); dock.size = Vector2(302, 600)
	var theme := Theme.new(); theme.default_font_size = 20; dock.theme = theme
	root.add_child(dock); dock.add_child(creation)
	creation.open_for()
	await process_frame
	assert(creation.get_class() == "VBoxContainer" and creation.get_combined_minimum_size().x <= 302, "New-map dock horizontal overflow")
	creation._id_field.text = "compact_dialog_layout_test"
	creation._prepare()
	await process_frame
	assert(creation.get_combined_minimum_size().x <= 302, "Preview expanded new-map dock")
	creation._id_field.text = "a".repeat(48)
	creation._prepare()
	await process_frame
	assert(creation.get_combined_minimum_size().x <= 302, "Long ID expanded new-map dock")
	creation._id_field.text = "coast_dialog_layout"
	creation._preset.select(1)
	creation._preset_changed(1)
	creation._prepare()
	await process_frame
	assert(creation.get_combined_minimum_size().x <= 302, "Coast preview expanded new-map dock")
	creation._scroll.scroll_vertical = 10000
	for i in 4: await process_frame
	assert(creation.get_global_rect().encloses(creation.get_create_button().get_global_rect()), "Create outside pinned footer")
	assert(creation.get_global_rect().encloses(creation._preview_button.get_global_rect()), "Preview outside pinned footer")
	creation.hide()
	creation.free(); dock.free()
	var extension := ExtensionDialog.new()
	root.add_child(extension)
	extension.open_for(map)
	await process_frame
	assert(extension.size.x <= 500 and extension.size.y <= 320, "Extension dialog grew beyond its requested size: %s" % extension.size)
	extension.hide()
	extension.free()
	map.free()
	print("COMPACT_DIALOG_LAYOUT flat_and_coast=ok extension=ok")
	quit()
