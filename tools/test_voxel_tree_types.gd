extends SceneTree

const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Provider = preload("res://addons/ember_import/ember_voxel_large_tree_generator.gd")
const GenerationPanel = preload("res://addons/ember_import/ember_voxel_generation_panel.gd")
var failures := 0


func _init() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func wood(source: EmberVoxelModelResource) -> Dictionary:
	var result := {}
	var grid := source.grid_size()
	for index in source.voxels.size():
		if source.voxels[index] < 1 or source.voxels[index] > 3: continue
		var point := Vector3i(index % grid.x - grid.x / 2, index / (grid.x * grid.z), (index / grid.x) % grid.z - grid.z / 2)
		result[point] = source.voxels[index]
	return result


func _run() -> void:
	var base := Generator.default_recipe(Generator.LARGE_TREE)
	base.parameters.height = 64
	base.seed = 371
	check(base.parameters.generation_version == 2 and base.parameters.tree_type == 0, "existing default remains savanna v2")
	var classic := base.duplicate(true)
	classic.parameters = {"height": 64}
	check(Provider.normalize(classic.parameters).generation_version == 1, "missing old version remains classic")
	var hashes := {}
	# Captured from the pre-type provider on Godot 4.7.2, seed 371, defaults.
	var classic_hashes := [4077626769, 4029382303, 4050106091]
	var savanna_hashes := [107502460, 314000213, 4278328961]
	for index in 3:
		var settings := Provider.defaults()
		settings.height = [64, 128, 256][index]
		settings.generation_version = 1
		var legacy := Provider.build(settings, 371, Color.WHITE, {}, "Legacy parity")
		check(hash(legacy.geometry.voxels) == classic_hashes[index], "classic source remains byte-identical to pre-type provider")
	for kind in 4:
		for height in [64, 128, 256]:
			var recipe := base.duplicate(true)
			recipe.parameters.tree_type = kind
			recipe.parameters.height = height
			recipe.parameters = Generator.normalized_parameters(recipe.generator_id, recipe.parameters)
			var start := Time.get_ticks_usec()
			var built := Generator.build(recipe, Color.WHITE, {}, "Type", "type_fixture")
			print("Tree type %d / %d vox: %.2f ms" % [kind, height, (Time.get_ticks_usec() - start) / 1000.0])
			check(not built.has("error"), "type builds: %d / %d" % [kind, height])
			if built.has("error"): continue
			check(built.geometry.validation_errors().is_empty(), "canonical source validates")
			if kind == 0:
				check(hash(built.geometry.voxels) == savanna_hashes[[64, 128, 256].find(height)], "savanna source remains byte-identical to pre-type provider")
			check(built.structure.lines.size() <= 128 and built.structure.groups.size() <= 128, "bounded structural data")
			recipe.structure = built.structure.duplicate(true)
			var restored := Generator.build(recipe, Color.WHITE, {}, "Type", "type_fixture")
			check(not restored.has("error"), "frozen type restores")
			if restored.has("error"): continue
			check(restored.geometry.voxels == built.geometry.voxels and restored.geometry.palette == built.geometry.palette, "frozen structure restores exact full geometry")
			if height != 64: continue
			hashes[hash(built.geometry.voxels)] = true
			var rerun := Generator.build(recipe, Color.WHITE, {}, "Type", "type_fixture")
			check(rerun.geometry.voxels == restored.geometry.voxels, "same seed repeats exactly")
			if kind == 0: continue
			var expected := wood(built.geometry)
			var rounder := recipe.duplicate(true)
			rounder.parameters.cluster_flatten = 10
			var reshaped := Generator.build(rounder, Color.WHITE, {}, "Rounder")
			check(not reshaped.has("error") and reshaped.geometry.voxels != built.geometry.voxels, "new type foliage flatten control changes geometry")
			for amount in [0, 30, 100]:
				var edited := recipe.duplicate(true)
				edited.parameters.foliage_along = amount
				edited.parameters.foliage_color = Color("c67432")
				var next := Generator.build(edited, Color.WHITE, {}, "Season")
				check(not next.has("error"), "interior foliage edits build")
				if not next.has("error"):
					check(wood(next.geometry) == expected, "interior foliage and season preserve wood coordinates/colors")
					check(next.geometry.voxels != built.geometry.voxels or next.geometry.palette != built.geometry.palette, "foliage edit changes tree")
			var bare := recipe.duplicate(true)
			bare.structure = {}
			bare.parameters.foliage_along = 0
			var fresh_bare := Generator.build(bare, Color.WHITE, {}, "Bare interior")
			check(fresh_bare.structure.lines == built.structure.lines, "interior foliage does not consume different branch randomness")
	check(hashes.size() == 4, "four distinct silhouettes for same seed")
	for kind in [1, 2, 3]:
		var extreme := Provider.defaults()
		extreme.merge({"tree_type": kind, "height": 256, "trunk_width": 24, "crown_spread": 85, "cluster_size": 180, "canopy_cohesion": 100}, true)
		var boundary := Provider.build(extreme, 52, Color.WHITE, {}, "Extreme type")
		check(not boundary.has("error"), "type extreme respects storage envelope")
		if not boundary.has("error"): check(boundary.geometry.validation_errors().is_empty(), "extreme type validates")
	var oak := base.duplicate(true)
	oak.parameters.tree_type = 1
	var upward := oak.duplicate(true)
	upward.parameters.branch_direction = 1
	var lateral := oak.duplicate(true)
	lateral.parameters.branch_direction = 2
	var down := oak.duplicate(true)
	down.parameters.branch_direction = 3
	var up_tree := Generator.build(upward, Color.WHITE, {}, "Up")
	var side_tree := Generator.build(lateral, Color.WHITE, {}, "Side")
	var down_tree := Generator.build(down, Color.WHITE, {}, "Down")
	check(not up_tree.has("error") and not side_tree.has("error") and not down_tree.has("error"), "all branch directions build")
	if not up_tree.has("error") and not side_tree.has("error") and not down_tree.has("error"):
		check(up_tree.structure.lines != side_tree.structure.lines and side_tree.structure.lines != down_tree.structure.lines, "direction changes actual support lines")
	var directory := "user://tree_type_fixture_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var frozen := Generator.freeze_structure(oak)
	check(not frozen.has("error"), "new tree type supports generator editor")
	if not frozen.has("error"):
		check(ResourceSaver.save(frozen.recipe, directory.path_join("oak.tres")) == OK, "typed recipe saves")
		var reopened := ResourceLoader.load(directory.path_join("oak.tres"), "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
		check(reopened.parameters.tree_type == 1 and reopened.structure.lines.size() == frozen.recipe.structure.lines.size(), "type/parameters/skeleton survive reopen")
		var before_save := Generator.build(frozen.recipe, Color.WHITE, {}, "Saved")
		var after_save := Generator.build(reopened, Color.WHITE, {}, "Saved")
		check(not after_save.has("error") and after_save.geometry.voxels == before_save.geometry.voxels, "recipe text roundtrip restores exact voxels")
	var panel := GenerationPanel.new()
	root.add_child(panel)
	await process_frame
	panel._change_parameter("tree_type", 1)
	check(panel.recipe.parameters.tree_type == 1 and panel.recipe.parameters.generation_version == 8, "shared creation UI selects latest oak")
	panel.undo_local()
	check(panel.recipe.parameters.tree_type == 0 and panel.recipe.parameters.generation_version == 2, "type choice Undo restores exact savanna version")
	panel.redo_local()
	check(panel.recipe.parameters.tree_type == 1, "oak type choice Redo")
	panel.undo_local()
	panel.controls.tree_type.select(2)
	panel.controls.tree_type.item_selected.emit(2)
	check(panel.recipe.parameters.tree_type == 2 and panel.recipe.parameters.generation_version == 5, "shared creation UI selects latest birch")
	panel.undo_local()
	check(panel.recipe.parameters.tree_type == 0 and panel.recipe.parameters.generation_version == 2, "birch choice Undo restores saved algorithm")
	panel.redo_local()
	check(panel.recipe.parameters.tree_type == 2 and panel.recipe.parameters.generation_version == 5, "birch type choice Redo")
	check(panel.controls.foliage_along.get_parent().visible, "interior foliage control visible for new types")
	panel._syncing = true
	panel.active_id = ""
	panel.candidate_recipe = frozen.recipe.duplicate(true)
	panel._sync_candidate_controls()
	check(panel.candidate_controls.has("foliage_along"), "workshop rebuilds candidate descriptors when type changes")
	panel.candidate_recipe = base.duplicate(true)
	panel._sync_candidate_controls()
	check(not panel.candidate_controls.has("foliage_along"), "savanna candidate fields do not retain unsupported interior setting")
	panel.free()
	print("Voxel tree types: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
