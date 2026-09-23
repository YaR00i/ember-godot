@tool
extends EditorPlugin
## Enable only in a disposable Forward+ copy. Authored checkout is never saved.
var errors: Array[String] = []

func _enter_tree() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)

func frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-world-native-"):
		printerr("FAIL NATIVE_WORLD fixture requires a disposable ember-world-native project")
		return
	await frames(15)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: printerr("FAIL NATIVE_WORLD importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec()+90000
	while importer._editor_preparation.visible and Time.get_ticks_msec() < deadline: await frames(1)
	EditorInterface.open_scene_from_path("res://scenes/test_pier.tscn")
	await frames(30)
	EditorInterface.set_main_screen_editor("3D")
	var scene := EditorInterface.get_edited_scene_root()
	var world: Node = importer._world_editor
	world.enabled.button_pressed = true
	check(world.active and world.sidebar.is_visible_in_tree(),"native 3D sidebar missing")
	world.edit_region = Rect2i(19,3,2,2)
	var stroke_start := Time.get_ticks_usec()
	world._create_ground()
	while world.dragging: await frames(1)
	print("NATIVE_WORLD_PROFILE full Pier foundation stroke+frame work=",(Time.get_ticks_usec()-stroke_start)/1000,"ms packed history=",world.last_history_bytes,"bytes")
	var ground: EmberVoxelModelResource = world.entry.resource
	check(ground.voxels.size() == 19660800,"full native Pier was reduced")
	world.category.select(1)
	world._category_changed(1)
	world.palette.select(2)
	world.radius.value = 0.5
	world._begin_stroke({"hit":Vector3i(312,31,56),"normal":Vector3i.UP})
	world.released = true
	while world.dragging: await frames(1)
	var scene_history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	var paint_index: int = world.Model.index_of(Vector3i(312,31,56),ground.grid_size())
	check(ground.voxels[paint_index] == 3,"native paint did not affect surface")
	scene_history.undo()
	check(ground.voxels[paint_index] == 1,"native EditorUndoRedoManager paint Undo")
	scene_history.redo()
	check(ground.voxels[paint_index] == 3,"native EditorUndoRedoManager paint Redo")
	world.category.select(2)
	world._category_changed(2)
	world.water_height.value = 2
	world._begin_stroke({"hit":Vector3i(312,31,56),"normal":Vector3i.UP})
	world.released = true
	while world.dragging: await frames(1)
	world.hide_water.button_pressed = true
	await frames(10)
	var original_water: MeshInstance3D = scene.get_node("Map/Terrain/BayWater/Visual")
	check(original_water.visible,"working view mutated authored visibility")
	world.hide_water.button_pressed = false
	world.open_canvas()
	await frames(3)
	var canvas := EditorInterface.get_editor_main_screen().find_child("EmberSurfaceCanvasWorkspace",true,false)
	check(canvas._resource == ground and canvas.has_unsaved_changes(),"Canvas does not share native world draft")
	EditorInterface.set_main_screen_editor("3D")
	await frames(3)
	check(not canvas.visible,"Canvas forced Save dialog when returning to world")
	var target: EmberVoxelProp = scene.get_node_or_null("Map/Props/placed_ember_surface_pilot")
	if target != null:
		var pose := target.transform
		world.entry = world.sessions.open_object(target,scene)
		check(not world.entry.is_empty(),"native object open: " + world.sessions.error)
		if not world.entry.is_empty():
			var old_voxel: int = world.entry.resource.voxels[0]
			world.actions.apply_stroke(world.entry.resource,{0:{"before":old_voxel,"after":1 if old_voxel == 0 else 0}})
			scene_history.undo()
			check(world.entry.resource.voxels[0] == old_voxel,"native cross-target object Undo")
			scene_history.undo()
			check(ground.surface_fill_levels.is_empty(),"native cross-target water Undo")
			scene_history.redo()
			scene_history.redo()
			var save_start := Time.get_ticks_usec()
			check(world.save_all(),"native common Save: " + world.sessions.error)
			print("NATIVE_WORLD_PROFILE common source+prefab+native scene Save=",(Time.get_ticks_usec()-save_start)/1000,"ms")
			print("NATIVE_WORLD_PROFILE Save breakdown ",world.sessions.last_save_profile)
			check(target.transform == pose and target.model_id != "ember_surface_pilot","unique instance/save transform")
	else: check(world.save_all(),"native ground Save: " + world.sessions.error)
	await frames(30)
	check(original_water.visible,"Save persisted hidden water")
	check(world.sessions.dirty_count(scene) == 0,"native Save left dirty drafts")
	# The native menu/shortcut route must also publish registered Canvas/world drafts.
	var map_entry: Dictionary = world.sessions.open_map(scene.get_node("Map"),scene)
	var before_menu: PackedByteArray = ground.voxels.duplicate()
	ground.voxels[paint_index] = 2
	world.actions.commit_applied_stroke(ground,before_menu,ground.voxels.duplicate(),PackedInt32Array([paint_index]))
	ground.notify_geometry_changed(PackedInt32Array([paint_index]))
	print("NATIVE_WORLD_MENU begin")
	check(EditorInterface.save_scene() == OK,"native menu scene Save failed")
	print("NATIVE_WORLD_MENU returned; pending=",not world.sessions.pending_native_save.is_empty())
	await frames(30)
	check(world.sessions.dirty_count(scene) == 0,"native menu Save did not publish draft")
	var menu_source := ResourceLoader.load(map_entry.path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	check(menu_source.voxels[paint_index] == 2,"native menu Save lost bound Canvas-style stroke")
	var saved := ResourceLoader.load("res://scenes/test_pier.tscn","",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var reopened := saved.instantiate()
	check(reopened.get_node("Map").visual_surface != null,"native scene lost Surface reference")
	check(reopened.get_node("Map").surface_origin == Vector3(0,-32,0),"native scene lost origin")
	check(reopened.get_node("Map/Terrain/BayWater/Visual").visible,"native scene saved working hide state")
	reopened.free()
	world.entry = world.sessions.open_map(scene.get_node("Map"),scene)
	world.target_choice.select(0)
	world._refresh_palette()
	world.category.select(0)
	world._category_changed(0)
	world.hide_water.button_pressed = true
	var projection: Node = scene.get_node("Map")._visual_surface_projection
	while projection.pending_physics_chunk_count() > 0 or projection.pending_chunk_count() > 0: await frames(1)
	check(not projection._collision_chunks.is_empty(),"native draft/new ground collision absent")
	check(scene.get_node("Map/Terrain/StoneQuay/Collision").disabled == false,"existing Pier physics disabled")
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var camera := viewport.get_camera_3d()
	camera.global_position = Vector3(350,95,140)
	camera.look_at(Vector3(312,-2,56))
	world.camera = camera
	world.hover = {"hit":Vector3i(312,31,56),"normal":Vector3i.UP}
	world._update_overlay()
	var navigation := InputEventMouseButton.new()
	navigation.button_index = MOUSE_BUTTON_RIGHT
	navigation.pressed = true
	check(world.forward_input(camera,navigation) == EditorPlugin.AFTER_GUI_INPUT_PASS,"camera RMB intercepted")
	var bracket := InputEventKey.new()
	bracket.pressed = true
	bracket.keycode = KEY_BRACKETRIGHT
	world.radius.get_line_edit().grab_focus()
	var old_radius: float = world.radius.value
	check(world.forward_input(camera,bracket) == EditorPlugin.AFTER_GUI_INPUT_PASS and world.radius.value == old_radius,"text field radius shortcut intercepted")
	world.radius.get_line_edit().release_focus()
	# Exercise native mouse routing and real ray picking, not only direct jobs.
	var ground_frame: Transform3D = world.sessions.frame(world.entry)
	var cursor := camera.unproject_position(ground_frame*(Vector3(312.5,32.001,56.5)/ground.normalized_density()))
	var before_mouse_top: int = world.Model._top_filled_y(ground.voxels,ground.grid_size(),312,56)
	var before_mouse_history := scene_history.get_history_count()
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = cursor
	mouse.pressed = true
	check(world.forward_input(camera,mouse) == EditorPlugin.AFTER_GUI_INPUT_STOP and world.dragging,"native mouse press/ray pick did not start stroke")
	mouse.pressed = false
	world.forward_input(camera,mouse)
	while world.dragging: await frames(1)
	check(world.Model._top_filled_y(ground.voxels,ground.grid_size(),312,56) > before_mouse_top and scene_history.get_history_count() == before_mouse_history+1,"native mouse stroke did not raise terrain in one Undo")
	scene_history.undo()
	check(world.Model._top_filled_y(ground.voxels,ground.grid_size(),312,56) == before_mouse_top and world.sessions.dirty_count(scene) == 0,"native mouse stroke Undo did not restore saved draft")
	await frames(10)
	var screenshot := ProjectSettings.globalize_path("user://native-world-editor.png")
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(screenshot)
	print("NATIVE_WORLD_SCREENSHOT ",screenshot)
	if errors.is_empty(): print("PASS NATIVE_WORLD Forward+ sidebar, full Pier, paint/water, shared Canvas, unique instance, native Save/reopen")
	else:
		for error in errors: printerr("FAIL NATIVE_WORLD ",error)
	await frames(5)
	get_tree().quit(0 if errors.is_empty() else 1)
