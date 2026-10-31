extends SceneTree
## Focused authoring/save gate; disposable mixed-test project only.
const Creation = preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
const RecipePanel = preload("res://addons/ember_import/ember_voxel_generator_panel.gd")
const GenerationPanel = preload("res://addons/ember_import/ember_voxel_generation_panel.gd")
const Surface = preload("res://scripts/ember_tree_surface.gd")
const Provider = preload("res://addons/ember_import/ember_voxel_large_tree_generator.gd")
var errors: Array[String] = []
func _init() -> void:
	if not FileAccess.file_exists("res://.mixed-editor-test-sandbox"):
		printerr("Disposable test project required"); quit(2); return
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: errors.append(message); push_error(message)
func material(node: Node) -> ShaderMaterial:
	return node.get_node("Mesh").mesh.surface_get_material(1)
func _run() -> void:
	var recipe: Resource = load("res://content/editor/voxel_generators/vox_painted_maple.tres")
	var original: EmberVoxelModelResource = load("res://content/voxel_models/vox_painted_maple.tres")
	check(Surface.settings_errors(original.tree_surface.settings).is_empty(), "old Source no longer validates")
	var normalized := Provider.normalize(recipe.parameters)
	check(normalized.tree_leaf_palette_strength == 0, "old recipe opted into new colouring")
	var baseline := Surface.build(original.to_definition().model)
	check(float(baseline.surface_get_material(1).get_shader_parameter("painted_leaf_palette_strength")) == 0.0, "old colour mode changed")
	for bad in [{"tree_leaf_secondary_color":Color(NAN,0,0)}, {"tree_leaf_palette_strength":101}, {"tree_leaf_palette_strength":NAN}]:
		var settings: Dictionary = normalized.duplicate(true); settings.merge(bad, true)
		check(not Surface.settings_errors(settings).is_empty(), "invalid colour data accepted")
	var holder := Node3D.new(); holder.name = "PaletteAuthoringFixture"; root.add_child(holder); current_scene = holder
	var history := UndoRedo.new()
	var directory := "user://tree-leaf-palette-%d" % OS.get_process_id()
	var creation := Creation.new(); creation.source_directory = directory.path_join("sources"); creation.prefab_directory = directory.path_join("prefabs"); creation.recipe_directory = directory.path_join("recipes")
	check(creation.prepare_recipe(recipe, "Palette fixture", "", "palette_fixture"), "old recipe preparation")
	check(creation.source.voxels == original.voxels, "default preparation changed geometry")
	check(creation.save_to_library(holder, history), "fixture publication")
	var source_path := creation.source_directory.path_join("palette_fixture.tres")
	var prop := creation.packed.instantiate(); holder.add_child(prop); prop.owner = holder
	var collision: PackedVector3Array = prop.get_node("Collision/Shape").shape.get_faces()
	var canvas := CanvasLayer.new(); holder.add_child(canvas)
	var scroll := ScrollContainer.new(); scroll.size = Vector2(390,800); canvas.add_child(scroll)
	var panel := RecipePanel.new(); panel.custom_minimum_size.x = 360; scroll.add_child(panel)
	panel.recipe_directory = creation.recipe_directory
	var context := {"root":holder,"parent":holder,"undo":history,"world_size":16.0,"position":Vector3.ZERO,"source_directory":creation.source_directory,"prefab_directory":creation.prefab_directory}
	check(panel.open_source(creation.source,context), "ordinary generator panel opens old recipe")
	check(panel.controls.has("tree_leaf_secondary_color") and panel.controls.has("tree_leaf_palette_strength"), "colour controls absent")
	panel._save_mode.select(1); panel._save_mode_changed(1)
	panel.controls.foliage_color.color_changed.emit(Color("c7a15c"))
	panel.controls.tree_leaf_secondary_color.color_changed.emit(Color("9a683c"))
	panel.controls.tree_leaf_palette_strength.value = 100
	check(panel.creation == null, "colour input remeshed without preview")
	panel.undo_parameters(); check(panel.recipe.parameters.tree_leaf_palette_strength == 0, "colour Undo")
	panel.redo_parameters(); check(panel.recipe.parameters.tree_leaf_palette_strength == 100, "colour Redo")
	panel.prepare(); check(panel.creation != null, "colour preview failed")
	if panel.creation == null: quit(1); return
	var preview: Node = panel.creation.packed.instantiate()
	check(panel.creation.source.voxels == original.voxels, "colour changed occupancy")
	check(preview.get_node("Collision/Shape").shape.get_faces() == collision, "colour changed collision")
	check(preview.get_node("Mesh").mesh.surface_get_arrays(1) == baseline.surface_get_arrays(1), "colour changed sprig geometry/UV")
	check(material(preview).get_shader_parameter("painted_leaf_palette_primary") == Color("c7a15c"), "primary colour missing in preview")
	check(material(preview).get_shader_parameter("painted_leaf_palette_secondary") == Color("9a683c"), "secondary colour missing in preview")
	check(panel.save_variant(), "ordinary update failed: " + panel._info.text)
	check(float(material(prop).get_shader_parameter("painted_leaf_palette_strength")) == 1.0, "placed tree did not update")
	history.undo(); check(float(material(prop).get_shader_parameter("painted_leaf_palette_strength")) == 0.0, "scene Undo colours")
	history.redo(); check(float(material(prop).get_shader_parameter("painted_leaf_palette_strength")) == 1.0, "scene Redo colours")
	var saved: EmberVoxelModelResource = ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(saved.validation_errors().is_empty() and saved.tree_surface.settings.tree_leaf_palette_strength == 100, "Source save/reopen")
	var reopened_recipe: Resource = Creation.load_recipe("palette_fixture",creation.recipe_directory)
	check(reopened_recipe.parameters.tree_leaf_secondary_color == Color("9a683c"), "recipe lost colour")
	var packed := PackedScene.new(); packed.pack(holder)
	check(ResourceSaver.save(packed,directory.path_join("map.tscn")) == OK, "scene save")
	var reopened: Node = load(directory.path_join("map.tscn")).instantiate()
	check(material(reopened.get_child(0)).get_shader_parameter("painted_leaf_palette_secondary") == material(preview).get_shader_parameter("painted_leaf_palette_secondary"), "scene differs from preview")
	reopened.free(); preview.free()
	check(panel.open_source(saved,context), "reopen generator")
	panel.controls.tree_leaf_palette_strength.value = 25; panel.discard()
	check(panel.recipe.parameters.tree_leaf_palette_strength == 100 and panel.creation == null, "discard lost saved palette")
	var authoring := GenerationPanel.new(); root.add_child(authoring)
	authoring._change_parameter("tree_type",3)
	check(authoring.controls.has("tree_leaf_secondary_color") and authoring.controls.has("tree_leaf_palette_strength"), "new-tree creation has no palette controls")
	authoring.free()
	var output := OS.get_environment("EMBER_TREE_PALETTE_CAPTURE_DIR")
	if not output.is_empty():
		var camera := Camera3D.new(); holder.add_child(camera); camera.position = Vector3(125,100,175); camera.look_at(Vector3(0,48,0)); camera.current = true
		var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-55,-30,0); holder.add_child(sun)
		var world := WorldEnvironment.new(); world.environment = Environment.new(); world.environment.background_mode = Environment.BG_COLOR; world.environment.background_color = Color(0.52,0.65,0.75); world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; world.environment.ambient_light_color = Color.WHITE; world.environment.ambient_light_energy = 0.4; holder.add_child(world)
		for i in 8: await process_frame
		var fields_scroll := panel._fields.get_parent() as ScrollContainer
		fields_scroll.scroll_vertical += int(panel.controls.foliage_color.global_position.y - fields_scroll.global_position.y) - 48
		await process_frame; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("generator-palette.png"))
	history.clear_history(); history.free(); creation = null; holder.queue_free()
	await process_frame; await process_frame
	print("PASS tree leaf palette: legacy mode, validation, real colour controls/no input remesh, local/scene Undo/Redo, preview/update, Source/recipe/map save/reopen/discard, unchanged sprigs/collision" if errors.is_empty() else "FAIL tree leaf palette")
	quit(0 if errors.is_empty() else 1)
