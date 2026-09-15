extends SceneTree
## Engine isolation only; no library, shader, sky, authored scene or publication.
func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var camera := Camera3D.new()
	camera.position.z = 4
	root.add_child(camera)
	var enabled := "--probe" in OS.get_cmdline_user_args()
	if enabled:
		root.add_child(ReflectionProbe.new())
	for i in 60: await process_frame
	for child in root.get_children():
		if child is Camera3D or child is ReflectionProbe: child.queue_free()
	for i in 60: await process_frame
	print("ENGINE_REFLECTION_ISOLATION probe=",enabled)
	quit()
