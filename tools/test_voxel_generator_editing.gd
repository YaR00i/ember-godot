extends SceneTree

const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Creation = preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")

var failures := 0


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _init() -> void:
	_run.call_deferred()


func wood_positions(source: EmberVoxelModelResource, collision := false) -> Dictionary:
	var positions := {}
	var grid := source.grid_size()
	for index in source.voxels.size():
		var value := source.voxels[index]
		if value < 1 or value > 3 or (collision and source.collision_voxels[index] == 0):
			continue
		var x := index % grid.x
		var z := (index / grid.x) % grid.z
		var y := index / (grid.x * grid.z)
		positions[Vector3i(x - grid.x / 2, y, z - grid.z / 2)] = value
	return positions


func _run() -> void:
	_test_face_winding()
	var recipe := Generator.default_recipe(Generator.LARGE_TREE)
	recipe.seed = 371
	recipe.parameters.height = 64
	var original := Generator.build(recipe, Color.WHITE, {}, "Tree", "editing_tree")
	var frozen := Generator.freeze_structure(recipe)
	check(not frozen.has("error") and recipe.structure.is_empty(), "freeze is detached")
	if frozen.has("error"):
		quit(1)
		return
	var baseline: Resource = frozen.recipe
	var built := Generator.build(baseline, Color.WHITE, {}, "Tree")
	check(not built.has("error"), "fixed skeleton build")
	if built.has("error"):
		quit(1)
		return
	check(wood_positions(built.geometry) == wood_positions(original.geometry), "freezing preserves original wood coordinates")
	check(built.geometry.voxels == original.geometry.voxels, "freezing preserves original complete geometry: grids %s/%s occupied %s/%s" % [built.geometry.grid_size(), original.geometry.grid_size(), built.occupied, original.occupied])
	var expected := wood_positions(built.geometry)
	for entry in [[64, 1], [128, 2], [256, 0]]:
		var boundary := recipe.duplicate(true)
		boundary.parameters.height = entry[0]
		boundary.parameters.crown_shape = entry[1]
		var exact := Generator.build(boundary, Color.WHITE, {}, "Boundary")
		var captured := Generator.freeze_structure(boundary)
		var restored := Generator.build(captured.recipe, Color.WHITE, {}, "Boundary")
		check(not restored.has("error") and restored.geometry.voxels == exact.geometry.voxels, "structure captures exact boundary/crown: " + str(entry))
		check(restored.geometry.validation_errors().is_empty(), "fixed boundary validates")
	var expected_collision := wood_positions(built.geometry, true)
	for entry in [["foliage_color", Color("e08026")], ["cluster_size", 170], ["cluster_flatten", 20], ["canopy_cohesion", 15], ["irregularity", 80], ["foliage_amount", 30], ["foliage_amount", 0]]:
		var changed := baseline.duplicate(true)
		changed.parameters[entry[0]] = entry[1]
		var result := Generator.build(changed, Color.WHITE, {}, "Variant")
		check(not result.has("error"), "foliage parameter builds: " + str(entry[0]))
		if not result.has("error"):
			check(wood_positions(result.geometry) == expected, "foliage must not move wood: " + str(entry[0]))
			check(wood_positions(result.geometry, true) == expected_collision, "foliage must not move collision")
			if entry[0] == "foliage_color":
				check(result.geometry.voxels == built.geometry.voxels, "palette-only season preserves every voxel")
			if entry[0] == "foliage_amount" and entry[1] == 0:
				check(result.geometry.voxels.count(4) + result.geometry.voxels.count(5) + result.geometry.voxels.count(6) == 0, "bare tree is supported")
	var thick := baseline.duplicate(true)
	thick.parameters.branch_thickness = 100
	var thicker := Generator.build(thick, Color.WHITE, {}, "Thick")
	check(not thicker.has("error") and thicker.structure.lines == baseline.structure.lines, "thickness preserves support lines")
	check(wood_positions(thicker.geometry) != expected, "thickness changes wood")
	var invalid := baseline.duplicate(true)
	invalid.structure.lines[0].start = "bad"
	check(not Generator.validation_errors(invalid).is_empty(), "invalid structure rejected")
	var directory := "user://generator_editing_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	check(ResourceSaver.save(baseline, directory.path_join("editing_tree.tres")) == OK, "recipe structure save")
	var reopened := Creation.load_recipe("editing_tree", directory)
	check(reopened != null and reopened.structure.lines.size() == baseline.structure.lines.size(), "structure save/reopen")
	var reopen_build := Generator.build(reopened, Color.WHITE, {}, "Tree")
	check(not reopen_build.has("error") and reopen_build.geometry.voxels == built.geometry.voxels, "reopened recipe rebuilds same voxels")
	var workspace := Workspace.new()
	root.add_child(workspace)
	root.size = Vector2i(1400, 900)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var undo := UndoRedo.new()
	workspace.setup(null, undo)
	workspace.ensure_ui()
	workspace._generator_panel.recipe_directory = directory
	workspace.open_surface(original.geometry, "")
	var panel: VBoxContainer = workspace._generator_panel
	check(not workspace._sidebar_tabs.is_tab_hidden(2), "generated tree opens contextual tab")
	workspace._sidebar_tabs.current_tab = 2
	panel.controls.branch_thickness.value = 40
	check(panel.recipe.parameters.branch_thickness == 40 and panel.recipe.parameters.foliage_amount == 100, "descriptor control edits its own key")
	panel.undo_parameters()
	panel.set_parameter("foliage_amount", 30)
	panel.undo_parameters()
	check(panel.recipe.parameters.foliage_amount == 100, "pending parameter Undo")
	panel.redo_parameters()
	check(panel.recipe.parameters.foliage_amount == 30, "pending parameter Redo")
	var undo_key := InputEventKey.new()
	undo_key.keycode = KEY_Z
	undo_key.pressed = true
	undo_key.ctrl_pressed = true
	workspace._input(undo_key)
	check(panel.recipe.parameters.foliage_amount == 100, "generator routes Ctrl+Z to parameters")
	undo_key.shift_pressed = true
	workspace._input(undo_key)
	check(panel.recipe.parameters.foliage_amount == 30, "generator routes Ctrl+Shift+Z to parameters")
	var scene := Node3D.new()
	root.add_child(scene)
	panel.context = {"root": scene, "parent": scene, "position": Vector3.ZERO, "world_size": 1.0, "undo": undo}
	panel.prepare()
	check(panel.creation != null and workspace._generator_preview != null and not workspace._surface_root.visible, "exact preview in shared viewport")
	check(workspace._resource == original.geometry and not workspace.has_unsaved_changes(), "preview does not change source/draft")
	var yaw_before: float = workspace._yaw
	var orbit := InputEventMouseButton.new()
	orbit.button_index = MOUSE_BUTTON_RIGHT
	orbit.pressed = true
	workspace._on_viewport_input(orbit)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(10, 5)
	workspace._on_viewport_input(motion)
	orbit.pressed = false
	workspace._on_viewport_input(orbit)
	check(workspace._yaw != yaw_before and workspace._generator_preview != null, "camera orbit keeps exact generator preview")
	if "--capture" in OS.get_cmdline_user_args():
		for frame in 15:
			await process_frame
		var image_path := "user://voxel_generator_editing.png"
		root.get_texture().get_image().save_png(image_path)
		print("GENERATOR_EDITING_CAPTURE ", ProjectSettings.globalize_path(image_path))
		var old_pitch: float = workspace._pitch
		workspace._pitch = deg_to_rad(40)
		workspace._update_camera()
		for frame in 6:
			await process_frame
		var bottom_path := "user://voxel_generator_bottom.png"
		root.get_texture().get_image().save_png(bottom_path)
		print("GENERATOR_BOTTOM_CAPTURE ", ProjectSettings.globalize_path(bottom_path))
		workspace._pitch = old_pitch
		workspace._update_camera()
	# The fixture redirects all writes to user:// before committing.
	panel.creation.source_directory = directory.path_join("sources")
	panel.creation.prefab_directory = directory.path_join("prefabs")
	panel.creation.recipe_directory = directory.path_join("recipes")
	var variant_id: String = panel.creation.source.model_id
	var exact_voxels: PackedByteArray = panel.creation.source.voxels.duplicate()
	panel.save_variant()
	check(scene.get_child_count() == 1, "variant placed separately")
	undo.undo()
	check(scene.get_child_count() == 0, "variant placement Undo")
	undo.redo()
	check(scene.get_child_count() == 1, "variant placement Redo")
	var saved_scene := PackedScene.new()
	check(saved_scene.pack(scene) == OK, "variant scene packs")
	check(ResourceSaver.save(saved_scene, directory.path_join("scene.tscn")) == OK, "variant scene saves")
	var scene_resource := ResourceLoader.load(directory.path_join("scene.tscn"), "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var scene_reopened := scene_resource.instantiate()
	check(scene_reopened.get_child_count() == 1 and scene_reopened.get_child(0).model_id == variant_id, "variant scene reopens")
	scene_reopened.free()
	var saved := ResourceLoader.load(directory.path_join("sources/" + variant_id + ".tres"), "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
	check(saved != null and saved.voxels == exact_voxels, "saved variant equals exact preview")
	var saved_recipe := Creation.load_recipe(variant_id, directory.path_join("recipes"))
	check(saved_recipe != null and saved_recipe.parameters.foliage_amount == 30 and saved_recipe.structure.lines.size() == baseline.structure.lines.size(), "saved variant recipe reopens")
	await _test_variations(directory, saved, saved_recipe, scene, undo)
	panel.prepare()
	workspace._sidebar_tabs.current_tab = 0
	check(workspace._generator_preview == null and workspace._surface_root.visible, "leaving tab discards preview")
	check(workspace._canvas_mode == workspace.CanvasMode.BRUSH, "leaving generator restores brush")
	workspace._sidebar_tabs.current_tab = 2
	check(workspace._canvas_mode == workspace.CanvasMode.GENERATOR and workspace._tool.get_selected_items().is_empty(), "generator is an exclusive active tool")
	workspace._return_to_last_brush()
	check(workspace._sidebar_tabs.current_tab == 0, "choosing brush exits generator")
	panel.discard()
	check(panel.recipe.parameters.foliage_amount == 100, "discard restores original recipe")
	var ordinary := original.geometry.duplicate(true) as EmberVoxelModelResource
	ordinary.model_id = "ordinary_fixture"
	workspace.open_surface(ordinary, "")
	check(workspace._sidebar_tabs.is_tab_hidden(2), "ordinary source hides generator")
	undo.clear_history()
	workspace.free()
	scene.free()
	undo.free()
	print("Voxel generator editing: ", "PASS" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)


func _test_face_winding() -> void:
	for normal in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		VoxMesher._append_face_arrays(vertices, normals, colors, indices, Vector3.ZERO, normal, Color.WHITE, 1.0)
		var geometric := (vertices[indices[1]] - vertices[indices[0]]).cross(vertices[indices[2]] - vertices[indices[0]])
		check(geometric.dot(normal) < 0, "Godot clockwise winding points outward: " + str(normal))


func _test_variations(directory: String, saved: EmberVoxelModelResource, saved_recipe: Resource, scene: Node3D, undo: UndoRedo) -> void:
	var recipes := directory.path_join("recipes")
	var base := saved_recipe.duplicate(true)
	base.variation_name = "Основной"
	ResourceSaver.save(base, Creation.recipe_path("editing_tree", recipes))
	var entries: Array[Dictionary] = [
		{"id": "editing_tree", "title": "Tree", "owner": "godot", "ready": true},
		{"id": saved.model_id, "title": saved.display_name, "owner": "godot", "ready": true},
	]
	var grouped := Creation.grouped_entries(entries, recipes)
	check(grouped.size() == 1 and grouped[0].variations.size() == 2, "one card holds named variations")
	check(Creation.variation_name_exists("editing_tree", "новая вариация", "", recipes), "duplicate names are case insensitive")
	check(not Creation.variation_name_exists("editing_tree", saved_recipe.variation_name, saved.model_id, recipes), "selected variation may keep its own name")
	var library := preload("res://addons/ember_import/ember_voxel_object_library_panel.gd").new()
	root.add_child(library)
	library.recipe_directory = recipes
	library._all_entries = grouped
	library._can_place = true
	library._apply_filter(saved.model_id)
	check(library._picker._entries.size() == 1 and library.selected_model_id() == saved.model_id, "library selects child variation under family card")
	var actions := {"placed": "", "edited": ""}
	library.place_requested.connect(func(id: String, _anchor): actions.placed = id)
	library.edit_requested.connect(func(id: String): actions.edited = id)
	library._place_selected()
	library._edit_selected()
	check(actions.placed == saved.model_id and actions.edited == saved.model_id, "placement/edit use concrete selected variation")
	library.free()
	var desired := saved_recipe.duplicate(true)
	desired.parameters.foliage_amount = 80
	var update := Creation.new()
	update.source_directory = directory.path_join("sources")
	update.prefab_directory = directory.path_join("prefabs")
	update.recipe_directory = recipes
	check(update.prepare_recipe(desired, saved.display_name, saved.model_id), "update exact preview")
	var target := scene.get_child(0) as EmberVoxelProp
	var twin := target.duplicate() as EmberVoxelProp
	scene.add_child(twin)
	twin.owner = scene
	var before_mesh: Mesh = target.get_node("Mesh").mesh
	var context := {"root": scene, "undo": undo}
	check(update.update_variation(saved.model_id, context), "shared variation update: " + update.error)
	var source_path := update.source_directory.path_join(saved.model_id + ".tres")
	var updated := ResourceLoader.load(source_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
	check(updated != null and updated.voxels == update.source.voxels, "update saves exact preview under same model ID")
	check(target.get_node("Mesh").mesh != before_mesh and twin.get_node("Mesh").mesh == target.get_node("Mesh").mesh, "all instances of selected variation update")
	undo.undo()
	var restored_recipe := Creation.load_recipe(saved.model_id, recipes)
	var restored_source := ResourceLoader.load(source_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
	check(restored_recipe.parameters.foliage_amount == 30 and restored_source.voxels == saved.voxels and target.get_node("Mesh").mesh == before_mesh, "one Undo restores source/recipe/instances")
	undo.redo()
	check(Creation.load_recipe(saved.model_id, recipes).parameters.foliage_amount == 80, "one Redo restores recipe")
	var standalone := desired.duplicate(true)
	standalone.family_id = ""
	standalone.family_title = "Other tree"
	standalone.variation_name = "Основной"
	var separate := Creation.new()
	check(separate.prepare_recipe(standalone, "Other tree"), "standalone prepares")
	ResourceSaver.save(separate.recipe, Creation.recipe_path(separate.source.model_id, recipes))
	entries.append({"id": separate.source.model_id, "title": "Other tree", "owner": "godot", "ready": true})
	check(Creation.grouped_entries(entries, recipes).size() == 2, "standalone creates a separate card")
	# Fresh preview cannot overwrite persisted manual changes.
	check(update.prepare_recipe(desired, saved.display_name, saved.model_id), "fresh update prepare")
	updated = ResourceLoader.load(source_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
	updated.voxels[0] = 2
	ResourceSaver.save(updated, source_path)
	check(not update.update_variation(saved.model_id, context), "external source change after preview blocks update")
