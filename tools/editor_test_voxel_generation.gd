@tool
extends EditorPlugin
## Opt-in real Godot editor check. Only a disposable copy may enable this file.
var errors: Array[String] = []

func _enter_tree() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value: errors.append(message)

func frames(count := 30) -> void:
	for frame in count: await get_tree().process_frame

func settle() -> void:
	for frame in 600:
		var filesystem := EditorInterface.get_resource_filesystem()
		if not filesystem.is_scanning() and not filesystem.is_importing(): return
		await get_tree().process_frame
	check(false, "filesystem did not settle")

func work(panel: Node) -> void:
	for frame in 600:
		await get_tree().process_frame
		if not panel._busy() and not panel._step_queued: return
	check(false, "generation work did not settle")

func _run() -> void:
	print("GENERATION_NATIVE stage=start")
	if not ProjectSettings.globalize_path("res://").contains("ember-generation-smoke-"):
		push_error("Generation fixture requires a disposable copy")
		return
	await frames(10)
	await settle()
	print("GENERATION_NATIVE stage=ready")
	var scene := Node3D.new()
	scene.name = "GenerationFixture"
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	scene.add_child(light)
	light.owner = scene
	var saved := PackedScene.new()
	check(saved.pack(scene) == OK, "fixture pack")
	check(ResourceSaver.save(saved, "res://scenes/generation_fixture.tscn") == OK, "fixture save")
	scene.free()
	preload("res://addons/ember_import/ember_editor_filesystem.gd").request()
	await frames(30)
	await settle()
	EditorInterface.open_scene_from_path("res://scenes/generation_fixture.tscn")
	await frames(10)
	print("GENERATION_NATIVE stage=scene")
	var create := EditorInterface.get_base_control().find_child("VoxelLibraryNewLargeTree", true, false) as Button
	check(create != null, "real library create button")
	if create == null: get_tree().quit(1); return
	create.pressed.emit()
	await frames(10)
	print("GENERATION_NATIVE stage=panel")
	var panel := EditorInterface.get_base_control().find_child("EmberGenerationWorkspace", true, false)
	check(panel != null, "real native generation panel")
	if panel == null: get_tree().quit(1); return
	if OS.get_cmdline_user_args().has("--oak-crown-only") or OS.get_cmdline_user_args().has("--birch-shape-only") or OS.get_cmdline_user_args().has("--bark-pattern-only") or OS.get_cmdline_user_args().has("--maple-shape-only") or OS.get_cmdline_user_args().has("--savanna-shape-only") or OS.get_cmdline_user_args().has("--spruce-shape-only"):
		var birch := OS.get_cmdline_user_args().has("--birch-shape-only")
		var bark := OS.get_cmdline_user_args().has("--bark-pattern-only")
		var maple := OS.get_cmdline_user_args().has("--maple-shape-only")
		await _check_oak_shapes(panel, birch, bark, maple)
		await frames(15)
		await settle()
		for message in errors: push_error(message)
		print("editor_test_voxel_spruce_shape: " if OS.get_cmdline_user_args().has("--spruce-shape-only") else ("editor_test_voxel_savanna_shape: " if OS.get_cmdline_user_args().has("--savanna-shape-only") else ("editor_test_voxel_maple_shape: " if maple else ("editor_test_voxel_bark_pattern: " if bark else ("editor_test_voxel_birch_shape: " if birch else "editor_test_voxel_oak_crown: ")))), "PASS" if errors.is_empty() else "FAIL")
		get_tree().quit(0 if errors.is_empty() else 1)
		return
	scene = EditorInterface.get_edited_scene_root()
	check(scene.scene_file_path == preload("res://addons/ember_import/ember_voxel_generation_session.gd").STUDIO_PATH, "dedicated native generation scene tab")
	panel.controls.height.value = 64
	panel._count.value = 4
	panel._seed.value = 391
	panel.context.world_size = 1.0
	panel._generate.pressed.emit()
	for frame in 300:
		await get_tree().process_frame
		if not panel.session.running: break
	check(panel.session.candidates.size() == 4, "four exact native candidates")
	print("GENERATION_NATIVE stage=generated count=", panel.session.candidates.size())
	if panel.session.candidates.is_empty(): get_tree().quit(1); return
	var candidate: Dictionary = panel.session.candidates[0]
	panel._select_preview(candidate)
	await frames(10)
	check(EditorInterface.get_selection().get_selected_nodes().has(candidate.node), "native preview centered pivot selection")
	var other: Dictionary = panel.session.candidates[1]
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(other.node)
	await frames(3)
	check(panel.active_id == str(other.creation.source.model_id), "native 3D selection routes to individual editor")
	panel._select_preview(candidate)
	panel.candidate_controls.foliage_amount.value = 70
	check(panel._draft_dirty(), "native individual draft")
	EditorInterface.open_scene_from_path("res://scenes/generation_fixture.tscn")
	await frames(10)
	check(panel.suspended and panel.session.candidates.size() == 4 and panel._draft_dirty(), "map tab retains gallery and draft")
	check(EditorInterface.get_edited_scene_root().get_child_count() == 1, "generation objects never attached to map")
	panel.studio_requested.emit()
	await frames(10)
	check(not panel.suspended and panel._draft_dirty(), "return to generation tab restores draft")
	panel._apply.pressed.emit()
	check(candidate.creation.recipe.parameters.foliage_amount == 70, "native individual apply")
	panel._show_solo()
	check(candidate.node.visible and not other.node.visible, "native solo view")
	panel._select_all_previews()
	var old_voxels: PackedByteArray = other.creation.source.voxels.duplicate()
	var old_palette: PackedColorArray = other.creation.source.palette.duplicate()
	panel._choose(candidate, true)
	panel._generate.pressed.emit()
	await work(panel)
	check(panel.session.candidates.size() == 8 and panel.session.preview_ids.size() == 4, "two batches retain all eight records")
	check(candidate.chosen and other.creation.packed == null, "favorites independent of unloaded archive")
	panel._select_preview(other)
	check(other.creation.source.voxels == old_voxels and other.creation.source.palette == old_palette,
		"old native candidate restored exactly")
	var new_candidate: Dictionary = panel.session.candidates[4]
	panel._compare_candidate(new_candidate, true)
	await work(panel)
	check(panel.session.preview_ids.size() == 2, "native comparison spans batches")
	panel._history_filter_code = 2
	panel._rebuild_candidates()
	check(panel._candidates.get_child_count() == 4, "native batch filter")
	panel._history_filter_code = 0
	panel._rebuild_candidates()
	panel._select_all_previews()
	panel.request_close()
	var close_dialog: ConfirmationDialog
	for child in panel.get_children():
		if child is ConfirmationDialog: close_dialog = child
	check(close_dialog != null, "unsaved collection close asks confirmation")
	if close_dialog != null: close_dialog.get_cancel_button().pressed.emit()
	await frames(3)
	check(panel.session.candidates.size() == 8, "cancel collection close retains all history")
	# Exercise the editor's actual focus shortcut without moving the user's camera.
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var container: Node = viewport.get_parent()
	while container != null and not container.is_class("Node3DEditorViewport"):
		container = container.get_parent()
	if container is Control:
		var motion := InputEventMouseMotion.new()
		motion.position = container.get_global_rect().get_center()
		motion.global_position = motion.position
		EditorInterface.get_base_control().get_viewport().push_input(motion)
		var click := InputEventMouseButton.new()
		click.position = motion.position
		click.global_position = motion.position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		EditorInterface.get_base_control().get_viewport().push_input(click)
		click = click.duplicate()
		click.pressed = false
		EditorInterface.get_base_control().get_viewport().push_input(click)
		panel._select_all_previews()
		var event := InputEventKey.new()
		event.keycode = KEY_F
		event.physical_keycode = KEY_F
		event.pressed = true
		EditorInterface.get_base_control().get_viewport().push_input(event)
		event = event.duplicate()
		event.pressed = false
		EditorInterface.get_base_control().get_viewport().push_input(event)
		# Native F does not fit bounds. Use actual wheel navigation to fit the
		# gallery even when this disposable scene's previous camera was saved.
		var bounds := AABB()
		var first_bounds := true
		for item in panel.session.preview_candidates():
			for mesh in item.node.get_children():
				if not mesh is MeshInstance3D: continue
				var mesh_bounds: AABB = mesh.global_transform * mesh.get_aabb()
				bounds = mesh_bounds if first_bounds else bounds.merge(mesh_bounds)
				first_bounds = false
		var target_distance := maxf(4.0, bounds.size.length() * 1.2)
		await frames(3)
		for step in 160:
			var camera := viewport.get_camera_3d()
			var distance := camera.global_position.distance_to(bounds.get_center())
			if distance > target_distance * 0.85 and distance < target_distance * 1.15: break
			var wheel := InputEventMouseButton.new()
			wheel.position = motion.position
			wheel.global_position = motion.position
			wheel.button_index = MOUSE_BUTTON_WHEEL_UP if distance > target_distance else MOUSE_BUTTON_WHEEL_DOWN
			wheel.pressed = true
			EditorInterface.get_base_control().get_viewport().push_input(wheel)
			await frames(2)
	await frames(30)
	var capture := "user://generation_native.png"
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(capture)
	print("GENERATION_NATIVE_CAPTURE ", ProjectSettings.globalize_path(capture))
	panel._choose(candidate, true)
	panel._save.pressed.emit()
	await work(panel)
	print("GENERATION_NATIVE stage=saved")
	check(candidate.saved, "native candidate published")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo()
	check(not candidate.saved, "native asset-only Undo")
	await frames(30)
	await settle()
	history.redo()
	check(candidate.saved, "native asset-only Redo")
	await frames(30)
	await settle()
	panel._preset_name.text = "Native Autumn %d" % Time.get_ticks_usec()
	panel._save_preset()
	print("GENERATION_NATIVE stage=preset")
	check(not panel.presets.list_presets("large_tree").is_empty(), "native preset saved/reopened")
	await frames(45)
	await settle()
	check(EditorInterface.save_scene() == OK, "save map during temporary preview")
	var reopened: Node = ResourceLoader.load(scene.scene_file_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP).instantiate()
	check(reopened.get_child_count() == 3 and reopened.find_child("EmberGenerationPreview", true, false) == null, "temporary preview not serialized in studio")
	reopened.free()
	var id: String = candidate.creation.source.model_id
	panel.edit_requested.emit(id)
	print("GENERATION_NATIVE stage=edit")
	await frames(45)
	var canvas := EditorInterface.get_editor_main_screen().find_child("EmberSurfaceCanvasWorkspace", true, false)
	check(canvas != null and canvas.visible, "saved candidate opens existing Canvas")
	panel.close_session()
	check(scene.get_child_count() == 3, "native discard temporary nodes")
	var library := EditorInterface.get_base_control().find_child("VoxelObjectLibrary", true, false)
	if library == null:
		# The panel's class is stable even when its historical Node name differs.
		library = _find_library(EditorInterface.get_base_control())
	check(library != null, "library panel for reuse")
	if library != null:
		library.refresh(id)
		library._more_button.get_popup().id_pressed.emit(3)
		await frames(10)
		check(panel.recipe.structure.is_empty() and panel.recipe.parameters.height == 64,
			"generate-similar reuses parameters, not skeleton")
		panel.close_session()
	await _check_tree_types(panel)
	await frames(30)
	await settle()
	for message in errors: push_error(message)
	print("editor_test_voxel_generation: ", "PASS" if errors.is_empty() else "FAIL")
	# This opt-in disposable fixture has already saved/reopened the required
	# assets; do not leave a native unsaved-tab confirmation holding the run open.
	get_tree().quit(0 if errors.is_empty() else 1)

