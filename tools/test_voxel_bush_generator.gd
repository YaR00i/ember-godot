extends SceneTree

const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Stamp = preload("res://addons/ember_import/ember_voxel_stamp.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")

var errors := 0


func check(ok: bool, label: String) -> void:
	if not ok:
		errors += 1
		push_error(label)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var recipe := Generator.default_recipe(Generator.BUSH)
	recipe.seed = 247
	recipe.parameters = {
		"height": 10,
		"spread_radius": 5,
		"stem_count": 6,
		"foliage_density": 70,
		"roughness": 40,
		"density": 16,
		"stem_color": Color("7b5239"),
		"foliage_color": Color("57964f"),
		"variant_count": 6,
		"size_variation": 25,
	}
	var first := Generator.build(recipe, Color.WHITE, {}, "Куст")
	var same := Generator.build(recipe, Color.WHITE, {}, "Куст")
	check(not first.has("error"), "bush generator build")
	if first.has("error"):
		_finish()
		return
	var geometry: EmberVoxelModelResource = first.geometry
	check(geometry.validation_errors().is_empty(), "generated bush canonical geometry")
	check(geometry.tags.has("bush") and geometry.tags.has("stamp"), "generated bush tags")
	check(geometry.voxels == same.geometry.voxels, "bush seed determinism")
	check(geometry.palette.size() == 3, "bush stem and foliage palette")
	check(geometry.voxels.count(1) >= 4, "bush has visible stems")
	check(geometry.voxels.count(2) >= 20, "bush has useful foliage")
	check(_is_connected(geometry), "bush remains one connected volume")
	check(_base_count(geometry) > 0, "bush has ground contact")
	var other_recipe: Resource = recipe.duplicate(true)
	other_recipe.seed += 1
	var other := Generator.build(other_recipe, Color.WHITE, {}, "Другой куст")
	check(not other.has("error") and other.geometry.voxels != geometry.voxels, "another bush seed")
	var variants := Generator.build_variants(recipe, geometry)
	var repeated := Generator.build_variants(recipe, geometry)
	check(
		not variants.has("error") and variants.variants.size() == 6,
		"bush builds a bounded form set",
	)
	if not variants.has("error"):
		var distinct := false
		for index in range(1, variants.variants.size()):
			var candidate: EmberVoxelModelResource = variants.variants[index]
			check(candidate.voxels == repeated.variants[index].voxels, "bush form determinism %d" % index)
			check(_is_connected(candidate), "bush form %d remains connected" % index)
			if candidate.grid_size() != geometry.grid_size() or candidate.voxels != geometry.voxels:
				distinct = true
		check(distinct, "bush form set contains distinct silhouettes")
	var normalized := Generator.normalized_parameters(Generator.BUSH, {
		"height": 100,
		"spread_radius": 100,
		"stem_count": 0,
		"foliage_density": 0,
		"roughness": 150,
		"density": 31,
		"variant_count": 20,
		"size_variation": 80,
	})
	check(
		normalized.height == 24
		and normalized.spread_radius == 12
		and normalized.stem_count == 1
		and normalized.foliage_density == 20
		and normalized.roughness == 100
		and normalized.density == 16
		and normalized.variant_count == 8
		and normalized.size_variation == 50,
		"bush recipe normalization",
	)
	var maximum := Generator.default_recipe(Generator.BUSH)
	maximum.seed = 53
	maximum.parameters = {
		"height": 24,
		"spread_radius": 12,
		"stem_count": 12,
		"foliage_density": 100,
		"roughness": 100,
		"density": 32,
		"stem_color": Color("70482e"),
		"foliage_color": Color("3f8448"),
		"variant_count": 8,
		"size_variation": 50,
	}
	var started := Time.get_ticks_usec()
	var maximum_bush := Generator.build(maximum, Color.WHITE, {}, "Большой куст")
	var maximum_set := Generator.build_variants(maximum, maximum_bush.geometry)
	var elapsed := Time.get_ticks_usec() - started
	print("Generated bush set 8x up to 24 high: %.2f ms" % (float(elapsed) / 1000.0))
	check(
		not maximum_bush.has("error")
		and not maximum_set.has("error")
		and maximum_set.variants.size() == 8,
		"maximum bounded bush form set",
	)
	check(elapsed < 1000000, "maximum bush set exceeded the one-second safety budget")

	var preset := Stamp.Preset.new()
	preset.display_name = "Куст"
	preset.kind = Stamp.Preset.KIND_GENERATED_VOLUME
	preset.anchor = 1
	preset.generator_recipe = recipe
	preset.geometry = geometry
	var directory := "user://voxel_bush_generator_%d" % Time.get_ticks_usec()
	var saved := Stamp.save_new(
		preset, directory.path_join("presets"), directory.path_join("models")
	)
	check(saved.has("path"), "generated bush save")
	var entries := Stamp.library(directory.path_join("presets"))
	check(
		entries.size() == 1
		and entries[0].generator_id == Generator.BUSH
		and entries[0].variant_count == 6,
		"generated bush library metadata",
	)
	var reopened := ResourceLoader.load(saved.path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(
		reopened.generator_recipe.generator_id == Generator.BUSH
		and reopened.generator_recipe.parameters.stem_color == Color("7b5239")
		and reopened.generator_recipe.parameters.foliage_color == Color("57964f"),
		"generated bush recipe reopen",
	)
	var prepared := Stamp.prepare_generated_variants(preset)
	check(
		not prepared.has("error")
		and prepared.variants.size() == 6
		and Stamp.recommended_spacing(preset) == 8,
		"bush set uses shared generated-source preparation",
	)
	var target: EmberVoxelModelResource = Shapes.build(
		"empty", Vector3i(64, 32, 64), 16, Color.DARK_GREEN, "bush_target", "Target"
	).source
	for z in 64:
		for x in 64:
			target.voxels[Stamp.Fragment.Model.index_of(Vector3i(x, 0, z), target.grid_size())] = 1
	var baseline := target.to_definition()
	var path: Array[Vector3i] = Stamp.sample_line(Vector3i(12, 1, 32), Vector3i(52, 1, 32), 10)
	var scatter := Stamp.plan_scatter(
		target, reopened, path, Vector3i.UP, 2, 89, true, 0, -1, 1, false, 0
	)
	check(
		not scatter.has("error")
		and scatter.scatter_variants.size() == scatter.placements.size()
		and scatter.selected.size() > 60,
		"bush uses shared multi-form scatter plan",
	)
	check(target.to_definition() == baseline, "bush scatter preview stays detached")
	await _ui(target, directory)
	_finish()


func _ui(target: EmberVoxelModelResource, directory: String) -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var undo := UndoRedo.new()
	var workspace := Workspace.new()
	workspace.setup(null, undo)
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.open_surface(target, directory.path_join("target.tres"))
	var panel: VBoxContainer = workspace._stamp_panel
	panel.directory = directory.path_join("presets")
	panel.sources = directory.path_join("models")
	panel.refresh_library()
	workspace._show_stamp_library_mode(false)
	panel._set_create_expanded(true)
	panel._select_create_kind(4)
	panel._title.text = "Куст из UI"
	panel._bush_height.value = 9
	panel._bush_spread_radius.value = 4
	panel._bush_stem_count.value = 7
	panel._bush_foliage_density.value = 75
	panel._bush_roughness.value = 45
	panel._bush_stem_color.color = Color("855b3d")
	panel._bush_foliage_color.color = Color("5ca456")
	panel._bush_variant_count.value = 5
	panel._bush_size_variation.value = 30
	for frame in 4:
		await process_frame
	check(
		panel._create_kind_buttons.size() == 6
		and panel._bush_panel.visible
		and not panel._tree_panel.visible
		and not panel._rock_panel.visible
		and panel._bush_preview.texture != null
		and panel._bush_preview_variants.size() == 4,
		"procedural bush create UI",
	)
	var save_button := panel.find_child("VoxelWorkshopSaveBush", true, false) as Button
	check(save_button != null, "bush save action exists")
	if "--capture" in OS.get_cmdline_user_args():
		root.get_texture().get_image().save_png("user://voxel_generator_bush.png")
		print(
			"VOXEL_BUSH_GENERATOR_CAPTURE ",
			ProjectSettings.globalize_path("user://voxel_generator_bush.png"),
		)
	panel._save_bush()
	for frame in 3:
		await process_frame
	check(
		panel._entries.size() == 2
		and panel._entries[panel._library.selected].generator_id == Generator.BUSH
		and panel._entries[panel._library.selected].variant_count == 5,
		"procedural bush saved into shared source library",
	)
	var generated_path: String = panel._entries[panel._library.selected].path
	panel._edit()
	for frame in 3:
		await process_frame
	check(
		panel._create_kind == 4
		and panel._editing_path == generated_path
		and int(panel._bush_height.value) == 9
		and int(panel._bush_stem_count.value) == 7,
		"procedural bush recipe edit lifecycle",
	)
	var original_seed: int = panel._bush_seed
	panel._on_bush_variant()
	panel._bush_stem_count.value = 1
	panel._set_create_expanded(false)
	var discarded := ResourceLoader.load(generated_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(
		discarded.generator_recipe.seed == original_seed
		and int(discarded.generator_recipe.parameters.stem_count) == 7,
		"discarding bush recipe edit leaves saved source unchanged",
	)
	panel._edit()
	for frame in 2:
		await process_frame
	var edited_seed: int = panel._bush_seed + 1
	panel._on_bush_variant()
	panel._save_bush()
	var edited := ResourceLoader.load(generated_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(
		panel._entries.size() == 2 and edited.generator_recipe.seed == edited_seed,
		"procedural bush edit updates the same library card",
	)
	panel._place()
	var interaction: Control = workspace._selection_interaction
	check(
		interaction._stamp_variant_count == 5 and int(interaction._stamp_spacing.value) == 6,
		"bush source prepares its set and spacing once selected",
	)
	var before := target.to_definition()
	interaction._stamp_application.select(3)
	interaction._update_stamp_application_controls()
	interaction._stamp_spacing.value = 10
	interaction._stamp_scatter_spread.value = 2
	interaction._stamp_normal = Vector3i.UP
	interaction._stamp_knots.assign([Vector3i(12, 1, 24), Vector3i(52, 1, 24)])
	interaction._stamp_draft_ready = true
	interaction._stamp_draft_visible_count = interaction._all_stamp_placements().size()
	interaction._set_stamp_position(Vector3i(52, 1, 24))
	for frame in 4:
		await process_frame
	check(
		interaction.transforming
		and not interaction._plan.has("error")
		and target.to_definition() == before,
		"bush uses detached shared scatter preview",
	)
	interaction.commit()
	check(target.to_definition() != before, "bush scatter commit")
	check(interaction.transforming and interaction._stamp_variant_count == 5, "bush stays selected")
	undo.undo()
	check(target.to_definition() == before, "bush scatter one-step Undo")
	workspace.free()
	undo.clear_history()
	undo.free()


func _base_count(resource: EmberVoxelModelResource) -> int:
	var count := 0
	var size := resource.grid_size()
	for z in size.z:
		for x in size.x:
			if resource.voxels[Stamp.Fragment.Model.index_of(Vector3i(x, 0, z), size)] != 0:
				count += 1
	return count


func _is_connected(resource: EmberVoxelModelResource) -> bool:
	var occupied := {}
	var first := -1
	for index in resource.voxels.size():
		if resource.voxels[index] != 0:
			occupied[index] = true
			if first < 0:
				first = index
	if first < 0:
		return false
	var size := resource.grid_size()
	var visited := {first: true}
	var pending: Array[int] = [first]
	var directions: Array[Vector3i] = [
		Vector3i.LEFT, Vector3i.RIGHT, Vector3i.DOWN,
		Vector3i.UP, Vector3i.FORWARD, Vector3i.BACK,
	]
	while not pending.is_empty():
		var index: int = pending.pop_back()
		var cell := Stamp.Fragment.Selection.cell_of(index, size)
		for direction in directions:
			var neighbor: Vector3i = cell + direction
			if not Stamp.Fragment.Model.contains(neighbor, size):
				continue
			var neighbor_index := Stamp.Fragment.Model.index_of(neighbor, size)
			if occupied.has(neighbor_index) and not visited.has(neighbor_index):
				visited[neighbor_index] = true
				pending.append(neighbor_index)
	return visited.size() == occupied.size()


func _finish() -> void:
	print("Voxel bush generator: ", "PASS" if errors == 0 else "FAIL %d" % errors)
	quit(0 if errors == 0 else 1)
