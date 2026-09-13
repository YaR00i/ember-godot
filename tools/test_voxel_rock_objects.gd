extends SceneTree
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Rock = preload("res://addons/ember_import/ember_voxel_rock_generator.gd")
const GenerationPanel = preload("res://addons/ember_import/ember_voxel_generation_panel.gd")
const SavedPanel = preload("res://addons/ember_import/ember_voxel_generator_panel.gd")
const Creation = preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
var errors: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: errors.append(message)

func _init() -> void:
	_run.call_deferred()

func settle(panel: Node) -> void:
	for frame in 300:
		await process_frame
		if not panel._busy() and not panel._step_queued: return
	check(false, "panel work did not settle")

func connected(source: EmberVoxelModelResource) -> bool:
	var grid := source.grid_size()
	var first := -1
	for index in source.voxels.size():
		if source.voxels[index] != 0:
			first = index
			break
	if first < 0: return false
	var queue: Array[int] = [first]
	var seen := {first: true}
	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		var cell := Vector3i(index % grid.x, index / (grid.x * grid.z), (index / grid.x) % grid.z)
		for direction in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
			var next: Vector3i = cell + direction
			if next.x < 0 or next.y < 0 or next.z < 0 or next.x >= grid.x or next.y >= grid.y or next.z >= grid.z: continue
			var key := Model.index_of(next, grid)
			if source.voxels[key] != 0 and not seen.has(key):
				seen[key] = true
				queue.append(key)
	return seen.size() == source.voxels.size() - source.voxels.count(0)

func occupancy(source: EmberVoxelModelResource) -> PackedByteArray:
	var cells := source.voxels.duplicate()
	for index in cells.size(): cells[index] = 0 if cells[index] == 0 else 1
	return cells

