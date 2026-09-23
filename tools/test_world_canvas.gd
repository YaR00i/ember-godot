extends SceneTree
const Layout = preload("res://tools/world_canvas_layout.gd")
const World = preload("res://addons/ember_import/ember_world_editor.gd")
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
const Physics = preload("res://scripts/ember_voxel_surface_physics.gd")
var errors: Array[String] = []
var fixture := "user://ember-tests/world-canvas-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]

func _init() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)

func drain(world: Node) -> void:
	var steps := 0
	while world.dragging and steps < 10000:
		world._process(0)
		steps += 1
	check(not world.dragging, "stroke did not finish")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(fixture)
	var protected := {}
	for path in [Layout.SOURCE_PATH, "res://scenes/world_canvas.tscn", "res://scenes/test_pier.tscn", "res://content/world_surfaces/test_pier_surface.tres"]:
		protected[path] = FileAccess.get_sha256(path)
	var source := ResourceLoader.load(Layout.SOURCE_PATH) as EmberVoxelModelResource
	check(source != null and source.validation_errors().is_empty(), "invalid canvas Source")
	if source == null: quit(1); return
	check(source.grid_size() == Vector3i(384,128,400) and source.physical, "wrong canvas grid/physics")
	var size := source.grid_size()
	var wet := 0
	var max_step := 0
	for z in size.z:
		var last := -1
		for x in size.x:
			var top := Physics.solid_height_at(source,Vector2i(x,z))
			check(top >= 11 and top <= 37, "floor outside reserved depth")
			if last >= 0: max_step = maxi(max_step, absi(top-last))
			last = top
			var column := x+z*size.x
			if source.surface_fill_materials[column] != 0:
				wet += 1
				check(source.surface_fill_levels[column] == 32 and top < 31, "water overlaps dry land or has a stepped level")
			else: check(top >= 31, "submerged column has no water")
	check(max_step <= 1, "shore has a steep cliff")
	check(wet > 60000 and wet < 110000, "canvas must contain substantial land and water")
	check(absf(Layout.shoreline(40)-Layout.shoreline(230)) > 20, "shore silhouette is straight")
	var progress := root.get_node("EmberExploreProgress") as EmberExploreState
	progress.set_meta("world_canvas_storage_root", fixture.path_join("play"))
	var scene := (load("res://scenes/world_canvas.tscn") as PackedScene).instantiate()
	scene.scene_file_path = fixture.path_join("world_canvas.tscn")
	# Exercise publication at an already loaded file path, not only creation.
	var fixture_source_path := fixture.path_join("surface.tres")
	check(Store.install_surface_resource(source.duplicate_model(),fixture_source_path).ok, "fixture Source install")
	var initial_cached := ResourceLoader.load(fixture_source_path) as EmberVoxelModelResource
	scene.get_node("Map").visual_surface = initial_cached
	root.add_child(scene)
	current_scene = scene
	var map: EmberMapLoader = scene.get_node("Map")
	check(map.has_authored_content() and map.resolved_visual_surface() == initial_cached, "empty Props triggers legacy import")
	check(scene.get_node("Map/Props").get_child_count() == 0 and scene.get_node("Map/Terrain").get_child_count() == 0, "unexpected decorative floor or props")
	var projection: Node = map._visual_surface_projection
	var start := Time.get_ticks_usec()
	var deadline := Time.get_ticks_msec()+120000
	while not projection.is_projection_complete() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(projection.is_projection_complete(), "projection did not finish")
	print("WORLD_CANVAS_PROFILE initial_projection_ms=", (Time.get_ticks_usec()-start)/1000)
	for i in 20: await physics_frame
	var player := scene.get_node_or_null("Player") as EmberPlayer
	check(player != null and player.is_on_floor(), "hero spawned before Surface physics or fell through ground")
	check(progress.storage_root == fixture.path_join("play") and progress._map_id == Layout.MAP_ID, "play/save namespace leaked")
	var space := map.get_world_3d().direct_space_state
	for point in [Vector3(72.5,50,200.5), Vector3(180.5,50,200.5), Vector3(340.5,50,200.5)]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point,point-Vector3(0,100,0),1))
		var sample := map.surface_floor_sample(point)
		check(not hit.is_empty() and sample.solid and absf(hit.get("position",Vector3.ZERO).y-sample.position.y) < 0.001, "physics differs from displayed floor")
	var water: Dictionary = projection.water_surface_sample(Vector3(340.5,0,200.5))
	check(water.wet and absf(water.position.y-0.085) < 0.001, "water world height does not match sea level")
	var history := UndoRedo.new()
	var world := World.new()
	root.add_child(world)
	world.configure(null,history)
	world.set_process(false)
	root.add_child(world.build_toolbar())
	root.add_child(world.build_sidebar())
	world.scene = scene
	world.map = map
	world.active = true
	world.entry = world.sessions.open_map(map,scene)
	world._refresh_palette()
	world.sessions.recovery_directory = fixture.path_join("recovery")
	var draft: EmberVoxelModelResource = world.entry.resource
	var scope_camera := Camera3D.new()
	scene.add_child(scope_camera)
	scope_camera.position = Vector3(72,120,200)
	scope_camera.look_at(Vector3(72,0,200),Vector3.FORWARD)
	world.camera = scope_camera
	check(world._plane_cell(scope_camera.unproject_position(Vector3(72,0,200))) == Vector2i(4,12), "work-area selection could not resolve native Surface footprint")
	world.camera = null
	scope_camera.free()
	var original := draft.voxels.duplicate()
	world.radius.value = 1
	world._begin_stroke({"hit":Vector3i(63,37,63),"normal":Vector3i.UP})
	world.released = true
	drain(world)
	check(draft.voxels != original, "seam-crossing raise changed nothing")
	history.undo()
	check(draft.voxels == original, "raise Undo did not restore Source")
	history.redo()
	world._begin_stroke({"hit":Vector3i(63,41,63),"normal":Vector3i.UP})
	world._process(0)
	world.cancel_stroke()
	history.undo()
	check(draft.voxels == original, "cancel/Undo lost saved terrain")
	world.category.select(1)
	world._category_changed(1)
	world.radius.value = 0.25
	world.palette.select(2)
	var wall_index := World.Model.index_of(Vector3i(0,25,63),size)
	world._begin_stroke({"hit":Vector3i(0,25,63),"normal":Vector3i.LEFT})
	world.released = true
	drain(world)
	check(draft.voxels[wall_index] == 3, "vertical wall paint failed")
	var original_levels := draft.surface_fill_levels.duplicate()
	world.category.select(2)
	world._category_changed(2)
	world.water_height.value = 2
	world._begin_stroke({"hit":Vector3i(340,11,200),"normal":Vector3i.UP})
	world.released = true
	drain(world)
	check(draft.surface_fill_levels[340+200*size.x] == 34, "water brush did not change level")
	history.undo()
	check(draft.surface_fill_levels == original_levels, "water Undo lost initial fill")
	world.sessions.save_scene = func() -> int:
		var saved := PackedScene.new()
		var result := saved.pack(scene)
		return ResourceSaver.save(saved,scene.scene_file_path) if result == OK else result
	var save_start := Time.get_ticks_usec()
	check(world.save_all(), "shared canvas Save: "+world.sessions.error)
	check(initial_cached.voxels == original and map.visual_surface.voxels == draft.voxels and world.sessions.same_data(world.entry.source_resource,world.entry.baseline), "publication mutated baseline or kept stale Source cache")
	print("WORLD_CANVAS_PROFILE shared_save_ms=", (Time.get_ticks_usec()-save_start)/1000)
	var reopened_source := ResourceLoader.load(scene.scene_file_path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if reopened_source != null:
		var reopened := reopened_source.instantiate()
		check(reopened.get_node("Map").visual_surface.voxels[wall_index] == 3 and reopened.get_node("Map").surface_origin == Layout.ORIGIN, "Save/reopen lost wall/origin")
		reopened.free()
	else: check(false, "saved scene could not be reopened")
	history.undo()
	check(draft.voxels == original, "post-Save paint Undo did not restore initial canvas")
	check(world.save_all(), "repeat Save after Undo: "+world.sessions.error)
	world.sessions.discard(scene)
	world.sessions.release()
	world.toolbar.free()
	world.sidebar.free()
	world.free()
	history.free()
	root.remove_child(scene)
	scene.free()
	for path in protected: check(FileAccess.get_sha256(path) == protected[path], "test overwrote authored file: "+path)
	if errors.is_empty(): print("PASS WORLD_CANVAS native source, gentle shore, water, real play physics, wall paint, seam Undo/cancel, shared Save/reopen")
	else:
		for error in errors: printerr("FAIL WORLD_CANVAS ", error)
	quit(0 if errors.is_empty() else 1)
