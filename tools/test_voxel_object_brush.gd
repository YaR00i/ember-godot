extends SceneTree

const Brush = preload("res://addons/ember_import/ember_voxel_object_brush.gd")
const Math = preload("res://addons/ember_import/ember_voxel_placement_math.gd")
const Creation = preload("res://addons/ember_import/ember_voxel_shape_creation.gd")
const MainPlugin = preload("res://addons/ember_import/plugin.gd")
var errors: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var props := Node3D.new()
	scene.add_child(props)
	props.owner = scene
	props.transform = Transform3D(Basis(Vector3.UP, 0.4).scaled(Vector3(2, 0.8, 1.2)), Vector3(10, 3, -4))
	var folder := "user://ember-tests/object-brush-%d" % Time.get_ticks_usec()
	var creation := Creation.new()
	creation.source_directory = folder.path_join("sources")
	creation.prefab_directory = folder.path_join("prefabs")
	check(creation.prepare("block", Vector3i(12, 3, 5), 16, Color("a86f45"), "Plank"), "fixture prepare")
	var creation_undo := UndoRedo.new()
	var original := creation.commit(scene, props, creation_undo, Vector3.ZERO)
	creation_undo.clear_history()
	creation_undo.free()
	if original == null:
		push_error("fixture failed")
		quit(1)
		return
	var source_path := creation.source_directory.path_join(original.model_id + ".tres")
	var source_hash := FileAccess.get_sha256(source_path)
	var packed := load(creation.prefab_directory.path_join(original.model_id + ".tscn")) as PackedScene
	var undo := UndoRedo.new()
	var brush := Brush.new()
	root.add_child(brush)
	check(brush.activate(scene, props, packed, original.model_id, undo, 16.0), "activate")
	brush.yaw_degrees = 31
	brush.scale_factor = 1.35
	brush.bury_vox = 2
	var point := Vector3(20, 8, 30)
	var pose: Transform3D = brush.transform_at(point)
	check((pose * brush._pivot).is_equal_approx(point - Vector3.UP * 2), "actual mesh bottom pivot / bury")
	brush._append(point)
	brush._append(point + Vector3.RIGHT * 16)
	check(props.get_child_count() == 1, "preview mutated scene instances")
	var saved := PackedScene.new()
	check(saved.pack(scene) == OK, "pack preview")
	var saved_scene := saved.instantiate()
	check(saved_scene.get_child_count() == 1, "preview serialized")
	saved_scene.free()
	check(brush.commit_stroke() == 2, "batch commit")
	check(brush.active and props.get_child_count() == 3, "sticky asset / instance count")
	var a := props.get_child(1) as EmberVoxelProp
	var b := props.get_child(2) as EmberVoxelProp
	check(a.placement_id != b.placement_id and a.placement_id != original.placement_id, "unique reserved IDs")
	check(a.global_transform.is_equal_approx(pose), "preview differs from commit under transformed parent")
	check(a.owner == scene and b.owner == scene, "tscn ownership")
	brush.deactivate()
	undo.undo()
	check(props.get_child_count() == 1, "one undo after brush deactivate")
	# Change active scene before Redo: action must retain its original parent.
	var other := Node3D.new()
	root.add_child(other)
	var other_parent := Node3D.new()
	other.add_child(other_parent)
	check(brush.activate(other, other_parent, packed, original.model_id, undo, 16), "reactivate")
	undo.redo()
	check(props.get_child_count() == 3 and other_parent.get_child_count() == 0, "redo uses mutable brush context")
	brush.deactivate()
	check(saved.pack(scene) == OK, "pack committed")
	var scene_path := folder.path_join("scene.tscn")
	check(ResourceSaver.save(saved, scene_path) == OK, "save")
	var reopened := (ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_child(0).get_child_count() == 3, "save/reopen instances")
	check((reopened.get_child(0).get_child(1) as EmberVoxelProp).transform.is_equal_approx(a.transform), "save/reopen transform")
	reopened.free()
	check(FileAccess.get_sha256(source_path) == source_hash, "source modified")
	check(brush.activate(scene, props, packed, original.model_id, undo, 16), "activate cancel test")
	brush._append(Vector3.ZERO)
	brush.cancel_stroke()
	check(brush.commit_stroke() == 0 and props.get_child_count() == 3, "discard produced instances")
	for index in 300:
		brush._append(Vector3(index, 0, 0))
	check(brush._transforms.size() == 256, "unbounded stroke")
	brush.cancel_stroke()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	check(brush.forward_input(null, escape) == EditorPlugin.AFTER_GUI_INPUT_STOP and not brush.active, "escape")
	var one := Math.stroke_samples(Vector3.ZERO, Vector3(10, 0, 0), 3, 3)
	var first := Math.stroke_samples(Vector3.ZERO, Vector3(4, 0, 0), 3, 3)
	var second := Math.stroke_samples(Vector3(4, 0, 0), Vector3(10, 0, 0), 3, first.remaining)
	check(one.points == first.points + second.points, "spacing depends on event frequency")
	check(is_equal_approx(one.remaining, second.remaining), "distance carry")
	# Real physics picking, including an elevated platform; not a fake y=0 plane.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50, 2, 50)
	shape.shape = box
	body.add_child(shape)
	scene.add_child(body)
	body.position = Vector3(0, 7, 0)
	check(brush.activate(scene, props, packed, original.model_id, undo, 16), "physics activate")
	await physics_frame
	await physics_frame
	var hit: Dictionary = brush._ray(Vector3(0, 30, 0), Vector3(0, -30, 0))
	check(not hit.is_empty() and is_equal_approx(hit.position.y, 8), "elevated physical surface")
	check(brush._ray(Vector3(80, 30, 0), Vector3(80, -30, 0)).is_empty(), "empty space fallback")
	brush.deactivate()
	undo.clear_history()
	undo.free()
	brush.free()
	other.free()
	scene.free()
	for message in errors:
		push_error(message)
	print("test_voxel_object_brush: ", "PASS" if errors.is_empty() else "FAIL", " · ", errors.size(), " errors")
	quit(0 if errors.is_empty() else 1)
