extends SceneTree
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Rock = preload("res://addons/ember_import/ember_voxel_rock_generator.gd")
const GenerationPanel = preload("res://addons/ember_import/ember_voxel_generation_panel.gd")
const SavedPanel = preload("res://addons/ember_import/ember_voxel_generator_panel.gd")
const Creation = preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
var errors: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: errors.append(message)

func _init() -> void:
	_run.call_deferred()

func settle(panel: Node) -> void:
	for frame in 400:
		await process_frame
		if not panel._busy() and not panel._step_queued: return
	check(false, "panel failed to settle")

func mask(source: EmberVoxelModelResource) -> PackedByteArray:
	var cells := source.voxels.duplicate()
	for index in cells.size(): cells[index] = 0 if cells[index] == 0 else 1
	return cells

func _run() -> void:
	var presets := Generator.creation_presets(Generator.ROCK)
	for index in [6,7,8]:
		var recipe: Resource = presets[index].recipe.duplicate(true)
		recipe.seed = 37
		var original: EmberVoxelModelResource = Generator.build(recipe, Color.WHITE, {}, "Reference").geometry
		var changes := {"crystal_count": 1, "crystal_width": 3, "crystal_variation": 0, "crystal_lean": 0, "crystal_tip": 1 - int(recipe.parameters.crystal_tip), "crystal_base_size": 100, "roughness": 100, "chips": 100}
		for key in changes:
			var altered: Resource = recipe.duplicate(true)
			altered.parameters[key] = changes[key]
			if key == "crystal_base_size": altered.parameters.crystal_base_enabled = true
			var report := Generator.build(altered, Color.WHITE, {}, "Control")
			check(not report.has("error"), "failed cluster control " + key)
			if report.has("error"): continue
			check(report.geometry.validation_errors().is_empty() and mask(report.geometry) != mask(original), "inert geometry control " + key + " / " + str(index))
		var surface_only: Resource = recipe.duplicate(true)
		surface_only.parameters.surface_seed = 591
		check(mask(Generator.build(surface_only, Color.WHITE, {}, "Surface").geometry) == mask(original), "surface seed changed crystal form")
		check(original.emissive.count(0) == original.emissive.size() and original.transparency.count(0) == original.transparency.size(), "prototype accidentally enabled glow / transparency")
	for kind in [3,4]:
		for density in [16,32]:
			var recipe: Resource = presets[6].recipe.duplicate(true)
			recipe.parameters.merge({"rock_type": kind, "density": density, "dimensions": Vector3i(3,3,3), "crystal_count": 8, "crystal_width": 20, "crystal_variation": 100, "crystal_lean": 100, "crystal_base_size": 0, "chips": 100}, true)
			var report := Generator.build(recipe, Color.WHITE, {}, "Tiny")
			check(not report.has("error") and report.geometry.validation_errors().is_empty(), "tiny cluster extreme")
	var normalized := Rock.normalize({"generation_version": 2, "rock_type": 3, "crystal_count": 99, "crystal_width": 0, "crystal_variation": -5, "crystal_tip": 99})
	check(normalized.crystal_count == 8 and normalized.crystal_width == 2 and normalized.crystal_variation == 0 and normalized.crystal_tip == 1, "cluster normalization")
	var max_recipe: Resource = presets[6].recipe.duplicate(true)
	max_recipe.parameters.merge({"dimensions": Vector3i(64,64,64), "crystal_count": 8, "crystal_width": 20}, true)
	var started := Time.get_ticks_usec()
	var large := Generator.build(max_recipe, Color.WHITE, {}, "Max cluster")
	check(not large.has("error") and Generator.candidate_limit(max_recipe) == 2, "large cluster build / working set")
	print("CRYSTAL_64_BUILD_MS ", (Time.get_ticks_usec() - started) / 1000.0)
	var loose: Resource = presets[6].recipe.duplicate(true)
	loose.parameters.merge({"dimensions": Vector3i(64,80,64), "crystal_width": 6, "crystal_count": 8, "crystal_lean": 0, "crystal_base_enabled": false}, true)
	var bare: EmberVoxelModelResource = Generator.build(loose, Color.WHITE, {}, "No footing").geometry
	var with_base: Resource = loose.duplicate(true)
	with_base.parameters.crystal_base_enabled = true
	var based: EmberVoxelModelResource = Generator.build(with_base, Color.WHITE, {}, "Footing").geometry
	check(bare.validation_errors().is_empty() and mask(bare) != mask(based), "base toggle inert")
	check(bare.voxels.slice(0,64 * 64).count(0) > based.voxels.slice(0,64 * 64).count(0), "platform remains without base")
	var single: Resource = loose.duplicate(true)
	single.parameters.crystal_count = 1
	var central: EmberVoxelModelResource = Generator.build(single, Color.WHITE, {}, "Single").geometry
	check(bare.voxels.size() - bare.voxels.count(0) > 2 * (central.voxels.size() - central.voxels.count(0)), "separate prisms were deleted")
	var legacy: Resource = with_base.duplicate(true)
	legacy.parameters.erase("crystal_base_enabled")
	check(Generator.build(legacy, Color.WHITE, {}, "Old recipe").geometry.voxels == based.voxels, "missing toggle changed old recipe")
	loose.parameters.crystal_base_size = 100
	check(Generator.build(loose, Color.WHITE, {}, "Inactive base").geometry.voxels == bare.voxels, "disabled base size changes geometry")
	check(Rock.normalize({"generation_version": 2, "density": 32, "dimensions": Vector3i(999,999,999)}).dimensions == Vector3i(256,256,256), "density32 axis limits")
	for kind in [0,1,2,3,4]:
		var tall: Resource = presets[6].recipe.duplicate(true)
		tall.parameters.merge({"rock_type": kind, "dimensions": Vector3i(32,128,32)}, true)
		started = Time.get_ticks_usec()
		var report := Generator.build(tall, Color.WHITE, {}, "Tall")
		check(not report.has("error") and report.geometry.height_voxels == 128 and report.geometry.validation_errors().is_empty(), "large height " + str(kind))
		print("ROCK_TALL_BUILD_MS ", kind, " ", (Time.get_ticks_usec() - started) / 1000.0)
	for dimensions in [Vector3i(64,128,64), Vector3i(256,32,64), Vector3i(32,256,32)]:
		var extended: Resource = loose.duplicate(true)
		extended.parameters.merge({"dimensions": dimensions, "density": 32}, true)
		started = Time.get_ticks_usec()
		var report := Generator.build(extended, Color.WHITE, {}, "Extended")
		check(not report.has("error") and report.geometry.validation_errors().is_empty() and Generator.candidate_limit(extended) == 1, "extended dimensions " + str(dimensions))
		print("CRYSTAL_EXTENDED_BUILD_MS ", dimensions, " ", (Time.get_ticks_usec() - started) / 1000.0)
	var oversized: Resource = loose.duplicate(true)
	oversized.parameters.merge({"dimensions": Vector3i(256,256,256), "density": 32}, true)
	check(Generator.build(oversized, Color.WHITE, {}, "Over budget").get("error", "").contains("524 288"), "oversized volume not rejected")
	var scene := Node3D.new()
	root.add_child(scene)
	var undo := UndoRedo.new()
	var panel := GenerationPanel.new()
	root.add_child(panel)
	var folder := "user://ember-tests/crystal-objects-%d" % Time.get_ticks_usec()
	panel.session.source_directory = folder.path_join("sources")
	panel.session.prefab_directory = folder.path_join("prefabs")
	panel.session.recipe_directory = folder.path_join("recipes")
	panel.presets.directory = folder.path_join("presets")
	panel.open_for({"root": scene, "parent": scene, "undo": undo, "world_size": 1.0}, presets[0].recipe)
	check(not (panel.controls.crystal_count.get_meta("rock_cluster_wrapper") as Control).visible, "cluster UI shown for plain rocks")
	panel._change_parameter("rock_type", 3)
	check((panel.controls.crystal_count.get_meta("rock_cluster_wrapper") as Control).visible, "cluster UI hidden after selecting crystal form")
	panel.undo_local()
	check(not (panel.controls.crystal_count.get_meta("rock_cluster_wrapper") as Control).visible, "form Undo did not hide cluster settings")
	panel.open_for({"root": scene, "parent": scene, "undo": undo, "world_size": 1.0}, presets[6].recipe)
	check(panel.controls.dimensions._spins[0].max_value == 256 and panel.controls.dimensions._spins[1].max_value == 128, "studio axis limits")
	check(not panel.controls.crystal_base_size.editable, "inactive base size enabled")
	panel.controls.crystal_base_enabled.button_pressed = true
	check(panel.recipe.parameters.crystal_base_enabled and panel.controls.crystal_base_size.editable, "studio footing toggle")
	panel.undo_local()
	check(not panel.recipe.parameters.crystal_base_enabled and not panel.controls.crystal_base_size.editable, "footing Undo")
	panel.controls.dimensions._spins[1].value = 80
	check(panel.recipe.parameters.dimensions.y == 80, "studio height >64")
	check(panel._count.max_value == 1, "large studio working set")
	panel.undo_local()
	panel.controls.crystal_count.value = 6
	panel.undo_local()
	check(panel.recipe.parameters.crystal_count == 5, "cluster count Undo")
	panel.redo_local()
	check(panel.recipe.parameters.crystal_count == 6, "cluster count Redo")
	panel._count.value = 2
	panel.generate()
	await settle(panel)
	check(panel.session.candidates.size() == 2, "cluster batch")
	if panel.session.candidates.size() < 2:
		quit(1)
		return
	var a: Dictionary = panel.session.candidates[0]
	var b: Dictionary = panel.session.candidates[1]
	var original: PackedByteArray = a.creation.source.voxels.duplicate()
	var other: PackedByteArray = b.creation.source.voxels.duplicate()
	panel._select_preview(a)
	check(panel.candidate_controls.has("crystal_width"), "candidate missing cluster fields")
	check(panel.candidate_controls.has("crystal_base_enabled") and not panel.candidate_controls.crystal_base_size.editable, "candidate footing controls")
	panel.candidate_controls.crystal_width.value = 12
	check(a.creation.source.voxels == original, "draft changed canonical source")
	panel.discard_candidate()
	check(panel.candidate_recipe.parameters.crystal_width == 9, "cluster discard")
	panel.candidate_controls.crystal_width.value = 12
	panel.apply_candidate()
	check(a.creation.source.voxels != original and b.creation.source.voxels == other, "cluster Apply did not isolate candidate")
	panel.undo_local()
	check(a.creation.source.voxels == original, "cluster geometry Undo")
	panel.redo_local()
	check(a.creation.recipe.parameters.crystal_width == 12, "cluster geometry Redo")
	var before_reject: PackedByteArray = a.creation.source.voxels.duplicate()
	panel._change_candidate_parameter("dimensions", Vector3i(256,128,256))
	panel.apply_candidate()
	check(a.creation.source.voxels == before_reject and panel._status.text.contains("524 288"), "over-budget Apply changed source / unclear error")
	panel.discard_candidate()
	panel.candidate_controls.dimensions._spins[1].value = 80
	check(a.creation.source.height_voxels == 40, "large candidate draft mutated source")
	panel.apply_candidate()
	check(a.creation.source.height_voxels == 80, "large candidate Apply")
	check(panel.session.ensure_loaded(b) and b.creation.source.voxels == other, "large candidate evicted neighbour changed")
	panel._choose(a, true)
	panel.save_chosen()
	await settle(panel)
	check(a.saved, "cluster publication")
	var id: String = a.creation.source.model_id
	var reopened := Creation.load_recipe(id, panel.session.recipe_directory)
	check(reopened != null and reopened.parameters == a.creation.recipe.parameters, "cluster recipe save/reopen")
	var source_path: String = panel.session.source_directory.path_join(id + ".tres")
	var source := load(source_path) as EmberVoxelModelResource
	check(source.voxels == a.creation.source.voxels and source.palette == a.creation.source.palette, "saved cluster differs from preview")
	var digest := FileAccess.get_sha256(source_path)
	panel._candidate_to_batch()
	panel._preset_name.text = "Crystal fixture"
	panel._save_preset()
	var custom := panel.presets.list_presets(Generator.ROCK)
	check(custom.size() == 1 and custom[0].recipe.parameters == reopened.parameters, "cluster custom preset lost parameters")
	panel.session.clear_previews()
	check(panel.session.ensure_loaded(a) and a.creation.source.voxels == source.voxels, "cluster saved reload regenerated source")
	var saved := SavedPanel.new()
	root.add_child(saved)
	saved.recipe_directory = panel.session.recipe_directory
	check(saved.open_source(source, {"root": scene, "parent": scene, "undo": undo}) and saved.controls.has("crystal_lean"), "saved cluster editing")
	check(saved.controls.has("crystal_base_enabled") and not saved.controls.crystal_base_size.editable and saved.controls.dimensions._spins[1].max_value == 128, "saved footing / dimensions UI")
	saved.set_parameter("crystal_base_enabled", true)
	saved.prepare()
	check(saved.creation != null and saved.controls.crystal_base_size.editable and saved.creation.source.voxels != source.voxels, "saved footing preview")
	saved.undo_parameters()
	check(not saved.recipe.parameters.crystal_base_enabled and not saved.controls.crystal_base_size.editable, "saved footing Undo")
	saved.discard()
	saved.set_parameter("crystal_tip", 0)
	saved.prepare()
	check(saved.creation != null and saved.creation.source.voxels != source.voxels, "saved cluster exact recipe preview")
	saved.undo_parameters()
	saved.redo_parameters()
	saved.discard()
	check(saved.recipe.parameters == reopened.parameters and FileAccess.get_sha256(source_path) == digest, "saved draft/discard mutated source")
	saved.free()
	panel.free()
	undo.clear_history()
	undo.free()
	scene.free()
	for message in errors: push_error(message)
	print("test_voxel_crystal_objects: ", "PASS" if errors.is_empty() else "FAIL", " · ", errors.size(), " errors")
	quit(0 if errors.is_empty() else 1)
