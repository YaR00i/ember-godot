@tool
extends EditorPlugin
## Installed only in a disposable ember-canvas-smoke-walk-panel-* project.
const Surface = preload("res://addons/ember_import/ember_walk_surface.gd")
const Mask = preload("res://addons/ember_import/ember_walk_surface_mask.gd")
var errors: Array[String] = []


func _enter_tree() -> void:
	print("WALK_PANEL_EDITOR fixture attached")
	_run.call_deferred()


func frames(count: int) -> void:
	for frame in count:
		await get_tree().process_frame


func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)


func capture(label: String) -> void:
	await frames(10)
	RenderingServer.force_draw(false)
	var path := "user://walk-panel-editor-%s.png" % label
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(path)
	print("WALK_PANEL_CAPTURE ", ProjectSettings.globalize_path(path))


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-canvas-smoke-walk-panel-"):
		push_error("Walk panel fixture requires disposable project")
		return
	print("WALK_PANEL_EDITOR starting")
	await frames(10)
	var draft := Node3D.new()
	draft.name = "WalkPanelFixture"
	var bridge := Node3D.new()
	bridge.name = "Bridge"
	draft.add_child(bridge)
	bridge.owner = draft
	for index in 8:
		var board := MeshInstance3D.new()
		board.name = "Board%d" % index
		var mesh := BoxMesh.new()
		mesh.size = Vector3(9, 1, 20)
		board.mesh = mesh
		board.position = Vector3(-35 + index * 10, 0.5, 0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("c18b50")
		board.material_override = material
		bridge.add_child(board)
		board.owner = draft
	var packed := PackedScene.new()
	packed.pack(draft)
	var path := "res://scenes/__walk_panel_fixture.tscn"
	if not FileAccess.file_exists(path):
		ResourceSaver.save(packed, path)
	draft.free()
	if EditorInterface.get_edited_scene_root() == null or EditorInterface.get_edited_scene_root().scene_file_path != path:
		EditorInterface.get_resource_filesystem().scan()
	print("WALK_PANEL_EDITOR fixture saved")
	await frames(30)
	if EditorInterface.get_edited_scene_root() == null or EditorInterface.get_edited_scene_root().scene_file_path != path:
		EditorInterface.open_scene_from_path(path)
	print("WALK_PANEL_EDITOR open requested")
	EditorInterface.set_main_screen_editor("3D")
	await frames(30)
	var scene := EditorInterface.get_edited_scene_root() as Node3D
	if scene == null or scene.scene_file_path != path:
		push_error("Walk panel fixture could not activate scene")
		get_tree().quit(1)
		return
	bridge = scene.get_node("Bridge")
	# Repeated native runs reuse this disposable file. Remove only this fixture's
	# previously committed support and save a clean baseline before assertions.
	for child in bridge.get_children():
		if Surface.is_surface(child):
			child.free()
	check(EditorInterface.save_scene() == OK, "save clean fixture baseline")
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(bridge)
	var plugin := get_tree().root.find_child("EmberImportPlugin", true, false)
	check(plugin != null, "actual Ember plugin missing")
	if plugin == null:
		push_error("actual Ember plugin missing")
		get_tree().quit(1)
		return
	plugin.call("_walk_surface_selected")
	await frames(15)
	var panel = plugin.get("_walk_surface_panel")
	check(panel != null and panel.is_visible_in_tree(), "native bottom panel not visible")
	check(scene.get_child_count() == 1 and bridge.get_child_count() == 8, "draft mutated scene tree")
	check(not EditorInterface.get_unsaved_scenes().has(path), "opening draft dirtied scene")
	panel._numbers[3].value = 1.5
	check(panel._instances.size() >= 2 and not panel._apply.disabled, "main-world preview missing")
	check(panel._meshes[0] is PlaneMesh, "no surface plane")
	panel._generate()
	check(not panel.session.planned_mask.is_empty() and panel._meshes[0] is ArrayMesh,"voxel generation not shown in native viewport")
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var viewport_parent: Node = viewport.get_parent()
	while viewport_parent != null and not viewport_parent.is_class("Node3DEditorViewport"):
		viewport_parent = viewport_parent.get_parent()
	var control := viewport_parent as Control
	print("WALK_EDITOR viewport parent=", control.get_class() if control != null else "null")
	# Deliver normal viewport input with the panel open; no modal window can trap it.
	if control != null:
		var root_viewport := EditorInterface.get_base_control().get_viewport()
		var hover := InputEventMouseMotion.new()
		hover.position = control.get_global_rect().get_center()
		hover.global_position = hover.position
		root_viewport.push_input(hover)
		control.focus_mode = Control.FOCUS_ALL
		control.grab_focus()
		var focus := InputEventKey.new()
		focus.keycode = KEY_F
		focus.physical_keycode = KEY_F
		focus.pressed = true
		root_viewport.push_input(focus)
		focus = focus.duplicate()
		focus.pressed = false
		root_viewport.push_input(focus)
		await frames(10)
		for step in 70:
			var camera := viewport.get_camera_3d()
			var distance := camera.size if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else camera.global_position.length()
			if distance > 80 and distance < 100:
				break
			var wheel := InputEventMouseButton.new()
			wheel.position = hover.position
			wheel.global_position = hover.position
			wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN if distance < 80 else MOUSE_BUTTON_WHEEL_UP
			wheel.pressed = true
			root_viewport.push_input(wheel)
			await frames(2)
		var before := viewport.get_camera_3d().global_transform
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_MIDDLE
		press.button_mask = MOUSE_BUTTON_MASK_MIDDLE
		press.position = hover.position
		press.global_position = press.position
		press.pressed = true
		root_viewport.push_input(press)
		var motion := InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
		motion.position = press.position + Vector2(160, 50)
		motion.relative = Vector2(160, 50)
		motion.screen_relative = motion.relative
		motion.global_position = motion.position
		root_viewport.push_input(motion)
		press.pressed = false
		press.button_mask = 0
		root_viewport.push_input(press)
		await frames(10)
		check(not viewport.get_camera_3d().global_transform.basis.is_equal_approx(before.basis), "viewport camera input did not rotate camera")
		# Actual viewport input must route through the real Ember plugin, paint
		# the projected voxel and leave scene data untouched until Apply.
		var world: Transform3D = panel.session.world_pose()
		var data: Dictionary = panel.session.planned_mask
		var pixel := viewport.get_camera_3d().unproject_position(world*Vector3(0.5,0,0.5))
		var point := control.get_global_rect().position+pixel
		var selected_cell := Mask.at(Vector3(0.5,0,0.5),data)
		var selected_index: int = selected_cell.y*data.count.x+selected_cell.x
		check(data.bits[selected_index] == 1,"fixture brush target starts empty")
		panel._brush.select(1)
		var move := InputEventMouseMotion.new()
		move.position = point
		move.global_position = point
		root_viewport.push_input(move)
		var stroke := InputEventMouseButton.new()
		stroke.position = point
		stroke.global_position = point
		stroke.button_index = MOUSE_BUTTON_LEFT
		stroke.button_mask = MOUSE_BUTTON_MASK_LEFT
		stroke.pressed = true
		root_viewport.push_input(stroke)
		stroke = stroke.duplicate()
		stroke.pressed = false
		stroke.button_mask = 0
		root_viewport.push_input(stroke)
		await frames(5)
		check(panel.session.planned_mask.bits[selected_index] == 0 and panel._undo_masks.size() == 1,"native left-click did not erase one voxel")
		check(not EditorInterface.get_unsaved_scenes().has(path),"brush draft dirtied scene")
		panel._history(false)
		check(panel.session.planned_mask.bits[selected_index] == 1,"native draft undo failed")
		panel._history(true)
		check(panel.session.planned_mask.bits[selected_index] == 0,"native draft redo failed")
		panel._brush.select(2)
		stroke.pressed = true
		stroke.button_mask = MOUSE_BUTTON_MASK_LEFT
		root_viewport.push_input(stroke)
		stroke = stroke.duplicate()
		stroke.pressed = false
		stroke.button_mask = 0
		root_viewport.push_input(stroke)
		await frames(5)
		check(panel.session.planned_mask.bits[selected_index] == 1,"native restore brush failed")
		# Keep a visible larger hole for captures and save/reopen assertions.
		panel._brush.select(1)
		panel._brush_size.value = 4
		stroke.pressed = true
		stroke.button_mask = MOUSE_BUTTON_MASK_LEFT
		root_viewport.push_input(stroke)
		stroke = stroke.duplicate()
		stroke.pressed = false
		stroke.button_mask = 0
		root_viewport.push_input(stroke)
		await frames(5)
		var brush_camera_before := viewport.get_camera_3d().global_transform.basis
		var orbit := InputEventMouseButton.new()
		orbit.position = point
		orbit.global_position = point
		orbit.button_index = MOUSE_BUTTON_MIDDLE
		orbit.button_mask = MOUSE_BUTTON_MASK_MIDDLE
		orbit.pressed = true
		root_viewport.push_input(orbit)
		var orbit_motion := InputEventMouseMotion.new()
		orbit_motion.position = point+Vector2(50,25)
		orbit_motion.global_position = orbit_motion.position
		orbit_motion.relative = Vector2(50,25)
		orbit_motion.screen_relative = orbit_motion.relative
		orbit_motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
		root_viewport.push_input(orbit_motion)
		orbit.pressed = false
		orbit.button_mask = 0
		root_viewport.push_input(orbit)
		await frames(5)
		check(not viewport.get_camera_3d().global_transform.basis.is_equal_approx(brush_camera_before),"active brush captures camera orbit")
		panel._brush.select(0)
	for dimensions in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		EditorInterface.get_base_control().get_window().size = dimensions
		await frames(8)
		check(panel.get_global_rect().end.y <= float(dimensions.y), "panel extends below editor window")
		check(not panel._scroll.get_h_scroll_bar().visible, "settings require horizontal scrolling")
		for number in panel._numbers:
			check(number.get_global_rect().end.x <= panel.get_global_rect().end.x, "numeric field is outside panel")
		await capture("voxel-%d" % dimensions.y)
		panel._advanced.button_pressed = true
		await frames(8)
		check(panel._fields.is_visible_in_tree() and not panel._scroll.get_h_scroll_bar().visible,"position fields not accessible")
		for number in panel._numbers:
			check(number.is_visible_in_tree() and number.get_global_rect().end.x <= panel.get_global_rect().end.x,"expanded position fields exceed panel")
		await capture("voxel-position-%d" % dimensions.y)
		panel._advanced.button_pressed = false
	check(EditorInterface.save_scene() == OK, "save while preview")
	var saved := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var reopened := saved.instantiate()
	check(reopened.get_node("Bridge").get_child_count() == 8, "draft saved into scene")
	reopened.free()
	panel._commit()
	await frames(10)
	check(bridge.get_child_count() == 9 and panel._instances.is_empty(), "Apply did not publish one plain support and remove preview")
	var support := bridge.get_node("WalkSurface") as StaticBody3D
	check(support != null and support.get_script() == null and support.has_meta(Surface.MASK_KEY), "support serialization changed")
	check(support.get_meta(Surface.MASK_KEY).bits.count(0) > 0,"painted hole not applied")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo()
	check(bridge.get_child_count() == 8, "native Undo")
	history.redo()
	check(bridge.get_child_count() == 9, "native Redo")
	check(EditorInterface.save_scene() == OK, "save applied support")
	selection.clear()
	selection.add_node(support)
	plugin.call("_walk_surface_selected")
	await frames(10)
	panel._numbers[3].value = 2.0
	panel.cancel_edit()
	check(is_equal_approx(support.position.y, 1.0), "Cancel changed committed support")
	plugin.call("_walk_surface_selected")
	await frames(10)
	var painted: PackedByteArray = support.get_meta(Surface.MASK_KEY).bits.duplicate()
	selection.clear()
	selection.add_node(bridge)
	panel._generate()
	check(panel.session.target == support and bridge.get_child_count() == 9,"rebind lost existing support or changed tree")
	panel._commit()
	check(bridge.get_child_count() == 9 and support.get_meta(Surface.MASK_KEY).bits != painted,"rebind failed or created duplicate")
	history.undo()
	check(support.get_meta(Surface.MASK_KEY).bits == painted,"rebind Undo loses painted mask")
	selection.clear()
	selection.add_node(support)
	plugin.call("_walk_surface_selected")
	await frames(10)
	panel.scene_context_changed(null)
	check(panel.session == null and panel._instances.is_empty(), "scene switch retained draft")
	# Native regression: matching older helper masks the edited holes.
	var overlap := Surface.make_node(Surface.dimensions(support))
	overlap.name = "OldSupport"
	var overlap_data: Dictionary = support.get_meta(Surface.MASK_KEY).duplicate(true)
	overlap_data.bits = overlap_data.allowed.duplicate()
	Surface.set_mask(overlap,overlap_data)
	overlap.transform = support.transform
	overlap.set_meta("ember_walk_source",NodePath("."))
	bridge.add_child(overlap)
	overlap.owner = scene
	for child in overlap.get_children():
		child.owner = scene
	selection.clear()
	selection.add_node(support)
	plugin.call("_walk_surface_selected")
	await frames(10)
	check(panel._replace.is_visible_in_tree() and panel._apply.disabled,"native duplicate warning/action missing")
	await capture("duplicate-warning")
	panel._replace.pressed.emit()
	await frames(10)
	check(overlap.collision_layer == 0 and bridge.get_child_count() == 10,"native duplicate resolution deleted a node or failed")
	history.undo()
	check(overlap.collision_layer == 1,"native duplicate resolution Undo")
	history.redo()
	check(overlap.collision_layer == 0,"native duplicate resolution Redo")
	check(EditorInterface.save_scene() == OK,"save disabled duplicate")
	var resolved_pack := ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var resolved_scene := resolved_pack.instantiate()
	check(resolved_scene.get_node("Bridge/OldSupport").collision_layer == 0,"disabled duplicate not saved")
	resolved_scene.free()
	selection.clear()
	selection.add_node(bridge)
	plugin.call("_walk_surface_selected")
	await frames(10)
	check(panel.session.target == support,"native reopen source creates another support")
	panel.cancel_edit()
	# Simulate an old constructed UI after a tool-script update. Reopening the
	# command reconstructs missing controls without restarting the live editor.
	panel._replace.free()
	plugin.call("_walk_surface_selected")
	await frames(10)
	panel = plugin.get("_walk_surface_panel")
	check(is_instance_valid(panel._replace) and panel.session.target == support,"reopen does not rebuild outdated panel")
	panel.cancel_edit()
	for error in errors:
		push_error(error)
	print("WALK_PANEL_EDITOR ", "PASS" if errors.is_empty() else "FAIL", " errors=", errors.size())
	get_tree().quit(0 if errors.is_empty() else 1)
