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
	root.add_child(creation)
	creation.open_for()
	await process_frame
	assert(creation.size.x <= 600 and creation.size.y <= 620, "New-map dialog grew beyond its requested size: %s" % creation.size)
	creation._id_field.text = "compact_dialog_layout_test"
	creation._prepare()
	await process_frame
	assert(creation.size.x <= 600 and creation.size.y <= 620, "Preview expanded the new-map dialog: %s" % creation.size)
	creation._id_field.text = "a".repeat(48)
	creation._prepare()
	await process_frame
	assert(creation.size.x <= 600 and creation.size.y <= 620, "Long valid ID expanded the new-map dialog: %s" % creation.size)
	creation._id_field.text = "coast_dialog_layout"
	creation._preset.select(1)
	creation._preset_changed(1)
	creation._prepare()
	await process_frame
	assert(creation.size.x <= 600 and creation.size.y <= 680, "Coast preview expanded the new-map dialog: %s" % creation.size)
	creation.hide()
	creation.free()
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
