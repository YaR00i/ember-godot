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
	var spruce: Resource = Generator.creation_presets(Generator.LARGE_TREE)[4].recipe
	check(spruce.parameters.tree_type == 4 and spruce.parameters.generation_version == 15, "spruce varied preset and type")
	spruce.parameters.generation_version = 10
	var directory := "user://spruce_shape_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for height in [64, 96, 128, 256]:
		for seed in [17, 371, 391]:
			var recipe := spruce.duplicate(true)
			recipe.parameters.height = height
			recipe.seed = seed
			var start := Time.get_ticks_usec()
			var built := Generator.build(recipe, Color.WHITE, {}, "Spruce")
			print("Spruce %d / seed %d: %.2f ms" % [height, seed, (Time.get_ticks_usec() - start) / 1000.0])
			check(not built.has("error"), "spruce builds inside envelope")
			if built.has("error"): continue
			check(built.geometry.validation_errors().is_empty(), "source validates")
			check(Provider.structure_errors(built.structure).is_empty(), "bounded frozen scaffold validates")
			var tiers := {}
			var lower := 0.0
			var upper := 0.0
			var leader := 0.0
			for line in built.structure.lines:
				if not line.branch: leader = maxf(leader, line.finish.y)
				if not line.branch or line.t0 != 0.0: continue
				tiers[roundi(line.start.y / (height * 0.04))] = true
				var reach := Vector2(line.finish.x - line.start.x, line.finish.z - line.start.z).length()
				if line.start.y < height * 0.35: lower = maxf(lower, reach)
				if line.start.y > height * 0.85: upper = maxf(upper, reach)
			check(leader > height * 0.95, "continuous leader reaches pointed top")
			check(tiers.size() >= 7 and lower > upper * 4.0, "several tiers taper strongly toward top")
			var lowest: int = height
			var highest := 0
			var leafy_rows := {}
			var grid: Vector3i = built.geometry.grid_size()
			for cell in built.geometry.voxels.size():
				if built.geometry.voxels[cell] < 4 or built.geometry.voxels[cell] > 6: continue
				var row: int = cell / (grid.x * grid.z)
				leafy_rows[row] = true
				lowest = mini(lowest, row)
				highest = maxi(highest, row)
			check(lowest < height * 0.30 and highest > height * 0.95, "foliage follows most of the trunk height")
			var covered := 0
			var first_row := roundi(height * 0.25)
			var last_row := roundi(height * 0.95)
			for row in range(first_row, last_row):
				if leafy_rows.has(row): covered += 1
			check(covered >= (last_row - first_row) * 0.90, "inner foliage bridges tiers instead of bare pole with plates")
			recipe.structure = built.structure.duplicate(true)
			var frozen := Generator.build(recipe, Color.WHITE, {}, "Frozen")
			check(not frozen.has("error") and frozen.geometry.voxels == built.geometry.voxels and frozen.geometry.collision_voxels == built.geometry.collision_voxels, "fresh/frozen exact including collision")
			var path := directory.path_join("spruce_%d_%d.tres" % [height, seed])
			check(ResourceSaver.save(recipe, path) == OK, "recipe saves")
			var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
			var restored := Generator.build(reopened, Color.WHITE, {}, "Reopened")
			check(not restored.has("error") and restored.geometry.voxels == built.geometry.voxels, "text roundtrip exact")
			var edited := recipe.duplicate(true)
			edited.parameters.merge({"foliage_amount": 0, "branch_thickness": 100, "foliage_color": Color("728d9c")}, true)
			var bare := Generator.build(edited, Color.WHITE, {}, "Bare")
			check(not bare.has("error") and bare.structure.lines == built.structure.lines, "bare/color/thickness preserve support points")
	var extreme := spruce.duplicate(true)
	extreme.parameters.merge({"height": 256, "trunk_width": 24, "crown_spread": 85, "branchiness": 100, "branch_thickness": 100, "cluster_size": 180, "canopy_cohesion": 100}, true)
	var maximal := Generator.build(extreme, Color.WHITE, {}, "Extreme")
	check(not maximal.has("error") and Provider.structure_errors(maximal.structure).is_empty(), "maximal settings bounded")
	for direction in [1, 2, 3]:
		var directed := spruce.duplicate(true)
		directed.parameters.branch_direction = direction
		check(not Generator.build(directed, Color.WHITE, {}, "Directed").has("error"), "directions remain available")
	var panel := GenerationPanel.new()
	var scene := Node3D.new()
	var undo := UndoRedo.new()
	root.add_child(panel)
	root.add_child(scene)
	await process_frame
	panel.open_for({"root": scene, "undo": undo, "world_size": 1.0})
	check(panel.recipe.parameters.generation_version == 14, "fresh workshop starts with current savanna")
	check(panel.controls.tree_type.item_count == 5, "five types visible together")
	for kind in 5:
		panel.controls.tree_type.item_selected.emit(kind)
		check(panel.recipe.parameters.generation_version == Provider.LATEST_VERSIONS[kind], "direct type selection uses latest profile")
	panel.undo_local()
	check(panel.recipe.parameters.tree_type == 3, "type choice Undo")
	panel.redo_local()
	check(panel.recipe.parameters.generation_version == 15, "type choice Redo")
	var old := Generator.default_recipe(Generator.LARGE_TREE)
	panel.open_for({"root": scene, "undo": undo, "world_size": 1.0}, old)
	check(panel.recipe.parameters.generation_version == 2 and panel.controls.tree_type.get_item_text(0).contains("прежняя"), "saved old algorithm remains and is marked")
	panel.controls.tree_type.item_selected.emit(0)
	check(panel.recipe.parameters.generation_version == 14 and not panel.controls.tree_type.get_item_text(0).contains("прежняя"), "explicit reselect upgrades visible type")
	panel.session.source_directory = directory.path_join("sources")
	panel.session.prefab_directory = directory.path_join("prefabs")
	panel.session.recipe_directory = directory.path_join("recipes")
	panel.open_for({"root": scene, "undo": undo, "world_size": 1.0}, spruce)
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
	check(stored != null and stored.parameters.generation_version == 10, "saved recipe reopens with spruce")
	panel.close_session()
	panel.free()
	scene.free()
	undo.clear_history()
	undo.free()
	print("Voxel spruce shape: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)

func settle(panel: Node) -> void:
	for frame in 400:
		await process_frame
		if not panel._busy() and not panel._step_queued: return
	check(false, "queue failed to settle")
