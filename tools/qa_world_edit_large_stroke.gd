extends SceneTree
## Secondary, headless main-WorldEditor input-path fixture. This is not a live
## Godot 3D-tab/user interaction measurement; the manual recorder is still due.
const World = preload("res://addons/ember_import/ember_world_editor.gd")
var errors: Array[String] = []
var _fixture_nodes: Array[Node] = []
var _history: UndoRedo

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok: errors.append(message)

func _run() -> void:
	var scene := Node3D.new()
	scene.name = "LargeStrokeFixture"
	root.add_child(scene)
	_fixture_nodes.append(scene)
	var source := EmberVoxelModelResource.new()
	source.model_id = "large_stroke_fixture"
	source.display_name = "Large stroke fixture"
	source.voxels_per_block = 16
	source.size_blocks = Vector3i(8,1,8)
	source.height_voxels = 64
	source.palette = PackedColorArray([Color.TRANSPARENT,Color.RED,Color.BLUE])
	var size := source.grid_size()
	var voxels := PackedByteArray()
	voxels.resize(size.x*size.y*size.z)
	for y in 32:
		for z in size.z:
			for x in size.x: voxels[x+z*size.x+y*size.x*size.z] = 1
	source.voxels = voxels
	var map := EmberMapLoader.new()
	map.name = "Map"
	map.map_id = "large_stroke_fixture"
	map.authored_size_blocks = Vector2i(8,8)
	map.hydrate_legacy_regions = false
	map.visual_surface = source
	scene.add_child(map)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(64,140,100)
	camera.look_at(Vector3(64,32,64))
	camera.current = true
	var history := UndoRedo.new()
	_history = history
	var world := World.new()
	root.add_child(world)
	_fixture_nodes.append(world)
	world.configure(null,history)
	var toolbar := world.build_toolbar()
	var sidebar := world.build_sidebar()
	root.add_child(toolbar)
	root.add_child(sidebar)
	_fixture_nodes.append(toolbar)
	_fixture_nodes.append(sidebar)
	world.scene = scene
	world.map = map
	world.entry = world.sessions.open_map(map,scene)
	_check(not world.entry.is_empty(),"map draft did not open: "+world.sessions.error)
	if world.entry.is_empty(): _finish(); return
	world._refresh_palette()
	world.active = true
	var projection: Node = map._visual_surface_projection
	var deadline := Time.get_ticks_msec()+30000
	while is_instance_valid(projection) and not projection.is_projection_complete() and Time.get_ticks_msec() < deadline: await process_frame
	_check(is_instance_valid(projection) and projection.is_projection_complete(),"initial projection did not settle")
	var ground: EmberVoxelModelResource = world.entry.resource
	var original := ground.voxels.duplicate()
	var cases := [
		{"name":"paint_warmup","tool":"paint","radius":0.75,"depth":16,"from":56,"to":72,"minimum":1000,"warmup":true},
		{"name":"paint_small_control","tool":"paint","radius":0.75,"depth":16,"from":56,"to":72,"minimum":1000},
		{"name":"paint_ordinary","tool":"paint","radius":1.25,"depth":16,"from":48,"to":80,"minimum":10000},
		{"name":"paint_stress","tool":"paint","radius":2.0,"depth":16,"from":48,"to":80,"minimum":50000},
		{"name":"shape_add","tool":"add","radius":1.25,"depth":16,"from":48,"to":80,"minimum":10000},
		{"name":"paint_timed","tool":"paint","radius":1.25,"depth":16,"from":48,"to":80,"minimum":10000,"timed":true},
	]
	for spec in cases:
		var report: Dictionary = await _stroke(world,camera,projection,history,ground,original,spec)
		if report.is_empty(): continue
		var stroke: Dictionary = report.strokes[0]
		if not spec.get("warmup",false):
			var max_handler_delay := 0
			for input in stroke.input: max_handler_delay = maxi(max_handler_delay,int(input.handler_delay_usec))
			print("LARGE_STROKE_HEADLESS_INPUT ",spec.name," changed=",stroke.changed_unique_voxels," stages_us=",stroke.stages_usec," queue_wait_total_us=",stroke.queue_wait_usec," max_queue_wait_us=",stroke.max_queue_wait_usec," max_scheduled_handler_delay_us=",max_handler_delay if spec.get("timed",false) else "not_scheduled")
		_check(stroke.changed_unique_voxels >= spec.minimum,"changed voxel threshold: "+spec.name+" got "+str(stroke.changed_unique_voxels))
		_check(stroke.input_source == "synthetic_forward_input_headless","stroke bypassed WorldEditor input: "+spec.name)
		_check(int(stroke.input.size()) >= 3,"stroke did not include continuous input: "+spec.name)
	var first: Dictionary = await _stroke(world,camera,projection,history,ground,original,{"name":"paint_sequence_1","tool":"paint","radius":0.75,"depth":16,"from":28,"to":44,"keep_after":true})
	var after_first := ground.voxels.duplicate()
	var second: Dictionary = await _stroke(world,camera,projection,history,ground,after_first,{"name":"paint_sequence_2","tool":"paint","radius":0.75,"depth":16,"from":84,"to":100,"keep_after":true})
	var after_second := ground.voxels.duplicate()
	_check(not first.is_empty() and not second.is_empty() and first.strokes[0].changed_unique_voxels > 1000 and second.strokes[0].changed_unique_voxels > 1000,"sequential strokes did not both change data")
	history.undo()
	history.undo()
	_check(ground.voxels == original,"two-stroke Undo did not fully restore starting data")
	history.redo()
	history.redo()
	_check(ground.voxels == after_second,"two-stroke Redo did not fully restore final data")
	history.undo()
	history.undo()
	_check(ground.voxels == original,"two-stroke cleanup did not restore starting data")
	print("LARGE_STROKE_SEQUENTIAL full-array Undo/Redo of two distinct strokes=",errors.is_empty())
	_finish()

