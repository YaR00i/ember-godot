extends SceneTree

const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Provider = preload("res://addons/ember_import/ember_voxel_large_tree_generator.gd")
const GenerationPanel = preload("res://addons/ember_import/ember_voxel_generation_panel.gd")
const Creation = preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
var failures := 0

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	for index in 3:
		var old := Provider.defaults()
		old.merge({"generation_version": 6, "tree_type": 3, "height": [64, 128, 256][index]}, true)
		var built := Provider.build(old, 371, Color.WHITE, {}, "Old maple")
		check(not built.has("error") and hash(built.geometry.voxels) == [3008355434, 2969065940, 970442213][index], "saved v6 maple remains byte-identical")
	var maple: Resource = Generator.creation_presets(Generator.LARGE_TREE)[3].recipe.duplicate(true)
	check(maple.parameters.generation_version == 7, "new maple preset selects revision 7")
	check(Provider.normalize({"tree_type": 3, "generation_version": 3}).generation_version == 3, "saved maple stays v3")
	var directory := "user://maple_shape_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for height in [64, 96, 128, 256]:
		for seed in [17, 371, 391]:
			var recipe := maple.duplicate(true)
			recipe.parameters.height = height
			recipe.seed = seed
			var start := Time.get_ticks_usec()
			var built := Generator.build(recipe, Color.WHITE, {}, "Maple")
			print("Maple %d / seed %d: %.2f ms" % [height, seed, (Time.get_ticks_usec() - start) / 1000.0])
			check(not built.has("error"), "maple builds inside envelope")
			if built.has("error"): continue
			check(built.geometry.validation_errors().is_empty() and Provider.structure_errors(built.structure).is_empty(), "source and skeleton validate")
			var forks := 0
			var sideways := 0
			for line in built.structure.lines:
				if not line.branch: continue
				if line.finish.y > line.start.y + 0.5: forks += 1
				if Vector2(line.finish.x - line.start.x, line.finish.z - line.start.z).length() > 2.0: sideways += 1
			check(forks >= 12 and sideways >= 12, "ascending forks spread sideways, not stacked on a pole")
			check(built.structure.groups.size() >= 60, "crown volumes dress several heights and canopy interior")
			var levels := {}
			var middle_reach := 0.0
			var upper_reach := 0.0
			for line in built.structure.lines:
				if not line.branch or line.t0 != 0.0: continue
				levels[roundi(line.start.y / (height * 0.05))] = true
				var reach := Vector2(line.finish.x - line.start.x, line.finish.z - line.start.z).length()
				if line.start.y > height * 0.45 and line.start.y < height * 0.65: middle_reach = maxf(middle_reach, reach)
				if line.start.y > height * 0.80: upper_reach = maxf(upper_reach, reach)
			check(levels.size() >= 5 and middle_reach > upper_reach * 1.5, "five branch heights, broad middle and narrowing top")
			var leaf_rows := {}
			var lowest: int = height
			var highest := 0
			var plane: int = built.grid.x * built.grid.z
			for cell in built.geometry.voxels.size():
				if built.geometry.voxels[cell] < 4 or built.geometry.voxels[cell] > 6: continue
				var row: int = cell / plane
				leaf_rows[row] = true
				lowest = mini(lowest, row)
				highest = maxi(highest, row)
			check(highest - lowest >= height * 0.65, "canopy spans most of the height, not a shallow cup")
			for row in range(lowest, highest + 1):
				check(leaf_rows.has(row), "canopy has no empty horizontal gaps between levels")
			recipe.structure = built.structure.duplicate(true)
			var frozen := Generator.build(recipe, Color.WHITE, {}, "Frozen")
			check(not frozen.has("error") and frozen.geometry.voxels == built.geometry.voxels and frozen.geometry.collision_voxels == built.geometry.collision_voxels, "exact fresh/frozen geometry and collision")
			var path := directory.path_join("maple_%d_%d.tres" % [height, seed])
			check(ResourceSaver.save(recipe, path) == OK, "maple Recipe saves")
			var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
			var restored := Generator.build(reopened, Color.WHITE, {}, "Reopened")
			check(not restored.has("error") and restored.geometry.voxels == built.geometry.voxels, "exact text Recipe roundtrip")
			var bare := recipe.duplicate(true)
			bare.parameters.foliage_amount = 0
			var skeleton := Generator.build(bare, Color.WHITE, {}, "Bare")
			check(not skeleton.has("error") and skeleton.structure.lines == built.structure.lines, "bare preserves skeleton")
			var edited := recipe.duplicate(true)
			edited.parameters.merge({"foliage_color": Color("c67432"), "foliage_along": 30, "branch_thickness": 85}, true)
			var autumn := Generator.build(edited, Color.WHITE, {}, "Autumn")
			check(not autumn.has("error") and autumn.structure.lines == built.structure.lines, "season and thickness retain support positions")
	var extreme := maple.duplicate(true)
	extreme.parameters.merge({"height": 256, "trunk_width": 24, "branchiness": 100, "cluster_size": 180, "canopy_cohesion": 100, "crown_spread": 85}, true)
	var maximal := Generator.build(extreme, Color.WHITE, {}, "Extreme")
	check(not maximal.has("error"), "maximal maple respects storage envelope: %s" % maximal.get("error", ""))
	for direction in [1, 2, 3]:
		var directed := maple.duplicate(true)
		directed.parameters.branch_direction = direction
		check(not Generator.build(directed, Color.WHITE, {}, "Direction").has("error"), "explicit branch directions remain available")
	var tiered := maple.duplicate(true)
	tiered.parameters.crown_shape = 2
	check(not Generator.build(tiered, Color.WHITE, {}, "Tiered").has("error"), "optional tiered silhouette remains available")
	var panel := GenerationPanel.new()
	var scene := Node3D.new()
	var undo := UndoRedo.new()
	root.add_child(panel)
	root.add_child(scene)
	await process_frame
	panel.controls.tree_type.select(3)
	panel.controls.tree_type.item_selected.emit(3)
	check(panel.recipe.parameters.generation_version == 7, "native type choice selects latest maple")
	panel.undo_local()
	check(panel.recipe.parameters.tree_type == 0 and panel.recipe.parameters.generation_version == 2, "type choice Undo restores old version")
	panel.redo_local()
	check(panel.recipe.parameters.tree_type == 3 and panel.recipe.parameters.generation_version == 7, "type choice Redo restores maple")
	panel.session.source_directory = directory.path_join("sources")
	panel.session.prefab_directory = directory.path_join("prefabs")
	panel.session.recipe_directory = directory.path_join("recipes")
	panel.open_for({"root": scene, "undo": undo, "world_size": 1.0}, maple)
	panel.controls.height.value = 64
	panel._count.value = 1
	panel.generate()
	await settle(panel)
	var candidate: Dictionary = panel.session.candidates[0]
	panel._select_preview(candidate)
	var voxels: PackedByteArray = candidate.creation.source.voxels.duplicate()
	panel.candidate_controls.foliage_amount.value = 0
	panel.discard_candidate()
	check(candidate.creation.source.voxels == voxels, "draft discard leaves source untouched")
	panel.candidate_controls.foliage_amount.value = 0
	panel.apply_candidate()
	panel.undo_local()
	check(candidate.creation.source.voxels == voxels, "maple Apply Undo exact")
	panel.redo_local()
	check(candidate.creation.recipe.parameters.foliage_amount == 0, "maple Apply Redo")
	panel.undo_local()
	panel._choose(candidate, true)
	panel.save_chosen()
	await settle(panel)
	check(candidate.saved, "maple publishes through existing library")
	undo.undo()
	check(not candidate.saved, "maple publication Undo")
	undo.redo()
	check(candidate.saved, "maple publication Redo")
	var saved := Creation.load_recipe(candidate.creation.source.model_id, panel.session.recipe_directory)
	check(saved != null and saved.parameters.generation_version == 7, "published maple recipe reopens")
	panel.close_session()
	panel.free()
	scene.free()
	undo.clear_history()
	undo.free()
	print("Voxel maple shape: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)

func settle(panel: Node) -> void:
	for frame in 400:
		await process_frame
		if not panel._busy() and not panel._step_queued: return
	check(false, "maple workshop queue did not settle")
