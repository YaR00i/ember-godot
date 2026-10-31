extends SceneTree
## Actual terrain-brush commands on an isolated copy of the main map.
const Brush = preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
var failures: Array[String] = []
var frame_ms: Array[float] = []
var last_frame := 0
var sampling := false
var metrics: Dictionary = {}
func _initialize() -> void:
	process_frame.connect(_sample)
	run.call_deferred()
func _sample() -> void:
	var now := Time.get_ticks_usec()
	if sampling and last_frame > 0: frame_ms.append((now-last_frame)/1000.0)
	last_frame = now
func check(value: bool, message: String) -> void:
	if not value: failures.append(message); printerr("FAIL anomaly editing: ",message)
func settle(map: EmberMapLoader, preview := false) -> void:
	var projection: Node = map.get_node("DerivedCompactWorldTerrain")
	var sphere: Node = map.get_node("WorldAnomaly")
	var patch: Node = map.get_node("Props/GrassPatch")
	var stable := 0
	var deadline := Time.get_ticks_msec()+180000
	while stable < 8 and Time.get_ticks_msec()<deadline:
		await process_frame
		var ready: bool = projection.pending_tile_count() == 0 and projection.pending_runtime_lod_count() == 0 and not patch._dirty and not patch._rebuilding and patch._revision == projection.column_revision()
		if preview:
			ready = ready and sphere._prepared and not sphere._preparing
			for binding: Dictionary in sphere._bindings:
				ready = ready and sphere._mesh_of(binding.source) == binding.mesh and (not binding.source is MultiMeshInstance3D or binding.source.multimesh == binding.scatter)
		stable = stable+1 if ready else 0
	check(stable == 8,"preparation settles")
func snapshot_frames(name: String, began: int) -> void:
	frame_ms.sort()
	metrics[name] = {"ms":Time.get_ticks_msec()-began,"max_frame_ms":frame_ms.back() if not frame_ms.is_empty() else 0.0,"p95_frame_ms":frame_ms[int(frame_ms.size()*0.95)] if not frame_ms.is_empty() else 0.0}
	frame_ms.clear()
