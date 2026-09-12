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
	var recipe := Generator.default_recipe(Generator.GRASS)
	recipe.seed = 631
	recipe.parameters = {
		"height": 7,
		"spread_radius": 2,
		"blade_count": 9,
		"height_variation": 40,
		"lean": 45,
		"density": 16,
		"base_color": Color("4c843c"),
		"tip_color": Color("91c85c"),
		"variant_count": 6,
		"size_variation": 25,
	}
	var first := Generator.build(recipe, Color.WHITE, {}, "Трава")
	var same := Generator.build(recipe, Color.WHITE, {}, "Трава")
	check(not first.has("error"), "grass generator build")
	if first.has("error"):
		_finish()
		return
	var geometry: EmberVoxelModelResource = first.geometry
	check(geometry.validation_errors().is_empty(), "generated grass canonical geometry")
	check(geometry.tags.has("grass") and geometry.tags.has("stamp"), "generated grass tags")
	check(geometry.voxels == same.geometry.voxels, "grass seed determinism")
	check(geometry.palette.size() == 3, "grass base and tip palette")
	check(geometry.voxels.count(1) > 0 and geometry.voxels.count(2) > 0, "grass two-tone blades")
	check(_layer_count(geometry, 6) > 0, "grass reaches requested height")
	check(
		geometry.collision_voxels.size() == geometry.voxels.size()
		and geometry.collision_voxels.count(1) == 0,
		"grass is explicitly non-colliding",
	)
	var other_recipe: Resource = recipe.duplicate(true)
	other_recipe.seed += 1
	var other := Generator.build(other_recipe, Color.WHITE, {}, "Другая трава")
	check(not other.has("error") and other.geometry.voxels != geometry.voxels, "another grass seed")
	var variants := Generator.build_variants(recipe, geometry)
	var repeated := Generator.build_variants(recipe, geometry)
	check(
		not variants.has("error") and variants.variants.size() == 6,
		"grass builds a bounded form set",
	)
	if not variants.has("error"):
		var distinct := false
		for index in range(1, variants.variants.size()):
			var candidate: EmberVoxelModelResource = variants.variants[index]
			check(candidate.voxels == repeated.variants[index].voxels, "grass form determinism %d" % index)
			check(
				candidate.collision_voxels.size() == candidate.voxels.size()
				and candidate.collision_voxels.count(1) == 0,
				"grass form %d stays decorative" % index,
			)
			if candidate.grid_size() != geometry.grid_size() or candidate.voxels != geometry.voxels:
				distinct = true
		check(distinct, "grass form set contains distinct silhouettes")
	var normalized := Generator.normalized_parameters(Generator.GRASS, {
		"height": 100,
		"spread_radius": 100,
		"blade_count": 0,
		"height_variation": 100,
		"lean": -1,
		"density": 31,
		"variant_count": 20,
		"size_variation": 80,
	})
	check(
		normalized.height == 12
		and normalized.spread_radius == 4
		and normalized.blade_count == 2
		and normalized.height_variation == 75
		and normalized.lean == 0
		and normalized.density == 16
		and normalized.variant_count == 8
		and normalized.size_variation == 50,
		"grass recipe normalization",
	)
	var maximum := Generator.default_recipe(Generator.GRASS)
	maximum.seed = 97
	maximum.parameters = {
		"height": 12,
		"spread_radius": 4,
		"blade_count": 16,
		"height_variation": 75,
		"lean": 100,
		"density": 32,
		"base_color": Color("467a39"),
		"tip_color": Color("9dce62"),
		"variant_count": 8,
		"size_variation": 50,
	}
	var started := Time.get_ticks_usec()
	var maximum_grass := Generator.build(maximum, Color.WHITE, {}, "Высокая трава")
	var maximum_set := Generator.build_variants(maximum, maximum_grass.geometry)
	var elapsed := Time.get_ticks_usec() - started
	print("Generated grass set 8x up to 12 high: %.2f ms" % (float(elapsed) / 1000.0))
	check(
		not maximum_grass.has("error")
		and not maximum_set.has("error")
		and maximum_set.variants.size() == 8,
		"maximum bounded grass form set",
	)
	check(elapsed < 1000000, "maximum grass set exceeded the one-second safety budget")

	var preset := Stamp.Preset.new()
	preset.display_name = "Трава"
	preset.kind = Stamp.Preset.KIND_GENERATED_VOLUME
	preset.anchor = 1
	preset.generator_recipe = recipe
	preset.geometry = geometry
	var defaults := Stamp.recommended_placement(preset)
	check(
		int(defaults.application) == 3
		and not bool(defaults.conform)
		and not bool(defaults.allow_conform)
		and bool(defaults.up_only)
		and Stamp.recommended_spacing(preset) == 5,
		"grass placement defaults",
	)
	var single_recipe := recipe.duplicate(true)
	single_recipe.parameters = single_recipe.parameters.duplicate(true)
	single_recipe.parameters.variant_count = 1
	var single_preset := preset.duplicate(true)
	single_preset.generator_recipe = single_recipe
	check(Stamp.recommended_spacing(single_preset) == 5, "single grass form keeps safe spacing")
	var directory := "user://voxel_grass_generator_%d" % Time.get_ticks_usec()
	var saved := Stamp.save_new(
		preset, directory.path_join("presets"), directory.path_join("models")
	)
	check(saved.has("path"), "generated grass save")
	var entries := Stamp.library(directory.path_join("presets"))
	check(
		entries.size() == 1
		and entries[0].generator_id == Generator.GRASS
		and entries[0].variant_count == 6,
		"generated grass library metadata",
	)
	var reopened := ResourceLoader.load(saved.path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(
		reopened.generator_recipe.generator_id == Generator.GRASS
		and reopened.geometry.collision_voxels.size() == reopened.geometry.voxels.size(),
		"generated grass recipe and collision reopen",
	)
	var target: EmberVoxelModelResource = Shapes.build(
		"empty", Vector3i(64, 24, 64), 16, Color.DARK_GREEN, "grass_target", "Target"
	).source
	for z in 64:
		for x in 64:
			target.voxels[Stamp.Fragment.Model.index_of(Vector3i(x, 0, z), target.grid_size())] = 1
	var baseline := target.to_definition()
	var path: Array[Vector3i] = Stamp.sample_line(Vector3i(12, 1, 32), Vector3i(52, 1, 32), 7)
	var scatter := Stamp.plan_scatter(
		target, reopened, path, Vector3i.UP, 2, 41, true, 0, -1, 1, true, 2
	)
	check(not scatter.has("error") and scatter.selected.size() > 20, "grass scatter plan")
	if not scatter.has("error"):
		var collision: PackedByteArray = scatter.properties.collision_voxels
		check(collision.size() == target.voxels.size(), "grass creates explicit target collision mask")
		check(
			collision[Stamp.Fragment.Model.index_of(Vector3i(0, 0, 0), target.grid_size())] == 1,
			"legacy ground stays colliding",
		)
		var decorative := true
		for index in scatter.selected:
			if collision[index] != 0:
				decorative = false
				break
		check(decorative, "placed grass stays non-colliding")
	var side := Stamp.plan(
		target, reopened, Vector3i(20, 1, 20), 0, 0, -1, 1, false, 1,
		Rect2i(), -1, Vector3i.RIGHT
	)
	check(side.has("error") and str(side.error).contains("растёт вверх"), "grass rejects side growth")
	check(target.to_definition() == baseline, "grass previews stay detached")
	_test_legacy_stamp_on_explicit_collision(target)
	await _ui(target, directory)
	_finish()


func _test_legacy_stamp_on_explicit_collision(template: EmberVoxelModelResource) -> void:
	var target := template.duplicate(true) as EmberVoxelModelResource
	target.collision_voxels.resize(target.voxels.size())
	for index in target.voxels.size():
		target.collision_voxels[index] = 1 if target.voxels[index] != 0 else 0
	var shape: EmberVoxelModelResource = Shapes.build(
		"block", Vector3i(2, 2, 2), 16, Color.SADDLE_BROWN, "legacy", "Legacy"
	).source
	shape.material = target.material.duplicate(true)
	var preset := Stamp.Preset.new()
	preset.display_name = "Legacy"
	preset.geometry = shape
	var plan := Stamp.plan(target, preset, Vector3i(30, 1, 30), 1, 0, -1, 1, false, 1, Rect2i(), -1, Vector3i.UP)
	check(not plan.has("error"), "legacy stamp on explicit collision target")
	if not plan.has("error"):
		var collision: PackedByteArray = plan.properties.collision_voxels
		var physical := true
		for index in plan.selected:
			if collision[index] != 1:
				physical = false
				break
		check(physical, "legacy occupied stamp remains physical")


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
	panel._select_create_kind(5)
	panel._title.text = "Трава из UI"
	panel._grass_height.value = 6
	panel._grass_spread_radius.value = 2
	panel._grass_blade_count.value = 10
	panel._grass_height_variation.value = 50
	panel._grass_lean.value = 55
	panel._grass_base_color.color = Color("508c42")
	panel._grass_tip_color.color = Color("96c963")
	panel._grass_variant_count.value = 5
	panel._grass_size_variation.value = 30
	for frame in 4:
		await process_frame
	check(
		panel._create_kind_buttons.size() == 6
		and panel._grass_panel.visible
		and not panel._bush_panel.visible
		and panel._grass_preview.texture != null
		and panel._grass_preview_variants.size() == 4,
		"procedural grass create UI",
	)
	if "--capture" in OS.get_cmdline_user_args():
		root.get_texture().get_image().save_png("user://voxel_generator_grass.png")
		print(
			"VOXEL_GRASS_GENERATOR_CAPTURE ",
			ProjectSettings.globalize_path("user://voxel_generator_grass.png"),
		)
	panel._save_grass()
	for frame in 3:
		await process_frame
	check(
		panel._entries.size() == 2
		and panel._entries[panel._library.selected].generator_id == Generator.GRASS,
		"procedural grass saved into shared source library",
	)
	var generated_path: String = panel._entries[panel._library.selected].path
	panel._edit()
	for frame in 3:
		await process_frame
	check(
		panel._create_kind == 5
		and panel._editing_path == generated_path
		and int(panel._grass_blade_count.value) == 10,
		"procedural grass recipe edit lifecycle",
	)
	var original_seed: int = panel._grass_seed
	panel._on_grass_variant()
	panel._grass_blade_count.value = 2
	panel._set_create_expanded(false)
	var discarded := ResourceLoader.load(generated_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(
		discarded.generator_recipe.seed == original_seed
		and int(discarded.generator_recipe.parameters.blade_count) == 10,
		"discarding grass recipe edit leaves saved source unchanged",
	)
	panel._edit()
	for frame in 2:
		await process_frame
	panel._on_grass_variant()
	panel._save_grass()
	panel._place()
	var interaction: Control = workspace._selection_interaction
	check(
		interaction._stamp_variant_count == 5
		and interaction._stamp_application.selected == 3
		and not interaction._stamp_scatter_conform.button_pressed
		and int(interaction._stamp_spacing.value) == 5,
		"grass starts as an upright root-snapped scatter and remembers shared settings",
	)
	var before := target.to_definition()
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
		"grass uses detached shared scatter preview",
	)
	interaction.commit()
	check(target.to_definition() != before, "grass scatter commit")
	check(
		target.collision_voxels.size() == target.voxels.size(),
		"grass commit keeps explicit mixed collision",
	)
	undo.undo()
	check(target.to_definition() == before, "grass scatter one-step Undo")
	workspace.free()
	undo.clear_history()
	undo.free()


func _layer_count(resource: EmberVoxelModelResource, y: int) -> int:
	var count := 0
	var size := resource.grid_size()
	for z in size.z:
		for x in size.x:
			if resource.voxels[Stamp.Fragment.Model.index_of(Vector3i(x, y, z), size)] != 0:
				count += 1
	return count


func _finish() -> void:
	print("Voxel grass generator: ", "PASS" if errors == 0 else "FAIL %d" % errors)
	quit(0 if errors == 0 else 1)
