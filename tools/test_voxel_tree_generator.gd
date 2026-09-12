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
	var recipe := Generator.default_recipe(Generator.TREE)
	recipe.seed = 419
	recipe.parameters = {
		"height": 18,
		"trunk_width": 2,
		"crown_radius": 5,
		"branchiness": 60,
		"crown_roughness": 40,
		"density": 16,
		"trunk_color": Color("825637"),
		"foliage_color": Color("4c9855"),
		"variant_count": 5,
		"size_variation": 25,
	}
	var first := Generator.build(recipe, Color.WHITE, {}, "Дерево")
	var same := Generator.build(recipe, Color.WHITE, {}, "Дерево")
	check(not first.has("error"), "tree generator build")
	if first.has("error"):
		_finish()
		return
	var geometry: EmberVoxelModelResource = first.geometry
	check(geometry.validation_errors().is_empty(), "generated tree canonical geometry")
	check(geometry.tags.has("tree") and geometry.tags.has("stamp"), "generated tree tags")
	check(geometry.voxels == same.geometry.voxels, "tree seed determinism")
	check(geometry.palette.size() == 3, "tree trunk and foliage palette")
	check(geometry.voxels.count(1) >= 12, "tree has a useful trunk")
	check(geometry.voxels.count(2) >= 40, "tree has a useful crown")
	check(_is_connected(geometry), "tree remains one connected volume")
	check(_base_count(geometry) > 0, "tree has a ground contact")
	var other_recipe: Resource = recipe.duplicate(true)
	other_recipe.seed += 1
	var other := Generator.build(other_recipe, Color.WHITE, {}, "Другое дерево")
	check(not other.has("error") and other.geometry.voxels != geometry.voxels, "another tree seed")
	var variants := Generator.build_variants(recipe, geometry)
	var repeated_variants := Generator.build_variants(recipe, geometry)
	check(
		not variants.has("error") and variants.variants.size() == 5,
		"tree builds a bounded form set",
	)
	if not variants.has("error"):
		var distinct := false
		for index in range(1, variants.variants.size()):
			var candidate: EmberVoxelModelResource = variants.variants[index]
			var repeated: EmberVoxelModelResource = repeated_variants.variants[index]
			check(candidate.voxels == repeated.voxels, "tree form set determinism %d" % index)
			check(_is_connected(candidate), "tree form %d remains connected" % index)
			if candidate.grid_size() != geometry.grid_size() or candidate.voxels != geometry.voxels:
				distinct = true
		check(distinct, "tree form set contains distinct silhouettes")
	var normalized := Generator.normalized_parameters(Generator.TREE, {
		"height": 100,
		"trunk_width": 0,
		"crown_radius": 100,
		"branchiness": -1,
		"crown_roughness": 150,
		"density": 31,
		"variant_count": 20,
		"size_variation": 80,
	})
	check(
		normalized.height == 32
		and normalized.trunk_width == 1
		and normalized.crown_radius == 10
		and normalized.branchiness == 0
		and normalized.crown_roughness == 100
		and normalized.density == 16
		and normalized.variant_count == 8
		and normalized.size_variation == 50,
		"tree recipe normalization",
	)
	var large_recipe := Generator.default_recipe(Generator.TREE)
	large_recipe.seed = 91
	large_recipe.parameters = {
		"height": 32,
		"trunk_width": 5,
		"crown_radius": 10,
		"branchiness": 100,
		"crown_roughness": 100,
		"density": 32,
		"trunk_color": Color("70482e"),
		"foliage_color": Color("3f8448"),
		"variant_count": 8,
		"size_variation": 50,
	}
	var large_started := Time.get_ticks_usec()
	var large_tree := Generator.build(large_recipe, Color.WHITE, {}, "Большое дерево")
	var large_set := Generator.build_variants(large_recipe, large_tree.geometry)
	var large_elapsed := Time.get_ticks_usec() - large_started
	print("Generated tree set 8x up to 32 high: %.2f ms" % (float(large_elapsed) / 1000.0))
	check(
		not large_tree.has("error") and not large_set.has("error") and large_set.variants.size() == 8,
		"maximum bounded tree form set",
	)
	check(large_elapsed < 1000000, "maximum tree set exceeded the one-second safety budget")

	var preset := Stamp.Preset.new()
	preset.display_name = "Дерево"
	preset.kind = Stamp.Preset.KIND_GENERATED_VOLUME
	preset.anchor = 1
	preset.generator_recipe = recipe
	preset.geometry = geometry
	var directory := "user://voxel_tree_generator_%d" % Time.get_ticks_usec()
	var saved := Stamp.save_new(
		preset, directory.path_join("presets"), directory.path_join("models")
	)
	check(saved.has("path"), "generated tree save")
	if saved.has("path"):
		check(
			not FileAccess.get_file_as_string(saved.path).contains("generated_variants"),
			"transient tree form cache is not serialized",
		)
	var entries := Stamp.library(directory.path_join("presets"))
	check(
		entries.size() == 1
		and entries[0].generator_id == Generator.TREE
		and entries[0].variant_count == 5,
		"generated tree library metadata",
	)
	var reopened := ResourceLoader.load(saved.path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(
		reopened.generator_recipe.generator_id == Generator.TREE
		and reopened.generator_recipe.parameters.trunk_color == Color("825637")
		and reopened.generator_recipe.parameters.foliage_color == Color("4c9855"),
		"generated tree recipe reopen",
	)
	var prepared := Stamp.prepare_generated_variants(preset)
	check(
		not prepared.has("error")
		and prepared.variants.size() == 5
		and Stamp.recommended_spacing(preset) == 9,
		"tree set uses shared generated-source preparation",
	)
	var target: EmberVoxelModelResource = Shapes.build(
		"empty", Vector3i(64, 32, 64), 16, Color.DARK_GREEN, "tree_target", "Target"
	).source
	for z in 64:
		for x in 64:
			target.voxels[Stamp.Fragment.Model.index_of(Vector3i(x, 0, z), target.grid_size())] = 1
	var baseline := target.to_definition()
	var path: Array[Vector3i] = Stamp.sample_line(Vector3i(16, 1, 32), Vector3i(48, 1, 32), 12)
	var scatter := Stamp.plan_scatter(
		target, reopened, path, Vector3i.UP, 2, 73, true, 0, -1, 1, false, 0
	)
	check(
		not scatter.has("error")
		and scatter.scatter_variants.size() == scatter.placements.size()
		and scatter.selected.size() > 100,
		"tree uses shared multi-form scatter plan",
	)
	check(target.to_definition() == baseline, "tree scatter preview stays detached")
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
	panel._select_create_kind(3)
	panel._title.text = "Дерево из UI"
	panel._tree_height.value = 16
	panel._tree_trunk_width.value = 2
	panel._tree_crown_radius.value = 4
	panel._tree_branchiness.value = 70
	panel._tree_crown_roughness.value = 45
	panel._tree_trunk_color.color = Color("8b5a38")
	panel._tree_foliage_color.color = Color("55a65d")
	panel._tree_variant_count.value = 6
	panel._tree_size_variation.value = 30
	for frame in 4:
		await process_frame
	check(
		panel._create_kind_buttons.size() == 6
		and panel._tree_panel.visible
		and not panel._rock_panel.visible
		and panel._tree_preview.texture != null
		and panel._tree_preview_variants.size() == 4,
		"procedural tree create UI",
	)
	var tree_save := panel.find_child("VoxelWorkshopSaveTree", true, false) as Button
	check(
		panel._create_panel.get_combined_minimum_size().x <= panel._create_scroll.size.x,
		"compact tree editor has no horizontal clipping",
	)
	check(
		panel._create_scroll.get_v_scroll_bar().visible and tree_save != null,
		"compact tree editor is scrollable",
	)
	if "--capture" in OS.get_cmdline_user_args():
		root.get_texture().get_image().save_png("user://voxel_generator_tree.png")
		print(
			"VOXEL_TREE_GENERATOR_CAPTURE ",
			ProjectSettings.globalize_path("user://voxel_generator_tree.png"),
		)
	panel._create_scroll.ensure_control_visible(tree_save)
	for frame in 5:
		await process_frame
	var visible_save: Rect2 = panel._create_scroll.get_global_rect().intersection(tree_save.get_global_rect())
	check(visible_save.size.y >= tree_save.size.y - 1.0, "compact tree save action is reachable")
	panel._save_tree()
	for frame in 3:
		await process_frame
	check(
		panel._entries.size() == 2
		and panel._entries[panel._library.selected].generator_id == Generator.TREE
		and panel._entries[panel._library.selected].variant_count == 6,
		"procedural tree saved into shared source library",
	)
	var generated_path: String = panel._entries[panel._library.selected].path
	panel._edit()
	for frame in 3:
		await process_frame
	check(
		panel._create_panel.visible
		and panel._create_kind == 3
		and panel._editing_path == generated_path
		and int(panel._tree_height.value) == 16
		and int(panel._tree_variant_count.value) == 6
		and panel._tree_trunk_color.color == Color("8b5a38"),
		"procedural tree recipe edit lifecycle",
	)
	var original_seed: int = panel._tree_seed
	panel._on_tree_variant()
	panel._tree_branchiness.value = 10
	panel._set_create_expanded(false)
	var discarded := ResourceLoader.load(generated_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(
		discarded.generator_recipe.seed == original_seed
		and int(discarded.generator_recipe.parameters.branchiness) == 70,
		"discarding tree recipe edit leaves saved source unchanged",
	)
	panel._edit()
	for frame in 2:
		await process_frame
	var edited_seed: int = panel._tree_seed + 1
	panel._on_tree_variant()
	panel._save_tree()
	var edited := ResourceLoader.load(generated_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(
		panel._entries.size() == 2 and edited.generator_recipe.seed == edited_seed,
		"procedural tree edit updates the same library card",
	)
	panel._place()
	var interaction: Control = workspace._selection_interaction
	check(
		interaction._stamp_variant_count == 6 and int(interaction._stamp_spacing.value) == 7,
		"tree source prepares its set and useful spacing once selected",
	)
	interaction._stamp_application.select(3)
	interaction._update_stamp_application_controls()
	interaction._stamp_spacing.value = 12
	interaction._stamp_scatter_spread.value = 2
	interaction._stamp_normal = Vector3i.UP
	interaction._stamp_knots.assign([Vector3i(16, 1, 24), Vector3i(48, 1, 24)])
	interaction._stamp_draft_ready = true
	interaction._stamp_draft_visible_count = interaction._all_stamp_placements().size()
	interaction._set_stamp_position(Vector3i(48, 1, 24))
	for frame in 5:
		await process_frame
	var before := target.to_definition()
	check(
		interaction.transforming
		and not interaction._plan.has("error")
		and interaction._plan.scatter_variants.size() == interaction._plan.placements.size()
		and target.to_definition() == before,
		"tree uses detached shared forest scatter preview",
	)
	if "--capture" in OS.get_cmdline_user_args():
		root.get_texture().get_image().save_png("user://voxel_generator_tree_scatter.png")
		print(
			"VOXEL_TREE_SCATTER_CAPTURE ",
			ProjectSettings.globalize_path("user://voxel_generator_tree_scatter.png"),
		)
	interaction.commit()
	check(target.to_definition() != before, "tree scatter commit")
	check(interaction.transforming and interaction._stamp_variant_count == 6, "tree stays selected")
	undo.undo()
	check(target.to_definition() == before, "tree scatter one-step Undo")
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
	print("Voxel tree generator: ", "PASS" if errors == 0 else "FAIL %d" % errors)
	quit(0 if errors == 0 else 1)