func surface_checks() -> void:
	var recipe: Resource = Generator.creation_presets(Generator.ROCK)[0].recipe.duplicate(true)
	recipe.parameters.dimensions = Vector3i(40,32,36)
	recipe.seed = 73
	var bare: EmberVoxelModelResource = Generator.build(recipe, Color.WHITE, {}, "Bare").geometry
	for parameters in [
		{"surface_strength": 80},
		{"mineral_pattern": 1, "mineral_direction": 0},
		{"mineral_pattern": 2, "mineral_width": 3},
		{"moss_coverage": 70, "moss_drape": 60},
		{"surface_strength": 65, "mineral_pattern": 2, "moss_coverage": 70},
	]:
		var dressed: Resource = recipe.duplicate(true)
		dressed.parameters.merge(parameters, true)
		var source: EmberVoxelModelResource = Generator.build(dressed, Color.WHITE, {}, "Dressed").geometry
		check(occupancy(source) == bare.voxels, "surface changed silhouette / collision occupancy")
		check(source.emissive == bare.emissive and source.shine == bare.shine and source.collision_voxels == bare.collision_voxels, "surface changed channels")
		check(source.validation_errors().is_empty() and connected(source), "dressed source invalid / disconnected")
		check(source.voxels != bare.voxels, "surface control inert " + str(parameters))
		var repeated: EmberVoxelModelResource = Generator.build(dressed, Color.RED, {}, "Repeat").geometry
		check(source.voxels == repeated.voxels and source.palette == repeated.palette, "surface not deterministic")
		dressed.parameters.surface_seed = 591
		var changed: EmberVoxelModelResource = Generator.build(dressed, Color.WHITE, {}, "Seed").geometry
		check(source.voxels != changed.voxels and occupancy(changed) == bare.voxels, "independent surface seed inert / changed shape")
		if parameters.has("moss_coverage"):
			var grid := source.grid_size()
			var lower := source.voxels.slice(0, grid.x * grid.z * 2)
			check(lower.count(5) == 0 and lower.count(6) == 0, "moss painted bottom")
	# Every exposed surface parameter has an observable, isolated effect.
	var complete: Resource = recipe.duplicate(true)
	complete.parameters.merge({"surface_strength": 80, "mineral_pattern": 1, "moss_coverage": 65, "moss_drape": 50}, true)
	var reference: EmberVoxelModelResource = Generator.build(complete, Color.WHITE, {}, "Reference").geometry
	var adjustments := {"surface_patch_size": 24, "mineral_direction": 1, "mineral_angle": 90, "mineral_width": 5, "mineral_spacing": 7, "moss_patch_size": 28, "moss_drape": 100}
	for key in adjustments:
		var changed: Resource = complete.duplicate(true)
		changed.parameters[key] = adjustments[key]
		var source: EmberVoxelModelResource = Generator.build(changed, Color.WHITE, {}, "Control").geometry
		check(source.voxels != reference.voxels and occupancy(source) == bare.voxels, "inert surface control " + key)
	for key in ["mineral_color", "moss_color", "surface_strength", "mineral_strength"]:
		var changed: Resource = complete.duplicate(true)
		changed.parameters[key] = Color("872f42") if key.ends_with("color") else 25
		check(Generator.build(changed, Color.WHITE, {}, "Tint").geometry.palette != reference.palette, "inert tint " + key)
	var old := Generator.default_recipe(Generator.ROCK)
	var previous: EmberVoxelModelResource = Generator.build(old, Color.WHITE, {}, "Old").geometry
	old.parameters.merge(complete.parameters, true)
	old.parameters.generation_version = 1
	old.parameters.dimensions = Vector3i(10,7,9)
	old.parameters.roughness = 35
	old.parameters.chips = 25
	check(Generator.build(old, Color.WHITE, {}, "Old dressed").geometry.voxels == previous.voxels, "legacy stamp changed")
	var bounded := Rock.Surface.normalized({"surface_patch_size": 1, "moss_coverage": 999, "mineral_pattern": 9, "mineral_color": "invalid", "moss_color": Color(NAN, 0, 0)})
	check(bounded.surface_patch_size == 4 and bounded.moss_coverage == 100 and bounded.mineral_pattern == 2 and bounded.moss_color == Color("394b23"), "surface normalization")
	var old_moss := Rock.Surface.normalized({"moss_color": Color("123456")})
	check(old_moss.moss_highlight_strength == 100 and old_moss.moss_highlight_color.is_equal_approx(Color("123456").lightened(0.12)), "legacy moss highlight changed")
	var covered: Resource = recipe.duplicate(true)
	covered.parameters.merge({"moss_coverage": 100, "moss_drape": 65, "moss_highlight_strength": 0}, true)
	var plain_moss: EmberVoxelModelResource = Generator.build(covered, Color.WHITE, {}, "No highlight").geometry
	check(plain_moss.voxels.count(5) > 0 and plain_moss.voxels.count(6) == 0 and plain_moss.palette[5] == plain_moss.palette[6], "zero highlight did not give single moss colour")
	covered.parameters.moss_highlight_strength = 100
	covered.parameters.moss_highlight_color = Color("662244")
	var accent: EmberVoxelModelResource = Generator.build(covered, Color.WHITE, {}, "Custom highlight").geometry
	check(accent.voxels.count(6) > 0 and accent.palette[6] == Color("662244") and occupancy(accent) == bare.voxels, "highlight colour ignored / changed shape")
	covered.parameters.moss_highlight_strength = 25
	var weak: EmberVoxelModelResource = Generator.build(covered, Color.WHITE, {}, "Weak highlight").geometry
	check(weak.palette[6].is_equal_approx(weak.palette[5].lerp(Color("662244"), 0.25)), "highlight strength ignored")
	var fractured: Resource = recipe.duplicate(true)
	fractured.parameters.merge({"mineral_pattern": 2, "mineral_vein_style": 1, "mineral_width": 2}, true)
	var main: EmberVoxelModelResource = Generator.build(fractured, Color.WHITE, {}, "New vein").geometry
	for key in ["mineral_irregularity", "mineral_branching", "mineral_vein_style"]:
		var alternate: Resource = fractured.duplicate(true)
		alternate.parameters[key] = 0
		var altered: EmberVoxelModelResource = Generator.build(alternate, Color.WHITE, {}, "Vein control").geometry
		check(altered.voxels != main.voxels and occupancy(altered) == bare.voxels, "inert vein parameter " + key)
	var repeated: EmberVoxelModelResource = Generator.build(fractured, Color.WHITE, {}, "Repeat").geometry
	check(repeated.voxels == main.voxels, "new vein nondeterministic")
	var frame_random := RandomNumberGenerator.new()
	frame_random.seed = 37
	var frame_settings := Rock.normalize(fractured.parameters)
	var with_branches := Rock.Surface._vein_frame(Vector3.RIGHT, frame_random, frame_settings.dimensions, frame_settings)
	frame_random.seed = 37
	frame_settings.mineral_branching = 0
	var without_branches := Rock.Surface._vein_frame(Vector3.RIGHT, frame_random, frame_settings.dimensions, frame_settings)
	check(with_branches.phase == without_branches.phase and with_branches.pockets == without_branches.pockets, "branch count moved main vein")
	fractured.parameters.mineral_pattern = 1
	var layers: EmberVoxelModelResource = Generator.build(fractured, Color.WHITE, {}, "Layers").geometry
	fractured.parameters.mineral_vein_style = 0
	fractured.parameters.mineral_irregularity = 0
	fractured.parameters.mineral_branching = 0
	check(Generator.build(fractured, Color.WHITE, {}, "Unchanged layers").geometry.voxels == layers.voxels, "vein controls changed accepted layers")

