extends SceneTree

const Monitor := preload("res://addons/ember_import/ember_voxel_editor_perf_monitor.gd")
const Workspace := preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")

var errors: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	check(Monitor.msaa_label(Viewport.MSAA_DISABLED) == "Off", "MSAA Off label wrong")
	check(Monitor.msaa_label(Viewport.MSAA_2X) == "2x", "MSAA 2x label wrong")
	check(Monitor.msaa_label(Viewport.MSAA_4X) == "4x", "MSAA 4x label wrong")

	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.look_at_from_position(Vector3(0, 1, 4), Vector3.ZERO, Vector3.UP)
	camera.current = true
	viewport.add_child(camera)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	viewport.add_child(mesh)
	Monitor.enable_viewport_measurement(viewport)
	for _frame in 4:
		await process_frame
	var values := Monitor.snapshot(viewport, 1, 0, {}, true)
	for key in [
		"visible_draw_calls", "visible_objects", "visible_primitives",
		"shadow_draw_calls", "shadow_objects", "shadow_primitives",
		"canvas_cpu_ms", "canvas_gpu_ms", "msaa_label", "studio_shadows",
	]:
		check(values.has(key), "diagnostic snapshot missing " + key)
	check(float(values.canvas_cpu_ms) >= 0.0, "Canvas CPU time negative")
	check(float(values.canvas_gpu_ms) >= 0.0, "Canvas GPU time negative")
	viewport.msaa_3d = Viewport.MSAA_2X
	values = Monitor.snapshot(viewport, 1, 0, {}, true)
	check(values.msaa_label == "2x", "snapshot did not track viewport MSAA")
	values = Monitor.snapshot(viewport, 1, 0, {}, false)
	check(not bool(values.studio_shadows), "snapshot shadow state wrong")
	viewport.queue_free()
	await process_frame

	# Exercise the real Canvas controls and public snapshot, not just the monitor.
	var canvas := Workspace.new()
	var undo := UndoRedo.new()
	canvas.setup(null, undo)
	root.add_child(canvas)
	canvas.ensure_ui()
	await process_frame
	values = canvas.editor_performance_snapshot()
	check(bool(values.studio_shadows), "Canvas default studio shadows changed")
	check(values.msaa_label == "4x", "Canvas default MSAA changed")
	var shadows := canvas.get("_perf_shadow_toggle") as CheckButton
	var msaa := canvas.get("_perf_msaa") as OptionButton
	check(shadows != null and msaa != null, "Canvas diagnostic controls missing")
	if shadows != null and msaa != null:
		shadows.button_pressed = false
		check(not bool(canvas.editor_performance_snapshot().studio_shadows), "Canvas shadow control failed")
		msaa.select(0)
		msaa.item_selected.emit(0)
		check(canvas.editor_performance_snapshot().msaa_label == "Off", "Canvas MSAA control failed")
	canvas.queue_free()
	await process_frame
	undo.free()

	for message in errors:
		push_error(message)
	print("test_voxel_editor_render_diagnostics: ", "PASS" if errors.is_empty() else "FAIL", " · ", errors.size())
	quit(0 if errors.is_empty() else 1)
