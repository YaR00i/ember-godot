extends SceneTree

const Placement = preload("res://addons/ember_import/ember_voxel_placement_session.gd")
const Dialog = preload("res://addons/ember_import/ember_voxel_placement_dialog.gd")
var errors: Array[String] = []

func check(value: bool, message := "preview condition") -> void:
	if not value: errors.append(message); push_error(message)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	DisplayServer.window_set_size(Vector2i(1280,720))
	root.size = Vector2i(1280,720)
	for frame in 3:
		await process_frame
	var scene := (load("res://scenes/test_pier.tscn") as PackedScene).instantiate()
	scene.set_script(null)
	scene.get_node("Map").set_script(null)
	root.add_child(scene)
	var group := scene.get_node("Map/Terrain/TimberPier/Visual") as Node3D
	check(group != null and not group is EmberVoxelProp,"Pier must be an assembly")
	var props := 0
	for child in group.get_children():
		if child is EmberVoxelProp:
			props += 1
			check(not child.model_id.is_empty() and child.get_node("Mesh").mesh != null,"assembly has invalid voxel part")
	check(props >= 12,"Pier lost reviewed deck parts")
	var initial := group.global_transform
	var placement := Placement.new()
	check(placement.open(group,scene,null),placement.error)
	var dialog := Dialog.new()
	root.add_child(dialog)
	var dock := VBoxContainer.new(); root.add_child(dock); dock.size = Vector2(302, 650)
	var theme := Theme.new(); theme.default_font_size = 20; dock.theme = theme
	dock.add_child(dialog.parameters_panel)
	check(dialog.open_for(placement))
	for frame in 12:
		await process_frame
	check(group.global_transform.is_equal_approx(initial),"dialog open mutated Pier")
	dialog._rotations[1].value = 19
	var rotated: Transform3D = dialog._planned_world
	check(not rotated.is_equal_approx(initial),"numeric rotation did not update preview")
	dialog._pivot.select(1)
	dialog._pivot.item_selected.emit(1)
	check(dialog._planned_world.is_equal_approx(rotated),"pivot switch moved active preview")
	var before_coords: Vector3 = placement.coordinate_for_world(dialog._desired_world,dialog._grid.get_selected_id())
	dialog._coordinates[0].value = before_coords.x+0.43
	var after_coords: Vector3 = placement.coordinate_for_world(dialog._desired_world,dialog._grid.get_selected_id())
	check(is_equal_approx(after_coords.x,roundf(before_coords.x+0.43)),"edited axis was not snapped")
	check(is_equal_approx(after_coords.y,before_coords.y) and is_equal_approx(after_coords.z,before_coords.z),"editing X unexpectedly snapped Y/Z")
	check(group.global_transform.is_equal_approx(initial),"preview controls mutated Pier")
	var before_custom: Transform3D = dialog._planned_world
	dialog._pivot.select(2); dialog._pivot.item_selected.emit(2); dialog._custom[0].value = 2
	check(dialog._custom_fields.visible and dialog._planned_world.is_equal_approx(before_custom),"custom pivot fields / transform preservation")
	await _capture(dialog,dock,Vector2i(1280,720),"720")
	await _capture(dialog,dock,Vector2i(1600,900),"900")
	check(dialog.is_dirty(),"collapse/reflow lost plan")
	dialog.hide(); dialog.show(); check(dialog.is_dirty(),"preview collapse reset plan")
	dialog.cancel_edit(); check(dialog.placement == null and dialog._selected_preview.get_child_count() == 0 and dialog._context.visuals.is_empty(),"Cancel retained private geometry")
	check(group.global_transform.is_equal_approx(initial),"Cancel mutated source")
	dialog.free()
	dock.free()
	scene.free()
	print("PLACEMENT_PREVIEW ", "PASS" if errors.is_empty() else "FAIL", " errors=", errors)
	quit(0 if errors.is_empty() else 1)


func _capture(dialog: Control,dock: Control,viewport_size: Vector2i,suffix: String) -> void:
	DisplayServer.window_set_size(viewport_size)
	root.size = viewport_size
	for frame in 3:
		await process_frame
	dock.position = Vector2(viewport_size.x-322,20); dock.size = Vector2(302,viewport_size.y-40)
	dialog.position = Vector2(20,viewport_size.y-330); dialog.size = Vector2(viewport_size.x-362,310)
	for frame in 12:
		await process_frame
	print("PLACEMENT_DOCK_LAYOUT_",suffix," root=",root.size," parameters=",dock.get_global_rect()," preview=",dialog.get_global_rect())
	check(dialog.parameters_panel.get_combined_minimum_size().x <= 302,"narrow parameter overflow "+suffix)
	check(root.get_visible_rect().encloses(dialog.get_global_rect()) and root.get_visible_rect().encloses(dock.get_global_rect()),"panels outside viewport "+suffix)
	var preview := dialog.find_child("PlacementPreview",true,false) as Control
	check(preview != null and preview.is_visible_in_tree() and preview.size.x >= 320 and preview.size.y >= 230,"preview clipped "+suffix)
	var scroll: ScrollContainer = dialog._parameter_scroll
	check(scroll != null and scroll.is_visible_in_tree(),"controls clipped "+suffix)
	scroll.scroll_vertical = 10000
	for frame in 3: await process_frame
	check(dock.get_global_rect().encloses(dialog.get_apply_button().get_global_rect()),"Apply outside pinned footer "+suffix)
	scroll.scroll_vertical = 0
	if DisplayServer.get_name() == "headless":
		return
	RenderingServer.force_draw(false)
	var path := "user://voxel-placement-preview-%s-%d.png" % [suffix,OS.get_process_id()]
	var image := root.get_texture().get_image()
	check(image.get_size() == viewport_size,"capture resolution "+suffix)
	image.save_png(path)
	print("PLACEMENT_PREVIEW_",suffix," ",ProjectSettings.globalize_path(path))