func _run() -> void:
	var presets := Generator.creation_presets(Generator.ROCK)
	check(presets.size() == 9, "three shapes, three dressed presets and crystal/ice forms")
	surface_checks()
	check(Rock.normalize({"dimensions": Vector3i(99,99,99)}).dimensions == Vector3i(32,32,32), "legacy bounds changed")
	check(Rock.normalize({"generation_version": 2, "dimensions": Vector3i(999,999,999)}).dimensions == Vector3i(256,128,256), "new object bounds")
	check(Rock.normalize({"generation_version": 2, "rock_type": 99, "stone_color": "bad"}).rock_type == 4, "normalize invalid type/color")
	var huge: Resource = presets[0].recipe.duplicate(true)
	huge.parameters.dimensions = Vector3i(64,64,64)
	check(Generator.candidate_limit(huge) == 2, "large mesh working set unbounded")
	for kind in 3:
		for density in [16,32]:
			var tiny := Generator.default_recipe(Generator.ROCK)
			tiny.parameters.merge({"generation_version": 2, "rock_type": kind, "dimensions": Vector3i(3,3,3), "roughness": 100, "chips": 100, "density": density, "surface_strength": 100, "mineral_pattern": 1, "mineral_width": 8, "mineral_spacing": 4, "moss_coverage": 100, "moss_drape": 100}, true)
			var extreme := Generator.build(tiny, Color.WHITE, {}, "Tiny")
			check(not extreme.has("error") and connected(extreme.geometry) and extreme.geometry.validation_errors().is_empty(), "tiny extreme settings / density")
	for preset in presets:
		var recipe: Resource = preset.recipe.duplicate(true)
		var hashes := {}
		for seed in 8:
			recipe.seed = seed * 104729
			var built := Generator.build(recipe, Color.WHITE, {}, "Rock", "rock_fixture")
			check(not built.has("error"), "build " + str(preset.name))
			if built.has("error"): continue
			var source: EmberVoxelModelResource = built.geometry
			check(source.validation_errors().is_empty(), "source schema")
			if int(recipe.parameters.rock_type) < 3 or bool(recipe.parameters.crystal_base_enabled):
				check(connected(source), "disconnected stone")
			var bottom := source.voxels.slice(0, source.grid_size().x * source.grid_size().z)
			check(bottom.count(0) < bottom.size(), "ungrounded stone")
			check(source.palette[1] == recipe.parameters.stone_color, "color parameter ignored")
			var repeated := Generator.build(recipe, Color.RED, {}, "Other title", "other_id")
			check(source.voxels == repeated.geometry.voxels, "seed nondeterministic")
			hashes[hash(source.voxels)] = true
		check(hashes.size() >= 6, "weak seed diversity " + str(preset.name))
		print("ROCK_DIVERSITY ", preset.name, " ", hashes.size(), "/8")
	var max_settings: Resource = presets[1].recipe.duplicate(true)
	max_settings.parameters.dimensions = Vector3i(64,64,64)
	var started := Time.get_ticks_usec()
	var large := Generator.build(max_settings, Color.WHITE, {}, "Large")
	check(not large.has("error"), "64^3 rock")
	print("ROCK_64_BUILD_MS ", (Time.get_ticks_usec() - started) / 1000.0)
	max_settings.parameters.merge({"surface_strength": 65, "mineral_pattern": 1, "moss_coverage": 70}, true)
	started = Time.get_ticks_usec()
	var large_surface := Generator.build(max_settings, Color.WHITE, {}, "Large surface")
	check(not large_surface.has("error") and occupancy(large_surface.geometry) == large.geometry.voxels, "64^3 dressed rock changed shape")
	print("ROCK_64_SURFACE_BUILD_MS ", (Time.get_ticks_usec() - started) / 1000.0)
	max_settings.parameters.merge({"mineral_pattern": 2, "mineral_vein_style": 1}, true)
	started = Time.get_ticks_usec()
	var large_vein := Generator.build(max_settings, Color.WHITE, {}, "Large vein")
	check(not large_vein.has("error") and occupancy(large_vein.geometry) == large.geometry.voxels, "64^3 branched vein changed shape")
	print("ROCK_64_VEIN_BUILD_MS ", (Time.get_ticks_usec() - started) / 1000.0)
	var scene := Node3D.new()
	root.add_child(scene)
	var undo := UndoRedo.new()
	var panel := GenerationPanel.new()
	root.add_child(panel)
	var folder := "user://ember-tests/rock-objects-%d" % Time.get_ticks_usec()
	panel.session.source_directory = folder.path_join("sources")
	panel.session.prefab_directory = folder.path_join("prefabs")
	panel.session.recipe_directory = folder.path_join("recipes")
	panel.presets.directory = folder.path_join("presets")
	panel.open_for({"root": scene, "parent": scene, "undo": undo, "world_size": 1.0}, presets[0].recipe)
	check(panel._provider.selected == 1 and panel.controls.has("dimensions") and not panel.controls.has("tree_type"), "provider selection and field rebuild")
	check(not panel.controls.surface_patch_size.editable and panel.controls.mineral_color.disabled and not panel.controls.moss_patch_size.editable, "inert layer controls enabled")
	panel.controls.dimensions._spins[0].value = 30
	check(panel.recipe.parameters.dimensions.x == 30, "vector width routing")
	panel.undo_local()
	check(panel.recipe.parameters.dimensions.x == 24, "vector Undo")
	panel.redo_local()
	check(panel.recipe.parameters.dimensions.x == 30, "vector Redo")
	panel._count.value = 2
	panel.generate()
	await settle(panel)
	check(panel.session.candidates.size() == 2, "rock batch")
	if panel.session.candidates.size() < 2:
		quit(1)
		return
	var a: Dictionary = panel.session.candidates[0]
	var b: Dictionary = panel.session.candidates[1]
	var preview_mesh := a.node.get_node("Mesh") as MeshInstance3D
	var colors: PackedColorArray = preview_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	check(not colors.is_empty() and colors[0].is_equal_approx(a.creation.source.palette[1]), "mesh lost stone palette")
	var original: PackedByteArray = a.creation.source.voxels.duplicate()
	var other: PackedByteArray = b.creation.source.voxels.duplicate()
	panel._select_preview(a)
	panel.candidate_controls.roughness.value = 85
	check(a.creation.source.voxels == original and panel._draft_dirty(), "draft mutated geometry")
	panel.discard_candidate()
	check(not panel._draft_dirty() and a.creation.source.voxels == original, "discard")
	panel.candidate_controls.chips.value = 85
	panel.apply_candidate()
	check(a.creation.source.voxels != original and b.creation.source.voxels == other, "isolated revision")
	panel.undo_local()
	check(a.creation.source.voxels == original, "revision Undo")
	panel.redo_local()
	check(a.creation.recipe.parameters.chips == 85, "revision Redo")
	panel.candidate_controls.stone_color.color = Color("925b43")
	panel.candidate_controls.stone_color.color_changed.emit(Color("925b43"))
	panel.apply_candidate()
	var shape := occupancy(a.creation.source)
	panel.candidate_controls.surface_strength.value = 75
	panel.candidate_controls.mineral_pattern.item_selected.emit(2)
	check(panel.candidate_controls.mineral_width.editable and not panel.candidate_controls.mineral_spacing.editable, "vein field gating")
	panel.candidate_controls.moss_coverage.value = 65
	panel.candidate_controls.moss_highlight_strength.value = 0
	check(panel.candidate_controls.moss_highlight_color.disabled, "highlight colour enabled at zero strength")
	panel.candidate_controls.surface_seed.value = 591
	panel.apply_candidate()
	check(occupancy(a.creation.source) == shape and a.creation.source.palette.size() == 7 and b.creation.source.voxels == other, "surface revision changed shape / other candidate")
	check(a.creation.source.voxels.count(6) == 0 and a.creation.recipe.parameters.mineral_vein_style == 1, "new vein opt-in / no moss highlight")
	panel.undo_local()
	check(a.creation.source.palette.size() == 2, "surface Apply Undo")
	panel.redo_local()
	check(a.creation.recipe.parameters.surface_seed == 591 and a.creation.source.palette.size() == 7, "surface Apply Redo")
	panel._choose(a, true)
	panel.save_chosen()
	await settle(panel)
	check(a.saved, "library publication")
	var id: String = a.creation.source.model_id
	var recipe_path: String = Creation.recipe_path(id, panel.session.recipe_directory)
	var reopened: Resource = Creation.load_recipe(id, panel.session.recipe_directory)
	check(reopened != null and reopened.parameters == a.creation.recipe.parameters and reopened.seed == a.creation.recipe.seed, "recipe save/reopen parameters")
	var source_path: String = panel.session.source_directory.path_join(id + ".tres")
	check((load(source_path) as EmberVoxelModelResource).palette[1] == Color("925b43"), "published color")
	var saved_source := load(source_path) as EmberVoxelModelResource
	check(saved_source.voxels == a.creation.source.voxels and saved_source.palette == a.creation.source.palette, "published surface lost voxel colors")
	var source_hash := FileAccess.get_sha256(source_path)
	panel._candidate_to_batch()
	panel._preset_name.text = "Custom stone"
	panel._save_preset()
	var custom: Array = panel.presets.list_presets(Generator.ROCK)
	check(custom.size() == 1 and custom[0].recipe.parameters == reopened.parameters, "preset parameters persistence")
	check(custom[0].recipe.structure.is_empty() and custom[0].recipe.family_id.is_empty(), "preset owns instances")
	panel.session.clear_previews()
	check(panel.session.ensure_loaded(a), "saved candidate reload")
	check(a.creation.source.voxels == (load(source_path) as EmberVoxelModelResource).voxels, "reload regenerated canonical source")
	# Saved Canvas recipe uses the same fields and publication guards as trees.
	var saved_panel := SavedPanel.new()
	root.add_child(saved_panel)
	saved_panel.recipe_directory = panel.session.recipe_directory
	check(saved_panel.open_source(load(source_path), {"root": scene, "parent": scene, "undo": undo}), "open saved recipe")
	check(saved_panel.controls.has("dimensions") and saved_panel.controls.has("stone_color"), "saved recipe editing fields")
	check(saved_panel.controls.has("surface_seed") and saved_panel.controls.has("moss_coverage") and saved_panel.controls.has("mineral_width"), "saved surface fields missing")
	check(saved_panel.controls.has("moss_highlight_strength") and saved_panel.controls.has("mineral_irregularity") and saved_panel.controls.moss_highlight_color.disabled, "saved new controls missing / gating")
	saved_panel.set_parameter("mineral_vein_style", 0)
	saved_panel.set_parameter("mineral_pattern", 2) # Same selection explicitly upgrades old style.
	check(saved_panel.recipe.parameters.mineral_vein_style == 1, "saved same-mode vein opt-in failed")
	saved_panel.undo_parameters()
	check(saved_panel.recipe.parameters.mineral_vein_style == 0, "saved vein upgrade Undo")
	saved_panel.redo_parameters()
	saved_panel.discard()
	saved_panel.set_parameter("moss_highlight_strength", 100)
	saved_panel.set_parameter("moss_highlight_color", Color("662244"))
	saved_panel.prepare()
	check(saved_panel.creation != null and saved_panel.creation.source.palette[6] == Color("662244"), "saved highlight preview ignored controls")
	saved_panel.discard()
	saved_panel.set_parameter("moss_coverage", 90)
	saved_panel.undo_parameters()
	check(saved_panel.recipe.parameters.moss_coverage == 65, "saved surface draft Undo")
	saved_panel.redo_parameters()
	saved_panel.discard()
	check(saved_panel.recipe.parameters.moss_coverage == 65, "saved surface discard")
	saved_panel.set_parameter("roughness", 50)
	saved_panel.prepare()
	check(saved_panel.creation != null and saved_panel.creation.packed != null, "saved recipe exact preview")
	if saved_panel.creation != null:
		var preview := saved_panel.creation.packed.instantiate() as Node3D
		var mesh := preview.get_node("Mesh") as MeshInstance3D
		var painted: PackedColorArray = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var visible_tints := {}
		var all_canonical := true
		var largest_error := 0.0
		for tint in painted:
			var nearest := INF
			for palette_color in saved_panel.creation.source.palette:
				nearest = minf(nearest, maxf(absf(tint.r - palette_color.r), maxf(absf(tint.g - palette_color.g), absf(tint.b - palette_color.b))))
			# ArrayMesh stores vertex colours at byte precision; palette remains float.
			all_canonical = all_canonical and nearest <= 1.0 / 255.0 + 0.00001
			largest_error = maxf(largest_error, nearest)
			visible_tints[tint] = true
		check(all_canonical, "derived mesh color not canonical")
		print("ROCK_MESH_PALETTE_MAX_ERROR ", largest_error)
		check(visible_tints.size() >= 3, "surface absent on derived mesh")
		preview.free()
	check(FileAccess.get_sha256(source_path) == source_hash and FileAccess.file_exists(recipe_path), "preview changed source")
	# Switching creation provider retains archive and favorites, never mixes families.
	panel._select_provider(0)
	check(panel.recipe.generator_id == Generator.LARGE_TREE and panel.controls.has("tree_type"), "return to trees")
	check(panel.session.candidates.size() == 2 and a.chosen and a.saved, "provider switch discarded history")
	check(panel.session.prepare_revision(b, panel.recipe) == null, "cross-provider candidate replacement")
	panel.undo_local()
	check(panel.recipe.generator_id == Generator.ROCK and panel.controls.has("dimensions"), "provider switch Undo")
	panel.redo_local()
	check(panel.recipe.generator_id == Generator.LARGE_TREE, "provider switch Redo")
	var legacy := Generator.default_recipe(Generator.ROCK)
	panel.open_for({"root": scene, "parent": scene, "undo": undo, "world_size": 1.0}, legacy)
	check(panel.controls.stone_color.disabled and panel.recipe.parameters.generation_version == 1, "legacy algorithm silently upgraded")
	check(not panel.controls.surface_strength.editable and panel.controls.mineral_pattern.disabled, "legacy offered inert surface fields")
	panel.controls.rock_type.item_selected.emit(0)
	check(panel.recipe.parameters.generation_version == 2 and not panel.controls.stone_color.disabled, "explicit same-type choice did not upgrade legacy algorithm")
	saved_panel.free()
	panel.free()
	undo.clear_history()
	undo.free()
	scene.free()
	for message in errors: push_error(message)
	print("test_voxel_rock_objects: ", "PASS" if errors.is_empty() else "FAIL", " · ", errors.size(), " errors")
	quit(0 if errors.is_empty() else 1)
