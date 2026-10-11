extends SceneTree
const MapPanel = preload("res://addons/ember_import/ember_compact_map_dialog.gd")
const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const DIRECTORY := "user://compact_map_dock_test"
var created_path := ""
var cancelled := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var dock := VBoxContainer.new(); dock.size = Vector2(302, 600)
	var theme := Theme.new(); theme.default_font_size = 20; dock.theme = theme
	root.add_child(dock)
	var panel := MapPanel.new(); dock.add_child(panel); panel.open_for()
	assert(not panel.is_dirty(), "new map has pending settings before editing")
	panel.creation.scene_directory = DIRECTORY.path_join("scenes")
	panel.creation.terrain_directory = DIRECTORY.path_join("terrains")
	panel.created.connect(func(path): created_path = path)
	panel.cancel_requested.connect(func(): cancelled = true; panel.clear_preview(); panel.hide())
	var id := "dock_" + str(OS.get_process_id())
	panel._id_field.text = " " + id.to_upper() + " "; panel._height.value = 48; panel._depth.value = 2
	assert(panel.is_dirty(), "new map does not protect modified settings")
	panel._preview_button.pressed.emit()
	assert(not panel.get_create_button().disabled and panel._swatch.visible)
	assert(not FileAccess.file_exists(panel.creation.scene_path()))
	assert(not FileAccess.file_exists(panel.creation.terrain_path()))
	assert(panel.creation.map_id == id and panel._preview_label.text.contains(id), "preview filename differs from canonical ID")
	var candidate: Terrain = panel.creation.source
	for i in 5: await process_frame
	assert(panel.get_combined_minimum_size().x <= 302, "narrow dock overflow")
	panel._scroll.scroll_vertical = 10000
	for i in 5: await process_frame
	assert(panel.get_global_rect().encloses(panel.get_create_button().get_global_rect()))
	assert(panel.get_global_rect().encloses(panel._preview_button.get_global_rect()))
	panel.open_for(); assert(panel.creation.source == candidate, "reopening lost prepared candidate")
	panel.get_create_button().pressed.emit()
	assert(created_path == panel.creation.scene_path() and not panel.visible)
	var saved := ResourceLoader.load(panel.creation.terrain_path(), "", ResourceLoader.CACHE_MODE_IGNORE) as Terrain
	assert(saved.same_terrain_data(candidate.sectioned_copy()), "Create lost preview terrain")
	var packed := ResourceLoader.load(created_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var scene := packed.instantiate()
	assert(scene.get_node("Map").compact_terrain.same_terrain_data(candidate.sectioned_copy()))
	scene.free()
	var terrain_path: String = panel.creation.terrain_path()
	var hash := FileAccess.get_sha256(terrain_path)
	panel.open_for(); panel._prepare()
	assert(panel.get_create_button().disabled and not panel.creation.error.is_empty())
	assert(FileAccess.get_sha256(terrain_path) == hash, "duplicate preparation changed file")
	var committed := created_path; created_path = ""
	panel._id_field.text = "a".repeat(48); panel._preset.select(1); panel._preset_changed(1)
	panel._depth.value = 1; panel._prepare()
	assert(not panel.get_create_button().disabled and panel._texture.texture != null)
	for i in 5: await process_frame
	assert(panel.get_combined_minimum_size().x <= 302, "long ID/coast overflow")
	panel._seed.value += 1
	assert(panel.get_create_button().disabled and panel.creation.source == null and panel._texture.texture == null)
	panel._id_field.text = id + "_cancel"; panel._prepare()
	var cancelled_path: String = panel.creation.scene_path()
	panel.cancel_requested.emit()
	assert(cancelled and not panel.visible and panel.creation.source == null and created_path.is_empty())
	assert(not FileAccess.file_exists(cancelled_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(committed))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(terrain_path))
	dock.free()
	print("COMPACT_MAP_DOCK PASS narrow/pinned/flat/coast/long-ID/reopen/invalidation/no-preview-writes/exact-create/duplicate/cancel")
	quit()
