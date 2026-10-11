extends "res://tools/test_terrain_plan_lake.gd"
const Grove = preload("res://addons/ember_import/ember_grove_planner.gd")
const Export = preload("res://addons/ember_import/ember_terrain_cache_export.gd")
const ROOT := "user://ember-tests/grove"
var _map: EmberMapLoader
var _scene: Node3D
var _catalog := {}

func make_tree(id: String, color: Color) -> PackedScene:
	var prop := EmberVoxelProp.new(); prop.name = id; prop.model_id = id
	var visual := MeshInstance3D.new(); visual.name = "Mesh"; visual.mesh = BoxMesh.new(); visual.mesh.size = Vector3(8,32,8); visual.position.y = 16
	var material := StandardMaterial3D.new(); material.albedo_color = color; visual.material_override = material
	prop.add_child(visual); visual.owner = prop
	var body := StaticBody3D.new(); body.name = "Collision"; prop.add_child(body); body.owner = prop
	var shape := CollisionShape3D.new(); shape.name = "Shape"; shape.shape = BoxShape3D.new(); shape.shape.size = Vector3(8,32,8); shape.position.y = 16
	body.add_child(shape); shape.owner = prop
	var packed := PackedScene.new(); check(packed.pack(prop) == OK,"pack tree"); prop.free()
	var path := ROOT.path_join(id+".tscn"); check(ResourceSaver.save(packed,path) == OK,"save tree")
	return ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene

func plan() -> Resource:
	var result := Plan.new(); result.schema_version = Plan.VERSION
	var values := Plan.Influence.GROVE_DEFAULTS.duplicate(true); values.model_ids = PackedStringArray(["vox_fixture_tree_a","vox_fixture_tree_b"]); values.density = 1.0; values.spacing_m = 5.0
	result.regions = [{"id":"grove","name":"Роща","kind":"grove","enabled":true,"bounds":Rect2i(8,8,24,24),"parameters":values},
		{"id":"road","name":"Дорога","kind":"road","enabled":true,"bounds":Rect2i(0,20,45,9),"points_m":PackedVector2Array([Vector2(4,24),Vector2(40,24)]),"parameters":Plan.Influence.ROAD_DEFAULTS.duplicate(true)}]
	return result

func prepare(source: Resource, input: Resource, budget := 4000) -> RefCounted:
	var job := Grove.new(); check(job.begin(source,_map,_scene,input,_catalog),job.error)
	if not job.error.is_empty(): return job
	var timeout := Time.get_ticks_msec()+30000
	while not job.finished and Time.get_ticks_msec() < timeout: job.step(budget)
	check(job.finished and job.error.is_empty(),job.error)
	return job

func attach(job: RefCounted) -> Dictionary:
	var delta: Dictionary = job.finalize(_map.get_node("Props")); check(not delta.is_empty(),job.error)
	if not delta.is_empty(): Grove.apply_delta(delta,true); _map.set_meta(Plan.META,delta.plan)
	return delta

