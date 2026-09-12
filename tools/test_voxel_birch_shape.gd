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
	var birch: Resource = Generator.creation_presets(Generator.LARGE_TREE)[2].recipe.duplicate(true)
	check(birch.parameters.generation_version == 5, "new birch preset selects revision 5")
	var directory := "user://birch_shape_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for height in [64, 96, 128, 256]:
		for seed in [17, 371, 391]:
			var recipe := birch.duplicate(true)
			recipe.parameters.height = height
			recipe.seed = seed
			var start := Time.get_ticks_usec()
			var built := Generator.build(recipe, Color.WHITE, {}, "Birch")
			print("Birch %d / seed %d: %.2f ms" % [height, seed, (Time.get_ticks_usec() - start) / 1000.0])
			check(not built.has("error"), "birch builds inside envelope")
			if built.has("error"): continue
			check(built.geometry.validation_errors().is_empty(), "birch source validates")
			check(built.structure.lines.size() <= 128 and built.structure.groups.size() <= 128, "bounded birch structure")
			var trunk_top := 0.0
			var hanging := 0
			for line in built.structure.lines:
				if not line.branch: trunk_top = maxf(trunk_top, line.finish.y)
				if line.branch and line.finish.y < line.start.y: hanging += 1
			check(trunk_top >= height * 0.95, "continuous slender leader reaches top")
			check(hanging >= 12, "many hanging outer twigs, not flat branches")
			recipe.structure = built.structure.duplicate(true)
			var frozen := Generator.build(recipe, Color.WHITE, {}, "Frozen")
			check(not frozen.has("error") and frozen.geometry.voxels == built.geometry.voxels and frozen.geometry.collision_voxels == built.geometry.collision_voxels, "exact fresh/frozen geometry and collision")
			var path := directory.path_join("birch_%d_%d.tres" % [height, seed])
			check(ResourceSaver.save(recipe, path) == OK, "birch Recipe saves")
			var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
			var restored := Generator.build(reopened, Color.WHITE, {}, "Reopened")
			check(not restored.has("error") and restored.geometry.voxels == built.geometry.voxels, "exact text Recipe roundtrip")
			var bare := recipe.duplicate(true)
			bare.parameters.foliage_amount = 0
			var skeleton := Generator.build(bare, Color.WHITE, {}, "Bare")
			check(not skeleton.has("error") and skeleton.structure.lines == built.structure.lines, "bare preserves skeleton")
			var edited := recipe.duplicate(true)
			edited.parameters.merge({"foliage_color": Color("c67432"), "foliage_along": 30, "branch_thickness": 65}, true)
			var autumn := Generator.build(edited, Color.WHITE, {}, "Autumn")
			check(not autumn.has("error") and autumn.structure.lines == built.structure.lines, "season and branch thickness retain support positions")
	var extreme := birch.duplicate(true)
	extreme.parameters.merge({"height": 256, "trunk_width": 24, "branchiness": 100, "cluster_size": 180, "canopy_cohesion": 100, "crown_spread": 85}, true)
	check(not Generator.build(extreme, Color.WHITE, {}, "Extreme").has("error"), "maximal birch respects storage envelope")
	for direction in [1, 2, 3]:
		var directed := birch.duplicate(true)
		directed.parameters.branch_direction = direction
		var shaped := Generator.build(directed, Color.WHITE, {}, "Direction")
		check(not shaped.has("error"), "birch supports explicit branch direction")
	var tiered := birch.duplicate(true)
	tiered.parameters.crown_shape = 2
	check(not Generator.build(tiered, Color.WHITE, {}, "Tiered").has("error"), "optional tiered crown remains available")
	var damaged: Resource = Generator.freeze_structure(birch).recipe
	damaged.structure.noise_radius = NAN
	check(not Generator.validation_errors(damaged).is_empty(), "invalid volume noise profile rejected")
	var panel := GenerationPanel.new()
	var scene := Node3D.new()
	var undo := UndoRedo.new()
	root.add_child(panel)
	root.add_child(scene)
	await process_frame
	panel.session.source_directory = directory.path_join("sources")
	panel.session.prefab_directory = directory.path_join("prefabs")
	panel.session.recipe_directory = directory.path_join("recipes")
	panel.open_for({"root": scene, "undo": undo, "world_size": 1.0}, birch)
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
	check(candidate.creation.source.voxels == voxels, "birch Apply Undo exact")
	panel.redo_local()
	check(candidate.creation.recipe.parameters.foliage_amount == 0, "birch Apply Redo")
	panel.undo_local()
	panel._choose(candidate, true)
	panel.save_chosen()
	await settle(panel)
	check(candidate.saved, "birch publishes through existing library")
	undo.undo()
	check(not candidate.saved, "birch publication Undo")
	undo.redo()
	check(candidate.saved, "birch publication Redo")
	var saved := Creation.load_recipe(candidate.creation.source.model_id, panel.session.recipe_directory)
	check(saved != null and saved.parameters.generation_version == 5, "published birch recipe reopens")
	panel.close_session()
	panel.free()
	scene.free()
	undo.clear_history()
	undo.free()
	print("Voxel birch shape: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)

func settle(panel: Node) -> void:
	for frame in 400:
		await process_frame
		if not panel._busy() and not panel._step_queued: return
	check(false, "birch workshop queue did not settle")
