extends SceneTree

const Placement = preload("res://addons/ember_import/ember_voxel_placement_session.gd")
const Dialog = preload("res://addons/ember_import/ember_voxel_placement_dialog.gd")


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
	assert(group != null and group.get_child_count() == 12)
	var initial := group.global_transform
	var placement := Placement.new()
	assert(placement.open(group,scene,null),placement.error)
	var dialog := Dialog.new()
	root.add_child(dialog)
	assert(dialog.open_for(placement))
	for frame in 12:
		await process_frame
	assert(group.global_transform.is_equal_approx(initial),"dialog open mutated Pier")
	dialog._rotations[1].value = 19
	var rotated: Transform3D = dialog._planned_world
	assert(not rotated.is_equal_approx(initial),"numeric rotation did not update preview")
	dialog._pivot.select(1)
	dialog._pivot.item_selected.emit(1)
	assert(dialog._planned_world.is_equal_approx(rotated),"pivot switch moved active preview")
	var before_coords: Vector3 = placement.coordinate_for_world(dialog._desired_world,dialog._grid.get_selected_id())
	dialog._coordinates[0].value = before_coords.x+0.43
	var after_coords: Vector3 = placement.coordinate_for_world(dialog._desired_world,dialog._grid.get_selected_id())
	assert(is_equal_approx(after_coords.x,roundf(before_coords.x+0.43)),"edited axis was not snapped")
	assert(is_equal_approx(after_coords.y,before_coords.y) and is_equal_approx(after_coords.z,before_coords.z),"editing X unexpectedly snapped Y/Z")
	assert(group.global_transform.is_equal_approx(initial),"preview controls mutated Pier")
	await _capture(dialog,Vector2i(1280,720),"720")
	await _capture(dialog,Vector2i(1600,900),"900")
	dialog.free()
	scene.free()
	print("PLACEMENT_PREVIEW PASS")
	quit()


func _capture(dialog: Window,viewport_size: Vector2i,suffix: String) -> void:
	dialog.hide()
	DisplayServer.window_set_size(viewport_size)
	root.size = viewport_size
	for frame in 3:
		await process_frame
	dialog.popup_centered(Vector2i(720,640))
	for frame in 12:
		await process_frame
	print("PLACEMENT_LAYOUT_",suffix," root=",root.size," visible=",root.get_visible_rect().size," content=",root.content_scale_size," window=",DisplayServer.window_get_size()," dialog=",dialog.position," + ",dialog.size)
	assert(dialog.position.x >= 0 and dialog.position.y >= 0,"dialog starts outside viewport "+suffix)
	assert(dialog.position.x+dialog.size.x <= viewport_size.x and dialog.position.y+dialog.size.y <= viewport_size.y,"dialog extends outside viewport "+suffix)
	var preview := dialog.find_child("PlacementPreview",true,false) as Control
	assert(preview != null and preview.is_visible_in_tree() and preview.size.x >= 300 and preview.size.y >= 410,"preview clipped "+suffix)
	var scroll := dialog.find_child("PlacementScroll",true,false) as ScrollContainer
	assert(scroll != null and scroll.is_visible_in_tree() and scroll.size.x >= 320,"controls clipped "+suffix)
	RenderingServer.force_draw(false)
	var path := "user://voxel-placement-preview-%s-%d.png" % [suffix,OS.get_process_id()]
	var image := root.get_texture().get_image()
	assert(image.get_size() == viewport_size,"capture resolution "+suffix)
	image.save_png(path)
	print("PLACEMENT_PREVIEW_",suffix," ",ProjectSettings.globalize_path(path))
