extends SceneTree
const Creation = preload("res://addons/ember_import/ember_voxel_shape_creation.gd")
const Assembly = preload("res://addons/ember_import/ember_voxel_scene_assembly.gd")
const Canvas = preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Dialog = preload("res://addons/ember_import/ember_voxel_duplicate_dialog.gd")
var failures: Array[String] = []
class PathHolder extends Node:
	@export var target_path: NodePath

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _run() -> void:
	var scene := Node3D.new()
	scene.name = "Fixture"
	root.add_child(scene)
	var parent := Node3D.new()
	parent.name = "Parts"
	parent.transform = Transform3D(Basis(Vector3.UP, 0.37).scaled(Vector3(1.2, 0.8, 1.4)), Vector3(13, 7, -4))
	scene.add_child(parent)
	parent.owner = scene
	var undo := UndoRedo.new()
	var folder := "user://ember-tests/scene-assembly-%d" % Time.get_ticks_usec()
	var creation := Creation.new()
	creation.source_directory = folder.path_join("sources")
	creation.prefab_directory = folder.path_join("prefabs")
	check(creation.prepare("block", Vector3i(16, 3, 32), 16, Color.BROWN, "Board"), "prepare source")
	var source := creation.commit(scene, parent, undo, Vector3(3, 1.5, 4))
	if source == null:
		_finish(scene, undo)
		return
	source.rotation_degrees = Vector3(3, 7, 2)
	var source_pose := source.global_transform
	var source_hash := FileAccess.get_sha256(folder.path_join("sources").path_join(source.model_id + ".tres"))
	var action := Assembly.new()
	action.source_directory = creation.source_directory
	var step := Vector3(19, 0.25, -0.5)
	check(action.prepare_copies(source, scene, step, 3), action.error)
	var preview := action.positions.duplicate()
	var before_count := parent.get_child_count()
	check(parent.get_child_count() == before_count, "preview created nodes")
	var copies := action.commit_copies(undo)
	check(copies.size() == 3, "copy count: " + action.error)
	if copies.size() != 3:
		_finish(scene, undo)
		return
	var ids := {}
	ids[source.placement_id] = true
	for index in copies.size():
		var copy := copies[index]
		check(copy.global_transform.is_equal_approx(preview[index]), "preview vs commit")
		check(copy.model_id == source.model_id and copy.owner == scene, "linked source and scene owner")
		check(not ids.has(copy.placement_id), "duplicate placement ID")
		ids[copy.placement_id] = true
		var relative: Transform3D = source.global_transform.affine_inverse() * source.get_node("Collision/Shape").global_transform
		check((copy.global_transform.affine_inverse() * copy.get_node("Collision/Shape").global_transform).is_equal_approx(relative), "copy collision")
	undo.undo()
	check(parent.get_child_count() == before_count, "Undo entire row")
	undo.redo()
	check(parent.get_child_count() == before_count + 3, "Redo row")
	check(source.global_transform.is_equal_approx(source_pose), "original moved")
	var repeated := Assembly.new()
	repeated.source_directory = creation.source_directory
	check(repeated.prepare_copies(copies.back(), scene, step, 1), repeated.error)
	var next := repeated.commit_copies(undo)
	check(next.size() == 1 and next[0].global_position.is_equal_approx(copies.back().global_position + step), "repeat last step")

	var group_action := Assembly.new()
	group_action.source_directory = creation.source_directory
	var selection: Array = [source, copies[0], copies[1], copies[2]]
	var holder := PathHolder.new()
	holder.name = "ExternalReference"
	scene.add_child(holder)
	holder.owner = scene
	holder.target_path = holder.get_path_to(source)
	check(group_action.group(selection, scene, undo) == null, "external NodePath allowed reparent")
	check(source.get_parent() == parent, "refusal partially regrouped")
	holder.free()
	source.unique_name_in_owner = true
	var poses: Array[Transform3D] = []
	for part in selection:
		poses.append(part.global_transform)
	var group := group_action.group(selection, scene, undo)
	check(group != null, "group: " + group_action.error)
	if group == null:
		_finish(scene, undo)
		return
	for index in selection.size():
		check(selection[index].global_transform.is_equal_approx(poses[index]), "group shifted part")
		check(selection[index].owner == scene, "group lost owner")
	check(source.unique_name_in_owner, "group lost unique name flag")
	undo.undo()
	check(source.get_parent() == parent and source.get_index() == 0, "group Undo order")
	undo.redo()
	check(source.get_parent() == group, "group Redo")
	var grouped_pack := PackedScene.new()
	check(grouped_pack.pack(scene) == OK, "grouped pack")
	var grouped_reopened := grouped_pack.instantiate()
	check(grouped_reopened.get_node(NodePath("Parts/" + str(group.name))).get_child_count() == 4, "grouped scene lost members")
	grouped_reopened.free()
	# Subsequent authored transforms must survive ungroup; no original geometry restore.
	group.rotation_degrees = Vector3(2, 17, 0)
	group.position += Vector3(4, 0, -7)
	copies[0].position.y += 0.8
	poses.clear()
	for part in selection:
		poses.append(part.global_transform)
	var break_action := Assembly.new()
	break_action.source_directory = creation.source_directory
	check(break_action.ungroup(group, scene, undo), "ungroup: " + break_action.error)
	for index in selection.size():
		check(selection[index].global_transform.is_equal_approx(poses[index]), "ungroup lost placement edits")
	undo.undo()
	check(source.get_parent() == group, "ungroup Undo")
	undo.redo()
	check(source.get_parent() == parent, "ungroup Redo")
	# Edit one linked copy via existing Canvas: other models must remain unchanged.
	var canvas := Canvas.new()
	canvas.source_directory = creation.source_directory
	canvas.prefab_directory = creation.prefab_directory
	check(canvas.open(copies[0], scene, undo), "copy Canvas open: " + canvas.error)
	canvas.draft.voxels[0] = 0
	var saved: Dictionary = canvas.save(canvas.draft)
	check(saved.get("ok", false), "COW copy save")
	check(copies[0].model_id != source.model_id and copies[1].model_id == source.model_id, "copy COW isolation")
	check(FileAccess.get_sha256(folder.path_join("sources").path_join(source.model_id + ".tres")) == source_hash, "original source overwritten")
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK, "scene pack")
	var scene_path := folder.path_join("roundtrip.tscn")
	check(ResourceSaver.save(packed, scene_path) == OK, "scene save")
	var reopened := (ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var saved_parent := reopened.get_node("Parts")
	check(saved_parent.get_child_count() == parent.get_child_count(), "reopen count")
	for part in parent.get_children():
		check(saved_parent.get_node(NodePath(str(part.name))).transform.is_equal_approx(part.transform), "reopen pose")
	reopened.free()
	# Invalid/stale plans must not publish nodes.
	check(action.prepare_copies(source, scene, step, 2), "prepare stale")
	source.position.x += 1
	check(action.commit_copies(undo).is_empty(), "stale source committed")
	source.position.x -= 1
	check(not action.prepare_copies(source, scene, Vector3.ZERO, 1), "zero step accepted")
	check(action.commit_copies(undo).is_empty(), "invalid plan retained copies")
	var measure := Assembly.new()
	measure.source_directory = creation.source_directory
	var started := Time.get_ticks_usec()
	check(measure.prepare_copies(source, scene, step, 32), "32-copy preview")
	var batch := measure.commit_copies(undo)
	check(batch.size() == 32, "32-copy commit")
	print("COPY_BATCH_32_MS ", (Time.get_ticks_usec() - started) / 1000.0)
	undo.undo()
	# UI is tested through actual signals; Cancel never creates scene nodes.
	var dialog := Dialog.new()
	root.add_child(dialog)
	check(dialog.open_for(source, scene, undo, creation.source_directory), "dialog open")
	var node_count := parent.get_child_count()
	dialog._axes[0].value = 23
	dialog._count.value = 4
	check(dialog.operation.positions.size() == 4, "UI count signal")
	check(parent.get_child_count() == node_count, "UI preview mutated scene")
	if "--capture" in OS.get_cmdline_user_args():
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.content_scale_size = Vector2i.ZERO
		root.size = Vector2i(1280, 720)
		dialog.popup_centered(Vector2i(620, 600))
		for frame in 12:
			await process_frame
		RenderingServer.force_draw(false)
		print("COPY_LAYOUT ", dialog.position, " / ", dialog.size, " container ", dialog.find_child("CopyPreview", true, false).size)
		check(dialog.position.y + dialog.size.y <= root.size.y, "dialog exceeds 720p")
		check(dialog.size.x <= root.size.x, "dialog exceeds viewport width")
		check(dialog._preview.get_child_count() == 7, "preview missing row visuals/camera/light")
		var path := "user://voxel-copies-preview-%d.png" % OS.get_process_id()
		root.get_texture().get_image().save_png(path)
		print("COPY_PREVIEW ", ProjectSettings.globalize_path(path))
		root.size = Vector2i(1600, 900)
		dialog.popup_centered(Vector2i(620, 600))
		for frame in 12:
			await process_frame
		check(dialog.position.y + dialog.size.y <= root.size.y, "dialog exceeds 900p")
		RenderingServer.force_draw(false)
		path = "user://voxel-copies-preview-900-%d.png" % OS.get_process_id()
		root.get_texture().get_image().save_png(path)
		print("COPY_PREVIEW_900 ", ProjectSettings.globalize_path(path))
	dialog.hide()
	dialog.free()
	check(parent.get_child_count() == node_count, "Cancel mutated scene")
	_finish(scene, undo)

func _finish(scene: Node, undo: UndoRedo) -> void:
	for message in failures:
		push_error(message)
	print("test_voxel_scene_assembly: ", "PASS" if failures.is_empty() else "FAIL", " · ", failures.size())
	undo.clear_history()
	undo.free()
	scene.free()
	quit(0 if failures.is_empty() else 1)
