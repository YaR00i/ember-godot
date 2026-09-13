extends SceneTree

const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const GenerationPanel = preload("res://addons/ember_import/ember_voxel_generation_panel.gd")
const SavedPanel = preload("res://addons/ember_import/ember_voxel_generator_panel.gd")
const Creation = preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
var errors: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: errors.append(message)

func _init() -> void:
	_run.call_deferred()

func occupancy(source: EmberVoxelModelResource) -> PackedByteArray:
	var result := source.voxels.duplicate()
	for index in result.size(): result[index] = 0 if result[index] == 0 else 1
	return result

func build(recipe: Resource) -> EmberVoxelModelResource:
	var result := Generator.build(recipe, Color.WHITE, {}, "Куст")
	check(not result.has("error"), "bush build " + str(result.get("error", "")))
	return result.get("geometry")

func settle(panel: Node) -> void:
	for frame in 300:
		await process_frame
		if not panel._busy() and not panel._step_queued: return
	check(false, "panel work did not settle")

func _run() -> void:
	var presets := Generator.creation_presets(Generator.BUSH)
	check(presets.size() == 3, "three bush presets")
	for entry in presets:
		for style in [1, 3]:
			var recipe: Resource = entry.recipe.duplicate(true)
			recipe.seed = 73
			recipe.parameters.foliage_style = style
			recipe.parameters.foliage_pattern_strength = 60
			var source := build(recipe)
			if source == null: continue
			check(source.validation_errors().is_empty(), "canonical bush source")
			check(source.palette.size() == 7 and source.voxels.count(1) > 8, "wood and controlled foliage palette")
			check(source.voxels.slice(0, source.grid_size().x * source.grid_size().z).count(1) >= 3, "multiple stems reach ground")
			check(source.voxels == build(recipe).voxels, "deterministic bush")
			recipe.seed += 1
			check(occupancy(source) != occupancy(build(recipe)), "seed changes silhouette, not only colours")
			recipe.seed = 73
			for key in ["foliage_detail", "foliage_pattern_strength", "foliage_highlight_color"]:
				var altered: Resource = recipe.duplicate(true)
				altered.parameters[key] = Color("cc4466") if key.ends_with("color") else 0
				var changed := build(altered)
				check(occupancy(source) == occupancy(changed), "pattern control changed shape " + key)
				check(source.voxels != changed.voxels or source.palette != changed.palette, "inert pattern control " + key)
			for key in ["foliage_density", "cluster_flatten", "stem_count", "roughness"]:
				var altered: Resource = recipe.duplicate(true)
				altered.parameters[key] = 20 if key == "foliage_density" else (3 if key == "stem_count" else 100)
				check(source.voxels != build(altered).voxels, "inert form control " + key)
			recipe.parameters.foliage_pattern_strength = 0
			var plain := build(recipe)
			check(plain.palette[4] == plain.palette[5] and plain.palette[5] == plain.palette[6], "zero pattern gives author base colour")
			recipe.parameters.structure_diversity = 0
			var frozen := occupancy(build(recipe))
			recipe.seed += 1
			check(frozen == occupancy(build(recipe)), "zero diversity freezes shape")
	var bounded := Generator.normalized_parameters(Generator.BUSH, {"generation_version": 2,
		"height": 999, "spread_radius": 999, "foliage_color": Color(NAN, 0, 0), "foliage_style": 99})
	check(bounded.height == 96 and bounded.spread_radius == 30 and bounded.foliage_style == 1 and bounded.foliage_color == Color("568f4d"), "v2 limits and colours")
	var maximum: Resource = presets[0].recipe.duplicate(true)
	maximum.parameters.merge({"height": 96, "base_height": 32, "stem_count": 12, "spread_radius": 30, "density": 32}, true)
	var start := Time.get_ticks_usec()
	var large := build(maximum)
	check(large != null and large.voxels.size() <= 524288, "largest bush fits storage budget")
	print("Bush maximum build: %.2f ms" % ((Time.get_ticks_usec() - start) / 1000.0))
	var scene := Node3D.new()
	root.add_child(scene)
	var undo := UndoRedo.new()
	var panel := GenerationPanel.new()
	root.add_child(panel)
	var folder := "user://ember-tests/bush-objects-%d" % Time.get_ticks_usec()
	panel.session.source_directory = folder.path_join("sources")
	panel.session.prefab_directory = folder.path_join("prefabs")
	panel.session.recipe_directory = folder.path_join("recipes")
	panel.presets.directory = folder.path_join("presets")
	var ui_recipe: Resource = presets[0].recipe.duplicate(true)
	ui_recipe.parameters.foliage_style = 1
	panel.open_for({"root": scene, "parent": scene, "undo": undo, "world_size": 1.0}, ui_recipe)
	check(panel._provider.item_count == 3 and panel._provider.selected == 2 and panel._title.text == "Куст", "bush studio provider visible")
	check(panel.controls.foliage_style.visible and panel.controls.structure_diversity.get_parent().visible and panel.controls.foliage_pattern_strength.get_parent().visible, "bush controls visible")
	check(panel.controls.base_height.get_parent().visible, "independent base control visible")
	panel.controls.base_height.value = 7
	check(panel.recipe.parameters.base_height == 7, "base height real binding")
	panel.undo_local()
	check(panel.recipe.parameters.base_height == 2 and panel.controls.base_height.value == 2, "base height Undo")
	panel.redo_local()
	check(panel.recipe.parameters.base_height == 7, "base height Redo")
	for kind in [1, 2]:
		panel.controls.bush_type.select(kind)
		panel.controls.bush_type.item_selected.emit(kind)
		check(panel.recipe.parameters.generation_version == 6 and panel.controls.base_height.get_parent().visible, "type choice enables cloud profile and base")
		panel.undo_local()
		check(panel.recipe.parameters.generation_version == 5 and panel.recipe.parameters.bush_type == 0, "profile choice Undo")
	panel.controls.foliage_style.select(1)
	panel.controls.foliage_style.item_selected.emit(1)
	check(panel.recipe.parameters.foliage_style == 3, "studio option value mapping")
	panel.undo_local()
	check(panel.recipe.parameters.foliage_style == 1 and panel.controls.foliage_style.selected == 0, "studio Undo")
	panel._count.value = 2
	panel.generate()
	await settle(panel)
	check(panel.session.candidates.size() == 2, "bush batch")
	if panel.session.candidates.size() >= 2:
		var a: Dictionary = panel.session.candidates[0]
		var b: Dictionary = panel.session.candidates[1]
		var original: PackedByteArray = a.creation.source.voxels.duplicate()
		var neighbour: PackedByteArray = b.creation.source.voxels.duplicate()
		panel._select_preview(a)
		panel.candidate_controls.foliage_style.select(1)
		panel.candidate_controls.foliage_style.item_selected.emit(1)
		check(panel.candidate_recipe.parameters.foliage_style == 3 and a.creation.source.voxels == original, "candidate draft mapping / source isolation")
		panel.discard_candidate()
		check(panel.candidate_controls.foliage_style.selected == 0, "candidate discard")
		panel._change_candidate_parameter("foliage_style", 3)
		panel._change_candidate_parameter("base_height", 18)
		panel.apply_candidate()
		check(a.creation.source.voxels != original and b.creation.source.voxels == neighbour, "Apply exact isolated bush")
		panel.undo_local()
		check(a.creation.source.voxels == original, "geometry Undo")
		panel.redo_local()
		check(a.creation.recipe.parameters.foliage_style == 3 and panel.candidate_controls.foliage_style.selected == 1, "geometry Redo / option restore")
		panel._choose(a, true)
		panel.save_chosen()
		await settle(panel)
		check(a.saved, "bush publication")
		var id: String = a.creation.source.model_id
		var reopened := Creation.load_recipe(id, panel.session.recipe_directory)
		check(reopened != null and reopened.parameters == a.creation.recipe.parameters, "all bush recipe settings roundtrip")
		var path: String = panel.session.source_directory.path_join(id + ".tres")
		var source := load(path) as EmberVoxelModelResource
		check(source.voxels == a.creation.source.voxels and source.palette == a.creation.source.palette, "saved source exact preview")
		var digest := FileAccess.get_sha256(path)
		panel._candidate_to_batch()
		panel._preset_name.text = "Bush fixture"
		panel._save_preset()
		check(panel.presets.list_presets(Generator.BUSH)[0].recipe.parameters == reopened.parameters, "bush custom preset")
		var saved := SavedPanel.new()
		root.add_child(saved)
		saved.recipe_directory = panel.session.recipe_directory
		check(saved.open_source(source, {"root": scene, "parent": scene, "undo": undo}) and saved.controls.foliage_style.selected == 1, "saved bush edit / value restore")
		check(saved.controls.base_height.value == 18, "saved base height restore")
		saved.controls.base_height.value = 10
		check(saved.recipe.parameters.base_height == 10, "saved base height binding")
		saved.undo_parameters()
		check(saved.recipe.parameters.base_height == 18 and saved.controls.base_height.value == 18, "saved base height Undo")
		saved.controls.foliage_style.select(0)
		saved.controls.foliage_style.item_selected.emit(0)
		saved.prepare()
		check(saved.recipe.parameters.foliage_style == 1 and saved.creation != null, "saved bush option edit")
		saved.undo_parameters()
		check(saved.recipe.parameters.foliage_style == 3 and saved.controls.foliage_style.selected == 1, "saved bush Undo")
		saved.redo_parameters()
		saved.discard()
		check(saved.recipe.parameters == reopened.parameters and FileAccess.get_sha256(path) == digest, "saved discard preserves author source")
		saved.free()
	for entry in presets.slice(1):
		var creation := Creation.new()
		creation.source_directory = panel.session.source_directory
		creation.prefab_directory = panel.session.prefab_directory
		creation.recipe_directory = panel.session.recipe_directory
		check(creation.prepare_recipe(entry.recipe, "Проверка нового типа"), "profile preview")
		check(creation.save_to_library(scene, undo), "profile publication")
		var reopened := Creation.load_recipe(creation.source.model_id, creation.recipe_directory)
		check(reopened.parameters == creation.recipe.parameters and reopened.parameters.generation_version == 6, "profile recipe save/reopen")
		var path := creation.source_directory.path_join(creation.source.model_id + ".tres")
		var source := load(path) as EmberVoxelModelResource
		check(source.voxels == creation.source.voxels and source.palette == creation.source.palette, "profile source save/reopen")
		var digest := FileAccess.get_sha256(path)
		var saved := SavedPanel.new()
		root.add_child(saved)
		saved.recipe_directory = creation.recipe_directory
		check(saved.open_source(source, {"root": scene, "parent": scene, "undo": undo}) and saved.controls.base_height.value == reopened.parameters.base_height, "profile saved controls")
		saved.controls.base_height.value = 32
		saved.prepare()
		check(saved.creation != null and saved.recipe.parameters.base_height == 32, "profile saved raised preview")
		saved.undo_parameters()
		check(saved.recipe.parameters.base_height == reopened.parameters.base_height, "profile saved height Undo")
		saved.redo_parameters()
		saved.discard()
		check(saved.recipe.parameters == reopened.parameters and FileAccess.get_sha256(path) == digest, "profile discard protects source")
		saved.free()
	panel.free()
	if DisplayServer.get_name() != "headless":
		await capture(presets)
	undo.clear_history()
	undo.free()
	scene.free()
	for message in errors: push_error(message)
	print("test_voxel_bush_objects: ", "PASS" if errors.is_empty() else "FAIL", " · ", errors.size(), " errors")
	quit(0 if errors.is_empty() else 1)