func run() -> void:
	var scene: Node = load("res://scenes/landscape_compact.tscn").instantiate()
	var map: EmberMapLoader = scene.get_node("Map")
	map.compact_terrain = map.compact_terrain.working_copy()
	var original: PackedInt32Array = map.compact_terrain.heights.duplicate()
	var sphere: Node = map.get_node("WorldAnomaly")
	var began := Time.get_ticks_msec()
	root.add_child(scene); current_scene = scene
	await settle(map,true)
	var deadline := Time.get_ticks_msec()+30000
	while not scene._startup_complete and Time.get_ticks_msec()<deadline: await process_frame
	check(scene._startup_complete and sphere._prepared,"play starts after anomaly preparation")
	metrics.startup_ms = Time.get_ticks_msec()-began
	scene._player.set_physics_process(false);scene._party_followers.set_physics_process(false)
	var untouched: Dictionary = {}
	for binding: Dictionary in sphere._bindings:
		if binding.source is MeshInstance3D and map.get_node("Props").is_ancestor_of(binding.source): untouched[binding.visual.get_instance_id()] = weakref(binding.visual)
	var prepared: int = sphere.preparations
	var patch: Node = map.get_node("Props/GrassPatch")
	var grass_material: Material = patch._visual.material_override
	sphere.set_authoring_active(true)
	var history := UndoRedo.new()
	var brush := Brush.new()
	brush.configure({"target":weakref(map),"resource":map.compact_terrain},history,scene)
	sampling = true;frame_ms.clear()
	for stroke in 2:
		began = Time.get_ticks_msec()
		var cell := Vector2i(50+stroke*5,210)
		# Raise to the highest sampled column. Lowering through an authored
		# material cap is a separate existing brush/history defect.
		var target := 0
		for z in range(cell.y-8,cell.y+9):
			for x in range(cell.x-8,cell.x+9): target = maxi(target,map.compact_terrain.heights[map.compact_terrain.column_index(x,z)])
		target += map.compact_terrain.origin_y+1
		check(brush.begin("level",0.5,1,1,0,16,0,7,0,target,"detail"),"flatten begins")
		brush.stamp(cell);brush.end()
		await settle(map)
		snapshot_frames("stroke_"+str(stroke),began)
		check(metrics["stroke_"+str(stroke)].max_frame_ms < 250.0,"flatten has no blocking quarter-second frame")
		check(sphere.preparations == prepared and not sphere._preview_requested,"brush never schedules anomaly preparation")
		check(patch._visual.material_override == grass_material,"height edit reuses the grass material bank")
		for binding: Dictionary in sphere._bindings: check(not binding.visual.visible,"brush shows authored surface")
	var edited: PackedInt32Array = map.compact_terrain.heights.duplicate()
	check(edited != original,"real brush changes terrain")
	history.undo();history.undo();await settle(map)
	check(map.compact_terrain.heights == original,"brush Undo restores terrain")
	history.redo();history.redo();await settle(map)
	check(map.compact_terrain.heights == edited,"brush Redo restores edits")
	check(sphere.preparations == prepared,"history never schedules anomaly preparation")
	# Interrupt a yielded scatter with a newer editor value. A stale job must
	# never overwrite the replacement density/positions after publication.
	patch._dirty = true
	while not patch._rebuilding: await process_frame
	patch.tufts_per_block = 0.0
	await settle(map)
	check(patch._visual.multimesh.instance_count == 0,"new edit cancels an in-flight scatter")
	patch.tufts_per_block = 100.0
	await settle(map)
	check(patch._visual.multimesh.instance_count > 0,"scatter rebuild recovers after cancellation")
	var saved := "user://anomaly-editing-terrain.res"
	check(ResourceSaver.save(map.compact_terrain,saved) == OK,"save isolated terrain")
	var reopened = ResourceLoader.load(saved,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened.heights == edited and reopened.validation_errors().is_empty(),"terrain save/reopen validates")
	map.compact_terrain.heights = original.duplicate()
	check(ResourceLoader.load(saved,"",ResourceLoader.CACHE_MODE_IGNORE).heights == edited,"discard leaves saved terrain intact")
	map.compact_terrain.heights = edited
	began = Time.get_ticks_msec();frame_ms.clear()
	sphere.request_preview();await settle(map,true)
	snapshot_frames("preview",began)
	check(sphere.preparations == prepared+1,"one explicit preparation after all edits")
	for reference: WeakRef in untouched.values(): check(is_instance_valid(reference.get_ref()),"unchanged prop display survives terrain edits")
	prepared = sphere.preparations
	var builds: int = sphere.Correspondence.builds
	var grouped_tufts := 0
	for binding: Dictionary in sphere._bindings:
		if binding.source is MultiMeshInstance3D and binding.voxel_only: grouped_tufts += binding.visual.multimesh.instance_count
	check(grouped_tufts == patch._visual.multimesh.instance_count,"spatial groups retain every authored tuft exactly once")
	for frame in 60:
		sphere.inner_look = 1+frame%2
		sphere.position.x += 0.1
		await process_frame
	check(sphere.preparations == prepared and sphere.Correspondence.builds == builds,"sphere movement and both looks remain instant")
	sphere.inner_look = 1
	sphere._process(0.0)
	for binding: Dictionary in sphere._bindings:
		if binding.voxel_only: check(not binding.visual.visible,"low-poly preview never submits voxel growth geometry")
	sphere.position += Vector3.ONE*10000.0
	sphere._process(0.0)
	for binding: Dictionary in sphere._bindings: check(not binding.visual.visible and binding.source.layers == binding.layers,"outside field uses original display")
	check(sphere.preparations == prepared,"spatial display selection never prepares geometry")
	sphere.stop_preview()
	check(not sphere._preview_requested,"return to editing")
	for binding: Dictionary in sphere._bindings: check(not binding.visual.visible and binding.source.layers == binding.layers,"editing restores source layers")
	metrics.pass = failures.is_empty();metrics.failures = failures
	metrics.renderer = RenderingServer.get_current_rendering_method()
	metrics.display_server = DisplayServer.get_name()
	metrics.preparations_during_editing = sphere.preparations-prepared
	var file := FileAccess.open("user://anomaly-editing-checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics,"\t"))
	print("WORLD_ANOMALY_EDITING ",JSON.stringify(metrics))
	history.clear_history();history.free();sphere.set_process(false)
	quit(0 if failures.is_empty() else 1)
