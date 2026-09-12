extends SceneTree

const Bark = preload("res://addons/ember_import/ember_voxel_bark_pattern.gd")
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Provider = preload("res://addons/ember_import/ember_voxel_large_tree_generator.gd")
const GenerationPanel = preload("res://addons/ember_import/ember_voxel_generation_panel.gd")
const GeneratorPanel = preload("res://addons/ember_import/ember_voxel_generator_panel.gd")
var failures := 0

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func occupancy(voxels: PackedByteArray) -> PackedByteArray:
	var mask := voxels.duplicate()
	for index in mask.size(): mask[index] = 0 if mask[index] == 0 else 1
	return mask

func _run() -> void:
	var wood := {}
	var rotated := {}
	for y in 33:
		for x in range(-4, 5):
			for z in range(-4, 5):
				if x * x + z * z > 16: continue
				wood[Vector3i(x, y, z)] = true
				rotated[Vector3i(z, x, y)] = true
	var line := {"start": Vector3.ZERO, "finish": Vector3(0, 32, 0), "r0": 4.0, "r1": 4.0, "t0": 0.0, "t1": 1.0, "branch": true}
	var turned := line.duplicate(true)
	turned.finish = Vector3(0, 0, 32)
	var settings := {"bark_pattern": true, "bark_pattern_density": 80, "bark_pattern_length": 12}
	var patterns: Array[Dictionary] = []
	for direction in 3:
		settings.bark_pattern_direction = direction
		var marks := Bark.marks(wood, [line], 391, settings)
		var on_branch := Bark.marks(rotated, [turned], 391, settings)
		check(not marks.is_empty() and marks.size() < wood.size(), "broken surface strokes, not a full coat")
		check(not marks.has(Vector3i(0, 16, 0)), "interior wood not painted")
		check(on_branch.size() == marks.size(), "same marks on rotated branch")
		for cell in marks: check(on_branch.has(Vector3i(cell.z, cell.x, cell.y)), "pattern follows support axis, not world Y")
		check(marks == Bark.marks(wood, [line], 391, settings), "deterministic pattern")
		patterns.append(marks)
	check(patterns[0] != patterns[1] and patterns[1] != patterns[2], "directions change stroke shape")
	settings.bark_pattern_length = 2
	var short_marks := Bark.marks(wood, [line], 391, settings)
	settings.bark_pattern_length = 24
	check(short_marks != Bark.marks(wood, [line], 391, settings), "length changes broken strokes")
	settings.bark_pattern_density = 0
	check(Bark.marks(wood, [line], 391, settings).is_empty(), "zero density paints nothing")
	settings.bark_pattern = false
	check(Bark.marks(wood, [line], 391, settings).is_empty(), "toggle off paints nothing")
	check(not Provider.normalize({"height": 64}).bark_pattern, "old missing key stays off")
	check(Bark.normalized({}).bark_pattern_version == 1, "saved missing version remains old distribution")
	settings.bark_pattern = true
	settings.bark_pattern_density = 80
	var legacy_marks := Bark.marks(wood, [line], 391, settings)
	check(not legacy_marks.is_empty(), "legacy compatibility fixture contains marks")
	settings.bark_pattern_version = 1
	check(legacy_marks == Bark.marks(wood, [line], 391, settings), "missing and explicit v1 preserve exact saved pattern")
	settings.merge({"bark_pattern": true, "bark_pattern_version": 2, "bark_pattern_density": 100, "bark_pattern_direction": 0}, true)
	for seed in [17, 371, 391]:
		var marks := Bark.marks(wood, [line], seed, settings)
		var on_branch := Bark.marks(rotated, [turned], seed, settings)
		check(marks.size() == on_branch.size(), "scattered distribution rotates with branch")
		for cell in marks: check(on_branch.has(Vector3i(cell.z, cell.x, cell.y)), "v2 frame covariance")
		for y in 64:
			var dark := 0
			for angle in 128:
				var around := (float(angle) / 128.0 - 0.5) * TAU * 2.5
				if Bark._scattered_stroke(float(y), around, 2.5, seed, settings): dark += 1
			check(dark < 85, "short cross strokes never form a dark ring, including density 100")
	for preset_index in [0, 1, 2, 3]:
		var recipe: Resource = Generator.creation_presets(Generator.LARGE_TREE)[preset_index].recipe.duplicate(true)
		recipe.parameters.height = 64
		recipe.parameters.bark_pattern = false
		var plain := Generator.build(recipe, Color.WHITE, {}, "Plain")
		recipe.structure = plain.structure.duplicate(true)
		recipe.parameters.merge({"bark_pattern": true, "bark_pattern_color": Color("912d46")}, true)
		var painted := Generator.build(recipe, Color.WHITE, {}, "Pattern")
		check(not painted.has("error"), "common pattern works for every tree type")
		if painted.has("error"): continue
		check(occupancy(plain.geometry.voxels) == occupancy(painted.geometry.voxels), "pattern never changes voxel occupancy")
		check(plain.geometry.collision_voxels == painted.geometry.collision_voxels and plain.structure.lines == painted.structure.lines, "collision and skeleton unchanged")
		check(painted.geometry.palette.size() == 8 and painted.geometry.palette[7] == Color("912d46"), "user colour has dedicated palette entry")
		recipe.parameters.bark_pattern = false
		check(Generator.build(recipe, Color.WHITE, {}, "Off").geometry.voxels == plain.geometry.voxels, "toggle off restores original wood colours exactly")
	var panel := GenerationPanel.new()
	root.add_child(panel)
	await process_frame
	panel.controls.bark_pattern.button_pressed = true
	check(panel.recipe.parameters.bark_pattern, "common creation toggle routes parameter")
	panel.undo_local()
	check(not panel.recipe.parameters.bark_pattern and not panel.controls.bark_pattern.button_pressed, "toggle Undo syncs native control")
	panel.redo_local()
	check(panel.recipe.parameters.bark_pattern and panel.controls.bark_pattern.button_pressed, "toggle Redo syncs native control")
	panel.recipe.parameters.bark_pattern_version = 1
	panel.controls.bark_pattern.button_pressed = false
	panel.controls.bark_pattern.button_pressed = true
	check(panel.recipe.parameters.bark_pattern_version == 2, "explicit creation off/on upgrades distribution")
	panel.undo_local()
	check(panel.recipe.parameters.bark_pattern_version == 1 and not panel.recipe.parameters.bark_pattern, "creation upgrade Undo restores old distribution")
	panel.free()
	var directory := "user://bark_ui_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var frozen: Resource = Generator.freeze_structure(Generator.creation_presets(Generator.LARGE_TREE)[1].recipe).recipe
	for version in [1, 2]:
		var saved_recipe := frozen.duplicate(true)
		saved_recipe.parameters.bark_pattern_version = version
		var before := Generator.build(saved_recipe, Color.WHITE, {}, "Roundtrip")
		var path := directory.path_join("bark_v%d.tres" % version)
		check(ResourceSaver.save(saved_recipe, path) == OK, "pattern version Recipe saves")
		var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		check(reopened != null and reopened.parameters.bark_pattern_version == version, "pattern version reopens unchanged")
		if reopened != null:
			check(Generator.build(reopened, Color.WHITE, {}, "Roundtrip").geometry.voxels == before.geometry.voxels, "both pattern versions reproduce exact saved colour data")
	check(ResourceSaver.save(frozen, directory.path_join("bark_ui.tres")) == OK, "contextual UI Recipe fixture saves")
	var source: Resource = Generator.build(frozen, Color.WHITE, {}, "Bark UI", "bark_ui").geometry
	var canvas_panel := GeneratorPanel.new()
	root.add_child(canvas_panel)
	await process_frame
	canvas_panel.recipe_directory = directory
	check(canvas_panel.open_source(source), "existing contextual generator opens patterned tree")
	check(canvas_panel.controls.bark_pattern is CheckButton and canvas_panel.controls.bark_pattern_direction is OptionButton, "contextual bool/choice descriptors supported")
	canvas_panel.controls.bark_pattern.button_pressed = false
	check(not canvas_panel.recipe.parameters.bark_pattern, "contextual toggle edits its own field")
	canvas_panel.undo_parameters()
	check(canvas_panel.controls.bark_pattern.button_pressed, "contextual toggle Undo syncs control")
	canvas_panel.controls.bark_pattern_direction.item_selected.emit(2)
	check(canvas_panel.recipe.parameters.bark_pattern_direction == 2, "contextual choice routes its own field")
	canvas_panel.discard()
	check(canvas_panel.recipe.parameters.bark_pattern_direction == 1 and canvas_panel.recipe.parameters.bark_pattern, "contextual discard restores Recipe baseline")
	canvas_panel.recipe.parameters.bark_pattern_version = 1
	canvas_panel.controls.bark_pattern.button_pressed = false
	canvas_panel.controls.bark_pattern.button_pressed = true
	check(canvas_panel.recipe.parameters.bark_pattern_version == 2, "explicit contextual off/on upgrades distribution")
	canvas_panel.undo_parameters()
	check(canvas_panel.recipe.parameters.bark_pattern_version == 1 and not canvas_panel.recipe.parameters.bark_pattern, "upgrade Undo restores old metadata and toggle")
	canvas_panel.free()
	print("Voxel bark pattern: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
