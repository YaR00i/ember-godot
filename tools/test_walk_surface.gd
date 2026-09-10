extends SceneTree
const Surface = preload("res://addons/ember_import/ember_walk_surface.gd")
const Session = preload("res://addons/ember_import/ember_walk_surface_session.gd")
const Dialog = preload("res://addons/ember_import/ember_walk_surface_dialog.gd")
var failures: Array[String] = []
class FixturePlayer extends EmberPlayer:
	func _progress() -> EmberExploreState:
		return null

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _run() -> void:
	var scene := Node3D.new()
	scene.name = "Fixture"
	root.add_child(scene)
	var group := Node3D.new()
	group.name = "Bridge"
	scene.add_child(group)
	group.owner = scene
	for index in 8:
		var board := MeshInstance3D.new()
		board.name = "Board%d" % index
		var mesh := BoxMesh.new()
		mesh.size = Vector3(9, 1, 20)
		board.mesh = mesh
		board.position = Vector3(5 + index * 10, 0.5 + (index % 2) * 0.7, 0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.5, 0.28 + index * 0.015, 0.09)
		board.material_override = material
		group.add_child(board)
		board.owner = scene
	var undo := UndoRedo.new()
	var edit := Session.new()
	check(edit.open(group, scene), edit.error)
	var pose := Transform3D(Basis.IDENTITY, Vector3(40, 1.8, 0))
	check(edit.plan(Vector2(80, 24), pose), edit.error)
	check(group.get_child_count() == 8, "preview modified scene")
	check(edit.warnings.is_empty(), "low boards flagged as protrusions")
	check(edit.plan(Vector2(80, 24), Transform3D(Basis.IDENTITY, Vector3(40, 0.2, 0))), "low preview")
	check(not edit.warnings.is_empty(), "missing protrusion warning")
	check(edit.plan(Vector2(80, 24), pose), "restore preview")
	var surface := edit.commit(undo)
	check(surface != null, edit.error)
	if surface == null:
		_finish(scene, undo)
		return
	check(surface.get_script() == null and surface.find_children("*", "MeshInstance3D", true, false).is_empty(), "runtime visual or script saved")
	check(surface.collision_layer == 1, "not on common physical layer")
	check(surface.owner == scene and Surface.shape_node(surface).owner == scene, "serialization owners")
	check(surface.transform.is_equal_approx(pose), "preview != applied")
	undo.undo()
	check(surface.get_parent() == null, "create Undo")
	undo.redo()
	check(surface.get_parent() == group, "create Redo")
	await physics_frame
	await physics_frame
	var hit := _ray(scene, Vector3(40, 30, 0), Vector3(40, -10, 0))
	check(not hit.is_empty() and is_equal_approx(hit.position.y, 1.8), "common physics height")
	check(_ray(scene, Vector3(82, 30, 0), Vector3(82, -10, 0)).is_empty(), "surface exceeds rectangle")
	# Actual existing player controller: no special support logic or override.
	var player := FixturePlayer.new()
	player.position = Vector3(5, 4, 0)
	scene.add_child(player)
	for frame in 45:
		await physics_frame
	check(player.is_on_floor(), "player does not stand on surface")
	Input.action_press("move_east")
	for frame in 120:
		await physics_frame
	Input.action_release("move_east")
	check(player.global_position.x > 50 and player.is_on_floor(), "player stuck walking deck")
	check(absf(player.global_position.y - 1.8) < 0.05, "player/height query disagree")
	player.free()
	var resize := Session.new()
	check(resize.open(surface, scene), resize.error)
	var slope := Transform3D(Basis(Vector3.FORWARD, deg_to_rad(8)), Vector3(40, 4, 0))
	check(resize.plan(Vector2(60, 20), slope), resize.error)
	check(resize.commit(undo) == surface, resize.error)
	check(surface.transform.is_equal_approx(slope) and Surface.dimensions(surface) == Vector2(60, 20), "edit surface")
	undo.undo()
	check(surface.transform.is_equal_approx(pose) and Surface.dimensions(surface) == Vector2(80, 24), "edit Undo")
	undo.redo()
	group.position = Vector3(3, 2, -1)
	await physics_frame
	await physics_frame
	hit = _ray(scene, Vector3(43, 30, -1), Vector3(43, -10, -1))
	check(not hit.is_empty() and absf(hit.position.y - 6) < 0.02, "incline/group physics mismatch")
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK, "pack")
	var path := "user://walk-surface-%d.tscn" % Time.get_ticks_usec()
	check(ResourceSaver.save(packed, path) == OK, "save")
	var reopened := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var reopened_surface := reopened.get_node(NodePath("Bridge/" + str(surface.name)))
	check(Surface.is_surface(reopened_surface) and Surface.dimensions(reopened_surface) == Vector2(60, 20), "reopen data")
	check(reopened_surface.get_script() == null and reopened_surface.get_child_count() == 1, "editor overlays serialized")
	reopened.free()
	var stale := Session.new()
	check(stale.open(surface, scene), "stale open")
	check(stale.plan(Vector2(40, 12), slope), "stale plan")
	group.position.x += 1
	check(stale.commit(undo) == null, "stale parent committed")
	group.position.x -= 1
	check(not stale.plan(Vector2(-1, 2), slope), "invalid dimensions")
	check(not stale.plan(Vector2(10, 10), Transform3D(Basis(Vector3.RIGHT, PI / 3), Vector3.ZERO)), "steep slope accepted")
	check(stale.commit(undo) == null, "invalid plan remained applicable")
	# Native dialog uses the exact same plan and leaves scene unchanged on Cancel.
	var dialog := Dialog.new()
	root.add_child(dialog)
	check(dialog.open_for(surface, scene, undo), "dialog open")
	var prior := surface.transform
	dialog._numbers[3].value = 0.5
	check(surface.transform.is_equal_approx(prior), "UI preview modified scene")
	check(not dialog.session.warnings.is_empty(), "UI protrusion report")
	if "--capture" in OS.get_cmdline_user_args():
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.content_scale_size = Vector2i.ZERO
		for dimensions in [Vector2i(1280,720), Vector2i(1600,900)]:
			root.size = dimensions
			dialog.popup_centered(Vector2i(730,620))
			for frame in 12:
				await process_frame
			check(dialog.position.y + dialog.size.y <= root.size.y, "dialog height")
			RenderingServer.force_draw(false)
			var image_path := "user://walk-surface-preview-%d-%d.png" % [dimensions.y, OS.get_process_id()]
			root.get_texture().get_image().save_png(image_path)
			print("WALK_PREVIEW ", ProjectSettings.globalize_path(image_path))
	dialog.free()
	check(surface.transform.is_equal_approx(prior), "Cancel modified surface")
	_finish(scene, undo)

func _ray(scene: Node3D, from: Vector3, to: Vector3) -> Dictionary:
	return scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))

func _finish(scene: Node, undo: UndoRedo) -> void:
	for message in failures:
		push_error(message)
	print("test_walk_surface: ", "PASS" if failures.is_empty() else "FAIL", " · ", failures.size())
	undo.clear_history()
	undo.free()
	scene.free()
	quit(0 if failures.is_empty() else 1)
