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
	var presets := Generator.creation_presets(Generator.LARGE_TREE)
	var oak: Resource = presets[1].recipe.duplicate(true)
	check(oak.parameters.generation_version == 17, "new oak preset opts into lateral mature revision")
	oak.parameters.generation_version = 8 # Preserve historical v8 geometry gates.
	check(Provider.normalize({"generation_version": 4, "tree_type": 1}).generation_version == 4, "saved v4 stays on original algorithm")
	var directory := "user://oak_crown_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var old_hashes := [925592257, 1240605481, 3443821226]
	var new_hashes := [2164683239, 789578374, 3144645852]
	for index in 3:
		var old := Provider.defaults()
		old.tree_type = 1
		old.generation_version = 3
		old.height = [64, 128, 256][index]
		var legacy := Provider.build(old, 371, Color.WHITE, {}, "Old oak")
		check(not legacy.has("error") and hash(legacy.geometry.voxels) == old_hashes[index], "saved v3 oak remains byte-identical")
		old.generation_version = 4
		var current := Provider.build(old, 371, Color.WHITE, {}, "Current oak")
		check(not current.has("error") and hash(current.geometry.voxels) == new_hashes[index], "oak fast union preserves exact crown geometry")
	for height in [64, 96, 128, 256]:
		for seed in [17, 371, 391]:
			var recipe := oak.duplicate(true)
			recipe.parameters.height = height
			recipe.seed = seed
			var start := Time.get_ticks_usec()
			var built := Generator.build(recipe, Color.WHITE, {}, "Oak")
			print("Oak crown %d vox / seed %d: %.2f ms" % [height, seed, (Time.get_ticks_usec() - start) / 1000.0])
			check(not built.has("error"), "new oak builds within envelope")
			if built.has("error"): continue
			check(built.geometry.validation_errors().is_empty(), "new oak validates")
			check(built.structure.lines.size() <= 128 and built.structure.groups.size() <= 128, "bounded crown structure")
			var trunk_lines := 0
			for line in built.structure.lines:
				if not line.branch and line.finish.y > height * 0.65: trunk_lines += 1
			check(trunk_lines == 0, "no tall central trunk or top pole")
			var forks := 0
			for line in built.structure.lines:
				if line.branch and line.t0 == 0.0: forks += 1
			check(forks >= 3, "multiple strong early boughs")
			var origins := {}
			var low_reach := 0.0
			var high_reach := 0.0
			for line in built.structure.lines:
				if line.branch and line.t0 == 0.0: origins[line.start.y] = true
				if line.branch and line.t0 == 0.72:
					var reach := Vector2(line.finish.x, line.finish.z).length()
					if line.finish.y < height * 0.60: low_reach = maxf(low_reach, reach)
					if line.finish.y > height * 0.75: high_reach = maxf(high_reach, reach)
			check(origins.size() >= 5, "scaffold limbs originate at different heights")
			check(low_reach > high_reach, "lower oak limbs spread more than upper ones")
			check(built.structure.lines[0].r0 > built.structure.lines[0].r1 * 1.30, "continuous thick flared collar")
			var lowest: int = height
			var highest := 0
			var grid: Vector3i = built.geometry.grid_size()
			for cell in built.geometry.voxels.size():
				if built.geometry.voxels[cell] < 4 or built.geometry.voxels[cell] > 6: continue
				var row: int = cell / (grid.x * grid.z)
				lowest = mini(lowest, row)
				highest = maxi(highest, row)
			check(highest - lowest >= height * 0.50, "real foliage spans a deep crown, not a flat cap")
			recipe.structure = built.structure.duplicate(true)
			var restored := Generator.build(recipe, Color.WHITE, {}, "Restored")
			check(not restored.has("error") and restored.geometry.voxels == built.geometry.voxels and restored.geometry.collision_voxels == built.geometry.collision_voxels, "frozen oak matches fresh exactly including collision")
			var path := directory.path_join("oak_%d_%d.tres" % [height, seed])
			check(ResourceSaver.save(recipe, path) == OK, "oak recipe saves")
			var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
			var roundtrip := Generator.build(reopened, Color.WHITE, {}, "Reopen")
			check(not roundtrip.has("error") and roundtrip.geometry.voxels == built.geometry.voxels, "oak Recipe text roundtrip preserves exact voxels")
			var bare := recipe.duplicate(true)
			bare.parameters.foliage_amount = 0
			var skeleton := Generator.build(bare, Color.WHITE, {}, "Bare")
			check(not skeleton.has("error") and skeleton.structure.lines == built.structure.lines, "bare view preserves same skeleton")
			var season := recipe.duplicate(true)
			season.parameters.foliage_color = Color("c67432")
			season.parameters.foliage_along = 30
			var autumn := Generator.build(season, Color.WHITE, {}, "Autumn")
			check(not autumn.has("error") and autumn.structure.lines == built.structure.lines, "season and crown filling preserve support lines")
			var thick := recipe.duplicate(true)
			thick.parameters.branch_thickness = 100
			var thickened := Generator.build(thick, Color.WHITE, {}, "Thick")
			check(not thickened.has("error") and thickened.structure.lines == built.structure.lines, "thickness preserves frozen skeleton")
	var extreme := oak.duplicate(true)
	extreme.parameters.merge({"height": 256, "trunk_width": 24, "branch_thickness": 100, "branchiness": 100, "cluster_size": 180, "canopy_cohesion": 100, "crown_spread": 85}, true)
	check(not Generator.build(extreme, Color.WHITE, {}, "Extreme").has("error"), "maximal oak stays within storage budget")
	for direction in [1, 2, 3]:
		var directed := oak.duplicate(true)
		directed.parameters.branch_direction = direction
		check(not Generator.build(directed, Color.WHITE, {}, "Direction").has("error"), "explicit branch directions remain available")
	var tiered := oak.duplicate(true)
	tiered.parameters.crown_shape = 2
	check(not Generator.build(tiered, Color.WHITE, {}, "Tiered").has("error"), "tiered crown remains available")
	var invalid: Resource = Generator.freeze_structure(oak).recipe
	invalid.structure.groups[0].radii = Vector3(NAN, 1, 1)
	check(not Generator.validation_errors(invalid).is_empty(), "invalid new crown volume rejected")
	var panel := GenerationPanel.new()
	var scene := Node3D.new()
	var undo := UndoRedo.new()
	root.add_child(panel)
	root.add_child(scene)
	await process_frame
	panel.session.source_directory = directory.path_join("sources")
	panel.session.prefab_directory = directory.path_join("prefabs")
	panel.session.recipe_directory = directory.path_join("recipes")
	panel.open_for({"root": scene, "undo": undo, "world_size": 1.0}, oak)
	panel.controls.tree_type.select(0)
	panel.controls.tree_type.item_selected.emit(0)
	panel.controls.tree_type.select(1)
	panel.controls.tree_type.item_selected.emit(1)
	check(panel.recipe.parameters.generation_version == 17, "native oak type choice routes to latest revision")
	panel.undo_local()
	check(panel.recipe.parameters.tree_type == 0, "type choice Undo")
	panel.redo_local()
	check(panel.recipe.parameters.generation_version == 17, "type choice Redo")
	panel.controls.height.value = 64
	panel._count.value = 1
	panel.generate()
	await settle(panel)
	var candidate: Dictionary = panel.session.candidates[0]
	panel._select_preview(candidate)
	var exact: PackedByteArray = candidate.creation.source.voxels.duplicate()
	panel.candidate_controls.foliage_amount.value = 20
	panel.discard_candidate()
	check(candidate.creation.source.voxels == exact, "candidate draft discard does not alter geometry")
	panel.candidate_controls.foliage_amount.value = 0
	panel.apply_candidate()
	check(candidate.creation.source.palette.size() >= 7 and candidate.creation.recipe.parameters.foliage_amount == 0, "workshop bare Apply")
	panel.undo_local()
	check(candidate.creation.source.voxels == exact, "workshop oak Apply Undo exact")
	panel.redo_local()
	check(candidate.creation.recipe.parameters.foliage_amount == 0, "workshop oak Apply Redo")
	panel.undo_local()
	panel._choose(candidate, true)
	panel.save_chosen()
	await settle(panel)
	check(candidate.saved, "new oak publishes through existing library owner")
	undo.undo()
	check(not candidate.saved, "oak publication Undo")
	undo.redo()
	check(candidate.saved, "oak publication Redo")
	var reopened := Creation.load_recipe(candidate.creation.source.model_id, panel.session.recipe_directory)
	check(reopened != null and reopened.parameters.generation_version == 17, "publication reopens lateral oak recipe")
	panel.close_session()
	panel.free()
	scene.free()
	undo.clear_history()
	undo.free()
	print("Voxel oak crown: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)

func settle(panel: Node) -> void:
	for frame in 400:
		await process_frame
		if not panel._busy() and not panel._step_queued: return
	check(false, "workshop queue did not settle")
