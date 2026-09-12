extends SceneTree

const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Placement = preload("res://addons/ember_import/ember_voxel_brush_placement.gd")
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
	var recipe := Generator.default_recipe(Generator.ROCK)
	recipe.seed = 7319
	recipe.parameters = {
		"dimensions": Vector3i(12, 8, 10),
		"roughness": 40,
		"chips": 35,
		"density": 16,
		"variant_count": 5,
		"size_variation": 25,
	}
	var first := Generator.build(recipe, Color.SLATE_GRAY, {}, "Камень")
	var same := Generator.build(recipe, Color.SLATE_GRAY, {}, "Камень")
	check(not first.has("error"), "rock generator build")
	if first.has("error"):
		_finish()
		return
	var geometry: EmberVoxelModelResource = first.geometry
	check(geometry.validation_errors().is_empty(), "generated rock canonical geometry")
	check(geometry.tags.has("rock") and geometry.tags.has("stamp"), "generated rock tags")
	check(geometry.voxels == same.geometry.voxels, "rock generator seed determinism")
	check(geometry.voxels.count(1) > 20, "generated rock has useful volume")
	check(_is_connected(geometry), "generated rock must remain one connected volume")
	check(_base_count(geometry) > 0, "generated rock has no stable lower contact")
	var other_recipe: Resource = recipe.duplicate(true)
	other_recipe.seed += 1
	var other := Generator.build(other_recipe, Color.SLATE_GRAY, {}, "Камень")
	check(not other.has("error") and other.geometry.voxels != geometry.voxels, "another rock variant")
	var variant_set := Generator.build_variants(recipe, geometry)
	var repeated_variant_set := Generator.build_variants(recipe, geometry)
	check(
		not variant_set.has("error") and variant_set.variants.size() == 5,
		"rock recipe builds the requested bounded variant set",
	)
	if not variant_set.has("error"):
		var distinct_variants := false
		for index in range(1, variant_set.variants.size()):
			var candidate: EmberVoxelModelResource = variant_set.variants[index]
			var repeated: EmberVoxelModelResource = repeated_variant_set.variants[index]
			check(candidate.voxels == repeated.voxels, "rock variant set determinism %d" % index)
			if candidate.grid_size() != geometry.grid_size() or candidate.voxels != geometry.voxels:
				distinct_variants = true
		check(distinct_variants, "rock variant set contains visibly different forms")
	var legacy_recipe := Generator.default_recipe(Generator.ROCK)
	legacy_recipe.parameters = {
		"dimensions": Vector3i(8, 5, 7), "roughness": 30, "chips": 20, "density": 16,
	}
	var legacy_geometry := Generator.build(legacy_recipe, Color.SLATE_GRAY, {}, "Старый камень")
	check(not legacy_geometry.has("error"), "legacy rock recipe still builds")
	if not legacy_geometry.has("error"):
		var legacy_preset := Stamp.Preset.new()
		legacy_preset.kind = Stamp.Preset.KIND_GENERATED_VOLUME
		legacy_preset.generator_recipe = legacy_recipe
		legacy_preset.geometry = legacy_geometry.geometry
		var legacy_prepared := Stamp.prepare_generated_variants(legacy_preset)
		check(
			not legacy_prepared.has("error") and legacy_prepared.variants.size() == 1,
			"legacy rock recipes remain single-form",
		)
	var normalized := Generator.normalized_parameters(Generator.ROCK, {
		"dimensions": Vector3i(1, 100, 5), "roughness": -20, "chips": 120,
		"density": 31, "variant_count": 20, "size_variation": -5,
	})
	check(
		normalized.dimensions == Vector3i(3, 32, 5)
		and normalized.roughness == 0
		and normalized.chips == 100
		and normalized.density == 16
		and normalized.variant_count == 8
		and normalized.size_variation == 0,
		"rock recipe normalization",
	)
	var large_recipe := Generator.default_recipe(Generator.ROCK)
	large_recipe.seed = 17
	large_recipe.parameters = {
		"dimensions": Vector3i(32, 32, 32),
		"roughness": 70,
		"chips": 60,
		"density": 32,
	}
	var generator_started := Time.get_ticks_usec()
	var large_result := Generator.build(large_recipe, Color.GRAY, {}, "Большой камень")
	var generator_elapsed := Time.get_ticks_usec() - generator_started
	print("Generated rock 32x32x32: %.2f ms" % (float(generator_elapsed) / 1000.0))
	check(not large_result.has("error"), "maximum bounded rock generation")
	check(generator_elapsed < 1000000, "maximum rock generation exceeded the one-second safety budget")
	large_recipe.parameters.variant_count = 8
	large_recipe.parameters.size_variation = 50
	var variants_started := Time.get_ticks_usec()
	var large_variants := Generator.build_variants(large_recipe, large_result.geometry)
	var variants_elapsed := Time.get_ticks_usec() - variants_started
	print("Generated rock set 8x up to 32^3: %.2f ms" % (float(variants_elapsed) / 1000.0))
	check(
		not large_variants.has("error") and large_variants.variants.size() == 8,
		"maximum bounded rock variant set",
	)
	check(variants_elapsed < 1000000, "maximum rock set exceeded the one-second safety budget")

	var preset := Stamp.Preset.new()
	preset.display_name = "Камень"
	preset.kind = Stamp.Preset.KIND_GENERATED_VOLUME
	preset.anchor = 1
	preset.generator_recipe = recipe
	preset.geometry = geometry
	var directory := "user://voxel_generator_%d" % Time.get_ticks_usec()
	var broken: Resource = preset.duplicate(true)
	broken.generator_recipe = null
	check(
		Stamp.save_new(
			broken, directory.path_join("broken_presets"), directory.path_join("broken_models")
		).has("error"),
		"generated stamp rejects a missing recipe",
	)
	var saved := Stamp.save_new(
		preset, directory.path_join("presets"), directory.path_join("models")
	)
	check(saved.has("path"), "generated stamp save")
	if saved.has("path"):
		var saved_text := FileAccess.get_file_as_string(saved.path)
		check(
			not saved_text.contains("generated_variants"),
			"derived rock form cache is not serialized",
		)
	var entries := Stamp.library(directory.path_join("presets"))
	check(
		entries.size() == 1
		and entries[0].kind == Stamp.Preset.KIND_GENERATED_VOLUME
		and entries[0].generator_id == Generator.ROCK
		and entries[0].variant_count == 5,
		"generated stamp library metadata",
	)
	var reopened := ResourceLoader.load(saved.path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(
		reopened.generator_recipe != null
		and reopened.generator_recipe.seed == recipe.seed
		and reopened.generator_recipe.parameters.dimensions == Vector3i(12, 8, 10),
		"generated recipe reopen",
	)

	var target: EmberVoxelModelResource = Shapes.build(
		"empty", Vector3i(32, 16, 32), 16, Color.DARK_GREEN, "rock_target", "Target"
	).source
	for z in 32:
		for x in 32:
			target.voxels[Stamp.Fragment.Model.index_of(Vector3i(x, 0, z), target.grid_size())] = 1
	var baseline := target.to_definition()
	var plan := Stamp.plan(target, reopened, Vector3i(16, 1, 16), 1, 0, -1, 1, false, 0)
	check(not plan.has("error") and plan.selected.size() > 20, "generated rock uses regular stamp plan")
	check(target.to_definition() == baseline, "generated rock preview detached")
	var path: Array[Vector3i] = Placement.sample_line(Vector3i(10, 1, 16), Vector3i(22, 1, 16), 3)
	var scatter := Stamp.plan_scatter(
		target, reopened, path, Vector3i.UP, 1, 17, true, 0, -1, 1, false, 0
	)
	var repeated_scatter := Stamp.plan_scatter(
		target, reopened, path, Vector3i.UP, 1, 17, true, 0, -1, 1, false, 0
	)
	if scatter.has("error"):
		print("Multi-form scatter error: ", scatter.error)
	check(
		not scatter.has("error")
		and scatter.placements.size() > 1
		and scatter.scatter_variants.size() == scatter.placements.size(),
		"generated rock uses shared multi-form scatter",
	)
	check(
		not repeated_scatter.has("error")
		and repeated_scatter.scatter_variants == scatter.scatter_variants
		and repeated_scatter.positions == scatter.positions
		and repeated_scatter.selected == scatter.selected,
		"multi-form scatter preview is deterministic",
	)
	var changed_scatter := Stamp.plan_scatter(
		target, reopened, path, Vector3i.UP, 1, 18, true, 0, -1, 1, false, 0
	)
	check(
		not changed_scatter.has("error")
		and (
			changed_scatter.scatter_variants != scatter.scatter_variants
			or changed_scatter.placements != scatter.placements
		),
		"another scatter variant changes placement or form choices",
	)
	check(target.to_definition() == baseline, "generated rock scatter preview detached")

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
	panel._select_create_kind(2)
	panel._title.text = "Камень из UI"
	panel._rock_width.value = 9
	panel._rock_height.value = 6
	panel._rock_depth.value = 8
	panel._rock_roughness.value = 45
	panel._rock_chips.value = 30
	panel._rock_variant_count.value = 6
	panel._rock_size_variation.value = 35
	for frame in 3:
		await process_frame
	check(
		panel._create_kind_buttons.size() == 6
		and panel._rock_panel.visible
		and not panel._pattern_panel.visible
		and panel._rock_preview.texture != null
		and panel._rock_preview_variants.size() == 4,
		"procedural rock create UI",
	)
	var rock_save := panel.find_child("VoxelWorkshopSaveRock", true, false) as Button
	check(
		panel._create_panel.get_combined_minimum_size().x <= panel._create_scroll.size.x,
		"compact rock editor has no horizontal clipping",
	)
	check(
		panel._create_scroll.get_v_scroll_bar().visible and rock_save != null,
		"compact rock editor is scrollable",
	)
	if "--capture" in OS.get_cmdline_user_args():
		for frame in 3:
			await process_frame
		root.get_texture().get_image().save_png("user://voxel_generator_rock.png")
		print("VOXEL_GENERATOR_CAPTURE ", ProjectSettings.globalize_path("user://voxel_generator_rock.png"))
	panel._create_scroll.ensure_control_visible(rock_save)
	for frame in 5:
		await process_frame
	var visible_save: Rect2 = panel._create_scroll.get_global_rect().intersection(rock_save.get_global_rect())
	check(visible_save.size.y >= rock_save.size.y - 1.0, "compact rock save action is reachable")
	panel._save_rock()
	for frame in 3:
		await process_frame
	check(
		panel._entries.size() == 2
		and panel._entries[panel._library.selected].kind == Stamp.Preset.KIND_GENERATED_VOLUME
		and panel._entries[panel._library.selected].variant_count == 6,
		"procedural rock saved into shared stamp library",
	)
	var generated_path: String = panel._entries[panel._library.selected].path
	panel._edit()
	for frame in 2:
		await process_frame
	check(
		panel._create_panel.visible
		and panel._create_kind == 2
		and panel._editing_path == generated_path
		and panel._rock_preview_geometry != null
		and int(panel._rock_variant_count.value) == 6
		and int(panel._rock_size_variation.value) == 35,
		"procedural rock recipe edit lifecycle",
	)
	var original_recipe_seed: int = panel._rock_seed
	panel._on_rock_variant()
	panel._rock_roughness.value = 80
	panel._set_create_expanded(false)
	var discarded := ResourceLoader.load(generated_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(
		discarded.generator_recipe.seed == original_recipe_seed
		and int(discarded.generator_recipe.parameters.roughness) == 45
		and int(discarded.generator_recipe.parameters.variant_count) == 6,
		"discarding rock recipe edit leaves saved source unchanged",
	)
	panel._edit()
	for frame in 2:
		await process_frame
	var edited_seed: int = panel._rock_seed + 1
	panel._on_rock_variant()
	panel._save_rock()
	var edited := ResourceLoader.load(generated_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(
		panel._entries.size() == 2
		and edited.generator_recipe.seed == edited_seed,
		"procedural rock edit updates recipe without duplicating the preset",
	)
	panel._place()
	var interaction: Control = workspace._selection_interaction
	check(int(interaction._stamp_spacing.value) == 7, "rock set gets a useful initial spacing")
	interaction._stamp_application.select(3)
	interaction._update_stamp_application_controls()
	interaction._stamp_spacing.value = 5
	interaction._stamp_scatter_spread.value = 1
	interaction._stamp_normal = Vector3i.UP
	interaction._stamp_knots.assign([Vector3i(8, 1, 12), Vector3i(24, 1, 12)])
	interaction._stamp_draft_ready = true
	interaction._stamp_draft_visible_count = interaction._all_stamp_placements().size()
	interaction._set_stamp_position(Vector3i(24, 1, 12))
	for frame in 3:
		await process_frame
	var before := target.to_definition()
	check(
		interaction.transforming
		and not interaction._is_pattern()
		and interaction._stamp_variant_count == 6
		and not interaction._plan.has("error")
		and interaction._plan.scatter_variants.size() == interaction._plan.placements.size()
		and target.to_definition() == before,
		"procedural rock uses regular detached multi-form scatter preview",
	)
	if "--capture" in OS.get_cmdline_user_args():
		for frame in 3:
			await process_frame
		root.get_texture().get_image().save_png("user://voxel_generator_rock_stamp.png")
		print(
			"VOXEL_GENERATOR_STAMP_CAPTURE ",
			ProjectSettings.globalize_path("user://voxel_generator_rock_stamp.png"),
		)
	interaction.commit()
	check(target.to_definition() != before, "procedural rock regular stamp commit")
	check(
		interaction.transforming and interaction._stamp_variant_count == 6,
		"procedural rock keeps its prepared form set after commit",
	)
	undo.undo()
	check(target.to_definition() == before, "procedural rock regular stamp Undo")
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
	var occupied := resource.voxels.size() - resource.voxels.count(0)
	if occupied == 0:
		return false
	var size := resource.grid_size()
	var first := resource.voxels.find(1)
	var pending: Array[int] = [first]
	var visited := {first: true}
	var directions: Array[Vector3i] = [
		Vector3i.LEFT, Vector3i.RIGHT, Vector3i.DOWN,
		Vector3i.UP, Vector3i.FORWARD, Vector3i.BACK,
	]
	while not pending.is_empty():
		var index: int = pending.pop_back()
		var cell := Vector3i(
			index % size.x,
			index / (size.x * size.z),
			(index / size.x) % size.z,
		)
		for direction: Vector3i in directions:
			var neighbor: Vector3i = cell + direction
			if not Stamp.Fragment.Model.contains(neighbor, size):
				continue
			var neighbor_index := Stamp.Fragment.Model.index_of(neighbor, size)
			if resource.voxels[neighbor_index] != 0 and not visited.has(neighbor_index):
				visited[neighbor_index] = true
				pending.append(neighbor_index)
	return visited.size() == occupied


func _finish() -> void:
	print("Voxel generator: ", "PASS" if errors == 0 else "FAIL %d" % errors)
	quit(errors)
