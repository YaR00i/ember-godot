extends SceneTree
const World = preload("res://addons/ember_import/ember_world_editor.gd")
const Sessions = preload("res://addons/ember_import/ember_world_edit_sessions.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
const ProjectionScript = preload("res://scripts/ember_voxel_surface_projection.gd")
const Physics = preload("res://scripts/ember_voxel_surface_physics.gd")
var errors: Array[String] = []
var fixture := "user://ember-tests/world-editor-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()]

func _init() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)

func drain(world: Node) -> void:
	var count := 0
	while world.dragging and count < 10000:
		world._process(0)
		count += 1
	check(not world.dragging,"incremental stroke did not finish")

func _run() -> void:
	var scene := Node3D.new()
	scene.name = "WorldFixture"
	scene.scene_file_path = fixture.path_join("world.tscn")
	root.add_child(scene)
	var map := EmberMapLoader.new()
	map.name = "Map"
	map.map_id = "world_editor_fixture_%d" % OS.get_process_id()
	map.hydrate_legacy_regions = false
	map.authored_size_blocks = Vector2i(4,4)
	scene.add_child(map)
	map.owner = scene
	var history := UndoRedo.new()
	var world := World.new()
	root.add_child(world)
	world.configure(null,history)
	world.sessions.recovery_directory = fixture.path_join("recovery")
	world.set_process(false)
	var top := world.build_toolbar()
	var side := world.build_sidebar()
	root.add_child(top)
	root.add_child(side)
	world.scene = scene
	world.map = map
	world.active = true
	world.edit_region = Rect2i(1,1,2,2)
	world._create_ground()
	world.entry.path = fixture.path_join("world_surface.tres")
	drain(world)
	var ground: EmberVoxelModelResource = world.entry.resource
	var size := ground.grid_size()
	var index := Model.index_of(Vector3i(24,31,24),size)
	check(ground.voxels[index] == 1,"foundation missing at requested top")
	check(ground.voxels[0] == 0,"foundation changed outside selected rectangle")
	check(world.sessions.dirty_count(scene) == 1,"ground draft not dirty")
	history.undo()
	check(ground.voxels[index] == 0,"foundation Undo failed")
	history.redo()
	check(ground.voxels[index] == 1,"foundation Redo failed")
	world.category.select(2)
	world._category_changed(2)
	world.water_height.value = 3
	world.clip.button_pressed = false
	world.radius.value = 0.25
	world._begin_stroke({"hit":Vector3i(24,31,24),"normal":Vector3i.UP})
	world.released = true
	drain(world)
	check(ground.surface_fill_levels[24+24*size.x] == 35,"world water level did not include negative ground origin")
	var rendered_water_layer := EmberVoxelSurfaceMesher.water_height_at(ground,Vector2i(24,24))
	check(is_equal_approx((rendered_water_layer+1.0)*map.imported_tile_size/ground.normalized_density()+world.entry.origin.y,3.0),"rendered water top differs from requested world height")
	history.undo()
	check(ground.surface_fill_levels.is_empty() and ground.surface_fill_palette.is_empty(),"water Undo failed to restore legacy empty channels")
	history.redo()
	check(ground.surface_fill_levels[24+24*size.x] == 35,"water Redo failed")
	world.water_height.value = -100
	world._begin_stroke({"hit":Vector3i(24,31,24),"normal":Vector3i.UP})
	check(not world.dragging and ground.surface_fill_levels[24+24*size.x] == 35,"out-of-grid water height silently clamped to another level")
	world.category.select(0)
	world._category_changed(0)
	world.edit_region = Rect2i()
	world._begin_stroke({"hit":Model.INVALID_CELL,"adjacent":Vector3i(4,32,4),"normal":Vector3i.UP,"empty_floor":true})
	world.released = true
	drain(world)
	check(Model._top_filled_y(ground.voxels,size,4,4) >= 32,"empty-space raise grew at grid bottom, not construction plane")
	world._begin_stroke({"hit":Vector3i(4,35,4),"normal":Vector3i.UP})
	world._process(0)
	var before_cancel: PackedByteArray = world.baseline.voxels
	world.cancel_stroke()
	check(ground.voxels == before_cancel,"Esc changed source")
	# The world session reuses ObjectSession's unique fork and exact adapters.
	var source := EmberVoxelModelResource.new()
	source.model_id = "world_object"
	source.display_name = "World object"
	source.voxels_per_block = 16
	source.height_voxels = 2
	source.palette = PackedColorArray([Color.TRANSPARENT,Color.RED,Color.BLUE])
	source.voxels.resize(512)
	source.voxels.fill(1)
	var source_path := fixture.path_join("sources/world_object.tres")
	var prefab_path := fixture.path_join("prefabs/world_object.tscn")
	check(Store.install_prepared_asset(source,EmberVoxelPrefab.prepare_resource(source),source_path,prefab_path).ok,"object fixture install")
	var packed := load(prefab_path) as PackedScene
	var a := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as EmberVoxelProp
	var b := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as EmberVoxelProp
	a.name = "A"
	b.name = "B"
	scene.add_child(a)
	scene.add_child(b)
	a.owner = scene
	b.owner = scene
	a.rotation = Vector3(0.2,0.7,0.1)
	a.scale = Vector3(1.3,0.8,1.1)
	a.position = Vector3(30,2,40)
	var pose := a.transform
	world.sessions.source_directory = fixture.path_join("sources")
	world.sessions.prefab_directory = fixture.path_join("prefabs")
	var object_entry: Dictionary = world.sessions.open_object(a,scene)
	check(not object_entry.is_empty(),"object open: " + world.sessions.error)
	if object_entry.is_empty(): _finish(); return
	var anchor: Transform3D = world.sessions.frame(object_entry)
	var mesh: MeshInstance3D = a.get_node("Mesh")
	check(anchor == a.global_transform*mesh.transform,"rotated/scaled object frame")
	object_entry.resource.voxels[0] = 0
	check(world.sessions.dirty_count(scene) == 2,"switching target lost a dirty draft")
	var canvas := EmberVoxelSculptWorkspace.new()
	root.add_child(canvas)
	canvas.setup(null,history)
	check(canvas.open_world_draft(object_entry,world.sessions,world.save_all),"Canvas shared open")
	check(canvas._resource == object_entry.resource and canvas.has_unsaved_changes(),"Canvas forked/reset world draft")
	check(canvas.open_world_draft(world.entry,world.sessions,world.save_all),"Canvas target switch")
	check(world.sessions.dirty_count(scene) == 2,"Canvas switch dropped object draft")
	world.sessions.save_scene = func() -> int:
		var next := PackedScene.new()
		var error := next.pack(scene)
		return ResourceSaver.save(next,scene.scene_file_path) if error == OK else error
	var saved: bool = world.save_all()
	check(saved,"common Save: " + world.sessions.error)
	if not saved: _finish(); return
	check(a.model_id != b.model_id and b.model_id == "world_object","Save changed other instance")
	check(a.transform == pose and mesh.visible,"Save modified pose/authored visibility")
	check(world.sessions.dirty_count(scene) == 0,"common Save did not accept baselines")
	check((ResourceLoader.load(world.entry.path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource).voxels == ground.voxels,"ground save/reopen")
	var reopened := (ResourceLoader.load(scene.scene_file_path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("A").model_id == a.model_id and reopened.get_node("B").model_id == "world_object","scene reopen lost unique bindings")
	check(reopened.get_node("Map").surface_origin == Vector3(0,-32,0),"origin serialization")
	reopened.free()
	var file_hash := FileAccess.get_sha256(world.entry.path)
	ground.voxels[index] = 2
	object_entry.resource.voxels[1] = 0
	var object_hash := FileAccess.get_sha256(object_entry.path)
	Store.asset_rename_override = func(from_path: String,to_path: String) -> int:
		return ERR_FILE_CANT_WRITE if to_path.ends_with(".tscn") else DirAccess.rename_absolute(ProjectSettings.globalize_path(from_path),ProjectSettings.globalize_path(to_path))
	check(not world.save_all(),"injected publication failure accepted")
	Store.asset_rename_override = Callable()
	check(FileAccess.get_sha256(world.entry.path) == file_hash and FileAccess.get_sha256(object_entry.path) == object_hash,"multi-asset failure did not restore exact bytes")
	check(world.sessions.dirty_count(scene) == 2,"Save failure lost drafts")
	world.sessions.save_scene = func() -> int: return ERR_FILE_CANT_WRITE
	check(not world.save_all(),"scene Save failure accepted")
	check(FileAccess.get_sha256(world.entry.path) == file_hash and FileAccess.get_sha256(object_entry.path) == object_hash,"scene failure did not rollback assets")
	# Native menu Save invokes external-data hooks after its initial scene pack.
	# Preparation must not recurse into that Save or accept drafts prematurely.
	var recursive_save := [false]
	world.sessions.save_scene = func() -> int: recursive_save[0] = true; return OK
	check(world.sessions.save_all(scene,true),"native menu Save preparation failed")
	check(not recursive_save[0] and world.sessions.saving and world.sessions.dirty_count(scene) == 2,"native Save recursed/accepted drafts before final scene publication")
	check(not world.sessions.finish_native_save(ERR_FILE_CANT_WRITE),"late native Save failure accepted")
	check(FileAccess.get_sha256(world.entry.path) == file_hash and FileAccess.get_sha256(object_entry.path) == object_hash and world.sessions.dirty_count(scene) == 2,"late native Save did not restore assets and drafts")
	world.sessions.discard(scene)
	check(world.sessions.dirty_count(scene) == 0,"Discard did not restore saved drafts")
	check(world.sessions.save_all(scene,true),"native Save retry preparation failed")
	var native_pending: Dictionary = world.sessions.pending_native_save
	check(ResourceSaver.save(native_pending.packed,native_pending.path) == OK,"owned native PackedScene publication failed")
	check(world.sessions.finish_native_save(OK) and world.sessions.dirty_count(scene) == 0,"native final Save did not accept baselines")
	# Undo still addresses the same draft after publication, not the cached asset.
	world.actions.apply_stroke(ground,{index:{"before":ground.voxels[index],"after":3}})
	history.undo()
	check(world.sessions.dirty_count(scene) == 0 and FileAccess.get_sha256(world.entry.path) == file_hash,"Undo after Save changed disk or detached the draft")
	history.redo()
	check(world.sessions.dirty_count(scene) == 1,"Redo after Save no longer addresses shared draft")
	world.sessions.discard(scene)
	ground.voxels[index] = 2
	var external := ResourceLoader.load(world.entry.path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	external.voxels[index] = 3
	check(ResourceSaver.save(external,world.entry.path) == OK,"external conflict fixture save")
	var external_hash := FileAccess.get_sha256(world.entry.path)
	check(not world.save_all() and FileAccess.get_sha256(world.entry.path) == external_hash and ground.voxels[index] == 2,"external file conflict overwritten/lost draft")
	check(Store.restore_surface_snapshot(Store._snapshot_file(scene.scene_file_path),scene.scene_file_path) == OK,"scene byte restore fixture")
	world.entry.hash = external_hash
	world.sessions.discard(scene)
	# Crash-cache restore must not replace a newer, already dirty draft.
	object_entry.resource.voxels[1] = 0
	world.sessions.write_recovery()
	world.sessions.discard(scene)
	var restored_count: int = world.sessions.restore_recovery(scene)
	check(restored_count == 1 and object_entry.resource.voxels[1] == 0,"editor-only recovery missing: count=%d %s" % [restored_count,world.sessions.error])
	object_entry.resource.voxels[2] = 0
	check(world.sessions.restore_recovery(scene) == 0 and object_entry.resource.voxels[2] == 0,"recovery replaced newer draft")
	world.entry = object_entry
	world.edit_region = Rect2i()
	var grab_before: EmberVoxelModelResource = object_entry.resource.duplicate_model()
	world.grab = {"baseline":grab_before,"frame":world.sessions.frame(object_entry),"plane":Plane(Vector3.UP,0),"anchor":Vector3.ZERO,"center":Vector3(1,1,8),"position":Vector2.ZERO,"pending":false,"released":true,"displacement":Vector3(3,0,0),"planned":Vector3.ZERO,"job":null,"plan":{},"radius":8.0}
	for iteration in 10000:
		world._process_grab()
		if world.grab.is_empty(): break
	check(world.grab.is_empty() and object_entry.resource.voxels != grab_before.voxels,"native world soft grab did not finish/apply: "+world.status.text)
	history.undo()
	check(object_entry.resource.voxels == grab_before.voxels and a.transform == pose,"soft grab Undo/transform drift")
	world.entry = world.sessions.entries[map.get_instance_id()]
	a.free()
	check(not world.save_all() and object_entry.resource.voxels[2] == 0,"deleted target lost draft/accepted Save")
	world.sessions.discard(scene)
	_closed_native_save_test()
	_partition_test()
	await _projection_test()
	_profile()
	history.clear_history()
	world.actions.configure(null)
	canvas._actions.configure(null)
	world.sessions.undo = null
	canvas.free()
	world.free()
	top.free()
	side.free()
	scene.free()
	history.free()
	_finish()

func _closed_native_save_test() -> void:
	var scene := Node3D.new()
	scene.name = "ClosedFixture"
	scene.scene_file_path = fixture.path_join("closed.tscn")
	root.add_child(scene)
	var map := EmberMapLoader.new()
	map.name = "Map"
	map.map_id = "closed_world_%d" % OS.get_process_id()
	map.hydrate_legacy_regions = false
	map.authored_size_blocks = Vector2i.ONE
	scene.add_child(map)
	map.owner = scene
	var initial := PackedScene.new()
	check(initial.pack(scene) == OK and ResourceSaver.save(initial,scene.scene_file_path) == OK,"closed fixture baseline scene")
	var sessions := Sessions.new()
	sessions.recovery_directory = fixture.path_join("closed-recovery")
	var entry := sessions.create_ground(map,scene)
	entry.path = fixture.path_join("closed_surface.tres")
	entry.resource.voxels[0] = 1
	sessions.write_recovery()
	sessions.release()
	scene.free()
	var reopened := (load(fixture.path_join("closed.tscn")) as PackedScene).instantiate()
	root.add_child(reopened)
	var recovered := Sessions.new()
	recovered.recovery_directory = fixture.path_join("closed-recovery")
	check(recovered.restore_recovery(reopened) == 1,"blank-ground recovery after root destruction")
	var recovered_entry: Dictionary = recovered.entries[reopened.get_node("Map").get_instance_id()]
	check(recovered_entry.path == fixture.path_join("closed_surface.tres"),"recovery lost original publication path")
	check(recovered.save_all(reopened,true),"prepare native Save-and-close snapshot")
	var pending: Dictionary = recovered.pending_native_save
	reopened.free()
	check(ResourceSaver.save(pending.packed,pending.path) == OK and recovered.finish_native_save(OK),"native owned scene save lost a closed target")
	var result := (ResourceLoader.load(pending.path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(result.get_node("Map").visual_surface.voxels[0] == 1 and result.get_node("Map").surface_origin == Vector3(0,-32,0),"closed scene lost recovered Surface binding/origin")
	result.free()
	recovered.release()

func _projection_test() -> void:
	# The common volume brush can expose an underside: collision must not fill
	# that visible gap with a heightfield wall, including the adjacent seam.
	var ledge := Model.make_native_world_surface("ledge",Vector2i(2,1),8)
	var ledge_size := ledge.grid_size()
	ledge.voxels[Model.index_of(Vector3i(16,4,4),ledge_size)] = 1
	var exact := Physics.build_collision_region_result(ledge,Vector3i(16,0,0),Vector3i(16,8,16),1.0)
	check(exact.get("volumetric",false),"floating ledge used an invented heightfield volume")
	var faces: PackedVector3Array = exact.mesh.get_faces()
	var lowest := INF
	for vertex in faces: lowest = minf(lowest,vertex.y)
	check(is_equal_approx(lowest,4.0),"ledge collider filled the gap below visible voxels")
	check(Physics.build_collision_region_result(ledge,Vector3i.ZERO,Vector3i(16,8,16),1.0).get("volumetric",false),"ledge seam neighbour used incompatible heightfield walls")
	var surface := Model.make_native_world_surface("regional",Vector2i(4,4),32)
	for z in 64:
		for x in 64: surface.voxels[Model.index_of(Vector3i(x,0,z),surface.grid_size())] = 1
	var projection := ProjectionScript.new()
	root.add_child(projection)
	projection.configure(surface,16,Vector2i(4,4),null,true)
	while projection.drain_next_chunk(): pass
	while projection.drain_next_physics_chunk(): pass
	var untouched: MeshInstance3D = projection._chunks[Vector2i(3,3)]
	var mesh := untouched.mesh
	var index := Model.index_of(Vector3i(16,1,16),surface.grid_size())
	surface.voxels[index] = 1
	surface.notify_geometry_changed(PackedInt32Array([index]))
	check(projection.pending_chunk_count() <= 3,"small edit queued full map remesh")
	while projection.drain_next_chunk(): pass
	while projection.drain_next_physics_chunk(): pass
	check(untouched.mesh == mesh,"unrelated chunk rebuilt")
	check(not Physics.build_collision_region_result(surface,Vector3i.ZERO,Vector3i(16,32,16),1.0).get("volumetric",false),"ordinary ground lost accelerated heightfield collision")
	projection.position.y = -32
	check(is_equal_approx(projection.floor_surface_sample(Vector3(16,-30,16)).position.y,-30),"offset collision/floor sample mismatch")
	projection.free()
	# Immutable initial heightfield must incorporate edits arriving before drain.
	var initial := Model.make_native_world_surface("initial_edit",Vector2i(4,4),32)
	var starting := ProjectionScript.new()
	root.add_child(starting)
	starting.configure(initial,16,Vector2i(4,4),null,true)
	var changed_index := Model.index_of(Vector3i(3,0,3),initial.grid_size())
	initial.voxels[changed_index] = 1
	initial.notify_geometry_changed(PackedInt32Array([changed_index]))
	while starting.drain_next_physics_chunk(): pass
	check(not starting._collision_chunks.is_empty(),"initial asynchronous collision dropped arriving stroke")
	initial.voxels[changed_index] = 0
	initial.notify_geometry_changed(PackedInt32Array([changed_index]))
	while starting.drain_next_physics_chunk(): pass
	check(starting._collision_chunks.is_empty() and not starting._physics_live,"last terrain removal left stale collision")
	starting.free()

func _partition_test() -> void:
	var surface := Model.make_native_world_surface("partition",Vector2i(4,4),32)
	for z in 64:
		for x in 64:
			for y in 6: surface.voxels[Model.index_of(Vector3i(x,y,z),surface.grid_size())] = 1
	for mode in ["raise","lower","paint","sand","smooth","level","shore"]:
		var next := Model.StrokeJob.new()
		next.source = surface
		next.from = Vector3i(14,5,18)
		next.to = Vector3i(36,5,21)
		next.radius = 12
		next.depth = 3
		next.palette = 3
		next.mode = mode
		next.options = {"level":8,"secondary":2,"shore":{"origin":Vector2(14,18),"height":5,"direction":0,"width":32,"roughness":15}}
		next.initialize()
		var collected := {}
		while not next.done: collected.merge(next.step(4000),true)
		var expected := {}
		match mode:
			"raise","lower": expected = Model.relief_segment_changes(surface,surface.voxels,next.from,next.to,Model.TOOL_RAISE if mode == "raise" else Model.TOOL_LOWER,3,12,3)
			"paint": expected = Model.oriented_stroke_changes(surface,surface.voxels,next.to,Vector3i.UP,Model.TOOL_PAINT,3,12,3)
			"sand": expected = Model.surface_pattern_segment_changes(surface,next.from,next.to,3,2,12,24,35,371)
			"smooth": expected = Model.smooth_segment_changes(surface,surface.voxels,next.from,next.to,3,12,3,false,{}, {},PackedInt32Array(),false,true)
			"level": expected = Model.level_segment_changes(surface,next.from,next.to,8,3,12)
			"shore": expected = Model.generative_relief_segment_changes(surface,surface.voxels,next.from,next.to,3,12,3,32,1,371,0,"shore",false,{}, {},PackedInt32Array(),{},next.options.shore)
		check(collected == expected,"tile partition changed global falloff/preview for "+mode)
	# Tangent-oriented paint includes vertical exposed voxel faces.
	var vertical := Model.StrokeJob.new()
	vertical.source = surface
	vertical.from = Vector3i(0,3,20)
	vertical.to = vertical.from
	vertical.normal = Vector3i.LEFT
	vertical.mode = "paint"
	vertical.palette = 3
	vertical.radius = 3
	vertical.depth = 1
	vertical.initialize()
	var wall := {}
	while not vertical.done: wall.merge(vertical.step(),true)
	check(wall.has(Model.index_of(vertical.to,surface.grid_size())),"vertical bank paint skipped side face")
	var water := Model.StrokeJob.new()
	water.source = surface
	water.from = Vector3i(20,5,20)
	water.to = water.from
	water.radius = 24
	water.mode = "water"
	water.options = {"level":12}
	water.region = Rect2i(16,16,16,16)
	var protected_index := Model.index_of(Vector3i(20,5,20),surface.grid_size())
	surface.voxel_groups = [{"id":"protected","locked":true,"indices":PackedInt32Array([protected_index])}]
	water.initialize()
	var wet := {}
	while not water.done: wet.merge(water.step(),true)
	check(not wet.has(20+20*64),"water edited locked column")
	for column in wet: check(water.region.has_point(Vector2i(column%64,column/64)),"water escaped global work rectangle")
	var copied := surface.duplicate_model()
	copied.voxels[0] = 3
	copied.voxel_groups[0].indices[0] = 0
	check(surface.voxels[0] == 1 and surface.voxel_groups[0].indices[0] == protected_index,"draft/metadata copy aliases its source")

func _profile() -> void:
	var started := Time.get_ticks_usec()
	var surface := Model.make_native_world_surface("full_pier_profile",Vector2i(24,25))
	var allocation_usec := Time.get_ticks_usec()-started
	check(surface != null and surface.voxels.size() == 19660800,"full Pier footprint was reduced to object limits")
	var next := Model.StrokeJob.new()
	next.source = surface
	next.from = Vector3i(192,32,192)
	next.to = next.from
	next.radius = 64
	next.depth = 4
	next.options = {"empty_floor":31}
	next.initialize()
	var history_bytes := 0
	var peak := 0
	var calculation_usec := 0
	var apply_usec := 0
	var values := surface.voxels.duplicate()
	var pairs := {}
	while not next.done:
		var start := Time.get_ticks_usec()
		var changes: Dictionary = next.step(4000)
		var elapsed := Time.get_ticks_usec()-start
		peak = maxi(peak,elapsed)
		calculation_usec += elapsed
		history_bytes += changes.size()*6
		start = Time.get_ticks_usec()
		for index in changes:
			values[index] = changes[index].after
			pairs[index] = Vector2i(changes[index].before,changes[index].after)
		apply_usec += Time.get_ticks_usec()-start
	surface.voxels = values
	var profile_history := UndoRedo.new()
	var profile_actions := EmberVoxelSculptActions.new()
	profile_actions.configure(profile_history)
	var memory_before := OS.get_static_memory_usage()
	var history_started := Time.get_ticks_usec()
	profile_actions.commit_applied_delta(surface,{"voxels":pairs},PackedInt32Array(pairs.keys()),"Full Pier profile")
	var history_usec := Time.get_ticks_usec()-history_started
	var retained_history_bytes := OS.get_static_memory_usage()-memory_before
	print("  full Pier profile: grid=%d bytes, allocation=%dms, calculation=%dms, peak calculation step=%dus, apply+delta=%dms, history pack=%dms, packed history payload=%d bytes, static history growth=%d bytes" % [surface.voxels.size(),allocation_usec/1000,calculation_usec/1000,peak,apply_usec/1000,history_usec/1000,history_bytes,retained_history_bytes])
	profile_history.clear_history()
	profile_actions.configure(null)
	profile_history.free()
	pairs.clear()
	var projection := ProjectionScript.new()
	root.add_child(projection)
	projection.set_process(false)
	var initial_started := Time.get_ticks_usec()
	projection.configure(surface,16,Vector2i(24,25),null,true)
	while projection.drain_next_chunk(): pass
	while projection.drain_next_physics_chunk(): pass
	var initial_usec := Time.get_ticks_usec()-initial_started
	var touched := Model.index_of(Vector3i(192,31,192),surface.grid_size())
	surface.voxels[touched] = 2
	surface.notify_geometry_changed(PackedInt32Array([touched]))
	var visual_count := projection.pending_chunk_count()
	var physics_count := projection.pending_physics_chunk_count()
	var regional_started := Time.get_ticks_usec()
	while projection.drain_next_chunk(): pass
	var visual_usec := Time.get_ticks_usec()-regional_started
	regional_started = Time.get_ticks_usec()
	while projection.drain_next_physics_chunk(): pass
	var physics_usec := Time.get_ticks_usec()-regional_started
	print("  full Pier projection: initial all chunks+physics=%dms; regional visual=%dms/%d chunks, physics=%dms/%d chunks (CPU fixture, not FPS)" % [initial_usec/1000,visual_usec/1000,visual_count,physics_usec/1000,physics_count])
	check(visual_count <= 3 and physics_count <= 3,"full Pier single edit rebuilt unrelated regions")
	projection.free()
	check(Model.make_native_world_surface("oversized",Vector2i(128,128)) == null,"unsafe allocation not rejected")

func _finish() -> void:
	if errors.is_empty(): print("PASS world editor: native UI, draft switching, common Save/reopen/rollback, unique objects, sparse history, regional physics and full Pier profile")
	else:
		for error in errors: printerr("FAIL world editor: ",error)
	quit(0 if errors.is_empty() else 1)
