extends SceneTree
## Depth of the detailed look is a material setting: editor sliders, live amplitude, height map re-derived
## only on slider release, Undo/Redo, Save/Reopen and Cancel. user:// copies only.
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
const Solid = preload("res://scripts/ember_voxel_solid_surface.gd")
const Dialog = preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
var errors: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: errors.append(message); printerr("FAIL ", message)
func run() -> void:
	DirAccess.make_dir_recursive_absolute("user://ember-tests")
	var stone: EmberCompactTerrainPattern = Materials.load_compact_terrain_variant("cartoon_stone")
	var prefab: PackedScene = load("res://prefabs/voxels/vox_painted_rock_group.tscn")
	var instance := prefab.instantiate()
	var mesh := (instance.get_node("Mesh") as MeshInstance3D).mesh as ArrayMesh
	var material := Solid.material_for(mesh, true)
	check(material.shader.code.contains("EMBER_SOLID_DEPTH") and bool(material.get_meta("ember_detailed_depth", false)), "detailed material built")
	check(is_equal_approx(float(material.get_shader_parameter("material_depth_amplitude_m")), 0.02) and bool(material.get_shader_parameter("material_depth_enabled")), "saved 20 mm depth bound")
	var plain := Solid.material_for(mesh, false)
	check(not plain.shader.code.contains("EMBER_SOLID_DEPTH") and plain.get_shader_parameter("material_depth_enabled") == null, "plain low poly material has no depth")
	var path := "user://ember-tests/depth-pattern.tres"
	check(ResourceSaver.save(stone.duplicate(true), path) == OK, "fixture saved")
	var panel := Dialog.new(); root.add_child(panel); root.add_child(panel.parameters_panel)
	panel.light_profile_previewed.connect(func(pattern, id): Solid.update_detail(material, mesh, pattern, id))
	panel.pattern_path_override = path
	check(panel.open_variant("cartoon_stone", "stone"), "pattern opens")
	check(is_equal_approx(panel._depth_sliders.depth_mm.value, 20.0) and is_equal_approx(panel._depth_sliders.depth_softness.value, 2.5), "sliders show the saved depth")
	var height_before: Texture2D = material.get_shader_parameter("material_depth_height")
	# Depth is live.
	panel._depth_sliders.depth_mm.value = 12.0
	check(is_equal_approx(float(material.get_shader_parameter("material_depth_amplitude_m")), 0.012) and material.get_shader_parameter("material_depth_height") == height_before, "depth previews live without re-deriving the height map")
	check(panel.is_dirty(), "edit marks the draft dirty")
	# Softness/sharpness: heavy part only on release.
	var slider: HSlider = panel._depth_sliders.depth_sharpness
	slider.drag_started.emit()
	slider.value = 0.4
	check(material.get_shader_parameter("material_depth_height") == height_before, "no height re-derivation while dragging")
	slider.drag_ended.emit(true)
	var height_after: Texture2D = material.get_shader_parameter("material_depth_height")
	check(height_after != height_before, "height map re-derived on release")
	check(height_after.get_image().get_data() != height_before.get_image().get_data(), "new sharpness changes the map")
	panel.undo_edit()
	check(is_equal_approx(panel._draft.depth_sharpness, 0.1), "Undo restores sharpness")
	panel.undo_edit()
	check(is_equal_approx(panel._draft.depth_mm, 20.0), "Undo restores depth")
	panel.redo_edit(); panel.redo_edit()
	check(is_equal_approx(panel._draft.depth_mm, 12.0) and is_equal_approx(panel._draft.depth_sharpness, 0.4), "Redo reapplies")
	# Face pull of the detailed look: heavy (rebuilds the faces), so it previews once, on release.
	var pull: HSlider = panel._depth_sliders.form_pull_mm
	check(is_equal_approx(pull.value, 30.0), "slider shows the saved face pull")
	var emitted := [0]
	var counter := func(_pattern, _id): emitted[0] += 1
	panel.light_profile_previewed.connect(counter)
	pull.drag_started.emit()
	pull.value = 45.0
	check(emitted[0] == 0 and is_equal_approx(panel._draft.form_pull_mm, 45.0), "no preview rebuild while dragging the face pull")
	pull.drag_ended.emit(true)
	check(emitted[0] == 1, "face pull previews once on release")
	panel.undo_edit()
	check(is_equal_approx(panel._draft.form_pull_mm, 30.0), "Undo restores the face pull")
	panel.redo_edit()
	check(is_equal_approx(panel._draft.form_pull_mm, 45.0), "Redo reapplies the face pull")
	panel.light_profile_previewed.disconnect(counter)
	check(panel._save(true), "save")
	var saved: EmberCompactTerrainPattern = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(is_equal_approx(saved.depth_mm, 12.0) and is_equal_approx(saved.depth_sharpness, 0.4) and is_equal_approx(saved.form_pull_mm, 45.0) and saved.style_rim_width_mm == stone.style_rim_width_mm and saved.pixels == stone.pixels, "reopen keeps depth; other fields unchanged")
	var hash := FileAccess.get_sha256(path)
	panel._depth_sliders.depth_mm.value = 3.0
	panel.cancel_edit()
	check(FileAccess.get_sha256(path) == hash, "discard leaves the file untouched")
	check(is_equal_approx(float(material.get_shader_parameter("material_depth_amplitude_m")), 0.012), "discard restores the saved preview")
	panel.free(); instance.free()
	print("DEPTH_CONTROL ", "PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