func _stroke(world: Node, camera: Camera3D, projection: Node, history: UndoRedo, ground: EmberVoxelModelResource, original: PackedByteArray, spec: Dictionary) -> Dictionary:
	world.category.select(1 if spec.tool == "paint" else 0)
	world._category_changed(1 if spec.tool == "paint" else 0)
	if spec.tool == "add": world.tools.select(2)
	world.palette.select(1)
	world.radius.value = spec.radius
	world.depth.value = spec.depth
	world._toggle_trace()
	var frame: Transform3D = world.sessions.frame(world.entry)
	var y := 32.0 if spec.tool == "add" else 31.5
	var from_screen := camera.unproject_position(frame*(Vector3(float(spec.from)+0.5,y,64.5)/16.0))
	var to_screen := camera.unproject_position(frame*(Vector3(float(spec.to)+0.5,y,64.5)/16.0))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = from_screen
	press.pressed = true
	var inputs: Array[Dictionary] = [{"event":press,"offset_usec":0}]
	for i in range(1,9):
		var move := InputEventMouseMotion.new()
		move.position = from_screen.lerp(to_screen,float(i)/8.0)
		move.button_mask = MOUSE_BUTTON_MASK_LEFT
		inputs.append({"event":move,"offset_usec":i*10000})
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = to_screen
	release.pressed = false
	inputs.append({"event":release,"offset_usec":90000})
	if spec.get("timed",false):
		var base_usec := Time.get_ticks_usec()+1000
		var cursor := 0
		while cursor < inputs.size():
			var now := Time.get_ticks_usec()
			while cursor < inputs.size() and base_usec+int(inputs[cursor].offset_usec) <= now:
				var input_event: InputEvent = inputs[cursor].event
				input_event.set_meta("ember_scheduled_usec",base_usec+int(inputs[cursor].offset_usec))
				world.forward_input(camera,input_event)
				cursor += 1
			if cursor < inputs.size(): await process_frame
	else:
		for item in inputs: world.forward_input(camera,item.event)
	var deadline := Time.get_ticks_msec()+60000
	while (world.dragging or not projection.is_projection_complete()) and Time.get_ticks_msec() < deadline: await process_frame
	await process_frame
	_check(not world.dragging and projection.is_projection_complete(),"stroke did not settle: "+spec.name)
	var changed := ground.voxels.duplicate()
	var result: Dictionary = world._trace.stop()
	result.scope = "headless synthetic mouse events routed through EmberWorldEditor.forward_input; not the Godot editor 3D tab"
	result.metadata.editor_viewport = "not available in headless fixture"
	if not result.strokes.is_empty(): result.strokes[0].input_source = "synthetic_forward_input_headless"
	projection.editor_diagnostic_sink = null
	world._trace_button.text = "Начать запись мазков"
	if result.strokes.is_empty():
		_check(false,"no recorded stroke: "+spec.name)
		return {}
	var undo_start := Time.get_ticks_usec()
	history.undo()
	var undo_usec := Time.get_ticks_usec()-undo_start
	_check(ground.voxels == original,"Undo did not fully restore touched data: "+spec.name)
	var redo_start := Time.get_ticks_usec()
	history.redo()
	var redo_usec := Time.get_ticks_usec()-redo_start
	_check(ground.voxels == changed,"Redo did not fully restore touched data: "+spec.name)
	if not spec.get("keep_after",false):
		history.undo()
		_check(ground.voxels == original,"second Undo did not restore starting state: "+spec.name)
	if not spec.get("warmup",false): print("LARGE_STROKE_HISTORY ",spec.name," undo_us=",undo_usec," redo_us=",redo_usec," complete_array_restoration=true")
	var path := "user://qa_world_edit_large_%s.json" % spec.name
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file != null:
		result["secondary_fixture"] = "headless synthetic mouse events through EmberWorldEditor.forward_input; editor preview is not connected in headless, so no visual chunks, frame intervals or visible latency are measured"
		result["undo_usec"] = undo_usec
		result["redo_usec"] = redo_usec
		file.store_string(JSON.stringify(result,"  "))
		file.close()
	return result

func _finish() -> void:
	if _history != null: _history.clear_history()
	for index in [1,2,3,0]:
		if index < _fixture_nodes.size() and is_instance_valid(_fixture_nodes[index]): _fixture_nodes[index].free()
	_fixture_nodes.clear()
	if _history != null: _history.free(); _history = null
	if errors.is_empty(): print("PASS large WorldEditor synthetic input/data/Undo path; live main 3D-tab visual responsiveness remains manual")
	else:
		for error in errors: printerr("FAIL large WorldEditor ",error)
	call_deferred("_quit_after_cleanup",0 if errors.is_empty() else 1)

func _quit_after_cleanup(exit_code: int) -> void:
	await process_frame
	await process_frame
	quit(exit_code)