func _check_tree_types(panel: Node) -> void:
	panel.studio_requested.emit()
	await frames(10)
	panel._title.text = "Native tree types"
	panel._count.value = 1
	var registry := preload("res://addons/ember_import/ember_voxel_generator.gd")
	var types := registry.creation_presets("large_tree")
	for kind in 4:
		panel._apply_recipe(types[kind].recipe)
		panel.controls.height.value = 64
		panel._seed.value = 391
		panel.context.world_size = 1.0
		panel._generate.pressed.emit()
		await work(panel)
	check(panel.session.candidates.size() == 4, "four distinct type records in native workshop")
	if panel.session.candidates.size() != 4: return
	for kind in 3:
		panel._compare_candidate(panel.session.candidates[kind], true)
		await work(panel)
	var oak: Dictionary = panel.session.candidates[1]
	panel._select_preview(oak)
	check(panel.candidate_controls.has("foliage_along"), "typed tree has shared interior foliage editing field")
	if panel.candidate_controls.has("foliage_along"):
		var original_amount: int = oak.creation.recipe.parameters.foliage_along
		panel.candidate_controls.foliage_along.value = 25
		panel._apply.pressed.emit()
		check(oak.creation.recipe.parameters.foliage_along == 25, "native interior foliage Apply")
		panel.undo_local()
		check(oak.creation.recipe.parameters.foliage_along == original_amount, "native interior foliage geometry Undo")
		panel.redo_local()
		check(oak.creation.recipe.parameters.foliage_along == 25, "native interior foliage geometry Redo")
	panel._select_all_previews()
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var container: Node = viewport.get_parent()
	while container != null and not container.is_class("Node3DEditorViewport"): container = container.get_parent()
	if container is Control:
		var motion := InputEventMouseMotion.new()
		motion.position = container.get_global_rect().get_center()
		motion.global_position = motion.position
		EditorInterface.get_base_control().get_viewport().push_input(motion)
		container.focus_mode = Control.FOCUS_ALL
		container.grab_focus()
		for pressed in [true, false]:
			var focus := InputEventKey.new()
			focus.keycode = KEY_F
			focus.physical_keycode = KEY_F
			focus.pressed = pressed
			EditorInterface.get_base_control().get_viewport().push_input(focus)
		await frames(3)
		var bounds := AABB()
		var first := true
		for item in panel.session.preview_candidates():
			for mesh in item.node.get_children():
				if not mesh is MeshInstance3D: continue
				var box: AABB = mesh.global_transform * mesh.get_aabb()
				bounds = box if first else bounds.merge(box)
				first = false
		var target := maxf(4.0, bounds.size.length() * 0.8)
		for step in 160:
			var distance := viewport.get_camera_3d().global_position.distance_to(bounds.get_center())
			if distance > target * 0.85 and distance < target * 1.15: break
			var wheel := InputEventMouseButton.new()
			wheel.position = motion.position
			wheel.global_position = motion.position
			wheel.button_index = MOUSE_BUTTON_WHEEL_UP if distance > target else MOUSE_BUTTON_WHEEL_DOWN
			wheel.pressed = true
			EditorInterface.get_base_control().get_viewport().push_input(wheel)
			await frames(2)
	await frames(15)
	var capture := "user://generation_types_native.png"
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(capture)
	print("GENERATION_TYPES_NATIVE_CAPTURE ", ProjectSettings.globalize_path(capture))
	panel._choose(oak, true)
	panel._save.pressed.emit()
	await work(panel)
	check(oak.saved, "typed object saved to existing library")
	var stored := preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd").load_recipe(oak.creation.source.model_id)
	check(stored != null and stored.parameters.tree_type == 1 and stored.parameters.foliage_along == 25, "typed concrete recipe reopens")
	panel.close_session()

