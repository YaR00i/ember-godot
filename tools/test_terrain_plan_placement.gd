extends "res://tools/test_terrain_plan_grove.gd"
const PlacementMath = preload("res://addons/ember_import/ember_voxel_placement_math.gd")
var _manual_tested := false

func plan() -> Resource:
	var result := super.plan()
	result.regions[0].kind = "placement"; result.regions[0].parameters.clearance_m = 0.5
	return result

func make_tree(id: String, color: Color) -> PackedScene:
	var original := super.make_tree(id,color)
	var prop := original.instantiate()
	if id.ends_with("_a"):
		prop.get_node("Mesh").mesh.size = Vector3(48,32,48)
		prop.get_node("Collision/Shape").shape.size = Vector3(48,32,48)
	var packed := PackedScene.new(); check(packed.pack(prop) == OK,"pack mixed object"); prop.free()
	var path := ROOT.path_join(id+".tscn"); check(ResourceSaver.save(packed,path) == OK,"save mixed object")
	return ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene

func prepare(source: Resource, input: Resource, budget := 4000) -> RefCounted:
	var job := super.prepare(source,input,budget)
	if not _manual_tested and not job.placements.is_empty():
		_manual_tested = true
		var manual := EmberVoxelProp.new(); manual.name = "ManualWide"; manual.placement_id = "manual_wide"; manual.model_id = "handmade_obstacle"
		var visual := MeshInstance3D.new(); visual.name = "Mesh"; visual.mesh = BoxMesh.new(); visual.mesh.size = Vector3(96,32,64); visual.position.y = 16
		manual.add_child(visual); manual.position = job.placements[0].transform.origin; _map.get_node("Props").add_child(manual); manual.owner = _scene; visual.owner = _scene
		var probe := Grove.new(); check(probe.begin(source,_map,_scene,input,_catalog),probe.error)
		while not probe.finished: probe.step(budget)
		var obstacle := PlacementMath.footprint(visual.transform*visual.mesh.get_aabb(),manual.transform)
		for spec in probe.placements:
			var footprint := PlacementMath.footprint(probe._template_bounds[spec.model_id],spec.transform)
			check(footprint.point.distance_to(obstacle.point) >= footprint.radius+obstacle.radius+0.5,"manual voxel object size ignored")
		visual.mesh.size.x += 16; check(probe.stale(),"manual mesh edit did not invalidate preview")
		manual.get_parent().remove_child(manual); manual.free()
	for i in job.placements.size():
		var first: Dictionary = job.placements[i]
		var a: Dictionary = PlacementMath.footprint(job._template_bounds[first.model_id],first.transform)
		for j in i:
			var second: Dictionary = job.placements[j]
			var b: Dictionary = PlacementMath.footprint(job._template_bounds[second.model_id],second.transform)
			check(a.point.distance_to(b.point)+0.00001 >= a.radius+b.radius+0.5,"mixed object footprints overlap")
	return job

func _run() -> void:
	var index := Grove.new(); var entries: Array[Dictionary] = []
	var edited := EmberVoxelProp.new(); edited.model_id = "edited_model"
	var edited_mesh := MeshInstance3D.new(); edited_mesh.name = "Mesh"; edited_mesh.mesh = BoxMesh.new(); edited_mesh.mesh.size = Vector3(64,16,64); edited.add_child(edited_mesh)
	index._base_bounds.edited_model = AABB(Vector3.ZERO,Vector3.ONE)
	check(index._bounds(edited).size.x == 64,"local mesh override kept source footprint")
	edited.free()
	for i in 32:
		var entry := {"point":Vector2(i-16,(i%7)-3)*3.5,"radius":0.2+i*0.1,"spacing":2.0,"clearance":0.5}
		entries.append(entry); index._add_neighbor(entry)
	var large := {"point":Vector2(-7,-8),"radius":70.0,"spacing":0.0,"clearance":0.5}; entries.append(large); index._add_neighbor(large)
	for x in range(-40,41,8):
		var point := Vector2(x,-2); var found: Array[Dictionary] = index._neighbors(point,6)
		for entry in entries:
			if point.distance_to(entry.point) < entry.radius+6: check(entry in found,"spatial index misses neighbor")
	var size := Vector3i(16,16,16); var voxels := PackedByteArray(); voxels.resize(4096)
	voxels[8+8*16] = 1; voxels[15+15*16+15*256] = 1
	var bounds := PlacementMath.base_voxel_bounds(size,16,voxels)
	check(bounds.size.x == 1 and bounds.size.z == 1,"crown incorrectly occupies ground footprint")
	check(PlacementMath.footprint(AABB(Vector3(-16,0,-16),Vector3(32,32,32)),Transform3D.IDENTITY).radius > 1.4,"footprint diagonal lost")
	var old := Plan.new(); old.schema_version = 7
	old.regions = [{"id":"old","name":"Старая роща","kind":"grove","enabled":true,"bounds":Rect2i(8,8,12,12),"parameters":Plan.Influence.GROVE_DEFAULTS.duplicate(true)}]
	check(Plan.from_data(old.data()).data() == old.data(),"v7 changed on read")
	var values := Plan.Influence.PLACEMENT_DEFAULTS.duplicate(true); values.model_ids = PackedStringArray(["handmade_stump"])
	check(Plan.Influence.parameter_error(values,"placement").is_empty(),"handmade model ID rejected")
	values.clearance_m = NAN; check(not Plan.Influence.parameter_error(values,"placement").is_empty(),"NaN clearance accepted")
	var panel := LakePanel.new(); root.add_child(panel)
	var choices: Array[Dictionary] = [{"id":"vox_a","title":"Дерево","role":"tree"},{"id":"vox_b","title":"Камень","role":"rock"},{"id":"handmade_stump","title":"Ручной пень","role":"other"}]
	values = Plan.Influence.PLACEMENT_DEFAULTS.duplicate(true); values.model_ids = PackedStringArray(["vox_a","vox_b"])
	panel.open_placement(Rect2i(0,0,24,24),values,choices)
	panel.size = Vector2(302,560); await process_frame
	check(panel.get_combined_minimum_size().x <= 302,"placement dock too wide")
	panel._source_filter.select(3); panel._filter_sources()
	check(panel._grove_choice_ids == PackedStringArray(["vox_b"]) and panel.parameters().model_ids == values.model_ids,"filter lost mixed sources")
	panel._source_search.text = "missing"
	panel._filter_sources()
	check(panel._grove_choice_ids.is_empty() and panel.parameters().model_ids == values.model_ids,"search erased hidden selections")
	panel._source_search.text = ""; panel._source_filter.select(0); panel._filter_sources()
	panel._grove_choices.select(2,false)
	check(panel.parameters().model_ids.has("handmade_stump"),"handmade source selection missing")
	panel.set_ready("Готово"); panel._grove_fields.clearance_m.value = 1
	check(panel.get_apply_button().disabled,"clearance changed without stale preview")
	panel._source_clear.pressed.emit(); check(panel.parameters().model_ids.is_empty(),"clear mixed set failed")
	panel.free()
	print("PLACEMENT_UI ","PASS" if errors.is_empty() else "FAIL"," sources/filters/mixed selection/clearance/legacy")
	await super._run()