func _run() -> void:
	for packed in [PackedByteArray([1,2,3]),PackedStringArray(["tree","leaf"]),PackedVector3Array([Vector3(1,2,3)])]:
		check(Grove._canonical(packed) == Grove._canonical(packed.duplicate()),"packed geometry fingerprint unstable")
	check(Grove._canonical(PackedByteArray([1,2,3])) != Grove._canonical(PackedByteArray([1,2,4])),"packed geometry change missed")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	_catalog = {"vox_fixture_tree_a":make_tree("vox_fixture_tree_a",Color.GREEN),"vox_fixture_tree_b":make_tree("vox_fixture_tree_b",Color.DARK_GREEN)}
	var source := fixture(); var initial: Resource = source.working_copy()
	check(ResourceSaver.save(source,ROOT.path_join("terrain.res")) == OK,"save terrain")
	_scene = Node3D.new(); _scene.scene_file_path = ROOT.path_join("map.tscn"); root.add_child(_scene)
	_map = EmberMapLoader.new(); _map.name = "Map"; _map.hydrate_legacy_regions = false; _map.compact_terrain = load(ROOT.path_join("terrain.res")); _map.authored_size_blocks = Vector2i(48,48)
	_scene.add_child(_map); _map.owner = _scene
	if _map.get_node_or_null("Props") == null:
		var props := Node3D.new(); props.name = "Props"; _map.add_child(props); props.owner = _scene
	await process_frame
	var input := plan(); var first := prepare(source,input)
	var panel := LakePanel.new(); root.add_child(panel)
	panel.open_grove(input.regions[0].bounds,input.regions[0].parameters,[{"id":"vox_fixture_tree_a","title":"Дерево A"},{"id":"vox_fixture_tree_b","title":"Дерево B"}])
	check(panel.parameters().model_ids.size() == 2 and panel.parameters().density == 1.0,"grove panel recipe roundtrip")
	panel.size = Vector2(302,560); await process_frame
	check(panel.get_combined_minimum_size().x <= 302,"grove panel overflow")
	panel.set_ready("Готово"); panel._grove_fields.spacing_m.value = 5.5
	check(panel.get_apply_button().disabled,"grove stale panel Apply")
	panel.open_influence(Rect2i(8,8,12,12),Plan.Influence.ROAD_DEFAULTS,"road")
	check(not panel._grove_grid.is_visible_in_tree() and panel._road_grid.is_visible_in_tree(),"grove fields leaked into road mode")
	panel.queue_free(); await process_frame
	check(first.placements.size() > 4 and first.placements.size() <= 64,"grove points")
	check(source.same_terrain_data(initial) and input.object_layers.is_empty(),"source/plan modified")
	var other := prepare(source,input,800)
	check(other.placements == first.placements,"budget changes placement")
	var new_seed: Resource = input.working_copy(); new_seed.regions[0].parameters.seed += 1
	check(prepare(source,new_seed).placements != first.placements,"seed does not change placement")
	var wet_plan: Resource = input.working_copy(); wet_plan.regions[0].bounds = Rect2i(0,0,18,18)
	var wet_job := prepare(source,wet_plan)
	for spec in wet_job.placements: check(spec.point.y >= 6.5,"tree foot intersects water")
	var dense: Resource = input.working_copy(); dense.regions[0].bounds = Rect2i(0,0,48,48); dense.regions[0].parameters.spacing_m = 2.0
	var dense_job := Grove.new(); check(dense_job.begin(source,_map,_scene,dense,_catalog),"dense setup")
	while not dense_job.finished: dense_job.step()
	check(not dense_job.error.is_empty(),"tree cap silently exceeded")
	var cancelled_job := Grove.new(); check(cancelled_job.begin(source,_map,_scene,input,_catalog),"cancel setup"); cancelled_job.cancel(); cancelled_job.step()
	check(cancelled_job.placements.is_empty(),"cancel created points")
	var blocker := MeshInstance3D.new(); blocker.name = "ManualBlocker"; blocker.mesh = BoxMesh.new(); blocker.mesh.size = Vector3(32,32,32)
	blocker.position = first.placements[0].transform.origin+Vector3.UP*16; _map.get_node("Props").add_child(blocker); blocker.owner = _scene
	var blocked := prepare(source,input)
	check(not blocked.placements.any(func(spec): return spec.point.distance_to(first.placements[0].point) < 2),"manual object not excluded")
	blocker.position.x += 1; check(blocked.stale(),"changed obstacle did not invalidate preview")
	blocker.queue_free(); await process_frame
	for spec in first.placements:
		check(absf(spec.point.y-24.0) > 4.0,"tree on road corridor")
		check(spec.transform.origin.y == 96,"tree height disagrees with physical source")
	for i in first.placements.size():
		for j in i: check(first.placements[i].point.distance_to(first.placements[j].point) >= 5.0,"spacing")
	var delta := attach(first)
	if delta.is_empty(): quit(1); return
	check(delta.plan.validation_errors(Vector2i(48,48)).is_empty(),"output validation")
	for member in delta.plan.object_layers.grove:
		var prop := _map.get_node("Props").get_node(NodePath(member.id)) as EmberVoxelProp
		check(Grove.fingerprint(prop,_map,first._frame) == member.expected,"applied tree fingerprint differs")
	var repeat := prepare(source,delta.plan); var repeated: Dictionary = repeat.finalize(_map.get_node("Props"))
	check(repeat.protected_members.is_empty(),"untouched trees protected")
	check(Plan.same(repeated.plan,delta.plan),"repeat changed member identities/state")
	for prop in repeated.added: prop.free()
	var baseline := Grove.snapshot(_map)
	var baseline_pose := Grove.pose_version(_map)
	var baseline_prop := delta.added[0] as EmberVoxelProp; baseline_prop.position += Vector3(4,0,8)
	check(Grove.restore_snapshot(_map,_scene,baseline).is_empty(),"snapshot restore")
	check(Grove.pose_version(_map) == baseline_pose,"snapshot lost transform/membership")
	check(is_instance_valid(baseline_prop) and baseline_prop.get_parent() != null,"snapshot replaced existing member identity")
	var packed := PackedScene.new(); check(packed.pack(_scene) == OK and ResourceSaver.save(packed,_scene.scene_file_path) == OK,"scene save")
	var disk := (ResourceLoader.load(_scene.scene_file_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene).instantiate()
	root.add_child(disk); await process_frame
	check(Plan.same(Plan.read(disk.get_node("Map")),delta.plan),"fresh plan roundtrip")
	var check_job := Grove.new(); check(check_job.begin(source,disk.get_node("Map"),disk,Plan.read(disk.get_node("Map")),_catalog),"fresh job")
	while not check_job.finished: check_job.step()
	check(check_job.protected_members.is_empty(),"fresh scene falsely protects trees")
	disk.queue_free(); await process_frame
	var world := Editor.new(); root.add_child(world); world.scene = _scene
	var history := UndoRedo.new()
	world.sessions.configure(history,func() -> int:
		var saved_scene := PackedScene.new(); var code := saved_scene.pack(_scene)
		return ResourceSaver.save(saved_scene,_scene.scene_file_path) if code == OK else code)
	world.sessions.recovery_directory = ROOT.path_join("recovery")
	var draft := world.sessions.open_map(_map,_scene)
	var changed := delta.plan.working_copy() as Resource; changed.regions[0].parameters.seed += 1
	check(world.commit_terrain_plan(_map,changed).is_empty(),"changed recipe")
	var atomic := prepare(source,changed)
	var context := {"grove_prepared":atomic,"draft":draft,"plan_version":changed.data(),"version":draft.resource.working_copy(),"layout":Sessions.compact_layout(_map).positions}
	check(world.commit_grove(_map,context).is_empty(),"atomic grove apply")
	var applied: Resource = Plan.read(_map); var pose := Grove.pose_version(_map)
	history.undo(); check(Plan.same(Plan.read(_map),changed) and Grove.pose_version(_map) == baseline_pose,"atomic grove Undo")
	history.redo(); check(Plan.same(Plan.read(_map),applied) and Grove.pose_version(_map) == pose,"atomic grove Redo")
	check(not world.commit_grove(_map,context).is_empty(),"stale grove commit accepted")
	check(world.sessions.save_all(_scene),world.sessions.error)
	var member_id: String = applied.object_layers.grove[0].id
	var manual_pose := _map.get_node("Props").get_node(NodePath(member_id)) as EmberVoxelProp
	manual_pose.position += Vector3(3,0,1)
	check(world.sessions.dirty(draft),"manual tree movement not dirty")
	check(world.sessions.save_all(_scene),world.sessions.error)
	var manual_saved := Grove.pose_version(_map); manual_pose.position += Vector3(9,0,0)
	world.sessions.write_recovery()
	world.sessions.discard(_scene)
	check(Grove.pose_version(_map) == manual_saved,"Discard lost saved manual tree position")
	check(world.sessions.restore_recovery(_scene) == 1,world.sessions.error)
	check(Grove.pose_version(_map) != manual_saved,"recovery missed tree placement")
	world.sessions.discard(_scene)
	# Continue the protection scenario from its independent initial baseline.
	check(Grove.restore_snapshot(_map,_scene,baseline).is_empty(),"reset fixture baseline")
	_map.set_meta(Plan.META,delta.plan)
	world.queue_free(); await process_frame
	var prop := _map.get_node("Props").get_node(NodePath(delta.plan.object_layers.grove[0].id)) as EmberVoxelProp; var moved_position := prop.position+Vector3(20,0,10); prop.position = moved_position
	var deleted := _map.get_node("Props").get_node(NodePath(delta.plan.object_layers.grove[1].id)) as EmberVoxelProp; deleted.get_parent().remove_child(deleted)
	var moved: Resource = delta.plan.working_copy(); moved.regions[0].bounds = Rect2i(20,28,20,16)
	var update := prepare(source,moved)
	check(update.protected_members.size() == 2,"manual move/delete unprotected")
	var update_delta := attach(update)
	check(prop.position == moved_position and prop.get_parent() != null and deleted.get_parent() == null,"manual changes lost")
	var disabled: Resource = update_delta.plan.working_copy(); disabled.regions[0].enabled = false
	var off := attach(prepare(source,disabled))
	check(off.added.is_empty() and prop.get_parent() != null,"off deleted protected tree")
	var removed: Resource = off.plan.working_copy(); removed.regions.remove_at(0)
	var removal := attach(prepare(source,removed))
	check(removal.plan.object_layers.is_empty() and prop.get_parent() != null and not prop.has_meta(Plan.GROVE_MEMBER_META),"delete did not preserve/manualize edited tree")
	var malformed: Resource = input.working_copy(); malformed.regions[0].parameters.spacing_m = NAN
	check(not malformed.validation_errors().is_empty(),"NaN spacing accepted")
	var invalid: Resource = input.working_copy(); invalid.regions[0].parameters.model_ids = ["../bad"]
	check(not invalid.validation_errors().is_empty(),"invalid recipe ID accepted")
	var older: Resource = input.working_copy(); older.schema_version = 6
	check(not older.validation_errors().is_empty(),"grove allowed on v6")
	var road_v6: Resource = input.working_copy(); road_v6.regions.remove_at(0); road_v6.schema_version = 6
	check(Plan.from_data(road_v6.data()) != null,"v6 compatibility")
	var snapshot := Grove.snapshot(_map)
	var snap_root := snapshot.instantiate(); check(snap_root.get_child_count() == 0,"removed grove snapshots manual tree"); snap_root.free()
	check(Export.strip_authoring_plan(_scene),"export strip did not report change")
	check(not _map.has_meta(Plan.META) and prop.get_parent() != null,"export lost physical scene members")
	print("GROVE_PLAN ","PASS" if errors.is_empty() else "FAIL"," placements=",first.placements.size()," calc_ms=",first.elapsed_us/1000.0," worst_step_ms=",first.worst_step_us/1000.0," errors=",errors)
	# Detached history members are owned by this fixture, never user scenes.
	history.clear_history()
	history.free()
	for group in [delta.added,delta.removed,update_delta.removed,off.removed,removal.removed]:
		for node in group:
			if is_instance_valid(node) and node.get_parent() == null: node.free()
	if is_instance_valid(deleted): deleted.free()
	_scene.queue_free(); await process_frame; quit(0 if errors.is_empty() else 1)
