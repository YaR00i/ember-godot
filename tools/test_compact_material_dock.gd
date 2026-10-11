extends SceneTree
const Editor = preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
const Pattern = preload("res://scripts/ember_compact_terrain_pattern.gd")
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
var saved: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var first := "user://material_dock_first.tres"
	var second := "user://material_dock_second.tres"
	var source := Materials.load_compact_terrain_pattern("grass")
	assert(ResourceSaver.save(source.duplicate(true), first) == OK)
	assert(ResourceSaver.save(source.duplicate(true), second) == OK)
	var editor := Editor.new(); root.add_child(editor); editor.size = Vector2(800, 350)
	var dock := VBoxContainer.new(); dock.size = Vector2(302, 600)
	var theme := Theme.new(); theme.default_font_size = 20; dock.theme = theme
	root.add_child(dock); dock.add_child(editor.parameters_panel)
	editor.set_variant_choices([{"id": "first", "role": "grass"}, {"id": "second", "role": "grass"}])
	editor.pattern_saved.connect(func(_pattern, id): saved.append(id))
	editor.pattern_path_override = first; assert(editor.open_variant("first", "grass"))
	for i in 5: await process_frame
	assert(editor.parameters_panel.get_combined_minimum_size().x <= 302)
	assert(editor._canvas_scroll.size.y >= 256 and editor._canvas_scroll.get_global_rect().encloses(editor._grid.get_global_rect()))
	assert(editor.parameters_panel.get_global_rect().encloses(editor._save_button.get_global_rect()))
	var original_hash := FileAccess.get_sha256(first)
	editor._finish_sliders.gloss.value = 0.55
	assert(editor.is_dirty())
	assert(editor.open_variant("first", "grass") and editor._draft.gloss == 0.55, "repeat lost draft")
	editor.pattern_path_override = second; assert(editor.open_variant("second", "grass"))
	assert(editor._id == "first" and editor._switch_box.visible and editor._draft.gloss == 0.55)
	editor._resolve_variant_switch(false)
	assert(editor._id == "second" and not editor.is_dirty() and FileAccess.get_sha256(first) == original_hash)
	editor._finish_sliders.sheen.value = 0.7
	var undo := InputEventKey.new(); undo.pressed = true; undo.ctrl_pressed = true; undo.keycode = KEY_Z
	assert(editor.handle_history_key(undo) and not editor.is_dirty())
	undo.keycode = KEY_Y; assert(editor.handle_history_key(undo) and editor.is_dirty())
	editor.pattern_path_override = first; assert(editor.open_variant("first", "grass"))
	editor._resolve_variant_switch(true)
	assert(editor._id == "first" and saved == ["second"])
	var stored := ResourceLoader.load(second, "", ResourceLoader.CACHE_MODE_IGNORE) as Pattern
	assert(is_equal_approx(stored.sheen, 0.7), "switch saved wrong source path")
	editor._finish_sliders.pixel_relief.value = 0.12
	var external := source.duplicate(true) as Pattern; external.gloss = 0.8
	assert(ResourceSaver.save(external, first) == OK)
	assert(not editor._save() and editor._draft != null and editor.is_dirty(), "stale Save lost draft")
	var external_hash := FileAccess.get_sha256(first)
	editor.hide(); editor.show()
	assert(editor.is_dirty(), "collapsing panel discarded draft")
	editor._show_new_variant(); assert(editor._new_variant_box.visible)
	editor.cancel_edit()
	assert(editor._draft == null and not editor._new_variant_box.visible and FileAccess.get_sha256(first) == external_hash)
	assert(editor.open_variant("first", "grass") and editor._draft.gloss == 0.8)
	editor._parameter_scroll.scroll_vertical = 10000
	for i in 5: await process_frame
	assert(editor.parameters_panel.get_global_rect().encloses(editor._save_button.get_global_rect()))
	editor.free(); dock.free()
	print("COMPACT_MATERIAL_DOCK PASS narrow/pinned/repeat/pending-switch/discard-switch/save-switch/original-path/history/stale-save/collapse/cancel/reopen")
	quit()
