extends SceneTree
## Rim frame width is a material setting: Pattern field + validation, GPU lookup, editor slider with
## live preview, Undo/Redo, Save/Reopen and Cancel/Discard. Uses user:// copies only.
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
const Dialog = preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
var errors: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: errors.append(message); printerr("FAIL ", message)
func run() -> void:
	DirAccess.make_dir_recursive_absolute("user://ember-tests")
	var stone: EmberCompactTerrainPattern = Materials.load_compact_terrain_variant("cartoon_stone")
	check(stone != null and is_equal_approx(stone.style_rim_width_mm, 10.0) and stone.validation_errors().is_empty(), "shipped stone has a 10 mm frame")
	var legacy: EmberCompactTerrainPattern = Materials.load_compact_terrain_variant("painted_light_grass")
	check(is_zero_approx(legacy.style_rim_width_mm), "other materials default to no frame limit")
	for bad_value in [NAN, -1.0, 50.5]:
		var bad := stone.duplicate(true) as EmberCompactTerrainPattern
		bad.style_rim_width_mm = bad_value
		check(not bad.validation_errors().is_empty(), "invalid width rejected: " + str(bad_value))
	var path := "user://ember-tests/rim-width-pattern.tres"
	check(ResourceSaver.save(stone.duplicate(true), path) == OK, "fixture saved")
	var material := Materials.compact_terrain_material()
	Materials.set_compact_terrain_roles(material, PackedStringArray(["", "stone"]), PackedStringArray(["", "cartoon_stone"]), PackedColorArray(), {"cartoon_stone": stone})
	var lookup: Image = material.get_meta("ember_style_rim_image")
	check(is_equal_approx(lookup.get_pixel(1, 0).a, 0.010), "GPU lookup carries the width in metres")
	var panel := Dialog.new(); root.add_child(panel); root.add_child(panel.parameters_panel)
	panel.light_profile_previewed.connect(func(pattern, _id): Materials.update_style_rim_profile(material, 1, pattern))
	panel.pattern_path_override = path
	check(panel.open_variant("cartoon_stone", "stone"), "pattern opens in the material editor")
	check(is_equal_approx(panel._style_rim_width_slider.value, 10.0), "slider shows the saved width")
	var identity: int = material.get_shader_parameter("style_rim_lookup").get_instance_id()
	panel._style_rim_width_slider.value = 14.0
	check(is_equal_approx(panel._draft.style_rim_width_mm, 14.0) and is_equal_approx(lookup.get_pixel(1, 0).a, 0.014), "slider previews live in the GPU lookup")
	check(material.get_shader_parameter("style_rim_lookup").get_instance_id() == identity, "no new texture or material rebuild")
	check(panel.is_dirty(), "edit marks the draft dirty")
	panel.undo_edit()
	check(is_equal_approx(panel._draft.style_rim_width_mm, 10.0) and is_equal_approx(lookup.get_pixel(1, 0).a, 0.010), "Undo restores the width and the preview")
	panel.redo_edit()
	check(is_equal_approx(panel._draft.style_rim_width_mm, 14.0), "Redo reapplies the width")
	check(panel._save(true), "save")
	var saved: EmberCompactTerrainPattern = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(is_equal_approx(saved.style_rim_width_mm, 14.0) and saved.style_rim_strength == stone.style_rim_strength and saved.pixels == stone.pixels, "reopen keeps the width; other fields unchanged")
	var hash := FileAccess.get_sha256(path)
	panel._style_rim_width_slider.value = 3.0
	check(is_equal_approx(lookup.get_pixel(1, 0).a, 0.003) and panel.is_dirty(), "new edit previews")
	panel.cancel_edit()
	check(FileAccess.get_sha256(path) == hash, "discard leaves the file untouched")
	check(is_equal_approx(lookup.get_pixel(1, 0).a, 0.014), "discard restores the saved preview")
	panel.free()
	print("RIM_WIDTH_CONTROL ", "PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
