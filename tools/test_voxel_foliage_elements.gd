extends SceneTree
const Provider = preload("res://addons/ember_import/ember_voxel_large_tree_generator.gd")
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const GenerationPanel = preload("res://addons/ember_import/ember_voxel_generation_panel.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	# Captured from the pre-B provider: current species, seed 7, height 80, clouds v2.
	var golden: Array[String] = [
		"d189eff55093d67b94c3aaf804c7a0f7e8c0ad2f5566d886e9ec8db3292c7d27",
		"8b5cda3890255e832653edf9f7835d593ebc850f6faa17baffd4e04d91a8f6d2",
		"ecda8605d3da7d60179d1cceada68239a221f5a9d28d4975780e5f93d78ab1a2",
		"a6cedf2e970b3993764e34e7aba44f20bc667eeac1974af011700f8b8af46c14",
		"4efb1ba3dd01bcb699f46bb05f665378906b2e931aa7b59f0422473f46ca0380"]
	for kind in 5:
		var settings := Provider.defaults()
		settings.tree_type = kind; settings.generation_version = Provider.LATEST_VERSIONS[kind]
		settings.height = 80; settings.foliage_style = 3
		var baseline := Provider.build(settings, 7, Color.WHITE, {}, "Fixture", "flat_fixture")
		check(not baseline.has("error"), "baseline builds")
		if baseline.has("error"): continue
		check(baseline.geometry.voxels.hex_encode().sha256_text() == golden[kind], "default preserves pre-B species %d" % kind)
		for detail in 2:
			settings.foliage_volume_form = 1; settings.foliage_element_size = detail
			var built := Provider.build(settings, 7, Color.WHITE, {}, "Fixture", "flat_fixture")
			check(not built.has("error"), "B builds %d/%d" % [kind, detail])
			if built.has("error"): continue
			var source: EmberVoxelModelResource = built.geometry
			check(source.validation_errors().is_empty(), "canonical B validates")
			check(source.collision_voxels == baseline.geometry.collision_voxels, "B preserves exact collision")
			check(source.palette == baseline.geometry.palette and source.material == baseline.geometry.material, "B preserves palette and material roles")
			var wood_same := true
			for index in source.voxels.size():
				if int(baseline.geometry.voxels[index]) in [1, 2, 3, 7] and source.voxels[index] != baseline.geometry.voxels[index]: wood_same = false; break
			check(wood_same, "B preserves wood including bark marks")
			check(source.voxels != baseline.geometry.voxels, "B changes foliage geometry")
			var frozen := Provider.build_on_structure(settings, built.structure, 7, {}, "Fixture", "flat_fixture")
			check(not frozen.has("error") and frozen.geometry.voxels == source.voxels, "frozen B preview repeats exactly")
			settings.foliage_volume_form = 0
			var reverted := Provider.build_on_structure(settings, built.structure, 7, {}, "Fixture", "flat_fixture")
			check(not reverted.has("error") and reverted.geometry.voxels == baseline.geometry.voxels, "form switch returns to baseline on the same scaffold")
			settings.foliage_volume_form = 1
	# Partial-height buckets and wood override, without growing the canonical grid.
	var toy := EmberVoxelModelResource.new()
	toy.model_id = "flat_toy"; toy.height_voxels = 5
	toy.palette = PackedColorArray([Color.TRANSPARENT, Color.BROWN, Color.BROWN, Color.BROWN, Color.GREEN, Color.GREEN, Color.GREEN])
	toy.voxels.resize(16 * 5 * 16); toy.collision_voxels.resize(toy.voxels.size())
	var leaf_index := 2 + 16 * (3 + 16 * 4)
	var wood_index := 3 + 16 * (3 + 16 * 4)
	toy.voxels[leaf_index] = 5; toy.voxels[wood_index] = 1; toy.collision_voxels[wood_index] = 1
	var before := toy.voxels.duplicate()
	var flat := Provider.FoliageElements.apply(toy, 0)
	check(toy.voxels == before, "conversion keeps input detached")
	check(flat.grid_size() == toy.grid_size() and flat.voxels.size() == before.size(), "last short bucket stays in bounds")
	check(flat.voxels.count(5) == 63 and flat.voxels[wood_index] == 1, "8x4x8 fills clipped final row around preserved wood")
	check(flat.collision_voxels == toy.collision_voxels, "new visual foliage does not add collision")
	var directory := "user://flat_elements_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := directory.path_join("edited.tres")
	# A normal manual edit remains ordinary voxel data through save/reopen.
	flat.voxels[leaf_index] = 0
	check(ResourceSaver.save(flat, file) == OK, "manual leaf edit saves")
	var reopened = ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(reopened != null and reopened.voxels[leaf_index] == 0 and reopened.voxels == flat.voxels, "manual edit survives reopen")
	var panel := GenerationPanel.new(); root.add_child(panel); await process_frame
	check(panel.controls.has("foliage_volume_form"), "native creation exposes form")
	check(not panel.controls.foliage_element_size.get_parent().visible, "size hidden for ordinary form")
	panel._change_parameter("foliage_volume_form", 1)
	check(panel.recipe.parameters.foliage_volume_form == 1 and panel.controls.foliage_element_size.get_parent().visible, "B shows size choice")
	panel._change_parameter("foliage_element_size", 1)
	panel.undo_local()
	check(panel.recipe.parameters.foliage_element_size == 0, "size Undo")
	panel.undo_local()
	check(panel.recipe.parameters.foliage_volume_form == 0, "form Undo")
	panel.redo_local(); panel.redo_local()
	check(panel.recipe.parameters.foliage_volume_form == 1 and panel.recipe.parameters.foliage_element_size == 1, "form/size Redo")
	panel.free()
	print("Voxel foliage elements: ", "PASS" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)
