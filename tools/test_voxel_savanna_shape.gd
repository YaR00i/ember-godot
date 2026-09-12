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
	var savanna: Resource = Generator.creation_presets(Generator.LARGE_TREE)[0].recipe
	check(savanna.parameters.generation_version == 14, "new savanna preset selects varied umbrella")
	savanna.parameters.generation_version = 9
	check(Generator.editing_fields(savanna).any(func(field): return field.key == "foliage_along"), "new savanna exposes shared interior foliage editing")
	check(Provider.normalize({"tree_type": 0, "generation_version": 2}).generation_version == 2, "saved savanna retains v2")
	var directory := "user://savanna_shape_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var old_hashes := [107502460, 314000213, 4278328961]
	for index in 3:
		var old := Provider.defaults()
		old.height = [64, 128, 256][index]
		var legacy := Provider.build(old, 371, Color.WHITE, {}, "Legacy")
		check(not legacy.has("error") and hash(legacy.geometry.voxels) == old_hashes[index], "saved v2 geometry remains byte-identical")
	for height in [64, 96, 128, 256]:
		for seed in [17, 371, 391]:
			var recipe := savanna.duplicate(true)
			recipe.parameters.height = height
			recipe.seed = seed
			var start := Time.get_ticks_usec()
			var built := Generator.build(recipe, Color.WHITE, {}, "Savanna")
			print("Savanna %d / seed %d: %.2f ms" % [height, seed, (Time.get_ticks_usec() - start) / 1000.0])
			check(not built.has("error"), "umbrella builds inside envelope")
			if built.has("error"): continue
			check(built.geometry.validation_errors().is_empty(), "source validates")
			check(built.structure.lines.size() <= 128 and built.structure.groups.size() <= 128, "bounded scaffold")
			var forks := 0
			for line in built.structure.lines:
				if not line.branch: check(line.finish.y < height * 0.60, "no central top pole")
				if line.branch and line.t0 == 0: forks += 1
			check(forks >= 3, "multiple main stems fan outward")
			var lowest: int = height
			var highest := 0
			var width := Vector2i(1 << 29, -(1 << 29))
			var grid: Vector3i = built.geometry.grid_size()
			for cell in built.geometry.voxels.size():
				if built.geometry.voxels[cell] < 4 or built.geometry.voxels[cell] > 6: continue
				var row: int = cell / (grid.x * grid.z)
				lowest = mini(lowest, row)
				highest = maxi(highest, row)
				width.x = mini(width.x, cell % grid.x)
				width.y = maxi(width.y, cell % grid.x)
			check(lowest > height * 0.65 and highest - lowest < height * 0.30, "shallow canopy sits above visible scaffold")
			check(width.y - width.x > (highest - lowest) * 2.5, "umbrella much wider than deep")
			recipe.structure = built.structure.duplicate(true)
			var frozen := Generator.build(recipe, Color.WHITE, {}, "Frozen")
			check(not frozen.has("error") and frozen.geometry.voxels == built.geometry.voxels and frozen.geometry.collision_voxels == built.geometry.collision_voxels, "fresh/frozen exact including collision")
			var path := directory.path_join("savanna_%d_%d.tres" % [height, seed])
			check(ResourceSaver.save(recipe, path) == OK, "recipe saves")
			var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
			var restored := Generator.build(reopened, Color.WHITE, {}, "Reopened")
			check(not restored.has("error") and restored.geometry.voxels == built.geometry.voxels, "text roundtrip exact")
			var edited := recipe.duplicate(true)
			edited.parameters.merge({"foliage_amount": 0, "branch_thickness": 100, "foliage_color": Color("c67432")}, true)
			var bare := Generator.build(edited, Color.WHITE, {}, "Bare")
			check(not bare.has("error") and bare.structure.lines == built.structure.lines, "bare/season/thickness retain support points")
	var extreme := savanna.duplicate(true)
	extreme.parameters.merge({"height": 256, "trunk_width": 24, "crown_spread": 85, "branchiness": 100, "branch_thickness": 100, "cluster_size": 180, "canopy_cohesion": 100}, true)
	check(not Generator.build(extreme, Color.WHITE, {}, "Extreme").has("error"), "maximal settings bounded")
	for direction in [1, 2, 3]:
		var directed := savanna.duplicate(true)
		directed.parameters.branch_direction = direction
		check(not Generator.build(directed, Color.WHITE, {}, "Directed").has("error"), "directions remain available")
	var panel := GenerationPanel.new()
	var scene := Node3D.new()
	var undo := UndoRedo.new()
	root.add_child(panel)
	root.add_child(scene)
	await process_frame
	check(panel.recipe.parameters.generation_version == 2, "opening default does not silently upgrade")
	panel.controls.tree_type.item_selected.emit(0)
	check(panel.recipe.parameters.generation_version == 14, "explicit reselect of savanna upgrades old default")
	panel.undo_local()
	check(panel.recipe.parameters.generation_version == 2, "same-type upgrade Undo restores saved revision")
	panel.redo_local()
	panel._change_parameter("tree_type", 1)
	panel._change_parameter("tree_type", 0)
	check(panel.recipe.parameters.generation_version == 14, "type choice selects latest savanna")
	panel.undo_local()
	check(panel.recipe.parameters.tree_type == 1, "type choice Undo")
	panel.redo_local()
	check(panel.recipe.parameters.generation_version == 14, "type choice Redo")
	panel.session.source_directory = directory.path_join("sources")
	panel.session.prefab_directory = directory.path_join("prefabs")
	panel.session.recipe_directory = directory.path_join("recipes")
	panel.open_for({"root": scene, "undo": undo, "world_size": 1.0}, savanna)
	panel.controls.height.value = 64
	panel._count.value = 1
	panel.generate()
	await settle(panel)
	var candidate: Dictionary = panel.session.candidates[0]
	panel._select_preview(candidate)
	var exact: PackedByteArray = candidate.creation.source.voxels.duplicate()
	panel.candidate_controls.foliage_amount.value = 0
	panel.discard_candidate()
	check(candidate.creation.source.voxels == exact, "discard unchanged")
	panel.candidate_controls.foliage_amount.value = 0
	panel.apply_candidate()
	panel.undo_local()
	check(candidate.creation.source.voxels == exact, "Apply Undo exact")
	panel.redo_local()
	check(candidate.creation.recipe.parameters.foliage_amount == 0, "Apply Redo")
	panel.undo_local()
	panel._choose(candidate, true)
	panel.save_chosen()
	await settle(panel)
	check(candidate.saved, "publication")
	undo.undo()
	check(not candidate.saved, "publication Undo")
	undo.redo()
	check(candidate.saved, "publication Redo")
	var stored := Creation.load_recipe(candidate.creation.source.model_id, panel.session.recipe_directory)
	check(stored != null and stored.parameters.generation_version == 9, "saved recipe reopens with v9")
	panel.close_session()
	panel.free()
	scene.free()
	undo.clear_history()
	undo.free()
	print("Voxel savanna shape: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)

func settle(panel: Node) -> void:
	for frame in 400:
		await process_frame
		if not panel._busy() and not panel._step_queued: return
	check(false, "queue failed to settle")
