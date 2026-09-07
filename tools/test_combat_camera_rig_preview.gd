extends SceneTree
## CameraRig Inspector preview must show the same world and lens as its child.

const ARENA := preload("res://scenes/combat/arenas/colored_crossing.tscn")
const Preview := preload("res://addons/ember_import/ember_camera_rig_preview.gd")


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	var errors: Array[String] = []
	var arena := ARENA.instantiate() as Node3D
	root.add_child(arena)
	await process_frame
	var rig := arena.get_node_or_null("CameraRig") as OrbitCamera
	var source := arena.get_node_or_null("CameraRig/CombatCamera3D") as Camera3D
	if rig == null or source == null:
		errors.append("arena lost its authored CameraRig/CombatCamera3D pair")
	else:
		var preview := Preview.new() as EmberCameraRigPreview
		preview.setup(rig)
		root.add_child(preview)
		await process_frame
		preview.sync_now()
		var viewport := preview.preview_viewport()
		var camera := preview.preview_camera()
		if viewport == null or camera == null:
			errors.append("CameraRig Inspector preview did not create its viewport camera")
		elif viewport.world_3d != source.get_world_3d():
			errors.append("CameraRig preview does not share the edited arena World3D")
		elif not camera.global_transform.is_equal_approx(source.global_transform):
			errors.append("CameraRig preview camera transform drifted from CombatCamera3D")
		elif camera.projection != source.projection or not is_equal_approx(camera.size, source.size):
			errors.append("CameraRig preview lens drifted from CombatCamera3D")
		rig.orthographic_size = 7.4
		rig.yaw_degrees = -22.0
		rig.apply_settings()
		preview.sync_now()
		if not is_equal_approx(camera.size, 7.4):
			errors.append("CameraRig preview did not live-update an Inspector lens change")
		if not camera.global_transform.is_equal_approx(source.global_transform):
			errors.append("CameraRig preview did not live-update an Inspector pose change")
		rig.projection_mode = 1
		rig.fov = 61.0
		rig.apply_settings()
		preview.sync_now()
		if source.projection != Camera3D.PROJECTION_PERSPECTIVE:
			errors.append("CameraRig did not apply perspective projection to its authored camera")
		if camera.projection != Camera3D.PROJECTION_PERSPECTIVE or not is_equal_approx(camera.fov, 61.0):
			errors.append("CameraRig preview did not live-update perspective FOV")
		var status := preview.find_child("CameraRigPreviewStatus", true, false) as Label
		if status == null or not status.text.contains("FOV 61.0"):
			errors.append("CameraRig preview does not explain the active perspective lens")
		if preview.find_child("SelectCameraRigChild", true, false) == null:
			errors.append("CameraRig preview lost the child-camera navigation action")
		preview.queue_free()
	await process_frame
	arena.queue_free()
	await process_frame
	if not errors.is_empty():
		printerr("FAIL combat CameraRig preview")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS combat CameraRig preview")
	print("  Inspector preview shares the arena World3D and follows the authored camera")
	print("  preview owns no second combat world or runtime camera")
	quit(0)
