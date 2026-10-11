extends "res://tools/test_terrain_plan_lake.gd"
func river_plan() -> Resource:
	var plan := Plan.new(); plan.schema_version = Plan.VERSION
	var points := PackedVector2Array([Vector2(22,28),Vector2(18,20),Vector2(25,13),Vector2(32,7),Vector2(34,3)])
	plan.regions = [{"id":"lake","name":"Озеро","kind":"lake","enabled":true,"bounds":Rect2i(12,18,20,20),"parameters":{"water_m":5.0,"depth_m":2.0,"shore_m":3.0}},
		{"id":"river","name":"Река","kind":"river","enabled":true,"points_m":points,"bounds":Plan.Influence.river_bounds(points,Plan.Influence.RIVER_DEFAULTS,Vector2i(48,48)),"parameters":Plan.Influence.RIVER_DEFAULTS.duplicate()}]
	return plan
func reject(source: Resource,plan: Resource,message: String) -> void:
	var job := Job.new()
	if job.begin(source,plan):
		for i in 15000:
			job.step()
			if not job.error.is_empty() or job.finished: break
	check(not job.error.is_empty() and job.candidate == null,message)
func _run() -> void:
	var source := fixture(); var plan := river_plan(); var first := compose(source,plan)
	check(is_equal_approx(Plan.Influence.river_height(2.0-0.00001,6.0,2.0,Plan.Influence.RIVER_DEFAULTS),Plan.Influence.river_height(2.0,6.0,2.0,Plan.Influence.RIVER_DEFAULTS)),"inner/outer bank seam")
	if first.candidate == null: quit(1); return
	var layer: Dictionary = first._layers[1]
	check(layer.start_water_m == 5.0 and layer.end_water_m == 2.0 and layer.end_s > layer.start_s,"derived water levels")
	for offset in range(0,ceili(layer.curve.get_baked_length()*2)):
		var point: Vector2 = layer.curve.sample_baked(float(offset)*0.5)
		var cell := Vector2i(point*16.0); var index: int = source.column_index(cell.x,cell.y)
		var water: int = first.candidate.column_value("water_levels",index)
		check(water > first.candidate.column_value("heights",index),"gap on centreline "+str(point))
		if float(offset)*0.5 <= layer.start_s: check(water == 80,"slope began inside lake")
		elif float(offset)*0.5 >= layer.end_s: check(water == 32,"sea changed at join")
		else: check(water <= 80 and water >= 32,"slope level outside endpoints")
	var current := Vector2i(25*16,13*16); var flow: Vector2 = first.candidate.flow_at_cell(current.x,current.y)
	check(flow.y < -0.1 and flow.x > 0.1 and flow.length() <= 0.65,"curve direction/strength")
	check(source.flow_at_cell(current.x,current.y) == Vector2.ZERO and plan.patches.is_empty(),"source mutated")
	check(first.candidate.column_value("heights",source.column_index(44*16,30*16)) == 96,"outside footprint changed")
	var repeat := compose(first.candidate,first.output_plan,1300)
	check(repeat.candidate != null and repeat.candidate.same_terrain_data(first.candidate) and Plan.same(repeat.output_plan,first.output_plan),"river repeat accumulation")
	var fast := compose(source,plan,50000); check(fast.candidate != null and fast.candidate.same_terrain_data(first.candidate),"river budget changed result")
	var off: Resource = first.output_plan.working_copy(); off.regions[1].enabled = false
	var stopped := compose(first.candidate,off)
	var lake_only: Resource = plan.working_copy(); lake_only.regions.remove_at(1)
	var lake := compose(source,lake_only)
	check(stopped.candidate != null and stopped.candidate.same_terrain_data(lake.candidate),"river off did not restore lake/flow/terrain")
	var removed: Resource = first.output_plan.working_copy(); removed.regions.clear()
	check(compose(first.candidate,removed).candidate.same_terrain_data(source),"remove all did not restore source/empty flow")
	var moved: Resource = first.output_plan.working_copy()
	var points := PackedVector2Array([Vector2(22,28),Vector2(28,20),Vector2(37,13),Vector2(39,3)])
	moved.regions[1].points_m = points; moved.regions[1].bounds = Plan.Influence.river_bounds(points,moved.regions[1].parameters,Vector2i(48,48))
	var move := compose(first.candidate,moved)
	check(move.candidate != null and move.candidate.flow_at_cell(current.x,current.y) == Vector2.ZERO,"old flow not restored on move")
	check(move.candidate.column_value("water_levels",source.column_index(current.x,current.y)) == 0,"old channel water not restored")
	for channel in ["heights","water_levels","top_materials","side","flow"]:
		var manual: Resource = first.candidate.working_copy(); var key := current/384
		var part: Resource = manual.sections[key].working_copy(); var local: int = current.x%384+(current.y%384)*part.width
		if channel == "side": part.column_material_overrides[local] = {0:1}
		elif channel == "flow":
			part.water_flow[(current.x%384)/16+((current.y%384)/16)*(part.width/16)] = Vector2(0.1,0.2)
		else:
			var values: Variant = part.get(channel); values[local] = values[local]+4 if channel in ["heights","water_levels"] else 1; part.set(channel,values)
		manual.sections[key] = part
		var keep := compose(manual,moved)
		if keep.candidate == null: quit(1); return
		check(keep.protected_blocks.has(current/16),"protection missing "+channel)
		check(keep.candidate.column_value("heights",source.column_index(current.x,current.y)) == manual.column_value("heights",source.column_index(current.x,current.y)),"manual height erased "+channel)
		check(keep.candidate.flow_at_cell(current.x,current.y) == manual.flow_at_cell(current.x,current.y),"protected shared flow erased "+channel)
		check(compose(keep.candidate,keep.output_plan).candidate.same_terrain_data(keep.candidate),"protected repeat "+channel)
	var higher: Resource = first.output_plan.working_copy(); higher.regions[0].parameters.water_m = 6.0
	var changed := compose(first.candidate,higher); check(changed.candidate != null and changed._layers[1].start_water_m == 6.0,"river used stale applied lake")
	var invalid: Resource = plan.working_copy(); invalid.regions[1].points_m.reverse()
	reject(source,invalid,"uphill river accepted")
	invalid = plan.working_copy(); invalid.regions[1].points_m[0] = Vector2(10,28)
	reject(source,invalid,"dry endpoint accepted")
	invalid = plan.working_copy(); invalid.regions[1].parameters.depth_m = 2.0
	reject(source,invalid,"bed below base accepted")
	invalid = plan.working_copy(); invalid.regions[1].points_m[2] = Vector2(NAN,10)
	check(not invalid.validation_errors().is_empty(),"NaN path accepted")
	check(not Plan.Influence.river_path_error(PackedVector2Array([Vector2(10,10),Vector2(20,20),Vector2(10,20),Vector2(20,10)])).is_empty(),"self-crossing path accepted")
	invalid = first.output_plan.working_copy(); invalid.patches[0].before_flows[Vector2i.ZERO] = Vector2(NAN,0)
	check(not invalid.validation_errors().is_empty(),"corrupt original flow accepted")
	invalid = first.output_plan.working_copy(); invalid.patches[0].before_flows.erase(invalid.patches[0].before_flows.keys()[0])
	check(not invalid.validation_errors().is_empty(),"incomplete original flow accepted")
	var legacy: Resource = lake.output_plan.working_copy(); legacy.schema_version = 3
	for patch in legacy.patches: patch.erase("before_flows")
	var v3: Resource = Plan.from_data(legacy.data()); check(v3 != null,"v3 read")
	var upgrade: Resource = v3.working_copy(); upgrade.upgrade_local_layers()
	check(upgrade.patches[0].before_waters == v3.patches[0].before_waters and upgrade.patches[0].before_tops == v3.patches[0].before_tops,"v3 migration lost original lake")
	check(compose(lake.candidate,v3).candidate.same_terrain_data(lake.candidate),"v3 replay changed lake")
	var shifted: Resource = first.output_plan.translated(Vector2i(24,24))
	check(shifted.validation_errors(Vector2i(96,96)).is_empty() and shifted.regions[1].points_m[0] == Vector2(46,52),"river translation invalid")
	var roundtrip: Resource = Plan.from_data(first.output_plan.data()); check(Plan.same(roundtrip,first.output_plan),"plan serialization")
	var dock := VBoxContainer.new(); dock.size = Vector2(302,650); var theme := Theme.new(); theme.default_font_size = 20; dock.theme = theme; root.add_child(dock)
	var panel := LakePanel.new(); dock.add_child(panel); await process_frame
	panel.open_influence(plan.regions[1].bounds,plan.regions[1].parameters,"river")
	check(panel._river_grid.visible and not panel._lake_grid.visible and panel.parameters() == plan.regions[1].parameters,"river dock fields")
	panel.set_ready("Ready"); panel._river_fields.width_m.value = 5; check(panel.get_apply_button().disabled,"stale river Apply")
	for i in 5: await process_frame
	check(panel.get_combined_minimum_size().x <= 302 and dock.get_global_rect().encloses(panel.get_apply_button().get_global_rect()),"river dock overflow")
	dock.free()
	# River points and both flow versions must survive the actual session file
	# and recovery manifest, not only an in-memory Dictionary roundtrip.
	var folder := "user://ember-tests/river-%d" % Time.get_ticks_usec(); DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var terrain_path := folder.path_join("terrain.res"); var scene_path := folder.path_join("map.tscn")
	check(ResourceSaver.save(source,terrain_path) == OK,"river fixture save")
	var scene := Node3D.new(); scene.scene_file_path = scene_path; root.add_child(scene)
	var map := EmberMapLoader.new(); map.name = "Map"; map.hydrate_legacy_regions = false; map.authored_size_blocks = Vector2i(48,48)
	map.compact_terrain = ResourceLoader.load(terrain_path,"",ResourceLoader.CACHE_MODE_IGNORE); scene.add_child(map); map.owner = scene; map.set_meta(Plan.META,plan)
	var editor := Editor.new(); root.add_child(editor); editor.scene = scene; var history := UndoRedo.new()
	editor.sessions.configure(history,func() -> int:
		var packed := PackedScene.new(); var error := packed.pack(scene); return ResourceSaver.save(packed,scene_path) if error == OK else error)
	editor.sessions.recovery_directory = folder.path_join("recovery")
	var draft := editor.sessions.open_map(map,scene)
	var context := {"draft":draft,"version":draft.resource.working_copy(),"candidate":first.candidate,"output_plan":first.output_plan,"plan_version":plan.data(),"layout":Sessions.compact_layout(map).positions}
	check(editor.commit_terrain_composition(map,context).is_empty(),"river commit")
	history.undo(); check(draft.resource.same_terrain_data(source) and Plan.read(map).patches.is_empty(),"atomic river Undo")
	history.redo(); check(draft.resource == first.candidate and Plan.same(Plan.read(map),first.output_plan),"atomic river Redo")
	check(not editor.commit_terrain_composition(map,context).is_empty(),"stale river Apply")
	check(editor.sessions.save_all(scene),editor.sessions.error)
	var reopened := (ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene).instantiate()
	check(Plan.same(Plan.read(reopened.get_node("Map")),first.output_plan) and reopened.get_node("Map").compact_terrain.same_terrain_data(first.candidate),"river fresh Save/Reopen")
	reopened.free(); check(editor.commit_terrain_plan(map,moved).is_empty(),"move river recipe")
	context = {"draft":draft,"version":draft.resource.working_copy(),"candidate":move.candidate,"output_plan":move.output_plan,"plan_version":moved.data(),"layout":Sessions.compact_layout(map).positions}
	check(editor.commit_terrain_composition(map,context).is_empty(),"move river commit")
	editor.sessions.write_recovery(); editor.sessions.discard(scene)
	check(draft.resource.same_terrain_data(first.candidate) and Plan.same(Plan.read(map),first.output_plan),"river Discard")
	check(editor.sessions.restore_recovery(scene) == 1 and draft.resource.same_terrain_data(move.candidate) and Plan.same(Plan.read(map),move.output_plan),"river recovery points/flow/provenance")
	history.clear_history(); editor.sessions.release(); editor.free(); history.free(); scene.free()
	print("RIVER_PLAN ","PASS" if errors.is_empty() else errors," cpu_ms=",first.elapsed_us/1000.0," repeat_ms=",repeat.elapsed_us/1000.0," worst_step_ms=",first.worst_step_us/1000.0," tiles=",first.changed_tiles.size())
	quit(0 if errors.is_empty() else 1)
