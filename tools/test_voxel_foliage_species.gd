extends SceneTree

const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Creation = preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
const Pattern = preload("res://addons/ember_import/ember_voxel_foliage_pattern.gd")
const GenerationPanel = preload("res://addons/ember_import/ember_voxel_generation_panel.gd")
const RecipePanel = preload("res://addons/ember_import/ember_voxel_generator_panel.gd")

var failures := 0
var directory := "user://foliage_species_%d" % Time.get_ticks_usec()

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error(message)

func _init() -> void:
	_run.call_deferred()

func wood_positions(source: EmberVoxelModelResource, physical := false) -> Dictionary:
	var result := {}
	var grid := source.grid_size()
	for index in source.voxels.size():
		if source.voxels[index] not in [1, 2, 3]: continue
		if physical and source.collision_voxels[index] == 0: continue
		result[Vector3i(index % grid.x - grid.x / 2, index / (grid.x * grid.z), (index / grid.x) % grid.z - grid.z / 2)] = true
	return result

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var scene := Node3D.new()
	root.add_child(scene)
	var undo := UndoRedo.new()
	var panel := GenerationPanel.new()
	root.add_child(panel)
	panel.open_for({"root": scene, "parent": scene, "undo": undo})
	var presets := Generator.creation_presets(Generator.LARGE_TREE)
	for kind in 5:
		var recipe: Resource = presets[kind].recipe.duplicate(true)
		recipe.parameters.height = 64
		recipe.parameters.trunk_width = 4
		recipe.parameters.crown_spread = 65
		recipe.seed = 371
		panel._apply_recipe(recipe)
		check(panel.controls.foliage_style.visible and not panel.controls.foliage_style.is_item_disabled(1) and not panel.controls.foliage_style.is_item_disabled(3), "both styles selectable for species %d" % kind)
		check(panel.controls.foliage_style.is_item_disabled(2) == (kind != 1), "shoot trial remains oak-only")
		if kind == 1:
			panel.controls.foliage_style.item_selected.emit(2)
			panel.controls.tree_type.item_selected.emit(0)
			check(panel.recipe.parameters.foliage_style == 0, "explicit species change does not carry unsupported shoot trial")
			panel.undo_local()
			check(panel.recipe.parameters.foliage_style == 2, "species change Undo restores oak shoot style")
			panel._apply_recipe(recipe)
		panel.controls.foliage_style.item_selected.emit(3)
		panel.undo_local()
		check(panel.recipe.parameters.foliage_style == 0, "creation style Undo")
		panel.redo_local()
		check(panel.recipe.parameters.foliage_style == 3, "creation style Redo")
		var frozen := Generator.freeze_structure(recipe)
		check(not frozen.has("error"), "species structure freezes")
		var legacy := Generator.build(recipe, Color.WHITE, {}, "Species")
		var legacy_wood := wood_positions(legacy.geometry)
		var legacy_collision := wood_positions(legacy.geometry, true)
		for style in [1, 3]:
			var dressed: Resource = frozen.recipe.duplicate(true)
			dressed.parameters.foliage_style = style
			dressed.parameters.foliage_pattern_strength = 37
			dressed.parameters.foliage_detail = 70
			var built := Generator.build(dressed, Color.WHITE, {}, "Species")
			check(not built.has("error"), "species style builds")
			if built.has("error"): continue
			check(built.structure == frozen.recipe.structure, "dressing preserves complete frozen scaffold")
			check(built.geometry.voxels != legacy.geometry.voxels, "dressing visibly differs from legacy")
			check(wood_positions(built.geometry) == legacy_wood and wood_positions(built.geometry, true) == legacy_collision, "species wood and physical surface unchanged")
			var fresh := dressed.duplicate(true)
			fresh.structure = {}
			var fresh_build := Generator.build(fresh, Color.WHITE, {}, "Species")
			var fresh_frozen := Generator.freeze_structure(fresh)
			var restored_fresh := Generator.build(fresh_frozen.recipe, Color.WHITE, {}, "Species")
			check(fresh_build.geometry.voxels == restored_fresh.geometry.voxels and fresh_build.geometry.palette == restored_fresh.geometry.palette, "fresh/frozen parity for every species and style")
			var alternate := fresh.duplicate(true)
			alternate.seed = 17
			var alternate_build := Generator.build(alternate, Color.WHITE, {}, "Alternate")
			check(not alternate_build.has("error") and alternate_build.structure.lines != fresh_build.structure.lines, "second seed preserves structural variety")
			var extreme := fresh.duplicate(true)
			extreme.parameters.height = 256
			var extreme_build := Generator.build(extreme, Color.WHITE, {}, "Extreme")
			check(not extreme_build.has("error") and extreme_build.geometry.voxels.size() <= Generator.LargeTreeProvider.MAX_STORAGE_CELLS, "256 height remains inside storage budget")
			var contrast := dressed.duplicate(true)
			contrast.parameters.foliage_pattern_strength = 90
			var contrasted := Generator.build(contrast, Color.WHITE, {}, "Species")
			check(contrasted.geometry.voxels == built.geometry.voxels and contrasted.geometry.palette != built.geometry.palette, "contrast changes palette only")
			var bare := dressed.duplicate(true)
			bare.parameters.foliage_amount = 0
			var bare_build := Generator.build(bare, Color.WHITE, {}, "Bare")
			check(bare_build.geometry.voxels.count(4) + bare_build.geometry.voxels.count(5) + bare_build.geometry.voxels.count(6) == 0, "bare tree supported in both modes")
			var id := "species_%d_style_%d" % [kind, style]
			check(ResourceSaver.save(dressed, Creation.recipe_path(id, directory)) == OK, "style recipe saves")
			var reopened: Resource = Creation.load_recipe(id, directory)
			check(reopened.parameters == dressed.parameters and reopened.structure.lines.size() == dressed.structure.lines.size(), "all parameters and structure roundtrip")
			var reopened_build := Generator.build(reopened, Color.WHITE, {}, "Species")
			check(reopened_build.geometry.voxels == built.geometry.voxels and reopened_build.geometry.palette == built.geometry.palette, "serialized recipe reconstructs exact geometry")
			built.geometry.model_id = id
			var contextual := RecipePanel.new()
			root.add_child(contextual)
			contextual.recipe_directory = directory
			check(contextual.open_source(built.geometry), "contextual editor opens each species")
			check(contextual.controls.foliage_style.selected == style and contextual.controls.foliage_pattern_strength.value == 37, "saved style/contrast restored in UI")
			check(contextual.controls.foliage_style.is_item_disabled(2) == (kind != 1), "contextual shoot option restricted")
			contextual.set_parameter("foliage_pattern_strength", 99)
			contextual.undo_parameters()
			contextual.redo_parameters()
			contextual.discard()
			check(contextual.recipe.parameters == dressed.parameters, "contextual Discard restores saved recipe")
			contextual.free()
			if "--capture" in OS.get_cmdline_user_args():
				var prop = EmberVoxelPrefab.prepare_resource(built.geometry).instantiate()
				prop.configure_voxel_scale(built.geometry.normalized_density(), 1.0)
				prop.position = Vector3(float(kind - 2) * 7.0, 0, 0 if style == 1 else 7.0)
				scene.add_child(prop)
				var label := Label3D.new()
				label.text = ["Саванна", "Дуб", "Берёза", "Клён", "Ель"][kind] + (" · пиксель" if style == 1 else " · облака")
				label.position = prop.position + Vector3(0, 5.0, 0)
				label.font_size = 40
				label.pixel_size = 0.015
				label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				scene.add_child(label)
		print("Species ", kind, " pixel/cloud: checked")
	if "--capture" in OS.get_cmdline_user_args():
		panel.hide()
		root.size = Vector2i(1700, 1000)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 22
		camera.position = Vector3(0, 13, 27)
		scene.add_child(camera)
		camera.look_at(Vector3(0, 2, 3.5))
		camera.current = true
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-50, -25, 0)
		scene.add_child(light)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color("202a33")
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.7
		scene.add_child(environment)
		for frame in 20: await process_frame
		var capture := "user://foliage_species_native.png"
		root.get_texture().get_image().save_png(capture)
		print("FOLIAGE_SPECIES_CAPTURE ", ProjectSettings.globalize_path(capture))
	panel.close_session()
	panel.free()
	undo.clear_history()
	undo.free()
	scene.free()
	print("Voxel foliage species: ", "PASS" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)