func capture(presets: Array[Dictionary]) -> void:
	var profiles := OS.get_cmdline_user_args().has("--cloud-profiles")
	var clouds := OS.get_cmdline_user_args().has("--cloud-shrub")
	var shoots := OS.get_cmdline_user_args().has("--shoot-shrub")
	var basic := shoots or OS.get_cmdline_user_args().has("--basic-silhouette")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1200, 800)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("242d36")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.3
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -25, 0)
	light.light_energy = 0.35
	world.add_child(light)
	for row in (1 if basic or clouds or profiles else 2):
		for column in 3:
			var recipe: Resource = presets[0 if basic or clouds else column].recipe.duplicate(true)
			recipe.parameters.foliage_style = 1 if row == 0 else 3
			recipe.seed = 73
			if profiles: recipe.parameters.foliage_style = 3
			if clouds:
				recipe.parameters.foliage_style = 3
				if column == 1: recipe.seed = 391
				if column == 2: recipe.parameters.merge({"base_height": 16, "stem_count": 12}, true)
			if basic:
				recipe.parameters.foliage_pattern_strength = 0
				if column == 0: recipe.parameters.generation_version = 3 if shoots else 2
				if column == 2: recipe.seed = 391
			var creation := Creation.new()
			creation.world_size = 1.0
			check(creation.prepare_recipe(recipe, "Куст"), "native bush prefab")
			if creation.packed == null: continue
			var prop := creation.packed.instantiate() as Node3D
			world.add_child(prop)
			prop.configure_voxel_scale(creation.source.normalized_density(), 1.0)
			prop.position = Vector3((column - 1) * 3.2, 0, 0 if basic or clouds or profiles else (row - 0.5) * 8.0)
			var label := Label3D.new()
			label.text = ["Округлый", "Раскидистый", "Высокий"][column] + (" · пиксель-арт" if row == 0 else " · облака")
			if basic: label.text = ["Прежняя форма", "Новый · сид 73", "Новый · сид 391"][column]
			if shoots: label.text = ["Прежние купола", "Побеги · сид 73", "Побеги · сид 391"][column]
			if clouds: label.text = ["Облака · сид 73", "Облака · сид 391", "Основание 16 · веток 12"][column]
			if profiles: label.text = ["Принятая основа", "Низкий раскидистый", "Высокий ветвистый"][column]
			label.position = prop.position + Vector3(0, -0.25, 1.3)
			label.font_size = 36
			label.pixel_size = 0.004
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			world.add_child(label)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.9 if basic else (8.4 if clouds or profiles else 10.5)
	camera.position = Vector3(0, 4, 11) if basic else (Vector3(0, 7, 12) if clouds or profiles else Vector3(0, 11, 16))
	camera.look_at(Vector3(0, 0.9, 0))
	camera.current = true
	for frame in 20: await process_frame
	await RenderingServer.frame_post_draw
	var path := "user://generation_bush_basic_native.png" if basic else "user://generation_bushes_native.png"
	if shoots: path = "user://generation_bush_shoots_native.png"
	if clouds: path = "user://generation_bush_clouds_native.png"
	if profiles: path = "user://generation_bush_profiles_native.png"
	check(viewport.get_texture().get_image().save_png(path) == OK, "native capture")
	print("BUSH_NATIVE_CAPTURE ", ProjectSettings.globalize_path(path))
	viewport.free()