func _check_oak_shapes(panel: Node, birch := false, bark := false, maple := false) -> void:
	var savanna := OS.get_cmdline_user_args().has("--savanna-shape-only")
	var spruce := OS.get_cmdline_user_args().has("--spruce-shape-only")
	panel.studio_requested.emit()
	await frames(10)
	var registry := preload("res://addons/ember_import/ember_voxel_generator.gd")
	check(panel.controls.tree_type.item_count == 5, "all five tree types directly accessible")
	var oak: Resource = registry.creation_presets("large_tree")[4 if spruce else (0 if savanna else (3 if maple else (2 if birch else 1)))].recipe
	var revision := 10 if spruce else (9 if savanna else (7 if maple else (5 if birch else 8)))
	panel._title.text = "Native birch shape" if birch else "Native oak crown"
	if maple: panel._title.text = "Native maple shape"
	if savanna: panel._title.text = "Native savanna shape"
	if spruce: panel._title.text = "Native spruce shape"
	panel._count.value = 1
	var entry := 0
	var configurations := [[3, 391, 100], [revision, 391, 100], [revision, 391, 0], [revision, 17, 100]]
	if spruce: configurations = [[10, 371, 100], [10, 391, 100], [10, 391, 0], [10, 17, 100]]
	for config in configurations:
		var recipe := oak.duplicate(true)
		if birch and config[0] == 3:
			recipe.parameters.merge({"trunk_width": 10, "crown_spread": 65, "branch_thickness": 45, "branch_taper": 60, "cluster_flatten": 60, "foliage_along": 40, "root_flare": 65}, true)
		if maple and config[0] == 3:
			recipe.parameters.merge({"generation_version": 6, "cluster_size": 130, "branch_start": 36}, true)
		if not birch and not maple and not bark and not savanna and not spruce and config[0] == 3:
			recipe.parameters.merge({"generation_version": 4, "trunk_width": 10, "crown_spread": 65, "branch_curve": 55, "branch_taper": 60, "cluster_size": 130, "branch_start": 32, "foliage_along": 85, "root_flare": 65}, true)
		if config[0] != 3 or birch or bark: recipe.parameters.generation_version = config[0]
		if savanna and config[0] == 3:
			recipe.parameters = registry.normalized_parameters("large_tree", registry.LargeTreeProvider.defaults())
			recipe.parameters.generation_version = 2
		recipe.parameters.height = 96
		recipe.parameters.foliage_amount = config[2]
		if bark:
			var scattered := OS.get_cmdline_user_args().has("--scattered-bark")
			recipe = registry.creation_presets("large_tree")[[2, 2, 2, 1][entry] if scattered else [2, 1, 2, 1][entry]].recipe.duplicate(true)
			recipe.parameters.height = 96
			recipe.parameters.foliage_amount = 0
			if scattered:
				recipe.parameters.bark_pattern_version = 1 if entry == 0 else 2
			if entry == 2 and not scattered:
				recipe.parameters.bark_pattern_direction = 2
				recipe.parameters.bark_pattern_color = Color("912d46")
			if entry == 3 and not scattered: recipe.parameters.bark_pattern = false
			panel._title.text = "Native bark pattern"
		entry += 1
		panel._apply_recipe(recipe)
		panel._seed.value = config[1]
		if bark and OS.get_cmdline_user_args().has("--scattered-bark"):
			panel._seed.value = [391, 391, 17, 371][entry - 1]
		panel.context.world_size = 1.0
		panel._generate.pressed.emit()
		await work(panel)
	check(panel.session.candidates.size() == 4, "old/new/bare/second-seed native oak records")
	if panel.session.candidates.size() != 4: return
	for index in 3:
		panel._compare_candidate(panel.session.candidates[index], true)
		await work(panel)
	var candidate: Dictionary = panel.session.candidates[1]
	panel._select_preview(candidate)
	var voxels: PackedByteArray = candidate.creation.source.voxels.duplicate()
	check(panel.candidate_controls.has("foliage_along"), "native crown interior foliage control exists")
	if not panel.candidate_controls.has("foliage_along"): return
	panel.candidate_controls.foliage_along.value = 30
	panel._apply.pressed.emit()
	check(candidate.creation.recipe.parameters.foliage_along == 30, "native oak canopy Apply")
	panel.undo_local()
	check(candidate.creation.source.voxels == voxels, "native oak canopy Undo restores full exact geometry")
	panel.redo_local()
	panel.undo_local()
	if bark:
		check(panel.candidate_controls.bark_pattern is CheckButton and panel.candidate_controls.bark_pattern_direction is OptionButton, "native bool/choice editing descriptors")
		panel.candidate_controls.bark_pattern.button_pressed = false
		panel._apply.pressed.emit()
		check(not candidate.creation.recipe.parameters.bark_pattern, "native bark toggle Apply")
		panel.undo_local()
		check(candidate.creation.source.voxels == voxels and panel.candidate_controls.bark_pattern.button_pressed, "native bark toggle Undo exact and control synced")
		panel.candidate_controls.bark_pattern_direction.item_selected.emit(2)
		panel.candidate_controls.bark_pattern_color.color_changed.emit(Color("af3154"))
		panel.candidate_controls.bark_pattern_length.value = 20
		panel._apply.pressed.emit()
		check(candidate.creation.recipe.parameters.bark_pattern_direction == 2 and candidate.creation.source.palette[7] == Color("af3154"), "native direction/colour/length Apply")
		panel.undo_local()
		check(candidate.creation.source.voxels == voxels, "native bark styling Undo exact")
	panel._select_all_previews()
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var container: Node = viewport.get_parent()
	while container != null and not container.is_class("Node3DEditorViewport"): container = container.get_parent()
	if container is Control:
		var motion := InputEventMouseMotion.new()
		motion.position = container.get_global_rect().get_center()
		motion.global_position = motion.position
		EditorInterface.get_base_control().get_viewport().push_input(motion)
		container.focus_mode = Control.FOCUS_ALL
		container.grab_focus()
		for pressed in [true, false]:
			var focus := InputEventKey.new()
			focus.keycode = KEY_F
			focus.physical_keycode = KEY_F
			focus.pressed = pressed
			EditorInterface.get_base_control().get_viewport().push_input(focus)
		await frames(3)
		var bounds := AABB()
		var first := true
		for item in panel.session.preview_candidates():
			for mesh in item.node.get_children():
				if not mesh is MeshInstance3D: continue
				var box: AABB = mesh.global_transform * mesh.get_aabb()
				bounds = box if first else bounds.merge(box)
				first = false
		var target := maxf(4.0, bounds.size.length() * 0.70)
		for step in 120:
			var distance := viewport.get_camera_3d().global_position.distance_to(bounds.get_center())
			if distance > target * 0.85 and distance < target * 1.15: break
			var wheel := InputEventMouseButton.new()
			wheel.position = motion.position
			wheel.global_position = motion.position
			wheel.button_index = MOUSE_BUTTON_WHEEL_UP if distance > target else MOUSE_BUTTON_WHEEL_DOWN
			wheel.pressed = true
			EditorInterface.get_base_control().get_viewport().push_input(wheel)
			await frames(2)
	await frames(15)
	var capture := "user://generation_bark_pattern_native.png" if bark else ("user://generation_birch_shape_native.png" if birch else "user://generation_oak_crown_native.png")
	if maple: capture = "user://generation_maple_upright_native.png"
	if savanna: capture = "user://generation_savanna_native.png"
	if spruce: capture = "user://generation_spruce_native.png"
	if bark and OS.get_cmdline_user_args().has("--scattered-bark"): capture = "user://generation_bark_scattered_native.png"
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(capture)
	print("GENERATION_OAK_NATIVE_CAPTURE ", ProjectSettings.globalize_path(capture))
	if (maple or (not birch and not bark)) and container is Control:
		panel._select_preview(candidate)
		panel._show_solo()
		var node: Node3D = candidate.node
		var original := node.position
		var box := AABB()
		var first := true
		for mesh in node.get_children():
			if not mesh is MeshInstance3D: continue
			var bounds: AABB = mesh.global_transform * mesh.get_aabb()
			box = bounds if first else box.merge(bounds)
			first = false
		node.position -= box.get_center()
		for key in [KEY_KP_1, KEY_KP_3]:
			var motion := InputEventMouseMotion.new()
			motion.position = container.get_global_rect().get_center()
			motion.global_position = motion.position
			EditorInterface.get_base_control().get_viewport().push_input(motion)
			container.grab_focus()
			var direction := "спереди" if key == KEY_KP_1 else "справа"
			var selected_view := false
			var pending: Array[Node] = [container]
			var popups: Array[PopupMenu] = []
			while not pending.is_empty():
				var control: Node = pending.pop_back()
				for child in control.get_children(true): pending.append(child)
				if control is PopupMenu: popups.append(control)
			for popup in popups:
				for index in popup.item_count:
					var text := popup.get_item_text(index).to_lower()
					if text.contains(direction) or text.contains("front" if key == KEY_KP_1 else "right"):
						popup.id_pressed.emit(popup.get_item_id(index))
						selected_view = true
						break
				if selected_view: break
			print("GENERATION_MAPLE_NATIVE_VIEW ", direction, " menu=", selected_view)
			check(selected_view, "native front/right camera menu is available")
			for pressed in [true, false]:
				var view := InputEventKey.new()
				view.keycode = key
				view.physical_keycode = key
				view.pressed = pressed
				EditorInterface.get_base_control().get_viewport().push_input(view)
			await frames(4)
			for step in 45:
				var camera := viewport.get_camera_3d()
				var current := camera.size if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else camera.global_position.length()
				var target := box.size.y * (1.9 if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else 1.6)
				if current > target * 0.85 and current < target * 1.15: break
				var wheel := InputEventMouseButton.new()
				wheel.position = motion.position
				wheel.global_position = wheel.position
				wheel.button_index = MOUSE_BUTTON_WHEEL_UP if current > target else MOUSE_BUTTON_WHEEL_DOWN
				wheel.pressed = true
				EditorInterface.get_base_control().get_viewport().push_input(wheel)
				await frames(2)
			await frames(10)
			var detail := "user://generation_%s_%s.png" % ["spruce" if spruce else ("savanna" if savanna else ("maple" if maple else "oak_mature")), "front" if key == KEY_KP_1 else "side"]
			EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(detail)
			print("GENERATION_MAPLE_VIEW_CAPTURE ", ProjectSettings.globalize_path(detail))
		node.position = original
	if bark and OS.get_cmdline_user_args().has("--scattered-bark") and container is Control:
		for index in 3:
			panel._select_preview(panel.session.candidates[index])
			panel._show_solo()
			var node: Node3D = panel.session.candidates[index].node
			var original := node.position
			var box := AABB()
			var first := true
			for mesh in node.get_children():
				if not mesh is MeshInstance3D: continue
				var bounds: AABB = mesh.global_transform * mesh.get_aabb()
				box = bounds if first else box.merge(bounds)
				first = false
			# Temporary fixture presentation only: the editor's pivot is at origin.
			# Return the candidate placement before publication checks.
			node.position -= box.get_center()
			box.position -= box.get_center()
			container.grab_focus()
			for pressed in [true, false]:
				var focus := InputEventKey.new()
				focus.keycode = KEY_F
				focus.physical_keycode = KEY_F
				focus.pressed = pressed
				EditorInterface.get_base_control().get_viewport().push_input(focus)
			await frames(4)
			for step in 120:
				var distance := viewport.get_camera_3d().global_position.distance_to(box.get_center())
				if distance < box.size.y * 0.30: break
				var wheel := InputEventMouseButton.new()
				wheel.position = container.get_global_rect().get_center()
				wheel.global_position = wheel.position
				wheel.button_index = MOUSE_BUTTON_WHEEL_UP
				wheel.pressed = true
				EditorInterface.get_base_control().get_viewport().push_input(wheel)
				await frames(2)
			await frames(10)
			var detail := "user://generation_bark_detail_%d.png" % (index + 1)
			EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(detail)
			print("GENERATION_BARK_DETAIL_CAPTURE ", ProjectSettings.globalize_path(detail))
			node.position = original
	panel._choose(candidate, true)
	panel._save.pressed.emit()
	await work(panel)
	check(candidate.saved, "native crown oak library publication")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(EditorInterface.get_edited_scene_root()))
	history.undo()
	check(not candidate.saved, "native crown oak publication Undo")
	await frames(15)
	await settle()
	history.redo()
	check(candidate.saved, "native crown oak publication Redo")
	var creation := preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
	var stored := creation.load_recipe(candidate.creation.source.model_id)
	check(stored != null and stored.parameters.generation_version == candidate.creation.recipe.parameters.generation_version, "native tree Recipe reopens with same revision")
	panel.close_session()

func _find_library(node: Node) -> Node:
	if node is EmberVoxelObjectLibraryPanel: return node
	for child in node.get_children():
		var found := _find_library(child)
		if found != null: return found
	return null
